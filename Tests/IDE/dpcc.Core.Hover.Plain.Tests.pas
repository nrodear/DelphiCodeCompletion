unit dpcc.Core.Hover.Plain.Tests;

// Tests für den Inhalt des schlichten Hover-Tooltips (S3, seit S3b mit vollem Inhalt, dpcc.Core.Hover.Plain):
// Zeile 1 Art und Signatur, Herkunft (Art in Worten · Bibliothek · Unit bzw. Unit.Typ), Fundort, Wert und
// Veraltung, die ganze XMLDoc (ohne Kürzen, mit offener Signatur), published-Mitglieder (je Abschnitt die ersten
// Zeilen, dann „+ n weitere“), Vererbungskette und der Wert im Debugger; Abschnitte in fester Reihenfolge, leere
// entfallen. Kürzungen: Kurztext für die Sprachausgabe, Tabellen, Kette.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccPlainHoverTests = class
  public
    [Test]
    procedure SignatureUnitAndDocumentation;
    [Test]
    procedure WithoutDocumentationOnlyHeadlineAndOrigin;
    [Test]
    procedure LongSummaryIsShortenedOnlyForSpeech;
    [Test]
    procedure MarkdownGivesSignatureAndDocumentation;
    [Test]
    procedure KindFromServerAndOrigin;
    [Test]
    procedure FullContentInOrder;
    [Test]
    procedure MembersAreShortened;
    [Test]
    procedure DebugValueAlone;
    [Test]
    procedure ClassReferenceShowsTargetType;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  dpcc.Core.Hover.Contract,
  dpcc.Core.Hover.DebugValue,
  dpcc.Core.Hover.Texts,
  dpcc.Core.Documentation.Contract,
  dpcc.Core.Documentation.Typeset,
  dpcc.Core.Hover.Plain;

/// <summary>Hover-Antwort aus AJson; der Aufrufer bekommt die Daten, das JSON wird freigegeben.</summary>
function DataOf(const AJson: string): TDpccHoverData;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Assert.IsNotNull(mValue, AJson);
    Result := TDpccHoverData.FromHover(mValue);
  finally
    mValue.Free;
  end;
end;

/// <summary>Texte wie in der deutschen Oberfläche (dpcc.UI.Hover.Strings), Art AKindCaption.</summary>
function Texts(const AKindCaption: string): TDpccHoverTexts;
begin
  Result := Default(TDpccHoverTexts);
  Result.KindCaption := AKindCaption;
  Result.Inheritance := 'Vererbung';
  Result.TargetType := 'Zieltyp %s';
  Result.DebugPending := 'wird ausgewertet …';
  Result.PublishedSummary := 'published: %d Properties · %d Ereignisse';
  Result.PublishedProperties := 'Properties';
  Result.PublishedEvents := 'Ereignisse';
  Result.PublishedImplicit := 'implizit';
  Result.PublishedMoreProperties := '+ %d weitere Properties';
  Result.PublishedMoreEvents := '+ %d weitere Ereignisse';
  Result.PublishedEventsNote := 'erkannt am Methodenzeiger-Typ, nicht am Namen';
  Result.PublishedArrayProperty := 'Array-Property';
  Result.PublishedDefaultProperty := 'Standard-Property';
  Result.PublishedVclNote := 'geerbte aus der VCL nur mit VCL-Quellen im Index';
end;

/// <summary>Abschnitte als Text, z. B. "Headline,Origin" (für lesbare Meldungen).</summary>
function SectionNames(const AHover: TDpccPlainHover): string;
const
  cNames: array[TDpccPlainHoverSection] of string = ('DebugValue', 'Headline', 'Origin', 'Location', 'Notes',
    'Documentation', 'Members', 'Chain');
var
  mSection: TDpccPlainHoverSection;
begin
  Result := '';
  for mSection in AHover.Sections do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + cNames[mSection];
  end;
end;

/// <summary>published-Mitglied als JSON.</summary>
function Member(const AName, AType, ADeclaring: string; AEvent: Boolean): string;
begin
  Result := Format('{"name": "%s", "type": "%s", "declaringClass": "%s", "event": %s}',
    [AName, AType, ADeclaring, LowerCase(BoolToStr(AEvent, True))]);
end;

{ TDpccPlainHoverTests }

procedure TDpccPlainHoverTests.SignatureUnitAndDocumentation;
var
  mHover: TDpccPlainHover;
begin
  mHover := TDpccPlainHover.From(DataOf('{"contents": {"kind": "markdown", "value": "x"}, "dpcc": {' +
    '"declaration": "constructor Create(const AFileName: string; Mode: Word);", "unit": "System.Classes", ' +
    '"container": "TFileStream", "kind": "constructor", "documentationText": "Öffnet die Datei. AFileName: Name", ' +
    '"documentation": {"sections": [' +
    '{"kind": "summary", "runs": [{"kind": "text", "text": "Öffnet die Datei"}, {"kind": "br"}, ' +
    '{"kind": "code", "text": "AFileName"}, {"kind": "text", "text": " im Modus Mode."}]}, ' +
    '{"kind": "param", "name": "AFileName", "runs": [{"kind": "text", "text": "Name der Datei"}]}, ' +
    '{"kind": "remarks", "runs": [{"kind": "text", "text": "Auch anzeigen."}]}]}}}'), 'Unit1');
  Assert.AreEqual('constructor', mHover.Kind);
  Assert.AreEqual('Create(const AFileName: string; Mode: Word)', mHover.Signature);
  Assert.AreEqual('constructor  Create(const AFileName: string; Mode: Word)', mHover.Headline);
  Assert.AreEqual('System.Classes.TFileStream', mHover.Origin);
  Assert.AreEqual('System.Classes.TFileStream', mHover.OriginLine, 'ohne Texte und Bibliothek nur die Herkunft');
  // Kurztext (Sprachausgabe) als Fließtext; die Doku bleibt ganz: summary, Parameter und Hinweise.
  Assert.AreEqual('Öffnet die Datei AFileName im Modus Mode.', mHover.Summary);
  Assert.IsTrue(mHover.HasSummary);
  Assert.AreEqual(3, Integer(Length(mHover.Doc.Sections)));
  Assert.AreEqual('Headline,Origin,Documentation', SectionNames(mHover));
  // Satz des Detailpanels: aufgeklappt, ohne Schalter, Parameter aus der Signatur.
  Assert.IsTrue(mHover.DocContent.Expanded);
  Assert.IsTrue(mHover.DocContent.Fixed);
  Assert.IsTrue(mHover.DocContent.OpenSignature);
  Assert.AreEqual(2, Integer(Length(mHover.DocContent.Signature.Params)));
  // S3c: Parameternamen wie Bezeichner der Code-Insight-Liste; Name der Kopfzeile fett („Create“).
  Assert.IsTrue(mHover.DocContent.PlainNames);
  Assert.AreEqual(Length('Create'), TDpccPlainHover.NameLength(mHover.Signature));
  Assert.AreEqual(Length('TFileStream'), TDpccPlainHover.NameLength('TFileStream = class(THandleStream)'));
  Assert.AreEqual(Length('Sys.Neu'), TDpccPlainHover.NameLength('Sys.Neu: TFoo'));
  Assert.AreEqual(0, TDpccPlainHover.NameLength(''));
end;

procedure TDpccPlainHoverTests.WithoutDocumentationOnlyHeadlineAndOrigin;
var
  mHover: TDpccPlainHover;
begin
  // Deklaration in der aktuellen Datei: Der Server nennt keine Unit, es gilt die Unit der Datei.
  mHover := TDpccPlainHover.From(DataOf('{"dpcc": {"declaration": "Zaehler: Integer;", "kind": "variable"}}'),
    TDpccPlainHover.UnitOfFile('C:\Projekt\Haupt.Form.pas'));
  Assert.AreEqual('var  Zaehler: Integer', mHover.Headline);
  Assert.AreEqual('Haupt.Form', mHover.Origin);
  Assert.AreEqual('', mHover.Summary);
  Assert.IsFalse(mHover.HasSummary);
  Assert.AreEqual('Headline,Origin', SectionNames(mHover));
  // Ohne Deklaration kein Tooltip.
  Assert.IsFalse(DataOf('{"dpcc": {"declaration": ""}}').Found);
  Assert.AreEqual('', SectionNames(TDpccPlainHover.From(DataOf('{"dpcc": {"declaration": ""}}'), 'Unit1')));
  // Routine ohne XMLDoc: Parameter und Rückgabe aus der Signatur (wie vor S3 mit hover.signatureParams).
  mHover := TDpccPlainHover.From(DataOf('{"dpcc": {"declaration": "function Summe(A, B: Integer): Integer;", ' +
    '"kind": "routine"}}'), 'Unit1');
  Assert.AreEqual('Headline,Origin,Documentation', SectionNames(mHover));
  Assert.IsTrue(mHover.Doc.IsEmpty);
  Assert.IsTrue(mHover.DocContent.SignatureShown);
end;

procedure TDpccPlainHoverTests.LongSummaryIsShortenedOnlyForSpeech;
var
  mText: string;
  mHover: TDpccPlainHover;
  mIndex: Integer;
begin
  mText := '';
  for mIndex := 1 to 600 do
  begin
    mText := mText + 'Wort' + IntToStr(mIndex mod 10) + ' ';
  end;
  mHover := TDpccPlainHover.From(DataOf('{"dpcc": {"declaration": "procedure Lang;", "kind": "routine", ' +
    '"documentation": {"sections": [{"kind": "summary", "runs": [{"kind": "text", "text": "' + mText + '"}]}]}}}'),
    'Unit1');
  Assert.AreEqual('procedure  Lang', mHover.Headline);
  // Sprachausgabe: höchstens cMaxSummaryChars Zeichen, an einem Leerzeichen gekürzt und mit „…“.
  Assert.IsTrue(Length(mHover.Summary) <= TDpccPlainHover.cMaxSummaryChars + 2, IntToStr(Length(mHover.Summary)));
  Assert.IsTrue(mHover.Summary.EndsWith(' …'), mHover.Summary);
  // Die Doku selbst bleibt ganz; lange Doku scrollt im Tooltip.
  Assert.IsTrue(Length(mHover.Doc.Sections[0].Text) > TDpccPlainHover.cMaxSummaryChars);
  Assert.IsTrue(mHover.Spoken.EndsWith(' …'), 'Sprachausgabe mit gekürztem Kurztext');
end;

procedure TDpccPlainHoverTests.MarkdownGivesSignatureAndDocumentation;
var
  mHover: TDpccPlainHover;
begin
  // Fremder Server ohne "dpcc": Markdown mit Codezaun, Doku im zweiten Absatz.
  mHover := TDpccPlainHover.From(DataOf('{"contents": {"kind": "markdown", "value": ' +
    '"```pascal\nprocedure Zeichne(X: Integer); override;\n```\n\nZeichnet **den** Punkt `X`\nneu.\n\n' +
    'Zweiter Absatz."}}'), 'Unit1');
  Assert.AreEqual('procedure  Zeichne(X: Integer); override', mHover.Headline);
  Assert.AreEqual('Unit1', mHover.Origin);
  Assert.AreEqual('Zeichnet den Punkt X neu.', mHover.Summary);
  // Ganzer Klartext als Beschreibung (beide Absätze).
  Assert.IsFalse(mHover.Doc.IsEmpty);
  Assert.IsTrue(Pos('Zweiter Absatz.', mHover.Doc.Sections[0].Text) > 0, mHover.Doc.Sections[0].Text);
  Assert.AreEqual('Headline,Origin,Documentation', SectionNames(mHover));
end;

procedure TDpccPlainHoverTests.KindFromServerAndOrigin;
var
  mHover: TDpccPlainHover;
begin
  // Typ: Art aus "kind", Herkunft nur die Unit.
  mHover := TDpccPlainHover.From(DataOf('{"dpcc": {"declaration": "TFileStream = class(THandleStream)", ' +
    '"unit": "System.Classes", "kind": "class"}}'), 'Unit1');
  Assert.AreEqual('type  TFileStream = class(THandleStream)', mHover.Headline);
  Assert.AreEqual('System.Classes', mHover.Origin);
  // class function behält beide Wörter als Art.
  mHover := TDpccPlainHover.From(DataOf('{"dpcc": {"declaration": "class function Neu: TFoo; static;", ' +
    '"unit": "Werkzeug", "container": "TFoo", "kind": "method"}}'), 'Unit1');
  Assert.AreEqual('class function', mHover.Kind);
  Assert.AreEqual('Neu: TFoo; static', mHover.Signature);
  Assert.AreEqual('Werkzeug.TFoo', mHover.Origin);
  // Include-Datei bleibt hinter Unit.Typ.
  mHover := TDpccPlainHover.From(DataOf('{"dpcc": {"declaration": "Wert: Integer;", "unit": "Haupt (teil.inc)", ' +
    '"container": "TFoo", "kind": "field"}}'), 'Unit1');
  Assert.AreEqual('field  Wert: Integer', mHover.Headline);
  Assert.AreEqual('Haupt.TFoo (teil.inc)', mHover.Origin);
  // Über einem Unit-Namen keine Herkunft.
  mHover := TDpccPlainHover.From(DataOf('{"dpcc": {"declaration": "unit Werkzeug;"}}'), 'Unit1');
  Assert.AreEqual('unit  Werkzeug', mHover.Headline);
  Assert.AreEqual('', mHover.Origin);
end;

procedure TDpccPlainHoverTests.FullContentInOrder;
var
  mHover: TDpccPlainHover;
  mJson: string;
  mIndex: Integer;
begin
  // Alles, was der Tooltip vor S3 zeigte: Wert im Debugger, Kopfzeile, Herkunft, Fundort, Veraltung, Doku,
  // published-Mitglieder und Kette, in dieser Reihenfolge.
  mJson := '{"dpcc": {"declaration": "TKnopf = class(TButton)", "unit": "Knoepfe", "kind": "class", ' +
    '"origin": "VCL", "deprecation": "Veraltet: TNeuerKnopf nehmen", "file": "C:\\P\\Knoepfe.pas", "line": 19, ' +
    '"character": 2, "documentation": {"sections": [{"kind": "summary", "runs": [{"kind": "text", ' +
    '"text": "Ein Knopf."}]}, {"kind": "remarks", "runs": [{"kind": "text", "text": "Mit Rand."}]}]}, ' +
    '"chainOf": "TKnopf", "ancestors": [';
  for mIndex := 0 to 6 do
  begin
    if mIndex > 0 then
    begin
      mJson := mJson + ', ';
    end;
    mJson := mJson + Format('{"name": "T%d", "file": "C:\\P\\T%d.pas", "line": %d, "character": 2}',
      [mIndex, mIndex, mIndex]);
  end;
  mJson := mJson + '], "published": {"defaultProperty": "Items[I: Integer]: string", "members": [' +
    Member('Caption', 'string', 'TKnopf', False) + ', ' + Member('OnClick', 'TNotifyEvent', 'TControl', True) +
    ']}}}';
  mHover := TDpccPlainHover.From(DataOf(mJson), 'Unit1', Texts('Klasse'),
    TDpccDebugValue.Evaluated('Knopf1.Caption', '''OK'''));
  Assert.AreEqual('DebugValue,Headline,Origin,Location,Notes,Documentation,Members,Chain', SectionNames(mHover));
  Assert.AreEqual('''OK''', mHover.DebugText);
  Assert.AreEqual('type  TKnopf = class(TButton)', mHover.Headline);
  Assert.AreEqual('Klasse · VCL · Knoepfe', mHover.OriginLine);
  Assert.AreEqual('Knoepfe.pas : 20', mHover.Location);
  Assert.AreEqual('Veraltet: TNeuerKnopf nehmen', mHover.Deprecation);
  Assert.AreEqual(2, Integer(Length(mHover.Doc.Sections)), 'summary und Hinweise');
  Assert.AreEqual('published: 1 Properties · 1 Ereignisse', mHover.MembersSummary);
  Assert.AreEqual('Properties', mHover.Properties.Caption);
  Assert.AreEqual('Caption', mHover.Properties.Rows[0].Name);
  Assert.AreEqual('TKnopf', mHover.Properties.Rows[0].Declared);
  Assert.AreEqual('', mHover.Properties.More);
  Assert.AreEqual('OnClick', mHover.Events.Rows[0].Name);
  Assert.AreEqual('erkannt am Methodenzeiger-Typ, nicht am Namen', mHover.Events.Note);
  Assert.AreEqual('Items[I: Integer]', mHover.DefaultProperty, 'Standard-Property bis „]“');
  Assert.AreEqual('Standard-Property', mHover.DefaultPropertyLabel);
  Assert.AreEqual('geerbte aus der VCL nur mit VCL-Quellen im Index', mHover.MembersNote);
  // Kette: die ersten vier, „…“, das letzte.
  Assert.AreEqual('Vererbung', mHover.ChainCaption);
  Assert.AreEqual('T0 › T1 › T2 › T3 › … › T6', mHover.Chain);
  // Sprachausgabe beginnt mit dem Wert.
  Assert.IsTrue(mHover.Spoken.StartsWith('Knopf1.Caption = ''OK''. type  TKnopf'), mHover.Spoken);
  // Wert einer Konstante.
  mHover := TDpccPlainHover.From(DataOf('{"dpcc": {"declaration": "cMax = 48;", "kind": "constant", ' +
    '"value": "48"}}'), 'Unit1', Texts('Konstante'), Default(TDpccDebugValue));
  Assert.AreEqual('= 48', mHover.ValueLine);
  Assert.AreEqual('Headline,Origin,Notes', SectionNames(mHover));
end;

procedure TDpccPlainHoverTests.MembersAreShortened;
var
  mHover: TDpccPlainHover;
  mJson: string;
  mIndex: Integer;
begin
  // Neun Properties, fünf Ereignisse: wie vor S3 ohne Klick die ersten sieben bzw. vier, dann „+ n weitere“.
  mJson := '{"dpcc": {"declaration": "TListe = class(TPanel)", "kind": "class", "published": {"members": [' +
    '{"name": "Aktiv", "type": "Boolean", "default": "False", "defaultKind": "implicit", "declaringClass": "TListe"}';
  for mIndex := 2 to 9 do
  begin
    mJson := mJson + ', ' + Member('P' + IntToStr(mIndex), 'Integer', 'TPanel', False);
  end;
  for mIndex := 1 to 5 do
  begin
    mJson := mJson + ', ' + Member('OnE' + IntToStr(mIndex), 'TNotifyEvent', 'TControl', True);
  end;
  mJson := mJson + ', ' + Member('OnFremd', 'TMethodePtr', 'TListe', True) + ']}}}';
  mHover := TDpccPlainHover.From(DataOf(mJson), 'Unit1', Texts('Klasse'), Default(TDpccDebugValue));
  Assert.AreEqual(TDpccPlainHover.cPropertyRows, Integer(Length(mHover.Properties.Rows)));
  Assert.AreEqual('+ 2 weitere Properties', mHover.Properties.More);
  Assert.AreEqual('False (implizit)', mHover.Properties.Rows[0].DefaultText);
  Assert.AreEqual(TDpccPlainHover.cEventRows, Integer(Length(mHover.Events.Rows)));
  Assert.AreEqual('+ 2 weitere Ereignisse', mHover.Events.More);
  Assert.AreEqual('published: 9 Properties · 6 Ereignisse', mHover.MembersSummary);
  // Ein Ereignis, dessen Typ nicht auf Event endet, ist als Methodenzeiger kenntlich.
  mHover := TDpccPlainHover.From(DataOf('{"dpcc": {"declaration": "TListe = class(TPanel)", "kind": "class", ' +
    '"published": {"members": [' + Member('OnFremd', 'TMethodePtr', 'TListe', True) + ']}}}'), 'Unit1',
    Texts('Klasse'), Default(TDpccDebugValue));
  Assert.AreEqual('(of object)', mHover.Events.Rows[0].DefaultText);
  Assert.IsTrue(mHover.Properties.IsEmpty);
end;

procedure TDpccPlainHoverTests.DebugValueAlone;
var
  mHover: TDpccPlainHover;
begin
  // Kennt der Server den Bezeichner nicht, zeigt der Tooltip nur den Wert.
  mHover := TDpccPlainHover.From(Default(TDpccHoverData), 'Unit1', Texts(''), TDpccDebugValue.Evaluated('I', '3'));
  Assert.AreEqual('DebugValue', SectionNames(mHover));
  Assert.AreEqual('3', mHover.DebugText);
  Assert.AreEqual('I = 3', mHover.Spoken);
  // Der Debugger antwortet verzögert: „wird ausgewertet …“.
  mHover := TDpccPlainHover.From(Default(TDpccHoverData), 'Unit1', Texts(''), TDpccDebugValue.Pending('I'));
  Assert.AreEqual('wird ausgewertet …', mHover.DebugText);
  // Fehler ohne Erklärung: nichts zu zeigen.
  mHover := TDpccPlainHover.From(Default(TDpccHoverData), 'Unit1', Texts(''),
    TDpccDebugValue.Failed('I', 'Undeclared identifier'));
  Assert.AreEqual('', SectionNames(mHover));
end;

procedure TDpccPlainHoverTests.ClassReferenceShowsTargetType;
var
  mHover: TDpccPlainHover;
begin
  mHover := TDpccPlainHover.From(DataOf('{"dpcc": {"declaration": "TFrameKlasse = class of TBFrame", ' +
    '"kind": "classref", "chainOf": "TBFrame", "ancestors": [{"name": "TBFrame"}, {"name": "TFrame"}, ' +
    '{"name": "TObject"}]}}'), 'Unit1', Texts('Klassenreferenz'), Default(TDpccDebugValue));
  Assert.AreEqual('Zieltyp TBFrame', mHover.ChainCaption);
  Assert.AreEqual('TBFrame › TFrame › TObject', mHover.Chain);
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccPlainHoverTests);

end.
