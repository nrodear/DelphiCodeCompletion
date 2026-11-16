unit dpcc.Core.Style.Look.Tests;

// Tests für den schlichten Look aller dpcc-Fenster (S8): Die Art-Kennung („unit“, „procedure“, „type“) steht in
// Hover und Vervollständigungsliste gedämpft wie der übrige Nebentext, nicht in der Farbe der reservierten Wörter;
// paramref in der XMLDoc ist schlicht (Editorschrift fett in der Farbe des Absatzes) statt einer Pille.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccStyleLookTests = class
  public
    /// <summary>KindLabel = Muted in hell, dunkel und in den Farben des Editors (ForWindow), nie Keyword.</summary>
    [Test]
    procedure KindLabelIsMuted;
    /// <summary>paramref: Editorschrift fett, Textfarbe des Absatzes, ohne Innenabstand; Nachbarn schließen an.
    /// </summary>
    [Test]
    procedure ParamRefIsPlainBold;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette,
  dpcc.Core.Documentation.Contract,
  dpcc.Core.Documentation.Layout,
  dpcc.Core.Documentation.Typeset;

function Measure(const AText: string; const AFace: TDpccDocFace): Integer;
begin
  if AFace.Font = TDpccDocFont.Mono then
  begin
    Result := 8 * Length(AText);
  end
  else
  begin
    Result := 7 * Length(AText);
  end;
end;

function DocOf(const AJson: string): TDpccDoc;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TDpccDoc.FromJson(mValue);
  finally
    mValue.Free;
  end;
end;

procedure CheckKind(const AColors: TDpccColors; const AName: string);
begin
  Assert.AreEqual(Integer(AColors.Muted), Integer(AColors.KindLabel), AName + ': gedämpft');
  Assert.AreNotEqual(Integer(AColors.Keyword), Integer(AColors.KindLabel), AName + ': nicht Keyword');
end;

procedure TDpccStyleLookTests.KindLabelIsMuted;
begin
  CheckKind(TDpccColors.Light, 'hell');
  CheckKind(TDpccColors.Dark, 'dunkel');
  CheckKind(TDpccColors.ForWindow(TDpccColorMath.FromHex('#FFFFFF'), TDpccColorMath.FromHex('#000000')),
    'Editor hell');
  CheckKind(TDpccColors.ForWindow(TDpccColorMath.FromHex('#1E1E1E'), TDpccColorMath.FromHex('#D4D4D4')),
    'Editor dunkel');
end;

procedure TDpccStyleLookTests.ParamRefIsPlainBold;
var
  mLayout: TDpccDocLayout;
  mSpans: TArray<TDpccDocSpan>;
  mIndex, mFound: Integer;
begin
  mLayout := TDpccDocTypeset.Build(DocOf('{"sections":[{"kind":"summary","runs":[{"kind":"text","text":"Setzt "},' +
    '{"kind":"paramref","text":"AValue"},{"kind":"text","text":" neu."}]}]}'), 400,
    TDpccDocMetrics.Create(16, 17, 1), Measure, TDpccDocLabels.German);
  Assert.AreEqual('Setzt AValue neu.', Trim(mLayout.Text));
  mSpans := mLayout.Lines[0].Spans;
  mFound := -1;
  for mIndex := 0 to High(mSpans) do
  begin
    if mSpans[mIndex].Text = 'AValue' then
    begin
      mFound := mIndex;
    end;
  end;
  Assert.IsTrue(mFound > 0, 'paramref als eigenes Stück');
  Assert.AreEqual(Ord(TDpccDocFont.Mono), Ord(mSpans[mFound].Face.Font), 'Editorschrift');
  Assert.IsTrue(mSpans[mFound].Face.Bold, 'fett');
  Assert.AreEqual(Ord(TDpccDocColor.Text), Ord(mSpans[mFound].Color), 'Farbe des Absatzes, kein Akzent');
  // Ohne Innenabstand: so breit wie der Name, Nachbarn schließen direkt an.
  Assert.AreEqual(6 * 8, mSpans[mFound].Width);
  Assert.AreEqual(mSpans[mFound - 1].Right, mSpans[mFound].Left);
  Assert.AreEqual(mSpans[mFound].Right, mSpans[mFound + 1].Left);
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccStyleLookTests);

end.
