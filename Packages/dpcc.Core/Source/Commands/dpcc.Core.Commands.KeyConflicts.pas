unit dpcc.Core.Commands.KeyConflicts;

// Verträglichkeit mit anderen Erweiterungen (#494), Teil ohne Open Tools API:
// - Tastenkürzel von dpcc gegen bekannte Belegungen prüfen (Aktionen der IDE
//   und anderer Erweiterungen, Editor-Belegungen der Standard-Tastaturbelegung).
//   Bei Konflikt belegt dpcc die Taste nur mit ausdrücklichem Vorrang; sonst
//   bleibt die fremde Belegung aktiv.
// - Erweiterungen mit eigener Vervollständigung an ihren Packages erkennen;
//   dpcc weist nur darauf hin und schaltet fremde Erweiterungen nie ab.
// - Seite „Tastenkonflikte“: je dpcc-Taste (Befehlspalette, Syntaxprüfung,
//   Vervollständigung, Parameter-Hint, Schnellschalter #604, Diagnosemodus #479) Taste, fremde Belegung und die Wahl
//   „dpcc verwenden“, „anderer Belegung überlassen“ oder „andere Taste für
//   dpcc“ (TDpccKeyEntry).
// - Alle dpcc-Tasten für die Tastenkürzel-Übersicht (#520) und die Einrichtung
//   (#625): AllFromSettings ergänzt die Seite „Tastenkonflikte“ um die Tasten
//   der Editorbefehle (#399), des Änderungsprotokolls (#721), des Suchfelds
//   der Willkommensseite (#760), des Wechsels Deklaration ⇄ Implementierung
//   (#775), des Wechsels Unit ⇄ Testunit (#189), des Fensters „Units
//   suchen“ (#777, eigene Taste und Übernahme von Strg+F12) und von
//   „Lesezeichen setzen…“ (#622, Strg+Alt+K) und des Erzeugen-Menüs (#719,
//   Alt+Einfg) und von „Element ausblenden …“ (#628, Strg+.) und von Zeilen
//   verschieben und duplizieren (#634, Alt+↑/↓, Umschalt+Alt+↑/↓) und der Mehrfachmarken (#589, Strg+D,
//   Strg+K Strg+D, Alt+Umschalt+I, Strg+Alt+↑/↓) und der schnellen
//   Lesezeichen (#1104: Strg+Umschalt+K, Strg+Umschalt+1…9, Strg+1…9 auch auf
//   der Seite „Tastenkonflikte“, dazu nächstes/voriges Lesezeichen). Ist eine Funktion
//   abgeschaltet, steht ihr Eintrag mit Disabled in der Liste: dpcc belegt die
//   Taste dann nicht, also ist sie auch kein Konflikt.
// Kürzel sind TShortCut-Werte (Word) wie in Vcl.Menus.

interface

uses
  System.SysUtils,
  dpcc.Core.Settings.Plugin;

type
  {$SCOPEDENUMS ON}
  /// <summary>Die ersten sechs stehen auf der Seite „Tastenkonflikte“ (FromSettings); die übrigen nur in der
  /// Übersicht (#520, AllFromSettings): Editorbefehle mit gemeinsamem Vorrang EditorKeysPriority, das Suchfeld
  /// der Willkommensseite, Deklaration ⇄ Implementierung mit zwei Tasten (#775), Unit ⇄ Testunit (#189), die
  /// eigene Taste für „Units suchen“, die Übernahme von Strg+F12 durch „Units suchen“ (#777) und „Lesezeichen
  /// setzen…“ (#622), das Erzeugen-Menü (#719), die Benachrichtigungen (#601) und die Schnellaktionen der
  /// Willkommensseite „Öffnen und bauen“ und „Tests“ (#764), „Element ausblenden …“ (#628), nächster und voriger
  /// Befund (#509), „Schnell öffnen“ (#503), Zurück, Vor und letzte Bearbeitungsstelle (#504) sowie Definition und
  /// Referenzen einblenden (#505), das Fenster „dpcc-Prüfung“ (#909) und die Abschnittssprünge zum interface- und
  /// implementation-Teil (#1101). Schnelle Lesezeichen (#1104): QuickBookmark (Strg+Umschalt+K), QuickBookmarkSet
  /// und QuickBookmarkJump (je eine Zeile für die Tasten 1–9, Key ist die Taste für 1) stehen mit eigener Wahl auch
  /// auf der Seite „Tastenkonflikte“; NextBookmark und PreviousBookmark nur in der Übersicht. Gezielt
  /// hineinspringen (#836) nur in der Übersicht. „Datei jetzt prüfen“ (#1744). Neue Funktionen
  /// nur hinten anhängen: Die Ordnungszahl steckt in Kennungen der Übersicht. Sicher löschen (#716). Neue Zeile am Ende
  /// des Abschnitts (#1768).</summary>
  TDpccKeyFunction = (Palette, Check, Completion, Signature, QuickToggle, DiagnosticMode, CodeActions,
    ExpandSelection, ShrinkSelection, GoToImplementation, TypeDefinition, UndoChange, RedoChange, WelcomeSearch,
    MethodToggleUp, MethodToggleDown, TestUnit, UnitSearch, UnitSearchIde, Bookmark, GenerateMenu,
    Notifications, WelcomeQuickBuild, WelcomeQuickTests, HideElement, NextProblem, PreviousProblem, QuickOpen,
    NavBack, NavForward, LastEdit, PeekDefinition, PeekReferences, Breadcrumbs, JumpToMatch,
    JumpToMatchSelect, NextChange, PreviousChange, MoveLinesUp, MoveLinesDown, DuplicateLinesUp,
    DuplicateLinesDown, CompleteStatement, MultiCursorNext, MultiCursorSkip, MultiCursorLineEnds,
    MultiCursorAbove, MultiCursorBelow, Search, SearchNext, SearchPrevious,
    SearchMethod, FormatCode, ToggleBlockComment, NewLineBelow, NewLineAbove, Unwrap, ProblemsWindow,
    SectionInterface, SectionImplementation, QuickBookmark, QuickBookmarkSet, QuickBookmarkJump, NextBookmark,
    PreviousBookmark, SearchReplace, StepIntoTarget, ExpressionType, SafeDelete, CreateIssue,
    DesignerSearch, CheckFile, SectionAppend, DesignerSelectionSetsSave, DesignerShowComponent,
    DesignerInlineCaption, DesignerSelectionBar, DesignerMagnifier, DesignerUsages);
  TDpccKeyChoice = (UseDpcc, LeaveOther, OtherKey);
  /// <summary>NoKey: keine Taste; IdeKey: Taste der IDE über Code Insight, dpcc belegt nichts selbst;
  /// Free: dpcc belegt die freie Taste; DpccWins: belegt, dpcc hat Vorrang; Left: belegt, dpcc
  /// überlässt sie der anderen Belegung.</summary>
  TDpccKeyStatus = (NoKey, IdeKey, Free, DpccWins, Left);
  {$SCOPEDENUMS OFF}

  /// <summary>Eine Taste von dpcc auf der Seite „Tastenkonflikte“ (#494).</summary>
  TDpccKeyEntry = record
    Func: TDpccKeyFunction;
    /// <summary>0 = keine Taste; bei Vervollständigung und Parameter-Hint die Taste der IDE.</summary>
    Key: Word;
    Priority: Boolean;
    /// <summary>Funktion abgeschaltet (etwa Deklaration ⇄ Implementierung aus, „Units suchen“ aus): dpcc belegt
    /// die Taste nicht, sie ist kein Konflikt (Status NoKey). Key behält den eingestellten Wert.</summary>
    Disabled: Boolean;
    class function Create(AFunc: TDpccKeyFunction; AKey: Word; APriority: Boolean): TDpccKeyEntry; overload; static;
    class function Create(AFunc: TDpccKeyFunction; AKey: Word; APriority, AEnabled: Boolean): TDpccKeyEntry;
      overload; static;
    /// <summary>Alle dpcc-Tasten aus den Einstellungen, in fester Reihenfolge.</summary>
    class function FromSettings(const ASettings: TDpccPluginSettings): TArray<TDpccKeyEntry>; static;
    /// <summary>Jede Taste von dpcc (#520): FromSettings, dann die Editorbefehle (Vorrang aus
    /// EditorKeysPriority), das Suchfeld der Willkommensseite (immer mit Vorrang: es nimmt die Taste nur dort,
    /// solange die Seite aktiv ist), Deklaration ⇄ Implementierung (#775), Unit ⇄ Testunit (#189), „Units
    /// suchen“ (#777, eigene Taste und Strg+F12) und „Lesezeichen setzen…“ (#622). Abgeschaltete Funktionen kommen
    /// mit Disabled.</summary>
    class function AllFromSettings(const ASettings: TDpccPluginSettings): TArray<TDpccKeyEntry>; static;
    /// <summary>Zweiter Teil von AllFromSettings ab dem Navigationsverlauf; AShared ist der gemeinsame Vorrang
    /// der Editorbefehle.</summary>
    class function MoreFromSettings(const ASettings: TDpccPluginSettings;
      AShared: Boolean): TArray<TDpccKeyEntry>; static;
    /// <summary>Tasten und Vorrang zurück in die Einstellungen; Disabled und die feste Taste Strg+F12 nicht (dafür
    /// gibt es eigene Schalter).</summary>
    class procedure ToSettings(const AEntries: TArray<TDpccKeyEntry>; var ASettings: TDpccPluginSettings); static;
    /// <summary>Taste der IDE, über die Code Insight dpcc aufruft (Strg+Leer, Strg+Umschalt+Leer); sonst 0.</summary>
    function IdeKey: Word;
    function Choice: TDpccKeyChoice;
    /// <summary>Wahl übernehmen: dpcc verwenden = Vorrang; sonst ohne Vorrang. dpcc verwenden ohne eigene
    /// Taste bei Vervollständigung und Parameter-Hint: dpcc belegt die Taste der IDE selbst.</summary>
    procedure Choose(AChoice: TDpccKeyChoice);
    /// <summary>Zustand bei fremder Belegung AOwner ('' = frei); abgeschaltet NoKey.</summary>
    function Status(const AOwner: string): TDpccKeyStatus;
  end;

  TDpccKeyOwner = record
    ShortCut: Word;
    Owner: string;
    class function Create(AShortCut: Word; const AOwner: string): TDpccKeyOwner; static;
  end;

  TDpccKeyConflicts = class
  public const
    cScShift = $2000;
    cScCtrl = $4000;
    cScAlt = $8000;
    cPaletteDefault = cScCtrl or cScShift or Ord('P');
    cCheckDefault = cScCtrl or cScAlt or $78; // VK_F9
    cIdeCompletionKey = cScCtrl or $20; // Strg+Leer
    cIdeSignatureKey = cScCtrl or cScShift or $20; // Strg+Umschalt+Leer
    cQuickToggleDefault = cScCtrl or cScShift or cScAlt or Ord('A');
    /// <summary>Diagnosemodus (#479): Strg+Alt+Umschalt+A gehört schon den Schnellschaltern (#604).</summary>
    cDiagnosticModeDefault = cScCtrl or cScShift or cScAlt or Ord('D');
    /// <summary>Strg+F12 der IDE-Aktion „Units“; „Units suchen“ übernimmt sie (#777, unitSearch.replaceIdeDialog).
    /// </summary>
    cIdeUnitsKey = cScCtrl or $7B; // VK_F12
  public
    /// <summary>Editor-Belegungen der Standard-Tastaturbelegung, die keine Aktionen sind.</summary>
    class function KnownIdeKeys: TArray<TDpccKeyOwner>; static;
    /// <summary>Wer belegt AShortCut schon? '' wenn frei.</summary>
    class function OwnerOf(AShortCut: Word; const AKeys: TArray<TDpccKeyOwner>): string; static;
    /// <summary>Soll dpcc die Taste belegen? Nur frei oder mit Vorrang; 0 heißt „keine Taste“.</summary>
    class function ShouldBind(AShortCut: Word; const AOwner: string; APriority: Boolean): Boolean; static;
    /// <summary>Namen von Erweiterungen mit eigener Vervollständigung unter den geladenen Modulen.</summary>
    class function CompletionExtensions(const AModules: TArray<string>): TArray<string>; static;
  end;

implementation


uses
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TKeyConflictsText = (IDEPlayKeyboardMacro, IDERecordKeyboardMacro, IDECodeBrowsingFindDeclaration,
    IDESelectColumnBlockUp, IDESelectColumnBlockDown, IDEFindReferences, IDEAddToDoItem, IDEFoldingCtrlShiftK,
    IDEToggleBookmark, IDEGoToBookmark);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TKeyConflictsText] of string = (
    ('IDE: Tastaturmakro abspielen',
     'IDE: Tastaturmakro aufzeichnen',
     'IDE: Code-Browsing (Deklaration suchen)',
     'IDE: Spaltenblock nach oben markieren',
     'IDE: Spaltenblock nach unten markieren',
     'IDE: Referenzen suchen',
     'IDE: To-Do-Eintrag hinzufügen',
     'IDE: Faltung (Strg+Umschalt+K, dann U, E, A, T, O …)',
     'IDE: Lesezeichen %d umschalten',
     'IDE: Zu Lesezeichen %d springen'),
    ('IDE: Play keyboard macro',
     'IDE: Record keyboard macro',
     'IDE: Code browsing (find declaration)',
     'IDE: Select column block up',
     'IDE: Select column block down',
     'IDE: Find references',
     'IDE: Add To-Do item',
     'IDE: Folding (Ctrl+Shift+K, then U, E, A, T, O …)',
     'IDE: Toggle bookmark %d',
     'IDE: Go to bookmark %d'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TKeyConflictsText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;
{ TDpccKeyEntry }

class function TDpccKeyEntry.Create(AFunc: TDpccKeyFunction; AKey: Word; APriority: Boolean): TDpccKeyEntry;
begin
  Result := Create(AFunc, AKey, APriority, True);
end;

class function TDpccKeyEntry.Create(AFunc: TDpccKeyFunction; AKey: Word; APriority,
  AEnabled: Boolean): TDpccKeyEntry;
begin
  Result.Func := AFunc;
  Result.Key := AKey;
  Result.Priority := APriority;
  Result.Disabled := not AEnabled;
end;

class function TDpccKeyEntry.FromSettings(const ASettings: TDpccPluginSettings): TArray<TDpccKeyEntry>;
begin
  Result := [Create(TDpccKeyFunction.Palette, Word(ASettings.PaletteKey), ASettings.PaletteKeyPriority),
    Create(TDpccKeyFunction.Check, Word(ASettings.CheckKey), ASettings.CheckKeyPriority),
    Create(TDpccKeyFunction.Completion, Word(ASettings.CompletionKey), ASettings.CompletionKeyPriority),
    Create(TDpccKeyFunction.Signature, Word(ASettings.SignatureKey), ASettings.SignatureKeyPriority),
    Create(TDpccKeyFunction.QuickToggle, Word(ASettings.QuickToggleKey), ASettings.QuickToggleKeyPriority),
    Create(TDpccKeyFunction.DiagnosticMode, Word(ASettings.DiagnosticModeKey), ASettings.DiagnosticModeKeyPriority),
    // Schnelle Lesezeichen (#1104): Die Tasten gehören in der IDE den Lesezeichen bzw. der Faltung; dpcc nimmt sie
    // mit Vorrang, „anderer Belegung überlassen“ gibt sie zurück. Wartezeit 0 = Strg+Umschalt+K bleibt bei der IDE.
    Create(TDpccKeyFunction.QuickBookmark, Word(ASettings.QuickBookmarkKey), ASettings.QuickBookmarkKeyPriority,
      ASettings.QuickBookmarks and (ASettings.QuickBookmarkChordWait > 0)),
    Create(TDpccKeyFunction.QuickBookmarkSet, Word(ASettings.QuickBookmarkSetKey),
      ASettings.QuickBookmarkSetKeyPriority, ASettings.QuickBookmarks and ASettings.QuickBookmarksNumberedKeys),
    Create(TDpccKeyFunction.QuickBookmarkJump, Word(ASettings.QuickBookmarkJumpKey),
      ASettings.QuickBookmarkJumpKeyPriority, ASettings.QuickBookmarks and ASettings.QuickBookmarksNumberedKeys)];
end;

class function TDpccKeyEntry.AllFromSettings(const ASettings: TDpccPluginSettings): TArray<TDpccKeyEntry>;
var
  mShared, mSecondToggle: Boolean;
begin
  mShared := ASettings.EditorKeysPriority;
  // Beide Tasten des Wechsels gleich: dpcc belegt die Taste nur einmal (AddAttemptKey), also auch nur ein Eintrag.
  mSecondToggle := ASettings.MethodToggle and (ASettings.MethodToggleDownKey <> ASettings.MethodToggleUpKey);
  Result := FromSettings(ASettings) + [Create(TDpccKeyFunction.CodeActions, Word(ASettings.ActionsKey), mShared),
    Create(TDpccKeyFunction.ExpandSelection, Word(ASettings.ExpandKey), mShared),
    Create(TDpccKeyFunction.ShrinkSelection, Word(ASettings.ShrinkKey), mShared),
    Create(TDpccKeyFunction.GoToImplementation, Word(ASettings.ImplementationKey), mShared),
    Create(TDpccKeyFunction.TypeDefinition, Word(ASettings.TypeDefinitionKey), mShared),
    Create(TDpccKeyFunction.UndoChange, Word(ASettings.UndoKey), mShared),
    Create(TDpccKeyFunction.RedoChange, Word(ASettings.RedoKey), mShared),
    Create(TDpccKeyFunction.WelcomeSearch, Word(ASettings.WelcomePageSearchKey), True,
      ASettings.WelcomePage and ASettings.WelcomePageSearch),
    // Deklaration ⇄ Implementierung (#775): aus = die Klassennavigation der IDE behält die Tasten.
    Create(TDpccKeyFunction.MethodToggleUp, Word(ASettings.MethodToggleUpKey), mShared, ASettings.MethodToggle),
    Create(TDpccKeyFunction.MethodToggleDown, Word(ASettings.MethodToggleDownKey), mShared, mSecondToggle),
    Create(TDpccKeyFunction.TestUnit, Word(ASettings.TestUnitKey), mShared),
    // Units suchen (#777): eigene Taste als Editorbefehl; Strg+F12 bleibt die Aktion der IDE, dpcc hängt sich nur
    // an ihre Ausführung (bewusst übernommen, daher mit Vorrang).
    Create(TDpccKeyFunction.UnitSearch, Word(ASettings.UnitSearchKey), mShared, ASettings.UnitSearchEnabled),
    Create(TDpccKeyFunction.UnitSearchIde, TDpccKeyConflicts.cIdeUnitsKey, True,
      ASettings.UnitSearchEnabled and ASettings.UnitSearchReplaceIdeDialog),
    // Benannte Lesezeichen (#622): aus = dpcc belegt Strg+Alt+K nicht.
    Create(TDpccKeyFunction.Bookmark, Word(ASettings.BookmarkKey), mShared, ASettings.BookmarksNamed),
    // Erzeugen-Menü (#719): aus = Alt+Einfg bleibt frei.
    Create(TDpccKeyFunction.GenerateMenu, Word(ASettings.GenerateMenuKey), mShared, ASettings.GenerateMenu),
    // Benachrichtigungszentrale (#601): aus = Strg+Umschalt+Alt+N bleibt frei.
    Create(TDpccKeyFunction.Notifications, Word(ASettings.NotificationsKey), mShared, ASettings.Notifications),
    // Schnellaktionen der Willkommensseite (#764): nur in der Zeile von „Projekte“ bzw. „Weiterarbeiten“ mit dem
    // Fokus, dort immer mit Vorrang (wie das Suchfeld); aus = Strg+B und Strg+T bleiben dort der IDE.
    Create(TDpccKeyFunction.WelcomeQuickBuild, Word(ASettings.WelcomePageQuickActionsBuildKey), True,
      ASettings.WelcomePage and ASettings.WelcomePageQuickActions),
    Create(TDpccKeyFunction.WelcomeQuickTests, Word(ASettings.WelcomePageQuickActionsTestKey), True,
      ASettings.WelcomePage and ASettings.WelcomePageQuickActions),
    // Ausblenden am Element (#628): nimmt die Taste nur auf einer Zeile mit dpcc-Element, sonst geht sie an die
    // IDE weiter (Strg+. = IDE Insight); darum immer mit Vorrang, ohne fremde Belegung abzuschalten.
    Create(TDpccKeyFunction.HideElement, Word(ASettings.HideElementKey), True),
    // Nächster/vorheriger Befund (#509): nur mit Problemen im Editor.
    Create(TDpccKeyFunction.NextProblem, Word(ASettings.NextProblemKey), mShared, ASettings.Problems),
    Create(TDpccKeyFunction.PreviousProblem, Word(ASettings.PreviousProblemKey), mShared, ASettings.Problems),
    // Schnell öffnen (#503): aus = Strg+P bleibt der IDE.
    Create(TDpccKeyFunction.QuickOpen, Word(ASettings.QuickOpenKey), mShared, ASettings.QuickOpen)];
  Result := Result + MoreFromSettings(ASettings, mShared);
end;

/// <summary>Letzter Teil von AllFromSettings: Designer, Prüfung und Abschnitt; AShared wie dort.</summary>
function DesignerKeys(const ASettings: TDpccPluginSettings; AShared: Boolean): TArray<TDpccKeyEntry>;
begin
  Result := [
    // Komponenten suchen (#1442): nur solange ein Designer gezeigt wird, dort mit Vorrang (wie das Suchfeld der
    // Willkommensseite).
    TDpccKeyEntry.Create(TDpccKeyFunction.DesignerSearch, Word(ASettings.DesignerSearchKey), True,
      ASettings.EditorDesignerBar),
    // Datei jetzt prüfen (#1744): in jedem Modus von problems.update; ohne Prüfregeln ist das Kürzel frei.
    TDpccKeyEntry.Create(TDpccKeyFunction.CheckFile, Word(ASettings.CheckFileKey), AShared, ASettings.Problems),
    // Neue Zeile am Ende des Abschnitts (#1768): frei belegbar, ohne Vorgabe.
    TDpccKeyEntry.Create(TDpccKeyFunction.SectionAppend, Word(ASettings.SectionAppendKey), AShared,
      ASettings.Breadcrumbs and ASettings.BreadcrumbsSectionAppend),
    // Auswahl speichern (#739): nur solange der Formular-Designer den Fokus hat, dort mit Vorrang (wie DesignerSearch).
    TDpccKeyEntry.Create(TDpccKeyFunction.DesignerSelectionSetsSave, Word(ASettings.DesignerSelectionSetsSaveKey),
      True, ASettings.EditorDesignerBar and ASettings.DesignerSelectionSets),
    // Im Designer zeigen (#511): Editorbefehl; Umschalt+F12 ist in der IDE „Formulare anzeigen“.
    TDpccKeyEntry.Create(TDpccKeyFunction.DesignerShowComponent, Word(ASettings.DesignerShowInDesignerKey), AShared,
      ASettings.DesignerShowInDesigner),
    // Text im Designer bearbeiten (#748): nur solange der Formular-Designer den Fokus hat, dort mit Vorrang.
    TDpccKeyEntry.Create(TDpccKeyFunction.DesignerInlineCaption, Word(ASettings.DesignerInlineCaptionKey), True,
      ASettings.EditorDesignerBar and ASettings.DesignerInlineCaption),
    // Auswahlleiste und Lupe im Designer: nur solange der Formular-Designer den Fokus hat, dort mit Vorrang.
    TDpccKeyEntry.Create(TDpccKeyFunction.DesignerSelectionBar, Word(ASettings.DesignerSelectionBarKey), True,
      ASettings.EditorDesignerBar and ASettings.DesignerSelectionBar),
    TDpccKeyEntry.Create(TDpccKeyFunction.DesignerMagnifier, Word(ASettings.DesignerMagnifierKey), True,
      ASettings.EditorDesignerBar and ASettings.DesignerMagnifier),
    // Verwendungen im Code (#750): nur solange der Formular-Designer den Fokus hat, dort mit Vorrang.
    TDpccKeyEntry.Create(TDpccKeyFunction.DesignerUsages, Word(ASettings.DesignerUsagesKey), True,
      ASettings.EditorDesignerBar and ASettings.DesignerUsages)];
end;

class function TDpccKeyEntry.MoreFromSettings(const ASettings: TDpccPluginSettings;
  AShared: Boolean): TArray<TDpccKeyEntry>;
begin
  Result := [
    // Navigationsverlauf (#504): Alt+Links/Rechts sind in der IDE „Zurück/Vor“ ihrer eigenen Navigation; der dpcc-
    // Verlauf führt deren Sprünge mit, darum mit Vorrang. Aus = die IDE behält die Tasten.
    Create(TDpccKeyFunction.NavBack, Word(ASettings.NavBackKey), True, ASettings.NavHistory),
    Create(TDpccKeyFunction.NavForward, Word(ASettings.NavForwardKey), True, ASettings.NavHistory),
    Create(TDpccKeyFunction.LastEdit, Word(ASettings.LastEditKey), AShared, ASettings.NavHistory),
    // Definition und Referenzen einblenden (#505).
    Create(TDpccKeyFunction.PeekDefinition, Word(ASettings.PeekDefinitionKey), AShared, ASettings.Peek),
    Create(TDpccKeyFunction.PeekReferences, Word(ASettings.PeekReferencesKey), AShared, ASettings.Peek),
    // Brotkrumenleiste (#590).
    Create(TDpccKeyFunction.Breadcrumbs, Word(ASettings.BreadcrumbsKey), AShared, ASettings.Breadcrumbs),
    // Sprung zum Gegenstück (#635).
    Create(TDpccKeyFunction.JumpToMatch, Word(ASettings.JumpToMatchKey), AShared, ASettings.JumpToMatch),
    Create(TDpccKeyFunction.JumpToMatchSelect, Word(ASettings.JumpToMatchSelectKey), AShared, ASettings.JumpToMatch),
    // Nächste/vorherige Änderung (#507).
    Create(TDpccKeyFunction.NextChange, Word(ASettings.NextChangeKey), AShared, ASettings.GitGutter),
    Create(TDpccKeyFunction.PreviousChange, Word(ASettings.PreviousChangeKey), AShared, ASettings.GitGutter),
    // Zeilen verschieben und duplizieren (#634): Alt+↑ ist in der IDE Code-Browsing, Umschalt+Alt+↑/↓ markiert
    // Spaltenblöcke; bewusst übernommen, darum mit Vorrang. Aus = die IDE behält die Tasten.
    Create(TDpccKeyFunction.MoveLinesUp, Word(ASettings.MoveLinesUpKey), True, ASettings.MoveLines),
    Create(TDpccKeyFunction.MoveLinesDown, Word(ASettings.MoveLinesDownKey), True, ASettings.MoveLines),
    Create(TDpccKeyFunction.DuplicateLinesUp, Word(ASettings.DuplicateLinesUpKey), True, ASettings.MoveLines),
    Create(TDpccKeyFunction.DuplicateLinesDown, Word(ASettings.DuplicateLinesDownKey), True, ASettings.MoveLines),
    // Anweisung vervollständigen (#697): Strg+Umschalt+Enter sucht in der IDE Referenzen; bewusst übernommen.
    Create(TDpccKeyFunction.CompleteStatement, Word(ASettings.CompleteStatementKey), True,
      ASettings.CompleteStatement),
    // Mehrfachmarken (#589, experimentell): bewusst eingeschaltet, darum mit Vorrang (Strg+D formatiert in der IDE
    // den Quelltext; ohne Wort am Cursor geht die Taste dorthin weiter). Überspringen wirkt nur nach Strg+K,
    // solange mehrere Marken aktiv sind. Aus = die IDE behält die Tasten.
    Create(TDpccKeyFunction.MultiCursorNext, Word(ASettings.MultiCursorNextKey), True, ASettings.MultiCursor),
    Create(TDpccKeyFunction.MultiCursorSkip, Word(ASettings.MultiCursorSkipKey), True, ASettings.MultiCursor),
    Create(TDpccKeyFunction.MultiCursorLineEnds, Word(ASettings.MultiCursorLineEndsKey), True,
      ASettings.MultiCursor),
    Create(TDpccKeyFunction.MultiCursorAbove, Word(ASettings.MultiCursorAboveKey), True, ASettings.MultiCursor),
    Create(TDpccKeyFunction.MultiCursorBelow, Word(ASettings.MultiCursorBelowKey), True, ASettings.MultiCursor),
    // dpcc-Suche (#878): Strg+F, F3 und Umschalt+F3 bewusst übernommen (Vorrang), nur mit search.replaceIdeSearch;
    // aus = die IDE behält ihre Suche. „In Methode suchen“ (#877) ist ein eigener Editorbefehl.
    Create(TDpccKeyFunction.Search, Word(ASettings.SearchKey), True, ASettings.SearchReplaceIde),
    Create(TDpccKeyFunction.SearchNext, Word(ASettings.SearchNextKey), True, ASettings.SearchReplaceIde),
    Create(TDpccKeyFunction.SearchPrevious, Word(ASettings.SearchPreviousKey), True, ASettings.SearchReplaceIde),
    Create(TDpccKeyFunction.SearchMethod, Word(ASettings.SearchMethodKey), AShared),
    // Suchen und ersetzen (#893): Strg+H wie Strg+F bewusst übernommen; mit search.replace aus gehört sie der IDE.
    Create(TDpccKeyFunction.SearchReplace, Word(ASettings.SearchReplaceKey), True,
      ASettings.SearchReplaceIde and ASettings.SearchReplace),
    // Formatieren (#43): aus = keine Taste.
    Create(TDpccKeyFunction.FormatCode, Word(ASettings.FormatCodeKey), AShared, ASettings.FormatCode),
    // Blockkommentar umschalten (#703): aus = Kürzel frei.
    Create(TDpccKeyFunction.ToggleBlockComment, Word(ASettings.ToggleBlockCommentKey), AShared,
      ASettings.ToggleBlockComment),
    // Neue Zeile ober- oder unterhalb (#700): aus = Tasten frei.
    Create(TDpccKeyFunction.NewLineBelow, Word(ASettings.NewLineBelowKey), AShared, ASettings.NewLineAround),
    Create(TDpccKeyFunction.NewLineAbove, Word(ASettings.NewLineAboveKey), AShared, ASettings.NewLineAround),
    // Umschließung entfernen (#657): aus = Kürzel frei.
    Create(TDpccKeyFunction.Unwrap, Word(ASettings.UnwrapKey), AShared, ASettings.Unwrap),
    // Fenster „dpcc-Prüfung“ (#909): aus = Kürzel frei.
    Create(TDpccKeyFunction.ProblemsWindow, Word(ASettings.ProblemsWindowKey), AShared,
      ASettings.Problems and ASettings.ProblemsWindow),
    // Abschnittssprünge (#1101): wirken auch ohne Editorleiste; ohne Taste nichts belegt.
    Create(TDpccKeyFunction.SectionInterface, Word(ASettings.GotoInterfaceKey), AShared),
    Create(TDpccKeyFunction.SectionImplementation, Word(ASettings.GotoImplementationKey), AShared),
    // Nächstes/voriges Lesezeichen (#1104): Vorgabe ohne Taste.
    Create(TDpccKeyFunction.NextBookmark, Word(ASettings.NextBookmarkKey), AShared, ASettings.QuickBookmarks),
    Create(TDpccKeyFunction.PreviousBookmark, Word(ASettings.PreviousBookmarkKey), AShared, ASettings.QuickBookmarks),
    // Gezielt hineinspringen (#836): nur im angehaltenen Zustand, sonst geht die Taste an die IDE; aus = Kürzel frei.
    Create(TDpccKeyFunction.StepIntoTarget, Word(ASettings.DebugStepIntoTargetKey), AShared,
      ASettings.DebugStepIntoTarget),
    // Typ des markierten Ausdrucks (#689) gibt es seit S3 nicht mehr: Die IDE behält Strg+Umschalt+T.
    Create(TDpccKeyFunction.ExpressionType, Word(ASettings.ExpressionTypeKey), True, False),
    // Sicher löschen (#716): aus = Kürzel frei.
    Create(TDpccKeyFunction.SafeDelete, Word(ASettings.SafeDeleteKey), AShared, ASettings.SafeDelete),
    // Issue anlegen (#1268): frei belegbar, ohne Vorgabe.
    Create(TDpccKeyFunction.CreateIssue, Word(ASettings.CreateIssueKey), AShared,
      ASettings.WelcomePage and ASettings.IssuesCreate)];
  Result := Result + DesignerKeys(ASettings, AShared);
end;

/// <summary>Teil 1 von ToSettings: Taste (und Vorrang) von AEntry in ASettings, wenn die Funktion hierher
/// gehört.</summary>
procedure StoreKeys1(const AEntry: TDpccKeyEntry; var ASettings: TDpccPluginSettings);
begin
  case AEntry.Func of
    TDpccKeyFunction.Palette:
      begin
        ASettings.PaletteKey := AEntry.Key;
        ASettings.PaletteKeyPriority := AEntry.Priority;
      end;
    TDpccKeyFunction.Check:
      begin
        ASettings.CheckKey := AEntry.Key;
        ASettings.CheckKeyPriority := AEntry.Priority;
      end;
    TDpccKeyFunction.Completion:
      begin
        ASettings.CompletionKey := AEntry.Key;
        ASettings.CompletionKeyPriority := AEntry.Priority;
      end;
    TDpccKeyFunction.Signature:
      begin
        ASettings.SignatureKey := AEntry.Key;
        ASettings.SignatureKeyPriority := AEntry.Priority;
      end;
    TDpccKeyFunction.QuickToggle:
      begin
        ASettings.QuickToggleKey := AEntry.Key;
        ASettings.QuickToggleKeyPriority := AEntry.Priority;
      end;
    TDpccKeyFunction.DiagnosticMode:
      begin
        ASettings.DiagnosticModeKey := AEntry.Key;
        ASettings.DiagnosticModeKeyPriority := AEntry.Priority;
      end;
    // Editorbefehle (#399, #721): eine gemeinsame Wahl für alle.
    TDpccKeyFunction.CodeActions:
      begin
        ASettings.ActionsKey := AEntry.Key;
        ASettings.EditorKeysPriority := AEntry.Priority;
      end;
    TDpccKeyFunction.ExpandSelection:
      ASettings.ExpandKey := AEntry.Key;
    TDpccKeyFunction.ShrinkSelection:
      ASettings.ShrinkKey := AEntry.Key;
    TDpccKeyFunction.GoToImplementation:
      ASettings.ImplementationKey := AEntry.Key;
    TDpccKeyFunction.TypeDefinition:
      ASettings.TypeDefinitionKey := AEntry.Key;
    TDpccKeyFunction.UndoChange:
      ASettings.UndoKey := AEntry.Key;
    TDpccKeyFunction.RedoChange:
      ASettings.RedoKey := AEntry.Key;
  else
    // Gehört zu einem anderen Teil.
  end;
end;

/// <summary>Teil 2 von ToSettings: Taste (und Vorrang) von AEntry in ASettings, wenn die Funktion hierher
/// gehört.</summary>
procedure StoreKeys2(const AEntry: TDpccKeyEntry; var ASettings: TDpccPluginSettings);
begin
  case AEntry.Func of
    TDpccKeyFunction.WelcomeSearch:
      ASettings.WelcomePageSearchKey := AEntry.Key;
    TDpccKeyFunction.MethodToggleUp:
      ASettings.MethodToggleUpKey := AEntry.Key;
    TDpccKeyFunction.MethodToggleDown:
      ASettings.MethodToggleDownKey := AEntry.Key;
    TDpccKeyFunction.TestUnit:
      ASettings.TestUnitKey := AEntry.Key;
    TDpccKeyFunction.UnitSearch:
      ASettings.UnitSearchKey := AEntry.Key;
    TDpccKeyFunction.Bookmark:
      ASettings.BookmarkKey := AEntry.Key;
    TDpccKeyFunction.GenerateMenu:
      ASettings.GenerateMenuKey := AEntry.Key;
    TDpccKeyFunction.Notifications:
      ASettings.NotificationsKey := AEntry.Key;
    TDpccKeyFunction.WelcomeQuickBuild:
      ASettings.WelcomePageQuickActionsBuildKey := AEntry.Key;
    TDpccKeyFunction.WelcomeQuickTests:
      ASettings.WelcomePageQuickActionsTestKey := AEntry.Key;
    TDpccKeyFunction.HideElement:
      ASettings.HideElementKey := AEntry.Key;
    TDpccKeyFunction.NextProblem:
      ASettings.NextProblemKey := AEntry.Key;
    TDpccKeyFunction.PreviousProblem:
      ASettings.PreviousProblemKey := AEntry.Key;
  else
    // Gehört zu einem anderen Teil.
  end;
end;

/// <summary>Teil 3 von ToSettings: Taste (und Vorrang) von AEntry in ASettings, wenn die Funktion hierher
/// gehört.</summary>
procedure StoreKeys3(const AEntry: TDpccKeyEntry; var ASettings: TDpccPluginSettings);
begin
  case AEntry.Func of
    TDpccKeyFunction.QuickOpen:
      ASettings.QuickOpenKey := AEntry.Key;
    TDpccKeyFunction.NavBack:
      ASettings.NavBackKey := AEntry.Key;
    TDpccKeyFunction.NavForward:
      ASettings.NavForwardKey := AEntry.Key;
    TDpccKeyFunction.LastEdit:
      ASettings.LastEditKey := AEntry.Key;
    TDpccKeyFunction.PeekDefinition:
      ASettings.PeekDefinitionKey := AEntry.Key;
    TDpccKeyFunction.PeekReferences:
      ASettings.PeekReferencesKey := AEntry.Key;
    TDpccKeyFunction.Breadcrumbs:
      ASettings.BreadcrumbsKey := AEntry.Key;
    TDpccKeyFunction.JumpToMatch:
      ASettings.JumpToMatchKey := AEntry.Key;
    TDpccKeyFunction.JumpToMatchSelect:
      ASettings.JumpToMatchSelectKey := AEntry.Key;
    TDpccKeyFunction.NextChange:
      ASettings.NextChangeKey := AEntry.Key;
    TDpccKeyFunction.PreviousChange:
      ASettings.PreviousChangeKey := AEntry.Key;
    TDpccKeyFunction.MoveLinesUp:
      ASettings.MoveLinesUpKey := AEntry.Key;
    TDpccKeyFunction.MoveLinesDown:
      ASettings.MoveLinesDownKey := AEntry.Key;
  else
    // Gehört zu einem anderen Teil.
  end;
end;

/// <summary>Teil 4 von ToSettings: Taste (und Vorrang) von AEntry in ASettings, wenn die Funktion hierher
/// gehört.</summary>
procedure StoreKeys4(const AEntry: TDpccKeyEntry; var ASettings: TDpccPluginSettings);
begin
  case AEntry.Func of
    TDpccKeyFunction.DuplicateLinesUp:
      ASettings.DuplicateLinesUpKey := AEntry.Key;
    TDpccKeyFunction.DuplicateLinesDown:
      ASettings.DuplicateLinesDownKey := AEntry.Key;
    TDpccKeyFunction.CompleteStatement:
      ASettings.CompleteStatementKey := AEntry.Key;
    TDpccKeyFunction.MultiCursorNext:
      ASettings.MultiCursorNextKey := AEntry.Key;
    TDpccKeyFunction.MultiCursorSkip:
      ASettings.MultiCursorSkipKey := AEntry.Key;
    TDpccKeyFunction.MultiCursorLineEnds:
      ASettings.MultiCursorLineEndsKey := AEntry.Key;
    TDpccKeyFunction.MultiCursorAbove:
      ASettings.MultiCursorAboveKey := AEntry.Key;
    TDpccKeyFunction.MultiCursorBelow:
      ASettings.MultiCursorBelowKey := AEntry.Key;
    TDpccKeyFunction.Search:
      ASettings.SearchKey := AEntry.Key;
    TDpccKeyFunction.SearchNext:
      ASettings.SearchNextKey := AEntry.Key;
    TDpccKeyFunction.SearchPrevious:
      ASettings.SearchPreviousKey := AEntry.Key;
    TDpccKeyFunction.SearchMethod:
      ASettings.SearchMethodKey := AEntry.Key;
    TDpccKeyFunction.SearchReplace:
      ASettings.SearchReplaceKey := AEntry.Key;
  else
    // Gehört zu einem anderen Teil.
  end;
end;

/// <summary>Teil 5 von ToSettings: Taste (und Vorrang) von AEntry in ASettings, wenn die Funktion hierher
/// gehört.</summary>
procedure StoreKeys5(const AEntry: TDpccKeyEntry; var ASettings: TDpccPluginSettings);
begin
  case AEntry.Func of
    TDpccKeyFunction.FormatCode:
      ASettings.FormatCodeKey := AEntry.Key;
    TDpccKeyFunction.ToggleBlockComment:
      ASettings.ToggleBlockCommentKey := AEntry.Key;
    TDpccKeyFunction.NewLineBelow:
      ASettings.NewLineBelowKey := AEntry.Key;
    TDpccKeyFunction.NewLineAbove:
      ASettings.NewLineAboveKey := AEntry.Key;
    TDpccKeyFunction.Unwrap:
      ASettings.UnwrapKey := AEntry.Key;
    TDpccKeyFunction.ProblemsWindow:
      ASettings.ProblemsWindowKey := AEntry.Key;
    TDpccKeyFunction.SectionInterface:
      ASettings.GotoInterfaceKey := AEntry.Key;
    TDpccKeyFunction.SectionImplementation:
      ASettings.GotoImplementationKey := AEntry.Key;
    TDpccKeyFunction.QuickBookmark:
      begin
        ASettings.QuickBookmarkKey := AEntry.Key;
        ASettings.QuickBookmarkKeyPriority := AEntry.Priority;
      end;
    TDpccKeyFunction.QuickBookmarkSet:
      begin
        ASettings.QuickBookmarkSetKey := AEntry.Key;
        ASettings.QuickBookmarkSetKeyPriority := AEntry.Priority;
      end;
    TDpccKeyFunction.QuickBookmarkJump:
      begin
        ASettings.QuickBookmarkJumpKey := AEntry.Key;
        ASettings.QuickBookmarkJumpKeyPriority := AEntry.Priority;
      end;
    TDpccKeyFunction.NextBookmark:
      ASettings.NextBookmarkKey := AEntry.Key;
    TDpccKeyFunction.PreviousBookmark:
      ASettings.PreviousBookmarkKey := AEntry.Key;
  else
    // Gehört zu einem anderen Teil.
  end;
end;

/// <summary>Teil 6 von ToSettings: Taste (und Vorrang) von AEntry in ASettings, wenn die Funktion hierher
/// gehört.</summary>
procedure StoreKeys6(const AEntry: TDpccKeyEntry; var ASettings: TDpccPluginSettings);
begin
  case AEntry.Func of
    TDpccKeyFunction.StepIntoTarget:
      ASettings.DebugStepIntoTargetKey := AEntry.Key;
    TDpccKeyFunction.ExpressionType:
      ASettings.ExpressionTypeKey := AEntry.Key;
    TDpccKeyFunction.SafeDelete:
      ASettings.SafeDeleteKey := AEntry.Key;
    TDpccKeyFunction.CreateIssue:
      ASettings.CreateIssueKey := AEntry.Key;
    TDpccKeyFunction.DesignerSearch:
      ASettings.DesignerSearchKey := AEntry.Key;
    TDpccKeyFunction.CheckFile:
      ASettings.CheckFileKey := AEntry.Key;
    TDpccKeyFunction.SectionAppend:
      ASettings.SectionAppendKey := AEntry.Key;
    TDpccKeyFunction.DesignerSelectionSetsSave:
      ASettings.DesignerSelectionSetsSaveKey := AEntry.Key;
    TDpccKeyFunction.DesignerShowComponent:
      ASettings.DesignerShowInDesignerKey := AEntry.Key;
    TDpccKeyFunction.DesignerInlineCaption:
      ASettings.DesignerInlineCaptionKey := AEntry.Key;
    TDpccKeyFunction.DesignerSelectionBar:
      ASettings.DesignerSelectionBarKey := AEntry.Key;
    TDpccKeyFunction.DesignerMagnifier:
      ASettings.DesignerMagnifierKey := AEntry.Key;
    TDpccKeyFunction.DesignerUsages:
      ASettings.DesignerUsagesKey := AEntry.Key;
  else
    // Gehört zu einem anderen Teil.
  end;
end;

class procedure TDpccKeyEntry.ToSettings(const AEntries: TArray<TDpccKeyEntry>;
  var ASettings: TDpccPluginSettings);
var
  mEntry: TDpccKeyEntry;
begin
  // Strg+F12 (UnitSearchIde) ist fest; ein- und ausgeschaltet wird über unitSearch.replaceIdeDialog.
  for mEntry in AEntries do
  begin
    StoreKeys1(mEntry, ASettings);
    StoreKeys2(mEntry, ASettings);
    StoreKeys3(mEntry, ASettings);
    StoreKeys4(mEntry, ASettings);
    StoreKeys5(mEntry, ASettings);
    StoreKeys6(mEntry, ASettings);
  end;
end;

function TDpccKeyEntry.IdeKey: Word;
begin
  case Func of
    TDpccKeyFunction.Completion:
      Result := TDpccKeyConflicts.cIdeCompletionKey;
    TDpccKeyFunction.Signature:
      Result := TDpccKeyConflicts.cIdeSignatureKey;
  else
    Result := 0;
  end;
end;

function TDpccKeyEntry.Choice: TDpccKeyChoice;
begin
  if Priority then
  begin
    Result := TDpccKeyChoice.UseDpcc;
  end
  else
  begin
    Result := TDpccKeyChoice.LeaveOther;
  end;
end;

procedure TDpccKeyEntry.Choose(AChoice: TDpccKeyChoice);
begin
  Priority := AChoice = TDpccKeyChoice.UseDpcc;
  if Priority and (Key = 0) then
  begin
    Key := IdeKey;
  end;
end;

function TDpccKeyEntry.Status(const AOwner: string): TDpccKeyStatus;
begin
  if Disabled then
  begin
    Result := TDpccKeyStatus.NoKey;
  end
  else if Key = 0 then
  begin
    if IdeKey <> 0 then
    begin
      Result := TDpccKeyStatus.IdeKey;
    end
    else
    begin
      Result := TDpccKeyStatus.NoKey;
    end;
  end
  else if AOwner = '' then
  begin
    Result := TDpccKeyStatus.Free;
  end
  else if Priority then
  begin
    Result := TDpccKeyStatus.DpccWins;
  end
  else
  begin
    Result := TDpccKeyStatus.Left;
  end;
end;

{ TDpccKeyOwner }

class function TDpccKeyOwner.Create(AShortCut: Word; const AOwner: string): TDpccKeyOwner;
begin
  Result.ShortCut := AShortCut;
  Result.Owner := AOwner;
end;

{ TDpccKeyConflicts }

class function TDpccKeyConflicts.KnownIdeKeys: TArray<TDpccKeyOwner>;
var
  mDigit: Integer;
begin
  Result := [TDpccKeyOwner.Create(cScCtrl or cScShift or Ord('P'), UiText(TKeyConflictsText.IDEPlayKeyboardMacro)),
    TDpccKeyOwner.Create(cScCtrl or cScShift or Ord('R'), UiText(TKeyConflictsText.IDERecordKeyboardMacro)),
    // Zeilen verschieben und duplizieren (#634) nimmt diese Tasten mit Vorrang.
    TDpccKeyOwner.Create(cScAlt or $26, UiText(TKeyConflictsText.IDECodeBrowsingFindDeclaration)), // VK_UP
    TDpccKeyOwner.Create(cScShift or cScAlt or $26, UiText(TKeyConflictsText.IDESelectColumnBlockUp)),
    TDpccKeyOwner.Create(cScShift or cScAlt or $28, UiText(TKeyConflictsText.IDESelectColumnBlockDown)), // VK_DOWN
    // Anweisung vervollständigen (#697) nimmt Strg+Umschalt+Enter mit Vorrang.
    TDpccKeyOwner.Create(cScCtrl or cScShift or $0D, UiText(TKeyConflictsText.IDEFindReferences)), // VK_RETURN
    // Typ des markierten Ausdrucks (#689) nimmt Strg+Umschalt+T mit Vorrang.
    TDpccKeyOwner.Create(cScCtrl or cScShift or Ord('T'), UiText(TKeyConflictsText.IDEAddToDoItem)),
    // Schnelle Lesezeichen (#1104): erster Teil der Faltungsakkorde.
    TDpccKeyOwner.Create(cScCtrl or cScShift or Ord('K'), UiText(TKeyConflictsText.IDEFoldingCtrlShiftK))];
  // Lesezeichen 0–9 der IDE; 0 bleibt immer bei ihr.
  for mDigit := 0 to 9 do
  begin
    Result := Result + [TDpccKeyOwner.Create(cScCtrl or cScShift or (Ord('0') + mDigit),
      Format(UiText(TKeyConflictsText.IDEToggleBookmark), [mDigit])),
        TDpccKeyOwner.Create(cScCtrl or (Ord('0') + mDigit),
      Format(UiText(TKeyConflictsText.IDEGoToBookmark), [mDigit]))];
  end;
end;

class function TDpccKeyConflicts.OwnerOf(AShortCut: Word; const AKeys: TArray<TDpccKeyOwner>): string;
var
  mKey: TDpccKeyOwner;
begin
  Result := '';
  if AShortCut = 0 then
  begin
    Exit;
  end;
  for mKey in AKeys do
  begin
    if mKey.ShortCut = AShortCut then
    begin
      Exit(mKey.Owner);
    end;
  end;
end;

class function TDpccKeyConflicts.ShouldBind(AShortCut: Word; const AOwner: string; APriority: Boolean): Boolean;
begin
  Result := (AShortCut <> 0) and ((AOwner = '') or APriority);
end;

class function TDpccKeyConflicts.CompletionExtensions(const AModules: TArray<string>): TArray<string>;
type
  TKnown = record
    Prefix: string;
    mName: string;
  end;
const
  // Package-Namen (ohne Version) und Anzeigename; nur Erweiterungen mit eigener Vervollständigung.
  cKnown: array[0..2] of TKnown = (
    (Prefix: 'CnWizards'; mName: 'CnPack (Input Helper)'),
    (Prefix: 'Castalia'; mName: 'Castalia'),
    (Prefix: 'CodeInsightPlus'; mName: 'Code Insight Plus'));
var
  mModule, mName: string;
  mIndex: Integer;
  mFound: Boolean;
begin
  Result := nil;
  for mIndex := Low(cKnown) to High(cKnown) do
  begin
    mFound := False;
    for mModule in AModules do
    begin
      mName := ExtractFileName(mModule);
      if mName.StartsWith(cKnown[mIndex].Prefix, True) then
      begin
        mFound := True;
      end;
    end;
    if mFound then
    begin
      Result := Result + [cKnown[mIndex].mName];
    end;
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Commands.KeyConflicts', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
