unit dpcc.Core.Diagnostics.PluginModules.Tests;

// Tests für die Modulmenge des Plugins (S7b, dpcc.Core.Diagnostics.PluginModules) und ihre Nutzer:
// - TDpccPluginModules: An- und Abmelden, keine Doppelten, Klassen des eigenen Moduls erkannt.
// - TDpccOverdueThreads mit Modulmengen (V3): Ein überfälliger Thread zählt für jedes seiner Module; läuft er beim
//   Entladen eines davon noch, werden alle festgehalten (nicht nur das Modul, das gerade entladen wird).
// - TDpccThreadList.StopAll übergibt überfällige Threads mit allen dpcc-Modulen, nicht nur mit HInstance von Core.
// Die „Module“ der Tests sind erfundene Handles; Festhalten ersetzt TDpccUnloadSafety.ResetForTests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccPluginModulesTests = class
  public
    /// <summary>Das Modul der Exe (hier liegt dpcc.Core) ist angemeldet, die Klassen daraus gehören zu dpcc.</summary>
    [Test]
    procedure OwnModuleIsRegistered;
    [Test]
    procedure AddAndRemove;
    /// <summary>0 wird nie angemeldet, doppeltes Anmelden zählt einmal.</summary>
    [Test]
    procedure IgnoresZeroAndDuplicates;
    [Test]
    procedure NilClassIsNotOwn;
  end;

  [TestFixture]
  TDpccOverdueThreadsTests = class
  private
    FRelease: TObject;
    FPinned: TArray<NativeUInt>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ein Thread mit zwei Modulen zählt für jedes, für ein drittes nicht; beendet zählt er nicht mehr.
    /// </summary>
    [Test]
    procedure ThreadCountsForEachOfItsModules;
    /// <summary>V3: Läuft der Thread beim Entladen eines seiner Module noch, werden alle seine Module
    /// festgehalten, das entladene zuerst.</summary>
    [Test]
    procedure SettlePinsEveryModuleOfRunningThread;
    /// <summary>Endet der Thread rechtzeitig, wird nichts festgehalten.</summary>
    [Test]
    procedure SettleWithoutRunningThreadPinsNothing;
    /// <summary>V3: TDpccThreadList (dpcc.Core) übergibt einen überfälligen Thread mit allen angemeldeten Modulen,
    /// also auch mit dem von dpcc.IDE.Base, dessen Code er ausführt.</summary>
    [Test]
    procedure ThreadListAdoptsWithAllPluginModules;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  dpcc.Core.Diagnostics.PluginModules,
  dpcc.Core.Diagnostics.UnloadSafety,
  dpcc.Core.Diagnostics.WorkerSlot,
  dpcc.Core.Diagnostics.ThreadList;

const
  // Erfundene Module: nie Adressen geladener Module (unterhalb von 64 KB vergibt Windows keine).
  cModuleA = HMODULE($1000);
  cModuleB = HMODULE($2000);
  cModuleC = HMODULE($3000);
  cWaitMs = 5000;

{ TDpccPluginModulesTests }

procedure TDpccPluginModulesTests.OwnModuleIsRegistered;
begin
  Assert.IsTrue(TDpccPluginModules.Contains(HInstance));
  Assert.IsTrue(TDpccPluginModules.OwnsClass(TDpccPluginModules));
  Assert.IsTrue(TDpccPluginModules.OwnsClass(TDpccOverdueThreads));
end;

procedure TDpccPluginModulesTests.AddAndRemove;
var
  mBefore: Integer;
begin
  mBefore := Length(TDpccPluginModules.All);
  TDpccPluginModules.Add(cModuleA);
  try
    Assert.IsTrue(TDpccPluginModules.Contains(cModuleA));
    Assert.AreEqual(mBefore + 1, Length(TDpccPluginModules.All));
    Assert.AreEqual(UInt64(cModuleA), UInt64(TDpccPluginModules.All[mBefore]));
  finally
    TDpccPluginModules.Remove(cModuleA);
  end;
  Assert.IsFalse(TDpccPluginModules.Contains(cModuleA));
  Assert.AreEqual(mBefore, Length(TDpccPluginModules.All));
  Assert.IsTrue(TDpccPluginModules.Contains(HInstance));
end;

procedure TDpccPluginModulesTests.IgnoresZeroAndDuplicates;
var
  mBefore: Integer;
begin
  mBefore := Length(TDpccPluginModules.All);
  TDpccPluginModules.Add(0);
  Assert.IsFalse(TDpccPluginModules.Contains(0));
  TDpccPluginModules.Add(cModuleB);
  TDpccPluginModules.Add(cModuleB);
  try
    Assert.AreEqual(mBefore + 1, Length(TDpccPluginModules.All));
  finally
    TDpccPluginModules.Remove(cModuleB);
  end;
  Assert.AreEqual(mBefore, Length(TDpccPluginModules.All));
  // Abmelden eines nie angemeldeten Moduls ändert nichts.
  TDpccPluginModules.Remove(cModuleC);
  Assert.AreEqual(mBefore, Length(TDpccPluginModules.All));
end;

procedure TDpccPluginModulesTests.NilClassIsNotOwn;
begin
  Assert.IsFalse(TDpccPluginModules.OwnsClass(nil));
end;

{ TDpccOverdueThreadsTests }

/// <summary>Angehalten erzeugter Thread (FreeOnTerminate aus), der bis ARelease wartet.</summary>
function WaitingThread(ARelease: TEvent): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    begin
      ARelease.WaitFor(cWaitMs);
    end);
  Result.FreeOnTerminate := False;
end;

/// <summary>Index von AModule in AModules; -1 ohne.</summary>
function IndexIn(const AModules: TArray<NativeUInt>; AModule: HMODULE): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AModules) do
  begin
    if AModules[mIndex] = NativeUInt(AModule) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TDpccOverdueThreadsTests.Setup;
begin
  FRelease := TEvent.Create(nil, True, False, '');
  FPinned := nil;
  TDpccUnloadSafety.ResetForTests(
    procedure(AModule: HMODULE)
    begin
      FPinned := FPinned + [NativeUInt(AModule)];
    end);
end;

procedure TDpccOverdueThreadsTests.TearDown;
begin
  TEvent(FRelease).SetEvent;
  // Was ein Test übergeben hat, ist danach beendet und freigegeben.
  TDpccOverdueThreads.Settle(cModuleA, cWaitMs);
  TDpccOverdueThreads.Settle(cModuleB, cWaitMs);
  TDpccOverdueThreads.Settle(HInstance, cWaitMs);
  TDpccUnloadSafety.ResetForTests(nil);
  FPinned := nil;
  FreeAndNil(FRelease);
end;

procedure TDpccOverdueThreadsTests.ThreadCountsForEachOfItsModules;
var
  mThread: TThread;
begin
  mThread := WaitingThread(TEvent(FRelease));
  mThread.Start;
  TDpccOverdueThreads.Adopt(mThread, TArray<HMODULE>.Create(cModuleA, cModuleB));
  Assert.AreEqual(1, TDpccOverdueThreads.Pending(cModuleA));
  Assert.AreEqual(1, TDpccOverdueThreads.Pending(cModuleB));
  Assert.AreEqual(0, TDpccOverdueThreads.Pending(cModuleC));
  TEvent(FRelease).SetEvent;
  Assert.IsTrue(TDpccOverdueThreads.Settle(cModuleB, cWaitMs));
  Assert.AreEqual(0, TDpccOverdueThreads.Pending(cModuleA));
  Assert.AreEqual(0, Length(FPinned));
end;

procedure TDpccOverdueThreadsTests.SettlePinsEveryModuleOfRunningThread;
var
  mThread: TThread;
begin
  mThread := WaitingThread(TEvent(FRelease));
  mThread.Start;
  TDpccOverdueThreads.Adopt(mThread, TArray<HMODULE>.Create(cModuleA, cModuleB));
  Assert.IsFalse(TDpccOverdueThreads.Settle(cModuleB, 10));
  Assert.AreEqual(2, Length(FPinned));
  Assert.AreEqual(0, IndexIn(FPinned, cModuleB), 'das entladene Modul zuerst');
  Assert.AreEqual(1, IndexIn(FPinned, cModuleA));
  Assert.IsFalse(TDpccUnloadSafety.IsSafe(cModuleA));
  Assert.IsFalse(TDpccUnloadSafety.IsSafe(cModuleB));
  Assert.IsTrue(TDpccUnloadSafety.IsSafe(cModuleC));
  TEvent(FRelease).SetEvent;
  Assert.IsTrue(TDpccOverdueThreads.Settle(cModuleA, cWaitMs));
end;

procedure TDpccOverdueThreadsTests.SettleWithoutRunningThreadPinsNothing;
var
  mThread: TThread;
begin
  mThread := WaitingThread(TEvent(FRelease));
  mThread.Start;
  TDpccOverdueThreads.Adopt(mThread, TArray<HMODULE>.Create(cModuleA, cModuleB));
  TEvent(FRelease).SetEvent;
  Assert.IsTrue(TDpccOverdueThreads.Settle(cModuleA, cWaitMs));
  Assert.AreEqual(0, Length(FPinned));
  Assert.IsTrue(TDpccUnloadSafety.IsSafe(cModuleA));
  Assert.IsTrue(TDpccUnloadSafety.IsSafe(cModuleB));
end;

procedure TDpccOverdueThreadsTests.ThreadListAdoptsWithAllPluginModules;
var
  mList: TDpccThreadList;
  mRelease: TEvent;
begin
  mRelease := TEvent(FRelease);
  // cModuleA spielt dpcc.IDE.Base: angemeldet wie von dpcc.IDE.Foundation.Module.
  TDpccPluginModules.Add(cModuleA);
  try
    mList := TDpccThreadList.Create;
    try
      mList.Start(
        procedure
        begin
          mRelease.WaitFor(cWaitMs);
        end);
      Assert.IsFalse(mList.StopAll(10));
    finally
      mList.Free;
    end;
    Assert.AreEqual(1, TDpccOverdueThreads.Pending(cModuleA), 'IDE.Base');
    Assert.AreEqual(1, TDpccOverdueThreads.Pending(HInstance), 'Core');
    Assert.IsFalse(TDpccOverdueThreads.Settle(cModuleA, 10));
    Assert.IsTrue(IndexIn(FPinned, cModuleA) >= 0, 'IDE.Base festgehalten');
    Assert.IsTrue(IndexIn(FPinned, HInstance) >= 0, 'Core festgehalten');
    mRelease.SetEvent;
    Assert.IsTrue(TDpccOverdueThreads.Settle(HInstance, cWaitMs));
  finally
    TDpccPluginModules.Remove(cModuleA);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccPluginModulesTests);
  TDUnitX.RegisterTestFixture(TDpccOverdueThreadsTests);

end.
