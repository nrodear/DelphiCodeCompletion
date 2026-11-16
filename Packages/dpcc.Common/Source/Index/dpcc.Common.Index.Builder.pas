unit dpcc.Common.Index.Builder;

// Baut den Symbolindex auf.
//
// - Build: indiziert die Projektdateien. Einträge aus dem Cache gelten
//   weiter, wenn der Zeitstempel gleich ist (Datei wird nicht gelesen) oder
//   der Hash des Inhalts gleich ist (nur der Zeitstempel wird erneuert).
// - Danach werden die referenzierten Units (uses) bedarfsweise über den
//   Resolver gesucht und indiziert, rekursiv, aber nur was wirklich in einer
//   uses-Liste vorkommt. So kommen RTL und VCL nur teilweise in den Index.
// - EnsureUnit indiziert eine einzelne Unit nachträglich.
// - ApplyChanges übernimmt Dateiänderungen von außen (git checkout,
//   andere Werkzeuge): bekannte Units neu einlesen, gelöschte entfernen.
//   Neue Dateien kommen erst in den Index, wenn sie referenziert werden;
//   dafür vergisst der Builder die bisher nicht gefundenen Units.
// - Include-Dateien (#264) werden über IncludePaths gesucht. Units mit
//   Includes übernimmt der Builder aus dem Cache nur, wenn auch alle
//   Include-Dateien denselben Zeitstempel haben (#617); eine geänderte
//   Include-Datei liest alle Units neu ein, die sie einbinden.
// - Aus dem Cache kommen zunächst nur die Köpfe; die Symbole einer Unit
//   dekodiert der Builder erst, wenn er die Unit übernimmt (#617).
// - Mit Usages (#492, index.usages) erfasst der Builder in Projekt-Units auch
//   die Verwendungen der Bezeichner. Ein Cache-Eintrag ohne sie gilt dann als
//   veraltet; ohne Usages bleiben Verwendungen aus dem Cache weg.
// - Projekt-Units bekommen beim Einlesen ihre Folgemuster (#1890, gelernte
//   Vorschläge); sie kommen mit dem Eintrag in den Cache. Bibliotheken nicht.
// - Läuft im aufrufenden Thread; den Hintergrund-Thread stellt die
//   Komposition bereit.
// - Jede Datei liest nur ein Thread zur selben Zeit (#1236): Fragen Aufbau und
//   Anfragen (EnsureUnit) dieselbe Unit gleichzeitig an, wartet der zweite
//   auf den ersten und übernimmt sein Ergebnis; sonst parsten beim Start
//   mehrere Anfrage-Threads und der Aufbau dieselben RTL-/VCL-Units doppelt.
//   Verschiedene Units laufen parallel (#617).
// - ReleaseCache gibt die Cache-Einträge nach dem Aufbau frei (Rückmeldung
//   15.10.2026): Jeder Eintrag hält die ganze gelesene Cache-Datei; mit sechs
//   Projekten lagen so Projekt- und Bibliotheks-Cache sechsmal im Speicher,
//   obwohl der Index sie längst übernommen hatte.
// - Bedarfsweises Laden (Speicher-Optimierung Phase 3, LazyLibrary): Die
//   Bibliotheksstufe übernimmt Units aus dem Cache nur mit Kopf, Katalog und
//   Block (ISymbolIndex.AddCold); neu gelesene kommen verdrängbar in den Index
//   (AddEvictable). Die Projektstufe (Projektdateien und ihre uses-Hülle wie
//   IndexReferenced) lädt und pinnt; trifft sie auf eine Unit, die nur im
//   Katalog steht, lädt und pinnt sie diese und folgt ihren uses. Oft genutzte
//   Units (Nutzungsstatistik, Usage) lädt auch die Bibliotheksstufe gleich.
//   Ohne Cache (erster Start) liest die Bibliotheksstufe alle Units neu; sie
//   bleiben im Speicher, bis ihr Block im Cache steht. Damit die Spitze dabei
//   begrenzt bleibt, ruft sie OnLibraryFlush, sobald neu gelesene Units rund
//   cFlushBytes belegen: Der Dienst schreibt dann den Bibliotheks-Cache, und der
//   Index darf diese Units verdrängen.
//   Entscheidungen über den Stand einer Unit (AlreadyIndexed, Stufen) laden
//   nichts nach (FindHeader).

interface

uses
  System.SysUtils,
  System.Diagnostics,
  System.Generics.Collections,
  dpcc.Common.Pascal.Preprocessor,
  dpcc.Common.Index.Contract,
  dpcc.Common.Index.Cache;

type
  /// <summary>Warum der Builder eine Unit neu einlas statt aus dem Cache (Diagnoselog, Rückmeldung
  /// 22.10.2026: bei jedem Start rund 2300 Units neu): kein Eintrag, Datei geändert, Include-Datei geändert,
  /// Verwendungen fehlen, kompakter Eintrag nicht verwendbar, Block beschädigt.</summary>
  TIndexCacheMiss = (NoEntry, Changed, Includes, Usages, Compact, Damaged);

  TIndexBuildResult = record
    Parsed: Integer;
    /// <summary>Parsed nach Grund; die Summe ist Parsed.</summary>
    Misses: array[TIndexCacheMiss] of Integer;
    FromCache: Integer;
    Missing: Integer;
    /// <summary>Zeit für das Suchen der Unit-Dateien (uses) und für das Parsen, fürs Diagnoselog (#647).</summary>
    ResolveMs: Int64;
    ParseMs: Int64;
    Cancelled: Boolean;
  end;

  /// <summary>Eine Stufe des Aufbaus ist fertig; APartial ist der Stand bis dahin.</summary>
  TIndexStageDone = reference to procedure(const APartial: TIndexBuildResult);

  /// <summary>Defines je Datei (#647): Dateien unter LibraryRoots (Delphi-Installation) mit LibraryDefines, alle
  /// anderen mit denen des Projekts.</summary>
  TIndexFileDefines = record
    Project: TArray<string>;
    LibraryDefines: TArray<string>;
    LibraryRoots: TArray<string>;
    function DefinesOf(const AFileName: string): TArray<string>;
    /// <summary>Schlüssel der Defines für AFileName (TUnitIndex.DefinesKey).</summary>
    function KeyOf(const AFileName: string): string;
    /// <summary>Liegt AFileName unter einem der Ordner aus ARoots?</summary>
    class function IsUnder(const AFileName: string; const ARoots: TArray<string>): Boolean; static;
  end;

  /// <summary>Threadsichere Menge von Schlüsseln (Großschreibung) für den Builder: nicht gefundene Units und
  /// Dateien, die gerade ein Thread liest (#1236).</summary>
  TIndexKeySet = class
  private
    FKeys: TDictionary<string, Boolean>;
    FLock: TObject;
  public
    constructor Create;
    destructor Destroy; override;
    function Contains(const AKey: string): Boolean;
    procedure Add(const AKey: string);
    /// <summary>Entfernt AKey und weckt alle, die in Claim darauf warten.</summary>
    procedure Remove(const AKey: string);
    procedure Clear;
    /// <summary>Wartet, bis AKey frei ist, und trägt ihn ein. False (nicht eingetragen), wenn gewartet wurde und
    /// AAlreadyDone danach gilt: Dann hat ein anderer Thread die Arbeit schon erledigt.</summary>
    function Claim(const AKey: string; const AAlreadyDone: TFunc<Boolean>): Boolean;
  end;

  /// <summary>Threadsicherer Vergleichsstand aus dem Cache: EnsureUnit liest ihn aus Anfrage-Threads,
  /// ReleaseCache leert ihn.</summary>
  TIndexCacheEntries = class
  private
    FEntries: TDictionary<string, TIndexCacheEntry>;
    FLock: TObject;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AFileName: string; const AEntry: TIndexCacheEntry);
    function TryGet(const AFileName: string; out AEntry: TIndexCacheEntry): Boolean;
    procedure Clear;
    function Count: Integer;
  end;

  /// <summary>Was alle Stufen eines Aufbaus teilen: Fortschritt, Abbruch, Reihenfolge mehrerer Aufbauten,
  /// Gesamtzahl der Dateien für die Prozentangabe.</summary>
  TIndexStageRun = record
    Progress: TIndexProgressEvent;
    Cancelled: TIndexCancelled;
    Turn: IIndexTurn;
    Total: Integer;
  end;

  TIndexBuilder = class
  public const
    /// <summary>Ab so vielen (geschätzten) Bytes neu gelesener Units ruft die Bibliotheksstufe OnLibraryFlush. Seit
    /// Phase 4 hängt ein Zwischenstand nur die neuen Blöcke an: halb so viel wie vorher (32 MB), das senkt die Spitze
    /// des ersten Aufbaus, ohne dass die Datei öfter ganz geschrieben wird.</summary>
    cFlushBytes = 16 * 1024 * 1024;
  private
    FIndex: ISymbolIndex;
    FFileSystem: IIndexFileSystem;
    FResolveUnit: TUnitFileResolver;
    FCache: TIndexCacheEntries;
    // Von EnsureUnit aus Anfrage-Threads genutzt.
    FFailedUnits: TIndexKeySet;
    // Dateien, die gerade ein Thread liest.
    FInFlight: TIndexKeySet;
    FIncludePaths: TArray<string>;
    FDefines: TIndexFileDefines;
    FUsages: Boolean;
    FOnProjectDone: TIndexStageDone;
    FRarelyUsedRoots: TArray<string>;
    FLazyLibrary: Boolean;
    FUsage: IIndexUsage;
    FOnLibraryFlush: TIndexStageDone;
    // Geschätzte Bytes der neu gelesenen, noch nicht im Cache stehenden Units seit dem letzten OnLibraryFlush.
    FUnboundBytes: Int64;
    function WantsUsages(ALibrary: Boolean): Boolean;
    /// <summary>Oft genutzte Unit (Nutzungsstatistik): beim Aufbau laden und nie verdrängen.</summary>
    function Hot(const AUnitName: string): Boolean;
    /// <summary>Übernimmt den Cache-Eintrag nur mit Kopf, Katalog und Block (Phase 3).</summary>
    procedure AddColdFrom(const AEntry: TIndexCacheEntry; AStamp: Int64; ALibrary: Boolean);
    /// <summary>Taugt der Cache-Eintrag? AMiss nennt bei False den Grund.</summary>
    function CacheFits(const AEntry: TIndexCacheEntry; ALibrary: Boolean; out AMiss: TIndexCacheMiss): Boolean;
    function FromCache(const AEntry: TIndexCacheEntry; ALibrary: Boolean; out AUnit: TUnitIndex): Boolean;
    function IncludeResolver: TIncludeResolver;
    /// <summary>Steht AFileName mit Stand AStamp schon passend im Index, z. B. von einem anderen Projekt der
    /// Gruppe mit denselben Defines? Dann nicht noch einmal übernehmen.</summary>
    function AlreadyIndexed(const AFileName: string; AStamp: Int64; ALibrary: Boolean): Boolean;
    /// <summary>Indiziert AFileName; liest ein anderer Thread die Datei gerade, wartet es auf ihn und übernimmt sein
    /// Ergebnis (#1236).</summary>
    /// <summary>ALazy (Bibliotheksstufe mit LazyLibrary): aus dem Cache nur Kopf und Katalog, neu gelesen
    /// verdrängbar.</summary>
    function IndexFile(const AFileName: string; ALibrary: Boolean; var AResult: TIndexBuildResult;
      ALazy: Boolean = False): Boolean;
    function IndexFileNow(const AFileName: string; ALibrary: Boolean; var AResult: TIndexBuildResult;
      ALazy: Boolean): Boolean;
    /// <summary>Liest AText neu ein und übernimmt die Unit in den Index (Parsed); mit ALazy verdrängbar.</summary>
    procedure ParseFile(const AFileName, AText, AHash: string; AStamp: Int64; ALibrary, ALazy: Boolean;
      var AResult: TIndexBuildResult);
    procedure IndexReferenced(var AResult: TIndexBuildResult; const ARun: TIndexStageRun);
    /// <summary>Holt die über uses genannte Unit AName in den Index, falls nötig; AUses sind die uses, denen der
    /// Aufbau weiter folgt, ALibrary sagt, ob AName eine Unit der Installation (LibraryRoots) ist. False, wenn es
    /// nichts zu folgen gibt. AFromLibrary: Eine Unit der Installation nennt AName; dann keine Unit unter
    /// RarelyUsedRoots.</summary>
    function NextReferenced(const AName: string; AFromLibrary: Boolean; var AResult: TIndexBuildResult;
      const AProgress: TIndexProgressEvent; out AUses: TArray<string>; out ALibrary: Boolean): Boolean;
    /// <summary>Eine Stufe (#648): AFiles einlesen, in der Projektstufe auch über uses erreichbare Units. Wartet über
    /// ARun.Turn auf ihre Reihe; False bei Abbruch (dann ist AResult.Cancelled gesetzt).</summary>
    function RunStage(AStage: TIndexStage; const AFiles: TArray<string>; const ALabel: string; ADone: Integer;
      var AResult: TIndexBuildResult; const ARun: TIndexStageRun): Boolean;
    /// <summary>Eine Dateiänderung übernehmen; liefert die Zahl geänderter Units.</summary>
    function ApplyChange(const AChange: TFileChange; var AIgnored: TIndexBuildResult): Integer;
  public
    constructor Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
      const ADefines: TArray<string>; const AResolveUnit: TUnitFileResolver);
    destructor Destroy; override;
    /// <summary>Übernimmt einen geladenen Cache als Vergleichsstand.</summary>
    procedure UseCache(const AUnits: TArray<TUnitIndex>); overload;
    /// <summary>Übernimmt die Köpfe eines Caches; Symbole werden erst bei Bedarf dekodiert.</summary>
    procedure UseCache(const AEntries: TArray<TIndexCacheEntry>); overload;
    /// <summary>Gibt die Cache-Einträge frei (nach dem Aufbau); spätere Units liest der Builder aus der Datei.
    /// Threadsicher.</summary>
    procedure ReleaseCache;
    /// <summary>Zahl der gehaltenen Cache-Einträge (für Tests).</summary>
    function CachedCount: Integer;
    /// <summary>Übernähme dieser Aufbau AUnit aus dem Index unverändert (gleiche Defines, Verwendungen und Art wie
    /// AlreadyIndexed, ohne Blick auf Datei und Includes)? Dann braucht er ihren Cache-Eintrag nicht (b1). Erst nach
    /// LibraryRoots, LibraryDefines und Usages gültig.</summary>
    function Keeps(const AUnit: TUnitIndex): Boolean;
    function Build(const AFiles: TArray<string>; const AProgress: TIndexProgressEvent;
      const ACancelled: TIndexCancelled): TIndexBuildResult; overload;
    /// <summary>Aufbau in Stufen (#648): AFiles samt über uses erreichbarer Units, dann ASearchFiles (Projekt),
    /// dann ALibraryFiles (Bibliothek). ATurn ordnet die Stufen mehrerer Aufbauten; nil = ohne Warten.
    /// Nach der Projektstufe läuft OnProjectDone.</summary>
    function Build(const AFiles, ASearchFiles, ALibraryFiles: TArray<string>; const AProgress: TIndexProgressEvent;
      const ACancelled: TIndexCancelled; const ATurn: IIndexTurn): TIndexBuildResult; overload;
    /// <summary>Indiziert die Unit, falls noch nicht vorhanden. False, wenn sie nicht gefunden wird.</summary>
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>Übernimmt Dateiänderungen; liefert die Zahl geänderter Units.</summary>
    function ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
    /// <summary>Ungespeicherter Text einer bekannten Unit (Tipp-Pause, #492): nur im Speicher, ohne Cache;
    /// True, wenn der Index sich dadurch geändert hat.</summary>
    function ApplyText(const AFileName, AText: string): Boolean;
    /// <summary>Suchpfade für $I nach dem Ordner der Unit (Projekt-Suchpfade, dann Bibliothekspfade).</summary>
    property IncludePaths: TArray<string> read FIncludePaths write FIncludePaths;
    /// <summary>Verwendungen der Bezeichner in Projekt-Units erfassen (#492); Standard aus.</summary>
    property Usages: Boolean read FUsages write FUsages;
    /// <summary>Verwendungen einer Unit frisch aus der Datei (ausgelagert und nicht im Cache).</summary>
    function ReadUsages(const AFileName: string; out AUsages: TArray<TIndexUsage>): Boolean;
    /// <summary>Ordner der Delphi-Installation (BDS-Ordner) samt Unterordnern.
    /// Deren Units kommen als fertige DCUs; die Defines des Projekts wirken nicht auf sie. Leer = alle
    /// Dateien mit den Defines des Projekts.</summary>
    property LibraryRoots: TArray<string> read FDefines.LibraryRoots write FDefines.LibraryRoots;
    /// <summary>Symbole für Dateien unter LibraryRoots: nur die des Compilers (Plattform, Version).</summary>
    property LibraryDefines: TArray<string> read FDefines.LibraryDefines write FDefines.LibraryDefines;
    /// <summary>Läuft nach der Projektstufe (Projektdateien und über uses erreichbare Units) mit dem Stand bis
    /// dahin, z. B. um den Projekt-Cache früh zu schreiben (#647).</summary>
    property OnProjectDone: TIndexStageDone read FOnProjectDone write FOnProjectDone;
    /// <summary>Ordner selten genutzter Bibliotheken (c1: OCX\Servers, WinRT). Ihre Units liest die Projektstufe nur
    /// ein, wenn eine Unit außerhalb der Installation (LibraryRoots) sie in den uses nennt, nicht über die uses der
    /// Bibliothek; EnsureUnit lädt sie weiter bei Bedarf. Leer = keine Ausnahme.</summary>
    property RarelyUsedRoots: TArray<string> read FRarelyUsedRoots write FRarelyUsedRoots;
    /// <summary>Bibliotheksstufe lädt nur Kopf und Katalog (Speicher-Optimierung Phase 3); Standard aus.</summary>
    property LazyLibrary: Boolean read FLazyLibrary write FLazyLibrary;
    /// <summary>Nutzungsstatistik: oft genutzte Units lädt auch die Bibliotheksstufe gleich; nil = keine.</summary>
    property Usage: IIndexUsage read FUsage write FUsage;
    /// <summary>Läuft in der Bibliotheksstufe mit LazyLibrary, sobald neu gelesene Units ohne Block rund cFlushBytes
    /// belegen (Phase 3): z. B. den Bibliotheks-Cache schreiben, damit der Index sie verdrängen darf.</summary>
    property OnLibraryFlush: TIndexStageDone read FOnLibraryFlush write FOnLibraryFlush;
  end;

implementation

uses
  dpcc.Common.Pascal.IncludeFiles,
  dpcc.Common.Index.Memory,
  dpcc.Common.Index.Extractor,
  dpcc.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TBuilderText = (SymbolIndex, SearchPaths, LibraryText, UnitsSymbols);

const
  cTexts: array[TBuilderText] of TDpccText = (
    (De: 'Symbolindex'; En: 'Symbol index'),
    (De: 'Suchpfade: '; En: 'Search paths: '),
    (De: 'Bibliothek: '; En: 'Library: '),
    (De: '%d Units, %d Symbole'; En: '%d units, %d symbols'));

{$SCOPEDENUMS OFF}

function IsCancelled(const ACancelled: TIndexCancelled): Boolean;
begin
  Result := Assigned(ACancelled) and ACancelled();
end;

/// <summary>Zeitstempel der Include-Dateien beim Einlesen, parallel zu AIncludes; -1 = fehlt.</summary>
function IncludeStampsOf(const AFileSystem: IIndexFileSystem; const AIncludes: TArray<string>): TArray<Int64>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AIncludes));
  for mIndex := 0 to High(AIncludes) do
  begin
    if not AFileSystem.FileStamp(AIncludes[mIndex], Result[mIndex]) then
    begin
      Result[mIndex] := -1;
    end;
  end;
end;

/// <summary>Haben alle Include-Dateien von ACached noch den Zeitstempel vom Einlesen (#617)?</summary>
function IncludesUnchanged(const AFileSystem: IIndexFileSystem; const ACached: TUnitIndex): Boolean;
var
  mIndex: Integer;
  mStamp: Int64;
begin
  // Ältere Einträge ohne Zeitstempel gelten als geändert.
  Result := Length(ACached.IncludeStamps) = Length(ACached.Includes);
  mIndex := 0;
  while Result and (mIndex < Length(ACached.Includes)) do
  begin
    Result := AFileSystem.FileStamp(ACached.Includes[mIndex], mStamp) and (ACached.IncludeStamps[mIndex] >= 0) and
      (mStamp = ACached.IncludeStamps[mIndex]);
    Inc(mIndex);
  end;
end;

/// <summary>Über uses genannter Name samt Art der nennenden Unit (Bibliothek oder nicht).</summary>
type
  TReferencedName = TPair<string, Boolean>;

procedure EnqueueAll(APending: TQueue<TReferencedName>; const ANames: TArray<string>; AFromLibrary: Boolean);
var
  mName: string;
begin
  for mName in ANames do
  begin
    APending.Enqueue(TReferencedName.Create(mName, AFromLibrary));
  end;
end;

/// <summary>Units in AIndex gelten als gesehen; ihre uses (interface und implementation) warten in APending.</summary>
procedure SeedReferenced(const AIndex: ISymbolIndex; APending: TQueue<TReferencedName>;
  ASeen: TDictionary<string, Boolean>; const ALibraryRoots: TArray<string>);
var
  mStored: TIndexStoredUnit;
  mFromLibrary: Boolean;
begin
  // Nur die gepinnten Units (Phase 3): Die uses einer nur bei Bedarf geladenen Bibliotheks-Unit gehören nicht zur
  // Hülle der Projekte; sonst wüchse sie mit jedem Nachladen.
  for mStored in AIndex.StoredUnits do
  begin
    if not mStored.Pinned then
    begin
      Continue;
    end;
    ASeen.AddOrSetValue(UpperCase(mStored.Unit_.UnitName), True);
    // Bibliothek heißt hier: Datei der Delphi-Installation (nicht: über uses nachgeladen).
    mFromLibrary := TIndexFileDefines.IsUnder(mStored.Unit_.FileName, ALibraryRoots);
    EnqueueAll(APending, mStored.Unit_.InterfaceUses, mFromLibrary);
    EnqueueAll(APending, mStored.Unit_.ImplementationUses, mFromLibrary);
  end;
end;

/// <summary>Units in AIndex, die AFileName per $I einbinden.</summary>
function DependentsOf(const AIndex: ISymbolIndex; const AFileName: string): TArray<TUnitIndex>;
var
  mList: TList<TUnitIndex>;
  mStored: TIndexStoredUnit;
  mUnit: TUnitIndex;
  mInclude: string;
begin
  mList := TList<TUnitIndex>.Create;
  try
    // Alle Units samt verdrängter (Phase 3): Ihr Kopf kennt die Include-Dateien.
    for mStored in AIndex.StoredUnits do
    begin
      mUnit := mStored.Unit_;
      for mInclude in mUnit.Includes do
      begin
        if SameText(mInclude, AFileName) then
        begin
          mList.Add(mUnit);
          Break;
        end;
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

{ TIndexFileDefines }

class function TIndexFileDefines.IsUnder(const AFileName: string; const ARoots: TArray<string>): Boolean;
var
  mRoot: string;
begin
  // Windows-Pfade auch unter anderen Systemen (Tests): beide Trenner gelten.
  Result := False;
  for mRoot in ARoots do
  begin
    if (mRoot <> '') and AFileName.StartsWith(mRoot, True) and (CharInSet(mRoot[Length(mRoot)], ['\', '/']) or
      ((Length(AFileName) > Length(mRoot)) and CharInSet(AFileName[Length(mRoot) + 1], ['\', '/']))) then
    begin
      Exit(True);
    end;
  end;
end;

function TIndexFileDefines.DefinesOf(const AFileName: string): TArray<string>;
begin
  // RTL, VCL und FMX einmal je Compiler und Plattform statt je Projekt-Defines (#647).
  if IsUnder(AFileName, LibraryRoots) then
  begin
    Result := LibraryDefines;
  end
  else
  begin
    Result := Project;
  end;
end;

function TIndexFileDefines.KeyOf(const AFileName: string): string;
begin
  Result := AnsiUpperCase(String.Join(';', DefinesOf(AFileName)));
end;

{ TIndexKeySet }

constructor TIndexKeySet.Create;
begin
  inherited Create;
  FKeys := TDictionary<string, Boolean>.Create;
  FLock := TObject.Create;
end;

destructor TIndexKeySet.Destroy;
begin
  FLock.Free;
  FKeys.Free;
  inherited;
end;

function TIndexKeySet.Contains(const AKey: string): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FKeys.ContainsKey(AnsiUpperCase(AKey));
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexKeySet.Add(const AKey: string);
begin
  TMonitor.Enter(FLock);
  try
    FKeys.AddOrSetValue(AnsiUpperCase(AKey), True);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexKeySet.Remove(const AKey: string);
begin
  TMonitor.Enter(FLock);
  try
    FKeys.Remove(AnsiUpperCase(AKey));
    TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexKeySet.Clear;
begin
  TMonitor.Enter(FLock);
  try
    FKeys.Clear;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TIndexKeySet.Claim(const AKey: string; const AAlreadyDone: TFunc<Boolean>): Boolean;
const
  cWaitSliceMs = 50;
var
  mKey: string;
  mWaited: Boolean;
begin
  mKey := AnsiUpperCase(AKey);
  mWaited := False;
  TMonitor.Enter(FLock);
  try
    while FKeys.ContainsKey(mKey) do
    begin
      mWaited := True;
      TMonitor.Wait(FLock, cWaitSliceMs);
    end;
    Result := not (mWaited and AAlreadyDone());
    if Result then
    begin
      FKeys.Add(mKey, True);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TIndexCacheEntries }

constructor TIndexCacheEntries.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TIndexCacheEntry>.Create;
  FLock := TObject.Create;
end;

destructor TIndexCacheEntries.Destroy;
begin
  FLock.Free;
  FEntries.Free;
  inherited;
end;

procedure TIndexCacheEntries.Add(const AFileName: string; const AEntry: TIndexCacheEntry);
begin
  TMonitor.Enter(FLock);
  try
    FEntries.AddOrSetValue(AnsiUpperCase(AFileName), AEntry);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TIndexCacheEntries.TryGet(const AFileName: string; out AEntry: TIndexCacheEntry): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FEntries.TryGetValue(AnsiUpperCase(AFileName), AEntry);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexCacheEntries.Clear;
begin
  TMonitor.Enter(FLock);
  try
    FEntries.Clear;
    FEntries.TrimExcess;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TIndexCacheEntries.Count: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := FEntries.Count;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TIndexBuilder }

constructor TIndexBuilder.Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
  const ADefines: TArray<string>; const AResolveUnit: TUnitFileResolver);
begin
  inherited Create;
  FIndex := AIndex;
  FFileSystem := AFileSystem;
  FDefines.Project := ADefines;
  FResolveUnit := AResolveUnit;
  FCache := TIndexCacheEntries.Create;
  FFailedUnits := TIndexKeySet.Create;
  FInFlight := TIndexKeySet.Create;
end;

function TIndexBuilder.AlreadyIndexed(const AFileName: string; AStamp: Int64; ALibrary: Boolean): Boolean;
var
  mExisting: TUnitIndex;
begin
  // Ohne diese Prüfung übernahm jedes Projekt einer Gruppe die gemeinsamen Units erneut (aus dem Cache oder
  // geparst) und ersetzte die des vorigen; die Namenslisten des Index behielten die ersetzten Einträge, bis es
  // mehr tote als lebende gab (Speicher, Rückmeldung 01.11.2026). Bedingungen wie bei CacheFits.
  // Ohne Nachladen (Phase 3): Kopf einer verdrängten Unit reicht.
  Result := FIndex.FindHeader(AFileName, mExisting) and (mExisting.Stamp = AStamp) and
    (mExisting.Library_ = ALibrary) and Keeps(mExisting) and IncludesUnchanged(FFileSystem, mExisting);
end;

function TIndexBuilder.Keeps(const AUnit: TUnitIndex): Boolean;
begin
  Result := (AUnit.DefinesKey <> '') and (AUnit.DefinesKey = FDefines.KeyOf(AUnit.FileName)) and
    (AUnit.UsagesIndexed or not WantsUsages(AUnit.Library_)) and
    (not AUnit.Compact or (AUnit.Library_ and (FIndex.Budget > 0)));
end;

destructor TIndexBuilder.Destroy;
begin
  FInFlight.Free;
  FFailedUnits.Free;
  FCache.Free;
  inherited;
end;

procedure TIndexBuilder.UseCache(const AUnits: TArray<TUnitIndex>);
var
  mUnitIndex: TUnitIndex;
begin
  // Ob ein kompakter Eintrag taugt, entscheidet CacheFits beim Einlesen.
  for mUnitIndex in AUnits do
  begin
    FCache.Add(mUnitIndex.FileName, TIndexCacheEntry.FromUnit(mUnitIndex));
  end;
end;

procedure TIndexBuilder.UseCache(const AEntries: TArray<TIndexCacheEntry>);
var
  mEntry: TIndexCacheEntry;
begin
  for mEntry in AEntries do
  begin
    FCache.Add(mEntry.Header.FileName, mEntry);
  end;
end;

procedure TIndexBuilder.ReleaseCache;
begin
  FCache.Clear;
end;

function TIndexBuilder.CachedCount: Integer;
begin
  Result := FCache.Count;
end;

function TIndexBuilder.IncludeResolver: TIncludeResolver;
var
  mFileSystem: IIndexFileSystem;
begin
  mFileSystem := FFileSystem;
  Result := TIncludeFiles.Resolver(FIncludePaths,
    function(const AFileName: string): Boolean
    var
      Stamp: Int64;
    begin
      Result := mFileSystem.FileStamp(AFileName, Stamp);
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := mFileSystem.ReadText(AFileName, AText);
    end);
end;

function TIndexBuilder.WantsUsages(ALibrary: Boolean): Boolean;
begin
  Result := FUsages and not ALibrary;
end;

function TIndexBuilder.Hot(const AUnitName: string): Boolean;
begin
  Result := (FUsage <> nil) and (FUsage.Score(AUnitName) >= cIndexHotScore);
end;

procedure TIndexBuilder.AddColdFrom(const AEntry: TIndexCacheEntry; AStamp: Int64; ALibrary: Boolean);
var
  mHeader: TUnitIndex;
  mCatalog: TCatalogUnit;
begin
  mHeader := AEntry.Header;
  mHeader.Stamp := AStamp;
  mHeader.Library_ := ALibrary;
  mHeader.DefinesKey := FDefines.KeyOf(mHeader.FileName);
  if not WantsUsages(ALibrary) then
  begin
    mHeader.UsagesIndexed := False;
  end;
  mCatalog := AEntry.Catalog;
  mCatalog.Library_ := ALibrary;
  FIndex.AddCold(mHeader, mCatalog, AEntry.Source, AEntry.SymbolCount, AEntry.UnavailableCount, AEntry.UsageCount);
end;

function TIndexBuilder.CacheFits(const AEntry: TIndexCacheEntry; ALibrary: Boolean;
  out AMiss: TIndexCacheMiss): Boolean;
begin
  AMiss := TIndexCacheMiss.NoEntry;
  // Mit Includes kann sich das Ergebnis ändern, ohne dass die Unit sich ändert; ohne erfasste
  // Verwendungen taugt der Eintrag nicht, sobald sie gebraucht werden.
  Result := IncludesUnchanged(FFileSystem, AEntry.Header);
  if not Result then
  begin
    AMiss := TIndexCacheMiss.Includes;
    Exit;
  end;
  Result := AEntry.Header.UsagesIndexed or not WantsUsages(ALibrary);
  if not Result then
  begin
    AMiss := TIndexCacheMiss.Usages;
    Exit;
  end;
  // Kompakten Einträgen fehlen die Symbole aus dem implementation-Teil. Für Bibliotheken reicht
  // das, solange ein Budget gilt: der Index würde sie ohnehin wieder kompakt halten. Sonst liefen
  // bei knappem Budget alle Bibliotheken bei jedem Start durch den Parser (Diagnoselog 15.10.2026).
  if AEntry.Header.Compact then
  begin
    Result := ALibrary and (FIndex.Budget > 0);
  end;
  if not Result then
  begin
    AMiss := TIndexCacheMiss.Compact;
  end;
end;

function TIndexBuilder.FromCache(const AEntry: TIndexCacheEntry; ALibrary: Boolean; out AUnit: TUnitIndex): Boolean;
begin
  Result := TIndexCache.Expand(AEntry, AUnit, WantsUsages(ALibrary));
  if Result and not WantsUsages(ALibrary) then
  begin
    AUnit.Usages := nil;
    AUnit.UsagesIndexed := False;
    AUnit.UsagesOffloaded := False;
  end;
end;

function TIndexBuilder.ReadUsages(const AFileName: string; out AUsages: TArray<TIndexUsage>): Boolean;
var
  mText: string;
begin
  AUsages := nil;
  Result := FFileSystem.ReadText(AFileName, mText);
  if Result then
  begin
    AUsages := TIndexExtractor.ExtractText(mText, AFileName, FDefines.DefinesOf(AFileName), IncludeResolver(),
      True).Usages;
  end;
end;

function TIndexBuilder.IndexFile(const AFileName: string; ALibrary: Boolean;
  var AResult: TIndexBuildResult; ALazy: Boolean): Boolean;
var
  mIndex: ISymbolIndex;
  mFileName: string;
begin
  mIndex := FIndex;
  mFileName := AFileName;
  // Ein anderer Thread hat die Datei eben gelesen: sein Ergebnis gilt, kein zweites Parsen.
  if not FInFlight.Claim(AFileName,
    function: Boolean
    var
      mExisting: TUnitIndex;
    begin
      Result := mIndex.FindHeader(mFileName, mExisting);
    end) then
  begin
    Exit(True);
  end;
  try
    Result := IndexFileNow(AFileName, ALibrary, AResult, ALazy);
  finally
    FInFlight.Remove(AFileName);
  end;
end;

function TIndexBuilder.IndexFileNow(const AFileName: string; ALibrary: Boolean;
  var AResult: TIndexBuildResult; ALazy: Boolean): Boolean;
var
  mStamp: Int64;
  mText, mHash: string;
  mEntry: TIndexCacheEntry;
  mCached: TUnitIndex;
  mHasCache, mTaken, mCold: Boolean;
  mMiss: TIndexCacheMiss;
begin
  if not FFileSystem.FileStamp(AFileName, mStamp) then
  begin
    Inc(AResult.Missing);
    Exit(False);
  end;
  if AlreadyIndexed(AFileName, mStamp, ALibrary) then
  begin
    Inc(AResult.FromCache);
    Exit(True);
  end;
  mMiss := TIndexCacheMiss.NoEntry;
  mHasCache := FCache.TryGet(AFileName, mEntry) and CacheFits(mEntry, ALibrary, mMiss);
  // Phase 3: In der Bibliotheksstufe genügen Kopf, Katalog und Block; die Symbole lädt der Index bei Bedarf.
  mCold := ALazy and mHasCache and not mEntry.Expanded and (mEntry.Source <> nil) and
    not Hot(mEntry.Header.UnitName);
  if mCold and (mEntry.Header.Stamp = mStamp) then
  begin
    AddColdFrom(mEntry, mStamp, ALibrary);
    Inc(AResult.FromCache);
    Exit(True);
  end;
  // Zeitstempel oder Inhalt passen: erst jetzt die Symbole dekodieren; ein beschädigter Block
  // zählt wie ein fehlender Cache-Eintrag.
  mTaken := not mCold and mHasCache and (mEntry.Header.Stamp = mStamp) and FromCache(mEntry, ALibrary, mCached);
  if not mTaken then
  begin
    if not FFileSystem.ReadText(AFileName, mText) then
    begin
      Inc(AResult.Missing);
      Exit(False);
    end;
    mHash := TIndexCache.HashOf(mText);
    if mCold and (mEntry.Header.Hash = mHash) then
    begin
      // Nur der Zeitstempel ist neu: Der Kopf trägt ihn, der Block bleibt.
      AddColdFrom(mEntry, mStamp, ALibrary);
      Inc(AResult.FromCache);
      Exit(True);
    end;
    if mHasCache and (mEntry.Header.Hash = mHash) then
    begin
      mTaken := FromCache(mEntry, ALibrary, mCached);
      mMiss := TIndexCacheMiss.Damaged;
    end
    else if mHasCache then
    begin
      mMiss := TIndexCacheMiss.Changed;
    end;
  end;
  if mTaken then
  begin
    mCached.Stamp := mStamp;
    mCached.Library_ := ALibrary;
    mCached.DefinesKey := FDefines.KeyOf(AFileName);
    if ALazy and not Hot(mCached.UnitName) then
    begin
      // Aus dem Cache, aber vollständig (z. B. ohne Block): verdrängbar, sobald der Block bekannt ist.
      FIndex.AddEvictable(mCached, mEntry.Source);
      if mEntry.Source = nil then
      begin
        Inc(FUnboundBytes, TIndexMemory.UnitBytes(mCached));
      end;
    end
    else
    begin
      FIndex.AddUnit(mCached);
    end;
    Inc(AResult.FromCache);
    Exit(True);
  end;
  ParseFile(AFileName, mText, mHash, mStamp, ALibrary, ALazy, AResult);
  Inc(AResult.Misses[mMiss]);
  Result := True;
end;

procedure TIndexBuilder.ParseFile(const AFileName, AText, AHash: string; AStamp: Int64; ALibrary, ALazy: Boolean;
  var AResult: TIndexBuildResult);
var
  mWatch: TStopwatch;
  mUnit: TUnitIndex;
begin
  mWatch := TStopwatch.StartNew;
  mUnit := TIndexExtractor.ExtractText(AText, AFileName, FDefines.DefinesOf(AFileName), IncludeResolver(),
    WantsUsages(ALibrary), not ALibrary);
  Inc(AResult.ParseMs, mWatch.ElapsedMilliseconds);
  mUnit.Stamp := AStamp;
  mUnit.Hash := AHash;
  mUnit.IncludeStamps := IncludeStampsOf(FFileSystem, mUnit.Includes);
  mUnit.Library_ := ALibrary;
  mUnit.DefinesKey := FDefines.KeyOf(AFileName);
  if ALazy and not Hot(mUnit.UnitName) then
  begin
    // Noch ohne Block im Cache: verdrängbar erst, wenn der Cache geschrieben ist (TIndexCacheWriter bindet ihn).
    FIndex.AddEvictable(mUnit, nil);
    Inc(FUnboundBytes, TIndexMemory.UnitBytes(mUnit));
  end
  else
  begin
    FIndex.AddUnit(mUnit);
  end;
  Inc(AResult.Parsed);
end;

function TIndexBuilder.NextReferenced(const AName: string; AFromLibrary: Boolean; var AResult: TIndexBuildResult;
  const AProgress: TIndexProgressEvent; out AUses: TArray<string>; out ALibrary: Boolean): Boolean;
var
  mExisting: TUnitIndex;
  mFileName: string;
  mStamp: Int64;
  mWatch: TStopwatch;
  mWasPinned: Boolean;
begin
  AUses := nil;
  ALibrary := True;
  if FIndex.FindUnitHeader(AName, mExisting) then
  begin
    // Phase 3: Steht sie nur im Katalog (Bibliotheksstufe), gehört sie jetzt zur Hülle: laden, pinnen und ihren uses
    // folgen. Sonst wie bisher nichts zu tun.
    if not FIndex.Pin(mExisting.FileName, mWasPinned) or mWasPinned then
    begin
      Exit(False);
    end;
    AUses := mExisting.InterfaceUses;
    ALibrary := TIndexFileDefines.IsUnder(mExisting.FileName, FDefines.LibraryRoots);
    Exit(True);
  end;
  mWatch := TStopwatch.StartNew;
  mFileName := FResolveUnit(AName);
  Inc(AResult.ResolveMs, mWatch.ElapsedMilliseconds);
  if mFileName = '' then
  begin
    Exit(False);
  end;
  // c1: Office-Typbibliotheken und WinRT nur, wenn das Projekt selbst sie nennt. Über die uses der Bibliothek
  // hing es vorher vom Zufall der Reihenfolge ab, ob sie im Index landeten (bis 35 Units, rund 19 MB), und jeder
  // Neuaufbau parste sie (Speicher-Optimierung Phase 2).
  if AFromLibrary and (Length(FRarelyUsedRoots) > 0) and TIndexFileDefines.IsUnder(mFileName, FRarelyUsedRoots) then
  begin
    Exit(False);
  end;
  // Unter anderem Namen schon im Index, z. B. "Forms" als Vcl.Forms aus einem anderen Projekt
  // der Gruppe: nicht neu einlesen. Sonst las jedes Projekt dieselben Units erneut (#647).
  if not (FIndex.FindHeader(mFileName, mExisting) and FFileSystem.FileStamp(mFileName, mStamp) and
    (mStamp = mExisting.Stamp)) then
  begin
    if Assigned(AProgress) then
    begin
      AProgress(TIndexProgressKind.Report, AName, -1);
    end;
    if not (IndexFile(mFileName, True, AResult) and FIndex.FindHeader(mFileName, mExisting)) then
    begin
      Exit(False);
    end;
  end;
  // Zur Hülle der Projekte: geladen halten (auch wenn sie bisher nur im Katalog stand).
  FIndex.Pin(mFileName, mWasPinned);
  // Nur das interface ist von außen sichtbar; dessen uses reichen.
  AUses := mExisting.InterfaceUses;
  ALibrary := TIndexFileDefines.IsUnder(mExisting.FileName, FDefines.LibraryRoots);
  Result := True;
end;

procedure TIndexBuilder.IndexReferenced(var AResult: TIndexBuildResult; const ARun: TIndexStageRun);
var
  mPending: TQueue<TReferencedName>;
  mSeen: TDictionary<string, Boolean>;
  mName: TReferencedName;
  mUses_: TArray<string>;
  mLibrary: Boolean;
begin
  if not Assigned(FResolveUnit) then
  begin
    Exit;
  end;
  mPending := TQueue<TReferencedName>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    SeedReferenced(FIndex, mPending, mSeen, FDefines.LibraryRoots);
    while (mPending.Count > 0) and not AResult.Cancelled do
    begin
      AResult.Cancelled := IsCancelled(ARun.Cancelled);
      mName := mPending.Dequeue;
      if not AResult.Cancelled and not mSeen.ContainsKey(UpperCase(mName.Key)) then
      begin
        mSeen.Add(UpperCase(mName.Key), True);
        if NextReferenced(mName.Key, mName.Value, AResult, ARun.Progress, mUses_, mLibrary) then
        begin
          EnqueueAll(mPending, mUses_, mLibrary);
        end;
      end;
    end;
  finally
    mSeen.Free;
    mPending.Free;
  end;
end;

function TIndexBuilder.Build(const AFiles: TArray<string>; const AProgress: TIndexProgressEvent;
  const ACancelled: TIndexCancelled): TIndexBuildResult;
begin
  Result := Build(AFiles, nil, nil, AProgress, ACancelled, nil);
end;

function TIndexBuilder.RunStage(AStage: TIndexStage; const AFiles: TArray<string>; const ALabel: string;
  ADone: Integer; var AResult: TIndexBuildResult; const ARun: TIndexStageRun): Boolean;
var
  mIndex: Integer;
  mExisting: TUnitIndex;
  mProject: Boolean;
begin
  mProject := AStage = TIndexStage.Project;
  // Ohne Dateien wartet nur die Projektstufe auf ihre Reihe: Sie folgt auch ohne Projektdateien den uses.
  if not mProject and (Length(AFiles) = 0) then
  begin
    Exit(True);
  end;
  AResult.Cancelled := (ARun.Turn <> nil) and not ARun.Turn.Enter(AStage, ARun.Cancelled);
  if AResult.Cancelled then
  begin
    Exit(False);
  end;
  try
    mIndex := 0;
    while (mIndex < Length(AFiles)) and not AResult.Cancelled do
    begin
      AResult.Cancelled := IsCancelled(ARun.Cancelled);
      // Schon da (anderes Projekt der Gruppe, über uses erreicht): Suchpfade und Bibliothek nicht noch einmal
      // lesen. Projektdateien prüft IndexFile selbst (gleiche Defines, AlreadyIndexed).
      if not AResult.Cancelled and (mProject or not FIndex.FindHeader(AFiles[mIndex], mExisting)) then
      begin
        if Assigned(ARun.Progress) then
        begin
          ARun.Progress(TIndexProgressKind.Report, ALabel + AFiles[mIndex], ((ADone + mIndex) * 100) div ARun.Total);
        end;
        IndexFile(AFiles[mIndex], AStage = TIndexStage.Library_, AResult,
          (AStage = TIndexStage.Library_) and FLazyLibrary);
        // Erster Start ohne Cache: zwischendurch schreiben lassen, damit die neu gelesenen Units gehen dürfen.
        if (AStage = TIndexStage.Library_) and FLazyLibrary and (FUnboundBytes >= cFlushBytes) and
          Assigned(FOnLibraryFlush) then
        begin
          FUnboundBytes := 0;
          FOnLibraryFlush(AResult);
        end;
      end;
      Inc(mIndex);
    end;
    if mProject and not AResult.Cancelled then
    begin
      IndexReferenced(AResult, ARun);
    end;
  finally
    if ARun.Turn <> nil then
    begin
      ARun.Turn.Leave;
    end;
  end;
  Result := not AResult.Cancelled;
end;

function TIndexBuilder.Build(const AFiles, ASearchFiles, ALibraryFiles: TArray<string>;
  const AProgress: TIndexProgressEvent; const ACancelled: TIndexCancelled; const ATurn: IIndexTurn): TIndexBuildResult;
var
  mRun: TIndexStageRun;
begin
  Result := Default(TIndexBuildResult);
  mRun := Default(TIndexStageRun);
  mRun.Progress := AProgress;
  mRun.Cancelled := ACancelled;
  mRun.Turn := ATurn;
  mRun.Total := Length(AFiles) + Length(ASearchFiles) + Length(ALibraryFiles);
  if mRun.Total = 0 then
  begin
    mRun.Total := 1;
  end;
  if Assigned(AProgress) then
  begin
    AProgress(TIndexProgressKind.Started, cTexts[TBuilderText.SymbolIndex].Text, 0);
  end;
  try
    // Units der Suchpfade gehören zum Projekt, auch wenn keine sie einbindet.
    if RunStage(TIndexStage.Project, AFiles, '', 0, Result, mRun) and Assigned(FOnProjectDone) then
    begin
      FOnProjectDone(Result);
    end;
    if not Result.Cancelled and RunStage(TIndexStage.SearchPaths, ASearchFiles, cTexts[TBuilderText.SearchPaths].Text,
      Length(AFiles),
      Result, mRun) then
    begin
      RunStage(TIndexStage.Library_, ALibraryFiles, cTexts[TBuilderText.LibraryText].Text, Length(AFiles) +
        Length(ASearchFiles), Result,
        mRun);
    end;
  finally
    if Assigned(AProgress) then
    begin
      AProgress(TIndexProgressKind.Finished,
        cTexts[TBuilderText.UnitsSymbols].Fmt([FIndex.UnitCount, FIndex.SymbolCount]), 100);
    end;
  end;
end;

function TIndexBuilder.EnsureUnit(const AUnitName: string): Boolean;
var
  mExisting: TUnitIndex;
  mFileName: string;
  mIgnored: TIndexBuildResult;
begin
  if FIndex.FindUnit(AUnitName, mExisting) then
  begin
    Exit(True);
  end;
  if not Assigned(FResolveUnit) then
  begin
    Exit(False);
  end;
  if FFailedUnits.Contains(AUnitName) then
  begin
    Exit(False);
  end;
  mFileName := FResolveUnit(AUnitName);
  mIgnored := Default(TIndexBuildResult);
  Result := (mFileName <> '') and IndexFile(mFileName, True, mIgnored);
  if not Result then
  begin
    FFailedUnits.Add(AUnitName);
  end;
end;

function TIndexBuilder.ApplyText(const AFileName, AText: string): Boolean;
var
  mExisting, mUnitIndex: TUnitIndex;
  mHash: string;
begin
  Result := False;
  // Nur Units, die der Index kennt; neue Dateien kommen wie bisher beim Speichern dazu.
  if not FIndex.FindHeader(AFileName, mExisting) then
  begin
    Exit;
  end;
  mHash := TIndexCache.HashOf(AText);
  if mHash = mExisting.Hash then
  begin
    Exit;
  end;
  mUnitIndex := TIndexExtractor.ExtractText(AText, AFileName, FDefines.DefinesOf(AFileName), IncludeResolver(),
    WantsUsages(mExisting.Library_), not mExisting.Library_);
  // Zeitstempel bleibt der der Datei: Beim Speichern liest IndexFile sie dann neu von der Platte.
  mUnitIndex.Stamp := mExisting.Stamp;
  mUnitIndex.Hash := mHash;
  mUnitIndex.IncludeStamps := IncludeStampsOf(FFileSystem, mUnitIndex.Includes);
  mUnitIndex.Library_ := mExisting.Library_;
  FIndex.AddUnit(mUnitIndex);
  Result := True;
end;

function TIndexBuilder.ApplyChange(const AChange: TFileChange; var AIgnored: TIndexBuildResult): Integer;
var
  mExisting, mDependent: TUnitIndex;
begin
  Result := 0;
  // Units, die die Datei per $I einbinden, neu einlesen.
  for mDependent in DependentsOf(FIndex, AChange.FileName) do
  begin
    if IndexFile(mDependent.FileName, mDependent.Library_, AIgnored) then
    begin
      Inc(Result);
    end;
  end;
  if not FIndex.FindHeader(AChange.FileName, mExisting) then
  begin
    // Eine neue Datei kann eine bisher fehlende Unit sein.
    if AChange.Kind <> TFileChangeKind.Deleted then
    begin
      FFailedUnits.Clear;
    end;
    Exit;
  end;
  // IndexFile vergleicht mit dem Cache vom Start; ein geänderter Zeitstempel
  // führt zum Neueinlesen, gleicher Inhalt nicht. Was sich nicht mehr lesen
  // lässt oder gelöscht ist, fällt aus dem Index.
  if (AChange.Kind = TFileChangeKind.Deleted) or not IndexFile(AChange.FileName, mExisting.Library_, AIgnored) then
  begin
    FIndex.RemoveFile(AChange.FileName);
  end;
  Inc(Result);
end;

function TIndexBuilder.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
var
  mChange: TFileChange;
  mIgnored: TIndexBuildResult;
begin
  Result := 0;
  mIgnored := Default(TIndexBuildResult);
  for mChange in AChanges do
  begin
    Inc(Result, ApplyChange(mChange, mIgnored));
  end;
end;

initialization
  TDpccTextTables.Add('dpcc.Common.Index.Builder', cTexts);

end.
