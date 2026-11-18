unit dpcc.Core.Completion.Parentheses.Tests;

// Tests für Klammern beim Übernehmen (#430). Die Vorschau im Editor (#434) ist seit OPT2 samt Tests entfallen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccParenthesesTests = class
  public
    [Test]
    procedure WantsParenthesesOnlyForRoutinesWithParameters;
    [Test]
    procedure TypedCloseParenSkipsAutomaticOne;
    [Test]
    procedure TypedCloseParenAfterArguments;
    [Test]
    procedure FollowsEditsBeforeTheParen;
    [Test]
    procedure StopsWhenParenIsDeletedOrLineReplaced;
    /// <summary>#472: "(" hinter einem Bezeichner löst „Methode anlegen“ aus, hinter Schlüsselwörtern nicht.</summary>
    [Test]
    procedure CallOpenedAfterIdentifier;
  end;

implementation

uses
  dpcc.Core.Completion.Parentheses;

procedure TDpccParenthesesTests.WantsParenthesesOnlyForRoutinesWithParameters;
begin
  Assert.IsTrue(TDpccParentheses.Wanted(True, True, ';'));
  Assert.IsTrue(TDpccParentheses.Wanted(True, True, #0));
  Assert.IsFalse(TDpccParentheses.Wanted(True, False, ';'), 'Clear ohne Parameter: Delphi-Stil ohne Klammern');
  Assert.IsFalse(TDpccParentheses.Wanted(False, True, ';'), 'keine Routine');
  Assert.IsFalse(TDpccParentheses.Wanted(True, True, '('), 'schon eine Klammer');
end;

procedure TDpccParenthesesTests.TypedCloseParenSkipsAutomaticOne;
var
  Paren: TDpccAutoParen;
  RemoveAt: Integer;
begin
  // "  List.Add(|)": automatische ")" an Index 11.
  Paren := TDpccAutoParen.Start(5, 11, '  List.Add()');
  Paren.Update('  List.Add())', RemoveAt);
  Assert.AreEqual(12, RemoveAt);
  Assert.IsFalse(Paren.Active);
end;

procedure TDpccParenthesesTests.TypedCloseParenAfterArguments;
var
  Paren: TDpccAutoParen;
  RemoveAt: Integer;
  Line: string;
begin
  Paren := TDpccAutoParen.Start(5, 11, '  List.Add()');
  Line := '  List.Add()';
  // "X" tippen: Klammer wandert mit.
  Insert('X', Line, 12);
  Paren.Update(Line, RemoveAt);
  Assert.AreEqual(-1, RemoveAt);
  Assert.AreEqual(12, Paren.Close);
  // ")" hinter X: die automatische fällt weg.
  Insert(')', Line, 13);
  Paren.Update(Line, RemoveAt);
  Assert.AreEqual(13, RemoveAt);
end;

procedure TDpccParenthesesTests.FollowsEditsBeforeTheParen;
var
  Paren: TDpccAutoParen;
  RemoveAt: Integer;
begin
  Paren := TDpccAutoParen.Start(5, 11, '  List.Add()');
  // Einrückung vorn erweitert.
  Paren.Update('   List.Add()', RemoveAt);
  Assert.AreEqual(12, Paren.Close);
  Assert.IsTrue(Paren.Active);
  // Und wieder entfernt.
  Paren.Update('  List.Add()', RemoveAt);
  Assert.AreEqual(11, Paren.Close);
  Assert.AreEqual(-1, RemoveAt);
end;

procedure TDpccParenthesesTests.StopsWhenParenIsDeletedOrLineReplaced;
var
  Paren: TDpccAutoParen;
  RemoveAt: Integer;
begin
  Paren := TDpccAutoParen.Start(5, 11, '  List.Add()');
  Paren.Update('  List.Add(', RemoveAt);
  Assert.IsFalse(Paren.Active, 'automatische Klammer gelöscht');
  Paren := TDpccAutoParen.Start(5, 11, '  List.Add()');
  Paren.Update('  Other.Call(1, 2)', RemoveAt);
  Assert.IsFalse(Paren.Active, 'Zeile ersetzt');
  Assert.AreEqual(-1, RemoveAt);
end;

procedure TDpccParenthesesTests.CallOpenedAfterIdentifier;
begin
  Assert.IsTrue(TDpccParentheses.CallOpened('  Total := CalcDiscount(', 24));
  Assert.IsTrue(TDpccParentheses.CallOpened('  Kunde.Speichern(', 18));
  // Cursor nicht direkt hinter "(", Leerzeichen davor, Schlüsselwort, Zahl, Kommentar und String.
  Assert.IsFalse(TDpccParentheses.CallOpened('  Total := CalcDiscount(', 23));
  Assert.IsFalse(TDpccParentheses.CallOpened('  Total := (', 12));
  Assert.IsFalse(TDpccParentheses.CallOpened('  if (', 6));
  Assert.IsFalse(TDpccParentheses.CallOpened('  X := 3(', 9));
  Assert.IsFalse(TDpccParentheses.CallOpened('  // Rechne(', 12));
  Assert.IsFalse(TDpccParentheses.CallOpened('  S := ''Rechne(', 15));
  Assert.IsFalse(TDpccParentheses.CallOpened('(', 1));
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccParenthesesTests);

end.
