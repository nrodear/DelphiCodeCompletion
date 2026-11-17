unit dpcc.Common.Semantics.NameResolver.Expressions;

// Ausdrücke der Namensauflösung: der erste Name einer Kette (lokal, Mitglied der Methodenklasse, Unit, global,
// with-Mitglied), Werte von Ausdrücken (Aufruf, Index, Typumwandlung, Literal) und die Auswahl passender
// Überladungen nach Zahl und Typ der Argumente.

interface

uses
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Semantics.NameResolver.Symbols,
  dpcc.Common.Semantics.NameResolver.Place,
  dpcc.Common.Semantics.NameResolver.Units,
  dpcc.Common.Semantics.NameResolver.Lookup,
  dpcc.Common.Semantics.NameResolver.Typing,
  dpcc.Common.Semantics.NameResolver.Members,
  dpcc.Common.Semantics.NameResolver.Locals;

type
  /// <summary>Die Teile der Namensauflösung, auf denen Ausdrücke, Ketten, Kandidaten und Abfragen aufbauen.
  /// </summary>
  TResolverParts = record
    Place: TResolverPlace;
    Units: TResolverUnits;
    Lookup: TResolverLookup;
    Typing: TResolverTyping;
    Members: TResolverMembers;
    Locals: TResolverLocals;
  end;

  TResolverExpressions = class
  private
    FPlace: TResolverPlace;
    FUnits: TResolverUnits;
    FLookup: TResolverLookup;
    FTyping: TResolverTyping;
    FMembers: TResolverMembers;
    FLocals: TResolverLocals;
    function ClassMember(const AName: string; out AResult: TResolvedSymbol): Boolean;
    function UnitPrefix(const ANames: TArray<string>; out AConsumed: Integer; out AResult: TResolvedSymbol): Boolean;
    function GlobalName(const AName: string; out AResult: TResolvedSymbol): Boolean;
    function Overloads(const AName: string; AConsumed: Integer; const AFirst: TResolvedSymbol): TArray<TResolvedSymbol>;
    function IdentifierCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
    function AccessCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
    function UnitMemberCandidates(const AOwner: TResolvedSymbol; const AName: string): TArray<TResolvedSymbol>;
    function TypeMemberCandidates(const AOwner, AType: TResolvedSymbol; const AName: string): TArray<TResolvedSymbol>;
    function NodeSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function FirstCandidate(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function MemberSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function GenericMemberSymbol(ANode, AArgs: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function CallSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function IndexSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function ElementSymbol(const AType: TResolvedSymbol; out AResult: TResolvedSymbol): Boolean;
    function OperandType(ANode: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
    function OperatorResult(const AType: TResolvedSymbol; const ANames: TArray<string>;
      out AResult: TResolvedSymbol): Boolean;
    function DerefSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function AddressSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function UnarySymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function BinarySymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function SetSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    function ProceduralResult(const ACallee: TResolvedSymbol; out AResult: TResolvedSymbol): Boolean;
    procedure InferTypeArguments(ANode: TSyntaxNode; var ACallee: TResolvedSymbol);
    function DeclaredBase(const ACandidate: TResolvedSymbol; const AParam: string; out ABase: TResolvedSymbol): Boolean;
    function ParamFits(const ACandidate: TResolvedSymbol; AArg: Integer; const AArgType: string;
      out ASame: Boolean): Boolean;
    function CandidateScore(const ACandidate: TResolvedSymbol; AArgCount: Integer;
      const AArgTypes: TArray<string>): Integer;
  public
    constructor Create(const AParts: TResolverParts);
    /// <summary>Erster Name einer Kette an der Stelle; AConsumed: wie viele Namen er verbraucht (Unit-Namen mit
    /// Punkten).</summary>
    function ResolveFirst(const ANames: TArray<string>; out AConsumed: Integer; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Wie ResolveFirst, mit with-Mitgliedern zuerst und allen Überladungen einer Routine.</summary>
    function ResolveFirstAll(const ANames: TArray<string>; out AConsumed: Integer;
      out AResults: TArray<TResolvedSymbol>): Boolean;
    /// <summary>Mögliche Symbole des Ausdrucks ANode (alle Überladungen eines Namens).</summary>
    function ExprCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
    /// <summary>Symbol, für das der Ausdruck ANode steht; bei Werten das Symbol, dessen Typ der Wert hat.</summary>
    function ExprSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Element, über das for-in mit dem Ausdruck ANode läuft (L3): Arrays, Mengen, Zeichen eines
    /// Strings, sonst GetEnumerator.Current; ein Wert bzw. die Property Current.</summary>
    function ElementSymbolOf(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Typnamen der Argumente von ANode ab dem Kind AFirst; '' = unbekannt.</summary>
    function ArgTypes(ANode: TSyntaxNode; AFirst: Integer): TArray<string>;
    /// <summary>Überladungen, die zu AArgCount Argumenten der Typen AArgTypes passen; die mit den meisten genau
    /// passenden Typen. AArgCount &lt; 0: alle.</summary>
    function SelectOverloads(const ACandidates: TArray<TResolvedSymbol>; AArgCount: Integer;
      const AArgTypes: TArray<string>): TArray<TResolvedSymbol>;
    /// <summary>Mitglieder AName der umgebenden with-Ausdrücke; AStop: ein Ausdruck hat einen unbekannten Typ.
    /// </summary>
    function LookupWith(const AName: string; out AResults: TArray<TResolvedSymbol>; out AStop: Boolean): Boolean;
    /// <summary>Wie LookupWith, dazu die with-Anweisung und der Platz ihres Ausdrucks.</summary>
    function LookupWithOwner(const AName: string; out AResults: TArray<TResolvedSymbol>; out AStop: Boolean;
      out AWith: TSyntaxNode; out AElement: Integer): Boolean;
    /// <summary>Typ des Ausdrucks AIndex der with-Anweisung AWith, an seiner eigenen Stelle aufgelöst.</summary>
    function WithElementType(AWith: TSyntaxNode; AIndex: Integer; out AType: TResolvedSymbol): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  dpcc.Common.Index.Contract,
  dpcc.Common.Index.Extractor;

/// <summary>Setzt bei allen Konstruktoren in AList den erzeugten Typ AType.</summary>
procedure MarkConstructed(var AList: TArray<TResolvedSymbol>; const AType: TResolvedSymbol);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AList) do
  begin
    if AList[mIndex].SymbolKind = TIndexSymbolKind.Constructor_ then
    begin
      AList[mIndex].Constructed := [AType];
    end;
  end;
end;

/// <summary>Typ eines Literals: Text, Gleitkomma oder Ganzzahl.</summary>
function LiteralSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mText: string;
begin
  mText := ANode.Name;
  Result := mText <> '';
  if not Result then
  begin
    Exit;
  end;
  if CharInSet(mText[1], ['''', '#']) then
  begin
    AResult := TResolvedSymbol.BuiltinOf('string');
  end
  else if not CharInSet(mText[1], ['0'..'9', '$', '%']) then
  begin
    Result := False;
  end
  else if (mText[1] <> '$') and ((Pos('.', mText) > 0) or (Pos('E', UpperCase(mText)) > 0)) then
  begin
    AResult := TResolvedSymbol.BuiltinOf('Double');
  end
  else
  begin
    AResult := TResolvedSymbol.BuiltinOf('Integer');
  end;
end;

/// <summary>Wert des eingebauten Typs AName (L3).</summary>
function BuiltinValue(const AName: string): TResolvedSymbol;
begin
  Result := TResolvedSymbol.ValueOf(TResolvedSymbol.BuiltinOf(AName));
end;

/// <summary>Namen der Methoden "class operator" für den Operator AOperator (L3), wie Delphi sie vergibt.
/// </summary>
function OperatorNames(const AOperator: string; AUnary: Boolean): TArray<string>;
const
  cBinary: array[0..16, 0..1] of string = (('+', 'Add'), ('-', 'Subtract'), ('*', 'Multiply'), ('/', 'Divide'),
    ('div', 'IntDivide'), ('mod', 'Modulus'), ('shl', 'LeftShift'), ('shr', 'RightShift'), ('and', 'LogicalAnd'),
    ('or', 'LogicalOr'), ('xor', 'LogicalXor'), ('=', 'Equal'), ('<>', 'NotEqual'), ('<', 'LessThan'),
    ('>', 'GreaterThan'), ('<=', 'LessThanOrEqual'), ('>=', 'GreaterThanOrEqual'));
var
  mIndex: Integer;
begin
  Result := nil;
  if AUnary then
  begin
    if AOperator = '-' then
    begin
      Result := ['Negative'];
    end
    else if AOperator = '+' then
    begin
      Result := ['Positive'];
    end
    else if AOperator = 'not' then
    begin
      Result := ['LogicalNot'];
    end;
    Exit;
  end;
  for mIndex := Low(cBinary) to High(cBinary) do
  begin
    if cBinary[mIndex, 0] = AOperator then
    begin
      Result := [cBinary[mIndex, 1]];
    end;
  end;
  // and/or/xor auf Ganzzahlen heißen Bitwise…
  if (AOperator = 'and') or (AOperator = 'or') or (AOperator = 'xor') then
  begin
    Result := Result + ['Bitwise' + UpperCase(AOperator[1]) + Copy(AOperator, 2, MaxInt)];
  end;
end;

/// <summary>Ganzzahliges Ergebnis zweier Operanden: Int64, wenn einer 64 Bit hat, sonst Integer.</summary>
function IntegerResult(const ALeft, ARight: string): string;
begin
  if SameText(ALeft, 'Int64') or SameText(ARight, 'Int64') or SameText(ALeft, 'UInt64') or
    SameText(ARight, 'UInt64') then
  begin
    Result := 'Int64';
  end
  else
  begin
    Result := 'Integer';
  end;
end;

/// <summary>Ergebnis mit Gleitkomma: Currency bleibt Currency, Double bleibt Double, sonst Extended.</summary>
function FloatResult(const ALeft, ARight: string): string;
begin
  if SameText(ALeft, 'Currency') or SameText(ARight, 'Currency') then
  begin
    Result := 'Currency';
  end
  else if (SameText(ALeft, 'Double') or not TResolverText.IsFloatName(ALeft)) and
    (SameText(ARight, 'Double') or not TResolverText.IsFloatName(ARight)) then
  begin
    Result := 'Double';
  end
  else
  begin
    Result := 'Extended';
  end;
end;

/// <summary>Text eines Typs als Typargument, auflösbar aus einer anderen Unit (Unit.Typ&lt;Argumente&gt;); ''
/// bei lokalen und verschachtelten Typen.</summary>
function TypeArgumentText(const AType: TResolvedSymbol): string;
var
  mBinding: string;
  mArgs: TArray<string>;
begin
  Result := '';
  if AType.Builtin then
  begin
    Exit(AType.Name);
  end;
  if (AType.Kind <> TResolvedKind.Symbol) or (AType.Container <> '') or (AType.UnitName = '') or
    (Pos('^', AType.Name) > 0) or (Pos(' ', AType.Name) > 0) then
  begin
    Exit;
  end;
  Result := AType.UnitName + '.' + AType.Name;
  mArgs := nil;
  for mBinding in AType.Bindings do
  begin
    mArgs := mArgs + [Copy(mBinding, Pos('=', mBinding) + 1, MaxInt)];
  end;
  if Length(mArgs) > 0 then
  begin
    Result := Result + '<' + string.Join(',', mArgs) + '>';
  end;
end;

/// <summary>Ist der Typparameter AParam in ABindings schon gebunden?</summary>
function IsBound(const AParam: string; const ABindings: TArray<string>): Boolean;
var
  mBinding: string;
begin
  for mBinding in ABindings do
  begin
    if SameText(Copy(mBinding, 1, Pos('=', mBinding) - 1), AParam) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Einträge aus AFitting, deren Wertung in AScores die beste ist.</summary>
function BestScored(const AFitting: TArray<TResolvedSymbol>; const AScores: TArray<Integer>): TArray<TResolvedSymbol>;
var
  mBest, mIndex: Integer;
begin
  mBest := MaxIntValue(AScores);
  Result := nil;
  for mIndex := 0 to High(AFitting) do
  begin
    if AScores[mIndex] = mBest then
    begin
      Result := Result + [AFitting[mIndex]];
    end;
  end;
end;

constructor TResolverExpressions.Create(const AParts: TResolverParts);
begin
  inherited Create;
  FPlace := AParts.Place;
  FUnits := AParts.Units;
  FLookup := AParts.Lookup;
  FTyping := AParts.Typing;
  FMembers := AParts.Members;
  FLocals := AParts.Locals;
end;

function TResolverExpressions.ClassMember(const AName: string; out AResult: TResolvedSymbol): Boolean;
var
  mClasses: TArray<TResolvedSymbol>;
  mClass: TResolvedSymbol;
begin
  mClasses := FTyping.MethodClasses;
  if Length(mClasses) = 0 then
  begin
    Exit(False);
  end;
  if SameText(AName, 'Self') then
  begin
    AResult := mClasses[0];
    Exit(True);
  end;
  // Innerster Typ zuerst, dann die äußeren (verschachtelte Typen sehen deren Mitglieder).
  for mClass in mClasses do
  begin
    if FMembers.FindMember(mClass, AName, AResult) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TResolverExpressions.UnitPrefix(const ANames: TArray<string>; out AConsumed: Integer;
  out AResult: TResolvedSymbol): Boolean;
var
  mCount: Integer;
  mFound: TUnitIndex;
begin
  // Unit-Namen mit Punkten: längstes Präfix zuerst (System.SysUtils.Foo). Der
  // ganze Ausdruck zählt mit, sonst bleibt "Vcl.Werkzeug" in uses unaufgelöst.
  AConsumed := 1;
  for mCount := Length(ANames) downto 2 do
  begin
    if FUnits.FindQualifierUnit(string.Join('.', Copy(ANames, 0, mCount)), mFound) then
    begin
      AConsumed := mCount;
      AResult := TResolvedSymbol.OfUnit(mFound);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TResolverExpressions.GlobalName(const AName: string; out AResult: TResolvedSymbol): Boolean;
var
  mFound: TUnitIndex;
begin
  Result := FLookup.LookupGlobal(FPlace.Current, AName, FPlace.InImplementation, False, AResult);
  if not Result and FUnits.FindQualifierUnit(AName, mFound) then
  begin
    AResult := TResolvedSymbol.OfUnit(mFound);
    Result := True;
  end;
end;

function TResolverExpressions.ResolveFirst(const ANames: TArray<string>; out AConsumed: Integer;
  out AResult: TResolvedSymbol): Boolean;
begin
  AConsumed := 1;
  Result := FLocals.LookupLocal(ANames[0], AResult) or ClassMember(ANames[0], AResult) or
    UnitPrefix(ANames, AConsumed, AResult) or GlobalName(ANames[0], AResult);
end;

function TResolverExpressions.Overloads(const AName: string; AConsumed: Integer;
  const AFirst: TResolvedSymbol): TArray<TResolvedSymbol>;
var
  mClass: TResolvedSymbol;
begin
  // Überladungen: Mitglieder der eigenen Klasse oder freie Routinen derselben Unit.
  // Verschachtelte Routinen (#881): ihre Überladungen in der umgebenden Routine.
  Result := nil;
  if (AConsumed = 1) and (AFirst.Kind = TResolvedKind.Local) and (AFirst.SymbolKind = TIndexSymbolKind.Routine) then
  begin
    Result := FLocals.LocalOverloads(AFirst);
  end
  else if (AConsumed = 1) and (AFirst.Kind = TResolvedKind.Symbol) and (AFirst.SymbolKind in cRoutineKinds) then
  begin
    if (AFirst.Container <> '') and FTyping.CurrentClass(mClass) then
    begin
      Result := FMembers.FindMembers(mClass, AName);
    end;
    if Length(Result) = 0 then
    begin
      Result := FLocals.UnitRoutines(AFirst);
    end;
  end
  else
  begin
    Result := [AFirst];
  end;
end;

function TResolverExpressions.ResolveFirstAll(const ANames: TArray<string>; out AConsumed: Integer;
  out AResults: TArray<TResolvedSymbol>): Boolean;
var
  mFirst: TResolvedSymbol;
  mStop: Boolean;
begin
  AConsumed := 1;
  AResults := nil;
  if LookupWith(ANames[0], AResults, mStop) then
  begin
    Exit(True);
  end;
  if mStop or not ResolveFirst(ANames, AConsumed, mFirst) then
  begin
    Exit(False);
  end;
  AResults := Overloads(ANames[0], AConsumed, mFirst);
  Result := True;
end;

function TResolverExpressions.IdentifierCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
var
  mConsumed, mSavedOffset: Integer;
begin
  mSavedOffset := FPlace.Offset;
  FPlace.Offset := ANode.StartOffset;
  try
    if not ResolveFirstAll([ANode.Name], mConsumed, Result) then
    begin
      Result := nil;
    end;
  finally
    FPlace.Offset := mSavedOffset;
  end;
end;

function TResolverExpressions.UnitMemberCandidates(const AOwner: TResolvedSymbol;
  const AName: string): TArray<TResolvedSymbol>;
var
  mOwnerUnit: TUnitIndex;
  mSingle: TResolvedSymbol;
begin
  Result := nil;
  if FUnits.FindUnit(AOwner.UnitName, mOwnerUnit) and
    FLookup.LookupInUnit(mOwnerUnit, AName, not FPlace.IsCurrentFile(mOwnerUnit.FileName), False, mSingle) then
  begin
    Result := FLocals.UnitRoutines(mSingle);
  end;
end;

function TResolverExpressions.TypeMemberCandidates(const AOwner, AType: TResolvedSymbol;
  const AName: string): TArray<TResolvedSymbol>;
var
  mTarget: TResolvedSymbol;
begin
  // Wert einer Klassenreferenz (FError: ExceptClass): Mitglieder der Zielklasse, FError.Create ist
  // Exception.Create und liefert ein Exception. Die Referenz selbst hat im Index keine Vorfahren, ohne
  // diesen Schritt fände FindMembers nur TObject.Create.
  if not AOwner.IsType and FTyping.ClassRefTargetOf(AType, mTarget) then
  begin
    Result := FMembers.FindMembers(mTarget, AName);
    MarkConstructed(Result, mTarget);
    Exit;
  end;
  // P.X bei einem Zeiger auf einen Record (L3).
  Result := FMembers.FindMembers(FTyping.MemberHost(AType), AName);
  // TKunde.Create liefert TKunde, auch wenn Create aus TObject stammt.
  if AOwner.IsType then
  begin
    MarkConstructed(Result, AType);
  end;
end;

function TResolverExpressions.AccessCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
var
  mOwner, mType: TResolvedSymbol;
begin
  Result := nil;
  if not ExprSymbol(ANode[0], mOwner) then
  begin
    Exit;
  end;
  if mOwner.Kind = TResolvedKind.UnitName then
  begin
    Result := UnitMemberCandidates(mOwner, ANode.Name);
  end
  else if FTyping.TypeOf(mOwner, mType) then
  begin
    Result := TypeMemberCandidates(mOwner, mType, ANode.Name);
  end;
end;

function TResolverExpressions.ExprCandidates(ANode: TSyntaxNode): TArray<TResolvedSymbol>;
var
  mSingle: TResolvedSymbol;
begin
  Result := nil;
  if ANode.Kind = TSyntaxKind.Identifier then
  begin
    Result := IdentifierCandidates(ANode);
  end
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.FindChild(TSyntaxKind.GenericArgs) = nil) and
    (ANode.ChildCount > 0) then
  begin
    Result := AccessCandidates(ANode);
  end
  else if ExprSymbol(ANode, mSingle) then
  begin
    Result := [mSingle];
  end;
end;

function TResolverExpressions.FirstCandidate(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
begin
  mCandidates := ExprCandidates(ANode);
  Result := Length(mCandidates) > 0;
  if Result then
  begin
    AResult := mCandidates[0];
  end;
end;

function TResolverExpressions.GenericMemberSymbol(ANode, AArgs: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
  mArguments: TArray<string>;
  mIndex: Integer;
begin
  // Foo<Integer>: Typargumente an die Typparameter der Methode binden. Nur eine generische Überladung
  // passt; eine gleichnamige ohne Typparameter wäre falsch (TJSONObject.GetValue(Name): TJSONValue
  // neben TJSONValue.GetValue<T>). Ohne generischen Kandidaten bleibt der Ausdruck unbekannt.
  mCandidates := ExprCandidates(ANode[0]);
  mIndex := 0;
  while (mIndex <= High(mCandidates)) and (mCandidates[mIndex].TypeParams = '') do
  begin
    Inc(mIndex);
  end;
  if mIndex > High(mCandidates) then
  begin
    Exit(False);
  end;
  AResult := mCandidates[mIndex];
  mArguments := nil;
  for mIndex := 0 to AArgs.ChildCount - 1 do
  begin
    mArguments := mArguments + [FLookup.QualifyType(TIndexExtractor.TypeText(AArgs[mIndex]), FPlace.Current,
      FPlace.InImplementation)];
  end;
  AResult.Bindings := AResult.Bindings + TResolverText.Bind(AResult.TypeParams, mArguments);
  Result := True;
end;

function TResolverExpressions.MemberSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mArgs: TSyntaxNode;
begin
  mArgs := ANode.FindChild(TSyntaxKind.GenericArgs);
  if (mArgs <> nil) and (ANode.ChildCount > 0) and (ANode[0] <> mArgs) then
  begin
    Result := GenericMemberSymbol(ANode, mArgs, AResult);
  end
  else
  begin
    Result := FirstCandidate(ANode, AResult);
  end;
end;

function TResolverExpressions.CallSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mCandidates: TArray<TResolvedSymbol>;
  mResult: TResolvedSymbol;
begin
  Result := False;
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  mCandidates := ExprCandidates(ANode[0]);
  if Length(mCandidates) = 0 then
  begin
    Exit;
  end;
  // TFoo(X) ist eine Typumwandlung.
  if not mCandidates[0].IsType then
  begin
    mCandidates := SelectOverloads(mCandidates, ANode.ChildCount - 1, ArgTypes(ANode, 1));
  end;
  AResult := mCandidates[0];
  Result := True;
  if AResult.IsType then
  begin
    Exit;
  end;
  // Aufruf über eine Variable, ein Feld oder eine Property mit Prozedurtyp (L3): ihr Ergebnis.
  if not (AResult.SymbolKind in cRoutineKinds) and ProceduralResult(AResult, mResult) then
  begin
    AResult := TResolvedSymbol.ValueOf(mResult);
  end
  // Generische Routine ohne Typargumente (L3): Typparameter aus den Argumenten.
  else if (AResult.SymbolKind in cRoutineKinds) and (AResult.TypeParams <> '') then
  begin
    InferTypeArguments(ANode, AResult);
  end;
end;

function TResolverExpressions.ProceduralResult(const ACallee: TResolvedSymbol; out AResult: TResolvedSymbol): Boolean;
var
  mType: TResolvedSymbol;
begin
  Result := FTyping.ShapeOf(ACallee, mType) and SameText(mType.TargetForm, 'function') and
    FTyping.TargetOfType(mType, mType.TargetType, AResult);
end;

procedure TResolverExpressions.InferTypeArguments(ANode: TSyntaxNode; var ACallee: TResolvedSymbol);
var
  mParams: TArray<string>;
  mParam, mText, mArgText: string;
  mArg: Integer;
  mValue, mType, mElement: TResolvedSymbol;
begin
  mParams := TResolverText.SplitArgs(ACallee.TypeParams);
  for mArg := 0 to Min(Length(ACallee.ParamTypes), ANode.ChildCount - 1) - 1 do
  begin
    mText := Trim(ACallee.ParamTypes[mArg]);
    for mParam in mParams do
    begin
      if IsBound(Trim(mParam), ACallee.Bindings) then
      begin
        Continue;
      end;
      mArgText := '';
      // Foo<T>(const A: T), Foo<T>(const A: array of T) bzw. TArray<T>: einfache Fälle wie der Compiler.
      if SameText(mText, Trim(mParam)) then
      begin
        if OperandType(ANode[mArg + 1], mType) then
        begin
          mArgText := TypeArgumentText(mType);
        end;
      end
      else if SameText(mText, 'array of ' + Trim(mParam)) or SameText(mText, 'TArray<' + Trim(mParam) + '>') then
      begin
        if ExprSymbol(ANode[mArg + 1], mValue) and FTyping.ShapeOf(mValue, mType) and
          FTyping.ElementOf(mType, mElement) then
        begin
          mArgText := TypeArgumentText(mElement);
        end;
      end;
      if mArgText <> '' then
      begin
        ACallee.Bindings := ACallee.Bindings + [Trim(mParam) + '=' + mArgText];
      end;
    end;
  end;
end;

function TResolverExpressions.OperandType(ANode: TSyntaxNode; out AType: TResolvedSymbol): Boolean;
var
  mValue: TResolvedSymbol;
begin
  Result := ExprSymbol(ANode, mValue) and (mValue.Kind <> TResolvedKind.UnitName) and FTyping.TypeOf(mValue, AType);
end;

function TResolverExpressions.OperatorResult(const AType: TResolvedSymbol; const ANames: TArray<string>;
  out AResult: TResolvedSymbol): Boolean;
var
  mName: string;
  mMember: TResolvedSymbol;
begin
  // class operator Add(const A, B: TPunkt): TPunkt (L3): Ergebnistyp aus dem Index.
  Result := False;
  if AType.Builtin or not (AType.SymbolKind in [TIndexSymbolKind.RecordType, TIndexSymbolKind.ClassType]) then
  begin
    Exit;
  end;
  for mName in ANames do
  begin
    for mMember in FMembers.FindMembers(AType, mName) do
    begin
      if (IndexText('operator', mMember.Directives) >= 0) and FTyping.TypeOf(mMember, AResult) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

function TResolverExpressions.DerefSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mBase, mShape, mTarget: TResolvedSymbol;
begin
  // P^ (L3): der Zieltyp des Zeigers (PFoo = ^TFoo aus dem Index, @X, var P: ^TFoo).
  Result := (ANode.ChildCount > 0) and ExprSymbol(ANode[0], mBase) and FTyping.ShapeOf(mBase, mShape) and
    FTyping.Dereferenced(mShape, mTarget);
  if Result then
  begin
    AResult := TResolvedSymbol.ValueOf(mTarget);
  end;
end;

function TResolverExpressions.AddressSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mValue, mType: TResolvedSymbol;
begin
  // @R (L3): Zeiger auf den Typ von R; @Routine bleibt unbekannt (Methodenzeiger).
  Result := (ANode.ChildCount > 0) and ExprSymbol(ANode[0], mValue) and not mValue.IsType and
    (mValue.Kind <> TResolvedKind.UnitName) and not (mValue.SymbolKind in cRoutineKinds) and
    FTyping.TypeOf(mValue, mType);
  if Result then
  begin
    AResult := TResolvedSymbol.ValueOf(TResolvedSymbol.PointerTo(mType));
  end;
end;

function TResolverExpressions.UnarySymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mOperator: string;
  mType, mResult: TResolvedSymbol;
  mKnown: Boolean;
begin
  // not, -, + (L3): Typ des Operanden; not auf Unbekanntem ist meist ein Boolean.
  Result := ANode.ChildCount > 0;
  if not Result then
  begin
    Exit;
  end;
  mOperator := LowerCase(ANode.Name);
  mKnown := OperandType(ANode[0], mType);
  if mKnown and OperatorResult(mType, OperatorNames(mOperator, True), mResult) then
  begin
    AResult := TResolvedSymbol.ValueOf(mResult);
  end
  else if mOperator = 'not' then
  begin
    if mKnown and TResolverText.IsIntegerName(mType.Name) then
    begin
      AResult := TResolvedSymbol.ValueOf(mType);
    end
    else
    begin
      AResult := BuiltinValue('Boolean');
    end;
  end
  else
  begin
    Result := mKnown;
    if Result then
    begin
      AResult := TResolvedSymbol.ValueOf(mType);
    end;
  end;
end;

function TResolverExpressions.BinarySymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mOperator, mLeftName, mRightName: string;
  mLeft, mRight, mResult: TResolvedSymbol;
  mLeftKnown, mRightKnown, mText: Boolean;
begin
  // Operatoren nach den Regeln von Delphi (L3): Vergleiche Boolean, Text + Text string, Ganzzahlen Integer bzw.
  // Int64, / Gleitkomma, and/or/xor Boolean oder Ganzzahl; Operatoren von Records und Klassen zuerst.
  Result := False;
  if ANode.ChildCount <> 2 then
  begin
    Exit;
  end;
  mOperator := LowerCase(ANode.Name);
  mLeftKnown := OperandType(ANode[0], mLeft);
  mRightKnown := OperandType(ANode[1], mRight);
  if (mLeftKnown and OperatorResult(mLeft, OperatorNames(mOperator, False), mResult)) or
    (mRightKnown and OperatorResult(mRight, OperatorNames(mOperator, False), mResult)) then
  begin
    AResult := TResolvedSymbol.ValueOf(mResult);
    Exit(True);
  end;
  if MatchText(mOperator, ['=', '<>', '<', '>', '<=', '>=', 'in', 'not in', 'is', 'is not']) then
  begin
    AResult := BuiltinValue('Boolean');
    Exit(True);
  end;
  if not mLeftKnown and not mRightKnown then
  begin
    Exit;
  end;
  mLeftName := '';
  mRightName := '';
  if mLeftKnown and mLeft.Builtin then
  begin
    mLeftName := mLeft.Name;
  end;
  if mRightKnown and mRight.Builtin then
  begin
    mRightName := mRight.Name;
  end;
  mText := TResolverText.IsStringName(mLeftName) or TResolverText.IsStringName(mRightName) or
    TResolverText.IsCharName(mLeftName) or TResolverText.IsCharName(mRightName);
  // Mengen: A + B, A - B, A * B bleiben Mengen vom Typ des linken Operanden.
  if mLeftKnown and SameText(mLeft.TargetForm, 'set of') and MatchText(mOperator, ['+', '-', '*']) then
  begin
    AResult := TResolvedSymbol.ValueOf(mLeft);
    Result := True;
  end
  else if (mOperator = '+') and mText then
  begin
    AResult := BuiltinValue('string');
    Result := True;
  end
  else if MatchText(mOperator, ['and', 'or', 'xor']) and (SameText(mLeftName, 'Boolean') or
    SameText(mRightName, 'Boolean')) then
  begin
    AResult := BuiltinValue('Boolean');
    Result := True;
  end
  else if (mOperator = '/') and not mText then
  begin
    AResult := BuiltinValue('Extended');
    Result := True;
  end
  else if MatchText(mOperator, ['+', '-', '*']) and (TResolverText.IsFloatName(mLeftName) or
    TResolverText.IsFloatName(mRightName)) then
  begin
    AResult := BuiltinValue(FloatResult(mLeftName, mRightName));
    Result := True;
  end
  else if MatchText(mOperator, ['+', '-', '*', 'div', 'mod', 'shl', 'shr', 'and', 'or', 'xor']) and
    (TResolverText.IsIntegerName(mLeftName) or TResolverText.IsIntegerName(mRightName)) and
    (TResolverText.IsIntegerName(mLeftName) or not mLeftKnown) and
    (TResolverText.IsIntegerName(mRightName) or not mRightKnown) then
  begin
    AResult := BuiltinValue(IntegerResult(mLeftName, mRightName));
    Result := True;
  end;
end;

function TResolverExpressions.SetSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mElement: TSyntaxNode;
  mType: TResolvedSymbol;
begin
  // [A, B] bzw. [A..B] (L3): Menge vom Typ des ersten Elements.
  Result := False;
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  mElement := ANode[0];
  if (mElement.Kind = TSyntaxKind.RangeExpr) and (mElement.ChildCount > 0) then
  begin
    mElement := mElement[0];
  end;
  Result := OperandType(mElement, mType);
  if Result then
  begin
    AResult := TResolvedSymbol.ValueOf(TResolvedSymbol.SetOf(mType));
  end;
end;

function TResolverExpressions.ElementSymbolOf(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mValue, mType, mElement, mHost, mGetter, mEnumerator: TResolvedSymbol;
begin
  Result := ExprSymbol(ANode, mValue) and (mValue.Kind <> TResolvedKind.UnitName) and
    FTyping.ShapeOf(mValue, mType);
  if not Result then
  begin
    Exit;
  end;
  // for C in S: Zeichen; Arrays und Mengen: ihr Element.
  if mType.Builtin and TResolverText.IsStringName(mType.Name) then
  begin
    AResult := BuiltinValue('Char');
    Exit(True);
  end;
  if FTyping.ElementOf(mType, mElement) then
  begin
    AResult := TResolvedSymbol.ValueOf(mElement);
    Exit(True);
  end;
  // Sonst wie der Compiler: GetEnumerator, davon Current.
  mHost := FTyping.MemberHost(mType);
  Result := FMembers.FindMember(mHost, 'GetEnumerator', mGetter) and FTyping.TypeOf(mGetter, mEnumerator) and
    FMembers.FindMember(FTyping.MemberHost(mEnumerator), 'Current', AResult);
end;

function TResolverExpressions.ElementSymbol(const AType: TResolvedSymbol; out AResult: TResolvedSymbol): Boolean;
var
  mText: string;
  mFromUnit: TUnitIndex;
  mElement, mTarget: TResolvedSymbol;
begin
  // array of T, array[..] of T, TArray<T> (Eintrag target: aus dem Index, L3): das Element.
  if FTyping.ElementOf(AType, mElement) then
  begin
    AResult := TResolvedSymbol.ValueOf(mElement);
    Exit(True);
  end;
  // Zeiger: P[i] ist P^[i] bei einem Zeiger auf ein Array (PByteArray), sonst das Ziel (POINTERMATH).
  if FTyping.Dereferenced(AType, mTarget) then
  begin
    if not FTyping.ElementOf(mTarget, mElement) then
    begin
      mElement := mTarget;
    end;
    AResult := TResolvedSymbol.ValueOf(mElement);
    Exit(True);
  end;
  // TArray<T>[i] aus Ständen ohne Eintrag target:.
  Result := False;
  if SameText(AType.Name, 'TArray') and (Length(AType.Bindings) > 0) then
  begin
    mText := AType.Bindings[0];
    mText := Copy(mText, Pos('=', mText) + 1, MaxInt);
    Result := FUnits.UnitOf(AType, mFromUnit) and FLookup.ResolveTypeText(mText, mFromUnit, True, AResult);
  end;
end;

function TResolverExpressions.IndexSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
var
  mBase, mType: TResolvedSymbol;
begin
  if (ANode.ChildCount = 0) or not ExprSymbol(ANode[0], mBase) then
  begin
    Exit(False);
  end;
  // Liste.Items[i]: die indizierte Property selbst. Bei Lines[i][j] ist Base schon der Wert von Lines[i]
  // (ein string), nicht die Property (#1369, SynEdit).
  if (mBase.SymbolKind = TIndexSymbolKind.Property_) and (mBase.MaxArgs > 0) and
    (ANode[0].Kind <> TSyntaxKind.IndexAccess) then
  begin
    AResult := mBase;
    Exit(True);
  end;
  // Felder und Variablen mit anonymem Array-Typ (FListe: array of TFoo) über ihren eigenen Eintrag (L3).
  if not FTyping.ShapeOf(mBase, mType) then
  begin
    Exit(False);
  end;
  Result := FMembers.DefaultProperty(mType, AResult);
  if not Result and mType.Builtin and TResolverText.IsStringName(mType.Name) then
  begin
    AResult := TResolvedSymbol.BuiltinOf('Char');
    Result := True;
  end;
  Result := Result or ElementSymbol(mType, AResult);
end;

function TResolverExpressions.NodeSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
begin
  Result := False;
  case ANode.Kind of
    TSyntaxKind.Identifier:
      Result := FirstCandidate(ANode, AResult);
    TSyntaxKind.MemberAccess:
      Result := MemberSymbol(ANode, AResult);
    TSyntaxKind.Call:
      Result := CallSymbol(ANode, AResult);
    TSyntaxKind.IndexAccess:
      Result := IndexSymbol(ANode, AResult);
    TSyntaxKind.ParenExpr:
      Result := (ANode.ChildCount > 0) and ExprSymbol(ANode[0], AResult);
    TSyntaxKind.BinaryExpr:
      if SameText(ANode.Name, 'as') then
      begin
        // (X as TBar): der Zieltyp.
        Result := (ANode.ChildCount = 2) and ExprSymbol(ANode[1], AResult) and AResult.IsType;
      end
      else
      begin
        Result := BinarySymbol(ANode, AResult);
      end;
    TSyntaxKind.UnaryExpr:
      Result := UnarySymbol(ANode, AResult);
    TSyntaxKind.Dereference:
      Result := DerefSymbol(ANode, AResult);
    TSyntaxKind.AddressOf:
      Result := AddressSymbol(ANode, AResult);
    TSyntaxKind.SetConstructor:
      Result := SetSymbol(ANode, AResult);
    TSyntaxKind.AnonymousMethod:
      begin
        // var F := function(A: Integer): string begin … end (L3): Routine mit Ergebnistyp, F(1) ist ein string.
        AResult := FLocals.FromNode(ANode, 'function', TIndexSymbolKind.Routine, False);
        Result := True;
      end;
    TSyntaxKind.IfExpr:
      Result := (ANode.ChildCount >= 2) and ExprSymbol(ANode[1], AResult);
    TSyntaxKind.Literal:
      Result := LiteralSymbol(ANode, AResult);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function TResolverExpressions.ExprSymbol(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean;
begin
  Result := False;
  if (ANode = nil) or (FPlace.InferDepth > cMaxInferDepth * 4) then
  begin
    Exit;
  end;
  FPlace.InferDepth := FPlace.InferDepth + 1;
  try
    Result := NodeSymbol(ANode, AResult);
  finally
    FPlace.InferDepth := FPlace.InferDepth - 1;
  end;
end;

function TResolverExpressions.ArgTypes(ANode: TSyntaxNode; AFirst: Integer): TArray<string>;
var
  mIndex: Integer;
  mArg: TSyntaxNode;
  mValue, mType: TResolvedSymbol;
  mText: string;
begin
  Result := nil;
  for mIndex := AFirst to ANode.ChildCount - 1 do
  begin
    mArg := ANode[mIndex];
    if mArg.Kind = TSyntaxKind.GenericArgs then
    begin
      Continue;
    end;
    mText := '';
    if mArg.Kind = TSyntaxKind.SetConstructor then
    begin
      mText := '[]';
    end
    else if ExprSymbol(mArg, mValue) and FTyping.TypeOf(mValue, mType) then
    begin
      mText := mType.Name;
    end;
    Result := Result + [mText];
  end;
end;

function TResolverExpressions.DeclaredBase(const ACandidate: TResolvedSymbol; const AParam: string;
  out ABase: TResolvedSymbol): Boolean;
var
  mOwner: TUnitIndex;
  mDeclared: TResolvedSymbol;
begin
  Result := FUnits.UnitOf(ACandidate, mOwner) and FLookup.ResolveTypeText(AParam, mOwner, True, mDeclared) and
    FTyping.TypeOf(mDeclared, ABase) and not SameText(ABase.Name, AParam);
end;

function TResolverExpressions.ParamFits(const ACandidate: TResolvedSymbol; AArg: Integer; const AArgType: string;
  out ASame: Boolean): Boolean;
var
  mParam: string;
  mBase: TResolvedSymbol;
begin
  mParam := ACandidate.ParamTypes[AArg];
  Result := TResolverText.ArgumentFits(mParam, AArgType);
  ASame := Result and (AArgType <> '') and TResolverText.SameFamily(mParam, AArgType);
  if Result or TResolverText.IsBuiltinName(mParam) or not DeclaredBase(ACandidate, mParam, mBase) then
  begin
    Exit;
  end;
  Result := TResolverText.ArgumentFits(mBase.Name, AArgType);
  ASame := Result and TResolverText.SameFamily(mBase.Name, AArgType);
end;

function TResolverExpressions.CandidateScore(const ACandidate: TResolvedSymbol; AArgCount: Integer;
  const AArgTypes: TArray<string>): Integer;
var
  mArg: Integer;
  mSame: Boolean;
begin
  if (ACandidate.SymbolKind in cRoutineKinds) and
    ((AArgCount < ACandidate.MinArgs) or (AArgCount > ACandidate.MaxArgs)) then
  begin
    Exit(-1);
  end;
  Result := 0;
  for mArg := 0 to Min(Min(AArgCount, Length(ACandidate.ParamTypes)), Length(AArgTypes)) - 1 do
  begin
    if not ParamFits(ACandidate, mArg, AArgTypes[mArg], mSame) then
    begin
      Exit(-1);
    end;
    if mSame then
    begin
      Inc(Result);
    end;
  end;
end;

function TResolverExpressions.SelectOverloads(const ACandidates: TArray<TResolvedSymbol>; AArgCount: Integer;
  const AArgTypes: TArray<string>): TArray<TResolvedSymbol>;
var
  mCandidate: TResolvedSymbol;
  mFitting: TArray<TResolvedSymbol>;
  mScores: TArray<Integer>;
  mScore: Integer;
begin
  if (AArgCount < 0) or (Length(ACandidates) <= 1) then
  begin
    Exit(ACandidates);
  end;
  mFitting := nil;
  mScores := nil;
  for mCandidate in ACandidates do
  begin
    mScore := CandidateScore(mCandidate, AArgCount, AArgTypes);
    if mScore >= 0 then
    begin
      mFitting := mFitting + [mCandidate];
      mScores := mScores + [mScore];
    end;
  end;
  // Passt keine, lieber alle zeigen als eine falsche.
  if Length(mFitting) = 0 then
  begin
    Exit(ACandidates);
  end;
  Result := BestScored(mFitting, mScores);
end;

function TResolverExpressions.LookupWith(const AName: string; out AResults: TArray<TResolvedSymbol>;
  out AStop: Boolean): Boolean;
var
  mWith: TSyntaxNode;
  mElement: Integer;
begin
  Result := LookupWithOwner(AName, AResults, AStop, mWith, mElement);
end;

function TResolverExpressions.LookupWithOwner(const AName: string; out AResults: TArray<TResolvedSymbol>;
  out AStop: Boolean; out AWith: TSyntaxNode; out AElement: Integer): Boolean;
var
  mWith: TSyntaxNode;
  mIndex: Integer;
  mType: TResolvedSymbol;
begin
  Result := False;
  AStop := False;
  AResults := nil;
  AWith := nil;
  AElement := -1;
  for mWith in FPlace.EnclosingWiths do
  begin
    for mIndex := mWith.ChildCount - 2 downto 0 do
    begin
      // Unbekannter Typ: der Name könnte ein Mitglied sein, also lieber nichts liefern.
      AStop := not WithElementType(mWith, mIndex, mType);
      if AStop then
      begin
        Exit;
      end;
      AResults := FMembers.FindMembers(mType, AName);
      if Length(AResults) > 0 then
      begin
        AWith := mWith;
        AElement := mIndex;
        Exit(True);
      end;
    end;
  end;
end;

function TResolverExpressions.WithElementType(AWith: TSyntaxNode; AIndex: Integer;
  out AType: TResolvedSymbol): Boolean;
var
  mValue: TResolvedSymbol;
  mSavedOffset: Integer;
begin
  // Den Ausdruck an seiner eigenen Stelle auflösen, außerhalb des with-Rumpfs.
  mSavedOffset := FPlace.Offset;
  FPlace.Offset := AWith[AIndex].StartOffset;
  try
    Result := ExprSymbol(AWith[AIndex], mValue) and FTyping.TypeOf(mValue, AType);
  finally
    FPlace.Offset := mSavedOffset;
  end;
end;

end.
