unit Shell.Composition.Prewarm.Tests;

// Vorladen beim Öffnen und Aktivieren (dpcc/prewarm, Shell.Composition.Prewarm): Der Auftrag lädt die Units der uses
// (kalt aus dem Katalog, sonst über EnsureUnit) und berührt geladene nur; über dem Deckel lässt er kalte Units liegen;
// ein Abbruch wirkt vor der nächsten Unit; danach braucht eine definition-Anfrage weder Parse noch Nachladen. Der
// Dienst tut während des Indexaufbaus nichts (danach einmal) und bricht einen laufenden Auftrag ab, wenn eine andere
// Datei gemeldet wird.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  DUnitX.TestFramework,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Index.Contract,
  Shell.Composition.Prewarm;

type
  [TestFixture]
  TShellPrewarmTests = class
  private
    FIndex: ISymbolIndex;
    FStore: IDocumentStore;
    /// <summary>Quelltexte, die FakeEnsure kennt (Unit-Name groß).</summary>
    FSources: TDictionary<string, string>;
    /// <summary>Unter FLock: Aufrufe von FakeEnsure und Zeilen des Diagnoselogs (auch aus dem Thread des Dienstes).
    /// </summary>
    FLock: TObject;
    FEnsured: TList<string>;
    FLines: TList<string>;
    FBuilding: Boolean;
    /// <summary>Wird beim ersten FakeEnsure ausgelöst (Abbruch mitten im Auftrag).</summary>
    FCancelOnEnsure: IShellPrewarmCancel;
    /// <summary>FakeEnsure für diese Unit hält einmal an: FEntered setzen, auf FRelease warten.</summary>
    FBlockName: string;
    FEntered: TEvent;
    FRelease: TEvent;
    /// <summary>EnsureUnit wie die Ordner: liest eine bekannte Unit in den Index ein.</summary>
    function FakeEnsure(const AUnitName: string): Boolean;
    function EnsureCount: Integer;
    function Lines: TArray<string>;
    /// <summary>Bibliotheks-Unit nur mit Kopf, Katalog und Block (wie aus dem Cache beim Start).</summary>
    procedure AddCold(const AText, AFileName: string);
    function OpenDocument(const AFileName, AText: string): ITextDocument;
    function InputFor(const ADocument: ITextDocument): TShellPrewarmInput;
    function Services: TShellPrewarmServices;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Kalte Units aus dem Katalog, fehlende über EnsureUnit, unbekannte gezählt; beim zweiten Mal nur
    /// berührt, kein Laden mehr, nichts gepinnt.</summary>
    [Test]
    procedure LoadsUsesFromCatalogAndSearchPaths;
    /// <summary>Verdrängbare Units am Deckel: kalte Units bleiben kalt.</summary>
    [Test]
    procedure KeepsColdUnitsAboveLimit;
    /// <summary>Abbruch während einer Unit: die nächste wird nicht mehr geladen.</summary>
    [Test]
    procedure CancelStopsBeforeNextUnit;
    /// <summary>Nach dem Vorladen: definition nutzt den Baum aus dem Zwischenspeicher und lädt nichts nach.</summary>
    [Test]
    procedure DefinitionAfterPrewarmNeedsNoLoading;
    /// <summary>Während des Indexaufbaus nichts, nach dem Aufbau einmal.</summary>
    [Test]
    procedure NothingWhileIndexBuilds;
    /// <summary>Eine andere Datei bricht den laufenden Auftrag ab und läuft danach.</summary>
    [Test]
    procedure NewFileCancelsRunningJob;
  end;

implementation

uses
  dpcc.Common.Documents.Uris,
  dpcc.Common.Documents.Providers.DocumentStore,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.Extractor,
  dpcc.Common.Index.Cache,
  dpcc.Common.Pascal.TreeCache,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Lsp.Definition;

const
  cWaitMs = 5000;

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Alpha, Beta;'#10 +
    'implementation'#10 +
    'uses Gamma, Fehlt;'#10 +
    'end.';

  UnitAlpha =
    'unit Alpha;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TAlpha = class(TObject)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  UnitBeta =
    'unit Beta;'#10 +
    'interface'#10 +
    'procedure Zeige;'#10 +
    'implementation'#10 +
    'procedure Zeige;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'procedure Rechne;'#10 +
    'implementation'#10 +
    'procedure Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitNutzer =
    'unit Nutzer;'#10 +          // 0
    'interface'#10 +             // 1
    'uses Werkzeug;'#10 +        // 2
    'implementation'#10 +        // 3
    'procedure Lauf;'#10 +       // 4
    'begin'#10 +                 // 5
    '  Rechne;'#10 +             // 6
    'end;'#10 +                  // 7
    'end.';

{ TShellPrewarmTests }

procedure TShellPrewarmTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FStore := TDocumentStore.Create;
  FSources := TDictionary<string, string>.Create;
  // Je ein Symbol: Eine geladene Unit erkennt das Vorladen an ihren Symbolen (ein kalter Kopf hat keine).
  FSources.Add('GAMMA', 'unit Gamma;'#10'interface'#10'const'#10'  cGamma = 1;'#10'implementation'#10'end.');
  FSources.Add('DELTA', 'unit Delta;'#10'interface'#10'const'#10'  cDelta = 2;'#10'implementation'#10'end.');
  FSources.Add('SYSTEM', 'unit System;'#10'interface'#10'type'#10'  TObject = class'#10'  end;'#10 +
    'implementation'#10'end.');
  FLock := TObject.Create;
  FEnsured := TList<string>.Create;
  FLines := TList<string>.Create;
  FEntered := TEvent.Create(nil, True, False, '');
  FRelease := TEvent.Create(nil, True, False, '');
  FBuilding := False;
  FBlockName := '';
  FCancelOnEnsure := nil;
end;

procedure TShellPrewarmTests.TearDown;
begin
  FCancelOnEnsure := nil;
  FreeAndNil(FRelease);
  FreeAndNil(FEntered);
  FreeAndNil(FLines);
  FreeAndNil(FEnsured);
  FreeAndNil(FLock);
  FreeAndNil(FSources);
  FStore := nil;
  FIndex := nil;
end;

function TShellPrewarmTests.FakeEnsure(const AUnitName: string): Boolean;
var
  mBlock: Boolean;
  mText: string;
begin
  System.TMonitor.Enter(FLock);
  try
    FEnsured.Add(AUnitName);
    mBlock := (FBlockName <> '') and SameText(FBlockName, AUnitName);
    if mBlock then
    begin
      FBlockName := '';
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  if mBlock then
  begin
    FEntered.SetEvent;
    FRelease.WaitFor(cWaitMs);
  end;
  if FCancelOnEnsure <> nil then
  begin
    FCancelOnEnsure.Cancel;
  end;
  Result := FSources.TryGetValue(UpperCase(AUnitName), mText);
  if Result then
  begin
    FIndex.AddUnit(TIndexExtractor.ExtractText(mText, 'C:\Lib\' + AUnitName + '.pas', nil));
  end;
end;

function TShellPrewarmTests.EnsureCount: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FEnsured.Count;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellPrewarmTests.Lines: TArray<string>;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FLines.ToArray;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TShellPrewarmTests.AddCold(const AText, AFileName: string);
var
  mUnit: TUnitIndex;
  mUnits: TArray<TUnitIndex>;
  mEntries: TArray<TIndexCacheEntry>;
  mEntry: TIndexCacheEntry;
begin
  mUnit := TIndexExtractor.ExtractText(AText, AFileName, nil);
  mUnit.Library_ := True;
  mUnit.Stamp := 7;
  mUnit.Hash := 'H' + AFileName;
  mUnits := [mUnit];
  mEntries := TIndexCache.ReadEntries(TIndexCache.Serialize(mUnits));
  Assert.AreEqual(1, Integer(Length(mEntries)), 'Cache gelesen');
  for mEntry in mEntries do
  begin
    FIndex.AddCold(mEntry.Header, mEntry.Catalog, mEntry.Source, mEntry.SymbolCount, mEntry.UnavailableCount,
      mEntry.UsageCount);
  end;
end;

function TShellPrewarmTests.OpenDocument(const AFileName, AText: string): ITextDocument;
begin
  Result := FStore.Open(TDocumentUris.FromPath(AFileName), 'delphi', 1, AText);
end;

function TShellPrewarmTests.InputFor(const ADocument: ITextDocument): TShellPrewarmInput;
begin
  Result := Default(TShellPrewarmInput);
  Result.Document := ADocument;
  Result.Index := FIndex;
  Result.EnsureUnit := FakeEnsure;
  Result.EvictableLimit := TSymbolIndex.cEvictableBudget;
end;

function TShellPrewarmTests.Services: TShellPrewarmServices;
begin
  Result := Default(TShellPrewarmServices);
  Result.Documents := FStore;
  // Closures statt Methoden ohne Parameter: Die würden sonst sofort aufgerufen.
  Result.Index :=
    function: ISymbolIndex
    begin
      Result := FIndex;
    end;
  Result.EnsureUnit := FakeEnsure;
  Result.IndexBuilding :=
    function: Boolean
    begin
      Result := FBuilding;
    end;
  Result.Log :=
    procedure(AText: string)
    begin
      System.TMonitor.Enter(FLock);
      try
        FLines.Add(AText);
      finally
        System.TMonitor.Exit(FLock);
      end;
    end;
  Result.DocumentLabel :=
    function(AFileName: string): string
    begin
      Result := ExtractFileName(AFileName);
    end;
end;

procedure TShellPrewarmTests.LoadsUsesFromCatalogAndSearchPaths;
var
  mDocument: ITextDocument;
  mStats: TShellPrewarmStats;
  mLazy: TIndexLazyStats;
begin
  AddCold(UnitAlpha, 'C:\Lib\Alpha.pas');
  AddCold(UnitBeta, 'C:\Lib\Beta.pas');
  mDocument := OpenDocument('C:\P\Haupt.pas', UnitHaupt);
  mStats := TShellPrewarmJob.Run(InputFor(mDocument), nil);
  Assert.AreEqual(5, mStats.Units, 'Alpha, Beta, Gamma, Fehlt, System');
  Assert.AreEqual(2, mStats.Catalog, 'Alpha und Beta aus dem Katalog');
  Assert.AreEqual(2, mStats.Parsed, 'Gamma und System über EnsureUnit');
  Assert.AreEqual(1, mStats.Missing, 'Fehlt');
  Assert.AreEqual(0, mStats.Warm);
  Assert.AreEqual(0, mStats.Skipped);
  Assert.IsFalse(mStats.Cancelled);
  mLazy := FIndex.LazyStats;
  Assert.AreEqual(2, mLazy.Loads, 'zwei Units nachgeladen');
  Assert.AreEqual(2, mLazy.Evictable, 'nur berührt: die geladenen bleiben verdrängbar, nichts gepinnt');
  Assert.IsTrue(Pos('prewarm doc#1 units 5 warm 0 catalog 2 parsed 2 missing 1 skipped 0 ms ',
    mStats.Text('doc#1')) = 1, mStats.Text('doc#1'));
  // Zweiter Auftrag: alles schon geladen, nur berührt.
  mStats := TShellPrewarmJob.Run(InputFor(mDocument), nil);
  Assert.AreEqual(4, mStats.Warm, 'Alpha, Beta, Gamma, System');
  Assert.AreEqual(0, mStats.Catalog);
  Assert.AreEqual(0, mStats.Parsed);
  Assert.AreEqual(1, mStats.Missing);
  Assert.AreEqual(2, FIndex.LazyStats.Loads, 'kein weiteres Laden');
end;

procedure TShellPrewarmTests.KeepsColdUnitsAboveLimit;
var
  mDocument: ITextDocument;
  mInput: TShellPrewarmInput;
  mStats: TShellPrewarmStats;
begin
  AddCold(UnitAlpha, 'C:\Lib\Alpha.pas');
  AddCold(UnitBeta, 'C:\Lib\Beta.pas');
  mDocument := OpenDocument('C:\P\Haupt.pas', UnitHaupt);
  mInput := InputFor(mDocument);
  // Die verdrängbaren Units liegen schon am Deckel (hier 0 Byte): kalte Units bleiben kalt.
  mInput.EvictableLimit := 0;
  mStats := TShellPrewarmJob.Run(mInput, nil);
  Assert.AreEqual(2, mStats.Skipped, 'Alpha und Beta übersprungen');
  Assert.AreEqual(0, mStats.Catalog);
  Assert.AreEqual(0, FIndex.LazyStats.Loads, 'nichts nachgeladen, nichts verdrängt');
end;

procedure TShellPrewarmTests.CancelStopsBeforeNextUnit;
var
  mDocument: ITextDocument;
  mStats: TShellPrewarmStats;
begin
  mDocument := OpenDocument('C:\P\Zwei.pas',
    'unit Zwei;'#10'interface'#10'uses Gamma, Delta;'#10'implementation'#10'end.');
  FCancelOnEnsure := TShellPrewarmCancel.Create;
  mStats := TShellPrewarmJob.Run(InputFor(mDocument), FCancelOnEnsure);
  Assert.IsTrue(mStats.Cancelled);
  Assert.AreEqual(1, EnsureCount, 'nur Gamma');
  Assert.AreEqual(1, mStats.Parsed);
  Assert.IsTrue(Pos('cancelled yes', mStats.Text('doc#1')) > 0);
end;

procedure TShellPrewarmTests.DefinitionAfterPrewarmNeedsNoLoading;
var
  mDocument: ITextDocument;
  mStats: TShellPrewarmStats;
  mLoads, mEnsured, mParses: Integer;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mTargets: TArray<TDefinitionTarget>;
begin
  AddCold(UnitWerkzeug, 'C:\Lib\Werkzeug.pas');
  mDocument := OpenDocument('C:\P\Nutzer.pas', UnitNutzer);
  mStats := TShellPrewarmJob.Run(InputFor(mDocument), nil);
  Assert.AreEqual(1, mStats.Catalog, 'Werkzeug');
  Assert.AreEqual(1, mStats.Parsed, 'System');
  mLoads := FIndex.LazyStats.Loads;
  mEnsured := EnsureCount;
  mParses := TSyntaxTreeCache.ParseCount;
  // Wie TLspDefinition.Handle: Baum aus dem Zwischenspeicher, eigener Resolver mit EnsureUnit.
  mShared := TSyntaxTreeCache.Get(mDocument);
  Assert.AreEqual(mParses, TSyntaxTreeCache.ParseCount, 'Baum aus dem Zwischenspeicher');
  mResolver := TNameResolver.Create(FIndex, FakeEnsure);
  try
    mTargets := TLspDefinition.Targets(mResolver, FIndex, mShared.Tree, TDocumentUris.ToPath(mDocument.Uri),
      TTextPosition.Create(6, 3), False);
  finally
    mResolver.Free;
  end;
  Assert.IsTrue(Length(mTargets) > 0, 'Ziel gefunden');
  Assert.IsTrue(SameText('C:\Lib\Werkzeug.pas', mTargets[0].FileName), mTargets[0].FileName);
  Assert.AreEqual(mLoads, FIndex.LazyStats.Loads, 'nichts aus dem Katalog nachgeladen');
  Assert.AreEqual(mEnsured, EnsureCount, 'kein EnsureUnit');
end;

procedure TShellPrewarmTests.NothingWhileIndexBuilds;
var
  mDocument: ITextDocument;
  mPrewarm: TShellPrewarm;
  mLines: TArray<string>;
begin
  mDocument := OpenDocument('C:\P\A.pas', 'unit A;'#10'interface'#10'uses Gamma;'#10'implementation'#10'end.');
  FBuilding := True;
  mPrewarm := TShellPrewarm.Create(Services);
  try
    mPrewarm.Request(mDocument.Uri);
    Assert.IsTrue(mPrewarm.WaitIdle(cWaitMs));
    Assert.AreEqual(0, Integer(Length(Lines)), 'während des Aufbaus kein Auftrag');
    Assert.AreEqual(0, EnsureCount);
    FBuilding := False;
    mPrewarm.IndexFinished;
    Assert.IsTrue(mPrewarm.WaitIdle(cWaitMs));
    mLines := Lines;
    Assert.AreEqual(1, Integer(Length(mLines)), 'nach dem Aufbau einmal');
    Assert.IsTrue(mLines[0].StartsWith('prewarm A.pas units 2 '), mLines[0]);
    Assert.IsTrue(Pos('cancelled no', mLines[0]) > 0, mLines[0]);
    // Ein zweites IndexFinished holt nichts mehr nach.
    mPrewarm.IndexFinished;
    Assert.IsTrue(mPrewarm.WaitIdle(cWaitMs));
    Assert.AreEqual(1, Integer(Length(Lines)));
  finally
    mPrewarm.Free;
  end;
end;

procedure TShellPrewarmTests.NewFileCancelsRunningJob;
var
  mA, mB: ITextDocument;
  mPrewarm: TShellPrewarm;
  mLines: TArray<string>;
begin
  mA := OpenDocument('C:\P\A.pas', 'unit A;'#10'interface'#10'uses Gamma;'#10'implementation'#10'end.');
  mB := OpenDocument('C:\P\B.pas', 'unit B;'#10'interface'#10'uses Delta;'#10'implementation'#10'end.');
  FBlockName := 'Gamma';
  mPrewarm := TShellPrewarm.Create(Services);
  try
    mPrewarm.Request(mA.Uri);
    Assert.IsTrue(FEntered.WaitFor(cWaitMs) = wrSignaled, 'A lädt Gamma');
    // B kommt, während A in EnsureUnit steckt: A bricht vor der nächsten Unit (System) ab, danach läuft B.
    mPrewarm.Request(mB.Uri);
    FRelease.SetEvent;
    Assert.IsTrue(mPrewarm.WaitIdle(cWaitMs));
    mLines := Lines;
    Assert.AreEqual(2, Integer(Length(mLines)));
    Assert.IsTrue(mLines[0].StartsWith('prewarm A.pas '), mLines[0]);
    Assert.IsTrue(Pos('parsed 1 ', mLines[0]) > 0, mLines[0]);
    Assert.IsTrue(Pos('cancelled yes', mLines[0]) > 0, mLines[0]);
    Assert.IsTrue(mLines[1].StartsWith('prewarm B.pas '), mLines[1]);
    Assert.IsTrue(Pos('parsed 2 ', mLines[1]) > 0, 'Delta und System: ' + mLines[1]);
    Assert.IsTrue(Pos('cancelled no', mLines[1]) > 0, mLines[1]);
  finally
    FRelease.SetEvent;
    mPrewarm.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellPrewarmTests);

end.
