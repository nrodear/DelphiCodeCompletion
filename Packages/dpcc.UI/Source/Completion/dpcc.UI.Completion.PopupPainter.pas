unit dpcc.UI.Completion.PopupPainter;

// Vervollständigungs-Popup (#410), Stufe Zeichnen: Warnleiste, Überschriften, Zeilen, Scrollleiste, Fußzeile und
// leerer Zustand; dazu der Tooltip für gekürzte Zeilen (#420). Kette und Aussehen: dpcc.UI.Completion.Popup.
// Schlicht (S6): Zeilen wie die Code-Insight-Liste der IDE und der Hover-Tooltip (DrawRow): Art als Wort gedämpft
// (Colors.KindLabel, S8), Name fett (getippte Zeichen unterstrichen), Rest der Signatur direkt dahinter bzw.
// das Detail gedämpft, rechts gedämpft „+ Unit“ und Warnungen als Text; Auswahl flach über die ganze Zeile.
// Fußzeile auf der Fläche mit Trennlinie, nur Tasten bzw. Hinweise. Badges, Tags als Flächen, Sterne, Chips,
// Auswahlmarke, Griff und Detailpanel gibt es seit S7a nicht mehr. Seit S8 sind auch Warnleiste (Text in
// Warnfarbe über einer Trennlinie) und Kästchen im Mengenmodus (1 px, eckig) flach.

interface

uses
  Vcl.Controls,
  Winapi.Messages,
  System.Classes,
  System.Types,
  dpcc.Core.Style.Color,
  dpcc.Core.Completion.Contract,
  dpcc.UI.Completion.PopupState,
  dpcc.UI.Completion.PopupLayout;

type
  TDpccCompletionPopupPainter = class(TDpccCompletionPopupLayout)
  protected
    function Dim(AColor: TDpccColor): TDpccColor;
    procedure DrawSyntax;
    procedure DrawHeader(ARow, APosition: Integer);
    procedure DrawCheck(const ARow: TRect; AChecked: Boolean);
    /// <summary>Zeile der Liste.</summary>
    procedure DrawRow(ARow, APosition: Integer);
    /// <summary>Name fett ab ALeft bis höchstens ARight, getippte Zeichen unterstrichen; liefert das Ende des
    /// Namens. ATruncated, wenn er nicht ganz passt.</summary>
    function DrawName(const AName: string; ALeft, ARight: Integer; const ARow: TRect; AColor: TDpccColor;
      out ATruncated: Boolean): Integer;
    /// <summary>Textfarbe auf der gewählten Zeile.</summary>
    function SelectionText: TDpccColor;
    /// <summary>Merkt für den Tooltip (#420), ob die sichtbare Zeile ARow gekürzt ist.</summary>
    procedure MarkTruncated(ARow: Integer; ATruncated: Boolean);
    procedure DrawScrollBar;
    procedure DrawFooter(const ALeft, ARight: string);
    /// <summary>Warnleiste, sichtbare Zeilen, Scrollleiste und Fußzeile.</summary>
    procedure DrawList;
    procedure PaintEmpty;
    procedure Paint; override;
    /// <summary>Sichtbare Zeile unter der Maus, wenn sie ein gekürzter Eintrag ist.</summary>
    function TipRow(out ARow: Integer): Boolean;
    procedure TipTimer(Sender: TObject);
    procedure HideTip;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Gezeigter Hinweis der Fußzeile; '' ohne.</summary>
    property Notice: string read FNotice;
    /// <summary>Gezeigter Hinweis bei unvollständigem Code (#457).</summary>
    property Syntax: TDpccSyntaxNotice read FSyntax;
    /// <summary>Gezogene Breite der Liste in logischen Pixeln, 0 = automatisch (#416).</summary>
    property ManualListWidth: Integer read FManualListWidth write FManualListWidth;
    property OnWidthChanged: TDpccWidthEvent read FEvents.OnWidthChanged write FEvents.OnWidthChanged;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Graphics,
  dpcc.Core.Completion.Ranking,
  dpcc.Core.Completion.Presentation,
  dpcc.Core.Diagnostics.Timing,
  dpcc.UI.Popup.Draw,
  dpcc.UI.Completion.Strings,
  dpcc.UI.Completion.PopupTexts;

const
  cTextFlags = DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;

{ TDpccCompletionPopupPainter }

constructor TDpccCompletionPopupPainter.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTipTimer.OnTimer := TipTimer;
end;

function TDpccCompletionPopupPainter.Dim(AColor: TDpccColor): TDpccColor;
begin
  if FDimRow then
  begin
    Result := TDpccColorMath.Mix(AColor, Colors.Surface, 0.62);
  end
  else
  begin
    Result := AColor;
  end;
end;

procedure TDpccCompletionPopupPainter.DrawSyntax;
var
  mBar, mText: TRect;
  mLead, mLineText: string;
  mLeft: Integer;
begin
  FSyntaxLink := Rect(0, 0, 0, 0);
  if SyntaxHeight = 0 then
  begin
    Exit;
  end;
  // Flach wie der Hover-Tooltip: nur Text in Warnfarbe, darunter eine dünne Trennlinie.
  mBar := Rect(Pad + Scale(4), Pad + Scale(2), ListWidth - Pad - Scale(4), Pad + SyntaxHeight - Scale(2));
  TDpccDraw.Separator(Canvas, Pad, ListWidth - Pad, Pad + SyntaxHeight - 1, Colors.Line);
  mLead := TDpccCompletionTexts.SyntaxLead(FSyntax.Trust);
  mLineText := TDpccCompletionTexts.SyntaxLineText(FSyntax.Line);
  Canvas.Font := UIFont;
  Canvas.Font.Color := ToColor(Colors.Warn);
  Canvas.Brush.Style := bsClear;
  mText := Rect(mBar.Left + Scale(8), mBar.Top, mBar.Right - Scale(8), mBar.Bottom);
  DrawText(Canvas.Handle, PChar(mLead), -1, mText, cTextFlags or DT_END_ELLIPSIS);
  // Zeilenangabe unterstrichen dahinter; nur sie ist anklickbar.
  mLeft := mText.Left + Canvas.TextWidth(mLead);
  if mLeft + Canvas.TextWidth(mLineText) <= mText.Right then
  begin
    Canvas.Font.Style := [fsUnderline];
    mText.Left := mLeft;
    DrawText(Canvas.Handle, PChar(mLineText), -1, mText, cTextFlags);
    FSyntaxLink := Rect(mLeft, mBar.Top, mLeft + Canvas.TextWidth(mLineText), mBar.Bottom);
    Canvas.Font.Style := [];
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
end;

procedure TDpccCompletionPopupPainter.DrawHeader(ARow, APosition: Integer);
var
  mRow: TRect;
  mText: string;
begin
  mText := TDpccCompletionTexts.HeaderText(FItems, FOrder, APosition);
  mRow := RowRect(ARow);
  Inc(mRow.Left, Scale(7));
  Canvas.Font := UIFont;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(Colors.Muted);
  Canvas.Brush.Style := bsClear;
  mRow.Top := mRow.Top + Scale(4);
  DrawText(Canvas.Handle, PChar(mText), -1, mRow, cTextFlags or DT_END_ELLIPSIS);
  Canvas.Font.Style := [];
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
  MarkTruncated(ARow, False);
end;

procedure TDpccCompletionPopupPainter.DrawFooter(const ALeft, ARight: string);
var
  mFooter, mText: TRect;
begin
  // Auf der Fläche, nur durch die Trennlinie abgesetzt.
  mFooter := Rect(0, ClientHeight - FooterHeight, ListWidth, ClientHeight);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(mFooter);
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.MoveTo(mFooter.Left, mFooter.Top);
  Canvas.LineTo(mFooter.Right, mFooter.Top);
  Canvas.Font := UIFont;
  Canvas.Font.Color := ToColor(Colors.Muted);
  Canvas.Brush.Style := bsClear;
  mText := Rect(mFooter.Left + Scale(9), mFooter.Top + 1, mFooter.Right - Scale(9), mFooter.Bottom);
  DrawText(Canvas.Handle, PChar(ARight), -1, mText, cTextFlags or DT_RIGHT);
  mText.Right := mText.Right - Canvas.TextWidth(ARight) - Scale(10);
  DrawText(Canvas.Handle, PChar(ALeft), -1, mText, cTextFlags or DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
end;

procedure TDpccCompletionPopupPainter.PaintEmpty;
var
  mLine: TRect;

  procedure DrawLine(AIndex: Integer; const AText: string; AColor: TDpccColor);
  begin
    mLine := Rect(Pad + Scale(7), ListTop + AIndex * RowHeight, ListWidth - Pad - Scale(7),
      ListTop + (AIndex + 1) * RowHeight);
    Canvas.Font := UIFont;
    Canvas.Font.Color := ToColor(AColor);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(AText), -1, mLine, cTextFlags or DT_END_ELLIPSIS);
  end;

begin
  DrawSyntax;
  if FEmpty.Prefix <> '' then
  begin
    DrawLine(0, TDpccCompletionStrings.Fmt(TDpccCompletionTextId.NoMatchesFor, [FEmpty.Prefix]), Colors.Text);
  end
  else
  begin
    DrawLine(0, TDpccCompletionStrings.Text(TDpccCompletionTextId.NoSuggestions), Colors.Text);
  end;
  // Unvollständiger Code (#457): statt des Tipps zur Rücktaste der Fehler.
  if (FSyntax.Trust <> TDpccSyntaxTrust.Sure) and (FSyntax.Message <> '') then
  begin
    DrawLine(1, FSyntax.Message, Colors.Muted);
  end
  else if FEmpty.Prefix <> '' then
  begin
    DrawLine(1, TDpccCompletionStrings.Text(TDpccCompletionTextId.BackspaceWidens), Colors.Muted);
  end;
  Canvas.Brush.Style := bsSolid;
  DrawFooter(TDpccCompletionStrings.Text(TDpccCompletionTextId.EscCloses), '');
end;

/// <summary>Je Zeichen von AName (1-basiert), ob es zum Getippten APattern gehört.</summary>
function NameMarks(const APattern, AName: string): TArray<Boolean>;
var
  mPosition: Integer;
begin
  SetLength(Result, Length(AName) + 1);
  for mPosition in TDpccItemPresentation.Highlights(APattern, AName) do
  begin
    if (mPosition >= 1) and (mPosition <= Length(AName)) then
    begin
      Result[mPosition] := True;
    end;
  end;
end;

/// <summary>Letztes Zeichen des Laufs gleicher Hervorhebung ab AStart.</summary>
function RunEnd(const AMarks: TArray<Boolean>; AStart, ALength: Integer): Integer;
begin
  Result := AStart;
  while (Result < ALength) and (AMarks[Result + 1] = AMarks[AStart]) do
  begin
    Inc(Result);
  end;
end;

procedure TDpccCompletionPopupPainter.DrawCheck(const ARow: TRect; AChecked: Boolean);
var
  mBox: TRect;
  mSize, mTop: Integer;
  mPoints: array[0..2] of TPoint;
begin
  mSize := Scale(13);
  mTop := ARow.Top + (ARow.Height - mSize) div 2;
  mBox := Rect(ARow.Left + Scale(7), mTop, ARow.Left + Scale(7) + mSize, mTop + mSize);
  // Eckig und flach (S8): leer nur der Rand, gewählt gefüllt mit Haken.
  if not AChecked then
  begin
    FrameBox(mBox, Colors.Muted);
    Exit;
  end;
  FillBox(mBox, Colors.Accent);
  // Haken in der Flächenfarbe.
  mPoints[0] := Point(mBox.Left + MulDiv(mSize, 3, 13), mBox.Top + MulDiv(mSize, 7, 13));
  mPoints[1] := Point(mBox.Left + MulDiv(mSize, 5, 13), mBox.Top + MulDiv(mSize, 10, 13));
  mPoints[2] := Point(mBox.Left + MulDiv(mSize, 10, 13), mBox.Top + MulDiv(mSize, 3, 13));
  Canvas.Pen.Color := ToColor(Colors.Surface);
  Canvas.Pen.Width := Max(1, Scale(2));
  Canvas.Polyline(mPoints);
  Canvas.Pen.Width := 1;
end;

function TDpccCompletionPopupPainter.SelectionText: TDpccColor;
begin
  // Wie in der Liste der IDE: Hebt sich die Auswahl kräftig ab (hell auf dunkler Fläche bzw. umgekehrt), steht
  // der Text in der Farbe der Fläche, sonst in der Textfarbe.
  if TDpccColorMath.IsDark(Colors.Selection) = TDpccColorMath.IsDark(Colors.Surface) then
  begin
    Result := Colors.Text;
  end
  else
  begin
    Result := Colors.Surface;
  end;
end;

function TDpccCompletionPopupPainter.DrawName(const AName: string; ALeft, ARight: Integer; const ARow: TRect;
  AColor: TDpccColor; out ATruncated: Boolean): Integer;
var
  mMarks: TArray<Boolean>;
  mIndex, mRun, mX, mWidth: Integer;
  mPart: TRect;
  mText: string;
begin
  Canvas.Font := UIFont;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(AColor);
  Canvas.Brush.Style := bsClear;
  mWidth := Canvas.TextWidth(AName);
  ATruncated := ALeft + mWidth > ARight;
  if ATruncated or (FPattern = '') then
  begin
    // Gekürzt ohne Unterstreichung: Die Positionen passen nicht mehr zur Ellipse.
    mPart := Rect(ALeft, ARow.Top, Max(ALeft, ARight), ARow.Bottom);
    DrawText(Canvas.Handle, PChar(AName), -1, mPart, cTextFlags or DT_END_ELLIPSIS);
    Canvas.Font.Style := [];
    Exit(Min(ALeft + mWidth, Max(ALeft, ARight)));
  end;
  // Getippte Zeichen unterstrichen wie in der Code-Insight-Liste der IDE; Läufe gleicher Markierung nacheinander.
  mMarks := NameMarks(FPattern, AName);
  mX := ALeft;
  mIndex := 1;
  while mIndex <= Length(AName) do
  begin
    mRun := RunEnd(mMarks, mIndex, Length(AName));
    mText := Copy(AName, mIndex, mRun - mIndex + 1);
    if mMarks[mIndex] then
    begin
      Canvas.Font.Style := [fsBold, fsUnderline];
    end
    else
    begin
      Canvas.Font.Style := [fsBold];
    end;
    mPart := Rect(mX, ARow.Top, ARight, ARow.Bottom);
    DrawText(Canvas.Handle, PChar(mText), -1, mPart, cTextFlags);
    Inc(mX, Canvas.TextWidth(mText));
    mIndex := mRun + 1;
  end;
  Canvas.Font.Style := [];
  Result := mX;
end;

procedure TDpccCompletionPopupPainter.DrawRow(ARow, APosition: Integer);
var
  mItem: TDpccCompletionItem;
  mPlain: TDpccPlainRow;
  mRow, mPart: TRect;
  mSelected, mTruncated, mNameCut: Boolean;
  mLeft, mRight, mX, mWidth: Integer;
  mTextColor, mKindColor, mMutedColor, mNameColor, mTailColor: TDpccColor;
  mTail: string;
begin
  mItem := FItems[FOrder[APosition]];
  mRow := RowRect(ARow);
  mSelected := APosition = FSelected;
  // Geerbt (#419), in der aktiven Konfiguration nicht vorhanden (#476) bzw. Rest ohne Treffer (#497): gedämpft;
  // die gewählte Zeile bleibt voll lesbar.
  FDimRow := ((FOptions.DimInherited and (mItem.Depth > 0)) or mItem.Unavailable or ((FRestFrom >= 0) and
    (APosition > FRestFrom))) and not mSelected;
  if mSelected then
  begin
    // Auswahl flach über die ganze Zeile wie in der Liste der IDE: ohne Rundung, Rahmen und Marke.
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Colors.Selection);
    Canvas.FillRect(mRow);
    mTextColor := SelectionText;
    mKindColor := mTextColor;
    mMutedColor := mTextColor;
    mNameColor := mTextColor;
  end
  else
  begin
    mTextColor := Dim(Colors.Text);
    mKindColor := Dim(Colors.KindLabel);
    mMutedColor := Dim(Colors.Muted);
    // Aktionen (#444, #471) und Hinweise (#466) in Akzentfarbe.
    if mItem.IsAction or mItem.Hint then
    begin
      mNameColor := Dim(Colors.Accent);
    end
    else
    begin
      mNameColor := mTextColor;
    end;
  end;
  // Mengenmodus (#448): Kontrollkästchen vor der Art.
  if mItem.SetOf <> '' then
  begin
    DrawCheck(mRow, mItem.Checked);
    Inc(mRow.Left, Scale(cCheckWidth));
  end;
  mPlain := RowOf(mItem);
  mLeft := mRow.Left + Scale(cInset);
  mRight := mRow.Right - Scale(cInset);
  // Art als Wort in eigener Spalte (Breite nach „constructor“ wie im Hover-Tooltip).
  if mPlain.Kind <> '' then
  begin
    mPart := Rect(mLeft, mRow.Top, Max(mLeft, Min(mRight, mLeft + KindWidth - Scale(cInset))), mRow.Bottom);
    Canvas.Font := UIFont;
    Canvas.Font.Color := ToColor(mKindColor);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(mPlain.Kind), -1, mPart, cTextFlags or DT_END_ELLIPSIS);
  end;
  Inc(mLeft, KindWidth);
  mTruncated := False;
  // Rechts gedämpft „+ Unit“ und Warnungen, solange dem Namen genug Platz bleibt.
  if mPlain.Trailer <> '' then
  begin
    Canvas.Font := UIFont;
    mWidth := Canvas.TextWidth(mPlain.Trailer);
    if mRight - mWidth - Scale(cGap) >= mLeft + Scale(60) then
    begin
      Canvas.Font.Color := ToColor(mMutedColor);
      Canvas.Brush.Style := bsClear;
      mPart := Rect(mRight - mWidth, mRow.Top, mRight, mRow.Bottom);
      DrawText(Canvas.Handle, PChar(mPlain.Trailer), -1, mPart, cTextFlags);
      Dec(mRight, mWidth + Scale(cGap));
    end
    else
    begin
      mTruncated := True;
    end;
  end;
  mX := DrawName(mItem.Name, mLeft, mRight, mRow, mNameColor, mNameCut);
  mTruncated := mTruncated or mNameCut;
  // Rest der Signatur direkt hinter dem Namen, sonst das Detail abgesetzt und gedämpft; zu lang: mit „…“.
  mTail := '';
  mTailColor := mTextColor;
  if mPlain.Params <> '' then
  begin
    mTail := mPlain.Params;
  end
  else if mPlain.Detail <> '' then
  begin
    mTail := mPlain.Detail;
    mTailColor := mMutedColor;
    Inc(mX, Scale(cGap));
  end;
  if (mTail <> '') and not mNameCut then
  begin
    Canvas.Font := UIFont;
    if mX + Scale(20) <= mRight then
    begin
      Canvas.Font.Color := ToColor(mTailColor);
      Canvas.Brush.Style := bsClear;
      mPart := Rect(mX, mRow.Top, mRight, mRow.Bottom);
      DrawText(Canvas.Handle, PChar(mTail), -1, mPart, cTextFlags or DT_END_ELLIPSIS);
      mTruncated := mTruncated or (mX + Canvas.TextWidth(mTail) > mRight);
    end
    else
    begin
      mTruncated := True;
    end;
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Font := Font;
  MarkTruncated(ARow, mTruncated);
  FDimRow := False;
end;

procedure TDpccCompletionPopupPainter.MarkTruncated(ARow: Integer; ATruncated: Boolean);
begin
  if ARow >= Length(FTruncated) then
  begin
    SetLength(FTruncated, ARow + 1);
  end;
  FTruncated[ARow] := ATruncated;
end;

procedure TDpccCompletionPopupPainter.DrawScrollBar;
var
  mTrack, mThumb: TRect;
  mTotal, mVisible, mThumbHeight, mThumbTop: Integer;
begin
  mTotal := Length(FOrder);
  mVisible := RowCount;
  if mTotal <= mVisible then
  begin
    Exit;
  end;
  mTrack := Rect(ListWidth - Pad - Scale(5), ListTop + Scale(2), ListWidth - Pad - Scale(1),
    ListTop + mVisible * RowHeight - Scale(2));
  mThumbHeight := Max(Scale(16), mTrack.Height * mVisible div mTotal);
  mThumbTop := mTrack.Top + (mTrack.Height - mThumbHeight) * FTop div Max(1, mTotal - mVisible);
  mThumb := Rect(mTrack.Left, mThumbTop, mTrack.Right, mThumbTop + mThumbHeight);
  TDpccDraw.Thumb(Canvas, mThumb, Colors);
end;

procedure TDpccCompletionPopupPainter.Paint;
var
  mTimings: TDpccQueryTimings;
  mStamp: Int64;
begin
  mTimings := nil;
  mStamp := 0;
  if TDpccQueryTimings.Enabled then
  begin
    mTimings := TDpccQueryTimings.Shared;
    mStamp := TDpccQueryTimings.Stamp;
  end;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  if FEmpty.Showing then
  begin
    PaintEmpty;
  end
  else
  begin
    DrawList;
  end;
  // Kein Griff: Die Breite lässt sich am rechten Rand ziehen.
  PaintBorder;
  if mTimings <> nil then
  begin
    mTimings.Drawn(TDpccQueryTimings.MsSince(mStamp));
  end;
end;

procedure TDpccCompletionPopupPainter.DrawList;
var
  mRow: Integer;
  mFooter: TDpccCompletionFooter;
begin
  DrawSyntax;
  for mRow := 0 to RowCount - 1 do
  begin
    if FTop + mRow < Length(FOrder) then
    begin
      if TDpccRanking.IsHeader(FOrder[FTop + mRow]) then
      begin
        DrawHeader(mRow, FTop + mRow);
      end
      else
      begin
        DrawRow(mRow, FTop + mRow);
      end;
    end;
  end;
  DrawScrollBar;
  mFooter := TDpccCompletionTexts.Footer(ListState);
  DrawFooter(mFooter.Left, mFooter.Right);
end;

procedure TDpccCompletionPopupPainter.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  HideTip;
  FHoverPosition := -1;
end;

procedure TDpccCompletionPopupPainter.HideTip;
begin
  FTipTimer.Enabled := False;
  FTip.HidePopup;
end;

function TDpccCompletionPopupPainter.TipRow(out ARow: Integer): Boolean;
begin
  ARow := FHoverPosition - FTop;
  Result := IsShown and (FHoverPosition >= 0) and (FHoverPosition < Length(FOrder)) and (ARow >= 0) and
    (ARow < Length(FTruncated));
  Result := Result and FTruncated[ARow] and not TDpccRanking.IsHeader(FOrder[FHoverPosition]);
end;

procedure TDpccCompletionPopupPainter.TipTimer(Sender: TObject);
var
  mRow: Integer;
  mItem: TDpccCompletionItem;
  mArea: TRect;
begin
  FTipTimer.Enabled := False;
  if not TipRow(mRow) then
  begin
    Exit;
  end;
  mItem := FItems[FOrder[FHoverPosition]];
  FTip.Colors := Colors;
  FTip.SetScaling(PPI, 1, Font.Name, Font.Size);
  mArea := RowRect(mRow);
  FTip.ShowText(TDpccCompletionTexts.TipText(mItem, ItemTags(mItem)),
    ClientToScreen(Point(mArea.Left, mArea.Bottom + Scale(2))));
end;

end.
