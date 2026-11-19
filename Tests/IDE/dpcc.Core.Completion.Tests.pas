unit dpcc.Core.Completion.Tests;

// Tests der Datenquellen der Vervollständigung (#408).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccCompletionProviderTests = class
  public
    [Test]
    procedure MapsLspCompletionList;
    [Test]
    procedure ReadsTextEditOfPostfixItems;
    [Test]
    procedure ReadsScopeUnitAndHiddenNames;
    [Test]
    procedure ReadsAnonymousMethodItems;
    [Test]
    procedure ReadsRaiseItems;
    [Test]
    procedure ReadsSyntaxNotice;
    [Test]
    procedure ReadsItemArrayAndNull;
    [Test]
    procedure PartialItemsContinueRank;
    [Test]
    procedure ServerItemsUsePlaceholderMode;
    [Test]
    procedure ReadsResolvedDetails;
    [Test]
    procedure MergesProvidersAndCompletesOnce;
    [Test]
    procedure CancelDropsLateItems;
    [Test]
    procedure NewQueryReplacesRunningQuery;
    [Test]
    procedure WithoutSessionCompletesEmpty;
  end;

  /// <summary>Zusammenführen ohne Warten (perf1): Query kehrt sofort zurück, Quellen laufen auf Arbeitern.</summary>
  [TestFixture]
  TDpccCompositeNoWaitTests = class
  public
    /// <summary>Sicherung und Arbeiter vor der Leckmessung (die Sicherung merkt sich langsame Quellen).</summary>
    [SetupFixture]
    procedure WarmUp;
    /// <summary>Eine Quelle, die 400 ms blockiert, hält Query nicht auf; ihre Einträge kommen danach.</summary>
    [Test]
    procedure QueryReturnsBeforeSlowSource;
    /// <summary>Läuft der vorige Aufruf noch (im Zeitlimit), startet die neueste Abfrage gleich danach; nie zwei
    /// Aufrufe einer Quelle zugleich.</summary>
    [Test]
    procedure LatestQueryRunsAfterRunningCall;
    /// <summary>Hängt eine Quelle über das Zeitlimit, ist ihr Teil fertig; die nächste Abfrage überspringt sie.
    /// </summary>
    [Test]
    procedure HangingSourceIsAbandonedAndSkipped;
  end;

  [TestFixture]
  TDpccServerCompletionTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    // Startet den echten Server im eigenen Prozess (wie das Plugin, seit S1 der einzige Betrieb).
    [Test]
    procedure CompletesMembersFromServer;
  end;

  /// <summary>XMLDoc-Tags in ///-Kommentaren (#435).</summary>
  [TestFixture]
  TDpccItemDetailsTests = class
  public
    /// <summary>Ein Hinweis zur Verfügbarkeit allein füllt das Panel (#476).</summary>
    [Test]
    procedure AvailabilityAloneIsNotEmpty;
  end;

  [TestFixture]
  TDpccXmlDocTests = class
  public
    [Test]
    procedure RecognizesTagContext;
    [Test]
    procedure OffersParamsOfFollowingMethod;
  end;

  /// <summary>Zeitbudget (#409): Filtern und Sortieren beim Weitertippen.</summary>
  [TestFixture]
  TDpccMatchingBudgetTests = class
  public
    [Test]
    procedure CommitTextFixesCase;
    [Test]
    procedure AnnouncementNamesKindPositionAndDetail;
    [Test]
    procedure TagTextNamesStatesInWords;
    [Test]
    procedure TyposAppearUnderDidYouMean;
    [Test]
    procedure CommitTextKeepsTypedCaseWhenOff;
    [Test]
    [Category('Benchmark')]
    procedure Filters5000EntriesWithin12ms;
    /// <summary>Mit dem Rest der Liste (#497) bleibt ein Filterschritt unter 16 ms (#409).</summary>
    [Test]
    [Category('Benchmark')]
    procedure Orders5000EntriesWithRestWithin16ms;
  end;

  /// <summary>Schlichte Zeile der Liste (S6) wie die Code-Insight-Liste der IDE: Art als Wort, Rest der Signatur
  /// hinter dem Namen bzw. Detail, rechts nur „+ Unit“ und Warnungen.</summary>
  [TestFixture]
  TDpccPlainRowTests = class
  public
    [Test]
    procedure KindWordsLikeIdeList;
    [Test]
    procedure ParamsFollowName;
    [Test]
    procedure DetailWhenSignatureHasNoName;
    [Test]
    procedure TrailerKeepsUnitAndWarnings;
  end;

  [TestFixture]
  TDpccWordTests = class
  public
    [Test]
    procedure FindsStartBeforeCursor;
    [Test]
    procedure FindsEndBehindCursorInsideWord;
    [Test]
    procedure EndStaysAtCursorWithoutWordBehind;
    [Test]
    procedure DetectsDataNameStrings;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Composite,
  dpcc.Core.Completion.Providers.Fixed,
  dpcc.Core.Completion.Providers.Server,
  dpcc.Core.Completion.Word,
  dpcc.Core.Completion.Matching,
  dpcc.Core.Completion.Presentation,
  dpcc.Core.Completion.Ranking,
  dpcc.Core.Completion.Providers.XmlDoc,
  System.Diagnostics,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.Adapters.InProcess;

type
  /// <summary>Sammelt Einträge aus beliebigen Threads und meldet Complete über ein Ereignis.</summary>
  TCollectingSink = class(TInterfacedObject, IDpccCompletionSink)
  private
    FLock: TCriticalSection;
    FNames: TList<string>;
    FCompleted: Integer;
    FDone: TEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddItems(const AItems: TDpccCompletionItems);
    procedure MarkIncomplete;
    procedure MarkSyntax(const ANotice: TDpccSyntaxNotice);
    procedure Complete;
    function WaitDone(ATimeoutMs: Cardinal): Boolean;
    function Names: string;
    function Completed: Integer;
  end;

constructor TCollectingSink.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FNames := TList<string>.Create;
  FDone := TEvent.Create(nil, True, False, '');
end;

destructor TCollectingSink.Destroy;
begin
  FDone.Free;
  FNames.Free;
  FLock.Free;
  inherited;
end;

procedure TCollectingSink.AddItems(const AItems: TDpccCompletionItems);
var
  Item: TDpccCompletionItem;
begin
  FLock.Enter;
  try
    for Item in AItems do
    begin
      FNames.Add(Item.Name);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TCollectingSink.MarkIncomplete;
begin
end;

procedure TCollectingSink.MarkSyntax(const ANotice: TDpccSyntaxNotice);
begin
end;

procedure TCollectingSink.Complete;
begin
  TInterlocked.Increment(FCompleted);
  FDone.SetEvent;
end;

function TCollectingSink.WaitDone(ATimeoutMs: Cardinal): Boolean;
begin
  Result := FDone.WaitFor(ATimeoutMs) = wrSignaled;
end;

function TCollectingSink.Names: string;
var
  List: TArray<string>;
begin
  FLock.Enter;
  try
    List := FNames.ToArray;
  finally
    FLock.Leave;
  end;
  TArray.Sort<string>(List);
  Result := string.Join(',', List);
end;

function TCollectingSink.Completed: Integer;
begin
  Result := TInterlocked.CompareExchange(FCompleted, 0, 0);
end;

function Item(const AName: string): TDpccCompletionItem;
begin
  Result := Default(TDpccCompletionItem);
  Result.Name := AName;
end;

function Context: TDpccContext;
begin
  Result := Default(TDpccContext);
  Result.FileName := 'C:\P\A.pas';
end;

{ TDpccCompletionProviderTests }

procedure TDpccCompletionProviderTests.ReadsTextEditOfPostfixItems;
var
  Response: TJSONValue;
  Items: TDpccCompletionItems;
begin
  // Liste.for (#188): ersetzt ab dem Anfang von "Liste" bis zum Cursor.
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[{"label":"for","kind":15,"filterText":"Liste.for",' +
    '"textEdit":{"range":{"start":{"line":7,"character":2},"end":{"line":7,"character":10}},' +
    '"newText":"for var Item in Liste do\n    "},"data":{"action":"postfix"}},{"label":"Count","kind":10},' +
    '{"label":"notnil","kind":15,"filterText":"Wert.notnil","insertTextFormat":2,' +
    '"textEdit":{"range":{"start":{"line":7,"character":2},"end":{"line":7,"character":13}},' +
    '"newText":"if Assigned(Wert) then\n    $0"},"data":{"action":"postfix"}}]}');
  try
    Items := TDpccServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  // Gefiltert wird über das Kürzel hinter dem Punkt.
  Assert.IsTrue(Items[0].Postfix);
  Assert.AreEqual('for', Items[0].FilterText);
  Assert.IsFalse(Items[1].Postfix);
  Assert.AreEqual('notnil', Items[2].FilterText);
  Assert.AreEqual('if Assigned(Wert) then'#10'    $0', Items[2].PlaceholderText);
  Assert.AreEqual(Ord(TDpccItemKind.Snippet), Ord(Items[0].Kind));
  Assert.IsTrue(Items[0].HasTextEdit);
  Assert.AreEqual(7, Items[0].TextEdit.StartLine);
  Assert.AreEqual(2, Items[0].TextEdit.StartCharacter);
  Assert.AreEqual(10, Items[0].TextEdit.EndCharacter);
  Assert.AreEqual('for var Item in Liste do'#10'    ', Items[0].TextEdit.NewText);
  Assert.IsFalse(Items[1].HasTextEdit);
end;

procedure TDpccCompletionProviderTests.ReadsAnonymousMethodItems;
var
  Response: TJSONValue;
  Items: TDpccCompletionItems;
begin
  // #468: Typ als methodRef; das Gerüst kommt mit Platzhaltern (insertTextFormat 2).
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"procedure","kind":15,"insertTextFormat":2,' +
    '"textEdit":{"range":{"start":{"line":3,"character":12},"end":{"line":3,"character":12}},' +
    '"newText":"procedure\n  begin\n    $0\n  end"},"data":{"methodRef":"TProc","action":"anonymous"}}]}');
  try
    Items := TDpccServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual('TProc', Items[0].MethodRef);
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.AreEqual('procedure'#10'  begin'#10'    $0'#10'  end', Items[0].PlaceholderText);
end;

procedure TDpccCompletionProviderTests.ReadsSyntaxNotice;
var
  Response: TJSONValue;
  Notice: TDpccSyntaxNotice;
begin
  // #457: syntaxNotice der CompletionList; ohne Angabe sicher.
  Response := TJSONObject.ParseJSONValue('{"isIncomplete":false,"items":[],"syntaxNotice":' +
    '{"trust":"unknown","line":13,"character":12,"message":"Ausdruck erwartet"}}');
  try
    Notice := TDpccServerCompletionProvider.SyntaxNoticeOf(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(Ord(TDpccSyntaxTrust.Unknown), Ord(Notice.Trust));
  Assert.AreEqual(13, Notice.Line);
  Assert.AreEqual(12, Notice.Character);
  Assert.AreEqual('Ausdruck erwartet', Notice.Message);
  Response := TJSONObject.ParseJSONValue('{"isIncomplete":false,"items":[]}');
  try
    Notice := TDpccServerCompletionProvider.SyntaxNoticeOf(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(Ord(TDpccSyntaxTrust.Sure), Ord(Notice.Trust));
  Assert.AreEqual(-1, Notice.Line);
end;

procedure TDpccCompletionProviderTests.ReadsRaiseItems;
var
  Response: TJSONValue;
  Items: TDpccCompletionItems;
begin
  // #483: Gruppe und Reihenfolge-Warnung aus data; nach raise "EFoo.Create('$0')" mit Endposition.
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"EAppError","kind":7,"insertTextFormat":2,' +
    '"textEdit":{"range":{"start":{"line":3,"character":8},"end":{"line":3,"character":8}},' +
    '"newText":"EAppError.Create(''$0'')"},"data":{"exceptionGroup":"raise"}},' +
    '{"label":"EConvertError","kind":7,"data":{"exceptionGroup":"general","unreachable":"Exception"}}]}');
  try
    Items := TDpccServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual('raise', Items[0].ExceptionGroup);
  Assert.AreEqual('general', Items[1].ExceptionGroup);
  Assert.AreEqual('Exception', Items[1].Unreachable);
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual('EAppError.Create(''$0'')', Items[0].PlaceholderText);
  Assert.AreEqual('', Items[1].PlaceholderText);
end;

procedure TDpccCompletionProviderTests.ReadsScopeUnitAndHiddenNames;
var
  Response: TJSONValue;
  Items: TDpccCompletionItems;
begin
  // #488: Bereichsstufe, Unit bei Stufe 5 und verdeckte Deklarationen.
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"Name","kind":6,"data":{"scope":1,"hides":["Feld TFoo.Name","Werkzeug.Name"]}},' +
    '{"label":"Rechne","kind":3,"data":{"scope":5,"unit":"Werkzeug"}}]}');
  try
    Items := TDpccServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(1, Items[0].Scope);
  Assert.AreEqual(2, Integer(Length(Items[0].Hides)));
  Assert.AreEqual('Feld TFoo.Name', Items[0].Hides[0]);
  Assert.AreEqual('Werkzeug.Name', Items[0].Hides[1]);
  Assert.AreEqual(5, Items[1].Scope);
  Assert.AreEqual('Werkzeug', Items[1].DeclaringUnit);
  Assert.AreEqual(0, Integer(Length(Items[1].Hides)));
end;

procedure TDpccCompletionProviderTests.MapsLspCompletionList;
var
  Response: TJSONValue;
  Items: TDpccCompletionItems;
begin
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"Add","kind":2,"detail":"function Add(const S: string): Integer",' +
    '"documentation":{"kind":"plaintext","value":"Hängt S an."},' +
    '"additionalTextEdits":[{"range":{"start":{"line":2,"character":5},"end":{"line":2,"character":5}},' +
    '"newText":", System.Classes"}]},' +
    '{"label":"TFoo","kind":7,"documentation":"Klasse"}]}');
  try
    Items := TDpccServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual('Add', Items[0].Name);
  Assert.AreEqual(Ord(TDpccItemKind.Method), Ord(Items[0].Kind));
  Assert.AreEqual('function Add(const S: string): Integer', Items[0].Signature);
  Assert.AreEqual('Hängt S an.', Items[0].Documentation);
  Assert.AreEqual(1, Integer(Length(Items[0].AdditionalEdits)));
  Assert.AreEqual(2, Items[0].AdditionalEdits[0].StartLine);
  Assert.AreEqual(5, Items[0].AdditionalEdits[0].EndCharacter);
  Assert.AreEqual(', System.Classes', Items[0].AdditionalEdits[0].NewText);
  Assert.IsFalse(Items[0].UnitUsed, 'Eintrag mit uses-Ergänzung');
  Assert.AreEqual(Ord(TDpccItemKind.Class_), Ord(Items[1].Kind));
  Assert.AreEqual('Klasse', Items[1].Documentation);
  Assert.IsTrue(Items[1].UnitUsed);
  Assert.AreEqual(1, Items[1].Rank);
end;

procedure TDpccCompletionProviderTests.ServerItemsUsePlaceholderMode;
var
  Response: TJSONValue;
  Items: TDpccCompletionItems;
begin
  // Eintrag des Servers mit insertTextFormat 2 (#51): Text mit Platzhaltern für den Platzhalter-Modus,
  // die Setter-Änderungen sind keine uses-Ergänzung.
  Response := TJSONObject.ParseJSONValue(
    '{"isIncomplete":false,"items":[' +
    '{"label":"prop Farbe","kind":15,"insertTextFormat":2,"data":{"action":"snippet"},' +
    '"textEdit":{"range":{"start":{"line":9,"character":4},"end":{"line":9,"character":7}},' +
    '"newText":"property ${1:Farbe}: TColor read FFarbe write SetFarbe;$0"},' +
    '"additionalTextEdits":[{"range":{"start":{"line":10,"character":0},"end":{"line":10,"character":0}},' +
    '"newText":"  private\n    procedure SetFarbe(const Value: TColor);\n"}]},' +
    '{"label":"Farbe","kind":5,"insertText":"Farbe"}]}');
  try
    Items := TDpccServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual(Ord(TDpccItemKind.Snippet), Ord(Items[0].Kind));
  Assert.AreEqual('property ${1:Farbe}: TColor read FFarbe write SetFarbe;$0', Items[0].PlaceholderText);
  Assert.IsTrue(Items[0].HasTextEdit);
  Assert.AreEqual(4, Items[0].TextEdit.StartCharacter);
  Assert.AreEqual(1, Integer(Length(Items[0].AdditionalEdits)));
  Assert.IsTrue(Items[0].UnitUsed, 'Keine uses-Ergänzung');
  Assert.AreEqual('', Items[1].PlaceholderText);
end;

procedure TDpccCompletionProviderTests.PartialItemsContinueRank;
var
  Response: TJSONValue;
  Items: TDpccCompletionItems;
begin
  // Teilergebnis als CompletionItem[] (#616): Rang zählt ab dem ersten Eintrag dieses Teils.
  Response := TJSONObject.ParseJSONValue('[{"label":"A","kind":6},5,{"label":"B","kind":6}]');
  try
    Items := TDpccServerCompletionProvider.ItemsFromLsp(Response, 10);
  finally
    Response.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Items)), 'Nicht-Objekte übersprungen');
  Assert.AreEqual('B', Items[1].Name);
  Assert.AreEqual(10, Items[0].Rank);
  Assert.AreEqual(12, Items[1].Rank);
end;

procedure TDpccCompletionProviderTests.ReadsItemArrayAndNull;
var
  Response: TJSONValue;
begin
  Response := TJSONObject.ParseJSONValue('[{"label":"A"},{"label":"B","kind":99,"filterText":"mylist"}]');
  try
    Assert.AreEqual(2, Integer(Length(TDpccServerCompletionProvider.ItemsFromLsp(Response))));
    Assert.AreEqual(Ord(TDpccItemKind.Unknown),
      Ord(TDpccServerCompletionProvider.ItemsFromLsp(Response)[1].Kind));
    // Der filterText des Servers ist das getippte Wort (für VS Code); dpcc filtert gegen den Namen.
    Assert.AreEqual('', TDpccServerCompletionProvider.ItemsFromLsp(Response)[1].FilterText);
  finally
    Response.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TDpccServerCompletionProvider.ItemsFromLsp(nil))));
end;

/// <summary>Mitglied eines Helpers (#456) und Angaben anderer Server.</summary>
procedure AssertHelperAndForeignDetails;
var
  mResponse: TJSONValue;
  mDetails: TDpccItemDetails;
begin
  // Mitglied eines Helpers (#456).
  mResponse := TJSONObject.ParseJSONValue('{"label":"Trim","data":{"dpcc":{"declaration":"function Trim: string;",' +
    '"unit":"System.SysUtils","container":"TStringHelper","helper":true}}}');
  try
    mDetails := TDpccServerCompletionProvider.DetailsFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.IsTrue(mDetails.IsHelper);
  Assert.AreEqual('TStringHelper', mDetails.Container);
  // Andere Server: detail und documentation.
  mResponse := TJSONObject.ParseJSONValue('{"label":"X","detail":"X: Integer","documentation":{"value":"Doku"}}');
  try
    mDetails := TDpccServerCompletionProvider.DetailsFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual('X: Integer', mDetails.Declaration);
  Assert.AreEqual('Doku', mDetails.Summary);
  Assert.IsFalse(mDetails.IsDeprecated);
  Assert.IsTrue(mDetails.Doc.IsEmpty);
  Assert.IsFalse(mDetails.Display.Known);
end;

procedure TDpccCompletionProviderTests.ReadsResolvedDetails;
var
  Response: TJSONValue;
  Items: TDpccCompletionItems;
  Details: TDpccItemDetails;
begin
  // data bleibt für completionItem/resolve erhalten.
  Response := TJSONObject.ParseJSONValue('[{"label":"Add","data":{"file":"C:\\P\\A.pas","line":9,"character":13}}]');
  try
    Items := TDpccServerCompletionProvider.ItemsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.Contains(Items[0].ResolveData, '"line":9');
  Response := TJSONObject.ParseJSONValue(
    '{"label":"Add","detail":"function Add(const S: string): Integer; virtual;","data":{"dpcc":{' +
    '"declaration":"function Add(const S: string): Integer; virtual;","unit":"Liste","container":"TListe",' +
    '"visibility":"public","directives":["virtual","deprecated"],"deprecated":"Neu verwenden",' +
    '"summary":"Hängt S an.","returns":"Index.","params":[{"name":"S","text":"Der Text."}],' +
    '"exceptions":[{"name":"EListError","text":"Voll."}],' +
    '"documentation":{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Hängt "},' +
    '{"kind":"paramref","text":"S"},{"kind":"text","text":" an."}]}]},' +
    '"xmlDoc":{"full":true,"maxLines":20}}}}');
  try
    Details := TDpccServerCompletionProvider.DetailsFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual('function Add(const S: string): Integer; virtual;', Details.Declaration);
  Assert.AreEqual('Liste', Details.UnitName);
  Assert.AreEqual('TListe', Details.Container);
  Assert.AreEqual('public', Details.Visibility);
  Assert.AreEqual(2, Integer(Length(Details.Directives)));
  Assert.IsTrue(Details.IsDeprecated);
  Assert.AreEqual('Neu verwenden', Details.DeprecatedText);
  Assert.AreEqual('Hängt S an.', Details.Summary);
  Assert.AreEqual('Index.', Details.Returns);
  Assert.AreEqual('Der Text.', Details.Params[0].Text);
  Assert.AreEqual('EListError', Details.Exceptions[0].Name);
  // Vollständige XMLDoc und Anzeige (#654).
  Assert.AreEqual(1, Integer(Length(Details.Doc.Sections)));
  Assert.AreEqual('Hängt S an.', Details.Doc.Sections[0].Text);
  Assert.IsTrue(Details.Display.Known);
  Assert.AreEqual(20, Details.Display.MaxLines);
  Assert.IsFalse(Details.IsHelper);
  AssertHelperAndForeignDetails;
end;

procedure TDpccCompletionProviderTests.MergesProvidersAndCompletesOnce;
var
  Providers: TDpccCompletionProviders;
  Provider: IDpccCompletionProvider;
  Sink: TCollectingSink;
  SinkRef: IDpccCompletionSink;
begin
  Providers := TDpccCompletionProviders.Create;
  Provider := Providers;
  Providers.Add(TDpccFixedCompletionProvider.Create([Item('Beta')]));
  Providers.Add(TDpccFixedCompletionProvider.Create([Item('Alpha'), Item('Gamma')], 50));
  Sink := TCollectingSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Assert.IsTrue(Sink.WaitDone(3000), 'Complete kam nicht');
  Assert.AreEqual('Alpha,Beta,Gamma', Sink.Names);
  Assert.AreEqual(1, Sink.Completed);
end;

procedure TDpccCompletionProviderTests.CancelDropsLateItems;
var
  Providers: TDpccCompletionProviders;
  Provider: IDpccCompletionProvider;
  Sink: TCollectingSink;
  SinkRef: IDpccCompletionSink;
begin
  Providers := TDpccCompletionProviders.Create;
  Provider := Providers;
  Providers.Add(TDpccFixedCompletionProvider.Create([Item('Spaet')], 200));
  Sink := TCollectingSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Provider.Cancel;
  Assert.IsFalse(Sink.WaitDone(400), 'Nach Cancel darf kein Complete kommen');
  Assert.AreEqual('', Sink.Names);
end;

procedure TDpccCompletionProviderTests.NewQueryReplacesRunningQuery;
var
  Providers: TDpccCompletionProviders;
  Provider: IDpccCompletionProvider;
  First, Second: TCollectingSink;
  FirstRef, SecondRef: IDpccCompletionSink;
begin
  Providers := TDpccCompletionProviders.Create;
  Provider := Providers;
  Providers.Add(TDpccFixedCompletionProvider.Create([Item('X')], 100));
  First := TCollectingSink.Create;
  FirstRef := First;
  Second := TCollectingSink.Create;
  SecondRef := Second;
  Provider.Query(Context, FirstRef);
  Provider.Query(Context, SecondRef);
  Assert.IsTrue(Second.WaitDone(3000), 'Complete des neuen Query kam nicht');
  Assert.AreEqual('X', Second.Names);
  Assert.AreEqual(0, First.Completed, 'Der ersetzte Query wurde noch beendet');
  Assert.AreEqual('', First.Names);
end;

procedure TDpccCompletionProviderTests.WithoutSessionCompletesEmpty;
var
  Server: TDpccServerCompletionProvider;
  Provider: IDpccCompletionProvider;
  Sink: TCollectingSink;
  SinkRef: IDpccCompletionSink;
  Logged: string;
begin
  Server := TDpccServerCompletionProvider.Create(
    function: TLspSession
    begin
      Result := nil;
    end);
  Provider := Server;
  // Warum die Liste leer bleibt, steht im Diagnoselog des Plugins (#647).
  Logged := '';
  Server.OnLog :=
    procedure(const AMessage: string)
    begin
      Logged := Logged + AMessage;
    end;
  Sink := TCollectingSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Assert.IsTrue(Sink.WaitDone(0), 'Ohne Server sofort fertig');
  Assert.AreEqual('', Sink.Names);
  Assert.Contains(Logged, 'kein Server');
end;

{ TDpccServerCompletionTests }

procedure TDpccItemDetailsTests.AvailabilityAloneIsNotEmpty;
var
  Details: TDpccItemDetails;
begin
  Details := Default(TDpccItemDetails);
  Assert.IsTrue(Details.IsEmpty);
  Details.Availability := 'Nicht verfügbar: Die Bedingung „WIN64“ ist für Win32 · Debug nicht erfüllt.';
  Assert.IsFalse(Details.IsEmpty);
end;

procedure TDpccServerCompletionTests.WarmUpFirstUse;
begin
  // Erster echter Start (Pipes, Threads, Sitzung, Zeitlimit-Arbeiter) ungemessen statt [IgnoreMemoryLeaks].
  try
    CompletesMembersFromServer;
  except
    // Scheitert der Lauf, meldet das der Test selbst.
    on Exception do
      ;
  end;
end;

const
  cCompletesMembersUnitText =
    'unit Probe;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    FWert: Integer;'#13#10 +
    '    FWeite: Integer;'#13#10 +
    '    procedure Setze;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TFoo.Setze;'#13#10 +
    'begin'#13#10 +
    '  Self.FWe'#13#10 +
    'end;'#13#10 +
    'end.';

procedure TDpccServerCompletionTests.CompletesMembersFromServer;
var
  Server: TLspInProcessServer;
  ServerRef: IDpccLspServer;
  Session: TLspSession;
  Provider: TDpccServerCompletionProvider;
  ProviderRef: IDpccCompletionProvider;
  Sink: TCollectingSink;
  SinkRef: IDpccCompletionSink;
  Query: TDpccContext;
begin
  Server := TLspInProcessServer.Create;
  ServerRef := Server;
  try
    Session := TLspSession.Create(ServerRef.Client, 5000);
    try
      Session.Initialize;
      Provider := TDpccServerCompletionProvider.Create(
        function: TLspSession
        begin
          Result := Session;
        end, 5000);
      ProviderRef := Provider;
      Query := Default(TDpccContext);
      Query.FileName := TPath.Combine(TPath.GetTempPath, 'DpccCompletionProbe.pas');
      Query.Text := cCompletesMembersUnitText;
      Query.Line := 11;
      // Hinter "  Self.FWe".
      Query.Character := 10;
      Query.Prefix := 'FWe';
      Query.Kind := TDpccContextKind.MemberAccess;
      Sink := TCollectingSink.Create;
      SinkRef := Sink;
      ProviderRef.Query(Query, SinkRef);
      Assert.IsTrue(Sink.WaitDone(10000), 'Keine Antwort vom Server');
      Assert.Contains(Sink.Names, 'FWeite');
      Assert.Contains(Sink.Names, 'FWert');
      // Vor dem Freigeben der Sitzung auf laufende Anfragen warten.
      Provider.Shutdown;
      ProviderRef := nil;
      // Wie StopSessionNow im Plugin: Client schließen, Sitzung freigeben, dann den Server.
      ServerRef.Client.Close;
    finally
      Session.Free;
    end;
  finally
    ServerRef := nil;
  end;
end;

{ TDpccXmlDocTests }

procedure TDpccXmlDocTests.RecognizesTagContext;
begin
  Assert.IsTrue(TDpccXmlDoc.IsTagContext('  /// <'));
  Assert.IsTrue(TDpccXmlDoc.IsTagContext('  /// Text <su'));
  Assert.IsFalse(TDpccXmlDoc.IsTagContext('  // <'), 'nur ///');
  Assert.IsFalse(TDpccXmlDoc.IsTagContext('  /// Text'));
  Assert.IsFalse(TDpccXmlDoc.IsTagContext('  if A < B'));
end;

procedure TDpccXmlDocTests.OffersParamsOfFollowingMethod;
const
  Text = 'type'#13#10 +
    '  TFoo = class'#13#10 +
    '    /// <'#13#10 +
    '    /// weiter'#13#10 +
    '    function CalcDiscount(const Customer: TCustomer;'#13#10 +
    '      Rate, Extra: Double): Currency;'#13#10 +
    '  end;';
var
  Declaration, Names: string;
  Item: TDpccCompletionItem;
begin
  Declaration := TDpccXmlDoc.FollowingDeclaration(Text, 2);
  Assert.AreEqual('function CalcDiscount(const Customer: TCustomer; Rate, Extra: Double): Currency;', Declaration);
  Assert.AreEqual('Customer,Rate,Extra', String.Join(',', TDpccXmlDoc.ParamNames(Declaration)));
  Names := '';
  for Item in TDpccXmlDoc.TagItems(Declaration) do
  begin
    Names := Names + Item.Name + '|';
  end;
  Assert.IsTrue(Names.StartsWith('summary|param name="Customer"|param name="Rate"|param name="Extra"|returns|'),
    Names);
  Assert.AreEqual('summary>$0</summary>', TDpccXmlDoc.TagItems(Declaration)[0].InsertText);
  // Prozedur: kein returns.
  Assert.IsFalse(String.Join('|', [TDpccXmlDoc.TagItems('procedure Add(A: Integer);')[2].Name]) = 'returns');
end;

{ TDpccMatchingBudgetTests }

procedure TDpccMatchingBudgetTests.Filters5000EntriesWithin12ms;
const
  Words: array[0..11] of string = ('Add', 'String', 'List', 'Item', 'Get', 'Set', 'Count', 'Object', 'Begin',
    'Update', 'Index', 'Value');
var
  Items: TDpccCompletionItems;
  Index, Run: Integer;
  Pattern: string;
  Watch: TStopwatch;
  Times: TArray<Int64>;
begin
  SetLength(Items, 5000);
  for Index := 0 to High(Items) do
  begin
    Items[Index].Name := Words[Index mod 12] + Words[(Index div 12) mod 12] + Words[(Index div 144) mod 12] +
      IntToStr(Index);
    Items[Index].Rank := Index;
  end;
  // Typische Schritte beim Tippen: Anfang, CamelCase, Teilfolge, kein Treffer.
  for Pattern in ['A', 'Ad', 'AddS', 'ASL', 'stl', 'xyz'] do
  begin
    TDpccCompletionMatcher.Filter(Items, Pattern);
    Times := nil;
    for Run := 1 to 5 do
    begin
      Watch := TStopwatch.StartNew;
      TDpccCompletionMatcher.Filter(Items, Pattern);
      Times := Times + [Watch.ElapsedMilliseconds];
    end;
    // Median von fünf Läufen, damit ein einzelner Ausreißer der Maschine nicht zählt.
    TArray.Sort<Int64>(Times);
    Assert.IsTrue(Times[2] <= 12, Format('Filtern nach "%s" dauerte %d ms', [Pattern, Times[2]]));
  end;
end;

procedure TDpccMatchingBudgetTests.Orders5000EntriesWithRestWithin16ms;
const
  Words: array[0..11] of string = ('Add', 'String', 'List', 'Item', 'Get', 'Set', 'Count', 'Object', 'Begin',
    'Update', 'Index', 'Value');
var
  Items: TDpccCompletionItems;
  Index, Run, RestStart: Integer;
  Pattern: string;
  Watch: TStopwatch;
  Times: TArray<Int64>;
  Options: TDpccRankOptions;
  Order: TArray<Integer>;
begin
  SetLength(Items, 5000);
  for Index := 0 to High(Items) do
  begin
    Items[Index].Name := Words[Index mod 12] + Words[(Index div 12) mod 12] + Words[(Index div 144) mod 12] +
      IntToStr(Index);
    Items[Index].Rank := Index;
  end;
  Options := TDpccRankOptions.Defaults;
  Options.ListMode := TDpccListMode.Rest;
  for Pattern in ['A', 'AddS', 'ASL', 'xyz'] do
  begin
    Order := TDpccRanking.Order(Items, Pattern, Options, RestStart);
    Assert.AreEqual(5000, TDpccRanking.ItemCount(Order), 'Alle Einträge bleiben sichtbar');
    Times := nil;
    for Run := 1 to 5 do
    begin
      Watch := TStopwatch.StartNew;
      TDpccRanking.Order(Items, Pattern, Options, RestStart);
      Times := Times + [Watch.ElapsedMilliseconds];
    end;
    TArray.Sort<Int64>(Times);
    Assert.IsTrue(Times[2] <= 16, Format('Ordnen mit Rest nach "%s" dauerte %d ms', [Pattern, Times[2]]));
  end;
  Items := nil;
  Order := nil;
end;

{ TDpccWordTests }

procedure TDpccWordTests.FindsStartBeforeCursor;
begin
  // "  myList := TStringL|ist.": Präfix ab Index 12.
  Assert.AreEqual(12, TDpccWord.StartBefore('  myList := TStringList.', 20));
  Assert.AreEqual(0, TDpccWord.StartBefore('Format', 3));
  Assert.AreEqual(5, TDpccWord.StartBefore('List.Ad', 7));
  Assert.AreEqual(5, TDpccWord.StartBefore('List.', 5));
end;

procedure TDpccWordTests.FindsEndBehindCursorInsideWord;
begin
  // Mitten im Wort: bis zum Punkt ersetzen, nicht nur bis zum Cursor.
  Assert.AreEqual(23, TDpccWord.EndAfter('  myList := TStringList.', 20));
  Assert.AreEqual(6, TDpccWord.EndAfter('Format', 3));
  Assert.AreEqual(5, TDpccWord.EndAfter('Größe(', 2));
end;

procedure TDpccWordTests.EndStaysAtCursorWithoutWordBehind;
begin
  Assert.AreEqual(4, TDpccWord.EndAfter('List.Add', 4));
  Assert.AreEqual(6, TDpccWord.EndAfter('Format', 6));
  Assert.AreEqual(8, TDpccWord.EndAfter('  Add(  ', 8));
end;

procedure TDpccWordTests.DetectsDataNameStrings;
begin
  // Feld- und Parameternamen (#461): nur im ersten String-Argument.
  Assert.IsTrue(TDpccWord.InDataNameString('  qryOrders.FieldByName(''cu', 27));
  Assert.IsTrue(TDpccWord.InDataNameString('  qryOrders.Params.ParamByName(''', 32));
  Assert.IsTrue(TDpccWord.InDataNameString('  if q.FindField(''A''''B'') = nil', 22));
  Assert.IsFalse(TDpccWord.InDataNameString('  qryOrders.FieldByName(''cu'').AsString', 29));
  Assert.IsFalse(TDpccWord.InDataNameString('  ShowMessage(''cu', 17));
  Assert.IsFalse(TDpccWord.InDataNameString('  FieldByName(''cu', 17));
  Assert.IsFalse(TDpccWord.InDataNameString('  // q.FieldByName(''cu', 22));
end;

procedure TDpccMatchingBudgetTests.TyposAppearUnderDidYouMean;
var
  Items: TDpccCompletionItems;
  Order: TArray<Integer>;
  Name: string;
  Item: TDpccCompletionItem;
begin
  Assert.AreEqual(1, TDpccCompletionMatcher.Distance('Lenght', 'Length'), 'Vertauschung zählt 1');
  Assert.AreEqual(1, TDpccCompletionMatcher.Distance('lengh', 'Length'));
  Assert.AreEqual(0, TDpccCompletionMatcher.TypoLimit('Le'));
  Items := nil;
  for Name in ['Length', 'Low', 'High', 'Lengthy'] do
  begin
    Item := Default(TDpccCompletionItem);
    Item.Name := Name;
    Items := Items + [Item];
  end;
  Order := TDpccRanking.Order(Items, 'Lenght', TDpccRankOptions.Defaults);
  Assert.AreEqual(TDpccRanking.cTypoHeader, Order[0], 'keine regulären Treffer: gleich „Meintest du“');
  Assert.AreEqual('Length', Items[Order[1]].Name);
  Assert.AreEqual(2, TDpccRanking.ItemCount(Order), 'Length und Lengthy (Anfang), nicht Low');
  Assert.IsTrue(TDpccRanking.OnlyTypos(Order), 'Fußzeile: Keine Treffer für „Lenght“');
  // Mit genug regulären Treffern keine Tippfehler-Gruppe.
  Order := TDpccRanking.Order(Items, 'L', TDpccRankOptions.Defaults);
  Assert.IsFalse(TDpccRanking.IsHeader(Order[0]));
  Assert.IsFalse(TDpccRanking.OnlyTypos(Order));
  Assert.IsFalse(TDpccRanking.OnlyTypos([TDpccRanking.cTypoHeader]));
end;

procedure TDpccMatchingBudgetTests.AnnouncementNamesKindPositionAndDetail;
var
  Item: TDpccCompletionItem;
begin
  Item := Default(TDpccCompletionItem);
  Item.Name := 'ShowMessage';
  Item.Signature := 'procedure ShowMessage(const Msg: string)';
  Assert.AreEqual('ShowMessage, Methode, 3 von 12. procedure ShowMessage(const Msg: string)',
    TDpccItemPresentation.Announcement(Item, 'Methode', '%d von %d', 3, 12));
  Item.Signature := '';
  Assert.AreEqual('ShowMessage, 1 von 1.', TDpccItemPresentation.Announcement(Item, '', '%d von %d', 1, 1));
end;

{ TDpccPlainRowTests }

function PlainItem(const AName: string; AKind: TDpccItemKind; const ASignature: string): TDpccCompletionItem;
begin
  Result := Default(TDpccCompletionItem);
  Result.Name := AName;
  Result.Kind := AKind;
  Result.Signature := ASignature;
  Result.UnitUsed := True;
end;

procedure TDpccPlainRowTests.KindWordsLikeIdeList;
begin
  // Methoden nach dem Anfang der Signatur, ohne Signatur als function.
  Assert.AreEqual('procedure', TDpccItemPresentation.KindWord(PlainItem('Add', TDpccItemKind.Method,
    'procedure Add(const S: string)')));
  Assert.AreEqual('procedure', TDpccItemPresentation.KindWord(PlainItem('Run', TDpccItemKind.Method,
    'class procedure Run')));
  Assert.AreEqual('function', TDpccItemPresentation.KindWord(PlainItem('Count', TDpccItemKind.Method,
    'function Count: Integer')));
  Assert.AreEqual('destructor', TDpccItemPresentation.KindWord(PlainItem('Destroy', TDpccItemKind.Method,
    'destructor Destroy')));
  Assert.AreEqual('function', TDpccItemPresentation.KindWord(PlainItem('Foo', TDpccItemKind.Method, 'TList')));
  Assert.AreEqual('procedure', TDpccItemPresentation.KindWord(PlainItem('Foo', TDpccItemKind.Procedure_, '')));
  Assert.AreEqual('constructor', TDpccItemPresentation.KindWord(PlainItem('Create', TDpccItemKind.Constructor_,
    '')));
  Assert.AreEqual('type', TDpccItemPresentation.KindWord(PlainItem('TFoo', TDpccItemKind.Class_, '')));
  Assert.AreEqual('type', TDpccItemPresentation.KindWord(PlainItem('TRec', TDpccItemKind.Record_, '')));
  Assert.AreEqual('var', TDpccItemPresentation.KindWord(PlainItem('I', TDpccItemKind.Variable, 'Integer')));
  Assert.AreEqual('const', TDpccItemPresentation.KindWord(PlainItem('cMax', TDpccItemKind.Constant, '')));
  Assert.AreEqual('field', TDpccItemPresentation.KindWord(PlainItem('FCount', TDpccItemKind.Field, '')));
  Assert.AreEqual('property', TDpccItemPresentation.KindWord(PlainItem('Count', TDpccItemKind.Property_, '')));
  Assert.AreEqual('keyword', TDpccItemPresentation.KindWord(PlainItem('nil', TDpccItemKind.Keyword, '')));
  Assert.AreEqual('unit', TDpccItemPresentation.KindWord(PlainItem('System.Classes', TDpccItemKind.Unit_, '')));
  Assert.AreEqual('', TDpccItemPresentation.KindWord(PlainItem('x', TDpccItemKind.Unknown, '')));
end;

procedure TDpccPlainRowTests.ParamsFollowName;
var
  mRow: TDpccPlainRow;
begin
  mRow := TDpccItemPresentation.PlainRow(PlainItem('lvOrdersDblClick', TDpccItemKind.Method,
    'procedure lvOrdersDblClick(Sender: TObject);'), 'Detail', '');
  Assert.AreEqual('procedure', mRow.Kind);
  Assert.AreEqual('(Sender: TObject);', mRow.Params);
  Assert.AreEqual('', mRow.Detail, 'Signatur mit Namen: kein Detail');
  mRow := TDpccItemPresentation.PlainRow(PlainItem('Count', TDpccItemKind.Method, 'function Count: Integer'), '',
    '');
  Assert.AreEqual(': Integer', mRow.Params);
  // Ohne Parameter: nichts hinter dem Namen.
  mRow := TDpccItemPresentation.PlainRow(PlainItem('Open', TDpccItemKind.Method, 'procedure Open'), 'x', '');
  Assert.AreEqual('', mRow.Params);
  Assert.AreEqual('', mRow.Detail);
end;

procedure TDpccPlainRowTests.DetailWhenSignatureHasNoName;
var
  mRow: TDpccPlainRow;
  mTail: string;
begin
  // Typ, Klasse oder Unit statt Signatur: abgesetzt als Detail.
  mRow := TDpccItemPresentation.PlainRow(PlainItem('FCount', TDpccItemKind.Field, 'Integer'), 'Integer', '');
  Assert.AreEqual('field', mRow.Kind);
  Assert.AreEqual('', mRow.Params);
  Assert.AreEqual('Integer', mRow.Detail);
  // Nur der ganze Name: "Add" ist nicht der Anfang von "AddPair".
  Assert.IsFalse(TDpccItemPresentation.SignatureTail('Add', 'procedure AddPair(const S: string)', mTail));
  // Detail gleich Name bzw. Art fällt weg.
  mRow := TDpccItemPresentation.PlainRow(PlainItem('nil', TDpccItemKind.Keyword, 'keyword'), 'keyword', '');
  Assert.AreEqual('', mRow.Detail);
end;

procedure TDpccPlainRowTests.TrailerKeepsUnitAndWarnings;
var
  mItem: TDpccCompletionItem;
  mTags: TDpccTags;
begin
  mItem := PlainItem('tdUnicodeClass', TDpccItemKind.Constant, 'Winapi.CorHdr (add to uses)');
  mItem.UnitUsed := False;
  mItem.Directives := ['deprecated'];
  mItem.Usage := TDpccUsageMark.Recent;
  mItem.IsHelper := True;
  mTags := TDpccItemPresentation.PlainTags(TDpccItemPresentation.Tags(mItem));
  // „+ Unit“ und deprecated bleiben, zuletzt und Helper (Akzent) nicht.
  Assert.AreEqual(2, Integer(Length(mTags)));
  Assert.AreEqual('+ Winapi.CorHdr', mTags[0].Text);
  Assert.AreEqual('deprecated', mTags[1].Text);
  // Fehlt die Unit, ist das Detail leer; die Unit steht rechts.
  Assert.AreEqual('', TDpccItemPresentation.PlainRow(mItem, TDpccItemPresentation.Detail(mItem), '').Detail);
end;

procedure TDpccMatchingBudgetTests.TagTextNamesStatesInWords;
var
  Item: TDpccCompletionItem;
begin
  Item := Default(TDpccCompletionItem);
  Item.Name := 'AddPair';
  Assert.AreEqual('', TDpccItemPresentation.TagText(Item));
  Item.Directives := ['deprecated'];
  Item.IsHelper := True;
  Assert.AreEqual('deprecated, Helper', TDpccItemPresentation.TagText(Item));
  Item.Directives := nil;
end;

procedure TDpccMatchingBudgetTests.CommitTextFixesCase;
begin
  Assert.AreEqual('ShowMessage', TDpccCompletionMatcher.CommitText('showmessage', 'ShowMessage', True));
  Assert.AreEqual('ShowMessage', TDpccCompletionMatcher.CommitText('showm', 'ShowMessage', True));
end;

procedure TDpccMatchingBudgetTests.CommitTextKeepsTypedCaseWhenOff;
begin
  Assert.AreEqual('showmessage', TDpccCompletionMatcher.CommitText('showmessage', 'ShowMessage', False));
  Assert.AreEqual('showMessage', TDpccCompletionMatcher.CommitText('show', 'ShowMessage', False));
  // Unscharfer Treffer ("TSL" → TStringList): kein Anfang, also der Name.
  Assert.AreEqual('TStringList', TDpccCompletionMatcher.CommitText('tsl', 'TStringList', False));
end;

{ TDpccCompositeNoWaitTests }

type
  /// <summary>Quelle, die in Query (wie ein langsames Prepare) ADelayMs blockiert und dann liefert; zählt Aufrufe
  /// und wie viele gleichzeitig liefen.</summary>
  TBlockingProvider = class(TInterfacedObject, IDpccCompletionProvider, IDpccNamedProvider)
  private
    FItems: TDpccCompletionItems;
    FDelayMs: Cardinal;
    FRunning: Integer;
    FOverlapped: Integer;
    FCalls: Integer;
  public
    constructor Create(const AItems: TDpccCompletionItems; ADelayMs: Cardinal);
    procedure Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
    procedure Cancel;
    function ProviderName: string;
    function Running: Integer;
    function Calls: Integer;
    function Overlapped: Integer;
  end;

const
  cBlockingName = 'Blockierend';

constructor TBlockingProvider.Create(const AItems: TDpccCompletionItems; ADelayMs: Cardinal);
begin
  inherited Create;
  FItems := AItems;
  FDelayMs := ADelayMs;
end;

procedure TBlockingProvider.Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
begin
  TInterlocked.Increment(FCalls);
  if TInterlocked.Increment(FRunning) > 1 then
  begin
    TInterlocked.Increment(FOverlapped);
  end;
  try
    TThread.Sleep(FDelayMs);
  finally
    TInterlocked.Decrement(FRunning);
  end;
  ASink.AddItems(FItems);
  ASink.Complete;
end;

procedure TBlockingProvider.Cancel;
begin
end;

function TBlockingProvider.ProviderName: string;
begin
  Result := cBlockingName;
end;

function TBlockingProvider.Running: Integer;
begin
  Result := TInterlocked.CompareExchange(FRunning, 0, 0);
end;

function TBlockingProvider.Calls: Integer;
begin
  Result := TInterlocked.CompareExchange(FCalls, 0, 0);
end;

function TBlockingProvider.Overlapped: Integer;
begin
  Result := TInterlocked.CompareExchange(FOverlapped, 0, 0);
end;

/// <summary>Bis AMs warten, bis AProvider keinen Aufruf mehr ausführt (Arbeiter des Tests enden im Test).</summary>
function WaitIdle(AProvider: TBlockingProvider; AMs: Cardinal): Boolean;
var
  mWatch: TStopwatch;
begin
  mWatch := TStopwatch.StartNew;
  while (AProvider.Running > 0) and (mWatch.ElapsedMilliseconds < AMs) do
  begin
    TThread.Sleep(5);
  end;
  // Der Arbeiter gibt seine Spur kurz nach dem Ende von Query frei.
  TThread.Sleep(20);
  Result := AProvider.Running = 0;
end;

procedure TDpccCompositeNoWaitTests.WarmUp;
var
  mProviders: TDpccCompletionProviders;
  mProvider: IDpccCompletionProvider;
  mBlocking: TBlockingProvider;
  mSink: TCollectingSink;
  mSinkRef: IDpccCompletionSink;
begin
  // Die Sicherung legt je Quelle Einträge für „langsam“ an und behält sie bis Programmende.
  TDpccGuard.ReportProviderSlow(cBlockingName, 'Vorwärmen');
  mProviders := TDpccCompletionProviders.Create;
  mProvider := mProviders;
  mBlocking := TBlockingProvider.Create([Item('A')], 0);
  mProviders.Add(mBlocking);
  mSink := TCollectingSink.Create;
  mSinkRef := mSink;
  mProvider.Query(Context, mSinkRef);
  mSink.WaitDone(3000);
  WaitIdle(mBlocking, 3000);
end;

procedure TDpccCompositeNoWaitTests.QueryReturnsBeforeSlowSource;
var
  mProviders: TDpccCompletionProviders;
  mProvider: IDpccCompletionProvider;
  mBlocking: TBlockingProvider;
  mBlockingRef: IDpccCompletionProvider;
  mSink: TCollectingSink;
  mSinkRef: IDpccCompletionSink;
  mWatch: TStopwatch;
begin
  mProviders := TDpccCompletionProviders.Create;
  mProvider := mProviders;
  mProviders.TimeLimitMs := 2000;
  mBlocking := TBlockingProvider.Create([Item('B')], 400);
  mBlockingRef := mBlocking;
  mProviders.Add(mBlockingRef);
  mProviders.Add(TDpccFixedCompletionProvider.Create([Item('A')]));
  mSink := TCollectingSink.Create;
  mSinkRef := mSink;
  mWatch := TStopwatch.StartNew;
  mProvider.Query(Context, mSinkRef);
  // Vorher wartete Query bis zu 2000 ms (hier 400 ms) auf die blockierende Quelle.
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 150, Format('Query wartete %d ms', [mWatch.ElapsedMilliseconds]));
  Assert.IsTrue(mSink.WaitDone(3000), 'Complete kam nicht');
  Assert.AreEqual('A,B', mSink.Names);
  Assert.AreEqual(1, mSink.Completed);
  Assert.IsTrue(WaitIdle(mBlocking, 3000));
end;

procedure TDpccCompositeNoWaitTests.LatestQueryRunsAfterRunningCall;
var
  mProviders: TDpccCompletionProviders;
  mProvider: IDpccCompletionProvider;
  mBlocking: TBlockingProvider;
  mBlockingRef: IDpccCompletionProvider;
  mFirst, mSecond: TCollectingSink;
  mFirstRef, mSecondRef: IDpccCompletionSink;
begin
  mProviders := TDpccCompletionProviders.Create;
  mProvider := mProviders;
  mProviders.TimeLimitMs := 2000;
  mBlocking := TBlockingProvider.Create([Item('B')], 150);
  mBlockingRef := mBlocking;
  mProviders.Add(mBlockingRef);
  mFirst := TCollectingSink.Create;
  mFirstRef := mFirst;
  mSecond := TCollectingSink.Create;
  mSecondRef := mSecond;
  mProvider.Query(Context, mFirstRef);
  mProvider.Query(Context, mSecondRef);
  Assert.IsTrue(mSecond.WaitDone(3000), 'Complete der neuesten Abfrage kam nicht');
  Assert.AreEqual('B', mSecond.Names);
  Assert.AreEqual(0, mFirst.Completed, 'Die ersetzte Abfrage wurde noch beendet');
  Assert.IsTrue(WaitIdle(mBlocking, 3000));
  Assert.AreEqual(2, mBlocking.Calls, 'die laufende und die neueste');
  Assert.AreEqual(0, mBlocking.Overlapped, 'nie zwei Aufrufe zugleich');
end;

procedure TDpccCompositeNoWaitTests.HangingSourceIsAbandonedAndSkipped;
var
  mProviders: TDpccCompletionProviders;
  mProvider: IDpccCompletionProvider;
  mBlocking: TBlockingProvider;
  mBlockingRef: IDpccCompletionProvider;
  mFirst, mSecond: TCollectingSink;
  mFirstRef, mSecondRef: IDpccCompletionSink;
begin
  mProviders := TDpccCompletionProviders.Create;
  mProvider := mProviders;
  mProviders.TimeLimitMs := 100;
  mBlocking := TBlockingProvider.Create([Item('B')], 600);
  mBlockingRef := mBlocking;
  mProviders.Add(mBlockingRef);
  mFirst := TCollectingSink.Create;
  mFirstRef := mFirst;
  mProvider.Query(Context, mFirstRef);
  // Nach dem Zeitlimit gilt der Teil als fertig, obwohl die Quelle noch blockiert.
  Assert.IsTrue(mFirst.WaitDone(450), 'Complete nach dem Zeitlimit kam nicht');
  Assert.AreEqual('', mFirst.Names);
  Assert.AreEqual(1, mBlocking.Running, 'Die Quelle hängt noch');
  mSecond := TCollectingSink.Create;
  mSecondRef := mSecond;
  mProvider.Query(Context, mSecondRef);
  Assert.IsTrue(mSecond.WaitDone(200), 'Die hängende Quelle wurde nicht übersprungen');
  Assert.AreEqual('', mSecond.Names);
  Assert.IsTrue(WaitIdle(mBlocking, 3000));
  Assert.AreEqual(1, mBlocking.Calls, 'kein zweiter Arbeiter für die hängende Quelle');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccCompletionProviderTests);
  TDUnitX.RegisterTestFixture(TDpccCompositeNoWaitTests);
  TDUnitX.RegisterTestFixture(TDpccServerCompletionTests);
  TDUnitX.RegisterTestFixture(TDpccItemDetailsTests);
  TDUnitX.RegisterTestFixture(TDpccXmlDocTests);
  TDUnitX.RegisterTestFixture(TDpccMatchingBudgetTests);
  TDUnitX.RegisterTestFixture(TDpccWordTests);
  TDUnitX.RegisterTestFixture(TDpccPlainRowTests);


end.
