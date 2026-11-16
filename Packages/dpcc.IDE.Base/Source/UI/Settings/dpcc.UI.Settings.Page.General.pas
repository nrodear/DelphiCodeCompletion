unit dpcc.UI.Settings.Page.General;

// Reiter „Allgemein“: Hauptschalter, „Index neu aufbauen“, Statusfeld, Diagnose und Hinweise. Den Teil
// „Benachrichtigungen“ gibt es seit S7a nicht mehr (es gibt keine Benachrichtigungszentrale).
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
  /// <summary>Reiter „Allgemein“: Hauptschalter, Statusfeld, Diagnose, Architektur und Hinweise.</summary>
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
  dpcc.Core.Commands.ShortcutTips;

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

end.
