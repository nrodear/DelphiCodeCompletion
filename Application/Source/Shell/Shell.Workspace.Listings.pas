unit Shell.Workspace.Listings;

// Internals-Rolle Shell: Ordnerlisten und Dateizugriffe für Unit-Suche und Indexaufbau der Arbeitsbereiche.
// Die Listen der .pas- und .dcu-Dateien je Ordner teilen sich alle Projekte des Servers.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Common.Index.Contract,
  dpcc.Common.Projects.UnitLookup,
  dpcc.Common.Index.ProjectFiles;

type
  /// <summary>.pas-Dateien (für uses-unit-not-found auch .dcu, #1016) je Ordner, geteilt von allen Projekten
  /// des Servers. Neu gelesen, wenn sich der Ordner geändert hat (Datei hinzugefügt oder entfernt).</summary>
  TSharedUnitListings = class
  private type
    TListing = record
      Stamp: TDateTime;
      Files: TArray<string>;
    end;
  private
    class var FLock: TObject;
    class var FListings: TDictionary<string, TListing>;
    class function Cached(const AKey: string; AStamp: TDateTime; out AFiles: TArray<string>): Boolean; static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>.pas-Dateien des Ordners.</summary>
    class function List(AFolder: string): TArray<string>; static;
    /// <summary>.pas- und .dcu-Dateien des Ordners.</summary>
    class function ListUnitFiles(AFolder: string): TArray<string>; static;
    class function Listed(const AFolder, APattern: string): TArray<string>; static;
    /// <summary>Leert die Listen. Für Tests: Je Testordner bliebe sonst ein Eintrag bis Programmende.</summary>
    class procedure Clear; static;
    /// <summary>List als Rückruf.</summary>
    class function ListFunc: TFunc<string, TArray<string>>; static;
    /// <summary>ListUnitFiles als Rückruf.</summary>
    class function ListUnitFilesFunc: TFunc<string, TArray<string>>; static;
  end;

  /// <summary>Stände von Ordnern außerhalb der beobachteten Wurzeln (L2): Suchpfade in anderen Repositories,
  /// Fremdquellen der Bibliothek, Zusatzordner und $(BDS) melden keine Ereignisse. Je Ordner merkt sich die Klasse
  /// einen Fingerabdruck aus Namen, Zeit und Größe der .pas-Dateien; ändert er sich, vergleicht Changes die Dateien
  /// mit dem Index. Nicht threadsicher (ein Prüflauf zur Zeit).</summary>
  TShellFolderStamps = class
  private
    FPrints: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Fingerabdruck von AFolder ('' wenn er fehlt).</summary>
    class function PrintOf(const AFolder: string): string; static;
    /// <summary>Änderungen in AFolders seit dem letzten Aufruf gegen AIndex: neue, geänderte (anderer Stand, wie
    /// TIndexBuilder.SourceStampOf über AFileSystem) und gelöschte .pas-Dateien. Beim ersten Mal je Ordner nur der
    /// Fingerabdruck.</summary>
    function Changes(const AFolders: TArray<string>; const AIndex: ISymbolIndex;
      const AFileSystem: IIndexFileSystem): TArray<TFileChange>;
    /// <summary>Gemerkte Ordner (Tests).</summary>
    function Count: Integer;
  end;

  /// <summary>Dateizugriffe als Rückrufe für Unit-Suche, Projektleser und Indexaufbau; nicht lesbare Ordner und
  /// Dateien tragen nichts bei.</summary>
  TShellFileAccess = class
  public
    /// <summary>Unterordner von AFolder, ungeteilt.</summary>
    class function Folders(AFolder: string): TArray<string>; static;
    /// <summary>.pas-Dateien von AFolder, ungeteilt (#648: alle Units der Such- und Bibliothekspfade).</summary>
    class function PasFiles(const AFolder: string): TArray<string>; static;
    class function Exists(AFileName: string): Boolean; static;
    /// <summary>Text der Datei in ihrer Kodierung; False, wenn sie fehlt oder nicht lesbar ist.</summary>
    class function ReadText(const AFileName: string; out AText: string): Boolean; static;
    // Als Rückrufe: Free Pascal bricht beim Zuweisen statischer Klassenmethoden einer anderen Unit an
    // Methodenreferenzen intern ab (EListError); eine anonyme Methode je Rückruf umgeht das.
    class function FoldersFunc: TFunc<string, TArray<string>>; static;
    class function PasFilesFunc: TIndexListUnits; static;
    class function ExistsFunc: TFunc<string, Boolean>; static;
    class function ReadTextFunc: TUnitLookupReadText; static;
  end;

implementation

uses
  System.IOUtils,
  System.Hash,
  dpcc.Common.Index.Builder,
  dpcc.Common.Documents.FileEncoding;

{ TShellFolderStamps }

constructor TShellFolderStamps.Create;
begin
  inherited Create;
  FPrints := TDictionary<string, string>.Create;
end;

destructor TShellFolderStamps.Destroy;
begin
  FPrints.Free;
  inherited;
end;

function TShellFolderStamps.Count: Integer;
begin
  Result := FPrints.Count;
end;

class function TShellFolderStamps.PrintOf(const AFolder: string): string;
var
  mSearch: TSearchRec;
  mText: TStringBuilder;
  mCount: Integer;
begin
  Result := '';
  mCount := 0;
  mText := TStringBuilder.Create;
  try
    if FindFirst(IncludeTrailingPathDelimiter(AFolder) + '*.pas', faAnyFile, mSearch) = 0 then
    try
      repeat
        mText.Append(LowerCase(mSearch.Name)).Append('|').Append(mSearch.TimeStamp).Append('|').Append(mSearch.Size)
          .Append(';');
        Inc(mCount);
      until FindNext(mSearch) <> 0;
    finally
      FindClose(mSearch);
    end;
    if mCount > 0 then
    begin
      Result := IntToStr(mCount) + '#' + THashSHA1.GetHashString(mText.ToString);
    end;
  finally
    mText.Free;
  end;
end;

function TShellFolderStamps.Changes(const AFolders: TArray<string>; const AIndex: ISymbolIndex;
  const AFileSystem: IIndexFileSystem): TArray<TFileChange>;
var
  mFolder, mKey, mPrint, mKnown, mFileName: string;
  mStamp: Int64;
  mUnit: TUnitIndex;
  mCatalog: TCatalogUnit;
  mChanged: TList<string>;
  mList: TList<TFileChange>;
begin
  mChanged := TList<string>.Create;
  mList := TList<TFileChange>.Create;
  try
    for mFolder in AFolders do
    begin
      mKey := AnsiUpperCase(ExcludeTrailingPathDelimiter(mFolder));
      if mChanged.Contains(mKey) then
      begin
        Continue;
      end;
      mPrint := PrintOf(mFolder);
      if not FPrints.TryGetValue(mKey, mKnown) then
      begin
        // Erster Blick: nur merken. Was vor dem Aufbau geändert war, hat der Aufbau gelesen.
        FPrints.Add(mKey, mPrint);
        Continue;
      end;
      if mKnown = mPrint then
      begin
        Continue;
      end;
      FPrints[mKey] := mPrint;
      mChanged.Add(mKey);
      for mFileName in TShellFileAccess.PasFiles(ExcludeTrailingPathDelimiter(mFolder)) do
      begin
        if not AIndex.FindHeader(mFileName, mUnit) then
        begin
          mList.Add(TFileChange.Create(mFileName, TFileChangeKind.Created));
        end
        else if TIndexBuilder.SourceStampOf(AFileSystem, mFileName, mStamp) and (mStamp <> mUnit.Stamp) then
        begin
          mList.Add(TFileChange.Create(mFileName, TFileChangeKind.Changed));
        end;
      end;
    end;
    // Gelöschte: Units des Index in einem geänderten Ordner, deren Datei fehlt.
    if mChanged.Count > 0 then
    begin
      for mCatalog in AIndex.CatalogUnits do
      begin
        if mChanged.Contains(AnsiUpperCase(ExtractFileDir(mCatalog.FileName))) and not FileExists(mCatalog.FileName) then
        begin
          mList.Add(TFileChange.Create(mCatalog.FileName, TFileChangeKind.Deleted));
        end;
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mChanged.Free;
  end;
end;

{ TSharedUnitListings }

class constructor TSharedUnitListings.Create;
begin
  FLock := TObject.Create;
  FListings := TDictionary<string, TListing>.Create;
end;

class destructor TSharedUnitListings.Destroy;
begin
  FListings.Free;
  FLock.Free;
end;

class procedure TSharedUnitListings.Clear;
begin
  TMonitor.Enter(FLock);
  try
    FListings.Clear;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TSharedUnitListings.List(AFolder: string): TArray<string>;
begin
  Result := Listed(AFolder, '*.pas');
end;

class function TSharedUnitListings.ListUnitFiles(AFolder: string): TArray<string>;
begin
  Result := Listed(AFolder, '*.pas') + Listed(AFolder, '*.dcu');
end;

class function TSharedUnitListings.Cached(const AKey: string; AStamp: TDateTime; out AFiles: TArray<string>): Boolean;
var
  mListing: TListing;
begin
  TMonitor.Enter(FLock);
  try
    Result := FListings.TryGetValue(AKey, mListing) and (mListing.Stamp = AStamp);
    AFiles := mListing.Files;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TSharedUnitListings.Listed(const AFolder, APattern: string): TArray<string>;
var
  mKey: string;
  mListing: TListing;
begin
  Result := nil;
  try
    if not TDirectory.Exists(AFolder) then
    begin
      Exit;
    end;
    mListing.Stamp := TDirectory.GetLastWriteTime(AFolder);
    mKey := AnsiLowerCase(ExcludeTrailingPathDelimiter(AFolder)) + '|' + APattern;
    if Cached(mKey, mListing.Stamp, Result) then
    begin
      Exit;
    end;
    mListing.Files := TDirectory.GetFiles(AFolder, APattern);
    TMonitor.Enter(FLock);
    try
      FListings.AddOrSetValue(mKey, mListing);
    finally
      TMonitor.Exit(FLock);
    end;
    Result := mListing.Files;
  except
    // Nicht lesbare Ordner (Rechte, Netzlaufwerk) tragen nichts bei.
    on Exception do
      Result := nil;
  end;
end;

class function TSharedUnitListings.ListFunc: TFunc<string, TArray<string>>;
begin
  Result :=
    function(AFolder: string): TArray<string>
    begin
      Result := List(AFolder);
    end;
end;

class function TSharedUnitListings.ListUnitFilesFunc: TFunc<string, TArray<string>>;
begin
  Result :=
    function(AFolder: string): TArray<string>
    begin
      Result := ListUnitFiles(AFolder);
    end;
end;

{ TShellFileAccess }

class function TShellFileAccess.FoldersFunc: TFunc<string, TArray<string>>;
begin
  Result :=
    function(AFolder: string): TArray<string>
    begin
      Result := Folders(AFolder);
    end;
end;

class function TShellFileAccess.PasFilesFunc: TIndexListUnits;
begin
  Result :=
    function(const AFolder: string): TArray<string>
    begin
      Result := PasFiles(AFolder);
    end;
end;

class function TShellFileAccess.ExistsFunc: TFunc<string, Boolean>;
begin
  Result :=
    function(AFileName: string): Boolean
    begin
      Result := Exists(AFileName);
    end;
end;

class function TShellFileAccess.ReadTextFunc: TUnitLookupReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadText(AFileName, AText);
    end;
end;

class function TShellFileAccess.Folders(AFolder: string): TArray<string>;
begin
  Result := nil;
  try
    if TDirectory.Exists(AFolder) then
    begin
      Result := TDirectory.GetDirectories(AFolder);
    end;
  except
    on Exception do
      Result := nil;
  end;
end;

class function TShellFileAccess.PasFiles(const AFolder: string): TArray<string>;
begin
  Result := nil;
  try
    if TDirectory.Exists(AFolder) then
    begin
      Result := TDirectory.GetFiles(AFolder, '*.pas');
    end;
  except
    // Nicht lesbare Ordner (Rechte, Netzlaufwerk) tragen nichts bei.
    on Exception do
      Result := nil;
  end;
end;

class function TShellFileAccess.Exists(AFileName: string): Boolean;
begin
  Result := FileExists(AFileName);
end;

class function TShellFileAccess.ReadText(const AFileName: string; out AText: string): Boolean;
var
  mFormat: TFileFormat;
begin
  Result := FileExists(AFileName);
  AText := '';
  if Result then
  try
    AText := TFileEncoding.LoadFromFile(AFileName, mFormat);
  except
    on Exception do
      Result := False;
  end;
end;

end.
