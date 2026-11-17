unit dpcc.Common.Lsp.SignatureHelp;

// Parameterhilfe (textDocument/signatureHelp): zeigt beim Aufruf alle Überladungen der Routine,
// hebt den aktiven Parameter hervor und übernimmt die ///-Dokumentation samt <param>-Texten
// (TXmlDoc mit <inheritdoc/>, #654).
// Der Aufruf wird an den Tokens vor dem Cursor erkannt: die innerste offene Klammer hinter
// einem Bezeichner; Kommas auf derselben Ebene zählen den aktiven Parameter.
// Überladungen nach Argumenttypen (#498): Jedes bisherige Argument bekommt einen Typ (Literale: Zeichen, String,
// Zahl, Boolean, nil, Menge; Bezeichner über die Namensauflösung, Aufzählungswerte über ihren Typ) und wird mit dem
// Parametertyp verglichen (TResolverText.ArgumentFits). Unbekannte Typen gelten als verträglich. Jede Signatur
// trägt das Ergebnis in data.fits und data.mismatch (erstes unverträgliches Argument, -1); vorgewählt wird die
// erste verträgliche mit genug Parametern.
// Formatroutinen (#451): Ist die Routine Format oder eine andere Formatroutine (Pascal.FormatRoutines, dazu eigene
// aus FormatRoutinesFor), steht unter "format" die Zuordnung Platzhalter → Argument (Lsp.SignatureFormat).
// Erweiterungen (L3):
// - Überladungen aus Vorfahren: Tragen alle Methoden des Typs overload (bzw. override), kommen die gleichnamigen
//   der Vorfahren dazu (TNameResolver.CallCandidates, nur die Kette des einen Typs); ohne overload verdeckt die
//   Ableitung sie wie beim Compiler.
// - Prozedurtypen: Variablen, Felder, Properties und Parameter eines Prozedurtyps (procedure … of object,
//   reference to, auch generisch wie TProc<Integer>) zeigen die Signatur des Typs mit eingesetzten Typargumenten.
// - Foo<Integer>(: Typargumente vor der Klammer wählen die generische Überladung und werden eingesetzt.
// - Index-Properties: Liste.Items[ und Liste[ (default-Property) zeigen die Indexparameter, wenn kein Aufruf die
//   Klammer umschließt; sonst gilt wie bisher der Aufruf.
// - Argumenttypen auch für Ausdrücke (Aufrufe, Index, Operatoren …) über TNameResolver.NodeType.
// Die Stelle ist dieselbe wie beim Parameter-Hint der IDE (Core: TDpccCallScanner); findet sie nichts (ein Array
// statt einer Index-Property), bleibt die Antwort leer.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Index.Contract,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Pascal.FormatRoutines,
  dpcc.Common.Lsp.SignatureFormat,
  dpcc.Common.Lsp.Hover;

type
  TCallSite = record
    /// <summary>Position des Routinennamens vor der Klammer.</summary>
    NamePosition: TTextPosition;
    /// <summary>Nullbasiert.</summary>
    ActiveParameter: Integer;
    Found: Boolean;
    /// <summary>Tokens der bisherigen Argumente (Index in ATree.Tokens, Last einschließlich), das gerade getippte
    /// eingeschlossen; First &gt; Last bei leerem Argument (#498).</summary>
    ArgumentFirst: TArray<Integer>;
    ArgumentLast: TArray<Integer>;
    /// <summary>Index des Namens in ATree.Tokens.</summary>
    NameIndex: Integer;
    /// <summary>Offset hinter dem aufgerufenen Ausdruck: hinter dem Namen bzw. hinter dem "&gt;" der Typargumente
    /// (L3).</summary>
    CalleeEnd: Integer;
    /// <summary>Index-Property: [ statt ( (L3).</summary>
    Bracket: Boolean;
    /// <summary>Typargumente vor der Klammer (Foo&lt;Integer&gt;(, L3); nil ohne.</summary>
    TypeArgs: TArray<string>;
  end;

  TSignatureParameter = record
    /// <summary>Bereich im Label der Signatur (Zeichen, nullbasiert, Ende exklusiv).</summary>
    StartIndex: Integer;
    EndIndex: Integer;
    Documentation: string;
    /// <summary>Typ hinter dem Doppelpunkt ohne Vorgabewert; '' bei untypisierten Parametern (#498).</summary>
    TypeName: string;
  end;

  TSignature = record
    Text: string;
    Documentation: string;
    Parameters: TArray<TSignatureParameter>;
    /// <summary>Kopf mit Typ-Präfix (procedure TFoo.Bar), also der Rumpf einer Methode.</summary>
    Qualified: Boolean;
    /// <summary>Alle bisherigen Argumente sind mit ihren Parametern verträglich (#498).</summary>
    Fits: Boolean;
    /// <summary>Erstes unverträgliches Argument, -1 ohne.</summary>
    Mismatch: Integer;
  end;

  TSignatureHelp = record
    Signatures: TArray<TSignature>;
    ActiveSignature: Integer;
    ActiveParameter: Integer;
    /// <summary>Signaturen aus der eingebauten Liste von System (#880), ohne Quelltext.</summary>
    Intrinsic: Boolean;
    /// <summary>Platzhalter einer Formatroutine (#451); Found = False sonst.</summary>
    Format: TSignatureFormat;
    function Found: Boolean;
  end;

  /// <summary>Eingaben der Parameterhilfe: Namensauflösung, Index, Dokument und Formatroutinen (#451).</summary>
  TSignatureHelpRequest = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    Tree: TSyntaxTree;
    TreeText: string;
    FileName: string;
    ReadText: THoverReadText;
    /// <summary>Formatroutinen (#451); Create setzt die eingebauten.</summary>
    Routines: TArray<TFormatRoutine>;
    class function Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const ATreeText, AFileName: string; const AReadText: THoverReadText): TSignatureHelpRequest; static;
  end;

  /// <summary>Formatroutinen für das Dokument AUri: eingebaute und eigene (#451).</summary>
  TFormatRoutinesFunc = reference to function(const AUri: string): TArray<TFormatRoutine>;

  TLspSignatureHelp = class
  public const
    cMethod = 'textDocument/signatureHelp';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: THoverReadText;
    FNamespaces: TArray<string>;
    FFormatRoutinesFor: TFormatRoutinesFunc;
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt: Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: THoverReadText;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AReadText: THoverReadText); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>signatureHelpProvider mit ( und , als Auslöser.</summary>
    class function Capability: TJSONObject; static;
    /// <summary>Innerster offener Aufruf vor APosition: Klammer ( hinter einem Bezeichner. Index-Properties und
    /// Typargumente vor der Klammer erkennt nur HelpAt (L3); hier bleibt es beim bisherigen Verhalten für die
    /// Vervollständigung.</summary>
    class function CallSiteAt(ATree: TSyntaxTree; const APosition: TTextPosition): TCallSite; static;
    /// <summary>Typ des Arguments aus ATokens[AFirst..ALast] (#498): Char, string, Integer, Double, Boolean, nil,
    /// [] oder der Typ eines Bezeichners; sonst der Typ des Ausdrucks, den die Namensauflösung liefert
    /// (TNameResolver.NodeType, L3); '' wenn unbekannt oder ohne AResolver.</summary>
    class function ArgumentType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      AFirst, ALast: Integer): string; static;
    /// <summary>Setzt Fits und Mismatch von ASignature für AArgumentTypes.</summary>
    class procedure Match(var ASignature: TSignature; const AArgumentTypes: TArray<string>); static;
    /// <summary>Kopf einer Routine ab ALine/AColumn bis zum ; hinter der Parameterliste, auf eine Zeile
    /// gebracht.</summary>
    class function ParseSignature(const ALines: TArray<string>; ALine, AColumn: Integer): TSignature; static;
    /// <summary>Signaturen des Aufrufs an APosition im Dokument von ARequest.</summary>
    class function HelpAt(const ARequest: TSignatureHelpRequest; const APosition: TTextPosition): TSignatureHelp;
      static;
    /// <summary>SignatureHelp des LSP; JSON-null ohne Signaturen. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AHelp: TSignatureHelp): TJSONValue; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Formatroutinen je Dokument (#451); ohne gelten die eingebauten.</summary>
    property FormatRoutinesFor: TFormatRoutinesFunc read FFormatRoutinesFor write FFormatRoutinesFor;
  end;

implementation

uses
  dpcc.Common.Lsp.Internals.Namespaces,
  dpcc.Common.Index.Files,
  System.Math,
  System.StrUtils,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Lsp.Positions,
  dpcc.Common.Pascal.Contract,
  dpcc.Common.Pascal.TreeCache,
  dpcc.Common.Index.Extractor,
  dpcc.Common.Pascal.XmlDoc,
  dpcc.Common.Semantics.SystemIntrinsics,
  dpcc.Common.Semantics.Attributes,
  dpcc.Common.Lsp.Documentation,
  dpcc.Common.Lsp.Internals.Cancellation,
  dpcc.Common.Editing.InterfaceStubs,
  dpcc.Text.Lines,
  dpcc.Common.Localization.Texts;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TSignatureHelpText = (FieldsTextDocumentUriAndPosition);

const
  cTexts: array[TSignatureHelpText] of TDpccText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen'; En: 'Fields "textDocument.uri" and "position" missing'));

const
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  cMaxHeaderLines = 50;
  cParameterModifiers: array[0..4] of string = ('const ', 'var ', 'out ', 'constref ', '[ref] ');
  /// <summary>Schlüsselwörter, an denen die Suche nach der offenen Klammer endet.</summary>
  cStatementKeywords: array[0..4] of string = ('begin', 'end', 'then', 'do', 'var');
  /// <summary>Zeichen hinter einem Parameternamen in seiner Gruppe.</summary>
  cNameEnds: array[0..2] of string = (':', ' ', ',');
  /// <summary>LiteralChars: kein Zeichen- oder String-Literal.</summary>
  cNoLiteral = -2;
  /// <summary>So viele Tokens zwischen &lt; und &gt; der Typargumente vor einer Klammer höchstens (L3).</summary>
  cMaxTypeArgTokens = 64;
  /// <summary>Ausdrücke, deren Typ ein Argument haben kann (ArgumentType, L3).</summary>
  cValueKinds = [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.AddressOf, TSyntaxKind.SetConstructor,
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.InheritedExpr,
    TSyntaxKind.AnonymousMethod, TSyntaxKind.IfExpr];
  /// <summary>Zugriffe hinter dem Kopf einer Property, die nicht ins Label gehören.</summary>
  cPropertyAccessors: array[0..1] of string = (' read ', ' write ');

type
  /// <summary>Rückwärtssuche nach der innersten offenen Aufrufklammer (CallSiteAt); sammelt die Argumente
  /// (#498).</summary>
  TCallScan = record
    Tokens: TArray<TPascalToken>;
    /// <summary>Letztes Token vor der Position.</summary>
    Last: Integer;
    Depth: Integer;
    Commas: Integer;
    /// <summary>Letztes Token des Arguments links vom nächsten Komma.</summary>
    SpanEnd: Integer;
    Firsts: TArray<Integer>;
    Lasts: TArray<Integer>;
    /// <summary>Auch Index-Properties (Name[) und Typargumente vor der Klammer (Foo&lt;Integer&gt;(), L3.</summary>
    Extended: Boolean;
    /// <summary>Innerste Index-Property (L3); gilt nur, wenn kein Aufruf sie umschließt.</summary>
    Pending: TCallSite;
    procedure AddArgument(AFirst: Integer);
    /// <summary>Füllt ASite für die Klammer an AIndex mit dem Namen an AName; APrevious: Token vor der Klammer.
    /// </summary>
    procedure FillSite(AIndex, AName, APrevious: Integer; const ATypeArgs: TArray<string>; var ASite: TCallSite);
    /// <summary>Name vor den Typargumenten, deren "&gt;" an AClose steht; -1, wenn davor keine Typargumente
    /// stehen. ATypeArgs: die Argumente als Text.</summary>
    function GenericName(AClose: Integer; out ATypeArgs: TArray<string>): Integer;
    function Opening(AIndex: Integer; var ASite: TCallSite): Boolean;
    function Separator(AIndex: Integer): Boolean;
    /// <summary>Verarbeitet das Token AIndex; True beendet die Suche.</summary>
    function Step(AIndex: Integer; var ASite: TCallSite): Boolean;
  end;

  /// <summary>Ein Lauf von HelpAt: Aufruf finden, Überladungen sammeln, Argumente vergleichen.</summary>
  THelpRun = class
  private
    FRequest: TSignatureHelpRequest;
    FPosition: TTextPosition;
    FSite: TCallSite;
    FResolved: TResolvedSymbol;
    FStarts: TArray<TTextPosition>;
    FStartSymbols: TArray<TResolvedSymbol>;
    /// <summary>Gebundene Typparameter je Anfang (Name=Typ): die des umgebenden Typs bzw. Prozedurtyps, dazu
    /// Typargumente vor der Klammer.</summary>
    FStartBindings: TArray<TArray<string>>;
    /// <summary>Gelesene Dateien des Laufs: Name, Zeilen, lesbar.</summary>
    FFiles: TArray<string>;
    FFileLines: TArray<TArray<string>>;
    FFileFound: TArray<Boolean>;
    /// <summary>Signatur aus einem Prozedurtyp (L3): Kopf ohne Typ-Präfix-Prüfung.</summary>
    FProcedural: Boolean;
    /// <summary>Konstruktor einer Attributklasse statt des Namens (#465).</summary>
    FAttribute: Boolean;
    procedure ResolveSite;
    function IntrinsicHelp: TSignatureHelp;
    function LinesOf(const AFileName: string; out ALines: TArray<string>): Boolean;
    procedure AddStart(const APosition: TTextPosition; const ASymbol: TResolvedSymbol;
      const ABindings: TArray<string>);
    function IsOverload(const ASymbol: TIndexSymbol): Boolean;
    function OwnerUnit(out AOwner: TUnitIndex): Boolean;
    function CollectUnitStarts: Boolean;
    function InheritedCall: Boolean;
    procedure AddInheritedStarts;
    procedure OrderByContainer(const AOrder: TArray<string>);
    procedure KeepGenericStarts;
    function CollectStarts: Boolean;
    function ProceduralType(out AType: TResolvedSymbol): Boolean;
    function IndexedProperty(out AProperty: TResolvedSymbol): Boolean;
    function BoundTypes(const ABindings: TArray<string>): TArray<string>;
    function HeaderLines(const ALines: TArray<string>; const AStart: TTextPosition;
      const ABindings: TArray<string>): TArray<string>;
    function ParseText(const ALines: TArray<string>; ALine, AColumn: Integer): TSignature;
    function IndexSignature(AIndex: Integer): TSignature;
    function Signatures: TArray<TSignature>;
    procedure MatchArguments(var ASignatures: TArray<TSignature>);
    procedure AddFormat(var AHelp: TSignatureHelp);
    function SiteHelp: TSignatureHelp;
  public
    constructor Create(const ARequest: TSignatureHelpRequest; const APosition: TTextPosition);
    function Run: TSignatureHelp;
  end;

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

function CollapseSpaces(const AText: string): string;
var
  mIndex: Integer;
  mSpace: Boolean;
begin
  Result := '';
  mSpace := False;
  for mIndex := 1 to Length(AText) do
  begin
    if CharInSet(AText[mIndex], [' ', #9, #10, #13]) then
    begin
      mSpace := Result <> '';
    end
    else
    begin
      if mSpace then
      begin
        Result := Result + ' ';
      end;
      mSpace := False;
      Result := Result + AText[mIndex];
    end;
  end;
end;

function IsSkipped(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Index des nächsten Tokens vor AIndex, das kein Kommentar und keine Direktive ist; -1 ohne.</summary>
function PreviousCodeToken(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsSkipped(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Letztes Token, das vor APosition beginnt; -1 ohne.</summary>
function LastTokenBefore(const ATokens: TArray<TPascalToken>; const APosition: TTextPosition): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ATokens) do
  begin
    if ComparePositions(ATokens[mIndex].StartPos, APosition) >= 0 then
    begin
      Break;
    end;
    Result := mIndex;
  end;
end;

/// <summary>; oder ein Schlüsselwort, hinter dem kein offener Aufruf mehr stehen kann.</summary>
function EndsStatement(const AToken: TPascalToken): Boolean;
var
  mKeyword: string;
begin
  Result := AToken.IsSymbol(';');
  for mKeyword in cStatementKeywords do
  begin
    Result := Result or AToken.IsKeyword(mKeyword);
  end;
end;

{ TCallScan }

procedure TCallScan.AddArgument(AFirst: Integer);
begin
  Firsts := TArray<Integer>.Create(AFirst) + Firsts;
  Lasts := TArray<Integer>.Create(SpanEnd) + Lasts;
end;

function TCallScan.GenericName(AClose: Integer; out ATypeArgs: TArray<string>): Integer;
var
  mIndex, mDepth, mCount: Integer;
  mToken: TPascalToken;
  mArgument: string;
begin
  // Rückwärts von ">" bis zum passenden "<": nur Bezeichner, Punkte, Kommas, string und verschachtelte <>,
  // wie TExpressionParser.LooksLikeGenericArgs vorwärts.
  Result := -1;
  ATypeArgs := nil;
  mDepth := 0;
  mCount := 0;
  mArgument := '';
  mIndex := AClose;
  while (mIndex >= 0) and (mCount < cMaxTypeArgTokens) do
  begin
    mToken := Tokens[mIndex];
    if IsSkipped(mToken) then
    begin
      Dec(mIndex);
      Continue;
    end;
    if mToken.IsSymbol('>') then
    begin
      Inc(mDepth);
      if mDepth > 1 then
      begin
        mArgument := mToken.Text + mArgument;
      end;
    end
    else if mToken.IsSymbol('<') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        ATypeArgs := TArray<string>.Create(Trim(mArgument)) + ATypeArgs;
        Result := PreviousCodeToken(Tokens, mIndex);
        if (Result < 0) or (Tokens[Result].Kind <> TPascalTokenKind.Identifier) then
        begin
          Result := -1;
          ATypeArgs := nil;
        end;
        Exit;
      end;
      mArgument := mToken.Text + mArgument;
    end
    else if mToken.IsSymbol(',') and (mDepth = 1) then
    begin
      ATypeArgs := TArray<string>.Create(Trim(mArgument)) + ATypeArgs;
      mArgument := '';
    end
    else if mToken.IsSymbol(',') then
    begin
      mArgument := ', ' + mArgument;
    end
    else if (mToken.Kind = TPascalTokenKind.Identifier) or mToken.IsSymbol('.') or mToken.IsKeyword('string') then
    begin
      mArgument := mToken.Text + mArgument;
    end
    else
    begin
      Break;
    end;
    Dec(mIndex);
    Inc(mCount);
  end;
  ATypeArgs := nil;
end;

procedure TCallScan.FillSite(AIndex, AName, APrevious: Integer; const ATypeArgs: TArray<string>;
  var ASite: TCallSite);
begin
  AddArgument(AIndex + 1);
  ASite.NamePosition := Tokens[AName].StartPos;
  ASite.NameIndex := AName;
  ASite.CalleeEnd := Tokens[APrevious].Offset + Length(Tokens[APrevious].Text);
  ASite.Bracket := not Tokens[AIndex].IsSymbol('(');
  ASite.TypeArgs := ATypeArgs;
  ASite.ActiveParameter := Commas;
  ASite.Found := True;
  ASite.ArgumentFirst := Firsts;
  ASite.ArgumentLast := Lasts;
end;

function TCallScan.Opening(AIndex: Integer; var ASite: TCallSite): Boolean;
var
  mPrevious, mName: Integer;
  mTypeArgs: TArray<string>;
  mIdentifier: Boolean;
begin
  Result := False;
  if Depth > 0 then
  begin
    Dec(Depth);
    Exit;
  end;
  mPrevious := PreviousCodeToken(Tokens, AIndex);
  mIdentifier := (mPrevious >= 0) and (Tokens[mPrevious].Kind = TPascalTokenKind.Identifier);
  mName := -1;
  mTypeArgs := nil;
  if mIdentifier and Tokens[AIndex].IsSymbol('(') then
  begin
    mName := mPrevious;
  end
  else if Extended and Tokens[AIndex].IsSymbol('(') and (mPrevious >= 0) and Tokens[mPrevious].IsSymbol('>') then
  begin
    // Foo<Integer>( (L3).
    mName := GenericName(mPrevious, mTypeArgs);
  end
  else if Extended and mIdentifier and not Pending.Found then
  begin
    // Index-Property Liste[ (L3): nur, wenn kein Aufruf sie umschließt, wie beim Parameter-Hint der IDE
    // (TDpccCallScanner). Weiter nach außen suchen; die Klammer zählt dort als Teil eines Arguments.
    FillSite(AIndex, mPrevious, mPrevious, nil, Pending);
  end;
  if mName >= 0 then
  begin
    FillSite(AIndex, mName, mPrevious, mTypeArgs, ASite);
    Exit(True);
  end;
  // Klammer um einen Ausdruck oder eine Menge: sie ist selbst ein Argument des äußeren Aufrufs.
  Commas := 0;
  Firsts := nil;
  Lasts := nil;
  SpanEnd := Last;
end;

function TCallScan.Separator(AIndex: Integer): Boolean;
begin
  Result := False;
  if Tokens[AIndex].IsSymbol(',') then
  begin
    Inc(Commas);
    AddArgument(AIndex + 1);
    SpanEnd := AIndex - 1;
  end
  else
  begin
    Result := EndsStatement(Tokens[AIndex]);
  end;
end;

function TCallScan.Step(AIndex: Integer; var ASite: TCallSite): Boolean;
var
  mToken: TPascalToken;
begin
  Result := False;
  mToken := Tokens[AIndex];
  if IsSkipped(mToken) then
  begin
    Exit;
  end;
  if mToken.IsSymbol(')') or mToken.IsSymbol(']') then
  begin
    Inc(Depth);
  end
  else if mToken.IsSymbol('(') or mToken.IsSymbol('[') then
  begin
    Result := Opening(AIndex, ASite);
  end
  else if Depth = 0 then
  begin
    Result := Separator(AIndex);
  end;
end;

/// <summary>Innerster offener Aufruf vor APosition; AExtended: auch Index-Properties und Typargumente vor der
/// Klammer (L3).</summary>
function ScanCallSite(ATree: TSyntaxTree; const APosition: TTextPosition; AExtended: Boolean): TCallSite;
var
  mScan: TCallScan;
  mIndex: Integer;
begin
  Result := Default(TCallSite);
  if ATree = nil then
  begin
    Exit;
  end;
  mScan := Default(TCallScan);
  mScan.Tokens := ATree.Tokens;
  mScan.Extended := AExtended;
  mScan.Last := LastTokenBefore(mScan.Tokens, APosition);
  // Argumente rückwärts gesammelt (#498).
  mScan.SpanEnd := mScan.Last;
  for mIndex := mScan.Last downto 0 do
  begin
    if mScan.Step(mIndex, Result) then
    begin
      Break;
    end;
  end;
  // Kein Aufruf um die Index-Property: sie selbst (L3).
  if not Result.Found and mScan.Pending.Found then
  begin
    Result := mScan.Pending;
  end;
end;

/// <summary>Umfasst ANode den Bereich AStart..AEnd? Knoten ohne Bereich (unvollständiger Code) gelten als
/// umfassend.</summary>
function NodeAround(ANode: TSyntaxNode; AStart, AEnd: Integer): Boolean;
begin
  Result := (ANode.EndOffset <= ANode.StartOffset) or ((ANode.StartOffset <= AStart) and (ANode.EndOffset >= AEnd));
end;

/// <summary>Äußerster Bezeichner bzw. Mitgliedszugriff, der an AEnd endet: der aufgerufene Ausdruck (L3); nil
/// ohne.</summary>
function CalleeNode(ATree: TSyntaxTree; AEnd: Integer): TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) or (AEnd <= 0) then
  begin
    Exit;
  end;
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and (ANode.EndOffset = AEnd) then
      begin
        Result := TSyntaxSearchStep.Found;
      end
      else if NodeAround(ANode, AEnd - 1, AEnd) then
      begin
        Result := TSyntaxSearchStep.Descend;
      end
      else
      begin
        Result := TSyntaxSearchStep.Skip;
      end;
    end);
end;

/// <summary>Indexzugriff, dessen Basis an AEnd endet (Liste[, L3); nil ohne.</summary>
function IndexNode(ATree: TSyntaxTree; AEnd: Integer): TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) or (AEnd <= 0) then
  begin
    Exit;
  end;
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if (ANode.Kind = TSyntaxKind.IndexAccess) and (ANode.ChildCount > 0) and (ANode[0].EndOffset = AEnd) then
      begin
        Result := TSyntaxSearchStep.Found;
      end
      else if NodeAround(ANode, AEnd - 1, AEnd) then
      begin
        Result := TSyntaxSearchStep.Descend;
      end
      else
      begin
        Result := TSyntaxSearchStep.Skip;
      end;
    end);
end;

/// <summary>Äußerster Ausdruck, der genau von AStart bis AEnd reicht (ein Argument, L3); nil ohne.</summary>
function SpanNode(ATree: TSyntaxTree; AStart, AEnd: Integer): TSyntaxNode;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) or (AEnd <= AStart) then
  begin
    Exit;
  end;
  Result := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if (ANode.Kind in cValueKinds) and (ANode.StartOffset = AStart) and (ANode.EndOffset = AEnd) then
      begin
        Result := TSyntaxSearchStep.Found;
      end
      else if NodeAround(ANode, AStart, AEnd) then
      begin
        Result := TSyntaxSearchStep.Descend;
      end
      else
      begin
        Result := TSyntaxSearchStep.Skip;
      end;
    end);
end;

{ TSignatureHelpRequest }

class function TSignatureHelpRequest.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const ATreeText, AFileName: string; const AReadText: THoverReadText): TSignatureHelpRequest;
begin
  Result := Default(TSignatureHelpRequest);
  Result.Resolver := AResolver;
  Result.Index := AIndex;
  Result.Tree := ATree;
  Result.TreeText := ATreeText;
  Result.FileName := AFileName;
  Result.ReadText := AReadText;
  Result.Routines := TFormatRoutines.Defaults;
end;

{ TSignatureHelp }

function TSignatureHelp.Found: Boolean;
begin
  Result := Length(Signatures) > 0;
end;

{ TLspSignatureHelp }

function TLspSignatureHelp.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspSignatureHelp.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspSignatureHelp.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText);
begin
  Create(AStore, AIndex, AReadText, nil);
end;

constructor TLspSignatureHelp.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspSignatureHelp.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod, Handle);
end;

class function TLspSignatureHelp.Capability: TJSONObject;
var
  mTriggers, mRetriggers: TJSONArray;
begin
  mTriggers := TJSONArray.Create;
  mTriggers.Add('(');
  mTriggers.Add(',');
  mRetriggers := TJSONArray.Create;
  mRetriggers.Add(')');
  Result := TJSONObject.Create;
  Result.AddPair('triggerCharacters', mTriggers);
  Result.AddPair('retriggerCharacters', mRetriggers);
end;

class function TLspSignatureHelp.CallSiteAt(ATree: TSyntaxTree; const APosition: TTextPosition): TCallSite;
begin
  Result := ScanCallSite(ATree, APosition, False);
end;

/// <summary>Position des ; außerhalb von runden und eckigen Klammern in AText, 0 ohne; ADepth zählt offene Klammern
/// über die Zeilen hinweg. Eckige zählen für Index-Properties mit mehreren Gruppen (L3).</summary>
function HeaderEnd(const AText: string; var ADepth: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 1 to Length(AText) do
  begin
    case AText[mIndex] of
      '(', '[': Inc(ADepth);
      ')', ']': Dec(ADepth);
      ';':
        if ADepth = 0 then
        begin
          Exit(mIndex);
        end;
    end;
  end;
end;

/// <summary>Kopf ab ALine/AColumn bis zum ; außerhalb von Klammern, Zeilen mit Leerzeichen verbunden.</summary>
function CollectHeader(const ALines: TArray<string>; ALine, AColumn: Integer): string;
var
  mDepth, mLine, mEnd: Integer;
  mText: string;
begin
  Result := '';
  mDepth := 0;
  mLine := ALine;
  while (mLine <= High(ALines)) and (mLine < ALine + cMaxHeaderLines) do
  begin
    mText := ALines[mLine];
    if mLine = ALine then
    begin
      mText := Copy(mText, AColumn + 1, MaxInt);
    end;
    mEnd := HeaderEnd(mText, mDepth);
    if mEnd > 0 then
    begin
      Exit(Result + Copy(mText, 1, mEnd - 1));
    end;
    Result := Result + mText + ' ';
    Inc(mLine);
  end;
end;

/// <summary>procedure TFoo.Bar → procedure Bar; True, wenn ein Typ-Präfix entfernt wurde.</summary>
function StripQualifier(var AText: string): Boolean;
var
  mKeyword, mOpen, mDot: Integer;
begin
  Result := False;
  mKeyword := Pos(' ', AText);
  if mKeyword = 0 then
  begin
    Exit;
  end;
  mOpen := Pos('(', AText);
  if mOpen > 0 then
  begin
    mDot := LastDelimiter('.', Copy(AText, 1, mOpen - 1));
  end
  else
  begin
    mDot := LastDelimiter('.', AText);
  end;
  Result := mDot > mKeyword;
  if Result then
  begin
    Delete(AText, mKeyword + 1, mDot - mKeyword);
  end;
end;

/// <summary>Position der Klammer AClose, die die Klammer AOpenChar an AOpen schließt; 0 ohne.</summary>
function ClosingBracket(const AText: string; AOpen: Integer; AOpenChar, ACloseChar: Char): Integer;
var
  mIndex, mDepth: Integer;
begin
  Result := 0;
  mDepth := 0;
  for mIndex := AOpen to Length(AText) do
  begin
    if AText[mIndex] = AOpenChar then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = ACloseChar then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(mIndex);
      end;
    end;
  end;
end;

/// <summary>Typ hinter dem Doppelpunkt ohne Vorgabewert und ohne Unit davor (System.Boolean → Boolean, #498);
/// '' bei untypisierten Parametern.</summary>
function GroupType(const AGroupText: string): string;
var
  mColon, mEqual: Integer;
begin
  Result := '';
  mColon := Pos(':', AGroupText);
  if mColon = 0 then
  begin
    Exit;
  end;
  Result := Copy(AGroupText, mColon + 1, MaxInt);
  mEqual := Pos('=', Result);
  if mEqual > 0 then
  begin
    Result := Copy(Result, 1, mEqual - 1);
  end;
  Result := Trim(Result);
  if (Pos('<', Result) = 0) and (Pos(' ', Result) = 0) and (LastDelimiter('.', Result) > 0) then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
end;

/// <summary>Namen vor dem Doppelpunkt ohne const/var/out/constref/[ref].</summary>
function GroupNames(const AGroupText: string): string;
var
  mColon: Integer;
  mModifier: string;
begin
  mColon := Pos(':', AGroupText);
  if mColon = 0 then
  begin
    Result := AGroupText;
  end
  else
  begin
    Result := Copy(AGroupText, 1, mColon - 1);
  end;
  for mModifier in cParameterModifiers do
  begin
    if StartsText(mModifier, Result) then
    begin
      Delete(Result, 1, Length(mModifier));
    end;
  end;
end;

function NewParameter(AStart, AEnd: Integer; const ATypeName: string): TSignatureParameter;
begin
  Result := Default(TSignatureParameter);
  Result.StartIndex := AStart;
  Result.EndIndex := AEnd;
  Result.TypeName := ATypeName;
end;

/// <summary>Parameter der Gruppe AText[AFrom..ATo) (1-basiert, ATo exklusiv). A, B: Integer gibt je Name einen
/// Parameter, hervorgehoben wird nur der Name.</summary>
function GroupParameters(const AText: string; AFrom, ATo: Integer): TArray<TSignatureParameter>;
var
  mGroup, mNames, mTypeName, mItem: string;
  mFrom, mOffset, mSearch: Integer;
begin
  Result := nil;
  mGroup := Copy(AText, AFrom, ATo - AFrom);
  mFrom := AFrom + Length(mGroup) - Length(TrimLeft(mGroup));
  mGroup := Trim(mGroup);
  if mGroup = '' then
  begin
    Exit;
  end;
  mTypeName := GroupType(mGroup);
  mNames := GroupNames(mGroup);
  if Pos(',', mNames) = 0 then
  begin
    Result := TArray<TSignatureParameter>.Create(NewParameter(mFrom - 1, mFrom - 1 + Length(mGroup), mTypeName));
    Exit;
  end;
  mSearch := mFrom;
  for mItem in mNames.Split([',']) do
  begin
    mOffset := PosEx(Trim(mItem), AText, mSearch);
    Result := Result + [NewParameter(mOffset - 1, mOffset - 1 + Length(Trim(mItem)), mTypeName)];
    mSearch := mOffset + Length(Trim(mItem));
  end;
end;

/// <summary>Parameter zwischen den Klammern an AOpen und AClose, Gruppen durch ; getrennt.</summary>
function ParameterGroups(const AText: string; AOpen, AClose: Integer): TArray<TSignatureParameter>;
var
  mIndex, mStart, mDepth: Integer;
begin
  Result := nil;
  mStart := AOpen + 1;
  mDepth := 0;
  for mIndex := AOpen + 1 to AClose do
  begin
    if (mIndex = AClose) or (AText[mIndex] = ';') and (mDepth = 0) then
    begin
      Result := Result + GroupParameters(AText, mStart, mIndex);
      mStart := mIndex + 1;
    end
    else if AText[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = ')' then
    begin
      Dec(mDepth);
    end;
  end;
end;

/// <summary>AText ohne read/write hinter der Position AFrom (Kopf einer Index-Property, L3).</summary>
function WithoutAccessors(const AText: string; AFrom: Integer): string;
var
  mLower, mAccessor: string;
  mAt, mCut: Integer;
begin
  mLower := LowerCase(AText);
  mCut := Length(AText) + 1;
  for mAccessor in cPropertyAccessors do
  begin
    mAt := PosEx(mAccessor, mLower, AFrom);
    if (mAt > 0) and (mAt < mCut) then
    begin
      mCut := mAt;
    end;
  end;
  Result := Copy(AText, 1, mCut - 1);
end;

/// <summary>Kopf ab ALine/AColumn auf eine Zeile gebracht, Parameter zwischen AOpenChar und ACloseChar; AStrip
/// entfernt ein Typ-Präfix (procedure TFoo.Bar). Bei [ ] (Index-Property) ohne read/write (L3).</summary>
function ParseHeader(const ALines: TArray<string>; ALine, AColumn: Integer; AOpenChar, ACloseChar: Char;
  AStrip: Boolean): TSignature;
var
  mText: string;
  mOpen, mClose: Integer;
begin
  Result := Default(TSignature);
  Result.Fits := True;
  Result.Mismatch := -1;
  mText := CollapseSpaces(CollectHeader(ALines, ALine, AColumn));
  if AStrip then
  begin
    Result.Qualified := StripQualifier(mText);
  end;
  mOpen := Pos(AOpenChar, mText);
  mClose := 0;
  if mOpen > 0 then
  begin
    mClose := ClosingBracket(mText, mOpen, AOpenChar, ACloseChar);
  end;
  if (mClose > 0) and (AOpenChar = '[') then
  begin
    mText := WithoutAccessors(mText, mClose);
  end;
  Result.Text := mText;
  if mClose > 0 then
  begin
    Result.Parameters := ParameterGroups(mText, mOpen, mClose);
  end;
end;

class function TLspSignatureHelp.ParseSignature(const ALines: TArray<string>; ALine, AColumn: Integer): TSignature;
begin
  Result := ParseHeader(ALines, ALine, AColumn, '(', ')', True);
end;

/// <summary>Name ohne Unit bzw. umgebenden Typ davor (System.Boolean → Boolean); Generics bleiben.</summary>
function LastPart(const AName: string): string;
begin
  if Pos('<', AName) > 0 then
  begin
    Result := AName;
  end
  else
  begin
    Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
  end;
end;

/// <summary>Zeichen in einem String-Literal ('it''s' = 4); -1 bei mehrzeiligen.</summary>
function LiteralLength(const AText: string): Integer;
begin
  if StartsStr('''''''', AText) then
  begin
    Exit(-1);
  end;
  Result := Length(StringReplace(Copy(AText, 2, Length(AText) - 2), '''''', '''', [rfReplaceAll]));
end;

/// <summary>Tokens ATokens[AFirst..ALast] ohne Kommentare und Direktiven.</summary>
function CodeTokens(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer): TArray<TPascalToken>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := Max(AFirst, 0) to Min(ALast, High(ATokens)) do
  begin
    if not IsSkipped(ATokens[mIndex]) then
    begin
      Result := Result + [ATokens[mIndex]];
    end;
  end;
end;

/// <summary>Zeichen im Literal AToken; -1 bei mehrzeiligen Strings, cNoLiteral bei anderen Tokens.</summary>
function LiteralChars(const AToken: TPascalToken): Integer;
begin
  if AToken.Kind = TPascalTokenKind.StringLiteral then
  begin
    Result := LiteralLength(AToken.Text);
  end
  else if AToken.Kind = TPascalTokenKind.CharLiteral then
  begin
    Result := 1;
  end
  else
  begin
    Result := cNoLiteral;
  end;
end;

/// <summary>Zeichen und Strings, auch zusammengesetzt wie 'a'#13'b'; True, wenn AParts so bestimmt ist. Ein offenes
/// Literal wird noch getippt: True mit AType = ''.</summary>
function TextLiteralType(const AParts: TArray<TPascalToken>; out AType: string): Boolean;
var
  mToken: TPascalToken;
  mChars, mCount: Integer;
  mLiteral: Boolean;
begin
  Result := True;
  AType := '';
  mChars := 0;
  mLiteral := True;
  for mToken in AParts do
  begin
    if not mToken.Terminated then
    begin
      Exit;
    end;
    mCount := LiteralChars(mToken);
    if mCount = -1 then
    begin
      AType := 'string';
      Exit;
    end;
    if mCount = cNoLiteral then
    begin
      mLiteral := False;
    end
    else
    begin
      Inc(mChars, mCount);
    end;
  end;
  Result := mLiteral;
  if Result and (mChars = 1) then
  begin
    AType := 'Char';
  end
  else if Result then
  begin
    AType := 'string';
  end;
end;

function IsFloatText(const AText: string): Boolean;
begin
  Result := not CharInSet(AText[1], ['$', '%']) and ((Pos('.', AText) > 0) or ContainsText(AText, 'e'));
end;

/// <summary>Zahlen, auch mit Vorzeichen.</summary>
function NumberType(const AParts: TArray<TPascalToken>; out AType: string): Boolean;
var
  mStart: Integer;
begin
  AType := '';
  mStart := 0;
  if (Length(AParts) = 2) and (AParts[0].IsSymbol('-') or AParts[0].IsSymbol('+')) then
  begin
    mStart := 1;
  end;
  Result := (Length(AParts) = mStart + 1) and (AParts[mStart].Kind = TPascalTokenKind.Number);
  if Result and IsFloatText(AParts[mStart].Text) then
  begin
    AType := 'Double';
  end
  else if Result then
  begin
    AType := 'Integer';
  end;
end;

/// <summary>nil, True oder False allein.</summary>
function KeywordType(const AParts: TArray<TPascalToken>; out AType: string): Boolean;
begin
  AType := '';
  if Length(AParts) = 1 then
  begin
    if AParts[0].IsKeyword('nil') then
    begin
      AType := 'nil';
    end
    else if (AParts[0].Kind = TPascalTokenKind.Identifier) and (SameText(AParts[0].Text, 'True') or
      SameText(AParts[0].Text, 'False')) then
    begin
      AType := 'Boolean';
    end;
  end;
  Result := AType <> '';
end;

/// <summary>Menge, Zeichen, String, Zahl, nil oder Boolean; True, wenn AParts damit bestimmt ist.</summary>
function LiteralArgumentType(const AParts: TArray<TPascalToken>; out AType: string): Boolean;
begin
  Result := True;
  if AParts[0].IsSymbol('[') then
  begin
    AType := '[]';
  end
  else if not TextLiteralType(AParts, AType) and not NumberType(AParts, AType) then
  begin
    Result := KeywordType(AParts, AType);
  end;
end;

/// <summary>Bezeichner oder Kette A.B.C.</summary>
function IsNameChain(const AParts: TArray<TPascalToken>): Boolean;
var
  mIndex: Integer;
begin
  Result := Odd(Length(AParts));
  for mIndex := 0 to High(AParts) do
  begin
    if Odd(mIndex) then
    begin
      Result := Result and AParts[mIndex].IsSymbol('.');
    end
    else
    begin
      Result := Result and (AParts[mIndex].Kind = TPascalTokenKind.Identifier);
    end;
  end;
end;

/// <summary>Typ eines aufgelösten Bezeichners. Aufzählungswerte tragen ihren Typ als Container; Routinen bleiben
/// unbekannt (Methodenzeiger).</summary>
function ResolvedType(const AResolved: TResolvedSymbol): string;
begin
  Result := '';
  if not (AResolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) then
  begin
    Exit;
  end;
  if AResolved.SymbolKind = TIndexSymbolKind.EnumMember then
  begin
    Result := LastPart(AResolved.Container);
  end
  else if AResolved.SymbolKind in [TIndexSymbolKind.Variable, TIndexSymbolKind.Field, TIndexSymbolKind.Property_,
    TIndexSymbolKind.Constant] then
  begin
    Result := LastPart(Trim(AResolved.TypeName));
  end;
end;

/// <summary>Typ des Ausdrucks aus AParts über die Namensauflösung (L3): Aufrufe, Index, Typumwandlung und alles,
/// was TNameResolver.NodeType typisiert (Operatoren …). Bloße Namen von Routinen und Typen bleiben unbekannt:
/// Sie können ein Methodenzeiger bzw. eine Klassenreferenz sein.</summary>
function ExpressionType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const AParts: TArray<TPascalToken>): string;
var
  mNode: TSyntaxNode;
  mSymbol, mType: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  Result := '';
  mNode := SpanNode(ATree, AParts[0].Offset, AParts[High(AParts)].Offset + Length(AParts[High(AParts)].Text));
  if (mNode = nil) or not AResolver.NodeType(ATree, AFileName, mNode, mSymbol, mType, mTypeFound) or
    not mTypeFound then
  begin
    Exit;
  end;
  if (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
    (mSymbol.IsType or (mSymbol.SymbolKind in cRoutineKinds)) then
  begin
    Exit;
  end;
  Result := LastPart(mType.Name);
end;

class function TLspSignatureHelp.ArgumentType(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  AFirst, ALast: Integer): string;
var
  mParts: TArray<TPascalToken>;
begin
  Result := '';
  if (ATree = nil) or (AFirst > ALast) then
  begin
    Exit;
  end;
  mParts := CodeTokens(ATree.Tokens, AFirst, ALast);
  if (Length(mParts) = 0) or LiteralArgumentType(mParts, Result) or (AResolver = nil) then
  begin
    Exit;
  end;
  // Bezeichner oder Kette A.B.C: Aufzählungswerte über ihren Typ, Routinen bleiben unbekannt.
  if IsNameChain(mParts) then
  begin
    Result := ResolvedType(AResolver.Resolve(ATree, AFileName, mParts[High(mParts)].StartPos));
  end;
  // Übrige Ausdrücke und Namen ohne deklarierten Typ (var X := …) über den Ausdrucksbaum (L3).
  if Result = '' then
  begin
    Result := ExpressionType(AResolver, ATree, AFileName, mParts);
  end;
end;

class procedure TLspSignatureHelp.Match(var ASignature: TSignature; const AArgumentTypes: TArray<string>);
var
  mIndex: Integer;
begin
  ASignature.Fits := True;
  ASignature.Mismatch := -1;
  // Zu viele Argumente zählt der Hint selbst; hier nur die Typen.
  for mIndex := 0 to Min(High(AArgumentTypes), High(ASignature.Parameters)) do
  begin
    if not TResolverText.ArgumentFits(ASignature.Parameters[mIndex].TypeName, AArgumentTypes[mIndex]) then
    begin
      ASignature.Fits := False;
      ASignature.Mismatch := mIndex;
      Exit;
    end;
  end;
end;

/// <summary>Benennt der Parametertext AText (etwa "const A, B: Integer") den Parameter AName?</summary>
function NamesParameter(const AText, AName: string): Boolean;
var
  mEnd: string;
begin
  Result := SameText(AText, AName);
  for mEnd in cNameEnds do
  begin
    Result := Result or StartsText(AName + mEnd, AText) or ContainsText(AText, ' ' + AName + mEnd);
  end;
end;

procedure ApplyDocumentation(var ASignature: TSignature; const ADoc: TXmlDoc);
var
  mSection: TXmlDocSection;
  mName, mText: string;
  mIndex: Integer;
begin
  // Alles außer den Parametern an die Signatur, <param> an den passenden Parameter. Klartext: Der Hint
  // des Plugins und der Client von RAD Studio zeigen kein Markdown; Namen aus cref bleiben erhalten.
  ASignature.Documentation := ADoc.ToPlainText(False);
  for mSection in ADoc.Sections do
  begin
    if mSection.Kind <> TXmlDocSectionKind.Param then
    begin
      Continue;
    end;
    mName := mSection.Name;
    for mIndex := 0 to High(ASignature.Parameters) do
    begin
      mText := Copy(ASignature.Text, ASignature.Parameters[mIndex].StartIndex + 1,
        ASignature.Parameters[mIndex].EndIndex - ASignature.Parameters[mIndex].StartIndex);
      if NamesParameter(mText, mName) then
      begin
        ASignature.Parameters[mIndex].Documentation := mSection.Text;
        Break;
      end;
    end;
  end;
end;

/// <summary>Erste Überladung mit genug Parametern für AActiveParameter.</summary>
function ActiveSignatureOf(const ASignatures: TArray<TSignature>; AActiveParameter: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to High(ASignatures) do
  begin
    if Length(ASignatures[mIndex].Parameters) > AActiveParameter then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Steht der Name an APosition in einer Attributklammer ("[TestCase(")? ANameToken: sein Token.</summary>
function AttributeName(ATree: TSyntaxTree; const APosition: TTextPosition; out ANameToken: TPascalToken): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mIndex, mPrev: Integer;
begin
  Result := False;
  mTokens := ATree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if (mTokens[mIndex].StartPos.Line = APosition.Line) and
      (mTokens[mIndex].StartPos.Character = APosition.Character) then
    begin
      mPrev := PreviousCodeToken(mTokens, mIndex);
      ANameToken := mTokens[mIndex];
      Exit((mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and TAttributes.InBracket(mTokens, mPrev));
    end;
  end;
end;

/// <summary>Attribut (#465): Konstruktor der Attributklasse hinter dem Namen; [Foo] meint zuerst FooAttribute.
/// </summary>
function AttributeConstructor(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; const AResolved: TResolvedSymbol; out ACtor: TResolvedSymbol): Boolean;
var
  mNameToken: TPascalToken;
  mAttributeClass: TResolvedSymbol;
begin
  Result := False;
  ACtor := Default(TResolvedSymbol);
  if not AttributeName(ATree, APosition, mNameToken) then
  begin
    Exit;
  end;
  if not AResolver.Queries.AttributeClassOf(AResolved, mAttributeClass) and
    not AResolver.Queries.AttributeClassOf(AResolver.ResolveChain(ATree, AFileName,
      TArray<string>.Create(TAttributes.ShortName(mNameToken.Text) + 'Attribute'), mNameToken.Offset), mAttributeClass) then
  begin
    Exit;
  end;
  Result := AResolver.DeclaredMember(mAttributeClass, 'Create', ACtor) and
    (ACtor.SymbolKind = TIndexSymbolKind.Constructor_);
end;

/// <summary>Routinen der Unit System ohne Quelltext (#880): Signaturen aus der eingebauten Liste.</summary>
function IntrinsicSignatures(const AName: string): TArray<TSignature>;
var
  mIntrinsic: TSystemIntrinsic;
  mSignature: TSignature;
begin
  Result := nil;
  for mIntrinsic in TSystemIntrinsics.Find(AName) do
  begin
    if mIntrinsic.Kind = TIndexSymbolKind.Routine then
    begin
      mSignature := TLspSignatureHelp.ParseSignature([mIntrinsic.Declaration], 0, 0);
      if mSignature.Text = '' then
      begin
        Continue;
      end;
      mSignature.Documentation := mIntrinsic.Documentation;
      Result := Result + [mSignature];
    end;
  end;
end;

/// <summary>Erste verträgliche Überladung mit genug Parametern, sonst die erste mit genug Parametern.</summary>
function PreferredSignature(const ASignatures: TArray<TSignature>; AActiveParameter: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ASignatures) do
  begin
    if (Length(ASignatures[mIndex].Parameters) > AActiveParameter) and ASignatures[mIndex].Fits then
    begin
      Exit(mIndex);
    end;
  end;
  Result := ActiveSignatureOf(ASignatures, AActiveParameter);
end;

{ THelpRun }

constructor THelpRun.Create(const ARequest: TSignatureHelpRequest; const APosition: TTextPosition);
begin
  inherited Create;
  FRequest := ARequest;
  FPosition := APosition;
end;

procedure THelpRun.ResolveSite;
var
  mCtor: TResolvedSymbol;
begin
  FResolved := FRequest.Resolver.Resolve(FRequest.Tree, FRequest.FileName, FSite.NamePosition);
  // Attribut (#465): [TestCase('Name', |] zeigt den Konstruktor von TestCaseAttribute.
  if not FSite.Bracket and AttributeConstructor(FRequest.Resolver, FRequest.Tree, FRequest.FileName,
    FSite.NamePosition, FResolved, mCtor) then
  begin
    FResolved := mCtor;
    FAttribute := True;
  end;
end;

function THelpRun.IntrinsicHelp: TSignatureHelp;
var
  mName: string;
begin
  // Unbekannt: vielleicht eine Routine von System ohne Quelltext (SetLength, Inc ...; #880).
  Result := Default(TSignatureHelp);
  if TSystemIntrinsics.NameAt(FRequest.Tree, FSite.NamePosition, mName) then
  begin
    Result.Signatures := IntrinsicSignatures(mName);
    Result.Intrinsic := True;
    Result.ActiveParameter := FSite.ActiveParameter;
    Result.ActiveSignature := ActiveSignatureOf(Result.Signatures, FSite.ActiveParameter);
  end;
end;

function THelpRun.LinesOf(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  mIndex: Integer;
  mText: string;
begin
  // Jede Datei einmal je Lauf: Überladungen aus Vorfahren können in anderen Units stehen (L3).
  for mIndex := 0 to High(FFiles) do
  begin
    if SameText(FFiles[mIndex], AFileName) then
    begin
      ALines := FFileLines[mIndex];
      Exit(FFileFound[mIndex]);
    end;
  end;
  if SameText(AFileName, FRequest.FileName) then
  begin
    mText := FRequest.TreeText;
    Result := True;
  end
  else
  begin
    Result := Assigned(FRequest.ReadText) and FRequest.ReadText(AFileName, mText);
  end;
  ALines := nil;
  if Result then
  begin
    ALines := TTextLines.SplitLines(mText);
  end;
  FFiles := FFiles + [AFileName];
  // Einzeln gesetzt: [ALines] wäre als Literal eines Arrays von Arrays, [Result] als Menge mehrdeutig.
  SetLength(FFileLines, Length(FFileLines) + 1);
  FFileLines[High(FFileLines)] := ALines;
  SetLength(FFileFound, Length(FFileFound) + 1);
  FFileFound[High(FFileFound)] := Result;
end;

procedure THelpRun.AddStart(const APosition: TTextPosition; const ASymbol: TResolvedSymbol;
  const ABindings: TArray<string>);
begin
  FStarts := FStarts + [APosition];
  FStartSymbols := FStartSymbols + [ASymbol];
  SetLength(FStartBindings, Length(FStartBindings) + 1);
  FStartBindings[High(FStartBindings)] := ABindings;
end;

function THelpRun.IsOverload(const ASymbol: TIndexSymbol): Boolean;
begin
  Result := (ASymbol.Kind in cRoutineKinds) and SameText(ASymbol.Name, FResolved.Name) and
    SameText(ASymbol.Container, FResolved.Container);
end;

function THelpRun.OwnerUnit(out AOwner: TUnitIndex): Boolean;
begin
  Result := True;
  if SameText(FResolved.FileName, FRequest.FileName) then
  begin
    AOwner := TIndexExtractor.Extract(FRequest.Tree, FRequest.FileName);
  end
  else
  begin
    Result := TIndexFiles.UnitOf(FRequest.Index, FResolved.FileName, AOwner);
  end;
end;

function THelpRun.CollectUnitStarts: Boolean;
var
  mOwner: TUnitIndex;
  mSymbol: TIndexSymbol;
  mHasInterface: Boolean;
begin
  Result := OwnerUnit(mOwner);
  if not Result then
  begin
    Exit;
  end;
  mHasInterface := False;
  for mSymbol in mOwner.Symbols do
  begin
    mHasInterface := mHasInterface or (IsOverload(mSymbol) and mSymbol.InInterface);
  end;
  // Rümpfe globaler Routinen aus interface weglassen: sie dürfen die Parameter auslassen.
  for mSymbol in mOwner.Symbols do
  begin
    if IsOverload(mSymbol) and (mSymbol.InInterface or not mHasInterface) and
      SameText(mOwner.SymbolFile(mSymbol), FResolved.FileName) then
    begin
      AddStart(mSymbol.Range.StartPos, TResolvedSymbol.FromIndex(mOwner, mSymbol), FResolved.Bindings);
    end;
  end;
end;

function THelpRun.InheritedCall: Boolean;
var
  mPrevious: Integer;
begin
  // inherited Add(: nur die Vorfahren; die eigenen Überladungen gehören nicht dazu.
  mPrevious := PreviousCodeToken(FRequest.Tree.Tokens, FSite.NameIndex);
  Result := (mPrevious >= 0) and FRequest.Tree.Tokens[mPrevious].IsKeyword('inherited');
end;

procedure THelpRun.AddInheritedStarts;
var
  mCallee: TSyntaxNode;
  mCandidate: TResolvedSymbol;
  mOrder: TArray<string>;
begin
  // Überladungen aus Vorfahren (L3): Die Namensauflösung sammelt sie wie der Compiler (alle Methoden einer Stufe mit
  // overload bzw. override, sonst verdeckt die Stufe die Vorfahren), nur entlang der Kette des einen Typs.
  if (FResolved.Kind <> TResolvedKind.Symbol) or (FResolved.Container = '') or FAttribute or InheritedCall then
  begin
    Exit;
  end;
  mCallee := CalleeNode(FRequest.Tree, FSite.CalleeEnd);
  if mCallee = nil then
  begin
    Exit;
  end;
  mOrder := nil;
  for mCandidate in FRequest.Resolver.CallCandidates(FRequest.Tree, FRequest.FileName, mCallee) do
  begin
    if not (mCandidate.SymbolKind in cRoutineKinds) or not SameText(mCandidate.Name, FResolved.Name) then
    begin
      Continue;
    end;
    if IndexText(mCandidate.Container, mOrder) < 0 then
    begin
      mOrder := mOrder + [mCandidate.Container];
    end;
    if not SameText(mCandidate.Container, FResolved.Container) then
    begin
      AddStart(mCandidate.Range.StartPos, mCandidate, mCandidate.Bindings);
    end;
  end;
  OrderByContainer(mOrder);
end;

procedure THelpRun.OrderByContainer(const AOrder: TArray<string>);
var
  mRank, mIndex: Integer;
  mStarts: TArray<TTextPosition>;
  mSymbols: TArray<TResolvedSymbol>;
  mBindings: TArray<TArray<string>>;
begin
  // Stabil nach der Stufe der Vererbung: der Typ selbst zuerst, dann seine Vorfahren, unabhängig davon, welche
  // Überladung die Auflösung gewählt hat.
  if Length(AOrder) < 2 then
  begin
    Exit;
  end;
  mStarts := nil;
  mSymbols := nil;
  mBindings := nil;
  for mRank := -1 to High(AOrder) do
  begin
    for mIndex := 0 to High(FStarts) do
    begin
      if IndexText(FStartSymbols[mIndex].Container, AOrder) = mRank then
      begin
        mStarts := mStarts + [FStarts[mIndex]];
        mSymbols := mSymbols + [FStartSymbols[mIndex]];
        SetLength(mBindings, Length(mBindings) + 1);
        mBindings[High(mBindings)] := FStartBindings[mIndex];
      end;
    end;
  end;
  FStarts := mStarts;
  FStartSymbols := mSymbols;
  FStartBindings := mBindings;
end;

procedure THelpRun.KeepGenericStarts;
var
  mIndex: Integer;
  mStarts: TArray<TTextPosition>;
  mSymbols: TArray<TResolvedSymbol>;
  mBindings: TArray<TArray<string>>;
begin
  // Foo<Integer>( (L3): nur Überladungen mit so vielen Typparametern; die Typargumente werden eingesetzt.
  if Length(FSite.TypeArgs) = 0 then
  begin
    Exit;
  end;
  mStarts := nil;
  mSymbols := nil;
  mBindings := nil;
  for mIndex := 0 to High(FStarts) do
  begin
    if Length(TResolverText.SplitArgs(FStartSymbols[mIndex].TypeParams)) = Length(FSite.TypeArgs) then
    begin
      mStarts := mStarts + [FStarts[mIndex]];
      mSymbols := mSymbols + [FStartSymbols[mIndex]];
      SetLength(mBindings, Length(mBindings) + 1);
      mBindings[High(mBindings)] := TResolverText.Bind(FStartSymbols[mIndex].TypeParams, FSite.TypeArgs) +
        FStartBindings[mIndex];
    end;
  end;
  FStarts := mStarts;
  FStartSymbols := mSymbols;
  FStartBindings := mBindings;
end;

function THelpRun.CollectStarts: Boolean;
var
  mNested: TResolvedSymbol;
begin
  // Überladungen: gleicher Name im selben Typ bzw. auf Unit-Ebene derselben Unit, dazu die geerbten.
  Result := True;
  if FResolved.Kind = TResolvedKind.Local then
  begin
    // Verschachtelte Routinen (#881): alle Überladungen in der umgebenden Routine, vor und hinter dem Aufruf.
    for mNested in FRequest.Resolver.Candidates.LocalOverloads(FResolved) do
    begin
      AddStart(mNested.Range.StartPos, mNested, FResolved.Bindings);
    end;
  end
  else
  begin
    Result := CollectUnitStarts;
    if Result then
    begin
      AddInheritedStarts;
    end;
  end;
  KeepGenericStarts;
end;

function IsProcedureForm(const AForm: string): Boolean;
begin
  Result := SameText(AForm, 'procedure') or SameText(AForm, 'function');
end;

function THelpRun.ProceduralType(out AType: TResolvedSymbol): Boolean;
begin
  // Aufruf über eine Variable, ein Feld, eine Property oder einen Parameter eines Prozedurtyps (L3): FOnChange(Self),
  // Callback(1), AProc(. Der Index führt die Form als "target:procedure" bzw. "target:function".
  Result := False;
  AType := Default(TResolvedSymbol);
  if FResolved.IsType or (FResolved.SymbolKind in cRoutineKinds) then
  begin
    Exit;
  end;
  // Feld mit anonymem Typ: FOnTick: procedure(ATicks: Integer) of object;
  if (FResolved.TypeName = '') and IsProcedureForm(FResolved.TargetForm) then
  begin
    AType := FResolved;
    Exit(True);
  end;
  Result := FRequest.Resolver.TypeOf(FResolved, AType) and not AType.Builtin and
    (AType.SymbolKind = TIndexSymbolKind.TypeAlias) and IsProcedureForm(AType.TargetForm);
end;

function IsIndexedProperty(const ASymbol: TResolvedSymbol): Boolean;
begin
  Result := (ASymbol.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and
    (ASymbol.SymbolKind = TIndexSymbolKind.Property_) and (ASymbol.MaxArgs > 0);
end;

function THelpRun.IndexedProperty(out AProperty: TResolvedSymbol): Boolean;
var
  mNode: TSyntaxNode;
  mType: TResolvedSymbol;
  mTypeFound: Boolean;
begin
  // Liste.Items[ ist die Property selbst; Liste[ meint die default-Property des Typs (L3), die die
  // Namensauflösung am Indexzugriff liefert.
  AProperty := FResolved;
  if IsIndexedProperty(FResolved) then
  begin
    Exit(True);
  end;
  Result := False;
  if not (FResolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) then
  begin
    Exit;
  end;
  mNode := IndexNode(FRequest.Tree, FSite.CalleeEnd);
  Result := (mNode <> nil) and FRequest.Resolver.NodeType(FRequest.Tree, FRequest.FileName, mNode, AProperty, mType,
    mTypeFound) and IsIndexedProperty(AProperty);
end;

function THelpRun.BoundTypes(const ABindings: TArray<string>): TArray<string>;
var
  mBinding: string;
begin
  // Typargumente ohne Unit davor ("T=TKunde" statt "T=Listen.TKunde").
  Result := nil;
  for mBinding in ABindings do
  begin
    Result := Result + [Copy(mBinding, 1, Pos('=', mBinding)) +
      FRequest.Resolver.Queries.UnqualifyType(Copy(mBinding, Pos('=', mBinding) + 1, MaxInt))];
  end;
end;

function THelpRun.HeaderLines(const ALines: TArray<string>; const AStart: TTextPosition;
  const ABindings: TArray<string>): TArray<string>;
var
  mLine: Integer;
begin
  // Gebundene Typparameter (#450): FItems: TObjectList<TKunde> zeigt Add(const Value: TKunde). Nur die
  // Zeilen des Kopfs; die Spalte des Anfangs bleibt, weil davor kein Typparameter steht.
  Result := ALines;
  if Length(ABindings) = 0 then
  begin
    Exit;
  end;
  Result := Copy(ALines);
  for mLine := AStart.Line to Min(High(Result), AStart.Line + cMaxHeaderLines) do
  begin
    Result[mLine] := TInterfaceStubs.SubstituteWords(Result[mLine], ABindings);
  end;
end;

function THelpRun.ParseText(const ALines: TArray<string>; ALine, AColumn: Integer): TSignature;
begin
  if FSite.Bracket then
  begin
    Result := ParseHeader(ALines, ALine, AColumn, '[', ']', False);
  end
  else
  begin
    // Der Kopf eines Prozedurtyps hat kein Typ-Präfix; Punkte darin (Typargumente) sind keins.
    Result := ParseHeader(ALines, ALine, AColumn, '(', ')', not FProcedural);
  end;
end;

function THelpRun.IndexSignature(AIndex: Integer): TSignature;
begin
  // Kopf aus dem Index: ohne lesbaren Quelltext, und bei neu deklarierten Properties (property Items;), deren
  // Indexparameter MergedProperty vom Vorfahren übernimmt.
  Result := ParseText([TInterfaceStubs.SubstituteWords(FStartSymbols[AIndex].Signature,
    BoundTypes(FStartBindings[AIndex]))], 0, 0);
end;

function THelpRun.Signatures: TArray<TSignature>;
var
  mIndex: Integer;
  mStart: TTextPosition;
  mSignature: TSignature;
  mKey: string;
  mSeen, mLines: TArray<string>;
  mReader: TDocReadText;
  mFromSource: Boolean;
begin
  Result := nil;
  mSeen := nil;
  mReader := TLspDocumentation.Reader(FRequest.FileName, FRequest.TreeText, FRequest.ReadText);
  for mIndex := 0 to High(FStarts) do
  begin
    mStart := FStarts[mIndex];
    mFromSource := LinesOf(FStartSymbols[mIndex].FileName, mLines) and (mStart.Line >= 0) and
      (mStart.Line <= High(mLines));
    if mFromSource then
    begin
      mSignature := ParseText(HeaderLines(mLines, mStart, BoundTypes(FStartBindings[mIndex])), mStart.Line,
        mStart.Character);
    end
    else
    begin
      mSignature := Default(TSignature);
    end;
    if not mFromSource or (FSite.Bracket and (Length(mSignature.Parameters) = 0)) then
    begin
      mSignature := IndexSignature(mIndex);
    end;
    // Deklaration und Rumpf derselben Routine nur einmal; die Deklaration steht vorn und trägt die Doku.
    mKey := UpperCase(StringReplace(mSignature.Text, ' ', '', [rfReplaceAll]));
    if (mSignature.Text = '') or mSignature.Qualified or MatchStr(mKey, mSeen) then
    begin
      Continue;
    end;
    mSeen := mSeen + [mKey];
    if mFromSource then
    begin
      ApplyDocumentation(mSignature, TLspDocumentation.Load(FRequest.Resolver, FStartSymbols[mIndex], mLines,
        mStart.Line, mReader));
    end;
    Result := Result + [mSignature];
  end;
end;

procedure THelpRun.MatchArguments(var ASignatures: TArray<TSignature>);
var
  mTypes: TArray<string>;
  mIndex: Integer;
begin
  // Argumenttypen (#498), erst nach dem Einsammeln der Überladungen aufgelöst.
  mTypes := nil;
  for mIndex := 0 to High(FSite.ArgumentFirst) do
  begin
    mTypes := mTypes + [TLspSignatureHelp.ArgumentType(FRequest.Resolver, FRequest.Tree, FRequest.FileName,
      FSite.ArgumentFirst[mIndex], FSite.ArgumentLast[mIndex])];
  end;
  for mIndex := 0 to High(ASignatures) do
  begin
    TLspSignatureHelp.Match(ASignatures[mIndex], mTypes);
  end;
end;

procedure THelpRun.AddFormat(var AHelp: TSignatureHelp);
var
  mRoutine: TFormatRoutine;
  mCall: TSignatureFormatCall;
begin
  // Platzhalter einer Formatroutine (#451), nach dem voll qualifizierten Namen.
  if (Length(AHelp.Signatures) = 0) or not TFormatRoutines.FindQualified(FRequest.Routines,
    FResolved.UnitName + '.' + FResolved.QualifiedName, mRoutine) then
  begin
    Exit;
  end;
  mCall := Default(TSignatureFormatCall);
  mCall.Resolver := FRequest.Resolver;
  mCall.Tree := FRequest.Tree;
  mCall.FileName := FRequest.FileName;
  mCall.Firsts := FSite.ArgumentFirst;
  mCall.Lasts := FSite.ArgumentLast;
  mCall.ActiveParameter := FSite.ActiveParameter;
  AHelp.Format := TSignatureFormats.Analyze(mCall, mRoutine);
end;

function THelpRun.SiteHelp: TSignatureHelp;
var
  mType: TResolvedSymbol;
begin
  Result := Default(TSignatureHelp);
  ResolveSite;
  if FSite.Bracket then
  begin
    // Index-Property (L3).
    if not IndexedProperty(mType) then
    begin
      Exit;
    end;
    AddStart(mType.Range.StartPos, mType, mType.Bindings);
  end
  else if not (FResolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) then
  begin
    if Length(FSite.TypeArgs) = 0 then
    begin
      Result := IntrinsicHelp;
    end;
    Exit;
  end
  else if FResolved.SymbolKind in cRoutineKinds then
  begin
    if not CollectStarts then
    begin
      Exit;
    end;
  end
  else if ProceduralType(mType) then
  begin
    FProcedural := True;
    AddStart(mType.Range.StartPos, mType, mType.Bindings);
  end
  else
  begin
    Exit;
  end;
  Result.Signatures := Signatures;
  Result.ActiveParameter := FSite.ActiveParameter;
  MatchArguments(Result.Signatures);
  Result.ActiveSignature := PreferredSignature(Result.Signatures, FSite.ActiveParameter);
  AddFormat(Result);
end;

function THelpRun.Run: TSignatureHelp;
begin
  // Dieselbe Stelle wie der Parameter-Hint der IDE (TDpccCallScanner): Findet sie nichts (ein Array statt einer
  // Index-Property, ein Vergleich A < B > (C)), bleibt die Antwort leer statt eines anderen Aufrufs.
  Result := Default(TSignatureHelp);
  FSite := ScanCallSite(FRequest.Tree, FPosition, True);
  if FSite.Found then
  begin
    Result := SiteHelp;
  end;
end;

class function TLspSignatureHelp.HelpAt(const ARequest: TSignatureHelpRequest;
  const APosition: TTextPosition): TSignatureHelp;
var
  mRun: THelpRun;
begin
  mRun := THelpRun.Create(ARequest, APosition);
  try
    Result := mRun.Run;
  finally
    mRun.Free;
  end;
end;

class function TLspSignatureHelp.ToJson(const AHelp: TSignatureHelp): TJSONValue;
var
  mSignatures, mParameters, mLabelRange: TJSONArray;
  mSignature, mParameter, mDocumentation, mData, mFormatJson: TJSONObject;
  mItem: TSignature;
  mIndex: Integer;
begin
  if not AHelp.Found then
  begin
    Exit(TJSONNull.Create);
  end;
  mSignatures := TJSONArray.Create;
  for mItem in AHelp.Signatures do
  begin
    mSignature := TJSONObject.Create;
    mSignatures.AddElement(mSignature);
    mSignature.AddPair('label', mItem.Text);
    if mItem.Documentation <> '' then
    begin
      mDocumentation := TJSONObject.Create;
      mDocumentation.AddPair('kind', 'markdown');
      mDocumentation.AddPair('value', mItem.Documentation);
      mSignature.AddPair('documentation', mDocumentation);
    end;
    mParameters := TJSONArray.Create;
    mSignature.AddPair('parameters', mParameters);
    for mIndex := 0 to High(mItem.Parameters) do
    begin
      mParameter := TJSONObject.Create;
      mParameters.AddElement(mParameter);
      mLabelRange := TJSONArray.Create;
      mLabelRange.Add(mItem.Parameters[mIndex].StartIndex);
      mLabelRange.Add(mItem.Parameters[mIndex].EndIndex);
      mParameter.AddPair('label', mLabelRange);
      if mItem.Parameters[mIndex].Documentation <> '' then
      begin
        mParameter.AddPair('documentation', mItem.Parameters[mIndex].Documentation);
      end;
    end;
    // Verträglichkeit der bisherigen Argumente (#498), für den Parameter-Hint des Plugins.
    mData := TJSONObject.Create;
    mData.AddPair('fits', TJSONBool.Create(mItem.Fits));
    mData.AddPair('mismatch', TJSONNumber.Create(mItem.Mismatch));
    mSignature.AddPair('data', mData);
  end;
  Result := TJSONObject.Create;
  TJSONObject(Result).AddPair('signatures', mSignatures);
  TJSONObject(Result).AddPair('activeSignature', TJSONNumber.Create(AHelp.ActiveSignature));
  TJSONObject(Result).AddPair('activeParameter', TJSONNumber.Create(AHelp.ActiveParameter));
  // Platzhalter (#451), Erweiterung von dpcc.
  mFormatJson := TSignatureFormats.ToJson(AHelp.Format);
  if mFormatJson <> nil then
  begin
    TJSONObject(Result).AddPair('format', mFormatJson);
  end;
end;

function TLspSignatureHelp.Handle(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri: string;
  mPositionValue: TJSONValue;
  mDocument: ITextDocument;
  mTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mHelp: TSignatureHelp;
  mRequest: TSignatureHelpRequest;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TSignatureHelpText.FieldsTextDocumentUriAndPosition].Text);
  end;
  if not FStore.TryGet(mUri, mDocument) then
  begin
    Exit(TJSONNull.Create);
  end;
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  mTree := mShared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mResolver.Namespaces := Namespaces;
    mRequest := TSignatureHelpRequest.Create(mResolver, FIndex, mTree, mDocument.Text, TDocumentUris.ToPath(mUri),
      FReadText);
    if Assigned(FFormatRoutinesFor) then
    begin
      mRequest.Routines := FFormatRoutinesFor(mUri);
    end;
    mHelp := HelpAt(mRequest, TLspPositions.ReadPosition(mPositionValue));
  finally
    mResolver.Free;
  end;
  Result := ToJson(mHelp);
end;

initialization
  TDpccTextTables.Add('dpcc.Common.Lsp.SignatureHelp', cTexts);

end.
