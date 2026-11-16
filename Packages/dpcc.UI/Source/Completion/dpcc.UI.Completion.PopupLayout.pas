unit dpcc.UI.Completion.PopupLayout;

// Vervollständigungs-Popup (#410), Stufe Lage: wo Liste, Zeilen und Warnleiste liegen, wie breit die Liste wird
// (#416) und wohin das Fenster kommt (darunter, sonst darüber; nie über den Monitorrand). Kette und Aussehen:
// dpcc.UI.Completion.Popup.
// Die Breite misst wie die schlichte Liste (S6) zeichnet: Art-Spalte, fetter Name, Signatur bzw. Detail und den
// Text rechts. Detailpanel, Chips und Sternspalte gibt es seit S7a nicht mehr.

interface

uses
  System.Types,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Presentation,
  dpcc.UI.Completion.PopupTexts,
  dpcc.UI.Completion.PopupState;

type
  TDpccCompletionPopupLayout = class(TDpccCompletionPopupState)
  protected
    function Logical(APixels: Integer): Integer;
    function ListWidth: Integer;
    /// <summary>Höhe der Warnleiste (#457); 0 ohne Hinweis.</summary>
    function SyntaxHeight: Integer;
    function ListTop: Integer;
    function ListHeight: Integer;
    procedure Relayout;
    function RowAt(AX, AY: Integer): Integer;
    function RowRect(ARow: Integer): TRect;
    procedure EnsureSelectedVisible;
    procedure PlaceAt(AListWidth, AHeight: Integer);
    function HitArea(AX, AY: Integer): TDpccHitArea;
    /// <summary>Breite der Liste: Art-Spalte, fetter Name, Signatur bzw. Detail, Text rechts.</summary>
    function MeasureWidth: Integer;
    /// <summary>Breite der Art-Spalte: „constructor“ plus Abstand (wie im Hover-Tooltip).</summary>
    function KindWidth: Integer;
    /// <summary>Text rechts in der Zeile: „+ Unit“ und Warnungen (PlainTags) in Worten.</summary>
    function Trailer(const AItem: TDpccCompletionItem): string;
    /// <summary>Zeile zu AItem: Art, Signatur bzw. Detail, Text rechts.</summary>
    function RowOf(const AItem: TDpccCompletionItem): TDpccPlainRow;
    /// <summary>Tags der Zeile; ohne ShowVariantBranch fehlt „Zweig 0“ (#846).</summary>
    function ItemTags(const AItem: TDpccCompletionItem): TDpccTags;
    procedure PlaceAndShow;
    procedure WidthChanged;
    /// <summary>Gezeigte Liste für die Texte der Fußzeile.</summary>
    function ListState: TDpccCompletionList;
  public
    function PageSize: Integer;
    /// <summary>Caret-Rechteck in Bildschirmkoordinaten; vor dem ersten ShowList setzen.</summary>
    property Anchor: TRect read FAnchor write FAnchor;
    property VisibleRows: Integer read FVisibleRows write FVisibleRows;
    /// <summary>Geerbte Member abgeschwächt zeichnen (#419).</summary>
    property DimInherited: Boolean read FOptions.DimInherited write FOptions.DimInherited;
    /// <summary>Marke „Zweig 0“ an Feldern varianter Records (#846, completion.variantBranch); Vorgabe an.
    /// </summary>
    property ShowVariantBranch: Boolean read FOptions.ShowVariantBranch write FOptions.ShowVariantBranch;
    /// <summary>Der Server indiziert noch (#492, #457): Die Fußzeile meldet „eingeschränkt“; die Liste
    /// zeigt den vorhandenen Stand.</summary>
    property Limited: Boolean read FOptions.Limited write FOptions.Limited;
    /// <summary>Aktives Ziel („Win32 · Debug“) für die Fußzeile (#476); '' = keins bekannt.</summary>
    property Target: string read FOptions.Target write FOptions.Target;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Graphics,
  dpcc.Core.Completion.Width,
  dpcc.Core.Completion.Ranking,
  dpcc.UI.Completion.Strings;

const
  // Rand der Fußzeile in der Breite des Fensters.
  cFooterPadding = 18;

{ TDpccCompletionPopupLayout }

function TDpccCompletionPopupLayout.ListWidth: Integer;
begin
  Result := TDpccPopupWidth.Effective(Scale(FManualListWidth), FSessionWidth);
end;

function TDpccCompletionPopupLayout.Logical(APixels: Integer): Integer;
begin
  Result := MulDiv(APixels, 96, PPI);
end;

function TDpccCompletionPopupLayout.ListHeight: Integer;
begin
  if FEmpty.Showing then
  begin
    Result := 2 * Pad + SyntaxHeight + 2 * RowHeight + FooterHeight;
  end
  else
  begin
    Result := 2 * Pad + SyntaxHeight + RowCount * RowHeight + FooterHeight;
  end;
end;

procedure TDpccCompletionPopupLayout.Relayout;
begin
  FSessionHeight := ListHeight;
  PlaceAt(ListWidth, FSessionHeight);
end;

function TDpccCompletionPopupLayout.SyntaxHeight: Integer;
begin
  if FSyntax.Trust = TDpccSyntaxTrust.Sure then
  begin
    Exit(0);
  end;
  EnsureMetrics;
  Result := FMetrics.SyntaxHeight;
end;

function TDpccCompletionPopupLayout.ListTop: Integer;
begin
  Result := Pad + SyntaxHeight;
end;

function TDpccCompletionPopupLayout.PageSize: Integer;
begin
  Result := FVisibleRows;
end;

function TDpccCompletionPopupLayout.RowRect(ARow: Integer): TRect;
var
  mHeight: Integer;
begin
  mHeight := RowHeight;
  Result := Rect(Pad, ListTop + ARow * mHeight, ListWidth - Pad - ScrollReserve, ListTop + (ARow + 1) * mHeight);
end;

function TDpccCompletionPopupLayout.RowAt(AX, AY: Integer): Integer;
begin
  if (AY < ListTop) or (AX < 0) or (AX >= ListWidth) then
  begin
    Exit(-1);
  end;
  Result := FTop + (AY - ListTop) div RowHeight;
  if (Result < FTop) or (Result >= Min(FTop + RowCount, Length(FOrder))) then
  begin
    Result := -1;
  end;
end;

procedure TDpccCompletionPopupLayout.EnsureSelectedVisible;
begin
  if FSelected < 0 then
  begin
    Exit;
  end;
  if FSelected < FTop then
  begin
    FTop := FSelected;
  end
  else if FSelected >= FTop + FVisibleRows then
  begin
    FTop := FSelected - FVisibleRows + 1;
  end;
  FTop := EnsureRange(FTop, 0, Max(0, Length(FOrder) - FVisibleRows));
end;

function TDpccCompletionPopupLayout.ItemTags(const AItem: TDpccCompletionItem): TDpccTags;
var
  mTag: TDpccTag;
begin
  Result := nil;
  for mTag in TDpccItemPresentation.Tags(AItem) do
  begin
    if FOptions.ShowVariantBranch or (mTag.Id <> TDpccTagId.VariantBranch) then
    begin
      Result := Result + [mTag];
    end;
  end;
end;

function TDpccCompletionPopupLayout.KindWidth: Integer;
begin
  Canvas.Font := UIFont;
  Result := Canvas.TextWidth(cKindSample) + Scale(cKindGap);
  Canvas.Font := Font;
end;

function TDpccCompletionPopupLayout.Trailer(const AItem: TDpccCompletionItem): string;
var
  mTag: TDpccTag;
begin
  Result := '';
  for mTag in TDpccItemPresentation.PlainTags(ItemTags(AItem)) do
  begin
    if Result <> '' then
    begin
      Result := Result + '   ';
    end;
    Result := Result + TDpccCompletionTexts.TagText(mTag);
  end;
end;

function TDpccCompletionPopupLayout.RowOf(const AItem: TDpccCompletionItem): TDpccPlainRow;
begin
  Result := TDpccItemPresentation.PlainRow(AItem, TDpccCompletionTexts.DetailText(AItem), Trailer(AItem));
end;

function TDpccCompletionPopupLayout.MeasureWidth: Integer;
var
  mPosition, mCount, mWidest, mWidth: Integer;
  mItem: TDpccCompletionItem;
  mRow: TDpccPlainRow;
begin
  // Nur die ersten Einträge messen, in der UI-Schrift; eine gezogene Breite (#416) hat Vorrang (ListWidth).
  mWidest := 0;
  mCount := Min(Length(FOrder), 200);
  for mPosition := 0 to mCount - 1 do
  begin
    if TDpccRanking.IsHeader(FOrder[mPosition]) then
    begin
      Continue;
    end;
    mItem := FItems[FOrder[mPosition]];
    mRow := RowOf(mItem);
    Canvas.Font := UIFont;
    Canvas.Font.Style := [fsBold];
    mWidth := Canvas.TextWidth(mItem.Name);
    Canvas.Font.Style := [];
    if mRow.Params <> '' then
    begin
      Inc(mWidth, Canvas.TextWidth(mRow.Params));
    end;
    if mRow.Detail <> '' then
    begin
      Inc(mWidth, Scale(cGap) + Canvas.TextWidth(mRow.Detail));
    end;
    if mRow.Trailer <> '' then
    begin
      Inc(mWidth, Scale(cGap) + Canvas.TextWidth(mRow.Trailer));
    end;
    if mItem.SetOf <> '' then
    begin
      Inc(mWidth, Scale(cCheckWidth));
    end;
    mWidest := Max(mWidest, mWidth);
  end;
  Canvas.Font := Font;
  // Art-Spalte, Ränder der Zeile, Ränder des Fensters und Scrollleiste.
  Inc(mWidest, KindWidth + Scale(2 * cInset) + 2 * Pad + ScrollReserve);
  Canvas.Font := UIFont;
  mWidest := Max(mWidest, Canvas.TextWidth(TDpccCompletionStrings.Text(TDpccCompletionTextId.FooterKeys)) +
    Scale(cFooterPadding));
  Canvas.Font := Font;
  Result := TDpccPopupWidth.Fit(mWidest, Scale(cMinWidth), Scale(cMaxWidth));
end;

procedure TDpccCompletionPopupLayout.PlaceAndShow;
begin
  // Nur wachsen, nie schrumpfen, solange die Sitzung läuft (#416).
  FSessionWidth := TDpccPopupWidth.Grow(FSessionWidth, MeasureWidth);
  Relayout;
end;

procedure TDpccCompletionPopupLayout.PlaceAt(AListWidth, AHeight: Integer);
var
  mBounds, mArea: TRect;
begin
  mArea := WorkAreaAt(FAnchor.TopLeft);
  // Die Liste bleibt am Wortanfang.
  mBounds := TRect.Create(Point(FAnchor.Left, FAnchor.Bottom + 2), AListWidth, AHeight);
  // Unten kein Platz: über die Zeile.
  if mBounds.Bottom > mArea.Bottom then
  begin
    mBounds.SetLocation(mBounds.Left, FAnchor.Top - AHeight - 2);
  end;
  if mBounds.Right > mArea.Right then
  begin
    mBounds.SetLocation(Max(mArea.Left, mArea.Right - AListWidth), mBounds.Top);
  end;
  if mBounds.Top < mArea.Top then
  begin
    mBounds.SetLocation(mBounds.Left, mArea.Top);
  end;
  ShowAt(mBounds);
end;

procedure TDpccCompletionPopupLayout.WidthChanged;
begin
  if Assigned(FEvents.OnWidthChanged) then
  begin
    FEvents.OnWidthChanged(FManualListWidth);
  end;
end;

function TDpccCompletionPopupLayout.HitArea(AX, AY: Integer): TDpccHitArea;
begin
  Result := TDpccHitArea.None;
  if AX >= ClientWidth - Scale(4) then
  begin
    if AY >= ClientHeight - Scale(16) then
    begin
      Result := TDpccHitArea.Corner;
    end
    else
    begin
      Result := TDpccHitArea.Edge;
    end;
  end;
end;

function TDpccCompletionPopupLayout.ListState: TDpccCompletionList;
begin
  Result.Items := FItems;
  Result.Order := FOrder;
  Result.Pattern := FPattern;
  Result.RestFrom := FRestFrom;
  Result.Limited := FOptions.Limited;
  Result.Target := FOptions.Target;
  Result.Notice := FNotice;
end;

end.
