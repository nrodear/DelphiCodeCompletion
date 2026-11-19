unit dpcc.Common.Sources.Tests;

// Auftrag L2 (Quellen und Aktualität): welche Dateien in den Index kommen. Zusätzliche Quellordner samt Unterordnern
// (index.extraSourceFolders), Office-Typbibliotheken und WinRT immer im Katalog und nur bei Bedarf geladen,
// gleichnamige Units, neue und geänderte Dateien, Fehler je Datei, uses mit in-Pfad, Makros und Browsing Path,
// Typen der Installation ohne Quelltext.

interface

uses
  System.SysUtils,
  System.JSON,
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract;

type
  [TestFixture]
  TDpccSourcesTests = class
  public
    /// <summary>Einmal-Belegungen (Texttabellen, Sperrobjekte) vor dem Leckmonitor.</summary>
    [SetupFixture]
    procedure WarmUp;
    /// <summary>Zusatzordner: $(Name) aus den Variablen, sonst aus der Umgebung, %Name% aus der Umgebung; ein offener
    /// Verweis verwirft den Ordner.</summary>
    [Test]
    procedure ExtraFolderMacrosResolve;
    /// <summary>Zusatzordner samt Unterordnern: Tiefe zuerst, alphabetisch, ohne .git, __history und __recovery, mit
    /// Obergrenze.</summary>
    [Test]
    procedure FolderTreeSkipsHistoryAndStopsAtLimit;
    /// <summary>Ein Zusatzordner-Cache hängt an Plattform, Version und Ordnern, nicht an ihrer Reihenfolge.</summary>
    [Test]
    procedure ExtraSignatureIgnoresOrder;
    /// <summary>Eine Office-Unit, die schon kalt im Index steht, kommt über die uses einer Bibliotheks-Unit nicht in
    /// die gepinnte Hülle; ohne OnDemandRoots schon (Gegenprobe zum Stand vor L2).</summary>
    [Test]
    procedure OnDemandUnitStaysUnpinnedViaLibraryUses;
    /// <summary>Zusatzordner lesen mit den Symbolen der Bibliothek, nicht mit denen des Projekts.</summary>
    [Test]
    procedure ExtraFoldersUseLibraryDefines;
    /// <summary>Punkt 3: Gleichnamige Units bleiben beide im Index; die Projekt-Unit geht der Bibliothek vor (gepatchte
    /// Kopie gewinnt), zwei Projekt-Units in der Reihenfolge der Aufnahme; das Entfernen der einen lässt die andere
    /// unter dem Namen (vorher verlor der Name den Eintrag).</summary>
    [Test]
    procedure SameNamedUnitsKeepAllFiles;
    /// <summary>Punkt 3: Zwei Projekte mit gleichnamiger Unit: Die Namensauflösung nimmt die Datei, die das Projekt
    /// der Ausgangsdatei wählt (IIndexUnitScopes); ohne Projektbezug die erste.</summary>
    [Test]
    procedure ResolverTakesUnitOfOwnProject;
    /// <summary>Punkt 3: Der Rang der Projektbezüge legt die Zusatzordner hinter die Bibliothek.</summary>
    [Test]
    procedure RankPutsExtraFoldersLast;
    /// <summary>Punkt 7: Eine Datei, deren Lesen eine Ausnahme auslöst, fehlt im Index; der Aufbau läuft weiter und
    /// meldet sie.</summary>
    [Test]
    procedure UnreadableFileDoesNotStopBuild;
    /// <summary>Punkt 5: Gleicher Zeitstempel, andere Größe: anderer Stand.</summary>
    [Test]
    procedure SizeChangesSourceStamp;
    /// <summary>Punkt 5: Beim Nachladen einer kalten Unit mit geänderter Datei liest der Builder sie neu.</summary>
    [Test]
    procedure StaleColdUnitIsReadAgain;
    /// <summary>Punkt 4: Eine neue Datei kommt über AddFile in den Index (Suchpfad: gepinnt).</summary>
    [Test]
    procedure CreatedFileJoinsIndex;
    /// <summary>Punkt 9: uses X in 'pfad' der .dpr ohne DCCReference gehört zum Projekt; die uses einer Unit sucht
    /// der Builder ab ihrem Ordner.</summary>
    [Test]
    procedure InPathsAndFromDirectory;
    /// <summary>Punkt 5: Ordner außerhalb der beobachteten Wurzeln: erster Blick nur merken, dann neue, geänderte
    /// und gelöschte Dateien gegen den Index.</summary>
    [Test]
    procedure FolderStampsReportChanges;
    /// <summary>Punkte 5, 6, 8: Browsing Path und Registry-Schlüssel gehören zum Kontext; nicht auflösbare Pfade
    /// nennt ApplyTo; alle Umgebungsvariablen des Prozesses.</summary>
    [Test]
    procedure ContextCarriesBrowsingPathAndProfile;
    /// <summary>Punkt 1a: Typen aus Packages der Installation nur für Units ohne Quelltext.</summary>
    [Test]
    procedure InstalledTypesOnlyWithoutSource;
    /// <summary>Doppelte Einträge: Palette und RTTI melden dieselben Typen. Unique lässt je Unit.Typ den ersten
    /// (samt Vorfahr); UnitsOf des Katalogs im Server nennt jede Unit einmal.</summary>
    [Test]
    procedure IdeTypesAndUnitsAreUnique;
    /// <summary>Punkt 8: Win64x ohne eigenen Browsing Path nimmt den von Win64 (liest nur die Registry; ohne Delphi 13
    /// nichts zu prüfen).</summary>
    [Test]
    procedure Win64xBorrowsBrowsingPath;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  dpcc.Common.Rules.Contract,
  dpcc.Common.Lsp.IdeTypes,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Projects.DprojReader,
  dpcc.Common.Lsp.IdeProject,
  dpcc.Core.Lsp.IdeTypes,
  dpcc.Windows.Projects.DelphiInstallation,
  Shell.Workspace.Listings,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Semantics.NameResolver.Symbols,
  dpcc.Common.Index.Builder,
  dpcc.Common.Index.ProjectFiles,
  dpcc.Common.Projects.Contract,
  dpcc.Common.Memory.Phase1.Tests;

/// <summary>Unit-Suche des Szenarios: W liegt unter OCX\Servers, alles andere unter C:\Lib.</summary>
function ResolveScenarioUnit(const AUnitName: string): string;
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

/// <summary>Bibliotheksstufe mit W (verdrängbar, nicht gepinnt), dann Projektstufe für P (uses A; A nennt W).
/// Liefert, ob W danach gepinnt ist.</summary>
function RunOnDemandScenario(AOnDemand: Boolean): Boolean;
var
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mBuilder: TIndexBuilder;
  mStored: TIndexStoredUnit;
begin
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mFiles.Put('C:\P\P.dpr', 'program P;'#10'uses A;'#10'begin end.', 1);
  mFiles.Put('C:\Lib\A.pas', 'unit A;'#10'interface'#10'uses W;'#10'implementation'#10'end.', 1);
  mFiles.Put('C:\Lib\OCX\Servers\W.pas', 'unit W;'#10'interface'#10'type TW = class end;'#10'implementation'#10'end.',
    1);
  mIndex := TSymbolIndex.Create;
  // Erster Aufbau: nur die Bibliothek, W kommt verdrängbar in den Index (wie aus dem Katalog nach einem Neustart).
  mBuilder := TIndexBuilder.Create(mIndex, mFileSystem, ['MSWINDOWS'], ResolveScenarioUnit);
  try
    mBuilder.LibraryRoots := ['C:\Lib'];
    mBuilder.LazyLibrary := True;
    mBuilder.Build(nil, nil, ['C:\Lib\OCX\Servers\W.pas'], nil, nil, nil);
  finally
    mBuilder.Free;
  end;
  mBuilder := TIndexBuilder.Create(mIndex, mFileSystem, ['MSWINDOWS'], ResolveScenarioUnit);
  try
    mBuilder.LibraryRoots := ['C:\Lib'];
    if AOnDemand then
    begin
      mBuilder.OnDemandRoots := ['C:\Lib\OCX\Servers\'];
    end;
    mBuilder.Build(['C:\P\P.dpr'], nil, nil);
  finally
    mBuilder.Free;
  end;
  Result := False;
  for mStored in mIndex.StoredUnits do
  begin
    if SameText(mStored.Unit_.UnitName, 'W') then
    begin
      Result := mStored.Pinned;
    end;
  end;
end;

/// <summary>Hat AUnit ein Symbol AName (oberste Ebene)?</summary>
function HasSymbol(const AUnit: TUnitIndex; const AName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  /// <summary>Dateisystem für Punkt 7: wie TCountingIndexFileSystem, aber das Lesen von AFailing wirft.</summary>
  TFailingFileSystem = class(TInterfacedObject, IIndexFileSystem)
  private
    FInner: IIndexFileSystem;
    FFailing: string;
  public
    constructor Create(const AInner: IIndexFileSystem; const AFailing: string);
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    function ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
    function WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
    function TryLockWrite(const AFileName: string): IInterface;
    function OpenBlocks(const AFileName: string): IIndexBlockReader;
    function WriteStream(const AFileName: string; const AWrite: TIndexStreamWrite; out AError: string): Boolean;
  end;

  /// <summary>Dateisystem für Punkt 5: Zeitstempel fest, Größe einstellbar (IIndexFileSize).</summary>
  TSizedFileSystem = class(TInterfacedObject, IIndexFileSystem, IIndexFileSize)
  private
    FInner: IIndexFileSystem;
  public
    Size: Int64;
    constructor Create(const AInner: IIndexFileSystem);
    function FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
    function FileSize(const AFileName: string; out ASize: Int64): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function WriteText(const AFileName, AText: string): Boolean;
    function ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
    function WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
    function TryLockWrite(const AFileName: string): IInterface;
    function OpenBlocks(const AFileName: string): IIndexBlockReader;
    function WriteStream(const AFileName: string; const AWrite: TIndexStreamWrite; out AError: string): Boolean;
  end;

  /// <summary>Projektbezug für Punkt 3: Dateien unter C:\P2\ wählen die Unit aus C:\P2\.</summary>
  TProjectScopes = class(TInterfacedObject, IIndexUnitScopes)
  public
    function ChooseUnit(const AFromFile, AUnitName: string; const ACandidates: TArray<string>): string;
    function NamespacesOf(const AFromFile: string; out ANamespaces: TArray<string>): Boolean;
    function RankOf(const AFileName: string; ALibrary: Boolean): Integer;
  end;

  /// <summary>Projektbezug für Punkt 3: Rang wie TShellUnitScopes, Zusatzordner unter C:\Extra.</summary>
  TRankScopes = class(TInterfacedObject, IIndexUnitScopes)
  public
    function ChooseUnit(const AFromFile, AUnitName: string; const ACandidates: TArray<string>): string;
    function NamespacesOf(const AFromFile: string; out ANamespaces: TArray<string>): Boolean;
    function RankOf(const AFileName: string; ALibrary: Boolean): Integer;
  end;

constructor TFailingFileSystem.Create(const AInner: IIndexFileSystem; const AFailing: string);
begin
  inherited Create;
  FInner := AInner;
  FFailing := AFailing;
end;

function TFailingFileSystem.FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
begin
  Result := FInner.FileStamp(AFileName, AStamp);
end;

function TFailingFileSystem.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  if SameText(AFileName, FFailing) then
  begin
    raise EEncodingError.Create('Kodierung kaputt');
  end;
  Result := FInner.ReadText(AFileName, AText);
end;

function TFailingFileSystem.WriteText(const AFileName, AText: string): Boolean;
begin
  Result := FInner.WriteText(AFileName, AText);
end;

function TFailingFileSystem.ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
begin
  Result := FInner.ReadBytes(AFileName, ABytes);
end;

function TFailingFileSystem.WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
begin
  Result := FInner.WriteBytes(AFileName, ABytes, AError);
end;

function TFailingFileSystem.TryLockWrite(const AFileName: string): IInterface;
begin
  Result := FInner.TryLockWrite(AFileName);
end;

function TFailingFileSystem.OpenBlocks(const AFileName: string): IIndexBlockReader;
begin
  Result := FInner.OpenBlocks(AFileName);
end;

function TFailingFileSystem.WriteStream(const AFileName: string; const AWrite: TIndexStreamWrite;
  out AError: string): Boolean;
begin
  Result := FInner.WriteStream(AFileName, AWrite, AError);
end;

constructor TSizedFileSystem.Create(const AInner: IIndexFileSystem);
begin
  inherited Create;
  FInner := AInner;
end;

function TSizedFileSystem.FileStamp(const AFileName: string; out AStamp: Int64): Boolean;
begin
  Result := FInner.FileStamp(AFileName, AStamp);
end;

function TSizedFileSystem.FileSize(const AFileName: string; out ASize: Int64): Boolean;
begin
  ASize := Size;
  Result := True;
end;

function TSizedFileSystem.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FInner.ReadText(AFileName, AText);
end;

function TSizedFileSystem.WriteText(const AFileName, AText: string): Boolean;
begin
  Result := FInner.WriteText(AFileName, AText);
end;

function TSizedFileSystem.ReadBytes(const AFileName: string; out ABytes: TBytes): Boolean;
begin
  Result := FInner.ReadBytes(AFileName, ABytes);
end;

function TSizedFileSystem.WriteBytes(const AFileName: string; const ABytes: TBytes; out AError: string): Boolean;
begin
  Result := FInner.WriteBytes(AFileName, ABytes, AError);
end;

function TSizedFileSystem.TryLockWrite(const AFileName: string): IInterface;
begin
  Result := FInner.TryLockWrite(AFileName);
end;

function TSizedFileSystem.OpenBlocks(const AFileName: string): IIndexBlockReader;
begin
  Result := FInner.OpenBlocks(AFileName);
end;

function TSizedFileSystem.WriteStream(const AFileName: string; const AWrite: TIndexStreamWrite;
  out AError: string): Boolean;
begin
  Result := FInner.WriteStream(AFileName, AWrite, AError);
end;

function TProjectScopes.ChooseUnit(const AFromFile, AUnitName: string; const ACandidates: TArray<string>): string;
var
  mCandidate: string;
begin
  Result := '';
  for mCandidate in ACandidates do
  begin
    if AFromFile.StartsWith('C:\P2\', True) = mCandidate.StartsWith('C:\P2\', True) then
    begin
      Exit(mCandidate);
    end;
  end;
end;

function TProjectScopes.NamespacesOf(const AFromFile: string; out ANamespaces: TArray<string>): Boolean;
begin
  ANamespaces := nil;
  Result := False;
end;

function TProjectScopes.RankOf(const AFileName: string; ALibrary: Boolean): Integer;
begin
  Result := Ord(ALibrary);
end;

function TRankScopes.ChooseUnit(const AFromFile, AUnitName: string; const ACandidates: TArray<string>): string;
begin
  Result := '';
end;

function TRankScopes.NamespacesOf(const AFromFile: string; out ANamespaces: TArray<string>): Boolean;
begin
  ANamespaces := nil;
  Result := False;
end;

function TRankScopes.RankOf(const AFileName: string; ALibrary: Boolean): Integer;
begin
  if not ALibrary then
  begin
    Result := 0;
  end
  else if AFileName.StartsWith('C:\EXTRA\', True) then
  begin
    Result := 2;
  end
  else
  begin
    Result := 1;
  end;
end;

/// <summary>Unit AName in AFileName für die Tests von Punkt 3.</summary>
function UnitAt(const AName, AFileName: string; ALibrary: Boolean): TUnitIndex;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AName;
  Result.FileName := AFileName;
  Result.Library_ := ALibrary;
end;

{ TDpccSourcesTests }

procedure TDpccSourcesTests.WarmUp;
begin
  RunOnDemandScenario(True);
  ExtraFoldersUseLibraryDefines;
  UnreadableFileDoesNotStopBuild;
  InPathsAndFromDirectory;
  ContextCarriesBrowsingPathAndProfile;
end;

procedure TDpccSourcesTests.ExtraFolderMacrosResolve;
var
  mVariables: TArray<TPair<string, string>>;
  mEnvironment: TIndexEnvironment;
begin
  mVariables := [TPair<string, string>.Create('BDS', 'C:\Studio')];
  mEnvironment :=
    function(const AName: string): string
    begin
      if SameText(AName, 'LIBS') then
      begin
        Result := 'D:\Libs';
      end
      else
      begin
        Result := '';
      end;
    end;
  Assert.AreEqual('C:\Studio\Source\DUnitX', TIndexProjectFiles.ExpandFolder('$(BDS)\Source\DUnitX', mVariables,
    mEnvironment), 'Variable der Installation');
  Assert.AreEqual('D:\Libs\X', TIndexProjectFiles.ExpandFolder('$(LIBS)\X', mVariables, mEnvironment),
    '$(Name) aus der Umgebung');
  Assert.AreEqual('D:\Libs\Y', TIndexProjectFiles.ExpandFolder(' %LIBS%\Y\ ', mVariables, mEnvironment),
    '%Name% aus der Umgebung, ohne Leerraum und Trenner am Ende');
  Assert.AreEqual('C:\50%\Z', TIndexProjectFiles.ExpandFolder('C:\50%\Z', mVariables, mEnvironment),
    'einzelnes % bleibt');
  Assert.AreEqual('', TIndexProjectFiles.ExpandFolder('$(UNBEKANNT)\X', mVariables, mEnvironment),
    'offener Verweis: verworfen');
end;

procedure TDpccSourcesTests.FolderTreeSkipsHistoryAndStopsAtLimit;
var
  mChildren: TDictionary<string, TArray<string>>;
  mList: TIndexListFolders;
  mTree: TArray<string>;
  mTruncated: Boolean;
begin
  mChildren := TDictionary<string, TArray<string>>.Create;
  try
    mChildren.Add('C:\R', ['C:\R\b', 'C:\R\A', 'C:\R\__history', 'C:\R\.git']);
    mChildren.Add('C:\R\A', ['C:\R\A\Deep', 'C:\R\A\__recovery']);
    mList :=
      function(const AFolder: string): TArray<string>
      begin
        if not mChildren.TryGetValue(AFolder, Result) then
        begin
          Result := nil;
        end;
      end;
    mTree := TIndexProjectFiles.FolderTree(['C:\R\', 'C:\r\a'], mList, 100, mTruncated);
    Assert.AreEqual('C:\R|C:\R\A|C:\R\A\Deep|C:\R\b', string.Join('|', mTree), 'Tiefe zuerst, ohne Doppel');
    Assert.IsFalse(mTruncated, 'unter der Grenze');
    mTree := TIndexProjectFiles.FolderTree(['C:\R'], mList, 2, mTruncated);
    Assert.AreEqual(2, Integer(Length(mTree)), 'Grenze');
    Assert.IsTrue(mTruncated, 'gekürzt');
  finally
    mChildren.Free;
  end;
end;

procedure TDpccSourcesTests.ExtraSignatureIgnoresOrder;
var
  mProject: TProjectInfo;
begin
  mProject := Default(TProjectInfo);
  mProject.Platform := 'Win32';
  Assert.AreEqual(TIndexProjectFiles.ExtraSignature(mProject, '37.0', ['C:\A', 'd:\b']),
    TIndexProjectFiles.ExtraSignature(mProject, '37.0', ['D:\B', 'C:\a']), 'Reihenfolge und Schreibweise egal');
  Assert.AreNotEqual(TIndexProjectFiles.ExtraSignature(mProject, '37.0', ['C:\A']),
    TIndexProjectFiles.ExtraSignature(mProject, '37.0', ['C:\A', 'C:\B']), 'andere Ordner, anderer Cache');
  mProject.Platform := 'Win64';
  Assert.AreNotEqual(TIndexProjectFiles.ExtraSignature(mProject, '37.0', ['C:\A']),
    TIndexProjectFiles.ExtraSignature(Default(TProjectInfo), '37.0', ['C:\A']), 'andere Plattform');
end;

procedure TDpccSourcesTests.OnDemandUnitStaysUnpinnedViaLibraryUses;
begin
  Assert.IsFalse(RunOnDemandScenario(True), 'Office/WinRT über die uses der Bibliothek: bleibt verdrängbar');
  Assert.IsTrue(RunOnDemandScenario(False), 'Gegenprobe ohne OnDemandRoots: gepinnt');
end;

procedure TDpccSourcesTests.ExtraFoldersUseLibraryDefines;
var
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mBuilder: TIndexBuilder;
  mFound: TUnitIndex;
begin
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mFiles.Put('D:\Extra\X.pas', 'unit X;'#10'interface'#10'{$IFDEF PROJEKT}type TProjekt = class end;{$ENDIF}'#10 +
    '{$IFDEF BIBLIOTHEK}type TBibliothek = class end;{$ENDIF}'#10'implementation'#10'end.', 1);
  mIndex := TSymbolIndex.Create;
  mBuilder := TIndexBuilder.Create(mIndex, mFileSystem, ['PROJEKT'], nil);
  try
    mBuilder.LibraryRoots := ['C:\Studio'];
    mBuilder.LibraryDefines := ['BIBLIOTHEK'];
    mBuilder.ExtraRoots := ['D:\Extra'];
    mBuilder.Build(nil, nil, ['D:\Extra\X.pas'], nil, nil, nil);
  finally
    mBuilder.Free;
  end;
  Assert.IsTrue(mIndex.FindUnit('X', mFound), 'X im Index');
  Assert.IsTrue(mFound.Library_, 'als Bibliothek');
  Assert.IsTrue(HasSymbol(mFound, 'TBibliothek'), 'mit den Symbolen der Bibliothek');
  Assert.IsFalse(HasSymbol(mFound, 'TProjekt'), 'nicht mit denen des Projekts');
end;

procedure TDpccSourcesTests.SameNamedUnitsKeepAllFiles;
var
  mIndex: ISymbolIndex;
  mFound: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(UnitAt('System.Foo', 'C:\Studio\source\System.Foo.pas', True));
  mIndex.AddUnit(UnitAt('System.Foo', 'C:\P\System.Foo.pas', False));
  Assert.IsTrue(mIndex.FindUnit('System.Foo', mFound), 'gefunden');
  Assert.AreEqual('C:\P\System.Foo.pas', mFound.FileName, 'gepatchte Kopie im Projekt gewinnt');
  Assert.AreEqual(2, Integer(Length(mIndex.UnitFiles('system.foo'))), 'beide Dateien bekannt');
  mIndex.AddUnit(UnitAt('Unit1', 'C:\P1\Unit1.pas', False));
  mIndex.AddUnit(UnitAt('Unit1', 'C:\P2\Unit1.pas', False));
  // Neue Fassung derselben Datei behält ihren Platz.
  mIndex.AddUnit(UnitAt('Unit1', 'C:\P1\Unit1.pas', False));
  Assert.AreEqual('C:\P1\UNIT1.PAS|C:\P2\UNIT1.PAS', string.Join('|', mIndex.UnitFiles('Unit1')), 'Reihenfolge');
  mIndex.RemoveFile('C:\P1\Unit1.pas');
  Assert.IsTrue(mIndex.FindUnit('Unit1', mFound), 'der Name bleibt (vorher: verloren)');
  Assert.AreEqual('C:\P2\Unit1.pas', mFound.FileName, 'die andere Datei');
  mIndex.RemoveFile('C:\P2\Unit1.pas');
  Assert.IsFalse(mIndex.FindUnit('Unit1', mFound), 'beide entfernt');
end;

/// <summary>Datei, aus der die Namensauflösung TShared von AFromFile aus nimmt.</summary>
function SharedFileFrom(const AIndex: ISymbolIndex; const AFromFile: string): string;
var
  mResolver: TNameResolver;
  mFrom: TUnitIndex;
  mFound: TResolvedSymbol;
begin
  Result := '';
  Assert.IsTrue(AIndex.FindFile(AFromFile, mFrom), AFromFile);
  mResolver := TNameResolver.Create(AIndex);
  try
    if mResolver.ResolveTypeFrom(mFrom, 'TShared', mFound) then
    begin
      Result := mFound.FileName;
    end;
  finally
    mResolver.Free;
  end;
end;

procedure TDpccSourcesTests.ResolverTakesUnitOfOwnProject;
var
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mBuilder: TIndexBuilder;
begin
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mFiles.Put('C:\P1\Main.pas', 'unit Main;'#10'interface'#10'uses Shared;'#10'implementation'#10'end.', 1);
  mFiles.Put('C:\P1\Shared.pas', 'unit Shared;'#10'interface'#10'type TShared = class end;'#10'implementation'#10'end.', 1);
  mFiles.Put('C:\P2\Main2.pas', 'unit Main2;'#10'interface'#10'uses Shared;'#10'implementation'#10'end.', 1);
  mFiles.Put('C:\P2\Shared.pas', 'unit Shared;'#10'interface'#10'type TShared = class end;'#10'implementation'#10'end.', 1);
  mIndex := TSymbolIndex.Create;
  mBuilder := TIndexBuilder.Create(mIndex, mFileSystem, ['MSWINDOWS'], nil);
  try
    mBuilder.Build(['C:\P1\Main.pas', 'C:\P1\Shared.pas', 'C:\P2\Main2.pas', 'C:\P2\Shared.pas'], nil, nil);
  finally
    mBuilder.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mIndex.UnitFiles('Shared'))), 'beide Dateien');
  // Gegenprobe ohne Projektbezug: die zuerst aufgenommene.
  Assert.AreEqual('C:\P1\Shared.pas', SharedFileFrom(mIndex, 'C:\P2\Main2.pas'), 'ohne Projektbezug die erste');
  mIndex.SetUnitScopes(TProjectScopes.Create);
  try
    Assert.AreEqual('C:\P2\Shared.pas', SharedFileFrom(mIndex, 'C:\P2\Main2.pas'), 'Projekt 2 nimmt seine Unit');
    Assert.AreEqual('C:\P1\Shared.pas', SharedFileFrom(mIndex, 'C:\P1\Main.pas'), 'Projekt 1 seine');
  finally
    mIndex.SetUnitScopes(nil);
  end;
end;

procedure TDpccSourcesTests.RankPutsExtraFoldersLast;
var
  mIndex: ISymbolIndex;
  mFound: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.SetUnitScopes(TRankScopes.Create);
  try
    // Der Zusatzordner kommt zuerst in den Index, die Bibliothek danach: Der Rang entscheidet.
    mIndex.AddUnit(UnitAt('Shared.Unit', 'C:\Extra\Shared.Unit.pas', True));
    mIndex.AddUnit(UnitAt('Shared.Unit', 'C:\Studio\Shared.Unit.pas', True));
    Assert.IsTrue(mIndex.FindUnit('Shared.Unit', mFound), 'gefunden');
    Assert.AreEqual('C:\Studio\Shared.Unit.pas', mFound.FileName, 'Bibliothek vor Zusatzordner');
  finally
    mIndex.SetUnitScopes(nil);
  end;
end;

procedure TDpccSourcesTests.UnreadableFileDoesNotStopBuild;
var
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mBuilder: TIndexBuilder;
  mResult: TIndexBuildResult;
  mReported: string;
  mFound: TUnitIndex;
begin
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mFiles.Put('C:\P\A.pas', 'unit A;'#10'interface'#10'implementation'#10'end.', 1);
  mFiles.Put('C:\P\B.pas', 'unit B;'#10'interface'#10'implementation'#10'end.', 1);
  mFiles.Put('C:\P\C.pas', 'unit C;'#10'interface'#10'implementation'#10'end.', 1);
  mIndex := TSymbolIndex.Create;
  mReported := '';
  mBuilder := TIndexBuilder.Create(mIndex, TFailingFileSystem.Create(mFileSystem, 'C:\P\B.pas'), ['MSWINDOWS'], nil);
  try
    mBuilder.OnUnreadable :=
      procedure(const AFileName, AError: string)
      begin
        mReported := mReported + AFileName + '=' + AError;
      end;
    mResult := mBuilder.Build(['C:\P\A.pas', 'C:\P\B.pas', 'C:\P\C.pas'], nil, nil);
  finally
    mBuilder.Free;
  end;
  Assert.AreEqual(1, mResult.Unreadable, 'eine Datei übergangen');
  Assert.IsFalse(mResult.OutOfMemory, 'kein Speichermangel');
  Assert.IsTrue(mIndex.FindUnit('A', mFound) and mIndex.FindUnit('C', mFound), 'die anderen im Index');
  Assert.IsFalse(mIndex.FindUnit('B', mFound), 'B fehlt');
  Assert.Contains(mReported, 'C:\P\B.pas=EEncodingError: Kodierung kaputt', 'gemeldet mit Pfad und Fehler');
end;

procedure TDpccSourcesTests.SizeChangesSourceStamp;
var
  mFiles: TCountingIndexFileSystem;
  mSized: TSizedFileSystem;
  mFileSystem: IIndexFileSystem;
  mFirst, mSecond: Int64;
begin
  mFiles := TCountingIndexFileSystem.Create;
  mSized := TSizedFileSystem.Create(mFiles);
  mFileSystem := mSized;
  mFiles.Put('C:\P\A.pas', 'unit A;', 1000);
  mSized.Size := 100;
  Assert.IsTrue(TIndexBuilder.SourceStampOf(mFileSystem, 'C:\P\A.pas', mFirst), 'Stand');
  mSized.Size := 101;
  TIndexBuilder.SourceStampOf(mFileSystem, 'C:\P\A.pas', mSecond);
  Assert.AreNotEqual(mFirst, mSecond, 'andere Größe, anderer Stand');
  // Ohne IIndexFileSize: nur der Zeitstempel wie bisher.
  TIndexBuilder.SourceStampOf(mFiles, 'C:\P\A.pas', mSecond);
  Assert.AreEqual(Int64(1000), mSecond, 'ohne Größe');
end;

procedure TDpccSourcesTests.StaleColdUnitIsReadAgain;
var
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mBuilder: TIndexBuilder;
  mHeader, mFound: TUnitIndex;
begin
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mFiles.Put('C:\Lib\W.pas', 'unit W;'#10'interface'#10'type TAlt = class end;'#10'implementation'#10'end.', 1);
  mIndex := TSymbolIndex.Create;
  mBuilder := TIndexBuilder.Create(mIndex, mFileSystem, ['MSWINDOWS'], nil);
  try
    mBuilder.LibraryRoots := ['C:\Lib'];
    mBuilder.LazyLibrary := True;
    mBuilder.Build(nil, nil, ['C:\Lib\W.pas'], nil, nil, nil);
    Assert.IsTrue(mIndex.FindHeader('C:\Lib\W.pas', mHeader), 'Kopf');
    Assert.IsFalse(mBuilder.RefreshStale(mHeader), 'unverändert: nichts zu tun');
    mFiles.Put('C:\Lib\W.pas', 'unit W;'#10'interface'#10'type TNeu = class end;'#10'implementation'#10'end.', 2);
    Assert.IsTrue(mBuilder.RefreshStale(mHeader), 'geändert: neu gelesen');
  finally
    mBuilder.Free;
  end;
  Assert.IsTrue(mIndex.FindUnit('W', mFound) and HasSymbol(mFound, 'TNeu'), 'neuer Stand im Index');
end;

procedure TDpccSourcesTests.CreatedFileJoinsIndex;
var
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mBuilder: TIndexBuilder;
  mStored: TIndexStoredUnit;
  mPinned: Boolean;
begin
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mIndex := TSymbolIndex.Create;
  mBuilder := TIndexBuilder.Create(mIndex, mFileSystem, ['MSWINDOWS'], nil);
  try
    mBuilder.Build(nil, nil, nil);
    mFiles.Put('C:\Such\Neu.pas', 'unit Neu;'#10'interface'#10'implementation'#10'end.', 1);
    Assert.IsTrue(mBuilder.AddFile('C:\Such\Neu.pas', False), 'aufgenommen');
    Assert.IsFalse(mBuilder.AddFile('C:\Such\Fehlt.pas', False), 'fehlende Datei');
  finally
    mBuilder.Free;
  end;
  mPinned := False;
  for mStored in mIndex.StoredUnits do
  begin
    if SameText(mStored.Unit_.UnitName, 'Neu') then
    begin
      mPinned := mStored.Pinned;
    end;
  end;
  Assert.IsTrue(mPinned, 'Suchpfad-Unit gepinnt');
end;

procedure TDpccSourcesTests.InPathsAndFromDirectory;
var
  mProject: TProjectInfo;
  mUnit: TProjectUnit;
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mBuilder: TIndexBuilder;
  mAsked: string;
begin
  mProject := Default(TProjectInfo);
  mProject.MainSource := 'C:\P\App.dpr';
  mUnit.Name := 'Alt';
  mUnit.FileName := 'C:\P\Alt.pas';
  mProject.Units := [mUnit];
  mProject := TDprojReader.WithInPaths(mProject, 'program App;'#10'uses'#10'  Alt in ''Alt.pas'','#10 +
    '  Neu in ''..\Gemeinsam\Neu.pas'' {Form1},'#10'  System.SysUtils;'#10'begin end.');
  Assert.AreEqual(2, Integer(Length(mProject.Units)), 'eine dazu, keine doppelt');
  Assert.AreEqual('C:\Gemeinsam\Neu.pas', mProject.Units[1].FileName, 'Pfad ab dem Ordner der .dpr');
  // uses der Projekt-Unit: ab ihrem eigenen Ordner gesucht.
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mFiles.Put('C:\Q\Sub\U.pas', 'unit U;'#10'interface'#10'uses V;'#10'implementation'#10'end.', 1);
  mFiles.Put('C:\Q\Sub\V.pas', 'unit V;'#10'interface'#10'implementation'#10'end.', 1);
  mIndex := TSymbolIndex.Create;
  mAsked := '';
  mBuilder := TIndexBuilder.Create(mIndex, mFileSystem, ['MSWINDOWS'],
    function(const AUnitName: string): string
    begin
      Result := '';
    end);
  try
    mBuilder.ResolveUnitFrom :=
      function(const AUnitName, AFromDirectory: string): string
      begin
        mAsked := mAsked + AUnitName + '@' + AFromDirectory + ';';
        Result := TPath.Combine(AFromDirectory, AUnitName + '.pas');
      end;
    mBuilder.Build(['C:\Q\Sub\U.pas'], nil, nil);
  finally
    mBuilder.Free;
  end;
  Assert.Contains(mAsked, 'V@C:\Q\Sub;', 'mit dem Ordner der nennenden Unit gesucht');
end;

procedure TDpccSourcesTests.FolderStampsReportChanges;
var
  mFolder: string;
  mStamps: TShellFolderStamps;
  mIndex: ISymbolIndex;
  mChanges: TArray<TFileChange>;
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mKnown: TUnitIndex;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'dpcc-l2-scan-' + IntToStr(MainThreadID));
  ForceDirectories(mFolder);
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mStamps := TShellFolderStamps.Create;
  try
    TFile.WriteAllText(TPath.Combine(mFolder, 'Alt.pas'), 'unit Alt;');
    TFile.WriteAllText(TPath.Combine(mFolder, 'Weg.pas'), 'unit Weg;');
    mIndex := TSymbolIndex.Create;
    mKnown := UnitAt('Alt', TPath.Combine(mFolder, 'Alt.pas'), True);
    mKnown.Stamp := 5;
    mIndex.AddUnit(mKnown);
    mIndex.AddUnit(UnitAt('Weg', TPath.Combine(mFolder, 'Weg.pas'), True));
    mFiles.Put(TPath.Combine(mFolder, 'Alt.pas'), 'unit Alt;', 5);
    mChanges := mStamps.Changes([mFolder], mIndex, mFileSystem);
    Assert.AreEqual(0, Integer(Length(mChanges)), 'erster Blick: nur merken');
    TFile.WriteAllText(TPath.Combine(mFolder, 'Neu.pas'), 'unit Neu;');
    TFile.Delete(TPath.Combine(mFolder, 'Weg.pas'));
    mFiles.Put(TPath.Combine(mFolder, 'Alt.pas'), 'unit Alt;', 6);
    mChanges := mStamps.Changes([mFolder], mIndex, mFileSystem);
    Assert.AreEqual(3, Integer(Length(mChanges)), 'neu, geändert, gelöscht');
    Assert.AreEqual(0, Integer(Length(mStamps.Changes([mFolder], mIndex, mFileSystem))), 'unverändert: nichts');
  finally
    mStamps.Free;
    TDirectory.Delete(mFolder, True);
  end;
end;

procedure TDpccSourcesTests.ContextCarriesBrowsingPathAndProfile;
var
  mJson: TJSONObject;
  mContext, mOther: TIdeProjectContext;
  mProject: TProjectInfo;
  mDropped: TArray<string>;
  mVariables: TArray<TPair<string, string>>;
  mPair: TPair<string, string>;
  mHasPath: Boolean;
begin
  mJson := TJSONObject.ParseJSONValue('{"project": "C:\\P\\P.dproj", "platform": "Win64x", "searchPaths": ' +
    '["$(Unbekannt)\\X", "Lib"], "browsingPaths": ["$(BDS)\\source\\rtl"], "registryKey": ' +
    '"Software\\Embarcadero\\Profil\\37.0"}') as TJSONObject;
  try
    mContext := TIdeProjectContext.FromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.AreEqual('Software\Embarcadero\Profil\37.0', mContext.RegistryKey, 'Profil');
  Assert.AreEqual(1, Integer(Length(mContext.BrowsingPaths)), 'Browsing Path');
  mOther := mContext;
  mOther.BrowsingPaths := nil;
  Assert.AreNotEqual(mContext.Key, mOther.Key, 'Browsing Path gehört zum Schlüssel');
  mProject := Default(TProjectInfo);
  mProject.FileName := 'C:\P\P.dproj';
  mProject.Platform := 'Win64x';
  mContext.ApplyTo(mProject, [TPair<string, string>.Create('BDS', 'C:\Studio')], mDropped);
  Assert.AreEqual('$(Unbekannt)\X', string.Join('|', mDropped), 'verworfener Pfad genannt');
  Assert.AreEqual(1, Integer(Length(mProject.SearchPaths)), 'der andere bleibt');
  Assert.AreEqual('C:\Studio\source\rtl', string.Join('|', mContext.ExpandedBrowsingPaths(mProject,
    [TPair<string, string>.Create('BDS', 'C:\Studio')], mDropped)), 'Browsing Path aufgelöst');
  // Alle Umgebungsvariablen des Prozesses (vorher fünf).
  mVariables := TDelphiInstallation.ProcessEnvironment;
  mHasPath := False;
  for mPair in mVariables do
  begin
    mHasPath := mHasPath or SameText(mPair.Key, 'PATH') or SameText(mPair.Key, 'SystemRoot');
  end;
  Assert.IsTrue(mHasPath, 'PATH bzw. SystemRoot aus der Umgebung');
end;

procedure TDpccSourcesTests.InstalledTypesOnlyWithoutSource;
var
  mSources: TDictionary<string, Boolean>;
  mType: TDpccIdeType;
begin
  mSources := TDpccIdeTypes.UnitNames(['C:\Studio\source\vcl\Vcl.Forms.pas', 'C:\Studio\OCX\Servers\Word2010.pas']);
  try
    Assert.IsTrue(TDpccIdeType.FromQualified('Vcl.Forms.TForm', '', mType), 'Typ');
    Assert.IsFalse(TDpccIdeTypes.KeepInstalled(mType, mSources), 'mit Quelltext: steht im Index');
    Assert.IsTrue(TDpccIdeType.FromQualified('DUnitX.TestFramework.TDUnitX', '', mType), 'Typ');
    Assert.IsTrue(TDpccIdeTypes.KeepInstalled(mType, mSources), 'nur als .dcu: von der IDE');
    Assert.IsTrue(TDpccIdeTypes.KeepInstalled(mType, nil), 'außerhalb der Installation immer');
  finally
    mSources.Free;
  end;
end;

procedure TDpccSourcesTests.IdeTypesAndUnitsAreUnique;
var
  mTypes, mUnique: TArray<TDpccIdeType>;
  mCatalog: TIdeTypeCatalog;
  mCatalogRef: IRuleIdeTypes;
  mParams: TJSONValue;
  mUnits: TArray<string>;
begin
  SetLength(mTypes, 4);
  Assert.IsTrue(TDpccIdeType.FromQualified('Vendor.Grid.TVendorGrid', 'Vcl.Controls.TCustomControl', mTypes[0]));
  Assert.IsTrue(TDpccIdeType.FromQualified('Vendor.Grid.TVendorGrid', '', mTypes[1]), 'Palette');
  Assert.IsTrue(TDpccIdeType.FromQualified('VENDOR.GRID.TVendorGrid', '', mTypes[2]), 'andere Schreibweise');
  Assert.IsTrue(TDpccIdeType.FromQualified('Vendor.Other.TVendorGrid', '', mTypes[3]), 'andere Unit');
  mUnique := TDpccIdeTypes.Unique(mTypes);
  Assert.AreEqual(2, Integer(Length(mUnique)));
  Assert.AreEqual('Vcl.Controls.TCustomControl', mUnique[0].Parent, 'der erste bleibt');
  Assert.AreEqual('Vendor.Other', mUnique[1].UnitName);
  // Server: dieselbe Unit mehrfach gemeldet, auch in anderer Schreibweise.
  mCatalog := TIdeTypeCatalog.Create;
  mCatalogRef := mCatalog;
  mParams := TJSONObject.ParseJSONValue('{"units": [{"unit": "Vendor.Grid", "types": ["TVendorGrid"]}, ' +
    '{"unit": "VENDOR.GRID", "types": ["TVendorGrid", {"name": "TVendorGrid"}]}, ' +
    '{"unit": "Vendor.Other", "types": ["TVendorGrid"]}]}');
  try
    Assert.AreEqual(2, mCatalog.Replace(mParams));
  finally
    mParams.Free;
  end;
  mUnits := mCatalog.UnitsOf('tvendorgrid');
  Assert.AreEqual(2, Integer(Length(mUnits)));
  Assert.AreEqual('Vendor.Grid', mUnits[0]);
  Assert.AreEqual('Vendor.Other', mUnits[1]);
  Assert.AreEqual(0, Integer(Length(mCatalog.UnitsOf('TUnbekannt'))));
end;

procedure TDpccSourcesTests.Win64xBorrowsBrowsingPath;
var
  mInstallation: TDelphiInstallation;
  mHold: IInterface;
begin
  if TDelphiInstallation.RootDirOf('37.0') = '' then
  begin
    Assert.Pass('Delphi 13 nicht installiert');
    Exit;
  end;
  mInstallation := TDelphiInstallation.Create('37.0');
  mHold := mInstallation;
  Assert.AreEqual('Software\Embarcadero\BDS\37.0', mInstallation.BaseKey, 'Standardprofil');
  Assert.IsTrue(Length(mInstallation.BrowsingPaths('Win64x')) > 0, 'Win64x hat Quellpfade');
  Assert.AreEqual(Length(mInstallation.BrowsingPaths('Win64')), Length(mInstallation.BrowsingPaths('Win64x')),
    'wie Win64, solange Win64x keinen eigenen hat');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccSourcesTests);

end.
