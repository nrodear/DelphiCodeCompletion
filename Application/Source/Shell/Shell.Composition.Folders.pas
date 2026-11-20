unit Shell.Composition.Folders;

// Internals-Rolle Shell: Arbeitsbereiche anlegen und entfernen. Ein gemeldeter Ordner, eine .dproj oder eine
// .groupproj wird zu einem Arbeitsbereich je Projekt (#648); Ordner ohne Meldung leitet es aus geöffneten Dateien ab
// (#175). Beim Entfernen verlassen die Units der Projekte den Index, sofern kein anderes sie enthält. Units, die
// eine Anfrage braucht, lädt es aus den Suchpfaden nach. Ein abgeleiteter Ordner verschwindet wieder, wenn das
// letzte seiner geöffneten Dokumente geschlossen ist (a5, Speicher-Optimierung Phase 2): Sonst blieb je fremder Datei
// ein Arbeitsbereich samt Projektindex bis zum Ende des Servers.
// Sprung in ein anderes Package: AddAll merkt alle Projekte einer Meldung, bevor es das erste anlegt (die IDE meldet
// jede .dproj einzeln, das aktive Projekt zuerst); kommt später ein Package-Projekt dazu, laden die vorhandenen
// Package-Projekte neu (RefreshPackages). Ein neues Projekt und jede fertige Stufe eines Aufbaus lassen alle
// Arbeitsbereiche die nicht gefundenen Units vergessen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Common.Logging.Contract,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Index.Contract,
  dpcc.Common.Index.Scheduler,
  dpcc.Common.Diagnostics.Anonymizer,
  dpcc.Common.Projects.Selection,
  dpcc.Common.Lsp.IdeProject,
  dpcc.Common.Lsp.WorkspaceFolders,
  dpcc.Common.Rules.Contract,
  Shell.Workspace,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.Configuration;

type
  TShellFoldersIndexFunc = reference to function: ISymbolIndex;
  TShellFoldersIdeProjectFunc = reference to function: TLspIdeProject;
  /// <summary>Typen der laufenden IDE (dpcc/ideTypes); nil ohne Plugin.</summary>
  TShellFoldersIdeTypesFunc = reference to function: IRuleIdeTypes;
  TShellFoldersSelectionFunc = reference to function: TProjectSelection;
  TShellFoldersAnonymizerFunc = reference to function: ILogAnonymizer;
  TShellFoldersTextFunc = reference to function: string;
  TShellFoldersReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Was das Anlegen und Entfernen der Arbeitsbereiche von der Komposition braucht. Die Funktionen fragen
  /// erst beim Anlegen; was sie liefern, entsteht nach den Ordnern.</summary>
  TShellFoldersServices = record
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    Documents: IDocumentStore;
    Workspaces: TShellWorkspaceRegistry;
    Settings: TShellSettings;
    Configuration: TShellConfiguration;
    Index: TShellFoldersIndexFunc;
    IdeProject: TShellFoldersIdeProjectFunc;
    IdeTypes: TShellFoldersIdeTypesFunc;
    Selection: TShellFoldersSelectionFunc;
    /// <summary>Anonymisierer des Server-Logs (#647); nil ohne.</summary>
    Anonymizer: TShellFoldersAnonymizerFunc;
    /// <summary>clientInfo.name für die Anmeldung am Index-Cache (#62).</summary>
    ClientName: TShellFoldersTextFunc;
    ReadText: TShellFoldersReadText;
    /// <summary>Ein Projekt ist geladen oder entfernt.</summary>
    ProjectLoaded: TProc;
    /// <summary>Projektstufe (True) bzw. ganzer Aufbau (False) eines Index fertig; im Index-Thread.</summary>
    IndexStageDone: TProc<Boolean>;
    /// <summary>Zeile fürs Diagnoselog (#647).</summary>
    IndexEvent: TProc<string>;
    /// <summary>Einstellungen eines Ordners gelesen, für serverweite Werte (#283).</summary>
    SettingsChanged: TProc<TServerSettings>;
  end;

  /// <summary>Legt Arbeitsbereiche an und entfernt sie.</summary>
  TShellFolders = class
  private
    FServices: TShellFoldersServices;
    FScheduler: TIndexScheduler;
    FCounter: Integer;
    FPriority: Integer;
    /// <summary>Abgeleitete Ordner (Derive): Schlüssel → Eintrag; nur der Thread der Nachrichtenschleife.</summary>
    FDerived: TDictionary<string, TWorkspaceFolder>;
    /// <summary>Ordner loser Dateien ohne Projekt (L2, groß); NewWorkspace setzt dafür Setup.LooseFolder.</summary>
    FLooseRoots: TDictionary<string, Boolean>;
    /// <summary>Projekte zu einem Eintrag: die .dproj, die Projekte der .groupproj bzw. der einzigen im Ordner.
    /// </summary>
    function ProjectsOf(const AFolder: TWorkspaceFolder): TArray<string>;
    /// <summary>Arbeitsbereiche zu einem Eintrag (Rumpf von Add).</summary>
    procedure AddEntry(const AFolder: TWorkspaceFolder);
    /// <summary>Kam mit diesem Aufruf ein Ordner mit .dpk dazu (AFoldersBefore: PackageFolders vorher), laden die
    /// schon bestehenden Arbeitsbereiche AExisting neu, deren Projekt ein Package ist.</summary>
    procedure RefreshPackages(const AExisting: TArray<TShellWorkspace>; const AFoldersBefore: TArray<string>);
    procedure AddProject(const ARoot, AName, AProjectFile, AOrigin: string; ADeferred: Boolean);
    function NewWorkspace(const ARoot, AName, AProjectFile, AOrigin: string; ADeferred: Boolean): TShellWorkspace;
    procedure WireEvents(AWorkspace: TShellWorkspace);
    procedure AddLogNames(const ANames: TArray<string>);
    /// <summary>Units der entfernten Projekte verlassen den Index, sofern kein verbleibendes sie enthält.</summary>
    procedure RemoveOwnedUnits(const ARemoved, ARemaining: TArray<TShellWorkspace>);
    /// <summary>Meldungen in dpcc.json: gespeicherte Abfragen (#1351) und, mit fertigem Index,
    /// Eigenschaftsregeln mit unbekannter Klasse oder Property (#309).</summary>
  public
    constructor Create(const AServices: TShellFoldersServices);
    destructor Destroy; override;
    /// <summary>Arbeitsbereiche zu einem gemeldeten Eintrag; Projektgruppe (#648): das erste Projekt ist aktiv,
    /// die übrigen warten bei index.projectGroup = false, bis eine ihrer Dateien geöffnet wird.</summary>
    procedure Add(const AFolder: TWorkspaceFolder);
    /// <summary>Wie Add für alle Einträge einer Meldung (initialize, didChangeWorkspaceFolders): Die Projekte aller
    /// Einträge sind gemerkt, bevor das erste angelegt wird.</summary>
    procedure AddAll(const AFolders: TArray<TWorkspaceFolder>);
    /// <summary>Entfernt alle Arbeitsbereiche, die der Eintrag erzeugt hat.</summary>
    procedure Remove(const AFolder: TWorkspaceFolder);
    /// <summary>Datei ohne Arbeitsbereich: Ordner mit Projekt darüber anlegen (#175).</summary>
    procedure Derive(const AFileName: string);
    /// <summary>AFileName ist geschlossen: Gehört sie zu einem abgeleiteten Ordner und ist keines seiner Dokumente
    /// mehr geöffnet, entfernt es ihn wieder (a5).</summary>
    procedure ForgetDerived(const AFileName: string);
    /// <summary>Lädt AUnitName über die Suchpfade eines Arbeitsbereichs; Anfrage-Threads.</summary>
    function EnsureUnit(const AUnitName: string): Boolean;
    function EnsureUnitFunc: TEnsureUnitFunc;
    /// <summary>Reihenfolge der Indexaufbauten aller Projekte (#648).</summary>
    property Scheduler: TIndexScheduler read FScheduler;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Index.Processes,
  dpcc.Common.JsonRpc.CurrentRequest,
  Shell.Platform,
  Shell.Bootstrap,
  Shell.Workspace.Setup,
  dpcc.Text.LogMarks;

/// <summary>Gehört AFileName zu AWorkspace? Mit fester Projektdatei nur die Projekt- und Suchpfad-Units, sonst
/// alles unter dem Ordner.</summary>
function OwnsFile(AWorkspace: TShellWorkspace; const AFileName: string): Boolean;
begin
  Result := AWorkspace.State.ContainsFile(AFileName);
  if not Result and (AWorkspace.Setup.ProjectFile = '') then
  begin
    Result := TLspWorkspaceFolders.FolderOf([TWorkspaceFolder.Create(AWorkspace.Root, '')], AFileName) = 0;
  end;
end;

/// <summary>Gehört AFileName zu einem der Arbeitsbereiche AWorkspaces?</summary>
function OwnedByAny(const AWorkspaces: TArray<TShellWorkspace>; const AFileName: string): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  Result := False;
  for mWorkspace in AWorkspaces do
  begin
    if OwnsFile(mWorkspace, AFileName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Liegt in AFolder eine .dproj oder .groupproj?</summary>
function HasProjectFile(const AFolder: string): Boolean;
begin
  try
    Result := (Length(TDirectory.GetFiles(AFolder, '*.dproj')) > 0) or
      (Length(TDirectory.GetFiles(AFolder, '*.groupproj')) > 0);
  except
    // Ungültige oder nicht lesbare Ordner zählen als ohne Projekt.
    on Exception do
      Result := False;
  end;
end;

/// <summary>Die einzige .groupproj in AFolder, wenn dort nicht genau eine .dproj liegt; sonst ''.</summary>
function GroupFileIn(const AFolder: string): string;
var
  mGroups: TArray<string>;
begin
  Result := '';
  try
    // Genau eine .dproj im Ordner: wie bisher dieses Projekt (oder "project" aus dpcc.json).
    if Length(TDirectory.GetFiles(AFolder, '*.dproj')) <> 1 then
    begin
      mGroups := TDirectory.GetFiles(AFolder, '*.groupproj');
      if Length(mGroups) = 1 then
      begin
        Result := mGroups[0];
      end;
    end;
  except
    // Nicht lesbare Ordner haben keine Gruppe.
    on Exception do
      Result := '';
  end;
end;

constructor TShellFolders.Create(const AServices: TShellFoldersServices);
begin
  inherited Create;
  FServices := AServices;
  FScheduler := TIndexScheduler.Create;
  FDerived := TDictionary<string, TWorkspaceFolder>.Create;
  FLooseRoots := TDictionary<string, Boolean>.Create;
end;

destructor TShellFolders.Destroy;
begin
  FreeAndNil(FLooseRoots);
  FreeAndNil(FDerived);
  FreeAndNil(FScheduler);
  inherited Destroy;
end;

function TShellFolders.EnsureUnitFunc: TEnsureUnitFunc;
begin
  Result := EnsureUnit;
end;

function TShellFolders.ProjectsOf(const AFolder: TWorkspaceFolder): TArray<string>;
var
  mGroupFile: string;
begin
  Result := nil;
  if SameText(ExtractFileExt(AFolder.ProjectFile), '.dproj') then
  begin
    Result := TArray<string>.Create(AFolder.ProjectFile);
    Exit;
  end;
  if SameText(ExtractFileExt(AFolder.ProjectFile), '.groupproj') then
  begin
    mGroupFile := AFolder.ProjectFile;
  end
  else
  begin
    mGroupFile := GroupFileIn(AFolder.Path);
  end;
  if mGroupFile <> '' then
  begin
    Result := TShellBootstrap.LoadGroup(mGroupFile, FServices.Logger);
  end;
end;

procedure TShellFolders.Add(const AFolder: TWorkspaceFolder);
begin
  AddAll(TArray<TWorkspaceFolder>.Create(AFolder));
end;

/// <summary>Liegt in AFolder eine .dpk?</summary>
function HasPackageSource(const AFolder: string): Boolean;
begin
  try
    Result := Length(TDirectory.GetFiles(AFolder, '*.dpk')) > 0;
  except
    // Nicht lesbare Ordner zählen als ohne Package.
    on Exception do
      Result := False;
  end;
end;

procedure TShellFolders.AddAll(const AFolders: TArray<TWorkspaceFolder>);
var
  mFolder: TWorkspaceFolder;
  mKnown, mFoldersBefore: TArray<string>;
  mExisting: TArray<TShellWorkspace>;
begin
  if Length(AFolders) = 0 then
  begin
    Exit;
  end;
  mFoldersBefore := FServices.Workspaces.PackageFolders;
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mExisting := FServices.Workspaces.Items.ToArray;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
  // Die IDE meldet jede .dproj einzeln, das aktive Projekt zuerst; es indiziert sofort beim Anlegen und muss die
  // Ordner der übrigen schon kennen.
  mKnown := nil;
  for mFolder in AFolders do
  begin
    if SameText(ExtractFileExt(mFolder.ProjectFile), '.dproj') then
    begin
      mKnown := mKnown + [mFolder.ProjectFile];
    end;
  end;
  FServices.Workspaces.NoteProjects(mKnown);
  for mFolder in AFolders do
  begin
    AddEntry(mFolder);
  end;
  RefreshPackages(mExisting, mFoldersBefore);
end;

procedure TShellFolders.RefreshPackages(const AExisting: TArray<TShellWorkspace>;
  const AFoldersBefore: TArray<string>);
var
  mFolder: string;
  mNewPackage: Boolean;
  mWorkspace: TShellWorkspace;
begin
  if Length(AExisting) = 0 then
  begin
    Exit;
  end;
  mNewPackage := False;
  for mFolder in FServices.Workspaces.PackageFolders do
  begin
    if (IndexText(mFolder, AFoldersBefore) < 0) and HasPackageSource(mFolder) then
    begin
      mNewPackage := True;
      Break;
    end;
  end;
  if not mNewPackage then
  begin
    Exit;
  end;
  FServices.Logger.Info('Package-Projekt dazugekommen; die requires der vorhandenen Packages werden neu aufgelöst');
  // Die Arbeitsbereiche aus AExisting bestehen noch: Entfernen geschieht nur in diesem Thread.
  for mWorkspace in AExisting do
  begin
    mWorkspace.RefreshPackages;
  end;
end;

procedure TShellFolders.AddEntry(const AFolder: TWorkspaceFolder);
var
  mProjects: TArray<string>;
  mIndex: Integer;
  mHasOthers: Boolean;
begin
  mProjects := ProjectsOf(AFolder);
  if Length(mProjects) = 0 then
  begin
    AddProject(AFolder.Path, AFolder.Name, '', AFolder.Key, False);
    Exit;
  end;
  mHasOthers := FServices.Workspaces.AddGroupProjects(mProjects);
  for mIndex := 0 to High(mProjects) do
  begin
    AddProject(ExtractFileDir(mProjects[mIndex]), ChangeFileExt(ExtractFileName(mProjects[mIndex]), ''),
      mProjects[mIndex], AFolder.Key, mHasOthers or (mIndex > 0));
  end;
end;

procedure TShellFolders.AddProject(const ARoot, AName, AProjectFile, AOrigin: string; ADeferred: Boolean);
var
  mWorkspace: TShellWorkspace;
begin
  if (AProjectFile <> '') and FServices.Workspaces.HasProject(AProjectFile) then
  begin
    Exit;
  end;
  AddLogNames(TArray<string>.Create(AName, ExtractFileName(ExcludeTrailingPathDelimiter(ARoot)),
    ChangeFileExt(ExtractFileName(AProjectFile), '')));
  mWorkspace := NewWorkspace(ARoot, AName, AProjectFile, AOrigin, ADeferred);
  WireEvents(mWorkspace);
  mWorkspace.Configuration.SetGlobalSettings(FServices.Settings.GlobalSettings);
  mWorkspace.Configuration.SetEditorSettings(FServices.Settings.EditorSettings);
  FServices.Workspaces.Add(mWorkspace);
  // Ein neues Projekt kann eine bisher nicht gefundene Unit liefern (Sprung in ein anderes Package).
  FServices.Workspaces.ForgetFailedUnits;
  FServices.Configuration.UpdateWatchedFiles;
  if AProjectFile <> '' then
  begin
    FServices.Logger.Info('Arbeitsbereich für Projekt: ' + TLogMarks.Path(AProjectFile));
  end
  else
  begin
    FServices.Logger.Info('Arbeitsbereichsordner: ' + TLogMarks.Path(ARoot));
  end;
  mWorkspace.Load;
end;

function TShellFolders.NewWorkspace(const ARoot, AName, AProjectFile, AOrigin: string;
  ADeferred: Boolean): TShellWorkspace;
var
  mIdentity: TIndexProcessInfo;
begin
  Inc(FCounter);
  Result := TShellWorkspace.Create(ARoot, AName, TShellWorkspaceServices.Create(FServices.Documents,
    FServices.Transport, FServices.Logger, FServices.Index(), Format('dpcc-index-%d', [FCounter])));
  Result.Setup.ProjectFile := AProjectFile;
  Result.Setup.Priority := FPriority;
  Inc(FPriority);
  Result.Setup.Scheduler := FScheduler;
  Result.Setup.Deferred := ADeferred;
  Result.Setup.IdeProjects := FServices.IdeProject();
  if Assigned(FServices.IdeTypes) then
  begin
    Result.Setup.IdeTypes := FServices.IdeTypes();
  end;
  Result.Setup.Origin := AOrigin;
  Result.Setup.LooseFolder := (AProjectFile = '') and FLooseRoots.ContainsKey(AnsiUpperCase(ARoot));
  Result.Setup.Selection := FServices.Selection();
  // Anmeldung am Index-Cache für „Prozesse am Projekt“ (#62).
  mIdentity := Default(TIndexProcessInfo);
  mIdentity.Pid := TShellPlatform.CurrentProcessId;
  mIdentity.Kind := TIndexProcessInfo.cKindLsp;
  mIdentity.Client := FServices.ClientName();
  Result.Setup.ProcessIdentity := mIdentity;
  // Ordner entstehen in der Nachrichtenschleife (initialized, didChangeWorkspaceFolders, didOpen):
  // Reload ist nur dort erlaubt.
  Result.Setup.LoopThreadId := TThread.Current.ThreadID;
end;

procedure TShellFolders.WireEvents(AWorkspace: TShellWorkspace);
begin
  // uses-unit-not-found: Was ein Projekt der Gruppe in einen Suchpfad übersetzt, gibt es beim Bau der Gruppe.
  AWorkspace.Setup.OnGroupProjects :=
    function: TArray<string>
    begin
      Result := FServices.Workspaces.GroupProjectFiles;
    end;
  // requires-Packages als Quelle zuerst bei den Projekten der Gruppe suchen (#46).
  AWorkspace.Setup.OnPackageFolders :=
    function: TArray<string>
    begin
      Result := FServices.Workspaces.PackageFolders;
    end;
  AWorkspace.Events.OnProjectLoaded := FServices.ProjectLoaded;
  // Eine fertige Stufe kann Units liefern, die andere Arbeitsbereiche vergeblich gesucht haben.
  AWorkspace.Events.OnIndexFinished :=
    procedure
    begin
      FServices.Workspaces.ForgetFailedUnits;
      FServices.IndexStageDone(False);
    end;
  AWorkspace.Events.OnProjectReady :=
    procedure
    begin
      FServices.Workspaces.ForgetFailedUnits;
      FServices.IndexStageDone(True);
    end;
  // Projekt- und Unit-Namen erscheinen im Server-Log nicht im Klartext (#647).
  AWorkspace.Events.OnNames :=
    procedure(ANames: TArray<string>)
    begin
      AddLogNames(ANames);
    end;
  AWorkspace.Events.OnIndexEvent := FServices.IndexEvent;
  // Das Zeitlimit gilt serverweit; bei mehreren Ordnern das zuletzt gelesene.
  AWorkspace.Events.OnSettingsChanged := FServices.SettingsChanged;
end;

procedure TShellFolders.AddLogNames(const ANames: TArray<string>);
var
  mAnonymizer: ILogAnonymizer;
begin
  mAnonymizer := FServices.Anonymizer();
  if mAnonymizer <> nil then
  begin
    mAnonymizer.AddNames(ANames);
  end;
end;

procedure TShellFolders.Remove(const AFolder: TWorkspaceFolder);
var
  mRemoved: TArray<TShellWorkspace>;
  mRemaining: TArray<TShellWorkspace>;
  mWorkspace: TShellWorkspace;
begin
  // Ein Eintrag (Ordner, .dproj oder .groupproj) kann mehrere Arbeitsbereiche erzeugt haben (#648).
  mRemoved := FServices.Workspaces.Extract(AFolder.Key, mRemaining);
  if Length(mRemoved) = 0 then
  begin
    Exit;
  end;
  FServices.Logger.Info(Format('Arbeitsbereich entfernt: %s (%d Projekte)', [TLogMarks.Path(AFolder.Path),
    Length(mRemoved)]));
  for mWorkspace in mRemoved do
  begin
    mWorkspace.Stop;
  end;
  RemoveOwnedUnits(mRemoved, mRemaining);
  for mWorkspace in mRemoved do
  begin
    FServices.Workspaces.FreeWhenUnused(mWorkspace);
  end;
  FServices.Configuration.UpdateWatchedFiles;
  FServices.ProjectLoaded();
end;

procedure TShellFolders.RemoveOwnedUnits(const ARemoved, ARemaining: TArray<TShellWorkspace>);
var
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
begin
  // Geteilte Bibliotheks-Units bleiben.
  mIndex := FServices.Index();
  for mUnit in mIndex.Units do
  begin
    if not mUnit.Library_ and OwnedByAny(ARemoved, mUnit.FileName) and not OwnedByAny(ARemaining, mUnit.FileName) then
    begin
      mIndex.RemoveFile(mUnit.FileName);
    end;
  end;
end;

/// <summary>Die .dproj in AFolder, die AFileName als Unit nennt (L2); bei mehreren ohne Treffer die erste
/// (alphabetisch), bei einer '' (dann wählt der Arbeitsbereich sie selbst). AReason nennt den Weg fürs Protokoll.
/// </summary>
function ProjectContaining(const AFolder, AFileName: string; out AReason: string): string;
var
  mCandidates: TArray<string>;
  mCandidate, mText, mNeedle: string;
begin
  Result := '';
  AReason := '';
  try
    mCandidates := TDirectory.GetFiles(AFolder, '*.dproj');
  except
    on Exception do
      mCandidates := nil;
  end;
  if Length(mCandidates) < 2 then
  begin
    Exit;
  end;
  TArray.Sort<string>(mCandidates);
  // DCCReference Include="…\Datei.pas": der Dateiname genügt, Ordnerangaben sind relativ.
  mNeedle := '\' + LowerCase(ExtractFileName(AFileName)) + '"';
  for mCandidate in mCandidates do
  begin
    try
      mText := LowerCase(TFile.ReadAllText(mCandidate)).Replace('"' + LowerCase(ExtractFileName(AFileName)) + '"',
        '"\' + LowerCase(ExtractFileName(AFileName)) + '"');
    except
      on Exception do
        mText := '';
    end;
    if Pos(mNeedle, mText) > 0 then
    begin
      AReason := 'enthält die Datei';
      Exit(mCandidate);
    end;
  end;
  AReason := 'keine enthält die Datei, die erste';
  Result := mCandidates[0];
end;

procedure TShellFolders.Derive(const AFileName: string);
var
  mKnown, mLibrary: Boolean;
  mFolder, mProjectFile, mReason: string;
  mEntry: TWorkspaceFolder;
begin
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mKnown := FServices.Workspaces.WorkspaceOf(AFileName) <> nil;
    mLibrary := FServices.Workspaces.IsLibrarySource(AFileName);
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
  if mKnown then
  begin
    Exit;
  end;
  mFolder := TLspWorkspaceFolders.ProjectFolderFor(AFileName, HasProjectFile);
  mProjectFile := '';
  if mFolder <> '' then
  begin
    // L2: Mehrere .dproj im Ordner: die mit der Datei, sonst die erste (vorher indizierte der Ordner nichts).
    mProjectFile := ProjectContaining(mFolder, AFileName, mReason);
    if mProjectFile <> '' then
    begin
      FServices.Logger.Info(Format('Mehrere Projekte in %s; gewählt %s (%s)', [TLogMarks.Path(mFolder),
        TLogMarks.Path(ExtractFileName(mProjectFile)), mReason]));
    end;
  end
  else if not mLibrary then
  begin
    // L2: Lose Datei ohne Projekt darüber: ihr Ordner gilt als Suchpfad (bei Bedarf geladen). Quellen der
    // Bibliothek (Gehe zu in die RTL) bekommen keinen eigenen Arbeitsbereich.
    mFolder := ExtractFileDir(AFileName);
    FLooseRoots.AddOrSetValue(AnsiUpperCase(mFolder), True);
    FServices.Logger.Info('Datei ohne Projekt; ihr Ordner gilt als Suchpfad: ' + TLogMarks.Path(mFolder));
  end;
  if mFolder <> '' then
  begin
    mEntry := TWorkspaceFolder.Create(mFolder, ExtractFileName(mFolder), mProjectFile);
    Add(mEntry);
    FDerived.AddOrSetValue(mEntry.Key, mEntry);
  end;
end;

procedure TShellFolders.ForgetDerived(const AFileName: string);
var
  mWorkspace: TShellWorkspace;
  mOrigin: string;
  mEntry: TWorkspaceFolder;
  mDocument: ITextDocument;
  mStillOpen: Boolean;
begin
  if FDerived.Count = 0 then
  begin
    Exit;
  end;
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mWorkspace := FServices.Workspaces.WorkspaceOf(AFileName);
    mOrigin := '';
    if mWorkspace <> nil then
    begin
      mOrigin := mWorkspace.Setup.Origin;
    end;
    if (mOrigin = '') or not FDerived.TryGetValue(mOrigin, mEntry) then
    begin
      Exit;
    end;
    // Noch ein geöffnetes Dokument desselben Ordners: bleibt.
    mStillOpen := False;
    for mDocument in FServices.Documents.Documents do
    begin
      mWorkspace := FServices.Workspaces.WorkspaceOf(TDocumentUris.ToPath(mDocument.Uri));
      if (mWorkspace <> nil) and SameText(mWorkspace.Setup.Origin, mOrigin) then
      begin
        mStillOpen := True;
        Break;
      end;
    end;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
  if mStillOpen then
  begin
    Exit;
  end;
  FDerived.Remove(mOrigin);
  Remove(mEntry);
end;

function TShellFolders.EnsureUnit(const AUnitName: string): Boolean;
var
  mWorkspace: TShellWorkspace;
  mTargets: TArray<TShellWorkspace>;
begin
  // Anfrage-Threads: jeder Ordner versucht es mit seinen Suchpfaden. Das Parsen läuft außerhalb der Sperre
  // (#647): Sonst warteten alle Anfragen, die nur kurz einen Arbeitsbereich suchen (Defines, Einstellungen,
  // Diagnoselog), auf das Parsen einer Unit, und Hover dauerte Minuten.
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mTargets := FServices.Workspaces.Items.ToArray;
    FServices.Workspaces.Hold(mTargets);
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
  try
    Result := False;
    for mWorkspace in mTargets do
    begin
      // Abgebrochene Anfrage (Watchdog, $/cancelRequest): keine weitere Unit parsen.
      TJsonRpcCurrentRequest.ThrowIfCancellationRequested;
      if mWorkspace.EnsureUnit(AUnitName) then
      begin
        Exit(True);
      end;
    end;
  finally
    FServices.Workspaces.Release(mTargets);
  end;
end;

end.
