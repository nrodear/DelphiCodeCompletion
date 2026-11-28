unit dpcc.IDE.Foundation.LspRedirect;

// Betriebsart Server (Stufe 2 von dpcc.LspServer.exe): IAT-Hook auf kernel32!CreateProcessW im Modul IDELSP290.bpl
// (Delphi 12) bzw. IDELSP370.bpl (Delphi 13). Startet die IDE DelphiLSP.exe und gilt für diese Delphi-Version die
// Betriebsart Server, startet stattdessen dpcc.LspServer.exe. Klein und ohne VCL; nichts im Delphi-Programmordner,
// keine Administratorrechte.
//   - Einbau (Install) beim Anmelden des Plugins. IDELSP ist dann gemessen schon geladen; sonst holt ein kleiner
//     Hintergrund-Thread den Einbau nach (alle 500 ms, höchstens 5 Minuten, beim Abbau sofort beendet).
//   - Abbau (Uninstall) beim Abmelden und im finalization: die Einträge zurück, sofern sie noch auf den Hook zeigen,
//     dann höchstens cDrainMs warten, bis kein Aufruf mehr im Hook steckt. Danach ruft niemand mehr Code dieser BPL;
//     beim Entladen/Neuladen des Packages in der laufenden IDE startet danach wieder das Original.
//   - Bei jedem Aufruf die Betriebsart dieser Version frisch aus der Registry lesen (RegQueryValueEx, ohne
//     Hauptthread) und die reine Entscheidung TDpccLspRedirect.Decide fragen. Fehlt die EXE oder schlägt ihr Start
//     fehl: Originalaufruf, eine Zeile ins dpcc-Protokoll. Alles in try/except; im Zweifel geht der Originalaufruf
//     unverändert durch. Flags, Handles, Umgebung, Arbeitsordner und StartupInfo bleiben, wie die IDE sie setzt.
//   - Gegenseitiger Ausschluss: Nach einer Umleitung in dieser Sitzung (Redirected) startet der eingebaute Server
//     nicht mehr, bis Delphi neu startet (dpcc.IDE.CodeInsight.Manager.Session.RequestStart). Im Plugin-Betrieb
//     leitet der Hook nie um (Betriebsart <> Server), und die IDE ruft DelphiLSP dann ohnehin nicht.

interface

type
  TDpccLspRedirectHook = class
  public const
    /// <summary>Beim Abbau höchstens so lange warten, bis kein Aufruf mehr im Hook steckt.</summary>
    cDrainMs = 5000;
  public
    /// <summary>Hook einbauen (Hauptthread, beim Anmelden). AVersion: Version der IDE ("23.0", "37.0"), mit eigenem
    /// Registry-Profil davor das Profil (TDpccIdeSettings.IdeScope), für den Registry-Namen der Betriebsart.</summary>
    class procedure Install(const AVersion: string); static;
    /// <summary>Hook abbauen (Abmelden, finalization); mehrfach aufrufbar.</summary>
    class procedure Uninstall; static;
    /// <summary>Hat der Hook in dieser Sitzung schon einmal auf dpcc.LspServer.exe umgeleitet?</summary>
    class function Redirected: Boolean; static;
    /// <summary>Ist der Hook gerade eingebaut (mindestens ein Eintrag umgebogen)?</summary>
    class function Installed: Boolean; static;
    /// <summary>Ort von dpcc.LspServer.exe zum geladenen Plugin; '' ohne.</summary>
    class function ServerExe: string; static;
    /// <summary>Name des Moduls, in dem der Hook sitzt (IDELSP290.bpl bzw. IDELSP370.bpl).</summary>
    class function TargetModule: string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.ImportPatch,
  dpcc.Core.Lsp.ServerRedirect,
  dpcc.Core.Settings.OperatingMode;

const
  cTargetFunction = 'CreateProcessW';
  cKernel32 = 'kernel32.dll';
  cSettingsKey = 'Software\dpcc\IdePlugin';
{$IF CompilerVersion >= 37.0}
  cTargetModule = 'IDELSP370.bpl';
{$ELSE}
  cTargetModule = 'IDELSP290.bpl';
{$IFEND}

type
  TCreateProcessW = function(lpApplicationName: PWideChar; lpCommandLine: PWideChar;
    lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: BOOL;
    dwCreationFlags: DWORD; lpEnvironment: Pointer; lpCurrentDirectory: PWideChar;
    lpStartupInfo: PStartupInfoW; lpProcessInformation: PProcessInformation): BOOL; stdcall;

  /// <summary>Holt den Einbau nach, falls IDELSP beim Anmelden noch nicht geladen war.</summary>
  TInstallWaiter = class(TThread)
  protected
    procedure Execute; override;
  end;

var
  GLock: TRTLCriticalSection;
  GLockReady: Boolean;
  GVersion: string;
  GSlots: TArray<PPointer>;
  GOriginals: TArray<Pointer>;
  /// <summary>Weiterleitungsziel: der Wert des ersten umgebogenen Eintrags, sonst der Export von kernel32.</summary>
  GOriginal: TCreateProcessW;
  GWaiter: TInstallWaiter;
  GStop: THandle;
  /// <summary>Aufrufe, die gerade im Hook stecken (Abbau wartet darauf).</summary>
  GInFlight: Integer;
  GRedirects: Integer;
  GCalls: Integer;

procedure Log(const AText: string);
begin
  try
    TDpccGuard.Log('LSP-Umleitung: ' + AText);
  except
    // Das Protokoll darf den Start der IDE nie stören.
  end;
end;

function Is64BitWindows: Boolean;
{$IFDEF WIN64}
begin
  Result := True;
end;
{$ELSE}
var
  mWow: BOOL;
begin
  mWow := False;
  Result := IsWow64Process(GetCurrentProcess, mWow) and mWow;
end;
{$ENDIF}

function PluginFile: string;
var
  mBuffer: array[0..MAX_PATH] of Char;
  mLength: DWORD;
begin
  mLength := GetModuleFileName(HInstance, mBuffer, MAX_PATH);
  SetString(Result, mBuffer, mLength);
end;

function LocateServer: string;
begin
  Result := TDpccLspRedirect.Locate(PluginFile, Is64BitWindows,
    function(APath: string): Boolean
    begin
      Result := FileExists(APath);
    end);
end;

/// <summary>Betriebsart dieser Version frisch aus HKCU\Software\dpcc\IdePlugin; ohne eigenen Wert wie
/// TDpccPluginSettings: früheres Enabled (0 → Aus, sonst Plugin). Nur Server führt zur Umleitung.</summary>
function ReadMode: TDpccOperatingMode;
var
  mKey: HKEY;
  mType, mSize: DWORD;
  mBuffer: array[0..63] of Char;
  mDword: DWORD;
  mStored, mLegacyExists, mFromLegacy: Boolean;
  mText: string;
begin
  Result := TDpccOperatingModes.cDefault;
  if RegOpenKeyEx(HKEY_CURRENT_USER, cSettingsKey, 0, KEY_READ, mKey) <> ERROR_SUCCESS then
  begin
    Exit;
  end;
  try
    mStored := False;
    mText := '';
    mSize := SizeOf(mBuffer) - SizeOf(Char);
    FillChar(mBuffer, SizeOf(mBuffer), 0);
    if (RegQueryValueEx(mKey, PChar(TDpccOperatingModes.ValueName(GVersion)), nil, @mType, @mBuffer[0],
      @mSize) = ERROR_SUCCESS) and ((mType = REG_SZ) or (mType = REG_EXPAND_SZ)) then
    begin
      mStored := True;
      mText := PChar(@mBuffer[0]);
    end;
    mDword := 0;
    mSize := SizeOf(mDword);
    mLegacyExists := (RegQueryValueEx(mKey, TDpccOperatingModes.cLegacyName, nil, @mType, @mDword,
      @mSize) = ERROR_SUCCESS) and (mType = REG_DWORD);
    Result := TDpccOperatingModes.Resolve(mStored, mText, mLegacyExists, Integer(mDword), mFromLegacy);
  finally
    RegCloseKey(mKey);
  end;
end;

function HookedCreateProcessW(lpApplicationName: PWideChar; lpCommandLine: PWideChar;
  lpProcessAttributes, lpThreadAttributes: PSecurityAttributes; bInheritHandles: BOOL;
  dwCreationFlags: DWORD; lpEnvironment: Pointer; lpCurrentDirectory: PWideChar;
  lpStartupInfo: PStartupInfoW; lpProcessInformation: PProcessInformation): BOOL; stdcall;
var
  mInput: TDpccLspRedirectInput;
  mDecision: TDpccLspRedirectDecision;
  mApp, mCmd: string;
  mAppPtr: PWideChar;
  mError: DWORD;
  mCall: Integer;
begin
  InterlockedIncrement(GInFlight);
  try
    mDecision := Default(TDpccLspRedirectDecision);
    mCall := 0;
    try
      mCall := InterlockedIncrement(GCalls);
      mInput := Default(TDpccLspRedirectInput);
      if lpApplicationName <> nil then
      begin
        mInput.ApplicationName := lpApplicationName;
      end;
      if lpCommandLine <> nil then
      begin
        mInput.CommandLine := lpCommandLine;
      end;
      // Nur für DelphiLSP Registry und Dateien fragen; jeder andere Start der IDE geht ohne Umweg durch.
      if TDpccLspRedirect.IsDelphiLsp(mInput.ApplicationName) or
        (Pos(LowerCase(TDpccLspRedirect.cDelphiLspExe), LowerCase(mInput.CommandLine)) > 0) then
      begin
        mInput.Mode := ReadMode;
        if mInput.Mode = TDpccOperatingMode.Server then
        begin
          mInput.ServerExe := LocateServer;
        end;
        mDecision := TDpccLspRedirect.Decide(mInput,
          function(APath: string): Boolean
          begin
            Result := FileExists(APath);
          end);
        if mDecision.IsDelphiLsp and not mDecision.Redirect then
        begin
          Log(Format('#%d Start von DelphiLSP nicht umgeleitet (%s)', [mCall, mDecision.Reason]));
        end;
      end;
    except
      on E: Exception do
      begin
        mDecision.Redirect := False;
        Log(Format('#%d Ausnahme in der Entscheidung, Originalaufruf: %s', [mCall, E.ClassName]));
      end;
    end;

    if mDecision.Redirect then
    begin
      mApp := mDecision.ApplicationName;
      mCmd := mDecision.CommandLine;
      // CreateProcessW darf die Kommandozeile verändern: eigener, beschreibbarer Puffer.
      UniqueString(mCmd);
      mAppPtr := nil;
      if mApp <> '' then
      begin
        mAppPtr := PWideChar(mApp);
      end;
      Result := GOriginal(mAppPtr, PWideChar(mCmd), lpProcessAttributes, lpThreadAttributes, bInheritHandles,
        dwCreationFlags, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation);
      mError := GetLastError;
      if Result then
      begin
        InterlockedIncrement(GRedirects);
        try
          if lpProcessInformation <> nil then
          begin
            Log(Format('#%d DelphiLSP umgeleitet auf %s (PID %d)', [mCall, mApp,
              lpProcessInformation.dwProcessId]));
          end;
        except
          on Exception do
            ;
        end;
      end
      else
      begin
        Log(Format('#%d Start von %s fehlgeschlagen (Fehler %d), Originalaufruf', [mCall,
          TDpccLspRedirect.cServerExe, mError]));
        Result := GOriginal(lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes,
          bInheritHandles, dwCreationFlags, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation);
        mError := GetLastError;
      end;
      SetLastError(mError);
    end
    else
    begin
      Result := GOriginal(lpApplicationName, lpCommandLine, lpProcessAttributes, lpThreadAttributes,
        bInheritHandles, dwCreationFlags, lpEnvironment, lpCurrentDirectory, lpStartupInfo, lpProcessInformation);
    end;
  finally
    InterlockedDecrement(GInFlight);
  end;
end;

/// <summary>Einträge im geladenen IDELSP umbiegen; False, solange das Modul nicht geladen ist.</summary>
function TryInstall(const AWhen: string): Boolean;
var
  mModule: HMODULE;
  mSlot: PPointer;
  mOld: Pointer;
  mCount: Integer;
begin
  Result := False;
  try
    mModule := GetModuleHandle(cTargetModule);
    if mModule = 0 then
    begin
      Exit;
    end;
    Result := True;
    mCount := 0;
    EnterCriticalSection(GLock);
    try
      if not Assigned(GOriginal) then
      begin
        @GOriginal := GetProcAddress(GetModuleHandle(cKernel32), cTargetFunction);
      end;
      if not Assigned(GOriginal) then
      begin
        Log('CreateProcessW nicht gefunden, kein Hook');
        Exit;
      end;
      for mSlot in TDpccImportPatch.FindSlots(mModule, cKernel32, cTargetFunction) do
      begin
        if mSlot^ = @HookedCreateProcessW then
        begin
          Continue;
        end;
        // Ziel ist immer der Wert im Eintrag (falls schon jemand davor hängt, bleibt er in der Kette).
        if TDpccImportPatch.Patch(mSlot, @HookedCreateProcessW, mOld) then
        begin
          if mCount = 0 then
          begin
            @GOriginal := mOld;
          end;
          GSlots := GSlots + [mSlot];
          GOriginals := GOriginals + [mOld];
          Inc(mCount);
        end;
      end;
    finally
      LeaveCriticalSection(GLock);
    end;
    Log(Format('Hook %s (%s): %d Eintrag/Einträge in %s umgebogen; Betriebsart jetzt %s; EXE: %s', [AWhen,
      GVersion, mCount, cTargetModule, TDpccOperatingModes.LogName(ReadMode), LocateServer]));
  except
    on E: Exception do
    begin
      Log('Einbau fehlgeschlagen: ' + TDpccGuard.ErrorText(E));
      Result := True;
    end;
  end;
end;

{ TInstallWaiter }

procedure TInstallWaiter.Execute;
var
  mIndex: Integer;
begin
  try
    for mIndex := 1 to 600 do
    begin
      if WaitForSingleObject(GStop, 500) = WAIT_OBJECT_0 then
      begin
        Exit;
      end;
      if TryInstall(Format('nachgeholt nach %d ms', [mIndex * 500])) then
      begin
        Exit;
      end;
    end;
    Log(cTargetModule + ' nach 5 Minuten nicht geladen; keine Umleitung');
  except
    // Nie in die IDE durchschlagen.
    on Exception do
      ;
  end;
end;

{ TDpccLspRedirectHook }

class procedure TDpccLspRedirectHook.Install(const AVersion: string);
begin
  try
    if not GLockReady then
    begin
      InitializeCriticalSection(GLock);
      GLockReady := True;
    end;
    GVersion := AVersion;
    if Installed or (GWaiter <> nil) then
    begin
      Exit;
    end;
    if not TryInstall('beim Anmelden') then
    begin
      Log(cTargetModule + ' noch nicht geladen; Einbau wird nachgeholt');
      if GStop = 0 then
      begin
        GStop := CreateEvent(nil, True, False, nil);
      end;
      ResetEvent(GStop);
      GWaiter := TInstallWaiter.Create(False);
    end;
  except
    on E: Exception do
      Log('Einbau fehlgeschlagen: ' + TDpccGuard.ErrorText(E));
  end;
end;

class procedure TDpccLspRedirectHook.Uninstall;
var
  mIndex, mRestored: Integer;
  mStart: UInt64;
begin
  try
    if GWaiter <> nil then
    begin
      SetEvent(GStop);
      GWaiter.WaitFor;
      FreeAndNil(GWaiter);
    end;
    if not GLockReady then
    begin
      Exit;
    end;
    mRestored := 0;
    EnterCriticalSection(GLock);
    try
      for mIndex := 0 to High(GSlots) do
      begin
        if TDpccImportPatch.Restore(GSlots[mIndex], @HookedCreateProcessW, GOriginals[mIndex]) then
        begin
          Inc(mRestored);
        end;
      end;
      if Length(GSlots) > 0 then
      begin
        Log(Format('Hook abgebaut: %d von %d Einträgen zurückgesetzt; Umleitungen in dieser Sitzung: %d',
          [mRestored, Length(GSlots), GRedirects]));
      end;
      GSlots := nil;
      GOriginals := nil;
    finally
      LeaveCriticalSection(GLock);
    end;
    // Wer schon im Hook ist, läuft noch in dieser BPL: begrenzt warten.
    mStart := GetTickCount64;
    while (GInFlight > 0) and (GetTickCount64 - mStart < cDrainMs) do
    begin
      Sleep(10);
    end;
  except
    on Exception do
      ;
  end;
end;

class function TDpccLspRedirectHook.Redirected: Boolean;
begin
  Result := GRedirects > 0;
end;

class function TDpccLspRedirectHook.Installed: Boolean;
begin
  Result := Length(GSlots) > 0;
end;

class function TDpccLspRedirectHook.ServerExe: string;
begin
  try
    Result := LocateServer;
  except
    on Exception do
      Result := '';
  end;
end;

class function TDpccLspRedirectHook.TargetModule: string;
begin
  Result := cTargetModule;
end;

initialization

finalization
  // Sicherheitsnetz, falls das Abmelden nicht lief: Kein Eintrag zeigt nach dem Entladen in diese BPL.
  TDpccLspRedirectHook.Uninstall;
  if GStop <> 0 then
  begin
    CloseHandle(GStop);
    GStop := 0;
  end;
  if GLockReady then
  begin
    DeleteCriticalSection(GLock);
    GLockReady := False;
  end;

end.
