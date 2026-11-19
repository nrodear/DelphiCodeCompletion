unit dpcc.Core.Lsp.IdeSlices.Tests;

// Tests für die Zeitscheiben der IDE-Typen und -Mitglieder (dpcc.Core.Lsp.IdeSlices): Fortsetzen über Takte
// (Packages und Typen bzw. Palette und Komponenten), Zeitbudget nach jedem Schritt, Neu-Laden nach entladenen
// Modulen, Fehler je Element, Statistik der Takte, Zuordnung Unit → Module und das Zusammenführen mehrerer
// Anforderungen dpcc/ideMembersWanted samt Abbruch.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccIdeSlicesTests = class
  public
    /// <summary>Ohne Budgetgrenze: ein Aufruf besucht alles in Reihenfolge, leere Elemente werden übergangen.
    /// </summary>
    [Test]
    procedure WalkVisitsAllInOrder;
    /// <summary>Budget schon erschöpft: jeder Aufruf erledigt genau einen Schritt (Laden oder Besuch) und kommt voran.
    /// </summary>
    [Test]
    procedure WalkMakesOneStepWhenExhausted;
    /// <summary>Das Budget gilt nach jedem einzelnen Typ, nicht erst nach einem ganzen Package.</summary>
    [Test]
    procedure WalkChecksBudgetAfterEachVisit;
    /// <summary>Reload lädt die innere Liste neu und setzt an derselben Stelle fort; ist sie kürzer, geht es weiter.
    /// </summary>
    [Test]
    procedure WalkReloadContinuesAtSamePlace;
    /// <summary>Eine Ausnahme beim Laden oder Besuchen lässt nur dieses Element aus.</summary>
    [Test]
    procedure WalkSkipsFailingElements;
    /// <summary>Ohne äußere Elemente sofort fertig.</summary>
    [Test]
    procedure WalkEmptyIsDone;
    /// <summary>Takte zählen, Summe und längster Takt.</summary>
    [Test]
    procedure StatsCountStepsAndLongest;
    /// <summary>Module der Units ohne Groß-/Kleinschreibung und ohne doppelte; eine unbekannte Unit: False.</summary>
    [Test]
    procedure UnitModulesFindModules;
    /// <summary>Anforderung während eines Laufs: kein zweiter Lauf, die Units laufen danach genau einmal vereint.
    /// </summary>
    [Test]
    procedure MemberQueueMergesRequests;
    /// <summary>Abbruch (neue Sitzung, Stopp): Der alte Lauf ist veraltet, wartende Units entfallen, sein Ende ändert
    /// nichts mehr.</summary>
    [Test]
    procedure MemberQueueCancelDropsRun;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Lsp.IdeSlices;

const
  /// <summary>Typen je Package im Beispiel: das mittlere ist leer.</summary>
  cCounts: array[0..2] of Integer = (2, 0, 3);

/// <summary>Besuchte Stellen als Text ("0.0 0.1 2.0").</summary>
function Visits(const AText: string; AOuter, AInner: Integer): string;
begin
  Result := Trim(AText + ' ' + IntToStr(AOuter) + '.' + IntToStr(AInner));
end;

procedure TDpccIdeSlicesTests.WalkVisitsAllInOrder;
var
  mWalk: TDpccSliceWalk;
  mText: string;
  mLoads: Integer;
begin
  mText := '';
  mLoads := 0;
  mWalk := TDpccSliceWalk.Create(3);
  try
    Assert.IsTrue(mWalk.Run(
      function(AOuter: Integer): Integer
      begin
        Inc(mLoads);
        Result := cCounts[AOuter];
      end,
      procedure(AOuter, AInner: Integer)
      begin
        mText := Visits(mText, AOuter, AInner);
      end,
      function: Boolean
      begin
        Result := False;
      end));
    Assert.AreEqual('0.0 0.1 2.0 2.1 2.2', mText);
    Assert.AreEqual(3, mLoads);
    Assert.IsTrue(mWalk.Done);
  finally
    mWalk.Free;
  end;
end;

procedure TDpccIdeSlicesTests.WalkMakesOneStepWhenExhausted;
var
  mWalk: TDpccSliceWalk;
  mSteps: Integer;
  mRuns: Integer;
  mLoad: TFunc<Integer, Integer>;
  mVisit: TProc<Integer, Integer>;
  mExhausted: TFunc<Boolean>;
begin
  mSteps := 0;
  mRuns := 0;
  mLoad :=
    function(AOuter: Integer): Integer
    begin
      Inc(mSteps);
      Result := cCounts[AOuter];
    end;
  mVisit :=
    procedure(AOuter, AInner: Integer)
    begin
      Inc(mSteps);
    end;
  mExhausted :=
    function: Boolean
    begin
      Result := True;
    end;
  mWalk := TDpccSliceWalk.Create(3);
  try
    repeat
      Inc(mRuns);
      Assert.IsTrue(mRuns < 100, 'kommt nicht voran');
    until mWalk.Run(mLoad, mVisit, mExhausted);
    // Drei Laden und fünf Besuche, je Aufruf genau einer.
    Assert.AreEqual(8, mSteps);
    Assert.AreEqual(8, mRuns);
  finally
    mWalk.Free;
  end;
end;

procedure TDpccIdeSlicesTests.WalkChecksBudgetAfterEachVisit;
var
  mWalk: TDpccSliceWalk;
  mClockMs: Integer;
  mVisits: Integer;
  mDone: Boolean;
begin
  mClockMs := 0;
  mVisits := 0;
  mWalk := TDpccSliceWalk.Create(1);
  try
    // Ein großes Package (100 Typen), je Typ 4 ms, Budget 10 ms: nach dem dritten Typ ist Schluss.
    mDone := mWalk.Run(
      function(AOuter: Integer): Integer
      begin
        Result := 100;
      end,
      procedure(AOuter, AInner: Integer)
      begin
        Inc(mVisits);
        Inc(mClockMs, 4);
      end,
      function: Boolean
      begin
        Result := mClockMs >= 10;
      end);
    Assert.IsFalse(mDone);
    Assert.AreEqual(3, mVisits);
    Assert.AreEqual(0, mWalk.Outer);
    Assert.AreEqual(3, mWalk.Inner, 'setzt im Package fort');
  finally
    mWalk.Free;
  end;
end;

procedure TDpccIdeSlicesTests.WalkReloadContinuesAtSamePlace;
var
  mWalk: TDpccSliceWalk;
  mText: string;
  mLoads: Integer;
  mStop: Boolean;
  mLoad: TFunc<Integer, Integer>;
  mVisit: TProc<Integer, Integer>;
  mExhausted: TFunc<Boolean>;
begin
  mText := '';
  mLoads := 0;
  mStop := True;
  mLoad :=
    function(AOuter: Integer): Integer
    begin
      Inc(mLoads);
      Result := 3;
    end;
  mVisit :=
    procedure(AOuter, AInner: Integer)
    begin
      mText := Visits(mText, AOuter, AInner);
    end;
  mExhausted :=
    function: Boolean
    begin
      Result := mStop;
    end;
  mWalk := TDpccSliceWalk.Create(2);
  try
    // Laden, dann 0.0.
    mWalk.Run(mLoad, mVisit, mExhausted);
    mWalk.Run(mLoad, mVisit, mExhausted);
    Assert.AreEqual('0.0', mText);
    // Module haben sich geändert: neu laden, dann weiter bei 0.1.
    mWalk.Reload;
    mStop := False;
    Assert.IsTrue(mWalk.Run(mLoad, mVisit, mExhausted));
    Assert.AreEqual('0.0 0.1 0.2 1.0 1.1 1.2', mText);
    Assert.AreEqual(3, mLoads);
  finally
    mWalk.Free;
  end;
end;

procedure TDpccIdeSlicesTests.WalkSkipsFailingElements;
var
  mWalk: TDpccSliceWalk;
  mText: string;
  mRuns: Integer;
  mLoad: TFunc<Integer, Integer>;
  mVisit: TProc<Integer, Integer>;
  mExhausted: TFunc<Boolean>;
begin
  mText := '';
  mLoad :=
    function(AOuter: Integer): Integer
    begin
      if AOuter = 1 then
      begin
        raise EInvalidOpException.Create('RTTI unlesbar');
      end;
      Result := 2;
    end;
  mVisit :=
    procedure(AOuter, AInner: Integer)
    begin
      if (AOuter = 0) and (AInner = 0) then
      begin
        raise EInvalidOpException.Create('Typ unlesbar');
      end;
      mText := Visits(mText, AOuter, AInner);
    end;
  mExhausted :=
    function: Boolean
    begin
      Result := False;
    end;
  mRuns := 0;
  mWalk := TDpccSliceWalk.Create(3);
  try
    repeat
      Inc(mRuns);
      Assert.IsTrue(mRuns < 10, 'kommt nicht voran');
      try
        mWalk.Run(mLoad, mVisit, mExhausted);
      except
        on EInvalidOpException do
          ;
      end;
    until mWalk.Done;
    Assert.AreEqual('0.1 2.0 2.1', mText);
  finally
    mWalk.Free;
  end;
end;

procedure TDpccIdeSlicesTests.WalkEmptyIsDone;
var
  mWalk: TDpccSliceWalk;
  mCalls: Integer;
begin
  mCalls := 0;
  mWalk := TDpccSliceWalk.Create(0);
  try
    Assert.IsTrue(mWalk.Done);
    Assert.IsTrue(mWalk.Run(
      function(AOuter: Integer): Integer
      begin
        Inc(mCalls);
        Result := 1;
      end,
      procedure(AOuter, AInner: Integer)
      begin
        Inc(mCalls);
      end,
      function: Boolean
      begin
        Result := True;
      end));
    Assert.AreEqual(0, mCalls);
  finally
    mWalk.Free;
  end;
end;

procedure TDpccIdeSlicesTests.StatsCountStepsAndLongest;
var
  mStats: TDpccSliceStats;
begin
  mStats := Default(TDpccSliceStats);
  mStats.Add(3);
  mStats.Add(17);
  mStats.Add(9);
  Assert.AreEqual(3, mStats.Steps);
  Assert.AreEqual(Int64(29), mStats.TotalMs);
  Assert.AreEqual(Int64(17), mStats.LongestMs);
end;

procedure TDpccIdeSlicesTests.UnitModulesFindModules;
var
  mMap: TDpccUnitModules;
  mModules: TArray<string>;
begin
  mMap := TDpccUnitModules.Create;
  try
    mMap.Add('DUnitX.TestFramework', 'C:\Studio\bin\DUnitXRuntime.bpl');
    mMap.Add('DUnitX.TestFramework', 'C:\Studio\bin\DUnitXRuntime.bpl');
    mMap.Add('DUnitX.Assert', 'C:\STUDIO\BIN\dunitxruntime.bpl');
    mMap.Add('FireDAC.Comp.Client', 'C:\Studio\bin\FireDAC.bpl');
    mMap.Add('', 'C:\Studio\bin\leer.bpl');
    mMap.Add('Ohne.Modul', '');
    Assert.AreEqual(3, mMap.Count);
    Assert.IsTrue(mMap.ModulesOf(['dunitx.testframework', 'DUnitX.Assert', 'FireDAC.Comp.Client'], mModules));
    Assert.AreEqual(2, Integer(Length(mModules)), 'ein Modul je Package');
    Assert.AreEqual('C:\Studio\bin\DUnitXRuntime.bpl', mModules[0]);
    Assert.AreEqual('C:\Studio\bin\FireDAC.bpl', mModules[1]);
    Assert.IsFalse(mMap.ModulesOf(['DUnitX.Assert', 'Unbekannt.Unit'], mModules), 'unbekannt: alle besuchen');
    Assert.AreEqual(0, Integer(Length(mModules)));
  finally
    mMap.Free;
  end;
end;

procedure TDpccIdeSlicesTests.MemberQueueMergesRequests;
var
  mQueue: TDpccIdeMemberQueue;
  mUnits: TArray<string>;
  mFirst, mSecond: Cardinal;
begin
  mQueue := Default(TDpccIdeMemberQueue);
  Assert.IsTrue(mQueue.Request(['DUnitX.TestFramework']), 'nichts läuft: beginnen');
  Assert.IsTrue(mQueue.TryStart(mUnits, mFirst));
  Assert.AreEqual(1, Integer(Length(mUnits)));
  Assert.IsTrue(mQueue.IsCurrent(mFirst));
  // Während des Laufs: merken, nicht beginnen; doppelte zählen einmal.
  Assert.IsFalse(mQueue.Request(['FireDAC.Comp.Client', 'DUnitX.Assert']));
  Assert.IsFalse(mQueue.Request(['firedac.comp.client', ' ']));
  Assert.IsFalse(mQueue.TryStart(mUnits, mSecond), 'nie zwei Läufe zugleich');
  Assert.AreEqual(2, Integer(Length(mQueue.Pending)));
  // Ende des Laufs: Es wartet etwas, genau ein weiterer Lauf mit allen Units.
  Assert.IsTrue(mQueue.Finish(mFirst));
  Assert.IsTrue(mQueue.TryStart(mUnits, mSecond));
  Assert.AreEqual('FireDAC.Comp.Client,DUnitX.Assert', string.Join(',', mUnits));
  Assert.IsTrue(mFirst <> mSecond, 'neue Generation');
  Assert.IsFalse(mQueue.TryStart(mUnits, mFirst), 'kein dritter Lauf');
  Assert.IsFalse(mQueue.Finish(mSecond), 'nichts wartet mehr');
  Assert.IsFalse(mQueue.Running);
end;

procedure TDpccIdeSlicesTests.MemberQueueCancelDropsRun;
var
  mQueue: TDpccIdeMemberQueue;
  mUnits: TArray<string>;
  mOld, mNew: Cardinal;
begin
  mQueue := Default(TDpccIdeMemberQueue);
  mQueue.Request(['Vcl.Forms']);
  Assert.IsTrue(mQueue.TryStart(mUnits, mOld));
  mQueue.Request(['Vcl.Controls']);
  mQueue.Cancel;
  Assert.IsFalse(mQueue.IsCurrent(mOld), 'abgebrochen: nichts mehr senden');
  Assert.IsFalse(mQueue.Running);
  Assert.AreEqual(0, Integer(Length(mQueue.Pending)), 'wartende Units entfallen');
  // Neue Sitzung fragt neu; das Ende des alten Laufs stört den neuen nicht.
  Assert.IsTrue(mQueue.Request(['Vcl.Graphics']));
  Assert.IsTrue(mQueue.TryStart(mUnits, mNew));
  Assert.IsFalse(mQueue.Finish(mOld));
  Assert.IsTrue(mQueue.IsCurrent(mNew), 'der neue Lauf läuft weiter');
  Assert.IsFalse(mQueue.Finish(mNew));
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccIdeSlicesTests);

end.
