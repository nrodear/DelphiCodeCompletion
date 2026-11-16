unit dpcc.Common.Projects.PackageLocator;

// Findet ein Package aus requires und beantwortet, ob es eine Unit liefert
// (#46). Zuerst die Quelle <Name>.dpk in den bekannten Ordnern (Projekte der
// Gruppe, Suchpfade): Ihr contains ist die Antwort. Sonst das übersetzte
// <Name>.dcp in den Bibliothekspfaden.
// Vom .dcp bleiben nur Namen im Speicher (Speicher-Optimierung a2): Der Kopf der Datei (Format PKX0 für Win32,
// PKX1 für Win64) nennt nach dem BPL-Namen die requires und je enthaltener Unit Name und Namespace als
// nullterminierte Zeichenketten, abgeschlossen von ".<Package>". Diese Namen (und die requires) sind die Antwort;
// gelesen wird dafür nur der Anfang der Datei. Kennt dpcc das Format nicht oder fehlt der Abschluss, gilt wie früher
// jedes Wort der ganzen Datei als Name (Näherung ohne das DCP-Format). Früher hielt jeder Prozess die ganze .dcp
// (rtl.dcp 45,9 MB, fmx.dcp 25 MB) und durchsuchte sie je Unit.
// Ergebnisse bleiben je Package im Speicher; der Zugriff ist threadsicher. Die Namen der .dcp hält
// TPackageCompiledFiles einmal je Prozess für alle Locatoren.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Common.Projects.PackageReader;

type
  /// <summary>Liest eine Datei; False, wenn sie fehlt oder nicht lesbar ist.</summary>
  TPackageReadFile = reference to function(const AFileName: string; out AData: TBytes): Boolean;

  /// <summary>Was dpcc von einem übersetzten Package (.dcp) behält: Namen, keine Bytes.</summary>
  TPackageCompiledNames = record
    /// <summary>Großgeschrieben und sortiert: Units und Namespaces aus dem Kopf (FromHeader), sonst jedes Wort der
    /// Datei.</summary>
    Names: TArray<string>;
    /// <summary>requires aus dem Kopf; nil ohne Kopf.</summary>
    Requires: TArray<string>;
    /// <summary>Namen aus dem Kopf der Datei (PKX0/PKX1); False = Näherung über alle Wörter.</summary>
    FromHeader: Boolean;
    /// <summary>Kommt AUnitName als ganzer Name vor (ohne Groß-/Kleinschreibung)?</summary>
    function Contains(const AUnitName: string): Boolean;
    /// <summary>Geschätzter Speicher der Namen in Byte.</summary>
    function Bytes: Int64;
    /// <summary>Namen aus dem Kopf von AData; False, wenn das Format unbekannt ist oder der Abschluss
    /// ".&lt;APackage&gt;" in AData fehlt (etwa weil AData nur der Anfang der Datei ist).</summary>
    class function TryParseHeader(const AData: TBytes; const APackage: string;
      out ANames: TPackageCompiledNames): Boolean; static;
    /// <summary>Namen aus dem Kopf, sonst jedes Wort von AData (ganze Datei).</summary>
    class function Parse(const AData: TBytes; const APackage: string): TPackageCompiledNames; static;
  end;

  /// <summary>Namen der übersetzten Packages (.dcp) einmal je Prozess. Jeder Arbeitsbereich hat seinen
  /// TPackageLocator, und bei jedem Indexstart entsteht ein neuer; früher hielt jeder Eintrag die ganze .dcp (bei
  /// Fremdkomponenten oft zweistellige MB, rtl.dcp 45,9 MB). Ein Eintrag gilt, solange Zeitstempel und Größe der
  /// Datei gleich sind.</summary>
  TPackageCompiledFiles = record
  private type
    TEntry = record
      Stamp: TDateTime;
      Size: Int64;
      Names: TPackageCompiledNames;
    end;
  private class var
    FLock: TObject;
    FFiles: TDictionary<string, TEntry>;
  public const
    /// <summary>So viel liest Read zuerst; der Kopf großer .dcp (rtl, fmx) hat unter 32 KB.</summary>
    cHeadBytes = 1024 * 1024;
  public
    /// <summary>Namen von AFileName, geteilt; False, wenn die Datei fehlt oder nicht lesbar ist.</summary>
    class function Read(const AFileName: string; out ANames: TPackageCompiledNames): Boolean; static;
    /// <summary>Geschätzter Speicher der gehaltenen Namen in Byte (Selbstmessung, Diagnoselog).</summary>
    class function Bytes: Int64; static;
    /// <summary>Zahl der gemerkten Dateien.</summary>
    class function Count: Integer; static;
    class procedure Clear; static;
  end;

  /// <summary>Liest die Namen eines .dcp; False, wenn es fehlt oder nicht lesbar ist.</summary>
  TPackageReadCompiled = reference to function(const AFileName, APackage: string;
    out ANames: TPackageCompiledNames): Boolean;

  TPackageLocator = class
  private type
    TFound = record
      Known: Boolean;
      FileName: string;
      Source: TPackageSource;
      Compiled: TPackageCompiledNames;
    end;
  private
    FFolders: TArray<string>;
    FReadFile: TPackageReadFile;
    FReadCompiled: TPackageReadCompiled;
    FCache: TDictionary<string, TFound>;
    FLock: TObject;
    function Find(const APackage: string): TFound;
  public
    /// <summary>AFolders in Suchreihenfolge; Dateien vom Dateisystem, die Namen der .dcp geteilt über
    /// TPackageCompiledFiles.</summary>
    constructor Create(const AFolders: TArray<string>); overload;
    /// <summary>Alle Dateien über AReadFile (Tests); die Namen der .dcp liest jeder Locator selbst.</summary>
    constructor Create(const AFolders: TArray<string>; const AReadFile: TPackageReadFile); overload;
    destructor Destroy; override;
    /// <summary>True, wenn das Package gefunden wurde; AContains sagt dann, ob es AUnitName liefert.</summary>
    function Provides(const APackage, AUnitName: string; out AContains: Boolean): Boolean;
    /// <summary>Quelle &lt;APackage&gt;.dpk; False, wenn es keine gibt (auch, wenn nur ein .dcp da ist).</summary>
    function FindSource(const APackage: string; out AFileName: string; out ASource: TPackageSource): Boolean;
    /// <summary>Namen aus requires der Quelle &lt;APackage&gt;.dpk, ohne Quelle die aus dem Kopf des .dcp; leer,
    /// wenn beides fehlt.</summary>
    function Requires(const APackage: string): TArray<string>;
    /// <summary>Dateien aus contains mit in '…', vollständig zum Ordner von AFileName (der .dpk).</summary>
    class function ContainedFiles(const AFileName: string; const ASource: TPackageSource): TArray<string>; static;
    /// <summary>contains-Dateien der requires-Packages von ASource mit Quelltext, auch über deren requires;
    /// ohne Doppelte, in Suchreihenfolge.</summary>
    function RequiredFiles(const ASource: TPackageSource): TArray<string>;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Math,
  dpcc.Common.Documents.FileEncoding;

{ TPackageCompiledNames }

function IsNameByte(AByte: Byte): Boolean;
begin
  Result := (AByte in [Ord('A')..Ord('Z'), Ord('a')..Ord('z'), Ord('0')..Ord('9'), Ord('_'), Ord('.')]) or
    (AByte >= $80);
end;

/// <summary>Name aus dem Kopf: nur ASCII, beginnt mit Buchstabe oder "_" (Unit-, Namespace- und Package-Namen).
/// </summary>
function IsHeaderNameByte(AByte: Byte): Boolean;
begin
  Result := AByte in [Ord('A')..Ord('Z'), Ord('a')..Ord('z'), Ord('0')..Ord('9'), Ord('_'), Ord('.')];
end;

function IsHeaderNameStart(AByte: Byte): Boolean;
begin
  Result := AByte in [Ord('A')..Ord('Z'), Ord('a')..Ord('z'), Ord('_')];
end;

function ReadUInt32(const AData: TBytes; AOffset: Integer): Cardinal;
begin
  Result := Cardinal(AData[AOffset]) or (Cardinal(AData[AOffset + 1]) shl 8) or (Cardinal(AData[AOffset + 2]) shl 16) or
    (Cardinal(AData[AOffset + 3]) shl 24);
end;

/// <summary>Nullterminierte Zeichenkette ab APos; APos steht danach hinter der Null. False ohne Null bis zum Ende.
/// </summary>
function ReadCString(const AData: TBytes; var APos: Integer; out AText: string): Boolean;
var
  mEnd: Integer;
begin
  mEnd := APos;
  while (mEnd < Length(AData)) and (AData[mEnd] <> 0) do
  begin
    Inc(mEnd);
  end;
  Result := mEnd < Length(AData);
  if Result then
  begin
    AText := TEncoding.ANSI.GetString(AData, APos, mEnd - APos);
    APos := mEnd + 1;
  end;
end;

/// <summary>Stelle der Null vor ".&lt;APackage&gt;" + Null ab AFrom (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
function FindPackageEnd(const AData: TBytes; AFrom: Integer; const APackage: string): Integer;
var
  mMarker: TBytes;
  mStart, mOffset: Integer;
  mMatches: Boolean;
begin
  Result := -1;
  mMarker := TEncoding.ASCII.GetBytes(#0'.' + UpperCase(APackage) + #0);
  for mStart := Max(AFrom, 0) to Length(AData) - Length(mMarker) do
  begin
    mMatches := True;
    for mOffset := 0 to High(mMarker) do
    begin
      if (AData[mStart + mOffset] <> mMarker[mOffset]) and not ((AData[mStart + mOffset] in [Ord('a')..Ord('z')]) and
        (AData[mStart + mOffset] - 32 = mMarker[mOffset])) then
      begin
        mMatches := False;
        Break;
      end;
    end;
    if mMatches then
    begin
      Exit(mStart);
    end;
  end;
end;

/// <summary>Großgeschrieben, sortiert, ohne Doppelte.</summary>
function SortedNames(ANames: TList<string>): TArray<string>;
var
  mSet: TDictionary<string, Boolean>;
  mName: string;
begin
  mSet := TDictionary<string, Boolean>.Create;
  try
    for mName in ANames do
    begin
      mSet.AddOrSetValue(UpperCase(mName), True);
    end;
    Result := mSet.Keys.ToArray;
  finally
    mSet.Free;
  end;
  TArray.Sort<string>(Result);
end;

class function TPackageCompiledNames.TryParseHeader(const AData: TBytes; const APackage: string;
  out ANames: TPackageCompiledNames): Boolean;
var
  mRequiresRaw: Cardinal;
  mRequires, mPos, mEnd, mIndex, mStop: Integer;
  mText: string;
  mNames: TList<string>;
begin
  ANames := Default(TPackageCompiledNames);
  Result := False;
  // PKX0 (Win32): requires-Zahl bei 4, Namen ab 32; PKX1 (Win64): requires-Zahl bei 8, Namen ab 40.
  if (Length(AData) < 48) or (AData[0] <> Ord('P')) or (AData[1] <> Ord('K')) or (AData[2] <> Ord('X')) then
  begin
    Exit;
  end;
  case AData[3] of
    Ord('0'):
      begin
        mRequiresRaw := ReadUInt32(AData, 4);
        mPos := 32;
      end;
    Ord('1'):
      begin
        mRequiresRaw := ReadUInt32(AData, 8);
        mPos := 40;
      end;
  else
    Exit;
  end;
  if mRequiresRaw > 4096 then
  begin
    Exit;
  end;
  mRequires := Integer(mRequiresRaw);
  mNames := TList<string>.Create;
  try
    // BPL-Name, dann die requires.
    if not ReadCString(AData, mPos, mText) then
    begin
      Exit;
    end;
    for mIndex := 1 to mRequires do
    begin
      if not ReadCString(AData, mPos, mText) or (mText = '') then
      begin
        Exit;
      end;
      ANames.Requires := ANames.Requires + [mText];
      mNames.Add(mText);
    end;
    mEnd := FindPackageEnd(AData, mPos - 1, APackage);
    if mEnd < 0 then
    begin
      Exit;
    end;
    // Jede nullterminierte Zeichenkette aus Namenszeichen, vor der eine Null steht: Unit und Namespace je Eintrag.
    // Reste der Adressen dazwischen (drei Bytes vor einer Null) stören nicht: Keine Unit heißt so.
    mIndex := mPos;
    while mIndex <= mEnd do
    begin
      if IsHeaderNameStart(AData[mIndex]) and ((mIndex = 0) or (AData[mIndex - 1] = 0)) then
      begin
        mStop := mIndex;
        while (mStop < Length(AData)) and IsHeaderNameByte(AData[mStop]) do
        begin
          Inc(mStop);
        end;
        if (mStop < Length(AData)) and (AData[mStop] = 0) then
        begin
          mNames.Add(TEncoding.ASCII.GetString(AData, mIndex, mStop - mIndex));
        end;
        mIndex := mStop + 1;
      end
      else
      begin
        Inc(mIndex);
      end;
    end;
    ANames.Names := SortedNames(mNames);
    ANames.FromHeader := True;
    Result := True;
  finally
    mNames.Free;
  end;
end;

class function TPackageCompiledNames.Parse(const AData: TBytes; const APackage: string): TPackageCompiledNames;
var
  mNames: TList<string>;
  mIndex, mStop: Integer;
begin
  if TryParseHeader(AData, APackage, Result) then
  begin
    Exit;
  end;
  // Näherung wie vor a2: jedes Wort aus Namenszeichen, ganz und ohne Groß-/Kleinschreibung.
  Result := Default(TPackageCompiledNames);
  mNames := TList<string>.Create;
  try
    mIndex := 0;
    while mIndex < Length(AData) do
    begin
      if IsNameByte(AData[mIndex]) then
      begin
        mStop := mIndex;
        while (mStop < Length(AData)) and IsNameByte(AData[mStop]) do
        begin
          Inc(mStop);
        end;
        mNames.Add(TEncoding.ANSI.GetString(AData, mIndex, mStop - mIndex));
        mIndex := mStop;
      end
      else
      begin
        Inc(mIndex);
      end;
    end;
    Result.Names := SortedNames(mNames);
  finally
    mNames.Free;
  end;
end;

function TPackageCompiledNames.Contains(const AUnitName: string): Boolean;
var
  mFound: Integer;
begin
  Result := (AUnitName <> '') and TArray.BinarySearch<string>(Names, UpperCase(AUnitName), mFound);
end;

function TPackageCompiledNames.Bytes: Int64;
var
  mName: string;
begin
  // Je Name ein Zeiger im Feld und ein String (12 Byte Kopf, UTF-16, Endnull, Rundung des Speichermanagers).
  Result := 0;
  for mName in Names + Requires do
  begin
    Inc(Result, SizeOf(Pointer) + 16 + (Length(mName) + 1) * SizeOf(Char));
  end;
end;

{ TPackageCompiledFiles }

/// <summary>Namen aus der Datei: zuerst nur ihr Anfang, die ganze Datei nur ohne erkennbaren Kopf.</summary>
function ReadCompiledNames(const AFileName, APackage: string; out ANames: TPackageCompiledNames): Boolean;
var
  mStream: TFileStream;
  mHead: TBytes;
begin
  Result := False;
  try
    mStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(mHead, Integer(Min(mStream.Size, Int64(TPackageCompiledFiles.cHeadBytes))));
      if Length(mHead) > 0 then
      begin
        mStream.ReadBuffer(mHead[0], Length(mHead));
      end;
    finally
      mStream.Free;
    end;
    if not TPackageCompiledNames.TryParseHeader(mHead, APackage, ANames) then
    begin
      ANames := TPackageCompiledNames.Parse(TFile.ReadAllBytes(AFileName), APackage);
    end;
    Result := True;
  except
    // Gesperrte oder nicht lesbare Dateien zählen als fehlend.
    // lsp-ignore: catch-all-without-raise -- Cache nach Kräften; Fehler heißt nicht gefunden
    on Exception do
      ANames := Default(TPackageCompiledNames);
  end;
end;

class function TPackageCompiledFiles.Read(const AFileName: string; out ANames: TPackageCompiledNames): Boolean;
var
  mKey: string;
  mEntry: TEntry;
  mStamp: TDateTime;
  mSize: Int64;
begin
  ANames := Default(TPackageCompiledNames);
  if not TFile.Exists(AFileName) then
  begin
    Exit(False);
  end;
  try
    mStamp := TFile.GetLastWriteTime(AFileName);
    mSize := TFile.GetSize(AFileName);
  except
    // lsp-ignore: catch-all-without-raise -- Cache nach Kräften; Fehler heißt nicht gefunden
    on Exception do
      Exit(False);
  end;
  mKey := AnsiUpperCase(ExpandFileName(AFileName));
  TMonitor.Enter(FLock);
  try
    if FFiles.TryGetValue(mKey, mEntry) and (mEntry.Stamp = mStamp) and (mEntry.Size = mSize) then
    begin
      ANames := mEntry.Names;
      Exit(True);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  // Außerhalb der Sperre lesen; liest ein zweiter Thread dieselbe Datei gleichzeitig, gewinnt der letzte.
  if not ReadCompiledNames(AFileName, ChangeFileExt(ExtractFileName(AFileName), ''), ANames) then
  begin
    Exit(False);
  end;
  mEntry.Stamp := mStamp;
  mEntry.Size := mSize;
  mEntry.Names := ANames;
  TMonitor.Enter(FLock);
  try
    FFiles.AddOrSetValue(mKey, mEntry);
  finally
    TMonitor.Exit(FLock);
  end;
  Result := True;
end;

class function TPackageCompiledFiles.Bytes: Int64;
var
  mEntry: TEntry;
begin
  Result := 0;
  TMonitor.Enter(FLock);
  try
    for mEntry in FFiles.Values do
    begin
      Inc(Result, mEntry.Names.Bytes);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TPackageCompiledFiles.Count: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := FFiles.Count;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TPackageCompiledFiles.Clear;
begin
  TMonitor.Enter(FLock);
  try
    // Neu anlegen statt Clear: Clear behält die Bucket-Tabelle (Speicher bleibt belegt).
    FFiles.Free;
    FFiles := TDictionary<string, TEntry>.Create;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function DiskReadFile: TPackageReadFile;
begin
  Result :=
    function(const AFileName: string; out AData: TBytes): Boolean
    begin
      AData := nil;
      Result := TFile.Exists(AFileName);
      if Result then
      try
        AData := TFile.ReadAllBytes(AFileName);
      except
        // Gesperrte oder nicht lesbare Dateien zählen als fehlend.
        // lsp-ignore: catch-all-without-raise -- Cache nach Kräften; Fehler heißt nicht gefunden
        on Exception do
          Result := False;
      end;
    end;
end;

/// <summary>Übersetzte Packages geteilt über alle Locatoren (Speicher, Rückmeldung 01.11.2026), nur die Namen.
/// </summary>
function DiskReadCompiled: TPackageReadCompiled;
begin
  Result :=
    function(const AFileName, APackage: string; out ANames: TPackageCompiledNames): Boolean
    begin
      Result := TPackageCompiledFiles.Read(AFileName, ANames);
    end;
end;

/// <summary>Namen eines .dcp über AReadFile (Tests): ganze Datei lesen, Namen behalten.</summary>
function CompiledVia(const AReadFile: TPackageReadFile): TPackageReadCompiled;
begin
  Result :=
    function(const AFileName, APackage: string; out ANames: TPackageCompiledNames): Boolean
    var
      mData: TBytes;
    begin
      ANames := Default(TPackageCompiledNames);
      Result := AReadFile(AFileName, mData);
      if Result then
      begin
        ANames := TPackageCompiledNames.Parse(mData, APackage);
      end;
    end;
end;

{ TPackageLocator }

constructor TPackageLocator.Create(const AFolders: TArray<string>);
begin
  Create(AFolders, DiskReadFile());
  FReadCompiled := DiskReadCompiled();
end;

constructor TPackageLocator.Create(const AFolders: TArray<string>; const AReadFile: TPackageReadFile);
begin
  inherited Create;
  FFolders := AFolders;
  FReadFile := AReadFile;
  FReadCompiled := CompiledVia(AReadFile);
  FCache := TDictionary<string, TFound>.Create;
  FLock := TObject.Create;
end;

destructor TPackageLocator.Destroy;
begin
  FLock.Free;
  FCache.Free;
  inherited;
end;

function TPackageLocator.Find(const APackage: string): TFound;
var
  mKey, mFolder, mFileName: string;
  mData: TBytes;
  mFileFormat: TFileFormat;
  mNames: TPackageCompiledNames;
begin
  mKey := UpperCase(APackage);
  TMonitor.Enter(FLock);
  try
    if FCache.TryGetValue(mKey, Result) then
    begin
      Exit;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := Default(TFound);
  for mFolder in FFolders do
  begin
    mFileName := TPath.Combine(mFolder, APackage + '.dpk');
    if FReadFile(mFileName, mData) then
    begin
      Result.Source := TPackageReader.Read(TFileEncoding.Decode(mData, mFileFormat));
      if Result.Source.IsPackage then
      begin
        Result.Known := True;
        Result.FileName := mFileName;
        Break;
      end;
    end;
  end;
  if not Result.Known then
  begin
    for mFolder in FFolders do
    begin
      mFileName := TPath.Combine(mFolder, APackage + '.dcp');
      if FReadCompiled(mFileName, APackage, mNames) then
      begin
        Result.Known := True;
        Result.FileName := mFileName;
        Result.Compiled := mNames;
        Break;
      end;
    end;
  end;
  TMonitor.Enter(FLock);
  try
    FCache.AddOrSetValue(mKey, Result);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TPackageLocator.Provides(const APackage, AUnitName: string; out AContains: Boolean): Boolean;
var
  mFound: TFound;
begin
  mFound := Find(APackage);
  Result := mFound.Known;
  if mFound.Source.IsPackage then
  begin
    AContains := mFound.Source.ContainsIndex(AUnitName) >= 0;
    Exit;
  end;
  // Binärsuche in den Namen des .dcp; früher ein Lauf über alle Bytes je Unit.
  AContains := Result and mFound.Compiled.Contains(AUnitName);
end;

class function TPackageLocator.ContainedFiles(const AFileName: string;
  const ASource: TPackageSource): TArray<string>;
var
  mEntry: TPackageEntry;
  mFolder: string;
begin
  Result := nil;
  mFolder := ExtractFilePath(AFileName);
  for mEntry in ASource.Contains do
  begin
    if mEntry.Path <> '' then
    begin
      Result := Result + [ExpandFileName(TPath.Combine(mFolder, mEntry.Path))];
    end;
  end;
end;

/// <summary>Hängt die Dateien aus AItems an AFiles an, die noch nicht in ASeen stehen (ohne Rücksicht auf
/// Groß-/Kleinschreibung, Reihenfolge bleibt).</summary>
procedure AddNewFiles(const AItems: TArray<string>; ASeen: TDictionary<string, Boolean>; AFiles: TList<string>);
var
  mItem: string;
begin
  for mItem in AItems do
  begin
    if not ASeen.ContainsKey(UpperCase(mItem)) then
    begin
      ASeen.Add(UpperCase(mItem), True);
      AFiles.Add(mItem);
    end;
  end;
end;

function TPackageLocator.RequiredFiles(const ASource: TPackageSource): TArray<string>;
var
  mSeen, mKnown: TDictionary<string, Boolean>;
  mFiles: TList<string>;
  mPending: TQueue<TPackageSource>;
  mCurrent, mRequired: TPackageSource;
  mEntry: TPackageEntry;
  mFileName: string;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  mKnown := TDictionary<string, Boolean>.Create;
  mFiles := TList<string>.Create;
  mPending := TQueue<TPackageSource>.Create;
  try
    mSeen.Add(UpperCase(ASource.Name), True);
    mPending.Enqueue(ASource);
    while mPending.Count > 0 do
    begin
      mCurrent := mPending.Dequeue;
      for mEntry in mCurrent.Requires do
      begin
        // Jedes Package nur einmal, auch wenn es mehrere verlangen.
        if mSeen.ContainsKey(UpperCase(mEntry.Name)) then
        begin
          Continue;
        end;
        mSeen.Add(UpperCase(mEntry.Name), True);
        if FindSource(mEntry.Name, mFileName, mRequired) then
        begin
          AddNewFiles(ContainedFiles(mFileName, mRequired), mKnown, mFiles);
          mPending.Enqueue(mRequired);
        end;
      end;
    end;
    Result := mFiles.ToArray;
  finally
    mPending.Free;
    mFiles.Free;
    mKnown.Free;
    mSeen.Free;
  end;
end;

function TPackageLocator.FindSource(const APackage: string; out AFileName: string;
  out ASource: TPackageSource): Boolean;
var
  mFound: TFound;
begin
  mFound := Find(APackage);
  Result := mFound.Known and mFound.Source.IsPackage;
  AFileName := mFound.FileName;
  ASource := mFound.Source;
end;

function TPackageLocator.Requires(const APackage: string): TArray<string>;
var
  mFound: TFound;
  mEntry: TPackageEntry;
begin
  Result := nil;
  mFound := Find(APackage);
  if mFound.Source.IsPackage then
  begin
    for mEntry in mFound.Source.Requires do
    begin
      Result := Result + [mEntry.Name];
    end;
  end
  else if mFound.Known then
  begin
    // Ohne Quelle nennt der Kopf des .dcp die requires (a2): Vorher deckte die Suche über alle Bytes auch Units
    // der verlangten Packages ab (vcl.dcp erwähnt System.SysUtils), jetzt geht die Unit-Suche über die requires.
    Result := mFound.Compiled.Requires;
  end;
end;

initialization
  TPackageCompiledFiles.FLock := TObject.Create;
  // Den Monitor gleich anlegen: TMonitor belegt ihn beim ersten Enter (Selbstmessung zählt die Dateien), im Test
  // zählte das als Leck.
  TMonitor.Enter(TPackageCompiledFiles.FLock);
  TMonitor.Exit(TPackageCompiledFiles.FLock);
  TPackageCompiledFiles.FFiles := TDictionary<string, TPackageCompiledFiles.TEntry>.Create;

finalization
  FreeAndNil(TPackageCompiledFiles.FFiles);
  FreeAndNil(TPackageCompiledFiles.FLock);

end.
