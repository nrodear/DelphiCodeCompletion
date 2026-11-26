unit dpcc.IDE.Signature.FormatMarks;

// Farbige Platzhalter im Editor (#451): Solange der Parameter-Hint einer Formatroutine offen ist, bekommen jeder
// Platzhalter im Formatstring und sein Argument in der Liste [...] dieselbe Farbe (Palette Placeholders). Welche
// Stellen welche Farbe bekommen, rechnet TDpccSignatureFormats.Marks aus; hier bleibt das Zeichnen.
// - Show übernimmt die Stellen mit dem Text, auf den sie sich beziehen; Clear nimmt sie weg (Hint zu).
// - PaintLine (plsEndPaint) überzieht die Stellen halb durchsichtig, aber nur in Zeilen, die im Editor noch dem
//   angefragten Stand entsprechen. Nach einer Änderung bleibt die Zeile ungefärbt, bis die neue Antwort da ist.
// - Deckkraft je Stufe der Darstellung (LOOK2): TDpccIdeStyle.Look.MarkAlpha, Intensiv 110, Dezent 70 (wie vorher
//   fest), Unscheinbar 36 von 255. Die Farben der Marken hängen nicht von der Stufe ab.
// - completion.formatPlaceholders aus: Der Editor ruft Show nicht auf.
// Gesichert über TDpccFeature.Signature (#493). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  System.Generics.Collections,
  Winapi.Windows,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  dpcc.Core.Style.Color,
  dpcc.Core.Signature.Format,
  dpcc.Core.Editor.TabStops;

type
  TDpccIdeFormatMarks = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFileName: string;
    FLines: TArray<string>;
    FTabStops: TDpccTabStops;
    FByLine: TDictionary<Integer, TArray<TDpccFormatMark>>;
    procedure PaintMarks(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const AText: string;
      const AMarks: TArray<TDpccFormatMark>; ABack: TDpccColor);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class procedure Invalidate; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Färbt AMarks in AFileName; AText ist der Stand des Puffers, zu dem sie gehören, ATabStops die
    /// Tabulatorpositionen seiner Ansicht (TDpccEditorBuffer.TabStops).</summary>
    procedure Show(const AFileName, AText: string; const ATabStops: TDpccTabStops;
      const AMarks: TArray<TDpccFormatMark>);
    procedure Clear;
  end;

implementation

uses
  System.Math,
  dpcc.Text.Lines,
  dpcc.Core.Style.Palette,
  dpcc.Core.Style.Look,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Lsp.Session,
  dpcc.IDE.Foundation.EditorStyle,
  dpcc.IDE.Foundation.EditorRefresh;

{ TDpccIdeFormatMarks.TEvents }

function TDpccIdeFormatMarks.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TDpccIdeFormatMarks.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TDpccIdeFormatMarks }

constructor TDpccIdeFormatMarks.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FByLine := TDictionary<Integer, TArray<TDpccFormatMark>>.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TDpccIdeFormatMarks.Destroy;
var
  mServices: INTACodeEditorServices;
  mPainted: Boolean;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  mPainted := FByLine.Count > 0;
  FByLine.Clear;
  FLines := nil;
  FreeAndNil(FByLine);
  if mPainted then
  begin
    Invalidate;
  end;
  inherited;
end;

class procedure TDpccIdeFormatMarks.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TDpccIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

procedure TDpccIdeFormatMarks.Show(const AFileName, AText: string; const ATabStops: TDpccTabStops;
  const AMarks: TArray<TDpccFormatMark>);
var
  mMark: TDpccFormatMark;
  mMarks: TArray<TDpccFormatMark>;
  mPainted: Boolean;
begin
  mPainted := FByLine.Count > 0;
  FByLine.Clear;
  FFileName := AFileName;
  FTabStops := ATabStops;
  FLines := nil;
  if Length(AMarks) > 0 then
  begin
    FLines := TTextLines.SplitLines(AText);
  end;
  for mMark in AMarks do
  begin
    if not FByLine.TryGetValue(mMark.Line, mMarks) then
    begin
      mMarks := nil;
    end;
    FByLine.AddOrSetValue(mMark.Line, mMarks + [mMark]);
  end;
  if mPainted or (FByLine.Count > 0) then
  begin
    Invalidate;
  end;
end;

procedure TDpccIdeFormatMarks.Clear;
begin
  FFileName := '';
  FLines := nil;
  if FByLine.Count = 0 then
  begin
    Exit;
  end;
  FByLine.Clear;
  Invalidate;
end;

procedure TDpccIdeFormatMarks.PaintMarks(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const AText: string; const AMarks: TArray<TDpccFormatMark>; ABack: TDpccColor);
var
  mMark: TDpccFormatMark;
  mColors: TDpccColors;
  mFirst, mLast, mCode: TRect;
  mDC: HDC;
  mSaved: Integer;
  mAlpha: Byte;
begin
  mColors := TDpccColors.ForBackground(ABack);
  // Einmal je Zeile: Look liest die Einstellung PopupLook.
  mAlpha := TDpccIdeStyle.Look.MarkAlpha;
  mDC := AContext.Canvas.Handle;
  mCode := AContext.LineState.CodeRect;
  mSaved := SaveDC(mDC);
  try
    if mCode.Right > mCode.Left then
    begin
      IntersectClipRect(mDC, mCode.Left, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    for mMark in AMarks do
    begin
      mFirst := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, mMark.Start, FTabStops),
        AContext.EditorLineNum);
      mLast := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, mMark.Stop, FTabStops),
        AContext.EditorLineNum);
      TDpccIdeStyle.Blend(mDC, TRect.Create(mFirst.Left, ARect.Top, Max(mLast.Left, mFirst.Left + 1), ARect.Bottom),
        COLORREF(ColorToRGB(TColor(mColors.Placeholders[mMark.Slot]))), mAlpha);
    end;
  finally
    RestoreDC(mDC, mSaved);
  end;
end;

procedure TDpccIdeFormatMarks.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLineState: INTACodeEditorLineState;
  mMarks: TArray<TDpccFormatMark>;
  mLine: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or (FByLine.Count = 0) or
    TDpccGuard.Disabled(TDpccFeature.Signature) then
  begin
    Exit;
  end;
  try
    if not SameText(Context.FileName, FFileName) then
    begin
      Exit;
    end;
    mLine := Context.LogicalLineNum - 1;
    if (mLine < 0) or (mLine >= Length(FLines)) or not FByLine.TryGetValue(mLine, mMarks) then
    begin
      Exit;
    end;
    mLineState := Context.LineState;
    // Nur, wenn die Zeile im Editor dem angefragten Stand entspricht.
    if (mLineState = nil) or (TrimRight(mLineState.Text) <> TrimRight(FLines[mLine])) then
    begin
      Exit;
    end;
    PaintMarks(Rect, Context, FLines[mLine], mMarks, TDpccIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2,
      Rect.Top + 1));
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Signature, E);
  end;
end;

end.
