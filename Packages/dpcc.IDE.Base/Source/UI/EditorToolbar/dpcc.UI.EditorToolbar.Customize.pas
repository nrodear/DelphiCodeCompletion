unit dpcc.UI.EditorToolbar.Customize;

// dpcc-Editorleiste (#1101): Dialog „Leiste anpassen“. Links die verfügbaren
// Befehle der Befehlspalette (#600) samt „— Trennstrich —“, rechts die Knöpfe
// der Leiste mit Symbol in ihrer Reihenfolge. Dazwischen →/← (hinzufügen,
// entfernen), daneben ↑/↓ (verschieben); Doppelklick fügt hinzu bzw. entfernt.
// Darunter „Text neben den Symbolen“, die Position und „Standard
// wiederherstellen“. Der Dialog arbeitet auf einer Kopie (TDpccToolbarConfig);
// erst OK übernimmt sie. Die Listenschritte selbst stecken in
// TDpccToolbarItems (ohne VCL getestet). Die Listen werden erst mit Fenster
// gefüllt (TListBox.Items braucht eins), Änderungen ohne Fenster nur gemerkt.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  dpcc.UI.Foundation.Dialog;

type
  /// <summary>Ein Befehl, der in die Leiste kann (aus der Befehlspalette).</summary>
  TDpccToolbarCommandInfo = record
    Id: string;
    Caption: string;
    class function Create(const AId, ACaption: string): TDpccToolbarCommandInfo; static;
  end;

  /// <summary>Was der Dialog ändert.</summary>
  TDpccToolbarConfig = record
    Items: TArray<string>;
    Labels: Boolean;
    /// <summary>belowBreadcrumbs, aboveBreadcrumbs oder inBreadcrumbs.</summary>
    Position: string;
  end;

  TDpccToolbarCustomizeDialog = class(TDpccDialog)
  private
    FCommands: TArray<TDpccToolbarCommandInfo>;
    FConfig: TDpccToolbarConfig;
    /// <summary>Kennungen der linken Liste in Anzeigereihenfolge (zuerst der Trennstrich).</summary>
    FAvailable: TArray<string>;
    FAvailableList: TListBox;
    FCurrentList: TListBox;
    FAddButton: TButton;
    FRemoveButton: TButton;
    FUpButton: TButton;
    FDownButton: TButton;
    FLabelsCheck: TCheckBox;
    FPositionCombo: TComboBox;
    FOk: TButton;
    FCancel: TButton;
    FFilled: Boolean;
    procedure BuildAvailable;
    procedure Fill(ACurrentIndex, AAvailableIndex: Integer);
    procedure UpdateButtons;
    /// <summary>Knopf mit Aktion im Tag (TDpccToolbarCustomizeAction).</summary>
    procedure ActionClick(Sender: TObject);
    /// <summary>Doppelklick: links hinzufügen, rechts entfernen.</summary>
    procedure ListDblClick(Sender: TObject);
    procedure ListClick(Sender: TObject);
    procedure LabelsClick(Sender: TObject);
    procedure PositionChange(Sender: TObject);
    procedure CurrentDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const ACommands: TArray<TDpccToolbarCommandInfo>;
      const AConfig: TDpccToolbarConfig);
    /// <summary>Beschriftung zur Kennung; '|' ist der Trennstrich, unbekannte Kennungen bleiben, wie sie
    /// sind.</summary>
    function CaptionOf(const AId: string): string;
    /// <summary>Linke Liste: Kennungen in Anzeigereihenfolge (Trennstrich zuerst, dann nach Beschriftung).</summary>
    function Available: TArray<string>;
    /// <summary>Eintrag AAvailableIndex der linken Liste vor AIndex einfügen; liefert den neuen Index oder
    /// -1.</summary>
    function AddItem(AAvailableIndex, AIndex: Integer): Integer;
    function RemoveItem(AIndex: Integer): Boolean;
    function MoveItem(AIndex, ADelta: Integer): Integer;
    procedure RestoreDefault;
    procedure SetLabels(AValue: Boolean);
    procedure SetPosition(const AValue: string);
    property Config: TDpccToolbarConfig read FConfig;
    property AvailableList: TListBox read FAvailableList;
    property CurrentList: TListBox read FCurrentList;
    property OkButton: TButton read FOk;
    property CancelButton: TButton read FCancel;
    /// <summary>Zeigt den Dialog modal; True und die neue Belegung in AConfig bei OK.</summary>
    class function Execute(const ACommands: TArray<TDpccToolbarCommandInfo>;
      var AConfig: TDpccToolbarConfig): Boolean; static;
  end;

const
  /// <summary>Werte von editor.toolbar.position in der Reihenfolge der Auswahl.</summary>
  cDpccToolbarPositions: array[0..2] of string = ('belowBreadcrumbs', 'aboveBreadcrumbs', 'inBreadcrumbs');

implementation

uses
  dpcc.Core.Settings.ToolbarItems,
  dpcc.Core.EditorToolbar.Icons,
  System.Math,
  System.UITypes,
  System.Generics.Collections,
  System.Generics.Defaults,
  dpcc.UI.Strings,
  dpcc.UI.EditorToolbar.Strings,
  dpcc.UI.EditorToolbar.Glyphs;

const
  cGap = 8;
  cDialogWidth = 640;

type
{$SCOPEDENUMS ON}
  /// <summary>Aktion eines Knopfs (im Tag).</summary>
  TDpccToolbarCustomizeAction = (None, Add, Remove, Up, Down, Default, Ok);
{$SCOPEDENUMS OFF}

  /// <summary>Baut die Steuerelemente des Dialogs: untere Knopfleiste, Optionen und die Listen.</summary>
  TDpccToolbarCustomizeBuilder = record
    Dialog: TDpccToolbarCustomizeDialog;
    function NewPanel(AParent: TWinControl; AAlign: TAlign; ASize: Integer): TPanel;
    function NewButton(AParent: TWinControl; const ACaption, AHint: string;
      AAction: TDpccToolbarCustomizeAction): TButton;
    function NewList(AParent: TWinControl): TListBox;
    procedure BuildBottom;
    procedure BuildOptions;
    procedure BuildLists;
    procedure BuildHeading;
  end;

function TDpccToolbarCustomizeBuilder.NewPanel(AParent: TWinControl; AAlign: TAlign; ASize: Integer): TPanel;
begin
  Result := TPanel.Create(Dialog);
  Result.Parent := AParent;
  Result.Align := AAlign;
  Result.BevelOuter := bvNone;
  if AAlign in [alLeft, alRight] then
  begin
    Result.Width := ASize;
  end
  else if AAlign in [alTop, alBottom] then
  begin
    Result.Height := ASize;
  end;
end;

function TDpccToolbarCustomizeBuilder.NewButton(AParent: TWinControl; const ACaption, AHint: string;
  AAction: TDpccToolbarCustomizeAction): TButton;
begin
  Result := TButton.Create(Dialog);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.Tag := Ord(AAction);
  if AAction <> TDpccToolbarCustomizeAction.None then
  begin
    Result.OnClick := Dialog.ActionClick;
  end;
  Dialog.Canvas.Font := Dialog.Font;
  Result.Width := Max(Dialog.ScaleValue(90), Dialog.Canvas.TextWidth(ACaption) + Dialog.ScaleValue(32));
  Result.Top := Dialog.ScaleValue(cGap);
  Result.Height := Dialog.ScaleValue(28);
end;

function TDpccToolbarCustomizeBuilder.NewList(AParent: TWinControl): TListBox;
begin
  Result := TListBox.Create(Dialog);
  Result.Parent := AParent;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(Dialog.ScaleValue(cGap), Dialog.ScaleValue(4), 0, Dialog.ScaleValue(cGap));
  Result.OnClick := Dialog.ListClick;
  Result.OnDblClick := Dialog.ListDblClick;
end;

procedure TDpccToolbarCustomizeBuilder.BuildBottom;
var
  mBottom: TPanel;
  mDefault: TButton;
begin
  mBottom := NewPanel(Dialog, alBottom, Dialog.ScaleValue(44));
  Dialog.FCancel := NewButton(mBottom, TDpccEditorToolbarStrings.Text(TDpccEditorToolbarTextId.EditorToolbarCancel),
    '',
    TDpccToolbarCustomizeAction.None);
  Dialog.FCancel.Cancel := True;
  Dialog.FCancel.ModalResult := mrCancel;
  Dialog.FCancel.Left := mBottom.ClientWidth - Dialog.FCancel.Width - Dialog.ScaleValue(cGap);
  Dialog.FCancel.Anchors := [akTop, akRight];
  Dialog.FOk := NewButton(mBottom, TDpccEditorToolbarStrings.Text(TDpccEditorToolbarTextId.EditorToolbarOk), '',
    TDpccToolbarCustomizeAction.Ok);
  Dialog.FOk.Default := True;
  Dialog.FOk.Left := Dialog.FCancel.Left - Dialog.FOk.Width - Dialog.ScaleValue(cGap);
  Dialog.FOk.Anchors := [akTop, akRight];
  mDefault := NewButton(mBottom, TDpccEditorToolbarStrings.Text(TDpccEditorToolbarTextId.EditorToolbarRestoreDefault),
    '',
    TDpccToolbarCustomizeAction.Default);
  mDefault.Left := Dialog.ScaleValue(cGap);
end;

procedure TDpccToolbarCustomizeBuilder.BuildOptions;
var
  mOptions: TPanel;
  mCaption: TLabel;
begin
  mOptions := NewPanel(Dialog, alBottom, Dialog.ScaleValue(36));
  Dialog.FLabelsCheck := TCheckBox.Create(Dialog);
  Dialog.FLabelsCheck.Parent := mOptions;
  Dialog.FLabelsCheck.Caption := TDpccStrings.Text(TDpccTextId.EditorToolbarLabels);
  Dialog.FLabelsCheck.SetBounds(Dialog.ScaleValue(cGap), Dialog.ScaleValue(cGap), Dialog.ScaleValue(220),
    Dialog.ScaleValue(20));
  Dialog.FLabelsCheck.Checked := Dialog.FConfig.Labels;
  Dialog.FLabelsCheck.OnClick := Dialog.LabelsClick;
  mCaption := TLabel.Create(Dialog);
  mCaption.Parent := mOptions;
  mCaption.Caption := TDpccStrings.Text(TDpccTextId.EditorToolbarPosition);
  mCaption.SetBounds(Dialog.ScaleValue(250), Dialog.ScaleValue(cGap + 2), Dialog.ScaleValue(70), Dialog.ScaleValue(20));
  Dialog.FPositionCombo := TComboBox.Create(Dialog);
  Dialog.FPositionCombo.Parent := mOptions;
  Dialog.FPositionCombo.Style := csDropDownList;
  Dialog.FPositionCombo.SetBounds(Dialog.ScaleValue(330), Dialog.ScaleValue(cGap - 2), Dialog.ScaleValue(240),
    Dialog.ScaleValue(24));
  Dialog.FPositionCombo.OnChange := Dialog.PositionChange;
  mCaption.FocusControl := Dialog.FPositionCombo;
end;

procedure TDpccToolbarCustomizeBuilder.BuildLists;
var
  mLists, mMiddle, mSide: TPanel;
begin
  mLists := NewPanel(Dialog, alClient, 0);
  // Links verfügbar, Mitte → ←, rechts die Leiste, ganz rechts ↑ ↓.
  mSide := NewPanel(mLists, alRight, Dialog.ScaleValue(48));
  Dialog.FUpButton := NewButton(mSide, '↑',
    TDpccEditorToolbarStrings.Text(TDpccEditorToolbarTextId.EditorToolbarUpHint),
    TDpccToolbarCustomizeAction.Up);
  Dialog.FUpButton.SetBounds(Dialog.ScaleValue(cGap), Dialog.ScaleValue(80), Dialog.ScaleValue(32),
    Dialog.ScaleValue(28));
  Dialog.FDownButton := NewButton(mSide, '↓',
    TDpccEditorToolbarStrings.Text(TDpccEditorToolbarTextId.EditorToolbarDownHint),
    TDpccToolbarCustomizeAction.Down);
  Dialog.FDownButton.SetBounds(Dialog.ScaleValue(cGap), Dialog.ScaleValue(116), Dialog.ScaleValue(32),
    Dialog.ScaleValue(28));
  Dialog.FCurrentList := NewList(mLists);
  Dialog.FCurrentList.Align := alRight;
  Dialog.FCurrentList.Width := Dialog.ScaleValue(260);
  Dialog.FCurrentList.Style := lbOwnerDrawFixed;
  Dialog.FCurrentList.ItemHeight := Dialog.ScaleValue(24);
  Dialog.FCurrentList.OnDrawItem := Dialog.CurrentDrawItem;
  mMiddle := NewPanel(mLists, alRight, Dialog.ScaleValue(56));
  Dialog.FAddButton := NewButton(mMiddle, '→',
    TDpccEditorToolbarStrings.Text(TDpccEditorToolbarTextId.EditorToolbarAddHint),
    TDpccToolbarCustomizeAction.Add);
  Dialog.FAddButton.SetBounds(Dialog.ScaleValue(12), Dialog.ScaleValue(80), Dialog.ScaleValue(32),
    Dialog.ScaleValue(28));
  Dialog.FRemoveButton := NewButton(mMiddle, '←',
    TDpccEditorToolbarStrings.Text(TDpccEditorToolbarTextId.EditorToolbarRemoveHint),
    TDpccToolbarCustomizeAction.Remove);
  Dialog.FRemoveButton.SetBounds(Dialog.ScaleValue(12), Dialog.ScaleValue(116), Dialog.ScaleValue(32),
    Dialog.ScaleValue(28));
  Dialog.FAvailableList := NewList(mLists);
  Dialog.FAvailableList.Align := alClient;
end;

procedure TDpccToolbarCustomizeBuilder.BuildHeading;
var
  mCaption: TLabel;
begin
  // Überschriften über den Listen.
  mCaption := TLabel.Create(Dialog);
  mCaption.Parent := Dialog;
  mCaption.Align := alTop;
  mCaption.AlignWithMargins := True;
  mCaption.Margins.SetBounds(Dialog.ScaleValue(cGap), Dialog.ScaleValue(cGap), Dialog.ScaleValue(cGap), 0);
  mCaption.ShowAccelChar := False;
  mCaption.Caption := TDpccEditorToolbarStrings.Text(TDpccEditorToolbarTextId.EditorToolbarAvailable) + '  ›  ' +
    TDpccEditorToolbarStrings.Text(TDpccEditorToolbarTextId.EditorToolbarCurrent);
end;

{ TDpccToolbarCommandInfo }

class function TDpccToolbarCommandInfo.Create(const AId, ACaption: string): TDpccToolbarCommandInfo;
begin
  Result.Id := AId;
  Result.Caption := ACaption;
end;

{ TDpccToolbarCustomizeDialog }

constructor TDpccToolbarCustomizeDialog.CreateDialog(AOwner: TComponent;
  const ACommands: TArray<TDpccToolbarCommandInfo>; const AConfig: TDpccToolbarConfig);
var
  mBuilder: TDpccToolbarCustomizeBuilder;
  mPosition: string;
begin
  inherited CreateDialog(AOwner, '', cDialogWidth);
  FCommands := ACommands;
  FConfig := AConfig;
  FConfig.Items := TDpccToolbarItems.Clean(AConfig.Items);
  Caption := TDpccEditorToolbarStrings.Text(TDpccEditorToolbarTextId.EditorToolbarCustomizeTitle);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  ClientHeight := ScaleValue(440);
  Constraints.MinWidth := ScaleValue(480);
  Constraints.MinHeight := ScaleValue(320);
  mBuilder.Dialog := Self;
  mBuilder.BuildBottom;
  mBuilder.BuildOptions;
  mBuilder.BuildLists;
  mBuilder.BuildHeading;
  ShowHint := True;
  BuildAvailable;
  for mPosition in cDpccToolbarPositions do
  begin
    if SameText(mPosition, FConfig.Position) then
    begin
      FConfig.Position := mPosition;
    end;
  end;
  if FConfig.Position = '' then
  begin
    FConfig.Position := cDpccToolbarPositions[0];
  end;
end;

function TDpccToolbarCustomizeDialog.CaptionOf(const AId: string): string;
var
  mCommand: TDpccToolbarCommandInfo;
begin
  if TDpccToolbarItems.IsSeparator(AId) then
  begin
    Exit(TDpccEditorToolbarStrings.Text(TDpccEditorToolbarTextId.EditorToolbarSeparator));
  end;
  for mCommand in FCommands do
  begin
    if SameText(mCommand.Id, AId) then
    begin
      Exit(mCommand.Caption);
    end;
  end;
  Result := AId;
end;

procedure TDpccToolbarCustomizeDialog.BuildAvailable;
var
  mCommand: TDpccToolbarCommandInfo;
  mItem: string;
  mUsed: Boolean;
  mRest: TList<TDpccToolbarCommandInfo>;
begin
  mRest := TList<TDpccToolbarCommandInfo>.Create;
  try
    for mCommand in FCommands do
    begin
      mUsed := False;
      for mItem in FConfig.Items do
      begin
        if SameText(mItem, mCommand.Id) then
        begin
          mUsed := True;
        end;
      end;
      if not mUsed then
      begin
        mRest.Add(mCommand);
      end;
    end;
    mRest.Sort(TComparer<TDpccToolbarCommandInfo>.Construct(
      function(const A, B: TDpccToolbarCommandInfo): Integer
      begin
        Result := CompareText(A.Caption, B.Caption);
      end));
    FAvailable := [TDpccToolbarItems.cSeparator];
    for mCommand in mRest do
    begin
      FAvailable := FAvailable + [mCommand.Id];
    end;
  finally
    mRest.Free;
  end;
end;

function TDpccToolbarCustomizeDialog.Available: TArray<string>;
begin
  Result := FAvailable;
end;

function TDpccToolbarCustomizeDialog.AddItem(AAvailableIndex, AIndex: Integer): Integer;
var
  mNext: Integer;
begin
  if (AAvailableIndex < 0) or (AAvailableIndex > High(FAvailable)) then
  begin
    Exit(-1);
  end;
  Result := TDpccToolbarItems.Add(FConfig.Items, FAvailable[AAvailableIndex], AIndex);
  if Result < 0 then
  begin
    Exit;
  end;
  BuildAvailable;
  // Links bleibt die Auswahl an derselben Stelle (der Trennstrich bleibt stehen).
  mNext := Min(AAvailableIndex, High(FAvailable));
  Fill(Result, mNext);
end;

function TDpccToolbarCustomizeDialog.RemoveItem(AIndex: Integer): Boolean;
begin
  Result := TDpccToolbarItems.Remove(FConfig.Items, AIndex);
  if not Result then
  begin
    Exit;
  end;
  BuildAvailable;
  Fill(Min(AIndex, High(FConfig.Items)), -1);
end;

function TDpccToolbarCustomizeDialog.MoveItem(AIndex, ADelta: Integer): Integer;
begin
  Result := TDpccToolbarItems.Move(FConfig.Items, AIndex, ADelta);
  Fill(Result, -1);
end;

procedure TDpccToolbarCustomizeDialog.RestoreDefault;
begin
  FConfig.Items := TDpccToolbarItems.Default;
  FConfig.Labels := False;
  FConfig.Position := cDpccToolbarPositions[0];
  BuildAvailable;
  Fill(-1, -1);
end;

procedure TDpccToolbarCustomizeDialog.SetLabels(AValue: Boolean);
begin
  FConfig.Labels := AValue;
  if FFilled and (FLabelsCheck.Checked <> AValue) then
  begin
    FLabelsCheck.Checked := AValue;
  end;
end;

procedure TDpccToolbarCustomizeDialog.SetPosition(const AValue: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(cDpccToolbarPositions) do
  begin
    if SameText(cDpccToolbarPositions[mIndex], AValue) then
    begin
      FConfig.Position := cDpccToolbarPositions[mIndex];
      if FFilled then
      begin
        FPositionCombo.ItemIndex := mIndex;
      end;
    end;
  end;
end;

procedure TDpccToolbarCustomizeDialog.DoShow;
begin
  inherited DoShow;
  Fill(-1, -1);
end;

procedure TDpccToolbarCustomizeDialog.Fill(ACurrentIndex, AAvailableIndex: Integer);
var
  mItem: string;
  mIndex: Integer;
begin
  // Ohne Fenster bleibt es bei FConfig; DoShow füllt dann.
  if not HandleAllocated then
  begin
    Exit;
  end;
  FFilled := True;
  FAvailableList.Items.BeginUpdate;
  try
    FAvailableList.Items.Clear;
    for mItem in FAvailable do
    begin
      FAvailableList.Items.Add(CaptionOf(mItem));
    end;
  finally
    FAvailableList.Items.EndUpdate;
  end;
  FCurrentList.Items.BeginUpdate;
  try
    FCurrentList.Items.Clear;
    for mItem in FConfig.Items do
    begin
      FCurrentList.Items.Add(CaptionOf(mItem));
    end;
  finally
    FCurrentList.Items.EndUpdate;
  end;
  FCurrentList.ItemIndex := ACurrentIndex;
  FAvailableList.ItemIndex := AAvailableIndex;
  FLabelsCheck.Checked := FConfig.Labels;
  if FPositionCombo.Items.Count = 0 then
  begin
    FPositionCombo.Items.Add(TDpccStrings.Text(TDpccTextId.EditorToolbarPositionBelow));
    FPositionCombo.Items.Add(TDpccStrings.Text(TDpccTextId.EditorToolbarPositionAbove));
    FPositionCombo.Items.Add(TDpccStrings.Text(TDpccTextId.EditorToolbarPositionInline));
  end;
  FPositionCombo.ItemIndex := 0;
  for mIndex := 0 to High(cDpccToolbarPositions) do
  begin
    if cDpccToolbarPositions[mIndex] = FConfig.Position then
    begin
      FPositionCombo.ItemIndex := mIndex;
    end;
  end;
  UpdateButtons;
end;

procedure TDpccToolbarCustomizeDialog.UpdateButtons;
var
  mCurrent: Integer;
begin
  mCurrent := FCurrentList.ItemIndex;
  FAddButton.Enabled := FAvailableList.ItemIndex >= 0;
  FRemoveButton.Enabled := mCurrent >= 0;
  FUpButton.Enabled := mCurrent > 0;
  FDownButton.Enabled := (mCurrent >= 0) and (mCurrent < High(FConfig.Items));
end;

procedure TDpccToolbarCustomizeDialog.ListClick(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TDpccToolbarCustomizeDialog.ActionClick(Sender: TObject);
var
  mTarget: Integer;
begin
  case TDpccToolbarCustomizeAction(TComponent(Sender).Tag) of
    TDpccToolbarCustomizeAction.Add:
      begin
        // Hinter dem ausgewählten Knopf der Leiste einfügen, sonst hinten.
        mTarget := Length(FConfig.Items);
        if FCurrentList.ItemIndex >= 0 then
        begin
          mTarget := FCurrentList.ItemIndex + 1;
        end;
        AddItem(FAvailableList.ItemIndex, mTarget);
      end;
    TDpccToolbarCustomizeAction.Remove:
      RemoveItem(FCurrentList.ItemIndex);
    TDpccToolbarCustomizeAction.Up:
      MoveItem(FCurrentList.ItemIndex, -1);
    TDpccToolbarCustomizeAction.Down:
      MoveItem(FCurrentList.ItemIndex, 1);
    TDpccToolbarCustomizeAction.Default:
      RestoreDefault;
    TDpccToolbarCustomizeAction.Ok:
      begin
        // Trennstriche am Rand oder doppelt fallen beim Übernehmen weg.
        FConfig.Items := TDpccToolbarItems.Clean(FConfig.Items);
        ModalResult := mrOk;
      end;
  else
    // None: Abbrechen schließt über ModalResult.
  end;
end;

procedure TDpccToolbarCustomizeDialog.ListDblClick(Sender: TObject);
begin
  if Sender = FAvailableList then
  begin
    ActionClick(FAddButton);
  end
  else
  begin
    ActionClick(FRemoveButton);
  end;
end;

procedure TDpccToolbarCustomizeDialog.LabelsClick(Sender: TObject);
begin
  FConfig.Labels := FLabelsCheck.Checked;
end;

procedure TDpccToolbarCustomizeDialog.PositionChange(Sender: TObject);
begin
  if (FPositionCombo.ItemIndex >= 0) and (FPositionCombo.ItemIndex <= High(cDpccToolbarPositions)) then
  begin
    FConfig.Position := cDpccToolbarPositions[FPositionCombo.ItemIndex];
  end;
end;

procedure TDpccToolbarCustomizeDialog.CurrentDrawItem(Control: TWinControl; Index: Integer; Rect: TRect;
  State: TOwnerDrawState);
var
  mList: TListBox;
  mId: string;
  mIcon, mText: TRect;
  mCaption_: string;
  mSize, mMiddle: Integer;
begin
  mList := TListBox(Control);
  mList.Canvas.FillRect(Rect);
  if (Index < 0) or (Index > High(FConfig.Items)) then
  begin
    Exit;
  end;
  mId := FConfig.Items[Index];
  mCaption_ := CaptionOf(mId);
  mSize := ScaleValue(16);
  mIcon := System.Types.Rect(Rect.Left + ScaleValue(4), Rect.Top + (Rect.Height - mSize) div 2,
    Rect.Left + ScaleValue(4) + mSize, Rect.Top + (Rect.Height - mSize) div 2 + mSize);
  if TDpccToolbarItems.IsSeparator(mId) then
  begin
    mMiddle := (Rect.Top + Rect.Bottom) div 2;
    mList.Canvas.Pen.Color := mList.Canvas.Font.Color;
    mList.Canvas.MoveTo(mIcon.Left, mMiddle);
    mList.Canvas.LineTo(mIcon.Right, mMiddle);
  end
  else
  begin
    TDpccGlyphPainter.Draw(mList.Canvas, TDpccToolbarIcons.IconOf(mId), mIcon, mList.Canvas.Font.Color,
      mList.Canvas.Brush.Color, mCaption_);
  end;
  mText := System.Types.Rect(mIcon.Right + ScaleValue(6), Rect.Top, Rect.Right - ScaleValue(2), Rect.Bottom);
  mList.Canvas.Brush.Style := bsClear;
  DrawText(mList.Canvas.Handle, PChar(mCaption_), -1, mText, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  mList.Canvas.Brush.Style := bsSolid;
end;

class function TDpccToolbarCustomizeDialog.Execute(const ACommands: TArray<TDpccToolbarCommandInfo>;
  var AConfig: TDpccToolbarConfig): Boolean;
var
  mDialog: TDpccToolbarCustomizeDialog;
begin
  mDialog := TDpccToolbarCustomizeDialog.CreateDialog(nil, ACommands, AConfig);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AConfig := mDialog.Config;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
