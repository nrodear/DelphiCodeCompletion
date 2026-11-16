unit dpcc.Common.Lsp.Completion.Handle.Tests;

// Charakterisierungstests für textDocument/completion über den Dispatcher (Block H
// Schritt 0): Reihenfolge und Exklusivität der Fälle in TLspCompletion.Handle – Schnellbefehle,
// Feldnamen im String, Freigabe absichern, Mengen, Aufzählungswerte vorab, Interface-Hinweise,
// Sender, Deklarieren am Ende, abschaltbare Schlüsselwörter und gestaffelte Teilergebnisse.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  System.JSON,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Index.Contract,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.Lsp.ConditionalSymbols,
  dpcc.Common.Lsp.Completion;

type
  [TestFixture]
  TLspCompletionHandleTests = class
  private
    FIndex: ISymbolIndex;
    FStore: IDocumentStore;
    FCompletion: TLspCompletion;
    FDispatcher: TJsonRpcDispatcher;
    FFiles: TDictionary<string, string>;
    FForm: string;
    FProgress: TArray<string>;
    FId: Integer;
    /// <summary>Unit für den Index und für ReadText.</summary>
    procedure AddUnit(const AFileName, AText: string);
    /// <summary>Fragt an der Stelle von "|" in AText; ATrigger und AToken '' = ohne. Der Aufrufer gibt frei.
    /// </summary>
    function Complete(const AText: string): TJSONObject; overload;
    function Complete(const AText, ATrigger, AToken: string): TJSONObject; overload;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DataNameInStringIsExclusive;
    [Test]
    procedure SetModeReturnsOnlyEnumValues;
    [Test]
    procedure BracketWithoutSetIsEmpty;
    [Test]
    procedure EnumValuesPrecedeCollected;
    [Test]
    procedure InterfaceHintComesFirst;
    [Test]
    procedure InterfaceBatchIsExclusive;
    [Test]
    procedure KeywordsCanBeSwitchedOff;
    [Test]
    procedure PartialSendsEnumsThenStages;
    [Test]
    procedure SenderCastIsExclusive;
    /// <summary>#452: Feld vom Typ TCustomerList in einem Projekt mit F-Konvention.</summary>
    [Test]
    procedure NameSuggestionsFollowProjectConvention;
    /// <summary>#452: ohne Konvention kein Präfix, vergebene Namen mit Ziffer.</summary>
    [Test]
    procedure NameSuggestionsWithoutConvention;
    /// <summary>#452: Vorgabe der Projektdatei geht vor; completion.nameSuggestions aus schaltet ab.</summary>
    [Test]
    procedure NameSuggestionsForcedAndSwitchedOff;
    /// <summary>#88: Strg+Leer in einem ///-Block, dessen Routine einen Parameter mehr hat, bietet nur
    /// „Parameter abgleichen“; completeBlocks.docComment aus schaltet es ab.</summary>
    [Test]
    procedure DocBlockOffersParameterAdjust;
    /// <summary>#102: Nach {$IFDEF  kommen die Symbole mit Herkunft, nicht geltende abgeschwächt;
    /// directives.completion aus lässt die Liste leer.</summary>
    [Test]
    procedure DirectiveSymbolsWithOrigin;
    /// <summary>#102: In einer offenen Direktive kommen die Direktivennamen mit Beschreibung, nach {$WARN  die
    /// Warnungen (aus dpcc.Common.Lsp.Completion.Directives, Rückbau R2).</summary>
    [Test]
    procedure DirectiveNamesAndWarnings;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Documents.Providers.DocumentStore,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.Extractor;

const
  HauptFile = 'C:\P\Haupt.pas';

  TypenFile = 'C:\P\Typen.pas';
  UnitTypen =
    'unit Typen;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TAlign = (alNone, alTop,'#13#10 +
    '    alClient);'#13#10 +
    '  TAnchorKind = (akLeft, akTop, akRight, akBottom);'#13#10 +
    '  TAnchors = set of TAnchorKind;'#13#10 +
    '  TControl = class'#13#10 +
    '    Align: TAlign;'#13#10 +
    '    Anchors: TAnchors;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

  /// <summary>Routine mit Zugriff auf Typen; ABody steht zwischen begin und end.</summary>
  function EnumSource(const ABody: string): string;
  begin
    Result :=
      'unit Haupt;'#13#10 +
      'interface'#13#10 +
      'uses Typen;'#13#10 +
      'implementation'#13#10 +
      'procedure Setze(C: TControl; List: TArray<Integer>);'#13#10 +
      'begin'#13#10 +
      ABody + #13#10 +
      'end;'#13#10 +
      'end.';
  end;

{ TLspCompletionHandleTests }

procedure TLspCompletionHandleTests.WarmUpFirstUse;
begin
  Setup;
  try
    DataNameInStringIsExclusive;
  finally
    TearDown;
  end;
  Setup;
  try
    PartialSendsEnumsThenStages;
  finally
    TearDown;
  end;
end;

procedure TLspCompletionHandleTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FStore := TDocumentStore.Create;
  FFiles := TDictionary<string, string>.Create;
  FForm := '';
  FProgress := nil;
  FId := 0;
  FCompletion := TLspCompletion.Create(FStore, FIndex);
  FCompletion.Hooks.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      if SameText(ExtractFileExt(AFileName), '.dfm') then
      begin
        AText := FForm;
        Exit(FForm <> '');
      end;
      Result := FFiles.TryGetValue(LowerCase(AFileName), AText);
    end;
  FCompletion.Hooks.Notify :=
    procedure(const AMethod: string; AParams: TJSONObject)
    begin
      try
        FProgress := FProgress + [AParams.ToJSON];
      finally
        AParams.Free;
      end;
    end;
  FDispatcher := TJsonRpcDispatcher.Create;
  FCompletion.Attach(FDispatcher);
end;

procedure TLspCompletionHandleTests.TearDown;
begin
  FDispatcher.Free;
  FCompletion.Free;
  FFiles.Free;
  FStore := nil;
  FIndex := nil;
  // Von den Tests gefüllt; der Leckmonitor zählte die Felder sonst dem Test an.
  FProgress := nil;
  FForm := '';
end;

procedure TLspCompletionHandleTests.AddUnit(const AFileName, AText: string);
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(AText, AFileName, nil));
  FFiles.AddOrSetValue(LowerCase(AFileName), AText);
end;

function TLspCompletionHandleTests.Complete(const AText: string): TJSONObject;
begin
  Result := Complete(AText, '', '');
end;

function TLspCompletionHandleTests.Complete(const AText, ATrigger, AToken: string): TJSONObject;
var
  Marker, Index, Line, LineStart: Integer;
  Text, Uri, Params: string;
  Request, Response: TJSONObject;
begin
  Marker := Pos('|', AText);
  if Marker = 0 then
  begin
    raise Exception.Create('Marker "|" fehlt');
  end;
  Line := 0;
  LineStart := 1;
  for Index := 1 to Marker - 1 do
  begin
    if AText[Index] = #10 then
    begin
      Inc(Line);
      LineStart := Index + 1;
    end;
  end;
  Text := Copy(AText, 1, Marker - 1) + Copy(AText, Marker + 1, MaxInt);
  Uri := TDocumentUris.FromPath(HauptFile);
  FStore.Close(Uri);
  FStore.Open(Uri, 'delphi', 1, Text);
  Params := '{"textDocument":{"uri":"' + Uri.Replace('\', '\\') + '"},"position":{"line":' + IntToStr(Line) +
    ',"character":' + IntToStr(Marker - LineStart) + '}';
  if ATrigger <> '' then
  begin
    Params := Params + ',"context":{"triggerKind":2,"triggerCharacter":"' + ATrigger + '"}';
  end;
  if AToken <> '' then
  begin
    Params := Params + ',"partialResultToken":"' + AToken + '"';
  end;
  Params := Params + '}';
  Inc(FId);
  Request := TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","id":' + IntToStr(FId) +
    ',"method":"textDocument/completion","params":' + Params + '}') as TJSONObject;
  try
    Response := FDispatcher.DispatchMessage(Request);
  finally
    Request.Free;
  end;
  Assert.IsNotNull(Response);
  try
    Assert.IsTrue(Response.GetValue('result') is TJSONObject, Response.ToJSON);
    Result := Response.GetValue('result').Clone as TJSONObject;
  finally
    Response.Free;
  end;
end;

/// <summary>Labels der Einträge, mit Leerzeichen getrennt.</summary>
function Labels(AResult: TJSONObject): string;
var
  Items: TJSONArray;
  Index: Integer;
begin
  Result := '';
  Items := AResult.GetValue('items') as TJSONArray;
  for Index := 0 to Items.Count - 1 do
  begin
    Result := Result + ' ' + (Items.Items[Index] as TJSONObject).GetValue<string>('label');
  end;
  Result := Result.Trim;
end;

function ItemCount(AResult: TJSONObject): Integer;
begin
  Result := (AResult.GetValue('items') as TJSONArray).Count;
end;

function ItemAt(AResult: TJSONObject; AIndex: Integer): TJSONObject;
begin
  Result := (AResult.GetValue('items') as TJSONArray).Items[AIndex] as TJSONObject;
end;

function Occurrences(const AText, AWord: string): Integer;
var
  Start: Integer;
begin
  Result := 0;
  Start := Pos(AWord, AText);
  while Start > 0 do
  begin
    Inc(Result);
    Start := Pos(AWord, AText, Start + 1);
  end;
end;

procedure TLspCompletionHandleTests.DataNameInStringIsExclusive;
const
  Form =
    'object frmOrders: TfrmOrders'#13#10 +
    '  object qryOrders: TSQLQuery'#13#10 +
    '    SQL.Strings = ('#13#10 +
    '      ''select O.CUSTOMER_ID, O.CURRENCY, O.TOTAL from ORDERS O where O.ID = :OrderId'')'#13#10 +
    '  end'#13#10 +
    'end'#13#10;
var
  Answer: TJSONObject;
begin
  FForm := Form;
  Answer := Complete('unit Haupt;'#13#10'{$R *.dfm}'#13#10'  qryOrders.FieldByName(''cu|'').AsInteger;'#13#10);
  try
    Assert.AreEqual('CUSTOMER_ID CURRENCY TOTAL', Labels(Answer));
  finally
    Answer.Free;
  end;
  // Zur Laufzeit erzeugte Datenmenge: im String nichts, auch keine Namen aus dem Gültigkeitsbereich.
  Answer := Complete('unit Haupt;'#13#10'{$R *.dfm}'#13#10'  qryNeu.FieldByName(''cu|'')'#13#10);
  try
    Assert.AreEqual(0, ItemCount(Answer));
    Assert.IsFalse(Answer.GetValue<Boolean>('isIncomplete'));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.SetModeReturnsOnlyEnumValues;
var
  Answer: TJSONObject;
begin
  AddUnit(TypenFile, UnitTypen);
  Answer := Complete(EnumSource('  C.Anchors := [akLeft, |];'));
  try
    Assert.AreEqual('akLeft akTop akRight akBottom', Labels(Answer));
    Assert.AreEqual('TAnchorKind', ItemAt(Answer, 0).GetValue<string>('data.setOf'));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.BracketWithoutSetIsEmpty;
var
  Answer: TJSONObject;
begin
  AddUnit(TypenFile, UnitTypen);
  Answer := Complete(EnumSource('  List[0] := List[|];'), '[', '');
  try
    Assert.AreEqual(0, ItemCount(Answer), Answer.ToJSON);
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.EnumValuesPrecedeCollected;
var
  Answer: TJSONObject;
  Text: string;
begin
  AddUnit(TypenFile, UnitTypen);
  Answer := Complete(EnumSource('  C.Align := |;'));
  try
    Text := Labels(Answer);
    Assert.IsTrue(Text.StartsWith('alNone alTop alClient '), Text);
    // Aus der übrigen Liste nicht noch einmal.
    Assert.AreEqual(1, Occurrences(' ' + Text + ' ', ' alNone '), Text);
    Assert.IsTrue(Occurrences(' ' + Text + ' ', ' TControl ') = 1, Text);
    Assert.AreEqual('00000', ItemAt(Answer, 0).GetValue<string>('sortText'));
  finally
    Answer.Free;
  end;
end;

const
  BasisFile = 'C:\P\Basis.pas';
  UnitBasis =
    'unit Basis;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  IFlush = interface'#13#10 +
    '    procedure Flush;'#13#10 +
    '  end;'#13#10 +
    '  IExporter = interface(IFlush)'#13#10 +
    '    procedure Export(const AFileName: string);'#13#10 +
    '    function GetName: string;'#13#10 +
    '    procedure SetName(const AValue: string);'#13#10 +
    '  end;'#13#10 +
    '  TBasis = class(TInterfacedObject)'#13#10 +
    '  public'#13#10 +
    '    procedure SetName(const AValue: string);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

function InterfaceSource(const ALine: string): string;
begin
  Result :=
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Basis;'#13#10 +
    'type'#13#10 +
    '  TJsonExporter = class(TBasis, IExporter)'#13#10 +
    '  private'#13#10 +
    '    FText: string;'#13#10 +
    ALine + #13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
end;

procedure TLspCompletionHandleTests.InterfaceHintComesFirst;
var
  Answer: TJSONObject;
begin
  AddUnit(BasisFile, UnitBasis);
  Answer := Complete(InterfaceSource('    Ex|'));
  try
    Assert.IsTrue(ItemCount(Answer) > 1, Answer.ToJSON);
    Assert.IsTrue(ItemAt(Answer, 0).GetValue<Boolean>('data.hint'), Answer.ToJSON);
    Assert.AreEqual('IExporter', ItemAt(Answer, 0).GetValue<string>('data.container'));
    // Je Interface ein Hinweis, danach die übrige Liste.
    Assert.AreEqual('IFlush', ItemAt(Answer, 1).GetValue<string>('data.container'));
    Assert.IsTrue(ItemCount(Answer) > 2, Answer.ToJSON);
    Assert.IsFalse(ItemAt(Answer, 2).ToJSON.Contains('"hint"'), Answer.ToJSON);
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.InterfaceBatchIsExclusive;
var
  Answer: TJSONObject;
begin
  AddUnit(BasisFile, UnitBasis);
  Answer := Complete(InterfaceSource('    |'));
  try
    Assert.AreEqual('Export GetName Flush', Labels(Answer));
    Assert.IsTrue(ItemAt(Answer, 0).GetValue<Boolean>('data.batch'));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.KeywordsCanBeSwitchedOff;
const
  Text =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Laden;'#13#10 +
    'var'#13#10 +
    '  Beginn: Integer;'#13#10 +
    'begin'#13#10 +
    '  be|'#13#10 +
    'end;'#13#10 +
    'end.';
var
  Answer: TJSONObject;
begin
  Answer := Complete(Text);
  try
    Assert.IsTrue(Answer.ToJSON.Contains('"label":"begin","kind":14'), Answer.ToJSON);
    Assert.IsTrue(Answer.ToJSON.Contains('"label":"Beginn"'), Answer.ToJSON);
  finally
    Answer.Free;
  end;
  FCompletion.Hooks.SettingsFor :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := TCompletionSettings.Default;
      Result.Keywords := False;
    end;
  Answer := Complete(Text);
  try
    Assert.IsFalse(Answer.ToJSON.Contains('"kind":14'), Answer.ToJSON);
    Assert.IsTrue(Answer.ToJSON.Contains('"label":"Beginn"'), Answer.ToJSON);
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.PartialSendsEnumsThenStages;
var
  Answer: TJSONObject;
  Sent, Index: Integer;
  Value: TJSONObject;
begin
  AddUnit(TypenFile, UnitTypen);
  Answer := Complete(EnumSource('  C.Align := |;'), '', 'tok');
  try
    // Zuerst die Aufzählungswerte, dann der eigene Gültigkeitsbereich; die Antwort setzt sortText fort.
    Assert.IsTrue(Length(FProgress) >= 2, IntToStr(Length(FProgress)));
    Assert.IsTrue(FProgress[0].Contains('"token":"tok"'), FProgress[0]);
    Assert.IsTrue(FProgress[0].Contains('"label":"alNone"'), FProgress[0]);
    Assert.IsTrue(FProgress[0].Contains('"sortText":"00000"'), FProgress[0]);
    Assert.IsFalse(FProgress[1].Contains('"label":"alNone"'), FProgress[1]);
    Assert.IsTrue(FProgress[1].Contains('"sortText":"00003"'), FProgress[1]);
    Assert.IsFalse(Answer.ToJSON.Contains('"label":"alNone"'), Answer.ToJSON);
    Sent := 0;
    for Index := 0 to High(FProgress) do
    begin
      Value := TJSONObject.ParseJSONValue(FProgress[Index]) as TJSONObject;
      try
        Inc(Sent, (Value.GetValue('value') as TJSONArray).Count);
      finally
        Value.Free;
      end;
    end;
    if ItemCount(Answer) > 0 then
    begin
      Assert.AreEqual(Format('%.5d', [Sent]), ItemAt(Answer, 0).GetValue<string>('sortText'));
    end;
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.SenderCastIsExclusive;
const
  UnitSteuer =
    'unit Steuer;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TControl = class'#13#10 +
    '  public'#13#10 +
    '    Caption: string;'#13#10 +
    '  end;'#13#10 +
    '  TButton = class(TControl)'#13#10 +
    '  end;'#13#10 +
    '  TBitBtn = class(TButton)'#13#10 +
    '  end;'#13#10 +
    '  TForm = class(TControl)'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';
var
  Answer: TJSONObject;
begin
  AddUnit('C:\P\Steuer.pas', UnitSteuer);
  FForm :=
    'object frmMain: TfrmMain'#13#10 +
    '  object btnSave: TButton'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    '  object btnLoad: TBitBtn'#13#10 +
    '    OnClick = btnAnyClick'#13#10 +
    '  end'#13#10 +
    'end';
  Answer := Complete(
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'uses Steuer;'#13#10 +
    'type'#13#10 +
    '  TfrmMain = class(TForm)'#13#10 +
    '    btnSave: TButton;'#13#10 +
    '    btnLoad: TBitBtn;'#13#10 +
    '    procedure btnAnyClick(Sender: TObject);'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    '{$R *.dfm}'#13#10 +
    'procedure TfrmMain.btnAnyClick(Sender: TObject);'#13#10 +
    'begin'#13#10 +
    '  Sender.Cap|'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual('Caption', Labels(Answer));
    Assert.AreEqual('TButton', ItemAt(Answer, 0).GetValue<string>('data.sender'));
  finally
    Answer.Free;
  end;
end;

const
  KundenFile = 'C:\P\Kunden.pas';

  /// <summary>Unit mit AFields Feldern, davon APrefixed mit F.</summary>
  function FieldUnit(AFields, APrefixed: Integer): string;
  var
    Index: Integer;
  begin
    Result := 'unit Kunden;'#13#10'interface'#13#10'type'#13#10'  TKunde = class'#13#10;
    for Index := 1 to AFields do
    begin
      if Index <= APrefixed then
      begin
        Result := Result + '    FWert' + IntToStr(Index) + ': Integer;'#13#10;
      end
      else
      begin
        Result := Result + '    Wert' + IntToStr(Index) + ': Integer;'#13#10;
      end;
    end;
    Result := Result + '  end;'#13#10'implementation'#13#10'end.';
  end;

const
  FieldSite =
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TForm = class'#13#10 +
    '  private'#13#10 +
    '    |: TCustomerList;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.';

procedure TLspCompletionHandleTests.NameSuggestionsFollowProjectConvention;
var
  Answer: TJSONObject;
begin
  // 3 von 5 Feldern mit F: genau 60 %.
  AddUnit(KundenFile, FieldUnit(5, 3));
  Answer := Complete(FieldSite);
  try
    Assert.AreEqual('FCustomers FCustomerList FList', Labels(Answer), Answer.ToJSON);
    Assert.AreEqual(5, ItemAt(Answer, 0).GetValue<Integer>('kind'));
    Assert.AreEqual('TCustomerList', ItemAt(Answer, 0).GetValue<string>('detail'));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.NameSuggestionsWithoutConvention;
var
  Answer: TJSONObject;
begin
  // 2 von 5: unter 60 %.
  AddUnit(KundenFile, FieldUnit(5, 2));
  Answer := Complete(FieldSite);
  try
    Assert.AreEqual('Customers CustomerList List', Labels(Answer), Answer.ToJSON);
  finally
    Answer.Free;
  end;
  // Lokale Variable: vergebene Namen bekommen eine Ziffer, der Name an der Stelle selbst zählt nicht.
  Answer := Complete(
    'unit Haupt;'#13#10 +
    'interface'#13#10 +
    'implementation'#13#10 +
    'procedure Laden(List: Integer);'#13#10 +
    'var'#13#10 +
    '  Customers: Integer;'#13#10 +
    '  Cu|: TCustomerList;'#13#10 +
    'begin'#13#10 +
    'end;'#13#10 +
    'end.');
  try
    Assert.AreEqual('Customers2 CustomerList List2', Labels(Answer), Answer.ToJSON);
    Assert.AreEqual(6, ItemAt(Answer, 0).GetValue<Integer>('kind'));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.NameSuggestionsForcedAndSwitchedOff;
var
  Answer: TJSONObject;
begin
  AddUnit(KundenFile, FieldUnit(5, 0));
  FCompletion.Hooks.NamingFor :=
    function(const AUri: string; AKind: TNamingKind): string
    begin
      Result := '';
      if AKind = TNamingKind.Field then
      begin
        Result := 'F';
      end;
    end;
  Answer := Complete(FieldSite);
  try
    Assert.AreEqual('FCustomers FCustomerList FList', Labels(Answer), Answer.ToJSON);
  finally
    Answer.Free;
  end;
  FCompletion.Hooks.SettingsFor :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := TCompletionSettings.Default;
      Result.NameSuggestions := False;
    end;
  Answer := Complete(FieldSite);
  try
    Assert.IsFalse(Labels(Answer).Contains('Customers'), Answer.ToJSON);
  finally
    Answer.Free;
  end;
end;

const
  FrageUnit =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses'#10 +
    '  Dialogs;'#10 +
    #10 +
    'procedure Frage;'#10 +
    'begin'#10 +
    '  ShowMessage(''Eintrag wirklich l|öschen?'');'#10 +
    'end;'#10 +
    #10 +
    'end.';
  TexteFile = 'C:\P\Texte.pas';
  TexteUnit =
    'unit Texte;'#10 +
    'interface'#10 +
    'resourcestring'#10 +
    '  SOk = ''OK'';'#10 +
    'implementation'#10 +
    'end.';

procedure TLspCompletionHandleTests.DocBlockOffersParameterAdjust;
const
  Source =
    'unit Haupt;'#13#10'interface'#13#10'type'#13#10'  TRechner = class'#13#10 +
    '    /// <summary>Rabatt|</summary>'#13#10'    /// <param name="Customer">Kunde</param>'#13#10 +
    '    function CalcDiscount(Customer: TObject; Rate: Double): Currency;'#13#10 +
    '  end;'#13#10'implementation'#13#10'end.';
var
  Answer: TJSONObject;
  Edits: TJSONArray;
  Enabled: Boolean;
begin
  Enabled := True;
  FCompletion.Hooks.DocCommentsFor :=
    function(const AUri: string): Boolean
    begin
      Result := Enabled;
    end;
  Answer := Complete(Source);
  try
    Assert.AreEqual('Parameter abgleichen', Labels(Answer));
    Edits := ((Answer.GetValue('items') as TJSONArray).Items[0] as TJSONObject).GetValue('additionalTextEdits')
      as TJSONArray;
    Assert.AreEqual(1, Integer(Edits.Count));
    Assert.AreEqual('    /// <param name="Rate"></param>'#13#10,
      (Edits.Items[0] as TJSONObject).GetValue<string>('newText'));
    Assert.IsTrue(Answer.ToJSON.Contains('"action":"docParams"'), Answer.ToJSON);
  finally
    Answer.Free;
  end;
  // Passt der Block, kommt das Angebot nicht.
  Answer := Complete(StringReplace(Source, 'Kunde</param>', 'Kunde</param>'#13#10 +
    '    /// <param name="Rate">Satz</param>', []));
  try
    Assert.IsFalse(Labels(Answer).Contains('Parameter abgleichen'), Labels(Answer));
  finally
    Answer.Free;
  end;
  Enabled := False;
  Answer := Complete(Source);
  try
    Assert.IsFalse(Labels(Answer).Contains('Parameter abgleichen'), Labels(Answer));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.DirectiveSymbolsWithOrigin;
var
  Answer: TJSONObject;
  Enabled: Boolean;
begin
  Enabled := True;
  FCompletion.Hooks.SymbolsFor :=
    function(const AUri: string): TConditionalContext
    begin
      Result := TConditionalContext.Default;
      Result.CompletionEnabled := Enabled;
      Result.HasDefines := True;
      Result.Defines := ['DEBUG', 'MSWINDOWS'];
      Result.Sources := TConditionalSymbols.SourcesOf(['DEBUG'],
        [TPair<string, string>.Create('DEBUG', 'Konfiguration Debug')], ['MSWINDOWS'], 'Win64');
    end;
  Answer := Complete('unit Haupt;'#13#10'{$IFDEF |'#13#10'implementation'#13#10'end.');
  try
    Assert.AreEqual('DEBUG', ItemAt(Answer, 0).GetValue<string>('label'));
    Assert.AreEqual('Konfiguration Debug (.dproj)', ItemAt(Answer, 0).GetValue<string>('detail'));
    Assert.IsTrue(Labels(Answer).Contains('MSWINDOWS'), Labels(Answer));
    Assert.IsTrue(Labels(Answer).Contains('LINUX'), Labels(Answer));
    Assert.IsFalse(Labels(Answer).Contains('ALIGN'), Labels(Answer));
  finally
    Answer.Free;
  end;
  Enabled := False;
  Answer := Complete('unit Haupt;'#13#10'{$IFDEF |'#13#10'implementation'#13#10'end.');
  try
    Assert.AreEqual(0, ItemCount(Answer), Labels(Answer));
  finally
    Answer.Free;
  end;
end;

procedure TLspCompletionHandleTests.DirectiveNamesAndWarnings;
var
  Answer: TJSONObject;
  Index: Integer;
  Found: Boolean;
begin
  Answer := Complete('unit Haupt;'#13#10'{$IFD|'#13#10'implementation'#13#10'end.');
  try
    Assert.IsTrue((' ' + Labels(Answer) + ' ').Contains(' IFDEF '), Labels(Answer));
    Assert.IsTrue((' ' + Labels(Answer) + ' ').Contains(' IFNDEF '), Labels(Answer));
    Found := False;
    for Index := 0 to ItemCount(Answer) - 1 do
    begin
      if ItemAt(Answer, Index).GetValue<string>('label') = 'IFDEF' then
      begin
        Found := True;
        Assert.AreNotEqual('', ItemAt(Answer, Index).GetValue<string>('detail', ''));
      end;
    end;
    Assert.IsTrue(Found);
  finally
    Answer.Free;
  end;
  Answer := Complete('unit Haupt;'#13#10'{$WARN SYMBOL_DEP|'#13#10'implementation'#13#10'end.');
  try
    Assert.IsTrue((' ' + Labels(Answer) + ' ').Contains(' SYMBOL_DEPRECATED '), Labels(Answer));
    Assert.AreEqual('Compiler-Warnung', ItemAt(Answer, 0).GetValue<string>('detail'));
  finally
    Answer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspCompletionHandleTests);

end.
