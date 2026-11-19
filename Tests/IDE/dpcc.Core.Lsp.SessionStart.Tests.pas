unit dpcc.Core.Lsp.SessionStart.Tests;

// Tests für die gemeinsamen Objekte von Hauptthread und Start-/Stopp-Threads (dpcc.Core.Lsp.SessionStart), ohne
// IDE: genau ein Besitzer je Start (Deliver, Take, Cancel), der Ablauf „Start läuft, Manager wird abgebaut,
// Start-Thread meldet sich später“ mit echtem Thread (der Thread bleibt Besitzer, nichts geht an den Manager), das
// einmalige Ende des Servers, der Fortschritts-Merker, der Stopp-Zähler und die Leerlauf-Signale.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccSessionStartTests = class
  public
    /// <summary>Abgeben, übernehmen: genau einmal; danach weder Take noch Cancel mit Ergebnis.</summary>
    [Test]
    procedure DeliverThenTake;
    /// <summary>Abgegeben, dann abgebrochen: Cancel liefert das Ergebnis (der Hauptthread stoppt es), Take nicht.
    /// </summary>
    [Test]
    procedure DeliverThenCancel;
    /// <summary>Start läuft, der Manager wird abgebaut (Close, Cancel, letzter Verweis des Managers weg); der
    /// Start-Thread meldet sich später: Deliver liefert False, der Thread bleibt Besitzer; das Ticket lebt über den
    /// Verweis des Threads; der Zustand verwirft den späten Start.</summary>
    [Test]
    procedure LateStartAfterManagerTeardown;
    /// <summary>Ende des Servers wird genau einmal gemeldet; Fortschritt höchstens einmal eingereiht.</summary>
    [Test]
    procedure EndReportAndProgressOnce;
    /// <summary>Stopp-Zähler: Warten endet, sobald der letzte Stopp (in einem Thread) fertig ist.</summary>
    [Test]
    procedure StopGateWaitsForThread;
    /// <summary>Leerlauf-Signale: je eine Statusabfrage und ein Befehl, beliebig viele Bedienbefehle.</summary>
    [Test]
    procedure IdleSignals;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.SessionLifecycle,
  dpcc.Core.Lsp.SessionStart;

function NewJob(AGeneration: Cardinal): TDpccStartJob;
begin
  Result := Default(TDpccStartJob);
  Result.Generation := AGeneration;
  Result.Locale := 'de';
end;

/// <summary>Arbeit eines Start-Threads: eigener Verweis auf das Ticket (nicht die Variable des Tests), wartet auf
/// AGo und gibt dann ab. ADelivered und AOwned überleben den Thread (der Test wartet auf ihn).</summary>
function DeliverLater(const ATicket: IDpccStartTicket; AGo: TEvent; ADelivered, AOwned: PBoolean): TProc;
var
  mOwn: IDpccStartTicket;
  mGo: TEvent;
  mDelivered, mOwned: PBoolean;
begin
  mOwn := ATicket;
  mGo := AGo;
  mDelivered := ADelivered;
  mOwned := AOwned;
  Result :=
    procedure
    begin
      mGo.WaitFor(5000);
      mDelivered^ := mOwn.Deliver(nil, nil, '', 10);
      // Abgebrochen: Dieser Thread ist Besitzer und räumt selbst ab.
      mOwned^ := not mDelivered^;
      mOwn := nil;
    end;
end;

/// <summary>Arbeit eines Stopp-Threads: kurz warten, dann Leave am eigenen Verweis.</summary>
function LeaveLater(const AGate: IDpccStopGate): TProc;
var
  mOwn: IDpccStopGate;
begin
  mOwn := AGate;
  Result :=
    procedure
    begin
      Sleep(20);
      mOwn.Leave;
    end;
end;

{ TDpccSessionStartTests }

procedure TDpccSessionStartTests.DeliverThenTake;
var
  mTicket: IDpccStartTicket;
  mServer: IDpccLspServer;
  mSession: TLspSession;
  mError: string;
  mMs: Int64;
begin
  mTicket := TDpccStartTicket.Create(NewJob(7));
  Assert.AreEqual(7, Integer(mTicket.Job.Generation), 'Generation');
  Assert.IsFalse(mTicket.Take(mServer, mSession, mError, mMs), 'vor der Abgabe nichts');
  Assert.IsTrue(mTicket.Deliver(nil, nil, 'grund', 42), 'abgegeben');
  Assert.IsFalse(mTicket.Deliver(nil, nil, 'zweimal', 1), 'nur einmal');
  Assert.IsTrue(mTicket.Take(mServer, mSession, mError, mMs), 'übernommen');
  Assert.AreEqual('grund', mError, 'Grund');
  Assert.AreEqual(42, Integer(mMs), 'Dauer');
  Assert.IsFalse(mTicket.Take(mServer, mSession, mError, mMs), 'kein zweites Mal');
  Assert.IsFalse(mTicket.Cancel(mServer, mSession), 'nach der Übernahme nichts mehr zu stoppen');
  Assert.IsTrue(mTicket.Cancelled, 'aber abgebrochen');
end;

procedure TDpccSessionStartTests.DeliverThenCancel;
var
  mTicket: IDpccStartTicket;
  mServer: IDpccLspServer;
  mSession: TLspSession;
  mError: string;
  mMs: Int64;
begin
  mTicket := TDpccStartTicket.Create(NewJob(1));
  Assert.IsTrue(mTicket.Deliver(nil, nil, '', 5), 'abgegeben');
  Assert.IsTrue(mTicket.Cancel(mServer, mSession), 'Hauptthread ist Besitzer');
  Assert.IsFalse(mTicket.Take(mServer, mSession, mError, mMs), 'eingereihte Übernahme danach: nichts');
  Assert.IsFalse(mTicket.Cancel(mServer, mSession), 'zweiter Abbruch: nichts');
end;

procedure TDpccSessionStartTests.LateStartAfterManagerTeardown;
var
  mLife: TDpccSessionLifecycle;
  mGeneration: Cardinal;
  mTicket: IDpccStartTicket;
  mServer: IDpccLspServer;
  mSession: TLspSession;
  mGo: TEvent;
  mThread: TThread;
  mDelivered, mOwnedByThread: Boolean;
begin
  mLife := TDpccSessionLifecycle.Create;
  mGo := TEvent.Create(nil, True, False, '');
  try
    Assert.IsTrue(mLife.TryBeginStart(1000, mGeneration), 'Start läuft');
    mTicket := TDpccStartTicket.Create(NewJob(mGeneration));
    mDelivered := True;
    mOwnedByThread := False;
    // Der Start-Thread hält nur das Ticket (eigener Verweis), nie den Manager.
    mThread := TThread.CreateAnonymousThread(DeliverLater(mTicket, mGo, @mDelivered, @mOwnedByThread));
    mThread.FreeOnTerminate := False;
    mThread.Start;
    // Manager wird abgebaut: Zustand schließen, Start abbrechen, eigenen Verweis aufgeben.
    mLife.Close;
    Assert.IsFalse(mTicket.Cancel(mServer, mSession), 'noch nichts abgegeben: nichts zu stoppen');
    Assert.IsNull(mSession, 'keine Sitzung');
    mTicket := nil;
    // Jetzt meldet sich der Start-Thread.
    mGo.SetEvent;
    mThread.WaitFor;
    mThread.Free;
    Assert.IsFalse(mDelivered, 'Deliver nach dem Abbau: False');
    Assert.IsTrue(mOwnedByThread, 'der Thread bleibt Besitzer');
    // Käme die eingereihte Rückmeldung doch an, verwürfe der Zustand sie.
    Assert.AreEqual(Ord(TDpccStartOutcome.Discard), Ord(mLife.FinishStart(mGeneration, True, True, 2000)),
      'später Start verworfen');
    Assert.IsFalse(mLife.TryBeginStart(3000, mGeneration), 'kein neuer Start nach dem Abbau');
  finally
    mGo.Free;
    mLife.Free;
  end;
end;

procedure TDpccSessionStartTests.EndReportAndProgressOnce;
var
  mTicket: IDpccStartTicket;
begin
  mTicket := TDpccStartTicket.Create(NewJob(1));
  Assert.IsTrue(mTicket.TakeEndReport, 'erstes Ende');
  Assert.IsFalse(mTicket.TakeEndReport, 'kein zweites');
  Assert.IsTrue(mTicket.TryMarkProgress, 'Fortschritt eingereiht');
  Assert.IsFalse(mTicket.TryMarkProgress, 'wartet schon');
  mTicket.ClearProgress;
  Assert.IsTrue(mTicket.TryMarkProgress, 'nach dem Lauf wieder');
end;

procedure TDpccSessionStartTests.StopGateWaitsForThread;
var
  mGate: IDpccStopGate;
  mThread: TThread;
begin
  mGate := TDpccStopGate.Create;
  Assert.IsTrue(mGate.WaitIdle(0), 'anfangs frei');
  mGate.Enter;
  mGate.Enter;
  Assert.AreEqual(2, mGate.Count, 'zwei Stopps');
  Assert.IsFalse(mGate.WaitIdle(0), 'läuft');
  mGate.Leave;
  Assert.IsFalse(mGate.WaitIdle(0), 'einer läuft noch');
  mThread := TThread.CreateAnonymousThread(LeaveLater(mGate));
  mThread.FreeOnTerminate := False;
  mThread.Start;
  try
    Assert.IsTrue(mGate.WaitIdle(5000), 'nach dem letzten Stopp frei');
    Assert.AreEqual(0, mGate.Count, 'keiner mehr');
  finally
    mThread.WaitFor;
    mThread.Free;
  end;
  // Ein überzähliges Leave zählt nicht unter 0.
  mGate.Leave;
  Assert.AreEqual(0, mGate.Count, 'nicht negativ');
end;

procedure TDpccSessionStartTests.IdleSignals;
var
  mSignals: IDpccIdleSignals;
begin
  mSignals := TDpccIdleSignals.Create;
  Assert.IsTrue(mSignals.WaitQuery(0) and mSignals.WaitCommand(0) and mSignals.WaitServerCommands(0), 'anfangs frei');
  Assert.IsTrue(mSignals.TryBeginQuery, 'Abfrage');
  Assert.IsFalse(mSignals.TryBeginQuery, 'nur eine Abfrage');
  Assert.IsTrue(mSignals.QueryRunning, 'läuft');
  Assert.IsFalse(mSignals.WaitQuery(0), 'Stopp wartet');
  mSignals.EndQuery;
  Assert.IsTrue(mSignals.WaitQuery(0), 'frei');
  Assert.IsTrue(mSignals.TryBeginCommand, 'Befehl');
  Assert.IsFalse(mSignals.TryBeginCommand, 'nur ein Befehl');
  mSignals.EndCommand;
  Assert.IsFalse(mSignals.CommandRunning, 'fertig');
  mSignals.BeginServerCommand;
  mSignals.BeginServerCommand;
  Assert.AreEqual(2, mSignals.ServerCommands, 'zwei Bedienbefehle');
  mSignals.EndServerCommand;
  Assert.IsFalse(mSignals.WaitServerCommands(0), 'einer läuft');
  mSignals.EndServerCommand;
  Assert.IsTrue(mSignals.WaitServerCommands(0), 'alle fertig');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccSessionStartTests);

end.
