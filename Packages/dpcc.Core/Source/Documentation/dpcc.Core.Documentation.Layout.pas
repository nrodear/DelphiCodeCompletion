unit dpcc.Core.Documentation.Layout;

// Satz der XMLDoc (#654, #770) für Hover-Tooltip und Detailpanel, ohne VCL: Aus
// der strukturierten Doku werden Zeilen mit Stücken (Text, Schrift, Farbe,
// Position), Klickflächen für Verweise, Links und „Mehr/Weniger anzeigen“ und
// der Klartext zum Kopieren. Gemessen wird über einen Rückruf; so lässt sich der
// Satz ohne Fenster testen.
//
//   - Zugeklappt: Beschreibung, dazu „Mehr anzeigen ▾“ und gedämpft, was
//     verborgen ist („3 Parameter · Rückgabe · 1 Ausnahme · Hinweis“, Ausnahmen
//     in Fehlerfarbe). Ohne weitere Abschnitte kein Schalter.
//   - Aufgeklappt: Abschnitte unter Überschriften in Kapitälchen (gedämpft, mit
//     Linie bis zum rechten Rand) in fester Reihenfolge PARAMETER, TYPPARAMETER,
//     RÜCKGABE, WERT, AUSNAHMEN, HINWEISE, BEISPIEL; SIEHE AUCH in einer Zeile
//     mit den Verweisen; am Ende „Weniger anzeigen ▴“.
//   - Parameter dreispaltig in der Reihenfolge der Signatur: Name (Editorschrift,
//     halbfett, Akzent), Art und Typ (gedämpft), Beschreibung; ohne <param>
//     „nicht dokumentiert“ (kursiv, gedämpft); ein <param>, den die Signatur
//     nicht kennt, am Ende in Warnfarbe.
//   - Rückgabe: Ergebnistyp (Schlüsselwortfarbe) und Text; ohne <returns> nur der
//     Typ. Ausnahmen: Klasse in Fehlerfarbe, anklickbar mit Fundort.
//   - Läufe: Code in der Editorschrift, paramref schlicht in der Editorschrift
//     fett (seit S8 ohne Pille), Verweise in Akzentfarbe, unterstrichen und
//     anklickbar, wenn der Server den Fundort kennt; Links öffnen den Browser;
//     Codeblöcke eingefärbt mit dünnem, eckigem Rahmen ohne Füllfläche; Listen mit hängendem Einzug je Ebene;
//     Tabellen zweispaltig. Eine Listenmarke mit Ziel (Kästchen einer
//     Checkliste in der Issue-Vorschau, #1273) ist ein Link in Akzentfarbe.
//   - Begründungen (#1123) unter BEGRÜNDUNG nach allen XMLDoc-Abschnitten: je
//     Eintrag Marke (Editorschrift, halbfett, Akzent) und Text. Zugeklappt die
//     ersten MaxRationale, der Rest hinter „Mehr anzeigen“ („2 weitere
//     Begründungen“). ADR-Verweise mit Fundort öffnen die Datei, Issue-Links
//     "issue:312" die Adresse aus TDpccDocIssueLinks; ohne Tracker bleiben sie
//     Text.
//   - TDpccDocExpandState hält „wie zuletzt“ (hints.xmlDocExpand = last) je
//     Fläche (Tooltip, Detailpanel) für die Sitzung.
// Stufen (LOOK2): Die Stücke tragen eine Rolle (TDpccDocColor), keine feste Farbe; Überschriften, Parameternamen,
// Rückgabetyp und Verweise färbt der Zeichner über TDpccDocTypeset.ColorOf in den Doc*-Farben der Stufe.

interface

uses
  System.SysUtils,
  dpcc.Core.Documentation.Contract,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  TDpccDocFont = (UI, Mono);

  /// <summary>Rolle eines Stücks; die Farbe dazu liefert TDpccDocTypeset.ColorOf aus der Stufe (LOOK2): Heading
  /// (Überschriften), Param (Parameternamen), TypeName (Rückgabe- und Werttyp), Link (Verweise und Links).
  /// </summary>
  TDpccDocColor = (Text, Muted, Accent, Error, Keyword, StringLiteral, Comment, Number, Warn, Heading, Param,
    TypeName, Link);

  TDpccDocFace = record
    Font: TDpccDocFont;
    Bold: Boolean;
    Italic: Boolean;
    /// <summary>Kleinere Schrift der Überschriften.</summary>
    Small: Boolean;
    class function Create(AFont: TDpccDocFont): TDpccDocFace; overload; static;
    class function Create(AFont: TDpccDocFont; ABold: Boolean): TDpccDocFace; overload; static;
    class function Create(AFont: TDpccDocFont; ABold, AItalic: Boolean): TDpccDocFace; overload; static;
    /// <summary>Überschrift: UI, halbfett, klein.</summary>
    class function Heading: TDpccDocFace; static;
    function SameAs(const AOther: TDpccDocFace): Boolean;
  end;

  /// <summary>Breite von AText in Pixeln in der Schrift AFace.</summary>
  TDpccDocMeasure = reference to function(const AText: string; const AFace: TDpccDocFace): Integer;

  TDpccDocMetrics = record
    /// <summary>Zeilenhöhe der UI-Schrift bzw. der Editorschrift.</summary>
    LineHeight: Integer;
    MonoHeight: Integer;
    /// <summary>Einzug je Listenebene.</summary>
    Indent: Integer;
    /// <summary>Abstand zwischen den Spalten.</summary>
    ColumnGap: Integer;
    ParagraphGap: Integer;
    SectionGap: Integer;
    /// <summary>Innenabstand der Codefläche links und rechts.</summary>
    CodePad: Integer;
    /// <summary>Werte für 96 dpi, mit AScale (Pixel je Zoll / 96) multipliziert.</summary>
    class function Create(ALineHeight, AMonoHeight: Integer; AScale: Double): TDpccDocMetrics; static;
  end;

  /// <summary>Überschriften und Texte in der Sprache der IDE.</summary>
  TDpccDocLabels = record
    Params: string;
    TypeParams: string;
    Returns: string;
    Value: string;
    Exceptions: string;
    Remarks: string;
    Example: string;
    SeeAlso: string;
    Rationale: string;
    Undocumented: string;
    More: string;
    Less: string;
    /// <summary>Verborgenes im zugeklappten Zustand; Count* mit %d.</summary>
    CountParam: string;
    CountParams: string;
    CountTypeParam: string;
    CountTypeParams: string;
    CountException: string;
    CountExceptions: string;
    CountRationale: string;
    CountRationales: string;
    ItemReturns: string;
    ItemValue: string;
    ItemRemarks: string;
    ItemExample: string;
    ItemSeeAlso: string;
    class function ForLanguage(ALanguage: TDpccLanguage): TDpccDocLabels; static;
    class function German: TDpccDocLabels; static;
    /// <summary>Beschriftungen in der Sprache der Oberfläche (TDpccTextLanguage).</summary>
    class function Current: TDpccDocLabels; static;
  end;

  TDpccDocSpan = record
    Text: string;
    Left: Integer;
    Width: Integer;
    Face: TDpccDocFace;
    Color: TDpccDocColor;
    Underline: Boolean;
    /// <summary>Index in Links; -1 ohne.</summary>
    Link: Integer;
    /// <summary>Anfang im Klartext (0-basiert).</summary>
    TextStart: Integer;
    function Right: Integer;
  end;

  TDpccDocLine = record
    /// <summary>Abstand über der Zeile.</summary>
    GapBefore: Integer;
    Top: Integer;
    Height: Integer;
    Spans: TArray<TDpccDocSpan>;
    /// <summary>Überschrift: Linie ab RuleFrom bis zum rechten Rand.</summary>
    Rule: Boolean;
    RuleFrom: Integer;
    /// <summary>Codezeile: gerahmter Bereich ab ShadeLeft (1 px, eckig, ohne Füllfläche).</summary>
    Shaded: Boolean;
    ShadeLeft: Integer;
    function Bottom: Integer;
  end;

  TDpccDocLinkKind = (Ref, Url, Toggle);

  TDpccDocLink = record
    Kind: TDpccDocLinkKind;
    /// <summary>Ref: Ziel mit Fundort.</summary>
    Target: TDpccDocTarget;
    /// <summary>Url: Adresse.</summary>
    Url: string;
  end;

  /// <summary>Zustand „wie zuletzt“ (#770) je Fläche für die Sitzung; nach dem Start zugeklappt.</summary>
  TDpccDocExpandState = class
  private class var
    FLast: array[TDpccDocSurface] of Boolean;
  public
    /// <summary>Aufgeklappt beim Öffnen nach AExpand.</summary>
    class function Initial(AExpand: TDpccDocExpand; ASurface: TDpccDocSurface): Boolean; static;
    /// <summary>Nach einem Klick auf „Mehr“ bzw. „Weniger anzeigen“.</summary>
    class procedure Remember(ASurface: TDpccDocSurface; AExpanded: Boolean); static;
    /// <summary>Wie nach dem Start (Tests).</summary>
    class procedure Reset; static;
  end;

  /// <summary>Issue-Links "issue:312" der Begründungen (#1123): Die IDE meldet den Tracker der Willkommensseite
  /// (#765) an und beim Entladen wieder ab. Nur im Hauptthread.</summary>
  TDpccDocIssueLinks = class
  public const
    cPrefix = 'issue:';
  private class var
    FResolver: TDpccDocIssueUrl;
  public
    class procedure SetResolver(const AResolver: TDpccDocIssueUrl); static;
    class procedure Clear; static;
    /// <summary>Adresse zu ATarget ("issue:312"); '' ohne Tracker oder bei anderen Zielen.</summary>
    class function Url(const ATarget: string): string; static;
  end;

  TDpccDocLayout = record
  public const
    /// <summary>Begründungen, die zugeklappt sichtbar sind.</summary>
    cMaxRationale = 3;
    /// <summary>Tabellen: Spalte der Begriffe höchstens so viel Prozent der Breite.</summary>
    cTermColumnPercent = 45;
    /// <summary>Parameter: Namens- und Typspalte höchstens so viel Prozent der Breite.</summary>
    cNameColumnPercent = 30;
    cTypeColumnPercent = 35;
    cSeparator = ' · ';
  public
    Lines: TArray<TDpccDocLine>;
    Links: TArray<TDpccDocLink>;
    /// <summary>Klartext aller Zeilen (CRLF), Grundlage der Markierung.</summary>
    Text: string;
    Height: Integer;
    /// <summary>Mehr als die Beschreibung: Es gibt „Mehr/Weniger anzeigen“.</summary>
    Collapsible: Boolean;
    Expanded: Boolean;
    function IsEmpty: Boolean;
    /// <summary>Zeile an AY; -1 außerhalb.</summary>
    function LineAt(AY: Integer): Integer;
    /// <summary>Link unter (AX, AY); -1 ohne.</summary>
    function LinkAt(AX, AY: Integer): Integer;
    /// <summary>Anfang der ersten Zeile ab ALine mit Text; sonst Ende des Klartexts.</summary>
    function FirstTextFrom(ALine: Integer): Integer;
    /// <summary>Erste Zeile unterhalb von AY; -1 ohne.</summary>
    function LineBelow(AY: Integer): Integer;
    /// <summary>Stelle im Klartext unter (AX, AY) für die Markierung; oberhalb 0, unterhalb Ende.</summary>
    function PositionAt(AX, AY: Integer; const AMeasure: TDpccDocMeasure): Integer;
    /// <summary>Pixelbereich [ALeft, ARight) des Stücks für den Klartextbereich [AFrom, ATo); False ohne
    /// Überschneidung.</summary>
    function SpanRange(const ASpan: TDpccDocSpan; AFrom, ATo: Integer; const AMeasure: TDpccDocMeasure;
      out ALeft, ARight: Integer): Boolean;
    /// <summary>Markierter Klartext; Reihenfolge von AFrom und ATo beliebig.</summary>
    function Selected(AFrom, ATo: Integer): string;
    /// <summary>Höhe der ersten ALines Zeilen samt Abständen (0 = alle).</summary>
    function HeightOfLines(ALines: Integer): Integer;
  end;

implementation

uses
  System.Math;

{ TDpccDocFace }

class function TDpccDocFace.Create(AFont: TDpccDocFont): TDpccDocFace;
begin
  Result := Create(AFont, False, False);
end;

class function TDpccDocFace.Create(AFont: TDpccDocFont; ABold: Boolean): TDpccDocFace;
begin
  Result := Create(AFont, ABold, False);
end;

class function TDpccDocFace.Create(AFont: TDpccDocFont; ABold, AItalic: Boolean): TDpccDocFace;
begin
  Result.Font := AFont;
  Result.Bold := ABold;
  Result.Italic := AItalic;
  Result.Small := False;
end;

class function TDpccDocFace.Heading: TDpccDocFace;
begin
  Result := Create(TDpccDocFont.UI, True, False);
  Result.Small := True;
end;

function TDpccDocFace.SameAs(const AOther: TDpccDocFace): Boolean;
begin
  Result := (Font = AOther.Font) and (Bold = AOther.Bold) and (Italic = AOther.Italic) and
    (Small = AOther.Small);
end;

{ TDpccDocMetrics }

class function TDpccDocMetrics.Create(ALineHeight, AMonoHeight: Integer; AScale: Double): TDpccDocMetrics;
begin
  Result.LineHeight := ALineHeight;
  Result.MonoHeight := AMonoHeight;
  Result.Indent := Round(14 * AScale);
  Result.ColumnGap := Round(8 * AScale);
  Result.ParagraphGap := Round(5 * AScale);
  Result.SectionGap := Round(6 * AScale);
  Result.CodePad := Round(6 * AScale);
end;

type
  /// <summary>Beschriftungen von TDpccDocLabels in Feldreihenfolge.</summary>
  TDocLabel = (Params, TypeParams, Returns, Value, Exceptions, Remarks, Example, SeeAlso, Rationale, Undocumented,
    More, Less, CountParam, CountParams, CountTypeParam, CountTypeParams, CountException, CountExceptions,
    CountRationale, CountRationales, ItemReturns, ItemValue, ItemRemarks, ItemExample, ItemSeeAlso);

const
  cDocLabels: array[TDpccLanguage, TDocLabel] of string = (
    ('PARAMETER',
     'TYPPARAMETER',
     'RÜCKGABE',
     'WERT',
     'AUSNAHMEN',
     'HINWEISE',
     'BEISPIEL',
     'SIEHE AUCH',
     'BEGRÜNDUNG',
     'nicht dokumentiert',
     'Mehr anzeigen ▾',
     'Weniger anzeigen ▴',
     '%d Parameter',
     '%d Parameter',
     '%d Typparameter',
     '%d Typparameter',
     '%d Ausnahme',
     '%d Ausnahmen',
     '%d weitere Begründung',
     '%d weitere Begründungen',
     'Rückgabe',
     'Wert',
     'Hinweis',
     'Beispiel',
     'Siehe auch'),
    ('PARAMETERS',
     'TYPE PARAMETERS',
     'RETURNS',
     'VALUE',
     'EXCEPTIONS',
     'REMARKS',
     'EXAMPLE',
     'SEE ALSO',
     'RATIONALE',
     'not documented',
     'Show more ▾',
     'Show less ▴',
     '%d parameter',
     '%d parameters',
     '%d type parameter',
     '%d type parameters',
     '%d exception',
     '%d exceptions',
     '%d more rationale',
     '%d more rationales',
     'Returns',
     'Value',
     'Remark',
     'Example',
     'See also'));

{ TDpccDocLabels }

class function TDpccDocLabels.ForLanguage(ALanguage: TDpccLanguage): TDpccDocLabels;
begin
  Result.Params := cDocLabels[ALanguage, TDocLabel.Params];
  Result.TypeParams := cDocLabels[ALanguage, TDocLabel.TypeParams];
  Result.Returns := cDocLabels[ALanguage, TDocLabel.Returns];
  Result.Value := cDocLabels[ALanguage, TDocLabel.Value];
  Result.Exceptions := cDocLabels[ALanguage, TDocLabel.Exceptions];
  Result.Remarks := cDocLabels[ALanguage, TDocLabel.Remarks];
  Result.Example := cDocLabels[ALanguage, TDocLabel.Example];
  Result.SeeAlso := cDocLabels[ALanguage, TDocLabel.SeeAlso];
  Result.Rationale := cDocLabels[ALanguage, TDocLabel.Rationale];
  Result.Undocumented := cDocLabels[ALanguage, TDocLabel.Undocumented];
  Result.More := cDocLabels[ALanguage, TDocLabel.More];
  Result.Less := cDocLabels[ALanguage, TDocLabel.Less];
  Result.CountParam := cDocLabels[ALanguage, TDocLabel.CountParam];
  Result.CountParams := cDocLabels[ALanguage, TDocLabel.CountParams];
  Result.CountTypeParam := cDocLabels[ALanguage, TDocLabel.CountTypeParam];
  Result.CountTypeParams := cDocLabels[ALanguage, TDocLabel.CountTypeParams];
  Result.CountException := cDocLabels[ALanguage, TDocLabel.CountException];
  Result.CountExceptions := cDocLabels[ALanguage, TDocLabel.CountExceptions];
  Result.CountRationale := cDocLabels[ALanguage, TDocLabel.CountRationale];
  Result.CountRationales := cDocLabels[ALanguage, TDocLabel.CountRationales];
  Result.ItemReturns := cDocLabels[ALanguage, TDocLabel.ItemReturns];
  Result.ItemValue := cDocLabels[ALanguage, TDocLabel.ItemValue];
  Result.ItemRemarks := cDocLabels[ALanguage, TDocLabel.ItemRemarks];
  Result.ItemExample := cDocLabels[ALanguage, TDocLabel.ItemExample];
  Result.ItemSeeAlso := cDocLabels[ALanguage, TDocLabel.ItemSeeAlso];
end;

class function TDpccDocLabels.German: TDpccDocLabels;
begin
  Result := ForLanguage(TDpccLanguage.German);
end;

class function TDpccDocLabels.Current: TDpccDocLabels;
begin
  Result := ForLanguage(TDpccTextLanguage.Current);
end;

{ TDpccDocSpan }

function TDpccDocSpan.Right: Integer;
begin
  Result := Left + Width;
end;

{ TDpccDocLine }

function TDpccDocLine.Bottom: Integer;
begin
  Result := Top + Height;
end;

{ TDpccDocExpandState }

class function TDpccDocExpandState.Initial(AExpand: TDpccDocExpand; ASurface: TDpccDocSurface): Boolean;
begin
  case AExpand of
    TDpccDocExpand.Collapsed:
      Result := False;
    TDpccDocExpand.Expanded:
      Result := True;
  else
    Result := FLast[ASurface];
  end;
end;

class procedure TDpccDocExpandState.Remember(ASurface: TDpccDocSurface; AExpanded: Boolean);
begin
  FLast[ASurface] := AExpanded;
end;

class procedure TDpccDocExpandState.Reset;
var
  mSurface: TDpccDocSurface;
begin
  for mSurface := Low(TDpccDocSurface) to High(TDpccDocSurface) do
  begin
    FLast[mSurface] := False;
  end;
end;

{ TDpccDocIssueLinks }

class procedure TDpccDocIssueLinks.SetResolver(const AResolver: TDpccDocIssueUrl);
begin
  FResolver := AResolver;
end;

class procedure TDpccDocIssueLinks.Clear;
begin
  FResolver := nil;
end;

class function TDpccDocIssueLinks.Url(const ATarget: string): string;
begin
  Result := '';
  if not ATarget.StartsWith(cPrefix, True) or not Assigned(FResolver) then
  begin
    Exit;
  end;
  Result := FResolver(Copy(ATarget, Length(cPrefix) + 1, MaxInt));
  // Nur Web-Adressen, wie beim Öffnen aus „Meine Issues“.
  if not (Result.StartsWith('https://', True) or Result.StartsWith('http://', True)) then
  begin
    Result := '';
  end;
end;

{ TDpccDocLayout }

function TDpccDocLayout.IsEmpty: Boolean;
begin
  Result := Length(Lines) = 0;
end;

function TDpccDocLayout.LineAt(AY: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Lines) do
  begin
    if (AY >= Lines[mIndex].Top - Lines[mIndex].GapBefore) and (AY < Lines[mIndex].Bottom) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TDpccDocLayout.LinkAt(AX, AY: Integer): Integer;
var
  mLine: Integer;
  mSpan: TDpccDocSpan;
begin
  Result := -1;
  mLine := LineAt(AY);
  if (mLine < 0) or (AY < Lines[mLine].Top) then
  begin
    Exit;
  end;
  for mSpan in Lines[mLine].Spans do
  begin
    if (mSpan.Link >= 0) and (AX >= mSpan.Left) and (AX < mSpan.Right) then
    begin
      Exit(mSpan.Link);
    end;
  end;
end;

/// <summary>Stelle im Stück unter AX: Zeichen, deren Mitte links von AX liegt, gehören dazu.</summary>
function SpanPosition(const ASpan: TDpccDocSpan; AX: Integer; const AMeasure: TDpccDocMeasure): Integer;
var
  mCount: Integer;
begin
  if AX < ASpan.Left then
  begin
    Exit(ASpan.TextStart);
  end;
  mCount := 0;
  while (mCount < Length(ASpan.Text)) and
    (ASpan.Left + (AMeasure(Copy(ASpan.Text, 1, mCount), ASpan.Face) +
    AMeasure(Copy(ASpan.Text, 1, mCount + 1), ASpan.Face)) div 2 <= AX) do
  begin
    Inc(mCount);
  end;
  Result := ASpan.TextStart + mCount;
end;

/// <summary>Stelle in einer Zeile mit Stücken; links davor Anfang, rechts dahinter Ende.</summary>
function LinePosition(const ASpans: TArray<TDpccDocSpan>; AX: Integer; const AMeasure: TDpccDocMeasure): Integer;
var
  mSpan: TDpccDocSpan;
begin
  if AX < ASpans[0].Left then
  begin
    Exit(ASpans[0].TextStart);
  end;
  for mSpan in ASpans do
  begin
    if AX < mSpan.Right then
    begin
      Exit(SpanPosition(mSpan, AX, AMeasure));
    end;
  end;
  mSpan := ASpans[High(ASpans)];
  Result := mSpan.TextStart + Length(mSpan.Text);
end;

function TDpccDocLayout.FirstTextFrom(ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := ALine to High(Lines) do
  begin
    if Length(Lines[mIndex].Spans) > 0 then
    begin
      Exit(Lines[mIndex].Spans[0].TextStart);
    end;
  end;
  Result := Length(Text);
end;

function TDpccDocLayout.LineBelow(AY: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Lines) do
  begin
    if AY < Lines[mIndex].Top then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TDpccDocLayout.PositionAt(AX, AY: Integer; const AMeasure: TDpccDocMeasure): Integer;
var
  mLine: Integer;
begin
  if (Length(Lines) = 0) or (AY < Lines[0].Top - Lines[0].GapBefore) then
  begin
    Exit(0);
  end;
  mLine := LineAt(AY);
  if mLine < 0 then
  begin
    // Unterhalb bzw. zwischen Zeilen: Ende bzw. nächste Zeile.
    mLine := LineBelow(AY);
    if mLine < 0 then
    begin
      Exit(Length(Text));
    end;
    Exit(PositionAt(AX, Lines[mLine].Top, AMeasure));
  end;
  // Leere Zeile: Anfang der nächsten Zeile mit Text.
  if Length(Lines[mLine].Spans) = 0 then
  begin
    Exit(FirstTextFrom(mLine + 1));
  end;
  Result := LinePosition(Lines[mLine].Spans, AX, AMeasure);
end;

function TDpccDocLayout.SpanRange(const ASpan: TDpccDocSpan; AFrom, ATo: Integer;
  const AMeasure: TDpccDocMeasure; out ALeft, ARight: Integer): Boolean;
var
  mFrom, mTill: Integer;
begin
  mFrom := Max(AFrom, ASpan.TextStart) - ASpan.TextStart;
  mTill := Min(ATo, ASpan.TextStart + Length(ASpan.Text)) - ASpan.TextStart;
  Result := mTill > mFrom;
  if not Result then
  begin
    Exit;
  end;
  ALeft := ASpan.Left + AMeasure(Copy(ASpan.Text, 1, mFrom), ASpan.Face);
  ARight := ASpan.Left + AMeasure(Copy(ASpan.Text, 1, mTill), ASpan.Face);
end;

function TDpccDocLayout.Selected(AFrom, ATo: Integer): string;
var
  mFrom, mTill: Integer;
begin
  mFrom := EnsureRange(Min(AFrom, ATo), 0, Length(Text));
  mTill := EnsureRange(Max(AFrom, ATo), 0, Length(Text));
  Result := Copy(Text, mFrom + 1, mTill - mFrom);
end;

function TDpccDocLayout.HeightOfLines(ALines: Integer): Integer;
begin
  if (ALines <= 0) or (ALines >= Length(Lines)) then
  begin
    Exit(Height);
  end;
  Result := Lines[ALines - 1].Bottom;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Documentation.Layout', cDocLabels[TDpccLanguage.German],
    cDocLabels[TDpccLanguage.English]);

end.
