unit dpcc.IDE.CodeInsight.Manager.Editors;

// Anbindungen des Code Insight-Managers an den Editor: Vervollständigung im eigenen Popup (#410), Parameter-Hint
// (#436) und eigener Hover-Tooltip (#442). Sie fragen die Sitzung über die Haken des Managers; abgebaut wird in der
// Reihenfolge, die DetachSession und Shutdown brauchen. Probleme, Inlay-Hints und Code Lens gibt es seit Rückbau R6
// nicht mehr.
// Tippen (L5, completion.autoMinChars): Die Vervollständigung entsteht sonst erst beim ersten Strg+Leertaste. Damit
// das Öffnen beim Tippen von Anfang an wirkt, beobachtet ein kleiner Editor-Beobachter die Änderungen, bis sie
// existiert: Beim ersten Tippen in einer Datei, die dpcc bedient, legt er sie gleich nach der Benachrichtigung an und
// merkt sich den Stand der Zeile; ab dann übernimmt ihr eigener Beobachter.

interface

uses
  System.SysUtils,
  ToolsAPI,
  dpcc.Core.Lsp.Session,
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
    /// <summary>Beobachter bis zur ersten Vervollständigung (L5); -1 ohne.</summary>
    FWatchIndex: Integer;
    FWatch: TObject;
    /// <summary>Eigene Referenz: Der Beobachter lebt, bis StopWatch ihn gelöst hat.</summary>
    FWatchRef: IInterface;
    /// <summary>Das Anlegen nach dem ersten Tippen ist eingereiht.</summary>
    FCreating: Boolean;
    /// <summary>ReleaseViews lief: nichts mehr anlegen.</summary>
    FReleased: Boolean;
    procedure CreateHover;
    procedure StartWatch;
    procedure StopWatch;
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
    /// beenden.</summary>
    procedure BeginStop;
    /// <summary>Nach dem Schließen der Verbindung: Hover-Anfragen kehren sofort zurück.</summary>
    procedure EndStop;
    /// <summary>Hauptschalter aus (#407): offene Liste samt Platzhalter-Modus, Parameter-Hint und Tooltip schließen;
    /// die Anbindungen bleiben für das Wiedereinschalten. Nur im Hauptthread.</summary>
    procedure CloseViews;
    /// <summary>Vor der Sitzung freigeben: wartet auf laufende Anfragen und meldet Tasten und Beobachter ab.</summary>
    procedure ReleaseViews;
    /// <summary>Änderung in AView, solange es noch keine Vervollständigung gibt (L5): beim ersten Tippen in einer
    /// Datei von dpcc anlegen, wenn completion.autoMinChars nicht 0 ist.</summary>
    procedure TypingSeen(const AView: IOTAEditView);
  end;

implementation

uses
  System.Classes,
  DockForm,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.IDE.Foundation.Settings;

type
  /// <summary>Editor-Beobachter bis zur ersten Vervollständigung (L5): meldet Änderungen an TypingSeen.</summary>
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
  // Laufende Anfragen der Vervollständigung nutzen die Sitzung noch.
  if FCompletion <> nil then
  begin
    FCompletion.Shutdown;
  end;
  if FSignature <> nil then
  begin
    FSignature.Shutdown;
  end;
end;

procedure TDpccCodeInsightEditors.EndStop;
begin
  // Hover-Anfragen halten die Sitzung als rohen Zeiger; nach Close kehren sie sofort zurück.
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
end;

procedure TDpccCodeInsightEditors.ReleaseViews;
begin
  FReleased := True;
  StopWatch;
  FreeAndNil(FHover);
  FreeAndNil(FSignature);
  FreeAndNil(FCompletion);
end;

end.
