unit dpcc.Core.Hover.Contract.Tests;

// Tests für den Inhalt der Hover-Antwort (#442, #588, #654, #110): Teile aus "dpcc", Rückfall auf Klartext,
// gekürzte Vererbungskette, Titel und Fundort, strukturierte Doku und published-Mitglieder. Seit S3b wieder im
// Testprojekt (Typverweise, Neuzuweisung und Verlauf liest bzw. hat der
// schlichte Tooltip nicht mehr).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccHoverContractTests = class
  public
    [Test]
    procedure ReadsDpccParts;
    [Test]
    procedure FallsBackToPlainText;
    [Test]
    procedure ShortensLongChains;
    [Test]
    procedure TitleAndLocation;
    [Test]
    procedure ClassReferenceTitleIsOwnName;
    [Test]
    procedure ReadsStructuredDocumentation;
    /// <summary>#1123: Nur Begründungen strukturiert; die Doku als Klartext bleibt davor.</summary>
    [Test]
    procedure KeepsPlainDocumentationBeforeRationale;
    /// <summary>#1921: Über einem Unit-Namen bleibt der Dateipfad vor dem Inhalt der Unit stehen.</summary>
    [Test]
    procedure KeepsPathBeforeUnitContents;
    /// <summary>#110: dpcc.published und die Filter.</summary>
    [Test]
    procedure ReadsPublishedMembers;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  dpcc.Core.Documentation.Contract,
  dpcc.Core.Hover.Contract;

const
  // TGalleryFrameClass = class of TBFrame; TBFrame = class(TFrame) in Gallery.Types.pas.
  cHoverJson =
    '{"contents": "TBFrame = class(TFrame)", "dpcc": {' +
    '"declaration": "TBFrame = class(TFrame)", "unit": "Gallery.Types", "documentation": "Basis aller Seiten.",' +
    '"kind": "class", "origin": "VCL", "value": "", "file": "C:\\P\\Gallery.Types.pas", "line": 19, ' +
    '"character": 2, "chainOf": "TBFrame", "ancestors": [' +
    '{"name": "TBFrame", "file": "C:\\P\\Gallery.Types.pas", "line": 19, "character": 2},' +
    '{"name": "TFrame", "file": "C:\\RTL\\Vcl.Forms.pas", "line": 500, "character": 2},' +
    '{"name": "TObject", "unit": "System", "file": "C:\\RTL\\System.pas", "line": 10, "character": 2}]}}';

function Parse(const AJson: string): TDpccHoverData;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TDpccHoverData.FromHover(mValue);
  finally
    mValue.Free;
  end;
end;

function Ref(const AName: string; ALine: Integer): TDpccHoverTypeRef;
begin
  Result := Default(TDpccHoverTypeRef);
  Result.Name := AName;
  Result.FileName := 'C:\P\Typen.pas';
  Result.Line := ALine;
end;

{ TDpccHoverContractTests }

procedure TDpccHoverContractTests.ReadsDpccParts;
var
  mData: TDpccHoverData;
begin
  mData := Parse(cHoverJson);
  Assert.IsTrue(mData.Found);
  Assert.AreEqual('TBFrame = class(TFrame)', mData.Declaration);
  Assert.AreEqual('Gallery.Types', mData.UnitName);
  Assert.AreEqual('Basis aller Seiten.', mData.Documentation);
  Assert.AreEqual('class', mData.Kind);
  Assert.AreEqual('VCL', mData.Origin);
  Assert.AreEqual('C:\P\Gallery.Types.pas', mData.Location.FileName);
  Assert.AreEqual(19, mData.Location.Line);
  Assert.AreEqual('TBFrame', mData.Location.Name, 'aus dem ersten Kettenglied');
  Assert.AreEqual('TBFrame', mData.ChainOf);
  Assert.AreEqual(3, Integer(Length(mData.Ancestors)));
  Assert.AreEqual('System', mData.Ancestors[2].UnitName);
  // Wert, Veraltung und Typ, in dem die Deklaration steht.
  mData := Parse('{"dpcc": {"declaration": "cMax = 48;", "kind": "constant", "value": "48", ' +
    '"deprecation": "Veraltet: cGrenze nehmen", "container": "TFoo"}}');
  Assert.AreEqual('48', mData.Value);
  Assert.AreEqual('Veraltet: cGrenze nehmen', mData.Deprecation);
  Assert.AreEqual('TFoo', mData.Container);
end;

procedure TDpccHoverContractTests.FallsBackToPlainText;
var
  mData: TDpccHoverData;
begin
  mData := Parse('{"contents": {"kind": "markdown", "value": "```pascal\nprocedure Lauf;\n```\n\nStartet."}}');
  Assert.AreEqual('procedure Lauf;', mData.Declaration);
  Assert.AreEqual('Startet.', mData.Documentation);
  Assert.IsFalse(mData.Location.HasLocation);
  Assert.IsFalse(TDpccHoverData.FromHover(nil).Found);
end;

procedure TDpccHoverContractTests.ShortensLongChains;
var
  mData: TDpccHoverData;
  mIndex: Integer;
  mChain: TArray<Integer>;
begin
  mData := Default(TDpccHoverData);
  for mIndex := 0 to 4 do
  begin
    mData.Ancestors := mData.Ancestors + [Ref('T' + IntToStr(mIndex), mIndex)];
  end;
  Assert.AreEqual(5, Integer(Length(mData.VisibleChain)), 'fünf Glieder ganz');
  mData.Ancestors := mData.Ancestors + [Ref('T5', 5), Ref('TObject', 6)];
  mChain := mData.VisibleChain;
  // Die ersten vier, dann "…", dann das letzte.
  Assert.AreEqual(6, Integer(Length(mChain)));
  Assert.AreEqual(0, mChain[0]);
  Assert.AreEqual(3, mChain[3]);
  Assert.AreEqual(-1, mChain[4]);
  Assert.AreEqual(6, mChain[5]);
end;

procedure TDpccHoverContractTests.TitleAndLocation;
var
  mData: TDpccHoverData;
begin
  mData := Parse(cHoverJson);
  Assert.AreEqual('TBFrame', mData.Title);
  Assert.AreEqual('Gallery.Types.pas : 20', mData.LocationText);
  mData := Default(TDpccHoverData);
  mData.Declaration := 'procedure Lauf(A: Integer);';
  mData.Kind := 'routine';
  mData.UnitName := 'Haupt';
  Assert.AreEqual('Lauf', mData.Title);
  Assert.AreEqual('Haupt', mData.LocationText, 'ohne Fundort die Unit');
end;

procedure TDpccHoverContractTests.ClassReferenceTitleIsOwnName;
var
  mData: TDpccHoverData;
begin
  mData := Default(TDpccHoverData);
  mData.Declaration := 'TGalleryFrameClass = class of TBFrame;';
  mData.Kind := TDpccHoverData.cKindClassRef;
  mData.ChainOf := 'TBFrame';
  mData.Ancestors := [Ref('TBFrame', 19), Ref('TObject', 10)];
  // Die Kette gehört zum Zieltyp, der Titel ist die Klassenreferenz selbst.
  Assert.AreEqual('TGalleryFrameClass', mData.Title);
end;

procedure TDpccHoverContractTests.ReadsStructuredDocumentation;
var
  mData: TDpccHoverData;
begin
  // #654: documentation als Abschnitte, Klartext in documentationText, Anzeige in xmlDoc.
  mData := Parse('{"contents": "x", "dpcc": {"declaration": "constructor Create(AOwner: TComponent);",' +
    '"documentationText": "Legt an.\nAOwner: Besitzer", "documentation": {"sections": [' +
    '{"kind": "summary", "runs": [{"kind": "text", "text": "Legt an."}]},' +
    '{"kind": "param", "name": "AOwner", "runs": [{"kind": "text", "text": "Besitzer"}]}]},' +
    '"xmlDoc": {"expand": "collapsed", "maxLines": 8}}}');
  Assert.AreEqual('Legt an.'#10'AOwner: Besitzer', mData.Documentation);
  Assert.AreEqual(2, Integer(Length(mData.Doc.Sections)));
  Assert.AreEqual('AOwner', mData.Doc.Sections[1].Name);
  Assert.IsTrue(mData.Display.Known);
  Assert.AreEqual(Ord(TDpccDocExpand.Collapsed), Ord(mData.Display.Expand));
  Assert.AreEqual(8, mData.Display.MaxLines);
  // Ältere Server: documentation als Text, keine Anzeige-Angabe.
  mData := Parse(cHoverJson);
  Assert.IsTrue(mData.Doc.IsEmpty);
  Assert.IsFalse(mData.Display.Known);
end;

procedure TDpccHoverContractTests.KeepsPlainDocumentationBeforeRationale;
var
  mData: TDpccHoverData;
begin
  mData := Parse('{"contents": "x", "dpcc": {"declaration": "var Zaehler: Integer;",' +
    '"documentationText": "Zaehlt.", "documentation": {"sections": [' +
    '{"kind": "rationale", "name": "WHY", "runs": [{"kind": "text", "text": "Schnell."}]}]}}}');
  Assert.AreEqual(2, Integer(Length(mData.Doc.Sections)));
  Assert.AreEqual(Ord(TDpccDocSectionKind.Summary), Ord(mData.Doc.Sections[0].Kind));
  Assert.AreEqual('Zaehlt.', mData.Doc.Sections[0].Text);
  Assert.AreEqual(Ord(TDpccDocSectionKind.Rationale), Ord(mData.Doc.Sections[1].Kind));
end;

procedure TDpccHoverContractTests.KeepsPathBeforeUnitContents;
var
  mData: TDpccHoverData;
begin
  mData := Parse('{"contents": "x", "dpcc": {"declaration": "unit Werk;",' +
    '"documentationText": "C:\\P\\Werk.pas", "documentation": {"sections": [' +
    '{"kind": "unitContents", "heading": "TYPEN (1)", "name": "Klassen", "runs": [' +
    '{"kind": "ref", "text": "TKunde", "target": "TKunde", "file": "C:\\P\\Werk.pas", "line": 3}]}]}}}');
  Assert.AreEqual(2, Integer(Length(mData.Doc.Sections)));
  Assert.AreEqual('C:\P\Werk.pas', mData.Doc.Sections[0].Text);
  Assert.AreEqual(Ord(TDpccDocSectionKind.UnitContents), Ord(mData.Doc.Sections[1].Kind));
  Assert.AreEqual('TYPEN (1)', mData.Doc.Sections[1].Heading);
  Assert.AreEqual('Klassen', mData.Doc.Sections[1].Name);
  Assert.AreEqual(3, mData.Doc.Sections[1].Runs[0].Location.Line);
end;

procedure TDpccHoverContractTests.ReadsPublishedMembers;
var
  mData: TDpccHoverData;
begin
  mData := Parse('{"contents": "x", "dpcc": {"declaration": "TKnopf = class(TBasis)", "file": "C:\\P\\K.pas",' +
    '"line": 3, "character": 2, "ancestors": [{"name": "TKnopf", "file": "C:\\P\\K.pas", "line": 3,' +
    '"character": 2}], "published": {"defaultProperty": "Items[I: Integer]: string", "members": [' +
    '{"name": "Aktiv", "type": "Boolean", "default": "False", "defaultKind": "implicit", "declaringClass": "TKnopf"},' +
    '{"name": "Titel", "type": "string", "stored": "False", "declaringClass": "TBasis"},' +
    '{"name": "Zahl", "type": "Integer", "defaultKind": "nodefault", "declaringClass": "TBasis"},' +
    '{"name": "OnKlick", "type": "TKlickEvent", "declaringClass": "TBasis", "event": true}]}}}');
  Assert.AreEqual(4, Integer(Length(mData.Members)));
  Assert.AreEqual('Items[I: Integer]: string', mData.DefaultProperty);
  Assert.IsTrue(mData.Members[0].DefaultKind = hdImplicit);
  Assert.IsTrue(mData.Members[2].DefaultKind = hdNoDefault);
  Assert.IsTrue(mData.Members[3].IsEvent);
  Assert.AreEqual(3, mData.MemberCount(False));
  Assert.AreEqual(1, mData.MemberCount(True));
  Assert.AreEqual('False (implizit)', mData.Members[0].DefaultText('implizit'));
  Assert.AreEqual('stored False', mData.Members[1].DefaultText('implizit'));
  // Eigene (TKnopf) bzw. nur mit Vorgabe.
  Assert.AreEqual(1, Integer(Length(mData.VisibleMembers(False, False, False))));
  Assert.AreEqual(1, Integer(Length(mData.VisibleMembers(False, True, True))));
  Assert.AreEqual(0, Integer(Length(mData.VisibleMembers(True, False, False))));
  Assert.IsTrue(Parse(cHoverJson).Members = nil);
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccHoverContractTests);

end.
