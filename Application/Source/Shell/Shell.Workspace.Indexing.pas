unit Shell.Workspace.Indexing;

// Internals-Rolle Shell: Indexaufbau eines Arbeitsbereichs. Startet den Aufbau eines geladenen Projekts in den
// gemeinsamen Symbolindex (#648), mit Unit-Suche (#1016), Packages (#46), Cache-Sperre (#62, #184) und
// Fortschritt, und meldet Ende, Fehler und Cache-Ereignisse an Protokoll, Diagnoselog (#647) und Zustand.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Common.Logging.Contract,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Lsp.WorkDoneProgress,
  dpcc.Common.Projects.UnitResolver,
  dpcc.Common.Projects.PackageLocator,
  dpcc.Common.Index.Contract,
  dpcc.Common.Index.Builder,
  dpcc.Common.Index.Service,
  dpcc.Common.Index.Scheduler,
  Shell.Workspace.Setup,
  Shell.Workspace.State,
  Shell.Workspace.Cache,
  Shell.Workspace.Loader,
  Shell.Workspace.Encodings;

type
  /// <summary>Teile des Arbeitsbereichs, mit denen der Aufbau arbeitet; sie gehören dem Arbeitsbereich.</summary>
  TShellIndexingParts = record
    Name: string;
    Root: string;
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    Index: ISymbolIndex;
    ProgressToken: string;
    Setup: TShellWorkspaceSetup;
    Events: TShellWorkspaceEvents;
    State: TShellProjectState;
    Cache: TShellWorkspaceCache;
  end;

  TShellWorkspaceIndexing = class
  private
    FParts: TShellIndexingParts;
    FService: TIndexService;
    FProgress: TLspWorkDoneProgress;
    FEncodings: TShellEncodingReport;
    /// <summary>Schlüssel und Unit-Listen des letzten Aufbaus; gleich = nicht neu starten.</summary>
    FSignature: string;
    /// <summary>Beim nächsten Aufbau den Cache verwerfen (#49).</summary>
    FDiscardCache: Boolean;
    /// <summary>index.officeAndWinRt des letzten Aufbaus (c1).</summary>
    FOfficeAndWinRt: Boolean;
    /// <summary>Nimmt die Bibliotheks-Units unter TShellIndexRequests.RarelyUsedRoots aus dem Index, wenn
    /// index.officeAndWinRt eben ausgeschaltet wurde (c1): Sonst schlüge „+ Unit“ sie bis zum Neustart weiter vor.
    /// Über uses erreichte liest der Aufbau gleich wieder ein.</summary>
    procedure DropRarelyUsed(const ALoaded: TShellLoadedProject);
    procedure Attach;
    procedure ProjectReady(const AResult: TIndexBuildResult; AElapsedMs: Int64);
    procedure Finished(const AResult: TIndexBuildResult; AElapsedMs: Int64);
    procedure CacheWritten(ALibrary: Boolean; AUnits: Integer; ABytes, AElapsedMs: Int64);
    procedure CacheRejected(const AFileName, AReason: string);
    procedure CacheNotWritten(const AFileName, AReason: string);
    procedure Failed(const AError: Exception);
    procedure IndexEvent(const AText: string);
    /// <summary>Package-Locator und Unit-Suche des Projekts in den Zustand (#46, #1016).</summary>
    function PublishLookups(const ALoaded: TShellLoadedProject): TPackageLocator;
    /// <summary>Resolver des neuen Aufbaus; er lebt, solange Auftrag und Builder ihn über den Rückruf halten (a3).
    /// </summary>
    function NewResolver(const ALoaded: TShellLoadedProject): TUnitFileResolver;
    /// <summary>Sperre, Warten auf den Schreiber (#62) und Verwerfen (#49) des Caches.</summary>
    procedure PrepareCache(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings;
      var ARequest: TIndexRequest);
    procedure Publish(const ALoaded: TShellLoadedProject; const ARequest: TIndexRequest);
  public
    constructor Create(const AParts: TShellIndexingParts);
    destructor Destroy; override;
    /// <summary>Startet den Aufbau für ALoaded; False, wenn sich Schlüssel und Unit-Listen seit dem letzten nicht
    /// geändert haben. Bricht einen laufenden Aufbau ab, ohne auf ihn zu warten (#874).</summary>
    function Start(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings): Boolean;
    /// <summary>Nächster Start baut auch bei gleichem Schlüssel neu auf.</summary>
    procedure Forget;
    /// <summary>Nächster Start verwirft den Cache (#49).</summary>
    procedure DiscardNext;
    procedure Stop;
    function EnsureUnit(const AUnitName: string): Boolean;
    function ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
    function ApplyText(const AFileName, AText: string): Boolean;
    /// <summary>Fortschritt des laufenden Aufbaus in Prozent; -1, wenn keiner läuft (#647).</summary>
    function Loading: Integer;
    /// <summary>Stufe des laufenden Aufbaus und ob er auf sie wartet (#2142).</summary>
    function Stage: TIndexStageState;
    /// <summary>Token der $/progress-Meldungen dieses Arbeitsbereichs (#2142).</summary>
    function ProgressToken: string;
    /// <summary>Der gemeinsame Symbolindex.</summary>
    function Index: ISymbolIndex;
  end;

implementation

uses
  Shell.Workspace.Requests,
  System.StrUtils,
  dpcc.Common.Index.Adapters.DiskFileSystem,
  dpcc.Common.Index.Adapters.CacheDirectory,
  dpcc.Common.Index.Processes,
  dpcc.Common.Index.ProjectFiles,
  dpcc.Common.Projects.UnitAliases,
  Shell.Platform,
  Shell.Diagnostics,
  Shell.Workspace.Listings,
  Shell.Workspace.Packages,
  dpcc.Text.LogMarks,
  dpcc.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TWorkspaceIndexingText = (FromCache, Failed);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TWorkspaceIndexingText] of TDpccText = (
    (De: 'Stand übernommen (%d Units aus dem Cache)'; En: 'State taken over (%d units from the cache)'),
    (De: 'Fehlgeschlagen'; En: 'Failed'));

const
  /// <summary>So lange wartet ein lesender Prozess höchstens auf den Cache des schreibenden (#62).</summary>
  cCacheWaitMs = 120000;

/// <summary>Private Bytes des Prozesses in MB (a0); 0, wenn die Abfrage scheitert. GetMemoryManagerState meldete in
/// der IDE immer 0 (gemeinsamer Speichermanager borlndmm.dll).</summary>
function PrivateMegaBytes: Int64;
var
  mMemory: TProcessMemory;
begin
  mMemory := TProcessInfo.Memory;
  Result := 0;
  if mMemory.Valid then
  begin
    Result := mMemory.PrivateBytes div (1024 * 1024);
  end;
end;

/// <summary>Neu eingelesene Units nach Grund und belegter Speicher (Private Bytes), fürs Diagnoselog (Rückmeldung
/// 22.10.2026).</summary>
function MissText(const AResult: TIndexBuildResult): string;
begin
  Result := Format(' new %d changed %d includes %d usages %d compact %d damaged %d mem %d MB',
    [AResult.Misses[TIndexCacheMiss.NoEntry], AResult.Misses[TIndexCacheMiss.Changed],
     AResult.Misses[TIndexCacheMiss.Includes], AResult.Misses[TIndexCacheMiss.Usages],
     AResult.Misses[TIndexCacheMiss.Compact], AResult.Misses[TIndexCacheMiss.Damaged],
     PrivateMegaBytes]);
end;

/// <summary>Art des Caches an seinem Ordner: AProject, ALibrary oder ASearch.</summary>
function CacheKindOf(const AFileName, AProject, ALibrary, ASearch: string): string;
begin
  Result := AProject;
  if Pos(PathDelim + TIndexCacheDirectory.cLibraryFolder + PathDelim, AFileName) > 0 then
  begin
    Result := ALibrary;
  end
  else if Pos(PathDelim + TIndexCacheDirectory.cSearchFolder + PathDelim, AFileName) > 0 then
  begin
    Result := ASearch;
  end;
end;

type
  /// <summary>Hält einen TUnitResolver für den Rückruf TIndexRequest.ResolveUnit (a3): Der alte Builder bedient
  /// EnsureUnit, bis der neue veröffentlicht ist, und ruft ihn dabei noch auf. Frei wird er mit dem letzten Halter,
  /// also wenn der nächste Aufbau den alten Builder und Auftrag freigibt; vorher blieben alle früheren bis zur
  /// Freigabe des Arbeitsbereichs.</summary>
  IUnitResolverHold = interface
    ['{B3E1A6F2-5C47-4D9B-8E21-7F0A4C3D9B56}']
    function Resolver: TUnitResolver;
  end;

  TUnitResolverHold = class(TInterfacedObject, IUnitResolverHold)
  private
    FResolver: TUnitResolver;
  public
    constructor Create(AResolver: TUnitResolver);
    destructor Destroy; override;
    function Resolver: TUnitResolver;
  end;

constructor TUnitResolverHold.Create(AResolver: TUnitResolver);
begin
  inherited Create;
  FResolver := AResolver;
end;

destructor TUnitResolverHold.Destroy;
begin
  FResolver.Free;
  inherited;
end;

function TUnitResolverHold.Resolver: TUnitResolver;
begin
  Result := FResolver;
end;

/// <summary>Rückruf für TIndexRequest.ResolveUnit; fängt nur den Halter ein.</summary>
function ResolveUnitOf(const AHold: IUnitResolverHold): TUnitFileResolver;
begin
  Result :=
    function(const AUnitName: string): string
    begin
      Result := AHold.Resolver.Resolve(AUnitName);
    end;
end;

/// <summary>Rückruf für TIndexRequest.CacheBusy; fängt nur die Datei ein.</summary>
function CacheBusyOf(const ACacheFile: string): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := TIndexCacheDirectory.IsLocked(ACacheFile);
    end;
end;

{ TShellWorkspaceIndexing }

constructor TShellWorkspaceIndexing.Create(const AParts: TShellIndexingParts);
begin
  inherited Create;
  FParts := AParts;
  FEncodings := TShellEncodingReport.Create(AParts.Name, AParts.Root, AParts.Logger, AParts.Transport, AParts.Index);
  // Eine Platte für alle Arbeitsbereiche (b1): Nur so teilen sie den gelesenen Bibliotheks-Cache und seinen Stand.
  FService := TIndexService.Create(AParts.Index, TDiskIndexFileSystem.Shared);
  FProgress := TLspWorkDoneProgress.Create(AParts.Transport, AParts.ProgressToken);
  Attach;
end;

destructor TShellWorkspaceIndexing.Destroy;
begin
  FService.Free;
  FProgress.Free;
  FEncodings.Free;
  FParts := Default(TShellIndexingParts);
  inherited;
end;

procedure TShellWorkspaceIndexing.Attach;
begin
  FService.OnProgress := FProgress.AsIndexProgress();
  FService.OnProjectReady :=
    procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
    begin
      ProjectReady(AResult, AElapsedMs);
    end;
  FService.OnFinished :=
    procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
    begin
      Finished(AResult, AElapsedMs);
    end;
  FService.OnCacheWritten :=
    procedure(ALibrary: Boolean; AUnits: Integer; ABytes, AElapsedMs: Int64)
    begin
      CacheWritten(ALibrary, AUnits, ABytes, AElapsedMs);
    end;
  FService.OnCacheRejected :=
    procedure(const AFileName, AReason: string)
    begin
      CacheRejected(AFileName, AReason);
    end;
  FService.OnCacheNotWritten :=
    procedure(const AFileName, AReason: string)
    begin
      CacheNotWritten(AFileName, AReason);
    end;
  // b1: Der Index hielt den Stand des gemeinsamen Caches schon; nicht noch einmal gelesen.
  FService.OnCacheSkipped :=
    procedure(const AFileName: string)
    begin
      IndexEvent(Format('index project#%d cache skipped %s', [FParts.Setup.Priority,
        CacheKindOf(AFileName, 'project', 'library', 'search')]));
    end;
  FService.OnError :=
    procedure(const AError: Exception)
    begin
      Failed(AError);
    end;
end;

procedure TShellWorkspaceIndexing.IndexEvent(const AText: string);
begin
  FParts.Events.IndexEvent(AText);
end;

procedure TShellWorkspaceIndexing.ProjectReady(const AResult: TIndexBuildResult; AElapsedMs: Int64);
begin
  FParts.State.ProjectPending := False;
  IndexEvent(Format('index project#%d projectStage %d ms parsed %d cached %d missing %d',
    [FParts.Setup.Priority, AElapsedMs, AResult.Parsed, AResult.FromCache, AResult.Missing]) + MissText(AResult));
  FParts.Events.ProjectReady;
end;

procedure TShellWorkspaceIndexing.Finished(const AResult: TIndexBuildResult; AElapsedMs: Int64);
begin
  // Abgebrochen (Neustart): Der neue Aufbau hat ProjectPending schon wieder gesetzt.
  if not AResult.Cancelled then
  begin
    FParts.State.ProjectPending := False;
    FParts.State.Finished(AResult, AElapsedMs);
  end;
  IndexEvent(Format('index project#%d done %d ms parsed %d cached %d missing %d units %d resolve %d ms parse %d ms%s',
    [FParts.Setup.Priority, AElapsedMs, AResult.Parsed, AResult.FromCache, AResult.Missing, FParts.Index.UnitCount,
     AResult.ResolveMs, AResult.ParseMs, IfThen(AResult.Cancelled, ' cancelled', '')]) + MissText(AResult));
  FParts.Logger.Info(Format('Symbolindex für %s fertig in %d ms: %d Units, %d Symbole (%d neu eingelesen, %d aus dem Cache, %d fehlen)%s; Speicher: %s',
    [TLogMarks.Name(FParts.Name), AElapsedMs, FParts.Index.UnitCount, FParts.Index.SymbolCount, AResult.Parsed,
     AResult.FromCache, AResult.Missing, IfThen(AResult.Cancelled, ', abgebrochen', ''),
     TShellMemoryReport.Take(FParts.Index, nil, -1).LogText]));
  if AResult.Cancelled then
  begin
    Exit;
  end;
  // Prozesse am Projekt (#62): Der Schreiber hat gespeichert, ein Leser den Stand übernommen.
  if FParts.Cache.Writes then
  begin
    FParts.Cache.Report(TIndexProcessInfo.cStateReady, True, Format('Index gespeichert (%d Units)',
      [AResult.Parsed + AResult.FromCache]));
  end
  else
  begin
    FParts.Cache.Report(TIndexProcessInfo.cStateReady, False,
      cTexts[TWorkspaceIndexingText.FromCache].Fmt([AResult.FromCache]));
  end;
  FEncodings.Report(FParts.State.ProjectFiles);
  FParts.Events.IndexFinished;
end;

procedure TShellWorkspaceIndexing.CacheWritten(ALibrary: Boolean; AUnits: Integer; ABytes, AElapsedMs: Int64);
begin
  // Wie oft und wie groß geschrieben wird (Rückmeldung 22.10.2026); ohne Pfad. Das Zeilenformat ist festgelegt
  // (#1478, docs/Diagnose.md): Einheiten außer „MB“ am Ende klein, damit ^\S+ index project#\d+ \w+ [\d a-z]+ mem \d+
  // MB$
  // jede Speicherzeile trifft.
  IndexEvent(Format('index project#%d cacheWrite %s units %d %d kb %d ms mem %d MB',
    [FParts.Setup.Priority, IfThen(ALibrary, 'library', 'project'), AUnits, ABytes div 1024, AElapsedMs,
     PrivateMegaBytes]));
end;

procedure TShellWorkspaceIndexing.CacheRejected(const AFileName, AReason: string);
begin
  // Still neu aufbauen (#492): nur ins Log, keine Meldung an den Benutzer. Ohne Pfad: Das Log bleibt
  // anonym (der Cache liegt im Benutzerprofil). Welcher Cache und warum, steht auch im Diagnose-Log: Ohne
  // Grund war nicht zu sehen, warum ein Rechner bei jedem Start alles neu aufbaut (29.10.2026). Die Gründe
  // von TIndexCache.ReadEntries enthalten keinen Pfad.
  FParts.Logger.Info(Format('Index-Cache verworfen (%s); wird neu aufgebaut', [AReason]));
  IndexEvent(Format('index project#%d cache rejected %s reason %s', [FParts.Setup.Priority,
    CacheKindOf(AFileName, 'project', 'library', 'search'), AReason]));
  FParts.Cache.Report(TIndexProcessInfo.cStateBuilding, FParts.Cache.Writes, Format('Cache verworfen (%s)', [AReason]));
end;

procedure TShellWorkspaceIndexing.CacheNotWritten(const AFileName, AReason: string);
var
  mKind: string;
begin
  // Früher still. Der nächste Aufbau liest die fehlenden Units neu; ohne Pfad ins Log.
  mKind := CacheKindOf(AFileName, 'Projekt', 'Bibliothek', 'Suchpfade');
  FParts.Logger.Warning(Format('Index-Cache (%s) nicht geschrieben: %s', [mKind, AReason]));
  IndexEvent('index cache not written ' + mKind);
end;

procedure TShellWorkspaceIndexing.Failed(const AError: Exception);
begin
  // Sonst bliebe workspace/diagnostic bis zum nächsten Reload bei indexLoading.
  // Start hält den alten Lauf an, bevor es ProjectPending setzt: Das hier trifft nur den eigenen.
  FParts.State.ProjectPending := False;
  FParts.Logger.Error(Format('Fehler beim Aufbau des Symbolindex für %s: %s: %s', [TLogMarks.Name(FParts.Name),
    AError.ClassName,
      TLogMarks.Text(AError.Message)]));
  IndexEvent(Format('index project#%d failed %s', [FParts.Setup.Priority, AError.ClassName]));
  try
    // Ohne aktiven Fortschritt ein No-op.
    FProgress.Finish(cTexts[TWorkspaceIndexingText.Failed].Text);
  except
    // Transport schon geschlossen: Das Log genügt.
  end;
  // Teilweise aufgebauter Index: Syntaxprüfung und Pull-Diagnosen sollen ihn trotzdem nutzen.
  FParts.Events.IndexFinished;
end;

function TShellWorkspaceIndexing.PublishLookups(const ALoaded: TShellLoadedProject): TPackageLocator;
var
  mSource: TShellUnitLookupSource;
begin
  // requires-Packages (#46): Quelle .dpk in den Ordnern der Gruppe, im Projektordner und in den Suchpfaden,
  // übersetzt .dcp in den Bibliothekspfaden.
  Result := TPackageLocator.Create(FParts.Setup.PackageFolders + [ExtractFileDir(ALoaded.ProjectFile)] +
    ALoaded.Project.SearchPaths + ALoaded.CompilerLibraryPaths);
  mSource := Default(TShellUnitLookupSource);
  mSource.Project := ALoaded.Project;
  mSource.Installation := ALoaded.Installation;
  mSource.LibraryPaths := ALoaded.CompilerLibraryPaths;
  mSource.Packages := TPackageLocatorHold.Create(Result);
  mSource.Index := FParts.Index;
  // Unit-Aliase der .dproj (DCC_UnitAlias) für Namensauflösung und Vorschläge; die Vorgaben kennt der Index.
  FParts.Index.AddUnitAliases(TUnitAliases.OfProject(ALoaded.Project));
  if Assigned(FParts.Setup.OnGroupProjects) then
  begin
    mSource.GroupOutputsOf := TShellPackageLookups.GroupOutputsOf(FParts.Setup.OnGroupProjects,
      ALoaded.ProjectFile, ALoaded.Options, FParts.Logger);
  end;
  FParts.State.SetLookups(mSource.Packages, TShellPackageLookups.UnitLookupFor(mSource));
end;

function TShellWorkspaceIndexing.NewResolver(const ALoaded: TShellLoadedProject): TUnitFileResolver;
var
  mResolver: TUnitResolver;
begin
  mResolver := TUnitResolver.Create(ALoaded.Project, ALoaded.LibraryPaths, TShellFileAccess.ExistsFunc());
  // Ordner einmal auflisten, über alle Projekte geteilt (CPU beim Start).
  mResolver.ListUnits := TSharedUnitListings.ListFunc();
  // Anfragen können den alten Builder noch nutzen (EnsureUnit ohne Sperre, #647): Er hält seinen Resolver selbst.
  Result := ResolveUnitOf(TUnitResolverHold.Create(mResolver));
end;

procedure TShellWorkspaceIndexing.PrepareCache(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings;
  var ARequest: TIndexRequest);
var
  mFiles: TShellCacheFiles;
begin
  mFiles := TShellCacheFiles.Create(ARequest.CacheFile, ARequest.LibraryCacheFile, ARequest.SearchCacheFile);
  ARequest.ReadOnlyCache := not FParts.Cache.Lock(mFiles, TShellIndexRequests.CacheOriginOf(ALoaded.Project,
    FParts.Root), ASettings);
  if ARequest.ReadOnlyCache then
  begin
    FParts.Logger.Info(Format('Cache %s wird von einer anderen Instanz geschrieben und hier nur gelesen',
      [TLogMarks.Path(ARequest.CacheFile)]));
    // Auf deren Stand warten statt alles doppelt zu lesen (#62), begrenzt.
    ARequest.CacheBusy := CacheBusyOf(ARequest.CacheFile);
    ARequest.CacheWaitMs := cCacheWaitMs;
  end;
  if FDiscardCache then
  begin
    FDiscardCache := False;
    // Im Index-Thread nach dem Ende des alten Aufbaus löschen: Sonst schriebe er den Cache danach wieder.
    if not ARequest.ReadOnlyCache then
    begin
      ARequest.Prepare := TShellWorkspaceCache.DiscardFiles(mFiles, FParts.Logger);
    end;
  end;
end;

procedure TShellWorkspaceIndexing.Publish(const ALoaded: TShellLoadedProject; const ARequest: TIndexRequest);
var
  mFiles: TShellIndexedFiles;
begin
  mFiles.Defines := ARequest.Defines;
  mFiles.Namespaces := ALoaded.Project.Namespaces;
  mFiles.SearchPaths := ALoaded.Project.SearchPaths;
  mFiles.ProjectFiles := ARequest.Files;
  mFiles.SearchFiles := ARequest.SearchFiles;
  FParts.State.SetIndexedFiles(mFiles);
  FParts.Cache.SetFiles(TShellCacheFiles.Create(ARequest.CacheFile, ARequest.LibraryCacheFile, ''));
end;

function TShellWorkspaceIndexing.Start(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings): Boolean;
var
  mFiles: TShellIndexFiles;
  mTarget: TShellRequestTarget;
  mRequest: TIndexRequest;
  mKey: string;
begin
  mFiles := TShellIndexRequests.FilesOf(ALoaded, ASettings);
  TShellIndexRequests.AddPackageFiles(ALoaded.Project, PublishLookups(ALoaded), mFiles, FParts.Logger, FParts.Name);
  mKey := mFiles.Key(TIndexProjectFiles.Signature(ALoaded.Project, ALoaded.Version));
  Result := mKey <> FSignature;
  if not Result then
  begin
    Exit;
  end;
  FSignature := mKey;
  if FOfficeAndWinRt and not ASettings.IndexOfficeAndWinRt then
  begin
    DropRarelyUsed(ALoaded);
  end;
  FOfficeAndWinRt := ASettings.IndexOfficeAndWinRt;
  mTarget.CacheRoot := FParts.Setup.CacheRoot;
  mTarget.Priority := FParts.Setup.Priority;
  mTarget.Usages := ASettings.IndexUsages;
  mTarget.OfficeAndWinRt := ASettings.IndexOfficeAndWinRt;
  mRequest := TShellIndexRequests.RequestOf(ALoaded, mFiles, mTarget);
  mRequest.ResolveUnit := NewResolver(ALoaded);
  FService.Scheduler := FParts.Setup.Scheduler;
  PrepareCache(ALoaded, ASettings, mRequest);
  Publish(ALoaded, mRequest);
  FParts.Logger.Info(Format('Symbolindex für %s (%s, %s): %d Projektdateien, %d Units der Suchpfade, %d der Bibliothek, Cache %s',
    [TLogMarks.Path(ALoaded.ProjectFile),
      TLogMarks.Name(ALoaded.Project.Config), TLogMarks.Name(ALoaded.Project.Platform), Length(mRequest.Files),
     Length(mRequest.SearchFiles), Length(mRequest.LibraryFiles), TLogMarks.Path(mRequest.CacheFile)]));
  FParts.Logger.Info('Speicher beim Start des Aufbaus: ' + TShellMemoryReport.Take(FParts.Index, nil, -1).LogText);
  IndexEvent(Format('index project#%d start files %d search %d library %d cache %s',
    [FParts.Setup.Priority, Length(mRequest.Files), Length(mRequest.SearchFiles), Length(mRequest.LibraryFiles),
     IfThen(mRequest.ReadOnlyCache, 'readOnly', 'write')]));
  FParts.State.ProjectPending := True;
  FService.Start(mRequest);
end;

procedure TShellWorkspaceIndexing.DropRarelyUsed(const ALoaded: TShellLoadedProject);
var
  mRoots: TArray<string>;
  mUnit: TCatalogUnit;
  mDropped: Integer;
begin
  mRoots := TShellIndexRequests.RarelyUsedRoots(ALoaded);
  if Length(mRoots) = 0 then
  begin
    Exit;
  end;
  mDropped := 0;
  // Katalog: auch Units, die nicht geladen sind (Speicher-Optimierung Phase 3).
  for mUnit in FParts.Index.CatalogUnits do
  begin
    if mUnit.Library_ and TShellIndexRequests.IsRarelyUsed(mUnit.FileName, mRoots) then
    begin
      FParts.Index.RemoveFile(mUnit.FileName);
      Inc(mDropped);
    end;
  end;
  if mDropped > 0 then
  begin
    FParts.Logger.Info(Format('%s: index.officeAndWinRt aus, %d Units aus OCX\Servers und WinRT aus dem Index genommen',
      [TLogMarks.Name(FParts.Name), mDropped]));
  end;
end;

procedure TShellWorkspaceIndexing.Forget;
begin
  FSignature := '';
end;

procedure TShellWorkspaceIndexing.DiscardNext;
begin
  FDiscardCache := True;
end;

procedure TShellWorkspaceIndexing.Stop;
begin
  FService.Stop;
end;

function TShellWorkspaceIndexing.EnsureUnit(const AUnitName: string): Boolean;
begin
  Result := FService.EnsureUnit(AUnitName);
end;

function TShellWorkspaceIndexing.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
begin
  Result := FService.ApplyChanges(AChanges);
  if Result > 0 then
  begin
    FParts.State.Touch;
  end;
end;

function TShellWorkspaceIndexing.ApplyText(const AFileName, AText: string): Boolean;
begin
  Result := FService.ApplyText(AFileName, AText);
  if Result then
  begin
    FParts.State.Touch;
  end;
end;

function TShellWorkspaceIndexing.Loading: Integer;
begin
  Result := -1;
  if FProgress.Active then
  begin
    Result := FProgress.Percent;
  end;
end;

function TShellWorkspaceIndexing.Stage: TIndexStageState;
begin
  Result := FService.StageState;
end;

function TShellWorkspaceIndexing.ProgressToken: string;
begin
  Result := FParts.ProgressToken;
end;

function TShellWorkspaceIndexing.Index: ISymbolIndex;
begin
  Result := FParts.Index;
end;

initialization
  TDpccTextTables.Add('Shell.Workspace.Indexing', cTexts);

end.
