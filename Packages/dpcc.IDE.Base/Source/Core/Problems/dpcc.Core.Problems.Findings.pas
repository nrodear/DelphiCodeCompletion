unit dpcc.Core.Problems.Findings;

// Modell des Fensters „dpcc-Prüfung“ (#909), ohne VCL und Open Tools API.
// Die Befunde kommen aus demselben Speicher wie Wellenlinien und Hover
// (TDpccProblemStore, #398); es gibt keine zweite Prüfung.
// - TDpccFindings: Befunde aus dem Speicher (ohne inaktive Zweige, uses-
//   Hinweise und Testmeldungen), Art aus dem Schweregrad (error → Error,
//   warning → Warnung, information/hint → Info), Kategorie aus dem Katalog
//   bzw. „Compiler“ für dcc, Zeilentext ohne Einrückung, Spalten-Layout als
//   Text für problems.window.columns. Spalte „Compiler“ (#1024): Code der
//   Compilermeldung bzw. die Codes, denen die Regel entspricht, mit
//   „dpcc + dcc“, wenn der letzte Build den Befund bestätigt.
// - TDpccFindingsCache (dpcc.Core.Problems.FindingsCache) baut darauf auf.
// - TDpccFindingsView: Filter (Bereich, Arten, Kategorie, Text, Compiler),
//   Gruppierung (keine, Datei, Regel, Kategorie), Sortierung (Vorgabe Art,
//   Datei, Zeile; Klick auf eine Spalte sortiert nach ihr, zweiter Klick
//   kehrt um), Zeilen mit aufklappbaren Gruppen, Zähler je Art. Neue Befunde
//   werden kurz markiert (IsNew). Auswahl und Aufklappzustand hängen an
//   Schlüsseln, die nicht von der Zeile abhängen: Sie bleiben erhalten, wenn
//   die Zeilen beim Tippen mitwandern oder neue Ergebnisse kommen.
// - Offene Units zuerst (#1108, problems.window.openFirst): Die Stufe (aktive
//   Unit, geöffnete Units, nicht geöffnete Units) ist der erste
//   Sortierschlüssel, die Spaltensortierung gilt innerhalb der Stufe. Bei
//   Gruppierung nach Datei steht die Gruppe der aktiven Unit angepinnt oben,
//   darunter Trennzeilen „Geöffnet“ und „Nicht geöffnet“ mit den Gruppen
//   alphabetisch; ohne Gruppierung dieselben drei Abschnitte als Trennzeilen;
//   bei Regel oder Kategorie nur die Reihenfolge innerhalb jeder Gruppe.
//   Nicht geöffnete Units ausgegraut, normal oder ausgeblendet
//   (problems.window.closedUnits); die aktive Unit auf Wunsch auch ohne
//   Befunde (problems.window.showCleanActive). Trennzeilen sind weder Gruppen
//   noch Befunde: nicht klappbar, nicht wählbar, nicht in Visible, Step,
//   SelectAt und beim Kopieren. .pas und .dfm/.fmx einer Unit zählen als eine.
// - Fehler der IDE (#1819, problems.ideErrors): Die Befunde kommen aus
//   WithIde des Speichers, abgeglichen mit Error Insight. Spalte „Quelle“
//   (dpcc, dpcc + IDE, IDE) und Filter Origin (alle, nur dpcc, nur IDE).
// - IDpccBulkFixer: Vertrag der Sammelkorrektur (#1352) für das Modul
//   Prüfregeln (#1455).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Core.Problems.Contract,
  dpcc.Core.Problems.IdeErrors,
  dpcc.Core.Problems.Store;

type
  {$SCOPEDENUMS ON}
  /// <summary>Spalte „Art“: Error (auch Bug), Warnung, Info (information und hint).</summary>
  TDpccFindingKind = (Error, Warning, Info);
  TDpccFindingCategory = (Bug, Vulnerability, CodeSmell, SecurityHotspot, Compiler, Other);
  TDpccFindingColumn = (Icon, Kind, Category, Message, Line, Location, Rule, Compiler, Source);
  /// <summary>Filter „Quelle“ (#1819): dpcc und IDE (alle), nur dpcc, nur IDE.</summary>
  TDpccFindingOrigin = (All, DpccOnly, IdeOnly);
  TDpccFindingScope = (CurrentFile, Project, Group);
  TDpccFindingGrouping = (None, ByFile, ByRule, ByCategory);
  /// <summary>Stufe einer Datei (#1108): Datei des oberen Editors, in der IDE geöffnet, nicht geöffnet.</summary>
  TDpccFindingTier = (Active, Open, Closed);
  /// <summary>Darstellung nicht geöffneter Units (problems.window.closedUnits).</summary>
  TDpccClosedUnits = (Dimmed, Normal, Hidden);
  {$SCOPEDENUMS OFF}
  TDpccFindingKinds = set of TDpccFindingKind;

  TDpccFinding = record
    FileName: string;
    Problem: TDpccProblem;
    Kind: TDpccFindingKind;
    Category: TDpccFindingCategory;
    /// <summary>Betroffene Quelltextzeile ohne führenden und folgenden Leerraum; '' wenn unbekannt.</summary>
    LineText: string;
    /// <summary>Datei, Regel, Meldung und laufende Nummer: unabhängig von der Zeile.</summary>
    Key: string;
    /// <summary>Stufe der Datei (#1108); setzt TDpccFindingsView aus den geöffneten Dateien.</summary>
    Tier: TDpccFindingTier;
    /// <summary>"Unit1.pas:12:5" (1-basiert).</summary>
    function Location: string;
    /// <summary>Zeilentext, gekürzt auf AMax Zeichen mit „…“.</summary>
    function ShortLine(AMax: Integer): string;
    /// <summary>Regel-ID bzw. Meldungsnummer des Compilers.</summary>
    function Rule: string;
    /// <summary>Spalte „Compiler“ (#1024): "E2035", "E2034, E2035" oder "E2035 · dpcc + dcc" bei einem vom
    /// Build bestätigten Befund; '' ohne Code.</summary>
    function CompilerText: string;
    /// <summary>Spalte „Quelle“ (#1819): "dpcc", "dpcc + IDE", "IDE" bzw. die Quelle (dcc, DUnitX, Aufgabe).
    /// </summary>
    function SourceText: string;
    /// <summary>Meldung; ohne AShowCompilerCode (problems.showCompilerCode aus) ohne „(wie E2035)“.</summary>
    function MessageText(AShowCompilerCode: Boolean): string;
  end;

  /// <summary>Sammelkorrektur (#1352) im Kontextmenü von „dpcc-Prüfung“; ein Modul stellt sie bereit (#1455, Modul
  /// Prüfregeln), das Fenster fragt laufende Module. Ohne Modul fehlt der Eintrag.</summary>
  IDpccBulkFixer = interface
    ['{3B7E2D91-5A4C-4F68-9E13-C82D6A0F7B54}']
    /// <summary>Eintrag sichtbar (fix.bulk an).</summary>
    function CanFixAll: Boolean;
    /// <summary>Alle sicheren Treffer von ARule in den Dateien von AFindings (den angezeigten Befunden) korrigieren:
    /// Vorschau, dann die gewählten Dateien. Nur im Hauptthread.</summary>
    procedure FixAll(const ARule: string; const AFindings: TArray<TDpccFinding>);
  end;

  TDpccFindingColumnState = record
    Column: TDpccFindingColumn;
    /// <summary>Breite in Pixeln bei 96 dpi; 0 = Vorgabe.</summary>
    Width: Integer;
    Visible: Boolean;
    class function Create(AColumn: TDpccFindingColumn; AWidth: Integer; AVisible: Boolean):
      TDpccFindingColumnState; static;
  end;

  TDpccFindingCounts = record
    Errors: Integer;
    Warnings: Integer;
    Infos: Integer;
    /// <summary>Dateien mit sichtbaren Befunden.</summary>
    Files: Integer;
    /// <summary>Offene Units zuerst (#1108): Units der aktiven und geöffneten Stufe mit sichtbaren Befunden und
    /// deren Befunde; sonst 0.</summary>
    OpenUnits: Integer;
    OpenFindings: Integer;
    /// <summary>Nicht geöffnete Units mit sichtbaren Befunden und deren Befunde; sonst 0.</summary>
    ClosedUnits: Integer;
    ClosedFindings: Integer;
    /// <summary>Nicht geöffnete Units, deren Befunde problems.window.closedUnits = hidden ausblendet.</summary>
    HiddenUnits: Integer;
    function Total: Integer;
    function OfKind(AKind: TDpccFindingKind): Integer;
  end;

  TDpccFindingFilter = record
    Scope: TDpccFindingScope;
    Kinds: TDpccFindingKinds;
    /// <summary>False = alle Kategorien.</summary>
    OneCategory: Boolean;
    Category: TDpccFindingCategory;
    /// <summary>Teiltext in Meldung, Regel oder Datei (Groß-/Kleinschreibung egal); '' = alle.</summary>
    Text: string;
    /// <summary>Compilermeldungen zeigen (problems.window.compiler).</summary>
    Compiler: Boolean;
    /// <summary>Filter „Quelle“ (#1819); nur dpcc bzw. nur IDE ohne Compiler, Tests und Aufgaben.</summary>
    Origin: TDpccFindingOrigin;
    /// <summary>Bereich „aktuelle Datei“.</summary>
    CurrentFile: string;
    /// <summary>Bereich „Projekt“ bzw. „Projektgruppe“: Dateien des Bereichs; nil = alle Dateien des
    /// Speichers.</summary>
    Files: TArray<string>;
    /// <summary>Alle Arten und Kategorien, Bereich Projektgruppe, ohne Compiler.</summary>
    class function Create: TDpccFindingFilter; static;
    /// <summary>Alles außer den Arten: für die Zähler auf den Umschaltern.</summary>
    function MatchesExceptKind(const AFinding: TDpccFinding): Boolean;
    function Matches(const AFinding: TDpccFinding): Boolean;
  end;

  TDpccFindingRow = record
    IsGroup: Boolean;
    /// <summary>Gruppe der Zeile bzw. des Befunds; '' ohne Gruppierung.</summary>
    GroupKey: string;
    /// <summary>Gruppenzeile: Datei (ohne Pfad), Regel oder Kategorie (Name der Kategorie); sonst ''.</summary>
    Caption: string;
    /// <summary>Gruppenzeile: Befunde der Gruppe.</summary>
    Count: Integer;
    /// <summary>Gruppenzeile: Kategorie bei Gruppierung nach Kategorie.</summary>
    Category: TDpccFindingCategory;
    Expanded: Boolean;
    /// <summary>Befundzeile: Index in TDpccFindingsView.Findings; -1 bei Gruppenzeilen.</summary>
    Finding: Integer;
    /// <summary>Befund kam mit der letzten Aktualisierung neu dazu.</summary>
    IsNew: Boolean;
    /// <summary>Trennzeile (#1108): „Geöffnet“, „Nicht geöffnet“, ohne Gruppierung auch die aktive Unit; weder
    /// Gruppe noch Befund. Caption = Datei der aktiven Unit, Count = Befunde, Units = Units des Abschnitts.</summary>
    IsSection: Boolean;
    Units: Integer;
    /// <summary>Stufe der Zeile; nur mit Offene-zuerst aussagekräftig.</summary>
    Tier: TDpccFindingTier;
    /// <summary>Zeile der aktiven Unit: hinterlegt, Gruppe mit Nadel.</summary>
    Pinned: Boolean;
    /// <summary>Zeile einer nicht geöffneten Unit: ausgegraut (problems.window.closedUnits = dimmed).</summary>
    Dimmed: Boolean;
    /// <summary>Aktive Unit ohne Befunde (problems.window.showCleanActive): Trennzeile „Keine Befunde“ bzw. „wird
    /// geprüft …“ (Checking), solange der Server die Datei noch nicht geliefert hat.</summary>
    IsCleanActive: Boolean;
    Checking: Boolean;
  end;

  TDpccFindings = class
  public const
    /// <summary>Zeilentext in der Spalte „Zeile“; länger mit „…“, der Tooltip zeigt die ganze Zeile.</summary>
    cLineMax = 80;
    cColumnNames: array[TDpccFindingColumn] of string = ('icon', 'kind', 'category', 'message', 'line',
      'location', 'rule', 'compiler', 'source');
    /// <summary>Marke eines vom Compiler bestätigten Befunds (#1024).</summary>
    cConfirmedMark = TDpccProblem.cConfirmedSource;
    cScopeNames: array[TDpccFindingScope] of string = ('file', 'project', 'group');
    cGroupingNames: array[TDpccFindingGrouping] of string = ('none', 'file', 'rule', 'category');
    cClosedUnitsNames: array[TDpccClosedUnits] of string = ('dimmed', 'normal', 'hidden');
  public
    /// <summary>Vergleichsschlüssel einer Datei (#1108): Kleinbuchstaben, Formular (.dfm/.fmx) als seine .pas.
    /// </summary>
    class function UnitKey(const AFileName: string): string; static;
    class function TryParseClosedUnits(const AText: string; out AValue: TDpccClosedUnits): Boolean; static;
    class function KindOf(ASeverity: TDpccProblemSeverity): TDpccFindingKind; static;
    /// <summary>dcc = Compiler; sonst nach data.category ("bug", "vulnerability", "code-smell",
    /// "security-hotspot"), ohne Kategorie Other.</summary>
    class function CategoryOf(const AProblem: TDpccProblem): TDpccFindingCategory; static;
    /// <summary>Gehört der Eintrag in das Fenster? Ohne inaktive Zweige, uses-Hinweise (#621) und Tests (#69).
    /// </summary>
    class function IsFinding(const AProblem: TDpccProblem): Boolean; static;
    /// <summary>Befunde der Dateien AFiles (nil = alle Dateien des Speichers). Zeilentext aus dem bekannten Text
    /// des Speichers, sonst aus den Zeilen von AReadLines (je Datei höchstens ein Aufruf; nil = ohne).</summary>
    class function FromStore(AStore: TDpccProblemStore; const AFiles: TArray<string>;
      const AReadLines: TFunc<string, TArray<string>>): TArray<TDpccFinding>; static;
    /// <summary>Befunde einer Datei des Speichers, Zeilentext wie bei FromStore.</summary>
    class function FromStoreFile(AStore: TDpccProblemStore; const AFileName: string;
      const AReadLines: TFunc<string, TArray<string>>): TArray<TDpccFinding>; static;
    /// <summary>Hängt die Listen aneinander, mit einer einzigen Belegung.</summary>
    class function Concat(const AParts: TArray<TArray<TDpccFinding>>): TArray<TDpccFinding>; static;
    /// <summary>Aus einer Liste je Datei; vergibt die Schlüssel.</summary>
    class function FromProblems(const AFileName: string; const AProblems: TArray<TDpccProblem>;
      const ALines: TArray<string>): TArray<TDpccFinding>; static;
    /// <summary>Ohne führenden und folgenden Leerraum, gekürzt auf AMax Zeichen mit „…“.</summary>
    class function Shorten(const AText: string; AMax: Integer): string; static;
    /// <summary>Wie viele von AProjectFiles hat der Server schon geliefert (Statuszeile „214 von 214 Units
    /// geprüft“)?</summary>
    class function CheckedCount(AStore: TDpccProblemStore; const AProjectFiles: TArray<string>): Integer; static;
    /// <summary>Spalten aus problems.window.columns: "kind:70,category,-rule,…" (Name, optional Breite, "-" =
    /// ausgeblendet). Unbekannte Namen fallen weg, fehlende Spalten kommen hinten dazu; Pflichtspalten sind immer
    /// sichtbar. '' = alle in der Vorgabe-Reihenfolge.</summary>
    class function ParseColumns(const AText: string): TArray<TDpccFindingColumnState>; static;
    class function FormatColumns(const AColumns: TArray<TDpccFindingColumnState>): string; static;
    /// <summary>Icon, Art, Kategorie, Zeile und Stelle lassen sich nicht ausblenden.</summary>
    class function IsMandatory(AColumn: TDpccFindingColumn): Boolean; static;
    class function TryParseScope(const AText: string; out AScope: TDpccFindingScope): Boolean; static;
    class function TryParseGrouping(const AText: string; out AGrouping: TDpccFindingGrouping): Boolean; static;
    /// <summary>„Kopieren“: je Befund eine Zeile im Format des Compilers, "Unit.pas:12:5: warning [regel]
    /// Meldung", dahinter eingerückt der Zeilentext; Zeilenende CRLF.</summary>
    class function AsText(const AFindings: TArray<TDpccFinding>): string; static;
  end;

  /// <summary>Befunde je Stufe in der angezeigten Reihenfolge (Indizes in die Befunde).</summary>
  TDpccFindingTierMembers = array[TDpccFindingTier] of TArray<Integer>;

  /// <summary>Befunde mit Filter und Stufen (offene Units zuerst, #1108); Grundlage von TDpccFindingsView.
  /// </summary>
  TDpccFindingsSource = class
  protected
    FFindings: TArray<TDpccFinding>;
    FFilter: TDpccFindingFilter;
    FKnown: TDictionary<string, Boolean>;
    FNew: TDictionary<string, Boolean>;
    FFilled: Boolean;
    FOpenFirst: Boolean;
    FClosedUnits: TDpccClosedUnits;
    FShowCleanActive: Boolean;
    FActiveFile: string;
    FActiveKey: string;
    FActiveChecked: Boolean;
    FOpenKeys: TDictionary<string, Boolean>;
    /// <summary>Zeilen und Zähler nach einer Änderung neu aufbauen.</summary>
    procedure Rebuild; virtual; abstract;
    procedure SetFilter(const AValue: TDpccFindingFilter);
    procedure SetOpenFirst(AValue: Boolean);
    procedure SetClosedUnits(AValue: TDpccClosedUnits);
    procedure SetShowCleanActive(AValue: Boolean);
    function TierOf(const AFileName: string): TDpccFindingTier;
    procedure AssignTiers;
    /// <summary>Wird AFinding wegen problems.window.closedUnits = hidden ausgeblendet?</summary>
    function HiddenByTier(const AFinding: TDpccFinding): Boolean;
    function IsActiveInScope: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neuer Stand aus dem Speicher. Befunde, deren Schlüssel vorher fehlte, sind neu (nicht beim ersten
    /// Füllen).</summary>
    procedure SetFindings(const AFindings: TArray<TDpccFinding>);
    /// <summary>Offene Units zuerst (#1108): AActive = Datei des oberen Editors ('' = keine), AOpen = alle in der
    /// IDE geöffneten Dateien; AActiveChecked = der Server hat die aktive Datei schon geliefert (sonst zeigt die
    /// Zeile ohne Befunde „wird geprüft …“).</summary>
    procedure SetOpenFiles(const AActive: string; const AOpen: TArray<string>; AActiveChecked: Boolean);
    /// <summary>Wirkt die Stufe gerade? Offene-zuerst an und Bereich nicht „Aktuelle Datei“.</summary>
    function TiersActive: Boolean;
    /// <summary>Markierung „neu“ entfernen (nach dem kurzen Hervorheben).</summary>
    procedure ClearNew;
    function Finding(AIndex: Integer): TDpccFinding;
    property Filter: TDpccFindingFilter read FFilter write SetFilter;
    /// <summary>problems.window.openFirst; im Modell Vorgabe aus, die Einstellung hat Vorgabe an.</summary>
    property OpenFirst: Boolean read FOpenFirst write SetOpenFirst;
    /// <summary>problems.window.closedUnits (Vorgabe ausgegraut).</summary>
    property ClosedUnits: TDpccClosedUnits read FClosedUnits write SetClosedUnits;
    /// <summary>problems.window.showCleanActive (Vorgabe an).</summary>
    property ShowCleanActive: Boolean read FShowCleanActive write SetShowCleanActive;
    property ActiveFile: string read FActiveFile;
  end;

  /// <summary>Gruppierung und Sortierung der Befunde.</summary>
  TDpccFindingsSorted = class(TDpccFindingsSource)
  protected
    FGrouping: TDpccFindingGrouping;
    FSortColumn: TDpccFindingColumn;
    FSortDescending: Boolean;
    FSortCustom: Boolean;
    procedure SetGrouping(AValue: TDpccFindingGrouping);
    function GroupKeyOf(const AFinding: TDpccFinding): string;
    function Compare(const A, B: TDpccFinding): Integer;
    /// <summary>Reihenfolge zweier Gruppen nach ihrem ersten Befund; bei Gleichstand nach dem Schlüssel.</summary>
    function CompareGroups(const AFirstA, AFirstB: TDpccFinding; const AKeyA, AKeyB: string): Integer;
    /// <summary>Indizes der Befunde unter Filter und Stufe, sortiert.</summary>
    function SortedMatches: TArray<Integer>;
    /// <summary>Trennzeilen der Stufen gelten nach Datei (bei Regel und Kategorie würden sie sich wiederholen).
    /// </summary>
    function TiersByFile: Boolean;
  public
    constructor Create;
    /// <summary>Klick auf den Spaltenkopf: nach AColumn sortieren, beim zweiten Klick absteigend.</summary>
    procedure SortBy(AColumn: TDpccFindingColumn);
    /// <summary>Zurück zur Vorgabe: Art, Datei, Zeile.</summary>
    procedure ResetSort;
    property Grouping: TDpccFindingGrouping read FGrouping write SetGrouping;
    property SortDescending: Boolean read FSortDescending;
    property SortCustom: Boolean read FSortCustom;
  end;

  TDpccFindingsView = class(TDpccFindingsSorted)
  private
    FCollapsed: TDictionary<string, Boolean>;
    FVisible: TArray<Integer>;
    FRows: TArray<TDpccFindingRow>;
    FSelectedKey: string;
    // Counts bis zum nächsten Rebuild: Das Fenster fragt sie in jedem Takt für die Statuszeile.
    FCounts: TDpccFindingCounts;
    FCountsValid: Boolean;
    // BeginUpdate/EndUpdate: ein Neuaufbau für mehrere Änderungen.
    FUpdateCount: Integer;
    FRebuildPending: Boolean;
    function GetSelectedRow: Integer;
    /// <summary>Zeile für AFinding mit Stufe, Nadel und Grau.</summary>
    function FindingRow(AIndex: Integer; const AGroupKey: string): TDpccFindingRow;
    /// <summary>Trennzeile der Stufe ATier über die Befunde AMembers.</summary>
    function SectionRow(ATier: TDpccFindingTier; const AMembers: TArray<Integer>): TDpccFindingRow;
    /// <summary>Zeile „Keine Befunde“ der aktiven Unit, wenn sie gezeigt werden soll.</summary>
    function CleanActiveRow(out ARow: TDpccFindingRow): Boolean;
    /// <summary>Kopfzeile der Gruppe AKey mit ihrem ersten Befund und Aufklappzustand.</summary>
    function GroupRow(const AKey: string; const AFirst: TDpccFinding; ACount: Integer): TDpccFindingRow;
    /// <summary>Ohne Gruppierung (#1108): die drei Stufen als Trennzeilen, die aktive Unit auch ohne Befunde.
    /// </summary>
    procedure RebuildFlat(const AOrder: TArray<Integer>; const AOfTier: TDpccFindingTierMembers;
      ARows: TList<TDpccFindingRow>);
    procedure RebuildGrouped(const AOrder: TArray<Integer>; const AOfTier: TDpccFindingTierMembers;
      ARows: TList<TDpccFindingRow>);
    /// <summary>Indizes der sichtbaren Befunde der Gruppe AGroupKey.</summary>
    function GroupMembers(const AGroupKey: string): TArray<Integer>;
  protected
    procedure Rebuild; override;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Änderungen sammeln (Filter, Befunde, offene Dateien): Zeilen und Zähler werden erst mit dem letzten
    /// EndUpdate einmal neu aufgebaut, nicht nach jeder einzelnen Änderung. Dazwischen nicht lesen.</summary>
    procedure BeginUpdate;
    procedure EndUpdate;
    function Rows: TArray<TDpccFindingRow>;
    /// <summary>Befunde in der angezeigten Reihenfolge (gefiltert, unabhängig vom Aufklappen).</summary>
    function Visible: TArray<TDpccFinding>;
    /// <summary>Zähler je Art unter dem Filter ohne die Arten; Files zählt die Dateien der sichtbaren Befunde.
    /// </summary>
    function Counts: TDpccFindingCounts;
    /// <summary>Gruppe auf- bzw. zuklappen (bleibt über Aktualisierungen erhalten).</summary>
    procedure SetExpanded(const AGroupKey: string; AExpanded: Boolean);
    procedure Toggle(ARow: Integer);
    procedure Select(ARow: Integer);
    /// <summary>Markierung folgt dem Cursor: ersten Befund auf der Zeile (0-basiert) wählen; True, wenn einer
    /// gefunden wurde. Klappt seine Gruppe auf.</summary>
    function SelectAt(const AFileName: string; ALine: Integer): Boolean;
    /// <summary>Nächster bzw. vorheriger Befund der gefilterten Liste ab der Auswahl (am Ende wieder vorn); wählt
    /// ihn aus und klappt seine Gruppe auf.</summary>
    function Step(AForward: Boolean; out AFinding: TDpccFinding): Boolean;
    /// <summary>Befunde der Zeilen ARows ohne Doppelte, zum Kopieren; eine Gruppenzeile steht für ihre Befunde.
    /// </summary>
    function FindingsOfRows(const ARows: TArray<Integer>): TArray<TDpccFinding>;
    function SelectedFinding(out AFinding: TDpccFinding): Boolean;
    property SelectedKey: string read FSelectedKey write FSelectedKey;
    /// <summary>-1 ohne Auswahl oder wenn der gewählte Befund nicht sichtbar ist.</summary>
    property SelectedRow: Integer read GetSelectedRow;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults;

const
  cCategoryNames: array[TDpccFindingCategory] of string = ('bug', 'vulnerability', 'code-smell',
    'security-hotspot', 'compiler', '');

{ TDpccFinding }

function TDpccFinding.Location: string;
begin
  Result := Format('%s:%d:%d', [ExtractFileName(FileName), Problem.StartLine + 1, Problem.StartCharacter + 1]);
end;

function TDpccFinding.ShortLine(AMax: Integer): string;
begin
  Result := TDpccFindings.Shorten(LineText, AMax);
end;

function TDpccFinding.Rule: string;
begin
  Result := Problem.Code;
end;

function TDpccFinding.CompilerText: string;
begin
  Result := Problem.CompilerCodeText;
  if Problem.Confirmed then
  begin
    Result := Result + ' ' + #$00B7 + ' ' + TDpccFindings.cConfirmedMark;
  end;
end;

function TDpccFinding.SourceText: string;
begin
  Result := TDpccIdeErrors.OriginText(Problem);
end;

function TDpccFinding.MessageText(AShowCompilerCode: Boolean): string;
begin
  Result := Problem.Message;
  if not AShowCompilerCode then
  begin
    Result := TDpccProblem.WithoutCompilerCode(Result);
  end;
end;

{ TDpccFindingColumnState }

class function TDpccFindingColumnState.Create(AColumn: TDpccFindingColumn; AWidth: Integer;
  AVisible: Boolean): TDpccFindingColumnState;
begin
  Result.Column := AColumn;
  Result.Width := AWidth;
  Result.Visible := AVisible;
end;

{ TDpccFindingCounts }

function TDpccFindingCounts.Total: Integer;
begin
  Result := Errors + Warnings + Infos;
end;

function TDpccFindingCounts.OfKind(AKind: TDpccFindingKind): Integer;
begin
  case AKind of
    TDpccFindingKind.Error:
      Result := Errors;
    TDpccFindingKind.Warning:
      Result := Warnings;
  else
    Result := Infos;
  end;
end;

{ TDpccFindingFilter }

class function TDpccFindingFilter.Create: TDpccFindingFilter;
begin
  Result := Default(TDpccFindingFilter);
  Result.Scope := TDpccFindingScope.Group;
  Result.Kinds := [TDpccFindingKind.Error, TDpccFindingKind.Warning, TDpccFindingKind.Info];
end;

/// <summary>AFileName steht in AFiles (ohne Groß-/Kleinschreibung).</summary>
function InFiles(const AFiles: TArray<string>; const AFileName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in AFiles do
  begin
    if SameText(mName, AFileName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Meldung, Code oder Dateiname enthalten ANeedle (klein geschrieben).</summary>
function ContainsNeedle(const AFinding: TDpccFinding; const ANeedle: string): Boolean;
begin
  Result := AFinding.Problem.Message.ToLower.Contains(ANeedle) or AFinding.Problem.Code.ToLower.Contains(ANeedle) or
    ExtractFileName(AFinding.FileName).ToLower.Contains(ANeedle);
end;

function TDpccFindingFilter.MatchesExceptKind(const AFinding: TDpccFinding): Boolean;
begin
  Result := Compiler or (AFinding.Category <> TDpccFindingCategory.Compiler);
  Result := Result and (not OneCategory or (AFinding.Category = Category));
  if Scope = TDpccFindingScope.CurrentFile then
  begin
    Result := Result and SameText(AFinding.FileName, CurrentFile);
  end
  else
  begin
    Result := Result and ((Files = nil) or InFiles(Files, AFinding.FileName));
  end;
  Result := Result and ((Text = '') or ContainsNeedle(AFinding, Text.ToLower));
  // Quelle (#1819): „dpcc und IDE“ lässt alle durch.
  if Origin = TDpccFindingOrigin.DpccOnly then
  begin
    Result := Result and (TDpccIdeErrors.OriginOf(AFinding.Problem) = TDpccProblemOrigin.Dpcc);
  end
  else if Origin = TDpccFindingOrigin.IdeOnly then
  begin
    Result := Result and (TDpccIdeErrors.OriginOf(AFinding.Problem) = TDpccProblemOrigin.Ide);
  end;
end;

function TDpccFindingFilter.Matches(const AFinding: TDpccFinding): Boolean;
begin
  Result := (AFinding.Kind in Kinds) and MatchesExceptKind(AFinding);
end;

{ TDpccFindings }

class function TDpccFindings.KindOf(ASeverity: TDpccProblemSeverity): TDpccFindingKind;
begin
  case ASeverity of
    TDpccProblemSeverity.Error:
      Result := TDpccFindingKind.Error;
    TDpccProblemSeverity.Warning:
      Result := TDpccFindingKind.Warning;
  else
    Result := TDpccFindingKind.Info;
  end;
end;

class function TDpccFindings.CategoryOf(const AProblem: TDpccProblem): TDpccFindingCategory;
var
  mCategory: TDpccFindingCategory;
begin
  if AProblem.IsCompiler then
  begin
    Exit(TDpccFindingCategory.Compiler);
  end;
  for mCategory := Low(TDpccFindingCategory) to Pred(TDpccFindingCategory.Compiler) do
  begin
    if SameText(AProblem.Category, cCategoryNames[mCategory]) then
    begin
      Exit(mCategory);
    end;
  end;
  Result := TDpccFindingCategory.Other;
end;

class function TDpccFindings.IsFinding(const AProblem: TDpccProblem): Boolean;
begin
  Result := not AProblem.Unnecessary and not AProblem.IsUses and
    not SameText(AProblem.Source, TDpccProblemStore.cTestSource);
end;

class function TDpccFindings.FromProblems(const AFileName: string; const AProblems: TArray<TDpccProblem>;
  const ALines: TArray<string>): TArray<TDpccFinding>;
var
  mProblem: TDpccProblem;
  mFinding: TDpccFinding;
  mSeen: TDictionary<string, Integer>;
  mBase: string;
  mNumber, mCount: Integer;
begin
  SetLength(Result, Length(AProblems));
  mCount := 0;
  mSeen := TDictionary<string, Integer>.Create;
  try
    for mProblem in AProblems do
    begin
      if not IsFinding(mProblem) then
      begin
        Continue;
      end;
      mFinding := Default(TDpccFinding);
      mFinding.FileName := AFileName;
      mFinding.Problem := mProblem;
      mFinding.Kind := KindOf(mProblem.Severity);
      mFinding.Category := CategoryOf(mProblem);
      if (mProblem.StartLine >= 0) and (mProblem.StartLine < Length(ALines)) then
      begin
        mFinding.LineText := ALines[mProblem.StartLine].Trim;
      end;
      mBase := AnsiLowerCase(AFileName) + '|' + mProblem.Source + '|' + mProblem.Code + '|' + mProblem.Message;
      if not mSeen.TryGetValue(mBase, mNumber) then
      begin
        mNumber := 0;
      end;
      Inc(mNumber);
      mSeen.AddOrSetValue(mBase, mNumber);
      mFinding.Key := mBase + '|' + IntToStr(mNumber);
      Result[mCount] := mFinding;
      Inc(mCount);
    end;
  finally
    mSeen.Free;
  end;
  SetLength(Result, mCount);
end;

type
  /// <summary>Zeilen einer Datei von der Platte, höchstens einmal gelesen (Hänger mit vielen Befunden).</summary>
  TDiskLines = record
    FileName: string;
    ReadLines: TFunc<string, TArray<string>>;
    Lines: TArray<string>;
    Read: Boolean;
    function Line(AIndex: Integer): string;
  end;

function TDiskLines.Line(AIndex: Integer): string;
begin
  Result := '';
  if not Assigned(ReadLines) then
  begin
    Exit;
  end;
  if not Read then
  begin
    Lines := ReadLines(FileName);
    Read := True;
  end;
  if AIndex < Length(Lines) then
  begin
    Result := Lines[AIndex];
  end;
end;

function LastStartLine(const AProblems: TArray<TDpccProblem>): Integer;
var
  mProblem: TDpccProblem;
begin
  Result := -1;
  for mProblem in AProblems do
  begin
    Result := Max(Result, mProblem.StartLine);
  end;
end;

class function TDpccFindings.FromStoreFile(AStore: TDpccProblemStore; const AFileName: string;
  const AReadLines: TFunc<string, TArray<string>>): TArray<TDpccFinding>;
var
  mText: string;
  mProblems: TArray<TDpccProblem>;
  mLines: TArray<string>;
  mProblem: TDpccProblem;
  mDisk: TDiskLines;
begin
  mProblems := AStore.WithIde(AFileName);
  Result := nil;
  if mProblems = nil then
  begin
    Exit;
  end;
  SetLength(mLines, LastStartLine(mProblems) + 1);
  // Die Platte höchstens einmal je Datei, nicht je Zeile.
  mDisk := Default(TDiskLines);
  mDisk.FileName := AFileName;
  mDisk.ReadLines := AReadLines;
  for mProblem in mProblems do
  begin
    if (mProblem.StartLine < 0) or (mLines[mProblem.StartLine] <> '') then
    begin
      Continue;
    end;
    if AStore.LineText(AFileName, mProblem.StartLine, mText) then
    begin
      mLines[mProblem.StartLine] := mText;
    end
    else
    begin
      mLines[mProblem.StartLine] := mDisk.Line(mProblem.StartLine);
    end;
  end;
  Result := FromProblems(AFileName, mProblems, mLines);
end;

class function TDpccFindings.Concat(const AParts: TArray<TArray<TDpccFinding>>): TArray<TDpccFinding>;
var
  mPart: TArray<TDpccFinding>;
  mCount, mIndex: Integer;
begin
  mCount := 0;
  for mPart in AParts do
  begin
    Inc(mCount, Length(mPart));
  end;
  SetLength(Result, mCount);
  mCount := 0;
  for mPart in AParts do
  begin
    for mIndex := 0 to High(mPart) do
    begin
      Result[mCount] := mPart[mIndex];
      Inc(mCount);
    end;
  end;
end;

class function TDpccFindings.FromStore(AStore: TDpccProblemStore; const AFiles: TArray<string>;
  const AReadLines: TFunc<string, TArray<string>>): TArray<TDpccFinding>;
var
  mFiles: TArray<string>;
  mParts: TArray<TArray<TDpccFinding>>;
  mIndex: Integer;
begin
  mFiles := AFiles;
  if mFiles = nil then
  begin
    mFiles := AStore.Files;
  end;
  SetLength(mParts, Length(mFiles));
  for mIndex := 0 to High(mFiles) do
  begin
    mParts[mIndex] := FromStoreFile(AStore, mFiles[mIndex], AReadLines);
  end;
  Result := Concat(mParts);
end;

class function TDpccFindings.Shorten(const AText: string; AMax: Integer): string;
begin
  Result := AText.Trim;
  if (AMax > 1) and (Length(Result) > AMax) then
  begin
    Result := Copy(Result, 1, AMax - 1).TrimRight + '…';
  end;
end;

class function TDpccFindings.CheckedCount(AStore: TDpccProblemStore; const AProjectFiles: TArray<string>): Integer;
var
  mFileName: string;
begin
  Result := 0;
  for mFileName in AProjectFiles do
  begin
    if AStore.Contains(mFileName) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TDpccFindings.IsMandatory(AColumn: TDpccFindingColumn): Boolean;
begin
  Result := not (AColumn in [TDpccFindingColumn.Message, TDpccFindingColumn.Rule, TDpccFindingColumn.Compiler,
    TDpccFindingColumn.Source]);
end;

/// <summary>Teil einer Spaltenliste („-rule:120“): Name, Breite (0 ohne) und ob ausgeblendet.</summary>
procedure SplitColumnPart(const APart: string; out AName: string; out AWidth: Integer; out AHidden: Boolean);
var
  mColon: Integer;
begin
  AName := APart.Trim;
  AHidden := AName.StartsWith('-');
  if AHidden then
  begin
    AName := AName.Substring(1).Trim;
  end;
  AWidth := 0;
  mColon := AName.IndexOf(':');
  if mColon >= 0 then
  begin
    AWidth := Max(0, StrToIntDef(AName.Substring(mColon + 1).Trim, 0));
    AName := AName.Substring(0, mColon).Trim;
  end;
end;

/// <summary>Spalte zum Namen; False bei unbekanntem Namen.</summary>
function ColumnByName(const AName: string; out AColumn: TDpccFindingColumn): Boolean;
var
  mCandidate: TDpccFindingColumn;
begin
  AColumn := TDpccFindingColumn.Icon;
  for mCandidate := Low(TDpccFindingColumn) to High(TDpccFindingColumn) do
  begin
    if SameText(AName, TDpccFindings.cColumnNames[mCandidate]) then
    begin
      AColumn := mCandidate;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDpccFindings.ParseColumns(const AText: string): TArray<TDpccFindingColumnState>;
var
  mPart, mName: string;
  mColumn: TDpccFindingColumn;
  mHidden: Boolean;
  mWidth: Integer;
  mTaken: set of TDpccFindingColumn;
begin
  Result := nil;
  mTaken := [];
  for mPart in AText.Split([',']) do
  begin
    SplitColumnPart(mPart, mName, mWidth, mHidden);
    if ColumnByName(mName, mColumn) and not (mColumn in mTaken) then
    begin
      Include(mTaken, mColumn);
      Result := Result + [TDpccFindingColumnState.Create(mColumn, mWidth, not mHidden or IsMandatory(mColumn))];
    end;
  end;
  for mColumn := Low(TDpccFindingColumn) to High(TDpccFindingColumn) do
  begin
    if not (mColumn in mTaken) then
    begin
      Result := Result + [TDpccFindingColumnState.Create(mColumn, 0, True)];
    end;
  end;
end;

class function TDpccFindings.FormatColumns(const AColumns: TArray<TDpccFindingColumnState>): string;
var
  mState: TDpccFindingColumnState;
  mPart: string;
begin
  Result := '';
  for mState in AColumns do
  begin
    mPart := cColumnNames[mState.Column];
    if not mState.Visible and not IsMandatory(mState.Column) then
    begin
      mPart := '-' + mPart;
    end;
    if mState.Width > 0 then
    begin
      mPart := mPart + ':' + IntToStr(mState.Width);
    end;
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mPart;
  end;
end;

class function TDpccFindings.TryParseScope(const AText: string; out AScope: TDpccFindingScope): Boolean;
var
  mScope: TDpccFindingScope;
begin
  for mScope := Low(TDpccFindingScope) to High(TDpccFindingScope) do
  begin
    if SameText(AText, cScopeNames[mScope]) then
    begin
      AScope := mScope;
      Exit(True);
    end;
  end;
  AScope := TDpccFindingScope.Group;
  Result := False;
end;

class function TDpccFindings.TryParseGrouping(const AText: string; out AGrouping: TDpccFindingGrouping): Boolean;
var
  mGrouping: TDpccFindingGrouping;
begin
  for mGrouping := Low(TDpccFindingGrouping) to High(TDpccFindingGrouping) do
  begin
    if SameText(AText, cGroupingNames[mGrouping]) then
    begin
      AGrouping := mGrouping;
      Exit(True);
    end;
  end;
  AGrouping := TDpccFindingGrouping.ByFile;
  Result := False;
end;

class function TDpccFindings.UnitKey(const AFileName: string): string;
var
  mExtension: string;
begin
  Result := AnsiLowerCase(AFileName);
  mExtension := ExtractFileExt(Result);
  if (mExtension = '.dfm') or (mExtension = '.fmx') then
  begin
    Result := ChangeFileExt(Result, '.pas');
  end;
end;

class function TDpccFindings.TryParseClosedUnits(const AText: string; out AValue: TDpccClosedUnits): Boolean;
var
  mValue: TDpccClosedUnits;
begin
  for mValue := Low(TDpccClosedUnits) to High(TDpccClosedUnits) do
  begin
    if SameText(AText, cClosedUnitsNames[mValue]) then
    begin
      AValue := mValue;
      Exit(True);
    end;
  end;
  AValue := TDpccClosedUnits.Dimmed;
  Result := False;
end;

class function TDpccFindings.AsText(const AFindings: TArray<TDpccFinding>): string;
const
  cKindWords: array[TDpccFindingKind] of string = ('error', 'warning', 'info');
var
  mItem: TDpccFinding;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mItem in AFindings do
    begin
      mBuilder.Append(mItem.Location).Append(': ').Append(cKindWords[mItem.Kind]);
      if mItem.Rule <> '' then
      begin
        mBuilder.Append(' [').Append(mItem.Rule).Append(']');
      end;
      mBuilder.Append(' ').Append(mItem.Problem.Message).Append(#13#10);
      if mItem.LineText <> '' then
      begin
        mBuilder.Append('    ').Append(mItem.LineText).Append(#13#10);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

{ TDpccFindingsSource }

constructor TDpccFindingsSource.Create;
begin
  inherited Create;
  FFilter := TDpccFindingFilter.Create;
  FKnown := TDictionary<string, Boolean>.Create;
  FNew := TDictionary<string, Boolean>.Create;
  FOpenKeys := TDictionary<string, Boolean>.Create;
  // Aus, bis die IDE-Schicht die Einstellung setzt: so verhält sich das Modell ohne Stufen genau wie #909.
  FOpenFirst := False;
  FClosedUnits := TDpccClosedUnits.Dimmed;
  FShowCleanActive := True;
end;

destructor TDpccFindingsSource.Destroy;
begin
  FOpenKeys.Free;
  FNew.Free;
  FKnown.Free;
  inherited Destroy;
end;

procedure TDpccFindingsSource.SetFindings(const AFindings: TArray<TDpccFinding>);
var
  mFinding: TDpccFinding;
begin
  FFindings := AFindings;
  FNew.Clear;
  if FFilled then
  begin
    for mFinding in AFindings do
    begin
      if not FKnown.ContainsKey(mFinding.Key) then
      begin
        FNew.AddOrSetValue(mFinding.Key, True);
      end;
    end;
  end;
  FKnown.Clear;
  for mFinding in AFindings do
  begin
    FKnown.AddOrSetValue(mFinding.Key, True);
  end;
  FFilled := True;
  AssignTiers;
  Rebuild;
end;

procedure TDpccFindingsSource.SetOpenFiles(const AActive: string; const AOpen: TArray<string>;
  AActiveChecked: Boolean);
var
  mFileName: string;
begin
  FActiveFile := AActive;
  FActiveKey := '';
  if AActive <> '' then
  begin
    FActiveKey := TDpccFindings.UnitKey(AActive);
  end;
  // Das Formular steht für seine Unit: Angezeigt wird die .pas.
  if FActiveKey <> AnsiLowerCase(AActive) then
  begin
    FActiveFile := ChangeFileExt(AActive, '.pas');
  end;
  FActiveChecked := AActiveChecked;
  FOpenKeys.Clear;
  for mFileName in AOpen do
  begin
    if mFileName <> '' then
    begin
      FOpenKeys.AddOrSetValue(TDpccFindings.UnitKey(mFileName), True);
    end;
  end;
  AssignTiers;
  Rebuild;
end;

function TDpccFindingsSource.TierOf(const AFileName: string): TDpccFindingTier;
var
  mKey: string;
begin
  mKey := TDpccFindings.UnitKey(AFileName);
  if (FActiveKey <> '') and (mKey = FActiveKey) then
  begin
    Result := TDpccFindingTier.Active;
  end
  else if FOpenKeys.ContainsKey(mKey) then
  begin
    Result := TDpccFindingTier.Open;
  end
  else
  begin
    Result := TDpccFindingTier.Closed;
  end;
end;

procedure TDpccFindingsSource.AssignTiers;
var
  mIndex: Integer;
  mLast: string;
  mTier: TDpccFindingTier;
begin
  // Befunde einer Datei stehen hintereinander: die Stufe je Datei nur einmal bestimmen.
  mLast := '';
  mTier := TDpccFindingTier.Closed;
  for mIndex := 0 to High(FFindings) do
  begin
    if (mIndex = 0) or (FFindings[mIndex].FileName <> mLast) then
    begin
      mLast := FFindings[mIndex].FileName;
      mTier := TierOf(mLast);
    end;
    FFindings[mIndex].Tier := mTier;
  end;
end;

function TDpccFindingsSource.TiersActive: Boolean;
begin
  Result := FOpenFirst and (FFilter.Scope <> TDpccFindingScope.CurrentFile);
end;

function TDpccFindingsSource.HiddenByTier(const AFinding: TDpccFinding): Boolean;
begin
  Result := TiersActive and (FClosedUnits = TDpccClosedUnits.Hidden) and
    (AFinding.Tier = TDpccFindingTier.Closed);
end;

procedure TDpccFindingsSource.SetOpenFirst(AValue: Boolean);
begin
  FOpenFirst := AValue;
  Rebuild;
end;

procedure TDpccFindingsSource.SetClosedUnits(AValue: TDpccClosedUnits);
begin
  FClosedUnits := AValue;
  Rebuild;
end;

procedure TDpccFindingsSource.SetShowCleanActive(AValue: Boolean);
begin
  FShowCleanActive := AValue;
  Rebuild;
end;

procedure TDpccFindingsSource.ClearNew;
begin
  if FNew.Count = 0 then
  begin
    Exit;
  end;
  FNew.Clear;
  Rebuild;
end;

procedure TDpccFindingsSource.SetFilter(const AValue: TDpccFindingFilter);
begin
  FFilter := AValue;
  Rebuild;
end;

function TDpccFindingsSource.IsActiveInScope: Boolean;
var
  mName: string;
begin
  if FActiveKey = '' then
  begin
    Exit(False);
  end;
  if (FFilter.Scope = TDpccFindingScope.CurrentFile) or (FFilter.Files = nil) then
  begin
    Exit(True);
  end;
  for mName in FFilter.Files do
  begin
    if TDpccFindings.UnitKey(mName) = FActiveKey then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDpccFindingsSource.Finding(AIndex: Integer): TDpccFinding;
begin
  Result := FFindings[AIndex];
end;

{ TDpccFindingsSorted }

constructor TDpccFindingsSorted.Create;
begin
  inherited Create;
  FGrouping := TDpccFindingGrouping.ByFile;
end;

procedure TDpccFindingsSorted.SetGrouping(AValue: TDpccFindingGrouping);
begin
  FGrouping := AValue;
  Rebuild;
end;

procedure TDpccFindingsSorted.SortBy(AColumn: TDpccFindingColumn);
begin
  if FSortCustom and (FSortColumn = AColumn) then
  begin
    FSortDescending := not FSortDescending;
  end
  else
  begin
    FSortCustom := True;
    FSortColumn := AColumn;
    FSortDescending := False;
  end;
  Rebuild;
end;

procedure TDpccFindingsSorted.ResetSort;
begin
  FSortCustom := False;
  FSortDescending := False;
  Rebuild;
end;

function TDpccFindingsSorted.GroupKeyOf(const AFinding: TDpccFinding): string;
begin
  case FGrouping of
    TDpccFindingGrouping.ByFile:
      Result := 'file:' + AnsiLowerCase(AFinding.FileName);
    TDpccFindingGrouping.ByRule:
      Result := 'rule:' + AnsiLowerCase(AFinding.Problem.Code);
    TDpccFindingGrouping.ByCategory:
      Result := 'category:' + IntToStr(Ord(AFinding.Category));
  else
    Result := '';
  end;
end;

function CompareDefault(const A, B: TDpccFinding): Integer;
begin
  Result := Ord(A.Kind) - Ord(B.Kind);
  if Result = 0 then
  begin
    Result := CompareText(A.FileName, B.FileName);
  end;
  if Result = 0 then
  begin
    Result := A.Problem.StartLine - B.Problem.StartLine;
  end;
  if Result = 0 then
  begin
    Result := A.Problem.StartCharacter - B.Problem.StartCharacter;
  end;
  if Result = 0 then
  begin
    Result := CompareStr(A.Key, B.Key);
  end;
end;

function CompareLocation(const A, B: TDpccFinding): Integer;
begin
  Result := CompareText(ExtractFileName(A.FileName), ExtractFileName(B.FileName));
  if Result = 0 then
  begin
    Result := A.Problem.StartLine - B.Problem.StartLine;
  end;
  if Result = 0 then
  begin
    Result := A.Problem.StartCharacter - B.Problem.StartCharacter;
  end;
end;

/// <summary>Vergleich nach der Spalte AColumn (aufsteigend).</summary>
function CompareColumn(AColumn: TDpccFindingColumn; const A, B: TDpccFinding): Integer;
begin
  case AColumn of
    TDpccFindingColumn.Category:
      Result := Ord(A.Category) - Ord(B.Category);
    TDpccFindingColumn.Message:
      Result := CompareText(A.Problem.Message, B.Problem.Message);
    TDpccFindingColumn.Line:
      Result := CompareText(A.LineText, B.LineText);
    TDpccFindingColumn.Location:
      Result := CompareLocation(A, B);
    TDpccFindingColumn.Rule:
      Result := CompareText(A.Problem.Code, B.Problem.Code);
    TDpccFindingColumn.Compiler:
      Result := CompareText(A.CompilerText, B.CompilerText);
    TDpccFindingColumn.Source:
      Result := CompareText(A.SourceText, B.SourceText);
  else
    // Symbol und Art.
    Result := Ord(A.Kind) - Ord(B.Kind);
  end;
end;

function TDpccFindingsSorted.Compare(const A, B: TDpccFinding): Integer;
begin
  // Offene Units zuerst (#1108): Die Stufe kommt vor jeder Spalte; ein Klick auf den Spaltenkopf sortiert nur
  // innerhalb der Stufe.
  Result := 0;
  if TiersActive then
  begin
    Result := Ord(A.Tier) - Ord(B.Tier);
  end;
  if (Result = 0) and FSortCustom then
  begin
    Result := CompareColumn(FSortColumn, A, B);
    if FSortDescending then
    begin
      Result := -Result;
    end;
  end;
  if Result = 0 then
  begin
    Result := CompareDefault(A, B);
  end;
end;

function TDpccFindingsSorted.TiersByFile: Boolean;
begin
  Result := TiersActive and (FGrouping = TDpccFindingGrouping.ByFile);
end;

function TDpccFindingsSorted.CompareGroups(const AFirstA, AFirstB: TDpccFinding;
  const AKeyA, AKeyB: string): Integer;
begin
  // Gruppen nach Datei, Regel bzw. Kategorie; innerhalb der Gruppe die gewählte Sortierung. Nach Datei mit
  // Offene-zuerst (#1108) kommt die Stufe vor dem Namen: aktive Unit, geöffnete und nicht geöffnete je
  // alphabetisch, damit beim Editorwechsel nur die angepinnte Gruppe springt.
  Result := 0;
  if TiersByFile then
  begin
    Result := Ord(AFirstA.Tier) - Ord(AFirstB.Tier);
  end;
  if Result = 0 then
  begin
    case FGrouping of
      TDpccFindingGrouping.ByFile:
        Result := CompareText(ExtractFileName(AFirstA.FileName), ExtractFileName(AFirstB.FileName));
      TDpccFindingGrouping.ByRule:
        Result := CompareText(AFirstA.Problem.Code, AFirstB.Problem.Code);
    else
      Result := Ord(AFirstA.Category) - Ord(AFirstB.Category);
    end;
  end;
  if Result = 0 then
  begin
    Result := CompareText(AKeyA, AKeyB);
  end;
end;

function TDpccFindingsSorted.SortedMatches: TArray<Integer>;
var
  mIndex: Integer;
  mOrder: TList<Integer>;
begin
  mOrder := TList<Integer>.Create;
  try
    for mIndex := 0 to High(FFindings) do
    begin
      if FFilter.Matches(FFindings[mIndex]) and not HiddenByTier(FFindings[mIndex]) then
      begin
        mOrder.Add(mIndex);
      end;
    end;
    mOrder.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := Compare(FFindings[A], FFindings[B]);
      end));
    Result := mOrder.ToArray;
  finally
    mOrder.Free;
  end;
end;

/// <summary>AOrder je Stufe aufgeteilt, Reihenfolge bleibt.</summary>
function SplitByTier(const AFindings: TArray<TDpccFinding>; const AOrder: TArray<Integer>):
  TDpccFindingTierMembers;
var
  mCount: array[TDpccFindingTier] of Integer;
  mTier: TDpccFindingTier;
  mIndex: Integer;
begin
  for mTier := Low(TDpccFindingTier) to High(TDpccFindingTier) do
  begin
    mCount[mTier] := 0;
  end;
  for mIndex in AOrder do
  begin
    Inc(mCount[AFindings[mIndex].Tier]);
  end;
  for mTier := Low(TDpccFindingTier) to High(TDpccFindingTier) do
  begin
    SetLength(Result[mTier], mCount[mTier]);
    mCount[mTier] := 0;
  end;
  for mIndex in AOrder do
  begin
    mTier := AFindings[mIndex].Tier;
    Result[mTier][mCount[mTier]] := mIndex;
    Inc(mCount[mTier]);
  end;
end;

{ TDpccFindingsView }

constructor TDpccFindingsView.Create;
begin
  inherited Create;
  FCollapsed := TDictionary<string, Boolean>.Create;
end;

destructor TDpccFindingsView.Destroy;
begin
  FCollapsed.Free;
  inherited Destroy;
end;

procedure TDpccFindingsView.BeginUpdate;
begin
  Inc(FUpdateCount);
end;

procedure TDpccFindingsView.EndUpdate;
begin
  if FUpdateCount = 0 then
  begin
    Exit;
  end;
  Dec(FUpdateCount);
  if (FUpdateCount = 0) and FRebuildPending then
  begin
    Rebuild;
  end;
end;

function TDpccFindingsView.FindingRow(AIndex: Integer; const AGroupKey: string): TDpccFindingRow;
begin
  Result := Default(TDpccFindingRow);
  Result.GroupKey := AGroupKey;
  Result.Finding := AIndex;
  Result.IsNew := FNew.ContainsKey(FFindings[AIndex].Key);
  Result.Tier := FFindings[AIndex].Tier;
  if TiersActive then
  begin
    Result.Pinned := Result.Tier = TDpccFindingTier.Active;
    Result.Dimmed := (Result.Tier = TDpccFindingTier.Closed) and (FClosedUnits = TDpccClosedUnits.Dimmed);
  end;
end;

function TDpccFindingsView.SectionRow(ATier: TDpccFindingTier; const AMembers: TArray<Integer>): TDpccFindingRow;
var
  mIndex: Integer;
  mUnits: TDictionary<string, Boolean>;
begin
  Result := Default(TDpccFindingRow);
  Result.IsSection := True;
  Result.Finding := -1;
  Result.Tier := ATier;
  Result.Pinned := ATier = TDpccFindingTier.Active;
  Result.Dimmed := (ATier = TDpccFindingTier.Closed) and (FClosedUnits = TDpccClosedUnits.Dimmed);
  Result.Count := Length(AMembers);
  mUnits := TDictionary<string, Boolean>.Create;
  try
    for mIndex in AMembers do
    begin
      mUnits.AddOrSetValue(TDpccFindings.UnitKey(FFindings[mIndex].FileName), True);
    end;
    Result.Units := mUnits.Count;
  finally
    mUnits.Free;
  end;
  if ATier = TDpccFindingTier.Active then
  begin
    Result.Caption := ExtractFileName(FActiveFile);
  end;
end;

function TDpccFindingsView.CleanActiveRow(out ARow: TDpccFindingRow): Boolean;
begin
  ARow := Default(TDpccFindingRow);
  Result := TiersActive and FShowCleanActive and IsActiveInScope;
  if not Result then
  begin
    Exit;
  end;
  ARow := SectionRow(TDpccFindingTier.Active, nil);
  ARow.IsCleanActive := True;
  ARow.Checking := not FActiveChecked;
end;

function TDpccFindingsView.GroupRow(const AKey: string; const AFirst: TDpccFinding;
  ACount: Integer): TDpccFindingRow;
var
  mCollapsed: Boolean;
begin
  Result := Default(TDpccFindingRow);
  Result.IsGroup := True;
  Result.GroupKey := AKey;
  Result.Finding := -1;
  Result.Count := ACount;
  Result.Category := AFirst.Category;
  if TiersByFile then
  begin
    Result.Tier := AFirst.Tier;
    Result.Pinned := AFirst.Tier = TDpccFindingTier.Active;
    Result.Dimmed := (AFirst.Tier = TDpccFindingTier.Closed) and (FClosedUnits = TDpccClosedUnits.Dimmed);
  end;
  case FGrouping of
    TDpccFindingGrouping.ByFile:
      Result.Caption := ExtractFileName(AFirst.FileName);
    TDpccFindingGrouping.ByRule:
      Result.Caption := AFirst.Problem.Code;
    TDpccFindingGrouping.ByCategory:
      Result.Caption := cCategoryNames[AFirst.Category];
    TDpccFindingGrouping.None: ;
  end;
  if not FCollapsed.TryGetValue(AKey, mCollapsed) then
  begin
    mCollapsed := False;
  end;
  Result.Expanded := not mCollapsed;
end;

procedure TDpccFindingsView.Rebuild;
var
  mOrder: TArray<Integer>;
  mOfTier: TDpccFindingTierMembers;
  mRows: TList<TDpccFindingRow>;
begin
  FCountsValid := False;
  if FUpdateCount > 0 then
  begin
    FRebuildPending := True;
    Exit;
  end;
  FRebuildPending := False;
  mOrder := SortedMatches;
  mOfTier := SplitByTier(FFindings, mOrder);
  // Zeilen über Listen statt Array + [x]: Mit zehntausenden Befunden wäre jeder Neuaufbau quadratisch.
  mRows := TList<TDpccFindingRow>.Create;
  try
    if FGrouping = TDpccFindingGrouping.None then
    begin
      RebuildFlat(mOrder, mOfTier, mRows);
    end
    else
    begin
      RebuildGrouped(mOrder, mOfTier, mRows);
    end;
    FRows := mRows.ToArray;
  finally
    mRows.Free;
  end;
  // Zugeklappte Gruppen, die gerade keine Befunde haben, bleiben gemerkt: Kommen ihre Befunde wieder, bleiben sie
  // zugeklappt.
end;

procedure TDpccFindingsView.RebuildFlat(const AOrder: TArray<Integer>; const AOfTier: TDpccFindingTierMembers;
  ARows: TList<TDpccFindingRow>);
var
  mIndex: Integer;
  mTier: TDpccFindingTier;
  mStarted: set of TDpccFindingTier;
  mRow: TDpccFindingRow;
  mTiers: Boolean;
begin
  FVisible := AOrder;
  mTiers := TiersActive;
  mStarted := [];
  if mTiers and (Length(AOfTier[TDpccFindingTier.Active]) = 0) and CleanActiveRow(mRow) then
  begin
    ARows.Add(mRow);
  end;
  for mIndex in FVisible do
  begin
    mTier := FFindings[mIndex].Tier;
    if mTiers and not (mTier in mStarted) then
    begin
      Include(mStarted, mTier);
      ARows.Add(SectionRow(mTier, AOfTier[mTier]));
    end;
    ARows.Add(FindingRow(mIndex, ''));
  end;
end;

/// <summary>Gruppenschlüssel in der Reihenfolge des ersten Auftretens und ihre Befunde.</summary>
procedure CollectGroups(const AKeys: TArray<string>; const AOrder: TArray<Integer>; AGroups: TList<string>;
  AMembers: TObjectDictionary<string, TList<Integer>>);
var
  mIndex: Integer;
  mList: TList<Integer>;
begin
  for mIndex := 0 to High(AOrder) do
  begin
    if not AMembers.TryGetValue(AKeys[mIndex], mList) then
    begin
      AGroups.Add(AKeys[mIndex]);
      mList := TList<Integer>.Create;
      AMembers.Add(AKeys[mIndex], mList);
    end;
    mList.Add(AOrder[mIndex]);
  end;
end;

procedure TDpccFindingsView.RebuildGrouped(const AOrder: TArray<Integer>; const AOfTier: TDpccFindingTierMembers;
  ARows: TList<TDpccFindingRow>);
var
  mKeys: TArray<string>;
  mIndex, mMember: Integer;
  mGroups: TList<string>;
  mMembers: TObjectDictionary<string, TList<Integer>>;
  mKey: string;
  mRow: TDpccFindingRow;
  mFirst: TDpccFinding;
  mStarted: set of TDpccFindingTier;
  mVisible: TList<Integer>;
begin
  SetLength(mKeys, Length(AOrder));
  for mIndex := 0 to High(AOrder) do
  begin
    mKeys[mIndex] := GroupKeyOf(FFindings[AOrder[mIndex]]);
  end;
  mStarted := [];
  mVisible := TList<Integer>.Create;
  mGroups := TList<string>.Create;
  mMembers := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  try
    CollectGroups(mKeys, AOrder, mGroups, mMembers);
    mGroups.Sort(TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result := CompareGroups(FFindings[mMembers[A][0]], FFindings[mMembers[B][0]], A, B);
      end));
    if TiersByFile and (Length(AOfTier[TDpccFindingTier.Active]) = 0) and CleanActiveRow(mRow) then
    begin
      ARows.Add(mRow);
    end;
    for mKey in mGroups do
    begin
      mFirst := FFindings[mMembers[mKey][0]];
      // Trennzeilen „Geöffnet“ und „Nicht geöffnet“ nur nach Datei.
      if TiersByFile and (mFirst.Tier <> TDpccFindingTier.Active) and not (mFirst.Tier in mStarted) then
      begin
        Include(mStarted, mFirst.Tier);
        ARows.Add(SectionRow(mFirst.Tier, AOfTier[mFirst.Tier]));
      end;
      mRow := GroupRow(mKey, mFirst, mMembers[mKey].Count);
      ARows.Add(mRow);
      for mMember in mMembers[mKey] do
      begin
        mVisible.Add(mMember);
        if mRow.Expanded then
        begin
          ARows.Add(FindingRow(mMember, mKey));
        end;
      end;
    end;
    FVisible := mVisible.ToArray;
  finally
    mMembers.Free;
    mGroups.Free;
    mVisible.Free;
  end;
end;

function TDpccFindingsView.Rows: TArray<TDpccFindingRow>;
begin
  Result := FRows;
end;

function TDpccFindingsView.Visible: TArray<TDpccFinding>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(FVisible));
  for mIndex := 0 to High(FVisible) do
  begin
    Result[mIndex] := FFindings[FVisible[mIndex]];
  end;
end;

type
  /// <summary>Units und Dateien, die Counts zählt.</summary>
  TCountUnits = record
    Files: TDictionary<string, Boolean>;
    Open: TDictionary<string, Boolean>;
    Closed: TDictionary<string, Boolean>;
    Hidden: TDictionary<string, Boolean>;
    procedure Init;
    procedure Done;
  end;

procedure TCountUnits.Init;
begin
  Files := TDictionary<string, Boolean>.Create;
  Open := TDictionary<string, Boolean>.Create;
  Closed := TDictionary<string, Boolean>.Create;
  Hidden := TDictionary<string, Boolean>.Create;
end;

procedure TCountUnits.Done;
begin
  Hidden.Free;
  Closed.Free;
  Open.Free;
  Files.Free;
end;

procedure CountKind(AKind: TDpccFindingKind; var ACounts: TDpccFindingCounts);
begin
  case AKind of
    TDpccFindingKind.Error:
      Inc(ACounts.Errors);
    TDpccFindingKind.Warning:
      Inc(ACounts.Warnings);
  else
    Inc(ACounts.Infos);
  end;
end;

/// <summary>Einen Befund unter dem Filter ohne die Arten zählen; AInKinds = seine Art ist im Filter.</summary>
procedure CountFinding(const AFinding: TDpccFinding; AHidden, ATiers, AInKinds: Boolean;
  var ACounts: TDpccFindingCounts; const AUnits: TCountUnits);
begin
  // Ausgegraut ist reine Darstellung und zählt mit; ausgeblendet zählt nicht (#1108).
  if AHidden then
  begin
    if AInKinds then
    begin
      AUnits.Hidden.AddOrSetValue(TDpccFindings.UnitKey(AFinding.FileName), True);
    end;
    Exit;
  end;
  if ATiers and AInKinds and (AFinding.Tier = TDpccFindingTier.Closed) then
  begin
    AUnits.Closed.AddOrSetValue(TDpccFindings.UnitKey(AFinding.FileName), True);
    Inc(ACounts.ClosedFindings);
  end
  else if ATiers and AInKinds then
  begin
    AUnits.Open.AddOrSetValue(TDpccFindings.UnitKey(AFinding.FileName), True);
    Inc(ACounts.OpenFindings);
  end;
  CountKind(AFinding.Kind, ACounts);
  if AInKinds then
  begin
    AUnits.Files.AddOrSetValue(AnsiLowerCase(AFinding.FileName), True);
  end;
end;

function TDpccFindingsView.Counts: TDpccFindingCounts;
var
  mFinding: TDpccFinding;
  mUnits: TCountUnits;
  mTiers: Boolean;
begin
  if FCountsValid then
  begin
    Exit(FCounts);
  end;
  Result := Default(TDpccFindingCounts);
  mTiers := TiersActive;
  mUnits.Init;
  try
    for mFinding in FFindings do
    begin
      if FFilter.MatchesExceptKind(mFinding) then
      begin
        CountFinding(mFinding, HiddenByTier(mFinding), mTiers, mFinding.Kind in FFilter.Kinds, Result, mUnits);
      end;
    end;
    Result.Files := mUnits.Files.Count;
    Result.OpenUnits := mUnits.Open.Count;
    Result.ClosedUnits := mUnits.Closed.Count;
    Result.HiddenUnits := mUnits.Hidden.Count;
    FCounts := Result;
    FCountsValid := True;
  finally
    mUnits.Done;
  end;
end;

procedure TDpccFindingsView.SetExpanded(const AGroupKey: string; AExpanded: Boolean);
begin
  if AExpanded then
  begin
    FCollapsed.Remove(AGroupKey);
  end
  else
  begin
    FCollapsed.AddOrSetValue(AGroupKey, True);
  end;
  Rebuild;
end;

procedure TDpccFindingsView.Toggle(ARow: Integer);
begin
  if (ARow < 0) or (ARow > High(FRows)) or not FRows[ARow].IsGroup then
  begin
    Exit;
  end;
  SetExpanded(FRows[ARow].GroupKey, not FRows[ARow].Expanded);
end;

procedure TDpccFindingsView.Select(ARow: Integer);
begin
  if (ARow < 0) or (ARow > High(FRows)) then
  begin
    FSelectedKey := '';
  end
  else if FRows[ARow].IsSection then
  begin
    // Trennzeilen sind nicht wählbar: Die Auswahl bleibt, wo sie war.
    Exit;
  end
  else if FRows[ARow].IsGroup then
  begin
    FSelectedKey := 'group:' + FRows[ARow].GroupKey;
  end
  else
  begin
    FSelectedKey := FFindings[FRows[ARow].Finding].Key;
  end;
end;

function TDpccFindingsView.GetSelectedRow: Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if FSelectedKey = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FRows) do
  begin
    if FRows[mIndex].IsSection then
    begin
      Continue;
    end
    else if FRows[mIndex].IsGroup then
    begin
      if FSelectedKey = 'group:' + FRows[mIndex].GroupKey then
      begin
        Exit(mIndex);
      end;
    end
    else if FFindings[FRows[mIndex].Finding].Key = FSelectedKey then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TDpccFindingsView.SelectedFinding(out AFinding: TDpccFinding): Boolean;
var
  mRow: Integer;
begin
  AFinding := Default(TDpccFinding);
  mRow := GetSelectedRow;
  Result := (mRow >= 0) and not FRows[mRow].IsGroup and not FRows[mRow].IsSection;
  if Result then
  begin
    AFinding := FFindings[FRows[mRow].Finding];
  end;
end;

function TDpccFindingsView.SelectAt(const AFileName: string; ALine: Integer): Boolean;
var
  mIndex: Integer;
  mFinding: TDpccFinding;
  mKey: string;
begin
  for mIndex in FVisible do
  begin
    mFinding := FFindings[mIndex];
    if SameText(mFinding.FileName, AFileName) and (ALine >= mFinding.Problem.StartLine) and
      (ALine <= Max(mFinding.Problem.StartLine, mFinding.Problem.EndLine)) then
    begin
      FSelectedKey := mFinding.Key;
      mKey := GroupKeyOf(mFinding);
      if (mKey <> '') and FCollapsed.ContainsKey(mKey) then
      begin
        SetExpanded(mKey, True);
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDpccFindingsView.Step(AForward: Boolean; out AFinding: TDpccFinding): Boolean;
var
  mCurrent, mIndex, mTarget: Integer;
  mKey: string;
begin
  AFinding := Default(TDpccFinding);
  if Length(FVisible) = 0 then
  begin
    Exit(False);
  end;
  mCurrent := -1;
  for mIndex := 0 to High(FVisible) do
  begin
    if FFindings[FVisible[mIndex]].Key = FSelectedKey then
    begin
      mCurrent := mIndex;
    end;
  end;
  if mCurrent < 0 then
  begin
    if AForward then
    begin
      mTarget := 0;
    end
    else
    begin
      mTarget := High(FVisible);
    end;
  end
  else if AForward then
  begin
    mTarget := (mCurrent + 1) mod Length(FVisible);
  end
  else
  begin
    mTarget := (mCurrent - 1 + Length(FVisible)) mod Length(FVisible);
  end;
  AFinding := FFindings[FVisible[mTarget]];
  FSelectedKey := AFinding.Key;
  mKey := GroupKeyOf(AFinding);
  if (mKey <> '') and FCollapsed.ContainsKey(mKey) then
  begin
    SetExpanded(mKey, True);
  end;
  Result := True;
end;

function TDpccFindingsView.GroupMembers(const AGroupKey: string): TArray<Integer>;
var
  mIndex: Integer;
  mList: TList<Integer>;
begin
  mList := TList<Integer>.Create;
  try
    for mIndex in FVisible do
    begin
      if GroupKeyOf(FFindings[mIndex]) = AGroupKey then
      begin
        mList.Add(mIndex);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TDpccFindingsView.FindingsOfRows(const ARows: TArray<Integer>): TArray<TDpccFinding>;
var
  mRow, mIndex: Integer;
  mMembers: TArray<Integer>;
  mDone: TDictionary<Integer, Boolean>;
  mList: TList<TDpccFinding>;
begin
  mDone := TDictionary<Integer, Boolean>.Create;
  mList := TList<TDpccFinding>.Create;
  try
    for mRow in ARows do
    begin
      if (mRow < 0) or (mRow > High(FRows)) or FRows[mRow].IsSection then
      begin
        Continue;
      end;
      if FRows[mRow].IsGroup then
      begin
        mMembers := GroupMembers(FRows[mRow].GroupKey);
      end
      else
      begin
        mMembers := TArray<Integer>.Create(FRows[mRow].Finding);
      end;
      for mIndex in mMembers do
      begin
        if not mDone.ContainsKey(mIndex) then
        begin
          mDone.Add(mIndex, True);
          mList.Add(FFindings[mIndex]);
        end;
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mDone.Free;
  end;
end;

end.
