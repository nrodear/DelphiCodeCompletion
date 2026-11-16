unit dpcc.Core.Settings.MasterSwitch.Tests;

// Tests für den Hauptschalter ohne Neustart (dpcc.Core.Settings.MasterSwitch): Mit dem Stand beim Anmelden als
// Ausgang meldet jede Änderung der Einstellungen genau dann „an“ bzw. „aus“, wenn completion.enabled umspringt, auch
// beim schnellen Hin- und Herschalten; andere Änderungen melden nichts.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccMasterSwitchTests = class
  public
    /// <summary>Gestartet mit aus, dann an: „an“ (der Fall, der bisher erst nach einem Neustart wirkte).</summary>
    [Test]
    procedure StartedOffTurnsOn;
    [Test]
    procedure StartedOnTurnsOff;
    /// <summary>Andere Einstellung geändert, Hauptschalter gleich: nichts.</summary>
    [Test]
    procedure OtherChangeReportsNothing;
    [Test]
    procedure FastTogglingReportsEveryChange;
    /// <summary>Ohne Reset gilt der erste Stand als bekannt: kein „an“ beim ersten Lesen.</summary>
    [Test]
    procedure FirstUpdateWithoutResetReportsNothing;
    /// <summary>Reset (neues Anmelden) setzt den Ausgang neu.</summary>
    [Test]
    procedure ResetReplacesKnownState;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Settings.MasterSwitch;

function Change(var ASwitch: TDpccMasterSwitch; AEnabled: Boolean): Integer;
begin
  Result := Ord(ASwitch.Update(AEnabled));
end;

{ TDpccMasterSwitchTests }

procedure TDpccMasterSwitchTests.StartedOffTurnsOn;
var
  mSwitch: TDpccMasterSwitch;
begin
  mSwitch.Reset(False);
  Assert.AreEqual(Ord(TDpccMasterSwitchChange.TurnedOn), Change(mSwitch, True));
  Assert.IsTrue(mSwitch.Enabled);
end;

procedure TDpccMasterSwitchTests.StartedOnTurnsOff;
var
  mSwitch: TDpccMasterSwitch;
begin
  mSwitch.Reset(True);
  Assert.AreEqual(Ord(TDpccMasterSwitchChange.TurnedOff), Change(mSwitch, False));
  Assert.IsFalse(mSwitch.Enabled);
end;

procedure TDpccMasterSwitchTests.OtherChangeReportsNothing;
var
  mSwitch: TDpccMasterSwitch;
begin
  mSwitch.Reset(True);
  Assert.AreEqual(Ord(TDpccMasterSwitchChange.None), Change(mSwitch, True));
  mSwitch.Reset(False);
  Assert.AreEqual(Ord(TDpccMasterSwitchChange.None), Change(mSwitch, False));
end;

procedure TDpccMasterSwitchTests.FastTogglingReportsEveryChange;
var
  mSwitch: TDpccMasterSwitch;
  mIndex: Integer;
begin
  mSwitch.Reset(False);
  for mIndex := 1 to 50 do
  begin
    Assert.AreEqual(Ord(TDpccMasterSwitchChange.TurnedOn), Change(mSwitch, True), 'an, Runde ' + IntToStr(mIndex));
    Assert.AreEqual(Ord(TDpccMasterSwitchChange.TurnedOff), Change(mSwitch, False), 'aus, Runde ' + IntToStr(mIndex));
  end;
  Assert.AreEqual(Ord(TDpccMasterSwitchChange.None), Change(mSwitch, False));
end;

procedure TDpccMasterSwitchTests.FirstUpdateWithoutResetReportsNothing;
var
  mSwitch: TDpccMasterSwitch;
begin
  mSwitch := Default(TDpccMasterSwitch);
  Assert.AreEqual(Ord(TDpccMasterSwitchChange.None), Change(mSwitch, True));
  Assert.AreEqual(Ord(TDpccMasterSwitchChange.TurnedOff), Change(mSwitch, False));
end;

procedure TDpccMasterSwitchTests.ResetReplacesKnownState;
var
  mSwitch: TDpccMasterSwitch;
begin
  mSwitch.Reset(False);
  mSwitch.Reset(True);
  Assert.AreEqual(Ord(TDpccMasterSwitchChange.None), Change(mSwitch, True));
  Assert.AreEqual(Ord(TDpccMasterSwitchChange.TurnedOff), Change(mSwitch, False));
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccMasterSwitchTests);

end.
