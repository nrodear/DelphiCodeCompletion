unit Shell.Composition.IndexArea;

// Teilwurzel Index der Komposition: gemeinsamer Symbolindex aller Ordner, Uses-Graph (#64), Declared(X) in {$IF}
// (#847), die Ordner des Arbeitsbereichs vom Client und die Ereignisse des Indexaufbaus (Projekt geladen,
// Stufe fertig). Dazu die Ersatz-Units der IDE (dpcc/ideMembers) und der Index für Hover, Vervollständigung und
// Parameterhilfe, der sie zum gemeinsamen Index hinzunimmt. Wer außerhalb auf Namespaces oder Bibliotheksordner hört,
// bekommt sie über die Dienste. Seit Schritt 2 kennt sie nur den schlanken Kern (TShellCoreBase) und meldet sich
// bei den Diagnosen über optionale Ereignisse statt über die Teilwurzel Diagnosen; so nutzt sie auch die Wurzel der
// Completion (Shell.Composition.CompletionServer), die keine Diagnosen hat.
// Gleichnamige Units (L2): TShellUnitScopes meldet dem Index je Datei das Projekt, das die Unit wählt (Unit-Suche des
// Projekts in Compiler-Reihenfolge), seine Unit-Scope-Namen und den Rang ohne Projektbezug.

interface

uses
  System.SysUtils,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.Index.Contract,
  dpcc.Common.Pascal.Contract,
  dpcc.Common.Architecture.UsesService,
  dpcc.Common.Diagnostics.Anonymizer,
  dpcc.Common.Lsp.WorkspaceFolders,
  dpcc.Common.Lsp.IdeUnits,
  Shell.Composition.CoreBase;

type
  /// <summary>Der Kern; besteht, sobald der Index Ereignisse meldet.</summary>
  TShellIndexCoreFunc = reference to function: TShellCoreBase;
  /// <summary>Nach einer Stufe des Indexaufbaus (AProjectStage: die Projektstufe); True = offene Dateien gebündelt
  /// neu prüfen.</summary>
  TShellIndexRecheckFunc = reference to function(AProjectStage: Boolean): Boolean;
  /// <summary>Anonymisierer des Server-Logs (#647); nil ohne.</summary>
  TShellIndexAnonymizerFunc = reference to function: ILogAnonymizer;
  /// <summary>Namespaces bzw. Bibliotheksordner aller Projekte ohne Doppelte.</summary>
  TShellIndexNamesProc = reference to procedure(const ANames: TArray<string>);
  /// <summary>Reiht AWork in die Nachrichtenschleife ein; False ohne Verbindung.</summary>
  TShellIndexQueueFunc = reference to function(const AWork: TProc): Boolean;

  /// <summary>Was die Teilwurzel Index von der Komposition braucht.</summary>
  TShellIndexAreaServices = record
    Dispatcher: TJsonRpcDispatcher;
    Core: TShellIndexCoreFunc;
    /// <summary>Optional: Ein neuer Indexaufbau beginnt (Projektprüfung neu starten).</summary>
    IndexStarted: TProc;
    /// <summary>Optional: Ein Projekt ist geladen; offene Dateien sofort neu prüfen.</summary>
    Refresh: TProc;
    /// <summary>Optional: Eine Stufe ist fertig; True = offene Dateien gebündelt neu prüfen (RefreshLater).</summary>
    Recheck: TShellIndexRecheckFunc;
    /// <summary>Optional: offene Dateien gebündelt neu prüfen.</summary>
    RefreshLater: TProc;
    Anonymizer: TShellIndexAnonymizerFunc;
    /// <summary>Neues Projekt oder neue Installation: Der Compiler bekommt eine neue Chance (#40).</summary>
    ProjectStarted: TProc;
    NamespacesChanged: TShellIndexNamesProc;
    LibraryRootsChanged: TShellIndexNamesProc;
    Queue: TShellIndexQueueFunc;
    /// <summary>Der Aufbau ist ganz fertig (alle Stufen, kein Projekt mehr offen).</summary>
    IndexFinished: TProc;
  end;

  /// <summary>Hält Index, Uses-Graph und Ordner des Arbeitsbereichs.</summary>
  TShellIndexArea = class
  private
    FServices: TShellIndexAreaServices;
    FIndex: ISymbolIndex;
    /// <summary>Der an TPascalPreprocessor gemeldete Anbieter für Declared(X).</summary>
    FDeclared: TDeclaredFunc;
    /// <summary>Uses-Graph über FIndex für uses-cycle und unused-unit (#64); lebt so lange wie der Index.</summary>
    FUsesGraph: TUsesGraphService;
    FFolders: TLspWorkspaceFolders;
    FIdeUnits: TIdeUnits;
    FEditorIndex: ISymbolIndex;
    procedure FoldersChanged(const AAdded, ARemoved: TArray<TWorkspaceFolder>);
    procedure CollectNamespaces(out ANamespaces, ALibraryRoots: TArray<string>);
    procedure ApplyNamespaces(const ANamespaces: TArray<string>);
    procedure HideIndexedUnits;
    procedure RevalidateLater;
  public
    /// <summary>Legt Index und Uses-Graph an, meldet Declared(X) an und hängt die Ordner an den Verteiler.</summary>
    constructor Create(const AServices: TShellIndexAreaServices);
    /// <summary>Gibt Ordner und Uses-Graph frei und lässt den Index los; Declared(X) meldet die Komposition
    /// ab.</summary>
    destructor Destroy; override;
    /// <summary>Ein Ordner hat sein Projekt geladen: Namespaces und Bibliotheksordner neu verteilen.</summary>
    procedure ProjectLoaded;
    /// <summary>Beenden: meldet den Anbieter für Declared(X) ab, sofern kein neuerer Server ihn ersetzt hat
    /// (In-Process-Modus).</summary>
    procedure ReleaseDeclaredProvider;
    /// <summary>Eine Stufe des Indexaufbaus ist fertig (AProjectStage: die Projektstufe).</summary>
    procedure IndexStageDone(AProjectStage: Boolean);
    property Index: ISymbolIndex read FIndex;
    property UsesGraph: TUsesGraphService read FUsesGraph;
    /// <summary>Ersatz-Units der IDE für Units ohne Quelltext.</summary>
    property IdeUnits: TIdeUnits read FIdeUnits;
    /// <summary>Index samt Ersatz-Units für Hover, Vervollständigung und Parameterhilfe.</summary>
    property EditorIndex: ISymbolIndex read FEditorIndex;
  end;

implementation

uses
  System.StrUtils,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Lsp.IdeIndex,
  dpcc.Common.Architecture.UsesGraph,
  dpcc.Common.Pascal.Preprocessor,
  Shell.Workspace,
  Shell.Workspace.Requests;

type
  /// <summary>Projektbezug gleichnamiger Units (L2) über die Arbeitsbereiche des Kerns.</summary>
  TShellUnitScopes = class(TInterfacedObject, IIndexUnitScopes)
  private
    FCore: TShellIndexCoreFunc;
  public
    constructor Create(const ACore: TShellIndexCoreFunc);
    function ChooseUnit(const AFromFile, AUnitName: string; const ACandidates: TArray<string>): string;
    function NamespacesOf(const AFromFile: string; out ANamespaces: TArray<string>): Boolean;
    function RankOf(const AFileName: string; ALibrary: Boolean): Integer;
  end;

constructor TShellUnitScopes.Create(const ACore: TShellIndexCoreFunc);
begin
  inherited Create;
  FCore := ACore;
end;

function TShellUnitScopes.ChooseUnit(const AFromFile, AUnitName: string; const ACandidates: TArray<string>): string;
var
  mCore: TShellCoreBase;
  mWorkspace: TShellWorkspace;
  mResolve: TUnitFileResolver;
  mFile, mCandidate: string;
begin
  Result := '';
  mCore := FCore();
  if mCore = nil then
  begin
    Exit;
  end;
  mResolve := nil;
  System.TMonitor.Enter(mCore.Workspaces.Lock);
  try
    mWorkspace := mCore.Workspaces.Pick(AFromFile);
    if mWorkspace <> nil then
    begin
      mResolve := mWorkspace.UnitFileResolver();
    end;
  finally
    System.TMonitor.Exit(mCore.Workspaces.Lock);
  end;
  // Unit-Suche des Projekts wie der Compiler (Projektdateien, Projektordner, Suchpfade, Bibliothek, Zusatzordner);
  // außerhalb der Sperre, sie kann Ordner auflisten. Der Rückruf hält seinen Resolver selbst.
  mFile := '';
  if Assigned(mResolve) then
  begin
    mFile := mResolve(AUnitName);
  end;
  for mCandidate in ACandidates do
  begin
    if SameText(mCandidate, mFile) then
    begin
      Exit(mCandidate);
    end;
  end;
end;

function TShellUnitScopes.NamespacesOf(const AFromFile: string; out ANamespaces: TArray<string>): Boolean;
var
  mCore: TShellCoreBase;
  mWorkspace: TShellWorkspace;
begin
  ANamespaces := nil;
  Result := False;
  mCore := FCore();
  if mCore = nil then
  begin
    Exit;
  end;
  System.TMonitor.Enter(mCore.Workspaces.Lock);
  try
    // Nur das Projekt, das die Datei enthält; sonst gelten die aller Projekte.
    mWorkspace := mCore.Workspaces.WorkspaceOf(AFromFile);
    Result := (mWorkspace <> nil) and mWorkspace.State.ContainsFile(AFromFile);
    if Result then
    begin
      ANamespaces := mWorkspace.State.Namespaces;
    end;
  finally
    System.TMonitor.Exit(mCore.Workspaces.Lock);
  end;
end;

function TShellUnitScopes.RankOf(const AFileName: string; ALibrary: Boolean): Integer;
begin
  // Projekt und Suchpfade vor der Bibliothek, die zusätzlichen Quellordner zuletzt.
  if not ALibrary then
  begin
    Result := 0;
  end
  else if TShellIndexRequests.IsExtraSource(AFileName) then
  begin
    Result := 2;
  end
  else
  begin
    Result := 1;
  end;
end;

function DeclaredIn(const AIndex: ISymbolIndex): TDeclaredFunc;
begin
  Result :=
    function(const AName: string): Boolean
    var
      mLocation: TSymbolLocation;
    begin
      for mLocation in AIndex.FindSymbols(AName) do
      begin
        if mLocation.Symbol.Container = '' then
        begin
          Exit(True);
        end;
      end;
      Result := False;
    end;
end;

constructor TShellIndexArea.Create(const AServices: TShellIndexAreaServices);
begin
  inherited Create;
  FServices := AServices;
  FIndex := TSymbolIndex.Create;
  FUsesGraph := TUsesGraphService.Create(FIndex, TUsesGraphOptions.Default);
  // Declared(X) in {$IF} fragt den Index (#847). Die Referenz hält den Index, bis die Komposition den Anbieter
  // abmeldet.
  FDeclared := DeclaredIn(FIndex);
  TPascalPreprocessor.SetDeclaredProvider(FDeclared);
  FFolders := TLspWorkspaceFolders.Create;
  FFolders.OnChanged := FoldersChanged;
  FFolders.Attach(FServices.Dispatcher);
  FIdeUnits := TIdeUnits.Create;
  FEditorIndex := TIdeIndex.Create(FIndex, FIdeUnits.Index);
  // L2: gleichnamige Units je Projekt.
  FIndex.SetUnitScopes(TShellUnitScopes.Create(FServices.Core));
end;

procedure TShellIndexArea.ReleaseDeclaredProvider;
begin
  if Assigned(FDeclared) then
  begin
    TPascalPreprocessor.ReleaseDeclaredProvider(FDeclared);
  end;
  FDeclared := nil;
end;

destructor TShellIndexArea.Destroy;
begin
  FreeAndNil(FFolders);
  FreeAndNil(FUsesGraph);
  FEditorIndex := nil;
  FreeAndNil(FIdeUnits);
  if FIndex <> nil then
  begin
    FIndex.SetUnitScopes(nil);
  end;
  FIndex := nil;
  FServices := Default(TShellIndexAreaServices);
  inherited;
end;

procedure TShellIndexArea.FoldersChanged(const AAdded, ARemoved: TArray<TWorkspaceFolder>);
var
  mCore: TShellCoreBase;
  mFolder: TWorkspaceFolder;
begin
  mCore := FServices.Core();
  for mFolder in ARemoved do
  begin
    mCore.Folders.Remove(mFolder);
  end;
  for mFolder in AAdded do
  begin
    mCore.Folders.Add(mFolder);
  end;
end;

procedure TShellIndexArea.ProjectLoaded;
var
  mNamespaces: TArray<string>;
  mLibraryRoots: TArray<string>;
  mAnonymizer: ILogAnonymizer;
begin
  // Neuer Indexaufbau: Seine Projektstufe oder, falls die ausbleibt, sein Ende startet die Projektprüfung.
  if Assigned(FServices.IndexStarted) then
  begin
    FServices.IndexStarted();
  end;
  if Assigned(FServices.ProjectStarted) then
  begin
    FServices.ProjectStarted();
  end;
  CollectNamespaces(mNamespaces, mLibraryRoots);
  ApplyNamespaces(mNamespaces);
  FServices.LibraryRootsChanged(mLibraryRoots);
  mAnonymizer := FServices.Anonymizer();
  if mAnonymizer <> nil then
  begin
    mAnonymizer.SetLibraryRoots(mLibraryRoots);
  end;
  if Assigned(FServices.Refresh) then
  begin
    FServices.Refresh();
  end;
end;

procedure TShellIndexArea.CollectNamespaces(out ANamespaces, ALibraryRoots: TArray<string>);
var
  mCore: TShellCoreBase;
  mWorkspace: TShellWorkspace;
  mNamespace: string;
begin
  // Die Features kennen eine Liste: die Namespaces aller Projekte ohne Doppelte.
  ANamespaces := nil;
  ALibraryRoots := nil;
  mCore := FServices.Core();
  System.TMonitor.Enter(mCore.Workspaces.Lock);
  try
    for mWorkspace in mCore.Workspaces.Items do
    begin
      for mNamespace in mWorkspace.State.Namespaces do
      begin
        if IndexText(mNamespace, ANamespaces) < 0 then
        begin
          ANamespaces := ANamespaces + [mNamespace];
        end;
      end;
      // Units der Delphi-Installation erscheinen im Diagnoselog mit Namen (#647).
      if (mWorkspace.State.BdsRoot <> '') and (IndexText(mWorkspace.State.BdsRoot, ALibraryRoots) < 0) then
      begin
        ALibraryRoots := ALibraryRoots + [mWorkspace.State.BdsRoot];
      end;
    end;
  finally
    System.TMonitor.Exit(mCore.Workspaces.Lock);
  end;
end;

procedure TShellIndexArea.ApplyNamespaces(const ANamespaces: TArray<string>);
var
  mGraphOptions: TUsesGraphOptions;
begin
  // Uses-Graph (#64) löst Namen ohne Namensraum über dieselbe Liste auf; neu aufgebaut nur bei Änderung.
  mGraphOptions := FUsesGraph.Options;
  if string.Join(';', mGraphOptions.Namespaces) <> string.Join(';', ANamespaces) then
  begin
    mGraphOptions.Namespaces := ANamespaces;
    FUsesGraph.SetOptions(mGraphOptions);
  end;
  FServices.NamespacesChanged(ANamespaces);
end;

procedure TShellIndexArea.HideIndexedUnits;
var
  mAnonymizer: ILogAnonymizer;
  mUnit: TCatalogUnit;
begin
  // Units aus Suchpfaden stehen in keiner .dproj; im Server-Log ebenfalls verbergen (#647).
  mAnonymizer := FServices.Anonymizer();
  if mAnonymizer = nil then
  begin
    Exit;
  end;
  // Katalog: alle Units, auch die nicht geladenen (Speicher-Optimierung Phase 3).
  for mUnit in FIndex.CatalogUnits do
  begin
    mAnonymizer.AddUnit(mUnit.UnitName, mUnit.FileName);
  end;
end;

procedure TShellIndexArea.RevalidateLater;
var
  mCore: TShellCoreBase;
begin
  // Meldungen in dpcc.json, die den Index brauchen (#309); Publish nur in der Nachrichtenschleife.
  mCore := FServices.Core();
  FServices.Queue(
    procedure
    var
      mWorkspace: TShellWorkspace;
      mWorkspaces: TArray<TShellWorkspace>;
    begin
      System.TMonitor.Enter(mCore.Workspaces.Lock);
      try
        mWorkspaces := mCore.Workspaces.Items.ToArray;
      finally
        System.TMonitor.Exit(mCore.Workspaces.Lock);
      end;
      for mWorkspace in mWorkspaces do
      begin
        mWorkspace.Configuration.Revalidate;
      end;
    end);
end;

procedure TShellIndexArea.IndexStageDone(AProjectStage: Boolean);
begin
  HideIndexedUnits;
  // Befunde aus der Zeit des Aufbaus enthalten Units, die damals noch fehlten. Im Pull-Modus steigt
  // damit die Generation: Der Client holt geöffnete Dateien neu, workspace/diagnostic prüft alle.
  // Gebündelt: Die große Datei zu prüfen dauerte im Log über 20 s, und jedes Projekt meldet sich.
  // In einer Projektgruppe erst, wenn kein Projekt mehr indiziert wird: Sonst prüfte jedes fertige
  // Projekt alle Dateien neu (CPU-Last beim Start).
  if FServices.Core().Workspaces.ProjectIndexPending then
  begin
    Exit;
  end;
  // Erst am Ende des ganzen Aufbaus steht fest, welche Units der IDE keinen Quelltext haben.
  if not AProjectStage and Assigned(FServices.IndexFinished) then
  begin
    FServices.IndexFinished();
  end;
  // Nach der Projektstufe kennt der Index alles, was das Projekt über uses erreicht. Das Ende des Aufbaus
  // (Suchpfade, Bibliothek) startet die Prüfung nicht noch einmal von vorn (Diagnose-Log 29.10.2026).
  if Assigned(FServices.Recheck) and FServices.Recheck(AProjectStage) and Assigned(FServices.RefreshLater) then
  begin
    FServices.RefreshLater();
  end;
  RevalidateLater;
end;

end.
