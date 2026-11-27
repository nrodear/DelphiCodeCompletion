unit dpcc.Core.Settings.OperatingMode.Tests;

// Tests für die Betriebsart je Delphi-Version (Stufe 2 von dpcc.LspServer.exe, dpcc.Core.Settings.OperatingMode und
// TDpccPluginSettings.Mode), ohne Registry: Kennungen, Registry-Name je Version, Überführung des früheren
// gemeinsamen Enabled (0 → Aus, 1 → Plugin, ohne Wert Plugin) für jede Version ohne eigenen Wert, getrennte
// Speicherung für Delphi 12 und 13, Enabled nur noch abgeleitet und nicht mehr geschrieben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccOperatingModeTests = class
  public
    /// <summary>Kennungen off/plugin/server hin und zurück, ohne Groß-/Kleinschreibung; Unbekanntes ist keine.
    /// </summary>
    [Test]
    procedure IdsRoundTrip;
    /// <summary>Registry-Name je Version: "OperatingMode 23.0", "OperatingMode 37.0"; ohne Version ohne Zusatz.
    /// </summary>
    [Test]
    procedure ValueNamePerVersion;
    /// <summary>Überführung: Enabled 0 → Aus, 1 (und jeder andere Wert) → Plugin, ohne Wert → Plugin (Vorgabe);
    /// ein eigener gültiger Wert gewinnt, ein ungültiger zählt wie keiner.</summary>
    [Test]
    procedure LegacyEnabledIsMigrated;
    /// <summary>Laden aus einem Speicher mit nur Enabled: beide Versionen bekommen denselben überführten Wert und
    /// ModeFromLegacy; mit eigenem Wert einer Version gilt der nur für sie.</summary>
    [Test]
    [TestCase('Enabled 0', '0,0')]
    [TestCase('Enabled 1', '1,1')]
    [TestCase('ohne Enabled', '-1,1')]
    procedure LoadMigratesPerVersion(ALegacy, AExpected: Integer);
    /// <summary>Delphi 12 und 13 getrennt: Speichern schreibt nur den Wert der eigenen Version, nie Enabled; die andere
    /// Version liest weiter ihren eigenen bzw. den überführten Wert.</summary>
    [Test]
    procedure SavedSeparatelyPerVersion;
    /// <summary>Enabled ist abgeleitet: nur Plugin; True wählt Plugin, False macht aus Plugin Aus, Server bleibt.
    /// </summary>
    [Test]
    procedure EnabledIsDerived;
    /// <summary>Vorgabe nach der Installation (leerer Speicher, beide Versionen): Plugin.</summary>
    [Test]
    procedure DefaultIsPlugin;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.OperatingMode;

function Loaded(const AStore: IDpccSettingsStore; const AVersion: string): TDpccPluginSettings;
begin
  Result := TDpccPluginSettings.Defaults;
  Result.IdeVersion := AVersion;
  Result.Load(AStore);
end;

{ TDpccOperatingModeTests }

procedure TDpccOperatingModeTests.IdsRoundTrip;
var
  mMode, mBack: TDpccOperatingMode;
begin
  Assert.AreEqual('off', TDpccOperatingModes.IdOf(TDpccOperatingMode.Off));
  Assert.AreEqual('plugin', TDpccOperatingModes.IdOf(TDpccOperatingMode.Plugin));
  Assert.AreEqual('server', TDpccOperatingModes.IdOf(TDpccOperatingMode.Server));
  for mMode := Low(TDpccOperatingMode) to High(TDpccOperatingMode) do
  begin
    Assert.IsTrue(TDpccOperatingModes.TryFromId(TDpccOperatingModes.IdOf(mMode), mBack), 'gelesen');
    Assert.AreEqual(Ord(mMode), Ord(mBack), TDpccOperatingModes.IdOf(mMode));
    Assert.IsTrue(TDpccOperatingModes.TryFromId(' ' + UpperCase(TDpccOperatingModes.IdOf(mMode)) + ' ', mBack),
      'groß und mit Leerraum');
    Assert.AreEqual(Ord(mMode), Ord(mBack), 'groß');
  end;
  Assert.IsFalse(TDpccOperatingModes.TryFromId('an', mBack), 'unbekannt');
  Assert.IsFalse(TDpccOperatingModes.TryFromId('', mBack), 'leer');
  Assert.IsFalse(TDpccOperatingModes.TryFromId('1', mBack), 'Zahl');
  Assert.AreEqual('Server', TDpccOperatingModes.LogName(TDpccOperatingMode.Server), 'Protokoll');
end;

procedure TDpccOperatingModeTests.ValueNamePerVersion;
begin
  Assert.AreEqual('OperatingMode 23.0', TDpccOperatingModes.ValueName('23.0'));
  Assert.AreEqual('OperatingMode 37.0', TDpccOperatingModes.ValueName('37.0'));
  Assert.AreEqual('OperatingMode', TDpccOperatingModes.ValueName(''));
  Assert.AreEqual('OperatingMode 37.0', TDpccOperatingModes.ValueName(' 37.0 '), 'Leerraum');
  Assert.AreNotEqual(TDpccOperatingModes.ValueName('23.0'), TDpccOperatingModes.ValueName('37.0'), 'getrennt');
end;

procedure TDpccOperatingModeTests.LegacyEnabledIsMigrated;
var
  mFromLegacy: Boolean;
begin
  Assert.AreEqual(Ord(TDpccOperatingMode.Off), Ord(TDpccOperatingModes.FromLegacy(True, 0)), '0');
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(TDpccOperatingModes.FromLegacy(True, 1)), '1');
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(TDpccOperatingModes.FromLegacy(True, 7)), '7');
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(TDpccOperatingModes.FromLegacy(False, 0)), 'ohne Wert');
  // Eigener Wert gewinnt über Enabled.
  Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(TDpccOperatingModes.Resolve(True, 'server', True, 0,
    mFromLegacy)), 'eigener Wert');
  Assert.IsFalse(mFromLegacy, 'nicht überführt');
  Assert.AreEqual(Ord(TDpccOperatingMode.Off), Ord(TDpccOperatingModes.Resolve(True, 'off', True, 1, mFromLegacy)),
    'eigener Wert Aus');
  // Ungültig oder fehlend: Überführung.
  Assert.AreEqual(Ord(TDpccOperatingMode.Off), Ord(TDpccOperatingModes.Resolve(True, 'bunt', True, 0,
    mFromLegacy)), 'ungültig');
  Assert.IsTrue(mFromLegacy, 'ungültig überführt');
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(TDpccOperatingModes.Resolve(False, '', False, 0,
    mFromLegacy)), 'nichts');
  Assert.IsTrue(mFromLegacy, 'nichts überführt');
end;

procedure TDpccOperatingModeTests.LoadMigratesPerVersion(ALegacy, AExpected: Integer);
var
  mStore: IDpccMemorySettingsStore;
  mSettings: TDpccPluginSettings;
  mVersion: string;
begin
  mStore := TDpccMemorySettingsStore.Create;
  if ALegacy >= 0 then
  begin
    mStore.WriteInteger('Enabled', ALegacy);
  end;
  for mVersion in ['23.0', '37.0'] do
  begin
    mSettings := Loaded(mStore, mVersion);
    if AExpected = 0 then
    begin
      Assert.AreEqual(Ord(TDpccOperatingMode.Off), Ord(mSettings.Mode), mVersion);
    end
    else
    begin
      Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(mSettings.Mode), mVersion);
    end;
    Assert.IsTrue(mSettings.ModeFromLegacy, mVersion + ': überführt');
    Assert.AreEqual(mVersion, mSettings.IdeVersion, 'Version bleibt nach Load');
  end;
  // Delphi 13 bekommt einen eigenen Wert: Er gilt nur dort, Delphi 12 überführt weiter.
  mStore.WriteString('OperatingMode 37.0', 'server');
  mSettings := Loaded(mStore, '37.0');
  Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(mSettings.Mode), '37.0 eigener Wert');
  Assert.IsFalse(mSettings.ModeFromLegacy, '37.0 nicht überführt');
  mSettings := Loaded(mStore, '23.0');
  Assert.IsTrue(mSettings.ModeFromLegacy, '23.0 weiter überführt');
  Assert.AreNotEqual(Ord(TDpccOperatingMode.Server), Ord(mSettings.Mode), '23.0 nicht Server');
end;

procedure TDpccOperatingModeTests.SavedSeparatelyPerVersion;
var
  mStore: IDpccMemorySettingsStore;
  mSettings: TDpccPluginSettings;
begin
  mStore := TDpccMemorySettingsStore.Create;
  mStore.WriteInteger('Enabled', 0);
  // Delphi 13 wählt Server und speichert.
  mSettings := Loaded(mStore, '37.0');
  mSettings.Mode := TDpccOperatingMode.Server;
  mSettings.Save(mStore);
  Assert.AreEqual('server', mStore.Text('OperatingMode 37.0'), '37.0 geschrieben');
  Assert.AreEqual('', mStore.Text('OperatingMode 23.0'), '23.0 nicht geschrieben');
  Assert.AreEqual('0', mStore.Text('Enabled'), 'Enabled unverändert');
  Assert.IsFalse(MatchText('OperatingMode', mStore.Names), 'kein Wert ohne Version');
  // Delphi 12 liest weiter den alten Wert (Aus) und speichert Plugin: nur unter 23.0.
  mSettings := Loaded(mStore, '23.0');
  Assert.AreEqual(Ord(TDpccOperatingMode.Off), Ord(mSettings.Mode), '23.0 überführt');
  mSettings.Mode := TDpccOperatingMode.Plugin;
  mSettings.Save(mStore);
  Assert.AreEqual('plugin', mStore.Text('OperatingMode 23.0'), '23.0 geschrieben');
  Assert.AreEqual('server', mStore.Text('OperatingMode 37.0'), '37.0 bleibt');
  Assert.AreEqual('0', mStore.Text('Enabled'), 'Enabled weiter unverändert');
  // Beide lesen ihren eigenen Wert zurück.
  Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(Loaded(mStore, '37.0').Mode), '37.0 gelesen');
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(Loaded(mStore, '23.0').Mode), '23.0 gelesen');
  // Enabled steht nur noch unter den nur gelesenen Namen.
  Assert.IsTrue(MatchText('Enabled', TDpccPluginSettings.ReadOnlyNames), 'nur gelesen');
  Assert.IsFalse(MatchText('Enabled', TDpccPluginSettings.StoredNames), 'nicht gespeichert');
end;

procedure TDpccOperatingModeTests.EnabledIsDerived;
var
  mSettings: TDpccPluginSettings;
begin
  mSettings := TDpccPluginSettings.Defaults;
  Assert.IsTrue(mSettings.Enabled, 'Plugin');
  mSettings.Mode := TDpccOperatingMode.Server;
  Assert.IsFalse(mSettings.Enabled, 'Server: eingebauter Server aus');
  mSettings.Enabled := False;
  Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(mSettings.Mode), 'Server bleibt');
  mSettings.Mode := TDpccOperatingMode.Off;
  Assert.IsFalse(mSettings.Enabled, 'Aus');
  mSettings.Enabled := True;
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(mSettings.Mode), 'True wählt Plugin');
  mSettings.Enabled := False;
  Assert.AreEqual(Ord(TDpccOperatingMode.Off), Ord(mSettings.Mode), 'False aus Plugin: Aus');
end;

procedure TDpccOperatingModeTests.DefaultIsPlugin;
var
  mStore: IDpccMemorySettingsStore;
begin
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(TDpccOperatingModes.cDefault), 'Vorgabe');
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(TDpccPluginSettings.Defaults.Mode), 'Defaults');
  mStore := TDpccMemorySettingsStore.Create;
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(Loaded(mStore, '23.0').Mode), 'Delphi 12');
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(Loaded(mStore, '37.0').Mode), 'Delphi 13');
  // Erster Start: ohne jeden Wert ist es die Vorgabe (die IDE-Schicht stellt dann auf Plugin); mit dem früheren
  // Enabled oder einem eigenen Wert nicht.
  Assert.IsTrue(Loaded(mStore, '37.0').ModeFromDefault, 'leer: Vorgabe');
  mStore.WriteInteger('Enabled', 1);
  Assert.IsFalse(Loaded(mStore, '37.0').ModeFromDefault, 'mit Enabled');
  mStore := TDpccMemorySettingsStore.Create;
  mStore.WriteString('OperatingMode 37.0', 'off');
  Assert.IsFalse(Loaded(mStore, '37.0').ModeFromDefault, 'mit eigenem Wert');
  Assert.IsTrue(Loaded(mStore, '23.0').ModeFromDefault, 'andere Version weiter leer');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccOperatingModeTests);

end.
