unit dpcc.UI.CodeInsight.Strings;

// Oberflächentexte des Features Code Insight auf Deutsch und Englisch. Die Sprache bestimmt
// `TDpccStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `dpcc.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TDpccCodeInsightTextId = (
    StartSlow, UndoActionServer, MetricsReportNoProject, MetricsReportFailed, MetricsReportRunning,
    MetricsReportBusy, NotificationsBadgeHint, NotificationsServerRestarted, NotificationsServerReopened,
    NotificationsServerCrashed, NotificationsServerError, NotificationsServerMessage, ProblemCounterText,
    ProblemCounterHint, FuseTrippedTitle, FuseTrippedEnable, FuseTrippedOpenLog, ServerCrashedCause,
    ServerHeldTitle, ServerHeldText, ServerHeldPhase, LogBrokenTitle, LogBrokenText, CrashRestartedTitle,
    CrashCaseTitle, CrashCaseText, CrashOpenCase, CrashCreateIssue, CrashHide, CrashSkipTitle, CrashSkipText,
    CrashSkipEnded, CrashRetry, CrashSkipProblem);

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
    ('dpcc: Der Start der IDE dauerte %d ms (Zeitlimit %d ms); dpcc selbst brauchte davon %d ms%s.',
     'Änderung des Servers',
     'Metrikbericht: kein aktives Projekt.',
     'Metrikbericht: Der dpcc-Server hat keinen Bericht geliefert.',
     'Metrikbericht wird erstellt …',
     'Metrikbericht: Der dpcc-Server berechnet gerade Metriken; bitte gleich noch einmal versuchen.',
     '%d ungelesene Benachrichtigungen; ein Klick auf die Zahl öffnet die Liste.',
     'Server neu gestartet',
     '%d offene Dateien erneut an den Server gesendet.',
     'Der Server war beendet und läuft wieder.',
     'Server: Fehler',
     'Meldung des Servers',
     'Fehler %d · Warnungen %d · Hinweise %d',
     '%d Fehler, %d Warnungen, %d Hinweise in dpcc-Probleme. Klick öffnet die Liste.',
     '%s nach Fehlern abgeschaltet',
     'Wieder einschalten',
     'Protokoll öffnen',
     'Der Server war beendet (%s) und läuft wieder.',
     'Server wiederholt abgestürzt',
     'Der Server endete zweimal mit %s innerhalb von %d Minuten. dpcc startet ihn nicht mehr von selbst neu, ' +
     'damit der Fehler nicht in einer Schleife wiederkehrt. Der Fehlerbericht enthält das Protokoll und die ' +
     'Ausgabe des Servers auf stderr.',
     '%s; zweimal, kein automatischer Neustart',
     'dpcc-Protokoll gestört',
     'dpcc kann nicht in %s schreiben: %s. dpcc versucht es bei jeder Zeile weiter und vermerkt die Lücke im ' +
     'Protokoll, sobald es wieder geht.',
     'dpcc-Server neu gestartet',
     'Absturzfall gesichert',
     'Der Server hat die Anfrage abgebrochen: %s',
     'Fall öffnen',
     'Issue anlegen',
     'Ausblenden',
     'Übersprungen nach Absturz',
     '%s an %s wird bis zur nächsten Änderung übersprungen (%d Abstürze, %s).',
     '%s an %s wird wieder beantwortet.',
     'Erneut versuchen',
     'Übersprungen nach Absturz: %s (%d Abstürze, %s); Fall %s'),
    ('dpcc: the IDE start took %d ms (time limit %d ms); dpcc itself took %d ms of it%s.',
     'Change by the server',
     'Metrics report: no active project.',
     'Metrics report: the dpcc server returned no report.',
     'Creating metrics report …',
     'Metrics report: the dpcc server is computing metrics right now; please try again shortly.',
     '%d unread notifications; click the number to open the list.',
     'Server restarted',
     '%d open files sent to the server again.',
     'The server had stopped and is running again.',
     'Server: error',
     'Message from the server',
     'Errors %d · Warnings %d · Hints %d',
     '%d errors, %d warnings, %d hints in dpcc problems. Click opens the list.',
     '%s switched off after errors',
     'Switch on again',
     'Open log',
     'The server had stopped (%s) and is running again.',
     'Server crashed repeatedly',
     'The server ended twice with %s within %d minutes. dpcc no longer restarts it on its own, so the error ' +
     'does not recur in a loop. The bug report contains the log and the server''s output on stderr.',
     '%s; twice, no automatic restart',
     'dpcc log disrupted',
     'dpcc cannot write to %s: %s. dpcc keeps trying with every line and notes the gap in the log once writing ' +
     'works again.',
     'dpcc server restarted',
     'Crash case saved',
     'The server aborted the request: %s',
     'Open case',
     'Create issue',
     'Dismiss',
     'Skipped after crash',
     '%s on %s is skipped until the next change (%d crashes, %s).',
     '%s on %s is answered again.',
     'Retry',
     'Skipped after crash: %s (%d crashes, %s); case %s'));

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
