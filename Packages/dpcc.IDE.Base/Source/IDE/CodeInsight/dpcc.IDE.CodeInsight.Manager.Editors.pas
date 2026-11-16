unit dpcc.IDE.CodeInsight.Manager.Editors;

// Anbindungen des Code Insight-Managers an den Editor: Vervollständigung im eigenen Popup (#410), Parameter-Hint
// (#436) und eigener Hover-Tooltip (#442). Sie fragen die Sitzung über die Haken des Managers; abgebaut wird in der
// Reihenfolge, die StopSession und Shutdown brauchen. Probleme, Inlay-Hints und Code Lens gibt es seit Rückbau R6
// nicht mehr.

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
    /// <summary>Laufende Sitzung oder Start im Hauptthread; außerhalb des Hauptthreads nur, was schon läuft.
    /// </summary>
    EnsureSession: TFunc<Boolean>;
    /// <summary>Laufende Sitzung oder nil, nie während StopSession; startet keinen Server.</summary>
    RunningSession: TFunc<TLspSession>;
    /// <summary>Server läuft und Sitzung initialisiert; startet keinen Server.</summary>
    ReadySession: TFunc<TLspSession>;
    Diagnose: TProc<string>;
    /// <summary>Bedient dpcc diese Datei?</summary>
    Handles: TFunc<string, Boolean>;
    /// <summary>Editoransicht, in der Code Insight gerade läuft.</summary>
    EditView: TFunc<IOTAEditView>;
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
    procedure CreateHover;
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
  end;

implementation

constructor TDpccCodeInsightEditors.Create(const AHooks: TDpccCodeInsightEditorHooks);
begin
  inherited Create;
  FHooks := AHooks;
  CreateHover;
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
  FreeAndNil(FHover);
  FreeAndNil(FSignature);
  FreeAndNil(FCompletion);
end;

end.
