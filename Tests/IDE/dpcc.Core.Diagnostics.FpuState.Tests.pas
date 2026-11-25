unit dpcc.Core.Diagnostics.FpuState.Tests;

// Tests für die Gleitkomma-Einstellung im dpcc.log (FPU1, dpcc.Core.Diagnostics.FpuState), nur mit Zahlen:
// - Klartext zum x87-Steuerwort: welche der sechs Ausnahmen nicht maskiert sind ($033F Vorgabe der RTL, $137A aus dem
//   Absturzabbild, $1372 und $1332 ältere Vorgaben, $0000 nichts maskiert);
// - Vergleich nur der Masken (Bits 0–5) und des ganzen Worts;
// - Start- und Änderungszeile;
// - TDpccFpuWatch: nur Änderungen gegenüber dem zuletzt gemeldeten Stand, höchstens 20 Meldungen, die letzte mit
//   Hinweis; inaktiv vor Reset und nach Clear.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccFpuStateTests = class
  public
    /// <summary>Klartext für $033F, $137A, $1372, $1332 und $0000; Hex mit vier Stellen.</summary>
    [Test]
    procedure ControlWordTexts;
    /// <summary>SameMasks vergleicht nur Bits 0–5, Changed das ganze Wort.</summary>
    [Test]
    procedure MaskComparison;
    /// <summary>Startzeile: Vorgabe und Hauptthread mit Klartext, MXCSR nur als Hex.</summary>
    [Test]
    procedure StartLineNamesBothWords;
    /// <summary>Änderungszeile: alter → neuer Wert je Teil, unverändert bzw. „Masken gleich“, Sekunden und Nummer; die
    /// letzte erlaubte Meldung mit Hinweis.</summary>
    [Test]
    procedure ChangeLineShowsOldAndNew;
    /// <summary>Zustandshalter: keine Zeile ohne Änderung, neuer Stand nach jeder Meldung, Änderung nur im Hauptthread.
    /// </summary>
    [Test]
    procedure WatchReportsOnlyChanges;
    /// <summary>Zustandshalter: höchstens 20 Meldungen, die 20. mit Hinweis; inaktiv vor Reset und nach Clear.
    /// </summary>
    [Test]
    procedure WatchStopsAtLimit;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  dpcc.Core.Diagnostics.FpuState;

const
  cHint = '; weitere Änderungen werden nicht mehr gemeldet';

{ TDpccFpuStateTests }

procedure TDpccFpuStateTests.ControlWordTexts;
begin
  Assert.AreEqual('$033F (alle maskiert)', TDpccFpuState.ControlWordText($033F));
  Assert.AreEqual('$137A (nicht maskiert: Invalid, ZeroDivide)', TDpccFpuState.ControlWordText($137A));
  Assert.AreEqual('$1372 (nicht maskiert: Invalid, ZeroDivide, Overflow)', TDpccFpuState.ControlWordText($1372));
  Assert.AreEqual('$1332 (nicht maskiert: Invalid, ZeroDivide, Overflow)', TDpccFpuState.ControlWordText($1332));
  Assert.AreEqual('$0000 (nicht maskiert: Invalid, Denormal, ZeroDivide, Overflow, Underflow, Precision)',
    TDpccFpuState.ControlWordText($0000));
  Assert.AreEqual('', TDpccFpuState.UnmaskedNames(TDpccFpuState.cDefault8087CW), 'Vorgabe der RTL');
  Assert.AreEqual('$1F80', TDpccFpuState.HexText($1F80));
  Assert.AreEqual('$003F', TDpccFpuState.HexText($3F));
end;

procedure TDpccFpuStateTests.MaskComparison;
begin
  Assert.IsTrue(TDpccFpuState.SameMasks($033F, $033F), 'gleich');
  Assert.IsTrue(TDpccFpuState.SameMasks($033F, $133F), 'nur Genauigkeit anders');
  Assert.IsTrue(TDpccFpuState.SameMasks($1372, $1332), 'nur Bit 6 anders');
  Assert.IsFalse(TDpccFpuState.SameMasks($033F, $137A), 'Invalid und ZeroDivide frei');
  Assert.IsFalse(TDpccFpuState.SameMasks($003F, $003E), 'nur Invalid frei');
  Assert.IsFalse(TDpccFpuState.Changed($033F, $033F), 'ganzes Wort gleich');
  Assert.IsTrue(TDpccFpuState.Changed($1372, $1332), 'ganzes Wort anders');
  Assert.IsTrue(TDpccFpuState.Changed($033F, $133F), 'Genauigkeit anders');
end;

procedure TDpccFpuStateTests.StartLineNamesBothWords;
begin
  Assert.AreEqual('Gleitkomma beim Start: Vorgabe $137A (nicht maskiert: Invalid, ZeroDivide); ' +
    'Hauptthread $033F (alle maskiert); MXCSR Vorgabe $1F80, Hauptthread $1FA0',
    TDpccFpuState.StartLine($137A, $033F, $1F80, $1FA0));
end;

procedure TDpccFpuStateTests.ChangeLineShowsOldAndNew;
begin
  Assert.AreEqual('Gleitkomma geändert nach 42 s (Meldung 1 von höchstens 20): ' +
    'Vorgabe $033F (alle maskiert) → $137A (nicht maskiert: Invalid, ZeroDivide); ' +
    'Hauptthread unverändert $033F (alle maskiert)',
    TDpccFpuState.ChangeLine($033F, $137A, $033F, $033F, 42, 1, 20));
  Assert.AreEqual('Hauptthread $1332 (nicht maskiert: Invalid, ZeroDivide, Overflow) → ' +
    '$1372 (nicht maskiert: Invalid, ZeroDivide, Overflow), Masken gleich',
    TDpccFpuState.ChangeText('Hauptthread', $1332, $1372));
  Assert.AreEqual('Vorgabe unverändert $137A (nicht maskiert: Invalid, ZeroDivide)',
    TDpccFpuState.ChangeText('Vorgabe', $137A, $137A));
  Assert.IsFalse(EndsStr(cHint, TDpccFpuState.ChangeLine($033F, $137A, $033F, $033F, 1, 19, 20)), 'vorletzte');
  Assert.IsTrue(EndsStr(cHint, TDpccFpuState.ChangeLine($033F, $137A, $033F, $033F, 1, 20, 20)), 'letzte');
end;

procedure TDpccFpuStateTests.WatchReportsOnlyChanges;
var
  mWatch: TDpccFpuWatch;
  mLine: string;
begin
  mWatch := Default(TDpccFpuWatch);
  mWatch.Reset($033F, $033F);
  Assert.IsTrue(mWatch.Active, 'aktiv nach Reset');
  Assert.IsFalse(mWatch.Differs($033F, $033F), 'nichts geändert');
  Assert.AreEqual('', mWatch.Take($033F, $033F, 1), 'keine Zeile ohne Änderung');
  Assert.AreEqual(0, mWatch.Reported);
  // Nur der Hauptthread ändert sich.
  mLine := mWatch.Take($033F, $137A, 5);
  Assert.IsTrue(ContainsStr(mLine, 'nach 5 s (Meldung 1 von höchstens 20)'), mLine);
  Assert.IsTrue(ContainsStr(mLine, 'Vorgabe unverändert $033F (alle maskiert); ' +
    'Hauptthread $033F (alle maskiert) → $137A (nicht maskiert: Invalid, ZeroDivide)'), mLine);
  Assert.AreEqual(1, mWatch.Reported);
  Assert.AreEqual(Integer($033F), Integer(mWatch.LastDefault), 'Vorgabe gemerkt');
  Assert.AreEqual(Integer($137A), Integer(mWatch.LastMain), 'Hauptthread gemerkt');
  // Gleicher Stand wie zuletzt gemeldet: keine weitere Zeile.
  Assert.IsFalse(mWatch.Differs($033F, $137A), 'Stand schon gemeldet');
  Assert.AreEqual('', mWatch.Take($033F, $137A, 6));
  // Auch eine Änderung nur außerhalb der Masken wird gemeldet.
  mLine := mWatch.Take($133F, $137A, 7);
  Assert.IsTrue(ContainsStr(mLine, 'Vorgabe $033F (alle maskiert) → $133F (alle maskiert), Masken gleich'), mLine);
  Assert.AreEqual(2, mWatch.Reported);
end;

procedure TDpccFpuStateTests.WatchStopsAtLimit;
var
  mWatch: TDpccFpuWatch;
  mLine, mLast: string;
  mIndex, mLines: Integer;
  mMain: Word;
begin
  mWatch := Default(TDpccFpuWatch);
  Assert.IsFalse(mWatch.Active, 'inaktiv vor Reset');
  Assert.IsFalse(mWatch.Differs($137A, $137A), 'inaktiv: nichts zu melden');
  Assert.AreEqual('', mWatch.Take($137A, $137A, 1));
  mWatch.Reset($033F, $033F);
  mLines := 0;
  mLast := '';
  for mIndex := 1 to 30 do
  begin
    if Odd(mIndex) then
    begin
      mMain := $137A;
    end
    else
    begin
      mMain := $033F;
    end;
    mLine := mWatch.Take($033F, mMain, mIndex);
    if mLine <> '' then
    begin
      Inc(mLines);
      if mLines = TDpccFpuState.cMaxReports then
      begin
        Assert.IsTrue(EndsStr(cHint, mLine), Format('Hinweis in der letzten Meldung (%d)', [mLines]));
      end
      else
      begin
        Assert.IsFalse(EndsStr(cHint, mLine), Format('kein Hinweis vor der letzten Meldung (%d)', [mLines]));
      end;
      mLast := mLine;
    end;
  end;
  Assert.AreEqual(TDpccFpuState.cMaxReports, mLines, 'höchstens 20 Meldungen');
  Assert.AreEqual(20, mWatch.Reported);
  Assert.IsTrue(ContainsStr(mLast, '(Meldung 20 von höchstens 20)'), mLast);
  Assert.IsFalse(mWatch.Differs($0000, $0000), 'Obergrenze erreicht');
  mWatch.Clear;
  Assert.IsFalse(mWatch.Active, 'inaktiv nach Clear');
  Assert.AreEqual(0, mWatch.Reported);
  Assert.IsFalse(mWatch.Differs($0000, $0000), 'nach Clear nichts zu melden');
  // Neu angemeldet: wieder von vorn.
  mWatch.Reset($033F, $033F);
  Assert.IsTrue(ContainsStr(mWatch.Take($137A, $033F, 1), '(Meldung 1 von höchstens 20)'), 'neu gezählt');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccFpuStateTests);

end.
