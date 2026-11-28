unit dpcc.Core.Completion.AutoOpen.Tests;

// Tests für das Öffnen der Vervollständigung beim Tippen (L5, completion.autoMinChars, TDpccAutoOpen): unter der
// Schwelle keine Anfrage, ab der Schwelle genau eine; Strg+Leertaste bei jeder Länge; nach "." wie bisher; eine
// offene Liste filtert weiter; Einstellung 3 und 7; dazu das Erkennen eines getippten Zeichens und das Verhalten
// einer beim Tippen geöffneten Liste im Ablauf (still schließen ohne Einträge, Enter bei fertigem Wort). Seit CI-OPT
// öffnet "." nur mit „Nach dem Punkt automatisch öffnen“ (TDpccAutoOpen.TriggerAllowed).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccAutoOpenTests = class
  public
    [Test]
    procedure TypingBelowFiveLettersSendsNoQuery;
    [Test]
    procedure FifthLetterQueriesOnce;
    [Test]
    procedure CtrlSpaceQueriesAtAnyLength;
    [Test]
    procedure MemberListAfterDotUnchanged;
    [Test]
    procedure OpenListKeepsFiltering;
    [Test]
    procedure SettingThreeAndSeven;
    [Test]
    procedure SettingZeroNeverOpens;
    [Test]
    procedure NoTypingListInCommentsStringsAndNumbers;
    [Test]
    procedure NoTypingListInsideAWord;
    [Test]
    procedure TrackerSeesOneTypedCharacter;
    [Test]
    procedure TrackerIgnoresPasteCommitAndBackspace;
    [Test]
    procedure TypedListWithoutItemsClosesQuietly;
    [Test]
    procedure TypedCompleteWordLeavesEnterToEditor;
    [Test]
    procedure CtrlSpaceCompleteWordStillCommits;
    [Test]
    procedure SettingDefaultAndRange;
    /// <summary>CI-OPT: „.“ öffnet nur mit „Nach dem Punkt automatisch öffnen“; Strg+Leertaste (#0) und die übrigen
    /// Auslöser bleiben, wie sie sind; Vorgabe an.</summary>
    [Test]
    procedure DotOpensOnlyWithSetting;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Controller,
  dpcc.Core.Completion.AutoOpen,
  dpcc.Core.Settings.Plugin;

type
  TCountingView = class(TInterfacedObject, IDpccCompletionView)
  public
    Shown: Boolean;
    Empty: Boolean;
    Selected: Integer;
    procedure ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
  end;

  /// <summary>Liefert sofort feste Einträge und zählt die Anfragen samt Präfix der ersten.</summary>
  TCountingProvider = class(TInterfacedObject, IDpccCompletionProvider)
  public
    Items: TDpccCompletionItems;
    Queries: Integer;
    FirstPrefix: string;
    procedure Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
    procedure Cancel;
  end;

procedure TCountingView.ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
begin
  Shown := True;
  Empty := False;
  Selected := ASelected;
end;

procedure TCountingView.HideList;
begin
  Shown := False;
  Empty := False;
end;

procedure TCountingView.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
  Shown := False;
  Empty := True;
end;

function TCountingView.PageSize: Integer;
begin
  Result := 5;
end;

procedure TCountingProvider.Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
begin
  Inc(Queries);
  if Queries = 1 then
  begin
    FirstPrefix := AContext.Prefix;
  end;
  if Length(Items) > 0 then
  begin
    ASink.AddItems(Items);
  end;
  ASink.Complete;
end;

procedure TCountingProvider.Cancel;
begin
end;

function Item(const AName: string): TDpccCompletionItem;
begin
  Result := Default(TDpccCompletionItem);
  Result.Name := AName;
end;

function Context(const APrefix: string; ATyped: Boolean): TDpccContext;
begin
  Result := Default(TDpccContext);
  Result.FileName := 'C:\P\A.pas';
  Result.Line := 10;
  Result.Character := 4 + Length(APrefix);
  Result.Prefix := APrefix;
  Result.Automatic := ATyped;
  Result.Typed := ATyped;
end;

/// <summary>Arbeitet eingereihte Aufrufe ab, bis ACondition gilt oder die Zeit um ist.</summary>
function WaitFor(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal = 3000): Boolean;
var
  mStart: UInt64;
begin
  mStart := TThread.GetTickCount64;
  repeat
    CheckSynchronize(5);
    if ACondition() then
    begin
      Exit(True);
    end;
  until TThread.GetTickCount64 - mStart > ATimeoutMs;
  Result := False;
end;

procedure Settle(AController: TDpccCompletionController);
begin
  Assert.IsTrue(WaitFor(
    function: Boolean
    begin
      Result := not AController.Loading;
    end), 'Abfrage abgeschlossen');
end;

/// <summary>Tippt AWord Zeichen für Zeichen hinter ALead wie der Editor: je Zeichen die Entscheidung von
/// TDpccAutoOpen; Query startet eine Anfrage, Filter filtert die offene Liste weiter, None tut nichts.</summary>
procedure TypeWord(AController: TDpccCompletionController; const ALead, AWord: string; AMinChars: Integer);
var
  mIndex: Integer;
  mLine, mPrefix: string;
begin
  for mIndex := 1 to Length(AWord) do
  begin
    mPrefix := Copy(AWord, 1, mIndex);
    mLine := ALead + mPrefix;
    case TDpccAutoOpen.Action(TDpccCompletionSource.Typing, mLine, Length(mLine), AController.Active, AMinChars) of
      TDpccAutoOpenAction.Query:
        begin
          AController.Start(Context(mPrefix, True));
          Settle(AController);
        end;
      TDpccAutoOpenAction.Filter:
        AController.UpdatePrefix(mPrefix);
    end;
  end;
end;

function TypingAction(const ALine: string; AMinChars: Integer = 5): TDpccAutoOpenAction;
begin
  Result := TDpccAutoOpen.Action(TDpccCompletionSource.Typing, ALine, Length(ALine), False, AMinChars);
end;

{ TDpccAutoOpenTests }

procedure TDpccAutoOpenTests.TypingBelowFiveLettersSendsNoQuery;
var
  mLetters: Integer;
  mView: TCountingView;
  mViewRef: IDpccCompletionView;
  mProvider: TCountingProvider;
  mProviderRef: IDpccCompletionProvider;
  mController: TDpccCompletionController;
begin
  for mLetters := 0 to 4 do
  begin
    Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  x := ' + Copy('Strin', 1, mLetters))),
      IntToStr(mLetters) + ' Buchstaben');
  end;
  // Im Ablauf: vier Zeichen getippt, keine Anfrage und kein Popup.
  mView := TCountingView.Create;
  mViewRef := mView;
  mProvider := TCountingProvider.Create;
  mProviderRef := mProvider;
  mProvider.Items := [Item('StringReplace'), Item('StringOfChar')];
  mController := TDpccCompletionController.Create(mProviderRef, mViewRef);
  try
    TypeWord(mController, '  x := ', 'Stri', 5);
    Assert.AreEqual(0, mProvider.Queries);
    Assert.IsFalse(mController.Active);
    Assert.IsFalse(mView.Shown);
  finally
    mController.Free;
  end;
end;

procedure TDpccAutoOpenTests.FifthLetterQueriesOnce;
var
  mView: TCountingView;
  mViewRef: IDpccCompletionView;
  mProvider: TCountingProvider;
  mProviderRef: IDpccCompletionProvider;
  mController: TDpccCompletionController;
begin
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TypingAction('  x := Strin')));
  Assert.AreEqual(5, TDpccAutoOpen.TypedWord('  x := Strin', 12));
  mView := TCountingView.Create;
  mViewRef := mView;
  mProvider := TCountingProvider.Create;
  mProviderRef := mProvider;
  mProvider.Items := [Item('StringReplace'), Item('StringOfChar')];
  mController := TDpccCompletionController.Create(mProviderRef, mViewRef);
  try
    // Ab dem fünften Zeichen offen; die weiteren filtern, ohne neu zu fragen.
    TypeWord(mController, '  x := ', 'StringRe', 5);
    Assert.AreEqual(1, mProvider.Queries);
    Assert.AreEqual('Strin', mProvider.FirstPrefix);
    Assert.IsTrue(mController.Visible);
    Assert.AreEqual('StringRe', mController.Prefix);
    Assert.IsTrue(mController.Typed);
  finally
    mController.Free;
  end;
end;

procedure TDpccAutoOpenTests.CtrlSpaceQueriesAtAnyLength;
var
  mView: TCountingView;
  mViewRef: IDpccCompletionView;
  mProvider: TCountingProvider;
  mProviderRef: IDpccCompletionProvider;
  mController: TDpccCompletionController;
begin
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TDpccAutoOpen.Action(TDpccCompletionSource.Key, '  S', 3,
    False, 5)), 'ein Buchstabe');
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TDpccAutoOpen.Action(TDpccCompletionSource.Key, '  ', 2,
    False, 5)), 'ohne Buchstaben');
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TDpccAutoOpen.Action(TDpccCompletionSource.Key, '  S', 3,
    True, 5)), 'bei offener Liste neu');
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TDpccAutoOpen.Action(TDpccCompletionSource.Key, '  S', 3,
    False, 0)), 'auch wenn Tippen nie öffnet');
  // Im Ablauf: Strg+Leertaste bei "S" fragt sofort.
  mView := TCountingView.Create;
  mViewRef := mView;
  mProvider := TCountingProvider.Create;
  mProviderRef := mProvider;
  mProvider.Items := [Item('StringReplace'), Item('Self')];
  mController := TDpccCompletionController.Create(mProviderRef, mViewRef);
  try
    mController.Start(Context('S', False));
    Settle(mController);
    Assert.AreEqual(1, mProvider.Queries);
    Assert.AreEqual('S', mProvider.FirstPrefix);
    Assert.IsTrue(mController.Visible);
  finally
    mController.Free;
  end;
end;

procedure TDpccAutoOpenTests.MemberListAfterDotUnchanged;
begin
  // Tippen hinter "." öffnet nicht selbst (die Mitgliederliste kommt wie bisher über "."), auch über der Schwelle.
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  List.Strin')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  List.StringsAdd')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  for i := 0..Count')));
  // Der Punkt selbst (Auslösezeichen) fragt wie bisher, ohne Buchstaben.
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TDpccAutoOpen.Action(TDpccCompletionSource.Trigger,
    '  List.', 7, False, 5)));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TDpccAutoOpen.Action(TDpccCompletionSource.Trigger,
    '  List.', 7, False, 0)));
end;

procedure TDpccAutoOpenTests.OpenListKeepsFiltering;
var
  mLetters: Integer;
  mView: TCountingView;
  mViewRef: IDpccCompletionView;
  mProvider: TCountingProvider;
  mProviderRef: IDpccCompletionProvider;
  mController: TDpccCompletionController;
begin
  for mLetters := 1 to 7 do
  begin
    Assert.AreEqual(Ord(TDpccAutoOpenAction.Filter), Ord(TDpccAutoOpen.Action(TDpccCompletionSource.Typing,
      Copy('StringR', 1, mLetters), mLetters, True, 5)), IntToStr(mLetters) + ' Buchstaben');
  end;
  // Im Ablauf: mit Strg+Leertaste bei "S" geöffnet, Weitertippen filtert ohne neue Anfrage.
  mView := TCountingView.Create;
  mViewRef := mView;
  mProvider := TCountingProvider.Create;
  mProviderRef := mProvider;
  mProvider.Items := [Item('StringReplace'), Item('Self'), Item('StrToInt')];
  mController := TDpccCompletionController.Create(mProviderRef, mViewRef);
  try
    mController.Start(Context('S', False));
    Settle(mController);
    TypeWord(mController, '', 'StringR', 5);
    Assert.AreEqual(1, mProvider.Queries);
    Assert.AreEqual('StringR', mController.Prefix);
    Assert.IsTrue(mController.Visible);
    Assert.IsFalse(mController.Typed, 'Strg+Leertaste bleibt die Art der Liste');
  finally
    mController.Free;
  end;
end;

procedure TDpccAutoOpenTests.SettingThreeAndSeven;
begin
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  Fo', 3)));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TypingAction('  For', 3)));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  String', 7)));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TypingAction('  StringR', 7)));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TypingAction('  StringRe', 7)), 'darüber auch');
end;

procedure TDpccAutoOpenTests.SettingZeroNeverOpens;
begin
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  S', 0)));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  StringReplace', 0)));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  StringReplace', -1)));
end;

procedure TDpccAutoOpenTests.NoTypingListInCommentsStringsAndNumbers;
begin
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  // Strings')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  x := 1; // Strings')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  { Strings')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('{$IFDEF')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  (* Strings')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  s := ''Strings')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  s := ''it''''s Strings')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  x := $FFFFF')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  x := 12345')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  x := 1E10A')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  c := #13101')));
  // Nach geschlossenem Kommentar bzw. String wieder Code.
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TypingAction('  { x } Strin')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TypingAction('  (* x *) Strin')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TypingAction('  s := ''a'' + Strin')));
  // uses, raise und Attribut: dieselbe Schwelle, die Liste wählt der Server.
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('uses Syst')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TypingAction('uses Syste')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TypingAction('  raise EArg')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TypingAction('  raise EArgu')));
  Assert.AreEqual(Ord(TDpccAutoOpenAction.Query), Ord(TypingAction('  [TestC')));
end;

procedure TDpccAutoOpenTests.NoTypingListInsideAWord;
begin
  // Cursor nach "Strin" in "StringReplace": mitten im Wort.
  Assert.AreEqual(Ord(TDpccAutoOpenAction.None), Ord(TDpccAutoOpen.Action(TDpccCompletionSource.Typing,
    '  StringReplace', 7, False, 5)));
  Assert.AreEqual(5, TDpccAutoOpen.TypedWord('  Strin(', 7), 'Klammer dahinter ist kein Wort');
  Assert.AreEqual(0, TDpccAutoOpen.TypedWord('', 0));
  Assert.AreEqual(0, TDpccAutoOpen.TypedWord('  x := ', 7));
end;

procedure TDpccAutoOpenTests.TrackerSeesOneTypedCharacter;
var
  mTracker: TDpccTypingTracker;
begin
  mTracker := Default(TDpccTypingTracker);
  Assert.IsFalse(mTracker.Typed('A.pas', 3, 6, '  Stri'), 'ohne vorigen Stand');
  Assert.IsTrue(mTracker.Typed('A.pas', 3, 7, '  Strin'));
  Assert.IsFalse(mTracker.Typed('A.pas', 3, 7, '  Strin'), 'keine Änderung');
  Assert.IsTrue(mTracker.Typed('a.PAS', 3, 8, '  String'), 'Groß- und Kleinschreibung der Datei egal');
  // Mitten in der Zeile eingefügt.
  Assert.IsTrue(mTracker.Typed('A.pas', 3, 3, '  xString'));
  // Andere Zeile, andere Datei.
  Assert.IsFalse(mTracker.Typed('A.pas', 4, 1, 'a'));
  Assert.IsFalse(mTracker.Typed('B.pas', 4, 2, 'ab'));
  // Kein Bezeichnerzeichen.
  Assert.IsTrue(mTracker.Typed('B.pas', 4, 3, 'abc'));
  Assert.IsFalse(mTracker.Typed('B.pas', 4, 4, 'abc.'));
  Assert.IsFalse(mTracker.Typed('B.pas', 4, 5, 'abc. '));
end;

procedure TDpccAutoOpenTests.TrackerIgnoresPasteCommitAndBackspace;
var
  mTracker: TDpccTypingTracker;
begin
  mTracker := Default(TDpccTypingTracker);
  mTracker.Typed('A.pas', 1, 4, 'Stri');
  Assert.IsFalse(mTracker.Typed('A.pas', 1, 13, 'StringReplace'), 'eingefügt bzw. übernommen');
  Assert.IsFalse(mTracker.Typed('A.pas', 1, 12, 'StringReplac'), 'Rücktaste');
  // Cursor nicht hinter dem neuen Zeichen (etwa Rückgängig an anderer Stelle).
  Assert.IsFalse(mTracker.Typed('A.pas', 1, 2, 'StringReplacX'));
  mTracker.Reset;
  Assert.IsFalse(mTracker.Typed('A.pas', 1, 14, 'StringReplacXY'), 'nach Reset zählt die erste Änderung nicht');
  Assert.IsTrue(mTracker.Typed('A.pas', 1, 15, 'StringReplacXYZ'));
end;

procedure TDpccAutoOpenTests.TypedListWithoutItemsClosesQuietly;
var
  mView: TCountingView;
  mViewRef: IDpccCompletionView;
  mProvider: TCountingProvider;
  mProviderRef: IDpccCompletionProvider;
  mController: TDpccCompletionController;
begin
  mView := TCountingView.Create;
  mViewRef := mView;
  mProvider := TCountingProvider.Create;
  mProviderRef := mProvider;
  mController := TDpccCompletionController.Create(mProviderRef, mViewRef);
  try
    // Beim Tippen ohne Einträge (etwa in einem mehrzeiligen Kommentar): still zu, kein leerer Zustand.
    mController.Start(Context('Strin', True));
    Settle(mController);
    Assert.IsFalse(mController.Active);
    Assert.IsFalse(mView.Empty);
    Assert.IsFalse(mView.Shown);
    // Mit Strg+Leertaste bleibt der leere Zustand (#423).
    mController.Start(Context('Strin', False));
    Settle(mController);
    Assert.IsTrue(mController.Active);
    Assert.IsTrue(mView.Empty);
  finally
    mController.Free;
  end;
end;

procedure TDpccAutoOpenTests.TypedCompleteWordLeavesEnterToEditor;
var
  mView: TCountingView;
  mViewRef: IDpccCompletionView;
  mProvider: TCountingProvider;
  mProviderRef: IDpccCompletionProvider;
  mController: TDpccCompletionController;
  mCommitted: string;
begin
  mView := TCountingView.Create;
  mViewRef := mView;
  mProvider := TCountingProvider.Create;
  mProviderRef := mProvider;
  mProvider.Items := [Item('begin'), Item('BeginUpdate')];
  mController := TDpccCompletionController.Create(mProviderRef, mViewRef);
  try
    mCommitted := '';
    mController.OnCommit :=
      procedure(const AItem: TDpccCompletionItem)
      begin
        mCommitted := AItem.Name;
      end;
    // "begin" getippt: nichts zu ergänzen, Enter bricht die Zeile um.
    mController.Start(Context('begin', True));
    Settle(mController);
    Assert.IsTrue(mController.Passive);
    Assert.AreEqual(-1, mView.Selected, 'nichts gewählt');
    Assert.IsFalse(mController.HandleKey(TDpccNavigationKey.Accept), 'Enter gehört dem Editor');
    Assert.AreEqual('', mCommitted);
    Assert.IsFalse(mController.Active);
    // Pfeiltaste wählt, dann übernimmt Enter.
    mController.Start(Context('beginU', True));
    Settle(mController);
    Assert.IsFalse(mController.Passive, 'Anfang eines längeren Namens: gewählt');
    mController.UpdatePrefix('begin');
    Assert.IsTrue(mController.Passive);
    mController.HandleKey(TDpccNavigationKey.Down);
    Assert.IsFalse(mController.Passive);
    Assert.IsTrue(mController.HandleKey(TDpccNavigationKey.Accept));
    Assert.AreEqual('begin', mCommitted);
  finally
    mController.Free;
  end;
end;

procedure TDpccAutoOpenTests.CtrlSpaceCompleteWordStillCommits;
var
  mView: TCountingView;
  mViewRef: IDpccCompletionView;
  mProvider: TCountingProvider;
  mProviderRef: IDpccCompletionProvider;
  mController: TDpccCompletionController;
  mCommitted: string;
begin
  mView := TCountingView.Create;
  mViewRef := mView;
  mProvider := TCountingProvider.Create;
  mProviderRef := mProvider;
  mProvider.Items := [Item('begin'), Item('BeginUpdate')];
  mController := TDpccCompletionController.Create(mProviderRef, mViewRef);
  try
    mCommitted := '';
    mController.OnCommit :=
      procedure(const AItem: TDpccCompletionItem)
      begin
        mCommitted := AItem.Name;
      end;
    mController.Start(Context('begin', False));
    Settle(mController);
    Assert.IsFalse(mController.Passive);
    Assert.IsTrue(mController.HandleKey(TDpccNavigationKey.Accept));
    Assert.AreEqual('begin', mCommitted);
  finally
    mController.Free;
  end;
end;

procedure TDpccAutoOpenTests.SettingDefaultAndRange;
var
  mSettings: TDpccPluginSettings;
begin
  Assert.AreEqual(Integer(TDpccAutoOpen.cDefaultMinChars), Integer(TDpccPluginSettings.cDefaultAutoMinChars));
  Assert.AreEqual(Integer(TDpccAutoOpen.cMaxMinChars), Integer(TDpccPluginSettings.cMaxAutoMinChars));
  // Vorgabe 0 = aus (Entscheidung des Nutzers nach L5, vorher 5); einschaltbar bis 10.
  Assert.AreEqual(0, TDpccPluginSettings.Defaults.AutoMinChars);
  Assert.AreEqual(0, Integer(TDpccAutoOpen.cDefaultMinChars));
  Assert.IsTrue(TDpccAutoOpen.Action(TDpccCompletionSource.Typing, '  Anfang', Length('  Anfang'), False,
    TDpccPluginSettings.Defaults.AutoMinChars) = TDpccAutoOpenAction.None, 'Vorgabe: Tippen öffnet nie');
  mSettings := TDpccPluginSettings.Defaults;
  mSettings.AutoMinChars := -3;
  mSettings.Normalize;
  Assert.AreEqual(0, mSettings.AutoMinChars);
  mSettings.AutoMinChars := 99;
  mSettings.Normalize;
  Assert.AreEqual(10, mSettings.AutoMinChars);
  mSettings.AutoMinChars := 7;
  mSettings.Normalize;
  Assert.AreEqual(7, mSettings.AutoMinChars);
end;

procedure TDpccAutoOpenTests.DotOpensOnlyWithSetting;
const
  cOthers = #0#1#2#3'(,<[;{''';
var
  mChar: Char;
begin
  Assert.IsTrue(TDpccPluginSettings.Defaults.OpenAfterDot, 'Vorgabe an');
  Assert.IsTrue(TDpccAutoOpen.TriggerAllowed('.', True), 'an: nach „.“');
  Assert.IsFalse(TDpccAutoOpen.TriggerAllowed('.', False), 'aus: nicht nach „.“');
  // Strg+Leertaste (#0), Parameterhilfe (#1), Browse (#2), Symbolhinweis (#3) und die übrigen Auslöser bleiben.
  for mChar in cOthers do
  begin
    Assert.IsTrue(TDpccAutoOpen.TriggerAllowed(mChar, False), 'aus: #' + IntToStr(Ord(mChar)));
    Assert.IsTrue(TDpccAutoOpen.TriggerAllowed(mChar, True), 'an: #' + IntToStr(Ord(mChar)));
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccAutoOpenTests);

end.
