unit dpcc.Core.Diagnostics.ImportPatch;

// Einträge der Importtabelle (IAT) eines geladenen Moduls finden, umbiegen und zurücksetzen, ohne VCL. Grundlage des
// Hooks der Betriebsart Server (dpcc.IDE.Foundation.LspRedirect: kernel32!CreateProcessW in IDELSP290/370.bpl);
// getestet an einem ungefährlichen Ziel im Testprogramm selbst.
// Gesucht wird ein Eintrag über den Namen in der Import-Lookup-Tabelle (OriginalFirstThunk) der genannten DLL;
// fehlt die Lookup-Tabelle oder heißt die DLL anders (API-Set), zählt ersatzweise jeder Eintrag, dessen Wert die
// Adresse der Funktion ist (GetProcAddress). Umbiegen und Zurücksetzen tauschen den Zeiger atomar
// (InterlockedExchangePointer) mit VirtualProtect davor und danach. Zurückgesetzt wird nur ein Eintrag, der noch auf
// das eigene Ziel zeigt; hat ihn jemand anders seither umgebogen, bleibt er. Keine Ausnahme verlässt diese Unit.

interface

uses
  Winapi.Windows;

type
  TDpccImportPatch = class
  public
    /// <summary>Alle Einträge für ADllName!AFunction in der Importtabelle von AModule (ohne Doppel); leer, wenn das
    /// Modul die Funktion nicht importiert oder kein gültiges PE-Abbild ist.</summary>
    class function FindSlots(AModule: HMODULE; const ADllName, AFunction: string): TArray<PPointer>; static;
    /// <summary>Eintrag ASlot auf ANew setzen; AOld = Wert davor. False, wenn der Schutz nicht änderbar war.
    /// </summary>
    class function Patch(ASlot: PPointer; ANew: Pointer; out AOld: Pointer): Boolean; static;
    /// <summary>Eintrag ASlot auf AOriginal zurück, aber nur, wenn er noch AExpected enthält. True, wenn
    /// zurückgesetzt.</summary>
    class function Restore(ASlot: PPointer; AExpected, AOriginal: Pointer): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

type
  TImportDescriptor = packed record
    OriginalFirstThunk, TimeDateStamp, ForwarderChain, Name, FirstThunk: DWORD;
  end;
  PImportDescriptor = ^TImportDescriptor;

/// <summary>Gleicher DLL-Name, auch ohne Endung ("kernel32" = "KERNEL32.DLL").</summary>
function SameDll(const AName, AWanted: string): Boolean;
begin
  Result := SameText(AName, AWanted) or SameText(ChangeFileExt(AName, ''), ChangeFileExt(AWanted, ''));
end;

procedure AddSlot(var AList: TArray<PPointer>; ASlot: PPointer);
var
  mKnown: PPointer;
begin
  for mKnown in AList do
  begin
    if mKnown = ASlot then
    begin
      Exit;
    end;
  end;
  AList := AList + [ASlot];
end;

class function TDpccImportPatch.FindSlots(AModule: HMODULE; const ADllName, AFunction: string): TArray<PPointer>;
const
  cOrdinalFlag = NativeUInt(1) shl (SizeOf(NativeUInt) * 8 - 1);
var
  mDos: PImageDosHeader;
  mNt: PImageNtHeaders;
  mDir: TImageDataDirectory;
  mDesc: PImportDescriptor;
  mThunk, mLookup: PNativeUInt;
  mDll: string;
  mTarget: Pointer;
  mTargetModule: HMODULE;
  mByName: Boolean;
begin
  Result := nil;
  if AModule = 0 then
  begin
    Exit;
  end;
  try
    mTarget := nil;
    mTargetModule := GetModuleHandle(PChar(ADllName));
    if mTargetModule <> 0 then
    begin
      mTarget := GetProcAddress(mTargetModule, PChar(AFunction));
    end;
    mDos := PImageDosHeader(AModule);
    if mDos.e_magic <> IMAGE_DOS_SIGNATURE then
    begin
      Exit;
    end;
    mNt := PImageNtHeaders(NativeUInt(AModule) + NativeUInt(mDos._lfanew));
    if mNt.Signature <> IMAGE_NT_SIGNATURE then
    begin
      Exit;
    end;
    mDir := mNt.OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (mDir.VirtualAddress = 0) or (mDir.Size = 0) then
    begin
      Exit;
    end;
    mDesc := PImportDescriptor(NativeUInt(AModule) + mDir.VirtualAddress);
    while (mDesc.Name <> 0) or (mDesc.FirstThunk <> 0) do
    begin
      if (mDesc.Name <> 0) and (mDesc.FirstThunk <> 0) then
      begin
        mDll := string(AnsiString(PAnsiChar(NativeUInt(AModule) + mDesc.Name)));
        mByName := SameDll(mDll, ADllName) and (mDesc.OriginalFirstThunk <> 0);
        mThunk := PNativeUInt(NativeUInt(AModule) + mDesc.FirstThunk);
        mLookup := nil;
        if mByName then
        begin
          mLookup := PNativeUInt(NativeUInt(AModule) + mDesc.OriginalFirstThunk);
        end;
        while mThunk^ <> 0 do
        begin
          if (mLookup <> nil) and ((mLookup^ and cOrdinalFlag) = 0) and
            (string(AnsiString(PAnsiChar(NativeUInt(AModule) + mLookup^ + 2))) = AFunction) then
          begin
            AddSlot(Result, PPointer(mThunk));
          end
          else if (mTarget <> nil) and (Pointer(mThunk^) = mTarget) then
          begin
            // Ohne Lookup-Tabelle oder unter anderem DLL-Namen: derselbe aufgelöste Zeiger.
            AddSlot(Result, PPointer(mThunk));
          end;
          Inc(mThunk);
          if mLookup <> nil then
          begin
            Inc(mLookup);
          end;
        end;
      end;
      Inc(mDesc);
    end;
  except
    // Ein unerwartetes Abbild darf die IDE nie stören: was bis dahin gefunden ist, gilt.
    on Exception do
      ;
  end;
end;

class function TDpccImportPatch.Patch(ASlot: PPointer; ANew: Pointer; out AOld: Pointer): Boolean;
var
  mProtect, mDummy: DWORD;
begin
  AOld := nil;
  Result := False;
  if ASlot = nil then
  begin
    Exit;
  end;
  try
    if not VirtualProtect(ASlot, SizeOf(Pointer), PAGE_READWRITE, mProtect) then
    begin
      Exit;
    end;
    try
      AOld := InterlockedExchangePointer(ASlot^, ANew);
      Result := True;
    finally
      VirtualProtect(ASlot, SizeOf(Pointer), mProtect, mDummy);
    end;
  except
    on Exception do
      Result := False;
  end;
end;

class function TDpccImportPatch.Restore(ASlot: PPointer; AExpected, AOriginal: Pointer): Boolean;
var
  mProtect, mDummy: DWORD;
begin
  Result := False;
  if ASlot = nil then
  begin
    Exit;
  end;
  try
    if ASlot^ <> AExpected then
    begin
      // Seither von jemand anderem umgebogen: nicht anfassen.
      Exit;
    end;
    if not VirtualProtect(ASlot, SizeOf(Pointer), PAGE_READWRITE, mProtect) then
    begin
      Exit;
    end;
    try
      // Nur tauschen, wenn noch unser Ziel drinsteht (zwischen Prüfung und Tausch).
      Result := InterlockedCompareExchangePointer(ASlot^, AOriginal, AExpected) = AExpected;
    finally
      VirtualProtect(ASlot, SizeOf(Pointer), mProtect, mDummy);
    end;
  except
    on Exception do
      Result := False;
  end;
end;

end.
