unit dpcc.Common.Memory.Phase5.Tests;

// Speicher-Optimierung Phase 5 (Review der Phase 4): Tippen prüft den Schutz der Units aus den uses nicht neu (R1);
// FindSymbols schiebt das Verdrängen nicht mehr für den ganzen Index auf, die Spitze einer Suche bleibt im Budget (R2);
// der Blockleser ohne Opener liest nach einem Ergänzen weiter, und eine neu gebundene Unit fällt nicht aus dem Index
// (R3); Zwischenstände schreiben den Projekt-Cache, wenn Bibliotheks-Units außerhalb der Installation hinzukommen (R4);
// der gemerkte Stand eines gemeinsamen Caches samt Leser fällt mit dem letzten Dienst (R5); die Nutzungsstatistik
// startet keinen Thread ohne Grund und schreibt nie einen älteren Stand über einen neueren (R6); Anhängen nur an die
// bekannte Datei (R7); Überlesen prüft wie Dekodieren (R8); am Ende eines Aufbaus wird ein Cache mit zu viel
// ungenutztem Platz verdichtet (R9).

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract;

type
  [TestFixture]
  TDpccMemoryPhase5Tests = class
  private
    FFolder: string;
    /// <summary>Ein Aufbau mit Platte im Ordner AFolder (P.dpr, Lib\B.pas, Lib\C.pas); Ergebnis der Index.</summary>
    function BuildOnDisk(const AFolder: string; const AFileSystem: IIndexFileSystem): ISymbolIndex;
  public
    [SetupFixture]
    procedure WarmUp;
    [TearDownFixture]
    procedure CleanUp;
    /// <summary>R1: Neue Fassungen einer Projekt-Unit mit denselben uses (Tippen) prüfen den Schutz nicht neu; ein
    /// neuer oder weggefallener Name schon.</summary>
    [Test]
    procedure TypingDoesNotRefreshGuards;
    /// <summary>R2: Während FindSymbols die kalten Units eines Namens lädt, verdrängt ein anderer Thread weiter.
    /// </summary>
    [Test]
    procedure OtherThreadEvictsDuringSearch;
    /// <summary>R2: Vier Units desselben Namens über dem Budget: FindSymbols findet alle, die verdrängbaren bleiben
    /// dabei im Budget.</summary>
    [Test]
    procedure FrequentNameStaysInBudget;
    /// <summary>R3: Der Blockleser ohne Opener liest nach einem Ergänzen und nach einem abgebrochenen Ergänzen weiter;
    /// ein Schreiben ganz kopiert die alten Blöcke; nachladen nimmt keine Unit aus dem Index.</summary>
    [Test]
    procedure ReopeningReaderSurvivesAppend;
    /// <summary>R3: Scheitert das Nachladen, weil die Unit inzwischen einen neuen Block hat, lädt der Index aus ihm.
    /// </summary>
    [Test]
    procedure RebindDuringLoadKeepsUnit;
    /// <summary>R4: Ein Zwischenstand schreibt den Projekt-Cache, wenn eine Bibliotheks-Unit außerhalb der Installation
    /// hinzukam, sonst nicht.</summary>
    [Test]
    procedure FlushWritesProjectCacheForOutsideUnits;
    /// <summary>R5: Nach dem Stopp des letzten Dienstes kein gemerkter Stand und kein offener Leser mehr.</summary>
    [Test]
    procedure StopReleasesSharedState;
    /// <summary>R6: Ohne Änderung startet kein Schreiben im Hintergrund.</summary>
    [Test]
    procedure StatisticsNotDueStartsNoThread;
    /// <summary>R6: Ein später begonnenes Schreiben wartet auf ein laufendes; der neuere Stand bleibt.</summary>
    [Test]
    procedure StatisticsNewerStateWins;
    /// <summary>R7: Ist die Datei bei gleichem Zeitstempel ersetzt, hängt der Dienst nicht an, sondern schreibt ganz.
    /// </summary>
    [Test]
    procedure AppendRejectsReplacedFile;
    /// <summary>R8: Ein Block mit ungültiger Textnummer bzw. leerem Dateinamen wird auch beim Teil-Dekodieren
    /// verworfen.</summary>
    [Test]
    procedure SkippingChecksLikeDecoding;
    /// <summary>R9: Nach mehrmaligem Anhängen verdichtet das Schreiben am Ende die Datei, auch ohne neue Units.
    /// </summary>
    [Test]
    procedure EndOfBuildCompactsAppendedCache;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  System.Math,
  dpcc.Common.Index.Cache,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.NameIndex,
  dpcc.Common.Index.Service,
  dpcc.Common.Index.Adapters.DiskFileSystem,
  dpcc.Common.Memory.Phase1.Tests,
  dpcc.Windows.Documents.SharedRead;

type
  /// <summary>Block, dessen Laden wartet, bis der Test ihn freigibt (AEntered, ARelease gehören dem Test).</summary>
  TGateSource = class(TInterfacedObject, IIndexUnitSource)
  private
    FInner: IIndexUnitSource;
    FEntered: TEvent;
    FRelease: TEvent;
  public
    constructor Create(const AInner: IIndexUnitSource; AEntered, ARelease: TEvent);
    function Load(out AUnit: TUnitIndex): Boolean;
    function ReadBlock(out ABlock: TBytes; out AChecksum: Cardinal): Boolean;
    function BlockSize: Integer;
  end;

  /// <summary>Block, der beim Laden die verdrängbaren Bytes des Index notiert (außerhalb der Sperre).</summary>
  TPeekSource = class(TInterfacedObject, IIndexUnitSource)
  private
    FInner: IIndexUnitSource;
    // Ohne Referenz: Der Index hält die Quelle.
    FIndex: TSymbolIndex;
  public
    class var MaxEvictable: Int64;
    constructor Create(const AInner: IIndexUnitSource; AIndex: TSymbolIndex);
    function Load(out AUnit: TUnitIndex): Boolean;
    function ReadBlock(out ABlock: TBytes; out AChecksum: Cardinal): Boolean;
    function BlockSize: Integer;
  end;

  /// <summary>Block, der nicht lesbar ist, der Unit aber vorher einen neuen gibt (wie BindSources nach dem Schreiben
  /// des Caches während eines Nachladens).</summary>
  TRebindSource = class(TInterfacedObject, IIndexUnitSource)
  private
    FIndex: TSymbolIndex;
    FHeader: TUnitIndex;
    FGood: IIndexUnitSource;
  public
    constructor Create(AIndex: TSymbolIndex; const AHeader: TUnitIndex; const AGood: IIndexUnitSource);
    function Load(out AUnit: TUnitIndex): Boolean;
    function ReadBlock(out ABlock: TBytes; out AChecksum: Cardinal): Boolean;
    function BlockSize: Integer;
  end;

  /// <summary>Sucht einen Namen im eigenen Thread; Found = Zahl der Treffer.</summary>
  TSearchThread = class(TThread)
  private
    FIndex: ISymbolIndex;
    FName: string;
  protected
    procedure Execute; override;
  public
    Found: Integer;
    constructor Create(const AIndex: ISymbolIndex; const AName: string);
  end;

  /// <summary>Blockleser, der mitzählt, wie viele gerade leben (offene Handles).</summary>
  TCountedReader = class(TInterfacedObject, IIndexBlockReader)
  private
    FInner: IIndexBlockReader;
  public
    class var Alive: Integer;
    constructor Create(const AInner: IIndexBlockReader);
    destructor Destroy; override;
    function Read(AOffset: Int64; ACount: Integer; out ABytes: TBytes): Boolean;
    function Size: Int64;
    function Stamp: Int64;
  end;

  /// <summary>Dateisystem nur für Text: Das erste WriteText wartet, bis der Test es freigibt; LastText ist der zuletzt
  /// geschriebene Text.</summary>
  TBlockingTextFileSystem = class(TInterfacedObject, IIndexFileSystem)
  private
    FWrites: Integer;
    FLast: string;
  public
    Entered: TEvent;
    Release: TEvent;
    constructor Create;
    destructor Destroy; override;
    function LastText: string;
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    function ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
    function WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
    function TryLockWrite(const AFileName: string): IInterface;
    function OpenBlocks(const AFileName: string): IIndexBlockReader;
    function WriteStream(const AFileName: string; const AWrite: TIndexStreamWrite; out AError: string): Boolean;
  end;

{ TGateSource }

constructor TGateSource.Create(const AInner: IIndexUnitSource; AEntered, ARelease: TEvent);
begin
  inherited Create;
  FInner := AInner;
  FEntered := AEntered;
  FRelease := ARelease;
end;

function TGateSource.Load(out AUnit: TUnitIndex): Boolean;
begin
  FEntered.SetEvent;
  FRelease.WaitFor(10000);
  Result := FInner.Load(AUnit);
end;

function TGateSource.ReadBlock(out ABlock: TBytes; out AChecksum: Cardinal): Boolean;
begin
  Result := FInner.ReadBlock(ABlock, AChecksum);
end;

function TGateSource.BlockSize: Integer;
begin
  Result := FInner.BlockSize;
end;

{ TPeekSource }

constructor TPeekSource.Create(const AInner: IIndexUnitSource; AIndex: TSymbolIndex);
begin
  inherited Create;
  FInner := AInner;
  FIndex := AIndex;
end;

function TPeekSource.Load(out AUnit: TUnitIndex): Boolean;
begin
  MaxEvictable := Max(MaxEvictable, FIndex.LazyStats.EvictableBytes);
  Result := FInner.Load(AUnit);
end;

function TPeekSource.ReadBlock(out ABlock: TBytes; out AChecksum: Cardinal): Boolean;
begin
  Result := FInner.ReadBlock(ABlock, AChecksum);
end;

function TPeekSource.BlockSize: Integer;
begin
  Result := FInner.BlockSize;
end;

{ TRebindSource }

constructor TRebindSource.Create(AIndex: TSymbolIndex; const AHeader: TUnitIndex; const AGood: IIndexUnitSource);
begin
  inherited Create;
  FIndex := AIndex;
  FHeader := AHeader;
  FGood := AGood;
end;

function TRebindSource.Load(out AUnit: TUnitIndex): Boolean;
begin
  AUnit := Default(TUnitIndex);
  // Die Datei wurde eben neu geschrieben: Die Unit bekommt den neuen Block, der alte ist nicht mehr lesbar.
  FIndex.BindSources([FHeader], [FGood]);
  Result := False;
end;

function TRebindSource.ReadBlock(out ABlock: TBytes; out AChecksum: Cardinal): Boolean;
begin
  ABlock := nil;
  AChecksum := 0;
  Result := False;
end;

function TRebindSource.BlockSize: Integer;
begin
  Result := FGood.BlockSize;
end;

{ TSearchThread }

constructor TSearchThread.Create(const AIndex: ISymbolIndex; const AName: string);
begin
  FIndex := AIndex;
  FName := AName;
  Found := -1;
  inherited Create(True);
end;

procedure TSearchThread.Execute;
begin
  Found := Length(FIndex.FindSymbols(FName));
end;

{ TCountedReader }

constructor TCountedReader.Create(const AInner: IIndexBlockReader);
begin
  inherited Create;
  FInner := AInner;
  TInterlocked.Increment(Alive);
end;

destructor TCountedReader.Destroy;
begin
  TInterlocked.Decrement(Alive);
  inherited;
end;

function TCountedReader.Read(AOffset: Int64; ACount: Integer; out ABytes: TBytes): Boolean;
begin
  Result := FInner.Read(AOffset, ACount, ABytes);
end;

function TCountedReader.Size: Int64;
begin
  Result := FInner.Size;
end;

function TCountedReader.Stamp: Int64;
begin
  Result := FInner.Stamp;
end;

{ TBlockingTextFileSystem }

constructor TBlockingTextFileSystem.Create;
begin
  inherited Create;
  Entered := TEvent.Create(nil, True, False, '');
  Release := TEvent.Create(nil, True, False, '');
end;

destructor TBlockingTextFileSystem.Destroy;
begin
  Release.Free;
  Entered.Free;
  inherited;
end;

function TBlockingTextFileSystem.LastText: string;
begin
  TMonitor.Enter(Self);
  try
    Result := FLast;
  finally
    TMonitor.Exit(Self);
  end;
end;

function TBlockingTextFileSystem.FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
begin
  AStamp := 0;
  Result := False;
end;

function TBlockingTextFileSystem.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function TBlockingTextFileSystem.WriteText(const AFileName, AText: string): Boolean;
begin
  // Das erste Schreiben hängt, bis der Test es freigibt.
  if TInterlocked.Increment(FWrites) = 1 then
  begin
    Entered.SetEvent;
    Release.WaitFor(10000);
  end;
  TMonitor.Enter(Self);
  try
    FLast := AText;
  finally
    TMonitor.Exit(Self);
  end;
  Result := True;
end;

function TBlockingTextFileSystem.ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
begin
  ABytes := nil;
  Result := False;
end;

function TBlockingTextFileSystem.WriteBytes(const AFileName: string; const ABytes: TBytes;
  out AError: string): Boolean;
begin
  AError := '';
  Result := False;
end;

function TBlockingTextFileSystem.TryLockWrite(const AFileName: string): IInterface;
begin
  Result := nil;
end;

function TBlockingTextFileSystem.OpenBlocks(const AFileName: string): IIndexBlockReader;
begin
  Result := nil;
end;

function TBlockingTextFileSystem.WriteStream(const AFileName: string; const AWrite: TIndexStreamWrite;
  out AError: string): Boolean;
begin
  AError := '';
  Result := False;
end;

{ Hilfen }

/// <summary>Unit mit einem Typ ATop oberster Ebene und AMembers Mitgliedern "M" mit langer gleicher Signatur; rund
/// 430 Byte je Mitglied in der Schätzung.</summary>
function BigUnit(const AUnitName, ATop: string; AMembers: Integer): TUnitIndex;
var
  mIndex: Integer;
  mSignature: string;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AUnitName;
  Result.FileName := 'C:\L5\' + AUnitName + '.pas';
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

procedure AddColdEntry(const AIndex: ISymbolIndex; const AEntry: TIndexCacheEntry;
  const ASource: IIndexUnitSource = nil);
var
  mSource: IIndexUnitSource;
begin
  mSource := ASource;
  if mSource = nil then
  begin
    mSource := AEntry.Source;
  end;
  AIndex.AddCold(AEntry.Header, AEntry.Catalog, mSource, AEntry.SymbolCount, AEntry.UnavailableCount,
    AEntry.UsageCount);
end;

function ProjectUnit(const AUses: TArray<string>; const AHash: string): TUnitIndex;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := 'Haupt5';
  Result.FileName := 'C:\P5\Haupt5.pas';
  Result.Hash := AHash;
  Result.InterfaceUses := AUses;
  SetLength(Result.Symbols, 1);
  Result.Symbols[0].Name := 'Lokal' + AHash;
  Result.Symbols[0].Kind := TIndexSymbolKind.Variable;
end;

/// <summary>FNV-1a (32 Bit) wie die Prüfsumme der Blöcke.</summary>
function Fnv(const AData: TBytes): Cardinal;
var
  mIndex: Integer;
begin
  Result := 2166136261;
  for mIndex := 0 to High(AData) do
  begin
    Result := Cardinal(UInt64(Result xor AData[mIndex]) * 16777619);
  end;
end;

function ReadVarAt(const AData: TBytes; var APosition: Integer): UInt64;
var
  mShift: Integer;
  mByte: Byte;
begin
  Result := 0;
  mShift := 0;
  repeat
    mByte := AData[APosition];
    Inc(APosition);
    Result := Result or (UInt64(mByte and $7F) shl mShift);
    Inc(mShift, 7);
  until mByte < $80;
end;

function VarBytes(AValue: UInt64): TBytes;
begin
  Result := nil;
  while AValue >= $80 do
  begin
    Result := Result + [Byte(AValue and $7F) or $80];
    AValue := AValue shr 7;
  end;
  Result := Result + [Byte(AValue)];
end;

/// <summary>Block der einzigen Unit von AUnit (über Write und die gemeldete Lage, ohne das Verzeichnis zu lesen).
/// </summary>
function BlockOf(const AUnit: TUnitIndex): TBytes;
var
  mStream: TBytesStream;
  mPlaces: TArray<TIndexBlockPlace>;
begin
  mStream := TBytesStream.Create;
  try
    TIndexCache.Write(mStream, [TIndexCacheItem.OfUnit(AUnit)], mPlaces);
    Result := Copy(mStream.Bytes, Integer(mPlaces[0].Offset), mPlaces[0].Length);
  finally
    mStream.Free;
  end;
end;

/// <summary>Quelle über den Block ABlock mit passender Prüfsumme.</summary>
function SourceOfBlock(const ABlock: TBytes): IIndexUnitSource;
var
  mPlace: TIndexBlockPlace;
begin
  mPlace := Default(TIndexBlockPlace);
  mPlace.Offset := 0;
  mPlace.Length := Length(ABlock);
  mPlace.Checksum := Fnv(ABlock);
  mPlace.Written := True;
  Result := TIndexCache.SourceAt(TIndexBlockFiles.OfBytes(ABlock, 1), mPlace);
end;

/// <summary>Ungenutzte Bytes der Cache-Datei AFileName (Größe ohne Kopf, Verzeichnis und Blöcke).</summary>
function UnusedOf(const AFileSystem: IIndexFileSystem; const AFileName: string; out AUnits: Integer): Int64;
var
  mReader: IIndexBlockReader;
  mEntries: TArray<TIndexCacheEntry>;
  mEntry: TIndexCacheEntry;
  mReason: string;
  mBlocks: Int64;
begin
  mReader := AFileSystem.OpenBlocks(AFileName);
  mEntries := TIndexCache.ReadEntries(mReader, mReason);
  AUnits := Length(mEntries);
  mBlocks := 0;
  for mEntry in mEntries do
  begin
    Inc(mBlocks, mEntry.Source.BlockSize);
  end;
  Result := TIndexCache.UnusedBytes(mReader, mBlocks);
end;

/// <summary>Lassen sich alle Units der Cache-Datei AFileName dekodieren? AUnits: ihre Zahl.</summary>
function AllExpand(const AFileSystem: IIndexFileSystem; const AFileName: string; out AUnits: Integer): Boolean;
var
  mEntries: TArray<TIndexCacheEntry>;
  mEntry: TIndexCacheEntry;
  mReason: string;
  mBack: TUnitIndex;
begin
  mEntries := TIndexCache.ReadEntries(AFileSystem.OpenBlocks(AFileName), mReason);
  AUnits := Length(mEntries);
  Result := mReason = '';
  for mEntry in mEntries do
  begin
    Result := Result and TIndexCache.Expand(mEntry, mBack);
  end;
end;

function Never: Boolean;
begin
  Result := False;
end;

/// <summary>Auftrag für TIndexCacheWriter mit Caches in AFolder; Installation C:\L5.</summary>
function WriterRequest(const AFolder: string): TIndexRequest;
begin
  Result := Default(TIndexRequest);
  Result.CacheFile := TPath.Combine(AFolder, 'projekt-34.dpccidx');
  Result.LibraryCacheFile := TPath.Combine(AFolder, 'bibliothek-34.dpccidx');
  Result.LibraryRoots := ['C:\L5'];
  Result.LazyLibrary := True;
end;

{ TDpccMemoryPhase5Tests }

procedure TDpccMemoryPhase5Tests.WarmUp;
var
  mEvent: TEvent;
  mThread: TThread;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
begin
  // Einmal-Belegungen von TEvent, Threads, Kodierungen und der prozessweiten Tabellen vor dem Leckmonitor.
  mEvent := TEvent.Create(nil, True, False, '');
  mEvent.Free;
  mThread := TThread.CreateAnonymousThread(
    procedure
    begin
    end);
  mThread.FreeOnTerminate := False;
  mThread.Start;
  mThread.WaitFor;
  mThread.Free;
  FFolder := TPath.Combine(TPath.GetTempPath, 'dpcc-m5-' + IntToStr(MainThreadID));
  ForceDirectories(FFolder);
  mFileSystem := TDiskIndexFileSystem.Create;
  mIndex := BuildOnDisk(TPath.Combine(FFolder, 'vorlauf'), mFileSystem);
  mIndex := nil;
  TImportNames.Clear;
  TIndexCache.Deserialize(TIndexCache.Serialize([BigUnit('UWarm5', 'TopWarm5', 2)]));
end;

procedure TDpccMemoryPhase5Tests.CleanUp;
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

function TDpccMemoryPhase5Tests.BuildOnDisk(const AFolder: string; const AFileSystem: IIndexFileSystem): ISymbolIndex;
var
  mService: TIndexService;
  mRequest: TIndexRequest;
  mLib: string;
begin
  mLib := TPath.Combine(AFolder, 'Lib');
  ForceDirectories(mLib);
  TFile.WriteAllText(TPath.Combine(AFolder, 'P.dpr'), 'program P;'#13#10'uses B;'#13#10'begin end.');
  TFile.WriteAllText(TPath.Combine(mLib, 'B.pas'), 'unit B;'#13#10'interface'#13#10'type TB = class end;'#13#10 +
    'implementation'#13#10'end.');
  TFile.WriteAllText(TPath.Combine(mLib, 'C.pas'), 'unit C;'#13#10'interface'#13#10'type TC = class end;'#13#10 +
    'procedure RunC;'#13#10'implementation'#13#10'procedure RunC; begin end;'#13#10'end.');
  Result := TSymbolIndex.Create;
  mService := TIndexService.Create(Result, AFileSystem);
  try
    mRequest := Default(TIndexRequest);
    mRequest.Defines := ['DEBUG', 'MSWINDOWS'];
    mRequest.LibraryDefines := ['MSWINDOWS', 'WIN32'];
    mRequest.Files := [TPath.Combine(AFolder, 'P.dpr')];
    mRequest.LibraryFiles := [TPath.Combine(mLib, 'B.pas'), TPath.Combine(mLib, 'C.pas')];
    mRequest.LibraryRoots := [mLib];
    mRequest.ResolveUnit :=
      function(const AUnitName: string): string
      begin
        Result := TPath.Combine(mLib, AUnitName + '.pas');
      end;
    mRequest.CacheFile := TPath.Combine(AFolder, 'Cache\projekt-34.dpccidx');
    mRequest.LibraryCacheFile := TPath.Combine(AFolder, 'Cache\bibliothek-34.dpccidx');
    mRequest.LazyLibrary := True;
    mService.Start(mRequest);
    mService.WaitFor;
    Assert.IsTrue(TIndexService.KnowsSharedCache(AFileSystem, mRequest.LibraryCacheFile),
      'Stand des Bibliotheks-Caches gemerkt, solange der Dienst läuft');
  finally
    mService.Free;
  end;
end;

procedure TDpccMemoryPhase5Tests.TypingDoesNotRefreshGuards;
var
  mObject: TSymbolIndex;
  mIndex: ISymbolIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mUnit: TUnitIndex;
  mBefore, mKey: Integer;
begin
  mObject := TSymbolIndex.Create;
  mIndex := mObject;
  mEntries := EntriesOf([BigUnit('UR1', 'TopUR1', 3), BigUnit('UR2', 'TopUR2', 3)]);
  AddColdEntry(mIndex, mEntries[0]);
  AddColdEntry(mIndex, mEntries[1]);
  mEntries := nil;
  mIndex.AddUnit(ProjectUnit(['UR1'], '0'));
  Assert.IsTrue(mIndex.FindUnit('UR1', mUnit), 'UR1 geladen');
  Assert.IsTrue(mIndex.FindUnit('UR2', mUnit), 'UR2 geladen');
  mUnit := Default(TUnitIndex);
  Assert.AreEqual(1, mIndex.LazyStats.Evictable, 'UR1 geschützt, UR2 verdrängbar');
  mBefore := mObject.GuardRefreshes;
  // Tippen: jede Tipp-Pause bringt eine neue Fassung mit denselben uses.
  for mKey := 1 to 20 do
  begin
    mIndex.AddUnit(ProjectUnit(['UR1'], IntToStr(mKey)));
    mIndex.LazyStats;
  end;
  Assert.AreEqual(mBefore, mObject.GuardRefreshes, 'Tippen prüft den Schutz nicht neu');
  Assert.AreEqual(1, mIndex.LazyStats.Evictable, 'Schutz unverändert');
  // Ein neuer Name in den uses: einmal neu prüfen, UR2 ist jetzt geschützt.
  mIndex.AddUnit(ProjectUnit(['UR1', 'UR2'], 'neu'));
  Assert.AreEqual(0, mIndex.LazyStats.Evictable, 'UR2 geschützt');
  Assert.AreEqual(mBefore + 1, mObject.GuardRefreshes, 'neuer Name: neu geprüft');
  // Ein Name fällt weg: UR1 verdrängbar.
  mIndex.AddUnit(ProjectUnit(['UR2'], 'weg'));
  Assert.AreEqual(1, mIndex.LazyStats.Evictable, 'UR1 nicht mehr geschützt');
  Assert.AreEqual(mBefore + 2, mObject.GuardRefreshes, 'weggefallener Name: neu geprüft');
  mIndex := nil;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase5Tests.OtherThreadEvictsDuringSearch;
var
  mIndex: ISymbolIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mEntered, mRelease: TEvent;
  mThread: TSearchThread;
  mUnit: TUnitIndex;
  mName: string;
  mStats: TIndexLazyStats;
begin
  mIndex := TSymbolIndex.Create;
  mEntered := TEvent.Create(nil, True, False, '');
  mRelease := TEvent.Create(nil, True, False, '');
  mThread := nil;
  try
    // Eine kleine Unit mit dem gesuchten Namen, deren Laden hängt, und drei große (je rund 13 MB) ohne ihn.
    mEntries := EntriesOf([BigUnit('UH1', 'Haeufig5', 3), BigUnit('UF1', 'TopUF1', 28000),
      BigUnit('UF2', 'TopUF2', 28000), BigUnit('UF3', 'TopUF3', 28000)]);
    AddColdEntry(mIndex, mEntries[0], TGateSource.Create(mEntries[0].Source, mEntered, mRelease));
    AddColdEntry(mIndex, mEntries[1]);
    AddColdEntry(mIndex, mEntries[2]);
    AddColdEntry(mIndex, mEntries[3]);
    mEntries := nil;
    mThread := TSearchThread.Create(mIndex, 'haeufig5');
    mThread.Start;
    Assert.IsTrue(mEntered.WaitFor(10000) = wrSignaled, 'Suche lädt');
    // Während die Suche lädt: drei große Units über dem Budget. Phase 4 verdrängte jetzt nichts (FEvictDefer).
    for mName in ['UF1', 'UF2', 'UF3'] do
    begin
      Assert.IsTrue(mIndex.FindUnit(mName, mUnit), mName);
    end;
    mUnit := Default(TUnitIndex);
    mStats := mIndex.LazyStats;
    Assert.IsTrue(mStats.Evictions >= 1, 'anderer Thread verdrängt während der Suche');
    Assert.IsTrue(mStats.EvictableBytes <= TSymbolIndex.cEvictableBudget, 'im Budget');
    mRelease.SetEvent;
    mThread.WaitFor;
    Assert.AreEqual(1, mThread.Found, 'Suche vollständig');
  finally
    mRelease.SetEvent;
    if mThread <> nil then
    begin
      mThread.WaitFor;
      mThread.Free;
    end;
    mIndex := nil;
    mRelease.Free;
    mEntered.Free;
    TImportNames.Clear;
  end;
end;

procedure TDpccMemoryPhase5Tests.FrequentNameStaysInBudget;
var
  mObject: TSymbolIndex;
  mIndex: ISymbolIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mPick: Integer;
begin
  mObject := TSymbolIndex.Create;
  mIndex := mObject;
  TPeekSource.MaxEvictable := 0;
  // Vier Units zu je rund 13 MB mit demselben Namen oberster Ebene: zusammen über dem Budget von 32 MB.
  mEntries := EntriesOf([BigUnit('UQ1', 'Register5', 28000), BigUnit('UQ2', 'Register5', 28000),
    BigUnit('UQ3', 'Register5', 28000), BigUnit('UQ4', 'Register5', 28000)]);
  for mPick := 0 to High(mEntries) do
  begin
    AddColdEntry(mIndex, mEntries[mPick], TPeekSource.Create(mEntries[mPick].Source, mObject));
  end;
  mEntries := nil;
  Assert.AreEqual(4, Integer(Length(mIndex.FindSymbols('register5'))), 'alle vier gefunden');
  Assert.AreEqual(4, mIndex.LazyStats.Loads, 'jede einmal geladen');
  Assert.IsTrue(TPeekSource.MaxEvictable <= TSymbolIndex.cEvictableBudget,
    Format('während der Suche im Budget (%d MB)', [TPeekSource.MaxEvictable div (1024 * 1024)]));
  Assert.IsTrue(mIndex.LazyStats.EvictableBytes <= TSymbolIndex.cEvictableBudget, 'danach im Budget');
  Assert.IsTrue(mIndex.HasSymbol('Register5',
    function(const ASymbol: TIndexSymbol): Boolean
    begin
      Result := ASymbol.Kind = TIndexSymbolKind.ClassType;
    end), 'HasSymbol');
  mIndex := nil;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase5Tests.ReopeningReaderSurvivesAppend;
var
  mFileSystem: IIndexFileSystem;
  mAppend: IIndexFileAppend;
  mFile, mError, mReason: string;
  mItems, mCopies: TArray<TIndexCacheItem>;
  mPlaces, mMore: TArray<TIndexBlockPlace>;
  mOld: IIndexBlockReader;
  mEntries: TArray<TIndexCacheEntry>;
  mBack: TUnitIndex;
  mStamp: Int64;
  mCount: Integer;
  mStream: TFileStream;
  mTail: TBytes;
  mIndex: ISymbolIndex;
  mOut: TBytesStream;
begin
  // Ohne Opener der Plattform: TReopeningBlockReader (Tests, andere Plattformen).
  TIndexBlockFiles.Opener := nil;
  mFileSystem := TDiskIndexFileSystem.Create;
  Assert.IsTrue(Supports(mFileSystem, IIndexFileAppend, mAppend), 'Platte kann ergänzen');
  mFile := TPath.Combine(FFolder, 'reopen-34.dpccidx');
  mItems := [TIndexCacheItem.OfUnit(BigUnit('UA5', 'TopUA5', 5)), TIndexCacheItem.OfUnit(BigUnit('UB5', 'TopUB5', 6))];
  Assert.IsTrue(mFileSystem.WriteStream(mFile,
    function(AStream: TStream): Boolean
    begin
      Result := TIndexCache.Write(AStream, mItems, mPlaces) = 2;
    end, mError), 'geschrieben: ' + mError);
  mOld := mFileSystem.OpenBlocks(mFile);
  mEntries := TIndexCache.ReadEntries(mOld, mReason);
  Assert.AreEqual(2, Integer(Length(mEntries)), 'gelesen');
  mIndex := TSymbolIndex.Create;
  AddColdEntry(mIndex, mEntries[1]);
  // Ergänzen: UA5 und UB5 bleiben, UC5 kommt dazu.
  mItems := [TIndexCacheItem.OfEntry(mEntries[0]), TIndexCacheItem.OfEntry(mEntries[1]),
    TIndexCacheItem.OfUnit(BigUnit('UC5', 'TopUC5', 7))];
  Assert.IsTrue(mFileSystem.FileStamp(mFile, mStamp), 'Zeitstempel');
  mCount := 0;
  Assert.IsTrue(mAppend.AppendStream(mFile, mStamp,
    function(AStream: TStream): Boolean
    begin
      mCount := TIndexCache.Append(AStream, mItems,
        function(const ASource: IIndexUnitSource): Boolean
        begin
          Result := TIndexCache.ReaderOf(ASource) = mOld;
        end, mOld, mMore);
      Result := mCount >= 0;
    end, mError), 'ergänzt: ' + mError);
  Assert.AreEqual(3, mCount, 'drei Units');
  // Phase 4: Größe und Zeitstempel geändert, der Leser lehnte jeden Block ab.
  Assert.IsTrue(TIndexCache.Expand(mEntries[0], mBack) and (mBack.UnitName = 'UA5'), 'alter Leser liest weiter');
  Assert.IsTrue(mIndex.FindUnit('UB5', mBack), 'Nachladen nach dem Ergänzen');
  Assert.AreEqual(1, mIndex.UnitCount, 'Unit bleibt im Index');
  // Abgebrochenes Ergänzen: Daten am Ende, Kopf unverändert.
  mStream := TFileStream.Create(mFile, fmOpenReadWrite or fmShareDenyWrite);
  try
    mStream.Seek(0, soEnd);
    mTail := [1, 2, 3, 4, 5, 6, 7, 8];
    mStream.WriteBuffer(mTail[0], Length(mTail));
  finally
    mStream.Free;
  end;
  // Danach schreibt der Dienst ganz und kopiert die Blöcke über den alten Leser; vorher fehlten sie.
  mCopies := [TIndexCacheItem.OfEntry(mEntries[0]), TIndexCacheItem.OfEntry(mEntries[1])];
  mOut := TBytesStream.Create;
  try
    Assert.AreEqual(2, TIndexCache.Write(mOut, mCopies), 'alte Blöcke kopiert');
  finally
    mOut.Free;
  end;
  mIndex := nil;
  mEntries := nil;
  mItems := nil;
  mCopies := nil;
  mOld := nil;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase5Tests.RebindDuringLoadKeepsUnit;
var
  mObject: TSymbolIndex;
  mIndex: ISymbolIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mUnit: TUnitIndex;
begin
  mObject := TSymbolIndex.Create;
  mIndex := mObject;
  mEntries := EntriesOf([BigUnit('UN5', 'TopUN5', 4)]);
  AddColdEntry(mIndex, mEntries[0], TRebindSource.Create(mObject, mEntries[0].Header, mEntries[0].Source));
  mEntries := nil;
  Assert.IsTrue(mIndex.FindUnit('UN5', mUnit), 'aus dem neuen Block geladen');
  Assert.AreEqual(5, Integer(Length(mUnit.Symbols)), 'vollständig');
  Assert.AreEqual(1, mIndex.UnitCount, 'nicht aus dem Index genommen');
  mUnit := Default(TUnitIndex);
  mIndex := nil;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase5Tests.FlushWritesProjectCacheForOutsideUnits;
var
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mWriter: TIndexCacheWriter;
  mRequest: TIndexRequest;
  mOutside: TUnitIndex;
  mUnits: Integer;
  mStamp, mLater: Int64;
begin
  TIndexBlockFiles.Opener := nil;
  mFileSystem := TDiskIndexFileSystem.Create;
  mRequest := WriterRequest(TPath.Combine(FFolder, 'r4'));
  mIndex := TSymbolIndex.Create;
  mIndex.AddEvictable(BigUnit('UL5', 'TopUL5', 3), nil);
  mWriter := TIndexCacheWriter.Create(mIndex, mFileSystem, Default(TIndexCacheEvents), mRequest, Never);
  try
    mWriter.Load(nil);
    mWriter.FlushLibrary;
    Assert.IsTrue(FileExists(mRequest.LibraryCacheFile), 'Bibliothek geschrieben');
    Assert.IsFalse(FileExists(mRequest.CacheFile), 'ohne Units außerhalb der Installation kein Projekt-Cache');
    // Drittanbieter-Quelle außerhalb der Installation: gehört in den Projekt-Cache (#647).
    mOutside := BigUnit('UO5', 'TopUO5', 3);
    mOutside.FileName := 'C:\Fremd5\UO5.pas';
    mIndex.AddEvictable(mOutside, nil);
    mWriter.FlushLibrary;
    Assert.IsTrue(AllExpand(mFileSystem, mRequest.CacheFile, mUnits), 'Projekt-Cache lesbar');
    Assert.AreEqual(1, mUnits, 'mit der Unit außerhalb der Installation');
    // Nichts Neues: kein weiteres Schreiben.
    Assert.IsTrue(mFileSystem.FileStamp(mRequest.CacheFile, mStamp), 'Zeitstempel');
    TThread.Sleep(20);
    mWriter.FlushLibrary;
    Assert.IsTrue(mFileSystem.FileStamp(mRequest.CacheFile, mLater) and (mLater = mStamp), 'nicht neu geschrieben');
  finally
    mWriter.Free;
  end;
  mIndex := nil;
  TIndexService.ForgetSharedStates;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase5Tests.StopReleasesSharedState;
var
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mLibraryFile: string;
  mAlive: Integer;
begin
  mAlive := TCountedReader.Alive;
  TIndexBlockFiles.Opener :=
    function(const AFileName: string): IIndexBlockReader
    begin
      Result := TWindowsSharedRead.OpenBlocks(AFileName);
      if Result <> nil then
      begin
        Result := TCountedReader.Create(Result);
      end;
    end;
  try
    mFileSystem := TDiskIndexFileSystem.Create;
    // BuildOnDisk prüft, dass der Stand gemerkt ist, solange der Dienst läuft, und gibt den Dienst frei (Stopp).
    mIndex := BuildOnDisk(TPath.Combine(FFolder, 'r5'), mFileSystem);
    mLibraryFile := TPath.Combine(FFolder, 'r5\Cache\bibliothek-34.dpccidx');
    Assert.IsTrue(FileExists(mLibraryFile), 'Bibliotheks-Cache geschrieben');
    Assert.IsFalse(TIndexService.KnowsSharedCache(mFileSystem, mLibraryFile), 'nach dem Stopp kein gemerkter Stand');
    // Der Index hält die Blöcke seiner verdrängbaren Units noch; ohne ihn ist kein Leser mehr offen.
    mIndex := nil;
    TImportNames.Clear;
    Assert.AreEqual(mAlive, TCountedReader.Alive, 'kein offener Leser mehr');
  finally
    TIndexBlockFiles.Opener := nil;
  end;
end;

procedure TDpccMemoryPhase5Tests.StatisticsNotDueStartsNoThread;
var
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mStats: TIndexUsageStats;
  mService: TIndexService;
  mRound: Integer;
begin
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mIndex := TSymbolIndex.Create;
  mStats := TIndexUsageStats.Create(mFileSystem, 'C:\Cache5\usage.dat', 1000);
  mIndex.SetUsage(mStats);
  for mRound := 1 to 2 do
  begin
    // Zweiter Durchgang: geändert, aber noch nicht fällig (10 Minuten).
    if mRound = 2 then
    begin
      mStats.Note('Vcl.Forms', 3);
    end;
    mService := TIndexService.Create(mIndex, mFileSystem);
    try
      mService.EnsureUnit('Nirgends');
      mService.EnsureUnit('Nirgends');
      Assert.AreEqual(0, mService.BackgroundSaves, Format('Durchgang %d: kein Thread', [mRound]));
    finally
      mService.Free;
    end;
  end;
  mIndex := nil;
  mFileSystem := nil;
end;

procedure TDpccMemoryPhase5Tests.StatisticsNewerStateWins;
var
  mFiles: TBlockingTextFileSystem;
  mFileSystem: IIndexFileSystem;
  mStats: TIndexUsageStats;
  mHold: IIndexUsage;
  mFirst, mSecond: TThread;
begin
  mFiles := TBlockingTextFileSystem.Create;
  mFileSystem := mFiles;
  mStats := TIndexUsageStats.Create(mFileSystem, 'C:\Cache5\usage.dat', 1000);
  mHold := mStats;
  mStats.Note('Alt5', 10);
  mFirst := TThread.CreateAnonymousThread(
    procedure
    begin
      mStats.SaveIfDue(True);
    end);
  mFirst.FreeOnTerminate := False;
  mSecond := nil;
  try
    mFirst.Start;
    Assert.IsTrue(mFiles.Entered.WaitFor(10000) = wrSignaled, 'erstes Schreiben läuft');
    mStats.Note('Neu5', 10);
    mSecond := TThread.CreateAnonymousThread(
      procedure
      begin
        mStats.SaveIfDue(True);
      end);
    mSecond.FreeOnTerminate := False;
    mSecond.Start;
    // Phase 4: Das zweite Schreiben überholte das hängende erste, das danach den älteren Stand schrieb.
    TThread.Sleep(200);
    mFiles.Release.SetEvent;
    mFirst.WaitFor;
    mSecond.WaitFor;
    Assert.IsTrue(Pos('Neu5', mFiles.LastText) > 0, 'neuerer Stand zuletzt geschrieben: ' + mFiles.LastText);
    Assert.IsTrue(Pos('Alt5', mFiles.LastText) > 0, 'mit dem älteren Eintrag');
  finally
    mFiles.Release.SetEvent;
    mFirst.WaitFor;
    mFirst.Free;
    if mSecond <> nil then
    begin
      mSecond.WaitFor;
      mSecond.Free;
    end;
  end;
  mHold := nil;
  mFileSystem := nil;
end;

procedure TDpccMemoryPhase5Tests.AppendRejectsReplacedFile;
var
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mWriter: TIndexCacheWriter;
  mRequest: TIndexRequest;
  mStamp, mAfter: Int64;
  mError: string;
  mUnits: Integer;
begin
  TIndexBlockFiles.Opener :=
    function(const AFileName: string): IIndexBlockReader
    begin
      Result := TWindowsSharedRead.OpenBlocks(AFileName);
    end;
  try
    mFileSystem := TDiskIndexFileSystem.Create;
    mRequest := WriterRequest(TPath.Combine(FFolder, 'r7'));
    mIndex := TSymbolIndex.Create;
    mIndex.AddEvictable(BigUnit('UA7', 'TopUA7', 4), nil);
    mIndex.AddEvictable(BigUnit('UB7', 'TopUB7', 4), nil);
    mWriter := TIndexCacheWriter.Create(mIndex, mFileSystem, Default(TIndexCacheEvents), mRequest, Never);
    try
      mWriter.Load(nil);
      mWriter.FlushLibrary;
      Assert.IsTrue(mFileSystem.FileStamp(mRequest.LibraryCacheFile, mStamp), 'geschrieben');
      // Ein anderer ersetzt die Datei (andere Units, andere Größe) mit demselben Zeitstempel (auf ms gerundet).
      Assert.IsTrue(mFileSystem.WriteBytes(mRequest.LibraryCacheFile, TIndexCache.Serialize([
        BigUnit('UX7', 'TopUX7', 9), BigUnit('UY7', 'TopUY7', 9), BigUnit('UZ7', 'TopUZ7', 9)]), mError),
        'ersetzt: ' + mError);
      // Genau die gemerkte Millisekunde (FileStamp rundet die Ortszeit auf ms).
      TFile.SetLastWriteTime(mRequest.LibraryCacheFile, mStamp / MSecsPerDay);
      Assert.IsTrue(mFileSystem.FileStamp(mRequest.LibraryCacheFile, mAfter) and (mAfter = mStamp),
        'gleicher Zeitstempel');
      mIndex.AddEvictable(BigUnit('UC7', 'TopUC7', 4), nil);
      mWriter.FlushLibrary;
    finally
      mWriter.Free;
    end;
    // Phase 4 hängte an die fremde Datei an: Die Verweise auf UA7 und UB7 zeigten auf fremde Bytes.
    Assert.IsTrue(AllExpand(mFileSystem, mRequest.LibraryCacheFile, mUnits), 'jede Unit lesbar');
    Assert.AreEqual(6, mUnits, 'eigene drei und die drei des anderen');
    mIndex := nil;
  finally
    TIndexBlockFiles.Opener := nil;
    TIndexService.ForgetSharedStates;
    TImportNames.Clear;
  end;
end;

procedure TDpccMemoryPhase5Tests.SkippingChecksLikeDecoding;
var
  mUnit, mBack: TUnitIndex;
  mBlock, mBad: TBytes;
  mPosition, mCount, mIndex, mLast, mLength: Integer;
  mEntry: TIndexCacheEntry;
  mUsages: TArray<TIndexUsage>;
begin
  // a) Das letzte Symbol nennt als einziges den Text "RLetzt5", der als letzter in die String-Tabelle kommt. Ohne ihn
  // zeigt seine Nummer hinter die Tabelle.
  mUnit := BigUnit('US5', 'TopUS5', 2);
  mUnit.Library_ := False;
  mUnit.Symbols[2].Rationale := ['RLetzt5'];
  mBlock := BlockOf(mUnit);
  Assert.IsTrue(TIndexCache.LoadFrom(SourceOfBlock(mBlock), mBack, True), 'unverändert lesbar');
  mPosition := 0;
  mCount := Integer(ReadVarAt(mBlock, mPosition));
  mLast := 0;
  for mIndex := 0 to mCount - 1 do
  begin
    mLast := mPosition;
    mLength := Integer(ReadVarAt(mBlock, mPosition));
    Inc(mPosition, mLength);
  end;
  mBad := VarBytes(mCount - 1) + Copy(mBlock, Length(VarBytes(mCount)), mLast - Length(VarBytes(mCount))) +
    Copy(mBlock, mPosition, MaxInt);
  Assert.IsFalse(TIndexCache.LoadFrom(SourceOfBlock(mBad), mBack, True), 'volles Dekodieren verwirft');
  Assert.IsFalse(TIndexCache.LoadFrom(SourceOfBlock(mBad), mBack, False), 'ohne Verwendungen ebenso');
  mEntry := Default(TIndexCacheEntry);
  mEntry.Header := mUnit;
  mEntry.Header.Symbols := nil;
  mEntry.Source := SourceOfBlock(mBad);
  // Phase 4: Überlesen nahm jede Nummer an.
  Assert.IsFalse(TIndexCache.ExpandUsages(mEntry, mUsages), 'nur Verwendungen: Symbole überlesen und verworfen');
  // b) Leerer Dateiname: ReadUnitStart verwirft ihn, das Überlesen des Kopfes nun auch.
  mUnit.FileName := '';
  mUnit.Symbols[2].Rationale := nil;
  mBlock := BlockOf(mUnit);
  Assert.IsFalse(TIndexCache.LoadFrom(SourceOfBlock(mBlock), mBack, True), 'volles Dekodieren verwirft');
  mEntry.Source := SourceOfBlock(mBlock);
  Assert.IsFalse(TIndexCache.ExpandUsages(mEntry, mUsages), 'Kopf überlesen und verworfen');
end;

procedure TDpccMemoryPhase5Tests.EndOfBuildCompactsAppendedCache;
var
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mWriter: TIndexCacheWriter;
  mRequest: TIndexRequest;
  mUnits: Integer;
  mUnused: Int64;
  mSize: Int64;
  mName: string;
begin
  TIndexBlockFiles.Opener := nil;
  mFileSystem := TDiskIndexFileSystem.Create;
  mRequest := WriterRequest(TPath.Combine(FFolder, 'r9'));
  mIndex := TSymbolIndex.Create;
  mWriter := TIndexCacheWriter.Create(mIndex, mFileSystem, Default(TIndexCacheEvents), mRequest, Never);
  try
    mWriter.Load(nil);
    // Erster Aufbau: drei Zwischenstände, der zweite und dritte angehängt.
    for mName in ['UD9', 'UE9', 'UF9'] do
    begin
      mIndex.AddEvictable(BigUnit(mName, 'Top' + mName, 3), nil);
      mWriter.FlushLibrary;
    end;
    mUnused := UnusedOf(mFileSystem, mRequest.LibraryCacheFile, mUnits);
    Assert.AreEqual(3, mUnits, 'drei Units');
    Assert.IsTrue(mUnused > 0, 'alte Verzeichnisse ungenutzt');
    mSize := TFile.GetSize(mRequest.LibraryCacheFile);
    // Ende des Aufbaus: keine Unit neu (alles schon angehängt). Phase 4 schrieb dann nicht und ließ den Platz liegen.
    mWriter.WriteCaches(0);
  finally
    mWriter.Free;
  end;
  mUnused := UnusedOf(mFileSystem, mRequest.LibraryCacheFile, mUnits);
  Assert.AreEqual(Int64(0), mUnused, 'verdichtet');
  Assert.IsTrue(TFile.GetSize(mRequest.LibraryCacheFile) < mSize, 'kleiner');
  Assert.IsTrue(AllExpand(mFileSystem, mRequest.LibraryCacheFile, mUnits) and (mUnits = 3), 'alle lesbar');
  mIndex := nil;
  TIndexService.ForgetSharedStates;
  TImportNames.Clear;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccMemoryPhase5Tests);

end.
