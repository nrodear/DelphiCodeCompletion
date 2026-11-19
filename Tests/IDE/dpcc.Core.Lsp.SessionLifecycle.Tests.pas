unit dpcc.Core.Lsp.SessionLifecycle.Tests;

// Tests für den Zustand von Start und Stopp der Sitzung (dpcc.Core.Lsp.SessionLifecycle), ohne IDE und ohne
// Threads: Idle → Starting → Ready, verworfene und fehlgeschlagene Starts, Sperrzeit nach einem Fehlschlag, Abbruch
// eines laufenden Starts (Generation), Verlust der Sitzung, Entladen und die Zähler der Stopps im Hintergrund.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccSessionLifecycleTests = class
  public
    /// <summary>Idle → Starting → Ready; während Starting kein zweiter Start.</summary>
    [Test]
    procedure StartAndAdopt;
    /// <summary>Fehlschlag: Idle mit Sperrzeit; erst nach cRetryBlockMs wieder ein Start; der Fehler bleibt gemerkt.
    /// </summary>
    [Test]
    procedure FailureBlocksRetry;
    /// <summary>Start von Hand hebt die Sperre auf.</summary>
    [Test]
    procedure ClearBlockAllowsStart;
    /// <summary>Abbruch während Starting: der alte Start wird verworfen, auch wenn er erfolgreich war; ein neuer Start
    /// mit neuer Generation wird übernommen.</summary>
    [Test]
    procedure CancelDiscardsRunningStart;
    /// <summary>Inzwischen nicht mehr erwünscht (Hauptschalter aus): verworfen, ohne Sperre.</summary>
    [Test]
    procedure NotAllowedIsDiscardedWithoutBlock;
    /// <summary>Stopp einer bereiten Sitzung und Verlust (Server von selbst beendet): Idle, sofort neu startbar.
    /// </summary>
    [Test]
    procedure CancelAndLossOfReadySession;
    /// <summary>Close (Entladen): laufender Start verworfen, keine neuen.</summary>
    [Test]
    procedure CloseRejectsStarts;
    /// <summary>Zähler der Stopps im Hintergrund.</summary>
    [Test]
    procedure StopCounters;
  end;

implementation

uses
  dpcc.Core.Lsp.SessionLifecycle;

const
  cT0 = 1000000;

{ TDpccSessionLifecycleTests }

procedure TDpccSessionLifecycleTests.StartAndAdopt;
var
  mLife: TDpccSessionLifecycle;
  mGeneration, mSecond: Cardinal;
begin
  mLife := TDpccSessionLifecycle.Create;
  try
    Assert.AreEqual(Ord(TDpccSessionPhase.Idle), Ord(mLife.Phase), 'anfangs Idle');
    Assert.IsTrue(mLife.TryBeginStart(cT0, mGeneration), 'Start beginnt');
    Assert.AreEqual(Ord(TDpccSessionPhase.Starting), Ord(mLife.Phase), 'Starting');
    Assert.AreEqual(Integer(mGeneration), Integer(mLife.Generation), 'Generation vergeben');
    Assert.IsFalse(mLife.TryBeginStart(cT0 + 1, mSecond), 'kein zweiter Start');
    Assert.AreEqual(Ord(TDpccStartOutcome.Adopt), Ord(mLife.FinishStart(mGeneration, True, True, cT0 + 10)),
      'übernehmen');
    Assert.AreEqual(Ord(TDpccSessionPhase.Ready), Ord(mLife.Phase), 'Ready');
    Assert.IsFalse(mLife.TryBeginStart(cT0 + 20, mSecond), 'bereit: kein Start');
    Assert.AreEqual('', mLife.LastError, 'kein Fehler');
  finally
    mLife.Free;
  end;
end;

procedure TDpccSessionLifecycleTests.FailureBlocksRetry;
var
  mLife: TDpccSessionLifecycle;
  mGeneration: Cardinal;
begin
  mLife := TDpccSessionLifecycle.Create;
  try
    Assert.IsTrue(mLife.TryBeginStart(cT0, mGeneration));
    Assert.AreEqual(Ord(TDpccStartOutcome.Failed), Ord(mLife.FinishStart(mGeneration, False, True, cT0 + 100,
      'kaputt')), 'Fehlschlag');
    Assert.AreEqual(Ord(TDpccSessionPhase.Idle), Ord(mLife.Phase), 'Idle');
    Assert.AreEqual('kaputt', mLife.LastError, 'Fehler gemerkt');
    Assert.IsTrue(mLife.Blocked(cT0 + 101), 'gesperrt');
    Assert.AreEqual(TDpccSessionLifecycle.cRetryBlockMs - 1, Integer(mLife.BlockLeftMs(cT0 + 101)), 'Restzeit');
    Assert.IsFalse(mLife.TryBeginStart(cT0 + 100 + TDpccSessionLifecycle.cRetryBlockMs - 1, mGeneration),
      'kurz vor Ablauf kein Start');
    Assert.IsFalse(mLife.Blocked(cT0 + 100 + TDpccSessionLifecycle.cRetryBlockMs), 'Sperre abgelaufen');
    Assert.IsTrue(mLife.TryBeginStart(cT0 + 100 + TDpccSessionLifecycle.cRetryBlockMs, mGeneration),
      'danach wieder');
    Assert.AreEqual(Ord(TDpccStartOutcome.Adopt), Ord(mLife.FinishStart(mGeneration, True, True,
      cT0 + 200 + TDpccSessionLifecycle.cRetryBlockMs)), 'übernommen');
    Assert.AreEqual('', mLife.LastError, 'Fehler vergessen');
  finally
    mLife.Free;
  end;
end;

procedure TDpccSessionLifecycleTests.ClearBlockAllowsStart;
var
  mLife: TDpccSessionLifecycle;
  mGeneration: Cardinal;
begin
  mLife := TDpccSessionLifecycle.Create;
  try
    Assert.IsTrue(mLife.TryBeginStart(cT0, mGeneration));
    mLife.FinishStart(mGeneration, False, True, cT0);
    Assert.IsFalse(mLife.TryBeginStart(cT0 + 1, mGeneration), 'gesperrt');
    mLife.ClearBlock;
    Assert.AreEqual(0, Integer(mLife.BlockLeftMs(cT0 + 1)), 'keine Restzeit');
    Assert.IsTrue(mLife.TryBeginStart(cT0 + 1, mGeneration), 'von Hand wieder');
  finally
    mLife.Free;
  end;
end;

procedure TDpccSessionLifecycleTests.CancelDiscardsRunningStart;
var
  mLife: TDpccSessionLifecycle;
  mOld, mNew: Cardinal;
begin
  mLife := TDpccSessionLifecycle.Create;
  try
    Assert.IsTrue(mLife.TryBeginStart(cT0, mOld));
    Assert.AreEqual(Ord(TDpccSessionPhase.Starting), Ord(mLife.Cancel), 'Zustand davor');
    Assert.AreEqual(Ord(TDpccSessionPhase.Idle), Ord(mLife.Phase), 'Idle');
    Assert.IsTrue(mOld <> mLife.Generation, 'neue Generation');
    // Der abgebrochene Start meldet sich spät, sogar erfolgreich: verworfen, ohne Sperre.
    Assert.AreEqual(Ord(TDpccStartOutcome.Discard), Ord(mLife.FinishStart(mOld, True, True, cT0 + 5)), 'verworfen');
    Assert.AreEqual(Ord(TDpccSessionPhase.Idle), Ord(mLife.Phase), 'bleibt Idle');
    Assert.IsFalse(mLife.Blocked(cT0 + 5), 'keine Sperre');
    // Ein neuer Start läuft, der alte meldet sich erst jetzt: Der neue bleibt unberührt.
    Assert.IsTrue(mLife.TryBeginStart(cT0 + 6, mNew));
    Assert.IsTrue(mOld <> mNew, 'andere Generation');
    Assert.AreEqual(Ord(TDpccStartOutcome.Discard), Ord(mLife.FinishStart(mOld, False, True, cT0 + 7)),
      'alter Fehlschlag zählt nicht');
    Assert.AreEqual(Ord(TDpccSessionPhase.Starting), Ord(mLife.Phase), 'neuer läuft weiter');
    Assert.IsFalse(mLife.Blocked(cT0 + 7), 'alter Fehlschlag sperrt nicht');
    Assert.AreEqual(Ord(TDpccStartOutcome.Adopt), Ord(mLife.FinishStart(mNew, True, True, cT0 + 8)), 'neuer');
  finally
    mLife.Free;
  end;
end;

procedure TDpccSessionLifecycleTests.NotAllowedIsDiscardedWithoutBlock;
var
  mLife: TDpccSessionLifecycle;
  mGeneration: Cardinal;
begin
  mLife := TDpccSessionLifecycle.Create;
  try
    Assert.IsTrue(mLife.TryBeginStart(cT0, mGeneration));
    Assert.AreEqual(Ord(TDpccStartOutcome.Discard), Ord(mLife.FinishStart(mGeneration, True, False, cT0 + 1)),
      'nicht mehr erwünscht');
    Assert.AreEqual(Ord(TDpccSessionPhase.Idle), Ord(mLife.Phase), 'Idle');
    Assert.IsTrue(mLife.TryBeginStart(cT0 + 2, mGeneration), 'sofort wieder startbar');
  finally
    mLife.Free;
  end;
end;

procedure TDpccSessionLifecycleTests.CancelAndLossOfReadySession;
var
  mLife: TDpccSessionLifecycle;
  mGeneration, mBefore: Cardinal;
begin
  mLife := TDpccSessionLifecycle.Create;
  try
    Assert.IsTrue(mLife.TryBeginStart(cT0, mGeneration));
    mLife.FinishStart(mGeneration, True, True, cT0);
    mBefore := mLife.Generation;
    Assert.AreEqual(Ord(TDpccSessionPhase.Ready), Ord(mLife.Cancel), 'Stopp aus Ready');
    Assert.AreEqual(Integer(mBefore), Integer(mLife.Generation),
      'Stopp einer bereiten Sitzung ändert die Generation nicht');
    Assert.AreEqual(Ord(TDpccSessionPhase.Idle), Ord(mLife.Phase), 'Idle');
    Assert.IsTrue(mLife.TryBeginStart(cT0 + 1, mGeneration), 'neu startbar');
    mLife.FinishStart(mGeneration, True, True, cT0 + 2);
    mLife.SessionLost;
    Assert.AreEqual(Ord(TDpccSessionPhase.Idle), Ord(mLife.Phase), 'verloren: Idle');
    Assert.IsFalse(mLife.Blocked(cT0 + 3), 'keine Sperre nach Absturz');
    Assert.IsTrue(mLife.TryBeginStart(cT0 + 3, mGeneration), 'Neustart');
    // SessionLost wirkt nur auf Ready.
    mLife.SessionLost;
    Assert.AreEqual(Ord(TDpccSessionPhase.Starting), Ord(mLife.Phase), 'Starting bleibt');
  finally
    mLife.Free;
  end;
end;

procedure TDpccSessionLifecycleTests.CloseRejectsStarts;
var
  mLife: TDpccSessionLifecycle;
  mGeneration: Cardinal;
begin
  mLife := TDpccSessionLifecycle.Create;
  try
    Assert.IsTrue(mLife.TryBeginStart(cT0, mGeneration));
    mLife.Close;
    Assert.IsTrue(mLife.Closed, 'geschlossen');
    Assert.AreEqual(Ord(TDpccSessionPhase.Idle), Ord(mLife.Phase), 'Idle');
    Assert.AreEqual(Ord(TDpccStartOutcome.Discard), Ord(mLife.FinishStart(mGeneration, True, True, cT0 + 1)),
      'laufender Start verworfen');
    Assert.IsFalse(mLife.TryBeginStart(cT0 + 2, mGeneration), 'keine neuen Starts');
  finally
    mLife.Free;
  end;
end;

procedure TDpccSessionLifecycleTests.StopCounters;
var
  mLife: TDpccSessionLifecycle;
begin
  mLife := TDpccSessionLifecycle.Create;
  try
    Assert.IsFalse(mLife.Stopping, 'anfangs kein Stopp');
    mLife.StopBegun;
    mLife.StopBegun;
    Assert.AreEqual(2, mLife.Stops, 'zwei Stopps');
    Assert.IsTrue(mLife.Stopping, 'Stopping');
    mLife.StopEnded;
    mLife.StopEnded;
    Assert.IsFalse(mLife.Stopping, 'fertig');
    // Ein überzähliges Ende (etwa nach dem Entladen) zählt nicht unter 0.
    mLife.StopEnded;
    Assert.AreEqual(0, mLife.Stops, 'nicht negativ');
  finally
    mLife.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccSessionLifecycleTests);

end.
