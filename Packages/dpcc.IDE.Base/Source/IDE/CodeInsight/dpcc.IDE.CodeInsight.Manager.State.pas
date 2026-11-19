unit dpcc.IDE.CodeInsight.Manager.State;

// Zustand des Code Insight-Managers, unterste Stufe der Klassenkette State → Session → Commands →
// Crashes → Manager: Server, Sitzung, Phase für das Statusfeld (#591, #754), Abstürze (#1355), Haken der
// Kompositionswurzel und das Diagnoseprotokoll.

interface

uses
  System.SysUtils,
  System.Classes,
  dpcc.Core.Status.Lines,
  dpcc.Core.Diagnostics.ThreadList,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.Crashes,
  dpcc.Core.Lsp.CrashCases,
  dpcc.Core.Files.WatchedChanges,
  dpcc.Core.Signature.Contract,
  dpcc.Core.Notifications.Contract,
  dpcc.IDE.Completion.Editor,
  dpcc.IDE.CodeInsight.Manager.Editors;

type
  /// <summary>Adapter des Kerns, eingesetzt von der Kompositionswurzel.</summary>
  TDpccCodeInsightAdapters = record
    /// <summary>Startet den Server im IDE-Prozess (Package dpcc.Server, seit S1 der einzige Betrieb); löst bei
    /// Fehlern der Wurzel eine Exception aus.</summary>
    NewServer: TFunc<IDpccLspServer>;
    NewFolderWatcher: TFunc<TDpccWatchedChanges, IDpccFolderWatcher>;
    NewCompletionSources: TDpccCompletionSourcesFactory;
    NewSignatureSource: TFunc<TDpccSessionFunc, IDpccSignatureSource>;
  end;

  /// <summary>Phase des Servers für das Statusfeld (#591) mit Beginn (Ortszeit) und „von dpcc beendet“ (#754).
  /// </summary>
  TDpccServerPhaseState = record
    Phase: TDpccServerPhase;
    Error: string;
    Since: TDateTime;
    Ended: Boolean;
  end;

  /// <summary>Zustand und Protokoll des Managers; die Stufen darüber starten die Sitzung, schicken Befehle,
  /// melden Abstürze und bedienen die IDE.</summary>
  TDpccCodeInsightState = class(TInterfacedObject)
  protected
    FEnabled: Boolean;
    FAdapters: TDpccCodeInsightAdapters;
    FServer: IDpccLspServer;
    FSession: TLspSession;
    FLastError: string;
    FDiagnose: Boolean;
    FPhase: TDpccServerPhaseState;
    /// <summary>DetachSession schließt gerade die Verbindung: Ein Ende des Servers jetzt ist kein Absturz.</summary>
    FStopping: Boolean;
    /// <summary>Shutdown ist gelaufen: Sitzung, Threads und Editor-Anbindungen sind weg (#886).</summary>
    FShutDown: Boolean;
    FOnServerChanged: TProc;
    FOnOpenLog: TProc;
    FOnBugReport: TProc;
    FOnCrashIssue: TProc<TDpccCrashCase>;
    /// <summary>Erfolgreiche Starts des Servers; ab dem zweiten meldet jeder „Server neu gestartet“ (#601).
    /// </summary>
    FStarts: Integer;
    /// <summary>Abstürze des Servers; nach zwei gleichen startet dpcc ihn nicht mehr still neu.</summary>
    FCrashes: TDpccServerCrashes;
    /// <summary>Anfragen, die der Server gerade nach Absturz überspringt (#1355); nur im Hauptthread.</summary>
    FCrashSkips: TDpccCrashSkips;
    /// <summary>Start der laufenden Sitzung; nach einem Absturz gilt ein Fall ab hier als dessen Ursache.</summary>
    FStartedAt: TDateTime;
    /// <summary>Vervollständigung, Parameter-Hint und Hover.</summary>
    FEditors: TDpccCodeInsightEditors;
    /// <summary>Threads von Statusabfrage, Befehlen und Bedienbefehlen; Destroy wartet auf ihr Ende (#886).</summary>
    FThreads: TDpccThreadList;
    procedure SetPhase(APhase: TDpccServerPhase; const AError: string); overload;
    procedure SetPhase(APhase: TDpccServerPhase; const AError: string; AEnded: Boolean); overload;
    /// <summary>OnServerChanged aufrufen, falls gesetzt; aus jedem Thread.</summary>
    procedure ServerChanged;
    /// <summary>Aktion „Protokoll öffnen“ für Einträge der Benachrichtigungszentrale (#601); leer ohne OnOpenLog.
    /// </summary>
    function LogActions: TArray<TDpccNotificationAction>;
    procedure ReportError(const AMessage: string);
    procedure Diagnose(const AMessage: string);
    /// <summary>Server läuft und die Sitzung ist initialisiert, auch während DetachSession.</summary>
    function ReadySession: TLspSession;
  public
    constructor Create(const AAdapters: TDpccCodeInsightAdapters);
    destructor Destroy; override;
    /// <summary>Laufende, initialisierte Sitzung oder nil; startet keinen Server (#402).</summary>
    function RunningSession: TLspSession;
    /// <summary>Fortschritt des Servers ("Index 45 %"); '' ohne Sitzung oder Vorgang. Startet keinen Server
    /// (#492).</summary>
    function ServerProgress: string;
    /// <summary>Stand des Servers für das Statusfeld (#591); startet keinen Server.</summary>
    function ServerInfo: TDpccServerInfo;
    /// <summary>Indizierung läuft? APercent = Fortschritt, -1 = unbekannt; False ohne Sitzung.</summary>
    function ServerIndexing(out APercent: Integer): Boolean;
    /// <summary>Wie ServerIndexing für den Vorgang AToken (ein Projekt der Gruppe, #2142).</summary>
    function ServerIndexingOf(const AToken: string; out APercent: Integer): Boolean;
    /// <summary>Zeile im Diagnoseprotokoll (nur mit Diagnose = 1).</summary>
    procedure Log(const AMessage: string);
    /// <summary>Zeile im Protokoll unabhängig von Diagnose, z. B. Hänger (#501).</summary>
    procedure Report(const AMessage: string);
    /// <summary>Phase, Version oder Fortschritt haben sich geändert; aus jedem Thread.</summary>
    property OnServerChanged: TProc read FOnServerChanged write FOnServerChanged;
    /// <summary>„Protokoll öffnen“ für die Einträge der Quelle Server in der Benachrichtigungszentrale (#601).
    /// </summary>
    property OnOpenLog: TProc read FOnOpenLog write FOnOpenLog;
    /// <summary>„Fehlerbericht erstellen…“ in der Meldung nach zwei gleichen Abstürzen des Servers.
    /// </summary>
    property OnBugReport: TProc read FOnBugReport write FOnBugReport;
    /// <summary>„Issue anlegen“ in der Meldung zu einem Absturzfall (#1355, Dialog aus #1268).</summary>
    property OnCrashIssue: TProc<TDpccCrashCase> read FOnCrashIssue write FOnCrashIssue;
  end;

/// <summary>Ist AManager der lebende Manager? Späte Einträge im Hauptthread (applyEdit, Meldungen) tun sonst nichts.
/// </summary>
function ManagerLive(AManager: TObject): Boolean;
/// <summary>AManager ist abgebaut (Shutdown): ab jetzt nicht mehr lebend.</summary>
procedure RetireManager(AManager: TObject);
/// <summary>Der lebende Manager oder nil; nur im Hauptthread benutzen (dort wird er auch abgebaut). Rückmeldungen
/// der Hintergrund-Threads suchen ihn erst hier, statt ihn selbst zu halten.</summary>
function LiveManagerObject: TObject;

implementation

uses
  dpcc.UI.Strings,
  dpcc.UI.CodeInsight.Strings,
  dpcc.Core.Notifications.Center,
  dpcc.Core.Notifications.Sources,
  dpcc.IDE.CodeInsight.Manager.Paths,
  ToolsAPI;

var
  /// <summary>Lebender Manager; nach dem Abbau nil, damit späte applyEdit-Aufrufe nichts mehr tun.</summary>
  LiveManager: TObject;

function ManagerLive(AManager: TObject): Boolean;
begin
  Result := (AManager <> nil) and (LiveManager = AManager);
end;

procedure RetireManager(AManager: TObject);
begin
  if LiveManager = AManager then
  begin
    LiveManager := nil;
  end;
end;

function LiveManagerObject: TObject;
begin
  Result := LiveManager;
end;

{ TDpccCodeInsightState }

constructor TDpccCodeInsightState.Create(const AAdapters: TDpccCodeInsightAdapters);
begin
  inherited Create;
  FAdapters := AAdapters;
  LiveManager := Self;
  FEnabled := True;
  FDiagnose := TDpccCodeInsightPaths.DiagnoseEnabled;
  FPhase := Default(TDpccServerPhaseState);
  FPhase.Phase := TDpccServerPhase.NotStarted;
  FThreads := TDpccThreadList.Create;
  FCrashes := TDpccServerCrashes.Create(nil);
  FCrashSkips := TDpccCrashSkips.Create;
end;

destructor TDpccCodeInsightState.Destroy;
begin
  RetireManager(Self);
  FreeAndNil(FThreads);
  // Nach Shutdown: Kein Lese-Thread meldet mehr ein Ende.
  FreeAndNil(FCrashes);
  FreeAndNil(FCrashSkips);
  inherited;
end;

procedure TDpccCodeInsightState.ServerChanged;
var
  mChanged: TProc;
begin
  mChanged := FOnServerChanged;
  if Assigned(mChanged) then
  begin
    mChanged();
  end;
end;

procedure TDpccCodeInsightState.SetPhase(APhase: TDpccServerPhase; const AError: string);
begin
  SetPhase(APhase, AError, False);
end;

procedure TDpccCodeInsightState.SetPhase(APhase: TDpccServerPhase; const AError: string; AEnded: Boolean);
begin
  // Ein beendeter Server bleibt beendet, bis er wieder startet; der Zeitpunkt bleibt der erste.
  if (APhase <> FPhase.Phase) or (AEnded <> FPhase.Ended) then
  begin
    FPhase.Since := Now;
  end;
  FPhase.Phase := APhase;
  FPhase.Error := AError;
  FPhase.Ended := (APhase = TDpccServerPhase.Stopped) and AEnded;
  ServerChanged;
end;

function TDpccCodeInsightState.LogActions: TArray<TDpccNotificationAction>;
begin
  Result := nil;
  if Assigned(FOnOpenLog) then
  begin
    Result := [TDpccNotificationCenter.Action(TDpccStrings.Text(TDpccTextId.StatusOpenLog), FOnOpenLog)];
  end;
end;

procedure TDpccCodeInsightState.ReportError(const AMessage: string);
var
  mMessages: IOTAMessageServices;
  mMode: TDpccNotificationMode;
begin
  Diagnose('Fehler: ' + AMessage);
  // Jede Meldung nur einmal, sonst flutet ein fehlender Server das Meldungsfenster.
  if AMessage = FLastError then
  begin
    Exit;
  end;
  FLastError := AMessage;
  // Benachrichtigungszentrale (#601): bei „nur sammeln“ oder „aus“ keine Zeile im Meldungsfenster.
  mMode := TDpccNotificationCenter.Default.Notify(TDpccNotificationSources.cServer,
    TDpccNotificationSeverity.Error, TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.NotificationsServerError),
    AMessage,
    LogActions);
  if (mMode = TDpccNotificationMode.Show) and Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    mMessages.AddTitleMessage('dpcc: ' + AMessage);
  end;
end;

procedure TDpccCodeInsightState.Diagnose(const AMessage: string);
begin
  // Diagnose darf die IDE nie stören.
  if FDiagnose then
  begin
    TDpccCodeInsightPaths.Append(AMessage);
  end;
end;

procedure TDpccCodeInsightState.Log(const AMessage: string);
begin
  Diagnose(AMessage);
end;

procedure TDpccCodeInsightState.Report(const AMessage: string);
begin
  TDpccCodeInsightPaths.Append(AMessage);
end;

function TDpccCodeInsightState.ReadySession: TLspSession;
begin
  Result := nil;
  if (FServer <> nil) and FServer.Running and (FSession <> nil) and FSession.Initialized then
  begin
    Result := FSession;
  end;
end;

function TDpccCodeInsightState.RunningSession: TLspSession;
begin
  Result := nil;
  // Während DetachSession nie: Die Sitzung wird gleich gelöst und im Hintergrund freigegeben. Aus jedem Thread
  // aufrufbar.
  if not FStopping then
  begin
    Result := ReadySession;
  end;
end;

function TDpccCodeInsightState.ServerProgress: string;
begin
  Result := '';
  if (FSession <> nil) and FSession.Initialized then
  begin
    Result := FSession.ProgressText;
  end;
end;

function TDpccCodeInsightState.ServerInfo: TDpccServerInfo;
begin
  Result := Default(TDpccServerInfo);
  Result.Phase := FPhase.Phase;
  Result.Error := FPhase.Error;
  Result.Since := FPhase.Since;
  Result.Ended := FPhase.Ended;
  Result.Version := '';
  Result.AverageMs := 0;
  Result.Samples := 0;
  if (FSession <> nil) and FSession.Initialized then
  begin
    Result.Version := FSession.ServerVersion;
  end;
  if FServer <> nil then
  begin
    Result.AverageMs := FServer.Client.AverageMs(Result.Samples);
  end;
  if (FCrashSkips <> nil) and (FPhase.Phase = TDpccServerPhase.Running) then
  begin
    Result.Skipped := FCrashSkips.Count;
  end;
end;

function TDpccCodeInsightState.ServerIndexing(out APercent: Integer): Boolean;
begin
  APercent := -1;
  Result := (FSession <> nil) and FSession.Initialized and FSession.Indexing(APercent);
end;

function TDpccCodeInsightState.ServerIndexingOf(const AToken: string; out APercent: Integer): Boolean;
begin
  APercent := -1;
  Result := (FSession <> nil) and FSession.Initialized and FSession.IndexingOf(AToken, APercent);
end;

end.
