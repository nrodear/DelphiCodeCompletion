unit dpcc.IDE.CodeInsight.Manager.Crashes;

// Abstürze des Servers im Code Insight-Manager, vierte Stufe der Klassenkette. Ende des Servers: Endet
// er von selbst, steht in dpcc.log, womit (Exit-Code, etwa Stapelüberlauf), nach welcher Laufzeit, bei welcher
// Anfrage und wie viel er auf stderr schrieb; das Statusfeld nennt die Ursache. Den ersten Absturz startet die
// nächste Anfrage wie bisher neu. Endet er zweimal mit demselben Code innerhalb von zehn Minuten, startet dpcc ihn
// nicht mehr still neu, sondern meldet es mit „Server neu starten“ und „Fehlerbericht erstellen…“
// (TDpccServerCrashes). Ein Start von Hand hebt das auf.
// Absturzfälle (#1355): Der Server sichert jeden Absturz einer Anfrage als Fall und meldet ihn mit dpcc/crashCase;
// stirbt er dabei, sucht der Neustart den jüngsten Fall seit dem letzten Start. Die Meldung nennt Methode, Datei,
// Zeile und Ausnahme, mit „Fall öffnen“, „Issue anlegen“ (OnCrashIssue) und „Ausblenden“. Übersprungene Anfragen
// (dpcc/crashSkip, Sicherheitsnetz) zählt ServerInfo.Skipped für die Statusleiste; das Prüffenster zeigt sie als
// Warnung an der Datei, die Meldung bietet „Erneut versuchen“.

interface

uses
  System.SysUtils,
  System.JSON,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.CrashCases,
  dpcc.IDE.CodeInsight.Manager.Commands;

type
  /// <summary>Ende und Abstürze des Servers, Absturzfälle und übersprungene Anfragen.</summary>
  TDpccCodeInsightCrashes = class(TDpccCodeInsightCommands)
  protected
    /// <summary>Der Server endete von selbst (Hauptthread, aus ClientClosed): Ursache, Laufzeit und letzte Anfrage
    /// ins Protokoll, Ursache ins Statusfeld; nach zwei gleichen Abstürzen anhalten (ServerHeld).</summary>
    procedure ServerEnded(const AInfo: TLspCloseInfo); override;
    /// <summary>Hauptthread: Statusfeld und Benachrichtigung mit Neustart und Fehlerbericht.</summary>
    procedure ServerHeld(ACode: Cardinal);
    /// <summary>Hauptthread nach ServerEnded: anhalten oder die Ursache ins Statusfeld.</summary>
    procedure ServerEndedMain(ACode: Cardinal; AContinues: Boolean);
    /// <summary>Hauptthread: dpcc/crashCase und dpcc/crashSkip (#1355) melden; dpcc/ideMembersWanted an die Stufe
    /// Session.</summary>
    procedure DpccNotified(const AMethod: string; AParams: TJSONValue); override;
    procedure CrashCaseSaved(const ACase: TDpccCrashCase);
    procedure CrashSkipChanged(const ASkip: TDpccCrashSkip);
    /// <summary>„Erneut versuchen“ einer übersprungenen Anfrage an AUri.</summary>
    function RetryAction(const AUri: string): TProc;
  end;

implementation

uses
  dpcc.UI.Strings,
  dpcc.UI.CodeInsight.Strings,
  dpcc.Core.Status.Lines,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Lsp.Crashes,
  dpcc.Core.Lsp.IdeMembers,
  dpcc.Core.Notifications.Contract,
  dpcc.Core.Notifications.Center,
  dpcc.Core.Notifications.Sources,
  dpcc.IDE.CodeInsight.Manager.State,
  dpcc.IDE.CodeInsight.Manager.Handlers;

procedure TDpccCodeInsightCrashes.ServerEnded(const AInfo: TLspCloseInfo);
var
  mManager: TDpccCodeInsightCrashes;
  mCode: Cardinal;
  mLine: string;
  mContinues: Boolean;
begin
  mCode := TDpccServerExits.cUnknown;
  if AInfo.ExitKnown then
  begin
    mCode := AInfo.ExitCode;
  end;
  mLine := TDpccServerExits.Line(mCode, AInfo.RuntimeMs, AInfo.LastMethod, AInfo.OpenMethods);
  // dpcc.log für den Fehlerbericht, das Diagnoseprotokoll für den zeitlichen Zusammenhang mit den Aufrufen.
  TDpccGuard.Log(mLine);
  Report(mLine);
  mContinues := FCrashes.Crashed(mCode);
  if not mContinues then
  begin
    TDpccGuard.Log(Format('Server: zweimal %s innerhalb von %d min, kein weiterer Start ohne Zutun',
      [TDpccServerExits.Describe(mCode), TDpccServerCrashes.cWindowMinutes]));
  end;
  mManager := Self;
  // Statusfeld und Benachrichtigung im Hauptthread: Der Fehlertext der Phase ist ein String, den der Hauptthread
  // liest.
  TDpccMainThread.Queue(TDpccFeature.Server,
    procedure
    begin
      if ManagerLive(mManager) then
      begin
        mManager.ServerEndedMain(mCode, mContinues);
      end;
    end);
end;

procedure TDpccCodeInsightCrashes.ServerEndedMain(ACode: Cardinal; AContinues: Boolean);
begin
  if not AContinues then
  begin
    ServerHeld(ACode);
  end
  // Inzwischen neu gestartet oder von dpcc beendet: Die Ursache gehört nicht mehr ins Statusfeld.
  else if (FPhase.Phase = TDpccServerPhase.Stopped) and not FPhase.Ended then
  begin
    SetPhase(TDpccServerPhase.Stopped, TDpccServerExits.Describe(ACode));
  end;
end;

procedure TDpccCodeInsightCrashes.ServerHeld(ACode: Cardinal);
var
  mManager: TDpccCodeInsightCrashes;
  mActions: TArray<TDpccNotificationAction>;
  mCause: string;
begin
  // Von Hand neu gestartet, bevor dieser Eintrag dran war: nichts mehr zu melden.
  if not FCrashes.Held then
  begin
    Exit;
  end;
  mCause := TDpccServerExits.Describe(ACode);
  SetPhase(TDpccServerPhase.Stopped, TDpccCodeInsightStrings.Fmt(TDpccCodeInsightTextId.ServerHeldPhase, [mCause]));
  mManager := Self;
  mActions := [TDpccNotificationCenter.Action(TDpccStrings.Text(TDpccTextId.StatusRestartServer),
    procedure
    begin
      if ManagerLive(mManager) then
      begin
        mManager.RestartServer;
      end;
    end)];
  if Assigned(FOnBugReport) then
  begin
    mActions := mActions + [TDpccNotificationCenter.Action(TDpccStrings.Text(TDpccTextId.BugReportMenu),
      FOnBugReport)];
  end;
  mActions := mActions + LogActions;
  TDpccNotificationCenter.Default.Notify(TDpccNotificationSources.cServer, TDpccNotificationSeverity.Error,
    TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.ServerHeldTitle),
    TDpccCodeInsightStrings.Fmt(TDpccCodeInsightTextId.ServerHeldText, [mCause, TDpccServerCrashes.cWindowMinutes]),
    mActions);
end;

procedure TDpccCodeInsightCrashes.DpccNotified(const AMethod: string; AParams: TJSONValue);
var
  mCase: TDpccCrashCase;
  mSkip: TDpccCrashSkip;
begin
  // Hauptthread, schon der Sitzung zugeordnet (SessionOf); AParams gehört dem Aufrufer.
  if AMethod = TDpccCrashCases.cCaseNotification then
  begin
    if TDpccCrashCases.ParseCase(AParams, mCase) then
    begin
      CrashCaseSaved(mCase);
    end;
  end
  else if AMethod = TDpccCrashCases.cSkipNotification then
  begin
    if TDpccCrashCases.ParseSkip(AParams, mSkip) then
    begin
      CrashSkipChanged(mSkip);
    end;
  end
  else
  begin
    // dpcc/ideMembersWanted und weitere.
    inherited DpccNotified(AMethod, AParams);
  end;
end;

procedure TDpccCodeInsightCrashes.CrashCaseSaved(const ACase: TDpccCrashCase);
begin
  Diagnose('Absturzfall gesichert: ' + ACase.Summary);
  TDpccNotificationCenter.Default.Notify(TDpccNotificationSources.cServer, TDpccNotificationSeverity.Warning,
    TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.CrashCaseTitle),
    TDpccCodeInsightStrings.Fmt(TDpccCodeInsightTextId.CrashCaseText, [TDpccCrashCases.SummaryText(ACase)]),
    TDpccServerHandlers.CrashActions(ACase, FOnCrashIssue));
end;

function TDpccCodeInsightCrashes.RetryAction(const AUri: string): TProc;
var
  mManager: TDpccCodeInsightCrashes;
  mUri: string;
begin
  mManager := Self;
  mUri := AUri;
  Result :=
    procedure
    var
      mArguments: TJSONArray;
    begin
      // Die Meldung kann den Manager überleben (Entladen).
      if not ManagerLive(mManager) then
      begin
        Exit;
      end;
      mArguments := TDpccCrashCases.RetryArguments(mUri);
      try
        mManager.RunServerCommandAsync(TDpccCrashCases.cRetryCommand, mArguments.ToJSON, 5000, nil);
      finally
        mArguments.Free;
      end;
    end;
end;

procedure TDpccCodeInsightCrashes.CrashSkipChanged(const ASkip: TDpccCrashSkip);
var
  mName: string;
begin
  if not FCrashSkips.Apply(ASkip) then
  begin
    Exit;
  end;
  mName := TDpccServerHandlers.SkipName(ASkip);
  if ASkip.Active then
  begin
    TDpccNotificationCenter.Default.Notify(TDpccNotificationSources.cServer, TDpccNotificationSeverity.Warning,
      TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.CrashSkipTitle),
      TDpccCodeInsightStrings.Fmt(TDpccCodeInsightTextId.CrashSkipText,
      [ASkip.Method, mName, ASkip.Crashes, ASkip.ExceptionClass]),
      [TDpccNotificationCenter.Action(TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.CrashRetry),
      RetryAction(ASkip.Uri))]);
  end
  else
  begin
    TDpccNotificationCenter.Default.Notify(TDpccNotificationSources.cServer, TDpccNotificationSeverity.Info,
      TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.CrashSkipTitle),
      TDpccCodeInsightStrings.Fmt(TDpccCodeInsightTextId.CrashSkipEnded,
      [ASkip.Method, mName]), LogActions);
  end;
  ServerChanged;
end;

end.
