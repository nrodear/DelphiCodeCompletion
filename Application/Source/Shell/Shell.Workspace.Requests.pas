unit Shell.Workspace.Requests;

// Internals-Rolle Shell: Dateien und Indexauftrag eines geladenen Projekts. Projektdateien, alle Units der Such-
// und Bibliothekspfade (#648), Packages aus contains und requires (#46), Symbole, Include-Pfade (#264) und die
// Cache-Dateien je Projekt, Bibliothek und Suchpfaden (#492, #647).

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
    LibraryFiles: TArray<string>;
    /// <summary>Neu indexieren, wenn sich ASignature oder die Unit-Listen ändern; der Cache hängt nur an
    /// ASignature.</summary>
    function Key(const ASignature: string): string;
  end;

  /// <summary>Wohin und wie ein Aufbau schreibt.</summary>
  TShellRequestTarget = record
    CacheRoot: string;
    Priority: Integer;
    Usages: Boolean;
    /// <summary>index.officeAndWinRt (c1): Ohne OCX\Servers und WinRT hat die Bibliothek einen eigenen Cache.
    /// </summary>
    OfficeAndWinRt: Boolean;
  end;

  TShellIndexRequests = class
  public
    /// <summary>Trifft ein Muster aus APatterns (index.exclude) den Dateinamen?</summary>
    class function ExcludedOf(const APatterns: TArray<string>): TIndexExcluded; static;
    /// <summary>Projektdateien; mit index.searchPaths die Units der Suchpfade, mit index.libraryPaths die der
    /// Bibliothekspfade, jeweils alle, nicht nur die über uses erreichbaren (#648). Ohne index.officeAndWinRt (c1)
    /// fehlen davon die Units unter RarelyUsedRoots.</summary>
    class function FilesOf(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings): TShellIndexFiles;
      static;
    /// <summary>Packages (#46): contains der .dpk gehört zum Projekt, auch ohne DCCReference; die Units der
    /// requires-Packages mit Quelltext kommen zu den Suchpfad-Units. Meldet die Anzahlen an ALogger.</summary>
    class procedure AddPackageFiles(const AProject: TProjectInfo; ALocator: TPackageLocator;
      var AFiles: TShellIndexFiles; const ALogger: ILogger; const AName: string); static;
    /// <summary>Auftrag für den Aufbau ohne Unit-Suche, Sperre und Vorbereitung.</summary>
    class function RequestOf(const ALoaded: TShellLoadedProject; const AFiles: TShellIndexFiles;
      const ATarget: TShellRequestTarget): TIndexRequest; static;
    /// <summary>Herkunft für das Aufräumen (#905): die Projektdatei, ohne sie ARoot.</summary>
    class function CacheOriginOf(const AProject: TProjectInfo; const ARoot: string): string; static;
    /// <summary>Ordner der Installation, die ohne index.officeAndWinRt nicht vorab indiziert werden (c1):
    /// $(BDS)\OCX\Servers (Office-Typbibliotheken, MSHTML) und $(BDS)\source\rtl\win\winrt; mit Trenner am
    /// Ende, leer ohne Installation.</summary>
    class function RarelyUsedRoots(const ALoaded: TShellLoadedProject): TArray<string>; static;
    /// <summary>Liegt AFileName unter einem Ordner aus ARoots (ohne Groß-/Kleinschreibung)?</summary>
    class function IsRarelyUsed(const AFileName: string; const ARoots: TArray<string>): Boolean; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  System.IOUtils,
  dpcc.Common.Compiler.CommandLine,
  dpcc.Common.Projects.PackageReader,
  dpcc.Common.Index.Adapters.CacheDirectory,
  Shell.Bootstrap,
  Shell.Workspace.Listings,
  dpcc.Text.LogMarks;

/// <summary>AFiles ohne die Dateien unter ARoots (c1).</summary>
function WithoutRarelyUsed(const AFiles, ARoots: TArray<string>): TArray<string>;
var
  mFiles: TList<string>;
  mFileName: string;
begin
  if Length(ARoots) = 0 then
  begin
    Exit(AFiles);
  end;
  mFiles := TList<string>.Create;
  try
    for mFileName in AFiles do
    begin
      if not TShellIndexRequests.IsRarelyUsed(mFileName, ARoots) then
      begin
        mFiles.Add(mFileName);
      end;
    end;
    Result := mFiles.ToArray;
  finally
    mFiles.Free;
  end;
end;

{ TShellIndexFiles }

function TShellIndexFiles.Key(const ASignature: string): string;
begin
  Result := ASignature + '#' + AnsiUpperCase(String.Join(';', Files)) + '#' +
    AnsiUpperCase(String.Join(';', SearchFiles)) + '#' + AnsiUpperCase(String.Join(';', LibraryFiles));
end;

{ TShellIndexRequests }

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

class function TShellIndexRequests.FilesOf(const ALoaded: TShellLoadedProject;
  const ASettings: TServerSettings): TShellIndexFiles;
var
  mExcluded: TIndexExcluded;
begin
  mExcluded := ExcludedOf(ASettings.IndexExclude);
  Result := Default(TShellIndexFiles);
  Result.Files := TIndexProjectFiles.Files(ALoaded.Project);
  if ASettings.IndexSearchPaths then
  begin
    Result.SearchFiles := TIndexProjectFiles.PathFiles(ALoaded.Project.SearchPaths, TShellFileAccess.PasFilesFunc(),
      mExcluded, Result.Files);
  end;
  if ASettings.IndexLibraryPaths then
  begin
    Result.LibraryFiles := TIndexProjectFiles.PathFiles(ALoaded.LibraryPaths, TShellFileAccess.PasFilesFunc(),
      mExcluded, Result.Files + Result.SearchFiles);
  end;
  if not ASettings.IndexOfficeAndWinRt then
  begin
    Result.LibraryFiles := WithoutRarelyUsed(Result.LibraryFiles, RarelyUsedRoots(ALoaded));
  end;
end;

class function TShellIndexRequests.RarelyUsedRoots(const ALoaded: TShellLoadedProject): TArray<string>;
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

class function TShellIndexRequests.IsRarelyUsed(const AFileName: string; const ARoots: TArray<string>): Boolean;
var
  mRoot: string;
begin
  for mRoot in ARoots do
  begin
    if StartsText(mRoot, AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
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
  // RTL/VCL/FMX einmal je Compilerversion und Plattform, geteilt mit allen Projekten (#492, #647). Ohne OCX\Servers
  // und WinRT (c1) ein eigener, kleinerer Cache: Beim Umschalten bleibt der andere liegen und gilt beim
  // Zurückschalten wieder; Einträge der ausgelassenen Units läsen sonst bei jedem Start mit.
  mLibrarySignature := TIndexProjectFiles.LibrarySignature(ALoaded.Project, ALoaded.Version);
  if not ATarget.OfficeAndWinRt then
  begin
    mLibrarySignature := mLibrarySignature + '|ohne-office-winrt';
    // Auch über die uses der Bibliothek nicht vorab (nur, wenn das Projekt sie nennt).
    Result.RarelyUsedRoots := RarelyUsedRoots(ALoaded);
  end;
  Result.LibraryCacheFile := TIndexCacheDirectory.LibraryFileFor(ATarget.CacheRoot, ALoaded.Version,
    mLibrarySignature);
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
