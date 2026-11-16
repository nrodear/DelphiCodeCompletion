unit dpcc.Common.Index.Extractor;

// Liest aus dem Syntaxbaum einer Unit die Einträge für den Symbolindex:
// Typen mit Mitgliedern und Vorfahren, Konstanten, Variablen, Routinen und
// die uses-Listen. Lokale Deklarationen in Routinen gehören nicht dazu.
//
// Vor dem Parsen werden die inaktiven Zweige der bedingten Kompilierung
// durch Leerzeichen ersetzt (Zeilenumbrüche bleiben), damit nur aktive
// Deklarationen erscheinen und alle Positionen stimmen.
//
// Mit Include-Auflösung kommen die Deklarationen aktiver $I-Dateien dazu
// (#500): Jede Datei wird für sich geparst (ein Fragment ohne unit-Kopf
// liefert seine Deklarationen), ihre Symbole tragen die .inc als FileName
// und zählen zum Abschnitt, in dem die Direktive steht. Steht die Direktive
// mitten in einem type-, const- oder var-Abschnitt und beginnt die Datei
// nicht selbst mit einem Abschnitt, wird das Schlüsselwort vorangestellt.
// Zyklen und zu tiefe Verschachtelung überspringt der Extractor; die
// Diagnose dazu kommt aus dem Präprozessor.
//
// Vorwärtsdeklarationen (TFoo = class;) erscheinen nur, wenn die Unit den Typ
// nicht vollständig deklariert. Sonst fänden Hover, Vererbungskette und
// Gehe zu Definition die Vorwärtsdeklaration (ohne Vorfahren) statt des Typs.
//
// Tokens liest dpcc.Common.Index.Extractor.Tokens, Typtexte dpcc.Common.Index.Extractor.TypeText, bedingte
// Kompilierung dpcc.Common.Index.Extractor.Conditions und inline-Rümpfe dpcc.Common.Index.Extractor.InlineRefs.
//
// Index-Inhalte L1 (Format 35): Was eine Deklaration ohne eigenes Feld ausmacht, steht als Eintrag in
// TIndexSymbol.Directives (Zieltyp und Form, Attribute, DLL-Angaben, resourcestring, threadvar, operator,
// destructor, message, Einschränkungen der Typparameter; Lesefunktionen am Symbol). Werte anonymer Aufzählungen
// (set of (a, b), F: (x, y)) und Felder anonymer Records (F: record … end) kommen mit dem Feld- bzw. Typnamen als
// Container dazu. In Bibliotheks-Units entfallen die Rümpfe im implementation-Teil, die eine interface-Deklaration
// wiederholen (DropImplementationDuplicates); ihre DLL-Angaben und ihre Zeile stehen am interface-Symbol.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Common.Pascal.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Pascal.Preprocessor,
  dpcc.Common.Index.Contract,
  dpcc.Common.Index.Extractor.Tokens;

type
  /// <summary>Zustand beim Lesen der Deklarationen, den Add für das nächste Symbol braucht.</summary>
  TIndexDeclarationState = record
    InInterface: Boolean;
    Visibility: TIndexVisibility;
    /// <summary>Typargumente der Vorfahren für den nächsten Add aus AddType.</summary>
    AncestorArgs: TArray<string>;
    /// <summary>Der nächste Add aus AddType ist eine Vorwärtsdeklaration; FForwards hält deren Nummern.</summary>
    IsForward: Boolean;
    /// <summary>Zweig des varianten Record-Teils, in dem AddMembers gerade steht (#846).</summary>
    VariantBranch: string;
    /// <summary>AddMembers steht in einem Abschnitt "class var" (#1001).</summary>
    ClassVar: Boolean;
    /// <summary>Der nächste Add gehört zu einer Aufzählung unter {$SCOPEDENUMS ON} (#849).</summary>
    Scoped: Boolean;
    /// <summary>Nummer des Typs in FSymbols, dessen Rumpf AddMembers gerade liest; -1 ohne. Methodenzuordnungen
    /// landen in seinen Resolutions.</summary>
    ResolutionOwner: Integer;
    /// <summary>Attribute vor der nächsten Deklaration als "@Name" (L1); Add übernimmt und leert sie.</summary>
    Attributes: TArray<string>;
    /// <summary>"resourcestring" bzw. "threadvar", solange ein solcher Abschnitt gelesen wird (L1); sonst ''.
    /// </summary>
    SectionWord: string;
  end;

  TIndexExtractor = class
  private
    FReader: TIndexTokenReader;
    FSymbols: TList<TIndexSymbol>;
    FForwards: TList<Integer>;
    FState: TIndexDeclarationState;
    function NewSymbol(ANode: TSyntaxNode; const AName, AContainer: string; AKind: TIndexSymbolKind): TIndexSymbol;
    /// <summary>Typ, Typargumente und Signatur.</summary>
    procedure SetTypeInfo(var ASymbol: TIndexSymbol; ANode: TSyntaxNode; const AName: string;
      AKind: TIndexSymbolKind);
    procedure SetParamInfo(var ASymbol: TIndexSymbol; ANode: TSyntaxNode; AKind: TIndexSymbolKind);
    procedure SetDirectives(var ASymbol: TIndexSymbol; ANode: TSyntaxNode; AKind: TIndexSymbolKind;
      const AContainer: string);
    /// <summary>Einträge für Arten, DLL-Angaben, Einschränkungen, Zieltyp und Attribute (L1).</summary>
    procedure AddKindEntries(var ASymbol: TIndexSymbol; ANode: TSyntaxNode; AKind: TIndexSymbolKind);
    procedure Add(ANode: TSyntaxNode; const AName, AContainer: string; AKind: TIndexSymbolKind;
      const AAncestors: TArray<string>);
    procedure AddNames(ANode: TSyntaxNode; const AContainer: string; AKind: TIndexSymbolKind);
    /// <summary>Mitglieder eines anonymen Typs (Aufzählung, Record) eines Felds, einer Variablen oder einer Menge mit
    /// AContainer als Container (L1).</summary>
    procedure AddAnonymousMembers(AType: TSyntaxNode; const AContainer: string);
    /// <summary>Zieltyp und Form als Eintrag "target:Form=Typ" für Typen und Werte ohne TypeName (L1); '' sonst.
    /// </summary>
    function TargetEntry(ANode: TSyntaxNode; AKind: TIndexSymbolKind; const ATypeName: string): string;
    /// <summary>Attribute des Knotens AAttribute ([Weak], [TestCase('a')]) an FState.Attributes anhängen (L1).
    /// </summary>
    procedure TakeAttributes(AAttribute: TSyntaxNode);
    /// <summary>Wie AddMembers bzw. AddDeclarations für einen const- oder var-Abschnitt; merkt resourcestring und
    /// threadvar (L1).</summary>
    procedure EnterSection(ASection: TSyntaxNode; out ASaved: string);
    procedure AddTypeSymbol(ADecl, ABody: TSyntaxNode; const AContainer: string);
    procedure AddEnumMembers(ABody: TSyntaxNode; const AQualified: string);
    /// <summary>Elementtyp einer Menge bzw. eines Arrays als Text für den Zieltyp (L1).</summary>
    function ElementText(AElement: TSyntaxNode): string;
    /// <summary>Mitglieder des Rumpfs ABody; ACount: Nummer des Typs in FSymbols.</summary>
    procedure AddBodyMembers(ABody: TSyntaxNode; const AQualified: string; ACount: Integer);
    procedure AddType(ADecl: TSyntaxNode; const AContainer: string);
    /// <summary>Hängt die Methodenzuordnung AHeader als "IFoo.Bar=Baz" an die Resolutions des Typs an.</summary>
    procedure AddResolution(AHeader: TSyntaxNode);
    procedure AddHeader(AHeader: TSyntaxNode; const AContainer: string);
    /// <summary>Zweig eines varianten Teils (#846); das Selektorfeld davor steht im äußeren Zweig.</summary>
    procedure AddCaseItem(AItem: TSyntaxNode; const AContainer: string);
    procedure AddMember(AChild: TSyntaxNode; const AContainer: string);
    procedure AddMembers(ABody: TSyntaxNode; const AContainer: string);
    procedure AddDeclarations(ANode: TSyntaxNode);
    procedure AddRoutine(ANode: TSyntaxNode);
    /// <summary>Vorwärtsdeklarationen entfernen, deren Typ in der Unit vollständig deklariert ist.</summary>
    procedure DropForwards;
    /// <summary>uses-Listen, Hinweise, Begründungen und Initialisierung der Unit.</summary>
    procedure ReadUnitInfo(ARoot: TSyntaxNode; var AUnit: TUnitIndex);
    procedure Walk(ARoot: TSyntaxNode; var AUnit: TUnitIndex);
  public
    /// <summary>Erster direkter Typverweis eines Knotens (A: TFoo, function F: TFoo); sonst ''.</summary>
    class function DeclaredType(ANode: TSyntaxNode): string; static;
    /// <summary>Knoten des ersten direkten Typverweises; sonst nil.</summary>
    class function DeclaredTypeNode(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Typ als Text samt Typargumenten: TDictionary&lt;string, TList&lt;TKunde&gt;&gt; (#263).</summary>
    class function TypeText(ANode: TSyntaxNode): string; static;
    /// <summary>Typargumente eines Typverweises kommagetrennt ('' ohne).</summary>
    class function GenericArgsText(ATypeRef: TSyntaxNode): string; static;
    /// <summary>Parameterzahlen und -typen eines Routinenkopfs oder einer indizierten Property.</summary>
    class procedure ParamInfo(ANode: TSyntaxNode; out AMin, AMax: Integer; out ATypes: TArray<string>); static;
    constructor Create(const ATokens: TArray<TPascalToken>);
    destructor Destroy; override;
    /// <summary>Index-Eintrag aus einem fertigen Syntaxbaum (ohne Stamp und Hash).</summary>
    class function Extract(ATree: TSyntaxTree; const AFileName: string): TUnitIndex; static;
    /// <summary>Parst AText mit den aktiven Symbolen ADefines und liefert den Eintrag. Mit AResolver werden
    /// $I-Dateien gelesen (#264): ihre $DEFINEs gelten, Includes listet sie auf. Mit AUsages kommen die
    /// Verwendungen der Bezeichner dazu (#492), mit APatterns die Folgemuster der Anweisungen (#1890).</summary>
    class function ExtractText(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; AUsages, APatterns: Boolean): TUnitIndex; overload; static;
    /// <summary>Wie oben mit APatterns = False.</summary>
    class function ExtractText(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; AUsages: Boolean): TUnitIndex; overload; static;
    /// <summary>Wie oben mit AUsages = False.</summary>
    class function ExtractText(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver): TUnitIndex; overload; static;
    /// <summary>Wie oben ohne $I-Dateien und Verwendungen (AResolver = nil, AUsages = False).</summary>
    class function ExtractText(const AText, AFileName: string; const ADefines: TArray<string>): TUnitIndex;
      overload; static;
    /// <summary>Nur für Bibliotheks-Units (L1): Rümpfe im implementation-Teil, deren Routine bzw. Methode das
    /// interface deklariert (gleicher Name und Typ), entfallen; DLL-Angaben (external:, name:, index:, delayed),
    /// inline und die Zeile des Rumpfs ("impl:Zeile") kommen an die interface-Deklaration. Bei Überladungen
    /// entscheiden die Parametertypen. Routinen nur im implementation-Teil bleiben. Liefert die Zahl der entfernten
    /// Symbole.</summary>
    class function DropImplementationDuplicates(var AUnit: TUnitIndex): Integer; static;
    /// <summary>Ersetzt inaktive Zweige durch Leerzeichen; Zeilen und Spalten bleiben erhalten.</summary>
    class function BlankInactive(const AText: string; const ADefines: TArray<string>): string; static;
    /// <summary>Beginnt AName mit APrefix vor einem Großbuchstaben (FName, AValue, LIndex)?</summary>
    class function HasNamePrefix(const AName, APrefix: string): Boolean; static;
    /// <summary>Felder (auch in Records und var-Abschnitten von Klassen), Parameter und lokale Variablen
    /// (var-Abschnitte von Routinen und Inline-Variablen) unter ARoot, gezählt mit Präfix (#452).</summary>
    class function NamingOf(ARoot: TSyntaxNode): TNamingCounts; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Defaults,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.Lexer,
  dpcc.Common.Pascal.Parser,
  dpcc.Common.Pascal.TreeCache,
  dpcc.Common.Rationale.Contract,
  dpcc.Common.Rationale.Scanner,
  dpcc.Common.Index.Extractor.TypeText,
  dpcc.Common.Index.Extractor.Conditions,
  dpcc.Common.Index.Extractor.InlineRefs,
  dpcc.Common.Index.Extractor.Patterns;

const
  // Direktiven nach Routinenköpfen und Hinweise (wie im Parser); zählen nicht als Verwendung.
  cDirectiveWords: array[0..32] of string = (
    'abstract', 'assembler', 'cdecl', 'deprecated', 'dispid', 'dynamic', 'experimental',
    'export', 'external', 'far', 'final', 'forward', 'inline', 'library', 'local',
    'near', 'noreturn', 'overload', 'override', 'pascal', 'platform',
    'register', 'reintroduce', 'safecall', 'static', 'stdcall', 'unsafe', 'varargs',
    'virtual', 'winapi', 'delayed', 'sealed', 'nodefault');
  /// <summary>Arten mit Typverweis (A: TFoo, function F: TFoo, TAlias = TFoo).</summary>
  cTypedKinds = [TIndexSymbolKind.TypeAlias, TIndexSymbolKind.Constant, TIndexSymbolKind.Variable,
    TIndexSymbolKind.Field, TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Routine];
  /// <summary>Rümpfe mit Mitgliedern.</summary>
  cMemberBodies = [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.HelperType, TSyntaxKind.RecordType,
    TSyntaxKind.InterfaceType];
  /// <summary>Höchste Verschachtelung von $I-Dateien.</summary>
  cMaxIncludeDepth = 16;
  /// <summary>Name des Hilfstyps, in den AddIncluded eine .inc aus einem Klassenrumpf einbettet (#849).</summary>
  cIncludeHost = 'TDpccIncludeHost__';

function VisibilityOf(const AText: string): TIndexVisibility;
var
  mText: string;
begin
  mText := LowerCase(Trim(AText));
  if mText = 'strict private' then
  begin
    Result := TIndexVisibility.StrictPrivate;
  end
  else if mText = 'private' then
  begin
    Result := TIndexVisibility.Private;
  end
  else if mText = 'strict protected' then
  begin
    Result := TIndexVisibility.StrictProtected;
  end
  else if mText = 'protected' then
  begin
    Result := TIndexVisibility.Protected;
  end
  else if mText = 'published' then
  begin
    Result := TIndexVisibility.Published;
  end
  else
  begin
    Result := TIndexVisibility.Public;
  end;
end;

function FileNameToUnitName(const AFileName: string): string;
var
  mStart, mStop: Integer;
begin
  mStart := LastDelimiter('\/', AFileName) + 1;
  mStop := LastDelimiter('.', AFileName);
  if mStop < mStart then
  begin
    mStop := Length(AFileName) + 1;
  end;
  Result := Copy(AFileName, mStart, mStop - mStart);
end;

/// <summary>Höchstens TRationale.cMaxEntries Begründungen für den Index.</summary>
function RationaleOf(const AEntries: TArray<TRationaleEntry>): TArray<string>;
begin
  Result := TRationale.EncodeAll(Copy(AEntries, 0, TRationale.cMaxEntries));
end;

/// <summary>Rumpf einer Typdeklaration: das erste Kind außer Typparametern und Attributen; nil ohne.</summary>
function TypeBodyOf(ADecl: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ADecl.ChildCount - 1 do
  begin
    if not (ADecl[mIndex].Kind in [TSyntaxKind.GenericParams, TSyntaxKind.Attribute]) then
    begin
      Exit(ADecl[mIndex]);
    end;
  end;
  Result := nil;
end;

function KindOfBody(ABody: TSyntaxNode): TIndexSymbolKind;
begin
  Result := TIndexSymbolKind.TypeAlias;
  if ABody = nil then
  begin
    Exit;
  end;
  case ABody.Kind of
    TSyntaxKind.ClassType, TSyntaxKind.ClassOfType, TSyntaxKind.ForwardType:
      Result := TIndexSymbolKind.ClassType;
    TSyntaxKind.ObjectType:
      Result := TIndexSymbolKind.ObjectType;
    TSyntaxKind.HelperType:
      Result := TIndexSymbolKind.HelperType;
    TSyntaxKind.RecordType:
      Result := TIndexSymbolKind.RecordType;
    TSyntaxKind.InterfaceType:
      Result := TIndexSymbolKind.InterfaceType;
    TSyntaxKind.EnumType:
      Result := TIndexSymbolKind.EnumType;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Vorfahren: direkte Typverweise des Rumpfs (class(TBase, IFoo), helper for T). AArgs: Typargumente
/// jedes Vorfahren, nil wenn keiner welche hat.</summary>
function AncestorsOf(ABody: TSyntaxNode; out AArgs: TArray<string>): TArray<string>;
var
  mIndex: Integer;
  mArgs: string;
  mWithArgs: Boolean;
begin
  Result := nil;
  AArgs := nil;
  mWithArgs := False;
  if (ABody = nil) or not (ABody.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.InterfaceType,
    TSyntaxKind.HelperType]) then
  begin
    Exit;
  end;
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if (ABody[mIndex].Kind = TSyntaxKind.TypeReference) and (ABody[mIndex].Name <> '') then
    begin
      // Typargumente jedes Vorfahren: IComparer<TKunde> an zweiter Stelle braucht sie für den
      // Vergleich der Signaturen genauso wie der erste.
      mArgs := TIndexTypeText.GenericArgsText(ABody[mIndex]);
      mWithArgs := mWithArgs or (mArgs <> '');
      AArgs := AArgs + [mArgs];
      Result := Result + [ABody[mIndex].Name];
    end;
  end;
  if not mWithArgs then
  begin
    AArgs := nil;
  end;
end;

function QualifiedOf(const AContainer, AName: string): string;
begin
  if AContainer = '' then
  begin
    Result := AName;
  end
  else
  begin
    Result := AContainer + '.' + AName;
  end;
end;

/// <summary>Hängt den Eintrag AEntry an die Direktiven von ASymbol, wenn er nicht leer und noch nicht da ist (L1).
/// </summary>
procedure AddEntry(var ASymbol: TIndexSymbol; const AEntry: string);
begin
  if (AEntry <> '') and (IndexText(AEntry, ASymbol.Directives) < 0) then
  begin
    ASymbol.Directives := ASymbol.Directives + [AEntry];
  end;
end;

/// <summary>Anonymer Typ mit Mitgliedern einer Deklaration: Aufzählung oder Record als Typ eines Felds bzw. einer
/// Variablen (F: (a, b), F: record … end), die Aufzählung einer Menge (set of (a, b)); sonst nil.</summary>
function AnonymousTypeOf(ANode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    case ANode[mIndex].Kind of
      TSyntaxKind.EnumType, TSyntaxKind.RecordType:
        Exit(ANode[mIndex]);
      TSyntaxKind.SetType:
        if (ANode[mIndex].ChildCount > 0) and (ANode[mIndex][0].Kind = TSyntaxKind.EnumType) then
        begin
          Exit(ANode[mIndex][0]);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

/// <summary>Typknoten der Deklaration ANode für den Zieltyp: Rumpf einer Typdeklaration, sonst der erste
/// Typknoten ohne Namen (array, ^, set, class of, file of, Prozedurtyp, Teilbereich, Aufzählung, Record); nil
/// ohne.</summary>
function TargetNodeOf(ANode: TSyntaxNode): TSyntaxNode;
var
  mIndex: Integer;
begin
  Result := nil;
  if ANode.Kind = TSyntaxKind.TypeDecl then
  begin
    Exit(TypeBodyOf(ANode));
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[mIndex].Kind in [TSyntaxKind.ArrayType, TSyntaxKind.PointerType, TSyntaxKind.SetType,
      TSyntaxKind.ClassOfType, TSyntaxKind.FileType, TSyntaxKind.ProcedureType, TSyntaxKind.SubrangeType,
      TSyntaxKind.EnumType, TSyntaxKind.RecordType] then
    begin
      Exit(ANode[mIndex]);
    end;
  end;
end;

{ TIndexExtractor }

constructor TIndexExtractor.Create(const ATokens: TArray<TPascalToken>);
begin
  inherited Create;
  FReader := TIndexTokenReader.Create(ATokens);
  FSymbols := TList<TIndexSymbol>.Create;
  FForwards := TList<Integer>.Create;
  FState := Default(TIndexDeclarationState);
  FState.ResolutionOwner := -1;
end;

destructor TIndexExtractor.Destroy;
begin
  FForwards.Free;
  FSymbols.Free;
  FReader.Free;
  inherited;
end;

class function TIndexExtractor.DeclaredType(ANode: TSyntaxNode): string;
begin
  Result := TIndexTypeText.DeclaredType(ANode);
end;

class function TIndexExtractor.DeclaredTypeNode(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := TIndexTypeText.DeclaredTypeNode(ANode);
end;

class function TIndexExtractor.TypeText(ANode: TSyntaxNode): string;
begin
  Result := TIndexTypeText.TypeText(ANode);
end;

class function TIndexExtractor.GenericArgsText(ATypeRef: TSyntaxNode): string;
begin
  Result := TIndexTypeText.GenericArgsText(ATypeRef);
end;

class procedure TIndexExtractor.ParamInfo(ANode: TSyntaxNode; out AMin, AMax: Integer; out ATypes: TArray<string>);
begin
  TIndexTypeText.ParamInfo(ANode, AMin, AMax, ATypes);
end;

class function TIndexExtractor.HasNamePrefix(const AName, APrefix: string): Boolean;
begin
  Result := TIndexTypeText.HasNamePrefix(AName, APrefix);
end;

class function TIndexExtractor.NamingOf(ARoot: TSyntaxNode): TNamingCounts;
begin
  Result := TIndexTypeText.NamingOf(ARoot);
end;

function TIndexExtractor.NewSymbol(ANode: TSyntaxNode; const AName, AContainer: string;
  AKind: TIndexSymbolKind): TIndexSymbol;
begin
  Result := Default(TIndexSymbol);
  // Der Index führt die Namen ohne Escape-&, wie die Namensauflösung sie sucht (#1137).
  Result.Name := TPascalLexer.PlainName(AName);
  Result.Container := TPascalLexer.PlainName(AContainer);
  Result.Kind := AKind;
  Result.Range := TTextRange.Create(ANode.StartPos, ANode.EndPos);
  Result.SelectionRange := FReader.NameRange(ANode, Result.Name);
  Result.InInterface := FState.InInterface;
  // Erweiterungen für die Namensauflösung, Stufe 2 (#263).
  Result.AncestorArgs := FState.AncestorArgs;
  Result.TypeParams := TIndexTypeText.TypeParamsOf(ANode);
  Result.Visibility := TIndexVisibility.Public;
  if (AContainer <> '') and (AKind <> TIndexSymbolKind.EnumMember) then
  begin
    Result.Visibility := FState.Visibility;
  end;
  Result.VariantBranch := FState.VariantBranch;
  Result.ScopedEnum := FState.Scoped;
end;

procedure TIndexExtractor.SetTypeInfo(var ASymbol: TIndexSymbol; ANode: TSyntaxNode; const AName: string;
  AKind: TIndexSymbolKind);
var
  mTypeNode: TSyntaxNode;
  mTypeText: string;
begin
  mTypeText := '';
  if AKind in cTypedKinds then
  begin
    mTypeNode := TIndexTypeText.DeclaredTypeNode(ANode);
    ASymbol.TypeName := TIndexTypeText.DeclaredType(ANode);
    // type AnsiString(Codepage) ist ein eigener Stringtyp (RawByteString, UTF8String): Die Namensauflösung darf
    // ihn nicht bis AnsiString verfolgen, sonst meldet z. B. suspicious-string-pointer-cast "R ist AnsiString".
    if (AKind = TIndexSymbolKind.TypeAlias) and SameText(ASymbol.TypeName, 'AnsiString') and
      (mTypeNode.ChildCount > 0) then
    begin
      ASymbol.TypeName := '';
    end;
    if ASymbol.TypeName <> '' then
    begin
      ASymbol.TypeArgs := TIndexTypeText.GenericArgsText(mTypeNode);
      mTypeText := TIndexTypeText.TypeText(mTypeNode);
    end;
  end;
  // Inhalt für Hover, Detailpanel und Verwendungen ohne erneutes Lesen der Datei (#492).
  ASymbol.Signature := FReader.SignatureOf(ANode, AKind, AName, mTypeText);
end;

procedure TIndexExtractor.SetParamInfo(var ASymbol: TIndexSymbol; ANode: TSyntaxNode; AKind: TIndexSymbolKind);
var
  mMin, mMax: Integer;
begin
  if AKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine,
    TIndexSymbolKind.Property_] then
  begin
    TIndexTypeText.ParamInfo(ANode, mMin, mMax, ASymbol.ParamTypes);
    ASymbol.MinArgs := mMin;
    ASymbol.MaxArgs := mMax;
  end;
  ASymbol.IsDefault := (AKind = TIndexSymbolKind.Property_) and FReader.IsDefaultProperty(ANode);
  ASymbol.IsVirtual := (AKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
    TIndexTypeText.IsVirtualHeader(ANode);
end;

procedure TIndexExtractor.SetDirectives(var ASymbol: TIndexSymbol; ANode: TSyntaxNode; AKind: TIndexSymbolKind;
  const AContainer: string);
var
  mProcedureKind: string;
begin
  ASymbol.Directives := FReader.DirectivesOf(ANode, AKind, ASymbol.DeprecatedText);
  if ASymbol.IsDefault and (IndexText('default', ASymbol.Directives) < 0) then
  begin
    ASymbol.Directives := ASymbol.Directives + ['default'];
  end;
  // Methodenzeiger und Methodenreferenzen als Merkmal (#1326): Die Signatur kann bei langen Parameterlisten
  // vor "of object" abgeschnitten sein (TIndexSymbol.cMaxSignature).
  if AKind = TIndexSymbolKind.TypeAlias then
  begin
    mProcedureKind := FReader.ProcedureKindOf(TIndexTypeText.ProcedureTypeOf(ANode));
    if mProcedureKind <> '' then
    begin
      ASymbol.Directives := ASymbol.Directives + [mProcedureKind];
    end;
  end;
  // Klassenmitglieder (class var, class property, class function) tragen "class" vorn, damit Regeln wie
  // property-accessor-invalid (#1001) sie ohne die Datei erkennen.
  if (AContainer <> '') and (((AKind = TIndexSymbolKind.Field) and FState.ClassVar) or
    ((AKind in [TIndexSymbolKind.Property_, TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_]) and
    FReader.IsClassMember(ANode))) then
  begin
    ASymbol.Directives := ['class'] + ASymbol.Directives;
  end;
  AddKindEntries(ASymbol, ANode, AKind);
end;

procedure TIndexExtractor.AddKindEntries(var ASymbol: TIndexSymbol; ANode: TSyntaxNode; AKind: TIndexSymbolKind);
var
  mHeader: TSyntaxNode;
  mWord, mEntry: string;
begin
  // Arten ohne eigene Symbolart (L1): class operator, destructor, resourcestring, threadvar, message.
  if AKind in [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine] then
  begin
    mHeader := TIndexTypeText.HeaderOf(ANode);
    mWord := FReader.RoutineWord(mHeader);
    if (mWord = 'operator') or (mWord = 'destructor') then
    begin
      AddEntry(ASymbol, mWord);
    end;
    for mEntry in FReader.ExternalEntries(mHeader) do
    begin
      AddEntry(ASymbol, mEntry);
    end;
    AddEntry(ASymbol, FReader.MessageEntry(mHeader));
  end;
  if (FState.SectionWord <> '') and (AKind in [TIndexSymbolKind.Constant, TIndexSymbolKind.Variable,
    TIndexSymbolKind.Field]) then
  begin
    AddEntry(ASymbol, FState.SectionWord);
  end;
  for mEntry in FReader.ConstraintEntries(ANode) do
  begin
    AddEntry(ASymbol, mEntry);
  end;
  AddEntry(ASymbol, TargetEntry(ANode, AKind, ASymbol.TypeName));
  for mEntry in FState.Attributes do
  begin
    AddEntry(ASymbol, mEntry);
  end;
  FState.Attributes := nil;
end;

procedure TIndexExtractor.Add(ANode: TSyntaxNode; const AName, AContainer: string; AKind: TIndexSymbolKind;
  const AAncestors: TArray<string>);
var
  mSymbol: TIndexSymbol;
begin
  if AName = '' then
  begin
    Exit;
  end;
  mSymbol := NewSymbol(ANode, AName, AContainer, AKind);
  mSymbol.Ancestors := AAncestors;
  SetTypeInfo(mSymbol, ANode, AName, AKind);
  SetParamInfo(mSymbol, ANode, AKind);
  SetDirectives(mSymbol, ANode, AKind, AContainer);
  mSymbol.Rationale := RationaleOf(TRationaleScanner.ForNode(FReader.Tokens, ANode));
  if FState.IsForward then
  begin
    FForwards.Add(FSymbols.Count);
  end;
  FSymbols.Add(mSymbol);
end;

procedure TIndexExtractor.AddNames(ANode: TSyntaxNode; const AContainer: string; AKind: TIndexSymbolKind);
var
  mName: string;
  mAttributes: TArray<string>;
  mType: TSyntaxNode;
begin
  // A, B: Integer; Attribute davor gelten für jeden Namen.
  mAttributes := FState.Attributes;
  mType := AnonymousTypeOf(ANode);
  for mName in ANode.Name.Split([',']) do
  begin
    FState.Attributes := mAttributes;
    Add(ANode, mName.Trim, AContainer, AKind, nil);
    // Anonymer Typ (L1): Mitglieder mit dem Feld- bzw. Variablennamen als Container.
    if (mType <> nil) and (mName.Trim <> '') then
    begin
      AddAnonymousMembers(mType, QualifiedOf(AContainer, TPascalLexer.PlainName(mName.Trim)));
    end;
  end;
  FState.Attributes := nil;
end;

procedure TIndexExtractor.AddAnonymousMembers(AType: TSyntaxNode; const AContainer: string);
var
  mVisibility: TIndexVisibility;
  mOwner: Integer;
  mClassVar: Boolean;
  mSection: string;
begin
  case AType.Kind of
    TSyntaxKind.EnumType:
      begin
        FState.Scoped := FReader.ScopedAt(AType.StartOffset);
        AddEnumMembers(AType, AContainer);
      end;
    TSyntaxKind.RecordType:
      begin
        mVisibility := FState.Visibility;
        mOwner := FState.ResolutionOwner;
        mClassVar := FState.ClassVar;
        mSection := FState.SectionWord;
        FState.Visibility := TIndexVisibility.Public;
        FState.ResolutionOwner := -1;
        FState.ClassVar := False;
        FState.SectionWord := '';
        try
          AddMembers(AType, AContainer);
        finally
          FState.Visibility := mVisibility;
          FState.ResolutionOwner := mOwner;
          FState.ClassVar := mClassVar;
          FState.SectionWord := mSection;
        end;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function TIndexExtractor.TargetEntry(ANode: TSyntaxNode; AKind: TIndexSymbolKind; const ATypeName: string): string;
var
  mBody, mElement: TSyntaxNode;
  mForm, mType, mBounds: string;
  mIndex: Integer;
begin
  Result := '';
  if not (AKind in [TIndexSymbolKind.TypeAlias, TIndexSymbolKind.ClassType, TIndexSymbolKind.Constant,
    TIndexSymbolKind.Variable, TIndexSymbolKind.Field]) or (ATypeName <> '') then
  begin
    Exit;
  end;
  mBody := TargetNodeOf(ANode);
  if mBody = nil then
  begin
    Exit;
  end;
  mType := '';
  case mBody.Kind of
    TSyntaxKind.PointerType:
      begin
        mForm := '^';
        mType := TIndexTypeText.TypeText(mBody.FindChild(TSyntaxKind.TypeReference));
      end;
    TSyntaxKind.ClassOfType:
      begin
        mForm := 'class of';
        mType := TIndexTypeText.TypeText(mBody.FindChild(TSyntaxKind.TypeReference));
      end;
    TSyntaxKind.FileType:
      begin
        mForm := 'file of';
        mType := TIndexTypeText.TypeText(mBody.FindChild(TSyntaxKind.TypeReference));
      end;
    TSyntaxKind.SetType:
      begin
        mForm := 'set of';
        if mBody.ChildCount > 0 then
        begin
          mType := ElementText(mBody[0]);
        end;
      end;
    TSyntaxKind.ArrayType:
      begin
        // array[0..9, Boolean] of T: alle Kinder außer dem letzten sind Grenzen.
        mBounds := '';
        for mIndex := 0 to mBody.ChildCount - 2 do
        begin
          if mBounds <> '' then
          begin
            mBounds := mBounds + ', ';
          end;
          mBounds := mBounds + FReader.NodeText(mBody[mIndex]);
        end;
        if mBounds = '' then
        begin
          mForm := 'array of';
        end
        else
        begin
          mForm := 'array[' + mBounds + '] of';
        end;
        mElement := nil;
        if mBody.ChildCount > 0 then
        begin
          mElement := mBody[mBody.ChildCount - 1];
        end;
        mType := ElementText(mElement);
      end;
    TSyntaxKind.ProcedureType:
      begin
        if FReader.RoutineWord(mBody) = 'function' then
        begin
          mForm := 'function';
        end
        else if SameText(mBody.Name, 'reference') and FReader.NodeText(mBody).Contains(' function') then
        begin
          mForm := 'function';
        end
        else
        begin
          mForm := 'procedure';
        end;
        mType := TIndexTypeText.TypeText(mBody.FindChild(TSyntaxKind.TypeReference));
      end;
    TSyntaxKind.SubrangeType:
      begin
        mForm := 'range';
        mType := FReader.NodeText(mBody);
      end;
    TSyntaxKind.EnumType:
      mForm := 'enum';
    TSyntaxKind.RecordType:
      mForm := 'record';
  else
    Exit;
  end;
  Result := TIndexSymbol.cTargetPrefix + mForm + '=' + TIndexTokenReader.Shortened(mType, TIndexSymbol.cMaxSignature);
end;

function TIndexExtractor.ElementText(AElement: TSyntaxNode): string;
begin
  // Elementtyp einer Menge bzw. eines Arrays: benannt wie geschrieben (TList<T>, array of Byte), anonyme
  // Aufzählungen und Records ohne Text, sonst der Text der Deklaration (1..9, procedure of object).
  Result := '';
  if AElement = nil then
  begin
    Exit;
  end;
  case AElement.Kind of
    TSyntaxKind.TypeReference:
      Result := TIndexTypeText.TypeText(AElement);
    TSyntaxKind.EnumType, TSyntaxKind.RecordType:
      Result := '';
  else
    Result := FReader.NodeText(AElement);
  end;
end;

procedure TIndexExtractor.TakeAttributes(AAttribute: TSyntaxNode);
var
  mIndex: Integer;
  mName: string;
begin
  // [Weak], [Weak, Unsafe], [TestCase('A', '1')]: je Ausdruck sein Name.
  for mIndex := 0 to AAttribute.ChildCount - 1 do
  begin
    mName := AAttribute[mIndex].Name;
    if mName <> '' then
    begin
      FState.Attributes := FState.Attributes + [TIndexSymbol.cAttributePrefix + mName];
    end;
  end;
end;

procedure TIndexExtractor.EnterSection(ASection: TSyntaxNode; out ASaved: string);
begin
  ASaved := FState.SectionWord;
  if MatchText(ASection.Name, ['resourcestring', 'threadvar']) then
  begin
    FState.SectionWord := LowerCase(ASection.Name);
  end
  else
  begin
    FState.SectionWord := '';
  end;
end;

procedure TIndexExtractor.AddTypeSymbol(ADecl, ABody: TSyntaxNode; const AContainer: string);
var
  mKind: TIndexSymbolKind;
  mAncestors, mArgs: TArray<string>;
begin
  mKind := KindOfBody(ABody);
  mAncestors := AncestorsOf(ABody, mArgs);
  FState.AncestorArgs := mArgs;
  FState.IsForward := (ABody <> nil) and (ABody.Kind = TSyntaxKind.ForwardType);
  FState.Scoped := (mKind = TIndexSymbolKind.EnumType) and FReader.ScopedAt(ADecl.StartOffset);
  try
    Add(ADecl, ADecl.Name, AContainer, mKind, mAncestors);
  finally
    FState.AncestorArgs := nil;
    FState.IsForward := False;
  end;
end;

procedure TIndexExtractor.AddEnumMembers(ABody: TSyntaxNode; const AQualified: string);
var
  mIndex: Integer;
begin
  // Enum-Werte sind ohne SCOPEDENUMS auch auf Unit-Ebene sichtbar; der
  // Container hält den Typ fest, ScopedEnum den Schalter (#849), die Namensauflösung entscheidet.
  try
    for mIndex := 0 to ABody.ChildCount - 1 do
    begin
      if ABody[mIndex].Kind = TSyntaxKind.Identifier then
      begin
        Add(ABody[mIndex], ABody[mIndex].Name, AQualified, TIndexSymbolKind.EnumMember, nil);
      end;
    end;
  finally
    FState.Scoped := False;
  end;
end;

procedure TIndexExtractor.AddBodyMembers(ABody: TSyntaxNode; const AQualified: string; ACount: Integer);
var
  mVisibility: TIndexVisibility;
  mOwner: Integer;
begin
  // Verschachtelte Typen haben ihre eigene Sichtbarkeit; danach gilt wieder die äußere.
  mVisibility := FState.Visibility;
  mOwner := FState.ResolutionOwner;
  FState.Visibility := TIndexVisibility.Public;
  FState.ResolutionOwner := -1;
  if FSymbols.Count > ACount then
  begin
    FState.ResolutionOwner := ACount;
  end;
  try
    AddMembers(ABody, AQualified);
  finally
    FState.Visibility := mVisibility;
    FState.ResolutionOwner := mOwner;
  end;
end;

procedure TIndexExtractor.AddType(ADecl: TSyntaxNode; const AContainer: string);
var
  mBody: TSyntaxNode;
  mCount: Integer;
begin
  mBody := TypeBodyOf(ADecl);
  mCount := FSymbols.Count;
  AddTypeSymbol(ADecl, mBody, AContainer);
  if mBody = nil then
  begin
    Exit;
  end;
  if mBody.Kind = TSyntaxKind.EnumType then
  begin
    AddEnumMembers(mBody, QualifiedOf(AContainer, ADecl.Name));
  end
  else if (mBody.Kind = TSyntaxKind.SetType) and (mBody.ChildCount > 0) and
    (mBody[0].Kind = TSyntaxKind.EnumType) then
  begin
    // set of (a, b) (L1): Die Werte der anonymen Aufzählung gehören zur Menge.
    FState.Scoped := FReader.ScopedAt(mBody[0].StartOffset);
    AddEnumMembers(mBody[0], QualifiedOf(AContainer, ADecl.Name));
  end
  else if mBody.Kind in cMemberBodies then
  begin
    AddBodyMembers(mBody, QualifiedOf(AContainer, ADecl.Name), mCount);
  end;
end;

procedure TIndexExtractor.AddResolution(AHeader: TSyntaxNode);
var
  mSymbol: TIndexSymbol;
begin
  if (FState.ResolutionOwner < 0) or (AHeader.Name = '') or (AHeader.ResolutionTarget = '') then
  begin
    Exit;
  end;
  mSymbol := FSymbols[FState.ResolutionOwner];
  mSymbol.Resolutions := mSymbol.Resolutions + [AHeader.Name + '=' + AHeader.ResolutionTarget];
  FSymbols[FState.ResolutionOwner] := mSymbol;
end;

procedure TIndexExtractor.AddHeader(AHeader: TSyntaxNode; const AContainer: string);
begin
  // Methodenzuordnung procedure IFoo.Bar = MyBar ist kein Mitglied (#849), sondern steht am Typ.
  if AHeader.IsMethodResolution then
  begin
    AddResolution(AHeader);
  end
  else if FReader.IsConstructor(AHeader) then
  begin
    Add(AHeader, AHeader.Name, AContainer, TIndexSymbolKind.Constructor_, nil);
  end
  else
  begin
    Add(AHeader, AHeader.Name, AContainer, TIndexSymbolKind.Method, nil);
  end;
end;

procedure TIndexExtractor.AddCaseItem(AItem: TSyntaxNode; const AContainer: string);
var
  mOuter: string;
begin
  mOuter := FState.VariantBranch;
  if FState.VariantBranch = '' then
  begin
    FState.VariantBranch := AItem.Name;
  end
  else
  begin
    FState.VariantBranch := FState.VariantBranch + ' › ' + AItem.Name;
  end;
  try
    AddMembers(AItem, AContainer);
  finally
    FState.VariantBranch := mOuter;
  end;
end;

procedure TIndexExtractor.AddMember(AChild: TSyntaxNode; const AContainer: string);
var
  mClassVar: Boolean;
  mSection: string;
begin
  case AChild.Kind of
    TSyntaxKind.Visibility:
      begin
        FState.Visibility := VisibilityOf(AChild.Name);
        AddMembers(AChild, AContainer);
      end;
    TSyntaxKind.TypeSection, TSyntaxKind.VariantPart:
      AddMembers(AChild, AContainer);
    TSyntaxKind.ConstSection:
      begin
        EnterSection(AChild, mSection);
        try
          AddMembers(AChild, AContainer);
        finally
          FState.SectionWord := mSection;
        end;
      end;
    TSyntaxKind.VarSection:
      begin
        mClassVar := FState.ClassVar;
        FState.ClassVar := (AContainer <> '') and FReader.IsClassMember(AChild);
        EnterSection(AChild, mSection);
        try
          AddMembers(AChild, AContainer);
        finally
          FState.ClassVar := mClassVar;
          FState.SectionWord := mSection;
        end;
      end;
    TSyntaxKind.Attribute:
      TakeAttributes(AChild);
    TSyntaxKind.CaseItem:
      AddCaseItem(AChild, AContainer);
    TSyntaxKind.TypeDecl:
      AddType(AChild, AContainer);
    TSyntaxKind.ConstDecl:
      Add(AChild, AChild.Name, AContainer, TIndexSymbolKind.Constant, nil);
    TSyntaxKind.VarDecl, TSyntaxKind.Field:
      AddNames(AChild, AContainer, TIndexSymbolKind.Field);
    TSyntaxKind.PropertyDecl:
      Add(AChild, AChild.Name, AContainer, TIndexSymbolKind.Property_, nil);
    TSyntaxKind.RoutineHeader:
      AddHeader(AChild, AContainer);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TIndexExtractor.AddMembers(ABody: TSyntaxNode; const AContainer: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    AddMember(ABody[mIndex], AContainer);
    // Attribute gelten nur für die Deklaration direkt dahinter (L1).
    if ABody[mIndex].Kind <> TSyntaxKind.Attribute then
    begin
      FState.Attributes := nil;
    end;
  end;
end;

procedure TIndexExtractor.AddRoutine(ANode: TSyntaxNode);
var
  mName: string;
  mDot: Integer;
begin
  // TFoo.Bar in implementation: Methode von TFoo; sonst freie Routine.
  mName := ANode.Name;
  mDot := mName.LastIndexOf('.');
  if mDot < 0 then
  begin
    Add(ANode, mName, '', TIndexSymbolKind.Routine, nil);
  end
  else if FReader.IsConstructor(ANode) then
  begin
    Add(ANode, mName.Substring(mDot + 1), mName.Substring(0, mDot), TIndexSymbolKind.Constructor_, nil);
  end
  else
  begin
    Add(ANode, mName.Substring(mDot + 1), mName.Substring(0, mDot), TIndexSymbolKind.Method, nil);
  end;
end;

procedure TIndexExtractor.AddDeclarations(ANode: TSyntaxNode);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mSection: string;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := ANode[mIndex];
    case mChild.Kind of
      TSyntaxKind.TypeSection:
        AddDeclarations(mChild);
      TSyntaxKind.ConstSection, TSyntaxKind.VarSection:
        begin
          EnterSection(mChild, mSection);
          try
            AddDeclarations(mChild);
          finally
            FState.SectionWord := mSection;
          end;
        end;
      TSyntaxKind.Attribute:
        TakeAttributes(mChild);
      TSyntaxKind.TypeDecl:
        AddType(mChild, '');
      TSyntaxKind.ConstDecl:
        Add(mChild, mChild.Name, '', TIndexSymbolKind.Constant, nil);
      TSyntaxKind.VarDecl:
        AddNames(mChild, '', TIndexSymbolKind.Variable);
      TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl:
        AddRoutine(mChild);
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
    if mChild.Kind <> TSyntaxKind.Attribute then
    begin
      FState.Attributes := nil;
    end;
  end;
end;

procedure TIndexExtractor.DropForwards;
var
  mIndex: Integer;
  mForwards: TArray<Boolean>;
  mFull: TDictionary<string, Boolean>;
begin
  if FForwards.Count = 0 then
  begin
    Exit;
  end;
  SetLength(mForwards, FSymbols.Count);
  for mIndex in FForwards do
  begin
    mForwards[mIndex] := True;
  end;
  mFull := TDictionary<string, Boolean>.Create;
  try
    for mIndex := 0 to FSymbols.Count - 1 do
    begin
      if not mForwards[mIndex] then
      begin
        mFull.AddOrSetValue(UpperCase(FSymbols[mIndex].QualifiedName), True);
      end;
    end;
    for mIndex := FForwards.Count - 1 downto 0 do
    begin
      if mFull.ContainsKey(UpperCase(FSymbols[FForwards[mIndex]].QualifiedName)) then
      begin
        FSymbols.Delete(FForwards[mIndex]);
      end;
    end;
  finally
    mFull.Free;
  end;
  FForwards.Clear;
end;

procedure TIndexExtractor.ReadUnitInfo(ARoot: TSyntaxNode; var AUnit: TUnitIndex);
begin
  AUnit.InterfaceUses := nil;
  AUnit.ImplementationUses := nil;
  AUnit.Requires := nil;
  AUnit.Directives := nil;
  AUnit.DeprecatedText := '';
  AUnit.Rationale := RationaleOf(TRationaleScanner.ForUnit(FReader.Tokens, ARoot));
  AUnit.HasInitialization := (ARoot.FindChild(TSyntaxKind.InitializationSection) <> nil) or
    (ARoot.FindChild(TSyntaxKind.FinalizationSection) <> nil);
  if ARoot.Kind = TSyntaxKind.UnitFile then
  begin
    FReader.UnitHints(AUnit);
    AUnit.InterfaceUses := TIndexTypeText.UsesOf(ARoot.FindChild(TSyntaxKind.InterfaceSection));
    AUnit.ImplementationUses := TIndexTypeText.UsesOf(ARoot.FindChild(TSyntaxKind.ImplementationSection));
  end
  else
  begin
    // program, library, package: alles gilt als implementation. Beim package (L1) zählen alle Klauseln: contains
    // (die Units des Packages) wie uses, requires (Packages) getrennt.
    AUnit.ImplementationUses := TIndexTypeText.UsesOf(ARoot, ['uses', 'contains', '']);
    AUnit.Requires := TIndexTypeText.UsesOf(ARoot, ['requires']);
  end;
end;

procedure TIndexExtractor.Walk(ARoot: TSyntaxNode; var AUnit: TUnitIndex);
var
  mIndex: Integer;
  mChild: TSyntaxNode;
  mInlineRefs: TIndexInlineRefs;
begin
  ReadUnitInfo(ARoot, AUnit);
  for mIndex := 0 to ARoot.ChildCount - 1 do
  begin
    mChild := ARoot[mIndex];
    if mChild.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
    begin
      FState.InInterface := mChild.Kind = TSyntaxKind.InterfaceSection;
      AddDeclarations(mChild);
    end;
  end;
  if ARoot.Kind <> TSyntaxKind.UnitFile then
  begin
    FState.InInterface := False;
    AddDeclarations(ARoot);
  end;
  DropForwards;
  if ARoot.Kind = TSyntaxKind.UnitFile then
  begin
    mInlineRefs := TIndexInlineRefs.Create(FSymbols, FReader);
    try
      mInlineRefs.Add(ARoot.FindChild(TSyntaxKind.ImplementationSection));
    finally
      mInlineRefs.Free;
    end;
  end;
  AUnit.Symbols := FSymbols.ToArray;
  AUnit.Naming := TIndexTypeText.NamingOf(ARoot);
end;

class function TIndexExtractor.Extract(ATree: TSyntaxTree; const AFileName: string): TUnitIndex;
var
  mExtractor: TIndexExtractor;
begin
  Result := Default(TUnitIndex);
  Result.FileName := AFileName;
  Result.UnitName := ATree.Root.Name;
  if Result.UnitName = '' then
  begin
    Result.UnitName := FileNameToUnitName(AFileName);
  end;
  mExtractor := TIndexExtractor.Create(ATree.Tokens);
  try
    mExtractor.Walk(ATree.Root, Result);
  finally
    mExtractor.Free;
  end;
end;

/// <summary>Routine, Methode oder Konstruktor?</summary>
function IsRoutineKind(AKind: TIndexSymbolKind): Boolean;
begin
  Result := AKind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_];
end;

/// <summary>Schlüssel für gleichnamige Routinen: Typ und Name groß.</summary>
function RoutineKey(const ASymbol: TIndexSymbol): string;
begin
  Result := UpperCase(ASymbol.Container + '.' + ASymbol.Name);
end;

function SameParamList(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  mIndex := 0;
  while Result and (mIndex <= High(A)) do
  begin
    Result := SameText(A[mIndex].Replace(' ', ''), B[mIndex].Replace(' ', ''));
    Inc(mIndex);
  end;
end;

/// <summary>Gehört der Eintrag ADirective eines Rumpfs an die interface-Deklaration (DLL-Angaben, inline)?</summary>
function IsMergedEntry(const ADirective: string): Boolean;
begin
  Result := SameText(ADirective, 'external') or SameText(ADirective, 'delayed') or SameText(ADirective, 'inline') or
    StartsText('external:', ADirective) or StartsText('name:', ADirective) or StartsText('index:', ADirective);
end;

/// <summary>Deklaration im interface zum Rumpf ABody aus ACandidates (Nummern in ASymbols); -1, wenn sie sich bei
/// Überladungen nicht eindeutig bestimmen lässt.</summary>
function DeclarationOf(const ASymbols: TArray<TIndexSymbol>; const ABody: TIndexSymbol;
  const ACandidates: TList<Integer>): Integer;
var
  mCandidate: Integer;
begin
  if ACandidates.Count = 1 then
  begin
    Exit(ACandidates[0]);
  end;
  Result := -1;
  for mCandidate in ACandidates do
  begin
    if SameParamList(ASymbols[mCandidate].ParamTypes, ABody.ParamTypes) then
    begin
      if Result >= 0 then
      begin
        Exit(-1);
      end;
      Result := mCandidate;
    end;
  end;
end;

/// <summary>DLL-Angaben, inline und Zeile des Rumpfs ABody an die Deklaration ADeclaration.</summary>
procedure MergeBody(var ADeclaration: TIndexSymbol; const ABody: TIndexSymbol);
var
  mDirective, mLine: string;
begin
  for mDirective in ABody.Directives do
  begin
    if IsMergedEntry(mDirective) and (IndexText(mDirective, ADeclaration.Directives) < 0) then
    begin
      ADeclaration.Directives := ADeclaration.Directives + [mDirective];
    end;
  end;
  if SameText(ABody.FileName, ADeclaration.FileName) and
    (ADeclaration.DirectiveValue(TIndexSymbol.cImplementationPrefix) = '') then
  begin
    mLine := TIndexSymbol.cImplementationPrefix + ':' + IntToStr(ABody.SelectionRange.StartPos.Line);
    ADeclaration.Directives := ADeclaration.Directives + [mLine];
  end;
  if (ADeclaration.InlineRefs = nil) and (ABody.InlineRefs <> nil) then
  begin
    ADeclaration.InlineRefs := ABody.InlineRefs;
  end;
end;

class function TIndexExtractor.DropImplementationDuplicates(var AUnit: TUnitIndex): Integer;
var
  mDeclarations: TObjectDictionary<string, TList<Integer>>;
  mCandidates: TList<Integer>;
  mKept: TList<TIndexSymbol>;
  mPosition, mTarget: Integer;
  mSymbols: TArray<TIndexSymbol>;
begin
  Result := 0;
  mSymbols := AUnit.Symbols;
  mDeclarations := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  mKept := TList<TIndexSymbol>.Create;
  try
    // Deklarationen im interface: freie Routinen und Methoden der Typen dort.
    for mPosition := 0 to High(mSymbols) do
    begin
      if mSymbols[mPosition].InInterface and IsRoutineKind(mSymbols[mPosition].Kind) then
      begin
        if not mDeclarations.TryGetValue(RoutineKey(mSymbols[mPosition]), mCandidates) then
        begin
          mCandidates := TList<Integer>.Create;
          mDeclarations.Add(RoutineKey(mSymbols[mPosition]), mCandidates);
        end;
        mCandidates.Add(mPosition);
      end;
    end;
    if mDeclarations.Count = 0 then
    begin
      Exit;
    end;
    // Erst übertragen, dann entfernen: Die Nummern der Deklarationen bleiben dabei gültig.
    for mPosition := 0 to High(mSymbols) do
    begin
      if mSymbols[mPosition].InInterface or not IsRoutineKind(mSymbols[mPosition].Kind) or
        not mDeclarations.TryGetValue(RoutineKey(mSymbols[mPosition]), mCandidates) then
      begin
        Continue;
      end;
      mTarget := DeclarationOf(mSymbols, mSymbols[mPosition], mCandidates);
      if mTarget >= 0 then
      begin
        MergeBody(mSymbols[mTarget], mSymbols[mPosition]);
      end;
    end;
    for mPosition := 0 to High(mSymbols) do
    begin
      if not mSymbols[mPosition].InInterface and IsRoutineKind(mSymbols[mPosition].Kind) and
        mDeclarations.ContainsKey(RoutineKey(mSymbols[mPosition])) then
      begin
        Inc(Result);
      end
      else
      begin
        mKept.Add(mSymbols[mPosition]);
      end;
    end;
    if Result > 0 then
    begin
      AUnit.Symbols := mKept.ToArray;
    end
    else
    begin
      AUnit.Symbols := mSymbols;
    end;
  finally
    mKept.Free;
    mDeclarations.Free;
  end;
end;

class function TIndexExtractor.BlankInactive(const AText: string; const ADefines: TArray<string>): string;
var
  mIncludes: TArray<string>;
  mConditionals: TArray<TConditionalRange>;
begin
  Result := TIndexConditions.BlankInactive(AText, '', ADefines, nil, mIncludes, mConditionals);
end;

type
  TUsageBucket = class
    FName: string;
    FPositions: TList<TTextPosition>;
    constructor Create(const AName: string);
    destructor Destroy; override;
  end;

constructor TUsageBucket.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
  FPositions := TList<TTextPosition>.Create;
end;

destructor TUsageBucket.Destroy;
begin
  FPositions.Free;
  inherited;
end;

function PositionKey(const APosition: TTextPosition): Int64;
begin
  Result := (Int64(APosition.Line) shl 32) or Cardinal(APosition.Character);
end;

/// <summary>Name der Verwendung am Token AToken ohne Escape-&amp;; '' für Schlüsselwörter, Direktiven, Self, Result
/// und Deklarationsstellen (ADeclared).</summary>
function UsageName(const AToken: TPascalToken; ADeclared: TDictionary<Int64, Boolean>): string;
begin
  if AToken.Kind <> TPascalTokenKind.Identifier then
  begin
    Exit('');
  end;
  Result := AToken.Text;
  if Result.StartsWith('&') then
  begin
    Result := Copy(Result, 2, MaxInt);
  end;
  if MatchText(Result, ['Self', 'Result']) or (IndexText(Result, cDirectiveWords) >= 0) or
    ADeclared.ContainsKey(PositionKey(AToken.StartPos)) then
  begin
    Result := '';
  end;
end;

/// <summary>Verwendungen aus ABuckets, nach Name sortiert.</summary>
function UsagesOf(ABuckets: TObjectDictionary<string, TUsageBucket>): TArray<TIndexUsage>;
var
  mNames: TArray<string>;
  mBucket: TUsageBucket;
  mIndex: Integer;
begin
  mNames := ABuckets.Keys.ToArray;
  TArray.Sort<string>(mNames);
  SetLength(Result, Length(mNames));
  for mIndex := 0 to High(mNames) do
  begin
    mBucket := ABuckets[mNames[mIndex]];
    Result[mIndex].Name := mBucket.FName;
    Result[mIndex].Positions := mBucket.FPositions.ToArray;
  end;
end;

/// <summary>Verwendungen aller Bezeichner in ATokens außer an den Deklarationsstellen von ASymbols
/// (#492), nach Name sortiert; Schlüsselwörter, Direktiven, Self und Result zählen nicht.</summary>
function CollectUsages(const ATokens: TArray<TPascalToken>; const ASymbols: TArray<TIndexSymbol>):
  TArray<TIndexUsage>;
var
  mDeclared: TDictionary<Int64, Boolean>;
  mBuckets: TObjectDictionary<string, TUsageBucket>;
  mBucket: TUsageBucket;
  mSymbol: TIndexSymbol;
  mToken: TPascalToken;
  mName: string;
begin
  mDeclared := TDictionary<Int64, Boolean>.Create;
  mBuckets := TObjectDictionary<string, TUsageBucket>.Create([doOwnsValues]);
  try
    // Die Deklaration selbst ist keine Verwendung; Symbole aus $I-Dateien stehen woanders.
    for mSymbol in ASymbols do
    begin
      if mSymbol.FileName = '' then
      begin
        mDeclared.AddOrSetValue(PositionKey(mSymbol.SelectionRange.StartPos), True);
      end;
    end;
    for mToken in ATokens do
    begin
      mName := UsageName(mToken, mDeclared);
      if mName = '' then
      begin
        Continue;
      end;
      if not mBuckets.TryGetValue(UpperCase(mName), mBucket) then
      begin
        mBucket := TUsageBucket.Create(mName);
        mBuckets.Add(UpperCase(mName), mBucket);
      end;
      mBucket.FPositions.Add(mToken.StartPos);
    end;
    Result := UsagesOf(mBuckets);
  finally
    mBuckets.Free;
    mDeclared.Free;
  end;
end;

/// <summary>Position hinter dem Schluss AClose ab AIndex; hinter dem Text, wenn er fehlt.</summary>
function ClosingAfter(const AText, AClose: string; AIndex: Integer): Integer;
begin
  Result := PosEx(AClose, AText, AIndex);
  if Result = 0 then
  begin
    Result := Length(AText) + 1;
  end
  else
  begin
    Inc(Result, Length(AClose));
  end;
end;

/// <summary>Erstes Zeichen hinter dem Leerzeichen oder Kommentar an AIndex; AIndex, wenn dort keins beginnt.
/// </summary>
function TriviaEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  if CharInSet(AText[AIndex], [#1..' ']) then
  begin
    Result := AIndex + 1;
  end
  else if AText[AIndex] = '{' then
  begin
    Result := ClosingAfter(AText, '}', AIndex);
  end
  else if Copy(AText, AIndex, 2) = '(*' then
  begin
    Result := ClosingAfter(AText, '*)', AIndex);
  end
  else if Copy(AText, AIndex, 2) = '//' then
  begin
    while (Result <= Length(AText)) and not CharInSet(AText[Result], [#10, #13]) do
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Erstes Wort von AText hinter Leerraum und Kommentaren, klein.</summary>
function FirstWord(const AText: string): string;
var
  mIndex, mNext, mStart: Integer;
begin
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mNext := TriviaEnd(AText, mIndex);
    if mNext = mIndex then
    begin
      Break;
    end;
    mIndex := mNext;
  end;
  mStart := mIndex;
  while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
  begin
    Inc(mIndex);
  end;
  Result := LowerCase(Copy(AText, mStart, mIndex - mStart));
end;

function Shifted(const APosition: TTextPosition; ALines: Integer): TTextPosition;
begin
  Result := TTextPosition.Create(APosition.Line - ALines, APosition.Character);
end;

/// <summary>Innerster Rumpf (class, object, record, interface, helper) unter ANode, der AOffset enthält; sonst nil.
/// </summary>
function BodyAt(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  mIndex: Integer;
  mInner: TSyntaxNode;
begin
  Result := nil;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if (ANode[mIndex].StartOffset < AOffset) and (AOffset < ANode[mIndex].EndOffset) then
    begin
      if ANode[mIndex].Kind in cMemberBodies then
      begin
        Result := ANode[mIndex];
      end;
      mInner := BodyAt(ANode[mIndex], AOffset);
      if mInner <> nil then
      begin
        Result := mInner;
      end;
      Exit;
    end;
  end;
end;

/// <summary>Kopf des Hilfstyps für eine .inc an AOffset in ABody: Art des Rumpfs und die dort geltende
/// Sichtbarkeit, z. B. "type TDpccIncludeHost__ = class public" und ein Zeilenumbruch.</summary>
function HostHead(ABody: TSyntaxNode; AOffset: Integer): string;
var
  mIndex: Integer;
  mVisibility: string;
begin
  mVisibility := '';
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    if (ABody[mIndex].Kind = TSyntaxKind.Visibility) and (ABody[mIndex].StartOffset < AOffset) then
    begin
      mVisibility := ABody[mIndex].Name;
    end;
  end;
  case ABody.Kind of
    TSyntaxKind.RecordType:
      Result := 'record';
    TSyntaxKind.InterfaceType:
      Result := 'interface';
    TSyntaxKind.ObjectType:
      Result := 'object';
  else
    Result := 'class';
  end;
  Result := 'type' + #10 + cIncludeHost + ' = ' + Result + ' ' + mVisibility + #10;
end;

/// <summary>Inhalt einer .inc als eine Zeile für die Signatur einer Konstanten (#849).</summary>
function OneLine(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := AText;
  for mIndex := 1 to Length(Result) do
  begin
    if CharInSet(Result[mIndex], [#9, #10, #13]) then
    begin
      Result[mIndex] := ' ';
    end;
  end;
  Result := Trim(Result);
  while Pos('  ', Result) > 0 do
  begin
    Result := StringReplace(Result, '  ', ' ', [rfReplaceAll]);
  end;
  while Result.EndsWith(';') do
  begin
    Result := Copy(Result, 1, Length(Result) - 1).TrimRight;
  end;
end;

/// <summary>Zuletzt geöffneter Deklarationsabschnitt hinter AToken, für Dateien ohne eigenes Schlüsselwort.
/// </summary>
function SectionAfter(const AToken: TPascalToken; const ASection: string): string;
begin
  Result := ASection;
  if (AToken.Kind = TPascalTokenKind.Keyword) and
    MatchText(AToken.Text, ['type', 'const', 'var', 'resourcestring', 'threadvar']) then
  begin
    Result := LowerCase(AToken.Text);
  end
  else if AToken.IsKeyword('begin') or AToken.IsKeyword('implementation') or AToken.IsKeyword('interface') then
  begin
    Result := '';
  end;
end;

/// <summary>Typ eines Symbols aus einer .inc im Hilfstyp: TDpccIncludeHost__ wird zum umgebenden Typ AHost.
/// </summary>
function HostContainer(const AContainer, AHost: string): string;
begin
  Result := AContainer;
  if AHost = '' then
  begin
    Exit;
  end;
  if SameText(AContainer, cIncludeHost) then
  begin
    Result := AHost;
  end
  else if StartsText(cIncludeHost + '.', AContainer) then
  begin
    Result := AHost + Copy(AContainer, Length(cIncludeHost) + 1, MaxInt);
  end;
end;

/// <summary>Symbol ASymbol aus der .inc AFile an seinen Platz in der Unit: Typ, Datei und um AShift Zeilen
/// verschobene Stellen (für die vorangestellten Zeilen).</summary>
function Relocated(const ASymbol: TIndexSymbol; const AFile, AHost: string; AShift: Integer;
  AInInterface: Boolean): TIndexSymbol;
begin
  Result := ASymbol;
  Result.Container := HostContainer(ASymbol.Container, AHost);
  if Result.FileName = '' then
  begin
    Result.FileName := AFile;
    Result.Range := TTextRange.Create(Shifted(Result.Range.StartPos, AShift), Shifted(Result.Range.EndPos, AShift));
    Result.SelectionRange := TTextRange.Create(Shifted(Result.SelectionRange.StartPos, AShift),
      Shifted(Result.SelectionRange.EndPos, AShift));
  end;
  Result.InInterface := AInInterface;
end;

type
  /// <summary>Fügt die Deklarationen aktiver $I-Dateien in den Eintrag einer Unit ein (#500).</summary>
  TIncludeMerger = class
  private
    FTree: TSyntaxTree;
    FFileName: string;
    FDefines: TArray<string>;
    FResolver: TIncludeResolver;
    FStack: TArray<string>;
    FSymbols: TList<TIndexSymbol>;
    FIncludes: TArray<string>;
    FImplementationOffset: Integer;
    procedure AddInclude(const AFile: string);
    /// <summary>Wert einer Konstanten (V = {$I commit.inc};, #849): Inhalt in die Signatur, keine Deklarationen.
    /// </summary>
    procedure ReplaceValue(const AToken: TPascalToken; const AText: string);
    procedure AddSymbols(const AIncluded: TUnitIndex; const AFile, AHost: string; AShift: Integer;
      AInInterface: Boolean);
    procedure AddFile(const AToken: TPascalToken; const ASection, AFile, AText: string);
    procedure TakeDirective(const AToken, APrevious: TPascalToken; const ASection: string);
  public
    constructor Create(ATree: TSyntaxTree; const AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; const AStack: TArray<string>);
    destructor Destroy; override;
    procedure Merge(var AUnit: TUnitIndex);
    class function ExtractLevel(const AText, AFileName: string; const ADefines: TArray<string>;
      const AResolver: TIncludeResolver; const AStack: TArray<string>; AUsages, APatterns: Boolean): TUnitIndex;
      static;
  end;

constructor TIncludeMerger.Create(ATree: TSyntaxTree; const AFileName: string; const ADefines: TArray<string>;
  const AResolver: TIncludeResolver; const AStack: TArray<string>);
var
  mToken: TPascalToken;
begin
  inherited Create;
  FTree := ATree;
  FFileName := AFileName;
  FDefines := ADefines;
  FResolver := AResolver;
  FStack := AStack;
  FSymbols := TList<TIndexSymbol>.Create;
  FImplementationOffset := MaxInt;
  for mToken in ATree.Tokens do
  begin
    if mToken.IsKeyword('implementation') then
    begin
      FImplementationOffset := mToken.Offset;
      Break;
    end;
  end;
end;

destructor TIncludeMerger.Destroy;
begin
  FSymbols.Free;
  inherited;
end;

procedure TIncludeMerger.AddInclude(const AFile: string);
begin
  if IndexText(AFile, FIncludes) < 0 then
  begin
    FIncludes := FIncludes + [AFile];
  end;
end;

procedure TIncludeMerger.ReplaceValue(const AToken: TPascalToken; const AText: string);
var
  mPosition: Integer;
  mSymbol: TIndexSymbol;
begin
  for mPosition := 0 to FSymbols.Count - 1 do
  begin
    mSymbol := FSymbols[mPosition];
    if (mSymbol.Kind = TIndexSymbolKind.Constant) and (mSymbol.FileName = '') and
      TIndexConditions.InRange(AToken.StartPos, mSymbol.Range) then
    begin
      mSymbol.Signature := TIndexTokenReader.Shortened(StringReplace(mSymbol.Signature, AToken.Text,
        OneLine(AText), []), TIndexSymbol.cMaxSignature);
      FSymbols[mPosition] := mSymbol;
    end;
  end;
end;

procedure TIncludeMerger.AddSymbols(const AIncluded: TUnitIndex; const AFile, AHost: string; AShift: Integer;
  AInInterface: Boolean);
var
  mSymbol: TIndexSymbol;
  mName: string;
begin
  for mSymbol in AIncluded.Symbols do
  begin
    // Der Hilfstyp selbst gehört nicht in den Index.
    if (AHost = '') or not SameText(mSymbol.Container, '') or not SameText(mSymbol.Name, cIncludeHost) then
    begin
      FSymbols.Add(Relocated(mSymbol, AFile, AHost, AShift, AInInterface));
    end;
  end;
  for mName in AIncluded.Includes do
  begin
    AddInclude(mName);
  end;
end;

procedure TIncludeMerger.AddFile(const AToken: TPascalToken; const ASection, AFile, AText: string);
var
  mBody: TSyntaxNode;
  mText, mHost: string;
  mShift: Integer;
begin
  mText := AText;
  mHost := '';
  mShift := 0;
  mBody := BodyAt(FTree.Root, AToken.Offset);
  if mBody <> nil then
  begin
    // Mitten im Klassenrumpf (#849): die .inc in einen Hilfstyp derselben Art einbetten; ihre
    // Mitglieder gehören danach zum umgebenden Typ.
    mHost := mBody.EnclosingTypeName;
    mText := HostHead(mBody, AToken.Offset) + AText + #10 + 'end;';
    mShift := 2;
  end
  else if (ASection <> '') and not MatchText(FirstWord(AText), ['type', 'const', 'var', 'resourcestring',
    'threadvar', 'procedure', 'function', 'constructor', 'destructor', 'class', 'operator', 'uses', 'begin',
    'exports']) then
  begin
    mText := ASection + #10 + AText;
    mShift := 1;
  end;
  AddSymbols(ExtractLevel(mText, AFile, FDefines, FResolver, FStack + [AFile], False, False), AFile, mHost, mShift,
    (FTree.Root.Kind = TSyntaxKind.UnitFile) and (AToken.Offset < FImplementationOffset));
end;

procedure TIncludeMerger.TakeDirective(const AToken, APrevious: TPascalToken; const ASection: string);
var
  mName, mFile, mText: string;
begin
  if not TPascalPreprocessor.IncludeFileOf(AToken.Text, mName) then
  begin
    Exit;
  end;
  // Nicht gefunden oder Zyklus: überspringen, die Diagnose kommt aus dem Präprozessor.
  if not FResolver(mName, FFileName, mFile, mText) or (IndexText(mFile, FStack) >= 0) then
  begin
    Exit;
  end;
  AddInclude(mFile);
  if TPascalParser.IncludeAsValue(APrevious) then
  begin
    ReplaceValue(AToken, mText);
  end
  else
  begin
    AddFile(AToken, ASection, mFile, mText);
  end;
end;

procedure TIncludeMerger.Merge(var AUnit: TUnitIndex);
var
  mToken, mPrevious: TPascalToken;
  mSection: string;
begin
  FSymbols.AddRange(AUnit.Symbols);
  FIncludes := AUnit.Includes;
  mSection := '';
  mPrevious := Default(TPascalToken);
  mPrevious.Kind := TPascalTokenKind.Unknown;
  for mToken in FTree.Tokens do
  begin
    mSection := SectionAfter(mToken, mSection);
    if mToken.Kind = TPascalTokenKind.Directive then
    begin
      TakeDirective(mToken, mPrevious, mSection);
    end
    else if mToken.Kind <> TPascalTokenKind.Comment then
    begin
      mPrevious := mToken;
    end;
  end;
  AUnit.Symbols := FSymbols.ToArray;
  AUnit.Includes := FIncludes;
end;

class function TIncludeMerger.ExtractLevel(const AText, AFileName: string; const ADefines: TArray<string>;
  const AResolver: TIncludeResolver; const AStack: TArray<string>; AUsages, APatterns: Boolean): TUnitIndex;
var
  mTree: TSyntaxTree;
  mIncludes: TArray<string>;
  mConditionals: TArray<TConditionalRange>;
  mMerger: TIncludeMerger;
begin
  mTree := TSyntaxTreeCache.Parse(TIndexConditions.BlankInactive(AText, AFileName, ADefines, AResolver, mIncludes,
    mConditionals));
  try
    Result := TIndexExtractor.Extract(mTree, AFileName);
    Result.Includes := mIncludes;
    TIndexConditions.AnnotateConditions(Result, AText, mConditionals);
    if AUsages then
    begin
      Result.Usages := CollectUsages(mTree.Tokens, Result.Symbols);
      Result.UsagesIndexed := True;
    end;
    if APatterns then
    begin
      Result.Patterns := TIndexFollowPatterns.Collect(mTree);
    end;
    if Assigned(AResolver) and (Length(AStack) <= cMaxIncludeDepth) then
    begin
      mMerger := TIncludeMerger.Create(mTree, AFileName, ADefines, AResolver, AStack);
      try
        mMerger.Merge(Result);
      finally
        mMerger.Free;
      end;
    end;
  finally
    mTree.Free;
  end;
end;

class function TIndexExtractor.ExtractText(const AText, AFileName: string; const ADefines: TArray<string>;
  const AResolver: TIncludeResolver): TUnitIndex;
begin
  Result := ExtractText(AText, AFileName, ADefines, AResolver, False);
end;

class function TIndexExtractor.ExtractText(const AText, AFileName: string;
  const ADefines: TArray<string>): TUnitIndex;
begin
  Result := ExtractText(AText, AFileName, ADefines, nil, False);
end;

class function TIndexExtractor.ExtractText(const AText, AFileName: string;
  const ADefines: TArray<string>; const AResolver: TIncludeResolver; AUsages: Boolean): TUnitIndex;
begin
  Result := ExtractText(AText, AFileName, ADefines, AResolver, AUsages, False);
end;

class function TIndexExtractor.ExtractText(const AText, AFileName: string;
  const ADefines: TArray<string>; const AResolver: TIncludeResolver; AUsages, APatterns: Boolean): TUnitIndex;
begin
  Result := TIncludeMerger.ExtractLevel(AText, AFileName, ADefines, AResolver, [AFileName], AUsages, APatterns);
end;

end.
