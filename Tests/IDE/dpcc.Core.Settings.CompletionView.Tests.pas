unit dpcc.Core.Settings.CompletionView.Tests;

// Tests für den Completion-Schnitt der Optionen (dpcc.Core.Settings.CompletionView): welche Plugin-Einstellungen
// Tools › Optionen › dpcc noch zeigt (und wo), dass es seit S2 keine Code-Vorlagen und keine Seite „Server“ mehr
// gibt, welche Tasten „Tastenkonflikte“ zeigt und dass die Suche über die Einstellungen nichts Ausgeblendetes mehr
// findet. Seit S3 auch: keine Seite „Robustheit“ und keine Extras des Hovers mehr. Seit S4: keine Seite „Index“ und
// keine Schalter zum Server mehr; Umfang, Verwendungen und Speichergrenze des Index sind fest. Seit S7a: keine
// Schalter der früheren Liste (Filter-Chips, Detailpanel, Auswahlmarke) und keine gelernten Vorschläge mehr. Seit S8:
// keine versteckten Schalter ohne Wirkung der Reiter Allgemein und Hints mehr (weder im Katalog noch gespeichert);
// der versteckte, aber wirksame Hauptschalter experimental.enabled bleibt. Seit S9: keine Schalter Paarfärbung und
// Blocklinien (highlight.pairColors/pairGuides) mehr; dpcc fasst die Strukturhervorhebung der IDE nicht mehr an.
// Seit OPT1: eine einzige Seite mit genau zwölf Optionen unter dem Hauptschalter und zwei Knöpfen (cPageItems); die
// übrigen Optionen der früheren Unterseiten sind fest verdrahtet (TDpccFixedSettings), alte Werte wirken nicht mehr;
// „XMLDoc beim Öffnen“ (hints.xmlDocExpand) ist entfallen, Plugin und Server überlesen alte Werte ohne Meldung. Die
// Seite „Tastenkonflikte“ gibt es nicht mehr.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccCompletionViewTests = class
  public
    /// <summary>OPT1: Die Seite zeigt genau den Hauptschalter und zwölf Optionen in vier Abschnitten, dazu zwei
    /// Knöpfe; alles andere ist versteckt.</summary>
    [Test]
    procedure PageShowsExactlyTwelveOptions;
    /// <summary>OPT1: Die festen Werte sind die bisherigen Vorgaben (z. B. OpenDelayMs 150, FixCase an), stehen nicht
    /// auf der Seite und setzen sich gegen alte Werte durch; der Rest bleibt.</summary>
    [Test]
    procedure FixedSettingsKeepFormerDefaults;
    /// <summary>OPT1: hints.xmlDocExpand (und davor hints.xmlDocFull) gibt es weder im Katalog noch gespeichert noch
    /// in settings.json umgeleitet; alte Werte in Registry und settings.json lösen keine Meldung aus und ändern nichts.
    /// </summary>
    [Test]
    procedure XmlDocExpandIsIgnoredSilently;
    /// <summary>Die Seite „Tastenkonflikte“ gibt es seit Rückbau R5 nicht mehr: Tasten sind versteckt.</summary>
    [Test]
    procedure KeysAreHidden;
    /// <summary>S1: Pfad und Betriebsart eines eigenen Server-Prozesses gibt es nicht mehr.</summary>
    [Test]
    procedure ServerProcessSettingsAreGone;
    [Test]
    procedure RemovedPagesAreHidden;
    /// <summary>S2: keine Einstellungen der Code-Vorlagen (snippets.*) mehr, und Einstellungen des Servers haben
    /// keine eigene Seite („dpcc › Server“) mehr.</summary>
    [Test]
    procedure SnippetSettingsAndServerPageAreGone;
    /// <summary>S3: Seite „Robustheit“ (Hänger-Schwelle, Hinweis, Zeitlimit der Datenquellen) und die Extras des
    /// Hovers (Aktionszeile, Erklärungen, Beispiele, Mitglieder, offene Parameter, Debug-Werte, Typ des
    /// Ausdrucks) sind weder im Katalog noch gespeichert; das Schema bleibt ohne Fehler.</summary>
    [Test]
    procedure RobustnessAndHoverExtrasAreGone;
    /// <summary>S4: Seite „Index“ (Umfang, Verwendungen, Speichergrenze) und die Schalter „Prozesse am Projekt…“
    /// und Fenster „dpcc-Server“ sind weder im Katalog noch gespeichert noch nach settings.json umgeleitet; der
    /// Server nimmt feste Werte, auch wenn settings.json andere enthält.</summary>
    [Test]
    procedure IndexPageAndServerSwitchesAreGone;
    /// <summary>S6/S7a: Die Liste ist schlicht wie die Code-Insight-Liste der IDE; Filter-Chips, Detailpanel
    /// (Breite, eingeklappt), Auswahlmarke und die gelernten Vorschläge (suggestions.*) sind weder im Katalog noch
    /// gespeichert, die übrigen Schalter der Liste stehen auf der Seite.</summary>
    [Test]
    procedure PlainListSwitchesAreGone;
    /// <summary>S8: Die versteckten Schalter ohne Wirkung der Reiter Allgemein und Hints (Statusfeld, Diagnose,
    /// Tastenkürzel-Tipps, Projektdatei, Inlay-Hints, Brotkrumenleiste, Minimap, mitlaufender Kopf, Statusleiste,
    /// Änderungsmarken, dpcc-Spalte, gleichen Text hervorheben, übrige Paarfärbung usw.) sind weder im Katalog noch
    /// gespeichert noch nach settings.json umgeleitet; die Unterpunkte (x-nodes) dazu fehlen auch. Was noch wirkt,
    /// bleibt versteckt.</summary>
    [Test]
    procedure HiddenSwitchesWithoutEffectAreGone;
    /// <summary>S9: Paarfärbung und Blocklinien (highlight.pairColors, highlight.pairGuides) und ihr Unterpunkt
    /// editor.pairs sind weder im Katalog noch gespeichert noch nach settings.json umgeleitet; die eigenen Farben
    /// hängen an keinem Hauptschalter mehr, und das Schema bleibt ohne Fehler.</summary>
    [Test]
    procedure PairSwitchesAreGone;
    [Test]
    procedure SearchFindsNoHiddenSetting;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  dpcc.Core.Settings.Catalog,
  dpcc.Core.Settings.Groups,
  dpcc.Core.Settings.Search,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.History,
  dpcc.Core.Settings.Scopes,
  dpcc.Core.Settings.CompletionView,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Configuration.Parser;

function PlaceOfName(ACatalog: TDpccSettingsCatalog; const AName: string): TDpccSettingPlace;
var
  mIndex: Integer;
begin
  mIndex := ACatalog.IndexOfName(AName);
  Assert.IsTrue(mIndex >= 0, 'Katalog kennt ' + AName);
  Result := TDpccCompletionView.PlaceOf(ACatalog[mIndex]);
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
  mCatalog: TDpccSettingsCatalog;
  mIndex, mOptions, mButtons, mShown: Integer;
  mName: string;
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
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    for mName in TDpccCompletionView.SettingNames do
    begin
      Assert.AreEqual(Ord(spMain), Ord(PlaceOfName(mCatalog, mName)), mName);
    end;
    // Fest verdrahtet bzw. nur noch über settings.json: nicht mehr auf der Seite.
    for mName in TDpccFixedSettings.Names + ['XmlDocMaxLines', 'ExperimentalEnabled', 'SettingsSearch',
      'SettingsMarkModified'] do
    begin
      Assert.AreEqual(Ord(spHidden), Ord(PlaceOfName(mCatalog, mName)), mName);
    end;
    // Genau die 13 Einstellungen der Seite gelten als gezeigt.
    mShown := 0;
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      if TDpccCompletionView.ShowsSetting(mCatalog[mIndex]) then
      begin
        Inc(mShown);
        Assert.IsTrue(MatchText(mCatalog[mIndex].Name, TDpccCompletionView.SettingNames), mCatalog[mIndex].Name);
      end;
    end;
    Assert.AreEqual(13, mShown, 'gezeigte Einstellungen im Katalog');
  finally
    mCatalog.Free;
  end;
end;

procedure TDpccCompletionViewTests.FixedSettingsKeepFormerDefaults;
var
  mSettings, mDefaults: TDpccPluginSettings;
  mFixed, mDefault: IDpccMemorySettingsStore;
  mName: string;
begin
  mDefaults := TDpccPluginSettings.Defaults;
  // Die festen Werte sind die bisherigen Vorgaben.
  Assert.AreEqual(150, TDpccFixedSettings.cOpenDelayMs, 'OpenDelayMs');
  Assert.AreEqual(mDefaults.OpenDelayMs, TDpccFixedSettings.cOpenDelayMs, 'OpenDelayMs = Vorgabe');
  Assert.IsTrue(TDpccFixedSettings.cFixCase and mDefaults.FixCase, 'FixCase an');
  Assert.IsTrue(TDpccFixedSettings.cFavorites and mDefaults.Favorites, 'Favorites an');
  Assert.IsTrue(TDpccFixedSettings.cGroupInherited and mDefaults.GroupInherited, 'GroupInherited an');
  Assert.IsTrue(TDpccFixedSettings.cCompletionVariantBranch and mDefaults.CompletionVariantBranch,
    'CompletionVariantBranch an');
  Assert.AreEqual('members', TDpccFixedSettings.cCompletionListScope, 'CompletionListScope');
  Assert.AreEqual(mDefaults.CompletionListScope, TDpccFixedSettings.cCompletionListScope, 'Scope = Vorgabe');
  Assert.IsFalse(TDpccFixedSettings.cPreview or mDefaults.Preview, 'Preview aus');
  Assert.IsTrue(TDpccFixedSettings.cFormatPlaceholders and mDefaults.FormatPlaceholders, 'FormatPlaceholders an');
  Assert.AreEqual(0, mDefaults.XmlDocMaxLines, 'XmlDocMaxLines 0 (nur noch settings.json)');
  Assert.AreEqual(8, Integer(Length(TDpccFixedSettings.Names)), 'feste Einstellungen');
  // Alte, abweichende Werte (Registry) setzen sich nicht durch; die Optionen der Seite bleiben unberührt.
  mSettings := mDefaults;
  mSettings.OpenDelayMs := 900;
  mSettings.Favorites := False;
  mSettings.GroupInherited := False;
  mSettings.CompletionVariantBranch := False;
  mSettings.CompletionListScope := 'everywhere';
  mSettings.Preview := True;
  mSettings.FixCase := False;
  mSettings.FormatPlaceholders := False;
  mSettings.VisibleRows := 14;
  mSettings.AutoMinChars := 3;
  mSettings.Learning := False;
  TDpccFixedSettings.Apply(mSettings);
  mFixed := TDpccMemorySettingsStore.FromSettings(mSettings);
  mDefault := TDpccMemorySettingsStore.FromSettings(mDefaults);
  for mName in TDpccFixedSettings.Names do
  begin
    Assert.IsTrue(MatchText(mName, mDefault.Names), mName + ' gespeichert');
    Assert.AreEqual(mDefault.Text(mName), mFixed.Text(mName), mName);
  end;
  Assert.AreEqual(150, mSettings.OpenDelayMs, 'OpenDelayMs fest');
  Assert.IsTrue(mSettings.FixCase, 'FixCase fest');
  Assert.AreEqual(14, mSettings.VisibleRows, 'VisibleRows bleibt');
  Assert.AreEqual(3, mSettings.AutoMinChars, 'AutoMinChars bleibt');
  Assert.IsFalse(mSettings.Learning, 'Learning bleibt');
  // Keine feste Einstellung steht auf der Seite.
  for mName in TDpccFixedSettings.Names do
  begin
    Assert.IsFalse(MatchText(mName, TDpccCompletionView.SettingNames), mName + ' auf der Seite');
  end;
end;

procedure TDpccCompletionViewTests.XmlDocExpandIsIgnoredSilently;
var
  mCatalog: TDpccSettingsCatalog;
  mStore, mSaved: IDpccMemorySettingsStore;
  mSettings: TDpccPluginSettings;
  mRouted: TDpccRoutedSetting;
  mServer: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mIndex: Integer;
begin
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    Assert.IsTrue(mCatalog.IndexOfName('XmlDocExpand') < 0, 'XmlDocExpand im Katalog');
    Assert.IsTrue(mCatalog.IndexOfName('XmlDocMaxLines') >= 0, 'XmlDocMaxLines bleibt');
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      Assert.IsFalse(MatchText(mCatalog[mIndex].Key, ['hints.xmlDocExpand', 'hints.xmlDocFull']),
        mCatalog[mIndex].Key);
    end;
  finally
    mCatalog.Free;
  end;
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
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Meldungen');
  Assert.AreEqual(7, mServer.Hints.XmlDocMaxLines, 'xmlDocMaxLines');
  TConfigurationParser.Parse('{"hints": {"xmlDocExpand": 3, "xmlDocFull": "ja"}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Meldungen bei ungültigen alten Werten');
  // Unbekanntes in hints meldet der Server weiter.
  TConfigurationParser.Parse('{"hints": {"xmlDocExpandX": "expanded"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'unbekannter Schlüssel');
end;

procedure TDpccCompletionViewTests.PlainListSwitchesAreGone;
const
  cGone: array[0..8] of string = ('FilterChips', 'PanelWidth', 'PanelCollapsed', 'SelectionMarker',
    'SuggestionsLearned', 'SuggestionsDelayMs', 'SuggestionsMinShare', 'SuggestionsMinCount',
    'SuggestionsLearnFromUsage');
var
  mCatalog: TDpccSettingsCatalog;
  mStore: IDpccMemorySettingsStore;
  mIndex: Integer;
  mName: string;
begin
  mStore := TDpccMemorySettingsStore.FromSettings(TDpccPluginSettings.Defaults);
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    for mName in cGone do
    begin
      Assert.IsTrue(mCatalog.IndexOfName(mName) < 0, mName);
      Assert.IsFalse(MatchText(mName, mStore.Names), mName + ' gespeichert');
    end;
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      Assert.IsFalse((mCatalog[mIndex].Source = asPlugin) and StartsText('suggestions.', mCatalog[mIndex].Key),
        mCatalog[mIndex].Key);
    end;
    // Lernen steht auf der Seite; Favoriten und Gruppierung sind seit OPT1 fest verdrahtet.
    Assert.AreEqual(Ord(spMain), Ord(PlaceOfName(mCatalog, 'Learning')), 'Learning');
    for mName in ['Favorites', 'GroupInherited'] do
    begin
      Assert.AreEqual(Ord(spHidden), Ord(PlaceOfName(mCatalog, mName)), mName);
    end;
  finally
    mCatalog.Free;
  end;
end;

procedure TDpccCompletionViewTests.KeysAreHidden;
var
  mCatalog: TDpccSettingsCatalog;
begin
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    Assert.AreEqual(Ord(spHidden), Ord(PlaceOfName(mCatalog, 'CompletionKey')));
    Assert.AreEqual(Ord(spHidden), Ord(PlaceOfName(mCatalog, 'SignatureKeyPriority')));
    Assert.AreEqual(Ord(spHidden), Ord(PlaceOfName(mCatalog, 'PaletteKey')));
    Assert.AreEqual(Ord(spHidden), Ord(PlaceOfName(mCatalog, 'QuickToggleKey')));
  finally
    mCatalog.Free;
  end;
end;

procedure TDpccCompletionViewTests.ServerProcessSettingsAreGone;
var
  mCatalog: TDpccSettingsCatalog;
  mIndex: Integer;
begin
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    Assert.IsTrue(mCatalog.IndexOfName('ServerPath') < 0, 'ServerPath');
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      // Pfad und Betriebsart gab es nur für den eigenen Server-Prozess.
      Assert.IsFalse(MatchText(mCatalog[mIndex].Key, ['server.path', 'server.mode']), mCatalog[mIndex].Key);
    end;
  finally
    mCatalog.Free;
  end;
end;

procedure TDpccCompletionViewTests.RemovedPagesAreHidden;
const
  cRemoved: array[0..18] of string = ('Befehle', 'Issue-Tracker', 'Willkommensseite', 'Compiler', 'Debuggen',
    'Prüfregeln', 'Units suchen', 'Versionsverwaltung', 'Start und Updates', 'Projekt', 'Rückgängig', 'MCP',
    'KI-Assistenten', 'Architektur', 'Hotspots', 'Formatierung', 'Release-Build', 'Farben', 'Editor'); // german-ok x-page
var
  mCatalog: TDpccSettingsCatalog;
  mIndex, mChecked: Integer;
  mEntry: TDpccCatalogEntry;
  mName: string;
begin
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    mChecked := 0;
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      mEntry := mCatalog[mIndex];
      if (mEntry.Source <> asPlugin) or not MatchText(mEntry.Page, cRemoved) or StartsText('hints.', mEntry.Key) then
      begin
        Continue;
      end;
      Inc(mChecked);
      Assert.IsFalse(TDpccCompletionView.ShowsSetting(mEntry), mEntry.Key + ' (' + mEntry.Page + ')');
    end;
    Assert.IsTrue(mChecked > 300, 'Einträge geprüft: ' + IntToStr(mChecked));
    // Aus Allgemein nur der Hauptschalter; Übertragen, Suche, Architektur usw. fallen weg (Statusfeld, Diagnose,
    // Tipps, Projektdatei und Neuladen gibt es seit S8 auch als Einstellung nicht mehr).
    for mName in ['ExperimentalEnabled', 'Notifications', 'SettingsExportImport', 'SettingsSearch',
      'ArchitectureEnabled', 'QueryEnabled'] do
    begin
      Assert.AreEqual(Ord(spHidden), Ord(PlaceOfName(mCatalog, mName)), mName);
    end;
  finally
    mCatalog.Free;
  end;
end;

procedure TDpccCompletionViewTests.SnippetSettingsAndServerPageAreGone;
var
  mCatalog: TDpccSettingsCatalog;
  mIndex, mServer: Integer;
  mEntry: TDpccCatalogEntry;
  mStore: IDpccMemorySettingsStore;
begin
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    // Code-Vorlagen (#51) und Live Templates der IDE: weder im Katalog noch auf einer Seite.
    Assert.IsTrue(mCatalog.IndexOfName('Snippets') < 0, 'Snippets');
    Assert.IsTrue(mCatalog.IndexOfName('ImportIdeTemplates') < 0, 'ImportIdeTemplates');
    mServer := 0;
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      mEntry := mCatalog[mIndex];
      if mEntry.Source = asPlugin then
      begin
        Assert.IsFalse(StartsText('snippets.', mEntry.Key), mEntry.Key);
      end
      else
      begin
        // Einstellungen des Servers (settings.json, dpcc.json): ohne Seite „dpcc › Server“ nirgends mehr gezeigt.
        Inc(mServer);
        Assert.AreEqual(Ord(spHidden), Ord(TDpccCompletionView.PlaceOf(mEntry)), mEntry.Key);
      end;
    end;
    Assert.IsTrue(mServer > 0, 'Einstellungen des Servers geprüft');
  finally
    mCatalog.Free;
  end;
  // Gespeichert werden die Schalter der Code-Vorlagen auch nicht mehr.
  mStore := TDpccMemorySettingsStore.FromSettings(TDpccPluginSettings.Defaults);
  Assert.IsFalse(MatchText('Snippets', mStore.Names), 'Snippets gespeichert');
  Assert.IsFalse(MatchText('ImportIdeTemplates', mStore.Names), 'ImportIdeTemplates gespeichert');
  Assert.IsTrue(MatchText('AutoUses', mStore.Names), 'AutoUses gespeichert');
end;

procedure TDpccCompletionViewTests.RobustnessAndHoverExtrasAreGone;
const
  // DebugHoverValues ist seit S3b wieder da (Seite Hints), die übrigen Hover-Schalter bleiben weg.
  cGone: array[0..10] of string = ('HangThresholdMs', 'HangHint', 'ProviderTimeLimitMs', 'HoverProblemActions',
    'HoverExplainMessages', 'HoverRuleExamples', 'HoverMembersMaxLines', 'HoverSignatureParams',
    'ExpressionType', 'ExpressionTypeConversions', 'ExpressionTypeConstValue');
var
  mCatalog: TDpccSettingsCatalog;
  mGroups: TDpccSettingsGroups;
  mStore: IDpccMemorySettingsStore;
  mIndex: Integer;
  mName, mIssue: string;
begin
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  mGroups := TDpccSettingsGroups.Create(mCatalog);
  try
    for mName in cGone do
    begin
      Assert.IsTrue(mCatalog.IndexOfName(mName) < 0, mName);
    end;
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      if mCatalog[mIndex].Source <> asPlugin then
      begin
        Continue;
      end;
      Assert.IsFalse(SameText(mCatalog[mIndex].Page, 'Robustheit'), mCatalog[mIndex].Key); // german-ok x-page
      Assert.IsFalse(StartsText('robustness.', mCatalog[mIndex].Key), mCatalog[mIndex].Key);
      Assert.IsFalse(StartsText('hover.', mCatalog[mIndex].Key), mCatalog[mIndex].Key);
    end;
    // Der Hover bleibt schaltbar und steht auf der Seite „dpcc“.
    Assert.AreEqual(Ord(spMain), Ord(PlaceOfName(mCatalog, 'HoverTooltip')));
    // Werte im Hover beim Debuggen (S3b): schaltbar auf derselben Seite, weil dpcc dafür den Wert-Tooltip der IDE
    // abschaltet.
    Assert.AreEqual(Ord(spMain), Ord(PlaceOfName(mCatalog, 'DebugHoverValues')));
    // Kein Verweis auf einen entfernten Hauptschalter (keys.expressionType hing an hints.expressionType).
    for mIssue in mGroups.Issues do
    begin
      Assert.IsFalse(ContainsText(mIssue, 'expressionType') or ContainsText(mIssue, 'hover.'), mIssue);
    end;
  finally
    mGroups.Free;
    mCatalog.Free;
  end;
  mStore := TDpccMemorySettingsStore.FromSettings(TDpccPluginSettings.Defaults);
  for mName in cGone do
  begin
    Assert.IsFalse(MatchText(mName, mStore.Names), mName + ' gespeichert');
  end;
  Assert.IsTrue(MatchText('HoverTooltip', mStore.Names), 'HoverTooltip gespeichert');
  Assert.IsTrue(MatchText('DebugHoverValues', mStore.Names), 'DebugHoverValues gespeichert');
  Assert.IsTrue(TDpccPluginSettings.Defaults.DebugHoverValues, 'Vorgabe wie vor S3: an');
end;

procedure TDpccCompletionViewTests.IndexPageAndServerSwitchesAreGone;
const
  cGone: array[0..6] of string = ('IndexProjectGroup', 'IndexSearchPaths', 'IndexLibraryPaths', 'IndexUsages',
    'MemoryBudgetMb', 'DiagnosticsProcesses', 'ServerStatusWindow');
  cGoneKeys: array[0..6] of string = ('index.projectGroup', 'index.searchPaths', 'index.libraryPaths',
    'index.usages', 'memoryBudgetMb', 'diagnostics.processes', 'server.statusWindow');
var
  mCatalog: TDpccSettingsCatalog;
  mStore: IDpccMemorySettingsStore;
  mRouted: TDpccRoutedSetting;
  mIndex: Integer;
  mName: string;
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    for mName in cGone do
    begin
      Assert.IsTrue(mCatalog.IndexOfName(mName) < 0, mName);
    end;
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      if mCatalog[mIndex].Source <> asPlugin then
      begin
        Continue;
      end;
      Assert.IsFalse(SameText(mCatalog[mIndex].Page, 'Index'), mCatalog[mIndex].Key);
      Assert.IsFalse(MatchText(mCatalog[mIndex].Key, cGoneKeys), mCatalog[mIndex].Key);
    end;
  finally
    mCatalog.Free;
  end;
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
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Meldungen');
  Assert.IsTrue(mSettings.IndexProjectGroup, 'index.projectGroup');
  Assert.IsTrue(mSettings.IndexSearchPaths, 'index.searchPaths');
  Assert.IsTrue(mSettings.IndexLibraryPaths, 'index.libraryPaths');
  Assert.IsFalse(mSettings.IndexUsages, 'index.usages');
  Assert.AreEqual(cIndexMemoryBudgetMb, mSettings.MemoryBudgetMb, 'memoryBudgetMb');
  // Übrige Schlüssel des Index wirken weiter.
  Assert.IsFalse(mSettings.IndexRemoveOrphans, 'index.removeOrphans');
end;

procedure TDpccCompletionViewTests.HiddenSwitchesWithoutEffectAreGone;
const
  // Registry-Namen der entfernten Schalter (Reiter Allgemein und Hints, S8).
  cGone: array[0..85] of string = ('ReloadExternal', 'OpenForEdits', 'StatusField', 'StatusFieldSummary',
    'StatusFieldToggles', 'IndexProgressPlace', 'StatusFieldHidden', 'DiagnosticMode', 'DiagnosticPluginTimings',
    'DiagnosticSlowMs', 'ShortcutTips', 'ShortcutTipsScope', 'TeamFile', 'PairOwners', 'PairGuideWidth',
    'PairGuideOpacity', 'NestedRoutines', 'NestedRoutineBand', 'InactiveDim', 'InlayHints', 'InlayTypeHints',
    'InlayDefineHints', 'InlayCharHints', 'InlayMethodHints', 'BlockEndLabels', 'BlockEndLabelsMinLines',
    'DimUnusedUses', 'Breadcrumbs', 'BreadcrumbsShowUnit', 'BreadcrumbsVisibility', 'BreadcrumbsMemberBlocks',
    'BreadcrumbsVisibilityMark', 'BreadcrumbsDeclarationBlocks', 'BreadcrumbsConditionals', 'BreadcrumbsRegions',
    'BreadcrumbsStatements', 'BreadcrumbsSectionCounts', 'BreadcrumbsSectionAppend', 'BreadcrumbsSectionCreate',
    'BreadcrumbsHideIdeToolbar', 'BreadcrumbsIdeColors', 'BreadcrumbsKey', 'SectionAppendKey', 'BreadcrumbsContextMenu',
    'BreadcrumbsOverloads', 'BreadcrumbsInterfaces', 'BreadcrumbsMetrics', 'MouseNavButtons', 'EditorStatusBar',
    'EditorStatusBarItems', 'CallHierarchyDiagram', 'StickyScroll', 'StickyScrollMaxLines', 'StickyScrollTypes',
    'StickyScrollRoutines', 'StickyScrollBlocks', 'StickyScrollLoops', 'StickyScrollTry', 'StickyScrollCase',
    'StickyScrollWith', 'StickyScrollBlockMinLines', 'Minimap', 'MinimapRender', 'MinimapWidth', 'MinimapScale',
    'MinimapMaxColumn', 'MinimapSide', 'MinimapShowSlider', 'MinimapSectionHeaders', 'MinimapHighlightMethod',
    'MinimapMarkers', 'MinimapClickJumps', 'GitGutter', 'NextChangeKey', 'PreviousChangeKey', 'GitBlame',
    'GutterColumn', 'GutterColumnProblems', 'GutterColumnCodeActions', 'GutterColumnOverrides', 'SelectionMatches',
    'SelectionMatchesMinLength', 'SelectionMatchesCaseSensitive', 'SelectionMatchesWholeWord',
    'SelectionMatchesNavigateF3', 'SelectionMatchesMaxMatches');
  // Präfixe der x-keys, die es im Plugin gar nicht mehr gibt.
  cGonePrefixes: array[0..7] of string = ('statusField.', 'shortcutTips.', 'diagnosticMode.', 'teamFile.',
    'inlayHints.', 'editor.stickyScroll', 'editor.gutterColumn', 'highlight.selectionMatches');
  cGoneNodes: array[0..8] of string = ('general.statusField', 'general.shortcutTips', 'editor.breadcrumbs',
    'editor.statusBar', 'editor.stickyScroll', 'editor.minimap', 'editor.gitGutter', 'editor.gutterColumn',
    'editor.selectionMatches');
var
  mCatalog: TDpccSettingsCatalog;
  mGroups: TDpccSettingsGroups;
  mStore: IDpccMemorySettingsStore;
  mRouted: TDpccRoutedSetting;
  mNode: TDpccCatalogArea;
  mIndex: Integer;
  mName, mPrefix, mIssue: string;
begin
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  mGroups := TDpccSettingsGroups.Create(mCatalog);
  try
    for mName in cGone do
    begin
      Assert.IsTrue(mCatalog.IndexOfName(mName) < 0, mName);
    end;
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      if mCatalog[mIndex].Source <> asPlugin then
      begin
        Continue;
      end;
      for mPrefix in cGonePrefixes do
      begin
        Assert.IsFalse(StartsText(mPrefix, mCatalog[mIndex].Key), mCatalog[mIndex].Key);
      end;
    end;
    for mNode in mGroups.Nodes do
    begin
      Assert.IsFalse(MatchText(mNode.Id, cGoneNodes), mNode.Id);
    end;
    // Das gekürzte Schema bleibt stimmig: keine Verweise auf entfernte Hauptschalter oder Unterpunkte.
    for mIssue in mGroups.Issues do
    begin
      for mPrefix in cGonePrefixes do
      begin
        Assert.IsFalse(ContainsText(mIssue, mPrefix), mIssue);
      end;
      for mName in cGoneNodes do
      begin
        Assert.IsFalse(ContainsText(mIssue, mName), mIssue);
      end;
    end;
    // Versteckt, aber wirksam: Hauptschalter der experimentellen Funktionen (settings.json, experimentelle Schlüssel
    // des Servers). Paarfärbung und Blocklinien gibt es seit S9 nicht mehr (PairSwitchesAreGone).
    Assert.AreEqual(Ord(spHidden), Ord(PlaceOfName(mCatalog, 'ExperimentalEnabled')), 'ExperimentalEnabled');
  finally
    mGroups.Free;
    mCatalog.Free;
  end;
  mStore := TDpccMemorySettingsStore.FromSettings(TDpccPluginSettings.Defaults);
  for mName in cGone do
  begin
    Assert.IsFalse(MatchText(mName, mStore.Names), mName + ' gespeichert');
    Assert.IsFalse(TDpccSettingsScopes.TryRouted(mName, mRouted), mName + ' umgeleitet');
  end;
  Assert.IsTrue(MatchText('ExperimentalEnabled', mStore.Names), 'ExperimentalEnabled gespeichert');
  // Das Plugin schreibt keine Inlay-Hints mehr nach settings.json; experimental.enabled schon.
  for mRouted in TDpccSettingsScopes.Routed do
  begin
    Assert.IsFalse(StartsText('inlayHints.', mRouted.Path), mRouted.Path);
  end;
  Assert.IsTrue(TDpccSettingsScopes.TryRouted('ExperimentalEnabled', mRouted), 'ExperimentalEnabled umgeleitet');
end;

procedure TDpccCompletionViewTests.PairSwitchesAreGone;
const
  cGone: array[0..1] of string = ('PairColors', 'PairGuides');
  cGoneKeys: array[0..1] of string = ('highlight.pairColors', 'highlight.pairGuides');
  // Eigene Farben hingen an highlight.pairColors; sie bleiben (gespeichert, versteckt), aber ohne Hauptschalter.
  cColors: array[0..3] of string = ('PairColorsLight', 'PairColorsDark', 'NestedRoutineColorLight',
    'NestedRoutineColorDark');
var
  mCatalog: TDpccSettingsCatalog;
  mGroups: TDpccSettingsGroups;
  mStore: IDpccMemorySettingsStore;
  mRouted: TDpccRoutedSetting;
  mNode: TDpccCatalogArea;
  mIndex: Integer;
  mName, mIssue: string;
begin
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  mGroups := TDpccSettingsGroups.Create(mCatalog);
  try
    for mName in cGone do
    begin
      Assert.IsTrue(mCatalog.IndexOfName(mName) < 0, mName);
      Assert.IsFalse(mGroups.Contains(mName), mName + ' in den Gruppen');
    end;
    for mIndex := 0 to mCatalog.Count - 1 do
    begin
      if mCatalog[mIndex].Source <> asPlugin then
      begin
        Continue;
      end;
      Assert.IsFalse(MatchText(mCatalog[mIndex].Key, cGoneKeys), mCatalog[mIndex].Key);
    end;
    Assert.IsFalse(mGroups.HasNode('editor.pairs'), 'Unterpunkt editor.pairs');
    for mNode in mGroups.Nodes do
    begin
      Assert.IsFalse(SameText(mNode.Id, 'editor.pairs'), mNode.Id);
    end;
    for mName in cColors do
    begin
      Assert.IsTrue(mCatalog.IndexOfName(mName) >= 0, mName);
      Assert.AreEqual('', mGroups.ParentOf(mName), mName + ': Hauptschalter');
    end;
    // Das gekürzte Schema bleibt stimmig: kein Verweis auf den entfernten Hauptschalter oder Unterpunkt.
    for mIssue in mGroups.Issues do
    begin
      Assert.IsFalse(ContainsText(mIssue, 'highlight.pair') or ContainsText(mIssue, 'editor.pairs'), mIssue);
    end;
  finally
    mGroups.Free;
    mCatalog.Free;
  end;
  mStore := TDpccMemorySettingsStore.FromSettings(TDpccPluginSettings.Defaults);
  for mName in cGone do
  begin
    Assert.IsFalse(MatchText(mName, mStore.Names), mName + ' gespeichert');
    Assert.IsFalse(TDpccSettingsScopes.TryRouted(mName, mRouted), mName + ' umgeleitet');
  end;
  for mRouted in TDpccSettingsScopes.Routed do
  begin
    Assert.IsFalse(MatchText(mRouted.Path, cGoneKeys), mRouted.Path);
  end;
  for mName in cColors do
  begin
    Assert.IsTrue(MatchText(mName, mStore.Names), mName + ' gespeichert');
  end;
end;

procedure TDpccCompletionViewTests.SearchFindsNoHiddenSetting;
var
  mCatalog: TDpccSettingsCatalog;
  mGroups: TDpccSettingsGroups;
  mHits: TArray<TDpccSettingHit>;
  mHit: TDpccSettingHit;
  mWord: string;
begin
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  mGroups := TDpccSettingsGroups.Create(mCatalog);
  try
    // Ausgeblendete Funktionen: kein Treffer mit ihrem Schlüssel; Tippfehler-Treffer („minimap“ ~ „Minimum“) dürfen nur
    // gezeigte Einstellungen sein.
    for mWord in ['minimap', 'breadcrumbs', 'tracker', 'welcomePage'] do
    begin
      for mHit in TDpccSettingsSearch.Find(mCatalog, mGroups, mWord, False, 50) do
      begin
        Assert.IsFalse(ContainsText(mHit.Key, mWord), mWord + ': ' + mHit.Key);
        Assert.IsTrue(TDpccCompletionView.ShowsName(mCatalog, mHit.Name), mWord + ': ' + mHit.Key);
      end;
    end;
    // „server“ fehlt seit S1: Die einzigen gezeigten Treffer waren Pfad und Betriebsart des eigenen Server-Prozesses.
    // „index“ trifft seit S4 höchstens noch gezeigte Einstellungen anderer Seiten (die Seite „Index“ ist weg).
    for mWord in ['hover', 'uses', 'index'] do
    begin
      mHits := TDpccSettingsSearch.Find(mCatalog, mGroups, mWord, False, 50);
      Assert.IsTrue((Length(mHits) > 0) or (mWord = 'index'), mWord);
      for mHit in mHits do
      begin
        Assert.IsTrue(TDpccCompletionView.ShowsName(mCatalog, mHit.Name), mWord + ': ' + mHit.Key);
      end;
    end;
    // Der Haken Shown schränkt weiter ein (Seite zeigt nur, was sichtbar ist).
    mHits := TDpccSettingsSearch.Find(mCatalog, mGroups, 'hover', False, 50, TDpccSettingsSearchHooks.Create(nil, nil,
      function(const AName: string): Boolean
      begin
        Result := False;
      end));
    Assert.AreEqual(0, Integer(Length(mHits)));
  finally
    mGroups.Free;
    mCatalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccCompletionViewTests);

end.
