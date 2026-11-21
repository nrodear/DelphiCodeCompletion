unit dpcc.Core.Hover.Look.Tests;

// Tests für die Stufen der Darstellung im Hover-Tooltip und in der Doku (LOOK2): Der Satz der XMLDoc vergibt Rollen
// (Überschrift, Parametername, Rückgabetyp, Verweis, Fehler, Warnung, Zahl), TDpccDocTypeset.ColorOf macht daraus je
// Stufe die Farbe aus TDpccLook; die Art der Kopfzeile ergibt die Artgruppe für Look.Kind. Alles ohne Zeichenfläche.
// Dazu (LOOK4): Ein Hover ohne "dpcc" (Direktive {$IFNDEF X}) ergibt Abschnitte ohne Markdown-Zeichen. Die Kopfzeile
// ist eine markierte Fläche: Intensiv zeichnet sie mit Look.Marked in den Farben von Dezent, die Doku bleibt in denen
// von Intensiv.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccHoverLookTests = class
  public
    /// <summary>Rollen der Stücke im Hover (PlainNames): Überschriften, Parameternamen (nicht fett), unbekannter
    /// Parameter, „nicht dokumentiert“, Rückgabetyp, Ausnahme, Verweis (unterstrichen), Zahl im Codeblock.</summary>
    [Test]
    procedure DocRolesInHover;
    /// <summary>ColorOf je Stufe, hell und dunkel: Rollen auf die Doc*-, Syn*- und Meldungsfarben des Looks.</summary>
    [Test]
    procedure ColorOfFollowsLook;
    /// <summary>Was jede Stufe ändert (Entwurf): Überschrift, Verweis, Rückgabetyp, Warnung und Fehler je Stufe.
    /// </summary>
    [Test]
    procedure ColorOfPerLevel;
    /// <summary>Artgruppe der Kopfzeile: „class function“, operator, resourcestring, threadvar, program …</summary>
    [Test]
    procedure KindGroupOfHeadline;
    /// <summary>Dezent: Art in der Kopfzeile gedämpft wie bisher (Colors.KindLabel), für jede Art.</summary>
    [Test]
    procedure SubtleKindStaysMuted;
    /// <summary>Intensiv: Kopfzeile (Look.Marked) wie Dezent – Art gedämpft für jede Art, Typ abgeschwächt, Zahl in
    /// Textfarbe, Schlüsselwort, String und Kommentar wie Dezent, keine Fläche unter dem aktiven Parameter; die Doku
    /// (ColorOf mit dem Look des Fensters) behält die Farben von Intensiv.</summary>
    [Test]
    procedure IntenseHeadlineLikeSubtle;
    /// <summary>Hover über {$IFNDEF AUTOREFCOUNT} (Markdown ohne "dpcc"): Kopfzeile ohne Sterne mit fettem Namen,
    /// Doku ohne „---“, {$IFNDEF} fett, [DocWiki](URL) als Link mit der ganzen URL (Klammern darin).</summary>
    [Test]
    procedure DirectiveHoverWithoutMarkdown;
    /// <summary>Weitere Markdown-Köpfe: `Code` und **fett** ohne Zeichen; „**function** (…)“ bekommt keine Art.
    /// </summary>
    [Test]
    procedure MarkdownHeadlines;
    /// <summary>Trennlinie über der Doku (LOOK6): ohne Strich, wenn die Doku mit einer Überschrift samt Linie beginnt
    /// (Add ohne XMLDoc: PARAMETER); mit Strich vor einem Beschreibungssatz, gescrollt und ohne Doku.</summary>
    [Test]
    procedure DocSeparatorOnlyBeforeText;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette,
  dpcc.Core.Style.Look,
  dpcc.Core.Documentation.Contract,
  dpcc.Core.Documentation.Layout,
  dpcc.Core.Documentation.Typeset,
  dpcc.Core.Hover.Contract,
  dpcc.Core.Hover.Plain,
  dpcc.UI.Hover.Tip;

const
  cDeclaration = 'function ImportFile(const AFileName: string; AMaxRows: Integer = 0): Integer';
  cDocJson = '{"sections":[' +
    '{"kind":"summary","runs":[{"kind":"text","text":"Liest eine CSV-Datei ein."}]},' +
    '{"kind":"param","name":"AFileName","runs":[{"kind":"text","text":"Pfad der Datei."}]},' +
    '{"kind":"param","name":"AOld","runs":[{"kind":"text","text":"Gibt es nicht mehr."}]},' +
    '{"kind":"returns","runs":[{"kind":"text","text":"Anzahl der Zeilen."}]},' +
    '{"kind":"exception","name":"EFOpenError","runs":[{"kind":"text","text":"Datei fehlt."}]},' +
    '{"kind":"example","runs":[{"kind":"codeblock","text":"X := 42;"}]},' +
    '{"kind":"seealso","runs":[{"kind":"ref","text":"ImportStream","file":"ImportCsv.pas","line":12}]}' +
    ']}';

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

/// <summary>Satz wie im Hover (TDpccPlainHover.DocContent): aufgeklappt, offene Signatur, schlichte Namen.</summary>
function HoverLayout: TDpccDocLayout;
var
  mContent: TDpccDocContent;
begin
  mContent := TDpccDocContent.Create(DocOf(cDocJson), TDpccDocSignature.Parse(cDeclaration), True);
  mContent.OpenSignature := True;
  mContent.Fixed := True;
  mContent.PlainNames := True;
  Result := TDpccDocTypeset.Build(mContent, 600, TDpccDocMetrics.Create(16, 17, 1), Measure,
    TDpccDocLabels.German);
end;

/// <summary>Stück mit dem Text AText (ohne Leerraum am Rand); ALast: das letzte statt des ersten.</summary>
function SpanOf(const ALayout: TDpccDocLayout; const AText: string; ALast: Boolean = False): TDpccDocSpan;
var
  mLine: TDpccDocLine;
  mSpan: TDpccDocSpan;
  mFound: Boolean;
begin
  Result := Default(TDpccDocSpan);
  mFound := False;
  for mLine in ALayout.Lines do
  begin
    for mSpan in mLine.Spans do
    begin
      if Trim(mSpan.Text) = AText then
      begin
        Result := mSpan;
        mFound := True;
        if not ALast then
        begin
          Exit;
        end;
      end;
    end;
  end;
  Assert.IsTrue(mFound, 'Stück „' + AText + '“ fehlt');
end;

procedure CheckRole(const ALayout: TDpccDocLayout; const AText: string; AExpected: TDpccDocColor;
  ALast: Boolean = False);
begin
  Assert.AreEqual(Ord(AExpected), Ord(SpanOf(ALayout, AText, ALast).Color), 'Rolle von „' + AText + '“');
end;

procedure Same(AExpected, AActual: TDpccColor; const AName: string);
begin
  Assert.AreEqual(Integer(AExpected), Integer(AActual), AName);
end;

procedure TDpccHoverLookTests.DocRolesInHover;
var
  mLayout: TDpccDocLayout;
  mLabels: TDpccDocLabels;
begin
  mLayout := HoverLayout;
  mLabels := TDpccDocLabels.German;
  CheckRole(mLayout, mLabels.Params, TDpccDocColor.Heading);
  CheckRole(mLayout, mLabels.Returns, TDpccDocColor.Heading);
  CheckRole(mLayout, mLabels.Exceptions, TDpccDocColor.Heading);
  CheckRole(mLayout, mLabels.Example, TDpccDocColor.Heading);
  CheckRole(mLayout, mLabels.SeeAlso, TDpccDocColor.Heading);
  CheckRole(mLayout, 'AFileName', TDpccDocColor.Param);
  Assert.IsFalse(SpanOf(mLayout, 'AFileName').Face.Bold, 'Parametername im Hover nicht fett');
  CheckRole(mLayout, 'AMaxRows', TDpccDocColor.Param);
  CheckRole(mLayout, Trim(mLabels.Undocumented), TDpccDocColor.Muted);
  CheckRole(mLayout, 'AOld', TDpccDocColor.Warn);
  // Rückgabetyp: das letzte „Integer“ (das erste ist der Typ von AMaxRows in der Parametertabelle).
  CheckRole(mLayout, 'Integer', TDpccDocColor.TypeName, True);
  Assert.IsFalse(SpanOf(mLayout, 'Integer', True).Face.Bold, 'Rückgabetyp: Schriftstil wie bisher');
  CheckRole(mLayout, 'EFOpenError', TDpccDocColor.Error);
  CheckRole(mLayout, 'ImportStream', TDpccDocColor.Link);
  Assert.IsTrue(SpanOf(mLayout, 'ImportStream').Underline, 'Verweis mit Fundort unterstrichen');
  CheckRole(mLayout, '42', TDpccDocColor.Number);
  CheckRole(mLayout, 'Liest eine CSV-Datei ein.', TDpccDocColor.Text);
end;

procedure CheckColorOf(const AColors: TDpccColors; const AName: string);
var
  mLevel: TDpccLookLevel;
  mLook: TDpccLook;
  mName: string;
begin
  for mLevel := Low(TDpccLookLevel) to High(TDpccLookLevel) do
  begin
    mLook := TDpccLook.From(AColors, mLevel);
    mName := AName + ' ' + DpccLookLevelToId(mLevel) + ': ';
    Same(mLook.DocHeading, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.Heading), mName + 'Heading');
    Same(mLook.DocParam, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.Param), mName + 'Param');
    Same(mLook.DocType, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.TypeName), mName + 'TypeName');
    Same(mLook.Link, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.Link), mName + 'Link');
    Same(mLook.Error, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.Error), mName + 'Error');
    Same(mLook.Warn, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.Warn), mName + 'Warn');
    Same(mLook.SynKeyword, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.Keyword), mName + 'Keyword');
    Same(mLook.SynString, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.StringLiteral), mName + 'StringLiteral');
    Same(mLook.SynComment, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.Comment), mName + 'Comment');
    Same(mLook.SynNumber, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.Number), mName + 'Number');
    Same(AColors.Text, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.Text), mName + 'Text');
    Same(AColors.Muted, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.Muted), mName + 'Muted');
    Same(AColors.Accent, TDpccDocTypeset.ColorOf(mLook, TDpccDocColor.Accent), mName + 'Accent');
  end;
end;

procedure TDpccHoverLookTests.ColorOfFollowsLook;
begin
  CheckColorOf(TDpccColors.Light, 'hell');
  CheckColorOf(TDpccColors.Dark, 'dunkel');
end;

procedure TDpccHoverLookTests.ColorOfPerLevel;
var
  mColors: TDpccColors;
  mIntense, mSubtle, mPlain: TDpccLook;
begin
  mColors := TDpccColors.Light;
  mIntense := TDpccLook.From(mColors, TDpccLookLevel.Intense);
  mSubtle := TDpccLook.From(mColors, TDpccLookLevel.Subtle);
  mPlain := TDpccLook.From(mColors, TDpccLookLevel.Plain);
  // Überschriften: Akzent, abgeschwächt, gedämpft.
  Same(mColors.Accent, TDpccDocTypeset.ColorOf(mIntense, TDpccDocColor.Heading), 'Intensiv: Überschrift');
  Assert.AreNotEqual(Integer(mColors.Muted), Integer(TDpccDocTypeset.ColorOf(mSubtle, TDpccDocColor.Heading)),
    'Dezent: Überschrift nicht nur gedämpft');
  Same(mColors.Muted, TDpccDocTypeset.ColorOf(mPlain, TDpccDocColor.Heading), 'Unscheinbar: Überschrift');
  // Verweise: Akzent, Akzent, Textfarbe.
  Same(mColors.Accent, TDpccDocTypeset.ColorOf(mIntense, TDpccDocColor.Link), 'Intensiv: Verweis');
  Same(mColors.Accent, TDpccDocTypeset.ColorOf(mSubtle, TDpccDocColor.Link), 'Dezent: Verweis');
  Same(mColors.Text, TDpccDocTypeset.ColorOf(mPlain, TDpccDocColor.Link), 'Unscheinbar: Verweis');
  // Rückgabetyp und Parameternamen: nicht mehr in Schlüsselwortfarbe; unscheinbar in Textfarbe.
  Assert.AreNotEqual(Integer(mColors.Keyword), Integer(TDpccDocTypeset.ColorOf(mSubtle, TDpccDocColor.TypeName)),
    'Dezent: Rückgabetyp nicht in Schlüsselwortfarbe');
  Same(mColors.Text, TDpccDocTypeset.ColorOf(mPlain, TDpccDocColor.TypeName), 'Unscheinbar: Rückgabetyp');
  Same(mColors.Text, TDpccDocTypeset.ColorOf(mPlain, TDpccDocColor.Param), 'Unscheinbar: Parametername');
  // Warnung: farbig, farbig, gedämpft; Fehler in allen Stufen in Fehlerfarbe.
  Same(mColors.Warn, TDpccDocTypeset.ColorOf(mIntense, TDpccDocColor.Warn), 'Intensiv: Warnung');
  Same(mColors.Warn, TDpccDocTypeset.ColorOf(mSubtle, TDpccDocColor.Warn), 'Dezent: Warnung');
  Same(mColors.Muted, TDpccDocTypeset.ColorOf(mPlain, TDpccDocColor.Warn), 'Unscheinbar: Warnung');
  Same(mColors.Error, TDpccDocTypeset.ColorOf(mIntense, TDpccDocColor.Error), 'Intensiv: Fehler');
  Same(mColors.Error, TDpccDocTypeset.ColorOf(mSubtle, TDpccDocColor.Error), 'Dezent: Fehler');
  Same(mColors.Error, TDpccDocTypeset.ColorOf(mPlain, TDpccDocColor.Error), 'Unscheinbar: Fehler');
end;

procedure CheckGroup(const AKind: string; AExpected: TDpccKindGroup);
var
  mHover: TDpccPlainHover;
begin
  mHover := Default(TDpccPlainHover);
  mHover.Kind := AKind;
  Assert.AreEqual(Ord(AExpected), Ord(mHover.KindGroup), 'Artgruppe von „' + AKind + '“');
end;

procedure TDpccHoverLookTests.KindGroupOfHeadline;
begin
  CheckGroup('function', TDpccKindGroup.Routine);
  CheckGroup('class function', TDpccKindGroup.Routine);
  CheckGroup('class procedure', TDpccKindGroup.Routine);
  CheckGroup('constructor', TDpccKindGroup.Routine);
  CheckGroup('class operator', TDpccKindGroup.Routine);
  CheckGroup('property', TDpccKindGroup.Prop);
  CheckGroup('class property', TDpccKindGroup.Prop);
  CheckGroup('var', TDpccKindGroup.Variable);
  CheckGroup('threadvar', TDpccKindGroup.Variable);
  CheckGroup('field', TDpccKindGroup.Variable);
  CheckGroup('type', TDpccKindGroup.TypeName);
  CheckGroup('unit', TDpccKindGroup.TypeName);
  CheckGroup('program', TDpccKindGroup.TypeName);
  CheckGroup('const', TDpccKindGroup.Constant);
  CheckGroup('resourcestring', TDpccKindGroup.Constant);
  CheckGroup('', TDpccKindGroup.None);
end;

procedure TDpccHoverLookTests.SubtleKindStaysMuted;
const
  cKinds: array[0..6] of string = ('function', 'class function', 'property', 'var', 'type', 'const', '');
var
  mColors: TDpccColors;
  mLook: TDpccLook;
  mHover: TDpccPlainHover;
  mKind: string;
begin
  mColors := TDpccColors.Light;
  mLook := TDpccLook.From(mColors, TDpccLookLevel.Subtle);
  for mKind in cKinds do
  begin
    mHover := Default(TDpccPlainHover);
    mHover.Kind := mKind;
    Same(mColors.KindLabel, mLook.Kind[mHover.KindGroup], 'Dezent: Art „' + mKind + '“');
  end;
end;

procedure TDpccHoverLookTests.IntenseHeadlineLikeSubtle;
const
  cKinds: array[0..6] of string = ('function', 'class function', 'property', 'var', 'type', 'const', '');
var
  mColors: TDpccColors;
  mIntense, mMarked, mSubtle: TDpccLook;
  mHover: TDpccPlainHover;
  mKind, mName: string;
  mDark: Boolean;
begin
  for mDark := False to True do
  begin
    if mDark then
    begin
      mColors := TDpccColors.Dark;
      mName := 'dunkel: ';
    end
    else
    begin
      mColors := TDpccColors.Light;
      mName := 'hell: ';
    end;
    mIntense := TDpccLook.From(mColors, TDpccLookLevel.Intense);
    mSubtle := TDpccLook.From(mColors, TDpccLookLevel.Subtle);
    mMarked := mIntense.Marked;
    for mKind in cKinds do
    begin
      mHover := Default(TDpccPlainHover);
      mHover.Kind := mKind;
      Same(mColors.KindLabel, mMarked.Kind[mHover.KindGroup], mName + 'Kopfzeile Art „' + mKind + '“');
    end;
    // Ohne Marked hätte „function“ die Platzhalterfarbe der Routinen: Die Kopfzeile muss Marked nehmen.
    Assert.AreNotEqual(Integer(mColors.KindLabel), Integer(mIntense.Kind[TDpccKindGroup.Routine]),
      mName + 'Intensiv außerhalb der Kopfzeile farbig');
    Same(mSubtle.SynKeyword, mMarked.SynKeyword, mName + 'Schlüsselwort');
    Same(mSubtle.SynString, mMarked.SynString, mName + 'String');
    Same(mSubtle.SynComment, mMarked.SynComment, mName + 'Kommentar');
    Same(mColors.Text, mMarked.SynNumber, mName + 'Zahl in Textfarbe');
    Same(mSubtle.SynType, mMarked.SynType, mName + 'Typ abgeschwächt');
    Assert.IsFalse(mMarked.ParamBackUsed, mName + 'keine Fläche unter dem aktiven Parameter');
    // Die Kopffläche ist in beiden Stufen dieselbe; die Doku nimmt weiter den Look des Fensters.
    Same(mSubtle.HeadBack, mIntense.HeadBack, mName + 'Kopffläche');
    Same(mColors.Accent, TDpccDocTypeset.ColorOf(mIntense, TDpccDocColor.Heading), mName + 'Doku-Überschrift');
  end;
end;

const
  cDocWikiUrl = 'https://docwiki.embarcadero.com/RADStudio/Athens/en/IFNDEF_directive_(Delphi)';
  cHeadText = 'AUTOREFCOUNT: nicht definiert, weder im Projekt noch vom Compiler noch mit {$DEFINE} davor gesetzt';

/// <summary>Hover-Antwort ohne "dpcc" mit AMarkdown als Inhalt (wie TLspHover.MarkdownAnswer).</summary>
function MarkdownData(const AMarkdown: string): TDpccHoverData;
var
  mHover, mContents: TJSONObject;
begin
  mHover := TJSONObject.Create;
  try
    mContents := TJSONObject.Create;
    mContents.AddPair('kind', 'markdown');
    mContents.AddPair('value', AMarkdown);
    mHover.AddPair('contents', mContents);
    Result := TDpccHoverData.FromHover(mHover);
  finally
    mHover.Free;
  end;
end;

/// <summary>Text ohne Markdown-Zeichen (**, `, ---, [..](..)).</summary>
procedure CheckNoMarks(const AText, AName: string);
begin
  Assert.AreEqual(0, Pos('**', AText), AName + ': ** in „' + AText + '“');
  Assert.AreEqual(0, Pos('`', AText), AName + ': ` in „' + AText + '“');
  Assert.AreEqual(0, Pos('---', AText), AName + ': --- in „' + AText + '“');
  Assert.AreEqual(0, Pos('](', AText), AName + ': ]( in „' + AText + '“');
end;

procedure TDpccHoverLookTests.DirectiveHoverWithoutMarkdown;
var
  mData: TDpccHoverData;
  mHover: TDpccPlainHover;
  mSection: TDpccDocSection;
  mRun: TDpccDocRun;
  mBold, mLink, mText: Boolean;
  mLayout: TDpccDocLayout;
  mSpan: TDpccDocSpan;
begin
  // Genau der Text von TLspHover.DirectiveHover für {$IFNDEF AUTOREFCOUNT} in System.pas (Symbol, ---, Direktive).
  mData := MarkdownData('**AUTOREFCOUNT**: nicht definiert, weder im Projekt noch vom Compiler noch mit {$DEFINE} ' +
    'davor gesetzt' + #10#10'---'#10#10 + '**{$IFNDEF}**' + #10#10 +
    'Kompilieren, wenn das bedingte Symbol nicht definiert ist.' + #10#10 + '[DocWiki](' + cDocWikiUrl + ')');
  Assert.IsTrue(mData.Markdown, 'ohne dpcc: Markdown');
  mHover := TDpccPlainHover.From(mData, 'System');
  // Kopfzeile: ohne Sterne, ohne Art; der Name am Anfang wird fett gezeichnet (NameLength).
  Assert.AreEqual(cHeadText, mHover.Headline);
  Assert.AreEqual('', mHover.Kind);
  Assert.AreEqual(Length('AUTOREFCOUNT'), TDpccPlainHover.NameLength(mHover.Signature));
  Assert.AreEqual('System', mHover.Origin);
  Assert.IsTrue(mHover.Has(TDpccPlainHoverSection.Documentation), 'Doku da');
  // Doku: keine Markdown-Zeichen; {$IFNDEF} fett, der Satz als Text, DocWiki als Link mit ganzer URL.
  mBold := False;
  mLink := False;
  mText := False;
  for mSection in mHover.Doc.Sections do
  begin
    CheckNoMarks(mSection.Text, 'Abschnitt');
    for mRun in mSection.Runs do
    begin
      CheckNoMarks(mRun.Text, 'Lauf');
      if (mRun.Text = '{$IFNDEF}') and mRun.Bold then
      begin
        mBold := True;
      end;
      if (mRun.Kind = TDpccDocRunKind.Link) and (mRun.Text = 'DocWiki') then
      begin
        mLink := True;
        Assert.AreEqual(cDocWikiUrl, mRun.Target, 'Ziel samt Klammern');
      end;
      if mRun.Text = 'Kompilieren, wenn das bedingte Symbol nicht definiert ist.' then
      begin
        mText := True;
      end;
    end;
  end;
  Assert.IsTrue(mBold, '{$IFNDEF} fett');
  Assert.IsTrue(mLink, 'DocWiki als Link');
  Assert.IsTrue(mText, 'Satz als Text');
  CheckNoMarks(mHover.Summary, 'Kurztext');
  CheckNoMarks(mHover.Spoken, 'Sprachausgabe');
  // Satz wie im Tooltip: Link in Linkfarbe, unterstrichen; im Klartext weder Zeichen noch URL.
  mLayout := TDpccDocTypeset.Build(mHover.DocContent, 400, TDpccDocMetrics.Create(16, 17, 1), Measure,
    TDpccDocLabels.German);
  CheckNoMarks(mLayout.Text, 'Satz');
  Assert.AreEqual(0, Pos('https:', mLayout.Text), 'URL nicht im Text');
  mSpan := SpanOf(mLayout, 'DocWiki');
  Assert.AreEqual(Ord(TDpccDocColor.Link), Ord(mSpan.Color));
  Assert.IsTrue(mSpan.Underline, 'Link unterstrichen');
  Assert.IsTrue(SpanOf(mLayout, '{$IFNDEF}').Face.Bold, '{$IFNDEF} fett im Satz');
end;

procedure TDpccHoverLookTests.MarkdownHeadlines;
var
  mHover: TDpccPlainHover;
begin
  // Wert einer Bedingung (#847): **wahr**: `Defined(X)`.
  mHover := TDpccPlainHover.From(MarkdownData('**wahr**: `Defined(DEBUG)`' + #10#10 + '- `Defined(DEBUG)` wahr'),
    'Unit1');
  Assert.AreEqual('wahr: Defined(DEBUG)', mHover.Headline);
  CheckNoMarks(mHover.Doc.Sections[0].Text, 'Teilwert');
  // Schlüsselwort (#187): die Sterne verhindern wie bisher, dass „function“ als Art erkannt wird.
  mHover := TDpccPlainHover.From(MarkdownData('**function** (Schlüsselwort)' + #10#10 + 'Deklariert eine Funktion.'),
    'Unit1');
  Assert.AreEqual('', mHover.Kind);
  Assert.AreEqual('function (Schlüsselwort)', mHover.Headline);
  // Fremder Server mit Pascal-Deklaration: unverändert.
  mHover := TDpccPlainHover.From(MarkdownData('```pascal' + #10 + 'property Items[Index: Integer]: TItem;' + #10 +
    '```'), 'Unit1');
  Assert.AreEqual('property  Items[Index: Integer]: TItem', mHover.Headline);
end;

/// <summary>Satz der Doku wie im Tooltip zur Antwort AJson (Objekt "dpcc").</summary>
function TipLayout(const AJson: string): TDpccDocLayout;
var
  mValue: TJSONValue;
  mData: TDpccHoverData;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mData := TDpccHoverData.FromHover(mValue);
  finally
    mValue.Free;
  end;
  Result := TDpccDocTypeset.Build(TDpccPlainHover.From(mData, 'Unit1').DocContent, 400,
    TDpccDocMetrics.Create(16, 17, 1), Measure, TDpccDocLabels.German);
end;

procedure TDpccHoverLookTests.DocSeparatorOnlyBeforeText;
var
  mLayout: TDpccDocLayout;
begin
  // Add (TStrings) ohne XMLDoc: Die Doku beginnt mit PARAMETER samt Linie, die Trennlinie darüber entfällt.
  mLayout := TipLayout('{"contents": "x", "dpcc": {"declaration": "function Add(const S: string): Integer;", ' +
    '"kind": "method"}}');
  Assert.IsTrue(Length(mLayout.Lines) > 0, 'Doku aus der Signatur');
  Assert.IsTrue(mLayout.Lines[0].Rule, 'erste Zeile ist eine Überschrift mit Linie');
  Assert.IsFalse(TDpccHoverTip.DocSeparatorShown(mLayout, 0), 'kein Strich über PARAMETER');
  // Weggescrollt: wieder mit Strich.
  Assert.IsTrue(TDpccHoverTip.DocSeparatorShown(mLayout, 5), 'gescrollt mit Strich');
  // Mit Beschreibungssatz: Strich wie bisher.
  mLayout := TipLayout('{"contents": "x", "dpcc": {"declaration": "function Add(const S: string): Integer;", ' +
    '"kind": "method", "documentation": {"sections": [{"kind": "summary", "runs": [{"kind": "text", ' +
    '"text": "Fügt hinzu."}]}]}}}');
  Assert.IsFalse(mLayout.Lines[0].Rule, 'erste Zeile ist Text');
  Assert.IsTrue(TDpccHoverTip.DocSeparatorShown(mLayout, 0), 'Strich über dem Beschreibungssatz');
  // Ohne Doku: Strich (die Entscheidung ändert nichts).
  Assert.IsTrue(TDpccHoverTip.DocSeparatorShown(Default(TDpccDocLayout), 0), 'leere Doku');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccHoverLookTests);

end.
