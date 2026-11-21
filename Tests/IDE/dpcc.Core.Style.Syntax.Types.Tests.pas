unit dpcc.Core.Style.Syntax.Types.Tests;

// Tests für die Typnamen in Signaturen (LOOK1, TDpccSyntax.TypeRanges und SignatureTokens): Typ ist der Bezeichner
// direkt hinter einem Doppelpunkt bzw. hinter „of“ in „array of X“, auch qualifiziert und generisch; Schlüsselwörter,
// Standardwerte und Doppelpunkte in Strings und Kommentaren sind keine Typen. Tokens liefert die neue Art nie.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccStyleSyntaxTypesTests = class
  public
    /// <summary>string bleibt Schlüsselwort, Integer ist Typ, der Standardwert 0 ist Zahl.</summary>
    [Test]
    procedure ParametersAndResult;
    [Test]
    procedure ResultOnly;
    [Test]
    procedure StreamParameter;
    /// <summary>array of const: nur Schlüsselwörter, kein Typ.</summary>
    [Test]
    procedure ArrayOfConst;
    [Test]
    procedure ArrayOfType;
    [Test]
    procedure GenericType;
    /// <summary>TArray&lt;string&gt;: Typ mit Schlüsselwort darin; string bleibt Schlüsselwort.</summary>
    [Test]
    procedure GenericWithKeyword;
    [Test]
    procedure QualifiedType;
    /// <summary>Doppelpunkt im String-Literal beginnt keinen Typ.</summary>
    [Test]
    procedure ColonInStringLiteral;
    /// <summary>Doppelpunkt im Kommentar beginnt keinen Typ.</summary>
    [Test]
    procedure ColonInComment;
    /// <summary>Standardwert hinter „=“ ist kein Typ, auch wenn er wie ein Name aussieht.</summary>
    [Test]
    procedure DefaultValueIsNoType;
    /// <summary>Property: Typ hinter dem Doppelpunkt, read/write-Namen sind keine Typen.</summary>
    [Test]
    procedure PropertyType;
    /// <summary>Tokens (Doku, Peek) bleibt ohne Typnamen; SignatureTokens ist lückenlos.</summary>
    [Test]
    procedure TokensUnchangedAndGapless;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  dpcc.Core.Style.Syntax;

/// <summary>Texte der Typbereiche, getrennt durch „|“.</summary>
function TypesOf(const AText: string): string;
var
  mRange: TPoint;
begin
  Result := '';
  for mRange in TDpccSyntax.TypeRanges(AText) do
  begin
    if Result <> '' then
    begin
      Result := Result + '|';
    end;
    Result := Result + Copy(AText, mRange.X + 1, mRange.Y - mRange.X);
  end;
end;

/// <summary>Texte der Stücke von SignatureTokens mit der Art AKind, getrennt durch „|“.</summary>
function PiecesOf(const AText: string; AKind: TDpccTokenKind): string;
var
  mToken: TDpccToken;
begin
  Result := '';
  for mToken in TDpccSyntax.SignatureTokens(AText) do
  begin
    if mToken.Kind <> AKind then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + '|';
    end;
    Result := Result + Copy(AText, mToken.Start + 1, mToken.Stop - mToken.Start);
  end;
end;

{ TDpccStyleSyntaxTypesTests }

procedure TDpccStyleSyntaxTypesTests.ParametersAndResult;
const
  cText = '(const AFileName: string; AMaxRows: Integer = 0): Integer';
begin
  Assert.AreEqual('Integer|Integer', TypesOf(cText));
  Assert.AreEqual('Integer|Integer', PiecesOf(cText, TDpccTokenKind.TypeName));
  Assert.AreEqual('const|string', PiecesOf(cText, TDpccTokenKind.Keyword));
  Assert.AreEqual('0', PiecesOf(cText, TDpccTokenKind.Number));
end;

procedure TDpccStyleSyntaxTypesTests.ResultOnly;
begin
  Assert.AreEqual('Int64', TypesOf(': Int64'));
  Assert.AreEqual('Int64', PiecesOf(': Int64', TDpccTokenKind.TypeName));
end;

procedure TDpccStyleSyntaxTypesTests.StreamParameter;
begin
  Assert.AreEqual('TStream|Integer', TypesOf('(AStream: TStream): Integer'));
end;

procedure TDpccStyleSyntaxTypesTests.ArrayOfConst;
const
  cText = 'const Args: array of const';
begin
  Assert.AreEqual('', TypesOf(cText));
  Assert.AreEqual('', PiecesOf(cText, TDpccTokenKind.TypeName));
  Assert.AreEqual('const|array|of|const', PiecesOf(cText, TDpccTokenKind.Keyword));
end;

procedure TDpccStyleSyntaxTypesTests.ArrayOfType;
begin
  Assert.AreEqual('TStream', TypesOf('(const AItems: array of TStream)'));
  Assert.AreEqual('Integer', TypesOf('type TIntegers = array of Integer'));
  Assert.AreEqual('Byte', TypesOf('AValues: array[0..3] of Byte'));
end;

procedure TDpccStyleSyntaxTypesTests.GenericType;
begin
  Assert.AreEqual('TProc<Integer>', TypesOf('AProgress: TProc<Integer>'));
  Assert.AreEqual('TProc<Integer>', PiecesOf('AProgress: TProc<Integer>', TDpccTokenKind.TypeName));
  Assert.AreEqual('TDictionary<string, TList<Integer>>', TypesOf('(AMap: TDictionary<string, TList<Integer>>)'));
end;

procedure TDpccStyleSyntaxTypesTests.GenericWithKeyword;
const
  cText = 'function Names: TArray<string>';
begin
  Assert.AreEqual('TArray<string>', TypesOf(cText));
  Assert.AreEqual('function|string', PiecesOf(cText, TDpccTokenKind.Keyword));
  Assert.AreEqual('TArray<|>', PiecesOf(cText, TDpccTokenKind.TypeName));
end;

procedure TDpccStyleSyntaxTypesTests.QualifiedType;
begin
  Assert.AreEqual('System.Classes.TStream', TypesOf(': System.Classes.TStream'));
  Assert.AreEqual('System.Classes.TStream', PiecesOf(': System.Classes.TStream', TDpccTokenKind.TypeName));
end;

procedure TDpccStyleSyntaxTypesTests.ColonInStringLiteral;
const
  cText = '(const ASeparator: string = ''a: TFoo''; ACount: Integer)';
begin
  Assert.AreEqual('Integer', TypesOf(cText));
  Assert.AreEqual('''a: TFoo''', PiecesOf(cText, TDpccTokenKind.StringLiteral));
end;

procedure TDpccStyleSyntaxTypesTests.ColonInComment;
begin
  Assert.AreEqual('Integer', TypesOf('(A: Integer { B: TFoo } (* C: TBar *))'));
  Assert.AreEqual('Integer', TypesOf('(A: Integer) // B: TFoo'));
end;

procedure TDpccStyleSyntaxTypesTests.DefaultValueIsNoType;
begin
  Assert.AreEqual('TAlign', TypesOf('(AAlign: TAlign = TAlign.alClient)'));
  Assert.AreEqual('Integer', TypesOf('const cMax: Integer = High(Integer)'));
end;

procedure TDpccStyleSyntaxTypesTests.PropertyType;
begin
  Assert.AreEqual('Integer|TStrings', TypesOf('property Items[AIndex: Integer]: TStrings read GetItems write SetItems'));
end;

procedure TDpccStyleSyntaxTypesTests.TokensUnchangedAndGapless;
const
  cText = 'function Load(const AFileName: string; AStream: System.Classes.TStream): TArray<Integer>; overload;';
var
  mToken: TDpccToken;
  mStop: Integer;
begin
  for mToken in TDpccSyntax.Tokens(cText) do
  begin
    Assert.AreNotEqual(Ord(TDpccTokenKind.TypeName), Ord(mToken.Kind), 'Tokens ohne Typnamen');
  end;
  mStop := 0;
  for mToken in TDpccSyntax.SignatureTokens(cText) do
  begin
    Assert.AreEqual(mStop, mToken.Start, 'lückenlos');
    Assert.IsTrue(mToken.Stop > mToken.Start, 'nicht leer');
    mStop := mToken.Stop;
  end;
  Assert.AreEqual(Length(cText), mStop, 'bis zum Ende');
  Assert.AreEqual('System.Classes.TStream|TArray<Integer>', PiecesOf(cText, TDpccTokenKind.TypeName));
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccStyleSyntaxTypesTests);

end.
