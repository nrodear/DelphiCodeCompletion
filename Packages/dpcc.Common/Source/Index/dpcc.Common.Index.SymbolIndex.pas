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
  private
    // Name → Verweise; Vorfahr ohne Unit-Präfix und Typargumente → Verweise; beide ohne Groß-/Kleinschreibung.
    FByName: TSymbolTable;
    FByAncestor: TSymbolTable;
    // Alle Verweise, in Blöcken; FNodeCount belegt (samt freier).
    FNodes: TArray<TArray<TSymbolRef>>;
    FNodeCount: Integer;
    // Freiliste (Phase 3): Knoten entfernter Units, verkettet über Next; -1 = leer.
    FFreeNode: Integer;
    // Platz → Dateischlüssel ('' = Unit ersetzt oder entfernt) und Zahl seiner Verweise.
    FSlotKeys: TList<string>;
    FSlotRefs: TList<Integer>;
    // Platz → Unit für die Suche (Known = False, wenn ersetzt oder entfernt); parallel zu FSlotKeys.
    FSlotUnits: TList<TSlotUnit>;
    // Dateischlüssel → aktueller Platz.
    FFileSlots: TDictionary<string, Integer>;
    FLiveRefs: Integer;
    FDeadRefs: Integer;
    procedure AddRef(ATable: TSymbolTable; const AKey: string; ASlot, APosition: Integer);
    function NodeAt(AIndex: Integer): TSymbolRef; inline;
    procedure SetNext(AIndex, ANext: Integer); inline;
    function Locations(ATable: TSymbolTable; const AKey: string): TArray<TSymbolLocation>;
    /// <summary>Entfernt aus der Kette von AKey alle Verweise auf ASlot.</summary>
    procedure Unlink(ATable: TSymbolTable; const AKey: string; ASlot: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    /// <summary>Trägt die Symbole von AUnit (Dateischlüssel AKey) auf einem neuen Platz ein.</summary>
    procedure Add(const AKey: string; const AUnit: TUnitIndex);
    /// <summary>Macht die Verweise der Unit AKey tot.</summary>
    procedure Drop(const AKey: string);
    /// <summary>Entfernt die Verweise der Unit AKey mit den Symbolen ASymbols ganz (Verdrängen, Phase 3): keine
    /// toten Verweise, die Knoten kommen in die Freiliste.</summary>
    procedure Remove(const AKey: string; const ASymbols: TArray<TIndexSymbol>);
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
    /// <summary>Zählt AUnit hinzu (ASign = 1) oder heraus (ASign = -1).</summary>
    procedure Count(const AUnit: TUnitIndex; ASign: Integer);
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
    /// <summary>Geschätzter Bedarf der geladenen Unit (TIndexMemory.UnitBytes).</summary>
    Bytes: Int64;
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

  TSymbolIndex = class(TInterfacedObject, ISymbolIndex)
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
    // Unit-Name (groß) → Dateiname (groß)
    FUnitFiles: TDictionary<string, string>;
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
    FEvictableBytes: Int64;
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
    // Name (Hash) → Eintrag mit diesem Symbol im Katalog, für FindSymbols über verdrängte Units; bis zur nächsten
    // Generation.
    FNameHashes: TArray<UInt64>;
    FNameKeys: TArray<string>;
    FNameGeneration: Int64;
    FUsage: IIndexUsage;
    function NewEntry: TIndexEntry;
    procedure Account(AEntry: TIndexEntry; ASign: Integer);
    procedure AddLocked(const AKey: string; const AUnit: TUnitIndex; APinned: Boolean;
      const ASource: IIndexUnitSource);
    /// <summary>Trägt die geladene Unit von AEntry in Tabellen und Zähler ein.</summary>
    procedure InstallLocked(const AKey: string; AEntry: TIndexEntry);
    procedure ChangeUsesPins(const AUnit: TUnitIndex; ASign: Integer);
    function UsesPinned(AEntry: TIndexEntry): Boolean;
    procedure ShrinkLocked;
    function OverBudgetLocked: Boolean;
    /// <summary>Verkleinert die Unit AKey im Durchgang APass: 0 Bibliothek kompakt halten, 1 Verwendungen der
    /// Projekt-Units auslagern, 2 Projekt-Units kompakt halten.</summary>
    procedure ShrinkUnitLocked(APass: Integer; const AKey: string);
    procedure RemoveFileLocked(const AFileKey: string);
    /// <summary>Baut die Tabellen neu, wenn die toten Verweise überwiegen.</summary>
    procedure CleanRefsLocked;
    /// <summary>Dateischlüssel zum Unit-Namen (auch über Aliase); '' wenn unbekannt.</summary>
    function UnitKeyLocked(const AUnitName: string): string;
    procedure TouchLocked(AEntry: TIndexEntry);
    /// <summary>Lädt die Unit AKey nach, falls sie verdrängt ist; liefert sie.</summary>
    function LoadKey(const AKey: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Verdrängt, bis die verdrängbaren Units wieder ins Budget passen; AKeep bleibt.</summary>
    procedure EvictLocked(AKeep: TIndexEntry);
    procedure UnloadLocked(const AKey: string; AEntry: TIndexEntry);
    /// <summary>Lädt die verdrängten Units, in deren Katalog ein Symbol AName steht.</summary>
    procedure LoadColdNamed(const AName: string);
    procedure BuildNameLookupLocked;
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
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.Math,
  System.StrUtils,
  System.Generics.Defaults,
  dpcc.Common.Projects.UnitAliases,
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

{ TSymbolIndex }

constructor TSymbolIndex.Create;
begin
  inherited Create;
  FGeneration := TInterlocked.Increment(IndexSerial) shl 32;
  FLock := TCriticalSection.Create;
  FPoolLock := TCriticalSection.Create;
  FUnavailable := TDictionary<string, Boolean>.Create;
  FFiles := TObjectDictionary<string, TIndexEntry>.Create([doOwnsValues]);
  FUnitFiles := TDictionary<string, string>.Create;
  FPool := TStringPool.Create;
  FRefs := TSymbolRefTables.Create;
  FShrinkable := TDictionary<string, Boolean>.Create;
  FUsesPins := TDictionary<string, Integer>.Create;
  FAliases := TUnitAliases.Defaults;
  SetLength(FLoadMs, cLoadSamples);
  FNameGeneration := -1;
end;

destructor TSymbolIndex.Destroy;
begin
  // Namensindex der Import-Vorschläge (#617) hält sonst unseren Katalog fest.
  TImportNames.Forget(Self);
  FUsesPins.Free;
  FShrinkable.Free;
  FRefs.Free;
  FPool.Free;
  FUnitFiles.Free;
  FFiles.Free;
  FUnavailable.Free;
  FPoolLock.Free;
  FLock.Free;
  inherited;
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
  end;
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
      FUsesPins.Remove(mKey);
    end
    else
    begin
      FUsesPins.AddOrSetValue(mKey, mCount);
    end;
  end;
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

procedure TSymbolIndex.RemoveFileLocked(const AFileKey: string);
var
  mExisting: TIndexEntry;
  mUnitFile: string;
begin
  if not FFiles.TryGetValue(AFileKey, mExisting) then
  begin
    Exit;
  end;
  Account(mExisting, -1);
  if mExisting.Loaded then
  begin
    FTotals.Count(mExisting.Unit_, -1);
    FRefs.Drop(AFileKey);
    ChangeUsesPins(mExisting.Unit_, -1);
  end
  else
  begin
    Dec(FColdSymbols, mExisting.SymbolCount);
  end;
  Dec(FCatalogBytes, mExisting.CatalogBytes);
  FUnitsSnapshot := nil;
  FCatalogSnapshot := nil;
  FUnavailable.Remove(AFileKey);
  FShrinkable.Remove(AFileKey);
  Inc(FGeneration);
  if FUnitFiles.TryGetValue(UpperCase(mExisting.Unit_.UnitName), mUnitFile) and (mUnitFile = AFileKey) then
  begin
    FUnitFiles.Remove(UpperCase(mExisting.Unit_.UnitName));
  end;
  FFiles.Remove(AFileKey);
end;

procedure TSymbolIndex.InstallLocked(const AKey: string; AEntry: TIndexEntry);
begin
  // Jede abgelegte Fassung bekommt ihre eigene Namenstabelle (Diagnoselog 15.10.2026); FindUnit und
  // FindFile geben sie mit, die Namensauflösung sucht darüber statt linear.
  AEntry.Unit_.PrepareNames;
  AEntry.Loaded := True;
  AEntry.Bytes := TIndexMemory.UnitBytes(AEntry.Unit_);
  AEntry.SymbolCount := Length(AEntry.Unit_.Symbols);
  AEntry.UnavailableCount := Length(AEntry.Unit_.Unavailable);
  AEntry.UsageCount := Length(AEntry.Unit_.Usages);
  FUnitsSnapshot := nil;
  if Length(AEntry.Unit_.Unavailable) > 0 then
  begin
    FUnavailable.AddOrSetValue(AKey, True);
  end;
  FTotals.Count(AEntry.Unit_, 1);
  if not AEntry.Unit_.Compact or (Length(AEntry.Unit_.Usages) > 0) then
  begin
    FShrinkable.AddOrSetValue(AKey, True);
  end;
  FRefs.Add(AKey, AEntry.Unit_);
  ChangeUsesPins(AEntry.Unit_, 1);
  Account(AEntry, 1);
end;

procedure TSymbolIndex.AddLocked(const AKey: string; const AUnit: TUnitIndex; APinned: Boolean;
  const ASource: IIndexUnitSource);
var
  mEntry: TIndexEntry;
begin
  mEntry := NewEntry;
  mEntry.Unit_ := AUnit;
  mEntry.Pinned := APinned;
  mEntry.Source := ASource;
  mEntry.Catalog := TCatalogUnit.FromUnit(AUnit);
  mEntry.CatalogBytes := mEntry.Catalog.Bytes;
  FFiles.Add(AKey, mEntry);
  Inc(FCatalogBytes, mEntry.CatalogBytes);
  FCatalogSnapshot := nil;
  Inc(FGeneration);
  FUnitFiles.AddOrSetValue(UpperCase(AUnit.UnitName), AKey);
  InstallLocked(AKey, mEntry);
end;

{ TSymbolIndexTotals }

procedure TSymbolIndexTotals.Count(const AUnit: TUnitIndex; ASign: Integer);
begin
  Inc(SymbolCount, ASign * Length(AUnit.Symbols));
  Inc(Bytes, ASign * TIndexMemory.UnitBytes(AUnit));
  Inc(UsageBytes, ASign * TIndexMemory.UsageBytes(AUnit));
  if AUnit.Library_ then
  begin
    Inc(LibraryBytes, ASign * (TIndexMemory.UnitBytes(AUnit) - TIndexMemory.UsageBytes(AUnit)));
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
  FFileSlots := TDictionary<string, Integer>.Create;
  FFreeNode := -1;
end;

destructor TSymbolRefTables.Destroy;
begin
  FFileSlots.Free;
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
  FFileSlots.Clear;
  FLiveRefs := 0;
  FDeadRefs := 0;
end;

function TSymbolRefTables.NodeAt(AIndex: Integer): TSymbolRef;
begin
  Result := FNodes[AIndex div cNodeChunk][AIndex mod cNodeChunk];
end;

procedure TSymbolRefTables.SetNext(AIndex, ANext: Integer);
begin
  FNodes[AIndex div cNodeChunk][AIndex mod cNodeChunk].Next := ANext;
end;

procedure TSymbolRefTables.AddRef(ATable: TSymbolTable; const AKey: string; ASlot, APosition: Integer);
var
  mChain: TSymbolChain;
  mNode, mBlock: Integer;
begin
  // Erst die Freiliste (Knoten verdrängter Units), dann ein neuer Knoten.
  if FFreeNode >= 0 then
  begin
    mNode := FFreeNode;
    FFreeNode := NodeAt(mNode).Next;
  end
  else
  begin
    mNode := FNodeCount;
    mBlock := mNode div cNodeChunk;
    if mBlock >= Length(FNodes) then
    begin
      SetLength(FNodes, mBlock + 1);
      SetLength(FNodes[mBlock], cNodeChunk);
    end;
    Inc(FNodeCount);
  end;
  FNodes[mNode div cNodeChunk][mNode mod cNodeChunk].Slot := ASlot;
  FNodes[mNode div cNodeChunk][mNode mod cNodeChunk].Position := APosition;
  FNodes[mNode div cNodeChunk][mNode mod cNodeChunk].Next := -1;
  if ATable.TryGetValue(AKey, mChain) then
  begin
    SetNext(mChain.Last, mNode);
    mChain.Last := mNode;
    Inc(mChain.Count);
    ATable[AKey] := mChain;
  end
  else
  begin
    mChain.First := mNode;
    mChain.Last := mNode;
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

procedure TSymbolRefTables.Add(const AKey: string; const AUnit: TUnitIndex);
var
  mSlot, mPosition, mCount: Integer;
  mKey: string;
  mSlotUnit: TSlotUnit;
begin
  mSlot := FSlotKeys.Add(AKey);
  FSlotRefs.Add(0);
  mSlotUnit.Known := True;
  mSlotUnit.UnitName := AUnit.UnitName;
  mSlotUnit.FileName := AUnit.FileName;
  mSlotUnit.Symbols := AUnit.Symbols;
  FSlotUnits.Add(mSlotUnit);
  FFileSlots.AddOrSetValue(AKey, mSlot);
  mCount := 0;
  // Zugriff über den Index, damit die Symbol-Records nicht kopiert werden.
  for mPosition := 0 to High(AUnit.Symbols) do
  begin
    // Der Name selbst ist der Schlüssel (geteilter Puffer, keine Kopie).
    AddRef(FByName, AUnit.Symbols[mPosition].Name, mSlot, mPosition);
    Inc(mCount);
    for mKey in AncestorKeys(AUnit.Symbols[mPosition]) do
    begin
      AddRef(FByAncestor, mKey, mSlot, mPosition);
      Inc(mCount);
    end;
  end;
  FSlotRefs[mSlot] := mCount;
  Inc(FLiveRefs, mCount);
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
  FSlotKeys[mSlot] := '';
  FSlotUnits[mSlot] := Default(TSlotUnit);
  Dec(FLiveRefs, FSlotRefs[mSlot]);
  Inc(FDeadRefs, FSlotRefs[mSlot]);
  FSlotRefs[mSlot] := 0;
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
      // In die Freiliste; Slot -1 hält ihn aus jeder Suche heraus.
      FNodes[mNode div cNodeChunk][mNode mod cNodeChunk].Slot := -1;
      SetNext(mNode, FFreeNode);
      FFreeNode := mNode;
    end
    else
    begin
      mPrevious := mNode;
    end;
    mNode := mNext;
  end;
  if mChain.Count <= 0 then
  begin
    ATable.Remove(AKey);
  end
  else
  begin
    ATable[AKey] := mChain;
  end;
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
  // Jeden Schlüssel der Unit einmal: seine Kette verliert alle Verweise auf diesen Platz.
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
  FFileSlots.Remove(AKey);
  FSlotKeys[mSlot] := '';
  FSlotUnits[mSlot] := Default(TSlotUnit);
  Dec(FLiveRefs, FSlotRefs[mSlot]);
  FSlotRefs[mSlot] := 0;
end;

function TSymbolRefTables.Locations(ATable: TSymbolTable; const AKey: string): TArray<TSymbolLocation>;
var
  mChain: TSymbolChain;
  mNode, mCount, mLastSlot: Integer;
  mRef: TSymbolRef;
  mOwner: TSlotUnit;
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
  mNode := mChain.First;
  while mNode >= 0 do
  begin
    mRef := NodeAt(mNode);
    mNode := mRef.Next;
    // Verweise einer Unit stehen beieinander: den Platz nur beim Wechsel lesen.
    if mRef.Slot <> mLastSlot then
    begin
      mLastSlot := mRef.Slot;
      mOwner := FSlotUnits[mRef.Slot];
    end;
    if not mOwner.Known or (mRef.Position > High(mOwner.Symbols)) then
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
  mNode, mLastSlot: Integer;
  mRef: TSymbolRef;
  mOwner: TSlotUnit;
begin
  Result := False;
  if not FByName.TryGetValue(AName, mChain) then
  begin
    Exit;
  end;
  mLastSlot := -1;
  mOwner := Default(TSlotUnit);
  mNode := mChain.First;
  while mNode >= 0 do
  begin
    mRef := NodeAt(mNode);
    mNode := mRef.Next;
    // Wie Locations: der Eintrag des Platzes, nicht der ganze TUnitIndex aus FFiles.
    if mRef.Slot <> mLastSlot then
    begin
      mLastSlot := mRef.Slot;
      mOwner := FSlotUnits[mRef.Slot];
    end;
    if mOwner.Known and (mRef.Position <= High(mOwner.Symbols)) and AMatch(mOwner.Symbols[mRef.Position]) then
    begin
      Exit(True);
    end;
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
      FRefs.Add(mPair.Key, mPair.Value.Unit_);
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

/// <summary>Seltener genutzt (Zähler nach Alterung), bei Gleichstand länger nicht genutzt?</summary>
function UsedLess(AEntry, AOther: TIndexEntry; AEpoch: Integer): Boolean;
var
  mHits, mOther: Integer;
begin
  mHits := AEntry.Hits shr Integer(Min(30, AEpoch - AEntry.HitEpoch));
  mOther := AOther.Hits shr Integer(Min(30, AEpoch - AOther.HitEpoch));
  Result := (mHits < mOther) or ((mHits = mOther) and (AEntry.LastUse < AOther.LastUse));
end;

procedure TSymbolIndex.UnloadLocked(const AKey: string; AEntry: TIndexEntry);
begin
  Account(AEntry, -1);
  FRefs.Remove(AKey, AEntry.Unit_.Symbols);
  FTotals.Count(AEntry.Unit_, -1);
  ChangeUsesPins(AEntry.Unit_, -1);
  AEntry.SymbolCount := Length(AEntry.Unit_.Symbols);
  AEntry.UnavailableCount := Length(AEntry.Unit_.Unavailable);
  AEntry.UsageCount := Length(AEntry.Unit_.Usages);
  Inc(FColdSymbols, AEntry.SymbolCount);
  AEntry.Unit_ := HeaderOf(AEntry.Unit_);
  AEntry.Loaded := False;
  AEntry.Bytes := 0;
  FUnavailable.Remove(AKey);
  FShrinkable.Remove(AKey);
  FUnitsSnapshot := nil;
  Inc(FEvictions);
end;

procedure TSymbolIndex.EvictLocked(AKeep: TIndexEntry);
var
  mPair: TPair<string, TIndexEntry>;
  mVictim: TIndexEntry;
  mVictimKey: string;
begin
  while FEvictableBytes > cEvictableBudget do
  begin
    mVictim := nil;
    for mPair in FFiles do
    begin
      if not mPair.Value.Evictable or (mPair.Value = AKeep) or UsesPinned(mPair.Value) or
        ((FUsage <> nil) and (FUsage.Score(mPair.Value.Unit_.UnitName) >= cHotScore)) then
      begin
        Continue;
      end;
      if (mVictim = nil) or UsedLess(mPair.Value, mVictim, FEpoch) then
      begin
        mVictim := mPair.Value;
        mVictimKey := mPair.Key;
      end;
    end;
    if mVictim = nil then
    begin
      Break;
    end;
    UnloadLocked(mVictimKey, mVictim);
  end;
end;

function TSymbolIndex.LoadKey(const AKey: string; out AUnit: TUnitIndex): Boolean;
var
  mEntry: TIndexEntry;
  mSerial: Int64;
  mSource: IIndexUnitSource;
  mHeader, mFull: TUnitIndex;
  mLoaded: Boolean;
  mWatch: TStopwatch;
  mMs: Double;
begin
  AUnit := Default(TUnitIndex);
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
    mSerial := mEntry.Serial;
    mSource := mEntry.Source;
    mHeader := mEntry.Unit_;
  finally
    FLock.Leave;
  end;
  // Block lesen und dekodieren ohne die Sperre: Andere Anfragen warten nicht auf große Units.
  mWatch := TStopwatch.StartNew;
  mLoaded := (mSource <> nil) and mSource.Load(mFull);
  mMs := mWatch.Elapsed.TotalMilliseconds;
  FLock.Enter;
  try
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
      // Ein anderer Thread war schneller.
      TouchLocked(mEntry);
      AUnit := mEntry.Unit_;
      Exit(True);
    end;
    if not mLoaded then
    begin
      // Block fehlt oder ist beschädigt: Die Unit fällt aus dem Index; EnsureUnit liest sie aus der Datei neu.
      RemoveFileLocked(AKey);
      Exit(False);
    end;
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
    Dec(FColdSymbols, mEntry.SymbolCount);
    mEntry.Unit_ := mFull;
    InstallLocked(AKey, mEntry);
    NoteLoad(mMs, mEntry.Bytes);
    TouchLocked(mEntry);
    EvictLocked(mEntry);
    AUnit := mEntry.Unit_;
    Result := True;
  finally
    FLock.Leave;
  end;
end;

procedure TSymbolIndex.BuildNameLookupLocked;
var
  mPair: TPair<string, TIndexEntry>;
  mHashes: TList<UInt64>;
  mKeys: TList<string>;
  mIndex: Integer;
begin
  if FNameGeneration = FGeneration then
  begin
    Exit;
  end;
  mHashes := TList<UInt64>.Create;
  mKeys := TList<string>.Create;
  try
    for mPair in FFiles do
    begin
      // Nur verdrängbare Units: Gepinnte sind immer geladen.
      if mPair.Value.Pinned or (mPair.Value.Source = nil) then
      begin
        Continue;
      end;
      for mIndex := 0 to High(mPair.Value.Catalog.Symbols) do
      begin
        mHashes.Add((UInt64(Cardinal(NameHash(mPair.Value.Catalog.Symbols[mIndex].Name))) shl 32) or
          UInt64(mKeys.Count));
      end;
      mKeys.Add(mPair.Key);
    end;
    mHashes.Sort;
    FNameHashes := mHashes.ToArray;
    FNameKeys := mKeys.ToArray;
    FNameGeneration := FGeneration;
  finally
    mKeys.Free;
    mHashes.Free;
  end;
end;

procedure TSymbolIndex.LoadColdNamed(const AName: string);
var
  mHash: UInt64;
  mLow, mHigh, mMiddle, mFrom, mTo, mPosition, mSymbol: Integer;
  mKeys: TArray<string>;
  mKey: string;
  mEntry: TIndexEntry;
  mUnit: TUnitIndex;
  mFound: Boolean;
begin
  mKeys := nil;
  FLock.Enter;
  try
    BuildNameLookupLocked;
    if Length(FNameHashes) = 0 then
    begin
      Exit;
    end;
    // Erster Eintrag mit diesem Hash (obere 32 Bit), dann alle gleichen.
    mHash := UInt64(Cardinal(NameHash(AName))) shl 32;
    mLow := 0;
    mHigh := Length(FNameHashes);
    while mLow < mHigh do
    begin
      mMiddle := (mLow + mHigh) shr 1;
      if FNameHashes[mMiddle] < mHash then
      begin
        mLow := mMiddle + 1;
      end
      else
      begin
        mHigh := mMiddle;
      end;
    end;
    mFrom := mLow;
    mTo := mFrom;
    while (mTo < Length(FNameHashes)) and ((FNameHashes[mTo] shr 32) = (mHash shr 32)) do
    begin
      Inc(mTo);
    end;
    for mPosition := mFrom to mTo - 1 do
    begin
      mKey := FNameKeys[Integer(FNameHashes[mPosition] and $FFFFFFFF)];
      if not FFiles.TryGetValue(mKey, mEntry) or mEntry.Loaded or (IndexText(mKey, mKeys) >= 0) then
      begin
        Continue;
      end;
      // Gleicher Hash heißt nicht gleicher Name.
      mFound := False;
      for mSymbol := 0 to High(mEntry.Catalog.Symbols) do
      begin
        if SameText(mEntry.Catalog.Symbols[mSymbol].Name, AName) then
        begin
          mFound := True;
          Break;
        end;
      end;
      if mFound then
      begin
        mKeys := mKeys + [mKey];
      end;
    end;
  finally
    FLock.Leave;
  end;
  for mKey in mKeys do
  begin
    LoadKey(mKey, mUnit);
  end;
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
  FLock.Enter;
  try
    // Eine Projekt-Unit ändert sich (Tippen, Speichern): neue uses zählen in der Nutzungsstatistik (Phase 3).
    if (FUsage <> nil) and not mPooled.Library_ and FFiles.TryGetValue(mKey, mOld) and mOld.Loaded then
    begin
      NoteAddedUsesLocked(mOld.Unit_, mPooled);
    end;
    RemoveFileLocked(mKey);
    AddLocked(mKey, mPooled, True, nil);
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
  FLock.Enter;
  try
    RemoveFileLocked(mKey);
    AddLocked(mKey, mPooled, False, ASource);
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
    FUnitFiles.AddOrSetValue(UpperCase(AHeader.UnitName), mKey);
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
    Account(mEntry, -1);
    mEntry.Pinned := True;
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
begin
  if FUnitFiles.TryGetValue(UpperCase(AUnitName), Result) then
  begin
    Exit;
  end;
  // Wie dcc: uses WinTypes lädt Winapi.Windows. Eine Unit, die selbst so heißt, geht vor.
  Result := '';
  if TUnitAliases.Target(FAliases, AUnitName, mTarget) and not FUnitFiles.TryGetValue(UpperCase(mTarget), Result) then
  begin
    Result := '';
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
begin
  // Symbole oberster Ebene verdrängter Units kennt der Katalog: diese Units zuerst laden.
  LoadColdNamed(AName);
  FLock.Enter;
  try
    Result := FRefs.ByName(AName);
  finally
    FLock.Leave;
  end;
end;

function TSymbolIndex.HasSymbol(const AName: string; const AMatch: TSymbolMatch): Boolean;
begin
  LoadColdNamed(AName);
  FLock.Enter;
  try
    Result := FRefs.HasName(AName, AMatch);
  finally
    FLock.Leave;
  end;
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
    for mEntry in FFiles.Values do
    begin
      if not mEntry.Loaded then
      begin
        Inc(Result.Cold);
        Continue;
      end;
      Inc(Result.Loaded);
      if mEntry.Pinned or (mEntry.Source = nil) then
      begin
        Inc(Result.Pinned);
      end
      else
      begin
        Inc(Result.Evictable);
      end;
    end;
    Result.EvictableBytes := FEvictableBytes;
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

end.
