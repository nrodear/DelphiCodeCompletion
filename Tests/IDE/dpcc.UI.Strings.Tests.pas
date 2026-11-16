unit dpcc.UI.Strings.Tests;

// Tests für die Oberflächentexte (#446).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccStringsTests = class
  public
    [Test]
    procedure EveryTextExistsInBothLanguagesWithSamePlaceholders;
    [Test]
    procedure SwitchesLanguage;
    [Test]
    procedure ConfidenceLineForRuleFindings;
    [Test]
    procedure DocLabelsGerman;
    [Test]
    procedure TypeArgHeadingAndFooter;
    [Test]
    procedure UsesFooterAndCycle;
    [Test]
    procedure SignatureFormatLines;
    /// <summary>Abnahme #530: ein Hinweis H2164 zeigt „1 Hinweis“ in der Zusammenfassung.</summary>
    [Test]
    procedure BuildCountsSingularAndPlural;
  end;

/// <summary>Ein Text eines Moduls (#1455) in beiden Sprachen: nicht leer, gleiche Platzhalter in gleicher Folge.
/// AIndex ist die Ordnungszahl der Id für die Meldung.</summary>
procedure AssertTextPair(const AGerman, AEnglish: string; AIndex: Integer);

implementation

uses
  System.SysUtils,
  dpcc.Core.Documentation.Layout,
  dpcc.Core.Signature.Contract,
  dpcc.Core.Signature.Format,
  dpcc.UI.Strings,
  dpcc.UI.Completion.Strings;

function Placeholders(const AText: string): string;
var
  Index: Integer;
begin
  // %d und %s in Reihenfolge, z. B. "ds".
  Result := '';
  for Index := 1 to Length(AText) - 1 do
  begin
    if AText[Index] = '%' then
    begin
      Result := Result + AText[Index + 1];
    end;
  end;
end;

procedure AssertTextPair(const AGerman, AEnglish: string; AIndex: Integer);
begin
  Assert.IsTrue((AGerman <> '') and (AEnglish <> ''), AIndex.ToString);
  Assert.AreEqual(Placeholders(AGerman), Placeholders(AEnglish), AGerman + ' / ' + AEnglish);
end;

procedure TDpccStringsTests.EveryTextExistsInBothLanguagesWithSamePlaceholders;
var
  Id: TDpccTextId;
  German, English: string;
  Saved: TDpccLanguage;
begin
  Saved := TDpccStrings.Language;
  try
    for Id := Low(TDpccTextId) to High(TDpccTextId) do
    begin
      TDpccStrings.Language := TDpccLanguage.German;
      German := TDpccStrings.Text(Id);
      TDpccStrings.Language := TDpccLanguage.English;
      English := TDpccStrings.Text(Id);
      Assert.IsTrue((German <> '') and (English <> ''), Ord(Id).ToString);
      Assert.AreEqual(Placeholders(German), Placeholders(English), German + ' / ' + English);
    end;
  finally
    TDpccStrings.Language := Saved;
  end;
end;

procedure TDpccStringsTests.ConfidenceLineForRuleFindings;
var
  Saved: TDpccLanguage;
begin
  Saved := TDpccStrings.Language;
  try
    TDpccStrings.Language := TDpccLanguage.German;
    Assert.AreEqual('Konfidenz: mittel', TDpccStrings.Confidence('medium'));
    Assert.AreEqual('Konfidenz: hoch', TDpccStrings.Confidence('high'));
    Assert.AreEqual('', TDpccStrings.Confidence(''), 'Syntax- und Compilermeldungen ohne Konfidenz');
    TDpccStrings.Language := TDpccLanguage.English;
    Assert.AreEqual('Confidence: low', TDpccStrings.Confidence('low'));
  finally
    TDpccStrings.Language := Saved;
  end;
end;

procedure TDpccStringsTests.BuildCountsSingularAndPlural;
var
  Saved: TDpccLanguage;
begin
  Saved := TDpccStrings.Language;
  try
    TDpccStrings.Language := TDpccLanguage.German;
    Assert.AreEqual('1 Hinweis', TDpccStrings.BuildCounts(0, 1));
    Assert.AreEqual('2 Warnungen, 1 Hinweis', TDpccStrings.BuildCounts(2, 1));
    Assert.AreEqual('1 Warnung, 3 Hinweise', TDpccStrings.BuildCounts(1, 3));
    Assert.AreEqual('', TDpccStrings.BuildCounts(0, 0));
    TDpccStrings.Language := TDpccLanguage.English;
    Assert.AreEqual('2 warnings, 1 hint', TDpccStrings.BuildCounts(2, 1));
  finally
    TDpccStrings.Language := Saved;
  end;
end;

procedure TDpccStringsTests.SwitchesLanguage;
var
  Saved: TDpccLanguage;
begin
  Saved := TDpccStrings.Language;
  try
    TDpccStrings.Language := TDpccLanguage.German;
    Assert.AreEqual('Enter übernehmen · Esc schließen',
      TDpccCompletionStrings.Text(TDpccCompletionTextId.FooterKeys));
    Assert.AreEqual('3 von 84', TDpccCompletionStrings.Fmt(TDpccCompletionTextId.CountOf, [3, 84]));
    TDpccStrings.Language := TDpccLanguage.English;
    Assert.AreEqual('Enter to accept · Esc to close', TDpccCompletionStrings.Text(TDpccCompletionTextId.FooterKeys));
    Assert.AreEqual('3 of 84', TDpccCompletionStrings.Fmt(TDpccCompletionTextId.CountOf, [3, 84]));
  finally
    TDpccStrings.Language := Saved;
  end;
end;

procedure TDpccStringsTests.TypeArgHeadingAndFooter;
var
  Saved: TDpccLanguage;
begin
  // Typargumente (#450).
  Saved := TDpccStrings.Language;
  try
    TDpccStrings.Language := TDpccLanguage.German;
    Assert.AreEqual('T: class · nur Klassen', TDpccStrings.TypeArgHeading('T', 'class', 'classes'));
    Assert.AreEqual('T: record · nur Records und Grundtypen', TDpccStrings.TypeArgHeading('T', 'record', 'values'));
    Assert.AreEqual('T: class, constructor · nur Klassen mit parameterlosem Konstruktor',
      TDpccStrings.TypeArgHeading('T', 'class, constructor', 'constructible'));
    Assert.AreEqual('T: IVergleich · nur Typen, die IVergleich implementieren',
      TDpccStrings.TypeArgHeading('T', 'IVergleich', 'implements:IVergleich'));
    Assert.AreEqual('T: TBasis · nur Typen, die von TBasis abgeleitet sind',
      TDpccStrings.TypeArgHeading('T', 'TBasis', 'descends:TBasis'));
    Assert.AreEqual('Typargument V', TDpccStrings.TypeArgHeading('V', '', ''));
    Assert.AreEqual('Ausgeblendet: Records, Aufzählungen, Grundtypen',
      TDpccStrings.TypeArgHidden('records,enums,basic'));
    Assert.AreEqual('', TDpccStrings.TypeArgHidden(''));
    TDpccStrings.Language := TDpccLanguage.English;
    Assert.AreEqual('T: class · classes only', TDpccStrings.TypeArgHeading('T', 'class', 'classes'));
    Assert.AreEqual('Hidden: interfaces', TDpccStrings.TypeArgHidden('interfaces'));
  finally
    TDpccStrings.Language := Saved;
  end;
end;

procedure TDpccStringsTests.UsesFooterAndCycle;
var
  Saved: TDpccLanguage;
begin
  // uses-Abschnitt (#469): Fußzeile zu schon eingebundenen Units, Zirkelbezug im Detailpanel.
  Saved := TDpccStrings.Language;
  try
    TDpccStrings.Language := TDpccLanguage.German;
    Assert.AreEqual('', TDpccStrings.UsesHidden(nil));
    Assert.AreEqual('System.SysUtils ist schon eingebunden und fehlt hier',
      TDpccStrings.UsesHidden(['System.SysUtils']));
    Assert.AreEqual('System.SysUtils, System.Classes sind schon eingebunden und fehlen hier',
      TDpccStrings.UsesHidden(['System.SysUtils', 'System.Classes']));
    Assert.AreEqual('A, B und 2 weitere sind schon eingebunden und fehlen hier',
      TDpccStrings.UsesHidden(['A', 'B', 'C', 'D']));
    Assert.AreEqual('uGeneratorBeleg bindet diese Unit im interface-Teil ein',
      TDpccStrings.UsesCycle('uGeneratorBeleg → Haupt'));
    Assert.AreEqual('uMitte bindet diese Unit über uZwei, uDrei im interface-Teil ein',
      TDpccStrings.UsesCycle('uMitte → uZwei → uDrei → Haupt'));
    Assert.AreEqual('', TDpccStrings.UsesCycle(''));
    TDpccStrings.Language := TDpccLanguage.English;
    Assert.AreEqual('A is already used and not listed', TDpccStrings.UsesHidden(['A']));
    Assert.AreEqual('uA uses this unit in its interface section', TDpccStrings.UsesCycle('uA → Haupt'));
    // Nach "inherited " (#482): ausgelassene abstrakte Vorfahrmethoden.
    Assert.AreEqual('TBasis.Zeichnen is abstract and not listed', TDpccStrings.InheritedAbstract(['TBasis.Zeichnen']));
    TDpccStrings.Language := TDpccLanguage.German;
    Assert.AreEqual('', TDpccStrings.InheritedAbstract(nil));
    Assert.AreEqual('TBasis.Zeichnen ist abstrakt und fehlt', TDpccStrings.InheritedAbstract(['TBasis.Zeichnen']));
    Assert.AreEqual('Abstrakte Vorfahrmethoden fehlen: A.X, A.Y, B.Z, …',
      TDpccStrings.InheritedAbstract(['A.X', 'A.Y', 'B.Z', 'B.W']));
  finally
    TDpccStrings.Language := Saved;
  end;
end;

procedure TDpccStringsTests.DocLabelsGerman;
var
  Saved: TDpccLanguage;
  Labels, Expected: TDpccDocLabels;
begin
  Saved := TDpccStrings.Language;
  try
    TDpccStrings.Language := TDpccLanguage.German;
    Labels := TDpccStrings.DocLabels;
    Expected := TDpccDocLabels.German;
    Assert.AreEqual(Expected.Params, Labels.Params);
    Assert.AreEqual(Expected.TypeParams, Labels.TypeParams);
    Assert.AreEqual(Expected.Returns, Labels.Returns);
    Assert.AreEqual(Expected.Value, Labels.Value);
    Assert.AreEqual(Expected.Exceptions, Labels.Exceptions);
    Assert.AreEqual(Expected.Remarks, Labels.Remarks);
    Assert.AreEqual(Expected.Example, Labels.Example);
    Assert.AreEqual(Expected.SeeAlso, Labels.SeeAlso);
    Assert.AreEqual(Expected.Undocumented, Labels.Undocumented);
    Assert.AreEqual(Expected.More, Labels.More);
    Assert.AreEqual(Expected.Less, Labels.Less);
    Assert.AreEqual(Expected.CountParam, Labels.CountParam);
    Assert.AreEqual(Expected.CountParams, Labels.CountParams);
    Assert.AreEqual(Expected.CountTypeParam, Labels.CountTypeParam);
    Assert.AreEqual(Expected.CountTypeParams, Labels.CountTypeParams);
    Assert.AreEqual(Expected.CountException, Labels.CountException);
    Assert.AreEqual(Expected.CountExceptions, Labels.CountExceptions);
    Assert.AreEqual(Expected.ItemReturns, Labels.ItemReturns);
    Assert.AreEqual(Expected.ItemValue, Labels.ItemValue);
    Assert.AreEqual(Expected.ItemRemarks, Labels.ItemRemarks);
    Assert.AreEqual(Expected.ItemExample, Labels.ItemExample);
    Assert.AreEqual(Expected.ItemSeeAlso, Labels.ItemSeeAlso);
  finally
    TDpccStrings.Language := Saved;
  end;
end;

procedure TDpccStringsTests.SignatureFormatLines;
var
  Saved: TDpccLanguage;
  Line: TDpccFormatLine;
begin
  Saved := TDpccStrings.Language;
  try
    TDpccStrings.Language := TDpccLanguage.German;
    // Akzeptanz #451: Platzhalter 2 als ganzzahlig.
    Line := Default(TDpccFormatLine);
    Line.Kind := TDpccFormatLineKind.Placeholder;
    Line.Placeholder := 1;
    Line.Count := 2;
    Line.TypeChar := 'd';
    Assert.AreEqual('Platzhalter 2 von 2 erwartet ganzzahlig', TDpccStrings.SignatureFormatLine(Line));
    Line.Kind := TDpccFormatLineKind.Problem;
    Line.Problem := TDpccFormatProblem.TooManyArguments;
    Line.Argument := 2;
    Assert.AreEqual('Mehr Argumente als Platzhalter: Argument 3 wird nicht ausgegeben.',
      TDpccStrings.SignatureFormatLine(Line));
    Line.Problem := TDpccFormatProblem.TypeConflict;
    Line.Argument := 1;
    Line.PlaceholderText := '%d';
    Line.ProblemKind := 'string';
    Assert.AreEqual('Platzhalter 2 (%d) erwartet ganzzahlig, Argument 2 ist ein String: EConvertError zur Laufzeit.',
      TDpccStrings.SignatureFormatLine(Line));
    TDpccStrings.Language := TDpccLanguage.English;
    Line.Kind := TDpccFormatLineKind.Placeholder;
    Line.TypeChar := 's';
    Assert.AreEqual('Placeholder 2 of 2 expects string', TDpccStrings.SignatureFormatLine(Line));
    Assert.AreEqual('', TDpccStrings.SignatureFormatLine(Default(TDpccFormatLine)));
  finally
    TDpccStrings.Language := Saved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccStringsTests);

end.
