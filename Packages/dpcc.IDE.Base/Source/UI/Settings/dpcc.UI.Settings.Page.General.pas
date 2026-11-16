unit dpcc.UI.Settings.Page.General;

// Reiter „Allgemein“: Hauptschalter, „Index neu aufbauen“, Statusfeld, Diagnose, Hinweise und Benachrichtigungen.
// „Index neu aufbauen“ (S4, statt der Seite „Index“): Rückfrage, dann leert die IDE-Schicht die Index-Caches und baut
// den Index neu auf (OnRebuildIndex); die Seite zeigt nur das Ergebnis. Anzeigen und Schalter zum Server (Zustand,
// Version, Fenster „dpcc-Server“, „Prozesse am Projekt…“) gibt es seit S1 bzw. S4 nicht mehr.

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  dpcc.Core.Settings.Plugin,
  dpcc.UI.Settings.ChoiceBox,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Allgemein“: Hauptschalter, Statusfeld, Diagnose, Architektur, Hinweise und
  /// Benachrichtigungen.</summary>
  TDpccSettingsGeneralPart = class(TDpccSettingsPagePart)
  private
    FDiagnosticMode: TCheckBox;
    FShortcutTipsScope: TDpccChoiceBox;
    FStatusToggles: TDpccChoiceBox;
    FIndexProgress: TDpccChoiceBox;
    FStatusHidden: TEdit;
    /// <summary>Hauptschalter der experimentellen Funktionen (#834), Hinweis darüber und Filter unten.</summary>
    FExperimentalEnabled: TCheckBox;
    /// <summary>„Index neu aufbauen“ (S4) und die Zeile mit dem Ergebnis.</summary>
    FRebuild: TButton;
    FRebuildInfo: TLabel;
    FOnRebuildIndex: TFunc<string>;
    FConfirmRebuild: TFunc<Boolean>;
    procedure AddRebuildRow;
    procedure RebuildClick(Sender: TObject);
    procedure SetOnRebuildIndex(const AValue: TFunc<string>);
  public
    procedure Build;
    procedure Build2;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    procedure BindMarks; override;
    property DiagnosticMode: TCheckBox read FDiagnosticMode;
    property ExperimentalEnabled: TCheckBox read FExperimentalEnabled;
    property ShortcutTipsScope: TDpccChoiceBox read FShortcutTipsScope;
    property StatusToggles: TDpccChoiceBox read FStatusToggles;
    property IndexProgress: TDpccChoiceBox read FIndexProgress;
    property StatusHidden: TEdit read FStatusHidden;
    /// <summary>Zum Testen: Knopf „Index neu aufbauen“ und die Zeile mit dem Ergebnis.</summary>
    property Rebuild: TButton read FRebuild;
    property RebuildInfo: TLabel read FRebuildInfo;
    /// <summary>„Index neu aufbauen“ (S4): leert die Index-Caches, baut den Index neu auf und liefert die Meldung
    /// für die Seite; nil = Knopf gesperrt.</summary>
    property OnRebuildIndex: TFunc<string> read FOnRebuildIndex write SetOnRebuildIndex;
    /// <summary>Rückfrage vor dem Neuaufbau; Standard: Dialog mit Ja/Nein.</summary>
    property ConfirmRebuild: TFunc<Boolean> read FConfirmRebuild write FConfirmRebuild;
  end;

  /// <summary>Benachrichtigungszentrale (#601) am Ende des Reiters „Allgemein“: Schalter, Größe und Verhalten je
  /// Quelle.</summary>
  TDpccSettingsNotificationsPart = class(TDpccSettingsPagePart)
  private
    FNotificationsMax: TEdit;
    FNotificationSource: TDpccChoiceBox;
    FNotificationMode: TDpccChoiceBox;
    FNotificationsSpec: string;
    /// <summary>Zeile „Verhalten je Quelle“ (#601): Quelle und Verhalten nebeneinander.</summary>
    procedure AddNotificationSources;
    procedure NotificationSourceChange(Sender: TObject);
    procedure NotificationModeChange(Sender: TObject);
  public
    procedure Build;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    procedure BindMarks; override;
    property NotificationsMax: TEdit read FNotificationsMax;
    property NotificationSource: TDpccChoiceBox read FNotificationSource;
    property NotificationMode: TDpccChoiceBox read FNotificationMode;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.UITypes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Dialogs,
  Vcl.Forms,
  dpcc.UI.Settings.Page.Sheets,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.Core.Commands.ShortcutTips,
  dpcc.Core.Notifications.Contract,
  dpcc.Core.Notifications.Sources,
  dpcc.UI.Notifications.Window;

{ TDpccSettingsGeneralPart }

procedure TDpccSettingsGeneralPart.Build;
begin
  AddSheet(TDpccTextId.SettingsTabGeneral);
  BindCheck('Enabled', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsEnabled)));
  AddRebuildRow;
  BindCheck('ReloadExternal', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReload)));
  // Änderungen an nicht geöffneten Dateien (#397).
  BindCheck('OpenForEdits', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsOpenForEdits)));
  // dpcc-Statusfeld (#591).
  BindCheck('StatusField', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStatusField)));
  BindCheck('StatusFieldSummary', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStatusSummary)));
  FStatusToggles := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStatusToggles),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStatusTogglesBoth),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStatusTogglesRight),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStatusTogglesDouble)]);
end;

procedure TDpccSettingsGeneralPart.Build2;
begin
  FIndexProgress := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexProgress),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexProgressField),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexProgressMenu),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexProgressOff)]);
  FStatusHidden := AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStatusHidden));
  FStatusHidden.NumbersOnly := False;
  FStatusHidden.Width := FStatusHidden.ScaleValue(180);
  // Diagnosemodus (#479); Taste auf der Seite „Tastenkonflikte“.
  FDiagnosticMode := BindCheck('DiagnosticMode',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDiagnosticMode)));
  // Diagnose-Fenster: Zeiten des Plugins (Hauptthread, Anfragen, Hintergrund, Hänger).
  BindCheck('DiagnosticPluginTimings',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDiagnosticPluginTimings)));
  BindText('DiagnosticSlowMs', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDiagnosticSlowMs)));
  // „Prozesse am Projekt…“ (#62) und Fenster „dpcc-Server“ (#1356) seit S4 weg.
  // Prüfliste der Einrichtung (#625) entfallen: abgeschaltet (Completion-Schnitt).
  // Hauptschalter der experimentellen Funktionen (#834).
  FExperimentalEnabled := BindCheck('ExperimentalEnabled',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExperimentalEnabled)));
  // Tastenkürzel-Tipps (#600); Reihenfolge wie TDpccTipScope: dpcc, all.
  BindCheck('ShortcutTips', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsShortcutTips)));
  FShortcutTipsScope := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsShortcutTipsScope),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsShortcutTipsDpcc),
      TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsShortcutTipsAll)]);
end;

procedure TDpccSettingsGeneralPart.AddRebuildRow;
var
  mPanel: TWinControl;
begin
  // „Index neu aufbauen“ (S4): ersetzt die Knöpfe der früheren Seite „Index“.
  mPanel := AddPanel(32);
  FRebuild := TButton.Create(FPage);
  FRebuild.Parent := mPanel;
  FRebuild.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexRebuild);
  FRebuild.Left := 0;
  FRebuild.Top := FRebuild.ScaleValue(3);
  FRebuild.Width := FRebuild.ScaleValue(180);
  FRebuild.OnClick := RebuildClick;
  mPanel := AddPanel(20);
  FRebuildInfo := TLabel.Create(FPage);
  FRebuildInfo.Parent := mPanel;
  FRebuildInfo.Left := 0;
  FRebuildInfo.Top := FRebuildInfo.ScaleValue(2);
  FRebuildInfo.Font.Color := clGrayText;
  Allow(FRebuild, False);
end;

procedure TDpccSettingsGeneralPart.SetOnRebuildIndex(const AValue: TFunc<string>);
begin
  FOnRebuildIndex := AValue;
  Allow(FRebuild, Assigned(FOnRebuildIndex));
end;

procedure TDpccSettingsGeneralPart.RebuildClick(Sender: TObject);
var
  mConfirmed: Boolean;
  mCursor: TCursor;
begin
  if not Assigned(FOnRebuildIndex) then
  begin
    Exit;
  end;
  if Assigned(FConfirmRebuild) then
  begin
    mConfirmed := FConfirmRebuild();
  end
  else
  begin
    mConfirmed := MessageDlg(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexRebuildConfirm),
      mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  end;
  if not mConfirmed then
  begin
    Exit;
  end;
  // Laufende Sitzung anhalten, Caches löschen und neu starten dauert ein paar Sekunden.
  mCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    FRebuildInfo.Caption := FOnRebuildIndex();
  finally
    Screen.Cursor := mCursor;
  end;
end;

procedure TDpccSettingsGeneralPart.BindMarks;
begin
  FPage.Marks.Bind(FShortcutTipsScope, ['ShortcutTipsScope']);
  FPage.Marks.Bind(FStatusToggles, ['StatusFieldToggles']);
  FPage.Marks.Bind(FIndexProgress, ['IndexProgressPlace']);
  FPage.Marks.Bind(FStatusHidden, ['StatusFieldHidden']);
end;

procedure TDpccSettingsGeneralPart.Load(const ASettings: TDpccPluginSettings);
begin
  FShortcutTipsScope.Choice := Ord(TDpccShortcutTips.ScopeOf(ASettings.ShortcutTipsScope));
  if not ASettings.StatusTogglesOnDoubleClick then
  begin
    FStatusToggles.Choice := 1;
  end
  else if not ASettings.StatusTogglesOnRightClick then
  begin
    FStatusToggles.Choice := 2;
  end
  else
  begin
    FStatusToggles.Choice := 0;
  end;
  if SameText(ASettings.IndexProgressPlace, 'menu') then
  begin
    FIndexProgress.Choice := 1;
  end
  else if SameText(ASettings.IndexProgressPlace, 'off') then
  begin
    FIndexProgress.Choice := 2;
  end
  else
  begin
    FIndexProgress.Choice := 0;
  end;
  FStatusHidden.Text := ASettings.StatusFieldHidden;
end;

procedure TDpccSettingsGeneralPart.Save(var ASettings: TDpccPluginSettings);
begin
  ASettings.ShortcutTipsScope := TDpccShortcutTips.ScopeName(TDpccTipScope(EnsureRange(FShortcutTipsScope.Choice,
    Ord(Low(TDpccTipScope)), Ord(High(TDpccTipScope)))));
  case FStatusToggles.Choice of
    1:
      ASettings.StatusFieldToggles := 'rightClick';
    2:
      ASettings.StatusFieldToggles := 'doubleClick';
  else
    ASettings.StatusFieldToggles := 'both';
  end;
  case FIndexProgress.Choice of
    1:
      ASettings.IndexProgressPlace := 'menu';
    2:
      ASettings.IndexProgressPlace := 'off';
  else
    ASettings.IndexProgressPlace := 'statusField';
  end;
  ASettings.StatusFieldHidden := Trim(FStatusHidden.Text);
end;

{ TDpccSettingsNotificationsPart }

procedure TDpccSettingsNotificationsPart.Build;
begin
  // Benachrichtigungszentrale (#601); Taste auf dem Reiter Befehle.
  BindCheck('Notifications', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNotifications)));
  FNotificationsMax := AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNotificationsMax));
  AddNotificationSources;
end;

procedure TDpccSettingsNotificationsPart.Load(const ASettings: TDpccPluginSettings);
begin
  FNotificationsMax.Text := IntToStr(ASettings.NotificationsMaxEntries);
  FNotificationsSpec := ASettings.NotificationsSources;
  NotificationSourceChange(nil);
end;

procedure TDpccSettingsNotificationsPart.Save(var ASettings: TDpccPluginSettings);
begin
  ASettings.NotificationsMaxEntries := StrToIntDef(Trim(FNotificationsMax.Text), ASettings.NotificationsMaxEntries);
  ASettings.NotificationsSources := TDpccNotificationSources.Normalize(FNotificationsSpec);
end;

procedure TDpccSettingsNotificationsPart.BindMarks;
begin
  FPage.Marks.Bind(FNotificationsMax, ['NotificationsMaxEntries']);
  FPage.Marks.Bind(FNotificationSource, ['NotificationsSources']);
end;

procedure TDpccSettingsNotificationsPart.AddNotificationSources;
var
  mPanel: TWinControl;
  mCaption: TLabel;
  mNames: TArray<string>;
  mSource: string;
begin
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := mPanel;
  mCaption.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNotificationsSources);
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(5);
  mNames := nil;
  for mSource in TDpccNotificationSources.Known do
  begin
    mNames := mNames + [TDpccNotificationTexts.SourceCaption(mSource)];
  end;
  FNotificationSource := TDpccChoiceBox.Create(FPage);
  FNotificationSource.Parent := mPanel;
  FNotificationSource.Left := cFieldLeft;
  FNotificationSource.Top := 1;
  FNotificationSource.Width := FNotificationSource.ScaleValue(180);
  FNotificationSource.SetChoices(mNames);
  FNotificationSource.Choice := 0;
  FNotificationSource.OnChange := NotificationSourceChange;
  // Reihenfolge wie TDpccNotificationMode: einblenden und sammeln, nur sammeln, aus.
  FNotificationMode := TDpccChoiceBox.Create(FPage);
  FNotificationMode.Parent := mPanel;
  FNotificationMode.Left := cFieldLeft + FNotificationMode.ScaleValue(186);
  FNotificationMode.Top := 1;
  FNotificationMode.Width := FNotificationMode.ScaleValue(170);
  FNotificationMode.SetChoices([TDpccStrings.Text(TDpccTextId.NotificationsModeShow),
    TDpccStrings.Text(TDpccTextId.NotificationsModeCollect), TDpccStrings.Text(TDpccTextId.NotificationsModeOff)]);
  FNotificationMode.Choice := 0;
  FNotificationMode.OnChange := NotificationModeChange;
end;

procedure TDpccSettingsNotificationsPart.NotificationSourceChange(Sender: TObject);
var
  mKnown: TArray<string>;
begin
  mKnown := TDpccNotificationSources.Known;
  if (FNotificationSource.Choice < 0) or (FNotificationSource.Choice > High(mKnown)) then
  begin
    Exit;
  end;
  FNotificationMode.Choice := Ord(TDpccNotificationSources.ModeIn(FNotificationsSpec,
    mKnown[FNotificationSource.Choice]));
end;

procedure TDpccSettingsNotificationsPart.NotificationModeChange(Sender: TObject);
var
  mKnown: TArray<string>;
begin
  mKnown := TDpccNotificationSources.Known;
  if (FNotificationSource.Choice < 0) or (FNotificationSource.Choice > High(mKnown)) or
    (FNotificationMode.Choice < Ord(Low(TDpccNotificationMode))) or
    (FNotificationMode.Choice > Ord(High(TDpccNotificationMode))) then
  begin
    Exit;
  end;
  FNotificationsSpec := TDpccNotificationSources.WithMode(FNotificationsSpec, mKnown[FNotificationSource.Choice],
    TDpccNotificationMode(FNotificationMode.Choice));
end;

end.
