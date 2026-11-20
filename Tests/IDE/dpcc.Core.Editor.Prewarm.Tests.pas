unit dpcc.Core.Editor.Prewarm.Tests;

// Vorladen beim Aktivieren (TDpccPrewarmGate) mit einstellbarer Uhr: erst nach der Ruhe, eine neue Aktivierung
// beginnt sie neu und ersetzt die Datei, eine Datei ohne dpcc verwirft die wartende; je Datei und Dokumentstand
// höchstens einmal, eine andere Sitzung beginnt von vorn.

interface

uses
  DUnitX.TestFramework,
  dpcc.Core.Editor.Prewarm;

type
  [TestFixture]
  TDpccPrewarmGateTests = class
  private
    FNow: UInt64;
    FGate: TDpccPrewarmGate;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Fällig erst nach der Ruhe, dann genau einmal.</summary>
    [Test]
    procedure DueAfterQuietPeriod;
    /// <summary>Durchblättern: Jede Aktivierung beginnt die Ruhe neu, es gilt die letzte Datei.</summary>
    [Test]
    procedure NewActivationRestartsQuiet;
    /// <summary>Andere Datei vorn (ohne dpcc): die wartende entfällt.</summary>
    [Test]
    procedure CancelDropsPending;
    /// <summary>Uhr läuft zurück: Die Ruhe beginnt von vorn statt sofort fällig zu sein.</summary>
    [Test]
    procedure ClockBackwardsWaitsAgain;
    /// <summary>Je Datei und Stand einmal, ohne Groß-/Kleinschreibung; ein neuer Stand gilt wieder.</summary>
    [Test]
    procedure ClaimOncePerVersion;
    /// <summary>Andere Sitzung, Forget und Reset: wieder vorladen.</summary>
    [Test]
    procedure NewSessionAndForgetStartOver;
  end;

implementation

const
  cA = 'C:\P\A.pas';
  cB = 'C:\P\B.pas';

procedure TDpccPrewarmGateTests.Setup;
begin
  FNow := 1000;
  FGate := TDpccPrewarmGate.Create(
    function: UInt64
    begin
      Result := FNow;
    end, 400);
end;

procedure TDpccPrewarmGateTests.TearDown;
begin
  FGate.Free;
  FGate := nil;
end;

procedure TDpccPrewarmGateTests.DueAfterQuietPeriod;
var
  mFile: string;
begin
  Assert.IsFalse(FGate.Pending);
  Assert.IsFalse(FGate.TakeDue(mFile), 'ohne Aktivierung');
  FGate.Activated(cA);
  Assert.IsTrue(FGate.Pending);
  Assert.AreEqual(400, Integer(FGate.WaitMs));
  Assert.IsFalse(FGate.TakeDue(mFile), 'sofort');
  FNow := 1399;
  Assert.AreEqual(1, Integer(FGate.WaitMs));
  Assert.IsFalse(FGate.TakeDue(mFile), 'kurz vor Ende der Ruhe');
  FNow := 1400;
  Assert.IsTrue(FGate.TakeDue(mFile), 'Ruhe vorbei');
  Assert.AreEqual(cA, mFile);
  Assert.IsFalse(FGate.Pending, 'nicht mehr wartend');
  Assert.IsFalse(FGate.TakeDue(mFile), 'nur einmal');
  Assert.AreEqual('', mFile);
end;

procedure TDpccPrewarmGateTests.NewActivationRestartsQuiet;
var
  mFile: string;
begin
  FGate.Activated(cA);
  FNow := 1300;
  FGate.Activated(cB);
  FNow := 1500;
  Assert.IsFalse(FGate.TakeDue(mFile), 'Ruhe ab der zweiten Aktivierung');
  Assert.AreEqual(200, Integer(FGate.WaitMs));
  FNow := 1700;
  Assert.IsTrue(FGate.TakeDue(mFile));
  Assert.AreEqual(cB, mFile, 'die letzte Datei');
  Assert.IsFalse(FGate.TakeDue(mFile), 'A kommt nicht mehr');
end;

procedure TDpccPrewarmGateTests.CancelDropsPending;
var
  mFile: string;
begin
  FGate.Activated(cA);
  FGate.Cancel;
  FNow := 2000;
  Assert.IsFalse(FGate.TakeDue(mFile), 'nach Cancel');
  FGate.Activated(cA);
  FGate.Activated('');
  FNow := 3000;
  Assert.IsFalse(FGate.Pending, 'Aktivierung ohne Datei verwirft');
  Assert.AreEqual(0, Integer(FGate.WaitMs));
end;

procedure TDpccPrewarmGateTests.ClockBackwardsWaitsAgain;
var
  mFile: string;
begin
  FGate.Activated(cA);
  FNow := 500;
  Assert.AreEqual(400, Integer(FGate.WaitMs), 'Ruhe von vorn');
  Assert.IsFalse(FGate.TakeDue(mFile));
  FNow := 900;
  Assert.IsTrue(FGate.TakeDue(mFile));
  Assert.AreEqual(cA, mFile);
end;

procedure TDpccPrewarmGateTests.ClaimOncePerVersion;
var
  mSession: Pointer;
begin
  mSession := Pointer(1);
  Assert.IsTrue(FGate.Claim(cA, 7, mSession), 'erster Stand');
  Assert.IsFalse(FGate.Claim(cA, 7, mSession), 'derselbe Stand');
  Assert.IsFalse(FGate.Claim('c:\p\a.PAS', 7, mSession), 'andere Schreibweise');
  Assert.IsTrue(FGate.Claim(cB, 7, mSession), 'andere Datei');
  Assert.IsTrue(FGate.Claim(cA, 8, mSession), 'neuer Stand');
  Assert.IsFalse(FGate.Claim(cA, 8, mSession));
end;

procedure TDpccPrewarmGateTests.NewSessionAndForgetStartOver;
begin
  Assert.IsTrue(FGate.Claim(cA, 7, Pointer(1)));
  Assert.IsTrue(FGate.Claim(cA, 7, Pointer(2)), 'neue Sitzung');
  Assert.IsFalse(FGate.Claim(cA, 7, Pointer(2)));
  FGate.Forget(cA);
  Assert.IsTrue(FGate.Claim(cA, 7, Pointer(2)), 'nach Forget');
  FGate.Activated(cB);
  FGate.Reset;
  Assert.IsFalse(FGate.Pending, 'Reset verwirft die wartende');
  Assert.IsTrue(FGate.Claim(cA, 7, Pointer(2)), 'nach Reset');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccPrewarmGateTests);

end.
