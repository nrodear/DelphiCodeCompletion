unit dpcc.Core.Editor.TabStops.Tests;

// Tabulatorpositionen der Editoroptionen (dpcc.Core.Editor.TabStops): Vorher galt die erste Zahl von
// BufferOptions.TabStops als Tabweite; "3 5" wurde so zu Weite 3 statt Stopps in Spalte 3, 5, 7, ….
// - Eine Zahl = Abstand, mehrere = absolute Spalten mit dem letzten Abstand dahinter; leer oder kaputt wie bisher 8.
// - Editorspalte ↔ Zeichenindex mit Tabs am Anfang und mitten in der Zeile, Rundlauf Index → Spalte → Index.
// - TLspSessionJson.ColumnToIndex/IndexToColumn: die Fassung mit Zahl wie bisher, die mit TDpccTabStops gleich.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccTabStopsTests = class
  public
    /// <summary>"4": alle vier Spalten (5, 9, 13 …).</summary>
    [Test]
    procedure SingleNumberIsInterval;
    /// <summary>"3 5": Stopps in Spalte 3, 5, dahinter im Abstand 2 (7, 9 …).</summary>
    [Test]
    procedure TwoStopsContinueWithLastInterval;
    /// <summary>"9 17" ergibt dieselben Stopps wie "8".</summary>
    [Test]
    procedure NineSeventeenEqualsEight;
    /// <summary>"4 10 20": unregelmäßig, dahinter im Abstand 10.</summary>
    [Test]
    procedure IrregularList;
    /// <summary>Leer, keine Zahl, Null, absteigend, doppelt: Abstand 8.</summary>
    [Test]
    procedure InvalidFallsBackToEight;
    /// <summary>Tabs mitten in der Zeile: Spalte und Index bei regelmäßigen und unregelmäßigen Stopps.</summary>
    [Test]
    procedure TabsInMiddleOfLine;
    /// <summary>Index → Spalte → Index ergibt den Index, auch hinter dem Zeilenende.</summary>
    [Test]
    procedure RoundTripIndexColumnIndex;
    /// <summary>Anzeige der Zeile: Tabs als Leerzeichen bis zur nächsten Position.</summary>
    [Test]
    procedure DisplayLineFillsToNextStop;
    /// <summary>TLspSessionJson: Fassung mit Zahl wie bisher (Weite 0 ohne Division durch null), Fassung mit
    /// TDpccTabStops wie die Unit.</summary>
    [Test]
    procedure SessionOverloadsAgree;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Editor.TabStops,
  dpcc.Core.Lsp.Session.Json;

{ TDpccTabStopsTests }

procedure TDpccTabStopsTests.SingleNumberIsInterval;
var
  mStops: TDpccTabStops;
begin
  mStops := TDpccTabStops.Parse('4');
  Assert.IsTrue(mStops.IsUniform, 'gleichmäßig');
  Assert.AreEqual(4, mStops.Width, 'Abstand');
  Assert.AreEqual('4', mStops.ToText);
  Assert.AreEqual(5, mStops.NextStop(1), 'von Spalte 1');
  Assert.AreEqual(5, mStops.NextStop(4), 'von Spalte 4');
  Assert.AreEqual(9, mStops.NextStop(5), 'von Spalte 5');
  Assert.AreEqual(9, mStops.NextStop(6), 'von Spalte 6');
  Assert.AreEqual(5, mStops.NextStop(0), 'Spalte 0 wie 1');
  // Mit Leerzeichen um die Zahl wie aus den Editoroptionen.
  Assert.AreEqual(4, TDpccTabStops.Parse(' 4 ').Width, 'Leerzeichen');
end;

procedure TDpccTabStopsTests.TwoStopsContinueWithLastInterval;
var
  mStops: TDpccTabStops;
begin
  mStops := TDpccTabStops.Parse('3 5');
  Assert.IsFalse(mStops.IsUniform, 'feste Positionen');
  Assert.AreEqual(2, mStops.Width, 'Abstand hinter der letzten');
  Assert.AreEqual('3 5', mStops.ToText);
  Assert.AreEqual(3, mStops.NextStop(1), '1 → 3');
  Assert.AreEqual(3, mStops.NextStop(2), '2 → 3');
  Assert.AreEqual(5, mStops.NextStop(3), '3 → 5');
  Assert.AreEqual(5, mStops.NextStop(4), '4 → 5');
  Assert.AreEqual(7, mStops.NextStop(5), '5 → 7');
  Assert.AreEqual(7, mStops.NextStop(6), '6 → 7');
  Assert.AreEqual(9, mStops.NextStop(7), '7 → 9');
  Assert.AreEqual(21, mStops.NextStop(20), '20 → 21');
end;

procedure TDpccTabStopsTests.NineSeventeenEqualsEight;
var
  mStops, mEight: TDpccTabStops;
  mColumn: Integer;
begin
  mStops := TDpccTabStops.Parse('9 17');
  mEight := TDpccTabStops.Parse('8');
  Assert.AreEqual(8, mStops.Width, 'Abstand');
  for mColumn := 1 to 60 do
  begin
    Assert.AreEqual(mEight.NextStop(mColumn), mStops.NextStop(mColumn), Format('Spalte %d', [mColumn]));
  end;
end;

procedure TDpccTabStopsTests.IrregularList;
var
  mStops: TDpccTabStops;
begin
  mStops := TDpccTabStops.Parse('4 10 20');
  Assert.AreEqual(10, mStops.Width, 'Abstand hinter der letzten');
  Assert.AreEqual(4, mStops.NextStop(1), '1 → 4');
  Assert.AreEqual(10, mStops.NextStop(4), '4 → 10');
  Assert.AreEqual(10, mStops.NextStop(9), '9 → 10');
  Assert.AreEqual(20, mStops.NextStop(10), '10 → 20');
  Assert.AreEqual(30, mStops.NextStop(20), '20 → 30');
  Assert.AreEqual(30, mStops.NextStop(29), '29 → 30');
  Assert.AreEqual(40, mStops.NextStop(30), '30 → 40');
  // Auch mit anderen Trennern.
  Assert.AreEqual('4 10 20', TDpccTabStops.Parse('4,10;20').ToText, 'Komma und Semikolon');
  Assert.AreEqual('4 10 20', TDpccTabStops.Parse('  4   10'#9'20 ').ToText, 'mehrere Leerzeichen und Tab');
end;

procedure TDpccTabStopsTests.InvalidFallsBackToEight;
const
  cInvalid: array[0..8] of string = ('', '   ', 'abc', '0', '-3', '8 4', '5 5', '4 x 8', '3 5 4');
var
  mText: string;
  mStops: TDpccTabStops;
begin
  for mText in cInvalid do
  begin
    mStops := TDpccTabStops.Parse(mText);
    Assert.IsTrue(mStops.IsUniform, Format('"%s" gleichmäßig', [mText]));
    Assert.AreEqual(8, mStops.Width, Format('"%s" Abstand 8', [mText]));
    Assert.AreEqual(9, mStops.NextStop(1), Format('"%s" von Spalte 1', [mText]));
  end;
  // Ohne Angabe (Default) und mit Weite < 1 ebenso.
  mStops := Default(TDpccTabStops);
  Assert.AreEqual(8, mStops.Width, 'Default');
  Assert.AreEqual(9, mStops.NextStop(1), 'Default von Spalte 1');
  Assert.AreEqual(8, TDpccTabStops.Uniform(0).Width, 'Weite 0');
  Assert.AreEqual(8, TDpccTabStops.Uniform(-2).Width, 'Weite negativ');
end;

procedure TDpccTabStopsTests.TabsInMiddleOfLine;
const
  // a b <Tab> c <Tab> d
  cLine = 'ab'#9'c'#9'd';
var
  mStops: TDpccTabStops;
begin
  // "3 5": a in Spalte 1, b in 2, Tab ab 3 bis vor 5, c in 5, Tab ab 6 bis vor 7, d in 7.
  mStops := TDpccTabStops.Parse('3 5');
  Assert.AreEqual(1, mStops.IndexToColumn(cLine, 0), 'a');
  Assert.AreEqual(3, mStops.IndexToColumn(cLine, 2), 'erster Tab');
  Assert.AreEqual(5, mStops.IndexToColumn(cLine, 3), 'c');
  Assert.AreEqual(6, mStops.IndexToColumn(cLine, 4), 'zweiter Tab');
  Assert.AreEqual(7, mStops.IndexToColumn(cLine, 5), 'd');
  Assert.AreEqual(8, mStops.IndexToColumn(cLine, 6), 'Zeilenende');
  Assert.AreEqual(3, mStops.ColumnToIndex(cLine, 5), 'Spalte 5 = c');
  Assert.AreEqual(5, mStops.ColumnToIndex(cLine, 7), 'Spalte 7 = d');
  Assert.AreEqual(2, mStops.ColumnToIndex(cLine, 3), 'Spalte 3 = Tab');
  Assert.AreEqual(3, mStops.ColumnToIndex(cLine, 4), 'Spalte 4 im Tab: Zeichen danach');
  Assert.AreEqual(6, mStops.ColumnToIndex(cLine, 30), 'hinter dem Ende höchstens die Länge');
  // Abstand 8: c in Spalte 9, d in Spalte 17.
  mStops := TDpccTabStops.Uniform(8);
  Assert.AreEqual(9, mStops.IndexToColumn(cLine, 3), 'c bei 8');
  Assert.AreEqual(17, mStops.IndexToColumn(cLine, 5), 'd bei 8');
  Assert.AreEqual(5, mStops.ColumnToIndex(cLine, 17), 'Spalte 17 = d');
  // "4 10 20" mit führendem Tab: x in Spalte 4, Tab ab 5 bis vor 10, y in 10.
  mStops := TDpccTabStops.Parse('4 10 20');
  Assert.AreEqual(4, mStops.IndexToColumn(#9'x'#9'y', 1), 'x');
  Assert.AreEqual(10, mStops.IndexToColumn(#9'x'#9'y', 3), 'y');
  Assert.AreEqual(3, mStops.ColumnToIndex(#9'x'#9'y', 10), 'Spalte 10 = y');
end;

procedure TDpccTabStopsTests.RoundTripIndexColumnIndex;
const
  cStops: array[0..4] of string = ('8', '4', '3 5', '9 17', '4 10 20');
  cLines: array[0..3] of string = ('', 'procedure Bar;', #9#9'procedure Berechne(A: Integer);',
    'a'#9'bc'#9#9'd'#9'e');
var
  mStopsText, mLine: string;
  mStops: TDpccTabStops;
  mIndex: Integer;
begin
  for mStopsText in cStops do
  begin
    mStops := TDpccTabStops.Parse(mStopsText);
    for mLine in cLines do
    begin
      for mIndex := 0 to Length(mLine) + 3 do
      begin
        if mIndex <= Length(mLine) then
        begin
          Assert.AreEqual(mIndex, mStops.ColumnToIndex(mLine, mStops.IndexToColumn(mLine, mIndex)),
            Format('"%s", Index %d', [mStopsText, mIndex]));
        end
        else
        begin
          // Hinter dem Zeilenende: Spalte zählt weiter, der Index bleibt bei der Länge.
          Assert.AreEqual(Length(mLine), mStops.ColumnToIndex(mLine, mStops.IndexToColumn(mLine, mIndex)),
            Format('"%s", Index %d hinter dem Ende', [mStopsText, mIndex]));
        end;
      end;
    end;
  end;
end;

procedure TDpccTabStopsTests.DisplayLineFillsToNextStop;
begin
  Assert.AreEqual('ab  c', TDpccTabStops.Parse('3 5').DisplayLine('ab'#9'c'), '"3 5"');
  Assert.AreEqual('ab      c', TDpccTabStops.Uniform(8).DisplayLine('ab'#9'c'), 'Abstand 8');
  Assert.AreEqual('   x     y', TDpccTabStops.Parse('4 10 20').DisplayLine(#9'x'#9'y'), '"4 10 20"');
  Assert.AreEqual('ohne Tab', TDpccTabStops.Uniform(8).DisplayLine('ohne Tab'), 'ohne Tab unverändert');
end;

procedure TDpccTabStopsTests.SessionOverloadsAgree;
const
  cLine = #9#9'procedure Berechne(A: Integer);';
begin
  // Wie TabIndentedDeclaration (GotoBothWays): zwei Tabs und "procedure ", "Berechne" in Spalte 27 bei Weite 8.
  Assert.AreEqual(12, TLspSessionJson.ColumnToIndex(cLine, 27, 8), 'Zahl');
  Assert.AreEqual(12, TLspSessionJson.ColumnToIndex(cLine, 27, TDpccTabStops.Uniform(8)), 'TDpccTabStops');
  Assert.AreEqual(27, TLspSessionJson.IndexToColumn(cLine, 12, 8), 'Umkehrung mit Zahl');
  Assert.AreEqual(27, TLspSessionJson.IndexToColumn(cLine, 12, TDpccTabStops.Uniform(8)), 'Umkehrung');
  // "3 5": Tabs bis Spalte 3 und 5, "procedure " ab 5, "Berechne" in Spalte 15.
  Assert.AreEqual(15, TLspSessionJson.IndexToColumn(cLine, 12, TDpccTabStops.Parse('3 5')), 'unregelmäßig');
  Assert.AreEqual(12, TLspSessionJson.ColumnToIndex(cLine, 15, TDpccTabStops.Parse('3 5')), 'unregelmäßig zurück');
  // Weite 0: vorher eine Division durch null in ColumnToIndex; jetzt wie 8.
  Assert.AreEqual(12, TLspSessionJson.ColumnToIndex(cLine, 27, 0), 'Weite 0 wie 8');
  // IndexToColumn mit Weite 0 wie bisher: ein Tab eine Spalte.
  Assert.AreEqual(13, TLspSessionJson.IndexToColumn(cLine, 12, 0), 'Weite 0 bei IndexToColumn wie bisher');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccTabStopsTests);

end.
