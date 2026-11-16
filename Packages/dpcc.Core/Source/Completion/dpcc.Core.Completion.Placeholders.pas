unit dpcc.Core.Completion.Placeholders;

// Platzhalter-Modus nach dem Einsetzen eines Eintrags mit Platzhaltern (#51), ohne Editor: Lage
// der Platzhalter im Dokument, Tab-Reihenfolge und verknüpfte Platzhalter.
//
// Positionen sind 0-basierte Offsets in UTF-16-Einheiten im ganzen Text. Nach
// jeder Änderung bekommt Update den neuen Text. Liegt die Änderung ganz in
// einem Platzhalter der aktuellen Nummer, wächst oder schrumpft dieser und
// alles dahinter verschiebt sich; sonst endet der Modus. MirrorEdits liefert
// danach die Änderungen, die die verknüpften Platzhalter angleichen; nach dem
// Schreiben meldet Applied sie zurück.
//
// Text mit Platzhaltern (TDpccPlaceholderText, seit S2 hier statt in der früheren Unit der Code-Vorlagen):
//   ${1:List}  Platzhalter 1 mit Vorgabetext
//   ${2}       Platzhalter 2 ohne Vorgabe
//   $0, ${0}   Cursor nach dem letzten Platzhalter
// Wiederholte Nummern sind verknüpft und zeigen denselben Text. Ein "$" vor
// etwas anderem bleibt stehen, auch "$0F" oder "$FF": Hexzahlen im Delphi-Code
// sind keine Platzhalter. "$$" steht für ein einzelnes "$". Einträge des Servers
// mit insertTextFormat 2 (LSP-Syntax) wandelt FromLsp in dieses Format.

interface

uses
  System.SysUtils;

type
  /// <summary>Platzhalter im eingesetzten Text.</summary>
  TDpccPlaceholderStop = record
    /// <summary>0 = Endposition.</summary>
    Number: Integer;
    /// <summary>0-basiert, UTF-16-Einheiten ab dem Anfang des eingesetzten Texts.</summary>
    Start: Integer;
    Length: Integer;
  end;

  /// <summary>Eingesetzter Text und seine Platzhalter.</summary>
  TDpccPlaceholderExpansion = record
    Text: string;
    /// <summary>In Textreihenfolge.</summary>
    Stops: TArray<TDpccPlaceholderStop>;
    /// <summary>Gibt es Platzhalter mit Nummer ab 1?</summary>
    function HasPlaceholders: Boolean;
  end;

  /// <summary>Text mit Platzhaltern (${1:Vorgabe}, ${2}, $0, $$) einsetzen bzw. aus der LSP-Syntax übernehmen.
  /// </summary>
  TDpccPlaceholderText = class
  public
    /// <summary>Setzt ABody ein: jede Zeile nach der ersten bekommt AIndent vorangestellt, Zeilenumbrüche werden
    /// zu ALineBreak, Platzhalter zu ihrem Vorgabetext (verknüpfte zum ersten vorhandenen).</summary>
    class function Expand(const ABody, AIndent, ALineBreak: string): TDpccPlaceholderExpansion; static;
    /// <summary>Klartext ohne Platzhalter, Zeilen mit #10.</summary>
    class function PlainText(const ABody: string): string; static;
    /// <summary>Text des Servers (LSP-Syntax, insertTextFormat 2) im eigenen Format: \$ wird zu $$, $1 zu ${1},
    /// Auswahl ${1|a,b|} zu ${1:a}; verschachtelte Platzhalter und ${NAME:…} werden zu ihrem Vorgabetext, "$" vor
    /// einem Buchstaben bleibt Text.</summary>
    class function FromLsp(const AText: string): string; static;
  end;

  TDpccPlaceholderField = record
    Number: Integer;
    Start: Integer;
    Length: Integer;
    function Stop: Integer;
  end;

  /// <summary>Ersetzt Start bis Stop (Offsets im Text vor der Änderung) durch Text.</summary>
  TDpccPlaceholderEdit = record
    Start: Integer;
    Stop: Integer;
    Text: string;
  end;

  TDpccPlaceholderEdits = TArray<TDpccPlaceholderEdit>;

  TDpccPlaceholderSession = class
  private
    FText: string;
    FFields: TArray<TDpccPlaceholderField>;
    /// <summary>Nummern in Tab-Reihenfolge: 1, 2, … aufsteigend, zuletzt 0.</summary>
    FOrder: TArray<Integer>;
    FCurrent: Integer;
    /// <summary>Zuletzt bearbeiteter Platzhalter der aktuellen Nummer; Vorlage für die verknüpften.</summary>
    FPrimary: Integer;
    procedure Shift(AFrom, ADelta, AExcept: Integer);
    function FirstOf(ANumber: Integer): Integer;
  public
    /// <summary>ADocument: Text nach dem Einsetzen; AOffset: Anfang des eingesetzten Texts darin.
    /// Ohne $0 endet die Vorlage hinter ihrem Text.</summary>
    constructor Create(const ADocument: string; AOffset: Integer; const AExpansion: TDpccPlaceholderExpansion);
    /// <summary>Weiterer Platzhalter außerhalb der Vorlage (Offset im ganzen Text, #473), verknüpft mit den
    /// gleich nummerierten; ohne solche Nummer oder mit Nummer 0 übergangen. Der Cursor bleibt in der Vorlage.
    /// </summary>
    procedure Link(const AField: TDpccPlaceholderField);
    /// <summary>Nummer des aktuellen Platzhalters; 0 = Endposition (Modus vorbei).</summary>
    function CurrentNumber: Integer;
    /// <summary>Stelle des aktuellen Platzhalters ab 1 und Zahl der nummerierten, für die Fußzeile.</summary>
    function Position: Integer;
    function Count: Integer;
    /// <summary>Der Platzhalter, in dem der Cursor steht (zuletzt bearbeitet bzw. erster der Nummer).</summary>
    function Current: TDpccPlaceholderField;
    /// <summary>Alle Platzhalter ohne die Endposition, in Textreihenfolge.</summary>
    function Fields: TArray<TDpccPlaceholderField>;
    /// <summary>Endposition ($0 bzw. Ende der Vorlage).</summary>
    function FinalOffset: Integer;
    /// <summary>Tab: zum nächsten Platzhalter. False, wenn danach nur noch die Endposition kommt.</summary>
    function Next: Boolean;
    /// <summary>Umschalt+Tab: zum vorigen; am ersten bleibt es dort.</summary>
    procedure Previous;
    /// <summary>Text geändert. False, wenn die Änderung nicht in einem Platzhalter der aktuellen Nummer
    /// liegt.</summary>
    function Update(const ADocument: string): Boolean;
    /// <summary>Änderungen, die die verknüpften Platzhalter an den aktuellen angleichen; aufsteigend.</summary>
    function MirrorEdits: TDpccPlaceholderEdits;
    /// <summary>Die Änderungen aus MirrorEdits sind geschrieben.</summary>
    procedure Applied(const AEdits: TDpccPlaceholderEdits);
    function FieldText(const AField: TDpccPlaceholderField): string;
    /// <summary>Zeile und Zeichen (0-basiert) zum Offset AOffset in AText; Zeilen enden mit #10.</summary>
    class procedure Locate(const AText: string; AOffset: Integer; out ALine, ACharacter: Integer); static;
    property Text: string read FText;
  end;

implementation

uses
  System.Math,
  dpcc.Text.Chars;

{ Text mit Platzhaltern }

type
  TSegment = record
    IsStop: Boolean;
    Number: Integer;
    HasDefault: Boolean;
    Text: string;
  end;

function IsDigit(AC: Char): Boolean;
begin
  Result := (AC >= '0') and (AC <= '9');
end;

function NormalizeBreaks(const AText: string): string;
begin
  Result := StringReplace(StringReplace(AText, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
end;

procedure FlushLiteral(var ASegments: TArray<TSegment>; var ALiteral: string);
var
  mSegment: TSegment;
begin
  if ALiteral = '' then
  begin
    Exit;
  end;
  mSegment := Default(TSegment);
  mSegment.Text := ALiteral;
  ASegments := ASegments + [mSegment];
  ALiteral := '';
end;

/// <summary>${n} bzw. ${n:Vorgabe} ab dem "$" an AIndex; ANext: Index hinter "}".</summary>
function TryBracedStop(const ABody: string; AIndex: Integer; out ASegment: TSegment; out ANext: Integer): Boolean;
var
  mClose, mColon, mNumber: Integer;
  mInner: string;
begin
  ASegment := Default(TSegment);
  ANext := AIndex;
  if not ((AIndex + 2 <= Length(ABody)) and (ABody[AIndex + 1] = '{') and IsDigit(ABody[AIndex + 2])) then
  begin
    Exit(False);
  end;
  mClose := AIndex + 2;
  while (mClose <= Length(ABody)) and (ABody[mClose] <> '}') and (ABody[mClose] <> #10) do
  begin
    Inc(mClose);
  end;
  mInner := Copy(ABody, AIndex + 2, mClose - AIndex - 2);
  mColon := Pos(':', mInner);
  if mColon = 0 then
  begin
    mColon := Length(mInner) + 1;
  end;
  Result := (mClose <= Length(ABody)) and (ABody[mClose] = '}') and
    TryStrToInt(Copy(mInner, 1, mColon - 1), mNumber) and (mNumber >= 0);
  if Result then
  begin
    ASegment.IsStop := True;
    ASegment.Number := mNumber;
    ASegment.HasDefault := mColon <= Length(mInner);
    ASegment.Text := Copy(mInner, mColon + 1, MaxInt);
    ANext := mClose + 1;
  end;
end;

/// <summary>$0 allein, nicht $0F, ab dem "$" an AIndex.</summary>
function TryEndStop(const ABody: string; AIndex: Integer; out ASegment: TSegment; out ANext: Integer): Boolean;
begin
  ASegment := Default(TSegment);
  ANext := AIndex + 2;
  Result := (AIndex < Length(ABody)) and (ABody[AIndex + 1] = '0') and
    ((AIndex + 2 > Length(ABody)) or not TTextChars.IsAsciiIdentChar(ABody[AIndex + 2]));
  ASegment.IsStop := Result;
end;

/// <summary>Zerlegt den Text in Klartext und Platzhalter.</summary>
function Segments(const ABody: string): TArray<TSegment>;
var
  mIndex, mNext: Integer;
  mLiteral: string;
  mSegment: TSegment;
begin
  Result := nil;
  mLiteral := '';
  mIndex := 1;
  while mIndex <= Length(ABody) do
  begin
    if ABody[mIndex] <> '$' then
    begin
      mLiteral := mLiteral + ABody[mIndex];
      Inc(mIndex);
    end
    // "$$" = "$"
    else if (mIndex < Length(ABody)) and (ABody[mIndex + 1] = '$') then
    begin
      mLiteral := mLiteral + '$';
      Inc(mIndex, 2);
    end
    else if TryBracedStop(ABody, mIndex, mSegment, mNext) or TryEndStop(ABody, mIndex, mSegment, mNext) then
    begin
      FlushLiteral(Result, mLiteral);
      Result := Result + [mSegment];
      mIndex := mNext;
    end
    else
    begin
      mLiteral := mLiteral + '$';
      Inc(mIndex);
    end;
  end;
  FlushLiteral(Result, mLiteral);
end;

function ConvertLsp(const AText: string; var AIndex: Integer; ATop: Boolean): string; forward;

/// <summary>"\" an AIndex: maskiertes Zeichen (auf oberster Ebene "\$" als "$$"), sonst "\" selbst.</summary>
function EscapeAt(const AText: string; var AIndex: Integer; ATop: Boolean): string;
begin
  if (AIndex < Length(AText)) and CharInSet(AText[AIndex + 1], ['\', '$', '}', ',', '|']) then
  begin
    Result := AText[AIndex + 1];
    if ATop and (Result = '$') then
    begin
      Result := '$$';
    end;
    Inc(AIndex, 2);
  end
  else
  begin
    Result := '\';
    Inc(AIndex);
  end;
end;

procedure SkipPast(const AText: string; var AIndex: Integer; AChar: Char);
begin
  while (AIndex <= Length(AText)) and (AText[AIndex] <> AChar) do
  begin
    Inc(AIndex);
  end;
  Inc(AIndex);
end;

/// <summary>Auswahl ${n|a,b|} ab hinter "|": die erste Möglichkeit als Vorgabe; AIndex danach hinter "}".</summary>
function ChoiceDefault(const AText: string; var AIndex: Integer): string;
var
  mStart: Integer;
begin
  mStart := AIndex;
  while (AIndex <= Length(AText)) and not CharInSet(AText[AIndex], [',', '|']) do
  begin
    Inc(AIndex);
  end;
  Result := Copy(AText, mStart, AIndex - mStart);
  SkipPast(AText, AIndex, '}');
end;

/// <summary>Vorgabe eines Platzhalters in Klammern ab hinter dem Namen; AIndex danach hinter "}".</summary>
function BracedDefault(const AText: string; var AIndex: Integer): string;
begin
  Result := '';
  if (AIndex <= Length(AText)) and (AText[AIndex] = ':') then
  begin
    Inc(AIndex);
    Result := ConvertLsp(AText, AIndex, False);
  end
  else if (AIndex <= Length(AText)) and (AText[AIndex] = '|') then
  begin
    Inc(AIndex);
    Result := ChoiceDefault(AText, AIndex);
  end
  else
  begin
    SkipPast(AText, AIndex, '}');
  end;
end;

/// <summary>Tabstopp nur auf oberster Ebene und mit Nummer; Variablen werden zu ihrer Vorgabe.</summary>
function StopText(const ANumber, ADefault: string; ATop: Boolean): string;
begin
  if not (ATop and (ANumber <> '') and IsDigit(ANumber[1])) then
  begin
    Result := ADefault;
  end
  else if (ADefault = '') and (ANumber = '0') then
  begin
    Result := '$0';
  end
  else if ADefault = '' then
  begin
    Result := '${' + ANumber + '}';
  end
  else
  begin
    Result := '${' + ANumber + ':' + ADefault + '}';
  end;
end;

/// <summary>$1, ${1}, ${1:Vorgabe}, ${1|a,b|}, ${NAME:Vorgabe} ab dem "$" an AIndex.</summary>
function PlaceholderAt(const AText: string; var AIndex: Integer; ATop: Boolean): string;
var
  mStart: Integer;
  mBraced: Boolean;
  mNumber, mDefault: string;
begin
  Inc(AIndex);
  mBraced := AText[AIndex] = '{';
  if mBraced then
  begin
    Inc(AIndex);
  end;
  mStart := AIndex;
  while (AIndex <= Length(AText)) and TTextChars.IsAsciiIdentChar(AText[AIndex]) do
  begin
    Inc(AIndex);
  end;
  mNumber := Copy(AText, mStart, AIndex - mStart);
  mDefault := '';
  if mBraced then
  begin
    mDefault := BracedDefault(AText, AIndex);
  end;
  Result := StopText(mNumber, mDefault, ATop);
end;

/// <summary>"$" an AIndex beginnt einen Platzhalter; "$" vor einem Buchstaben bleibt Text ($FF).</summary>
function IsPlaceholderStart(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (AText[AIndex] = '$') and (AIndex < Length(AText)) and
    (IsDigit(AText[AIndex + 1]) or (AText[AIndex + 1] = '{'));
end;

/// <summary>Liest ab AIndex Klartext bis zum passenden "}" bzw. Textende (verschachtelte Platzhalter und Variablen
/// werden zu ihrer Vorgabe). Mit ATop entsteht das eigene Format ($$, ${n}, ${n:Vorgabe}).</summary>
function ConvertLsp(const AText: string; var AIndex: Integer; ATop: Boolean): string;
begin
  Result := '';
  while AIndex <= Length(AText) do
  begin
    if AText[AIndex] = '\' then
    begin
      Result := Result + EscapeAt(AText, AIndex, ATop);
    end
    else if (AText[AIndex] = '}') and not ATop then
    begin
      Inc(AIndex);
      Exit;
    end
    else if IsPlaceholderStart(AText, AIndex) then
    begin
      Result := Result + PlaceholderAt(AText, AIndex, ATop);
    end
    // Ein "$" ohne Platzhalter bleibt Text.
    else if ATop and (AText[AIndex] = '$') then
    begin
      Result := Result + '$$';
      Inc(AIndex);
    end
    else
    begin
      Result := Result + AText[AIndex];
      Inc(AIndex);
    end;
  end;
end;

{ TDpccPlaceholderExpansion }

function TDpccPlaceholderExpansion.HasPlaceholders: Boolean;
var
  mStop: TDpccPlaceholderStop;
begin
  Result := False;
  for mStop in Stops do
  begin
    if mStop.Number > 0 then
    begin
      Exit(True);
    end;
  end;
end;

{ TDpccPlaceholderText }

class function TDpccPlaceholderText.Expand(const ABody, AIndent, ALineBreak: string): TDpccPlaceholderExpansion;
var
  mParts: TArray<TSegment>;
  mDefaults: TArray<string>;
  mKnown: TArray<Boolean>;
  mIndex, mNumber, mHighest: Integer;
  mText: string;
  mStop: TDpccPlaceholderStop;

  function Indented(const AValue: string): string;
  begin
    Result := StringReplace(NormalizeBreaks(AValue), #10, ALineBreak + AIndent, [rfReplaceAll]);
  end;

begin
  Result := Default(TDpccPlaceholderExpansion);
  mParts := Segments(NormalizeBreaks(ABody));
  // Vorgabetext je Nummer: der erste vorhandene.
  mHighest := 0;
  for mIndex := 0 to High(mParts) do
  begin
    if mParts[mIndex].IsStop and (mParts[mIndex].Number > mHighest) then
    begin
      mHighest := mParts[mIndex].Number;
    end;
  end;
  SetLength(mDefaults, mHighest + 1);
  SetLength(mKnown, mHighest + 1);
  for mIndex := 0 to High(mParts) do
  begin
    if mParts[mIndex].IsStop and mParts[mIndex].HasDefault and not mKnown[mParts[mIndex].Number] then
    begin
      mDefaults[mParts[mIndex].Number] := mParts[mIndex].Text;
      mKnown[mParts[mIndex].Number] := True;
    end;
  end;
  mText := '';
  for mIndex := 0 to High(mParts) do
  begin
    if mParts[mIndex].IsStop then
    begin
      mNumber := mParts[mIndex].Number;
      mStop.Number := mNumber;
      mStop.Start := Length(mText);
      mText := mText + Indented(mDefaults[mNumber]);
      mStop.Length := Length(mText) - mStop.Start;
      Result.Stops := Result.Stops + [mStop];
    end
    else
    begin
      mText := mText + Indented(mParts[mIndex].Text);
    end;
  end;
  Result.Text := mText;
end;

class function TDpccPlaceholderText.PlainText(const ABody: string): string;
begin
  Result := Expand(ABody, '', #10).Text;
end;

class function TDpccPlaceholderText.FromLsp(const AText: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  Result := ConvertLsp(NormalizeBreaks(AText), mIndex, True);
end;

{ Platzhalter-Modus }

type
  /// <summary>Änderung des Texts: gleicher Anfang und gleiches Ende (unabhängig voneinander), alte Länge,
  /// Längenunterschied.</summary>
  TTextChange = record
    Prefix: Integer;
    Suffix: Integer;
    OldLength: Integer;
    Delta: Integer;
  end;

function HasNumber(const ANumbers: TArray<Integer>; ANumber: Integer): Boolean;
var
  mNumber: Integer;
begin
  for mNumber in ANumbers do
  begin
    if mNumber = ANumber then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Nummern der Platzhalter ohne Endposition, ohne doppelte, aufsteigend.</summary>
function SortedNumbers(const AStops: TArray<TDpccPlaceholderStop>): TArray<Integer>;
var
  mStop: TDpccPlaceholderStop;
  mIndex, mInner, mSwap: Integer;
begin
  Result := nil;
  for mStop in AStops do
  begin
    if (mStop.Number > 0) and not HasNumber(Result, mStop.Number) then
    begin
      Result := Result + [mStop.Number];
    end;
  end;
  // Aufsteigend sortieren (wenige Einträge).
  for mIndex := 1 to High(Result) do
  begin
    for mInner := mIndex downto 1 do
    begin
      if Result[mInner] < Result[mInner - 1] then
      begin
        mSwap := Result[mInner];
        Result[mInner] := Result[mInner - 1];
        Result[mInner - 1] := mSwap;
      end;
    end;
  end;
end;

/// <summary>Gleicher Anfang und gleiches Ende von AOld und ANew, unabhängig voneinander: Bei "aa" → "aaa" ist jede
/// Stelle möglich.</summary>
function ChangeOf(const AOld, ANew: string): TTextChange;
var
  mLimit: Integer;
begin
  Result.OldLength := Length(AOld);
  Result.Delta := Length(ANew) - Length(AOld);
  mLimit := Min(Length(AOld), Length(ANew));
  Result.Prefix := 0;
  while (Result.Prefix < mLimit) and (AOld[Result.Prefix + 1] = ANew[Result.Prefix + 1]) do
  begin
    Inc(Result.Prefix);
  end;
  Result.Suffix := 0;
  while (Result.Suffix < mLimit) and (AOld[Length(AOld) - Result.Suffix] = ANew[Length(ANew) - Result.Suffix]) do
  begin
    Inc(Result.Suffix);
  end;
end;

/// <summary>Die Änderung liegt ganz in AField.</summary>
function Fits(const AField: TDpccPlaceholderField; const AChange: TTextChange): Boolean;
begin
  Result := (AChange.Prefix >= AField.Start) and (AChange.Suffix >= AChange.OldLength - AField.Stop) and
    (AField.Length + AChange.Delta >= 0);
end;

/// <summary>Index des Platzhalters der Nummer ANumber, in dem die Änderung liegt: erst APrimary, dann die übrigen;
/// -1, wenn keiner passt.</summary>
function FittingField(const AFields: TArray<TDpccPlaceholderField>; APrimary, ANumber: Integer;
  const AChange: TTextChange): Integer;
var
  mIndex: Integer;
begin
  if Fits(AFields[APrimary], AChange) then
  begin
    Exit(APrimary);
  end;
  for mIndex := 0 to High(AFields) do
  begin
    if (mIndex <> APrimary) and (AFields[mIndex].Number = ANumber) and Fits(AFields[mIndex], AChange) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TDpccPlaceholderField }

function TDpccPlaceholderField.Stop: Integer;
begin
  Result := Start + Length;
end;

{ TDpccPlaceholderSession }

constructor TDpccPlaceholderSession.Create(const ADocument: string; AOffset: Integer;
  const AExpansion: TDpccPlaceholderExpansion);
var
  mStop: TDpccPlaceholderStop;
  mField: TDpccPlaceholderField;
  mHasEnd: Boolean;
begin
  inherited Create;
  FText := ADocument;
  mHasEnd := False;
  for mStop in AExpansion.Stops do
  begin
    // Die Endposition gilt nur einmal (die erste).
    if (mStop.Number = 0) and mHasEnd then
    begin
      Continue;
    end;
    mHasEnd := mHasEnd or (mStop.Number = 0);
    mField.Number := mStop.Number;
    mField.Start := AOffset + mStop.Start;
    mField.Length := mStop.Length;
    FFields := FFields + [mField];
  end;
  if not mHasEnd then
  begin
    mField.Number := 0;
    mField.Start := AOffset + System.Length(AExpansion.Text);
    mField.Length := 0;
    FFields := FFields + [mField];
  end;
  FOrder := SortedNumbers(AExpansion.Stops) + [0];
  FCurrent := 0;
  FPrimary := FirstOf(FOrder[0]);
end;

procedure TDpccPlaceholderSession.Link(const AField: TDpccPlaceholderField);
begin
  // Hinten anhängen: FirstOf findet zuerst die Platzhalter der Vorlage, dort steht der Cursor.
  if (AField.Number > 0) and (FirstOf(AField.Number) >= 0) then
  begin
    FFields := FFields + [AField];
  end;
end;

function TDpccPlaceholderSession.FirstOf(ANumber: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FFields) do
  begin
    if FFields[mIndex].Number = ANumber then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TDpccPlaceholderSession.CurrentNumber: Integer;
begin
  Result := FOrder[FCurrent];
end;

function TDpccPlaceholderSession.Position: Integer;
begin
  Result := FCurrent + 1;
end;

function TDpccPlaceholderSession.Count: Integer;
begin
  Result := High(FOrder);
end;

function TDpccPlaceholderSession.Current: TDpccPlaceholderField;
begin
  Result := FFields[FPrimary];
end;

function TDpccPlaceholderSession.Fields: TArray<TDpccPlaceholderField>;
var
  mField: TDpccPlaceholderField;
begin
  Result := nil;
  for mField in FFields do
  begin
    if mField.Number > 0 then
    begin
      Result := Result + [mField];
    end;
  end;
end;

function TDpccPlaceholderSession.FinalOffset: Integer;
begin
  Result := FFields[FirstOf(0)].Start;
end;

function TDpccPlaceholderSession.Next: Boolean;
begin
  if FCurrent < High(FOrder) then
  begin
    Inc(FCurrent);
  end;
  FPrimary := FirstOf(FOrder[FCurrent]);
  Result := FOrder[FCurrent] <> 0;
end;

procedure TDpccPlaceholderSession.Previous;
begin
  if (FCurrent > 0) and (FOrder[FCurrent] <> 0) then
  begin
    Dec(FCurrent);
  end;
  FPrimary := FirstOf(FOrder[FCurrent]);
end;

function TDpccPlaceholderSession.FieldText(const AField: TDpccPlaceholderField): string;
begin
  Result := Copy(FText, AField.Start + 1, AField.Length);
end;

class procedure TDpccPlaceholderSession.Locate(const AText: string; AOffset: Integer; out ALine,
  ACharacter: Integer);
var
  mIndex, mLineStart: Integer;
begin
  ALine := 0;
  mLineStart := 0;
  if AOffset > Length(AText) then
  begin
    AOffset := Length(AText);
  end;
  for mIndex := 1 to AOffset do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(ALine);
      mLineStart := mIndex;
    end;
  end;
  ACharacter := AOffset - mLineStart;
end;

procedure TDpccPlaceholderSession.Shift(AFrom, ADelta, AExcept: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FFields) do
  begin
    if (mIndex <> AExcept) and (FFields[mIndex].Start >= AFrom) then
    begin
      Inc(FFields[mIndex].Start, ADelta);
    end;
  end;
end;

function TDpccPlaceholderSession.Update(const ADocument: string): Boolean;
var
  mChange: TTextChange;
  mIndex: Integer;
begin
  if ADocument = FText then
  begin
    Exit(True);
  end;
  Result := False;
  if CurrentNumber = 0 then
  begin
    Exit;
  end;
  mChange := ChangeOf(FText, ADocument);
  mIndex := FittingField(FFields, FPrimary, CurrentNumber, mChange);
  if mIndex < 0 then
  begin
    Exit;
  end;
  FPrimary := mIndex;
  Shift(FFields[FPrimary].Stop, mChange.Delta, FPrimary);
  // Eine leere Endposition direkt am Anfang des Platzhalters bleibt davor.
  Inc(FFields[FPrimary].Length, mChange.Delta);
  FText := ADocument;
  Result := True;
end;

function TDpccPlaceholderSession.MirrorEdits: TDpccPlaceholderEdits;
var
  mIndex, mInner: Integer;
  mValue: string;
  mEdit: TDpccPlaceholderEdit;
begin
  Result := nil;
  if CurrentNumber = 0 then
  begin
    Exit;
  end;
  mValue := FieldText(FFields[FPrimary]);
  for mIndex := 0 to High(FFields) do
  begin
    if (mIndex <> FPrimary) and (FFields[mIndex].Number = CurrentNumber) and (FieldText(FFields[mIndex]) <> mValue) then
    begin
      mEdit.Start := FFields[mIndex].Start;
      mEdit.Stop := FFields[mIndex].Stop;
      mEdit.Text := mValue;
      Result := Result + [mEdit];
    end;
  end;
  // Aufsteigend: Verknüpfte Platzhalter außerhalb der Vorlage (#473) können vor ihr liegen.
  for mIndex := 1 to High(Result) do
  begin
    for mInner := mIndex downto 1 do
    begin
      if Result[mInner].Start < Result[mInner - 1].Start then
      begin
        mEdit := Result[mInner];
        Result[mInner] := Result[mInner - 1];
        Result[mInner - 1] := mEdit;
      end;
    end;
  end;
end;

procedure TDpccPlaceholderSession.Applied(const AEdits: TDpccPlaceholderEdits);
var
  mEdit: TDpccPlaceholderEdit;
  mIndex, mOffset, mDelta: Integer;
begin
  // Rückwärts, damit die Offsets der früheren Änderungen gelten.
  for mIndex := High(AEdits) downto 0 do
  begin
    mEdit := AEdits[mIndex];
    mDelta := Length(mEdit.Text) - (mEdit.Stop - mEdit.Start);
    FText := Copy(FText, 1, mEdit.Start) + mEdit.Text + Copy(FText, mEdit.Stop + 1, MaxInt);
    for mOffset := 0 to High(FFields) do
    begin
      if (FFields[mOffset].Start = mEdit.Start) and (FFields[mOffset].Stop = mEdit.Stop) and
        (FFields[mOffset].Number = CurrentNumber) then
      begin
        FFields[mOffset].Length := Length(mEdit.Text);
      end
      else if FFields[mOffset].Start >= mEdit.Stop then
      begin
        Inc(FFields[mOffset].Start, mDelta);
      end;
    end;
  end;
end;

end.
