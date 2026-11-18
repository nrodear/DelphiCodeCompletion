unit dpcc.Core.Settings.CompletionView.Tests;

// Tests für die Seite „dpcc“ und die Plugin-Einstellungen dahinter (dpcc.Core.Settings.CompletionView,
// dpcc.Core.Settings.Plugin, dpcc.Core.Settings.Scopes).
// Seit OPT1 gibt es eine einzige Seite mit genau zwölf Optionen unter dem Hauptschalter und zwei Knöpfen (cPageItems);
// die übrigen Optionen der früheren Unterseiten sind fest verdrahtet (TDpccFixedSettings).
// Seit OPT2 kennt das Plugin nur noch diese Einstellungen: OK schreibt genau die Werte der Seite (zwölf in die
// Registry, index.extraSourceFolders nach settings.json), hints.xmlDocMaxLines und LogNames werden nur gelesen. Alte
// Registry-Werte (feste Optionen, Modul-Schalter, Tasten, entfernte Reiter) und alte Schlüssel in settings.json
// bleiben liegen, wirken nicht und lösen keine Meldung aus; „Werte beim Debuggen“ hängt an keinem Modul-Schalter.
// Katalog, Suche, Gruppen und Schnellschalter, die die früheren Tests hier prüften, gibt es seit OPT2 nicht mehr.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccCompletionViewTests = class
  public
    /// <summary>OPT1: Die Seite zeigt genau den Hauptschalter und zwölf Optionen in vier Abschnitten, dazu zwei
    /// Knöpfe; gespeichert werden genau diese Optionen (OPT2).</summary>
    [Test]
    procedure PageShowsExactlyTwelveOptions;
    /// <summary>OPT2: OK schreibt nur die Werte der Seite: zwölf in die Registry, index.extraSourceFolders nach
    /// settings.json; keine weiteren Namen und keine weiteren Schlüssel der Datei.</summary>
    [Test]
    procedure SaveWritesOnlyPageValues;
    /// <summary>OPT2: Alte Registry-Werte (feste Optionen, Modul-Schalter, Tasten, entfernte Reiter, Einstellungsverlauf)
    /// werden weder gelesen noch überschrieben noch entfernt.</summary>
    [Test]
    procedure OldRegistryValuesAreIgnored;
    /// <summary>OPT2: „Werte beim Debuggen“ hängt nur an debug.hoverValues, nicht am früheren Modul-Schalter
    /// debug.enabled.</summary>
    [Test]
    procedure DebugValuesIgnoreModuleSwitch;
    /// <summary>OPT2: hints.xmlDocMaxLines (settings.json, sonst ein alter Registry-Wert) und LogNames (Registry) werden
    /// gelesen, aber nie geschrieben.</summary>
    [Test]
    procedure ReadOnlyValuesAreReadNotWritten;
    /// <summary>OPT1: Die festen Werte sind die bisherigen Vorgaben (z. B. 150 ms, Schreibweise an), stehen nicht auf
    /// der Seite und werden nicht gespeichert.</summary>
    [Test]
    procedure FixedSettingsKeepFormerDefaults;
    /// <summary>OPT1: hints.xmlDocExpand (und davor hints.xmlDocFull) wird weder gespeichert noch umgeleitet; alte
    /// Werte in Registry und settings.json lösen keine Meldung aus und ändern nichts.</summary>
    [Test]
    procedure XmlDocExpandIsIgnoredSilently;
    /// <summary>OPT2: Die früher nach settings.json umgeleiteten Schlüssel (Schnellbefehle, Metriken, Architektur,
    /// Tracker, Versionsverwaltung …) schreibt das Plugin nicht mehr; vorhandene Werte bleiben unverändert stehen, und
    /// der Server meldet sie nicht.</summary>
    [Test]
    procedure FormerRoutedKeysStayWithoutWarnings;
    /// <summary>S4: Umfang, Verwendungen und Speichergrenze des Index sind weder gespeichert noch umgeleitet; der
    /// Server nimmt feste Werte, auch wenn settings.json andere enthält.</summary>
    [Test]
    procedure IndexPageAndServerSwitchesAreGone;
    /// <summary>S1 bis S9 und OPT2: Einstellungen entfernter Seiten und Funktionen sind weder gespeichert noch
    /// umgeleitet.</summary>
    [Test]
    procedure FormerSettingsAreNeitherStoredNorRouted;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.Scopes,
  dpcc.Core.Settings.JsonText,
  dpcc.Core.Settings.CompletionView,
  dpcc.Core.Completion.Ranking,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Configuration.Parser;

/// <summary>Die Registry-Namen der Seite ohne index.extraSourceFolders (liegt in settings.json).</summary>
function RegistryPageNames: TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in TDpccCompletionView.SettingNames do
  begin
    if not SameText(mName, 'IndexExtraSourceFolders') then
    begin
      Result := Result + [mName];
    end;
  end;
end;

/// <summary>Wert unter APath in AText als JSON-Text; '' ohne.</summary>
function JsonAt(const AText, APath: string): string;
var
  mRoot: TJSONObject;
begin
  Result := '';
  mRoot := TDpccJsonText.Parse(AText);
  try
    if mRoot <> nil then
    begin
      Result := TDpccJsonText.ValueAt(mRoot, APath);
    end;
  finally
    mRoot.Free;
  end;
end;

function IssuesText(const AIssues: TArray<TConfigurationIssue>): string;
var
  mIssue: TConfigurationIssue;
begin
  Result := '';
  for mIssue in AIssues do
  begin
    Result := Result + mIssue.Message + '; ';
  end;
end;

{ TDpccCompletionViewTests }

procedure TDpccCompletionViewTests.PageShowsExactlyTwelveOptions;
const
  // Erwarteter Aufbau der Seite (Auftrag OPT1): Abschnitt und Element; Knöpfe mit ihrer Kennung.
  cSections: array[0..14] of TDpccPageSection = (psMaster, psCompletion, psCompletion, psCompletion, psCompletion,
    psCompletion, psCompletion, psCommit, psCommit, psCommit, psHints, psHints, psHints, psIndex, psIndex);
  cNames: array[0..14] of string = ('Enabled', 'AutoMinChars', 'CompletionListMode', 'VisibleRows', 'ListWidth',
    'Learning', 'ResetHistory', 'AutoParentheses', 'CommitCharacters', 'AutoUses', 'ParameterHints', 'HoverTooltip',
    'DebugHoverValues', 'IndexExtraSourceFolders', 'RebuildIndex');
var
  mIndex, mOptions, mButtons: Integer;
  mName: string;
  mStored: TArray<string>;
begin
  Assert.AreEqual(Integer(Length(cNames)), Integer(Length(cPageItems)), 'Elemente');
  mOptions := 0;
  mButtons := 0;
  for mIndex := 0 to High(cPageItems) do
  begin
    Assert.AreEqual(cNames[mIndex], cPageItems[mIndex].Name, 'Element ' + IntToStr(mIndex));
    Assert.AreEqual(Ord(cSections[mIndex]), Ord(cPageItems[mIndex].Section), cNames[mIndex] + ': Abschnitt');
    if cPageItems[mIndex].Kind = pkButton then
    begin
      Inc(mButtons);
    end
    else if cPageItems[mIndex].Section <> psMaster then
    begin
      Inc(mOptions);
    end;
  end;
  Assert.AreEqual(12, mOptions, 'Optionen unter dem Hauptschalter');
  Assert.AreEqual(2, mButtons, 'Knöpfe');
  Assert.AreEqual(cPageResetHistory, cPageItems[6].Name);
  Assert.AreEqual(cPageRebuildIndex, cPageItems[14].Name);
  Assert.AreEqual(13, Integer(Length(TDpccCompletionView.SettingNames)), 'Einstellungen samt Hauptschalter');
  // Gespeichert werden genau die Einstellungen der Seite, jede einmal.
  mStored := TDpccPluginSettings.StoredNames;
  Assert.AreEqual(13, Integer(Length(mStored)), 'gespeicherte Namen: ' + string.Join(', ', mStored));
  for mName in TDpccCompletionView.SettingNames do
  begin
    Assert.IsTrue(MatchText(mName, mStored), mName + ' gespeichert');
  end;
  for mName in mStored do
  begin
    Assert.IsTrue(MatchText(mName, TDpccCompletionView.SettingNames), mName + ' auf der Seite');
  end;
  // Die nur gelesenen stehen nicht auf der Seite.
  for mName in TDpccPluginSettings.ReadOnlyNames do
  begin
    Assert.IsFalse(MatchText(mName, TDpccCompletionView.SettingNames), mName + ' auf der Seite');
    Assert.IsFalse(MatchText(mName, mStored), mName + ' gespeichert');
  end;
end;

procedure TDpccCompletionViewTests.SaveWritesOnlyPageValues;
const
  // Eine settings.json mit Server-Schlüsseln, die das Plugin nicht kennt (Kommentar und Reihenfolge bleiben).
  cBefore = '{' + #13#10 + '  // eigene Notiz' + #13#10 + '  "language": "de",' + #13#10 +
    '  "completion": {"keywords": true}' + #13#10 + '}';
var
  mRegistry: IDpccMemorySettingsStore;
  mRouted: TDpccRoutedSettingsStore;
  mStore: IDpccSettingsStore;
  mSettings: TDpccPluginSettings;
  mName: string;
  mRoot: TJSONObject;
begin
  mSettings := TDpccPluginSettings.Defaults;
  mSettings.VisibleRows := 12;
  mSettings.IndexExtraSourceFolders := 'C:\A;C:\B';
  mRegistry := TDpccMemorySettingsStore.Create;
  mRouted := TDpccRoutedSettingsStore.Create(mRegistry, cBefore);
  mStore := mRouted;
  mSettings.Save(mStore);
  // Registry: genau die zwölf Werte der Seite (Hauptschalter und elf Optionen; die Quellordner liegen in der Datei).
  Assert.AreEqual(12, Integer(Length(mRegistry.Names)), 'Registry: ' + string.Join(', ', mRegistry.Names));
  for mName in RegistryPageNames do
  begin
    Assert.IsTrue(MatchText(mName, mRegistry.Names), mName + ' in der Registry');
  end;
  Assert.IsFalse(MatchText('IndexExtraSourceFolders', mRegistry.Names), 'Quellordner in der Registry');
  Assert.AreEqual('12', mRegistry.Text('VisibleRows'), 'VisibleRows');
  // settings.json: nur index.extraSourceFolders dazu; das Übrige bleibt, wie es war.
  Assert.AreEqual('"C:\\A;C:\\B"', JsonAt(mRouted.Text, 'index.extraSourceFolders'), 'Quellordner');
  Assert.IsTrue(ContainsText(mRouted.Text, '// eigene Notiz'), 'Kommentar bleibt');
  Assert.AreEqual('"de"', JsonAt(mRouted.Text, 'language'), 'language bleibt');
  Assert.AreEqual('true', JsonAt(mRouted.Text, 'completion.keywords'), 'completion.keywords bleibt');
  mRoot := TDpccJsonText.Parse(mRouted.Text);
  try
    Assert.IsTrue(mRoot <> nil, 'gültiges JSON');
    Assert.AreEqual(3, mRoot.Count, 'Schlüssel der Wurzel: ' + mRouted.Text);
    for mName in ['hints', 'experimental', 'metrics', 'slashCommands', 'codeLens', 'compiler', 'architecture',
      'query', 'ruleChecks', 'hotspots', 'references', 'navigation', 'tests', 'issues', 'vcs'] do
    begin
      Assert.IsTrue(mRoot.GetValue(mName) = nil, mName + ' geschrieben');
    end;
  finally
    mRoot.Free;
  end;
end;

procedure TDpccCompletionViewTests.OldRegistryValuesAreIgnored;
const
  // Frühere Registry-Namen mit Werten abweichend von der Vorgabe: feste Optionen (OPT1), Modul-Schalter, Tasten,
  // experimentelle Schalter, Einstellungsverlauf, umbenannte Tracker-Namen, entfernte Reiter.
  cOldIntegers: array[0..15] of string = ('OpenDelayMs', 'Favorites', 'GroupInherited', 'CompletionVariantBranch',
    'Preview', 'FixCase', 'FormatPlaceholders', 'DebugEnabled', 'ExperimentalEnabled', 'CompletionKey',
    'SignatureKeyPriority', 'QuickToggleKey', 'SafeKeepSettingsHistory', 'RecursionMarkers', 'Problems',
    'BookmarksNamed');
  cOldStrings: array[0..3] of string = ('CompletionListScope', 'WelcomePageIssuesTracker', 'IssuesQuery',
    'InlineDiagnostics');
var
  mStore, mSaved: IDpccMemorySettingsStore;
  mSettings: TDpccPluginSettings;
  mName: string;
begin
  mStore := TDpccMemorySettingsStore.Create;
  for mName in cOldIntegers do
  begin
    mStore.WriteInteger(mName, 7);
  end;
  for mName in cOldStrings do
  begin
    mStore.WriteString(mName, 'alt');
  end;
  // Dazu Werte der Seite: Die gelten.
  mStore.WriteInteger('VisibleRows', 14);
  mStore.WriteInteger('AutoMinChars', 3);
  mStore.WriteInteger('Learning', 0);
  mSettings.Load(mStore);
  Assert.AreEqual(14, mSettings.VisibleRows, 'VisibleRows');
  Assert.AreEqual(3, mSettings.AutoMinChars, 'AutoMinChars');
  Assert.IsFalse(mSettings.Learning, 'Learning');
  Assert.IsTrue(mSettings.Enabled and mSettings.HoverTooltip and mSettings.DebugHoverValues, 'übrige Vorgaben');
  // Gespeichert in denselben Speicher: Die alten Werte bleiben, wie sie waren; geschrieben wird nur die Seite.
  mSettings.Save(mStore);
  for mName in cOldIntegers do
  begin
    Assert.AreEqual('7', mStore.Text(mName), mName + ' bleibt liegen');
  end;
  for mName in cOldStrings do
  begin
    Assert.AreEqual('alt', mStore.Text(mName), mName + ' bleibt liegen');
  end;
  Assert.AreEqual(Integer(Length(cOldIntegers) + Length(cOldStrings) + 13), Integer(Length(mStore.Names)),
    'nur die Seite dazu');
  // In einen leeren Speicher: keiner der alten Namen.
  mSaved := TDpccMemorySettingsStore.FromSettings(mSettings);
  for mName in cOldIntegers do
  begin
    Assert.IsFalse(MatchText(mName, mSaved.Names), mName + ' gespeichert');
  end;
  for mName in cOldStrings do
  begin
    Assert.IsFalse(MatchText(mName, mSaved.Names), mName + ' gespeichert');
  end;
end;

procedure TDpccCompletionViewTests.DebugValuesIgnoreModuleSwitch;
var
  mStore: IDpccMemorySettingsStore;
  mSettings: TDpccPluginSettings;
begin
  // Früher schaltete der versteckte Modul-Schalter debug.enabled (DebugEnabled = 0) die Werte beim Debuggen mit ab.
  mStore := TDpccMemorySettingsStore.Create;
  mStore.WriteInteger('DebugEnabled', 0);
  mStore.WriteInteger('DebugHoverValues', 1);
  mSettings.Load(mStore);
  Assert.IsTrue(mSettings.DebugHoverValues, 'an trotz DebugEnabled = 0');
  // Und umgekehrt: Die eigene Option schaltet ab, gleich was der frühere Schalter sagt.
  mStore.WriteInteger('DebugEnabled', 1);
  mStore.WriteInteger('DebugHoverValues', 0);
  mSettings.Load(mStore);
  Assert.IsFalse(mSettings.DebugHoverValues, 'aus mit eigener Option');
  Assert.IsTrue(mSettings.HoverTooltip, 'Tooltip unberührt');
  Assert.IsFalse(MatchText('DebugEnabled', TDpccPluginSettings.StoredNames), 'Modul-Schalter gespeichert');
end;

procedure TDpccCompletionViewTests.ReadOnlyValuesAreReadNotWritten;
var
  mRegistry, mSaved: IDpccMemorySettingsStore;
  mRouted: TDpccRoutedSettingsStore;
  mStore: IDpccSettingsStore;
  mSettings: TDpccPluginSettings;
  mSetting: TDpccRoutedSetting;
  mText: string;
begin
  Assert.IsTrue(TDpccSettingsScopes.TryRouted('XmlDocMaxLines', mSetting), 'XmlDocMaxLines umgeleitet');
  Assert.IsTrue(mSetting.ReadOnly, 'nur gelesen');
  Assert.IsFalse(TDpccSettingsScopes.TryRouted('LogNames', mSetting), 'LogNames umgeleitet');
  // Aus settings.json gelesen.
  mText := '{"hints": {"xmlDocMaxLines": 7}}';
  mRegistry := TDpccMemorySettingsStore.Create;
  mRegistry.WriteInteger('LogNames', 1);
  mRegistry.WriteInteger('XmlDocMaxLines', 3);
  mRouted := TDpccRoutedSettingsStore.Create(mRegistry, mText);
  mStore := mRouted;
  mSettings.Load(mStore);
  Assert.AreEqual(7, mSettings.XmlDocMaxLines, 'aus settings.json');
  Assert.IsTrue(mSettings.LogNames, 'LogNames aus der Registry');
  // Gespeichert: weder in die Datei noch in die Registry, auch nicht geändert.
  mSettings.XmlDocMaxLines := 9;
  mSettings.LogNames := False;
  mSettings.Save(mStore);
  Assert.AreEqual('7', JsonAt(mRouted.Text, 'hints.xmlDocMaxLines'), 'Datei unverändert');
  Assert.AreEqual('1', mRegistry.Text('LogNames'), 'LogNames unverändert');
  Assert.AreEqual('3', mRegistry.Text('XmlDocMaxLines'), 'alter Registry-Wert unverändert');
  mStore.WriteInteger('XmlDocMaxLines', 5);
  Assert.AreEqual('7', JsonAt(mRouted.Text, 'hints.xmlDocMaxLines'), 'auch direkt nicht geschrieben');
  Assert.AreEqual('3', mRegistry.Text('XmlDocMaxLines'), 'auch nicht in die Registry');
  // Ohne Wert in settings.json gilt ein alter Registry-Wert, ohne beides die Vorgabe 0.
  mRouted := TDpccRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mSettings.Load(mStore);
  Assert.AreEqual(3, mSettings.XmlDocMaxLines, 'alter Registry-Wert');
  mSaved := TDpccMemorySettingsStore.Create;
  mSettings.Load(mSaved);
  Assert.AreEqual(0, mSettings.XmlDocMaxLines, 'Vorgabe');
  Assert.IsFalse(mSettings.LogNames, 'Vorgabe LogNames');
  // In einen leeren Speicher: keiner der beiden Namen.
  mSaved := TDpccMemorySettingsStore.FromSettings(mSettings);
  Assert.IsFalse(MatchText('XmlDocMaxLines', mSaved.Names), 'XmlDocMaxLines gespeichert');
  Assert.IsFalse(MatchText('LogNames', mSaved.Names), 'LogNames gespeichert');
end;

procedure TDpccCompletionViewTests.FixedSettingsKeepFormerDefaults;
const
  cFixedNames: array[0..7] of string = ('OpenDelayMs', 'Favorites', 'GroupInherited', 'CompletionVariantBranch',
    'CompletionListScope', 'Preview', 'FixCase', 'FormatPlaceholders');
var
  mName: string;
  mMode: TDpccListMode;
begin
  // Die festen Werte sind die bisherigen Vorgaben.
  Assert.AreEqual(150, Integer(TDpccFixedSettings.cOpenDelayMs), 'OpenDelayMs');
  Assert.IsTrue(TDpccFixedSettings.cFavorites, 'Favorites an');
  Assert.IsTrue(TDpccFixedSettings.cGroupInherited, 'GroupInherited an');
  Assert.IsTrue(TDpccFixedSettings.cCompletionVariantBranch, 'CompletionVariantBranch an');
  Assert.AreEqual('members', TDpccFixedSettings.cCompletionListScope, 'CompletionListScope');
  Assert.AreEqual(TDpccListModes.cScopeNames[Low(TDpccListScope)], TDpccFixedSettings.cCompletionListScope,
    'Scope = erster Wert der Liste');
  Assert.IsTrue(TDpccFixedSettings.cFixCase, 'FixCase an');
  Assert.IsTrue(TDpccFixedSettings.cFormatPlaceholders, 'FormatPlaceholders an');
  // Die Namen des Listenmodus gleichen denen der Vervollständigung.
  for mMode := Low(TDpccListMode) to High(TDpccListMode) do
  begin
    Assert.AreEqual(TDpccListModes.cModeNames[mMode], cCompletionListModeNames[Ord(mMode)], 'Listenmodus');
  end;
  // Keine feste Einstellung steht auf der Seite oder wird gespeichert.
  for mName in cFixedNames do
  begin
    Assert.IsFalse(MatchText(mName, TDpccCompletionView.SettingNames), mName + ' auf der Seite');
    Assert.IsFalse(MatchText(mName, TDpccPluginSettings.StoredNames), mName + ' gespeichert');
  end;
end;

procedure TDpccCompletionViewTests.XmlDocExpandIsIgnoredSilently;
var
  mStore, mSaved: IDpccMemorySettingsStore;
  mSettings: TDpccPluginSettings;
  mRouted: TDpccRoutedSetting;
  mServer: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Plugin: ein alter Registry-Wert wird weder gelesen noch zurückgeschrieben; die übrigen Werte gelten.
  mStore := TDpccMemorySettingsStore.FromSettings(TDpccPluginSettings.Defaults);
  mStore.WriteString('XmlDocExpand', 'expanded');
  mStore.WriteInteger('XmlDocFull', 1);
  mStore.WriteInteger('XmlDocMaxLines', 7);
  mSettings := TDpccPluginSettings.Defaults;
  mSettings.Load(mStore);
  Assert.AreEqual(7, mSettings.XmlDocMaxLines, 'XmlDocMaxLines gelesen');
  mSaved := TDpccMemorySettingsStore.FromSettings(mSettings);
  Assert.IsFalse(MatchText('XmlDocExpand', mSaved.Names), 'XmlDocExpand gespeichert');
  Assert.IsFalse(MatchText('XmlDocFull', mSaved.Names), 'XmlDocFull gespeichert');
  Assert.IsFalse(TDpccSettingsScopes.TryRouted('XmlDocExpand', mRouted), 'XmlDocExpand umgeleitet');
  Assert.IsFalse(TDpccSettingsScopes.TryRouted('XmlDocFull', mRouted), 'XmlDocFull umgeleitet');
  Assert.IsTrue(TDpccSettingsScopes.TryRouted('XmlDocMaxLines', mRouted), 'XmlDocMaxLines umgeleitet');
  Assert.AreEqual('hints.xmlDocMaxLines', mRouted.Path);
  // Server: alte Werte in settings.json ohne Meldung, auch ungültige; xmlDocMaxLines wirkt weiter.
  mServer := TConfigurationParser.Parse('{"hints": {"xmlDocExpand": "expanded", "xmlDocFull": true, ' +
    '"xmlDocMaxLines": 7}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Meldungen: ' + IssuesText(mIssues));
  Assert.AreEqual(7, mServer.Hints.XmlDocMaxLines, 'xmlDocMaxLines');
  TConfigurationParser.Parse('{"hints": {"xmlDocExpand": 3, "xmlDocFull": "ja"}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Meldungen bei ungültigen alten Werten: ' + IssuesText(mIssues));
  // Unbekanntes in hints meldet der Server weiter.
  TConfigurationParser.Parse('{"hints": {"xmlDocExpandX": "expanded"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'unbekannter Schlüssel');
end;

procedure TDpccCompletionViewTests.FormerRoutedKeysStayWithoutWarnings;
const
  // Was das Plugin bis OPT2 bei jedem OK nach settings.json schrieb (mit seinen Vorgaben), dazu xmlDocMaxLines.
  cFormer = '{"hints": {"xmlDocMaxLines": 0}, "slashCommands": {"enabled": true}, "codeLens": {"metrics": true}, ' +
    '"metrics": true, "experimental": {"enabled": false}, "compiler": {"onSave": false}, ' +
    '"architecture": {"enabled": true, "scope": "projectGroup", "includeLibraryUnits": false, "centralUnits": 15}, ' +
    '"query": {"enabled": true}, "ruleChecks": {"enabled": true}, ' +
    '"hotspots": {"enabled": true, "months": 12, "coupling": {"minCommits": 5}}, ' +
    '"references": {"inferred": true, "textMatches": false}, ' +
    '"navigation": {"symbolPath": true, "impact": true, "impactDepth": 2}, ' +
    '"tests": {"affected": true, "affectedDepth": 3}, ' +
    '"issues": {"connections": [], "projects": [], "queries": []}, ' +
    '"vcs": {"provider": "auto", "git": {"path": ""}, "svn": {"path": ""}, "timeoutSeconds": 15, "projects": []}, ' +
    '"index": {"extraSourceFolders": "C:\\A"}}';
  cPaths: array[0..14] of string = ('slashCommands.enabled', 'codeLens.metrics', 'metrics', 'experimental.enabled',
    'compiler.onSave', 'architecture.enabled', 'architecture.scope', 'query.enabled', 'ruleChecks.enabled',
    'hotspots.months', 'references.inferred', 'navigation.impactDepth', 'tests.affected', 'issues.connections',
    'vcs.provider');
var
  mRouted: TDpccRoutedSettingsStore;
  mStore: IDpccSettingsStore;
  mSettings: TDpccPluginSettings;
  mSetting: TDpccRoutedSetting;
  mPath: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Umgeleitet sind nur noch die beiden Werte der Seite bzw. des Tooltips.
  Assert.AreEqual(2, Integer(Length(TDpccSettingsScopes.Routed)), 'umgeleitete Werte');
  for mSetting in TDpccSettingsScopes.Routed do
  begin
    Assert.IsTrue(MatchText(mSetting.Path, ['hints.xmlDocMaxLines', 'index.extraSourceFolders']), mSetting.Path);
  end;
  for mPath in ['SlashCommands', 'CodeLensMetrics', 'Metrics', 'ExperimentalEnabled', 'CompileOnSave',
    'ArchitectureEnabled', 'QueryEnabled', 'RuleChecksEnabled', 'HotspotsEnabled', 'ReferencesInferred', 'SymbolPath',
    'Impact', 'TestsAffected', 'IssuesConnections', 'VcsProvider', 'VcsProjects'] do
  begin
    Assert.IsFalse(TDpccSettingsScopes.TryRouted(mPath, mSetting), mPath + ' umgeleitet');
  end;
  // Plugin: Lesen und Speichern lässt die früheren Schlüssel stehen, wie sie sind (Werte abweichend gesetzt).
  mRouted := TDpccRoutedSettingsStore.Create(TDpccMemorySettingsStore.Create,
    StringReplace(StringReplace(cFormer, '"onSave": false', '"onSave": true', []), '"months": 12', '"months": 30',
    []));
  mStore := mRouted;
  mSettings.Load(mStore);
  Assert.AreEqual('C:\A', mSettings.IndexExtraSourceFolders, 'Quellordner gelesen');
  mSettings.Save(mStore);
  Assert.AreEqual('true', JsonAt(mRouted.Text, 'compiler.onSave'), 'compiler.onSave bleibt');
  Assert.AreEqual('30', JsonAt(mRouted.Text, 'hotspots.months'), 'hotspots.months bleibt');
  for mPath in cPaths do
  begin
    Assert.IsTrue(JsonAt(mRouted.Text, mPath) <> '', mPath + ' bleibt stehen');
  end;
  // Server: die ganze frühere Datei ohne Meldung.
  TConfigurationParser.Parse(cFormer, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Meldungen: ' + IssuesText(mIssues));
end;

procedure TDpccCompletionViewTests.IndexPageAndServerSwitchesAreGone;
const
  cGone: array[0..6] of string = ('IndexProjectGroup', 'IndexSearchPaths', 'IndexLibraryPaths', 'IndexUsages',
    'MemoryBudgetMb', 'DiagnosticsProcesses', 'ServerStatusWindow');
  cGoneKeys: array[0..6] of string = ('index.projectGroup', 'index.searchPaths', 'index.libraryPaths',
    'index.usages', 'memoryBudgetMb', 'diagnostics.processes', 'server.statusWindow');
var
  mStore: IDpccMemorySettingsStore;
  mRouted: TDpccRoutedSetting;
  mName: string;
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mStore := TDpccMemorySettingsStore.FromSettings(TDpccPluginSettings.Defaults);
  for mName in cGone do
  begin
    Assert.IsFalse(MatchText(mName, mStore.Names), mName + ' gespeichert');
    Assert.IsFalse(TDpccSettingsScopes.TryRouted(mName, mRouted), mName + ' umgeleitet');
  end;
  // Das Plugin schreibt die Schlüssel nicht mehr nach settings.json.
  for mRouted in TDpccSettingsScopes.Routed do
  begin
    Assert.IsFalse(MatchText(mRouted.Path, cGoneKeys), mRouted.Path);
  end;
  // Vorgaben des Servers: ganzer Umfang, ohne Verwendungen, 768 MB.
  mSettings := TConfigurationParser.Parse('{}', mIssues);
  Assert.IsTrue(mSettings.IndexProjectGroup and mSettings.IndexSearchPaths and mSettings.IndexLibraryPaths,
    'Umfang (Vorgabe)');
  Assert.IsFalse(mSettings.IndexUsages, 'Verwendungen (Vorgabe)');
  Assert.AreEqual(cIndexMemoryBudgetMb, mSettings.MemoryBudgetMb, 'Speichergrenze (Vorgabe)');
  Assert.AreEqual(768, cIndexMemoryBudgetMb, 'bisherige Vorgabe');
  // Alte Werte in settings.json wirken nicht mehr und lösen keine Meldung aus.
  mSettings := TConfigurationParser.Parse('{"index": {"projectGroup": false, "searchPaths": false, ' +
    '"libraryPaths": false, "usages": true, "removeOrphans": false}, "memoryBudgetMb": 16}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Meldungen: ' + IssuesText(mIssues));
  Assert.IsTrue(mSettings.IndexProjectGroup, 'index.projectGroup');
  Assert.IsTrue(mSettings.IndexSearchPaths, 'index.searchPaths');
  Assert.IsTrue(mSettings.IndexLibraryPaths, 'index.libraryPaths');
  Assert.IsFalse(mSettings.IndexUsages, 'index.usages');
  Assert.AreEqual(cIndexMemoryBudgetMb, mSettings.MemoryBudgetMb, 'memoryBudgetMb');
  // Übrige Schlüssel des Index wirken weiter.
  Assert.IsFalse(mSettings.IndexRemoveOrphans, 'index.removeOrphans');
end;

procedure TDpccCompletionViewTests.FormerSettingsAreNeitherStoredNorRouted;
const
  // Je Rückbau ein paar Registry-Namen: Server-Prozess (S1), Code-Vorlagen (S2), Robustheit und Hover-Extras (S3),
  // Liste (S7a), versteckte Schalter (S8), Paarfärbung (S9), Tasten (R5), Experimentell, Modul-Schalter,
  // Einstellungsverlauf, Suche und Geändert-Markierung (OPT1/OPT2), dazu Namen der entfernten Reiter.
  cGone: array[0..39] of string = ('ServerPath', 'ServerMode', 'Snippets', 'ImportIdeTemplates', 'HangThresholdMs',
    'HoverProblemActions', 'ExpressionType', 'FilterChips', 'PanelWidth', 'SelectionMarker', 'SuggestionsLearned',
    'StatusField', 'Breadcrumbs', 'Minimap', 'StickyScroll', 'GitGutter', 'InlayHints', 'PairColors', 'PairGuides',
    'PairColorsLight', 'CompletionKey', 'SignatureKey', 'CompletionKeyPriority', 'PaletteKey', 'QuickToggleKey',
    'ExperimentalEnabled', 'DebugEnabled', 'SafeKeepSettingsHistory', 'SettingsSearch', 'SettingsMarkModified',
    'RecursionMarkers', 'ExitPoints', 'Reassigned', 'Problems', 'TrackLines', 'InlineDiagnostics', 'IssuesTracker',
    'WelcomePage', 'UnitSearchEnabled', 'VcsProvider');
var
  mStored: TArray<string>;
  mRouted: TDpccRoutedSetting;
  mName: string;
begin
  mStored := TDpccPluginSettings.StoredNames;
  for mName in cGone do
  begin
    Assert.IsFalse(MatchText(mName, mStored), mName + ' gespeichert');
    Assert.IsFalse(MatchText(mName, TDpccPluginSettings.ReadOnlyNames), mName + ' gelesen');
    Assert.IsFalse(TDpccSettingsScopes.TryRouted(mName, mRouted), mName + ' umgeleitet');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccCompletionViewTests);

end.
