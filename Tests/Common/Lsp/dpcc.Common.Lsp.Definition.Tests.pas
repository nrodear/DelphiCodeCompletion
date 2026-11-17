unit dpcc.Common.Lsp.Definition.Tests;

// Sprungziele (TLspDefinition), zurückgeholt aus _deleteMe (Auftrag NAV, auf dpcc. umgestellt) und um die Fälle für
// Strg+Klick ergänzt: Methode ↔ Implementierung, über Units, Unit-Name in uses, lokale Variable und Parameter,
// Typdefinition, Feld nach Ausdruck (List[i].X, L3-Auflösung), Include-Datei, nicht geltender $IFDEF-Zweig,
// kalte Bibliotheks-Unit, Office-Typbibliothek (kalt, im Katalog), Ersatz-Unit ohne Quelltext (kein Sprung) und
// gleichnamige Units (L2). Die Fälle zählen für die Trefferquote im Bericht des Auftrags.

interface

uses
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Lsp.Definition;

type
  [TestFixture]
  TLspDefinitionTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function TargetsAt(const AMarker: string; AOccurrence: Integer; ADeclaration: Boolean): TArray<TDefinitionTarget>;
    function TargetsIn(const AText, AMarker: string; AOccurrence: Integer;
      ADeclaration: Boolean): TArray<TDefinitionTarget>;
    /// <summary>Wie TargetsIn für eine Datei AFileName, die vorher in den Index kommt.</summary>
    function TargetsOfFile(const AText, AFileName, AMarker: string; AOccurrence: Integer;
      ADeclaration: Boolean): TArray<TDefinitionTarget>;
    procedure AddColdUnits(const AUnits: TArray<TUnitIndex>);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DefinitionOfMethodCallIsImplementation;
    [Test]
    procedure DeclarationOfMethodCallIsClassMember;
    [Test]
    procedure DefinitionOnImplementationJumpsBack;
    [Test]
    procedure DefinitionCrossesUnits;
    [Test]
    procedure UnitNameJumpsToFileStart;
    [Test]
    procedure LocalVariableAndUnknownName;
    /// <summary>Parameter einer Routine: zu seiner Deklaration in der Parameterliste.</summary>
    [Test]
    procedure ParameterJumpsToItsDeclaration;
    /// <summary>Typname in einer Deklaration: zur Deklaration des Typs.</summary>
    [Test]
    procedure TypeNameJumpsToTypeDeclaration;
    [Test]
    procedure TypeDefinitionFollowsDeclaredTypes;
    /// <summary>Feld hinter einem Ausdruck (List[i].X): über den Typ des Elements (L3).</summary>
    [Test]
    procedure FieldAfterIndexExpression;
    /// <summary>Routine aus einer Include-Datei: Ziel in der Include-Datei.</summary>
    [Test]
    procedure RoutineFromIncludeFile;
    /// <summary>Deklaration nur in einem nicht geltenden $IFDEF-Zweig: dorthin (UnavailableTargets, NAV).</summary>
    [Test]
    procedure InactiveBranchDeclaration;
    /// <summary>Typ aus einer kalten Bibliotheks-Unit (nur Katalog im Speicher): Die Unit wird nachgeladen.</summary>
    [Test]
    procedure ColdLibraryUnitIsLoaded;
    /// <summary>Office-Typbibliothek (kalt im Katalog, bei Bedarf geladen, L2): wie eine kalte Unit.</summary>
    [Test]
    procedure OfficeTypeLibraryUnit;
    /// <summary>Gleichnamige Units (L2): Ziel ist die Unit des eigenen Projekts.</summary>
    [Test]
    procedure SameNamedUnitsFollowProject;
    [Test]
    procedure WritesLocations;
    /// <summary>Ersatz-Units der IDE (dpcc-ide:…) gibt es nicht als Datei: kein Sprungziel.</summary>
    [Test]
    procedure SkipsIdeUnits;
    /// <summary>Typ aus einer Unit ohne Quelltext (nur Ersatz-Unit der IDE): kein Sprung.</summary>
    [Test]
    procedure IdeUnitTypeHasNoJump;
    /// <summary>Überladungen: Deklaration und Implementierung derselben Variante (gleiche Parametertypen); vorher
    /// galt immer die erste Überladung (Hover auf der zweiten zeigte die erste).</summary>
    [Test]
    procedure OverloadsPairByParameters;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  System.JSON,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Pascal.Parser,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.Extractor,
  dpcc.Common.Index.Cache,
  dpcc.Common.Lsp.IdeUnits;

const
  HauptFile = 'C:\P\Haupt.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'procedure Rechne;'#10 +
    'implementation'#10 +
    'procedure Rechne;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werkzeug;'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Bar;'#10 +
    '    procedure Baz;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar;'#10 +
    'var'#10 +
    '  Wert: Integer;'#10 +
    'begin'#10 +
    '  Wert := 1;'#10 +
    '  Baz;'#10 +
    '  Rechne;'#10 +
    '  Unbekannt;'#10 +
    'end;'#10 +
    'procedure TFoo.Baz;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  KonsoleFile = 'C:\P\Konsole.pas';

  UnitKonsole =
    'unit Konsole;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKonsole = class'#10 +
    '    procedure Progress(const S: string); overload;'#10 +
    '    procedure Progress(const S: string; Force: Boolean); overload;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TKonsole.Progress(const S: string);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TKonsole.Progress(const S: string; Force: Boolean);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  VendorThingsFile = 'C:\Lib\Vendor.Things.pas';

  UnitVendorThings =
    'unit Vendor.Things;'#10 +              // 0
    'interface'#10 +                        // 1
    'type'#10 +                             // 2
    '  TVendorThing = class(TObject)'#10 +  // 3
    '  end;'#10 +                           // 4
    'implementation'#10 +                   // 5
    'end.';

  WordFile = 'C:\Studio\OCX\Servers\Word2010.pas';

  UnitWord =
    'unit Word2010;'#10 +                   // 0
    'interface'#10 +                        // 1
    'type'#10 +                             // 2
    '  TWordApplication = class(TObject)'#10 + // 3
    '  end;'#10 +                           // 4
    'implementation'#10 +                   // 5
    'end.';

type
  /// <summary>Projektbezug für gleichnamige Units (L2): gilt die Datei im Ordner der fragenden Datei.</summary>
  TFolderScopes = class(TInterfacedObject, IIndexUnitScopes)
  public
    function ChooseUnit(const AFromFile, AUnitName: string; const ACandidates: TArray<string>): string;
    function NamespacesOf(const AFromFile: string; out ANamespaces: TArray<string>): Boolean;
    function RankOf(const AFileName: string; ALibrary: Boolean): Integer;
  end;

function TFolderScopes.ChooseUnit(const AFromFile, AUnitName: string; const ACandidates: TArray<string>): string;
var
  mCandidate: string;
begin
  Result := '';
  for mCandidate in ACandidates do
  begin
    if SameText(ExtractFilePath(mCandidate), ExtractFilePath(AFromFile)) then
    begin
      Exit(mCandidate);
    end;
  end;
end;

function TFolderScopes.NamespacesOf(const AFromFile: string; out ANamespaces: TArray<string>): Boolean;
begin
  ANamespaces := nil;
  Result := False;
end;

function TFolderScopes.RankOf(const AFileName: string; ALibrary: Boolean): Integer;
begin
  Result := 0;
end;

function PositionOf(const AText, AMarker: string; AOccurrence: Integer): TTextPosition;
var
  Index, Found, Line, LineStart: Integer;
begin
  Found := 0;
  Index := 0;
  repeat
    Index := Pos(AMarker, AText, Index + 1);
    if Index = 0 then
    begin
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    end;
    Inc(Found);
  until Found = AOccurrence;
  Line := 0;
  LineStart := 1;
  for Found := 1 to Index - 1 do
  begin
    if AText[Found] = #10 then
    begin
      Inc(Line);
      LineStart := Found + 1;
    end;
  end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

/// <summary>Bibliotheks-Unit aus AText.</summary>
function LibraryUnit(const AText, AFileName: string): TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(AText, AFileName, nil);
  Result.Library_ := True;
  Result.Stamp := 7;
  Result.Hash := 'H' + AFileName;
end;

{ TLspDefinitionTests }

procedure TLspDefinitionTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, 'C:\P\Werkzeug.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspDefinitionTests.TearDown;
begin
  FreeAndNil(FResolver);
  FIndex := nil;
end;

procedure TLspDefinitionTests.AddColdUnits(const AUnits: TArray<TUnitIndex>);
var
  mEntries: TArray<TIndexCacheEntry>;
  mEntry: TIndexCacheEntry;
begin
  // Wie die Bibliotheksstufe beim Start aus dem Cache: nur Kopf, Katalog und Block.
  mEntries := TIndexCache.ReadEntries(TIndexCache.Serialize(AUnits));
  Assert.AreEqual(Integer(Length(AUnits)), Integer(Length(mEntries)), 'Cache gelesen');
  for mEntry in mEntries do
  begin
    FIndex.AddCold(mEntry.Header, mEntry.Catalog, mEntry.Source, mEntry.SymbolCount, mEntry.UnavailableCount,
      mEntry.UsageCount);
  end;
end;

function TLspDefinitionTests.TargetsAt(const AMarker: string; AOccurrence: Integer;
  ADeclaration: Boolean): TArray<TDefinitionTarget>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Result := TLspDefinition.Targets(FResolver, FIndex, Tree, HauptFile,
      PositionOf(UnitHaupt, AMarker, AOccurrence), ADeclaration);
  finally
    Tree.Free;
  end;
end;

function TLspDefinitionTests.TargetsIn(const AText, AMarker: string; AOccurrence: Integer;
  ADeclaration: Boolean): TArray<TDefinitionTarget>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TLspDefinition.Targets(FResolver, FIndex, Tree, KonsoleFile, PositionOf(AText, AMarker, AOccurrence),
      ADeclaration);
  finally
    Tree.Free;
  end;
end;

function TLspDefinitionTests.TargetsOfFile(const AText, AFileName, AMarker: string; AOccurrence: Integer;
  ADeclaration: Boolean): TArray<TDefinitionTarget>;
var
  Tree: TSyntaxTree;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(AText, AFileName, nil));
  Tree := TPascalParser.Parse(AText);
  try
    Result := TLspDefinition.Targets(FResolver, FIndex, Tree, AFileName, PositionOf(AText, AMarker, AOccurrence),
      ADeclaration);
  finally
    Tree.Free;
  end;
end;

procedure TLspDefinitionTests.OverloadsPairByParameters;
const
  Zweite = 'Progress(const S: string; Force';
  Erste = 'Progress(const S: string)';
var
  Targets: TArray<TDefinitionTarget>;
begin
  // Hover und Strg+Klick auf der zweiten Überladung: ihre eigene Deklaration.
  Targets := TargetsIn(UnitKonsole, Zweite, 1, True);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual(5, Targets[0].SelectionRange.StartPos.Line, 'Deklaration der zweiten');
  Assert.AreEqual(5, Targets[0].Range.StartPos.Line, 'Bereich der zweiten');
  // definition auf der Deklaration der zweiten: ihre Implementierung, und zurück.
  Targets := TargetsIn(UnitKonsole, Zweite, 1, False);
  Assert.AreEqual(11, Targets[0].SelectionRange.StartPos.Line, 'Implementierung der zweiten');
  Targets := TargetsIn(UnitKonsole, Zweite, 2, False);
  Assert.AreEqual(5, Targets[0].SelectionRange.StartPos.Line, 'zurück zur zweiten');
  // Die erste bleibt bei sich.
  Targets := TargetsIn(UnitKonsole, Erste, 1, False);
  Assert.AreEqual(8, Targets[0].SelectionRange.StartPos.Line, 'Implementierung der ersten');
  Targets := TargetsIn(UnitKonsole, Erste, 2, False);
  Assert.AreEqual(4, Targets[0].SelectionRange.StartPos.Line, 'zurück zur ersten');
end;

procedure TLspDefinitionTests.DefinitionOfMethodCallIsImplementation;
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsAt('Baz;', 2, False);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual(HauptFile, Targets[0].FileName);
  Assert.AreEqual(18, Targets[0].SelectionRange.StartPos.Line);
end;

procedure TLspDefinitionTests.DeclarationOfMethodCallIsClassMember;
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsAt('Baz;', 2, True);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual(6, Targets[0].SelectionRange.StartPos.Line);
end;

procedure TLspDefinitionTests.DefinitionOnImplementationJumpsBack;
var
  Targets: TArray<TDefinitionTarget>;
begin
  // Auf der Deklaration in der Klasse: zur Implementierung.
  Targets := TargetsAt('Bar;', 1, False);
  Assert.AreEqual(9, Targets[0].SelectionRange.StartPos.Line);
  // Auf dem Namen der Implementierung: zurück zur Deklaration (auch mit declaration).
  Targets := TargetsAt('Bar;', 2, False);
  Assert.AreEqual(5, Targets[0].SelectionRange.StartPos.Line);
  Targets := TargetsAt('Bar;', 2, True);
  Assert.AreEqual(5, Targets[0].SelectionRange.StartPos.Line);
  // declaration auf der Deklaration selbst: sie selbst (die IDE-Seite fragt dann definition, NAV).
  Targets := TargetsAt('Bar;', 1, True);
  Assert.AreEqual(5, Targets[0].SelectionRange.StartPos.Line);
end;

procedure TLspDefinitionTests.DefinitionCrossesUnits;
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsAt('Rechne;', 1, False);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual('C:\P\Werkzeug.pas', Targets[0].FileName);
  Assert.AreEqual(4, Targets[0].SelectionRange.StartPos.Line);
  Targets := TargetsAt('Rechne;', 1, True);
  Assert.AreEqual(2, Targets[0].SelectionRange.StartPos.Line);
end;

procedure TLspDefinitionTests.UnitNameJumpsToFileStart;
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsAt('Werkzeug;', 1, False);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual('C:\P\Werkzeug.pas', Targets[0].FileName);
  Assert.AreEqual(0, Targets[0].SelectionRange.StartPos.Line);
  Assert.AreEqual(0, Targets[0].SelectionRange.StartPos.Character);
end;

procedure TLspDefinitionTests.LocalVariableAndUnknownName;
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsAt('Wert :=', 1, False);
  Assert.AreEqual(1, Integer(Length(Targets)));
  Assert.AreEqual(HauptFile, Targets[0].FileName);
  Assert.AreEqual(11, Targets[0].SelectionRange.StartPos.Line);
  Targets := TargetsAt('Unbekannt', 1, False);
  Assert.AreEqual(0, Integer(Length(Targets)));
end;

procedure TLspDefinitionTests.ParameterJumpsToItsDeclaration;
const
  Source =
    'unit Para;'#10 +                                      // 0
    'interface'#10 +                                       // 1
    'implementation'#10 +                                  // 2
    'function Doppelt(Zahl: Integer): Integer;'#10 +       // 3
    'begin'#10 +                                           // 4
    '  Result := Zahl * 2;'#10 +                           // 5
    'end;'#10 +                                            // 6
    'end.';
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsOfFile(Source, 'C:\P\Para.pas', 'Zahl * 2', 1, True);
  Assert.AreEqual(1, Integer(Length(Targets)), 'ein Ziel');
  Assert.AreEqual('C:\P\Para.pas', Targets[0].FileName);
  Assert.AreEqual(3, Targets[0].SelectionRange.StartPos.Line, 'Zeile des Parameters');
  Assert.AreEqual(17, Targets[0].SelectionRange.StartPos.Character, 'Spalte des Parameters');
end;

procedure TLspDefinitionTests.TypeNameJumpsToTypeDeclaration;
const
  Source =
    'unit Typen2;'#10 +                                    // 0
    'interface'#10 +                                       // 1
    'type'#10 +                                            // 2
    '  TBasis = class end;'#10 +                           // 3
    'var Global: TBasis;'#10 +                             // 4
    'implementation'#10 +                                  // 5
    'end.';
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsOfFile(Source, 'C:\P\Typen2.pas', 'TBasis;', 1, True);
  Assert.AreEqual(1, Integer(Length(Targets)), 'ein Ziel');
  Assert.AreEqual(3, Targets[0].SelectionRange.StartPos.Line, 'Deklaration des Typs');
end;

procedure TLspDefinitionTests.TypeDefinitionFollowsDeclaredTypes;
const
  Source =
    'unit Typen;'#10 +                       // 0
    'interface'#10 +                         // 1
    'type'#10 +                              // 2
    '  TBasis = class end;'#10 +             // 3
    '  TAlias = TBasis;'#10 +                // 4
    'var Global: TAlias;'#10 +               // 5
    'implementation'#10 +                    // 6
    'function Liefere(Zahl: Integer): TBasis;'#10 + // 7
    'begin'#10 +                             // 8
    '  Global := Liefere(Zahl);'#10 +        // 9
    'end;'#10 +                              // 10
    'end.';
var
  Tree: TSyntaxTree;
  Targets: TArray<TDefinitionTarget>;
begin
  Tree := TPascalParser.Parse(Source);
  try
    // Variable mit Alias-Typ: zum Zieltyp des Alias.
    Targets := TLspDefinition.TypeTargets(FResolver, Tree, 'C:\P\Typen.pas', PositionOf(Source, 'Global :=', 1));
    Assert.AreEqual(1, Integer(Length(Targets)));
    Assert.AreEqual(3, Targets[0].SelectionRange.StartPos.Line);
    // Funktion: zum Ergebnistyp.
    Targets := TLspDefinition.TypeTargets(FResolver, Tree, 'C:\P\Typen.pas', PositionOf(Source, 'Liefere(Zahl)', 1));
    Assert.AreEqual(1, Integer(Length(Targets)));
    Assert.AreEqual(3, Targets[0].SelectionRange.StartPos.Line);
    // Integer steht nicht im Index: kein Ziel.
    Targets := TLspDefinition.TypeTargets(FResolver, Tree, 'C:\P\Typen.pas', PositionOf(Source, 'Zahl);', 1));
    Assert.AreEqual(0, Integer(Length(Targets)));
  finally
    Tree.Free;
  end;
end;

procedure TLspDefinitionTests.FieldAfterIndexExpression;
const
  Source =
    'unit Liste;'#10 +                                     // 0
    'interface'#10 +                                       // 1
    'type'#10 +                                            // 2
    '  TPunkt = record'#10 +                               // 3
    '    X: Integer;'#10 +                                 // 4
    '  end;'#10 +                                          // 5
    '  TPunkte = array of TPunkt;'#10 +                    // 6
    'implementation'#10 +                                  // 7
    'procedure Lies(const List: TPunkte; I: Integer);'#10 + // 8
    'var'#10 +                                             // 9
    '  Wert: Integer;'#10 +                                // 10
    'begin'#10 +                                           // 11
    '  Wert := List[I].X;'#10 +                            // 12
    'end;'#10 +                                            // 13
    'end.';
var
  Targets: TArray<TDefinitionTarget>;
begin
  Targets := TargetsOfFile(Source, 'C:\P\Liste.pas', 'X;', 1, True);
  Assert.AreEqual(1, Integer(Length(Targets)), 'ein Ziel');
  Assert.AreEqual('C:\P\Liste.pas', Targets[0].FileName);
  Assert.AreEqual(4, Targets[0].SelectionRange.StartPos.Line, 'Feld X des Elementtyps');
end;

procedure TLspDefinitionTests.RoutineFromIncludeFile;
const
  IncFile = 'C:\P\Teile.inc';
  IncText = 'procedure Teil;'#10;
  MainFile = 'C:\P\MitInclude.pas';
  Source =
    'unit MitInclude;'#10 +                                // 0
    'interface'#10 +                                       // 1
    '{$I Teile.inc}'#10 +                                  // 2
    'implementation'#10 +                                  // 3
    'procedure Teil;'#10 +                                 // 4
    'begin'#10 +                                           // 5
    'end;'#10 +                                            // 6
    'procedure Nutze;'#10 +                                // 7
    'begin'#10 +                                           // 8
    '  Teil;'#10 +                                         // 9
    'end;'#10 +                                            // 10
    'end.';
var
  Tree: TSyntaxTree;
  Targets: TArray<TDefinitionTarget>;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(Source, MainFile, nil,
    function(const AName, AFromFile: string; out AFileName, AText: string): Boolean
    begin
      Result := SameText(AName, 'Teile.inc');
      AFileName := IncFile;
      AText := IncText;
    end));
  Tree := TPascalParser.Parse(Source);
  try
    // Aufruf: zur Deklaration in der Include-Datei.
    Targets := TLspDefinition.Targets(FResolver, FIndex, Tree, MainFile, PositionOf(Source, 'Teil;', 2), True);
    Assert.AreEqual(1, Integer(Length(Targets)), 'ein Ziel');
    Assert.AreEqual(IncFile, Targets[0].FileName, 'Deklaration in der Include-Datei');
    Assert.AreEqual(0, Targets[0].SelectionRange.StartPos.Line, 'Zeile in der Include-Datei');
    // Name der Implementierung: zurück zur Deklaration in der Include-Datei.
    Targets := TLspDefinition.Targets(FResolver, FIndex, Tree, MainFile, PositionOf(Source, 'Teil;', 1), False);
    Assert.AreEqual(1, Integer(Length(Targets)), 'ein Ziel von der Implementierung');
    Assert.AreEqual(IncFile, Targets[0].FileName, 'zurück in die Include-Datei');
  finally
    Tree.Free;
  end;
end;

procedure TLspDefinitionTests.InactiveBranchDeclaration;
const
  MainFile = 'C:\P\Zweige.pas';
  Source =
    'unit Zweige;'#10 +                                    // 0
    'interface'#10 +                                       // 1
    '{$IFDEF NIE}'#10 +                                    // 2
    'procedure Weg;'#10 +                                  // 3
    '{$ENDIF}'#10 +                                        // 4
    'implementation'#10 +                                  // 5
    'procedure Nutze;'#10 +                                // 6
    'begin'#10 +                                           // 7
    '  {$IFDEF NIE}'#10 +                                  // 8
    '  Weg;'#10 +                                          // 9
    '  {$ENDIF}'#10 +                                      // 10
    '  // Weg im Kommentar'#10 +                           // 11
    'end;'#10 +                                            // 12
    'end.';
var
  Tree: TSyntaxTree;
  Targets: TArray<TDefinitionTarget>;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(Source, MainFile, TArray<string>.Create('MSWINDOWS')));
  // Wie der Server: Baum ohne die nicht geltenden Zweige (Leerzeichen), Name aus dem Text des Dokuments.
  Tree := TPascalParser.Parse(TIndexExtractor.BlankInactive(Source, TArray<string>.Create('MSWINDOWS')));
  try
    // Die Namensauflösung kennt Weg nicht (nicht geltender Zweig).
    Targets := TLspDefinition.Targets(FResolver, FIndex, Tree, MainFile, PositionOf(Source, 'Weg;', 2), True);
    Assert.AreEqual(0, Integer(Length(Targets)), 'nicht aufgelöst');
    Targets := TLspDefinition.UnavailableTargets(FIndex, Tree, MainFile, Source, PositionOf(Source, 'Weg;', 2));
    Assert.AreEqual(1, Integer(Length(Targets)), 'Deklaration im Zweig');
    Assert.AreEqual(MainFile, Targets[0].FileName);
    Assert.AreEqual(3, Targets[0].SelectionRange.StartPos.Line, 'Zeile der Deklaration');
    // Im Kommentar kein Ziel.
    Targets := TLspDefinition.UnavailableTargets(FIndex, Tree, MainFile, Source,
      PositionOf(Source, 'Weg im', 1));
    Assert.AreEqual(0, Integer(Length(Targets)), 'Kommentar');
  finally
    Tree.Free;
  end;
end;

procedure TLspDefinitionTests.ColdLibraryUnitIsLoaded;
const
  Source =
    'unit Kunde;'#10 +
    'interface'#10 +
    'uses Vendor.Things;'#10 +
    'var Ding: TVendorThing;'#10 +
    'implementation'#10 +
    'end.';
var
  Targets: TArray<TDefinitionTarget>;
begin
  AddColdUnits([LibraryUnit(UnitVendorThings, VendorThingsFile)]);
  Targets := TargetsOfFile(Source, 'C:\P\Kunde.pas', 'TVendorThing;', 1, True);
  Assert.AreEqual(1, Integer(Length(Targets)), 'ein Ziel');
  Assert.AreEqual(VendorThingsFile, Targets[0].FileName, 'kalte Unit');
  Assert.AreEqual(3, Targets[0].SelectionRange.StartPos.Line, 'Zeile des Typs');
  // Unit-Name in uses: an den Anfang der kalten Unit.
  Targets := TargetsOfFile(Source, 'C:\P\Kunde.pas', 'Vendor.Things;', 1, True);
  Assert.AreEqual(1, Integer(Length(Targets)), 'Unit-Name');
  Assert.AreEqual(VendorThingsFile, Targets[0].FileName, 'Datei der Unit');
end;

procedure TLspDefinitionTests.OfficeTypeLibraryUnit;
const
  Source =
    'unit Buero;'#10 +
    'interface'#10 +
    'uses Word2010;'#10 +
    'var Word: TWordApplication;'#10 +
    'implementation'#10 +
    'end.';
var
  Targets: TArray<TDefinitionTarget>;
begin
  AddColdUnits([LibraryUnit(UnitWord, WordFile)]);
  Targets := TargetsOfFile(Source, 'C:\P\Buero.pas', 'TWordApplication;', 1, True);
  Assert.AreEqual(1, Integer(Length(Targets)), 'ein Ziel');
  Assert.AreEqual(WordFile, Targets[0].FileName, 'Typbibliothek');
  Assert.AreEqual(3, Targets[0].SelectionRange.StartPos.Line, 'Zeile des Typs');
end;

procedure TLspDefinitionTests.SameNamedUnitsFollowProject;
const
  SharedText = 'unit Shared;'#10'interface'#10'type'#10'  TShared = class end;'#10'implementation'#10'end.';
  Source =
    'unit Main2;'#10 +
    'interface'#10 +
    'uses Shared;'#10 +
    'var S: TShared;'#10 +
    'implementation'#10 +
    'end.';
var
  Targets: TArray<TDefinitionTarget>;
begin
  FIndex.AddUnit(TIndexExtractor.ExtractText(SharedText, 'C:\P1\Shared.pas', nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(SharedText, 'C:\P2\Shared.pas', nil));
  FIndex.SetUnitScopes(TFolderScopes.Create);
  try
    Targets := TargetsOfFile(Source, 'C:\P2\Main2.pas', 'TShared;', 1, True);
    Assert.AreEqual(1, Integer(Length(Targets)), 'ein Ziel');
    Assert.AreEqual('C:\P2\Shared.pas', Targets[0].FileName, 'Unit des eigenen Projekts');
    Targets := TargetsOfFile(Source, 'C:\P2\Main2.pas', 'Shared;', 1, True);
    Assert.AreEqual(1, Integer(Length(Targets)), 'Unit-Name');
    Assert.AreEqual('C:\P2\Shared.pas', Targets[0].FileName, 'Datei des eigenen Projekts');
  finally
    FIndex.SetUnitScopes(nil);
  end;
end;

procedure TLspDefinitionTests.WritesLocations;
var
  Target: TDefinitionTarget;
  Json: TJSONArray;
  Location: TJSONValue;
  Uri: string;
  Line, Character: Integer;
begin
  Target.FileName := 'C:\P\Werkzeug.pas';
  Target.Range := TTextRange.Create(TTextPosition.Create(4, 0), TTextPosition.Create(6, 4));
  Target.SelectionRange := TTextRange.Create(TTextPosition.Create(4, 10), TTextPosition.Create(4, 16));
  Json := TLspDefinition.ToJson([Target]);
  try
    Assert.AreEqual(1, Integer(Json.Count));
    // Werte erst in typisierte Variablen lesen: GetValue<T> direkt als
    // Argument von Assert.AreEqual übersetzt dcc64 (Delphi 13) nicht.
    Location := Json.Items[0];
    Uri := Location.GetValue<string>('uri');
    Line := Location.GetValue<Integer>('range.start.line');
    Character := Location.GetValue<Integer>('range.start.character');
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\Werkzeug.pas'), Uri);
    Assert.AreEqual(4, Line);
    Assert.AreEqual(10, Character);
  finally
    Json.Free;
  end;
end;

procedure TLspDefinitionTests.SkipsIdeUnits;
var
  Real, Ide: TDefinitionTarget;
  Json: TJSONArray;
  Uri: string;
begin
  Real.FileName := 'C:\P\Werkzeug.pas';
  Real.Range := TTextRange.Create(TTextPosition.Create(4, 0), TTextPosition.Create(6, 4));
  Real.SelectionRange := Real.Range;
  Ide := Real;
  Ide.FileName := TIdeUnits.PathOf('Vcl.Forms');
  Json := TLspDefinition.ToJson([Ide]);
  try
    // Ersatz-Unit der IDE allein: kein Sprungziel.
    Assert.AreEqual(0, Integer(Json.Count));
  finally
    Json.Free;
  end;
  Json := TLspDefinition.ToJson([Ide, Real]);
  try
    Assert.AreEqual(1, Integer(Json.Count));
    Uri := Json.Items[0].GetValue<string>('uri');
    Assert.AreEqual(TDocumentUris.FromPath('C:\P\Werkzeug.pas'), Uri);
  finally
    Json.Free;
  end;
end;

procedure TLspDefinitionTests.IdeUnitTypeHasNoJump;
const
  BplText = 'unit Vendor.Bpl;'#10'interface'#10'type'#10'  TBplThing = class end;'#10'implementation'#10'end.';
  Source =
    'unit NutztBpl;'#10 +
    'interface'#10 +
    'uses Vendor.Bpl;'#10 +
    'var B: TBplThing;'#10 +
    'implementation'#10 +
    'end.';
var
  Targets: TArray<TDefinitionTarget>;
  Json: TJSONArray;
begin
  // Ersatz-Unit der IDE (Package ohne Quelltext): Die Namensauflösung findet den Typ, ein Sprungziel gibt es nicht.
  FIndex.AddUnit(TIndexExtractor.ExtractText(BplText, TIdeUnits.PathOf('Vendor.Bpl'), nil));
  Targets := TargetsOfFile(Source, 'C:\P\NutztBpl.pas', 'TBplThing;', 1, True);
  Json := TLspDefinition.ToJson(Targets);
  try
    Assert.AreEqual(0, Integer(Json.Count), 'kein Sprung in die Ersatz-Unit');
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDefinitionTests);

end.
