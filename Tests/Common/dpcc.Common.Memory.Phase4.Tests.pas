unit dpcc.Common.Memory.Phase4.Tests;

// Speicher-Optimierung Phase 4: Korrektheit und Kosten des bedarfsweisen Ladens. FindSymbols verdrängt keine eben
// geladene Unit desselben Namens; Units, die erst nach dem Aufbau ihres Namensverzeichnisses einen Block bekommen,
// bleiben auffindbar; geschützte Units (uses einer Projekt-Unit) zählen nicht gegen das Budget; Plätze der
// Verweistabellen werden wiederverwendet; ein zweiter Leser derselben kalten Unit liest den Block nicht noch einmal;
// Tippen baut das Namensverzeichnis nicht neu; Verdrängen sucht einmal je Lauf; aufgelöste Symbole übernehmen die
// Signatur ohne Dekodieren; Blöcke lassen sich ohne bzw. nur mit Verwendungen dekodieren; der Cache lässt sich an Ort
// und Stelle ergänzen.

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract;

type
  [TestFixture]
  TDpccMemoryPhase4Tests = class
  private
    FFolder: string;
  public
    [SetupFixture]
    procedure WarmUp;
    [TearDownFixture]
    procedure CleanUp;
    /// <summary>K1: Drei kalte Units mit demselben Namen oberster Ebene über cEvictableBudget: FindSymbols findet alle
    /// drei; erst danach verdrängt der Index wieder bis ins Budget.</summary>
    [Test]
    procedure BatchLoadFindsAllUnitsOfAName;
    /// <summary>K2: Eine verdrängbare Unit bekommt ihren Block erst nach dem ersten FindSymbols (BindSources); ist
    /// sie danach verdrängt, findet FindSymbols ihr Symbol oberster Ebene trotzdem.</summary>
    [Test]
    procedure BoundUnitStaysFindableAfterEviction;
    /// <summary>T1: Units aus den uses einer Projekt-Unit über 32 MB verdrängen die übrigen nicht; fallen sie aus den
    /// uses, zählen sie wieder.</summary>
    [Test]
    procedure GuardedUnitsDoNotCountAgainstBudget;
    /// <summary>B3/B4: Laden und Verdrängen im Wechsel lässt Plätze und Knoten der Verweistabellen nicht wachsen; die
    /// Verweise bleiben richtig.</summary>
    [Test]
    procedure LoadEvictChurnReusesSlots;
    /// <summary>B5: Zwei Threads laden dieselbe kalte Unit gleichzeitig: Der Block wird einmal gelesen.</summary>
    [Test]
    procedure ConcurrentLoadsReadBlockOnce;
    /// <summary>B1: Tippen in einer Projekt-Unit (AddUnit) baut das Namensverzeichnis der kalten Units nicht neu; eine
    /// neue kalte Unit schon.</summary>
    [Test]
    procedure TypingDoesNotRebuildNameLookup;
    /// <summary>B2: Viele Units bekommen auf einmal ihren Block (erster Aufbau): ein Verdrängungslauf.</summary>
    [Test]
    procedure MassEvictionIsOneRun;
    /// <summary>P1: TResolvedSymbol.FromIndex teilt die UTF-8-Signatur des Index; SignatureContains sucht darin.
    /// </summary>
    [Test]
    procedure ResolvedSymbolKeepsUtf8Signature;
    /// <summary>P3: Ein Block lässt sich ohne Verwendungen bzw. nur mit ihnen dekodieren.</summary>
    [Test]
    procedure BlockDecodesPartially;
    /// <summary>E1/E2: Write meldet die Lage der Blöcke; Append ergänzt die Datei an Ort und Stelle, alte Leser lesen
    /// weiter, ein abgebrochenes Ergänzen lässt den alten Stand gültig.</summary>
    [Test]
    procedure AppendKeepsBlocksAndReaders;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Index.Cache,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.NameIndex,
  dpcc.Common.Index.Adapters.DiskFileSystem,
  dpcc.Common.Semantics.NameResolver.Symbols,
  dpcc.Windows.Documents.SharedRead;

type
  /// <summary>Sucht eine Unit im eigenen Thread und merkt sich die Zahl ihrer Symbole (-1 = nicht gefunden).</summary>
  TFindThread = class(TThread)
  private
    FIndex: ISymbolIndex;
  protected
    procedure Execute; override;
  public
    Found: Integer;
    constructor Create(const AIndex: ISymbolIndex);
  end;

  /// <summary>Block, dessen Laden dauert und mitgezählt wird.</summary>
  TSlowSource = class(TInterfacedObject, IIndexUnitSource)
  private
    FInner: IIndexUnitSource;
  public
    Loads: Integer;
    constructor Create(const AInner: IIndexUnitSource);
    function Load(out AUnit: TUnitIndex): Boolean;
    function ReadBlock(out ABlock: TBytes; out AChecksum: Cardinal): Boolean;
    function BlockSize: Integer;
  end;

constructor TFindThread.Create(const AIndex: ISymbolIndex);
begin
  FIndex := AIndex;
  Found := -1;
  inherited Create(True);
end;

procedure TFindThread.Execute;
var
  mUnit: TUnitIndex;
begin
  if FIndex.FindUnit('UL1', mUnit) then
  begin
    Found := Length(mUnit.Symbols);
  end;
end;

constructor TSlowSource.Create(const AInner: IIndexUnitSource);
begin
  inherited Create;
  FInner := AInner;
end;

function TSlowSource.Load(out AUnit: TUnitIndex): Boolean;
begin
  TInterlocked.Increment(Loads);
  TThread.Sleep(150);
  Result := FInner.Load(AUnit);
end;

function TSlowSource.ReadBlock(out ABlock: TBytes; out AChecksum: Cardinal): Boolean;
begin
  Result := FInner.ReadBlock(ABlock, AChecksum);
end;

function TSlowSource.BlockSize: Integer;
begin
  Result := FInner.BlockSize;
end;

/// <summary>Unit mit einem Typ ATop oberster Ebene und AMembers Mitgliedern "M" mit langer gleicher Signatur; rund
/// 430 Byte je Mitglied in der Schätzung.</summary>
function BigUnit(const AUnitName, ATop: string; AMembers: Integer): TUnitIndex;
var
  mIndex: Integer;
  mSignature: string;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AUnitName;
  Result.FileName := 'C:\L4\' + AUnitName + '.pas';
  Result.Stamp := 7;
  Result.Hash := 'H' + AUnitName;
  Result.Library_ := True;
  mSignature := StringOfChar('x', 290);
  SetLength(Result.Symbols, AMembers + 1);
  Result.Symbols[0].Name := ATop;
  Result.Symbols[0].Kind := TIndexSymbolKind.ClassType;
  Result.Symbols[0].InInterface := True;
  for mIndex := 1 to AMembers do
  begin
    Result.Symbols[mIndex].Name := 'M';
    Result.Symbols[mIndex].Container := ATop;
    Result.Symbols[mIndex].Kind := TIndexSymbolKind.Method;
    Result.Symbols[mIndex].InInterface := True;
    Result.Symbols[mIndex].Signature := mSignature;
  end;
end;

function EntriesOf(const AUnits: TArray<TUnitIndex>): TArray<TIndexCacheEntry>;
begin
  Result := TIndexCache.ReadEntries(TIndexCache.Serialize(AUnits));
end;

procedure AddColdEntry(const AIndex: ISymbolIndex; const AEntry: TIndexCacheEntry);
begin
  AIndex.AddCold(AEntry.Header, AEntry.Catalog, AEntry.Source, AEntry.SymbolCount, AEntry.UnavailableCount,
    AEntry.UsageCount);
end;

function IsLoaded(const AIndex: ISymbolIndex; const AUnitName: string): Boolean;
var
  mUnit: TUnitIndex;
begin
  Result := AIndex.FindUnitHeader(AUnitName, mUnit) and (Length(mUnit.Symbols) > 0);
end;

function ProjectUnit(const AUses: TArray<string>): TUnitIndex;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := 'Haupt4';
  Result.FileName := 'C:\P4\Haupt4.pas';
  Result.InterfaceUses := AUses;
end;

{ TDpccMemoryPhase4Tests }

procedure TDpccMemoryPhase4Tests.WarmUp;
var
  mBack: TArray<TUnitIndex>;
  mEvent: TEvent;
begin
  mBack := TIndexCache.Deserialize(TIndexCache.Serialize([BigUnit('UWarm4', 'TopWarm', 2)]));
  Assert.AreEqual(1, Integer(Length(mBack)), 'Vorlauf');
  // Einmal-Belegungen von TEvent und Thread-Verwaltung vor dem Leckmonitor.
  mEvent := TEvent.Create(nil, True, False, '');
  mEvent.Free;
  FFolder := TPath.Combine(TPath.GetTempPath, 'dpcc-m4-' + IntToStr(MainThreadID));
  ForceDirectories(FFolder);
  ConcurrentLoadsReadBlockOnce;
end;

procedure TDpccMemoryPhase4Tests.CleanUp;
begin
  if (FFolder <> '') and TDirectory.Exists(FFolder) then
  try
    TDirectory.Delete(FFolder, True);
  except
    // Ein Rest im Temp-Ordner stört keinen Test.
    on Exception do
      ;
  end;
end;

procedure TDpccMemoryPhase4Tests.BatchLoadFindsAllUnitsOfAName;
var
  mIndex: ISymbolIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mEntry: TIndexCacheEntry;
begin
  mIndex := TSymbolIndex.Create;
  // Je rund 13 MB: zwei passen ins Budget von 32 MB, drei nicht. Alle drei haben "Gemeinsam" oberster Ebene.
  mEntries := EntriesOf([BigUnit('UK1', 'Gemeinsam', 28000), BigUnit('UK2', 'Gemeinsam', 28000),
    BigUnit('UK3', 'Gemeinsam', 28000)]);
  for mEntry in mEntries do
  begin
    AddColdEntry(mIndex, mEntry);
  end;
  mEntries := nil;
  Assert.AreEqual(3, Integer(Length(mIndex.FindSymbols('gemeinsam'))), 'alle drei Units gefunden');
  Assert.AreEqual(3, mIndex.LazyStats.Loads, 'jede einmal geladen');
  Assert.AreEqual(1, mIndex.LazyStats.Evictions, 'erst danach eine verdrängt');
  Assert.IsTrue(mIndex.LazyStats.EvictableBytes <= TSymbolIndex.cEvictableBudget, 'wieder im Budget');
  Assert.IsTrue(mIndex.HasSymbol('Gemeinsam',
    function(const ASymbol: TIndexSymbol): Boolean
    begin
      Result := ASymbol.Kind = TIndexSymbolKind.ClassType;
    end), 'HasSymbol ebenso');
  Assert.AreEqual(3, Integer(Length(mIndex.FindSymbols('Gemeinsam'))), 'auch beim zweiten Mal');
  mIndex := nil;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase4Tests.BoundUnitStaysFindableAfterEviction;
var
  mIndex: ISymbolIndex;
  mBound: TUnitIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mUnit: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  // Erster Aufbau ohne Cache: UB4 neu gelesen, verdrängbar, aber noch ohne Block; UB5 und UB6 aus dem Cache.
  mBound := BigUnit('UB4', 'TopUB4', 28000);
  mEntries := EntriesOf([mBound, BigUnit('UB5', 'TopUB5', 28000), BigUnit('UB6', 'TopUB6', 28000)]);
  mIndex.AddEvictable(mBound, nil);
  mBound := Default(TUnitIndex);
  AddColdEntry(mIndex, mEntries[1]);
  AddColdEntry(mIndex, mEntries[2]);
  // Eine Suche baut das Namensverzeichnis, solange UB4 noch keinen Block hat.
  Assert.AreEqual(0, Integer(Length(mIndex.FindSymbols('Unbekannt'))), 'nichts gefunden');
  // Der Cache ist geschrieben: UB4 bekommt ihren Block und darf gehen (Generation bleibt).
  Assert.AreEqual(1, mIndex.BindSources([mEntries[0].Header], [mEntries[0].Source]), 'Block gebunden');
  mEntries := nil;
  // UB5 und UB6 öfter genutzt: Beim Laden der dritten geht UB4.
  Assert.IsTrue(mIndex.FindUnit('UB5', mUnit) and mIndex.FindUnit('UB5', mUnit), 'UB5');
  Assert.IsTrue(mIndex.FindUnit('UB6', mUnit) and mIndex.FindUnit('UB6', mUnit), 'UB6');
  mUnit := Default(TUnitIndex);
  Assert.IsFalse(IsLoaded(mIndex, 'UB4'), 'UB4 verdrängt');
  Assert.AreEqual(1, Integer(Length(mIndex.FindSymbols('TopUB4'))), 'Symbol oberster Ebene trotzdem gefunden');
  mIndex := nil;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase4Tests.GuardedUnitsDoNotCountAgainstBudget;
var
  mIndex: ISymbolIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mEntry: TIndexCacheEntry;
  mUnit: TUnitIndex;
  mName: string;
  mStats: TIndexLazyStats;
begin
  mIndex := TSymbolIndex.Create;
  mEntries := EntriesOf([BigUnit('UG1', 'TopUG1', 28000), BigUnit('UG2', 'TopUG2', 28000),
    BigUnit('UG3', 'TopUG3', 28000), BigUnit('US1', 'TopUS1', 2000), BigUnit('US2', 'TopUS2', 2000),
    BigUnit('US3', 'TopUS3', 2000), BigUnit('US4', 'TopUS4', 2000), BigUnit('US5', 'TopUS5', 2000)]);
  for mEntry in mEntries do
  begin
    AddColdEntry(mIndex, mEntry);
  end;
  mEntries := nil;
  // Eine Projekt-Unit nennt UG1 bis UG3 (zusammen rund 39 MB) in ihren uses.
  mIndex.AddUnit(ProjectUnit(['UG1', 'UG2', 'UG3']));
  for mName in ['UG1', 'UG2', 'UG3', 'US1', 'US2', 'US3', 'US4'] do
  begin
    Assert.IsTrue(mIndex.FindUnit(mName, mUnit), mName);
  end;
  mUnit := Default(TUnitIndex);
  mStats := mIndex.LazyStats;
  Assert.AreEqual(0, mStats.Evictions, 'nichts verdrängt');
  Assert.AreEqual(4, mStats.Evictable, 'nur US1 bis US4 verdrängbar');
  Assert.IsTrue(mStats.EvictableBytes < 8 * 1024 * 1024, 'geschützte zählen nicht');
  // Fallen sie aus den uses, zählen sie wieder: Das nächste Laden geht ins Budget zurück.
  mIndex.AddUnit(ProjectUnit(nil));
  Assert.IsTrue(mIndex.FindUnit('US5', mUnit), 'US5');
  mUnit := Default(TUnitIndex);
  mStats := mIndex.LazyStats;
  Assert.IsTrue(mStats.Evictions >= 1, 'jetzt verdrängt');
  Assert.IsTrue(mStats.EvictableBytes <= TSymbolIndex.cEvictableBudget, 'im Budget');
  mIndex := nil;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase4Tests.LoadEvictChurnReusesSlots;
const
  cUnits = 20;
var
  mObject: TSymbolIndex;
  mIndex: ISymbolIndex;
  mUnits: TArray<TUnitIndex>;
  mEntries: TArray<TIndexCacheEntry>;
  mEntry: TIndexCacheEntry;
  mUnit: TUnitIndex;
  mRound, mPick, mLoaded, mSlots, mNodes: Integer;
begin
  mObject := TSymbolIndex.Create;
  mIndex := mObject;
  // 20 Units zu je rund 1,7 MB: Zusammen passen sie nicht ins Budget, jedes Nachladen verdrängt eine andere.
  SetLength(mUnits, cUnits);
  for mPick := 0 to cUnits - 1 do
  begin
    mUnits[mPick] := BigUnit('UC' + IntToStr(mPick), 'TopUC' + IntToStr(mPick), 4000);
  end;
  mEntries := EntriesOf(mUnits);
  mUnits := nil;
  for mEntry in mEntries do
  begin
    AddColdEntry(mIndex, mEntry);
  end;
  mEntries := nil;
  for mPick := 0 to cUnits - 1 do
  begin
    mIndex.FindUnit('UC' + IntToStr(mPick), mUnit);
  end;
  mSlots := mObject.RefSlots;
  mNodes := mObject.RefNodes;
  for mRound := 1 to 3 do
  begin
    for mPick := 0 to cUnits - 1 do
    begin
      Assert.IsTrue(mIndex.FindUnit('UC' + IntToStr(mPick), mUnit), 'geladen');
    end;
  end;
  mUnit := Default(TUnitIndex);
  Assert.IsTrue(mIndex.LazyStats.Evictions > cUnits, 'Laden und Verdrängen im Wechsel');
  Assert.IsTrue(mObject.RefSlots <= mSlots + 1, Format('Plätze wiederverwendet (%d, vorher %d)',
    [mObject.RefSlots, mSlots]));
  // Tote Knoten langer Ketten ("M") bleiben, bis die Hälfte der Kette tot ist: höchstens doppelt so viele.
  Assert.IsTrue(mObject.RefNodes <= 2 * mNodes + 4001, Format('Knoten wiederverwendet (%d, vorher %d)',
    [mObject.RefNodes, mNodes]));
  // Die Verweise stimmen: je geladene Unit 4000 Mitglieder "M", keine der verdrängten.
  mLoaded := mIndex.LazyStats.Loaded;
  Assert.AreEqual(mLoaded * 4000, Integer(Length(mIndex.FindSymbols('M'))), 'nur Verweise geladener Units');
  mIndex := nil;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase4Tests.ConcurrentLoadsReadBlockOnce;
var
  mIndex: ISymbolIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mSlow: TSlowSource;
  mHold: IIndexUnitSource;
  mThreads: array[0..1] of TFindThread;
  mPick: Integer;
begin
  mIndex := TSymbolIndex.Create;
  mEntries := EntriesOf([BigUnit('UL1', 'TopUL1', 50)]);
  mSlow := TSlowSource.Create(mEntries[0].Source);
  mHold := mSlow;
  mIndex.AddCold(mEntries[0].Header, mEntries[0].Catalog, mHold, mEntries[0].SymbolCount,
    mEntries[0].UnavailableCount, mEntries[0].UsageCount);
  mEntries := nil;
  mThreads[0] := TFindThread.Create(mIndex);
  mThreads[1] := TFindThread.Create(mIndex);
  try
    mThreads[0].Start;
    mThreads[1].Start;
    mThreads[0].WaitFor;
    mThreads[1].WaitFor;
    Assert.AreEqual(1, mSlow.Loads, 'Block einmal gelesen');
    Assert.AreEqual(51, mThreads[0].Found, 'erster Leser');
    Assert.AreEqual(51, mThreads[1].Found, 'zweiter Leser übernimmt das Ergebnis');
  finally
    for mPick := 0 to 1 do
    begin
      mThreads[mPick].Free;
    end;
  end;
  Assert.AreEqual(1, mIndex.LazyStats.Loads, 'ein Ladevorgang');
  mIndex := nil;
  mHold := nil;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase4Tests.TypingDoesNotRebuildNameLookup;
var
  mObject: TSymbolIndex;
  mIndex: ISymbolIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mEntry: TIndexCacheEntry;
  mProject: TUnitIndex;
  mKey: Integer;
begin
  mObject := TSymbolIndex.Create;
  mIndex := mObject;
  mEntries := EntriesOf([BigUnit('UT1', 'TopUT1', 3), BigUnit('UT2', 'TopUT2', 3)]);
  for mEntry in mEntries do
  begin
    AddColdEntry(mIndex, mEntry);
  end;
  Assert.AreEqual(0, Integer(Length(mIndex.FindSymbols('Nichts'))), 'erste Suche');
  Assert.AreEqual(1, mObject.NameLookupBuilds, 'Namensverzeichnis gebaut');
  // Tippen: jede Tipp-Pause bringt eine neue Fassung der Projekt-Unit (neue Generation).
  for mKey := 1 to 20 do
  begin
    mProject := ProjectUnit(['UT1']);
    mProject.Hash := IntToStr(mKey);
    SetLength(mProject.Symbols, 1);
    mProject.Symbols[0].Name := 'Lokal' + IntToStr(mKey);
    mProject.Symbols[0].Kind := TIndexSymbolKind.Variable;
    mIndex.AddUnit(mProject);
    mIndex.FindSymbols('Lokal' + IntToStr(mKey));
  end;
  Assert.AreEqual(1, mObject.NameLookupBuilds, 'Tippen baut es nicht neu');
  Assert.AreEqual(1, Integer(Length(mIndex.FindSymbols('TopUT2'))), 'kalte Unit gefunden');
  // Eine neue kalte Unit ändert die Menge: einmal neu.
  mEntries := EntriesOf([BigUnit('UT3', 'TopUT3', 3)]);
  AddColdEntry(mIndex, mEntries[0]);
  mEntries := nil;
  Assert.AreEqual(1, Integer(Length(mIndex.FindSymbols('TopUT3'))), 'neue kalte Unit gefunden');
  Assert.AreEqual(2, mObject.NameLookupBuilds, 'jetzt neu gebaut');
  mIndex := nil;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase4Tests.MassEvictionIsOneRun;
const
  cUnits = 20;
var
  mObject: TSymbolIndex;
  mIndex: ISymbolIndex;
  mUnits: TArray<TUnitIndex>;
  mEntries: TArray<TIndexCacheEntry>;
  mHeaders: TArray<TUnitIndex>;
  mSources: TArray<IIndexUnitSource>;
  mPick: Integer;
begin
  mObject := TSymbolIndex.Create;
  mIndex := mObject;
  SetLength(mUnits, cUnits);
  for mPick := 0 to cUnits - 1 do
  begin
    mUnits[mPick] := BigUnit('UE' + IntToStr(mPick), 'TopUE' + IntToStr(mPick), 4000);
    // Erster Aufbau ohne Cache: alle neu gelesen, noch ohne Block.
    mIndex.AddEvictable(mUnits[mPick], nil);
  end;
  Assert.AreEqual(0, mObject.EvictionRuns, 'ohne Block nichts zu verdrängen');
  mEntries := EntriesOf(mUnits);
  mUnits := nil;
  SetLength(mHeaders, cUnits);
  SetLength(mSources, cUnits);
  for mPick := 0 to cUnits - 1 do
  begin
    mHeaders[mPick] := mEntries[mPick].Header;
    mSources[mPick] := mEntries[mPick].Source;
  end;
  mEntries := nil;
  Assert.AreEqual(cUnits, mIndex.BindSources(mHeaders, mSources), 'alle gebunden');
  mHeaders := nil;
  mSources := nil;
  Assert.AreEqual(1, mObject.EvictionRuns, 'ein Lauf');
  Assert.IsTrue(mIndex.LazyStats.Evictions >= 1, 'verdrängt');
  Assert.IsTrue(mIndex.LazyStats.EvictableBytes <= TSymbolIndex.cEvictableBudget, 'im Budget');
  mIndex := nil;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase4Tests.ResolvedSymbolKeepsUtf8Signature;
var
  mUnit: TUnitIndex;
  mResolved: TResolvedSymbol;
begin
  mUnit := Default(TUnitIndex);
  mUnit.UnitName := 'UP';
  mUnit.FileName := 'C:\L4\UP.pas';
  SetLength(mUnit.Symbols, 2);
  mUnit.Symbols[0].Name := 'Foo';
  mUnit.Symbols[0].Kind := TIndexSymbolKind.Routine;
  mUnit.Symbols[0].Signature := 'procedure Foo(A: Integer); overload;';
  mUnit.Symbols[1].Name := 'Größe';
  mUnit.Symbols[1].Kind := TIndexSymbolKind.Routine;
  mUnit.Symbols[1].Signature := 'function Größe: Integer;';
  mResolved := TResolvedSymbol.FromIndex(mUnit, mUnit.Symbols[0]);
  Assert.IsTrue(Pointer(mResolved.SignatureUtf8) = Pointer(mUnit.Symbols[0].SignatureUtf8),
    'UTF-8 geteilt, nicht dekodiert');
  Assert.AreEqual('procedure Foo(A: Integer); overload;', mResolved.Signature, 'beim Lesen dekodiert');
  Assert.IsTrue(mResolved.SignatureContains('OVERLOAD'), 'ohne Groß-/Kleinschreibung');
  Assert.IsFalse(mResolved.SignatureContains('virtual'), 'fehlt');
  mResolved := TResolvedSymbol.FromIndex(mUnit, mUnit.Symbols[1]);
  Assert.IsTrue(mResolved.SignatureContains('größe'), 'ohne ASCII über den Text');
  mResolved.Signature := 'property Wert: Integer read FWert;';
  Assert.IsTrue(mResolved.SignatureContains('read'), 'gesetzt');
end;

procedure TDpccMemoryPhase4Tests.BlockDecodesPartially;
var
  mUnit, mBack: TUnitIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mUsages: TArray<TIndexUsage>;
begin
  mUnit := BigUnit('UD', 'TopUD', 3);
  mUnit.Library_ := False;
  mUnit.UsagesIndexed := True;
  mUnit.InterfaceUses := ['System.SysUtils'];
  SetLength(mUnit.Usages, 2);
  mUnit.Usages[0].Name := 'Foo';
  mUnit.Usages[0].Positions := [TTextPosition.Create(3, 4), TTextPosition.Create(9, 1)];
  mUnit.Usages[1].Name := 'Bar';
  mUnit.Usages[1].Positions := [TTextPosition.Create(12, 7)];
  mEntries := EntriesOf([mUnit]);
  Assert.IsTrue(TIndexCache.ExpandUsages(mEntries[0], mUsages), 'nur Verwendungen');
  Assert.AreEqual(2, Integer(Length(mUsages)), 'beide');
  Assert.AreEqual(9, mUsages[0].Positions[1].Line, 'Stelle');
  Assert.AreEqual('Bar', mUsages[1].Name, 'Name');
  Assert.IsTrue(TIndexCache.LoadFrom(mEntries[0].Source, mBack, False), 'ohne Verwendungen');
  Assert.AreEqual(4, Integer(Length(mBack.Symbols)), 'alle Symbole');
  Assert.AreEqual(0, Integer(Length(mBack.Usages)), 'Verwendungen überlesen');
  Assert.AreEqual('System.SysUtils', mBack.InterfaceUses[0], 'Kopf');
  Assert.IsTrue(TIndexCache.Expand(mEntries[0], mBack, False) and mBack.UsagesOffloaded, 'ausgelagert');
  Assert.IsTrue(TIndexCache.Expand(mEntries[0], mBack, True) and (Length(mBack.Usages) = 2), 'mit Verwendungen');
end;

procedure TDpccMemoryPhase4Tests.AppendKeepsBlocksAndReaders;
var
  mFileSystem: IIndexFileSystem;
  mAppend: IIndexFileAppend;
  mFile, mError, mReason: string;
  mItems: TArray<TIndexCacheItem>;
  mPlaces, mMore: TArray<TIndexBlockPlace>;
  mFirst: IIndexBlockReader;
  mSources: TArray<IIndexUnitSource>;
  mEntries: TArray<TIndexCacheEntry>;
  mBack: TUnitIndex;
  mStamp, mSizeBefore: Int64;
  mCount: Integer;
  mStream: TFileStream;
  mTail: TBytes;
begin
  TIndexBlockFiles.Opener :=
    function(const AFileName: string): IIndexBlockReader
    begin
      Result := TWindowsSharedRead.OpenBlocks(AFileName);
    end;
  try
    mFileSystem := TDiskIndexFileSystem.Create;
    Assert.IsTrue(Supports(mFileSystem, IIndexFileAppend, mAppend), 'Platte kann ergänzen');
    mFile := TPath.Combine(FFolder, 'append-34.dpccidx');
    mItems := [TIndexCacheItem.OfUnit(BigUnit('UA4', 'TopUA4', 5)), TIndexCacheItem.OfUnit(BigUnit('UB4', 'TopUB4', 6))];
    Assert.IsTrue(mFileSystem.WriteStream(mFile,
      function(AStream: TStream): Boolean
      begin
        Result := TIndexCache.Write(AStream, mItems, mPlaces) = 2;
      end, mError), 'geschrieben: ' + mError);
    // E2: die Blöcke aus der gemeldeten Lage, ohne das Verzeichnis zu lesen.
    mFirst := mFileSystem.OpenBlocks(mFile);
    mSources := [TIndexCache.SourceAt(mFirst, mPlaces[0]), TIndexCache.SourceAt(mFirst, mPlaces[1])];
    Assert.IsTrue(mSources[1].Load(mBack) and (mBack.UnitName = 'UB4'), 'Block aus der Lage');
    // E1: UA4 und UB4 stehen schon in der Datei (Leser mFirst), UC4 kommt dazu.
    mItems[0].Source := mSources[0];
    mItems[0].SymbolCount := 6;
    mItems[1].Source := mSources[1];
    mItems[1].SymbolCount := 7;
    mItems := mItems + [TIndexCacheItem.OfUnit(BigUnit('UC4', 'TopUC4', 7))];
    Assert.IsTrue(mFileSystem.FileStamp(mFile, mStamp), 'Zeitstempel');
    mSizeBefore := mFirst.Size;
    mCount := 0;
    Assert.IsTrue(mAppend.AppendStream(mFile, mStamp,
      function(AStream: TStream): Boolean
      begin
        mCount := TIndexCache.Append(AStream, mItems,
          function(const ASource: IIndexUnitSource): Boolean
          begin
            Result := TIndexCache.ReaderOf(ASource) = mFirst;
          end, mMore);
        Result := mCount >= 0;
      end, mError), 'ergänzt: ' + mError);
    Assert.AreEqual(3, mCount, 'drei Units im neuen Verzeichnis');
    Assert.AreEqual(mPlaces[0].Offset, mMore[0].Offset, 'UA4 bleibt an ihrer Stelle');
    Assert.IsTrue(mMore[2].Offset >= mSizeBefore, 'UC4 am Ende');
    Assert.IsTrue(mSources[0].Load(mBack) and (mBack.UnitName = 'UA4'), 'alter Leser liest weiter');
    mEntries := TIndexCache.ReadEntries(mFileSystem.OpenBlocks(mFile), mReason);
    Assert.AreEqual('', mReason, 'gültig');
    Assert.AreEqual(3, Integer(Length(mEntries)), 'neuer Leser sieht drei');
    Assert.IsTrue(TIndexCache.Expand(mEntries[2], mBack) and (mBack.Symbols[0].Name = 'TopUC4'), 'neuer Block');
    Assert.IsTrue(TIndexCache.Expand(mEntries[0], mBack) and (mBack.Symbols[0].Name = 'TopUA4'), 'alter Block');
    // Ein abgebrochenes Ergänzen (Daten am Ende, Kopf unverändert) lässt den Stand gültig.
    mEntries := nil;
    mFirst := nil;
    mSources := nil;
    mStream := TFileStream.Create(mFile, fmOpenReadWrite or fmShareDenyWrite);
    try
      mStream.Seek(0, soEnd);
      mTail := [1, 2, 3, 4, 5, 6, 7, 8];
      mStream.WriteBuffer(mTail[0], Length(mTail));
    finally
      mStream.Free;
    end;
    mEntries := TIndexCache.ReadEntries(mFileSystem.OpenBlocks(mFile), mReason);
    Assert.AreEqual(3, Integer(Length(mEntries)), 'Rest am Ende stört nicht: ' + mReason);
    // Hat ein anderer die Datei geändert, ergänzt AppendStream nicht.
    Assert.IsFalse(mAppend.AppendStream(mFile, mStamp - 1,
      function(AStream: TStream): Boolean
      begin
        Result := True;
      end, mError), 'geänderte Datei');
    mEntries := nil;
  finally
    TIndexBlockFiles.Opener := nil;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccMemoryPhase4Tests);

end.
