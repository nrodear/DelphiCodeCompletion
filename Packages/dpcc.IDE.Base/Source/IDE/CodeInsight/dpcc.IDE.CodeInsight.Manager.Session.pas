unit dpcc.IDE.CodeInsight.Manager.Session;

// Sitzung des Code Insight-Managers, zweite Stufe der Klassenkette: Server starten und stoppen, Neustart
// nach Absturz (#393), Projektgruppe (#648): Die Sitzung meldet dem Server alle Projekte der Gruppe, das aktive
// zuerst; Änderungen der Gruppe prüft sie höchstens alle zwei Sekunden. Änderungen außerhalb der IDE (#395): Die
// Ordner der Projekte (Git-Arbeitsverzeichnis, sonst Projektordner) werden beobachtet; gesammelte Änderungen gehen
// bei der nächsten Anfrage als workspace/didChangeWatchedFiles an den Server. Projektkontext (#396): Konfiguration,
// Plattform und Optionen der Projekte gehen in initialize mit; Änderungen prüft die Sitzung höchstens einmal je
// Sekunde, seit V2 nur über einen billigen Fingerabdruck: Voll gelesen wird nur bei geändertem Fingerabdruck, nach
// einem Ereignis oder im Sicherheitstakt (TDpccIdeProjectContext.GroupIfDue); Projektliste und beobachtete Ordner
// folgen nur einem neuen vollen Lesen. workspace/applyEdit (#397) und window/showMessage (#121) übernimmt der Hauptthread. Typen der IDE: Beim
// Start jeder Sitzung gehen die Typen der geladenen Packages als dpcc/ideTypes an den Server (auch ohne .pas).
// Start und Stopp ohne Warten im Hauptthread (Hänger beim Öffnen einer Formular-Unit):
//   - EnsureSession gibt eine laufende Sitzung zurück; sonst stößt es einen Start an und liefert sofort False. Der
//     Hauptthread sammelt nur, was die Open Tools API braucht (Projekte, Projektkontexte, offene Dokumente einer
//     abgestürzten Sitzung); Server, Sitzung, initialize (bis 15 s) und die Liste der .pas unter $(BDS)\source
//     entstehen in einem Hintergrund-Thread. Fertig, übernimmt der Hauptthread die Sitzung (TDpccMainThread.Queue)
//     oder verwirft sie, wenn inzwischen Hauptschalter aus, Manager abgeschaltet oder abgebaut. Ein Fehlschlag sperrt
//     neue Versuche für 30 s (TDpccSessionLifecycle). Die RTTI der Packages liest der Hauptthread danach in kleinen
//     Schritten (TDpccIdeTypeCollector.StartRun).
//   - Typen und Mitglieder der IDE (dpcc/ideTypes, dpcc/ideMembers): Jeder Takt ist ein eigener Eintrag
//     (TDpccMainThread.ForceQueue, „IDE-Typen sammeln“ bzw. „IDE-Mitglieder sammeln“) mit höchstens etwa
//     cIdeTypesSliceMs, das Budget gilt nach jedem Typ. Der fertige Lauf liefert reine Datensätze; Eindeutig machen,
//     JSON und Senden erledigt ein Arbeiter aus TDpccTimeLimit (Post), wie der Abgleich der Formulare: nur, solange
//     das Ticket des Laufs noch die Sitzung ist; der Stopp schließt vorher die Verbindung und wartet auf diese
//     Arbeiter (WaitIdle), bevor er die Sitzung freigibt. Mitglieder: höchstens ein Lauf (TDpccIdeMemberQueue);
//     Anforderungen währenddessen laufen danach genau einmal zusammen. Neue Sitzung, Stopp, „Index neu aufbauen“
//     und Entladen brechen jeden Lauf ab, er sendet nichts mehr.
//   - Stopp (SetEnabled(False), Neustart, Abbruch eines Starts): Der Hauptthread bricht die Anfragen von
//     Vervollständigung und Parameter-Hint nur ab (BeginStop wartet nicht), schließt die Verbindung (offene Anfragen
//     kehren sofort zurück) und löst Sitzung und Server aus den Feldern; Warten auf laufende Abfragen, auf die
//     Arbeiter der Quellen (WaitWorkersIdle, sie halten die Sitzung als rohen Zeiger) und das Beenden des Servers
//     (bis 20 s) erledigt ein Hintergrund-Thread. Ein neuer Start wartet im Hintergrund, bis frühere Stopps fertig
//     sind (Sperren der Index-Caches).
//   - „Index neu aufbauen“ (RebuildIndex) kehrt sofort zurück: TDpccSessionLifecycle.TryBeginRebuild sperrt jeden
//     Start (Tippen, Hauptschalter, „Server neu starten“, zweiter Klick tut nichts), der Stopp läuft wie oben. Ein
//     Hintergrund-Thread wartet abbrechbar (höchstens cRebuildWaitMs) auf alle Stopps und abgebrochenen Starts
//     (FStopGate, FStartGate), löscht dann die Caches (AClear) und meldet sich über TDpccMainThread.Queue:
//     RebuildFinished gibt den Start frei und startet eine vorher laufende Sitzung neu, danach ADone für die
//     Optionsseite. Entladen bricht den Thread ab (IDpccRebuildRun.Cancel): weder Löschen noch Start.
//   - Kein Start-, Stopp- oder Lese-Thread hält den Manager: Sie arbeiten nur mit referenzgezählten Objekten
//     (dpcc.Core.Lsp.SessionStart: Ticket, Stopp-Zähler, Leerlauf-Signale) und dem Abbruchsignal. Jede Rückmeldung an
//     den Manager geht über TDpccMainThread.Queue (beim Entladen verworfen); erst im Hauptthread sucht SessionOf den
//     lebenden Manager (ManagerLive) und prüft am Ticket, ob die Meldung noch zu seiner Sitzung bzw. seinem Start
//     gehört. Ein Thread, der beim Entladen überfällig ist, fasst den Manager so nie an.
//   - Ein Start gehört genau einem Besitzer (Ticket): dem Hauptthread (übernommen oder zum Stoppen gelöst) oder, wenn
//     er abgebrochen wurde, seinem eigenen Thread, der dann selbst stoppt.
//   - Beim Entladen (ShutdownSession) wartet der Hauptthread auf alle Start- und Stopp-Threads, zusammen höchstens
//     cUnloadWaitMs; wer dann noch läuft, hält die Packages von dpcc geladen (TDpccThreadList.StopAll).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.JSON,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.WorkspaceEdits,
  dpcc.Core.Lsp.SessionLifecycle,
  dpcc.Core.Lsp.SessionStart,
  dpcc.Core.Files.WatchedChanges,
  dpcc.Core.Diagnostics.ThreadList,
  dpcc.Core.Lsp.IdeSlices,
  dpcc.IDE.CodeInsight.Manager.State;

type
  /// <summary>Laufender „Index neu aufbauen“: Kennung für die Rückmeldung im Hauptthread und Abbruch beim Entladen.
  /// Threadsicher, referenzgezählt; der Thread hält es selbst, nie den Manager.</summary>
  IDpccRebuildRun = interface
    ['{34BF16B5-0B8C-43E5-8B8E-084002593D59}']
    procedure Cancel;
    function Cancelled: Boolean;
  end;

  /// <summary>Start, Stopp und Abgleich der Sitzung mit Projektgruppe, Projektkontext und Dateien.</summary>
  TDpccCodeInsightSession = class(TDpccCodeInsightState)
  public const
    /// <summary>Beim Entladen höchstens so lange auf Start- und Stopp-Threads warten.</summary>
    cUnloadWaitMs = 5000;
    /// <summary>Ein Start wartet im Hintergrund höchstens so lange auf frühere Stopps.</summary>
    cStartWaitStopsMs = 30000;
    /// <summary>„Index neu aufbauen“: Der Thread wartet höchstens so lange (im Hintergrund, abbrechbar) auf Stopps
    /// und abgebrochene Starts, dann löscht er die Caches trotzdem (gesperrte bleiben stehen).</summary>
    cRebuildWaitMs = 40000;
    /// <summary>Der Stopp-Thread wartet höchstens so lange auf die Arbeiter von Vervollständigung und
    /// Parameter-Hint, bevor er die Sitzung freigibt.</summary>
    cWorkersWaitMs = 5000;
    /// <summary>Zeitbudget je Takt für die RTTI der Packages (Hauptthread).</summary>
    cIdeTypesSliceMs = 15;
  protected
    // Zuletzt geprüfte Projektgruppe (#648).
    FProjectsChecked: UInt64;
    /// <summary>Stand von TDpccIdeProjectContext.Generation, mit dem die Projekte zuletzt gemeldet wurden (V2).
    /// </summary>
    FProjectsGeneration: Cardinal;
    /// <summary>Zuletzt geprüfter Projektkontext (#396).</summary>
    FContextsChecked: UInt64;
    /// <summary>Änderungen außerhalb der IDE (#395).</summary>
    FFileChanges: TDpccWatchedChanges;
    FFolderWatcher: IDpccFolderWatcher;
    /// <summary>„Keine Statusabfrage“, „kein Befehl“ und „kein Bedienbefehl“ im Hintergrund; der Stopp im
    /// Hintergrund wartet auf sie. Referenzgezählt: Threads halten es selbst.</summary>
    FSignals: IDpccIdleSignals;
    /// <summary>Zustand von Start und Stopp (nur Hauptthread).</summary>
    FLifecycle: TDpccSessionLifecycle;
    /// <summary>Laufender Start; nil ohne.</summary>
    FStartTicket: IDpccStartTicket;
    /// <summary>Ticket der übernommenen Sitzung (Kennung für Meldungen des Servers); nil ohne Sitzung.</summary>
    FSessionTicket: IDpccStartTicket;
    FStopGate: IDpccStopGate;
    /// <summary>Laufende Start-Threads (auch abgebrochene, die ihr Ergebnis selbst stoppen); „Index neu aufbauen“
    /// wartet auch auf sie.</summary>
    FStartGate: IDpccStopGate;
    /// <summary>Laufender „Index neu aufbauen“; nil ohne.</summary>
    FRebuildRun: IDpccRebuildRun;
    /// <summary>Start-, Stopp- und Neuaufbau-Threads; ShutdownSession wartet auf sie.</summary>
    FLifeThreads: TDpccThreadList;
    /// <summary>Anforderungen dpcc/ideMembersWanted: höchstens ein Lauf; was währenddessen kommt, läuft danach
    /// genau einmal zusammengeführt (nur Hauptthread).</summary>
    FIdeMembers: TDpccIdeMemberQueue;
    /// <summary>Laufende Sitzung oder Start anstoßen (nur im Hauptthread); False, solange keine Sitzung läuft.
    /// Außerhalb des Hauptthreads nur, was schon läuft.</summary>
    function EnsureSession: Boolean;
    /// <summary>Start im Hintergrund anstoßen, falls keiner läuft, keine Sperre gilt und der Server nicht nach
    /// Abstürzen angehalten ist (Hauptthread).</summary>
    procedure RequestStart;
    /// <summary>Hauptthread: Ein Start ist fertig; übernehmen, verwerfen oder Fehlschlag melden.</summary>
    procedure StartFinished(const ATicket: IDpccStartTicket);
    /// <summary>Hauptthread: Der Server der übernommenen Sitzung endete (beim Stopp von dpcc oder von selbst).
    /// </summary>
    procedure ClientClosed(const AInfo: TLspCloseInfo);
    /// <summary>Laufenden Start abbrechen (Hauptthread); sein Ergebnis wird im Hintergrund gestoppt.</summary>
    procedure CancelStart(const AReason: string);
    /// <summary>Sitzung und Server aus den Feldern lösen und im Hintergrund stoppen (Hauptthread).</summary>
    procedure DetachSession(const AReason: string);
    /// <summary>Server und Sitzung im Hintergrund stoppen und freigeben.</summary>
    procedure StopDetachedAsync(const AServer: IDpccLspServer; ASession: TLspSession; const AReason: string);
    /// <summary>Start abbrechen und Sitzung im Hintergrund stoppen; kehrt sofort zurück (Hauptthread).</summary>
    procedure StopSessionAsync(const AReason: string);
    /// <summary>Hauptthread: Der Thread von „Index neu aufbauen“ hat die Caches gelöscht. Gibt den Start frei und
    /// startet eine vorher laufende Sitzung (ARestart) neu, sofern nicht entladen und der Hauptschalter an ist. True =
    /// Neustart angestoßen bzw. Sitzung läuft.</summary>
    function RebuildFinished(ARestart: Boolean): Boolean;
    /// <summary>Beim Entladen: Start abbrechen, Sitzung stoppen, begrenzt auf alle Start- und Stopp-Threads warten.
    /// Nur im Hauptthread, mehrfach aufrufbar.</summary>
    procedure ShutdownSession;
    /// <summary>Eintrag „Server neu gestartet“ ab dem zweiten Start (#601).</summary>
    procedure NotifyRestart(ACrashed: Boolean; APreviousStart: TDateTime; AReopened: Integer);
    /// <summary>Projekte der geöffneten Gruppe, aktives zuerst; leer ohne Gruppe (#648).</summary>
    class function GroupProjects: TArray<string>; static;
    procedure RefreshProjects;
    /// <summary>Meldet geänderte Projektkontexte (#396); höchstens einmal je Sekunde (Hauptthread).</summary>
    procedure RefreshContexts;
    /// <summary>Typen der geladenen Packages an ASession (dpcc/ideTypes): RTTI in Takten im Hauptthread, JSON und
    /// Senden im Hintergrund. Verwirft einen Lauf der Mitglieder der vorigen Sitzung.</summary>
    procedure QueueIdeTypes(ASession: TLspSession);
    /// <summary>Ein Takt davon; reiht den nächsten ein, solange ATicket die Sitzung ist.</summary>
    procedure StepIdeTypes(const ATicket: IDpccStartTicket; const ARun: IInterface; AStartedAt: UInt64);
    /// <summary>Hauptthread: Mitglieder der Typen in AUnits an die Sitzung; läuft schon ein Lauf, danach genau einmal
    /// zusammengeführt.</summary>
    procedure SendIdeMembers(const AUnits: TArray<string>);
    /// <summary>Nächsten Lauf der Mitglieder beginnen, falls keiner läuft und Units warten (Hauptthread).</summary>
    procedure StartIdeMembers;
    /// <summary>Ein Takt eines Laufs der Mitglieder; reiht den nächsten ein, solange ATicket die Sitzung und
    /// AGeneration der laufende Lauf ist.</summary>
    procedure StepIdeMembers(const ATicket: IDpccStartTicket; const ARun: IInterface; AGeneration: Cardinal;
      AStartedAt: UInt64);
    /// <summary>Hauptthread: workspace/applyEdit der Sitzung ausführen (#397); genau eine Antwort.</summary>
    procedure ServerApplyEdit(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply);
    /// <summary>Hauptthread: Warnungen und Fehler des Servers (window/showMessage) ins Meldungsfenster (#121).
    /// </summary>
    procedure ServerShowMessage(AType: Integer; const AMessage: string);
    /// <summary>Hauptthread: Benachrichtigung dpcc/… der Sitzung (AParams gehört dem Aufrufer, kann nil sein); hier
    /// dpcc/ideMembersWanted, die Absturzfälle in der Stufe Crashes.</summary>
    procedure DpccNotified(const AMethod: string; AParams: TJSONValue); virtual;
    /// <summary>Beobachtet die Ordner dieser Projekte (#395).</summary>
    procedure WatchProjects(const AProjects: TArray<string>);
    /// <summary>Gesammelte Änderungen außerhalb der IDE an den Server (Hauptthread, #395).</summary>
    procedure FlushFileChanges;
    /// <summary>Der Server endete von selbst (Hauptthread, aus ClientClosed).</summary>
    procedure ServerEnded(const AInfo: TLspCloseInfo); virtual;
    /// <summary>Hauptthread, am Ende von StartFinished: Ein Start ist fertig, AAdopted = Sitzung übernommen (sonst
    /// fehlgeschlagen oder verworfen). Der Manager fragt dann einen gemerkten Sprungwunsch; hier nichts.</summary>
    procedure SessionStartDone(AAdopted: Boolean); virtual;
    function SessionOrNil: TLspSession;
    /// <summary>Gibt es den Server? Seit S1 läuft er im IDE-Prozess (Package dpcc.Server) und ist immer da; keine
    /// Exe mehr zu suchen.</summary>
    function ServerAvailable: Boolean;
    /// <summary>Bedient dpcc diese Datei? Wie HandlesFile, aber ohne Diagnosezeile.</summary>
    function Handles(const AFileName: string): Boolean;
    /// <summary>Läuft gerade ein Start im Hintergrund?</summary>
    function StartPending: Boolean;
  public
    constructor Create(const AAdapters: TDpccCodeInsightAdapters);
    destructor Destroy; override;
    /// <summary>Laufende Sitzung; sonst nil und der Start ist angestoßen (Hauptthread).</summary>
    function ActiveSession: TLspSession;
    /// <summary>„Server neu starten“ (#591, #393): Sitzung im Hintergrund beenden und neu starten; hebt das Anhalten
    /// nach Abstürzen und die Sperre nach einem Fehlschlag auf (AllowStart). True = Start angestoßen.</summary>
    function RestartServer: Boolean;
    /// <summary>„Index neu aufbauen“ (S4, Optionsseite), kehrt sofort zurück (Hauptthread): Sitzung im Hintergrund
    /// stoppen (gibt die Sperren der Index-Caches frei), bis zum Abschluss jeden Start sperren; ein Hintergrund-Thread
    /// wartet auf die Stopps, führt AClear aus (Caches löschen; im Hintergrund, ohne VCL und Open Tools API), danach
    /// im Hauptthread Neustart einer vorher laufenden oder startenden Sitzung und ADone(True = neu gestartet). Lief
    /// keine Sitzung, nur AClear, ohne Server zu starten. Beim Entladen entfallen AClear, Start und ADone. True =
    /// angestoßen; False = abgelehnt (läuft schon, entladen), dann weder AClear noch ADone.</summary>
    function RebuildIndex(const AClear: TProc; const ADone: TProc<Boolean>): Boolean;
    /// <summary>Start von Hand („Server starten“): Nach zwei gleichen Abstürzen startet dpcc den Server wieder
    ///; ebenso vor Ablauf der Sperre nach einem Fehlschlag.</summary>
    procedure AllowStart;
    /// <summary>Neustarts des Servers in dieser Sitzung (Starts nach dem ersten; Fenster „dpcc-Server“, #1356).
    /// </summary>
    function ServerRestarts: Integer;
  end;

implementation

uses
  ToolsAPI,
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  dpcc.Core.Status.Lines,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Diagnostics.TimeLimit,
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Projects.Contract,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Projects.Context,
  dpcc.IDE.CodeInsight.Manager.Paths,
  dpcc.IDE.CodeInsight.Manager.Handlers,
  dpcc.IDE.CodeInsight.IdeTypes,
  dpcc.IDE.CodeInsight.IdeMembers,
  dpcc.Core.Lsp.IdeTypes,
  dpcc.Core.Lsp.IdeMembers,
  dpcc.Core.Localization.Language,
  dpcc.Core.Diagnostics.Deadline,
  dpcc.Core.Diagnostics.Hangs,
  dpcc.Core.Completion.Internals.Async,
  dpcc.Core.Signature.Providers.Server,
  dpcc.IDE.Hover.Editor;

const
  /// <summary>Höchstens so oft die Projektgruppe bzw. die Projektkontexte neu lesen.</summary>
  cProjectsCheckMs = 2000;
  cContextsCheckMs = 1000;
  /// <summary>Takt, in dem der Thread von „Index neu aufbauen“ auf Stopps und Starts schaut (im Hintergrund).
  /// </summary>
  cRebuildPollMs = 50;

type
  /// <summary>Kennung und Abbruch eines laufenden „Index neu aufbauen“.</summary>
  TDpccRebuildRun = class(TInterfacedObject, IDpccRebuildRun)
  private
    FCancelled: Integer;
  public
    procedure Cancel;
    function Cancelled: Boolean;
  end;

{ TDpccRebuildRun }

procedure TDpccRebuildRun.Cancel;
begin
  AtomicExchange(FCancelled, 1);
end;

function TDpccRebuildRun.Cancelled: Boolean;
begin
  Result := AtomicCmpExchange(FCancelled, 0, 0) <> 0;
end;

{ Zuordnung im Hauptthread }

/// <summary>Nur Hauptthread: lebender Manager, dessen übernommene Sitzung zu ATicket gehört; sonst nil. Der Manager
/// wird erst hier gesucht (ManagerLive), nie in einem anderen Thread gehalten.</summary>
function SessionOf(const ATicket: IDpccStartTicket): TDpccCodeInsightSession;
var
  mLive: TObject;
begin
  Result := nil;
  mLive := LiveManagerObject;
  if (ATicket <> nil) and (mLive is TDpccCodeInsightSession) and
    (TDpccCodeInsightSession(mLive).FSessionTicket = ATicket) then
  begin
    Result := TDpccCodeInsightSession(mLive);
  end;
end;

/// <summary>Nur Hauptthread: lebender Manager, dessen laufender Start ATicket ist; sonst nil.</summary>
function StarterOf(const ATicket: IDpccStartTicket): TDpccCodeInsightSession;
var
  mLive: TObject;
begin
  Result := nil;
  mLive := LiveManagerObject;
  if (ATicket <> nil) and (mLive is TDpccCodeInsightSession) and
    (TDpccCodeInsightSession(mLive).FStartTicket = ATicket) then
  begin
    Result := TDpccCodeInsightSession(mLive);
  end;
end;

/// <summary>Nur Hauptthread: lebender Manager mit dem Stopp-Zähler AGate; sonst nil.</summary>
function GateOwnerOf(const AGate: IDpccStopGate): TDpccCodeInsightSession;
var
  mLive: TObject;
begin
  Result := nil;
  mLive := LiveManagerObject;
  if (AGate <> nil) and (mLive is TDpccCodeInsightSession) and
    (TDpccCodeInsightSession(mLive).FStopGate = AGate) then
  begin
    Result := TDpccCodeInsightSession(mLive);
  end;
end;

/// <summary>Nur Hauptthread: lebender Manager, dessen laufender „Index neu aufbauen“ ARun ist; sonst nil.</summary>
function RebuilderOf(const ARun: IDpccRebuildRun): TDpccCodeInsightSession;
var
  mLive: TObject;
begin
  Result := nil;
  mLive := LiveManagerObject;
  if (ARun <> nil) and (mLive is TDpccCodeInsightSession) and
    (TDpccCodeInsightSession(mLive).FRebuildRun = ARun) then
  begin
    Result := TDpccCodeInsightSession(mLive);
  end;
end;

{ Arbeit der Hintergrund-Threads: nur Ticket, Zähler, Signale und Abbruchsignal, nie der Manager }

/// <summary>Zeile ins Diagnoseprotokoll aus einem Hintergrund-Thread, ohne den Manager anzufassen.</summary>
procedure DiagnoseFrom(ADiagnose: Boolean; const AMessage: string);
begin
  if ADiagnose then
  begin
    TDpccCodeInsightPaths.Append(AMessage);
  end;
end;

/// <summary>Empfänger an Client und Sitzung eines Starts. Die anonymen Methoden fangen nur Ticket und Client ein
/// (weder Server noch Sitzung noch Manager) und reichen alles über TDpccMainThread.Queue weiter.</summary>
procedure HookSession(AClient: TLspClient; ASession: TLspSession; const ATicket: IDpccStartTicket);
var
  mClient: TLspClient;
  mTicket: IDpccStartTicket;
begin
  mClient := AClient;
  mTicket := ATicket;
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
  // Ende des Servers: beim Stopp läuft das im Hauptthread (Queue sofort), sonst im Lese-Thread (eingereiht). Vor der
  // Übernahme gehört das Ticket keiner Sitzung, dann zählt es nicht (der Start meldet den Fehlschlag selbst).
  mClient.OnClosed :=
    procedure
    var
      mInfo: TLspCloseInfo;
    begin
      mInfo := mClient.CloseInfo;
      TDpccMainThread.Queue(TDpccFeature.Server,
        procedure
        var
          mOwner: TDpccCodeInsightSession;
        begin
          mOwner := SessionOf(mTicket);
          if (mOwner <> nil) and mTicket.TakeEndReport then
          begin
            mOwner.ClientClosed(mInfo);
          end;
        end);
    end;
  ASession.OnApplyEdit :=
    procedure(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply)
    begin
      // Lese-Thread: Open Tools API nur im Hauptthread. Beim Entladen verworfen; ohne Antwort gibt die Sitzung die Id
      // frei. Manager weg oder neue Sitzung: Die alte Verbindung gibt es nicht mehr, nicht antworten.
      TDpccMainThread.Queue(TDpccFeature.EditorCommands,
        procedure
        var
          mOwner: TDpccCodeInsightSession;
        begin
          mOwner := SessionOf(mTicket);
          if mOwner <> nil then
          begin
            mOwner.ServerApplyEdit(AEdit, AReply);
          end;
        end);
    end;
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
        var
          mOwner: TDpccCodeInsightSession;
        begin
          mOwner := SessionOf(mTicket);
          if mOwner <> nil then
          begin
            mOwner.ServerShowMessage(AType, AMessage);
          end;
        end);
    end;
  ASession.OnDpccNotification :=
    procedure(const AMethod: string; const AParams: TJSONValue)
    var
      mJson: string;
    begin
      // Im Lese-Thread nur als Text sichern: AParams gehört dem Aufrufer und lebt nicht bis in den Hauptthread.
      mJson := '';
      if AParams <> nil then
      begin
        mJson := AParams.ToJSON;
      end;
      TDpccMainThread.Queue(TDpccFeature.Server,
        procedure
        var
          mOwner: TDpccCodeInsightSession;
          mValue: TJSONValue;
        begin
          mOwner := SessionOf(mTicket);
          if mOwner = nil then
          begin
            Exit;
          end;
          mValue := nil;
          if mJson <> '' then
          begin
            mValue := TJSONObject.ParseJSONValue(mJson);
          end;
          try
            mOwner.DpccNotified(AMethod, mValue);
          finally
            mValue.Free;
          end;
        end);
    end;
  // Fortschritt ($/progress): höchstens ein Eintrag wartet; Phase, Version oder Fortschritt melden.
  ASession.SetOnProgress(
    procedure
    begin
      if not mTicket.TryMarkProgress then
      begin
        Exit;
      end;
      TDpccMainThread.Queue(TDpccFeature.Server,
        procedure
        var
          mOwner: TDpccCodeInsightSession;
        begin
          mTicket.ClearProgress;
          mOwner := SessionOf(mTicket);
          if mOwner <> nil then
          begin
            mOwner.ServerChanged;
          end;
        end);
    end);
end;

/// <summary>Arbeit des Start-Threads (StartWork): Server und Sitzung anlegen, initialize, Ergebnis an das Ticket.
/// Hält nur Ticket, Fabrik des Servers und Stopp-Zähler, nie den Manager.</summary>
procedure StartWorkRun(const ATicket: IDpccStartTicket; const ANewServer: TFunc<IDpccLspServer>;
  const AGate: IDpccStopGate);
var
  mTicket: IDpccStartTicket;
  mNewServer: TFunc<IDpccLspServer>;
  mGate: IDpccStopGate;
  mWatch: TStopwatch;
  mJob: TDpccStartJob;
  mServer: IDpccLspServer;
  mSession: TLspSession;
  mError: string;
begin
  mTicket := ATicket;
  mNewServer := ANewServer;
  mGate := AGate;
  TThread.NameThreadForDebugging('dpcc.SessionStart');
  mWatch := TStopwatch.StartNew;
  mJob := mTicket.Job;
  mServer := nil;
  mSession := nil;
  mError := '';
  try
    // Erst wenn frühere Sitzungen gestoppt sind (Sperren der Index-Caches), wie früher der Stopp vor dem Start.
    if not mGate.WaitIdle(TDpccCodeInsightSession.cStartWaitStopsMs) and not TDpccShutdown.Signalled then
    begin
      DiagnoseFrom(mJob.Diagnose, 'Serverstart: früherer Stopp läuft noch, Start trotzdem');
    end;
    if TDpccShutdown.Signalled or mTicket.Cancelled then
    begin
      raise EAbort.Create('abgebrochen');
    end;
    mServer := mNewServer();
    mSession := TLspSession.Create(mServer.Client);
    // Sprache der Oberfläche (#1458); ohne "language" in settings.json entscheidet allein diese Angabe.
    mSession.InitializeOptions := TLspInitializeOptions.ForLocale(mJob.Locale);
    // Vor initialize nur gemerkt; gehen mit initialize an den Server (#396, #648).
    mSession.SetProjectContexts(mJob.Contexts);
    mSession.SetProjects(mJob.Projects);
    // Empfänger vor initialize (der Server darf gleich danach Nachrichten schicken).
    HookSession(mServer.Client, mSession, mTicket);
    DiagnoseFrom(mJob.Diagnose, 'initialize mit locale ' + mJob.Locale);
    mSession.Initialize;
    if Length(mJob.Documents) > 0 then
    begin
      mSession.Reopen(mJob.Documents);
    end;
    // Liste der .pas unter $(BDS)\source und OCX (rekursiv) hier statt im Hauptthread.
    TDpccIdeTypeCollector.PrepareSourceUnits;
  except
    on E: Exception do
    begin
      mError := E.Message;
      if mError = '' then
      begin
        mError := E.ClassName;
      end;
    end;
  end;
  if mError <> '' then
  begin
    // Fehlschlag: Halbfertiges gleich hier abbauen, der Hauptthread bekommt nur den Grund.
    try
      if mServer <> nil then
      begin
        mServer.Client.Close;
      end;
      FreeAndNil(mSession);
      mServer := nil;
    except
      on E: Exception do
        TDpccGuard.Log('Server: Abbau nach fehlgeschlagenem Start: ' + TDpccGuard.ErrorText(E));
    end;
  end;
  if not mTicket.Deliver(mServer, mSession, mError, mWatch.ElapsedMilliseconds) then
  begin
    // Abgebrochen (Hauptschalter aus, Stopp, Entladen, Index neu aufbauen): Dieser Thread ist Besitzer und stoppt
    // selbst.
    try
      if mServer <> nil then
      begin
        mServer.Client.Close;
      end;
      FreeAndNil(mSession);
      mServer := nil;
    except
      on E: Exception do
        TDpccGuard.Log('Server: Abbau eines verworfenen Starts: ' + TDpccGuard.ErrorText(E));
    end;
    DiagnoseFrom(mJob.Diagnose, Format(
      'Serverstart verworfen und im Hintergrund gestoppt nach %d ms (Generation %d)',
      [mWatch.ElapsedMilliseconds, mJob.Generation]));
    Exit;
  end;
  // Ab hier gehören Server und Sitzung dem Ticket.
  mServer := nil;
  mSession := nil;
  // Verwirft TDpccMainThread den Eintrag (Entladen), holt ShutdownSession das Ergebnis über CancelStart.
  TDpccMainThread.Queue(TDpccFeature.Server,
    procedure
    var
      mOwner: TDpccCodeInsightSession;
    begin
      mOwner := StarterOf(mTicket);
      if mOwner <> nil then
      begin
        mOwner.StartFinished(mTicket);
      end;
    end);
end;

/// <summary>Start im Hintergrund (StartWorkRun). Die anonyme Methode fängt nur Ticket, Fabrik des Servers und die
/// Zähler der Stopps bzw. Starts ein; die Rückmeldung geht über TDpccMainThread.Queue an den Manager, den erst der
/// Hauptthread sucht (StarterOf). AStarts hat der Hauptthread vor dem Start betreten; der Thread verlässt ihn ganz am
/// Ende, auch nach dem Stopp eines verworfenen Ergebnisses („Index neu aufbauen“ wartet darauf).</summary>
function StartWork(const ATicket: IDpccStartTicket; const ANewServer: TFunc<IDpccLspServer>;
  const AGate, AStarts: IDpccStopGate): TProc;
var
  mTicket: IDpccStartTicket;
  mNewServer: TFunc<IDpccLspServer>;
  mGate: IDpccStopGate;
  mStarts: IDpccStopGate;
begin
  mTicket := ATicket;
  mNewServer := ANewServer;
  mGate := AGate;
  mStarts := AStarts;
  Result :=
    procedure
    begin
      try
        StartWorkRun(mTicket, mNewServer, mGate);
      finally
        mStarts.Leave;
      end;
    end;
end;

/// <summary>Stopp im Hintergrund: auf laufende Abfragen warten, Sitzung freigeben, Server beenden (bis 20 s, beim
/// Entladen 10 s). Die anonyme Methode fängt nur Server, Sitzung, Signale und Stopp-Zähler ein, nie den Manager;
/// den Zustand im Manager zählt ein Eintrag im Hauptthread nach (GateOwnerOf).</summary>
function StopWork(const AServer: IDpccLspServer; ASession: TLspSession; const AReason: string;
  const ASignals: IDpccIdleSignals; const AGate: IDpccStopGate; ADiagnose: Boolean): TProc;
var
  mServer: IDpccLspServer;
  mSession: TLspSession;
  mReason: string;
  mSignals: IDpccIdleSignals;
  mGate: IDpccStopGate;
  mDiagnose: Boolean;
begin
  mServer := AServer;
  mSession := ASession;
  mReason := AReason;
  mSignals := ASignals;
  mGate := AGate;
  mDiagnose := ADiagnose;
  Result :=
    procedure
    var
      mWatch: TStopwatch;
    begin
      TThread.NameThreadForDebugging('dpcc.SessionStop');
      mWatch := TStopwatch.StartNew;
      try
        try
          // Meist schon geschlossen (DetachSession); danach kehren Abfragen und Befehle sofort zurück (#591, #66).
          if mServer <> nil then
          begin
            mServer.Client.Close;
          end;
          if mSession <> nil then
          begin
            mSignals.WaitQuery(5000);
            // Aufgegebene Zeitlimit-Arbeiter können noch in Prepare bzw. Sync der Sitzung stecken; auch das Senden von
            // Formulartext, IDE-Typen und IDE-Mitgliedern läuft dort und hält die Sitzung als rohen Zeiger. Dieser
            // Thread ist nicht der Hauptthread, deshalb die großzügige Grenze.
            if not TDpccTimeLimit.WaitIdle(TDpccCodeInsightSession.cWorkersWaitMs) then
            begin
              DiagnoseFrom(mDiagnose, 'Sitzung beendet, während ein Zeitlimit-Arbeiter noch lief');
            end;
            // Arbeiter von Vervollständigung und Parameter-Hint halten die Sitzung als rohen Zeiger. BeginStop hat
            // sie nur abgebrochen; nach dem Schließen kehren ihre Anfragen sofort zurück. Hier statt im Hauptthread.
            if not TDpccAsyncCompletionProvider.WaitWorkersIdle(TDpccCodeInsightSession.cWorkersWaitMs) then
            begin
              DiagnoseFrom(mDiagnose, Format('Sitzung beendet, während %d Arbeiter der Vervollständigung liefen',
                [TDpccAsyncCompletionProvider.RunningWorkers]));
            end;
            if not TDpccServerSignatureProvider.WaitWorkersIdle(TDpccCodeInsightSession.cWorkersWaitMs) then
            begin
              DiagnoseFrom(mDiagnose, Format('Sitzung beendet, während %d Arbeiter des Parameter-Hints liefen',
                [TDpccServerSignatureProvider.RunningWorkers]));
            end;
            if not TDpccEditorHover.WaitWorkersIdle(TDpccCodeInsightSession.cWorkersWaitMs) then
            begin
              DiagnoseFrom(mDiagnose, Format('Sitzung beendet, während %d Arbeiter des Tooltips liefen',
                [TDpccEditorHover.RunningWorkers]));
            end;
            mSignals.WaitCommand(5000);
            mSignals.WaitServerCommands(5000);
          end;
          FreeAndNil(mSession);
          // Letzter Verweis: TLspInProcessServer.Destroy beendet den Server hier, nicht im Hauptthread.
          mServer := nil;
        except
          on E: Exception do
          begin
            TDpccGuard.Log('Server: Stopp im Hintergrund: ' + TDpccGuard.ErrorText(E));
          end;
        end;
        DiagnoseFrom(mDiagnose, Format('Stopp im Hintergrund fertig in %d ms (%s)', [mWatch.ElapsedMilliseconds,
          mReason]));
      finally
        mGate.Leave;
        // Zähler des Zustands nur im Hauptthread; beim Entladen verworfen, dann zählt niemand mehr.
        TDpccMainThread.Queue(TDpccFeature.Server,
          procedure
          var
            mOwner: TDpccCodeInsightSession;
          begin
            mOwner := GateOwnerOf(mGate);
            if mOwner <> nil then
            begin
              mOwner.FLifecycle.StopEnded;
            end;
          end);
      end;
    end;
end;

/// <summary>„Index neu aufbauen“ im Hintergrund: abbrechbar auf Stopps (AStops) und laufende Starts (AStarts) warten,
/// höchstens cRebuildWaitMs, dann AClear (Caches löschen) und Abschluss im Hauptthread (RebuilderOf, RebuildFinished,
/// ADone). Die anonyme Methode fängt nur Kennung, Zähler und die Prozeduren ein, nie den Manager. Abgebrochen
/// (Entladen): weder AClear noch Abschluss.</summary>
function RebuildWork(const ARun: IDpccRebuildRun; const AStops, AStarts: IDpccStopGate; const AClear: TProc;
  const ADone: TProc<Boolean>; ARestart, ADiagnose: Boolean): TProc;
var
  mRun: IDpccRebuildRun;
  mStops: IDpccStopGate;
  mStarts: IDpccStopGate;
  mClear: TProc;
  mDone: TProc<Boolean>;
  mRestart: Boolean;
  mDiagnose: Boolean;
begin
  mRun := ARun;
  mStops := AStops;
  mStarts := AStarts;
  mClear := AClear;
  mDone := ADone;
  mRestart := ARestart;
  mDiagnose := ADiagnose;
  Result :=
    procedure
    var
      mWatch: TStopwatch;
      mIdle: Boolean;
    begin
      TThread.NameThreadForDebugging('dpcc.RebuildIndex');
      mWatch := TStopwatch.StartNew;
      // Erst wenn der alte Server beendet ist (Sperren der Index-Caches): Stopps und abgebrochene Starts, die ihr
      // Ergebnis selbst stoppen. Im Takt nachsehen, damit Entladen den Thread sofort beendet.
      repeat
        mIdle := (mStops.Count = 0) and (mStarts.Count = 0);
        if mIdle or mRun.Cancelled or TDpccShutdown.Signalled or
          (mWatch.ElapsedMilliseconds >= TDpccCodeInsightSession.cRebuildWaitMs) then
        begin
          Break;
        end;
        TThread.Sleep(cRebuildPollMs);
      until False;
      if mRun.Cancelled or TDpccShutdown.Signalled then
      begin
        DiagnoseFrom(mDiagnose, 'Index neu aufbauen abgebrochen (Entladen)');
        Exit;
      end;
      if not mIdle then
      begin
        DiagnoseFrom(mDiagnose, Format('Index neu aufbauen: Stopp nach %d ms nicht fertig, Caches trotzdem löschen',
          [mWatch.ElapsedMilliseconds]));
      end;
      try
        mClear();
      except
        on E: Exception do
        begin
          TDpccGuard.Log('Index neu aufbauen: Caches löschen: ' + TDpccGuard.ErrorText(E));
        end;
      end;
      DiagnoseFrom(mDiagnose, Format('Index neu aufbauen: Caches gelöscht nach %d ms', [mWatch.ElapsedMilliseconds]));
      if mRun.Cancelled then
      begin
        Exit;
      end;
      // Beim Entladen verworfen: dann weder Start noch Meldung an die Optionsseite.
      TDpccMainThread.Queue(TDpccFeature.Server,
        procedure
        var
          mActivity: IInterface;
          mOwner: TDpccCodeInsightSession;
          mStarted: Boolean;
        begin
          mActivity := TDpccActivity.Scope('Index neu aufbauen: Neustart');
          mStarted := False;
          mOwner := RebuilderOf(mRun);
          if mOwner = nil then
          begin
            Exit;
          end;
          try
            mStarted := mOwner.RebuildFinished(mRestart);
          finally
            // Die Optionsseite erfährt das Ende auch nach einem Fehler beim Neustart.
            if Assigned(mDone) then
            begin
              mDone(mStarted);
            end;
          end;
        end);
    end;
end;

{ TDpccCodeInsightSession }

constructor TDpccCodeInsightSession.Create(const AAdapters: TDpccCodeInsightAdapters);
begin
  inherited Create(AAdapters);
  FSignals := TDpccIdleSignals.Create;
  FLifecycle := TDpccSessionLifecycle.Create;
  FStopGate := TDpccStopGate.Create;
  FStartGate := TDpccStopGate.Create;
  FLifeThreads := TDpccThreadList.Create;
  Diagnose('Plugin geladen: ' + GetModuleName(HInstance));
  FFileChanges := TDpccWatchedChanges.Create;
  FFolderWatcher := FAdapters.NewFolderWatcher(FFileChanges);
end;

destructor TDpccCodeInsightSession.Destroy;
begin
  // Hält die Beobachter-Threads an; erst danach darf der Sammler weg (Shutdown hat beides meist schon getan).
  FFolderWatcher := nil;
  FreeAndNil(FFileChanges);
  // Start- und Stopp-Threads (Shutdown hat auf sie gewartet; hier höchstens TDpccShutdown.cStopMs). Überfällige
  // halten nur ihre eigenen, referenzgezählten Objekte, nie diesen Manager.
  if FLifeThreads <> nil then
  begin
    FLifeThreads.StopAll(TDpccShutdown.cStopMs);
  end;
  FreeAndNil(FLifeThreads);
  // Erst die Threads; die Signale gibt der letzte Verweis frei.
  FreeAndNil(FThreads);
  FSignals := nil;
  FStartTicket := nil;
  FSessionTicket := nil;
  FRebuildRun := nil;
  FStopGate := nil;
  FStartGate := nil;
  FreeAndNil(FLifecycle);
  inherited;
end;

function TDpccCodeInsightSession.StartPending: Boolean;
begin
  Result := (FLifecycle <> nil) and (FLifecycle.Phase = TDpccSessionPhase.Starting);
end;

procedure TDpccCodeInsightSession.DetachSession(const AReason: string);
var
  mActivity: IInterface;
  mServer: IDpccLspServer;
  mSession: TLspSession;
begin
  Assert(TDpccMainThread.IsMain, 'DetachSession außerhalb des Hauptthreads');
  if (FSession = nil) and (FServer = nil) then
  begin
    FSessionTicket := nil;
    Exit;
  end;
  mActivity := TDpccActivity.Scope('Sitzung stoppen');
  // Während des Schließens ist ein Ende des Servers kein Absturz (OnClosed läuft in Close, im Hauptthread sofort).
  // Nichts davon wartet: BeginStop bricht die Anfragen von Vervollständigung und Parameter-Hint nur ab (vor dem
  // Schließen, damit kein geweckter Arbeiter noch liefert); Close weckt alle offenen Anfragen sofort (Done). Auf die
  // Arbeiter (auch die des Tooltips) wartet StopWork im Hintergrund, bevor es die Sitzung freigibt.
  FStopping := True;
  try
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
  finally
    FStopping := False;
  end;
  mServer := FServer;
  mSession := FSession;
  FSession := nil;
  FServer := nil;
  // Ab hier gehören späte Meldungen des alten Servers keiner Sitzung mehr.
  FSessionTicket := nil;
  Diagnose('Sitzung gelöst (' + AReason + '), Stopp im Hintergrund');
  StopDetachedAsync(mServer, mSession, AReason);
end;

procedure TDpccCodeInsightSession.StopDetachedAsync(const AServer: IDpccLspServer; ASession: TLspSession;
  const AReason: string);
var
  mWork: TProc;
begin
  if (AServer = nil) and (ASession = nil) then
  begin
    Exit;
  end;
  FStopGate.Enter;
  FLifecycle.StopBegun;
  mWork := StopWork(AServer, ASession, AReason, FSignals, FStopGate, FDiagnose);
  try
    FLifeThreads.Start(mWork);
  except
    on E: Exception do
    begin
      // Kein Thread: dann eben hier (selten, etwa ohne Thread-Handles).
      TDpccGuard.Log('Server: Stopp-Thread nicht gestartet, Stopp im Hauptthread: ' + TDpccGuard.ErrorText(E));
      mWork();
    end;
  end;
end;

procedure TDpccCodeInsightSession.CancelStart(const AReason: string);
var
  mTicket: IDpccStartTicket;
  mServer: IDpccLspServer;
  mSession: TLspSession;
begin
  mTicket := FStartTicket;
  FStartTicket := nil;
  if mTicket <> nil then
  begin
    if mTicket.Cancel(mServer, mSession) then
    begin
      // Schon fertig, aber noch nicht übernommen: Der Hauptthread ist Besitzer und stoppt es.
      StopDetachedAsync(mServer, mSession, 'Start verworfen: ' + AReason);
    end;
    Diagnose('Serverstart verworfen: ' + AReason);
  end;
  if FLifecycle.Phase = TDpccSessionPhase.Starting then
  begin
    FLifecycle.Cancel;
    if FPhase.Phase = TDpccServerPhase.Starting then
    begin
      SetPhase(TDpccServerPhase.Stopped, '', True);
    end;
  end;
end;

procedure TDpccCodeInsightSession.StopSessionAsync(const AReason: string);
begin
  if not TDpccMainThread.IsMain then
  begin
    Exit;
  end;
  CancelStart(AReason);
  if FLifecycle.Phase = TDpccSessionPhase.Ready then
  begin
    FLifecycle.Cancel;
  end;
  DetachSession(AReason);
end;

procedure TDpccCodeInsightSession.ShutdownSession;
var
  mWatch: TStopwatch;
  mDone: Boolean;
begin
  if (FLifecycle = nil) or FLifecycle.Closed then
  begin
    Exit;
  end;
  // Laufender „Index neu aufbauen“: Sein Thread hört auf zu warten und löscht nichts mehr; kein Start danach.
  if FRebuildRun <> nil then
  begin
    FRebuildRun.Cancel;
    FRebuildRun := nil;
  end;
  CancelStart('Entladen');
  DetachSession('Entladen');
  FLifecycle.Close;
  // Kein Thread darf nach dem Entladen weiterlaufen: begrenzt warten; wer dann noch läuft, hält die Packages von
  // dpcc geladen (TDpccThreadList.StopAll) und nur seine eigenen Objekte, nie den Manager.
  mWatch := TStopwatch.StartNew;
  mDone := FLifeThreads.StopAll(cUnloadWaitMs);
  Report(Format('Entladen: auf Start- und Stopp-Threads gewartet %d ms, alle beendet: %s',
    [mWatch.ElapsedMilliseconds, BoolToStr(mDone, True)]));
  if not mDone then
  begin
    TDpccGuard.Log(Format('Entladen: Start- oder Stopp-Thread nach %d ms nicht beendet; Packages bleiben geladen',
      [cUnloadWaitMs]));
  end;
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
var
  mActivity: IInterface;
begin
  mActivity := TDpccActivity.Scope('Server neu starten');
  Report('Server wird neu gestartet');
  AllowStart;
  StopSessionAsync('Neustart von Hand');
  SetPhase(TDpccServerPhase.Stopped, '', True);
  // Während „Index neu aufbauen“ startet erst dessen Abschluss den Server (RequestStart tut dann nichts).
  RequestStart;
  Result := StartPending;
end;

function TDpccCodeInsightSession.RebuildIndex(const AClear: TProc; const ADone: TProc<Boolean>): Boolean;
var
  mActivity: IInterface;
  mRestart: Boolean;
  mRun: IDpccRebuildRun;
begin
  mActivity := TDpccActivity.Scope('Index neu aufbauen');
  Result := False;
  if not TDpccMainThread.IsMain or FShutDown or (FLifecycle = nil) or not Assigned(AClear) then
  begin
    Exit;
  end;
  // Laufende oder startende Sitzung: nach dem Löschen neu starten. Sonst nur löschen, ohne Server zu starten.
  mRestart := (RunningSession <> nil) or StartPending;
  // Zweiter Klick, während der erste noch läuft (oder nach dem Entladen): nichts tun.
  if not FLifecycle.TryBeginRebuild then
  begin
    Diagnose('Index neu aufbauen läuft schon; Aufruf ignoriert');
    Exit;
  end;
  mRun := TDpccRebuildRun.Create;
  FRebuildRun := mRun;
  if mRestart then
  begin
    Report('Index wird neu aufgebaut: Sitzung wird angehalten und danach neu gestartet');
  end
  else
  begin
    Report('Index wird neu aufgebaut: Caches werden gelöscht, der Server startet bei der nächsten Anfrage');
  end;
  // Kehrt sofort zurück; der Stopp läuft im Hintergrund (FStopGate). Ab hier startet nichts, bis RebuildFinished.
  StopSessionAsync('Index neu aufbauen');
  if mRestart then
  begin
    SetPhase(TDpccServerPhase.Stopped, '', True);
  end;
  try
    FLifeThreads.Start(RebuildWork(mRun, FStopGate, FStartGate, AClear, ADone, mRestart, FDiagnose));
    Result := True;
  except
    on E: Exception do
    begin
      // Kein Thread: Neuaufbau zurücknehmen; die Caches bleiben, die Sitzung startet wieder.
      TDpccGuard.Log('Index neu aufbauen: Thread nicht gestartet: ' + TDpccGuard.ErrorText(E));
      FRebuildRun := nil;
      if FLifecycle.EndRebuild and mRestart then
      begin
        RequestStart;
      end;
    end;
  end;
end;

function TDpccCodeInsightSession.RebuildFinished(ARestart: Boolean): Boolean;
begin
  Result := False;
  FRebuildRun := nil;
  // Entladen oder abgebaut: kein Start mehr.
  if not FLifecycle.EndRebuild or FShutDown then
  begin
    Exit;
  end;
  Diagnose('Index neu aufbauen: Caches gelöscht, Start wieder frei');
  // Wie früher nur eine vorher laufende Sitzung neu starten; nicht bei inzwischen ausgeschaltetem Hauptschalter.
  if ARestart and TDpccIdeSettings.Current.Enabled then
  begin
    RequestStart;
    Result := StartPending or (RunningSession <> nil);
  end;
end;

procedure TDpccCodeInsightSession.AllowStart;
begin
  if FCrashes.Held then
  begin
    TDpccGuard.Log('Server: Start von Hand nach wiederholtem Absturz');
  end;
  FCrashes.Reset;
  if FLifecycle <> nil then
  begin
    FLifecycle.ClearBlock;
  end;
end;

procedure TDpccCodeInsightSession.ServerEnded(const AInfo: TLspCloseInfo);
begin
end;

procedure TDpccCodeInsightSession.ClientClosed(const AInfo: TLspCloseInfo);
var
  mEnded: Boolean;
begin
  // Während des Stopps beendet dpcc den Server selbst; sonst ist er abgestürzt (#754).
  mEnded := FStopping;
  SetPhase(TDpccServerPhase.Stopped, '', mEnded);
  // Erst danach: Die Ursache aus ServerEnded setzt der Hauptthread nur auf einen abgestürzten Server.
  if not mEnded then
  begin
    ServerEnded(AInfo);
  end;
end;

function TDpccCodeInsightSession.EnsureSession: Boolean;
var
  mMain: Boolean;
begin
  // Start und Stopp gehören dem Hauptthread: Zeitlimit-Arbeiter, Lese-Thread und Hintergrund-Threads
  // bekommen nur, was schon läuft. Abgebaut, aber von der IDE noch gehalten (#886): im Hauptthread keinen Server
  // mehr. Während eines Stopps (FStopping) weder neu starten noch die gleich gelöste Sitzung herausgeben.
  mMain := TDpccMainThread.IsMain;
  if not mMain or FShutDown or FStopping then
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
  // Nie warten: Start anstoßen; bis er fertig ist, antworten die Aufrufer ohne Sitzung.
  RequestStart;
  Result := False;
end;

procedure TDpccCodeInsightSession.RequestStart;
var
  mJob: TDpccStartJob;
  mGeneration: Cardinal;
  mTicket: IDpccStartTicket;
begin
  if not TDpccMainThread.IsMain or FShutDown or (FLifecycle = nil) then
  begin
    Exit;
  end;
  case FLifecycle.Phase of
    TDpccSessionPhase.Starting:
      Exit;
    TDpccSessionPhase.Ready:
      begin
        // Bereit, aber ReadySession = nil: Der Server endete von selbst. Steht sein Ende noch in der Warteschlange,
        // hier zuerst auswerten (Absturz zählen, Phase), damit der Neustart richtig gemeldet wird.
        if (FSessionTicket <> nil) and (FServer <> nil) and FSessionTicket.TakeEndReport then
        begin
          ClientClosed(FServer.Client.CloseInfo);
        end;
        FLifecycle.SessionLost;
        Diagnose('Sitzung verloren: Server läuft nicht mehr');
      end;
  end;
  // Zweimal gleich abgestürzt: kein stiller Neustart; „Server neu starten“ hebt das auf. Nach einem Fehlschlag
  // gilt die Sperrzeit. Während „Index neu aufbauen“ startet erst dessen Abschluss (RebuildFinished), nachdem die
  // Caches gelöscht sind.
  if FCrashes.Held or FLifecycle.Blocked(TDpccTicks.Now) or FLifecycle.Closed or FLifecycle.Rebuilding then
  begin
    Exit;
  end;
  mJob := Default(TDpccStartJob);
  // Vom Server selbst beendet (nicht von dpcc): für den Eintrag „Server neu gestartet“ (#601).
  mJob.Crashed := (FPhase.Phase = TDpccServerPhase.Stopped) and not FPhase.Ended;
  mJob.PreviousStart := FStartedAt;
  // Abgestürzter oder hängender Server: Was die alte Sitzung abgeglichen hatte, bekommt der neue Server sofort
  // wieder, nicht erst bei der nächsten Anfrage je Datei (#393).
  if FSession <> nil then
  begin
    mJob.Documents := FSession.OpenDocuments;
  end;
  DetachSession('Neustart');
  // Der neue Server meldet nach initialized, was er weiter überspringt (#1355).
  if FCrashSkips.Count > 0 then
  begin
    FCrashSkips.Clear;
  end;
  if not FLifecycle.TryBeginStart(TDpccTicks.Now, mGeneration) then
  begin
    Exit;
  end;
  mJob.Generation := mGeneration;
  mJob.Diagnose := FDiagnose;
  // Sprache der Oberfläche (#1458): Befunde, Code-Aktionen und Hover wie die Oberfläche.
  mJob.Locale := TDpccTextLanguage.Code;
  mJob.MasterOn := TDpccIdeSettings.Current.Enabled;
  // Open Tools API nur hier im Hauptthread; der Hintergrund-Thread bekommt die fertigen Werte.
  try
    mJob.Projects := GroupProjects;
  except
    on E: Exception do
    begin
      Diagnose('Projektgruppe nicht gelesen: ' + E.Message);
    end;
  end;
  try
    // Mit Diagnose=1 prüfbar, ob die geerbten Optionen ankommen (#396).
    mJob.Contexts := TDpccIdeProjectContext.Group;
  except
    on E: Exception do
    begin
      Diagnose('Projektkontext nicht gelesen: ' + E.Message);
    end;
  end;
  mTicket := TDpccStartTicket.Create(mJob);
  FStartTicket := mTicket;
  SetPhase(TDpccServerPhase.Starting, '');
  Diagnose(Format('Serverstart angestoßen (Generation %d, %d Projekte, %d Dateien zum erneuten Öffnen)',
    [mGeneration, Length(mJob.Projects), Length(mJob.Documents)]));
  // Verlassen am Ende des Start-Threads (StartWork); „Index neu aufbauen“ wartet darauf.
  FStartGate.Enter;
  try
    FLifeThreads.Start(StartWork(mTicket, FAdapters.NewServer, FStopGate, FStartGate));
  except
    on E: Exception do
    begin
      // Kein Thread: Start gilt als abgebrochen, der nächste Aufruf versucht es wieder.
      FStartGate.Leave;
      TDpccGuard.Log('Server: Start-Thread nicht gestartet: ' + TDpccGuard.ErrorText(E));
      CancelStart('kein Start-Thread');
    end;
  end;
end;

procedure TDpccCodeInsightSession.StartFinished(const ATicket: IDpccStartTicket);
var
  mServer: IDpccLspServer;
  mSession: TLspSession;
  mError: string;
  mElapsedMs: Int64;
  mJob: TDpccStartJob;
  mSucceeded, mAllowed: Boolean;
  mContext: TDpccProjectContext;
begin
  if FStartTicket = ATicket then
  begin
    FStartTicket := nil;
  end;
  if not ATicket.Take(mServer, mSession, mError, mElapsedMs) then
  begin
    Exit;
  end;
  mJob := ATicket.Job;
  mSucceeded := (mError = '') and (mServer <> nil) and (mSession <> nil) and mServer.Running and
    mSession.Initialized;
  if (mError = '') and not mSucceeded then
  begin
    mError := 'Server endete während des Starts';
  end;
  // Inzwischen abgeschaltet: IDE (SetEnabled), Hauptschalter, Abbau oder Entladen.
  mAllowed := not FShutDown and FEnabled and not TDpccShutdown.Signalled and
    (not mJob.MasterOn or TDpccIdeSettings.Current.Enabled);
  case FLifecycle.FinishStart(mJob.Generation, mSucceeded, mAllowed, TDpccTicks.Now, mError) of
    TDpccStartOutcome.Adopt:
      begin
        // Ab hier ordnet das Ticket die Meldungen des Servers dieser Sitzung zu.
        FSessionTicket := ATicket;
        FServer := mServer;
        FSession := mSession;
        FProjectsChecked := TDpccTicks.Now;
        FContextsChecked := TDpccTicks.Now;
        WatchProjects(mJob.Projects);
        for mContext in mJob.Contexts do
        begin
          Diagnose('Projektkontext: ' + mContext.Describe);
        end;
        FLastError := '';
        FStartedAt := Now;
        SetPhase(TDpccServerPhase.Running, '');
        // Jeder weitere Start ist ein Neustart (#393).
        Inc(FStarts);
        if FStarts > 1 then
        begin
          NotifyRestart(mJob.Crashed, mJob.PreviousStart, Length(mJob.Documents));
        end;
        Diagnose(Format('Serverstart fertig in %d ms (Generation %d)', [mElapsedMs, mJob.Generation]));
        if mJob.Documents <> nil then
        begin
          Diagnose(Format('Nach Neustart erneut geöffnet: %d Dateien', [Length(mJob.Documents)]));
        end;
        QueueIdeTypes(FSession);
        SessionStartDone(True);
      end;
    TDpccStartOutcome.Failed:
      begin
        StopDetachedAsync(mServer, mSession, 'Start fehlgeschlagen');
        Diagnose(Format('Serverstart fehlgeschlagen nach %d ms; nächster Versuch frühestens in %d s',
          [mElapsedMs, TDpccSessionLifecycle.cRetryBlockMs div 1000]));
        ReportError('Start fehlgeschlagen: ' + mError);
        SetPhase(TDpccServerPhase.Failed, TDpccCodeInsightPaths.WithoutPaths(mError));
        SessionStartDone(False);
      end;
  else
    begin
      StopDetachedAsync(mServer, mSession, 'Start verworfen');
      Diagnose(Format('Serverstart verworfen nach %d ms (Generation %d)', [mElapsedMs, mJob.Generation]));
      if FPhase.Phase = TDpccServerPhase.Starting then
      begin
        SetPhase(TDpccServerPhase.Stopped, '', True);
      end;
      SessionStartDone(False);
    end;
  end;
end;

procedure TDpccCodeInsightSession.SessionStartDone(AAdopted: Boolean);
begin
  // Haken für den Manager (gemerkter Sprungwunsch, dpcc.IDE.CodeInsight.Manager).
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

procedure TDpccCodeInsightSession.ServerApplyEdit(const AEdit: TLspWorkspaceEdit; const AReply: TLspApplyEditReply);
var
  mManager: TDpccCodeInsightSession;
  mApplied: Boolean;
  mReason: string;
begin
  mManager := Self;
  mApplied := TDpccServerHandlers.ApplyEdit(AEdit,
    procedure(AMessage: string)
    begin
      mManager.Diagnose(AMessage);
    end, mReason);
  // Genau eine Antwort, auch nach einer Ausnahme.
  AReply(mApplied, mReason);
end;

procedure TDpccCodeInsightSession.ServerShowMessage(AType: Integer; const AMessage: string);
begin
  Diagnose('window/showMessage: ' + AMessage);
  TDpccServerHandlers.ServerMessage(AType, AMessage, LogActions);
end;

procedure TDpccCodeInsightSession.DpccNotified(const AMethod: string; AParams: TJSONValue);
var
  mUnits: TArray<string>;
begin
  if AMethod = TDpccIdeMembers.cWantedMethod then
  begin
    // RTTI der Packages nur im Hauptthread (hier sind wir schon), in Takten; hier nur merken und anstoßen.
    mUnits := TDpccIdeMembers.WantedUnits(AParams);
    if Length(mUnits) > 0 then
    begin
      SendIdeMembers(mUnits);
    end;
  end;
end;

procedure TDpccCodeInsightSession.RefreshProjects;
var
  mProjects: TArray<string>;
  mGeneration: Cardinal;
begin
  // Open Tools API nur im Hauptthread.
  if (GetCurrentThreadId <> MainThreadID) or (TDpccTicks.Since(FProjectsChecked) < cProjectsCheckMs) then
  begin
    Exit;
  end;
  FProjectsChecked := TDpccTicks.Now;
  // V2: Die Liste stammt aus dem letzten vollen Lesen des Projektkontexts (RefreshContexts); melden und Ordner
  // beobachten (Suche nach .git) nur nach einem neuen, nicht je Takt.
  mGeneration := TDpccIdeProjectContext.Generation;
  if mGeneration = FProjectsGeneration then
  begin
    Exit;
  end;
  try
    mProjects := TDpccIdeProjectContext.SavedProjects;
    FSession.SetProjects(mProjects);
    // Erst nach dem Melden: Schlägt es fehl, versucht es der nächste Takt wieder.
    FProjectsGeneration := mGeneration;
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
  mContexts, mChanged: TArray<TDpccProjectContext>;
  mReason: string;
begin
  // Open Tools API nur im Hauptthread.
  if (GetCurrentThreadId <> MainThreadID) or
    ((FContextsChecked <> 0) and (TDpccTicks.Since(FContextsChecked) < cContextsCheckMs)) then
  begin
    Exit;
  end;
  FContextsChecked := TDpccTicks.Now;
  try
    // V2: Je Takt nur der billige Fingerabdruck der Gruppe; voll gelesen (Dateien, Registry, Optionen) nur, wenn er
    // sich geändert hat, nach einem Ereignis (modaler Dialog geschlossen) oder im Sicherheitstakt.
    if not TDpccIdeProjectContext.GroupIfDue(mContexts, mReason) then
    begin
      Exit;
    end;
    // Mit Diagnose=1 prüfbar, ob die geerbten Optionen ankommen (#396).
    mChanged := FSession.SetProjectContexts(mContexts);
    for mContext in mChanged do
    begin
      Diagnose('Projektkontext (' + mReason + '): ' + mContext.Describe);
    end;
  except
    on E: Exception do
    begin
      // Nächster Takt liest wieder voll, wie vor V2.
      TDpccIdeProjectContext.Invalidate;
      Diagnose('Projektkontext nicht gemeldet: ' + E.Message);
    end;
  end;
end;

const
  /// <summary>Namen der Takte für den Wächter (dpcc.log).</summary>
  cIdeTypesActivity = 'IDE-Typen sammeln';
  cIdeMembersActivity = 'IDE-Mitglieder sammeln';

/// <summary>Arbeiter aus TDpccTimeLimit (Post): Typen eindeutig machen, JSON bauen und an ASession senden
/// (dpcc/ideTypes), danach die Diagnosezeile. Hält nur Kopien (Datensätze, Texte) und die Sitzung als rohen Zeiger
/// wie der Abgleich der Formulare: Der Hauptthread hat beim Post geprüft, dass sie noch die laufende ist; der Stopp
/// schließt vorher die Verbindung (Notify sendet dann nichts) und wartet auf diese Arbeiter (TDpccTimeLimit.WaitIdle),
/// bevor er sie freigibt. Nie der Manager.</summary>
function SendIdeTypesWork(ASession: TLspSession; const ATypes: TArray<TDpccIdeType>; const AInfo: string;
  ADiagnose: Boolean): TProc;
var
  mSession: TLspSession;
  mTypes: TArray<TDpccIdeType>;
  mInfo: string;
  mDiagnose: Boolean;
begin
  mSession := ASession;
  mTypes := ATypes;
  mInfo := AInfo;
  mDiagnose := ADiagnose;
  Result :=
    procedure
    var
      mWatch: TStopwatch;
      mUnique: TArray<TDpccIdeType>;
    begin
      mWatch := TStopwatch.StartNew;
      try
        if TDpccShutdown.Signalled then
        begin
          Exit;
        end;
        // Palette und RTTI der Packages melden dieselben Komponenten: einmal je Unit.Typ, der erste bleibt.
        mUnique := TDpccIdeTypes.Unique(mTypes);
        // Nach Initialize: Der Server ersetzt mit jeder Meldung den ganzen Stand und prüft offene Dateien neu.
        mSession.Notify(TDpccIdeTypes.cMethod, TDpccIdeTypes.ToJson(mUnique));
        DiagnoseFrom(mDiagnose, Format('IDE-Typen: %d, %s, im Hintergrund gesendet in %d ms',
          [Length(mUnique), mInfo, mWatch.ElapsedMilliseconds]));
      except
        on E: Exception do
        begin
          DiagnoseFrom(mDiagnose, 'IDE-Typen: ' + E.Message);
        end;
      end;
    end;
end;

/// <summary>Arbeiter aus TDpccTimeLimit (Post): JSON der Mitglieder bauen und an ASession senden (dpcc/ideMembers),
/// danach die Diagnosezeile AInfo mit der Zeit dafür. Lebensdauer der Sitzung wie bei SendIdeTypesWork.</summary>
function SendIdeMembersWork(ASession: TLspSession; const ADetails: TArray<TDpccIdeTypeDetail>; const AInfo: string;
  ADiagnose: Boolean): TProc;
var
  mSession: TLspSession;
  mDetails: TArray<TDpccIdeTypeDetail>;
  mInfo: string;
  mDiagnose: Boolean;
begin
  mSession := ASession;
  mDetails := ADetails;
  mInfo := AInfo;
  mDiagnose := ADiagnose;
  Result :=
    procedure
    var
      mWatch: TStopwatch;
    begin
      mWatch := TStopwatch.StartNew;
      try
        if TDpccShutdown.Signalled then
        begin
          Exit;
        end;
        mSession.Notify(TDpccIdeMembers.cMethod, TDpccIdeMembers.ToJson(mDetails));
        DiagnoseFrom(mDiagnose, Format('%s, im Hintergrund gesendet in %d ms', [mInfo, mWatch.ElapsedMilliseconds]));
      except
        on E: Exception do
        begin
          DiagnoseFrom(mDiagnose, 'IDE-Mitglieder: ' + E.Message);
        end;
      end;
    end;
end;

procedure TDpccCodeInsightSession.QueueIdeTypes(ASession: TLspSession);
var
  mManager: TDpccCodeInsightSession;
  mTicket: IDpccStartTicket;
  mRun: IInterface;
  mStartedAt: UInt64;
begin
  // Neue Sitzung: Ein Lauf der Mitglieder für die alte sendet nichts mehr, wartende Anforderungen entfallen.
  FIdeMembers.Cancel;
  if FShutDown or (ASession = nil) or (ASession <> FSession) or (FSessionTicket = nil) then
  begin
    Exit;
  end;
  try
    mRun := TDpccIdeTypeCollector.StartRun;
  except
    on E: Exception do
    begin
      Diagnose('IDE-Typen: ' + E.Message);
      Exit;
    end;
  end;
  // Nur im Hauptthread verglichen (ManagerLive), nie in einem anderen Thread benutzt.
  mManager := Self;
  mTicket := FSessionTicket;
  mStartedAt := TDpccTicks.Now;
  // Jeder Takt ein eigener Eintrag mit Namen für den Wächter, auch der erste (nicht mehr in der Übernahme).
  TDpccMainThread.ForceQueue(TDpccFeature.Server, cIdeTypesActivity,
    procedure
    begin
      if ManagerLive(mManager) then
      begin
        mManager.StepIdeTypes(mTicket, mRun, mStartedAt);
      end;
    end);
end;

procedure TDpccCodeInsightSession.StepIdeTypes(const ATicket: IDpccStartTicket; const ARun: IInterface;
  AStartedAt: UInt64);
var
  mRun: IDpccIdeTypeRun;
  mManager: TDpccCodeInsightSession;
  mTicket: IDpccStartTicket;
  mNext: IInterface;
  mStartedAt: UInt64;
  mStats: TDpccSliceStats;
  mCache: string;
  mInfo: string;
begin
  // Sitzung gewechselt, gestoppt, „Index neu aufbauen“ oder entladen: abbrechen, nichts senden; die neue sammelt
  // selbst. Das Ticket statt des Zeigers: Eine neue Sitzung kann an derselben Adresse liegen.
  if FShutDown or (ATicket = nil) or (FSessionTicket <> ATicket) or (FSession = nil) or
    not Supports(ARun, IDpccIdeTypeRun, mRun) then
  begin
    Exit;
  end;
  try
    // RTTI nur im Hauptthread, in kleinen Stücken: Zwischen den Takten bleibt die IDE bedienbar.
    if not mRun.Step(cIdeTypesSliceMs) then
    begin
      mManager := Self;
      mTicket := ATicket;
      mNext := ARun;
      mStartedAt := AStartedAt;
      TDpccMainThread.ForceQueue(TDpccFeature.Server, cIdeTypesActivity,
        procedure
        begin
          if ManagerLive(mManager) then
          begin
            mManager.StepIdeTypes(mTicket, mNext, mStartedAt);
          end;
        end);
      Exit;
    end;
    mStats := mRun.Stats;
    mCache := '';
    if mRun.FromCache then
    begin
      mCache := ', gemerkt';
    end;
    mInfo := Format('%d Module, %d Takte, %d ms bis fertig, %d ms in Takten, längster Takt %d ms, ' +
      'RTTI unlesbar: %d%s', [mRun.Modules, mStats.Steps, TDpccTicks.Since(AStartedAt), mStats.TotalMs,
      mStats.LongestMs, mRun.Failed, mCache]);
    // Eindeutig machen, JSON und Senden im Hintergrund; FSession ist hier noch die Sitzung des Laufs.
    if not TDpccTimeLimit.Post(SendIdeTypesWork(FSession, mRun.Types, mInfo, FDiagnose)) then
    begin
      Diagnose('IDE-Typen: nicht gesendet, dpcc wird beendet');
    end;
  except
    on E: Exception do
    begin
      Diagnose('IDE-Typen: ' + E.Message);
    end;
  end;
end;

procedure TDpccCodeInsightSession.SendIdeMembers(const AUnits: TArray<string>);
begin
  // Läuft schon ein Lauf, kommen die Units dazu und laufen danach genau einmal zusammen; nie zwei Läufe zugleich.
  if FIdeMembers.Request(AUnits) then
  begin
    StartIdeMembers;
  end;
end;

procedure TDpccCodeInsightSession.StartIdeMembers;
var
  mUnits: TArray<string>;
  mGeneration: Cardinal;
  mManager: TDpccCodeInsightSession;
  mTicket: IDpccStartTicket;
  mRun: IInterface;
  mStartedAt: UInt64;
begin
  if FShutDown or (FSession = nil) or (FSessionTicket = nil) then
  begin
    FIdeMembers.Cancel;
    Exit;
  end;
  if not FIdeMembers.TryStart(mUnits, mGeneration) then
  begin
    Exit;
  end;
  try
    mRun := TDpccIdeMemberCollector.StartRun(mUnits);
  except
    on E: Exception do
    begin
      Diagnose('IDE-Mitglieder: ' + E.Message);
      FIdeMembers.Cancel;
      Exit;
    end;
  end;
  mManager := Self;
  mTicket := FSessionTicket;
  mStartedAt := TDpccTicks.Now;
  TDpccMainThread.ForceQueue(TDpccFeature.Server, cIdeMembersActivity,
    procedure
    begin
      if ManagerLive(mManager) then
      begin
        mManager.StepIdeMembers(mTicket, mRun, mGeneration, mStartedAt);
      end;
    end);
end;

procedure TDpccCodeInsightSession.StepIdeMembers(const ATicket: IDpccStartTicket; const ARun: IInterface;
  AGeneration: Cardinal; AStartedAt: UInt64);
var
  mRun: IDpccIdeMemberRun;
  mManager: TDpccCodeInsightSession;
  mTicket: IDpccStartTicket;
  mNext: IInterface;
  mGeneration: Cardinal;
  mStartedAt: UInt64;
  mDetails: TArray<TDpccIdeTypeDetail>;
  mStats: TDpccSliceStats;
  mScope: string;
  mInfo: string;
begin
  // Abgelöst (neue Sitzung, Abbruch): Der neue Stand gilt.
  if not FIdeMembers.IsCurrent(AGeneration) then
  begin
    Exit;
  end;
  // Sitzung gewechselt, gestoppt, „Index neu aufbauen“ oder entladen: abbrechen, nichts senden.
  if FShutDown or (ATicket = nil) or (FSessionTicket <> ATicket) or (FSession = nil) or
    not Supports(ARun, IDpccIdeMemberRun, mRun) then
  begin
    FIdeMembers.Cancel;
    Exit;
  end;
  // Nur im Hauptthread verglichen (ManagerLive), nie in einem anderen Thread benutzt.
  mManager := Self;
  try
    // RTTI nur im Hauptthread, in kleinen Stücken: Zwischen den Takten bleibt die IDE bedienbar.
    if not mRun.Step(cIdeTypesSliceMs) then
    begin
      mTicket := ATicket;
      mNext := ARun;
      mGeneration := AGeneration;
      mStartedAt := AStartedAt;
      TDpccMainThread.ForceQueue(TDpccFeature.Server, cIdeMembersActivity,
        procedure
        begin
          if ManagerLive(mManager) then
          begin
            mManager.StepIdeMembers(mTicket, mNext, mGeneration, mStartedAt);
          end;
        end);
      Exit;
    end;
    mDetails := mRun.Details;
    mStats := mRun.Stats;
    mScope := 'alle';
    if mRun.Filtered then
    begin
      mScope := 'nur die der Units';
    end;
    // ms = Summe der Takte im Hauptthread.
    mInfo := Format('IDE-Mitglieder: %d Units, %d Typen, %d ms, %d Schritte, längster Schritt %d ms, ' +
      '%d ms bis fertig, %d Packages (%s), RTTI unlesbar: %d', [mRun.UnitCount, Length(mDetails), mStats.TotalMs,
      mStats.Steps, mStats.LongestMs, TDpccTicks.Since(AStartedAt), mRun.Packages, mScope, mRun.Failed]);
    // JSON und Senden im Hintergrund; FSession ist hier noch die Sitzung des Laufs.
    if not TDpccTimeLimit.Post(SendIdeMembersWork(FSession, mDetails, mInfo, FDiagnose)) then
    begin
      Diagnose('IDE-Mitglieder: nicht gesendet, dpcc wird beendet');
    end;
  except
    on E: Exception do
    begin
      Diagnose('IDE-Mitglieder: ' + E.Message);
    end;
  end;
  // Lauf zu Ende (auch nach einem Fehler): Was inzwischen angefordert wurde, läuft genau einmal danach.
  if FIdeMembers.Finish(AGeneration) then
  begin
    TDpccMainThread.ForceQueue(TDpccFeature.Server, cIdeMembersActivity,
      procedure
      begin
        if ManagerLive(mManager) then
        begin
          mManager.StartIdeMembers;
        end;
      end);
  end;
end;

procedure TDpccCodeInsightSession.WatchProjects(const AProjects: TArray<string>);
begin
  if FFolderWatcher = nil then
  begin
    Exit;
  end;
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
  if (GetCurrentThreadId <> MainThreadID) or (FFileChanges = nil) then
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
