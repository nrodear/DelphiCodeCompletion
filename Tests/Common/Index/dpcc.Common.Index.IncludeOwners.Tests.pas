unit dpcc.Common.Index.IncludeOwners.Tests;

// Auftrag L3, Punkt 12: Symbole aus .inc-Dateien verdrängter Bibliotheks-Units. TIndexFiles.UnitOf fand die
// einbindende Unit nur unter den geladenen; jetzt kennt der Index die Zuordnung Include-Datei → Unit aus dem Kopf
// jeder Unit (auch kalter, aus dem Verzeichnis des Caches) und lädt die gefundene über FindFile nach. Nur APIs, die es
// vor L3 schon gab (UnitOf, AddCold, AddEvictable, TrimEvictable, LazyStats): Gegen den alten Stand schlagen
// ColdOwnerIsFoundAndLoaded, EvictedOwnerIsReloaded, SameNameUnitsKeepTheirFiles und IdeIndexFindsColdOwner fehl.

interface

uses
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract;

type
  [TestFixture]
  TIndexIncludeOwnersTests = class
  public
    /// <summary>Einmal-Belegungen (Kodierungen der Cache-Blöcke) vor dem Leckmonitor.</summary>
    [SetupFixture]
    procedure WarmUp;
    /// <summary>Kalte Unit (nur Kopf und Katalog): Die Include-Datei führt auf sie, FindFile lädt sie mit dem
    /// Symbol aus der .inc nach; genau ein Ladevorgang.</summary>
    [Test]
    procedure ColdOwnerIsFoundAndLoaded;
    /// <summary>Verdrängte Unit (erst geladen, dann TrimEvictable): Die Zuordnung bleibt, die Unit kommt wieder.
    /// </summary>
    [Test]
    procedure EvictedOwnerIsReloaded;
    /// <summary>Binden eine geladene und eine kalte Unit dieselbe Datei ein, gilt die geladene, ohne Nachladen.
    /// </summary>
    [Test]
    procedure LoadedOwnerNeedsNoLoad;
    /// <summary>Gleichnamige Units (L2) in zwei Ordnern mit je eigener Include-Datei: Jede Datei führt auf ihre Unit.
    /// </summary>
    [Test]
    procedure SameNameUnitsKeepTheirFiles;
    /// <summary>Nach RemoveFile führt die Include-Datei auf keine Unit mehr; eine unbekannte Datei auch nicht.
    /// </summary>
    [Test]
    procedure RemovedOwnerIsForgotten;
    /// <summary>Über den Index des Editors (TIdeIndex: gemeinsamer Index plus Ersatz-Units) wie direkt.</summary>
    [Test]
    procedure IdeIndexFindsColdOwner;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Index.Cache,
  dpcc.Common.Index.Files,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Lsp.IdeIndex;

const
  VendorFile = 'C:\Lib\Vendor.Lib.pas';
  VendorInclude = 'C:\Lib\Vendor.Decl.inc';
  ExtraFile = 'C:\Extra\Vendor.Lib.pas';
  ExtraInclude = 'C:\Extra\Vendor.Decl.inc';

/// <summary>Bibliotheks-Unit AUnitName in AFileName, die AInclude einbindet: ein Typ aus der Unit selbst und ein
/// Record ARecord aus der Include-Datei (TIndexSymbol.FileName).</summary>
function IncludingUnit(const AUnitName, AFileName, AInclude, ARecord: string): TUnitIndex;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AUnitName;
  Result.FileName := AFileName;
  Result.Stamp := 42;
  Result.Hash := 'H' + AFileName;
  Result.Library_ := True;
  Result.Includes := [AInclude];
  Result.IncludeStamps := [7];
  SetLength(Result.Symbols, 2);
  Result.Symbols[0].Name := 'TVendorLib';
  Result.Symbols[0].Kind := TIndexSymbolKind.ClassType;
  Result.Symbols[0].InInterface := True;
  Result.Symbols[0].SelectionRange := TTextRange.Create(4, 2, 4, 12);
  Result.Symbols[0].Range := Result.Symbols[0].SelectionRange;
  Result.Symbols[1].Name := ARecord;
  Result.Symbols[1].Kind := TIndexSymbolKind.RecordType;
  Result.Symbols[1].InInterface := True;
  Result.Symbols[1].FileName := AInclude;
  Result.Symbols[1].SelectionRange := TTextRange.Create(1, 2, 1, 2 + Length(ARecord));
  Result.Symbols[1].Range := Result.Symbols[1].SelectionRange;
end;

/// <summary>Einträge eines Caches aus AUnits (Blöcke im Speicher), wie beim Start aus der Datei.</summary>
function EntriesOf(const AUnits: TArray<TUnitIndex>): TArray<TIndexCacheEntry>;
begin
  Result := TIndexCache.ReadEntries(TIndexCache.Serialize(AUnits));
end;

procedure AddColdEntry(const AIndex: ISymbolIndex; const AEntry: TIndexCacheEntry);
begin
  AIndex.AddCold(AEntry.Header, AEntry.Catalog, AEntry.Source, AEntry.SymbolCount, AEntry.UnavailableCount,
    AEntry.UsageCount);
end;

/// <summary>Hat AUnit ein Symbol namens AName aus der Datei AFileName?</summary>
function HasSymbolFrom(const AUnit: TUnitIndex; const AName, AFileName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.Name, AName) and SameText(mSymbol.FileName, AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TIndexIncludeOwnersTests }

procedure TIndexIncludeOwnersTests.WarmUp;
var
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  AddColdEntry(mIndex, EntriesOf([IncludingUnit('Vendor.Lib', VendorFile, VendorInclude, 'TVendorDecl')])[0]);
  TIndexFiles.UnitOf(mIndex, VendorInclude, mUnit);
end;

procedure TIndexIncludeOwnersTests.ColdOwnerIsFoundAndLoaded;
var
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  AddColdEntry(mIndex, EntriesOf([IncludingUnit('Vendor.Lib', VendorFile, VendorInclude, 'TVendorDecl')])[0]);
  Assert.AreEqual(1, mIndex.LazyStats.Cold, 'nur im Katalog');
  Assert.AreEqual(0, Integer(Length(mIndex.Units)), 'nicht geladen');
  // Schreibweise wie in TIndexSymbol.FileName, nicht wie im Kopf.
  Assert.IsTrue(TIndexFiles.UnitOf(mIndex, LowerCase(VendorInclude), mUnit), 'Include-Datei führt auf die Unit');
  Assert.AreEqual('Vendor.Lib', mUnit.UnitName, 'Unit');
  Assert.IsTrue(HasSymbolFrom(mUnit, 'TVendorDecl', VendorInclude), 'mit dem Symbol aus der .inc');
  Assert.AreEqual(1, mIndex.LazyStats.Loads, 'genau ein Ladevorgang');
end;

procedure TIndexIncludeOwnersTests.EvictedOwnerIsReloaded;
var
  mIndex: ISymbolIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mUnit: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mUnit := IncludingUnit('Vendor.Lib', VendorFile, VendorInclude, 'TVendorDecl');
  mEntries := EntriesOf([mUnit]);
  mIndex.AddEvictable(mUnit, mEntries[0].Source);
  Assert.AreEqual(1, Integer(Length(mIndex.Units)), 'erst geladen');
  mIndex.TrimEvictable;
  Assert.AreEqual(1, mIndex.LazyStats.Evictions, 'verdrängt');
  Assert.AreEqual(0, Integer(Length(mIndex.Units)), 'nicht mehr geladen');
  Assert.IsTrue(TIndexFiles.UnitOf(mIndex, VendorInclude, mUnit), 'Zuordnung bleibt beim Verdrängen');
  Assert.IsTrue(HasSymbolFrom(mUnit, 'TVendorDecl', VendorInclude), 'nachgeladen mit dem Symbol aus der .inc');
  Assert.AreEqual(1, mIndex.LazyStats.Loads, 'ein Ladevorgang');
end;

procedure TIndexIncludeOwnersTests.LoadedOwnerNeedsNoLoad;
var
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  AddColdEntry(mIndex, EntriesOf([IncludingUnit('Vendor.Cold', 'C:\Lib\Vendor.Cold.pas', VendorInclude,
    'TColdDecl')])[0]);
  mIndex.AddUnit(IncludingUnit('Vendor.Lib', VendorFile, VendorInclude, 'TVendorDecl'));
  Assert.IsTrue(TIndexFiles.UnitOf(mIndex, VendorInclude, mUnit), 'gefunden');
  Assert.AreEqual('Vendor.Lib', mUnit.UnitName, 'die geladene');
  Assert.AreEqual(0, mIndex.LazyStats.Loads, 'nichts nachgeladen');
end;

procedure TIndexIncludeOwnersTests.SameNameUnitsKeepTheirFiles;
var
  mIndex: ISymbolIndex;
  mEntries: TArray<TIndexCacheEntry>;
  mUnit: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mEntries := EntriesOf([IncludingUnit('Vendor.Lib', VendorFile, VendorInclude, 'TVendorDecl'),
    IncludingUnit('Vendor.Lib', ExtraFile, ExtraInclude, 'TExtraDecl')]);
  AddColdEntry(mIndex, mEntries[0]);
  AddColdEntry(mIndex, mEntries[1]);
  Assert.AreEqual(2, Integer(Length(mIndex.UnitFiles('Vendor.Lib'))), 'zwei Dateien unter einem Namen');
  Assert.IsTrue(TIndexFiles.UnitOf(mIndex, ExtraInclude, mUnit), 'Include-Datei des Zusatzordners');
  Assert.AreEqual(ExtraFile, mUnit.FileName, 'führt auf ihre Datei, nicht auf die erste des Namens');
  Assert.IsTrue(HasSymbolFrom(mUnit, 'TExtraDecl', ExtraInclude), 'mit ihrem Symbol');
  Assert.IsTrue(TIndexFiles.UnitOf(mIndex, VendorInclude, mUnit), 'Include-Datei der Bibliothek');
  Assert.AreEqual(VendorFile, mUnit.FileName, 'führt auf die Bibliotheksdatei');
end;

procedure TIndexIncludeOwnersTests.RemovedOwnerIsForgotten;
var
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  AddColdEntry(mIndex, EntriesOf([IncludingUnit('Vendor.Lib', VendorFile, VendorInclude, 'TVendorDecl')])[0]);
  mIndex.RemoveFile(VendorFile);
  Assert.IsFalse(TIndexFiles.UnitOf(mIndex, VendorInclude, mUnit), 'entfernt');
  Assert.IsFalse(TIndexFiles.UnitOf(mIndex, 'C:\Lib\Unbekannt.inc', mUnit), 'unbekannte Datei');
  Assert.AreEqual(0, mIndex.LazyStats.Loads, 'nichts geladen');
end;

procedure TIndexIncludeOwnersTests.IdeIndexFindsColdOwner;
var
  mInner, mIde, mEditor: ISymbolIndex;
  mUnit: TUnitIndex;
begin
  mInner := TSymbolIndex.Create;
  mIde := TSymbolIndex.Create;
  AddColdEntry(mInner, EntriesOf([IncludingUnit('Vendor.Lib', VendorFile, VendorInclude, 'TVendorDecl')])[0]);
  mEditor := TIdeIndex.Create(mInner, mIde);
  Assert.IsTrue(TIndexFiles.UnitOf(mEditor, VendorInclude, mUnit), 'über den Index des Editors');
  Assert.AreEqual('Vendor.Lib', mUnit.UnitName, 'Unit');
  Assert.AreEqual(1, mInner.LazyStats.Loads, 'im gemeinsamen Index nachgeladen');
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexIncludeOwnersTests);

end.
