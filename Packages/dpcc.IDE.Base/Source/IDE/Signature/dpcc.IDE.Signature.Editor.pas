unit dpcc.IDE.Signature.Editor;

// Parameter-Hint im Editor der IDE (#436, #437, #440): verbindet die Signaturen
// des Servers, den Ablauf (TDpccSignatureController) und das Hint-Fenster mit
// dem Editor. Der Code Insight-Manager ruft Invoke bei "(", "," und
// Strg+Umschalt+Leer statt der eingebauten Parameterhilfe.
//   - Start: Aufruf am Caret lokal suchen (TDpccCallScanner), Signaturen beim
//     Server anfragen, Hint an der öffnenden Klammer zeigen.
//   - Weitertippen: EditorViewModified und ein Zeitgeber zählen den aktiven
//     Parameter lokal neu; der Hint wechselt bei Bedarf die Überladung.
//   - Verschachtelt (#438): Pfadzeile mit den äußeren Aufrufen; verlässt der Caret
//     den inneren Aufruf nach vorn (Klammer davor), zeigt der Hint den äußeren.
//   - Schließen (#414): Caret verlässt den Aufruf (auch durch ")"), Esc,
//     Fokusverlust, IDE inaktiv, Scrollen, Tab-Wechsel.
//   - Wieder öffnen: Wird die schließende Klammer entfernt (Rücktaste, Entf) und
//     steht der Caret danach in einem Aufruf, erscheint der Hint erneut; nicht für
//     einen Aufruf, dessen Hint mit Esc geschlossen wurde. Dazu merkt sich jede
//     Änderung die Zeile vorher.
//   - Alle Überladungen stehen untereinander; Klick wählt eine. Tasten über den
//     gemeinsamen Hook: Esc schließt, Strg+Alt+↑/↓ wechselt die gewählte Überladung
//     (NAV, TDpccOverloadKeys; bis dahin Alt+↑/↓, das in der IDE „Deklaration suchen“ ist);
//     nach der Vervollständigung, die Esc zuerst bekommt.
//   - Platzhalter (#451): Bei Format und anderen Formatroutinen zeigt der Hint, welchen Platzhalter der Eintrag
//     am Cursor füllt, und TDpccIdeFormatMarks färbt Platzhalter und Argumente im Editor. Ändern sich Text oder
//     Cursor, fragt der Zeitgeber nach kurzer Ruhe neu; UpdateFormat übernimmt nur die neue Zuordnung.
//     Abschaltbar mit completion.formatPlaceholders.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.ExtCtrls,
  ToolsAPI,
  dpcc.Core.Signature.Contract,
  dpcc.Core.Signature.Controller,
  dpcc.UI.Signature.Hint,
  dpcc.Core.Editor.CloseRules,
  dpcc.Core.Editor.Navigation,
  dpcc.IDE.Foundation.KeyHook,
  dpcc.IDE.Signature.FormatMarks;

type
  TDpccLogFunc = reference to procedure(const AMessage: string);
  /// <summary>Ist das Vervollständigungs-Popup offen? Dann steht der Hint über der Zeile (#440).</summary>
  TDpccBoolFunc = reference to function: Boolean;

  /// <summary>Zeile vor der letzten Änderung (Wieder öffnen nach entfernter „)“).</summary>
  TDpccSignatureLastLine = record
    FileName: string;
    Line: Integer;
    Text: string;
  end;

  /// <summary>Mit Esc geschlossener Aufruf.</summary>
  TDpccSignatureDismissed = record
    FileName: string;
    OpenParen: Integer;
  end;

  /// <summary>Stand der letzten Platzhalter-Anfrage (#451): Text, Cursor und Takte bis zur nächsten.</summary>
  TDpccSignatureFormatState = record
    Text: string;
    Caret: Integer;
    Due: Integer;
  end;

  TDpccEditorSignature = class
  private const
    /// <summary>Takte ohne Änderung, bis die Platzhalter neu angefragt werden (#451).</summary>
    cFormatQuietTicks = 3;
  private
    FProvider: IDpccSignatureSource;
    FHint: TDpccSignatureHint;
    FController: TDpccSignatureController;
    FTimer: TTimer;
    FKeys: TDpccKeyClient;
    FLog: TDpccLogFunc;
    FCompletionOpen: TDpccBoolFunc;
    FNotifierIndex: Integer;
    // Zustand des offenen Hints.
    FView: IOTAEditView;
    FEditorWindow: HWND;
    FOpenParen: Integer;
    // Fenster beim Öffnen bzw. nach dem letzten Mitwandern; TDpccCloseRules vergleicht damit (#414).
    FOpened: TDpccEditorWindowState;
    /// <summary>Zeile (ab 1), an der der Hint hängt: Caret-Zeile beim Öffnen.</summary>
    FAnchorLine: Integer;
    FPending: Boolean;
    FLast: TDpccSignatureLastLine;
    FDismissed: TDpccSignatureDismissed;
    // Platzhalter (#451): Färbung und Stand der letzten Anfrage.
    FMarks: TDpccIdeFormatMarks;
    FFormat: TDpccSignatureFormatState;
    procedure ShowFormat(const AFormat: TDpccSignatureFormat; const AText: string);
    procedure CheckFormat(const AText: string; ALine, ACharacter, ACaret: Integer);
    procedure Reopen(const AView: IOTAEditView);
    /// <summary>Antwort des Servers auf die Anfrage aus Invoke; AText: Text zur Zeit der Anfrage.</summary>
    procedure HelpArrived(const AHelp: TDpccSignatureHelp; const AText: string);
    procedure Log(const AMessage: string);
    procedure TimerTick(Sender: TObject);
    procedure Recheck;
    procedure ApplyStyle(const ACaret: TRect);
    procedure ActiveChanged;
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleKey(AKey: Word);
  public
    /// <summary>ASource: Server-Anbieter, eingesetzt von der Kompositionswurzel.</summary>
    constructor Create(const ASource: IDpccSignatureSource; const ACompletionOpen: TDpccBoolFunc;
      const ALog: TDpccLogFunc);
    destructor Destroy; override;
    /// <summary>Öffnet den Hint für den Aufruf am Cursor von AView; False ohne Aufruf.</summary>
    function Invoke(const AView: IOTAEditView): Boolean;
    procedure Close;
    procedure EditorModified(const AView: IOTAEditView);
    /// <summary>Bricht laufende Serveranfragen ab, ohne zu warten; vor dem Freigeben der Sitzung (gewartet wird im
    /// Stopp-Thread der Sitzung).</summary>
    procedure Shutdown;
    function Active: Boolean;
  end;

implementation

uses
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Lsp.Client,
  Vcl.Forms,
  DockForm,
  dpcc.Core.Signature.CallScanner,
  dpcc.Core.Signature.Format,
  dpcc.IDE.Foundation.EditorBuffer,
  dpcc.IDE.Foundation.EditorStyle,
  dpcc.IDE.Foundation.Settings,
  dpcc.Core.Settings.CompletionView,
  dpcc.Core.Lsp.Session;

/// <summary>Größe des Editorfensters (Client-Bereich); (0, 0) ohne Fenster.</summary>
function EditorSize(AWindow: HWND): TPoint;
var
  mArea: TRect;
begin
  if (AWindow <> 0) and GetClientRect(AWindow, mArea) then
  begin
    Result := Point(mArea.Width, mArea.Height);
  end
  else
  begin
    Result := Point(0, 0);
  end;
end;

/// <summary>Zustand für TDpccCloseRules (#414).</summary>
function WindowState(const AView: IOTAEditView; AWindow, AFocus: HWND): TDpccEditorWindowState;
begin
  Result := Default(TDpccEditorWindowState);
  Result.AppActive := Application.Active;
  Result.Focus := AFocus;
  Result.Size := EditorSize(AWindow);
  if AView = nil then
  begin
    Exit;
  end;
  Result.TopRow := AView.TopRow;
  Result.Rows := AView.ViewSize.cy;
  if AView.Buffer <> nil then
  begin
    Result.FileName := AView.Buffer.FileName;
  end;
end;

type
  /// <summary>Cursor eines Editors: Text, Zeile (ab 1), Zeichen in der Zeile und Offset im Text.</summary>
  TCursorSpot = record
    Text: string;
    Line: Integer;
    Character: Integer;
    Caret: Integer;
  end;

function CursorSpot(const AView: IOTAEditView): TCursorSpot;
var
  mCursor: TOTAEditPos;
begin
  Result.Text := TDpccEditorBuffer.Text(AView.Buffer);
  mCursor := AView.CursorPos;
  Result.Line := mCursor.Line;
  Result.Character := TLspSession.ColumnToIndex(TDpccEditorBuffer.LineText(AView, mCursor.Line), mCursor.Col,
    TDpccEditorBuffer.TabWidth(AView.Buffer));
  Result.Caret := TDpccEditorBuffer.CharOffset(Result.Text, mCursor.Line - 1, Result.Character);
end;

/// <summary>Fenster und Rechteck des Carets (Bildschirmkoordinaten); False ohne Caret.</summary>
function CaretAnchor(out AWindow: HWND; out AAnchor: TRect): Boolean;
var
  mInfo: TGUIThreadInfo;
begin
  FillChar(mInfo, SizeOf(mInfo), 0);
  mInfo.cbSize := SizeOf(mInfo);
  Result := GetGUIThreadInfo(GetCurrentThreadId, mInfo) and (mInfo.hwndCaret <> 0);
  AWindow := mInfo.hwndCaret;
  AAnchor := mInfo.rcCaret;
  if Result then
  begin
    MapWindowPoints(AWindow, 0, AAnchor, 2);
  end;
end;

type
  TSignatureKeys = class(TDpccKeyClient)
  private
    FOwner: TDpccEditorSignature;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  public
    constructor Create(AOwner: TDpccEditorSignature);
  end;

  TSignatureNotifier = class(TNotifierObject, INTAEditServicesNotifier)
  private
    FOwner: TDpccEditorSignature;
  public
    constructor Create(AOwner: TDpccEditorSignature);
    procedure WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
    procedure WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
    procedure WindowActivated(const EditWindow: INTAEditWindow);
    procedure WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean);
    procedure EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
  end;

{ TSignatureKeys }

constructor TSignatureKeys.Create(AOwner: TDpccEditorSignature);
begin
  // Nach der Vervollständigung (Priorität 0): Esc schließt zuerst deren Popup.
  inherited Create(10);
  FOwner := AOwner;
end;

function TSignatureKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := FOwner.WantsKey(AKey, AShift);
end;

procedure TSignatureKeys.HandleKey(AKey: Word; AShift: TShiftState);
begin
  try
    FOwner.HandleKey(AKey);
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Signature, E);
  end;
end;

{ TSignatureNotifier }

constructor TSignatureNotifier.Create(AOwner: TDpccEditorSignature);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TSignatureNotifier.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
end;

procedure TSignatureNotifier.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
end;

procedure TSignatureNotifier.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TSignatureNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TSignatureNotifier.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  try
    FOwner.Close;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Signature, E);
  end;
end;

procedure TSignatureNotifier.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  try
    FOwner.EditorModified(EditView);
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Signature, E);
  end;
end;

procedure TSignatureNotifier.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TSignatureNotifier.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TSignatureNotifier.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TDpccEditorSignature }

constructor TDpccEditorSignature.Create(const ASource: IDpccSignatureSource; const ACompletionOpen: TDpccBoolFunc;
  const ALog: TDpccLogFunc);
var
  mEditor: IOTAEditorServices;
  mNotifier: INTAEditServicesNotifier;
begin
  inherited Create;
  FLog := ALog;
  FCompletionOpen := ACompletionOpen;
  FNotifierIndex := -1;
  FOpenParen := -1;
  FLast.Line := -1;
  FDismissed.OpenParen := -1;
  FFormat.Caret := -1;
  FProvider := ASource;
  FMarks := TDpccIdeFormatMarks.Create;
  FHint := TDpccSignatureHint.Create(nil);
  FController := TDpccSignatureController.Create(FHint);
  FHint.OnSelect :=
    procedure(AIndex: Integer)
    begin
      FController.SelectOverload(AIndex);
    end;
  FKeys := TSignatureKeys.Create(Self);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := 50;
  FTimer.OnTimer := TimerTick;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    mNotifier := TSignatureNotifier.Create(Self);
    FNotifierIndex := mEditor.AddNotifier(mNotifier);
  end;
end;

destructor TDpccEditorSignature.Destroy;
var
  mEditor: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  TDpccKeyHook.Remove(FKeys);
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    mEditor.RemoveNotifier(FNotifierIndex);
  end;
  FTimer.Free;
  Shutdown;
  FController.Free;
  FHint.Free;
  FMarks.Free;
  FProvider := nil;
  FKeys.Free;
  inherited;
end;

procedure TDpccEditorSignature.Log(const AMessage: string);
begin
  if Assigned(FLog) then
  begin
    FLog(AMessage);
  end;
end;

procedure TDpccEditorSignature.Shutdown;
begin
  Close;
  FProvider.Shutdown;
end;

function TDpccEditorSignature.Active: Boolean;
begin
  Result := FController.Active or FPending;
end;

procedure TDpccEditorSignature.ApplyStyle(const ACaret: TRect);
begin
  TDpccIdeStyle.Apply(FHint, ACaret);
end;

function TDpccEditorSignature.Invoke(const AView: IOTAEditView): Boolean;
var
  mSpot: TCursorSpot;
  mSite: TDpccCallSite;
  mWindow: HWND;
  mAnchor: TRect;
begin
  Result := False;
  // Parameter-Hint abgeschaltet (ARG-046): weder bei "(" und "," noch nach dem Übernehmen.
  if (AView = nil) or (AView.Buffer = nil) or not TDpccIdeSettings.Current.ParameterHints then
  begin
    Exit;
  end;
  mSpot := CursorSpot(AView);
  mSite := TDpccCallScanner.Scan(mSpot.Text, mSpot.Caret);
  if not mSite.Found then
  begin
    Close;
    Exit;
  end;
  // Schon offen für denselben Aufruf (z. B. "," gleich nach "("): nur den Parameter nachziehen.
  if FController.Active and (mSite.OpenParen = FOpenParen) and (AView = FView) then
  begin
    FController.UpdateParameter(mSite.ActiveParameter);
    Exit(True);
  end;
  if not CaretAnchor(mWindow, mAnchor) then
  begin
    Exit;
  end;
  ApplyStyle(mAnchor);
  // Linke Kante an der öffnenden Klammer, wenn sie in derselben Zeile vor dem Caret steht.
  FHint.Canvas.Font := FHint.Font;
  if mSpot.Caret - mSite.OpenParen <= mSpot.Character then
  begin
    mAnchor.Left := mAnchor.Left - FHint.Canvas.TextWidth(Copy(mSpot.Text, mSite.OpenParen + 1,
      mSpot.Caret - mSite.OpenParen));
  end;
  FHint.Anchor := mAnchor;
  FHint.Above := Assigned(FCompletionOpen) and FCompletionOpen();
  // Platzhalter von Format zuordnen und einfärben (#451): fest an seit OPT1.
  FHint.FormatPlaceholders := TDpccFixedSettings.cFormatPlaceholders;
  FController.Close;
  FDismissed.OpenParen := -1;
  FFormat.Text := mSpot.Text;
  FFormat.Caret := mSpot.Caret;
  FFormat.Due := 0;
  FView := AView;
  FEditorWindow := mWindow;
  FOpenParen := mSite.OpenParen;
  FOpened := WindowState(AView, FEditorWindow, FEditorWindow);
  FAnchorLine := mSpot.Line;
  FPending := FProvider.Query(AView.Buffer.FileName, mSpot.Text, mSpot.Line - 1, mSpot.Character,
    procedure(const AHelp: TDpccSignatureHelp)
    begin
      HelpArrived(AHelp, mSpot.Text);
    end);
  ActiveChanged;
  Result := FPending;
end;

procedure TDpccEditorSignature.HelpArrived(const AHelp: TDpccSignatureHelp; const AText: string);
var
  mCurrent: TDpccCallSite;
  mSpot: TCursorSpot;
begin
  FPending := False;
  if FView = nil then
  begin
    Exit;
  end;
  // Seit der Anfrage weitergetippt: Parameter lokal neu zählen.
  mSpot := CursorSpot(FView);
  mCurrent := TDpccCallScanner.Scan(mSpot.Text, mSpot.Caret);
  if not mCurrent.Found or (mCurrent.OpenParen <> FOpenParen) then
  begin
    Close;
    Exit;
  end;
  FHint.Above := Assigned(FCompletionOpen) and FCompletionOpen();
  FHint.SetPath(mCurrent.Outer, mCurrent.Name);
  FController.Show(AHelp, mCurrent.ActiveParameter);
  ShowFormat(AHelp.Format, AText);
  Log(Format('Parameter-Hint: %d Signaturen, Parameter %d', [Length(AHelp.Signatures), mCurrent.ActiveParameter]));
  ActiveChanged;
end;

procedure TDpccEditorSignature.Close;
begin
  FPending := False;
  FProvider.Cancel;
  FController.Close;
  FMarks.Clear;
  FFormat.Text := '';
  FFormat.Caret := -1;
  FFormat.Due := 0;
  ActiveChanged;
end;

procedure TDpccEditorSignature.ShowFormat(const AFormat: TDpccSignatureFormat; const AText: string);
begin
  if FHint.FormatPlaceholders and AFormat.Found and (FView <> nil) and (FView.Buffer <> nil) then
  begin
    FMarks.Show(FView.Buffer.FileName, AText, TDpccEditorBuffer.TabWidth(FView.Buffer),
      TDpccSignatureFormats.Marks(AFormat));
  end
  else
  begin
    FMarks.Clear;
  end;
end;

procedure TDpccEditorSignature.CheckFormat(const AText: string; ALine, ACharacter, ACaret: Integer);
var
  mText: string;
begin
  if FPending or not FHint.FormatPlaceholders or not FController.Help.Format.Found or (FView = nil) then
  begin
    Exit;
  end;
  // Erst nach kurzer Ruhe: Jede Anfrage gleicht den Puffer mit dem Server ab.
  if (ACaret <> FFormat.Caret) or (AText <> FFormat.Text) then
  begin
    FFormat.Text := AText;
    FFormat.Caret := ACaret;
    FFormat.Due := cFormatQuietTicks;
    Exit;
  end;
  if FFormat.Due <= 0 then
  begin
    Exit;
  end;
  Dec(FFormat.Due);
  if FFormat.Due > 0 then
  begin
    Exit;
  end;
  mText := AText;
  FProvider.Query(FView.Buffer.FileName, mText, ALine, ACharacter,
    procedure(const AHelp: TDpccSignatureHelp)
    begin
      // Inzwischen geschlossen oder weitergetippt: Der nächste Takt fragt neu.
      if (FView = nil) or not FController.Active or (mText <> FFormat.Text) then
      begin
        Exit;
      end;
      FController.UpdateFormat(AHelp.Format);
      ShowFormat(AHelp.Format, mText);
    end);
end;

procedure TDpccEditorSignature.ActiveChanged;
begin
  FTimer.Enabled := Active;
  if FController.Active then
  begin
    TDpccKeyHook.Add(FKeys);
  end
  else
  begin
    TDpccKeyHook.Remove(FKeys);
  end;
  if not Active then
  begin
    FView := nil;
    FOpenParen := -1;
  end;
end;

procedure TDpccEditorSignature.EditorModified(const AView: IOTAEditView);
var
  mFileName, mLineText: string;
  mLine: Integer;
  mRemoved: Boolean;
begin
  if Active then
  begin
    Recheck;
  end;
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  mFileName := AView.Buffer.FileName;
  mLine := AView.CursorPos.Line;
  mLineText := TDpccEditorBuffer.LineText(AView, mLine);
  mRemoved := not Active and SameText(mFileName, FLast.FileName) and (mLine = FLast.Line) and
    TDpccCallScanner.RemovedClosingParen(FLast.Text, mLineText);
  FLast.FileName := mFileName;
  FLast.Line := mLine;
  FLast.Text := mLineText;
  if not mRemoved then
  begin
    Exit;
  end;
  // Erst nach der Änderung, wenn die IDE den Caret gesetzt hat.
  TDpccMainThread.ForceQueue(TDpccFeature.Signature,
    procedure
    begin
      try
        Reopen(AView);
      except
        on E: Exception do
        begin
          Log('Parameter-Hint: ' + E.Message);
          // Server weg oder Zeitlimit ist erwartbar; anderes zählt die Sicherung.
          if not (E is ELspClientError) then
          begin
            TDpccGuard.Report(TDpccFeature.Signature, E);
          end;
        end;
      end;
    end);
end;

procedure TDpccEditorSignature.Reopen(const AView: IOTAEditView);
var
  mSpot: TCursorSpot;
  mSite: TDpccCallSite;
begin
  if Active or (AView = nil) or (AView.Buffer = nil) or not Application.Active then
  begin
    Exit;
  end;
  mSpot := CursorSpot(AView);
  mSite := TDpccCallScanner.Scan(mSpot.Text, mSpot.Caret);
  if not mSite.Found or ((mSite.OpenParen = FDismissed.OpenParen) and
    SameText(AView.Buffer.FileName, FDismissed.FileName)) then
  begin
    Exit;
  end;
  Log('Parameter-Hint: nach entfernter Klammer wieder geöffnet');
  Invoke(AView);
end;

procedure TDpccEditorSignature.TimerTick(Sender: TObject);
begin
  try
    Recheck;
  except
    on E: Exception do
    begin
      Log('Parameter-Hint: ' + E.Message);
      TDpccGuard.Report(TDpccFeature.Signature, E);
      Close;
    end;
  end;
end;

procedure TDpccEditorSignature.Recheck;
var
  mAnchor: TRect;
  mSpot: TCursorSpot;
  mSite: TDpccCallSite;
  mView: IOTAEditView;
  mNow: TDpccEditorWindowState;
  mMove: Boolean;
begin
  if not Active or (FView = nil) then
  begin
    ActiveChanged;
    Exit;
  end;
  // IDE inaktiv, Fokus woanders, Größe geändert, Ankerzeile außer Sicht: schließen (#414).
  mNow := WindowState(FView, FEditorWindow, GetFocus);
  if TDpccCloseRules.Hint(FOpened, mNow, FAnchorLine, mMove) <> TDpccCloseReason.None then
  begin
    Close;
    Exit;
  end;
  // Gescrollt: mitwandern, solange die Ankerzeile sichtbar ist.
  if mMove then
  begin
    mAnchor := FHint.Anchor;
    mAnchor.Offset(0, (FOpened.TopRow - mNow.TopRow) * mAnchor.Height);
    FHint.MoveTo(mAnchor);
    FOpened.TopRow := mNow.TopRow;
  end;
  mSpot := CursorSpot(FView);
  mSite := TDpccCallScanner.Scan(mSpot.Text, mSpot.Caret);
  // Aufruf verlassen (auch durch ")") oder in einen anderen gewechselt.
  if not mSite.Found or (mSite.OpenParen > FOpenParen) then
  begin
    Close;
    Exit;
  end;
  // Inneren Aufruf verlassen: wieder den äußeren zeigen (#438).
  if mSite.OpenParen < FOpenParen then
  begin
    mView := FView;
    Close;
    Invoke(mView);
    Exit;
  end;
  if FController.Active then
  begin
    FHint.Above := Assigned(FCompletionOpen) and FCompletionOpen();
    FController.UpdateParameter(mSite.ActiveParameter);
    CheckFormat(mSpot.Text, mSpot.Line - 1, mSpot.Character, mSpot.Caret);
  end;
end;

function TDpccEditorSignature.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  // Alt+↑/↓ bleibt bei der IDE („Deklaration suchen“, NAV); die Überladung wechselt mit Strg+Alt+↑/↓.
  Result := FController.Active and
    (((AKey = VK_ESCAPE) and (AShift = [])) or
     (TDpccOverloadKeys.Step(AKey, AShift, Length(FController.Help.Signatures)) <> 0));
end;

procedure TDpccEditorSignature.HandleKey(AKey: Word);
begin
  case AKey of
    VK_ESCAPE:
      begin
        // Für diesen Aufruf nicht von selbst wieder öffnen.
        if FView <> nil then
        begin
          FDismissed.FileName := FView.Buffer.FileName;
        end;
        FDismissed.OpenParen := FOpenParen;
        Close;
      end;
    VK_UP:
      FController.PreviousOverload;
    VK_DOWN:
      FController.NextOverload;
  end;
end;

end.
