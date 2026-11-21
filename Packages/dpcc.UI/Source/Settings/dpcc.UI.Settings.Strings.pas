unit dpcc.UI.Settings.Strings;

// Oberflächentexte des Features Einstellungen auf Deutsch und Englisch. Die Sprache bestimmt
// `TDpccStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `dpcc.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.
// Seit OPT1 nur noch die Texte der einen Seite „dpcc“: Hauptschalter, vier Abschnitte, dreizehn Optionen (seit LOOK1
// mit „Darstellung der Popups“), zwei Knöpfe
// und die Meldungen von „Index neu aufbauen“; seit IDECHECK der Abschnitt „IDE“ mit „Jetzt prüfen“. Texte der Reiter, des Baums, der Suche, des Filters, der
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
    SettingsIndexRebuildRunning, SettingsIndexRebuildRejected);

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
    ('Code Insight von dpcc (stellt den Code-Insight-Anbieter der IDE auf dpcc um; aus = DelphiLSP)',
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
     'Index neu aufbauen ist gerade nicht möglich (läuft noch oder dpcc wird beendet).'),
    ('Code Insight by dpcc (switches the IDE''s Code Insight provider to dpcc; off = DelphiLSP)',
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
     'Cannot rebuild the index right now (still running or dpcc is shutting down).'));

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
