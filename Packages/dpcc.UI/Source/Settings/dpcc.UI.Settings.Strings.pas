unit dpcc.UI.Settings.Strings;

// Oberflächentexte des Features Einstellungen auf Deutsch und Englisch. Die Sprache bestimmt
// `TDpccStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `dpcc.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.
// Seit OPT1 nur noch die Texte der einen Seite „dpcc“: Hauptschalter, vier Abschnitte, dreizehn Optionen (seit LOOK1
// mit „Darstellung der Popups“), zwei Knöpfe
// und die Meldungen von „Index neu aufbauen“; seit IDECHECK der Abschnitt „IDE“ mit „Jetzt prüfen“, seit LOG1 dort
// „Ablauf protokollieren (Log)“ samt Hint und den Zeilen im Meldungsfenster. Texte der Reiter, des Baums, der Suche, des Filters, der
// Geändert-Markierung, der experimentellen Funktionen, der Favoritenliste und der fest verdrahteten Optionen sind
// entfallen.

interface

{$SCOPEDENUMS ON}

type
  TDpccSettingsTextId = (
    // Hauptschalter und Überschriften der Abschnitte.
    SettingsEnabled, SettingsSectionCompletion, SettingsSectionCommit, SettingsSectionHints, SettingsSectionIndex,
    // Vervollständigung.
    SettingsAutoMinChars, SettingsListMode, SettingsListModeFilter, SettingsListModeAll, SettingsListModeRest,
    SettingsRows, SettingsAutoWidth, SettingsLearning, SettingsResetHistory,
    // Beim Übernehmen.
    SettingsParentheses, SettingsCommitChars, SettingsAutoUses,
    // Parameter-Hint und Tooltip; seit LOOK1 die Darstellung der Popups (in der Reihenfolge von TDpccLookLevel).
    SettingsParameterHints, SettingsHover, SettingsDebugHoverValues, SettingsPopupLook, SettingsPopupLookIntense,
    SettingsPopupLookSubtle, SettingsPopupLookPlain,
    // Index: zusätzliche Quellordner (L2) und „Index neu aufbauen“ (S4).
    SettingsIndexExtraSourceFolders, SettingsIndexRebuild, SettingsIndexRebuildConfirm, SettingsIndexRebuildLater,
    SettingsIndexCacheFailed, SettingsIndexCacheCleared,
    // IDE: Betriebsart und Schalter der IDE (IDECHECK).
    SettingsSectionIde, SettingsCheckIde,
    // „Index neu aufbauen“ läuft im Hintergrund (Knopf grau); von der Sitzung abgelehnt (Knopf frei).
    SettingsIndexRebuildRunning, SettingsIndexRebuildRejected,
    // Abschnitt IDE: „Ablauf protokollieren (Log)“ (LOG1), Hint am Schalter mit der Datei, Zeilen im Meldungsfenster
    // beim Ein- und Ausschalten.
    SettingsDiagnose, SettingsDiagnoseHint, SettingsDiagnoseFile, SettingsDiagnoseOn, SettingsDiagnoseOff,
    // Betriebsart statt Hauptschalter (Stufe 2 von dpcc.LspServer.exe): je Art Beschriftung und erklärender Satz, in
    // der Reihenfolge von TDpccOperatingMode; Hinweis, wenn dpcc.LspServer.exe fehlt, und Hint mit ihrem Ort.
    SettingsModeOff, SettingsModePlugin, SettingsModeServer, SettingsModeOffInfo, SettingsModePluginInfo,
    SettingsModeServerInfo, SettingsModeServerMissing, SettingsModeServerFile);

  TDpccSettingsStrings = class
  public
    class function Text(AId: TDpccSettingsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TDpccSettingsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  dpcc.UI.Strings;

const
  cTexts: array[TDpccLanguage, TDpccSettingsTextId] of string = (
    ('Betriebsart',
     'Vervollständigung',
     'Beim Übernehmen',
     'Parameter-Hint und Tooltip',
     'Index',
     'Beim Tippen öffnen ab Zeichen (0 = nie):',
     'Beim Tippen zeigen:',
     'Nur Treffer',
     'Alle Einträge, Treffer oben',
     'Treffer, darunter gedämpft der Rest',
     'Sichtbare Zeilen der Liste:',
     'Breite automatisch',
     'Häufig und zuletzt gewählte Einträge nach oben',
     'Verlauf zurücksetzen',
     'Klammern bei Methoden ergänzen',
     'Übernehmen mit „(“, „;“ und „.“',
     'Unit automatisch in uses eintragen',
     'Parameter-Hint bei „(“ und „,“',
     'Eigener Tooltip beim Verweilen über Bezeichnern',
     'Werte beim Debuggen zeigen (schaltet den Wert-Tooltip der IDE ab)',
     'Darstellung der Popups:',
     'Intensiv',
     'Dezent',
     'Unscheinbar',
     'Zusätzliche Quellordner (mit „;“ getrennt, samt Unterordnern):',
     'Index neu aufbauen',
     'Alle Index-Caches löschen und den Index neu aufbauen? Der erste Aufbau kann einige Minuten dauern.',
     '%d Index-Caches gelöscht; der Index wird beim nächsten Start der Code Completion neu aufgebaut.',
     'Index-Cache konnte nicht gelöscht werden: %s',
     '%d Index-Caches gelöscht; der Index wird neu aufgebaut.',
     'IDE',
     'Jetzt prüfen',
     'Index wird neu aufgebaut: Sitzung wird angehalten, Caches werden gelöscht …',
     'Index neu aufbauen ist gerade nicht möglich (läuft noch oder dpcc wird beendet).',
     'Ablauf protokollieren (Log)',
     'Schreibt jeden Schritt von Strg+Klick, Vervollständigung, Hover und Parameterhilfe ins Diagnoseprotokoll ' +
     'neben dem Plugin, ohne Quelltext außer dem Wort an der Stelle. Wirkt nach OK ohne Neustart.',
     'Protokolldatei: %s',
     'dpcc: Der Ablauf wird protokolliert in %s. Ausschalten: Tools › Optionen › Drittanbieter › dpcc, „Ablauf ' +
     'protokollieren (Log)“.',
     'dpcc: Ablaufprotokoll aus.',
     'Aus – Delphi arbeitet ohne dpcc',
     'Plugin – Code Insight von dpcc im Editor (Vorgabe)',
     'Server – dpcc.LspServer.exe an Stelle von DelphiLSP',
     'Delphi nutzt seinen eigenen Code-Insight-Anbieter (DelphiLSP); dpcc zeigt keine Fenster und leitet nichts um.',
     'dpcc wird der Code-Insight-Anbieter der IDE, mit eigener Liste, Tooltip und Parameter-Hint. Der Wechsel von ' +
     'oder zu Plugin wirkt nach dem Neustart von Delphi.',
     'Delphi bleibt im LSP-Betrieb und zeigt seine eigenen Fenster; die Antworten liefert dpcc.LspServer.exe statt ' +
     'DelphiLSP.exe. Die Fehlermarkierung der IDE (Error Insight) bleibt leer. dpcc schaltet in den ' +
     'Code-Insight-Optionen der IDE Programmierhilfe, Automatisch aufrufen, Code-Parameter und Symbol-Insight ein ' +
     'und stellt sie beim Verlassen von Server zurück; dort muss man für den Server nichts abschalten. Der Wechsel ' +
     'von oder zu Plugin wirkt nach dem Neustart von Delphi, zwischen Aus und Server beim nächsten Öffnen einer ' +
     'Projektgruppe; die vier Optionen liest die IDE aber erst beim nächsten Start von Delphi.',
     'Nicht wählbar: dpcc.LspServer.exe ist nicht installiert (im Setup die Komponente „LSP-Server“ wählen).',
     'Programm: %s'),
    ('Mode',
     'Completion',
     'When accepting',
     'Parameter hint and tooltip',
     'Index',
     'Open on typing from characters (0 = never):',
     'While typing, show:',
     'Only matches',
     'All entries, matches on top',
     'Matches, then the rest dimmed',
     'Visible rows of the list:',
     'Automatic width',
     'Frequently and recently chosen entries first',
     'Reset history',
     'Add parentheses to methods',
     'Accept with “(”, “;” and “.”',
     'Add the unit to uses automatically',
     'Parameter hint on “(” and “,”',
     'Own tooltip when hovering identifiers',
     'Show values while debugging (turns off the IDE''s value tooltip)',
     'Popup appearance:',
     'Intense',
     'Subtle',
     'Plain',
     'Additional source folders (separated by “;”, including subfolders):',
     'Rebuild index',
     'Delete all index caches and rebuild the index? The first build can take a few minutes.',
     '%d index caches deleted; the index is rebuilt the next time code completion starts.',
     'Index cache could not be deleted: %s',
     '%d index caches deleted; the index is being rebuilt.',
     'IDE',
     'Check now',
     'Rebuilding index: stopping the session, deleting caches …',
     'Cannot rebuild the index right now (still running or dpcc is shutting down).',
     'Log the flow (log file)',
     'Writes every step of Ctrl+click, completion, hover and parameter hints to the diagnostic log next to the ' +
     'plugin, without source code except the word at the position. Takes effect after OK without a restart.',
     'Log file: %s',
     'dpcc: The flow is logged to %s. To turn it off: Tools › Options › Third Party › dpcc, “Log the flow (log ' +
     'file)”.',
     'dpcc: Flow log off.',
     'Off – Delphi works without dpcc',
     'Plugin – Code Insight by dpcc in the editor (default)',
     'Server – dpcc.LspServer.exe instead of DelphiLSP',
     'Delphi uses its own Code Insight provider (DelphiLSP); dpcc shows no windows and redirects nothing.',
     'dpcc becomes the IDE''s Code Insight provider, with its own list, tooltip and parameter hint. Switching to or ' +
     'from Plugin takes effect after restarting Delphi.',
     'Delphi stays in LSP mode and shows its own windows; the answers come from dpcc.LspServer.exe instead of ' +
     'DelphiLSP.exe. The IDE''s error marks (Error Insight) stay empty. dpcc turns on code completion, auto ' +
     'invoke, code parameters and symbol insight in the IDE''s Code Insight options and restores them when leaving ' +
     'Server; nothing needs to be turned off there for the server. Switching to or from Plugin takes effect after ' +
     'restarting Delphi, between Off and Server the next time a project group is opened; the IDE reads the four ' +
     'options only at the next start of Delphi, though.',
     'Not available: dpcc.LspServer.exe is not installed (select the component “LSP server” in the setup).',
     'Program: %s'));

{ TDpccSettingsStrings }

class function TDpccSettingsStrings.Text(AId: TDpccSettingsTextId): string;
begin
  Result := cTexts[TDpccStrings.Language, AId];
end;

class function TDpccSettingsStrings.Fmt(AId: TDpccSettingsTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
