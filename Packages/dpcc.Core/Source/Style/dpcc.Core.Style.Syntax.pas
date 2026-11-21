unit dpcc.Core.Style.Syntax;

// Einfache Syntaxfärbung für Deklarationen und Signaturen in Detailpanel und
// Parameter-Hint: Schlüsselwörter (samt Direktiven wie overload und dem Typ
// string), String-Literale, Kommentare, Zahlen. Kein Parser: Es geht nur um
// die Farbe kurzer Einzeiler, wie im Entwurf. LineTokens färbt mehrere Zeilen
// (Peek, #505) und trägt offene {…}- und (*…*)-Kommentare in die Folgezeilen.
// Typnamen (LOOK1): SignatureTokens markiert zusätzlich die Typen einer Signatur (TypeRanges) als TypeName; Tokens
// und LineTokens liefern diese Art nie.

interface

uses
  System.SysUtils,
  System.Types;

type
  /// <summary>Art eines Tokens; TypeName nur aus SignatureTokens.</summary>
  TDpccTokenKind = (Plain, Keyword, StringLiteral, Comment, Number, TypeName);

  TDpccToken = record
    /// <summary>0-basiert.</summary>
    Start: Integer;
    /// <summary>Exklusiv.</summary>
    Stop: Integer;
    Kind: TDpccTokenKind;
  end;

  TDpccTokens = TArray<TDpccToken>;

  TDpccSyntax = class
  public
    class function IsKeyword(const AWord: string): Boolean; static;
    /// <summary>Lückenlose Zerlegung von AText; benachbarte Plain-Stücke sind zusammengefasst.</summary>
    class function Tokens(const AText: string): TDpccTokens; static;
    /// <summary>Tokens je Zeile; Kommentare über mehrere Zeilen bleiben Kommentar.</summary>
    class function LineTokens(const ALines: TArray<string>): TArray<TDpccTokens>; static;
    /// <summary>Standardwerte der Parameter (#441): je Parameter der Bereich " = Wert" (0-basiert, Stop
    /// exklusiv, X = Start, Y = Stop) innerhalb der äußersten Klammern einer Signatur.</summary>
    class function DefaultRanges(const ASignature: string): TArray<TPoint>; static;
    /// <summary>Typnamen einer Signatur (LOOK1), aufsteigend, X = Start, Y = Stop (0-basiert, exklusiv): der
    /// Bezeichner direkt hinter einem Doppelpunkt (Parameter-, Rückgabe-, Property-Typ) bzw. hinter „of“ in „array
    /// of X“ und „set of X“, auch mit Punkten und generischen Klammern (System.Classes.TStream, TProc&lt;Integer&gt;).
    /// Er endet vor „;“, „)“, „=“, „,“, einem Leerzeichen oder am Textende. Schlüsselwörter (string, array, const
    /// …) sind keine Typen, ein Standardwert hinter „=“ ebenso wenig; Doppelpunkte in Strings und Kommentaren
    /// zählen nicht.</summary>
    class function TypeRanges(const AText: string): TArray<TPoint>; static;
    /// <summary>Wie Tokens, die Plain-Stücke in TypeRanges als TypeName; Schlüsselwörter darin (TArray&lt;string&gt;)
    /// bleiben Schlüsselwörter.</summary>
    class function SignatureTokens(const AText: string): TDpccTokens; static;
  end;

implementation

uses
  dpcc.Text.Chars;

const
  cKeywords: array of string = [
    'absolute', 'abstract', 'and', 'array', 'as', 'begin', 'case', 'cdecl', 'class', 'const', 'constructor',
    'default', 'deprecated', 'destructor', 'dispinterface', 'div', 'do', 'downto', 'dynamic', 'else', 'end',
    'except', 'experimental', 'export', 'external', 'file', 'final', 'finalization', 'finally', 'for',
    'forward', 'function', 'goto', 'helper', 'if', 'implementation', 'implements', 'in', 'index', 'inherited',
    'initialization', 'inline', 'interface', 'is', 'label', 'library', 'message', 'mod', 'nil', 'nodefault',
    'not', 'object', 'of', 'on', 'or', 'out', 'overload', 'override', 'packed', 'platform', 'private',
    'procedure', 'program', 'property', 'protected', 'public', 'published', 'raise', 'read', 'record',
    'reference', 'reintroduce', 'repeat', 'resourcestring', 'safecall', 'sealed', 'set', 'shl', 'shr',
    'static', 'stdcall', 'stored', 'strict', 'string', 'then', 'threadvar', 'to',
    'try', 'type', 'unit', 'until', 'uses', 'var', 'virtual', 'while', 'with', 'write', 'xor'];

{ Lesen ab einer 1-basierten Position }

/// <summary>Steht hinter AIndex das Zeichen ANext?</summary>
function IsPairAt(const AText: string; AIndex: Integer; ANext: Char): Boolean;
begin
  Result := (AIndex < Length(AText)) and (AText[AIndex + 1] = ANext);
end;

/// <summary>Position hinter dem schließenden Anführungszeichen des Strings an AIndex.</summary>
function AfterQuote(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= Length(AText)) and (AText[Result] <> '''') do
  begin
    Inc(Result);
  end;
  Inc(Result);
end;

/// <summary>Position hinter „}“ des Kommentars an AIndex; Length + 2, wenn er offen bleibt.</summary>
function AfterBrace(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and (AText[Result] <> '}') do
  begin
    Inc(Result);
  end;
  Inc(Result);
end;

/// <summary>Position hinter „*)“ des Kommentars „(*“ an AIndex; über Length + 1, wenn er offen bleibt.</summary>
function AfterParenStar(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 2;
  while (Result < Length(AText)) and not ((AText[Result] = '*') and (AText[Result + 1] = ')')) do
  begin
    Inc(Result);
  end;
  Inc(Result, 2);
end;

/// <summary>Bezeichner ab AIndex; nach einem Punkt ist es ein Name (TFoo.Create, Self.Read), kein
/// Schlüsselwort.</summary>
function WordAt(const AText: string; var AIndex: Integer): TDpccTokenKind;
var
  mStart: Integer;
begin
  mStart := AIndex;
  while (AIndex <= Length(AText)) and TTextChars.IsIdentChar(AText[AIndex]) do
  begin
    Inc(AIndex);
  end;
  Result := TDpccTokenKind.Plain;
  if ((mStart = 1) or (AText[mStart - 1] <> '.')) and
    TDpccSyntax.IsKeyword(Copy(AText, mStart, AIndex - mStart)) then
  begin
    Result := TDpccTokenKind.Keyword;
  end;
end;

function NumberEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result <= Length(AText)) and CharInSet(AText[Result], ['0'..'9', 'A'..'F', 'a'..'f', '.']) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Art des Tokens ab AIndex; AIndex steht danach hinter ihm.</summary>
function TokenAt(const AText: string; var AIndex: Integer): TDpccTokenKind;
begin
  Result := TDpccTokenKind.Comment;
  if AText[AIndex] = '''' then
  begin
    AIndex := AfterQuote(AText, AIndex);
    Result := TDpccTokenKind.StringLiteral;
  end
  else if AText[AIndex] = '{' then
  begin
    AIndex := AfterBrace(AText, AIndex);
  end
  else if (AText[AIndex] = '(') and IsPairAt(AText, AIndex, '*') then
  begin
    AIndex := AfterParenStar(AText, AIndex);
  end
  else if (AText[AIndex] = '/') and IsPairAt(AText, AIndex, '/') then
  begin
    AIndex := Length(AText) + 1;
  end
  else if TTextChars.IsIdentStart(AText[AIndex]) then
  begin
    Result := WordAt(AText, AIndex);
  end
  else if CharInSet(AText[AIndex], ['0'..'9', '$']) then
  begin
    AIndex := NumberEnd(AText, AIndex);
    Result := TDpccTokenKind.Number;
  end
  else
  begin
    Inc(AIndex);
    Result := TDpccTokenKind.Plain;
  end;
end;

type
  /// <summary>Wachsende Liste der Tokens; benachbarte Plain-Stücke werden zusammengefasst.</summary>
  TTokenList = record
    Items: TDpccTokens;
    Count: Integer;
    procedure Emit(AStart, AStop: Integer; AKind: TDpccTokenKind);
    function Done: TDpccTokens;
  end;

procedure TTokenList.Emit(AStart, AStop: Integer; AKind: TDpccTokenKind);
begin
  if AStop <= AStart then
  begin
    Exit;
  end;
  if (AKind = TDpccTokenKind.Plain) and (Count > 0) and (Items[Count - 1].Kind = TDpccTokenKind.Plain) and
    (Items[Count - 1].Stop = AStart) then
  begin
    Items[Count - 1].Stop := AStop;
    Exit;
  end;
  if Count = Length(Items) then
  begin
    SetLength(Items, Count * 2 + 4);
  end;
  Items[Count].Start := AStart;
  Items[Count].Stop := AStop;
  Items[Count].Kind := AKind;
  Inc(Count);
end;

function TTokenList.Done: TDpccTokens;
begin
  SetLength(Items, Count);
  Result := Items;
end;

{ TDpccSyntax }

class function TDpccSyntax.IsKeyword(const AWord: string): Boolean;
var
  mWord: string;
begin
  for mWord in cKeywords do
  begin
    if SameText(mWord, AWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDpccSyntax.Tokens(const AText: string): TDpccTokens;
var
  mList: TTokenList;
  mIndex, mStart: Integer;
  mKind: TDpccTokenKind;
begin
  mList := Default(TTokenList);
  // Index 1-basiert über den String; Tokens 0-basiert.
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mStart := mIndex;
    mKind := TokenAt(AText, mIndex);
    if mIndex > Length(AText) + 1 then
    begin
      mIndex := Length(AText) + 1;
    end;
    mList.Emit(mStart - 1, mIndex - 1, mKind);
  end;
  Result := mList.Done;
end;

type
{$SCOPEDENUMS ON}
  TOpenComment = (None, Brace, ParenStar);
{$SCOPEDENUMS OFF}

/// <summary>Überspringt das Zeichen bzw. den String oder Kommentar an AIndex (danach auf seinem letzten
/// Zeichen). False am Zeilenkommentar oder an einem offenen Kommentar (AOpen).</summary>
function SkipAt(const AText: string; var AIndex: Integer; out AOpen: TOpenComment): Boolean;
var
  mClose: Integer;
begin
  AOpen := TOpenComment.None;
  Result := True;
  mClose := AIndex + 1;
  case AText[AIndex] of
    '''':
      mClose := AfterQuote(AText, AIndex);
    '/':
      Result := not IsPairAt(AText, AIndex, '/');
    '{':
      begin
        mClose := AfterBrace(AText, AIndex);
        AOpen := TOpenComment.Brace;
      end;
    '(':
      if IsPairAt(AText, AIndex, '*') then
      begin
        mClose := AfterParenStar(AText, AIndex);
        AOpen := TOpenComment.ParenStar;
      end;
  end;
  if (AOpen <> TOpenComment.None) and (mClose > Length(AText) + 1) then
  begin
    Result := False;
  end
  else
  begin
    AOpen := TOpenComment.None;
    AIndex := mClose - 1;
  end;
end;

/// <summary>Kommentar, der am Ende von AText (ab dem 1-basierten AFrom) offen bleibt.</summary>
function OpenAtEnd(const AText: string; AFrom: Integer): TOpenComment;
var
  mIndex: Integer;
begin
  Result := TOpenComment.None;
  mIndex := AFrom;
  while (mIndex <= Length(AText)) and SkipAt(AText, mIndex, Result) do
  begin
    Inc(mIndex);
  end;
end;

/// <summary>1-basierte Position hinter dem Ende des offenen Kommentars AState in AText; 0, wenn er weiter offen
/// bleibt.</summary>
function CommentEnd(const AText: string; AState: TOpenComment): Integer;
begin
  Result := 0;
  if AState = TOpenComment.Brace then
  begin
    Result := Pos('}', AText) + 1;
  end
  else if Pos('*)', AText) > 0 then
  begin
    Result := Pos('*)', AText) + 2;
  end;
  if Result = 1 then
  begin
    Result := 0;
  end;
end;

function CommentToken(AStop: Integer): TDpccTokens;
var
  mHead: TDpccToken;
begin
  Result := nil;
  if AStop > 0 then
  begin
    mHead.Start := 0;
    mHead.Stop := AStop;
    mHead.Kind := TDpccTokenKind.Comment;
    Result := [mHead];
  end;
end;

function Shifted(const ATokens: TDpccTokens; AOffset: Integer): TDpccTokens;
var
  mIndex: Integer;
begin
  Result := Copy(ATokens);
  for mIndex := 0 to High(Result) do
  begin
    Inc(Result[mIndex].Start, AOffset);
    Inc(Result[mIndex].Stop, AOffset);
  end;
end;

class function TDpccSyntax.LineTokens(const ALines: TArray<string>): TArray<TDpccTokens>;
var
  mLine, mClose, mOffset: Integer;
  mState: TOpenComment;
  mText: string;
begin
  Result := nil;
  SetLength(Result, Length(ALines));
  mState := TOpenComment.None;
  for mLine := 0 to High(ALines) do
  begin
    mText := ALines[mLine];
    mOffset := 0;
    Result[mLine] := nil;
    if mState <> TOpenComment.None then
    begin
      mClose := CommentEnd(mText, mState);
      if mClose = 0 then
      begin
        Result[mLine] := CommentToken(Length(mText));
        Continue;
      end;
      Result[mLine] := CommentToken(mClose - 1);
      mOffset := mClose - 1;
    end;
    Result[mLine] := Result[mLine] + Shifted(Tokens(Copy(mText, mOffset + 1, MaxInt)), mOffset);
    mState := OpenAtEnd(mText, mOffset + 1);
  end;
end;

type
  /// <summary>Zustand von DefaultRanges: Klammertiefe und Anfang des offenen Standardwerts (0-basiert, -1 ohne).
  /// </summary>
  TDefaultScan = record
    Depth: Integer;
    Start: Integer;
    Ranges: TArray<TPoint>;
    /// <summary>Offener Standardwert endet vor AIndex.</summary>
    procedure Close(AIndex: Integer);
    procedure Take(const ASignature: string; AIndex: Integer);
  end;

procedure TDefaultScan.Close(AIndex: Integer);
begin
  if (Depth = 1) and (Start >= 0) then
  begin
    Ranges := Ranges + [Point(Start, AIndex - 1)];
    Start := -1;
  end;
end;

procedure TDefaultScan.Take(const ASignature: string; AIndex: Integer);
begin
  case ASignature[AIndex] of
    '(', '[':
      Inc(Depth);
    ')', ']':
      begin
        Close(AIndex);
        Dec(Depth);
      end;
    ';':
      Close(AIndex);
    '=':
      if (Depth = 1) and (Start < 0) then
      begin
        // Leerzeichen vor "=" gehören dazu: "Offset: Integer = 1" → " = 1".
        Start := AIndex - 1;
        while (Start > 0) and (ASignature[Start] = ' ') do
        begin
          Dec(Start);
        end;
      end;
  end;
end;

class function TDpccSyntax.DefaultRanges(const ASignature: string): TArray<TPoint>;
var
  mIndex: Integer;
  mScan: TDefaultScan;
  mInString: Boolean;
begin
  // 1-basiert über den Text; Ergebnis 0-basiert. "=" auf Ebene 1 beginnt einen Standardwert, der bis
  // vor das nächste ";" bzw. die schließende Klammer derselben Ebene reicht.
  mScan := Default(TDefaultScan);
  mScan.Start := -1;
  mInString := False;
  for mIndex := 1 to Length(ASignature) do
  begin
    if ASignature[mIndex] = '''' then
    begin
      mInString := not mInString;
    end;
    if not mInString then
    begin
      mScan.Take(ASignature, mIndex);
    end;
  end;
  Result := mScan.Ranges;
end;

{ Typnamen (LOOK1), 1-basiert über den Text }

/// <summary>Position hinter dem Bezeichner an AIndex.</summary>
function IdentEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and TTextChars.IsIdentChar(AText[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Erste Position ab AIndex, die kein Leerzeichen bzw. Tabulator ist.</summary>
function SkipBlanks(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and CharInSet(AText[Result], [' ', #9]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Position hinter den generischen Klammern „&lt;…&gt;“ an AIndex (auch verschachtelt); AIndex selbst,
/// wenn dort keine stehen oder sie vor „;“, „)“, „=“, „:“, einem String oder Kommentar nicht schließen.</summary>
function GenericEnd(const AText: string; AIndex: Integer): Integer;
var
  mIndex, mDepth: Integer;
begin
  Result := AIndex;
  if (AIndex > Length(AText)) or (AText[AIndex] <> '<') then
  begin
    Exit;
  end;
  mDepth := 0;
  mIndex := AIndex;
  while mIndex <= Length(AText) do
  begin
    case AText[mIndex] of
      '<':
        Inc(mDepth);
      '>':
        begin
          Dec(mDepth);
          if mDepth = 0 then
          begin
            Exit(mIndex + 1);
          end;
        end;
      ';', ')', '(', '=', ':', '''', '{':
        Exit;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Typname ab AIndex (davor nur Leerzeichen) nach ARanges; AIndex steht danach hinter ihm. Ein
/// Schlüsselwort ist kein Typ: AIndex steht dann vor ihm, damit der Aufrufer es liest („array of …“).</summary>
procedure TakeType(const AText: string; var AIndex: Integer; var ARanges: TArray<TPoint>);
var
  mStart, mStop: Integer;
begin
  mStart := SkipBlanks(AText, AIndex);
  if (mStart > Length(AText)) or not TTextChars.IsIdentStart(AText[mStart]) then
  begin
    Exit;
  end;
  mStop := IdentEnd(AText, mStart);
  if TDpccSyntax.IsKeyword(Copy(AText, mStart, mStop - mStart)) then
  begin
    AIndex := mStart;
    Exit;
  end;
  // Qualifizierter Name: System.Classes.TStream.
  while (mStop < Length(AText)) and (AText[mStop] = '.') and TTextChars.IsIdentStart(AText[mStop + 1]) do
  begin
    mStop := IdentEnd(AText, mStop + 1);
  end;
  mStop := GenericEnd(AText, mStop);
  ARanges := ARanges + [Point(mStart - 1, mStop - 1)];
  AIndex := mStop;
end;

/// <summary>Folgt hinter „array“ bzw. „set“ (AIndex steht hinter dem Wort) nach Leerzeichen und wahlweise „[…]“
/// das Wort „of“? AIndex steht dann hinter „of“, sonst bleibt er.</summary>
function OfFollows(const AText: string; var AIndex: Integer): Boolean;
var
  mIndex, mStop: Integer;
begin
  Result := False;
  mIndex := SkipBlanks(AText, AIndex);
  if (mIndex <= Length(AText)) and (AText[mIndex] = '[') then
  begin
    while (mIndex <= Length(AText)) and (AText[mIndex] <> ']') do
    begin
      Inc(mIndex);
    end;
    mIndex := SkipBlanks(AText, mIndex + 1);
  end;
  if (mIndex > Length(AText)) or not TTextChars.IsIdentStart(AText[mIndex]) then
  begin
    Exit;
  end;
  mStop := IdentEnd(AText, mIndex);
  if SameText(Copy(AText, mIndex, mStop - mIndex), 'of') then
  begin
    AIndex := mStop;
    Result := True;
  end;
end;

class function TDpccSyntax.TypeRanges(const AText: string): TArray<TPoint>;
var
  mIndex, mStop: Integer;
  mWord: string;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    // Strings und Kommentare überspringen: Ihre Doppelpunkte beginnen keinen Typ.
    if AText[mIndex] = '''' then
    begin
      mIndex := AfterQuote(AText, mIndex);
    end
    else if AText[mIndex] = '{' then
    begin
      mIndex := AfterBrace(AText, mIndex);
    end
    else if (AText[mIndex] = '(') and IsPairAt(AText, mIndex, '*') then
    begin
      mIndex := AfterParenStar(AText, mIndex);
    end
    else if (AText[mIndex] = '/') and IsPairAt(AText, mIndex, '/') then
    begin
      Break;
    end
    else if (AText[mIndex] = ':') and not IsPairAt(AText, mIndex, '=') then
    begin
      Inc(mIndex);
      TakeType(AText, mIndex, Result);
    end
    else if TTextChars.IsIdentStart(AText[mIndex]) then
    begin
      mStop := IdentEnd(AText, mIndex);
      mWord := Copy(AText, mIndex, mStop - mIndex);
      // Nach einem Punkt ist es ein Name (TFoo.Set), kein Schlüsselwort.
      if ((mIndex = 1) or (AText[mIndex - 1] <> '.')) and (SameText(mWord, 'array') or SameText(mWord, 'set')) and
        OfFollows(AText, mStop) then
      begin
        TakeType(AText, mStop, Result);
      end;
      mIndex := mStop;
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
end;

class function TDpccSyntax.SignatureTokens(const AText: string): TDpccTokens;
var
  mList: TTokenList;
  mToken: TDpccToken;
  mRanges: TArray<TPoint>;
  mRange: TPoint;
  mFrom, mStart, mStop: Integer;
begin
  mRanges := TypeRanges(AText);
  if Length(mRanges) = 0 then
  begin
    Exit(Tokens(AText));
  end;
  mList := Default(TTokenList);
  for mToken in Tokens(AText) do
  begin
    // Nur Plain wird Typ; Schlüsselwörter, Strings, Kommentare und Zahlen bleiben.
    if mToken.Kind <> TDpccTokenKind.Plain then
    begin
      mList.Emit(mToken.Start, mToken.Stop, mToken.Kind);
      Continue;
    end;
    mFrom := mToken.Start;
    for mRange in mRanges do
    begin
      if (mRange.Y <= mFrom) or (mRange.X >= mToken.Stop) then
      begin
        Continue;
      end;
      mStart := mRange.X;
      if mStart < mFrom then
      begin
        mStart := mFrom;
      end;
      mStop := mRange.Y;
      if mStop > mToken.Stop then
      begin
        mStop := mToken.Stop;
      end;
      mList.Emit(mFrom, mStart, TDpccTokenKind.Plain);
      mList.Emit(mStart, mStop, TDpccTokenKind.TypeName);
      mFrom := mStop;
    end;
    mList.Emit(mFrom, mToken.Stop, TDpccTokenKind.Plain);
  end;
  Result := mList.Done;
end;

end.
