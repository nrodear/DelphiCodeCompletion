unit dpcc.Core.InlayHints.Store;

// Inlay-Hints im Editor (#401, ARG-040), ohne VCL und Open Tools API:
// Parameternamen vor Literal-Argumenten (Zahl, String, Zeichen, True/False,
// nil) aus textDocument/inlayHint. Zwischenspeicher je Datei und Textstand:
// Ändert sich der Text, verfällt alles; geholt wird nur, was in den sichtbaren
// Zeilen (mit Rand) noch fehlt. Der RAD-Studio-Editor kennt keinen
// eingeschobenen Text; die Hinweise erscheinen deshalb in Zeilenreihenfolge
// hinter dem Zeilenende und verschieben weder Text noch Cursor. Weil dort der
// Bezug zum Argument fehlt, steht der Wert dabei („Name = 'LOCALAPPDATA'“), und
// es bleiben nur Hinweise, die etwas sagen: nicht beim einzigen Argument eines
// Aufrufs, nicht bei Namen wie S1, A oder X und nicht, wenn das Argument den
// Namen schon enthält.
// Blockende-Beschriftungen (#620): Die Endmarken des Servers ("// TKunde.Speichern"
// hinter dem end langer Blöcke, inlayHints.endMarkers) liegen getrennt von den
// Parameternamen und haben eine eigene Einstellung (BlockEndLabels). Keine Marke,
// wenn hinter dem end schon ein Kommentar steht; lange Texte enden mit „…“.
// Typmarken (#453): der abgeleitete Typ von var X := …, const X = … und for var X in … (kind 1) liegt
// ebenfalls getrennt, mit eigener Einstellung (InlayTypeHints), und erscheint als „: TStringList“.
// Include-Symbole (#860): hinter {$I datei.inc} die dort gesetzten Symbole, die die Unit prüft
// (data.includeDefines), mit eigener Einstellung (InlayDefineHints); die Beschriftung baut die
// Oberfläche in der Sprache der IDE („definiert COMPLIB_VCL“).
// Steuerzeichen (#862): hinter ^C im Wert einer Konstanten der Code „#3“ (data.controlChar), mit eigener
// Einstellung (InlayCharHints).
// Methoden ohne Self (#686): am Ende des Kopfs die Marke „braucht kein Self“ (data.methodWithoutSelf); ob sie
// kommt, entscheidet der Server (refactoring.methodKindMarker), die Beschriftung baut die Oberfläche. Die Stelle
// der Marke ist das Ziel des Klicks, der dort die Code-Aktionen öffnet.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TDpccInlayHint = record
    /// <summary>0-basiert.</summary>
    Line: Integer;
    /// <summary>0-basiert, UTF-16-Index in der Zeile.</summary>
    Character: Integer;
    /// <summary>Parametername ohne ":"; bei einer Endmarke deren Text ohne "//".</summary>
    Name: string;
    /// <summary>Endmarke hinter einem end (#620) statt Parametername.</summary>
    EndLabel: Boolean;
    /// <summary>Typmarke (#453): Name ist der abgeleitete Typ ohne ":".</summary>
    TypeHint: Boolean;
    /// <summary>Include-Symbole (#860): Name sind die Symbole durch ", " getrennt.</summary>
    DefineHint: Boolean;
    /// <summary>Steuerzeichen (#862): Name ist der Code wie „#3“.</summary>
    CharHint: Boolean;
    /// <summary>Methode ohne Self (#686): Marke am Ende des Kopfs.</summary>
    MethodHint: Boolean;
    /// <summary>Endmarke: Anfang des Blocks (0-basiert), zu dem ein Klick springt; nur mit HasBlock.</summary>
    BlockLine: Integer;
    BlockCharacter: Integer;
    HasBlock: Boolean;
  end;

  TDpccInlayHintStore = class
  public const
    /// <summary>Zusätzlich geholte Zeilen ober- und unterhalb des sichtbaren Bereichs.</summary>
    cMargin = 20;
    /// <summary>Längster gezeigter Wert, danach „…“.</summary>
    cMaxValueLength = 24;
    /// <summary>Längster Text einer Blockende-Beschriftung, danach „…“.</summary>
    cMaxEndLabelLength = 40;
    /// <summary>Längster gezeigter Typ einer Typmarke (#453), danach „…“.</summary>
    cMaxTypeLength = 40;
  private type
    TEntry = class
      FText: string;
      FLines: TArray<string>;
      FCovered: TArray<Boolean>;
      FHints: TArray<TDpccInlayHint>;
      FEnds: TArray<TDpccInlayHint>;
      FTypes: TArray<TDpccInlayHint>;
      FDefines: TArray<TDpccInlayHint>;
      FChars: TArray<TDpccInlayHint>;
      FMethods: TArray<TDpccInlayHint>;
      procedure PutEnd(const AHint: TDpccInlayHint);
      /// <summary>Typmarke, Include-Symbole, Steuerzeichen oder Methode ohne Self.</summary>
      procedure PutMarker(const AHint: TDpccInlayHint);
      procedure PutParameter(const AHint: TDpccInlayHint);
      /// <summary>AHint übernehmen, wenn er in AFrom..ATo liegt und passt.</summary>
      procedure PutHint(const AHint: TDpccInlayHint; AFrom, ATo: Integer);
      procedure Sort;
    end;
  private
    FEntries: TObjectDictionary<string, TEntry>;
    function Find(const AFileName: string): TEntry;
  public
    constructor Create;
    destructor Destroy; override;
    class function Key(const AFileName: string): string; static;
    /// <summary>Zeilen wie der Server sie zählt: CR, LF und CRLF trennen.</summary>
    class function SplitLines(const AText: string): TArray<string>; static;
    /// <summary>Beginnt an ACharacter (nach Leerraum) ein Literal: Zahl, String, Zeichen, True, False, nil?</summary>
    class function IsLiteralAt(const ALine: string; ACharacter: Integer): Boolean; static;
    /// <summary>Text des Arguments ab ACharacter bis zum nächsten Komma bzw. zur schließenden Klammer
    /// derselben Ebene, ohne Leerraum.</summary>
    class function ArgumentAt(const ALine: string; ACharacter: Integer): string; static;
    /// <summary>Ist das Argument ab ACharacter das einzige des Aufrufs: F(Argument)?</summary>
    class function IsSoleArgument(const ALine: string; ACharacter: Integer): Boolean; static;
    /// <summary>Sagt der Name nichts: ein oder zwei Zeichen oder Buchstabe mit Ziffern (S1, A, X2)?</summary>
    class function IsVagueName(const AName: string): Boolean; static;
    /// <summary>„Name = Wert“, lange Werte gekürzt.</summary>
    class function LabelOf(const AName, AValue: string): string; static;
    /// <summary>„// Text“ einer Blockende-Beschriftung, lange Texte gekürzt.</summary>
    class function EndLabelOf(const AText: string): string; static;
    /// <summary>Steht ab ACharacter (0-basiert) noch ein Kommentar in der Zeile?</summary>
    class function HasCommentAfter(const ALine: string; ACharacter: Integer): Boolean; static;
    /// <summary>Aktueller Text einer Datei; anderer Text verwirft ihre Hinweise.</summary>
    procedure SetText(const AFileName, AText: string);
    /// <summary>Fehlende Zeilen um AFirst..ALast (mit Rand); False, wenn alles da ist.</summary>
    function Missing(const AFileName: string; AFirst, ALast: Integer; out AFrom, ATo: Integer): Boolean;
    /// <summary>Antwort des Servers für AFrom..ATo zu AText; verworfen, wenn sich der Text inzwischen
    /// geändert hat. Nur Parameternamen vor Literalen bleiben.</summary>
    procedure Put(const AFileName, AText: string; AFrom, ATo: Integer; const AHints: TArray<TDpccInlayHint>);
    /// <summary>Beschriftungen („Name = Wert“) der Zeile in Reihenfolge.</summary>
    function OnLine(const AFileName: string; ALine: Integer): TArray<string>;
    /// <summary>Typmarken („: TStringList“, #453) der Zeile in Reihenfolge.</summary>
    function TypesOnLine(const AFileName: string; ALine: Integer): TArray<string>;
    /// <summary>Include-Symbole hinter {$I} in der Zeile (#860), je Direktive die Symbole durch ", " getrennt.
    /// </summary>
    function DefinesOnLine(const AFileName: string; ALine: Integer): TArray<string>;
    /// <summary>Codes der Steuerzeichen in der Zeile („#3“, #862) in Reihenfolge.</summary>
    function CharsOnLine(const AFileName: string; ALine: Integer): TArray<string>;
    /// <summary>Steht in der Zeile die Marke einer Methode ohne Self (#686)? ACharacter: ihre Stelle (Ende des
    /// Kopfs, 0-basiert), für den Klick auf die Marke.</summary>
    function MethodOnLine(const AFileName: string; ALine: Integer; out ACharacter: Integer): Boolean;
    /// <summary>„: Typ“, lange Typen gekürzt.</summary>
    class function TypeLabelOf(const ATypeName: string): string; static;
    /// <summary>Blockende-Beschriftung der Zeile: AText ist der Text der Marke ohne "//" (Anker), ALabel die
    /// gezeigte Beschriftung („// TKunde.Speichern“); False ohne.</summary>
    function EndLabelOn(const AFileName: string; ALine: Integer; out AText, ALabel: string): Boolean; overload;
    /// <summary>Wie oben, dazu die ganze Marke mit Blockanfang (#620).</summary>
    function EndLabelOn(const AFileName: string; ALine: Integer; out AText, ALabel: string;
      out AHint: TDpccInlayHint): Boolean; overload;
    /// <summary>Zeile im Speicher, zum Vergleich mit dem Editor.</summary>
    function LineText(const AFileName: string; ALine: Integer; out AText: string): Boolean;
    procedure Clear;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.Generics.Defaults,
  dpcc.Text.Lines,
  dpcc.Text.Chars;

{ TDpccInlayHintStore }

constructor TDpccInlayHintStore.Create;
begin
  inherited Create;
  FEntries := TObjectDictionary<string, TEntry>.Create([doOwnsValues]);
end;

destructor TDpccInlayHintStore.Destroy;
begin
  FEntries.Free;
  inherited;
end;

class function TDpccInlayHintStore.Key(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

class function TDpccInlayHintStore.SplitLines(const AText: string): TArray<string>;
begin
  Result := TTextLines.SplitLines(AText);
end;

/// <summary>Steht ab AIndex (1-basiert) True, False oder nil?</summary>
function IsLiteralWord(const ALine: string; AIndex: Integer): Boolean;
var
  mStop: Integer;
  mWord: string;
begin
  mStop := AIndex;
  while (mStop <= Length(ALine)) and TTextChars.IsIdentChar(ALine[mStop]) do
  begin
    Inc(mStop);
  end;
  mWord := LowerCase(Copy(ALine, AIndex, mStop - AIndex));
  Result := (mWord = 'true') or (mWord = 'false') or (mWord = 'nil');
end;
class function TDpccInlayHintStore.IsLiteralAt(const ALine: string; ACharacter: Integer): Boolean;
var
  mIndex: Integer;
  mNext: Char;
begin
  Result := False;
  mIndex := ACharacter + 1;
  while (mIndex <= Length(ALine)) and CharInSet(ALine[mIndex], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  if mIndex > Length(ALine) then
  begin
    Exit;
  end;
  mNext := #0;
  if mIndex < Length(ALine) then
  begin
    mNext := ALine[mIndex + 1];
  end;
  case ALine[mIndex] of
    '''', '0'..'9':
      Result := True;
    '#', '$', '%':
      Result := CharInSet(mNext, ['0'..'9', 'A'..'F', 'a'..'f', '$']);
    '-', '+':
      Result := CharInSet(mNext, ['0'..'9', '$', '%']);
  else
    Result := IsLiteralWord(ALine, mIndex);
  end;
end;

function TDpccInlayHintStore.Find(const AFileName: string): TEntry;
begin
  if not FEntries.TryGetValue(Key(AFileName), Result) then
  begin
    Result := nil;
  end;
end;

procedure TDpccInlayHintStore.SetText(const AFileName, AText: string);
var
  mEntry: TEntry;
begin
  mEntry := Find(AFileName);
  if (mEntry <> nil) and (mEntry.FText = AText) then
  begin
    Exit;
  end;
  if mEntry = nil then
  begin
    mEntry := TEntry.Create;
    FEntries.Add(Key(AFileName), mEntry);
  end;
  mEntry.FText := AText;
  mEntry.FLines := SplitLines(AText);
  mEntry.FCovered := nil;
  SetLength(mEntry.FCovered, Length(mEntry.FLines));
  mEntry.FHints := nil;
  mEntry.FEnds := nil;
  mEntry.FTypes := nil;
  mEntry.FDefines := nil;
  mEntry.FChars := nil;
  mEntry.FMethods := nil;
end;

function TDpccInlayHintStore.Missing(const AFileName: string; AFirst, ALast: Integer; out AFrom,
  ATo: Integer): Boolean;
var
  mEntry: TEntry;
  mLine, mFirst, mLast: Integer;
begin
  AFrom := -1;
  ATo := -1;
  mEntry := Find(AFileName);
  if (mEntry = nil) or (Length(mEntry.FLines) = 0) then
  begin
    Exit(False);
  end;
  mFirst := AFirst - cMargin;
  if mFirst < 0 then
  begin
    mFirst := 0;
  end;
  mLast := ALast + cMargin;
  if mLast > High(mEntry.FLines) then
  begin
    mLast := High(mEntry.FLines);
  end;
  for mLine := mFirst to mLast do
  begin
    if not mEntry.FCovered[mLine] then
    begin
      if AFrom < 0 then
      begin
        AFrom := mLine;
      end;
      ATo := mLine;
    end;
  end;
  Result := AFrom >= 0;
end;

/// <summary>Fügt AHint an, wenn an seiner Stelle noch keiner steht (überlappende Abrufe).</summary>
procedure AddOnce(var AList: TArray<TDpccInlayHint>; const AHint: TDpccInlayHint);
var
  mKnown: TDpccInlayHint;
begin
  for mKnown in AList do
  begin
    if (mKnown.Line = AHint.Line) and (mKnown.Character = AHint.Character) then
    begin
      Exit;
    end;
  end;
  AList := AList + [AHint];
end;

function HintOrder(const ALeft, ARight: TDpccInlayHint): Integer;
begin
  Result := ALeft.Line - ARight.Line;
  if Result = 0 then
  begin
    Result := ALeft.Character - ARight.Character;
  end;
end;

{ TDpccInlayHintStore.TEntry }

procedure TDpccInlayHintStore.TEntry.PutEnd(const AHint: TDpccInlayHint);
var
  mKnown: TDpccInlayHint;
  mDuplicate: Boolean;
begin
  // Endmarke (#620): nur ohne Kommentar hinter dem end, jede Zeile einmal.
  if TDpccInlayHintStore.HasCommentAfter(FLines[AHint.Line], AHint.Character) then
  begin
    Exit;
  end;
  mDuplicate := False;
  for mKnown in FEnds do
  begin
    mDuplicate := mDuplicate or (mKnown.Line = AHint.Line);
  end;
  if not mDuplicate then
  begin
    FEnds := FEnds + [AHint];
  end;
end;

procedure TDpccInlayHintStore.TEntry.PutMarker(const AHint: TDpccInlayHint);
begin
  // Typmarke (#453), Include-Symbole (#860), Steuerzeichen (#862) und Methoden ohne Self (#686): jede Stelle
  // einmal.
  if AHint.TypeHint then
  begin
    AddOnce(FTypes, AHint);
  end
  else if AHint.DefineHint then
  begin
    AddOnce(FDefines, AHint);
  end
  else if AHint.MethodHint then
  begin
    AddOnce(FMethods, AHint);
  end
  else
  begin
    AddOnce(FChars, AHint);
  end;
end;

procedure TDpccInlayHintStore.TEntry.PutParameter(const AHint: TDpccInlayHint);
var
  mLine: string;
begin
  mLine := FLines[AHint.Line];
  // Nur Parameternamen vor Literalen, die am Zeilenende noch etwas sagen. Überlappende Abrufe liefern
  // dieselben Hinweise noch einmal.
  if TDpccInlayHintStore.IsLiteralAt(mLine, AHint.Character) and
    not TDpccInlayHintStore.IsVagueName(AHint.Name) and
    not TDpccInlayHintStore.IsSoleArgument(mLine, AHint.Character) and
    not ContainsText(TDpccInlayHintStore.ArgumentAt(mLine, AHint.Character), AHint.Name) then
  begin
    AddOnce(FHints, AHint);
  end;
end;

procedure TDpccInlayHintStore.TEntry.PutHint(const AHint: TDpccInlayHint; AFrom, ATo: Integer);
begin
  if (AHint.Line < AFrom) or (AHint.Line > ATo) or (AHint.Line > High(FLines)) or (AHint.Name = '') then
  begin
    Exit;
  end;
  if AHint.EndLabel then
  begin
    PutEnd(AHint);
  end
  else if AHint.TypeHint or AHint.DefineHint or AHint.CharHint or AHint.MethodHint then
  begin
    PutMarker(AHint);
  end
  else
  begin
    PutParameter(AHint);
  end;
end;

procedure TDpccInlayHintStore.TEntry.Sort;
var
  mOrder: IComparer<TDpccInlayHint>;
begin
  mOrder := TComparer<TDpccInlayHint>.Construct(HintOrder);
  TArray.Sort<TDpccInlayHint>(FHints, mOrder);
  TArray.Sort<TDpccInlayHint>(FTypes, mOrder);
  TArray.Sort<TDpccInlayHint>(FDefines, mOrder);
  TArray.Sort<TDpccInlayHint>(FChars, mOrder);
end;
procedure TDpccInlayHintStore.Put(const AFileName, AText: string; AFrom, ATo: Integer;
  const AHints: TArray<TDpccInlayHint>);
var
  mEntry: TEntry;
  mLine: Integer;
  mHint: TDpccInlayHint;
begin
  mEntry := Find(AFileName);
  if (mEntry = nil) or (mEntry.FText <> AText) then
  begin
    Exit;
  end;
  for mLine := AFrom to ATo do
  begin
    if (mLine >= 0) and (mLine <= High(mEntry.FCovered)) then
    begin
      mEntry.FCovered[mLine] := True;
    end;
  end;
  for mHint in AHints do
  begin
    mEntry.PutHint(mHint, AFrom, ATo);
  end;
  mEntry.Sort;
end;

/// <summary>Namen der Hinweise aus AHints in ALine, in Reihenfolge.</summary>
function NamesOn(const AHints: TArray<TDpccInlayHint>; ALine: Integer): TArray<string>;
var
  mHint: TDpccInlayHint;
begin
  Result := nil;
  for mHint in AHints do
  begin
    if mHint.Line = ALine then
    begin
      Result := Result + [mHint.Name];
    end;
  end;
end;

function TDpccInlayHintStore.DefinesOnLine(const AFileName: string; ALine: Integer): TArray<string>;
var
  mEntry: TEntry;
begin
  Result := nil;
  mEntry := Find(AFileName);
  if mEntry <> nil then
  begin
    Result := NamesOn(mEntry.FDefines, ALine);
  end;
end;

function TDpccInlayHintStore.CharsOnLine(const AFileName: string; ALine: Integer): TArray<string>;
var
  mEntry: TEntry;
begin
  Result := nil;
  mEntry := Find(AFileName);
  if mEntry <> nil then
  begin
    Result := NamesOn(mEntry.FChars, ALine);
  end;
end;

function TDpccInlayHintStore.MethodOnLine(const AFileName: string; ALine: Integer; out ACharacter: Integer): Boolean;
var
  mEntry: TEntry;
  mHint: TDpccInlayHint;
begin
  Result := False;
  ACharacter := 0;
  mEntry := Find(AFileName);
  if mEntry = nil then
  begin
    Exit;
  end;
  for mHint in mEntry.FMethods do
  begin
    if mHint.Line = ALine then
    begin
      ACharacter := mHint.Character;
      Exit(True);
    end;
  end;
end;

function TDpccInlayHintStore.OnLine(const AFileName: string; ALine: Integer): TArray<string>;
var
  mEntry: TEntry;
  mHint: TDpccInlayHint;
begin
  Result := nil;
  mEntry := Find(AFileName);
  if mEntry = nil then
  begin
    Exit;
  end;
  for mHint in mEntry.FHints do
  begin
    if mHint.Line = ALine then
    begin
      Result := Result + [LabelOf(mHint.Name, ArgumentAt(mEntry.FLines[ALine], mHint.Character))];
    end;
  end;
end;

function TDpccInlayHintStore.TypesOnLine(const AFileName: string; ALine: Integer): TArray<string>;
var
  mEntry: TEntry;
  mHint: TDpccInlayHint;
begin
  Result := nil;
  mEntry := Find(AFileName);
  if mEntry = nil then
  begin
    Exit;
  end;
  // In Spaltenreihenfolge, wie die Variablen in der Zeile stehen.
  for mHint in mEntry.FTypes do
  begin
    if mHint.Line = ALine then
    begin
      Result := Result + [TypeLabelOf(mHint.Name)];
    end;
  end;
end;

class function TDpccInlayHintStore.TypeLabelOf(const ATypeName: string): string;
begin
  Result := ': ' + ATypeName;
  if Length(Result) > cMaxTypeLength + 2 then
  begin
    Result := Copy(Result, 1, cMaxTypeLength + 1) + '…';
  end;
end;

function TDpccInlayHintStore.EndLabelOn(const AFileName: string; ALine: Integer; out AText, ALabel: string): Boolean;
var
  mHint: TDpccInlayHint;
begin
  Result := EndLabelOn(AFileName, ALine, AText, ALabel, mHint);
end;

function TDpccInlayHintStore.EndLabelOn(const AFileName: string; ALine: Integer; out AText, ALabel: string;
  out AHint: TDpccInlayHint): Boolean;
var
  mEntry: TEntry;
  mHint: TDpccInlayHint;
begin
  AText := '';
  ALabel := '';
  AHint := Default(TDpccInlayHint);
  mEntry := Find(AFileName);
  if mEntry = nil then
  begin
    Exit(False);
  end;
  for mHint in mEntry.FEnds do
  begin
    if mHint.Line = ALine then
    begin
      AText := mHint.Name;
      ALabel := EndLabelOf(mHint.Name);
      AHint := mHint;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDpccInlayHintStore.EndLabelOf(const AText: string): string;
begin
  if Length(AText) > cMaxEndLabelLength then
  begin
    Result := '// ' + TrimRight(Copy(AText, 1, cMaxEndLabelLength - 1)) + '…';
  end
  else
  begin
    Result := '// ' + AText;
  end;
end;

class function TDpccInlayHintStore.HasCommentAfter(const ALine: string; ACharacter: Integer): Boolean;
var
  mIndex: Integer;
  mInString: Boolean;
begin
  mInString := False;
  mIndex := Max(0, ACharacter) + 1;
  while mIndex <= Length(ALine) do
  begin
    if mInString then
    begin
      if ALine[mIndex] = '''' then
      begin
        mInString := False;
      end;
    end
    else if ALine[mIndex] = '''' then
    begin
      mInString := True;
    end
    else if (ALine[mIndex] = '{') or (Copy(ALine, mIndex, 2) = '//') or (Copy(ALine, mIndex, 2) = '(*') then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
  Result := False;
end;

class function TDpccInlayHintStore.ArgumentAt(const ALine: string; ACharacter: Integer): string;
var
  mIndex, mDepth: Integer;
  mInString: Boolean;
begin
  mDepth := 0;
  mInString := False;
  mIndex := ACharacter + 1;
  while mIndex <= Length(ALine) do
  begin
    if mInString then
    begin
      if ALine[mIndex] = '''' then
      begin
        mInString := False;
      end;
    end
    else if ALine[mIndex] = '''' then
    begin
      mInString := True;
    end
    else if CharInSet(ALine[mIndex], ['(', '[']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(ALine[mIndex], [')', ']']) then
    begin
      if mDepth = 0 then
      begin
        Break;
      end;
      Dec(mDepth);
    end
    else if (ALine[mIndex] = ',') and (mDepth = 0) then
    begin
      Break;
    end;
    Inc(mIndex);
  end;
  Result := Trim(Copy(ALine, ACharacter + 1, mIndex - ACharacter - 1));
end;

class function TDpccInlayHintStore.IsSoleArgument(const ALine: string; ACharacter: Integer): Boolean;
var
  mBefore, mAfter: Integer;
begin
  mBefore := ACharacter;
  while (mBefore >= 1) and CharInSet(ALine[mBefore], [' ', #9]) do
  begin
    Dec(mBefore);
  end;
  mAfter := ACharacter + Length(ArgumentAt(ALine, ACharacter)) + 1;
  while (mAfter <= Length(ALine)) and CharInSet(ALine[mAfter], [' ', #9]) do
  begin
    Inc(mAfter);
  end;
  Result := (mBefore >= 1) and (ALine[mBefore] = '(') and (mAfter <= Length(ALine)) and (ALine[mAfter] = ')');
end;

class function TDpccInlayHintStore.IsVagueName(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(AName) <= 2;
  if Result or not CharInSet(AName[1], ['A'..'Z', 'a'..'z']) then
  begin
    Exit;
  end;
  for mIndex := 2 to Length(AName) do
  begin
    if not CharInSet(AName[mIndex], ['0'..'9']) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

class function TDpccInlayHintStore.LabelOf(const AName, AValue: string): string;
begin
  if Length(AValue) > cMaxValueLength then
  begin
    Result := AName + ' = ' + Copy(AValue, 1, cMaxValueLength - 1) + '…';
  end
  else
  begin
    Result := AName + ' = ' + AValue;
  end;
end;

function TDpccInlayHintStore.LineText(const AFileName: string; ALine: Integer; out AText: string): Boolean;
var
  mEntry: TEntry;
begin
  AText := '';
  mEntry := Find(AFileName);
  Result := (mEntry <> nil) and (ALine >= 0) and (ALine <= High(mEntry.FLines));
  if Result then
  begin
    AText := mEntry.FLines[ALine];
  end;
end;

procedure TDpccInlayHintStore.Clear;
begin
  FEntries.Clear;
end;

end.
