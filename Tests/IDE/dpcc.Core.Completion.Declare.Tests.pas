unit dpcc.Core.Completion.Declare.Tests;

// Tests für die Deklaration unbekannter Namen in der Vervollständigung (#471): Gruppe am Ende mit Überschrift,
// Felder aus der Antwort des Servers und Enter ohne Auswahl.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccCompletionDeclareTests = class
  public
    [Test]
    procedure UnknownGroupComesLast;
    [Test]
    procedure ReadsDeclareFieldsFromServer;
    [Test]
    procedure EnterPassesThroughWithoutSelection;
    [Test]
    procedure ReadsLinkedEditsAndCommand;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Placeholders,
  dpcc.Core.Completion.Controller,
  dpcc.Core.Completion.Ranking,
  dpcc.Core.Completion.Providers.Fixed,
  dpcc.Core.Completion.Providers.Server;

type
  TDeclareView = class(TInterfacedObject, IDpccCompletionView)
  public
    Selected: Integer;
    procedure ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    function PageSize: Integer;
  end;

procedure TDeclareView.ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
begin
  Selected := ASelected;
end;

procedure TDeclareView.HideList;
begin
end;

procedure TDeclareView.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
end;

function TDeclareView.PageSize: Integer;
begin
  Result := 5;
end;

function Declare(const AName: string; ARank: Integer): TDpccCompletionItem;
begin
  Result := Default(TDpccCompletionItem);
  Result.Name := AName;
  Result.Kind := TDpccItemKind.Variable;
  Result.IsAction := True;
  Result.Unknown := 'TotalCount';
  Result.Rank := ARank;
end;

function Declarations: TDpccCompletionItems;
begin
  Result := [Declare('Lokale Variable anlegen', 1), Declare('Feld FTotalCount anlegen', 2)];
end;

function Names(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index in AOrder do
  begin
    if Index = TDpccRanking.cUnknownHeader then
    begin
      Result := Result + '? ';
    end
    else if TDpccRanking.IsHeader(Index) then
    begin
      Result := Result + '# ';
    end
    else
    begin
      Result := Result + AItems[Index].Name + ' ';
    end;
  end;
  Result := Result.Trim;
end;

const
  // resourcestring auslagern (#473) mit Platzhalter im Literal und in der Deklaration.
  ResourceItem =
    '{"label":"Als resourcestring auslagern","kind":21,"insertTextFormat":2,"textEdit":{"range":{"start":' +
    '{"line":9,"character":14},"end":{"line":9,"character":21}},"newText":"${1:SFrage}"},' +
    '"additionalTextEdits":[{"range":{"start":{"line":3,"character":0},"end":{"line":3,"character":0}},' +
    '"newText":"  ${1:SFrage} = ''Frage?'';\n"}],"command":{"title":"Eintragen","command":' +
    '"dpcc.server.addResourceString","arguments":["C:\\P\\Texte.pas","SFrage","''Frage?''"]},' +
    '"data":{"action":"create","pinned":true,"linkedEdits":true}}';

function ResourceFromLsp(const AJson: string): TDpccCompletionItem;
var
  Json: TJSONObject;
begin
  Json := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  try
    Result := TDpccServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
end;

function WaitFor(const ACondition: TFunc<Boolean>): Boolean;
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

{ TDpccCompletionDeclareTests }

procedure TDpccCompletionDeclareTests.UnknownGroupComesLast;
var
  Items: TDpccCompletionItems;
  Regular: TDpccCompletionItem;
begin
  Regular := Default(TDpccCompletionItem);
  Regular.Name := 'TotalItems';
  Regular.Kind := TDpccItemKind.Variable;
  Items := Declarations + [Regular];
  Assert.AreEqual('TotalItems ? Lokale Variable anlegen Feld FTotalCount anlegen',
    Names(Items, TDpccRanking.Order(Items, 'Tot', TDpccRankOptions.Defaults)));
  // Ohne andere Einträge bleibt die Gruppe mit ihrer Überschrift.
  Items := Declarations;
  Assert.AreEqual('? Lokale Variable anlegen Feld FTotalCount anlegen',
    Names(Items, TDpccRanking.Order(Items, 'TotalCount', TDpccRankOptions.Defaults)));
end;

procedure TDpccCompletionDeclareTests.ReadsDeclareFieldsFromServer;
var
  Json: TJSONObject;
  Item: TDpccCompletionItem;
begin
  Json := TJSONObject.ParseJSONValue('{"label":"Lokale Variable anlegen","kind":6,"textEdit":{"range":{"start":' +
    '{"line":9,"character":2},"end":{"line":9,"character":12}},"newText":"TotalCount$0"},"additionalTextEdits":' +
    '[{"range":{"start":{"line":8,"character":0},"end":{"line":8,"character":0}},"newText":"var"}],' +
    '"data":{"action":"declare","unknown":"TotalCount"}}') as TJSONObject;
  try
    Item := TDpccServerCompletionProvider.ItemFromLsp(Json, 0);
  finally
    Json.Free;
  end;
  Assert.IsTrue(Item.IsAction);
  Assert.AreEqual('TotalCount', Item.Unknown);
  Assert.IsTrue(Item.UnitUsed, 'die Zusatzänderung ist keine uses-Ergänzung');
  Assert.AreEqual('TotalCount$0', Item.TextEdit.NewText);
end;

procedure TDpccCompletionDeclareTests.ReadsLinkedEditsAndCommand;
var
  Item: TDpccCompletionItem;
begin
  Item := ResourceFromLsp(ResourceItem);
  Assert.IsTrue(Item.IsAction);
  Assert.IsTrue(Item.LinkedEdits);
  Assert.AreEqual(TDpccPlaceholderText.FromLsp('${1:SFrage}'), Item.PlaceholderText);
  Assert.AreEqual(1, Integer(Length(Item.AdditionalEdits)));
  Assert.AreEqual(TDpccPlaceholderText.FromLsp('  ${1:SFrage} = ''Frage?'';'#10), Item.AdditionalEdits[0].NewText);
  Assert.AreEqual('dpcc.server.addResourceString', Item.Command);
  Assert.AreEqual('["C:\\P\\Texte.pas","SFrage","''Frage?''"]', Item.CommandArguments);
  // Ohne Vorlage keine verknüpften Änderungen, ohne Argumente eine leere Liste.
  Item := ResourceFromLsp(StringReplace(StringReplace(ResourceItem, '"insertTextFormat":2,', '', []),
    ',"arguments":["C:\\P\\Texte.pas","SFrage","''Frage?''"]', '', []));
  Assert.IsFalse(Item.LinkedEdits);
  Assert.AreEqual('  ${1:SFrage} = ''Frage?'';'#10, Item.AdditionalEdits[0].NewText);
  Assert.AreEqual('[]', Item.CommandArguments);
end;

procedure TDpccCompletionDeclareTests.EnterPassesThroughWithoutSelection;
var
  View: TDeclareView;
  ViewRef: IDpccCompletionView;
  Controller: TDpccCompletionController;
  Committed: string;
  Context: TDpccContext;
begin
  View := TDeclareView.Create;
  ViewRef := View;
  Controller := TDpccCompletionController.Create(
    TDpccFixedCompletionProvider.Create(Declarations) as IDpccCompletionProvider, ViewRef);
  try
    Committed := '';
    Controller.OnCommit :=
      procedure(const AItem: TDpccCompletionItem)
      begin
        Committed := AItem.Name;
      end;
    Context := Default(TDpccContext);
    Context.FileName := 'C:\P\A.pas';
    Context.Prefix := 'TotalCount';
    Controller.Start(Context);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    // Nur Deklarationen: sichtbar, nichts gewählt; Enter gehört dem Editor und schließt die Liste.
    Assert.IsTrue(Controller.Passive);
    Assert.AreEqual(-1, View.Selected);
    Assert.IsFalse(Controller.HandleKey(TDpccNavigationKey.Accept));
    Assert.AreEqual('', Committed);
    Assert.IsFalse(Controller.Active);
    // Pfeiltaste wählt die erste Deklaration, Enter übernimmt sie.
    Controller.Start(Context);
    Assert.IsTrue(WaitFor(
      function: Boolean
      begin
        Result := not Controller.Loading;
      end));
    Assert.IsTrue(Controller.HandleKey(TDpccNavigationKey.Down));
    Assert.IsFalse(Controller.Passive);
    Assert.IsTrue(View.Selected >= 0);
    Assert.IsTrue(Controller.HandleKey(TDpccNavigationKey.Accept));
    Assert.AreEqual('Lokale Variable anlegen', Committed);
  finally
    Controller.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccCompletionDeclareTests);

end.
