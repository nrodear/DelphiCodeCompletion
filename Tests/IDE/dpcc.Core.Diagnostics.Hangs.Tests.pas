unit dpcc.Core.Diagnostics.Hangs.Tests;

// Tests für die reine Logik des Einfrier-Wächters (dpcc.Core.Diagnostics.Hangs) und die Listen der langsamsten
// Aufrufe (PluginTimings, Timing), mit einstellbarer Uhr, ohne Thread und ohne Fenster:
// - Aktivitätsstapel: innerster Name für den Wächter, Dauer je Scope, Arbeit der IDE zählt nicht und ist keine
//   dpcc-Aktivität, Nachrichtenschleife unterdrückt die Dauerzeile, Abbau außer der Reihe, Kürzen, volle Tiefe.
// - Drosselung je Name (eine Zeile je Minute, übergangene zählen mit) und Budget je Minute.
// - Wächter-Zustand: Schwelle 250 ms, Zeilen bei Beginn und Ende, ohne dpcc-Aktivität nur im Diagnosemodus,
//   höchstens 5 Hänger je Minute einzeln, Summe der übrigen, Pausen des ganzen Prozesses zählen nicht.

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccHangsTests = class
  private
    FNowMs: Int64;
    FNowUs: Int64;
    function Clock: TFunc<Int64>;
  public
    [Test]
    procedure StackTopIsInnermost;
    [Test]
    procedure StackMeasuresEachScope;
    /// <summary>Arbeit der IDE (RunIde) ist keine dpcc-Aktivität und zählt für keinen umgebenden Scope.</summary>
    [Test]
    procedure IdeWorkIsExcludedAndNotDpcc;
    [Test]
    procedure PumpedMarksScope;
    /// <summary>Endet ein äußerer Scope zuerst, verschwinden die inneren mit; ihr spätes Ende tut nichts.</summary>
    [Test]
    procedure OuterPopDropsInner;
    [Test]
    procedure LongNameIsTruncated;
    [Test]
    procedure DeepStackBeyondMaxDepth;
    /// <summary>TDpccActivity im Thread der Tests: im Hauptthread verschachtelt lesbar, sonst nil.</summary>
    [Test]
    procedure ActivityScopesNestInMainThread;
    [Test]
    procedure ThrottleOneLinePerNameAndInterval;
    [Test]
    procedure SlowLogLines;
    [Test]
    procedure SlowLogOffStoresNothing;
    [Test]
    procedure LineBudgetPerWindow;
    [Test]
    procedure MonitorThresholdIs250;
    [Test]
    procedure TrackerBelowThresholdIsSilent;
    [Test]
    procedure TrackerReportsDpccHangAtStartAndEnd;
    [Test]
    procedure TrackerWithoutActivityIsSilentWithoutDiagnose;
    [Test]
    procedure TrackerWithoutActivityGoesToDiagnosticLog;
    [Test]
    procedure TrackerActivityFoundLater;
    [Test]
    procedure TrackerAnswerJustBelowThresholdCountsAsThreshold;
    /// <summary>Höchstens 5 Hänger je Minute einzeln; die übrigen als Summe bei der nächsten Zeile und am Ende.</summary>
    [Test]
    procedure TrackerThrottlesFivePerMinute;
    /// <summary>Stand der ganze Prozess (Debugger, Ruhezustand), zählt die Lücke nicht als Hänger.</summary>
    [Test]
    procedure TrackerPauseIsNoHang;
    [Test]
    procedure TrackerPauseDuringHangIsExcluded;
    [Test]
    procedure RecorderKeepsTenSlowest;
    [Test]
    procedure QueryReportListsSlowestFirst;
  end;

implementation

uses
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Hangs,
  dpcc.Core.Diagnostics.PluginTimings,
  dpcc.Core.Diagnostics.Timing;

function ZeroTime: TFunc<TDateTime>;
begin
  Result :=
    function: TDateTime
    begin
      Result := 0;
    end;
end;

function NewTracker(ADiagnose: Boolean): TDpccHangTracker;
begin
  Result := TDpccHangTracker.Create(ADiagnose, ZeroTime());
end;

{ TDpccHangsTests }

function TDpccHangsTests.Clock: TFunc<Int64>;
begin
  Result :=
    function: Int64
    begin
      Result := FNowMs;
    end;
end;

procedure TDpccHangsTests.StackTopIsInnermost;
var
  mStack: TDpccActivityStack;
  mOuter, mInner: Integer;
  mMs: Int64;
  mPumped: Boolean;
begin
  FNowMs := 0;
  mStack := TDpccActivityStack.Create(Clock());
  try
    Assert.AreEqual('', mStack.Top);
    mOuter := mStack.Push('Außen', TDpccActivityKind.Timed);
    mInner := mStack.Push('Innen', TDpccActivityKind.Feature);
    Assert.AreEqual('Innen', mStack.Top);
    Assert.IsTrue(mStack.Pop(mInner, mMs, mPumped));
    Assert.AreEqual('Außen', mStack.Top);
    Assert.IsTrue(mStack.Pop(mOuter, mMs, mPumped));
    Assert.AreEqual('', mStack.Top);
    Assert.AreEqual(0, mStack.Depth);
  finally
    mStack.Free;
  end;
end;

procedure TDpccHangsTests.StackMeasuresEachScope;
var
  mStack: TDpccActivityStack;
  mOuter, mInner: Integer;
  mMs: Int64;
  mPumped: Boolean;
begin
  FNowMs := 1000;
  mStack := TDpccActivityStack.Create(Clock());
  try
    mOuter := mStack.Push('Außen', TDpccActivityKind.Timed);
    FNowMs := 1010;
    mInner := mStack.Push('Innen', TDpccActivityKind.Timed);
    FNowMs := 1070;
    Assert.IsTrue(mStack.Pop(mInner, mMs, mPumped));
    Assert.AreEqual(60, Integer(mMs), 'innen');
    Assert.IsFalse(mPumped);
    FNowMs := 1100;
    Assert.IsTrue(mStack.Pop(mOuter, mMs, mPumped));
    Assert.AreEqual(100, Integer(mMs), 'außen samt innen');
  finally
    mStack.Free;
  end;
end;

procedure TDpccHangsTests.IdeWorkIsExcludedAndNotDpcc;
var
  mStack: TDpccActivityStack;
  mOuter, mMiddle, mIde: Integer;
  mMs: Int64;
  mPumped: Boolean;
begin
  FNowMs := 0;
  mStack := TDpccActivityStack.Create(Clock());
  try
    mOuter := mStack.Push('Außen', TDpccActivityKind.Feature);
    FNowMs := 10;
    mMiddle := mStack.Push('Mitte', TDpccActivityKind.Timed);
    FNowMs := 20;
    mIde := mStack.Push('IDE', TDpccActivityKind.Ide);
    Assert.AreEqual('', mStack.Top, 'Arbeit der IDE ist keine dpcc-Aktivität');
    FNowMs := 220;
    Assert.IsTrue(mStack.Pop(mIde, mMs, mPumped));
    Assert.AreEqual('Mitte', mStack.Top);
    FNowMs := 230;
    Assert.IsTrue(mStack.Pop(mMiddle, mMs, mPumped));
    Assert.AreEqual(20, Integer(mMs), 'Mitte ohne die 200 ms der IDE');
    FNowMs := 240;
    Assert.IsTrue(mStack.Pop(mOuter, mMs, mPumped));
    Assert.AreEqual(40, Integer(mMs), 'außen ohne die 200 ms der IDE');
  finally
    mStack.Free;
  end;
end;

procedure TDpccHangsTests.PumpedMarksScope;
var
  mStack: TDpccActivityStack;
  mToken: Integer;
  mMs: Int64;
  mPumped: Boolean;
begin
  FNowMs := 0;
  mStack := TDpccActivityStack.Create(Clock());
  try
    mToken := mStack.Push('Dialog', TDpccActivityKind.Timed);
    mStack.Pumped;
    Assert.IsTrue(mStack.Pop(mToken, mMs, mPumped));
    Assert.IsTrue(mPumped, 'Nachrichtenschleife lief');
    mToken := mStack.Push('Blockiert', TDpccActivityKind.Timed);
    Assert.IsTrue(mStack.Pop(mToken, mMs, mPumped));
    Assert.IsFalse(mPumped, 'keine Nachricht dazwischen');
  finally
    mStack.Free;
  end;
end;

procedure TDpccHangsTests.OuterPopDropsInner;
var
  mStack: TDpccActivityStack;
  mOuter, mInner: Integer;
  mMs: Int64;
  mPumped: Boolean;
begin
  FNowMs := 0;
  mStack := TDpccActivityStack.Create(Clock());
  try
    mOuter := mStack.Push('Außen', TDpccActivityKind.Timed);
    mInner := mStack.Push('Innen', TDpccActivityKind.Timed);
    Assert.IsTrue(mStack.Pop(mOuter, mMs, mPumped));
    Assert.AreEqual(0, mStack.Depth);
    Assert.IsFalse(mStack.Pop(mInner, mMs, mPumped), 'schon abgebaut');
    Assert.AreEqual(0, mStack.Depth);
  finally
    mStack.Free;
  end;
end;

procedure TDpccHangsTests.LongNameIsTruncated;
var
  mStack: TDpccActivityStack;
  mToken: Integer;
  mMs: Int64;
  mPumped: Boolean;
begin
  FNowMs := 0;
  mStack := TDpccActivityStack.Create(Clock());
  try
    mToken := mStack.Push(StringOfChar('x', TDpccActivityStack.cMaxNameLength + 20), TDpccActivityKind.Timed);
    Assert.AreEqual(StringOfChar('x', TDpccActivityStack.cMaxNameLength), mStack.Top);
    Assert.IsTrue(mStack.Pop(mToken, mMs, mPumped));
  finally
    mStack.Free;
  end;
end;

procedure TDpccHangsTests.DeepStackBeyondMaxDepth;
var
  mStack: TDpccActivityStack;
  mTokens: array[0..TDpccActivityStack.cMaxDepth] of Integer;
  mIndex: Integer;
  mMs: Int64;
  mPumped: Boolean;
begin
  FNowMs := 0;
  mStack := TDpccActivityStack.Create(Clock());
  try
    for mIndex := 0 to TDpccActivityStack.cMaxDepth do
    begin
      mTokens[mIndex] := mStack.Push('Ebene ' + IntToStr(mIndex), TDpccActivityKind.Timed);
    end;
    // Der Eintrag über der festen Tiefe ist nicht gespeichert; der Wächter sieht den obersten gespeicherten.
    Assert.AreEqual('Ebene ' + IntToStr(TDpccActivityStack.cMaxDepth - 1), mStack.Top);
    Assert.IsFalse(mStack.Pop(mTokens[TDpccActivityStack.cMaxDepth], mMs, mPumped), 'nicht gespeichert');
    Assert.AreEqual(TDpccActivityStack.cMaxDepth, mStack.Depth);
    for mIndex := TDpccActivityStack.cMaxDepth - 1 downto 0 do
    begin
      Assert.IsTrue(mStack.Pop(mTokens[mIndex], mMs, mPumped), 'Ebene ' + IntToStr(mIndex));
    end;
    Assert.AreEqual(0, mStack.Depth);
  finally
    mStack.Free;
  end;
end;

procedure TDpccHangsTests.ActivityScopesNestInMainThread;
var
  mOuter, mInner, mIde: IInterface;
begin
  mOuter := TDpccActivity.Scope('Test außen');
  if not TDpccActivity.IsMainThread then
  begin
    Assert.IsTrue(mOuter = nil, 'außerhalb des Hauptthreads keine Aktivität');
    Exit;
  end;
  Assert.AreEqual('Test außen', TDpccActivity.Current);
  mInner := TDpccActivity.Waiting('Test warten');
  Assert.AreEqual('Test warten', TDpccActivity.Running);
  mIde := TDpccActivity.IdeWork;
  Assert.AreEqual('', TDpccActivity.Current, 'Arbeit der IDE');
  // Rückwärts freigeben wie am Ende einer Routine.
  mIde := nil;
  Assert.AreEqual('Test warten', TDpccActivity.Current);
  mInner := nil;
  Assert.AreEqual('Test außen', TDpccActivity.Current);
  mOuter := nil;
  Assert.AreEqual('', TDpccActivity.Current);
end;

procedure TDpccHangsTests.ThrottleOneLinePerNameAndInterval;
var
  mThrottle: TDpccLogThrottle;
  mSkipped: Integer;
  mMaxMs: Int64;
begin
  mThrottle := TDpccLogThrottle.Create(60000);
  try
    Assert.IsTrue(mThrottle.Allow('Aktion', 0, 70, mSkipped, mMaxMs), 'erste Meldung');
    Assert.AreEqual(0, mSkipped);
    Assert.IsFalse(mThrottle.Allow('aktion', 100, 80, mSkipped, mMaxMs), 'ohne Groß-/Kleinschreibung');
    Assert.IsFalse(mThrottle.Allow('Aktion', 200, 120, mSkipped, mMaxMs));
    Assert.IsTrue(mThrottle.Allow('Andere', 300, 60, mSkipped, mMaxMs), 'je Name');
    Assert.IsTrue(mThrottle.Allow('Aktion', 60000, 55, mSkipped, mMaxMs), 'nach einer Minute');
    Assert.AreEqual(2, mSkipped, 'übergangene');
    Assert.AreEqual(120, Integer(mMaxMs), 'längste übergangene');
    Assert.IsFalse(mThrottle.Allow('Aktion', 60001, 55, mSkipped, mMaxMs));
  finally
    mThrottle.Free;
  end;
end;

procedure TDpccHangsTests.SlowLogLines;
begin
  Assert.AreEqual('Hauptthread: Vervollständigung öffnen: 87 ms',
    TDpccSlowLog.ActivityLine('Vervollständigung öffnen', 87));
  Assert.AreEqual('Hauptthread wartete 340 ms auf Server textDocument/completion: Zeitlimit',
    TDpccSlowLog.WaitLine('textDocument/completion', 340, 'Zeitlimit'));
  Assert.AreEqual('', TDpccSlowLog.SkippedText(0, 0));
  Assert.AreEqual(' (dazu 3 weitere seit der letzten Meldung, längste 120 ms)', TDpccSlowLog.SkippedText(3, 120));
end;

procedure TDpccHangsTests.SlowLogOffStoresNothing;
begin
  // In den Tests ist das Sammeln aus (nur der Wächter in der IDE schaltet es ein).
  Assert.IsFalse(TDpccSlowLog.Enabled);
  TDpccSlowLog.NoteActivity('Test', 5000);
  TDpccSlowLog.NoteWait('test/method', 5000, 'Antwort');
  Assert.AreEqual(0, Integer(Length(TDpccSlowLog.Take)));
end;

procedure TDpccHangsTests.LineBudgetPerWindow;
var
  mBudget: TDpccLineBudget;
begin
  mBudget.Init(2, 1000);
  Assert.IsTrue(mBudget.Allow(0));
  Assert.IsTrue(mBudget.Allow(10));
  Assert.IsFalse(mBudget.Allow(20));
  Assert.IsFalse(mBudget.Allow(999));
  Assert.IsTrue(mBudget.Allow(1000), 'neues Fenster');
end;

procedure TDpccHangsTests.MonitorThresholdIs250;
var
  mMonitor: TDpccHangMonitor;
  mHang: TDpccHang;
begin
  Assert.AreEqual(250, Integer(TDpccHangMonitor.cDefaultThresholdMs));
  mMonitor := TDpccHangMonitor.Create;
  try
    mHang := Default(TDpccHang);
    mHang.DurationMs := 249;
    Assert.AreEqual('', mMonitor.Finish(mHang));
    Assert.AreEqual(0, mMonitor.Count);
    mHang.DurationMs := 250;
    mHang.Activity := 'Parameterhilfe';
    Assert.AreEqual('Hauptthread hing 250 ms in Parameterhilfe', mMonitor.Finish(mHang));
    Assert.AreEqual(1, mMonitor.WithDpcc);
  finally
    mMonitor.Free;
  end;
end;

procedure TDpccHangsTests.TrackerBelowThresholdIsSilent;
var
  mTracker: TDpccHangTracker;
begin
  mTracker := NewTracker(True);
  try
    mTracker.Sent(0);
    Assert.AreEqual(0, Integer(Length(mTracker.Waiting(200, 'A'))));
    Assert.AreEqual(0, Integer(Length(mTracker.Answered(240))));
    Assert.AreEqual(0, mTracker.Monitor.Count);
    Assert.AreEqual(0, Integer(Length(mTracker.Summary)));
  finally
    mTracker.Free;
  end;
end;

procedure TDpccHangsTests.TrackerReportsDpccHangAtStartAndEnd;
var
  mTracker: TDpccHangTracker;
  mLines: TArray<TDpccHangLine>;
begin
  mTracker := NewTracker(False);
  try
    mTracker.Sent(0);
    Assert.AreEqual(0, Integer(Length(mTracker.Waiting(100, 'Vervollständigung öffnen'))));
    mLines := mTracker.Waiting(260, 'Vervollständigung öffnen');
    Assert.AreEqual(1, Integer(Length(mLines)));
    Assert.AreEqual('Hauptthread hängt seit 260 ms in Vervollständigung öffnen', mLines[0].Text);
    Assert.IsFalse(mLines[0].Diagnostic);
    Assert.AreEqual(0, Integer(Length(mTracker.Waiting(500, 'Vervollständigung öffnen'))), 'nur einmal');
    mLines := mTracker.Answered(1300);
    Assert.AreEqual(1, Integer(Length(mLines)));
    Assert.AreEqual('Hauptthread hing 1300 ms in Vervollständigung öffnen', mLines[0].Text);
    Assert.IsFalse(mLines[0].Diagnostic);
    Assert.AreEqual(1, mTracker.Monitor.WithDpcc);
    mLines := mTracker.Summary;
    Assert.AreEqual(1, Integer(Length(mLines)));
    Assert.AreEqual('Hänger mit dpcc-Aktivität in dieser Sitzung: 1, längster 1300 ms, nicht einzeln protokolliert: 0',
      mLines[0].Text);
  finally
    mTracker.Free;
  end;
end;

procedure TDpccHangsTests.TrackerWithoutActivityIsSilentWithoutDiagnose;
var
  mTracker: TDpccHangTracker;
begin
  mTracker := NewTracker(False);
  try
    mTracker.Sent(0);
    Assert.AreEqual(0, Integer(Length(mTracker.Waiting(300, ''))));
    Assert.AreEqual(0, Integer(Length(mTracker.Answered(800))));
    Assert.AreEqual(1, mTracker.Monitor.Count, 'gezählt');
    Assert.AreEqual(0, mTracker.Monitor.WithDpcc);
    Assert.AreEqual(0, Integer(Length(mTracker.Summary)), 'nichts im Normalbetrieb');
  finally
    mTracker.Free;
  end;
end;

procedure TDpccHangsTests.TrackerWithoutActivityGoesToDiagnosticLog;
var
  mTracker: TDpccHangTracker;
  mLines: TArray<TDpccHangLine>;
begin
  mTracker := NewTracker(True);
  try
    mTracker.Sent(0);
    mLines := mTracker.Waiting(300, '');
    Assert.AreEqual(1, Integer(Length(mLines)));
    Assert.AreEqual('Hauptthread hängt seit 300 ms ohne dpcc-Aktivität', mLines[0].Text);
    Assert.IsTrue(mLines[0].Diagnostic);
    mLines := mTracker.Answered(900);
    Assert.AreEqual(1, Integer(Length(mLines)));
    Assert.AreEqual('Hauptthread hing 900 ms ohne dpcc-Aktivität', mLines[0].Text);
    Assert.IsTrue(mLines[0].Diagnostic);
    mLines := mTracker.Summary;
    Assert.AreEqual(1, Integer(Length(mLines)));
    Assert.IsTrue(mLines[0].Diagnostic);
    Assert.IsTrue(mLines[0].Text.StartsWith('Hänger ohne dpcc-Aktivität in dieser Sitzung: 1, längster 900 ms'));
  finally
    mTracker.Free;
  end;
end;

procedure TDpccHangsTests.TrackerActivityFoundLater;
var
  mTracker: TDpccHangTracker;
  mLines: TArray<TDpccHangLine>;
begin
  mTracker := NewTracker(False);
  try
    mTracker.Sent(0);
    Assert.AreEqual(0, Integer(Length(mTracker.Waiting(300, ''))));
    mLines := mTracker.Waiting(350, 'Symbolhinweis');
    Assert.AreEqual(1, Integer(Length(mLines)));
    Assert.AreEqual('Hauptthread hängt seit 350 ms in Symbolhinweis', mLines[0].Text);
    mLines := mTracker.Answered(400);
    Assert.AreEqual('Hauptthread hing 400 ms in Symbolhinweis', mLines[0].Text);
  finally
    mTracker.Free;
  end;
end;

procedure TDpccHangsTests.TrackerAnswerJustBelowThresholdCountsAsThreshold;
var
  mTracker: TDpccHangTracker;
  mLines: TArray<TDpccHangLine>;
begin
  mTracker := NewTracker(False);
  try
    mTracker.Sent(0);
    Assert.AreEqual(1, Integer(Length(mTracker.Waiting(260, 'A'))));
    // Die Antwort wurde knapp vor dem Takt gestempelt.
    mLines := mTracker.Answered(240);
    Assert.AreEqual(1, Integer(Length(mLines)));
    Assert.AreEqual('Hauptthread hing 250 ms in A', mLines[0].Text);
  finally
    mTracker.Free;
  end;
end;

procedure TDpccHangsTests.TrackerThrottlesFivePerMinute;
var
  mTracker: TDpccHangTracker;
  mLines: TArray<TDpccHangLine>;
  mIndex: Integer;
  mBase: Int64;
begin
  mTracker := NewTracker(False);
  try
    for mIndex := 0 to 6 do
    begin
      mBase := mIndex * 2000;
      mTracker.Sent(mBase);
      mLines := mTracker.Waiting(mBase + 300, 'A');
      if mIndex < TDpccHangTracker.cMaxPerMinute then
      begin
        Assert.AreEqual(1, Integer(Length(mLines)), 'Beginn ' + IntToStr(mIndex));
        Assert.AreEqual(1, Integer(Length(mTracker.Answered(mBase + 400))), 'Ende ' + IntToStr(mIndex));
      end
      else
      begin
        Assert.AreEqual(0, Integer(Length(mLines)), 'Beginn gedrosselt ' + IntToStr(mIndex));
        Assert.AreEqual(0, Integer(Length(mTracker.Answered(mBase + 400))), 'Ende gedrosselt ' + IntToStr(mIndex));
      end;
    end;
    Assert.AreEqual(2, mTracker.DpccSkippedTotal);
    // Neue Minute: wieder eine Zeile, mit der Summe der übergangenen.
    mTracker.Sent(61000);
    mLines := mTracker.Waiting(61300, 'A');
    Assert.AreEqual(1, Integer(Length(mLines)));
    Assert.AreEqual('Hauptthread hängt seit 300 ms in A (seit der letzten Meldung 2 Hänger nicht einzeln ' +
      'protokolliert, zusammen 800 ms)', mLines[0].Text);
    mTracker.Answered(61400);
    mLines := mTracker.Summary;
    Assert.AreEqual(1, Integer(Length(mLines)));
    Assert.AreEqual('Hänger mit dpcc-Aktivität in dieser Sitzung: 8, längster 400 ms, nicht einzeln protokolliert: 2',
      mLines[0].Text);
  finally
    mTracker.Free;
  end;
end;

procedure TDpccHangsTests.TrackerPauseIsNoHang;
var
  mTracker: TDpccHangTracker;
begin
  mTracker := NewTracker(True);
  try
    mTracker.Tick(0);
    mTracker.Sent(0);
    mTracker.Tick(50);
    // Debugger hielt die IDE 5 s an: Auch der Wächter lief nicht.
    mTracker.Tick(5050);
    Assert.AreEqual(0, Integer(Length(mTracker.Waiting(5050, 'A'))));
    Assert.AreEqual(0, Integer(Length(mTracker.Answered(5100))));
    Assert.AreEqual(0, mTracker.Monitor.Count);
    Assert.AreEqual(5000, Integer(mTracker.PausedMs));
  finally
    mTracker.Free;
  end;
end;

procedure TDpccHangsTests.TrackerPauseDuringHangIsExcluded;
var
  mTracker: TDpccHangTracker;
  mLines: TArray<TDpccHangLine>;
begin
  mTracker := NewTracker(False);
  try
    mTracker.Tick(0);
    mTracker.Sent(0);
    mTracker.Tick(300);
    Assert.AreEqual(1, Integer(Length(mTracker.Waiting(300, 'A'))));
    mTracker.Tick(10300);
    mLines := mTracker.Answered(10500);
    Assert.AreEqual(1, Integer(Length(mLines)));
    Assert.AreEqual('Hauptthread hing 500 ms in A', mLines[0].Text);
  finally
    mTracker.Free;
  end;
end;

procedure TDpccHangsTests.RecorderKeepsTenSlowest;
var
  mRecorder: TDpccPluginRecorder;
  mCalls: TArray<TDpccSlowCall>;
  mLines: TArray<string>;
  mIndex, mToken: Integer;
begin
  FNowUs := 0;
  mRecorder := TDpccPluginRecorder.Create(
    function: Int64
    begin
      Result := FNowUs;
    end,
    ZeroTime(),
    function: Boolean
    begin
      Result := True;
    end);
  try
    for mIndex := 1 to 12 do
    begin
      mToken := mRecorder.Enter;
      Inc(FNowUs, mIndex * 20 * 1000);
      mRecorder.Leave(TDpccFeature.Completion, mToken);
    end;
    mCalls := mRecorder.Slowest;
    Assert.AreEqual(TDpccPluginRecorder.cTopCapacity, Integer(Length(mCalls)));
    Assert.AreEqual(240, Integer(Round(mCalls[0].Ms)), 'längster zuerst');
    Assert.AreEqual(60, Integer(Round(mCalls[High(mCalls)].Ms)), 'zehntlängster zuletzt');
    mLines := mRecorder.SlowestLines(10);
    Assert.AreEqual(1 + TDpccPluginRecorder.cTopCapacity, Integer(Length(mLines)), 'Überschrift und zehn Aufrufe');
    Assert.AreEqual('Langsamste Aufrufe im Hauptthread (eigene Zeit):', mLines[0]);
  finally
    mRecorder.Free;
  end;
end;

procedure TDpccHangsTests.QueryReportListsSlowestFirst;
var
  mQueries: TArray<TDpccQueryTiming>;
  mLines: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mQueries, 3);
  for mIndex := 0 to High(mQueries) do
  begin
    mQueries[mIndex] := Default(TDpccQueryTiming);
    mQueries[mIndex].ContextMs := -1;
    mQueries[mIndex].FilterSortMs := -1;
    mQueries[mIndex].DrawMs := -1;
    mQueries[mIndex].Providers := nil;
  end;
  mQueries[0].Kind := 'schnell';
  mQueries[0].FirstVisibleMs := 20;
  mQueries[1].Kind := 'langsam';
  mQueries[1].FirstVisibleMs := 400;
  mQueries[2].Kind := 'mittel';
  mQueries[2].FirstVisibleMs := 90;
  mLines := TDpccTimingReport.SlowestLines(mQueries, 2);
  Assert.AreEqual(3, Integer(Length(mLines)), 'Überschrift und zwei Abfragen');
  Assert.IsTrue(mLines[1].Contains('langsam'), mLines[1]);
  Assert.IsTrue(mLines[2].Contains('mittel'), mLines[2]);
  Assert.AreEqual(0, Integer(Length(TDpccTimingReport.SlowestLines(nil, 10))));
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccHangsTests);

end.
