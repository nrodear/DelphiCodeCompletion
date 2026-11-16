unit dpcc.IDE.CodeInsight.Manager.Handlers;

// Antworten des Code Insight-Managers auf den Server, jeweils im Hauptthread: window/showMessage ins Meldungsfenster
// (#121) und Einträge der Benachrichtigungszentrale zu Neustart (#393, #601) und Absturzfall (#1355).
// Seit Rückbau R6: workspace/applyEdit lehnt dpcc ab (der Completion-Server schickt keines mehr; ohne
// Code-Aktionen und Refactorings gibt es nichts zu übernehmen), übersprungene Anfragen stehen nur noch in der
// Benachrichtigung, nicht mehr im Prüffenster.

interface

uses
  System.SysUtils,
  dpcc.Core.Lsp.WorkspaceEdits,
  dpcc.Core.Lsp.CrashCases,
  dpcc.Core.Notifications.Contract;

type
  /// <summary>Was der Eintrag „Server neu gestartet“ nennt.</summary>
  TDpccServerRestart = record
    /// <summary>Vom Server selbst beendet, nicht von dpcc.</summary>
    Crashed: Boolean;
    /// <summary>Exit-Code des abgestürzten Servers, falls bekannt.</summary>
    CodeKnown: Boolean;
    Code: Cardinal;
    /// <summary>Start der vorigen Sitzung; ein Absturzfall ab hier gehört zum Absturz.</summary>
    PreviousStart: TDateTime;
    /// <summary>Dateien, die der neue Server sofort wieder bekam (#393).</summary>
    Reopened: Integer;
    LogActions: TArray<TDpccNotificationAction>;
    CrashIssue: TProc<TDpccCrashCase>;
  end;

  /// <summary>Antworten auf den Server im Hauptthread.</summary>
  TDpccServerHandlers = record
  public
    /// <summary>workspace/applyEdit: seit Rückbau R6 immer False mit AReason „nicht unterstützt“.</summary>
    class function ApplyEdit(const AEdit: TLspWorkspaceEdit; const ADiagnose: TProc<string>;
      out AReason: string): Boolean; static;
    /// <summary>Fehler (1) rot, Warnung (2) gelb in die Benachrichtigungszentrale (#601); im Meldungsfenster nur
    /// bei der Einstellung „zeigen“.</summary>
    class procedure ServerMessage(AType: Integer; const AMessage: string;
      const ALogActions: TArray<TDpccNotificationAction>); static;
    /// <summary>„Server neu gestartet“ (#601); drei innerhalb von 10 s fasst die Zentrale zusammen.</summary>
    class procedure NotifyRestarted(const ARestart: TDpccServerRestart); static;
    /// <summary>„Fall öffnen“, „Issue anlegen“ (nur mit AIssue) und „Ausblenden“ (#1355).</summary>
    class function CrashActions(const ACase: TDpccCrashCase;
      const AIssue: TProc<TDpccCrashCase>): TArray<TDpccNotificationAction>; static;
    /// <summary>Name einer übersprungenen Anfrage für die Meldung: Datei, sonst Uri.</summary>
    class function SkipName(const ASkip: TDpccCrashSkip): string; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.ShellAPI,
  ToolsAPI,
  dpcc.UI.CodeInsight.Strings,
  dpcc.Core.Lsp.Crashes,
  dpcc.Core.Notifications.Center,
  dpcc.Core.Notifications.Sources,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  THandlersText = (ApplyEditUnsupported);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, THandlersText] of string = (
    ('Änderungen vom Server (workspace/applyEdit) werden nicht unterstützt.'),
    ('Edits from the server (workspace/applyEdit) are not supported.'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: THandlersText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

class function TDpccServerHandlers.ApplyEdit(const AEdit: TLspWorkspaceEdit; const ADiagnose: TProc<string>;
  out AReason: string): Boolean;
begin
  Result := False;
  AReason := UiText(THandlersText.ApplyEditUnsupported);
  ADiagnose('workspace/applyEdit abgelehnt: nicht unterstützt');
end;

/// <summary>Zeile in der Meldungsansicht, Gruppe „dpcc“.</summary>
procedure MessageLine(const AText: string);
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mGroup := mMessages.GetGroup('dpcc');
  if mGroup = nil then
  begin
    mGroup := mMessages.AddMessageGroup('dpcc');
  end;
  mMessages.AddTitleMessage(AText, mGroup);
end;

class procedure TDpccServerHandlers.ServerMessage(AType: Integer; const AMessage: string;
  const ALogActions: TArray<TDpccNotificationAction>);
var
  mSeverity: TDpccNotificationSeverity;
begin
  mSeverity := TDpccNotificationSeverity.Warning;
  if AType = 1 then
  begin
    mSeverity := TDpccNotificationSeverity.Error;
  end;
  if TDpccNotificationCenter.Default.Notify(TDpccNotificationSources.cServer, mSeverity,
    TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.NotificationsServerMessage), AMessage, ALogActions) <>
    TDpccNotificationMode.Show then
  begin
    Exit;
  end;
  MessageLine('dpcc: ' + AMessage);
end;

/// <summary>Ursache des Neustarts und erneut geöffnete Dateien als Text des Eintrags.</summary>
function RestartText(const ARestart: TDpccServerRestart): string;
begin
  Result := '';
  if ARestart.Crashed and ARestart.CodeKnown then
  begin
    Result := TDpccCodeInsightStrings.Fmt(TDpccCodeInsightTextId.ServerCrashedCause,
      [TDpccServerExits.Describe(ARestart.Code)]);
  end
  else if ARestart.Crashed then
  begin
    Result := TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.NotificationsServerCrashed);
  end;
  if ARestart.Reopened > 0 then
  begin
    Result := Trim(Result + ' ' + TDpccCodeInsightStrings.Fmt(TDpccCodeInsightTextId.NotificationsServerReopened,
      [ARestart.Reopened]));
  end;
end;

class procedure TDpccServerHandlers.NotifyRestarted(const ARestart: TDpccServerRestart);
var
  mText: string;
  mCase: TDpccCrashCase;
  mSeverity: TDpccNotificationSeverity;
begin
  mText := RestartText(ARestart);
  // Absturzfall des abgestürzten Servers (#1355): Methode, Datei, Zeile und Ausnahme statt nur des Codes. Mit
  // server.crashCases aus schreibt der Server keinen, dann bleibt es beim Code.
  if ARestart.Crashed and (ARestart.PreviousStart > 0) and
    TDpccCrashCases.Newest(TDpccCrashCases.DefaultRoot, ARestart.PreviousStart, mCase) then
  begin
    TDpccNotificationCenter.Default.Notify(TDpccNotificationSources.cServer, TDpccNotificationSeverity.Warning,
      TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.CrashRestartedTitle),
      TDpccCrashCases.SummaryText(mCase) + ' ' + mText,
      CrashActions(mCase, ARestart.CrashIssue));
    Exit;
  end;
  mSeverity := TDpccNotificationSeverity.Info;
  if ARestart.Crashed then
  begin
    mSeverity := TDpccNotificationSeverity.Warning;
  end;
  TDpccNotificationCenter.Default.Notify(TDpccNotificationSources.cServer, mSeverity,
    TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.NotificationsServerRestarted), mText,
    ARestart.LogActions);
end;

class function TDpccServerHandlers.CrashActions(const ACase: TDpccCrashCase;
  const AIssue: TProc<TDpccCrashCase>): TArray<TDpccNotificationAction>;
var
  mFolder: string;
  mCase: TDpccCrashCase;
  mIssue: TProc<TDpccCrashCase>;
begin
  mFolder := ACase.Folder;
  mCase := ACase;
  mIssue := AIssue;
  Result := [TDpccNotificationCenter.Action(
    TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.CrashOpenCase),
    procedure
    begin
      if DirectoryExists(mFolder) then
      begin
        ShellExecute(0, 'open', 'explorer.exe', PChar('"' + mFolder + '"'), nil, SW_SHOWNORMAL);
      end;
    end)];
  if Assigned(mIssue) then
  begin
    Result := Result + [TDpccNotificationCenter.Action(
      TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.CrashCreateIssue),
      procedure
      begin
        mIssue(mCase);
      end)];
  end;
  // Ausblenden: nur den Eintrag schließen, der Fall bleibt im Ordner.
  Result := Result + [TDpccNotificationCenter.Action(
    TDpccCodeInsightStrings.Text(TDpccCodeInsightTextId.CrashHide),
    procedure
    begin
    end)];
end;

class function TDpccServerHandlers.SkipName(const ASkip: TDpccCrashSkip): string;
begin
  Result := ExtractFileName(ASkip.FileName);
  if Result = '' then
  begin
    Result := ASkip.Uri;
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.IDE.CodeInsight.Manager.Handlers', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
