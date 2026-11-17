unit dpcc.Common.Lsp.Hover.Lookup;

// Sammelt den Inhalt eines Hovers (THoverInfo) an einer Stelle.
//
// Die Deklaration ist die erste Zeile der Fundstelle ab ihrem Anfang. Der
// Dokumentationskommentar sind die ///-Zeilen direkt darüber, zerlegt von
// TXmlDoc samt <inheritdoc/> (TLspDocumentation, #654). Bei Methoden mit
// getrennter Implementierung gilt die Deklaration (TLspDefinition).
// Bei Klassen folgen die published-Properties und Ereignisse samt geerbter
// (TPublishedMembers). Auf einem Attribut (#119) zusätzlich die Konstruktoren
// der Attributklasse, bei Argumenten die mit passender Parameterzahl.
// Zahlenliterale zeigen ihre Schreibweisen, Bezeichner von System ohne
// Quelltext die eingebaute Beschreibung (#880), Unit-Namen den Dateinamen
// und den Inhalt der Unit (#1921, TLspHoverUnitContents).
//
// Auflösung im Editor L3: Zieht sich eine Deklaration über mehrere Zeilen, zeigt
// der Hover den vollen Kopf (TIndexFiles.SourceSignature, gelesen nur aus den
// Zeilen der Deklaration). Ohne ///-Kommentar gelten der normale Kommentarblock
// darüber und der Kommentar am Zeilenende (TLspDocumentation.DocAt); aus der
// Deklarationszeile fällt der Kommentar am Ende weg. Inline-Variablen ohne Typ
// (var X := …) zeigen den abgeleiteten Typ, Konstanten den Wert einfacher
// Ausdrücke (cMax = cBase * 2) samt Konstanten aus dem Index. Deklarationen aus
// nicht geltenden Zweigen ($IFDEF) liest der Hover aus ihrer Datei, wenn die
// Namensauflösung sie nicht kennt.

interface

uses
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Lsp.Hover.Info;

type
  TLspHoverLookup = class
  public
    /// <summary>Hover-Inhalt an APosition; ATreeText ist der Text von ATree, ADelphiVersion der Release-Name
    /// ('' = neueste; seit Rückbau R3 ohne DocWiki-Links ungenutzt).</summary>
    class function InfoAt(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText, AFileName: string;
      const APosition: TTextPosition; const ADelphiVersion: string): THoverInfo; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  dpcc.Common.Index.Contract,
  dpcc.Common.Index.Files,
  dpcc.Common.Index.Extractor,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Semantics.SystemIntrinsics,
  dpcc.Common.Semantics.Attributes,
  dpcc.Common.Pascal.Contract,
  dpcc.Common.Pascal.Lexer,
  dpcc.Common.Pascal.TreeCache,
  dpcc.Common.Pascal.XmlDoc,
  dpcc.Common.Dfm.FormInfo,
  dpcc.Common.Lsp.Definition,
  dpcc.Common.Lsp.Documentation,
  dpcc.Common.Lsp.MessageHandlers,
  dpcc.Common.Lsp.HoverValues,
  dpcc.Common.Lsp.HoverTypes,
  dpcc.Common.Lsp.PublishedMembers,
  dpcc.Common.Lsp.Hover.UnitContents,
  dpcc.Common.Diagnostics.RequestScope,
  dpcc.Text.Lines,
  dpcc.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLookupText = (PossibleElement, PossibleElements, Inactive, InactiveCondition);

const
  cTexts: array[TLookupText] of TDpccText = (
    (De: ' · 1 mögliches Element'; En: ' · 1 possible element'),
    (De: ' · %s mögliche Elemente'; En: ' · %s possible elements'),
    (De: '**Nicht aktiv** unter der aktuellen Konfiguration'; En: '**Inactive** under the current configuration'),
    (De: '**Nicht aktiv** unter der aktuellen Konfiguration (Bedingung: %s)';
     En: '**Inactive** under the current configuration (condition: %s)'));

{$SCOPEDENUMS OFF}

const
  /// <summary>So viele Zeilen ab dem Anfang einer Deklaration liest der Hover für ihren vollen Kopf höchstens
  /// (L3); Klassen und Routinen brauchen nur die ersten (TIndexFiles.SourceSignature).</summary>
  cSignatureLines = 200;
  /// <summary>Längere Köpfe kürzt der Hover mit " …" (L3).</summary>
  cMaxDeclaration = 1000;
  /// <summary>Arten, deren Kopf nur die erste Zeile ist (Rumpf folgt); ohne abschließendes ";".</summary>
  cBodyKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType];
  /// <summary>Arten mit Rumpf hinter dem Kopf (Routinen).</summary>
  cRoutineKinds = [TIndexSymbolKind.Routine, TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_];

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
  begin
    Result := A.Line - B.Line;
  end
  else
  begin
    Result := A.Character - B.Character;
  end;
end;

/// <summary>Deklaration von ARange bis zum Ende der letzten Zeile (dort stehen Direktiven wie deprecated).</summary>
function DeclarationText(const ALines: TArray<string>; const ARange: TTextRange): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := ARange.StartPos.Line to ARange.EndPos.Line do
  begin
    if (mLine < 0) or (mLine > High(ALines)) then
    begin
      Break;
    end;
    if mLine = ARange.StartPos.Line then
    begin
      Result := Copy(ALines[mLine], ARange.StartPos.Character + 1, MaxInt);
    end
    else
    begin
      Result := Result + ' ' + Trim(ALines[mLine]);
    end;
  end;
end;

/// <summary>AText ohne Kommentar am Zeilenende ("FWert: Integer; // mm" ergibt "FWert: Integer;"); ein Kommentar
/// mitten in der Zeile bleibt (L3).</summary>
function WithoutLineEndComment(const AText: string): string;
var
  mToken: TPascalToken;
  mCut: Integer;
begin
  mCut := -1;
  for mToken in TPascalLexer.Tokenize(AText) do
  begin
    if mToken.Kind = TPascalTokenKind.Comment then
    begin
      if mCut < 0 then
      begin
        mCut := mToken.Offset;
      end;
    end
    else
    begin
      mCut := -1;
    end;
  end;
  Result := AText;
  if mCut > 0 then
  begin
    Result := TrimRight(Copy(AText, 1, mCut));
  end;
end;

/// <summary>AText ohne Leerraum zwischen aufeinanderfolgenden String- und Zeichenliteralen: Die Signatur setzt
/// zwischen alle Tokens ein Leerzeichen, "'a' + #13 #10" wäre aber kein gültiger Ausdruck mehr.</summary>
function GluedLiterals(const AText: string): string;
var
  mToken: TPascalToken;
  mPos: Integer;
  mPreviousLiteral, mLiteral: Boolean;
begin
  Result := '';
  mPos := 1;
  mPreviousLiteral := False;
  for mToken in TPascalLexer.Tokenize(AText) do
  begin
    mLiteral := mToken.Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral];
    if not (mPreviousLiteral and mLiteral and (Trim(Copy(AText, mPos, mToken.Offset + 1 - mPos)) = '')) then
    begin
      Result := Result + Copy(AText, mPos, mToken.Offset + 1 - mPos);
    end;
    Result := Result + mToken.Text;
    mPos := mToken.Offset + Length(mToken.Text) + 1;
    mPreviousLiteral := mLiteral;
  end;
  Result := Result + Copy(AText, mPos, MaxInt);
end;

/// <summary>Volle Signatur von ASymbol (TIndexFiles.SourceSignature, L1), gelesen nur aus den Zeilen seiner
/// Deklaration in ALines statt aus dem ganzen Text. ATruncated, wenn die Deklaration länger als cSignatureLines
/// Zeilen ist und ihr Kopf daher nicht vollständig sein kann. '' ohne Ergebnis.</summary>
function SignatureFromLines(const ALines: TArray<string>; const ASymbol: TIndexSymbol;
  out ATruncated: Boolean): string;
var
  mFirst, mLast, mLine, mEndCharacter: Integer;
  mText: string;
  mSymbol: TIndexSymbol;
begin
  Result := '';
  ATruncated := False;
  if ASymbol.Unavailable then
  begin
    // Nur die Zeile ist bekannt; SourceSignature liest ab ihrem Anfang.
    mFirst := ASymbol.SelectionRange.StartPos.Line;
    mLast := mFirst + cSignatureLines;
  end
  else
  begin
    mFirst := ASymbol.Range.StartPos.Line;
    mLast := ASymbol.Range.EndPos.Line;
  end;
  if (mFirst < 0) or (mFirst > High(ALines)) then
  begin
    Exit;
  end;
  mEndCharacter := ASymbol.Range.EndPos.Character;
  if mLast > mFirst + cSignatureLines then
  begin
    mLast := mFirst + cSignatureLines;
    mEndCharacter := MaxInt div 2;
    ATruncated := not ASymbol.Unavailable and not (ASymbol.Kind in cBodyKinds + cRoutineKinds);
  end;
  if mLast > High(ALines) then
  begin
    mLast := High(ALines);
    mEndCharacter := MaxInt div 2;
  end;
  mText := '';
  for mLine := mFirst to mLast do
  begin
    if mLine > mFirst then
    begin
      mText := mText + #10;
    end;
    mText := mText + ALines[mLine];
  end;
  // Positionen auf den Ausschnitt verschieben: seine erste Zeile ist Zeile 0.
  mSymbol := ASymbol;
  mSymbol.SelectionRange := TTextRange.Create(ASymbol.SelectionRange.StartPos.Line - mFirst,
    ASymbol.SelectionRange.StartPos.Character, ASymbol.SelectionRange.EndPos.Line - mFirst,
    ASymbol.SelectionRange.EndPos.Character);
  if not ASymbol.Unavailable then
  begin
    mSymbol.Range := TTextRange.Create(0, ASymbol.Range.StartPos.Character, mLast - mFirst, mEndCharacter);
  end;
  Result := GluedLiterals(TIndexFiles.SourceSignature(mText, mSymbol));
end;

/// <summary>ASignature (ohne ";") als Kopf im Hover: mit ";" wie in der Quelle, bei Typen mit Rumpf ohne; die
/// Standard-Property mit "; default"; zu lange bzw. abgeschnittene Köpfe mit " …".</summary>
function DisplayedSignature(const ASymbol: TIndexSymbol; const ASignature: string; ATruncated: Boolean): string;
begin
  Result := ASignature;
  if (ASymbol.Kind = TIndexSymbolKind.Property_) and ASymbol.IsDefault then
  begin
    Result := Result + '; default';
  end;
  if ATruncated or (Length(Result) > cMaxDeclaration) then
  begin
    Result := Copy(Result, 1, cMaxDeclaration) + ' …';
  end
  else if not (ASymbol.Kind in cBodyKinds) then
  begin
    Result := Result + ';';
  end;
end;

/// <summary>Zeichen eines Bezeichners (auch Unicode-Buchstaben)?</summary>
function IsNameChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

/// <summary>Bezeichner an APosition in AText ('' ohne).</summary>
function NameAt(const AText: string; const APosition: TTextPosition): string;
var
  mLines: TArray<string>;
  mLine: string;
  mStart, mEnd: Integer;
begin
  Result := '';
  mLines := TTextLines.SplitLines(AText);
  if (APosition.Line < 0) or (APosition.Line > High(mLines)) then
  begin
    Exit;
  end;
  mLine := mLines[APosition.Line];
  mStart := APosition.Character + 1;
  if (mStart < 1) or (mStart > Length(mLine)) or not IsNameChar(mLine[mStart]) then
  begin
    Exit;
  end;
  mEnd := mStart;
  while (mStart > 1) and IsNameChar(mLine[mStart - 1]) do
  begin
    Dec(mStart);
  end;
  while (mEnd < Length(mLine)) and IsNameChar(mLine[mEnd + 1]) do
  begin
    Inc(mEnd);
  end;
  Result := Copy(mLine, mStart, mEnd - mStart + 1);
  if CharInSet(Result[1], ['0'..'9']) then
  begin
    Result := '';
  end;
end;

/// <summary>Typ für die Anzeige hinter einer Inline-Variablen: der Name, bei gebundenen Typparametern samt
/// Typargumenten (TList&lt;Integer&gt;).</summary>
function TypeDisplay(const AType: TResolvedSymbol): string;
var
  mParam, mBinding, mArgs: string;
  mFound: Boolean;
begin
  Result := AType.Name;
  if (AType.TypeParams = '') or (Length(AType.Bindings) = 0) then
  begin
    Exit;
  end;
  mArgs := '';
  for mParam in AType.TypeParams.Split([',']) do
  begin
    mFound := False;
    for mBinding in AType.Bindings do
    begin
      if SameText(Copy(mBinding, 1, Pos('=', mBinding) - 1), Trim(mParam)) then
      begin
        mArgs := mArgs + IfThen(mArgs <> '', ', ') + Copy(mBinding, Pos('=', mBinding) + 1, MaxInt);
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Exit;
    end;
  end;
  Result := Result + '<' + mArgs + '>';
end;

/// <summary>Ordinalzahl eines Aufzählungswerts: Position im Typ, ohne explizite Werte.</summary>
function EnumOrdinal(const AUnit: TUnitIndex; const AMember: TIndexSymbol): Integer;
var
  mSymbol: TIndexSymbol;
begin
  Result := 0;
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.EnumMember) and SameText(mSymbol.Container, AMember.Container) then
    begin
      if mSymbol.SelectionRange.StartPos = AMember.SelectionRange.StartPos then
      begin
        Exit;
      end;
      Inc(Result);
    end;
  end;
end;

/// <summary>Zahl der Werte der Aufzählung ABaseType laut Index; -1, wenn sie sich nicht auflösen lässt.</summary>
function EnumMemberCount(AResolver: TNameResolver; const AUnit: TUnitIndex; const ABaseType: string): Integer;
var
  mResolved: TResolvedSymbol;
  mEnumUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  Result := -1;
  if not (AResolver.ResolveTypeFrom(AUnit, ABaseType, mResolved) and
    (mResolved.SymbolKind = TIndexSymbolKind.EnumType) and AResolver.DeclaringUnit(mResolved, mEnumUnit)) then
  begin
    Exit;
  end;
  Result := 0;
  for mSymbol in mEnumUnit.Symbols do
  begin
    if (mSymbol.Kind = TIndexSymbolKind.EnumMember) and SameText(mSymbol.Container, mResolved.Name) then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Bei Mengentypen "set of TBar · 4 mögliche Elemente" (#38); Aufzählungen über den Index gezählt.
/// '' bei anderen Typen.</summary>
function SetTypeValue(AResolver: TNameResolver; const AUnit: TUnitIndex; const ADeclaration: string): string;
var
  mBaseType: string;
  mCount: Integer;
begin
  Result := '';
  if not THoverValues.SetBaseType(ADeclaration, mBaseType) then
  begin
    Exit;
  end;
  mCount := THoverValues.BaseTypeCount(mBaseType);
  if mCount < 0 then
  begin
    mCount := EnumMemberCount(AResolver, AUnit, mBaseType);
  end;
  Result := 'set of ' + mBaseType;
  if mCount = 1 then
  begin
    Result := Result + cTexts[TLookupText.PossibleElement].Text;
  end
  else if mCount >= 0 then
  begin
    Result := Result + cTexts[TLookupText.PossibleElements].Fmt([IntToStr(mCount)]);
  end;
end;

/// <summary>Text der Formulardatei neben AUnitFile (.dfm vor .fmx); die geöffnete Datei AOpenFile aus AOpenText.
/// '' ohne Formulardatei.</summary>
function FormText(const AUnitFile, AOpenFile, AOpenText: string; const AReadText: TDocReadText;
  out AFormFile: string): string;
var
  mExtension: string;
begin
  Result := '';
  for mExtension in TArray<string>.Create('.dfm', '.fmx') do
  begin
    AFormFile := ChangeFileExt(AUnitFile, mExtension);
    if SameText(AFormFile, AOpenFile) then
    begin
      Result := AOpenText;
    end
    else if not (Assigned(AReadText) and AReadText(AFormFile, Result)) then
    begin
      Result := '';
    end;
    if Result <> '' then
    begin
      Break;
    end;
  end;
end;


/// <summary>Konstruktor ASymbol steht in der Deklaration der Klasse AClass (Zeilen dazwischen).</summary>
function IsOwnConstructor(const ASymbol, AClass: TIndexSymbol; const ALines: TArray<string>): Boolean;
begin
  Result := (ASymbol.Kind = TIndexSymbolKind.Constructor_) and SameText(ASymbol.Container, AClass.Name) and
    (ASymbol.Range.StartPos.Line > AClass.Range.StartPos.Line) and
    (ASymbol.Range.StartPos.Line < AClass.Range.EndPos.Line) and (ASymbol.Range.StartPos.Line <= High(ALines));
end;

/// <summary>Konstruktoren von AClass in AUnit, die AArgCount Argumente annehmen; passt keiner, alle.</summary>
function AttributeConstructors(const AUnit: TUnitIndex; const AClass: TIndexSymbol; const ALines: TArray<string>;
  AArgCount: Integer): string;
var
  mSymbol: TIndexSymbol;
  mAll, mMatching, mLine: string;
begin
  mAll := '';
  mMatching := '';
  for mSymbol in AUnit.Symbols do
  begin
    if IsOwnConstructor(mSymbol, AClass, ALines) then
    begin
      mLine := Trim(ALines[mSymbol.Range.StartPos.Line]);
      mAll := mAll + IfThen(mAll <> '', #10) + mLine;
      if (AArgCount >= mSymbol.MinArgs) and (AArgCount <= mSymbol.MaxArgs) then
      begin
        mMatching := mMatching + IfThen(mMatching <> '', #10) + mLine;
      end;
    end;
  end;
  Result := IfThen(mMatching <> '', mMatching, mAll);
end;

/// <summary>Leser für TPublishedMembers: die eigene Datei kommt aus dem Editor, nicht von der Platte. Eigene
/// Routine, damit die anonyme Methode nur diese Kopien einfängt.</summary>
function MemberReader(const AFileName, ATreeText: string; const AReadText: TDocReadText): TMemberReadText;
begin
  Result :=
    function(const AName: string; out AText: string): Boolean
    begin
      Result := SameText(AName, AFileName);
      if Result then
      begin
        AText := ATreeText;
      end
      else
      begin
        Result := Assigned(AReadText) and AReadText(AName, AText);
      end;
    end;
end;

/// <summary>Derselbe Leser für TMessageHandlers.</summary>
function MessageReader(const AFileName, ATreeText: string; const AReadText: TDocReadText): TMessageReadText;
begin
  Result :=
    function(const AName: string; out AText: string): Boolean
    begin
      Result := SameText(AName, AFileName);
      if Result then
      begin
        AText := ATreeText;
      end
      else
      begin
        Result := Assigned(AReadText) and AReadText(AName, AText);
      end;
    end;
end;

type
  /// <summary>Ein Hover-Lauf: Felder statt Locals, Schritte als Methoden.</summary>
  THoverLookupRun = class
  private
    FSource: THoverSource;
    FTree: TSyntaxTree;
    FTreeText: string;
    FFileName: string;
    FPosition: TTextPosition;
    FDelphiVersion: string;
    FInfo: THoverInfo;
    /// <summary>Erstes Ziel der Definition.</summary>
    FTarget: TDefinitionTarget;
    /// <summary>Text und Zeilen der Datei des Ziels.</summary>
    FText: string;
    FLines: TArray<string>;
    FOwner: TUnitIndex;
    FSelfName: string;
    FTypeSymbol: Boolean;
    FDocSymbol: TResolvedSymbol;
    FDocContainer: string;
    /// <summary>Typ, in dem die Konstante unter dem Cursor steht ('' auf Unit-Ebene); für Namen in ihrem Wert.
    /// </summary>
    FValueContainer: string;
    function TryNumber: Boolean;
    function TryIntrinsic: Boolean;
    function FindTarget: Boolean;
    function InCodeAt: Boolean;
    function FindUnavailable(out AUnit: TUnitIndex; out ASymbol: TIndexSymbol): Boolean;
    function TryUnavailable: Boolean;
    function TryUnitName: Boolean;
    function ReadDeclaration: Boolean;
    function FindOwnerUnit: Boolean;
    function IsTargetSymbol(const ASymbol: TIndexSymbol): Boolean;
    function ConstantExpressionOf(const AName: string; out AExpression: string): Boolean;
    function ValueOf(const ASymbol: TIndexSymbol): string;
    procedure ApplyFullDeclaration(const ASymbol: TIndexSymbol);
    procedure ApplyInferredType;
    procedure ApplySymbol(const ASymbol: TIndexSymbol);
    procedure ApplyDocumentation;
    procedure ApplyTypes;
    function IsTargetClass(const ASymbol: TIndexSymbol): Boolean;
    function MessagesOf(const AClassName: string): string;
    function MessagesInOtherUnit(const AClassName: string; const AReader: TMemberReadText): string;
    procedure ApplyClass(const ASymbol: TIndexSymbol);
  public
    constructor Create(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText, AFileName: string;
      const APosition: TTextPosition);
    function Run(const ADelphiVersion: string): THoverInfo;
  end;

constructor THoverLookupRun.Create(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText,
  AFileName: string; const APosition: TTextPosition);
begin
  inherited Create;
  FSource := ASource;
  FTree := ATree;
  FTreeText := ATreeText;
  FFileName := AFileName;
  FPosition := APosition;
end;

function THoverLookupRun.TryNumber: Boolean;
var
  mToken: TPascalToken;
  mNumber: Int64;
begin
  // Zahlenliteral unter dem Cursor: Schreibweisen statt Deklaration.
  Result := False;
  for mToken in FTree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Number) and (ComparePositions(mToken.StartPos, FPosition) <= 0) and
      (ComparePositions(FPosition, mToken.EndPos) < 0) then
    begin
      if THoverValues.TryParseNumber(mToken.Text, mNumber) then
      begin
        FInfo.Declaration := mToken.Text;
        FInfo.Value := THoverValues.FormatNumber(mNumber);
      end
      else
      begin
        TRequestDiagnostics.Reason('numberUnparsed');
      end;
      Exit(True);
    end;
  end;
end;

function THoverLookupRun.TryIntrinsic: Boolean;
var
  mName: string;
  mIntrinsic: TSystemIntrinsic;
begin
  // Bezeichner von System ohne Quelltext (#880): Kopf und Beschreibung aus der eingebauten Liste.
  Result := TSystemIntrinsics.NameAt(FTree, FPosition, mName);
  if not Result then
  begin
    Exit;
  end;
  for mIntrinsic in TSystemIntrinsics.Find(mName) do
  begin
    if FInfo.Declaration <> '' then
    begin
      FInfo.Declaration := FInfo.Declaration + #10;
    end;
    FInfo.Declaration := FInfo.Declaration + mIntrinsic.Declaration;
    if FInfo.Documentation = '' then
    begin
      FInfo.Documentation := mIntrinsic.Documentation;
    end;
  end;
  FInfo.UnitName := 'System';
end;

function THoverLookupRun.FindTarget: Boolean;
var
  mTargets: TArray<TDefinitionTarget>;
begin
  mTargets := TLspDefinition.Targets(FSource.Resolver, FSource.Index, FTree, FFileName, FPosition, True);
  Result := Length(mTargets) > 0;
  if Result then
  begin
    FTarget := mTargets[0];
  end
  else if not TryIntrinsic and not TryUnavailable then
  begin
    // Grundcodes für das Diagnoselog (#647).
    TRequestDiagnostics.Reason('noTarget');
  end;
end;

function THoverLookupRun.InCodeAt: Boolean;
var
  mToken: TPascalToken;
begin
  // In Kommentaren und Strings sucht der Hover keine Namen nicht geltender Zweige.
  for mToken in FTree.Tokens do
  begin
    if (ComparePositions(mToken.StartPos, FPosition) <= 0) and (ComparePositions(FPosition, mToken.EndPos) < 0) then
    begin
      Exit(not (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive,
        TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]));
    end;
  end;
  Result := True;
end;

function THoverLookupRun.FindUnavailable(out AUnit: TUnitIndex; out ASymbol: TIndexSymbol): Boolean;
var
  mName: string;
  mCandidate: TIndexSymbol;
begin
  // Nur Deklarationen der eigenen Unit; die Deklaration unter dem Cursor geht einem gleichnamigen Eintrag vor.
  Result := False;
  ASymbol := Default(TIndexSymbol);
  if not TIndexFiles.UnitOf(FSource.Index, FFileName, AUnit) or (Length(AUnit.Unavailable) = 0) or
    not InCodeAt then
  begin
    Exit;
  end;
  mName := NameAt(FTreeText, FPosition);
  for mCandidate in AUnit.Unavailable do
  begin
    if not SameText(mCandidate.Name, mName) then
    begin
      Continue;
    end;
    if (mCandidate.SelectionRange.StartPos.Line = FPosition.Line) and
      SameText(AUnit.SymbolFile(mCandidate), FFileName) then
    begin
      ASymbol := mCandidate;
      Exit(True);
    end;
    if not Result then
    begin
      ASymbol := mCandidate;
      Result := True;
    end;
  end;
end;

function THoverLookupRun.TryUnavailable: Boolean;
var
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mFile, mText, mSignature: string;
  mLine: Integer;
  mTruncated: Boolean;
begin
  // Deklaration aus einem nicht geltenden Zweig (L1, L3): Der Index kennt nur Name, Art und Zeile; Kopf und
  // Kommentar kommen lazy aus der einen Datei der Deklaration.
  Result := FindUnavailable(mUnit, mSymbol);
  if not Result then
  begin
    Exit;
  end;
  mFile := mUnit.SymbolFile(mSymbol);
  if SameText(mFile, FFileName) then
  begin
    mText := FTreeText;
  end
  else if not (Assigned(FSource.ReadText) and FSource.ReadText(mFile, mText)) then
  begin
    Exit(False);
  end;
  FLines := TTextLines.SplitLines(mText);
  mSignature := SignatureFromLines(FLines, mSymbol, mTruncated);
  Result := mSignature <> '';
  if not Result then
  begin
    Exit;
  end;
  mLine := mSymbol.SelectionRange.StartPos.Line;
  FInfo.Declaration := DisplayedSignature(mSymbol, mSignature, mTruncated);
  FInfo.Doc := TLspDocumentation.DocAt(FLines, mLine, mLine);
  FInfo.Documentation := FInfo.Doc.ToMarkdown;
  FInfo.Kind := TLspHoverTypes.KindOf(mSymbol.Kind, FInfo.Declaration);
  FInfo.Container := mSymbol.Container;
  FInfo.Origin := TLspHoverTypes.Origin(mUnit.UnitName);
  if not SameText(mFile, mUnit.FileName) then
  begin
    FInfo.UnitName := mUnit.UnitName + ' (' + ExtractFileName(mFile) + ')';
  end
  else if not SameText(mFile, FFileName) then
  begin
    FInfo.UnitName := mUnit.UnitName;
  end;
  FInfo.FileName := mFile;
  FInfo.Line := mLine;
  FInfo.Character := mSymbol.SelectionRange.StartPos.Character;
  if mSymbol.Condition <> '' then
  begin
    FInfo.Deprecation := cTexts[TLookupText.InactiveCondition].Fmt([mSymbol.Condition]);
  end
  else
  begin
    FInfo.Deprecation := cTexts[TLookupText.Inactive].Text;
  end;
end;

function THoverLookupRun.TryUnitName: Boolean;
var
  mUnit: TUnitIndex;
begin
  // Unit-Namen: Ziel ist der Dateianfang. Vor dem Lesen der Datei prüfen, denn dafür wird ihr Text nicht gebraucht.
  Result := (FTarget.Range.StartPos = TTextPosition.Create(0, 0)) and (FTarget.Range.EndPos = FTarget.Range.StartPos)
    and not SameText(FTarget.FileName, FFileName);
  if not Result then
  begin
    Exit;
  end;
  if FSource.Index.FindFile(FTarget.FileName, mUnit) then
  begin
    FInfo.Declaration := 'unit ' + mUnit.UnitName + ';';
    FInfo.UnitContents := TLspHoverUnitContents.Select(TLspHoverUnitContents.Collect(mUnit, FTree.Tokens),
      THoverUnitMode.All);
  end;
  FInfo.Documentation := '`' + FTarget.FileName + '`';
end;

function THoverLookupRun.ReadDeclaration: Boolean;
var
  mStart: TTextPosition;
begin
  if SameText(FTarget.FileName, FFileName) then
  begin
    FText := FTreeText;
  end
  else if not (Assigned(FSource.ReadText) and FSource.ReadText(FTarget.FileName, FText)) then
  begin
    TRequestDiagnostics.Reason('declarationUnreadable');
    Exit(False);
  end;
  FLines := TTextLines.SplitLines(FText);
  mStart := FTarget.Range.StartPos;
  Result := (mStart.Line >= 0) and (mStart.Line <= High(FLines));
  if not Result then
  begin
    TRequestDiagnostics.Reason('declarationOutOfRange');
    Exit;
  end;
  // Erste Zeile; mehrzeilige Köpfe ersetzt ApplyFullDeclaration. Der Kommentar am Zeilenende ist Doku (L3).
  FInfo.Declaration := WithoutLineEndComment(TrimRight(Copy(FLines[mStart.Line], mStart.Character + 1, MaxInt)));
  FInfo.Doc := TLspDocumentation.DocAt(FLines, mStart.Line, FTarget.SelectionRange.StartPos.Line);
  FInfo.Documentation := FInfo.Doc.ToMarkdown;
  FInfo.Deprecation := THoverValues.Deprecation(DeclarationText(FLines, FTarget.Range));
  FInfo.FileName := FTarget.FileName;
  FInfo.Line := FTarget.SelectionRange.StartPos.Line;
  FInfo.Character := FTarget.SelectionRange.StartPos.Character;
end;

function THoverLookupRun.FindOwnerUnit: Boolean;
begin
  // Aus einer Include-Datei (#500): die einbindende Unit, die Datei dahinter. Die eigene Datei
  // auch ohne Index (noch nicht gespeichert bzw. nicht im Projekt) aus dem Baum.
  Result := TIndexFiles.UnitOf(FSource.Index, FTarget.FileName, FOwner);
  if not Result and SameText(FTarget.FileName, FFileName) then
  begin
    FOwner := TIndexExtractor.Extract(FTree, FFileName);
    Result := True;
  end;
  if not Result then
  begin
    TRequestDiagnostics.Reason('unitNotIndexed');
  end
  else if not SameText(FTarget.FileName, FOwner.FileName) then
  begin
    FInfo.UnitName := FOwner.UnitName + ' (' + ExtractFileName(FTarget.FileName) + ')';
  end
  else if not SameText(FTarget.FileName, FFileName) then
  begin
    FInfo.UnitName := FOwner.UnitName;
  end;
end;

function THoverLookupRun.IsTargetSymbol(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.SelectionRange.StartPos = FTarget.SelectionRange.StartPos) and
    SameText(FOwner.SymbolFile(ASymbol), FTarget.FileName);
end;

function THoverLookupRun.ConstantExpressionOf(const AName: string; out AExpression: string): Boolean;
var
  mSymbol: TIndexSymbol;
  mResolved: TResolvedSymbol;
  mSignature: string;
begin
  // Namen im Wert einer Konstanten (L3): zuerst die eigene Unit (im selben Typ vor der Unit-Ebene), sonst über die
  // Namensauflösung von dort aus. Der Wert kommt aus der Signatur im Index, ohne weitere Dateien zu lesen.
  AExpression := '';
  mSignature := '';
  if Pos('.', AName) = 0 then
  begin
    for mSymbol in FOwner.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.Constant) and SameText(mSymbol.Name, AName) and
        (SameText(mSymbol.Container, FValueContainer) or (mSymbol.Container = '')) then
      begin
        mSignature := mSymbol.Signature;
        if SameText(mSymbol.Container, FValueContainer) then
        begin
          Break;
        end;
      end;
    end;
  end;
  // Wie ein cref: Typ.Konstante, Konstante des eigenen Typs samt Vorfahren, globale Konstante über uses.
  if (mSignature = '') and FSource.Resolver.LocateCref(FOwner, FValueContainer, AName, mResolved) and
    (mResolved.Kind = TResolvedKind.Symbol) and (mResolved.SymbolKind = TIndexSymbolKind.Constant) then
  begin
    mSignature := mResolved.Signature;
  end;
  // Eine gekürzte Signatur (…) hat keinen vollständigen Wert.
  if (mSignature <> '') and not mSignature.EndsWith('…') then
  begin
    AExpression := THoverValues.ConstantExpression(mSignature);
  end;
  Result := AExpression <> '';
end;

function THoverLookupRun.ValueOf(const ASymbol: TIndexSymbol): string;
begin
  case ASymbol.Kind of
    TIndexSymbolKind.Constant:
      begin
        // Ganze Deklaration: Mengen und Texte über mehrere Zeilen (Resourcestrings, #38); einfache Ausdrücke samt
        // anderer Konstanten (L3).
        FValueContainer := ASymbol.Container;
        Result := THoverValues.ConstantValue(DeclarationText(FLines, FTarget.Range), ConstantExpressionOf);
      end;
    TIndexSymbolKind.TypeAlias:
      Result := SetTypeValue(FSource.Resolver, FOwner, DeclarationText(FLines, FTarget.Range));
    TIndexSymbolKind.EnumMember:
      Result := 'Ord = ' + IntToStr(EnumOrdinal(FOwner, ASymbol));
  else
    // Andere Arten haben keinen Wert für die Kopfzeile.
    Result := '';
  end;
end;

procedure THoverLookupRun.ApplyFullDeclaration(const ASymbol: TIndexSymbol);
var
  mSymbol: TIndexSymbol;
  mSignature: string;
  mTruncated: Boolean;
begin
  // Mehrzeilige Köpfe vollständig (L3); einzeilige bleiben wie in der Quelle.
  if FTarget.Range.EndPos.Line <= FTarget.Range.StartPos.Line then
  begin
    Exit;
  end;
  // Positionen des Ziels: Sie passen zum gelesenen Text, auch wenn der Index der eigenen Datei älter ist.
  mSymbol := ASymbol;
  mSymbol.Range := FTarget.Range;
  mSymbol.SelectionRange := FTarget.SelectionRange;
  mSignature := SignatureFromLines(FLines, mSymbol, mTruncated);
  if mSignature <> '' then
  begin
    FInfo.Declaration := DisplayedSignature(mSymbol, mSignature, mTruncated);
  end;
end;

procedure THoverLookupRun.ApplyInferredType;
var
  mOffset, mEnd: Integer;
  mRest: string;
  mResolved, mType: TResolvedSymbol;
begin
  // var X := …, for var I := …, const C = …: den Typ aus dem Ausdruck hinter dem Namen einsetzen (L3).
  if (FTarget.SelectionRange.StartPos.Line <> FTarget.Range.StartPos.Line) or
    (FTarget.SelectionRange.EndPos.Line <> FTarget.SelectionRange.StartPos.Line) then
  begin
    Exit;
  end;
  mOffset := FTarget.SelectionRange.StartPos.Character - FTarget.Range.StartPos.Character;
  mEnd := mOffset + FTarget.SelectionRange.EndPos.Character - FTarget.SelectionRange.StartPos.Character;
  if (mOffset < 0) or (mEnd > Length(FInfo.Declaration)) then
  begin
    Exit;
  end;
  mRest := TrimLeft(Copy(FInfo.Declaration, mEnd + 1, MaxInt));
  if not (StartsStr(':=', mRest) or StartsStr('=', mRest) or StartsText('in ', mRest)) then
  begin
    Exit;
  end;
  // Resolve setzt die Stelle, die TypeOf für den Ausdruck braucht.
  mResolved := FSource.Resolver.Resolve(FTree, FFileName, FPosition);
  if (mResolved.Kind = TResolvedKind.Local) and (mResolved.TypeName = '') and (mResolved.Initializer <> nil) and
    FSource.Resolver.TypeOf(mResolved, mType) and (mType.Name <> '') then
  begin
    FInfo.Declaration := Copy(FInfo.Declaration, 1, mEnd) + ': ' + TypeDisplay(mType) +
      Copy(FInfo.Declaration, mEnd + 1, MaxInt);
  end;
end;

procedure THoverLookupRun.ApplySymbol(const ASymbol: TIndexSymbol);
var
  mFormFile: string;
begin
  ApplyFullDeclaration(ASymbol);
  FSelfName := ASymbol.Name;
  FDocSymbol := TResolvedSymbol.FromIndex(FOwner, ASymbol);
  FDocContainer := ASymbol.Container;
  if FDocContainer = '' then
  begin
    FDocContainer := ASymbol.Name;
  end;
  FInfo.Kind := TLspHoverTypes.KindOf(ASymbol.Kind, FInfo.Declaration);
  FInfo.Container := ASymbol.Container;
  FTypeSymbol := (ASymbol.Container = '') and (ASymbol.Kind in [TIndexSymbolKind.ClassType,
    TIndexSymbolKind.ObjectType, TIndexSymbolKind.InterfaceType]);
  FInfo.Value := ValueOf(ASymbol);
  if (ASymbol.Kind = TIndexSymbolKind.Field) and (ASymbol.Container <> '') then
  begin
    FInfo.FormValues := TFormInfo.FieldMarkdown(FormText(FTarget.FileName, FFileName, FTreeText, FSource.ReadText,
      mFormFile), mFormFile, ASymbol.Container, ASymbol.Name);
  end;
end;

procedure THoverLookupRun.ApplyDocumentation;
begin
  // XMLDoc mit <inheritdoc/> und den Fundorten der cref-Verweise (#654).
  if FInfo.Doc.InheritDoc then
  begin
    FInfo.Doc := TLspDocumentation.Load(FSource.Resolver, FDocSymbol, FLines, FTarget.Range.StartPos.Line,
      TLspDocumentation.Reader(FFileName, FTreeText, FSource.ReadText));
    FInfo.Documentation := FInfo.Doc.ToMarkdown;
  end;
  FInfo.DocTargets := TLspDocumentation.Targets(FSource.Resolver, FOwner, FDocContainer, FInfo.Doc);
end;

procedure THoverLookupRun.ApplyTypes;
var
  mChainName: string;
  mResolved: TResolvedSymbol;
begin
  // Typen in der Deklaration und Vererbungskette für den dpcc-Tooltip (#588).
  FInfo.Origin := TLspHoverTypes.Origin(FOwner.UnitName);
  FInfo.Links := TLspHoverTypes.Links(FSource.Resolver, FOwner, FInfo.Declaration, FSelfName);
  if not FTypeSymbol then
  begin
    Exit;
  end;
  mChainName := TLspHoverTypes.ClassRefTarget(FInfo.Declaration);
  if mChainName = '' then
  begin
    mChainName := FSelfName;
  end;
  if FSource.Resolver.ResolveTypeFrom(FOwner, mChainName, mResolved) then
  begin
    FInfo.ChainOf := mResolved.Name;
    FInfo.Ancestors := TLspHoverTypes.Chain(FSource.Resolver, mResolved);
  end;
end;

function THoverLookupRun.IsTargetClass(const ASymbol: TIndexSymbol): Boolean;
var
  mStart: TTextPosition;
begin
  mStart := FTarget.Range.StartPos;
  Result := (ASymbol.Kind = TIndexSymbolKind.ClassType) and (ASymbol.Container = '') and
    ((ASymbol.Range.StartPos = mStart) or (ASymbol.SelectionRange.StartPos = mStart)) and
    SameText(FOwner.SymbolFile(ASymbol), FTarget.FileName);
end;

function THoverLookupRun.MessagesOf(const AClassName: string): string;
var
  mReader: TMessageReadText;
begin
  mReader := MessageReader(FFileName, FTreeText, FSource.ReadText);
  if SameText(FTarget.FileName, FFileName) then
  begin
    Result := TMessageHandlers.Overview(FSource.Resolver, FTree, FFileName, AClassName, mReader).ToMarkdown;
    Exit;
  end;
  // Klasse in einer anderen Unit (oft VCL): ohne gemeinsamen Baum parst der Server die ganze Unit. Gemerkt wird
  // das Ergebnis, solange die gelesenen Dateien (die Unit und die Vorfahren) denselben Text haben.
  Result := TPublishedMembers.CachedText(FSource.Index, 'messages|' + FTarget.FileName + '|' + AClassName,
    MemberReader(FFileName, FTreeText, FSource.ReadText),
    function(AReader: TMemberReadText): string
    begin
      Result := MessagesInOtherUnit(AClassName, AReader);
    end);
end;

/// <summary>Derselbe Leser als TMessageReadText; eigene Routine, damit die Methodenreferenz keinen fremden Rahmen
/// festhält.</summary>
function AsMessageReader(const AReader: TMemberReadText): TMessageReadText;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := AReader(AFileName, AText);
    end;
end;

function THoverLookupRun.MessagesInOtherUnit(const AClassName: string; const AReader: TMemberReadText): string;
var
  mText: string;
  mClassTree: TSyntaxTree;
begin
  // Über den Leser, damit die Unit selbst zu den geprüften Dateien gehört.
  if not AReader(FTarget.FileName, mText) then
  begin
    mText := FText;
  end;
  mClassTree := TSyntaxTreeCache.Parse(mText);
  try
    Result := TMessageHandlers.Overview(FSource.Resolver, mClassTree, FTarget.FileName, AClassName,
      AsMessageReader(AReader)).ToMarkdown;
  finally
    mClassTree.Free;
  end;
end;

procedure THoverLookupRun.ApplyClass(const ASymbol: TIndexSymbol);
var
  mUse: TAttributeUse;
  mReader: TMemberReadText;
begin
  if TAttributes.At(FTree, FPosition, mUse) then
  begin
    FInfo.Constructors := AttributeConstructors(FOwner, ASymbol, FLines, mUse.ArgCount);
  end;
  mReader := MemberReader(FFileName, FTreeText, FSource.ReadText);
  FInfo.PublishedItems := TPublishedMembers.Collect(FSource.Index, ASymbol.Name, mReader);
  FInfo.DefaultProperty := TPublishedMembers.DefaultProperty(FSource.Index, ASymbol.Name, mReader);
  FInfo.Members := TPublishedMembers.ToMarkdown(FInfo.PublishedItems, FInfo.DefaultProperty);
  FInfo.Messages := MessagesOf(ASymbol.Name);
end;

function THoverLookupRun.Run(const ADelphiVersion: string): THoverInfo;
var
  mSymbol: TIndexSymbol;
  mApplied: Boolean;
begin
  FDelphiVersion := ADelphiVersion;
  FInfo := Default(THoverInfo);
  if not TryNumber and FindTarget and not TryUnitName and ReadDeclaration and FindOwnerUnit then
  begin
    mApplied := False;
    for mSymbol in FOwner.Symbols do
    begin
      if IsTargetSymbol(mSymbol) then
      begin
        ApplySymbol(mSymbol);
        mApplied := True;
        Break;
      end;
    end;
    // Lokale Namen stehen nicht im Index: Inline-Variablen ohne Typ zeigen den abgeleiteten (L3).
    if not mApplied and SameText(FTarget.FileName, FFileName) then
    begin
      ApplyInferredType;
    end;
    ApplyDocumentation;
    ApplyTypes;
    for mSymbol in FOwner.Symbols do
    begin
      if IsTargetClass(mSymbol) then
      begin
        ApplyClass(mSymbol);
        Break;
      end;
    end;
  end;
  Result := FInfo;
end;

{ TLspHoverLookup }

class function TLspHoverLookup.InfoAt(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText,
  AFileName: string; const APosition: TTextPosition; const ADelphiVersion: string): THoverInfo;
var
  mRun: THoverLookupRun;
begin
  mRun := THoverLookupRun.Create(ASource, ATree, ATreeText, AFileName, APosition);
  try
    Result := mRun.Run(ADelphiVersion);
  finally
    mRun.Free;
  end;
end;

initialization
  TDpccTextTables.Add('dpcc.Common.Lsp.Hover.Lookup', cTexts);

end.
