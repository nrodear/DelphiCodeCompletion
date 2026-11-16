unit dpcc.UI.CodeInsight.Strings;

// Oberflächentexte des Features Code Insight auf Deutsch und Englisch. Die Sprache bestimmt
// `TDpccStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `dpcc.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TDpccCodeInsightTextId = (
    NotificationsServerRestarted, NotificationsServerReopened, NotificationsServerCrashed, NotificationsServerError,
    NotificationsServerMessage, ServerCrashedCause, ServerHeldTitle, ServerHeldText, ServerHeldPhase,
    CrashRestartedTitle, CrashCaseTitle, CrashCaseText, CrashOpenCase, CrashCreateIssue, CrashHide, CrashSkipTitle,
    CrashSkipText, CrashSkipEnded, CrashRetry);

  TDpccCodeInsightStrings = class
  public
    class function Text(AId: TDpccCodeInsightTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TDpccCodeInsightTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  dpcc.UI.Strings;

const
  cTexts: array[TDpccLanguage, TDpccCodeInsightTextId] of string = (
    ('Server neu gestartet',
     '%d offene Dateien erneut an den Server gesendet.',
     'Der Server war beendet und läuft wieder.',
     'Server: Fehler',
     'Meldung des Servers',
     'Der Server war beendet (%s) und läuft wieder.',
     'Server wiederholt abgestürzt',
     'Der Server endete zweimal mit %s innerhalb von %d Minuten. dpcc startet ihn nicht mehr von selbst neu, ' +
     'damit der Fehler nicht in einer Schleife wiederkehrt. Der Fehlerbericht enthält das Protokoll und die ' +
     'Ausgabe des Servers auf stderr.',
     '%s; zweimal, kein automatischer Neustart',
     'dpcc-Server neu gestartet',
     'Absturzfall gesichert',
     'Der Server hat die Anfrage abgebrochen: %s',
     'Fall öffnen',
     'Issue anlegen',
     'Ausblenden',
     'Übersprungen nach Absturz',
     '%s an %s wird bis zur nächsten Änderung übersprungen (%d Abstürze, %s).',
     '%s an %s wird wieder beantwortet.',
     'Erneut versuchen'),
    ('Server restarted',
     '%d open files sent to the server again.',
     'The server had stopped and is running again.',
     'Server: error',
     'Message from the server',
     'The server had stopped (%s) and is running again.',
     'Server crashed repeatedly',
     'The server ended twice with %s within %d minutes. dpcc no longer restarts it on its own, so the error ' +
     'does not recur in a loop. The bug report contains the log and the server''s output on stderr.',
     '%s; twice, no automatic restart',
     'dpcc server restarted',
     'Crash case saved',
     'The server aborted the request: %s',
     'Open case',
     'Create issue',
     'Dismiss',
     'Skipped after crash',
     '%s on %s is skipped until the next change (%d crashes, %s).',
     '%s on %s is answered again.',
     'Retry'));

{ TDpccCodeInsightStrings }

class function TDpccCodeInsightStrings.Text(AId: TDpccCodeInsightTextId): string;
begin
  Result := cTexts[TDpccStrings.Language, AId];
end;

class function TDpccCodeInsightStrings.Fmt(AId: TDpccCodeInsightTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
