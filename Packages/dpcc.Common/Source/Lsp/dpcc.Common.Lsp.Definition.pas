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
// Variante (gleiche Parametertypen) zusammen; steht der Cursor auf einer
// Routine der Datei, gilt deren Variante. Vorher galt immer die erste
// Überladung (Hover auf der zweiten zeigte die erste).
// Unit-Namen (z. B. in uses) führen an den Anfang der Unit-Datei.
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

/// <summary>Gleiche Parametertypen (Groß-/Kleinschreibung egal): dieselbe Variante einer Überladung.</summary>
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
    if not SameText(A[mIndex], B[mIndex]) then
    begin
      Exit(False);
    end;
  end;
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
      Exit;
    end;
  end;
end;

/// <summary>Parametertypen der gemeinten Variante: die der Routine unter dem Cursor in AHere, sonst die von
/// AResolved.</summary>
function VariantParams(AHere: TUnitIndex; const AResolved: TResolvedSymbol;
  const APosition: TTextPosition): TArray<string>;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AHere.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Name, AResolved.Name) and
      Within(APosition, mSymbol.SelectionRange) then
    begin
      Exit(mSymbol.ParamTypes);
    end;
  end;
  Result := AResolved.ParamTypes;
end;

/// <summary>Fundstellen der Routine AResolved in AOwner: erst die Variante mit AParams, ohne zweite Fundstelle
/// das einzige Paar ohne Überladungen (die Implementierung darf ihre Parameter weglassen). False ohne Paar.
/// </summary>
function RoutinePair(AOwner: TUnitIndex; const AResolved: TResolvedSymbol; const AParams: TArray<string>;
  out AVariant: TArray<TIndexSymbol>): Boolean;
var
  mSymbol: TIndexSymbol;
  mSame: TArray<TIndexSymbol>;
begin
  mSame := nil;
  AVariant := nil;
  for mSymbol in AOwner.Symbols do
  begin
    if (mSymbol.Kind in cRoutineKinds) and SameText(mSymbol.Container, AResolved.Container) and
      SameText(mSymbol.Name, AResolved.Name) then
    begin
      mSame := mSame + [mSymbol];
      if SameParams(mSymbol.ParamTypes, AParams) then
      begin
        AVariant := AVariant + [mSymbol];
      end;
    end;
  end;
  if (Length(AVariant) < 2) and (Length(mSame) = 2) then
  begin
    AVariant := mSame;
  end;
  Result := Length(AVariant) >= 2;
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

/// <summary>Ziel einer Routine: Deklaration und Implementierung derselben Variante. Steht der Cursor auf einer
/// Routine dieser Datei (Deklaration oder Implementierung), gilt deren Variante. Ohne Paar das Symbol selbst.
/// </summary>
function RoutineTargets(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AQuery: TDefinitionQuery;
  const AResolved: TResolvedSymbol): TArray<TDefinitionTarget>;
var
  mHere, mOwnerUnit: TUnitIndex;
  mVariant: TArray<TIndexSymbol>;
  mFirst, mLast, mChosen: TIndexSymbol;
  mFound: Boolean;
begin
  Result := [Target(AResolved.FileName, AResolved.Range, AResolved.SelectionRange)];
  mHere := AResolver.ExtractedUnit(AQuery.Tree, AQuery.FileName);
  mOwnerUnit := mHere;
  mFound := SameText(AResolved.FileName, AQuery.FileName) or TIndexFiles.UnitOf(AIndex, AResolved.FileName,
    mOwnerUnit);
  if not mFound or not RoutinePair(mOwnerUnit, AResolved, VariantParams(mHere, AResolved, AQuery.Position),
    mVariant) then
  begin
    // Include-Dateien (NAV): Der Baum der offenen Datei kennt Deklarationen aus $I-Dateien nicht, ihr Eintrag im
    // Index schon. Nur ein Paar, das in eine andere Datei führt: Zeilen der eigenen Datei stehen im Baum aktueller.
    if not (SameText(AResolved.FileName, AQuery.FileName) and
      TIndexFiles.UnitOf(AIndex, AQuery.FileName, mOwnerUnit) and
      RoutinePair(mOwnerUnit, AResolved, VariantParams(mHere, AResolved, AQuery.Position), mVariant) and
      ReachesOtherFile(mOwnerUnit, mVariant, AQuery.FileName)) then
    begin
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
  if AQuery.Declaration or (SameText(mOwnerUnit.SymbolFile(mLast), AQuery.FileName) and
    Within(AQuery.Position, mLast.SelectionRange)) then
  begin
    mChosen := mFirst;
  end;
  Result := [Target(mOwnerUnit.SymbolFile(mChosen), mChosen.Range, mChosen.SelectionRange)];
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

function TLspDefinition.ResolveTargets(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName,
  AText: string; const APosition: TTextPosition; ADeclaration: Boolean): TArray<TDefinitionTarget>;
begin
  Result := Targets(AResolver, FIndex, ATree, AFileName, APosition, ADeclaration);
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
