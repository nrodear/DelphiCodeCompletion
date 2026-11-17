unit dpcc.IDE.Hover.Editor;

// Hover-Tooltip im Editor (#442) über die Code-Editor-API (ToolsAPI.Editor), seit S3 schlicht wie die
// Vervollständigung (dpcc.UI.Hover.Tip, Inhalt aus dpcc.Core.Hover.Plain):
//   - Mausbewegung im Editor → Bezeichner unter der Maus (Zeile, Wortgrenzen).
//   - Nach 500 ms Verweilen auf demselben Bezeichner: textDocument/hover im Hintergrund (die IDE wartet nie auf
//     den Server, TLspSession.HoverDataAt) und Tooltip unter dem Wort.
//   - Schließen 300 ms nachdem die Maus Bezeichner und Tooltip verlassen hat; sofort bei Esc und jeder anderen
//     Taste (außer Umschalt, Strg, Alt allein), Mausklick, Scrollen, Größenänderung, IDE inaktiv (ein Wächter
//     prüft das, solange der Tooltip offen ist, #414).
// Die IDE zeigt dann keinen eigenen Tooltip: GetHintText und GetHelpInsightHtml liefern '' (Manager), Help
// Insight schaltet dpcc.IDE.Foundation.InsightSwitch ab. Bedient dpcc die Datei nicht (Hauptschalter, Server
// fehlt, Sicherung), übernimmt die IDE und der dpcc-Tooltip bleibt zu.
// Delphi 12 (#281): Tastatur-Ereignisse des Code-Editors gibt es erst ab Delphi 13 (INTACodeEditorEvents370).
// Dort schließt der Tooltip über den Tastatur-Hook, solange er sichtbar ist.
// Debuggen (#891, seit S3b wieder): Ist der Prozess angehalten und debug.hoverValues an, wertet dpcc den Ausdruck
// unter der Maus über den Debugger der IDE aus (TDpccIdeDebugValues, ohne Nebenwirkungen) und zeigt den Wert ganz
// oben; ohne Antwort des Servers nur den Wert. Antwortet der Debugger verzögert, steht dort „wird ausgewertet …“,
// bis der Wert kommt (DebugValueDone zeigt den Tooltip neu).
// Andere Popups (S3c): Ist über dem Editor die Liste der Vervollständigung (der IDE oder von dpcc), ein Parameter-
// Hint oder ein Menü offen, erscheint kein Tooltip; geht eins auf, schließt der offene Tooltip (Wächter alle
// 100 ms, TDpccCloseRules.OtherPopup über die obersten Fenster des Hauptthreads). Aussehen: Farben der
// Code-Insight-Liste (TDpccIdeStyle.ListColors).
// Strg+Klick (NAV): Bei gedrückter Strg-Taste lässt der Tooltip Maus und Klick an den Editor darunter durch
// (TDpccTooltipMouse.PassThrough), und Strg schließt ihn, wenn die Maus über ihm steht (KeyCloses): So bleibt ein
// Wort, das er verdeckt, mit Strg+Klick erreichbar.
// Seit S3 entfallen Verlauf und Anheften, Aktionen, Links und Kopieren. Probleme an der Mausposition zeigt der
// Tooltip nicht: Seit R6 gibt es in der IDE keine Quelle mehr dafür (der Rückruf war schon vor S3 nil).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Hover.Contract,
  dpcc.Core.Hover.DebugValue,
  dpcc.Core.Editor.CloseRules,
  dpcc.Core.Editor.Navigation,
  dpcc.IDE.Foundation.KeyHook,
  dpcc.IDE.Hover.DebugValue,
  dpcc.UI.Hover.Tip;

type
  TDpccHoverSessionFunc = reference to function: TLspSession;
  TDpccHoverLogFunc = reference to procedure(const AMessage: string);
  /// <summary>Bedient dpcc die Datei? Sonst zeigt die IDE ihren eigenen Tooltip.</summary>
  TDpccHoverHandlesFunc = reference to function(const AFileName: string): Boolean;

  /// <summary>Lebt der Tooltip noch? Hintergrund-Anfragen prüfen das, bevor sie ihr Ergebnis zeigen.</summary>
  TDpccHoverAlive = class(TInterfacedObject)
  public
    Alive: Boolean;
  end;

  /// <summary>Stelle unter der Maus im Editor: Zeile (1-basiert), Spalte und sichtbare Zeile des Editors, Index im
  /// Zeilentext (0-basiert).</summary>
  TDpccHoverMousePos = record
    State: INTACodeEditorState;
    Editor: TWinControl;
    View: IOTAEditView;
    Line: Integer;
    Column: Integer;
    VisibleLine: Integer;
    Index: Integer;
    Text: string;
  end;

  TDpccEditorHover = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
    end;

    THoverKeys = class(TDpccKeyClient)
    private
      FOwner: TDpccEditorHover;
    protected
      function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
      procedure HandleKey(AKey: Word; AShift: TShiftState); override;
    public
      constructor Create(AOwner: TDpccEditorHover);
    end;
  public const
    /// <summary>Nach Vervollständigung (0) und Parameter-Hint (10).</summary>
    cKeyPriority = 20;
  private
    FTip: TDpccHoverTip;
    FSession: TDpccHoverSessionFunc;
    FLog: TDpccHoverLogFunc;
    FHandles: TDpccHoverHandlesFunc;
    // FAlive endet mit dem Objekt; Hintergrund-Anfragen prüfen es.
    FAlive: TDpccHoverAlive;
    FAliveRef: IInterface;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FKeys: THoverKeys;
    FShowTimer: TTimer;
    FHideTimer: TTimer;
    FWatchTimer: TTimer;
    // Anfrage an den Server im Hintergrund: Die IDE friert nie ein, auch wenn er langsam ist.
    // FRequest zählt die Anfragen; nur die jüngste wird angezeigt.
    FRequest: Integer;
    FWorkers: TList<TThread>;
    // Bezeichner unter der Maus bzw. im offenen Tooltip.
    FEditor: TWinControl;
    FView: IOTAEditView;
    FLine: Integer;
    FStart: Integer;
    FWordRect: TRect;
    FKey: string;
    FShownKey: string;
    // Fenster beim Anzeigen (Fokus, Datei, oberste Zeile); TDpccCloseRules vergleicht damit.
    FShown: TDpccEditorWindowState;
    // Antwort des Servers im offenen Tooltip; ein verzögerter Wert im Debugger zeigt sie neu.
    FShownData: TDpccHoverData;
    // Wert im angehaltenen Debugger (#891): Ausdruck unter der Maus ('' ohne angehaltenen Prozess) und Wert.
    FDebug: TDpccIdeDebugValues;
    FDebugExpression: string;
    FDebugValue: TDpccDebugValue;
    /// <summary>Wert des Ausdrucks unter der Maus anfordern (#891); verzögerte Werte ergänzt DebugValueDone.</summary>
    procedure EvaluateDebugValue;
    procedure DebugValueDone(const AKey: string; const AValue: TDpccDebugValue);
    /// <summary>Zeigt AData mit dem Wert im Debugger unter dem Wort.</summary>
    procedure ShowTip(const AData: TDpccHoverData);
    /// <summary>Ist über dem Editor ein anderes Popup offen (Liste der Vervollständigung, Parameter-Hint, Menü)?
    /// Dann kein Tooltip bzw. schließen (S3c, TDpccCloseRules.OtherPopup).</summary>
    function OtherPopupOpen: Boolean;
    procedure Log(const AMessage: string);
    function Handles(const AFileName: string): Boolean;
    function CurrentSession: TLspSession;
    function CurrentEditView: IOTAEditView;
    function MouseOverTip: Boolean;
    /// <summary>Liegt der Editor unter der Maus (kein anderes Fenster davor)?</summary>
    function MouseOverEditor: Boolean;
    function WindowState: TDpccEditorWindowState;
    procedure EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
    /// <summary>Stelle unter der Maus in einer Datei, die dpcc bedient; False sonst.</summary>
    function MousePos(const AEditor: TWinControl; AX, AY: Integer; out APos: TDpccHoverMousePos): Boolean;
    /// <summary>Schlüssel des Bezeichners an APos ('' ohne); ein neuer setzt Wort und Wortrechteck.</summary>
    function WordKey(const APos: TDpccHoverMousePos): string;
    /// <summary>Zeitgeber nach dem Schlüssel unter der Maus: anzeigen, offen lassen oder schließen.</summary>
    procedure TrackKey(const AKey: string);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    {$IF CompilerVersion >= 37.0}
    procedure EditorKeyDown(const Editor: TWinControl; Key: Word; Shift: TShiftState; var Handled: Boolean);
    {$ENDIF}
    procedure EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
    procedure EditorResized(const Editor: TWinControl);
    procedure ShowData(const AData: TDpccHoverData);
    procedure ReapWorkers(AWait: Boolean);
    procedure ShowTimerTick(Sender: TObject);
    /// <summary>textDocument/hover im Hintergrund; das Ergebnis zeigt ShowData im Hauptthread.</summary>
    procedure RequestHover(ASession: TLspSession);
    procedure HideTimerTick(Sender: TObject);
    procedure WatchTimerTick(Sender: TObject);
  public
    constructor Create(const ASession: TDpccHoverSessionFunc; const ALog: TDpccHoverLogFunc;
      const AHandles: TDpccHoverHandlesFunc); overload;
    /// <summary>Wie oben mit AHandles = nil (jede Datei).</summary>
    constructor Create(const ASession: TDpccHoverSessionFunc; const ALog: TDpccHoverLogFunc); overload;
    destructor Destroy; override;
    procedure Hide;
    /// <summary>Laufende Anfragen abwarten, bevor die Sitzung wegfällt (Neustart, Abschalten).
    /// Ihre Ergebnisse zeigt der Tooltip nicht mehr. Nur im Hauptthread.</summary>
    procedure Shutdown;
  end;

implementation

uses
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.MainThread,
  Winapi.Windows,
  Vcl.Forms,
  dpcc.Core.Completion.Word,
  dpcc.Core.Documentation.Contract,
  dpcc.Core.Hover.Plain,
  dpcc.IDE.Foundation.EditorBuffer,
  dpcc.IDE.Foundation.EditorStyle,
  dpcc.IDE.Foundation.Settings;

{ TDpccEditorHover.TEvents }

function TDpccEditorHover.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevWindowEvents, cevMouseEvents];
  {$IF CompilerVersion >= 37.0}
  Include(Result, cevKeyboardEvents);
  {$ENDIF}
end;

{ TDpccEditorHover.THoverKeys }

constructor TDpccEditorHover.THoverKeys.Create(AOwner: TDpccEditorHover);
begin
  inherited Create(cKeyPriority);
  FOwner := AOwner;
end;

function TDpccEditorHover.THoverKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  // Nur Esc gehört dem Tooltip; andere Tasten gehen an den Editor und schließen ihn dort.
  Result := FOwner.FTip.IsShown and (AKey = VK_ESCAPE) and (AShift = []);
  {$IF CompilerVersion < 37.0}
  // Ohne Tastatur-Ereignisse des Editors: andere Tasten schließen nach der Verarbeitung (wie EditorKeyDown).
  if not Result and FOwner.FTip.IsShown and TDpccTooltipMouse.KeyCloses(AKey, FOwner.MouseOverTip) then
  begin
    TDpccMainThread.ForceQueue(TDpccFeature.Hover,
      procedure
      begin
        FOwner.Hide;
      end);
  end;
  {$ENDIF}
end;

procedure TDpccEditorHover.THoverKeys.HandleKey(AKey: Word; AShift: TShiftState);
begin
  try
    FOwner.Hide;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Hover, E);
  end;
end;

{ TDpccEditorHover }

constructor TDpccEditorHover.Create(const ASession: TDpccHoverSessionFunc; const ALog: TDpccHoverLogFunc);
begin
  Create(ASession, ALog, nil);
end;

constructor TDpccEditorHover.Create(const ASession: TDpccHoverSessionFunc; const ALog: TDpccHoverLogFunc;
  const AHandles: TDpccHoverHandlesFunc);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
  FHandles := AHandles;
  FTip := TDpccHoverTip.Create(nil);
  // Strg+Klick auf ein Wort unter dem Tooltip (NAV): Mit Strg geht die Maus an den Editor.
  FTip.MouseTransparent :=
    function: Boolean
    begin
      Result := TDpccTooltipMouse.PassThrough(GetKeyState(VK_CONTROL) < 0);
    end;
  FDebug := TDpccIdeDebugValues.Create;
  FAlive := TDpccHoverAlive.Create;
  FAlive.Alive := True;
  FAliveRef := FAlive;
  FIndex := -1;
  FKeys := THoverKeys.Create(Self);
  FWorkers := TList<TThread>.Create;
  FShowTimer := TTimer.Create(nil);
  FShowTimer.Enabled := False;
  FShowTimer.Interval := TDpccCloseRules.cTooltipShowDelayMs;
  FShowTimer.OnTimer := ShowTimerTick;
  FHideTimer := TTimer.Create(nil);
  FHideTimer.Enabled := False;
  FHideTimer.Interval := TDpccCloseRules.cTooltipHideDelayMs;
  FHideTimer.OnTimer := HideTimerTick;
  FWatchTimer := TTimer.Create(nil);
  FWatchTimer.Enabled := False;
  // 100 ms: Geht eine Liste der Vervollständigung auf, schließt der Tooltip praktisch sofort (S3c).
  FWatchTimer.Interval := 100;
  FWatchTimer.OnTimer := WatchTimerTick;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorMouseMove := EditorMouseMove;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  {$IF CompilerVersion >= 37.0}
  FEvents.OnEditorKeyDown := EditorKeyDown;
  {$ENDIF}
  FEvents.OnEditorScrolled := EditorScrolled;
  FEvents.OnEditorResized := EditorResized;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TDpccEditorHover.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  TDpccKeyHook.Remove(FKeys);
  if FEvents <> nil then
  begin
    FEvents.OnEditorMouseMove := nil;
    FEvents.OnEditorMouseDown := nil;
    {$IF CompilerVersion >= 37.0}
    FEvents.OnEditorKeyDown := nil;
    {$ENDIF}
    FEvents.OnEditorScrolled := nil;
    FEvents.OnEditorResized := nil;
  end;
  FEventsRef := nil;
  // Laufende Anfragen zeigen nichts mehr; auf sie warten, bevor die Sitzung wegfällt.
  if FAlive <> nil then
  begin
    FAlive.Alive := False;
  end;
  ReapWorkers(True);
  FWorkers.Free;
  FShowTimer.Free;
  FHideTimer.Free;
  FWatchTimer.Free;
  FKeys.Free;
  FDebug.Free;
  FTip.Free;
  inherited Destroy;
end;

procedure TDpccEditorHover.Log(const AMessage: string);
begin
  if Assigned(FLog) then
  begin
    FLog(AMessage);
  end;
end;

function TDpccEditorHover.Handles(const AFileName: string): Boolean;
begin
  Result := not Assigned(FHandles) or FHandles(AFileName);
end;

function TDpccEditorHover.CurrentSession: TLspSession;
begin
  Result := nil;
  if Assigned(FSession) then
  begin
    Result := FSession();
  end;
end;

function TDpccEditorHover.CurrentEditView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
end;

function TDpccEditorHover.MouseOverEditor: Boolean;
var
  mUnder: HWND;
begin
  // Liegt ein anderes Fenster über dem Editor (z. B. „Units suchen“), kein Tooltip darüber.
  mUnder := WindowFromPoint(Mouse.CursorPos);
  Result := (FEditor <> nil) and FEditor.HandleAllocated and
    ((mUnder = FEditor.Handle) or IsChild(FEditor.Handle, mUnder));
end;

function TDpccEditorHover.MouseOverTip: Boolean;
begin
  Result := FTip.IsShown and PtInRect(FTip.BoundsRect, Mouse.CursorPos);
end;

procedure TDpccEditorHover.Hide;
begin
  FWatchTimer.Enabled := False;
  FShowTimer.Enabled := False;
  FHideTimer.Enabled := False;
  TDpccKeyHook.Remove(FKeys);
  FDebug.Cancel;
  FDebugValue := Default(TDpccDebugValue);
  FShownData := Default(TDpccHoverData);
  FTip.HidePopup;
  FShownKey := '';
  FKey := '';
  FView := nil;
end;

procedure TDpccEditorHover.Shutdown;
begin
  // Eingereihte Ergebnisse veralten (Show vergleicht FRequest); die Arbeiter halten die Sitzung als rohen Zeiger.
  // Ohne Hide: Der Tooltip zeigt kopierte Daten, ein Neustart soll ihn nicht schließen.
  Inc(FRequest);
  ReapWorkers(True);
end;

procedure TDpccEditorHover.EditorMouseMove(const Editor: TWinControl; Shift: TShiftState; X, Y: Integer);
var
  mPos: TDpccHoverMousePos;
  mKey: string;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TDpccGuard.Disabled(TDpccFeature.Hover) then
  begin
    Exit;
  end;
  try
    if not TDpccIdeSettings.Current.Enabled or not TDpccIdeSettings.Current.HoverTooltip then
    begin
      Exit;
    end;
    mKey := '';
    if MousePos(Editor, X, Y, mPos) then
    begin
      mKey := WordKey(mPos);
    end;
    TrackKey(mKey);
  except
    on E: Exception do
    begin
      Log('Hover: ' + E.Message);
      TDpccGuard.Report(TDpccFeature.Hover, E);
    end;
  end;
end;

function TDpccEditorHover.MousePos(const AEditor: TWinControl; AX, AY: Integer; out APos: TDpccHoverMousePos):
  Boolean;
var
  mServices: INTACodeEditorServices;
begin
  APos := Default(TDpccHoverMousePos);
  APos.Editor := AEditor;
  Result := Supports(BorlandIDEServices, INTACodeEditorServices, mServices);
  if Result then
  begin
    APos.State := mServices.EditorState[AEditor];
    Result := (APos.State <> nil) and APos.State.PointToCharacterPos(Point(AX, AY), APos.Column, APos.VisibleLine);
  end;
  if not Result then
  begin
    Exit;
  end;
  APos.View := APos.State.View;
  APos.Line := APos.State.LineState[APos.VisibleLine].LogicalLineNum;
  // Nur, wo dpcc die Code Insight übernimmt; sonst zeigt die IDE ihren Tooltip, und es wären zwei.
  Result := (APos.View <> nil) and (APos.View.Buffer <> nil) and (APos.Line > 0) and
    Handles(APos.View.Buffer.FileName);
  if Result then
  begin
    APos.Text := TDpccEditorBuffer.LineText(APos.View, APos.Line);
    APos.Index := TLspSession.ColumnToIndex(APos.Text, APos.Column, TDpccEditorBuffer.TabWidth(APos.View.Buffer));
  end;
end;

function TDpccEditorHover.WordKey(const APos: TDpccHoverMousePos): string;
var
  mStart, mStop: Integer;
  mFirst, mLast: TRect;
begin
  Result := '';
  if (APos.Index >= Length(APos.Text)) or not TDpccWord.IsIdentifierChar(APos.Text[APos.Index + 1]) or
    CharInSet(APos.Text[TDpccWord.StartBefore(APos.Text, APos.Index + 1) + 1], ['0'..'9']) then
  begin
    Exit;
  end;
  mStart := TDpccWord.StartBefore(APos.Text, APos.Index + 1);
  mStop := TDpccWord.EndAfter(APos.Text, APos.Index);
  Result := Format('%s|%d|%d', [APos.View.Buffer.FileName, APos.Line, mStart]);
  if Result = FKey then
  begin
    Exit;
  end;
  FEditor := APos.Editor;
  FView := APos.View;
  FLine := APos.Line;
  FStart := mStart;
  FDebugExpression := '';
  if TDpccIdeSettings.Current.DebugHoverValues and TDpccIdeDebugValues.Stopped then
  begin
    FDebugExpression := TDpccDebugExpression.At(APos.Text, mStart, mStop);
  end;
  // Wortrechteck aus der ersten und letzten Spalte des Worts (Bildschirmkoordinaten).
  mFirst := APos.State.GetCharacterPosPx(APos.Column - (APos.Index - mStart), APos.VisibleLine);
  mLast := APos.State.GetCharacterPosPx(APos.Column + (mStop - APos.Index - 1), APos.VisibleLine);
  FWordRect := TRect.Create(APos.Editor.ClientToScreen(mFirst.TopLeft), APos.Editor.ClientToScreen(mLast.BottomRight));
end;

procedure TDpccEditorHover.TrackKey(const AKey: string);
begin
  if AKey = '' then
  begin
    // Kein Bezeichner: offenen Tooltip nach 300 ms schließen, wartenden verwerfen.
    FShowTimer.Enabled := False;
    FKey := '';
    FHideTimer.Enabled := FHideTimer.Enabled or FTip.IsShown;
  end
  else if AKey = FShownKey then
  begin
    FHideTimer.Enabled := False;
  end
  else if AKey <> FKey then
  begin
    FKey := AKey;
    FShowTimer.Enabled := False;
    FShowTimer.Enabled := True;
    FHideTimer.Enabled := FHideTimer.Enabled or FTip.IsShown;
  end;
end;

procedure TDpccEditorHover.ReapWorkers(AWait: Boolean);
var
  mIndex: Integer;
begin
  for mIndex := FWorkers.Count - 1 downto 0 do
  begin
    if AWait or FWorkers[mIndex].Finished then
    begin
      FWorkers[mIndex].WaitFor;
      FWorkers[mIndex].Free;
      FWorkers.Delete(mIndex);
    end;
  end;
end;

procedure TDpccEditorHover.ShowTimerTick(Sender: TObject);
var
  mSession: TLspSession;
begin
  // Durch die Sicherung abgeschaltet (#493).
  if TDpccGuard.Disabled(TDpccFeature.Hover) then
  begin
    Exit;
  end;
  FShowTimer.Enabled := False;
  try
    if (FView = nil) or (FKey = '') or not Application.Active then
    begin
      Exit;
    end;
    // Liste der Vervollständigung oder Parameter-Hint offen: kein Tooltip darüber (S3c).
    if OtherPopupOpen then
    begin
      Hide;
      Exit;
    end;
    EvaluateDebugValue;
    mSession := CurrentSession;
    if mSession = nil then
    begin
      // Ohne Server nur der Wert im Debugger (ShowData schließt, wenn es keinen gibt).
      ShowData(Default(TDpccHoverData));
    end
    else
    begin
      RequestHover(mSession);
    end;
  except
    on E: Exception do
    begin
      Log('Hover: ' + E.Message);
      TDpccGuard.Report(TDpccFeature.Hover, E);
    end;
  end;
end;

procedure TDpccEditorHover.RequestHover(ASession: TLspSession);
var
  mText, mFileName, mKey: string;
  mLine, mCharacter, mRequest: Integer;
  mOwner: TDpccEditorHover;
  mAlive: TDpccHoverAlive;
  mAliveRef: IInterface;
  mWorker: TThread;
begin
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mText := TDpccEditorBuffer.Text(FView.Buffer);
  mFileName := FView.Buffer.FileName;
  ASession.Sync(mFileName, mText);
  ReapWorkers(False);
  Inc(FRequest);
  mRequest := FRequest;
  mKey := FKey;
  mLine := FLine - 1;
  mCharacter := FStart;
  mOwner := Self;
  mAlive := FAlive;
  mAliveRef := FAliveRef;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    var
      mData: TDpccHoverData;
      mShow: TThreadProcedure;
    begin
      mData := Default(TDpccHoverData);
      try
        mData := ASession.HoverDataAt(mFileName, mLine, mCharacter, 0);
      except
        // Server langsam oder weg: kein Tooltip, die IDE wartet nie darauf.
        mData := Default(TDpccHoverData);
      end;
      mShow :=
        procedure
        begin
          // Nur die jüngste Anfrage und nur, solange die Maus noch auf demselben Wort steht.
          if not mAlive.Alive or (mAliveRef = nil) or (mOwner.FRequest <> mRequest) or (mOwner.FKey <> mKey) then
          begin
            Exit;
          end;
          TDpccGuard.Run(TDpccFeature.Hover,
            procedure
            begin
              mOwner.ShowData(mData);
            end);
        end;
      // dpcc gehört der Eintrag: beim Entladen verworfen, übersteht aber ReapWorkers.
      TDpccMainThread.Queue(TDpccFeature.Hover, mShow);
    end);
  mWorker.FreeOnTerminate := False;
  FWorkers.Add(mWorker);
  mWorker.Start;
end;

procedure TDpccEditorHover.ShowData(const AData: TDpccHoverData);
begin
  if (FView = nil) or not Application.Active or not MouseOverEditor then
  begin
    Exit;
  end;
  // Ohne Inhalt bzw. wenn inzwischen eine Liste oder ein Parameter-Hint aufgegangen ist (S3c): nichts zeigen.
  if (not AData.Found and not FDebugValue.Visible) or OtherPopupOpen then
  begin
    Hide;
    Exit;
  end;
  ShowTip(AData);
  TDpccKeyHook.Add(FKeys);
  FShownKey := FKey;
  FShown := WindowState;
  FHideTimer.Enabled := False;
  FWatchTimer.Enabled := True;
end;

procedure TDpccEditorHover.ShowTip(const AData: TDpccHoverData);
var
  mData: TDpccHoverData;
begin
  // Anzeige der XMLDoc (#654): Höchstzeilen meldet der Server (hints aus settings.json), sonst die Optionen des
  // Plugins (dieselben Werte, #227). Aufgeklappt ist sie im Tooltip immer (keine Klicks).
  mData := AData;
  if not mData.Display.Known then
  begin
    mData.Display := TDpccDocDisplay.Create(TDpccDocDisplay.ExpandOf(TDpccIdeSettings.Current.XmlDocExpand),
      TDpccIdeSettings.Current.XmlDocMaxLines);
  end;
  FShownData := mData;
  // Aussehen der Code-Insight-Liste der IDE (S3c): Apply setzt Fläche, Namen und Art aus dem Farbschema des Editors
  // (ListColors).
  TDpccIdeStyle.Apply(FTip, FWordRect);
  FTip.ShowHover(mData, FDebugValue, TDpccPlainHover.UnitOfFile(FView.Buffer.FileName), FWordRect);
end;

/// <summary>Sammelt die obersten Fenster des Hauptthreads (EnumThreadWindows).</summary>
function CollectTopWindow(AWindow: HWND; AParam: LPARAM): BOOL; stdcall;
var
  mList: ^TArray<TDpccTopWindow>;
  mName: array[0..63] of Char;
  mRect: TRect;
begin
  mList := Pointer(AParam);
  mName[0] := #0;
  GetClassName(AWindow, mName, Length(mName));
  if not GetWindowRect(AWindow, mRect) then
  begin
    mRect := TRect.Empty;
  end;
  mList^ := mList^ + [TDpccTopWindow.Create(NativeUInt(AWindow), Cardinal(GetWindowLong(AWindow, GWL_STYLE)),
    string(mName), IsWindowVisible(AWindow), mRect)];
  Result := True;
end;

function TDpccEditorHover.OtherPopupOpen: Boolean;
var
  mWindows: TArray<TDpccTopWindow>;
  mArea: TRect;
  mOwn: NativeUInt;
begin
  // Liste der Vervollständigung (IDE oder dpcc), Parameter-Hint, Kontextmenü über dem Editor (S3c).
  Result := False;
  if (FEditor = nil) or not FEditor.HandleAllocated or not GetWindowRect(FEditor.Handle, mArea) then
  begin
    Exit;
  end;
  mWindows := nil;
  EnumThreadWindows(MainThreadID, @CollectTopWindow, LPARAM(@mWindows));
  mOwn := 0;
  if FTip.HandleAllocated then
  begin
    mOwn := NativeUInt(FTip.Handle);
  end;
  Result := TDpccCloseRules.OtherPopup(mWindows, mOwn, mArea);
end;

procedure TDpccEditorHover.EvaluateDebugValue;
var
  mOwner: TDpccEditorHover;
  mKey: string;
  mAlive: TDpccHoverAlive;
  mAliveRef: IInterface;
begin
  FDebug.Cancel;
  FDebugValue := Default(TDpccDebugValue);
  if (FDebugExpression = '') or not TDpccIdeSettings.Current.DebugHoverValues then
  begin
    Exit;
  end;
  mOwner := Self;
  mKey := FKey;
  mAlive := FAlive;
  mAliveRef := FAliveRef;
  // Im Hauptthread: Der Debugger der IDE ist nicht threadsicher. Sofortige Werte stehen gleich im Tooltip.
  FDebugValue := FDebug.Evaluate(FDebugExpression, FView.Buffer.FileName, FLine,
    procedure(const AValue: TDpccDebugValue)
    begin
      if mAlive.Alive and (mAliveRef <> nil) then
      begin
        mOwner.DebugValueDone(mKey, AValue);
      end;
    end);
end;

procedure TDpccEditorHover.DebugValueDone(const AKey: string; const AValue: TDpccDebugValue);
begin
  // Nur für das Wort, auf dem die Maus noch steht; FDebug verwirft ältere Auswertungen ohnehin.
  if AKey <> FKey then
  begin
    Exit;
  end;
  FDebugValue := AValue;
  if not FTip.IsShown or (FShownKey <> AKey) or (FView = nil) then
  begin
    Exit;
  end;
  // Kein Wert (Fehler, weitergelaufen) und sonst nichts zu zeigen: schließen.
  if not FDebugValue.Visible and not FShownData.Found then
  begin
    Hide;
  end
  else
  begin
    ShowTip(FShownData);
  end;
end;

function TDpccEditorHover.WindowState: TDpccEditorWindowState;
var
  mView: IOTAEditView;
begin
  Result := Default(TDpccEditorWindowState);
  Result.AppActive := Application.Active;
  Result.Focus := GetFocus;
  mView := CurrentEditView;
  if mView = nil then
  begin
    Exit;
  end;
  Result.TopRow := mView.TopRow;
  Result.Rows := mView.ViewSize.cy;
  if mView.Buffer <> nil then
  begin
    Result.FileName := mView.Buffer.FileName;
  end;
end;

procedure TDpccEditorHover.WatchTimerTick(Sender: TObject);
begin
  try
    // Andere Anwendung im Vordergrund, anderer Editor-Tab, Fokus woanders in der IDE (Objektinspektor,
    // Projektverwaltung …), gescrollt (#414). Größe und Scrollen melden zusätzlich die Editor-Ereignisse.
    if not FTip.IsShown then
    begin
      FWatchTimer.Enabled := False;
    end
    else if (TDpccCloseRules.Tooltip(FShown, WindowState, False, MouseOverTip) <> TDpccCloseReason.None) or
      OtherPopupOpen then
    begin
      // Auch, wenn eine Liste der Vervollständigung oder ein Parameter-Hint aufgegangen ist (S3c).
      Hide;
    end;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Hover, E);
  end;
end;

procedure TDpccEditorHover.HideTimerTick(Sender: TObject);
begin
  try
    FHideTimer.Enabled := False;
    // Die Maus darf in den Tooltip wandern (#442), etwa um einen langen Kurztext zu lesen; nicht mit Strg (NAV:
    // Die Maus geht dann an den Editor darunter).
    if FTip.IsShown and MouseOverTip and Application.Active and
      not TDpccTooltipMouse.PassThrough(GetKeyState(VK_CONTROL) < 0) then
    begin
      FHideTimer.Enabled := True;
      Exit;
    end;
    Hide;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Hover, E);
  end;
end;

procedure TDpccEditorHover.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  try
    Hide;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Hover, E);
  end;
end;

{$IF CompilerVersion >= 37.0}
procedure TDpccEditorHover.EditorKeyDown(const Editor: TWinControl; Key: Word; Shift: TShiftState;
  var Handled: Boolean);
begin
  try
    // Umschalt, Strg und Alt allein schließen nicht: Strg+Klick auf das Wort darunter braucht sie. Strg aber,
    // wenn die Maus über dem Tooltip steht: Er verdeckt dann das Wort, das der Klick meint (NAV).
    if not TDpccTooltipMouse.KeyCloses(Key, MouseOverTip) then
    begin
      Exit;
    end;
    Hide;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Hover, E);
  end;
end;
{$ENDIF}

procedure TDpccEditorHover.EditorScrolled(const Editor: TWinControl; const Direction: TCodeEditorScrollDirection);
begin
  try
    Hide;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Hover, E);
  end;
end;

procedure TDpccEditorHover.EditorResized(const Editor: TWinControl);
begin
  try
    Hide;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Hover, E);
  end;
end;

end.
