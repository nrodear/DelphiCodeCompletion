unit dpcc.UI.Hover.Tip;

// Hover-Tooltip (#442), schlicht wie die Code-Insight-Liste der IDE (Strg+Leertaste; S3, S3b voller Inhalt, S3c
// Aussehen der Liste): TDpccPopupWindow mit FlatFrame (eckig, 1 px Rand in Colors.Line), Farben von
// TDpccIdeStyle.ListColors (setzt dpcc.IDE.Hover.Editor; Fläche, Namen, Art aus dem Farbschema des Editors wie die
// Liste), alles in der UI-Schrift, Code in der Editorschrift auf UI-Größe (FCodeFont), knappe Ränder (cPadX,
// cPadTop), zwischen Abschnitten nur eine dünne Trennlinie (TDpccDraw.Separator). Den Inhalt stellt
// dpcc.Core.Hover.Plain zusammen; hier werden seine Abschnitte nur der Reihe nach gezeichnet:
//   Wert im Debugger   Ausdruck in der Editorschrift, darunter Wert bzw. „wird ausgewertet …“, Trennlinie
//   Kopfzeile          wie eine Zeile der Liste (Höhe, Art-Spalte nach „constructor“, Art in der Farbe der
//                      reservierten Wörter, Name fett, Rest eingefärbt mit TDpccStyledText), an Leerzeichen
//                      umbrochen
//   Herkunft, Fundort  gedämpft in der UI-Schrift
//   Trennlinie, Wert und Veraltung, XMLDoc mit demselben Satz und Zeichner wie im Detailpanel (TDpccDocView, ganz
//   aufgeklappt, ohne „Mehr anzeigen“); ist der Tooltip höher als der Platz bzw. hints.xmlDocMaxLines, scrollt
//   nur die Doku mit dem Mausrad (Balken rechts wie im Detailpanel)
//   Trennlinie, published-Mitglieder: Zusammenfassung, PROPERTIES und EREIGNISSE als schlichte Spalten
//   Trennlinie, VERERBUNG bzw. ZIELTYP mit der Kette
// Ohne Fokus, ohne Klickflächen, Links, Kacheln, Badges oder Kopfleisten; den Tooltip schließt
// dpcc.IDE.Hover.Editor.

interface

uses
  System.Classes,
  System.Types,
  Vcl.Graphics,
  dpcc.Core.Hover.Contract,
  dpcc.Core.Hover.DebugValue,
  dpcc.Core.Hover.Plain,
  dpcc.UI.Documentation.View,
  dpcc.UI.Popup.Styled,
  dpcc.UI.Popup.Window;

type
  TDpccHoverTip = class(TDpccPopupWindow)
  public const
    /// <summary>Höchstbreite in logischen Pixeln (wie vor S3).</summary>
    cMaxWidth = 460;
    /// <summary>Mindestbreite in logischen Pixeln.</summary>
    cMinWidth = 200;
  private
    FHover: TDpccPlainHover;
    FSignature: TDpccStyledText;
    FDoc: TDpccDocView;
    FDocTop: Integer;
    /// <summary>Editorschrift in der Größe der UI-Schrift für Code.</summary>
    FCodeFont: TFont;
    /// <summary>Über dem Wort gezeigt: Beim Neusetzen (Wert im Debugger kommt nach) bleibt der untere Rand.</summary>
    FAbove: Boolean;
    procedure PrepareFonts;
    /// <summary>Breite für den Inhalt: mit Doku, Mitgliedern oder Kette die Höchstbreite, sonst Zeile 1 ungebrochen.
    /// </summary>
    function PreferredWidth: Integer;
    /// <summary>Höhe für die Breite AWidth mit höchstens AAvailable Pixeln: begrenzt die Doku (scrollt dann).
    /// </summary>
    function FitHeight(AWidth, AAvailable: Integer): Integer;
    /// <summary>Zeichnet (ADraw) bzw. misst den Inhalt in der Breite AWidth; liefert die Höhe.</summary>
    function Render(AWidth: Integer; ADraw: Boolean): Integer;
  protected
    procedure Paint; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Zeigt den Inhalt zu AData und dem Wert im Debugger ADebug unter (bzw. über) dem Wort AWord
    /// (Bildschirmkoordinaten); ACurrentUnit gilt, wenn der Server keine Unit nennt.</summary>
    procedure ShowHover(const AData: TDpccHoverData; const ADebug: TDpccDebugValue; const ACurrentUnit: string;
      const AWord: TRect);
    property Hover: TDpccPlainHover read FHover;
    property Doc: TDpccDocView read FDoc;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Math,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette,
  dpcc.Core.Hover.Texts,
  dpcc.Core.Diagnostics.Guard,
  dpcc.UI.Strings,
  dpcc.UI.Popup.Accessibility,
  dpcc.UI.Popup.Draw,
  dpcc.UI.Hover.Strings;

const
  // Abstände wie in der Code-Insight-Liste der IDE (logische Pixel, S3c): Rand links 8, oben 5; Zeile 1 so hoch
  // wie eine Zeile der Liste (Schrifthöhe + cRowPad); zwischen Blöcken cBlockGap, zwischen Abschnitten nur die
  // Trennlinie mit cSeparatorGap (weniger als eine halbe Zeile).
  cPadX = 8;
  cPadTop = 5;
  cPadBottom = 5;
  cRowPad = 9;
  cIndent = 16;
  cBlockGap = 1;
  cSeparatorGap = 7;
  cColumnGap = 12;
  // Art-Spalte: so breit wie „constructor“ (das längste Wort, das dpcc der IDE als GetLongestItem meldet) plus
  // Abstand, wie die Spalte der Liste.
  cKindColumnSample = 'constructor';
  cKindGap = 24;

function KindCaptionOf(const AKind: string): string;
const
  cKinds: array[0..15] of string = ('class', 'classref', 'object', 'record', 'interface', 'helper', 'enum', 'type',
    'method', 'constructor', 'routine', 'property', 'field', 'variable', 'constant', 'enumMember');
  cIds: array[0..15] of TDpccTextId = (TDpccTextId.KindClass, TDpccTextId.KindClassRef, TDpccTextId.KindObject,
    TDpccTextId.KindRecord, TDpccTextId.KindInterface, TDpccTextId.KindHelper, TDpccTextId.KindEnum,
    TDpccTextId.KindType, TDpccTextId.KindMethod, TDpccTextId.KindConstructor, TDpccTextId.KindRoutine,
    TDpccTextId.KindProperty, TDpccTextId.KindField, TDpccTextId.KindVariable, TDpccTextId.KindConstant,
    TDpccTextId.KindEnumMember);
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(cKinds) do
  begin
    if cKinds[mIndex] = AKind then
    begin
      Exit(TDpccStrings.Text(cIds[mIndex]));
    end;
  end;
end;

/// <summary>Texte des Inhalts in der Sprache der Oberfläche.</summary>
function HoverTexts(const AData: TDpccHoverData): TDpccHoverTexts;
begin
  Result := Default(TDpccHoverTexts);
  Result.KindCaption := KindCaptionOf(AData.Kind);
  Result.Inheritance := TDpccHoverStrings.Text(TDpccHoverTextId.HoverInheritance);
  Result.TargetType := TDpccHoverStrings.Text(TDpccHoverTextId.HoverTargetType);
  Result.DebugPending := TDpccHoverStrings.Text(TDpccHoverTextId.HoverDebugPending);
  Result.PublishedSummary := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedSummary);
  Result.PublishedProperties := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedProperties);
  Result.PublishedEvents := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedEvents);
  Result.PublishedName := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedName);
  Result.PublishedType := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedType);
  Result.PublishedDefault := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedDefault);
  Result.PublishedDeclared := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedDeclared);
  Result.PublishedImplicit := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedImplicit);
  Result.PublishedMoreProperties := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedMoreProperties);
  Result.PublishedMoreEvents := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedMoreEvents);
  Result.PublishedEventsNote := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedEventsNote);
  Result.PublishedArrayProperty := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedArrayProperty);
  Result.PublishedDefaultProperty := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedDefaultProperty);
  Result.PublishedDefaultPropertyNote := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedDefaultPropertyNote);
  Result.PublishedVclNote := TDpccHoverStrings.Text(TDpccHoverTextId.PublishedVclNote);
end;

type
  /// <summary>Ein Durchlauf von TDpccHoverTip.Render wie TDetailRender im Detailpanel: Spalte von Left bis Right,
  /// laufende Höhe Y; ohne Draw wird nur gemessen.</summary>
  THoverRender = record
    Tip: TDpccHoverTip;
    Canvas: TCanvas;
    Colors: TDpccColors;
    Draw: Boolean;
    Left: Integer;
    Right: Integer;
    Y: Integer;
    /// <summary>Schon etwas gezeichnet: Vor dem nächsten Abschnitt steht eine Trennlinie.</summary>
    Started: Boolean;
    function Scale(AValue: Integer): Integer;
    /// <summary>Text in der UI-Schrift umbrechend ab Y, höchstens AMaxLines Zeilen (0 = alle).</summary>
    procedure Block(const AText: string; AColor: TDpccColor; AStyle: TFontStyles; AMaxLines: Integer = 0);
    /// <summary>Text in der Editorschrift umbrechend ab Y.</summary>
    procedure Mono(const AText: string; AColor: TDpccColor);
    /// <summary>Überschrift eines Abschnitts in Großbuchstaben, gedämpft und fett (wie im Detailpanel).</summary>
    procedure Heading(const AText: string);
    procedure Separator;
    /// <summary>Trennlinie vor einem neuen Abschnitt (nicht vor dem ersten).</summary>
    procedure Section;
    procedure DebugValue;
    procedure Headline;
    procedure Notes;
    procedure Documentation;
    procedure Table(const ATable: TDpccPlainHoverTable; AHeader: Boolean);
    procedure Members;
    procedure Chain;
  end;

function THoverRender.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Tip.PPI, 96);
end;

procedure THoverRender.Block(const AText: string; AColor: TDpccColor; AStyle: TFontStyles; AMaxLines: Integer);
var
  mArea: TRect;
begin
  if AText = '' then
  begin
    Exit;
  end;
  Canvas.Font := Tip.UIFont;
  Canvas.Font.Style := AStyle;
  Canvas.Font.Color := ToColor(AColor);
  Canvas.Brush.Style := bsClear;
  mArea := Rect(Left, Y, Right, Y);
  DrawText(Canvas.Handle, PChar(AText), -1, mArea, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
  mArea.Right := Right;
  if AMaxLines > 0 then
  begin
    mArea.Bottom := Min(mArea.Bottom, Y + AMaxLines * Canvas.TextHeight('Wg'));
  end;
  if Draw then
  begin
    DrawText(Canvas.Handle, PChar(AText), -1, mArea, DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;
  Y := mArea.Bottom + Scale(cBlockGap);
  Canvas.Font.Style := [];
end;

procedure THoverRender.Mono(const AText: string; AColor: TDpccColor);
var
  mArea: TRect;
begin
  if AText = '' then
  begin
    Exit;
  end;
  Canvas.Font := Tip.FCodeFont;
  Canvas.Font.Color := ToColor(AColor);
  Canvas.Brush.Style := bsClear;
  mArea := Rect(Left, Y, Right, Y);
  DrawText(Canvas.Handle, PChar(AText), -1, mArea, DT_WORDBREAK or DT_NOPREFIX or DT_CALCRECT);
  mArea.Right := Right;
  if Draw then
  begin
    DrawText(Canvas.Handle, PChar(AText), -1, mArea, DT_WORDBREAK or DT_NOPREFIX);
  end;
  Y := mArea.Bottom + Scale(cBlockGap);
end;

procedure THoverRender.Heading(const AText: string);
begin
  Block(AnsiUpperCase(AText), Colors.Muted, [fsBold]);
end;

procedure THoverRender.Separator;
begin
  if Draw then
  begin
    TDpccDraw.Separator(Canvas, Left, Right, Y + Scale(cSeparatorGap div 2), Colors.Line);
  end;
  Inc(Y, Scale(cSeparatorGap));
end;

procedure THoverRender.Section;
begin
  if Started then
  begin
    Separator;
  end;
  Started := True;
end;

procedure THoverRender.DebugValue;
var
  mHover: TDpccPlainHover;
begin
  // Wert im angehaltenen Debugger (#891): Ausdruck, darunter der Wert bzw. „wird ausgewertet …“.
  mHover := Tip.FHover;
  Section;
  Mono(mHover.Debug.Expression, Colors.Text);
  if mHover.Debug.State = TDpccDebugValueState.Pending then
  begin
    Block(mHover.DebugText, Colors.Muted, [], 1);
  end
  else
  begin
    Block(mHover.DebugText, Colors.Text, [], TDpccPlainHover.cDebugValueLines);
  end;
end;

procedure THoverRender.Headline;
var
  mHover: TDpccPlainHover;
  mLineHeight, mRowHeight, mLine, mX, mSignatureLeft, mNameEnd, mNormal, mBold: Integer;
  mLines: TArray<TPoint>;
  mRow: TRect;
  mRange: TPoint;
  mNameText: string;
begin
  // Wie eine Zeile der Code-Insight-Liste: UI-Schrift, Art in der Art-Spalte (Farbe der reservierten Wörter, Breite
  // nach „constructor“ wie die Spalte der Liste), Name fett, Rest der Signatur eingefärbt; Zeile 1 so hoch wie eine
  // Zeile der Liste, Folgezeilen eingerückt.
  mHover := Tip.FHover;
  Section;
  Canvas.Font := Tip.UIFont;
  mLineHeight := Canvas.TextHeight('Wg') + Scale(2);
  mRowHeight := Canvas.TextHeight('Wg') + Scale(cRowPad);
  mSignatureLeft := Left;
  if mHover.Kind <> '' then
  begin
    mRow := Rect(Left, Y, Right, Y + mRowHeight);
    if Draw then
    begin
      Canvas.Font.Color := ToColor(Colors.Keyword);
      Canvas.Brush.Style := bsClear;
      DrawText(Canvas.Handle, PChar(mHover.Kind), -1, mRow, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
    end;
    mSignatureLeft := Left + Max(Canvas.TextWidth(cKindColumnSample), Canvas.TextWidth(mHover.Kind)) +
      Scale(cKindGap);
  end;
  // Name fett: um seinen Mehrbedarf schmaler umbrechen, damit Zeile 1 nicht abgeschnitten wird.
  mNameEnd := TDpccPlainHover.NameLength(mHover.Signature);
  mNameText := Copy(mHover.Signature, 1, mNameEnd);
  mNormal := Canvas.TextWidth(mNameText);
  Canvas.Font.Style := [fsBold];
  mBold := Canvas.TextWidth(mNameText);
  Canvas.Font.Style := [];
  mLines := Tip.FSignature.WrapAtSpaces(Canvas, Max(Scale(40), Right - mSignatureLeft - (mBold - mNormal)),
    Scale(cIndent));
  for mLine := 0 to High(mLines) do
  begin
    mX := mSignatureLeft + IfThen(mLine > 0, Scale(cIndent));
    if mLine = 0 then
    begin
      mRow := Rect(mX, Y, Right, Y + mRowHeight);
    end
    else
    begin
      mRow := Rect(mX, Y, Right, Y + mLineHeight);
    end;
    mRange := mLines[mLine];
    if Draw and (mLine = 0) and (mRange.X = 0) and (mNameEnd > 0) then
    begin
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := ToColor(Colors.Text);
      Canvas.Brush.Style := bsClear;
      DrawText(Canvas.Handle, PChar(mNameText), -1, mRow, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
      Canvas.Font.Style := [];
      Inc(mX, mBold);
      mRange.X := Min(mNameEnd, mRange.Y);
    end;
    if Draw then
    begin
      Tip.FSignature.Draw(TDpccStyledTarget.Create(Canvas, Colors, Scale(3)), mRange, mX,
        Rect(mX, mRow.Top, Right, mRow.Bottom), False);
    end;
    Inc(Y, mRow.Height);
  end;
  if Length(mLines) = 0 then
  begin
    Inc(Y, mRowHeight);
  end;
  // Herkunft und Fundort gedämpft (wie die Kopfzeile eines Menüs der IDE).
  Block(mHover.OriginLine, Colors.Muted, []);
  Block(mHover.Location, Colors.Muted, []);
end;

procedure THoverRender.Notes;
var
  mHover: TDpccPlainHover;
begin
  mHover := Tip.FHover;
  Mono(mHover.ValueLine, Colors.Muted);
  Block(mHover.Deprecation, Colors.Warn, []);
end;

procedure THoverRender.Documentation;
begin
  // Derselbe Satz und Zeichner wie im Detailpanel der Vervollständigung.
  Tip.FDocTop := Y;
  if Draw then
  begin
    Tip.FDoc.Paint(Canvas, Colors, Left, Y);
  end;
  Inc(Y, Tip.FDoc.Height + Scale(cBlockGap));
end;

procedure THoverRender.Table(const ATable: TDpccPlainHoverTable; AHeader: Boolean);
var
  mTexts: TDpccHoverTexts;
  mRow: TDpccPlainHoverRow;
  mTypeX, mDefaultX, mLineHeight, mDeclaredWidth: Integer;
  mCell: TRect;

  procedure Cell(const AText: string; AX, ARight: Integer; AColor: TDpccColor);
  begin
    if not Draw or (AText = '') or (ARight <= AX) then
    begin
      Exit;
    end;
    Canvas.Font.Color := ToColor(AColor);
    mCell := Rect(AX, Y, ARight, Y + mLineHeight);
    DrawText(Canvas.Handle, PChar(AText), -1, mCell, DT_LEFT or DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;

begin
  if ATable.IsEmpty then
  begin
    Exit;
  end;
  mTexts := HoverTexts(Default(TDpccHoverData));
  Heading(ATable.Caption);
  // Spalten nach den breitesten Werten: Name, Typ, Vorgabe; „deklariert in“ rechtsbündig.
  Canvas.Font := Tip.FCodeFont;
  Canvas.Brush.Style := bsClear;
  mLineHeight := Canvas.TextHeight('Wg') + Scale(2);
  mTypeX := 0;
  mDefaultX := 0;
  mDeclaredWidth := 0;
  for mRow in ATable.Rows do
  begin
    mTypeX := Max(mTypeX, Canvas.TextWidth(mRow.Name));
    mDefaultX := Max(mDefaultX, Canvas.TextWidth(mRow.TypeName));
    mDeclaredWidth := Max(mDeclaredWidth, Canvas.TextWidth(mRow.Declared));
  end;
  mTypeX := Left + mTypeX + Scale(cColumnGap);
  mDefaultX := mTypeX + mDefaultX + Scale(cColumnGap);
  if AHeader then
  begin
    Canvas.Font := Tip.UIFont;
    Cell(mTexts.PublishedName, Left, mTypeX, Colors.Muted);
    Cell(mTexts.PublishedType, mTypeX, mDefaultX, Colors.Muted);
    Cell(mTexts.PublishedDefault, mDefaultX, Right - mDeclaredWidth, Colors.Muted);
    Cell(mTexts.PublishedDeclared, Right - Canvas.TextWidth(mTexts.PublishedDeclared), Right, Colors.Muted);
    Inc(Y, Canvas.TextHeight('Wg') + Scale(2));
    Canvas.Font := Tip.FCodeFont;
  end;
  for mRow in ATable.Rows do
  begin
    Cell(mRow.Name, Left, mTypeX - Scale(4), Colors.Text);
    Cell(mRow.TypeName, mTypeX, mDefaultX - Scale(4), Colors.Text);
    Cell(mRow.DefaultText, mDefaultX, Right - mDeclaredWidth - Scale(cColumnGap), Colors.Muted);
    Cell(mRow.Declared, Right - Canvas.TextWidth(mRow.Declared), Right, Colors.Muted);
    Inc(Y, mLineHeight);
  end;
  Block(ATable.More, Colors.Muted, []);
  Block(ATable.Note, Colors.Muted, [fsItalic]);
end;

procedure THoverRender.Members;
var
  mHover: TDpccPlainHover;
begin
  // published-Mitglieder einer Komponentenklasse (#110).
  mHover := Tip.FHover;
  Section;
  Block(mHover.MembersSummary, Colors.Muted, []);
  Table(mHover.Properties, True);
  Table(mHover.Events, False);
  if mHover.DefaultProperty <> '' then
  begin
    Heading(mHover.DefaultPropertyCaption);
    Mono(mHover.DefaultProperty + ' · ' + mHover.DefaultPropertyLabel, Colors.Text);
    Block(mHover.DefaultPropertyNote, Colors.Muted, [fsItalic]);
  end;
  Block(mHover.MembersNote, Colors.Muted, [fsItalic]);
end;

procedure THoverRender.Chain;
var
  mHover: TDpccPlainHover;
begin
  mHover := Tip.FHover;
  Section;
  Heading(mHover.ChainCaption);
  Mono(mHover.Chain, Colors.Text);
end;

{ TDpccHoverTip }

constructor TDpccHoverTip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TDpccFeature.Hover;
  // Flach wie ein Menü der IDE und das Popup der Vervollständigung: eckig, grauer Rand, kein Akzentrahmen.
  FlatFrame := True;
  FDoc := TDpccDocView.Create;
  FCodeFont := TFont.Create;
end;

destructor TDpccHoverTip.Destroy;
begin
  FDoc.Free;
  FCodeFont.Free;
  inherited Destroy;
end;

procedure TDpccHoverTip.PrepareFonts;
begin
  // Code (Ausdruck, Wert, Kette, Mitglieder, Typen und Beispiele der Doku) in der Editorschrift, aber so groß wie
  // die UI-Schrift: alles in der Größe einer Zeile der Code-Insight-Liste.
  FCodeFont.Assign(Font);
  FCodeFont.Height := UIFont.Height;
  FCodeFont.Style := [];
end;

function TDpccHoverTip.Render(AWidth: Integer; ADraw: Boolean): Integer;
var
  mRender: THoverRender;
  mSection: TDpccPlainHoverSection;
  mAfterHeadline: Boolean;
begin
  mRender := Default(THoverRender);
  mRender.Tip := Self;
  mRender.Canvas := Canvas;
  mRender.Colors := Colors;
  mRender.Draw := ADraw;
  mRender.Left := Scale(cPadX);
  mRender.Right := AWidth - Scale(cPadX);
  mRender.Y := Scale(cPadTop);
  mAfterHeadline := False;
  for mSection in FHover.Sections do
  begin
    case mSection of
      TDpccPlainHoverSection.DebugValue:
        mRender.DebugValue;
      TDpccPlainHoverSection.Headline:
        mRender.Headline;
      TDpccPlainHoverSection.Notes, TDpccPlainHoverSection.Documentation:
        begin
          // Wert, Veraltung und Doku bilden einen Block unter einer Trennlinie (wie im Detailpanel).
          if not mAfterHeadline then
          begin
            mRender.Separator;
            mAfterHeadline := True;
          end;
          if mSection = TDpccPlainHoverSection.Notes then
          begin
            mRender.Notes;
          end
          else
          begin
            mRender.Documentation;
          end;
        end;
      TDpccPlainHoverSection.Members:
        mRender.Members;
      TDpccPlainHoverSection.Chain:
        mRender.Chain;
    end;
    // Herkunft und Fundort zeichnet Headline mit.
  end;
  Canvas.Brush.Style := bsSolid;
  Result := mRender.Y - Scale(cBlockGap) + Scale(cPadBottom);
end;

function TDpccHoverTip.PreferredWidth: Integer;
var
  mWidest, mName, mHeadline: Integer;
begin
  if FHover.Has(TDpccPlainHoverSection.Documentation) or FHover.Has(TDpccPlainHoverSection.Members) or
    FHover.Has(TDpccPlainHoverSection.Chain) or FHover.Has(TDpccPlainHoverSection.Notes) then
  begin
    Exit(Scale(cMaxWidth));
  end;
  Canvas.Font := FCodeFont;
  mWidest := Canvas.TextWidth(FHover.Debug.Expression);
  Canvas.Font := UIFont;
  // Zeile 1 mit fettem Namen; die Art-Spalte so breit wie in der Code-Insight-Liste.
  Canvas.Font.Style := [fsBold];
  mName := Canvas.TextWidth(Copy(FHover.Signature, 1, TDpccPlainHover.NameLength(FHover.Signature)));
  Canvas.Font.Style := [];
  mHeadline := FSignature.Width(Canvas, 0, Length(FSignature.Text)) + mName -
    Canvas.TextWidth(Copy(FHover.Signature, 1, TDpccPlainHover.NameLength(FHover.Signature)));
  if FHover.Kind <> '' then
  begin
    Inc(mHeadline, Max(Canvas.TextWidth(cKindColumnSample), Canvas.TextWidth(FHover.Kind)) + Scale(cKindGap));
  end;
  mWidest := Max(mWidest, mHeadline);
  mWidest := Max(mWidest, Canvas.TextWidth(FHover.OriginLine));
  mWidest := Max(mWidest, Canvas.TextWidth(FHover.Location));
  if FHover.Debug.Visible then
  begin
    mWidest := Max(mWidest, Canvas.TextWidth(FHover.DebugText));
  end;
  Result := EnsureRange(mWidest + Scale(2 * cPadX) + 2, Scale(cMinWidth), Scale(cMaxWidth));
end;

function TDpccHoverTip.FitHeight(AWidth, AAvailable: Integer): Integer;
var
  mInner: Integer;
begin
  FDoc.Clear;
  mInner := AWidth - Scale(2 * cPadX);
  if FHover.Has(TDpccPlainHoverSection.Documentation) then
  begin
    // Derselbe Satz und Zeichner wie im Detailpanel; Code in der Editorschrift in UI-Größe.
    FDoc.Build(Canvas, FHover.DocContent, mInner, TDpccDocFonts.Create(FCodeFont, UIFont, PPI),
      TDpccStrings.DocLabels);
    FDoc.FitHeight(FHover.Display.MaxLines, 0);
  end;
  Result := Render(AWidth, False);
  // Zu hoch: nur die Doku wird kürzer und scrollt (wie im Detailpanel).
  if (Result > AAvailable) and not FDoc.IsEmpty then
  begin
    FDoc.FitHeight(FHover.Display.MaxLines, Max(1, FDoc.Height - (Result - AAvailable)));
    Result := Render(AWidth, False);
  end;
end;

procedure TDpccHoverTip.ShowHover(const AData: TDpccHoverData; const ADebug: TDpccDebugValue;
  const ACurrentUnit: string; const AWord: TRect);
var
  mWidth, mHeight: Integer;
  mArea, mBounds: TRect;
begin
  HandleNeeded;
  PrepareFonts;
  FHover := TDpccPlainHover.From(AData, ACurrentUnit, HoverTexts(AData), ADebug);
  FSignature := TDpccStyledText.Create(FHover.Signature);
  mWidth := PreferredWidth;
  mArea := WorkAreaAt(AWord.TopLeft);
  // Höchstens so hoch wie der größere Platz unter bzw. über dem Wort; darüber scrollt die Doku.
  mHeight := FitHeight(mWidth, Max(mArea.Bottom - AWord.Bottom, AWord.Top - mArea.Top) - Scale(12));
  // Unter dem Wort; reicht der Platz nicht, darüber.
  mBounds := TRect.Create(Point(AWord.Left, AWord.Bottom + Scale(4)), mWidth, mHeight);
  FAbove := mBounds.Bottom > mArea.Bottom;
  if FAbove then
  begin
    mBounds.SetLocation(mBounds.Left, Max(mArea.Top, AWord.Top - mHeight - Scale(4)));
  end;
  if mBounds.Right > mArea.Right then
  begin
    mBounds.SetLocation(Max(mArea.Left, mArea.Right - mWidth), mBounds.Top);
  end;
  ShowAt(mBounds);
  // Sprachausgabe (#447): Wert im Debugger, Signatur, Herkunft und Kurztext.
  SetAccessible(cUiaToolTipControlType, TDpccHoverStrings.Text(TDpccHoverTextId.AccessHover));
  Announce(FHover.Spoken);
end;

function TDpccHoverTip.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  mSteps: Integer;
begin
  // Nur die Doku scrollt (wie im Detailpanel); Kopfzeile und übrige Abschnitte bleiben stehen.
  Result := True;
  if FDoc.IsEmpty or not FDoc.CanScroll or (WheelDelta = 0) then
  begin
    Exit;
  end;
  mSteps := Max(1, Abs(WheelDelta) div WHEEL_DELTA);
  if WheelDelta > 0 then
  begin
    mSteps := -mSteps;
  end;
  if FDoc.ScrollBy(mSteps * FDoc.WheelStep) then
  begin
    Invalidate;
  end;
end;

procedure TDpccHoverTip.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Render(ClientWidth, True);
  PaintBorder;
end;

end.
