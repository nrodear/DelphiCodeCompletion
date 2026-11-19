unit dpcc.UI.Settings.Page.Tests;

// Tests für die eine Seite „dpcc“ unter Tools › Optionen › Fremdhersteller (OPT1, dpcc.UI.Settings.Page). Die Seite
// wird ohne IDE und ohne Fenster erzeugt (wie die IDE sie vor dem Einhängen erzeugt) und an ihren Elementen geprüft:
// genau Hauptschalter, zwölf Optionen und zwei Knöpfe in Reihenfolge und Abschnitten, Sperre durch den Hauptschalter,
// Kopplung „Eigener Tooltip“ → „Werte beim Debuggen“, Laden und Speichern über TDpccPluginSettings, die Knöpfe und
// das Layout (keine Beschriftung ragt in ein Feld, deutsch und englisch; passt ohne Rollen). Seit IDECHECK zuletzt der
// Abschnitt IDE mit „Jetzt prüfen“ und den Statuszeilen (OnIdeStatus).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccSettingsPageTests = class
  public
    /// <summary>Einmalige Belegungen der VCL (Stil, Schriften) vor der Leckmessung der Tests.</summary>
    [SetupFixture]
    procedure Prewarm;
    /// <summary>Genau Hauptschalter, zwölf Optionen und zwei Knöpfe, in der Reihenfolge der Seite und unter der
    /// richtigen Überschrift; vier Überschriften in Großbuchstaben.</summary>
    [Test]
    procedure PageHasTwelveOptionsAndTwoButtonsInSections;
    /// <summary>Hauptschalter aus: alle Optionen und „Verlauf zurücksetzen“ grau, „Index neu aufbauen“ nicht.
    /// </summary>
    [Test]
    procedure MasterSwitchLocksAllOptions;
    /// <summary>„Werte beim Debuggen“ grau, wenn „Eigener Tooltip“ aus ist.</summary>
    [Test]
    procedure TooltipCouplesDebugValues;
    /// <summary>Laden und Speichern aller Werte der Seite; was die Seite nicht zeigt, bleibt.</summary>
    [Test]
    procedure LoadAndSaveRoundTrip;
    /// <summary>„Breite automatisch“: an = 0, aus = gezogene bzw. mittlere Breite.</summary>
    [Test]
    procedure AutoWidthKeepsDraggedWidth;
    /// <summary>„Verlauf zurücksetzen“ ruft den Haken einmal und wird grau.</summary>
    [Test]
    procedure ResetHistoryButton;
    /// <summary>„Index neu aufbauen“: ohne Haken grau, mit Rückfrage Nein nichts, mit Ja die Meldung.</summary>
    [Test]
    procedure RebuildIndexButton;
    /// <summary>„Index neu aufbauen“ im Hintergrund (OnRebuildStatus): läuft → Knopf grau mit Meldung, zweiter Klick
    /// tut nichts, danach wieder frei; eine neu geöffnete Seite zeigt einen laufenden Neuaufbau sofort.</summary>
    [Test]
    procedure RebuildIndexRunningState;
    /// <summary>„Index neu aufbauen“ von der Sitzung abgelehnt (wie TDpccPageOptions dann meldet: läuft nicht, eigener
    /// Text): Knopf sofort wieder frei, neben ihm nicht mehr „läuft …“, ein weiterer Klick ist möglich.</summary>
    [Test]
    procedure RebuildIndexRejected;
    /// <summary>Abschnitt IDE: „Jetzt prüfen“ ohne Haken grau; mit Haken zeigt die Seite die Statuszeilen sofort und
    /// nach jedem Klick neu; hängt nicht am Hauptschalter.</summary>
    [Test]
    procedure CheckIdeButton;
    /// <summary>Keine Beschriftung ragt in ihr Feld, auch nicht auf Englisch; die Seite passt ohne Rollen.</summary>
    [Test]
    [TestCase('Deutsch', 'False')]
    [TestCase('Englisch', 'True')]
    procedure LabelsDoNotOverlapFields(AEnglish: Boolean);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.UITypes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.CompletionView,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.UI.Settings.Page;

function RowIndex(APage: TDpccSettingsPage; ARow: TWinControl): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(APage.Rows) do
  begin
    if APage.Rows[mIndex] = ARow then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TDpccSettingsPageTests }

procedure TDpccSettingsPageTests.Prewarm;
var
  mPage: TDpccSettingsPage;
  mLanguage: TDpccLanguage;
begin
  for mLanguage := Low(TDpccLanguage) to High(TDpccLanguage) do
  begin
    TDpccStrings.Language := mLanguage;
    mPage := TDpccSettingsPage.Create(nil);
    try
      mPage.LoadFrom(TDpccPluginSettings.Defaults);
    finally
      mPage.Free;
    end;
  end;
  TDpccStrings.Language := Low(TDpccLanguage);
end;

procedure TDpccSettingsPageTests.PageHasTwelveOptionsAndTwoButtonsInSections;
const
  cNames: array[0..15] of string = ('Enabled', 'AutoMinChars', 'CompletionListMode', 'VisibleRows', 'ListWidth',
    'Learning', 'ResetHistory', 'AutoParentheses', 'CommitCharacters', 'AutoUses', 'ParameterHints', 'HoverTooltip',
    'DebugHoverValues', 'IndexExtraSourceFolders', 'RebuildIndex', 'CheckIde');
  cSections: array[0..15] of TDpccPageSection = (psMaster, psCompletion, psCompletion, psCompletion, psCompletion,
    psCompletion, psCompletion, psCommit, psCommit, psCommit, psHints, psHints, psHints, psIndex, psIndex, psIde);
  cTitles: array[TDpccPageSection] of string = ('', 'VERVOLLSTÄNDIGUNG', 'BEIM ÜBERNEHMEN',
    'PARAMETER-HINT UND TOOLTIP', 'INDEX', 'IDE');
var
  mPage: TDpccSettingsPage;
  mEntry: TDpccSettingsPageEntry;
  mIndex, mRow, mLastRow, mTitleRow, mOptions, mButtons: Integer;
  mSection, mFound: TDpccPageSection;
begin
  mPage := TDpccSettingsPage.Create(nil);
  try
    Assert.AreEqual(Integer(Length(cNames)), Integer(Length(mPage.Entries)), 'Elemente');
    // Fünf Überschriften, Großbuchstaben, keine für den Hauptschalter.
    Assert.IsNull(mPage.TitleOf(psMaster), 'Überschrift Hauptschalter');
    for mSection := psCompletion to psIde do
    begin
      Assert.IsNotNull(mPage.TitleOf(mSection), 'Überschrift ' + cTitles[mSection]);
      Assert.AreEqual(cTitles[mSection], mPage.TitleOf(mSection).Caption);
      Assert.IsTrue(fsBold in mPage.TitleOf(mSection).Font.Style, 'fett');
    end;
    mOptions := 0;
    mButtons := 0;
    mLastRow := -1;
    for mIndex := 0 to High(mPage.Entries) do
    begin
      mEntry := mPage.Entries[mIndex];
      Assert.AreEqual(cNames[mIndex], mEntry.Item.Name, 'Element ' + IntToStr(mIndex));
      Assert.AreEqual(Ord(cSections[mIndex]), Ord(mEntry.Item.Section), cNames[mIndex] + ': Abschnitt');
      Assert.IsTrue(mPage.ControlOf(cNames[mIndex]) = mEntry.Control, cNames[mIndex] + ': ControlOf');
      if mEntry.Item.Kind = pkButton then
      begin
        Inc(mButtons);
        Assert.IsTrue(mEntry.Control is TButton, cNames[mIndex] + ': Knopf');
      end
      else if mEntry.Item.Section <> psMaster then
      begin
        Inc(mOptions);
      end;
      // Reihenfolge: jede Zeile unter der vorigen (Breite automatisch und Verlauf zurücksetzen teilen die Zeile).
      mRow := RowIndex(mPage, mEntry.Row);
      Assert.IsTrue(mRow >= mLastRow, cNames[mIndex] + ': Reihenfolge');
      if mIndex > 0 then
      begin
        Assert.IsTrue(mPage.Rows[mRow].Top >= mPage.Entries[mIndex - 1].Row.Top, cNames[mIndex] + ': Lage');
      end;
      mLastRow := mRow;
      // Gruppierung: die nächste Überschrift darüber gehört zum Abschnitt des Elements.
      mFound := psMaster;
      mTitleRow := -1;
      for mSection := psCompletion to psIde do
      begin
        if (RowIndex(mPage, mPage.TitleOf(mSection).Parent) < mRow) and
          (RowIndex(mPage, mPage.TitleOf(mSection).Parent) > mTitleRow) then
        begin
          mTitleRow := RowIndex(mPage, mPage.TitleOf(mSection).Parent);
          mFound := mSection;
        end;
      end;
      Assert.AreEqual(Ord(mEntry.Item.Section), Ord(mFound), cNames[mIndex] + ': unter der Überschrift');
    end;
    Assert.AreEqual(12, mOptions, 'Optionen');
    Assert.AreEqual(3, mButtons, 'Knöpfe');
    // Art der Elemente.
    Assert.IsTrue(mPage.ControlOf('Enabled') is TCheckBox, 'Hauptschalter');
    Assert.IsTrue(mPage.ControlOf('ListWidth') = mPage.AutoWidth, 'Breite automatisch');
    Assert.IsTrue(mPage.ControlOf('IndexExtraSourceFolders') is TEdit, 'Quellordner');
    Assert.IsTrue(mPage.ControlOf('CompletionListMode') = mPage.ListModeChoice, 'Listenmodus');
    Assert.IsTrue(mPage.ControlOf(cPageCheckIde) = mPage.CheckIde, 'Jetzt prüfen');
    Assert.IsTrue(mPage.IdeStatus.Parent = mPage.CheckIde.Parent, 'Statuszeilen neben dem Knopf');
    Assert.IsNull(mPage.ControlOf('OpenDelayMs'), 'fest verdrahtet');
    Assert.IsNull(mPage.ControlOf('XmlDocExpand'), 'entfallen');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.MasterSwitchLocksAllOptions;
var
  mPage: TDpccSettingsPage;
  mEntry: TDpccSettingsPageEntry;
  mSettings: TDpccPluginSettings;
begin
  mPage := TDpccSettingsPage.Create(nil);
  try
    mPage.OnRebuildIndex :=
      function: string
      begin
        Result := '';
      end;
    mPage.OnIdeStatus :=
      function: string
      begin
        Result := '';
      end;
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    for mEntry in mPage.Entries do
    begin
      Assert.IsTrue(mEntry.Control.Enabled, mEntry.Item.Name + ' an');
    end;
    // Ausgeschaltet geladen: alles darunter grau, auch die Beschriftungen.
    mSettings := TDpccPluginSettings.Defaults;
    mSettings.Enabled := False;
    mPage.LoadFrom(mSettings);
    for mEntry in mPage.Entries do
    begin
      if (mEntry.Item.Name = 'Enabled') or (mEntry.Item.Name = cPageRebuildIndex) or
        (mEntry.Item.Name = cPageCheckIde) then
      begin
        Assert.IsTrue(mEntry.Control.Enabled, mEntry.Item.Name + ' bleibt bedienbar');
        Continue;
      end;
      Assert.IsFalse(mEntry.Control.Enabled, mEntry.Item.Name + ' grau');
      if mEntry.Caption <> nil then
      begin
        Assert.IsFalse(mEntry.Caption.Enabled, mEntry.Item.Name + ': Beschriftung grau');
      end;
    end;
    // Klick auf den Hauptschalter gibt alles wieder frei.
    mPage.MasterSwitch.Checked := True;
    for mEntry in mPage.Entries do
    begin
      Assert.IsTrue(mEntry.Control.Enabled, mEntry.Item.Name + ' wieder an');
    end;
    mPage.MasterSwitch.Checked := False;
    Assert.IsFalse(mPage.ControlOf('IndexExtraSourceFolders').Enabled, 'Quellordner nach Klick grau');
    Assert.IsFalse(mPage.ResetHistory.Enabled, 'Verlauf zurücksetzen nach Klick grau');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.TooltipCouplesDebugValues;
var
  mPage: TDpccSettingsPage;
  mSettings: TDpccPluginSettings;
begin
  mPage := TDpccSettingsPage.Create(nil);
  try
    mSettings := TDpccPluginSettings.Defaults;
    mSettings.HoverTooltip := False;
    mPage.LoadFrom(mSettings);
    Assert.IsFalse(mPage.DebugHoverValues.Enabled, 'Tooltip aus geladen');
    Assert.IsTrue(mPage.DebugHoverValues.Checked, 'Wert bleibt');
    mPage.HoverTooltip.Checked := True;
    Assert.IsTrue(mPage.DebugHoverValues.Enabled, 'Tooltip an');
    mPage.HoverTooltip.Checked := False;
    Assert.IsFalse(mPage.DebugHoverValues.Enabled, 'Tooltip aus');
    // Hauptschalter aus sperrt auch mit eigenem Tooltip.
    mPage.HoverTooltip.Checked := True;
    mPage.MasterSwitch.Checked := False;
    Assert.IsFalse(mPage.DebugHoverValues.Enabled, 'Hauptschalter aus');
    // Gespeichert wird der Wert trotzdem.
    mSettings := TDpccPluginSettings.Defaults;
    mSettings.DebugHoverValues := False;
    mPage.SaveTo(mSettings);
    Assert.IsTrue(mSettings.DebugHoverValues, 'Werte beim Debuggen gespeichert');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.LoadAndSaveRoundTrip;
var
  mPage: TDpccSettingsPage;
  mLoaded, mTarget: TDpccPluginSettings;
begin
  // Alle Werte der Seite abweichend von der Vorgabe.
  mLoaded := TDpccPluginSettings.Defaults;
  mLoaded.Enabled := False;
  mLoaded.AutoMinChars := 4;
  mLoaded.CompletionListMode := 'rest';
  mLoaded.VisibleRows := 13;
  mLoaded.ListWidth := 500;
  mLoaded.Learning := False;
  mLoaded.AutoParentheses := False;
  mLoaded.CommitCharacters := False;
  mLoaded.AutoUses := False;
  mLoaded.ParameterHints := False;
  mLoaded.HoverTooltip := False;
  mLoaded.DebugHoverValues := False;
  mLoaded.IndexExtraSourceFolders := 'C:\A;C:\B';
  mPage := TDpccSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mLoaded);
    Assert.AreEqual(4, mPage.AutoMinCharsChoice.Choice, 'Auswahl ab Zeichen');
    Assert.AreEqual(13 - TDpccPluginSettings.cMinVisibleRows, mPage.VisibleRowsChoice.Choice, 'Auswahl Zeilen');
    Assert.AreEqual(2, mPage.ListModeChoice.Choice, 'Listenmodus');
    Assert.IsFalse(mPage.AutoWidth.Checked, 'Breite automatisch');
    // Gespeichert in die Vorgabe mit abweichenden Werten, die die Seite nicht zeigt (seit OPT2 nur noch die nur
    // gelesenen): Die bleiben.
    mTarget := TDpccPluginSettings.Defaults;
    mTarget.XmlDocMaxLines := 9;
    mTarget.LogNames := True;
    mPage.SaveTo(mTarget);
    Assert.IsFalse(mTarget.Enabled, 'Enabled');
    Assert.AreEqual(4, mTarget.AutoMinChars, 'AutoMinChars');
    Assert.AreEqual('rest', mTarget.CompletionListMode, 'CompletionListMode');
    Assert.AreEqual(13, mTarget.VisibleRows, 'VisibleRows');
    Assert.AreEqual(500, mTarget.ListWidth, 'ListWidth');
    Assert.IsFalse(mTarget.Learning, 'Learning');
    Assert.IsFalse(mTarget.AutoParentheses, 'AutoParentheses');
    Assert.IsFalse(mTarget.CommitCharacters, 'CommitCharacters');
    Assert.IsFalse(mTarget.AutoUses, 'AutoUses');
    Assert.IsFalse(mTarget.ParameterHints, 'ParameterHints');
    Assert.IsFalse(mTarget.HoverTooltip, 'HoverTooltip');
    Assert.IsFalse(mTarget.DebugHoverValues, 'DebugHoverValues');
    Assert.AreEqual('C:\A;C:\B', mTarget.IndexExtraSourceFolders, 'IndexExtraSourceFolders');
    Assert.AreEqual(9, mTarget.XmlDocMaxLines, 'XmlDocMaxLines bleibt');
    Assert.IsTrue(mTarget.LogNames, 'LogNames bleibt');
    // Und zurück zur Vorgabe.
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    mTarget := mLoaded;
    mPage.SaveTo(mTarget);
    Assert.IsTrue(mTarget.Enabled, 'Enabled Vorgabe');
    Assert.AreEqual(TDpccPluginSettings.Defaults.AutoMinChars, mTarget.AutoMinChars, 'AutoMinChars Vorgabe');
    Assert.AreEqual(TDpccPluginSettings.Defaults.VisibleRows, mTarget.VisibleRows, 'VisibleRows Vorgabe');
    Assert.AreEqual(TDpccPluginSettings.Defaults.CompletionListMode, mTarget.CompletionListMode, 'Listenmodus');
    Assert.AreEqual(0, mTarget.ListWidth, 'ListWidth automatisch');
    Assert.AreEqual('', mTarget.IndexExtraSourceFolders, 'Quellordner leer');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.AutoWidthKeepsDraggedWidth;
var
  mPage: TDpccSettingsPage;
  mSettings: TDpccPluginSettings;
begin
  mPage := TDpccSettingsPage.Create(nil);
  try
    mSettings := TDpccPluginSettings.Defaults;
    mSettings.ListWidth := 420;
    mPage.LoadFrom(mSettings);
    mPage.AutoWidth.Checked := True;
    mPage.SaveTo(mSettings);
    Assert.AreEqual(0, mSettings.ListWidth, 'automatisch');
    mPage.AutoWidth.Checked := False;
    mPage.SaveTo(mSettings);
    Assert.AreEqual(420, mSettings.ListWidth, 'gezogene Breite');
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    Assert.IsTrue(mPage.AutoWidth.Checked, 'Vorgabe automatisch');
    mPage.AutoWidth.Checked := False;
    mPage.SaveTo(mSettings);
    Assert.AreEqual(TDpccPluginSettings.cMinListWidth + 160, mSettings.ListWidth, 'mittlere Breite');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.ResetHistoryButton;
var
  mPage: TDpccSettingsPage;
  mCalls: Integer;
begin
  mCalls := 0;
  mPage := TDpccSettingsPage.Create(nil);
  try
    mPage.OnResetHistory :=
      procedure
      begin
        Inc(mCalls);
      end;
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    Assert.IsTrue(mPage.ResetHistory.Enabled, 'bereit');
    mPage.ResetHistory.Click;
    Assert.AreEqual(1, mCalls, 'Aufrufe');
    Assert.IsFalse(mPage.ResetHistory.Enabled, 'nach dem Klick grau');
    // Auch Hauptschalter aus und wieder an gibt ihn nicht frei.
    mPage.MasterSwitch.Checked := False;
    mPage.MasterSwitch.Checked := True;
    Assert.IsFalse(mPage.ResetHistory.Enabled, 'bleibt grau');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.RebuildIndexButton;
var
  mPage: TDpccSettingsPage;
  mCalls: Integer;
  mConfirm: Boolean;
begin
  mCalls := 0;
  mConfirm := False;
  mPage := TDpccSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    Assert.IsFalse(mPage.Rebuild.Enabled, 'ohne Haken grau');
    mPage.ConfirmRebuild :=
      function: Boolean
      begin
        Result := mConfirm;
      end;
    mPage.OnRebuildIndex :=
      function: string
      begin
        Inc(mCalls);
        Result := 'neu aufgebaut';
      end;
    Assert.IsTrue(mPage.Rebuild.Enabled, 'mit Haken bereit');
    mPage.Rebuild.Click;
    Assert.AreEqual(0, mCalls, 'Rückfrage Nein');
    Assert.AreEqual('', mPage.RebuildInfo.Caption, 'keine Meldung');
    mConfirm := True;
    mPage.Rebuild.Click;
    Assert.AreEqual(1, mCalls, 'Rückfrage Ja');
    Assert.AreEqual('neu aufgebaut', mPage.RebuildInfo.Caption, 'Meldung');
    // Hängt nicht am Hauptschalter (wie bisher).
    mPage.MasterSwitch.Checked := False;
    Assert.IsTrue(mPage.Rebuild.Enabled, 'Hauptschalter aus');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.RebuildIndexRunningState;
var
  mPage: TDpccSettingsPage;
  mCalls: Integer;
  mStatus: TDpccRebuildStatus;
begin
  mCalls := 0;
  mStatus := Default(TDpccRebuildStatus);
  mPage := TDpccSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    mPage.ConfirmRebuild :=
      function: Boolean
      begin
        Result := True;
      end;
    mPage.OnRebuildIndex :=
      function: string
      begin
        Inc(mCalls);
        mStatus.Running := True;
        mStatus.Text := 'running';
        Result := 'started';
      end;
    mPage.OnRebuildStatus :=
      function: TDpccRebuildStatus
      begin
        Result := mStatus;
      end;
    Assert.IsTrue(mPage.Rebuild.Enabled, 'bereit');
    mPage.Rebuild.Click;
    Assert.AreEqual(1, mCalls, 'angestoßen');
    Assert.IsFalse(mPage.Rebuild.Enabled, 'läuft: grau');
    Assert.AreEqual('running', mPage.RebuildInfo.Caption, 'Meldung während des Laufs');
    mPage.Rebuild.Click;
    Assert.AreEqual(1, mCalls, 'zweiter Klick tut nichts');
    // Abschluss im Hintergrund; die Seite sieht ihn bei der nächsten Abfrage (Timer).
    mStatus.Running := False;
    mStatus.Text := 'done';
    mPage.RefreshRebuild;
    Assert.IsTrue(mPage.Rebuild.Enabled, 'wieder frei');
    Assert.AreEqual('done', mPage.RebuildInfo.Caption, 'Meldung nach dem Abschluss');
  finally
    mPage.Free;
  end;
  // Seite neu geöffnet, während ein Neuaufbau läuft: sofort grau.
  mStatus.Running := True;
  mStatus.Text := 'running';
  mPage := TDpccSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    mPage.OnRebuildIndex :=
      function: string
      begin
        Result := '';
      end;
    mPage.OnRebuildStatus :=
      function: TDpccRebuildStatus
      begin
        Result := mStatus;
      end;
    Assert.IsFalse(mPage.Rebuild.Enabled, 'neu geöffnet: grau');
    Assert.AreEqual('running', mPage.RebuildInfo.Caption, 'neu geöffnet: Meldung');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.RebuildIndexRejected;
var
  mPage: TDpccSettingsPage;
  mCalls: Integer;
  mStatus: TDpccRebuildStatus;
begin
  mCalls := 0;
  mStatus := Default(TDpccRebuildStatus);
  mPage := TDpccSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    mPage.ConfirmRebuild :=
      function: Boolean
      begin
        Result := True;
      end;
    // Wie TDpccPageOptions nach der Ablehnung: läuft nicht, Zustand und Antwort mit eigenem Text statt „läuft …“.
    mPage.OnRebuildIndex :=
      function: string
      begin
        Inc(mCalls);
        mStatus.Running := False;
        mStatus.Text := 'rejected';
        Result := mStatus.Text;
      end;
    mPage.OnRebuildStatus :=
      function: TDpccRebuildStatus
      begin
        Result := mStatus;
      end;
    mPage.Rebuild.Click;
    Assert.AreEqual(1, mCalls, 'angestoßen');
    Assert.IsTrue(mPage.Rebuild.Enabled, 'abgelehnt: Knopf frei');
    Assert.AreEqual('rejected', mPage.RebuildInfo.Caption, 'abgelehnt: Meldung');
    // Nächste Abfrage (Timer) ändert nichts mehr.
    mPage.RefreshRebuild;
    Assert.IsTrue(mPage.Rebuild.Enabled, 'bleibt frei');
    Assert.AreEqual('rejected', mPage.RebuildInfo.Caption, 'bleibt ohne „läuft …“');
    mPage.Rebuild.Click;
    Assert.AreEqual(2, mCalls, 'erneut möglich');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.CheckIdeButton;
var
  mPage: TDpccSettingsPage;
  mCalls: Integer;
begin
  mCalls := 0;
  mPage := TDpccSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    Assert.IsFalse(mPage.CheckIde.Enabled, 'ohne Haken grau');
    Assert.AreEqual('', mPage.IdeStatus.Caption, 'ohne Haken keine Zeilen');
    mPage.OnIdeStatus :=
      function: string
      begin
        Inc(mCalls);
        Result := 'Betriebsart dpcc' + sLineBreak + 'Lauf ' + IntToStr(mCalls);
      end;
    Assert.IsTrue(mPage.CheckIde.Enabled, 'mit Haken bereit');
    Assert.AreEqual(1, mCalls, 'beim Setzen gelesen');
    Assert.AreEqual('Betriebsart dpcc' + sLineBreak + 'Lauf 1', mPage.IdeStatus.Caption, 'Statuszeilen');
    mPage.CheckIde.Click;
    Assert.AreEqual(2, mCalls, 'Jetzt prüfen liest neu');
    Assert.IsTrue(EndsText('Lauf 2', mPage.IdeStatus.Caption), 'neue Zeilen');
    // Hängt nicht am Hauptschalter (wie „Index neu aufbauen“).
    mPage.MasterSwitch.Checked := False;
    Assert.IsTrue(mPage.CheckIde.Enabled, 'Hauptschalter aus');
    mPage.OnIdeStatus := nil;
    Assert.IsFalse(mPage.CheckIde.Enabled, 'Haken entfernt');
    Assert.AreEqual('', mPage.IdeStatus.Caption, 'Zeilen geleert');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.LabelsDoNotOverlapFields(AEnglish: Boolean);
var
  mPage: TDpccSettingsPage;
  mEntry: TDpccSettingsPageEntry;
  mLeft: TControl;
  mRight: Integer;
begin
  if AEnglish then
  begin
    TDpccStrings.Language := High(TDpccLanguage);
  end
  else
  begin
    TDpccStrings.Language := Low(TDpccLanguage);
  end;
  mPage := TDpccSettingsPage.Create(nil);
  try
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    Assert.IsTrue(AEnglish = StartsText('Code Insight by', mPage.MasterSwitch.Caption), 'Sprache');
    for mEntry in mPage.Entries do
    begin
      // Beschriftung links neben dem Feld: endet vor dem Feld.
      if (mEntry.Caption <> nil) and (mEntry.Caption.Parent = mEntry.Control.Parent) then
      begin
        mRight := mEntry.Caption.Left + mPage.TextWidthFor(mEntry.Caption, mEntry.Caption.Caption);
        Assert.IsTrue(mRight < mEntry.Control.Left, Format('%s: Beschriftung bis %d, Feld ab %d',
          [mEntry.Item.Name, mRight, mEntry.Control.Left]));
      end;
      // Kontrollkästchen fassen ihren Text.
      if mEntry.Control is TCheckBox then
      begin
        Assert.IsTrue(mEntry.Control.Width > mPage.TextWidthFor(mEntry.Control, TCheckBox(mEntry.Control).Caption),
          mEntry.Item.Name + ': Breite');
      end;
    end;
    // Elemente in derselben Zeile überlappen nicht.
    mLeft := mPage.ControlOf('VisibleRows');
    Assert.IsTrue(mPage.AutoWidth.Left >= mLeft.Left + mLeft.Width, 'Breite automatisch neben den Zeilen');
    mLeft := mPage.ControlOf('Learning');
    Assert.IsTrue(mPage.ResetHistory.Left >= mLeft.Left + mLeft.Width, 'Verlauf zurücksetzen neben dem Lernen');
    Assert.IsTrue(mPage.ResetHistory.Width > mPage.TextWidthFor(mPage.ResetHistory, mPage.ResetHistory.Caption),
      'Knopf fasst Text');
    Assert.IsTrue(mPage.Rebuild.Width > mPage.TextWidthFor(mPage.Rebuild, mPage.Rebuild.Caption), 'Knopf fasst Text');
    Assert.IsTrue(mPage.CheckIde.Width > mPage.TextWidthFor(mPage.CheckIde, mPage.CheckIde.Caption),
      'Jetzt prüfen fasst Text');
    Assert.IsTrue(mPage.IdeStatus.Left >= mPage.CheckIde.Left + mPage.CheckIde.Width, 'Statuszeilen neben dem Knopf');
    // Gleiche Einrückung der Optionen; „Werte beim Debuggen“ tiefer als „Eigener Tooltip“.
    Assert.AreEqual(mPage.ControlOf('AutoParentheses').Left, mPage.ControlOf('ParameterHints').Left, 'Einrückung');
    Assert.AreEqual(mPage.ControlOf('Learning').Left, mPage.ControlOf('HoverTooltip').Left, 'Einrückung');
    Assert.IsTrue(mPage.DebugHoverValues.Left > mPage.HoverTooltip.Left, 'Unterpunkt eingerückt');
    Assert.IsTrue(mPage.ControlOf('AutoParentheses').Left > mPage.MasterSwitch.Left, 'unter der Überschrift');
    // Passt ohne Rollen in einen Bereich üblicher Größe (bei 96 dpi etwa 580 Punkte hoch und 520 breit; seit IDECHECK
    // mit dem Abschnitt IDE, vorher 500).
    Assert.IsTrue(mPage.Height <= mPage.ScaleValue(580), 'Höhe ' + IntToStr(mPage.Height));
    Assert.IsTrue(mPage.ResetHistory.Left + mPage.ResetHistory.Width <= mPage.ScaleValue(520),
      'Breite der Lernen-Zeile ' + IntToStr(mPage.ResetHistory.Left + mPage.ResetHistory.Width));
  finally
    mPage.Free;
    TDpccStrings.Language := Low(TDpccLanguage);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccSettingsPageTests);

end.
