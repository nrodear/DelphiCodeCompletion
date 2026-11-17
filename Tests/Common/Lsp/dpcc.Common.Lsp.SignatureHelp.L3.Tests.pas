unit dpcc.Common.Lsp.SignatureHelp.L3.Tests;

// Parameterhilfe, Auftrag L3 Punkt 7: Überladungen aus Vorfahren, Prozedurtypen (of object, reference to, generisch),
// Typargumente vor der Klammer, Index-Properties und Argumenttypen aus Ausdrücken.

interface

uses
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Lsp.SignatureHelp;

type
  [TestFixture]
  TLspSignatureHelpL3Tests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function HelpAt(const ACode, AMarker: string): TSignatureHelp;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>overload in der Ableitung macht die geerbten Überladungen sichtbar.</summary>
    [Test]
    procedure InheritedOverloadsAreListed;
    /// <summary>Ohne overload verdeckt die Ableitung die Methode des Vorfahren.</summary>
    [Test]
    procedure HidingMethodStaysAlone;
    /// <summary>FOnChange(Self, … über Feld, Property und Feld mit anonymem Prozedurtyp.</summary>
    [Test]
    procedure MethodPointerShowsItsType;
    /// <summary>reference to, generisch: TAktion&lt;Integer&gt;, TPruefung&lt;string, Boolean&gt;.</summary>
    [Test]
    procedure GenericReferenceShowsBoundType;
    /// <summary>Wandle&lt;Integer&gt;(: nur die generische Überladung, Typargument eingesetzt.</summary>
    [Test]
    procedure TypeArgumentsBeforeParenthesis;
    /// <summary>Liste.Werte[ und Liste[ (default-Property) außerhalb eines Aufrufs.</summary>
    [Test]
    procedure IndexPropertyShowsIndexParameters;
    /// <summary>[ in einem Aufruf: der Aufruf bleibt; [ an einem Array ohne Aufruf: keine Hilfe.</summary>
    [Test]
    procedure ArrayIndexKeepsOuterCall;
    /// <summary>Aufruf und Indexzugriff als Argument wählen die Überladung über ihren Typ.</summary>
    [Test]
    procedure ExpressionArgumentsPickOverload;
    /// <summary>Operator im Argument: Typ aus der Namensauflösung (Ausdruckstypen, L3 Punkt 4).</summary>
    [Test]
    procedure OperatorArgumentPicksOverload;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Pascal.Parser,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.Extractor;

const
  HauptFile = 'C:\P\Haupt.pas';
  BasisFile = 'C:\P\Basis.pas';

  UnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TMeldung = procedure(Sender: TObject; Code: Integer) of object;'#10 +
    '  TAktion<T> = reference to procedure(Wert: T);'#10 +
    '  TPruefung<T, TErgebnis> = reference to function(Wert: T): TErgebnis;'#10 +
    '  TBasis = class'#10 +
    '  public'#10 +
    '    procedure Add(A: Integer); overload;'#10 +
    '  end;'#10 +
    '  TAbgeleitet = class(TBasis)'#10 +
    '  public'#10 +
    '    procedure Add(const S: string); overload;'#10 +
    '  end;'#10 +
    '  TVerdeckt = class(TBasis)'#10 +
    '  public'#10 +
    '    procedure Add(const S: string);'#10 +
    '  end;'#10 +
    '  TListe = class'#10 +
    '  private'#10 +
    '    function GetItem(Index: Integer): string;'#10 +
    '    function GetWert(const Name: string; Nr: Integer): Integer;'#10 +
    '  public'#10 +
    '    property Items[Index: Integer]: string read GetItem; default;'#10 +
    '    property Werte[const Name: string; Nr: Integer]: Integer read GetWert;'#10 +
    '  end;'#10 +
    '  TWerkzeug = class'#10 +
    '  public'#10 +
    '    function Wandle<T>(const Wert: T): T; overload;'#10 +
    '    function Wandle(const Text: string): string; overload;'#10 +
    '  end;'#10 +
    'procedure Waehle(Zahl: Integer); overload;'#10 +
    'procedure Waehle(const S: string); overload;'#10 +
    'procedure Nimm(const S: string); overload;'#10 +
    'procedure Nimm(Zahl: Integer); overload;'#10 +
    'function Liefere(A: Integer): string;'#10 +
    'implementation'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    FMeldung: TMeldung;'#10 +
    '    FRoh: procedure(A: Integer) of object;'#10 +
    '    FListe: TListe;'#10 +
    '    FZahlen: array of Integer;'#10 +
    '    FAbgeleitet: TAbgeleitet;'#10 +
    '    FVerdeckt: TVerdeckt;'#10 +
    '    FWerkzeug: TWerkzeug;'#10 +
    '    property OnMeldung: TMeldung read FMeldung write FMeldung;'#10 +
    '    procedure Bar(Anzahl: Integer; const Aktion: TAktion<Integer>;'#10 +
    '      const Pruefe: TPruefung<string, Boolean>);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar(Anzahl: Integer; const Aktion: TAktion<Integer>;'#10 +
    '  const Pruefe: TPruefung<string, Boolean>);'#10 +
    'begin'#10 +
    '  |'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  Index, Line, LineStart, Scan: Integer;
begin
  // Cursor hinter AMarker.
  Index := Pos(AMarker, AText);
  if Index = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  Inc(Index, Length(AMarker));
  Line := 0;
  LineStart := 1;
  for Scan := 1 to Index - 1 do
  begin
    if AText[Scan] = #10 then
    begin
      Inc(Line);
      LineStart := Scan + 1;
    end;
  end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

function ReadBasis(const AFileName: string; out AText: string): Boolean;
begin
  AText := UnitBasis;
  Result := SameText(AFileName, BasisFile);
end;

{ TLspSignatureHelpL3Tests }

procedure TLspSignatureHelpL3Tests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspSignatureHelpL3Tests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspSignatureHelpL3Tests.HelpAt(const ACode, AMarker: string): TSignatureHelp;
var
  Text: string;
  Tree: TSyntaxTree;
begin
  Text := StringReplace(UnitHaupt, '  |', ACode, []);
  Tree := TPascalParser.Parse(Text);
  try
    Result := TLspSignatureHelp.HelpAt(TSignatureHelpRequest.Create(FResolver, FIndex, Tree, Text, HauptFile,
      ReadBasis), PositionOf(Text, AMarker));
  finally
    Tree.Free;
  end;
end;

procedure TLspSignatureHelpL3Tests.InheritedOverloadsAreListed;
var
  Help: TSignatureHelp;
begin
  Help := HelpAt('  FAbgeleitet.Add(', 'FAbgeleitet.Add(');
  Assert.AreEqual(2, Integer(Length(Help.Signatures)), 'eigene und geerbte Überladung');
  Assert.AreEqual('procedure Add(const S: string)', Help.Signatures[0].Text);
  Assert.AreEqual('procedure Add(A: Integer)', Help.Signatures[1].Text);
  // Die Ganzzahl wählt die geerbte; die Reihenfolge bleibt (Ableitung zuerst), auch wenn die Auflösung die geerbte
  // Überladung trifft.
  Help := HelpAt('  FAbgeleitet.Add(5', 'FAbgeleitet.Add(5');
  Assert.AreEqual(2, Integer(Length(Help.Signatures)));
  Assert.AreEqual('procedure Add(const S: string)', Help.Signatures[0].Text);
  Assert.IsFalse(Help.Signatures[0].Fits);
  Assert.AreEqual(1, Help.ActiveSignature);
end;

procedure TLspSignatureHelpL3Tests.HidingMethodStaysAlone;
var
  Help: TSignatureHelp;
begin
  Help := HelpAt('  FVerdeckt.Add(', 'FVerdeckt.Add(');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.AreEqual('procedure Add(const S: string)', Help.Signatures[0].Text);
end;

procedure TLspSignatureHelpL3Tests.MethodPointerShowsItsType;
var
  Help: TSignatureHelp;
begin
  Help := HelpAt('  FMeldung(Self, ', 'FMeldung(Self, ');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.AreEqual('TMeldung = procedure(Sender: TObject; Code: Integer) of object', Help.Signatures[0].Text);
  Assert.AreEqual(2, Integer(Length(Help.Signatures[0].Parameters)));
  Assert.AreEqual('Integer', Help.Signatures[0].Parameters[1].TypeName);
  Assert.AreEqual(1, Help.ActiveParameter);
  // Über die Property.
  Help := HelpAt('  OnMeldung(', 'OnMeldung(');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.AreEqual('TMeldung = procedure(Sender: TObject; Code: Integer) of object', Help.Signatures[0].Text);
  // Feld mit anonymem Prozedurtyp.
  Help := HelpAt('  FRoh(', 'FRoh(');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.IsTrue(Help.Signatures[0].Text.Contains('procedure(A: Integer)'), Help.Signatures[0].Text);
  Assert.AreEqual(1, Integer(Length(Help.Signatures[0].Parameters)));
  Assert.AreEqual('Integer', Help.Signatures[0].Parameters[0].TypeName);
end;

procedure TLspSignatureHelpL3Tests.GenericReferenceShowsBoundType;
var
  Help: TSignatureHelp;
begin
  Help := HelpAt('  Aktion(', 'Aktion(');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.AreEqual('TAktion<Integer> = reference to procedure(Wert: Integer)', Help.Signatures[0].Text);
  Assert.AreEqual('Integer', Help.Signatures[0].Parameters[0].TypeName);
  Help := HelpAt('  Pruefe(''a''', 'Pruefe(''a''');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.AreEqual('TPruefung<string, Boolean> = reference to function(Wert: string): Boolean',
    Help.Signatures[0].Text);
  Assert.IsTrue(Help.Signatures[0].Fits, 'Zeichen an string');
end;

procedure TLspSignatureHelpL3Tests.TypeArgumentsBeforeParenthesis;
var
  Help: TSignatureHelp;
begin
  Help := HelpAt('  FWerkzeug.Wandle<Integer>(', 'Wandle<Integer>(');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)), 'nur die generische Überladung');
  Assert.AreEqual('function Wandle<Integer>(const Wert: Integer): Integer', Help.Signatures[0].Text);
  Assert.AreEqual(0, Help.ActiveParameter);
end;

procedure TLspSignatureHelpL3Tests.IndexPropertyShowsIndexParameters;
var
  Help: TSignatureHelp;
begin
  Help := HelpAt('  FListe.Werte[', 'FListe.Werte[');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.AreEqual('property Werte[const Name: string; Nr: Integer]: Integer', Help.Signatures[0].Text);
  Assert.AreEqual(2, Integer(Length(Help.Signatures[0].Parameters)));
  Assert.AreEqual(0, Help.ActiveParameter);
  Help := HelpAt('  Anzahl := FListe.Werte[''a'', 2];', 'FListe.Werte[''a'', ');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.AreEqual(1, Help.ActiveParameter);
  Assert.IsTrue(Help.Signatures[0].Fits);
  // default-Property.
  Help := HelpAt('  if FListe[1] = '''' then;', 'FListe[');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.AreEqual('property Items[Index: Integer]: string', Help.Signatures[0].Text);
end;

procedure TLspSignatureHelpL3Tests.ArrayIndexKeepsOuterCall;
var
  Help: TSignatureHelp;
begin
  // In einem Aufruf gilt der Aufruf, wie beim Parameter-Hint der IDE: auch bei einer Index-Property.
  Help := HelpAt('  Nimm(FZahlen[', 'Nimm(FZahlen[');
  Assert.AreEqual(2, Integer(Length(Help.Signatures)));
  Assert.AreEqual('procedure Nimm(const S: string)', Help.Signatures[0].Text);
  Assert.AreEqual(0, Help.ActiveParameter);
  Help := HelpAt('  Nimm(FListe[', 'Nimm(FListe[');
  Assert.AreEqual(2, Integer(Length(Help.Signatures)));
  // Ein Array ist keine Index-Property: ohne Aufruf drumherum keine Hilfe.
  Assert.IsFalse(HelpAt('  Anzahl := FZahlen[', 'FZahlen[').Found);
end;

procedure TLspSignatureHelpL3Tests.ExpressionArgumentsPickOverload;
var
  Help: TSignatureHelp;
begin
  // Funktionsaufruf als Argument: Liefere ergibt string.
  Help := HelpAt('  Waehle(Liefere(1));', 'Waehle(Liefere(1)');
  Assert.AreEqual(2, Integer(Length(Help.Signatures)));
  Assert.IsFalse(Help.Signatures[0].Fits, 'string an Integer');
  Assert.IsTrue(Help.Signatures[1].Fits);
  Assert.AreEqual(1, Help.ActiveSignature);
  // default-Property als Argument: FListe[1] ist ein string.
  Help := HelpAt('  Waehle(FListe[1]);', 'Waehle(FListe[1]');
  Assert.AreEqual(1, Help.ActiveSignature);
end;

procedure TLspSignatureHelpL3Tests.OperatorArgumentPicksOverload;
var
  Help: TSignatureHelp;
begin
  // Anzahl + 1 ist eine Ganzzahl: die zweite Überladung.
  Help := HelpAt('  Nimm(Anzahl + 1);', 'Nimm(Anzahl + 1');
  Assert.AreEqual(2, Integer(Length(Help.Signatures)));
  Assert.IsFalse(Help.Signatures[0].Fits, 'Ganzzahl an string');
  Assert.AreEqual(1, Help.ActiveSignature);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSignatureHelpL3Tests);

end.
