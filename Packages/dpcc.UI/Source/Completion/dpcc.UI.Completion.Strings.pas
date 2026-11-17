unit dpcc.UI.Completion.Strings;

// Oberflächentexte des Features Vervollständigung auf Deutsch und Englisch. Die Sprache bestimmt
// `TDpccStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `dpcc.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TDpccCompletionTextId = (
    FooterKeys, CountOf, NoMatchesFor, BackspaceWidens, NoSuggestions, EscCloses, InheritedFrom, InheritedPlain,
    TagRecent, TagFrequent, FitsType, OtherGroup, CountFits, AccessCompletion, AccessPosition, DidYouMean,
    SetFooterKeys, SetChosen, SetHeader, SetHeaderPlain, UnknownHeader, BatchHeader, AssignHeader, FormHeader,
    SenderHeader, DataSourceFooter, GuardFooterKeys, PlaceholderFooter, CompletionLimited, ExceptionGroupTry,
    ExceptionGroupGeneral, SyntaxLimited, SyntaxUnknown, SyntaxLine, TargetFooter, FavoritePinned, FavoriteUnpinned,
    FavoritesFull, FavoriteNotAllowed, AccessFavorite, CompletionRestHeader, CountHitsRest, UsesGroupProject,
    UsesGroupRtl, UsesGroupLibrary, UsesInInterface, UsesInImplementation, UsesCycleTag, InheritedSameTag,
    InheritedOverloadTag, SameNameActiveTag, SameNameHiddenFooter, TagVariantBranch, IdeListAgain);

  TDpccCompletionStrings = class
  public
    class function Text(AId: TDpccCompletionTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TDpccCompletionTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  dpcc.UI.Strings;

const
  cTexts: array[TDpccLanguage, TDpccCompletionTextId] of string = (
    ('Enter übernehmen · Esc schließen',
     '%d von %d',
     'Keine Treffer für „%s“',
     'Rücktaste erweitert die Suche',
     'Keine Vorschläge an dieser Stelle',
     'Esc schließt',
     'Geerbt von %s',
     'Geerbt',
     'zuletzt',
     'häufig',
     'Passt zu %s',
     'Weitere',
     '%d passend · %d gesamt',
     'dpcc Vervollständigung',
     '%d von %d',
     'Meintest du',
     'Leertaste wählen · Enter einfügen · Esc verwerfen',
     '%d gewählt',
     '%s · Menge von %s',
     'Menge von %s',
     '„%s“ ist unbekannt',
     'Fehlende Methoden von %s',
     'Alle Felder zuweisen · %s',
     'Formular %s',
     'Sender ist %s · %s',
     'Quelle: %s',
     'Enter anwenden · weitertippen verwirft',
     'Platzhalter %d / %d · Tab weiter · Esc fertig',
     'eingeschränkt (Index wird aufgebaut)',
     'Aus dem try-Block',
     'Allgemein',
     'Ergebnisse möglicherweise unvollständig · Syntaxfehler in ',
     'Kontext unklar · Syntaxfehler in ',
     'Zeile %d',
     'Ziel: %s',
     '%s angeheftet · Strg+D löst',
     '%s gelöst',
     'Schon %d Favoriten bei %s – erst einen lösen',
     'Dieser Eintrag lässt sich nicht anheften',
     'angeheftet',
     'Weitere Einträge',
     '%d Treffer · %d weitere',
     'Projekt',
     'RTL/VCL',
     'Drittanbieter',
     'bereits im interface-Teil',
     'bereits im implementation-Teil',
     'Zirkelbezug',
     'gleiche Parameter',
     'Überladung',
     'aktiv',
     '%s ausgeblendet',
     'Zweig %s',
     'Strg+Leertaste erneut für die Liste der IDE'),
    ('Enter to accept · Esc to close',
     '%d of %d',
     'No matches for “%s”',
     'Backspace widens the search',
     'No suggestions here',
     'Esc closes',
     'Inherited from %s',
     'Inherited',
     'recent',
     'frequent',
     'Matches %s',
     'Other',
     '%d matching · %d total',
     'dpcc completion',
     '%d of %d',
     'Did you mean',
     'Space selects · Enter inserts · Esc discards',
     '%d selected',
     '%s · set of %s',
     'Set of %s',
     '"%s" is unknown',
     'Missing methods of %s',
     'Assign all fields · %s',
     'Form %s',
     'Sender is %s · %s',
     'Source: %s',
     'Enter applies · keep typing to discard',
     'Placeholder %d / %d · Tab next · Esc done',
     'limited (index is being built)',
     'From the try block',
     'General',
     'Results may be incomplete · syntax error in ',
     'Context unclear · syntax error in ',
     'line %d',
     'Target: %s',
     '%s pinned · Ctrl+D unpins',
     '%s unpinned',
     'Already %d favorites for %s – unpin one first',
     'This entry cannot be pinned',
     'pinned',
     'More entries',
     '%d matches · %d more',
     'Project',
     'RTL/VCL',
     'Third party',
     'already in the interface section',
     'already in the implementation section',
     'Circular reference',
     'same parameters',
     'overload',
     'active',
     '%s hidden',
     'branch %s',
     'Press Ctrl+Space again for the IDE list'));

{ TDpccCompletionStrings }

class function TDpccCompletionStrings.Text(AId: TDpccCompletionTextId): string;
begin
  Result := cTexts[TDpccStrings.Language, AId];
end;

class function TDpccCompletionStrings.Fmt(AId: TDpccCompletionTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
