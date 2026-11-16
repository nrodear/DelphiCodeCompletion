unit dpcc.UI.Foundation.Dialog;

// Gemeinsame Basis der im Code gebauten dpcc-Dialoge (#2062). Vorher setzte
// jeder der 61 Dialoge Rahmen, Position, Schrift und Breite selbst, baute
// eigene Knopf-Helfer (46 Units) und färbte Fehlertexte mit clRed; 36 Dialoge
// bekamen nie das Thema der IDE. TDpccDialog bringt mit:
// - CreateDialog: CreateNew, bsDialog, poMainFormCenter, Dialogschrift aus
//   TDpccUiTheme, Breite in logischen Pixeln (96 dpi), Abo beim Themendienst;
// - DoShow: IDE-Thema an der Wurzel (Kinder erben den Stil), ThemeChanged bei
//   jedem Wechsel, solange der Dialog lebt; Abmelden im Destroy;
// - AddRow, AddLabel, AddButtonRow, AddNote: Zeilen von oben nach unten,
//   Größen in logischen Pixeln, skaliert über das Formular;
// - FitHeight: Höhe bis unter das letzte Element;
// - AllowResize: Rahmen ziehbar, die gebaute Größe ist die kleinste; eine
//   Zeile (Liste, Textfeld) nimmt zusätzliche Höhe, alles darunter bleibt
//   unten. Felder, die mitwachsen sollen, verankert der Dialog rechts
//   (FitRight).
// TDpccButtonRow misst die Knöpfe nach ihrem Text, TDpccNoteLabel zeigt
// Hinweise in der Textfarbe der Palette (Fehler, Warnung, Ok); Hinweise ohne
// Aussage zeichnet der Stil. Eigene Farben holt ein Dialog in ThemeChanged.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  dpcc.Core.Style.Signal;

type
{$SCOPEDENUMS ON}
  /// <summary>Rolle eines Knopfs: normal, Vorgabe (Eingabetaste) oder Abbrechen (Esc, mrCancel).</summary>
  TDpccButtonKind = (Plain, Default, Cancel);
{$SCOPEDENUMS OFF}

  /// <summary>Knopfleiste eines Dialogs; Knöpfe von links nach rechts, Breite nach Text.</summary>
  TDpccButtonRow = class(TFlowPanel)
  public const
    /// <summary>Mindestbreite und Rand rechts und links des Texts, logische Pixel.</summary>
    cButtonMinWidth = 75;
    cButtonPadding = 32;
    cButtonGap = 8;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Knopf anfügen; Breite aus dem Text in der Schrift der Leiste.</summary>
    function AddButton(const ACaption: string; AKind: TDpccButtonKind): TButton; overload;
    /// <summary>Normalen Knopf anfügen.</summary>
    function AddButton(const ACaption: string): TButton; overload;
    /// <summary>Breite eines Knopfs mit ACaption in Gerätepixeln.</summary>
    function ButtonWidth(const ACaption: string): Integer;
  end;

  /// <summary>Hinweis- oder Fehlerzeile eines Dialogs in der Textfarbe der Palette; folgt dem Thema.</summary>
  TDpccNoteLabel = class(TLabel)
  private
    FKind: TDpccSignalKind;
    procedure ApplyKind;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Text und Bedeutung setzen; leerer Text leert die Zeile.</summary>
    procedure ShowNote(const AText: string; AKind: TDpccSignalKind);
    property Kind: TDpccSignalKind read FKind;
  end;

  TDpccDialog = class(TForm)
  public const
    /// <summary>Abstand am Rand und zwischen Zeilen, logische Pixel.</summary>
    cRowGap = 8;
    /// <summary>Abstand einer Beschriftung vom oberen Rand ihrer Zeile, logische Pixel.</summary>
    cRowLabelTop = 4;
  private
    procedure HandleThemeChanged;
  protected
    /// <summary>Thema anwenden, bevor das Fenster sichtbar wird: Das IDE-Thema setzt StyleName und erzeugt das
    /// Fenster neu; mitten im Anzeigen (DoShow) bricht die VCL das mit einem Fehler ab.</summary>
    procedure VisibleChanging; override;
    /// <summary>Thema der IDE hat gewechselt (nach dem Anwenden an der Wurzel): eigene Farben neu holen.</summary>
    procedure ThemeChanged; virtual;
    /// <summary>Oberkante unter dem bisher untersten Element (alTop stapelt nach Top).</summary>
    function NextTop: Integer;
  public
    /// <summary>Leeren Dialog mit Titel ACaption und Innenbreite AWidth96 (logische Pixel) anlegen.</summary>
    constructor CreateDialog(AOwner: TComponent; const ACaption: string; AWidth96: Integer);
    destructor Destroy; override;
    /// <summary>Zeile ohne Rahmen mit Höhe AHeight96 (logische Pixel) unter dem bisher Untersten.</summary>
    function AddRow(AHeight96: Integer): TPanel;
    /// <summary>Beschriftung links in AParent.</summary>
    function AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
    /// <summary>Knopfleiste unter dem bisher Untersten.</summary>
    function AddButtonRow: TDpccButtonRow;
    /// <summary>Hinweiszeile mit Höhe AHeight96 (logische Pixel) unter dem bisher Untersten; anfangs leer.</summary>
    function AddNote(AHeight96: Integer): TDpccNoteLabel;
    /// <summary>Innenhöhe bis unter das unterste Element plus Rand.</summary>
    procedure FitHeight;
    /// <summary>Größe ziehbar machen, nachdem alles gebaut ist: Rahmen bsSizeable, die jetzige Größe ist die
    /// kleinste. AGrow (direktes Kind, alTop) nimmt zusätzliche Höhe auf, die alTop-Elemente darunter bleiben
    /// am unteren Rand; ohne AGrow (nil) nur breiter. In frei gesetzten Dialogen (alNone) wird AGrow unten
    /// verankert und alles darunter vom oberen an den unteren Rand umgehängt.</summary>
    procedure AllowResize(AGrow: TControl);
    /// <summary>AControl wächst mit der Breite seiner Zeile: rechter Rand wie der linke Abstand zur Zeile, oder
    /// bündig, wenn es links bei 0 steht.</summary>
    procedure FitRight(AControl: TControl);
  end;

implementation

uses
  System.Math,
  Vcl.Graphics,
  dpcc.UI.Foundation.Theme;

{ TDpccButtonRow }

constructor TDpccButtonRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Align := alTop;
  AutoSize := True;
  BevelOuter := bvNone;
  Caption := '';
  AlignWithMargins := True;
end;

function TDpccButtonRow.ButtonWidth(const ACaption: string): Integer;
var
  mBitmap: TBitmap;
begin
  mBitmap := TBitmap.Create;
  try
    // Font.Height ist schon in Gerätepixeln der Leiste.
    mBitmap.Canvas.Font.Assign(Font);
    Result := mBitmap.Canvas.TextWidth(ACaption) + ScaleValue(cButtonPadding);
  finally
    mBitmap.Free;
  end;
  if Result < ScaleValue(cButtonMinWidth) then
  begin
    Result := ScaleValue(cButtonMinWidth);
  end;
end;

function TDpccButtonRow.AddButton(const ACaption: string; AKind: TDpccButtonKind): TButton;
begin
  Result := TButton.Create(Owner);
  Result.Parent := Self;
  Result.Caption := ACaption;
  Result.Width := ButtonWidth(ACaption);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, ScaleValue(cButtonGap), ScaleValue(cButtonGap div 2));
  Result.Default := AKind = TDpccButtonKind.Default;
  Result.Cancel := AKind = TDpccButtonKind.Cancel;
  if Result.Cancel then
  begin
    Result.ModalResult := mrCancel;
  end;
end;

function TDpccButtonRow.AddButton(const ACaption: string): TButton;
begin
  Result := AddButton(ACaption, TDpccButtonKind.Plain);
end;

{ TDpccNoteLabel }

constructor TDpccNoteLabel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FKind := TDpccSignalKind.Info;
  Caption := '';
  WordWrap := True;
  TDpccUiTheme.Subscribe(Self,
    procedure
    begin
      ApplyKind;
    end);
end;

destructor TDpccNoteLabel.Destroy;
begin
  TDpccUiTheme.Unsubscribe(Self);
  inherited;
end;

procedure TDpccNoteLabel.ApplyKind;
begin
  // Mit seFont zeichnet der VCL-Stil die Schrift in seiner Textfarbe und übergeht Font.Color.
  if TDpccUiTheme.UsesStyleText(FKind) then
  begin
    StyleElements := StyleElements + [seFont];
  end
  else
  begin
    StyleElements := StyleElements - [seFont];
  end;
  Font.Color := TDpccUiTheme.TextColor(FKind);
end;

procedure TDpccNoteLabel.ShowNote(const AText: string; AKind: TDpccSignalKind);
begin
  FKind := AKind;
  ApplyKind;
  Caption := AText;
end;

{ TDpccDialog }

constructor TDpccDialog.CreateDialog(AOwner: TComponent; const ACaption: string; AWidth96: Integer);
begin
  inherited CreateNew(AOwner);
  Caption := ACaption;
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  TDpccUiTheme.AssignDialogFont(Font);
  ClientWidth := ScaleValue(AWidth96);
  TDpccUiTheme.Subscribe(Self,
    procedure
    begin
      HandleThemeChanged;
    end);
end;

destructor TDpccDialog.Destroy;
begin
  TDpccUiTheme.Unsubscribe(Self);
  inherited;
end;

procedure TDpccDialog.VisibleChanging;
begin
  if not Visible then
  begin
    TDpccUiTheme.Apply(Self);
  end;
  inherited;
end;

procedure TDpccDialog.HandleThemeChanged;
begin
  TDpccUiTheme.Apply(Self);
  ThemeChanged;
end;

procedure TDpccDialog.ThemeChanged;
begin
end;

function TDpccDialog.NextTop: Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to ControlCount - 1 do
  begin
    if Controls[mIndex].Top + Controls[mIndex].Height + 1 > Result then
    begin
      Result := Controls[mIndex].Top + Controls[mIndex].Height + 1;
    end;
  end;
end;

function TDpccDialog.AddRow(AHeight96: Integer): TPanel;
var
  mTop: Integer;
begin
  mTop := NextTop;
  Result := TPanel.Create(Self);
  // Lage vor Align und Parent: Sonst ordnet die VCL alTop-Zeilen beim Anlegen des Fensters nach der
  // vorläufigen Lage und kann die Reihenfolge vertauschen.
  Result.Top := mTop;
  Result.Height := ScaleValue(AHeight96);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(cRowGap), ScaleValue(cRowGap div 2), ScaleValue(cRowGap), 0);
  Result.BevelOuter := bvNone;
  Result.Caption := '';
  Result.Align := alTop;
  Result.Parent := Self;
end;

function TDpccDialog.AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := 0;
  Result.Top := ScaleValue(cRowLabelTop);
end;

function TDpccDialog.AddButtonRow: TDpccButtonRow;
var
  mTop: Integer;
begin
  mTop := NextTop;
  Result := TDpccButtonRow.Create(Self);
  Result.Parent := Self;
  Result.Margins.SetBounds(ScaleValue(cRowGap), ScaleValue(cRowGap), ScaleValue(cRowGap), ScaleValue(cRowGap));
  Result.Top := mTop;
end;

function TDpccDialog.AddNote(AHeight96: Integer): TDpccNoteLabel;
var
  mRow: TPanel;
begin
  mRow := AddRow(AHeight96);
  Result := TDpccNoteLabel.Create(Self);
  Result.Parent := mRow;
  Result.Align := alClient;
end;

procedure TDpccDialog.FitHeight;
begin
  ClientHeight := NextTop + ScaleValue(cRowGap);
end;

procedure TDpccDialog.AllowResize(AGrow: TControl);
var
  mIndex, mClientWidth, mClientHeight: Integer;
  mControl: TControl;
begin
  mClientWidth := ClientWidth;
  mClientHeight := ClientHeight;
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  // Der breitere Rahmen nimmt sonst Platz vom Inhalt.
  ClientWidth := mClientWidth;
  ClientHeight := mClientHeight;
  Constraints.MinWidth := Width;
  Constraints.MinHeight := Height;
  if AGrow = nil then
  begin
    Constraints.MaxHeight := Height;
    Exit;
  end;
  DisableAlign;
  try
    for mIndex := 0 to ControlCount - 1 do
    begin
      mControl := Controls[mIndex];
      if (mControl = AGrow) or (mControl.Top <= AGrow.Top) then
      begin
        Continue;
      end;
      if mControl.Align = alTop then
      begin
        mControl.Align := alBottom;
      end
      else if mControl.Align = alNone then
      begin
        // Frei gesetzte Dialoge: am unteren Rand verankern statt oben.
        mControl.Anchors := mControl.Anchors - [akTop] + [akBottom];
      end;
    end;
    if AGrow.Align = alTop then
    begin
      AGrow.Align := alClient;
    end
    else if AGrow.Align = alNone then
    begin
      AGrow.Anchors := AGrow.Anchors + [akBottom];
    end;
  finally
    EnableAlign;
  end;
end;

procedure TDpccDialog.FitRight(AControl: TControl);
var
  mParent: TWinControl;
begin
  mParent := AControl.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  // Ohne Fenster ordnet die VCL die Zeilen nicht an, ihre Breite wäre die vorläufige.
  HandleNeeded;
  AControl.Width := mParent.ClientWidth - AControl.Left - Min(AControl.Left, ScaleValue(cRowGap));
  AControl.Anchors := [akLeft, akTop, akRight];
end;

end.
