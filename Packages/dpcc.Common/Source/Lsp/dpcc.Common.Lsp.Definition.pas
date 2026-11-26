unit dpcc.Common.Lsp.Definition;

// Gehe zu Definition und Gehe zu Deklaration (textDocument/definition,
// textDocument/declaration) über die Namensauflösung.
//
// Bei Routinen und Methoden mit getrennter Deklaration und Implementierung:
//   - declaration springt immer zur Deklaration (interface bzw. Klasse),
//   - definition springt zur Implementierung; steht der Cursor bereits auf
//     dem Namen der Implementierung, zurück zur Deklaration. So wechselt
//     dieselbe Taste zwischen beiden.
// Bei Überladungen gehören nur Deklaration und Implementierung derselben
// Variante (gleiche Parametertypen, dazu der Ergebnistyp, wo beide einen
// haben: class operator Implicit) zusammen; steht der Cursor auf einer
// Routine der Datei, gilt deren Variante. Vorher galt immer die erste
// Überladung (Hover auf der zweiten zeigte die erste). Typen vergleicht das
// ohne Leerzeichen, Groß/Klein und Unit-Qualifizierung (System.Integer =
// Integer, TList<System.Integer> = TList<Integer>). Findet sich so kein
// Gegenstück, paart es unter den gleichnamigen Routinen des Containers
// eindeutig nach Parameterzahl und -namen, zuletzt nach der Reihenfolge der
// übrigen (nur bei gleich vielen Deklarationen und Rümpfen); sonst kein Paar.
// Zwei Fundstellen ohne Rumpf (abstrakte, Interface- oder external-Überladungen) sind kein Paar: Strg+Klick bleibt
// auf der Deklaration. TPaar und TPaar<T> derselben Unit (im Index derselbe Container) trennt die Zahl der
// Typparameter (ContainerArity). Steht eine Methodendeklaration per {$I} im Klassenrumpf, kennt nur der Index der
// einbindenden Unit ihren Typ (HostResolved): So führt Strg+Klick in der Include-Datei zur Implementierung.
// Unit-Namen (z. B. in uses) führen an den Anfang der Unit-Datei, ebenso der Dateiname in {$I …}/{$INCLUDE …}
// an den Anfang der eingebundenen Datei (IncludeTargets). "inherited;" ohne Namen führt wie "inherited Name" zur
// gleichnamigen Methode im Vorfahren (BareInheritedAt). Beides nach Entscheidung des Nutzers vom 26.11.2026.
// textDocument/typeDefinition springt von Variablen, Feldern, Parametern,
// Properties und Funktionen zur Deklaration ihres Typs.
// Strg+Klick (Auftrag NAV): Seit NAV meldet die Wurzel des Completion-Servers diese Anfragen an. Findet die
// Namensauflösung nichts, gilt eine Deklaration der eigenen Unit aus einem nicht geltenden $IFDEF-Zweig (L1, L3:
// der Index kennt Name, Art und Zeile; UnavailableTargets), wie beim Hover.
// Kein Ziel (Sprung in ein anderes Package): Bevor declaration bzw. definition leer (null oder []) antworten, geht
// dpcc/noTarget mit dem Grund an den Client (Notify; im selben Thread vor der Antwort, also davor auf demselben
// Ausgang): noDocument, noIdentifier, unresolved, unitNotFound, noSource, inactiveBranch, other; dazu Name, Stelle
// und ob der Index noch aufgebaut wird. Derselbe Grund steht im Diagnoselog (statt empty:unspecified), der Name dort
// nur als Kennzahl (#647). Führt die Auflösung nur in Ersatz-Units der IDE (Package ohne Quelltext im Index), lädt
// sie zuerst die echte Quelle über EnsureUnit nach; vorher verdeckte die Ersatz-Unit sie still.
// Paar Deklaration/Implementierung im Diagnoselog (LOG1, nur Codes und Zahlen): pair=found:types|sole|names|order
// (Weg des Paars) mit pairChosen (declaration bzw. implementation) oder pair=none:noUnit|noSymbol|single|params
// mit pairSame und pairVariant; so ist
// ablesbar, warum ein Strg+Klick auf der Deklaration nicht zur Implementierung führt.

interface

uses
  System.SysUtils,
  System.JSON,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Index.Contract,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Dfm.Navigation;

type
  TDefinitionTarget = record
    FileName: string;
    Range: TTextRange;
    SelectionRange: TTextRange;
  end;

  TDefinitionRequestKind = (Definition, Declaration, TypeDefinition);

  /// <summary>Schickt eine Benachrichtigung an den Client; übernimmt AParams.</summary>
  TDefinitionNotifyProc = reference to procedure(const AMethod: string; AParams: TJSONObject);
  /// <summary>Wird der Index noch aufgebaut oder geladen?</summary>
  TDefinitionIndexingFunc = reference to function: Boolean;

  /// <summary>Warum ein Sprung kein Ziel hat (dpcc/noTarget): Grundcode und Bezeichner bzw. Unit ('' ohne).
  /// </summary>
  TDefinitionNoTarget = record
    Reason: string;
    Name: string;
  end;

  /// <summary>Stelle einer Sprungabfrage: Baum, Datei, Position und ob zur Deklaration.</summary>
  TDefinitionQuery = record
    Tree: TSyntaxTree;
    FileName: string;
    Position: TTextPosition;
    /// <summary>Immer zur Deklaration springen (sonst wechselt die Taste zwischen beiden).</summary>
    Declaration: Boolean;
    class function Create(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      ADeclaration: Boolean): TDefinitionQuery; static;
  end;

  TLspDefinition = class
  public const
    cDefinitionMethod = 'textDocument/definition';
    cDeclarationMethod = 'textDocument/declaration';
    cTypeDefinitionMethod = 'textDocument/typeDefinition';
    /// <summary>Benachrichtigung vor einer leeren Antwort auf declaration bzw. definition.</summary>
    cNoTargetMethod = 'dpcc/noTarget';
    /// <summary>Der Server kennt das Dokument nicht.</summary>
    cReasonNoDocument = 'noDocument';
    /// <summary>An der Stelle steht kein Bezeichner (auch Kommentar, String, Direktive).</summary>
    cReasonNoIdentifier = 'noIdentifier';
    /// <summary>Bezeichner nicht aufgelöst.</summary>
    cReasonUnresolved = 'unresolved';
    /// <summary>Eine benutzte Unit wurde nicht gefunden.</summary>
    cReasonUnitNotFound = 'unitNotFound';
    /// <summary>Das Ziel liegt in einer Unit ohne Quelltext (nur Package bzw. RTTI der IDE).</summary>
    cReasonNoSource = 'noSource';
    /// <summary>Das Ziel bzw. die Stelle liegt in einem nicht geltenden $IFDEF-Zweig.</summary>
    cReasonInactiveBranch = 'inactiveBranch';
    cReasonOther = 'other';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    FReadText: TDfmReadText;
    FNotify: TDefinitionNotifyProc;
    FIndexing: TDefinitionIndexingFunc;
    function FormTargets(const AText, AUri: string; const APosition: TTextPosition): TJSONValue;
    /// <summary>Ziele über die Namensauflösung, sonst aus nicht geltenden Zweigen der eigenen Unit.</summary>
    function ResolveTargets(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition; ADeclaration: Boolean): TArray<TDefinitionTarget>;
    /// <summary>Lädt die echten Quellen der Ersatz-Units in ATargets über EnsureUnit; True, wenn eine geladen ist.
    /// </summary>
    function LoadIdeSources(const ATargets: TArray<TDefinitionTarget>): Boolean;
    /// <summary>Grund ins Diagnoselog und, außer bei typeDefinition, dpcc/noTarget an den Client.</summary>
    procedure ReportNoTarget(AKind: TDefinitionRequestKind; const AUri: string; const APosition: TTextPosition;
      const AWhy: TDefinitionNoTarget);
    function Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
      AKind: TDefinitionRequestKind): TJSONValue;
    function HandleDefinition(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleDeclaration(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleTypeDefinition(const AParams: TJSONValue;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt: Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex); overload;
    /// <summary>Registriert beide Anfragen am Dispatcher.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Sprungziele für den Bezeichner an APosition; leer, wenn er nicht auflösbar ist.</summary>
    class function Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean): TArray<TDefinitionTarget>;
        static;
    /// <summary>Wie Targets, für ein schon aufgelöstes Symbol (etwa einen Kandidaten aus ResolveAll, #1119).
    /// </summary>
    class function TargetsOf(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AQuery: TDefinitionQuery;
      const AResolved: TResolvedSymbol): TArray<TDefinitionTarget>; static;
    /// <summary>Deklaration des Typs des Bezeichners an APosition; leer, wenn er keinen bekannten Typ hat.</summary>
    class function TypeTargets(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition): TArray<TDefinitionTarget>; static;
    /// <summary>Deklarationen des Namens an APosition in AText aus nicht geltenden Zweigen der Unit AFileName
    /// (TUnitIndex.Unavailable), die Deklaration in derselben Zeile zuerst; leer in Kommentaren, Strings und
    /// Direktiven oder ohne solche Deklaration.</summary>
    class function UnavailableTargets(const AIndex: ISymbolIndex; ATree: TSyntaxTree; const AFileName, AText: string;
      const APosition: TTextPosition): TArray<TDefinitionTarget>; static;
    /// <summary>LocationLink[] des LSP ohne Ziele in Ersatz-Units der IDE. Der Aufrufer übernimmt das Objekt.
    /// </summary>
    class function ToJson(const ATargets: TArray<TDefinitionTarget>): TJSONArray; static;
    /// <summary>Warum ATargets (nach ToJson) kein Ziel ergibt: noSource (nur Ersatz-Units), noIdentifier,
    /// inactiveBranch (Stelle oder Deklaration in einer benutzten Unit in einem nicht geltenden Zweig), unitNotFound
    /// (eine Unit aus uses fehlt; Name = Unit) oder unresolved. AResolver hat die Stelle schon aufgelöst.</summary>
    class function Explain(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName, AText: string; const APosition: TTextPosition;
      const ATargets: TArray<TDefinitionTarget>): TDefinitionNoTarget; static;
    /// <summary>Unit-Name einer Ersatz-Unit der IDE (dpcc-ide:Vendor.Grid.pas → Vendor.Grid).</summary>
    class function IdeUnitName(const AFileName: string): string; static;
    /// <summary>Unit-Namespaces des Projekts (DCC_Namespace).</summary>
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Liest die Unit neben einer Formulardatei (#44); ohne sie gibt es dort keine Sprünge.</summary>
    property ReadText: TDfmReadText read FReadText write FReadText;
    /// <summary>Für dpcc/noTarget; ohne geht der Grund nur ins Diagnoselog. Vor dem ersten Attach zu setzen.
    /// </summary>
    property Notify: TDefinitionNotifyProc read FNotify write FNotify;
    /// <summary>Feld "indexing" von dpcc/noTarget; ohne gilt False.</summary>
    property Indexing: TDefinitionIndexingFunc read FIndexing write FIndexing;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  System.Hash,
  dpcc.Common.Diagnostics.RequestScope,
  dpcc.Common.Lsp.Internals.Namespaces,
  dpcc.Common.Index.Files,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Lsp.Positions,
  dpcc.Common.Pascal.Contract,
  dpcc.Common.Pascal.IncludeFiles,
  dpcc.Common.Pascal.TreeCache,
  dpcc.Common.Lsp.Internals.Cancellation,
  dpcc.Common.Dfm.Parser,
  dpcc.Common.Lsp.IdeUnits,
  dpcc.Text.Lines,
  dpcc.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDefinitionText = (FieldsTextDocumentUriAndPosition);

const
  cTexts: array[TDefinitionText] of TDpccText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen'; En: 'Fields "textDocument.uri" and "position" missing'));

{$SCOPEDENUMS OFF}

const
  cRoutineKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];

function Within(const APosition: TTextPosition; const ARange: TTextRange): Boolean;
begin
  Result :=
    ((APosition.Line > ARange.StartPos.Line) or
     ((APosition.Line = ARange.StartPos.Line) and (APosition.Character >= ARange.StartPos.Character))) and
    ((APosition.Line < ARange.EndPos.Line) or
     ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

/// <summary>Zeichen eines Namens in einem Typtext (auch "&amp;" vor reservierten Wörtern und Zeichen jenseits von
/// ASCII).</summary>
function IsTypeChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_', '&']) or (Ord(AChar) > 127);
end;

/// <summary>Erste Stelle ab AIndex in AText, die kein Leerzeichen oder Umbruch ist (Length + 1 am Ende).</summary>
function SkipBlanks(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and (AText[Result] <= ' ') do
  begin
    Inc(Result);
  end;
end;

/// <summary>Typtext zum Vergleich von Parameter- und Ergebnistypen: ohne Leerzeichen und "&amp;", groß geschrieben
/// und ohne Unit-Qualifizierung je Name (System.Integer → INTEGER, TList&lt;System.Integer&gt; → TLIST&lt;INTEGER&gt;,
/// array of System.Byte → ARRAYOFBYTE). Generische Argumente und ihre Reihenfolge bleiben erhalten; Aliasse
/// (string/UnicodeString) löst das nicht auf.</summary>
function NormalTypeText(const AType: string): string;
var
  mBuilder: TStringBuilder;
  mIndex, mStart, mNext: Integer;
  mName: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    mIndex := 1;
    while mIndex <= Length(AType) do
    begin
      if not IsTypeChar(AType[mIndex]) then
      begin
        // Satzzeichen (<, >, Komma, ^) bleiben, Leerzeichen und Umbrüche fallen weg.
        if AType[mIndex] > ' ' then
        begin
          mBuilder.Append(AType[mIndex]);
        end;
        Inc(mIndex);
        Continue;
      end;
      // Ein Name, ggf. qualifiziert (System.Generics.Collections.TList): nur der letzte Teil zählt.
      while True do
      begin
        mStart := mIndex;
        while (mIndex <= Length(AType)) and IsTypeChar(AType[mIndex]) do
        begin
          Inc(mIndex);
        end;
        mName := Copy(AType, mStart, mIndex - mStart);
        mNext := SkipBlanks(AType, mIndex);
        if (mNext > Length(AType)) or (AType[mNext] <> '.') then
        begin
          Break;
        end;
        mNext := SkipBlanks(AType, mNext + 1);
        if (mNext > Length(AType)) or not IsTypeChar(AType[mNext]) then
        begin
          Break;
        end;
        mIndex := mNext;
      end;
      mBuilder.Append(StringReplace(mName, '&', '', [rfReplaceAll]));
    end;
    Result := AnsiUpperCase(mBuilder.ToString);
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Gleiche Typen nach NormalTypeText (Groß-/Kleinschreibung, Leerzeichen und Unit-Qualifizierung egal).
/// </summary>
function SameTypeText(const A, B: string): Boolean;
begin
  Result := SameText(A, B) or (NormalTypeText(A) = NormalTypeText(B));
end;

/// <summary>Gleiche Parametertypen (SameTypeText je Parameter): dieselbe Variante einer Überladung.</summary>
function SameParams(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(A) do
  begin
    if not SameTypeText(A[mIndex], B[mIndex]) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Ergebnistyp einer Funktion samt Typargumenten (TList&lt;Integer&gt;); '' bei Prozeduren, Konstruktoren
/// und Rümpfen ohne Ergebnistyp ("function TFoo.Rechne;").</summary>
function ResultTypeOf(const ATypeName, ATypeArgs: string): string;
begin
  Result := ATypeName;
  if (Result <> '') and (ATypeArgs <> '') then
  begin
    Result := Result + '<' + ATypeArgs + '>';
  end;
end;

/// <summary>Gleicher Ergebnistyp, wo beide einen haben: Ein Rumpf ohne Ergebnistyp (bei nicht überladenen Routinen
/// erlaubt) passt zu jedem.</summary>
function SameResult(const A, B: string): Boolean;
begin
  Result := (A = '') or (B = '') or SameTypeText(A, B);
end;

function Target(const AFileName: string; const ARange, ASelectionRange: TTextRange): TDefinitionTarget;
begin
  Result.FileName := AFileName;
  Result.Range := ARange;
  Result.SelectionRange := ASelectionRange;
end;

{ TDefinitionQuery }

class function TDefinitionQuery.Create(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  ADeclaration: Boolean): TDefinitionQuery;
begin
  Result.Tree := ATree;
  Result.FileName := AFileName;
  Result.Position := APosition;
  Result.Declaration := ADeclaration;
end;

{ TLspDefinition }

function TLspDefinition.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspDefinition.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspDefinition.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex);
begin
  Create(AStore, AIndex, nil);
end;

constructor TLspDefinition.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspDefinition.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cDefinitionMethod, HandleDefinition);
  ADispatcher.RegisterConcurrentRequest(cDeclarationMethod, HandleDeclaration);
  ADispatcher.RegisterConcurrentRequest(cTypeDefinitionMethod, HandleTypeDefinition);
end;

class function TLspDefinition.Targets(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; ADeclaration: Boolean): TArray<TDefinitionTarget>;
begin
  Result := TargetsOf(AResolver, AIndex, TDefinitionQuery.Create(ATree, AFileName, APosition, ADeclaration),
    AResolver.Resolve(ATree, AFileName, APosition));
end;

/// <summary>Die Deklaration unter dem Cursor in der eigenen Datei; Kind None, wenn dort keine steht.</summary>
function DeclarationAt(AResolver: TNameResolver; const AQuery: TDefinitionQuery): TResolvedSymbol;
var
  mOwnerUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  Result := Default(TResolvedSymbol);
  // Über den Resolver: bei gepinntem Baum ohne neue Auswertung.
  mOwnerUnit := AResolver.ExtractedUnit(AQuery.Tree, AQuery.FileName);
  for mSymbol in mOwnerUnit.Symbols do
  begin
    if SameText(mOwnerUnit.SymbolFile(mSymbol), AQuery.FileName) and
      Within(AQuery.Position, mSymbol.SelectionRange) then
    begin
      Result.Kind := TResolvedKind.Symbol;
      Result.Name := mSymbol.Name;
      Result.Container := mSymbol.Container;
      Result.SymbolKind := mSymbol.Kind;
      Result.FileName := AQuery.FileName;
      Result.Range := mSymbol.Range;
      Result.SelectionRange := mSymbol.SelectionRange;
      Result.ParamTypes := mSymbol.ParamTypes;
      // Ergebnistyp für die Variante (class operator Implicit, der sich nur darin unterscheidet).
      Result.TypeName := mSymbol.TypeName;
      Result.TypeArgs := mSymbol.TypeArgs;
      Exit;
    end;
  end;
end;

type
  /// <summary>Gemeinte Variante einer Routine: Parameter- und Ergebnistyp der Routine unter dem Cursor (sonst des
  /// aufgelösten Symbols) und ihre Stelle, um sie unter den gleichnamigen Fundstellen wiederzufinden.</summary>
  TRoutineWanted = record
    ParamTypes: TArray<string>;
    ResultType: string;
    FileName: string;
    Start: TTextPosition;
  end;

const
  /// <summary>Wege, auf denen RoutinePair ein Paar findet (Diagnoselog pair=found:Weg): gleiche Typen, die einzigen
  /// zwei Fundstellen, gleiche Parameterzahl und -namen, Reihenfolge der übrigen.</summary>
  cPairTypes = 'types';
  cPairSole = 'sole';
  cPairNames = 'names';
  cPairOrder = 'order';
  /// <summary>Art eines Parameters vor seinem Namen.</summary>
  cParamModifiers: array[0..3] of string = ('const', 'var', 'out', 'constref');

/// <summary>Gemeinte Variante: die Routine unter dem Cursor in AHere, sonst AResolved.</summary>
function WantedOf(const AHere: TUnitIndex; const AResolved: TResolvedSymbol;
  const APosition: TTextPosition): TRoutineWanted;
var
  mSymbol: TIndexSymbol;
begin
  Result := Default(TRoutineWanted);
  for mSymbol in AHere.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Name, AResolved.Name) and
      Within(APosition, mSymbol.SelectionRange) then
    begin
      Result.ParamTypes := mSymbol.ParamTypes;
      Result.ResultType := ResultTypeOf(mSymbol.TypeName, mSymbol.TypeArgs);
      Result.FileName := AHere.SymbolFile(mSymbol);
      Result.Start := mSymbol.SelectionRange.StartPos;
      Exit;
    end;
  end;
  Result.ParamTypes := AResolved.ParamTypes;
  Result.ResultType := ResultTypeOf(AResolved.TypeName, AResolved.TypeArgs);
  Result.FileName := AResolved.FileName;
  Result.Start := AResolved.SelectionRange.StartPos;
end;

/// <summary>Dieselbe Variante: gleiche Parametertypen und, wo beide einen haben, gleicher Ergebnistyp.</summary>
function SameVariant(const ASymbol: TIndexSymbol; const AParamTypes: TArray<string>;
  const AResultType: string): Boolean;
begin
  Result := SameParams(ASymbol.ParamTypes, AParamTypes) and
    SameResult(ResultTypeOf(ASymbol.TypeName, ASymbol.TypeArgs), AResultType);
end;

function IsRoutineBody(const ASymbol: TIndexSymbol; out AKnown: Boolean): Boolean; forward;

/// <summary>Zahl der Typparameter in "T" bzw. "TKey,TValue"; 0 ohne.</summary>
function TypeParamCount(const ATypeParams: string): Integer;
var
  mIndex: Integer;
begin
  if Trim(ATypeParams) = '' then
  begin
    Exit(0);
  end;
  Result := 1;
  for mIndex := 1 to Length(ATypeParams) do
  begin
    if ATypeParams[mIndex] = ',' then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Typparameter des umgebenden Typs im Kopf eines Rumpfs (procedure TPaar&lt;T&gt;.Setze → 1,
/// procedure TPaar.Setze → 0): die spitzen Klammern direkt vor dem letzten Punkt vor der Parameterliste.</summary>
function HeadContainerArity(const ASignature: string): Integer;
var
  mIndex, mDepth, mDot, mEnd: Integer;
begin
  // Ende des Namens: erste "(" bzw. ":" oder ";" außerhalb spitzer Klammern.
  mEnd := Length(ASignature);
  mDepth := 0;
  mDot := 0;
  for mIndex := 1 to Length(ASignature) do
  begin
    case ASignature[mIndex] of
      '<':
        Inc(mDepth);
      '>':
        if mDepth > 0 then
        begin
          Dec(mDepth);
        end;
      '.':
        if mDepth = 0 then
        begin
          mDot := mIndex;
        end;
      '(', ':', ';', '=':
        if mDepth = 0 then
        begin
          mEnd := mIndex;
          Break;
        end;
    end;
  end;
  Result := 0;
  if (mDot <= 1) or (mDot > mEnd) or (ASignature[mDot - 1] <> '>') then
  begin
    Exit;
  end;
  // Von ">" rückwärts bis zur passenden "<", Kommas auf erster Ebene zählen.
  mDepth := 0;
  Result := 1;
  for mIndex := mDot - 1 downto 1 do
  begin
    case ASignature[mIndex] of
      '>':
        Inc(mDepth);
      '<':
        begin
          Dec(mDepth);
          if mDepth = 0 then
          begin
            Exit;
          end;
        end;
      ',':
        if mDepth = 1 then
        begin
          Inc(Result);
        end;
    end;
  end;
  Result := 0;
end;

/// <summary>Typparameter des Typs, zu dem die Routine ASymbol gehört: beim Rumpf aus dem Kopf, bei der Deklaration
/// aus dem Typ, in dessen Bereich sie steht. -1, wenn das nicht feststeht (etwa Deklaration aus einer Include-Datei).
/// Trennt TPaar und TPaar&lt;T&gt; derselben Unit, die im Index denselben Container "TPaar" tragen.</summary>
function ContainerArity(const AOwner: TUnitIndex; const ASymbol: TIndexSymbol): Integer;
var
  mKnown: Boolean;
  mTypeName, mFile: string;
  mType: TIndexSymbol;
begin
  Result := -1;
  if ASymbol.Container = '' then
  begin
    Exit;
  end;
  if IsRoutineBody(ASymbol, mKnown) then
  begin
    Exit(HeadContainerArity(ASymbol.Signature));
  end;
  if not mKnown then
  begin
    Exit;
  end;
  mTypeName := ASymbol.Container;
  if LastDelimiter('.', mTypeName) > 0 then
  begin
    mTypeName := Copy(mTypeName, LastDelimiter('.', mTypeName) + 1, MaxInt);
  end;
  mFile := AOwner.SymbolFile(ASymbol);
  for mType in AOwner.Symbols do
  begin
    if (mType.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
      TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType]) and SameText(mType.Name, mTypeName) and
      SameText(AOwner.SymbolFile(mType), mFile) and Within(ASymbol.SelectionRange.StartPos, mType.Range) then
    begin
      Exit(TypeParamCount(mType.TypeParams));
    end;
  end;
end;

/// <summary>Routinen in AOwner mit Name und Container von AResolved, in der Reihenfolge des Index. Gehört
/// AResolved zu einem generischen bzw. nicht generischen Typ (TPaar&lt;T&gt; neben TPaar), nur die Routinen
/// desselben Typs; wo das nicht feststeht, alle.</summary>
function SameRoutines(const AOwner: TUnitIndex; const AResolved: TResolvedSymbol): TArray<TIndexSymbol>;
var
  mSymbol: TIndexSymbol;
  mAll: TArray<TIndexSymbol>;
  mWanted, mArity: Integer;
begin
  mAll := nil;
  mWanted := -1;
  for mSymbol in AOwner.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Container, AResolved.Container) and
      SameText(mSymbol.Name, AResolved.Name) then
    begin
      mAll := mAll + [mSymbol];
      if (mSymbol.SelectionRange.StartPos.Line = AResolved.SelectionRange.StartPos.Line) and
        (mSymbol.SelectionRange.StartPos.Character = AResolved.SelectionRange.StartPos.Character) and
        SameText(AOwner.SymbolFile(mSymbol), AResolved.FileName) then
      begin
        mWanted := ContainerArity(AOwner, mSymbol);
      end;
    end;
  end;
  if mWanted < 0 then
  begin
    Exit(mAll);
  end;
  Result := nil;
  for mSymbol in mAll do
  begin
    mArity := ContainerArity(AOwner, mSymbol);
    if (mArity < 0) or (mArity = mWanted) then
    begin
      Result := Result + [mSymbol];
    end;
  end;
end;

/// <summary>AText an ASeparator geteilt, aber nicht in runden oder eckigen Klammern und nicht in Strings.</summary>
function SplitTopLevel(const AText: string; ASeparator: Char): TArray<string>;
var
  mIndex, mDepth, mStart: Integer;
  mQuoted: Boolean;
begin
  Result := nil;
  mDepth := 0;
  mQuoted := False;
  mStart := 1;
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end
    else if not mQuoted then
    begin
      if CharInSet(AText[mIndex], ['(', '[']) then
      begin
        Inc(mDepth);
      end
      else if CharInSet(AText[mIndex], [')', ']']) then
      begin
        if mDepth > 0 then
        begin
          Dec(mDepth);
        end;
      end
      else if (AText[mIndex] = ASeparator) and (mDepth = 0) then
      begin
        Result := Result + [Copy(AText, mStart, mIndex - mStart)];
        mStart := mIndex + 1;
      end;
    end;
  end;
  Result := Result + [Copy(AText, mStart, MaxInt)];
end;

/// <summary>Kopf ASignature bis zur Parameterliste: True, wenn der Name dort qualifiziert ist (procedure TFoo.Bar,
/// TFoo&lt;T&gt;.Bar: ein Rumpf). AParamsAt = Stelle der öffnenden Klammer der Parameter, 0 ohne Parameterliste.
/// Typparameter in spitzen Klammern (auch mit Einschränkungen "T: class") zählen nicht.</summary>
function ScanHead(const ASignature: string; out AParamsAt: Integer): Boolean;
var
  mIndex, mDepth: Integer;
begin
  Result := False;
  AParamsAt := 0;
  mDepth := 0;
  for mIndex := 1 to Length(ASignature) do
  begin
    case ASignature[mIndex] of
      '<':
        Inc(mDepth);
      '>':
        if mDepth > 0 then
        begin
          Dec(mDepth);
        end;
      '.':
        if mDepth = 0 then
        begin
          Result := True;
        end;
      '(':
        if mDepth = 0 then
        begin
          AParamsAt := mIndex;
          Exit;
        end;
      ':', ';', '=':
        if mDepth = 0 then
        begin
          Exit;
        end;
    end;
  end;
end;

/// <summary>Trägt der Kopf ASignature hinter einem Semikolon die Direktive AWord (forward, external …)?</summary>
function HasHeadDirective(const ASignature, AWord: string): Boolean;
var
  mParts: TArray<string>;
  mIndex: Integer;
  mPart: string;
begin
  mParts := SplitTopLevel(ASignature, ';');
  for mIndex := 1 to High(mParts) do
  begin
    mPart := Trim(mParts[mIndex]);
    if StartsText(AWord, mPart) and ((Length(mPart) = Length(AWord)) or
      not IsTypeChar(mPart[Length(AWord) + 1])) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Rumpf (Implementierung) statt Deklaration? Methoden: Kopf mit qualifiziertem Namen (TFoo.Bar). Freie
/// Routinen: außerhalb des interface und ohne forward bzw. external. AKnown False ohne Kopf im Index.</summary>
function IsRoutineBody(const ASymbol: TIndexSymbol; out AKnown: Boolean): Boolean;
var
  mSignature: string;
  mParamsAt: Integer;
begin
  mSignature := ASymbol.Signature;
  AKnown := Trim(mSignature) <> '';
  if not AKnown then
  begin
    Exit(False);
  end;
  if ASymbol.Container <> '' then
  begin
    Exit(ScanHead(mSignature, mParamsAt));
  end;
  Result := not ASymbol.InInterface and not ASymbol.HasDirective('forward') and
    not ASymbol.HasDirective('external') and not HasHeadDirective(mSignature, 'forward') and
    not HasHeadDirective(mSignature, 'external');
end;

/// <summary>Können A und B Deklaration und Implementierung derselben Routine sein? Ja, wenn genau eine ein Rumpf ist,
/// bei freien Routinen auch, wenn genau eine im interface steht (Deklaration dort, "external" im implementation-Teil
/// wie in Winapi.Windows). Ohne Kopf im Index (unbekannt) wie bisher ja. Nein für zwei Deklarationen ohne Rumpf
/// (abstrakte, Interface- oder external-Überladungen).</summary>
function DeclarationWithBody(const A, B: TIndexSymbol): Boolean;
var
  mKnownA, mKnownB, mBodyA, mBodyB: Boolean;
begin
  mBodyA := IsRoutineBody(A, mKnownA);
  mBodyB := IsRoutineBody(B, mKnownB);
  Result := not (mKnownA and mKnownB) or (mBodyA <> mBodyB) or
    ((A.Container = '') and (B.Container = '') and (A.InInterface <> B.InInterface));
end;

/// <summary>Text der Parameterliste im Kopf ASignature ohne die Klammern; '' ohne Parameterliste. False, wenn die
/// Liste nicht endet (Kopf im Index gekürzt).</summary>
function ParamListOf(const ASignature: string; out AContent: string): Boolean;
var
  mStart, mIndex, mDepth: Integer;
  mQuoted: Boolean;
begin
  AContent := '';
  ScanHead(ASignature, mStart);
  if mStart = 0 then
  begin
    Exit(True);
  end;
  mDepth := 0;
  mQuoted := False;
  for mIndex := mStart to Length(ASignature) do
  begin
    if ASignature[mIndex] = '''' then
    begin
      mQuoted := not mQuoted;
    end
    else if not mQuoted and CharInSet(ASignature[mIndex], ['(', '[']) then
    begin
      Inc(mDepth);
    end
    else if not mQuoted and CharInSet(ASignature[mIndex], [')', ']']) then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        AContent := Copy(ASignature, mStart + 1, mIndex - mStart - 1);
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>AText ohne führende Attribute ([Ref]) und ohne führende Parameterart (const, var, out, constref).
/// </summary>
function WithoutParamPrefix(const AText: string): string;
var
  mClose, mSpace, mRound: Integer;
begin
  Result := Trim(AText);
  // Zwei Runden: "const [ref] A" und "[ref] const A".
  for mRound := 1 to 2 do
  begin
    while (Result <> '') and (Result[1] = '[') do
    begin
      mClose := Pos(']', Result);
      if mClose = 0 then
      begin
        Break;
      end;
      Result := Trim(Copy(Result, mClose + 1, MaxInt));
    end;
    mSpace := Pos(' ', Result);
    if (mSpace > 0) and (IndexText(Copy(Result, 1, mSpace - 1), cParamModifiers) >= 0) then
    begin
      Result := Trim(Copy(Result, mSpace + 1, MaxInt));
    end;
  end;
end;

/// <summary>Parameterzahl und -namen aus dem Kopf (Signature) als Schlüssel "2:A,B" (groß geschrieben); False ohne
/// lesbaren Kopf. Ohne Parameterliste "0:".</summary>
function ParamNamesKey(const ASymbol: TIndexSymbol; out AKey: string): Boolean;
var
  mSignature, mContent, mGroup, mText, mName, mNames: string;
  mColon, mCount: Integer;
begin
  AKey := '';
  mSignature := ASymbol.Signature;
  Result := (Trim(mSignature) <> '') and ParamListOf(mSignature, mContent);
  if not Result then
  begin
    Exit;
  end;
  mCount := 0;
  mNames := '';
  if Trim(mContent) <> '' then
  begin
    for mGroup in SplitTopLevel(mContent, ';') do
    begin
      mText := WithoutParamPrefix(mGroup);
      mColon := Pos(':', mText);
      if mColon > 0 then
      begin
        mText := Copy(mText, 1, mColon - 1);
      end;
      for mName in mText.Split([',']) do
      begin
        if Trim(mName) = '' then
        begin
          Continue;
        end;
        if mNames <> '' then
        begin
          mNames := mNames + ',';
        end;
        mNames := mNames + AnsiUpperCase(StringReplace(Trim(mName), '&', '', [rfReplaceAll]));
        Inc(mCount);
      end;
    end;
  end;
  AKey := IntToStr(mCount) + ':' + mNames;
end;

/// <summary>Rückfall, wenn die Typen für ASame[AWanted] kein eindeutiges Gegenstück finden: Deklarationen und Rümpfe
/// der gleichnamigen Routinen ASame (desselben Containers) paaren, je Stufe nur gegenseitig eindeutig: zuerst gleiche
/// Typen (das nimmt andere Varianten aus dem Spiel), dann gleiche Parameterzahl und -namen, zuletzt die Reihenfolge
/// der übrigen, aber nur bei gleich vielen ungepaarten Deklarationen und Rümpfen. Lieber kein Paar als ein falsches:
/// False, wenn ein Kopf fehlt oder ASame[AWanted] ungepaart bleibt. ADeclaration und ABody sind Nummern in ASame,
/// AWay der Weg des Paars (cPairTypes, cPairNames, cPairOrder).</summary>
function PairByStages(const ASame: TArray<TIndexSymbol>; AWanted: Integer; out ADeclaration, ABody: Integer;
  out AWay: string): Boolean;
var
  mBody: TArray<Boolean>;
  mPartner: TArray<Integer>;
  mWays, mKeys: TArray<string>;
  mIndex, mOther, mCount: Integer;
  mKnown: Boolean;
  mDeclarations, mBodies: TArray<Integer>;

  /// <summary>Passen ASame[A] und ASame[B] in Stufe AStage (0 Typen, 1 Parameterzahl und -namen)?</summary>
  function Matches(AStage, A, B: Integer): Boolean;
  begin
    if AStage = 0 then
    begin
      Result := SameVariant(ASame[A], ASame[B].ParamTypes, ResultTypeOf(ASame[B].TypeName, ASame[B].TypeArgs));
    end
    else
    begin
      Result := (mKeys[A] <> '') and (mKeys[A] = mKeys[B]);
    end;
  end;

  /// <summary>Das einzige ungepaarte Gegenstück zu ASame[A] auf der anderen Seite in Stufe AStage; -1 ohne oder bei
  /// mehreren.</summary>
  function OnlyCandidate(AStage, A: Integer): Integer;
  var
    mCandidate: Integer;
  begin
    Result := -1;
    for mCandidate := 0 to High(ASame) do
    begin
      if (mBody[mCandidate] <> mBody[A]) and (mPartner[mCandidate] < 0) and Matches(AStage, A, mCandidate) then
      begin
        if Result >= 0 then
        begin
          Exit(-1);
        end;
        Result := mCandidate;
      end;
    end;
  end;

  /// <summary>Stufe AStage wiederholen, bis sich nichts mehr ändert; jedes neue Paar heißt AStageWay.</summary>
  procedure RunStage(AStage: Integer; const AStageWay: string);
  var
    mChanged: Boolean;
    mDeclaration, mCandidate: Integer;
  begin
    repeat
      mChanged := False;
      for mDeclaration := 0 to High(ASame) do
      begin
        if mBody[mDeclaration] or (mPartner[mDeclaration] >= 0) then
        begin
          Continue;
        end;
        mCandidate := OnlyCandidate(AStage, mDeclaration);
        if (mCandidate >= 0) and (OnlyCandidate(AStage, mCandidate) = mDeclaration) then
        begin
          mPartner[mDeclaration] := mCandidate;
          mPartner[mCandidate] := mDeclaration;
          mWays[mDeclaration] := AStageWay;
          mWays[mCandidate] := AStageWay;
          mChanged := True;
        end;
      end;
    until not mChanged;
  end;

begin
  Result := False;
  ADeclaration := -1;
  ABody := -1;
  AWay := '';
  if (AWanted < 0) or (AWanted > High(ASame)) then
  begin
    Exit;
  end;
  mCount := Length(ASame);
  SetLength(mBody, mCount);
  SetLength(mPartner, mCount);
  SetLength(mWays, mCount);
  SetLength(mKeys, mCount);
  for mIndex := 0 to mCount - 1 do
  begin
    mBody[mIndex] := IsRoutineBody(ASame[mIndex], mKnown);
    // Ohne Kopf keine sichere Trennung von Deklaration und Rumpf.
    if not mKnown then
    begin
      Exit;
    end;
    mPartner[mIndex] := -1;
    if not ParamNamesKey(ASame[mIndex], mKeys[mIndex]) then
    begin
      mKeys[mIndex] := '';
    end;
  end;
  RunStage(0, cPairTypes);
  RunStage(1, cPairNames);
  // Reihenfolge: nur, wenn auf beiden Seiten gleich viele übrig sind.
  mDeclarations := nil;
  mBodies := nil;
  for mIndex := 0 to mCount - 1 do
  begin
    if mPartner[mIndex] >= 0 then
    begin
      Continue;
    end;
    if mBody[mIndex] then
    begin
      mBodies := mBodies + [mIndex];
    end
    else
    begin
      mDeclarations := mDeclarations + [mIndex];
    end;
  end;
  if (Length(mDeclarations) > 0) and (Length(mDeclarations) = Length(mBodies)) then
  begin
    for mIndex := 0 to High(mDeclarations) do
    begin
      mOther := mBodies[mIndex];
      mPartner[mDeclarations[mIndex]] := mOther;
      mPartner[mOther] := mDeclarations[mIndex];
      mWays[mDeclarations[mIndex]] := cPairOrder;
      mWays[mOther] := cPairOrder;
    end;
  end;
  if mPartner[AWanted] < 0 then
  begin
    Exit;
  end;
  if mBody[AWanted] then
  begin
    ABody := AWanted;
    ADeclaration := mPartner[AWanted];
  end
  else
  begin
    ADeclaration := AWanted;
    ABody := mPartner[AWanted];
  end;
  AWay := mWays[AWanted];
  Result := True;
end;

/// <summary>Nummer der gemeinten Routine AWanted in ASame (gleiche Datei und Anfang des Namens); -1 ohne.</summary>
function IndexOfWanted(const AOwner: TUnitIndex; const ASame: TArray<TIndexSymbol>;
  const AWanted: TRoutineWanted): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ASame) do
  begin
    if (ASame[mIndex].SelectionRange.StartPos.Line = AWanted.Start.Line) and
      (ASame[mIndex].SelectionRange.StartPos.Character = AWanted.Start.Character) and
      SameText(AOwner.SymbolFile(ASame[mIndex]), AWanted.FileName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Fundstellen der Routine AResolved in AOwner und der Weg des Paars in AWay:
/// - types: genau zwei Fundstellen mit Parameter- und Ergebnistyp von AWanted (Typen ohne Leerzeichen, Groß/Klein
///   und Unit-Qualifizierung verglichen; der Ergebnistyp nur, wo beide einen haben);
/// - sole: sonst bei genau zwei gleichnamigen Fundstellen diese beiden (ohne Überladungen darf die Implementierung
///   Parameter und Ergebnistyp weglassen);
/// - names, order (oder types): sonst PairByStages unter den gleichnamigen Routinen des Containers, Deklaration
///   zuerst. Mehr als zwei Fundstellen gleicher Typen ohne eindeutiges Paar: wie bisher die erste und die letzte.
/// False ohne Paar.</summary>
function RoutinePair(const AOwner: TUnitIndex; const AResolved: TResolvedSymbol; const AWanted: TRoutineWanted;
  out AVariant: TArray<TIndexSymbol>; out AWay: string): Boolean;
var
  mSymbol: TIndexSymbol;
  mSame: TArray<TIndexSymbol>;
  mWanted, mDeclaration, mBody: Integer;
  mWay: string;
begin
  AVariant := nil;
  AWay := '';
  mSame := SameRoutines(AOwner, AResolved);
  for mSymbol in mSame do
  begin
    if SameVariant(mSymbol, AWanted.ParamTypes, AWanted.ResultType) then
    begin
      AVariant := AVariant + [mSymbol];
    end;
  end;
  if (Length(AVariant) = 2) and DeclarationWithBody(AVariant[0], AVariant[1]) then
  begin
    AWay := cPairTypes;
    Exit(True);
  end;
  // Zwei Überladungen ohne Rumpf (abstract, Interface, external) sind kein Paar: Strg+Klick bleibt stehen, statt zur
  // anderen Überladung zu springen.
  if (Length(AVariant) < 2) and (Length(mSame) = 2) and DeclarationWithBody(mSame[0], mSame[1]) then
  begin
    AVariant := mSame;
    AWay := cPairSole;
    Exit(True);
  end;
  // Keine oder mehrere Fundstellen gleicher Typen: eindeutig über Stufen paaren.
  mWanted := IndexOfWanted(AOwner, mSame, AWanted);
  if (mWanted >= 0) and PairByStages(mSame, mWanted, mDeclaration, mBody, mWay) then
  begin
    AVariant := [mSame[mDeclaration], mSame[mBody]];
    AWay := mWay;
    Exit(True);
  end;
  if Length(AVariant) > 2 then
  begin
    AWay := cPairTypes;
    Exit(True);
  end;
  AVariant := nil;
  Result := False;
end;

/// <summary>Steht eine der Fundstellen AVariant in einer anderen Datei als AFileName (Include-Datei)?</summary>
function ReachesOtherFile(const AOwner: TUnitIndex; const AVariant: TArray<TIndexSymbol>;
  const AFileName: string): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AVariant do
  begin
    if not SameText(AOwner.SymbolFile(mSymbol), AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Diagnoselog (#647, LOG1; nur Codes und Zahlen): warum RoutinePair in AOwner kein Paar fand. pair=none:
/// noSymbol (die Routine steht dort nicht), single (nur eine Fundstelle: keine zweite Hälfte im Index) oder params
/// (mehrere Fundstellen, aber weder zwei mit Parameter- und Ergebnistyp von AWanted noch ein eindeutiges Paar nach
/// Namen oder Reihenfolge), dazu pairSame und pairVariant.</summary>
procedure NoteNoPair(const AOwner: TUnitIndex; const AResolved: TResolvedSymbol; const AWanted: TRoutineWanted);
var
  mSymbol: TIndexSymbol;
  mSame, mVariant: Integer;
begin
  mSame := 0;
  mVariant := 0;
  // Dieselbe Auswahl wie RoutinePair, nur gezählt.
  for mSymbol in SameRoutines(AOwner, AResolved) do
  begin
    Inc(mSame);
    if SameVariant(mSymbol, AWanted.ParamTypes, AWanted.ResultType) then
    begin
      Inc(mVariant);
    end;
  end;
  if mSame = 0 then
  begin
    TRequestDiagnostics.Note('pair', 'none:noSymbol');
  end
  else if mSame = 1 then
  begin
    TRequestDiagnostics.Note('pair', 'none:single');
  end
  else
  begin
    TRequestDiagnostics.Note('pair', 'none:params');
  end;
  TRequestDiagnostics.Note('pairSame', mSame);
  TRequestDiagnostics.Note('pairVariant', mVariant);
end;

/// <summary>Ziel einer Routine: Deklaration und Implementierung derselben Variante. Steht der Cursor auf einer
/// Routine dieser Datei (Deklaration oder Implementierung), gilt deren Variante. Ohne Paar das Symbol selbst.
/// Im Diagnoselog des Servers (nur bei offenem Bereich) steht, ob und auf welchem Weg ein Paar gefunden wurde
/// (pair=found:types|sole|names|order, pairChosen=declaration|implementation) und sonst warum nicht (NoteNoPair,
/// pair=none:noUnit ohne Unit im Index).
/// </summary>
/// <summary>AResolved, wie die einbindende Unit AHost es kennt: Steht die Routine in der Include-Datei AFileName im
/// Klassenrumpf ({$I …} zwischen class und end), sieht der Baum der Include-Datei allein eine freie Routine; der Index
/// der Unit kennt ihren Typ (Container). Sonst AResolved unverändert.</summary>
function HostResolved(const AHost: TUnitIndex; const AResolved: TResolvedSymbol;
  const AFileName: string): TResolvedSymbol;
var
  mSymbol: TIndexSymbol;
begin
  Result := AResolved;
  for mSymbol in AHost.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Name, AResolved.Name) and
      (mSymbol.SelectionRange.StartPos.Line = AResolved.SelectionRange.StartPos.Line) and
      (mSymbol.SelectionRange.StartPos.Character = AResolved.SelectionRange.StartPos.Character) and
      SameText(AHost.SymbolFile(mSymbol), AFileName) then
    begin
      Result.Container := mSymbol.Container;
      Result.SymbolKind := mSymbol.Kind;
      Exit;
    end;
  end;
end;

function RoutineTargets(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AQuery: TDefinitionQuery;
  const AResolved: TResolvedSymbol): TArray<TDefinitionTarget>;
var
  mHere, mOwnerUnit: TUnitIndex;
  mVariant: TArray<TIndexSymbol>;
  mFirst, mLast, mChosen: TIndexSymbol;
  mFound, mToDeclaration: Boolean;
  mWanted: TRoutineWanted;
  mWay: string;
begin
  Result := [Target(AResolved.FileName, AResolved.Range, AResolved.SelectionRange)];
  mHere := AResolver.ExtractedUnit(AQuery.Tree, AQuery.FileName);
  mOwnerUnit := mHere;
  mWanted := WantedOf(mHere, AResolved, AQuery.Position);
  mFound := SameText(AResolved.FileName, AQuery.FileName) or TIndexFiles.UnitOf(AIndex, AResolved.FileName,
    mOwnerUnit);
  if not mFound or not RoutinePair(mOwnerUnit, AResolved, mWanted, mVariant, mWay) then
  begin
    // Include-Dateien (NAV): Der Baum der offenen Datei kennt Deklarationen aus $I-Dateien nicht, ihr Eintrag im
    // Index schon. Nur ein Paar, das in eine andere Datei führt: Zeilen der eigenen Datei stehen im Baum aktueller.
    if not (SameText(AResolved.FileName, AQuery.FileName) and
      TIndexFiles.UnitOf(AIndex, AQuery.FileName, mOwnerUnit) and
      RoutinePair(mOwnerUnit, HostResolved(mOwnerUnit, AResolved, AQuery.FileName), mWanted, mVariant, mWay) and
      ReachesOtherFile(mOwnerUnit, mVariant, AQuery.FileName)) then
    begin
      // Diagnoselog (LOG1): Gezählt wird in der Unit, in der RoutinePair zuerst suchte (bei derselben Datei der Baum,
      // sonst die Unit des Ziels im Index).
      if TRequestDiagnostics.IsOpen then
      begin
        if not mFound then
        begin
          TRequestDiagnostics.Note('pair', 'none:noUnit');
        end
        else if SameText(AResolved.FileName, AQuery.FileName) then
        begin
          NoteNoPair(mHere, AResolved, mWanted);
        end
        else
        begin
          NoteNoPair(mOwnerUnit, AResolved, mWanted);
        end;
      end;
      Exit;
    end;
  end;
  mFirst := mVariant[0];
  mLast := mVariant[High(mVariant)];
  // Deklarationen aus $I-Dateien hängt der Index hinten an (#500): Die im interface ist die Deklaration (NAV).
  if not mFirst.InInterface and mLast.InInterface then
  begin
    mFirst := mVariant[High(mVariant)];
    mLast := mVariant[0];
  end;
  // Mit Include-Dateien (#500) kann jede Fundstelle in einer anderen Datei stehen.
  mChosen := mLast;
  mToDeclaration := AQuery.Declaration or (SameText(mOwnerUnit.SymbolFile(mLast), AQuery.FileName) and
    Within(AQuery.Position, mLast.SelectionRange));
  if mToDeclaration then
  begin
    mChosen := mFirst;
  end;
  Result := [Target(mOwnerUnit.SymbolFile(mChosen), mChosen.Range, mChosen.SelectionRange)];
  // Diagnoselog (LOG1): Paar gefunden und welche Hälfte das Ziel ist.
  if TRequestDiagnostics.IsOpen then
  begin
    TRequestDiagnostics.Note('pair', 'found:' + mWay);
    TRequestDiagnostics.Note('pairVariant', Integer(Length(mVariant)));
    if mToDeclaration then
    begin
      TRequestDiagnostics.Note('pairChosen', 'declaration');
    end
    else
    begin
      TRequestDiagnostics.Note('pairChosen', 'implementation');
    end;
  end;
end;

class function TLspDefinition.TargetsOf(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AQuery: TDefinitionQuery; const AResolved: TResolvedSymbol): TArray<TDefinitionTarget>;
var
  mResolved: TResolvedSymbol;
  mEmpty: TTextRange;
begin
  // Namen in Deklarationen (z. B. Methoden in der Klasse) sind keine Verwendungen:
  // dann gilt die Deklaration unter dem Cursor selbst. Zuerst prüfen: Die
  // Namensauflösung liest einen solchen Namen sonst wie eine Verwendung und nimmt
  // bei Überladungen die erste (Hover auf der zweiten zeigte die erste).
  // Das Ergebnis erst zuweisen statt Exit([...]): In der früheren Form brach dcc64 (Delphi 13) ohne Meldung ab.
  mResolved := DeclarationAt(AResolver, AQuery);
  // Sonst die schon aufgelöste Verwendung des Aufrufers (TargetsOf, #1119).
  if mResolved.Kind = TResolvedKind.None then
  begin
    mResolved := AResolved;
  end;
  case mResolved.Kind of
    TResolvedKind.None:
      Result := nil;
    TResolvedKind.UnitName:
      begin
        mEmpty := TTextRange.Create(TTextPosition.Create(0, 0), TTextPosition.Create(0, 0));
        Result := [Target(mResolved.FileName, mEmpty, mEmpty)];
      end;
    TResolvedKind.Local:
      Result := [Target(AQuery.FileName, mResolved.Range, mResolved.SelectionRange)];
  else
    if mResolved.SymbolKind in cRoutineKinds then
    begin
      Result := RoutineTargets(AResolver, AIndex, AQuery, mResolved);
    end
    else
    begin
      Result := [Target(mResolved.FileName, mResolved.Range, mResolved.SelectionRange)];
    end;
  end;
end;

class function TLspDefinition.TypeTargets(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TDefinitionTarget>;
var
  mTypeInfo: TResolvedSymbol;
begin
  mTypeInfo := AResolver.ResolveType(ATree, AFileName, APosition);
  if mTypeInfo.Kind = TResolvedKind.Symbol then
  begin
    Result := [Target(mTypeInfo.FileName, mTypeInfo.Range, mTypeInfo.SelectionRange)];
  end
  else
  begin
    Result := nil;
  end;
end;

function IsNameChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
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

/// <summary>Bezeichner an APosition in AText; '' außerhalb eines Bezeichners.</summary>
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
end;

/// <summary>Liegt APosition im Code (nicht in Kommentar, String oder Direktive)? Ohne Token dort: ja (Text
/// nicht geltender Zweige).</summary>
function InCodeAt(ATree: TSyntaxTree; const APosition: TTextPosition): Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in ATree.Tokens do
  begin
    if (ComparePositions(mToken.StartPos, APosition) <= 0) and (ComparePositions(APosition, mToken.EndPos) < 0) then
    begin
      Exit(not (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive,
        TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]));
    end;
  end;
  Result := True;
end;

class function TLspDefinition.UnavailableTargets(const AIndex: ISymbolIndex; ATree: TSyntaxTree; const AFileName,
  AText: string; const APosition: TTextPosition): TArray<TDefinitionTarget>;
var
  mUnit: TUnitIndex;
  mName: string;
  mCandidate, mChosen: TIndexSymbol;
  mFound: Boolean;
begin
  Result := nil;
  if not TIndexFiles.UnitOf(AIndex, AFileName, mUnit) or (Length(mUnit.Unavailable) = 0) or
    not InCodeAt(ATree, APosition) then
  begin
    Exit;
  end;
  mName := NameAt(AText, APosition);
  if mName = '' then
  begin
    Exit;
  end;
  mFound := False;
  mChosen := Default(TIndexSymbol);
  for mCandidate in mUnit.Unavailable do
  begin
    if not SameText(mCandidate.Name, mName) then
    begin
      Continue;
    end;
    // Die Deklaration in der Zeile der Stelle geht einer gleichnamigen anderen vor.
    if (mCandidate.SelectionRange.StartPos.Line = APosition.Line) and
      SameText(mUnit.SymbolFile(mCandidate), AFileName) then
    begin
      mChosen := mCandidate;
      mFound := True;
      Break;
    end;
    if not mFound then
    begin
      mChosen := mCandidate;
      mFound := True;
    end;
  end;
  if mFound then
  begin
    Result := [Target(mUnit.SymbolFile(mChosen), mChosen.Range, mChosen.SelectionRange)];
  end;
end;

class function TLspDefinition.ToJson(const ATargets: TArray<TDefinitionTarget>): TJSONArray;
var
  mItem: TDefinitionTarget;
  mLocation: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mItem in ATargets do
  begin
    // Ersatz-Units der IDE (dpcc-ide:…) gibt es nicht als Datei: kein Sprungziel für Strg+Klick.
    if TIdeUnits.IsIdePath(mItem.FileName) then
    begin
      Continue;
    end;
    mLocation := TJSONObject.Create;
    mLocation.AddPair('uri', TDocumentUris.FromPath(mItem.FileName));
    mLocation.AddPair('range', TLspPositions.RangeToJson(mItem.SelectionRange));
    Result.AddElement(mLocation);
  end;
end;

/// <summary>Bezeichner an APosition, sonst direkt davor (Schreibmarke hinter dem Namen); AAt ist die Stelle, an der
/// er steht. '' ohne Bezeichner.</summary>
function IdentifierAt(const AText: string; const APosition: TTextPosition; out AAt: TTextPosition): string;
begin
  AAt := APosition;
  Result := NameAt(AText, AAt);
  if (Result = '') and (APosition.Character > 0) then
  begin
    AAt := TTextPosition.Create(APosition.Line, APosition.Character - 1);
    Result := NameAt(AText, AAt);
  end;
end;

/// <summary>Steht an APosition ein Token des Baums? Nein in nicht geltenden Zweigen: Der Baum entsteht aus dem Text
/// ohne sie.</summary>
function HasTokenAt(ATree: TSyntaxTree; const APosition: TTextPosition): Boolean;
var
  mToken: TPascalToken;
begin
  for mToken in ATree.Tokens do
  begin
    if (ComparePositions(mToken.StartPos, APosition) <= 0) and (ComparePositions(APosition, mToken.EndPos) < 0) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Unit AName (auch mit einem der ANamespaces davor) im Index.</summary>
function FindUsedUnit(const AIndex: ISymbolIndex; const AName: string; const ANamespaces: TArray<string>;
  out AUnit: TUnitIndex): Boolean;
var
  mNamespace: string;
begin
  if AIndex.FindUnit(AName, AUnit) then
  begin
    Exit(True);
  end;
  for mNamespace in ANamespaces do
  begin
    if AIndex.FindUnit(mNamespace + '.' + AName, AUnit) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Deklariert eine der Units AUses AName nur in einem nicht geltenden Zweig?</summary>
function DeclaredInactive(const AIndex: ISymbolIndex; const AUses, ANamespaces: TArray<string>;
  const AName: string): Boolean;
var
  mUsed: string;
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  if AIndex = nil then
  begin
    Exit(False);
  end;
  for mUsed in AUses do
  begin
    if not FindUsedUnit(AIndex, mUsed, ANamespaces, mUnit) then
    begin
      Continue;
    end;
    for mSymbol in mUnit.Unavailable do
    begin
      if SameText(mSymbol.Name, AName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Name fürs Diagnoselog: nur eine Kennzahl, nie der Bezeichner (#647).</summary>
function NameLabel(const AName: string): string;
begin
  Result := 'h' + IntToHex(Cardinal(THashFNV1a32.GetHashValue(UpperCase(AName))), 8);
end;

/// <summary>Führen alle Ziele in Ersatz-Units der IDE (und gibt es welche)?</summary>
function OnlyIdeTargets(const ATargets: TArray<TDefinitionTarget>): Boolean;
var
  mTarget: TDefinitionTarget;
begin
  Result := Length(ATargets) > 0;
  for mTarget in ATargets do
  begin
    if not TIdeUnits.IsIdePath(mTarget.FileName) then
    begin
      Exit(False);
    end;
  end;
end;

class function TLspDefinition.IdeUnitName(const AFileName: string): string;
begin
  Result := AFileName;
  if TIdeUnits.IsIdePath(Result) then
  begin
    Result := Copy(Result, Length(TIdeUnits.cPathPrefix) + 1, MaxInt);
  end;
  if SameText(ExtractFileExt(Result), '.pas') then
  begin
    Result := ChangeFileExt(Result, '');
  end;
end;

class function TLspDefinition.Explain(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName, AText: string; const APosition: TTextPosition;
  const ATargets: TArray<TDefinitionTarget>): TDefinitionNoTarget;
var
  mTarget: TDefinitionTarget;
  mAt: TTextPosition;
  mOwn: TUnitIndex;
  mUses: TArray<string>;
  mMissing: string;
begin
  Result := Default(TDefinitionNoTarget);
  // Aufgelöst, aber nur in eine Ersatz-Unit der IDE: Package ohne Quelltext.
  for mTarget in ATargets do
  begin
    if TIdeUnits.IsIdePath(mTarget.FileName) then
    begin
      Result.Reason := cReasonNoSource;
      Result.Name := IdeUnitName(mTarget.FileName);
      Exit;
    end;
  end;
  Result.Name := IdentifierAt(AText, APosition, mAt);
  if (Result.Name = '') or not InCodeAt(ATree, mAt) then
  begin
    Result.Reason := cReasonNoIdentifier;
    Result.Name := '';
    Exit;
  end;
  // Ein Bezeichner im Text, aber kein Token im Baum: Die Stelle liegt in einem nicht geltenden Zweig.
  if not HasTokenAt(ATree, mAt) then
  begin
    Result.Reason := cReasonInactiveBranch;
    Exit;
  end;
  mOwn := AResolver.ExtractedUnit(ATree, AFileName);
  mUses := mOwn.InterfaceUses + mOwn.ImplementationUses;
  // Eine Unit aus uses fehlt (Package ohne gefundene Quelle): Sie ist der wahrscheinliche Ort der Deklaration.
  for mMissing in AResolver.MissingUnits do
  begin
    if IndexText(mMissing, mUses) >= 0 then
    begin
      Result.Reason := cReasonUnitNotFound;
      Result.Name := mMissing;
      Exit;
    end;
  end;
  if DeclaredInactive(AIndex, mUses, AResolver.Namespaces, Result.Name) then
  begin
    Result.Reason := cReasonInactiveBranch;
    Exit;
  end;
  Result.Reason := cReasonUnresolved;
end;

/// <summary>Token an APosition (auch direkt dahinter, wie IdentifierAt); -1 ohne. Die Token sind nach ihrer Stelle
/// sortiert und überlappen nicht.</summary>
function TokenIndexAt(ATree: TSyntaxTree; const APosition: TTextPosition): Integer;
var
  mTokens: TArray<TPascalToken>;
  mLow, mHigh, mMiddle: Integer;
begin
  mTokens := ATree.Tokens;
  mLow := 0;
  mHigh := Length(mTokens);
  while mLow < mHigh do
  begin
    mMiddle := (mLow + mHigh) div 2;
    if ComparePositions(mTokens[mMiddle].EndPos, APosition) < 0 then
    begin
      mLow := mMiddle + 1;
    end
    else
    begin
      mHigh := mMiddle;
    end;
  end;
  if (mLow <= High(mTokens)) and (ComparePositions(mTokens[mLow].StartPos, APosition) <= 0) then
  begin
    Exit(mLow);
  end;
  Result := -1;
end;

/// <summary>Name der Methode (ohne Klasse), in deren Rumpf AOffset liegt: die äußerste Routine mit Punkt im Namen
/// (procedure TFoo.Bar, wie TResolverTyping.MethodTypeName); '' außerhalb.</summary>
function OutermostMethodName(ANode: TSyntaxNode; AOffset: Integer): string;
var
  mIndex: Integer;
  mChild: TSyntaxNode;
begin
  Result := '';
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := ANode[mIndex];
    if (mChild.StartOffset <= AOffset) and (AOffset < mChild.EndOffset) then
    begin
      if (mChild.Kind = TSyntaxKind.RoutineDecl) and (Pos('.', mChild.Name) > 0) then
      begin
        Exit(Copy(mChild.Name, LastDelimiter('.', mChild.Name) + 1, MaxInt));
      end;
      Exit(OutermostMethodName(mChild, AOffset));
    end;
  end;
end;

/// <summary>"inherited" ohne Namen dahinter (inherited; inherited end) an APosition: die gleichnamige Methode im
/// Vorfahren der Klasse der umgebenden Methode, wie bei "inherited Name" (Entscheidung des Nutzers, 26.11.2026).
/// Kind None an anderen Stellen. Bei Überladungen im Vorfahren gilt die erste.</summary>
function BareInheritedAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TResolvedSymbol;
var
  mIndex: Integer;
  mToken: TPascalToken;
  mName: string;
begin
  Result := Default(TResolvedSymbol);
  mIndex := TokenIndexAt(ATree, APosition);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mToken := ATree.Tokens[mIndex];
  if not mToken.IsKeyword('inherited') or
    ((mIndex < High(ATree.Tokens)) and (ATree.Tokens[mIndex + 1].Kind = TPascalTokenKind.Identifier)) then
  begin
    Exit;
  end;
  mName := OutermostMethodName(ATree.Root, mToken.Offset);
  if mName <> '' then
  begin
    Result := AResolver.ResolveChain(ATree, AFileName, [mName], mToken.Offset, True);
  end;
end;

/// <summary>Dateiname einer Include-Direktive ({$I Name}, {$INCLUDE Name}, auch (*$I …*)) an APosition: True mit
/// dem Namen, wenn APosition darauf steht. {$I+}/{$I-} (I/O-Prüfung) und andere Direktiven zählen nicht.</summary>
function IncludeNameAt(ATree: TSyntaxTree; const APosition: TTextPosition; out AName: string): Boolean;
var
  mIndex, mStart, mEnd, mWordEnd: Integer;
  mToken: TPascalToken;
  mText, mWord: string;
begin
  Result := False;
  AName := '';
  mIndex := TokenIndexAt(ATree, APosition);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mToken := ATree.Tokens[mIndex];
  if (mToken.Kind <> TPascalTokenKind.Directive) or (mToken.StartPos.Line <> mToken.EndPos.Line) or
    (mToken.StartPos.Line <> APosition.Line) then
  begin
    Exit;
  end;
  mText := mToken.Text;
  // Anfang hinter "{$" bzw. "(*$", Ende vor "}" bzw. "*)" (Stellen 1-basiert in mText).
  if StartsText('{$', mText) then
  begin
    mStart := 3;
  end
  else if StartsText('(*$', mText) then
  begin
    mStart := 4;
  end
  else
  begin
    Exit;
  end;
  mEnd := Length(mText);
  if EndsText('*)', mText) then
  begin
    mEnd := Length(mText) - 2;
  end
  else if EndsText('}', mText) then
  begin
    mEnd := Length(mText) - 1;
  end;
  mWordEnd := mStart;
  while (mWordEnd <= mEnd) and CharInSet(mText[mWordEnd], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(mWordEnd);
  end;
  mWord := Copy(mText, mStart, mWordEnd - mStart);
  if not (SameText(mWord, 'I') or SameText(mWord, 'INCLUDE')) or (mWordEnd > mEnd) or (mText[mWordEnd] > ' ') then
  begin
    Exit;
  end;
  // Der Name: ab dem ersten Zeichen nach den Leerzeichen bis zum Ende der Direktive, ohne Leerzeichen am Ende.
  mStart := mWordEnd;
  while (mStart <= mEnd) and (mText[mStart] <= ' ') do
  begin
    Inc(mStart);
  end;
  while (mEnd >= mStart) and (mText[mEnd] <= ' ') do
  begin
    Dec(mEnd);
  end;
  if mEnd < mStart then
  begin
    Exit;
  end;
  // Klick auf dem Namen (oder direkt dahinter): Zeichen der Zeile ab dem Anfang des Tokens.
  if (APosition.Character < mToken.StartPos.Character + mStart - 1) or
    (APosition.Character > mToken.StartPos.Character + mEnd) then
  begin
    Exit;
  end;
  AName := Copy(mText, mStart, mEnd - mStart + 1);
  Result := True;
end;

/// <summary>Ziel der Include-Direktive an APosition in AFileName: Anfang der eingebundenen Datei, wie ein Unit-Name in
/// uses (Entscheidung des Nutzers, 26.11.2026). Zuerst die Include-Dateien der Unit im Index (dort auch über die
/// Suchpfade gefunden), sonst neben der Datei bzw. mit ".inc"/".pas" wie der Compiler. Leer ohne.</summary>
function IncludeTargets(const AIndex: ISymbolIndex; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition): TArray<TDefinitionTarget>;
var
  mName, mPlain, mFound, mInclude: string;
  mUnit: TUnitIndex;
  mEmpty: TTextRange;
begin
  Result := nil;
  if not IncludeNameAt(ATree, APosition, mName) then
  begin
    Exit;
  end;
  mPlain := mName;
  if (Length(mPlain) >= 2) and (mPlain[1] = '''') and (mPlain[Length(mPlain)] = '''') then
  begin
    mPlain := Copy(mPlain, 2, Length(mPlain) - 2);
  end;
  mFound := '';
  if (AIndex <> nil) and TIndexFiles.UnitOf(AIndex, AFileName, mUnit) then
  begin
    for mInclude in mUnit.Includes do
    begin
      if SameText(ExtractFileName(mInclude), ExtractFileName(mPlain)) or
        ((ExtractFileExt(mPlain) = '') and (SameText(ExtractFileName(mInclude), ExtractFileName(mPlain) + '.inc') or
        SameText(ExtractFileName(mInclude), ExtractFileName(mPlain) + '.pas'))) then
      begin
        mFound := mInclude;
        Break;
      end;
    end;
  end;
  if (mFound = '') and not TIncludeFiles.FindInclude(mPlain, AFileName, nil,
    function(const APath: string): Boolean
    begin
      Result := FileExists(APath);
    end, mFound) then
  begin
    Exit;
  end;
  mEmpty := TTextRange.Create(TTextPosition.Create(0, 0), TTextPosition.Create(0, 0));
  Result := [Target(mFound, mEmpty, mEmpty)];
end;

function TLspDefinition.ResolveTargets(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const APosition: TTextPosition; ADeclaration: Boolean): TArray<TDefinitionTarget>;
var
  mInherited: TResolvedSymbol;
begin
  // Dateiname in {$I …}/{$INCLUDE …}: die Datei öffnen.
  Result := IncludeTargets(FIndex, ATree, AFileName, APosition);
  if Length(Result) > 0 then
  begin
    Exit;
  end;
  Result := Targets(AResolver, FIndex, ATree, AFileName, APosition, ADeclaration);
  // "inherited;" ohne Namen: die gleichnamige Methode des Vorfahren.
  if Length(Result) = 0 then
  begin
    mInherited := BareInheritedAt(AResolver, ATree, AFileName, APosition);
    if mInherited.Kind <> TResolvedKind.None then
    begin
      Result := TargetsOf(AResolver, FIndex, TDefinitionQuery.Create(ATree, AFileName, APosition, ADeclaration),
        mInherited);
    end;
  end;
  // Nichts aufgelöst: vielleicht eine Deklaration aus einem nicht geltenden Zweig (NAV).
  if Length(Result) = 0 then
  begin
    Result := UnavailableTargets(FIndex, ATree, AFileName, AText, APosition);
  end;
end;

function TLspDefinition.LoadIdeSources(const ATargets: TArray<TDefinitionTarget>): Boolean;
var
  mTarget: TDefinitionTarget;
begin
  Result := False;
  if not Assigned(FEnsureUnit) then
  begin
    Exit;
  end;
  for mTarget in ATargets do
  begin
    if TIdeUnits.IsIdePath(mTarget.FileName) and FEnsureUnit(IdeUnitName(mTarget.FileName)) then
    begin
      Result := True;
    end;
  end;
end;

procedure TLspDefinition.ReportNoTarget(AKind: TDefinitionRequestKind; const AUri: string;
  const APosition: TTextPosition; const AWhy: TDefinitionNoTarget);
var
  mIndexing: Boolean;
  mParams: TJSONObject;
  mMethod: string;
begin
  mIndexing := Assigned(FIndexing) and FIndexing();
  // Diagnoselog (#647): der Grund statt empty:unspecified, der Name nur als Kennzahl.
  TRequestDiagnostics.Reason(AWhy.Reason);
  if AWhy.Name <> '' then
  begin
    TRequestDiagnostics.Note('name', NameLabel(AWhy.Name));
  end;
  TRequestDiagnostics.Note('indexing', mIndexing);
  if (AKind = TDefinitionRequestKind.TypeDefinition) or not Assigned(FNotify) then
  begin
    Exit;
  end;
  mMethod := cDefinitionMethod;
  if AKind = TDefinitionRequestKind.Declaration then
  begin
    mMethod := cDeclarationMethod;
  end;
  mParams := TJSONObject.Create;
  mParams.AddPair('method', mMethod);
  mParams.AddPair('uri', AUri);
  mParams.AddPair('line', TJSONNumber.Create(APosition.Line));
  mParams.AddPair('character', TJSONNumber.Create(APosition.Character));
  mParams.AddPair('reason', AWhy.Reason);
  mParams.AddPair('name', AWhy.Name);
  mParams.AddPair('indexing', TJSONBool.Create(mIndexing));
  // Im Thread der Anfrage und vor ihrer Antwort: Der Client sieht den Grund vor dem leeren Ergebnis. Die Meldung ist
  // ein Zusatz; scheitert sie, bleibt die Antwort.
  try
    FNotify(cNoTargetMethod, mParams);
  except
    // lsp-ignore: catch-all-without-raise -- Zusatzmeldung; die Antwort geht trotzdem
    on Exception do
      ;
  end;
end;

function TLspDefinition.Handle(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
  AKind: TDefinitionRequestKind): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri, mFileName: string;
  mPositionValue: TJSONValue;
  mPosition: TTextPosition;
  mDocument: ITextDocument;
  mTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
  mResolver: TNameResolver;
  mTargets: TArray<TDefinitionTarget>;
  mJson: TJSONArray;
  mWhy: TDefinitionNoTarget;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPositionValue)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TDefinitionText.FieldsTextDocumentUriAndPosition].Text);
  end;
  mPosition := TLspPositions.ReadPosition(mPositionValue);
  if not FStore.TryGet(mUri, mDocument) then
  begin
    mWhy := Default(TDefinitionNoTarget);
    mWhy.Reason := cReasonNoDocument;
    ReportNoTarget(AKind, mUri, mPosition, mWhy);
    Exit(TJSONNull.Create);
  end;
  if TDfmParser.IsFormFile(mUri) then
  begin
    Result := FormTargets(mDocument.Text, mUri, mPosition);
    if not ((Result is TJSONArray) and (TJSONArray(Result).Count > 0)) then
    begin
      mWhy := Default(TDefinitionNoTarget);
      mWhy.Reason := cReasonOther;
      ReportNoTarget(AKind, mUri, mPosition, mWhy);
    end;
    Exit;
  end;
  mFileName := TDocumentUris.ToPath(mUri);
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mShared := TSyntaxTreeCache.Get(mDocument, mCancellation);
  mTree := mShared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  // Je Anfrage ein eigener Resolver: er hält Zustand pro Aufruf.
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mResolver.Namespaces := Namespaces;
    if AKind = TDefinitionRequestKind.TypeDefinition then
    begin
      Exit(ToJson(TypeTargets(mResolver, mTree, mFileName, mPosition)));
    end;
    mTargets := ResolveTargets(mResolver, mTree, mFileName, mDocument.Text, mPosition,
      AKind = TDefinitionRequestKind.Declaration);
    // Nur Ersatz-Units der IDE: Ein Package ohne Quelle im Index verdeckte die echte Unit (sie wurde nie
    // nachgeladen, weil die Ersatz-Unit den Namen schon lieferte). Echte Quelle laden und neu auflösen; die Antworten
    // des alten Resolvers kennen nur die Ersatz-Unit.
    if OnlyIdeTargets(mTargets) and LoadIdeSources(mTargets) then
    begin
      FreeAndNil(mResolver);
      mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
      mResolver.Namespaces := Namespaces;
      mTargets := ResolveTargets(mResolver, mTree, mFileName, mDocument.Text, mPosition,
        AKind = TDefinitionRequestKind.Declaration);
    end;
    mJson := ToJson(mTargets);
    try
      if mJson.Count = 0 then
      begin
        ReportNoTarget(AKind, mUri, mPosition, Explain(mResolver, FIndex, mTree, mFileName, mDocument.Text,
          mPosition, mTargets));
      end;
    except
      mJson.Free;
      raise;
    end;
    Result := mJson;
  finally
    mResolver.Free;
  end;
end;

function TLspDefinition.FormTargets(const AText, AUri: string; const APosition: TTextPosition): TJSONValue;
var
  mFound: TArray<TDfmTarget>;
  mTargets: TArray<TDefinitionTarget>;
  mIndex: Integer;
begin
  if not Assigned(FReadText) then
  begin
    Exit(TJSONNull.Create);
  end;
  mFound := TDfmNavigation.Targets(AText, TDocumentUris.ToPath(AUri), APosition, FReadText);
  SetLength(mTargets, Length(mFound));
  for mIndex := 0 to High(mFound) do
  begin
    mTargets[mIndex] := Target(mFound[mIndex].FileName, mFound[mIndex].Range, mFound[mIndex].SelectionRange);
  end;
  Result := ToJson(mTargets);
end;

function TLspDefinition.HandleDefinition(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, ACancellation, TDefinitionRequestKind.Definition);
end;

function TLspDefinition.HandleDeclaration(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, ACancellation, TDefinitionRequestKind.Declaration);
end;

function TLspDefinition.HandleTypeDefinition(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Handle(AParams, ACancellation, TDefinitionRequestKind.TypeDefinition);
end;

initialization
  TDpccTextTables.Add('dpcc.Common.Lsp.Definition', cTexts);

end.
