unit dpcc.Core.Settings.CompletionView.Tests;

// Tests für den Completion-Schnitt der Optionen (dpcc.Core.Settings.CompletionView): welche Plugin-Einstellungen
// Tools › Optionen › dpcc noch zeigt (und wo), dass es seit S2 keine Code-Vorlagen und keine Seite „Server“ mehr
// gibt, welche Tasten „Tastenkonflikte“ zeigt und dass die Suche über die Einstellungen nichts Ausgeblendetes mehr
// findet. Seit S3 auch: keine Seite „Robustheit“ und keine Extras des Hovers mehr. Seit S4: keine Seite „Index“ und
// keine Schalter zum Server mehr; Umfang, Verwendungen und Speichergrenze des Index sind fest.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccCompletionViewTests = class
  public
    [Test]
    procedure CompletionSettingsStayOnMainPage;
    [Test]
    procedure KeysHaveOwnPage;
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
    [Test]
    procedure KeysPageShowsCompletionAndSignature;
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
  dpcc.Core.Commands.KeyConflicts,
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

procedure TDpccCompletionViewTests.CompletionSettingsStayOnMainPage;
var
  mCatalog: TDpccSettingsCatalog;
  mName: string;
begin
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    for mName in ['Enabled', 'OpenDelayMs', 'VisibleRows', 'AutoUses', 'ParameterHints',
      'HoverTooltip', 'XmlDocExpand', 'XmlDocMaxLines'] do
    begin
      Assert.AreEqual(Ord(spMain), Ord(PlaceOfName(mCatalog, mName)), mName);
    end;
  finally
    mCatalog.Free;
  end;
end;

procedure TDpccCompletionViewTests.KeysHaveOwnPage;
var
  mCatalog: TDpccSettingsCatalog;
begin
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    Assert.AreEqual(Ord(spKeys), Ord(PlaceOfName(mCatalog, 'CompletionKey')));
    Assert.AreEqual(Ord(spKeys), Ord(PlaceOfName(mCatalog, 'SignatureKeyPriority')));
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
    // Aus Allgemein nur der Hauptschalter; Statusfeld, Diagnose, Übertragen, Team-Datei usw. fallen weg.
    for mName in ['DiagnosticMode', 'ExperimentalEnabled', 'StatusField', 'ShortcutTips',
      'Notifications', 'SettingsExportImport', 'SettingsSearch', 'TeamFile', 'ArchitectureEnabled', 'QueryEnabled',
      'ReloadExternal'] do
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

procedure TDpccCompletionViewTests.KeysPageShowsCompletionAndSignature;
var
  mFunc: TDpccKeyFunction;
begin
  for mFunc := Low(TDpccKeyFunction) to High(TDpccKeyFunction) do
  begin
    Assert.IsTrue((mFunc in [TDpccKeyFunction.Completion, TDpccKeyFunction.Signature]) =
      TDpccCompletionView.ShowsKey(mFunc), IntToStr(Ord(mFunc)));
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
