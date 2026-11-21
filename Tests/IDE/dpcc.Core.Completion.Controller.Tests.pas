unit dpcc.Core.Completion.Controller.Tests;

// Tests für Filtern (#409) und Ablauf der Vervollständigung (#410, #414) ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccCompletionMatcherTests = class
  public
    [Test]
    procedure RanksExactBeforePrefixBeforeWordStarts;
    [Test]
    procedure MatchesCamelCaseAndSubsequence;
    [Test]
    procedure FiltersAndKeepsSourceOrderOnTies;
  end;

  [TestFixture]
  TDpccCompletionControllerTests = class
  public
    [Test]
    procedure ShowsItemsFilteredByPrefix;
    [Test]
    procedure TypingRefiltersAndResetsSelection;
    [Test]
    procedure KeysMoveSelectionAndEnterCommits;
    [Test]
    procedure EscapeClosesAndKeysPassThroughWhenClosed;
    [Test]
    procedure EscapeBlocksAutomaticReopenInSameWord;
    [Test]
    procedure NoMatchShowsEmptyState;
    [Test]
    procedure EmptyResultShowsEmptyStateUntilEscape;
    [Test]
    procedure CommitCharacterOnlyForClearMatch;
    [Test]
    procedure TypoSuggestionsTakeOnlyEnter;
    [Test]
    procedure ItemsAfterCloseAreDropped;
    [Test]
    procedure TruncatedListIsRequeried;
    [Test]
    procedure RequeryKeepsSelectedEntry;
    [Test]
    procedure CompleteListFiltersLocallyUntilPrefixShrinks;
    [Test]
    procedure SyntaxNoticeReachesView;
    [Test]
    procedure PartialResultsReplaceThenAppend;
    /// <summary>Teilergebnis und Endantwort mit Überschneidung: jeder Eintrag einmal, der erste bleibt, die
    /// Reihenfolge auch (doppelte Einträge beim Start).</summary>
    [Test]
    procedure OverlappingPartsAppearOnce;
    /// <summary>Gewollte Doppelnamen bleiben: andere Unit (#475), Typkonvertierung (#490), andere Signatur
    /// (Überladung); gleicher Name in anderer Schreibweise ist derselbe Eintrag.</summary>
    [Test]
    procedure VariantsSurviveDeduplication;
    /// <summary>Requery ersetzt die Liste: Der Abgleich beginnt neu, Dubletten innerhalb der neuen Teile fallen
    /// weg.</summary>
    [Test]
    procedure RequeryReplacesAndDeduplicatesAnew;
    /// <summary>Eine Zeile je Teil mit Dubletten ins Diagnoselog; Namen nur mit LogNames.</summary>
    [Test]
    procedure RemovedDuplicatesAreLogged;
    /// <summary>Look-ahead ("str|ing"): Präfix + Rest ist vorgewählt, ohne Groß-/Kleinschreibung; ohne passenden
    /// Eintrag oder ohne Rest die gewöhnliche Vorauswahl; Reihenfolge unverändert.</summary>
    [Test]
    procedure LookAheadPreselectsWholeWord;
    /// <summary>Look-ahead: Kommt der Eintrag erst in einem späteren Teilergebnis (#616), wird er dann gewählt.
    /// </summary>
    [Test]
    procedure LookAheadFollowsLaterParts;
    /// <summary>Look-ahead beim Weitertippen: eigene Wahl bleibt bis zur nächsten Änderung des Präfixes, dann gilt
    /// wieder Präfix + Rest; Entf ändert den Rest.</summary>
    [Test]
    procedure LookAheadFollowsTypingAndKeepsOwnChoice;
    /// <summary>Die automatische Vorauswahl klebt nicht: Ein späteres Teilergebnis (#616) sortiert string vor den
    /// bisher gewählten Eintrag, danach ist string gewählt ("test : strin" in einem var-Block).</summary>
    [Test]
    procedure AutoSelectionFollowsLaterParts;
    /// <summary>Eine eigene Wahl mit der Pfeiltaste bleibt nach einem späteren Teilergebnis.</summary>
    [Test]
    procedure OwnChoiceSurvivesLaterParts;
    /// <summary>Requery ersetzt die Liste: ohne eigene Wahl die Vorauswahl der neuen Liste, mit eigener Wahl
    /// derselbe Eintrag.</summary>
    [Test]
    procedure RequeryKeepsOnlyOwnChoice;
  end;

  /// <summary>Diagnosemodus (#479) über den ganzen Ablauf: Quellen, Filtern, erste Liste.</summary>
  [TestFixture]
  TDpccCompletionTimingTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DelayedProviderIsOverBudget;
    [Test]
    procedure NoSourceTextInMeasurements;
    [Test]
    procedure OffMeasuresNothing;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Matching,
  dpcc.Core.Completion.Controller,
  dpcc.Core.Completion.Ranking,
  dpcc.Core.Completion.Usage,
  dpcc.Core.Completion.Composite,
  dpcc.Core.Completion.Providers.Fixed,
  dpcc.Core.Diagnostics.Timing;

type
  TFakeView = class(TInterfacedObject, IDpccCompletionView, IDpccCompletionSyntaxView)
  public
    Shown: Boolean;
    /// <summary>Hinweis bei unvollständigem Code (#457) und wie oft er kam.</summary>
    Syntax: TDpccSyntaxNotice;
    SyntaxCount: Integer;
    ShowCount: Integer;
    Names: string;
    Selected: Integer;
    Empty: Boolean;
    EmptyText: string;
    procedure ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
    procedure ShowSyntax(const ANotice: TDpccSyntaxNotice);
  end;

procedure TFakeView.ShowSyntax(const ANotice: TDpccSyntaxNotice);
begin
  Syntax := ANotice;
  Inc(SyntaxCount);
end;

procedure TFakeView.ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
var
  Index: Integer;
begin
  Shown := True;
  Empty := False;
  Inc(ShowCount);
  Names := '';
  for Index in AOrder do
  begin
    if Names <> '' then
    begin
      Names := Names + ',';
    end;
    if TDpccRanking.IsHeader(Index) then
    begin
      Names := Names + '#';
    end
    else
    begin
      Names := Names + AItems[Index].Name;
    end;
  end;
  Selected := ASelected;
end;

procedure TFakeView.HideList;
begin
  Shown := False;
  Empty := False;
end;

procedure TFakeView.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
  Shown := False;
  Empty := True;
  EmptyText := Format('%s/%d', [APrefix, ATotal]);
end;

function TFakeView.PageSize: Integer;
begin
  Result := 3;
end;

type
  /// <summary>Liefert sofort zwei Einträge aus dem Präfix und meldet die Liste als gekürzt.</summary>
  TPrefixProvider = class(TInterfacedObject, IDpccCompletionProvider)
  public
    Queries: Integer;
    /// <summary>Liste vollständig melden (#616).</summary>
    CompleteList: Boolean;
    /// <summary>Jeden Eintrag als eigenes Teilergebnis liefern (#616).</summary>
    Staged: Boolean;
    /// <summary>Hinweis bei unvollständigem Code (#457); Sure = keiner.</summary>
    Syntax: TDpccSyntaxNotice;
    procedure Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
    procedure Cancel;
  end;

procedure TPrefixProvider.Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
var
  First, Second: TDpccCompletionItem;
begin
  Inc(Queries);
  First := Default(TDpccCompletionItem);
  First.Name := AContext.Prefix + '1';
  Second := Default(TDpccCompletionItem);
  Second.Name := AContext.Prefix + '2';
  if Staged then
  begin
    ASink.AddItems([First]);
    ASink.AddItems([Second]);
  end
  else
  begin
    ASink.AddItems([First, Second]);
  end;
  if not CompleteList then
  begin
    ASink.MarkIncomplete;
  end;
  if Syntax.Trust <> TDpccSyntaxTrust.Sure then
  begin
    ASink.MarkSyntax(Syntax);
  end;
  ASink.Complete;
end;

procedure TPrefixProvider.Cancel;
begin
end;

type
  /// <summary>Liefert die Teile Stages nacheinander als Teilergebnisse (#616), dann Complete.</summary>
  TStagedProvider = class(TInterfacedObject, IDpccCompletionProvider)
  public
    Queries: Integer;
    Stages: TArray<TDpccCompletionItems>;
    /// <summary>AItems als weiteres Teil anhängen.</summary>
    procedure Add(const AItems: TDpccCompletionItems);
    procedure Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
    procedure Cancel;
  end;

procedure TStagedProvider.Add(const AItems: TDpccCompletionItems);
begin
  SetLength(Stages, Length(Stages) + 1);
  Stages[High(Stages)] := AItems;
end;

procedure TStagedProvider.Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
var
  Index: Integer;
begin
  Inc(Queries);
  for Index := 0 to High(Stages) do
  begin
    ASink.AddItems(Stages[Index]);
  end;
  ASink.Complete;
end;

procedure TStagedProvider.Cancel;
begin
end;

type
  /// <summary>Merkt sich die Senke der letzten Abfrage; der Test liefert Teile und Complete selbst.</summary>
  TManualProvider = class(TInterfacedObject, IDpccCompletionProvider)
  public
    Sink: IDpccCompletionSink;
    procedure Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
    procedure Cancel;
  end;

procedure TManualProvider.Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
begin
  Sink := ASink;
end;

procedure TManualProvider.Cancel;
begin
end;

function Item(const AName: string; ARank: Integer = 0): TDpccCompletionItem;
begin
  Result := Default(TDpccCompletionItem);
  Result.Name := AName;
  Result.Rank := ARank;
end;

/// <summary>Eintrag AName aus AUnit mit Signatur ASignature.</summary>
function UnitItem(const AName, AUnit, ASignature: string; ARank: Integer): TDpccCompletionItem;
begin
  Result := Item(AName, ARank);
  Result.Kind := TDpccItemKind.Function_;
  Result.DeclaringUnit := AUnit;
  Result.Signature := ASignature;
end;

/// <summary>Namen der Einträge in der Reihenfolge der Liste (nicht der Anzeige), durch Komma getrennt.</summary>
function ItemNames(const AItems: TDpccCompletionItems): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AItems) do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + AItems[Index].Name;
  end;
end;

function Context(const APrefix: string): TDpccContext;
begin
  Result := Default(TDpccContext);
  Result.FileName := 'C:\P\A.pas';
  Result.Prefix := APrefix;
end;

/// <summary>Kontext mitten im Wort (Look-ahead): APrefix links, ARest rechts des Cursors.</summary>
function WordContext(const APrefix, ARest: string): TDpccContext;
begin
  Result := Context(APrefix);
  Result.Rest := ARest;
end;

/// <summary>Name des gewählten Eintrags; '' ohne Auswahl.</summary>
function SelectedName(AController: TDpccCompletionController): string;
var
  mItem: TDpccCompletionItem;
begin
  Result := '';
  if AController.SelectedItem(mItem) then
  begin
    Result := mItem.Name;
  end;
end;

/// <summary>Arbeitet eingereihte Aufrufe ab, bis ACondition gilt oder die Zeit um ist.</summary>
function WaitFor(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal = 3000): Boolean;
var
  Start: UInt64;
begin
  Start := TThread.GetTickCount64;
  repeat
    CheckSynchronize(5);
    if ACondition() then
    begin
      Exit(True);
    end;
  until TThread.GetTickCount64 - Start > ATimeoutMs;
  Result := False;
end;

/// <summary>Start an AContext und warten, bis die Abfrage fertig ist; False bei Zeitüberschreitung.</summary>
function StartAndWait(AController: TDpccCompletionController; const AContext: TDpccContext): Boolean;
begin
  AController.Start(AContext);
  Result := WaitFor(
    function: Boolean
    begin
      Result := not AController.Loading;
    end);
end;

{ TDpccCompletionMatcherTests }

procedure TDpccCompletionMatcherTests.RanksExactBeforePrefixBeforeWordStarts;
begin
  Assert.AreEqual(TDpccCompletionMatcher.cScoreExact, TDpccCompletionMatcher.Score('add', 'Add'));
  Assert.AreEqual(TDpccCompletionMatcher.cScorePrefixCase, TDpccCompletionMatcher.Score('Add', 'AddItem'));
  Assert.AreEqual(TDpccCompletionMatcher.cScorePrefix, TDpccCompletionMatcher.Score('add', 'AddItem'));
  Assert.AreEqual(TDpccCompletionMatcher.cScoreWordStarts, TDpccCompletionMatcher.Score('ai', 'AddItem'));
  Assert.AreEqual(TDpccCompletionMatcher.cScoreSubstring, TDpccCompletionMatcher.Score('dIt', 'AddItem'));
  Assert.AreEqual(TDpccCompletionMatcher.cNoMatch, TDpccCompletionMatcher.Score('xy', 'AddItem'));
end;

procedure TDpccCompletionMatcherTests.MatchesCamelCaseAndSubsequence;
begin
  Assert.AreEqual(TDpccCompletionMatcher.cScoreWordStarts, TDpccCompletionMatcher.Score('TSL', 'TStringList'));
  Assert.AreEqual(TDpccCompletionMatcher.cScoreWordStarts, TDpccCompletionMatcher.Score('gtc', 'Get_Tick_Count'));
  // Teilfolge nur an Wortgrenzen bzw. zusammenhängend.
  Assert.AreEqual(TDpccCompletionMatcher.cScoreSubsequence, TDpccCompletionMatcher.Score('stl', 'TStringList'));
  Assert.AreEqual(TDpccCompletionMatcher.cScoreSubsequence, TDpccCompletionMatcher.Score('', 'Beliebig'));
  // Verstreute Treffer sind Rauschen (Fall aus der IDE: "myLis" bei nicht deklariertem myList).
  Assert.AreEqual(TDpccCompletionMatcher.cNoMatch, TDpccCompletionMatcher.Score('myLis', 'ERROR_TOO_MANY_LINKS'));
  Assert.AreEqual(TDpccCompletionMatcher.cNoMatch, TDpccCompletionMatcher.Score('tsit', 'TStringList'));
end;

procedure TDpccCompletionMatcherTests.FiltersAndKeepsSourceOrderOnTies;
var
  Items: TDpccCompletionItems;
  Order: TArray<Integer>;
begin
  Items := [Item('Count', 2), Item('Capacity', 1), Item('Clear', 0), Item('Add', 3)];
  Order := TDpccCompletionMatcher.Filter(Items, 'c');
  // Alle drei beginnen mit c: Reihenfolge der Quelle (Rank).
  Assert.AreEqual(3, Integer(Length(Order)));
  Assert.AreEqual('Clear', Items[Order[0]].Name);
  Assert.AreEqual('Capacity', Items[Order[1]].Name);
  Assert.AreEqual('Count', Items[Order[2]].Name);
  Order := TDpccCompletionMatcher.Filter(Items, 'count');
  Assert.AreEqual('Count', Items[Order[0]].Name);
end;

{ TDpccCompletionControllerTests }

procedure TDpccCompletionControllerTests.ShowsItemsFilteredByPrefix;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('Add'), Item('Clear'), Item('Count')]) as IDpccCompletionProvider,
    ViewRef);
  try
    Controller.Start(Context('C'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(View.Shown);
    Assert.AreEqual('Clear,Count', View.Names);
    Assert.AreEqual(0, View.Selected);
    Assert.IsTrue(Controller.Visible);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.TypingRefiltersAndResetsSelection;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('Add'), Item('Clear'), Item('Count')]) as IDpccCompletionProvider,
    ViewRef);
  try
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('Add,Clear,Count', View.Names);
    Controller.HandleKey(TDpccNavigationKey.Down);
    Assert.AreEqual(1, View.Selected);
    Controller.UpdatePrefix('co');
    Assert.AreEqual('Count', View.Names);
    Assert.AreEqual(0, View.Selected);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.KeysMoveSelectionAndEnterCommits;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
  Committed: string;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('A1'), Item('A2'), Item('A3'), Item('A4'), Item('A5')])
      as IDpccCompletionProvider, ViewRef);
  try
    Committed := '';
    Controller.OnCommit :=
      procedure(const AItem: TDpccCompletionItem)
      begin
        Committed := AItem.Name;
      end;
    Controller.Start(Context('A'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.HandleKey(TDpccNavigationKey.Up));
    Assert.AreEqual(0, View.Selected, 'Oben bleibt oben');
    Controller.HandleKey(TDpccNavigationKey.PageDown);
    Assert.AreEqual(2, View.Selected, 'Bild ab um PageSize - 1');
    Controller.HandleKey(TDpccNavigationKey.Last);
    Assert.AreEqual(4, View.Selected);
    Controller.HandleKey(TDpccNavigationKey.First);
    Controller.HandleKey(TDpccNavigationKey.Down);
    Assert.IsTrue(Controller.HandleKey(TDpccNavigationKey.Accept));
    Assert.AreEqual('A2', Committed);
    Assert.IsFalse(Controller.Active, 'Übernahme schließt');
    Assert.IsFalse(View.Shown);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.EscapeClosesAndKeysPassThroughWhenClosed;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('Add')]) as IDpccCompletionProvider, ViewRef);
  try
    Assert.IsFalse(Controller.HandleKey(TDpccNavigationKey.Down), 'Geschlossen: Taste gehört dem Editor');
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.HandleKey(TDpccNavigationKey.Cancel));
    Assert.IsFalse(Controller.Active);
    Assert.IsFalse(View.Shown);
    Assert.IsFalse(Controller.HandleKey(TDpccNavigationKey.Accept), 'Enter nach Esc gehört dem Editor');
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.EscapeBlocksAutomaticReopenInSameWord;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
  Typed: TDpccContext;
begin
  // #414: Nach Esc öffnet Weitertippen im selben Wort nicht automatisch; Strg+Leer schon.
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('Add')]) as IDpccCompletionProvider, ViewRef);
  try
    Controller.Start(Context('A'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.HandleKey(TDpccNavigationKey.Cancel));
    Typed := Context('Ad');
    Typed.Character := Typed.Character + 1;
    Typed.Automatic := True;
    Assert.IsTrue(Controller.Dismissed(Typed));
    Controller.Start(Typed);
    Assert.IsFalse(Controller.Active, 'automatisch im selben Wort: bleibt zu');
    // Neues Wort: wieder automatisch.
    Typed.Character := Typed.Character + 5;
    Assert.IsFalse(Controller.Dismissed(Typed));
    // Strg+Leer im gesperrten Wort öffnet und hebt die Sperre auf.
    Typed := Context('Ad');
    Typed.Character := Typed.Character + 1;
    Controller.Start(Typed);
    Assert.IsTrue(Controller.Active, 'Strg+Leer öffnet');
    Controller.Close;
    Typed.Automatic := True;
    Assert.IsFalse(Controller.Dismissed(Typed), 'Schließen ohne Esc sperrt nicht');
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.NoMatchShowsEmptyState;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('Add'), Item('Clear')]) as IDpccCompletionProvider, ViewRef);
  try
    Controller.Start(Context('a'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    // #423: "Lines.Axq" zeigt den leeren Zustand, Rücktaste bis "Lines.A" wieder Treffer.
    Controller.UpdatePrefix('axq');
    Assert.IsTrue(View.Empty);
    Assert.AreEqual('axq/2', View.EmptyText);
    Assert.IsTrue(Controller.Active);
    Assert.IsFalse(Controller.HandleKey(TDpccNavigationKey.Accept), 'Ohne Treffer gehört Enter dem Editor');
    Assert.IsFalse(Controller.HandleKey(TDpccNavigationKey.Down), 'Ohne Treffer gehören Pfeile dem Editor');
    Controller.UpdatePrefix('a');
    Assert.IsTrue(View.Shown);
    Assert.IsFalse(View.Empty);
    Assert.AreEqual('Add,Clear', View.Names);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.EmptyResultShowsEmptyStateUntilEscape;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create(nil) as IDpccCompletionProvider, ViewRef);
  try
    Controller.Start(Context('mylist'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(View.Empty, 'Nichts gefunden: leerer Zustand statt Verschwinden');
    Assert.AreEqual('mylist/0', View.EmptyText);
    Assert.IsTrue(Controller.HandleKey(TDpccNavigationKey.Cancel), 'Esc schließt den leeren Zustand');
    Assert.IsFalse(Controller.Active);
    Assert.IsFalse(View.Empty);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.CommitCharacterOnlyForClearMatch;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
  Placeholders: TDpccCompletionItem;
begin
  View := TFakeView.Create;
  ViewRef := View;
  // Eintrag mit Platzhaltern (#51): nie über ein Zeichen übernommen.
  Placeholders := Item('while');
  Placeholders.PlaceholderText := 'while ${1:Condition} do';
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('Add'), Item('AddStrings'), Item('Exchange'), Placeholders])
      as IDpccCompletionProvider, ViewRef);
  try
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsFalse(Controller.CanCommitOnCharacter, 'Ohne getipptes Wort übernimmt ";" nichts');
    Controller.UpdatePrefix('A');
    Assert.IsTrue(Controller.CanCommitOnCharacter, '"Lines.A" + "(" ergibt "Lines.Add("');
    Controller.UpdatePrefix('as');
    Assert.IsTrue(Controller.CanCommitOnCharacter, 'Wortanfänge: AddStrings');
    Controller.UpdatePrefix('xch');
    Assert.IsFalse(Controller.CanCommitOnCharacter, 'Nur Teilstring von Exchange: Zeichen bleibt allein');
    Controller.UpdatePrefix('while');
    Assert.IsFalse(Controller.CanCommitOnCharacter, '"while(" setzt keine Vorlage ein');
  finally
    Controller.Free;
  end;
end;
procedure TDpccCompletionControllerTests.TypoSuggestionsTakeOnlyEnter;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
  Committed: string;
begin
  // #485, Abnahme: "Lenght" zeigt Length unter „Meintest du“ statt des leeren Zustands; ";" übernimmt
  // nichts, Enter übernimmt.
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('Length'), Item('Low'), Item('High')])
      as IDpccCompletionProvider, ViewRef);
  try
    Committed := '';
    Controller.OnCommit :=
      procedure(const AItem: TDpccCompletionItem)
      begin
        Committed := AItem.Name;
      end;
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Controller.UpdatePrefix('Lenght');
    Assert.IsFalse(View.Empty, 'Vorschläge statt des Hinweistexts');
    Assert.AreEqual('#,Length', View.Names);
    Assert.AreEqual(1, View.Selected, 'Überschrift wird übersprungen');
    Assert.IsFalse(Controller.CanCommitOnCharacter, '";" fügt nur das Zeichen ein');
    Assert.IsTrue(Controller.HandleKey(TDpccNavigationKey.Accept));
    Assert.AreEqual('Length', Committed);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.ItemsAfterCloseAreDropped;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('Spaet')], 100) as IDpccCompletionProvider, ViewRef);
  try
    Controller.Start(Context(''));
    Controller.Close;
    WaitFor(
      function: Boolean
      begin
        Result := False;
      end, 300);
    Assert.AreEqual(0, View.ShowCount);
    Assert.IsFalse(Controller.Active);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.TruncatedListIsRequeried;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Provider: TPrefixProvider;
  ProviderRef: IDpccCompletionProvider;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TPrefixProvider.Create;
  ProviderRef := Provider;
  Controller := TDpccCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('ab1,ab2', View.Names);
    Assert.IsTrue(Controller.Incomplete, 'Gekürzte Liste gemeldet');
    // #431: Weitertippen fragt neu, die neue Liste ersetzt die alte.
    Controller.Requery(Context('abc'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual(2, Provider.Queries);
    Assert.AreEqual('abc1,abc2', View.Names);
    Assert.IsTrue(View.Shown);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.SyntaxNoticeReachesView;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Provider: TPrefixProvider;
  ProviderRef: IDpccCompletionProvider;
  Controller: TDpccCompletionController;
begin
  // #457: Der Hinweis der Quelle geht an die Ansicht; die nächste Abfrage ohne Hinweis blendet ihn aus.
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TPrefixProvider.Create;
  Provider.Syntax.Trust := TDpccSyntaxTrust.Limited;
  Provider.Syntax.Line := 12;
  Provider.Syntax.Message := 'Ausdruck erwartet';
  ProviderRef := Provider;
  Controller := TDpccCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual(Ord(TDpccSyntaxTrust.Limited), Ord(Controller.Syntax.Trust));
    Assert.AreEqual(Ord(TDpccSyntaxTrust.Limited), Ord(View.Syntax.Trust));
    Assert.AreEqual(12, View.Syntax.Line);
    Assert.AreEqual('ab1,ab2', View.Names, 'Einträge bleiben');
    Provider.Syntax := Default(TDpccSyntaxNotice);
    Controller.Requery(Context('abc'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual(Ord(TDpccSyntaxTrust.Sure), Ord(Controller.Syntax.Trust));
    Assert.AreEqual(Ord(TDpccSyntaxTrust.Sure), Ord(View.Syntax.Trust));
    // Schließen setzt zurück.
    Provider.Syntax.Trust := TDpccSyntaxTrust.Unknown;
    Controller.Requery(Context('abcd'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual(Ord(TDpccSyntaxTrust.Unknown), Ord(Controller.Syntax.Trust));
    Controller.Close;
    Assert.AreEqual(Ord(TDpccSyntaxTrust.Sure), Ord(Controller.Syntax.Trust));
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.CompleteListFiltersLocallyUntilPrefixShrinks;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Provider: TPrefixProvider;
  ProviderRef: IDpccCompletionProvider;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TPrefixProvider.Create;
  Provider.CompleteList := True;
  ProviderRef := Provider;
  Controller := TDpccCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsFalse(Controller.Incomplete);
    // Der Server hat nach "ab" gefiltert: Weitertippen filtert lokal, kürzer oder anders fragt neu (#616).
    Assert.IsFalse(Controller.NeedsQuery('abc'));
    Assert.IsFalse(Controller.NeedsQuery('ABx'), 'Groß- und Kleinschreibung egal');
    Assert.IsTrue(Controller.NeedsQuery('a'));
    Assert.IsTrue(Controller.NeedsQuery('xb'));
    Controller.UpdatePrefix('ab1');
    Assert.AreEqual(1, Provider.Queries);
    // Lokal gefiltert; ab2 steht als Tippfehler-Kandidat unter „Meintest du“ (#485, # = Überschrift).
    Assert.AreEqual('ab1,#,ab2', View.Names);
    Controller.Close;
    Assert.IsFalse(Controller.NeedsQuery('a'), 'geschlossen');
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.PartialResultsReplaceThenAppend;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Provider: TPrefixProvider;
  ProviderRef: IDpccCompletionProvider;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TPrefixProvider.Create;
  Provider.Staged := True;
  ProviderRef := Provider;
  Controller := TDpccCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('ab1,ab2', View.Names);
    // Requery: Das erste Teil ersetzt die alte Liste, das zweite hängt an (#616).
    Controller.Requery(Context('a'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('a1,a2', View.Names);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.RequeryKeepsSelectedEntry;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(TPrefixProvider.Create as IDpccCompletionProvider, ViewRef);
  try
    Controller.Start(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Controller.HandleKey(TDpccNavigationKey.Down);
    Assert.AreEqual(1, View.Selected);
    // Neue Einträge verschieben die Auswahl nicht (#431).
    Controller.Requery(Context('ab'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('ab1,ab2', View.Names);
    Assert.AreEqual(1, View.Selected);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.OverlappingPartsAppearOnce;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Provider: TStagedProvider;
  ProviderRef: IDpccCompletionProvider;
  Controller: TDpccCompletionController;
  Items: TDpccCompletionItems;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TStagedProvider.Create;
  ProviderRef := Provider;
  // Eigener Bereich, dann uses (mit Wiederholung im selben Teil), dann die Endantwort mit Überschneidung.
  Provider.Add([Item('Anzahl', 0), Item('Berechne', 1)]);
  Provider.Add([Item('Berechne', 2), Item('Clear', 3), Item('Clear', 4)]);
  Provider.Add([Item('Anzahl', 5), Item('Dauer', 6)]);
  Controller := TDpccCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Items := Controller.Items;
    Assert.AreEqual('Anzahl,Berechne,Clear,Dauer', ItemNames(Items));
    // Der erste bleibt: Rang aus dem ersten Teil.
    Assert.AreEqual(1, Items[1].Rank, 'Berechne aus dem ersten Teil');
    Assert.AreEqual(3, Items[2].Rank, 'erstes Clear');
    Assert.AreEqual('Anzahl,Berechne,Clear,Dauer', View.Names);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.VariantsSurviveDeduplication;
var
  Dedup: TDpccCompletionDedup;
  Items, Kept: TDpccCompletionItems;
  Removed: Integer;
  Examples: TArray<string>;
  Conversion, SameName: TDpccCompletionItem;
begin
  Conversion := UnitItem('Count', 'Classes', 'Integer', 2);
  Conversion.Conversion := 'string';
  Conversion.ConvertFrom := 'Count';
  SameName := UnitItem('Count', 'Vcl.Controls', 'Integer', 3);
  SameName.SameNameOf := 'Classes';
  Items := [UnitItem('Count', 'Classes', 'Integer', 0),
    // Gleich bis auf die Schreibweise des Namens und die Quelle: derselbe Eintrag.
    UnitItem('count', 'classes', 'Integer', 1),
    Conversion, SameName,
    // Überladung mit anderer Signatur, falls eine Quelle sie einzeln liefert.
    UnitItem('Count', 'Classes', 'Integer; overload', 4)];
  Items[1].ResolveData := '{"file":"C:\\P2\\Classes.pas"}';
  Dedup := TDpccCompletionDedup.Create;
  try
    Kept := Dedup.Unique(Items, Removed, Examples);
    Assert.AreEqual(1, Removed);
    Assert.AreEqual(4, Integer(Length(Kept)));
    Assert.AreEqual(0, Kept[0].Rank, 'der erste bleibt');
    Assert.AreEqual('string', Kept[1].Conversion);
    Assert.AreEqual('Classes', Kept[2].SameNameOf);
    Assert.AreEqual('Integer; overload', Kept[3].Signature);
    Assert.AreEqual(1, Integer(Length(Examples)));
    Assert.AreEqual('count', Examples[0]);
    // Ein späterer Teil kennt die Schlüssel; Clear verwirft sie.
    Kept := Dedup.Unique([UnitItem('COUNT', 'Classes', 'Integer', 9)], Removed, Examples);
    Assert.AreEqual(0, Integer(Length(Kept)));
    Assert.AreEqual(1, Removed);
    Dedup.Clear;
    Assert.AreEqual(0, Dedup.Count);
    Kept := Dedup.Unique([UnitItem('COUNT', 'Classes', 'Integer', 9)], Removed, Examples);
    Assert.AreEqual(1, Integer(Length(Kept)));
    Assert.AreEqual(0, Removed);
  finally
    Dedup.Free;
  end;
end;

procedure TDpccCompletionControllerTests.RequeryReplacesAndDeduplicatesAnew;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Provider: TStagedProvider;
  ProviderRef: IDpccCompletionProvider;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TStagedProvider.Create;
  ProviderRef := Provider;
  Provider.Add([Item('Anzahl', 0), Item('Berechne', 1)]);
  Provider.Add([Item('Berechne', 2), Item('Clear', 3)]);
  Controller := TDpccCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('Anzahl,Berechne,Clear', ItemNames(Controller.Items));
    // Requery mit denselben Einträgen: Das erste Teil ersetzt die Liste, ohne gegen die alte abzugleichen; das
    // zweite hängt an, ohne Berechne zu wiederholen.
    Controller.Requery(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual(2, Provider.Queries);
    Assert.AreEqual('Anzahl,Berechne,Clear', ItemNames(Controller.Items));
    // Erstes Teil mit Wiederholung im Ersetzen-Pfad.
    Provider.Stages := nil;
    Provider.Add([Item('Dauer', 0), Item('Dauer', 1), Item('Anzahl', 2)]);
    Controller.Requery(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('Dauer,Anzahl', ItemNames(Controller.Items));
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.RemovedDuplicatesAreLogged;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Provider: TStagedProvider;
  ProviderRef: IDpccCompletionProvider;
  Controller: TDpccCompletionController;
  Lines: TStringList;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TStagedProvider.Create;
  ProviderRef := Provider;
  Provider.Add([Item('Geheim', 0), Item('Berechne', 1)]);
  Provider.Add([Item('Geheim', 2), Item('Clear', 3)]);
  Provider.Add([Item('Dauer', 4)]);
  Lines := TStringList.Create;
  Controller := TDpccCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.OnLog :=
      procedure(const AMessage: string)
      begin
        Lines.Add(AMessage);
      end;
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    // Nur das Teil mit Dublette schreibt eine Zeile, ohne Namen.
    Assert.AreEqual(1, Lines.Count, Lines.Text);
    Assert.AreEqual('Vervollständigung: 1 Dubletten entfernt', Lines[0]);
    Lines.Clear;
    Controller.LogNames := True;
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual(1, Lines.Count, Lines.Text);
    Assert.AreEqual('Vervollständigung: 1 Dubletten entfernt (z. B. Geheim)', Lines[0]);
  finally
    Controller.Free;
    Lines.Free;
  end;
end;

procedure TDpccCompletionControllerTests.LookAheadPreselectsWholeWord;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('StrToInt', 0), Item('Stream', 1), Item('string', 2)])
      as IDpccCompletionProvider, ViewRef);
  try
    // "Str|ing": string steht nach der Rangfolge hinten (andere Schreibweise), ist aber gewählt.
    Assert.IsTrue(StartAndWait(Controller, WordContext('Str', 'ing')));
    Assert.AreEqual('StrToInt,Stream,string', View.Names, 'Reihenfolge wie ohne Look-ahead');
    Assert.AreEqual(2, View.Selected);
    Assert.AreEqual('string', SelectedName(Controller));
    // "str|ing" wie in System.pas.
    Assert.IsTrue(StartAndWait(Controller, WordContext('str', 'ing')));
    Assert.AreEqual('string', SelectedName(Controller));
    // Groß- und Kleinschreibung egal.
    Assert.IsTrue(StartAndWait(Controller, WordContext('STR', 'ING')));
    Assert.AreEqual('string', SelectedName(Controller));
    // Kein Eintrag Präfix + Rest: gewöhnliche Vorauswahl.
    Assert.IsTrue(StartAndWait(Controller, WordContext('Str', 'xyz')));
    Assert.AreEqual('StrToInt,Stream,string', View.Names);
    Assert.AreEqual(0, View.Selected);
    // Ohne Rest wie bisher.
    Assert.IsTrue(StartAndWait(Controller, WordContext('Str', '')));
    Assert.AreEqual(0, View.Selected);
    Assert.AreEqual('StrToInt', SelectedName(Controller));
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.LookAheadFollowsLaterParts;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Provider: TStagedProvider;
  ProviderRef: IDpccCompletionProvider;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TStagedProvider.Create;
  ProviderRef := Provider;
  // Eigener Bereich ohne string, string erst mit den Schlüsselwörtern im letzten Teil.
  Provider.Add([Item('StrToInt', 0), Item('Stream', 1)]);
  Provider.Add([Item('string', 2)]);
  Controller := TDpccCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.Start(WordContext('Str', 'ing'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('StrToInt,Stream,string', View.Names);
    Assert.AreEqual('string', SelectedName(Controller));
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.LookAheadFollowsTypingAndKeepsOwnChoice;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create([Item('StrToInt', 0), Item('Stream', 1), Item('string', 2)])
      as IDpccCompletionProvider, ViewRef);
  try
    Controller.Start(WordContext('Str', 'ing'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('string', SelectedName(Controller));
    // Eigene Wahl mit der Pfeiltaste bleibt, auch wenn Entf den Rest ändert.
    Controller.HandleKey(TDpccNavigationKey.Up);
    Assert.AreEqual('Stream', SelectedName(Controller));
    Controller.UpdatePrefix('Str', 'ing');
    Assert.AreEqual('Stream', SelectedName(Controller), 'nichts geändert');
    Controller.UpdatePrefix('Str', 'in');
    Assert.AreEqual('Stream', SelectedName(Controller), 'nur der Rest geändert');
    // Weitertippen mitten im Wort: "Stri|in" passt zu keinem Eintrag, gewöhnliche Vorauswahl.
    Controller.UpdatePrefix('Stri', 'in');
    Assert.AreEqual(0, View.Selected);
    // Rücktaste und Rest "ing": wieder string, die eigene Wahl galt nur bis zur Änderung des Präfixes.
    Controller.UpdatePrefix('Str', 'ing');
    Assert.AreEqual('StrToInt,Stream,string', View.Names);
    Assert.AreEqual('string', SelectedName(Controller));
    // Entf löscht den Rest: ohne Rest wie bisher.
    Controller.UpdatePrefix('Str', '');
    Assert.AreEqual('StrToInt', SelectedName(Controller));
    // UpdatePrefix ohne Rest behält den bisherigen Rest.
    Controller.UpdatePrefix('Str', 'ing');
    Controller.UpdatePrefix('St');
    Assert.AreEqual('ing', Controller.WordRest);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.AutoSelectionFollowsLaterParts;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Provider: TManualProvider;
  ProviderRef: IDpccCompletionProvider;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TManualProvider.Create;
  ProviderRef := Provider;
  Controller := TDpccCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.Start(Context('strin'));
    Provider.Sink.AddItems([Item('TStringField', 0), Item('EStringListError', 1)]);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := Length(Controller.Items) = 2;
      end));
    Assert.AreEqual('TStringField', SelectedName(Controller), 'Vorauswahl des ersten Teils');
    // Das Schlüsselwort kommt später und steht oben: Die Vorauswahl folgt ihm.
    Provider.Sink.AddItems([Item('string', 2), Item('IStringsAdapter', 3)]);
    Provider.Sink.Complete;
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual(4, Integer(Length(Controller.Items)));
    Assert.AreEqual('string', SelectedName(Controller));
    Assert.AreEqual(0, View.Selected);
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.OwnChoiceSurvivesLaterParts;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Provider: TManualProvider;
  ProviderRef: IDpccCompletionProvider;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TManualProvider.Create;
  ProviderRef := Provider;
  Controller := TDpccCompletionController.Create(ProviderRef, ViewRef);
  try
    Controller.Start(Context('strin'));
    Provider.Sink.AddItems([Item('TStringField', 0), Item('EStringListError', 1)]);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := Length(Controller.Items) = 2;
      end));
    Assert.IsTrue(Controller.HandleKey(TDpccNavigationKey.Down));
    Assert.AreEqual('EStringListError', SelectedName(Controller));
    Provider.Sink.AddItems([Item('string', 2), Item('IStringsAdapter', 3)]);
    Provider.Sink.Complete;
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual(4, Integer(Length(Controller.Items)));
    Assert.AreEqual('EStringListError', SelectedName(Controller), 'eigene Wahl bleibt');
  finally
    Controller.Free;
  end;
end;

procedure TDpccCompletionControllerTests.RequeryKeepsOnlyOwnChoice;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Provider: TStagedProvider;
  ProviderRef: IDpccCompletionProvider;
  Controller: TDpccCompletionController;
begin
  View := TFakeView.Create;
  ViewRef := View;
  Provider := TStagedProvider.Create;
  ProviderRef := Provider;
  Controller := TDpccCompletionController.Create(ProviderRef, ViewRef);
  try
    // Ohne eigene Wahl: Die neue Liste bringt string, das vor TStringField steht.
    Provider.Add([Item('TStringField', 0), Item('EStringListError', 1)]);
    Assert.IsTrue(StartAndWait(Controller, Context('strin')));
    Assert.AreEqual('TStringField', SelectedName(Controller));
    Provider.Stages := nil;
    Provider.Add([Item('TStringField', 0), Item('EStringListError', 1), Item('string', 2)]);
    Controller.Requery(Context('strin'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('string', SelectedName(Controller), 'Vorauswahl der neuen Liste');
    // Mit eigener Wahl: derselbe Eintrag nach dem Ersetzen.
    Provider.Stages := nil;
    Provider.Add([Item('TStringField', 0), Item('EStringListError', 1)]);
    Assert.IsTrue(StartAndWait(Controller, Context('strin')));
    Assert.IsTrue(Controller.HandleKey(TDpccNavigationKey.Down));
    Assert.AreEqual('EStringListError', SelectedName(Controller));
    Provider.Stages := nil;
    Provider.Add([Item('TStringField', 0), Item('EStringListError', 1), Item('string', 2)]);
    Controller.Requery(Context('strin'));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('EStringListError', SelectedName(Controller), 'eigene Wahl bleibt');
  finally
    Controller.Free;
  end;
end;

{ TDpccCompletionTimingTests }

/// <summary>Zwei Quellen mit Namen: "Langsam" liefert nach ADelayMs, "Schnell" sofort.</summary>
function TimedProviders(ADelayMs: Cardinal): IDpccCompletionProvider;
var
  Providers: TDpccCompletionProviders;
  Slow, Fast: TDpccFixedCompletionProvider;
begin
  Providers := TDpccCompletionProviders.Create;
  Result := Providers;
  // Zeitlimit höher als die Verzögerung: Die Quelle liefert spät, wird aber nicht abgebrochen.
  Providers.TimeLimitMs := 2000;
  Slow := TDpccFixedCompletionProvider.Create([Item('Langsam1'), Item('Langsam2')], ADelayMs);
  Slow.Name := 'Langsam';
  Providers.Add(Slow);
  Fast := TDpccFixedCompletionProvider.Create([Item('Schnell')]);
  Fast.Name := 'Schnell';
  Providers.Add(Fast);
end;

procedure TDpccCompletionTimingTests.TearDown;
begin
  TDpccQueryTimings.Enabled := False;
  TDpccQueryTimings.Shared.Clear;
end;

procedure TDpccCompletionTimingTests.DelayedProviderIsOverBudget;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
  Start: TDpccContext;
  Queries: TArray<TDpccQueryTiming>;
  Rows: TArray<TDpccTimingRow>;
  Row: TDpccTimingRow;
  SlowWarn, FastSeen: Boolean;
begin
  TDpccQueryTimings.Shared.Clear;
  TDpccQueryTimings.Enabled := True;
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(TimedProviders(200), ViewRef);
  try
    Start := Context('');
    Start.Started := TDpccQueryTimings.Stamp;
    Controller.Start(Start);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
  finally
    Controller.Free;
  end;
  Queries := TDpccQueryTimings.Shared.Snapshot;
  Assert.AreEqual(1, Integer(Length(Queries)));
  Assert.AreEqual(2, Integer(Length(Queries[0].Providers)), 'beide Quellen mit Namen');
  Assert.IsTrue(Queries[0].ContextMs >= 0, 'Kontext gemessen');
  Assert.IsTrue(Queries[0].FilterSortSteps > 0, 'Filtern und Sortieren gemessen');
  Assert.IsTrue(Queries[0].FirstVisibleMs >= 0, 'erste Liste gemessen');
  Assert.AreEqual(3, Integer(Queries[0].Count));
  // Abnahme: Die Zeit des verzögerten Providers erscheint in Warnfarbe, die des schnellen nicht.
  Rows := TDpccTimingRows.Build(Queries);
  SlowWarn := False;
  FastSeen := False;
  for Row in Rows do
  begin
    if Row.Kind = TDpccTimingRowKind.Provider then
    begin
      if Row.Name = 'Langsam' then
      begin
        Assert.IsTrue(Row.Last >= 150, 'Verzögerung gemessen');
        SlowWarn := Row.LastWarn;
      end
      else if Row.Name = 'Schnell' then
      begin
        FastSeen := True;
        Assert.IsFalse(Row.LastWarn, 'schnelle Quelle im Budget');
      end;
    end;
  end;
  Assert.IsTrue(SlowWarn, 'verzögerte Quelle über dem Budget');
  Assert.IsTrue(FastSeen);
end;

procedure TDpccCompletionTimingTests.NoSourceTextInMeasurements;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
  Start: TDpccContext;
  Input: TDpccTimingReportInput;
  Report: string;
begin
  TDpccQueryTimings.Shared.Clear;
  TDpccQueryTimings.Enabled := True;
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(TimedProviders(0), ViewRef);
  try
    Start := Context('Lan');
    Start.FileName := 'C:\Users\Tester\Projekt\GeheimeUnit.pas';
    Start.Text := 'procedure GeheimerQuelltext; begin Lan end;';
    Controller.Start(Start);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
  finally
    Controller.Free;
  end;
  Input := Default(TDpccTimingReportInput);
  Input.DpccVersion := '1.0.0';
  Input.IdeVersion := '37.0';
  Input.Platform := 'Win64';
  Input.Settings := '{}';
  Input.Created := Now;
  // Abnahme: Der kopierte Bericht enthält keinen Quelltext und ohne Häkchen keinen Dateinamen.
  Report := TDpccTimingReport.Build(TDpccQueryTimings.Shared.Snapshot, Input);
  Assert.IsFalse(Report.Contains('GeheimerQuelltext'), 'kein Quelltext');
  Assert.IsFalse(Report.Contains('begin Lan'), 'kein Quelltext');
  Assert.IsFalse(Report.Contains('GeheimeUnit'), 'Dateiname nur auf Wunsch');
  Assert.IsFalse(Report.Contains('Tester'), 'kein Ordner');
  Input.FileNames := True;
  Report := TDpccTimingReport.Build(TDpccQueryTimings.Shared.Snapshot, Input);
  Assert.IsTrue(Report.Contains('GeheimeUnit.pas'), 'auf Wunsch der Dateiname');
  Assert.IsFalse(Report.Contains('Tester'), 'auch dann ohne Ordner');
  Assert.IsFalse(Report.Contains('GeheimerQuelltext'), 'auch dann kein Quelltext');
end;

procedure TDpccCompletionTimingTests.OffMeasuresNothing;
var
  View: TFakeView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
  Version: Integer;
begin
  // Abnahme: Mit diagnosticMode.enabled aus misst dpcc nichts; der Ablauf ist derselbe.
  TDpccQueryTimings.Shared.Clear;
  TDpccQueryTimings.Enabled := False;
  Version := TDpccQueryTimings.Shared.Version;
  View := TFakeView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(TimedProviders(0), ViewRef);
  try
    Controller.Start(Context(''));
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    // Beide Quellen liefern wie sonst; die Reihenfolge hängt davon ab, welche zuerst fertig ist.
    Assert.Contains(View.Names, 'Langsam1');
    Assert.Contains(View.Names, 'Schnell');
  finally
    Controller.Free;
  end;
  Assert.AreEqual(Version, TDpccQueryTimings.Shared.Version, 'keine Messung');
  Assert.AreEqual(0, Integer(Length(TDpccQueryTimings.Shared.Snapshot)));
end;

initialization  TDUnitX.RegisterTestFixture(TDpccCompletionMatcherTests);
  TDUnitX.RegisterTestFixture(TDpccCompletionControllerTests);
  TDUnitX.RegisterTestFixture(TDpccCompletionTimingTests);

end.
