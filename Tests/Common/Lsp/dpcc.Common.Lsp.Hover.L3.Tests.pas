unit dpcc.Common.Lsp.Hover.L3.Tests;

// Tests zu Auftrag L3, Punkt 8 (Hover): volle Köpfe mehrzeiliger Deklarationen, abgeleiteter Typ bei var X := …,
// Werte einfacher konstanter Ausdrücke, normale Kommentare als Doku und Deklarationen aus nicht geltenden Zweigen.
// Die Tests nutzen nur die Hover-Schnittstelle (TLspHover.InfoAt, THoverValues.ConstantValue).

interface

uses
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Lsp.Hover;

type
  [TestFixture]
  TLspHoverL3Tests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function InfoAt(const AText, AFileName, AMarker: string; AOccurrence: Integer = 1): THoverInfo;
  public
    /// <summary>Einmal vorab: einmalig angelegte Daten zählen sonst als Leck des ersten Tests.</summary>
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Kopf einer Routine über zwei Zeilen vollständig, samt Direktive.</summary>
    [Test]
    procedure ShowsMultiLineRoutineHeader;
    /// <summary>Methode in der Klasse über zwei Zeilen; die ///-Doku bleibt.</summary>
    [Test]
    procedure ShowsMultiLineMethodHeader;
    /// <summary>Konstante über zwei Zeilen: ganzer Ausdruck, Literale ohne Leerzeichen dazwischen.</summary>
    [Test]
    procedure ShowsMultiLineConstant;
    /// <summary>var F := TFoo.Create zeigt "F: TFoo", var S := 'abc' zeigt "S: string".</summary>
    [Test]
    procedure ShowsInferredTypeOfInlineVar;
    /// <summary>var T := A + IntToStr(1) zeigt "T: string" (Ausdruckstypen aus Punkt 4).</summary>
    [Test]
    procedure ShowsInferredTypeFromOperators;
    /// <summary>Werte einfacher Ausdrücke ohne Namen (THoverValues.ConstantValue).</summary>
    [Test]
    procedure EvaluatesSimpleExpressions;
    /// <summary>Werte mit Verweisen auf Konstanten der eigenen Unit und aus dem Index.</summary>
    [Test]
    procedure ShowsValuesOfConstantExpressions;
    /// <summary>Kreis und Unbekanntes liefern keinen Wert.</summary>
    [Test]
    procedure NoValueForCyclesAndUnknownNames;
    /// <summary>Klassenkonstante, deren Wert Konstanten aus Typ und Unit verwendet.</summary>
    [Test]
    procedure ShowsValueOfClassConstant;
    /// <summary>Normaler Kommentarblock darüber ({ } und //) und Kommentar am Zeilenende als Doku.</summary>
    [Test]
    procedure ShowsPlainCommentsAsDocumentation;
    /// <summary>/// hat Vorrang; Lizenzköpfe, abgetrennte Blöcke und auskommentierter Code sind keine Doku.</summary>
    [Test]
    procedure SkipsHeadersSeparatedBlocksAndCode;
    /// <summary>Deklaration aus einem nicht geltenden $IFDEF-Zweig: voller Kopf und Kommentar aus der Datei.</summary>
    [Test]
    procedure ShowsUnavailableDeclaration;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Pascal.Parser,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.Extractor,
  dpcc.Common.Lsp.HoverValues;

const
  cSystemFile = 'C:\P\System.pas';
  cSysUtilsFile = 'C:\P\SysUtils.pas';
  cWerkFile = 'C:\P\Werk.pas';
  cWerteFile = 'C:\P\Werte.pas';
  cDokuFile = 'C:\P\Doku.pas';
  cBedingtFile = 'C:\P\Bedingt.pas';
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitSystem =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TObject = class'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    procedure Free;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUnitSysUtils =
    'unit SysUtils;'#10 +
    'interface'#10 +
    'function IntToStr(Value: Integer): string;'#10 +
    'implementation'#10 +
    'end.';

  cUnitWerk =
    'unit Werk;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TRechner = class'#10 +
    '  public'#10 +
    '    /// <summary>Teilt zwei Zahlen.</summary>'#10 +
    '    function Teile(AZaehler: Integer;'#10 +
    '      ANenner: Integer): Integer; virtual;'#10 +
    '  end;'#10 +
    'function Verbinde(const A: string;'#10 +
    '  const B: string): string; stdcall;'#10 +
    'implementation'#10 +
    'function Verbinde(const A: string; const B: string): string;'#10 +
    'begin'#10 +
    '  Result := A + B;'#10 +
    'end;'#10 +
    'function TRechner.Teile(AZaehler: Integer; ANenner: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := AZaehler div ANenner;'#10 +
    'end;'#10 +
    'end.';

  cUnitWerte =
    'unit Werte;'#10 +
    'interface'#10 +
    'const'#10 +
    '  cBasis = 10;'#10 +
    '  cZeilen = ''Eins'' + #13#10 +'#10 +
    '    ''Zwei'';'#10 +
    'type'#10 +
    '  TGrenzen = class'#10 +
    '  public const'#10 +
    '    cFaktor = 3;'#10 +
    '    cMax = cBasis * cFaktor + 1;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUnitDoku =
    'unit Doku;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TGeraet = class'#10 +
    '  public'#10 +
    '    // Startet das Gerät.'#10 +
    '    // Danach ist es bereit.'#10 +
    '    procedure Starte;'#10 +
    '    procedure Stoppe; // Hält das Gerät an.'#10 +
    '    { Setzt alles zurück. }'#10 +
    '    procedure Zuruecksetzen;'#10 +
    '    /// <summary>Misst mit XMLDoc.</summary>'#10 +
    '    procedure Messe; // nicht zeigen'#10 +
    '    // Copyright (c) 2026 Beispiel GmbH, alle Rechte vorbehalten.'#10 +
    '    procedure Lizenz;'#10 +
    '    // Abschnitt: Hilfen'#10 +
    ''#10 +
    '    procedure Getrennt;'#10 +
    '    // FZaehler := 0;'#10 +
    '    // Inc(FZaehler);'#10 +
    '    procedure Pruefe;'#10 +
    '    procedure Warte; // Sleep(10);'#10 +
    '    { Private-Deklarationen }'#10 +
    '    procedure Vorlage;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUnitBedingt =
    'unit Bedingt;'#10 +
    'interface'#10 +
    '{$IFDEF NIE}'#10 +
    '// Rechnet nur unter NIE.'#10 +
    'function Nie(A: Integer;'#10 +
    '  B: Integer): Integer;'#10 +
    '{$ENDIF}'#10 +
    'implementation'#10 +
    'end.';

  cUnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses SysUtils, Werk, Werte, Doku;'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '  end;'#10 +
    'const'#10 +
    '  cDoppelt = cBasis * 2;'#10 +
    '  cMaske = (1 shl 4) or $0F;'#10 +
    '  cNegativ = -cBasis div 3;'#10 +
    '  cName = ''dpcc'';'#10 +
    '  cPfad = ''C:\'' + cName;'#10 +
    '  cRest = 17 mod 5 xor 1;'#10 +
    '  cNicht = not 0 and $FF;'#10 +
    '  cKreisA = cKreisB + 1;'#10 +
    '  cKreisB = cKreisA + 1;'#10 +
    '  cUnbekannt = High(Integer) - 1;'#10 +
    'implementation'#10 +
    'procedure Lauf(const A: string);'#10 +
    'var'#10 +
    '  R: TRechner;'#10 +
    '  G: TGeraet;'#10 +
    'begin'#10 +
    '  var F := TFoo.Create;'#10 +
    '  var S := ''abc'';'#10 +
    '  var T := A + IntToStr(1);'#10 +
    '  F.Free;'#10 +
    '  S := S + ''x'';'#10 +
    '  T := T + S;'#10 +
    '  S := Verbinde(S, T);'#10 +
    '  R.Teile(1, 2);'#10 +
    '  G.Starte;'#10 +
    '  G.Stoppe;'#10 +
    '  G.Zuruecksetzen;'#10 +
    '  G.Messe;'#10 +
    '  G.Lizenz;'#10 +
    '  G.Getrennt;'#10 +
    '  G.Pruefe;'#10 +
    '  G.Warte;'#10 +
    '  G.Vorlage;'#10 +
    '  Writeln(cDoppelt, cMaske, cNegativ, cPfad, cRest, cNicht);'#10 +
    '  Writeln(cKreisA, cUnbekannt, TGrenzen.cMax, cZeilen);'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string; AOccurrence: Integer): TTextPosition;
var
  mIndex, mFound, mRun, mLine, mLineStart: Integer;
begin
  mFound := 0;
  mIndex := 0;
  repeat
    mIndex := Pos(AMarker, AText, mIndex + 1);
    if mIndex = 0 then
    begin
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    end;
    Inc(mFound);
  until mFound = AOccurrence;
  mLine := 0;
  mLineStart := 1;
  for mRun := 1 to mIndex - 1 do
  begin
    if AText[mRun] = #10 then
    begin
      Inc(mLine);
      mLineStart := mRun + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cSystemFile) then
  begin
    AText := cUnitSystem;
  end
  else if SameText(AFileName, cSysUtilsFile) then
  begin
    AText := cUnitSysUtils;
  end
  else if SameText(AFileName, cWerkFile) then
  begin
    AText := cUnitWerk;
  end
  else if SameText(AFileName, cWerteFile) then
  begin
    AText := cUnitWerte;
  end
  else if SameText(AFileName, cDokuFile) then
  begin
    AText := cUnitDoku;
  end
  else if SameText(AFileName, cBedingtFile) then
  begin
    AText := cUnitBedingt;
  end
  else
  begin
    AText := '';
    Result := False;
  end;
end;

{ TLspHoverL3Tests }

procedure TLspHoverL3Tests.WarmUp;
begin
  Setup;
  try
    InfoAt(cUnitHaupt, cHauptFile, 'Verbinde(S');
    InfoAt(cUnitHaupt, cHauptFile, 'F.Free');
    InfoAt(cUnitHaupt, cHauptFile, 'cDoppelt,');
    InfoAt(cUnitHaupt, cHauptFile, 'Starte;');
    InfoAt(cUnitBedingt, cBedingtFile, 'Nie(');
    THoverValues.ConstantValue('cX = (1 + 2) * 3;');
  finally
    TearDown;
  end;
end;

procedure TLspHoverL3Tests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitSystem, cSystemFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitSysUtils, cSysUtilsFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitWerk, cWerkFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitWerte, cWerteFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitDoku, cDokuFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBedingt, cBedingtFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspHoverL3Tests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspHoverL3Tests.InfoAt(const AText, AFileName, AMarker: string; AOccurrence: Integer): THoverInfo;
var
  mTree: TSyntaxTree;
begin
  // Nur die aktiven Zweige, wie der Baum des Editors.
  mTree := TPascalParser.ParseActive(AText, nil);
  try
    Result := TLspHover.InfoAt(THoverSource.Create(FResolver, FIndex, ReadText), mTree, AText, AFileName,
      PositionOf(AText, AMarker, AOccurrence));
  finally
    mTree.Free;
  end;
end;

procedure TLspHoverL3Tests.ShowsMultiLineRoutineHeader;
var
  mInfo: THoverInfo;
begin
  // Vorher: nur "function Verbinde(const A: string;".
  mInfo := InfoAt(cUnitHaupt, cHauptFile, 'Verbinde(S');
  Assert.AreEqual('function Verbinde(const A: string; const B: string): string; stdcall;', mInfo.Declaration);
  Assert.AreEqual('Werk', mInfo.UnitName);
end;

procedure TLspHoverL3Tests.ShowsMultiLineMethodHeader;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt(cUnitHaupt, cHauptFile, 'Teile(1');
  Assert.AreEqual('function Teile(AZaehler: Integer; ANenner: Integer): Integer; virtual;', mInfo.Declaration);
  Assert.AreEqual('Teilt zwei Zahlen.', mInfo.Documentation);
end;

procedure TLspHoverL3Tests.ShowsMultiLineConstant;
var
  mInfo: THoverInfo;
begin
  // Vorher: nur "cZeilen = 'Eins' + #13#10 +".
  mInfo := InfoAt(cUnitHaupt, cHauptFile, 'cZeilen)');
  Assert.AreEqual('cZeilen = ''Eins'' + #13#10 + ''Zwei'';', mInfo.Declaration);
  Assert.AreEqual('''Eins⏎Zwei''', mInfo.Value);
end;

procedure TLspHoverL3Tests.ShowsInferredTypeOfInlineVar;
var
  mInfo: THoverInfo;
begin
  // Vorher: "var F := TFoo.Create;" ohne Typ.
  mInfo := InfoAt(cUnitHaupt, cHauptFile, 'F.Free');
  Assert.IsTrue(mInfo.Found);
  Assert.Contains(mInfo.Declaration, 'F: TFoo');
  Assert.Contains(mInfo.Declaration, ':= TFoo.Create');
  mInfo := InfoAt(cUnitHaupt, cHauptFile, 'S := S');
  Assert.Contains(mInfo.Declaration, 'S: string');
end;

procedure TLspHoverL3Tests.ShowsInferredTypeFromOperators;
begin
  Assert.Contains(InfoAt(cUnitHaupt, cHauptFile, 'T := T').Declaration, 'T: string');
end;

procedure TLspHoverL3Tests.EvaluatesSimpleExpressions;
begin
  Assert.AreEqual('20 · $14 · %10100', THoverValues.ConstantValue('cX = (2 + 3) * 4;'));
  Assert.AreEqual('3 · $03 · %11', THoverValues.ConstantValue('cRest = 17 mod 5 xor 1;'));
  Assert.AreEqual('255 · $FF · %11111111', THoverValues.ConstantValue('cNicht = not 0 and $FF;'));
  Assert.AreEqual('17 · $11 · %10001', THoverValues.ConstantValue('cFlags = 1 shl 4 or 1;'));
  Assert.IsTrue(THoverValues.ConstantValue('cMinus = -(4 shl 2);').StartsWith('-16 · '));
  Assert.AreEqual('''ab⏎c''', THoverValues.ConstantValue('cText = (''a'' + ''b'') + #13#10''c'';'));
  // Unbekanntes: kein Wert statt eines geratenen.
  Assert.AreEqual('', THoverValues.ConstantValue('cNull = 7 div 0;'));
  Assert.AreEqual('', THoverValues.ConstantValue('cReal = 1.5 * 2;'));
  Assert.AreEqual('', THoverValues.ConstantValue('cMix = ''a'' + 1;'));
  Assert.AreEqual('', THoverValues.ConstantValue('cName = cAnders * 2;'));
  Assert.AreEqual('', THoverValues.ConstantValue('cVergleich = 1 < 2;'));
end;

procedure TLspHoverL3Tests.ShowsValuesOfConstantExpressions;
begin
  // cBasis kommt aus Werte (Index), cName aus der eigenen Unit.
  Assert.AreEqual('20 · $14 · %10100', InfoAt(cUnitHaupt, cHauptFile, 'cDoppelt,').Value);
  Assert.AreEqual('31 · $1F · %11111', InfoAt(cUnitHaupt, cHauptFile, 'cMaske,').Value);
  Assert.IsTrue(InfoAt(cUnitHaupt, cHauptFile, 'cNegativ,').Value.StartsWith('-3 · '));
  Assert.AreEqual('''C:\dpcc''', InfoAt(cUnitHaupt, cHauptFile, 'cPfad,').Value);
  Assert.AreEqual('3 · $03 · %11', InfoAt(cUnitHaupt, cHauptFile, 'cRest,').Value);
  Assert.AreEqual('255 · $FF · %11111111', InfoAt(cUnitHaupt, cHauptFile, 'cNicht)').Value);
end;

procedure TLspHoverL3Tests.NoValueForCyclesAndUnknownNames;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt(cUnitHaupt, cHauptFile, 'cKreisA,');
  Assert.IsTrue(mInfo.Found);
  Assert.AreEqual('', mInfo.Value);
  mInfo := InfoAt(cUnitHaupt, cHauptFile, 'cUnbekannt,');
  Assert.IsTrue(mInfo.Found);
  Assert.AreEqual('', mInfo.Value);
end;

procedure TLspHoverL3Tests.ShowsValueOfClassConstant;
begin
  // cFaktor aus dem eigenen Typ, cBasis von der Unit-Ebene: 10 * 3 + 1.
  Assert.AreEqual('31 · $1F · %11111', InfoAt(cUnitHaupt, cHauptFile, 'cMax,').Value);
end;

procedure TLspHoverL3Tests.ShowsPlainCommentsAsDocumentation;
var
  mInfo: THoverInfo;
begin
  mInfo := InfoAt(cUnitHaupt, cHauptFile, 'Starte;');
  Assert.Contains(mInfo.Documentation, 'Startet das Gerät.');
  Assert.Contains(mInfo.Documentation, 'Danach ist es bereit.');
  Assert.IsFalse(mInfo.Doc.IsEmpty);
  // Kommentar am Zeilenende: Doku, nicht Teil der Deklaration.
  mInfo := InfoAt(cUnitHaupt, cHauptFile, 'Stoppe;');
  Assert.AreEqual('Hält das Gerät an.', mInfo.Documentation);
  Assert.AreEqual('procedure Stoppe;', mInfo.Declaration);
  Assert.AreEqual('Setzt alles zurück.', InfoAt(cUnitHaupt, cHauptFile, 'Zuruecksetzen;').Documentation);
end;

procedure TLspHoverL3Tests.SkipsHeadersSeparatedBlocksAndCode;
var
  mInfo: THoverInfo;
begin
  // /// geht vor; der Kommentar am Zeilenende kommt dann nicht dazu.
  mInfo := InfoAt(cUnitHaupt, cHauptFile, 'Messe;');
  Assert.AreEqual('Misst mit XMLDoc.', mInfo.Documentation);
  Assert.AreEqual('', InfoAt(cUnitHaupt, cHauptFile, 'Lizenz;').Documentation);
  Assert.AreEqual('', InfoAt(cUnitHaupt, cHauptFile, 'Getrennt;').Documentation);
  Assert.AreEqual('', InfoAt(cUnitHaupt, cHauptFile, 'Pruefe;').Documentation);
  mInfo := InfoAt(cUnitHaupt, cHauptFile, 'Warte;');
  Assert.AreEqual('', mInfo.Documentation);
  Assert.IsTrue(mInfo.Doc.IsEmpty);
  // Hinweis der Formularvorlage gehört zum Abschnitt, nicht zum ersten Mitglied (L3).
  Assert.AreEqual('', InfoAt(cUnitHaupt, cHauptFile, 'Vorlage;').Documentation);
end;

procedure TLspHoverL3Tests.ShowsUnavailableDeclaration;
var
  mInfo: THoverInfo;
begin
  // Vorher: kein Hover, die Namensauflösung kennt die Deklaration nicht.
  mInfo := InfoAt(cUnitBedingt, cBedingtFile, 'Nie(');
  Assert.AreEqual('function Nie(A: Integer; B: Integer): Integer;', mInfo.Declaration);
  Assert.Contains(mInfo.Documentation, 'Rechnet nur unter NIE.');
  Assert.Contains(mInfo.Deprecation, 'NIE');
  Assert.AreEqual(4, mInfo.Line);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspHoverL3Tests);

end.
