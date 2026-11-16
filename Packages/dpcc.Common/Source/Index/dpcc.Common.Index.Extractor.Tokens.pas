unit dpcc.Common.Index.Extractor.Tokens;

// Liest aus den Tokens einer Unit, was der Syntaxbaum nicht festhält: Namensstellen, Signaturen als Text,
// Hinweise (deprecated, platform …), XML-Doku und den Schalter {$SCOPEDENUMS}. Ausgelagert aus
// dpcc.Common.Index.Extractor.

interface

uses
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Index.Contract;

type
  TIndexTokenReader = class
  private
    FTokens: TArray<TPascalToken>;
    /// <summary>Stellen der {$SCOPEDENUMS}-Schalter in FTokens (Offset, ON?); FScopedKnown nach dem ersten Lesen.
    /// </summary>
    FScopedOffsets: TArray<Integer>;
    FScopedOn: TArray<Boolean>;
    FScopedKnown: Boolean;
    procedure ReadScopedSwitches;
    /// <summary>Erstes Token ab AIndex, das weder Kommentar noch Direktive ist (Length(FTokens) ohne).</summary>
    function NextCode(AIndex: Integer): Integer;
    /// <summary>Letztes Token bis AIndex, das weder Kommentar noch Direktive ist (-1 ohne).</summary>
    function PreviousCode(AIndex: Integer): Integer;
    function IsHintAt(APos: Integer): Boolean;
    /// <summary>Endet an APos ein Hinweis? Hinter ihm folgt ";", "," oder der Grund als String, sonst ist er ein
    /// Bezeichner (z. B. ein Feld "platform: Integer").</summary>
    function EndsHint(APos: Integer): Boolean;
    /// <summary>Grund hinter deprecated am Token APos (deprecated 'Stattdessen Bar verwenden') nach AText.</summary>
    procedure ReasonAt(APos: Integer; var AText: string);
    procedure HeaderDirectives(AHeader: TSyntaxNode; var AWords: TArray<string>; var AReason: string);
    /// <summary>Hinweise vor dem Ende der Deklaration: "X = 1 deprecated;", "A: Integer platform;".</summary>
    procedure HintsBefore(ALast: Integer; var AWords: TArray<string>; var AReason: string);
    /// <summary>Hinweise hinter dem Ende des Knotens, die trotzdem zu ihm gehören.</summary>
    procedure HintsAfter(AFirst: Integer; var AWords: TArray<string>; var AReason: string);
    /// <summary>Erstes "of" außerhalb von Klammern in AFirst..ALast-1; -1 ohne.</summary>
    function TopLevelOf(AFirst, ALast: Integer): Integer;
    /// <summary>Erstes Token hinter dem Unit-Namen ab AIndex (Teile mit Punkt dazwischen).</summary>
    function AfterUnitName(AIndex: Integer): Integer;
    /// <summary>Länge hinter string[8] als "[8]"; '' bei anderen Typen.</summary>
    function StringLengthSuffix(ANode: TSyntaxNode): string;
  public
    constructor Create(const ATokens: TArray<TPascalToken>);
    /// <summary>AText, auf höchstens AMax Zeichen gekürzt (mit „…“ am Ende).</summary>
    class function Shortened(const AText: string; AMax: Integer): string; static;
    function TokenIndexAt(AOffset: Integer): Integer;
    /// <summary>Gilt {$SCOPEDENUMS ON} an AOffset?</summary>
    function ScopedAt(AOffset: Integer): Boolean;
    function NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
    function IsConstructor(ANode: TSyntaxNode): Boolean;
    /// <summary>Schlüsselwort einer Routine hinter "class" klein: procedure, function, constructor, destructor,
    /// operator; '' ohne (L1).</summary>
    function RoutineWord(ANode: TSyntaxNode): string;
    /// <summary>Beginnt die Deklaration mit "class" oder steht "class" direkt davor ("class property",
    /// "class var" vor dem var-Abschnitt)?</summary>
    function IsClassMember(ANode: TSyntaxNode): Boolean;
    function IsDefaultProperty(ANode: TSyntaxNode): Boolean;
    /// <summary>Tokens AFrom..ATo (ohne Kommentare und Compiler-Direktiven) als eine Zeile; mit
    /// AFirstLine endet der Text am Ende der ersten Zeile außerhalb von Klammern. Höchstens
    /// TIndexSymbol.cMaxSignature Zeichen.</summary>
    function TokenText(AFrom, ATo: Integer; AFirstLine: Boolean): string; overload;
    /// <summary>Wie oben mit höchstens AMax Zeichen; AMax &lt;= 0 = ungekürzt (volle Signatur aus der Quelle, L1).
    /// </summary>
    function TokenText(AFrom, ATo: Integer; AFirstLine: Boolean; AMax: Integer): string; overload;
    /// <summary>Kopf der Deklaration ANode als eine Zeile, höchstens TIndexSymbol.MaxSignatureOf(AKind) Zeichen;
    /// Aufzählungswerte mit ausdrücklichem Wert als "A = 5" (L1).</summary>
    function SignatureOf(ANode: TSyntaxNode; AKind: TIndexSymbolKind; const AName, ATypeText: string): string;
    /// <summary>Art des Prozedurtyps AType (#1326): 'of object' bei Methodenzeigern, 'reference to' bei
    /// Methodenreferenzen, sonst ''. Gelesen aus den Tokens, also unabhängig von Zeilenumbrüchen.</summary>
    function ProcedureKindOf(AType: TSyntaxNode): string;
    /// <summary>Direktiven der Deklaration; ADeprecatedText: Grund hinter deprecated 'Grund' (#38), sonst ''.
    /// </summary>
    function DirectivesOf(ANode: TSyntaxNode; AKind: TIndexSymbolKind; out ADeprecatedText: string): TArray<string>;
    /// <summary>DLL-Angaben der Direktive external im Kopf AHeader als Einträge für TIndexSymbol.Directives (L1):
    /// "external:Bibliothek", "name:Name", "index:Nummer"; nil ohne external mit Angaben.</summary>
    function ExternalEntries(AHeader: TSyntaxNode): TArray<string>;
    /// <summary>Nachricht einer message-Direktive als "message:WM_PAINT" (L1); '' ohne.</summary>
    function MessageEntry(AHeader: TSyntaxNode): string;
    /// <summary>Einschränkungen der Typparameter von ANode als Einträge "&lt;T:class,constructor&gt;" (L1).</summary>
    function ConstraintEntries(ANode: TSyntaxNode): TArray<string>;
    /// <summary>Text der Tokens im Bereich des Knotens ANode als eine Zeile, ungekürzt.</summary>
    function NodeText(ANode: TSyntaxNode): string;
    /// <summary>Hinweise zwischen unit Name und ";" (#1018).</summary>
    procedure UnitHints(var AUnit: TUnitIndex);
    property Tokens: TArray<TPascalToken> read FTokens;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  dpcc.Common.Pascal.Preprocessor,
  dpcc.Common.Index.Extractor.TypeText;

const
  cHintDirectives: array[0..3] of string = ('deprecated', 'platform', 'library', 'experimental');
  cNoSpaceBefore: array[0..9] of string = (';', ',', ')', ']', ':', '.', '(', '[', '^', '>');
  cNoSpaceAfter: array[0..3] of string = ('(', '[', '.', '@');
  /// <summary>Hinter diesen Zeichen beginnt ein Ausdruck oder Typ (L1).</summary>
  cOperandAfter: array[0..12] of string = ('=', ':', ',', ':=', '+', '-', '*', '/', '<>', '<=', '>=', '(', '[');
  cOperandAfterWords: array[0..9] of string = ('of', 'to', 'in', 'and', 'or', 'not', 'xor', 'div', 'mod', 'set');

/// <summary>Gehört AToken in den Text einer Signatur? Kommentare und Direktiven nicht, {$I datei.inc} als Wert
/// (#849) schon: AddIncluded setzt den Inhalt ein.</summary>
function IsTextToken(const AToken: TPascalToken): Boolean;
var
  mIncludeName: string;
begin
  Result := (AToken.Kind <> TPascalTokenKind.Comment) and ((AToken.Kind <> TPascalTokenKind.Directive) or
    TPascalPreprocessor.IncludeFileOf(AToken.Text, mIncludeName));
end;

/// <summary>Steht vor AToken ein Operator, ein Komma oder ein Schlüsselwort wie "of"? Dann beginnt AToken einen
/// Ausdruck oder Typ: "= ^Integer", "= (rot, gruen)", "of (a, b)", "= []" (L1).</summary>
function StartsOperand(const APrevious: TPascalToken): Boolean;
begin
  Result := ((APrevious.Kind = TPascalTokenKind.Symbol) and (IndexStr(APrevious.Text, cOperandAfter) >= 0)) or
    ((APrevious.Kind = TPascalTokenKind.Keyword) and (IndexText(APrevious.Text, cOperandAfterWords) >= 0));
end;

/// <summary>Steht AToken im Quelltext direkt hinter APrevious, ohne Leerraum dazwischen?</summary>
function Glued(const APrevious, AToken: TPascalToken): Boolean;
begin
  Result := (APrevious.Text <> '') and (APrevious.Offset + Length(APrevious.Text) = AToken.Offset);
end;

/// <summary>Kein Leerzeichen vor AToken? Satzzeichen wie ";" und ")" nie; "(" und "[" nicht hinter Namen ("F(A)"),
/// wohl aber hinter "=" oder "of"; "^" als Zeiger ("= ^Integer") mit, als Dereferenzierung ("P^") ohne; "&lt;" und
/// "&gt;" wie im Quelltext (TList&lt;T&gt; ohne, A &lt; B mit, L1).</summary>
function NoSpaceBefore(const AToken, APrevious: TPascalToken): Boolean;
begin
  Result := False;
  if AToken.Kind <> TPascalTokenKind.Symbol then
  begin
    Exit;
  end;
  if (AToken.Text = '(') or (AToken.Text = '[') or (AToken.Text = '^') then
  begin
    Result := not StartsOperand(APrevious);
  end
  else if (AToken.Text = '<') or (AToken.Text = '>') then
  begin
    Result := Glued(APrevious, AToken);
  end
  else
  begin
    // Teilbereich ohne Leerzeichen wie im Quelltext üblich: 0..9 (L1).
    Result := (IndexStr(AToken.Text, cNoSpaceBefore) >= 0) or (AToken.Text = '..');
  end;
end;

/// <summary>Kein Leerzeichen hinter APrevious? Hinter "(", "[", "." und "@" nie, hinter einem Zeiger-"^" auch nicht,
/// hinter "&lt;" nur, wenn der Quelltext keins hat (L1).</summary>
function NoSpaceAfter(const APrevious, AToken, ABeforePrevious: TPascalToken): Boolean;
begin
  if (APrevious.Kind = TPascalTokenKind.Symbol) and (APrevious.Text = '^') then
  begin
    Result := StartsOperand(ABeforePrevious);
  end
  else if (APrevious.Kind = TPascalTokenKind.Symbol) and (APrevious.Text = '<') then
  begin
    Result := Glued(APrevious, AToken);
  end
  else
  begin
    Result := (IndexStr(APrevious.Text, cNoSpaceAfter) >= 0) or
      ((APrevious.Kind = TPascalTokenKind.Symbol) and (APrevious.Text = '..'));
  end;
end;

/// <summary>Hängt AToken an; Leerzeichen nur, wo kein Satzzeichen es verbietet ("A: Integer", "F(A)").</summary>
procedure AppendTokenText(ABuilder: TStringBuilder; const AToken, APrevious, ABeforePrevious: TPascalToken);
begin
  if (ABuilder.Length > 0) and (AToken.Text <> '') and not NoSpaceBefore(AToken, APrevious) and
    not NoSpaceAfter(APrevious, AToken, ABeforePrevious) then
  begin
    ABuilder.Append(' ');
  end;
  ABuilder.Append(AToken.Text);
end;

/// <summary>Klammertiefe hinter AToken.</summary>
function DepthAfter(const AToken: TPascalToken; ADepth: Integer): Integer;
begin
  Result := ADepth;
  if AToken.Kind <> TPascalTokenKind.Symbol then
  begin
    Exit;
  end;
  if (AToken.Text = '(') or (AToken.Text = '[') then
  begin
    Inc(Result);
  end
  else if ((AToken.Text = ')') or (AToken.Text = ']')) and (Result > 0) then
  begin
    Dec(Result);
  end;
end;

/// <summary>Stringliteral ohne Anführungszeichen, verdoppelte Anführungszeichen einfach.</summary>
function Unquoted(const AText: string): string;
begin
  Result := AText;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := StringReplace(Copy(Result, 2, Length(Result) - 2), '''''', '''', [rfReplaceAll]);
  end;
end;

/// <summary>AWord klein an AWords anhängen, wenn noch nicht enthalten.</summary>
procedure AddHint(var AWords: TArray<string>; const AWord: string);
begin
  if IndexText(AWord, AWords) < 0 then
  begin
    AWords := AWords + [LowerCase(AWord)];
  end;
end;

/// <summary>Endet die Signatur von AKind am Ende der ersten Zeile? Ein Prozedurtyp über mehrere Zeilen gehört
/// ganz hinein, sonst fehlt "of object" (#1326).</summary>
function IsFirstLineKind(ANode: TSyntaxNode; AKind: TIndexSymbolKind): Boolean;
begin
  Result := (AKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType, TIndexSymbolKind.EnumType,
    TIndexSymbolKind.TypeAlias]) and
    not ((AKind = TIndexSymbolKind.TypeAlias) and (TIndexTypeText.ProcedureTypeOf(ANode) <> nil));
end;

{ TIndexTokenReader }

constructor TIndexTokenReader.Create(const ATokens: TArray<TPascalToken>);
begin
  inherited Create;
  FTokens := ATokens;
end;

class function TIndexTokenReader.Shortened(const AText: string; AMax: Integer): string;
begin
  Result := AText;
  if Length(Result) > AMax then
  begin
    Result := Copy(Result, 1, AMax - 1) + '…';
  end;
end;

function TIndexTokenReader.TokenIndexAt(AOffset: Integer): Integer;
var
  mLeft, mRight, mMiddle: Integer;
begin
  mLeft := 0;
  mRight := Length(FTokens);
  while mLeft < mRight do
  begin
    mMiddle := (mLeft + mRight) div 2;
    if FTokens[mMiddle].Offset < AOffset then
    begin
      mLeft := mMiddle + 1;
    end
    else
    begin
      mRight := mMiddle;
    end;
  end;
  Result := mLeft;
end;

function TIndexTokenReader.NextCode(AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result < Length(FTokens)) and (FTokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(Result);
  end;
end;

function TIndexTokenReader.PreviousCode(AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result >= 0) and (FTokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(Result);
  end;
end;

procedure TIndexTokenReader.ReadScopedSwitches;
var
  mToken: TPascalToken;
  mText: string;
begin
  FScopedKnown := True;
  for mToken in FTokens do
  begin
    if mToken.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    mText := UpperCase(mToken.Text);
    if mText.StartsWith('{$SCOPEDENUMS') or mText.StartsWith('(*$SCOPEDENUMS') then
    begin
      mText := Trim(Copy(mText, Pos('SCOPEDENUMS', mText) + Length('SCOPEDENUMS'), MaxInt));
      FScopedOffsets := FScopedOffsets + [mToken.Offset];
      FScopedOn := FScopedOn + [mText.StartsWith('ON')];
    end;
  end;
end;

function TIndexTokenReader.ScopedAt(AOffset: Integer): Boolean;
var
  mIndex: Integer;
begin
  if not FScopedKnown then
  begin
    ReadScopedSwitches;
  end;
  Result := False;
  mIndex := 0;
  while (mIndex <= High(FScopedOffsets)) and (FScopedOffsets[mIndex] < AOffset) do
  begin
    Result := FScopedOn[mIndex];
    Inc(mIndex);
  end;
end;

function TIndexTokenReader.NameRange(ANode: TSyntaxNode; const AName: string): TTextRange;
var
  mIndex: Integer;
begin
  mIndex := TokenIndexAt(ANode.StartOffset);
  while (mIndex < Length(FTokens)) and (FTokens[mIndex].Offset < ANode.EndOffset) do
  begin
    if (FTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      (SameText(FTokens[mIndex].Text, AName) or SameText(FTokens[mIndex].Text, '&' + AName)) then
    begin
      Exit(TTextRange.Create(FTokens[mIndex].StartPos, FTokens[mIndex].EndPos));
    end;
    Inc(mIndex);
  end;
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function TIndexTokenReader.IsConstructor(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := NextCode(TokenIndexAt(ANode.StartOffset));
  if (mIndex < Length(FTokens)) and FTokens[mIndex].IsKeyword('class') then
  begin
    Inc(mIndex);
  end;
  Result := (mIndex < Length(FTokens)) and
    (FTokens[mIndex].IsKeyword('constructor') or FTokens[mIndex].IsKeyword('destructor'));
end;

function TIndexTokenReader.RoutineWord(ANode: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  mIndex := NextCode(TokenIndexAt(ANode.StartOffset));
  if (mIndex < Length(FTokens)) and FTokens[mIndex].IsKeyword('class') then
  begin
    mIndex := NextCode(mIndex + 1);
  end;
  Result := '';
  if (mIndex < Length(FTokens)) and (FTokens[mIndex].Kind in [TPascalTokenKind.Keyword,
    TPascalTokenKind.Identifier]) and MatchText(FTokens[mIndex].Text, ['procedure', 'function', 'constructor',
    'destructor', 'operator']) then
  begin
    Result := LowerCase(FTokens[mIndex].Text);
  end;
end;

function TIndexTokenReader.IsClassMember(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  mIndex := NextCode(TokenIndexAt(ANode.StartOffset));
  if (mIndex < Length(FTokens)) and FTokens[mIndex].IsKeyword('class') then
  begin
    Exit(True);
  end;
  mIndex := PreviousCode(TokenIndexAt(ANode.StartOffset) - 1);
  if (mIndex < 0) or not FTokens[mIndex].IsKeyword('class') then
  begin
    Exit(False);
  end;
  // "TFoo = class" bzw. "= packed class" direkt vor dem ersten Mitglied ist der Typ selbst.
  mIndex := PreviousCode(mIndex - 1);
  Result := (mIndex >= 0) and not FTokens[mIndex].IsSymbol('=') and not FTokens[mIndex].IsKeyword('packed');
end;

function TIndexTokenReader.IsDefaultProperty(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
begin
  // property Items[I: Integer]: T read Get; default;  Anders als "default 0" (gespeicherter
  // Standardwert) folgt "default" hier auf ein Semikolon.
  Result := False;
  mIndex := TokenIndexAt(ANode.StartOffset);
  while (mIndex + 1 < Length(FTokens)) and (FTokens[mIndex].Offset <= ANode.EndOffset) do
  begin
    if FTokens[mIndex].IsSymbol(';') and SameText(FTokens[mIndex + 1].Text, 'default') then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
end;

function TIndexTokenReader.TokenText(AFrom, ATo: Integer; AFirstLine: Boolean): string;
begin
  Result := TokenText(AFrom, ATo, AFirstLine, TIndexSymbol.cMaxSignature);
end;

function TIndexTokenReader.TokenText(AFrom, ATo: Integer; AFirstLine: Boolean; AMax: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex, mDepth, mFirstLine: Integer;
  mToken, mPrevious, mBeforePrevious: TPascalToken;
begin
  mBuilder := TStringBuilder.Create;
  try
    mDepth := 0;
    mFirstLine := -1;
    mPrevious := Default(TPascalToken);
    mBeforePrevious := Default(TPascalToken);
    for mIndex := Max(AFrom, 0) to Min(ATo, High(FTokens)) do
    begin
      mToken := FTokens[mIndex];
      if not IsTextToken(mToken) then
      begin
        Continue;
      end;
      if mFirstLine < 0 then
      begin
        mFirstLine := mToken.StartPos.Line;
      end;
      if AFirstLine and (mDepth = 0) and (mToken.StartPos.Line > mFirstLine) then
      begin
        Break;
      end;
      AppendTokenText(mBuilder, mToken, mPrevious, mBeforePrevious);
      mDepth := DepthAfter(mToken, mDepth);
      mBeforePrevious := mPrevious;
      mPrevious := mToken;
      if (AMax > 0) and (mBuilder.Length > AMax) then
      begin
        Break;
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  if AMax > 0 then
  begin
    Result := Shortened(Result, AMax);
  end;
end;

function TIndexTokenReader.NodeText(ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode <> nil then
  begin
    Result := TokenText(TokenIndexAt(ANode.StartOffset), TokenIndexAt(ANode.EndOffset) - 1, False, 0);
  end;
end;

function TIndexTokenReader.StringLengthSuffix(ANode: TSyntaxNode): string;
var
  mTypeRef: TSyntaxNode;
begin
  // string[8]: Die Länge gehört zur Signatur (Anzeige, string-length-limit #1036); der Typname bleibt
  // string, damit die Namensauflösung ihn findet.
  Result := '';
  mTypeRef := TIndexTypeText.DeclaredTypeNode(ANode);
  if (mTypeRef <> nil) and SameText(mTypeRef.Name, 'string') and (mTypeRef.ChildCount = 1) and
    (mTypeRef[0].Kind <> TSyntaxKind.GenericArgs) then
  begin
    Result := '[' + TokenText(TokenIndexAt(mTypeRef[0].StartOffset), TokenIndexAt(mTypeRef[0].EndOffset) - 1,
      False) + ']';
  end;
end;

function TIndexTokenReader.SignatureOf(ANode: TSyntaxNode; AKind: TIndexSymbolKind;
  const AName, ATypeText: string): string;
var
  mNode: TSyntaxNode;
begin
  if AKind = TIndexSymbolKind.EnumMember then
  begin
    // Ausdrücklicher Wert (L1): Der Parser hängt ihn an den Bezeichner, A = B + 1.
    if ANode.ChildCount > 0 then
    begin
      Exit(Shortened(AName + ' = ' + NodeText(ANode[0]), TIndexSymbol.cMaxSignature));
    end;
    Exit(AName);
  end;
  // A, B: Integer: je Name eine eigene Signatur.
  if (AKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Variable]) and (ATypeText <> '') then
  begin
    Exit(AName + ': ' + ATypeText + StringLengthSuffix(ANode));
  end;
  mNode := TIndexTypeText.HeaderOf(ANode);
  Result := TokenText(TokenIndexAt(mNode.StartOffset), TokenIndexAt(mNode.EndOffset) - 1,
    IsFirstLineKind(mNode, AKind), TIndexSymbol.MaxSignatureOf(AKind));
  // Ein abschließendes Semikolon gehört nicht zur Anzeige.
  while Result.EndsWith(';') do
  begin
    Result := Copy(Result, 1, Length(Result) - 1).TrimRight;
  end;
end;

function TIndexTokenReader.TopLevelOf(AFirst, ALast: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  Result := AFirst;
  while Result < ALast do
  begin
    if (mDepth = 0) and FTokens[Result].IsKeyword('of') then
    begin
      Exit;
    end;
    mDepth := DepthAfter(FTokens[Result], mDepth);
    Inc(Result);
  end;
  Result := -1;
end;

function TIndexTokenReader.ProcedureKindOf(AType: TSyntaxNode): string;
var
  mOf, mLast, mIndex: Integer;
begin
  Result := '';
  if AType = nil then
  begin
    Exit;
  end;
  if SameText(AType.Name, 'reference') then
  begin
    Exit('reference to');
  end;
  mLast := TokenIndexAt(AType.EndOffset) - 1;
  mOf := TopLevelOf(TokenIndexAt(AType.StartOffset), mLast);
  // Kommentare und Direktiven zwischen "of" und "object" überspringen.
  mIndex := NextCode(mOf + 1);
  if (mOf >= 0) and (mIndex <= mLast) and SameText(FTokens[mIndex].Text, 'object') then
  begin
    Result := 'of object';
  end;
end;

function TIndexTokenReader.IsHintAt(APos: Integer): Boolean;
begin
  Result := (APos >= 0) and (APos < Length(FTokens)) and
    (FTokens[APos].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
    (IndexText(FTokens[APos].Text, cHintDirectives) >= 0);
end;

function TIndexTokenReader.EndsHint(APos: Integer): Boolean;
begin
  Result := (APos >= Length(FTokens)) or FTokens[APos].IsSymbol(';') or FTokens[APos].IsSymbol(',') or
    (FTokens[APos].Kind = TPascalTokenKind.StringLiteral) or IsHintAt(APos);
end;

procedure TIndexTokenReader.ReasonAt(APos: Integer; var AText: string);
var
  mNext: Integer;
begin
  if (APos < 0) or (APos >= Length(FTokens)) or not SameText(FTokens[APos].Text, 'deprecated') then
  begin
    Exit;
  end;
  mNext := NextCode(APos + 1);
  if (mNext < Length(FTokens)) and (FTokens[mNext].Kind = TPascalTokenKind.StringLiteral) then
  begin
    AText := Unquoted(FTokens[mNext].Text);
  end;
end;

procedure TIndexTokenReader.HeaderDirectives(AHeader: TSyntaxNode; var AWords: TArray<string>;
  var AReason: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if AHeader[mIndex].Kind = TSyntaxKind.Directive then
    begin
      AddHint(AWords, AHeader[mIndex].Name);
      ReasonAt(TokenIndexAt(AHeader[mIndex].StartOffset), AReason);
    end;
  end;
end;

procedure TIndexTokenReader.HintsBefore(ALast: Integer; var AWords: TArray<string>; var AReason: string);
var
  mIndex: Integer;
begin
  mIndex := ALast;
  while (mIndex > 0) and ((FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive,
    TPascalTokenKind.StringLiteral]) or FTokens[mIndex].IsSymbol(';')) do
  begin
    Dec(mIndex);
  end;
  while (mIndex > 0) and IsHintAt(mIndex) do
  begin
    AddHint(AWords, FTokens[mIndex].Text);
    ReasonAt(mIndex, AReason);
    Dec(mIndex);
    while (mIndex > 0) and ((FTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.StringLiteral]) or
      FTokens[mIndex].IsSymbol(',')) do
    begin
      Dec(mIndex);
    end;
  end;
end;

procedure TIndexTokenReader.HintsAfter(AFirst: Integer; var AWords: TArray<string>; var AReason: string);
var
  mIndex: Integer;
begin
  mIndex := AFirst;
  while (mIndex < Length(FTokens)) and (FTokens[mIndex].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive, TPascalTokenKind.StringLiteral]) do
  begin
    Inc(mIndex);
  end;
  while IsHintAt(mIndex) and EndsHint(NextCode(mIndex + 1)) do
  begin
    AddHint(AWords, FTokens[mIndex].Text);
    ReasonAt(mIndex, AReason);
    mIndex := NextCode(mIndex + 1);
    while (mIndex < Length(FTokens)) and ((FTokens[mIndex].Kind = TPascalTokenKind.StringLiteral) or
      FTokens[mIndex].IsSymbol(',')) do
    begin
      mIndex := NextCode(mIndex + 1);
    end;
  end;
end;

function TIndexTokenReader.DirectivesOf(ANode: TSyntaxNode; AKind: TIndexSymbolKind;
  out ADeprecatedText: string): TArray<string>;
var
  mNode: TSyntaxNode;
  mLast: Integer;
begin
  Result := nil;
  ADeprecatedText := '';
  mNode := TIndexTypeText.HeaderOf(ANode);
  if mNode.Kind = TSyntaxKind.RoutineHeader then
  begin
    HeaderDirectives(mNode, Result, ADeprecatedText);
  end
  else if AKind <> TIndexSymbolKind.EnumMember then
  begin
    mLast := TokenIndexAt(mNode.EndOffset) - 1;
    HintsBefore(mLast, Result, ADeprecatedText);
    HintsAfter(mLast + 1, Result, ADeprecatedText);
  end;
end;

function TIndexTokenReader.ExternalEntries(AHeader: TSyntaxNode): TArray<string>;
var
  mIndex, mToken, mLast: Integer;
  mKey: string;
begin
  Result := nil;
  if (AHeader = nil) or (AHeader.Kind <> TSyntaxKind.RoutineHeader) then
  begin
    Exit;
  end;
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[mIndex].Kind <> TSyntaxKind.Directive) or not SameText(AHeader[mIndex].Name, 'external') then
    begin
      Continue;
    end;
    // external user32 name 'MessageBoxW' index 12: Die Angaben stehen im Bereich der Direktive.
    mToken := NextCode(TokenIndexAt(AHeader[mIndex].StartOffset) + 1);
    mLast := TokenIndexAt(AHeader[mIndex].EndOffset) - 1;
    mKey := 'external';
    while mToken <= mLast do
    begin
      if SameText(FTokens[mToken].Text, 'delayed') then
      begin
        if IndexText('delayed', Result) < 0 then
        begin
          Result := Result + ['delayed'];
        end;
      end
      else if (mKey = '') and (FTokens[mToken].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and
        MatchText(FTokens[mToken].Text, ['name', 'index']) then
      begin
        mKey := LowerCase(FTokens[mToken].Text);
      end
      else if (mKey <> '') and not FTokens[mToken].IsSymbol(';') then
      begin
        Result := Result + [mKey + ':' + Unquoted(FTokens[mToken].Text)];
        mKey := '';
      end;
      mToken := NextCode(mToken + 1);
    end;
  end;
end;

function TIndexTokenReader.MessageEntry(AHeader: TSyntaxNode): string;
var
  mIndex, mToken, mLast: Integer;
begin
  Result := '';
  if (AHeader = nil) or (AHeader.Kind <> TSyntaxKind.RoutineHeader) then
  begin
    Exit;
  end;
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[mIndex].Kind = TSyntaxKind.Directive) and SameText(AHeader[mIndex].Name, 'message') then
    begin
      mToken := NextCode(TokenIndexAt(AHeader[mIndex].StartOffset) + 1);
      mLast := TokenIndexAt(AHeader[mIndex].EndOffset) - 1;
      if mToken <= mLast then
      begin
        Exit('message:' + TokenText(mToken, mLast, False, 0));
      end;
    end;
  end;
end;

function TIndexTokenReader.ConstraintEntries(ANode: TSyntaxNode): TArray<string>;
var
  mParams: TSyntaxNode;
  mIndex, mLast, mDepth: Integer;
  mNames: TArray<string>;
  mConstraints, mName: string;
  mInConstraints: Boolean;
begin
  // <K, V: class; T: IFoo, constructor>: Nach ":" gelten die Einschränkungen bis ";" für alle Namen davor.
  Result := nil;
  mParams := TIndexTypeText.HeaderOf(ANode).FindChild(TSyntaxKind.GenericParams);
  if mParams = nil then
  begin
    Exit;
  end;
  mNames := nil;
  mConstraints := '';
  mInConstraints := False;
  mDepth := 0;
  mIndex := NextCode(TokenIndexAt(mParams.StartOffset) + 1);
  mLast := TokenIndexAt(mParams.EndOffset) - 1;
  while mIndex <= mLast + 1 do
  begin
    if (mIndex > mLast) or ((mDepth = 0) and (FTokens[mIndex].IsSymbol(';') or FTokens[mIndex].IsSymbol('>') or
      FTokens[mIndex].IsSymbol('>='))) then
    begin
      // Ende einer Gruppe: Ihre Einschränkungen gelten für jeden Namen der Gruppe.
      if mConstraints <> '' then
      begin
        for mName in mNames do
        begin
          Result := Result + ['<' + mName + ':' + mConstraints + '>'];
        end;
      end;
      mNames := nil;
      mConstraints := '';
      mInConstraints := False;
      if (mIndex > mLast) or not FTokens[mIndex].IsSymbol(';') then
      begin
        Break;
      end;
    end
    else if (mDepth = 0) and FTokens[mIndex].IsSymbol(':') then
    begin
      mInConstraints := True;
    end
    else if mInConstraints then
    begin
      if FTokens[mIndex].IsSymbol('<') then
      begin
        Inc(mDepth);
      end
      else if (FTokens[mIndex].IsSymbol('>') or FTokens[mIndex].IsSymbol('>=')) and (mDepth > 0) then
      begin
        Dec(mDepth);
      end;
      mConstraints := mConstraints + FTokens[mIndex].Text;
    end
    else if FTokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      mNames := mNames + [FTokens[mIndex].Text];
    end;
    mIndex := NextCode(mIndex + 1);
  end;
end;

function TIndexTokenReader.AfterUnitName(AIndex: Integer): Integer;
var
  mAfterPart: Boolean;
begin
  // Name aus Teilen mit Punkt dazwischen; nach einem Teil ohne folgenden Punkt beginnen die Hinweise.
  Result := AIndex;
  mAfterPart := False;
  while (Result < Length(FTokens)) and not FTokens[Result].IsSymbol(';') do
  begin
    if mAfterPart and not FTokens[Result].IsSymbol('.') then
    begin
      Exit;
    end;
    mAfterPart := not FTokens[Result].IsSymbol('.');
    Result := NextCode(Result + 1);
  end;
end;

procedure TIndexTokenReader.UnitHints(var AUnit: TUnitIndex);
var
  mIndex: Integer;
begin
  // unit A.B deprecated 'Grund' platform;  Kommentare und Direktiven dazwischen überspringen.
  // Der Unit-Name zählt nicht als Hinweis: dpcc.Settings.Experimental ist nicht experimental.
  mIndex := NextCode(0);
  if (mIndex >= Length(FTokens)) or (FTokens[mIndex].Kind <> TPascalTokenKind.Keyword) or
    not SameText(FTokens[mIndex].Text, 'unit') then
  begin
    Exit;
  end;
  mIndex := AfterUnitName(NextCode(mIndex + 1));
  while (mIndex < Length(FTokens)) and not FTokens[mIndex].IsSymbol(';') do
  begin
    if IsHintAt(mIndex) then
    begin
      AddHint(AUnit.Directives, FTokens[mIndex].Text);
      ReasonAt(mIndex, AUnit.DeprecatedText);
    end;
    mIndex := NextCode(mIndex + 1);
  end;
end;

end.
