unit dpcc.IDE.Completion.EditorState;

// Vervollständigung im Editor (#410), unterste Stufe: Verträge zur Kompositionswurzel, Zustand der offenen Liste
// und Schließen. Die Klasse ist nach Aufgaben in eine Kette geteilt, damit jede Stufe überschaubar bleibt:
//   TDpccEditorCompletionState (Zustand, Schließen, Tastatur-Hook) → TDpccEditorCompletionOpen (Öffnen,
//   Verzögerung) → TDpccEditorCompletionCommit (Übernehmen, Einträge mit Platzhaltern einsetzen) →
//   TDpccEditorCompletion (dpcc.IDE.Completion.Editor: Tasten, Weitertippen,
//   Vorschau). Aufrufer verwenden nur TDpccEditorCompletion; Beschreibung des Ablaufs dort.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Types,
  Vcl.ExtCtrls,
  ToolsAPI,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Composite,
  dpcc.Core.Completion.Controller,
  dpcc.Core.Completion.Parentheses,
  dpcc.Core.Editor.CloseRules,
  dpcc.Core.Lsp.Session,
  dpcc.IDE.Completion.Preview,
  dpcc.IDE.Completion.Placeholders,
  dpcc.UI.Completion.Popup,
  dpcc.IDE.Foundation.KeyHook;

type
  /// <summary>Protokoll für die Diagnose (Registry-Wert Diagnose).</summary>
  TDpccLogProc = reference to procedure(const AMessage: string);

  /// <summary>Quellen der Vervollständigung aus dem Kern (Server, XMLDoc); setzt die Kompositionswurzel ein.
  /// </summary>
  TDpccCompletionSources = record
    /// <summary>Server; unterstützt auch IDpccCompletionResolver.</summary>
    Server: IDpccCompletionProvider;
    XmlDoc: IDpccCompletionProvider;
    /// <summary>Bricht laufende Anfragen des Servers ab und wartet auf sie.</summary>
    Shutdown: TProc;
  end;

  TDpccCompletionSourcesFactory = reference to function(const ASession: TDpccSessionFunc;
    const ALog: TDpccLogProc): TDpccCompletionSources;

  /// <summary>Verzögertes automatisches Öffnen (ARG-046): Ansicht, Zeile, Zeichen und Fenster beim Auslösen.
  /// </summary>
  TDpccEditorDelay = record
    Timer: TTimer;
    View: IOTAEditView;
    Line: Integer;
    Character: Integer;
    Window: HWND;
    State: TDpccEditorWindowState;
    /// <summary>Invoke kommt gerade aus dem Zeitgeber.</summary>
    Running: Boolean;
  end;

  /// <summary>Zustand der offenen Vervollständigung; Fenster beim Öffnen (Fokus, oberste Zeile, Größe) für
  /// TDpccCloseRules (#414).</summary>
  TDpccEditorOpenState = record
    View: IOTAEditView;
    Window: HWND;
    Line: Integer;
    WordStart: Integer;
    Opened: TDpccEditorWindowState;
  end;

  /// <summary>Commit über ein Zeichen (#429): Ende des Worts (-1 ohne) und Bytes des stehen bleibenden Zeichens.
  /// </summary>
  TDpccEditorCommitChar = record
    WordEnd: Integer;
    SuffixBytes: Integer;
  end;

  /// <summary>Freigabe absichern (#489): Zeile (ab 1) und Datei des zuletzt übernommenen Konstruktors (0 ohne);
  /// NewLine: Das nächste automatische Öffnen kommt vom Enter am Ende dieser Zeile.</summary>
  TDpccEditorGuard = record
    Line: Integer;
    FileName: string;
    NewLine: Boolean;
  end;

  /// <summary>"(" hinter einem Namen (#472): Das nächste automatische Öffnen kommt von dort; Stelle des zuletzt
  /// gefragten "(" (Datei, Zeile ab 1, Zeichen), damit dpcc nicht doppelt fragt.</summary>
  TDpccEditorCall = record
    Opened: Boolean;
    FileName: string;
    Line: Integer;
    Character: Integer;
  end;

  TDpccEditorCompletionState = class
  protected
    FSession: TDpccSessionFunc;
    FProviders: TDpccCompletionProviders;
    FProvidersRef: IDpccCompletionProvider;
    FSources: TDpccCompletionSources;
    FPlaceholders: TDpccEditorPlaceholders;
    FPopup: TDpccCompletionPopup;
    // Automatisch eingefügte ")" nach dem Übernehmen (#430).
    FAutoParen: TDpccAutoParen;
    FOnOpenSignature: TProc;
    // Vorschau des gewählten Eintrags im Editor (#434).
    FPreview: TDpccEditorPreview;
    FController: TDpccCompletionController;
    FTimer: TTimer;
    FDelay: TDpccEditorDelay;
    FKeys: TDpccKeyClient;
    FNotifierIndex: Integer;
    FLog: TDpccLogProc;
    FOpen: TDpccEditorOpenState;
    FCommitChar: TDpccEditorCommitChar;
    FGuard: TDpccEditorGuard;
    FCall: TDpccEditorCall;
    /// <summary>Ereignisse des Popups, die nur Ablauf, Einstellungen und Navigation brauchen.</summary>
    procedure WirePopup;
    procedure Log(const AMessage: string);
    procedure CancelDelay;
    procedure ActiveChanged;
    procedure InstallKeyHook;
    procedure RemoveKeyHook;
    /// <summary>Indiziert der Server gerade (#492)?</summary>
    function IndexingNow: Boolean;
    /// <summary>Zustand für TDpccCloseRules (#414); AWindow ist das Editorfenster mit dem Caret.</summary>
    class function WindowState(const AView: IOTAEditView; AWindow, AFocus: HWND): TDpccEditorWindowState; static;
  public
    /// <summary>ASources legt die Quellen des Kerns an (Kompositionswurzel).</summary>
    constructor Create(const ASession: TDpccSessionFunc; const ALog: TDpccLogProc;
      const ASources: TDpccCompletionSourcesFactory);
    destructor Destroy; override;
    procedure Close;
    /// <summary>Andere Ansicht im Editor: Popup schließen und Platzhalter-Modus beenden.</summary>
    procedure ViewChanged;
    /// <summary>Bricht laufende Serveranfragen ab und wartet auf sie; vor dem Freigeben der Sitzung.</summary>
    procedure Shutdown;
    function Visible: Boolean;
    /// <summary>Läuft gerade der Platzhalter-Modus eines Eintrags (#51)?</summary>
    function PlaceholdersActive: Boolean;
    /// <summary>Wurde in der Zeile des Cursors gerade ein Konstruktor übernommen (#489)? Dann fragt ";" dort
    /// nach „Mit try…finally absichern“.</summary>
    function GuardPending(const AView: IOTAEditView): Boolean;
    /// <summary>Hat Enter die Zeile des übernommenen Konstruktors gerade beendet (#489)? Der Cursor steht dann
    /// in einer leeren Zeile direkt darunter.</summary>
    function GuardNewLine(const AView: IOTAEditView): Boolean;
    /// <summary>Nach dem Übernehmen mit Klammern den Parameter-Hint öffnen (#430).</summary>
    property OnOpenSignature: TProc read FOnOpenSignature write FOnOpenSignature;
  end;

implementation

uses
  System.Math,
  Vcl.Forms,
  dpcc.Core.Settings.Plugin,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Foundation.Navigation,
  dpcc.IDE.Foundation.EditorBuffer;

const
  /// <summary>Takt, in dem die offene Liste Cursor und Vorschau prüft.</summary>
  cTickMs = 50;

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

/// <summary>Gezogene Breite der Liste (#416) gilt auch beim nächsten Mal.</summary>
procedure WireSettings(APopup: TDpccCompletionPopup);
begin
  APopup.OnWidthChanged :=
    procedure(AListWidth: Integer)
    var
      mSettings: TDpccPluginSettings;
    begin
      mSettings := TDpccIdeSettings.Stored;
      mSettings.ListWidth := AListWidth;
      TDpccIdeSettings.Update(mSettings);
    end;
end;

{ TDpccEditorCompletionState }

constructor TDpccEditorCompletionState.Create(const ASession: TDpccSessionFunc; const ALog: TDpccLogProc;
  const ASources: TDpccCompletionSourcesFactory);
begin
  inherited Create;
  FSession := ASession;
  FLog := ALog;
  FNotifierIndex := -1;
  FCommitChar.WordEnd := -1;
  FProviders := TDpccCompletionProviders.Create;
  FProvidersRef := FProviders;
  FSources := ASources(ASession,
    procedure(const AMessage: string)
    begin
      Log(AMessage);
    end);
  FProviders.Add(FSources.Server);
  // XMLDoc-Tags in ///-Kommentaren (#435), lokal.
  FProviders.Add(FSources.XmlDoc);
  FPlaceholders := TDpccEditorPlaceholders.Create;
  FPopup := TDpccCompletionPopup.Create(nil);
  FController := TDpccCompletionController.Create(FProvidersRef, FPopup);
  WirePopup;
  FPreview := TDpccEditorPreview.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cTickMs;
  FDelay.Timer := TTimer.Create(nil);
  FDelay.Timer.Enabled := False;
end;

destructor TDpccEditorCompletionState.Destroy;
begin
  // Erst schließen und Anfragen beenden, solange Zeitgeber und Vorschau noch bestehen; dann freigeben.
  Shutdown;
  RemoveKeyHook;
  FreeAndNil(FPlaceholders);
  FreeAndNil(FPreview);
  FTimer.Free;
  FDelay.Timer.Free;
  FController.Free;
  FPopup.Free;
  FKeys.Free;
  FSources := Default(TDpccCompletionSources);
  FProvidersRef := nil;
  inherited;
end;

procedure TDpccEditorCompletionState.WirePopup;
begin
  FPopup.OnSelect :=
    procedure(APosition: Integer)
    begin
      FController.Select(APosition);
    end;
  // Zeilenangabe der Warnleiste (#457): Liste schließen, Caret an den Fehler.
  FPopup.OnSyntaxLine :=
    procedure(ALine, ACharacter: Integer)
    begin
      Close;
      TDpccIdeNavigation.GoToPosition(ALine, Max(0, ACharacter));
    end;
  FPopup.OnAccept :=
    procedure(APosition: Integer)
    begin
      FController.Select(APosition);
      FController.CommitSelected;
    end;
  WireSettings(FPopup);
end;

class function TDpccEditorCompletionState.WindowState(const AView: IOTAEditView; AWindow,
  AFocus: HWND): TDpccEditorWindowState;
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

procedure TDpccEditorCompletionState.Log(const AMessage: string);
begin
  if Assigned(FLog) then
  begin
    FLog(AMessage);
  end;
end;

procedure TDpccEditorCompletionState.Shutdown;
begin
  Close;
  if Assigned(FSources.Shutdown) then
  begin
    FSources.Shutdown();
  end;
end;

function TDpccEditorCompletionState.IndexingNow: Boolean;
var
  mSession: TLspSession;
begin
  Result := False;
  if not Assigned(FSession) then
  begin
    Exit;
  end;
  mSession := FSession();
  Result := (mSession <> nil) and (mSession.IndexingText <> '');
end;

function TDpccEditorCompletionState.PlaceholdersActive: Boolean;
begin
  Result := (FPlaceholders <> nil) and FPlaceholders.Active;
end;

function TDpccEditorCompletionState.Visible: Boolean;
begin
  // Auch der leere Zustand (#423) nimmt Esc entgegen.
  Result := FController.Visible or FController.Empty;
end;

procedure TDpccEditorCompletionState.CancelDelay;
begin
  FDelay.Timer.Enabled := False;
  FDelay.View := nil;
end;

procedure TDpccEditorCompletionState.Close;
begin
  CancelDelay;
  FController.Close;
  if FPreview <> nil then
  begin
    FPreview.Clear;
  end;
  ActiveChanged;
end;

procedure TDpccEditorCompletionState.ViewChanged;
begin
  Close;
  if FPlaceholders <> nil then
  begin
    FPlaceholders.Stop;
  end;
end;

procedure TDpccEditorCompletionState.ActiveChanged;
begin
  FTimer.Enabled := FController.Active;
  if not FController.Active and (FPreview <> nil) then
  begin
    FPreview.Clear;
  end;
  if FController.Active then
  begin
    InstallKeyHook;
  end
  else
  begin
    RemoveKeyHook;
    FOpen.View := nil;
  end;
end;

procedure TDpccEditorCompletionState.InstallKeyHook;
begin
  TDpccKeyHook.Add(FKeys);
  if not TDpccKeyHook.Installed then
  begin
    Log('Vervollständigung: Tastatur-Hook nicht möglich: ' + SysErrorMessage(GetLastError));
  end;
end;

procedure TDpccEditorCompletionState.RemoveKeyHook;
begin
  TDpccKeyHook.Remove(FKeys);
end;

function TDpccEditorCompletionState.GuardNewLine(const AView: IOTAEditView): Boolean;
begin
  Result := (FGuard.Line > 0) and (AView <> nil) and (AView.Buffer <> nil) and
    (AView.CursorPos.Line = FGuard.Line + 1) and SameText(AView.Buffer.FileName, FGuard.FileName) and
    (Trim(TDpccEditorBuffer.LineText(AView, AView.CursorPos.Line)) = '') and
    not TDpccEditorBuffer.LineText(AView, FGuard.Line).TrimRight.EndsWith(';');
end;

function TDpccEditorCompletionState.GuardPending(const AView: IOTAEditView): Boolean;
begin
  Result := (FGuard.Line > 0) and (AView <> nil) and (AView.Buffer <> nil) and
    (AView.CursorPos.Line = FGuard.Line) and SameText(AView.Buffer.FileName, FGuard.FileName);
end;

end.
