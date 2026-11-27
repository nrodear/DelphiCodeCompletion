unit Shell.Workspace.Indexing;

// Internals-Rolle Shell: Indexaufbau eines Arbeitsbereichs. Startet den Aufbau eines geladenen Projekts in den
// gemeinsamen Symbolindex (#648), mit Unit-Suche (#1016), Packages (#46), Cache-Sperre (#62, #184) und
// Fortschritt, und meldet Ende, Fehler und Cache-Ereignisse an Protokoll, Diagnoselog (#647) und Zustand.
// Sprung in ein anderes Package: Die .dpk eines requires-Packages sucht der Locator auch in den Ordnern noch nicht
// angelegter Gruppenprojekte, in den zusätzlichen Quellordnern und in den Geschwisterordnern des Projektordners;
// ForgetFailedUnits lässt den Builder nicht gefundene Units vergessen.

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
  dpcc.Common.Index.ProjectFiles,
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
    /// <summary>Unit-Suche des letzten Aufbaus (L2: gleichnamige Units); nur unter FResolveLock.</summary>
    FResolveUnit: TUnitFileResolver;
    FResolveLock: TObject;
    /// <summary>Halter des Resolvers (L2: bei neuen Dateien leeren); nur unter FResolveLock.</summary>
    FResolveHold: IInterface;
    /// <summary>Ordner der Suchpfade bzw. der Bibliothek samt Zusatzordnern des letzten Aufbaus und der
    /// Projektordner (L2: neue Dateien, Prüfung außerhalb der beobachteten Ordner); nur unter FResolveLock.</summary>
    FSearchFolders: TArray<string>;
    FLibraryFolders: TArray<string>;
    FProjectFolder: string;
    FExcluded: TIndexExcluded;
    /// <summary>Neue Dateien aus AChanges, deren Ordner in den Pfaden liegt, in ihre Stufe (L2).</summary>
    function AddCreated(const AChanges: TArray<TFileChange>): Integer;
    procedure Attach;
    procedure ProjectReady(const AResult: TIndexBuildResult; AElapsedMs: Int64);
    procedure Finished(const AResult: TIndexBuildResult; AElapsedMs: Int64);
    procedure CacheWritten(ALibrary: Boolean; AUnits: Integer; ABytes, AElapsedMs: Int64);
    procedure CacheRejected(const AFileName, AReason: string);
    procedure CacheNotWritten(const AFileName, AReason: string);
    procedure Failed(const AError: Exception);
    procedure IndexEvent(const AText: string);
    /// <summary>Package-Locator und Unit-Suche des Projekts in den Zustand (#46, #1016). AExtraRoots: die
    /// zusätzlichen Quellordner (L2); auch dort liegt die .dpk eines requires-Packages.</summary>
    function PublishLookups(const ALoaded: TShellLoadedProject; const AExtraRoots: TArray<string>): TPackageLocator;
    /// <summary>Resolver des neuen Aufbaus; er lebt, solange Auftrag und Builder ihn über den Rückruf halten (a3).
    /// AExtraFolders (L2): zusätzliche Quellordner samt Unterordnern, nach den Bibliothekspfaden.</summary>
    function NewResolver(const ALoaded: TShellLoadedProject; const AExtraFolders: TArray<string>;
      out AFrom: TUnitFileResolverFrom): TUnitFileResolver;
    /// <summary>Eine Datei ließ sich nicht lesen oder parsen (L2): Protokoll und Diagnoselog.</summary>
    procedure Unreadable(const AFileName, AError: string);
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
    /// <summary>Vergisst die nicht gefundenen Units des Builders (Sprung in ein anderes Package). Threadsicher.
    /// </summary>
    procedure ForgetFailedUnits;
    /// <summary>Unit-Suche des letzten Aufbaus; nil ohne. Threadsicher.</summary>
    function UnitFileResolver: TUnitFileResolver;
    /// <summary>Ordner der Suchpfade, der Bibliothek und der Zusatzordner außerhalb des Projektordners (L2): Sie
    /// liegen meist nicht unter den beobachteten Ordnern; ihre Stände prüft der Server selbst. Threadsicher.</summary>
    function ScanFolders: TArray<string>;
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
  System.IOUtils,
  dpcc.Common.Index.Adapters.DiskFileSystem,
  dpcc.Common.Index.Adapters.CacheDirectory,
  dpcc.Common.Index.Processes,
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
  /// <summary>Höchstens so viele Geschwisterordner durchsucht der Package-Locator nach einer .dpk.</summary>
  cMaxSiblingFolders = 200;

/// <summary>Ordner der installierten Delphi-Versionen außer AVersion (TIndexRequest.ForeignRoots); ohne
/// Installation von AVersion leer, dann prüft der Aufbau nichts.</summary>
function ForeignInstallationRoots(const AVersion: string): TArray<string>;
var
  mVersion, mRoot, mOwnRoot: string;
begin
  Result := nil;
{$IFDEF MSWINDOWS}
  mOwnRoot := ExcludeTrailingPathDelimiter(TDelphiInstallation.RootDirOf(AVersion));
  if mOwnRoot = '' then
  begin
    Exit;
  end;
  for mVersion in TDelphiInstallation.Versions do
  begin
    mRoot := ExcludeTrailingPathDelimiter(TDelphiInstallation.RootDirOf(mVersion));
    if (mRoot <> '') and not SameText(mRoot, mOwnRoot) then
    begin
      Result := Result + [mRoot];
    end;
  end;
{$ENDIF}
end;

/// <summary>Die Ordner neben AFolder (eine Ebene, ohne AFolder selbst, höchstens cMaxSiblingFolders): Gängig ist
/// Packages\&lt;Name&gt;\&lt;Name&gt;.dpk, und ein requires-Package muss kein Projekt der Gruppe sein. Leer am
/// Laufwerk oder wenn der Elternordner nicht lesbar ist.</summary>
function SiblingFolders(const AFolder: string): TArray<string>;
var
  mParent, mFolder: string;
begin
  Result := nil;
  if AFolder = '' then
  begin
    Exit;
  end;
  mParent := ExtractFileDir(ExcludeTrailingPathDelimiter(AFolder));
  if (mParent = '') or SameText(ExcludeTrailingPathDelimiter(mParent), ExcludeTrailingPathDelimiter(AFolder)) then
  begin
    Exit;
  end;
  try
    for mFolder in TDirectory.GetDirectories(mParent) do
    begin
      if SameText(ExcludeTrailingPathDelimiter(mFolder), ExcludeTrailingPathDelimiter(AFolder)) then
      begin
        Continue;
      end;
      Result := Result + [mFolder];
      if Length(Result) >= cMaxSiblingFolders then
      begin
        Break;
      end;
    end;
  except
    // Nicht lesbare Ordner: keine Geschwister.
    on Exception do
      Result := nil;
  end;
end;

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
  end
  else if Pos(PathDelim + TIndexCacheDirectory.cExtraFolder + PathDelim, AFileName) > 0 then
  begin
    // Zusätzliche Quellordner (L2) zählen wie die Bibliothek.
    Result := ALibrary;
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

/// <summary>Rückruf für TIndexRequest.ResolveUnitFrom (L2); fängt nur den Halter ein.</summary>
function ResolveUnitFromOf(const AHold: IUnitResolverHold): TUnitFileResolverFrom;
begin
  Result :=
    function(const AUnitName, AFromDirectory: string): string
    begin
      Result := AHold.Resolver.Resolve(AUnitName, AFromDirectory);
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
  FResolveLock := TObject.Create;
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
  FResolveUnit := nil;
  FResolveHold := nil;
  FExcluded := nil;
  FResolveLock.Free;
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
  FService.OnUnreadable :=
    procedure(const AFileName, AError: string)
    begin
      Unreadable(AFileName, AError);
    end;
end;

procedure TShellWorkspaceIndexing.Unreadable(const AFileName, AError: string);
begin
  // L2: Die Datei fehlt im Index, der Aufbau läuft weiter. Pfad und Fehlertext ins Protokoll (anonymisiert wie
  // jeder Pfad), die Zeile im Diagnoselog ohne Pfad.
  FParts.Logger.Warning(Format('Datei nicht lesbar, im Index übergangen: %s (%s)', [TLogMarks.Path(AFileName),
    TLogMarks.Text(AError)]));
  IndexEvent(Format('index project#%d unreadable %s', [FParts.Setup.Priority,
    Copy(AError, 1, Pos(':', AError + ':') - 1)]));
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
  // L2: übergangene Dateien und erschöpfter Speicher nicht still.
  if AResult.Unreadable > 0 then
  begin
    FParts.Logger.Warning(Format('Symbolindex für %s: %d Dateien nicht lesbar und übergangen (Einzelheiten oben)',
      [TLogMarks.Name(FParts.Name), AResult.Unreadable]));
  end;
  if AResult.OutOfMemory then
  begin
    FParts.Logger.Error(Format('Symbolindex für %s: Speicher erschöpft; der Aufbau hat danach keine Dateien mehr ' +
      'gelesen, der Stand bis dahin bleibt', [TLogMarks.Name(FParts.Name)]));
  end;
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

function TShellWorkspaceIndexing.PublishLookups(const ALoaded: TShellLoadedProject;
  const AExtraRoots: TArray<string>): TPackageLocator;
var
  mSource: TShellUnitLookupSource;
begin
  // requires-Packages (#46): Quelle .dpk in den Ordnern der Gruppe (auch der noch nicht angelegten Projekte), im
  // Projektordner, in den Suchpfaden, in den zusätzlichen Quellordnern und in den Geschwisterordnern des
  // Projektordners (Packages\<Name>\<Name>.dpk; auch wenn das Package kein Projekt der Gruppe ist), übersetzt .dcp
  // in den Bibliothekspfaden. Läuft im Thread der Nachrichtenschleife des Servers, nie im Hauptthread der IDE.
  Result := TPackageLocator.Create(FParts.Setup.PackageFolders + [ExtractFileDir(ALoaded.ProjectFile)] +
    ALoaded.Project.SearchPaths + AExtraRoots + SiblingFolders(ExtractFileDir(ALoaded.ProjectFile)) +
    ALoaded.CompilerLibraryPaths);
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

function TShellWorkspaceIndexing.NewResolver(const ALoaded: TShellLoadedProject;
  const AExtraFolders: TArray<string>; out AFrom: TUnitFileResolverFrom): TUnitFileResolver;
var
  mResolver: TUnitResolver;
  mHold: IUnitResolverHold;
begin
  // Zusätzliche Quellordner (L2) zuletzt: Sie ergänzen, was es sonst nur als .dcu gibt.
  mResolver := TUnitResolver.Create(ALoaded.Project, ALoaded.LibraryPaths + AExtraFolders,
    TShellFileAccess.ExistsFunc());
  // Ordner einmal auflisten, über alle Projekte geteilt (CPU beim Start).
  mResolver.ListUnits := TSharedUnitListings.ListFunc();
  // Anfragen können den alten Builder noch nutzen (EnsureUnit ohne Sperre, #647): Er hält seinen Resolver selbst.
  mHold := TUnitResolverHold.Create(mResolver);
  Result := ResolveUnitOf(mHold);
  AFrom := ResolveUnitFromOf(mHold);
  TMonitor.Enter(FResolveLock);
  try
    FResolveHold := mHold;
  finally
    TMonitor.Exit(FResolveLock);
  end;
end;

procedure TShellWorkspaceIndexing.PrepareCache(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings;
  var ARequest: TIndexRequest);
var
  mFiles: TShellCacheFiles;
begin
  mFiles := TShellCacheFiles.Create(ARequest.CacheFile, ARequest.LibraryCacheFile, ARequest.SearchCacheFile);
  mFiles.ExtraFile := ARequest.ExtraCacheFile;
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
  mFiles := TShellIndexRequests.FilesOf(ALoaded, ASettings, FParts.Logger);
  TShellIndexRequests.AddPackageFiles(ALoaded.Project, PublishLookups(ALoaded, mFiles.ExtraRoots), mFiles,
    FParts.Logger, FParts.Name);
  mKey := mFiles.Key(TIndexProjectFiles.Signature(ALoaded.Project, ALoaded.Version));
  Result := mKey <> FSignature;
  if not Result then
  begin
    Exit;
  end;
  FSignature := mKey;
  mTarget.CacheRoot := FParts.Setup.CacheRoot;
  mTarget.Priority := FParts.Setup.Priority;
  mTarget.Usages := ASettings.IndexUsages;
  mRequest := TShellIndexRequests.RequestOf(ALoaded, mFiles, mTarget);
  // Als Ersatz für DelphiLSP (dpcc.LspServer.exe): Units anderer Installationen weder behalten noch aus Caches
  // übernehmen (gemessen 27.11.2026: Delphi 12 sprang bei TStringList in die Quellen von Delphi 13).
  if (FParts.Setup.IdeProjects <> nil) and FParts.Setup.IdeProjects.SeparateInstallations then
  begin
    mRequest.ForeignRoots := ForeignInstallationRoots(ALoaded.Version);
  end;
  mRequest.ResolveUnit := NewResolver(ALoaded, mFiles.ExtraFolders, mRequest.ResolveUnitFrom);
  TMonitor.Enter(FResolveLock);
  try
    FResolveUnit := mRequest.ResolveUnit;
    FSearchFolders := ALoaded.Project.SearchPaths;
    FLibraryFolders := ALoaded.LibraryPaths + mFiles.ExtraFolders;
    FProjectFolder := ExtractFileDir(ALoaded.ProjectFile);
    FExcluded := TShellIndexRequests.ExcludedOf(ASettings.IndexExclude);
  finally
    TMonitor.Exit(FResolveLock);
  end;
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

procedure TShellWorkspaceIndexing.ForgetFailedUnits;
begin
  FService.ForgetFailedUnits;
end;

function TShellWorkspaceIndexing.UnitFileResolver: TUnitFileResolver;
begin
  TMonitor.Enter(FResolveLock);
  try
    Result := FResolveUnit;
  finally
    TMonitor.Exit(FResolveLock);
  end;
end;

/// <summary>Liegt AFolder (ohne Trenner) in AFolders?</summary>
function FolderListed(const AFolder: string; const AFolders: TArray<string>): Boolean;
var
  mFolder: string;
begin
  for mFolder in AFolders do
  begin
    if SameText(ExcludeTrailingPathDelimiter(mFolder), AFolder) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TShellWorkspaceIndexing.ScanFolders: TArray<string>;
var
  mFolder: string;
begin
  Result := nil;
  TMonitor.Enter(FResolveLock);
  try
    for mFolder in FSearchFolders + FLibraryFolders do
    begin
      // Unter dem Projektordner meldet der Beobachter der IDE die Änderungen.
      if (FProjectFolder = '') or not TIndexFileDefines.IsUnder(mFolder + PathDelim, [FProjectFolder]) then
      begin
        Result := Result + [ExcludeTrailingPathDelimiter(mFolder)];
      end;
    end;
  finally
    TMonitor.Exit(FResolveLock);
  end;
end;

function TShellWorkspaceIndexing.AddCreated(const AChanges: TArray<TFileChange>): Integer;
var
  mChange: TFileChange;
  mSearch, mLibrary, mSearchFolders, mLibraryFolders: TArray<string>;
  mHold: IInterface;
  mExcluded: TIndexExcluded;
  mFolder: string;
begin
  TMonitor.Enter(FResolveLock);
  try
    mHold := FResolveHold;
    mSearchFolders := FSearchFolders;
    mLibraryFolders := FLibraryFolders;
    mExcluded := FExcluded;
  finally
    TMonitor.Exit(FResolveLock);
  end;
  mSearch := nil;
  mLibrary := nil;
  for mChange in AChanges do
  begin
    if (mChange.Kind <> TFileChangeKind.Created) or not SameText(ExtractFileExt(mChange.FileName), '.pas') then
    begin
      Continue;
    end;
    // Die Unit-Suche merkt sich Ordnerlisten und „nicht gefunden“; sie muss die neue Datei sehen.
    if mHold <> nil then
    begin
      (mHold as IUnitResolverHold).Resolver.Invalidate;
    end;
    if Assigned(mExcluded) and mExcluded(mChange.FileName) then
    begin
      Continue;
    end;
    mFolder := ExtractFileDir(mChange.FileName);
    if FolderListed(mFolder, mSearchFolders) then
    begin
      mSearch := mSearch + [mChange.FileName];
    end
    else if FolderListed(mFolder, mLibraryFolders) then
    begin
      mLibrary := mLibrary + [mChange.FileName];
    end;
  end;
  Result := FService.AddFiles(mSearch, False) + FService.AddFiles(mLibrary, True);
  if Result > 0 then
  begin
    IndexEvent(Format('index project#%d added %d', [FParts.Setup.Priority, Result]));
  end;
end;

function TShellWorkspaceIndexing.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
begin
  Result := FService.ApplyChanges(AChanges);
  // L2: Eine neue Datei im Suchpfad oder in der Bibliothek kommt gleich in den Index (vorher erst über uses).
  Inc(Result, AddCreated(AChanges));
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
