unit dpcc.Core.Lsp.ServerRedirect;

// Betriebsart Server (Stufe 2 von dpcc.LspServer.exe): die reine Entscheidung, ob ein Start von DelphiLSP.exe auf
// dpcc.LspServer.exe umgeleitet wird, und wo die EXE liegt. Ohne VCL, ohne Registry, ohne Dateizugriff (die Prüfung,
// ob eine Datei da ist, kommt als Funktion herein), damit alles ohne IDE testbar ist. Den Hook auf
// kernel32!CreateProcessW im Modul IDELSP290.bpl/IDELSP370.bpl baut dpcc.IDE.Foundation.LspRedirect.
// Gemessen (Delphi 12 und 13, 32-Bit-IDE): Die IDE setzt lpApplicationName (voller Pfad) UND die Kommandozeile
// "<bin>\DelphiLsp.exe" bzw. "<bin>\DelphiLSP.exe" (Schreibweise je Version verschieden, daher ohne Groß-/Klein-
// schreibung). Umgeleitet werden beide: Anwendung = voller Pfad der EXE, Kommandozeile = "<EXE>" plus die
// Originalparameter (die EXE verträgt sie). Flags, Handles und StartupInfo bleiben, wie die IDE sie setzt.
// Ort der EXE, relativ zum geladenen Plugin (Candidates), die 64-Bit-EXE zuerst, wenn Windows 64 Bit ist:
//   - Setup: Plugin unter {app}\bpl\d12|d13, EXE unter {app}\server\win64 bzw. {app}\server\win32;
//   - Entwicklungsbaum: Plugin unter Output\Win32\<Konfiguration>\Bpl, EXE unter Output\Win64\<Konfiguration>\Bin,
//     ersatzweise Output\Win64\Debug\Bin bzw. Release\Bin, dann dieselben Orte unter Win32;
//   - zuletzt neben dem Plugin (aus dem ZIP dorthin entpackt).

interface

uses
  System.SysUtils,
  dpcc.Core.Settings.OperatingMode;

type
  /// <summary>Was die IDE an CreateProcessW übergibt, und der Stand von dpcc.</summary>
  TDpccLspRedirectInput = record
    /// <summary>lpApplicationName; '' = nil.</summary>
    ApplicationName: string;
    /// <summary>lpCommandLine; '' = nil.</summary>
    CommandLine: string;
    /// <summary>Betriebsart dieser Delphi-Version, frisch gelesen.</summary>
    Mode: TDpccOperatingMode;
    /// <summary>Voller Pfad von dpcc.LspServer.exe; '' = nicht gefunden.</summary>
    ServerExe: string;
  end;

  /// <summary>Ergebnis: umleiten ja/nein, neue Anwendung und Kommandozeile, Grund fürs Protokoll.</summary>
  TDpccLspRedirectDecision = record
    /// <summary>Der Aufruf startet DelphiLSP.exe.</summary>
    IsDelphiLsp: Boolean;
    Redirect: Boolean;
    /// <summary>Neue lpApplicationName; '' = nil (wenn die IDE keine angegeben hatte).</summary>
    ApplicationName: string;
    /// <summary>Neue lpCommandLine.</summary>
    CommandLine: string;
    /// <summary>Kurzer Grund fürs Protokoll (nie übersetzt).</summary>
    Reason: string;
  end;

  TDpccLspRedirect = class
  public const
    cDelphiLspExe = 'DelphiLSP.exe';
    cServerExe = 'dpcc.LspServer.exe';
  public
    /// <summary>Zerlegt eine Kommandozeile in Programm (ohne Anführungszeichen) und Rest (ohne führenden Leerraum).
    /// False bei leerer Zeile.</summary>
    class function SplitCommandLine(const ACommandLine: string; out AProgram, ARest: string): Boolean; static;
    /// <summary>Endet APath auf DelphiLSP.exe (mit oder ohne Ordner, ohne Groß-/Kleinschreibung)?</summary>
    class function IsDelphiLsp(const APath: string): Boolean; static;
    /// <summary>Die Entscheidung (siehe Kopf der Unit). AExists prüft, ob die EXE da ist; nil = als vorhanden.
    /// </summary>
    class function Decide(const AInput: TDpccLspRedirectInput;
      const AExists: TFunc<string, Boolean>): TDpccLspRedirectDecision; static;
    /// <summary>Mögliche Orte der EXE zu APluginFile (voller Pfad des geladenen Plugins), in der Reihenfolge der
    /// Suche, ohne Doppel.</summary>
    class function Candidates(const APluginFile: string; AIs64BitWindows: Boolean): TArray<string>; static;
    /// <summary>Erster Ort aus Candidates, den AExists bestätigt; '' ohne.</summary>
    class function Locate(const APluginFile: string; AIs64BitWindows: Boolean;
      const AExists: TFunc<string, Boolean>): string; static;
  end;

implementation

class function TDpccLspRedirect.SplitCommandLine(const ACommandLine: string; out AProgram, ARest: string): Boolean;
var
  mLine: string;
  mEnd: Integer;
begin
  AProgram := '';
  ARest := '';
  mLine := TrimLeft(ACommandLine);
  if mLine = '' then
  begin
    Exit(False);
  end;
  if mLine[1] = '"' then
  begin
    mEnd := Pos('"', mLine, 2);
    if mEnd = 0 then
    begin
      // Ohne schließendes Anführungszeichen: der Rest ist das Programm.
      AProgram := Copy(mLine, 2, MaxInt);
    end
    else
    begin
      AProgram := Copy(mLine, 2, mEnd - 2);
      ARest := Trim(Copy(mLine, mEnd + 1, MaxInt));
    end;
  end
  else
  begin
    mEnd := Pos(' ', mLine);
    if mEnd = 0 then
    begin
      AProgram := mLine;
    end
    else
    begin
      AProgram := Copy(mLine, 1, mEnd - 1);
      ARest := Trim(Copy(mLine, mEnd + 1, MaxInt));
    end;
  end;
  Result := AProgram <> '';
end;

class function TDpccLspRedirect.IsDelphiLsp(const APath: string): Boolean;
var
  mName: string;
begin
  // Nur der Dateiname zählt; ein Ordner namens DelphiLSP.exe\… wäre kein Treffer.
  mName := Trim(APath);
  mName := Copy(mName, LastDelimiter('\/:', mName) + 1, MaxInt);
  Result := SameText(mName, cDelphiLspExe);
end;

class function TDpccLspRedirect.Decide(const AInput: TDpccLspRedirectInput;
  const AExists: TFunc<string, Boolean>): TDpccLspRedirectDecision;
var
  mProgram, mRest: string;
  mHasLine: Boolean;
begin
  Result := Default(TDpccLspRedirectDecision);
  Result.ApplicationName := AInput.ApplicationName;
  Result.CommandLine := AInput.CommandLine;
  mHasLine := SplitCommandLine(AInput.CommandLine, mProgram, mRest);
  Result.IsDelphiLsp := IsDelphiLsp(AInput.ApplicationName) or (mHasLine and IsDelphiLsp(mProgram));
  if not Result.IsDelphiLsp then
  begin
    Result.Reason := 'anderes Programm';
    Exit;
  end;
  if AInput.Mode <> TDpccOperatingMode.Server then
  begin
    Result.Reason := 'Betriebsart ' + TDpccOperatingModes.LogName(AInput.Mode);
    Exit;
  end;
  if Trim(AInput.ServerExe) = '' then
  begin
    Result.Reason := cServerExe + ' nicht gefunden';
    Exit;
  end;
  if Assigned(AExists) and not AExists(AInput.ServerExe) then
  begin
    Result.Reason := cServerExe + ' fehlt: ' + AInput.ServerExe;
    Exit;
  end;
  // Programm durch die EXE ersetzen, Originalparameter hinten anhängen (die IDE übergibt bisher keine).
  Result.CommandLine := '"' + AInput.ServerExe + '"';
  if mHasLine and (mRest <> '') then
  begin
    Result.CommandLine := Result.CommandLine + ' ' + mRest;
  end;
  // lpApplicationName nur ersetzen, wenn die IDE eine gesetzt hatte; sonst sucht Windows nach der Kommandozeile.
  if AInput.ApplicationName <> '' then
  begin
    Result.ApplicationName := AInput.ServerExe;
  end;
  Result.Redirect := True;
  Result.Reason := 'umgeleitet';
end;

procedure AddPath(var AList: TArray<string>; const APath: string);
var
  mKnown: string;
begin
  if APath = '' then
  begin
    Exit;
  end;
  for mKnown in AList do
  begin
    if SameText(mKnown, APath) then
    begin
      Exit;
    end;
  end;
  AList := AList + [APath];
end;

class function TDpccLspRedirect.Candidates(const APluginFile: string; AIs64BitWindows: Boolean): TArray<string>;
var
  mPluginDir, mParent, mGrand, mConfig, mPlatformDir, mOutput, mApp: string;
  mDevLayout, mSetupLayout: Boolean;
  mBitness: TArray<string>;
  mBits: string;
  mConfigs: TArray<string>;
  mItem: string;
begin
  Result := nil;
  mPluginDir := ExcludeTrailingPathDelimiter(ExtractFileDir(Trim(APluginFile)));
  if mPluginDir = '' then
  begin
    Exit;
  end;
  mParent := ExtractFileDir(mPluginDir);
  mGrand := ExtractFileDir(mParent);
  // Entwicklungsbaum: …\Output\Win32\<Konfiguration>\Bpl\dpcc.Plugin370.bpl.
  mConfig := ExtractFileName(mParent);
  mPlatformDir := ExtractFileName(mGrand);
  mOutput := ExtractFileDir(mGrand);
  mDevLayout := SameText(ExtractFileName(mPluginDir), 'Bpl') and SameText(mPlatformDir, 'Win32') and
    (mConfig <> '') and (mOutput <> '');
  // Setup: {app}\bpl\d13\dpcc.Plugin370.bpl.
  mApp := mGrand;
  mSetupLayout := SameText(ExtractFileName(mParent), 'bpl') and (mApp <> '');
  if AIs64BitWindows then
  begin
    mBitness := ['64', '32'];
  end
  else
  begin
    mBitness := ['32'];
  end;
  mConfigs := [mConfig, 'Debug', 'Release'];
  for mBits in mBitness do
  begin
    if mSetupLayout then
    begin
      AddPath(Result, mApp + '\server\win' + mBits + '\' + cServerExe);
    end;
    if mDevLayout then
    begin
      for mItem in mConfigs do
      begin
        if mItem <> '' then
        begin
          AddPath(Result, mOutput + '\Win' + mBits + '\' + mItem + '\Bin\' + cServerExe);
        end;
      end;
    end;
  end;
  // Zuletzt neben dem Plugin (aus dem ZIP dorthin gelegt); welche Bitbreite, entscheidet die Datei selbst.
  AddPath(Result, mPluginDir + '\' + cServerExe);
end;

class function TDpccLspRedirect.Locate(const APluginFile: string; AIs64BitWindows: Boolean;
  const AExists: TFunc<string, Boolean>): string;
var
  mPath: string;
begin
  Result := '';
  if not Assigned(AExists) then
  begin
    Exit;
  end;
  for mPath in Candidates(APluginFile, AIs64BitWindows) do
  begin
    if AExists(mPath) then
    begin
      Exit(mPath);
    end;
  end;
end;

end.
