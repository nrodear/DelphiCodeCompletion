unit dpcc.IDE.CodeInsight.Manager;

// Code Insight-Manager für Delphi in RAD Studio. Die IDE ruft ihn direkt auf; er fragt dpcc über eine
// eigene LSP-Sitzung. Umgesetzt: Symbolhinweis (Hover, GetHintText), Browse (Strg+Klick, „Deklaration suchen“,
// GotoDefinition über textDocument/declaration und definition; Auftrag NAV), Help
// Insight (leer, solange der dpcc-Tooltip an ist) und Vervollständigung im eigenen Popup (#410): Strg+Leer und "."
// lösen sie aus, InvokeCodeCompletion öffnet das Popup und meldet der IDE False, damit sie keine eigene Liste zeigt
// (#407). Parameterhilfe ebenso im eigenen Hint (#436): "(", "," und Strg+Umschalt+Leer, InvokeParameterCodeInsight
// meldet False.
// Oberste Stufe der Klassenkette State (Zustand, Protokoll) → Session (Start, Stopp, Projekte) → Commands (Befehle
// im Hintergrund) → Crashes (Abstürze, #1355) → Manager (Open Tools API). Serverprozess,
// Ordnerbeobachter und die Quellen von Vervollständigung und Parameter-Hint aus dem Kern setzt die
// Kompositionswurzel ein (TDpccCodeInsightAdapters).
// IOTACodeInsightManagerEnvOptions (IDECHECK, Delphi 12 und 13): Wählt der Nutzer im Code-Insight-Dialog der IDE dpcc
// bzw. einen anderen Anbieter, ruft die IDE ManagerEnabled bzw. ManagerDisabled; der Manager reicht das an
// OnProviderChoice weiter (Betriebsart, dpcc.IDE.Foundation.InsightSwitch). Die Is…Visible-Abfragen lassen alle
// Elemente des Dialogs sichtbar wie bisher.
// Strg+Klick und Symbolhinweis der IDE ohne Einfrieren (dpcc.Core.Lsp.LateAnswers): Der Hauptthread gleicht den
// Puffer ab und startet die Anfrage in einem Hintergrund-Thread (FThreads, Leerlauf-Signal für den Stopp); er wartet
// höchstens TDpccLateAnswers.cWaitMs. Kommt das Sprungziel später, antwortet GotoDefinition still (True ohne Datei,
// keine Meldung), und LateGoto springt selbst, wenn es noch passt (dieselbe Datei, Cursor an der Ausgangsstelle,
// kein neuerer Sprungwunsch, höchstens cMaxAgeMs alt). Ein später Symbolhinweis kommt in FHintCache; der nächste
// Aufruf der IDE für dasselbe Wort antwortet dann sofort. Nachgereicht wird nur über TDpccMainThread.Queue; der
// Eintrag sucht den lebenden Manager erst im Hauptthread (LiveManagerObject). Wartezeiten über cWaitMs stehen
// gedrosselt im Protokoll (TDpccGuard.ReportProviderSlow).

interface

uses
  System.SysUtils,
  ToolsAPI,
  dpcc.Core.Lsp.LateAnswers,
  dpcc.IDE.Completion.Editor,
  dpcc.IDE.CodeInsight.Manager.State,
  dpcc.IDE.CodeInsight.Manager.Editors,
  dpcc.IDE.CodeInsight.Manager.Crashes,
  dpcc.IDE.CodeInsight.Manager.Queries,
  dpcc.Core.Editor.Navigation;

type
  TDpccCodeInsightManager = class(TDpccCodeInsightCrashes, IOTACodeInsightManager, IOTACodeInsightManager90,
    IOTACodeInsightSelection, IOTACodeInsightManagerEnvOptions)
  private
    /// <summary>Laufende Nummer der Sprungwünsche: Ein nachgereichtes Ziel gilt nur für den neuesten. Nur
    /// Hauptthread.</summary>
    FGotoGeneration: Cardinal;
    /// <summary>Gemerkte Symbolhinweise (nur Hauptthread). Referenzgezählt: Nachgereichte Antworten erreichen ihn über
    /// TDpccMainThread.Queue, ohne den Manager zu halten.</summary>
    FHintCache: IDpccHintCache;
    /// <summary>Laufende bzw. letzte Anfrage des Symbolhinweises und ihr Schlüssel.</summary>
    FHintSlot: IDpccAnswerSlot;
    FHintKey: TDpccHintKey;
    /// <summary>AWork in einem Hintergrund-Thread (FThreads); der Stopp im Hintergrund wartet über das
    /// Leerlauf-Signal (BeginServerCommand), bevor er die Sitzung freigibt. AWork beendet das Signal selbst.</summary>
    procedure StartWork(const AWork: TProc);
    /// <summary>Sprungwunsch an AView: abgleichen, im Hintergrund fragen, höchstens cWaitMs warten. Deferred, wenn
    /// die Antwort später kommt (LateGoto). Unerwartete Fehler kommen als Exception.</summary>
    function AskDefinition(const AView: IOTAEditView; AIndex: Integer; out AFileName: string;
      out ALine: Integer): TDpccGotoOutcome;
    /// <summary>Nachgereichtes Sprungziel (Hauptthread): springen, wenn es noch passt, sonst still verwerfen.
    /// </summary>
    procedure LateGoto(const AOrigin: TDpccGotoOrigin; const AAnswer: TDpccAnswer);
    /// <summary>Hover-Text des Servers für APlace: gemerkt, sonst im Hintergrund gefragt und höchstens cWaitMs
    /// gewartet ('' und gemerkt, wenn er später kommt). ASource fürs Diagnoseprotokoll.</summary>
    function ServerHint(const APlace: TDpccHintPlace; out ASource: string): string;
    /// <summary>Haken der Editor-Anbindungen an diesen Manager.</summary>
    function EditorHooks: TDpccCodeInsightEditorHooks;
    /// <summary>Zeigt dpcc den Tooltip selbst (Hauptschalter und Tooltip an)?</summary>
    class function OwnTooltip: Boolean; static;
    /// <summary>Einmal je Sitzung (NAV): Ist dpcc für die Datei im Editor der gewählte Anbieter, eine Zeile im
    /// Meldungsfenster, was dann fehlt und dass Strg+Klick über dpcc läuft.</summary>
    procedure NoticeIfSelected;
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
    { IOTACodeInsightManagerEnvOptions }
    function IsEnableErrorInsightVisible: Boolean;
    function IsCodeCompleteAutoParensVisible: Boolean;
    function IsCodeCompleteAutoInvokeVisible: Boolean;
    function IsCodeCompleteHistoryVisible: Boolean;
    function IsCodeCompleteShowReservedWordsVisible: Boolean;
    function IsCodeParametersVisible: Boolean;
    function IsEvalHintsVisible: Boolean;
    function IsDeclInfoVisible: Boolean;
    function IsToolTipHelpInsightVisible: Boolean;
    function IsEnableAutoCompletionVisible: Boolean;
    function IsBlockWrapStyleVisible: Boolean;
    function GetCodeInsightUIName: string;
    procedure ManagerDisabled;
    procedure ManagerEnabled;
  public
    /// <summary>Wahl im Code-Insight-Dialog der IDE (True = dpcc gewählt, False = ein anderer Anbieter); setzt die
    /// Kompositionswurzel. Läuft im Thread des Aufrufs der IDE (Hauptthread).</summary>
    class var OnProviderChoice: TProc<Boolean>;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  dpcc.Core.Completion.Fallback,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.SessionStart,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Hangs,
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Foundation.EditorSnapshot,
  dpcc.IDE.Foundation.LineTracker,
  dpcc.IDE.Foundation.Navigation,
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

const
  /// <summary>Namen für die gedrosselten Zeilen im Protokoll (TDpccGuard.ReportProviderSlow: je Name höchstens eine
  /// Zeile je Minute).</summary>
  cGotoSlowName = 'Gehe zu Definition';
  cGotoLateName = 'Gehe zu Definition (nachgereicht)';
  cHintSlowName = 'Symbolhinweis';
  cHintLateName = 'Symbolhinweis (nachgereicht)';

/// <summary>Fehler einer Anfrage im Hintergrund als Teil der Antwort: Der Thread lässt keine Exception hinaus.
/// </summary>
procedure FailAnswer(AE: Exception; var AAnswer: TDpccAnswer);
begin
  AAnswer.Found := False;
  AAnswer.ErrorText := AE.ClassName + ': ' + AE.Message;
  if AE is ELspMethodNotFound then
  begin
    AAnswer.Error := TDpccAnswerError.MethodNotFound;
  end
  else if AE is ELspClientError then
  begin
    AAnswer.Error := TDpccAnswerError.ClientError;
  end
  else
  begin
    AAnswer.Error := TDpccAnswerError.Other;
  end;
end;

/// <summary>Nachgereichtes Sprungziel im Hauptthread: an den lebenden Manager, sonst verworfen.</summary>
procedure DeliverLateGoto(const AOrigin: TDpccGotoOrigin; const AAnswer: TDpccAnswer);
var
  mManager: TObject;
begin
  mManager := LiveManagerObject;
  if mManager is TDpccCodeInsightManager then
  begin
    TDpccCodeInsightManager(mManager).LateGoto(AOrigin, AAnswer);
  end;
end;

/// <summary>Aus dem Hintergrund-Thread: AAnswer über TDpccMainThread.Queue nachreichen (beim Entladen verworfen).
/// </summary>
procedure QueueLateGoto(const AOrigin: TDpccGotoOrigin; const AAnswer: TDpccAnswer);
var
  mOrigin: TDpccGotoOrigin;
  mAnswer: TDpccAnswer;
begin
  mOrigin := AOrigin;
  mAnswer := AAnswer;
  TDpccMainThread.Queue(TDpccFeature.GoToDefinition,
    procedure
    begin
      DeliverLateGoto(mOrigin, mAnswer);
    end);
end;

/// <summary>Arbeit des Hintergrund-Threads für einen Sprungwunsch: GotoTargetAt ohne Abgleich (Sync vorher im
/// Hauptthread), Antwort in ASlot; kam sie für den Hauptthread zu spät, reicht der Thread sie nach. Hält nur die
/// Sitzung (der Stopp wartet über ASignals), den Slot und Kopien, nie den Manager.</summary>
function GotoWork(ASession: TLspSession; const ASignals: IDpccIdleSignals; const ASlot: IDpccAnswerSlot;
  const APlace: TDpccGotoPlace): TProc;
var
  mSession: TLspSession;
  mSignals: IDpccIdleSignals;
  mSlot: IDpccAnswerSlot;
  mOrigin: TDpccGotoOrigin;
  mLineText: string;
begin
  mSession := ASession;
  mSignals := ASignals;
  mSlot := ASlot;
  mOrigin := APlace.Origin;
  mLineText := APlace.LineText;
  Result :=
    procedure
    var
      mAnswer: TDpccAnswer;
      mLocation: TLspLocation;
    begin
      try
        try
          TThread.NameThreadForDebugging('dpcc.GotoDefinition');
          mAnswer := Default(TDpccAnswer);
          try
            mAnswer.Found := mSession.GotoTargetAt(mOrigin.FileName, mLineText, mOrigin.AtLine - 1,
              mOrigin.AtCharacter, TDpccLateAnswers.cMaxAgeMs, mLocation);
            mAnswer.FileName := mLocation.FileName;
            mAnswer.Line := mLocation.Line;
            mAnswer.Character := mLocation.Character;
          except
            on E: Exception do
            begin
              FailAnswer(E, mAnswer);
            end;
          end;
          if not mSlot.Complete(mAnswer) then
          begin
            QueueLateGoto(mOrigin, mAnswer);
          end;
        except
          // Hintergrund-Thread: nie eine Ausnahme nach außen.
          on Exception do
          begin
          end;
        end;
      finally
        // Nie am Manager: Der Stopp im Hintergrund wartet auf dieses Signal, bevor er die Sitzung freigibt.
        mSignals.EndServerCommand;
      end;
    end;
end;

/// <summary>Aus dem Hintergrund-Thread: späten Symbolhinweis über TDpccMainThread.Queue in ACache merken; ein Fehler
/// kommt nur als gedrosselte Zeile ins Protokoll.</summary>
procedure QueueLateHint(const ACache: IDpccHintCache; const AKey: TDpccHintKey; const AAnswer: TDpccAnswer);
var
  mCache: IDpccHintCache;
  mKey: TDpccHintKey;
  mAnswer: TDpccAnswer;
begin
  mCache := ACache;
  mKey := AKey;
  mAnswer := AAnswer;
  TDpccMainThread.Queue(TDpccFeature.Hover,
    procedure
    begin
      if mAnswer.Error = TDpccAnswerError.None then
      begin
        mCache.Store(mKey, mAnswer.Text, TThread.GetTickCount64);
      end
      else
      begin
        TDpccGuard.ReportProviderSlow(cHintLateName, mAnswer.ErrorText);
      end;
    end);
end;

/// <summary>Arbeit des Hintergrund-Threads für den Symbolhinweis der IDE: HoverAt ohne Abgleich (Sync vorher im
/// Hauptthread), Antwort in ASlot; kam sie zu spät, kommt sie in ACache. Hält nie den Manager.</summary>
function HintWork(ASession: TLspSession; const ASignals: IDpccIdleSignals; const ASlot: IDpccAnswerSlot;
  const ACache: IDpccHintCache; const APlace: TDpccHintPlace): TProc;
var
  mSession: TLspSession;
  mSignals: IDpccIdleSignals;
  mSlot: IDpccAnswerSlot;
  mCache: IDpccHintCache;
  mKey: TDpccHintKey;
  mFileName: string;
  mLine, mCharacter: Integer;
begin
  mSession := ASession;
  mSignals := ASignals;
  mSlot := ASlot;
  mCache := ACache;
  mKey := APlace.Key;
  mFileName := APlace.FileName;
  mLine := APlace.Line;
  mCharacter := APlace.Character;
  Result :=
    procedure
    var
      mAnswer: TDpccAnswer;
    begin
      try
        try
          TThread.NameThreadForDebugging('dpcc.HintText');
          mAnswer := Default(TDpccAnswer);
          try
            mAnswer.Text := mSession.HoverAt(mFileName, mLine, mCharacter, TDpccLateAnswers.cMaxAgeMs);
            mAnswer.Found := True;
          except
            on E: Exception do
            begin
              FailAnswer(E, mAnswer);
            end;
          end;
          if not mSlot.Complete(mAnswer) then
          begin
            QueueLateHint(mCache, mKey, mAnswer);
          end;
        except
          // Hintergrund-Thread: nie eine Ausnahme nach außen.
          on Exception do
          begin
          end;
        end;
      finally
        // Nie am Manager: Der Stopp im Hintergrund wartet auf dieses Signal, bevor er die Sitzung freigibt.
        mSignals.EndServerCommand;
      end;
    end;
end;

{ TDpccCodeInsightManager }

constructor TDpccCodeInsightManager.Create(const AAdapters: TDpccCodeInsightAdapters);
begin
  inherited Create(AAdapters);
  // Gemeinsamer Pufferstand für Probleme und Inlay-Hints.
  TDpccEditorSnapshots.Install;
  FEditors := TDpccCodeInsightEditors.Create(EditorHooks);
  FHintCache := TDpccHintCache.Create;
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
      // Hover und Tippen: Hat die IDE den Manager abgeschaltet (SetEnabled), startet kein Server; eine laufende
      // Sitzung bleibt nutzbar. EnsureSession wartet nie.
      if FEnabled then
      begin
        Result := EnsureSession;
      end
      else
      begin
        Result := RunningSession <> nil;
      end;
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
  // Öffnen beim Tippen (L5): keine zweite Liste neben der offenen der IDE.
  Result.IdeListOpen :=
    function: Boolean
    begin
      Result := IdeCompletionListOpen;
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
  // Noch ausstehende Sprünge und Hinweise gelten nicht mehr; ihre Threads wartet FThreads.StopAll ab.
  Inc(FGotoGeneration);
  FHintSlot := nil;
  if FHintCache <> nil then
  begin
    FHintCache.Clear;
  end;
  // Hält die Beobachter-Threads an; erst danach darf der Sammler weg.
  FFolderWatcher := nil;
  FreeAndNil(FFileChanges);
  // Vor der Sitzung: wartet auf laufende Anfragen und meldet Tasten und Beobachter ab.
  if FEditors <> nil then
  begin
    FEditors.ReleaseViews;
  end;
  FOnServerChanged := nil;
  // Start abbrechen, Sitzung im Hintergrund stoppen und begrenzt (cUnloadWaitMs) auf alle Start- und Stopp-Threads
  // warten: Nach dem Entladen darf keiner mehr laufen.
  ShutdownSession;
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

procedure TDpccCodeInsightManager.StartWork(const AWork: TProc);
begin
  // Vor dem Start: Der Thread beendet das Signal, auch wenn er sofort fertig ist.
  FSignals.BeginServerCommand;
  try
    FThreads.Start(AWork);
  except
    FSignals.EndServerCommand;
    raise;
  end;
end;

function TDpccCodeInsightManager.ServerHint(const APlace: TDpccHintPlace; out ASource: string): string;
var
  mAnswer: TDpccAnswer;
begin
  Result := '';
  // Kurz zuvor beantwortet oder nachgereicht: sofort, ohne Server.
  if FHintCache.Lookup(APlace.Key, TThread.GetTickCount64, Result) then
  begin
    ASource := 'gemerkt';
    Exit;
  end;
  // Läuft die Anfrage für dasselbe Wort noch, auf sie warten statt eine zweite zu stellen.
  if (FHintSlot = nil) or FHintSlot.Done or not FHintKey.SameAs(APlace.Key) then
  begin
    // Abgleich im Hauptthread: braucht den Puffertext, wartet nicht auf den Server.
    FSession.Sync(APlace.FileName, APlace.Text);
    FHintSlot := TDpccAnswerSlot.Create(TThread.GetTickCount64);
    FHintKey := APlace.Key;
    StartWork(HintWork(FSession, FSignals, FHintSlot, FHintCache, APlace));
  end;
  if not FHintSlot.Await(TDpccLateAnswers.cWaitMs) then
  begin
    // Die IDE bekommt '' (kein Hinweis); die Antwort kommt in FHintCache für den nächsten Aufruf.
    TDpccGuard.ReportProviderSlow(cHintSlowName, Format('keine Antwort innerhalb von %d ms, Hinweis wird gemerkt',
      [TDpccLateAnswers.cWaitMs]));
    ASource := 'kommt später';
    Exit;
  end;
  mAnswer := FHintSlot.Answer;
  case mAnswer.Error of
    TDpccAnswerError.None:
      begin
        Result := mAnswer.Text;
        FHintCache.Store(APlace.Key, Result, TThread.GetTickCount64);
        ASource := 'Server';
      end;
    TDpccAnswerError.Other:
      begin
        // Wie ein Fehler im Hauptthread: Meldung und Sicherung (GetHintText).
        raise Exception.Create(mAnswer.ErrorText);
      end;
  else
    begin
      // Beendeter Server oder fehlende Methode: erwartbar, zählt nicht für die Sicherung.
      raise ELspClientError.Create(mAnswer.ErrorText);
    end;
  end;
end;

function TDpccCodeInsightManager.GetHintText(HintLine, HintCol: Integer): string;
var
  mView: IOTAEditView;
  mActivity: IInterface;
  mPlace: TDpccHintPlace;
  mSource: string;
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
    // Hauptschalter und Datei vor dem Start prüfen; EnsureSession wartet nie (ohne Sitzung kein Hinweis).
    if (mView <> nil) and (mView.Buffer <> nil) and FEnabled and Handles(mView.Buffer.FileName) and EnsureSession
      and TDpccCodeInsightQueries.HintPlace(mView, HintLine, HintCol, mPlace) then
    begin
      // Der Server im Hintergrund, höchstens cWaitMs; der Wert im Debugger wie bisher sofort.
      Result := TDpccCodeInsightQueries.HintWithDebugValue(ServerHint(mPlace, mSource), mPlace);
      Diagnose(Format('Hover (%s), Zeile %d, Spalte %d (Cursor %d/%d): %d Zeichen (%s)',
        [ExtractFileExt(mPlace.FileName), HintLine, HintCol, mView.CursorPos.Line, mView.CursorPos.Col,
        Length(Result), mSource]));
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
  mOutcome: TDpccGotoOutcome;
  mFileName: string;
  mLine: Integer;
  mAnswer: TDpccGotoAnswer;
begin
  mActivity := TDpccActivity.Scope('Gehe zu Definition');
  // Die IDE fragt nur den gewählten Anbieter und reicht nie an einen anderen weiter (ToolsAPI). Laut ToolsAPI
  // meldet False einen Fehlschlag („Datei "" nicht gefunden“); True mit AFileName = '' bricht still ab. Deshalb
  // immer True, mit Datei und Zeile nur bei einem Ziel (TDpccGotoDefinition.Answer).
  mFileName := '';
  mLine := 0;
  // Durch die Sicherung abgeschaltet (#493): still abbrechen.
  if TDpccGuard.Disabled(TDpccFeature.GoToDefinition) then
  begin
    mOutcome := TDpccGotoOutcome.Disabled;
  end
  else
  begin
    Diagnose(Format('GotoDefinition(Index %d) aufgerufen', [Index]));
    try
      NoticeIfSelected;
      mView := TDpccCodeInsightQueries.CurrentEditView;
      if (mView = nil) or (mView.Buffer = nil) then
      begin
        Diagnose('Gehe zu Definition: keine Editoransicht');
        mOutcome := TDpccGotoOutcome.NoView;
      end
      else if not FEnabled or not Handles(mView.Buffer.FileName) then
      begin
        // Hauptschalter aus oder keine Datei von dpcc: ohne Sitzung wie bisher, kein Start.
        Diagnose('Gehe zu Definition: dpcc bedient die Datei nicht');
        mOutcome := TDpccGotoOutcome.NoSession;
      end
      else if not EnsureSession then
      begin
        // Der Start läuft im Hintergrund; bis dahin wie ohne Server.
        if StartPending then
        begin
          Diagnose('Gehe zu Definition: dpcc startet noch');
        end;
        mOutcome := TDpccGotoOutcome.NoSession;
      end
      else if not FSession.Offers(cDefinitionMethod) then
      begin
        // Server ohne Sprungziele (ältere Fassung): still abbrechen, die IDE springt nicht.
        Diagnose('Gehe zu Definition: Server bietet keine Definitionen');
        mOutcome := TDpccGotoOutcome.NotOffered;
      end
      else
      begin
        // Im Hintergrund gefragt, höchstens cWaitMs gewartet; später kommt der Sprung über LateGoto.
        mOutcome := AskDefinition(mView, Index, mFileName, mLine);
      end;
    except
      on E: ELspMethodNotFound do
      begin
        // Erst jetzt als fehlend erkannt (-32601): wie oben.
        Diagnose('Gehe zu Definition: ' + E.Message);
        mOutcome := TDpccGotoOutcome.NotOffered;
      end;
      on E: ELspClientError do
      begin
        // Beendeter Server beim Abgleich: erwartbar, keine Meldung. (Eine langsame Antwort ist kein Fehler mehr: Sie
        // wird nachgereicht, AskDefinition.)
        Diagnose('Gehe zu Definition: ' + E.Message);
        mOutcome := TDpccGotoOutcome.TimedOut;
      end;
      on E: Exception do
      begin
        mOutcome := TDpccGotoOutcome.Failed;
        ReportError('Gehe zu Definition: ' + E.Message);
        ReportFailure(TDpccFeature.GoToDefinition, E);
      end;
    end;
  end;
  mAnswer := TDpccGotoDefinition.Answer(mOutcome, mFileName, mLine);
  AFileName := mAnswer.FileName;
  ALineNum := mAnswer.Line;
  Result := mAnswer.Result;
end;

function TDpccCodeInsightManager.AskDefinition(const AView: IOTAEditView; AIndex: Integer; out AFileName: string;
  out ALine: Integer): TDpccGotoOutcome;
var
  mPlace: TDpccGotoPlace;
  mSlot: IDpccAnswerSlot;
  mAnswer: TDpccAnswer;
  mTarget: string;
begin
  AFileName := '';
  ALine := 0;
  if not TDpccCodeInsightQueries.GotoPlace(AView,
    procedure(AMessage: string)
    begin
      Diagnose(AMessage);
    end, mPlace) then
  begin
    Exit(TDpccGotoOutcome.NoView);
  end;
  // Jeder Sprungwunsch macht ältere, noch ausstehende ungültig.
  Inc(FGotoGeneration);
  mPlace.Origin.Generation := FGotoGeneration;
  // Abgleich im Hauptthread: braucht den Puffertext, wartet nicht auf den Server.
  FSession.Sync(mPlace.Origin.FileName, mPlace.Text);
  mSlot := TDpccAnswerSlot.Create(mPlace.Origin.StartedMs);
  StartWork(GotoWork(FSession, FSignals, mSlot, mPlace));
  if not mSlot.Await(TDpccLateAnswers.cWaitMs) then
  begin
    // Die Anfrage läuft weiter (nicht abgebrochen); die IDE bricht still ab, ohne Hinweis im Meldungsfenster.
    TDpccGuard.ReportProviderSlow(cGotoSlowName, Format('keine Antwort innerhalb von %d ms, Sprung wird nachgereicht',
      [TDpccLateAnswers.cWaitMs]));
    Diagnose(TDpccCodeInsightQueries.GotoNote(AIndex, mPlace, 'kommt später'));
    Exit(TDpccGotoOutcome.Deferred);
  end;
  mAnswer := mSlot.Answer;
  case mAnswer.Error of
    TDpccAnswerError.MethodNotFound:
      begin
        // Erst jetzt als fehlend erkannt (-32601): Server ohne Sprungziele.
        Diagnose('Gehe zu Definition: ' + mAnswer.ErrorText);
        Exit(TDpccGotoOutcome.NotOffered);
      end;
    TDpccAnswerError.ClientError:
      begin
        // Beendeter Server: erwartbar, keine Meldung.
        Diagnose('Gehe zu Definition: ' + mAnswer.ErrorText);
        Exit(TDpccGotoOutcome.TimedOut);
      end;
    TDpccAnswerError.Other:
      begin
        // Wie ein Fehler im Hauptthread: Meldung und Sicherung (GotoDefinition).
        raise Exception.Create(mAnswer.ErrorText);
      end;
  end;
  Result := TDpccGotoOutcome.NotFound;
  mTarget := 'kein Ziel';
  if TDpccCodeInsightQueries.TargetOf(mAnswer) then
  begin
    AFileName := mAnswer.FileName;
    ALine := mAnswer.Line;
    Result := TDpccGotoOutcome.Found;
    mTarget := Format('%s, Zeile %d', [ExtractFileExt(AFileName), ALine + 1]);
  end;
  Diagnose(TDpccCodeInsightQueries.GotoNote(AIndex, mPlace, mTarget));
end;

procedure TDpccCodeInsightManager.LateGoto(const AOrigin: TDpccGotoOrigin; const AAnswer: TDpccAnswer);
var
  mActivity: IInterface;
  mVerdict: TDpccGotoVerdict;
  mFileName: string;
  mLine, mCharacter: Integer;
begin
  if FShutDown or not FEnabled or TDpccGuard.Disabled(TDpccFeature.GoToDefinition) then
  begin
    Exit;
  end;
  mActivity := TDpccActivity.Scope('Gehe zu Definition (nachgereicht)');
  if AAnswer.Error <> TDpccAnswerError.None then
  begin
    // Auch ein spätes Zeitlimit nicht stumm: gedrosselt ins Protokoll.
    TDpccGuard.ReportProviderSlow(cGotoLateName, AAnswer.ErrorText);
  end;
  mVerdict := TDpccLateGoto.Verdict(AOrigin, TDpccCodeInsightQueries.GotoNow(FGotoGeneration),
    TDpccCodeInsightQueries.TargetOf(AAnswer), TDpccLateAnswers.cMaxAgeMs);
  Diagnose(Format('Gehe zu Definition nachgereicht nach %d ms: %s',
    [Int64(TThread.GetTickCount64 - AOrigin.StartedMs), TDpccLateGoto.VerdictText(mVerdict)]));
  if mVerdict <> TDpccGotoVerdict.Jump then
  begin
    Exit;
  end;
  // Wie die IDE bei einer rechtzeitigen Antwort: Datei zeigen (nur öffnen, wenn nötig), Cursor aufs Ziel.
  mFileName := AAnswer.FileName;
  mLine := AAnswer.Line;
  mCharacter := AAnswer.Character;
  TDpccGuard.RunIde(
    procedure
    begin
      TDpccIdeNavigation.GoToLocation(mFileName, mLine, mCharacter);
    end);
end;

/// <summary>Zeile in der Meldungsansicht, Gruppe „dpcc“; nur im Hauptthread.</summary>
procedure MessageLine(const AText: string);
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mGroup := mMessages.GetGroup('dpcc');
  if mGroup = nil then
  begin
    mGroup := mMessages.AddMessageGroup('dpcc');
  end;
  mMessages.AddTitleMessage(AText, mGroup);
end;

procedure TDpccCodeInsightManager.NoticeIfSelected;
var
  mView: IOTAEditView;
begin
  // Schnell, solange schon gezeigt: AllowCodeInsight ruft es bei jeder Taste.
  if not TDpccProviderNotice.Pending then
  begin
    Exit;
  end;
  mView := TDpccCodeInsightQueries.CurrentEditView;
  if (mView = nil) or (mView.Buffer = nil) or IdeListReachable(mView.Buffer.FileName) then
  begin
    Exit;
  end;
  if TDpccProviderNotice.TakeFirst then
  begin
    MessageLine(TDpccProviderNotice.Text(TDpccTextLanguage.Current));
    Diagnose('Hinweis: dpcc ist der gewählte Code-Insight-Anbieter');
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

{ IOTACodeInsightManagerEnvOptions }

function TDpccCodeInsightManager.IsEnableErrorInsightVisible: Boolean;
begin
  Result := True;
end;

function TDpccCodeInsightManager.IsCodeCompleteAutoParensVisible: Boolean;
begin
  Result := True;
end;

function TDpccCodeInsightManager.IsCodeCompleteAutoInvokeVisible: Boolean;
begin
  Result := True;
end;

function TDpccCodeInsightManager.IsCodeCompleteHistoryVisible: Boolean;
begin
  Result := True;
end;

function TDpccCodeInsightManager.IsCodeCompleteShowReservedWordsVisible: Boolean;
begin
  Result := True;
end;

function TDpccCodeInsightManager.IsCodeParametersVisible: Boolean;
begin
  Result := True;
end;

function TDpccCodeInsightManager.IsEvalHintsVisible: Boolean;
begin
  Result := True;
end;

function TDpccCodeInsightManager.IsDeclInfoVisible: Boolean;
begin
  Result := True;
end;

function TDpccCodeInsightManager.IsToolTipHelpInsightVisible: Boolean;
begin
  Result := True;
end;

function TDpccCodeInsightManager.IsEnableAutoCompletionVisible: Boolean;
begin
  Result := True;
end;

function TDpccCodeInsightManager.IsBlockWrapStyleVisible: Boolean;
begin
  Result := True;
end;

function TDpccCodeInsightManager.GetCodeInsightUIName: string;
begin
  Result := cManagerName;
end;

/// <summary>Wahl im Dialog weiterreichen; während des Abbaus nicht mehr (die IDE meldet beim Abmelden des Managers
/// unter Umständen ManagerDisabled).</summary>
procedure ReportProviderChoice(ASelected: Boolean);
var
  mHandler: TProc<Boolean>;
begin
  if TDpccShutdown.Signalled then
  begin
    Exit;
  end;
  mHandler := TDpccCodeInsightManager.OnProviderChoice;
  if Assigned(mHandler) then
  begin
    try
      mHandler(ASelected);
    except
      on E: Exception do
        TDpccGuard.Log('Wahl des Code-Insight-Anbieters: ' + TDpccGuard.ErrorText(E));
    end;
  end;
end;

procedure TDpccCodeInsightManager.ManagerDisabled;
begin
  Diagnose('ManagerDisabled');
  ReportProviderChoice(False);
end;

procedure TDpccCodeInsightManager.ManagerEnabled;
begin
  Diagnose('ManagerEnabled');
  ReportProviderChoice(True);
end;

function TDpccCodeInsightManager.GetEnabled: Boolean;
begin
  Result := FEnabled;
end;

procedure TDpccCodeInsightManager.SetEnabled(Value: Boolean);
begin
  FEnabled := Value;
  Diagnose('SetEnabled(' + BoolToStr(Value, True) + ')');
  if not Value and not FShutDown then
  begin
    // Nie im Hauptthread warten: Start abbrechen, Sitzung im Hintergrund stoppen.
    StopSessionAsync('SetEnabled(False)');
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
    // Die IDE fragt nur den gewählten Anbieter: Dann einmal der Hinweis (NAV).
    NoticeIfSelected;
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
  mView: IOTAEditView;
begin
  mActivity := TDpccActivity.Scope('Vervollständigung öffnen');
  // False: Die IDE zeigt keine eigene Liste; unser Popup übernimmt (#407, #410).
  Result := False;
  Diagnose(Format('InvokeCodeCompletion(%d, %d Zeichen)', [Ord(HowInvoked), Length(Str)]));
  try
    // Start nur hier im Hauptthread und nur für Dateien, die dpcc bei Hauptschalter an bedient; er läuft im
    // Hintergrund, die Quellen bekommen die laufende Sitzung. Ohne Server liefern die übrigen Quellen trotzdem.
    mView := TDpccCodeInsightQueries.CurrentEditView;
    if FEnabled and (mView <> nil) and (mView.Buffer <> nil) and Handles(mView.Buffer.FileName) then
    begin
      EnsureSession;
    end;
    Completion.Invoke(mView, HowInvoked <> itManual);
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
  mView: IOTAEditView;
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
    // Start nur hier im Hauptthread, nur bei Hauptschalter an und für Dateien von dpcc; er läuft im Hintergrund.
    mView := TDpccCodeInsightQueries.CurrentEditView;
    if FEnabled and (mView <> nil) and (mView.Buffer <> nil) and Handles(mView.Buffer.FileName) then
    begin
      EnsureSession;
    end;
    FEditors.Signature.Invoke(mView);
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
        // Stößt den Start nur an; er läuft im Hintergrund.
        EnsureSession;
      end;
    end
    else
    begin
      // Ein Start, der noch läuft, wird verworfen (sein Ergebnis im Hintergrund gestoppt).
      CancelStart('Hauptschalter aus');
      if FEditors <> nil then
      begin
        // HandlesFile liest den Schalter bei jedem Aufruf: Die IDE nimmt ab jetzt wieder ihre Code Insight. Der
        // Server bleibt (#407): Die Optionsseite startet ihn für Kennzahlen ohnehin, und schnelles Umschalten zählte
        // jeden Start als Neustart mit Meldung.
        FEditors.CloseViews;
      end;
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
