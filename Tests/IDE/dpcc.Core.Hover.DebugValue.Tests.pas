unit dpcc.Core.Hover.DebugValue.Tests;

// Tests für den Variablenwert im Hover beim Debuggen (#891): Ausdruck unter der Maus, Zustände des Werts und
// Kürzen. Seit S3b wieder im Testprojekt.

interface

uses
  DUnitX.TestFramework,
  dpcc.Core.Hover.DebugValue;

type
  [TestFixture]
  TDpccDebugValueTests = class
  private
    /// <summary>Ausdruck zum ersten Vorkommen von AWord in ALine.</summary>
    function ExpressionAt(const ALine, AWord: string): string;
  public
    [Test]
    procedure PlainIdentifier;
    [Test]
    procedure QualifiedChain;
    [Test]
    procedure FirstPartOfChainOnly;
    [Test]
    procedure IndexAndDereference;
    [Test]
    procedure CallBeforeDotGivesNothing;
    [Test]
    procedure CallInIndexGivesNothing;
    [Test]
    procedure RangeIsNoQualifier;
    [Test]
    procedure ReservedWordsAndNumbers;
    [Test]
    procedure StringsAndComments;
    [Test]
    procedure EscapedIdentifier;
    [Test]
    procedure AtCharacterFindsWordBounds;
    [Test]
    procedure ShortenLongValues;
    [Test]
    procedure StatesAndPlainText;
  end;

implementation

uses
  System.SysUtils;

function TDpccDebugValueTests.ExpressionAt(const ALine, AWord: string): string;
var
  mStart: Integer;
begin
  mStart := Pos(AWord, ALine) - 1;
  Assert.IsTrue(mStart >= 0, AWord + ' fehlt in der Zeile');
  Result := TDpccDebugExpression.At(ALine, mStart, mStart + Length(AWord));
end;

procedure TDpccDebugValueTests.PlainIdentifier;
begin
  Assert.AreEqual('Kunde', ExpressionAt('  Kunde := nil;', 'Kunde'));
  Assert.AreEqual('Result', ExpressionAt('  Result := 0;', 'Result'));
end;

procedure TDpccDebugValueTests.QualifiedChain;
begin
  Assert.AreEqual('FList.Count', ExpressionAt('  for I := 0 to FList.Count - 1 do', 'Count'));
  Assert.AreEqual('Self.FKunde.Name', ExpressionAt('  S := Self.FKunde.Name;', 'Name'));
end;

procedure TDpccDebugValueTests.FirstPartOfChainOnly;
begin
  // Wie in der IDE: rechts vom Bezeichner wird nichts angehängt.
  Assert.AreEqual('FList', ExpressionAt('  N := FList.Count;', 'FList'));
end;

procedure TDpccDebugValueTests.IndexAndDereference;
begin
  Assert.AreEqual('Kunden[I].Name', ExpressionAt('  S := Kunden[I].Name;', 'Name'));
  Assert.AreEqual('Matrix[I][J + 1].Wert', ExpressionAt('  X := Matrix[I][J + 1].Wert;', 'Wert'));
  Assert.AreEqual('P^.Wert', ExpressionAt('  X := P^.Wert;', 'Wert'));
end;

procedure TDpccDebugValueTests.CallBeforeDotGivesNothing;
begin
  // Aufruf bzw. Typumwandlung vor dem Punkt: nicht auswerten, auch nicht nur „Name“.
  Assert.AreEqual('', ExpressionAt('  S := Get(X).Name;', 'Name'));
  Assert.AreEqual('', ExpressionAt('  S := TKunde(Obj).Name;', 'Name'));
end;

procedure TDpccDebugValueTests.CallInIndexGivesNothing;
begin
  Assert.AreEqual('', ExpressionAt('  S := Kunden[Index(1)].Name;', 'Name'));
  Assert.AreEqual('', ExpressionAt('  S := Werte[''a''].Name;', 'Name'));
end;

procedure TDpccDebugValueTests.RangeIsNoQualifier;
begin
  Assert.AreEqual('Count', ExpressionAt('  for I in [0..Count] do', 'Count'));
end;

procedure TDpccDebugValueTests.ReservedWordsAndNumbers;
begin
  Assert.AreEqual('', ExpressionAt('  begin', 'begin'));
  Assert.AreEqual('', ExpressionAt('  if A then', 'then'));
  Assert.AreEqual('', TDpccDebugExpression.At('  X := 42;', 7, 9));
  Assert.IsTrue(TDpccDebugExpression.IsReserved('END'));
  Assert.IsFalse(TDpccDebugExpression.IsReserved('Self'));
end;

procedure TDpccDebugValueTests.StringsAndComments;
begin
  Assert.AreEqual('', ExpressionAt('  S := ''Kunde'';', 'Kunde'));
  Assert.AreEqual('', ExpressionAt('  X := 1; // Kunde', 'Kunde'));
  Assert.AreEqual('', ExpressionAt('  X := 1; { Kunde }', 'Kunde'));
  Assert.AreEqual('', ExpressionAt('  X := 1; (* Kunde *)', 'Kunde'));
  // Nach dem Ende von String und Kommentar wieder auswertbar.
  Assert.AreEqual('Kunde', ExpressionAt('  S := ''a'' + { b } Kunde;', 'Kunde'));
end;

procedure TDpccDebugValueTests.EscapedIdentifier;
begin
  Assert.AreEqual('&Type.Name', ExpressionAt('  S := &Type.Name;', 'Name'));
end;

procedure TDpccDebugValueTests.AtCharacterFindsWordBounds;
var
  mLine: string;
begin
  mLine := '  N := FList.Count;';
  // Mitten in „Count“.
  Assert.AreEqual('FList.Count', TDpccDebugExpression.AtCharacter(mLine, Pos('ount', mLine) - 1));
  // Auf dem Leerzeichen: nichts.
  Assert.AreEqual('', TDpccDebugExpression.AtCharacter(mLine, 0));
  Assert.AreEqual('', TDpccDebugExpression.AtCharacter(mLine, Length(mLine)));
end;

procedure TDpccDebugValueTests.ShortenLongValues;
var
  mValue: TDpccDebugValue;
begin
  Assert.AreEqual('abc', TDpccDebugExpression.Shorten('abc', 3));
  Assert.AreEqual('ab …', TDpccDebugExpression.Shorten('abc', 2));
  mValue := TDpccDebugValue.Evaluated('S', StringOfChar('x', TDpccDebugExpression.cMaxValueLength + 10));
  Assert.AreEqual(TDpccDebugExpression.cMaxValueLength + 2, Integer(Length(mValue.Text)));
end;

procedure TDpccDebugValueTests.StatesAndPlainText;
var
  mValue: TDpccDebugValue;
begin
  mValue := Default(TDpccDebugValue);
  Assert.IsFalse(mValue.Visible);
  Assert.AreEqual('', mValue.PlainText);
  mValue := TDpccDebugValue.Pending('Count');
  Assert.IsTrue(mValue.Visible);
  Assert.AreEqual('', mValue.PlainText, 'ausstehend: noch kein Text für die IDE');
  mValue := TDpccDebugValue.Evaluated('Count', '3');
  Assert.IsTrue(mValue.Visible);
  Assert.AreEqual('Count = 3', mValue.PlainText);
  // Fehler ohne Erklärung zeigt der Tooltip nicht; mit Erklärung „kein Zugriff“ schon (#840).
  mValue := TDpccDebugValue.Failed('Count', 'Undeclared identifier');
  Assert.IsFalse(mValue.Visible);
  Assert.IsFalse(mValue.Explained);
  Assert.AreEqual('', mValue.PlainText);
  mValue.Note.Caption := '<kein Zugriff>';
  mValue.Note.Reason := 'Optimierung an.';
  Assert.IsTrue(mValue.Visible);
  Assert.IsTrue(mValue.Explained);
  Assert.AreEqual('Count = <kein Zugriff>' + sLineBreak + 'Optimierung an.', mValue.PlainText);
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccDebugValueTests);

end.
