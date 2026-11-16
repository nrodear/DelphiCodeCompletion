unit dpcc.Core.Commands.KeyMap;

// Tastenkürzel-Übersicht mit Konflikterkennung (#520), Teil ohne VCL und Open
// Tools API. Die IDE-Schicht sammelt alle Belegungen als TDpccKeyItem:
// Aktionen der IDE und anderer Erweiterungen (INTAServices.ActionList),
// Tastaturbelegungen des Editors (IOTAKeyboardServices, soweit auslesbar) und
// die Tasten von dpcc (TDpccKeyEntry.AllFromSettings, #399, #494, #502).
// Hier entsteht daraus die Übersicht:
// - Konflikt: dieselbe Taste, sich überschneidender Kontext (global
//   überschneidet sich mit allem) und verschiedene Besitzer (Herkunft, bei
//   dpcc die Funktion, bei Erweiterungen der Package-Name). Doppelte
//   Belegungen innerhalb der IDE sind ihre eigene Sache und kein Konflikt.
// - Wer gewinnt, entscheidet der Kontext, in dem sich die Belegungen treffen:
//   auf der Willkommensseite das Suchfeld von dpcc; im Editor eine
//   Tastaturbelegung vor einem Menübefehl, unter mehreren die wirksame
//   (zuletzt angemeldete); dpcc mit Vorrang vor der fremden Belegung; ohne
//   Vorrang überlässt dpcc die Taste (#494); unter Aktionen die erste der
//   Aktionsliste.
// - Suche nach Taste („Strg+Umschalt+P“, auch englisch „Ctrl+Shift+P“, nur
//   Umschalttasten „Strg+Alt“) oder nach Text in Taste, Befehl, Kategorie und
//   Herkunft.
// - Export als druckbare HTML-Seite (Zeilen mit Konflikt rot).
// - DpccConflicts liefert die dpcc-Tasten mit offenem Konflikt für die
//   Meldung beim Start und die Einrichtung (#625).
// - „Units suchen“ übernimmt Strg+F12 (#777): Die Taste bleibt bei der Aktion
//   der IDE; die Übersicht zeigt die Aktion als dpcc-Zeile (Quelle Action,
//   Kontext global), solange die Übernahme an ist.

interface

uses
  System.SysUtils,
  dpcc.Core.Commands.KeyConflicts;

type
  {$SCOPEDENUMS ON}
  /// <summary>Wem die Belegung gehört.</summary>
  TDpccKeyOrigin = (Ide, Dpcc, Plugin);
  /// <summary>Wo die Taste wirkt; Global überschneidet sich mit jedem anderen Kontext.</summary>
  TDpccKeyContext = (Global, Editor, Designer, WelcomePage);
  /// <summary>Action: Aktion mit Tastenkürzel (Menü, wirkt im ganzen Hauptfenster); Binding: Tastaturbelegung des
  /// Editors (IOTAKeyboardBinding); Window: Kürzel eines eigenen Fensters (Suchfeld der Willkommensseite).</summary>
  TDpccKeySource = (Action, Binding, Window);
  /// <summary>Warum der Gewinner eines Konflikts gewinnt.</summary>
  TDpccKeyReason = (None, DpccPriority, DpccYields, EditorBinding, LastBinding, FirstAction, OwnWindow,
    NoneActive);
  {$SCOPEDENUMS OFF}

  /// <summary>Aktion der IDE, die ein Modul übernommen hat, etwa Strg+F12 „Units“ für „Units suchen“ (#777).
  /// </summary>
  TDpccTakenAction = record
    /// <summary>dpcc-Funktion, die an Stelle der Aktion läuft.</summary>
    Func: TDpccKeyFunction;
    /// <summary>Name der Aktion in der Aktionsliste der IDE.</summary>
    ActionName: string;
  end;

  /// <summary>Übernommene Aktionen eines Moduls für die Tastenkürzel-Übersicht (#520, #1455); Hauptthread.
  /// </summary>
  IDpccTakenActions = interface
    ['{CA511338-4188-48A9-B7C7-E5B6CC0FFD28}']
    function TakenActions: TArray<TDpccTakenAction>;
  end;

  /// <summary>Wem eine Belegung gehört und woher sie stammt (für TDpccKeyItem.Create).</summary>
  TDpccKeyProvenance = record
    Origin: TDpccKeyOrigin;
    /// <summary>„IDE“, „dpcc“ oder der Package-Name der Erweiterung (ohne Pfad).</summary>
    OriginName: string;
    Context: TDpccKeyContext;
    Source: TDpccKeySource;
    /// <summary>Eindeutig je Quelle: Name der Aktion, dpcc-Funktion, Taste der Tastaturbelegung.</summary>
    Id: string;
    /// <summary>Reihenfolge in der Quelle (Aktionsliste, Anmeldung).</summary>
    Order: Integer;
    class function Create(AOrigin: TDpccKeyOrigin; const AOriginName: string; AContext: TDpccKeyContext;
      ASource: TDpccKeySource; const AId: string; AOrder: Integer): TDpccKeyProvenance; static;
  end;

  /// <summary>Eine Belegung einer Taste.</summary>
  TDpccKeyItem = record
    ShortCut: Word;
    /// <summary>Taste als Text, wie die IDE sie zeigt (ShortCutToText).</summary>
    KeyText: string;
    Command: string;
    /// <summary>Kategorie bzw. Menüpfad; '' ohne.</summary>
    Category: string;
    Origin: TDpccKeyOrigin;
    /// <summary>„IDE“, „dpcc“ oder der Package-Name der Erweiterung (ohne Pfad).</summary>
    OriginName: string;
    Context: TDpccKeyContext;
    Source: TDpccKeySource;
    /// <summary>Eindeutig je Quelle: Name der Aktion, dpcc-Funktion, Taste der Tastaturbelegung.</summary>
    Id: string;
    /// <summary>Reihenfolge in der Quelle (Aktionsliste, Anmeldung).</summary>
    Order: Integer;
    /// <summary>Hält die Taste: dpcc nur, wenn frei oder mit Vorrang belegt (#494); sonst immer True.</summary>
    Active: Boolean;
    /// <summary>dpcc: Vorrang gewählt („dpcc verwenden“).</summary>
    Priority: Boolean;
    /// <summary>Wirksame Tastaturbelegung des Editors für diese Taste (Abfrage der IDE).</summary>
    Effective: Boolean;
    /// <summary>Nur bei Herkunft dpcc: die Funktion.</summary>
    Func: TDpccKeyFunction;
    /// <summary>Ergebnis von Analyze: mindestens eine andere Belegung kollidiert.</summary>
    Conflict: Boolean;
    /// <summary>Ergebnis von Analyze: Index der Belegung, die im gemeinsamen Kontext gewinnt; -1 = keine.</summary>
    Winner: Integer;
    Wins: Boolean;
    Reason: TDpccKeyReason;
    /// <summary>Aufrufe des Befehls per Maus bzw. über das Kürzel (#600, Spalte „Selten per Tastatur“); 0 ohne
    /// Zählung.</summary>
    MouseUses: Integer;
    KeyUses: Integer;
    class function Create(AShortCut: Word; const AKeyText, ACommand: string;
      const AOwner: TDpccKeyProvenance): TDpccKeyItem; static;
    /// <summary>„Befehl (Herkunft)“ für Meldungen.</summary>
    function Holder: string;
    /// <summary>Selten per Tastatur genutzt (TDpccCommandUsage.IsRarelyByKeyboard).</summary>
    function RarelyByKeyboard: Boolean;
  end;

  /// <summary>Suche in der Übersicht.</summary>
  TDpccKeyQuery = record
    /// <summary>Kleingeschrieben und ohne Leerraum am Rand.</summary>
    Text: string;
    /// <summary>Erkannte Taste; 0 = keine.</summary>
    ShortCut: Word;
    /// <summary>Nur Umschalttasten erkannt („Strg+Umschalt“); 0 = keine.</summary>
    Modifiers: Word;
    class function Parse(const AText: string): TDpccKeyQuery; static;
    function IsEmpty: Boolean;
    function Matches(const AItem: TDpccKeyItem): Boolean;
  end;

  /// <summary>Zeile der HTML-Übersicht: Zellen als Klartext.</summary>
  TDpccKeyHtmlRow = record
    Cells: TArray<string>;
    Conflict: Boolean;
    class function Create(const ACells: TArray<string>; AConflict: Boolean): TDpccKeyHtmlRow; static;
  end;

  TDpccKeyMap = class
  public const
    cIdeName = 'IDE';
    cDpccName = 'dpcc';
    cScShift = TDpccKeyConflicts.cScShift;
    cScCtrl = TDpccKeyConflicts.cScCtrl;
    cScAlt = TDpccKeyConflicts.cScAlt;
    cModifierMask = cScShift or cScCtrl or cScAlt;
  public
    /// <summary>Kontext einer dpcc-Taste: das Suchfeld auf der Willkommensseite, Strg+F12 für „Units suchen“
    /// global (Aktion der IDE), alle übrigen im Editor (Tastaturbelegungen wirken nur dort).</summary>
    class function ContextOf(AFunc: TDpccKeyFunction): TDpccKeyContext; static;
    /// <summary>Window für das Suchfeld, Action für Strg+F12 (#777), sonst Binding.</summary>
    class function SourceOf(AFunc: TDpccKeyFunction): TDpccKeySource; static;
    /// <summary>Befehl der Befehlspalette (#502) zu einer dpcc-Taste; '' ohne. Mehrere Tasten können denselben
    /// Befehl haben (beide Tasten von Deklaration ⇄ Implementierung, eigene Taste und Strg+F12 für „Units
    /// suchen“).</summary>
    class function CommandIdOf(AFunc: TDpccKeyFunction): string; static;
    /// <summary>Kontext einer Aktion nach ihrer Kategorie: „Designer“/„Formular“ = Designer, „Editor“ = Editor,
    /// sonst global (Menübefehle wirken im ganzen Hauptfenster).</summary>
    class function ContextOfCategory(const ACategory: string): TDpccKeyContext; static;
    /// <summary>Herkunft nach dem Modul, das die Belegung umsetzt: dpcc-Package, Ordner der IDE (bds.exe) oder
    /// eine andere Erweiterung; AName ist dann der Package-Name ohne Pfad und Endung.</summary>
    class function OriginOfModule(const AModule, AIdeFolder, ADpccModule: string;
      out AName: string): TDpccKeyOrigin; static;
    class function Overlaps(A, B: TDpccKeyContext): Boolean; static;
    /// <summary>A und B belegen dieselbe Taste in sich überschneidendem Kontext und gehören verschiedenen
    /// Besitzern.</summary>
    class function Collide(const A, B: TDpccKeyItem): Boolean; static;
    /// <summary>Konflikte, Gewinner und Grund für jede Belegung setzen.</summary>
    class procedure Analyze(var AItems: TArray<TDpccKeyItem>); static;
    /// <summary>Belegungen mit Konflikt.</summary>
    class function ConflictCount(const AItems: TArray<TDpccKeyItem>): Integer; static;
    /// <summary>Andere Belegung im Konflikt mit AItems[AIndex]: der Gewinner, wenn es nicht sie selbst ist,
    /// sonst die erste kollidierende; -1 ohne Konflikt.</summary>
    class function PartnerOf(const AItems: TArray<TDpccKeyItem>; AIndex: Integer): Integer; static;
    /// <summary>dpcc-Tasten mit offenem Konflikt: kollidiert und nicht mit Vorrang gewonnen (#520, #625).</summary>
    class function DpccConflicts(const AItems: TArray<TDpccKeyItem>): TArray<Integer>; static;
    /// <summary>Indizes der Belegungen zur Suche, sortiert nach Taste und Befehl.</summary>
    class function Filter(const AItems: TArray<TDpccKeyItem>; const AQuery: string;
      AOnlyConflicts: Boolean): TArray<Integer>; static;
    /// <summary>Taste aus Text: Umschalttasten deutsch oder englisch, dann eine Taste; 0, wenn nicht erkannt.
    /// AModifiers bekommt die Umschalttasten auch ohne Taste.</summary>
    class function ParseShortCut(const AText: string; out AModifiers: Word): Word; static;
    /// <summary>Druckbare HTML-Seite: Titel, Unterzeile, Knopf „Drucken“, Tabelle; Zeilen mit Konflikt rot.</summary>
    class function Html(const ALanguage, ATitle, ASubtitle, APrint: string; const AHeaders: TArray<string>;
      const ARows: TArray<TDpccKeyHtmlRow>): string; static;
    class function HtmlEscape(const AText: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  dpcc.Core.Commands.Usage;

{ TDpccKeyProvenance }

class function TDpccKeyProvenance.Create(AOrigin: TDpccKeyOrigin; const AOriginName: string;
  AContext: TDpccKeyContext; ASource: TDpccKeySource; const AId: string; AOrder: Integer): TDpccKeyProvenance;
begin
  Result.Origin := AOrigin;
  Result.OriginName := AOriginName;
  Result.Context := AContext;
  Result.Source := ASource;
  Result.Id := AId;
  Result.Order := AOrder;
end;

{ TDpccKeyItem }

class function TDpccKeyItem.Create(AShortCut: Word; const AKeyText, ACommand: string;
  const AOwner: TDpccKeyProvenance): TDpccKeyItem;
begin
  Result := Default(TDpccKeyItem);
  Result.ShortCut := AShortCut;
  Result.KeyText := AKeyText;
  Result.Command := ACommand;
  Result.Origin := AOwner.Origin;
  Result.OriginName := AOwner.OriginName;
  Result.Context := AOwner.Context;
  Result.Source := AOwner.Source;
  Result.Id := AOwner.Id;
  Result.Order := AOwner.Order;
  Result.Active := True;
  Result.Winner := -1;
end;

function TDpccKeyItem.RarelyByKeyboard: Boolean;
begin
  Result := TDpccCommandUsage.IsRarelyByKeyboard(MouseUses, KeyUses);
end;

function TDpccKeyItem.Holder: string;
begin
  if OriginName = '' then
  begin
    Result := Command;
  end
  else
  begin
    Result := Command + ' (' + OriginName + ')';
  end;
end;

{ TDpccKeyQuery }

class function TDpccKeyQuery.Parse(const AText: string): TDpccKeyQuery;
begin
  Result := Default(TDpccKeyQuery);
  Result.Text := LowerCase(Trim(AText));
  Result.ShortCut := TDpccKeyMap.ParseShortCut(AText, Result.Modifiers);
end;

function TDpccKeyQuery.IsEmpty: Boolean;
begin
  Result := Text = '';
end;

function TDpccKeyQuery.Matches(const AItem: TDpccKeyItem): Boolean;
begin
  if Text = '' then
  begin
    Exit(True);
  end;
  if ShortCut <> 0 then
  begin
    Exit(AItem.ShortCut = ShortCut);
  end;
  if Modifiers <> 0 then
  begin
    Exit((AItem.ShortCut <> 0) and ((AItem.ShortCut and Modifiers) = Modifiers));
  end;
  Result := (Pos(Text, LowerCase(AItem.KeyText)) > 0) or (Pos(Text, LowerCase(AItem.Command)) > 0) or
    (Pos(Text, LowerCase(AItem.Category)) > 0) or (Pos(Text, LowerCase(AItem.OriginName)) > 0);
end;

{ TDpccKeyHtmlRow }

class function TDpccKeyHtmlRow.Create(const ACells: TArray<string>; AConflict: Boolean): TDpccKeyHtmlRow;
begin
  Result.Cells := ACells;
  Result.Conflict := AConflict;
end;

{ TDpccKeyMap }

class function TDpccKeyMap.ContextOf(AFunc: TDpccKeyFunction): TDpccKeyContext;
begin
  case AFunc of
    TDpccKeyFunction.WelcomeSearch, TDpccKeyFunction.WelcomeQuickBuild, TDpccKeyFunction.WelcomeQuickTests:
      Result := TDpccKeyContext.WelcomePage;
    TDpccKeyFunction.UnitSearchIde:
      Result := TDpccKeyContext.Global;
  else
    Result := TDpccKeyContext.Editor;
  end;
end;

class function TDpccKeyMap.SourceOf(AFunc: TDpccKeyFunction): TDpccKeySource;
begin
  case AFunc of
    TDpccKeyFunction.WelcomeSearch, TDpccKeyFunction.WelcomeQuickBuild, TDpccKeyFunction.WelcomeQuickTests:
      Result := TDpccKeySource.Window;
    TDpccKeyFunction.UnitSearchIde:
      Result := TDpccKeySource.Action;
    // Überspringen (#589): nur nach Strg+K, solange mehrere Einfügemarken aktiv sind; keine Bindung der IDE.
    TDpccKeyFunction.MultiCursorSkip:
      Result := TDpccKeySource.Window;
  else
    Result := TDpccKeySource.Binding;
  end;
end;

const
  /// <summary>Befehl der Befehlspalette je dpcc-Taste (CommandIdOf); '' ohne.</summary>
  cCommandIds: array[TDpccKeyFunction] of string = (
    '', // Palette
    'dpcc.CheckNow', // Check
    '', // Completion
    '', // Signature
    'dpcc.QuickToggles', // QuickToggle
    '', // DiagnosticMode
    'dpcc.CodeActions', // CodeActions
    'dpcc.ExpandSelection', // ExpandSelection
    'dpcc.ShrinkSelection', // ShrinkSelection
    'dpcc.Implementations', // GoToImplementation
    'dpcc.TypeDefinition', // TypeDefinition
    'dpcc.UndoChange', // UndoChange
    'dpcc.RedoChange', // RedoChange
    '', // WelcomeSearch
    'dpcc.ToggleMethod', // MethodToggleUp
    'dpcc.ToggleMethod', // MethodToggleDown
    'dpcc.SwitchTestUnit', // TestUnit
    'dpcc.UnitSearch', // UnitSearch
    'dpcc.UnitSearch', // UnitSearchIde
    'dpcc.BookmarkAdd', // Bookmark
    'dpcc.GenerateMenu', // GenerateMenu
    'dpcc.Notifications', // Notifications
    '', // WelcomeQuickBuild
    '', // WelcomeQuickTests
    'dpcc.HideElement', // HideElement
    'dpcc.NextProblem', // NextProblem
    'dpcc.PreviousProblem', // PreviousProblem
    'dpcc.QuickOpen', // QuickOpen
    'dpcc.NavBack', // NavBack
    'dpcc.NavForward', // NavForward
    'dpcc.LastEdit', // LastEdit
    'dpcc.PeekDefinition', // PeekDefinition
    'dpcc.PeekReferences', // PeekReferences
    'dpcc.Breadcrumbs', // Breadcrumbs
    'dpcc.JumpToMatch', // JumpToMatch
    'dpcc.JumpToMatchSelect', // JumpToMatchSelect
    'dpcc.NextChange', // NextChange
    'dpcc.PreviousChange', // PreviousChange
    'dpcc.MoveLinesUp', // MoveLinesUp
    'dpcc.MoveLinesDown', // MoveLinesDown
    'dpcc.DuplicateLinesUp', // DuplicateLinesUp
    'dpcc.DuplicateLinesDown', // DuplicateLinesDown
    'dpcc.CompleteStatement', // CompleteStatement
    'dpcc.MultiCursorNext', // MultiCursorNext
    '', // MultiCursorSkip
    'dpcc.MultiCursorLineEnds', // MultiCursorLineEnds
    'dpcc.MultiCursorAbove', // MultiCursorAbove
    'dpcc.MultiCursorBelow', // MultiCursorBelow
    'dpcc.Search', // Search
    'dpcc.SearchNext', // SearchNext
    'dpcc.SearchPrevious', // SearchPrevious
    'dpcc.SearchInMethod', // SearchMethod
    'dpcc.FormatCode', // FormatCode
    'dpcc.ToggleBlockComment', // ToggleBlockComment
    'dpcc.NewLineBelow', // NewLineBelow
    'dpcc.NewLineAbove', // NewLineAbove
    'dpcc.Unwrap', // Unwrap
    'dpcc.ProblemsWindow', // ProblemsWindow
    'dpcc.GotoInterface', // SectionInterface
    'dpcc.GotoImplementation', // SectionImplementation
    'dpcc.QuickBookmarkToggle', // QuickBookmark
    '', // QuickBookmarkSet
    '', // QuickBookmarkJump
    'dpcc.NextBookmark', // NextBookmark
    'dpcc.PreviousBookmark', // PreviousBookmark
    'dpcc.SearchReplace', // SearchReplace
    'dpcc.StepIntoTarget', // StepIntoTarget
    'dpcc.ExpressionType', // ExpressionType
    'dpcc.SafeDelete', // SafeDelete
    'dpcc.CreateIssue', // CreateIssue
    '', // DesignerSearch
    'dpcc.CheckFile', // CheckFile
    'dpcc.SectionAppend', // SectionAppend
    '', // DesignerSelectionSetsSave
    'dpcc.ShowInDesigner', // DesignerShowComponent
    '', // DesignerInlineCaption
    '', // DesignerSelectionBar
    '', // DesignerMagnifier
    '' // DesignerUsages
  );

class function TDpccKeyMap.CommandIdOf(AFunc: TDpccKeyFunction): string;
begin
  Result := cCommandIds[AFunc];
end;

class function TDpccKeyMap.ContextOfCategory(const ACategory: string): TDpccKeyContext;
var
  mLower: string;
begin
  mLower := LowerCase(ACategory);
  if (Pos('designer', mLower) > 0) or (Pos('formular', mLower) > 0) then
  begin
    Result := TDpccKeyContext.Designer;
  end
  else if Pos('editor', mLower) > 0 then
  begin
    Result := TDpccKeyContext.Editor;
  end
  else
  begin
    Result := TDpccKeyContext.Global;
  end;
end;

class function TDpccKeyMap.OriginOfModule(const AModule, AIdeFolder, ADpccModule: string;
  out AName: string): TDpccKeyOrigin;
var
  mFolder, mName: string;
begin
  // Kein Pfad nach außen: nur der Package-Name einer Erweiterung.
  mName := ExtractFileName(AModule.Replace('/', '\'));
  if (ADpccModule <> '') and SameText(AModule, ADpccModule) then
  begin
    AName := cDpccName;
    Exit(TDpccKeyOrigin.Dpcc);
  end;
  mFolder := IncludeTrailingPathDelimiter(AIdeFolder.Replace('/', '\'));
  if (AModule = '') or ((AIdeFolder <> '') and AModule.Replace('/', '\').StartsWith(mFolder, True)) then
  begin
    AName := cIdeName;
    Exit(TDpccKeyOrigin.Ide);
  end;
  AName := ChangeFileExt(mName, '');
  Result := TDpccKeyOrigin.Plugin;
end;

class function TDpccKeyMap.Overlaps(A, B: TDpccKeyContext): Boolean;
begin
  Result := (A = B) or (A = TDpccKeyContext.Global) or (B = TDpccKeyContext.Global);
end;

class function TDpccKeyMap.Collide(const A, B: TDpccKeyItem): Boolean;
begin
  Result := False;
  if (A.ShortCut = 0) or (A.ShortCut <> B.ShortCut) or not Overlaps(A.Context, B.Context) then
  begin
    Exit;
  end;
  if A.Origin <> B.Origin then
  begin
    Exit(True);
  end;
  case A.Origin of
    // Zwei dpcc-Funktionen auf derselben Taste: doppelt belegt.
    TDpccKeyOrigin.Dpcc:
      Result := A.Id <> B.Id;
    TDpccKeyOrigin.Plugin:
      Result := not SameText(A.OriginName, B.OriginName);
  else
    // Belegungen innerhalb der IDE sind ihre eigene Sache.
    Result := False;
  end;
end;

/// <summary>Kontext, in dem sich AItems[AIndex] mit den Partnern trifft: der eigene, bei globalen Belegungen der
/// engste der Partner (Editor vor Designer vor Willkommensseite).</summary>
function ClashContext(const AItems: TArray<TDpccKeyItem>; AIndex: Integer;
  const APartners: TArray<Integer>): TDpccKeyContext;
var
  mPartner: Integer;
  mFound: Boolean;
  mContext: TDpccKeyContext;
begin
  Result := AItems[AIndex].Context;
  if Result <> TDpccKeyContext.Global then
  begin
    Exit;
  end;
  for mContext in [TDpccKeyContext.Editor, TDpccKeyContext.Designer, TDpccKeyContext.WelcomePage] do
  begin
    mFound := False;
    for mPartner in APartners do
    begin
      if AItems[mPartner].Context = mContext then
      begin
        mFound := True;
      end;
    end;
    if mFound then
    begin
      Exit(mContext);
    end;
  end;
end;

/// <summary>Willkommensseite: Das Suchfeld von dpcc nimmt die Taste, solange die Seite aktiv ist; -1 ohne.
/// </summary>
function WindowWinner(const AItems: TArray<TDpccKeyItem>; const ACandidates: TArray<Integer>): Integer;
var
  mCandidate: Integer;
begin
  Result := -1;
  for mCandidate in ACandidates do
  begin
    if (AItems[mCandidate].Source = TDpccKeySource.Window) and AItems[mCandidate].Active then
    begin
      Exit(mCandidate);
    end;
  end;
end;

function IsActiveBinding(const AItem: TDpccKeyItem): Boolean;
begin
  Result := (AItem.Source = TDpccKeySource.Binding) and AItem.Active;
end;

/// <summary>Erste aktive Tastaturbelegung, die die IDE als wirksam meldet oder (DpccFirst) von dpcc mit Vorrang;
/// -1 ohne.</summary>
function FirstBinding(const AItems: TArray<TDpccKeyItem>; const ACandidates: TArray<Integer>;
  ADpccFirst: Boolean): Integer;
var
  mCandidate: Integer;
  mItem: TDpccKeyItem;
begin
  Result := -1;
  for mCandidate in ACandidates do
  begin
    mItem := AItems[mCandidate];
    if not IsActiveBinding(mItem) then
    begin
      Continue;
    end;
    if (not ADpccFirst and mItem.Effective) or
      (ADpccFirst and (mItem.Origin = TDpccKeyOrigin.Dpcc) and mItem.Priority) then
    begin
      Exit(mCandidate);
    end;
  end;
end;

/// <summary>Löst ACandidate den bisherigen Gewinner AWinner ab? Eine spätere Tastaturbelegung schlägt eine, die
/// weder wirksam ist noch Vorrang hat.</summary>
function Replaces(const AItems: TArray<TDpccKeyItem>; ACandidate, AWinner: Integer): Boolean;
begin
  Result := (AWinner < 0) or ((AItems[AWinner].Source = TDpccKeySource.Binding) and
    not AItems[AWinner].Effective and not AItems[AWinner].Priority and
    (AItems[ACandidate].Order > AItems[AWinner].Order));
end;

/// <summary>Editor: Tastaturbelegungen vor Menübefehlen; unter ihnen die wirksame (zuletzt angemeldete).</summary>
function EditorWinner(const AItems: TArray<TDpccKeyItem>; const ACandidates: TArray<Integer>): Integer;
var
  mCandidate: Integer;
begin
  Result := FirstBinding(AItems, ACandidates, False);
  if Result < 0 then
  begin
    Result := FirstBinding(AItems, ACandidates, True);
  end;
  for mCandidate in ACandidates do
  begin
    if IsActiveBinding(AItems[mCandidate]) and Replaces(AItems, mCandidate, Result) then
    begin
      Result := mCandidate;
    end;
  end;
end;

/// <summary>Die erste aktive Aktion der Aktionsliste; -1 ohne.</summary>
function ActionWinner(const AItems: TArray<TDpccKeyItem>; const ACandidates: TArray<Integer>): Integer;
var
  mCandidate: Integer;
begin
  Result := -1;
  for mCandidate in ACandidates do
  begin
    if (AItems[mCandidate].Source = TDpccKeySource.Action) and AItems[mCandidate].Active and
      ((Result < 0) or (AItems[mCandidate].Order < AItems[Result].Order)) then
    begin
      Result := mCandidate;
    end;
  end;
end;

/// <summary>Gewinnt AWinner nur, weil alle anderen dpcc-Tasten sind, die die Taste überlassen?</summary>
function OnlyDpccLeft(const AItems: TArray<TDpccKeyItem>; const ACandidates: TArray<Integer>;
  AWinner: Integer): Boolean;
var
  mCandidate: Integer;
begin
  Result := AItems[AWinner].Origin <> TDpccKeyOrigin.Dpcc;
  for mCandidate in ACandidates do
  begin
    if (mCandidate <> AWinner) and ((AItems[mCandidate].Origin <> TDpccKeyOrigin.Dpcc) or AItems[mCandidate].Active)
      then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Verliert eine Aktion gegen AWinner?</summary>
function ActionLoses(const AItems: TArray<TDpccKeyItem>; const ACandidates: TArray<Integer>;
  AWinner: Integer): Boolean;
var
  mCandidate: Integer;
begin
  Result := False;
  for mCandidate in ACandidates do
  begin
    if (mCandidate <> AWinner) and (AItems[mCandidate].Source = TDpccKeySource.Action) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Warum AWinner unter ACandidates gewinnt.</summary>
function ReasonOf(const AItems: TArray<TDpccKeyItem>; const ACandidates: TArray<Integer>;
  AWinner: Integer): TDpccKeyReason;
var
  mWinner: TDpccKeyItem;
begin
  mWinner := AItems[AWinner];
  if OnlyDpccLeft(AItems, ACandidates, AWinner) then
  begin
    Result := TDpccKeyReason.DpccYields;
  end
  else if mWinner.Source <> TDpccKeySource.Binding then
  begin
    Result := TDpccKeyReason.FirstAction;
  end
  else if (mWinner.Origin = TDpccKeyOrigin.Dpcc) and mWinner.Priority then
  begin
    Result := TDpccKeyReason.DpccPriority;
  end
  else if ActionLoses(AItems, ACandidates, AWinner) then
  begin
    Result := TDpccKeyReason.EditorBinding;
  end
  else
  begin
    Result := TDpccKeyReason.LastBinding;
  end;
end;

/// <summary>Gewinner unter ACandidates im Kontext AClash; -1, wenn keine die Taste hält.</summary>
procedure Decide(const AItems: TArray<TDpccKeyItem>; const ACandidates: TArray<Integer>;
  AClash: TDpccKeyContext; out AWinner: Integer; out AReason: TDpccKeyReason);
begin
  AWinner := -1;
  AReason := TDpccKeyReason.NoneActive;
  if AClash = TDpccKeyContext.WelcomePage then
  begin
    AWinner := WindowWinner(AItems, ACandidates);
  end;
  if AWinner >= 0 then
  begin
    AReason := TDpccKeyReason.OwnWindow;
    Exit;
  end;
  if AClash = TDpccKeyContext.Editor then
  begin
    AWinner := EditorWinner(AItems, ACandidates);
  end;
  // Sonst die erste Aktion der Aktionsliste.
  if AWinner < 0 then
  begin
    AWinner := ActionWinner(AItems, ACandidates);
  end;
  if AWinner >= 0 then
  begin
    AReason := ReasonOf(AItems, ACandidates, AWinner);
  end;
end;

/// <summary>Belegungen, die mit AItems[AIndex] kollidieren.</summary>
function PartnersOf(const AItems: TArray<TDpccKeyItem>; AIndex: Integer): TArray<Integer>;
var
  mOther: Integer;
begin
  Result := nil;
  for mOther := 0 to High(AItems) do
  begin
    if (mOther <> AIndex) and TDpccKeyMap.Collide(AItems[AIndex], AItems[mOther]) then
    begin
      Result := Result + [mOther];
    end;
  end;
end;

/// <summary>AIndex und die Partner, die sich mit dem Kontext AClash überschneiden.</summary>
function CandidatesOf(const AItems: TArray<TDpccKeyItem>; AIndex: Integer; const APartners: TArray<Integer>;
  AClash: TDpccKeyContext): TArray<Integer>;
var
  mOther: Integer;
begin
  Result := [AIndex];
  for mOther in APartners do
  begin
    if TDpccKeyMap.Overlaps(AItems[mOther].Context, AClash) then
    begin
      Result := Result + [mOther];
    end;
  end;
end;

class procedure TDpccKeyMap.Analyze(var AItems: TArray<TDpccKeyItem>);
var
  mIndex, mWinner: Integer;
  mPartners: TArray<Integer>;
  mClash: TDpccKeyContext;
  mReason: TDpccKeyReason;
begin
  for mIndex := 0 to High(AItems) do
  begin
    AItems[mIndex].Conflict := False;
    AItems[mIndex].Winner := -1;
    AItems[mIndex].Wins := False;
    AItems[mIndex].Reason := TDpccKeyReason.None;
  end;
  for mIndex := 0 to High(AItems) do
  begin
    if AItems[mIndex].ShortCut = 0 then
    begin
      Continue;
    end;
    mPartners := PartnersOf(AItems, mIndex);
    if Length(mPartners) = 0 then
    begin
      AItems[mIndex].Winner := mIndex;
      AItems[mIndex].Wins := AItems[mIndex].Active;
      Continue;
    end;
    AItems[mIndex].Conflict := True;
    mClash := ClashContext(AItems, mIndex, mPartners);
    Decide(AItems, CandidatesOf(AItems, mIndex, mPartners, mClash), mClash, mWinner, mReason);
    AItems[mIndex].Winner := mWinner;
    AItems[mIndex].Reason := mReason;
    AItems[mIndex].Wins := mWinner = mIndex;
  end;
end;

class function TDpccKeyMap.ConflictCount(const AItems: TArray<TDpccKeyItem>): Integer;
var
  mItem: TDpccKeyItem;
begin
  Result := 0;
  for mItem in AItems do
  begin
    if mItem.Conflict then
    begin
      Inc(Result);
    end;
  end;
end;

class function TDpccKeyMap.PartnerOf(const AItems: TArray<TDpccKeyItem>; AIndex: Integer): Integer;
var
  mOther: Integer;
begin
  Result := -1;
  if (AIndex < 0) or (AIndex > High(AItems)) or not AItems[AIndex].Conflict then
  begin
    Exit;
  end;
  if (AItems[AIndex].Winner >= 0) and (AItems[AIndex].Winner <> AIndex) then
  begin
    Exit(AItems[AIndex].Winner);
  end;
  for mOther := 0 to High(AItems) do
  begin
    if (mOther <> AIndex) and Collide(AItems[AIndex], AItems[mOther]) then
    begin
      Exit(mOther);
    end;
  end;
end;

class function TDpccKeyMap.DpccConflicts(const AItems: TArray<TDpccKeyItem>): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(AItems) do
  begin
    if (AItems[mIndex].Origin = TDpccKeyOrigin.Dpcc) and AItems[mIndex].Conflict and
      not (AItems[mIndex].Wins and AItems[mIndex].Priority) then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

class function TDpccKeyMap.Filter(const AItems: TArray<TDpccKeyItem>; const AQuery: string;
  AOnlyConflicts: Boolean): TArray<Integer>;
var
  mQuery: TDpccKeyQuery;
  mFound: TList<Integer>;
  mIndex: Integer;
  mItems: TArray<TDpccKeyItem>;
begin
  mItems := AItems;
  mQuery := TDpccKeyQuery.Parse(AQuery);
  mFound := TList<Integer>.Create;
  try
    for mIndex := 0 to High(mItems) do
    begin
      if (not AOnlyConflicts or mItems[mIndex].Conflict) and mQuery.Matches(mItems[mIndex]) then
      begin
        mFound.Add(mIndex);
      end;
    end;
    mFound.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := CompareText(mItems[A].KeyText, mItems[B].KeyText);
        if Result = 0 then
        begin
          Result := Integer(mItems[A].ShortCut) - Integer(mItems[B].ShortCut);
        end;
        if Result = 0 then
        begin
          Result := CompareText(mItems[A].Command, mItems[B].Command);
        end;
        if Result = 0 then
        begin
          Result := A - B;
        end;
      end));
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

/// <summary>Umschalttaste zum Namen (deutsch oder englisch); 0, wenn es keine ist.</summary>
function ModifierOf(const AName: string): Word;
begin
  if (AName = 'strg') or (AName = 'ctrl') or (AName = 'control') or (AName = 'ctl') then
  begin
    Result := TDpccKeyMap.cScCtrl;
  end
  else if (AName = 'umschalt') or (AName = 'umsch') or (AName = 'shift') or (AName = 'shft') then
  begin
    Result := TDpccKeyMap.cScShift;
  end
  else if (AName = 'alt') or (AName = 'menu') then
  begin
    Result := TDpccKeyMap.cScAlt;
  end
  else
  begin
    Result := 0;
  end;
end;

type
  /// <summary>Benannte Taste: Namen zwischen „|“ (deutsch und englisch, klein) und ihr virtueller Tastencode.
  /// </summary>
  TNamedKey = record
    Names: string;
    Key: Word;
  end;

const
  cNamedKeys: array[0..14] of TNamedKey = (
    (Names: '|leer|leertaste|space|'; Key: $20),
    (Names: '|eingabe|enter|return|'; Key: $0D),
    (Names: '|esc|escape|'; Key: $1B),
    (Names: '|tab|tabulator|'; Key: $09),
    (Names: '|entf|del|delete|'; Key: $2E),
    (Names: '|einfg|ins|insert|'; Key: $2D),
    (Names: '|pos1|home|'; Key: $24),
    (Names: '|ende|end|'; Key: $23),
    (Names: '|bild auf|bildauf|pgup|page up|pageup|'; Key: $21),
    (Names: '|bild ab|bildab|pgdn|page down|pagedown|'; Key: $22),
    (Names: '|rück|rücktaste|backspace|bksp|'; Key: $08), // german-ok: Eingabealias
    (Names: '|links|left|'; Key: $25),
    (Names: '|oben|auf|up|'; Key: $26),
    (Names: '|rechts|right|'; Key: $27),
    (Names: '|unten|ab|down|'; Key: $28));

/// <summary>Taste eines einzelnen Zeichens: Buchstabe, Ziffer, Punkt, Komma, Minus; 0 sonst.</summary>
function CharKey(ACh: Char): Word;
begin
  case ACh of
    'a'..'z':
      Result := Ord(UpCase(ACh));
    '0'..'9':
      Result := Ord(ACh);
    '.':
      Result := $BE;
    ',':
      Result := $BC;
    '-':
      Result := $BD;
  else
    Result := 0;
  end;
end;

/// <summary>Taste aus der Tabelle der benannten Tasten; 0, wenn unbekannt.</summary>
function NamedKey(const AName: string): Word;
var
  mNamed: TNamedKey;
begin
  Result := 0;
  // „|“ trennt die Namen in der Tabelle und ist selbst keiner.
  if Pos('|', AName) > 0 then
  begin
    Exit;
  end;
  for mNamed in cNamedKeys do
  begin
    if Pos('|' + AName + '|', mNamed.Names) > 0 then
    begin
      Exit(mNamed.Key);
    end;
  end;
end;

/// <summary>Virtueller Tastencode zum Namen (deutsch oder englisch); 0, wenn unbekannt. AFunctionKey bei F1–F24.
/// </summary>
function KeyOf(const AName: string; out AFunctionKey: Boolean): Word;
var
  mNumber: Integer;
begin
  AFunctionKey := False;
  if Length(AName) <= 1 then
  begin
    Result := 0;
    if AName <> '' then
    begin
      Result := CharKey(AName[1]);
    end;
  end
  else if (AName[1] = 'f') and TryStrToInt(Copy(AName, 2, MaxInt), mNumber) and (mNumber >= 1) and (mNumber <= 24) then
  begin
    AFunctionKey := True;
    Result := $70 + mNumber - 1;
  end
  else
  begin
    Result := NamedKey(AName);
  end;
end;

class function TDpccKeyMap.ParseShortCut(const AText: string; out AModifiers: Word): Word;
var
  mParts: TArray<string>;
  mIndex: Integer;
  mPart: string;
  mModifier, mKey: Word;
  mFunctionKey: Boolean;
begin
  Result := 0;
  AModifiers := 0;
  mParts := LowerCase(Trim(AText)).Split(['+']);
  if Length(mParts) = 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to High(mParts) do
  begin
    mPart := Trim(mParts[mIndex]);
    if (mPart = '') and (mIndex = High(mParts)) and (mIndex > 0) then
    begin
      // „Strg+“: nur Umschalttasten.
      Exit;
    end;
    mModifier := ModifierOf(mPart);
    if mModifier <> 0 then
    begin
      AModifiers := AModifiers or mModifier;
      Continue;
    end;
    // Eine Taste nur am Ende.
    mKey := KeyOf(mPart, mFunctionKey);
    if (mKey = 0) or (mIndex <> High(mParts)) then
    begin
      AModifiers := 0;
      Exit;
    end;
    // Ein einzelnes Zeichen ohne Umschalttaste ist eine Textsuche, eine Funktionstaste nicht.
    if (Length(mParts) = 1) and not mFunctionKey then
    begin
      Exit;
    end;
    Result := mKey or AModifiers;
  end;
end;

class function TDpccKeyMap.HtmlEscape(const AText: string): string;
var
  mBuilder: TStringBuilder;
  mCh: Char;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mCh in AText do
      case mCh of
        '&':
          mBuilder.Append('&amp;');
        '<':
          mBuilder.Append('&lt;');
        '>':
          mBuilder.Append('&gt;');
        '"':
          mBuilder.Append('&quot;');
        '''':
          mBuilder.Append('&#39;');
      else
        mBuilder.Append(mCh);
      end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

const
  /// <summary>Kopf der Seite ab der Formatvorlage bis zum Beginn von body.</summary>
  cHtmlStyle = '<style>'#13#10 +
    'body{font:13px "Segoe UI",Arial,sans-serif;color:#1f2328;margin:24px}'#13#10 +
    'h1{font-size:20px;margin:0 0 4px}'#13#10 +
    'p.sub{color:#59636e;margin:0 0 12px}'#13#10 +
    'button.print{margin:0 0 12px;padding:4px 12px}'#13#10 +
    'table{border-collapse:collapse;width:100%}'#13#10 +
    'th,td{text-align:left;padding:4px 8px;border-bottom:1px solid #d1d9e0;vertical-align:top}'#13#10 +
    'th{background:#f6f8fa}'#13#10 +
    'td.key{font-family:Consolas,"Courier New",monospace;white-space:nowrap}'#13#10 +
    'tr.conflict td{color:#cf222e}'#13#10 +
    'tr.conflict td.key{font-weight:600}'#13#10 +
    '@media print{body{margin:0}button.print{display:none}thead{display:table-header-group}' +
    'tr{page-break-inside:avoid}tr.conflict td{color:#cf222e;-webkit-print-color-adjust:exact;' +
    'print-color-adjust:exact}}'#13#10 +
    '</style>'#13#10'</head>'#13#10'<body>'#13#10;

/// <summary>Tabellenzeile ARow; die erste Zelle ist die Taste, Zeilen mit Konflikt sind markiert.</summary>
procedure AppendRow(ABuilder: TStringBuilder; const ARow: TDpccKeyHtmlRow);
var
  mIndex: Integer;
begin
  if ARow.Conflict then
  begin
    ABuilder.Append('<tr class="conflict">');
  end
  else
  begin
    ABuilder.Append('<tr>');
  end;
  for mIndex := 0 to High(ARow.Cells) do
  begin
    if mIndex = 0 then
    begin
      ABuilder.Append('<td class="key">');
    end
    else
    begin
      ABuilder.Append('<td>');
    end;
    ABuilder.Append(TDpccKeyMap.HtmlEscape(ARow.Cells[mIndex])).Append('</td>');
  end;
  ABuilder.Append('</tr>'#13#10);
end;

class function TDpccKeyMap.Html(const ALanguage, ATitle, ASubtitle, APrint: string;
  const AHeaders: TArray<string>; const ARows: TArray<TDpccKeyHtmlRow>): string;
var
  mBuilder: TStringBuilder;
  mHeader: string;
  mRow: TDpccKeyHtmlRow;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('<!DOCTYPE html>'#13#10'<html lang="').Append(HtmlEscape(ALanguage)).Append('">'#13#10);
    mBuilder.Append('<head>'#13#10'<meta charset="utf-8">'#13#10);
    mBuilder.Append('<title>').Append(HtmlEscape(ATitle)).Append('</title>'#13#10);
    mBuilder.Append(cHtmlStyle);
    mBuilder.Append('<h1>').Append(HtmlEscape(ATitle)).Append('</h1>'#13#10);
    if ASubtitle <> '' then
    begin
      mBuilder.Append('<p class="sub">').Append(HtmlEscape(ASubtitle)).Append('</p>'#13#10);
    end;
    if APrint <> '' then
    begin
      mBuilder.Append('<button class="print" onclick="window.print()">').Append(HtmlEscape(APrint))
        .Append('</button>'#13#10);
    end;
    mBuilder.Append('<table>'#13#10'<thead><tr>');
    for mHeader in AHeaders do
    begin
      mBuilder.Append('<th>').Append(HtmlEscape(mHeader)).Append('</th>');
    end;
    mBuilder.Append('</tr></thead>'#13#10'<tbody>'#13#10);
    for mRow in ARows do
    begin
      AppendRow(mBuilder, mRow);
    end;
    mBuilder.Append('</tbody>'#13#10'</table>'#13#10'</body>'#13#10'</html>'#13#10);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
