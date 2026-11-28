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
// OnProviderChoice weiter (Betriebsart, dpcc.IDE.Foundation.InsightSwitch). Seit CI-OPT blenden die Is…Visible-Abfragen
// aus, was dpcc auf seiner Seite regelt (Klammern, Automatisch aufrufen, Verlauf, reservierte Wörter, Code-Parameter,
// Ausdrucksauswertung, Symbol-Insight, Help Insight), und IOTACodeInsightManagerEnvOptions270 „LSP-Konfiguration
// generieren“. Blockvervollständigung, Umbruchstil, Vorlagen, Hinweise, „Unvollst. Eigenschaften“, „Programmierhilfe“
// und Error Insight bleiben sichtbar.
// Strg+Klick und Symbolhinweis der IDE ohne Einfrieren (dpcc.Core.Lsp.LateAnswers): Der Hauptthread gleicht den
// Puffer ab und startet die Anfrage in einem Hintergrund-Thread (FThreads, Leerlauf-Signal für den Stopp); er wartet
// höchstens TDpccLateAnswers.cWaitMs. Kommt das Sprungziel später, antwortet GotoDefinition still (True ohne Datei),
// und LateGoto springt selbst, wenn es noch passt (dieselbe Datei, Cursor im Bezeichner der Klickstelle oder der
// Ausgangsstelle, kein neuerer Sprungwunsch, höchstens cMaxAgeMs = 10 s vom Klick bis zur Ankunft der Antwort im
// Hintergrund-Thread). Ein später Symbolhinweis kommt in FHintCache; der nächste Aufruf der IDE für dasselbe Wort
// antwortet dann sofort. Nachgereicht wird nur über TDpccMainThread.Queue; der Eintrag sucht den lebenden Manager erst
// im Hauptthread (LiveManagerObject). Wartezeiten über cWaitMs stehen gedrosselt im Protokoll
// (TDpccGuard.ReportProviderSlow).
// Rückmeldung zu Sprüngen: Jeder Sprungwunsch ohne Ziel schreibt genau eine Zeile ins dpcc.log (TDpccGuard.Log,
// TDpccGotoLog: Ausgang samt Grund des Servers aus dpcc/noTarget, Dauer, Datei ohne Pfad, Zeile:Spalte); ein
// gelungener nur mit Diagnose = 1, ein nachgereichter immer. Den Grund (Unit nur als Package, nicht gefunden, Name
// nicht aufgelöst, keine Antwort …) zeigt das Meldungsfenster (Gruppe dpcc, TDpccGotoNotice), dieselbe Meldung nicht
// mehrfach hintereinander; verworfene späte Antworten (Cursor bewegt, andere Datei, neuer Sprung) nur im Protokoll.
// Startet der Server noch, merkt sich GotoDefinition den Wunsch (FStartGoto, Meldung „dpcc startet noch“);
// SessionStartDone fragt ihn nach dem Start im Hintergrund, die Antwort läuft über LateGoto mit derselben Prüfung.
// Ablaufprotokoll (LOG1, dpcc.Core.Diagnostics.Flow; „Ablauf protokollieren (Log)“ bzw. Diagnose = 1, ohne Neustart):
// Jeder Einstieg der IDE (GotoDefinition, GetHintText, InvokeCodeCompletion, InvokeParameterCodeInsight, eigene Tasten)
// beginnt eine Kennung und schreibt Eintritt, jeden frühen Ausstieg mit Grund und das Ergebnis an die IDE. Beim Sprung
// geht die Kennung mit der Stelle (TDpccGotoOrigin.FlowId) in den Hintergrund: Die Sitzung schreibt die Antwort auf
// declaration, das Urteil von OnTarget und definition, LateGoto und GotoLog den späteren Ausgang. Die früheren
// Diagnosezeilen dieser Einstiege sind darin aufgegangen; ausgeschaltet wird kein Text gebaut.

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
    IOTACodeInsightSelection, IOTACodeInsightManagerEnvOptions, IOTACodeInsightManagerEnvOptions270)
  private type
    /// <summary>Was ein Sprungwunsch für Protokoll und Rückmeldung liefert.</summary>
    TGotoReport = record
      /// <summary>Stelle des Wunschs; gilt nur mit HasPlace (nach GotoPlace).</summary>
      Place: TDpccGotoPlace;
      HasPlace: Boolean;
      /// <summary>Grund des Servers ohne Ziel (NotFound).</summary>
      NoTarget: TDpccNoTarget;
      /// <summary>Fehlertext (TimedOut, NotOffered, Failed) bzw. Grund bei NoSession; '' ohne.</summary>
      Detail: string;
      /// <summary>NoSession: dpcc ist für die Datei zuständig, aber kein Server läuft (sonst Hauptschalter aus,
      /// Manager abgeschaltet oder Datei nicht von dpcc).</summary>
      Responsible: Boolean;
      /// <summary>Kennung im Ablaufprotokoll (LOG1); 0 = nicht protokolliert.</summary>
      Flow: Integer;
    end;
  private
    /// <summary>Laufende Nummer der Sprungwünsche: Ein nachgereichtes Ziel gilt nur für den neuesten. Nur
    /// Hauptthread.</summary>
    FGotoGeneration: Cardinal;
    /// <summary>Sprungwunsch, der auf den Start der Sitzung wartet (Origin.Generation 0 = keiner). Nur Hauptthread.
    /// </summary>
    FStartGoto: TDpccGotoPlace;
    /// <summary>Rückmeldungen zu Sprüngen im Meldungsfenster, gegen Fluten (nur Hauptthread).</summary>
    FGotoNotices: TDpccNoticeRepeat;
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
    /// die Antwort später kommt (LateGoto). Unerwartete Fehler kommen als Exception (AReport ist dann schon gefüllt).
    /// </summary>
    function AskDefinition(const AView: IOTAEditView; AIndex: Integer; out AFileName: string;
      out ALine: Integer; var AReport: TGotoReport): TDpccGotoOutcome;
    /// <summary>Der Server startet noch: Stelle des Wunschs an AView merken (FStartGoto); Starting, oder NoView
    /// außerhalb des Puffers.</summary>
    function RememberStartGoto(const AView: IOTAEditView; var AReport: TGotoReport): TDpccGotoOutcome;
    /// <summary>Gemerkten Sprungwunsch nach dem Start fragen, wenn er noch passt (Datei, Cursor, Alter, Text); die
    /// Antwort geht wie eine nachgereichte über LateGoto. Sonst verwerfen (Zeile im Protokoll).</summary>
    procedure ResumeStartGoto(const APlace: TDpccGotoPlace; AAdopted: Boolean);
    /// <summary>Nachgereichtes Sprungziel (Hauptthread): springen, wenn es noch passt, sonst verwerfen; jeder Ausgang
    /// als Zeile im dpcc.log, ein Grund ohne Ziel auch im Meldungsfenster.</summary>
    procedure LateGoto(const AOrigin: TDpccGotoOrigin; const AAnswer: TDpccAnswer);
    /// <summary>Ausgang eines Sprungwunschs aus GotoDefinition: Zeile im dpcc.log (ohne Ziel immer, mit Ziel nur mit
    /// Diagnose = 1) und Rückmeldung im Meldungsfenster. Deferred und Starting schreiben ihre Zeile später.</summary>
    procedure FinishGoto(AOutcome: TDpccGotoOutcome; const AReport: TGotoReport; const AView: IOTAEditView;
      AStartedMs: UInt64);
    /// <summary>Zeile „Gehe zu Definition: AOutcome nach n ms, Datei Zeile:Spalte (Maus|Cursor)“ ins dpcc.log; nur
    /// bei AAlways oder mit Diagnose = 1.</summary>
    procedure GotoLog(AAlways: Boolean; const AOutcome: string; const AOrigin: TDpccGotoOrigin);
    /// <summary>AText im Meldungsfenster (Gruppe dpcc), dieselbe Meldung nicht mehrfach hintereinander.</summary>
    procedure GotoNotice(const AText: string);
    /// <summary>Für GotoPlace: Zeilen unter der Kennung AFlow ins Ablaufprotokoll (LOG1); nil bei AFlow = 0, dann
    /// baut GotoPlace keinen Text.</summary>
    function GotoPlaceLog(AFlow: Integer): TProc<string>;
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
  protected
    /// <summary>Ein Start ist fertig (übernommen oder nicht): einen gemerkten Sprungwunsch fragen oder verwerfen.
    /// </summary>
    procedure SessionStartDone(AAdopted: Boolean); override;
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
    { IOTACodeInsightManagerEnvOptions270 }
    function IsGenerateVSCodeInfo: Boolean;
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
  dpcc.Core.Diagnostics.Flow,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Foundation.EditorSnapshot,
  dpcc.IDE.Foundation.EditorBuffer,
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

/// <summary>Zeile AText des Sprungs AFlow im Ablaufprotokoll (LOG1); nichts bei AFlow = 0.</summary>
procedure FlowStep(AFlow: Integer; const AText: string);
begin
  if AFlow > 0 then
  begin
    TDpccFlow.Step(AFlow, TDpccFlowArea.Jump, AText);
  end;
end;

/// <summary>Zeile AText der Aktion AFlow im Bereich AArea (Ablaufprotokoll, LOG1); nichts bei AFlow = 0.</summary>
procedure AreaStep(AArea: TDpccFlowArea; AFlow: Integer; const AText: string);
begin
  if AFlow > 0 then
  begin
    TDpccFlow.Step(AFlow, AArea, AText);
  end;
end;

/// <summary>Zusatz fürs Ablaufprotokoll, wenn der Symbolhinweis der IDE leer bleibt; '' mit Text.</summary>
function HintEmptyReason(const AHint, ASource: string): string;
begin
  Result := '';
  if AHint <> '' then
  begin
    Exit;
  end;
  if ASource = 'kommt später' then
  begin
    Result := '; leer: Antwort nicht binnen der Wartezeit, gemerkt für den nächsten Aufruf';
  end
  else
  begin
    Result := '; leer: kein Hover-Text an der Stelle';
  end;
end;

/// <summary>Datei der Ansicht ohne Ordner fürs Ablaufprotokoll; „-“ ohne Ansicht.</summary>
function ViewFileText(const AView: IOTAEditView): string;
begin
  Result := '-';
  if (AView <> nil) and (AView.Buffer <> nil) then
  begin
    Result := TDpccFlow.FileText(AView.Buffer.FileName);
  end;
end;

/// <summary>„Maus“ (Strg+Klick) bzw. „Cursor“ als Quelle der Stelle.</summary>
function PlaceSource(AMouse: Boolean): string;
begin
  if AMouse then
  begin
    Result := 'Maus';
  end
  else
  begin
    Result := 'Cursor';
  end;
end;

/// <summary>Warum dpcc die Datei AFileName nicht bedient (Ablaufprotokoll, LOG1), in der Reihenfolge der Prüfung von
/// FEnabled und Handles.</summary>
function NotHandledReason(AShutDown, AEnabled: Boolean; const AFileName: string): string;
begin
  if AShutDown then
  begin
    Result := 'Manager abgebaut';
  end
  else if not AEnabled then
  begin
    Result := 'Manager von der IDE abgeschaltet (SetEnabled(False))';
  end
  else if not TDpccIdeSettings.Current.Enabled then
  begin
    Result := 'Hauptschalter aus';
  end
  else if TDpccGuard.Disabled(TDpccFeature.Completion) then
  begin
    Result := 'Vervollständigung von der Sicherung abgeschaltet';
  end
  else
  begin
    Result := 'Dateiart nicht von dpcc (' + ExtractFileExt(AFileName) + ')';
  end;
end;

/// <summary>Warum eine eigene Taste von dpcc nichts öffnet (Ablaufprotokoll, LOG1), in der Reihenfolge der Prüfung.
/// </summary>
function OwnKeyOffReason(AEnabled, AGuardOff: Boolean): string;
begin
  if not AEnabled then
  begin
    Result := 'Manager von der IDE abgeschaltet (SetEnabled(False))';
  end
  else if AGuardOff then
  begin
    Result := 'von der Sicherung abgeschaltet';
  end
  else
  begin
    Result := 'kein Server verfügbar';
  end;
end;

/// <summary>Ziel einer nachgereichten Antwort fürs Ablaufprotokoll: Stelle, „kein Ziel“ oder der Fehler.</summary>
function LateTargetText(const AAnswer: TDpccAnswer): string;
begin
  if AAnswer.Error <> TDpccAnswerError.None then
  begin
    Result := 'Fehler (' + AAnswer.ErrorText + ')';
  end
  else if TDpccCodeInsightQueries.TargetOf(AAnswer) then
  begin
    Result := TDpccFlow.PlaceText(AAnswer.FileName, AAnswer.Line + 1, AAnswer.Character);
  end
  else
  begin
    Result := 'keins';
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
      mNoTarget: TDpccNoTarget;
    begin
      try
        try
          TThread.NameThreadForDebugging('dpcc.GotoDefinition');
          mAnswer := Default(TDpccAnswer);
          try
            // Mit der Kennung des Ablaufprotokolls (LOG1): Die Sitzung schreibt declaration, OnTarget und definition.
            mAnswer.Found := mSession.GotoTargetAt(mOrigin.FileName, mLineText, mOrigin.AtLine - 1,
              mOrigin.AtCharacter, TDpccLateAnswers.cMaxAgeMs, mLocation, mNoTarget, mOrigin.FlowId);
            mAnswer.FileName := mLocation.FileName;
            mAnswer.Line := mLocation.Line;
            mAnswer.Character := mLocation.Character;
            mAnswer.NoTarget := mNoTarget;
          except
            on E: Exception do
            begin
              FailAnswer(E, mAnswer);
            end;
          end;
          // Das Alter einer späten Antwort zählt bis hier, nicht bis zur Zustellung im Hauptthread.
          mAnswer.ArrivedMs := TThread.GetTickCount64;
          if not mSlot.Complete(mAnswer) then
          begin
            if mOrigin.FlowId > 0 then
            begin
              TDpccFlow.Step(mOrigin.FlowId, TDpccFlowArea.Jump, Format('Antwort nach %d ms, der Hauptthread wartet ' +
                'nicht mehr: wird nachgereicht', [Int64(mAnswer.ArrivedMs - mOrigin.StartedMs)]));
            end;
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
            mAnswer.Text := mSession.HoverAt(mFileName, mLine, mCharacter, TDpccLateAnswers.cHintTimeoutMs);
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
  FStartGoto := Default(TDpccGotoPlace);
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
  mSource, mWhy: string;
  mFlow, mWordStart, mWordEnd: Integer;
begin
  mActivity := TDpccActivity.Scope('Symbolhinweis');
  Result := '';
  // Ablaufprotokoll (LOG1): je Aufruf der IDE eine Kennung; 0 = nicht protokolliert.
  mFlow := TDpccFlow.Start(TDpccFlowArea.Hover);
  // Durch die Sicherung abgeschaltet (#493); eigener Tooltip (#442): die IDE zeigt keinen
  // zweiten.
  if TDpccGuard.Disabled(TDpccFeature.Hover) then
  begin
    AreaStep(TDpccFlowArea.Hover, mFlow, 'Eintritt GetHintText: Ende, Hover ist von der Sicherung abgeschaltet');
    Exit;
  end;
  if TDpccIdeSettings.Current.HoverTooltip then
  begin
    if mFlow > 0 then
    begin
      AreaStep(TDpccFlowArea.Hover, mFlow, Format('Eintritt GetHintText(%d, %d): Ende, eigener Tooltip an (die IDE ' +
        'bekommt keinen Hinweis)', [HintLine, HintCol]));
    end;
    Exit;
  end;
  if mFlow > 0 then
  begin
    AreaStep(TDpccFlowArea.Hover, mFlow, Format('Eintritt GetHintText(%d, %d)', [HintLine, HintCol]));
  end;
  try
    mView := TDpccCodeInsightQueries.CurrentEditView;
    // Hauptschalter und Datei vor dem Start prüfen; EnsureSession wartet nie (ohne Sitzung kein Hinweis). Dieselbe
    // Reihenfolge wie früher in einer Bedingung; der erste Grund steht im Ablaufprotokoll.
    mWhy := '';
    if (mView = nil) or (mView.Buffer = nil) then
    begin
      mWhy := 'keine Editoransicht';
    end
    else if not FEnabled or not Handles(mView.Buffer.FileName) then
    begin
      mWhy := 'nicht zuständig, ' + NotHandledReason(FShutDown, FEnabled, mView.Buffer.FileName);
    end
    else if not EnsureSession then
    begin
      mWhy := 'keine Sitzung (Server startet noch oder läuft nicht)';
    end
    else if not TDpccCodeInsightQueries.HintPlace(mView, HintLine, HintCol, mPlace) then
    begin
      mWhy := 'Zeile außerhalb des Puffers';
    end;
    if mWhy <> '' then
    begin
      AreaStep(TDpccFlowArea.Hover, mFlow, 'Ende: ' + mWhy);
    end
    else
    begin
      // Der Server im Hintergrund, höchstens cWaitMs; der Wert im Debugger wie bisher sofort.
      Result := TDpccCodeInsightQueries.HintWithDebugValue(ServerHint(mPlace, mSource), mPlace);
      if mFlow > 0 then
      begin
        TDpccLateGoto.WordRange(mPlace.LineText, mPlace.Character, mWordStart, mWordEnd);
        AreaStep(TDpccFlowArea.Hover, mFlow, Format('Ergebnis an die IDE: %d Zeichen (%s), %s, Wort %s, Cursor ' +
          '%d/%d%s', [Length(Result), mSource, TDpccFlow.PlaceText(mPlace.FileName, HintLine, mPlace.Character),
          TDpccFlow.WordText(mPlace.LineText, mWordStart, mWordEnd), mView.CursorPos.Line, mView.CursorPos.Col,
          HintEmptyReason(Result, mSource)]));
      end;
    end;
  except
    on E: Exception do
    begin
      AreaStep(TDpccFlowArea.Hover, mFlow, 'Ende: Fehler ' + E.ClassName + ': ' + E.Message);
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
  mReport: TGotoReport;
  mStarted: UInt64;
begin
  mActivity := TDpccActivity.Scope('Gehe zu Definition');
  mStarted := TThread.GetTickCount64;
  // Die IDE fragt nur den gewählten Anbieter und reicht nie an einen anderen weiter (ToolsAPI). Laut ToolsAPI
  // meldet False einen Fehlschlag („Datei "" nicht gefunden“); True mit AFileName = '' bricht still ab. Deshalb
  // immer True, mit Datei und Zeile nur bei einem Ziel (TDpccGotoDefinition.Answer). Den Grund ohne Ziel nennt dpcc
  // selbst (FinishGoto).
  mFileName := '';
  mLine := 0;
  mReport := Default(TGotoReport);
  // Ablaufprotokoll (LOG1): eine Kennung für alle Zeilen dieses Sprungwunschs; 0 = nicht protokolliert.
  mReport.Flow := TDpccFlow.Start(TDpccFlowArea.Jump);
  // Durch die Sicherung abgeschaltet (#493): still abbrechen.
  if TDpccGuard.Disabled(TDpccFeature.GoToDefinition) then
  begin
    FlowStep(mReport.Flow, 'Ende: Gehe zu Definition ist von der Sicherung abgeschaltet (bis zum Neustart der IDE)');
    mOutcome := TDpccGotoOutcome.Disabled;
  end
  else
  begin
    try
      NoticeIfSelected;
      mView := TDpccCodeInsightQueries.CurrentEditView;
      if mReport.Flow > 0 then
      begin
        TDpccFlow.Step(mReport.Flow, TDpccFlowArea.Jump, Format('Eintritt IOTACodeInsightManager.GotoDefinition' +
          '(Index %d), Datei %s', [Index, ViewFileText(mView)]));
      end;
      if (mView = nil) or (mView.Buffer = nil) then
      begin
        FlowStep(mReport.Flow, 'Ende: keine Editoransicht');
        mOutcome := TDpccGotoOutcome.NoView;
      end
      else if not FEnabled or not Handles(mView.Buffer.FileName) then
      begin
        // Hauptschalter aus oder keine Datei von dpcc: ohne Sitzung wie bisher, kein Start.
        if mReport.Flow > 0 then
        begin
          FlowStep(mReport.Flow, 'Ende: nicht zuständig, ' + NotHandledReason(FShutDown, FEnabled,
            mView.Buffer.FileName));
        end;
        mReport.Detail := 'nicht zuständig (Hauptschalter, Manager abgeschaltet oder Datei nicht von dpcc)';
        mOutcome := TDpccGotoOutcome.NoSession;
      end
      else if not EnsureSession then
      begin
        // Der Start läuft im Hintergrund: Wunsch merken, nach dem Start fragen (SessionStartDone). Ohne Start (Sperre
        // nach Fehlschlag, nach Abstürzen angehalten) wie ohne Server.
        if StartPending then
        begin
          FlowStep(mReport.Flow, 'dpcc startet noch: Sprungwunsch gemerkt, gefragt wird nach dem Start');
          mOutcome := RememberStartGoto(mView, mReport);
        end
        else
        begin
          FlowStep(mReport.Flow, 'Ende: keine Sitzung (Server nicht gestartet, Start gesperrt oder nach Abstürzen ' +
            'angehalten)');
          mReport.Detail := 'keine Sitzung (Server nicht gestartet)';
          mReport.Responsible := True;
          mOutcome := TDpccGotoOutcome.NoSession;
        end;
      end
      else if not FSession.Offers(cDefinitionMethod) then
      begin
        // Server ohne Sprungziele (ältere Fassung): still abbrechen, die IDE springt nicht.
        FlowStep(mReport.Flow, 'Ende: Server bietet textDocument/definition nicht an');
        mOutcome := TDpccGotoOutcome.NotOffered;
      end
      else
      begin
        // Im Hintergrund gefragt, höchstens cWaitMs gewartet; später kommt der Sprung über LateGoto.
        mOutcome := AskDefinition(mView, Index, mFileName, mLine, mReport);
      end;
    except
      on E: ELspMethodNotFound do
      begin
        // Erst jetzt als fehlend erkannt (-32601): wie oben.
        FlowStep(mReport.Flow, 'Ende: Server ohne Sprungziele (-32601): ' + E.Message);
        mReport.Detail := TDpccGuard.MessageText(E.Message);
        mOutcome := TDpccGotoOutcome.NotOffered;
      end;
      on E: ELspClientError do
      begin
        // Beendeter Server beim Abgleich: erwartbar. (Eine langsame Antwort ist kein Fehler mehr: Sie wird
        // nachgereicht, AskDefinition.)
        FlowStep(mReport.Flow, 'Ende: Server getrennt beim Abgleich: ' + E.Message);
        mReport.Detail := TDpccGuard.MessageText(E.Message);
        mOutcome := TDpccGotoOutcome.TimedOut;
      end;
      on E: Exception do
      begin
        FlowStep(mReport.Flow, 'Ende: Fehler ' + E.ClassName + ': ' + E.Message);
        mOutcome := TDpccGotoOutcome.Failed;
        mReport.Detail := TDpccGuard.ErrorText(E);
        ReportError('Gehe zu Definition: ' + E.Message);
        ReportFailure(TDpccFeature.GoToDefinition, E);
      end;
    end;
  end;
  // Protokoll und Rückmeldung dürfen die Antwort an die IDE nie verhindern.
  try
    FinishGoto(mOutcome, mReport, mView, mStarted);
  except
    on E: Exception do
    begin
      TDpccGuard.Report(TDpccFeature.GoToDefinition, E);
    end;
  end;
  mAnswer := TDpccGotoDefinition.Answer(mOutcome, mFileName, mLine);
  if mReport.Flow > 0 then
  begin
    // Letzte Zeile der Kette (LOG1): was die IDE bekommt und ob das die Stelle des Klicks ist.
    TDpccFlow.Step(mReport.Flow, TDpccFlowArea.Jump, TDpccGotoLog.FlowResult(mOutcome, mAnswer, mReport.HasPlace,
      mReport.Place.Origin.FileName, mReport.Place.Origin.AtLine));
  end;
  AFileName := mAnswer.FileName;
  ALineNum := mAnswer.Line;
  Result := mAnswer.Result;
end;

function TDpccCodeInsightManager.AskDefinition(const AView: IOTAEditView; AIndex: Integer; out AFileName: string;
  out ALine: Integer; var AReport: TGotoReport): TDpccGotoOutcome;
var
  mSlot: IDpccAnswerSlot;
  mAnswer: TDpccAnswer;
begin
  AFileName := '';
  ALine := 0;
  if not TDpccCodeInsightQueries.GotoPlace(AView, GotoPlaceLog(AReport.Flow), AReport.Place) then
  begin
    Exit(TDpccGotoOutcome.NoView);
  end;
  AReport.HasPlace := True;
  AReport.Place.Origin.FlowId := AReport.Flow;
  if AReport.Flow > 0 then
  begin
    TDpccFlow.Step(AReport.Flow, TDpccFlowArea.Jump, Format('Stelle %s (%s), Wort %s', [TDpccFlow.PlaceText(
      AReport.Place.Origin.FileName, AReport.Place.Origin.AtLine, AReport.Place.Origin.AtCharacter),
      PlaceSource(AReport.Place.Mouse), TDpccFlow.WordText(AReport.Place.LineText,
      AReport.Place.Origin.AtWordStart, AReport.Place.Origin.AtWordEnd)]));
  end;
  // Jeder Sprungwunsch macht ältere, noch ausstehende ungültig (auch einen, der auf den Start wartet).
  Inc(FGotoGeneration);
  AReport.Place.Origin.Generation := FGotoGeneration;
  // Abgleich im Hauptthread: braucht den Puffertext, wartet nicht auf den Server.
  FSession.Sync(AReport.Place.Origin.FileName, AReport.Place.Text);
  mSlot := TDpccAnswerSlot.Create(AReport.Place.Origin.StartedMs);
  StartWork(GotoWork(FSession, FSignals, mSlot, AReport.Place));
  if not mSlot.Await(TDpccLateAnswers.cWaitMs) then
  begin
    // Die Anfrage läuft weiter (nicht abgebrochen); die IDE bricht still ab, LateGoto meldet später den Ausgang.
    TDpccGuard.ReportProviderSlow(cGotoSlowName, Format('keine Antwort innerhalb von %d ms, Sprung wird nachgereicht',
      [TDpccLateAnswers.cWaitMs]));
    if AReport.Flow > 0 then
    begin
      FlowStep(AReport.Flow, Format('keine Antwort binnen %d ms: die IDE bekommt kein Ziel, der Sprung wird ' +
        'nachgereicht (LateGoto, höchstens %d s nach dem Klick)', [TDpccLateAnswers.cWaitMs,
        TDpccLateAnswers.cMaxAgeMs div 1000]));
    end;
    Exit(TDpccGotoOutcome.Deferred);
  end;
  mAnswer := mSlot.Answer;
  case mAnswer.Error of
    TDpccAnswerError.MethodNotFound:
      begin
        // Erst jetzt als fehlend erkannt (-32601): Server ohne Sprungziele.
        FlowStep(AReport.Flow, 'Ende: Server ohne Sprungziele (-32601): ' + mAnswer.ErrorText);
        AReport.Detail := TDpccGuard.MessageText(mAnswer.ErrorText);
        Exit(TDpccGotoOutcome.NotOffered);
      end;
    TDpccAnswerError.ClientError:
      begin
        // Beendeter Server: erwartbar, keine Sicherung.
        FlowStep(AReport.Flow, 'Ende: Server getrennt oder Zeitlimit: ' + mAnswer.ErrorText);
        AReport.Detail := TDpccGuard.MessageText(mAnswer.ErrorText);
        Exit(TDpccGotoOutcome.TimedOut);
      end;
    TDpccAnswerError.Other:
      begin
        // Wie ein Fehler im Hauptthread: Meldung und Sicherung (GotoDefinition).
        raise Exception.Create(mAnswer.ErrorText);
      end;
  end;
  Result := TDpccGotoOutcome.NotFound;
  if TDpccCodeInsightQueries.TargetOf(mAnswer) then
  begin
    AFileName := mAnswer.FileName;
    ALine := mAnswer.Line;
    Result := TDpccGotoOutcome.Found;
    if AReport.Flow > 0 then
    begin
      FlowStep(AReport.Flow, Format('Antwort der Sitzung nach %d ms: %s', [Int64(mAnswer.ArrivedMs -
        AReport.Place.Origin.StartedMs), TDpccFlow.PlaceText(mAnswer.FileName, mAnswer.Line + 1,
        mAnswer.Character)]));
    end;
  end
  else
  begin
    AReport.NoTarget := TDpccCodeInsightQueries.NoTargetOf(mAnswer);
    if AReport.Flow > 0 then
    begin
      FlowStep(AReport.Flow, 'Antwort der Sitzung: ' + TDpccGotoLog.NoTargetOutcome(AReport.NoTarget));
    end;
  end;
end;

function TDpccCodeInsightManager.RememberStartGoto(const AView: IOTAEditView;
  var AReport: TGotoReport): TDpccGotoOutcome;
begin
  if not TDpccCodeInsightQueries.GotoPlace(AView, GotoPlaceLog(AReport.Flow), AReport.Place) then
  begin
    Exit(TDpccGotoOutcome.NoView);
  end;
  AReport.HasPlace := True;
  AReport.Place.Origin.FlowId := AReport.Flow;
  if AReport.Flow > 0 then
  begin
    FlowStep(AReport.Flow, Format('Stelle %s (%s), Wort %s; gemerkt bis zum Start', [TDpccFlow.PlaceText(
      AReport.Place.Origin.FileName, AReport.Place.Origin.AtLine, AReport.Place.Origin.AtCharacter),
      PlaceSource(AReport.Place.Mouse), TDpccFlow.WordText(AReport.Place.LineText, AReport.Place.Origin.AtWordStart,
      AReport.Place.Origin.AtWordEnd)]));
  end;
  // Wie ein Sprungwunsch an den Server: Ein neuerer (oder ein späterer Klick) macht ihn ungültig.
  Inc(FGotoGeneration);
  AReport.Place.Origin.Generation := FGotoGeneration;
  FStartGoto := AReport.Place;
  Result := TDpccGotoOutcome.Starting;
end;

procedure TDpccCodeInsightManager.SessionStartDone(AAdopted: Boolean);
var
  mPlace: TDpccGotoPlace;
begin
  inherited;
  if FStartGoto.Origin.Generation = 0 then
  begin
    Exit;
  end;
  mPlace := FStartGoto;
  FStartGoto := Default(TDpccGotoPlace);
  try
    ResumeStartGoto(mPlace, AAdopted);
  except
    on E: Exception do
    begin
      // Im Ablauf des Starts: kein Fehler darf ihn stören.
      GotoLog(True, 'nach dem Start: Fehler ' + TDpccGuard.ErrorText(E), mPlace.Origin);
      ReportFailure(TDpccFeature.GoToDefinition, E);
    end;
  end;
end;

procedure TDpccCodeInsightManager.ResumeStartGoto(const APlace: TDpccGotoPlace; AAdopted: Boolean);
var
  mActivity: IInterface;
  mNow: TDpccGotoNow;
  mVerdict: TDpccGotoVerdict;
  mView: IOTAEditView;
  mSlot: IDpccAnswerSlot;
begin
  mActivity := TDpccActivity.Scope('Gehe zu Definition (nach dem Start)');
  if not AAdopted or (FSession = nil) then
  begin
    GotoLog(True, 'nach dem Start verworfen: Start fehlgeschlagen oder verworfen', APlace.Origin);
    Exit;
  end;
  if FShutDown or not FEnabled or TDpccGuard.Disabled(TDpccFeature.GoToDefinition) then
  begin
    GotoLog(True, 'nach dem Start verworfen: dpcc abgeschaltet', APlace.Origin);
    Exit;
  end;
  // Dieselbe Prüfung wie für eine nachgereichte Antwort, nur noch ohne Antwort (Ziel angenommen).
  mNow := TDpccCodeInsightQueries.GotoNow(FGotoGeneration);
  mVerdict := TDpccLateGoto.Verdict(APlace.Origin, mNow, True, TDpccLateAnswers.cMaxAgeMs);
  if mVerdict <> TDpccGotoVerdict.Jump then
  begin
    GotoLog(True, Format('nach dem Start verworfen: %s (Start nach %d ms)', [TDpccLateGoto.VerdictText(mVerdict),
      Int64(TDpccLateGoto.AgeMs(APlace.Origin, mNow))]), APlace.Origin);
    Exit;
  end;
  // Der Puffer muss noch der vom Klick sein: Die Stelle bezieht sich auf diesen Text.
  mView := TDpccEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or (TDpccEditorBuffer.Text(mView.Buffer) <> APlace.Text) then
  begin
    GotoLog(True, 'nach dem Start verworfen: Text geändert', APlace.Origin);
    Exit;
  end;
  if not FSession.Offers(cDefinitionMethod) then
  begin
    GotoLog(True, 'nach dem Start: Server bietet keine Sprungziele', APlace.Origin);
    GotoNotice(TDpccGotoNotice.ForKind(TDpccTextLanguage.Current, TDpccGotoNoticeKind.NotOffered, '', 0, False));
    Exit;
  end;
  FlowStep(APlace.Origin.FlowId, 'nach dem Start: frage den Server, die Antwort geht über LateGoto');
  FSession.Sync(APlace.Origin.FileName, APlace.Text);
  mSlot := TDpccAnswerSlot.Create(APlace.Origin.StartedMs);
  StartWork(GotoWork(FSession, FSignals, mSlot, APlace));
  // Nicht warten: Ab jetzt reicht der Thread die Antwort nach (LateGoto). War er schon fertig, gleich hier.
  if mSlot.Await(0) then
  begin
    LateGoto(APlace.Origin, mSlot.Answer);
  end;
end;

procedure TDpccCodeInsightManager.LateGoto(const AOrigin: TDpccGotoOrigin; const AAnswer: TDpccAnswer);
var
  mActivity: IInterface;
  mVerdict: TDpccGotoVerdict;
  mNow: TDpccGotoNow;
  mCurrent, mOpened: Boolean;
  mArrival, mFileName, mProblem, mFlowText: string;
  mLine, mCharacter: Integer;
begin
  // Abgebaut: Protokoll und Editor gehören nicht mehr uns.
  if FShutDown then
  begin
    Exit;
  end;
  mActivity := TDpccActivity.Scope('Gehe zu Definition (nachgereicht)');
  mNow := TDpccCodeInsightQueries.GotoNow(FGotoGeneration);
  mNow.ArrivedMs := AAnswer.ArrivedMs;
  mArrival := Format(' (Antwort nach %d ms)', [Int64(TDpccLateGoto.AgeMs(AOrigin, mNow))]);
  // Nur der neueste Sprungwunsch bekommt eine Meldung; ältere stehen nur im Protokoll.
  mCurrent := AOrigin.Generation = FGotoGeneration;
  // Ablaufprotokoll (LOG1); ohne Kennung (vor dem Einschalten gefragt) wie bisher nur mit Diagnose = 1.
  if Diagnosing then
  begin
    mFlowText := Format('LateGoto: Antwort nach %d ms, Cursor jetzt %s %d:%d, gefragt %d:%d, Cursor beim Fragen ' +
      '%d:%d; Ziel %s', [Int64(TDpccLateGoto.AgeMs(AOrigin, mNow)), TDpccFlow.FileText(mNow.FileName),
      mNow.CaretLine, mNow.CaretCharacter + 1, AOrigin.AtLine, AOrigin.AtCharacter + 1, AOrigin.CaretLine,
      AOrigin.CaretCharacter + 1, LateTargetText(AAnswer)]);
    if AOrigin.FlowId > 0 then
    begin
      FlowStep(AOrigin.FlowId, mFlowText);
    end
    else
    begin
      Diagnose('Gehe zu Definition nachgereicht: ' + mFlowText);
    end;
  end;
  if not FEnabled or TDpccGuard.Disabled(TDpccFeature.GoToDefinition) then
  begin
    GotoLog(True, 'nachgereicht verworfen: dpcc abgeschaltet' + mArrival, AOrigin);
    Exit;
  end;
  if AAnswer.Error <> TDpccAnswerError.None then
  begin
    // Auch ein spätes Zeitlimit nicht stumm: gedrosselt ins Protokoll, dazu die Zeile zum Sprung.
    TDpccGuard.ReportProviderSlow(cGotoLateName, AAnswer.ErrorText);
    case AAnswer.Error of
      TDpccAnswerError.MethodNotFound:
        begin
          GotoLog(True, 'nachgereicht: Server bietet keine Sprungziele' + mArrival, AOrigin);
          if mCurrent then
          begin
            GotoNotice(TDpccGotoNotice.ForKind(TDpccTextLanguage.Current, TDpccGotoNoticeKind.NotOffered, '', 0,
              False));
          end;
        end;
      TDpccAnswerError.ClientError:
        begin
          if TDpccLateGoto.AgeMs(AOrigin, mNow) >= TDpccLateAnswers.cMaxAgeMs then
          begin
            GotoLog(True, 'nachgereicht: Zeitlimit' + mArrival, AOrigin);
            if mCurrent then
            begin
              GotoNotice(TDpccGotoNotice.ForKind(TDpccTextLanguage.Current, TDpccGotoNoticeKind.TimedOut, '',
                TDpccLateAnswers.cMaxAgeMs div 1000, False));
            end;
          end
          else
          begin
            GotoLog(True, 'nachgereicht: Server getrennt, ' + TDpccGuard.MessageText(AAnswer.ErrorText) + mArrival,
              AOrigin);
            if mCurrent then
            begin
              GotoNotice(TDpccGotoNotice.ForKind(TDpccTextLanguage.Current, TDpccGotoNoticeKind.ServerLost, '', 0,
                False));
            end;
          end;
        end;
    else
      GotoLog(True, 'nachgereicht: Fehler ' + TDpccGuard.MessageText(AAnswer.ErrorText) + mArrival, AOrigin);
    end;
    Exit;
  end;
  mVerdict := TDpccLateGoto.Verdict(AOrigin, mNow, TDpccCodeInsightQueries.TargetOf(AAnswer),
    TDpccLateAnswers.cMaxAgeMs);
  case mVerdict of
    TDpccGotoVerdict.NoTarget:
      begin
        GotoLog(True, 'nachgereicht ' + TDpccGotoLog.NoTargetOutcome(TDpccCodeInsightQueries.NoTargetOf(AAnswer)) +
          mArrival, AOrigin);
        if mCurrent then
        begin
          GotoNotice(TDpccGotoNotice.ForNoTarget(TDpccTextLanguage.Current,
            TDpccCodeInsightQueries.NoTargetOf(AAnswer)));
        end;
        Exit;
      end;
    TDpccGotoVerdict.TooOld:
      begin
        // Eine Antwort nach der Frist: für den Nutzer wie keine Antwort.
        GotoLog(True, 'nachgereicht verworfen: zu spät' + mArrival, AOrigin);
        GotoNotice(TDpccGotoNotice.ForKind(TDpccTextLanguage.Current, TDpccGotoNoticeKind.TimedOut, '',
          TDpccLateAnswers.cMaxAgeMs div 1000, False));
        Exit;
      end;
    TDpccGotoVerdict.CursorMoved:
      begin
        GotoLog(True, Format('nachgereicht verworfen: Cursor bewegt (jetzt %d:%d)%s', [mNow.CaretLine,
          mNow.CaretCharacter + 1, mArrival]), AOrigin);
        Exit;
      end;
    TDpccGotoVerdict.Superseded, TDpccGotoVerdict.OtherFile:
      begin
        GotoLog(True, 'nachgereicht verworfen: ' + TDpccLateGoto.VerdictText(mVerdict) + mArrival, AOrigin);
        Exit;
      end;
  end;
  // Wie die IDE bei einer rechtzeitigen Antwort: Datei zeigen (nur öffnen, wenn nötig), Cursor aufs Ziel.
  mFileName := AAnswer.FileName;
  mLine := AAnswer.Line;
  mCharacter := AAnswer.Character;
  mOpened := False;
  mProblem := '';
  TDpccGuard.RunIde(
    procedure
    begin
      mOpened := TDpccIdeNavigation.TryGoToLocation(mFileName, mLine, mCharacter, mProblem);
    end);
  if mOpened then
  begin
    FGotoNotices.Reset;
    GotoLog(True, 'nachgereicht gesprungen' + mArrival, AOrigin);
  end
  else
  begin
    GotoLog(True, 'nachgereicht: Fehler beim Öffnen (' + mProblem + ')' + mArrival, AOrigin);
    GotoNotice(TDpccGotoNotice.ForKind(TDpccTextLanguage.Current, TDpccGotoNoticeKind.OpenFailed,
      ExtractFileName(mFileName), 0, False));
  end;
end;

procedure TDpccCodeInsightManager.FinishGoto(AOutcome: TDpccGotoOutcome; const AReport: TGotoReport;
  const AView: IOTAEditView; AStartedMs: UInt64);
var
  mOrigin: TDpccGotoOrigin;
  mLanguage: TDpccLanguage;
begin
  // Stelle fürs Protokoll: die des Wunschs, sonst der Cursor der Ansicht (Spalte des Editors).
  if AReport.HasPlace then
  begin
    mOrigin := AReport.Place.Origin;
  end
  else
  begin
    mOrigin := Default(TDpccGotoOrigin);
    if (AView <> nil) and (AView.Buffer <> nil) then
    begin
      mOrigin.FileName := AView.Buffer.FileName;
      mOrigin.AtLine := AView.CursorPos.Line;
      mOrigin.AtCharacter := AView.CursorPos.Col - 1;
    end;
  end;
  mOrigin.StartedMs := AStartedMs;
  // Ablaufprotokoll (LOG1): Ende und Ergebnis dieses Aufrufs schreibt GotoDefinition selbst; GotoLog ergänzt die Kette
  // nur für spätere Ausgänge (LateGoto, nach dem Start).
  mOrigin.FlowId := 0;
  mLanguage := TDpccTextLanguage.Current;
  case AOutcome of
    TDpccGotoOutcome.Found:
      begin
        FGotoNotices.Reset;
        GotoLog(False, 'gesprungen', mOrigin);
      end;
    TDpccGotoOutcome.NotFound:
      begin
        GotoLog(True, TDpccGotoLog.NoTargetOutcome(AReport.NoTarget), mOrigin);
        GotoNotice(TDpccGotoNotice.ForNoTarget(mLanguage, AReport.NoTarget));
      end;
    TDpccGotoOutcome.Disabled:
      GotoLog(True, 'abgeschaltet (Sicherung)', mOrigin);
    TDpccGotoOutcome.NoView:
      GotoLog(True, 'keine Editoransicht oder Stelle außerhalb des Puffers', mOrigin);
    TDpccGotoOutcome.NoSession:
      begin
        GotoLog(True, AReport.Detail, mOrigin);
        if AReport.Responsible then
        begin
          GotoNotice(TDpccGotoNotice.ForKind(mLanguage, TDpccGotoNoticeKind.NotRunning, '', 0, False));
        end;
      end;
    TDpccGotoOutcome.NotOffered:
      begin
        GotoLog(True, 'Server bietet keine Sprungziele', mOrigin);
        GotoNotice(TDpccGotoNotice.ForKind(mLanguage, TDpccGotoNoticeKind.NotOffered, '', 0, False));
      end;
    TDpccGotoOutcome.TimedOut:
      begin
        // Binnen cWaitMs ist das kein Zeitlimit, sondern ein beendeter Server.
        GotoLog(True, 'Server getrennt: ' + AReport.Detail, mOrigin);
        GotoNotice(TDpccGotoNotice.ForKind(mLanguage, TDpccGotoNoticeKind.ServerLost, '', 0, False));
      end;
    TDpccGotoOutcome.Failed:
      // Die Meldung zeigt ReportError schon.
      GotoLog(True, 'Fehler ' + AReport.Detail, mOrigin);
    TDpccGotoOutcome.Starting:
      // Die Zeile zum Ausgang schreibt SessionStartDone.
      GotoNotice(TDpccGotoNotice.ForKind(mLanguage, TDpccGotoNoticeKind.Starting, '',
        TDpccLateAnswers.cMaxAgeMs div 1000, False));
  end;
  // Deferred: Die Zeile schreibt LateGoto.
end;

procedure TDpccCodeInsightManager.GotoLog(AAlways: Boolean; const AOutcome: string; const AOrigin: TDpccGotoOrigin);
var
  mElapsed: Int64;
begin
  // Ablaufprotokoll (LOG1): derselbe Ausgang als Zeile der Kette, auch für nachgereichte und verworfene Antworten.
  if AOrigin.FlowId > 0 then
  begin
    FlowStep(AOrigin.FlowId, 'Ausgang (dpcc.log): ' + AOutcome);
  end;
  if not AAlways and not Diagnosing then
  begin
    Exit;
  end;
  mElapsed := 0;
  if (AOrigin.StartedMs > 0) and (TThread.GetTickCount64 > AOrigin.StartedMs) then
  begin
    mElapsed := Int64(TThread.GetTickCount64 - AOrigin.StartedMs);
  end;
  TDpccGuard.Log(TDpccGotoLog.Line(AOutcome, mElapsed, AOrigin.FileName, AOrigin.AtLine, AOrigin.AtCharacter,
    AOrigin.AtMouse));
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

function TDpccCodeInsightManager.GotoPlaceLog(AFlow: Integer): TProc<string>;
var
  mFlow: Integer;
begin
  Result := nil;
  if AFlow <= 0 then
  begin
    Exit;
  end;
  mFlow := AFlow;
  Result :=
    procedure(AMessage: string)
    begin
      FlowStep(mFlow, AMessage);
    end;
end;

procedure TDpccCodeInsightManager.GotoNotice(const AText: string);
begin
  // Wie der Hinweis oben: Zeile in der Gruppe dpcc, ohne das Meldungsfenster nach vorn zu holen (kein Fokuswechsel
  // nach Strg+Klick).
  if FGotoNotices.Take(AText, TThread.GetTickCount64) then
  begin
    MessageLine(AText);
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

// CI-OPT: Was dpcc selbst regelt, steht auf der Seite dpcc und ist im Dialog der IDE (Editor › Sprache › Code
// Insight, wenn dpcc als Anbieter gewählt ist) ausgeblendet. Was die IDE allein macht, bleibt sichtbar:
// Blockvervollständigung (chkbxEnableAutoCompletion) samt Umbruchstil, Vorlagen und Hinweise (ohne Is-Abfrage),
// „Unvollst. Eigenschaften“ (ohne Is-Abfrage, Class Completion), „Programmierhilfe“ (ohne Is-Abfrage) und Error
// Insight (eigener Reiter, wie bisher).

function TDpccCodeInsightManager.IsEnableErrorInsightVisible: Boolean;
begin
  // Unverändert: Error Insight bleibt Sache der IDE.
  Result := True;
end;

function TDpccCodeInsightManager.IsCodeCompleteAutoParensVisible: Boolean;
begin
  // „Klammern bei Methoden ergänzen“ (AutoParentheses).
  Result := False;
end;

function TDpccCodeInsightManager.IsCodeCompleteAutoInvokeVisible: Boolean;
begin
  // „Nach dem Punkt automatisch öffnen“ (OpenAfterDot); die Verzögerung beim Tippen stellt dpcc selbst (-1).
  Result := False;
end;

function TDpccCodeInsightManager.IsCodeCompleteHistoryVisible: Boolean;
begin
  // „Häufig und zuletzt gewählte Einträge nach oben“ (Learning).
  Result := False;
end;

function TDpccCodeInsightManager.IsCodeCompleteShowReservedWordsVisible: Boolean;
begin
  // „Reservierte Wörter in der Liste zeigen“ (completion.keywords).
  Result := False;
end;

function TDpccCodeInsightManager.IsCodeParametersVisible: Boolean;
begin
  // „Parameter-Hint bei „(“ und „,““ (ParameterHints).
  Result := False;
end;

function TDpccCodeInsightManager.IsEvalHintsVisible: Boolean;
begin
  // „Werte beim Debuggen zeigen“ (DebugHoverValues).
  Result := False;
end;

function TDpccCodeInsightManager.IsDeclInfoVisible: Boolean;
begin
  // „Eigener Tooltip beim Verweilen über Bezeichnern“ (HoverTooltip).
  Result := False;
end;

function TDpccCodeInsightManager.IsToolTipHelpInsightVisible: Boolean;
begin
  // Ebenfalls der eigene Tooltip (HoverTooltip); Help Insight verbirgt dpcc zusätzlich zur Laufzeit.
  Result := False;
end;

function TDpccCodeInsightManager.IsEnableAutoCompletionVisible: Boolean;
begin
  // „Blockvervollständigung“ (Auto-block Completion): macht die IDE allein, bleibt sichtbar.
  Result := True;
end;

function TDpccCodeInsightManager.IsBlockWrapStyleVisible: Boolean;
begin
  // Umbruchstil der Blockvervollständigung (Block Wrap Style): bleibt sichtbar.
  Result := True;
end;

{ IOTACodeInsightManagerEnvOptions270 }

function TDpccCodeInsightManager.IsGenerateVSCodeInfo: Boolean;
begin
  // „LSP-Konfiguration generieren“ (chkbxVSCodeInfo) betrifft nur DelphiLSP; mit dpcc ohne Wirkung, ausgeblendet.
  // Unter Delphi 12 und 13 gleich deklariert (gleiche GUID, eine Methode).
  Result := False;
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
  mFlow: Integer;
begin
  mActivity := TDpccActivity.Scope('Vervollständigung öffnen');
  // False: Die IDE zeigt keine eigene Liste; unser Popup übernimmt (#407, #410).
  Result := False;
  // Ablaufprotokoll (LOG1): Kennung für Anfrage und Ergebnis (EditorOpen, Controller schreiben unter Current).
  mFlow := TDpccFlow.Start(TDpccFlowArea.Completion);
  try
    // Start nur hier im Hauptthread und nur für Dateien, die dpcc bei Hauptschalter an bedient; er läuft im
    // Hintergrund, die Quellen bekommen die laufende Sitzung. Ohne Server liefern die übrigen Quellen trotzdem.
    mView := TDpccCodeInsightQueries.CurrentEditView;
    if mFlow > 0 then
    begin
      AreaStep(TDpccFlowArea.Completion, mFlow, Format('Eintritt InvokeCodeCompletion(%d, %d Zeichen), Datei %s',
        [Ord(HowInvoked), Length(Str), ViewFileText(mView)]));
    end;
    if FEnabled and (mView <> nil) and (mView.Buffer <> nil) and Handles(mView.Buffer.FileName) then
    begin
      EnsureSession;
    end
    else if (mFlow > 0) and (mView <> nil) and (mView.Buffer <> nil) then
    begin
      // Fragt trotzdem: die übrigen Quellen liefern auch ohne Server.
      AreaStep(TDpccFlowArea.Completion, mFlow, 'ohne Server: ' + NotHandledReason(FShutDown, FEnabled,
        mView.Buffer.FileName));
    end;
    Completion.Invoke(mView, HowInvoked <> itManual);
  except
    on E: Exception do
    begin
      AreaStep(TDpccFlowArea.Completion, mFlow, 'Ende: Fehler ' + E.ClassName + ': ' + E.Message);
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
  mFlow: Integer;
begin
  // False: Die IDE zeigt keine eigene Parameterhilfe; unser Hint übernimmt (#436).
  Result := False;
  // Ablaufprotokoll (LOG1): Kennung für Anfrage und Ergebnis (Signature.Editor schreibt unter Current).
  mFlow := TDpccFlow.Start(TDpccFlowArea.Signature);
  // Durch die Sicherung abgeschaltet (#493).
  if TDpccGuard.Disabled(TDpccFeature.Signature) then
  begin
    AreaStep(TDpccFlowArea.Signature, mFlow, 'Eintritt InvokeParameterCodeInsight: Ende, Parameterhilfe ist von ' +
      'der Sicherung abgeschaltet');
    Exit;
  end;
  mActivity := TDpccActivity.Scope('Parameterhilfe');
  try
    // Start nur hier im Hauptthread, nur bei Hauptschalter an und für Dateien von dpcc; er läuft im Hintergrund.
    mView := TDpccCodeInsightQueries.CurrentEditView;
    if mFlow > 0 then
    begin
      AreaStep(TDpccFlowArea.Signature, mFlow, Format('Eintritt InvokeParameterCodeInsight(%d), Datei %s',
        [Ord(HowInvoked), ViewFileText(mView)]));
    end;
    if FEnabled and (mView <> nil) and (mView.Buffer <> nil) and Handles(mView.Buffer.FileName) then
    begin
      EnsureSession;
    end
    else if (mFlow > 0) and (mView <> nil) and (mView.Buffer <> nil) then
    begin
      AreaStep(TDpccFlowArea.Signature, mFlow, 'ohne Server: ' + NotHandledReason(FShutDown, FEnabled,
        mView.Buffer.FileName));
    end;
    FEditors.Signature.Invoke(mView);
  except
    on E: Exception do
    begin
      AreaStep(TDpccFlowArea.Signature, mFlow, 'Ende: Fehler ' + E.ClassName + ': ' + E.Message);
      ReportError('Parameterhilfe: ' + E.Message);
      ReportFailure(TDpccFeature.Signature, E);
    end;
  end;
end;

function TDpccCodeInsightManager.OpenCompletion: Boolean;
var
  mView: IOTAEditView;
  mIde: TDpccIdeList;
  mFlow: Integer;
begin
  Result := True;
  // Ablaufprotokoll (LOG1): Kennung für Anfrage und Ergebnis (EditorOpen, Controller schreiben unter Current).
  mFlow := TDpccFlow.Start(TDpccFlowArea.Completion);
  if not FEnabled or TDpccGuard.Disabled(TDpccFeature.Completion) or not ServerAvailable then
  begin
    if mFlow > 0 then
    begin
      AreaStep(TDpccFlowArea.Completion, mFlow, 'Eintritt eigene Taste (Strg+Leertaste): Ende, ' +
        OwnKeyOffReason(FEnabled, TDpccGuard.Disabled(TDpccFeature.Completion)));
    end;
    Exit;
  end;
  AreaStep(TDpccFlowArea.Completion, mFlow, 'Eintritt eigene Taste (Strg+Leertaste)');
  try
    // Start nur hier im Hauptthread, vor der Anfrage: Die Quellen holen sich die laufende Sitzung.
    EnsureSession;
    mView := TDpccCodeInsightQueries.CurrentEditView;
    mIde := TDpccIdeList.Usual;
    if (mView <> nil) and (mView.Buffer <> nil) then
    begin
      mIde := TDpccIdeList.Create(IdeListReachable(mView.Buffer.FileName), IdeCompletionListOpen);
      if mFlow > 0 then
      begin
        AreaStep(TDpccFlowArea.Completion, mFlow, Format('Datei %s; Liste der IDE: erreichbar %s, offen %s',
          [ViewFileText(mView), BoolToStr(mIde.Reachable, True), BoolToStr(mIde.Open, True)]));
      end;
    end;
    // Zweites Strg+Leertaste nach leerem Ergebnis an derselben Stelle (L3) bzw. offene Liste der IDE (L4): False,
    // die Taste gehört der IDE.
    Result := Completion.KeyInvoke(mView, mIde);
  except
    on E: Exception do
    begin
      AreaStep(TDpccFlowArea.Completion, mFlow, 'Ende: Fehler ' + E.ClassName + ': ' + E.Message);
      ReportError(UiText(TManagerText.Completion) + E.Message);
      ReportFailure(TDpccFeature.Completion, E);
    end;
  end;
end;

procedure TDpccCodeInsightManager.OpenSignature;
var
  mFlow: Integer;
begin
  // Ablaufprotokoll (LOG1): Kennung für Anfrage und Ergebnis (Signature.Editor schreibt unter Current).
  mFlow := TDpccFlow.Start(TDpccFlowArea.Signature);
  if not FEnabled or TDpccGuard.Disabled(TDpccFeature.Signature) or not ServerAvailable then
  begin
    if mFlow > 0 then
    begin
      AreaStep(TDpccFlowArea.Signature, mFlow, 'Eintritt eigene Taste (Strg+Umschalt+Leertaste): Ende, ' +
        OwnKeyOffReason(FEnabled, TDpccGuard.Disabled(TDpccFeature.Signature)));
    end;
    Exit;
  end;
  AreaStep(TDpccFlowArea.Signature, mFlow, 'Eintritt eigene Taste (Strg+Umschalt+Leertaste)');
  try
    // Start nur hier im Hauptthread.
    EnsureSession;
    FEditors.Signature.Invoke(TDpccCodeInsightQueries.CurrentEditView);
  except
    on E: Exception do
    begin
      AreaStep(TDpccFlowArea.Signature, mFlow, 'Ende: Fehler ' + E.ClassName + ': ' + E.Message);
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
