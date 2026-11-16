unit dpcc.Common.Index.Service;

// Hält den Symbolindex und baut ihn in einem Hintergrund-Thread auf:
// Cache laden, Projektdateien und referenzierte Units indizieren, Cache
// schreiben. Ein neuer Start (z. B. nach geänderter Konfiguration) bricht
// den laufenden Aufbau ab, wartet aber nicht auf ihn (#874): Das tut der neue
// Index-Thread, bevor er beginnt. So hält Start die Nachrichtenschleife des
// Servers nicht auf, und zwei Aufbauten laufen trotzdem nie gleichzeitig.
// Stop bricht ab und wartet.
//
// Schreibt eine andere Instanz den Cache gerade (#62), wartet der Aufbau
// begrenzt, bis sie fertig ist oder die Sperre freigibt, und lädt dann ihren
// Stand, statt alles selbst noch einmal zu lesen.
//
// Ein Schreiber je Cache: Den Projekt-Cache schreibt nur, wer
// seine Sperre hält (sonst ReadOnlyCache). Den gemeinsamen Bibliotheks-Cache
// teilen alle Projekte und Prozesse; wer ihm Units hinzufügt, sperrt ihn mit
// TryLockWrite, liest unter der Sperre den aktuellen Stand neu und ergänzt
// ihn. Vorher schrieben mehrere gleichzeitig und überschrieben gegenseitig
// ihre Ergänzungen. Was nicht geschrieben werden konnte, meldet
// OnCacheNotWritten.
//
// EnsureUnit parst ohne globale Sperre (#617): Die Sperre schützt nur den
// Zugriff auf den Builder und zählt seine Nutzer. Ein neuer Aufbau gibt den
// alten Builder erst frei, wenn ihn niemand mehr nutzt. So warten Hover und
// Vervollständigung nicht hintereinander auf das Parsen anderer Anfragen.
//
// Ein beschädigter Cache (falsche Prüfsumme, abgeschnitten, andere
// Formatversion, #492) wird nur über OnCacheRejected gemeldet; der Aufbau
// liest dann alles neu und schreibt den Cache wieder, ohne Meldung an den
// Benutzer. UsagesOf liefert die Verwendungen einer Unit auch dann, wenn sie
// wegen des Speicherbudgets ausgelagert sind: aus dem Cache, sonst aus der
// Datei.
//
// Stufen (#648): Projektdateien, dann alle Units der Suchpfade, dann die
// Bibliothek. Mit einem gemeinsamen TIndexScheduler laufen die Aufbauten
// mehrerer Projekte nacheinander und stufenweise.
//
// Speicher (Rückmeldung 15.10.2026, 1,5 GB bei sechs Projekten): Den
// gemeinsamen Bibliotheks-Cache lesen alle Dienste eines Prozesses nur einmal
// (TSharedCacheReads), und nach einem vollständigen Aufbau gibt der Builder
// seine Cache-Einträge frei. Vorher hielt jedes Projekt seinen Projekt- und
// eine eigene Kopie des Bibliotheks-Caches bis zum nächsten Aufbau.
//
// Speicher (Rückmeldung 22.10.2026, 3 GB im Task-Manager bei acht Projekten): Die Aufbauten einer
// Projektgruppe enden fast gleichzeitig. Jeder verglich die Bibliothek mit seinem eigenen, beim Start
// gelesenen Stand, fand die Units der anderen als neu und schrieb den ganzen gemeinsamen Cache, nach der
// Projektstufe und am Ende: bis zu 16 vollständige Serialisierungen je Start, mehrere gleichzeitig. Jetzt
// schreibt im Prozess immer nur ein Dienst (TSharedCacheWrites), und der Stand der zuletzt geschriebenen
// Bibliotheks-Datei ist bekannt: Wer nichts Neues hat, schreibt nicht. Ist der Stand unbekannt (Datei von
// einem anderen Prozess geschrieben), gilt der Weg über die Dateisperre oben.
//
// Speicher-Optimierung Phase 3: Die Caches haben Format 34 (Blöcke je Unit, Verzeichnis am Ende). Lesen öffnet die
// Datei über IIndexFileSystem.OpenBlocks und liest nur Kopf und Verzeichnis; Schreiben geht über WriteStream Block
// für Block. Units, deren Symbole nicht im Speicher sind (bedarfsweises Laden, TIndexRequest.LazyLibrary), schreibt es
// als unveränderten Block aus dem alten Cache, ebenso die Units anderer Projekte im gemeinsamen Cache. Nach dem
// Schreiben (und nach dem Lesen eines gemeinsamen Caches) bekommen die verdrängbaren Units des Index die Blöcke der
// neuen Datei (ISymbolIndex.BindSources); erst dann darf der Index sie verdrängen.
//
// Nutzungsstatistik (Speicher-Optimierung Phase 3): TIndexUsageStats zählt je Bibliotheks-Unit, wie oft Anfragen sie
// brauchen (FindUnit höchstens einmal je Sekunde, etwa einmal je Anfrage) und wie oft eine Projekt-Unit sie neu in die
// uses aufnimmt (angenommenes "+ Unit", 4 Punkte). Die Punkte halbieren sich je Woche. Ab cIndexHotScore Punkten lädt
// der Aufbau die Unit gleich und der Index verdrängt sie nie. Die Statistik steht in usage.dat neben dem
// Bibliotheks-Cache; geschrieben wird beim Stopp des Dienstes und höchstens alle 10 Minuten bei Anfragen, ihr Verlust
// ist unkritisch.
//
// Speicher (Speicher-Optimierung b1): Jeder Aufbau las den gemeinsamen Bibliotheks-Cache ganz (84 MB am Stück) und
// dekodierte alle Texte, auch wenn der Index jede Unit daraus schon im selben Stand hielt; das gab bei jedem
// Neuaufbau (Einstellungen, .dproj gespeichert, Konfiguration) eine Spitze. TSharedCacheWrites kennt nun auch den
// gelesenen Stand einer Datei (Zeitstempel, Stand je Unit). Hält der Index jede Unit des Auftrags aus diesem Stand
// unverändert und würde der Builder sie behalten (TIndexBuilder.Keeps), liest der Aufbau den Bibliotheks- bzw.
// Suchpfad-Cache nicht noch einmal (OnCacheSkipped).
//
// Speicher-Optimierung Phase 4:
// - Beim ersten Aufbau (LazyLibrary ohne Cache) schreibt OnLibraryFlush nur noch den Bibliotheks-Cache, und zwar durch
//   Anhängen an die eigene, unveränderte Datei (IIndexFileAppend, TIndexCache.Append): Blöcke, die schon darin stehen,
//   bleiben. Vorher schrieb jeder Zwischenstand den ganzen Bibliotheks-Cache neu (alle früheren Blöcke kopiert) und dazu
//   den Projekt-Cache. Das letzte Schreiben am Ende schreibt die Datei wieder ganz (ohne die alten Verzeichnisse).
// - Nach dem Schreiben bekommen die Units ihre Blöcke aus der Lage, die TIndexCache.Write meldet, statt das eben
//   geschriebene Verzeichnis neu zu lesen; TSharedCacheWrites merkt sie sich für Dienste, die nichts zu schreiben haben.
// - Die Nutzungsstatistik prüft ihre Fälligkeit ohne Sperre und schreibt im Hintergrund (eigener Thread), nicht im
//   Thread der Anfrage.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  dpcc.Common.Index.Contract,
  dpcc.Common.Index.Cache,
  dpcc.Common.Index.Builder,
  dpcc.Common.Index.Scheduler;

type
  TIndexRequest = record
    /// <summary>Projektdateien in Reihenfolge (Hauptdatei, Units).</summary>
    Files: TArray<string>;
    /// <summary>Alle Units der Projekt-Suchpfade (#648); gehören zum Projekt-Cache.</summary>
    SearchFiles: TArray<string>;
    /// <summary>Alle Units der Bibliotheks- und Suchpfade der Installation (#648); Bibliothek.</summary>
    LibraryFiles: TArray<string>;
    /// <summary>Reihenfolge unter mehreren Projekten; kleiner = früher (aktives Projekt 0).</summary>
    Priority: Integer;
    Defines: TArray<string>;
    /// <summary>Ordner der Installation und die Symbole, mit denen deren Units gelesen werden (#647);
    /// siehe TIndexBuilder.LibraryRoots.</summary>
    LibraryRoots: TArray<string>;
    LibraryDefines: TArray<string>;
    ResolveUnit: TUnitFileResolver;
    /// <summary>Suchpfade für $I-Dateien (#264).</summary>
    IncludePaths: TArray<string>;
    /// <summary>Cache-Datei; '' = ohne Cache.</summary>
    CacheFile: string;
    /// <summary>Gemeinsamer Cache der Units unter LibraryRoots (RTL/VCL/FMX) je Compilerversion und
    /// Plattform; '' = Bibliothek im Projekt-Cache (#492).</summary>
    LibraryCacheFile: string;
    /// <summary>Gemeinsamer Cache der Units aus SearchFiles für alle Projekte mit denselben Suchpfaden,
    /// Defines und Include-Pfaden (Speicher, Rückmeldung 01.11.2026): Vorher stand jede Suchpfad-Unit im Cache
    /// jedes Projekts, und eine Gruppe hielt beim Laden alle Kopien gleichzeitig. '' = im Projekt-Cache.</summary>
    SearchCacheFile: string;
    /// <summary>Cache nur lesen, z. B. weil eine andere Instanz ihn schreibt (#184).</summary>
    ReadOnlyCache: Boolean;
    /// <summary>Hält eine andere Instanz die Sperre noch? nil = nicht warten (#62).</summary>
    CacheBusy: TFunc<Boolean>;
    /// <summary>Höchstens so lange auf die andere Instanz warten, in ms.</summary>
    CacheWaitMs: Integer;
    /// <summary>Verwendungen der Bezeichner in Projekt-Units erfassen (#492, index.usages).</summary>
    Usages: Boolean;
    /// <summary>Optional: läuft im Index-Thread, wenn der vorige Aufbau geendet hat, vor dem Lesen der Caches,
    /// z. B. um sie zu löschen (#874: Start wartet nicht mehr auf den alten Aufbau).</summary>
    Prepare: TProc;
    /// <summary>Ordner selten genutzter Bibliotheken (c1); siehe TIndexBuilder.RarelyUsedRoots.</summary>
    RarelyUsedRoots: TArray<string>;
    /// <summary>Bibliotheksstufe nur mit Kopf und Katalog (Speicher-Optimierung Phase 3); siehe
    /// TIndexBuilder.LazyLibrary.</summary>
    LazyLibrary: Boolean;
  end;

  /// <summary>Cache-Datei verworfen; AReason z. B. "Prüfsumme stimmt nicht" (#492).</summary>
  TIndexCacheRejectedEvent = reference to procedure(const AFileName, AReason: string);

  TIndexFinishedEvent = reference to procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64);
  TIndexErrorEvent = reference to procedure(const AError: Exception);

  /// <summary>Ein Cache wurde geschrieben (Diagnoselog): ALibrary = gemeinsamer Bibliotheks-Cache.</summary>
  TIndexCacheWrittenEvent = reference to procedure(ALibrary: Boolean; AUnits: Integer; ABytes, AElapsedMs: Int64);

  /// <summary>Ein gemeinsamer Cache wurde nicht gelesen, weil der Index seinen Stand schon hält (b1).</summary>
  TIndexCacheSkippedEvent = reference to procedure(const AFileName: string);

  /// <summary>Übernähme der Aufbau die Unit aus dem Index unverändert (TIndexBuilder.Keeps)?</summary>
  TIndexUnitKept = reference to function(const AUnit: TUnitIndex): Boolean;

  /// <summary>Rückmeldungen beim Lesen und Schreiben der Caches (Diagnoselog).</summary>
  TIndexCacheEvents = record
    Rejected: TIndexCacheRejectedEvent;
    NotWritten: TIndexCacheRejectedEvent;
    Written: TIndexCacheWrittenEvent;
    Skipped: TIndexCacheSkippedEvent;
  end;

  /// <summary>Caches eines Aufbaus (#647): liest beim Start Projekt-, Suchpfad- und Bibliotheks-Cache und schreibt
  /// sie nach der Projektstufe und am Ende getrennt zurück. Hält die gemeinsam gelesenen Kopien (TSharedCacheHold)
  /// bis zur Freigabe.</summary>
  TIndexCacheWriter = class
  private
    FIndex: ISymbolIndex;
    FFileSystem: IIndexFileSystem;
    FEvents: TIndexCacheEvents;
    FRequest: TIndexRequest;
    FCancelled: TFunc<Boolean>;
    FCached: TArray<TIndexCacheEntry>;
    FLibraryCached: TArray<TIndexCacheEntry>;
    FSearchCached: TArray<TIndexCacheEntry>;
    FLibraryHold: IInterface;
    FSearchHold: IInterface;
    /// <summary>Bis zum letzten Schreiben neu gelesene Units.</summary>
    FWrittenParsed: Integer;
    function ReadCache(const AFileName: string): TArray<TIndexCacheEntry>;
    /// <summary>Wie ReadCache ohne Kataloge (Phase 3).</summary>
    function ReadHeaders(const AFileName: string): TArray<TIndexCacheEntry>;
    /// <summary>Gemeinsamer Cache AFileName, außer der Index hält seinen Stand schon (b1): dann leer, AHold nil.
    /// </summary>
    function LoadShared(const AFileName: string; const AKept: TIndexUnitKept; out AHold: IInterface):
      TArray<TIndexCacheEntry>;
    /// <summary>Hält der Index jede Unit des Auftrags aus dem bekannten Stand von AFileName unverändert?</summary>
    function IndexHolds(const AFileName: string; const AKept: TIndexUnitKept): Boolean;
    procedure NotWritten(const AFileName, AReason: string);
    /// <summary>Wartet begrenzt auf die Schreibsperre; nil, wenn sie ein anderer so lange hält oder der Aufbau
    /// abgebrochen ist.</summary>
    function LockForWrite(const AFileName: string): IInterface;
    /// <summary>Gibt den verdrängbaren Units des Index die Blöcke aus AEntries (Phase 3).</summary>
    procedure Bind(const AEntries: TArray<TIndexCacheEntry>);
    /// <summary>Serialisiert AItems nach AFileName; meldet Erfolg über Written, sonst NotWritten.</summary>
    function WriteCache(ALibrary: Boolean; const AFileName: string; const AItems: TArray<TIndexCacheItem>): Boolean;
      overload;
    /// <summary>Wie oben; APlaces nennt die Lage der geschriebenen Blöcke (Phase 4).</summary>
    function WriteCache(ALibrary: Boolean; const AFileName: string; const AItems: TArray<TIndexCacheItem>;
      out APlaces: TArray<TIndexBlockPlace>): Boolean; overload;
    /// <summary>Gibt den Units des Index die eben geschriebenen Blöcke (APlaces zu AItems) der Datei AFileName; liefert
    /// den Leser und die gebundenen Köpfe (nur Name, Datei, Stand) und Blöcke für TSharedCacheWrites.</summary>
    procedure BindWritten(const AFileName: string; const AItems: TArray<TIndexCacheItem>;
      const APlaces: TArray<TIndexBlockPlace>; out AReader: IIndexBlockReader; out AHeaders: TArray<TUnitIndex>;
      out ASources: TArray<IIndexUnitSource>);
    /// <summary>Hängt AUnits an die zuletzt in diesem Prozess geschriebene, unveränderte Datei AFileName an (Phase 4);
    /// False, wenn das nicht geht (dann schreibt der Aufrufer sie ganz).</summary>
    function AppendShared(const AFileName: string; AUnits: TList<TIndexCacheItem>): Boolean;
    /// <summary>Ergänzt einen gemeinsamen Cache (Bibliothek, Suchpfade) um AUnits, wenn etwas fehlt: unter der
    /// Schreibsperre mit dem aktuellen Stand der Datei zusammengeführt (andere Projekte und Prozesse).</summary>
    /// <summary>AUnbound: Der Index hat verdrängbare Units ohne Block (Phase 3); sie bekommen ihn aus der Datei,
    /// auch wenn nichts zu schreiben ist.</summary>
    /// <summary>AAppend (Zwischenstand des ersten Aufbaus, Phase 4): wenn möglich nur anhängen.</summary>
    procedure WriteSharedCache(const AFileName: string; const AStartCached: TArray<TIndexCacheEntry>;
      AUnits: TList<TIndexCacheItem>; AUnbound, AAppend: Boolean);
    /// <summary>Projekt-Units ins Projekt, Suchpfade und Bibliothek in die gemeinsamen Caches.</summary>
    procedure WriteSplit(AParsed: Integer);
  public
    constructor Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
      const AEvents: TIndexCacheEvents; const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>);
    /// <summary>Liest die Caches; Ergebnis für TIndexBuilder.UseCache. Mit AKept liest es gemeinsame Caches nicht
    /// noch einmal, deren Stand der Index schon hält (b1); nil = immer lesen.</summary>
    function Load(const AKept: TIndexUnitKept): TArray<TIndexCacheEntry>;
    /// <summary>Schreibt Projekt-, Suchpfad- und Bibliotheks-Cache; AParsedTotal = im ganzen Aufbau bisher neu
    /// gelesene Units.</summary>
    procedure WriteCaches(AParsedTotal: Integer);
    /// <summary>Zwischenstand des ersten Aufbaus (OnLibraryFlush, Phase 4): nur der Bibliotheks-Cache, angehängt; der
    /// Projekt-Cache folgt mit WriteCaches.</summary>
    procedure FlushLibrary;
    /// <summary>Gibt die gelesenen Einträge frei; die gemeinsamen Kopien hält das Objekt bis zum Ende.</summary>
    procedure Release;
  end;

  /// <summary>Nutzungsstatistik der Bibliotheks-Units (Speicher-Optimierung Phase 3): Punkte je Unit mit
  /// wöchentlicher Halbierung, gespeichert als Text (usage.dat). Threadsicher.</summary>
  TIndexUsageStats = class(TInterfacedObject, IIndexUsage)
  private type
    TValue = record
      Name: string;
      Points: Double;
      /// <summary>Tag (TDateTime ganzzahlig), auf den Points bezogen ist.</summary>
      Day: Integer;
    end;
  public const
    /// <summary>Höchstens so oft schreibt SaveIfDue.</summary>
    cSaveIntervalMs = 10 * 60 * 1000;
    /// <summary>Halbwertszeit der Punkte in Tagen.</summary>
    cHalfLifeDays = 7;
  private
    FFileSystem: IIndexFileSystem;
    FFileName: string;
    FLock: TObject;
    FValues: TDictionary<string, TValue>;
    FToday: Integer;
    FDirty: Boolean;
    FSavedAt: UInt64;
    function Day: Integer;
    /// <summary>Punkte von AValue am Tag ADay (Zerfall).</summary>
    class function Decayed(const AValue: TValue; ADay: Integer): Double; static;
    procedure Load;
  public
    /// <summary>Liest AFileName (fehlt sie, beginnt die Statistik leer). AToday &gt;= 0 setzt den Tag fest (Tests).
    /// </summary>
    constructor Create(const AFileSystem: IIndexFileSystem; const AFileName: string; AToday: Integer = -1);
    destructor Destroy; override;
    procedure Note(const AUnitName: string; AWeight: Integer);
    function Score(const AUnitName: string): Integer;
    function FileName: string;
    /// <summary>Schreibt die Datei, wenn sich etwas geändert hat (AForce) bzw. seit dem letzten Schreiben
    /// cSaveIntervalMs vergangen sind. Fehler beim Schreiben bleiben ohne Folgen.</summary>
    procedure SaveIfDue(AForce: Boolean);
    /// <summary>Datei der Statistik neben dem Bibliotheks-Cache ALibraryCacheFile; '' ohne.</summary>
    class function FileFor(const ALibraryCacheFile: string): string; static;
  end;

  TIndexService = class
  private
    FIndex: ISymbolIndex;
    FFileSystem: IIndexFileSystem;
    /// <summary>Jüngster Index-Thread (TIndexThread); hält den abgebrochenen Vorgänger, bis der endet.</summary>
    FThread: TThread;
    FBuilder: TIndexBuilder;
    FLock: TObject;
    /// <summary>Anfragen, die FBuilder gerade nutzen; nur unter FLock ändern.</summary>
    FUsers: Integer;
    /// <summary>Hält ApplyText und ApplyChanges in Reihe; EnsureUnit wartet darauf nicht.</summary>
    FApplyLock: TObject;
    FOnProgress: TIndexProgressEvent;
    FOnFinished: TIndexFinishedEvent;
    FOnProjectReady: TIndexFinishedEvent;
    FOnError: TIndexErrorEvent;
    FScheduler: TIndexScheduler;
    FStages: TIndexStageWatch;
    FCacheEvents: TIndexCacheEvents;
    /// <summary>Cache-Datei des letzten Aufbaus; nur unter FLock.</summary>
    FCacheFile: string;
    /// <summary>Schreibt die Nutzungsstatistik im Hintergrund (Phase 4); nur unter FLock.</summary>
    FSaveThread: TThread;
    /// <summary>Ticks, ab denen SaveStatistics(False) wieder nachsieht (TInterlocked).</summary>
    FNextSaveCheck: Int64;
    procedure Run(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>);
    /// <summary>Neuer Builder mit gelesenem Cache; noch nicht veröffentlicht.</summary>
    function PrepareBuilder(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>;
      ACaches: TIndexCacheWriter): TIndexBuilder;
    procedure WaitForOtherWriter(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>);
    function AcquireBuilder: TIndexBuilder;
    procedure ReleaseBuilder;
    procedure ReplaceBuilder(ABuilder: TIndexBuilder);
    /// <summary>Meldet AError über OnError; eine Ausnahme der Meldung beendet den Index-Thread nicht.</summary>
    procedure ReportError(const AError: Exception);
    /// <summary>Nutzungsstatistik des Index zum Bibliotheks-Cache des Auftrags (Phase 3); legt sie an oder ersetzt
    /// eine zu einer anderen Datei.</summary>
    procedure UseStatistics(const ARequest: TIndexRequest);
    /// <summary>Schreibt die Nutzungsstatistik des Index, wenn fällig (AForce: wenn geändert). Ohne AForce prüft es
    /// höchstens einmal je Minute und schreibt im Hintergrund (Phase 4).</summary>
    procedure SaveStatistics(AForce: Boolean);
    /// <summary>Startet das Schreiben der Statistik im Hintergrund, falls nicht schon eines läuft.</summary>
    procedure SaveInBackground;
    /// <summary>Wartet auf ein laufendes Schreiben im Hintergrund.</summary>
    procedure WaitForSave;
  public
    constructor Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem);
    destructor Destroy; override;
    /// <summary>Startet den Aufbau im Hintergrund; ein laufender wird abgebrochen. Kehrt sofort zurück: Der neue
    /// Aufbau beginnt erst, wenn der alte geendet hat (#874).</summary>
    procedure Start(const ARequest: TIndexRequest);
    /// <summary>Bricht ab und wartet auf das Ende.</summary>
    procedure Stop;
    /// <summary>Wartet auf das Ende des Aufbaus (für Tests).</summary>
    procedure WaitFor;
    /// <summary>Indiziert eine Unit nachträglich (z. B. für die Namensauflösung).</summary>
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>Übernimmt Dateiänderungen im aufrufenden Thread; 0 ohne laufenden Builder.</summary>
    function ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
    /// <summary>Ungespeicherter Text einer Unit nach der Tipp-Pause (#492).</summary>
    function ApplyText(const AFileName, AText: string): Boolean;
    /// <summary>Verwendungen der Bezeichner in AFileName (#492): aus dem Speicher, bei ausgelagerten aus dem
    /// Cache, sonst frisch aus der Datei. False, wenn die Unit nicht im Index ist oder keine erfasst wurden.</summary>
    function UsagesOf(const AFileName: string; out AUsages: TArray<TIndexUsage>): Boolean;
    /// <summary>Stufe des laufenden Aufbaus und ob er auf sie wartet (#2142).</summary>
    function StageState: TIndexStageState;
    /// <summary>Vergisst die im Prozess gemerkten Stände der gemeinsamen Caches (b1). Nur aufrufen, wenn kein
    /// Dienst mehr läuft (der letzte Server im Prozess ist beendet): Ohne Index braucht der nächste Aufbau sie
    /// nicht, sie hielten sonst je Unit Dateiname und Stand bis zum Ende des Prozesses.</summary>
    class procedure ForgetSharedStates; static;
    property Index: ISymbolIndex read FIndex;
    property OnCacheRejected: TIndexCacheRejectedEvent read FCacheEvents.Rejected write FCacheEvents.Rejected;
    /// <summary>Cache nicht geschrieben; AReason ohne Pfad. Im Index-Thread.</summary>
    property OnCacheNotWritten: TIndexCacheRejectedEvent read FCacheEvents.NotWritten write FCacheEvents.NotWritten;
    /// <summary>Nach jedem geschriebenen Cache; im Index-Thread.</summary>
    property OnCacheWritten: TIndexCacheWrittenEvent read FCacheEvents.Written write FCacheEvents.Written;
    /// <summary>Gemeinsamer Cache nicht gelesen, weil der Index seinen Stand schon hält (b1); im Index-Thread.
    /// </summary>
    property OnCacheSkipped: TIndexCacheSkippedEvent read FCacheEvents.Skipped write FCacheEvents.Skipped;
    property OnProgress: TIndexProgressEvent read FOnProgress write FOnProgress;
    property OnFinished: TIndexFinishedEvent read FOnFinished write FOnFinished;
    /// <summary>Projektstufe fertig (Projektdateien und über uses erreichbare Units), Cache geschrieben;
    /// Suchpfade und Bibliothek folgen. Im Index-Thread, nicht bei Abbruch.</summary>
    property OnProjectReady: TIndexFinishedEvent read FOnProjectReady write FOnProjectReady;
    property OnError: TIndexErrorEvent read FOnError write FOnError;
    /// <summary>Gemeinsam für alle Projekte (#648); gehört dem Aufrufer, nil = ohne Reihenfolge.</summary>
    property Scheduler: TIndexScheduler read FScheduler write FScheduler;
  end;

implementation

uses
  System.Diagnostics,
  System.Math,
  System.SyncObjs,
  dpcc.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TIndexServiceText = (WriteLockNotObtained);

const
  cTexts: array[TIndexServiceText] of TDpccText = (
    (De: 'Schreibsperre nicht erhalten'; En: 'Write lock not obtained'));

{$SCOPEDENUMS OFF}

/// <summary>Schlüssel einer Cache-Datei im Prozess: Dateisystem und Datei.</summary>
function SharedCacheKey(const AFileSystem: IIndexFileSystem; const AFileName: string): string;
begin
  Result := IntToHex(NativeInt(Pointer(AFileSystem)), 16) + '|' + AnsiUpperCase(AFileName);
end;

type
  /// <summary>Schreiben der Index-Caches im Prozess: immer nur ein Dienst zur Zeit (Enter/Leave), damit nie
  /// mehrere große Serialisierungen gleichzeitig Speicher belegen. Merkt sich je gemeinsamer Datei, welche
  /// Unit-Stände sie enthält, zuletzt hineingeschrieben oder gelesen (b1); gilt nur, solange die Datei denselben
  /// Zeitstempel hat (schreibt eine andere Instanz, ist der Stand unbekannt). Die Stände bleiben auch, wenn kein
  /// Aufbau die Datei mehr nutzt: Der nächste Aufbau braucht sie, um nicht neu zu lesen.</summary>
  TSharedCacheWrites = class
  private type
    TWritten = class
    public
      Stamp: Int64;
      Units: TDictionary<string, string>;
      /// <summary>Nach eigenem Schreiben (Phase 4): Leser der Datei und die gebundenen Köpfe (nur Name, Datei,
      /// Stand) mit ihren Blöcken; nil nach Lesen.</summary>
      Reader: IIndexBlockReader;
      Headers: TArray<TUnitIndex>;
      Sources: TArray<IIndexUnitSource>;
      destructor Destroy; override;
    end;
  private
    class var FLock: TObject;
    class var FFiles: TObjectDictionary<string, TWritten>;
  public
    class constructor Create;
    class destructor Destroy;
    class procedure Enter; static;
    class procedure Leave; static;
    /// <summary>Datei (groß) → Stand (StateOf) der zuletzt in AFileName geschriebenen Units; nil, wenn
    /// unbekannt oder die Datei seither einen anderen Zeitstempel hat. Nur zwischen Enter und Leave
    /// verwenden; das Ergebnis gehört weiter TSharedCacheWrites.</summary>
    class function Written(const AFileSystem: IIndexFileSystem; const AFileName: string): TDictionary<string, string>;
      static;
    /// <summary>Merkt den eben geschriebenen Stand mit dem jetzigen Zeitstempel der Datei; übernimmt AUnits.
    /// Nur zwischen Enter und Leave.</summary>
    class procedure Remember(const AFileSystem: IIndexFileSystem; const AFileName: string;
      AUnits: TDictionary<string, string>; const AReader: IIndexBlockReader = nil;
      const AHeaders: TArray<TUnitIndex> = nil; const ASources: TArray<IIndexUnitSource> = nil); static;
    /// <summary>Zuletzt in AFileName geschriebener Stand samt Leser (Phase 4), wenn die Datei seither unverändert ist;
    /// nur zwischen Enter und Leave.</summary>
    class function LastWrite(const AFileSystem: IIndexFileSystem; const AFileName: string; out AStamp: Int64;
      out AReader: IIndexBlockReader; out AUnits: TDictionary<string, string>): Boolean; static;
    /// <summary>Die zuletzt gebundenen Köpfe und Blöcke von AFileName (Phase 4), wenn die Datei unverändert ist; nur
    /// zwischen Enter und Leave.</summary>
    class function LastSources(const AFileSystem: IIndexFileSystem; const AFileName: string;
      out AHeaders: TArray<TUnitIndex>; out ASources: TArray<IIndexUnitSource>): Boolean; static;
    /// <summary>Merkt den eben gelesenen Stand von AFileName zum Zeitstempel AStamp, den die Datei vor dem Lesen
    /// hatte (b1); ohne Einträge oder ohne Zeitstempel nichts. Außerhalb von Enter und Leave.</summary>
    class procedure RememberRead(const AFileSystem: IIndexFileSystem; const AFileName: string; AStamp: Int64;
      const AEntries: TArray<TIndexCacheEntry>); static;
    /// <summary>Stand einer Unit: Zeitstempel und Prüfsumme.</summary>
    class function StateOf(const AUnit: TUnitIndex): string; static;
    /// <summary>Vergisst alle gemerkten Stände (der letzte Server im Prozess ist beendet).</summary>
    class procedure Clear; static;
  end;

  /// <summary>Gemeinsam gelesener Bibliotheks-Cache: Alle Dienste eines Prozesses teilen eine Kopie, solange
  /// jemand sie nutzt; Schlüssel ist Dateisystem und Datei, gültig für einen Zeitstempel.</summary>
  TSharedCacheReads = class
  private type
    TShared = class
      FStamp: Int64;
      FEntries: TArray<TIndexCacheEntry>;
      FUsers: Integer;
    end;
  private
    class var FLock: TObject;
    class var FFiles: TObjectDictionary<string, TShared>;
    class function KeyOf(const AFileSystem: IIndexFileSystem; const AFileName: string): string; static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Einträge von AFileName; liest nur, wenn niemand denselben Stand hält. AStamp merkt sich der
    /// Aufrufer für Release.</summary>
    class function Acquire(const AFileSystem: IIndexFileSystem; const AFileName: string; out AStamp: Int64;
      const ARead: TFunc<TArray<TIndexCacheEntry>>): TArray<TIndexCacheEntry>; static;
    class procedure Release(const AFileSystem: IIndexFileSystem; const AFileName: string; AStamp: Int64); static;
  end;

  /// <summary>Hält eine Kopie aus TSharedCacheReads für die Dauer eines Aufbaus; gibt sie frei, sobald die letzte
  /// Referenz fällt, auch nach einer Ausnahme (wie die Schreibsperre aus LockForWrite).</summary>
  TSharedCacheHold = class(TInterfacedObject)
  private
    FFileSystem: IIndexFileSystem;
    FFileName: string;
    FStamp: Int64;
  public
    /// <summary>Holt die Einträge von AFileName; AHold hält sie. '' = kein gemeinsamer Cache: leer, AHold
    /// nil.</summary>
    class function Acquire(const AFileSystem: IIndexFileSystem; const AFileName: string;
      const ARead: TFunc<TArray<TIndexCacheEntry>>; out AHold: IInterface): TArray<TIndexCacheEntry>; static;
    destructor Destroy; override;
  end;

{ TSharedCacheWrites.TWritten }

destructor TSharedCacheWrites.TWritten.Destroy;
begin
  Units.Free;
  inherited;
end;

{ TSharedCacheWrites }

class constructor TSharedCacheWrites.Create;
begin
  FLock := TObject.Create;
  FFiles := TObjectDictionary<string, TWritten>.Create([doOwnsValues]);
end;

class destructor TSharedCacheWrites.Destroy;
begin
  FFiles.Free;
  FLock.Free;
end;

class procedure TSharedCacheWrites.Enter;
begin
  TMonitor.Enter(FLock);
end;

class procedure TSharedCacheWrites.Leave;
begin
  TMonitor.Exit(FLock);
end;

class function TSharedCacheWrites.Written(const AFileSystem: IIndexFileSystem;
  const AFileName: string): TDictionary<string, string>;
var
  mEntry: TWritten;
  mStamp: Int64;
begin
  Result := nil;
  if not FFiles.TryGetValue(SharedCacheKey(AFileSystem, AFileName), mEntry) then
  begin
    Exit;
  end;
  if AFileSystem.FileStamp(AFileName, mStamp) and (mStamp = mEntry.Stamp) then
  begin
    Result := mEntry.Units;
  end;
end;

class procedure TSharedCacheWrites.Remember(const AFileSystem: IIndexFileSystem; const AFileName: string;
  AUnits: TDictionary<string, string>; const AReader: IIndexBlockReader; const AHeaders: TArray<TUnitIndex>;
  const ASources: TArray<IIndexUnitSource>);
var
  mEntry: TWritten;
  mStamp: Int64;
begin
  if not AFileSystem.FileStamp(AFileName, mStamp) then
  begin
    AUnits.Free;
    FFiles.Remove(SharedCacheKey(AFileSystem, AFileName));
    Exit;
  end;
  mEntry := TWritten.Create;
  mEntry.Stamp := mStamp;
  mEntry.Units := AUnits;
  mEntry.Reader := AReader;
  mEntry.Headers := AHeaders;
  mEntry.Sources := ASources;
  FFiles.AddOrSetValue(SharedCacheKey(AFileSystem, AFileName), mEntry);
end;

class function TSharedCacheWrites.LastWrite(const AFileSystem: IIndexFileSystem; const AFileName: string;
  out AStamp: Int64; out AReader: IIndexBlockReader; out AUnits: TDictionary<string, string>): Boolean;
var
  mEntry: TWritten;
begin
  AStamp := 0;
  AReader := nil;
  AUnits := nil;
  Result := FFiles.TryGetValue(SharedCacheKey(AFileSystem, AFileName), mEntry) and (mEntry.Reader <> nil) and
    AFileSystem.FileStamp(AFileName, AStamp) and (AStamp = mEntry.Stamp);
  if Result then
  begin
    AReader := mEntry.Reader;
    AUnits := mEntry.Units;
  end;
end;

class function TSharedCacheWrites.LastSources(const AFileSystem: IIndexFileSystem; const AFileName: string;
  out AHeaders: TArray<TUnitIndex>; out ASources: TArray<IIndexUnitSource>): Boolean;
var
  mEntry: TWritten;
  mStamp: Int64;
begin
  AHeaders := nil;
  ASources := nil;
  Result := FFiles.TryGetValue(SharedCacheKey(AFileSystem, AFileName), mEntry) and (mEntry.Sources <> nil) and
    AFileSystem.FileStamp(AFileName, mStamp) and (mStamp = mEntry.Stamp);
  if Result then
  begin
    AHeaders := mEntry.Headers;
    ASources := mEntry.Sources;
  end;
end;

class procedure TSharedCacheWrites.RememberRead(const AFileSystem: IIndexFileSystem; const AFileName: string;
  AStamp: Int64; const AEntries: TArray<TIndexCacheEntry>);
var
  mEntry: TWritten;
  mCacheEntry: TIndexCacheEntry;
begin
  if (AStamp < 0) or (Length(AEntries) = 0) then
  begin
    Exit;
  end;
  // Der Zeitstempel von vor dem Lesen: Hat ein anderer Prozess die Datei inzwischen ersetzt, passt er nicht mehr,
  // und der Stand gilt als unbekannt.
  mEntry := TWritten.Create;
  mEntry.Stamp := AStamp;
  mEntry.Units := TDictionary<string, string>.Create(Length(AEntries));
  for mCacheEntry in AEntries do
  begin
    mEntry.Units.AddOrSetValue(AnsiUpperCase(mCacheEntry.Header.FileName), StateOf(mCacheEntry.Header));
  end;
  TMonitor.Enter(FLock);
  try
    FFiles.AddOrSetValue(SharedCacheKey(AFileSystem, AFileName), mEntry);
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TSharedCacheWrites.StateOf(const AUnit: TUnitIndex): string;
begin
  Result := IntToStr(AUnit.Stamp) + '|' + AUnit.Hash;
end;

class procedure TSharedCacheWrites.Clear;
begin
  TMonitor.Enter(FLock);
  try
    FFiles.Clear;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TSharedCacheHold }

class function TSharedCacheHold.Acquire(const AFileSystem: IIndexFileSystem; const AFileName: string;
  const ARead: TFunc<TArray<TIndexCacheEntry>>; out AHold: IInterface): TArray<TIndexCacheEntry>;
var
  mHold: TSharedCacheHold;
  mStamp: Int64;
begin
  AHold := nil;
  Result := nil;
  if AFileName = '' then
  begin
    Exit;
  end;
  Result := TSharedCacheReads.Acquire(AFileSystem, AFileName, mStamp, ARead);
  mHold := TSharedCacheHold.Create;
  mHold.FFileSystem := AFileSystem;
  mHold.FFileName := AFileName;
  mHold.FStamp := mStamp;
  AHold := mHold;
end;

destructor TSharedCacheHold.Destroy;
begin
  TSharedCacheReads.Release(FFileSystem, FFileName, FStamp);
  inherited;
end;

{ TSharedCacheReads }

class constructor TSharedCacheReads.Create;
begin
  FLock := TObject.Create;
  FFiles := TObjectDictionary<string, TShared>.Create([doOwnsValues]);
end;

class destructor TSharedCacheReads.Destroy;
begin
  FFiles.Free;
  FLock.Free;
end;

class function TSharedCacheReads.KeyOf(const AFileSystem: IIndexFileSystem; const AFileName: string): string;
begin
  Result := SharedCacheKey(AFileSystem, AFileName);
end;

class function TSharedCacheReads.Acquire(const AFileSystem: IIndexFileSystem; const AFileName: string;
  out AStamp: Int64; const ARead: TFunc<TArray<TIndexCacheEntry>>): TArray<TIndexCacheEntry>;
var
  mKey: string;
  mShared: TShared;
begin
  if not AFileSystem.FileStamp(AFileName, AStamp) then
  begin
    AStamp := -1;
  end;
  mKey := KeyOf(AFileSystem, AFileName);
  // Unter der Sperre lesen: Ein zweiter Dienst wartet lieber, als dieselbe Datei ein zweites Mal zu laden.
  TMonitor.Enter(FLock);
  try
    if FFiles.TryGetValue(mKey, mShared) and (mShared.FStamp = AStamp) then
    begin
      Inc(mShared.FUsers);
      Exit(mShared.FEntries);
    end;
    mShared := TShared.Create;
    mShared.FStamp := AStamp;
    mShared.FEntries := ARead();
    mShared.FUsers := 1;
    FFiles.AddOrSetValue(mKey, mShared);
    Result := mShared.FEntries;
  finally
    TMonitor.Exit(FLock);
  end;
  // Außerhalb der Lese-Sperre: RememberRead wartet auf ein laufendes Schreiben. Nur nach eigenem Lesen; die
  // geteilte Kopie oben hat schon ihr Leser gemerkt.
  TSharedCacheWrites.RememberRead(AFileSystem, AFileName, AStamp, Result);
end;

class procedure TSharedCacheReads.Release(const AFileSystem: IIndexFileSystem; const AFileName: string;
  AStamp: Int64);
var
  mKey: string;
  mShared: TShared;
begin
  mKey := KeyOf(AFileSystem, AFileName);
  TMonitor.Enter(FLock);
  try
    // Anderer Stand: Der Eintrag wurde schon ersetzt; die eigene Kopie hält der Aufrufer selbst.
    if not FFiles.TryGetValue(mKey, mShared) or (mShared.FStamp <> AStamp) then
    begin
      Exit;
    end;
    Dec(mShared.FUsers);
    if mShared.FUsers <= 0 then
    begin
      // Den bekannten Stand der Datei behält TSharedCacheWrites (b1).
      FFiles.Remove(mKey);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

type
  TIndexThread = class(TThread)
  private
    FService: TIndexService;
    FRequest: TIndexRequest;
    /// <summary>Abgebrochener Vorgänger; Execute wartet auf ihn und gibt ihn frei.</summary>
    FPrevious: TThread;
    FCancelled: Boolean;
    function IsCancelled: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AService: TIndexService; const ARequest: TIndexRequest; APrevious: TThread);
    destructor Destroy; override;
    /// <summary>Bricht den Aufbau ab; wartet nicht.</summary>
    procedure Cancel;
  end;

{ TIndexThread }

constructor TIndexThread.Create(AService: TIndexService; const ARequest: TIndexRequest; APrevious: TThread);
begin
  FService := AService;
  FRequest := ARequest;
  FPrevious := APrevious;
  inherited Create(False);
  // Niedrige Priorität (#1236): Der Aufbau läuft im Hintergrund; IDE, Editor und Anfragen gehen vor. Der Thread
  // startet erst nach dem Konstruktor. Nicht jede Plattform erlaubt das.
  try
    Priority := tpLower;
  except
    // Dann eben mit normaler Priorität; der Aufbau selbst ist davon nicht betroffen.
  end;
end;

destructor TIndexThread.Destroy;
begin
  // Wartet selbst, falls Execute nicht bis zum Vorgänger kam.
  FreeAndNil(FPrevious);
  inherited Destroy;
end;

procedure TIndexThread.Cancel;
begin
  FCancelled := True;
end;

function TIndexThread.IsCancelled: Boolean;
begin
  Result := FCancelled;
end;

procedure TIndexThread.Execute;
begin
  NameThreadForDebugging('dpcc.Index');
  // Erst den abgebrochenen Vorgänger beenden: Builder und Cache-Dateien gehören immer nur einem Aufbau.
  if FPrevious <> nil then
  begin
    FPrevious.WaitFor;
    FreeAndNil(FPrevious);
  end;
  if not FCancelled then
  begin
    FService.Run(FRequest, IsCancelled);
  end;
end;

{ TIndexService }

constructor TIndexService.Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem);
begin
  inherited Create;
  FIndex := AIndex;
  FFileSystem := AFileSystem;
  FLock := TObject.Create;
  FApplyLock := TObject.Create;
  FStages := TIndexStageWatch.Create;
end;

destructor TIndexService.Destroy;
begin
  Stop;
  SaveStatistics(True);
  ReplaceBuilder(nil);
  FStages.Free;
  FApplyLock.Free;
  FLock.Free;
  inherited;
end;

/// <summary>Steht AUnit mit gleichem Stand (Zeitstempel, Prüfsumme) in AEntries? AByFile ordnet
/// jedem Dateinamen (groß) seine Stelle in AEntries zu; linear wären es bei Tausenden
/// Bibliotheks-Units Millionen Vergleiche (Diagnoselog 15.10.2026).</summary>
function ContainsUnit(const AEntries: TArray<TIndexCacheEntry>; AByFile: TDictionary<string, Integer>;
  const AUnit: TUnitIndex): Boolean;
var
  mPosition: Integer;
begin
  Result := AByFile.TryGetValue(AnsiUpperCase(AUnit.FileName), mPosition) and
    (AEntries[mPosition].Header.Stamp = AUnit.Stamp) and (AEntries[mPosition].Header.Hash = AUnit.Hash);
end;

function InSharedCache(const ARequest: TIndexRequest; const AFileName: string): Boolean;
begin
  // Ohne Installationsordner wie bisher: alle nachgeladenen Units in den gemeinsamen Cache.
  Result := (Length(ARequest.LibraryRoots) = 0) or TIndexFileDefines.IsUnder(AFileName, ARequest.LibraryRoots);
end;

/// <summary>Fehlt eine Unit aus AUnits in AEntries oder steht sie dort mit anderem Stand?</summary>
function MissingIn(const AEntries: TArray<TIndexCacheEntry>; AUnits: TList<TIndexCacheItem>): Boolean;
var
  mByFile: TDictionary<string, Integer>;
  mPosition: Integer;
  mItem: TIndexCacheItem;
begin
  Result := False;
  mByFile := TDictionary<string, Integer>.Create;
  try
    for mPosition := 0 to High(AEntries) do
    begin
      mByFile.AddOrSetValue(AnsiUpperCase(AEntries[mPosition].Header.FileName), mPosition);
    end;
    for mItem in AUnits do
    begin
      if not ContainsUnit(AEntries, mByFile, mItem.Header) then
      begin
        Exit(True);
      end;
    end;
  finally
    mByFile.Free;
  end;
end;

/// <summary>Steht jede Unit aus AUnits mit demselben Stand in AWritten (zuletzt in diesem Prozess geschrieben)?
/// </summary>
function AllWritten(AWritten: TDictionary<string, string>; AUnits: TList<TIndexCacheItem>): Boolean;
var
  mItem: TIndexCacheItem;
  mState: string;
begin
  for mItem in AUnits do
  begin
    if not AWritten.TryGetValue(AnsiUpperCase(mItem.Header.FileName), mState) or
      (mState <> TSharedCacheWrites.StateOf(mItem.Header)) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Die Units aus AEntries, die AUnits nicht hat, als unveränderte Blöcke (Format 34): Units anderer
/// Projekte im gemeinsamen Cache bleiben erhalten, ohne sie zu dekodieren.</summary>
function OthersOf(const AEntries: TArray<TIndexCacheEntry>; AUnits: TList<TIndexCacheItem>):
  TArray<TIndexCacheItem>;
var
  mCurrent: TDictionary<string, Boolean>;
  mEntry: TIndexCacheEntry;
  mItem: TIndexCacheItem;
  mItems: TList<TIndexCacheItem>;
begin
  mCurrent := TDictionary<string, Boolean>.Create;
  mItems := TList<TIndexCacheItem>.Create;
  try
    for mItem in AUnits do
    begin
      mCurrent.AddOrSetValue(AnsiUpperCase(mItem.Header.FileName), True);
    end;
    for mEntry in AEntries do
    begin
      if not mCurrent.ContainsKey(AnsiUpperCase(mEntry.Header.FileName)) then
      begin
        mItems.Add(TIndexCacheItem.OfEntry(mEntry));
      end;
    end;
    Result := mItems.ToArray;
  finally
    mItems.Free;
    mCurrent.Free;
  end;
end;

/// <summary>Einträge der Cache-Datei AFileName (nur Kopf und Verzeichnis, Format 34); meldet einen verworfenen
/// Cache über ARejected. Ohne ACatalog bleiben die Kataloge leer (Phase 3: nur Stand und Block, etwa für
/// ISymbolIndex.BindSources); das spart beim Bibliotheks-Cache einige MB Texte.</summary>
function ReadCacheFile(const AFileSystem: IIndexFileSystem; const AFileName: string;
  const ARejected: TIndexCacheRejectedEvent; ACatalog: Boolean = True): TArray<TIndexCacheEntry>;
var
  mReader: IIndexBlockReader;
  mReason: string;
begin
  Result := nil;
  if AFileName = '' then
  begin
    Exit;
  end;
  mReader := AFileSystem.OpenBlocks(AFileName);
  if mReader = nil then
  begin
    Exit;
  end;
  Result := TIndexCache.ReadEntries(mReader, mReason, ACatalog);
  if (mReason <> '') and Assigned(ARejected) then
  begin
    ARejected(AFileName, mReason);
  end;
end;

/// <summary>Eintrag für TIndexCache.Write zu einer Unit des Index (Phase 3): eine Unit, deren Symbole nicht im
/// Speicher sind, und eine unveränderte verdrängbare Unit als Block aus ihrem Cache, sonst aus dem Speicher.
/// </summary>
function ItemOf(const AStored: TIndexStoredUnit): TIndexCacheItem;
begin
  // Mit Block (auch gepinnt): unverändert seit dem Lesen, der Block wird kopiert statt neu geschrieben.
  Result := Default(TIndexCacheItem);
  if AStored.Loaded and (AStored.Source = nil) then
  begin
    // Den Katalog hat der Index schon (Phase 4; vorher je Unit und Schreiben neu gebaut).
    Result.Header := AStored.Unit_;
    Result.Catalog := AStored.Catalog;
    Result.SymbolCount := Length(AStored.Unit_.Symbols);
    Result.UnavailableCount := Length(AStored.Unit_.Unavailable);
    Result.UsageCount := Length(AStored.Unit_.Usages);
    Exit;
  end;
  Result.Header := AStored.Unit_;
  Result.Catalog := AStored.Catalog;
  Result.Source := AStored.Source;
  Result.SymbolCount := AStored.SymbolCount;
  Result.UnavailableCount := AStored.UnavailableCount;
  Result.UsageCount := AStored.UsageCount;
end;

/// <summary>Alle Units des Index als Einträge für TIndexCache.Write.</summary>
function ItemsOf(const AStored: TArray<TIndexStoredUnit>): TArray<TIndexCacheItem>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AStored));
  for mIndex := 0 to High(AStored) do
  begin
    Result[mIndex] := ItemOf(AStored[mIndex]);
  end;
end;

/// <summary>Großgeschriebene Dateinamen aus AFiles ohne die aus AExcept (nil = keine).</summary>
function FileKeys(const AFiles: TArray<string>; AExcept: TDictionary<string, Boolean>): TDictionary<string, Boolean>;
var
  mFileName, mKey: string;
begin
  Result := TDictionary<string, Boolean>.Create;
  for mFileName in AFiles do
  begin
    mKey := AnsiUpperCase(mFileName);
    if (AExcept = nil) or not AExcept.ContainsKey(mKey) then
    begin
      Result.AddOrSetValue(mKey, True);
    end;
  end;
end;

/// <summary>Verteilt AUnits auf die Caches: Bibliothek, Suchpfade, Projekt. Der Index ist mit anderen Projekten
/// geteilt: in den Projekt-Cache nur die eigenen Units.</summary>
procedure SortUnits(const ARequest: TIndexRequest; const AUnits: TArray<TIndexStoredUnit>;
  AProject, ASearch, ALibrary: TList<TIndexCacheItem>);
var
  mOwn, mSearched: TDictionary<string, Boolean>;
  mStored: TIndexStoredUnit;
  mUnit: TUnitIndex;
  mKey: string;
begin
  mOwn := FileKeys(ARequest.Files, nil);
  mSearched := nil;
  try
    // Eine Projektdatei, die auch im Suchpfad liegt, bleibt im Projekt-Cache.
    mSearched := FileKeys(ARequest.SearchFiles, mOwn);
    for mStored in AUnits do
    begin
      mUnit := mStored.Unit_;
      mKey := AnsiUpperCase(mUnit.FileName);
      if mUnit.Library_ and InSharedCache(ARequest, mUnit.FileName) then
      begin
        ALibrary.Add(ItemOf(mStored));
      end
      else if (ARequest.SearchCacheFile <> '') and mSearched.ContainsKey(mKey) then
      begin
        ASearch.Add(ItemOf(mStored));
      end
      else if mUnit.Library_ or mOwn.ContainsKey(mKey) or mSearched.ContainsKey(mKey) then
      begin
        // Über uses erreichte Units außerhalb der Installation (gemeinsamer Firmencode) liest
        // der Builder mit den Defines des Projekts; sie gehören in dessen Cache (#647).
        AProject.Add(ItemOf(mStored));
      end;
    end;
  finally
    mSearched.Free;
    mOwn.Free;
  end;
end;

{ TIndexUsageStats }

constructor TIndexUsageStats.Create(const AFileSystem: IIndexFileSystem; const AFileName: string; AToday: Integer);
begin
  inherited Create;
  FFileSystem := AFileSystem;
  FFileName := AFileName;
  FToday := AToday;
  FLock := TObject.Create;
  FValues := TDictionary<string, TValue>.Create;
  FSavedAt := TThread.GetTickCount64;
  Load;
end;

destructor TIndexUsageStats.Destroy;
begin
  FValues.Free;
  FLock.Free;
  inherited;
end;

class function TIndexUsageStats.FileFor(const ALibraryCacheFile: string): string;
begin
  Result := '';
  if ALibraryCacheFile <> '' then
  begin
    Result := IncludeTrailingPathDelimiter(ExtractFileDir(ALibraryCacheFile)) + 'usage.dat';
  end;
end;

function TIndexUsageStats.Day: Integer;
begin
  Result := FToday;
  if Result < 0 then
  begin
    Result := Trunc(Now);
  end;
end;

class function TIndexUsageStats.Decayed(const AValue: TValue; ADay: Integer): Double;
begin
  Result := AValue.Points;
  if ADay > AValue.Day then
  begin
    Result := Result * Power(0.5, (ADay - AValue.Day) / cHalfLifeDays);
  end;
end;

function TIndexUsageStats.FileName: string;
begin
  Result := FFileName;
end;

procedure TIndexUsageStats.Load;
var
  mText, mLine: string;
  mParts: TArray<string>;
  mValue: TValue;
begin
  if (FFileName = '') or (FFileSystem = nil) or not FFileSystem.ReadText(FFileName, mText) then
  begin
    Exit;
  end;
  // "Tag Tab Punkte Tab Unit" je Zeile; die erste Zeile nennt das Format. Unlesbares bleibt weg.
  for mLine in mText.Split([#10]) do
  begin
    mParts := mLine.Trim.Split([#9]);
    if (Length(mParts) <> 3) or not TryStrToInt(mParts[0], mValue.Day) or
      not TryStrToFloat(mParts[1], mValue.Points, TFormatSettings.Invariant) or (mParts[2] = '') then
    begin
      Continue;
    end;
    mValue.Name := mParts[2];
    FValues.AddOrSetValue(UpperCase(mValue.Name), mValue);
  end;
end;

procedure TIndexUsageStats.Note(const AUnitName: string; AWeight: Integer);
var
  mValue: TValue;
  mDay: Integer;
begin
  if AUnitName = '' then
  begin
    Exit;
  end;
  mDay := Day;
  TMonitor.Enter(FLock);
  try
    if FValues.TryGetValue(UpperCase(AUnitName), mValue) then
    begin
      mValue.Points := Decayed(mValue, mDay);
    end
    else
    begin
      mValue.Name := AUnitName;
      mValue.Points := 0;
    end;
    mValue.Day := mDay;
    mValue.Points := mValue.Points + AWeight;
    FValues.AddOrSetValue(UpperCase(AUnitName), mValue);
    FDirty := True;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TIndexUsageStats.Score(const AUnitName: string): Integer;
var
  mValue: TValue;
begin
  TMonitor.Enter(FLock);
  try
    if not FValues.TryGetValue(UpperCase(AUnitName), mValue) then
    begin
      Exit(0);
    end;
    Result := Trunc(Decayed(mValue, Day));
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexUsageStats.SaveIfDue(AForce: Boolean);
var
  mBuilder: TStringBuilder;
  mValue: TValue;
  mDay: Integer;
  mPoints: Double;
  mText: string;
begin
  if (FFileName = '') or (FFileSystem = nil) then
  begin
    Exit;
  end;
  // Phase 4: Nicht fällig ist der häufige Fall; ohne Sperre und Allokation erkennen (ein gerissener Lesewert führt nur
  // zur Prüfung unter der Sperre).
  if not AForce and (TThread.GetTickCount64 - FSavedAt < cSaveIntervalMs) then
  begin
    Exit;
  end;
  mDay := Day;
  mBuilder := TStringBuilder.Create;
  try
    TMonitor.Enter(FLock);
    try
      if not FDirty or (not AForce and (TThread.GetTickCount64 - FSavedAt < cSaveIntervalMs)) then
      begin
        Exit;
      end;
      mBuilder.Append('dpcc-usage 1').Append(#10);
      for mValue in FValues.Values do
      begin
        // Fast vergessene Units fallen weg; die Datei wächst nicht ohne Grenze.
        mPoints := Decayed(mValue, mDay);
        if mPoints >= 0.5 then
        begin
          mBuilder.Append(mDay).Append(#9).Append(FormatFloat('0.00', mPoints, TFormatSettings.Invariant))
            .Append(#9).Append(mValue.Name).Append(#10);
        end;
      end;
      FDirty := False;
      FSavedAt := TThread.GetTickCount64;
    finally
      TMonitor.Exit(FLock);
    end;
    mText := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  // Außerhalb der Sperre schreiben; scheitert es, gilt der Stand als geschrieben (Verlust unkritisch).
  FFileSystem.WriteText(FFileName, mText);
end;

{ TIndexCacheWriter }

constructor TIndexCacheWriter.Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
  const AEvents: TIndexCacheEvents; const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>);
begin
  inherited Create;
  FIndex := AIndex;
  FFileSystem := AFileSystem;
  FEvents := AEvents;
  FRequest := ARequest;
  FCancelled := ACancelled;
end;

function TIndexCacheWriter.ReadCache(const AFileName: string): TArray<TIndexCacheEntry>;
begin
  Result := ReadCacheFile(FFileSystem, AFileName, FEvents.Rejected);
end;

function TIndexCacheWriter.ReadHeaders(const AFileName: string): TArray<TIndexCacheEntry>;
begin
  Result := ReadCacheFile(FFileSystem, AFileName, FEvents.Rejected, False);
end;

function TIndexCacheWriter.IndexHolds(const AFileName: string; const AKept: TIndexUnitKept): Boolean;
var
  mWanted: TDictionary<string, Boolean>;
  mKnown: TDictionary<string, string>;
  mPair: TPair<string, string>;
  mFileName: string;
  mUnit: TUnitIndex;
begin
  Result := False;
  if not Assigned(AKept) then
  begin
    Exit;
  end;
  mWanted := TDictionary<string, Boolean>.Create;
  try
    for mFileName in FRequest.Files + FRequest.SearchFiles + FRequest.LibraryFiles do
    begin
      mWanted.AddOrSetValue(AnsiUpperCase(mFileName), True);
    end;
    TSharedCacheWrites.Enter;
    try
      mKnown := TSharedCacheWrites.Written(FFileSystem, AFileName);
      if (mKnown = nil) or (mKnown.Count = 0) then
      begin
        Exit;
      end;
      // Units des Caches, die der Auftrag nicht nennt (andere Projekte, nur über uses erreichte), zählen nicht: Ohne
      // Eintrag liest der Builder sie bei Bedarf aus der Datei.
      for mPair in mKnown do
      begin
        if mWanted.ContainsKey(mPair.Key) and not (FIndex.FindHeader(mPair.Key, mUnit) and
          (TSharedCacheWrites.StateOf(mUnit) = mPair.Value) and AKept(mUnit)) then
        begin
          Exit;
        end;
      end;
      Result := True;
    finally
      TSharedCacheWrites.Leave;
    end;
  finally
    mWanted.Free;
  end;
end;

function TIndexCacheWriter.LoadShared(const AFileName: string; const AKept: TIndexUnitKept;
  out AHold: IInterface): TArray<TIndexCacheEntry>;
var
  mFileName: string;
begin
  AHold := nil;
  Result := nil;
  if AFileName = '' then
  begin
    Exit;
  end;
  if IndexHolds(AFileName, AKept) then
  begin
    if Assigned(FEvents.Skipped) then
    begin
      FEvents.Skipped(AFileName);
    end;
    Exit;
  end;
  mFileName := AFileName;
  Result := TSharedCacheHold.Acquire(FFileSystem, AFileName,
    function: TArray<TIndexCacheEntry>
    begin
      Result := ReadCache(mFileName);
    end, AHold);
end;

function TIndexCacheWriter.Load(const AKept: TIndexUnitKept): TArray<TIndexCacheEntry>;
begin
  // Nur die Köpfe lesen; die Symbole dekodiert der Builder je Unit, wenn er sie übernimmt (#617).
  // Ein beschädigter Cache liefert nichts: Dann liest der Aufbau alles neu (#492).
  FCached := ReadCache(FRequest.CacheFile);
  // Bibliothek aus dem gemeinsamen Cache; Einträge im Projekt-Cache (ältere Stände) gelten weiter.
  // Alle Projekte teilen eine gelesene Kopie (Rückmeldung 15.10.2026); hält der Index den Stand schon, liest es
  // gar nicht (b1).
  FLibraryCached := LoadShared(FRequest.LibraryCacheFile, AKept, FLibraryHold);
  // Suchpfade ebenso: Die Projekte einer Gruppe teilen meist dieselben (Speicher, Rückmeldung 01.11.2026).
  FSearchCached := LoadShared(FRequest.SearchCacheFile, AKept, FSearchHold);
  // Phase 3: Units, die nur im Katalog stehen, lesen ab jetzt aus dieser Fassung der Datei (hat ein anderer Prozess
  // sie ersetzt, lasen sie bisher aus der alten über deren offenes Handle).
  Bind(FLibraryCached);
  Result := FLibraryCached + FSearchCached + FCached;
end;

procedure TIndexCacheWriter.Bind(const AEntries: TArray<TIndexCacheEntry>);
var
  mHeaders: TArray<TUnitIndex>;
  mSources: TArray<IIndexUnitSource>;
  mIndex: Integer;
begin
  if Length(AEntries) = 0 then
  begin
    Exit;
  end;
  SetLength(mHeaders, Length(AEntries));
  SetLength(mSources, Length(AEntries));
  for mIndex := 0 to High(AEntries) do
  begin
    mHeaders[mIndex] := AEntries[mIndex].Header;
    mSources[mIndex] := AEntries[mIndex].Source;
  end;
  FIndex.BindSources(mHeaders, mSources);
end;

procedure TIndexCacheWriter.Release;
begin
  FCached := nil;
  FLibraryCached := nil;
  FSearchCached := nil;
end;

const
  /// <summary>So lange wartet ein Aufbau höchstens darauf, den Bibliotheks-Cache schreiben zu dürfen; ein
  /// anderer Schreiber braucht für Lesen, Ergänzen und Schreiben wenige Sekunden.</summary>
  cLibraryLockWaitMs = 30000;
  cLockPollMs = 100;

function TIndexCacheWriter.LockForWrite(const AFileName: string): IInterface;
var
  mWatch: TStopwatch;
begin
  mWatch := TStopwatch.StartNew;
  Result := FFileSystem.TryLockWrite(AFileName);
  while (Result = nil) and not FCancelled() and (mWatch.ElapsedMilliseconds < cLibraryLockWaitMs) do
  begin
    TThread.Sleep(cLockPollMs);
    Result := FFileSystem.TryLockWrite(AFileName);
  end;
end;

procedure TIndexCacheWriter.NotWritten(const AFileName, AReason: string);
begin
  if Assigned(FEvents.NotWritten) then
  begin
    FEvents.NotWritten(AFileName, AReason);
  end;
end;

function TIndexCacheWriter.WriteCache(ALibrary: Boolean; const AFileName: string;
  const AItems: TArray<TIndexCacheItem>): Boolean;
var
  mPlaces: TArray<TIndexBlockPlace>;
begin
  Result := WriteCache(ALibrary, AFileName, AItems, mPlaces);
end;

function TIndexCacheWriter.WriteCache(ALibrary: Boolean; const AFileName: string;
  const AItems: TArray<TIndexCacheItem>; out APlaces: TArray<TIndexBlockPlace>): Boolean;
var
  mWatch: TStopwatch;
  mError: string;
  mItems: TArray<TIndexCacheItem>;
  mPlaces: TArray<TIndexBlockPlace>;
  mBytes: Int64;
  mUnits: Integer;
begin
  mWatch := TStopwatch.StartNew;
  mItems := AItems;
  mBytes := 0;
  mUnits := 0;
  // Format 34: Block für Block in die temporäre Datei; der ganze Cache liegt nie am Stück im Speicher.
  Result := FFileSystem.WriteStream(AFileName,
    function(AStream: TStream): Boolean
    var
      Start: Int64;
    begin
      Start := AStream.Position;
      mUnits := TIndexCache.Write(AStream, mItems, mPlaces);
      mBytes := AStream.Position - Start;
      Result := True;
    end, mError);
  APlaces := mPlaces;
  if not Result then
  begin
    NotWritten(AFileName, mError);
  end
  else if Assigned(FEvents.Written) then
  begin
    FEvents.Written(ALibrary, mUnits, mBytes, mWatch.ElapsedMilliseconds);
  end;
end;

/// <summary>Stand (TSharedCacheWrites.StateOf) je Datei (groß) aus AItems.</summary>
function StatesOf(const AItems: TArray<TIndexCacheItem>): TDictionary<string, string>;
var
  mIndex: Integer;
begin
  Result := TDictionary<string, string>.Create(Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    Result.AddOrSetValue(AnsiUpperCase(AItems[mIndex].Header.FileName),
      TSharedCacheWrites.StateOf(AItems[mIndex].Header));
  end;
end;

procedure TIndexCacheWriter.BindWritten(const AFileName: string; const AItems: TArray<TIndexCacheItem>;
  const APlaces: TArray<TIndexBlockPlace>; out AReader: IIndexBlockReader; out AHeaders: TArray<TUnitIndex>;
  out ASources: TArray<IIndexUnitSource>);
var
  mIndex, mCount: Integer;
begin
  AHeaders := nil;
  ASources := nil;
  AReader := FFileSystem.OpenBlocks(AFileName);
  // Passt die Datei nicht zur gemeldeten Lage (sollte nicht vorkommen: der Schreiber hält die Sperre), wie früher
  // ihr Verzeichnis lesen.
  for mIndex := 0 to High(APlaces) do
  begin
    if (AReader = nil) or (APlaces[mIndex].Written and
      (APlaces[mIndex].Offset + APlaces[mIndex].Length > AReader.Size)) then
    begin
      AReader := nil;
      Bind(ReadHeaders(AFileName));
      Exit;
    end;
  end;
  SetLength(AHeaders, Length(AItems));
  SetLength(ASources, Length(AItems));
  mCount := 0;
  for mIndex := 0 to Min(High(AItems), High(APlaces)) do
  begin
    if not APlaces[mIndex].Written then
    begin
      Continue;
    end;
    // Nur Name, Datei und Stand: Mehr vergleicht BindSources nicht, und gemerkt hielten sie sonst die Symbole fest.
    AHeaders[mCount] := Default(TUnitIndex);
    AHeaders[mCount].UnitName := AItems[mIndex].Header.UnitName;
    AHeaders[mCount].FileName := AItems[mIndex].Header.FileName;
    AHeaders[mCount].Stamp := AItems[mIndex].Header.Stamp;
    AHeaders[mCount].Hash := AItems[mIndex].Header.Hash;
    ASources[mCount] := TIndexCache.SourceAt(AReader, APlaces[mIndex]);
    Inc(mCount);
  end;
  SetLength(AHeaders, mCount);
  SetLength(ASources, mCount);
  FIndex.BindSources(AHeaders, ASources);
end;

function TIndexCacheWriter.AppendShared(const AFileName: string; AUnits: TList<TIndexCacheItem>): Boolean;
var
  mAppend: IIndexFileAppend;
  mStamp, mBytes: Int64;
  mOld, mReader: IIndexBlockReader;
  mKnown: TDictionary<string, string>;
  mWanted: TDictionary<string, Boolean>;
  mItem: TIndexCacheItem;
  mKey, mError: string;
  mItems: TArray<TIndexCacheItem>;
  mPlaces: TArray<TIndexBlockPlace>;
  mHeaders: TArray<TUnitIndex>;
  mSources: TArray<IIndexUnitSource>;
  mUnits: Integer;
  mWatch: TStopwatch;
begin
  Result := False;
  if not Supports(FFileSystem, IIndexFileAppend, mAppend) or
    not TSharedCacheWrites.LastWrite(FFileSystem, AFileName, mStamp, mOld, mKnown) then
  begin
    Exit;
  end;
  // Units der Datei, die der Auftrag nicht hat (andere Projekte), bräuchten für das neue Verzeichnis ihren Katalog
  // aus der Datei: dann lieber ganz schreiben.
  mWanted := TDictionary<string, Boolean>.Create(AUnits.Count);
  try
    for mItem in AUnits do
    begin
      mWanted.AddOrSetValue(AnsiUpperCase(mItem.Header.FileName), True);
    end;
    for mKey in mKnown.Keys do
    begin
      if not mWanted.ContainsKey(mKey) then
      begin
        Exit;
      end;
    end;
  finally
    mWanted.Free;
  end;
  mWatch := TStopwatch.StartNew;
  mItems := AUnits.ToArray;
  mBytes := 0;
  mUnits := 0;
  Result := mAppend.AppendStream(AFileName, mStamp,
    function(AStream: TStream): Boolean
    var
      Before: Int64;
    begin
      Before := AStream.Size;
      // Blöcke, die der zuletzt gebundene Leser dieser Datei liefert, stehen schon darin.
      mUnits := TIndexCache.Append(AStream, mItems,
        function(const ASource: IIndexUnitSource): Boolean
        begin
          Result := TIndexCache.ReaderOf(ASource) = mOld;
        end, mPlaces);
      mBytes := AStream.Size - Before;
      Result := mUnits >= 0;
    end, mError);
  if not Result then
  begin
    Exit;
  end;
  if Assigned(FEvents.Written) then
  begin
    FEvents.Written(True, mUnits, mBytes, mWatch.ElapsedMilliseconds);
  end;
  BindWritten(AFileName, mItems, mPlaces, mReader, mHeaders, mSources);
  TSharedCacheWrites.Remember(FFileSystem, AFileName, StatesOf(mItems), mReader, mHeaders, mSources);
end;

procedure TIndexCacheWriter.WriteSharedCache(const AFileName: string;
  const AStartCached: TArray<TIndexCacheEntry>; AUnits: TList<TIndexCacheItem>; AUnbound, AAppend: Boolean);
var
  mWritten: TDictionary<string, string>;
  mLock: IInterface;
  mLatest: TArray<TIndexCacheEntry>;
  mOthers, mItems: TArray<TIndexCacheItem>;
  mPlaces: TArray<TIndexBlockPlace>;
  mReader: IIndexBlockReader;
  mHeaders: TArray<TUnitIndex>;
  mSources: TArray<IIndexUnitSource>;
begin
  // Hat in diesem Prozess schon ein Dienst diese Units in die unveränderte Datei geschrieben, gibt es
  // nichts Neues; dann weder sperren noch lesen. Sonst gegen den beim Start gelesenen Stand.
  mWritten := TSharedCacheWrites.Written(FFileSystem, AFileName);
  if ((mWritten <> nil) and AllWritten(mWritten, AUnits)) or ((mWritten = nil) and not MissingIn(AStartCached,
    AUnits)) then
  begin
    // Phase 3: Verdrängbare Units ohne Block (neu gelesen) bekommen ihn aus der Datei, die ein anderer Dienst schon
    // geschrieben hat; Phase 4: aus den dabei gemerkten Blöcken, sonst aus ihrem Verzeichnis.
    if AUnbound then
    begin
      if TSharedCacheWrites.LastSources(FFileSystem, AFileName, mHeaders, mSources) then
      begin
        FIndex.BindSources(mHeaders, mSources);
      end
      else
      begin
        Bind(ReadHeaders(AFileName));
      end;
    end;
    Exit;
  end;
  // Ein Schreiber zur Zeit. Unter der Sperre den aktuellen Stand lesen: Ein anderes Projekt
  // oder ein anderer Prozess kann seit dem Start Units ergänzt haben, die sonst verloren gingen.
  mLock := LockForWrite(AFileName);
  if mLock = nil then
  begin
    // Abgebrochen ist kein Fehler: Der nächste Aufbau ergänzt den Cache.
    if not FCancelled() then
    begin
      NotWritten(AFileName, cTexts[TIndexServiceText.WriteLockNotObtained].Text);
    end;
    Exit;
  end;
  // Phase 4: Zwischenstand des ersten Aufbaus an die eigene, unveränderte Datei anhängen.
  if AAppend and AppendShared(AFileName, AUnits) then
  begin
    Exit;
  end;
  // Erst nur die Stände (Phase 3: ohne Kataloge, die der Index schon hat).
  mLatest := ReadHeaders(AFileName);
  if not MissingIn(mLatest, AUnits) then
  begin
    Bind(mLatest);
    Exit;
  end;
  // Units anderer Projekte bleiben als unveränderte Blöcke der alten Datei (Format 34); für ihren Eintrag im
  // Verzeichnis braucht es ihren Katalog.
  mOthers := OthersOf(mLatest, AUnits);
  if Length(mOthers) > 0 then
  begin
    mLatest := ReadCache(AFileName);
    mOthers := OthersOf(mLatest, AUnits);
  end;
  mLatest := nil;
  mItems := AUnits.ToArray + mOthers;
  if WriteCache(True, AFileName, mItems, mPlaces) then
  begin
    // Der Index liest ab hier aus der neuen Datei; die alte hält nur noch, wer gerade einen Block aus ihr liest. Die
    // Lage der Blöcke meldet Write (Phase 4; vorher las Bind das eben geschriebene Verzeichnis neu).
    BindWritten(AFileName, mItems, mPlaces, mReader, mHeaders, mSources);
    TSharedCacheWrites.Remember(FFileSystem, AFileName, StatesOf(mItems), mReader, mHeaders, mSources);
  end;
end;

/// <summary>Hat der Index verdrängbare (nicht gepinnte, geladene) Bibliotheks-Units ohne Block (Phase 3)?</summary>
function HasUnbound(const AUnits: TArray<TIndexStoredUnit>): Boolean;
var
  mStored: TIndexStoredUnit;
begin
  for mStored in AUnits do
  begin
    if mStored.Loaded and not mStored.Pinned and (mStored.Source = nil) and mStored.Unit_.Library_ then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TIndexCacheWriter.WriteSplit(AParsed: Integer);
var
  mProject, mSearch, mLibrary: TList<TIndexCacheItem>;
  mStored: TArray<TIndexStoredUnit>;
begin
  // Listen statt Array-Anhängen: das kopierte bei jeder Unit das ganze Array.
  mProject := TList<TIndexCacheItem>.Create;
  mSearch := TList<TIndexCacheItem>.Create;
  mLibrary := TList<TIndexCacheItem>.Create;
  try
    // Alle Units, auch die nur im Katalog (Phase 3).
    mStored := FIndex.StoredUnits;
    SortUnits(FRequest, mStored, mProject, mSearch, mLibrary);
    if (AParsed > 0) or (Length(FCached) <> mProject.Count) then
    begin
      WriteCache(False, FRequest.CacheFile, mProject.ToArray);
    end;
    if FRequest.SearchCacheFile <> '' then
    begin
      WriteSharedCache(FRequest.SearchCacheFile, FSearchCached, mSearch, False, False);
    end;
    WriteSharedCache(FRequest.LibraryCacheFile, FLibraryCached, mLibrary, HasUnbound(mStored), False);
  finally
    mLibrary.Free;
    mSearch.Free;
    mProject.Free;
  end;
end;

procedure TIndexCacheWriter.WriteCaches(AParsedTotal: Integer);
var
  mParsed: Integer;
begin
  mParsed := AParsedTotal - FWrittenParsed;
  FWrittenParsed := AParsedTotal;
  if (FRequest.CacheFile = '') or FRequest.ReadOnlyCache then
  begin
    Exit;
  end;
  // Immer nur ein Dienst des Prozesses serialisiert (Rückmeldung 22.10.2026): Die Projekte einer Gruppe
  // enden fast gleichzeitig, jede Serialisierung belegt kurzzeitig ein Vielfaches der Datei. Gegen andere
  // Prozesse schützt die Schreibsperre der Datei.
  TSharedCacheWrites.Enter;
  try
    if FRequest.LibraryCacheFile <> '' then
    begin
      WriteSplit(mParsed);
    end
    else if (mParsed > 0) or (Length(FCached) <> FIndex.UnitCount) then
    begin
      WriteCache(False, FRequest.CacheFile, ItemsOf(FIndex.StoredUnits));
    end;
  finally
    TSharedCacheWrites.Leave;
  end;
end;

procedure TIndexCacheWriter.FlushLibrary;
var
  mProject, mSearch, mLibrary: TList<TIndexCacheItem>;
  mStored: TArray<TIndexStoredUnit>;
begin
  // Wie WriteCaches, aber nur die Bibliothek und ohne die Zahl gelesener Units fortzuschreiben: Den Projekt-Cache
  // schreibt erst das Ende des Aufbaus (Phase 4).
  if (FRequest.CacheFile = '') or FRequest.ReadOnlyCache or (FRequest.LibraryCacheFile = '') then
  begin
    Exit;
  end;
  TSharedCacheWrites.Enter;
  try
    mProject := TList<TIndexCacheItem>.Create;
    mSearch := TList<TIndexCacheItem>.Create;
    mLibrary := TList<TIndexCacheItem>.Create;
    try
      mStored := FIndex.StoredUnits;
      SortUnits(FRequest, mStored, mProject, mSearch, mLibrary);
      WriteSharedCache(FRequest.LibraryCacheFile, FLibraryCached, mLibrary, HasUnbound(mStored), True);
    finally
      mLibrary.Free;
      mSearch.Free;
      mProject.Free;
    end;
  finally
    TSharedCacheWrites.Leave;
  end;
end;

/// <summary>Nach der Projektstufe schon schreiben (#647): In einer Projektgruppe endet der ganze Aufbau erst nach
/// allen Projekten; wer die IDE vorher schließt, begann sonst jedes Mal von vorn.</summary>
function ProjectDoneHandler(ACaches: TIndexCacheWriter; const AWatch: TStopwatch;
  const AReady: TIndexFinishedEvent): TIndexStageDone;
var
  mWatch: TStopwatch;
begin
  mWatch := AWatch;
  Result :=
    procedure(const APartial: TIndexBuildResult)
    begin
      ACaches.WriteCaches(APartial.Parsed);
      if Assigned(AReady) then
      begin
        AReady(APartial, mWatch.ElapsedMilliseconds);
      end;
    end;
end;

/// <summary>Erster Start mit LazyLibrary (Phase 3): den Bibliotheks-Cache zwischendurch schreiben (Phase 4: nur ihn,
/// angehängt); danach bekommen die neu gelesenen Bibliotheks-Units ihre Blöcke und dürfen verdrängt werden. Begrenzt
/// die Spitze des Aufbaus ohne Cache.</summary>
function LibraryFlushHandler(ACaches: TIndexCacheWriter): TIndexStageDone;
begin
  Result :=
    procedure(const APartial: TIndexBuildResult)
    begin
      ACaches.FlushLibrary;
    end;
end;

/// <summary>Abbruchabfrage des Dienstes für den Builder.</summary>
function BuilderCancelled(const ACancelled: TFunc<Boolean>): TIndexCancelled;
begin
  Result :=
    function: Boolean
    begin
      Result := ACancelled();
    end;
end;

/// <summary>Rückruf für TIndexCacheWriter.Load: TIndexBuilder.Keeps des neuen Builders (b1).</summary>
function BuilderKeeps(ABuilder: TIndexBuilder): TIndexUnitKept;
begin
  Result :=
    function(const AUnit: TUnitIndex): Boolean
    begin
      Result := ABuilder.Keeps(AUnit);
    end;
end;

function TIndexService.PrepareBuilder(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>;
  ACaches: TIndexCacheWriter): TIndexBuilder;
begin
  Result := TIndexBuilder.Create(FIndex, FFileSystem, ARequest.Defines, ARequest.ResolveUnit);
  try
    Result.IncludePaths := ARequest.IncludePaths;
    Result.LibraryRoots := ARequest.LibraryRoots;
    Result.LibraryDefines := ARequest.LibraryDefines;
    Result.Usages := ARequest.Usages;
    Result.RarelyUsedRoots := ARequest.RarelyUsedRoots;
    Result.LazyLibrary := ARequest.LazyLibrary;
    UseStatistics(ARequest);
    Result.Usage := FIndex.Usage;
    if Assigned(ARequest.Prepare) then
    begin
      ARequest.Prepare();
    end;
    WaitForOtherWriter(ARequest, ACancelled);
    TMonitor.Enter(FLock);
    try
      FCacheFile := ARequest.CacheFile;
    finally
      TMonitor.Exit(FLock);
    end;
    Result.UseCache(ACaches.Load(BuilderKeeps(Result)));
  except
    // Noch nicht veröffentlicht: sonst bliebe der Builder als Leck zurück.
    Result.Free;
    raise;
  end;
end;

procedure TIndexService.Run(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>);
var
  mCaches: TIndexCacheWriter;
  mBuilder: TIndexBuilder;
  mWatch: TStopwatch;
  mResult: TIndexBuildResult;
  mTurn: IIndexTurn;
begin
  mCaches := TIndexCacheWriter.Create(FIndex, FFileSystem, FCacheEvents, ARequest, ACancelled);
  try
    try
      mWatch := TStopwatch.StartNew;
      mBuilder := PrepareBuilder(ARequest, ACancelled, mCaches);
      // Erst mit gefülltem Cache veröffentlichen; bis dahin bedient der alte Builder EnsureUnit.
      // Ab hier gehört der Builder dem Dienst.
      ReplaceBuilder(mBuilder);
      mTurn := nil;
      if FScheduler <> nil then
      begin
        mTurn := FScheduler.Register(ARequest.Priority);
      end;
      mTurn := FStages.Watch(mTurn);
      mBuilder.OnProjectDone := ProjectDoneHandler(mCaches, mWatch, FOnProjectReady);
      mBuilder.OnLibraryFlush := LibraryFlushHandler(mCaches);
      mResult := mBuilder.Build(ARequest.Files, ARequest.SearchFiles, ARequest.LibraryFiles, FOnProgress,
        BuilderCancelled(ACancelled), mTurn);
      mBuilder.OnProjectDone := nil;
      mBuilder.OnLibraryFlush := nil;
      // Abmelden vor dem Schreiben des Caches: Das nächste Projekt muss darauf nicht warten.
      mTurn := nil;
      if not mResult.Cancelled then
      begin
        mCaches.WriteCaches(mResult.Parsed);
      end;
      // Der Index hat alles übernommen; spätere Units (EnsureUnit) liest der Builder aus der Datei. Auch nach
      // einem Abbruch: Sonst hielt der Builder die Einträge samt String-Tabellen ganzer Cache-Dateien, bis ein
      // neuer Aufbau ihn ersetzte, und ein abgebrochener Aufbau ohne Nachfolger behielt sie (Speicher,
      // Rückmeldung 01.11.2026).
      mBuilder.ReleaseCache;
      mCaches.Release;
      // Die Ablage gleicher Zeichenketten braucht nur der Aufbau selbst (rund 6 MB bei der Bibliothek).
      FIndex.ReleaseStringPool;
      if Assigned(FOnFinished) then
      begin
        FOnFinished(mResult, mWatch.ElapsedMilliseconds);
      end;
    except
      // lsp-ignore: catch-all-without-raise -- Fehlergrenze des Hintergrundlaufs; ReportError meldet
      on E: Exception do
        ReportError(E);
    end;
  finally
    FStages.Clear;
    // Gemeinsame Kopien freigeben (TSharedCacheHold), auch nach einer Ausnahme.
    mCaches.Free;
  end;
end;

function TIndexService.StageState: TIndexStageState;
begin
  Result := FStages.State;
end;

procedure TIndexService.ReportError(const AError: Exception);
begin
  if not Assigned(FOnError) then
  begin
    Exit;
  end;
  try
    FOnError(AError);
  except
    // Sonst läge die Ausnahme ungelesen in TThread.FatalException.
  end;
end;

procedure TIndexService.UseStatistics(const ARequest: TIndexRequest);
var
  mFile: string;
  mCurrent: IIndexUsage;
begin
  mFile := TIndexUsageStats.FileFor(ARequest.LibraryCacheFile);
  if not ARequest.LazyLibrary or (mFile = '') then
  begin
    Exit;
  end;
  mCurrent := FIndex.Usage;
  if (mCurrent <> nil) and SameText(mCurrent.FileName, mFile) then
  begin
    Exit;
  end;
  // Die bisherige (andere Bibliothek) vorher schreiben.
  SaveStatistics(True);
  FIndex.SetUsage(TIndexUsageStats.Create(FFileSystem, mFile));
end;

const
  /// <summary>So oft sieht SaveStatistics(False) höchstens nach (die Statistik selbst schreibt alle 10 Minuten).
  /// </summary>
  cSaveCheckMs = 60 * 1000;

procedure TIndexService.SaveStatistics(AForce: Boolean);
var
  mUsage: IIndexUsage;
  mNow: Int64;
begin
  if not AForce then
  begin
    // Phase 4: Läuft bei jeder Anfrage (ApplyText, EnsureUnit). Fälligkeit ohne Sperre und Allokation; geschrieben
    // wird im Hintergrund, nicht im Thread der Anfrage.
    mNow := Int64(TThread.GetTickCount64);
    if mNow < TInterlocked.Read(FNextSaveCheck) then
    begin
      Exit;
    end;
    TInterlocked.Exchange(FNextSaveCheck, mNow + cSaveCheckMs);
    SaveInBackground;
    Exit;
  end;
  WaitForSave;
  mUsage := FIndex.Usage;
  if mUsage is TIndexUsageStats then
  begin
    TIndexUsageStats(mUsage).SaveIfDue(True);
  end;
end;

procedure TIndexService.SaveInBackground;
var
  mUsage: IIndexUsage;
  mDone: TThread;
begin
  mUsage := FIndex.Usage;
  if not (mUsage is TIndexUsageStats) then
  begin
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    if (FSaveThread <> nil) and not FSaveThread.Finished then
    begin
      Exit;
    end;
    mDone := FSaveThread;
    FSaveThread := TThread.CreateAnonymousThread(
      procedure
      begin
        TThread.NameThreadForDebugging('dpcc.UsageSave');
        TIndexUsageStats(mUsage).SaveIfDue(False);
      end);
    FSaveThread.FreeOnTerminate := False;
    FSaveThread.Start;
  finally
    TMonitor.Exit(FLock);
  end;
  // Der vorige ist fertig (Finished); freigeben außerhalb der Sperre.
  mDone.Free;
end;

procedure TIndexService.WaitForSave;
var
  mThread: TThread;
begin
  TMonitor.Enter(FLock);
  try
    mThread := FSaveThread;
    FSaveThread := nil;
  finally
    TMonitor.Exit(FLock);
  end;
  if mThread <> nil then
  begin
    mThread.WaitFor;
    mThread.Free;
  end;
end;

procedure TIndexService.WaitForOtherWriter(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>);
var
  mWatch: TStopwatch;
  mBefore, mStamp: Int64;
begin
  if (ARequest.CacheFile = '') or not ARequest.ReadOnlyCache or not Assigned(ARequest.CacheBusy) then
  begin
    Exit;
  end;
  if not FFileSystem.FileStamp(ARequest.CacheFile, mBefore) then
  begin
    mBefore := 0;
  end;
  mWatch := TStopwatch.StartNew;
  // Bis die andere Instanz einen neuen Stand geschrieben oder die Sperre freigegeben hat,
  // nie länger als CacheWaitMs.
  while not ACancelled() and (mWatch.ElapsedMilliseconds < ARequest.CacheWaitMs) and ARequest.CacheBusy() do
  begin
    if FFileSystem.FileStamp(ARequest.CacheFile, mStamp) and (mStamp <> mBefore) then
    begin
      Exit;
    end;
    TThread.Sleep(200);
  end;
end;

procedure TIndexService.Start(const ARequest: TIndexRequest);
var
  mPrevious: TThread;
begin
  // Nicht warten (#874): Der neue Thread wartet auf den abgebrochenen und gibt ihn frei.
  mPrevious := FThread;
  FThread := nil;
  if mPrevious <> nil then
  begin
    TIndexThread(mPrevious).Cancel;
  end;
  FThread := TIndexThread.Create(Self, ARequest, mPrevious);
end;

class procedure TIndexService.ForgetSharedStates;
begin
  TSharedCacheWrites.Clear;
end;

procedure TIndexService.Stop;
begin
  // Nutzungsstatistik beim Stopp schreiben (Phase 3).
  SaveStatistics(True);
  if FThread = nil then
  begin
    Exit;
  end;
  TIndexThread(FThread).Cancel;
  FThread.WaitFor;
  FreeAndNil(FThread);
end;

procedure TIndexService.WaitFor;
begin
  if FThread <> nil then
  begin
    FThread.WaitFor;
  end;
end;

function TIndexService.AcquireBuilder: TIndexBuilder;
begin
  TMonitor.Enter(FLock);
  try
    Result := FBuilder;
    if Result <> nil then
    begin
      Inc(FUsers);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexService.ReleaseBuilder;
begin
  TMonitor.Enter(FLock);
  try
    Dec(FUsers);
    if FUsers = 0 then
    begin
      TMonitor.PulseAll(FLock);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexService.ReplaceBuilder(ABuilder: TIndexBuilder);
var
  mOld: TIndexBuilder;
begin
  TMonitor.Enter(FLock);
  try
    // Neue Anfragen sehen sofort den neuen Builder; der alte wird frei, sobald niemand ihn nutzt.
    mOld := FBuilder;
    FBuilder := nil;
    while FUsers > 0 do
    begin
      TMonitor.Wait(FLock, INFINITE);
    end;
    FBuilder := ABuilder;
  finally
    TMonitor.Exit(FLock);
  end;
  mOld.Free;
end;

function TIndexService.EnsureUnit(const AUnitName: string): Boolean;
var
  mBuilder: TIndexBuilder;
  mExisting: TUnitIndex;
begin
  // Höchstens alle 10 Minuten; Anfragen sind die Gelegenheit dazu (Phase 3).
  SaveStatistics(False);
  mBuilder := AcquireBuilder;
  if mBuilder = nil then
  begin
    Exit(FIndex.FindUnit(AUnitName, mExisting));
  end;
  try
    Result := mBuilder.EnsureUnit(AUnitName);
  finally
    ReleaseBuilder;
  end;
end;

function TIndexService.ApplyText(const AFileName, AText: string): Boolean;
var
  mBuilder: TIndexBuilder;
begin
  SaveStatistics(False);
  mBuilder := AcquireBuilder;
  if mBuilder = nil then
  begin
    Exit(False);
  end;
  try
    TMonitor.Enter(FApplyLock);
    try
      Result := mBuilder.ApplyText(AFileName, AText);
    finally
      TMonitor.Exit(FApplyLock);
    end;
  finally
    ReleaseBuilder;
  end;
end;

function TIndexService.UsagesOf(const AFileName: string; out AUsages: TArray<TIndexUsage>): Boolean;
var
  mExisting: TUnitIndex;
  mCacheFile: string;
  mEntry: TIndexCacheEntry;
  mBuilder: TIndexBuilder;
begin
  AUsages := nil;
  if not FIndex.FindFile(AFileName, mExisting) or not mExisting.UsagesIndexed then
  begin
    Exit(False);
  end;
  if not mExisting.UsagesOffloaded then
  begin
    AUsages := mExisting.Usages;
    Exit(True);
  end;
  // Ausgelagert: aus dem Cache, wenn er denselben Stand der Unit hat.
  TMonitor.Enter(FLock);
  try
    mCacheFile := FCacheFile;
  finally
    TMonitor.Exit(FLock);
  end;
  for mEntry in ReadCacheFile(FFileSystem, mCacheFile, FCacheEvents.Rejected) do
  begin
    if SameText(mEntry.Header.FileName, AFileName) and (mEntry.Header.Hash = mExisting.Hash) and
      mEntry.Header.UsagesIndexed then
    begin
      Exit(TIndexCache.ExpandUsages(mEntry, AUsages));
    end;
  end;
  // Noch nicht geschrieben (neu eingelesen): aus der Datei.
  mBuilder := AcquireBuilder;
  if mBuilder = nil then
  begin
    Exit(False);
  end;
  try
    Result := mBuilder.ReadUsages(AFileName, AUsages);
  finally
    ReleaseBuilder;
  end;
end;

function TIndexService.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
var
  mBuilder: TIndexBuilder;
begin
  mBuilder := AcquireBuilder;
  if mBuilder = nil then
  begin
    Exit(0);
  end;
  try
    TMonitor.Enter(FApplyLock);
    try
      Result := mBuilder.ApplyChanges(AChanges);
    finally
      TMonitor.Exit(FApplyLock);
    end;
  finally
    ReleaseBuilder;
  end;
end;

initialization
  TDpccTextTables.Add('dpcc.Common.Index.Service', cTexts);

end.
