unit dpcc.Common.Memory.Phase2.Tests;

// Speicher-Optimierung Phase 2: Nach dem Ende des Servers bleibt nichts vom Index im Prozess (Namensindex der
// Import-Vorschläge zum Index für Hover und Vervollständigung, prozessweite Merker beim letzten Server). Länger nicht
// benutzte Dokumente verlieren ihre abgeleiteten Daten (a1), ein abgeleiteter Arbeitsbereich verschwindet mit dem
// letzten seiner Dokumente (a5). Weniger Speicher je Symbol bei gleichem Verhalten (c2–c4): Signaturen als UTF-8,
// Namenstabellen und Verweistabellen ohne großgeschriebene Kopien, geteilte Direktiven-Listen; Office- und
// WinRT-Units nur, wenn das Projekt sie nennt.

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract;

type
  [TestFixture]
  TDpccMemoryPhase2Tests = class
  public
    /// <summary>Einmal-Belegungen (Server-Thread, Sperrobjekte, Texttabellen) vor dem Leckmonitor.</summary>
    [SetupFixture]
    procedure WarmUp;
    /// <summary>Der Index für Hover und Vervollständigung (TIdeIndex) verwirft beim Freigeben seinen Namensindex
    /// der Import-Vorschläge; vorher hielt dieser alle Units eines beendeten Servers fest (≈ 190 MB nach Stopp).
    /// </summary>
    [Test]
    procedure EditorIndexReleasesImportSnapshot;
    /// <summary>Endet der letzte Server im Prozess, verwirft er den Namensindex, auch den eines fremden Index.
    /// </summary>
    [Test]
    procedure LastServerReleasesImportSnapshot;
    /// <summary>a1: Nur die zuletzt benutzten Dokumente behalten abgeleitete Daten; ältere behalten Text und
    /// Version, der Baum entsteht beim nächsten Zugriff neu.</summary>
    [Test]
    procedure OldDocumentsLoseDerivedData;
    /// <summary>a5: Eine Datei außerhalb der gemeldeten Projekte bekommt einen abgeleiteten Arbeitsbereich; mit
    /// ihrem didClose verschwindet er wieder.</summary>
    [Test]
    procedure DerivedWorkspaceGoesWithLastDocument;
    /// <summary>c4: Die Namenstabelle einer Unit findet alle Stellen eines Namens ohne Groß-/Kleinschreibung,
    /// aufsteigend, und keine für fremde Namen.</summary>
    [Test]
    procedure NameTableFindsAllSpellings;
    /// <summary>c4: Symbole nach Namen und Nachfahren nach Vorfahr ohne Groß-/Kleinschreibung, in der Reihenfolge des
    /// Eintragens; ersetzte Units zählen nicht mehr.</summary>
    [Test]
    procedure RefTablesIgnoreCaseAndReplacedUnits;
    /// <summary>c2: Signaturen (auch mit Umlauten) kommen unverändert durch den Cache, auch wenn derselbe Text an
    /// anderer Stelle als Name steht; gleiche Signaturen teilen sich den Text.</summary>
    [Test]
    procedure SignaturesSurviveCache;
    /// <summary>c3: Gleiche Direktiven-Listen teilen sich ein Array.</summary>
    [Test]
    procedure EqualDirectivesShareOneArray;
    /// <summary>c1/c4: Eine Unit unter den selten genutzten Ordnern kommt nur über die uses einer Unit außerhalb der
    /// Installation in den Index, nicht über die uses der Bibliothek.</summary>
    [Test]
    procedure RarelyUsedUnitsOnlyFromOwnUses;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.JSON,
  dpcc.Common.Index.Cache,
  dpcc.Common.Index.Builder,
  dpcc.Common.Memory.Phase1.Tests,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Documents.Providers.DocumentStore,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.NameIndex,
  dpcc.Common.Lsp.IdeIndex,
  Shell.Composition.CompletionServer,
  Shell.Composition.InProcess;

const
  cA5Unit = 'unit UFremd;'#13#10'interface'#13#10'implementation'#13#10'end.'#13#10;
  cA5Dpr = 'program Fremd;'#13#10'uses'#13#10'  UFremd in ''UFremd.pas'';'#13#10'begin'#13#10'end.'#13#10;
  cA5Dproj =
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '    <PropertyGroup>'#13#10 +
    '        <ProjectGuid>{0B6C1A52-3E7D-4F28-9A41-5C2D8E7F1A90}</ProjectGuid>'#13#10 +
    '        <MainSource>Fremd.dpr</MainSource>'#13#10 +
    '        <Base>True</Base>'#13#10 +
    '        <Config Condition="''$(Config)''==''''">Debug</Config>'#13#10 +
    '        <Platform Condition="''$(Platform)''==''''">Win32</Platform>'#13#10 +
    '        <TargetedPlatforms>1</TargetedPlatforms>'#13#10 +
    '        <AppType>Console</AppType>'#13#10 +
    '    </PropertyGroup>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <DelphiCompile Include="$(MainSource)">'#13#10 +
    '            <MainSource>MainSource</MainSource>'#13#10 +
    '        </DelphiCompile>'#13#10 +
    '        <DCCReference Include="UFremd.pas"/>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>'#13#10;
  cA5WaitMs = 15000;

/// <summary>Referenzzähler eines dynamischen Arrays (Kopf vor den Daten, wie System.TDynArrayRec).</summary>
function RefsAt(AData: Pointer): Integer;
begin
  if AData = nil then
  begin
    Exit(0);
  end;
  Result := PInteger(PByte(AData) - SizeOf(NativeInt) - SizeOf(Integer))^;
end;

function DynArrayRefs(const AArray: TArray<TIndexSymbol>): Integer;
begin
  Result := RefsAt(Pointer(AArray));
end;

function UnitArrayRefs(const AArray: TArray<TUnitIndex>): Integer;
begin
  Result := RefsAt(Pointer(AArray));
end;

/// <summary>Unit mit importierbaren Klassen (interface, oberste Ebene).</summary>
function UnitWith(const AUnitName, AFileName: string; const ANames: array of string): TUnitIndex;
var
  mIndex: Integer;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AUnitName;
  Result.FileName := AFileName;
  Result.Stamp := 1;
  SetLength(Result.Symbols, Length(ANames));
  for mIndex := 0 to High(ANames) do
  begin
    Result.Symbols[mIndex].Name := ANames[mIndex];
    Result.Symbols[mIndex].Kind := TIndexSymbolKind.ClassType;
    Result.Symbols[mIndex].InInterface := True;
  end;
end;

/// <summary>Symbole der ersten Unit; eigene Routine, damit kein Zwischenergebnis des Aufrufers das Array der Units
/// hält.</summary>
function FirstSymbols(const AIndex: ISymbolIndex): TArray<TIndexSymbol>;
begin
  Result := AIndex.Units[0].Symbols;
end;

/// <summary>Schnappschuss der Units; eigene Routine wie FirstSymbols.</summary>
function UnitsOf(const AIndex: ISymbolIndex): TArray<TUnitIndex>;
begin
  Result := AIndex.Units;
end;

/// <summary>Einträge des Namensindex zu AIndex; eigene Routine wie FirstSymbols.</summary>
function ImportCount(const AIndex: ISymbolIndex): Integer;
begin
  Result := TImportNames.Current(AIndex).Count;
end;

/// <summary>Schickt eine JSON-RPC-Nachricht mit Kopfzeile an den Server.</summary>
procedure SendMessage(AServer: TShellInProcessServer; AMessage: TJSONObject);
var
  mBody, mBytes: TBytes;
begin
  try
    mBody := TEncoding.UTF8.GetBytes(AMessage.ToJSON);
  finally
    AMessage.Free;
  end;
  mBytes := TEncoding.ASCII.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(mBody)])) + mBody;
  AServer.ClientOutput.WriteBuffer(mBytes[0], Length(mBytes));
end;

function Notification(const AMethod: string; AParams: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  Result.AddPair('method', AMethod);
  Result.AddPair('params', AParams);
end;

function TextDocument(const AUri: string): TJSONObject;
begin
  Result := TJSONObject.Create(TJSONPair.Create('textDocument', TJSONObject.Create(TJSONPair.Create('uri', AUri))));
end;

/// <summary>Arbeitsbereiche der Wurzel (unter ihrer Sperre).</summary>
function WorkspaceCount(ARoot: TShellCompletionServer): Integer;
begin
  System.TMonitor.Enter(ARoot.Parts.Core.Workspaces.Lock);
  try
    Result := ARoot.Parts.Core.Workspaces.Items.Count;
  finally
    System.TMonitor.Exit(ARoot.Parts.Core.Workspaces.Lock);
  end;
end;

function WaitForWorkspaces(ARoot: TShellCompletionServer; ACount: Integer): Boolean;
var
  mStarted: UInt64;
begin
  mStarted := TThread.GetTickCount64;
  while (WorkspaceCount(ARoot) <> ACount) and (TThread.GetTickCount64 - mStarted < cA5WaitMs) do
  begin
    TThread.Sleep(20);
  end;
  Result := WorkspaceCount(ARoot) = ACount;
end;

/// <summary>a5: Server ohne gemeldete Ordner, didOpen einer Datei mit Projekt im Ordner, didClose; liefert die Zahl
/// der Arbeitsbereiche nach didOpen und nach didClose.</summary>
procedure RunDerivedScenario(out AOpened, AClosed: Integer);
var
  mFolder, mUnitFile, mUri: string;
  mServer: TShellInProcessServer;
  mRoot: TShellCompletionServer;
  mInitialize, mDocument: TJSONObject;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'dpcc-a5-' + IntToStr(MainThreadID));
  ForceDirectories(mFolder);
  mUnitFile := TPath.Combine(mFolder, 'UFremd.pas');
  TFile.WriteAllText(mUnitFile, cA5Unit, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(mFolder, 'Fremd.dpr'), cA5Dpr, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(mFolder, 'Fremd.dproj'), cA5Dproj, TEncoding.UTF8);
  mUri := TDocumentUris.FromPath(mUnitFile);
  mRoot := nil;
  mServer := TShellInProcessServer.Create(nil,
    procedure(AServer: TShellCompletionServer)
    begin
      mRoot := AServer;
    end);
  try
    mInitialize := TJSONObject.Create;
    mInitialize.AddPair('jsonrpc', '2.0');
    mInitialize.AddPair('id', TJSONNumber.Create(1));
    mInitialize.AddPair('method', 'initialize');
    mInitialize.AddPair('params', TJSONObject.Create(TJSONPair.Create('capabilities', TJSONObject.Create)));
    SendMessage(mServer, mInitialize);
    // Ohne Ordner leitet der Server sie aus den geöffneten Dateien ab (#175).
    SendMessage(mServer, Notification('initialized', TJSONObject.Create));
    mDocument := TJSONObject.Create;
    mDocument.AddPair('uri', mUri);
    mDocument.AddPair('languageId', 'pascal');
    mDocument.AddPair('version', TJSONNumber.Create(1));
    mDocument.AddPair('text', cA5Unit);
    SendMessage(mServer, Notification('textDocument/didOpen', TJSONObject.Create(TJSONPair.Create('textDocument',
      mDocument))));
    WaitForWorkspaces(mRoot, 1);
    AOpened := WorkspaceCount(mRoot);
    SendMessage(mServer, Notification('textDocument/didClose', TextDocument(mUri)));
    WaitForWorkspaces(mRoot, 0);
    AClosed := WorkspaceCount(mRoot);
    Assert.IsTrue(mServer.Stop, 'Server sauber beendet');
  finally
    mServer.Free;
    try
      TDirectory.Delete(mFolder, True);
    except
      // Ein Rest im Temp-Ordner stört keinen Test.
      on Exception do
        ;
    end;
  end;
end;

procedure StartAndStopServer;
var
  mServer: TShellInProcessServer;
begin
  mServer := TShellInProcessServer.Create(nil);
  try
    Assert.IsTrue(mServer.Stop, 'Server sauber beendet');
  finally
    mServer.Free;
  end;
end;

{ TDpccMemoryPhase2Tests }

procedure TDpccMemoryPhase2Tests.WarmUp;
var
  mIndex: ISymbolIndex;
  mOpened, mClosed: Integer;
begin
  StartAndStopServer;
  try
    RunDerivedScenario(mOpened, mClosed);
  except
    // Scheitert der Lauf, meldet das der Test selbst.
    on Exception do
      ;
  end;
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UnitWith('UWarm', 'C:\P\UWarm.pas', ['TWarm']));
  ImportCount(mIndex);
  mIndex := nil;
end;

procedure TDpccMemoryPhase2Tests.EditorIndexReleasesImportSnapshot;
var
  mInner, mIde, mEditor: ISymbolIndex;
  mSymbols: TArray<TIndexSymbol>;
begin
  mInner := TSymbolIndex.Create;
  mIde := TSymbolIndex.Create;
  mEditor := TIdeIndex.Create(mInner, mIde);
  mInner.AddUnit(UnitWith('UA', 'C:\P\UA.pas', ['TFoo', 'TBar']));
  mSymbols := FirstSymbols(mInner);
  // Hover, Vervollständigung und Parameterhilfe fragen über den Index mit den Ersatz-Units der IDE.
  Assert.AreEqual(2, ImportCount(mEditor), 'Namensindex über den Editor-Index');
  Assert.IsTrue(DynArrayRefs(mSymbols) > 1, 'Index und Namensindex halten die Symbole');
  mEditor := nil;
  mIde := nil;
  mInner := nil;
  Assert.AreEqual(1, DynArrayRefs(mSymbols), 'nach dem Freigeben hält nur noch der Test die Symbole');
end;

procedure TDpccMemoryPhase2Tests.LastServerReleasesImportSnapshot;
var
  mIndex: ISymbolIndex;
  mUnits: TArray<TUnitIndex>;
  mBefore: Integer;
begin
  Assert.AreEqual(0, TShellInProcessServer.ActiveCount, 'kein Server läuft');
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UnitWith('UB', 'C:\P\UB.pas', ['TBaz']));
  // Der Namensindex hält den Schnappschuss der Units (dasselbe Array wie der Index).
  mUnits := UnitsOf(mIndex);
  Assert.AreEqual(1, ImportCount(mIndex), 'Namensindex angelegt');
  mBefore := UnitArrayRefs(mUnits);
  StartAndStopServer;
  Assert.AreEqual(0, TShellInProcessServer.ActiveCount, 'abgemeldet');
  Assert.AreEqual(mBefore - 1, UnitArrayRefs(mUnits), 'der letzte Server hat den Namensindex verworfen');
  mIndex := nil;
  Assert.AreEqual(1, UnitArrayRefs(mUnits), 'Index frei');
end;

function DocumentUri(AIndex: Integer): string;
begin
  Result := Format('file:///C:/P/U%d.pas', [AIndex]);
end;

procedure TDpccMemoryPhase2Tests.OldDocumentsLoseDerivedData;
var
  mStore: IDocumentStore;
  mCalls, mIndex, mCount: Integer;
  mFactory: TFunc<IInterface>;
  mDocument: ITextDocument;
begin
  mStore := TDocumentStore.Create;
  mCalls := 0;
  mFactory :=
    function: IInterface
    begin
      Inc(mCalls);
      Result := TInterfacedObject.Create;
    end;
  mCount := TDocumentStore.cKeepDerived + 4;
  for mIndex := 1 to mCount do
  begin
    mStore.Open(DocumentUri(mIndex), 'pascal', 1, Format('unit U%d;', [mIndex]));
    Assert.IsTrue(mStore.TryGet(DocumentUri(mIndex), mDocument), 'geöffnet');
    mDocument.Derived('test', mFactory);
  end;
  mDocument := nil;
  Assert.AreEqual(mCount, mCalls, 'je Dokument einmal erzeugt');
  Assert.IsTrue(mStore.TryGet(DocumentUri(mCount), mDocument), 'zuletzt geöffnetes');
  mDocument.Derived('test', mFactory);
  Assert.AreEqual(mCount, mCalls, 'das zuletzt benutzte behält seine Daten');
  Assert.IsTrue(mStore.TryGet(DocumentUri(1), mDocument), 'ältestes noch offen');
  Assert.AreEqual('unit U1;', mDocument.Text, 'Text bleibt');
  Assert.AreEqual(1, mDocument.Version, 'Version bleibt');
  mDocument.Derived('test', mFactory);
  Assert.AreEqual(mCount + 1, mCalls, 'das älteste baut seine Daten neu');
  mDocument := nil;
  Assert.AreEqual(mCount, Length(mStore.Documents), 'alle Dokumente bleiben offen');
end;

function SymbolsWith(const ANames: array of string): TArray<TIndexSymbol>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ANames));
  for mIndex := 0 to High(ANames) do
  begin
    Result[mIndex].Name := ANames[mIndex];
    Result[mIndex].Kind := TIndexSymbolKind.Method;
  end;
end;

function PositionsText(const APositions: TArray<Integer>): string;
var
  mPosition: Integer;
begin
  Result := '';
  for mPosition in APositions do
  begin
    Result := Result + IntToStr(mPosition) + ' ';
  end;
  Result := Result.Trim;
end;

procedure TDpccMemoryPhase2Tests.NameTableFindsAllSpellings;
var
  mUnit: TUnitIndex;
begin
  mUnit := Default(TUnitIndex);
  mUnit.Symbols := SymbolsWith(['Foo', 'bar', 'FOO', 'Baz', 'foo', 'Fo', 'Fooo']);
  mUnit.PrepareNames;
  Assert.AreEqual('0 2 4', PositionsText(mUnit.SymbolsNamed('fOo')), 'alle Schreibweisen, aufsteigend');
  Assert.AreEqual('1', PositionsText(mUnit.SymbolsNamed('BAR')), 'einzelner Treffer');
  Assert.AreEqual('5', PositionsText(mUnit.SymbolsNamed('fo')), 'kürzerer Name');
  Assert.AreEqual('', PositionsText(mUnit.SymbolsNamed('Qux')), 'fremder Name');
  Assert.AreEqual('', PositionsText(mUnit.SymbolsNamed('')), 'leerer Name');
end;

function LocationUnits(const ALocations: TArray<TSymbolLocation>): string;
var
  mLocation: TSymbolLocation;
begin
  Result := '';
  for mLocation in ALocations do
  begin
    Result := Result + mLocation.UnitName + '.' + mLocation.Symbol.Name + ' ';
  end;
  Result := Result.Trim;
end;

procedure TDpccMemoryPhase2Tests.RefTablesIgnoreCaseAndReplacedUnits;
var
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mUnit := UnitWith('UA', 'C:\P\UA.pas', ['TBase', 'Run']);
  mIndex.AddUnit(mUnit);
  mUnit := UnitWith('UB', 'C:\P\UB.pas', ['TKind', 'RUN']);
  mUnit.Symbols[0].Ancestors := ['UA.TBase<Integer>'];
  mIndex.AddUnit(mUnit);
  Assert.AreEqual('UA.Run UB.RUN', LocationUnits(mIndex.FindSymbols('run')), 'beide Schreibweisen in Reihenfolge');
  Assert.IsTrue(mIndex.HasSymbol('rUn',
    function(const ASymbol: TIndexSymbol): Boolean
    begin
      Result := ASymbol.Name = 'RUN';
    end), 'HasSymbol ohne Groß-/Kleinschreibung');
  Assert.AreEqual('UB.TKind', LocationUnits(mIndex.Descendants('tbase')), 'Nachfahr über den Vorfahren');
  // UB ersetzt: der alte Stand zählt nicht mehr.
  mUnit := UnitWith('UB', 'C:\P\UB.pas', ['TOther']);
  mIndex.AddUnit(mUnit);
  Assert.AreEqual('UA.Run', LocationUnits(mIndex.FindSymbols('RUN')), 'ersetzte Unit');
  Assert.AreEqual('', LocationUnits(mIndex.Descendants('TBase')), 'ersetzter Nachfahr');
end;

procedure TDpccMemoryPhase2Tests.SignaturesSurviveCache;
var
  mUnit, mBack: TUnitIndex;
  mEntries: TArray<TIndexCacheEntry>;
begin
  mUnit := UnitWith('UC', 'C:\P\UC.pas', ['Größe', 'procedure Run;', 'Zwei']);
  mUnit.Symbols[0].Signature := 'function Größe(const AText: string): Integer;';
  // Text, der zugleich Name eines Symbols ist.
  mUnit.Symbols[1].Signature := 'procedure Run;';
  mUnit.Symbols[2].Signature := 'function Größe(const AText: string): Integer;';
  mEntries := TIndexCache.ReadEntries(TIndexCache.Serialize([mUnit]));
  Assert.AreEqual(1, Length(mEntries), 'ein Eintrag');
  Assert.IsTrue(TIndexCache.Expand(mEntries[0], mBack), 'Symbole gelesen');
  Assert.AreEqual('function Größe(const AText: string): Integer;', mBack.Symbols[0].Signature, 'Umlaute');
  Assert.AreEqual('procedure Run;', mBack.Symbols[1].Name, 'Text als Name');
  Assert.AreEqual('procedure Run;', mBack.Symbols[1].Signature, 'derselbe Text als Signatur');
  Assert.AreEqual('Größe', mBack.Symbols[0].Name, 'Name mit Umlaut');
  Assert.IsTrue(Pointer(mBack.Symbols[0].SignatureUtf8) = Pointer(mBack.Symbols[2].SignatureUtf8),
    'gleiche Signaturen teilen sich den Text');
end;

procedure TDpccMemoryPhase2Tests.EqualDirectivesShareOneArray;
var
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
  mStored: TArray<TIndexSymbol>;
begin
  mIndex := TSymbolIndex.Create;
  mUnit := UnitWith('UD', 'C:\P\UD.pas', ['A', 'B', 'C']);
  mUnit.Symbols[0].Directives := ['override'];
  mUnit.Symbols[1].Directives := ['override'];
  mUnit.Symbols[2].Directives := ['virtual'];
  mIndex.AddUnit(mUnit);
  mStored := FirstSymbols(mIndex);
  Assert.IsTrue(Pointer(mStored[0].Directives) = Pointer(mStored[1].Directives), 'gleiche Liste geteilt');
  Assert.IsFalse(Pointer(mStored[0].Directives) = Pointer(mStored[2].Directives), 'andere Liste getrennt');
  Assert.IsFalse(Pointer(mStored[0].Directives) = Pointer(mUnit.Symbols[0].Directives),
    'das Array des Aufrufers bleibt seines');
  Assert.AreEqual('override', mStored[1].Directives[0], 'Inhalt');
end;

function ResolveRarely(const AUnitName: string): string;
begin
  if SameText(AUnitName, 'W') then
  begin
    Result := 'C:\Lib\OCX\Servers\W.pas';
  end
  else
  begin
    Result := 'C:\Lib\' + AUnitName + '.pas';
  end;
end;

/// <summary>Projektstufe für AProgram mit Bibliothek C:\Lib (A nennt W aus OCX\Servers); liefert, ob A und W danach im
/// Index stehen.</summary>
procedure RunRarelyScenario(const AProgram: string; ARarely: Boolean; out AHasA, AHasW: Boolean);
var
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mBuilder: TIndexBuilder;
  mFound: TUnitIndex;
begin
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mFiles.Put('C:\P\P.dpr', AProgram, 1);
  mFiles.Put('C:\Lib\A.pas', 'unit A;'#10'interface'#10'uses W;'#10'implementation'#10'end.', 1);
  mFiles.Put('C:\Lib\OCX\Servers\W.pas', 'unit W;'#10'interface'#10'type TW = class end;'#10'implementation'#10'end.',
    1);
  mIndex := TSymbolIndex.Create;
  mBuilder := TIndexBuilder.Create(mIndex, mFileSystem, ['MSWINDOWS'], ResolveRarely);
  try
    mBuilder.LibraryRoots := ['C:\Lib'];
    if ARarely then
    begin
      mBuilder.RarelyUsedRoots := ['C:\Lib\OCX\Servers\'];
    end;
    mBuilder.Build(['C:\P\P.dpr'], nil, nil);
  finally
    mBuilder.Free;
  end;
  AHasA := mIndex.FindUnit('A', mFound);
  AHasW := mIndex.FindUnit('W', mFound);
end;

procedure TDpccMemoryPhase2Tests.RarelyUsedUnitsOnlyFromOwnUses;
var
  mHasA, mHasW: Boolean;
begin
  RunRarelyScenario('program P;'#10'uses A;'#10'begin end.', True, mHasA, mHasW);
  Assert.IsTrue(mHasA, 'Bibliotheks-Unit über die uses des Projekts');
  Assert.IsFalse(mHasW, 'nicht über die uses der Bibliothek');
  RunRarelyScenario('program P;'#10'uses W;'#10'begin end.', True, mHasA, mHasW);
  Assert.IsTrue(mHasW, 'nennt das Projekt sie selbst, kommt sie in den Index');
  RunRarelyScenario('program P;'#10'uses A;'#10'begin end.', False, mHasA, mHasW);
  Assert.IsTrue(mHasW, 'ohne Ausnahme (index.officeAndWinRt) wie bisher');
end;

procedure TDpccMemoryPhase2Tests.DerivedWorkspaceGoesWithLastDocument;
var
  mOpened, mClosed: Integer;
begin
  RunDerivedScenario(mOpened, mClosed);
  Assert.AreEqual(1, mOpened, 'abgeleiteter Arbeitsbereich nach didOpen');
  Assert.AreEqual(0, mClosed, 'nach didClose wieder entfernt');
  Assert.AreEqual(0, TShellInProcessServer.ActiveCount, 'abgemeldet');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccMemoryPhase2Tests);

end.
