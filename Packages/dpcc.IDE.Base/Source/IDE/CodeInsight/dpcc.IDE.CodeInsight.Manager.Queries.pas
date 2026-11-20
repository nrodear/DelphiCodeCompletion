unit dpcc.IDE.CodeInsight.Manager.Queries;

// Fragen des Code Insight-Managers an den Editor: Welche Code Insight löst eine Taste aus (Vervollständigung nach
// ".", Parameterhilfe nach "(", XMLDoc-Tags nach "<" in ///-Zeilen #435, Mengen nach "[" #448, try…finally nach ";"
// #489, Mitglieder nach "{" in Wertdarstellungen #854, Feldnamen nach ' in FieldByName #461)? Dazu die Stelle eines
// Symbolhinweises (GetHintText, mit Wert im angehaltenen Debugger #891) und eines Sprungwunschs für Strg+Klick und
// „Deklaration suchen“ (Auftrag NAV) an der Klickstelle bzw. am Cursor. Gefragt wird der Server im Hintergrund
// (dpcc.IDE.CodeInsight.Manager, dpcc.Core.Lsp.LateAnswers); hier steht nur, was der Hauptthread dafür vom Editor
// liest. Zeilen kommen aus der Zeilentabelle (TLineTable), ohne den Text in Strings je Zeile zu zerlegen.
// Position beim Sprung (UNGEPRÜFT, nur aus der ToolsAPI gelesen): GotoDefinition bekommt von der IDE keine Stelle,
// nur Index. Angenommen wird: Bei Strg+Klick ist Strg beim Aufruf noch gedrückt und die Maus steht über dem Wort, bei
// „Deklaration suchen“ (Kontextmenü, Tastatur) gilt der Cursor. Ob die IDE den Cursor bei Strg+Klick vorher (oder
// erst danach) auf die Klickstelle setzt und ob ein Rechtsklick fürs Kontextmenü ihn versetzt, ist nicht geprüft.
// Mit Diagnose = 1 schreibt GotoPlace dazu Strg, Cursor, Mausstelle und die gewählte Stelle ins Protokoll; der
// nachgereichte Sprung den Cursor bei Ankunft. Ein Lauf klärt so die Annahmen.

interface

uses
  System.SysUtils,
  ToolsAPI,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.LateAnswers,
  dpcc.Core.Editor.Navigation;

type
  /// <summary>Stelle eines Symbolhinweises der IDE (GetHintText) samt Puffertext für den Abgleich.</summary>
  TDpccHintPlace = record
    FileName: string;
    /// <summary>Ganzer Puffertext (Sync im Hauptthread).</summary>
    Text: string;
    LineText: string;
    /// <summary>Zeile und Zeichen, 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    /// <summary>Zeile und Spalte der IDE, 1-basiert.</summary>
    HintLine: Integer;
    HintCol: Integer;
    /// <summary>Schlüssel für den Zwischenspeicher (Datei, Wort, Textstand).</summary>
    Key: TDpccHintKey;
  end;

  /// <summary>Stelle eines Sprungwunschs (Strg+Klick, „Deklaration suchen“) samt Puffertext für den Abgleich.
  /// </summary>
  TDpccGotoPlace = record
    /// <summary>Datei, Cursor und Stelle der Anfrage; Generation setzt der Manager.</summary>
    Origin: TDpccGotoOrigin;
    /// <summary>Ganzer Puffertext (Sync im Hauptthread).</summary>
    Text: string;
    /// <summary>Zeile der Anfrage (Origin.AtLine).</summary>
    LineText: string;
    /// <summary>Stelle unter der Maus (Strg+Klick) statt des Cursors.</summary>
    Mouse: Boolean;
  end;

  /// <summary>Editorposition, Auslöser und Antworten des Servers für die Einstiegspunkte der IDE.</summary>
  TDpccCodeInsightQueries = record
  public
    /// <summary>Editoransicht, in der Code Insight gerade läuft, sonst die oberste.</summary>
    class function CurrentEditView: IOTAEditView; static;
    /// <summary>Cursorzeile ist ein ///-Kommentar (XMLDoc, #435).</summary>
    class function InXmlDocLine: Boolean; static;
    /// <summary>Cursorzeile ist eine Wertdarstellung (// dpcc-debug:, [DpccDebugDisplay], #854).</summary>
    class function InDebugDisplayLine: Boolean; static;
    /// <summary>Cursor im Namen von FieldByName('…'), FindField('…') oder ParamByName('…') (#461).
    /// ATypedQuote: Das gerade getippte ' steht vielleicht noch nicht im Puffer.</summary>
    class function InDataNameString(ATypedQuote: Boolean): Boolean; static;
    /// <summary>Code Insight zu Taste AChar im Element AElement (atComment, atString …); AGuardPending fragt nach
    /// „Mit try…finally absichern“ (#489).</summary>
    class function InsightType(AChar: Char; AElement: Integer; const AGuardPending: TFunc<Boolean>;
      out AInvoke: TOTAInvokeType): TOTACodeInsightType; static;
    /// <summary>Stelle des Symbolhinweises an Zeile AHintLine, Spalte AHintCol (1-basiert) von AView; False
    /// außerhalb des Puffers.</summary>
    class function HintPlace(const AView: IOTAEditView; AHintLine, AHintCol: Integer;
      out APlace: TDpccHintPlace): Boolean; static;
    /// <summary>AHover mit dem Wert im angehaltenen Debugger davor (#891); nur sofort verfügbare Werte. Die Dauer
    /// der Auswertung steht als eigene Aktion im Einfrier-Wächter.</summary>
    class function HintWithDebugValue(const AHover: string; const APlace: TDpccHintPlace): string; static;
    /// <summary>Stelle des Sprungwunschs: an der Klickstelle (Strg gedrückt, Maus über einem Bezeichner im Editor
    /// von AView), sonst am Cursor. False (mit Zeile im Diagnoseprotokoll), wenn sie außerhalb des Puffers liegt.
    /// </summary>
    class function GotoPlace(const AView: IOTAEditView; const ADiagnose: TProc<string>;
      out APlace: TDpccGotoPlace): Boolean; static;
    /// <summary>Zustand für ein nachgereichtes Sprungziel: aktive Editoransicht (Datei, Cursor) mit AGeneration.
    /// </summary>
    class function GotoNow(AGeneration: Cardinal): TDpccGotoNow; static;
    /// <summary>Ist AAnswer ein Sprungziel? Nicht bei Fehler, ohne Datei und bei einer Ersatz-Unit des Servers
    /// (dpcc-ide:…), die es nicht als Datei gibt.</summary>
    class function TargetOf(const AAnswer: TDpccAnswer): Boolean; static;
    /// <summary>Grund ohne Sprungziel: der des Servers (AAnswer.NoTarget); zeigt die Antwort auf eine Ersatz-Unit
    /// (dpcc-ide:Unit.pas), NoSource mit dem Namen der Unit.</summary>
    class function NoTargetOf(const AAnswer: TDpccAnswer): TDpccNoTarget; static;
    /// <summary>Zeile fürs Diagnoseprotokoll zu einem Sprungwunsch mit Ergebnis AResult.</summary>
    class function GotoNote(AIndex: Integer; const APlace: TDpccGotoPlace; const AResult: string): string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Types,
  System.Classes,
  System.StrUtils,
  Vcl.Controls,
  ToolsAPI.Editor,
  dpcc.Text.Lines,
  dpcc.Text.DebugDisplay,
  dpcc.Core.Diagnostics.Hangs,
  dpcc.Core.Hover.DebugValue,
  dpcc.Core.Completion.Word,
  dpcc.Core.Lsp.IdeMembers,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Foundation.EditorBuffer,
  dpcc.IDE.Hover.DebugValue;

class function TDpccCodeInsightQueries.CurrentEditView: IOTAEditView;
var
  mServices: IOTACodeInsightServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTACodeInsightServices, mServices) then
  begin
    mServices.GetEditView(Result);
  end;
  if Result = nil then
  begin
    Result := (BorlandIDEServices as IOTAEditorServices).TopView;
  end;
end;

class function TDpccCodeInsightQueries.InXmlDocLine: Boolean;
var
  mView: IOTAEditView;
begin
  mView := CurrentEditView;
  Result := (mView <> nil) and (mView.Buffer <> nil) and
    TrimLeft(TDpccEditorBuffer.LineText(mView, mView.CursorPos.Line)).StartsWith('///');
end;

class function TDpccCodeInsightQueries.InDebugDisplayLine: Boolean;
var
  mView: IOTAEditView;
  mLine, mTemplate: string;
  mColumn: Integer;
  mNames: TArray<string>;
begin
  mView := CurrentEditView;
  Result := False;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mLine := TDpccEditorBuffer.LineText(mView, mView.CursorPos.Line);
  Result := TDebugDisplayText.CommentTemplate(mLine, mTemplate, mColumn) or
    TDebugDisplayText.AttributeTemplate(mLine, mTemplate, mColumn) or TDebugDisplayText.CommentChildren(mLine, mNames)
    or TDebugDisplayText.AttributeChildren(mLine, mNames);
end;

class function TDpccCodeInsightQueries.InDataNameString(ATypedQuote: Boolean): Boolean;
var
  mView: IOTAEditView;
  mLine: string;
  mCharacter: Integer;
begin
  Result := False;
  mView := CurrentEditView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mLine := TDpccEditorBuffer.LineText(mView, mView.CursorPos.Line);
  mCharacter := TLspSession.ColumnToIndex(mLine, mView.CursorPos.Col, TDpccEditorBuffer.TabWidth(mView.Buffer));
  Result := TDpccWord.InDataNameString(mLine, mCharacter);
  if not Result and ATypedQuote then
  begin
    Insert('''', mLine, mCharacter + 1);
    Result := TDpccWord.InDataNameString(mLine, mCharacter + 1);
  end;
end;

/// <summary>Auslöser, die nicht vom Text um den Cursor abhängen: #0 Vervollständigung (Strg+Leer), "." nach dem
/// Punkt, #1 Parameterhilfe (Strg+Umschalt+Leer), "(" und ",", "&lt;" und "[", #2 Browse (Strg+Klick), #3
/// Symbolhinweis. Mit Zeitgeber: nach der in den Editoroptionen eingestellten Verzögerung.</summary>
function FixedType(AChar: Char; out AInvoke: TOTAInvokeType): TOTACodeInsightType;
begin
  AInvoke := itManual;
  case AChar of
    #0, '.', '<', '[':
      Result := citCodeInsight;
    #1, '(', ',':
      Result := citParameterCodeInsight;
    #2:
      Result := citBrowseCodeInsight;
    #3:
      Result := citHintCodeInsight;
  else
    Result := citNone;
  end;
  if CharInSet(AChar, ['.', '<', '[', '(', ',']) then
  begin
    AInvoke := itTimer;
  end;
end;

/// <summary>Auslöser, die vom Text um den Cursor abhängen: ";" hinter einem übernommenen Konstruktor (#489), "{" in
/// einer Wertdarstellung (#854), ' in FieldByName( (#461). Immer mit Zeitgeber.</summary>
function ContextType(AChar: Char; const AGuardPending: TFunc<Boolean>): Boolean;
begin
  case AChar of
    ';':
      Result := AGuardPending();
    '{':
      Result := TDpccCodeInsightQueries.InDebugDisplayLine;
    '''':
      Result := TDpccCodeInsightQueries.InDataNameString(True);
  else
    Result := False;
  end;
end;

/// <summary>Vervollständigung in Kommentar oder String, die trotzdem gilt: XMLDoc-Tags in ///-Zeilen (#435), Feld-
/// und Parameternamen im String (#461), Platzhalter in Wertdarstellungen (#854); die Einträge kommen vom Server.
/// </summary>
function KeptInside(AChar: Char; AElement: Integer): Boolean;
begin
  if ((AChar = '<') or (AElement = atComment)) and TDpccCodeInsightQueries.InXmlDocLine then
  begin
    Exit(True);
  end;
  if (AElement = atString) and TDpccCodeInsightQueries.InDataNameString(AChar = '''') then
  begin
    Exit(True);
  end;
  Result := ((AElement = atComment) or (AElement = atString)) and TDpccCodeInsightQueries.InDebugDisplayLine;
end;

class function TDpccCodeInsightQueries.InsightType(AChar: Char; AElement: Integer;
  const AGuardPending: TFunc<Boolean>; out AInvoke: TOTAInvokeType): TOTACodeInsightType;
begin
  Result := FixedType(AChar, AInvoke);
  if CharInSet(AChar, [';', '{', '''']) and ContextType(AChar, AGuardPending) then
  begin
    Result := citCodeInsight;
    AInvoke := itTimer;
  end;
  // In Kommentaren und Strings keine Vervollständigung (#435), außer KeptInside; "<" außerhalb davon ist ein
  // Vergleich, keine Auslösung.
  if (Result = citCodeInsight) and KeptInside(AChar, AElement) then
  begin
    Exit;
  end;
  if (AChar = '<') or ((Result in [citCodeInsight, citParameterCodeInsight]) and
    ((AElement = atComment) or (AElement = atString))) then
  begin
    Result := citNone;
  end;
end;

/// <summary>Wert im angehaltenen Debugger (#891) vor dem Hover-Text; nur sofort verfügbare Werte, die IDE wartet
/// nicht.</summary>
function WithDebugValue(const AHover, ALine, AFileName: string; ACharacter, AHintLine: Integer): string;
var
  mDebugText: string;
  mActivity: IInterface;
begin
  Result := AHover;
  if not TDpccIdeSettings.Current.DebugHoverValues or not TDpccIdeDebugValues.Stopped then
  begin
    Exit;
  end;
  // Eigene Aktion: Wie lange die Auswertung im Debugger den Hauptthread hält, sieht der Einfrier-Wächter getrennt.
  mActivity := TDpccActivity.Scope('Symbolhinweis: Wert im Debugger');
  mDebugText := TDpccIdeDebugValues.EvaluateNow(TDpccDebugExpression.AtCharacter(ALine, ACharacter), AFileName,
    AHintLine).PlainText;
  mActivity := nil;
  if (mDebugText <> '') and (Result <> '') then
  begin
    Result := mDebugText + #13#10#13#10 + Result;
  end
  else if mDebugText <> '' then
  begin
    Result := mDebugText;
  end;
end;

/// <summary>Zeile ALine (0-basiert) von AText ohne Umbruch, über die Zeilentabelle ATable; '' außerhalb.</summary>
function LineOf(const AText: string; const ATable: TLineTable; ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine < ATable.LineCount) then
  begin
    Result := Copy(AText, ATable.LineStart(ALine) + 1, ATable.LineContentEnd(ALine) - ATable.LineStart(ALine));
  end;
end;

class function TDpccCodeInsightQueries.HintPlace(const AView: IOTAEditView; AHintLine, AHintCol: Integer;
  out APlace: TDpccHintPlace): Boolean;
var
  mTable: TLineTable;
begin
  APlace := Default(TDpccHintPlace);
  APlace.Text := TDpccEditorBuffer.Text(AView.Buffer);
  mTable := TLineTable.Build(APlace.Text);
  Result := (AHintLine >= 1) and (AHintLine <= mTable.LineCount);
  if not Result then
  begin
    Exit;
  end;
  APlace.FileName := AView.Buffer.FileName;
  APlace.HintLine := AHintLine;
  APlace.HintCol := AHintCol;
  APlace.Line := AHintLine - 1;
  APlace.LineText := LineOf(APlace.Text, mTable, APlace.Line);
  APlace.Character := TLspSession.ColumnToIndex(APlace.LineText, AHintCol, TDpccEditorBuffer.TabWidth(AView.Buffer));
  APlace.Key := TDpccHintKey.Make(APlace.FileName, APlace.LineText, APlace.Line, APlace.Character,
    TDpccHintKey.HashOf(APlace.Text));
end;

class function TDpccCodeInsightQueries.HintWithDebugValue(const AHover: string; const APlace: TDpccHintPlace): string;
begin
  Result := WithDebugValue(AHover, APlace.LineText, APlace.FileName, APlace.Character, APlace.HintLine);
end;

class function TDpccCodeInsightQueries.TargetOf(const AAnswer: TDpccAnswer): Boolean;
begin
  // Ersatz-Units des Servers (dpcc-ide:…) gibt es nicht als Datei: kein Sprungziel für Strg+Klick.
  Result := (AAnswer.Error = TDpccAnswerError.None) and AAnswer.Found and (AAnswer.FileName <> '') and
    not TDpccIdeMembers.IsIdePath(AAnswer.FileName);
end;

class function TDpccCodeInsightQueries.NoTargetOf(const AAnswer: TDpccAnswer): TDpccNoTarget;
begin
  Result := AAnswer.NoTarget;
  // Älterer Server: Ziel in einer Ersatz-Unit aus der RTTI der Packages (dpcc-ide:Vcl.Forms.pas), ohne Quelltext.
  if AAnswer.Found and TDpccIdeMembers.IsIdePath(AAnswer.FileName) then
  begin
    Result.Reason := TDpccNoTargetReason.NoSource;
    Result.Name := ChangeFileExt(Copy(AAnswer.FileName, Length(TDpccIdeMembers.cPathPrefix) + 1, MaxInt), '');
  end;
end;

/// <summary>Stelle unter der Maus im Editor von AView: Zeile (1-basiert) und Zeichen (0-basiert) über einem
/// Bezeichner; False außerhalb des Editors oder neben einem Bezeichner. Zeilen aus AText über ATable.</summary>
function MousePosition(const AView: IOTAEditView; const AText: string; const ATable: TLineTable; ATabWidth: Integer;
  out ALine, ACharacter: Integer): Boolean;
var
  mServices: INTACodeEditorServices;
  mEditor: TWinControl;
  mState: INTACodeEditorState;
  mPoint: TPoint;
  mColumn, mVisibleLine: Integer;
  mLineText: string;
begin
  Result := False;
  ALine := 0;
  ACharacter := 0;
  if not Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    Exit;
  end;
  mEditor := mServices.GetEditorForView(AView);
  if (mEditor = nil) or not mEditor.HandleAllocated then
  begin
    Exit;
  end;
  mPoint := mEditor.ScreenToClient(Mouse.CursorPos);
  if not PtInRect(mEditor.ClientRect, mPoint) then
  begin
    Exit;
  end;
  mState := mServices.EditorState[mEditor];
  if (mState = nil) or not mState.PointToCharacterPos(mPoint, mColumn, mVisibleLine) then
  begin
    Exit;
  end;
  ALine := mState.LineState[mVisibleLine].LogicalLineNum;
  if (ALine < 1) or (ALine > ATable.LineCount) then
  begin
    Exit;
  end;
  mLineText := LineOf(AText, ATable, ALine - 1);
  ACharacter := TLspSession.ColumnToIndex(mLineText, mColumn, ATabWidth);
  Result := (ACharacter < Length(mLineText)) and TDpccWord.IsIdentifierChar(mLineText[ACharacter + 1]);
end;

class function TDpccCodeInsightQueries.GotoPlace(const AView: IOTAEditView; const ADiagnose: TProc<string>;
  out APlace: TDpccGotoPlace): Boolean;
var
  mTable: TLineTable;
  mCursor: TOTAEditPos;
  mTabWidth, mMouseLine, mMouseCharacter: Integer;
  mMouseOver, mMouseValid, mCtrlDown: Boolean;
  mCaret, mAt: TPoint;
  mCaretLineText: string;
begin
  APlace := Default(TDpccGotoPlace);
  APlace.Text := TDpccEditorBuffer.Text(AView.Buffer);
  mTable := TLineTable.Build(APlace.Text);
  mTabWidth := TDpccEditorBuffer.TabWidth(AView.Buffer);
  // Die synchrone Schnittstelle übergibt keine Klickstelle. Bei Strg+Klick gilt die Stelle unter der Maus (ob die
  // IDE den Cursor vorher dorthin setzt, ist nicht geprüft), sonst der Cursor („Deklaration suchen“, Alt+↑).
  mCursor := AView.CursorPos;
  mCaret := TPoint.Create(-1, mCursor.Line);
  mCaretLineText := '';
  if (mCursor.Line >= 1) and (mCursor.Line <= mTable.LineCount) then
  begin
    mCaretLineText := LineOf(APlace.Text, mTable, mCursor.Line - 1);
    mCaret.X := TLspSession.ColumnToIndex(mCaretLineText, mCursor.Col, mTabWidth);
  end;
  mCtrlDown := GetKeyState(VK_CONTROL) < 0;
  // Die Mausstelle auch ohne Strg: nur fürs Diagnoseprotokoll.
  mMouseOver := MousePosition(AView, APlace.Text, mTable, mTabWidth, mMouseLine, mMouseCharacter);
  mMouseValid := mCtrlDown and mMouseOver;
  mAt := TDpccGotoDefinition.ChoosePosition(mCtrlDown, mMouseValid, TPoint.Create(mMouseCharacter, mMouseLine),
    mCaret);
  // Ein Lauf mit Diagnose = 1 klärt, welche Stelle die IDE meint (Annahmen im Kopf der Unit).
  ADiagnose(Format('Gehe zu Definition: Stelle der IDE keine (nur Index), Strg %s, Cursor %d:%d (Editorspalte ' +
    '%d), Maus %s %d:%d, gefragt %d:%d (%s)', [BoolToStr(mCtrlDown, True), mCaret.Y, mCaret.X + 1, mCursor.Col,
    IfThen(mMouseOver, 'über Bezeichner', 'nicht über Bezeichner'), mMouseLine, mMouseCharacter + 1, mAt.Y,
    mAt.X + 1, IfThen(mMouseValid, 'Maus', 'Cursor')]));
  Result := (mAt.X >= 0) and (mAt.Y >= 1) and (mAt.Y <= mTable.LineCount);
  if not Result then
  begin
    ADiagnose(Format('Gehe zu Definition: Zeile %d außerhalb des Puffers (%d Zeilen)', [mAt.Y, mTable.LineCount]));
    Exit;
  end;
  APlace.Origin.FileName := AView.Buffer.FileName;
  APlace.Origin.CaretLine := mCaret.Y;
  APlace.Origin.CaretCharacter := mCaret.X;
  APlace.Origin.AtLine := mAt.Y;
  APlace.Origin.AtCharacter := mAt.X;
  APlace.Origin.StartedMs := TThread.GetTickCount64;
  APlace.LineText := LineOf(APlace.Text, mTable, mAt.Y - 1);
  APlace.Mouse := mMouseValid;
  APlace.Origin.AtMouse := mMouseValid;
  // Für das Urteil über eine nachgereichte Antwort: der Bezeichner an Klickstelle und Cursor (gleiches Wort genügt).
  TDpccLateGoto.WordRange(APlace.LineText, mAt.X, APlace.Origin.AtWordStart, APlace.Origin.AtWordEnd);
  TDpccLateGoto.WordRange(mCaretLineText, mCaret.X, APlace.Origin.CaretWordStart, APlace.Origin.CaretWordEnd);
end;

class function TDpccCodeInsightQueries.GotoNow(AGeneration: Cardinal): TDpccGotoNow;
var
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
begin
  Result := Default(TDpccGotoNow);
  Result.Generation := AGeneration;
  Result.NowMs := TThread.GetTickCount64;
  // Nicht CurrentEditView: Außerhalb eines Aufrufs der IDE gilt die aktive Ansicht.
  mView := TDpccEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  mCursor := mView.CursorPos;
  Result.FileName := mView.Buffer.FileName;
  Result.CaretLine := mCursor.Line;
  Result.CaretCharacter := TLspSession.ColumnToIndex(TDpccEditorBuffer.LineText(mView, mCursor.Line), mCursor.Col,
    TDpccEditorBuffer.TabWidth(mView.Buffer));
end;

class function TDpccCodeInsightQueries.GotoNote(AIndex: Integer; const APlace: TDpccGotoPlace;
  const AResult: string): string;
begin
  Result := Format('Gehe zu Definition (Index %d) (%s), Zeile %d, Zeichen %d (%s): %s',
    [AIndex, ExtractFileExt(APlace.Origin.FileName), APlace.Origin.AtLine, APlace.Origin.AtCharacter,
    IfThen(APlace.Mouse, 'Maus', 'Cursor'), AResult]);
end;

end.
