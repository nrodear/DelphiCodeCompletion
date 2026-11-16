unit dpcc.IDE.CodeInsight.Manager.Session;

// Sitzung des Code Insight-Managers, zweite Stufe der Klassenkette: Server starten und stoppen, Neustart
// nach Absturz (#393), Projektgruppe (#648): Die Sitzung meldet dem Server alle Projekte der Gruppe, das aktive
// zuerst; Änderungen der Gruppe prüft sie höchstens alle zwei Sekunden. Änderungen außerhalb der IDE (#395): Die
// Ordner der Projekte (Git-Arbeitsverzeichnis, sonst Projektordner) werden beobachtet; gesammelte Änderungen gehen
// bei der nächsten Anfrage als workspace/didChangeWatchedFiles an den Server. Projektkontext (#396): Konfiguration,
// Plattform und Optionen der Projekte gehen in initialize mit; Änderungen prüft die Sitzung höchstens einmal je
// Sekunde. workspace/applyEdit (#397) und window/showMessage (#121) übernimmt der Hauptthread. Typen der IDE: Beim
// Start jeder Sitzung gehen die Typen der geladenen Packages als dpcc/ideTypes an den Server (auch ohne .pas).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.SyncObjs,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Files.WatchedChanges,
  dpcc.IDE.CodeInsight.Manager.State;

type
  /// <summary>Start, Stopp und Abgleich der Sitzung mit Projektgruppe, Projektkontext und Dateien.</summary>
  TDpccCodeInsightSession = class(TDpccCodeInsightState)
  protected
    // Zuletzt geprüfte Projektgruppe (#648).
    FProjectsChecked: UInt64;
    /// <summary>Zuletzt geprüfter Projektkontext (#396).</summary>
    FContextsChecked: UInt64;
    /// <summary>Änderungen außerhalb der IDE (#395).</summary>
    FFileChanges: TDpccWatchedChanges;
    FFolderWatcher: IDpccFolderWatcher;
    /// <summary>Signale „keine Statusabfrage“, „kein Befehl“ und „kein Bedienbefehl“ im Hintergrund; StopSession
    /// wartet auf sie.</summary>
    FQueryIdle: TEvent;
    FCommandIdle: TEvent;
    FServerCommandsIdle: TEvent;
    /// <summary>Laufende Sitzung oder Start im Hauptthread; außerhalb des Hauptthreads nur, was schon läuft
    ///.</summary>
    function EnsureSession: Boolean;
    /// <summary>Server starten und Sitzung aufbauen; nur aus EnsureSession, nur im Hauptthread.</summary>
    function StartSession: Boolean;
    /// <summary>Server im IDE-Prozess starten; sein Ende färbt das Statusfeld sofort (#591).</summary>
    procedure ConnectServer;
    /// <summary>Sitzung auf dem neuen Server anlegen und initialisieren; ADocuments wieder öffnen (#393).</summary>
    procedure OpenSession(const ADocuments: TArray<TLspOpenDocument>);
    /// <summary>Eintrag „Server neu gestartet“ ab dem zweiten Start (#601).</summary>
    procedure NotifyRestart(ACrashed: Boolean; APreviousStart: TDateTime; AReopened: Integer);
    /// <summary>Projekte der geöffneten Gruppe, aktives zuerst; leer ohne Gruppe (#648).</summary>
    class function GroupProjects: TArray<string>; static;
    procedure RefreshProjects;
    /// <summary>Meldet geänderte Projektkontexte (#396); höchstens einmal je Sekunde (Hauptthread).</summary>
    procedure RefreshContexts;
    /// <summary>Typen der geladenen Packages an die Sitzung (dpcc/ideTypes, Hauptthread).</summary>
    procedure SendIdeTypes;
    /// <summary>Lese-Thread: Mitglieder der Typen in AUnits (dpcc/ideMembersWanted) im Hauptthread über die RTTI
    /// sammeln und an ASession schicken (dpcc/ideMembers), solange sie die Sitzung ist.</summary>
    procedure QueueIdeMembers(ASession: TLspSession; const AUnits: TArray<string>);
    /// <summary>Hauptthread: Mitglieder der Typen in AUnits an die Sitzung.</summary>
    procedure SendIdeMembers(const AUnits: TArray<string>);
    /// <summary>Beobachtet die Ordner dieser Projekte (#395).</summary>
    procedure WatchProjects(const AProjects: TArray<string>);
    /// <summary>Gesammelte Änderungen außerhalb der IDE an den Server (Hauptthread, #395).</summary>
    procedure FlushFileChanges;
    procedure StopSession;
    procedure StopSessionNow;
    /// <summary>Meldungen der neuen Sitzung annehmen: workspace/applyEdit und window/showMessage.</summary>
    procedure AcceptNotifications(ASession: TLspSession); virtual;
    /// <summary>Nimmt workspace/applyEdit der Sitzung an (#397).</summary>
    procedure AcceptApplyEdit(ASession: TLspSession);
    /// <summary>Warnungen und Fehler des Servers (window/showMessage) ins Meldungsfenster (#121).</summary>
    procedure AcceptShowMessage(ASession: TLspSession);
    /// <summary>Der Server endete von selbst (Lese-Thread).</summary>
    procedure ServerEnded(const AInfo: TLspCloseInfo); virtual;
    function SessionOrNil: TLspSession;
    /// <summary>Gibt es den Server? Seit S1 läuft er im IDE-Prozess (Package dpcc.Server) und ist immer da; keine
    /// Exe mehr zu suchen.</summary>
    function ServerAvailable: Boolean;
    /// <summary>Bedient dpcc diese Datei? Wie HandlesFile, aber ohne Diagnosezeile.</summary>
    function Handles(const AFileName: string): Boolean;
  public
    constructor Create(const AAdapters: TDpccCodeInsightAdapters);
    destructor Destroy; override;
    /// <summary>Laufende Sitzung, Server bei Bedarf gestartet; nil, wenn er nicht startet (Hauptthread).</summary>
    function ActiveSession: TLspSession;
    /// <summary>„Server neu starten“ (#591, #393): Sitzung beenden und neu starten; hebt das Anhalten nach
    /// Abstürzen auf (AllowStart).</summary>
    function RestartServer: Boolean;
    /// <summary>„Index neu aufbauen“ (S4, Optionsseite): eine laufende Sitzung beenden (gibt die Sperren der
    /// Index-Caches frei), AClear ausführen (Caches löschen) und die Sitzung neu starten; der neue Server baut den
    /// Index ohne Cache auf. Läuft keine Sitzung, nur AClear, ohne Server zu starten. True = neu gestartet.
    /// Hauptthread.</summary>
    function RebuildIndex(const AClear: TProc): Boolean;
    /// <summary>Start von Hand („Server starten“): Nach zwei gleichen Abstürzen startet dpcc den Server wieder
    ///.</summary>
    procedure AllowStart;
    /// <summary>Neustarts des Servers in dieser Sitzung (Starts nach dem ersten; Fenster „dpcc-Server“, #1356).
    /// </summary>
    function ServerRestarts: Integer;
  end;

implementation

uses
  ToolsAPI,
  dpcc.Core.Status.Lines,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Diagnostics.TimeLimit,
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Lsp.WorkspaceEdits,
  dpcc.Core.Projects.Contract,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Projects.Context,
  dpcc.IDE.CodeInsight.Manager.Paths,
  dpcc.IDE.CodeInsight.Manager.Handlers,
  dpcc.IDE.CodeInsight.IdeTypes,
  dpcc.IDE.CodeInsight.IdeMembers,
  dpcc.Core.Lsp.IdeTypes,
  dpcc.Core.Lsp.IdeMembers,
  System.Diagnostics,
  dpcc.Core.Localization.Language,
  dpcc.Core.Diagnostics.Deadline;

const
  /// <summary>Höchstens so oft die Projektgruppe bzw. die Projektkontexte neu lesen.</summary>
  cProjectsCheckMs = 2000;
  cContextsCheckMs = 1000;

constructor TDpccCodeInsightSession.Create(const AAdapters: TDpccCodeInsightAdapters);
begin
  inherited Create(AAdapters);
  FQueryIdle := TEvent.Create(nil, True, True, '');
  FCommandIdle := TEvent.Create(nil, True, True, '');
  FServerCommandsIdle := TEvent.Create(nil, True, True, '');
  Diagnose('Plugin geladen: ' + GetModuleName(HInstance));
  FFileChanges := TDpccWatchedChanges.Create;
  FFolderWatcher := FAdapters.NewFolderWatcher(FFileChanges);
end;

destructor TDpccCodeInsightSession.Destroy;
begin
  // Hält die Beobachter-Threads an; erst danach darf der Sammler weg (Shutdown hat beides meist schon getan).
  FFolderWatcher := nil;
  FreeAndNil(FFileChanges);
  // Erst die Threads: Sie nutzen die Ereignisse bis zuletzt.
  FreeAndNil(FThreads);
  FreeAndNil(FQueryIdle);
  FreeAndNil(FCommandIdle);
  FreeAndNil(FServerCommandsIdle);
  inherited;
end;

procedure TDpccCodeInsightSession.StopSession;
begin
  // Nur im Hauptthread; verschachtelt (CheckSynchronize beim Warten) nichts tun.
  if not TDpccMainThread.IsMain or FStopping then
  begin
    Exit;
  end;
  FStopping := True;
  try
    StopSessionNow;
  finally
    FStopping := False;
  end;
end;

procedure TDpccCodeInsightSession.StopSessionNow;
begin
  Assert(TDpccMainThread.IsMain, 'StopSessionNow außerhalb des Hauptthreads');
  if FEditors <> nil then
  begin
    FEditors.BeginStop;
  end;
  if FSession <> nil then
  begin
    FSession.SetOnProgress(nil);
  end;
  if FServer <> nil then
  begin
    FServer.Client.Close;
  end;
  if FEditors <> nil then
  begin
    FEditors.EndStop;
  end;
  // Eine Statusabfrage im Hintergrund kehrt nach Close sofort zurück (#591), ebenso ein Befehl (#66).
  FQueryIdle.WaitFor(5000);
  // Aufgegebene Zeitlimit-Arbeiter können noch in Prepare bzw. Sync der Sitzung stecken.
  if not TDpccTimeLimit.WaitIdle(TDpccShutdown.cStopMs) then
  begin
    Diagnose('Sitzung beendet, während ein Zeitlimit-Arbeiter noch lief');
  end;
  FCommandIdle.WaitFor(5000);
  FServerCommandsIdle.WaitFor(5000);
  FreeAndNil(FSession);
  FServer := nil;
end;

function TDpccCodeInsightSession.ServerRestarts: Integer;
begin
  Result := AtomicCmpExchange(FStarts, 0, 0) - 1;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

function TDpccCodeInsightSession.RestartServer: Boolean;
begin
  Report('Server wird neu gestartet');
  AllowStart;
  StopSession;
  SetPhase(TDpccServerPhase.Stopped, '', True);
  Result := EnsureSession;
end;

function TDpccCodeInsightSession.RebuildIndex(const AClear: TProc): Boolean;
var
  mRunning: Boolean;
begin
  mRunning := RunningSession <> nil;
  if mRunning then
  begin
    Report('Index wird neu aufgebaut: Sitzung wird neu gestartet');
    StopSession;
    SetPhase(TDpccServerPhase.Stopped, '', True);
  end;
  try
    AClear();
  finally
    Result := mRunning and EnsureSession;
  end;
end;

procedure TDpccCodeInsightSession.AllowStart;
begin
  if FCrashes.Held then
  begin
    TDpccGuard.Log('Server: Start von Hand nach wiederholtem Absturz');
  end;
  FCrashes.Reset;
end;

procedure TDpccCodeInsightSession.ServerEnded(const AInfo: TLspCloseInfo);
begin
end;

function TDpccCodeInsightSession.EnsureSession: Boolean;
var
  mMain: Boolean;
begin
  // Start und Stopp gehören dem Hauptthread: Zeitlimit-Arbeiter, Lese-Thread und Hintergrund-Threads
  // bekommen nur, was schon läuft. Abgebaut, aber von der IDE noch gehalten (#886): im Hauptthread keinen Server
  // mehr. Verschachtelt aus StopSession oder StartSession (Warten auf Threads arbeitet eingereihte Aufrufe ab):
  // weder neu starten noch die gleich freigegebene Sitzung herausgeben.
  mMain := TDpccMainThread.IsMain;
  if not mMain or FShutDown or FStopping or FStarting then
  begin
    Exit((RunningSession <> nil) and not (mMain and FShutDown));
  end;
  if ReadySession <> nil then
  begin
    RefreshContexts;
    RefreshProjects;
    FlushFileChanges;
    Exit(True);
  end;
  // Zweimal gleich abgestürzt: kein stiller Neustart; „Server neu starten“ hebt das auf.
  Result := False;
  if not FCrashes.Held then
  begin
    FStarting := True;
    try
      Result := StartSession;
    finally
      FStarting := False;
    end;
  end;
end;

function TDpccCodeInsightSession.StartSession: Boolean;
var
  mDocuments: TArray<TLspOpenDocument>;
  mCrashed: Boolean;
  mPreviousStart: TDateTime;
begin
  // Vom Server selbst beendet (nicht von dpcc): für den Eintrag „Server neu gestartet“ (#601).
  mCrashed := (FPhase.Phase = TDpccServerPhase.Stopped) and not FPhase.Ended;
  mPreviousStart := FStartedAt;
  // Der neue Server meldet nach initialized, was er weiter überspringt (#1355).
  if FCrashSkips.Count > 0 then
  begin
    FCrashSkips.Clear;
  end;
  // Abgestürzter oder hängender Server: Was die alte Sitzung abgeglichen hatte, bekommt der neue Server sofort
  // wieder, nicht erst bei der nächsten Anfrage je Datei (#393).
  mDocuments := nil;
  if FSession <> nil then
  begin
    mDocuments := FSession.OpenDocuments;
  end;
  StopSession;
  Diagnose('Starte Server im IDE-Prozess');
  SetPhase(TDpccServerPhase.Starting, '');
  try
    ConnectServer;
    OpenSession(mDocuments);
    FLastError := '';
    FStartedAt := Now;
    SetPhase(TDpccServerPhase.Running, '');
    Result := True;
    // Jeder weitere Start ist ein Neustart (#393).
    Inc(FStarts);
    if FStarts > 1 then
    begin
      NotifyRestart(mCrashed, mPreviousStart, Length(mDocuments));
    end;
  except
    on E: Exception do
    begin
      ReportError('Start fehlgeschlagen: ' + E.Message);
      StopSession;
      SetPhase(TDpccServerPhase.Failed, TDpccCodeInsightPaths.WithoutPaths(E.Message));
      Result := False;
    end;
  end;
end;

procedure TDpccCodeInsightSession.ConnectServer;
var
  mClient: TLspClient;
begin
  FServer := FAdapters.NewServer();
  mClient := FServer.Client;
  // Fehlende Methoden (schlanker Server, Schritt 2): eine Zeile je Methode und Sitzung, danach fragt der Client
  // nicht mehr.
  mClient.OnMethodNotFound :=
    procedure(const AMethod: string; AReported: Boolean)
    begin
      if AReported then
      begin
        TDpccGuard.Log('Server: ' + AMethod + ' nicht unterstützt (-32601); weitere Anfragen unterbleiben');
      end
      else
      begin
        TDpccGuard.Log('Server: ' + AMethod + ' nicht in den Capabilities; Anfragen unterbleiben');
      end;
    end;
  // Ende des Servers (Abbruch seines Threads) färbt das Statusfeld sofort rot (#591).
  mClient.OnClosed :=
    procedure
    var
      mEnded: Boolean;
    begin
      // Während StopSession beendet dpcc den Server selbst; sonst ist er abgestürzt (#754).
      mEnded := FStopping;
      SetPhase(TDpccServerPhase.Stopped, '', mEnded);
      // Erst danach: Die Ursache aus ServerEnded setzt der Hauptthread nur auf einen abgestürzten Server.
      if not mEnded then
      begin
        ServerEnded(mClient.CloseInfo);
      end;
    end;
end;

procedure TDpccCodeInsightSession.OpenSession(const ADocuments: TArray<TLspOpenDocument>);
var
  mProjects: TArray<string>;
begin
  FSession := TLspSession.Create(FServer.Client);
  // Sprache der Oberfläche (#1458): Befunde, Code-Aktionen und Hover wie die Oberfläche; ohne "language" in
  // settings.json entscheidet allein diese Angabe.
  FSession.InitializeOptions := TLspInitializeOptions.ForLocale(TDpccTextLanguage.Code);
  Diagnose('initialize mit locale ' + TDpccTextLanguage.Code);
  FContextsChecked := 0;
  RefreshContexts;
  AcceptNotifications(FSession);
  mProjects := GroupProjects;
  FSession.SetProjects(mProjects);
  WatchProjects(mProjects);
  // Server-Einstellungen liest der Server selbst aus settings.json und dpcc.json; das Plugin schickt keine.
  FSession.SetOnProgress(
    procedure
    begin
      ServerChanged;
    end);
  FProjectsChecked := TDpccTicks.Now;
  FSession.Initialize;
  SendIdeTypes;
  if ADocuments <> nil then
  begin
    FSession.Reopen(ADocuments);
    Diagnose(Format('Nach Neustart erneut geöffnet: %d Dateien', [Length(ADocuments)]));
  end;
end;

procedure TDpccCodeInsightSession.NotifyRestart(ACrashed: Boolean; APreviousStart: TDateTime; AReopened: Integer);
var
  mRestart: TDpccServerRestart;
begin
  mRestart := Default(TDpccServerRestart);
  mRestart.Crashed := ACrashed;
  mRestart.CodeKnown := ACrashed and FCrashes.LastCode(mRestart.Code);
  mRestart.PreviousStart := APreviousStart;
  mRestart.Reopened := AReopened;
  mRestart.LogActions := LogActions;
  mRestart.CrashIssue := FOnCrashIssue;
  TDpccServerHandlers.NotifyRestarted(mRestart);
end;

/// <summary>Ist AFileName ein gespeichertes Delphi-Projekt? Neue, noch namenlose Projekte haben keinen Ordner.
/// </summary>
function SavedProject(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dproj') and FileExists(AFileName);
end;

class function TDpccCodeInsightSession.GroupProjects: TArray<string>;
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mActive: string;
  mIndex: Integer;
  mFileName: string;
begin
  Result := nil;
  mGroup := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    mGroup := mModules.MainProjectGroup;
  end;
  if mGroup = nil then
  begin
    Exit;
  end;
  mActive := '';
  if mGroup.ActiveProject <> nil then
  begin
    mActive := mGroup.ActiveProject.FileName;
  end;
  if (mActive <> '') and SavedProject(mActive) then
  begin
    Result := [mActive];
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    mFileName := mGroup.Projects[mIndex].FileName;
    if SavedProject(mFileName) and not SameText(mFileName, mActive) then
    begin
      Result := Result + [mFileName];
    end;
  end;
end;

procedure TDpccCodeInsightSession.AcceptNotifications(ASession: TLspSession);
begin
  AcceptApplyEdit(ASession);
  AcceptShowMessage(ASession);
end;

procedure TDpccCodeInsightSession.AcceptApplyEdit(ASession: TLspSession);
var
  mManager: TDpccCodeInsightSession;
begin
  mManager := Self;
  ASession.OnApplyEdit :=
    procedure(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply)
    begin
      // Lese-Thread: Open Tools API nur im Hauptthread. dpcc gehört der Eintrag: beim Entladen verworfen
      //; ohne Antwort gibt die Sitzung die Id frei.
      TDpccMainThread.Queue(TDpccFeature.EditorCommands,
        procedure
        var
          mApplied: Boolean;
          mReason: string;
        begin
          // Manager weg oder neue Sitzung: Die alte Verbindung gibt es nicht mehr, nicht antworten.
          if not ManagerLive(mManager) or (mManager.FSession <> ASession) then
          begin
            Exit;
          end;
          mApplied := TDpccServerHandlers.ApplyEdit(AEdit,
            procedure(AMessage: string)
            begin
              mManager.Diagnose(AMessage);
            end, mReason);
          // Genau eine Antwort, auch nach einer Ausnahme.
          AReply(mApplied, mReason);
        end);
    end;
end;

procedure TDpccCodeInsightSession.AcceptShowMessage(ASession: TLspSession);
var
  mManager: TDpccCodeInsightSession;
begin
  mManager := Self;
  ASession.OnShowMessage :=
    procedure(AType: Integer; const AMessage: string)
    begin
      // Information und Protokoll gehören ins Diagnoseprotokoll, nicht ins Meldungsfenster.
      if AType > 2 then
      begin
        Exit;
      end;
      TDpccMainThread.Queue(TDpccFeature.Server,
        procedure
        begin
          if ManagerLive(mManager) and (mManager.FSession = ASession) then
          begin
            mManager.Diagnose('window/showMessage: ' + AMessage);
            TDpccServerHandlers.ServerMessage(AType, AMessage, mManager.LogActions);
          end;
        end);
    end;
end;

procedure TDpccCodeInsightSession.RefreshProjects;
var
  mProjects: TArray<string>;
begin
  // Open Tools API nur im Hauptthread.
  if (GetCurrentThreadId <> MainThreadID) or (TDpccTicks.Since(FProjectsChecked) < cProjectsCheckMs) then
  begin
    Exit;
  end;
  FProjectsChecked := TDpccTicks.Now;
  try
    mProjects := GroupProjects;
    FSession.SetProjects(mProjects);
    WatchProjects(mProjects);
  except
    on E: Exception do
    begin
      Diagnose('Projektgruppe nicht gemeldet: ' + E.Message);
    end;
  end;
end;

procedure TDpccCodeInsightSession.RefreshContexts;
var
  mContext: TDpccProjectContext;
  mChanged: TArray<TDpccProjectContext>;
begin
  // Open Tools API nur im Hauptthread.
  if (GetCurrentThreadId <> MainThreadID) or
    ((FContextsChecked <> 0) and (TDpccTicks.Since(FContextsChecked) < cContextsCheckMs)) then
  begin
    Exit;
  end;
  FContextsChecked := TDpccTicks.Now;
  try
    // Mit Diagnose=1 prüfbar, ob die geerbten Optionen ankommen (#396).
    mChanged := FSession.SetProjectContexts(TDpccIdeProjectContext.Group);
    for mContext in mChanged do
    begin
      Diagnose('Projektkontext: ' + mContext.Describe);
    end;
  except
    on E: Exception do
    begin
      Diagnose('Projektkontext nicht gemeldet: ' + E.Message);
    end;
  end;
end;

procedure TDpccCodeInsightSession.SendIdeTypes;
var
  mWatch: TStopwatch;
  mTypes: TArray<TDpccIdeType>;
  mFailed: Integer;
begin
  try
    mWatch := TStopwatch.StartNew;
    mTypes := TDpccIdeTypeCollector.Collect(mFailed);
    // Nach Initialize: Der Server ersetzt mit jeder Meldung den ganzen Stand und prüft offene Dateien neu.
    FSession.Notify(TDpccIdeTypes.cMethod, TDpccIdeTypes.ToJson(mTypes));
    Diagnose(Format('IDE-Typen: %d, %d ms, RTTI unlesbar: %d', [Length(mTypes), mWatch.ElapsedMilliseconds,
      mFailed]));
  except
    on E: Exception do
    begin
      Diagnose('IDE-Typen: ' + E.Message);
    end;
  end;
end;

procedure TDpccCodeInsightSession.QueueIdeMembers(ASession: TLspSession; const AUnits: TArray<string>);
var
  mManager: TDpccCodeInsightSession;
  mUnits: TArray<string>;
begin
  if Length(AUnits) = 0 then
  begin
    Exit;
  end;
  mManager := Self;
  mUnits := AUnits;
  // Open Tools API und RTTI der Packages nur im Hauptthread.
  TDpccMainThread.Queue(TDpccFeature.Server,
    procedure
    begin
      if ManagerLive(mManager) and (mManager.FSession = ASession) then
      begin
        mManager.SendIdeMembers(mUnits);
      end;
    end);
end;

procedure TDpccCodeInsightSession.SendIdeMembers(const AUnits: TArray<string>);
var
  mWatch: TStopwatch;
  mDetails: TArray<TDpccIdeTypeDetail>;
  mFailed: Integer;
begin
  try
    mWatch := TStopwatch.StartNew;
    mDetails := TDpccIdeMemberCollector.Details(AUnits, mFailed);
    FSession.Notify(TDpccIdeMembers.cMethod, TDpccIdeMembers.ToJson(mDetails));
    Diagnose(Format('IDE-Mitglieder: %d Units, %d Typen, %d ms, RTTI unlesbar: %d', [Length(AUnits),
      Length(mDetails), mWatch.ElapsedMilliseconds, mFailed]));
  except
    on E: Exception do
    begin
      Diagnose('IDE-Mitglieder: ' + E.Message);
    end;
  end;
end;

procedure TDpccCodeInsightSession.WatchProjects(const AProjects: TArray<string>);
begin
  try
    FFolderWatcher.SetRoots(TDpccWatchedChanges.Roots(AProjects,
      function(const APath: string): Boolean
      begin
        // .git ist ein Ordner, in Worktrees und Submodulen eine Datei.
        Result := DirectoryExists(APath) or FileExists(APath);
      end));
  except
    on E: Exception do
    begin
      Diagnose('Ordner nicht beobachtet: ' + E.Message);
    end;
  end;
end;

procedure TDpccCodeInsightSession.FlushFileChanges;
var
  mChanges: TArray<TDpccFileChange>;
begin
  if GetCurrentThreadId <> MainThreadID then
  begin
    Exit;
  end;
  mChanges := FFileChanges.Take(TDpccTicks.Now);
  if mChanges = nil then
  begin
    Exit;
  end;
  try
    FSession.FilesChanged(mChanges);
    Diagnose(Format('Änderungen außerhalb der IDE gemeldet: %d Dateien', [Length(mChanges)]));
  except
    on E: Exception do
    begin
      Diagnose('Änderungen außerhalb der IDE nicht gemeldet: ' + E.Message);
    end;
  end;
end;

function TDpccCodeInsightSession.SessionOrNil: TLspSession;
begin
  Result := nil;
  if EnsureSession then
  begin
    Result := FSession;
  end;
end;

function TDpccCodeInsightSession.ActiveSession: TLspSession;
begin
  Result := SessionOrNil;
end;

function TDpccCodeInsightSession.ServerAvailable: Boolean;
begin
  // Der Server steckt im Package dpcc.Server, das das Plugin mitlädt.
  Result := True;
end;

function TDpccCodeInsightSession.Handles(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  // Nach Shutdown (abgemeldet, die IDE hält den Manager noch): nichts mehr übernehmen (#886).
  Result := False;
  if FShutDown then
  begin
    Exit;
  end;
  mExtension := LowerCase(ExtractFileExt(AFileName));
  // Hauptschalter (#407): ausgeschaltet übernimmt die eingebaute Code Insight; ebenso ohne Server.
  Result := TDpccIdeSettings.Current.Enabled and not TDpccGuard.Disabled(TDpccFeature.Completion) and
    ((mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk') or (mExtension = '.inc')) and
    ServerAvailable;
end;

end.
