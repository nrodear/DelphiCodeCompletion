unit dpcc.UI.Settings.Page.Transfer;

// Übertragen der Einstellungen (#723): Export, Import, Profile, Zurücksetzen; Leiste unten über die ganze Seite.

interface

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.StdCtrls,
  dpcc.Core.Settings.Plugin,
  dpcc.UI.Settings.ChoiceBox,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Import (#723): AProfile True = erst ein eingebautes Profil wählen. True, wenn AResult gilt (die
  /// IDE hat schon gespeichert).</summary>
  TDpccSettingsImportEvent = reference to function(const ACurrent: TDpccPluginSettings; AProfile: Boolean;
    out AResult: TDpccPluginSettings): Boolean;
  /// <summary>„Alles zurücksetzen“ (#723) mit Rückfrage; True, wenn AResult gilt.</summary>
  TDpccSettingsResetEvent = reference to function(const ACurrent: TDpccPluginSettings;
    out AResult: TDpccPluginSettings): Boolean;

type
  /// <summary>Übertragen der Einstellungen (#723): Export, Import, Profile, Zurücksetzen; Leiste unten über die ganze
  /// Seite.</summary>
  TDpccSettingsTransferPart = class(TDpccSettingsPagePart)
  private
    // Einstellungen übertragen (#723): Schalter, Knöpfe unten, Punkte an geänderten Werten.
    FSettingsExportImport: TCheckBox;
    FSettingsMarkModified: TCheckBox;
    FSettingsExportSecrets: TDpccChoiceBox;
    FTransferBar: TWinControl;
    FExportButton: TButton;
    FImportButton: TButton;
    FProfileButton: TButton;
    FResetPageButton: TButton;
    FResetAllButton: TButton;
    FOnExportSettings: TProc<TDpccPluginSettings>;
    FOnImportSettings: TDpccSettingsImportEvent;
    FOnResetAllSettings: TDpccSettingsResetEvent;
    procedure AddTransferSection;
    procedure ResetPageClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
    procedure ProfileClick(Sender: TObject);
    procedure ResetAllClick(Sender: TObject);
  public
    procedure Build;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    procedure BindMarks; override;
    procedure ShowModified;
    /// <summary>„Exportieren…“ mit den Werten der Seite (#723).</summary>
    property OnExportSettings: TProc<TDpccPluginSettings> read FOnExportSettings write FOnExportSettings;
    /// <summary>„Importieren…“ und „Profil laden…“ (#723).</summary>
    property OnImportSettings: TDpccSettingsImportEvent read FOnImportSettings write FOnImportSettings;
    /// <summary>„Alles zurücksetzen…“ (#723).</summary>
    property OnResetAllSettings: TDpccSettingsResetEvent read FOnResetAllSettings write FOnResetAllSettings;
    property TransferBar: TWinControl read FTransferBar;
    property SettingsExportImportCheck: TCheckBox read FSettingsExportImport;
    property SettingsMarkModifiedCheck: TCheckBox read FSettingsMarkModified;
    property SettingsExportSecretsChoice: TDpccChoiceBox read FSettingsExportSecrets;
    property ExportButton: TButton read FExportButton;
    property ImportButton: TButton read FImportButton;
    property ResetAllButton: TButton read FResetAllButton;
  end;

implementation

uses
  System.Classes,
  dpcc.UI.Settings.Page.Sheets,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.Core.Settings.Transfer,
  dpcc.Core.Settings.CompletionView;

const
  // Lage der Knöpfe in der Leiste: erste Zeile Export, Import, Profil; zweite Zeile Zurücksetzen.
  cRow1 = 4;
  cButtonWidth = 120;
  cImportLeft = 126;
  cProfileLeft = 252;
  cResetWidth = 150;
  cResetAllLeft = 156;

{ TDpccSettingsTransferPart }

procedure TDpccSettingsTransferPart.Build;
begin
  // Einstellungen exportieren, importieren und zurücksetzen (#723).
  AddTransferSection;
end;

procedure TDpccSettingsTransferPart.AddTransferSection;
const
  cBarHeight = 66;
  cButtonHeight = 25;
  cRow2 = 34;

  function AddButton(const ACaption: string; ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(FPage);
    Result.Parent := FTransferBar;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, AWidth, cButtonHeight);
    Result.OnClick := AClick;
  end;

begin
  AddTitle(TDpccTextId.SettingsTransferTitle);
  FSettingsExportImport := BindCheck('SettingsExportImport',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExportImport)));
  FSettingsMarkModified := BindCheck('SettingsMarkModified',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMarkModified)));
  // Suche über die Einstellungen (#1884).
  BindCheck('SettingsSearch', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSearchEnabled)));
  BindCheck('SettingsBackupBeforeImport',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBackupBeforeImport)));
  FSettingsExportSecrets := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExportSecrets),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExportSecretsOmit),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExportSecretsPlaceholder)]);
  // Knöpfe unten über die ganze Seite; ohne settings.exportImport ausgeblendet (RefreshMarks).
  FTransferBar := TDpccSettingsRow.Create(FPage);
  FTransferBar.Parent := FPage;
  FTransferBar.Align := alBottom;
  FTransferBar.AlignWithMargins := True;
  FTransferBar.Height := cBarHeight;
  FExportButton := AddButton(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExportButton), 0, cRow1,
    cButtonWidth, ExportClick);
  FImportButton := AddButton(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportButton), cImportLeft, cRow1,
    cButtonWidth, ImportClick);
  FProfileButton := AddButton(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProfileButton), cProfileLeft,
    cRow1, cButtonWidth, ProfileClick);
  FResetPageButton := AddButton(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsResetPageButton), 0, cRow2,
    cResetWidth, ResetPageClick);
  FResetAllButton := AddButton(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsResetAllButton), cResetAllLeft,
    cRow2, cResetWidth, ResetAllClick);
end;

procedure TDpccSettingsTransferPart.BindMarks;
begin
  FPage.Marks.Bind(FSettingsExportSecrets, ['SettingsExportSecrets']);
end;

procedure TDpccSettingsTransferPart.ShowModified;
var
  mModified: TArray<string>;
begin
  // Completion-Schnitt: Export, Import und Zurücksetzen zeigt dpcc nicht mehr (settings.exportImport ausgeblendet).
  FTransferBar.Visible := FSettingsExportImport.Checked and
    TDpccCompletionView.ShowsName(FPage.Catalog, 'SettingsExportImport');
  mModified := nil;
  if FSettingsMarkModified.Checked then
  begin
    mModified := TDpccSettingsTransfer.ModifiedNames(FPage.Catalog, FPage.CurrentSettings);
  end;
  FPage.Marks.Show(mModified, FSettingsMarkModified.Checked);
end;

procedure TDpccSettingsTransferPart.ResetPageClick(Sender: TObject);
begin
  FPage.ResetPage;
end;

procedure TDpccSettingsTransferPart.ExportClick(Sender: TObject);
begin
  if Assigned(FOnExportSettings) then
  begin
    FOnExportSettings(FPage.CurrentSettings);
  end;
end;

procedure TDpccSettingsTransferPart.ImportClick(Sender: TObject);
var
  mImported: TDpccPluginSettings;
begin
  if Assigned(FOnImportSettings) and FOnImportSettings(FPage.CurrentSettings, False, mImported) then
  begin
    FPage.LoadFrom(mImported);
  end;
end;

procedure TDpccSettingsTransferPart.ProfileClick(Sender: TObject);
var
  mImported: TDpccPluginSettings;
begin
  if Assigned(FOnImportSettings) and FOnImportSettings(FPage.CurrentSettings, True, mImported) then
  begin
    FPage.LoadFrom(mImported);
  end;
end;

procedure TDpccSettingsTransferPart.ResetAllClick(Sender: TObject);
var
  mReset: TDpccPluginSettings;
begin
  if Assigned(FOnResetAllSettings) and FOnResetAllSettings(FPage.CurrentSettings, mReset) then
  begin
    FPage.LoadFrom(mReset);
  end;
end;

procedure TDpccSettingsTransferPart.Load(const ASettings: TDpccPluginSettings);
begin
  FSettingsExportSecrets.Choice := Ord(ASettings.SettingsExportSecrets = 'placeholder');
end;

procedure TDpccSettingsTransferPart.Save(var ASettings: TDpccPluginSettings);
begin
  ASettings.SettingsExportSecrets := 'omit';
  if FSettingsExportSecrets.Choice = 1 then
  begin
    ASettings.SettingsExportSecrets := 'placeholder';
  end;
end;

end.
