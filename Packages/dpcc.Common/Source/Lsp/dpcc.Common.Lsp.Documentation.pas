unit dpcc.Common.Lsp.Documentation;

// XMLDoc für Hover, Parameter-Hint und Vervollständigung (#654).
//
// Load liest den ///-Kommentar über einer Deklaration (TXmlDoc) und löst
// <inheritdoc/> auf: ohne cref über den überschriebenen Member im nächsten
// Vorfahren bzw. in implementierten Interfaces, bei Typen über den Vorfahrtyp;
// mit cref über das genannte Symbol. Eigene Abschnitte gehen vor, fehlende
// kommen vom Vorfahren (TXmlDoc.Inherit), auch über mehrere Stufen.
//
// ToJson gibt die Abschnitte strukturiert aus: je Abschnitt Art, Name und
// Teilstücke. Verweise (cref) tragen den Fundort des Ziels (name, unit, file,
// line, character), damit das Plugin sie wie die Typnamen der Deklaration
// anklickbar macht (#588). HintsJson gibt die Anzeige-Einstellungen "hints"
// des Projekts an das Plugin weiter (dpcc.json vor den Plugin-Einstellungen).
//
// Auflösung im Editor L3: DocAt nimmt ohne ///-Kommentar den normalen Kommentarblock direkt über der Deklaration
// (//, { } oder (* *), ohne Leerzeile dazwischen) und den Kommentar am Ende der Zeile des Namens als
// Zusammenfassung. Nicht als Doku gelten Datei- und Lizenzköpfe (Block am Dateianfang, Copyright, Lizenz …),
// Trennlinien, ein einzelner Name wie { TFoo } und auskommentierter Code. Die Kommentare stehen nicht im Index;
// sie kommen bei Bedarf aus dem Text der einen Datei.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  dpcc.Common.Index.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Pascal.XmlDoc;

type
  /// <summary>Liefert den Text einer Datei; False, wenn sie nicht lesbar ist.</summary>
  TDocReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Einstellungen "hints" für das Dokument AUri (#654).</summary>
  TDocHintsProvider = reference to function(const AUri: string): THintSettings;

  /// <summary>Fundort eines cref (0-basiert, Position des Namens).</summary>
  TDocTarget = record
    Cref: string;
    Name: string;
    UnitName: string;
    FileName: string;
    Line: Integer;
    Character: Integer;
  end;

  TLspDocumentation = class
  public const
    /// <summary>Höchstens so viele Stufen inheritdoc hintereinander.</summary>
    cMaxInheritDepth = 8;
  private type
    TLoader = class
    private
      FResolver: TNameResolver;
      FReadText: TDocReadText;
      FLines: TDictionary<string, TArray<string>>;
      function LinesOf(const AFileName: string; out ALines: TArray<string>): Boolean;
      function DocOf(const ASymbol: TResolvedSymbol; ADepth: Integer): TXmlDoc;
      function OwnerOf(const ASymbol: TResolvedSymbol; out AOwner: TResolvedSymbol): Boolean;
      function BasesOf(const AOwner: TResolvedSymbol): TArray<TResolvedSymbol>;
      function AncestorDoc(const ASymbol: TResolvedSymbol; ADepth: Integer): TXmlDoc;
      function Resolve(const ASymbol: TResolvedSymbol; const ADoc: TXmlDoc; ADepth: Integer): TXmlDoc;
    public
      constructor Create(AResolver: TNameResolver; const AReadText: TDocReadText);
      destructor Destroy; override;
    end;
  public
    /// <summary>Kommentar über ALine (0-basiert) in ALines. Ist ASymbol gesetzt (Found) und steht
    /// &lt;inheritdoc/&gt; im Kommentar, kommt die Doku des Vorfahren bzw. des cref-Ziels dazu; AReadText
    /// liest deren Dateien.</summary>
    class function Load(AResolver: TNameResolver; const ASymbol: TResolvedSymbol; const ALines: TArray<string>;
      ALine: Integer; const AReadText: TDocReadText): TXmlDoc; static;
    /// <summary>Doku der Deklaration ab Zeile ALine (0-basiert), deren Name in Zeile ANameLine steht (L3): Der
    /// ///-Kommentar direkt darüber hat Vorrang; sonst der normale Kommentarblock direkt darüber und der
    /// Kommentar am Ende der Zeile ANameLine als Zusammenfassung (PlainComment). Leer ohne Kommentar.</summary>
    class function DocAt(const ALines: TArray<string>; ALine, ANameLine: Integer): TXmlDoc; static;
    /// <summary>Normaler Kommentar zur Deklaration wie in DocAt, ohne Kommentarzeichen; Absätze durch #10#10
    /// getrennt, Zeilen eines Absatzes durch #10. Ohne Datei- und Lizenzköpfe, Trennlinien, einzelne Namen
    /// ({ TFoo }) und auskommentierten Code; '' ohne.</summary>
    class function PlainComment(const ALines: TArray<string>; ALine, ANameLine: Integer): string; static;
    /// <summary>Fundorte aller cref in ADoc (Verweise und Exceptions), von AFromUnit bzw. AContainer aus
    /// aufgelöst; nicht auflösbare fehlen.</summary>
    class function Targets(AResolver: TNameResolver; const AFromUnit: TUnitIndex; const AContainer: string;
      const ADoc: TXmlDoc): TArray<TDocTarget>; static;
    /// <summary>Abschnitte und Teilstücke als JSON; Verweise mit Eintrag in ATargets tragen ihren Fundort.</summary>
    class function ToJson(const ADoc: TXmlDoc; const ATargets: TArray<TDocTarget>): TJSONObject; static;
    /// <summary>Anzeige-Einstellungen für das Plugin: {"full": …, "maxLines": …} (#654).</summary>
    class function HintsJson(const AHints: THintSettings): TJSONObject; static;
    /// <summary>Liest AOwnFile aus AOwnText (Editorinhalt, auch ungespeichert), andere Dateien über
    /// AReadText.</summary>
    class function Reader(const AOwnFile, AOwnText: string; const AReadText: TDocReadText): TDocReadText; static;
    /// <summary>Text in Zeilen (CRLF, LF oder CR); wie TTextLines.SplitLines.</summary>
    class function SplitLines(const AText: string): TArray<string>; static;
  end;

implementation

uses
  System.StrUtils,
  dpcc.Text.Lines,
  dpcc.Common.Pascal.Contract,
  dpcc.Common.Pascal.Lexer,
  dpcc.Common.Lsp.IdeUnits;

const
  /// <summary>Höchstens so viele Zeilen hat ein Kommentarblock über einer Deklaration; längere sind meist Datei-
  /// oder Abschnittsköpfe (L3).</summary>
  cMaxCommentLines = 40;
  /// <summary>Wörter von Lizenz- und Dateiköpfen (klein).</summary>
  cHeaderWords: array[0..7] of string = ('copyright', 'license', 'licence', 'lizenz', 'all rights reserved',
    'alle rechte vorbehalten', '©', 'spdx-');

/// <summary>Text einer //-Zeile ohne die Schrägstriche (auch /// und //&lt;).</summary>
function LineCommentText(const AText: string): string;
begin
  Result := AText;
  while StartsStr('/', Result) do
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  // "//< Text" (Kommentar zum Element davor), nicht aber "<b>" am Anfang.
  if StartsStr('< ', Result) or (Result = '<') then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  Result := Trim(Result);
end;

/// <summary>Text eines Kommentar-Tokens ohne //, { } bzw. (* *).</summary>
function CommentTokenText(const AText: string): string;
begin
  if StartsStr('//', AText) then
  begin
    Exit(LineCommentText(AText));
  end;
  Result := AText;
  if StartsStr('{', Result) then
  begin
    Result := Copy(Result, 2, MaxInt);
    if EndsStr('}', Result) then
    begin
      Result := Copy(Result, 1, Length(Result) - 1);
    end;
  end
  else if StartsStr('(*', Result) then
  begin
    Result := Copy(Result, 3, MaxInt);
    if EndsStr('*)', Result) then
    begin
      Result := Copy(Result, 1, Length(Result) - 2);
    end;
  end;
  Result := Trim(Result);
end;

/// <summary>Zeile aus Satzzeichen wie //----- oder { ===== } (Trennlinie, keine Doku).</summary>
function IsSeparatorLine(const AText: string): Boolean;
var
  mChar: Char;
begin
  Result := Trim(AText) <> '';
  for mChar in AText do
  begin
    if not CharInSet(mChar, [' ', #9, '-', '=', '*', '#', '~', '_', '/', '+', '.', '<', '>', '|']) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Sieht die Kommentarzeile AText wie auskommentierter Pascal-Code aus? Endet auf ";" mit Code-Zeichen
/// (FList.Free; X := 1; Foo(A);) oder ohne Leerzeichen (inherited;), enthält ":=", ist begin/end/try … oder
/// "if … then", "for/while/with … do".</summary>
function LooksLikeCode(const AText: string): Boolean;
var
  mText: string;
begin
  mText := LowerCase(Trim(AText));
  Result := (Pos(':=', mText) > 0) or MatchStr(mText, ['begin', 'end', 'end.', 'try', 'finally', 'except',
    'else', 'repeat', 'begin;']) or StartsStr('{$', mText) or StartsStr('(*$', mText) or
    (StartsStr('if ', mText) and EndsStr(' then', mText)) or
    ((StartsStr('for ', mText) or StartsStr('while ', mText) or StartsStr('with ', mText)) and EndsStr(' do', mText));
  if not Result and EndsStr(';', mText) then
  begin
    Result := (Pos(' ', mText) = 0) or (Pos('(', mText) > 0) or (Pos(':', mText) > 0) or (Pos('.', mText) > 0) or
      (Pos('[', mText) > 0) or (Pos('^', mText) > 0) or (Pos('=', mText) > 0);
  end;
end;

/// <summary>Enthält AText ein Wort aus Lizenz- und Dateiköpfen?</summary>
function HasHeaderWord(const AText: string): Boolean;
var
  mText, mWord: string;
begin
  mText := LowerCase(AText);
  for mWord in cHeaderWords do
  begin
    if Pos(mWord, mText) > 0 then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Hinweis der Formularvorlage wie { Private-Deklarationen } bzw. { Public declarations } (L3)? Er gehört
/// zum Abschnitt, nicht zum ersten Mitglied darunter.</summary>
function IsTemplateRemark(const AText: string): Boolean;
const
  cSections: array[0..3] of string = ('private', 'protected', 'public', 'published');
  cWords: array[0..1] of string = ('deklarationen', 'declarations');
var
  mText, mSection, mWord: string;
begin
  mText := LowerCase(Trim(AText));
  if mText.EndsWith('.') then
  begin
    mText := Copy(mText, 1, Length(mText) - 1);
  end;
  for mSection in cSections do
  begin
    for mWord in cWords do
    begin
      if (mText = mSection + '-' + mWord) or (mText = mSection + ' ' + mWord) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Nur ein Name wie "TFoo" oder "TFoo.Bar" (Markierung { TFoo } der Klassenvervollständigung)?</summary>
function IsSingleName(const AText: string): Boolean;
var
  mChar: Char;
begin
  Result := AText <> '';
  for mChar in AText do
  begin
    if not (CharInSet(mChar, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) or (Ord(mChar) > 127)) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Block-Kommentar { … } bzw. (* … *), der in Zeile AEnd endet und am Anfang einer Zeile beginnt;
/// AStart ist seine erste Zeile, AParts sein Inhalt je Zeile. False bei Direktiven ({$IFDEF}), bei Code vor dem
/// Kommentar und ohne Anfang innerhalb von cMaxCommentLines Zeilen.</summary>
function BlockCommentAbove(const ALines: TArray<string>; AEnd: Integer; out AStart: Integer;
  out AParts: TArray<string>): Boolean;
var
  mOpen, mClose, mText: string;
  mIndex: Integer;
begin
  Result := False;
  AStart := AEnd;
  AParts := nil;
  mText := Trim(ALines[AEnd]);
  if EndsStr('}', mText) then
  begin
    mOpen := '{';
    mClose := '}';
  end
  else if EndsStr('*)', mText) then
  begin
    mOpen := '(*';
    mClose := '*)';
  end
  else
  begin
    Exit;
  end;
  // Die öffnende Klammer steht am Anfang einer Zeile; dazwischen weder öffnende noch schließende.
  mIndex := AEnd;
  while True do
  begin
    mText := Trim(ALines[mIndex]);
    if StartsStr(mOpen, mText) then
    begin
      Break;
    end;
    if (Pos(mOpen, mText) > 0) or ((mIndex < AEnd) and (Pos(mClose, mText) > 0)) or (mIndex = 0) or
      (AEnd - mIndex >= cMaxCommentLines) then
    begin
      Exit;
    end;
    Dec(mIndex);
  end;
  if StartsStr(mOpen + '$', mText) or ((mIndex < AEnd) and (Pos(mClose, mText) > 0)) or
    (Pos(mOpen, Copy(mText, Length(mOpen) + 1, MaxInt)) > 0) then
  begin
    Exit;
  end;
  AStart := mIndex;
  for mIndex := AStart to AEnd do
  begin
    mText := Trim(ALines[mIndex]);
    if mIndex = AStart then
    begin
      mText := Copy(mText, Length(mOpen) + 1, MaxInt);
    end;
    if mIndex = AEnd then
    begin
      mText := Copy(mText, 1, Length(mText) - Length(mClose));
    end;
    // Zeilen im Stil " * Text" ohne den Stern.
    mText := Trim(mText);
    if (mIndex > AStart) and (StartsStr('* ', mText) or (mText = '*')) then
    begin
      mText := Trim(Copy(mText, 2, MaxInt));
    end;
    AParts := AParts + [mText];
  end;
  Result := True;
end;

/// <summary>Inhalt der Kommentarzeilen direkt über ALine, von oben nach unten: //-Zeilen und Block-Kommentare,
/// Attribute ([Weak]) zwischen Kommentar und Deklaration übersprungen; eine Leerzeile beendet den Block. AFirst ist
/// seine erste Zeile. nil ohne Block oder wenn er länger als cMaxCommentLines ist.</summary>
function CommentLinesAbove(const ALines: TArray<string>; ALine: Integer; out AFirst: Integer): TArray<string>;
var
  mIndex, mStart: Integer;
  mText: string;
  mParts: TArray<string>;
begin
  Result := nil;
  AFirst := ALine;
  mIndex := ALine - 1;
  if mIndex > High(ALines) then
  begin
    mIndex := High(ALines);
  end;
  while mIndex >= 0 do
  begin
    mText := Trim(ALines[mIndex]);
    if StartsStr('//', mText) then
    begin
      Result := [LineCommentText(mText)] + Result;
      AFirst := mIndex;
      Dec(mIndex);
    end
    else if (Length(Result) = 0) and StartsStr('[', mText) then
    begin
      Dec(mIndex);
    end
    else if (mText <> '') and BlockCommentAbove(ALines, mIndex, mStart, mParts) then
    begin
      Result := mParts + Result;
      AFirst := mStart;
      mIndex := mStart - 1;
    end
    else
    begin
      Break;
    end;
    if Length(Result) > cMaxCommentLines then
    begin
      Exit(nil);
    end;
  end;
end;

/// <summary>Steht über AFirst nur Leeres? Dann ist der Block der Kopf der Datei (auch einer .inc-Datei).</summary>
function IsFileStart(const ALines: TArray<string>; AFirst: Integer): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := AFirst - 1 downto 0 do
  begin
    if Trim(ALines[mIndex]) <> '' then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Absätze aus den Zeilen ABlock (ab Zeile AFirst): Trennlinien und Code-Zeilen fallen weg, Leerzeilen
/// trennen Absätze. nil bei Datei- und Lizenzköpfen, bei überwiegend Code und bei einem einzelnen Namen.</summary>
function BlockParagraphs(const ALines, ABlock: TArray<string>; AFirst: Integer): TArray<string>;
var
  mLine, mParagraph: string;
  mCode, mText: Integer;
begin
  Result := nil;
  if (Length(ABlock) = 0) or IsFileStart(ALines, AFirst) or HasHeaderWord(string.Join(' ', ABlock)) then
  begin
    Exit;
  end;
  mCode := 0;
  mText := 0;
  for mLine in ABlock do
  begin
    if (Trim(mLine) = '') or IsSeparatorLine(mLine) then
    begin
      Continue;
    end;
    if LooksLikeCode(mLine) then
    begin
      Inc(mCode);
    end
    else
    begin
      Inc(mText);
    end;
  end;
  // Überwiegend Code: auskommentierter Code, keine Doku.
  if (mText = 0) or (mCode > mText) then
  begin
    Exit;
  end;
  mParagraph := '';
  for mLine in ABlock do
  begin
    if Trim(mLine) = '' then
    begin
      if mParagraph <> '' then
      begin
        Result := Result + [mParagraph];
      end;
      mParagraph := '';
    end
    else if not (IsSeparatorLine(mLine) or LooksLikeCode(mLine)) then
    begin
      mParagraph := mParagraph + IfThen(mParagraph <> '', #10) + Trim(mLine);
    end;
  end;
  if mParagraph <> '' then
  begin
    Result := Result + [mParagraph];
  end;
  if (Length(Result) = 1) and (IsSingleName(Result[0]) or IsTemplateRemark(Result[0])) then
  begin
    Result := nil;
  end;
end;

/// <summary>Kommentar am Ende von ALine hinter Code, ohne Kommentarzeichen; '' ohne, bei Code dahinter, bei
/// Trennlinien, Lizenzwörtern und auskommentiertem Code.</summary>
function LineEndComment(const ALine: string): string;
var
  mToken: TPascalToken;
  mCode: Boolean;
begin
  Result := '';
  mCode := False;
  for mToken in TPascalLexer.Tokenize(ALine) do
  begin
    if mToken.Kind = TPascalTokenKind.Comment then
    begin
      if mCode then
      begin
        Result := Result + IfThen(Result <> '', ' ') + CommentTokenText(mToken.Text);
      end;
    end
    else if mToken.Kind <> TPascalTokenKind.Directive then
    begin
      // Kommentar mitten in der Zeile ("procedure P({ Wert } A: Integer);") zählt nicht.
      Result := '';
      mCode := True;
    end;
  end;
  if IsSeparatorLine(Result) or LooksLikeCode(Result) or HasHeaderWord(Result) then
  begin
    Result := '';
  end;
end;

/// <summary>Absätze des normalen Kommentars zur Deklaration ab ALine mit dem Namen in ANameLine.</summary>
function PlainParagraphs(const ALines: TArray<string>; ALine, ANameLine: Integer): TArray<string>;
var
  mFirst: Integer;
  mBlock: TArray<string>;
  mTrailing: string;
begin
  Result := nil;
  if (ALine >= 0) and (ALine <= High(ALines)) then
  begin
    // Erst den Block lesen: AFirst kommt aus CommentLinesAbove.
    mBlock := CommentLinesAbove(ALines, ALine, mFirst);
    Result := BlockParagraphs(ALines, mBlock, mFirst);
  end;
  if (ANameLine >= 0) and (ANameLine <= High(ALines)) then
  begin
    mTrailing := LineEndComment(ALines[ANameLine]);
    if mTrailing <> '' then
    begin
      Result := Result + [mTrailing];
    end;
  end;
end;

/// <summary>AText als Text für TXmlDoc.Parse: &amp;, &lt; und &gt; maskiert.</summary>
function XmlText(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
end;

{ TLspDocumentation.TLoader }

constructor TLspDocumentation.TLoader.Create(AResolver: TNameResolver; const AReadText: TDocReadText);
begin
  inherited Create;
  FResolver := AResolver;
  FReadText := AReadText;
  FLines := TDictionary<string, TArray<string>>.Create;
end;

destructor TLspDocumentation.TLoader.Destroy;
begin
  FLines.Free;
  inherited;
end;

function TLspDocumentation.TLoader.LinesOf(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  mText: string;
begin
  if FLines.TryGetValue(UpperCase(AFileName), ALines) then
  begin
    Exit(True);
  end;
  Result := Assigned(FReadText) and FReadText(AFileName, mText);
  if not Result then
  begin
    Exit;
  end;
  ALines := TLspDocumentation.SplitLines(mText);
  FLines.AddOrSetValue(UpperCase(AFileName), ALines);
end;

function TLspDocumentation.TLoader.DocOf(const ASymbol: TResolvedSymbol; ADepth: Integer): TXmlDoc;
var
  mLines: TArray<string>;
begin
  Result := Default(TXmlDoc);
  if (ASymbol.FileName = '') or not LinesOf(ASymbol.FileName, mLines) then
  begin
    Exit;
  end;
  // Ohne ///-Kommentar beim Vorfahren auch dessen normaler Kommentar (L3).
  Result := TLspDocumentation.DocAt(mLines, ASymbol.Range.StartPos.Line, ASymbol.SelectionRange.StartPos.Line);
  if Result.InheritDoc then
  begin
    Result := Resolve(ASymbol, Result, ADepth);
  end;
end;

function TLspDocumentation.TLoader.OwnerOf(const ASymbol: TResolvedSymbol; out AOwner: TResolvedSymbol): Boolean;
var
  mOwnerUnit: TUnitIndex;
begin
  // Ein Typ ist sein eigener Träger, ein Member gehört zum Typ ASymbol.Container.
  if ASymbol.Container = '' then
  begin
    AOwner := ASymbol;
    Result := ASymbol.IsType;
  end
  else
  begin
    Result := FResolver.DeclaringUnit(ASymbol, mOwnerUnit) and
      FResolver.ResolveTypeFrom(mOwnerUnit, ASymbol.Container, AOwner);
  end;
end;

function TLspDocumentation.TLoader.BasesOf(const AOwner: TResolvedSymbol): TArray<TResolvedSymbol>;
var
  mTypeUnit: TUnitIndex;
  mBase: TResolvedSymbol;
  mIndex: Integer;
begin
  // Vorfahr zuerst, dann die implementierten Interfaces.
  Result := nil;
  // Helfer: nur der Vorfahr-Helfer (#848); der Zieltyp am Ende von Ancestors ist kein Vorfahr.
  if AOwner.SymbolKind = TIndexSymbolKind.HelperType then
  begin
    if FResolver.Queries.HelperParent(AOwner, mBase) then
    begin
      Result := [mBase];
    end;
    Exit;
  end;
  if FResolver.AncestorOf(AOwner, mBase) then
  begin
    Result := Result + [mBase];
  end;
  if not FResolver.DeclaringUnit(AOwner, mTypeUnit) then
  begin
    Exit;
  end;
  for mIndex := 1 to High(AOwner.Ancestors) do
  begin
    if FResolver.ResolveTypeFrom(mTypeUnit, AOwner.Ancestors[mIndex], mBase) then
    begin
      Result := Result + [mBase];
    end;
  end;
end;

function TLspDocumentation.TLoader.AncestorDoc(const ASymbol: TResolvedSymbol; ADepth: Integer): TXmlDoc;
var
  mOwner, mBase, mCandidate: TResolvedSymbol;
begin
  Result := Default(TXmlDoc);
  if (ADepth > TLspDocumentation.cMaxInheritDepth) or not OwnerOf(ASymbol, mOwner) then
  begin
    Exit;
  end;
  for mBase in BasesOf(mOwner) do
  begin
    mCandidate := mBase;
    if (ASymbol.Container <> '') and not FResolver.DeclaredMember(mBase, ASymbol.Name, mCandidate) then
    begin
      Continue;
    end;
    Result := DocOf(mCandidate, ADepth + 1);
    // Ohne eigene Doku dort weiter oben suchen.
    if Result.IsEmpty then
    begin
      Result := AncestorDoc(mCandidate, ADepth + 1);
    end;
    if not Result.IsEmpty then
    begin
      Exit;
    end;
  end;
end;

function TLspDocumentation.TLoader.Resolve(const ASymbol: TResolvedSymbol; const ADoc: TXmlDoc;
  ADepth: Integer): TXmlDoc;
var
  mFromUnit: TUnitIndex;
  mTarget: TResolvedSymbol;
  mBase: TXmlDoc;
begin
  mBase := Default(TXmlDoc);
  if ADepth <= TLspDocumentation.cMaxInheritDepth then
  begin
    if ADoc.InheritCref <> '' then
    begin
      if FResolver.DeclaringUnit(ASymbol, mFromUnit) and
        FResolver.LocateCref(mFromUnit, ASymbol.Container, ADoc.InheritCref, mTarget) then
      begin
        mBase := DocOf(mTarget, ADepth + 1);
      end;
    end
    else
    begin
      mBase := AncestorDoc(ASymbol, ADepth);
    end;
  end;
  Result := ADoc.Inherit(mBase);
end;

{ TLspDocumentation }

class function TLspDocumentation.SplitLines(const AText: string): TArray<string>;
begin
  Result := TTextLines.SplitLines(AText);
end;

class function TLspDocumentation.HintsJson(const AHints: THintSettings): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('maxLines', TJSONNumber.Create(AHints.XmlDocMaxLines));
end;

class function TLspDocumentation.Reader(const AOwnFile, AOwnText: string;
  const AReadText: TDocReadText): TDocReadText;
begin
  Result :=
    function(const AName: string; out AText: string): Boolean
    begin
      if SameText(AName, AOwnFile) then
      begin
        AText := AOwnText;
        Exit(True);
      end;
      Result := Assigned(AReadText) and AReadText(AName, AText);
    end;
end;

class function TLspDocumentation.Load(AResolver: TNameResolver; const ASymbol: TResolvedSymbol;
  const ALines: TArray<string>; ALine: Integer; const AReadText: TDocReadText): TXmlDoc;
var
  mLoader: TLoader;
begin
  Result := TXmlDoc.Parse(TXmlDoc.CommentAbove(ALines, ALine));
  if not Result.InheritDoc or (AResolver = nil) or not ASymbol.Found then
  begin
    Exit;
  end;
  mLoader := TLoader.Create(AResolver, AReadText);
  try
    Result := mLoader.Resolve(ASymbol, Result, 0);
  finally
    mLoader.Free;
  end;
end;

class function TLspDocumentation.PlainComment(const ALines: TArray<string>; ALine, ANameLine: Integer): string;
begin
  Result := string.Join(#10#10, PlainParagraphs(ALines, ALine, ANameLine));
end;

class function TLspDocumentation.DocAt(const ALines: TArray<string>; ALine, ANameLine: Integer): TXmlDoc;
var
  mXml, mParagraph: string;
begin
  // /// hat Vorrang; der normale Kommentar kommt nur ohne ihn (L3).
  mXml := TXmlDoc.CommentAbove(ALines, ALine);
  if Trim(mXml) = '' then
  begin
    mXml := '';
    for mParagraph in PlainParagraphs(ALines, ALine, ANameLine) do
    begin
      if mXml <> '' then
      begin
        mXml := mXml + '<para/>';
      end;
      mXml := mXml + XmlText(mParagraph);
    end;
  end;
  Result := TXmlDoc.Parse(mXml);
end;

class function TLspDocumentation.Targets(AResolver: TNameResolver; const AFromUnit: TUnitIndex;
  const AContainer: string; const ADoc: TXmlDoc): TArray<TDocTarget>;
var
  mSeen: TDictionary<string, Boolean>;
  mSection: TXmlDocSection;
  mRun: TXmlDocRun;

  procedure Add(const ACref: string);
  var
    mSymbol: TResolvedSymbol;
    mTarget: TDocTarget;
  begin
    if (ACref = '') or mSeen.ContainsKey(ACref) then
    begin
      Exit;
    end;
    mSeen.Add(ACref, True);
    if not AResolver.LocateCref(AFromUnit, AContainer, ACref, mSymbol) then
    begin
      Exit;
    end;
    mTarget.Cref := ACref;
    mTarget.Name := mSymbol.Name;
    mTarget.UnitName := mSymbol.UnitName;
    mTarget.FileName := mSymbol.FileName;
    mTarget.Line := mSymbol.SelectionRange.StartPos.Line;
    mTarget.Character := mSymbol.SelectionRange.StartPos.Character;
    Result := Result + [mTarget];
  end;

begin
  Result := nil;
  if AResolver = nil then
  begin
    Exit;
  end;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mSection in ADoc.Sections do
    begin
      if mSection.Kind = TXmlDocSectionKind.Exception then
      begin
        Add(mSection.Name);
      end;
      for mRun in mSection.Runs do
      begin
        if mRun.Kind = TXmlDocRunKind.Ref then
        begin
          Add(mRun.Target);
        end;
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

function FindTarget(const ATargets: TArray<TDocTarget>; const ACref: string; out ATarget: TDocTarget): Boolean;
var
  mTarget: TDocTarget;
begin
  for mTarget in ATargets do
  begin
    if mTarget.Cref = ACref then
    begin
      ATarget := mTarget;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Name, Unit und Fundort; Ersatz-Units der IDE (dpcc-ide:…) gibt es nicht als Datei: ohne Fundort,
/// also ohne Sprungziel.</summary>
procedure AddLocation(AObject: TJSONObject; const ATarget: TDocTarget);
begin
  AObject.AddPair('name', ATarget.Name);
  if ATarget.UnitName <> '' then
  begin
    AObject.AddPair('unit', ATarget.UnitName);
  end;
  if TIdeUnits.IsIdePath(ATarget.FileName) then
  begin
    Exit;
  end;
  AObject.AddPair('file', ATarget.FileName);
  AObject.AddPair('line', TJSONNumber.Create(ATarget.Line));
  AObject.AddPair('character', TJSONNumber.Create(ATarget.Character));
end;

/// <summary>Ein Teilstück als JSON; ein Verweis mit Eintrag in ATargets trägt seinen Fundort.</summary>
function RunJson(const ARun: TXmlDocRun; const ATargets: TArray<TDocTarget>): TJSONObject;
var
  mTarget: TDocTarget;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', TXmlDoc.RunKindName(ARun.Kind));
  if ARun.Text <> '' then
  begin
    Result.AddPair('text', ARun.Text);
  end;
  if ARun.Target <> '' then
  begin
    Result.AddPair('target', ARun.Target);
  end;
  if TXmlDocStyle.Bold in ARun.Styles then
  begin
    Result.AddPair('bold', TJSONTrue.Create);
  end;
  if TXmlDocStyle.Italic in ARun.Styles then
  begin
    Result.AddPair('italic', TJSONTrue.Create);
  end;
  if ARun.Level > 0 then
  begin
    Result.AddPair('level', TJSONNumber.Create(ARun.Level));
  end;
  if (ARun.Kind = TXmlDocRunKind.Ref) and FindTarget(ATargets, ARun.Target, mTarget) then
  begin
    AddLocation(Result, mTarget);
  end;
end;

class function TLspDocumentation.ToJson(const ADoc: TXmlDoc; const ATargets: TArray<TDocTarget>): TJSONObject;
var
  mSections, mRuns: TJSONArray;
  mSection: TXmlDocSection;
  mRun: TXmlDocRun;
  mItem, mRefItem: TJSONObject;
  mTarget: TDocTarget;
begin
  Result := TJSONObject.Create;
  mSections := TJSONArray.Create;
  Result.AddPair('sections', mSections);
  for mSection in ADoc.Sections do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('kind', TXmlDoc.SectionName(mSection.Kind));
    if mSection.Name <> '' then
    begin
      mItem.AddPair('name', mSection.Name);
    end;
    if (mSection.Kind = TXmlDocSectionKind.Exception) and FindTarget(ATargets, mSection.Name, mTarget) then
    begin
      mRefItem := TJSONObject.Create;
      AddLocation(mRefItem, mTarget);
      mItem.AddPair('ref', mRefItem);
    end;
    mRuns := TJSONArray.Create;
    for mRun in mSection.Runs do
    begin
      mRuns.AddElement(RunJson(mRun, ATargets));
    end;
    mItem.AddPair('runs', mRuns);
    mSections.AddElement(mItem);
  end;
end;

end.
