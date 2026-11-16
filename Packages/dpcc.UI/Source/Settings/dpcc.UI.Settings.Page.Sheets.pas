unit dpcc.UI.Settings.Page.Sheets;

// Bausteine der Optionsseite „dpcc“ (#227): Reiter je Bereich mit rollbarem Inhalt und die Zeilen darin
// (Kontrollkästchen, Zahl, Auswahl, Taste, Textzeile, Überschrift, Hinweis, Feldzeile mit Knöpfen). Unterste Stufe
// der Klassenkette der Seite; die Teile der Seite bauen ihre Elemente über diese Methoden.
// Überschriften von Abschnitten seit S8 im Stil des Hovers: Großbuchstaben, fett, gedämpft, dahinter eine dünne Linie
// bis zum rechten Rand; Farben aus dem IDE-Thema (hell und dunkel), keine eigenen Flächen.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  dpcc.UI.Strings,
  dpcc.UI.Settings.ChoiceBox;

const
  // Linke Kante der Eingabefelder; Platz für die längste Beschriftung („Breite der Blocklinien …“).
  cFieldLeft = 280;
  /// <summary>Oberkante der Knöpfe in einer Zeile der Seite.</summary>
  cRowButtonTop = 3;

type
  /// <summary>Zeile der Optionsseite (Beschriftung und Eingabefeld): zeichnet nichts selbst, der
  /// Hintergrund des Reiters scheint durch.</summary>
  TDpccSettingsRow = class(TWinControl)
  public
    constructor Create(AOwner: TComponent); override;
  end;

  /// <summary>Überschrift eines Abschnitts im Stil des Hovers: Text in Großbuchstaben, fett und gedämpft
  /// (clGrayText des IDE-Themas), dahinter eine dünne Linie (clBtnShadow des Themas) bis zum rechten Rand. Bleibt ein
  /// TLabel, damit die Seite sie wie jede Beschriftung behandelt (Completion-Schnitt, Suche).</summary>
  TDpccSettingsTitle = class(TLabel)
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  TDpccSettingsPageSheets = class(TFrame)
  protected
    /// <summary>Aktueller Reiter und sein rollbarer Inhalt; nimmt die Elemente auf.</summary>
    FSheet: TTabSheet;
    FContent: TScrollBox;
    // Reiter hängen erst mit dem Fensterhandle am PageControl (CreateWnd): Die IDE und die Tests
    // erzeugen die Seite, bevor sie ein übergeordnetes Fenster hat.
    FSheets: TArray<TTabSheet>;
    /// <summary>Rollbarer Inhalt je Bereich, gleicher Index wie FSheets.</summary>
    FBoxes: TArray<TScrollBox>;
    FNextTop: Integer;
  public
    /// <summary>AControl hat ein Fenster bzw. bekommt eines, sobald die Seite eines hat (Einträge von Listen und
    /// Bäumen leben im Fenster; auf noch nicht gezeigten Reitern fehlt es sonst).</summary>
    function ListReady(AControl: TWinControl): Boolean;
    /// <summary>Neuer Reiter; die folgenden Add… setzen ihre Elemente darauf.</summary>
    procedure AddSheet(AId: TDpccTextId);
    procedure AddSheetCaption(const ACaption: string);
    /// <summary>Weitere Elemente auf den vorhandenen Reiter AIndex, unter die vorhandenen (Abschnitte der Module).
    /// </summary>
    procedure ContinueSheet(AIndex: Integer);
    function AddCheck(const ACaption: string): TCheckBox;
    function AddPanel(AHeight: Integer): TWinControl;
    function AddNumber(const ACaption: string): TEdit;
    function AddChoice(const ACaption: string; const AItems: array of string): TDpccChoiceBox;
    /// <summary>Überschrift eines Abschnitts (TDpccSettingsTitle: Großbuchstaben, fett, gedämpft, mit Linie).</summary>
    procedure AddTitle(AId: TDpccTextId);
    procedure AddTitleText(const ACaption: string);
    /// <summary>Kürzel ohne eigenen Vorrang; der gilt für die Gruppe (#399). Palette und Prüfung stehen auf der
    /// Seite „Tastenkonflikte“ (#494).</summary>
    function AddKey(const ACaption: string): TEdit;
    /// <summary>Beschriftung über die ganze Breite mit Zeilenumbruch.</summary>
    function AddWrappedLabel(AHeight: Integer; const ACaption: string): TLabel;
    /// <summary>Zeile mit Beschriftung links und AControl rechts daneben (Verbindungen, Projekte).</summary>
    function AddFieldRow(AId: TDpccTextId; AControl: TWinControl; AWidth: Integer): TWinControl;
    function AddRowButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TDpccTextId;
      AClick: TNotifyEvent): TButton;
    /// <summary>Beschriftung in einer Zeile, darunter ein Textfeld über die ganze Breite (#766).</summary>
    function AddTextLine(const ACaption: string): TEdit;
    /// <summary>Reiter und ihr Inhalt in der Reihenfolge des Aufbaus.</summary>
    property Sheets: TArray<TTabSheet> read FSheets;
    property Boxes: TArray<TScrollBox> read FBoxes;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Vcl.Graphics,
  Vcl.Themes;

{ TDpccSettingsRow }

constructor TDpccSettingsRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csParentBackground] - [csOpaque];
  ParentBackground := True;
  ParentColor := True;
end;

{ TDpccSettingsTitle }

constructor TDpccSettingsTitle.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AutoSize := False;
  Transparent := True;
  ShowAccelChar := False;
  Font.Style := [fsBold];
  // Die Farbe setzt Paint aus dem IDE-Thema; der Stil soll sie nicht durch die Textfarbe ersetzen.
  StyleElements := StyleElements - [seFont];
end;

procedure TDpccSettingsTitle.Paint;
var
  mText: string;
  mTextWidth, mGap, mLineY: Integer;
begin
  mText := Caption;
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  Canvas.Font.Color := StyleServices.GetSystemColor(clGrayText);
  Canvas.TextOut(0, 0, mText);
  // Dünne Trennlinie von hinter dem Text bis zum rechten Rand, auf halber Texthöhe.
  mTextWidth := Canvas.TextWidth(mText);
  mGap := ScaleValue(8);
  mLineY := Canvas.TextHeight(mText) div 2;
  if mTextWidth + mGap < ClientWidth then
  begin
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Width := 1;
    Canvas.Pen.Color := StyleServices.GetSystemColor(clBtnShadow);
    Canvas.MoveTo(mTextWidth + mGap, mLineY);
    Canvas.LineTo(ClientWidth, mLineY);
  end;
end;

{ TDpccSettingsPageSheets }

function TDpccSettingsPageSheets.AddFieldRow(AId: TDpccTextId; AControl: TWinControl;
  AWidth: Integer): TWinControl;
var
  mCaption: TLabel;
begin
  Result := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Result;
  mCaption.Caption := TDpccStrings.Text(AId) + ':';
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(5);
  AControl.Parent := Result;
  AControl.Left := AControl.ScaleValue(90);
  AControl.Top := 1;
  AControl.Width := AWidth;
end;

function TDpccSettingsPageSheets.AddRowButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TDpccTextId;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := TDpccStrings.Text(AId);
  Result.Left := ALeft;
  Result.Top := Result.ScaleValue(cRowButtonTop);
  Result.Width := AWidth;
  Result.OnClick := AClick;
end;

function TDpccSettingsPageSheets.AddTextLine(const ACaption: string): TEdit;
var
  mPanel: TWinControl;
  mHeading: TLabel;
begin
  mPanel := AddPanel(20);
  mHeading := TLabel.Create(Self);
  mHeading.Parent := mPanel;
  mHeading.Caption := ACaption;
  mHeading.Left := 0;
  mHeading.Top := mHeading.ScaleValue(3);
  // Eigene Zeile für das Feld: Adressen und Pfade brauchen die Breite.
  mPanel := AddPanel(26);
  Result := TEdit.Create(Self);
  Result.Parent := mPanel;
  Result.Left := 0;
  Result.Top := 1;
  Result.Width := Result.ScaleValue(466);
  Result.Anchors := [akLeft, akTop, akRight];
end;

procedure TDpccSettingsPageSheets.AddSheet(AId: TDpccTextId);
begin
  AddSheetCaption(TDpccStrings.Text(AId));
end;

function TDpccSettingsPageSheets.ListReady(AControl: TWinControl): Boolean;
begin
  if not AControl.HandleAllocated and HandleAllocated then
  begin
    AControl.HandleNeeded;
  end;
  Result := AControl.HandleAllocated;
end;

procedure TDpccSettingsPageSheets.AddTitle(AId: TDpccTextId);
begin
  AddTitleText(TDpccStrings.Text(AId));
end;

procedure TDpccSettingsPageSheets.AddTitleText(const ACaption: string);
var
  mPanel: TWinControl;
  mCaption: TDpccSettingsTitle;
begin
  mPanel := AddPanel(22);
  mCaption := TDpccSettingsTitle.Create(Self);
  mCaption.Parent := mPanel;
  mCaption.Caption := AnsiUpperCase(ACaption);
  // Über die ganze Breite der Zeile: Die Linie reicht bis zum rechten Rand.
  mCaption.Align := alClient;
  mCaption.AlignWithMargins := True;
  mCaption.Margins.SetBounds(0, mCaption.ScaleValue(6), 0, 0);
end;

function TDpccSettingsPageSheets.AddChoice(const ACaption: string; const AItems: array of string): TDpccChoiceBox;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := mPanel;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(5);
  Result := TDpccChoiceBox.Create(Self);
  Result.Parent := mPanel;
  Result.Left := Result.ScaleValue(cFieldLeft);
  Result.Top := 1;
  Result.Width := Result.ScaleValue(180);
  Result.SetChoices(AItems);
end;

function TDpccSettingsPageSheets.AddCheck(const ACaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := FContent;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Caption := ACaption;
  // alTop stapelt nach Top: jedes neue Element unter das vorige.
  Result.Top := FNextTop;
  Inc(FNextTop, 100);
end;

function TDpccSettingsPageSheets.AddPanel(AHeight: Integer): TWinControl;
begin
  // Kein TPanel: Das zeichnet im IDE-Thema einen eigenen Hintergrund (dunkle Streifen im Reiter).
  Result := TDpccSettingsRow.Create(Self);
  Result.Parent := FContent;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Height := AHeight;
  Result.Top := FNextTop;
  Inc(FNextTop, 100);
end;

function TDpccSettingsPageSheets.AddKey(const ACaption: string): TEdit;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := mPanel;
  mCaption.Caption := StringReplace(ACaption, '…', '', []);
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(5);
  // Als Text wie im Menü ("Strg+Umschalt+P"); leer = keine Taste.
  Result := TEdit.Create(Self);
  Result.Parent := mPanel;
  Result.Left := Result.ScaleValue(cFieldLeft);
  Result.Top := 1;
  Result.Width := Result.ScaleValue(140);
end;

function TDpccSettingsPageSheets.AddNumber(const ACaption: string): TEdit;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := mPanel;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(5);
  Result := TEdit.Create(Self);
  Result.Parent := mPanel;
  Result.Left := Result.ScaleValue(cFieldLeft);
  Result.Top := 1;
  Result.Width := Result.ScaleValue(60);
  Result.NumbersOnly := True;
end;

function TDpccSettingsPageSheets.AddWrappedLabel(AHeight: Integer; const ACaption: string): TLabel;
var
  mPanel: TWinControl;
begin
  mPanel := AddPanel(AHeight);
  Result := TLabel.Create(Self);
  Result.Parent := mPanel;
  Result.AutoSize := False;
  Result.Align := alClient;
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
end;

procedure TDpccSettingsPageSheets.ContinueSheet(AIndex: Integer);
var
  mIndex: Integer;
  mControl: TControl;
begin
  FSheet := FSheets[AIndex];
  FContent := FBoxes[AIndex];
  // Neue Zeilen unter die vorhandenen: alTop ordnet nach Top.
  FNextTop := 100;
  for mIndex := 0 to FContent.ControlCount - 1 do
  begin
    mControl := FContent.Controls[mIndex];
    FNextTop := Max(FNextTop, mControl.Top + mControl.Height + 100);
  end;
end;

procedure TDpccSettingsPageSheets.AddSheetCaption(const ACaption: string);
begin
  FSheet := TTabSheet.Create(Self);
  FSheet.Caption := ACaption;
  FSheets := FSheets + [FSheet];
  // Rollbar: Lange Reiter passten sonst nicht in die Optionsseite und wurden abgeschnitten.
  FContent := TScrollBox.Create(Self);
  FBoxes := FBoxes + [FContent];
  FContent.Parent := FSheet;
  FContent.Align := alClient;
  FContent.BorderStyle := bsNone;
  FContent.ParentBackground := True;
  FContent.VertScrollBar.Tracking := True;
  FContent.HorzScrollBar.Visible := False;
  FNextTop := 100;
end;

end.
