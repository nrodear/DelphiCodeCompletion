unit dpcc.Core.Completion.Ranking.Tests;

// Tests für Rangfolge (#419), lernende Gewichtung (#418) und Formular-Komponenten (#455).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccRankingTests = class
  public
    [Test]
    procedure GroupsInheritedMembersWithHeaders;
    [Test]
    procedure ScopeOrdersAfterExpectedTypeBeforeBoost;
    [Test]
    procedure PrefixLiftsInheritedMatchWithoutHeaders;
    [Test]
    procedure BoostReordersButNeverBeatsBetterMatch;
    [Test]
    procedure ServerGroupHeaderAndActionLast;
    [Test]
    procedure PostfixAfterMembers;
    [Test]
    procedure FormComponentsComeFirst;
    [Test]
    procedure SenderItemsGetHeaderAndTag;
    [Test]
    procedure VariantFieldsGetBranchTag;
    [Test]
    procedure ConversionStandsBeforeOriginal;
    [Test]
    procedure TypeArgumentsGetHeaderAndFooter;
    [Test]
    procedure AttributesShowAsType;
    [Test]
    procedure DataNamesCarrySource;
    [Test]
    procedure UsesUnitsGroupedWithHeaders;
    [Test]
    procedure InheritedCallsFirstWithTags;
    [Test]
    procedure SameNameVariantsFollowTheActive;
    [Test]
    procedure ListModeFilterShowsOnlyMatches;
    [Test]
    procedure ListModeAllAppendsRestWithoutHeader;
    [Test]
    procedure ListModeRestUnderHeader;
    [Test]
    procedure ListModeRestSkipsTyposAndEmptyPattern;
    [Test]
    procedure ListModeNames;
  end;

  [TestFixture]
  TDpccUsageTests = class
  public
    [Test]
    procedure RecordsBoostAndMarks;
    [Test]
    procedure SavesLoadsAndClears;
    /// <summary>Unbrauchbare Datei liegt danach als .defekt daneben; eine beim Lesen gesperrte wird nicht
    /// überschrieben.</summary>
    [Test]
    procedure BrokenFileSetAsideLockedFileKept;
    [Test]
    procedure LearnedEntryRisesInController;
    [Test]
    procedure SelectionSkipsHeaders;
    [Test]
    procedure TypingDiscardsGuardOffer;
    [Test]
    procedure RestOnlyInMemberListsByDefault;
    [Test]
    procedure RestWithoutMatchSelectsNothing;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Ranking,
  dpcc.Core.Completion.Presentation,
  dpcc.Core.Completion.Usage,
  dpcc.Core.Files.DataFile,
  dpcc.Core.Completion.Controller,
  dpcc.Core.Completion.Providers.Fixed,
  dpcc.Core.Completion.Providers.Server;

type
  TRecordingView = class(TInterfacedObject, IDpccCompletionView)
  public
    Names: string;
    Selected: Integer;
    procedure ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
  end;

procedure TRecordingView.ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
var
  Index: Integer;
begin
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

procedure TRecordingView.HideList;
begin
end;

procedure TRecordingView.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
end;

function TRecordingView.PageSize: Integer;
begin
  Result := 9;
end;

function Member(const AName, AContainer: string; ADepth, ARank: Integer;
  AKind: TDpccItemKind = TDpccItemKind.Method): TDpccCompletionItem;
begin
  Result := Default(TDpccCompletionItem);
  Result.Name := AName;
  Result.DeclaringClass := AContainer;
  Result.Depth := ADepth;
  Result.Rank := ARank;
  Result.Kind := AKind;
end;

function Names(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index in AOrder do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    if TDpccRanking.IsHeader(Index) then
    begin
      Result := Result + '#';
    end
    else
    begin
      Result := Result + AItems[Index].Name;
    end;
  end;
end;

function Wait(const ACondition: TFunc<Boolean>): Boolean;
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
  until TThread.GetTickCount64 - Start > 3000;
  Result := False;
end;

function Context(const APrefix: string): TDpccContext;
begin
  Result := Default(TDpccContext);
  Result.FileName := 'C:\P\A.pas';
  Result.Prefix := APrefix;
end;

function StringsItems: TDpccCompletionItems;
begin
  // TStringList-Instanz: eigene Member, dann TStrings, dann TPersistent.
  Result := [Member('Sort', 'TStringList', 0, 0), Member('Add', 'TStrings', 1, 1),
    Member('BeginUpdate', 'TStrings', 1, 2), Member('Assign', 'TPersistent', 2, 3)];
end;

function RestItems: TDpccCompletionItems;
begin
  Result := [Member('Add', 'TStrings', 0, 0), Member('Assign', 'TPersistent', 0, 1),
    Member('BeginUpdate', 'TStrings', 0, 2), Member('Clear', 'TStrings', 0, 3), Member('Sort', 'TStringList', 0, 4)];
end;

function RestOptions(AMode: TDpccListMode): TDpccRankOptions;
begin
  Result := TDpccRankOptions.Defaults;
  Result.ListMode := AMode;
end;

{ TDpccRankingTests }

procedure TDpccRankingTests.ListModeFilterShowsOnlyMatches;
var
  Items: TDpccCompletionItems;
  Order: TArray<Integer>;
  RestStart: Integer;
begin
  // Heutiger Stand (#497, Variante 1): nur Treffer.
  Items := RestItems;
  Order := TDpccRanking.Order(Items, 'As', RestOptions(TDpccListMode.Filter), RestStart);
  Assert.AreEqual('Assign', Names(Items, Order));
  Assert.AreEqual(-1, RestStart);
end;

procedure TDpccRankingTests.ListModeAllAppendsRestWithoutHeader;
var
  Items: TDpccCompletionItems;
  Order: TArray<Integer>;
  RestStart: Integer;
begin
  // Variante 2: alles sichtbar, Treffer oben, der Rest in Rangfolge ohne Überschrift.
  Items := RestItems;
  Order := TDpccRanking.Order(Items, 'As', RestOptions(TDpccListMode.All), RestStart);
  Assert.AreEqual('Assign,Add,BeginUpdate,Clear,Sort', Names(Items, Order));
  Assert.AreEqual(1, RestStart);
end;

procedure TDpccRankingTests.ListModeRestUnderHeader;
var
  Items: TDpccCompletionItems;
  Order: TArray<Integer>;
  RestStart: Integer;
begin
  // Variante 3: Treffer, darunter abgesetzt „Weitere Einträge“.
  Items := RestItems;
  Order := TDpccRanking.Order(Items, 'As', RestOptions(TDpccListMode.Rest), RestStart);
  Assert.AreEqual('Assign,#,Add,BeginUpdate,Clear,Sort', Names(Items, Order));
  Assert.AreEqual(TDpccRanking.cRestHeader, Order[1]);
  Assert.AreEqual(2, RestStart);
  // Eine weitere Art (Eigenschaft) steht im Rest nach Rang und Name hinten.
  Items := Items + [Member('Count', 'TStrings', 0, 5, TDpccItemKind.Property_)];
  Order := TDpccRanking.Order(Items, 'As', RestOptions(TDpccListMode.Rest), RestStart);
  Assert.AreEqual('Assign,#,Add,BeginUpdate,Clear,Sort,Count', Names(Items, Order));
  Items := nil;
  Order := nil;
end;

procedure TDpccRankingTests.ListModeRestSkipsTyposAndEmptyPattern;
var
  Items: TDpccCompletionItems;
  Order: TArray<Integer>;
  RestStart: Integer;
begin
  Items := RestItems;
  // Ohne Präfix gibt es keinen Rest: alle Einträge sind Treffer.
  Order := TDpccRanking.Order(Items, '', RestOptions(TDpccListMode.Rest), RestStart);
  Assert.AreEqual('Add,Assign,BeginUpdate,Clear,Sort', Names(Items, Order));
  Assert.AreEqual(-1, RestStart);
  // Tippfehler (#485) stehen unter „Meintest du“ und nicht noch einmal im Rest.
  Order := TDpccRanking.Order(Items, 'Cleer', RestOptions(TDpccListMode.Rest), RestStart);
  Assert.AreEqual('#,Clear,#,Add,Assign,BeginUpdate,Sort', Names(Items, Order));
  Assert.AreEqual(TDpccRanking.cTypoHeader, Order[0]);
  Assert.AreEqual(TDpccRanking.cRestHeader, Order[2]);
  Assert.AreEqual(3, RestStart);
  Items := nil;
  Order := nil;
end;

procedure TDpccRankingTests.ListModeNames;
begin
  Assert.IsTrue(TDpccListModes.ModeOf('filter') = TDpccListMode.Filter);
  Assert.IsTrue(TDpccListModes.ModeOf(' ALL ') = TDpccListMode.All);
  Assert.IsTrue(TDpccListModes.ModeOf('rest') = TDpccListMode.Rest);
  Assert.IsTrue(TDpccListModes.ModeOf('alles') = TDpccListMode.Filter, 'Unbekanntes wird Filter');
  Assert.IsTrue(TDpccListModes.ScopeOf('everywhere') = TDpccListScope.Everywhere);
  Assert.IsTrue(TDpccListModes.ScopeOf('') = TDpccListScope.Members);
end;

procedure TDpccRankingTests.GroupsInheritedMembersWithHeaders;
var
  Options: TDpccRankOptions;
  Items: TDpccCompletionItems;
begin
  Items := StringsItems;
  Options := TDpccRankOptions.Defaults;
  Options.GroupInherited := True;
  Assert.AreEqual('Sort,#,Add,BeginUpdate,#,Assign', Names(Items, TDpccRanking.Order(Items, '', Options)));
  Assert.AreEqual(4, TDpccRanking.ItemCount(TDpccRanking.Order(Items, '', Options)));
  // Abgeschaltet: flache Liste in der Reihenfolge der Quelle.
  Options.GroupInherited := False;
  Assert.AreEqual('Sort,Add,BeginUpdate,Assign', Names(Items, TDpccRanking.Order(Items, '', Options)));
end;

procedure TDpccRankingTests.PrefixLiftsInheritedMatchWithoutHeaders;
var
  Options: TDpccRankOptions;
  Items: TDpccCompletionItems;
begin
  // Beispiel aus #419: "Ass" liefert Assign zuerst, obwohl es geerbt ist.
  Items := StringsItems + [Member('AssignTo', 'TStringList', 0, 4)];
  Options := TDpccRankOptions.Defaults;
  Options.GroupInherited := True;
  Assert.AreEqual('Assign,AssignTo', Names(Items, TDpccRanking.Order(Items, 'Assign', Options)));
  // Gleiche Güte: der eigene Member vor dem geerbten.
  Assert.AreEqual('AssignTo,Assign', Names(Items, TDpccRanking.Order(Items, 'Ass', Options)));
  // Ohne eigenen Treffer: das geerbte Assign zuerst, ohne Überschrift.
  Assert.AreEqual('Assign', Names(StringsItems, TDpccRanking.Order(StringsItems, 'Ass', Options)));
end;

procedure TDpccRankingTests.ScopeOrdersAfterExpectedTypeBeforeBoost;

  function Scoped(const AName: string; AScope: Integer): TDpccCompletionItem;
  begin
    Result := Member(AName, '', 0, 0, TDpccItemKind.Variable);
    Result.Scope := AScope;
  end;

var
  Options: TDpccRankOptions;
  Items: TDpccCompletionItems;
begin
  // #488: Präfix-Güte → erwarteter Typ → Bereich → Lerngewicht → Name.
  Items := [Scoped('FDiscount', 3), Scoped('ACustomer', 2), Scoped('Total', 1), Scoped('Format', 5),
    Scoped('TKasse', 4)];
  Options := TDpccRankOptions.Defaults;
  Options.Boost :=
    function(AIndex: Integer): Integer
    begin
      // FDiscount ist gelernt, schlägt aber keinen näheren Bereich.
      if AIndex = 0 then
      begin
        Result := 99;
      end
      else
      begin
        Result := 0;
      end;
    end;
  Assert.AreEqual('Total,ACustomer,FDiscount,TKasse,Format', Names(Items, TDpccRanking.Order(Items, '', Options)));
  // Erwarteter Typ vor Bereich: Nur ACustomer passt.
  Items[1].ExpectedType := 'Integer';
  Items[1].Fits := True;
  Items[2].ExpectedType := 'Integer';
  Assert.AreEqual('#,ACustomer,#,Total,FDiscount,TKasse,Format',
    Names(Items, TDpccRanking.Order(Items, '', Options)));
  // Mit Präfix: bessere Güte vor Bereich, bei gleicher Güte der nähere Bereich.
  Items := [Scoped('Totalbetrag', 5), Scoped('Total', 4), Scoped('TotalLokal', 1)];
  Assert.AreEqual('Total,TotalLokal,Totalbetrag', Names(Items, TDpccRanking.Order(Items, 'Total', Options)));
end;

procedure TDpccRankingTests.BoostReordersButNeverBeatsBetterMatch;
var
  Options: TDpccRankOptions;
  Items: TDpccCompletionItems;
begin
  Items := [Member('Add', '', 0, 0), Member('AddObject', '', 0, 1), Member('BeginUpdate', '', 0, 2)];
  Options := TDpccRankOptions.Defaults;
  Options.Boost :=
    function(AIndex: Integer): Integer
    begin
      if AIndex = 0 then
      begin
        Result := 0;
      end
      else
      begin
        Result := 99;
      end;
    end;
  // Ohne Präfix gewinnt das Gelernte.
  Assert.AreEqual('AddObject,BeginUpdate,Add', Names(Items, TDpccRanking.Order(Items, '', Options)));
  // Genauer Treffer bleibt vor einem gelernten Präfix-Treffer.
  Assert.AreEqual('Add,AddObject', Names(Items, TDpccRanking.Order(Items, 'Add', Options)));
end;

procedure TDpccRankingTests.PostfixAfterMembers;
var
  Items: TDpccCompletionItems;
begin
  // Postfix-Vorlagen (#188) stehen hinter allen echten Mitgliedern, auch wenn sie genauer passen.
  Items := [Member('tryf', '', 0, 0, TDpccItemKind.Snippet), Member('tryfNext', '', 0, 1),
    Member('TryFoo', '', 0, 2)];
  Items[0].Postfix := True;
  Items[0].FilterText := 'tryf';
  Assert.AreEqual('tryfNext,TryFoo,tryf', Names(Items, TDpccRanking.Order(Items, 'tryf',
    TDpccRankOptions.Defaults)));
  Assert.AreEqual('tryfNext,TryFoo,tryf', Names(Items, TDpccRanking.Order(Items, '', TDpccRankOptions.Defaults)));
end;

procedure TDpccRankingTests.ServerGroupHeaderAndActionLast;
var
  Options: TDpccRankOptions;
  Items: TDpccCompletionItems;
begin
  // Ereignis-Zuweisung (#444): Überschrift „Passt zu …“, die neue Methode immer zuletzt und immer sichtbar.
  Items := [Member('Neue Methode btnSaveClick …', '', 0, 0), Member('FormCreate', 'TForm1', 0, 1),
    Member('Klick', 'TBasis', 1, 2)];
  Items[0].IsAction := True;
  Items[1].ExpectedType := 'TNotifyEvent';
  Items[1].Fits := True;
  Items[2].ExpectedType := 'TNotifyEvent';
  Items[2].Fits := True;
  Options := TDpccRankOptions.Defaults;
  Options.GroupInherited := True;
  Assert.AreEqual('#,FormCreate,Klick,Neue Methode btnSaveClick …', Names(Items, TDpccRanking.Order(Items, '', Options)));
  Assert.AreEqual('#,Klick,Neue Methode btnSaveClick …', Names(Items, TDpccRanking.Order(Items, 'Kl', Options)));
  // Erwarteter Typ (#417): Passende oben, auch wenn ein übriger Eintrag besser zum Präfix passt.
  Items := [Member('Count', '', 0, 0), Member('Capacity', '', 0, 1), Member('Clear', '', 0, 2)];
  Items[0].ExpectedType := 'Integer';
  Items[1].ExpectedType := 'Integer';
  Items[1].Fits := True;
  Items[2].ExpectedType := 'Integer';
  Items[2].Fits := True;
  Assert.AreEqual('#,Capacity,Clear,#,Count', Names(Items, TDpccRanking.Order(Items, 'C', Options)));
  Assert.AreEqual('#,Count', Names(Items, TDpccRanking.Order(Items, 'Cou', Options)));
end;
procedure TDpccRankingTests.FormComponentsComeFirst;
var
  Json: TJSONObject;
  Items: TDpccCompletionItems;
  Options: TDpccRankOptions;
begin
  // Komponenten aus dem Formular (#455): eigene Gruppe vor allem anderen, Typtreffer hinter Namenstreffern.
  Json := TJSONObject.ParseJSONValue('{"label":"btnSave","kind":5,"detail":"TButton","data":{"form":"frmMain",' +
    '"byType":true,"scope":3}}') as TJSONObject;
  try
    Items := [Member('TButton', '', 0, 0, TDpccItemKind.Class_), TDpccServerCompletionProvider.ItemFromLsp(Json, 1),
      Member('btnButtonLeiste', '', 0, 2)];
  finally
    Json.Free;
  end;
  Assert.AreEqual('frmMain', Items[1].Form);
  Assert.IsTrue(Items[1].ByType);
  Items[2].Form := 'frmMain';
  Options := TDpccRankOptions.Defaults;
  Assert.AreEqual('#,btnButtonLeiste,btnSave,#,TButton', Names(Items, TDpccRanking.Order(Items, 'button', Options)));
  // Ohne Formulareinträge keine Überschrift.
  Items := Copy(Items, 0, 1);
  Assert.AreEqual('TButton', Names(Items, TDpccRanking.Order(Items, 'button', Options)));
end;

procedure TDpccRankingTests.VariantFieldsGetBranchTag;
var
  Json: TJSONObject;
  Item: TDpccCompletionItem;
  Tags: TDpccTags;
  Tag: TDpccTag;
  Found: Boolean;
begin
  // Felder varianter Records (#846): data.variant wird zur Marke „Zweig 0“.
  Json := TJSONObject.ParseJSONValue('{"label":"Left","kind":5,"detail":"Integer","data":{"variant":"0",' +
    '"container":"TRect"}}') as TJSONObject;
  try
    Item := TDpccServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.AreEqual('0', Item.VariantBranch);
  Tags := TDpccItemPresentation.Tags(Item);
  Found := False;
  for Tag in Tags do
  begin
    if Tag.Id = TDpccTagId.VariantBranch then
    begin
      Found := True;
      Assert.AreEqual('Zweig 0', Tag.Text);
      Assert.AreEqual('0', Tag.Arg);
      Assert.IsTrue(Tag.Kind = TDpccTagKind.Neutral);
    end;
  end;
  Assert.IsTrue(Found);
  // Ohne Zweig keine Marke.
  Item.VariantBranch := '';
  for Tag in TDpccItemPresentation.Tags(Item) do
  begin
    Assert.IsFalse(Tag.Id = TDpccTagId.VariantBranch);
  end;
end;

procedure TDpccRankingTests.SenderItemsGetHeaderAndTag;
var
  Json: TJSONObject;
  Items: TDpccCompletionItems;
  Options: TDpccRankOptions;
  Tags: TDpccTags;
  Found: Boolean;
  Tag: TDpccTag;
begin
  // Sender mit Typumwandlung (#480): eine Überschrift über der Liste, Marke „als TButton“.
  Json := TJSONObject.ParseJSONValue('{"label":"Caption","kind":10,"detail":"string","data":{"sender":"TButton",' +
    '"senderOf":"btnSave, btnLoad","scope":3}}') as TJSONObject;
  try
    Items := [TDpccServerCompletionProvider.ItemFromLsp(Json, 0)];
  finally
    Json.Free;
  end;
  Assert.AreEqual('TButton', Items[0].Sender);
  Assert.AreEqual('btnSave, btnLoad', Items[0].SenderOf);
  Options := TDpccRankOptions.Defaults;
  Assert.AreEqual('#,Caption', Names(Items, TDpccRanking.Order(Items, 'Cap', Options)));
  Tags := TDpccItemPresentation.Tags(Items[0]);
  Found := False;
  for Tag in Tags do
  begin
    if Tag.Text = 'als TButton' then
    begin
      Found := True;
    end;
  end;
  Assert.IsTrue(Found);
  // Ohne Sender keine Überschrift.
  Items[0].Sender := '';
  Assert.AreEqual('Caption', Names(Items, TDpccRanking.Order(Items, 'Cap', Options)));
end;

procedure TDpccRankingTests.ConversionStandsBeforeOriginal;
const
  Answers: array[0..3] of string = (
    '{"label":"Count.ToString","kind":5,"detail":"Integer","filterText":"Count","data":{"expected":"string",' +
      '"conversion":"string","convertFrom":"Count","scope":0}}',
    '{"label":"Text","kind":5,"detail":"string","data":{"expected":"string","fits":true}}',
    '{"label":"Count","kind":5,"detail":"Integer","data":{"expected":"string"}}',
    '{"label":"Preis","kind":5,"detail":"Double","data":{"expected":"Integer","lossy":"Double"}}');
var
  Json: TJSONObject;
  Items: TDpccCompletionItems;
  Options: TDpccRankOptions;
  Tag: TDpccTag;
  Found: Boolean;
  Answer: string;
begin
  // Typkonvertierung (#490): „Count.ToString → string“ direkt über Count, gefiltert nach dem Namen des Originals.
  Items := nil;
  for Answer in Answers do
  begin
    Json := TJSONObject.ParseJSONValue(Answer) as TJSONObject;
    try
      Items := Items + [TDpccServerCompletionProvider.ItemFromLsp(Json, Length(Items))];
    finally
      Json.Free;
    end;
  end;
  Assert.AreEqual('string', Items[0].Conversion);
  Assert.AreEqual('Count', Items[0].ConvertFrom);
  Assert.AreEqual('Count', Items[0].FilterText);
  Assert.AreEqual('Double', Items[3].Lossy);
  Items[1].Fits := True;
  Options := TDpccRankOptions.Defaults;
  Assert.AreEqual('#,Count.ToString,Count', Names(Items, TDpccRanking.Order(Items, 'Cou', Options)));
  Assert.AreEqual('#,Text,#,Count.ToString,Count,Preis', Names(Items, TDpccRanking.Order(Items, '', Options)));
  // Ohne sichtbares Original auch keine Umwandlung.
  Assert.AreEqual('#,Text', Names(Items, TDpccRanking.Order(Items, 'Tex', Options)));
  Found := False;
  for Tag in TDpccItemPresentation.Tags(Items[0]) do
  begin
    if Tag.Text = '→ string' then
    begin
      Found := True;
    end;
  end;
  Assert.IsTrue(Found);
end;

procedure TDpccRankingTests.AttributesShowAsType;
var
  Json: TJSONObject;
  Item: TDpccCompletionItem;
begin
  // Attribute nach "[" (#465): Art „type“ wie in der Code-Insight-Liste der IDE, dahinter die Konstruktorparameter.
  Json := TJSONObject.ParseJSONValue('{"label":"TestCase","kind":7,"detail":"(const AName: string)",' +
    '"insertText":"TestCase","data":{"attribute":true}}') as TJSONObject;
  try
    Item := TDpccServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.IsTrue(Item.Attribute);
  Assert.AreEqual('type', TDpccItemPresentation.KindWord(Item));
  Json := TJSONObject.ParseJSONValue('{"label":"TKunde","kind":7}') as TJSONObject;
  try
    Item := TDpccServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.IsFalse(Item.Attribute);
  Assert.AreEqual('type', TDpccItemPresentation.KindWord(Item));
end;

procedure TDpccRankingTests.TypeArgumentsGetHeaderAndFooter;
var
  Json: TJSONObject;
  Items: TDpccCompletionItems;
  Options: TDpccRankOptions;
begin
  // Typargumente (#450): eine Überschrift mit dem Constraint über der Liste, ausgeblendete Arten für die Fußzeile.
  Json := TJSONObject.ParseJSONValue('{"label":"TKunde","kind":7,"detail":"Listen","data":{"typeParam":"T",' +
    '"constraint":"class","constraintHint":"classes","hiddenKinds":"records,enums"}}') as TJSONObject;
  try
    Items := [TDpccServerCompletionProvider.ItemFromLsp(Json, 0)];
  finally
    Json.Free;
  end;
  Assert.AreEqual('T', Items[0].TypeParam);
  Assert.AreEqual('class', Items[0].Constraint);
  Assert.AreEqual('classes', Items[0].ConstraintHint);
  Assert.AreEqual('records,enums', TDpccItemPresentation.HiddenKinds(Items));
  Options := TDpccRankOptions.Defaults;
  Assert.AreEqual('#,TKunde', Names(Items, TDpccRanking.Order(Items, 'TK', Options)));
  Items[0].TypeParam := '';
  Assert.AreEqual('TKunde', Names(Items, TDpccRanking.Order(Items, 'TK', Options)));
end;

procedure TDpccRankingTests.DataNamesCarrySource;
var
  Json: TJSONObject;
  Items: TDpccCompletionItems;
begin
  // Feld- und Parameternamen (#461): Datenmenge und SQL-Anweisung für die Fußzeile.
  Json := TJSONObject.ParseJSONValue('{"label":"CUSTOMER_ID","kind":5,"detail":"Integer","data":{' +
    '"dataSet":"qryOrders","dataSource":"select CUSTOMER_ID from ORDERS"}}') as TJSONObject;
  try
    Items := [Member('Capacity', '', 0, 0), TDpccServerCompletionProvider.ItemFromLsp(Json, 0)];
  finally
    Json.Free;
  end;
  Assert.AreEqual('qryOrders', Items[1].DataSet);
  Assert.AreEqual('select CUSTOMER_ID from ORDERS', TDpccItemPresentation.DataSource(Items));
  Assert.AreEqual('', TDpccItemPresentation.DataSource(Copy(Items, 0, 1)));
end;

procedure TDpccRankingTests.SameNameVariantsFollowTheActive;
const
  Lines: array[0..2] of string = (
    '{"label":"TBitmap","kind":7,"data":{"scope":5,"unit":"Winapi.Windows","action":"sameName",' +
      '"sameNameOf":"Vcl.Graphics","sameNameInsert":"prefix","sameNameUnits":["Vcl.Graphics","Winapi.Windows"],' +
      '"sameNameHidden":["FMX.Graphics.TBitmap"]},"textEdit":{"range":{"start":{"line":8,"character":10},' +
      '"end":{"line":8,"character":15}},"newText":"Winapi.Windows.TBitmap"}}',
    '{"label":"TBitmap","kind":7,"data":{"scope":5,"unit":"Vcl.Graphics","sameNameActive":true,' +
      '"sameNameUnits":["Vcl.Graphics","Winapi.Windows"],"sameNameHidden":["FMX.Graphics.TBitmap"]}}',
    '{"label":"TBitmapImage","kind":7,"data":{"scope":5,"unit":"Vcl.Graphics"}}');
var
  Json: TJSONObject;
  Items: TDpccCompletionItems;
  Index: Integer;
  Order: TArray<Integer>;
  Found: Boolean;
  Tag: TDpccTag;
  Details: TDpccItemDetails;
begin
  // Gleiche Namen aus verschiedenen Units (#475): die Variante direkt unter der aktiven.
  Items := nil;
  for Index := 0 to High(Lines) do
  begin
    Json := TJSONObject.ParseJSONValue(Lines[Index]) as TJSONObject;
    try
      Items := Items + [TDpccServerCompletionProvider.ItemFromLsp(Json, Index)];
    finally
      Json.Free;
    end;
  end;
  Order := TDpccRanking.Order(Items, 'TBitm', TDpccRankOptions.Defaults);
  Assert.AreEqual(3, Integer(Length(Order)));
  // Der Server schickt die Variante hier vor der aktiven; sie rückt dahinter.
  Assert.AreEqual(1, Order[0]);
  Assert.AreEqual(0, Order[1]);
  Assert.AreEqual(2, Order[2]);
  Found := False;
  for Tag in TDpccItemPresentation.Tags(Items[1]) do
  begin
    if Tag.Id = TDpccTagId.Active then
    begin
      Found := True;
    end;
  end;
  Assert.IsTrue(Found);
  for Tag in TDpccItemPresentation.Tags(Items[0]) do
  begin
    Assert.IsFalse(Tag.Id = TDpccTagId.Active);
  end;
  Assert.AreEqual('FMX.Graphics.TBitmap', string.Join(',', TDpccItemPresentation.SameNameHidden(Items)));
  Details := Default(TDpccItemDetails);
  TDpccItemPresentation.AddSameName(Items[0], Details);
  Assert.AreEqual('Winapi.Windows', Details.SameNameThis);
  Assert.AreEqual('prefix', Details.SameNameInsert);
  Assert.AreEqual(2, Integer(Length(Details.SameNameUnits)));
  Assert.IsFalse(Details.IsEmpty);
end;

procedure TDpccRankingTests.InheritedCallsFirstWithTags;
const
  Lines: array[0..3] of string = (
    '{"label":"Free","kind":2,"data":{"container":"TObject","depth":3}}',
    '{"label":"CreateNew(AOwner, Dummy)","filterText":"CreateNew","kind":4,"detail":"TBaseView",' +
      '"data":{"container":"TBaseView","depth":1,"inheritedMatch":"other","inheritedAbstract":["TBaseView.Zeichnen"]}}',
    '{"label":"Create(AOwner)","filterText":"Create","kind":4,"detail":"TBaseView",' +
      '"data":{"container":"TBaseView","depth":1,"inheritedMatch":"same","inheritedAbstract":["TBaseView.Zeichnen"]}}',
    '{"label":"CreateParented(ParentWindow)","filterText":"CreateParented","kind":4,"detail":"TWinControl",' +
      '"data":{"container":"TWinControl","depth":2,"inheritedMatch":"other"}}');
var
  Json: TJSONObject;
  Items: TDpccCompletionItems;
  Index: Integer;
  Tags: TDpccTags;
  Found: Boolean;
  Tag: TDpccTag;
begin
  // Nach "inherited " (#482): der Aufruf mit gleichen Parametern zuerst, dann die übrigen Konstruktoren.
  Items := nil;
  for Index := 0 to High(Lines) do
  begin
    Json := TJSONObject.ParseJSONValue(Lines[Index]) as TJSONObject;
    try
      Items := Items + [TDpccServerCompletionProvider.ItemFromLsp(Json, Index)];
    finally
      Json.Free;
    end;
  end;
  Assert.AreEqual('Create(AOwner),CreateNew(AOwner, Dummy),CreateParented(ParentWindow)',
    Names(Items, TDpccRanking.Order(Items, 'Cre', TDpccRankOptions.Defaults)));
  Tags := TDpccItemPresentation.Tags(Items[2]);
  Found := False;
  for Tag in Tags do
  begin
    if Tag.Id = TDpccTagId.SameParams then
    begin
      Found := True;
    end;
  end;
  Assert.IsTrue(Found);
  // Weitere Konstruktoren tragen die deklarierende Klasse.
  Found := False;
  for Tag in TDpccItemPresentation.Tags(Items[3]) do
  begin
    if Tag.Text = 'TWinControl' then
    begin
      Found := True;
    end;
  end;
  Assert.IsTrue(Found);
  Assert.AreEqual('TBaseView.Zeichnen', string.Join(',', TDpccItemPresentation.InheritedAbstract(Items)));
end;

procedure TDpccRankingTests.UsesUnitsGroupedWithHeaders;
const
  Lines: array[0..3] of string = (
    '{"label":"Spring.Collections.Generic","kind":9,"data":{"usesGroup":"library","usesFilter":"Generic"}}',
    '{"label":"System.Generics.Collections","kind":9,' +
      '"detail":"$(BDS)\\source\\rtl\\common\\System.Generics.Collections.pas","data":{"usesGroup":"rtl",' +
      '"usesFilter":"Generics.Collections","usesTypes":["TList<T>","TObjectList<T>"],"usesTypeCount":7,' +
      '"usesHidden":["System.SysUtils"]}}',
    '{"label":"System.Generics.Defaults","kind":9,"data":{"usesGroup":"rtl","usesFilter":"Generics.Defaults",' +
      '"usesElsewhere":"implementation"}}',
    '{"label":"uGeneratorBeleg","kind":9,"detail":"C:\\P\\uGeneratorBeleg.pas","data":{"usesGroup":"project",' +
      '"usesCycle":"uGeneratorBeleg → Haupt"}}');
var
  Json: TJSONObject;
  Items: TDpccCompletionItems;
  Index: Integer;
  Tags: TDpccTags;
  Details: TDpccItemDetails;
begin
  // uses-Abschnitt (#469): Projekt vor RTL/VCL vor Drittanbietern, je Gruppe eine Überschrift; gefiltert wird nach
  // dem Namensteil ab dem Getippten.
  Items := nil;
  for Index := 0 to High(Lines) do
  begin
    Json := TJSONObject.ParseJSONValue(Lines[Index]) as TJSONObject;
    try
      Items := Items + [TDpccServerCompletionProvider.ItemFromLsp(Json, Index)];
    finally
      Json.Free;
    end;
  end;
  Assert.AreEqual('Generics.Collections', Items[1].FilterText);
  Assert.AreEqual('#,uGeneratorBeleg,#,System.Generics.Collections,System.Generics.Defaults,#,' +
    'Spring.Collections.Generic', Names(Items, TDpccRanking.Order(Items, 'Gener', TDpccRankOptions.Defaults)));
  Assert.AreEqual('#,System.Generics.Defaults',
    Names(Items, TDpccRanking.Order(Items, 'Defau', TDpccRankOptions.Defaults)));
  // Zirkelbezug als Marke in Fehlerfarbe, anderer Abschnitt rechts, kein Dateiname.
  Tags := TDpccItemPresentation.Tags(Items[3]);
  Assert.AreEqual(1, Integer(Length(Tags)));
  Assert.IsTrue(Tags[0].Kind = TDpccTagKind.Error);
  Assert.IsTrue(Tags[0].Id = TDpccTagId.Cycle);
  Assert.AreEqual('', TDpccItemPresentation.Detail(Items[3]));
  Assert.AreEqual('bereits im implementation-Teil', TDpccItemPresentation.Detail(Items[2]));
  Assert.AreEqual(1, Integer(Length(TDpccItemPresentation.UsesHidden(Items))));
  Assert.AreEqual('System.SysUtils', TDpccItemPresentation.UsesHidden(Items)[0]);
  // Detailpanel ohne Server: Deklaration, Pfad, Typen samt Gesamtzahl.
  Details := TDpccItemPresentation.UsesDetails(Items[1]);
  Assert.AreEqual('unit System.Generics.Collections', Details.Declaration);
  Assert.AreEqual('$(BDS)\source\rtl\common\System.Generics.Collections.pas', Details.UnitPath);
  Assert.AreEqual(2, Integer(Length(Details.UnitTypes)));
  Assert.AreEqual(7, Details.UnitTypeCount);
  Assert.IsFalse(Details.IsEmpty);
  Assert.AreEqual('uGeneratorBeleg → Haupt', TDpccItemPresentation.UsesDetails(Items[3]).UsesCycle);
  Assert.AreEqual('implementation', TDpccItemPresentation.UsesDetails(Items[2]).UsesElsewhere);
  // Ohne Gruppe (Schalter aus): keine Überschriften.
  for Index := 0 to High(Items) do
  begin
    Items[Index].UsesGroup := '';
  end;
  Assert.IsFalse(Names(Items, TDpccRanking.Order(Items, 'Gener', TDpccRankOptions.Defaults)).Contains('#'));
end;

{ TDpccUsageTests }

procedure TDpccUsageTests.RecordsBoostAndMarks;
var
  Usage: TDpccUsage;
  Begin_, Add: TDpccCompletionItem;
  Round: Integer;
begin
  Usage := TDpccUsage.Create;
  try
    Begin_ := Member('BeginUpdate', 'TStrings', 1, 0);
    Add := Member('Add', 'TStrings', 1, 1);
    Assert.AreEqual(0, Usage.Boost(Begin_));
    for Round := 1 to 3 do
    begin
      Usage.Record_(Begin_);
    end;
    Assert.AreEqual(75, Usage.Boost(Begin_), '3 × 15 + 30 für zuletzt');
    Assert.IsTrue(Usage.Mark(Begin_) = TDpccUsageMark.Recent);
    Usage.Record_(Add);
    Assert.IsTrue(Usage.Mark(Add) = TDpccUsageMark.Recent);
    Assert.IsTrue(Usage.Mark(Begin_) = TDpccUsageMark.None, 'erst ab 5 Übernahmen häufig');
    Usage.Record_(Begin_);
    Usage.Record_(Begin_);
    Usage.Record_(Add);
    Assert.IsTrue(Usage.Mark(Begin_) = TDpccUsageMark.Frequent);
    Assert.AreEqual(60, Usage.Boost(Begin_), 'gedeckelt, nicht mehr zuletzt');
  finally
    Usage.Free;
  end;
end;

procedure TDpccUsageTests.SavesLoadsAndClears;
var
  Usage, Loaded: TDpccUsage;
  FileName: string;
  Item: TDpccCompletionItem;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'DpccUsage' + IntToStr(TThread.GetTickCount64) + '.json');
  Item := Member('BeginUpdate', 'TStrings', 1, 0);
  Usage := TDpccUsage.Create;
  Loaded := TDpccUsage.Create;
  try
    Usage.Record_(Item);
    Usage.Record_(Item);
    Assert.IsTrue(Usage.Changed);
    Usage.SaveToFile(FileName);
    Assert.IsFalse(Usage.Changed);
    Loaded.LoadFromFile(FileName);
    Assert.AreEqual(Usage.Boost(Item), Loaded.Boost(Item));
    Assert.IsTrue(Loaded.Mark(Item) = TDpccUsageMark.Recent);
    Loaded.Clear;
    Assert.AreEqual(0, Loaded.Boost(Item));
    // Fehlende Datei: leer, kein Fehler.
    Loaded.LoadFromFile(FileName + '.fehlt');
    Assert.AreEqual(0, Integer(Loaded.Count));
  finally
    Loaded.Free;
    Usage.Free;
    TFile.Delete(FileName);
  end;
end;

procedure TDpccUsageTests.LearnedEntryRisesInController;
var
  View: TRecordingView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
  Usage: TDpccUsage;
  Round: Integer;
  Item: TDpccCompletionItem;
begin
  // Akzeptanz #418: nach dreimaliger Übernahme von BeginUpdate steht es ohne Präfix vor Add.
  View := TRecordingView.Create;
  ViewRef := View;
  Usage := TDpccUsage.Create;
  Controller := TDpccCompletionController.Create(TDpccFixedCompletionProvider.Create(
    [Member('Add', 'TStrings', 0, 0), Member('BeginUpdate', 'TStrings', 0, 1)]) as IDpccCompletionProvider, ViewRef);
  try
    Controller.Usage := Usage;
    for Round := 1 to 3 do
    begin
      Usage.Record_(Member('BeginUpdate', 'TStrings', 0, 1));
    end;
    Controller.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('BeginUpdate,Add', View.Names);
    Assert.IsTrue(Controller.SelectedItem(Item));
    Assert.IsTrue(Item.Usage = TDpccUsageMark.Recent);
  finally
    Controller.Free;
    Usage.Free;
  end;
end;

procedure TDpccUsageTests.SelectionSkipsHeaders;
var
  View: TRecordingView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
begin
  View := TRecordingView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(TDpccFixedCompletionProvider.Create(StringsItems)
    as IDpccCompletionProvider, ViewRef);
  try
    Controller.GroupInherited := True;
    Controller.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.AreEqual('Sort,#,Add,BeginUpdate,#,Assign', View.Names);
    Assert.AreEqual(0, View.Selected);
    Controller.HandleKey(TDpccNavigationKey.Down);
    Assert.AreEqual(2, View.Selected, 'Überschrift übersprungen');
    Controller.HandleKey(TDpccNavigationKey.Up);
    Assert.AreEqual(0, View.Selected);
    Controller.HandleKey(TDpccNavigationKey.Last);
    Assert.AreEqual(5, View.Selected);
    Controller.HandleKey(TDpccNavigationKey.Up);
    Assert.AreEqual(3, View.Selected);
  finally
    Controller.Free;
  end;
end;

procedure TDpccUsageTests.TypingDiscardsGuardOffer;
var
  View: TRecordingView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
  Json: TJSONObject;
  Guard: TDpccCompletionItem;
  Item: TDpccCompletionItem;
begin
  // Freigabe absichern (#489): Das Angebot ist gewählt; jedes getippte Zeichen schließt die Liste.
  Json := TJSONObject.ParseJSONValue('{"label":"Mit try…finally absichern","kind":15,"detail":"List.Free",' +
    '"data":{"guard":"newLine"}}') as TJSONObject;
  try
    Guard := TDpccServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.IsTrue(Guard.Guard);
  Assert.IsTrue(TDpccItemPresentation.Guarding([Guard]));
  Assert.IsFalse(TDpccItemPresentation.Guarding([Guard, Member('Add', 'TStrings', 0, 0)]));
  View := TRecordingView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(TDpccFixedCompletionProvider.Create([Guard]) as
    IDpccCompletionProvider, ViewRef);
  try
    Controller.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.SelectedItem(Item));
    Assert.AreEqual('Mit try…finally absichern', Item.Name);
    Controller.UpdatePrefix('L');
    Assert.IsFalse(Controller.Active);
  finally
    Controller.Free;
  end;
end;

function MemberContext(const APrefix: string): TDpccContext;
begin
  Result := Context(APrefix);
  Result.Kind := TDpccContextKind.MemberAccess;
end;

procedure TDpccUsageTests.RestOnlyInMemberListsByDefault;
var
  View: TRecordingView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
begin
  View := TRecordingView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(TDpccFixedCompletionProvider.Create(RestItems) as
    IDpccCompletionProvider, ViewRef);
  try
    Controller.ListMode := TDpccListMode.Rest;
    // Strg+Leer (alle sichtbaren Namen): nur Treffer, solange der Bereich Members ist.
    Controller.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Controller.UpdatePrefix('As');
    Assert.AreEqual('Assign', View.Names);
    Assert.AreEqual(-1, Controller.RestStart);
    // Nach ".": Treffer, darunter der Rest.
    Controller.Start(MemberContext(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Controller.UpdatePrefix('As');
    Assert.AreEqual('Assign,#,Add,BeginUpdate,Clear,Sort', View.Names);
    Assert.AreEqual(0, View.Selected, 'Bester Treffer gewählt');
    Assert.AreEqual(2, Controller.RestStart);
    // Bild↓/Ende überspringen die Überschrift und erreichen das Ende des Rests.
    Controller.HandleKey(TDpccNavigationKey.Down);
    Assert.AreEqual(2, View.Selected, 'Überschrift übersprungen');
    Controller.HandleKey(TDpccNavigationKey.Last);
    Assert.AreEqual(5, View.Selected);
    // Überall: auch ohne ".".
    Controller.ListScope := TDpccListScope.Everywhere;
    Controller.Start(Context(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Controller.UpdatePrefix('As');
    Assert.AreEqual('Assign,#,Add,BeginUpdate,Clear,Sort', View.Names);
  finally
    Controller.Free;
  end;
end;

procedure TDpccUsageTests.RestWithoutMatchSelectsNothing;
var
  View: TRecordingView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
  Item: TDpccCompletionItem;
begin
  View := TRecordingView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(TDpccFixedCompletionProvider.Create(RestItems) as
    IDpccCompletionProvider, ViewRef);
  try
    Controller.ListMode := TDpccListMode.All;
    Controller.Start(MemberContext(''));
    Assert.IsTrue(Wait(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    // Kein Treffer für "Zq": alles sichtbar, nichts gewählt; Enter gehört dem Editor.
    Controller.UpdatePrefix('Zq');
    Assert.AreEqual('Add,Assign,BeginUpdate,Clear,Sort', View.Names);
    Assert.AreEqual(0, Controller.RestStart);
    Assert.IsTrue(Controller.Passive);
    Assert.AreEqual(-1, View.Selected);
    Assert.IsFalse(Controller.CanCommitOnCharacter);
    // Eine Pfeiltaste wählt den ersten Eintrag.
    Controller.HandleKey(TDpccNavigationKey.Down);
    Assert.IsFalse(Controller.Passive);
    Assert.IsTrue(Controller.SelectedItem(Item));
    Assert.AreEqual('Add', Item.Name);
    // Mit Treffer wieder der beste gewählt.
    Controller.UpdatePrefix('Cl');
    Assert.AreEqual('Clear,Add,Assign,BeginUpdate,Sort', View.Names);
    Assert.AreEqual(0, View.Selected);
    Assert.IsFalse(Controller.Passive);
  finally
    Controller.Free;
  end;
end;

procedure TDpccUsageTests.BrokenFileSetAsideLockedFileKept;
var
  Usage: TDpccUsage;
  FileName: string;
  Lock: TFileStream;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'DpccUsage' + IntToStr(Random(MaxInt)) + '.json');
  Usage := TDpccUsage.Create;
  try
    TFile.WriteAllText(FileName, '{"entries": 5}');
    Assert.IsTrue(Usage.LoadFromFile(FileName) = TDpccDataLoad.Renewed);
    Assert.IsTrue(TFile.Exists(FileName + TDpccDataFile.cDefectExtension), 'beiseitegelegt');
    Usage.Record_(Member('BeginUpdate', 'TStrings', 1, 0));
    Assert.IsTrue(Usage.SaveToFile(FileName));
    Lock := TFileStream.Create(FileName, fmOpenRead or fmShareExclusive);
    try
      Assert.IsTrue(Usage.LoadFromFile(FileName) = TDpccDataLoad.Kept);
    finally
      Lock.Free;
    end;
    Assert.AreEqual(0, Integer(Usage.Count));
    Usage.Record_(Member('EndUpdate', 'TStrings', 1, 0));
    Assert.IsFalse(Usage.SaveToFile(FileName), 'beim Lesen gesperrt: nicht überschreiben');
    Assert.Contains(TFile.ReadAllText(FileName, TEncoding.UTF8), 'beginupdate');
    Assert.DoesNotContain(TFile.ReadAllText(FileName, TEncoding.UTF8), 'endupdate');
  finally
    Usage.Free;
    System.SysUtils.DeleteFile(FileName);
    System.SysUtils.DeleteFile(FileName + TDpccDataFile.cDefectExtension);
  end;
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TDpccDataFile.ForgetReports;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccRankingTests);
  TDUnitX.RegisterTestFixture(TDpccUsageTests);

end.
