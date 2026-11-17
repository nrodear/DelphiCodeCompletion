unit dpcc.IDE.CodeInsight.Manager;

// Code Insight-Manager für Delphi in RAD Studio. Die IDE ruft ihn direkt auf; er fragt dpcc über eine
// eigene LSP-Sitzung. Umgesetzt: Symbolhinweis (Hover, GetHintText), Browse (Strg+Klick, GotoDefinition), Help
// Insight (leer, solange der dpcc-Tooltip an ist) und Vervollständigung im eigenen Popup (#410): Strg+Leer und "."
// lösen sie aus, InvokeCodeCompletion öffnet das Popup und meldet der IDE False, damit sie keine eigene Liste zeigt
// (#407). Parameterhilfe ebenso im eigenen Hint (#436): "(", "," und Strg+Umschalt+Leer, InvokeParameterCodeInsight
// meldet False.
// Oberste Stufe der Klassenkette State (Zustand, Protokoll) → Session (Start, Stopp, Projekte) → Commands (Befehle
// im Hintergrund) → Crashes (Abstürze, #1355) → Manager (Open Tools API). Serverprozess,
// Ordnerbeobachter und die Quellen von Vervollständigung und Parameter-Hint aus dem Kern setzt die
// Kompositionswurzel ein (TDpccCodeInsightAdapters).

interface

uses
  System.SysUtils,
  ToolsAPI,
  dpcc.IDE.Completion.Editor,
  dpcc.IDE.CodeInsight.Manager.State,
  dpcc.IDE.CodeInsight.Manager.Editors,
  dpcc.IDE.CodeInsight.Manager.Crashes;

type
  TDpccCodeInsightManager = class(TDpccCodeInsightCrashes, IOTACodeInsightManager, IOTACodeInsightManager90,
    IOTACodeInsightSelection)
  private
    /// <summary>Haken der Editor-Anbindungen an diesen Manager.</summary>
    function EditorHooks: TDpccCodeInsightEditorHooks;
    /// <summary>Zeigt dpcc den Tooltip selbst (Hauptschalter und Tooltip an)?</summary>
    class function OwnTooltip: Boolean; static;
  public
    constructor Create(const AAdapters: TDpccCodeInsightAdapters);
    destructor Destroy; override;
    /// <summary>Alles abbauen, was im Code des Plugins weiterliefe: Editor-Anbindungen, Sitzung, Server und
    /// Hintergrund-Threads (#886). Mehrfach aufrufbar, nur im Hauptthread. Danach meldet der Manager sich als
    /// ausgeschaltet. Die Kompositionswurzel ruft es beim Abmelden, weil die IDE den Manager nach
    /// RemoveCodeInsightManager noch halten kann (etwa mitten im Gruppen-Build); Destroy liefe dann
    /// erst später.</summary>
    procedure Shutdown;
    /// <summary>Vervollständigung der Sitzung (Schnipsel, Neue Datei); beim ersten Aufruf angelegt.</summary>
    function Completion: TDpccEditorCompletion;
    /// <summary>Ist die Liste der Vervollständigung offen (#671)?</summary>
    function CompletionVisible: Boolean;
    /// <summary>Läuft der Platzhalter-Modus einer Vorlage (#589: dann keine Mehrfachmarken)?</summary>
    function PlaceholdersActive: Boolean;
    /// <summary>Vervollständigung über eine eigene Taste von dpcc öffnen (#494). False: Die Taste gehört der IDE,
    /// weil an derselben Stelle nach dem vorigen Strg+Leertaste die Liste leer blieb (L3) oder weil die Liste der
    /// IDE schon offen ist (L4); sonst True, auch wenn dpcc gerade nicht fragen kann (Hauptschalter, Sicherung,
    /// Server angehalten). Ist dpcc der für die Datei gewählte Code Insight-Anbieter, bliebe ein durchgereichtes
    /// Strg+Leertaste wieder bei dpcc (InvokeCodeCompletion): Dann bleibt die Taste bei dpcc (L4).</summary>
    function OpenCompletion: Boolean;
    /// <summary>Parameter-Hint über eine eigene Taste von dpcc öffnen (#494).</summary>
    procedure OpenSignature;
    /// <summary>Hauptschalter umgeschaltet (#407), ohne Neustart: an startet Sitzung und Server, falls sie nicht
    /// laufen; aus schließt Liste, Parameter-Hint und Tooltip von dpcc. Der Server läuft dann weiter. Nur im
    /// Hauptthread; nach Shutdown wirkungslos.</summary>
    procedure MasterSwitchChanged(AEnabled: Boolean);
    /// <summary>Bietet IOTACodeInsightManager90 (Help Insight) nur an, solange der dpcc-Tooltip an ist.</summary>
    function QueryInterface(const IID: TGUID; out Obj): HResult; stdcall;
    { IOTACodeInsightManager100 }
    function GetName: string;
    function GetIDString: string;
    function GetEnabled: Boolean;
    procedure SetEnabled(Value: Boolean);
    function EditorTokenValidChars(PreValidating: Boolean): TSysCharSet;
    procedure AllowCodeInsight(var Allow: Boolean; const Key: Char);
    function PreValidateCodeInsight(const Str: string): Boolean;
    function IsViewerBrowsable(Index: Integer): Boolean;
    function GetMultiSelect: Boolean;
    procedure GetSymbolList(out SymbolList: IOTACodeInsightSymbolList);
    procedure OnEditorKey(Key: Char; var CloseViewer: Boolean; var Accept: Boolean);
    function HandlesFile(const AFileName: string): Boolean;
    function GetLongestItem: string;
    procedure GetParameterList(out ParameterList: IOTACodeInsightParameterList);
    procedure GetCodeInsightType(AChar: Char; AElement: Integer; out CodeInsightType: TOTACodeInsightType;
      out InvokeType: TOTAInvokeType);
    function InvokeCodeCompletion(HowInvoked: TOTAInvokeType; var Str: string): Boolean;
    function InvokeParameterCodeInsight(HowInvoked: TOTAInvokeType; var SelectedIndex: Integer): Boolean;
    procedure ParameterCodeInsightAnchorPos(var EdPos: TOTAEditPos);
    function ParameterCodeInsightParamIndex(EdPos: TOTAEditPos): Integer;
    function GetHintText(HintLine, HintCol: Integer): string;
    function GotoDefinition(out AFileName: string; out ALineNum: Integer; Index: Integer): Boolean; overload;
    function GotoDefinition(out AFileName: string; out ALineNum: Integer): Boolean; overload;
    procedure Done(Accepted: Boolean; out DisplayParams: Boolean);
    { IOTACodeInsightManager }
    function GetOptionSetName: string;
    { IOTACodeInsightManager90 }
    function GetHelpInsightHtml: WideString;
    { IOTACodeInsightSelection }
    function GetDisplayName: string;
  end;

implementation

uses
  Winapi.Windows,
  dpcc.Core.Completion.Fallback,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Hangs,
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Foundation.EditorSnapshot,
  dpcc.IDE.Foundation.LineTracker,
  dpcc.IDE.CodeInsight.Manager.Queries,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TManagerText = (Completion);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TManagerText] of string = (
    ('Vervollständigung: '),
    ('Completion: '));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TManagerText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

const
  // Unterscheidet sich vom gleichnamigen benutzerdefinierten LSP-Eintrag.
  cManagerName = 'dpcc';
  cManagerId = 'dpcc.CodeInsight';
  cDefinitionMethod = 'textDocument/definition';

const
  /// <summary>Fensterklasse der Liste in der Code-Insight-Ansicht der IDE (Name aus coreide370.bpl; L4). In der IDE
  /// nicht geprüft: Fehlt sie, gilt die Liste der IDE als geschlossen, wie bis L3.</summary>
  cIdeListClass = 'TCodeCompleteListView';

/// <summary>Ist AWindow sichtbar und von der Klasse cIdeListClass?</summary>
function IsIdeListWindow(AWindow: HWND): Boolean;
var
  mClass: array[0..63] of Char;
begin
  Result := IsWindowVisible(AWindow) and (GetClassName(AWindow, mClass, Length(mClass)) > 0) and
    SameText(string(PChar(@mClass[0])), cIdeListClass);
end;

function FindIdeListChild(AWindow: HWND; AParam: LPARAM): BOOL; stdcall;
begin
  if IsIdeListWindow(AWindow) then
  begin
    PBoolean(AParam)^ := True;
    Exit(False);
  end;
  Result := True;
end;

function FindIdeListWindow(AWindow: HWND; AParam: LPARAM): BOOL; stdcall;
begin
  if not IsWindowVisible(AWindow) then
  begin
    Exit(True);
  end;
  if IsIdeListWindow(AWindow) then
  begin
    PBoolean(AParam)^ := True;
  end
  else
  begin
    EnumChildWindows(AWindow, @FindIdeListChild, AParam);
  end;
  Result := not PBoolean(AParam)^;
end;

/// <summary>Ist die Liste der Code-Insight-Ansicht der IDE gerade sichtbar (L4)? Sucht in den Fenstern des
/// Hauptthreads nach cIdeListClass.</summary>
function IdeCompletionListOpen: Boolean;
begin
  Result := False;
  EnumThreadWindows(GetCurrentThreadId, @FindIdeListWindow, LPARAM(@Result));
end;

/// <summary>Kommt ein durchgereichtes Strg+Leertaste in AFileName bei einem anderen Anbieter an (L4)? Nein, wenn
/// dpcc für die Datei der gewählte Code Insight-Anbieter ist: Dann ruft die IDE mit der Taste wieder dpcc auf.
/// </summary>
function IdeListReachable(const AFileName: string): Boolean;
var
  mServices: IOTACodeInsightServices;
begin
  Result := True;
  if Supports(BorlandIDEServices, IOTACodeInsightServices, mServices) then
  begin
    Result := not mServices.HandlesFile(AFileName, cManagerId);
  end;
end;

/// <summary>Fehler eines Einstiegspunkts an die Sicherung (#493); ein beendeter Server oder sein
/// Zeitlimit (ELspClientError) ist erwartbar und zählt nicht.</summary>
procedure ReportFailure(AFeature: TDpccFeature; AE: Exception);
begin
  if not (AE is ELspClientError) then
  begin
    TDpccGuard.Report(AFeature, AE);
  end;
end;

{ TDpccCodeInsightManager }

constructor TDpccCodeInsightManager.Create(const AAdapters: TDpccCodeInsightAdapters);
begin
  inherited Create(AAdapters);
  // Gemeinsamer Pufferstand für Probleme und Inlay-Hints.
  TDpccEditorSnapshots.Install;
  FEditors := TDpccCodeInsightEditors.Create(EditorHooks);
end;

destructor TDpccCodeInsightManager.Destroy;
begin
  Shutdown;
  FreeAndNil(FEditors);
  inherited;
end;

function TDpccCodeInsightManager.EditorHooks: TDpccCodeInsightEditorHooks;
begin
  Result := Default(TDpccCodeInsightEditorHooks);
  Result.EnsureSession :=
    function: Boolean
    begin
      Result := EnsureSession;
    end;
  Result.RunningSession :=
    function: TLspSession
    begin
      Result := RunningSession;
    end;
  Result.ReadySession :=
    function: TLspSession
    begin
      Result := ReadySession;
    end;
  Result.Diagnose :=
    procedure(AMessage: string)
    begin
      Diagnose(AMessage);
    end;
  Result.Handles :=
    function(AFileName: string): Boolean
    begin
      Result := Handles(AFileName);
    end;
  Result.EditView :=
    function: IOTAEditView
    begin
      Result := TDpccCodeInsightQueries.CurrentEditView;
    end;
  Result.NewCompletionSources := FAdapters.NewCompletionSources;
  Result.NewSignatureSource := FAdapters.NewSignatureSource;
end;

procedure TDpccCodeInsightManager.Shutdown;
begin
  if FShutDown then
  begin
    Exit;
  end;
  FShutDown := True;
  FEnabled := False;
  RetireManager(Self);
  // Hält die Beobachter-Threads an; erst danach darf der Sammler weg.
  FFolderWatcher := nil;
  FreeAndNil(FFileChanges);
  // Vor der Sitzung: wartet auf laufende Anfragen und meldet Tasten und Beobachter ab.
  if FEditors <> nil then
  begin
    FEditors.ReleaseViews;
  end;
  FOnServerChanged := nil;
  StopSession;
  TDpccEditorSnapshots.Uninstall;
  TDpccIdeLineTracker.Uninstall;
  // Die Threads geben sich nicht selbst frei: Erst wenn sie beendet sind, läuft nichts mehr im Code des Plugins,
  // auch nicht das Freigeben ihrer anonymen Methode (#886). Sie nutzen bis zuletzt die Ereignisse aus Destroy.
  if not FThreads.StopAll(TDpccShutdown.cStopMs) then
  begin
    Diagnose('Manager abgebaut, während ein Hintergrund-Thread noch lief');
  end;
end;

function TDpccCodeInsightManager.Completion: TDpccEditorCompletion;
begin
  Result := FEditors.Completion;
end;

function TDpccCodeInsightManager.CompletionVisible: Boolean;
begin
  Result := FEditors.CompletionVisible;
end;

function TDpccCodeInsightManager.PlaceholdersActive: Boolean;
begin
  Result := FEditors.PlaceholdersActive;
end;

function TDpccCodeInsightManager.GetHintText(HintLine, HintCol: Integer): string;
var
  mView: IOTAEditView;
  mActivity: IInterface;
begin
  mActivity := TDpccActivity.Scope('Symbolhinweis');
  Result := '';
  // Durch die Sicherung abgeschaltet (#493); eigener Tooltip (#442): die IDE zeigt keinen
  // zweiten.
  if TDpccGuard.Disabled(TDpccFeature.Hover) then
  begin
    Exit;
  end;
  Diagnose(Format('GetHintText(%d, %d) aufgerufen', [HintLine, HintCol]));
  if TDpccIdeSettings.Current.HoverTooltip then
  begin
    Exit;
  end;
  try
    mView := TDpccCodeInsightQueries.CurrentEditView;
    if (mView <> nil) and (mView.Buffer <> nil) and EnsureSession then
    begin
      Result := TDpccCodeInsightQueries.HintAt(FSession, mView, HintLine, HintCol,
        procedure(AMessage: string)
        begin
          Diagnose(AMessage);
        end);
    end;
  except
    on E: Exception do
    begin
      ReportError('Hover: ' + E.Message);
      ReportFailure(TDpccFeature.Hover, E);
      Result := '';
    end;
  end;
end;

function TDpccCodeInsightManager.GotoDefinition(out AFileName: string; out ALineNum: Integer): Boolean;
begin
  Result := GotoDefinition(AFileName, ALineNum, -1);
end;

function TDpccCodeInsightManager.GotoDefinition(out AFileName: string; out ALineNum: Integer;
  Index: Integer): Boolean;
var
  mView: IOTAEditView;
  mActivity: IInterface;
begin
  mActivity := TDpccActivity.Scope('Gehe zu Definition');
  // Laut ToolsAPI: AFileName = '' und ALineNum = 0 bricht ohne Meldung ab. Mit False meldet die IDE „Datei ""
  // nicht gefunden“; deshalb True. Ausnahme: Bietet der Server keine Definitionen an, False, damit die IDE selbst
  // navigiert.
  AFileName := '';
  ALineNum := 0;
  Result := True;
  // Durch die Sicherung abgeschaltet (#493); AFileName = '' bricht still ab.
  if TDpccGuard.Disabled(TDpccFeature.GoToDefinition) then
  begin
    Exit;
  end;
  Diagnose(Format('GotoDefinition(Index %d) aufgerufen', [Index]));
  try
    mView := TDpccCodeInsightQueries.CurrentEditView;
    if (mView = nil) or (mView.Buffer = nil) then
    begin
      Diagnose('Gehe zu Definition: keine Editoransicht');
    end
    else if EnsureSession then
    begin
      // Server ohne textDocument/definition (schlanker Server, Schritt 2): False, ohne Meldung; die IDE springt
      // dann selbst.
      if not FSession.Offers(cDefinitionMethod) then
      begin
        Diagnose('Gehe zu Definition: Server bietet keine Definitionen, die IDE übernimmt');
        Exit(False);
      end;
      TDpccCodeInsightQueries.DefinitionAt(FSession, mView, Index,
        procedure(AMessage: string)
        begin
          Diagnose(AMessage);
        end, AFileName, ALineNum);
    end;
  except
    on E: ELspMethodNotFound do
    begin
      // Erst jetzt als fehlend erkannt (-32601): wie oben.
      Diagnose('Gehe zu Definition: ' + E.Message + ', die IDE übernimmt');
      AFileName := '';
      ALineNum := 0;
      Result := False;
    end;
    on E: Exception do
    begin
      ReportError('Gehe zu Definition: ' + E.Message);
      ReportFailure(TDpccFeature.GoToDefinition, E);
      AFileName := '';
      ALineNum := 0;
    end;
  end;
end;

function TDpccCodeInsightManager.GetName: string;
begin
  Result := cManagerName;
end;

function TDpccCodeInsightManager.GetIDString: string;
begin
  Result := cManagerId;
end;

function TDpccCodeInsightManager.GetDisplayName: string;
begin
  Result := cManagerName;
end;

function TDpccCodeInsightManager.GetOptionSetName: string;
begin
  // Dieselben Editoreinstellungen wie der eingebaute Delphi-Manager.
  Result := 'Borland.EditOptions.Pascal';
end;

class function TDpccCodeInsightManager.OwnTooltip: Boolean;
begin
  Result := TDpccIdeSettings.Current.Enabled and TDpccIdeSettings.Current.HoverTooltip;
end;

function TDpccCodeInsightManager.QueryInterface(const IID: TGUID; out Obj): HResult;
begin
  // Ohne IOTACodeInsightManager90 holt sich die IDE Help Insight anderswo (DelphiLSP) und zeigt es neben dem
  // dpcc-Tooltip. Mit dem dpcc-Tooltip aus bleibt es beim Verhalten der IDE.
  if IsEqualGUID(IID, IOTACodeInsightManager90) and not OwnTooltip then
  begin
    Pointer(Obj) := nil;
    Exit(E_NOINTERFACE);
  end;
  Result := inherited QueryInterface(IID, Obj);
end;

function TDpccCodeInsightManager.GetHelpInsightHtml: WideString;
begin
  // Der dpcc-Tooltip zeigt alles; die IDE soll keinen zweiten Tooltip öffnen.
  Result := '';
  Diagnose('GetHelpInsightHtml aufgerufen');
end;

function TDpccCodeInsightManager.GetEnabled: Boolean;
begin
  Result := FEnabled;
end;

procedure TDpccCodeInsightManager.SetEnabled(Value: Boolean);
begin
  FEnabled := Value;
  Diagnose('SetEnabled(' + BoolToStr(Value, True) + ')');
  if not Value then
  begin
    StopSession;
  end;
end;

function TDpccCodeInsightManager.EditorTokenValidChars(PreValidating: Boolean): TSysCharSet;
begin
  Result := ['A'..'Z', 'a'..'z', '0'..'9', '_', '&'];
  if PreValidating then
  begin
    Include(Result, '.');
  end;
end;

procedure TDpccCodeInsightManager.AllowCodeInsight(var Allow: Boolean; const Key: Char);
begin
  Allow := False;
  try
    // #0 Vervollständigung (Strg+Leer), "." Vervollständigung nach Punkt, #2 Browse
    // (Strg+Klick), #3 Symbolhinweis; #1 Parameterhilfe (Strg+Umschalt+Leer), "(" und ",".
    // "<" nur für XMLDoc-Tags in ///-Kommentaren (#435), siehe GetCodeInsightType. "[" für Mengen (#448): Der
    // Server liefert nur in einem Mengenkonstruktor etwas, sonst bleibt das Popup zu.
    Allow := CharInSet(Key, [#0, '.', #1, '(', ',', #2, #3, '<', '[']);
    Diagnose(Format('AllowCodeInsight(#%d) = %s', [Ord(Key), BoolToStr(Allow, True)]));
  except
    on E: Exception do
    begin
      TDpccGuard.Report(TDpccFeature.Completion, E);
    end;
  end;
end;

function TDpccCodeInsightManager.PreValidateCodeInsight(const Str: string): Boolean;
begin
  Result := True;
end;

function TDpccCodeInsightManager.IsViewerBrowsable(Index: Integer): Boolean;
begin
  Result := False;
end;

function TDpccCodeInsightManager.GetMultiSelect: Boolean;
begin
  Result := False;
end;

procedure TDpccCodeInsightManager.GetSymbolList(out SymbolList: IOTACodeInsightSymbolList);
begin
  SymbolList := nil;
end;

procedure TDpccCodeInsightManager.OnEditorKey(Key: Char; var CloseViewer: Boolean; var Accept: Boolean);
begin
  try
    CloseViewer := True;
    Accept := False;
  except
    on E: Exception do
    begin
      TDpccGuard.Report(TDpccFeature.Completion, E);
    end;
  end;
end;

function TDpccCodeInsightManager.HandlesFile(const AFileName: string): Boolean;
begin
  Result := False;
  try
    Result := Handles(AFileName);
    Diagnose(Format('HandlesFile(%s) = %s', [ExtractFileExt(AFileName), BoolToStr(Result, True)]));
  except
    on E: Exception do
    begin
      TDpccGuard.Report(TDpccFeature.Completion, E);
    end;
  end;
end;

function TDpccCodeInsightManager.GetLongestItem: string;
begin
  Result := 'constructor';
end;

procedure TDpccCodeInsightManager.GetParameterList(out ParameterList: IOTACodeInsightParameterList);
begin
  ParameterList := nil;
end;

procedure TDpccCodeInsightManager.GetCodeInsightType(AChar: Char; AElement: Integer;
  out CodeInsightType: TOTACodeInsightType; out InvokeType: TOTAInvokeType);
begin
  CodeInsightType := citNone;
  InvokeType := itManual;
  try
    CodeInsightType := TDpccCodeInsightQueries.InsightType(AChar, AElement,
      function: Boolean
      begin
        // Nach dem ";" hinter einem übernommenen Konstruktor „Mit try…finally absichern“ (#489).
        Result := Completion.GuardPending(TDpccCodeInsightQueries.CurrentEditView);
      end, InvokeType);
    Diagnose(Format('GetCodeInsightType(#%d, Element %d) = %d', [Ord(AChar), AElement, Ord(CodeInsightType)]));
  except
    on E: Exception do
    begin
      TDpccGuard.Report(TDpccFeature.Completion, E);
    end;
  end;
end;

function TDpccCodeInsightManager.InvokeCodeCompletion(HowInvoked: TOTAInvokeType; var Str: string): Boolean;
var
  mActivity: IInterface;
begin
  mActivity := TDpccActivity.Scope('Vervollständigung öffnen');
  // False: Die IDE zeigt keine eigene Liste; unser Popup übernimmt (#407, #410).
  Result := False;
  Diagnose(Format('InvokeCodeCompletion(%d, %d Zeichen)', [Ord(HowInvoked), Length(Str)]));
  try
    // Start nur hier im Hauptthread; die Quellen bekommen danach die laufende Sitzung.
    // Ohne Server liefern die übrigen Quellen trotzdem.
    EnsureSession;
    Completion.Invoke(TDpccCodeInsightQueries.CurrentEditView, HowInvoked <> itManual);
  except
    on E: Exception do
    begin
      ReportError(UiText(TManagerText.Completion) + E.Message);
      ReportFailure(TDpccFeature.Completion, E);
    end;
  end;
end;

function TDpccCodeInsightManager.InvokeParameterCodeInsight(HowInvoked: TOTAInvokeType;
  var SelectedIndex: Integer): Boolean;
var
  mActivity: IInterface;
begin
  // False: Die IDE zeigt keine eigene Parameterhilfe; unser Hint übernimmt (#436).
  Result := False;
  // Durch die Sicherung abgeschaltet (#493).
  if TDpccGuard.Disabled(TDpccFeature.Signature) then
  begin
    Exit;
  end;
  mActivity := TDpccActivity.Scope('Parameterhilfe');
  Diagnose(Format('InvokeParameterCodeInsight(%d)', [Ord(HowInvoked)]));
  try
    // Start nur hier im Hauptthread.
    EnsureSession;
    FEditors.Signature.Invoke(TDpccCodeInsightQueries.CurrentEditView);
  except
    on E: Exception do
    begin
      ReportError('Parameterhilfe: ' + E.Message);
      ReportFailure(TDpccFeature.Signature, E);
    end;
  end;
end;

function TDpccCodeInsightManager.OpenCompletion: Boolean;
var
  mView: IOTAEditView;
  mIde: TDpccIdeList;
begin
  Result := True;
  if not FEnabled or TDpccGuard.Disabled(TDpccFeature.Completion) or not ServerAvailable then
  begin
    Exit;
  end;
  Diagnose('Vervollständigung über eigene Taste');
  try
    // Start nur hier im Hauptthread, vor der Anfrage: Die Quellen holen sich die laufende Sitzung.
    EnsureSession;
    mView := TDpccCodeInsightQueries.CurrentEditView;
    mIde := TDpccIdeList.Usual;
    if (mView <> nil) and (mView.Buffer <> nil) then
    begin
      mIde := TDpccIdeList.Create(IdeListReachable(mView.Buffer.FileName), IdeCompletionListOpen);
      Diagnose(Format('Liste der IDE: erreichbar %s, offen %s', [BoolToStr(mIde.Reachable, True),
        BoolToStr(mIde.Open, True)]));
    end;
    // Zweites Strg+Leertaste nach leerem Ergebnis an derselben Stelle (L3) bzw. offene Liste der IDE (L4): False,
    // die Taste gehört der IDE.
    Result := Completion.KeyInvoke(mView, mIde);
  except
    on E: Exception do
    begin
      ReportError(UiText(TManagerText.Completion) + E.Message);
      ReportFailure(TDpccFeature.Completion, E);
    end;
  end;
end;

procedure TDpccCodeInsightManager.OpenSignature;
begin
  if not FEnabled or TDpccGuard.Disabled(TDpccFeature.Signature) or not ServerAvailable then
  begin
    Exit;
  end;
  Diagnose('Parameterhilfe über eigene Taste');
  try
    // Start nur hier im Hauptthread.
    EnsureSession;
    FEditors.Signature.Invoke(TDpccCodeInsightQueries.CurrentEditView);
  except
    on E: Exception do
    begin
      ReportError('Parameterhilfe: ' + E.Message);
      ReportFailure(TDpccFeature.Signature, E);
    end;
  end;
end;

procedure TDpccCodeInsightManager.MasterSwitchChanged(AEnabled: Boolean);
begin
  if FShutDown or not TDpccMainThread.IsMain then
  begin
    Exit;
  end;
  Diagnose('Hauptschalter ' + BoolToStr(AEnabled, True));
  try
    if AEnabled then
    begin
      // Wer bisher den Server startete, war die erste Anfrage nach dem Einschalten. Jetzt gleich, damit Liste, Hint
      // und Tooltip sofort antworten; nicht, wenn die IDE den Manager abgeschaltet hat (SetEnabled) oder die
      // Sicherung die Vervollständigung. Nach zwei gleichen Abstürzen startet EnsureSession nicht (FCrashes).
      if FEnabled and not TDpccGuard.Disabled(TDpccFeature.Completion) then
      begin
        EnsureSession;
      end;
    end
    else if FEditors <> nil then
    begin
      // HandlesFile liest den Schalter bei jedem Aufruf: Die IDE nimmt ab jetzt wieder ihre Code Insight. Der Server
      // bleibt (#407): Die Optionsseite startet ihn für Kennzahlen ohnehin, ein Stopp wartete im Hauptthread auf
      // laufende Anfragen, und schnelles Umschalten zählte jeden Start als Neustart mit Meldung.
      FEditors.CloseViews;
    end;
  except
    on E: Exception do
    begin
      ReportError('Hauptschalter: ' + E.Message);
      ReportFailure(TDpccFeature.Completion, E);
    end;
  end;
end;

procedure TDpccCodeInsightManager.ParameterCodeInsightAnchorPos(var EdPos: TOTAEditPos);
begin
end;

function TDpccCodeInsightManager.ParameterCodeInsightParamIndex(EdPos: TOTAEditPos): Integer;
begin
  Result := -1;
end;

procedure TDpccCodeInsightManager.Done(Accepted: Boolean; out DisplayParams: Boolean);
begin
  DisplayParams := False;
  try
    DisplayParams := False;
  except
    on E: Exception do
    begin
      TDpccGuard.Report(TDpccFeature.Completion, E);
    end;
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.IDE.CodeInsight.Manager', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
