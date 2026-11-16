unit dpcc.UI.Settings.Transfer;

// Dialoge zum Exportieren und Importieren der Einstellungen (#723), ohne Open
// Tools API und ohne Dateizugriff (den macht die IDE-Schicht). Schlicht wie
// die übrigen dpcc-Dialoge:
// - Export: Bereiche zum Ankreuzen, Umgang mit Zugangsdaten, kurzer Hinweis,
//   „Speichern…“ und „Abbrechen“.
// - Import: Name und Beschreibung der Datei, „Zusammenführen“ oder
//   „Ersetzen“, Bereiche, Liste „Einstellung | Bereich | Aktuell | Neu |
//   Hinweis“ mit Kontrollkästchen je Schlüssel (nur neue Werte und
//   Zurücksetzen lassen sich wählen), Zahl der gewählten Werte, „Übernehmen“.
//   Moduswechsel und Bereiche rechnen die Vorschau über OnPreview neu.
// - Profil: Liste der eingebauten Profile mit Beschreibung.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  dpcc.Core.Settings.Catalog,
  dpcc.Core.Settings.Transfer,
  dpcc.UI.Foundation.Dialog;

type
  TDpccImportPreviewFunc = reference to function(AMode: TDpccImportMode;
    const AAreas: TArray<string>): TDpccImportPreview;

  TDpccExportDialog = class(TDpccDialog)
  private
    FAreas: TArray<TCheckBox>;
    FAreaIds: TArray<string>;
    FSecrets: TRadioGroup;
    FSave: TButton;
    FCancel: TButton;
    procedure AreaClick(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent; ACatalog: TDpccSettingsCatalog; ASecrets: TDpccSecretMode);
    /// <summary>Gewählte Optionen.</summary>
    function Options: TDpccExportOptions;
    /// <summary>Modal fragen; True nach „Speichern…“.</summary>
    class function Execute(ACatalog: TDpccSettingsCatalog; var AOptions: TDpccExportOptions;
      const APrepare: TProc<TForm>): Boolean; static;
    property SaveButton: TButton read FSave;
    property Secrets: TRadioGroup read FSecrets;
  end;

  TDpccImportDialog = class(TDpccDialog)
  private
    FCatalog: TDpccSettingsCatalog;
    FPreview: TDpccImportPreview;
    FOnPreview: TDpccImportPreviewFunc;
    FInfo: TLabel;
    FMode: TRadioGroup;
    FAreaBoxes: TArray<TCheckBox>;
    FAreaIds: TArray<string>;
    FList: TListView;
    FCount: TLabel;
    FApply: TButton;
    FCancel: TButton;
    FFilled: Boolean;
    procedure Recalculate(Sender: TObject);
    procedure ListChanged(Sender: TObject);
    procedure ListKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SyncChecks;
    function ValueText(const AItem: TDpccImportItem; const AJson: string): string;
    function NoteText(const AItem: TDpccImportItem): string;
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; ACatalog: TDpccSettingsCatalog; const AFileName: string;
      const APreview: TDpccImportPreview; const AOnPreview: TDpccImportPreviewFunc);
    /// <summary>Liste aus der Vorschau füllen (braucht ein Fenster).</summary>
    procedure Fill;
    /// <summary>Vorschau mit der Auswahl der Liste.</summary>
    function Result_: TDpccImportPreview;
    /// <summary>Modal zeigen; True nach „Übernehmen“, APreview enthält dann die Auswahl.</summary>
    class function Execute(ACatalog: TDpccSettingsCatalog; const AFileName: string;
      var APreview: TDpccImportPreview; const AOnPreview: TDpccImportPreviewFunc;
      const APrepare: TProc<TForm>): Boolean; static;
    property List: TListView read FList;
    property Mode: TRadioGroup read FMode;
    property CountLabel: TLabel read FCount;
    property ApplyButton: TButton read FApply;
  end;

  TDpccProfileDialog = class(TDpccDialog)
  private
    FList: TListBox;
    FDescription: TLabel;
    FNames: TArray<string>;
    FDescriptions: TArray<string>;
    FLoad: TButton;
    FCancel: TButton;
    procedure ListClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const ANames, ADescriptions: TArray<string>);
    /// <summary>Modal wählen; True mit AIndex des Profils.</summary>
    class function Choose(const ANames, ADescriptions: TArray<string>; out AIndex: Integer;
      const APrepare: TProc<TForm>): Boolean; static;
    property List: TListBox read FList;
  end;

implementation

uses
  Vcl.Graphics,
  Vcl.Menus,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings;

const
  // Breiten der Dialoge Export, Import und Profil.
  cExportWidth = 460;
  cImportWidth = 760;
  cProfileWidth = 420;
  // Vorläufige Lage; die Ausrichtung ordnet die Teile danach in dieser Reihenfolge an.
  cAreasTop = 1000;
  cSecretsTop = 3000;
  cModeTop = 1000;
  // Breiten der Spalten Schlüssel, aktueller Wert, neuer Wert und Hinweis in der Importliste.
  cKeyWidth = 220;
  cValueWidth = 110;
  cNoteWidth = 180;

const
  cGap = 8;

function NewButton(AOwner: TForm; AParent: TWinControl; const ACaption: string): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  AOwner.Canvas.Font := AOwner.Font;
  Result.Width := AOwner.Canvas.TextWidth(ACaption) + AOwner.ScaleValue(32);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, cGap, cGap div 2);
end;

function NewButtons(AOwner: TForm): TFlowPanel;
begin
  Result := TFlowPanel.Create(AOwner);
  Result.Parent := AOwner;
  Result.Align := alBottom;
  Result.AutoSize := True;
  Result.BevelOuter := bvNone;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(cGap, cGap, cGap, cGap);
end;

function HasArea(const AAreas: TArray<string>; const AArea: string): Boolean;
var
  mArea: string;
begin
  Result := False;
  for mArea in AAreas do
  begin
    if SameText(mArea, AArea) then
    begin
      Exit(True);
    end;
  end;
end;

function English: Boolean;
begin
  Result := TDpccStrings.Language = TDpccLanguage.English;
end;

/// <summary>Beschriftung oben im Dialog; ATop ordnet sie unter die vorigen.</summary>
function NewTopLabel(AOwner: TForm; const ACaption: string; ATop: Integer): TLabel;
begin
  Result := TLabel.Create(AOwner);
  Result.Parent := AOwner;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(cGap, cGap, cGap, 0);
  Result.Top := ATop;
  Result.Caption := ACaption;
end;

/// <summary>Hinweistext oben im Dialog: umgebrochen, ohne Tastenkürzel.</summary>
function NewInfoLabel(AOwner: TForm; const ACaption: string): TLabel;
begin
  Result := NewTopLabel(AOwner, ACaption, 0);
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
end;

/// <summary>Auswahl mit zwei Einträgen oben im Dialog.</summary>
function NewChoice(AOwner: TForm; const ACaption: string; ATop: Integer;
  const AItems: TArray<string>): TRadioGroup;
var
  mItem: string;
begin
  Result := TRadioGroup.Create(AOwner);
  Result.Parent := AOwner;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(cGap, cGap, cGap, 0);
  Result.Top := ATop;
  Result.Height := AOwner.ScaleValue(64);
  Result.Caption := ACaption;
  Result.Items.BeginUpdate;
  try
    for mItem in AItems do
    begin
      Result.Items.Add(mItem);
    end;
  finally
    Result.Items.EndUpdate;
  end;
end;

/// <summary>Kontrollkästchen je Bereich des Katalogs in einer Leiste oben im Dialog; angekreuzt sind alle (AAll)
/// oder die in AChecked. AIds bekommt die Bereiche in derselben Reihenfolge.</summary>
function NewAreaBoxes(AOwner: TForm; ACatalog: TDpccSettingsCatalog; const AChecked: TArray<string>;
  AAll: Boolean; const AOnClick: TNotifyEvent; out AIds: TArray<string>): TArray<TCheckBox>;
var
  mPanel: TFlowPanel;
  mArea: TDpccCatalogArea;
  mBox: TCheckBox;
begin
  Result := nil;
  AIds := nil;
  mPanel := TFlowPanel.Create(AOwner);
  mPanel.Parent := AOwner;
  mPanel.Align := alTop;
  mPanel.AutoSize := True;
  mPanel.BevelOuter := bvNone;
  mPanel.AlignWithMargins := True;
  mPanel.Margins.SetBounds(cGap, 4, cGap, 0);
  mPanel.Top := mPanel.ScaleValue(2000);
  for mArea in ACatalog.Areas do
  begin
    mBox := TCheckBox.Create(AOwner);
    mBox.Parent := mPanel;
    mBox.Width := AOwner.ScaleValue(140);
    mBox.Caption := ACatalog.AreaCaption(mArea.Id, English);
    mBox.Checked := AAll or HasArea(AChecked, mArea.Id);
    mBox.OnClick := AOnClick;
    Result := Result + [mBox];
    AIds := AIds + [mArea.Id];
  end;
end;

/// <summary>Knopf ADefault („Speichern…“, „Übernehmen“) und „Abbrechen“ unten im Dialog; ACancel bekommt den
/// zweiten Knopf, Ergebnis ist die Leiste.</summary>
function NewDialogButtons(AOwner: TForm; const ACaption: string; out ADefault, ACancel: TButton): TFlowPanel;
begin
  Result := NewButtons(AOwner);
  ADefault := NewButton(AOwner, Result, ACaption);
  ADefault.ModalResult := mrOk;
  ADefault.Default := True;
  ACancel := NewButton(AOwner, Result, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDialogCancel));
  ACancel.ModalResult := mrCancel;
  ACancel.Cancel := True;
end;

/// <summary>Name und Beschreibung der Datei (Profile) in der Sprache der Oberfläche, Hinweis auf eine neuere
/// Version.</summary>
function ImportInfo(const APreview: TDpccImportPreview): string;
begin
  Result := APreview.Source.Name;
  if English and (APreview.Source.NameEn <> '') then
  begin
    Result := APreview.Source.NameEn;
  end;
  if English and (APreview.Source.DescriptionEn <> '') then
  begin
    Result := Trim(Result + sLineBreak + APreview.Source.DescriptionEn);
  end
  else if APreview.Source.Description <> '' then
  begin
    Result := Trim(Result + sLineBreak + APreview.Source.Description);
  end;
  if APreview.Newer then
  begin
    Result := Trim(Result + sLineBreak + TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsImportNewer,
      [APreview.Source.DpccVersion]));
  end;
end;

/// <summary>Spalte ACaption mit der (schon skalierten) Breite AWidth an AList anhängen.</summary>
procedure AddColumn(AList: TListView; const ACaption: string; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := ACaption;
  mColumn.Width := AWidth;
end;

{ TDpccExportDialog }

constructor TDpccExportDialog.CreateDialog(AOwner: TComponent; ACatalog: TDpccSettingsCatalog;
  ASecrets: TDpccSecretMode);
var
  mTitle: TLabel;
begin
  inherited CreateDialog(AOwner, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExportTitle), cExportWidth);
  NewDialogButtons(Self, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExportSave), FSave, FCancel);
  NewInfoLabel(Self, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExportInfo));
  mTitle := NewTopLabel(Self, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExportAreas), cAreasTop);
  mTitle.Font.Style := [fsBold];
  FAreas := NewAreaBoxes(Self, ACatalog, nil, True, AreaClick, FAreaIds);
  FSecrets := NewChoice(Self, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExportSecrets), cSecretsTop,
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExportSecretsOmit),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExportSecretsPlaceholder)]);
  FSecrets.ItemIndex := Ord(ASecrets);
  FSecrets.Columns := 2;
  // Feste Höhe: vier Zeilen Bereiche bei 11 Bereichen und drei Spalten.
  ClientHeight := ScaleValue(360);
end;

procedure TDpccExportDialog.AreaClick(Sender: TObject);
var
  mBox: TCheckBox;
begin
  FSave.Enabled := False;
  for mBox in FAreas do
  begin
    if mBox.Checked then
    begin
      FSave.Enabled := True;
    end;
  end;
end;

function TDpccExportDialog.Options: TDpccExportOptions;
var
  mIndex: Integer;
  mAreas: TArray<string>;
  mSecrets: TDpccSecretMode;
begin
  mAreas := nil;
  for mIndex := 0 to High(FAreas) do
  begin
    if FAreas[mIndex].Checked then
    begin
      mAreas := mAreas + [FAreaIds[mIndex]];
    end;
  end;
  mSecrets := smOmit;
  if FSecrets.ItemIndex = 1 then
  begin
    mSecrets := smPlaceholder;
  end;
  Result := TDpccExportOptions.Create(mAreas, mSecrets);
end;

class function TDpccExportDialog.Execute(ACatalog: TDpccSettingsCatalog; var AOptions: TDpccExportOptions;
  const APrepare: TProc<TForm>): Boolean;
var
  mDialog: TDpccExportDialog;
begin
  mDialog := TDpccExportDialog.CreateDialog(nil, ACatalog, AOptions.Secrets);
  try
    if Assigned(APrepare) then
    begin
      APrepare(mDialog);
    end;
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AOptions := mDialog.Options;
    end;
  finally
    mDialog.Free;
  end;
end;

{ TDpccImportDialog }

constructor TDpccImportDialog.CreateDialog(AOwner: TComponent; ACatalog: TDpccSettingsCatalog;
  const AFileName: string; const APreview: TDpccImportPreview; const AOnPreview: TDpccImportPreviewFunc);
var
  mButtons: TFlowPanel;
begin
  inherited CreateDialog(AOwner,
    TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsImportTitle, [ExtractFileName(AFileName)]), cImportWidth);
  FCatalog := ACatalog;
  FPreview := APreview;
  FOnPreview := AOnPreview;
  mButtons := NewDialogButtons(Self, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportApply), FApply,
    FCancel);
  FCount := TLabel.Create(Self);
  FCount.Parent := mButtons;
  FCount.AlignWithMargins := True;
  FCount.Margins.SetBounds(cGap, 4, 0, 0);
  FInfo := NewInfoLabel(Self, ImportInfo(APreview));
  FInfo.Visible := FInfo.Caption <> '';
  FMode := NewChoice(Self, '', cModeTop, [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportMerge),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportReplace)]);
  FMode.ItemIndex := Ord(APreview.Mode);
  FMode.OnClick := Recalculate;
  FAreaBoxes := NewAreaBoxes(Self, ACatalog, APreview.Areas, False, Recalculate, FAreaIds);
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(cGap, cGap, cGap, 0);
  FList.ViewStyle := vsReport;
  FList.Checkboxes := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.OnClick := ListChanged;
  FList.OnKeyUp := ListKeyUp;
  AddColumn(FList, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportColKey), ScaleValue(cKeyWidth));
  AddColumn(FList, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportColArea), ScaleValue(100));
  AddColumn(FList, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportColCurrent), ScaleValue(cValueWidth));
  AddColumn(FList, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportColNew), ScaleValue(cValueWidth));
  AddColumn(FList, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportColNote), ScaleValue(cNoteWidth));

  ClientHeight := ScaleValue(520);
end;

procedure TDpccImportDialog.DoShow;
begin
  inherited;
  if not FFilled then
  begin
    Fill;
  end;
end;

function TDpccImportDialog.ValueText(const AItem: TDpccImportItem; const AJson: string): string;
var
  mValue: Integer;
begin
  if AJson = '' then
  begin
    Exit(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportDefault));
  end;
  Result := TDpccJsonValues.Display(AJson);
  // Tastenkürzel wie im Menü.
  if (AItem.Entry >= 0) and (FCatalog[AItem.Entry].Format = 'shortcut') and TryStrToInt(Result, mValue) then
  begin
    Result := ShortCutToText(TShortCut(mValue));
    if Result = '' then
    begin
      Result := '–';
    end;
  end;
end;

function TDpccImportDialog.NoteText(const AItem: TDpccImportItem): string;
begin
  case AItem.Status of
    isSame:
      Result := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportSame);
    isReset:
      Result := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportReset);
    isUnknown:
      if FPreview.Newer then
      begin
        Result := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportUnknownNewer);
      end
      else
      begin
        Result := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportUnknown);
      end;
    isInvalid:
      Result := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsImportInvalid, [string.Join('; ',
        AItem.Issues)]);
    isSecret:
      Result := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportSecret);
    isSkipped:
      Result := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportSkipped);
  else
    Result := '';
  end;
  if AItem.Migrated then
  begin
    Result := Trim(Result + ' ' + TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsImportMigrated,
      [AItem.SourceKey]));
  end;
  if AItem.Covered <> '' then
  begin
    Result := Trim(Result + ' ' + TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsImportCovered,
      [AItem.Covered]));
  end;
end;

procedure TDpccImportDialog.Fill;
var
  mIndex: Integer;
  mItem: TDpccImportItem;
  mRow: TListItem;
  mArea: string;
begin
  FFilled := True;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mIndex := 0 to High(FPreview.Items) do
    begin
      mItem := FPreview.Items[mIndex];
      mRow := FList.Items.Add;
      mRow.Caption := mItem.Key;
      mArea := '';
      if mItem.Area <> '' then
      begin
        mArea := FCatalog.AreaCaption(mItem.Area, English);
      end;
      mRow.SubItems.Add(mArea);
      mRow.SubItems.Add(ValueText(mItem, mItem.CurrentJson));
      if mItem.Selectable then
      begin
        mRow.SubItems.Add(ValueText(mItem, mItem.NewJson));
      end
      else
      begin
        mRow.SubItems.Add(TDpccJsonValues.Display(mItem.NewJson));
      end;
      mRow.SubItems.Add(NoteText(mItem));
      mRow.Data := Pointer(NativeInt(mIndex));
      mRow.Checked := mItem.Selected and mItem.Selectable;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  SyncChecks;
end;

procedure TDpccImportDialog.SyncChecks;
var
  mRow: TListItem;
  mIndex, mSelected, mSelectable: Integer;
begin
  mSelected := 0;
  mSelectable := 0;
  for mRow in FList.Items do
  begin
    mIndex := NativeInt(mRow.Data);
    if (mIndex < 0) or (mIndex > High(FPreview.Items)) then
    begin
      Continue;
    end;
    // Übersprungene Einträge lassen sich nicht wählen.
    if not FPreview.Items[mIndex].Selectable then
    begin
      if mRow.Checked then
      begin
        mRow.Checked := False;
      end;
      Continue;
    end;
    Inc(mSelectable);
    FPreview.Items[mIndex].Selected := mRow.Checked;
    if mRow.Checked then
    begin
      Inc(mSelected);
    end;
  end;
  FCount.Caption := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsImportCount, [mSelected, mSelectable]);
  FApply.Enabled := mSelected > 0;
end;

procedure TDpccImportDialog.ListChanged(Sender: TObject);
begin
  SyncChecks;
end;

procedure TDpccImportDialog.ListKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  SyncChecks;
end;

procedure TDpccImportDialog.Recalculate(Sender: TObject);
var
  mAreas: TArray<string>;
  mIndex: Integer;
  mMode: TDpccImportMode;
begin
  if not Assigned(FOnPreview) then
  begin
    Exit;
  end;
  mAreas := nil;
  for mIndex := 0 to High(FAreaBoxes) do
  begin
    if FAreaBoxes[mIndex].Checked then
    begin
      mAreas := mAreas + [FAreaIds[mIndex]];
    end;
  end;
  mMode := imMerge;
  if FMode.ItemIndex = 1 then
  begin
    mMode := imReplace;
  end;
  // Keine Bereiche gewählt: leere Vorschau statt „alle“.
  if Length(mAreas) = 0 then
  begin
    FPreview.Items := nil;
    FPreview.Areas := nil;
    FPreview.Mode := mMode;
  end
  else
  begin
    FPreview := FOnPreview(mMode, mAreas);
  end;
  if HandleAllocated then
  begin
    Fill;
  end;
end;

function TDpccImportDialog.Result_: TDpccImportPreview;
begin
  if FFilled then
  begin
    SyncChecks;
  end;
  Result := FPreview;
end;

class function TDpccImportDialog.Execute(ACatalog: TDpccSettingsCatalog; const AFileName: string;
  var APreview: TDpccImportPreview; const AOnPreview: TDpccImportPreviewFunc; const APrepare: TProc<TForm>): Boolean;
var
  mDialog: TDpccImportDialog;
begin
  mDialog := TDpccImportDialog.CreateDialog(nil, ACatalog, AFileName, APreview, AOnPreview);
  try
    if Assigned(APrepare) then
    begin
      APrepare(mDialog);
    end;
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      APreview := mDialog.Result_;
    end;
  finally
    mDialog.Free;
  end;
end;

{ TDpccProfileDialog }

constructor TDpccProfileDialog.CreateDialog(AOwner: TComponent; const ANames, ADescriptions: TArray<string>);
var
  mButtons: TFlowPanel;
begin
  inherited CreateDialog(AOwner, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProfileTitle), cProfileWidth);
  FDescriptions := ADescriptions;
  mButtons := NewButtons(Self);
  FLoad := NewButton(Self, mButtons, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportButton));
  FLoad.ModalResult := mrOk;
  FLoad.Default := True;
  FCancel := NewButton(Self, mButtons, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDialogCancel));
  FCancel.ModalResult := mrCancel;
  FCancel.Cancel := True;
  FDescription := TLabel.Create(Self);
  FDescription.Parent := Self;
  FDescription.Align := alBottom;
  FDescription.AlignWithMargins := True;
  FDescription.Margins.SetBounds(cGap, cGap, cGap, 0);
  FDescription.WordWrap := True;
  FDescription.ShowAccelChar := False;
  FDescription.AutoSize := False;
  FDescription.Height := ScaleValue(48);
  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(cGap, cGap, cGap, 0);
  FList.OnClick := ListClick;
  FList.OnDblClick := ListDblClick;
  ClientHeight := ScaleValue(240);
  // Einträge erst mit Fenster (DoShow); die Namen bis dahin merken.
  FNames := ANames;
end;

procedure TDpccProfileDialog.ListDblClick(Sender: TObject);
begin
  if FList.ItemIndex >= 0 then
  begin
    ModalResult := mrOk;
  end;
end;

procedure TDpccProfileDialog.DoShow;
var
  mName: string;
begin
  inherited;
  if FList.Items.Count = 0 then
  begin
    for mName in FNames do
    begin
      FList.Items.Add(mName);
    end;
    if FList.Items.Count > 0 then
    begin
      FList.ItemIndex := 0;
    end;
    ListClick(nil);
  end;
end;

procedure TDpccProfileDialog.ListClick(Sender: TObject);
begin
  FDescription.Caption := '';
  if (FList.ItemIndex >= 0) and (FList.ItemIndex <= High(FDescriptions)) then
  begin
    FDescription.Caption := FDescriptions[FList.ItemIndex];
  end;
  FLoad.Enabled := FList.ItemIndex >= 0;
end;

class function TDpccProfileDialog.Choose(const ANames, ADescriptions: TArray<string>; out AIndex: Integer;
  const APrepare: TProc<TForm>): Boolean;
var
  mDialog: TDpccProfileDialog;
begin
  AIndex := -1;
  mDialog := TDpccProfileDialog.CreateDialog(nil, ANames, ADescriptions);
  try
    if Assigned(APrepare) then
    begin
      APrepare(mDialog);
    end;
    Result := (mDialog.ShowModal = mrOk) and (mDialog.List.ItemIndex >= 0);
    if Result then
    begin
      AIndex := mDialog.List.ItemIndex;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
