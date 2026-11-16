unit dpcc.Common.Lsp.Hover.Parts.Tests;

// Tests der Teile des Hovers einzeln: Inhalt und Darstellungen (Hover.Info) und das Sammeln an einer Stelle
// (Hover.Lookup). Das Verhalten von textDocument/hover prüft dpcc.Common.Lsp.Hover.Tests.

interface

uses
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract,
  dpcc.Common.Semantics.NameResolver;

type
  [TestFixture]
  THoverPartsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure InfoFoundOnlyWithDeclaration;
    [Test]
    procedure InfoRendersDeclarationInEveryForm;
    [Test]
    procedure LookupFindsLocalDeclaration;
    /// <summary>S3: Der Hover nennt den Typ der Deklaration (container) für die Herkunft „Unit.Typ“.</summary>
    [Test]
    procedure LookupNamesContainer;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Pascal.TreeCache,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.Extractor,
  dpcc.Common.Lsp.Hover.Info,
  dpcc.Common.Lsp.Hover.Lookup;

const
  cFile = 'C:\P\Teile.pas';
  cUnit =
    'unit Teile;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure Probe;'#10 +
    'var'#10 +
    '  Anzahl: Integer;'#10 +
    'begin'#10 +
    '  Anzahl := 1;'#10 +
    'end;'#10 +
    'end.';

function ReadNothing(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

{ THoverPartsTests }

procedure THoverPartsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnit, cFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure THoverPartsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

procedure THoverPartsTests.InfoFoundOnlyWithDeclaration;
var
  mInfo: THoverInfo;
begin
  mInfo := Default(THoverInfo);
  Assert.IsFalse(mInfo.Found);
  mInfo.Declaration := 'Anzahl: Integer;';
  Assert.IsTrue(mInfo.Found);
end;

procedure THoverPartsTests.InfoRendersDeclarationInEveryForm;
var
  mInfo: THoverInfo;
  mJson: TJSONObject;
begin
  mInfo := Default(THoverInfo);
  mInfo.Declaration := 'Anzahl: Integer;';
  Assert.IsTrue(Pos('Anzahl: Integer;', mInfo.ToMarkdown) > 0, mInfo.ToMarkdown);
  Assert.IsTrue(Pos('Anzahl: Integer;', mInfo.ToPlainText) > 0, mInfo.ToPlainText);
  mJson := mInfo.ToDpccJson;
  try
    Assert.AreEqual('Anzahl: Integer;', mJson.GetValue<string>('declaration'));
    // Ohne Typ kein Feld container.
    Assert.IsNull(mJson.GetValue('container'));
  finally
    mJson.Free;
  end;
end;

procedure THoverPartsTests.LookupFindsLocalDeclaration;
var
  mTree: TSyntaxTree;
  mInfo: THoverInfo;
begin
  mTree := TSyntaxTreeCache.Parse(cUnit);
  try
    mInfo := TLspHoverLookup.InfoAt(THoverSource.Create(FResolver, FIndex, ReadNothing), mTree, cUnit, cFile,
      TTextPosition.Create(7, 3), '');
  finally
    mTree.Free;
  end;
  Assert.IsTrue(mInfo.Found);
  Assert.AreEqual('Anzahl: Integer;', mInfo.Declaration);
end;

procedure THoverPartsTests.LookupNamesContainer;
const
  cClassFile = 'C:\P\Rechner.pas';
  cClassUnit =
    'unit Rechner;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TRechner = class'#10 +
    '  public'#10 +
    '    function Summe(A, B: Integer): Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TRechner.Summe(A, B: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A + B;'#10 +
    'end;'#10 +
    'end.';
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mInfo: THoverInfo;
  mJson: TJSONObject;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cClassUnit, cClassFile, nil));
  mResolver := TNameResolver.Create(mIndex);
  try
    mTree := TSyntaxTreeCache.Parse(cClassUnit);
    try
      // Auf „Summe“ in der Klassendeklaration.
      mInfo := TLspHoverLookup.InfoAt(THoverSource.Create(mResolver, mIndex, ReadNothing), mTree, cClassUnit,
        cClassFile, TTextPosition.Create(5, 15), '');
    finally
      mTree.Free;
    end;
  finally
    mResolver.Free;
  end;
  Assert.IsTrue(mInfo.Found);
  Assert.AreEqual('TRechner', mInfo.Container);
  mJson := mInfo.ToDpccJson;
  try
    Assert.AreEqual('TRechner', mJson.GetValue<string>('container', ''));
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(THoverPartsTests);

end.
