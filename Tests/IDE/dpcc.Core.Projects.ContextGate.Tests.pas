unit dpcc.Core.Projects.ContextGate.Tests;

// Tests für die Entscheidung „Projektkontext voll lesen ja/nein“ (dpcc.Core.Projects.ContextGate, V2) mit
// einstellbarer Uhr: erstes Lesen, gleicher und geänderter Fingerabdruck, Ereignis (auch während des Lesens),
// Sicherheitstakt, zurücklaufende Uhr und der Fingerabdruck je Projekt.

interface

uses
  DUnitX.TestFramework,
  dpcc.Core.Projects.ContextGate;

type
  [TestFixture]
  TDpccProjectContextGateTests = class
  private
    FNow: UInt64;
    function NewGate: TDpccProjectContextGate;
  public
    [Setup]
    procedure Setup;
    /// <summary>Erster Aufruf (Start) liest immer voll, auch mit leerem Fingerabdruck.</summary>
    [Test]
    procedure FirstCallReadsFully;
    /// <summary>Gleicher Fingerabdruck vor Ablauf des Sicherheitstakts: kein volles Lesen.</summary>
    [Test]
    procedure SameFingerprintSkips;
    /// <summary>Geänderter Fingerabdruck: sofort, auch direkt nach dem letzten Lesen.</summary>
    [Test]
    procedure ChangedFingerprintReadsAtOnce;
    /// <summary>Ereignis: sofort; nach dem Lesen nicht mehr.</summary>
    [Test]
    procedure EventReadsAtOnce;
    /// <summary>Ein Ereignis während des Lesens geht nicht verloren.</summary>
    [Test]
    procedure EventDuringReadIsKept;
    /// <summary>Sicherheitstakt: knapp davor nicht, ab Ablauf ja; danach zählt er neu.</summary>
    [Test]
    procedure SafetyTickReadsAgain;
    /// <summary>Läuft die Uhr zurück, liest der Takt nicht ständig.</summary>
    [Test]
    procedure ClockBackwardsDoesNotRead;
    /// <summary>Konfiguration, Plattform, aktives Projekt und Datei ändern den Teil des Fingerabdrucks.</summary>
    [Test]
    procedure ProjectPartDiffers;
    /// <summary>Anlass als Text: leer nur für None.</summary>
    [Test]
    procedure ReasonTexts;
  end;

implementation

uses
  System.SysUtils;

const
  cT0 = 5000000;
  cSafety = 15000;

procedure ExpectReason(AExpected, AActual: TDpccContextReadReason; const AMessage: string = '');
begin
  Assert.AreEqual(Ord(AExpected), Ord(AActual), AMessage);
end;

procedure TDpccProjectContextGateTests.Setup;
begin
  FNow := cT0;
end;

function TDpccProjectContextGateTests.NewGate: TDpccProjectContextGate;
begin
  Result := TDpccProjectContextGate.Create(
    function: UInt64
    begin
      Result := FNow;
    end, cSafety);
end;

procedure TDpccProjectContextGateTests.FirstCallReadsFully;
var
  mGate: TDpccProjectContextGate;
begin
  mGate := NewGate;
  try
    ExpectReason(TDpccContextReadReason.First, mGate.Due(''));
    ExpectReason(TDpccContextReadReason.First, mGate.Due('A'), 'Due allein ändert nichts');
    mGate.Done('A', mGate.Signals);
    ExpectReason(TDpccContextReadReason.None, mGate.Due('A'));
  finally
    mGate.Free;
  end;
end;

procedure TDpccProjectContextGateTests.SameFingerprintSkips;
var
  mGate: TDpccProjectContextGate;
begin
  mGate := NewGate;
  try
    mGate.Done('A', mGate.Signals);
    FNow := cT0 + 1000;
    ExpectReason(TDpccContextReadReason.None, mGate.Due('A'));
    FNow := cT0 + cSafety - 1;
    ExpectReason(TDpccContextReadReason.None, mGate.Due('A'));
  finally
    mGate.Free;
  end;
end;

procedure TDpccProjectContextGateTests.ChangedFingerprintReadsAtOnce;
var
  mGate: TDpccProjectContextGate;
begin
  mGate := NewGate;
  try
    mGate.Done('A', mGate.Signals);
    ExpectReason(TDpccContextReadReason.Changed, mGate.Due('B'));
    ExpectReason(TDpccContextReadReason.Changed, mGate.Due(''), 'Gruppe geschlossen');
    mGate.Done('B', mGate.Signals);
    ExpectReason(TDpccContextReadReason.None, mGate.Due('B'));
    ExpectReason(TDpccContextReadReason.Changed, mGate.Due('A'), 'zurück zum alten Stand');
  finally
    mGate.Free;
  end;
end;

procedure TDpccProjectContextGateTests.EventReadsAtOnce;
var
  mGate: TDpccProjectContextGate;
begin
  mGate := NewGate;
  try
    mGate.Done('A', mGate.Signals);
    mGate.Signal;
    ExpectReason(TDpccContextReadReason.Event, mGate.Due('A'));
    // Geänderter Fingerabdruck geht vor (gleiche Wirkung, genauerer Anlass).
    ExpectReason(TDpccContextReadReason.Changed, mGate.Due('B'));
    mGate.Done('A', mGate.Signals);
    ExpectReason(TDpccContextReadReason.None, mGate.Due('A'));
  finally
    mGate.Free;
  end;
end;

procedure TDpccProjectContextGateTests.EventDuringReadIsKept;
var
  mGate: TDpccProjectContextGate;
  mSignals: Integer;
begin
  mGate := NewGate;
  try
    mSignals := mGate.Signals;
    // Das Ereignis kommt, während gelesen wird.
    mGate.Signal;
    mGate.Done('A', mSignals);
    ExpectReason(TDpccContextReadReason.Event, mGate.Due('A'));
  finally
    mGate.Free;
  end;
end;

procedure TDpccProjectContextGateTests.SafetyTickReadsAgain;
var
  mGate: TDpccProjectContextGate;
begin
  mGate := NewGate;
  try
    mGate.Done('A', mGate.Signals);
    FNow := cT0 + cSafety - 1;
    ExpectReason(TDpccContextReadReason.None, mGate.Due('A'));
    FNow := cT0 + cSafety;
    ExpectReason(TDpccContextReadReason.Safety, mGate.Due('A'));
    mGate.Done('A', mGate.Signals);
    FNow := cT0 + cSafety + cSafety - 1;
    ExpectReason(TDpccContextReadReason.None, mGate.Due('A'), 'Takt zählt ab dem letzten Lesen');
    FNow := cT0 + 2 * cSafety;
    ExpectReason(TDpccContextReadReason.Safety, mGate.Due('A'));
  finally
    mGate.Free;
  end;
end;

procedure TDpccProjectContextGateTests.ClockBackwardsDoesNotRead;
var
  mGate: TDpccProjectContextGate;
begin
  mGate := NewGate;
  try
    mGate.Done('A', mGate.Signals);
    FNow := cT0 - 1000;
    ExpectReason(TDpccContextReadReason.None, mGate.Due('A'));
  finally
    mGate.Free;
  end;
end;

procedure TDpccProjectContextGateTests.ProjectPartDiffers;
var
  mBase: string;
begin
  mBase := TDpccProjectContextGate.ProjectPart('C:\P\A.dproj', 'Debug', 'Win32', True);
  Assert.AreEqual(mBase, TDpccProjectContextGate.ProjectPart('C:\P\A.dproj', 'Debug', 'Win32', True));
  Assert.IsFalse(mBase = TDpccProjectContextGate.ProjectPart('C:\P\A.dproj', 'Release', 'Win32', True));
  Assert.IsFalse(mBase = TDpccProjectContextGate.ProjectPart('C:\P\A.dproj', 'Debug', 'Win64', True));
  Assert.IsFalse(mBase = TDpccProjectContextGate.ProjectPart('C:\P\A.dproj', 'Debug', 'Win32', False));
  Assert.IsFalse(mBase = TDpccProjectContextGate.ProjectPart('C:\P\B.dproj', 'Debug', 'Win32', True));
  // Die Grenzen zwischen den Feldern bleiben erhalten.
  Assert.IsFalse(TDpccProjectContextGate.ProjectPart('A', 'BC', 'D', False) =
    TDpccProjectContextGate.ProjectPart('AB', 'C', 'D', False));
end;

procedure TDpccProjectContextGateTests.ReasonTexts;
begin
  Assert.AreEqual('', TDpccProjectContextGate.ReasonText(TDpccContextReadReason.None));
  Assert.IsTrue(TDpccProjectContextGate.ReasonText(TDpccContextReadReason.First) <> '');
  Assert.IsTrue(TDpccProjectContextGate.ReasonText(TDpccContextReadReason.Changed) <> '');
  Assert.IsTrue(TDpccProjectContextGate.ReasonText(TDpccContextReadReason.Event) <> '');
  Assert.IsTrue(TDpccProjectContextGate.ReasonText(TDpccContextReadReason.Safety) <> '');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccProjectContextGateTests);

end.
