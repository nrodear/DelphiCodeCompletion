unit dpcc.Common.Memory.Phase3.Tests;

// Speicher-Optimierung Phase 3: Index-Cache Format 34 (Blöcke je Unit mit eigener String-Tabelle und Prüfsumme,
// Verzeichnis mit Katalog am Ende, Einzel-Lesen über einen Blockleser), Katalog aller Units, bedarfsweises Laden und
// Verdrängen im Symbolindex, Bibliotheksstufe nur mit Katalog.

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract;

type
  [TestFixture]
  TDpccMemoryPhase3Tests = class
  private
    FFolder: string;
    // Dateisystem im Speicher für LazyLibraryBuildKeepsHullLoaded; einmal im Vorlauf benutzt, damit die prozessweit
    // gemerkten Stände der Caches (TSharedCacheWrites) im Test nur ersetzt werden.
    FLazyFiles: TObject;
    FLazyFileSystem: IIndexFileSystem;
  public
    /// <summary>Einmal-Belegungen (Kodierungen, Texttabellen) vor dem Leckmonitor.</summary>
    [SetupFixture]
    procedure WarmUp;
    [TearDownFixture]
    procedure CleanUp;
    /// <summary>Format 34: Symbole, Signaturen, Verwendungen und Kopf überstehen Schreiben und Lesen; das
    /// Verzeichnis trägt Kopf und Katalog ohne die Blöcke zu dekodieren.</summary>
    [Test]
    procedure RoundTripKeepsUnitsAndCatalog;
    /// <summary>Format 34: Das Verzeichnis lesen kostet zwei Lesevorgänge (Kopf, Verzeichnis); eine Unit dekodieren
    /// liest genau ihren Block.</summary>
    [Test]
    procedure SingleUnitReadsOnlyItsBlock;
    /// <summary>Format 34: Ein beschädigter Block betrifft nur seine Unit; ein beschädigtes Verzeichnis verwirft den
    /// Cache mit Grund.</summary>
    [Test]
    procedure DamagedBlockOnlyAffectsItsUnit;
    /// <summary>Ein Cache im Format 33 wird mit Grund verworfen (einmaliger Neuaufbau).</summary>
    [Test]
    procedure OldFormatIsRejected;
    /// <summary>Units, die nicht im Speicher sind, kopiert Write als unveränderten Block.</summary>
    [Test]
    procedure CopiedBlocksKeepTheirContent;
    /// <summary>Unter Windows: Wird die Datei ersetzt, während ein Blockleser sie offen hält, gelingt das Ersetzen,
    /// und der alte Leser liest weiter den Stand, zu dem sein Verzeichnis passt.</summary>
    [Test]
    procedure ReplacingKeepsOpenReaderConsistent;
    /// <summary>Eine Unit nur mit Katalog: FindHeader und Units laden sie nicht, der Katalog und der Namensindex
    /// kennen sie, FindUnit lädt sie nach; Generation bleibt dabei gleich.</summary>
    [Test]
    procedure ColdUnitLoadsOnDemand;
    /// <summary>Über cEvictableBudget verdrängt der Index die am seltensten bzw. am längsten nicht genutzte Unit;
    /// ihr Katalog bleibt, FindSymbols und FindUnit laden sie wieder. Gepinnte Units und solche aus den uses einer
    /// Projekt-Unit bleiben.</summary>
    [Test]
    procedure EvictsLeastUsedAndReloads;
    /// <summary>Aufbau mit LazyLibrary: Die Bibliotheksstufe übernimmt Units nur mit Katalog, die uses-Hülle des
    /// Projekts lädt und pinnt; ein neuer Cache kopiert die Blöcke nicht geladener Units unverändert.</summary>
    [Test]
    procedure LazyLibraryBuildKeepsHullLoaded;
    /// <summary>Nutzungsstatistik: Punkte halbieren sich je Woche, überstehen Schreiben und Lesen (usage.dat neben
    /// dem Bibliotheks-Cache); neue uses einer Projekt-Unit zählen 4 Punkte.</summary>
    [Test]
    procedure UsageStatisticsDecayAndPersist;
    /// <summary>Eine oft genutzte Unit lädt auch die Bibliotheksstufe gleich (gepinnt), die übrigen nur mit Katalog.
    /// </summary>
    [Test]
    procedure HotUnitIsLoadedAtBuild;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Index.Cache,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.NameIndex,
  dpcc.Common.Index.Service,
  dpcc.Common.Index.Builder,
  dpcc.Common.Index.Adapters.DiskFileSystem,
  dpcc.Common.Memory.Phase1.Tests,
  dpcc.Windows.Documents.SharedRead;

type
  /// <summary>Blockleser über Bytes, der jeden Lesevorgang mitzählt.</summary>
  TCountingBlockReader = class(TInterfacedObject, IIndexBlockReader)
  private
    FInner: IIndexBlockReader;
  public
    Reads: Integer;
    BytesRead: Int64;
    constructor Create(const ABytes: TBytes);
    function Read(AOffset: Int64; ACount: Integer; out ABytes: TBytes): Boolean;
    function Size: Int64;
    function Stamp: Int64;
  end;

constructor TCountingBlockReader.Create(const ABytes: TBytes);
begin
  inherited Create;
  FInner := TIndexBlockFiles.OfBytes(ABytes, 1);
end;

function TCountingBlockReader.Read(AOffset: Int64; ACount: Integer; out ABytes: TBytes): Boolean;
begin
  Inc(Reads);
  Inc(BytesRead, ACount);
  Result := FInner.Read(AOffset, ACount, ABytes);
end;

function TCountingBlockReader.Size: Int64;
begin
  Result := FInner.Size;
end;

function TCountingBlockReader.Stamp: Int64;
begin
  Result := FInner.Stamp;
end;

/// <summary>Unit mit einer Klasse, einer Methode, einer Routine samt Signatur und einer Verwendung.</summary>
function SampleUnit(const AUnitName, AFileName, ATag: string): TUnitIndex;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AUnitName;
  Result.FileName := AFileName;
  Result.Stamp := 42;
  Result.Hash := 'H' + ATag;
  Result.Library_ := True;
  Result.InterfaceUses := ['System.SysUtils', 'System.Classes'];
  Result.ImplementationUses := ['System.Math'];
  Result.UsagesIndexed := True;
  SetLength(Result.Symbols, 4);
  Result.Symbols[0].Name := 'TKunde' + ATag;
  Result.Symbols[0].Kind := TIndexSymbolKind.ClassType;
  Result.Symbols[0].InInterface := True;
  Result.Symbols[0].Ancestors := ['TPersistent'];
  Result.Symbols[0].TypeParams := 'T, U';
  Result.Symbols[0].SelectionRange := TTextRange.Create(5, 2, 5, 8);
  Result.Symbols[0].Signature := 'TKunde = class(TPersistent)';
  Result.Symbols[1].Name := 'Speichern';
  Result.Symbols[1].Container := 'TKunde' + ATag;
  Result.Symbols[1].Kind := TIndexSymbolKind.Method;
  Result.Symbols[1].InInterface := True;
  Result.Symbols[1].Signature := 'procedure Speichern(const AName: string);';
  Result.Symbols[1].ParamTypes := ['string'];
  Result.Symbols[1].MinArgs := 1;
  Result.Symbols[1].MaxArgs := 1;
  Result.Symbols[2].Name := 'Größe' + ATag;
  Result.Symbols[2].Kind := TIndexSymbolKind.Routine;
  Result.Symbols[2].InInterface := True;
  Result.Symbols[2].TypeName := 'Integer';
  Result.Symbols[2].SelectionRange := TTextRange.Create(9, 9, 9, 14);
  Result.Symbols[2].Signature := 'function Größe(A: Integer = 0): Integer;';
  Result.Symbols[2].MaxArgs := 1;
  Result.Symbols[2].Directives := ['overload'];
  Result.Symbols[3].Name := 'Intern';
  Result.Symbols[3].Kind := TIndexSymbolKind.Routine;
  SetLength(Result.Unavailable, 1);
  Result.Unavailable[0].Name := 'NurWin64';
  Result.Unavailable[0].Kind := TIndexSymbolKind.Constant;
  Result.Unavailable[0].Unavailable := True;
  SetLength(Result.Usages, 1);
  Result.Usages[0].Name := 'Speichern';
  Result.Usages[0].Positions := [TTextPosition.Create(12, 4), TTextPosition.Create(20, 6)];
end;

{ TDpccMemoryPhase3Tests }

procedure TDpccMemoryPhase3Tests.WarmUp;
var
  mBack: TArray<TUnitIndex>;
begin
  mBack := TIndexCache.Deserialize(TIndexCache.Serialize([SampleUnit('UWarm', 'C:\L\UWarm.pas', 'W')]));
  Assert.AreEqual(1, Integer(Length(mBack)), 'Vorlauf');
  FFolder := TPath.Combine(TPath.GetTempPath, 'dpcc-m3-' + IntToStr(MainThreadID));
  ForceDirectories(FFolder);
  FLazyFiles := TCountingIndexFileSystem.Create;
  FLazyFileSystem := TCountingIndexFileSystem(FLazyFiles);
  LazyLibraryBuildKeepsHullLoaded;
end;

procedure TDpccMemoryPhase3Tests.CleanUp;
begin
  FLazyFileSystem := nil;
  FLazyFiles := nil;
  if (FFolder <> '') and TDirectory.Exists(FFolder) then
  try
    TDirectory.Delete(FFolder, True);
  except
    // Ein Rest im Temp-Ordner stört keinen Test.
    on Exception do
      ;
  end;
end;

procedure TDpccMemoryPhase3Tests.RoundTripKeepsUnitsAndCatalog;
var
  mEntries: TArray<TIndexCacheEntry>;
  mBack: TUnitIndex;
  mReason: string;
begin
  mEntries := TIndexCache.ReadEntries(TIndexCache.Serialize([SampleUnit('UA', 'C:\L\UA.pas', 'A'),
    SampleUnit('UB', 'C:\L\UB.pas', 'B')]), mReason);
  Assert.AreEqual('', mReason, 'gültig');
  Assert.AreEqual(2, Integer(Length(mEntries)), 'zwei Units');
  Assert.AreEqual('UB', mEntries[1].Header.UnitName, 'Kopf aus dem Verzeichnis');
  Assert.AreEqual('HB', mEntries[1].Header.Hash, 'Hash');
  Assert.AreEqual(Int64(42), mEntries[1].Header.Stamp, 'Zeitstempel');
  Assert.IsTrue(mEntries[1].Header.Library_ and mEntries[1].Header.UsagesIndexed, 'Merker');
  Assert.AreEqual('System.Math', mEntries[1].Header.ImplementationUses[0], 'uses');
  Assert.AreEqual(0, Integer(Length(mEntries[1].Header.Symbols)), 'Verzeichnis ohne Symbole');
  Assert.AreEqual(4, mEntries[1].SymbolCount, 'Symbolzahl');
  Assert.AreEqual(2, Integer(Length(mEntries[1].Catalog.Symbols)), 'Katalog: TKundeB und GrößeB');
  Assert.AreEqual('GrößeB', mEntries[1].Catalog.Symbols[1].Name, 'Katalogname');
  Assert.AreEqual(9, mEntries[1].Catalog.Symbols[1].Start.Character, 'Startposition');
  Assert.AreEqual(1, Integer(mEntries[1].Catalog.Symbols[1].MaxArgs), 'MaxArgs');
  Assert.AreEqual('TPersistent', mEntries[1].Catalog.Symbols[0].Ancestors[0], 'Vorfahr im Katalog');
  Assert.AreEqual('TKundeB<T,U>', mEntries[1].Catalog.ExportedTypes[0], 'Typ mit Parametern');
  Assert.IsTrue(TIndexCache.Expand(mEntries[1], mBack), 'Block gelesen');
  Assert.AreEqual(4, Integer(Length(mBack.Symbols)), 'alle Symbole');
  Assert.AreEqual('function Größe(A: Integer = 0): Integer;', mBack.Symbols[2].Signature, 'Signatur');
  Assert.AreEqual('overload', mBack.Symbols[2].Directives[0], 'Direktive');
  Assert.AreEqual('NurWin64', mBack.Unavailable[0].Name, 'nicht verfügbar');
  Assert.AreEqual(20, mBack.Usages[0].Positions[1].Line, 'Verwendung');
  Assert.IsTrue(TIndexCache.Expand(mEntries[1], mBack, False), 'ohne Verwendungen');
  Assert.AreEqual(0, Integer(Length(mBack.Usages)), 'Verwendungen bleiben auf der Platte');
  Assert.IsTrue(mBack.UsagesOffloaded, 'ausgelagert');
end;

procedure TDpccMemoryPhase3Tests.SingleUnitReadsOnlyItsBlock;
var
  mData: TBytes;
  mReader: TCountingBlockReader;
  mHold: IIndexBlockReader;
  mEntries: TArray<TIndexCacheEntry>;
  mBack: TUnitIndex;
  mReason: string;
  mUnits: TArray<TUnitIndex>;
  mIndex: Integer;
begin
  SetLength(mUnits, 20);
  for mIndex := 0 to High(mUnits) do
  begin
    mUnits[mIndex] := SampleUnit('U' + IntToStr(mIndex), 'C:\L\U' + IntToStr(mIndex) + '.pas', IntToStr(mIndex));
  end;
  mData := TIndexCache.Serialize(mUnits);
  mReader := TCountingBlockReader.Create(mData);
  mHold := mReader;
  mEntries := TIndexCache.ReadEntries(mHold, mReason);
  Assert.AreEqual(20, Integer(Length(mEntries)), 'Verzeichnis');
  Assert.AreEqual(2, mReader.Reads, 'Kopf und Verzeichnis');
  mReader.Reads := 0;
  mReader.BytesRead := 0;
  Assert.IsTrue(TIndexCache.Expand(mEntries[13], mBack), 'eine Unit');
  Assert.AreEqual('U13', mBack.UnitName, 'die richtige');
  Assert.AreEqual(1, mReader.Reads, 'ein Lesevorgang');
  Assert.AreEqual(Int64(mEntries[13].Source.BlockSize), mReader.BytesRead, 'genau ihr Block');
  Assert.IsTrue(mReader.BytesRead * 10 < Length(mData), 'nicht die ganze Datei');
end;

procedure TDpccMemoryPhase3Tests.DamagedBlockOnlyAffectsItsUnit;
var
  mData, mBroken: TBytes;
  mEntries: TArray<TIndexCacheEntry>;
  mBack: TUnitIndex;
  mReason: string;
begin
  mData := TIndexCache.Serialize([SampleUnit('UA', 'C:\L\UA.pas', 'A'), SampleUnit('UB', 'C:\L\UB.pas', 'B')]);
  // Ein Byte mitten im ersten Block (er beginnt hinter dem 25 Byte langen Kopf).
  mBroken := Copy(mData);
  mBroken[40] := mBroken[40] xor $5A;
  mEntries := TIndexCache.ReadEntries(mBroken, mReason);
  Assert.AreEqual('', mReason, 'Verzeichnis unversehrt');
  Assert.AreEqual(2, Integer(Length(mEntries)), 'beide Einträge');
  Assert.IsFalse(TIndexCache.Expand(mEntries[0], mBack), 'beschädigter Block');
  Assert.AreEqual('UA', mBack.UnitName, 'Kopf bleibt');
  Assert.IsTrue(TIndexCache.Expand(mEntries[1], mBack), 'andere Unit lesbar');
  Assert.AreEqual(4, Integer(Length(mBack.Symbols)), 'vollständig');
  // Letztes Byte gehört zum Verzeichnis.
  mBroken := Copy(mData);
  mBroken[High(mBroken)] := mBroken[High(mBroken)] xor $5A;
  mEntries := TIndexCache.ReadEntries(mBroken, mReason);
  Assert.AreEqual(0, Integer(Length(mEntries)), 'Verzeichnis beschädigt: verworfen');
  Assert.AreNotEqual('', mReason, 'mit Grund');
  // Abgeschnitten.
  mEntries := TIndexCache.ReadEntries(Copy(mData, 0, Length(mData) - 3), mReason);
  Assert.AreEqual(0, Integer(Length(mEntries)), 'abgeschnitten: verworfen');
  Assert.AreNotEqual('', mReason, 'mit Grund');
end;

procedure TDpccMemoryPhase3Tests.OldFormatIsRejected;
var
  mData: TBytes;
  mReason: string;
begin
  mData := TIndexCache.Serialize([SampleUnit('UA', 'C:\L\UA.pas', 'A')]);
  mData[8] := 33;
  Assert.AreEqual(0, Integer(Length(TIndexCache.ReadEntries(mData, mReason))), 'verworfen');
  Assert.Contains(mReason, '33', 'Grund nennt die Version');
end;

procedure TDpccMemoryPhase3Tests.CopiedBlocksKeepTheirContent;
var
  mFirst: TArray<TIndexCacheEntry>;
  mItems: TArray<TIndexCacheItem>;
  mStream: TBytesStream;
  mSecond: TArray<TIndexCacheEntry>;
  mBack: TUnitIndex;
  mReason: string;
begin
  mFirst := TIndexCache.ReadEntries(TIndexCache.Serialize([SampleUnit('UA', 'C:\L\UA.pas', 'A')]), mReason);
  mItems := [TIndexCacheItem.OfEntry(mFirst[0]), TIndexCacheItem.OfUnit(SampleUnit('UB', 'C:\L\UB.pas', 'B'))];
  Assert.IsTrue(mItems[0].Source <> nil, 'als Block');
  mStream := TBytesStream.Create;
  try
    Assert.AreEqual(2, TIndexCache.Write(mStream, mItems), 'beide geschrieben');
    mSecond := TIndexCache.ReadEntries(Copy(mStream.Bytes, 0, mStream.Size), mReason);
  finally
    mStream.Free;
  end;
  Assert.AreEqual('', mReason, 'gültig');
  Assert.AreEqual(2, Integer(Length(mSecond)), 'zwei Units');
  Assert.AreEqual('TKundeA', mSecond[0].Catalog.Symbols[0].Name, 'Katalog der kopierten Unit');
  Assert.IsTrue(TIndexCache.Expand(mSecond[0], mBack), 'kopierter Block lesbar');
  Assert.AreEqual('procedure Speichern(const AName: string);', mBack.Symbols[1].Signature, 'Inhalt');
  Assert.IsTrue(TIndexCache.Expand(mSecond[1], mBack), 'neue Unit lesbar');
  Assert.AreEqual('UB', mBack.UnitName, 'neue Unit');
end;

procedure TDpccMemoryPhase3Tests.ReplacingKeepsOpenReaderConsistent;
var
  mFileSystem: IIndexFileSystem;
  mFile, mError, mReason: string;
  mOld, mNew: TArray<TIndexCacheEntry>;
  mBack: TUnitIndex;
  mFirst, mSecond: TBytes;
begin
  TIndexBlockFiles.Opener :=
    function(const AFileName: string): IIndexBlockReader
    begin
      Result := TWindowsSharedRead.OpenBlocks(AFileName);
    end;
  try
    mFileSystem := TDiskIndexFileSystem.Create;
    mFile := TPath.Combine(FFolder, 'index-34.dpccidx');
    mFirst := TIndexCache.Serialize([SampleUnit('UA', 'C:\L\UA.pas', 'A')]);
    Assert.IsTrue(mFileSystem.WriteBytes(mFile, mFirst, mError), 'erste Fassung: ' + mError);
    mOld := TIndexCache.ReadEntries(mFileSystem.OpenBlocks(mFile), mReason);
    Assert.AreEqual(1, Integer(Length(mOld)), 'erste Fassung gelesen');
    mSecond := TIndexCache.Serialize([SampleUnit('UB', 'C:\L\UB.pas', 'B'), SampleUnit('UC', 'C:\L\UC.pas', 'C')]);
    Assert.IsTrue(mFileSystem.WriteBytes(mFile, mSecond, mError), 'ersetzt trotz offenem Leser: ' + mError);
    Assert.IsTrue(TIndexCache.Expand(mOld[0], mBack), 'alter Leser liest weiter');
    Assert.AreEqual('TKundeA', mBack.Symbols[0].Name, 'den alten Stand');
    mNew := TIndexCache.ReadEntries(mFileSystem.OpenBlocks(mFile), mReason);
    Assert.AreEqual(2, Integer(Length(mNew)), 'neuer Leser: neuer Stand');
    Assert.IsTrue(TIndexCache.Expand(mNew[1], mBack), 'neuer Block lesbar');
    Assert.AreEqual('TKundeC', mBack.Symbols[0].Name, 'neuer Inhalt');
    mOld := nil;
    mNew := nil;
    Assert.IsTrue(mFileSystem.WriteBytes(mFile, mFirst, mError), 'ohne Leser ersetzbar: ' + mError);
  finally
    TIndexBlockFiles.Opener := nil;
  end;
end;

/// <summary>Große Unit: ein Typ TopX oberster Ebene und AMembers Mitglieder mit langer gleicher Signatur. Die Schätzung
/// (TIndexMemory.UnitBytes) zählt die geteilte Signatur je Symbol: rund 430 Byte je Mitglied.</summary>
function BigUnit(const AUnitName: string; AMembers: Integer; ALibrary: Boolean): TUnitIndex;
var
  mIndex: Integer;
  mSignature: string;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AUnitName;
  Result.FileName := 'C:\L\' + AUnitName + '.pas';
  Result.Stamp := 7;
  Result.Hash := 'H' + AUnitName;
  Result.Library_ := ALibrary;
  mSignature := StringOfChar('x', 290);
  SetLength(Result.Symbols, AMembers + 1);
  Result.Symbols[0].Name := 'Top' + AUnitName;
  Result.Symbols[0].Kind := TIndexSymbolKind.ClassType;
  Result.Symbols[0].InInterface := True;
  for mIndex := 1 to AMembers do
  begin
    Result.Symbols[mIndex].Name := 'M';
    Result.Symbols[mIndex].Container := 'Top' + AUnitName;
    Result.Symbols[mIndex].Kind := TIndexSymbolKind.Method;
    Result.Symbols[mIndex].InInterface := True;
    Result.Symbols[mIndex].Signature := mSignature;
  end;
end;

/// <summary>Einträge eines Caches aus AUnits (Blöcke im Speicher).</summary>
function EntriesOf(const AUnits: TArray<TUnitIndex>): TArray<TIndexCacheEntry>;
begin
  Result := TIndexCache.ReadEntries(TIndexCache.Serialize(AUnits));
end;

procedure AddColdEntry(const AIndex: ISymbolIndex; const AEntry: TIndexCacheEntry);
begin
  AIndex.AddCold(AEntry.Header, AEntry.Catalog, AEntry.Source, AEntry.SymbolCount, AEntry.UnavailableCount,
    AEntry.UsageCount);
end;

procedure TDpccMemoryPhase3Tests.ColdUnitLoadsOnDemand;
var
  mIndex: ISymbolIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mUnit: TUnitIndex;
  mGeneration: Int64;
begin
  mIndex := TSymbolIndex.Create;
  mEntries := EntriesOf([SampleUnit('UA', 'C:\L\UA.pas', 'A')]);
  AddColdEntry(mIndex, mEntries[0]);
  mEntries := nil;
  mGeneration := mIndex.Generation;
  Assert.AreEqual(1, mIndex.UnitCount, 'Index kennt die Unit');
  Assert.AreEqual(0, Integer(Length(mIndex.Units)), 'aber nicht geladen');
  Assert.IsTrue(mIndex.FindUnitHeader('UA', mUnit), 'Kopf');
  Assert.AreEqual(0, Integer(Length(mUnit.Symbols)), 'ohne Symbole');
  Assert.IsTrue(mIndex.FindHeader('c:\l\ua.pas', mUnit), 'Kopf über die Datei');
  Assert.AreEqual(0, mIndex.LazyStats.Loads, 'FindHeader lädt nicht');
  Assert.AreEqual(1, mIndex.LazyStats.Cold, 'nur im Katalog');
  Assert.AreEqual('GrößeA', mIndex.CatalogUnits[0].Symbols[1].Name, 'Katalog');
  Assert.AreEqual(2, TImportNames.Current(mIndex).Count, 'Namensindex über den Katalog');
  Assert.IsTrue(mIndex.FindUnit('UA', mUnit), 'FindUnit lädt nach');
  Assert.AreEqual(4, Integer(Length(mUnit.Symbols)), 'mit Symbolen');
  Assert.AreEqual(1, mIndex.LazyStats.Loads, 'ein Ladevorgang');
  Assert.AreEqual(1, Integer(Length(mIndex.Units)), 'jetzt geladen');
  Assert.AreEqual(mGeneration, mIndex.Generation, 'Nachladen ändert die Generation nicht');
  Assert.AreEqual('UA.Speichern', string.Join(' ', [mIndex.FindSymbols('speichern')[0].UnitName + '.' +
    mIndex.FindSymbols('speichern')[0].Symbol.Name]), 'Verweistabellen');
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase3Tests.EvictsLeastUsedAndReloads;
var
  mIndex: ISymbolIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mUnit: TUnitIndex;
  mGeneration: Int64;
  mProject: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  // Je rund 13 MB geschätzt: zwei passen ins Budget von 32 MB, drei nicht.
  mEntries := EntriesOf([BigUnit('UBig1', 28000, True), BigUnit('UBig2', 28000, True), BigUnit('UBig3', 28000,
    True)]);
  AddColdEntry(mIndex, mEntries[0]);
  AddColdEntry(mIndex, mEntries[1]);
  AddColdEntry(mIndex, mEntries[2]);
  mEntries := nil;
  mGeneration := mIndex.Generation;
  Assert.IsTrue(mIndex.FindUnit('UBig1', mUnit), 'UBig1 geladen');
  Assert.IsTrue(mIndex.FindUnit('UBig1', mUnit), 'UBig1 öfter genutzt');
  Assert.IsTrue(mIndex.FindUnit('UBig2', mUnit), 'UBig2 geladen');
  Assert.AreEqual(0, mIndex.LazyStats.Evictions, 'zwei passen');
  Assert.IsTrue(mIndex.FindUnit('UBig3', mUnit), 'UBig3 geladen');
  mUnit := Default(TUnitIndex);
  Assert.AreEqual(1, mIndex.LazyStats.Evictions, 'eine verdrängt');
  Assert.IsTrue(mIndex.FindUnitHeader('UBig1', mUnit) and (Length(mUnit.Symbols) > 0), 'die öfter genutzte bleibt');
  Assert.IsTrue(mIndex.FindUnitHeader('UBig2', mUnit) and (Length(mUnit.Symbols) = 0),
    'die seltener genutzte geht');
  Assert.IsTrue(mIndex.FindUnitHeader('UBig3', mUnit) and (Length(mUnit.Symbols) > 0), 'die eben geladene bleibt');
  mUnit := Default(TUnitIndex);
  Assert.IsTrue(mIndex.LazyStats.EvictableBytes <= TSymbolIndex.cEvictableBudget, 'im Budget');
  Assert.AreEqual(mGeneration, mIndex.Generation, 'Verdrängen ändert die Generation nicht');
  Assert.AreEqual(3, Integer(Length(mIndex.CatalogUnits)), 'Katalog behält alle');
  // FindSymbols lädt eine verdrängte Unit, deren Katalog den Namen kennt; dafür geht die seltener genutzte UBig3.
  Assert.AreEqual(1, Integer(Length(mIndex.FindSymbols('TopUBig2'))), 'Symbol oberster Ebene einer kalten Unit');
  Assert.AreEqual(2, mIndex.LazyStats.Evictions, 'dafür eine weitere verdrängt');
  Assert.IsTrue(mIndex.FindUnitHeader('UBig3', mUnit) and (Length(mUnit.Symbols) = 0), 'UBig3 verdrängt');
  mUnit := Default(TUnitIndex);
  // Eine Projekt-Unit nennt UBig3: Sie bleibt geladen, auch wenn sie am wenigsten genutzt ist. Seit Phase 4 zählt sie
  // wie eine gepinnte nicht gegen das Budget: UBig1 und UBig2 (26 MB) passen daneben, keine wird verdrängt.
  mProject := Default(TUnitIndex);
  mProject.UnitName := 'Haupt';
  mProject.FileName := 'C:\P\Haupt.pas';
  mProject.InterfaceUses := ['UBig3'];
  mIndex.AddUnit(mProject);
  Assert.IsTrue(mIndex.FindUnit('UBig3', mUnit), 'UBig3 wieder geladen');
  Assert.IsTrue(mIndex.FindUnit('UBig2', mUnit), 'UBig2 wieder geladen');
  mUnit := Default(TUnitIndex);
  Assert.IsTrue(mIndex.FindUnitHeader('UBig3', mUnit) and (Length(mUnit.Symbols) > 0), 'aus den uses gepinnt');
  Assert.IsTrue(mIndex.FindUnitHeader('UBig1', mUnit) and (Length(mUnit.Symbols) > 0),
    'UBig1 bleibt: UBig3 zählt nicht gegen das Budget');
  Assert.AreEqual(2, mIndex.LazyStats.Evictions, 'keine weitere verdrängt');
  Assert.IsTrue(mIndex.LazyStats.EvictableBytes <= TSymbolIndex.cEvictableBudget, 'verdrängbare im Budget');
  mUnit := Default(TUnitIndex);
  TImportNames.Clear;
end;

const
  cLazyLibraryCache = 'C:\Cache3\Bibliothek\index.dpccidx';
  cLazyProjectCache = 'C:\Cache3\Projekt\index.dpccidx';

function ResolveLazyUnit(const AUnitName: string): string;
begin
  Result := 'C:\Lib3\' + AUnitName + '.pas';
end;

/// <summary>Ein Aufbau mit frischem Index; liefert den Index.</summary>
function BuildLazy(const AFileSystem: IIndexFileSystem; const ALibraryFiles: TArray<string>): ISymbolIndex;
var
  mService: TIndexService;
  mRequest: TIndexRequest;
begin
  Result := TSymbolIndex.Create;
  mService := TIndexService.Create(Result, AFileSystem);
  try
    mRequest := Default(TIndexRequest);
    mRequest.Defines := ['DEBUG', 'MSWINDOWS'];
    mRequest.LibraryDefines := ['MSWINDOWS', 'WIN32'];
    mRequest.Files := ['C:\P3\P.dpr'];
    mRequest.LibraryFiles := ALibraryFiles;
    mRequest.LibraryRoots := ['C:\Lib3'];
    mRequest.ResolveUnit := ResolveLazyUnit;
    mRequest.CacheFile := cLazyProjectCache;
    mRequest.LibraryCacheFile := cLazyLibraryCache;
    mRequest.LazyLibrary := True;
    mService.Start(mRequest);
    mService.WaitFor;
  finally
    mService.Free;
  end;
end;

procedure TDpccMemoryPhase3Tests.LazyLibraryBuildKeepsHullLoaded;
var
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
  mStats: TIndexLazyStats;
  mError: string;
begin
  mFiles := TCountingIndexFileSystem(FLazyFiles);
  mFileSystem := FLazyFileSystem;
  // Ohne Caches beginnen (leer gilt als nicht vorhanden).
  mFiles.WriteBytes(cLazyLibraryCache, nil, mError);
  mFiles.WriteBytes(cLazyProjectCache, nil, mError);
  mFiles.Put('C:\P3\P.dpr', 'program P;'#10'uses B;'#10'begin end.', 1);
  mFiles.Put('C:\Lib3\B.pas', 'unit B;'#10'interface'#10'type TB = class end;'#10'implementation'#10'end.', 1);
  mFiles.Put('C:\Lib3\C.pas', 'unit C;'#10'interface'#10'type TC = class end;'#10'procedure RunC;'#10 +
    'implementation'#10'procedure RunC; begin end;'#10'end.', 1);
  mFiles.Put('C:\Lib3\D.pas', 'unit D;'#10'interface'#10'type TD = class end;'#10'implementation'#10'end.', 1);
  // Erster Aufbau ohne Cache: C wird gelesen, verdrängbar, und bekommt nach dem Schreiben seinen Block.
  mIndex := BuildLazy(mFileSystem, ['C:\Lib3\B.pas', 'C:\Lib3\C.pas']);
  mStats := mIndex.LazyStats;
  Assert.AreEqual(1, mStats.Evictable, 'C verdrängbar (Block gebunden)');
  Assert.AreEqual(2, mStats.Pinned, 'P und B gepinnt');
  // Zweiter Aufbau mit frischem Index aus dem Cache: C nur im Katalog.
  mIndex := BuildLazy(mFileSystem, ['C:\Lib3\B.pas', 'C:\Lib3\C.pas']);
  mStats := mIndex.LazyStats;
  Assert.AreEqual(1, mStats.Cold, 'C nur im Katalog');
  Assert.IsTrue(mIndex.FindUnitHeader('B', mUnit) and (Length(mUnit.Symbols) > 0), 'B aus der Hülle geladen');
  Assert.AreEqual(3, Integer(Length(mIndex.CatalogUnits)), 'Katalog kennt P, B und C');
  // Dritter Aufbau mit neuer Bibliotheks-Unit D: der Cache wird neu geschrieben, C als unveränderter Block.
  mIndex := BuildLazy(mFileSystem, ['C:\Lib3\B.pas', 'C:\Lib3\C.pas', 'C:\Lib3\D.pas']);
  mIndex := BuildLazy(mFileSystem, ['C:\Lib3\B.pas', 'C:\Lib3\C.pas', 'C:\Lib3\D.pas']);
  Assert.AreEqual(2, mIndex.LazyStats.Cold, 'C und D nur im Katalog');
  Assert.IsTrue(mIndex.FindUnit('C', mUnit), 'C nachgeladen');
  Assert.AreEqual('RunC', mUnit.Symbols[1].Name, 'kopierter Block vollständig');
  Assert.AreEqual(1, mIndex.LazyStats.Loads, 'ein Ladevorgang');
  mUnit := Default(TUnitIndex);
  mIndex := nil;
  TImportNames.Clear;
end;

procedure TDpccMemoryPhase3Tests.UsageStatisticsDecayAndPersist;
var
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mStats: TIndexUsageStats;
  mHold: IIndexUsage;
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
  mFile: string;
begin
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mFile := TIndexUsageStats.FileFor('C:\Cache4\Bibliothek\ABC\index-34.dpccidx');
  Assert.AreEqual('C:\Cache4\Bibliothek\ABC\usage.dat', mFile, 'neben dem Bibliotheks-Cache');
  mStats := TIndexUsageStats.Create(mFileSystem, mFile, 1000);
  mHold := mStats;
  mStats.Note('Vcl.Forms', 30);
  mStats.Note('VCL.FORMS', 2);
  mStats.Note('Selten', 1);
  Assert.AreEqual(32, mStats.Score('vcl.forms'), 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual(0, mStats.Score('Unbekannt'), 'unbekannt');
  mStats.SaveIfDue(True);
  // Eine und zwei Wochen später, neu gelesen.
  mStats := TIndexUsageStats.Create(mFileSystem, mFile, 1007);
  mHold := mStats;
  Assert.AreEqual(16, mStats.Score('Vcl.Forms'), 'nach einer Woche halbiert');
  Assert.AreEqual(0, mStats.Score('Selten'), 'fast vergessen');
  mStats := TIndexUsageStats.Create(mFileSystem, mFile, 1014);
  mHold := mStats;
  Assert.AreEqual(8, mStats.Score('Vcl.Forms'), 'nach zwei Wochen');
  // Angenommenes "+ Unit": eine Projekt-Unit nimmt eine Unit neu in die uses auf.
  mIndex := TSymbolIndex.Create;
  mIndex.SetUsage(mStats);
  mUnit := Default(TUnitIndex);
  mUnit.UnitName := 'Haupt';
  mUnit.FileName := 'C:\P4\Haupt.pas';
  mUnit.InterfaceUses := ['Vcl.Forms'];
  mIndex.AddUnit(mUnit);
  mUnit.InterfaceUses := ['Vcl.Forms', 'System.Neu'];
  mIndex.AddUnit(mUnit);
  Assert.AreEqual(4, mStats.Score('System.Neu'), 'neue uses zählen 4 Punkte');
  Assert.AreEqual(8, mStats.Score('Vcl.Forms'), 'vorhandene nicht');
  mIndex := nil;
  mHold := nil;
end;

procedure TDpccMemoryPhase3Tests.HotUnitIsLoadedAtBuild;
var
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mStats: TIndexUsageStats;
  mHold: IIndexUsage;
  mBuilder: TIndexBuilder;
  mHot, mCold: TUnitIndex;
  mStored: TIndexStoredUnit;
  mPinned: string;
begin
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mFiles.Put('C:\L4\Heiss.pas', 'unit Heiss;', 1);
  mFiles.Put('C:\L4\Kalt.pas', 'unit Kalt;', 1);
  mHot := BigUnit('Heiss', 3, True);
  mHot.FileName := 'C:\L4\Heiss.pas';
  mHot.Stamp := 1;
  mCold := BigUnit('Kalt', 3, True);
  mCold.FileName := 'C:\L4\Kalt.pas';
  mCold.Stamp := 1;
  mStats := TIndexUsageStats.Create(nil, '', 1000);
  mHold := mStats;
  mStats.Note('Heiss', cIndexHotScore + 1);
  mIndex := TSymbolIndex.Create;
  mBuilder := TIndexBuilder.Create(mIndex, mFileSystem, ['DEBUG'], nil);
  try
    mBuilder.LibraryRoots := ['C:\L4'];
    mBuilder.LibraryDefines := ['MSWINDOWS'];
    mBuilder.LazyLibrary := True;
    mBuilder.Usage := mHold;
    mBuilder.UseCache(TIndexCache.ReadEntries(TIndexCache.Serialize([mHot, mCold])));
    mBuilder.Build(nil, nil, ['C:\L4\Heiss.pas', 'C:\L4\Kalt.pas'], nil, nil, nil);
  finally
    mBuilder.Free;
  end;
  Assert.AreEqual(1, mIndex.LazyStats.Cold, 'Kalt nur im Katalog');
  mPinned := '';
  for mStored in mIndex.StoredUnits do
  begin
    if mStored.Loaded and mStored.Pinned then
    begin
      mPinned := mPinned + mStored.Unit_.UnitName;
    end;
  end;
  Assert.AreEqual('Heiss', mPinned, 'oft genutzte Unit geladen und gepinnt');
  mIndex := nil;
  mHold := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccMemoryPhase3Tests);

end.
