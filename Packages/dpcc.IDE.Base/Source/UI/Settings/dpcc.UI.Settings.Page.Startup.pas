unit dpcc.UI.Settings.Page.Startup;

// Reiter „Start“ (abgesicherter Start #722, Fehlerbericht #108), „Rückgängig“ und
// „Units suchen“ (hier nur schnell öffnen #503; die Units-Suche #777 baut ihr Modul als Abschnitt dazu).
// Der Abschnitt „Version und Updates“ (#495, #1519) ist entfallen: Die Update-Prüfung ist abgeschaltet
// (Completion-Schnitt).

interface

uses
  Vcl.StdCtrls,
  dpcc.Core.Settings.Plugin,
  dpcc.UI.Settings.ChoiceBox,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Start“ (abgesicherter Start #722, Fehlerbericht #108), „Rückgängig“ und „Units
  /// suchen“ (schnell öffnen #503).</summary>
  TDpccSettingsStartupPart = class(TDpccSettingsPagePart)
  private
    FSafeKey: TDpccChoiceBox;
    FUndoOnConflict: TDpccChoiceBox;
    FUndoNewFiles: TDpccChoiceBox;
    procedure AddSafeSection;
    procedure AddUndoSection;
    procedure AddQuickOpenSection;
    procedure AddBugReportSection;
  public
    procedure Build;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    procedure BindMarks; override;
    property SafeKey: TDpccChoiceBox read FSafeKey;
    property UndoOnConflict: TDpccChoiceBox read FUndoOnConflict;
    property UndoNewFiles: TDpccChoiceBox read FUndoNewFiles;
  end;

implementation

uses
  System.Math,
  Vcl.Controls,
  dpcc.Core.Diagnostics.SafeMode,
  dpcc.UI.Settings.Bindings,
  dpcc.UI.Settings.Page.Sheets,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.UI.Diagnostics.Strings,
  dpcc.Core.Undo.Contract,
  dpcc.Core.Undo.Names;

{ TDpccSettingsStartupPart }

procedure TDpccSettingsStartupPart.Build;
begin
  // Abgesicherter Start und Fehlerbericht (#722, #108).
  AddSheet(TDpccTextId.SettingsTabStartup);
  AddSafeSection;
  AddBugReportSection;

  AddSheet(TDpccTextId.SettingsTabUndo);
  AddUndoSection;

  AddSheet(TDpccTextId.SettingsTabUnitSearch);
  AddQuickOpenSection;
end;

procedure TDpccSettingsStartupPart.BindMarks;
begin
  FPage.Marks.Bind(FSafeKey, ['SafeStartupKey']);
  FPage.Marks.Bind(FUndoOnConflict, ['UndoMultiFileOnConflict']);
  FPage.Marks.Bind(FUndoNewFiles, ['UndoMultiFileNewFiles']);
end;

procedure TDpccSettingsStartupPart.AddSafeSection;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  // Abgesicherter Start nach einem Absturz (#722).
  AddTitle(TDpccTextId.SettingsSafeTitle);
  BindCheck('SafeAskAfterCrash', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSafeAsk)));
  BindCheck('SafeAutoAfterRepeatedCrash', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSafeAuto)));
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := mPanel;
  mCaption.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSafeKey);
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(5);
  FSafeKey := TDpccChoiceBox.Create(FPage);
  FSafeKey.Parent := mPanel;
  FSafeKey.Left := cFieldLeft;
  FSafeKey.Top := 1;
  FSafeKey.Width := FSafeKey.ScaleValue(120);
  // Reihenfolge wie TDpccStartupKey ohne None vorn: Umschalt, Strg, keine.
  FSafeKey.SetChoices([TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSafeKeyShift),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSafeKeyCtrl),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSafeKeyNone)]);
  BindText('SafeStartupTimeoutMs', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSafeTimeout)));
  BindText('SafeKeepSettingsHistory', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSafeHistory)));
end;

procedure TDpccSettingsStartupPart.AddQuickOpenSection;
begin
  // Datei und Symbol schnell öffnen (#503); die Units-Suche baut ihr Modul als Abschnitt in diesen Reiter (#1455).
  AddTitle(TDpccTextId.QuickOpenTitle);
  BindCheck('QuickOpen', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsQuickOpen)));
  BindCheck('QuickOpenLibrary', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsQuickOpenLibrary)));
  BindKey('QuickOpenKey', AddKey(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsQuickOpenKey)));
end;

procedure TDpccSettingsStartupPart.AddUndoSection;
begin
  // dpcc-Änderungen über mehrere Dateien zurücknehmen (#721).
  AddTitle(TDpccTextId.SettingsUndoTitle);
  BindCheck('UndoMultiFile', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsUndoEnabled)));
  BindText('UndoMultiFileDepth', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsUndoDepth)));
  BindCheck('UndoMultiFilePersist', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsUndoPersist)));
  BindText('UndoMultiFileMaxSizeMb', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsUndoMaxSize)));
  // Reihenfolge wie TDpccUndoConflictMode und TDpccNewFilesMode.
  FUndoOnConflict := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsUndoOnConflict),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsUndoPartial),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsUndoAbort)]);
  FUndoNewFiles := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsUndoNewFiles),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsUndoRecycle),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsUndoDelete),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsUndoKeep)]);
end;

procedure TDpccSettingsStartupPart.AddBugReportSection;
begin
  // Fehlerbericht (#108).
  AddTitle(TDpccTextId.SettingsBugReportTitle);
  BindCheck('BugReportAnonymize',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBugReportAnonymize)));
  // Protokoll des Plugins mit Klarnamen (#1478, diagnostics.log.names); Vorgabe anonym.
  BindCheck('LogNames', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsLogNames)));
  // Kommandozeilen-Compiler prüfen (#1822, diagnostics.editionCheck).
  BindCheck('DiagnosticsEditionCheck',
    AddCheck(TDpccDiagnosticsStrings.Text(TDpccDiagnosticsTextId.SettingsEditionCheck)));
end;

procedure TDpccSettingsStartupPart.Load(const ASettings: TDpccPluginSettings);
begin
  case TDpccSafeMode.KeyOf(ASettings.SafeStartupKey) of
    TDpccStartupKey.Ctrl:
      FSafeKey.Choice := 1;
    TDpccStartupKey.None:
      FSafeKey.Choice := 2;
  else
    FSafeKey.Choice := 0;
  end;
  FUndoOnConflict.Choice := Ord(TDpccUndoNames.ParseConflictMode(ASettings.UndoMultiFileOnConflict));
  FUndoNewFiles.Choice := Ord(TDpccUndoNames.ParseNewFiles(ASettings.UndoMultiFileNewFiles));
end;

procedure TDpccSettingsStartupPart.Save(var ASettings: TDpccPluginSettings);
begin
  case FSafeKey.Choice of
    1:
      ASettings.SafeStartupKey := TDpccSafeMode.KeyText(TDpccStartupKey.Ctrl);
    2:
      ASettings.SafeStartupKey := TDpccSafeMode.KeyText(TDpccStartupKey.None);
  else
    ASettings.SafeStartupKey := TDpccSafeMode.KeyText(TDpccStartupKey.Shift);
  end;
  ASettings.UndoMultiFileOnConflict := TDpccUndoNames.ConflictModeName(TDpccUndoConflictMode(
    Max(0, FUndoOnConflict.Choice)));
  ASettings.UndoMultiFileNewFiles := TDpccUndoNames.NewFilesName(TDpccNewFilesMode(Max(0, FUndoNewFiles.Choice)));
end;

end.
