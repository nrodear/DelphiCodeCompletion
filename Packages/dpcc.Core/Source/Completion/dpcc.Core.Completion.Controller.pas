unit dpcc.Core.Completion.Controller;

// Ablauf der Vervollständigung ohne Fenster und ohne IDE (#410, #414): Start
// fragt die Datenquelle (#408), eintreffende Einträge werden lokal nach dem
// getippten Präfix gefiltert (#409) und an die Ansicht gegeben. Tasten
// verschieben die Auswahl, Enter/Tab übernehmen, Esc schließt. Ohne Treffer
// zeigt die Ansicht den leeren Zustand (#423), statt zu verschwinden.
//
// Alle öffentlichen Methoden laufen im Hauptthread. Einträge aus anderen
// Threads stellt die Senke über TDpccMainThread.Queue in den Hauptthread
// (beim Entladen verworfen); was nach
// Close, einem neuen Start oder dem Freigeben ankommt, wird verworfen.
//
// Gekürzte Listen (#431, LSP isIncomplete): Beim Weitertippen filtert Requery
// sofort lokal und fragt im Hintergrund neu; die neue Liste ersetzt die alte,
// sobald sie eintrifft, und eine eigene Wahl bleibt auf demselben Eintrag.
// Die automatische Vorauswahl klebt nicht: Nach jedem Teilergebnis und jedem Ersetzen gilt die Vorauswahl der
// ganzen Liste (FirstSelection, dann Look-ahead), solange niemand mit Pfeiltasten oder Maus gewählt hat. Nur das
// Anheften (ToggleFavorite) lässt die Auswahl auf dem Eintrag, auch auf einem automatisch gewählten.
// Der Server liefert nur Namen, die zum Präfix der Anfrage passen (#616). Eine Liste gilt daher nur, solange
// das getippte Wort mit diesem Präfix beginnt; kürzer oder anders (Rücktaste) heißt neu fragen (NeedsQuery).
// Teilergebnisse (#616) kommen als mehrere AddItems: Das erste ersetzt bei Requery die Liste, die weiteren
// hängen an.
//
// Rangfolge über TDpccRanking: Lernzuschlag (#418, Usage), Gruppen geerbter
// Member mit Überschriften (#419; Header in der Reihenfolge, die Auswahl
// überspringt sie). Filter-Chips (#422) gibt es seit S7a nicht mehr (schlichte Liste, S6).
//
// Favoriten (#458, Favorites): Eintreffende Einträge bekommen Favorite gesetzt; ToggleFavorite heftet den
// Eintrag an einer Position an bzw. löst ihn, sortiert neu und lässt die Auswahl auf dem gewählten Eintrag.
// Gespeichert wird vom Aufrufer (IDE-Schicht).
//
// Mengenmodus (#448, TDpccCompletionSets): Toggle (Leertaste) hakt den gewählten Wert an oder ab, Accept
// übernimmt die ganze Klammer. Hat niemand umgeschaltet, nimmt Enter den gewählten Wert dazu. Nach "[" geöffnet
// (Trigger) und ohne Einträge schließt die Liste still, statt den leeren Zustand zu zeigen.
//
// Unbekannter Name (#471): Stehen nur Deklarationen in der Liste, ist nichts gewählt (Passive). Enter gehört dann
// dem Editor und schließt die Liste, damit ein neuer Name nicht ungefragt deklariert wird; eine Pfeiltaste wählt
// die erste Deklaration. Ebenso, wenn oben nur ein Hinweis „n Methoden von I fehlen“ (#466) steht und sonst nichts:
// Der Hinweis wird nie vorgewählt, die Auswahl beginnt beim ersten Eintrag danach.
//
// Listenmodus (#497, TDpccListMode): Mit All bzw. Rest bleiben beim Tippen auch die Einträge ohne Treffer
// sichtbar, je nach ListScope nur in Mitgliederlisten nach "." oder überall. Steht kein Treffer oben, ist nichts
// gewählt (wie bei #471): Enter gehört dem Editor, eine Pfeiltaste wählt den ersten Eintrag.
//
// Freigabe absichern (#489): Steht nur dieses Angebot in der Liste, schließt jedes getippte Zeichen sie.
//
// Hinweis bei unvollständigem Code (#457): Meldet die Quelle MarkSyntax, gibt der Controller den Hinweis an eine
// Ansicht mit IDpccCompletionSyntaxView, sofort und noch einmal beim Abschluss der Abfrage (ohne Meldung dann
// „sicher“, damit ein alter Hinweis nach Requery verschwindet).
//
// Esc (#414): Nach dem Schließen mit Esc öffnet ein automatischer Start im selben Wort (Datei, Zeile,
// Wortanfang) die Liste nicht wieder; Strg+Leer öffnet sie und hebt die Sperre auf.
//
// Zweites Strg+Leertaste (L3): OnSettled meldet nach dem Abschluss jeder Abfrage, ob die Liste leer bleibt; die
// Entscheidung, ob ein weiteres Strg+Leertaste der IDE gehört, trifft TDpccCompletionFallback.
//
// Beim Tippen geöffnet (L5, TDpccContext.Typed, Regel in TDpccAutoOpen): Ohne Einträge schließt die Liste still
// (kein leerer Zustand, etwa in einem mehrzeiligen Kommentar). Ist das getippte Wort schon der Name des gewählten
// Eintrags (etwa "begin"), ist nichts gewählt (wie #471): Enter gehört dem Editor, eine Pfeiltaste wählt. Mit
// Strg+Leertaste geöffnete Listen bleiben wie bisher.
//
// Look-ahead (Cursor mitten im Wort, "str|ing"): TDpccContext.Rest ist der Wortrest rechts des Cursors. Ist
// Präfix + Rest (ohne Groß-/Kleinschreibung) der Name eines Eintrags, ist er nach dem Aufbau der Liste gewählt;
// gefiltert und sortiert wird weiter nur nach dem Präfix. Ohne solchen Eintrag oder ohne Rest bleibt die
// gewöhnliche Vorauswahl. Eine Auswahl mit Pfeiltasten oder Maus überschreibt er nicht, bis sich das Präfix ändert
// (dann setzt Refresh die Auswahl ohnehin zurück).
//
// Diagnosemodus (#479): Ist TDpccQueryTimings.Enabled, beginnt Start eine gemessene Abfrage (Kontext ab
// AContext.Started, Art des Kontexts, nur der Dateiname), Refresh meldet die Dauer von Filtern und Sortieren
// samt Anzahl der Einträge und die erste sichtbare Liste. Aus wird nichts gemessen.
//
// Doppelte Einträge (Befund beim Start): Teilergebnisse (#616) und Endantwort kamen ohne Abgleich in die Liste;
// abgeglichen wurde nur im Server. TDpccCompletionDedup verwirft jeden Eintrag, dessen Schlüssel (KeyOf) die Liste
// schon hat, auch innerhalb eines Teils; der erste bleibt, die Reihenfolge auch. Gewollte Varianten (gleichnamige
// aus anderen Units #475, Typkonvertierung #490, Überladungen mit anderer Signatur) unterscheiden sich im
// Schlüssel. Ersetzt Requery die Liste, beginnt der Abgleich neu. Entfernte Einträge meldet OnLog als eine Zeile,
// Namen nur mit LogNames.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Ranking,
  dpcc.Core.Completion.Usage,
  dpcc.Core.Completion.Favorites;

{$SCOPEDENUMS ON}

type
  TDpccNavigationKey = (Up, Down, PageUp, PageDown, First, Last, Accept, Cancel, Toggle);

  /// <summary>Anzeige der Liste; umgesetzt vom Popup (dpcc.UI) bzw. von Tests.</summary>
  IDpccCompletionView = interface
    ['{8D2F4B61-3E9A-4C57-A1D0-6B7E2F9C3A15}']
    /// <summary>Zeigt bzw. aktualisiert die Liste. AOrder: Indizes in AItems in Anzeigereihenfolge;
    /// ASelected: Position in AOrder; APattern: getippter Anfang, zum Hervorheben der Treffer.</summary>
    procedure ShowList(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    /// <summary>Leerer Zustand (#423): keine Treffer für APrefix unter ATotal Einträgen.</summary>
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    /// <summary>Zahl der sichtbaren Zeilen für Bild auf/ab.</summary>
    function PageSize: Integer;
  end;

  /// <summary>Ansicht mit Hinweis bei unvollständigem Code (#457); das Popup, wahlweise auch Tests.</summary>
  IDpccCompletionSyntaxView = interface
    ['{2C6E9B41-7A3D-4E85-B0F2-9D1C5A8E3B76}']
    /// <summary>Warnleiste bzw. Hinweis im leeren Zustand; Trust Sure blendet ihn aus.</summary>
    procedure ShowSyntax(const ANotice: TDpccSyntaxNotice);
  end;

  TDpccCommitEvent = reference to procedure(const AItem: TDpccCompletionItem);
  /// <summary>Abfrage abgeschlossen (L3); AEmpty: Die Liste zeigt danach den leeren Zustand (#423).</summary>
  TDpccSettledEvent = reference to procedure(AEmpty: Boolean);
  /// <summary>Zeile fürs Diagnoselog des Plugins; Namen aus dem Quelltext nur mit LogNames.</summary>
  TDpccCompletionLog = reference to procedure(const AMessage: string);

  /// <summary>Abgleich doppelter Einträge der offenen Liste: Teilergebnisse (#616) und Endantwort kommen ohne
  /// Abgleich an. Merkt sich die Schlüssel (KeyOf) der Liste, bis Clear sie verwirft.</summary>
  TDpccCompletionDedup = class
  public const
    /// <summary>Höchstzahl der Beispielnamen für das Diagnoselog.</summary>
    cMaxExamples = 3;
  private
    FSeen: TDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Schlüssel eines Eintrags: Name ohne Groß-/Kleinschreibung (wie Delphi), Art, Unit und Klasse der
    /// Deklaration, Signatur (Detail), Bedingung, Typkonvertierung samt Original, Variante gleichnamiger Units,
    /// Einfügetext, Deklaration eines unbekannten Namens, Befehl, Formular, Sender und die Merkmale Aktion, Postfix,
    /// Hinweis, angeheftet, nicht verfügbar. Rang, Quelle (Datei, Position) und Daten für resolve zählen nicht: Ein
    /// doppelter Eintrag kann aus einer zweiten Datei derselben Unit stammen.</summary>
    class function KeyOf(const AItem: TDpccCompletionItem): string; static;
    /// <summary>Alle gemerkten Schlüssel verwerfen (neue Liste).</summary>
    procedure Clear;
    /// <summary>AItems ohne die Einträge, deren Schlüssel schon gemerkt ist oder in AItems weiter vorn steht; der
    /// erste bleibt, die Reihenfolge auch. Die übrigen Schlüssel werden gemerkt. ARemoved: Zahl der verworfenen,
    /// AExamples: höchstens cMaxExamples ihrer Namen, ohne Wiederholung.</summary>
    function Unique(const AItems: TDpccCompletionItems; out ARemoved: Integer;
      out AExamples: TArray<string>): TDpccCompletionItems;
    /// <summary>Zahl der gemerkten Schlüssel.</summary>
    function Count: Integer;
  end;

  /// <summary>Einstellungen der Vervollständigung, die der Aufrufer setzt (#418, #419, #458, #497).
  /// </summary>
  TDpccCompletionSettings = class
  private
    FOnCommit: TDpccCommitEvent;
    FOnSettled: TDpccSettledEvent;
    FOnLog: TDpccCompletionLog;
    FLogNames: Boolean;
    FGroupInherited: Boolean;
    FListMode: TDpccListMode;
    FListScope: TDpccListScope;
    FUsage: TDpccUsage;
    FFavorites: TDpccFavorites;
    /// <summary>Marken „zuletzt“/„häufig“ (#418) und Favorit (#458) in AItems ab AFrom setzen.</summary>
    procedure MarkItems(var AItems: TDpccCompletionItems; AFrom: Integer);
    /// <summary>Optionen für TDpccRanking: Listenmodus (AMembers: Mitgliederliste nach ".") und Lernzuschlag für
    /// AItems.</summary>
    function RankOptions(AMembers: Boolean; const AItems: TDpccCompletionItems): TDpccRankOptions;
  public
    property OnCommit: TDpccCommitEvent read FOnCommit write FOnCommit;
    /// <summary>Eine Abfrage ist abgeschlossen (L3, zweites Strg+Leertaste): einmal je Start bzw. Requery, nachdem
    /// alle Quellen fertig sind, auch nach Fehler oder Zeitlimit einer Quelle (sie trägt dann nichts bei). AEmpty:
    /// Die Liste zeigt den leeren Zustand. Nicht nach Close, nicht nach dem stillen Schließen nach "[" (#448).
    /// </summary>
    property OnSettled: TDpccSettledEvent read FOnSettled write FOnSettled;
    /// <summary>Diagnoselog (Registry-Wert Diagnose): etwa die Zahl verworfener doppelter Einträge; nil = keins.
    /// </summary>
    property OnLog: TDpccCompletionLog read FOnLog write FOnLog;
    /// <summary>Klarnamen in OnLog (diagnostics.log.names, Vorgabe aus): Beispielnamen der Dubletten.</summary>
    property LogNames: Boolean read FLogNames write FLogNames;
    /// <summary>Geerbte Member gruppieren (#419).</summary>
    property GroupInherited: Boolean read FGroupInherited write FGroupInherited;
    /// <summary>Einträge ohne Treffer zeigen (#497); Filter = nur Treffer.</summary>
    property ListMode: TDpccListMode read FListMode write FListMode;
    /// <summary>Wo ListMode gilt (#497).</summary>
    property ListScope: TDpccListScope read FListScope write FListScope;
    /// <summary>Lernende Gewichtung (#418); nil = aus. Gehört dem Aufrufer.</summary>
    property Usage: TDpccUsage read FUsage write FUsage;
    /// <summary>Angeheftete Favoriten (#458); nil = aus. Gehört dem Aufrufer.</summary>
    property Favorites: TDpccFavorites read FFavorites write FFavorites;
  end;

  /// <summary>Stand der offenen Liste: Einträge, Reihenfolge, Auswahl und Zustand der Abfrage.</summary>
  TDpccCompletionState = class(TDpccCompletionSettings)
  private
    FActive: Boolean;
    FLoading: Boolean;
    FItems: TDpccCompletionItems;
    /// <summary>Schlüssel der Einträge in FItems (Abgleich doppelter Einträge); gehört dem Controller.</summary>
    FDedup: TDpccCompletionDedup;
    FOrder: TArray<Integer>;
    FSelected: Integer;
    FPrefix: string;
    /// <summary>Präfix, mit dem die aktuelle Liste angefragt wurde (#616).</summary>
    FQueryPrefix: string;
    FEmpty: Boolean;
    /// <summary>Nur Deklarationen eines unbekannten Namens, noch keine gewählt (#471).</summary>
    FPassive: Boolean;
    /// <summary>Position des ersten Eintrags ohne Treffer (#497); -1 ohne.</summary>
    FRestStart: Integer;
    /// <summary>Mitgliederliste nach "." (#497).</summary>
    FMembers: Boolean;
    FIncomplete: Boolean;
    /// <summary>Hinweis bei unvollständigem Code (#457): gezeigt bzw. von der laufenden Abfrage gemeldet.</summary>
    FSyntax: TDpccSyntaxNotice;
    FPendingSyntax: TDpccSyntaxNotice;
    /// <summary>Die nächsten Einträge ersetzen die Liste (laufendes Requery).</summary>
    FReplace: Boolean;
    /// <summary>Zeichen, nach dem automatisch geöffnet wurde (#448).</summary>
    FTrigger: string;
    /// <summary>Im Mengenmodus schon umgeschaltet.</summary>
    FToggled: Boolean;
    /// <summary>Beim Tippen geöffnet (L5).</summary>
    FTyped: Boolean;
    /// <summary>Look-ahead: Wortrest rechts des Cursors (TDpccContext.Rest).</summary>
    FWordRest: string;
    /// <summary>Look-ahead: Die Auswahl stammt von Pfeiltasten oder Maus; der Look-ahead lässt sie stehen.</summary>
    FUserChose: Boolean;
    /// <summary>Look-ahead: Das letzte Refresh hat den Eintrag Präfix + Rest gewählt.</summary>
    FLookAhead: Boolean;
    function GetVisible: Boolean;
    procedure SelectByName(const AName: string);
  public
    function SelectedItem(out AItem: TDpccCompletionItem): Boolean;
    /// <summary>Ein Commit-Zeichen (#429) darf übernehmen: Liste offen und der gewählte Eintrag
    /// trifft das Präfix klar (genau, Anfang, Wortanfänge), nicht nur unscharf.</summary>
    function CanCommitOnCharacter: Boolean;
    /// <summary>Für APrefix neu fragen statt lokal filtern (#616): Liste gekürzt, oder APrefix beginnt nicht
    /// mit dem Präfix der Anfrage (der Server hat nach diesem gefiltert).</summary>
    function NeedsQuery(const APrefix: string): Boolean;
    /// <summary>Mengenmodus (#448): Kontrollkästchen statt einfacher Auswahl.</summary>
    function SetMode: Boolean;
    property Active: Boolean read FActive;
    property Loading: Boolean read FLoading;
    /// <summary>Liste ist offen und hat Treffer.</summary>
    property Visible: Boolean read GetVisible;
    /// <summary>Leerer Zustand wird gezeigt (#423).</summary>
    property Empty: Boolean read FEmpty;
    /// <summary>Nichts gewählt, weil nur Deklarationen eines unbekannten Namens passen (#471); Enter gehört dem
    /// Editor.</summary>
    property Passive: Boolean read FPassive;
    /// <summary>Die Quelle hat gekürzt; beim Weitertippen Requery statt UpdatePrefix.</summary>
    property Incomplete: Boolean read FIncomplete;
    /// <summary>Gezeigter Hinweis bei unvollständigem Code (#457); Trust Sure ohne.</summary>
    property Syntax: TDpccSyntaxNotice read FSyntax;
    /// <summary>Die offene Liste wurde beim Tippen geöffnet (L5, TDpccContext.Typed).</summary>
    property Typed: Boolean read FTyped;
    property Prefix: string read FPrefix;
    /// <summary>Look-ahead: Wortrest rechts des Cursors der offenen Liste.</summary>
    property WordRest: string read FWordRest;
    property Items: TDpccCompletionItems read FItems;
    property Order: TArray<Integer> read FOrder;
    property Selected: Integer read FSelected;
    /// <summary>Position des ersten Eintrags ohne Treffer in Order (#497); -1 ohne.</summary>
    property RestStart: Integer read FRestStart;
  end;

  /// <summary>Ablauf der Vervollständigung; Einstellungen und Stand in den Vorfahren.</summary>
  TDpccCompletionController = class(TDpccCompletionState)
  private type
    /// <summary>Lebt, solange eine Senke oder ein eingereihter Aufruf ihn hält.</summary>
    TAliveFlag = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;

    TControllerSink = class(TInterfacedObject, IDpccCompletionSink)
    private
      FController: TDpccCompletionController;
      FFlag: TAliveFlag;
      FFlagRef: IInterface;
      FGeneration: Integer;
    public
      constructor Create(AController: TDpccCompletionController; AFlag: TAliveFlag; AGeneration: Integer);
      procedure AddItems(const AItems: TDpccCompletionItems);
      procedure MarkIncomplete;
      procedure MarkSyntax(const ANotice: TDpccSyntaxNotice);
      procedure Complete;
    end;

    /// <summary>Wort im Editor: Datei, Zeile, Wortanfang (#414); Line &lt; 0 ohne.</summary>
    TWordPlace = record
      FileName: string;
      Line: Integer;
      Start: Integer;
      class function At(const AContext: TDpccContext): TWordPlace; static;
      function Matches(const AContext: TDpccContext): Boolean;
    end;
  private
    FProvider: IDpccCompletionProvider;
    FView: IDpccCompletionView;
    FFlag: TAliveFlag;
    FFlagRef: IInterface;
    FGeneration: Integer;
    /// <summary>Wort der offenen Liste (#414).</summary>
    FWord: TWordPlace;
    /// <summary>Mit Esc geschlossenes Wort; Line &lt; 0 ohne.</summary>
    FDismissed: TWordPlace;
    procedure Dismiss;
    procedure ToggleSelected;
    procedure CommitSet;
    procedure ItemsArrived(AGeneration: Integer; const AItems: TDpccCompletionItems);
    /// <summary>AItems ohne Einträge, die die Liste schon hat (FDedup); verworfene meldet OnLog.</summary>
    function Deduplicated(const AItems: TDpccCompletionItems): TDpccCompletionItems;
    procedure IncompleteArrived(AGeneration: Integer);
    procedure SyntaxArrived(AGeneration: Integer; const ANotice: TDpccSyntaxNotice);
    /// <summary>FSyntax an eine Ansicht mit IDpccCompletionSyntaxView.</summary>
    procedure ShowSyntax;
    procedure Query(const AContext: TDpccContext);
    procedure Completed(AGeneration: Integer);
    procedure Refresh(AKeepSelection: Boolean);
    /// <summary>Liste, Liste ohne Auswahl (Passive) oder leeren Zustand zeigen.</summary>
    procedure ShowResult;
    procedure MoveSelection(APosition, ADirection: Integer); overload;
    procedure MoveSelection(APosition: Integer); overload;
    /// <summary>Pfeile, Bild auf/ab, Pos1, Ende; False bei anderen Tasten.</summary>
    function MoveByKey(AKey: TDpccNavigationKey; APage: Integer): Boolean;
    function AcceptKey: Boolean;
    function ToggleKey: Boolean;
  public
    constructor Create(const AProvider: IDpccCompletionProvider; const AView: IDpccCompletionView);
    destructor Destroy; override;
    /// <summary>Neue Vervollständigung an AContext; schließt eine offene. Ein automatischer Start im mit Esc
    /// geschlossenen Wort öffnet nichts (#414).</summary>
    procedure Start(const AContext: TDpccContext);
    /// <summary>Wurde die Liste im Wort von AContext mit Esc geschlossen (#414)?</summary>
    function Dismissed(const AContext: TDpccContext): Boolean;
    /// <summary>Das Wort unter dem Cursor hat sich geändert: neu filtern. Der Wortrest (Look-ahead) bleibt.</summary>
    procedure UpdatePrefix(const APrefix: string); overload;
    /// <summary>Wie oben mit dem aktuellen Wortrest rechts des Cursors (Look-ahead, TDpccContext.Rest).</summary>
    procedure UpdatePrefix(const APrefix, ARest: string); overload;
    /// <summary>Wie UpdatePrefix, fragt aber zusätzlich neu an (gekürzte Liste, #431).</summary>
    procedure Requery(const AContext: TDpccContext);
    procedure Close;
    /// <summary>True, wenn die Taste verbraucht wurde; nur bei sichtbarer Liste.</summary>
    function HandleKey(AKey: TDpccNavigationKey): Boolean;
    /// <summary>Auswahl per Maus; APosition in der Anzeigereihenfolge.</summary>
    procedure Select(APosition: Integer);
    procedure CommitSelected;
    /// <summary>Eintrag an APosition (Anzeigereihenfolge) anheften bzw. lösen (Klick auf den Stern); AItem ist
    /// der Eintrag. Added bzw. Removed sortieren neu, die Auswahl bleibt auf dem gewählten Eintrag. NotAllowed
    /// ohne Favoriten, ohne Liste oder auf einer Überschrift.</summary>
    function ToggleFavorite(APosition: Integer; out AItem: TDpccCompletionItem): TDpccFavoriteToggle;
    /// <summary>Wie ToggleFavorite für den gewählten Eintrag (Strg+D); NotAllowed, wenn nichts gewählt ist.</summary>
    function ToggleSelectedFavorite(out AItem: TDpccCompletionItem): TDpccFavoriteToggle;
  end;

implementation

uses
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Timing,
  System.Math,
  System.StrUtils,
  dpcc.Core.Completion.Matching,
  dpcc.Core.Completion.Presentation,
  dpcc.Core.Completion.Sets;

/// <summary>Art des Kontexts für den Diagnosemodus (#479); nie Text aus dem Editor.</summary>
function TimingKind(const AContext: TDpccContext): string;
begin
  case AContext.Kind of
    TDpccContextKind.MemberAccess:
      Result := 'Member';
    TDpccContextKind.ClassDeclaration:
      Result := 'Klassendeklaration';
    TDpccContextKind.EventAssignment:
      Result := 'Ereigniszuweisung';
    TDpccContextKind.Directive:
      Result := 'Direktive';
    TDpccContextKind.XmlDoc:
      Result := 'XMLDoc';
  else
    Result := 'Bezeichner';
  end;
  if AContext.Automatic then
  begin
    Result := Result + ', automatisch';
  end
  else
  begin
    Result := Result + ', Strg+Leer';
  end;
end;

/// <summary>Nächster Eintrag (keine Überschrift) ab APosition in Richtung ADirection, sonst in der Gegenrichtung;
/// -1 ohne.</summary>
function FirstItemIn(const AOrder: TArray<Integer>; APosition, ADirection: Integer): Integer;
begin
  Result := APosition;
  while (Result >= 0) and (Result <= High(AOrder)) and TDpccRanking.IsHeader(AOrder[Result]) do
  begin
    Inc(Result, ADirection);
  end;
  if (Result >= 0) and (Result <= High(AOrder)) then
  begin
    Exit;
  end;
  Result := APosition;
  while (Result >= 0) and (Result <= High(AOrder)) and TDpccRanking.IsHeader(AOrder[Result]) do
  begin
    Dec(Result, ADirection);
  end;
  if (Result < 0) or (Result > High(AOrder)) then
  begin
    Result := -1;
  end;
end;

/// <summary>Erster wählbarer Eintrag: Hinweise (#466) stehen oben, gewählt ist der erste Eintrag danach.</summary>
function FirstSelection(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>): Integer;
var
  mPosition: Integer;
begin
  Result := FirstItemIn(AOrder, 0, 1);
  mPosition := Result;
  while (mPosition >= 0) and (mPosition <= High(AOrder)) and (TDpccRanking.IsHeader(AOrder[mPosition]) or
    AItems[AOrder[mPosition]].Hint) do
  begin
    Inc(mPosition);
  end;
  if (Result >= 0) and (mPosition <= High(AOrder)) then
  begin
    Result := mPosition;
  end;
end;

/// <summary>Index des gewählten Eintrags, der nach dem Neusortieren gewählt bleiben soll; -1 ohne.</summary>
function KeptIndex(const AOrder: TArray<Integer>; ASelected: Integer; AKeep, APassive: Boolean): Integer;
begin
  Result := -1;
  if AKeep and not APassive and (ASelected >= 0) and (ASelected < Length(AOrder)) then
  begin
    Result := AOrder[ASelected];
  end;
end;

/// <summary>Position des Eintrags AIndex in AOrder; ADefault ohne AIndex (&lt; 0) oder wenn er fehlt.</summary>
function PositionOf(const AOrder: TArray<Integer>; AIndex, ADefault: Integer): Integer;
var
  mPosition: Integer;
begin
  Result := ADefault;
  if AIndex < 0 then
  begin
    Exit;
  end;
  for mPosition := 0 to High(AOrder) do
  begin
    if AOrder[mPosition] = AIndex then
    begin
      Exit(mPosition);
    end;
  end;
end;

/// <summary>Deklaration eines unbekannten Namens (#471), Hinweis (#466) oder Rest ohne Treffer (#497)?</summary>
function IsPassiveItem(const AItem: TDpccCompletionItem; ASelected, ARestStart: Integer): Boolean;
begin
  Result := (AItem.Unknown <> '') or AItem.Hint or ((ARestStart >= 0) and (ASelected >= ARestStart));
end;

/// <summary>Nur Deklarationen (#471): sichtbar, aber nicht gewählt, solange niemand eine Pfeiltaste drückt.
/// Ebenso, wenn oben kein Treffer steht, nur der Rest (#497). Ein behaltener Eintrag (AKept) bleibt gewählt.
/// </summary>
function IsPassive(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
  ASelected, ARestStart, AKept: Integer): Boolean;
begin
  if ASelected < 0 then
  begin
    Exit(False);
  end;
  Result := IsPassiveItem(AItems[AOrder[ASelected]], ASelected, ARestStart) and
    ((AKept < 0) or (AOrder[ASelected] <> AKept));
end;

/// <summary>Beim Tippen geöffnet (L5): Ist das getippte Wort APrefix schon der Name des gewählten Eintrags, gibt es
/// nichts zu ergänzen; Enter soll dann die Zeile umbrechen statt den Eintrag zu übernehmen.</summary>
function AlreadyTyped(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
  const APrefix: string): Boolean;
begin
  Result := (APrefix <> '') and (ASelected >= 0) and (ASelected <= High(AOrder)) and
    not TDpccRanking.IsHeader(AOrder[ASelected]) and SameText(AItems[AOrder[ASelected]].Name, APrefix);
end;

/// <summary>Look-ahead: Position des ersten Eintrags in AOrder, dessen Name ohne Groß-/Kleinschreibung APrefix +
/// ARest ist; -1 ohne Rest oder ohne solchen Eintrag. Überschriften, Hinweise (#466), Deklarationen unbekannter
/// Namen (#471) und der Rest ohne Treffer (#497, ab ARestStart) zählen nicht.</summary>
function WholeWordPosition(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
  const APrefix, ARest: string; ARestStart: Integer): Integer;
var
  mWord: string;
  mPosition: Integer;
begin
  Result := -1;
  if ARest = '' then
  begin
    Exit;
  end;
  mWord := APrefix + ARest;
  for mPosition := 0 to High(AOrder) do
  begin
    if (ARestStart >= 0) and (mPosition >= ARestStart) then
    begin
      Exit;
    end;
    if not TDpccRanking.IsHeader(AOrder[mPosition]) and not IsPassiveItem(AItems[AOrder[mPosition]], -1, -1) and
      SameText(AItems[AOrder[mPosition]].Name, mWord) then
    begin
      Exit(mPosition);
    end;
  end;
end;

/// <summary>Lernzuschlag (#418) für AItems; eigene Routine, damit die Methodenreferenz nur das Nötige hält.
/// </summary>
function BoostOf(AUsage: TDpccUsage; const AItems: TDpccCompletionItems): TDpccBoostFunc;
var
  mItems: TDpccCompletionItems;
begin
  mItems := AItems;
  Result :=
    function(AIndex: Integer): Integer
    begin
      Result := AUsage.Boost(mItems[AIndex]);
    end;
end;

{ TDpccCompletionDedup }

constructor TDpccCompletionDedup.Create;
begin
  inherited Create;
  FSeen := TDictionary<string, Boolean>.Create;
end;

destructor TDpccCompletionDedup.Destroy;
begin
  FSeen.Free;
  inherited;
end;

class function TDpccCompletionDedup.KeyOf(const AItem: TDpccCompletionItem): string;
const
  // Trennzeichen, das in keinem Namen und keiner Signatur steht.
  cSeparator = #1;
var
  mFlags: Integer;
begin
  mFlags := Ord(AItem.IsAction) or (Ord(AItem.Postfix) shl 1) or (Ord(AItem.Hint) shl 2) or
    (Ord(AItem.Pinned) shl 3) or (Ord(AItem.Unavailable) shl 4);
  // Name, Unit und Klasse ohne Groß-/Kleinschreibung wie in Delphi; Signatur, Bedingung und Texte genau.
  Result := AnsiUpperCase(AItem.Name) + cSeparator + IntToStr(Ord(AItem.Kind)) + cSeparator +
    AnsiUpperCase(AItem.DeclaringUnit) + cSeparator + AnsiUpperCase(AItem.DeclaringClass) + cSeparator +
    AItem.Signature + cSeparator + AItem.Condition + cSeparator + AItem.Conversion + cSeparator +
    AnsiUpperCase(AItem.ConvertFrom) + cSeparator + AnsiUpperCase(AItem.SameNameOf) + cSeparator +
    AItem.InsertText + cSeparator + AItem.Unknown + cSeparator + AItem.Command + cSeparator + AItem.Form +
    cSeparator + AItem.Sender + cSeparator + IntToStr(mFlags);
end;

procedure TDpccCompletionDedup.Clear;
begin
  FSeen.Clear;
end;

function TDpccCompletionDedup.Count: Integer;
begin
  Result := FSeen.Count;
end;

function TDpccCompletionDedup.Unique(const AItems: TDpccCompletionItems; out ARemoved: Integer;
  out AExamples: TArray<string>): TDpccCompletionItems;
var
  mIndex, mCount: Integer;
  mKey: string;
begin
  ARemoved := 0;
  AExamples := nil;
  // Einmal anlegen statt je Eintrag anhängen (#616: bis zu 1000 Einträge je Teil).
  Result := nil;
  SetLength(Result, Length(AItems));
  mCount := 0;
  for mIndex := 0 to High(AItems) do
  begin
    mKey := KeyOf(AItems[mIndex]);
    if FSeen.ContainsKey(mKey) then
    begin
      Inc(ARemoved);
      if (Length(AExamples) < cMaxExamples) and not MatchText(AItems[mIndex].Name, AExamples) then
      begin
        AExamples := AExamples + [AItems[mIndex].Name];
      end;
      Continue;
    end;
    FSeen.Add(mKey, True);
    Result[mCount] := AItems[mIndex];
    Inc(mCount);
  end;
  SetLength(Result, mCount);
end;

{ TDpccCompletionSettings }

procedure TDpccCompletionSettings.MarkItems(var AItems: TDpccCompletionItems; AFrom: Integer);
var
  mIndex: Integer;
begin
  for mIndex := Max(0, AFrom) to High(AItems) do
  begin
    if FUsage <> nil then
    begin
      AItems[mIndex].Usage := FUsage.Mark(AItems[mIndex]);
    end;
    AItems[mIndex].Favorite := (FFavorites <> nil) and FFavorites.IsFavorite(AItems[mIndex]);
  end;
end;

function TDpccCompletionSettings.RankOptions(AMembers: Boolean; const AItems: TDpccCompletionItems): TDpccRankOptions;
begin
  Result := TDpccRankOptions.Defaults;
  Result.GroupInherited := FGroupInherited;
  if AMembers or (FListScope = TDpccListScope.Everywhere) then
  begin
    Result.ListMode := FListMode;
  end;
  if FUsage <> nil then
  begin
    Result.Boost := BoostOf(FUsage, AItems);
  end;
end;

{ TDpccCompletionState }

function TDpccCompletionState.GetVisible: Boolean;
begin
  Result := FActive and (FSelected >= 0) and (Length(FOrder) > 0);
end;

procedure TDpccCompletionState.SelectByName(const AName: string);
var
  mPosition: Integer;
begin
  for mPosition := 0 to High(FOrder) do
  begin
    if not TDpccRanking.IsHeader(FOrder[mPosition]) and (FItems[FOrder[mPosition]].Name = AName) then
    begin
      FSelected := mPosition;
      Exit;
    end;
  end;
end;

function TDpccCompletionState.SetMode: Boolean;
begin
  Result := FActive and TDpccCompletionSets.Active(FItems);
end;

function TDpccCompletionState.SelectedItem(out AItem: TDpccCompletionItem): Boolean;
begin
  Result := GetVisible and not FPassive and (FSelected >= 0) and (FSelected < Length(FOrder));
  if Result then
  begin
    AItem := FItems[FOrder[FSelected]];
  end
  else
  begin
    AItem := Default(TDpccCompletionItem);
  end;
end;

function TDpccCompletionState.CanCommitOnCharacter: Boolean;
var
  mItem: TDpccCompletionItem;
begin
  // Einträge mit Platzhaltern (#51) nur über Enter oder Tab: "while(" soll keine Schleife einsetzen.
  Result := (FPrefix <> '') and SelectedItem(mItem) and (mItem.PlaceholderText = '') and
    (TDpccCompletionMatcher.Score(FPrefix, mItem.Name) >= TDpccCompletionMatcher.cScoreWordStarts);
end;

function TDpccCompletionState.NeedsQuery(const APrefix: string): Boolean;
begin
  Result := FActive and (FIncomplete or not APrefix.StartsWith(FQueryPrefix, True));
end;

{ TDpccCompletionController.TWordPlace }

class function TDpccCompletionController.TWordPlace.At(const AContext: TDpccContext): TWordPlace;
begin
  Result.FileName := AContext.FileName;
  Result.Line := AContext.Line;
  Result.Start := AContext.Character - Length(AContext.Prefix);
end;

function TDpccCompletionController.TWordPlace.Matches(const AContext: TDpccContext): Boolean;
begin
  Result := (Line >= 0) and (AContext.Line = Line) and (AContext.Character - Length(AContext.Prefix) = Start) and
    SameText(AContext.FileName, FileName);
end;

{ TDpccCompletionController.TControllerSink }

constructor TDpccCompletionController.TControllerSink.Create(AController: TDpccCompletionController;
  AFlag: TAliveFlag; AGeneration: Integer);
begin
  inherited Create;
  FController := AController;
  FFlag := AFlag;
  FFlagRef := AFlag;
  FGeneration := AGeneration;
end;

procedure TDpccCompletionController.TControllerSink.AddItems(const AItems: TDpccCompletionItems);
var
  mController: TDpccCompletionController;
  mFlag: TAliveFlag;
  mFlagRef: IInterface;
  mGeneration: Integer;
  mItems: TDpccCompletionItems;
begin
  mController := FController;
  mFlag := FFlag;
  mFlagRef := FFlagRef;
  mGeneration := FGeneration;
  mItems := AItems;
  // Im Hauptthread läuft Queue sofort, sonst beim nächsten CheckSynchronize; beim Entladen verworfen.
  TDpccMainThread.Queue(TDpccFeature.Completion,
    procedure
    begin
      if mFlag.Alive and (mFlagRef <> nil) then
      begin
        TDpccGuard.Run(TDpccFeature.Completion,
          procedure
          begin
            mController.ItemsArrived(mGeneration, mItems);
          end);
      end;
    end);
end;

procedure TDpccCompletionController.TControllerSink.MarkIncomplete;
var
  mController: TDpccCompletionController;
  mFlag: TAliveFlag;
  mFlagRef: IInterface;
  mGeneration: Integer;
begin
  mController := FController;
  mFlag := FFlag;
  mFlagRef := FFlagRef;
  mGeneration := FGeneration;
  TDpccMainThread.Queue(TDpccFeature.Completion,
    procedure
    begin
      if mFlag.Alive and (mFlagRef <> nil) then
      begin
        TDpccGuard.Run(TDpccFeature.Completion,
          procedure
          begin
            mController.IncompleteArrived(mGeneration);
          end);
      end;
    end);
end;

procedure TDpccCompletionController.TControllerSink.MarkSyntax(const ANotice: TDpccSyntaxNotice);
var
  mController: TDpccCompletionController;
  mFlag: TAliveFlag;
  mFlagRef: IInterface;
  mGeneration: Integer;
  mNotice: TDpccSyntaxNotice;
begin
  mController := FController;
  mFlag := FFlag;
  mFlagRef := FFlagRef;
  mGeneration := FGeneration;
  mNotice := ANotice;
  TDpccMainThread.Queue(TDpccFeature.Completion,
    procedure
    begin
      if mFlag.Alive and (mFlagRef <> nil) then
      begin
        TDpccGuard.Run(TDpccFeature.Completion,
          procedure
          begin
            mController.SyntaxArrived(mGeneration, mNotice);
          end);
      end;
    end);
end;

procedure TDpccCompletionController.TControllerSink.Complete;
var
  mController: TDpccCompletionController;
  mFlag: TAliveFlag;
  mFlagRef: IInterface;
  mGeneration: Integer;
begin
  mController := FController;
  mFlag := FFlag;
  mFlagRef := FFlagRef;
  mGeneration := FGeneration;
  TDpccMainThread.Queue(TDpccFeature.Completion,
    procedure
    begin
      if mFlag.Alive and (mFlagRef <> nil) then
      begin
        TDpccGuard.Run(TDpccFeature.Completion,
          procedure
          begin
            mController.Completed(mGeneration);
          end);
      end;
    end);
end;

{ TDpccCompletionController }

constructor TDpccCompletionController.Create(const AProvider: IDpccCompletionProvider;
  const AView: IDpccCompletionView);
begin
  inherited Create;
  FProvider := AProvider;
  FView := AView;
  FFlag := TAliveFlag.Create;
  FFlag.Alive := True;
  FFlagRef := FFlag;
  FDedup := TDpccCompletionDedup.Create;
  FSelected := -1;
  FRestStart := -1;
  FDismissed.Line := -1;
end;

destructor TDpccCompletionController.Destroy;
begin
  Close;
  // Eingereihte Aufrufe halten den Merker selbst und sehen dann Alive = False.
  FFlag.Alive := False;
  FFlagRef := nil;
  FreeAndNil(FDedup);
  inherited;
end;

function TDpccCompletionController.Dismissed(const AContext: TDpccContext): Boolean;
begin
  Result := FDismissed.Matches(AContext);
end;

procedure TDpccCompletionController.Dismiss;
begin
  FDismissed := FWord;
  Close;
end;

procedure TDpccCompletionController.Start(const AContext: TDpccContext);
begin
  Close;
  if AContext.Automatic and Dismissed(AContext) then
  begin
    Exit;
  end;
  // Ein anderes Wort oder Strg+Leer hebt die Sperre auf.
  FDismissed.Line := -1;
  FWord := TWordPlace.At(AContext);
  Inc(FGeneration);
  FActive := True;
  FLoading := True;
  FPrefix := AContext.Prefix;
  FWordRest := AContext.Rest;
  FUserChose := False;
  FLookAhead := False;
  FTrigger := AContext.Trigger;
  FTyped := AContext.Typed;
  FMembers := AContext.Kind = TDpccContextKind.MemberAccess;
  FRestStart := -1;
  FToggled := False;
  FItems := nil;
  FDedup.Clear;
  FOrder := nil;
  FSelected := -1;
  FEmpty := False;
  if TDpccQueryTimings.Enabled and (TDpccQueryTimings.Shared <> nil) then
  begin
    TDpccQueryTimings.Shared.BeginQuery(AContext.Started, TimingKind(AContext), ExtractFileName(AContext.FileName));
  end;
  Query(AContext);
end;

procedure TDpccCompletionController.Query(const AContext: TDpccContext);
var
  mSink: IDpccCompletionSink;
begin
  FIncomplete := False;
  FPendingSyntax := Default(TDpccSyntaxNotice);
  FQueryPrefix := AContext.Prefix;
  mSink := TControllerSink.Create(Self, FFlag, FGeneration);
  FProvider.Query(AContext, mSink);
end;

procedure TDpccCompletionController.Requery(const AContext: TDpccContext);
begin
  if not FActive then
  begin
    Start(AContext);
    Exit;
  end;
  // Sofort lokal filtern, damit das Popup ohne Warten folgt (#409) ...
  UpdatePrefix(AContext.Prefix, AContext.Rest);
  // ... und im Hintergrund die vollständigere Liste holen; ältere Antworten verfallen.
  Inc(FGeneration);
  FLoading := True;
  FReplace := True;
  Query(AContext);
end;

procedure TDpccCompletionController.IncompleteArrived(AGeneration: Integer);
begin
  if FActive and (AGeneration = FGeneration) then
  begin
    FIncomplete := True;
  end;
end;

procedure TDpccCompletionController.SyntaxArrived(AGeneration: Integer; const ANotice: TDpccSyntaxNotice);
begin
  if not FActive or (AGeneration <> FGeneration) then
  begin
    Exit;
  end;
  FPendingSyntax := ANotice;
  FSyntax := ANotice;
  ShowSyntax;
end;

procedure TDpccCompletionController.ShowSyntax;
var
  mView: IDpccCompletionSyntaxView;
begin
  if Supports(FView, IDpccCompletionSyntaxView, mView) then
  begin
    mView.ShowSyntax(FSyntax);
  end;
end;

procedure TDpccCompletionController.Close;
begin
  if not FActive then
  begin
    Exit;
  end;
  FActive := False;
  FLoading := False;
  FTyped := False;
  FIncomplete := False;
  FSyntax := Default(TDpccSyntaxNotice);
  FPendingSyntax := FSyntax;
  FReplace := False;
  Inc(FGeneration);
  FProvider.Cancel;
  FItems := nil;
  FDedup.Clear;
  FOrder := nil;
  FSelected := -1;
  FEmpty := False;
  FPassive := False;
  FRestStart := -1;
  FWordRest := '';
  FUserChose := False;
  FLookAhead := False;
  FView.HideList;
end;

procedure TDpccCompletionController.ItemsArrived(AGeneration: Integer; const AItems: TDpccCompletionItems);
var
  mItem: TDpccCompletionItem;
  mSelectedName: string;
  mItems: TDpccCompletionItems;
begin
  if not FActive or (AGeneration <> FGeneration) or (Length(AItems) = 0) then
  begin
    Exit;
  end;
  if FReplace then
  begin
    // Neue Liste nach Requery: ersetzen. Eine eigene Wahl (Pfeiltasten, Maus) bleibt auf demselben Eintrag; die
    // automatische Vorauswahl der alten Liste klebt nicht, es gilt die der neuen.
    mSelectedName := '';
    if FUserChose and SelectedItem(mItem) then
    begin
      mSelectedName := mItem.Name;
    end;
    FReplace := False;
    // Der Abgleich beginnt mit der neuen Liste; Dubletten innerhalb dieses Teils fallen trotzdem weg.
    FDedup.Clear;
    FItems := Deduplicated(AItems);
    MarkItems(FItems, 0);
    Refresh(False);
    if (mSelectedName <> '') and (Length(FOrder) > 0) then
    begin
      SelectByName(mSelectedName);
      FView.ShowList(FItems, FOrder, FSelected, FPrefix);
    end;
    Exit;
  end;
  // Teilergebnisse (#616) und Endantwort: nur, was die Liste noch nicht hat.
  mItems := Deduplicated(AItems);
  if Length(mItems) = 0 then
  begin
    Exit;
  end;
  FItems := FItems + mItems;
  MarkItems(FItems, Length(FItems) - Length(mItems));
  // Nur eine eigene Wahl bleibt; sonst gilt nach jedem Teil die Vorauswahl der ganzen Liste (ein späteres Teil
  // kann einen besseren Treffer vor den bisher gewählten sortieren).
  Refresh(FUserChose);
end;

function TDpccCompletionController.Deduplicated(const AItems: TDpccCompletionItems): TDpccCompletionItems;
var
  mRemoved: Integer;
  mExamples: TArray<string>;
begin
  Result := FDedup.Unique(AItems, mRemoved, mExamples);
  if (mRemoved = 0) or not Assigned(FOnLog) then
  begin
    Exit;
  end;
  // Ohne diagnostics.log.names keine Namen aus dem Quelltext im Protokoll.
  if FLogNames and (Length(mExamples) > 0) then
  begin
    FOnLog(Format('Vervollständigung: %d Dubletten entfernt (z. B. %s)', [mRemoved, string.Join(', ', mExamples)]));
  end
  else
  begin
    FOnLog(Format('Vervollständigung: %d Dubletten entfernt', [mRemoved]));
  end;
end;

function TDpccCompletionController.ToggleFavorite(APosition: Integer;
  out AItem: TDpccCompletionItem): TDpccFavoriteToggle;
begin
  Result := TDpccFavoriteToggle.NotAllowed;
  AItem := Default(TDpccCompletionItem);
  if (FFavorites = nil) or not FActive or (APosition < 0) or (APosition > High(FOrder)) or
    TDpccRanking.IsHeader(FOrder[APosition]) then
  begin
    Exit;
  end;
  AItem := FItems[FOrder[APosition]];
  Result := FFavorites.Toggle(AItem);
  if (Result <> TDpccFavoriteToggle.Added) and (Result <> TDpccFavoriteToggle.Removed) then
  begin
    Exit;
  end;
  // Alle Einträge neu markieren: Derselbe Member kann aus mehreren Quellen kommen.
  MarkItems(FItems, 0);
  AItem.Favorite := Result = TDpccFavoriteToggle.Added;
  Refresh(True);
end;

function TDpccCompletionController.ToggleSelectedFavorite(out AItem: TDpccCompletionItem): TDpccFavoriteToggle;
begin
  if not SelectedItem(AItem) then
  begin
    Exit(TDpccFavoriteToggle.NotAllowed);
  end;
  Result := ToggleFavorite(FSelected, AItem);
end;

procedure TDpccCompletionController.Completed(AGeneration: Integer);
begin
  if not FActive or (AGeneration <> FGeneration) then
  begin
    Exit;
  end;
  FLoading := False;
  // Der Hinweis gilt für die Liste dieser Abfrage (#457).
  FSyntax := FPendingSyntax;
  ShowSyntax;
  // Requery ohne Einträge: Die alte Liste gilt nicht mehr.
  if FReplace then
  begin
    FReplace := False;
    FItems := nil;
    FDedup.Clear;
  end;
  // Automatisch nach "[" geöffnet, aber keine Menge (#448), oder beim Tippen geöffnet (L5): still schließen.
  if (Length(FItems) = 0) and ((FTrigger <> '') or FTyped) then
  begin
    Close;
    Exit;
  end;
  // Nichts gefunden: leerer Zustand statt kommentarlos zu verschwinden (#423).
  if Length(FItems) = 0 then
  begin
    Refresh(False);
  end;
  // Zweites Strg+Leertaste (L3): Erst jetzt steht fest, ob die Liste leer bleibt.
  if Assigned(FOnSettled) then
  begin
    FOnSettled(FEmpty);
  end;
end;

procedure TDpccCompletionController.Refresh(AKeepSelection: Boolean);
var
  mKept, mWhole: Integer;
  mTimings: TDpccQueryTimings;
  mStamp: Int64;
begin
  // Diagnosemodus (#479): nur an einen Zeitstempel nehmen.
  mTimings := nil;
  mStamp := 0;
  if TDpccQueryTimings.Enabled then
  begin
    mTimings := TDpccQueryTimings.Shared;
    mStamp := TDpccQueryTimings.Stamp;
  end;
  mKept := KeptIndex(FOrder, FSelected, AKeepSelection, FPassive);
  FOrder := TDpccRanking.Order(FItems, FPrefix, RankOptions(FMembers, FItems), FRestStart);
  if mTimings <> nil then
  begin
    mTimings.FilterSorted(TDpccQueryTimings.MsSince(mStamp), Length(FItems), TDpccRanking.ItemCount(FOrder));
  end;
  FSelected := FirstSelection(FItems, FOrder);
  FSelected := PositionOf(FOrder, mKept, FSelected);
  // Look-ahead: den Eintrag Präfix + Rest wählen, solange niemand selbst gewählt hat; die Reihenfolge bleibt.
  mWhole := -1;
  if not FUserChose then
  begin
    mWhole := WholeWordPosition(FItems, FOrder, FPrefix, FWordRest, FRestStart);
  end;
  FLookAhead := mWhole >= 0;
  if FLookAhead then
  begin
    FSelected := mWhole;
  end;
  FEmpty := False;
  FPassive := IsPassive(FItems, FOrder, FSelected, FRestStart, mKept) or
    (FTyped and (mKept < 0) and AlreadyTyped(FItems, FOrder, FSelected, FPrefix));
  if (mTimings <> nil) and (FSelected >= 0) then
  begin
    mTimings.ListShown;
  end;
  ShowResult;
end;

procedure TDpccCompletionController.ShowResult;
begin
  if FPassive then
  begin
    FView.ShowList(FItems, FOrder, -1, FPrefix);
  end
  else if FSelected >= 0 then
  begin
    FView.ShowList(FItems, FOrder, FSelected, FPrefix);
  end
  else
  begin
    FSelected := -1;
    // Solange noch nichts da ist, nichts zeigen; sonst den leeren Zustand.
    if FLoading and (Length(FItems) = 0) then
    begin
      FView.HideList;
    end
    else
    begin
      FEmpty := True;
      FView.ShowEmpty(FPrefix, Length(FItems));
    end;
  end;
end;

procedure TDpccCompletionController.UpdatePrefix(const APrefix: string);
begin
  UpdatePrefix(APrefix, FWordRest);
end;

procedure TDpccCompletionController.UpdatePrefix(const APrefix, ARest: string);
begin
  if not FActive or ((APrefix = FPrefix) and (ARest = FWordRest)) then
  begin
    Exit;
  end;
  if APrefix = FPrefix then
  begin
    // Nur der Rest hat sich geändert (Entf hinter dem Cursor): eine eigene Auswahl bleibt, sonst neu vorwählen.
    FWordRest := ARest;
    if not FUserChose then
    begin
      Refresh(False);
    end;
    Exit;
  end;
  // Weitertippen verwirft das Angebot „Mit try…finally absichern“ (#489).
  if (APrefix <> '') and TDpccItemPresentation.Guarding(FItems) then
  begin
    Close;
    Exit;
  end;
  FPrefix := APrefix;
  FWordRest := ARest;
  // Refresh setzt die Auswahl zurück; der Look-ahead gilt wieder.
  FUserChose := False;
  Refresh(False);
end;

procedure TDpccCompletionController.MoveSelection(APosition: Integer);
begin
  MoveSelection(APosition, 1);
end;

procedure TDpccCompletionController.MoveSelection(APosition, ADirection: Integer);
begin
  // Erste Pfeiltaste ohne Auswahl (#471): die erste Deklaration wählen.
  if FPassive then
  begin
    FPassive := False;
    FUserChose := True;
    FView.ShowList(FItems, FOrder, FSelected, FPrefix);
    Exit;
  end;
  // Überschriften (#419) werden übersprungen.
  APosition := FirstItemIn(FOrder, EnsureRange(APosition, 0, High(FOrder)), ADirection);
  if (APosition < 0) or (APosition = FSelected) then
  begin
    Exit;
  end;
  FSelected := APosition;
  // Eigene Wahl: Der Look-ahead überschreibt sie beim nächsten Refresh nicht.
  FUserChose := True;
  FView.ShowList(FItems, FOrder, FSelected, FPrefix);
end;

function TDpccCompletionController.MoveByKey(AKey: TDpccNavigationKey; APage: Integer): Boolean;
begin
  Result := True;
  case AKey of
    TDpccNavigationKey.Up:
      MoveSelection(FSelected - 1, -1);
    TDpccNavigationKey.Down:
      MoveSelection(FSelected + 1);
    TDpccNavigationKey.PageUp:
      MoveSelection(FSelected - APage, -1);
    TDpccNavigationKey.PageDown:
      MoveSelection(FSelected + APage);
    TDpccNavigationKey.First:
      MoveSelection(0);
    TDpccNavigationKey.Last:
      MoveSelection(High(FOrder), -1);
  else
    Result := False;
  end;
end;

function TDpccCompletionController.AcceptKey: Boolean;
begin
  Result := True;
  if FPassive then
  begin
    Close;
    Result := False;
  end
  else if SetMode then
  begin
    CommitSet;
  end
  else
  begin
    CommitSelected;
  end;
end;

function TDpccCompletionController.ToggleKey: Boolean;
begin
  Result := SetMode;
  if Result then
  begin
    ToggleSelected;
  end;
end;

function TDpccCompletionController.HandleKey(AKey: TDpccNavigationKey): Boolean;
var
  mPage: Integer;
begin
  // Leerer Zustand: nur Esc gehört dem Popup; Pfeile und Enter gehen an den Editor.
  if FActive and FEmpty and (AKey = TDpccNavigationKey.Cancel) then
  begin
    Dismiss;
    Exit(True);
  end;
  if not GetVisible then
  begin
    Exit(False);
  end;
  mPage := Max(1, FView.PageSize - 1);
  Result := True;
  if MoveByKey(AKey, mPage) then
  begin
    Exit;
  end;
  case AKey of
    TDpccNavigationKey.Accept:
      Result := AcceptKey;
    TDpccNavigationKey.Cancel:
      Dismiss;
    TDpccNavigationKey.Toggle:
      Result := ToggleKey;
  else
    // Bewegungen hat MoveByKey genommen.
  end;
end;

procedure TDpccCompletionController.ToggleSelected;
var
  mIndex: Integer;
begin
  if (FSelected < 0) or (FSelected > High(FOrder)) or TDpccRanking.IsHeader(FOrder[FSelected]) then
  begin
    Exit;
  end;
  mIndex := FOrder[FSelected];
  FItems[mIndex].Checked := not FItems[mIndex].Checked;
  FToggled := True;
  FView.ShowList(FItems, FOrder, FSelected, FPrefix);
end;

procedure TDpccCompletionController.CommitSet;
var
  mItem: TDpccCompletionItem;
begin
  // Ohne Leertaste: Enter übernimmt den gewählten Wert zusätzlich zu den vorhandenen.
  if not FToggled and (FSelected >= 0) and (FSelected <= High(FOrder)) and
    not TDpccRanking.IsHeader(FOrder[FSelected]) then
  begin
    FItems[FOrder[FSelected]].Checked := True;
  end;
  mItem := TDpccCompletionSets.CommitItem(FItems);
  Close;
  if Assigned(FOnCommit) then
  begin
    FOnCommit(mItem);
  end;
end;

procedure TDpccCompletionController.Select(APosition: Integer);
begin
  if GetVisible then
  begin
    MoveSelection(APosition);
  end;
end;

procedure TDpccCompletionController.CommitSelected;
var
  mItem: TDpccCompletionItem;
begin
  if not SelectedItem(mItem) then
  begin
    Exit;
  end;
  // Alle Felder zuweisen mit vielen Feldern (#491): erst die Liste mit Kontrollkästchen, Enter übernimmt.
  if Length(mItem.Assignments) > 0 then
  begin
    FItems := TDpccCompletionSets.AssignItems(mItem);
    // Eigene Liste ohne Abgleich mit der alten.
    FDedup.Clear;
    FToggled := True;
    // Die Liste zeigt alle Felder, auch wenn hinter dem Punkt schon etwas getippt ist; späte Antworten der
    // alten Anfrage gehören nicht mehr dazu.
    FPrefix := '';
    FWordRest := '';
      Inc(FGeneration);
    FLoading := False;
    Refresh(False);
    Exit;
  end;
  if FUsage <> nil then
  begin
    FUsage.Record_(mItem);
  end;
  Close;
  if Assigned(FOnCommit) then
  begin
    FOnCommit(mItem);
  end;
end;

end.
