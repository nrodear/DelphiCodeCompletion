unit dpcc.IDE.Completion.Placeholders;

// Platzhalter-Modus im Editor nach dem Einsetzen eines Eintrags mit Platzhaltern (#51).
// Die IDE kennt keine LSP-Snippets (insertTextFormat 2); dpcc führt die Platzhalter selbst
// (Modell: dpcc.Core.Completion.Placeholders).
//   - Der aktuelle Platzhalter ist markiert, Tippen ersetzt die Vorgabe.
//   - Tab springt weiter, Umschalt+Tab zurück, nach dem letzten an die
//     Endposition ($0). Enter beendet und springt an die Endposition, Esc
//     beendet an Ort und Stelle. Die Tasten kommen über den gemeinsamen Hook
//     (Priorität nach Vervollständigung und Parameter-Hint), nur solange der
//     Modus läuft.
//   - Verknüpfte Platzhalter: Nach jeder Änderung im aktuellen Platzhalter
//     gleicht dpcc die übrigen mit derselben Nummer an (gleich danach per
//     ForceQueue, nicht in der Benachrichtigung).
//   - Zeichnen (eckige 1-px-Rahmen in Farben des Editors, TDpccIdeStyle.ListColors, S8):
//     aktueller Platzhalter durchgezogen umrahmt in Look.PlaceholderFrame der Stufe (LOOK1: Intensiv Akzent,
//     Dezent Textfarbe, Unscheinbar gedämpft; TDpccIdeStyle.Look), verknüpfte gestrichelt,
//     die übrigen gepunktet (beide gedämpft); hinter der Zeile gedämpft die Fußzeile
//     „Platzhalter 1 / 3 · Tab weiter · Esc fertig“.
//   - Eine Änderung außerhalb, ein Wechsel der Ansicht oder Esc beendet den Modus.
//   - Ein Undo-Schritt: Endet der Modus regulär (Esc, Enter, Tab nach dem
//     letzten Platzhalter), nimmt dpcc das Einsetzen, alle Eingaben und
//     Angleichungen über IOTAEditBuffer.Undo bis zum Stand vor dem Einsetzen
//     zurück und schreibt das Ergebnis mit einem einzigen Schreiber neu. Ein
//     Strg+Z danach stellt den Stand vor der Vorlage wieder her. Wird der Stand
//     vor dem Einsetzen nicht erreicht (z. B. weil die IDE Schritte
//     zusammengefasst hat), stellt Redo alles wieder her und es bleibt bei
//     mehreren Schritten. Endet der Modus durch eine Änderung außerhalb, bleibt
//     die Undo-Liste unberührt.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  ToolsAPI,
  ToolsAPI.Editor,
  dpcc.Core.Completion.Placeholders,
  dpcc.IDE.Foundation.KeyHook;

type
  TDpccEditorPlaceholders = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;

    TKeys = class(TDpccKeyClient)
    private
      FOwner: TDpccEditorPlaceholders;
    protected
      function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
      procedure HandleKey(AKey: Word; AShift: TShiftState); override;
    public
      constructor Create(AOwner: TDpccEditorPlaceholders);
    end;
  private
    FSession: TDpccPlaceholderSession;
    FView: IOTAEditView;
    FFileName: string;
    FKeys: TKeys;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FEventsIndex: Integer;
    // dpcc schreibt gerade selbst (verknüpfte Platzhalter): Benachrichtigungen übergehen.
    FApplying: Boolean;
    FMirrorQueued: Boolean;
    // Puffertext vor dem Einsetzen, für den gemeinsamen Undo-Schritt.
    FBefore: string;
    procedure CollapseUndo;
    procedure SelectCurrent;
    /// <summary>Rahmen und Fußzeile neu zeichnen lassen.</summary>
    procedure Invalidate;
    procedure MoveTo(AOffset: Integer);
    procedure Finish(AToEnd: Boolean);
    procedure ApplyMirrors;
    function CursorOffset(const AText: string): Integer;
    function EditPos(const AText: string; AOffset: Integer): TOTAEditPos;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleKey(AKey: Word; AShift: TShiftState);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>ABefore: Puffertext vor dem Einsetzen, ADocument: Text danach, AOffset: Anfang der Vorlage
    /// darin. Ohne Platzhalter steht nur der Cursor an der Endposition.</summary>
    procedure Start(const AView: IOTAEditView; const ABefore, ADocument: string; AOffset: Integer;
      const AExpansion: TDpccPlaceholderExpansion); overload;
    /// <summary>Wie oben, mit verknüpften Platzhaltern außerhalb der Vorlage (Offsets in ADocument, #473).</summary>
    procedure Start(const AView: IOTAEditView; const ABefore, ADocument: string; AOffset: Integer;
      const AExpansion: TDpccPlaceholderExpansion; const ALinked: TArray<TDpccPlaceholderField>); overload;
    procedure Stop;
    function Active: Boolean;
    /// <summary>Aus EditorViewModified.</summary>
    procedure EditorModified(const AView: IOTAEditView);
  end;

implementation

uses
  dpcc.Core.Diagnostics.MainThread,
  System.Math,
  Vcl.Graphics,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette,
  dpcc.Core.Style.Look,
  dpcc.IDE.Foundation.EditorBuffer,
  dpcc.IDE.Foundation.EditorStyle,
  dpcc.UI.Completion.Strings,
  dpcc.IDE.Foundation.EditorRefresh;

/// <summary>Zeile ALine (0-basiert) aus AText ohne Zeilenende.</summary>
function LineOf(const AText: string; ALine: Integer): string;
var
  mLines: TArray<string>;
begin
  mLines := AText.Replace(#13, '').Split([#10]);
  if (ALine >= 0) and (ALine <= High(mLines)) then
  begin
    Result := mLines[ALine];
  end
  else
  begin
    Result := '';
  end;
end;

function ByteOffset(const AText: string; AOffset: Integer): Integer;
begin
  Result := TEncoding.UTF8.GetByteCount(Copy(AText, 1, AOffset));
end;

{ TDpccEditorPlaceholders.TEvents }

function TDpccEditorPlaceholders.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TDpccEditorPlaceholders.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TDpccEditorPlaceholders.TKeys }

constructor TDpccEditorPlaceholders.TKeys.Create(AOwner: TDpccEditorPlaceholders);
begin
  // Nach Vervollständigung (0) und Parameter-Hint (10): Tab und Esc gehören zuerst deren Fenstern.
  inherited Create(20);
  FOwner := AOwner;
end;

function TDpccEditorPlaceholders.TKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := FOwner.WantsKey(AKey, AShift);
end;

procedure TDpccEditorPlaceholders.TKeys.HandleKey(AKey: Word; AShift: TShiftState);
begin
  try
    FOwner.HandleKey(AKey, AShift);
  except
    on E: Exception do
    begin
      FOwner.Stop;
      TDpccGuard.Report(TDpccFeature.Completion, E);
    end;
  end;
end;

{ TDpccEditorPlaceholders }

constructor TDpccEditorPlaceholders.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FKeys := TKeys.Create(Self);
  FEventsIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FEventsIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TDpccEditorPlaceholders.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  Stop;
  if (FEventsIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FEventsIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
  end;
  FEventsRef := nil;
  FKeys.Free;
  inherited Destroy;
end;

function TDpccEditorPlaceholders.Active: Boolean;
begin
  Result := FSession <> nil;
end;

procedure TDpccEditorPlaceholders.Start(const AView: IOTAEditView; const ABefore, ADocument: string;
  AOffset: Integer; const AExpansion: TDpccPlaceholderExpansion);
begin
  Start(AView, ABefore, ADocument, AOffset, AExpansion, nil);
end;

procedure TDpccEditorPlaceholders.Start(const AView: IOTAEditView; const ABefore, ADocument: string;
  AOffset: Integer; const AExpansion: TDpccPlaceholderExpansion; const ALinked: TArray<TDpccPlaceholderField>);
var
  mField: TDpccPlaceholderField;
begin
  Stop;
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  FView := AView;
  FFileName := AView.Buffer.FileName;
  FBefore := ABefore;
  FSession := TDpccPlaceholderSession.Create(ADocument, AOffset, AExpansion);
  for mField in ALinked do
  begin
    FSession.Link(mField);
  end;
  if not AExpansion.HasPlaceholders then
  begin
    Finish(True);
    Exit;
  end;
  TDpccKeyHook.Add(FKeys);
  SelectCurrent;
end;

procedure TDpccEditorPlaceholders.Stop;
var
  mWasActive: Boolean;
begin
  mWasActive := Active;
  TDpccKeyHook.Remove(FKeys);
  FreeAndNil(FSession);
  FView := nil;
  FBefore := '';
  FMirrorQueued := False;
  // Rahmen und Fußzeile verschwinden.
  if mWasActive then
  begin
    Invalidate;
  end;
end;

procedure TDpccEditorPlaceholders.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TDpccIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

function TDpccEditorPlaceholders.EditPos(const AText: string; AOffset: Integer): TOTAEditPos;
var
  mLine, mCharacter: Integer;
begin
  TDpccPlaceholderSession.Locate(AText, AOffset, mLine, mCharacter);
  Result.Line := mLine + 1;
  Result.Col := TLspSession.IndexToColumn(LineOf(AText, mLine), mCharacter, TDpccEditorBuffer.TabWidth(FView.Buffer));
end;

function TDpccEditorPlaceholders.CursorOffset(const AText: string): Integer;
var
  mCursor: TOTAEditPos;
  mLineText: string;
begin
  mCursor := FView.CursorPos;
  mLineText := TDpccEditorBuffer.LineText(FView, mCursor.Line);
  Result := TDpccEditorBuffer.CharOffset(AText, mCursor.Line - 1,
    TLspSession.ColumnToIndex(mLineText, mCursor.Col, TDpccEditorBuffer.TabWidth(FView.Buffer)));
end;

procedure TDpccEditorPlaceholders.MoveTo(AOffset: Integer);
begin
  FView.Block.Reset;
  FView.CursorPos := EditPos(FSession.Text, AOffset);
  FView.MoveViewToCursor;
  FView.Paint;
end;

procedure TDpccEditorPlaceholders.SelectCurrent;
var
  mField: TDpccPlaceholderField;
begin
  mField := FSession.Current;
  if mField.Length = 0 then
  begin
    MoveTo(mField.Start);
  end
  else
  begin
    // Wie Auswahl erweitern (#399): Anfang markieren, Cursor ans Ende, Ende markieren. Tippen ersetzt die Vorgabe.
    FView.Block.Style := btNonInclusive;
    FView.CursorPos := EditPos(FSession.Text, mField.Start);
    FView.Block.BeginBlock;
    FView.CursorPos := EditPos(FSession.Text, mField.Stop);
    FView.Block.EndBlock;
    FView.MoveViewToCursor;
    FView.Paint;
  end;
end;

procedure TDpccEditorPlaceholders.Finish(AToEnd: Boolean);
var
  mCursor: Integer;
begin
  if (FSession <> nil) and (FView <> nil) then
  begin
    mCursor := CursorOffset(FSession.Text);
    CollapseUndo;
    if AToEnd then
    begin
      MoveTo(FSession.FinalOffset);
    end
    else
    begin
      FView.CursorPos := EditPos(FSession.Text, mCursor);
      FView.Paint;
    end;
  end;
  Stop;
end;

/// <summary>Macht in ABuffer Schritte rückgängig, bis sein Text ATarget ist; AText ist der Text davor. Wird ATarget
/// nicht erreicht, stellt es alle Schritte wieder her und liefert False.</summary>
function UndoTo(const ABuffer: IOTAEditBuffer; const AText, ATarget: string): Boolean;
const
  // Obergrenze der Undo-Schritte; eine Vorlage braucht selten mehr als ein paar Dutzend.
  cMaxSteps = 1000;
var
  mText: string;
  mSteps, mIndex: Integer;
begin
  mSteps := 0;
  mText := AText;
  while (mText <> ATarget) and (mSteps < cMaxSteps) and ABuffer.Undo do
  begin
    Inc(mSteps);
    mText := TDpccEditorBuffer.Text(ABuffer);
  end;
  Result := mText = ATarget;
  if not Result then
  begin
    // Stand vor dem Einsetzen nicht erreicht: alles wiederherstellen.
    for mIndex := 1 to mSteps do
    begin
      if not ABuffer.Redo then
      begin
        Break;
      end;
    end;
  end;
end;

procedure TDpccEditorPlaceholders.CollapseUndo;
var
  mFinal: string;
  mPrefix, mSuffix: Integer;
  mWriter: IOTAEditWriter;
begin
  if (FSession = nil) or (FView = nil) or (FView.Buffer = nil) or (FBefore = '') then
  begin
    Exit;
  end;
  mFinal := TDpccEditorBuffer.Text(FView.Buffer);
  if mFinal <> FSession.Text then
  begin
    Exit;
  end;
  FApplying := True;
  try
    if not UndoTo(FView.Buffer, mFinal, FBefore) then
    begin
      Exit;
    end;
    // Gemeinsamer Anfang und gemeinsames Ende; dazwischen ersetzt ein Schreiber.
    mPrefix := 0;
    while (mPrefix < Length(FBefore)) and (mPrefix < Length(mFinal)) and (FBefore[mPrefix + 1] = mFinal[mPrefix + 1]) do
    begin
      Inc(mPrefix);
    end;
    mSuffix := 0;
    while (mSuffix < Length(FBefore) - mPrefix) and (mSuffix < Length(mFinal) - mPrefix) and
      (FBefore[Length(FBefore) - mSuffix] = mFinal[Length(mFinal) - mSuffix]) do
    begin
      Inc(mSuffix);
    end;
    mWriter := FView.Buffer.CreateUndoableWriter;
    mWriter.CopyTo(ByteOffset(FBefore, mPrefix));
    mWriter.DeleteTo(ByteOffset(FBefore, Length(FBefore) - mSuffix));
    mWriter.Insert(PAnsiChar(UTF8Encode(Copy(mFinal, mPrefix + 1, Length(mFinal) - mPrefix - mSuffix))));
    mWriter := nil;
  finally
    FApplying := False;
  end;
end;

function TDpccEditorPlaceholders.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := Active and ((AKey = VK_TAB) and ((AShift = []) or (AShift = [ssShift])) or
    ((AKey = VK_ESCAPE) or (AKey = VK_RETURN)) and (AShift = []));
end;

procedure TDpccEditorPlaceholders.HandleKey(AKey: Word; AShift: TShiftState);
begin
  if not Active then
  begin
    Exit;
  end;
  // Vor dem Springen noch ausstehende Angleichungen schreiben.
  ApplyMirrors;
  if not Active then
  begin
    Exit;
  end;
  case AKey of
    VK_TAB:
      if AShift = [ssShift] then
      begin
        FSession.Previous;
        SelectCurrent;
      end
      else if FSession.Next then
      begin
        SelectCurrent;
      end
      else
      begin
        Finish(True);
      end;
    VK_RETURN:
      Finish(True);
    VK_ESCAPE:
      Finish(False);
  end;
  if Active then
  begin
    Invalidate;
  end;
end;

procedure TDpccEditorPlaceholders.EditorModified(const AView: IOTAEditView);
begin
  if FApplying or not Active or (AView = nil) or (AView.Buffer = nil) or
    not SameText(AView.Buffer.FileName, FFileName) then
  begin
    Exit;
  end;
  if not FSession.Update(TDpccEditorBuffer.Text(AView.Buffer)) then
  begin
    Stop;
    Exit;
  end;
  if (Length(FSession.MirrorEdits) > 0) and not FMirrorQueued then
  begin
    FMirrorQueued := True;
    // Nicht im Benachrichtigungsaufruf selbst schreiben, sondern gleich danach.
    TDpccMainThread.ForceQueue(TDpccFeature.Completion,
      procedure
      begin
        try
          ApplyMirrors;
        except
          on E: Exception do
          begin
            Stop;
            TDpccGuard.Report(TDpccFeature.Completion, E);
          end;
        end;
      end);
  end;
end;

procedure TDpccEditorPlaceholders.ApplyMirrors;
var
  mEdits: TDpccPlaceholderEdits;
  mEdit: TDpccPlaceholderEdit;
  mText: string;
  mWriter: IOTAEditWriter;
  mCursor, mShift: Integer;
begin
  FMirrorQueued := False;
  if not Active or (FView = nil) or (FView.Buffer = nil) then
  begin
    Exit;
  end;
  mText := TDpccEditorBuffer.Text(FView.Buffer);
  if not FSession.Update(mText) then
  begin
    Stop;
    Exit;
  end;
  mEdits := FSession.MirrorEdits;
  if Length(mEdits) = 0 then
  begin
    Exit;
  end;
  mCursor := CursorOffset(mText);
  mShift := 0;
  FApplying := True;
  try
    // Ein Schreiber schreibt nur vorwärts; die Änderungen sind aufsteigend.
    mWriter := FView.Buffer.CreateUndoableWriter;
    for mEdit in mEdits do
    begin
      mWriter.CopyTo(ByteOffset(mText, mEdit.Start));
      mWriter.DeleteTo(ByteOffset(mText, mEdit.Stop));
      mWriter.Insert(PAnsiChar(UTF8Encode(mEdit.Text)));
      if mEdit.Stop <= mCursor then
      begin
        Inc(mShift, Length(mEdit.Text) - (mEdit.Stop - mEdit.Start));
      end;
    end;
    mWriter := nil;
  finally
    FApplying := False;
  end;
  FSession.Applied(mEdits);
  // Der Cursor bleibt an seiner Stelle im Text, auch wenn davor ein verknüpfter Platzhalter wuchs.
  FView.CursorPos := EditPos(FSession.Text, mCursor + mShift);
  FView.Paint;
end;

/// <summary>ALine, wie der Editor sie zeigt: Tabs bis zur nächsten Tabstelle als Leerzeichen, ohne #13 (wie
/// TDpccPairs.DisplayLine; seit Rückbau R6 hier, ohne die Klammerpaare).</summary>
function DisplayLine(const ALine: string; ATabWidth: Integer): string;
var
  mBuilder: TStringBuilder;
  mCh: Char;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mCh in ALine do
    begin
      if (mCh = #9) and (ATabWidth > 0) then
      begin
        mBuilder.Append(' ', ATabWidth - mBuilder.Length mod ATabWidth);
      end
      else if mCh <> #13 then
      begin
        mBuilder.Append(mCh);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Editorspalte (1-basiert) zum Zeichenindex (0-basiert) in ALine; Tabs aufgelöst.</summary>
function ColumnOf(const ALine: string; ACharacter, ATabWidth: Integer): Integer;
begin
  Result := Length(DisplayLine(Copy(ALine, 1, Max(0, ACharacter)), ATabWidth)) + 1;
end;

/// <summary>Zeichnet PaintLine für AContext: Modus läuft, Ansicht mit Puffer, Datei des Modus.</summary>
function PaintsLine(ASession: TDpccPlaceholderSession; const AFileName: string;
  const AContext: INTACodeEditorPaintContext): Boolean;
begin
  Result := (ASession <> nil) and (AContext <> nil) and (AContext.LineState <> nil) and (AContext.EditView <> nil);
  Result := Result and (AContext.EditView.Buffer <> nil) and SameText(AContext.FileName, AFileName);
end;

type
  /// <summary>Rahmen und Fußzeile der Platzhalter in einer Editorzeile (PaintLine).</summary>
  TPlaceholderPaint = record
    Session: TDpccPlaceholderSession;
    Context: INTACodeEditorPaintContext;
    Area: TRect;
    Colors: TDpccColors;
    /// <summary>Rahmen des aktuellen Platzhalters nach der Stufe der Darstellung (Look.PlaceholderFrame, LOOK1).
    /// </summary>
    CurrentFrame: TDpccColor;
    DC: HDC;
    /// <summary>Zeile (0-basiert) und ihr Text im Modell.</summary>
    Line: Integer;
    Text: string;
    TabWidth: Integer;
    /// <summary>Entspricht die Zeile im Editor dem Stand des Modells?</summary>
    function Matches: Boolean;
    /// <summary>Linker Rand des Zeichens ACharacter (0-basiert) der Zeile in Pixeln.</summary>
    function Pixel(ACharacter: Integer): Integer;
    /// <summary>Aktueller Platzhalter durchgezogen, verknüpfte gestrichelt, die übrigen gepunktet.</summary>
    procedure Frame(const AField, ACurrent: TDpccPlaceholderField);
    procedure Frames;
    /// <summary>Fußzeile hinter der Zeile des aktuellen Platzhalters.</summary>
    procedure Footer;
  end;

{ TPlaceholderPaint }

function TPlaceholderPaint.Matches: Boolean;
begin
  Result := TrimRight(DisplayLine(Context.LineState.Text, TabWidth)) =
    TrimRight(DisplayLine(Text, TabWidth));
end;

function TPlaceholderPaint.Pixel(ACharacter: Integer): Integer;
begin
  Result := Context.EditorState.GetCharacterPosPx(ColumnOf(Text, ACharacter, TabWidth), Context.EditorLineNum).Left;
end;

procedure TPlaceholderPaint.Frame(const AField, ACurrent: TDpccPlaceholderField);
var
  mStartLine, mStartChar, mEndLine, mEndChar, mLeft, mRight, mPenStyle: Integer;
  mColor: TColor;
  mPen, mOldPen: HGDIOBJ;
begin
  TDpccPlaceholderSession.Locate(Session.Text, AField.Start, mStartLine, mStartChar);
  TDpccPlaceholderSession.Locate(Session.Text, AField.Stop, mEndLine, mEndChar);
  if mStartLine <> Line then
  begin
    Exit;
  end;
  if mEndLine <> Line then
  begin
    mEndChar := Length(Text);
  end;
  mLeft := Pixel(mStartChar) - 1;
  mRight := Max(Pixel(mEndChar) + 1, mLeft + 2);
  if (AField.Start = ACurrent.Start) and (AField.Number = ACurrent.Number) then
  begin
    mPenStyle := PS_SOLID;
    mColor := TColor(CurrentFrame);
  end
  else if AField.Number = ACurrent.Number then
  begin
    mPenStyle := PS_DASH;
    mColor := TColor(Colors.Muted);
  end
  else
  begin
    mPenStyle := PS_DOT;
    mColor := TColor(Colors.Muted);
  end;
  mPen := CreatePen(mPenStyle, 1, ColorToRGB(mColor));
  mOldPen := SelectObject(DC, mPen);
  try
    Winapi.Windows.Rectangle(DC, mLeft, Area.Top, mRight, Area.Bottom);
  finally
    SelectObject(DC, mOldPen);
    DeleteObject(mPen);
  end;
end;

procedure TPlaceholderPaint.Frames;
var
  mField, mCurrent: TDpccPlaceholderField;
  mOldBrush: HGDIOBJ;
begin
  mCurrent := Session.Current;
  mOldBrush := SelectObject(DC, GetStockObject(NULL_BRUSH));
  for mField in Session.Fields do
  begin
    Frame(mField, mCurrent);
  end;
  SelectObject(DC, mOldBrush);
end;

procedure TPlaceholderPaint.Footer;
var
  mStartLine, mStartChar, mLeft: Integer;
  mHint: string;
  mOldFont: TColor;
  mOldBrushStyle: TBrushStyle;
begin
  TDpccPlaceholderSession.Locate(Session.Text, Session.Current.Start, mStartLine, mStartChar);
  if mStartLine <> Line then
  begin
    Exit;
  end;
  mHint := Format(TDpccCompletionStrings.Text(TDpccCompletionTextId.PlaceholderFooter), [Session.Position,
    Session.Count]);
  mLeft := Context.EditorState.GetCharacterPosPx(Length(DisplayLine(Text, TabWidth)) + 4,
    Context.EditorLineNum).Left;
  mOldFont := Context.Canvas.Font.Color;
  mOldBrushStyle := Context.Canvas.Brush.Style;
  try
    Context.Canvas.Font.Color := TColor(Colors.Muted);
    Context.Canvas.Brush.Style := bsClear;
    Context.Canvas.TextOut(mLeft, Area.Top, mHint);
  finally
    Context.Canvas.Font.Color := mOldFont;
    Context.Canvas.Brush.Style := mOldBrushStyle;
  end;
end;

procedure TDpccEditorPlaceholders.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mPaint: TPlaceholderPaint;
  mLook: TDpccLook;
  mSaved: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or not PaintsLine(FSession, FFileName, Context) then
  begin
    Exit;
  end;
  try
    mPaint.Session := FSession;
    mPaint.Context := Context;
    mPaint.Area := Rect;
    mPaint.Line := Context.LogicalLineNum - 1;
    mPaint.Text := LineOf(FSession.Text, mPaint.Line);
    mPaint.TabWidth := TDpccEditorBuffer.TabWidth(Context.EditView.Buffer);
    if not mPaint.Matches then
    begin
      Exit;
    end;
    // Farben des Editors (ListColors) in der eingestellten Stufe; Look.Colors sind die ListColors.
    mLook := TDpccIdeStyle.Look;
    mPaint.Colors := mLook.Colors;
    mPaint.CurrentFrame := mLook.PlaceholderFrame;
    mPaint.DC := Context.Canvas.Handle;
    mSaved := SaveDC(mPaint.DC);
    try
      mPaint.Frames;
      mPaint.Footer;
    finally
      RestoreDC(mPaint.DC, mSaved);
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Completion, E);
  end;
end;

end.
