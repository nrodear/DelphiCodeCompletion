unit dpcc.UI.Completion.Popup;

// Vervollständigungs-Popup (#410, #413): virtuelle Liste ohne Fokus. Gezeichnet
// werden nur die sichtbaren Zeilen; Filtern liefert nur ein neues Index-Array
// (AOrder), die Einträge selbst werden nicht kopiert.
// Schlicht (S6): Aussehen wie die Code-Insight-Liste der IDE und der Hover-Tooltip, flacher Rahmen,
// Farben aus TDpccIdeStyle.CompletionListColors (setzt dpcc.IDE.Completion.EditorOpen). Je Zeile die Art als Wort
// (procedure, function, type, …), der Name fett, dahinter die Signatur bzw. gedämpft das Detail, rechts gedämpft
// „+ Unit“ und Warnungen. Fußzeile nur mit Tasten bzw. Hinweisen. Zeichnen: dpcc.UI.Completion.PopupPainter.
// Das frühere Aussehen (Badges, Tags als Flächen, Filter-Chips, Sternspalte, Auswahlmarke, Griff, Zählung „n von
// m“, Detailpanel mit Überladungen und XMLDoc) ist seit S7a entfernt.
//   - Gekürzte Zeilen zeigen nach 600 ms Verweilen mit der Maus den vollen Text (#420).
//   - Breite (#416): Der rechte Rand ist mit der Maus ziehbar; Doppelklick unten rechts stellt die automatische
//     Breite wieder her. Ohne gezogene Breite wächst die Liste mit dem breitesten Eintrag. Gezogen wird ohne
//     Aktivierung, der Editor behält den Fokus.
// Die Position ergibt sich aus dem Anker (Caret-Rechteck in Bildschirm-
// koordinaten): darunter, sonst darüber; nie über den Monitorrand hinaus.
// Ohne Treffer zeigt es den leeren Zustand (#423). Breite und Höhe wachsen bei
// Bedarf, schrumpfen während einer Sitzung aber nicht (#416), damit es beim
// Filtern und Blättern nicht springt.
// Mengenmodus (#448): Kontrollkästchen vor der Art, Überschrift „TAnchors · Menge von TAnchorKind“, Fußzeile mit
// Leertaste und „n gewählt“.
// Diagnosemodus (#479): Ist die Messung an, meldet Paint seine Dauer an
// TDpccQueryTimings (Schritt „Zeichnen“); aus kein Zeitstempel.
// Favoriten (#458): Angeheftete Einträge stehen oben (Rangfolge im Controller) und werden als Favorit angesagt;
// anheften bzw. lösen mit Strg+D (IDE-Schicht). ShowNotice zeigt einen Hinweis links in der Fußzeile („Schon 5
// Favoriten bei TDataSet …“) bis zum nächsten getippten Zeichen bzw. Schließen; im leeren Zustand den Hinweis auf das
// zweite Strg+Leertaste (L3), dann mit „Esc schließt“ rechts daneben.
// Rest der Liste (#497): Einträge unter der Überschrift „Weitere Einträge“ (TDpccRanking.cRestHeader) sind
// gedämpft; die Fußzeile nennt „Keine Treffer“, wenn nur der Rest steht.
// Barrierefreiheit (#447): Die Einträge sind für UI Automation Listeneinträge (IDpccAccessibleItems) mit
// Zustand aus den Tags.
// Unvollständiger Code (#457, IDpccCompletionSyntaxView): Über der Liste steht eine Leiste in Warnfarbe
// „Ergebnisse möglicherweise unvollständig · Syntaxfehler in Zeile n“ (unbekannt: „Kontext unklar · …“), auch im
// leeren Zustand, der dann den Fehlertext nennt. Klick auf die unterstrichene Zeilenangabe meldet OnSyntaxLine.
// Aufbau: Die Klasse erbt ihre Teile über die Kette TDpccCompletionPopupState (Zustand, Höhen) →
// TDpccCompletionPopupLayout (Lage) → TDpccCompletionPopupPainter (Zeichnen, Tooltip); hier stehen Maus,
// Anzeige der Liste und Barrierefreiheit. Texte in dpcc.UI.Completion.PopupTexts.

interface

uses
  System.Classes,
  System.Types,
  Vcl.Controls,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Controller,
  dpcc.UI.Popup.Accessibility,
  dpcc.UI.Completion.PopupState,
  dpcc.UI.Completion.PopupPainter;

type
  TDpccCompletionPopup = class(TDpccCompletionPopupPainter, IDpccCompletionView, IDpccCompletionSyntaxView,
    IDpccAccessibleItems)
  private
    /// <summary>Breite ziehen (#416): Bildschirmkoordinaten, weil das Fenster beim Ziehen mitwächst.</summary>
    procedure DragTo;
    /// <summary>Mauszeiger über dem rechten Rand bzw. der Zeilenangabe der Warnleiste.</summary>
    procedure UpdateCursor(AX, AY: Integer);
    procedure AnnounceSelected;
    { IDpccAccessibleItems }
    function AccessibleCount: Integer;
    function AccessibleSelected: Integer;
    function AccessibleId(APosition: Integer): Integer;
    function AccessibleName(APosition: Integer): string;
    function AccessibleStatus(APosition: Integer): string;
    function AccessibleHelp(APosition: Integer): string;
    function AccessibleIsHeader(APosition: Integer): Boolean;
    function AccessibleBounds(APosition: Integer; out ARect: TRect): Boolean;
    procedure AccessibleSelect(APosition: Integer);
    /// <summary>Liste für UI Automation, sofern schon angefragt.</summary>
    function AccessibleList: TDpccAccessibleList;
  protected
    function CreateAccessible(ARole: Integer; const AName: string): TDpccAccessibleElement; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    /// <summary>Hinweis links in der Fußzeile (#458), auch für die Sprachausgabe; gilt bis zum nächsten
    /// getippten Zeichen bzw. Schließen.</summary>
    procedure ShowNotice(const AText: string);
    { IDpccCompletionView }
    procedure ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    { IDpccCompletionSyntaxView }
    procedure ShowSyntax(const ANotice: TDpccSyntaxNotice);
    property OnSelect: TDpccPositionEvent read FEvents.OnSelect write FEvents.OnSelect;
    property OnAccept: TDpccPositionEvent read FEvents.OnAccept write FEvents.OnAccept;
    /// <summary>Klick auf die Zeilenangabe der Warnleiste (#457).</summary>
    property OnSyntaxLine: TDpccSyntaxLineEvent read FEvents.OnSyntaxLine write FEvents.OnSyntaxLine;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  dpcc.Core.Completion.Width,
  dpcc.Core.Completion.Ranking,
  dpcc.Core.Completion.Presentation,
  dpcc.UI.Completion.Strings,
  dpcc.UI.Completion.PopupTexts;

const
  // Rand neben dem Text „keine Treffer für …“ in der Breite des Fensters.
  cNoMatchesPadding = 32;
  // Ränder und Abstand der Fußzeile mit Hinweis und „Esc schließt“ (DrawFooter: 9 + 10 + 9) samt Luft.
  cNoticePadding = 40;

{ TDpccCompletionPopup }

procedure TDpccCompletionPopup.ShowSyntax(const ANotice: TDpccSyntaxNotice);
begin
  FSyntax := ANotice;
  FSyntaxLink := Rect(0, 0, 0, 0);
  if FSyntax.Trust <> TDpccSyntaxTrust.Sure then
  begin
    // Die Leiste soll ganz lesbar sein: Breite wächst wie beim leeren Zustand.
    Canvas.Font := UIFont;
    FSessionWidth := Max(FSessionWidth, Canvas.TextWidth(TDpccCompletionTexts.SyntaxLead(FSyntax.Trust) +
      TDpccCompletionTexts.SyntaxLineText(FSyntax.Line)) + Scale(40));
    Canvas.Font := Font;
  end;
  if IsShown then
  begin
    Relayout;
  end;
  Invalidate;
end;

procedure TDpccCompletionPopup.ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
  ASelected: Integer; const APattern: string);
var
  mSameList: Boolean;
  mIndex: Integer;
begin
  // Nur die Auswahl bewegt (Pfeiltasten): dieselben Arrays, Breite nicht neu messen (#616).
  mSameList := not FEmpty.Showing and (Pointer(AItems) = Pointer(FItems)) and (Pointer(AOrder) = Pointer(FOrder)) and
    (APattern = FPattern) and IsShown;
  // Weitertippen verwirft den Hinweis der Fußzeile (#458).
  if APattern <> FPattern then
  begin
    FNotice := '';
  end;
  FEmpty.Showing := False;
  FItems := AItems;
  FOrder := AOrder;
  FSelected := ASelected;
  FPattern := APattern;
  FRestFrom := -1;
  for mIndex := 0 to High(FOrder) do
  begin
    if FOrder[mIndex] = TDpccRanking.cRestHeader then
    begin
      FRestFrom := mIndex;
      Break;
    end;
  end;
  EnsureSelectedVisible;
  if mSameList then
  begin
    Relayout;
  end
  else
  begin
    PlaceAndShow;
  end;
  AnnounceSelected;
  // UI Automation (#447): neue Einträge melden, dann den gewählten.
  if AccessibleList <> nil then
  begin
    if not mSameList then
    begin
      AccessibleList.ItemsChanged;
    end;
    AccessibleList.SelectionChanged;
  end;
end;

procedure TDpccCompletionPopup.AnnounceSelected;
var
  mKind: string;
begin
  if (FSelected < 0) or (FSelected > High(FOrder)) or TDpccRanking.IsHeader(FOrder[FSelected]) then
  begin
    Exit;
  end;
  mKind := TDpccCompletionTexts.KindText(FItems[FOrder[FSelected]].Kind);
  // Angeheftet (#458) mit ansagen.
  if FItems[FOrder[FSelected]].Favorite then
  begin
    if mKind <> '' then
    begin
      mKind := mKind + ', ';
    end;
    mKind := mKind + TDpccCompletionStrings.Text(TDpccCompletionTextId.AccessFavorite);
  end;
  Announce(TDpccItemPresentation.Announcement(FItems[FOrder[FSelected]], mKind,
    TDpccCompletionStrings.Text(TDpccCompletionTextId.AccessPosition), FSelected + 1, Length(FOrder)));
end;

procedure TDpccCompletionPopup.ShowNotice(const AText: string);
begin
  FNotice := AText;
  if AText <> '' then
  begin
    Announce(AText);
  end;
  // Leerer Zustand (L3, „Strg+Leertaste erneut …“): Hinweis links, „Esc schließt“ rechts; die Breite wächst, damit
  // beide ganz lesbar sind.
  if FEmpty.Showing and (AText <> '') then
  begin
    Canvas.Font := UIFont;
    FSessionWidth := Max(FSessionWidth, Canvas.TextWidth(AText) +
      Canvas.TextWidth(TDpccCompletionStrings.Text(TDpccCompletionTextId.EscCloses)) + Scale(cNoticePadding));
    Canvas.Font := Font;
    if IsShown then
    begin
      Relayout;
    end;
  end;
  Invalidate;
end;

procedure TDpccCompletionPopup.HideList;
begin
  HideTip;
  HidePopup;
  FNotice := '';
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FTop := 0;
  FSessionWidth := 0;
  FSessionHeight := 0;
  FEmpty.Showing := False;
  FDrag.Active := False;
  FSyntax := Default(TDpccSyntaxNotice);
  FSyntaxLink := Rect(0, 0, 0, 0);
end;

procedure TDpccCompletionPopup.ShowEmpty(const APrefix: string; ATotal: Integer);
begin
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FRestFrom := -1;
  FTop := 0;
  FEmpty.Prefix := APrefix;
  FEmpty.Total := ATotal;
  FEmpty.Showing := True;
  // Ein Hinweis der Liste (#458) gilt nicht für den leeren Zustand; den eigenen setzt ShowNotice danach (L3).
  FNotice := '';
  if AccessibleList <> nil then
  begin
    AccessibleList.ItemsChanged;
  end;
  Canvas.Font := UIFont;
  FSessionWidth := Max(FSessionWidth, Max(Scale(cMinWidth),
    Canvas.TextWidth(TDpccCompletionStrings.Fmt(TDpccCompletionTextId.NoMatchesFor, [APrefix])) +
    Scale(cNoMatchesPadding)));
  Canvas.Font := Font;
  Relayout;
end;

function TDpccCompletionPopup.CreateAccessible(ARole: Integer; const AName: string): TDpccAccessibleElement;
begin
  Result := TDpccAccessibleList.Create(Handle, AName, Self);
end;

function TDpccCompletionPopup.AccessibleList: TDpccAccessibleList;
begin
  Result := nil;
  if AccessibleObject is TDpccAccessibleList then
  begin
    Result := TDpccAccessibleList(AccessibleObject);
  end;
end;

function TDpccCompletionPopup.AccessibleCount: Integer;
begin
  Result := 0;
  if not FEmpty.Showing and IsShown then
  begin
    Result := Length(FOrder);
  end;
end;

function TDpccCompletionPopup.AccessibleSelected: Integer;
begin
  Result := FSelected;
end;

function TDpccCompletionPopup.AccessibleId(APosition: Integer): Integer;
begin
  // Index in FItems bleibt beim Filtern gleich; Überschriften sind negativ und kommen je Liste einmal vor.
  Result := FOrder[APosition];
end;

function TDpccCompletionPopup.AccessibleName(APosition: Integer): string;
begin
  if TDpccRanking.IsHeader(FOrder[APosition]) then
  begin
    Result := TDpccCompletionTexts.HeaderText(FItems, FOrder, APosition);
  end
  else
  begin
    Result := FItems[FOrder[APosition]].Name;
  end;
end;

function TDpccCompletionPopup.AccessibleStatus(APosition: Integer): string;
var
  mStatus: string;
  mTag: TDpccTag;
begin
  Result := '';
  if TDpccRanking.IsHeader(FOrder[APosition]) then
  begin
    Exit;
  end;
  // Dieselben Angaben wie die Tags der Zeile; nicht nur Farbe (#447).
  for mTag in ItemTags(FItems[FOrder[APosition]]) do
  begin
    if Result = '' then
    begin
      Result := mTag.Text;
    end
    else
    begin
      Result := Result + ', ' + mTag.Text;
    end;
  end;
  if FItems[FOrder[APosition]].Favorite then
  begin
    mStatus := TDpccCompletionStrings.Text(TDpccCompletionTextId.AccessFavorite);
    if Result <> '' then
    begin
      Result := mStatus + ', ' + Result;
    end
    else
    begin
      Result := mStatus;
    end;
  end;
end;

function TDpccCompletionPopup.AccessibleHelp(APosition: Integer): string;
begin
  Result := '';
  if not TDpccRanking.IsHeader(FOrder[APosition]) then
  begin
    Result := TDpccCompletionTexts.DetailText(FItems[FOrder[APosition]]);
  end;
end;

function TDpccCompletionPopup.AccessibleIsHeader(APosition: Integer): Boolean;
begin
  Result := TDpccRanking.IsHeader(FOrder[APosition]);
end;

function TDpccCompletionPopup.AccessibleBounds(APosition: Integer; out ARect: TRect): Boolean;
begin
  Result := IsShown and (APosition >= FTop) and (APosition < FTop + RowCount) and (APosition <= High(FOrder));
  if not Result then
  begin
    ARect := TRect.Empty;
    Exit;
  end;
  ARect := RowRect(APosition - FTop);
  ARect.TopLeft := ClientToScreen(ARect.TopLeft);
  ARect.BottomRight := ClientToScreen(ARect.BottomRight);
end;

procedure TDpccCompletionPopup.AccessibleSelect(APosition: Integer);
begin
  // Wie ein Klick auf die Zeile: Der Controller wählt und zeigt die Liste neu.
  if Assigned(FEvents.OnSelect) then
  begin
    FEvents.OnSelect(APosition);
  end;
end;

procedure TDpccCompletionPopup.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mPosition: Integer;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  // Zeilenangabe der Warnleiste (#457).
  if PtInRect(FSyntaxLink, Point(X, Y)) and Assigned(FEvents.OnSyntaxLine) then
  begin
    FEvents.OnSyntaxLine(FSyntax.Line, FSyntax.Character);
    Exit;
  end;
  // Rechter Rand (#416): Breite der Liste ziehen.
  if HitArea(X, Y) <> TDpccHitArea.None then
  begin
    HideTip;
    FDrag.Active := True;
    FDrag.StartWidth := ListWidth;
    FDrag.StartX := Mouse.CursorPos.X;
    Exit;
  end;
  mPosition := RowAt(X, Y);
  if (mPosition >= 0) and Assigned(FEvents.OnSelect) then
  begin
    FEvents.OnSelect(mPosition);
  end;
end;

procedure TDpccCompletionPopup.DblClick;
var
  mPoint_: TPoint;
begin
  inherited;
  // Doppelklick unten rechts: automatische Breite (#416).
  mPoint_ := ScreenToClient(Mouse.CursorPos);
  if HitArea(mPoint_.X, mPoint_.Y) = TDpccHitArea.Corner then
  begin
    FManualListWidth := 0;
    FDrag.Active := False;
    Relayout;
    Invalidate;
    WidthChanged;
    Exit;
  end;
  if (FSelected >= 0) and Assigned(FEvents.OnAccept) then
  begin
    FEvents.OnAccept(FSelected);
  end;
end;

procedure TDpccCompletionPopup.DragTo;
begin
  FManualListWidth := TDpccPopupWidth.Fit(Logical(FDrag.StartWidth + Mouse.CursorPos.X - FDrag.StartX), cMinWidth,
    cMaxWidth);
  Relayout;
  Invalidate;
end;

procedure TDpccCompletionPopup.UpdateCursor(AX, AY: Integer);
begin
  if HitArea(AX, AY) <> TDpccHitArea.None then
  begin
    Cursor := crSizeWE;
  end
  else if PtInRect(FSyntaxLink, Point(AX, AY)) then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
end;

procedure TDpccCompletionPopup.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mPosition: Integer;
begin
  inherited;
  if FDrag.Active then
  begin
    DragTo;
    Exit;
  end;
  UpdateCursor(X, Y);
  mPosition := RowAt(X, Y);
  if mPosition = FHoverPosition then
  begin
    Exit;
  end;
  HideTip;
  FHoverPosition := mPosition;
  FTipTimer.Enabled := mPosition >= 0;
end;

procedure TDpccCompletionPopup.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if not FDrag.Active then
  begin
    Exit;
  end;
  FDrag.Active := False;
  WidthChanged;
end;

function TDpccCompletionPopup.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  HideTip;
  if WheelDelta > 0 then
  begin
    FTop := Max(0, FTop - 3);
  end
  else
  begin
    FTop := Min(Max(0, Length(FOrder) - FVisibleRows), FTop + 3);
  end;
  Invalidate;
end;

end.
