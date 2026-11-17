unit dpcc.Common.Semantics.NameResolver.Typing;

// Typen der Namensauflösung: Typ eines aufgelösten Namens (Aliase verfolgt, Inline-Variablen aus ihrem
// Ausdruck), Vorfahren, Helfer, Klassenreferenzen, Sichtbarkeit von Mitgliedern und die Klasse der Methode an der
// Stelle.

interface

uses
  System.Generics.Collections,
  dpcc.Common.Index.Contract,
  dpcc.Common.Semantics.NameResolver.Symbols,
  dpcc.Common.Semantics.NameResolver.Place,
  dpcc.Common.Semantics.NameResolver.Units,
  dpcc.Common.Semantics.NameResolver.Lookup;

type
  TResolverTyping = class
  private
    FPlace: TResolverPlace;
    FUnits: TResolverUnits;
    FLookup: TResolverLookup;
    FInfer: TResolverInferFunc;
    FInferElement: TResolverInferFunc;
    // Je Baum: Helfer je Typname und aufgelöste Vorfahren je Typ (Diagnoselog 15.10.2026: Jeder Mitgliedszugriff
    // lief die ganze Vererbungskette neu durch). Gelten, solange FCacheEpoch dem Stand der Stelle entspricht.
    FHelpers: TDictionary<string, TResolvedSymbol>;
    FAncestors: TDictionary<string, TResolvedSymbol>;
    FCacheEpoch: Integer;
    // Klasse der umgebenden Methode, einmal je Ortswechsel (FClassMove): 0 = noch nicht ermittelt, 1 = keine,
    // 2 = FClass, 3 = wird gerade ermittelt.
    FClassState: Integer;
    FClass: TResolvedSymbol;
    FClassMove: Integer;
    /// <summary>Leert die baumbezogenen Zwischenspeicher, wenn die Stelle den Baum gewechselt hat.</summary>
    procedure SyncCaches;
    /// <summary>Typ, von dem TypeOf ausgeht, bevor Aliase verfolgt werden.</summary>
    function StartType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>TFoo.Create liefert ein TFoo.</summary>
    function ConstructedType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>Inline-Variable ohne Typangabe: Typ des Ausdrucks.</summary>
    function InferredType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>Deklarierter Typ samt Typargumenten, in der Unit der Deklaration aufgelöst.</summary>
    function DeclaredType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>Verfolgt Aliase von AStart bis zum Grundtyp.</summary>
    function FollowAliases(const AStart: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>Name des Typs der umgebenden Methode (TFoo in TFoo.Bar) bzw. der Property-Deklaration; ''
    /// sonst.</summary>
    function MethodTypeName: string;
    /// <summary>Verschachtelte Typen aus dem Kopf (TAussen.TInnen), innerster zuerst; nil, wenn der Pfad nicht
    /// aufgeht.</summary>
    function NestedMethodClasses(const ATypeName: string): TArray<TResolvedSymbol>;
    /// <summary>Reicht die Vorfahrenkette von AType ohne unbekannten Vorfahren bis TObject bzw. ans Ende?
    /// </summary>
    function ReachesRoot(const AType: TResolvedSymbol): Boolean;
    /// <summary>Verschachtelter Typ (L3): Typtext ATypeText eines Mitglieds AResolved, der im umgebenden Typ
    /// (oder dessen äußeren Typen und Vorfahren) deklariert ist, bzw. "TAussen&lt;X&gt;.TInnen". Bindungen bleiben
    /// erhalten.</summary>
    function NestedDeclaredType(const AResolved: TResolvedSymbol; const AFromUnit: TUnitIndex;
      const ATypeText: string; out AType: TResolvedSymbol): Boolean;
    /// <summary>Typ AName in AOuter oder dessen Vorfahren.</summary>
    function InheritedNestedType(const AOuter: TResolvedSymbol; const AName: string;
      out AResult: TResolvedSymbol): Boolean;
    /// <summary>Ist AName (Teil vor dem ersten Punkt eines Typtexts) eine Unit bzw. der Anfang eines Unit-Namens
    /// im Bereich von AFromUnit (System in System.Classes.TStrings)? Nur Namensvergleiche, ohne Nachschlagen.
    /// </summary>
    function IsUnitQualifier(const AName: string; const AFromUnit: TUnitIndex): Boolean;
    /// <summary>Typpfad "TAussen.TInnen" aus Typen dieser Unit bzw. ihrer uses.</summary>
    function TypePath(const APath: string; const AFromUnit: TUnitIndex; out AResult: TResolvedSymbol): Boolean;
  public
    constructor Create(APlace: TResolverPlace; AUnits: TResolverUnits; ALookup: TResolverLookup);
    destructor Destroy; override;
    /// <summary>Typ eines aufgelösten Namens, Aliase verfolgt (Typen sind ihr eigener Typ, TFoo.Create ein TFoo).
    /// </summary>
    function TypeOf(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
    /// <summary>Direkter Vorfahr eines Typs (ohne Angabe TObject bzw. IInterface); False ohne oder bei
    /// Helfern.</summary>
    function AncestorOf(const AType: TResolvedSymbol; out AAncestor: TResolvedSymbol): Boolean;
    /// <summary>Klasse, auf die die Klassenreferenz AType zeigt (class of …), aufgelöst in der Unit von AType.
    /// </summary>
    function ClassRefTargetOf(const AType: TResolvedSymbol; out ATarget: TResolvedSymbol): Boolean;
    /// <summary>Ist AType AAncestor oder stammt davon ab?</summary>
    function DescendsFrom(const AType, AAncestor: TResolvedSymbol): Boolean;
    /// <summary>Ist ASymbol (Mitglied von AOwner aus AOwnerUnit) an der Stelle sichtbar? ALocalChain: Ein Typ
    /// zwischen dem Empfänger und AOwner ist in der aktuellen Unit deklariert; dann sind protected-Mitglieder
    /// sichtbar wie in der Unit von AOwner (TKlasse(Control).Click, #1008).</summary>
    function IsVisible(const ASymbol: TIndexSymbol; const AOwnerUnit: TUnitIndex; const AOwner: TResolvedSymbol;
      ALocalChain: Boolean): Boolean;
    /// <summary>Klasse der umgebenden Methode, einmal je Ortswechsel ermittelt.</summary>
    function CurrentClass(out AType: TResolvedSymbol): Boolean;
    /// <summary>Zuletzt sichtbarer Helfer für AType an der Stelle: eigene Unit, dann uses von hinten.</summary>
    function HelperFor(const AType: TResolvedSymbol; out AHelper: TResolvedSymbol): Boolean;
    /// <summary>Vorfahr-Helfer eines Helfers (class helper (TBaseHelper) for T, #848); False ohne.</summary>
    function HelperParent(const AHelper: TResolvedSymbol; out AParent: TResolvedSymbol): Boolean;
    /// <summary>Im Typ AOuter selbst deklarierter Typ AName, ohne Sichtbarkeitsprüfung (Pfad im
    /// Methodenkopf).</summary>
    function NestedType(const AOuter: TResolvedSymbol; const AName: string; out AResult: TResolvedSymbol): Boolean;
    /// <summary>Innerster Typ aus MethodClasses.</summary>
    function MethodClass(out AType: TResolvedSymbol): Boolean;
    /// <summary>Typ der umgebenden Methode und bei verschachtelten Typen (TAussen.TInnen.Methode) die
    /// äußeren Typen, innerster zuerst; ihre Mitglieder sind dort ohne Präfix sichtbar. In einer
    /// Property-Deklaration deren Typ (#690).</summary>
    function MethodClasses: TArray<TResolvedSymbol>;
    /// <summary>Bricht die Vorfahrenkette der umgebenden Klasse an einem unbekannten Typ ab?</summary>
    function HasUnknownAncestor: Boolean;
    /// <summary>Namen ohne Unit von AClass und seinen Vorfahren, AClass zuerst (#483); bricht die Kette ab,
    /// zuletzt der Name des unbekannten Vorfahren. AComplete: Die Kette reicht ohne unbekannten Vorfahren bis zum
    /// Ende (#1326).</summary>
    function AncestorNames(const AClass: TResolvedSymbol; out AComplete: Boolean): TArray<string>;
    /// <summary>Zieltyp AText (aus einem Eintrag target: des Index bzw. eines Zeigertyps) von AOwner, aufgelöst in
    /// der Unit von AOwner, mit dessen Bindungen; eingebaute Typen auch ohne Unit (L3).</summary>
    function TargetOfType(const AOwner: TResolvedSymbol; const AText: string; out AType: TResolvedSymbol): Boolean;
    /// <summary>Zieltyp eines Zeigertyps (PFoo = ^TFoo, @X); False bei anderen Typen (L3).</summary>
    function Dereferenced(const AType: TResolvedSymbol; out ATarget: TResolvedSymbol): Boolean;
    /// <summary>Elementtyp eines Array-Typs (array of T, array[..] of T, TArray&lt;T&gt;) bzw. einer Menge (L3).
    /// </summary>
    function ElementOf(const AType: TResolvedSymbol; out AElement: TResolvedSymbol): Boolean;
    /// <summary>Typ, dessen Mitglieder hinter einem Punkt gelten: bei Zeigern auf Records und Klassen das Ziel
    /// (P.X statt P^.X, L3), sonst AType.</summary>
    function MemberHost(const AType: TResolvedSymbol): TResolvedSymbol;
    /// <summary>Typ von AValue wie TypeOf; bei Feldern und Variablen mit anonymem Typ (array of T, ^T) das Symbol
    /// selbst, dessen Eintrag target: den Aufbau beschreibt (L3).</summary>
    function ShapeOf(const AValue: TResolvedSymbol; out AShape: TResolvedSymbol): Boolean;
    /// <summary>Typ eines Ausdrucks für Inline-Variablen ohne Typangabe (TResolverExpressions.ExprSymbol).</summary>
    property Infer: TResolverInferFunc read FInfer write FInfer;
    /// <summary>Elementtyp eines Ausdrucks für for-in-Variablen ohne Typangabe (L3).</summary>
    property InferElement: TResolverInferFunc read FInferElement write FInferElement;
  end;

implementation

uses
  dpcc.Common.Pascal.SyntaxTree,
  System.SysUtils,
  System.StrUtils,
  dpcc.Common.Diagnostics.RequestScope;

/// <summary>Teilt "TAussen&lt;X&gt;.TInnen" am letzten Punkt außerhalb spitzer Klammern; False ohne Punkt.
/// </summary>
function SplitLastDot(const AText: string; out AHead, ATail: string): Boolean;
var
  mIndex, mDepth: Integer;
begin
  mDepth := 0;
  for mIndex := Length(AText) downto 1 do
  begin
    if AText[mIndex] = '>' then
    begin
      Inc(mDepth);
    end
    else if AText[mIndex] = '<' then
    begin
      Dec(mDepth);
    end
    else if (AText[mIndex] = '.') and (mDepth = 0) then
    begin
      AHead := Copy(AText, 1, mIndex - 1);
      ATail := Copy(AText, mIndex + 1, MaxInt);
      Exit((AHead <> '') and (ATail <> ''));
    end;
  end;
  Result := False;
end;

constructor TResolverTyping.Create(APlace: TResolverPlace; AUnits: TResolverUnits; ALookup: TResolverLookup);
begin
  inherited Create;
  FPlace := APlace;
  FUnits := AUnits;
  FLookup := ALookup;
  FHelpers := TDictionary<string, TResolvedSymbol>.Create;
  FAncestors := TDictionary<string, TResolvedSymbol>.Create;
  FCacheEpoch := APlace.CacheEpoch;
  FClassMove := APlace.MoveCount;
end;

destructor TResolverTyping.Destroy;
begin
  FAncestors.Free;
  FHelpers.Free;
  inherited;
end;

procedure TResolverTyping.SyncCaches;
begin
  if FCacheEpoch <> FPlace.CacheEpoch then
  begin
    FHelpers.Clear;
    FAncestors.Clear;
    FCacheEpoch := FPlace.CacheEpoch;
  end;
end;

function TResolverTyping.TypeOf(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  mStart: TResolvedSymbol;
begin
  Result := not AResolved.IsTypeParameter and StartType(AResolved, mStart) and FollowAliases(mStart, AType);
end;

function TResolverTyping.StartType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
begin
  // Typen sind ihr eigener Typ; Aliase werden danach verfolgt.
  Result := True;
  if AResolved.IsType then
  begin
    AType := AResolved;
  end
  else if Length(AResolved.Constructed) > 0 then
  begin
    AType := AResolved.Constructed[0];
  end
  else if (AResolved.SymbolKind = TIndexSymbolKind.Constructor_) and (AResolved.Container <> '') then
  begin
    Result := ConstructedType(AResolved, AType);
  end
  else if AResolved.TypeName = '' then
  begin
    Result := InferredType(AResolved, AType);
  end
  else
  begin
    Result := DeclaredType(AResolved, AType);
  end;
end;

function TResolverTyping.ConstructedType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  mFromUnit: TUnitIndex;
begin
  Result := FUnits.UnitOf(AResolved, mFromUnit) and FLookup.ResolveTypeName(AResolved.Container, mFromUnit,
    FPlace.IsCurrentFile(mFromUnit.FileName), AType);
  if Result then
  begin
    AType.Bindings := AResolved.Bindings;
  end;
end;

function TResolverTyping.InferredType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  mValue: TResolvedSymbol;
  mSavedOffset: Integer;
begin
  if (AResolved.Initializer = nil) or (FPlace.InferDepth >= cMaxInferDepth) or (FPlace.Tree = nil) or
    not Assigned(FInfer) or (AResolved.ElementOfInitializer and not Assigned(FInferElement)) then
  begin
    Exit(False);
  end;
  mSavedOffset := FPlace.Offset;
  FPlace.InferDepth := FPlace.InferDepth + 1;
  try
    FPlace.Offset := AResolved.Initializer.StartOffset;
    // for var X in Liste (L3): Elementtyp der Liste.
    if AResolved.ElementOfInitializer then
    begin
      Result := FInferElement(AResolved.Initializer, mValue) and TypeOf(mValue, AType);
    end
    else
    begin
      Result := FInfer(AResolved.Initializer, mValue) and TypeOf(mValue, AType);
    end;
  finally
    FPlace.InferDepth := FPlace.InferDepth - 1;
    FPlace.Offset := mSavedOffset;
  end;
end;

function TResolverTyping.DeclaredType(const AResolved: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  mFromUnit: TUnitIndex;
  mWithImplementation: Boolean;
  mText: string;
begin
  Result := FUnits.UnitOf(AResolved, mFromUnit);
  if Result then
  begin
    mWithImplementation := (AResolved.Kind = TResolvedKind.Local) or
      (FPlace.IsCurrentFile(mFromUnit.FileName) and FPlace.InImplementation);
    mText := TResolverText.Substitute(TResolverText.FullType(AResolved.TypeName, AResolved.TypeArgs),
      AResolved.Bindings);
    // Verschachtelte Typen zuerst (L3): "TAussen.TInnen" sonst als Unit TAussen gesucht, mit Nachladen.
    if (Pos('.', mText) > 0) and NestedDeclaredType(AResolved, mFromUnit, mText, AType) then
    begin
      Exit(True);
    end;
    Result := FLookup.ResolveTypeText(mText, mFromUnit, mWithImplementation, AType) or
      ((AResolved.Container <> '') and (Pos('.', mText) = 0) and
      NestedDeclaredType(AResolved, mFromUnit, mText, AType));
  end;
end;

function TResolverTyping.IsUnitQualifier(const AName: string; const AFromUnit: TUnitIndex): Boolean;
var
  mUnitName: string;
begin
  if SameText(AName, AFromUnit.UnitName) or StartsText(AName + '.', AFromUnit.UnitName) then
  begin
    Exit(True);
  end;
  for mUnitName in FUnits.ScopeUnits(AFromUnit, True) do
  begin
    if SameText(AName, mUnitName) or StartsText(AName + '.', mUnitName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TResolverTyping.TypePath(const APath: string; const AFromUnit: TUnitIndex;
  out AResult: TResolvedSymbol): Boolean;
var
  mParts: TArray<string>;
  mIndex: Integer;
  mInner: TResolvedSymbol;
begin
  mParts := APath.Split(['.']);
  Result := (Length(mParts) > 0) and FLookup.ResolveTypeName(mParts[0], AFromUnit,
    FPlace.IsCurrentFile(AFromUnit.FileName), AResult);
  mIndex := 1;
  while Result and (mIndex <= High(mParts)) do
  begin
    Result := NestedType(AResult, mParts[mIndex], mInner);
    AResult := mInner;
    Inc(mIndex);
  end;
end;

function TResolverTyping.InheritedNestedType(const AOuter: TResolvedSymbol; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mCurrent, mAncestor: TResolvedSymbol;
  mDepth: Integer;
begin
  mCurrent := AOuter;
  for mDepth := 0 to cMaxDepth do
  begin
    if NestedType(mCurrent, AName, AResult) then
    begin
      Exit(True);
    end;
    if not AncestorOf(mCurrent, mAncestor) then
    begin
      Break;
    end;
    mCurrent := mAncestor;
  end;
  Result := False;
end;

function TResolverTyping.NestedDeclaredType(const AResolved: TResolvedSymbol; const AFromUnit: TUnitIndex;
  const ATypeText: string; out AType: TResolvedSymbol): Boolean;
var
  mHead, mTail, mContainer, mFirst: string;
  mOuter, mInner: TResolvedSymbol;
  mDot: Integer;
begin
  Result := False;
  if SplitLastDot(ATypeText, mHead, mTail) then
  begin
    // TListe<TKunde>.TAufzaehler: Kopf samt Typargumenten, dann der Typ darin. Nur wenn der erste Teil ein Typ
    // ist; sonst ist er ein Unit-Präfix (System.Classes.TList) und gehört zum normalen Weg, ohne Nachladen hier.
    mFirst := ATypeText;
    mDot := Pos('.', mFirst);
    if (Pos('<', mFirst) > 0) and (Pos('<', mFirst) < mDot) then
    begin
      mDot := Pos('<', mFirst);
    end;
    mFirst := Copy(mFirst, 1, mDot - 1);
    if (Pos('<', mTail) > 0) or IsUnitQualifier(mFirst, AFromUnit) or not FLookup.ResolveTypeName(mFirst,
      AFromUnit, FPlace.IsCurrentFile(AFromUnit.FileName), mOuter) then
    begin
      Exit;
    end;
    if Pos('.', mHead) > 0 then
    begin
      Result := NestedDeclaredType(AResolved, AFromUnit, mHead, mOuter);
    end
    else
    begin
      Result := FLookup.ResolveTypeText(mHead, AFromUnit, FPlace.IsCurrentFile(AFromUnit.FileName), mOuter);
    end;
    if not Result or mOuter.Builtin or not InheritedNestedType(mOuter, mTail, mInner) then
    begin
      Exit(False);
    end;
    AType := mInner;
    AType.Bindings := mOuter.Bindings;
    Exit(True);
  end;
  if (Pos('<', ATypeText) > 0) or (AResolved.Container = '') then
  begin
    Exit;
  end;
  // Typ eines Mitglieds: im umgebenden Typ, dann in den äußeren (TAussen.TInnen.Feld sieht TAussen.X).
  mContainer := AResolved.Container;
  while mContainer <> '' do
  begin
    if TypePath(mContainer, AFromUnit, mOuter) and InheritedNestedType(mOuter, ATypeText, mInner) then
    begin
      AType := mInner;
      // Typparameter des umgebenden Typs gelten im verschachtelten (TListe<T>.TAufzaehler.Current: T).
      AType.Bindings := AResolved.Bindings;
      Exit(True);
    end;
    mDot := LastDelimiter('.', mContainer);
    mContainer := Copy(mContainer, 1, mDot - 1);
  end;
end;

function TResolverTyping.TargetOfType(const AOwner: TResolvedSymbol; const AText: string;
  out AType: TResolvedSymbol): Boolean;
var
  mText: string;
  mUnit: TUnitIndex;
  mFound: TResolvedSymbol;
begin
  mText := TResolverText.Substitute(AText, AOwner.Bindings);
  Result := False;
  if mText = '' then
  begin
    Exit;
  end;
  if not AOwner.Builtin and FUnits.UnitOf(AOwner, mUnit) then
  begin
    Result := FLookup.ResolveTypeText(mText, mUnit, (AOwner.Kind = TResolvedKind.Local) or
      FPlace.IsCurrentFile(mUnit.FileName), mFound) and FollowAliases(mFound, AType);
  end;
  if not Result and TResolverText.IsBuiltinName(mText) then
  begin
    AType := TResolvedSymbol.BuiltinOf(mText);
    Result := True;
  end;
end;

function TResolverTyping.Dereferenced(const AType: TResolvedSymbol; out ATarget: TResolvedSymbol): Boolean;
begin
  Result := False;
  if AType.TargetForm <> '^' then
  begin
    Exit;
  end;
  if Length(AType.Constructed) > 0 then
  begin
    Result := FollowAliases(AType.Constructed[0], ATarget);
  end
  else
  begin
    Result := TargetOfType(AType, AType.TargetType, ATarget);
  end;
end;

function TResolverTyping.ElementOf(const AType: TResolvedSymbol; out AElement: TResolvedSymbol): Boolean;
var
  mForm: string;
begin
  mForm := AType.TargetForm;
  Result := StartsText('array', mForm) or SameText(mForm, 'set of');
  if Result and (Length(AType.Constructed) > 0) then
  begin
    // Menge ohne Deklaration ([A, B], TResolvedSymbol.SetOf): das Element selbst.
    Result := FollowAliases(AType.Constructed[0], AElement);
  end
  else if Result then
  begin
    Result := TargetOfType(AType, AType.TargetType, AElement);
  end;
end;

function TResolverTyping.MemberHost(const AType: TResolvedSymbol): TResolvedSymbol;
begin
  if not Dereferenced(AType, Result) or Result.Builtin then
  begin
    Result := AType;
  end;
end;

function TResolverTyping.ShapeOf(const AValue: TResolvedSymbol; out AShape: TResolvedSymbol): Boolean;
begin
  Result := TypeOf(AValue, AShape);
  if not Result and not AValue.IsType and (AValue.TypeName = '') and (AValue.TargetForm <> '') then
  begin
    AShape := AValue;
    Result := True;
  end;
end;

function TResolverTyping.FollowAliases(const AStart: TResolvedSymbol; out AType: TResolvedSymbol): Boolean;
var
  mCurrent, mNext: TResolvedSymbol;
  mFromUnit: TUnitIndex;
  mDepth: Integer;
begin
  mCurrent := AStart;
  mDepth := 0;
  while not mCurrent.Builtin and (mCurrent.SymbolKind = TIndexSymbolKind.TypeAlias) and (mCurrent.TypeName <> '') and
    (mDepth < cMaxDepth) do
  begin
    // Eigene Variable: der out-Parameter würde mCurrent.TypeName vor dem Aufruf leeren.
    if not FUnits.UnitOf(mCurrent, mFromUnit) or
      not FLookup.ResolveTypeText(TResolverText.Substitute(TResolverText.FullType(mCurrent.TypeName,
        mCurrent.TypeArgs), mCurrent.Bindings), mFromUnit, FPlace.IsCurrentFile(mFromUnit.FileName), mNext) then
    begin
      Exit(False);
    end;
    mCurrent := mNext;
    Inc(mDepth);
  end;
  AType := mCurrent;
  Result := True;
end;

function TResolverTyping.AncestorOf(const AType: TResolvedSymbol; out AAncestor: TResolvedSymbol): Boolean;
var
  mFromUnit: TUnitIndex;
  mAlias: TResolvedSymbol;
  mName, mKey: string;
  mWithImplementation: Boolean;
begin
  Result := False;
  // Helfer: der "Vorfahr" ist der erweiterte Typ, nicht der Elterntyp.
  if AType.Builtin or not FUnits.UnitOf(AType, mFromUnit) or (AType.SymbolKind = TIndexSymbolKind.HelperType) then
  begin
    Exit;
  end;
  if Length(AType.Ancestors) > 0 then
  begin
    mName := TResolverText.Substitute(AType.AncestorText(0), AType.Bindings);
  end
  else if (AType.SymbolKind = TIndexSymbolKind.ClassType) and not SameText(AType.Name, 'TObject') then
  begin
    mName := 'TObject';
  end
  else if (AType.SymbolKind = TIndexSymbolKind.InterfaceType) and not SameText(AType.Name, 'IInterface') then
  begin
    mName := 'IInterface';
  end
  else
  begin
    Exit;
  end;
  SyncCaches;
  // Die Sichtbarkeit des implementation-Teils gehört zum Schlüssel: Der Cache überdauert ResolveTypeFrom
  //, dort ist Current eine andere Unit.
  mWithImplementation := FPlace.IsCurrentFile(mFromUnit.FileName);
  mKey := UpperCase(mFromUnit.FileName + '|' + AType.QualifiedName + '|' + mName) + '|' +
    BoolToStr(mWithImplementation, True);
  if FAncestors.TryGetValue(mKey, AAncestor) then
  begin
    Exit(AAncestor.Found);
  end;
  Result := FLookup.ResolveTypeText(mName, mFromUnit, mWithImplementation, AAncestor) and
    not AAncestor.Builtin and not SameText(AAncestor.QualifiedName, AType.QualifiedName);
  // class(TAlias) mit TAlias = TEcht: Vorfahr ist TEcht, der Alias selbst hat keine Member.
  if Result and (AAncestor.SymbolKind = TIndexSymbolKind.TypeAlias) then
  begin
    mAlias := AAncestor;
    Result := FollowAliases(mAlias, AAncestor) and not AAncestor.Builtin and
      not SameText(AAncestor.QualifiedName, AType.QualifiedName);
  end;
  if not Result then
  begin
    AAncestor := TResolvedSymbol.Empty;
  end;
  FAncestors.AddOrSetValue(mKey, AAncestor);
end;

function TResolverTyping.ClassRefTargetOf(const AType: TResolvedSymbol; out ATarget: TResolvedSymbol): Boolean;
var
  mName: string;
  mUnit: TUnitIndex;
begin
  Result := False;
  ATarget := TResolvedSymbol.Empty;
  if AType.Builtin or (AType.SymbolKind <> TIndexSymbolKind.ClassType) or (Length(AType.Ancestors) > 0) then
  begin
    Exit;
  end;
  // Zieltyp aus dem Index (L1, "target:class of=TFoo"); ältere Stände ohne Eintrag aus der Signatur.
  if SameText(AType.TargetForm, 'class of') then
  begin
    mName := AType.TargetType;
  end
  else
  begin
    mName := TResolverText.ClassRefTarget(AType.Signature);
  end;
  if (mName = '') or not FUnits.UnitOf(AType, mUnit) then
  begin
    Exit;
  end;
  Result := FLookup.ResolveTypeText(mName, mUnit, FPlace.IsCurrentFile(mUnit.FileName), ATarget) and
    not ATarget.Builtin and (ATarget.SymbolKind = TIndexSymbolKind.ClassType) and
    not SameText(ATarget.QualifiedName, AType.QualifiedName);
  if not Result then
  begin
    ATarget := TResolvedSymbol.Empty;
  end;
end;

function TResolverTyping.DescendsFrom(const AType, AAncestor: TResolvedSymbol): Boolean;
var
  mCurrent, mNext: TResolvedSymbol;
  mDepth: Integer;
begin
  mCurrent := AType;
  for mDepth := 0 to cMaxDepth do
  begin
    if SameText(mCurrent.QualifiedName, AAncestor.QualifiedName) and
      SameText(mCurrent.UnitName, AAncestor.UnitName) then
    begin
      Exit(True);
    end;
    if not AncestorOf(mCurrent, mNext) then
    begin
      Exit(False);
    end;
    mCurrent := mNext;
  end;
  Result := False;
end;

function TResolverTyping.IsVisible(const ASymbol: TIndexSymbol; const AOwnerUnit: TUnitIndex;
  const AOwner: TResolvedSymbol; ALocalChain: Boolean): Boolean;
var
  mSameUnit: Boolean;
  mOwn: TResolvedSymbol;
begin
  mSameUnit := FPlace.IsCurrentFile(AOwnerUnit.FileName);
  // Aus anderen Units sind nur Deklarationen im interface sichtbar, keine Rümpfe.
  if not mSameUnit and not ASymbol.InInterface then
  begin
    Exit(False);
  end;
  case ASymbol.Visibility of
    TIndexVisibility.Private:
      Result := mSameUnit;
    TIndexVisibility.StrictPrivate:
      Result := mSameUnit and CurrentClass(mOwn) and SameText(mOwn.QualifiedName, AOwner.QualifiedName);
    TIndexVisibility.Protected:
      Result := mSameUnit or ALocalChain or (CurrentClass(mOwn) and DescendsFrom(mOwn, AOwner));
    TIndexVisibility.StrictProtected:
      Result := CurrentClass(mOwn) and DescendsFrom(mOwn, AOwner);
  else
    Result := True;
  end;
end;

function TResolverTyping.CurrentClass(out AType: TResolvedSymbol): Boolean;
begin
  // Einmal je Ortswechsel: Klasse der umgebenden Methode.
  if FClassMove <> FPlace.MoveCount then
  begin
    FClassMove := FPlace.MoveCount;
    FClassState := 0;
  end;
  if FClassState = 3 then
  begin
    // Sicherheitsnetz, zusätzlich zur Ursachenbehebung in MethodClasses: Führt das Ermitteln
    // der Klasse wieder hierher, gilt „keine Klasse“ statt einer Rekursion bis zum Stapelüberlauf. Im
    // Diagnoselog als „resolve classRecursion“ sichtbar, damit ein neuer Weg dorthin auffällt.
    TRequestDiagnostics.ResolveFailed('classRecursion');
    AType := TResolvedSymbol.Empty;
    Exit(False);
  end;
  if FClassState = 0 then
  begin
    FClassState := 3;
    try
      if (FPlace.Tree <> nil) and MethodClass(FClass) then
      begin
        FClassState := 2;
      end
      else
      begin
        FClassState := 1;
      end;
    except
      // Abbruch der Anfrage: beim nächsten Aufruf neu ermitteln, nicht als Rekursion werten.
      FClassState := 0;
      raise;
    end;
  end;
  AType := FClass;
  Result := FClassState = 2;
end;

function TResolverTyping.HelperFor(const AType: TResolvedSymbol; out AHelper: TResolvedSymbol): Boolean;
var
  mKey, mUnitName: string;
  mUnits: TList<TUnitIndex>;
  mUsed: TUnitIndex;
  mPosition: Integer;
  mFound: Boolean;
  mCandidate: TResolvedSymbol;
begin
  SyncCaches;
  // Welche Helfer sichtbar sind, hängt an der Unit und am Abschnitt (uses von interface bzw.
  // implementation); der Cache überdauert ResolveTypeFrom und Abschnittswechsel.
  mKey := UpperCase(AType.UnitName + '.' + AType.QualifiedName + '|' + FPlace.Current.FileName + '|' +
    FPlace.Current.UnitName) + '|' + BoolToStr(FPlace.InImplementation, True);
  if FHelpers.TryGetValue(mKey, AHelper) then
  begin
    Exit(AHelper.Found);
  end;
  AHelper := TResolvedSymbol.Empty;
  // Nur der zuletzt sichtbare Helfer wirkt: eigene Unit, dann uses von hinten; in einer Unit der letzte.
  mUnits := TList<TUnitIndex>.Create;
  try
    mUnits.Add(FPlace.Current);
    for mUnitName in FUnits.ScopeUnits(FPlace.Current, FPlace.InImplementation) do
    begin
      if FUnits.FindUnit(mUnitName, mUsed) then
      begin
        mUnits.Add(mUsed);
      end;
    end;
    for mUsed in mUnits do
    begin
      mFound := False;
      // Nur die vorab ermittelten Helfer-Typen der Unit prüfen statt aller Symbole.
      for mPosition in FUnits.HelperPositions(mUsed) do
      begin
        if TResolverText.HelperTargets(mUsed.Symbols[mPosition].Ancestors[High(mUsed.Symbols[mPosition].Ancestors)],
          AType) and (mUsed.Symbols[mPosition].InInterface or FPlace.IsCurrentFile(mUsed.FileName)) then
        begin
          mCandidate := TResolvedSymbol.FromIndex(mUsed, mUsed.Symbols[mPosition]);
          mFound := True;
        end;
      end;
      if mFound then
      begin
        AHelper := mCandidate;
        Break;
      end;
    end;
  finally
    mUnits.Free;
  end;
  FHelpers.AddOrSetValue(mKey, AHelper);
  Result := AHelper.Found;
end;

function TResolverTyping.HelperParent(const AHelper: TResolvedSymbol; out AParent: TResolvedSymbol): Boolean;
var
  mFromUnit: TUnitIndex;
begin
  AParent := TResolvedSymbol.Empty;
  if (AHelper.SymbolKind <> TIndexSymbolKind.HelperType) or (Length(AHelper.Ancestors) < 2) or
    not FUnits.UnitOf(AHelper, mFromUnit) then
  begin
    Exit(False);
  end;
  Result := FLookup.ResolveTypeText(AHelper.Ancestors[0], mFromUnit, FPlace.IsCurrentFile(mFromUnit.FileName),
    AParent) and (AParent.SymbolKind = TIndexSymbolKind.HelperType) and
    not SameText(AParent.QualifiedName, AHelper.QualifiedName);
  if not Result then
  begin
    AParent := TResolvedSymbol.Empty;
  end;
end;

function TResolverTyping.NestedType(const AOuter: TResolvedSymbol; const AName: string;
  out AResult: TResolvedSymbol): Boolean;
var
  mOwnerUnit: TUnitIndex;
  mPosition: Integer;
begin
  Result := False;
  if AOuter.Builtin or not FUnits.UnitOf(AOuter, mOwnerUnit) then
  begin
    Exit;
  end;
  for mPosition in mOwnerUnit.SymbolsNamed(AName) do
  begin
    if (mOwnerUnit.Symbols[mPosition].Kind in cTypeKinds) and
      SameText(mOwnerUnit.Symbols[mPosition].Container, AOuter.QualifiedName) then
    begin
      AResult := TResolvedSymbol.FromIndex(mOwnerUnit, mOwnerUnit.Symbols[mPosition]);
      AResult.Bindings := AOuter.Bindings;
      Exit(True);
    end;
  end;
end;

function TResolverTyping.MethodClass(out AType: TResolvedSymbol): Boolean;
var
  mClasses: TArray<TResolvedSymbol>;
begin
  mClasses := MethodClasses;
  Result := Length(mClasses) > 0;
  if Result then
  begin
    AType := mClasses[0];
  end;
end;

function TResolverTyping.MethodTypeName: string;
var
  mRoutines: TArray<TSyntaxNode>;
  mName: string;
  mDot: Integer;
begin
  Result := '';
  if FPlace.Tree = nil then
  begin
    Exit;
  end;
  // Äußerste Routine mit Punkt im Namen: procedure TFoo.Bar
  mRoutines := FPlace.EnclosingRoutines;
  if Length(mRoutines) = 0 then
  begin
    // Zugriffe einer Property (read FName write SetName, #690) stehen im Bereich ihres Typs: Ohne das blieben
    // sie unaufgelöst, und Referenzsuche, Umbenennen und Datenfluss übersahen sie.
    Exit(FPlace.PropertyClassName);
  end;
  mName := mRoutines[High(mRoutines)].Name;
  mDot := LastDelimiter('.', mName);
  if mDot > 0 then
  begin
    Result := Copy(mName, 1, mDot - 1);
  end;
end;

function TResolverTyping.NestedMethodClasses(const ATypeName: string): TArray<TResolvedSymbol>;
var
  mParts: TArray<string>;
  mIndex: Integer;
  mCurrent, mInner: TResolvedSymbol;
begin
  Result := nil;
  mParts := ATypeName.Split(['.']);
  if (Length(mParts) <= 1) or not FLookup.ResolveTypeName(mParts[0], FPlace.Current, True, mCurrent) then
  begin
    Exit;
  end;
  Result := [mCurrent];
  for mIndex := 1 to High(mParts) do
  begin
    // Der Pfad im Kopf benennt den deklarierenden Typ, unabhängig von seiner Sichtbarkeit (strict private
    // verschachtelte Typen werden genauso implementiert). FindMember prüfte die Sichtbarkeit über
    // CurrentClass, das hierher zurückführte.
    if not NestedType(mCurrent, mParts[mIndex], mInner) then
    begin
      Exit(nil);
    end;
    mCurrent := mInner;
    Result := [mCurrent] + Result;
  end;
end;

function TResolverTyping.MethodClasses: TArray<TResolvedSymbol>;
var
  mTypeName: string;
  mCurrent: TResolvedSymbol;
begin
  Result := nil;
  mTypeName := MethodTypeName;
  if mTypeName = '' then
  begin
    Exit;
  end;
  // Verschachtelte Typen zuerst (procedure TAussen.TInnen.Methode): TAussen.TInnen sonst als Unit
  // TAussen gesucht, mit Nachladen über alle Suchpfade, und die Felder blieben unaufgelöst (#647).
  Result := NestedMethodClasses(mTypeName);
  if (Result = nil) and FLookup.ResolveTypeName(mTypeName, FPlace.Current, True, mCurrent) then
  begin
    Result := [mCurrent];
  end;
end;

function TResolverTyping.ReachesRoot(const AType: TResolvedSymbol): Boolean;
var
  mNext, mAncestor: TResolvedSymbol;
  mDepth: Integer;
begin
  mNext := AType;
  for mDepth := 0 to cMaxDepth do
  begin
    if (Length(mNext.Ancestors) = 0) or TResolverText.IsObjectRoot(mNext.Ancestors[0]) then
    begin
      Break;
    end;
    if not AncestorOf(mNext, mAncestor) then
    begin
      Exit(False);
    end;
    mNext := mAncestor;
  end;
  Result := True;
end;

function TResolverTyping.HasUnknownAncestor: Boolean;
var
  mClass: TResolvedSymbol;
begin
  for mClass in MethodClasses do
  begin
    if not ReachesRoot(mClass) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TResolverTyping.AncestorNames(const AClass: TResolvedSymbol; out AComplete: Boolean): TArray<string>;
var
  mCurrent, mNext: TResolvedSymbol;
  mDepth: Integer;
begin
  Result := nil;
  AComplete := False;
  if not AClass.Found then
  begin
    Exit;
  end;
  mCurrent := AClass;
  for mDepth := 0 to cMaxDepth do
  begin
    Result := Result + [mCurrent.Name];
    if Length(mCurrent.Ancestors) = 0 then
    begin
      AComplete := True;
      Exit;
    end;
    if not AncestorOf(mCurrent, mNext) then
    begin
      Result := Result + [TResolverText.LastPart(mCurrent.Ancestors[0])];
      Exit;
    end;
    mCurrent := mNext;
  end;
end;

end.
