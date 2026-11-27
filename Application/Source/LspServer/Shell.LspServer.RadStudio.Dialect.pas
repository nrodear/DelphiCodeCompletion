unit Shell.LspServer.RadStudio.Dialect;

// Host-Rolle Shell, nur in dpcc.LspServer.exe: Übersetzer zwischen dem Server und dem LSP-Dialekt der RAD-Studio-IDE
// als Transport um den eigentlichen Transport (stdin/stdout). Er liest initialize mit; meldet sich der Client als
// "RAD Studio" (clientInfo.name), gilt bis zum Ende der Verbindung der Dialekt, für alle anderen Clients bleibt alles
// Standard-LSP (nur documentSymbolProvider kommt in den Capabilities dazu).
// Dialekt (Capabilities gemessen am 26.11.2026 an DelphiLSP in Delphi 12 und 13; die Form der Antworten gemessen am
// 27.11.2026 über Stellvertreter in der IDE, Delphi 12 und 13 antworten gleich):
// - initialize: Capabilities wie DelphiLSP (textDocumentSync 1 = ganzer Text, completion mit resolve und den
//   Auslösezeichen . ( < [, signatureHelp mit ( , <), aber nur, was der Server kann: definition, declaration,
//   typeDefinition, implementation (dasselbe Ziel wie definition), documentSymbol, hover. Keine Diagnosen.
// - textDocument/completion: {"isIncomplete", "kibitzkind", "items": [{label, kind, detail, DCC_Flags, sortText}]}.
//   kibitzkind 2 nach "X.", 15 in der uses-Klausel, sonst 7; bestimmt aus dem Text von didOpen/didChange an der
//   Position der Anfrage. sortText ist die laufende Nummer hexadezimal in Großbuchstaben, so breit wie die Nummer des
//   letzten Eintrags (48 Einträge "00".."2F"); Schlüsselwörter stehen hinten mit "k000". Überladungen stehen einzeln,
//   Deklarationen aus nicht geltenden Zweigen fehlen. kind, detail und DCC_Flags je Art wie DelphiLSP (KindOf,
//   DetailWith, DccFlagsOf): detail hinter dem Namen ": Integer;", "(A: Integer; B: Integer): Integer;" (Gruppen
//   aufgelöst), " = 42;", " = TColorKind(1);", ": class(TObject);", lokale Variablen ": TProbe;". DCC_Flags-Bits:
//   0x1 Wert, 0x2 Typ, 0x4 Routine, 0x10 Mitglied, 0x20 Verfahren bzw. Prozedurtyp, 0x40 strukturierter Typ, 0x80
//   Klassen-Typ, 0x100 private, 0x200 virtual, 0x400 protected, 0x4000 Property mit write, 0x8000 Property nur
//   lesbar, 0x10000 Ereignis, 0x20000 Konstruktor, 0x40000 Destruktor, 0x200000 Array-Property, 0x800000
//   Klassenmethode bzw. globale Routine, 0x4000000 overload, 0x8000000 Interface, 0x10000000 deprecated. Einträge,
//   die zusätzliche Änderungen brauchen (uses ergänzen, Vorlagen, Befehle), fehlen: Die IDE übernähme nur den Namen.
// - completionItem/resolve: kind und insertTextFormat kommen als Zeichenketten; data fehlt. Der Übersetzer setzt den
//   Eintrag des Servers wieder ein (über sortText und label der Liste) und antwortet mit dem Eintrag, wie er in der
//   Liste stand, samt DCC_Flags und ohne documentation.
// - textDocument/signatureHelp: label wie die Kopfzeile des Hovers ohne ";" und Direktiven, Parameter einzeln mit Typ
//   ("A: Integer"). documentation der Signatur {"kind": "html"} im Gerüst des Hovers mit leerem Titel und leerer
//   Kopfzeile, der Wert DOPPELT maskiert (wörtlich \r\n und \"); Parameter {"kind": "xml", "value": Doku oder ""}.
//   Ohne documentation in Signatur und Parametern zeigt die IDE die Hilfe nicht.
// - textDocument/hover: {"contents": HTML als ein String}, ohne range. Gerüst mit Kopfzeile ("function
//   TProbe.Twice(const A: Integer): Integer", "type TProbe = class(TObject)", "var P: TProbe" …), Verweis
//   helpinsight:/filelink:<Pfad>?<Zeile>,1 und den Blöcken Summary, Parameters, Returns, Remarks; gebaut aus dem
//   dpcc-Teil der Antwort des Servers (HoverHtml, HoverCaption).
// - textDocument/definition, declaration, typeDefinition, implementation: ein Location-Objekt (kein Array), die URI
//   in der Schreibweise, in der die IDE die Datei geöffnet hat.
// - Benachrichtigungen und Anfragen des Servers an den Client (window/logMessage, $/progress, dpcc/…) gehen nicht an
//   die IDE; sie kennt sie nicht.
// Threadsicher: WriteMessage kommt aus Worker-Threads, ReadMessage nur aus dem Lese-Thread der Verbindung.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.JSON,
  System.Generics.Collections,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.Index.Contract;

type
  /// <summary>Symbole der Unit, die in AFileName steht (wie TUnitIndex.Symbols); False, wenn der Index die Datei
  /// nicht kennt. Das Feld wird nur gelesen.</summary>
  TRadUnitSymbols = reference to function(const AFileName: string; out ASymbols: TArray<TIndexSymbol>): Boolean;
  /// <summary>Deklaration des Typs ATypeName auf Unit-Ebene (irgendeine Unit des Index); False ohne Treffer.
  /// </summary>
  TRadTypeLookup = reference to function(const ATypeName: string; out ASymbol: TIndexSymbol): Boolean;
  /// <summary>Nach initialize: Name des Clients und processId (0 ohne).</summary>
  TRadInitializeEvent = reference to procedure(const AClientName: string; AProcessId: Cardinal);

  /// <summary>Routinenkopf, zerlegt aus "function Twice(const A, B: Integer): Integer; overload;".</summary>
  TRadRoutineHead = record
    /// <summary>Schlüsselwörter vor dem Namen: "function", "class procedure", "constructor" …</summary>
    Head: string;
    /// <summary>Name wie geschrieben (auch "TFoo.Bar" oder generisch).</summary>
    Name: string;
    /// <summary>Je Parameter einer mit Typ, Gruppen aufgelöst: "const A: Integer", "const B: Integer".</summary>
    Parameters: TArray<string>;
    /// <summary>Ergebnistyp; '' bei Prozeduren.</summary>
    ResultType: string;
  end;

  /// <summary>Offene Anfrage der IDE.</summary>
  TRadPendingRequest = record
    Method: string;
    /// <summary>textDocument/completion: kibitzkind aus dem Text an der Position der Anfrage.</summary>
    Kibitz: Integer;
    /// <summary>completionItem/resolve: Schlüssel des Eintrags der letzten Liste; '' ohne.</summary>
    ResolveKey: string;
    /// <summary>completionItem/resolve: der Eintrag, wie die IDE ihn schickte (JSON), für den Rückfall, wenn er nicht
    /// mehr aus der letzten Liste stammt; '' ohne.</summary>
    ResolveEcho: string;
  end;

  TRadStudioDialect = class(TInterfacedObject, IJsonRpcTransport)
  public const
    cClientName = 'RAD Studio';
    /// <summary>kibitzkind: Mitglieder nach "X.", Bezeichner ohne Punkt, Units in der uses-Klausel.</summary>
    cKibitzMember = 2;
    cKibitzScope = 7;
    cKibitzUses = 15;
  private
    FInner: IJsonRpcTransport;
    FLock: TCriticalSection;
    FActive: Boolean;
    FDecided: Boolean;
    /// <summary>Offene Anfragen des Clients (id als JSON-Text).</summary>
    FPending: TDictionary<string, TRadPendingRequest>;
    /// <summary>Einträge der letzten Vervollständigung je sortText + #1 + label der IDE: der Eintrag des Servers
    /// (für resolve) und der Eintrag, wie ihn die IDE bekam.</summary>
    FLastItems: TObjectDictionary<string, TJSONObject>;
    FLastRadItems: TObjectDictionary<string, TJSONObject>;
    /// <summary>Dokumente der IDE je TDocumentUris.Key: URI in der Schreibweise von didOpen und der ganze Text nach
    /// didOpen bzw. didChange.</summary>
    FUris: TDictionary<string, string>;
    FTexts: TDictionary<string, string>;
    FUnitSymbols: TRadUnitSymbols;
    FTypeLookup: TRadTypeLookup;
    FOnInitialize: TRadInitializeEvent;
    FDropped: Integer;
    function GetActive: Boolean;
    procedure NoteInitialize(AMessage: TJSONObject);
    procedure NoteDocument(const AMethod: string; AMessage: TJSONObject);
    function KibitzOf(AMessage: TJSONObject): Integer;
    /// <summary>Setzt den Eintrag des Servers als params ein; liefert seinen Schlüssel ('' ohne).</summary>
    function FixResolveParams(AMessage: TJSONObject): string;
    function TakePending(const AId: TJSONValue; out APending: TRadPendingRequest): Boolean;
    function Transform(const APending: TRadPendingRequest; AResult: TJSONValue): TJSONValue;
    function CompletionAnswer(AResult: TJSONValue; AKibitz: Integer): TJSONValue;
    function ResolveAnswer(AResult: TJSONValue; const AKey, AEcho: string): TJSONValue;
    function LocationAnswer(AResult: TJSONValue): TJSONValue;
    /// <summary>AUri in der Schreibweise, in der die IDE die Datei geöffnet hat; sonst unverändert.</summary>
    function IdeUri(const AUri: string): string;
    procedure RememberItems(AServerItems, ARadItems: TList<TJSONObject>);
  public
    constructor Create(const AInner: IJsonRpcTransport);
    destructor Destroy; override;
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
    /// <summary>Capabilities für die IDE aus denen des Servers (nur, was er kann); der Aufrufer übernimmt sie.
    /// </summary>
    class function RadCapabilities(const AServer: TJSONObject): TJSONObject; static;
    /// <summary>Hover im Format der IDE (HTML aus dem dpcc-Teil) aus der Antwort des Servers; der Aufrufer übernimmt
    /// es.</summary>
    class function HoverAnswer(AResult: TJSONValue): TJSONValue; static;
    /// <summary>Parameterhilfe im Format der IDE; der Aufrufer übernimmt sie.</summary>
    class function SignatureAnswer(AResult: TJSONValue): TJSONValue; static;
    /// <summary>Gerüst des Hovers wie DelphiLSP (CRLF, Tabs vor dem Verweis); ohne AFileName bzw. mit ALine &lt; 0
    /// ohne Verweis. ALine 0-basiert, ABody fertiges HTML.</summary>
    class function HoverHtml(const ACaption, AFileName: string; ALine: Integer; const ABody: string): string; static;
    /// <summary>Kopfzeile des Hovers aus den Teilen des dpcc-Objekts (declaration, kind, container, unit, file,
    /// value).</summary>
    class function HoverCaption(const ADeclaration, AKind, AContainer, AUnitName, AFileName,
      AValue: string): string; static;
    /// <summary>Zerlegt einen Routinenkopf; False, wenn AText keiner ist.</summary>
    class function ParseRoutine(const AText: string; out AHead: TRadRoutineHead): Boolean; static;
    /// <summary>Parameterliste (Text zwischen den Klammern) einzeln mit Typ: "A, B: Integer" →
    /// ["A: Integer", "B: Integer"], Modifizierer je Name.</summary>
    class function ResolveParameters(const AText: string): TArray<string>; static;
    /// <summary>"function Q.Name(A: Integer; B: Integer): Integer" mit AQualifier ("TProbe." oder '').</summary>
    class function RoutineCaption(const AHead: TRadRoutineHead; const AQualifier: string): string; static;
    class function HtmlEscape(const AText: string): string; static;
    /// <summary>AText als Inhalt eines JSON-Strings maskiert (\\, \", \r, \n, \t): für die doppelt maskierte
    /// documentation der Parameterhilfe.</summary>
    class function JsonEscaped(const AText: string): string; static;
    /// <summary>kibitzkind an ALine/ACharacter (0-basiert) in AText: 15 in der uses-Klausel, 2 nach "X.", sonst 7.
    /// </summary>
    class function KibitzKindAt(const AText: string; ALine, ACharacter: Integer): Integer; static;
    /// <summary>kind der IDE zu ASymbol.</summary>
    class function KindOf(const ASymbol: TIndexSymbol): Integer; static;
    /// <summary>detail wie DelphiLSP aus der Deklaration ASymbol (ohne die übrigen Symbole der Unit).</summary>
    class function DetailOf(const ASymbol: TIndexSymbol): string; static;
    /// <summary>detail wie DelphiLSP; ASymbols sind die Symbole der Unit (Ordnung und Grenzen von Aufzählungen),
    /// nil ohne.</summary>
    class function DetailWith(const ASymbol: TIndexSymbol; const ASymbols: TArray<TIndexSymbol>): string; static;
    /// <summary>DCC_Flags zu ASymbol ohne die Bits des Typs (Klasse, Record, Prozedurtyp); False, wenn für die Art
    /// kein Wert gemessen ist.</summary>
    class function DccFlagsOf(const ASymbol: TIndexSymbol; out AFlags: Int64): Boolean; static;
    /// <summary>Markdown grob als Klartext (Backticks, Sternchen, Rauten am Zeilenanfang, Trennlinien).</summary>
    class function PlainOf(const AMarkdown: string): string; static;
    /// <summary>Der Client ist RAD Studio (nach initialize).</summary>
    property Active: Boolean read GetActive;
    /// <summary>Verworfene Nachrichten des Servers an die IDE.</summary>
    property Dropped: Integer read FDropped;
    property UnitSymbols: TRadUnitSymbols read FUnitSymbols write FUnitSymbols;
    property TypeLookup: TRadTypeLookup read FTypeLookup write FTypeLookup;
    property OnInitialize: TRadInitializeEvent read FOnInitialize write FOnInitialize;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  dpcc.Common.Documents.Uris;

const
  cCrLf = #13#10;
  cArrow = #$2192;
  cBlockBreak = #10#10;
  cInitializeMethod = 'initialize';
  cCompletionMethod = 'textDocument/completion';
  cResolveMethod = 'completionItem/resolve';
  cSignatureMethod = 'textDocument/signatureHelp';
  cHoverMethod = 'textDocument/hover';
  cDefinitionMethod = 'textDocument/definition';
  cDeclarationMethod = 'textDocument/declaration';
  cTypeDefinitionMethod = 'textDocument/typeDefinition';
  cImplementationMethod = 'textDocument/implementation';
  cDidOpenMethod = 'textDocument/didOpen';
  cDidChangeMethod = 'textDocument/didChange';
  cDidCloseMethod = 'textDocument/didClose';
  // Arten des Servers (LSP), die eigens übersetzt werden.
  cServerKindVariable = 6;
  cServerKindModule = 9;
  cServerKindKeyword = 14;
  // Arten der IDE (gemessen an DelphiLSP).
  cRadKindMethod = 2;
  cRadKindRoutine = 3;
  cRadKindConstructor = 4;
  cRadKindField = 5;
  cRadKindVariable = 6;
  cRadKindClass = 7;
  cRadKindInterface = 8;
  cRadKindProperty = 10;
  cRadKindAlias = 12;
  cRadKindEnum = 13;
  cRadKindKeyword = 14;
  cRadKindUnit = 17;
  cRadKindPointer = 18;
  cRadKindEnumMember = 20;
  cRadKindConstant = 21;
  cRadKindRecord = 22;
  cRadKindEvent = 23;
  cFlagsUnit = $4026;
  /// <summary>Wörter nach dem Typ einer Property (Zugriff), die nicht in die Kopfzeile gehören.</summary>
  cAccessWords: array[0..9] of string = ('read', 'write', 'index', 'default', 'nodefault', 'stored', 'implements',
    'dispid', 'readonly', 'writeonly');
  /// <summary>Wörter, nach denen keine uses-Klausel mehr offen ist (unvollständiger Text).</summary>
  cSectionWords: array[0..10] of string = ('interface', 'implementation', 'begin', 'type', 'var', 'const',
    'procedure', 'function', 'initialization', 'finalization', 'end');

function IdKey(const AId: TJSONValue): string;
begin
  Result := '';
  if AId <> nil then
  begin
    Result := AId.ToJSON;
  end;
end;

/// <summary>Zeichenkette wie "2" als Zahl ersetzen (completionItem/resolve der IDE).</summary>
procedure NumberFromString(AObject: TJSONObject; const AName: string);
var
  mValue: TJSONValue;
  mNumber: Integer;
begin
  mValue := AObject.GetValue(AName);
  if (mValue is TJSONString) and not (mValue is TJSONNumber) and TryStrToInt(Trim(mValue.Value), mNumber) then
  begin
    AObject.RemovePair(AName).Free;
    AObject.AddPair(AName, TJSONNumber.Create(mNumber));
  end;
end;

/// <summary>Zeichen eines Bezeichners (auch &amp;-Escape und Unicode-Buchstaben).</summary>
function IsIdentChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_', '&']) or (Ord(AChar) > 127);
end;

/// <summary>Leerraum (auch Zeilenumbrüche) als ein Leerzeichen.</summary>
function CollapseSpaces(const AText: string): string;
var
  mIndex: Integer;
  mSpace: Boolean;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mSpace := False;
    for mIndex := 1 to Length(AText) do
    begin
      if CharInSet(AText[mIndex], [' ', #9, #13, #10]) then
      begin
        mSpace := True;
      end
      else
      begin
        if mSpace and (mBuilder.Length > 0) then
        begin
          mBuilder.Append(' ');
        end;
        mSpace := False;
        mBuilder.Append(AText[mIndex]);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Erster Bezeichner von AText (Leerraum davor übergangen); '' ohne.</summary>
function LeadingIdentifier(const AText: string): string;
var
  mIndex, mStart: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], [' ', #9, #13, #10]) do
  begin
    Inc(mIndex);
  end;
  mStart := mIndex;
  while (mIndex <= Length(AText)) and IsIdentChar(AText[mIndex]) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(AText, mStart, mIndex - mStart);
end;

/// <summary>Ohne abschließende ";" und Leerraum.</summary>
function StripSemicolons(const AText: string): string;
begin
  Result := TrimRight(AText);
  while EndsStr(';', Result) do
  begin
    Result := TrimRight(Copy(Result, 1, Length(Result) - 1));
  end;
end;

/// <summary>Position des ersten AChar ab AFrom außerhalb von Klammern ( [ &lt; und Zeichenketten; 0 ohne.</summary>
function PosTop(const AText: string; AChar: Char; AFrom: Integer): Integer;
var
  mIndex, mDepth: Integer;
  mQuoted: Boolean;
begin
  Result := 0;
  mDepth := 0;
  mQuoted := False;
  for mIndex := AFrom to Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
      Continue;
    end;
    if mQuoted then
    begin
      Continue;
    end;
    if (mDepth <= 0) and (AText[mIndex] = AChar) then
    begin
      Exit(mIndex);
    end;
    case AText[mIndex] of
      '(', '[', '<':
        Inc(mDepth);
      ')', ']', '>':
        Dec(mDepth);
    end;
  end;
end;

/// <summary>AText an ADelimiter außerhalb von Klammern und Zeichenketten geteilt.</summary>
function SplitTop(const AText: string; ADelimiter: Char): TArray<string>;
var
  mStart, mPos: Integer;
begin
  Result := nil;
  mStart := 1;
  while True do
  begin
    mPos := PosTop(AText, ADelimiter, mStart);
    if mPos = 0 then
    begin
      Result := Result + [Copy(AText, mStart, MaxInt)];
      Break;
    end;
    Result := Result + [Copy(AText, mStart, mPos - mStart)];
    mStart := mPos + 1;
  end;
end;

/// <summary>Position der Klammer ")", die die Klammer bei AOpen schließt; 0 ohne.</summary>
function MatchingClose(const AText: string; AOpen: Integer): Integer;
var
  mIndex, mDepth: Integer;
  mQuoted: Boolean;
begin
  Result := 0;
  mDepth := 0;
  mQuoted := False;
  for mIndex := AOpen to Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
      Continue;
    end;
    if mQuoted then
    begin
      Continue;
    end;
    if AText[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(mIndex);
      end;
    end;
  end;
end;

/// <summary>Position des ersten ganzen Worts aus AWords außerhalb von Klammern und Zeichenketten; 0 ohne.</summary>
function WordPosTop(const AText: string; const AWords: array of string): Integer;
var
  mIndex, mStart, mDepth: Integer;
  mQuoted: Boolean;
begin
  Result := 0;
  mDepth := 0;
  mQuoted := False;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
      Inc(mIndex);
      Continue;
    end;
    if mQuoted then
    begin
      Inc(mIndex);
      Continue;
    end;
    if IsIdentChar(AText[mIndex]) then
    begin
      mStart := mIndex;
      while (mIndex <= Length(AText)) and IsIdentChar(AText[mIndex]) do
      begin
        Inc(mIndex);
      end;
      if (mDepth <= 0) and (IndexText(Copy(AText, mStart, mIndex - mStart), AWords) >= 0) then
      begin
        Exit(mStart);
      end;
      Continue;
    end;
    case AText[mIndex] of
      '(', '[', '<':
        Inc(mDepth);
      ')', ']', '>':
        Dec(mDepth);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Teil der Signatur hinter dem Namen bis zum ersten ";" außerhalb von Klammern, z. B.
/// "(const A: Integer): Integer"; '' ohne Namen.</summary>
function AfterName(const ASignature, AName: string): string;
var
  mUpper, mName: string;
  mPos, mIndex, mDepth: Integer;
  mFound: Boolean;
begin
  Result := '';
  mUpper := UpperCase(ASignature);
  mName := UpperCase(AName);
  mPos := Pos(mName, mUpper);
  mFound := False;
  while mPos > 0 do
  begin
    // Ganzes Wort: davor kein Buchstabe, dahinter keiner.
    if ((mPos = 1) or not CharInSet(mUpper[mPos - 1], ['A'..'Z', '0'..'9', '_', '.'])) and
      ((mPos + Length(mName) > Length(mUpper)) or not CharInSet(mUpper[mPos + Length(mName)], ['A'..'Z', '0'..'9',
      '_'])) then
    begin
      mFound := True;
      Break;
    end;
    mPos := PosEx(mName, mUpper, mPos + 1);
  end;
  if not mFound then
  begin
    Exit;
  end;
  mIndex := mPos + Length(mName);
  mDepth := 0;
  while mIndex <= Length(ASignature) do
  begin
    case ASignature[mIndex] of
      '(', '[', '<':
        Inc(mDepth);
      ')', ']', '>':
        Dec(mDepth);
      ';':
        if mDepth <= 0 then
        begin
          Break;
        end;
    end;
    Result := Result + ASignature[mIndex];
    Inc(mIndex);
  end;
  Result := Trim(Result);
  // Generische Parameter des Namens (Foo<T>(…)) bleiben vorn stehen.
end;

/// <summary>Rechte Seite einer Typdeklaration "TFoo = class(TBar);" ohne ";": "class(TBar)"; '' ohne "=".</summary>
function TypeRhs(const ASignature: string): string;
var
  mPos: Integer;
begin
  Result := '';
  mPos := PosTop(ASignature, '=', 1);
  if mPos = 0 then
  begin
    Exit;
  end;
  Result := Trim(Copy(ASignature, mPos + 1, MaxInt));
  mPos := PosTop(Result, ';', 1);
  if mPos > 0 then
  begin
    Result := Trim(Copy(Result, 1, mPos - 1));
  end;
end;

/// <summary>Nur ein (qualifizierter) Typname ohne Typargumente und Schlüsselwörter.</summary>
function IsPlainTypeName(const AText: string): Boolean;
var
  mChar: Char;
begin
  Result := (AText <> '') and not StartsText('type ', AText);
  for mChar in AText do
  begin
    if not (IsIdentChar(mChar) or (mChar = '.')) then
    begin
      Exit(False);
    end;
  end;
end;

function IsDestructor(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := ASymbol.HasDirective('destructor') or StartsText('destructor', TrimLeft(ASymbol.Signature));
end;

function IsRoutineKind(AKind: TIndexSymbolKind): Boolean;
begin
  Result := AKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
end;

/// <summary>Typ eines Felds, einer Variablen oder Property als Text: TypeName mit Typargumenten, sonst aus der
/// Signatur ("array of Byte").</summary>
function SymbolTypeText(const ASymbol: TIndexSymbol): string;
var
  mRest: string;
  mPos: Integer;
begin
  Result := ASymbol.TypeName;
  if (Result <> '') and (ASymbol.TypeArgs <> '') and (Pos('<', Result) = 0) then
  begin
    Result := Result + '<' + ASymbol.TypeArgs + '>';
  end;
  if Result <> '' then
  begin
    Exit;
  end;
  mRest := AfterName(ASymbol.Signature, ASymbol.Name);
  mPos := PosTop(mRest, ':', 1);
  if mPos = 0 then
  begin
    Exit;
  end;
  Result := Trim(Copy(mRest, mPos + 1, MaxInt));
  mPos := PosTop(Result, '=', 1);
  if mPos > 0 then
  begin
    Result := Trim(Copy(Result, 1, mPos - 1));
  end;
  mPos := WordPosTop(Result, cAccessWords);
  if mPos > 0 then
  begin
    Result := Trim(Copy(Result, 1, mPos - 1));
  end;
end;

/// <summary>": Typ;" bzw. ";" ohne Typ.</summary>
function TypedDetail(const AType: string): string;
begin
  if AType = '' then
  begin
    Result := ';';
  end
  else
  begin
    Result := ': ' + AType + ';';
  end;
end;

/// <summary>"(A: Integer; B: Integer): Integer;" bzw. ": Integer;" oder ";".</summary>
function RoutineDetail(const AHead: TRadRoutineHead): string;
begin
  Result := '';
  if Length(AHead.Parameters) > 0 then
  begin
    Result := '(' + string.Join('; ', AHead.Parameters) + ')';
  end;
  if AHead.ResultType <> '' then
  begin
    Result := Result + ': ' + AHead.ResultType;
  end;
  Result := Result + ';';
end;

/// <summary>Ordnung des Aufzählungswerts ASymbol unter den Werten seines Typs in ASymbols; -1 unbekannt. Werte mit
/// eigener Zahl (A = 5) zählen wie die übrigen.</summary>
function EnumOrdinal(const ASymbol: TIndexSymbol; const ASymbols: TArray<TIndexSymbol>): Integer;
var
  mIndex, mCount: Integer;
begin
  Result := -1;
  mCount := 0;
  for mIndex := 0 to High(ASymbols) do
  begin
    if (ASymbols[mIndex].Kind = TIndexSymbolKind.EnumMember) and
      SameText(ASymbols[mIndex].Container, ASymbol.Container) then
    begin
      if ASymbols[mIndex].SelectionRange.StartPos = ASymbol.SelectionRange.StartPos then
      begin
        Exit(mCount);
      end;
      Inc(mCount);
    end;
  end;
end;

/// <summary>Erster und letzter Wert des Aufzählungstyps ASymbol: aus ASymbols, sonst aus der Signatur.</summary>
function EnumBounds(const ASymbol: TIndexSymbol; const ASymbols: TArray<TIndexSymbol>; out AFirst,
  ALast: string): Boolean;
var
  mIndex: Integer;
  mRest: string;
  mParts: TArray<string>;
begin
  AFirst := '';
  ALast := '';
  for mIndex := 0 to High(ASymbols) do
  begin
    if (ASymbols[mIndex].Kind = TIndexSymbolKind.EnumMember) and
      SameText(ASymbols[mIndex].Container, ASymbol.Name) then
    begin
      if AFirst = '' then
      begin
        AFirst := ASymbols[mIndex].Name;
      end;
      ALast := ASymbols[mIndex].Name;
    end;
  end;
  if AFirst = '' then
  begin
    mRest := TypeRhs(ASymbol.Signature);
    if StartsStr('(', mRest) and EndsStr(')', mRest) then
    begin
      mParts := SplitTop(Copy(mRest, 2, Length(mRest) - 2), ',');
      if Length(mParts) > 0 then
      begin
        AFirst := LeadingIdentifier(mParts[0]);
        ALast := LeadingIdentifier(mParts[High(mParts)]);
      end;
    end;
  end;
  Result := (AFirst <> '') and (ALast <> '');
end;

/// <summary>Name und Typ eines Parameters ("const A: Integer = 0" → A, Integer).</summary>
procedure SplitParameter(const AParameter: string; out AName, AType: string);
var
  mText, mWord: string;
  mPos: Integer;
begin
  mText := Trim(AParameter);
  while StartsStr('[', mText) and (Pos(']', mText) > 0) do
  begin
    mText := TrimLeft(Copy(mText, Pos(']', mText) + 1, MaxInt));
  end;
  mWord := LowerCase(LeadingIdentifier(mText));
  if (mWord = 'const') or (mWord = 'var') or (mWord = 'out') or (mWord = 'constref') then
  begin
    mText := TrimLeft(Copy(mText, Length(mWord) + 1, MaxInt));
  end;
  mPos := PosTop(mText, ':', 1);
  if mPos = 0 then
  begin
    AName := Trim(mText);
    AType := '';
    Exit;
  end;
  AName := Trim(Copy(mText, 1, mPos - 1));
  AType := Trim(Copy(mText, mPos + 1, MaxInt));
  mPos := PosTop(AType, '=', 1);
  if mPos > 0 then
  begin
    AType := Trim(Copy(AType, 1, mPos - 1));
  end;
end;

/// <summary>"P: TProbe" bzw. "GCounter: TCount = 0" → Name und Typ; False, wenn es keine solche Deklaration ist.
/// </summary>
function NameAndType(const ADeclaration: string; out AName, AType: string): Boolean;
var
  mText, mBefore: string;
  mPos: Integer;
  mChar: Char;
begin
  Result := False;
  AType := '';
  mText := Trim(ADeclaration);
  AName := LeadingIdentifier(mText);
  mPos := PosTop(mText, ':', 1);
  if (AName = '') or (mPos = 0) then
  begin
    Exit;
  end;
  // Vor dem Doppelpunkt nur Namen ("A, B"), kein Kopf wie "property X" oder "function F".
  mBefore := StringReplace(Trim(Copy(mText, 1, mPos - 1)), ', ', ',', [rfReplaceAll]);
  for mChar in mBefore do
  begin
    if not (IsIdentChar(mChar) or (mChar = ',')) then
    begin
      Exit;
    end;
  end;
  AType := Trim(Copy(mText, mPos + 1, MaxInt));
  mPos := PosTop(AType, '=', 1);
  if mPos > 0 then
  begin
    AType := Trim(Copy(AType, 1, mPos - 1));
  end;
  Result := AType <> '';
end;

/// <summary>A und B mit &lt;br&gt; verbunden; leere Teile fallen weg.</summary>
function JoinText(const A, B: string): string;
begin
  if A = '' then
  begin
    Result := B;
  end
  else if B = '' then
  begin
    Result := A;
  end
  else
  begin
    Result := A + '<br>' + B;
  end;
end;

/// <summary>Block "&lt;h4&gt;Titel&lt;/h4&gt;…" wie DelphiLSP; '' ohne Text.</summary>
function TitledBlock(const ATitle, AText: string): string;
begin
  Result := '';
  if AText <> '' then
  begin
    Result := '<h4>' + ATitle + '</h4>' + cCrLf + '<P>' + cCrLf + '<DL>' + AText + '</DL>' + cCrLf + '</P>' + cCrLf;
  end;
end;

/// <summary>Teilstücke eines Doku-Abschnitts (dpcc.Common.Lsp.Documentation) als HTML.</summary>
function RunsHtml(ARuns: TJSONArray): string;
var
  mRun: TJSONValue;
  mKind, mText: string;
begin
  Result := '';
  if ARuns = nil then
  begin
    Exit;
  end;
  for mRun in ARuns do
  begin
    if not (mRun is TJSONObject) then
    begin
      Continue;
    end;
    mKind := TJSONObject(mRun).GetValue<string>('kind', '');
    mText := TJSONObject(mRun).GetValue<string>('text', '');
    if mText = '' then
    begin
      mText := TJSONObject(mRun).GetValue<string>('target', '');
    end;
    if (mKind = 'br') or (mKind = 'para') or (mKind = 'bullet') or (mKind = 'codeblock') then
    begin
      if Result <> '' then
      begin
        Result := Result + '<br>';
      end;
    end
    else if (mKind = 'cell') and (Result <> '') then
    begin
      Result := Result + ' ';
    end;
    Result := Result + TRadStudioDialect.HtmlEscape(mText);
  end;
  Result := Trim(Result);
end;

/// <summary>Text aus documentation (String oder MarkupContent); '' ohne.</summary>
function DocumentationText(AValue: TJSONValue): string;
begin
  Result := '';
  if AValue is TJSONObject then
  begin
    Result := TJSONObject(AValue).GetValue<string>('value', '');
    if SameText(TJSONObject(AValue).GetValue<string>('kind', ''), 'markdown') then
    begin
      Result := TRadStudioDialect.PlainOf(Result);
    end;
  end
  else if (AValue is TJSONString) and not (AValue is TJSONNumber) then
  begin
    Result := AValue.Value;
  end;
end;

/// <summary>contents des Servers (String, MarkupContent oder Liste) als Klartext.</summary>
function ContentsText(AContents: TJSONValue): string;
var
  mItem: TJSONValue;
begin
  Result := '';
  if AContents is TJSONArray then
  begin
    for mItem in TJSONArray(AContents) do
    begin
      if Result <> '' then
      begin
        Result := Result + #13#10;
      end;
      Result := Result + DocumentationText(mItem);
    end;
  end
  else
  begin
    Result := DocumentationText(AContents);
  end;
end;

/// <summary>Blöcke des Hovers aus dem dpcc-Objekt: Summary, Parameters (je Parameter aus AParameters mit Typ und
/// Doku), Returns, Remarks.</summary>
function DpccBody(ADpcc: TJSONObject; const AParameters: TArray<string>): string;
var
  mSections, mRuns: TJSONArray;
  mSection: TJSONValue;
  mSummary, mReturns, mRemarks, mKind, mText, mName, mType, mDoc, mParameter: string;
  mNames, mTexts: TArray<string>;
  mIndex: Integer;
begin
  mSummary := '';
  mReturns := '';
  mRemarks := '';
  mNames := nil;
  mTexts := nil;
  if ADpcc.TryGetValue<TJSONArray>('documentation.sections', mSections) then
  begin
    for mSection in mSections do
    begin
      if not (mSection is TJSONObject) then
      begin
        Continue;
      end;
      mKind := TJSONObject(mSection).GetValue<string>('kind', '');
      mRuns := nil;
      if TJSONObject(mSection).GetValue('runs') is TJSONArray then
      begin
        mRuns := TJSONArray(TJSONObject(mSection).GetValue('runs'));
      end;
      mText := RunsHtml(mRuns);
      if mKind = 'summary' then
      begin
        mSummary := JoinText(mSummary, mText);
      end
      else if mKind = 'param' then
      begin
        mNames := mNames + [TJSONObject(mSection).GetValue<string>('name', '')];
        mTexts := mTexts + [mText];
      end
      else if mKind = 'returns' then
      begin
        mReturns := JoinText(mReturns, mText);
      end
      else if mKind = 'remarks' then
      begin
        mRemarks := JoinText(mRemarks, mText);
      end;
    end;
  end
  else
  begin
    // Kommentar ohne XMLDoc: als Summary.
    mSummary := TRadStudioDialect.HtmlEscape(Trim(ADpcc.GetValue<string>('documentationText', '')));
  end;
  Result := '';
  if mSummary <> '' then
  begin
    Result := '<p>' + mSummary + '</p>' + cCrLf;
  end;
  if Length(AParameters) > 0 then
  begin
    // Wie DelphiLSP bei jeder Routine mit Parametern, auch ohne Doku.
    Result := Result + '<h4>Parameters</h4>' + cCrLf + '<P>' + cCrLf + '<DL>' + cCrLf;
    for mParameter in AParameters do
    begin
      SplitParameter(mParameter, mName, mType);
      mDoc := '';
      for mIndex := 0 to High(mNames) do
      begin
        if SameText(mNames[mIndex], mName) then
        begin
          mDoc := mTexts[mIndex];
          Break;
        end;
      end;
      Result := Result + '<DT><I>' + TRadStudioDialect.HtmlEscape(mName) + '</I></DT>' + cCrLf + '<DD>' +
        TRadStudioDialect.HtmlEscape(mType) + '</DD>' + cCrLf + '<DD>' + mDoc + '</DD>' + cCrLf;
    end;
    Result := Result + '</DL>' + cCrLf + '</P>' + cCrLf;
  end;
  Result := Result + TitledBlock('Returns', mReturns) + TitledBlock('Remarks', mRemarks);
end;

/// <summary>Hover-HTML aus dem dpcc-Objekt der Antwort des Servers.</summary>
function DpccHoverHtml(ADpcc: TJSONObject): string;
var
  mDeclaration, mKind, mFile, mCaption: string;
  mHead: TRadRoutineHead;
begin
  mDeclaration := ADpcc.GetValue<string>('declaration', '');
  mKind := ADpcc.GetValue<string>('kind', '');
  mFile := ADpcc.GetValue<string>('file', '');
  mCaption := TRadStudioDialect.HoverCaption(mDeclaration, mKind, ADpcc.GetValue<string>('container', ''),
    ADpcc.GetValue<string>('unit', ''), mFile, ADpcc.GetValue<string>('value', ''));
  mHead := Default(TRadRoutineHead);
  if (mKind = 'method') or (mKind = 'constructor') or (mKind = 'routine') then
  begin
    TRadStudioDialect.ParseRoutine(CollapseSpaces(mDeclaration), mHead);
  end;
  Result := TRadStudioDialect.HoverHtml(mCaption, mFile, ADpcc.GetValue<Integer>('line', -1),
    DpccBody(ADpcc, mHead.Parameters));
end;

/// <summary>Blöcke der Parameterhilfe aus dem Klartext des Servers (TXmlDoc.ToPlainText ohne Parameter): erster
/// Absatz Summary, Zeilen mit "→" Returns, der Rest Remarks.</summary>
function SignatureBody(const AText: string): string;
var
  mBlock, mText, mLine, mSummary, mReturns, mRemarks: string;
  mLines: TArray<string>;
begin
  mSummary := '';
  mReturns := '';
  mRemarks := '';
  for mBlock in StringReplace(Trim(AText), #13#10, #10, [rfReplaceAll]).Split([cBlockBreak]) do
  begin
    mText := Trim(mBlock);
    if mText = '' then
    begin
      Continue;
    end;
    mLines := mText.Split([#10]);
    if StartsStr(cArrow, mLines[0]) then
    begin
      for mLine in mLines do
      begin
        if StartsStr(cArrow, mLine) then
        begin
          mReturns := JoinText(mReturns, TRadStudioDialect.HtmlEscape(Trim(Copy(mLine, 2, MaxInt))));
        end
        else
        begin
          mRemarks := JoinText(mRemarks, TRadStudioDialect.HtmlEscape(Trim(mLine)));
        end;
      end;
    end
    else if mSummary = '' then
    begin
      mSummary := TRadStudioDialect.HtmlEscape(mText);
    end
    else
    begin
      mRemarks := JoinText(mRemarks, TRadStudioDialect.HtmlEscape(mText));
    end;
  end;
  Result := '';
  if mSummary <> '' then
  begin
    Result := '<p>' + mSummary + '</p>' + cCrLf;
  end;
  Result := Result + TitledBlock('Returns', mReturns) + TitledBlock('Remarks', mRemarks);
end;

/// <summary>Parameter einer Signatur des Servers: label als Text (Bereich im label der Signatur) und Doku.</summary>
procedure ServerParameters(ASignature: TJSONObject; const ALabel: string; out ALabels, ADocs: TArray<string>);
var
  mParameters: TJSONArray;
  mValue, mLabelValue: TJSONValue;
  mParameter: TJSONObject;
  mText: string;
  mStart, mEnd: Integer;
begin
  ALabels := nil;
  ADocs := nil;
  if not ASignature.TryGetValue<TJSONArray>('parameters', mParameters) then
  begin
    Exit;
  end;
  for mValue in mParameters do
  begin
    if not (mValue is TJSONObject) then
    begin
      Continue;
    end;
    mParameter := TJSONObject(mValue);
    mLabelValue := mParameter.GetValue('label');
    mText := '';
    if (mLabelValue is TJSONArray) and (TJSONArray(mLabelValue).Count = 2) then
    begin
      // Bereich [Anfang, Ende) im Label der Signatur.
      mStart := TJSONArray(mLabelValue).Items[0].GetValue<Integer>;
      mEnd := TJSONArray(mLabelValue).Items[1].GetValue<Integer>;
      mText := Copy(ALabel, mStart + 1, mEnd - mStart);
    end
    else if mLabelValue <> nil then
    begin
      mText := mLabelValue.Value;
    end;
    ALabels := ALabels + [mText];
    ADocs := ADocs + [DocumentationText(mParameter.GetValue('documentation'))];
  end;
end;

/// <summary>Braucht der Eintrag mehr als seinen Namen (Änderungen, Vorlage, Befehl)?</summary>
function NeedsEdits(AItem: TJSONObject): Boolean;
var
  mEdits: TJSONArray;
begin
  Result := (AItem.GetValue('textEdit') <> nil) or (AItem.GetValue('command') <> nil) or
    (AItem.GetValue<Integer>('insertTextFormat', 1) = 2) or
    (AItem.TryGetValue<TJSONArray>('additionalTextEdits', mEdits) and (mEdits.Count > 0));
end;

/// <summary>Deklaration aus einem nicht geltenden Zweig ({$IFDEF}); DelphiLSP zeigt sie nicht.</summary>
function IsUnavailable(AItem: TJSONObject): Boolean;
begin
  Result := (AItem.GetValue('data') is TJSONObject) and
    TJSONObject(AItem.GetValue('data')).GetValue<Boolean>('unavailable', False);
end;

/// <summary>insertText des Servers (Bezeichner mit &amp;) übernehmen.</summary>
procedure AddInsertText(AServer, ATarget: TJSONObject);
begin
  if AServer.GetValue('insertText') <> nil then
  begin
    ATarget.AddPair('insertText', AServer.GetValue<string>('insertText', ''));
  end;
end;

function PositionKey(ALine, ACharacter: Integer): Int64;
begin
  Result := (Int64(ALine) shl 32) or Int64(Cardinal(ACharacter));
end;

type
  /// <summary>Symbole einer Datei mit Nachschlagen über den Anfang des Namens, für eine Antwort.</summary>
  TRadFileSymbols = class
  private
    FSymbols: TArray<TIndexSymbol>;
    FPositions: TDictionary<Int64, Integer>;
  public
    constructor Create(const ASymbols: TArray<TIndexSymbol>);
    destructor Destroy; override;
    /// <summary>Index des Symbols, dessen Name bei ALine/ACharacter beginnt; -1 ohne.</summary>
    function IndexAt(ALine, ACharacter: Integer): Integer;
    property Symbols: TArray<TIndexSymbol> read FSymbols;
  end;

  /// <summary>Bits des Typs einer Variablen, eines Felds oder einer Property.</summary>
  TRadTypeInfo = record
    /// <summary>0xE0 Klasse (auch class of), 0x60 Record, 0x80000E0 Interface.</summary>
    Bits: Int64;
    /// <summary>Prozedurtyp (Methodenzeiger, Ereignis): kind 23 und 0x20.</summary>
    Procedural: Boolean;
  end;

  /// <summary>Baut die Einträge der IDE zu den Einträgen des Servers; merkt sich Symbole, Typen und gelieferte
  /// Einträge für eine Antwort.</summary>
  TRadCompletionBuilder = class
  private
    FUnitSymbols: TRadUnitSymbols;
    FTypeLookup: TRadTypeLookup;
    FFiles: TObjectDictionary<string, TRadFileSymbols>;
    FTypes: TDictionary<string, TRadTypeInfo>;
    FEmitted: TDictionary<string, Boolean>;
    function FileSymbols(const AFileName: string): TRadFileSymbols;
    function TypeInfoOf(const ATypeName: string; ADepth: Integer): TRadTypeInfo;
    function SymbolItem(const ALabel: string; AFiles: TRadFileSymbols; AIndex: Integer;
      AServer: TJSONObject): TJSONObject;
    function FallbackItem(AServer: TJSONObject; out AKeyword: Boolean): TJSONObject;
    procedure AddSymbol(const ALabel, AFileName: string; AFiles: TRadFileSymbols; AIndex: Integer;
      AServer: TJSONObject; AItems, ASources: TList<TJSONObject>);
  public
    constructor Create(const AUnitSymbols: TRadUnitSymbols; const ATypeLookup: TRadTypeLookup);
    destructor Destroy; override;
    /// <summary>Einträge der IDE zu AServer (mehrere bei Überladungen, keiner bei schon gelieferten) an AItems bzw.
    /// AKeywords; die Listen der Quellen bekommen je Eintrag AServer.</summary>
    procedure Add(AServer: TJSONObject; AItems, ASources, AKeywords, AKeywordSources: TList<TJSONObject>);
  end;

{ TRadFileSymbols }

constructor TRadFileSymbols.Create(const ASymbols: TArray<TIndexSymbol>);
var
  mIndex: Integer;
  mKey: Int64;
begin
  inherited Create;
  FSymbols := ASymbols;
  FPositions := TDictionary<Int64, Integer>.Create;
  for mIndex := 0 to High(FSymbols) do
  begin
    mKey := PositionKey(FSymbols[mIndex].SelectionRange.StartPos.Line,
      FSymbols[mIndex].SelectionRange.StartPos.Character);
    if not FPositions.ContainsKey(mKey) then
    begin
      FPositions.Add(mKey, mIndex);
    end;
  end;
end;

destructor TRadFileSymbols.Destroy;
begin
  FPositions.Free;
  inherited;
end;

function TRadFileSymbols.IndexAt(ALine, ACharacter: Integer): Integer;
begin
  if not FPositions.TryGetValue(PositionKey(ALine, ACharacter), Result) then
  begin
    Result := -1;
  end;
end;

{ TRadCompletionBuilder }

constructor TRadCompletionBuilder.Create(const AUnitSymbols: TRadUnitSymbols; const ATypeLookup: TRadTypeLookup);
begin
  inherited Create;
  FUnitSymbols := AUnitSymbols;
  FTypeLookup := ATypeLookup;
  FFiles := TObjectDictionary<string, TRadFileSymbols>.Create([doOwnsValues]);
  FTypes := TDictionary<string, TRadTypeInfo>.Create;
  FEmitted := TDictionary<string, Boolean>.Create;
end;

destructor TRadCompletionBuilder.Destroy;
begin
  FEmitted.Free;
  FTypes.Free;
  FFiles.Free;
  inherited;
end;

function TRadCompletionBuilder.FileSymbols(const AFileName: string): TRadFileSymbols;
var
  mKey: string;
  mSymbols: TArray<TIndexSymbol>;
  mFound: Boolean;
begin
  mKey := LowerCase(AFileName);
  if FFiles.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := nil;
  mSymbols := nil;
  mFound := False;
  if Assigned(FUnitSymbols) then
  begin
    try
      mFound := FUnitSymbols(AFileName, mSymbols);
    except
      // Ohne Symbole bleibt der Eintrag des Servers.
      on Exception do
        mFound := False;
    end;
  end;
  if mFound then
  begin
    Result := TRadFileSymbols.Create(mSymbols);
  end;
  // Auch "unbekannt" merken: jede Datei wird je Antwort einmal gefragt.
  FFiles.AddOrSetValue(mKey, Result);
end;

function TRadCompletionBuilder.TypeInfoOf(const ATypeName: string; ADepth: Integer): TRadTypeInfo;
var
  mName, mKey, mRest: string;
  mSymbol: TIndexSymbol;
  mFound: Boolean;
begin
  Result := Default(TRadTypeInfo);
  mName := Trim(ATypeName);
  if LastDelimiter('.', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('.', mName) + 1, MaxInt);
  end;
  if mName = '' then
  begin
    Exit;
  end;
  mKey := LowerCase(mName);
  if FTypes.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  mFound := False;
  if Assigned(FTypeLookup) then
  begin
    try
      mFound := FTypeLookup(mName, mSymbol);
    except
      on Exception do
        mFound := False;
    end;
  end;
  if mFound then
  begin
    case mSymbol.Kind of
      TIndexSymbolKind.ClassType:
        Result.Bits := $E0;
      TIndexSymbolKind.RecordType, TIndexSymbolKind.ObjectType:
        Result.Bits := $60;
      TIndexSymbolKind.InterfaceType:
        Result.Bits := $80000E0;
      TIndexSymbolKind.TypeAlias:
        begin
          mRest := TypeRhs(mSymbol.Signature);
          if StartsText('class of', mRest) then
          begin
            Result.Bits := $E0;
          end
          else if StartsText('reference to', mRest) then
          begin
            Result.Bits := $80000E0;
          end
          else if StartsText('procedure', mRest) or StartsText('function', mRest) then
          begin
            Result.Procedural := True;
          end
          else if (ADepth < 3) and IsPlainTypeName(mRest) and not SameText(mRest, mName) then
          begin
            // Alias eines anderen Typs (TMREWSync = TMultiReadExclusiveWriteSynchronizer).
            Result := TypeInfoOf(mRest, ADepth + 1);
          end;
        end;
    else
      // Aufzählungen, Helfer und übrige Typen tragen keine eigenen Bits.
    end;
  end
  else if SameText(mName, 'TNotifyEvent') or EndsText('Event', mName) then
  begin
    // Ohne Index: sparsam nach dem Namen.
    Result.Procedural := True;
  end;
  FTypes.AddOrSetValue(mKey, Result);
end;

function TRadCompletionBuilder.SymbolItem(const ALabel: string; AFiles: TRadFileSymbols; AIndex: Integer;
  AServer: TJSONObject): TJSONObject;
var
  mSymbol: TIndexSymbol;
  mKind: Integer;
  mFlags: Int64;
  mHasFlags: Boolean;
  mInfo: TRadTypeInfo;
begin
  mSymbol := AFiles.Symbols[AIndex];
  mKind := TRadStudioDialect.KindOf(mSymbol);
  mHasFlags := TRadStudioDialect.DccFlagsOf(mSymbol, mFlags);
  if mSymbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Variable, TIndexSymbolKind.Property_] then
  begin
    mInfo := Default(TRadTypeInfo);
    if mSymbol.TypeName <> '' then
    begin
      mInfo := TypeInfoOf(mSymbol.TypeName, 0);
    end
    else if (mSymbol.TargetForm = 'procedure') or (mSymbol.TargetForm = 'function') then
    begin
      mInfo.Procedural := True;
    end
    else if mSymbol.TargetForm = 'class of' then
    begin
      mInfo.Bits := $E0;
    end;
    mFlags := mFlags or mInfo.Bits;
    if mInfo.Procedural then
    begin
      // Ereignis-Property (TNotifyEvent) bzw. Variable eines Prozedurtyps.
      mKind := cRadKindEvent;
      mFlags := mFlags or $20;
      if mSymbol.Kind = TIndexSymbolKind.Property_ then
      begin
        mFlags := mFlags or $10000;
      end;
    end;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('label', ALabel);
  Result.AddPair('kind', TJSONNumber.Create(mKind));
  Result.AddPair('detail', TRadStudioDialect.DetailWith(mSymbol, AFiles.Symbols));
  if mHasFlags then
  begin
    Result.AddPair('DCC_Flags', TJSONNumber.Create(mFlags));
  end;
  AddInsertText(AServer, Result);
end;

function TRadCompletionBuilder.FallbackItem(AServer: TJSONObject; out AKeyword: Boolean): TJSONObject;
var
  mKind, mRadKind: Integer;
  mDetail: string;
  mFlags: Int64;
  mInfo: TRadTypeInfo;
begin
  AKeyword := False;
  mKind := AServer.GetValue<Integer>('kind', 1);
  mDetail := AServer.GetValue<string>('detail', '');
  Result := TJSONObject.Create;
  Result.AddPair('label', AServer.GetValue<string>('label', ''));
  if mKind = cServerKindKeyword then
  begin
    AKeyword := True;
    Result.AddPair('kind', TJSONNumber.Create(cRadKindKeyword));
    Result.AddPair('detail', '');
    Result.AddPair('DCC_Flags', TJSONNumber.Create(0));
  end
  else if mKind = cServerKindModule then
  begin
    Result.AddPair('kind', TJSONNumber.Create(cRadKindUnit));
    Result.AddPair('detail', ';');
    Result.AddPair('DCC_Flags', TJSONNumber.Create(cFlagsUnit));
  end
  else if (mKind = cServerKindVariable) and (mDetail <> '') and not CharInSet(mDetail[1], [':', '(', ';', ' ']) then
  begin
    // Lokale Variable oder Parameter (kein Index-Symbol): detail des Servers ist der Typ.
    mInfo := TypeInfoOf(mDetail, 0);
    mRadKind := cRadKindVariable;
    mFlags := $3 or mInfo.Bits;
    if mInfo.Procedural then
    begin
      mRadKind := cRadKindEvent;
      mFlags := mFlags or $20;
    end;
    Result.AddPair('kind', TJSONNumber.Create(mRadKind));
    Result.AddPair('detail', ': ' + mDetail + ';');
    Result.AddPair('DCC_Flags', TJSONNumber.Create(mFlags));
  end
  else
  begin
    Result.AddPair('kind', TJSONNumber.Create(mKind));
    Result.AddPair('detail', mDetail);
  end;
  AddInsertText(AServer, Result);
end;

procedure TRadCompletionBuilder.AddSymbol(const ALabel, AFileName: string; AFiles: TRadFileSymbols; AIndex: Integer;
  AServer: TJSONObject; AItems, ASources: TList<TJSONObject>);
var
  mItem: TJSONObject;
  mKey: string;
begin
  mItem := SymbolItem(ALabel, AFiles, AIndex, AServer);
  // Dieselbe Deklaration nur einmal (Überladungen kommen beim ersten Namen, Rümpfe im implementation-Teil gleichen
  // ihrer Deklaration).
  mKey := LowerCase(AFileName) + #1 + LowerCase(ALabel) + #1 + mItem.GetValue<string>('detail', '') + #1 +
    IntToStr(mItem.GetValue<Integer>('kind', 0));
  if FEmitted.ContainsKey(mKey) then
  begin
    mItem.Free;
    Exit;
  end;
  FEmitted.Add(mKey, True);
  AItems.Add(mItem);
  ASources.Add(AServer);
end;

procedure TRadCompletionBuilder.Add(AServer: TJSONObject; AItems, ASources, AKeywords,
  AKeywordSources: TList<TJSONObject>);
var
  mData: TJSONObject;
  mFile, mLabel: string;
  mFiles: TRadFileSymbols;
  mIndex, mSibling: Integer;
  mSymbol: TIndexSymbol;
  mItem: TJSONObject;
  mKeyword: Boolean;
begin
  mLabel := AServer.GetValue<string>('label', '');
  mFile := '';
  mFiles := nil;
  mIndex := -1;
  if AServer.GetValue('data') is TJSONObject then
  begin
    mData := TJSONObject(AServer.GetValue('data'));
    mFile := mData.GetValue<string>('file', '');
    if mFile <> '' then
    begin
      mFiles := FileSymbols(mFile);
      if mFiles <> nil then
      begin
        mIndex := mFiles.IndexAt(mData.GetValue<Integer>('line', -1), mData.GetValue<Integer>('character', -1));
      end;
    end;
  end;
  if mIndex < 0 then
  begin
    mItem := FallbackItem(AServer, mKeyword);
    if mKeyword then
    begin
      AKeywords.Add(mItem);
      AKeywordSources.Add(AServer);
    end
    else
    begin
      AItems.Add(mItem);
      ASources.Add(AServer);
    end;
    Exit;
  end;
  mSymbol := mFiles.Symbols[mIndex];
  if not (IsRoutineKind(mSymbol.Kind) and mSymbol.HasDirective('overload')) then
  begin
    AddSymbol(mLabel, mFile, mFiles, mIndex, AServer, AItems, ASources);
    Exit;
  end;
  // Überladungen einzeln wie DelphiLSP: alle gleichnamigen Routinen desselben Typs in der Unit.
  for mSibling := 0 to High(mFiles.Symbols) do
  begin
    if IsRoutineKind(mFiles.Symbols[mSibling].Kind) and SameText(mFiles.Symbols[mSibling].Name, mSymbol.Name) and
      SameText(mFiles.Symbols[mSibling].Container, mSymbol.Container) then
    begin
      AddSymbol(mLabel, mFile, mFiles, mSibling, AServer, AItems, ASources);
    end;
  end;
end;

{ TRadStudioDialect }

constructor TRadStudioDialect.Create(const AInner: IJsonRpcTransport);
begin
  inherited Create;
  FInner := AInner;
  FLock := TCriticalSection.Create;
  FPending := TDictionary<string, TRadPendingRequest>.Create;
  FLastItems := TObjectDictionary<string, TJSONObject>.Create([doOwnsValues]);
  FLastRadItems := TObjectDictionary<string, TJSONObject>.Create([doOwnsValues]);
  FUris := TDictionary<string, string>.Create;
  FTexts := TDictionary<string, string>.Create;
end;

destructor TRadStudioDialect.Destroy;
begin
  FTexts.Free;
  FUris.Free;
  FLastRadItems.Free;
  FLastItems.Free;
  FPending.Free;
  FLock.Free;
  FInner := nil;
  inherited;
end;

function TRadStudioDialect.GetActive: Boolean;
begin
  FLock.Enter;
  try
    Result := FActive;
  finally
    FLock.Leave;
  end;
end;

procedure TRadStudioDialect.NoteInitialize(AMessage: TJSONObject);
var
  mParams: TJSONObject;
  mName: string;
  mProcessId: Int64;
  mValue: TJSONValue;
begin
  mName := '';
  mProcessId := 0;
  if AMessage.GetValue('params') is TJSONObject then
  begin
    mParams := TJSONObject(AMessage.GetValue('params'));
    mName := mParams.GetValue<string>('clientInfo.name', '');
    mValue := mParams.GetValue('processId');
    if mValue is TJSONNumber then
    begin
      mProcessId := TJSONNumber(mValue).AsInt64;
    end;
  end;
  FLock.Enter;
  try
    if not FDecided then
    begin
      FDecided := True;
      FActive := SameText(Trim(mName), cClientName);
    end;
  finally
    FLock.Leave;
  end;
  if Assigned(FOnInitialize) then
  begin
    if (mProcessId < 0) or (mProcessId > High(Cardinal)) then
    begin
      mProcessId := 0;
    end;
    FOnInitialize(mName, Cardinal(mProcessId));
  end;
end;

procedure TRadStudioDialect.NoteDocument(const AMethod: string; AMessage: TJSONObject);
var
  mParams: TJSONObject;
  mUri, mKey, mText: string;
  mChanges: TJSONArray;
  mChange: TJSONValue;
  mHasText: Boolean;
begin
  if not (AMessage.GetValue('params') is TJSONObject) then
  begin
    Exit;
  end;
  mParams := TJSONObject(AMessage.GetValue('params'));
  mUri := mParams.GetValue<string>('textDocument.uri', '');
  if mUri = '' then
  begin
    Exit;
  end;
  mKey := TDocumentUris.Key(mUri);
  mText := '';
  mHasText := False;
  if AMethod = cDidOpenMethod then
  begin
    mHasText := mParams.TryGetValue<string>('textDocument.text', mText);
  end
  else if (AMethod = cDidChangeMethod) and mParams.TryGetValue<TJSONArray>('contentChanges', mChanges) and
    (mChanges.Count > 0) then
  begin
    // Nur der ganze Text (textDocumentSync 1); nach einer Teiländerung gilt der alte Stand nicht mehr.
    mChange := mChanges.Items[mChanges.Count - 1];
    mHasText := (mChange is TJSONObject) and (TJSONObject(mChange).GetValue('range') = nil) and
      TJSONObject(mChange).TryGetValue<string>('text', mText);
  end;
  FLock.Enter;
  try
    if AMethod = cDidOpenMethod then
    begin
      FUris.AddOrSetValue(mKey, mUri);
    end;
    if mHasText then
    begin
      FTexts.AddOrSetValue(mKey, mText);
    end
    else
    begin
      FTexts.Remove(mKey);
    end;
  finally
    FLock.Leave;
  end;
end;

function TRadStudioDialect.KibitzOf(AMessage: TJSONObject): Integer;
var
  mParams: TJSONObject;
  mUri, mText: string;
  mLine, mCharacter: Integer;
  mFound: Boolean;
begin
  Result := cKibitzMember;
  if not (AMessage.GetValue('params') is TJSONObject) then
  begin
    Exit;
  end;
  mParams := TJSONObject(AMessage.GetValue('params'));
  mUri := mParams.GetValue<string>('textDocument.uri', '');
  mLine := mParams.GetValue<Integer>('position.line', -1);
  mCharacter := mParams.GetValue<Integer>('position.character', -1);
  if (mUri = '') or (mLine < 0) or (mCharacter < 0) then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    mFound := FTexts.TryGetValue(TDocumentUris.Key(mUri), mText);
  finally
    FLock.Leave;
  end;
  if mFound then
  begin
    Result := KibitzKindAt(mText, mLine, mCharacter);
  end;
end;

function TRadStudioDialect.FixResolveParams(AMessage: TJSONObject): string;
var
  mParams, mOriginal: TJSONObject;
  mKey: string;
begin
  Result := '';
  if not (AMessage.GetValue('params') is TJSONObject) then
  begin
    Exit;
  end;
  mParams := TJSONObject(AMessage.GetValue('params'));
  NumberFromString(mParams, 'kind');
  NumberFromString(mParams, 'insertTextFormat');
  // Die IDE schickt den Eintrag ohne data zurück: den Eintrag des Servers einsetzen.
  mKey := mParams.GetValue<string>('sortText', '') + #1 + mParams.GetValue<string>('label', '');
  FLock.Enter;
  try
    if FLastItems.TryGetValue(mKey, mOriginal) then
    begin
      AMessage.RemovePair('params').Free;
      AMessage.AddPair('params', TJSONObject(mOriginal.Clone));
      Result := mKey;
    end;
  finally
    FLock.Leave;
  end;
end;

function TRadStudioDialect.ReadMessage: TJSONObject;
var
  mMethod: string;
  mId: TJSONValue;
  mPending: TRadPendingRequest;
begin
  Result := FInner.ReadMessage;
  try
    mMethod := Result.GetValue<string>('method', '');
    mId := Result.GetValue('id');
    if mMethod = cInitializeMethod then
    begin
      NoteInitialize(Result);
    end;
    mPending.Method := mMethod;
    mPending.Kibitz := cKibitzMember;
    mPending.ResolveKey := '';
    mPending.ResolveEcho := '';
    if Active then
    begin
      if (mMethod = cDidOpenMethod) or (mMethod = cDidChangeMethod) or (mMethod = cDidCloseMethod) then
      begin
        NoteDocument(mMethod, Result);
      end
      else if mMethod = cCompletionMethod then
      begin
        mPending.Kibitz := KibitzOf(Result);
      end
      else if mMethod = cResolveMethod then
      begin
        if Result.GetValue('params') is TJSONObject then
        begin
          mPending.ResolveEcho := Result.GetValue('params').ToJSON;
        end;
        mPending.ResolveKey := FixResolveParams(Result);
      end
      else if mMethod = cImplementationMethod then
      begin
        // Wie DelphiLSP: dasselbe Ziel wie definition; die Antwort geht als implementation zurück.
        Result.RemovePair('method').Free;
        Result.AddPair('method', cDefinitionMethod);
      end;
    end;
    if (mMethod <> '') and (mId <> nil) then
    begin
      FLock.Enter;
      try
        FPending.AddOrSetValue(IdKey(mId), mPending);
      finally
        FLock.Leave;
      end;
    end;
  except
    // Eine unerwartete Form darf die Nachricht nicht verlieren: unverändert weiter.
    on Exception do
      ;
  end;
end;

function TRadStudioDialect.TakePending(const AId: TJSONValue; out APending: TRadPendingRequest): Boolean;
var
  mKey: string;
begin
  mKey := IdKey(AId);
  FLock.Enter;
  try
    Result := FPending.TryGetValue(mKey, APending);
    if Result then
    begin
      FPending.Remove(mKey);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TRadStudioDialect.WriteMessage(const AMessage: TJSONObject);
var
  mPending: TRadPendingRequest;
  mResult, mNew: TJSONValue;
  mCopy: TJSONObject;
begin
  if AMessage.GetValue('method') <> nil then
  begin
    // Benachrichtigung oder Anfrage des Servers: Die IDE kennt sie nicht.
    if Active then
    begin
      TInterlocked.Increment(FDropped);
      Exit;
    end;
    FInner.WriteMessage(AMessage);
    Exit;
  end;
  if not TakePending(AMessage.GetValue('id'), mPending) then
  begin
    mPending.Method := '';
    mPending.Kibitz := cKibitzMember;
    mPending.ResolveKey := '';
  end;
  mResult := AMessage.GetValue('result');
  if (mResult = nil) or ((mPending.Method <> cInitializeMethod) and not Active) then
  begin
    FInner.WriteMessage(AMessage);
    Exit;
  end;
  mNew := nil;
  try
    mNew := Transform(mPending, mResult);
  except
    // Lieber die Antwort des Servers als keine.
    on Exception do
      FreeAndNil(mNew);
  end;
  if mNew = nil then
  begin
    FInner.WriteMessage(AMessage);
    Exit;
  end;
  mCopy := TJSONObject.Create;
  try
    mCopy.AddPair('jsonrpc', '2.0');
    mCopy.AddPair('id', TJSONValue(AMessage.GetValue('id').Clone));
    mCopy.AddPair('result', mNew);
    FInner.WriteMessage(mCopy);
  finally
    mCopy.Free;
  end;
end;

function TRadStudioDialect.Transform(const APending: TRadPendingRequest; AResult: TJSONValue): TJSONValue;
var
  mCaps: TJSONObject;
  mResult: TJSONObject;
  mMethod: string;
begin
  Result := nil;
  mMethod := APending.Method;
  if mMethod = cInitializeMethod then
  begin
    if not (AResult is TJSONObject) or not (TJSONObject(AResult).GetValue('capabilities') is TJSONObject) then
    begin
      Exit;
    end;
    mResult := TJSONObject(AResult.Clone);
    try
      if Active then
      begin
        mCaps := RadCapabilities(TJSONObject(TJSONObject(AResult).GetValue('capabilities')));
      end
      else
      begin
        mCaps := TJSONObject(TJSONObject(AResult).GetValue('capabilities').Clone);
        if mCaps.GetValue('documentSymbolProvider') = nil then
        begin
          mCaps.AddPair('documentSymbolProvider', TJSONBool.Create(True));
        end;
      end;
      mResult.RemovePair('capabilities').Free;
      mResult.AddPair('capabilities', mCaps);
    except
      mResult.Free;
      raise;
    end;
    Exit(mResult);
  end;
  if mMethod = cCompletionMethod then
  begin
    Result := CompletionAnswer(AResult, APending.Kibitz);
  end
  else if mMethod = cResolveMethod then
  begin
    Result := ResolveAnswer(AResult, APending.ResolveKey, APending.ResolveEcho);
  end
  else if mMethod = cSignatureMethod then
  begin
    Result := SignatureAnswer(AResult);
  end
  else if mMethod = cHoverMethod then
  begin
    Result := HoverAnswer(AResult);
  end
  else if (mMethod = cDefinitionMethod) or (mMethod = cDeclarationMethod) or (mMethod = cTypeDefinitionMethod) or
    (mMethod = cImplementationMethod) then
  begin
    Result := LocationAnswer(AResult);
  end;
end;

class function TRadStudioDialect.RadCapabilities(const AServer: TJSONObject): TJSONObject;
var
  mTriggers: TJSONArray;
  mCompletion, mSignature: TJSONObject;
  mName: string;
begin
  Result := TJSONObject.Create;
  // Ganzer Text bei jeder Änderung, wie die IDE ohnehin schickt.
  Result.AddPair('textDocumentSync', TJSONNumber.Create(1));
  for mName in TArray<string>.Create('definitionProvider', 'declarationProvider', 'typeDefinitionProvider') do
  begin
    if AServer.GetValue(mName) <> nil then
    begin
      Result.AddPair(mName, TJSONBool.Create(True));
    end;
  end;
  // implementation beantwortet der Übersetzer über definition (DelphiLSP liefert dasselbe Ziel).
  if AServer.GetValue('definitionProvider') <> nil then
  begin
    Result.AddPair('implementationProvider', TJSONBool.Create(True));
  end;
  Result.AddPair('documentSymbolProvider', TJSONBool.Create(True));
  if AServer.GetValue('hoverProvider') <> nil then
  begin
    Result.AddPair('hoverProvider', TJSONBool.Create(True));
  end;
  if AServer.GetValue('completionProvider') <> nil then
  begin
    mCompletion := TJSONObject.Create;
    mCompletion.AddPair('resolveProvider', TJSONBool.Create(True));
    mTriggers := TJSONArray.Create;
    mTriggers.Add('.').Add('(').Add('<').Add('[');
    mCompletion.AddPair('triggerCharacters', mTriggers);
    Result.AddPair('completionProvider', mCompletion);
  end;
  if AServer.GetValue('signatureHelpProvider') <> nil then
  begin
    mSignature := TJSONObject.Create;
    mTriggers := TJSONArray.Create;
    mTriggers.Add('(').Add(',').Add('<');
    mSignature.AddPair('triggerCharacters', mTriggers);
    Result.AddPair('signatureHelpProvider', mSignature);
  end;
end;

class function TRadStudioDialect.PlainOf(const AMarkdown: string): string;
var
  mLines: TArray<string>;
  mLine, mText: string;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mLines := StringReplace(AMarkdown, #13#10, #10, [rfReplaceAll]).Split([#10]);
    for mLine in mLines do
    begin
      mText := mLine;
      if StartsStr('```', Trim(mText)) or (Trim(mText) = '---') then
      begin
        Continue;
      end;
      while StartsStr('#', mText) do
      begin
        mText := Copy(mText, 2, MaxInt);
      end;
      mText := StringReplace(mText, '**', '', [rfReplaceAll]);
      mText := StringReplace(mText, '`', '', [rfReplaceAll]);
      mText := StringReplace(mText, '\_', '_', [rfReplaceAll]);
      if mBuilder.Length > 0 then
      begin
        mBuilder.Append(#13#10);
      end;
      mBuilder.Append(TrimLeft(mText));
    end;
    Result := Trim(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

class function TRadStudioDialect.HtmlEscape(const AText: string): string;
begin
  Result := StringReplace(AText, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, #13#10, '<br>', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '<br>', [rfReplaceAll]);
end;

class function TRadStudioDialect.JsonEscaped(const AText: string): string;
begin
  Result := StringReplace(AText, '\', '\\', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '\"', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\r', [rfReplaceAll]);
  Result := StringReplace(Result, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
end;

class function TRadStudioDialect.HoverHtml(const ACaption, AFileName: string; ALine: Integer;
  const ABody: string): string;
var
  mCaption, mLink, mLine: string;
begin
  mCaption := HtmlEscape(ACaption);
  mLink := '';
  if (AFileName <> '') and (ALine >= 0) then
  begin
    mLine := IntToStr(ALine + 1);
    mLink := cCrLf + #9#9#9#9#9 + '-' + cCrLf + #9#9 + '<a class="codelink" href="helpinsight:/filelink:' +
      HtmlEscape(AFileName) + '?' + mLine + ',1">' + HtmlEscape(ExtractFileName(AFileName)) + ' (' + mLine + ')</a>';
  end;
  Result := '<html>' + cCrLf + '<head>' + cCrLf + '<META http-equiv="Content-Type" content="text/html">' + cCrLf +
    '<link type="text/css" rel="Stylesheet" href="HelpInsight.css">' + cCrLf + '<title>' + mCaption + '</title>' +
    cCrLf + '</head>' + cCrLf + '<body>' + cCrLf + '<div name="main">' + cCrLf +
    '<table width="100%" cellpadding="0" cellspacing="0">' + cCrLf + '<tr>' + cCrLf + '<td nowrap="true">' + cCrLf +
    '<div class="maincaption">' + mCaption + mLink + '</div>' + cCrLf + '</td>' + cCrLf + '</tr>' + cCrLf +
    '</table>' + cCrLf + ABody + '</div>' + cCrLf + '</body>' + cCrLf + '</html>' + cCrLf;
end;

class function TRadStudioDialect.HoverCaption(const ADeclaration, AKind, AContainer, AUnitName, AFileName,
  AValue: string): string;
var
  mDecl, mUnit, mQualifier, mName, mType, mRest, mOrdinal: string;
  mHead: TRadRoutineHead;
  mPos, mFrom: Integer;
begin
  mDecl := StripSemicolons(CollapseSpaces(ADeclaration));
  // "System.Classes (Datei.inc)" bei Include-Dateien: nur die Unit.
  mUnit := AUnitName;
  mPos := Pos(' (', mUnit);
  if mPos > 0 then
  begin
    mUnit := Copy(mUnit, 1, mPos - 1);
  end;
  mQualifier := '';
  if mUnit <> '' then
  begin
    mQualifier := mUnit + '.';
  end;
  if (AContainer <> '') and (AKind <> 'enumMember') then
  begin
    mQualifier := mQualifier + AContainer + '.';
  end;
  if (AKind = 'method') or (AKind = 'constructor') or (AKind = 'routine') then
  begin
    if not ParseRoutine(mDecl, mHead) then
    begin
      Exit(mDecl);
    end;
    if Pos('.', mHead.Name) > 0 then
    begin
      // Schon qualifiziert (Kopf aus dem implementation-Teil).
      mQualifier := '';
      if mUnit <> '' then
      begin
        mQualifier := mUnit + '.';
      end;
    end;
    Exit(RoutineCaption(mHead, mQualifier));
  end;
  if (AKind = 'class') or (AKind = 'object') or (AKind = 'record') or (AKind = 'interface') or (AKind = 'helper') or
    (AKind = 'enum') or (AKind = 'type') or (AKind = 'classref') then
  begin
    mPos := PosTop(mDecl, '=', 1);
    if mPos = 0 then
    begin
      Exit('type ' + mQualifier + mDecl);
    end;
    mName := Trim(Copy(mDecl, 1, mPos - 1));
    mRest := Trim(Copy(mDecl, mPos + 1, MaxInt));
    // Wie DelphiLSP: Klassen ohne Vorfahr mit (TObject).
    if (AKind = 'class') and StartsText('class', mRest) and not StartsText('class of', mRest) and
      (Pos('(', mRest) = 0) and not SameText(mName, 'TObject') then
    begin
      mRest := mRest + '(TObject)';
    end;
    Exit('type ' + mQualifier + mName + ' = ' + mRest);
  end;
  if AKind = 'enumMember' then
  begin
    // Die Deklaration ist die Zeile ab dem Namen ("ckGreen, ckBlue);"): Name, Typ und Ordnung einzeln.
    mName := LeadingIdentifier(mDecl);
    mOrdinal := '';
    if StartsText('Ord = ', AValue) then
    begin
      mOrdinal := Trim(Copy(AValue, Length('Ord = ') + 1, MaxInt));
    end;
    if mUnit = '' then
    begin
      mUnit := ChangeFileExt(ExtractFileName(AFileName), '');
    end;
    if (AContainer <> '') and (mOrdinal <> '') and (mUnit <> '') then
    begin
      Exit('const ' + mUnit + '.' + mName + ' = ' + AContainer + '(' + mOrdinal + ')');
    end;
    Exit('const ' + mName);
  end;
  if AKind = 'constant' then
  begin
    Exit('const ' + mQualifier + mDecl);
  end;
  if AKind = 'property' then
  begin
    mRest := mDecl;
    if StartsText('class ', mRest) then
    begin
      mRest := TrimLeft(Copy(mRest, Length('class ') + 1, MaxInt));
    end;
    if StartsText('property ', mRest) then
    begin
      mRest := TrimLeft(Copy(mRest, Length('property ') + 1, MaxInt));
    end;
    // Ohne Zugriff (read, write, default …); gesucht erst hinter dem Typ.
    mFrom := PosTop(mRest, ':', 1);
    if mFrom = 0 then
    begin
      mFrom := Length(LeadingIdentifier(mRest)) + 1;
    end;
    mPos := WordPosTop(Copy(mRest, mFrom, MaxInt), cAccessWords);
    if mPos > 0 then
    begin
      mRest := TrimRight(Copy(mRest, 1, mFrom + mPos - 2));
    end;
    Exit('property ' + mQualifier + mRest);
  end;
  if (AKind = 'field') or (AKind = 'variable') or (AKind = '') then
  begin
    if NameAndType(mDecl, mName, mType) then
    begin
      Exit('var ' + mQualifier + mName + ': ' + mType);
    end;
  end;
  Result := mDecl;
end;

class function TRadStudioDialect.ParseRoutine(const AText: string; out AHead: TRadRoutineHead): Boolean;
var
  mText, mWord, mLower: string;
  mIndex, mStart, mDepth, mClose, mEnd: Integer;
begin
  AHead := Default(TRadRoutineHead);
  Result := False;
  mText := Trim(AText);
  mIndex := 1;
  // Schlüsselwörter vor dem Namen.
  while True do
  begin
    while (mIndex <= Length(mText)) and CharInSet(mText[mIndex], [' ', #9]) do
    begin
      Inc(mIndex);
    end;
    mStart := mIndex;
    while (mIndex <= Length(mText)) and IsIdentChar(mText[mIndex]) do
    begin
      Inc(mIndex);
    end;
    mWord := Copy(mText, mStart, mIndex - mStart);
    mLower := LowerCase(mWord);
    if (mLower <> 'class') and (mLower <> 'procedure') and (mLower <> 'function') and (mLower <> 'constructor') and
      (mLower <> 'destructor') and (mLower <> 'operator') then
    begin
      Exit;
    end;
    if AHead.Head <> '' then
    begin
      AHead.Head := AHead.Head + ' ';
    end;
    AHead.Head := AHead.Head + mLower;
    if mLower <> 'class' then
    begin
      Break;
    end;
  end;
  // Name bis zur Parameterliste, zum Ergebnistyp oder zum Ende des Kopfs.
  while (mIndex <= Length(mText)) and CharInSet(mText[mIndex], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  mStart := mIndex;
  mDepth := 0;
  while mIndex <= Length(mText) do
  begin
    if mText[mIndex] = '<' then
    begin
      Inc(mDepth);
    end
    else if mText[mIndex] = '>' then
    begin
      Dec(mDepth);
    end
    else if (mDepth <= 0) and CharInSet(mText[mIndex], ['(', ':', ';', '=', ' ', #9]) then
    begin
      Break;
    end;
    Inc(mIndex);
  end;
  AHead.Name := Trim(Copy(mText, mStart, mIndex - mStart));
  if AHead.Name = '' then
  begin
    Exit;
  end;
  while (mIndex <= Length(mText)) and CharInSet(mText[mIndex], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  if (mIndex <= Length(mText)) and (mText[mIndex] = '(') then
  begin
    mClose := MatchingClose(mText, mIndex);
    if mClose = 0 then
    begin
      mClose := Length(mText) + 1;
    end;
    AHead.Parameters := ResolveParameters(Copy(mText, mIndex + 1, mClose - mIndex - 1));
    mIndex := mClose + 1;
  end;
  while (mIndex <= Length(mText)) and CharInSet(mText[mIndex], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  if (mIndex <= Length(mText)) and (mText[mIndex] = ':') then
  begin
    mEnd := PosTop(mText, ';', mIndex + 1);
    if mEnd = 0 then
    begin
      mEnd := Length(mText) + 1;
    end;
    AHead.ResultType := Trim(Copy(mText, mIndex + 1, mEnd - mIndex - 1));
  end;
  Result := True;
end;

class function TRadStudioDialect.ResolveParameters(const AText: string): TArray<string>;
var
  mGroup, mRest, mPrefix, mWord, mNames, mType, mName: string;
  mPos: Integer;
begin
  Result := nil;
  for mGroup in SplitTop(AText, ';') do
  begin
    mRest := Trim(mGroup);
    if mRest = '' then
    begin
      Continue;
    end;
    mPrefix := '';
    // Attribute vor dem Parameter ([ref]).
    while StartsStr('[', mRest) and (Pos(']', mRest) > 0) do
    begin
      mPos := Pos(']', mRest);
      mPrefix := mPrefix + Copy(mRest, 1, mPos) + ' ';
      mRest := TrimLeft(Copy(mRest, mPos + 1, MaxInt));
    end;
    mWord := LeadingIdentifier(mRest);
    if SameText(mWord, 'const') or SameText(mWord, 'var') or SameText(mWord, 'out') or
      SameText(mWord, 'constref') then
    begin
      mPrefix := mPrefix + mWord + ' ';
      mRest := TrimLeft(Copy(mRest, Length(mWord) + 1, MaxInt));
    end;
    mPos := PosTop(mRest, ':', 1);
    if mPos > 0 then
    begin
      mNames := Copy(mRest, 1, mPos - 1);
      mType := Trim(Copy(mRest, mPos + 1, MaxInt));
    end
    else
    begin
      // Untypisiert (var Message).
      mNames := mRest;
      mType := '';
    end;
    for mName in mNames.Split([',']) do
    begin
      if Trim(mName) = '' then
      begin
        Continue;
      end;
      if mType <> '' then
      begin
        Result := Result + [mPrefix + Trim(mName) + ': ' + mType];
      end
      else
      begin
        Result := Result + [mPrefix + Trim(mName)];
      end;
    end;
  end;
end;

class function TRadStudioDialect.RoutineCaption(const AHead: TRadRoutineHead; const AQualifier: string): string;
begin
  Result := AHead.Head + ' ' + AQualifier + AHead.Name;
  if Length(AHead.Parameters) > 0 then
  begin
    Result := Result + '(' + string.Join('; ', AHead.Parameters) + ')';
  end;
  if AHead.ResultType <> '' then
  begin
    Result := Result + ': ' + AHead.ResultType;
  end;
end;

class function TRadStudioDialect.HoverAnswer(AResult: TJSONValue): TJSONValue;
var
  mDpcc: TJSONValue;
  mHtml, mCaption, mBody: string;
  mLines: TArray<string>;
  mIndex: Integer;
begin
  if not (AResult is TJSONObject) then
  begin
    // null: kein Hover.
    Exit(nil);
  end;
  mDpcc := TJSONObject(AResult).GetValue('dpcc');
  if (mDpcc is TJSONObject) and (TJSONObject(mDpcc).GetValue<string>('declaration', '') <> '') then
  begin
    mHtml := DpccHoverHtml(TJSONObject(mDpcc));
  end
  else
  begin
    // Ohne dpcc-Teil: erste Zeile des Klartexts als Kopfzeile, der Rest als Summary, ohne Verweis.
    mLines := StringReplace(ContentsText(TJSONObject(AResult).GetValue('contents')), #13#10, #10,
      [rfReplaceAll]).Split([#10]);
    mCaption := '';
    mBody := '';
    for mIndex := 0 to High(mLines) do
    begin
      if mCaption = '' then
      begin
        mCaption := StripSemicolons(Trim(mLines[mIndex]));
      end
      else
      begin
        mBody := mBody + mLines[mIndex] + #10;
      end;
    end;
    mBody := Trim(mBody);
    if mBody <> '' then
    begin
      mBody := '<p>' + HtmlEscape(mBody) + '</p>' + cCrLf;
    end;
    mHtml := HoverHtml(mCaption, '', -1, mBody);
  end;
  Result := TJSONObject.Create;
  TJSONObject(Result).AddPair('contents', mHtml);
end;

class function TRadStudioDialect.SignatureAnswer(AResult: TJSONValue): TJSONValue;
var
  mSignatures, mNewSignatures, mNewParameters: TJSONArray;
  mSignature, mNewSignature, mNewParameter, mDoc: TJSONObject;
  mSignatureValue: TJSONValue;
  mLabel, mHtml: string;
  mHead: TRadRoutineHead;
  mLabels, mDocs: TArray<string>;
  mIndex: Integer;
begin
  if not (AResult is TJSONObject) or not TJSONObject(AResult).TryGetValue<TJSONArray>('signatures', mSignatures) then
  begin
    Exit(nil);
  end;
  Result := TJSONObject.Create;
  try
    mNewSignatures := TJSONArray.Create;
    TJSONObject(Result).AddPair('signatures', mNewSignatures);
    for mSignatureValue in mSignatures do
    begin
      if not (mSignatureValue is TJSONObject) then
      begin
        Continue;
      end;
      mSignature := TJSONObject(mSignatureValue);
      mLabel := mSignature.GetValue<string>('label', '');
      ServerParameters(mSignature, mLabel, mLabels, mDocs);
      if ParseRoutine(mLabel, mHead) then
      begin
        // Wie DelphiLSP: Gruppen aufgelöst, ohne ";" und Direktiven; Parameter einzeln mit Typ.
        mLabel := RoutineCaption(mHead, '');
        if Length(mHead.Parameters) > 0 then
        begin
          mLabels := mHead.Parameters;
        end;
      end;
      mNewSignature := TJSONObject.Create;
      mNewSignatures.AddElement(mNewSignature);
      mNewSignature.AddPair('label', mLabel);
      // Ohne documentation zeigt die IDE die Hilfe nicht an; der Wert ist doppelt maskiert wie bei DelphiLSP.
      mHtml := HoverHtml('', '', -1, SignatureBody(DocumentationText(mSignature.GetValue('documentation'))));
      mDoc := TJSONObject.Create;
      mDoc.AddPair('kind', 'html');
      mDoc.AddPair('value', JsonEscaped(mHtml));
      mNewSignature.AddPair('documentation', mDoc);
      mNewParameters := TJSONArray.Create;
      mNewSignature.AddPair('parameters', mNewParameters);
      for mIndex := 0 to High(mLabels) do
      begin
        mNewParameter := TJSONObject.Create;
        mNewParameters.AddElement(mNewParameter);
        mNewParameter.AddPair('label', mLabels[mIndex]);
        mDoc := TJSONObject.Create;
        mDoc.AddPair('kind', 'xml');
        if mIndex <= High(mDocs) then
        begin
          mDoc.AddPair('value', mDocs[mIndex]);
        end
        else
        begin
          mDoc.AddPair('value', '');
        end;
        mNewParameter.AddPair('documentation', mDoc);
      end;
    end;
    TJSONObject(Result).AddPair('activeSignature',
      TJSONNumber.Create(TJSONObject(AResult).GetValue<Integer>('activeSignature', 0)));
    TJSONObject(Result).AddPair('activeParameter',
      TJSONNumber.Create(TJSONObject(AResult).GetValue<Integer>('activeParameter', 0)));
  except
    Result.Free;
    raise;
  end;
end;

class function TRadStudioDialect.KibitzKindAt(const AText: string; ALine, ACharacter: Integer): Integer;
var
  mOffset, mIndex, mLine, mStart, mColumn: Integer;
  mInUses: Boolean;
  mWord: string;
begin
  // Stelle der Anfrage als Zahl der Zeichen davor; die Spalte höchstens bis zum Zeilenende.
  mIndex := 1;
  mLine := 0;
  while (mLine < ALine) and (mIndex <= Length(AText)) do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
    end;
    Inc(mIndex);
  end;
  mColumn := 0;
  while (mColumn < ACharacter) and (mIndex + mColumn <= Length(AText)) and
    not CharInSet(AText[mIndex + mColumn], [#13, #10]) do
  begin
    Inc(mColumn);
  end;
  mOffset := mIndex - 1 + mColumn;
  // uses-Klausel: seit dem letzten "uses" kein ";" (Kommentare und Zeichenketten übergangen).
  mInUses := False;
  mIndex := 1;
  while mIndex <= mOffset do
  begin
    case AText[mIndex] of
      '{':
        begin
          while (mIndex <= mOffset) and (AText[mIndex] <> '}') do
          begin
            Inc(mIndex);
          end;
        end;
      '(':
        begin
          if (mIndex < Length(AText)) and (AText[mIndex + 1] = '*') then
          begin
            Inc(mIndex, 2);
            while (mIndex < mOffset) and not ((AText[mIndex] = '*') and (AText[mIndex + 1] = ')')) do
            begin
              Inc(mIndex);
            end;
            Inc(mIndex);
          end;
        end;
      '/':
        begin
          if (mIndex < Length(AText)) and (AText[mIndex + 1] = '/') then
          begin
            while (mIndex <= mOffset) and (AText[mIndex] <> #10) do
            begin
              Inc(mIndex);
            end;
          end;
        end;
      '''':
        begin
          Inc(mIndex);
          while (mIndex <= mOffset) and (AText[mIndex] <> '''') do
          begin
            Inc(mIndex);
          end;
        end;
      ';':
        mInUses := False;
    else
      if IsIdentChar(AText[mIndex]) then
      begin
        mStart := mIndex;
        while (mIndex <= mOffset) and IsIdentChar(AText[mIndex]) do
        begin
          Inc(mIndex);
        end;
        mWord := Copy(AText, mStart, mIndex - mStart);
        if SameText(mWord, 'uses') then
        begin
          mInUses := True;
        end
        else if IndexText(mWord, cSectionWords) >= 0 then
        begin
          mInUses := False;
        end;
        Continue;
      end;
    end;
    Inc(mIndex);
  end;
  if mInUses then
  begin
    Exit(cKibitzUses);
  end;
  // Nach "X.": vor dem angefangenen Namen ein Punkt (nicht "..").
  mIndex := mOffset;
  while (mIndex >= 1) and IsIdentChar(AText[mIndex]) do
  begin
    Dec(mIndex);
  end;
  while (mIndex >= 1) and CharInSet(AText[mIndex], [' ', #9, #13, #10]) do
  begin
    Dec(mIndex);
  end;
  if (mIndex >= 1) and (AText[mIndex] = '.') and not ((mIndex >= 2) and (AText[mIndex - 1] = '.')) then
  begin
    Exit(cKibitzMember);
  end;
  Result := cKibitzScope;
end;

class function TRadStudioDialect.KindOf(const ASymbol: TIndexSymbol): Integer;
var
  mRest: string;
begin
  case ASymbol.Kind of
    TIndexSymbolKind.Field:
      Result := cRadKindField;
    TIndexSymbolKind.Variable:
      Result := cRadKindVariable;
    TIndexSymbolKind.Property_:
      Result := cRadKindProperty;
    TIndexSymbolKind.Method:
      Result := cRadKindMethod;
    TIndexSymbolKind.Constructor_:
      begin
        // Wie DelphiLSP: Destruktoren sind Methoden.
        if IsDestructor(ASymbol) then
        begin
          Result := cRadKindMethod;
        end
        else
        begin
          Result := cRadKindConstructor;
        end;
      end;
    TIndexSymbolKind.Routine:
      Result := cRadKindRoutine;
    TIndexSymbolKind.Constant:
      Result := cRadKindConstant;
    TIndexSymbolKind.EnumMember:
      Result := cRadKindEnumMember;
    TIndexSymbolKind.EnumType:
      Result := cRadKindEnum;
    TIndexSymbolKind.ClassType, TIndexSymbolKind.HelperType:
      Result := cRadKindClass;
    TIndexSymbolKind.RecordType, TIndexSymbolKind.ObjectType:
      Result := cRadKindRecord;
    TIndexSymbolKind.InterfaceType:
      Result := cRadKindInterface;
    TIndexSymbolKind.TypeAlias:
      begin
        mRest := TypeRhs(ASymbol.Signature);
        if StartsStr('^', mRest) then
        begin
          Result := cRadKindPointer;
        end
        else if StartsText('class of', mRest) then
        begin
          Result := cRadKindClass;
        end
        else if StartsText('reference to', mRest) then
        begin
          Result := cRadKindInterface;
        end
        else
        begin
          Result := cRadKindAlias;
        end;
      end;
  else
    Result := 1;
  end;
end;

/// <summary>AText ohne Hinweis-Direktiven am Ende (deprecated mit oder ohne Text, platform, experimental, library).
/// </summary>
function WithoutHintDirectives(const AText: string): string;
var
  mBefore: string;
begin
  Result := Trim(AText);
  repeat
    mBefore := Result;
    Result := Trim(TRegEx.Replace(Result, '\s+(deprecated(\s+''[^'']*'')?|platform|experimental|library)$', '',
      [roIgnoreCase]));
  until Result = mBefore;
end;

class function TRadStudioDialect.DetailOf(const ASymbol: TIndexSymbol): string;
begin
  Result := DetailWith(ASymbol, nil);
end;

class function TRadStudioDialect.DetailWith(const ASymbol: TIndexSymbol; const ASymbols: TArray<TIndexSymbol>): string;
var
  mRest, mFirst, mLast: string;
  mHead: TRadRoutineHead;
  mOrdinal, mClose: Integer;
begin
  case ASymbol.Kind of
    TIndexSymbolKind.Field, TIndexSymbolKind.Variable:
      Result := TypedDetail(SymbolTypeText(ASymbol));
    TIndexSymbolKind.Property_:
      begin
        mRest := AfterName(ASymbol.Signature, ASymbol.Name);
        mClose := Pos(']', mRest);
        if StartsStr('[', mRest) and (mClose > 0) then
        begin
          // Array-Property: ": [Index: Integer]: string;".
          Result := ': [' + string.Join('; ', ResolveParameters(Copy(mRest, 2, mClose - 2))) + ']' +
            TypedDetail(SymbolTypeText(ASymbol));
        end
        else
        begin
          Result := TypedDetail(SymbolTypeText(ASymbol));
        end;
      end;
    TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine:
      begin
        if ParseRoutine(ASymbol.Signature, mHead) then
        begin
          Result := RoutineDetail(mHead);
        end
        else
        begin
          mRest := AfterName(ASymbol.Signature, ASymbol.Name);
          Result := mRest + ';';
        end;
      end;
    TIndexSymbolKind.Constant:
      begin
        // Hinweis-Direktiven gehören nicht zum Wert (MaxListSize = MaxInt div 16 deprecated).
        mRest := WithoutHintDirectives(AfterName(ASymbol.Signature, ASymbol.Name));
        if mRest = '' then
        begin
          Result := ';';
        end
        else if StartsStr('=', mRest) then
        begin
          Result := ' ' + mRest + ';';
        end
        else
        begin
          Result := mRest + ';';
        end;
      end;
    TIndexSymbolKind.EnumMember:
      begin
        mOrdinal := EnumOrdinal(ASymbol, ASymbols);
        if (ASymbol.Container <> '') and (mOrdinal >= 0) then
        begin
          Result := ' = ' + ASymbol.Container + '(' + IntToStr(mOrdinal) + ');';
        end
        else
        begin
          Result := ';';
        end;
      end;
    TIndexSymbolKind.EnumType:
      begin
        if EnumBounds(ASymbol, ASymbols, mFirst, mLast) then
        begin
          Result := ': ' + mFirst + '..' + mLast + ';';
        end
        else
        begin
          Result := ';';
        end;
      end;
    TIndexSymbolKind.ClassType:
      begin
        mRest := TypeRhs(ASymbol.Signature);
        if mRest = '' then
        begin
          mRest := 'class';
        end;
        if StartsText('class', mRest) and (Pos('(', mRest) = 0) and not SameText(ASymbol.Name, 'TObject') then
        begin
          mRest := mRest + '(TObject)';
        end;
        Result := ': ' + mRest + ';';
      end;
    TIndexSymbolKind.InterfaceType:
      begin
        mRest := TypeRhs(ASymbol.Signature);
        if mRest = '' then
        begin
          mRest := 'interface';
        end;
        if SameText(mRest, 'interface') and not SameText(ASymbol.Name, 'IInterface') and
          not SameText(ASymbol.Name, 'IUnknown') then
        begin
          mRest := mRest + '(IInterface)';
        end;
        Result := ': ' + mRest + ';';
      end;
    TIndexSymbolKind.RecordType:
      Result := ': record;';
    TIndexSymbolKind.ObjectType:
      Result := ': object;';
    TIndexSymbolKind.HelperType, TIndexSymbolKind.TypeAlias:
      Result := TypedDetail(TypeRhs(ASymbol.Signature));
  else
    Result := '';
  end;
end;

class function TRadStudioDialect.DccFlagsOf(const ASymbol: TIndexSymbol; out AFlags: Int64): Boolean;
var
  mRest: string;
begin
  AFlags := 0;
  Result := True;
  case ASymbol.Kind of
    TIndexSymbolKind.Field:
      AFlags := $13;
    TIndexSymbolKind.Variable:
      begin
        if ASymbol.Container <> '' then
        begin
          AFlags := $13;
        end
        else
        begin
          AFlags := $3;
        end;
      end;
    TIndexSymbolKind.Property_:
      begin
        AFlags := $18;
        if WordPosTop(ASymbol.Signature, ['write']) > 0 then
        begin
          AFlags := AFlags or $4000;
        end
        else
        begin
          AFlags := AFlags or $8000;
        end;
        if StartsStr('[', AfterName(ASymbol.Signature, ASymbol.Name)) then
        begin
          AFlags := AFlags or $200000;
        end;
      end;
    TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine:
      begin
        if ASymbol.TypeName <> '' then
        begin
          AFlags := $35;
        end
        else
        begin
          AFlags := $34;
        end;
        if IsDestructor(ASymbol) then
        begin
          AFlags := AFlags or $40000;
        end
        else if ASymbol.Kind = TIndexSymbolKind.Constructor_ then
        begin
          AFlags := AFlags or $20000;
        end;
        if (ASymbol.Kind = TIndexSymbolKind.Routine) or StartsText('class ', TrimLeft(ASymbol.Signature)) then
        begin
          AFlags := AFlags or $800000;
        end;
        // Globale Routinen sind kein Mitglied (gemessen: 0x800024 bzw. 0x800025 ohne das Bit 0x10).
        if ASymbol.Kind = TIndexSymbolKind.Routine then
        begin
          AFlags := AFlags and not Int64($10);
        end;
        if ASymbol.IsVirtual or ASymbol.HasDirective('virtual') or ASymbol.HasDirective('override') or
          ASymbol.HasDirective('dynamic') then
        begin
          AFlags := AFlags or $200;
        end;
        if ASymbol.HasDirective('overload') then
        begin
          AFlags := AFlags or $4000000;
        end;
      end;
    TIndexSymbolKind.Constant:
      AFlags := $1;
    TIndexSymbolKind.EnumMember:
      AFlags := $11;
    TIndexSymbolKind.EnumType:
      AFlags := $2;
    TIndexSymbolKind.ClassType, TIndexSymbolKind.HelperType:
      AFlags := $E2;
    TIndexSymbolKind.RecordType, TIndexSymbolKind.ObjectType:
      AFlags := $62;
    TIndexSymbolKind.InterfaceType:
      AFlags := $80000E2;
    TIndexSymbolKind.TypeAlias:
      begin
        mRest := TypeRhs(ASymbol.Signature);
        if StartsText('class of', mRest) then
        begin
          AFlags := $E2;
        end
        else if StartsText('reference to', mRest) then
        begin
          AFlags := $C0000E2;
        end
        else
        begin
          AFlags := $2;
        end;
      end;
  else
    Exit(False);
  end;
  if ASymbol.HasDirective('deprecated') then
  begin
    AFlags := AFlags or $10000000;
  end;
  if ASymbol.Visibility in [TIndexVisibility.Protected, TIndexVisibility.StrictProtected] then
  begin
    AFlags := AFlags or $400;
  end
  else if ASymbol.Visibility in [TIndexVisibility.Private, TIndexVisibility.StrictPrivate] then
  begin
    AFlags := AFlags or $100;
  end;
end;

procedure TRadStudioDialect.RememberItems(AServerItems, ARadItems: TList<TJSONObject>);
var
  mIndex: Integer;
  mKey: string;
begin
  FLock.Enter;
  try
    FLastItems.Clear;
    FLastRadItems.Clear;
    for mIndex := 0 to ARadItems.Count - 1 do
    begin
      mKey := ARadItems[mIndex].GetValue<string>('sortText', '') + #1 + ARadItems[mIndex].GetValue<string>('label', '');
      FLastItems.AddOrSetValue(mKey, TJSONObject(AServerItems[mIndex].Clone));
      FLastRadItems.AddOrSetValue(mKey, TJSONObject(ARadItems[mIndex].Clone));
    end;
  finally
    FLock.Leave;
  end;
end;

function TRadStudioDialect.CompletionAnswer(AResult: TJSONValue; AKibitz: Integer): TJSONValue;
var
  mItems, mNewItems: TJSONArray;
  mItem: TJSONValue;
  mIncomplete: Boolean;
  mBuilder: TRadCompletionBuilder;
  mRadItems, mKeywords: TObjectList<TJSONObject>;
  mSources, mKeywordSources: TList<TJSONObject>;
  mIndex, mLast, mWidth: Integer;
begin
  mIncomplete := False;
  if AResult is TJSONArray then
  begin
    mItems := TJSONArray(AResult);
  end
  else if (AResult is TJSONObject) and TJSONObject(AResult).TryGetValue<TJSONArray>('items', mItems) then
  begin
    mIncomplete := TJSONObject(AResult).GetValue<Boolean>('isIncomplete', False);
  end
  else
  begin
    mItems := nil;
  end;
  Result := TJSONObject.Create;
  try
    TJSONObject(Result).AddPair('isIncomplete', TJSONBool.Create(mIncomplete));
    TJSONObject(Result).AddPair('kibitzkind', TJSONNumber.Create(AKibitz));
    mNewItems := TJSONArray.Create;
    TJSONObject(Result).AddPair('items', mNewItems);
    if mItems = nil then
    begin
      Exit;
    end;
    mBuilder := TRadCompletionBuilder.Create(FUnitSymbols, FTypeLookup);
    mRadItems := TObjectList<TJSONObject>.Create(True);
    mKeywords := TObjectList<TJSONObject>.Create(True);
    mSources := TList<TJSONObject>.Create;
    mKeywordSources := TList<TJSONObject>.Create;
    try
      for mItem in mItems do
      begin
        if not (mItem is TJSONObject) or NeedsEdits(TJSONObject(mItem)) or IsUnavailable(TJSONObject(mItem)) then
        begin
          Continue;
        end;
        mBuilder.Add(TJSONObject(mItem), mRadItems, mSources, mKeywords, mKeywordSources);
      end;
      // Laufende Nummer hexadezimal, so breit wie die des letzten Eintrags; Schlüsselwörter dahinter mit "k".
      mLast := mRadItems.Count - 1;
      if mLast < 0 then
      begin
        mLast := 0;
      end;
      mWidth := Length(IntToHex(mLast, 1));
      for mIndex := 0 to mRadItems.Count - 1 do
      begin
        mRadItems[mIndex].AddPair('sortText', IntToHex(mIndex, mWidth));
      end;
      for mIndex := 0 to mKeywords.Count - 1 do
      begin
        mKeywords[mIndex].AddPair('sortText', 'k' + IntToHex(mIndex, 3));
      end;
      for mIndex := 0 to mKeywords.Count - 1 do
      begin
        mRadItems.Add(mKeywords[mIndex]);
        mSources.Add(mKeywordSources[mIndex]);
      end;
      mKeywords.OwnsObjects := False;
      RememberItems(mSources, mRadItems);
      // Ab hier gehören die Einträge der Antwort.
      mRadItems.OwnsObjects := False;
      for mIndex := 0 to mRadItems.Count - 1 do
      begin
        mNewItems.AddElement(mRadItems[mIndex]);
      end;
    finally
      mKeywordSources.Free;
      mSources.Free;
      mKeywords.Free;
      mRadItems.Free;
      mBuilder.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function TRadStudioDialect.ResolveAnswer(AResult: TJSONValue; const AKey, AEcho: string): TJSONValue;
var
  mItem: TJSONObject;
  mEcho: TJSONValue;
  mName: string;
begin
  if AKey <> '' then
  begin
    FLock.Enter;
    try
      // Wie DelphiLSP: derselbe Eintrag wie in der Liste, ohne documentation.
      if FLastRadItems.TryGetValue(AKey, mItem) then
      begin
        Exit(TJSONObject(mItem.Clone));
      end;
    finally
      FLock.Leave;
    end;
  end;
  // Nicht (mehr) aus der letzten Liste (etwa nach einer weiteren Vervollständigung): der Eintrag, wie die IDE ihn
  // schickte – er hat schon die Form der Liste samt DCC_Flags; kind wieder als Zahl, ohne documentation.
  if AEcho <> '' then
  begin
    mEcho := TJSONObject.ParseJSONValue(AEcho);
    if mEcho is TJSONObject then
    begin
      mItem := TJSONObject.Create;
      for mName in TArray<string>.Create('label', 'kind', 'detail', 'DCC_Flags', 'sortText') do
      begin
        if TJSONObject(mEcho).GetValue(mName) <> nil then
        begin
          mItem.AddPair(mName, TJSONValue(TJSONObject(mEcho).GetValue(mName).Clone));
        end;
      end;
      mEcho.Free;
      NumberFromString(mItem, 'kind');
      Exit(mItem);
    end;
    mEcho.Free;
  end;
  if not (AResult is TJSONObject) then
  begin
    Exit(nil);
  end;
  // Ohne Eintrag der Liste: in ihrer Form, so weit der Eintrag des Servers reicht.
  mItem := TJSONObject.Create;
  mItem.AddPair('label', TJSONObject(AResult).GetValue<string>('label', ''));
  mItem.AddPair('kind', TJSONNumber.Create(TJSONObject(AResult).GetValue<Integer>('kind', 1)));
  mItem.AddPair('detail', TJSONObject(AResult).GetValue<string>('detail', ''));
  mItem.AddPair('sortText', TJSONObject(AResult).GetValue<string>('sortText', ''));
  Result := mItem;
end;

function TRadStudioDialect.IdeUri(const AUri: string): string;
var
  mKey: string;
begin
  mKey := TDocumentUris.Key(AUri);
  FLock.Enter;
  try
    if not FUris.TryGetValue(mKey, Result) then
    begin
      Result := AUri;
    end;
  finally
    FLock.Leave;
  end;
end;

function TRadStudioDialect.LocationAnswer(AResult: TJSONValue): TJSONValue;
var
  mFirst, mRange: TJSONValue;
  mLocation: TJSONObject;
  mUri: string;
begin
  mFirst := nil;
  if AResult is TJSONArray then
  begin
    if TJSONArray(AResult).Count = 0 then
    begin
      Exit(TJSONNull.Create);
    end;
    mFirst := TJSONArray(AResult).Items[0];
  end
  else if AResult is TJSONObject then
  begin
    mFirst := AResult;
  end;
  if not (mFirst is TJSONObject) then
  begin
    // null bleibt null.
    Exit(nil);
  end;
  mLocation := TJSONObject(mFirst);
  if mLocation.GetValue('targetUri') <> nil then
  begin
    // LocationLink: Ziel des Namens.
    mUri := mLocation.GetValue<string>('targetUri', '');
    mRange := mLocation.GetValue('targetSelectionRange');
    if mRange = nil then
    begin
      mRange := mLocation.GetValue('targetRange');
    end;
  end
  else
  begin
    mUri := mLocation.GetValue<string>('uri', '');
    mRange := mLocation.GetValue('range');
  end;
  if (mUri = '') or not (mRange is TJSONObject) then
  begin
    Exit(nil);
  end;
  Result := TJSONObject.Create;
  TJSONObject(Result).AddPair('uri', IdeUri(mUri));
  TJSONObject(Result).AddPair('range', TJSONObject(mRange.Clone));
end;

end.
