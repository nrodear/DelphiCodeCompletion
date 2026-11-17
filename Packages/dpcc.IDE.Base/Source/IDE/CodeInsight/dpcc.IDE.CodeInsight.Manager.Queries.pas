unit dpcc.IDE.CodeInsight.Manager.Queries;

// Fragen des Code Insight-Managers an den Editor: Welche Code Insight löst eine Taste aus (Vervollständigung nach
// ".", Parameterhilfe nach "(", XMLDoc-Tags nach "<" in ///-Zeilen #435, Mengen nach "[" #448, try…finally nach ";"
// #489, Mitglieder nach "{" in Wertdarstellungen #854, Feldnamen nach ' in FieldByName #461)? Dazu Symbolhinweis
// (GetHintText, mit Wert im angehaltenen Debugger #891) und das Sprungziel für Strg+Klick und „Deklaration suchen“
// (Auftrag NAV) an der Klickstelle bzw. am Cursor.

interface

uses
  System.SysUtils,
  ToolsAPI,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Editor.Navigation;

type
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
    /// <summary>Hover-Text an Zeile AHintLine, Spalte AHintCol (1-basiert) von AView; '' außerhalb des Puffers.
    /// </summary>
    class function HintAt(ASession: TLspSession; const AView: IOTAEditView; AHintLine, AHintCol: Integer;
      const ADiagnose: TProc<string>): string; static;
    /// <summary>Ziel für Strg+Klick und „Deklaration suchen“ (NAV) an ALine, ACharacter (0-basiert) in AView
    /// (TLspSession.GotoTarget, Zeitlimit für den Hauptthread); False ohne Ziel oder mit einer Ersatz-Unit des
    /// Servers (dpcc-ide:…), die es nicht als Datei gibt.</summary>
    class function DefinitionOf(ASession: TLspSession; const AView: IOTAEditView; ALine, ACharacter: Integer;
      out ALocation: TLspLocation): Boolean; static;
    /// <summary>Sprungziel an der Klickstelle (Strg gedrückt, Maus über einem Bezeichner im Editor von AView),
    /// sonst am Cursor: Found mit AFileName und ALine (0-basiert), sonst NotFound bzw. NoView. Fehler und
    /// Zeitlimit kommen als Exception.</summary>
    class function DefinitionAt(ASession: TLspSession; const AView: IOTAEditView; AIndex: Integer;
      const ADiagnose: TProc<string>; out AFileName: string; out ALine: Integer): TDpccGotoOutcome; static;
  end;

implementation

uses
  Winapi.Windows,
  System.Types,
  System.StrUtils,
  Vcl.Controls,
  ToolsAPI.Editor,
  dpcc.Text.DebugDisplay,
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
begin
  Result := AHover;
  if not TDpccIdeSettings.Current.DebugHoverValues or not TDpccIdeDebugValues.Stopped then
  begin
    Exit;
  end;
  mDebugText := TDpccIdeDebugValues.EvaluateNow(TDpccDebugExpression.AtCharacter(ALine, ACharacter), AFileName,
    AHintLine).PlainText;
  if (mDebugText <> '') and (Result <> '') then
  begin
    Result := mDebugText + #13#10#13#10 + Result;
  end
  else if mDebugText <> '' then
  begin
    Result := mDebugText;
  end;
end;

class function TDpccCodeInsightQueries.HintAt(ASession: TLspSession; const AView: IOTAEditView; AHintLine,
  AHintCol: Integer; const ADiagnose: TProc<string>): string;
var
  mText: string;
  mLines: TArray<string>;
  mCharacter: Integer;
begin
  Result := '';
  mText := TDpccEditorBuffer.Text(AView.Buffer);
  mLines := mText.Split([#13#10, #10]);
  if (AHintLine < 1) or (AHintLine > Length(mLines)) then
  begin
    Exit;
  end;
  mCharacter := TLspSession.ColumnToIndex(mLines[AHintLine - 1], AHintCol, TDpccEditorBuffer.TabWidth(AView.Buffer));
  // Die IDE wartet im Hauptthread auf den Hinweis: kurzes Zeitlimit.
  Result := ASession.Hover(AView.Buffer.FileName, mText, AHintLine - 1, mCharacter, TLspSession.cMainThreadTimeoutMs);
  Result := WithDebugValue(Result, mLines[AHintLine - 1], AView.Buffer.FileName, mCharacter, AHintLine);
  ADiagnose(Format('Hover (%s), Zeile %d, Spalte %d (Cursor %d/%d): %d Zeichen',
    [ExtractFileExt(AView.Buffer.FileName), AHintLine, AHintCol, AView.CursorPos.Line, AView.CursorPos.Col,
    Length(Result)]));
end;

class function TDpccCodeInsightQueries.DefinitionOf(ASession: TLspSession; const AView: IOTAEditView; ALine,
  ACharacter: Integer; out ALocation: TLspLocation): Boolean;
begin
  // Ersatz-Units des Servers (dpcc-ide:…) gibt es nicht als Datei: kein Sprungziel für Strg+Klick.
  Result := ASession.GotoTarget(AView.Buffer.FileName, TDpccEditorBuffer.Text(AView.Buffer), ALine, ACharacter,
    TLspSession.cMainThreadTimeoutMs, ALocation) and not TDpccIdeMembers.IsIdePath(ALocation.FileName);
end;

/// <summary>Stelle unter der Maus im Editor von AView: Zeile (1-basiert) und Zeichen (0-basiert) über einem
/// Bezeichner; False außerhalb des Editors oder neben einem Bezeichner.</summary>
function MousePosition(const AView: IOTAEditView; const ALines: TArray<string>; ATabWidth: Integer;
  out ALine, ACharacter: Integer): Boolean;
var
  mServices: INTACodeEditorServices;
  mEditor: TWinControl;
  mState: INTACodeEditorState;
  mPoint: TPoint;
  mColumn, mVisibleLine: Integer;
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
  if (ALine < 1) or (ALine > Length(ALines)) then
  begin
    Exit;
  end;
  ACharacter := TLspSession.ColumnToIndex(ALines[ALine - 1], mColumn, ATabWidth);
  Result := (ACharacter < Length(ALines[ALine - 1])) and
    TDpccWord.IsIdentifierChar(ALines[ALine - 1][ACharacter + 1]);
end;

class function TDpccCodeInsightQueries.DefinitionAt(ASession: TLspSession; const AView: IOTAEditView;
  AIndex: Integer; const ADiagnose: TProc<string>; out AFileName: string; out ALine: Integer): TDpccGotoOutcome;
var
  mText: string;
  mLines: TArray<string>;
  mCursor: TOTAEditPos;
  mTabWidth, mMouseLine, mMouseCharacter: Integer;
  mMouseValid, mCtrlDown: Boolean;
  mCaret, mAt: TPoint;
  mLocation: TLspLocation;
begin
  AFileName := '';
  ALine := 0;
  mText := TDpccEditorBuffer.Text(AView.Buffer);
  mLines := mText.Split([#13#10, #10]);
  mTabWidth := TDpccEditorBuffer.TabWidth(AView.Buffer);
  // Die synchrone Schnittstelle übergibt keine Klickstelle. Bei Strg+Klick gilt die Stelle unter der Maus (ob die
  // IDE den Cursor vorher dorthin setzt, ist nicht geprüft), sonst der Cursor („Deklaration suchen“, Alt+↑).
  mCursor := AView.CursorPos;
  mCaret := TPoint.Create(-1, mCursor.Line);
  if (mCursor.Line >= 1) and (mCursor.Line <= Length(mLines)) then
  begin
    mCaret.X := TLspSession.ColumnToIndex(mLines[mCursor.Line - 1], mCursor.Col, mTabWidth);
  end;
  mMouseLine := 0;
  mMouseCharacter := 0;
  mCtrlDown := GetKeyState(VK_CONTROL) < 0;
  mMouseValid := mCtrlDown and MousePosition(AView, mLines, mTabWidth, mMouseLine, mMouseCharacter);
  mAt := TDpccGotoDefinition.ChoosePosition(mCtrlDown, mMouseValid, TPoint.Create(mMouseCharacter, mMouseLine),
    mCaret);
  if (mAt.X < 0) or (mAt.Y < 1) or (mAt.Y > Length(mLines)) then
  begin
    ADiagnose(Format('Gehe zu Definition: Zeile %d außerhalb des Puffers (%d Zeilen)', [mAt.Y, Length(mLines)]));
    Exit(TDpccGotoOutcome.NoView);
  end;
  Result := TDpccGotoOutcome.NotFound;
  if DefinitionOf(ASession, AView, mAt.Y - 1, mAt.X, mLocation) then
  begin
    AFileName := mLocation.FileName;
    ALine := mLocation.Line;
    Result := TDpccGotoOutcome.Found;
  end;
  ADiagnose(Format('Gehe zu Definition (Index %d) (%s), Zeile %d, Zeichen %d (%s): %s',
    [AIndex, ExtractFileExt(AView.Buffer.FileName), mAt.Y, mAt.X, IfThen(mMouseValid, 'Maus', 'Cursor'),
    IfThen(AFileName <> '', Format('%s, Zeile %d', [ExtractFileExt(AFileName), ALine + 1]), 'kein Ziel')]));
end;

end.
