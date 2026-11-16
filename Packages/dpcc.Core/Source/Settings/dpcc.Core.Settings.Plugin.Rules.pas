unit dpcc.Core.Settings.Plugin.Rules;

// Einstellungen des IDE-Plugins, Bereich Prüfregeln (problems.*) (#227):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TDpccPluginSettings (dpcc.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  dpcc.Core.Settings.Plugin.Store;

type
  /// <summary>Plugin-Einstellungen: Prüfregeln und Problemliste.</summary>
  TDpccPluginRulesSettings = record
    /// <summary>Fenster „dpcc-Prüfung“ (#909): verfügbar (aus = kein Menüeintrag, kein Fenster); nur mit Problems.
    /// </summary>
    ProblemsWindow: Boolean;
    /// <summary>Bereich des Fensters: 'file', 'project', 'group' (Vorgabe).</summary>
    ProblemsWindowScope: string;
    /// <summary>Einzelne Projekte der Gruppe in der Bereichsliste des Fensters (#1843).</summary>
    ProblemsWindowScopeProjects: Boolean;
    /// <summary>Gewähltes Einzelprojekt (Name ohne Endung) bei Bereich 'project' (#1843); '' = aktives Projekt.
    /// </summary>
    ProblemsWindowScopeProject: string;
    /// <summary>Gruppierung: 'none', 'file' (Vorgabe), 'rule', 'category'.</summary>
    ProblemsWindowGroupBy: string;
    /// <summary>Spalten mit Reihenfolge, Breite und Sichtbarkeit ("kind:70,-rule,…", TDpccFindings.ParseColumns); '' =
    /// alle in der Vorgabe-Reihenfolge.</summary>
    ProblemsWindowColumns: string;
    /// <summary>Compilermeldungen (dcc) im Fenster mit anzeigen.</summary>
    ProblemsWindowCompiler: Boolean;
    /// <summary>Eintrag zur Cursorzeile im Fenster markieren.</summary>
    ProblemsWindowFollowCursor: Boolean;
    /// <summary>Offene Units zuerst (#1108): aktive Unit oben angepinnt, geöffnete darunter, nicht geöffnete danach;
    /// Hauptschalter von ProblemsWindowClosedUnits und ProblemsWindowShowCleanActive.</summary>
    ProblemsWindowOpenFirst: Boolean;
    /// <summary>Nicht geöffnete Units: 'dimmed' (Vorgabe, ausgegraut), 'normal' (nur einsortiert), 'hidden'.</summary>
    ProblemsWindowClosedUnits: string;
    /// <summary>Aktive Unit auch ohne Befunde oben zeigen („Keine Befunde“ bzw. „wird geprüft …“).</summary>
    ProblemsWindowShowCleanActive: Boolean;
    /// <summary>Bestätigt der Build einen dpcc-Befund (gleiche Zeile, gleicher Code, #1024): 'merge' (Vorgabe)
    /// zeigt nur den dpcc-Befund mit Marke „dpcc + dcc“, 'both' beide Meldungen.</summary>
    ProblemsCompilerMerge: string;
    /// <summary>Compilercode (E2035 …) in Meldung, Spalte „Compiler“ und Hover zeigen (#1024).</summary>
    ProblemsShowCompilerCode: Boolean;
    /// <summary>Fehler der IDE (Error Insight) nach jeder Prüfung abfragen und im Fenster „dpcc-Prüfung“ neben die
    /// dpcc-Befunde stellen (#1819, problems.ideErrors); Vorgabe aus.</summary>
    ProblemsIdeErrors: Boolean;
    /// <summary>Wann die offene Datei geprüft wird (problems.update): 'live' (beim Tippen, Vorgabe), 'save' (beim
    /// Speichern), 'manual' (nur auf Anforderung). Ersetzt ProblemsLive (#909).</summary>
    ProblemsUpdate: string;
    /// <summary>Verzögerung der Live-Prüfung nach der letzten Änderung in ms (problems.liveDelayMs, 100 bis
    /// 10000).</summary>
    ProblemsLiveDelayMs: Integer;
    /// <summary>„Alle sicheren Treffer korrigieren …“ im Fenster dpcc-Prüfung (#1352, fix.bulk).</summary>
    FixBulk: Boolean;
    /// <summary>Probleme zusätzlich im Meldungsfenster auflisten (Gruppe „dpcc-Probleme“); nur mit Problems. Seit
    /// Fenster „dpcc-Prüfung“ (#909) Vorgabe aus. Registry-Name ProblemsMessageList: Der frühere Name ProblemsList
    /// trug bei fast allen Installationen die alte Vorgabe „an“, weil Save alle Werte schreibt; er gilt bewusst nicht
    /// mehr (kein x-renamedFrom).
    /// </summary>
    ProblemsMessageList: Boolean;
    /// <summary>Modul-Schalter ruleChecks.enabled (#1454): Prüfregeln; aus = die wirksamen Werte aller Einstellungen
    /// des Moduls sind
    /// „aus“ (TDpccModuleSwitches), gespeichert bleiben sie.</summary>
    RuleChecksEnabled: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TDpccPluginRulesSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TDpccSettingsExchange);
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Settings.ProblemsUpdate;

{ TDpccPluginRulesSettings }

class function TDpccPluginRulesSettings.Defaults: TDpccPluginRulesSettings;
begin
  Result.ProblemsWindow := True;
  Result.ProblemsWindowScope := 'group';
  Result.ProblemsWindowScopeProjects := True;
  Result.ProblemsWindowScopeProject := '';
  Result.ProblemsWindowGroupBy := 'file';
  Result.ProblemsWindowColumns := '';
  Result.ProblemsWindowCompiler := False;
  Result.ProblemsWindowFollowCursor := True;
  Result.ProblemsWindowOpenFirst := True;
  Result.ProblemsWindowClosedUnits := 'dimmed';
  Result.ProblemsWindowShowCleanActive := True;
  Result.ProblemsCompilerMerge := 'merge';
  Result.ProblemsShowCompilerCode := True;
  Result.ProblemsIdeErrors := False;
  Result.ProblemsUpdate := TDpccProblemsUpdateSetting.Name(TDpccProblemsUpdate.Live);
  Result.ProblemsLiveDelayMs := TDpccProblemsUpdateSetting.cDefaultDelayMs;
  Result.FixBulk := True;
  Result.ProblemsMessageList := False;
  Result.RuleChecksEnabled := True;
end;

procedure TDpccPluginRulesSettings.Normalize;
begin
  ProblemsWindowScope := Choice(ProblemsWindowScope, ['group', 'file', 'project']);
  ProblemsWindowScopeProject := Trim(ProblemsWindowScopeProject);
  ProblemsWindowGroupBy := Choice(ProblemsWindowGroupBy, ['file', 'none', 'rule', 'category']);
  ProblemsWindowClosedUnits := Choice(ProblemsWindowClosedUnits, ['dimmed', 'normal', 'hidden']);
  ProblemsCompilerMerge := Choice(ProblemsCompilerMerge, ['merge', 'both']);
  ProblemsUpdate := TDpccProblemsUpdateSetting.Normalize(ProblemsUpdate);
  ProblemsLiveDelayMs := TDpccProblemsUpdateSetting.ClampDelay(ProblemsLiveDelayMs);
end;

procedure TDpccPluginRulesSettings.Exchange(const AIo: TDpccSettingsExchange);
begin
  AIo.Flag('ProblemsWindow', ProblemsWindow);
  AIo.Text('ProblemsWindowScope', ProblemsWindowScope);
  AIo.Flag('ProblemsWindowScopeProjects', ProblemsWindowScopeProjects);
  AIo.Text('ProblemsWindowScopeProject', ProblemsWindowScopeProject);
  AIo.Text('ProblemsWindowGroupBy', ProblemsWindowGroupBy);
  AIo.Text('ProblemsWindowColumns', ProblemsWindowColumns);
  AIo.Flag('ProblemsWindowCompiler', ProblemsWindowCompiler);
  AIo.Flag('ProblemsWindowFollowCursor', ProblemsWindowFollowCursor);
  AIo.Flag('ProblemsWindowOpenFirst', ProblemsWindowOpenFirst);
  AIo.Text('ProblemsWindowClosedUnits', ProblemsWindowClosedUnits);
  AIo.Flag('ProblemsWindowShowCleanActive', ProblemsWindowShowCleanActive);
  AIo.Text('ProblemsCompilerMerge', ProblemsCompilerMerge);
  AIo.Flag('ProblemsShowCompilerCode', ProblemsShowCompilerCode);
  AIo.Flag('ProblemsIdeErrors', ProblemsIdeErrors);
  // Vor problems.update: problems.live (#909) übernehmen, an = live, aus = beim Speichern.
  if not AIo.Writing and (AIo.Store.ReadString('ProblemsUpdate', '') = '') then
  begin
    ProblemsUpdate := TDpccProblemsUpdateSetting.FromLive(AIo.Store.ReadInteger('ProblemsLive', 1) <> 0);
  end
  else
  begin
    AIo.Text('ProblemsUpdate', ProblemsUpdate);
  end;
  AIo.Number('ProblemsLiveDelayMs', ProblemsLiveDelayMs);
  AIo.Flag('FixBulk', FixBulk);
  AIo.Flag('ProblemsMessageList', ProblemsMessageList);
  AIo.Flag('RuleChecksEnabled', RuleChecksEnabled);
end;

end.
