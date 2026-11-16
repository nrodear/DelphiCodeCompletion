unit dpcc.Common.Memory.Phase1.Tests;

// Speicher-Optimierung Phase 1: Eine neue Syntaxbaum-Fassung ersetzt die früheren am Dokument (a6), der gemeinsame
// Bibliotheks-Cache wird nicht noch einmal gelesen, wenn der Index seinen Stand schon hält (b1), und
// Office-Typbibliotheken (OCX\Servers) und WinRT indiziert dpcc nur mit index.officeAndWinRt vorab (c1).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract;

type
  /// <summary>Dateisystem im Speicher; zählt ReadBytes je Datei (aus den früheren Index-Tests).</summary>
  TCountingIndexFileSystem = class(TInterfacedObject, IIndexFileSystem)
  private
    FTexts: TDictionary<string, string>;
    FBytes: TDictionary<string, TBytes>;
    FStamps: TDictionary<string, Int64>;
    FByteReads: TDictionary<string, Integer>;
    FLocked: TDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Put(const AFileName, AText: string; AStamp: Int64);
    /// <summary>So oft wurde AFileName mit ReadBytes gelesen.</summary>
    function ByteReads(const AFileName: string): Integer;
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    function ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
    function WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
    function TryLockWrite(const AFileName: string): IInterface;
    procedure Unlock(const AFileName: string);
  end;

  [TestFixture]
  TDpccMemoryPhase1Tests = class
  private
    FFiles: TCountingIndexFileSystem;
    FFileSystem: IIndexFileSystem;
    FFolder: string;
    /// <summary>Zwei Aufbauten mit frischem Index: Lesezugriffe auf den Bibliotheks-Cache je Aufbau, übersprungene
    /// Caches und die aus dem Cache übernommenen Units des ersten.</summary>
    procedure RunCacheScenario(out AFirstReads, ASecondReads, ASkipped, AFirstFromCache: Integer);
    procedure RunFilesScenario(out AWithout, AWith: TArray<string>; out AWithoutCache, AWithCache: string);
  public
    /// <summary>Einmal-Belegungen (gemeinsamer Stand der Cache-Datei, Ordnerlisten) vor dem Leckmonitor.</summary>
    [SetupFixture]
    procedure WarmUp;
    [TearDownFixture]
    procedure CleanUp;
    /// <summary>a6: Eine neue Fassung "Art|Stand" ersetzt die früheren derselben Art; andere Schlüssel bleiben.
    /// </summary>
    [Test]
    procedure NewTreeVariantReplacesOlder;
    /// <summary>b1: Hält der Index den Stand des Bibliotheks-Caches, liest der nächste Aufbau ihn nicht noch einmal;
    /// ein frischer Index liest ihn.</summary>
    [Test]
    procedure HeldLibraryCacheIsNotReadAgain;
    /// <summary>c1: index.officeAndWinRt ist aus (Server und Plugin), wird nach settings.json umgeleitet und auf
    /// der Seite „Allgemein“ gezeigt.</summary>
    [Test]
    procedure OfficeAndWinRtOffByDefault;
    /// <summary>c1: Ohne den Schalter fehlen die Units unter OCX\Servers und source\rtl\win\winrt in der
    /// Bibliothek, und der Bibliotheks-Cache hat einen eigenen Schlüssel.</summary>
    [Test]
    procedure OfficeAndWinRtLeftOutOfLibrary;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Documents.TextDocument,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.Service,
  dpcc.Common.Index.Builder,
  dpcc.Common.Projects.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Configuration.Parser,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.Scopes,
  dpcc.Core.Settings.Catalog,
  dpcc.Core.Settings.CompletionView,
  Shell.Workspace.Loader,
  Shell.Workspace.Requests;

{ TCountingIndexFileSystem }

constructor TCountingIndexFileSystem.Create;
begin
  inherited Create;
  FTexts := TDictionary<string, string>.Create;
  FBytes := TDictionary<string, TBytes>.Create;
  FStamps := TDictionary<string, Int64>.Create;
  FByteReads := TDictionary<string, Integer>.Create;
  FLocked := TDictionary<string, Boolean>.Create;
end;

destructor TCountingIndexFileSystem.Destroy;
begin
  FLocked.Free;
  FByteReads.Free;
  FStamps.Free;
  FBytes.Free;
  FTexts.Free;
  inherited;
end;

procedure TCountingIndexFileSystem.Put(const AFileName, AText: string; AStamp: Int64);
begin
  FTexts.AddOrSetValue(UpperCase(AFileName), AText);
  FStamps.AddOrSetValue(UpperCase(AFileName), AStamp);
end;

function TCountingIndexFileSystem.ByteReads(const AFileName: string): Integer;
begin
  TMonitor.Enter(Self);
  try
    if not FByteReads.TryGetValue(UpperCase(AFileName), Result) then
    begin
      Result := 0;
    end;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TCountingIndexFileSystem.FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
begin
  TMonitor.Enter(Self);
  try
    Result := FStamps.TryGetValue(UpperCase(AFileName), AStamp);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TCountingIndexFileSystem.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  TMonitor.Enter(Self);
  try
    Result := FTexts.TryGetValue(UpperCase(AFileName), AText);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TCountingIndexFileSystem.WriteText(const AFileName, AText: string): Boolean;
begin
  TMonitor.Enter(Self);
  try
    FTexts.AddOrSetValue(UpperCase(AFileName), AText);
    FStamps.AddOrSetValue(UpperCase(AFileName), 1);
    Result := True;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TCountingIndexFileSystem.ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
var
  mReads: Integer;
begin
  TMonitor.Enter(Self);
  try
    if not FByteReads.TryGetValue(UpperCase(AFileName), mReads) then
    begin
      mReads := 0;
    end;
    FByteReads.AddOrSetValue(UpperCase(AFileName), mReads + 1);
    Result := FBytes.TryGetValue(UpperCase(AFileName), ABytes);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TCountingIndexFileSystem.WriteBytes(const AFileName: string; const ABytes: TBytes;
  out AError: string): Boolean;
var
  mStamp: Int64;
begin
  AError := '';
  TMonitor.Enter(Self);
  try
    FBytes.AddOrSetValue(UpperCase(AFileName), ABytes);
    // Jedes Schreiben ändert den Zeitstempel wie auf der Platte.
    if not FStamps.TryGetValue(UpperCase(AFileName), mStamp) then
    begin
      mStamp := 0;
    end;
    FStamps.AddOrSetValue(UpperCase(AFileName), mStamp + 1);
    Result := True;
  finally
    TMonitor.Exit(Self);
  end;
end;

type
  /// <summary>Sperre aus TCountingIndexFileSystem.TryLockWrite; gibt beim Freigeben frei.</summary>
  TCountingWriteLock = class(TInterfacedObject)
  private
    FFiles: TCountingIndexFileSystem;
    FFileName: string;
  public
    constructor Create(AFiles: TCountingIndexFileSystem; const AFileName: string);
    destructor Destroy; override;
  end;

constructor TCountingWriteLock.Create(AFiles: TCountingIndexFileSystem; const AFileName: string);
begin
  inherited Create;
  FFiles := AFiles;
  FFileName := AFileName;
end;

destructor TCountingWriteLock.Destroy;
begin
  FFiles.Unlock(FFileName);
  inherited;
end;

function TCountingIndexFileSystem.TryLockWrite(const AFileName: string): IInterface;
begin
  TMonitor.Enter(Self);
  try
    if FLocked.ContainsKey(UpperCase(AFileName)) then
    begin
      Exit(nil);
    end;
    FLocked.Add(UpperCase(AFileName), True);
  finally
    TMonitor.Exit(Self);
  end;
  Result := TCountingWriteLock.Create(Self, AFileName);
end;

procedure TCountingIndexFileSystem.Unlock(const AFileName: string);
begin
  TMonitor.Enter(Self);
  try
    FLocked.Remove(UpperCase(AFileName));
  finally
    TMonitor.Exit(Self);
  end;
end;

/// <summary>Installation für FilesOf und RequestOf: $(BDS) = ARoot, Quellpfade AFolders.</summary>
type
  TFakeInstallation = class(TInterfacedObject, ILibraryPathProvider)
  private
    FRoot: string;
    FFolders: TArray<string>;
  public
    constructor Create(const ARoot: string; const AFolders: TArray<string>);
    function LibraryPaths(const APlatform: string): TArray<string>;
    function BrowsingPaths(const APlatform: string): TArray<string>;
    function Variables: TArray<TPair<string, string>>;
  end;

constructor TFakeInstallation.Create(const ARoot: string; const AFolders: TArray<string>);
begin
  inherited Create;
  FRoot := ARoot;
  FFolders := AFolders;
end;

function TFakeInstallation.LibraryPaths(const APlatform: string): TArray<string>;
begin
  Result := nil;
end;

function TFakeInstallation.BrowsingPaths(const APlatform: string): TArray<string>;
begin
  Result := FFolders;
end;

function TFakeInstallation.Variables: TArray<TPair<string, string>>;
begin
  Result := [TPair<string, string>.Create('BDS', FRoot)];
end;

const
  cLibraryCache = 'C:\Cache\Bibliothek\index.dpccidx';
  cProjectCache = 'C:\Cache\Projekt\index.dpccidx';

function ResolveLibraryUnit(const AUnitName: string): string;
begin
  Result := 'C:\Lib\' + AUnitName + '.pas';
end;

{ TDpccMemoryPhase1Tests }

procedure TDpccMemoryPhase1Tests.WarmUp;
var
  mReads, mSecond, mSkipped, mFromCache: Integer;
  mWithout, mWith: TArray<string>;
  mWithoutCache, mWithCache: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Katalog und Leser der Einstellungen legen beim ersten Mal Tabellen an.
  TDpccSettingsCatalog.CreateDefault.Free;
  TConfigurationParser.Parse('{"index": {"officeAndWinRt": true}}', mIssues);
  FFiles := TCountingIndexFileSystem.Create;
  FFileSystem := FFiles;
  FFiles.Put('C:\P\P.dpr', 'program P;'#10'uses B;'#10'begin end.', 1);
  FFiles.Put('C:\Lib\B.pas', 'unit B;'#10'interface'#10'type TB = class end;'#10'implementation'#10'end.', 1);
  FFiles.Put('C:\Lib\C.pas', 'unit C;'#10'interface'#10'type TC = class end;'#10'implementation'#10'end.', 1);
  // Erster Lauf: schreibt den Bibliotheks-Cache und merkt seinen Stand (TSharedCacheWrites gilt prozessweit); der
  // zweite merkt ihn wie im Test beim Lesen, damit dort nichts Neues hinzukommt.
  RunCacheScenario(mReads, mSecond, mSkipped, mFromCache);
  RunCacheScenario(mReads, mSecond, mSkipped, mFromCache);
  FFolder := TPath.Combine(TPath.GetTempPath, 'dpcc-c1-' + IntToStr(MainThreadID));
  ForceDirectories(TPath.Combine(FFolder, 'source\rtl\sys'));
  ForceDirectories(TPath.Combine(FFolder, 'OCX\Servers'));
  ForceDirectories(TPath.Combine(FFolder, 'source\rtl\win\winrt'));
  TFile.WriteAllText(TPath.Combine(FFolder, 'source\rtl\sys\System.Probe.pas'), 'unit System.Probe;');
  TFile.WriteAllText(TPath.Combine(FFolder, 'OCX\Servers\Word2099.pas'), 'unit Word2099;');
  TFile.WriteAllText(TPath.Combine(FFolder, 'source\rtl\win\winrt\WinAPI.Probe.pas'), 'unit WinAPI.Probe;');
  // Ordnerlisten merkt sich der Server prozessweit.
  RunFilesScenario(mWithout, mWith, mWithoutCache, mWithCache);
end;

procedure TDpccMemoryPhase1Tests.CleanUp;
begin
  FFileSystem := nil;
  FFiles := nil;
  if (FFolder <> '') and TDirectory.Exists(FFolder) then
  try
    TDirectory.Delete(FFolder, True);
  except
    // Ein Rest im Temp-Ordner stört keinen Test.
    on Exception do
      ;
  end;
end;

procedure TDpccMemoryPhase1Tests.RunCacheScenario(out AFirstReads, ASecondReads, ASkipped,
  AFirstFromCache: Integer);
var
  mIndex: ISymbolIndex;
  mService: TIndexService;
  mRequest: TIndexRequest;
  mSkipped, mFromCache, mBefore: Integer;
begin
  mIndex := TSymbolIndex.Create;
  mSkipped := 0;
  mFromCache := -1;
  mService := TIndexService.Create(mIndex, FFileSystem);
  try
    mService.OnCacheSkipped :=
      procedure(const AFileName: string)
      begin
        if SameText(AFileName, cLibraryCache) then
        begin
          Inc(mSkipped);
        end;
      end;
    mService.OnFinished :=
      procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
      begin
        if mFromCache < 0 then
        begin
          mFromCache := AResult.FromCache;
        end;
      end;
    mRequest := Default(TIndexRequest);
    // Mit Symbolen wie im Projekt: Ohne Defines hätte keine Unit einen Schlüssel, und der Builder übernähme keine
    // unverändert (TIndexBuilder.Keeps).
    mRequest.Defines := ['DEBUG', 'MSWINDOWS'];
    mRequest.LibraryDefines := ['MSWINDOWS', 'WIN32'];
    mRequest.Files := ['C:\P\P.dpr'];
    mRequest.LibraryFiles := ['C:\Lib\B.pas', 'C:\Lib\C.pas'];
    mRequest.LibraryRoots := ['C:\Lib'];
    mRequest.ResolveUnit := ResolveLibraryUnit;
    mRequest.CacheFile := cProjectCache;
    mRequest.LibraryCacheFile := cLibraryCache;
    mBefore := FFiles.ByteReads(cLibraryCache);
    mService.Start(mRequest);
    mService.WaitFor;
    AFirstReads := FFiles.ByteReads(cLibraryCache) - mBefore;
    mBefore := FFiles.ByteReads(cLibraryCache);
    // Wie ein Neuaufbau nach „.dproj gespeichert“: derselbe Auftrag, derselbe Index.
    mService.Start(mRequest);
    mService.WaitFor;
    ASecondReads := FFiles.ByteReads(cLibraryCache) - mBefore;
  finally
    mService.Free;
  end;
  ASkipped := mSkipped;
  AFirstFromCache := mFromCache;
end;

procedure TDpccMemoryPhase1Tests.RunFilesScenario(out AWithout, AWith: TArray<string>; out AWithoutCache,
  AWithCache: string);
var
  mLoaded: TShellLoadedProject;
  mSettings: TServerSettings;
  mFiles: TShellIndexFiles;
  mTarget: TShellRequestTarget;
begin
  mLoaded := Default(TShellLoadedProject);
  mLoaded.Version := '37.0';
  mLoaded.Project.FileName := TPath.Combine(FFolder, 'P.dproj');
  mLoaded.Project.Platform := 'Win32';
  mLoaded.Installation := TFakeInstallation.Create(FFolder, [TPath.Combine(FFolder, 'source\rtl\sys'),
    TPath.Combine(FFolder, 'OCX\Servers'), TPath.Combine(FFolder, 'source\rtl\win\winrt')]);
  mSettings := TServerSettings.Default;
  mTarget := Default(TShellRequestTarget);
  mTarget.CacheRoot := 'C:\Cache';
  mFiles := TShellIndexRequests.FilesOf(mLoaded, mSettings);
  AWithout := mFiles.LibraryFiles;
  mTarget.OfficeAndWinRt := mSettings.IndexOfficeAndWinRt;
  AWithoutCache := TShellIndexRequests.RequestOf(mLoaded, mFiles, mTarget).LibraryCacheFile;
  mSettings.IndexOfficeAndWinRt := True;
  mFiles := TShellIndexRequests.FilesOf(mLoaded, mSettings);
  AWith := mFiles.LibraryFiles;
  mTarget.OfficeAndWinRt := True;
  AWithCache := TShellIndexRequests.RequestOf(mLoaded, mFiles, mTarget).LibraryCacheFile;
end;

procedure TDpccMemoryPhase1Tests.NewTreeVariantReplacesOlder;
var
  mDocument: ITextDocument;
  mCalls: Integer;
  mFactory: TFunc<IInterface>;
begin
  mDocument := TTextDocument.Create('file:///C:/P/A.pas', 'pascal', 1, 'unit A;');
  mCalls := 0;
  mFactory :=
    function: IInterface
    begin
      Inc(mCalls);
      Result := TInterfacedObject.Create;
    end;
  mDocument.Derived('pascal.syntaxtree|DEBUG', mFactory);
  mDocument.Derived('pascal.syntaxtree|DEBUG', mFactory);
  Assert.AreEqual(1, mCalls, 'derselbe Stand aus dem Dokument');
  mDocument.Derived('pascal.syntaxtree.all', mFactory);
  Assert.AreEqual(2, mCalls, 'andere Art');
  mDocument.Derived('pascal.syntaxtree|RELEASE', mFactory);
  Assert.AreEqual(3, mCalls, 'neuer Stand');
  mDocument.Derived('pascal.syntaxtree.all', mFactory);
  Assert.AreEqual(3, mCalls, 'die andere Art bleibt');
  mDocument.Derived('pascal.syntaxtree|DEBUG', mFactory);
  Assert.AreEqual(4, mCalls, 'der frühere Stand ist ersetzt');
end;

procedure TDpccMemoryPhase1Tests.HeldLibraryCacheIsNotReadAgain;
var
  mFirstReads, mSecondReads, mSkipped, mFromCache: Integer;
begin
  RunCacheScenario(mFirstReads, mSecondReads, mSkipped, mFromCache);
  Assert.AreEqual(1, mFirstReads, 'frischer Index: Bibliotheks-Cache gelesen');
  Assert.AreEqual(3, mFromCache, 'P, B und C aus den Caches');
  Assert.AreEqual(0, mSecondReads, 'Index hält den Stand: nicht noch einmal gelesen');
  Assert.AreEqual(1, mSkipped, 'OnCacheSkipped');
end;

procedure TDpccMemoryPhase1Tests.OfficeAndWinRtOffByDefault;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
  mRouted: TDpccRoutedSetting;
  mCatalog: TDpccSettingsCatalog;
begin
  Assert.IsFalse(TServerSettings.Default.IndexOfficeAndWinRt, 'Server: Vorgabe aus');
  mSettings := TConfigurationParser.Parse('{"index": {"officeAndWinRt": true}}', mIssues);
  Assert.IsTrue(mSettings.IndexOfficeAndWinRt, 'index.officeAndWinRt aus settings.json');
  Assert.AreEqual(0, Integer(Length(mIssues)), 'ohne Meldung');
  Assert.IsFalse(TDpccPluginSettings.Defaults.IndexOfficeAndWinRt, 'Plugin: Vorgabe aus');
  Assert.IsTrue(TDpccSettingsScopes.TryRouted('IndexOfficeAndWinRt', mRouted), 'umgeleitet');
  Assert.AreEqual('index.officeAndWinRt', mRouted.Path, 'Schlüssel');
  Assert.IsTrue(mRouted.Flag, 'Wahrheitswert');
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    Assert.IsTrue(TDpccCompletionView.ShowsName(mCatalog, 'IndexOfficeAndWinRt'), 'auf der Optionsseite');
  finally
    mCatalog.Free;
  end;
end;

procedure TDpccMemoryPhase1Tests.OfficeAndWinRtLeftOutOfLibrary;
var
  mWithout, mWith: TArray<string>;
  mWithoutCache, mWithCache: string;
  mJoined: string;
begin
  RunFilesScenario(mWithout, mWith, mWithoutCache, mWithCache);
  mJoined := string.Join(';', mWithout);
  Assert.Contains(mJoined, 'System.Probe.pas', 'übrige Bibliothek bleibt');
  Assert.IsFalse(ContainsText(mJoined, 'Word2099'), 'OCX\Servers ohne Schalter');
  Assert.IsFalse(ContainsText(mJoined, 'WinAPI.Probe'), 'WinRT ohne Schalter');
  Assert.AreEqual(3, Integer(Length(mWith)), 'mit Schalter alles');
  Assert.AreNotEqual(mWithoutCache, mWithCache, 'eigener Bibliotheks-Cache');
  Assert.IsTrue(TShellIndexRequests.IsRarelyUsed(TPath.Combine(FFolder, 'ocx\servers\X.pas'),
    [IncludeTrailingPathDelimiter(TPath.Combine(FFolder, 'OCX\Servers'))]), 'ohne Groß-/Kleinschreibung');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccMemoryPhase1Tests);

end.
