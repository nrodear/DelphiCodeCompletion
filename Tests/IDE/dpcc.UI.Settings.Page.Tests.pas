unit dpcc.UI.Settings.Page.Tests;

// Tests für die eine Seite „dpcc“ unter Tools › Optionen › Fremdhersteller (OPT1, dpcc.UI.Settings.Page). Die Seite
// wird ohne IDE und ohne Fenster erzeugt (wie die IDE sie vor dem Einhängen erzeugt) und an ihren Elementen geprüft:
// genau Hauptschalter, zwölf Optionen und zwei Knöpfe in Reihenfolge und Abschnitten, Sperre durch den Hauptschalter,
// Kopplung „Eigener Tooltip“ → „Werte beim Debuggen“, Laden und Speichern über TDpccPluginSettings, die Knöpfe und
// das Layout (keine Beschriftung ragt in ein Feld, deutsch und englisch; passt ohne Rollen). Seit IDECHECK zuletzt der
// Abschnitt IDE mit „Jetzt prüfen“ und den Statuszeilen (OnIdeStatus). Seit LOOK1 dreizehn Optionen: zuletzt im
// Abschnitt Parameter-Hint und Tooltip die Auswahl „Darstellung der Popups“ (Intensiv, Dezent, Unscheinbar). Seit LOG1
// vierzehn Optionen: zuletzt im Abschnitt IDE das Häkchen „Ablauf protokollieren (Log)“ (Diagnose), nicht am
// Hauptschalter, mit der Protokolldatei im Hint. Seit CI-OPT sechzehn Optionen: im Abschnitt Vervollständigung zuerst
// „Nach dem Punkt automatisch öffnen“ und vor dem Lernen „Reservierte Wörter in der Liste zeigen“, je mit Hint.

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
    /// <summary>Genau Hauptschalter, (seit CI-OPT) sechzehn Optionen und drei Knöpfe, in der Reihenfolge der Seite und
    /// unter der richtigen Überschrift; fünf Überschriften in Großbuchstaben.</summary>
    [Test]
    procedure PageHasSixteenOptionsAndThreeButtonsInSections;
    /// <summary>CI-OPT: „Nach dem Punkt automatisch öffnen“ und „Reservierte Wörter in der Liste zeigen“ (englisch
    /// „Open automatically after the dot“, „Show reserved words in the list“) als Häkchen im Abschnitt
    /// Vervollständigung; Vorgabe an; Hint sagt, ab wann sie wirken; geladen und gespeichert über OpenAfterDot und
    /// ShowKeywords; grau außerhalb der Betriebsart Plugin.</summary>
    [Test]
    [TestCase('Deutsch', 'False')]
    [TestCase('Englisch', 'True')]
    procedure CompletionSwitchesCheckBoxes(AEnglish: Boolean);
    /// <summary>LOG1: „Ablauf protokollieren (Log)“ (englisch „Log the flow (log file)“) als Häkchen zuletzt im
    /// Abschnitt IDE; Vorgabe aus, geladen und gespeichert über TDpccPluginSettings.Diagnose; hängt nicht am
    /// Hauptschalter; der Hint nennt die Datei, sobald die IDE-Schicht sie setzt.</summary>
    [Test]
    [TestCase('Deutsch', 'False')]
    [TestCase('Englisch', 'True')]
    procedure DiagnoseCheckBox(AEnglish: Boolean);
    /// <summary>LOOK1: „Darstellung der Popups“ ist eine Auswahl mit Intensiv, Dezent, Unscheinbar (englisch Intense,
    /// Subtle, Plain), zuletzt im Abschnitt Parameter-Hint und Tooltip; Vorgabe Dezent; jede Stufe geladen und
    /// gespeichert; ohne Auswahl bleibt der bisherige Wert.</summary>
    [Test]
    [TestCase('Deutsch', 'False')]
    [TestCase('Englisch', 'True')]
    procedure PopupLookChoice(AEnglish: Boolean);
    /// <summary>Hauptschalter aus: alle Optionen und „Verlauf zurücksetzen“ grau, „Index neu aufbauen“ nicht.
    /// </summary>
    [Test]
    procedure MasterSwitchLocksAllOptions;
    /// <summary>Betriebsart (Stufe 2 von dpcc.LspServer.exe): drei Optionsfelder Aus, Plugin, Server in einer Gruppe,
    /// je mit Satz darunter (deutsch und englisch); Vorgabe Plugin; nur Plugin gibt die Optionen frei; ohne
    /// dpcc.LspServer.exe ist Server grau mit Hinweis, mit ihr wählbar samt Ort im Hint; geladen und gespeichert über
    /// TDpccPluginSettings.Mode.</summary>
    [Test]
    [TestCase('Deutsch', 'False')]
    [TestCase('Englisch', 'True')]
    procedure OperatingModeChoice(AEnglish: Boolean);
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
    /// <summary>Fehler 4c: Die gedämpften Sätze (Betriebsart, „Index neu aufbauen“, Abschnitt IDE) behalten die Schrift
    /// des Dialogs (ParentFont): Früher setzte Font.Color eine eigene Schrift, die bei 120 dpi zu groß war.</summary>
    [Test]
    procedure InfoLabelsUseDialogFont;
    /// <summary>Fehler 4b: Die Zeile des Abschnitts IDE wächst mit den Statuszeilen; nichts wird abgeschnitten
    /// (früher fest 64 Punkte).</summary>
    [Test]
    procedure IdeStatusRowGrowsWithLines;
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
  dpcc.Core.Settings.OperatingMode,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.UI.Settings.Page,
  dpcc.Core.Style.Look;

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

procedure TDpccSettingsPageTests.PageHasSixteenOptionsAndThreeButtonsInSections;
const
  cNames: array[0..19] of string = ('OperatingMode', 'OpenAfterDot', 'AutoMinChars', 'CompletionListMode',
    'VisibleRows', 'ListWidth', 'CompletionKeywords', 'Learning', 'ResetHistory', 'AutoParentheses',
    'CommitCharacters', 'AutoUses', 'ParameterHints', 'HoverTooltip', 'DebugHoverValues', 'PopupLook',
    'IndexExtraSourceFolders', 'RebuildIndex', 'CheckIde', 'Diagnose');
  cSections: array[0..19] of TDpccPageSection = (psMaster, psCompletion, psCompletion, psCompletion, psCompletion,
    psCompletion, psCompletion, psCompletion, psCompletion, psCommit, psCommit, psCommit, psHints, psHints, psHints,
    psHints, psIndex, psIndex, psIde, psIde);
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
    Assert.AreEqual(16, mOptions, 'Optionen');
    Assert.AreEqual(3, mButtons, 'Knöpfe');
    // Art der Elemente.
    Assert.IsTrue(mPage.ControlOf('OperatingMode') = mPage.ModeButton[TDpccOperatingMode.Plugin], 'Betriebsart');
    Assert.IsTrue(mPage.ControlOf('OpenAfterDot') = mPage.OpenAfterDot, 'Nach dem Punkt');
    Assert.IsTrue(mPage.ControlOf('CompletionKeywords') = mPage.Keywords, 'Reservierte Wörter');
    Assert.IsTrue(mPage.ControlOf('Diagnose') = mPage.DiagnoseLog, 'Ablauf protokollieren');
    Assert.IsTrue(mPage.ControlOf('PopupLook') = mPage.PopupLookChoice, 'Darstellung der Popups');
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
    mSettings.Mode := TDpccOperatingMode.Off;
    mPage.LoadFrom(mSettings);
    for mEntry in mPage.Entries do
    begin
      // Seit LOG1 bleibt auch „Ablauf protokollieren (Log)“ bedienbar.
      if (mEntry.Item.Name = 'OperatingMode') or (mEntry.Item.Name = cPageRebuildIndex) or
        (mEntry.Item.Name = cPageCheckIde) or (mEntry.Item.Name = 'Diagnose') then
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
    mPage.Mode := TDpccOperatingMode.Plugin;
    for mEntry in mPage.Entries do
    begin
      Assert.IsTrue(mEntry.Control.Enabled, mEntry.Item.Name + ' wieder an');
    end;
    mPage.Mode := TDpccOperatingMode.Off;
    Assert.IsFalse(mPage.ControlOf('IndexExtraSourceFolders').Enabled, 'Quellordner nach Klick grau');
    Assert.IsFalse(mPage.ResetHistory.Enabled, 'Verlauf zurücksetzen nach Klick grau');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.OperatingModeChoice(AEnglish: Boolean);
const
  cCaptions: array[Boolean, TDpccOperatingMode] of string = (('Aus', 'Plugin', 'Server'), ('Off', 'Plugin', 'Server'));
var
  mPage: TDpccSettingsPage;
  mMode, mOther: TDpccOperatingMode;
  mSettings: TDpccPluginSettings;
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
    // Vorgabe nach der Installation: Plugin.
    Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(mPage.Mode), 'Vorgabe');
    for mMode := Low(TDpccOperatingMode) to High(TDpccOperatingMode) do
    begin
      Assert.IsTrue(StartsText(cCaptions[AEnglish, mMode] + ' – ', mPage.ModeButton[mMode].Caption),
        'Beschriftung: ' + mPage.ModeButton[mMode].Caption);
      // Eine Gruppe: alle in derselben Zeile.
      Assert.IsTrue(mPage.ModeButton[mMode].Parent = mPage.ModeButton[TDpccOperatingMode.Plugin].Parent, 'Gruppe');
      if mMode > Low(TDpccOperatingMode) then
      begin
        Assert.IsTrue(mPage.ModeButton[mMode].Top > mPage.ModeButton[Pred(mMode)].Top, 'untereinander');
      end;
    end;
    // Ohne dpcc.LspServer.exe: Server grau, Hinweis sichtbar und unter Server.
    Assert.IsFalse(mPage.ModeButton[TDpccOperatingMode.Server].Enabled, 'Server ohne EXE grau');
    Assert.IsTrue(mPage.ServerMissing.Visible, 'Hinweis ohne EXE');
    Assert.IsTrue(ContainsText(mPage.ServerMissing.Caption, 'dpcc.LspServer.exe'), mPage.ServerMissing.Caption);
    Assert.IsTrue(mPage.ServerMissing.Top > mPage.ModeButton[TDpccOperatingMode.Server].Top, 'Hinweis unter Server');
    // Mit EXE: wählbar, Hint mit dem Ort, kein Hinweis.
    mPage.ServerExe := 'X:\dpcc\server\win64\dpcc.LspServer.exe';
    Assert.IsTrue(mPage.ModeButton[TDpccOperatingMode.Server].Enabled, 'Server mit EXE');
    Assert.IsFalse(mPage.ServerMissing.Visible, 'kein Hinweis');
    Assert.IsTrue(ContainsText(mPage.ModeButton[TDpccOperatingMode.Server].Hint,
      'X:\dpcc\server\win64\dpcc.LspServer.exe'), 'Ort im Hint');
    // Nur Plugin gibt die Optionen frei; jede Art geladen und gespeichert.
    for mMode := Low(TDpccOperatingMode) to High(TDpccOperatingMode) do
    begin
      mSettings := TDpccPluginSettings.Defaults;
      mSettings.Mode := mMode;
      mPage.LoadFrom(mSettings);
      Assert.AreEqual(Ord(mMode), Ord(mPage.Mode), 'geladen');
      for mOther := Low(TDpccOperatingMode) to High(TDpccOperatingMode) do
      begin
        Assert.IsTrue((mOther = mMode) = mPage.ModeButton[mOther].Checked, 'genau eine gewählt');
      end;
      Assert.IsTrue((mMode = TDpccOperatingMode.Plugin) = mPage.ControlOf('AutoParentheses').Enabled,
        'Optionen nur mit Plugin');
      Assert.IsTrue(mPage.CheckIde.Enabled or not Assigned(mPage.OnIdeStatus), 'Jetzt prüfen unabhängig');
      Assert.IsTrue(mPage.DiagnoseLog.Enabled, 'Ablauf protokollieren unabhängig');
      mSettings := TDpccPluginSettings.Defaults;
      mPage.SaveTo(mSettings);
      Assert.AreEqual(Ord(mMode), Ord(mSettings.Mode), 'gespeichert');
      Assert.IsTrue((mMode = TDpccOperatingMode.Plugin) = mSettings.Enabled, 'Enabled abgeleitet');
    end;
    // Gespeichertes Server ohne EXE bleibt sichtbar gewählt (nicht still verloren).
    mPage.ServerExe := '';
    mSettings := TDpccPluginSettings.Defaults;
    mSettings.Mode := TDpccOperatingMode.Server;
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(mPage.ModeButton[TDpccOperatingMode.Server].Checked, 'Server bleibt gewählt');
    Assert.IsTrue(mPage.ModeButton[TDpccOperatingMode.Server].Enabled, 'gewählt bleibt bedienbar');
    Assert.IsTrue(mPage.ServerMissing.Visible, 'mit Hinweis');
  finally
    mPage.Free;
    TDpccStrings.Language := Low(TDpccLanguage);
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
    mPage.Mode := TDpccOperatingMode.Off;
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
  mLoaded.Mode := TDpccOperatingMode.Server;
  mLoaded.OpenAfterDot := False;
  mLoaded.ShowKeywords := False;
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
  mLoaded.PopupLook := TDpccLookLevel.Plain;
  mLoaded.IndexExtraSourceFolders := 'C:\A;C:\B';
  mLoaded.Diagnose := True;
  mPage := TDpccSettingsPage.Create(nil);
  try
    mPage.LoadFrom(mLoaded);
    Assert.IsTrue(mPage.DiagnoseLog.Checked, 'Ablauf protokollieren');
    Assert.IsFalse(mPage.OpenAfterDot.Checked, 'Nach dem Punkt');
    Assert.IsFalse(mPage.Keywords.Checked, 'Reservierte Wörter');
    Assert.AreEqual(4, mPage.AutoMinCharsChoice.Choice, 'Auswahl ab Zeichen');
    Assert.AreEqual(Ord(TDpccLookLevel.Plain), mPage.PopupLookChoice.Choice, 'Darstellung der Popups');
    Assert.AreEqual(13 - TDpccPluginSettings.cMinVisibleRows, mPage.VisibleRowsChoice.Choice, 'Auswahl Zeilen');
    Assert.AreEqual(2, mPage.ListModeChoice.Choice, 'Listenmodus');
    Assert.IsFalse(mPage.AutoWidth.Checked, 'Breite automatisch');
    // Gespeichert in die Vorgabe mit abweichenden Werten, die die Seite nicht zeigt (seit OPT2 nur noch die nur
    // gelesenen): Die bleiben.
    mTarget := TDpccPluginSettings.Defaults;
    mTarget.XmlDocMaxLines := 9;
    mTarget.LogNames := True;
    mPage.SaveTo(mTarget);
    Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(mTarget.Mode), 'Betriebsart');
    Assert.IsFalse(mTarget.Enabled, 'Enabled');
    Assert.IsFalse(mTarget.OpenAfterDot, 'OpenAfterDot');
    Assert.IsFalse(mTarget.ShowKeywords, 'ShowKeywords');
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
    Assert.AreEqual(Ord(TDpccLookLevel.Plain), Ord(mTarget.PopupLook), 'PopupLook');
    Assert.AreEqual('C:\A;C:\B', mTarget.IndexExtraSourceFolders, 'IndexExtraSourceFolders');
    Assert.IsTrue(mTarget.Diagnose, 'Diagnose');
    Assert.AreEqual(9, mTarget.XmlDocMaxLines, 'XmlDocMaxLines bleibt');
    Assert.IsTrue(mTarget.LogNames, 'LogNames bleibt');
    // Und zurück zur Vorgabe.
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    mTarget := mLoaded;
    mPage.SaveTo(mTarget);
    Assert.IsTrue(mTarget.Enabled, 'Enabled Vorgabe');
    Assert.IsTrue(mTarget.OpenAfterDot and mTarget.ShowKeywords, 'Vorgabe der beiden Schalter an');
    Assert.AreEqual(TDpccPluginSettings.Defaults.AutoMinChars, mTarget.AutoMinChars, 'AutoMinChars Vorgabe');
    Assert.AreEqual(TDpccPluginSettings.Defaults.VisibleRows, mTarget.VisibleRows, 'VisibleRows Vorgabe');
    Assert.AreEqual(TDpccPluginSettings.Defaults.CompletionListMode, mTarget.CompletionListMode, 'Listenmodus');
    Assert.AreEqual(Ord(cDpccLookLevelDefault), Ord(mTarget.PopupLook), 'PopupLook Vorgabe');
    Assert.AreEqual(0, mTarget.ListWidth, 'ListWidth automatisch');
    Assert.AreEqual('', mTarget.IndexExtraSourceFolders, 'Quellordner leer');
    Assert.IsFalse(mTarget.Diagnose, 'Diagnose Vorgabe aus');
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
    mPage.Mode := TDpccOperatingMode.Off;
    mPage.Mode := TDpccOperatingMode.Plugin;
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
    mPage.Mode := TDpccOperatingMode.Off;
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
    mPage.Mode := TDpccOperatingMode.Off;
    Assert.IsTrue(mPage.CheckIde.Enabled, 'Hauptschalter aus');
    mPage.OnIdeStatus := nil;
    Assert.IsFalse(mPage.CheckIde.Enabled, 'Haken entfernt');
    Assert.AreEqual('', mPage.IdeStatus.Caption, 'Zeilen geleert');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.PopupLookChoice(AEnglish: Boolean);
const
  cGerman: array[TDpccLookLevel] of string = ('Intensiv', 'Dezent', 'Unscheinbar');
  cEnglish: array[TDpccLookLevel] of string = ('Intense', 'Subtle', 'Plain');
var
  mPage: TDpccSettingsPage;
  mEntry: TDpccSettingsPageEntry;
  mIndex, mLookIndex: Integer;
  mLevel: TDpccLookLevel;
  mSettings: TDpccPluginSettings;
  mChoices: TArray<string>;
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
    // Lage: letzte Option im Abschnitt Parameter-Hint und Tooltip, direkt danach beginnt der Abschnitt Index.
    mLookIndex := -1;
    for mIndex := 0 to High(mPage.Entries) do
    begin
      if mPage.Entries[mIndex].Item.Name = 'PopupLook' then
      begin
        mLookIndex := mIndex;
      end;
    end;
    Assert.IsTrue((mLookIndex > 0) and (mLookIndex < High(mPage.Entries)), 'Zeile vorhanden');
    mEntry := mPage.Entries[mLookIndex];
    Assert.AreEqual(Ord(psHints), Ord(mEntry.Item.Section), 'Abschnitt');
    Assert.AreEqual('DebugHoverValues', mPage.Entries[mLookIndex - 1].Item.Name, 'davor');
    Assert.AreEqual(Ord(psIndex), Ord(mPage.Entries[mLookIndex + 1].Item.Section), 'danach der Abschnitt Index');
    // Gebaut wie „Beim Tippen zeigen“: Beschriftung links in derselben Zeile, Auswahl in der Spalte der Felder.
    Assert.IsTrue(mEntry.Control = mPage.PopupLookChoice, 'Auswahl');
    Assert.IsNotNull(mEntry.Caption, 'Beschriftung');
    Assert.IsTrue(mEntry.Caption.Parent = mEntry.Control.Parent, 'Beschriftung in derselben Zeile');
    Assert.IsTrue(mEntry.Caption.FocusControl = mEntry.Control, 'Beschriftung führt zur Auswahl');
    Assert.AreEqual(mPage.ListModeChoice.Left, mEntry.Control.Left, 'Spalte der Felder');
    // Texte in der Reihenfolge von TDpccLookLevel.
    mChoices := mPage.PopupLookChoice.Choices;
    Assert.AreEqual(3, Integer(Length(mChoices)), 'Einträge');
    if AEnglish then
    begin
      Assert.AreEqual('Popup appearance:', mEntry.Caption.Caption, 'Beschriftung');
    end
    else
    begin
      Assert.AreEqual('Darstellung der Popups:', mEntry.Caption.Caption, 'Beschriftung');
    end;
    for mLevel := Low(TDpccLookLevel) to High(TDpccLookLevel) do
    begin
      if AEnglish then
      begin
        Assert.AreEqual(cEnglish[mLevel], mChoices[Ord(mLevel)], 'Eintrag ' + cEnglish[mLevel]);
      end
      else
      begin
        Assert.AreEqual(cGerman[mLevel], mChoices[Ord(mLevel)], 'Eintrag ' + cGerman[mLevel]);
      end;
    end;
    // Vorgabe: Dezent.
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    Assert.AreEqual(Ord(TDpccLookLevel.Subtle), mPage.PopupLookChoice.Choice, 'Vorgabe');
    // Jede Stufe auf die Seite und zurück in die Einstellungen.
    for mLevel := Low(TDpccLookLevel) to High(TDpccLookLevel) do
    begin
      mSettings := TDpccPluginSettings.Defaults;
      mSettings.PopupLook := mLevel;
      mPage.LoadFrom(mSettings);
      Assert.AreEqual(Integer(Ord(mLevel)), mPage.PopupLookChoice.Choice, 'geladen ' + cEnglish[mLevel]);
      mSettings := TDpccPluginSettings.Defaults;
      mPage.SaveTo(mSettings);
      Assert.AreEqual(Ord(mLevel), Ord(mSettings.PopupLook), 'gespeichert ' + cEnglish[mLevel]);
    end;
    // Auf der Seite gewählt.
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    mPage.PopupLookChoice.Choice := Ord(TDpccLookLevel.Intense);
    mSettings := TDpccPluginSettings.Defaults;
    mPage.SaveTo(mSettings);
    Assert.AreEqual(Ord(TDpccLookLevel.Intense), Ord(mSettings.PopupLook), 'auf der Seite gewählt');
    // Ohne Auswahl bleibt der bisherige Wert.
    mPage.PopupLookChoice.Choice := -1;
    mSettings := TDpccPluginSettings.Defaults;
    mSettings.PopupLook := TDpccLookLevel.Plain;
    mPage.SaveTo(mSettings);
    Assert.AreEqual(Ord(TDpccLookLevel.Plain), Ord(mSettings.PopupLook), 'ohne Auswahl');
    // Hängt am Hauptschalter wie alle Optionen.
    mPage.Mode := TDpccOperatingMode.Off;
    Assert.IsFalse(mPage.PopupLookChoice.Enabled, 'Hauptschalter aus');
    Assert.IsFalse(mEntry.Caption.Enabled, 'Beschriftung grau');
  finally
    mPage.Free;
    TDpccStrings.Language := Low(TDpccLanguage);
  end;
end;

procedure TDpccSettingsPageTests.DiagnoseCheckBox(AEnglish: Boolean);
var
  mPage: TDpccSettingsPage;
  mSettings: TDpccPluginSettings;
  mLast: TDpccSettingsPageEntry;
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
    // Lage: letztes Element der Seite, eine Einstellung im Abschnitt IDE, unter der Zeile von „Jetzt prüfen“.
    mLast := mPage.Entries[High(mPage.Entries)];
    Assert.AreEqual('Diagnose', mLast.Item.Name, 'letztes Element');
    Assert.AreEqual(Ord(psIde), Ord(mLast.Item.Section), 'Abschnitt IDE');
    Assert.IsTrue(mLast.Control = mPage.DiagnoseLog, 'Häkchen');
    Assert.IsTrue(mPage.DiagnoseLog.Parent.Top > mPage.CheckIde.Parent.Top, 'unter „Jetzt prüfen“');
    if AEnglish then
    begin
      Assert.AreEqual('Log the flow (log file)', mPage.DiagnoseLog.Caption, 'Beschriftung');
    end
    else
    begin
      Assert.AreEqual('Ablauf protokollieren (Log)', mPage.DiagnoseLog.Caption, 'Beschriftung');
    end;
    // Hint: ohne Datei der allgemeine Text, mit Datei zusätzlich die Zeile mit der Datei.
    Assert.IsTrue(mPage.DiagnoseLog.ShowHint, 'Hint an');
    Assert.IsTrue(mPage.DiagnoseLog.Hint <> '', 'Hint ohne Datei');
    Assert.IsFalse(ContainsText(mPage.DiagnoseLog.Hint, 'dpcc.IDE.Expert370.log'), 'noch keine Datei');
    mPage.DiagnoseFile := 'X:\Bpl\dpcc.IDE.Expert370.log';
    Assert.IsTrue(ContainsText(mPage.DiagnoseLog.Hint, 'X:\Bpl\dpcc.IDE.Expert370.log'), 'Datei im Hint');
    Assert.AreEqual('X:\Bpl\dpcc.IDE.Expert370.log', mPage.DiagnoseFile, 'Datei gemerkt');
    // Vorgabe aus; geladen und gespeichert über Diagnose.
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    Assert.IsFalse(mPage.DiagnoseLog.Checked, 'Vorgabe aus');
    mSettings := TDpccPluginSettings.Defaults;
    mSettings.Diagnose := True;
    mPage.LoadFrom(mSettings);
    Assert.IsTrue(mPage.DiagnoseLog.Checked, 'geladen an');
    mPage.DiagnoseLog.Checked := False;
    mPage.SaveTo(mSettings);
    Assert.IsFalse(mSettings.Diagnose, 'auf der Seite ausgeschaltet');
    mPage.DiagnoseLog.Checked := True;
    mPage.SaveTo(mSettings);
    Assert.IsTrue(mSettings.Diagnose, 'auf der Seite eingeschaltet');
    // Hängt nicht am Hauptschalter: Das Protokoll zeigt gerade dann, warum dpcc nicht zuständig ist.
    mPage.Mode := TDpccOperatingMode.Off;
    Assert.IsTrue(mPage.DiagnoseLog.Enabled, 'Hauptschalter aus');
  finally
    mPage.Free;
    TDpccStrings.Language := Low(TDpccLanguage);
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
    Assert.IsTrue(AEnglish = StartsText('Off', mPage.ModeButton[TDpccOperatingMode.Off].Caption), 'Sprache');
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
    Assert.IsTrue(mPage.ControlOf('AutoParentheses').Left > mPage.ModeButton[TDpccOperatingMode.Off].Left,
      'unter der Überschrift');
    // Passt ohne Rollen in einen Bereich üblicher Größe (bei 96 dpi etwa 640 Punkte hoch und 520 breit; seit IDECHECK
    // mit dem Abschnitt IDE, vorher 500; seit LOOK1 mit der Zeile „Darstellung der Popups“, vorher 580; seit LOG1 mit
    // der Zeile „Ablauf protokollieren (Log)“, vorher 610; seit der Betriebsart mit drei Optionsfeldern samt
    // erklärenden Sätzen und dem Hinweis zur fehlenden dpcc.LspServer.exe 900, vorher 640; seit CI-OPT mit zwei
    // Zeilen mehr im Abschnitt Vervollständigung 950). Der Bereich der IDE rollt, wenn er kleiner ist.
    Assert.IsTrue(mPage.Height <= mPage.ScaleValue(950), 'Höhe ' + IntToStr(mPage.Height));
    // CI-OPT: die beiden Häkchen eingerückt wie die übrigen Optionen.
    Assert.AreEqual(mPage.ControlOf('Learning').Left, mPage.OpenAfterDot.Left, 'Einrückung Nach dem Punkt');
    Assert.AreEqual(mPage.ControlOf('Learning').Left, mPage.Keywords.Left, 'Einrückung Reservierte Wörter');
    // Die Sätze der Betriebsart brechen in der Breite der Seite um, nicht in einer schmalen Ersatzbreite.
    Assert.IsTrue(mPage.ModeButton[TDpccOperatingMode.Server].Parent.Height <= mPage.ScaleValue(300),
      'Zeile der Betriebsart ' + IntToStr(mPage.ModeButton[TDpccOperatingMode.Server].Parent.Height));
    // LOG1: Das Häkchen im Abschnitt IDE eingerückt wie die übrigen Optionen.
    Assert.AreEqual(mPage.ControlOf('Learning').Left, mPage.DiagnoseLog.Left, 'Einrückung Ablauf protokollieren');
    Assert.IsTrue(mPage.ResetHistory.Left + mPage.ResetHistory.Width <= mPage.ScaleValue(520),
      'Breite der Lernen-Zeile ' + IntToStr(mPage.ResetHistory.Left + mPage.ResetHistory.Width));
  finally
    mPage.Free;
    TDpccStrings.Language := Low(TDpccLanguage);
  end;
end;

procedure TDpccSettingsPageTests.CompletionSwitchesCheckBoxes(AEnglish: Boolean);
var
  mPage: TDpccSettingsPage;
  mSettings: TDpccPluginSettings;
  mFirst: TDpccSettingsPageEntry;
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
    // Lage: „Nach dem Punkt“ erste Option des Abschnitts Vervollständigung, „Reservierte Wörter“ direkt vor dem
    // Lernen.
    mFirst := mPage.Entries[1];
    Assert.AreEqual('OpenAfterDot', mFirst.Item.Name, 'erste Option');
    Assert.AreEqual(Ord(psCompletion), Ord(mFirst.Item.Section), 'Abschnitt');
    Assert.IsTrue(mFirst.Control = mPage.OpenAfterDot, 'Häkchen');
    Assert.IsTrue(mPage.Keywords.Parent.Top < mPage.ControlOf('Learning').Parent.Top, 'vor dem Lernen');
    Assert.IsTrue(mPage.Keywords.Parent.Top > mPage.AutoWidth.Parent.Top, 'nach den sichtbaren Zeilen');
    if AEnglish then
    begin
      Assert.AreEqual('Open automatically after the dot', mPage.OpenAfterDot.Caption, 'Beschriftung');
      Assert.AreEqual('Show reserved words in the list', mPage.Keywords.Caption, 'Beschriftung');
      Assert.IsTrue(ContainsText(mPage.OpenAfterDot.Hint, 'without a restart'), mPage.OpenAfterDot.Hint);
      Assert.IsTrue(ContainsText(mPage.Keywords.Hint, 'completion.keywords'), mPage.Keywords.Hint);
    end
    else
    begin
      Assert.AreEqual('Nach dem Punkt automatisch öffnen', mPage.OpenAfterDot.Caption, 'Beschriftung');
      Assert.AreEqual('Reservierte Wörter in der Liste zeigen', mPage.Keywords.Caption, 'Beschriftung');
      Assert.IsTrue(ContainsText(mPage.OpenAfterDot.Hint, 'ohne Neustart'), mPage.OpenAfterDot.Hint);
      Assert.IsTrue(ContainsText(mPage.OpenAfterDot.Hint, 'Strg+Leertaste'), mPage.OpenAfterDot.Hint);
      Assert.IsTrue(ContainsText(mPage.Keywords.Hint, 'completion.keywords'), mPage.Keywords.Hint);
      Assert.IsTrue(ContainsText(mPage.Keywords.Hint, 'ohne Neustart'), mPage.Keywords.Hint);
    end;
    Assert.IsTrue(mPage.OpenAfterDot.ShowHint and mPage.Keywords.ShowHint, 'Hint an');
    // Vorgabe an; geladen und gespeichert.
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    Assert.IsTrue(mPage.OpenAfterDot.Checked and mPage.Keywords.Checked, 'Vorgabe an');
    mSettings := TDpccPluginSettings.Defaults;
    mSettings.OpenAfterDot := False;
    mPage.LoadFrom(mSettings);
    Assert.IsFalse(mPage.OpenAfterDot.Checked, 'geladen aus');
    Assert.IsTrue(mPage.Keywords.Checked, 'unabhängig');
    mPage.OpenAfterDot.Checked := True;
    mPage.Keywords.Checked := False;
    mPage.SaveTo(mSettings);
    Assert.IsTrue(mSettings.OpenAfterDot, 'gespeichert an');
    Assert.IsFalse(mSettings.ShowKeywords, 'gespeichert aus');
    // Merker der Übernahme zeigt die Seite nicht; SaveTo lässt sie stehen.
    mSettings.OpenAfterDotAdopted := True;
    mPage.SaveTo(mSettings);
    Assert.IsTrue(mSettings.OpenAfterDotAdopted, 'Merker bleibt');
    // Gesperrt außerhalb der Betriebsart Plugin, wie die übrigen Optionen.
    mPage.Mode := TDpccOperatingMode.Off;
    Assert.IsFalse(mPage.OpenAfterDot.Enabled or mPage.Keywords.Enabled, 'Aus: grau');
    mPage.Mode := TDpccOperatingMode.Server;
    Assert.IsFalse(mPage.OpenAfterDot.Enabled or mPage.Keywords.Enabled, 'Server: grau');
    mPage.Mode := TDpccOperatingMode.Plugin;
    Assert.IsTrue(mPage.OpenAfterDot.Enabled and mPage.Keywords.Enabled, 'Plugin: frei');
  finally
    mPage.Free;
    TDpccStrings.Language := Low(TDpccLanguage);
  end;
end;

procedure TDpccSettingsPageTests.InfoLabelsUseDialogFont;
var
  mPage: TDpccSettingsPage;
  mIndex, mCount: Integer;
  mLabel: TLabel;
begin
  mPage := TDpccSettingsPage.Create(nil);
  try
    mPage.Font.Size := 11;
    mCount := 0;
    for mIndex := 0 to mPage.ComponentCount - 1 do
    begin
      if mPage.Components[mIndex].ClassName = 'TDpccInfoLabel' then
      begin
        mLabel := mPage.Components[mIndex] as TLabel;
        Inc(mCount);
        Assert.IsTrue(mLabel.ParentFont, 'ParentFont: ' + mLabel.Caption);
        Assert.AreEqual(mPage.Font.Height, mLabel.Font.Height, 'Schrift des Dialogs: ' + mLabel.Caption);
      end;
    end;
    // Drei Sätze der Betriebsart, „dpcc.LspServer.exe fehlt“, Ergebnis von „Index neu aufbauen“, Abschnitt IDE.
    Assert.AreEqual(6, mCount, 'gedämpfte Sätze');
    Assert.AreEqual('TDpccInfoLabel', mPage.IdeStatus.ClassName, 'Statuszeilen');
    Assert.IsTrue(mPage.IdeStatus.ParentFont, 'Statuszeilen in der Schrift des Dialogs');
  finally
    mPage.Free;
  end;
end;

procedure TDpccSettingsPageTests.IdeStatusRowGrowsWithLines;
var
  mPage: TDpccSettingsPage;
  mBitmap: Vcl.Graphics.TBitmap;
  mLines: string;
  mNeeded, mPageHeight: Integer;
begin
  mLines := 'Betriebsart dpcc: dpcc ist der Code-Insight-Anbieter (dpcc.CodeInsight).' + sLineBreak +
    'Der Anbieter wird beim nächsten Start von Delphi dpcc.' + sLineBreak +
    'Von dpcc gesetzt: Insight Manager, Auto Code Completions, Auto Code Parameters, Declaration Information, ' +
    'Help Insight, ToolTip Watches' + sLineBreak + '1 Abweichung: Auto Code Completions' + sLineBreak +
    'Zeile 5' + sLineBreak + 'Zeile 6';
  mPage := TDpccSettingsPage.Create(nil);
  mBitmap := Vcl.Graphics.TBitmap.Create;
  try
    mPage.LoadFrom(TDpccPluginSettings.Defaults);
    mPageHeight := mPage.Height;
    mPage.OnIdeStatus :=
      function: string
      begin
        Result := mLines;
      end;
    mBitmap.Canvas.Font.Assign(mPage.IdeStatus.Font);
    // Mindestens sechs Zeilen Text: früher hatte die Zeile fest 64 Punkte (vier Zeilen).
    mNeeded := 6 * mBitmap.Canvas.TextHeight('Ag');
    Assert.IsTrue(mPage.IdeStatus.Height >= mNeeded, Format('Statuszeilen %d < %d', [mPage.IdeStatus.Height,
      mNeeded]));
    Assert.IsTrue(mPage.IdeStatus.Parent.Height >= mPage.IdeStatus.Height, 'Zeile so hoch wie die Statuszeilen');
    Assert.IsTrue(mPage.Height > mPageHeight, 'Seite wächst mit');
    // Wieder kurz: die Zeile schrumpft auf die Mindesthöhe.
    mLines := 'Betriebsart IDE';
    mPage.CheckIde.Click;
    Assert.IsTrue(mPage.IdeStatus.Height < mNeeded, 'schrumpft wieder');
  finally
    mBitmap.Free;
    mPage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccSettingsPageTests);

end.
