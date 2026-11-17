unit dpcc.Core.Settings.Plugin.General;

// Einstellungen des IDE-Plugins, Bereich Allgemein (Statusfeld, Diagnose, sicherer Modus) (#227):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. Umfang, Verwendungen und Speichergrenze des Index sind seit S4 fest
// (Server: dpcc.Common.Configuration, Seite „Index“ weg); „Prozesse am Projekt…“ und das Fenster „dpcc-Server“ haben
// seit S4 keinen Schalter mehr. TDpccPluginSettings (dpcc.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  dpcc.Core.Settings.Plugin.Store;

const
  /// <summary>Grenzen für safeMode.startupTimeoutMs und safeMode.keepSettingsHistory (#722).</summary>
  cMinSafeStartupTimeout = 1000;
  cMaxSafeStartupTimeout = 120000;
  cMaxSafeSettingsHistory = 50;
  /// <summary>Grenzen für notifications.maxEntries (#601); wie TDpccNotificationCenter.cMinEntries/MaxMaxEntries
  /// (Test prüft Gleichheit).</summary>
  cMinNotificationEntries = 10;
  cMaxNotificationEntries = 1000;
  /// <summary>Werte von help.source (#1886): GitHub-Doku des installierten Versionstags bzw. lokale HTML-Seiten.
  /// </summary>
  cHelpSourceOnline = 'online';
  cHelpSourceLocal = 'local';

type
  /// <summary>Plugin-Einstellungen: Server, Index, sicherer Modus, Architektur und Hotspots.</summary>
  TDpccPluginGeneralServerSettings = record
    // Seite „Robustheit“ seit S3 weg: Hänger-Schwelle (TDpccHangMonitor.cDefaultThresholdMs = 500) und
    // Zeitlimit der Datenquellen (TDpccTimeLimit.cDefaultMs = 200) sind feste Werte, der Hinweis im
    // Meldungsfenster nach langen Hängern entfällt (nur noch das Log).
    // Pfad und Betriebsart eines eigenen Server-Prozesses gibt es seit S1 nicht mehr: Der Server läuft nur noch im
    // IDE-Prozess; alte Werte in der Registry liest dpcc nicht mehr.
    // Projektdatei .dpcc (teamFile.enabled) und Diagnosemodus (diagnosticMode.*) gibt es seit S8 nicht mehr: Nichts
    // las die Werte außerhalb der Optionsseite.
    /// <summary>Architekturübersicht (#1118, architecture.enabled in settings.json): Fenster „dpcc-Architektur“,
    /// Bericht und get_architecture; Vorgabe an.</summary>
    ArchitectureEnabled: Boolean;
    /// <summary>Code-Abfragen (#1351, query.enabled in settings.json): Fenster „dpcc-Abfrage“, Befehl und
    /// query_code; Vorgabe an.</summary>
    QueryEnabled: Boolean;
    /// <summary>Umfang der Übersicht (architecture.scope): 'project' oder 'projectGroup' (Vorgabe).</summary>
    ArchitectureScope: string;
    /// <summary>Bibliotheks-Units (RTL, VCL, Fremdbibliotheken) mitzählen (architecture.includeLibraryUnits).
    /// </summary>
    ArchitectureIncludeLibraryUnits: Boolean;
    /// <summary>So viele zentrale Units (architecture.centralUnits, 5–100, Vorgabe 15).</summary>
    ArchitectureCentralUnits: Integer;
    /// <summary>Hotspots (#1354, hotspots.enabled in settings.json): Fenster „dpcc-Hotspots“, Bericht
    /// (--hotspots) und get_hotspots; Vorgabe an.</summary>
    HotspotsEnabled: Boolean;
    /// <summary>Ausgewerteter Zeitraum in Monaten (hotspots.months, 1–60, Vorgabe 12).</summary>
    HotspotsMonths: Integer;
    /// <summary>Mindestzahl gemeinsamer Commits der Änderungskopplung (hotspots.coupling.minCommits, 2–1000,
    /// Vorgabe 5).</summary>
    HotspotsCouplingMinCommits: Integer;
    /// <summary>Hauptschalter der experimentellen Funktionen (#834, experimental.enabled, liegt in settings.json):
    /// aus = keine Einstellung mit x-experimental wirkt, auch wenn sie an ist; Vorgabe aus.</summary>
    ExperimentalEnabled: Boolean;
    /// <summary>Abgesicherter Start (#722): nach einem Absturz fragen (safeMode.askAfterCrash).</summary>
    SafeAskAfterCrash: Boolean;
    /// <summary>Nach zwei Abstürzen kurz hintereinander ohne Rückfrage abgesichert
    /// (safeMode.autoAfterRepeatedCrash).</summary>
    SafeAutoAfterRepeatedCrash: Boolean;
    /// <summary>Taste beim Laden für den abgesicherten Start: shift, ctrl, none (safeMode.startupKey).</summary>
    SafeStartupKey: string;
    /// <summary>Langsamer Start ab dieser Zeit bis zur freien Nachrichtenschleife: dpcc nennt seine Startanteile
    /// im Meldungsfenster; kein Absturz, abgesichert startet dpcc deshalb nicht
    /// (safeMode.startupTimeoutMs).</summary>
    SafeStartupTimeoutMs: Integer;
    /// <summary>Gemerkte Einstellungsstände zum Zurücksetzen (safeMode.keepSettingsHistory).</summary>
    SafeKeepSettingsHistory: Integer;
    /// <summary>Fehlerbericht anonymisieren (#108, diagnostics.bugReport.anonymize): Pfade, Benutzername und
    /// Bezeichner ersetzen; Vorgabe an.</summary>
    BugReportAnonymize: Boolean;
    /// <summary>Protokoll dpcc.log mit Klarnamen (#1478, diagnostics.log.names); Vorgabe aus: Namen, Pfade und
    /// Meldungen stehen als name#N, datei#N, text#N.</summary>
    LogNames: Boolean;
    /// <summary>Zusätzliche Quellordner (index.extraSourceFolders in settings.json, L2), durch ";" getrennt; Vorgabe
    /// leer. Der Server liest denselben Wert. Ersetzt den Schalter index.officeAndWinRt (Speicher-Optimierung c1):
    /// Office-Typbibliotheken und WinRT stehen seit L2 immer im Katalog.</summary>
    IndexExtraSourceFolders: string;
    /// <summary>Modul-Schalter analysis.enabled (#1454): Analysefenster (Architektur, Unit-Beziehungen, Symbolpfad,
    /// Hotspots); aus = die wirksamen Werte aller Einstellungen des Moduls sind
    /// „aus“ (TDpccModuleSwitches), gespeichert bleiben sie.</summary>
    AnalysisEnabled: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TDpccPluginGeneralServerSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TDpccSettingsExchange);
  end;

  /// <summary>Plugin-Einstellungen: Oberfläche, Statusfeld, Benachrichtigungen und Einstellungsübertragung.</summary>
  TDpccPluginGeneralSettings = record
    // Das dpcc-Statusfeld (statusField.*) und die Tastenkürzel-Tipps (shortcutTips.*) gibt es seit S8 nicht mehr.
    /// <summary>Zustand: Das Fenster „dpcc-Architektur“ wurde einmal rechts neben die Projektverwaltung
    /// gelegt (ui.architectureWindowPlaced); danach gilt die Lage aus dem Desktop der IDE.</summary>
    ArchitectureWindowPlaced: Boolean;
    /// <summary>Zustand: Das Fenster „Unit-Beziehungen“ (#593) wurde einmal rechts neben die Projektverwaltung
    /// gelegt (ui.unitRelationsWindowPlaced); danach gilt die Lage aus dem Desktop der IDE.</summary>
    UnitRelationsWindowPlaced: Boolean;
    /// <summary>Zustand: Das Fenster „dpcc-Hotspots“ wurde einmal rechts neben die Projektverwaltung gelegt
    /// (ui.hotspotsWindowPlaced); danach gilt die Lage aus dem Desktop der IDE.</summary>
    HotspotsWindowPlaced: Boolean;
    /// <summary>Prüfliste „dpcc-Einrichtung“ beim IDE-Start zeigen, solange nicht alles grün ist (#625,
    /// ui.setupChecklist); aus: nur auf Abruf (Menü dpcc, Befehlspalette, Statusfeld).</summary>
    SetupChecklist: Boolean;
    /// <summary>Die Prüfliste war schon einmal offen (#625); vorher öffnet sie beim Start in jedem Fall. Kein
    /// Schlüssel in dpcc.json, nur Zustand des Plugins.</summary>
    SetupChecklistSeen: Boolean;
    /// <summary>Einmal täglich nach einer neuen Version sehen (#495, updates.check); Vorgabe aus, beim ersten
    /// Start wird gefragt.</summary>
    UpdatesCheck: Boolean;
    /// <summary>Updates installieren (#1519, updates.install): off (nur Hinweis wie #495), ask (Vorgabe: auf Klick
    /// laden und beim Beenden installieren) oder auto (gleich laden, beim Beenden installieren). Wirkt nur mit
    /// UpdatesCheck.</summary>
    UpdatesInstall: string;
    /// <summary>stable (Vorgabe) oder prerelease (auch Vorabversionen, #1519, updates.channel).</summary>
    UpdatesChannel: string;
    /// <summary>Neue Module eines Updates (#1519, updates.newModules): ask (Vorgabe, Auswahl zeigen), install oder
    /// skip.</summary>
    UpdatesNewModules: string;
    /// <summary>Benachrichtigungszentrale (#601, notifications.enabled): Hinweise sammeln, Zähler im
    /// dpcc-Statusfeld, Liste und Befehl dpcc.Notifications; aus = jede Funktion zeigt ihre Einblendung wie
    /// vor #601, nichts wird gesammelt.</summary>
    Notifications: Boolean;
    /// <summary>Verhalten je Quelle (#601, notifications.sources): "quelle=verhalten" mit Komma getrennt,
    /// verhalten show, collect oder off; nicht genannte Quellen zeigen (show).</summary>
    NotificationsSources: string;
    /// <summary>Höchstens so viele Einträge in der Liste (#601, notifications.maxEntries, 10–1000).</summary>
    NotificationsMaxEntries: Integer;
    /// <summary>Einstellungen exportieren, importieren und zurücksetzen (#723, settings.exportImport): Befehle der
    /// Befehlspalette, Knöpfe der Optionsseite und Kontextmenü „Auf Standard zurücksetzen“; aus = alles davon
    /// verschwindet samt Tipps.</summary>
    SettingsExportImport: Boolean;
    /// <summary>Geänderte Werte auf der Optionsseite mit einem Punkt vor der Beschriftung markieren (#723,
    /// settings.markModified).</summary>
    SettingsMarkModified: Boolean;
    /// <summary>Suchfeld über dem Baum der Optionsseite und Suche auf der Übersicht „dpcc“ (#1884,
    /// settings.search).</summary>
    SettingsSearch: Boolean;
    /// <summary>Präfix @ in der Befehlspalette listet Einstellungen (#1884, palette.settingsPrefix).</summary>
    PaletteSettingsPrefix: Boolean;
    /// <summary>Modul Hilfe (#1886, help.enabled): F1 auf Befund, Einstellung und dpcc-Fenster.</summary>
    HelpEnabled: Boolean;
    /// <summary>Quelle der Hilfe (#1886, help.source): cHelpSourceOnline oder cHelpSourceLocal.</summary>
    HelpSource: string;
    /// <summary>Kommandozeilen-Compiler prüfen (#1822, diagnostics.editionCheck): ohne dcc32/dcc64 Hinweis und
    /// Projektaufgaben mit dcc oder MSBuild abgeschaltet.</summary>
    DiagnosticsEditionCheck: Boolean;
    /// <summary>Hinweis „kein Kommandozeilen-Compiler“ wurde gezeigt (#1822, Zustand).</summary>
    EditionNoticeShown: Boolean;
    /// <summary>Vor jedem Import und vor „Alles zurücksetzen“ den aktuellen Stand als Datei sichern (#723,
    /// settings.backupBeforeImport; %APPDATA%\dpcc\Backups).</summary>
    SettingsBackupBeforeImport: Boolean;
    /// <summary>Zugangsdaten beim Export (#723, settings.exportSecrets): "omit" lässt sie aus, "placeholder"
    /// schreibt den Platzhalter.</summary>
    SettingsExportSecrets: string;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TDpccPluginGeneralSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TDpccSettingsExchange);
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  dpcc.Core.Notifications.Sources;

{ TDpccPluginGeneralServerSettings }

class function TDpccPluginGeneralServerSettings.Defaults: TDpccPluginGeneralServerSettings;
begin
  // Wie die Vorgaben im Schema (dpcc.schema.json, architecture).
  Result.ArchitectureEnabled := True;
  Result.QueryEnabled := True;
  Result.ArchitectureScope := 'projectGroup';
  Result.ArchitectureIncludeLibraryUnits := False;
  Result.ArchitectureCentralUnits := 15;
  // Wie die Vorgaben im Schema (dpcc.schema.json, hotspots).
  Result.HotspotsEnabled := True;
  Result.HotspotsMonths := 12;
  Result.HotspotsCouplingMinCommits := 5;
  Result.ExperimentalEnabled := False;
  Result.SafeAskAfterCrash := True;
  Result.SafeAutoAfterRepeatedCrash := True;
  Result.SafeStartupKey := 'shift';
  // Gemessen bis zur freien Nachrichtenschleife, mit Desktop, übrigen Packages und Projekt (#874).
  Result.SafeStartupTimeoutMs := 30000;
  Result.SafeKeepSettingsHistory := 5;
  Result.BugReportAnonymize := True;
  Result.LogNames := False;
  Result.AnalysisEnabled := True;
  // Wie die Vorgabe des Servers (TServerSettings, SetServerDefaults).
  Result.IndexExtraSourceFolders := '';
end;

procedure TDpccPluginGeneralServerSettings.Normalize;
begin
  ArchitectureScope := Choice(ArchitectureScope, ['projectGroup', 'project']);
  ArchitectureCentralUnits := EnsureRange(ArchitectureCentralUnits, 5, 100);
  HotspotsMonths := EnsureRange(HotspotsMonths, 1, 60);
  HotspotsCouplingMinCommits := EnsureRange(HotspotsCouplingMinCommits, 2, 1000);
  SafeStartupTimeoutMs := EnsureRange(SafeStartupTimeoutMs, cMinSafeStartupTimeout, cMaxSafeStartupTimeout);
  SafeKeepSettingsHistory := EnsureRange(SafeKeepSettingsHistory, 0, cMaxSafeSettingsHistory);
  SafeStartupKey := LowerCase(Trim(SafeStartupKey));
  if (SafeStartupKey <> 'shift') and (SafeStartupKey <> 'ctrl') and (SafeStartupKey <> 'none') then
  begin
    SafeStartupKey := 'shift';
  end;
end;

procedure TDpccPluginGeneralServerSettings.Exchange(const AIo: TDpccSettingsExchange);
begin
  AIo.Flag('ArchitectureEnabled', ArchitectureEnabled);
  AIo.Flag('QueryEnabled', QueryEnabled);
  AIo.Text('ArchitectureScope', ArchitectureScope);
  AIo.Flag('ArchitectureIncludeLibraryUnits', ArchitectureIncludeLibraryUnits);
  AIo.Number('ArchitectureCentralUnits', ArchitectureCentralUnits);
  AIo.Flag('HotspotsEnabled', HotspotsEnabled);
  AIo.Number('HotspotsMonths', HotspotsMonths);
  AIo.Number('HotspotsCouplingMinCommits', HotspotsCouplingMinCommits);
  AIo.Flag('ExperimentalEnabled', ExperimentalEnabled);
  AIo.Flag('SafeAskAfterCrash', SafeAskAfterCrash);
  AIo.Flag('SafeAutoAfterRepeatedCrash', SafeAutoAfterRepeatedCrash);
  AIo.Text('SafeStartupKey', SafeStartupKey);
  AIo.Number('SafeStartupTimeoutMs', SafeStartupTimeoutMs);
  AIo.Number('SafeKeepSettingsHistory', SafeKeepSettingsHistory);
  AIo.Flag('BugReportAnonymize', BugReportAnonymize);
  AIo.Flag('LogNames', LogNames);
  AIo.Flag('AnalysisEnabled', AnalysisEnabled);
  AIo.Text('IndexExtraSourceFolders', IndexExtraSourceFolders);
end;

{ TDpccPluginGeneralSettings }

class function TDpccPluginGeneralSettings.Defaults: TDpccPluginGeneralSettings;
begin
  Result.ArchitectureWindowPlaced := False;
  Result.UnitRelationsWindowPlaced := False;
  Result.HotspotsWindowPlaced := False;
  Result.SetupChecklist := True;
  Result.SetupChecklistSeen := False;
  Result.UpdatesCheck := False;
  Result.UpdatesInstall := 'ask';
  Result.UpdatesChannel := 'stable';
  Result.UpdatesNewModules := 'ask';
  Result.Notifications := True;
  Result.NotificationsSources := '';
  Result.NotificationsMaxEntries := 200;
  Result.SettingsExportImport := True;
  Result.SettingsMarkModified := True;
  Result.SettingsSearch := True;
  Result.PaletteSettingsPrefix := True;
  Result.HelpEnabled := True;
  Result.HelpSource := cHelpSourceOnline;
  Result.DiagnosticsEditionCheck := True;
  Result.EditionNoticeShown := False;
  Result.SettingsBackupBeforeImport := True;
  Result.SettingsExportSecrets := 'omit';
end;

procedure TDpccPluginGeneralSettings.Normalize;
begin
  NotificationsSources := TDpccNotificationSources.Normalize(NotificationsSources);
  NotificationsMaxEntries := EnsureRange(NotificationsMaxEntries, cMinNotificationEntries, cMaxNotificationEntries);
  SettingsExportSecrets := Choice(SettingsExportSecrets, ['omit', 'placeholder']);
  UpdatesInstall := Choice(UpdatesInstall, ['ask', 'off', 'auto']);
  UpdatesChannel := Choice(UpdatesChannel, ['stable', 'prerelease']);
  UpdatesNewModules := Choice(UpdatesNewModules, ['ask', 'install', 'skip']);
  HelpSource := Choice(HelpSource, [cHelpSourceOnline, cHelpSourceLocal]);
end;

procedure TDpccPluginGeneralSettings.Exchange(const AIo: TDpccSettingsExchange);
begin
  AIo.Flag('ArchitectureWindowPlaced', ArchitectureWindowPlaced);
  AIo.Flag('UnitRelationsWindowPlaced', UnitRelationsWindowPlaced);
  AIo.Flag('HotspotsWindowPlaced', HotspotsWindowPlaced);
  AIo.Flag('SetupChecklist', SetupChecklist);
  AIo.Flag('SetupChecklistSeen', SetupChecklistSeen);
  AIo.Flag('UpdatesCheck', UpdatesCheck);
  AIo.Text('UpdatesInstall', UpdatesInstall);
  AIo.Text('UpdatesChannel', UpdatesChannel);
  AIo.Text('UpdatesNewModules', UpdatesNewModules);
  AIo.Flag('Notifications', Notifications);
  AIo.Text('NotificationsSources', NotificationsSources);
  AIo.Number('NotificationsMaxEntries', NotificationsMaxEntries);
  AIo.Flag('SettingsExportImport', SettingsExportImport);
  AIo.Flag('SettingsMarkModified', SettingsMarkModified);
  AIo.Flag('SettingsSearch', SettingsSearch);
  AIo.Flag('PaletteSettingsPrefix', PaletteSettingsPrefix);
  AIo.Flag('HelpEnabled', HelpEnabled);
  AIo.Text('HelpSource', HelpSource);
  AIo.Flag('DiagnosticsEditionCheck', DiagnosticsEditionCheck);
  AIo.Flag('EditionNoticeShown', EditionNoticeShown);
  AIo.Flag('SettingsBackupBeforeImport', SettingsBackupBeforeImport);
  AIo.Text('SettingsExportSecrets', SettingsExportSecrets);
end;

end.
