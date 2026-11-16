unit dpcc.Core.Completion.Providers.Expression.Tests;

// Datenquelle der Debug-Dialoge (#538): Einträge aus dem Verlauf. Die
// Übersetzung der Serverantwort prüfen die Tests der Quelle Server.

interface

uses
  DUnitX.TestFramework,
  dpcc.Core.Completion.Providers.Expression;

type
  [TestFixture]
  TDpccExpressionProviderTests = class
  public
    [Test]
    procedure HistoryItemsReplaceField;
  end;

implementation

uses
  dpcc.Core.Completion.Contract;

{ TDpccExpressionProviderTests }

procedure TDpccExpressionProviderTests.HistoryItemsReplaceField;
var
  Items: TDpccCompletionItems;
begin
  Items := TDpccExpressionCompletionProvider.HistoryItems(TArray<string>.Create('Kunde.Name', 'Summe'), 'Verlauf');
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual('Kunde.Name', Items[0].Name);
  Assert.AreEqual('Verlauf', Items[1].Signature);
  Assert.AreEqual(1, Items[1].Rank, 'neuester zuerst');
  Assert.AreEqual(0, Integer(Length(TDpccExpressionCompletionProvider.HistoryItems(nil, 'Verlauf'))));
end;

end.
