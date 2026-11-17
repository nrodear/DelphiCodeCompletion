unit dpcc.Common.Index.SymbolIndex;

// Threadsicherer Symbolindex im Speicher. Schlüssel sind Unit-Namen und
// Dateinamen ohne Groß-/Kleinschreibung; Symbolnamen und Vorfahren werden
// beim Hinzufügen einer Unit in Nachschlagetabellen eingetragen.
//
// Nachschlagetabellen (Diagnoselog 15.10.2026): FindSymbols und Descendants
// liefen früher über alle Symbole aller Units. Mit eingelesener Bibliothek
// (über 5000 Units) kostete jeder Aufruf mehrere Zehntel Sekunden; Prüfregeln
// rufen ihn je Methode und Vorfahr auf, eine Datei brauchte so 30 s bis über
// 200 s. Jetzt verweist je Name (und je Vorfahr ohne Unit-Präfix) eine Liste
// auf Platz der Unit und Position des Symbols. Ersetzte oder entfernte Units
// lassen ihre Verweise als tot zurück (Platz ohne Datei); überwiegen die
// toten, werden die Tabellen neu aufgebaut.
//
// Speicherbudget (#185): Zeichenketten kommen in einen Pool. Übersteigt der
// geschätzte Bedarf das Budget, werden zuerst Bibliotheks-Units kompakt
// gehalten (nur interface-Symbole, ohne Verwendungen), dann die Verwendungen
// der Projekt-Units ausgelagert (#492; sie bleiben im Cache auf der Platte),
// zuletzt Projekt-Units kompakt gehalten. Die Verwendungen der Projekt-Units
// gehen erst nach den Bibliotheken: Ohne sie lesen projektweite Regeln
// (unused-public-member) jede Datei der Gruppe, und der Prüflauf staut sich
// (Abbrüche in 2.0-stable). MemoryParts teilt
// die Schätzung für das Fenster „dpcc-Server“ (#1356) in Projekt, Bibliothek
// und Verwendungen; die Anteile laufen beim Hinzufügen und Entfernen mit.
//
// Heißer Pfad: Units liefert einen Schnappschuss, der bis zur nächsten Änderung gilt,
// statt bei jedem Aufruf alle Units zu kopieren; UnavailableUnits nur die Units mit nicht geltenden
// Zweigen. Das Einordnen der Zeichenketten in den Pool läuft außerhalb der Index-Sperre unter einer
// eigenen, damit Leser nicht auf das Einlesen großer Units warten.
//
// Gleichnamige Units (L2): Je Unit-Name stehen alle Dateien in FUnitFiles, nach Rang (IIndexUnitScopes.RankOf,
// ohne: Projekt vor Bibliothek) und bei gleichem Rang in der Reihenfolge, in der der Index die Datei zum ersten Mal
// sah. FindUnit nimmt die erste; welche für eine Datei gilt, entscheidet die Namensauflösung über UnitFiles und
// UnitScopes. Entfernen einer Datei lässt die anderen gleichen Namens stehen (vorher verlor der Name den Eintrag).
//
// Unit-Aliase: FindUnit führt einen Alias (WinTypes → Winapi.Windows) auf seine
// Unit, wenn es keine Unit dieses Namens gibt. Die Vorgaben von Delphi gelten
// immer, AddUnitAliases ergänzt die Aliase der geladenen Projekte.
//
// Speicher (Speicher-Optimierung Phase 2, c4): Die Nachschlagetabellen vergleichen Namen ohne Groß-/Kleinschreibung
// (wie CompareText) und nutzen den Namen des Symbols selbst als Schlüssel statt einer großgeschriebenen Kopie. Je
// Schlüssel steht nur der Anfang und das Ende einer Kette; die Verweise liegen in Blöcken zu cNodeChunk Knoten statt
// in einer eigenen Liste je Name (vorher rund 44 MB für die Bibliothek).
//
// Speicher-Optimierung Phase 3 (bedarfsweises Laden):
// - Jede Unit hat einen Eintrag (TIndexEntry) mit Kopf und Katalog (TCatalogUnit: importierbare Symbole, uses,
//   erste Typen). Die vollen Symbole hält der Index nur für geladene Units. Gepinnt (nie verdrängt) sind alle
//   Units, die AddUnit bringt (Projekt, Suchpfade, uses-Hülle der Projekte) und die, deren Namen eine Projekt-Unit
//   in ihren uses nennt (auch offene Dokumente nach dem Tippen). Bibliotheks-Units aus der Bibliotheksstufe kommen
//   über AddCold nur mit Katalog und Block (IIndexUnitSource) bzw. über AddEvictable verdrängbar in den Index.
// - FindUnit und FindFile laden eine verdrängte Unit aus ihrem Block nach (außerhalb der Sperre; ein zweiter
//   Leser derselben Unit übernimmt das erste Ergebnis). FindSymbols und HasSymbol laden vorher die verdrängten
//   Units, deren Katalog einen Eintrag dieses Namens hat (Symbole oberster Ebene); Mitglieder verdrängter Units
//   finden sie nicht. Descendants sieht nur geladene Units. FindHeader und FindUnitHeader laden nie.
// - Verdrängt wird immer die ganze Unit, sobald die verdrängbaren Units zusammen mehr als cEvictableBudget
//   belegen: zuerst die am seltensten genutzte (Zähler mit Alterung je cAgingLoads Ladevorgänge), bei Gleichstand
//   die am längsten nicht genutzte. Der Katalogeintrag bleibt. Ihre Verweise entfernt der Index gezielt aus den
//   Nachschlagetabellen (die Knoten kommen in eine Freiliste) statt tote zurückzulassen.
// - Laden und Verdrängen ändern Generation nicht: Katalog, Namensindex der Import-Vorschläge (TImportNames) und
//   gemerkte Antworten (TIndexNameFacts) bleiben gültig. Leser halten referenzgezählte Kopien der Symbole; eine
//   Unit zu verdrängen gibt nur die Verweise des Index frei.
//
// Speicher-Optimierung Phase 4 (Korrektheit, Verdrängen ohne Flattern, kürzere Sperren):
// - FindSymbols und HasSymbol finden alle Units eines Namens, auch wenn das Laden der letzten eine eben geladene
//   desselben Namens wieder verdrängt (seit Phase 5 ohne aufgeschobenes Verdrängen, siehe unten).
// - Units aus den uses einer Projekt-Unit und oft genutzte (Nutzungsstatistik) gelten als geschützt (Guarded) und
//   zählen wie gepinnte nicht gegen cEvictableBudget; das Budget gilt nur für die tatsächlich verdrängbaren
//   (FCandidateBytes). Vorher zählten sie mit, wurden aber nie verdrängt: Lagen sie über 32 MB, verdrängte jedes
//   Nachladen alle übrigen. Ändern sich die uses, prüft der nächste Verdrängungslauf den Schutz neu (FGuardDirty).
// - Verdrängen sammelt die Kandidaten einmal, sortiert sie (seltener genutzt, länger nicht genutzt) und verdrängt dann
//   in einem Durchgang; ohne Überschreitung kostet es nichts.
// - Die Verweise einer verdrängbaren Unit merkt sich ihr Platz (Knotennummern). Verdrängen markiert sie tot, räumt
//   kurze Ketten gleich auf und lange beim nächsten Lesen (statt jede Namenskette wie Create oder Count ganz zu
//   durchlaufen); der Platz wird wiederverwendet.
// - Das Namensverzeichnis der kalten Units (FNameHashes) hängt an der Menge der verdrängbaren Einträge
//   (FNameMembership), nicht an Generation: Tippen in einer Projekt-Unit baut es nicht neu. Gebaut wird es außerhalb
//   der Sperre.
// - Lädt ein zweiter Thread dieselbe kalte Unit, wartet er auf das Ergebnis des ersten (TIndexLoadSignal), statt den
//   Block ein zweites Mal zu lesen. Größe und Katalog einer Unit entstehen vor der Sperre und nur einmal.
//
// Speicher-Optimierung Phase 5 (Review der Phase 4):
// - FindSymbols liest unter einer Sperre die Verweise der geladenen Units und merkt sich die kalten Units, deren
//   Katalog den Namen hat; jede Unit ist in diesem Augenblick entweder geladen oder kalt. Danach lädt es die kalten
//   einzeln und übernimmt ihre Symbole dieses Namens sofort; das Verdrängen läuft dabei normal weiter, für alle
//   Threads. Phase 4 schob es für den ganzen Index auf, solange eine Suche lud (FEvictDefer): Bei häufigen Namen
//   (Register) lagen alle ihre Units zugleich im Speicher, und auch andere Threads verdrängten nichts. Die Spitze einer
//   Suche ist jetzt höchstens die Grenze der verdrängbaren Units plus eine Unit plus die gefundenen Symbole.
// - HasSymbol prüft erst die geladenen Units und lädt kalte nur, solange es nichts gefunden hat.
// - Beim Tippen ändert sich der Schutz der Units aus den uses nicht mehr bei jeder neuen Fassung (nur ein neu
//   hinzugekommener oder weggefallener Name macht ihn ungültig, FGuardDirty).
// - Scheitert das Nachladen, weil der Block inzwischen an eine neue Datei gebunden wurde (BindSources), lädt LoadKey
//   aus dem neuen Block, statt die Unit aus dem Index zu nehmen.
//
// L3 (Include-Dateien verdrängter Units): Je Include-Datei (groß) die Dateischlüssel der Units, die sie einbinden
// (FIncludeOwners, IIndexIncludeOwners), gepflegt beim Eintragen und Entfernen jeder Unit aus ihrem Kopf
// (TUnitIndex.Includes); kalte Units bringen ihn aus dem Verzeichnis des Caches mit. Nur verwaltete Verweise auf die
// Schlüssel; ein Eintrag je Include-Datei.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  dpcc.Common.Index.Contract,
  dpcc.Common.Index.Memory;

type
  /// <summary>Nachschlagetabellen des Symbolindex: je Name und je Vorfahr Verweise auf Platz der Unit und Position
  /// des Symbols. Nicht threadsicher; TSymbolIndex nutzt sie unter seiner Sperre.</summary>
  TSymbolRefTables = class
  private type
    /// <summary>Verweis auf ein Symbol: Platz der Unit (FSlotKeys) und Position in ihren Symbolen; Next ist der
    /// nächste Verweis desselben Schlüssels (-1 = Ende).</summary>
    TSymbolRef = record
      Slot: Integer;
      Position: Integer;
      Next: Integer;
    end;
    /// <summary>Verweise eines Schlüssels in der Reihenfolge des Eintragens.</summary>
    TSymbolChain = record
      First: Integer;
      Last: Integer;
      Count: Integer;
    end;
    TSymbolTable = TDictionary<string, TSymbolChain>;
    /// <summary>Was die Suche nach Namen von der Unit eines Platzes braucht. FFiles.TryGetValue kopierte je
    /// Wechsel den ganzen TUnitIndex samt verwalteter Felder; die Symbole teilt sich dieser Eintrag mit ihm
    /// (dynamisches Array, nur gezählt).</summary>
    TSlotUnit = record
      Known: Boolean;
      UnitName: string;
      FileName: string;
      Symbols: TArray<TIndexSymbol>;
    end;
  private const
    /// <summary>Knoten je Block (12 Byte je Knoten).</summary>
    cNodeChunk = 16384;
    /// <summary>Ketten bis zu dieser Länge räumt das Verdrängen sofort auf; längere beim nächsten Lesen (Phase 4).
    /// </summary>
    cShortChain = 32;
  private
    // Name → Verweise; Vorfahr ohne Unit-Präfix und Typargumente → Verweise; beide ohne Groß-/Kleinschreibung.
    FByName: TSymbolTable;
    FByAncestor: TSymbolTable;
    // Alle Verweise, in Blöcken; FNodeCount belegt (samt freier).
    FNodes: TArray<TArray<TSymbolRef>>;
    FNodeCount: Integer;
    // Freiliste (Phase 3): Knoten entfernter Units, verkettet über Next; -1 = leer.
    FFreeNode: Integer;
    // Platz → Dateischlüssel ('' = Unit ersetzt oder entfernt) und Zahl seiner Verweise (bei ersetzten: der noch in
    // den Ketten stehenden).
    FSlotKeys: TList<string>;
    FSlotRefs: TList<Integer>;
    // Platz → Unit für die Suche (Known = False, wenn ersetzt oder entfernt); parallel zu FSlotKeys.
    FSlotUnits: TList<TSlotUnit>;
    // Platz → Knoten seiner Verweise, nur bei verdrängbaren Units (Phase 4: gezielt tot markieren); sonst nil.
    FSlotNodes: TList<TArray<Integer>>;
    // Freie Plätze (Phase 4): Kein Knoten verweist mehr auf sie.
    FFreeSlots: TList<Integer>;
    // Tote Knoten verdrängter Units je langer Kette (Phase 4); erreichen sie die Hälfte, wird die Kette aufgeräumt.
    FNameDead: TDictionary<string, Integer>;
    FAncestorDead: TDictionary<string, Integer>;
    // Dateischlüssel → aktueller Platz.
    FFileSlots: TDictionary<string, Integer>;
    FLiveRefs: Integer;
    // Tote Verweise, die noch in Ketten stehen (ersetzte Units, verdrängte in langen Ketten).
    FDeadRefs: Integer;
    function AddRef(ATable: TSymbolTable; const AKey: string; ASlot, APosition: Integer): Integer;
    function NodeAt(AIndex: Integer): TSymbolRef; inline;
    procedure SetNext(AIndex, ANext: Integer); inline;
    function NewSlot(const AKey: string; const ASlotUnit: TSlotUnit): Integer;
    /// <summary>Knoten in die Freiliste.</summary>
    procedure FreeNode(AIndex: Integer);
    /// <summary>Hängt den Knoten ANode (Vorgänger APrevious, -1 = Anfang) aus AChain aus und gibt ihn frei; war er
    /// tot, zählt er nicht mehr als tot, und ein ersetzter Platz ohne Verweise wird frei.</summary>
    procedure UnlinkDead(var AChain: TSymbolChain; APrevious, ANode: Integer);
    /// <summary>Ist der Verweis tot (verdrängte oder ersetzte Unit)?</summary>
    function IsDead(const ARef: TSymbolRef): Boolean; inline;
    procedure StoreChain(ATable: TSymbolTable; const AKey: string; const AChain: TSymbolChain);
    /// <summary>Zähler der toten Knoten zu ATable.</summary>
    function DeadOf(ATable: TSymbolTable): TDictionary<string, Integer>;
    /// <summary>Hängt alle toten Verweise aus der Kette von AKey aus.</summary>
    procedure CompactChain(ATable: TSymbolTable; const AKey: string);
    /// <summary>Ein Knoten der Kette von AKey ist eben tot geworden: kurze Ketten gleich aufräumen, lange, sobald die
    /// Hälfte tot ist (Kosten je totem Knoten gleichbleibend).</summary>
    procedure NoteDead(ATable: TSymbolTable; const AKey: string);
    /// <summary>Verdrängt den Platz einer verdrängbaren Unit: Knoten tot, kurze Ketten gleich aufgeräumt, Platz frei.
    /// </summary>
    procedure KillSlot(ASlot: Integer);
    function Locations(ATable: TSymbolTable; const AKey: string): TArray<TSymbolLocation>;
    /// <summary>Entfernt aus der Kette von AKey alle Verweise auf ASlot.</summary>
    procedure Unlink(ATable: TSymbolTable; const AKey: string; ASlot: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    /// <summary>Trägt die Symbole von AUnit (Dateischlüssel AKey) auf einem neuen oder frei gewordenen Platz ein.
    /// ATrack (verdrängbare Units): Der Platz merkt sich seine Knoten, damit Remove sie ohne Durchlauf der Ketten
    /// findet.</summary>
    procedure Add(const AKey: string; const AUnit: TUnitIndex; ATrack: Boolean = False);
    /// <summary>Macht die Verweise der Unit AKey tot.</summary>
    procedure Drop(const AKey: string);
    /// <summary>Entfernt die Verweise der Unit AKey mit den Symbolen ASymbols (Verdrängen, Phase 3); mit gemerkten
    /// Knoten (Phase 4) ohne Durchlauf der Ketten.</summary>
    procedure Remove(const AKey: string; const ASymbols: TArray<TIndexSymbol>);
    /// <summary>Belegte Plätze samt freier (Tests).</summary>
    function SlotCount: Integer;
    /// <summary>Belegte Knoten samt freier (Tests).</summary>
    property NodeCount: Integer read FNodeCount;
    /// <summary>Symbole mit dem Namen AName (ohne Groß-/Kleinschreibung).</summary>
    function ByName(const AName: string): TArray<TSymbolLocation>;
    /// <summary>Symbole mit dem Vorfahren AName (ohne Unit-Präfix und Typargumente, ohne Groß-/Kleinschreibung).
    /// </summary>
    function ByAncestor(const AName: string): TArray<TSymbolLocation>;
    function HasName(const AName: string; const AMatch: TSymbolMatch): Boolean;
    property LiveRefs: Integer read FLiveRefs;
    property DeadRefs: Integer read FDeadRefs;
  end;

  /// <summary>Zählerstände des Symbolindex: Symbole, geschätzte Bytes samt Anteilen (#1356: Verwendungen aller Units,
  /// Bibliotheks-Units ohne Verwendungen), kompakte Units und Units mit ausgelagerten Verwendungen.</summary>
  TSymbolIndexTotals = record
    SymbolCount: Integer;
    Bytes: Int64;
    UsageBytes: Int64;
    LibraryBytes: Int64;
    CompactCount: Integer;
    OffloadedCount: Integer;
    /// <summary>Zählt AUnit hinzu (ASign = 1) oder heraus (ASign = -1); ABytes und AUsageBytes sind ihre geschätzten
    /// Größen (TIndexMemory.UnitBytes, UsageBytes), einmal berechnet (Phase 4).</summary>
    procedure Count(const AUnit: TUnitIndex; ASign: Integer; ABytes, AUsageBytes: Int64);
  end;

  /// <summary>Ein Ladevorgang einer kalten Unit (Phase 4): Ein zweiter Leser derselben Unit wartet darauf, statt ihren
  /// Block noch einmal zu lesen. Referenzgezählt, damit der Wartende ihn auch hält, wenn der Eintrag inzwischen
  /// ersetzt ist.</summary>
  TIndexLoadSignal = class(TInterfacedObject)
  private
    FDone: TEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Signal;
    procedure WaitFor;
  end;

  /// <summary>Eine Unit im Index (Phase 3): Kopf oder volle Unit, Katalog, Block und Zähler für das Verdrängen.
  /// Nur unter der Sperre des Index benutzen.</summary>
  TIndexEntry = class
  public
    /// <summary>Eindeutig je Eintrag: Ein Ladevorgang außerhalb der Sperre erkennt daran, dass sein Eintrag noch gilt.
    /// </summary>
    Serial: Int64;
    /// <summary>Mit Symbolen, wenn Loaded; sonst nur der Kopf.</summary>
    Unit_: TUnitIndex;
    Catalog: TCatalogUnit;
    CatalogBytes: Int64;
    Source: IIndexUnitSource;
    Loaded: Boolean;
    Pinned: Boolean;
    /// <summary>Geschätzter Bedarf der geladenen Unit (TIndexMemory.UnitBytes) und davon der Verwendungen.</summary>
    Bytes: Int64;
    UsageBytes: Int64;
    /// <summary>Aus den uses einer Projekt-Unit oder oft genutzt (Phase 4): wird nicht verdrängt und zählt nicht gegen
    /// das Budget; nur bei geladenen, nicht gepinnten Units gepflegt.</summary>
    Guarded: Boolean;
    /// <summary>Laufender Ladevorgang (TIndexLoadSignal) oder nil.</summary>
    Loading: IInterface;
    SymbolCount: Integer;
    UnavailableCount: Integer;
    UsageCount: Integer;
    /// <summary>Nutzungen mit Alterung (HitEpoch) und letzte Nutzung (Zähler des Index).</summary>
    Hits: Integer;
    HitEpoch: Integer;
    LastUse: Int64;
    /// <summary>Zuletzt an die Nutzungsstatistik gemeldet (Ticks).</summary>
    LastNote: UInt64;
    /// <summary>Geladen, nicht gepinnt und mit Block: darf verdrängt werden.</summary>
    function Evictable: Boolean;
  end;

  TSymbolIndex = class(TInterfacedObject, ISymbolIndex, IIndexIncludeOwners)
  public const
    /// <summary>Ab so vielen toten Verweisen (und mehr tot als lebend) werden die Tabellen neu gebaut.</summary>
    cRebuildDeadRefs = 4096;
    /// <summary>Obergrenze für verdrängbare (nicht gepinnte) geladene Units (Phase 3); bewusst keine Einstellung.
    /// </summary>
    cEvictableBudget = 32 * 1024 * 1024;
    /// <summary>Nach so vielen Ladevorgängen halbieren sich die Nutzungszähler (Alterung des LFU).</summary>
    cAgingLoads = 64;
    /// <summary>Ab so vielen Punkten der Nutzungsstatistik gilt eine Bibliotheks-Unit als oft genutzt: Sie wird beim
    /// Aufbau geladen und nie verdrängt.</summary>
    cHotScore = cIndexHotScore;
    /// <summary>Ladedauern für Median und Höchstwert (Ringpuffer).</summary>
    cLoadSamples = 256;
  private
    FLock: TCriticalSection;
    // Schützt nur FPool (InternUnit außerhalb von FLock).
    FPoolLock: TCriticalSection;
    // Ergebnis von Units (nur geladene) bis zur nächsten Änderung; nil = neu aufbauen. Jede Änderung leert es,
    // damit ersetzte oder verdrängte Units nicht im Schnappschuss weiterleben.
    FUnitsSnapshot: TArray<TUnitIndex>;
    // Katalog aller Einträge bis zur nächsten Änderung der Generation.
    FCatalogSnapshot: TArray<TCatalogUnit>;
    // Dateischlüssel der Units mit Unavailable (#476).
    FUnavailable: TDictionary<string, Boolean>;
    // Dateiname (groß) → Eintrag
    FFiles: TObjectDictionary<string, TIndexEntry>;
    // Unit-Name (groß) → Dateinamen (groß), beste zuerst (L2: gleichnamige Units).
    FUnitFiles: TDictionary<string, TArray<string>>;
    // Dateiname (groß) → Nummer, mit der der Index ihn zuerst sah; Rang je Datei (L2). Unter FLock.
    FFileOrder: TDictionary<string, Int64>;
    FFileRank: TDictionary<string, Integer>;
    FFileOrderSerial: Int64;
    FUnitScopes: IIndexUnitScopes;
    // L2: Prüfung beim Nachladen kalter Units, ob die Datei neuer ist als der Block. Unter FLock gelesen.
    FStaleCheck: IIndexStaleCheck;
    // Zählerstände und Speicherschätzung aller geladenen Units.
    FTotals: TSymbolIndexTotals;
    FPool: TStringPool;
    FBudget: Int64;
    // Dateischlüssel der Units, die sich noch verkleinern lassen (nicht kompakt oder mit
    // Verwendungen); ShrinkLocked läuft nur über sie statt bei jeder Unit über alle.
    FShrinkable: TDictionary<string, Boolean>;
    FGeneration: Int64;
    FRefs: TSymbolRefTables;
    // Unit-Aliase (Vorgaben von Delphi und die der Projekte). Unter FLock.
    FAliases: TArray<TPair<string, string>>;
    // Phase 3: Laden und Verdrängen.
    FSerial: Int64;
    FClock: Int64;
    FEpoch: Integer;
    FLoadsInEpoch: Integer;
    // Geladene, nicht gepinnte Units mit Block; davon die nicht geschützten (nur sie zählen gegen das Budget).
    FEvictableBytes: Int64;
    FCandidateBytes: Int64;
    // Phase 4: uses der Projekt-Units haben sich geändert bzw. Stand der Alterung (FEpoch) beim letzten Prüfen des
    // Schutzes; der nächste Verdrängungslauf prüft ihn neu.
    FGuardDirty: Boolean;
    FGuardEpoch: Integer;
    FEvictionRuns: Integer;
    // So oft wurde der Schutz neu geprüft (Tests, Phase 5).
    FGuardRefreshes: Integer;
    FCatalogBytes: Int64;
    FColdSymbols: Integer;
    FLoads: Integer;
    FEvictions: Integer;
    FLoadMs: TArray<Double>;
    FLoadMsCount: Integer;
    FLoadMaxMs: Double;
    FLargestLoadBytes: Int64;
    FLargestLoadMs: Double;
    // uses der Projekt-Units (Name groß → Anzahl): Units dieses Namens bleiben geladen.
    FUsesPins: TDictionary<string, Integer>;
    // Name (Hash) → Eintrag mit diesem Symbol im Katalog, für FindSymbols über verdrängte Units; gilt für den Stand
    // FNameBuiltFor der Mitgliedschaft (Phase 4: nicht gepinnte Einträge mit Block, FNameMembership).
    FNameHashes: TArray<UInt64>;
    FNameKeys: TArray<string>;
    FNameMembership: Int64;
    FNameBuiltFor: Int64;
    FNameBuilds: Integer;
    FUsage: IIndexUsage;
    // L3: Include-Datei (groß) → Dateischlüssel der einbindenden Units in der Reihenfolge des Eintragens.
    FIncludeOwners: TDictionary<string, TArray<string>>;
    function NewEntry: TIndexEntry;
    /// <summary>Trägt AKey als einbindende Unit von AIncludes ein (L3).</summary>
    procedure LinkIncludesLocked(const AKey: string; const AIncludes: TArray<string>);
    /// <summary>Nimmt AKey bei AIncludes wieder heraus (L3).</summary>
    procedure UnlinkIncludesLocked(const AKey: string; const AIncludes: TArray<string>);
    procedure Account(AEntry: TIndexEntry; ASign: Integer);
    /// <summary>Gehört AEntry zum Namensverzeichnis der kalten Units (nicht gepinnt, mit Block)?</summary>
    class function NameRelevant(AEntry: TIndexEntry): Boolean; static; inline;
    procedure AddLocked(const AKey: string; const AUnit: TUnitIndex; APinned: Boolean;
      const ASource: IIndexUnitSource);
    /// <summary>Wie AddLocked mit vorab (außerhalb der Sperre) berechnetem Katalog und Größen.</summary>
    procedure AddPreparedLocked(const AKey: string; const AUnit: TUnitIndex; const ACatalog: TCatalogUnit;
      ABytes, AUsageBytes: Int64; APinned: Boolean; const ASource: IIndexUnitSource);
    /// <summary>Trägt die geladene Unit von AEntry mit ihren Größen in Tabellen und Zähler ein.</summary>
    procedure InstallLocked(const AKey: string; AEntry: TIndexEntry; ABytes, AUsageBytes: Int64);
    procedure ChangeUsesPins(const AUnit: TUnitIndex; ASign: Integer);
    function UsesPinned(AEntry: TIndexEntry): Boolean;
    /// <summary>Soll die geladene, nicht gepinnte Unit geschützt sein (uses einer Projekt-Unit, oft genutzt)?</summary>
    function ShouldGuardLocked(AEntry: TIndexEntry): Boolean;
    procedure SetGuardedLocked(AEntry: TIndexEntry; AValue: Boolean);
    /// <summary>Prüft den Schutz aller geladenen, nicht gepinnten Units neu.</summary>
    procedure RefreshGuardsLocked;
    procedure ShrinkLocked;
    function OverBudgetLocked: Boolean;
    /// <summary>Verkleinert die Unit AKey im Durchgang APass: 0 Bibliothek kompakt halten, 1 Verwendungen der
    /// Projekt-Units auslagern, 2 Projekt-Units kompakt halten.</summary>
    procedure ShrinkUnitLocked(APass: Integer; const AKey: string);
    procedure RemoveFileLocked(const AFileKey: string);
    /// <summary>Trägt AKey unter dem Unit-Namen AUnitName an seinem Rang ein (L2).</summary>
    procedure LinkUnitFileLocked(const AUnitName, AKey: string; ALibrary: Boolean);
    /// <summary>Nimmt AKey aus den Dateien von AUnitName; die anderen bleiben (L2).</summary>
    procedure UnlinkUnitFileLocked(const AUnitName, AKey: string);
    /// <summary>Baut die Tabellen neu, wenn die toten Verweise überwiegen.</summary>
    procedure CleanRefsLocked;
    /// <summary>Dateischlüssel zum Unit-Namen (auch über Aliase); '' wenn unbekannt.</summary>
    function UnitKeyLocked(const AUnitName: string): string;
    procedure TouchLocked(AEntry: TIndexEntry);
    /// <summary>Lädt die Unit AKey nach, falls sie verdrängt ist; liefert sie.</summary>
    function LoadKey(const AKey: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Ein Versuch von LoadKey; ARetry: Der Block war unlesbar, aber die Unit hat inzwischen einen neuen
    /// (BindSources nach dem Schreiben des Caches), also noch einmal (Phase 5).</summary>
    function LoadKeyOnce(const AKey: string; out AUnit: TUnitIndex; out ARetry: Boolean): Boolean;
    /// <summary>Verdrängt, bis die verdrängbaren Units wieder ins Budget passen; AKeep bleibt.</summary>
    procedure EvictLocked(AKeep: TIndexEntry); overload;
    /// <summary>Wie oben bis ABudget (L2: TrimEvictable mit 0).</summary>
    procedure EvictLocked(AKeep: TIndexEntry; ABudget: Int64); overload;
    procedure UnloadLocked(const AKey: string; AEntry: TIndexEntry);
    /// <summary>Einträge, deren Katalog vielleicht ein Symbol AName hat (gleicher Hash), über das Namensverzeichnis;
    /// AMembership ist der Stand der Mitgliedschaft, für den es gilt. Ohne Sperre.</summary>
    procedure ColdCandidates(const AName: string; out ACandidates: TArray<string>; out AMembership: Int64);
    /// <summary>Die kalten Einträge aus ACandidates, deren Katalog ein Symbol AName hat (Phase 5).</summary>
    function ColdKeysLocked(const AName: string; const ACandidates: TArray<string>): TArray<string>;
    /// <summary>Liest unter einer Sperre mit ARead die geladenen Units und liefert die kalten Units mit AName
    /// (Phase 5); hat sich die Menge der kalten Units während des Namensverzeichnisses geändert, noch einmal.</summary>
    function SnapshotNamed(const AName: string; const ARead: TProc): TArray<string>;
    /// <summary>Namensverzeichnis der kalten Units für die Mitgliedschaft FNameMembership; baut es außerhalb der Sperre
    /// neu, wenn es nicht mehr gilt. AMembership: Stand, für den das Ergebnis gilt.</summary>
    procedure NameLookup(out AHashes: TArray<UInt64>; out AKeys: TArray<string>; out AMembership: Int64);
    procedure NoteLoad(AMs: Double; ABytes: Int64);
    /// <summary>Nutzungsstatistik: Namen, die eine Projekt-Unit neu in ihre uses aufnimmt (angenommenes "+ Unit").
    /// </summary>
    procedure NoteAddedUsesLocked(const AOld, ANew: TUnitIndex);
  public
    constructor Create;
    destructor Destroy; override;
    { ISymbolIndex }
    procedure AddUnit(const AUnit: TUnitIndex);
    procedure RemoveFile(const AFileName: string);
    function FindUnit(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
    procedure AddUnitAliases(const AAliases: TArray<TPair<string, string>>);
    function FindFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    function FindSymbols(const AName: string): TArray<TSymbolLocation>;
    function HasSymbol(const AName: string; const AMatch: TSymbolMatch): Boolean;
    function Descendants(const ATypeName: string): TArray<TSymbolLocation>;
    function Units: TArray<TUnitIndex>;
    function UnavailableUnits: TArray<TUnitIndex>;
    function UnitCount: Integer;
    function SymbolCount: Integer;
    function MemoryBytes: Int64;
    function MemoryParts: TIndexMemoryParts;
    function CompactCount: Integer;
    function OffloadedCount: Integer;
    procedure SetBudget(ABytes: Int64);
    function Budget: Int64;
    function Generation: Int64;
    procedure ReleaseStringPool;
    function FindHeader(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    function FindUnitHeader(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
    function CatalogUnits: TArray<TCatalogUnit>;
    function StoredUnits: TArray<TIndexStoredUnit>;
    procedure AddEvictable(const AUnit: TUnitIndex; const ASource: IIndexUnitSource);
    procedure AddCold(const AHeader: TUnitIndex; const ACatalog: TCatalogUnit; const ASource: IIndexUnitSource;
      ASymbolCount, AUnavailableCount, AUsageCount: Integer);
    function Pin(const AFileName: string; out AWasPinned: Boolean): Boolean;
    function BindSources(const AHeaders: TArray<TUnitIndex>; const ASources: TArray<IIndexUnitSource>): Integer;
    function LazyStats: TIndexLazyStats;
    procedure SetUsage(const AUsage: IIndexUsage);
    function Usage: IIndexUsage;
    function UnitFiles(const AUnitName: string): TArray<string>;
    procedure SetUnitScopes(const AScopes: IIndexUnitScopes);
    function UnitScopes: IIndexUnitScopes;
    procedure SetStaleCheck(const ACheck: IIndexStaleCheck);
    function StaleCheck: IIndexStaleCheck;
    procedure TrimEvictable;
    { IIndexIncludeOwners }
    function IncludeOwner(const AIncludeFile: string): string;
    /// <summary>So oft wurde das Namensverzeichnis der kalten Units gebaut (Tests, Phase 4).</summary>
    function NameLookupBuilds: Integer;
    /// <summary>So oft suchte der Index Units zum Verdrängen (Tests, Phase 4).</summary>
    function EvictionRuns: Integer;
    /// <summary>So oft prüfte der Index den Schutz aller geladenen Units neu (Tests, Phase 5).</summary>
    function GuardRefreshes: Integer;
    /// <summary>Belegte Plätze und Knoten der Verweistabellen (Tests, Phase 4).</summary>
    function RefSlots: Integer;
    function RefNodes: Integer;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.Math,
  System.StrUtils,
  System.Generics.Defaults,
  dpcc.Common.Projects.UnitAliases,
  dpcc.Common.Index.Cache,
  dpcc.Common.Index.NameIndex;

var
  // Jeder Index beginnt mit eigener Generation, damit ein neuer Index an derselben Adresse
  // nie für den alten gehalten wird (#617).
  IndexSerial: Int64;

function LastPart(const AName: string): string;
var
  mDot: Integer;
begin
  // Unit.TFoo und TFoo<T> auf TFoo zurückführen.
  Result := AName;
  mDot := Pos('<', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, 1, mDot - 1);
  end;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

/// <summary>Kopf einer Unit ohne Symbole, nicht geltende Deklarationen, Verwendungen und Namenstabelle.</summary>
function HeaderOf(const AUnit: TUnitIndex): TUnitIndex;
begin
  Result := AUnit;
  Result.Symbols := nil;
  Result.Unavailable := nil;
  Result.Usages := nil;
  Result.NameTable := nil;
end;

{ TIndexEntry }

function TIndexEntry.Evictable: Boolean;
begin
  Result := Loaded and not Pinned and (Source <> nil);
end;

{ TIndexLoadSignal }

constructor TIndexLoadSignal.Create;
begin
  inherited Create;
  FDone := TEvent.Create(nil, True, False, '');
end;

destructor TIndexLoadSignal.Destroy;
begin
  FDone.Free;
  inherited;
end;

procedure TIndexLoadSignal.Signal;
begin
  FDone.SetEvent;
end;

procedure TIndexLoadSignal.WaitFor;
begin
  FDone.WaitFor(INFINITE);
end;

{ TSymbolIndex }

constructor TSymbolIndex.Create;
begin
  inherited Create;
  FGeneration := TInterlocked.Increment(IndexSerial) shl 32;
  FLock := TCriticalSection.Create;
  FPoolLock := TCriticalSection.Create;
  FUnavailable := TDictionary<string, Boolean>.Create;
  FFiles := TObjectDictionary<string, TIndexEntry>.Create([doOwnsValues]);
  FUnitFiles := TDictionary<string, TArray<string>>.Create;
  FFileOrder := TDictionary<string, Int64>.Create;
  FFileRank := TDictionary<string, Integer>.Create;
  FPool := TStringPool.Create;
  FRefs := TSymbolRefTables.Create;
  FShrinkable := TDictionary<string, Boolean>.Create;
  FUsesPins := TDictionary<string, Integer>.Create;
  FIncludeOwners := TDictionary<string, TArray<string>>.Create;
  FAliases := TUnitAliases.Defaults;
  SetLength(FLoadMs, cLoadSamples);
  FNameBuiltFor := -1;
end;

destructor TSymbolIndex.Destroy;
begin
  // Namensindex der Import-Vorschläge (#617) hält sonst unseren Katalog fest.
  TImportNames.Forget(Self);
  FIncludeOwners.Free;
  FUsesPins.Free;
  FShrinkable.Free;
  FRefs.Free;
  FPool.Free;
  FFileRank.Free;
  FFileOrder.Free;
  FUnitFiles.Free;
  FFiles.Free;
  FUnavailable.Free;
  FPoolLock.Free;
  FLock.Free;
  inherited;
end;

procedure TSymbolIndex.LinkIncludesLocked(const AKey: string; const AIncludes: TArray<string>);
var
  mInclude, mIncludeKey: string;
  mOwners: TArray<string>;
begin
  for mInclude in AIncludes do
  begin
    mIncludeKey := AnsiUpperCase(mInclude);
    if not FIncludeOwners.TryGetValue(mIncludeKey, mOwners) then
    begin
      mOwners := nil;
    end
    else if IndexStr(AKey, mOwners) >= 0 then
    begin
      // Dieselbe Datei zweimal eingebunden ({$I} in mehreren Zweigen).
      Continue;
    end;
    FIncludeOwners.AddOrSetValue(mIncludeKey, mOwners + [AKey]);
  end;
end;

procedure TSymbolIndex.UnlinkIncludesLocked(const AKey: string; const AIncludes: TArray<string>);
var
  mInclude, mIncludeKey: string;
  mOwners: TArray<string>;
  mAt: Integer;
begin
  for mInclude in AIncludes do
  begin
    mIncludeKey := AnsiUpperCase(mInclude);
    if not FIncludeOwners.TryGetValue(mIncludeKey, mOwners) then
    begin
      Continue;
    end;
    mAt := IndexStr(AKey, mOwners);
    if mAt < 0 then
    begin
      Continue;
    end;
    // Kopie: Ein Leser könnte das alte Array noch halten.
    mOwners := Copy(mOwners);
    Delete(mOwners, mAt, 1);
    if Length(mOwners) = 0 then
    begin
      FIncludeOwners.Remove(mIncludeKey);
    end
    else
    begin
      FIncludeOwners.AddOrSetValue(mIncludeKey, mOwners);
    end;
  end;
end;

function TSymbolIndex.IncludeOwner(const AIncludeFile: string): string;
var
  mOwners: TArray<string>;
  mKey: string;
  mEntry: TIndexEntry;
  mRank, mBestRank: Integer;
begin
  Result := '';
  FLock.Enter;
  try
    if not FIncludeOwners.TryGetValue(AnsiUpperCase(AIncludeFile), mOwners) then
    begin
      Exit;
    end;
    mBestRank := MaxInt;
    for mKey in mOwners do
    begin
      if not FFiles.TryGetValue(mKey, mEntry) then
      begin
        Continue;
      end;
      // Eine geladene Unit braucht kein Nachladen.
      if mEntry.Loaded then
      begin
        Exit(mEntry.Unit_.FileName);
      end;
      if not FFileRank.TryGetValue(mKey, mRank) then
      begin
        mRank := MaxInt - 1;
      end;
      if mRank < mBestRank then
      begin
        mBestRank := mRank;
        Result := mEntry.Unit_.FileName;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.NewEntry: TIndexEntry;
begin
  Result := TIndexEntry.Create;
  Inc(FSerial);
  Result.Serial := FSerial;
  Result.HitEpoch := FEpoch;
end;

procedure TSymbolIndex.Account(AEntry: TIndexEntry; ASign: Integer);
begin
  if AEntry.Evictable then
  begin
    Inc(FEvictableBytes, ASign * AEntry.Bytes);
    // Nur nicht geschützte zählen gegen das Budget (Phase 4).
    if not AEntry.Guarded then
    begin
      Inc(FCandidateBytes, ASign * AEntry.Bytes);
    end;
  end;
end;

class function TSymbolIndex.NameRelevant(AEntry: TIndexEntry): Boolean;
begin
  Result := not AEntry.Pinned and (AEntry.Source <> nil);
end;

procedure TSymbolIndex.ChangeUsesPins(const AUnit: TUnitIndex; ASign: Integer);
var
  mName, mKey: string;
  mCount: Integer;
begin
  // Nur Projekt-Units: Was sie (auch beim Tippen, ApplyText) in die uses schreiben, bleibt geladen.
  if AUnit.Library_ then
  begin
    Exit;
  end;
  for mName in AUnit.InterfaceUses + AUnit.ImplementationUses do
  begin
    mKey := UpperCase(mName);
    if not FUsesPins.TryGetValue(mKey, mCount) then
    begin
      mCount := 0;
    end;
    Inc(mCount, ASign);
    if mCount <= 0 then
    begin
      // Ein Name fällt aus den uses: Der Schutz der Units gilt nicht mehr (Phase 4, beim nächsten Verdrängen geprüft).
      if FUsesPins.ContainsKey(mKey) then
      begin
        FUsesPins.Remove(mKey);
        FGuardDirty := True;
      end;
    end
    else
    begin
      // Nur ein neu hinzugekommener Name (0 → 1) ändert den Schutz. Beim Tippen zählt die neue Fassung vorab mit
      // (1 → 2 → 1 → 2 → 1): Das Sinken auf 1 ist kein Wegfall und darf nicht jedes Mal alle Units neu prüfen
      // (Phase 5, R1).
      if (ASign > 0) and (mCount = 1) then
      begin
        FGuardDirty := True;
      end;
      FUsesPins.AddOrSetValue(mKey, mCount);
    end;
  end;
end;

function TSymbolIndex.ShouldGuardLocked(AEntry: TIndexEntry): Boolean;
begin
  Result := UsesPinned(AEntry) or ((FUsage <> nil) and AEntry.Unit_.Library_ and
    (FUsage.Score(AEntry.Unit_.UnitName) >= cHotScore));
end;

procedure TSymbolIndex.SetGuardedLocked(AEntry: TIndexEntry; AValue: Boolean);
begin
  if AEntry.Guarded = AValue then
  begin
    Exit;
  end;
  Account(AEntry, -1);
  AEntry.Guarded := AValue;
  Account(AEntry, 1);
end;

procedure TSymbolIndex.RefreshGuardsLocked;
var
  mEntry: TIndexEntry;
begin
  for mEntry in FFiles.Values do
  begin
    if mEntry.Loaded and not mEntry.Pinned then
    begin
      SetGuardedLocked(mEntry, ShouldGuardLocked(mEntry));
    end;
  end;
  FGuardDirty := False;
  FGuardEpoch := FEpoch;
  Inc(FGuardRefreshes);
end;

function TSymbolIndex.UsesPinned(AEntry: TIndexEntry): Boolean;
var
  mName: string;
  mDot: Integer;
begin
  // Auch ohne Namespace genannt (uses Forms → Vcl.Forms).
  mName := UpperCase(AEntry.Unit_.UnitName);
  repeat
    if FUsesPins.ContainsKey(mName) then
    begin
      Exit(True);
    end;
    mDot := Pos('.', mName);
    if mDot > 0 then
    begin
      mName := Copy(mName, mDot + 1, MaxInt);
    end;
  until mDot = 0;
  Result := False;
end;

procedure TSymbolIndex.LinkUnitFileLocked(const AUnitName, AKey: string; ALibrary: Boolean);
var
  mFiles: TArray<string>;
  mOrder, mOther: Int64;
  mRank, mOtherRank, mIndex, mAt: Integer;
begin
  if not FFileOrder.TryGetValue(AKey, mOrder) then
  begin
    Inc(FFileOrderSerial);
    mOrder := FFileOrderSerial;
    FFileOrder.Add(AKey, mOrder);
  end;
  if FUnitScopes <> nil then
  begin
    mRank := FUnitScopes.RankOf(AKey, ALibrary);
  end
  else
  begin
    mRank := Ord(ALibrary);
  end;
  FFileRank.AddOrSetValue(AKey, mRank);
  if not FUnitFiles.TryGetValue(AUnitName, mFiles) then
  begin
    FUnitFiles.Add(AUnitName, TArray<string>.Create(AKey));
    Exit;
  end;
  // Schon eingetragen (neue Fassung derselben Datei): herausnehmen und am Rang neu einordnen.
  mAt := -1;
  for mIndex := 0 to High(mFiles) do
  begin
    if mFiles[mIndex] = AKey then
    begin
      mAt := mIndex;
      Break;
    end;
  end;
  if mAt >= 0 then
  begin
    Delete(mFiles, mAt, 1);
  end;
  mAt := Length(mFiles);
  for mIndex := 0 to High(mFiles) do
  begin
    if not FFileRank.TryGetValue(mFiles[mIndex], mOtherRank) then
    begin
      mOtherRank := MaxInt;
    end;
    if not FFileOrder.TryGetValue(mFiles[mIndex], mOther) then
    begin
      mOther := High(Int64);
    end;
    if (mRank < mOtherRank) or ((mRank = mOtherRank) and (mOrder < mOther)) then
    begin
      mAt := mIndex;
      Break;
    end;
  end;
  Insert(AKey, mFiles, mAt);
  FUnitFiles.AddOrSetValue(AUnitName, mFiles);
end;

procedure TSymbolIndex.UnlinkUnitFileLocked(const AUnitName, AKey: string);
var
  mFiles: TArray<string>;
  mIndex: Integer;
begin
  if not FUnitFiles.TryGetValue(AUnitName, mFiles) then
  begin
    Exit;
  end;
  for mIndex := High(mFiles) downto 0 do
  begin
    if mFiles[mIndex] = AKey then
    begin
      Delete(mFiles, mIndex, 1);
    end;
  end;
  if Length(mFiles) = 0 then
  begin
    FUnitFiles.Remove(AUnitName);
  end
  else
  begin
    FUnitFiles.AddOrSetValue(AUnitName, mFiles);
  end;
end;

procedure TSymbolIndex.RemoveFileLocked(const AFileKey: string);
var
  mExisting: TIndexEntry;
begin
  if not FFiles.TryGetValue(AFileKey, mExisting) then
  begin
    Exit;
  end;
  Account(mExisting, -1);
  if mExisting.Loaded then
  begin
    FTotals.Count(mExisting.Unit_, -1, mExisting.Bytes, mExisting.UsageBytes);
    FRefs.Drop(AFileKey);
    ChangeUsesPins(mExisting.Unit_, -1);
  end
  else
  begin
    Dec(FColdSymbols, mExisting.SymbolCount);
  end;
  if NameRelevant(mExisting) then
  begin
    Inc(FNameMembership);
  end;
  Dec(FCatalogBytes, mExisting.CatalogBytes);
  FUnitsSnapshot := nil;
  FCatalogSnapshot := nil;
  FUnavailable.Remove(AFileKey);
  FShrinkable.Remove(AFileKey);
  Inc(FGeneration);
  // L2: Nur diese Datei fällt weg; gleichnamige Units anderer Dateien bleiben unter dem Namen.
  UnlinkUnitFileLocked(UpperCase(mExisting.Unit_.UnitName), AFileKey);
  UnlinkIncludesLocked(AFileKey, mExisting.Unit_.Includes);
  FFiles.Remove(AFileKey);
end;

procedure TSymbolIndex.InstallLocked(const AKey: string; AEntry: TIndexEntry; ABytes, AUsageBytes: Int64);
begin
  // Jede abgelegte Fassung bekommt ihre eigene Namenstabelle (Diagnoselog 15.10.2026); FindUnit und
  // FindFile geben sie mit, die Namensauflösung sucht darüber statt linear. Anlegen kostet nur das leere Objekt;
  // gebaut wird sie beim ersten Zugriff.
  AEntry.Unit_.PrepareNames;
  AEntry.Loaded := True;
  AEntry.Bytes := ABytes;
  AEntry.UsageBytes := AUsageBytes;
  AEntry.SymbolCount := Length(AEntry.Unit_.Symbols);
  AEntry.UnavailableCount := Length(AEntry.Unit_.Unavailable);
  AEntry.UsageCount := Length(AEntry.Unit_.Usages);
  FUnitsSnapshot := nil;
  if Length(AEntry.Unit_.Unavailable) > 0 then
  begin
    FUnavailable.AddOrSetValue(AKey, True);
  end;
  FTotals.Count(AEntry.Unit_, 1, ABytes, AUsageBytes);
  if not AEntry.Unit_.Compact or (Length(AEntry.Unit_.Usages) > 0) then
  begin
    FShrinkable.AddOrSetValue(AKey, True);
  end;
  // Verdrängbare merken sich ihre Knoten (Phase 4).
  FRefs.Add(AKey, AEntry.Unit_, not AEntry.Pinned);
  ChangeUsesPins(AEntry.Unit_, 1);
  AEntry.Guarded := not AEntry.Pinned and ShouldGuardLocked(AEntry);
  Account(AEntry, 1);
end;

procedure TSymbolIndex.AddLocked(const AKey: string; const AUnit: TUnitIndex; APinned: Boolean;
  const ASource: IIndexUnitSource);
begin
  AddPreparedLocked(AKey, AUnit, TCatalogUnit.FromUnit(AUnit), TIndexMemory.UnitBytes(AUnit),
    TIndexMemory.UsageBytes(AUnit), APinned, ASource);
end;

procedure TSymbolIndex.AddPreparedLocked(const AKey: string; const AUnit: TUnitIndex; const ACatalog: TCatalogUnit;
  ABytes, AUsageBytes: Int64; APinned: Boolean; const ASource: IIndexUnitSource);
var
  mEntry: TIndexEntry;
begin
  mEntry := NewEntry;
  mEntry.Unit_ := AUnit;
  mEntry.Pinned := APinned;
  mEntry.Source := ASource;
  mEntry.Catalog := ACatalog;
  mEntry.CatalogBytes := mEntry.Catalog.Bytes;
  FFiles.Add(AKey, mEntry);
  Inc(FCatalogBytes, mEntry.CatalogBytes);
  FCatalogSnapshot := nil;
  Inc(FGeneration);
  if NameRelevant(mEntry) then
  begin
    Inc(FNameMembership);
  end;
  LinkUnitFileLocked(UpperCase(AUnit.UnitName), AKey, AUnit.Library_);
  LinkIncludesLocked(AKey, AUnit.Includes);
  InstallLocked(AKey, mEntry, ABytes, AUsageBytes);
end;

{ TSymbolIndexTotals }

procedure TSymbolIndexTotals.Count(const AUnit: TUnitIndex; ASign: Integer; ABytes, AUsageBytes: Int64);
begin
  Inc(SymbolCount, ASign * Length(AUnit.Symbols));
  Inc(Bytes, ASign * ABytes);
  Inc(UsageBytes, ASign * AUsageBytes);
  if AUnit.Library_ then
  begin
    Inc(LibraryBytes, ASign * (ABytes - AUsageBytes));
  end;
  if AUnit.Compact then
  begin
    Inc(CompactCount, ASign);
  end;
  if AUnit.UsagesOffloaded then
  begin
    Inc(OffloadedCount, ASign);
  end;
end;

{ TSymbolRefTables }

/// <summary>FNV-1a über die Zeichen, a–z wie A–Z (passt zu CompareText).</summary>
function NameHash(const AName: string): Integer;
var
  mHash: Cardinal;
  mIndex: Integer;
  mCode: Cardinal;
begin
  mHash := 2166136261;
  for mIndex := 1 to Length(AName) do
  begin
    mCode := Ord(AName[mIndex]);
    if (mCode >= Ord('a')) and (mCode <= Ord('z')) then
    begin
      Dec(mCode, 32);
    end;
    mHash := Cardinal(UInt64(mHash xor mCode) * 16777619);
  end;
  Result := Integer(mHash);
end;

/// <summary>Schlüssel ohne Groß-/Kleinschreibung wie früher UpperCase (nur a–z), ohne Kopie des Namens.</summary>
function NameComparer: IEqualityComparer<string>;
begin
  Result := TEqualityComparer<string>.Construct(
    function(const ALeft, ARight: string): Boolean
    begin
      Result := CompareText(ALeft, ARight) = 0;
    end,
    function(const AValue: string): Integer
    begin
      Result := NameHash(AValue);
    end);
end;

constructor TSymbolRefTables.Create;
begin
  inherited Create;
  FByName := TSymbolTable.Create(NameComparer);
  FByAncestor := TSymbolTable.Create(NameComparer);
  FSlotKeys := TList<string>.Create;
  FSlotRefs := TList<Integer>.Create;
  FSlotUnits := TList<TSlotUnit>.Create;
  FSlotNodes := TList<TArray<Integer>>.Create;
  FFreeSlots := TList<Integer>.Create;
  FNameDead := TDictionary<string, Integer>.Create(NameComparer);
  FAncestorDead := TDictionary<string, Integer>.Create(NameComparer);
  FFileSlots := TDictionary<string, Integer>.Create;
  FFreeNode := -1;
end;

destructor TSymbolRefTables.Destroy;
begin
  FFileSlots.Free;
  FAncestorDead.Free;
  FNameDead.Free;
  FFreeSlots.Free;
  FSlotNodes.Free;
  FSlotUnits.Free;
  FSlotRefs.Free;
  FSlotKeys.Free;
  FByAncestor.Free;
  FByName.Free;
  inherited;
end;

procedure TSymbolRefTables.Clear;
begin
  FByName.Clear;
  FByAncestor.Clear;
  FNodes := nil;
  FNodeCount := 0;
  FFreeNode := -1;
  FSlotKeys.Clear;
  FSlotRefs.Clear;
  FSlotUnits.Clear;
  FSlotNodes.Clear;
  FFreeSlots.Clear;
  FNameDead.Clear;
  FAncestorDead.Clear;
  FFileSlots.Clear;
  FLiveRefs := 0;
  FDeadRefs := 0;
end;

function TSymbolRefTables.SlotCount: Integer;
begin
  Result := FSlotKeys.Count;
end;

function TSymbolRefTables.NodeAt(AIndex: Integer): TSymbolRef;
begin
  Result := FNodes[AIndex div cNodeChunk][AIndex mod cNodeChunk];
end;

procedure TSymbolRefTables.SetNext(AIndex, ANext: Integer);
begin
  FNodes[AIndex div cNodeChunk][AIndex mod cNodeChunk].Next := ANext;
end;

function TSymbolRefTables.AddRef(ATable: TSymbolTable; const AKey: string; ASlot, APosition: Integer): Integer;
var
  mChain: TSymbolChain;
  mBlock: Integer;
begin
  // Erst die Freiliste (Knoten verdrängter Units), dann ein neuer Knoten.
  if FFreeNode >= 0 then
  begin
    Result := FFreeNode;
    FFreeNode := NodeAt(Result).Next;
  end
  else
  begin
    Result := FNodeCount;
    mBlock := Result div cNodeChunk;
    if mBlock >= Length(FNodes) then
    begin
      SetLength(FNodes, mBlock + 1);
      SetLength(FNodes[mBlock], cNodeChunk);
    end;
    Inc(FNodeCount);
  end;
  FNodes[Result div cNodeChunk][Result mod cNodeChunk].Slot := ASlot;
  FNodes[Result div cNodeChunk][Result mod cNodeChunk].Position := APosition;
  FNodes[Result div cNodeChunk][Result mod cNodeChunk].Next := -1;
  if ATable.TryGetValue(AKey, mChain) then
  begin
    SetNext(mChain.Last, Result);
    mChain.Last := Result;
    Inc(mChain.Count);
    ATable[AKey] := mChain;
  end
  else
  begin
    mChain.First := Result;
    mChain.Last := Result;
    mChain.Count := 1;
    ATable.Add(AKey, mChain);
  end;
end;

/// <summary>Vorfahren eines Symbols ohne Unit-Präfix und Typargumente, jeden einmal ohne Groß-/Kleinschreibung
/// (class(TFoo, IFoo) mit Unit.TFoo und TFoo&lt;T&gt;).</summary>
function AncestorKeys(const ASymbol: TIndexSymbol): TArray<string>;
var
  mIndex: Integer;
  mKey: string;
begin
  Result := nil;
  for mIndex := 0 to High(ASymbol.Ancestors) do
  begin
    mKey := LastPart(ASymbol.Ancestors[mIndex]);
    if (mKey <> '') and (IndexText(mKey, Result) < 0) then
    begin
      Result := Result + [mKey];
    end;
  end;
end;

function TSymbolRefTables.NewSlot(const AKey: string; const ASlotUnit: TSlotUnit): Integer;
begin
  // Phase 4: Plätze verdrängter Units wiederverwenden; vorher kam bei jedem Laden ein neuer hinzu.
  if FFreeSlots.Count > 0 then
  begin
    Result := FFreeSlots[FFreeSlots.Count - 1];
    FFreeSlots.Delete(FFreeSlots.Count - 1);
    FSlotKeys[Result] := AKey;
    FSlotRefs[Result] := 0;
    FSlotUnits[Result] := ASlotUnit;
    FSlotNodes[Result] := nil;
  end
  else
  begin
    Result := FSlotKeys.Add(AKey);
    FSlotRefs.Add(0);
    FSlotUnits.Add(ASlotUnit);
    FSlotNodes.Add(nil);
  end;
end;

procedure TSymbolRefTables.Add(const AKey: string; const AUnit: TUnitIndex; ATrack: Boolean);
var
  mSlot, mPosition, mCount: Integer;
  mKey: string;
  mSlotUnit: TSlotUnit;
  mNodes: TArray<Integer>;

  procedure Track(ANode: Integer);
  begin
    if mCount >= Length(mNodes) then
    begin
      SetLength(mNodes, Length(mNodes) * 2 + 16);
    end;
    mNodes[mCount] := ANode;
  end;

begin
  mSlotUnit.Known := True;
  mSlotUnit.UnitName := AUnit.UnitName;
  mSlotUnit.FileName := AUnit.FileName;
  mSlotUnit.Symbols := AUnit.Symbols;
  mSlot := NewSlot(AKey, mSlotUnit);
  FFileSlots.AddOrSetValue(AKey, mSlot);
  mCount := 0;
  mNodes := nil;
  if ATrack then
  begin
    SetLength(mNodes, Length(AUnit.Symbols));
  end;
  // Zugriff über den Index, damit die Symbol-Records nicht kopiert werden.
  for mPosition := 0 to High(AUnit.Symbols) do
  begin
    // Der Name selbst ist der Schlüssel (geteilter Puffer, keine Kopie).
    if ATrack then
    begin
      Track(AddRef(FByName, AUnit.Symbols[mPosition].Name, mSlot, mPosition));
    end
    else
    begin
      AddRef(FByName, AUnit.Symbols[mPosition].Name, mSlot, mPosition);
    end;
    Inc(mCount);
    for mKey in AncestorKeys(AUnit.Symbols[mPosition]) do
    begin
      if ATrack then
      begin
        Track(AddRef(FByAncestor, mKey, mSlot, mPosition));
      end
      else
      begin
        AddRef(FByAncestor, mKey, mSlot, mPosition);
      end;
      Inc(mCount);
    end;
  end;
  if ATrack then
  begin
    SetLength(mNodes, mCount);
    // Leere Unit: ein leeres, aber gesetztes Feld kennzeichnet den Platz trotzdem als verfolgt.
    if mCount = 0 then
    begin
      mNodes := [-1];
    end;
    FSlotNodes[mSlot] := mNodes;
  end;
  FSlotRefs[mSlot] := mCount;
  Inc(FLiveRefs, mCount);
end;

function TSymbolRefTables.IsDead(const ARef: TSymbolRef): Boolean;
begin
  // Slot -1: Knoten einer verdrängten Unit; sonst ein Platz, dessen Unit ersetzt oder entfernt ist. Über List ohne
  // Kopie des Eintrags (verwaltete Felder).
  Result := (ARef.Slot < 0) or not FSlotUnits.List[ARef.Slot].Known;
end;

procedure TSymbolRefTables.FreeNode(AIndex: Integer);
begin
  // Slot -1 hält den Knoten aus jeder Suche heraus.
  FNodes[AIndex div cNodeChunk][AIndex mod cNodeChunk].Slot := -1;
  SetNext(AIndex, FFreeNode);
  FFreeNode := AIndex;
end;

procedure TSymbolRefTables.UnlinkDead(var AChain: TSymbolChain; APrevious, ANode: Integer);
var
  mRef: TSymbolRef;
begin
  mRef := NodeAt(ANode);
  if APrevious < 0 then
  begin
    AChain.First := mRef.Next;
  end
  else
  begin
    SetNext(APrevious, mRef.Next);
  end;
  if AChain.Last = ANode then
  begin
    AChain.Last := APrevious;
  end;
  Dec(AChain.Count);
  Dec(FDeadRefs);
  // Verweis auf einen ersetzten Platz: Ist es sein letzter, wird der Platz frei.
  if mRef.Slot >= 0 then
  begin
    FSlotRefs[mRef.Slot] := FSlotRefs[mRef.Slot] - 1;
    if FSlotRefs[mRef.Slot] = 0 then
    begin
      FFreeSlots.Add(mRef.Slot);
    end;
  end;
  FreeNode(ANode);
end;

procedure TSymbolRefTables.StoreChain(ATable: TSymbolTable; const AKey: string; const AChain: TSymbolChain);
begin
  if AChain.Count <= 0 then
  begin
    ATable.Remove(AKey);
  end
  else
  begin
    ATable[AKey] := AChain;
  end;
end;

function TSymbolRefTables.DeadOf(ATable: TSymbolTable): TDictionary<string, Integer>;
begin
  if ATable = FByName then
  begin
    Result := FNameDead;
  end
  else
  begin
    Result := FAncestorDead;
  end;
end;

procedure TSymbolRefTables.CompactChain(ATable: TSymbolTable; const AKey: string);
var
  mChain: TSymbolChain;
  mNode, mPrevious, mNext: Integer;
  mChanged: Boolean;
begin
  DeadOf(ATable).Remove(AKey);
  if not ATable.TryGetValue(AKey, mChain) then
  begin
    Exit;
  end;
  mChanged := False;
  mPrevious := -1;
  mNode := mChain.First;
  while mNode >= 0 do
  begin
    mNext := NodeAt(mNode).Next;
    if IsDead(NodeAt(mNode)) then
    begin
      UnlinkDead(mChain, mPrevious, mNode);
      mChanged := True;
    end
    else
    begin
      mPrevious := mNode;
    end;
    mNode := mNext;
  end;
  if mChanged then
  begin
    StoreChain(ATable, AKey, mChain);
  end;
end;

procedure TSymbolRefTables.NoteDead(ATable: TSymbolTable; const AKey: string);
var
  mChain: TSymbolChain;
  mDead: TDictionary<string, Integer>;
  mCount: Integer;
begin
  if not ATable.TryGetValue(AKey, mChain) then
  begin
    Exit;
  end;
  if mChain.Count <= cShortChain then
  begin
    CompactChain(ATable, AKey);
    Exit;
  end;
  mDead := DeadOf(ATable);
  if not mDead.TryGetValue(AKey, mCount) then
  begin
    mCount := 0;
  end;
  Inc(mCount);
  if mCount * 2 >= mChain.Count then
  begin
    CompactChain(ATable, AKey);
  end
  else
  begin
    mDead.AddOrSetValue(AKey, mCount);
  end;
end;

procedure TSymbolRefTables.KillSlot(ASlot: Integer);
var
  mNodes: TArray<Integer>;
  mSymbols: TArray<TIndexSymbol>;
  mIndex, mPosition: Integer;
  mKey: string;
begin
  mNodes := FSlotNodes[ASlot];
  mSymbols := FSlotUnits[ASlot].Symbols;
  // Erst alle Knoten tot (Slot -1): Danach verweist keiner mehr auf den Platz, er ist sofort wieder frei.
  for mIndex := 0 to High(mNodes) do
  begin
    if mNodes[mIndex] >= 0 then
    begin
      FNodes[mNodes[mIndex] div cNodeChunk][mNodes[mIndex] mod cNodeChunk].Slot := -1;
      Inc(FDeadRefs);
    end;
  end;
  Dec(FLiveRefs, FSlotRefs[ASlot]);
  FSlotKeys[ASlot] := '';
  FSlotUnits[ASlot] := Default(TSlotUnit);
  FSlotNodes[ASlot] := nil;
  FSlotRefs[ASlot] := 0;
  FFreeSlots.Add(ASlot);
  // Kurze Ketten gleich aufräumen; lange (Create, Count …) erst, wenn die Hälfte tot ist, oder beim nächsten Lesen,
  // statt sie hier jedes Mal ganz zu durchlaufen. Je Knoten einmal gezählt, in derselben Reihenfolge wie Add.
  for mPosition := 0 to High(mSymbols) do
  begin
    NoteDead(FByName, mSymbols[mPosition].Name);
    for mKey in AncestorKeys(mSymbols[mPosition]) do
    begin
      NoteDead(FByAncestor, mKey);
    end;
  end;
end;

procedure TSymbolRefTables.Drop(const AKey: string);
var
  mSlot: Integer;
begin
  if not FFileSlots.TryGetValue(AKey, mSlot) then
  begin
    Exit;
  end;
  FFileSlots.Remove(AKey);
  if FSlotNodes[mSlot] <> nil then
  begin
    KillSlot(mSlot);
    Exit;
  end;
  // Ohne gemerkte Knoten: Die Verweise bleiben tot in den Ketten, bis Lesen oder Neuaufbau sie entfernen; der Platz
  // wird frei, sobald keiner mehr auf ihn verweist.
  FSlotKeys[mSlot] := '';
  FSlotUnits[mSlot] := Default(TSlotUnit);
  Dec(FLiveRefs, FSlotRefs[mSlot]);
  Inc(FDeadRefs, FSlotRefs[mSlot]);
  if FSlotRefs[mSlot] = 0 then
  begin
    FFreeSlots.Add(mSlot);
  end;
end;

procedure TSymbolRefTables.Unlink(ATable: TSymbolTable; const AKey: string; ASlot: Integer);
var
  mChain: TSymbolChain;
  mNode, mPrevious, mNext: Integer;
  mRef: TSymbolRef;
begin
  if not ATable.TryGetValue(AKey, mChain) then
  begin
    Exit;
  end;
  mPrevious := -1;
  mNode := mChain.First;
  while mNode >= 0 do
  begin
    mRef := NodeAt(mNode);
    mNext := mRef.Next;
    if mRef.Slot = ASlot then
    begin
      if mPrevious < 0 then
      begin
        mChain.First := mNext;
      end
      else
      begin
        SetNext(mPrevious, mNext);
      end;
      if mChain.Last = mNode then
      begin
        mChain.Last := mPrevious;
      end;
      Dec(mChain.Count);
      FreeNode(mNode);
    end
    else
    begin
      mPrevious := mNode;
    end;
    mNode := mNext;
  end;
  StoreChain(ATable, AKey, mChain);
end;

procedure TSymbolRefTables.Remove(const AKey: string; const ASymbols: TArray<TIndexSymbol>);
var
  mSlot, mPosition: Integer;
  mNames, mAncestors: TDictionary<string, Boolean>;
  mKey: string;
begin
  if not FFileSlots.TryGetValue(AKey, mSlot) then
  begin
    Exit;
  end;
  FFileSlots.Remove(AKey);
  // Phase 4: Mit gemerkten Knoten ohne Durchlauf der Ketten.
  if FSlotNodes[mSlot] <> nil then
  begin
    KillSlot(mSlot);
    Exit;
  end;
  // Sonst jeden Schlüssel der Unit einmal: seine Kette verliert alle Verweise auf diesen Platz.
  mNames := TDictionary<string, Boolean>.Create(NameComparer);
  mAncestors := TDictionary<string, Boolean>.Create(NameComparer);
  try
    for mPosition := 0 to High(ASymbols) do
    begin
      mNames.AddOrSetValue(ASymbols[mPosition].Name, True);
      for mKey in AncestorKeys(ASymbols[mPosition]) do
      begin
        mAncestors.AddOrSetValue(mKey, True);
      end;
    end;
    for mKey in mNames.Keys do
    begin
      Unlink(FByName, mKey, mSlot);
    end;
    for mKey in mAncestors.Keys do
    begin
      Unlink(FByAncestor, mKey, mSlot);
    end;
  finally
    mAncestors.Free;
    mNames.Free;
  end;
  FSlotKeys[mSlot] := '';
  FSlotUnits[mSlot] := Default(TSlotUnit);
  Dec(FLiveRefs, FSlotRefs[mSlot]);
  FSlotRefs[mSlot] := 0;
  FFreeSlots.Add(mSlot);
end;

function TSymbolRefTables.Locations(ATable: TSymbolTable; const AKey: string): TArray<TSymbolLocation>;
var
  mChain: TSymbolChain;
  mNode, mNext, mPrevious, mCount, mLastSlot: Integer;
  mRef: TSymbolRef;
  mOwner: TSlotUnit;
  mChanged: Boolean;
begin
  Result := nil;
  if not ATable.TryGetValue(AKey, mChain) then
  begin
    Exit;
  end;
  // Direkt ins Ergebnis statt über eine Liste und ToArray: jedes Symbol ist ein großer Record mit verwalteten
  // Feldern, häufige Namen (Create, Count) haben Tausende Verweise, und die Regeln fragen je Bezeichner.
  SetLength(Result, mChain.Count);
  mCount := 0;
  mLastSlot := -1;
  mOwner := Default(TSlotUnit);
  mPrevious := -1;
  mChanged := False;
  mNode := mChain.First;
  while mNode >= 0 do
  begin
    mRef := NodeAt(mNode);
    mNext := mRef.Next;
    // Tote Verweise (Phase 4: verdrängte Units in langen Ketten, ersetzte Units) beim Lesen aushängen.
    if IsDead(mRef) then
    begin
      UnlinkDead(mChain, mPrevious, mNode);
      mChanged := True;
      mNode := mNext;
      Continue;
    end;
    mPrevious := mNode;
    mNode := mNext;
    // Verweise einer Unit stehen beieinander: den Platz nur beim Wechsel lesen.
    if mRef.Slot <> mLastSlot then
    begin
      mLastSlot := mRef.Slot;
      mOwner := FSlotUnits[mRef.Slot];
    end;
    if mRef.Position > High(mOwner.Symbols) then
    begin
      Continue;
    end;
    Result[mCount].UnitName := mOwner.UnitName;
    Result[mCount].FileName := mOwner.Symbols[mRef.Position].FileName;
    if Result[mCount].FileName = '' then
    begin
      Result[mCount].FileName := mOwner.FileName;
    end;
    Result[mCount].Symbol := mOwner.Symbols[mRef.Position];
    Inc(mCount);
  end;
  if mChanged then
  begin
    StoreChain(ATable, AKey, mChain);
    DeadOf(ATable).Remove(AKey);
  end;
  SetLength(Result, mCount);
end;

function TSymbolRefTables.ByName(const AName: string): TArray<TSymbolLocation>;
begin
  Result := Locations(FByName, AName);
end;

function TSymbolRefTables.ByAncestor(const AName: string): TArray<TSymbolLocation>;
begin
  Result := Locations(FByAncestor, AName);
end;

function TSymbolRefTables.HasName(const AName: string; const AMatch: TSymbolMatch): Boolean;
var
  mChain: TSymbolChain;
  mNode, mNext, mPrevious, mLastSlot: Integer;
  mRef: TSymbolRef;
  mOwner: TSlotUnit;
  mChanged: Boolean;
begin
  Result := False;
  if not FByName.TryGetValue(AName, mChain) then
  begin
    Exit;
  end;
  mLastSlot := -1;
  mOwner := Default(TSlotUnit);
  mPrevious := -1;
  mChanged := False;
  mNode := mChain.First;
  while mNode >= 0 do
  begin
    mRef := NodeAt(mNode);
    mNext := mRef.Next;
    if IsDead(mRef) then
    begin
      UnlinkDead(mChain, mPrevious, mNode);
      mChanged := True;
      mNode := mNext;
      Continue;
    end;
    mPrevious := mNode;
    mNode := mNext;
    // Wie Locations: der Eintrag des Platzes, nicht der ganze TUnitIndex aus FFiles.
    if mRef.Slot <> mLastSlot then
    begin
      mLastSlot := mRef.Slot;
      mOwner := FSlotUnits[mRef.Slot];
    end;
    if (mRef.Position <= High(mOwner.Symbols)) and AMatch(mOwner.Symbols[mRef.Position]) then
    begin
      Result := True;
      Break;
    end;
  end;
  if mChanged then
  begin
    StoreChain(FByName, AName, mChain);
    FNameDead.Remove(AName);
  end;
end;

{ TSymbolIndex: Nachschlagetabellen und Budget }

procedure TSymbolIndex.CleanRefsLocked;
var
  mPair: TPair<string, TIndexEntry>;
begin
  if (FRefs.DeadRefs < cRebuildDeadRefs) or (FRefs.DeadRefs <= FRefs.LiveRefs) then
  begin
    Exit;
  end;
  FRefs.Clear;
  for mPair in FFiles do
  begin
    if mPair.Value.Loaded then
    begin
      FRefs.Add(mPair.Key, mPair.Value.Unit_, not mPair.Value.Pinned);
    end;
  end;
end;

function TSymbolIndex.OverBudgetLocked: Boolean;
begin
  Result := (FBudget > 0) and (FTotals.Bytes > FBudget);
end;

procedure TSymbolIndex.ShrinkUnitLocked(APass: Integer; const AKey: string);
var
  mExisting: TIndexEntry;
  mUnit: TUnitIndex;
  mPinned: Boolean;
  mSource: IIndexUnitSource;
begin
  if not FFiles.TryGetValue(AKey, mExisting) or not mExisting.Loaded then
  begin
    Exit;
  end;
  mUnit := mExisting.Unit_;
  mPinned := mExisting.Pinned;
  mSource := mExisting.Source;
  if APass = 1 then
  begin
    if Length(mUnit.Usages) > 0 then
    begin
      RemoveFileLocked(AKey);
      AddLocked(AKey, TIndexMemory.WithoutUsages(mUnit), mPinned, mSource);
    end;
  end
  else if not mUnit.Compact and ((APass = 2) or mUnit.Library_) then
  begin
    RemoveFileLocked(AKey);
    AddLocked(AKey, TIndexMemory.Compacted(TIndexMemory.WithoutUsages(mUnit)), mPinned, mSource);
  end;
end;

procedure TSymbolIndex.ShrinkLocked;
var
  mPass: Integer;
  mKey: string;
begin
  // Erst Bibliotheken kompakt halten, dann die Verwendungen der Projekt-Units auslagern (#492), dann
  // Projekt-Units kompakt halten; jeweils nur bis das Budget wieder reicht. Ohne Überschreitung nichts kopieren:
  // AddUnit ruft
  // das bei jeder Unit auf.
  if not OverBudgetLocked or (FShrinkable.Count = 0) then
  begin
    Exit;
  end;
  for mPass := 0 to 2 do
  begin
    for mKey in FShrinkable.Keys.ToArray do
    begin
      if not OverBudgetLocked then
      begin
        Exit;
      end;
      ShrinkUnitLocked(mPass, mKey);
    end;
  end;
end;

{ TSymbolIndex: Laden und Verdrängen (Phase 3) }

procedure TSymbolIndex.TouchLocked(AEntry: TIndexEntry);
var
  mShift: Integer;
  mNow: UInt64;
begin
  Inc(FClock);
  AEntry.LastUse := FClock;
  // Alterung erst beim nächsten Zugriff: je verstrichener Epoche die Hälfte.
  if AEntry.HitEpoch <> FEpoch then
  begin
    mShift := FEpoch - AEntry.HitEpoch;
    if mShift > 30 then
    begin
      mShift := 30;
    end;
    AEntry.Hits := AEntry.Hits shr mShift;
    AEntry.HitEpoch := FEpoch;
  end;
  if AEntry.Hits < MaxInt then
  begin
    Inc(AEntry.Hits);
  end;
  // Nutzungsstatistik: höchstens einmal je Sekunde und Unit, das ist etwa einmal je Anfrage (die Namensauflösung
  // fragt dieselbe Unit je Bezeichner).
  if (FUsage <> nil) and AEntry.Unit_.Library_ then
  begin
    mNow := TThread.GetTickCount64;
    if (AEntry.LastNote = 0) or (mNow - AEntry.LastNote >= 1000) then
    begin
      AEntry.LastNote := mNow;
      FUsage.Note(AEntry.Unit_.UnitName, 1);
      // Phase 4: Ist sie damit oft genutzt, zählt sie ab jetzt wie gepinnt nicht mehr gegen das Budget.
      if AEntry.Loaded and not AEntry.Pinned and not AEntry.Guarded and
        (FUsage.Score(AEntry.Unit_.UnitName) >= cHotScore) then
      begin
        SetGuardedLocked(AEntry, True);
      end;
    end;
  end;
end;

procedure TSymbolIndex.NoteLoad(AMs: Double; ABytes: Int64);
begin
  FLoadMs[FLoadMsCount mod cLoadSamples] := AMs;
  Inc(FLoadMsCount);
  if AMs > FLoadMaxMs then
  begin
    FLoadMaxMs := AMs;
  end;
  if ABytes > FLargestLoadBytes then
  begin
    FLargestLoadBytes := ABytes;
    FLargestLoadMs := AMs;
  end;
  Inc(FLoads);
  Inc(FLoadsInEpoch);
  if FLoadsInEpoch >= cAgingLoads then
  begin
    FLoadsInEpoch := 0;
    Inc(FEpoch);
  end;
end;

type
  /// <summary>Kandidat beim Verdrängen: Zähler nach Alterung und letzte Nutzung, einmal je Lauf ermittelt.</summary>
  TEvictCandidate = record
    Key: string;
    Entry: TIndexEntry;
    Hits: Integer;
    LastUse: Int64;
  end;

procedure TSymbolIndex.UnloadLocked(const AKey: string; AEntry: TIndexEntry);
begin
  Account(AEntry, -1);
  FRefs.Remove(AKey, AEntry.Unit_.Symbols);
  FTotals.Count(AEntry.Unit_, -1, AEntry.Bytes, AEntry.UsageBytes);
  ChangeUsesPins(AEntry.Unit_, -1);
  AEntry.SymbolCount := Length(AEntry.Unit_.Symbols);
  AEntry.UnavailableCount := Length(AEntry.Unit_.Unavailable);
  AEntry.UsageCount := Length(AEntry.Unit_.Usages);
  Inc(FColdSymbols, AEntry.SymbolCount);
  AEntry.Unit_ := HeaderOf(AEntry.Unit_);
  AEntry.Loaded := False;
  AEntry.Bytes := 0;
  AEntry.UsageBytes := 0;
  AEntry.Guarded := False;
  FUnavailable.Remove(AKey);
  FShrinkable.Remove(AKey);
  FUnitsSnapshot := nil;
  Inc(FEvictions);
end;

procedure TSymbolIndex.EvictLocked(AKeep: TIndexEntry);
begin
  EvictLocked(AKeep, cEvictableBudget);
end;

procedure TSymbolIndex.TrimEvictable;
begin
  FLock.Enter;
  try
    EvictLocked(nil, 0);
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.EvictLocked(AKeep: TIndexEntry; ABudget: Int64);
var
  mPair: TPair<string, TIndexEntry>;
  mCandidates: TList<TEvictCandidate>;
  mCandidate: TEvictCandidate;
begin
  // Ohne Überschreitung nichts zu tun. Die Summe aller verdrängbaren begrenzt die der nicht geschützten nach oben;
  // erst darüber lohnt das Prüfen.
  if FEvictableBytes <= ABudget then
  begin
    Exit;
  end;
  if FGuardDirty or (FGuardEpoch <> FEpoch) then
  begin
    RefreshGuardsLocked;
  end;
  if FCandidateBytes <= ABudget then
  begin
    Exit;
  end;
  Inc(FEvictionRuns);
  // Phase 4: Kandidaten einmal sammeln und sortieren, dann in einem Durchgang verdrängen (vorher je Opfer ein Lauf
  // über alle Units samt uses-Prüfung und Nutzungsstatistik).
  mCandidates := TList<TEvictCandidate>.Create;
  try
    for mPair in FFiles do
    begin
      if mPair.Value.Evictable and not mPair.Value.Guarded and (mPair.Value <> AKeep) then
      begin
        mCandidate.Key := mPair.Key;
        mCandidate.Entry := mPair.Value;
        mCandidate.Hits := mPair.Value.Hits shr Min(30, FEpoch - mPair.Value.HitEpoch);
        mCandidate.LastUse := mPair.Value.LastUse;
        mCandidates.Add(mCandidate);
      end;
    end;
    // Zuerst die am seltensten genutzte (Zähler nach Alterung), bei Gleichstand die am längsten nicht genutzte.
    mCandidates.Sort(TComparer<TEvictCandidate>.Construct(
      function(const ALeft, ARight: TEvictCandidate): Integer
      begin
        Result := CompareValue(ALeft.Hits, ARight.Hits);
        if Result = 0 then
        begin
          Result := CompareValue(ALeft.LastUse, ARight.LastUse);
        end;
      end));
    for mCandidate in mCandidates do
    begin
      if FCandidateBytes <= ABudget then
      begin
        Break;
      end;
      UnloadLocked(mCandidate.Key, mCandidate.Entry);
    end;
  finally
    mCandidates.Free;
  end;
end;

function TSymbolIndex.LoadKey(const AKey: string; out AUnit: TUnitIndex): Boolean;
var
  mAttempt: Integer;
  mRetry: Boolean;
  mCheck: IIndexStaleCheck;
  mEntry: TIndexEntry;
  mHeader: TUnitIndex;
begin
  // L2: Ist die Datei seit dem Block geändert (Quellen außerhalb der beobachteten Ordner), liest die Prüfung sie neu
  // ein; danach steht der neue Stand im Index. Eine Abfrage des Zeitstempels je Nachladen.
  mCheck := nil;
  FLock.Enter;
  try
    if (FStaleCheck <> nil) and FFiles.TryGetValue(AKey, mEntry) and not mEntry.Loaded and (mEntry.Loading = nil) then
    begin
      mCheck := FStaleCheck;
      mHeader := mEntry.Unit_;
    end;
  finally
    FLock.Leave;
  end;
  if mCheck <> nil then
  begin
    mCheck.Refresh(mHeader);
  end;
  // Höchstens drei Versuche: Ein neuer Block kommt nur nach dem Schreiben des Caches.
  mAttempt := 0;
  repeat
    Inc(mAttempt);
    Result := LoadKeyOnce(AKey, AUnit, mRetry);
  until not mRetry or (mAttempt >= 3);
end;

function TSymbolIndex.LoadKeyOnce(const AKey: string; out AUnit: TUnitIndex; out ARetry: Boolean): Boolean;
var
  mEntry: TIndexEntry;
  mSerial: Int64;
  mSource: IIndexUnitSource;
  mHeader, mFull: TUnitIndex;
  mLoaded, mSettled: Boolean;
  mWatch: TStopwatch;
  mMs: Double;
  mBytes, mUsageBytes: Int64;
  mWait, mOwn: IInterface;
begin
  AUnit := Default(TUnitIndex);
  ARetry := False;
  mSerial := 0;
  mBytes := 0;
  mUsageBytes := 0;
  // Lädt schon ein anderer Thread dieselbe Unit, auf ihn warten und sein Ergebnis übernehmen (Phase 4); vorher lasen
  // und dekodierten beide den Block.
  repeat
    mWait := nil;
    FLock.Enter;
    try
      if not FFiles.TryGetValue(AKey, mEntry) then
      begin
        Exit(False);
      end;
      if mEntry.Loaded then
      begin
        TouchLocked(mEntry);
        AUnit := mEntry.Unit_;
        Exit(True);
      end;
      if mEntry.Loading <> nil then
      begin
        mWait := mEntry.Loading;
      end
      else
      begin
        mOwn := TIndexLoadSignal.Create;
        mEntry.Loading := mOwn;
        mSerial := mEntry.Serial;
        mSource := mEntry.Source;
        mHeader := mEntry.Unit_;
      end;
    finally
      FLock.Leave;
    end;
    if mWait <> nil then
    begin
      (mWait as TIndexLoadSignal).WaitFor;
    end;
  until mWait = nil;
  mSettled := False;
  try
    // Block lesen und dekodieren ohne die Sperre: Andere Anfragen warten nicht auf große Units.
    mWatch := TStopwatch.StartNew;
    // Verwendungen nur, wenn die Unit sie führt (Phase 4: sonst überlesen statt dekodiert und verworfen).
    mLoaded := TIndexCache.LoadFrom(mSource, mFull, mHeader.UsagesIndexed);
    mMs := mWatch.Elapsed.TotalMilliseconds;
    if mLoaded then
    begin
      // Stand, Art und Defines des Eintrags gelten (der Block trägt den Stand beim Schreiben).
      mFull.FileName := mHeader.FileName;
      mFull.Stamp := mHeader.Stamp;
      mFull.Library_ := mHeader.Library_;
      mFull.DefinesKey := mHeader.DefinesKey;
      if not mHeader.UsagesIndexed then
      begin
        mFull.Usages := nil;
        mFull.UsagesIndexed := False;
        mFull.UsagesOffloaded := False;
      end;
      // Größen vor der Sperre und nur einmal (Phase 4).
      mBytes := TIndexMemory.UnitBytes(mFull);
      mUsageBytes := TIndexMemory.UsageBytes(mFull);
    end;
    FLock.Enter;
    try
      mSettled := True;
      if FFiles.TryGetValue(AKey, mEntry) and (mEntry.Loading = mOwn) then
      begin
        mEntry.Loading := nil;
      end;
      if not FFiles.TryGetValue(AKey, mEntry) or (mEntry.Serial <> mSerial) then
      begin
        // Inzwischen ersetzt: der neue Stand gilt (falls geladen).
        Result := (mEntry <> nil) and mEntry.Loaded;
        if Result then
        begin
          AUnit := mEntry.Unit_;
        end;
        Exit;
      end;
      if mEntry.Loaded then
      begin
        TouchLocked(mEntry);
        AUnit := mEntry.Unit_;
        Exit(True);
      end;
      if not mLoaded and (mEntry.Source <> mSource) then
      begin
        // Inzwischen an die neue Datei gebunden (Phase 5): Der alte Block war während des Schreibens nicht lesbar, der
        // neue gilt. Nicht aus dem Index nehmen, sondern noch einmal laden.
        ARetry := True;
        Exit(False);
      end;
      if not mLoaded then
      begin
        // Block fehlt oder ist beschädigt: Die Unit fällt aus dem Index; EnsureUnit liest sie aus der Datei neu.
        RemoveFileLocked(AKey);
        Exit(False);
      end;
      Dec(FColdSymbols, mEntry.SymbolCount);
      mEntry.Unit_ := mFull;
      InstallLocked(AKey, mEntry, mBytes, mUsageBytes);
      NoteLoad(mMs, mBytes);
      TouchLocked(mEntry);
      EvictLocked(mEntry);
      AUnit := mEntry.Unit_;
      Result := True;
    finally
      FLock.Leave;
    end;
  finally
    if not mSettled then
    begin
      // Ausnahme beim Lesen: Ohne das hier warteten spätere Leser für immer auf diesen Ladevorgang.
      FLock.Enter;
      try
        if FFiles.TryGetValue(AKey, mEntry) and (mEntry.Loading = mOwn) then
        begin
          mEntry.Loading := nil;
        end;
      finally
        FLock.Leave;
      end;
    end;
    (mOwn as TIndexLoadSignal).Signal;
  end;
end;

type
  /// <summary>Katalogsymbole eines Eintrags für das Namensverzeichnis (referenzgezählt, ohne Kopie der Symbole).
  /// </summary>
  TCatalogNames = record
    Key: string;
    Symbols: TArray<TCatalogSymbol>;
  end;

procedure TSymbolIndex.NameLookup(out AHashes: TArray<UInt64>; out AKeys: TArray<string>; out AMembership: Int64);
var
  mPair: TPair<string, TIndexEntry>;
  mUnits: TArray<TCatalogNames>;
  mMembership: Int64;
  mCount, mUnit, mIndex, mAt: Integer;
begin
  FLock.Enter;
  try
    if FNameBuiltFor = FNameMembership then
    begin
      AHashes := FNameHashes;
      AKeys := FNameKeys;
      AMembership := FNameBuiltFor;
      Exit;
    end;
    // Nur verdrängbare Units (nicht gepinnt, mit Block): Gepinnte sind immer geladen. Unter der Sperre nur die
    // Verweise auf die Kataloge sammeln (Phase 4).
    mMembership := FNameMembership;
    AMembership := mMembership;
    SetLength(mUnits, FFiles.Count);
    mCount := 0;
    for mPair in FFiles do
    begin
      if NameRelevant(mPair.Value) then
      begin
        mUnits[mCount].Key := mPair.Key;
        mUnits[mCount].Symbols := mPair.Value.Catalog.Symbols;
        Inc(mCount);
      end;
    end;
  finally
    FLock.Leave;
  end;
  // Hashen und Sortieren außerhalb der Sperre: Hash (obere 32 Bit) und Nummer des Eintrags (untere).
  mAt := 0;
  for mUnit := 0 to mCount - 1 do
  begin
    Inc(mAt, Length(mUnits[mUnit].Symbols));
  end;
  SetLength(AHashes, mAt);
  SetLength(AKeys, mCount);
  mAt := 0;
  for mUnit := 0 to mCount - 1 do
  begin
    AKeys[mUnit] := mUnits[mUnit].Key;
    for mIndex := 0 to High(mUnits[mUnit].Symbols) do
    begin
      AHashes[mAt] := (UInt64(Cardinal(NameHash(mUnits[mUnit].Symbols[mIndex].Name))) shl 32) or UInt64(mUnit);
      Inc(mAt);
    end;
  end;
  mUnits := nil;
  TArray.Sort<UInt64>(AHashes);
  FLock.Enter;
  try
    Inc(FNameBuilds);
    // Hat sich die Mitgliedschaft inzwischen wieder geändert, gilt das Ergebnis nur für diesen Aufruf.
    if FNameMembership = mMembership then
    begin
      FNameHashes := AHashes;
      FNameKeys := AKeys;
      FNameBuiltFor := mMembership;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.ColdCandidates(const AName: string; out ACandidates: TArray<string>;
  out AMembership: Int64);
var
  mHashes: TArray<UInt64>;
  mNameKeys: TArray<string>;
  mHash: UInt64;
  mLow, mHigh, mMiddle, mPosition: Integer;
  mKey: string;
begin
  ACandidates := nil;
  NameLookup(mHashes, mNameKeys, AMembership);
  if Length(mHashes) = 0 then
  begin
    Exit;
  end;
  // Erster Eintrag mit diesem Hash (obere 32 Bit), dann alle gleichen; ohne Sperre auf dem eigenen Stand.
  mHash := UInt64(Cardinal(NameHash(AName))) shl 32;
  mLow := 0;
  mHigh := Length(mHashes);
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) shr 1;
    if mHashes[mMiddle] < mHash then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  mPosition := mLow;
  while (mPosition < Length(mHashes)) and ((mHashes[mPosition] shr 32) = (mHash shr 32)) do
  begin
    mKey := mNameKeys[Integer(mHashes[mPosition] and $FFFFFFFF)];
    if IndexText(mKey, ACandidates) < 0 then
    begin
      ACandidates := ACandidates + [mKey];
    end;
    Inc(mPosition);
  end;
end;

function TSymbolIndex.ColdKeysLocked(const AName: string; const ACandidates: TArray<string>): TArray<string>;
var
  mKey: string;
  mEntry: TIndexEntry;
  mSymbol: Integer;
begin
  Result := nil;
  for mKey in ACandidates do
  begin
    if not FFiles.TryGetValue(mKey, mEntry) or mEntry.Loaded then
    begin
      Continue;
    end;
    // Gleicher Hash heißt nicht gleicher Name.
    for mSymbol := 0 to High(mEntry.Catalog.Symbols) do
    begin
      if SameText(mEntry.Catalog.Symbols[mSymbol].Name, AName) then
      begin
        Result := Result + [mKey];
        Break;
      end;
    end;
  end;
end;

function TSymbolIndex.SnapshotNamed(const AName: string; const ARead: TProc): TArray<string>;
var
  mCandidates: TArray<string>;
  mMembership: Int64;
  mTry: Integer;
  mDone: Boolean;
begin
  Result := nil;
  mTry := 0;
  repeat
    Inc(mTry);
    ColdCandidates(AName, mCandidates, mMembership);
    FLock.Enter;
    try
      // Kam inzwischen eine kalte Unit hinzu, kennt das Namensverzeichnis sie nicht: noch einmal (höchstens dreimal).
      mDone := (mMembership = FNameMembership) or (mTry >= 3);
      if mDone then
      begin
        // Unter derselben Sperre: Jede Unit ist jetzt entweder geladen (ARead) oder kalt (Ergebnis).
        ARead();
        Result := ColdKeysLocked(AName, mCandidates);
      end;
    finally
      FLock.Leave;
    end;
  until mDone;
end;

/// <summary>Symbole AName der geladenen Unit AUnit wie TSymbolRefTables.Locations (Phase 5).</summary>
function NamedIn(const AUnit: TUnitIndex; const AName: string): TArray<TSymbolLocation>;
var
  mPosition, mCount: Integer;
begin
  Result := nil;
  mCount := 0;
  // Über den Index: die Symbol-Records nicht kopieren.
  for mPosition := 0 to High(AUnit.Symbols) do
  begin
    if CompareText(AUnit.Symbols[mPosition].Name, AName) = 0 then
    begin
      SetLength(Result, mCount + 1);
      Result[mCount].UnitName := AUnit.UnitName;
      Result[mCount].FileName := AUnit.Symbols[mPosition].FileName;
      if Result[mCount].FileName = '' then
      begin
        Result[mCount].FileName := AUnit.FileName;
      end;
      Result[mCount].Symbol := AUnit.Symbols[mPosition];
      Inc(mCount);
    end;
  end;
end;

/// <summary>Hat die geladene Unit AUnit ein Symbol AName, auf das AMatch passt (Phase 5)?</summary>
function HasNamedIn(const AUnit: TUnitIndex; const AName: string; const AMatch: TSymbolMatch): Boolean;
var
  mPosition: Integer;
begin
  for mPosition := 0 to High(AUnit.Symbols) do
  begin
    if (CompareText(AUnit.Symbols[mPosition].Name, AName) = 0) and AMatch(AUnit.Symbols[mPosition]) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TSymbolIndex.NoteAddedUsesLocked(const AOld, ANew: TUnitIndex);
var
  mName, mKey: string;
  mEntry: TIndexEntry;
begin
  for mName in ANew.InterfaceUses + ANew.ImplementationUses do
  begin
    if (IndexText(mName, AOld.InterfaceUses) >= 0) or (IndexText(mName, AOld.ImplementationUses) >= 0) then
    begin
      Continue;
    end;
    // Unter dem Namen der Unit zählen, wenn der Index sie kennt (auch über einen Alias).
    mKey := UnitKeyLocked(mName);
    if (mKey <> '') and FFiles.TryGetValue(mKey, mEntry) then
    begin
      FUsage.Note(mEntry.Unit_.UnitName, 4);
    end
    else
    begin
      FUsage.Note(mName, 4);
    end;
  end;
end;

procedure TSymbolIndex.AddUnit(const AUnit: TUnitIndex);
var
  mKey: string;
  mPooled: TUnitIndex;
  mOld: TIndexEntry;
  mCatalog: TCatalogUnit;
  mBytes, mUsageBytes: Int64;
begin
  mKey := AnsiUpperCase(AUnit.FileName);
  mPooled := AUnit;
  // Eigene Kopie der Arrays, damit der Pool die Einträge des Aufrufers nicht ändert. Kopieren und Einordnen
  // in den Pool außerhalb von FLock: Leser warten sonst auf jede große Unit. Zwei
  // gleichzeitige Aufrufe für dieselbe Datei können sich dadurch überholen; das Ergebnis ist dann wie bei
  // umgekehrter Aufrufreihenfolge. Der Index-Builder liest jede Datei nur aus einem Thread.
  mPooled.InterfaceUses := Copy(AUnit.InterfaceUses);
  mPooled.ImplementationUses := Copy(AUnit.ImplementationUses);
  mPooled.Symbols := Copy(AUnit.Symbols);
  FPoolLock.Enter;
  try
    FPool.InternUnit(mPooled);
  finally
    FPoolLock.Leave;
  end;
  // Katalog und Größen ebenfalls vor der Sperre und nur einmal (Phase 4).
  mCatalog := TCatalogUnit.FromUnit(mPooled);
  mBytes := TIndexMemory.UnitBytes(mPooled);
  mUsageBytes := TIndexMemory.UsageBytes(mPooled);
  FLock.Enter;
  try
    // Eine Projekt-Unit ändert sich (Tippen, Speichern): neue uses zählen in der Nutzungsstatistik (Phase 3).
    if (FUsage <> nil) and not mPooled.Library_ and FFiles.TryGetValue(mKey, mOld) and mOld.Loaded then
    begin
      NoteAddedUsesLocked(mOld.Unit_, mPooled);
    end;
    // Die uses der neuen Fassung zählen schon, bevor die alte herausfällt: Namen in beiden Fassungen fallen so nicht
    // kurz aus den uses, und der Schutz ihrer Units muss nicht neu geprüft werden (Tippen, Phase 4).
    ChangeUsesPins(mPooled, 1);
    try
      RemoveFileLocked(mKey);
      AddPreparedLocked(mKey, mPooled, mCatalog, mBytes, mUsageBytes, True, nil);
    finally
      ChangeUsesPins(mPooled, -1);
    end;
    ShrinkLocked;
    CleanRefsLocked;
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.AddEvictable(const AUnit: TUnitIndex; const ASource: IIndexUnitSource);
var
  mKey: string;
  mPooled: TUnitIndex;
  mCatalog: TCatalogUnit;
  mBytes, mUsageBytes: Int64;
begin
  mKey := AnsiUpperCase(AUnit.FileName);
  mPooled := AUnit;
  mPooled.InterfaceUses := Copy(AUnit.InterfaceUses);
  mPooled.ImplementationUses := Copy(AUnit.ImplementationUses);
  mPooled.Symbols := Copy(AUnit.Symbols);
  FPoolLock.Enter;
  try
    FPool.InternUnit(mPooled);
  finally
    FPoolLock.Leave;
  end;
  mCatalog := TCatalogUnit.FromUnit(mPooled);
  mBytes := TIndexMemory.UnitBytes(mPooled);
  mUsageBytes := TIndexMemory.UsageBytes(mPooled);
  FLock.Enter;
  try
    RemoveFileLocked(mKey);
    AddPreparedLocked(mKey, mPooled, mCatalog, mBytes, mUsageBytes, False, ASource);
    EvictLocked(nil);
    CleanRefsLocked;
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.AddCold(const AHeader: TUnitIndex; const ACatalog: TCatalogUnit;
  const ASource: IIndexUnitSource; ASymbolCount, AUnavailableCount, AUsageCount: Integer);
var
  mKey: string;
  mEntry: TIndexEntry;
begin
  mKey := AnsiUpperCase(AHeader.FileName);
  FLock.Enter;
  try
    RemoveFileLocked(mKey);
    mEntry := NewEntry;
    mEntry.Unit_ := HeaderOf(AHeader);
    mEntry.Catalog := ACatalog;
    mEntry.CatalogBytes := ACatalog.Bytes;
    mEntry.Source := ASource;
    mEntry.SymbolCount := ASymbolCount;
    mEntry.UnavailableCount := AUnavailableCount;
    mEntry.UsageCount := AUsageCount;
    FFiles.Add(mKey, mEntry);
    Inc(FCatalogBytes, mEntry.CatalogBytes);
    Inc(FColdSymbols, ASymbolCount);
    FCatalogSnapshot := nil;
    Inc(FGeneration);
    if NameRelevant(mEntry) then
    begin
      Inc(FNameMembership);
    end;
    LinkUnitFileLocked(UpperCase(AHeader.UnitName), mKey, AHeader.Library_);
    LinkIncludesLocked(mKey, AHeader.Includes);
    CleanRefsLocked;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.Pin(const AFileName: string; out AWasPinned: Boolean): Boolean;
var
  mKey: string;
  mEntry: TIndexEntry;
  mUnit: TUnitIndex;
  mLoaded: Boolean;
begin
  AWasPinned := False;
  mKey := AnsiUpperCase(AFileName);
  FLock.Enter;
  try
    if not FFiles.TryGetValue(mKey, mEntry) then
    begin
      Exit(False);
    end;
    AWasPinned := mEntry.Pinned;
    // Gepinnte gehören nicht mehr ins Namensverzeichnis der kalten Units (Phase 4).
    if NameRelevant(mEntry) then
    begin
      Inc(FNameMembership);
    end;
    Account(mEntry, -1);
    mEntry.Pinned := True;
    mEntry.Guarded := False;
    Account(mEntry, 1);
    mLoaded := mEntry.Loaded;
  finally
    FLock.Leave;
  end;
  Result := mLoaded or LoadKey(mKey, mUnit);
end;

function TSymbolIndex.BindSources(const AHeaders: TArray<TUnitIndex>;
  const ASources: TArray<IIndexUnitSource>): Integer;
var
  mIndex: Integer;
  mEntry: TIndexEntry;
begin
  Result := 0;
  FLock.Enter;
  try
    for mIndex := 0 to Min(High(AHeaders), High(ASources)) do
    begin
      // Auch gepinnte: Ihr Block dient dem nächsten Cache als Kopie (verdrängt werden sie trotzdem nie).
      if (ASources[mIndex] = nil) or not FFiles.TryGetValue(AnsiUpperCase(AHeaders[mIndex].FileName), mEntry) or
        (mEntry.Unit_.Hash <> AHeaders[mIndex].Hash) or (mEntry.Unit_.Stamp <> AHeaders[mIndex].Stamp) then
      begin
        Continue;
      end;
      Account(mEntry, -1);
      // Eine nicht gepinnte Unit bekommt ihren ersten Block: Ab jetzt gehört sie ins Namensverzeichnis der kalten
      // Units (Phase 4; vorher fehlte sie dort, war sie einmal verdrängt).
      if (mEntry.Source = nil) and not mEntry.Pinned then
      begin
        Inc(FNameMembership);
      end;
      mEntry.Source := ASources[mIndex];
      Account(mEntry, 1);
      Inc(Result);
    end;
    // Ohne Block blieben im Bibliotheksstufen-Aufbau ohne Cache alle Units geladen; jetzt dürfen sie gehen.
    EvictLocked(nil);
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.RemoveFile(const AFileName: string);
begin
  FLock.Enter;
  try
    RemoveFileLocked(AnsiUpperCase(AFileName));
    CleanRefsLocked;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.UnitKeyLocked(const AUnitName: string): string;
var
  mTarget: string;
  mFiles: TArray<string>;
begin
  // L2: Mehrere Dateien gleichen Namens: die beste (Rang, dann Reihenfolge).
  if FUnitFiles.TryGetValue(UpperCase(AUnitName), mFiles) then
  begin
    Exit(mFiles[0]);
  end;
  // Wie dcc: uses WinTypes lädt Winapi.Windows. Eine Unit, die selbst so heißt, geht vor.
  Result := '';
  if TUnitAliases.Target(FAliases, AUnitName, mTarget) and FUnitFiles.TryGetValue(UpperCase(mTarget), mFiles) then
  begin
    Result := mFiles[0];
  end;
end;

function TSymbolIndex.UnitFiles(const AUnitName: string): TArray<string>;
begin
  FLock.Enter;
  try
    if FUnitFiles.TryGetValue(UpperCase(AUnitName), Result) then
    begin
      // Kopie: Das Array im Index ändert sich mit jedem Eintragen.
      Result := Copy(Result);
    end
    else
    begin
      Result := nil;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.SetUnitScopes(const AScopes: IIndexUnitScopes);
begin
  FLock.Enter;
  try
    FUnitScopes := AScopes;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.UnitScopes: IIndexUnitScopes;
begin
  FLock.Enter;
  try
    Result := FUnitScopes;
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.SetStaleCheck(const ACheck: IIndexStaleCheck);
begin
  FLock.Enter;
  try
    FStaleCheck := ACheck;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.StaleCheck: IIndexStaleCheck;
begin
  FLock.Enter;
  try
    Result := FStaleCheck;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.FindUnit(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
var
  mKey: string;
  mEntry: TIndexEntry;
  mCold: Boolean;
begin
  mCold := False;
  FLock.Enter;
  try
    mKey := UnitKeyLocked(AUnitName);
    Result := (mKey <> '') and FFiles.TryGetValue(mKey, mEntry);
    if Result then
    begin
      if mEntry.Loaded then
      begin
        TouchLocked(mEntry);
        AUnit := mEntry.Unit_;
      end
      else
      begin
        mCold := True;
      end;
    end;
  finally
    FLock.Leave;
  end;
  if mCold then
  begin
    Result := LoadKey(mKey, AUnit);
  end;
end;

function TSymbolIndex.FindUnitHeader(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
var
  mKey: string;
  mEntry: TIndexEntry;
begin
  FLock.Enter;
  try
    mKey := UnitKeyLocked(AUnitName);
    Result := (mKey <> '') and FFiles.TryGetValue(mKey, mEntry);
    if Result then
    begin
      AUnit := mEntry.Unit_;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.AddUnitAliases(const AAliases: TArray<TPair<string, string>>);
begin
  FLock.Enter;
  try
    // Die neuen zuerst: Ein Projekt kann einen Alias der Vorgaben anders belegen.
    FAliases := TUnitAliases.Merge(AAliases, FAliases);
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.FindFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
var
  mKey: string;
  mEntry: TIndexEntry;
  mCold: Boolean;
begin
  mKey := AnsiUpperCase(AFileName);
  mCold := False;
  FLock.Enter;
  try
    Result := FFiles.TryGetValue(mKey, mEntry);
    if Result then
    begin
      if mEntry.Loaded then
      begin
        TouchLocked(mEntry);
        AUnit := mEntry.Unit_;
      end
      else
      begin
        mCold := True;
      end;
    end;
  finally
    FLock.Leave;
  end;
  if mCold then
  begin
    Result := LoadKey(mKey, AUnit);
  end;
end;

function TSymbolIndex.FindHeader(const AFileName: string; out AUnit: TUnitIndex): Boolean;
var
  mEntry: TIndexEntry;
begin
  FLock.Enter;
  try
    Result := FFiles.TryGetValue(AnsiUpperCase(AFileName), mEntry);
    if Result then
    begin
      AUnit := mEntry.Unit_;
    end;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.FindSymbols(const AName: string): TArray<TSymbolLocation>;
var
  mFound: TArray<TSymbolLocation>;
  mKeys: TArray<string>;
  mKey: string;
  mUnit: TUnitIndex;
begin
  // Verweise der geladenen Units und die kalten Units mit diesem Namen oberster Ebene (Katalog) im selben Augenblick
  // (Phase 5).
  mKeys := SnapshotNamed(AName,
    procedure
    begin
      mFound := FRefs.ByName(AName);
    end);
  // Die kalten einzeln laden und ihre Symbole gleich übernehmen: Das Verdrängen läuft weiter (auch die eben geladene
  // darf wieder gehen), die Antwort bleibt vollständig, und nie liegen alle Units eines häufigen Namens zugleich im
  // Speicher.
  for mKey in mKeys do
  begin
    if LoadKey(mKey, mUnit) then
    begin
      mFound := mFound + NamedIn(mUnit, AName);
    end;
    mUnit := Default(TUnitIndex);
  end;
  Result := mFound;
end;

function TSymbolIndex.HasSymbol(const AName: string; const AMatch: TSymbolMatch): Boolean;
var
  mHas: Boolean;
  mKeys: TArray<string>;
  mKey: string;
  mUnit: TUnitIndex;
begin
  mHas := False;
  mKeys := SnapshotNamed(AName,
    procedure
    begin
      mHas := FRefs.HasName(AName, AMatch);
    end);
  if mHas then
  begin
    Exit(True);
  end;
  // Kalte Units nur, solange nichts gefunden ist (Phase 5).
  for mKey in mKeys do
  begin
    if LoadKey(mKey, mUnit) and HasNamedIn(mUnit, AName, AMatch) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TSymbolIndex.Descendants(const ATypeName: string): TArray<TSymbolLocation>;
var
  mKey: string;
begin
  mKey := LastPart(ATypeName);
  if mKey = '' then
  begin
    Exit(nil);
  end;
  // Nur geladene Units: Der Katalog kennt die Vorfahren der Mitglieder verdrängter Units nicht (Phase 3).
  FLock.Enter;
  try
    Result := FRefs.ByAncestor(mKey);
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.Units: TArray<TUnitIndex>;
var
  mList: TList<TUnitIndex>;
  mEntry: TIndexEntry;
begin
  FLock.Enter;
  try
    // Schnappschuss der geladenen Units bis zur nächsten Änderung; dynamische Arrays sind referenzgezählt.
    if FUnitsSnapshot = nil then
    begin
      mList := TList<TUnitIndex>.Create;
      try
        mList.Capacity := FFiles.Count;
        for mEntry in FFiles.Values do
        begin
          if mEntry.Loaded then
          begin
            mList.Add(mEntry.Unit_);
          end;
        end;
        FUnitsSnapshot := mList.ToArray;
      finally
        mList.Free;
      end;
    end;
    Result := FUnitsSnapshot;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.CatalogUnits: TArray<TCatalogUnit>;
var
  mEntry: TIndexEntry;
  mIndex: Integer;
begin
  FLock.Enter;
  try
    if (FCatalogSnapshot = nil) and (FFiles.Count > 0) then
    begin
      SetLength(FCatalogSnapshot, FFiles.Count);
      mIndex := 0;
      for mEntry in FFiles.Values do
      begin
        FCatalogSnapshot[mIndex] := mEntry.Catalog;
        Inc(mIndex);
      end;
    end;
    Result := FCatalogSnapshot;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.StoredUnits: TArray<TIndexStoredUnit>;
var
  mEntry: TIndexEntry;
  mIndex: Integer;
begin
  FLock.Enter;
  try
    SetLength(Result, FFiles.Count);
    mIndex := 0;
    for mEntry in FFiles.Values do
    begin
      Result[mIndex].Unit_ := mEntry.Unit_;
      Result[mIndex].Catalog := mEntry.Catalog;
      Result[mIndex].Source := mEntry.Source;
      Result[mIndex].Loaded := mEntry.Loaded;
      Result[mIndex].Pinned := mEntry.Pinned;
      Result[mIndex].SymbolCount := mEntry.SymbolCount;
      Result[mIndex].UnavailableCount := mEntry.UnavailableCount;
      Result[mIndex].UsageCount := mEntry.UsageCount;
      Inc(mIndex);
    end;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.UnavailableUnits: TArray<TUnitIndex>;
var
  mKey: string;
  mFound: TList<TUnitIndex>;
  mEntry: TIndexEntry;
begin
  mFound := TList<TUnitIndex>.Create;
  try
    FLock.Enter;
    try
      for mKey in FUnavailable.Keys do
      begin
        if FFiles.TryGetValue(mKey, mEntry) and mEntry.Loaded then
        begin
          mFound.Add(mEntry.Unit_);
        end;
      end;
    finally
      FLock.Leave;
    end;
    Result := mFound.ToArray;
  finally
    mFound.Free;
  end;
end;

function TSymbolIndex.Generation: Int64;
begin
  FLock.Enter;
  try
    Result := FGeneration;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.UnitCount: Integer;
begin
  FLock.Enter;
  try
    Result := FFiles.Count;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.MemoryBytes: Int64;
begin
  FLock.Enter;
  try
    // Geladene Units und der Katalog aller Units (Phase 3).
    Result := FTotals.Bytes + FCatalogBytes;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.MemoryParts: TIndexMemoryParts;
begin
  FLock.Enter;
  try
    Result.UsageBytes := FTotals.UsageBytes;
    // Der Katalog zählt zur Bibliothek (fast alle seine Units sind Bibliotheks-Units).
    Result.LibraryBytes := FTotals.LibraryBytes + FCatalogBytes;
    Result.ProjectBytes := FTotals.Bytes - FTotals.UsageBytes - FTotals.LibraryBytes;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.CompactCount: Integer;
begin
  FLock.Enter;
  try
    Result := FTotals.CompactCount;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.OffloadedCount: Integer;
begin
  FLock.Enter;
  try
    Result := FTotals.OffloadedCount;
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.SetBudget(ABytes: Int64);
begin
  FLock.Enter;
  try
    FBudget := ABytes;
    ShrinkLocked;
    CleanRefsLocked;
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.ReleaseStringPool;
begin
  FPoolLock.Enter;
  try
    FPool.Free;
    FPool := TStringPool.Create;
  finally
    FPoolLock.Leave;
  end;
end;

function TSymbolIndex.Budget: Int64;
begin
  FLock.Enter;
  try
    Result := FBudget;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.SymbolCount: Integer;
begin
  FLock.Enter;
  try
    // Auch die Symbole verdrängter Units (Zahl aus dem Verzeichnis des Caches).
    Result := FTotals.SymbolCount + FColdSymbols;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.LazyStats: TIndexLazyStats;
var
  mEntry: TIndexEntry;
  mSamples: TArray<Double>;
  mCount: Integer;
begin
  Result := Default(TIndexLazyStats);
  FLock.Enter;
  try
    Result.CatalogUnits := FFiles.Count;
    Result.CatalogBytes := FCatalogBytes;
    // Geschützte (uses einer Projekt-Unit, oft genutzt) zählen wie gepinnte (Phase 4).
    if FGuardDirty then
    begin
      RefreshGuardsLocked;
    end;
    for mEntry in FFiles.Values do
    begin
      if not mEntry.Loaded then
      begin
        Inc(Result.Cold);
        Continue;
      end;
      Inc(Result.Loaded);
      if mEntry.Pinned or (mEntry.Source = nil) or mEntry.Guarded then
      begin
        Inc(Result.Pinned);
      end
      else
      begin
        Inc(Result.Evictable);
      end;
    end;
    Result.EvictableBytes := FCandidateBytes;
    Result.Loads := FLoads;
    Result.Evictions := FEvictions;
    Result.LoadMaxMs := FLoadMaxMs;
    Result.LargestLoadBytes := FLargestLoadBytes;
    Result.LargestLoadMs := FLargestLoadMs;
    mCount := Min(FLoadMsCount, cLoadSamples);
    mSamples := Copy(FLoadMs, 0, mCount);
  finally
    FLock.Leave;
  end;
  if Length(mSamples) > 0 then
  begin
    TArray.Sort<Double>(mSamples);
    Result.LoadMedianMs := mSamples[Length(mSamples) div 2];
  end;
end;

procedure TSymbolIndex.SetUsage(const AUsage: IIndexUsage);
begin
  FLock.Enter;
  try
    FUsage := AUsage;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.Usage: IIndexUsage;
begin
  FLock.Enter;
  try
    Result := FUsage;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.NameLookupBuilds: Integer;
begin
  FLock.Enter;
  try
    Result := FNameBuilds;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.EvictionRuns: Integer;
begin
  FLock.Enter;
  try
    Result := FEvictionRuns;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.GuardRefreshes: Integer;
begin
  FLock.Enter;
  try
    Result := FGuardRefreshes;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.RefSlots: Integer;
begin
  FLock.Enter;
  try
    Result := FRefs.SlotCount;
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.RefNodes: Integer;
begin
  FLock.Enter;
  try
    Result := FRefs.NodeCount;
  finally
    FLock.Leave;
  end;
end;

end.
