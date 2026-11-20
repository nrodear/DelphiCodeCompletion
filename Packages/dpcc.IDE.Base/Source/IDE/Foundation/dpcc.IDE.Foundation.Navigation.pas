unit dpcc.IDE.Foundation.Navigation;

// Zu einer Stelle springen (#400, #588): Datei öffnen, Editor zeigen, Cursor setzen. Foundation des Plugins
//: bis dahin TDpccEditorHover.GoToLocation; Ergebnisfenster, Umbenennen, Vervollständigung, Befehle
// und Unit-Suche importierten dafür den Hover. Nur im Hauptthread.
// Ersatz-Units des Servers (dpcc-ide:…, nur aus der RTTI der Packages) gibt es nicht als Datei: kein Sprung
// dorthin, die IDE legte sonst einen leeren Reiter unter diesem Namen an.
// ACharacter ist ein Zeichenindex wie im LSP; die Spalte des Editors rechnet Tabs mit der Tabulatorweite des Puffers
// um (vorher Zeichen + 1: In Zeilen mit Tabs landete der Cursor zu weit links). TryGoToLocation meldet, woran ein
// Sprung scheiterte (Datei nicht zu öffnen, kein Quelltexteditor, keine Ansicht), statt still aufzugeben.

interface

type
  TDpccIdeNavigation = class
  public
    /// <summary>Zeigt AFileName (öffnet sie nur, wenn sie noch nicht offen ist) und setzt den Cursor auf
    /// ALine/ACharacter (0-basiert).</summary>
    class procedure GoToLocation(const AFileName: string; ALine, ACharacter: Integer); static;
    /// <summary>Wie GoToLocation; True nach dem Sprung, sonst False mit dem Grund in AProblem (fürs Protokoll).
    /// </summary>
    class function TryGoToLocation(const AFileName: string; ALine, ACharacter: Integer;
      out AProblem: string): Boolean; static;
    /// <summary>Zeigt AFileName ohne Sprung; öffnet sie nur, wenn sie noch nicht offen ist. False, wenn die IDE sie
    /// nicht öffnen kann.</summary>
    class function ShowFile(const AFileName: string): Boolean; static;
    /// <summary>Setzt den Cursor im oberen Editor auf ALine/ACharacter (0-basiert), z. B. für den Sprung
    /// einer Code-Aktion zur Freigabe (#915).</summary>
    class procedure GoToPosition(ALine, ACharacter: Integer); static;
    /// <summary>Öffnet AFileName, markiert die ganze Zeile ALine (0-basiert) und setzt den Cursor an ihren Anfang,
    /// z. B. für den Sprung in eigenen Code nach einer Exception (#578).</summary>
    class procedure MarkLine(const AFileName: string; ALine: Integer); static;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  dpcc.Core.Lsp.IdeMembers,
  dpcc.Core.Lsp.Session.Json,
  dpcc.IDE.Foundation.EditorBuffer;

/// <summary>Modul von AFileName; öffnet die Datei nur, wenn sie noch nicht offen ist. OpenFile öffnete sie sonst
/// jedes Mal neu (Doppelklick in „dpcc-Prüfung“), bei Formular-Units samt Designer. nil, wenn das scheitert.
/// </summary>
function OpenModule(const AFileName: string): IOTAModule;
var
  mActions: IOTAActionServices;
  mModules: IOTAModuleServices;
begin
  Result := nil;
  if TDpccIdeMembers.IsIdePath(AFileName) or not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  Result := mModules.FindModule(AFileName);
  if (Result = nil) and Supports(BorlandIDEServices, IOTAActionServices, mActions) and
    mActions.OpenFile(AFileName) then
  begin
    Result := mModules.FindModule(AFileName);
  end;
end;

/// <summary>Erster Quelltexteditor des Moduls; nil ohne.</summary>
function SourceEditorOf(const AModule: IOTAModule): IOTASourceEditor;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AModule.ModuleFileCount - 1 do
  begin
    if Supports(AModule.ModuleFileEditors[mIndex], IOTASourceEditor, Result) then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

class procedure TDpccIdeNavigation.GoToLocation(const AFileName: string; ALine, ACharacter: Integer);
var
  mProblem: string;
begin
  TryGoToLocation(AFileName, ALine, ACharacter, mProblem);
end;

class function TDpccIdeNavigation.TryGoToLocation(const AFileName: string; ALine, ACharacter: Integer;
  out AProblem: string): Boolean;
var
  mModule: IOTAModule;
  mEditor: IOTASourceEditor;
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
begin
  Result := False;
  AProblem := '';
  if TDpccIdeMembers.IsIdePath(AFileName) then
  begin
    AProblem := 'Ersatz-Unit ohne Quelltext';
    Exit;
  end;
  // Schon offen: nur den Reiter zeigen und springen.
  mModule := OpenModule(AFileName);
  if mModule = nil then
  begin
    AProblem := 'Datei ließ sich nicht öffnen';
    Exit;
  end;
  mEditor := SourceEditorOf(mModule);
  if mEditor = nil then
  begin
    AProblem := 'kein Quelltexteditor';
    Exit;
  end;
  mEditor.Show;
  if mEditor.EditViewCount = 0 then
  begin
    AProblem := 'keine Editoransicht';
    Exit;
  end;
  mView := mEditor.EditViews[0];
  mCursor.Line := ALine + 1;
  // Spalte des Editors: Tabs springen zur nächsten Tabulatorposition.
  if mView.Buffer <> nil then
  begin
    mCursor.Col := TLspSessionJson.IndexToColumn(TDpccEditorBuffer.LineText(mView, ALine + 1), ACharacter,
      TDpccEditorBuffer.TabWidth(mView.Buffer));
  end
  else
  begin
    mCursor.Col := ACharacter + 1;
  end;
  mView.CursorPos := mCursor;
  mView.MoveViewToCursor;
  mView.Paint;
  Result := True;
end;

class function TDpccIdeNavigation.ShowFile(const AFileName: string): Boolean;
var
  mActions: IOTAActionServices;
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mIndex: Integer;
  mEditor: IOTASourceEditor;
begin
  Result := False;
  if TDpccIdeMembers.IsIdePath(AFileName) or not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  // Wie GoToLocation: OpenFile öffnete eine offene Datei erneut, bei Formular-Units samt Designer.
  mModule := mModules.FindModule(AFileName);
  if mModule <> nil then
  begin
    for mIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      if Supports(mModule.ModuleFileEditors[mIndex], IOTASourceEditor, mEditor) then
      begin
        mEditor.Show;
        Exit(True);
      end;
    end;
  end;
  Result := Supports(BorlandIDEServices, IOTAActionServices, mActions) and mActions.OpenFile(AFileName);
end;

class procedure TDpccIdeNavigation.GoToPosition(ALine, ACharacter: Integer);
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
begin
  if not Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Exit;
  end;
  mView := mEditors.TopView;
  if mView = nil then
  begin
    Exit;
  end;
  mCursor.Line := ALine + 1;
  mCursor.Col := ACharacter + 1;
  mView.CursorPos := mCursor;
  mView.MoveViewToCursor;
  mView.Paint;
end;

class procedure TDpccIdeNavigation.MarkLine(const AFileName: string; ALine: Integer);
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mCursor: TOTAEditPos;
begin
  GoToLocation(AFileName, ALine, 0);
  if not Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Exit;
  end;
  mView := mEditors.TopView;
  if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, AFileName) then
  begin
    Exit;
  end;
  // Zeilenanfang markieren, Cursor an den Anfang der nächsten Zeile, Ende markieren, Cursor zurück.
  mView.Block.Style := btNonInclusive;
  mCursor.Line := ALine + 1;
  mCursor.Col := 1;
  mView.CursorPos := mCursor;
  mView.Block.BeginBlock;
  mCursor.Line := ALine + 2;
  mView.CursorPos := mCursor;
  mView.Block.EndBlock;
  mCursor.Line := ALine + 1;
  mView.CursorPos := mCursor;
  mView.MoveViewToCursor;
  mView.Paint;
end;

end.
