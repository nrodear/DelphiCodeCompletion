unit dpcc.UI.Settings.Strings;

// Oberflächentexte des Features Einstellungen auf Deutsch und Englisch. Die Sprache bestimmt
// `TDpccStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `dpcc.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TDpccSettingsTextId = (
    SettingsTitle, SettingsEnabled, SettingsRows, SettingsParentheses, SettingsFixCase, SettingsLearning,
    SettingsGroupInherited, SettingsPreview, SettingsHover, SettingsResetHistory, SettingsResetWidths,
    SettingsXmlDocExpand, SettingsXmlDocCollapsed, SettingsXmlDocLast, SettingsXmlDocExpanded,
    SettingsXmlDocMaxLines, SettingsIndexRebuild, SettingsIndexRebuildConfirm, SettingsCommitChars, SettingsAutoUses,
    SettingsParameterHints, SettingsOpenDelay, SettingsAutoWidth,
    // „Index neu aufbauen“ auf der Seite „Allgemein“ (S4, vorher „Index-Cache löschen“ #184 auf der Seite „Index“).
    SettingsIndexRebuildLater, SettingsIndexCacheFailed, SettingsIndexCacheCleared, SettingsFavorites,
    SettingsFavoritesRemove, SettingsFavoritesRemoveAll, SettingsFavoritesNone, SettingsResetKey, SettingsResetPageMenu,
    SettingsModifiedHint, SettingsExperimentalEnabled, SettingsExperimentalTag, SettingsExperimentalOff,
    SettingsExperimentalAllow, SettingsFilter, SettingsFilterAll, SettingsFilterModified, SettingsFilterExperimental,
    SettingsListMode, SettingsListModeFilter, SettingsListModeAll, SettingsListModeRest, SettingsListScope,
    SettingsListScopeMembers, SettingsListScopeEverywhere, SettingsLockedExperimental, SettingsLockedMaster,
    SettingsOverviewTitle, SettingsOverviewDetails, SettingsCompletionVariantBranch, SettingsFormatPlaceholders,
    SettingsDpccNoHits, SettingsSearchPrompt, SettingsSearchOtherNode, SettingsSearchHint,
    // Werte im Hover beim Debuggen (#891, seit S3b auf der Seite „Hints“).
    SettingsDebugHoverValues,
    // L2: zusätzliche Quellordner (index.extraSourceFolders) auf der Seite „Allgemein“; ersetzt den Schalter
    // index.officeAndWinRt (Speicher-Optimierung c1).
    SettingsIndexExtraSourceFolders,
    // L5: Tippen öffnet die Liste erst ab so vielen Zeichen (completion.autoMinChars).
    SettingsAutoMinChars);

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
    ('Vervollständigung, Parameter-Hint und Tooltip von dpcc',
     'Code Insight von dpcc (aus: eingebaute Code Insight der IDE)',
     'Sichtbare Zeilen der Liste:',
     'Klammern beim Übernehmen von Methoden ergänzen',
     'Schreibweise beim Übernehmen korrigieren (showmessage → ShowMessage)',
     'Häufig und zuletzt gewählte Einträge nach oben',
     'Geerbte Member nachrangig und nach Klasse gruppiert',
     'Vorschau des gewählten Eintrags im Editor',
     'Eigener Tooltip beim Verweilen über Bezeichnern',
     'Verlauf zurücksetzen',
     'Breiten zurücksetzen',
     'XMLDoc beim Öffnen',
     'immer zugeklappt',
     'wie zuletzt',
     'immer aufgeklappt',
     'XMLDoc: höchstens Zeilen ohne Scrollen (0 = Bildschirm)',
     'Index neu aufbauen',
     'Alle Index-Caches löschen und den Index neu aufbauen? Der erste Aufbau kann einige Minuten dauern.',
     'Übernehmen mit „(“, „;“ und „.“ (Commit-Zeichen)',
     'Unit beim Übernehmen automatisch in uses eintragen',
     'Parameter-Hint bei „(“ und „,“',
     'Verzögerung bis zum Öffnen (ms):',
     'Breite der Liste automatisch',
     '%d Index-Caches gelöscht; der Index wird beim nächsten Start der Code Completion neu aufgebaut.',
     'Index-Cache konnte nicht gelöscht werden: %s',
     '%d Index-Caches gelöscht; der Index wird neu aufgebaut.',
     'Favoriten anheften (Strg+D)',
     'Entfernen',
     'Alle entfernen',
     'Keine Favoriten angeheftet.',
     'Auf Standard zurücksetzen',
     'Ganze Seite auf Standard zurücksetzen',
     'Vom Standard geändert; Rechtsklick setzt zurück.',
     'Experimentelle Funktionen erlauben (experimental.enabled)',
     'Experimentell',
     '⚠ Experimentelle Funktionen sind aus. Ihre Schalter wirken erst mit „Experimentelle Funktionen erlauben“.',
     'Erlauben',
     'Filter:',
     'Alle',
     'Geändert',
     'Nur experimentelle',
     'Beim Tippen zeigen:',
     'Nur Treffer',
     'Alle Einträge, Treffer oben',
     'Treffer, darunter gedämpft der Rest',
     'Gilt für:',
     'Mitgliederlisten nach „.“',
     'Alle Listen',
     'gesperrt: Experimentelle Funktionen sind aus',
     'gesperrt: „%s“ (%s) ist aus',
     'Funktionen in diesem Bereich',
     'Details',
     'Zweig varianter Record-Felder zeigen',
     'Platzhalter von Format im Parameter-Hint zuordnen und einfärben',
     'Keine Einstellung gefunden.',
     'Einstellung suchen …',
     'in %s',
     'Enter springt zum ersten Treffer, Pfeil runter in die Liste.',
     'Werte im Hover beim Debuggen (schaltet dafür den Wert-Tooltip der IDE ab)',
     'Zusätzliche Quellordner (mit „;“ getrennt, samt Unterordnern; z. B. DUnitX-Quellen):',
     'Beim Tippen öffnen ab Zeichen (0 = nie):'),
    ('Completion, parameter hint and tooltip by dpcc',
     'Code Insight by dpcc (off: built-in Code Insight of the IDE)',
     'Visible rows of the list:',
     'Add parentheses when accepting methods',
     'Fix the case when accepting (showmessage → ShowMessage)',
     'Frequently and recently chosen entries first',
     'Inherited members ranked lower and grouped by class',
     'Preview of the selected entry in the editor',
     'Own tooltip when hovering identifiers',
     'Reset history',
     'Reset widths',
     'XMLDoc when opened',
     'always collapsed',
     'as last time',
     'always expanded',
     'XMLDoc: max. lines before scrolling (0 = screen)',
     'Rebuild index',
     'Delete all index caches and rebuild the index? The first build can take a few minutes.',
     // german-ok: Kennung im Protokoll
     'Accept with "(", ";" and "." (commit characters)',
     'Add the unit to uses automatically when accepting',
     'Parameter hint on "(" and ","',
     'Delay before opening (ms):',
     'Automatic list width',
     '%d index caches deleted; the index is rebuilt the next time code completion starts.',
     'Index cache could not be deleted: %s',
     '%d index caches deleted; the index is being rebuilt.',
     'Pin favorites (Ctrl+D)',
     'Remove',
     'Remove all',
     'No pinned favorites.',
     'Reset to default',
     'Reset the whole page to default',
     'Changed from the default; right-click to reset.',
     'Allow experimental features (experimental.enabled)',
     'Experimental',
     '⚠ Experimental features are off. Their switches only work with “Allow experimental features”.',
     'Allow',
     'Filter:',
     'All',
     'Changed',
     'Experimental only',
     'While typing, show:',
     'Only matches',
     'All entries, matches on top',
     'Matches, then the rest dimmed',
     'Applies to:',
     'Member lists after “.”',
     'All lists',
     'locked: experimental features are off',
     'locked: “%s” (%s) is off',
     'Features in this area',
     'Details',
     'Show the branch of variant record fields',
     'Match and colour Format placeholders in the parameter hint',
     'No setting found.',
     'Search settings …',
     'in %s',
     'Enter jumps to the first hit, arrow down moves into the list.',
     'Values in the hover while debugging (turns off the IDE''s value tooltip)',
     'Additional source folders (separated by “;”, including subfolders; e.g. DUnitX sources):',
     'Open on typing from characters (0 = never):'));

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
