unit dpcc.IDE.Completion.Preview;

// Vorschau des gewählten Eintrags im Editor (#434): Der noch fehlende Teil
// steht kursiv und gedämpft hinter dem Cursor. Nur gezeichnet über die
// Zeichenereignisse der Code-Editor-API (ToolsAPI.Editor, PaintLine nach dem
// Zeichnen der Zeile); Datei und Undo-Liste bleiben unberührt. Beim Wechsel
// des Texts wird nur die betroffene Zeile neu gezeichnet. Seit Rückbau R6 ohne
// Anmeldung bei TDpccIdeElements (Ausblenden am Element entfällt).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor;

type
  TDpccEditorPreview = class
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
    /// <summary>1-basiert wie in der IDE.</summary>
    FLine: Integer;
    FColumn: Integer;
    FText: string;
    FFollowCursor: Boolean;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    /// <summary>Gehört die Vorschau in die Zeile, die AContext zeichnet?</summary>
    function ShowsIn(const AContext: INTACodeEditorPaintContext): Boolean;
    procedure InvalidateLine(ALine: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>AText hinter der Editorspalte AColumn (1-basiert) in Zeile ALine von AFileName zeigen.</summary>
    procedure Show(const AFileName: string; ALine, AColumn: Integer; const AText: string);
    procedure Clear;
    /// <summary>Nur zeichnen, solange der Cursor der Ansicht in der Zeile steht.</summary>
    property FollowCursor: Boolean read FFollowCursor write FFollowCursor;
  end;

implementation

uses
  dpcc.Core.Diagnostics.Guard,
  Winapi.Windows,
  dpcc.IDE.Foundation.EditorStyle,
  dpcc.IDE.Foundation.EditorRefresh;

{ TDpccEditorPreview.TEvents }

function TDpccEditorPreview.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TDpccEditorPreview.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TDpccEditorPreview }

constructor TDpccEditorPreview.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TDpccEditorPreview.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  Clear;
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

procedure TDpccEditorPreview.InvalidateLine(ALine: Integer);
var
  mServices: INTACodeEditorServices;
begin
  if (ALine > 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TDpccIdeEditorRefresh.InvalidateTopLine(mServices, ALine);
  end;
end;

procedure TDpccEditorPreview.Show(const AFileName: string; ALine, AColumn: Integer; const AText: string);
begin
  if (AText = FText) and (ALine = FLine) and (AColumn = FColumn) and SameText(AFileName, FFileName) then
  begin
    Exit;
  end;
  if FLine <> ALine then
  begin
    InvalidateLine(FLine);
  end;
  FFileName := AFileName;
  FLine := ALine;
  FColumn := AColumn;
  FText := AText;
  InvalidateLine(FLine);
end;

procedure TDpccEditorPreview.Clear;
begin
  if FText = '' then
  begin
    Exit;
  end;
  FText := '';
  InvalidateLine(FLine);
  FLine := 0;
end;

function TDpccEditorPreview.ShowsIn(const AContext: INTACodeEditorPaintContext): Boolean;
begin
  Result := (FText <> '') and (AContext <> nil) and (AContext.LogicalLineNum = FLine) and
    SameText(AContext.FileName, FFileName);
  // Nur in der Cursorzeile (FollowCursor): Der Cursor der Ansicht muss in der Zeile stehen.
  if Result and FFollowCursor then
  begin
    Result := (AContext.EditView <> nil) and (AContext.EditView.CursorPos.Line = FLine);
  end;
end;

procedure TDpccEditorPreview.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mCell: TRect;
  mCanvas: TCanvas;
  mItalic: TFont;
  mDC: HDC;
  mSaved, mTop: Integer;
begin
  try
    if BeforeEvent or (Stage <> plsEndPaint) or not ShowsIn(Context) then
    begin
      Exit;
    end;
    mCell := Context.EditorState.GetCharacterPosPx(FColumn, Context.EditorLineNum);
    mCanvas := Context.Canvas;
    mTop := Rect.Top + (Rect.Height - mCanvas.TextHeight('Wg')) div 2;
    // Eigene kursive Schrift und gesicherter DC-Zustand: Schrift, Textfarbe und
    // Hintergrundmodus der IDE bleiben unverändert (sonst färbt die Vorschaufarbe
    // später gezeichnete Läufe ein).
    mItalic := TFont.Create;
    try
      mItalic.Assign(mCanvas.Font);
      mItalic.Style := [fsItalic];
      mDC := mCanvas.Handle;
      mSaved := SaveDC(mDC);
      try
        SelectObject(mDC, mItalic.Handle);
        SetBkMode(mDC, TRANSPARENT);
        // Gedämpft in den Farben des Editors (ListColors, S8), wie der Nebentext von Liste und Hover.
        SetTextColor(mDC, ColorToRGB(TColor(TDpccIdeStyle.ListColors.Muted)));
        Winapi.Windows.TextOut(mDC, mCell.Left, mTop, PChar(FText), Length(FText));
      finally
        RestoreDC(mDC, mSaved);
      end;
    finally
      mItalic.Free;
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
    begin
      FText := '';
      TDpccGuard.Report(TDpccFeature.Completion, E);
    end;
  end;
end;

end.
