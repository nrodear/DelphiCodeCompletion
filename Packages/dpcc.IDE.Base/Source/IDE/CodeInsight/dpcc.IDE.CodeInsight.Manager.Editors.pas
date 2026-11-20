unit dpcc.IDE.CodeInsight.Manager.Editors;

// Anbindungen des Code Insight-Managers an den Editor: Vervollständigung im eigenen Popup (#410), Parameter-Hint
// (#436) und eigener Hover-Tooltip (#442). Sie fragen die Sitzung über die Haken des Managers; abgebaut wird in der
// Reihenfolge, die DetachSession und Shutdown brauchen. Probleme, Inlay-Hints und Code Lens gibt es seit Rückbau R6
// nicht mehr. Stopp der Sitzung: BeginStop bricht nur ab und wartet nicht im Hauptthread; auf die Arbeiter wartet
// der Stopp-Thread der Sitzung (dpcc.IDE.CodeInsight.Manager.Session, StopWork).
// Tippen (L5, completion.autoMinChars): Die Vervollständigung entsteht sonst erst beim ersten Strg+Leertaste. Damit
// das Öffnen beim Tippen von Anfang an wirkt, beobachtet ein kleiner Editor-Beobachter die Änderungen, bis sie
// existiert: Beim ersten Tippen in einer Datei, die dpcc bedient, legt er sie gleich nach der Benachrichtigung an und
// merkt sich den Stand der Zeile; ab dann übernimmt ihr eigener Beobachter.
// Vorladen beim Öffnen und Aktivieren (dpcc/prewarm): Derselbe Beobachter (er lebt bis ReleaseViews) meldet jede
// aktive Ansicht. Bedient dpcc die Datei, wartet TDpccPrewarmGate cQuietMs Ruhe ab (schnelles Durchblättern der Tabs
// löst nichts aus); ist sie dann noch vorn und die Sitzung bereit (nie ein Start), liest der Hauptthread den Puffer
// über den gemeinsamen Pufferstand (TDpccEditorSnapshots, nur wenn er als veraltet gilt) und stößt je Datei und Stand
// höchstens einmal einen Arbeiter aus TDpccTimeLimit an (Post, ohne Warten). Der gleicht ab (Session.Prewarm: Diff
// bzw. didOpen samt JSON, dann dpcc/prewarm); den Rest lädt der Server im Hintergrund. Der Arbeiter hält nur Kopien
// und die Sitzung als rohen Zeiger wie der Abgleich der Formulare; der Stopp wartet auf ihn (TDpccTimeLimit.WaitIdle).
// Hauptschalter aus, Stopp und Entladen verwerfen eine wartende Aktivierung; danach geht nichts mehr hinaus.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  ToolsAPI,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Editor.Prewarm,
  dpcc.Core.Signature.Contract,
  dpcc.IDE.Completion.Editor,
  dpcc.IDE.Signature.Editor,
  dpcc.IDE.Hover.Editor;

type
  /// <summary>Was die Anbindungen vom Manager brauchen.</summary>
  TDpccCodeInsightEditorHooks = record
    /// <summary>Laufende Sitzung; sonst stößt der Hauptthread den Start im Hintergrund an und bekommt False (wartet
    /// nie). Außerhalb des Hauptthreads nur, was schon läuft.</summary>
    EnsureSession: TFunc<Boolean>;
    /// <summary>Laufende Sitzung oder nil, nie während DetachSession; startet keinen Server.</summary>
    RunningSession: TFunc<TLspSession>;
    /// <summary>Server läuft und Sitzung initialisiert; startet keinen Server.</summary>
    ReadySession: TFunc<TLspSession>;
    Diagnose: TProc<string>;
    /// <summary>Bedient dpcc diese Datei?</summary>
    Handles: TFunc<string, Boolean>;
    /// <summary>Editoransicht, in der Code Insight gerade läuft.</summary>
    EditView: TFunc<IOTAEditView>;
    /// <summary>Ist die Liste der IDE gerade offen (L4)? Dann öffnet Tippen keine Liste von dpcc (L5).</summary>
    IdeListOpen: TFunc<Boolean>;
    NewCompletionSources: TDpccCompletionSourcesFactory;
    NewSignatureSource: TFunc<TDpccSessionFunc, IDpccSignatureSource>;
  end;

  /// <summary>Editor-Anbindungen des Managers.</summary>
  TDpccCodeInsightEditors = class
  private
    FHooks: TDpccCodeInsightEditorHooks;
    FCompletion: TDpccEditorCompletion;
    FSignature: TDpccEditorSignature;
    FHover: TDpccEditorHover;
    /// <summary>Editor-Beobachter (Tippen bis zur ersten Vervollständigung, L5; aktive Ansicht fürs Vorladen); -1
    /// ohne.</summary>
    FWatchIndex: Integer;
    FWatch: TObject;
    /// <summary>Eigene Referenz: Der Beobachter lebt, bis StopWatch ihn gelöst hat.</summary>
    FWatchRef: IInterface;
    /// <summary>Das Anlegen nach dem ersten Tippen ist eingereiht.</summary>
    FCreating: Boolean;
    /// <summary>ReleaseViews lief: nichts mehr anlegen.</summary>
    FReleased: Boolean;
    /// <summary>Vorladen: Ruhe nach dem Aktivieren, je Datei und Stand einmal.</summary>
    FPrewarmGate: TDpccPrewarmGate;
    /// <summary>Weckt PrewarmTick, sobald die Ruhe vorbei ist.</summary>
    FPrewarmTimer: TTimer;
    procedure CreateHover;
    procedure StartWatch;
    procedure StopWatch;
    procedure PrewarmTick(Sender: TObject);
    /// <summary>Ruhe vorbei: Ist AFileName noch vorn und die Sitzung bereit, abgleichen und dpcc/prewarm im
    /// Hintergrund.</summary>
    procedure PrewarmActive(const AFileName: string);
    /// <summary>Wartende Aktivierung verwerfen und alle gemerkten Stände vergessen.</summary>
    procedure StopPrewarm;
  public
    /// <summary>Hover anlegen; Vervollständigung und Parameter-Hint erst beim ersten Gebrauch.</summary>
    constructor Create(const AHooks: TDpccCodeInsightEditorHooks);
    destructor Destroy; override;
    /// <summary>Vervollständigung der Sitzung (Schnipsel, Neue Datei), beim ersten Aufruf angelegt.</summary>
    function Completion: TDpccEditorCompletion;
    /// <summary>Parameter-Hint, beim ersten Aufruf angelegt.</summary>
    function Signature: TDpccEditorSignature;
    /// <summary>Ist die Liste der Vervollständigung offen (#671)?</summary>
    function CompletionVisible: Boolean;
    /// <summary>Läuft der Platzhalter-Modus einer Vorlage (#589)?</summary>
    function PlaceholdersActive: Boolean;
    /// <summary>Vor dem Schließen der Verbindung: laufende Anfragen von Vervollständigung und Parameter-Hint
    /// abbrechen, ohne zu warten (kein Ergebnis kommt mehr an). Ihre Arbeiter kehren nach dem Schließen sofort
    /// zurück; der Stopp-Thread der Sitzung wartet auf sie (WaitWorkersIdle der Quellen), bevor er die Sitzung
    /// freigibt.</summary>
    procedure BeginStop;
    /// <summary>Nach dem Schließen der Verbindung: Ergebnisse laufender Hover-Anfragen verwerfen, ohne zu warten.
    /// Ihre Arbeiter kehren nach dem Schließen sofort zurück; der Stopp-Thread der Sitzung wartet auf sie
    /// (TDpccEditorHover.WaitWorkersIdle), bevor er die Sitzung freigibt.</summary>
    procedure EndStop;
    /// <summary>Hauptschalter aus (#407): offene Liste samt Platzhalter-Modus, Parameter-Hint und Tooltip schließen;
    /// die Anbindungen bleiben für das Wiedereinschalten. Nur im Hauptthread.</summary>
    procedure CloseViews;
    /// <summary>Vor der Sitzung freigeben: wartet auf laufende Anfragen und meldet Tasten und Beobachter ab.</summary>
    procedure ReleaseViews;
    /// <summary>Änderung in AView, solange es noch keine Vervollständigung gibt (L5): beim ersten Tippen in einer
    /// Datei von dpcc anlegen, wenn completion.autoMinChars nicht 0 ist.</summary>
    procedure TypingSeen(const AView: IOTAEditView);
    /// <summary>AView wurde aktiv (Öffnen, Tab-Wechsel, Sprung): Bedient dpcc die Datei, nach der Ruhe vorladen;
    /// sonst eine wartende Aktivierung verwerfen. Nur im Hauptthread.</summary>
    procedure ViewActivated(const AView: IOTAEditView);
  end;

implementation

uses
  System.Classes,
  DockForm,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Hangs,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Diagnostics.TimeLimit,
  dpcc.IDE.Foundation.EditorBuffer,
  dpcc.IDE.Foundation.EditorSnapshot,
  dpcc.IDE.Foundation.Settings;

const
  /// <summary>Kürzester Takt, wenn die Uhr beim Wecken noch etwas Ruhe übrig sieht.</summary>
  cPrewarmMinTickMs = 50;

/// <summary>Arbeiter aus TDpccTimeLimit (Post): Abgleich (didOpen bzw. didChange samt Diff und JSON, wie Sync) und
/// danach dpcc/prewarm an ASession. Hält nur Kopien (Datei, Text) und die Sitzung als rohen Zeiger wie der Abgleich
/// der Formulare (dpcc.IDE.Forms.Designer, SendWork): Der Hauptthread hat beim Post geprüft, dass sie die laufende
/// ist; der Stopp schließt vorher die Verbindung (Notify sendet dann nichts) und wartet auf diese Arbeiter
/// (TDpccTimeLimit.WaitIdle), bevor er sie freigibt. Nie die Anbindungen oder der Manager.</summary>
function PrewarmWork(ASession: TLspSession; const AFileName, AText: string): TProc;
var
  mSession: TLspSession;
  mFileName: string;
  mText: string;
begin
  mSession := ASession;
  mFileName := AFileName;
  mText := AText;
  Result :=
    procedure
    begin
      try
        if not TDpccShutdown.Signalled then
        begin
          mSession.Prewarm(mFileName, mText);
        end;
      except
        // Verbindung geschlossen oder Server fort: Die nächste Anfrage gleicht selbst ab.
        on Exception do
        begin
        end;
      end;
    end;
end;

type
  /// <summary>Editor-Beobachter: meldet Änderungen bis zur ersten Vervollständigung an TypingSeen (L5) und jede
  /// aktive Ansicht an ViewActivated (Vorladen). Lebt bis ReleaseViews.</summary>
  TTypingWatch = class(TNotifierObject, INTAEditServicesNotifier)
  private
    FOwner: TDpccCodeInsightEditors;
  public
    constructor Create(AOwner: TDpccCodeInsightEditors);
    procedure Detach;
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

{ TTypingWatch }

constructor TTypingWatch.Create(AOwner: TDpccCodeInsightEditors);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TTypingWatch.Detach;
begin
  FOwner := nil;
end;

procedure TTypingWatch.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
end;

procedure TTypingWatch.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
end;

procedure TTypingWatch.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TTypingWatch.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TTypingWatch.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  try
    if FOwner <> nil then
    begin
      FOwner.ViewActivated(EditView);
    end;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Server, E);
  end;
end;

procedure TTypingWatch.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  try
    if FOwner <> nil then
    begin
      FOwner.TypingSeen(EditView);
    end;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Completion, E);
  end;
end;

procedure TTypingWatch.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TTypingWatch.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TTypingWatch.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TDpccCodeInsightEditors }

constructor TDpccCodeInsightEditors.Create(const AHooks: TDpccCodeInsightEditorHooks);
begin
  inherited Create;
  FHooks := AHooks;
  FWatchIndex := -1;
  FPrewarmGate := TDpccPrewarmGate.Create;
  FPrewarmTimer := TTimer.Create(nil);
  FPrewarmTimer.Enabled := False;
  FPrewarmTimer.Interval := FPrewarmGate.QuietMs;
  FPrewarmTimer.OnTimer := PrewarmTick;
  CreateHover;
  StartWatch;
end;

procedure TDpccCodeInsightEditors.StartWatch;
var
  mEditor: IOTAEditorServices;
  mWatch: TTypingWatch;
begin
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    mWatch := TTypingWatch.Create(Self);
    FWatch := mWatch;
    FWatchRef := mWatch as INTAEditServicesNotifier;
    FWatchIndex := mEditor.AddNotifier(mWatch);
  end;
end;

procedure TDpccCodeInsightEditors.StopWatch;
var
  mEditor: IOTAEditorServices;
begin
  if FWatch <> nil then
  begin
    TTypingWatch(FWatch).Detach;
  end;
  if (FWatchIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    mEditor.RemoveNotifier(FWatchIndex);
  end;
  FWatchIndex := -1;
  FWatch := nil;
  FWatchRef := nil;
end;

procedure TDpccCodeInsightEditors.TypingSeen(const AView: IOTAEditView);
var
  mView: IOTAEditView;
begin
  if (FCompletion <> nil) or FCreating or FReleased or (TDpccIdeSettings.Current.AutoMinChars <= 0) or
    (AView = nil) or (AView.Buffer = nil) or not Assigned(FHooks.Handles) or
    not FHooks.Handles(AView.Buffer.FileName) then
  begin
    Exit;
  end;
  FCreating := True;
  mView := AView;
  // Nicht in der Benachrichtigung: Das Anlegen meldet selbst einen Beobachter an.
  TDpccMainThread.ForceQueue(TDpccFeature.Completion,
    procedure
    begin
      FCreating := False;
      if not FReleased and (FCompletion = nil) and (mView.Buffer <> nil) then
      begin
        Completion.SeedTyping(mView);
      end;
    end);
end;

procedure TDpccCodeInsightEditors.ViewActivated(const AView: IOTAEditView);
var
  mActivity: IInterface;
  mFileName: string;
begin
  if FReleased or (FPrewarmGate = nil) or (FPrewarmTimer = nil) then
  begin
    Exit;
  end;
  mActivity := TDpccActivity.Scope('Vorladen: Ansicht aktiv');
  mFileName := '';
  if (AView <> nil) and (AView.Buffer <> nil) then
  begin
    mFileName := AView.Buffer.FileName;
  end;
  // Datei, die dpcc nicht bedient (Formular, Text), Hauptschalter aus: Eine wartende Aktivierung entfällt.
  if (mFileName = '') or not Assigned(FHooks.Handles) or not FHooks.Handles(mFileName) then
  begin
    FPrewarmTimer.Enabled := False;
    FPrewarmGate.Cancel;
    Exit;
  end;
  // Die Ruhe beginnt neu: Schnelles Durchblättern der Tabs löst nichts aus.
  FPrewarmGate.Activated(mFileName);
  FPrewarmTimer.Enabled := False;
  FPrewarmTimer.Interval := FPrewarmGate.QuietMs;
  FPrewarmTimer.Enabled := True;
end;

procedure TDpccCodeInsightEditors.PrewarmTick(Sender: TObject);
var
  mActivity: IInterface;
  mFileName: string;
  mWaitMs: Cardinal;
begin
  mActivity := TDpccActivity.Scope('Vorladen: Ruhe vorbei');
  try
    if FReleased or (FPrewarmGate = nil) or (FPrewarmTimer = nil) then
    begin
      Exit;
    end;
    if not FPrewarmGate.TakeDue(mFileName) then
    begin
      // Takt etwas vor der Uhr: den Rest abwarten; ohne wartende Aktivierung aufhören.
      if FPrewarmGate.Pending then
      begin
        mWaitMs := FPrewarmGate.WaitMs;
        if mWaitMs < cPrewarmMinTickMs then
        begin
          mWaitMs := cPrewarmMinTickMs;
        end;
        FPrewarmTimer.Interval := mWaitMs;
      end
      else
      begin
        FPrewarmTimer.Enabled := False;
      end;
      Exit;
    end;
    FPrewarmTimer.Enabled := False;
    PrewarmActive(mFileName);
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Server, E);
  end;
end;

procedure TDpccCodeInsightEditors.PrewarmActive(const AFileName: string);
var
  mView: IOTAEditView;
  mSession: TLspSession;
  mSnapshot: TDpccEditorSnapshot;
  mSynced: string;
begin
  if FReleased or not Assigned(FHooks.Handles) or not FHooks.Handles(AFileName) or
    not Assigned(FHooks.RunningSession) then
  begin
    Exit;
  end;
  // Inzwischen eine andere Datei vorn (ohne neue Aktivierung, etwa ein zweites Editorfenster): nichts.
  mView := TDpccEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, AFileName) then
  begin
    Exit;
  end;
  // Nur eine laufende, bereite Sitzung; startet nie einen Server und wartet nie.
  mSession := FHooks.RunningSession();
  if mSession = nil then
  begin
    Exit;
  end;
  // Den Puffer liest nur der Hauptthread; der gemeinsame Stand liest ihn nur, wenn er als veraltet gilt (nach dem
  // Aktivieren immer: ein Lesevorgang je Datei, bei der der Benutzer bleibt).
  mSnapshot := TDpccEditorSnapshots.Get(mView);
  // Kennt die Sitzung die Datei nicht (neue Sitzung, auch an derselben Adresse): Der gemerkte Stand gilt nicht.
  if not mSession.SyncedText(AFileName, mSynced) then
  begin
    FPrewarmGate.Forget(AFileName);
  end;
  if not FPrewarmGate.Claim(AFileName, mSnapshot.Version, mSession) then
  begin
    Exit;
  end;
  // Diff, JSON und Senden im Hintergrund; ohne Arbeiter (dpcc wird beendet) beim nächsten Mal neu.
  if not TDpccTimeLimit.Post(PrewarmWork(mSession, AFileName, mSnapshot.Text)) then
  begin
    FPrewarmGate.Forget(AFileName);
  end;
end;

procedure TDpccCodeInsightEditors.StopPrewarm;
begin
  if FPrewarmTimer <> nil then
  begin
    FPrewarmTimer.Enabled := False;
  end;
  if FPrewarmGate <> nil then
  begin
    FPrewarmGate.Reset;
  end;
end;

destructor TDpccCodeInsightEditors.Destroy;
begin
  ReleaseViews;
  inherited;
end;

procedure TDpccCodeInsightEditors.CreateHover;
var
  mEnsure: TFunc<Boolean>;
  mRunning: TFunc<TLspSession>;
  mDiagnose: TProc<string>;
  mHandles: TFunc<string, Boolean>;
begin
  mEnsure := FHooks.EnsureSession;
  mRunning := FHooks.RunningSession;
  mDiagnose := FHooks.Diagnose;
  mHandles := FHooks.Handles;
  FHover := TDpccEditorHover.Create(
    function: TLspSession
    begin
      Result := nil;
      if mEnsure() then
      begin
        Result := mRunning();
      end;
    end,
    procedure(const AMessage: string)
    begin
      mDiagnose(AMessage);
    end,
    function(const AFileName: string): Boolean
    begin
      Result := mHandles(AFileName);
    end);
end;

function TDpccCodeInsightEditors.Signature: TDpccEditorSignature;
var
  mRunning: TFunc<TLspSession>;
  mDiagnose: TProc<string>;
begin
  if FSignature = nil then
  begin
    mRunning := FHooks.RunningSession;
    mDiagnose := FHooks.Diagnose;
    FSignature := TDpccEditorSignature.Create(
      FHooks.NewSignatureSource(
        function: TLspSession
        begin
          // Im Hauptthread beim Öffnen des Hints: nur eine laufende Sitzung, nie ein Start.
          Result := mRunning();
        end),
      function: Boolean
      begin
        Result := CompletionVisible;
      end,
      procedure(const AMessage: string)
      begin
        mDiagnose(AMessage);
      end);
  end;
  Result := FSignature;
end;

function TDpccCodeInsightEditors.Completion: TDpccEditorCompletion;
var
  mRunning: TFunc<TLspSession>;
  mDiagnose: TProc<string>;
  mEditView: TFunc<IOTAEditView>;
begin
  if FCompletion = nil then
  begin
    mRunning := FHooks.RunningSession;
    mDiagnose := FHooks.Diagnose;
    mEditView := FHooks.EditView;
    FCompletion := TDpccEditorCompletion.Create(
      function: TLspSession
      begin
        // Aufgerufen im Zeitlimit-Arbeiter (#493): nur eine laufende Sitzung, nie ein Start.
        Result := mRunning();
      end,
      procedure(const AMessage: string)
      begin
        mDiagnose(AMessage);
      end,
      FHooks.NewCompletionSources);
    // Nach "Add(|)" den Parameter-Hint öffnen (#430).
    FCompletion.OnOpenSignature :=
      procedure
      begin
        Signature.Invoke(mEditView());
      end;
    // Öffnen beim Tippen (L5).
    FCompletion.OnHandles := FHooks.Handles;
    FCompletion.OnEnsureSession := FHooks.EnsureSession;
    FCompletion.OnIdeListOpen := FHooks.IdeListOpen;
  end;
  Result := FCompletion;
end;

function TDpccCodeInsightEditors.CompletionVisible: Boolean;
begin
  Result := (FCompletion <> nil) and FCompletion.Visible;
end;

function TDpccCodeInsightEditors.PlaceholdersActive: Boolean;
begin
  Result := (FCompletion <> nil) and FCompletion.PlaceholdersActive;
end;

procedure TDpccCodeInsightEditors.BeginStop;
begin
  // Laufende Anfragen der Vervollständigung nutzen die Sitzung noch: abbrechen (Generation), nicht warten. Vor dem
  // Schließen, damit kein Arbeiter, den das Schließen weckt, noch ein (leeres) Ergebnis liefert.
  if FCompletion <> nil then
  begin
    FCompletion.Shutdown;
  end;
  if FSignature <> nil then
  begin
    FSignature.Shutdown;
  end;
  // Vorladen: Eine wartende Aktivierung geht nicht mehr an diese Sitzung; ein schon gestarteter Arbeiter sendet nach
  // dem Schließen nichts mehr, auf ihn wartet der Stopp-Thread (TDpccTimeLimit.WaitIdle).
  StopPrewarm;
end;

procedure TDpccCodeInsightEditors.EndStop;
begin
  // Hover-Anfragen halten die Sitzung als rohen Zeiger; nach Close kehren sie sofort zurück. Hier nur abbrechen;
  // gewartet wird im Stopp-Thread (TDpccEditorHover.WaitWorkersIdle).
  if FHover <> nil then
  begin
    FHover.Shutdown;
  end;
end;

procedure TDpccCodeInsightEditors.CloseViews;
begin
  if FCompletion <> nil then
  begin
    FCompletion.ViewChanged;
  end;
  if FSignature <> nil then
  begin
    FSignature.Close;
  end;
  // Hide verwirft auch ein noch ausstehendes Ergebnis (Schlüssel und Ansicht sind danach leer).
  if FHover <> nil then
  begin
    FHover.Hide;
  end;
  // Nach dem Wiedereinschalten gilt jeder Stand wieder als neu.
  StopPrewarm;
end;

procedure TDpccCodeInsightEditors.ReleaseViews;
begin
  FReleased := True;
  StopPrewarm;
  FreeAndNil(FPrewarmTimer);
  FreeAndNil(FPrewarmGate);
  StopWatch;
  FreeAndNil(FHover);
  FreeAndNil(FSignature);
  FreeAndNil(FCompletion);
end;

end.
