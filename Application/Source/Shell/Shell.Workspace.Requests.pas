unit Shell.Workspace.Requests;

// Internals-Rolle Shell: Dateien und Indexauftrag eines geladenen Projekts. Projektdateien, alle Units der Such-
// und Bibliothekspfade (#648), Packages aus contains und requires (#46), Symbole, Include-Pfade (#264) und die
// Cache-Dateien je Projekt, Bibliothek und Suchpfaden (#492, #647).
// L2: Office-Typbibliotheken und WinRT gehören immer zur Bibliothek (Katalog, bei Bedarf geladen; der Schalter
// index.officeAndWinRt und der eigene Cache ohne sie sind entfallen). Zusätzliche Quellordner
// (index.extraSourceFolders) kommen samt Unterordnern nach der Bibliothek, mit eigenem gemeinsamen Cache.
// Units eines requires-Packages mit Quelltext gelten als Suchpfad-Units, auch wenn sie zugleich in der Bibliothek
// oder einem Zusatzordner liegen (Sprung in ein anderes Package).

interface

uses
  System.SysUtils,
  dpcc.Common.Logging.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Projects.Contract,
  dpcc.Common.Projects.PackageLocator,
  dpcc.Common.Index.ProjectFiles,
  dpcc.Common.Index.Service,
  Shell.Workspace.Loader;

type
  /// <summary>Dateien eines Indexaufbaus.</summary>
  TShellIndexFiles = record
    Files: TArray<string>;
    SearchFiles: TArray<string>;
    /// <summary>Units der Bibliothek, am Ende die der zusätzlichen Quellordner (L2).</summary>
    LibraryFiles: TArray<string>;
    /// <summary>Zusätzliche Quellordner samt Unterordnern, aufgelöst (L2); leer ohne.</summary>
    ExtraFolders: TArray<string>;
    /// <summary>Die aufgelösten Wurzeln der zusätzlichen Quellordner (L2).</summary>
    ExtraRoots: TArray<string>;
    /// <summary>Neu indexieren, wenn sich ASignature oder die Unit-Listen ändern; der Cache hängt nur an
    /// ASignature.</summary>
    function Key(const ASignature: string): string;
  end;

  /// <summary>Wohin und wie ein Aufbau schreibt.</summary>
  TShellRequestTarget = record
    CacheRoot: string;
    Priority: Integer;
    Usages: Boolean;
  end;

  TShellIndexRequests = class
  private
    class var FExtraLock: TObject;
    class var FExtraRoots: TArray<string>;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Merkt sich die Wurzeln der zusätzlichen Quellordner (L2) für IsExtraSource; prozessweit, die
    /// Einstellung ist global.</summary>
    class procedure NoteExtraRoots(const ARoots: TArray<string>); static;
    /// <summary>Liegt AFileName unter einem zusätzlichen Quellordner? Ohne Wartezeit (kurze eigene Sperre).</summary>
    class function IsExtraSource(const AFileName: string): Boolean; static;
    /// <summary>Trifft ein Muster aus APatterns (index.exclude) den Dateinamen?</summary>
    class function ExcludedOf(const APatterns: TArray<string>): TIndexExcluded; static;
    /// <summary>Projektdateien; mit index.searchPaths die Units der Suchpfade, mit index.libraryPaths die der
    /// Bibliothekspfade, jeweils alle, nicht nur die über uses erreichbaren (#648); dahinter die Units der
    /// zusätzlichen Quellordner (L2). Meldet verworfene oder gekürzte Zusatzordner an ALogger (nil = still).</summary>
    class function FilesOf(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings;
      const ALogger: ILogger = nil): TShellIndexFiles; static;
    /// <summary>Die zusätzlichen Quellordner aus ASettings, aufgelöst ($(Name) mit den Variablen der Installation und
    /// der Umgebung, %Name%); relative ab dem Projektordner. Nicht auflösbare meldet es an ALogger.</summary>
    class function ExtraRootsOf(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings;
      const ALogger: ILogger): TArray<string>; static;
    /// <summary>Packages (#46): contains der .dpk gehört zum Projekt, auch ohne DCCReference; die Units der
    /// requires-Packages mit Quelltext kommen zu den Suchpfad-Units. Meldet die Anzahlen an ALogger.</summary>
    class procedure AddPackageFiles(const AProject: TProjectInfo; ALocator: TPackageLocator;
      var AFiles: TShellIndexFiles; const ALogger: ILogger; const AName: string); static;
    /// <summary>Auftrag für den Aufbau ohne Unit-Suche, Sperre und Vorbereitung.</summary>
    class function RequestOf(const ALoaded: TShellLoadedProject; const AFiles: TShellIndexFiles;
      const ATarget: TShellRequestTarget): TIndexRequest; static;
    /// <summary>Herkunft für das Aufräumen (#905): die Projektdatei, ohne sie ARoot.</summary>
    class function CacheOriginOf(const AProject: TProjectInfo; const ARoot: string): string; static;
    /// <summary>Ordner der Installation, deren Units nur als Katalog und bei Bedarf im Index stehen (L2; vorher c1
    /// „selten genutzt“ mit Schalter): $(BDS)\OCX\Servers (Office-Typbibliotheken) und
    /// $(BDS)\source\rtl\win\winrt; mit Trenner am Ende, leer ohne Installation.</summary>
    class function OnDemandRoots(const ALoaded: TShellLoadedProject): TArray<string>; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  System.IOUtils,
  dpcc.Common.Projects.Paths,
  dpcc.Common.Index.Builder,
  dpcc.Common.Compiler.CommandLine,
  dpcc.Common.Projects.PackageReader,
  dpcc.Common.Index.Adapters.CacheDirectory,
  Shell.Bootstrap,
  Shell.Workspace.Listings,
  dpcc.Text.LogMarks;

const
  /// <summary>Höchstens so viele Ordner durchsucht der Index unter den zusätzlichen Quellordnern (L2); ein zu weit
  /// gefasster Ordner (ein ganzes Laufwerk) bremst sonst jeden Aufbau.</summary>
  cMaxExtraFolders = 2000;

{ TShellIndexFiles }

function TShellIndexFiles.Key(const ASignature: string): string;
begin
  Result := ASignature + '#' + AnsiUpperCase(String.Join(';', Files)) + '#' +
    AnsiUpperCase(String.Join(';', SearchFiles)) + '#' + AnsiUpperCase(String.Join(';', LibraryFiles)) + '#' +
    AnsiUpperCase(String.Join(';', ExtraRoots));
end;

{ TShellIndexRequests }

class constructor TShellIndexRequests.Create;
begin
  FExtraLock := TObject.Create;
end;

class destructor TShellIndexRequests.Destroy;
begin
  FExtraLock.Free;
end;

class procedure TShellIndexRequests.NoteExtraRoots(const ARoots: TArray<string>);
begin
  TMonitor.Enter(FExtraLock);
  try
    FExtraRoots := ARoots;
  finally
    TMonitor.Exit(FExtraLock);
  end;
end;

class function TShellIndexRequests.IsExtraSource(const AFileName: string): Boolean;
var
  mRoots: TArray<string>;
begin
  TMonitor.Enter(FExtraLock);
  try
    mRoots := FExtraRoots;
  finally
    TMonitor.Exit(FExtraLock);
  end;
  Result := TIndexFileDefines.IsUnder(AFileName, mRoots);
end;

class function TShellIndexRequests.ExcludedOf(const APatterns: TArray<string>): TIndexExcluded;
var
  mPatterns: TArray<string>;
begin
  mPatterns := APatterns;
  Result :=
    function(const AFileName: string): Boolean
    var
      mPattern: string;
    begin
      Result := False;
      for mPattern in mPatterns do
      begin
        Result := Result or MatchesGlob(mPattern, AFileName);
      end;
    end;
end;

/// <summary>Wert einer Umgebungsvariablen des Prozesses (L2: $(Name) und %Name% in zusätzlichen Quellordnern).
/// </summary>
function EnvironmentOf: TIndexEnvironment;
begin
  Result :=
    function(const AName: string): string
    begin
      Result := GetEnvironmentVariable(AName);
    end;
end;

/// <summary>Ordnerliste für FolderTree.</summary>
function FoldersOf: TIndexListFolders;
var
  mFolders: TFunc<string, TArray<string>>;
begin
  mFolders := TShellFileAccess.FoldersFunc();
  Result :=
    function(const AFolder: string): TArray<string>
    begin
      Result := mFolders(AFolder);
    end;
end;

class function TShellIndexRequests.ExtraRootsOf(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings;
  const ALogger: ILogger): TArray<string>;
var
  mFolder, mExpanded: string;
  mVariables: TArray<TPair<string, string>>;
begin
  Result := nil;
  mVariables := ALoaded.Variables + [TPair<string, string>.Create('Platform', ALoaded.Project.Platform),
    TPair<string, string>.Create('Config', ALoaded.Project.Config)];
  for mFolder in ASettings.IndexExtraSourceFolders do
  begin
    mExpanded := TIndexProjectFiles.ExpandFolder(mFolder, mVariables, EnvironmentOf());
    if mExpanded = '' then
    begin
      if ALogger <> nil then
      begin
        ALogger.Warning(Format('index.extraSourceFolders: %s nicht auflösbar, übergangen', [TLogMarks.Path(mFolder)]));
      end;
      Continue;
    end;
    // Relativ: ab dem Projektordner (wie Suchpfade).
    mExpanded := TProjectPaths.Combine(ExtractFileDir(ALoaded.ProjectFile), mExpanded);
    if IndexText(mExpanded, Result) < 0 then
    begin
      Result := Result + [mExpanded];
    end;
  end;
end;

class function TShellIndexRequests.FilesOf(const ALoaded: TShellLoadedProject;
  const ASettings: TServerSettings; const ALogger: ILogger): TShellIndexFiles;
var
  mExcluded: TIndexExcluded;
  mTruncated: Boolean;
begin
  mExcluded := ExcludedOf(ASettings.IndexExclude);
  Result := Default(TShellIndexFiles);
  Result.Files := TIndexProjectFiles.Files(ALoaded.Project);
  // L2: Ohne Projekt (Ordner einer losen Datei) kommen seine Units nur bei Bedarf über die Unit-Suche.
  if ASettings.IndexSearchPaths and (ALoaded.ProjectFile <> '') then
  begin
    Result.SearchFiles := TIndexProjectFiles.PathFiles(ALoaded.Project.SearchPaths, TShellFileAccess.PasFilesFunc(),
      mExcluded, Result.Files);
  end;
  if ASettings.IndexLibraryPaths then
  begin
    Result.LibraryFiles := TIndexProjectFiles.PathFiles(ALoaded.LibraryPaths, TShellFileAccess.PasFilesFunc(),
      mExcluded, Result.Files + Result.SearchFiles);
  end;
  // L2: zusätzliche Quellordner samt Unterordnern, nach der Bibliothek (gleichnamige Units: Bibliothek vor
  // Zusatzordner); was Projekt, Suchpfade oder Bibliothek schon haben, bleibt dort.
  Result.ExtraRoots := ExtraRootsOf(ALoaded, ASettings, ALogger);
  NoteExtraRoots(Result.ExtraRoots);
  if Length(Result.ExtraRoots) > 0 then
  begin
    Result.ExtraFolders := TIndexProjectFiles.FolderTree(Result.ExtraRoots, FoldersOf(), cMaxExtraFolders, mTruncated);
    if mTruncated and (ALogger <> nil) then
    begin
      ALogger.Warning(Format('index.extraSourceFolders: mehr als %d Ordner, der Rest bleibt außen vor',
        [cMaxExtraFolders]));
    end;
    Result.LibraryFiles := Result.LibraryFiles + TIndexProjectFiles.PathFiles(Result.ExtraFolders,
      TShellFileAccess.PasFilesFunc(), mExcluded, Result.Files + Result.SearchFiles + Result.LibraryFiles);
  end;
end;

class function TShellIndexRequests.OnDemandRoots(const ALoaded: TShellLoadedProject): TArray<string>;
var
  mBds: string;
begin
  Result := nil;
  if ALoaded.Installation = nil then
  begin
    Exit;
  end;
  mBds := TCompilerCommandLine.BdsRoot(ALoaded.Installation.Variables);
  if mBds = '' then
  begin
    Exit;
  end;
  Result := [IncludeTrailingPathDelimiter(TPath.Combine(mBds, 'OCX\Servers')),
    IncludeTrailingPathDelimiter(TPath.Combine(mBds, 'source\rtl\win\winrt'))];
end;

/// <summary>Hängt die vorhandenen, noch nicht bekannten Dateien aus ACandidates an ATarget; Anzahl.</summary>
function AddNew(const ACandidates: TArray<string>; AKnown: TDictionary<string, Boolean>;
  var ATarget: TArray<string>): Integer;
var
  mFileName: string;
begin
  Result := 0;
  for mFileName in ACandidates do
  begin
    if not AKnown.ContainsKey(AnsiUpperCase(mFileName)) and FileExists(mFileName) then
    begin
      AKnown.Add(AnsiUpperCase(mFileName), True);
      ATarget := ATarget + [mFileName];
      Inc(Result);
    end;
  end;
end;

/// <summary>Die Dateien aus AFiles, die nicht in AKnown stehen (Schlüssel groß), in ihrer Reihenfolge.</summary>
function WithoutKnown(const AFiles: TArray<string>; AKnown: TDictionary<string, Boolean>): TArray<string>;
var
  mFileName: string;
begin
  Result := nil;
  for mFileName in AFiles do
  begin
    if not AKnown.ContainsKey(AnsiUpperCase(mFileName)) then
    begin
      Result := Result + [mFileName];
    end;
  end;
end;

/// <summary>Quelltext der .dpk von AProject; False, wenn es kein lesbares Package ist.</summary>
function PackageSourceOf(const AProject: TProjectInfo; out ASource: TPackageSource): Boolean;
var
  mText: string;
begin
  Result := SameText(ExtractFileExt(AProject.MainSource), '.dpk') and
    TShellBootstrap.ReadSourceText(AProject.MainSource, mText);
  if Result then
  begin
    ASource := TPackageReader.Read(mText);
    Result := ASource.IsPackage;
  end;
end;

class procedure TShellIndexRequests.AddPackageFiles(const AProject: TProjectInfo; ALocator: TPackageLocator;
  var AFiles: TShellIndexFiles; const ALogger: ILogger; const AName: string);
var
  mSource: TPackageSource;
  mKnown: TDictionary<string, Boolean>;
  mFileName: string;
  mAdded, mRequired: Integer;
begin
  if not PackageSourceOf(AProject, mSource) then
  begin
    Exit;
  end;
  mKnown := TDictionary<string, Boolean>.Create;
  try
    for mFileName in AFiles.Files + AFiles.SearchFiles do
    begin
      mKnown.AddOrSetValue(AnsiUpperCase(mFileName), True);
    end;
    mAdded := AddNew(TPackageLocator.ContainedFiles(AProject.MainSource, mSource), mKnown, AFiles.Files);
    mRequired := AddNew(ALocator.RequiredFiles(mSource), mKnown, AFiles.SearchFiles);
    // Liegt ein requires-Package in einem zusätzlichen Quellordner oder im Bibliothekspfad, stehen seine Units auch
    // in der Bibliotheksstufe; wie in FilesOf gilt die frühere Stufe.
    if (mAdded > 0) or (mRequired > 0) then
    begin
      AFiles.LibraryFiles := WithoutKnown(AFiles.LibraryFiles, mKnown);
    end;
  finally
    mKnown.Free;
  end;
  if (mAdded > 0) or (mRequired > 0) then
  begin
    ALogger.Info(Format('%s: Package mit %d Units aus contains ohne DCCReference und %d aus requires-Packages',
      [TLogMarks.Name(AName), mAdded, mRequired]));
  end;
end;

/// <summary>Schlüssel des Suchpfad-Caches: Suchpfad-Units einmal für alle Projekte mit denselben Suchpfaden,
/// Defines und Include-Pfaden (Speicher, Rückmeldung 01.11.2026); sie werden mit den Defines des Projekts gelesen,
/// die gehören in den Schlüssel.</summary>
function SearchCacheKey(const ARequest: TIndexRequest; const AProject: TProjectInfo): string;
begin
  Result := AnsiUpperCase('search|' + String.Join(';', ARequest.Defines) + '|' +
    String.Join(';', AProject.SearchPaths) + '|' + String.Join(';', ARequest.IncludePaths) + '|' +
    String.Join(';', AProject.Namespaces));
end;

/// <summary>Bibliothek des Auftrags: RTL, VCL und FMX einmal je Compiler und Plattform, unabhängig von Projekt und
/// Konfiguration (#647). Nur der Ordner der Installation: Eigener Code im Bibliothekspfad wird oft mit dem Projekt
/// übersetzt. $I-Dateien wie beim Compiler: Projekt-Suchpfade, dann Bibliothekspfade (#264).</summary>
procedure SetLibrary(const ALoaded: TShellLoadedProject; var ARequest: TIndexRequest);
begin
  ARequest.IncludePaths := ALoaded.Project.SearchPaths;
  if ALoaded.Installation = nil then
  begin
    Exit;
  end;
  ARequest.LibraryRoots := TArray<string>.Create(TCompilerCommandLine.BdsRoot(ALoaded.Installation.Variables));
  ARequest.LibraryDefines := TIndexProjectFiles.LibraryDefines(ALoaded.Project, ALoaded.Version);
  ARequest.IncludePaths := ALoaded.Project.SearchPaths + ALoaded.CompilerLibraryPaths;
end;

class function TShellIndexRequests.RequestOf(const ALoaded: TShellLoadedProject; const AFiles: TShellIndexFiles;
  const ATarget: TShellRequestTarget): TIndexRequest;
var
  mLibrarySignature: string;
begin
  Result := Default(TIndexRequest);
  Result.Files := AFiles.Files;
  Result.SearchFiles := AFiles.SearchFiles;
  Result.LibraryFiles := AFiles.LibraryFiles;
  Result.Priority := ATarget.Priority;
  Result.Defines := TIndexProjectFiles.Defines(ALoaded.Project, ALoaded.Version);
  SetLibrary(ALoaded, Result);
  // Ablage je IDE-Version und Projekt (#492): %LOCALAPPDATA%\dpcc\Index\<Version>\<Projekt-Hash>.
  Result.CacheFile := TIndexCacheDirectory.FileFor(ATarget.CacheRoot, ALoaded.Version,
    TIndexProjectFiles.Signature(ALoaded.Project, ALoaded.Version));
  // RTL/VCL/FMX einmal je Compilerversion und Plattform, geteilt mit allen Projekten (#492, #647); seit L2 immer
  // samt Office-Typbibliotheken und WinRT (der eigene Cache "ohne-office-winrt" der Speicher-Optimierung c1 ist
  // entfallen). Diese Units stehen im Katalog; über die uses der Bibliothek kommen sie nicht in die Hülle.
  mLibrarySignature := TIndexProjectFiles.LibrarySignature(ALoaded.Project, ALoaded.Version);
  Result.OnDemandRoots := OnDemandRoots(ALoaded);
  Result.LibraryCacheFile := TIndexCacheDirectory.LibraryFileFor(ATarget.CacheRoot, ALoaded.Version,
    mLibrarySignature);
  // Zusätzliche Quellordner (L2): eigener gemeinsamer Cache je Plattform, Version und Ordnern; ein anderer Ordner
  // liest so nicht die ganze Bibliothek neu.
  if Length(AFiles.ExtraRoots) > 0 then
  begin
    Result.ExtraRoots := AFiles.ExtraRoots;
    Result.ExtraCacheFile := TIndexCacheDirectory.ExtraFileFor(ATarget.CacheRoot, ALoaded.Version,
      TIndexProjectFiles.ExtraSignature(ALoaded.Project, ALoaded.Version, AFiles.ExtraRoots));
  end;
  // Speicher-Optimierung Phase 3: Die Bibliotheksstufe übernimmt Units aus diesem Cache nur mit Kopf und Katalog;
  // ihre Symbole lädt der Index bei Bedarf. Bewusst ohne Einstellung.
  Result.LazyLibrary := True;
  if Length(AFiles.SearchFiles) > 0 then
  begin
    Result.SearchCacheFile := TIndexCacheDirectory.SearchFileFor(ATarget.CacheRoot, ALoaded.Version,
      SearchCacheKey(Result, ALoaded.Project));
  end;
  Result.Usages := ATarget.Usages;
end;

class function TShellIndexRequests.CacheOriginOf(const AProject: TProjectInfo; const ARoot: string): string;
begin
  Result := AProject.FileName;
  if Result = '' then
  begin
    Result := ARoot;
  end;
end;

end.
