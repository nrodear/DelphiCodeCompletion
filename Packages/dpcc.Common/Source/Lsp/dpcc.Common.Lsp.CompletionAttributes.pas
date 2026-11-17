unit dpcc.Common.Lsp.CompletionAttributes;

// Attribute nach "[" (#465, ARG-066): Steht der Cursor auf dem Namen in einer Attributklammer vor einer
// Deklaration (TAttributes.InBracket), bleiben nur Attributklassen (Nachfahren von TCustomAttribute,
// TNameResolver.Queries.AttributeClassOf), gezeigt ohne die Endung Attribute.
// - Bekannte Attribute zuerst, in dieser Reihenfolge: DUnitX (Test, TestCase, TestFixture, Setup, TearDown),
//   JSONName, JSONMarshalled und die Compiler-Attribute weak, unsafe, volatile, Ref; die übrigen danach wie
//   gesammelt. Die Compiler-Attribute haben keine Klasse und kommen immer dazu, wenn sie zum Getippten passen.
// - Detail: Parameter des Konstruktors ("(const AName: string)"), ohne eigenen Konstruktor die Unit.
// - Aus einer nicht eingebundenen Unit mit uses-Eintrag (#180); dieselbe Klasse über mehrere Units (DUnitX
//   reicht TestAttribute aus DUnitX.Attributes über einen Alias in DUnitX.TestFramework weiter) nur einmal:
//   eingebunden vor Alias vor Original.
// - Attributklassen aus Packages der IDE ohne Quelltext (L3): Der Sammler lässt sie über ihren Vorfahren zu
//   (TCompletionAncestry); Detail ist dann ihre Unit.
// - Ohne Nachladen (L4): Klassen und Aliase oberster Ebene aus anderen Units prüft die Nachbearbeitung über den
//   Katalog wie der Vorfilter des Sammlers (TCompletionAncestry). Die Parameter des Konstruktors als Detail gibt
//   es nur, wenn die Unit der Klasse ohnehin im Speicher ist; sonst steht dort die Unit. Vorher bestimmte
//   TCompletionGenerics.ItemSymbol das Symbol jedes Eintrags und lud dafür jede kalte Unit der Liste nach.
// - Abschaltbar mit completion.attributes; dann gilt die gewöhnliche Liste.

interface

uses
  System.SysUtils,
  dpcc.Common.Pascal.Contract,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Lsp.CompletionRequest,
  dpcc.Common.Lsp.CompletionCollector;

type
  TCompletionAttributes = class
  public const
    /// <summary>Bekannte Attribute in der Reihenfolge der Liste; die Klassen heißen NameAttribute.</summary>
    cKnownNames: array[0..6] of string = ('Test', 'TestCase', 'TestFixture', 'Setup', 'TearDown', 'JSONName',
      'JSONMarshalled');
    /// <summary>Attribute, die der Compiler selbst kennt.</summary>
    cCompilerNames: array[0..3] of string = ('weak', 'unsafe', 'volatile', 'Ref');
  public
    /// <summary>Klassennamen der bekannten Attribute (TestAttribute …), für den uses-Eintrag schon ohne Eingabe.
    /// </summary>
    class function KnownClassNames: TArray<string>; static;
    /// <summary>Steht der Name hinter dem Token ALast in einer Attributklammer?</summary>
    class function SiteAt(const ATokens: TArray<TPascalToken>; ALast: Integer): Boolean; static;
    /// <summary>Vorfilter für den Sammler: nur Attributklassen (vor dem Kürzen auf die Höchstzahl).</summary>
    class function Admit(AResolver: TNameResolver): TCompletionAdmitFunc; static;
    /// <summary>Parameterliste aus einem Kopf ("constructor Create(const A: string);" → "(const A: string)");
    /// '' ohne Klammern.</summary>
    class function ParameterText(const ASignature: string): string; static;
    /// <summary>Nur Attributklassen, umbenannt und sortiert (siehe oben), dazu die Compiler-Attribute.</summary>
    class function Apply(ARequest: TCompletionRequest; const AContext: TCompletionContext;
      const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  dpcc.Common.Index.Contract,
  dpcc.Common.Semantics.Attributes,
  dpcc.Common.Lsp.FuzzyMatch,
  dpcc.Common.Lsp.IdeTypes;

{ TCompletionAttributes }

class function TCompletionAttributes.KnownClassNames: TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in cKnownNames do
  begin
    Result := Result + [mName + 'Attribute'];
  end;
end;

class function TCompletionAttributes.SiteAt(const ATokens: TArray<TPascalToken>; ALast: Integer): Boolean;
begin
  Result := TAttributes.InBracket(ATokens, ALast);
end;

class function TCompletionAttributes.Admit(AResolver: TNameResolver): TCompletionAdmitFunc;
begin
  Result :=
    function(const ASymbol: TResolvedSymbol): Boolean
    var
      AttributeClass: TResolvedSymbol;
    begin
      Result := AResolver.Queries.AttributeClassOf(ASymbol, AttributeClass);
    end;
end;

class function TCompletionAttributes.ParameterText(const ASignature: string): string;
var
  mOpen, mIndex, mDepth: Integer;
begin
  Result := '';
  mOpen := Pos('(', ASignature);
  if mOpen = 0 then
  begin
    Exit;
  end;
  mDepth := 0;
  for mIndex := mOpen to Length(ASignature) do
  begin
    if ASignature[mIndex] = '(' then
    begin
      Inc(mDepth);
    end
    else if ASignature[mIndex] = ')' then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit(Copy(ASignature, mOpen, mIndex - mOpen + 1));
      end;
    end;
  end;
end;

/// <summary>Rang eines bekannten Attributs (0 …), -1 sonst.</summary>
function KnownRank(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(TCompletionAttributes.cKnownNames) do
  begin
    if SameText(AName, TCompletionAttributes.cKnownNames[mIndex]) then
    begin
      Exit(mIndex);
    end;
  end;
  for mIndex := 0 to High(TCompletionAttributes.cCompilerNames) do
  begin
    if SameText(AName, TCompletionAttributes.cCompilerNames[mIndex]) then
    begin
      Exit(Length(TCompletionAttributes.cKnownNames) + mIndex);
    end;
  end;
  Result := -1;
end;

type
  TAttributeEntry = record
    Item: TCompletionItem;
    /// <summary>Klasse nach Aliasen, für doppelte Einträge.</summary>
    Key: string;
    /// <summary>Kleiner ist besser: 0 eingebunden, 1 Alias aus anderer Unit, 2 Original aus anderer Unit.</summary>
    Preference: Integer;
    Rank: Integer;
    Order: Integer;
  end;

/// <summary>Bekannte nach ihrem Rang, dann die übrigen in der gesammelten Reihenfolge; Order macht es eindeutig.
/// </summary>
function CompareEntries(const A, B: TAttributeEntry): Integer;
begin
  if (A.Rank >= 0) <> (B.Rank >= 0) then
  begin
    Result := 1;
    if A.Rank >= 0 then
    begin
      Result := -1;
    end;
  end
  else if (A.Rank >= 0) and (A.Rank <> B.Rank) then
  begin
    Result := A.Rank - B.Rank;
  end
  else
  begin
    Result := A.Order - B.Order;
  end;
end;

/// <summary>Vorzug eines Eintrags (siehe TAttributeEntry.Preference).</summary>
function PreferenceOf(const AItem: TCompletionItem; const ASymbol: TResolvedSymbol): Integer;
begin
  Result := 0;
  if Length(AItem.AdditionalEdits) = 0 then
  begin
    Exit;
  end;
  Result := 2;
  if ASymbol.SymbolKind = TIndexSymbolKind.TypeAlias then
  begin
    Result := 1;
  end;
end;

/// <summary>Detail eines Attributs: Parameter des eigenen Konstruktors, sonst die Unit der Klasse.</summary>
function DetailOf(ARequest: TCompletionRequest; const AAttributeClass: TResolvedSymbol): string;
var
  mCtor: TResolvedSymbol;
begin
  Result := '';
  if ARequest.Resolver.DeclaredMember(AAttributeClass, 'Create', mCtor) and
    not SameText(mCtor.Container, 'TCustomAttribute') and not SameText(mCtor.Container, 'TObject') then
  begin
    Result := TCompletionAttributes.ParameterText(mCtor.Signature);
  end;
  if Result = '' then
  begin
    Result := AAttributeClass.UnitName;
  end;
end;

type
  /// <summary>Sammelt die Attribut-Einträge einer Anfrage, eine Klasse nur einmal.</summary>
  TAttributeList = class
  private
    FRequest: TCompletionRequest;
    FPrefix: string;
    FUnits: TDictionary<string, TUnitIndex>;
    FByKey: TDictionary<string, Integer>;
    FEntries: TList<TAttributeEntry>;
    FOrder: Integer;
    /// <summary>Vorfahrenkette über den Katalog (L4); nil ohne Index.</summary>
    FAncestry: TCompletionAncestry;
    function Matches(const AName: string): Boolean;
    procedure Keep(var AEntry: TAttributeEntry);
    /// <summary>Eintrag für eine Attributklasse aus dem Katalog (L4), ohne Nachladen; False, wenn der Katalog den
    /// Eintrag nicht kennt oder nicht zulässt (dann entscheidet AddItem wie bisher).</summary>
    function AddCatalogItem(const AItem: TCompletionItem): Boolean;
    /// <summary>Eintrag für eine Attributklasse aus einem Package der IDE (L3); False bei anderen Einträgen.
    /// </summary>
    function AddIdeItem(const AItem: TCompletionItem): Boolean;
  public
    constructor Create(ARequest: TCompletionRequest; const APrefix: string);
    destructor Destroy; override;
    procedure AddItem(const AItem: TCompletionItem);
    procedure AddCompilerNames;
    function Items: TArray<TCompletionItem>;
  end;

constructor TAttributeList.Create(ARequest: TCompletionRequest; const APrefix: string);
begin
  inherited Create;
  FRequest := ARequest;
  FPrefix := APrefix;
  FUnits := TDictionary<string, TUnitIndex>.Create;
  FByKey := TDictionary<string, Integer>.Create;
  FEntries := TList<TAttributeEntry>.Create;
  if ARequest.Index <> nil then
  begin
    FAncestry := TCompletionAncestry.Create(ARequest.Index, TCompletionAncestryKind.Attributes, ARequest.IdeTypes);
  end;
end;

destructor TAttributeList.Destroy;
begin
  FAncestry.Free;
  FEntries.Free;
  FByKey.Free;
  FUnits.Free;
  inherited;
end;

function TAttributeList.Matches(const AName: string): Boolean;
begin
  Result := MatchScore(AName, FPrefix, FRequest.Matching) <> TFuzzyMatch.cNoMatch;
end;

procedure TAttributeList.Keep(var AEntry: TAttributeEntry);
var
  mExisting: Integer;
begin
  AEntry.Rank := KnownRank(AEntry.Item.Name);
  AEntry.Order := FOrder;
  Inc(FOrder);
  if AEntry.Key = '' then
  begin
    FEntries.Add(AEntry);
  end
  else if not FByKey.TryGetValue(AEntry.Key, mExisting) then
  begin
    FByKey.Add(AEntry.Key, FEntries.Count);
    FEntries.Add(AEntry);
  end
  else if AEntry.Preference < FEntries[mExisting].Preference then
  begin
    AEntry.Order := FEntries[mExisting].Order;
    FEntries[mExisting] := AEntry;
  end;
end;

function TAttributeList.AddIdeItem(const AItem: TCompletionItem): Boolean;
var
  mIdeType: TIdeTypeEntry;
  mName: string;
  mEntry: TAttributeEntry;
begin
  Result := IdeTypeOfItem(FRequest, AItem, mIdeType);
  if not Result then
  begin
    Exit;
  end;
  mName := TAttributes.ShortName(AItem.Name);
  if not Matches(mName) then
  begin
    Exit;
  end;
  mEntry := Default(TAttributeEntry);
  mEntry.Item := AItem;
  mEntry.Item.Name := mName;
  mEntry.Item.FilterText := mName;
  mEntry.Item.InsertText := mName;
  mEntry.Item.Attribute := True;
  mEntry.Item.Detail := mIdeType.UnitName;
  mEntry.Key := UpperCase(mIdeType.UnitName + '.' + mIdeType.Name);
  mEntry.Preference := PreferenceOf(AItem, TResolvedSymbol.Empty);
  Keep(mEntry);
end;

function TAttributeList.AddCatalogItem(const AItem: TCompletionItem): Boolean;
var
  mType, mClass: TCompletionCatalogType;
  mLoaded: TResolvedSymbol;
  mName: string;
  mEntry: TAttributeEntry;
begin
  // Die eigene Unit steht im Baum aktueller als im Katalog.
  Result := (FAncestry <> nil) and not SameText(AItem.SourceFile, FRequest.FileName) and
    FAncestry.ItemType(AItem, mType) and FAncestry.AdmitsCatalog(mType.Symbol);
  if not Result then
  begin
    Exit;
  end;
  mName := TAttributes.ShortName(AItem.Name);
  if not Matches(mName) then
  begin
    Exit;
  end;
  if not FAncestry.ClassOf(mType, mClass) then
  begin
    mClass := mType;
  end;
  mEntry := Default(TAttributeEntry);
  mEntry.Item := AItem;
  mEntry.Item.Name := mName;
  mEntry.Item.FilterText := mName;
  mEntry.Item.InsertText := mName;
  mEntry.Item.Attribute := True;
  // Parameter des Konstruktors nur aus einer Unit im Speicher; sonst die Unit wie bei den IDE-Typen.
  if LoadedTypeSymbol(FRequest.Index, mClass, mLoaded) then
  begin
    mEntry.Item.Detail := DetailOf(FRequest, mLoaded);
  end
  else
  begin
    mEntry.Item.Detail := mClass.UnitName;
  end;
  mEntry.Key := mClass.Key;
  mEntry.Preference := 0;
  if Length(AItem.AdditionalEdits) > 0 then
  begin
    mEntry.Preference := 2;
    if mType.Symbol.Kind = TIndexSymbolKind.TypeAlias then
    begin
      mEntry.Preference := 1;
    end;
  end;
  Keep(mEntry);
end;

procedure TAttributeList.AddItem(const AItem: TCompletionItem);
var
  mSymbol, mAttributeClass: TResolvedSymbol;
  mName: string;
  mEntry: TAttributeEntry;
begin
  if AddCatalogItem(AItem) then
  begin
    Exit;
  end;
  // Ohne Katalogeintrag: Symbol nur aus der eigenen Unit oder einer im Speicher (L4: kein Nachladen).
  if not LoadedItemSymbol(FRequest, FUnits, AItem, mSymbol) then
  begin
    // Ohne Quelle: vielleicht eine Attributklasse aus einem Package der IDE (L3).
    AddIdeItem(AItem);
    Exit;
  end;
  if not FRequest.Resolver.Queries.AttributeClassOf(mSymbol, mAttributeClass) then
  begin
    Exit;
  end;
  mName := TAttributes.ShortName(AItem.Name);
  if not Matches(mName) then
  begin
    Exit;
  end;
  mEntry := Default(TAttributeEntry);
  mEntry.Item := AItem;
  mEntry.Item.Name := mName;
  mEntry.Item.FilterText := mName;
  mEntry.Item.InsertText := mName;
  mEntry.Item.Attribute := True;
  mEntry.Item.Detail := DetailOf(FRequest, mAttributeClass);
  mEntry.Key := UpperCase(mAttributeClass.UnitName + '.' + mAttributeClass.QualifiedName);
  mEntry.Preference := PreferenceOf(AItem, mSymbol);
  Keep(mEntry);
end;

procedure TAttributeList.AddCompilerNames;
var
  mName: string;
  mEntry: TAttributeEntry;
begin
  // Compiler-Attribute ohne Klasse.
  for mName in TCompletionAttributes.cCompilerNames do
  begin
    if Matches(mName) then
    begin
      mEntry := Default(TAttributeEntry);
      mEntry.Item.Name := mName;
      mEntry.Item.Detail := 'Compiler';
      mEntry.Item.Kind := cKindKeyword;
      mEntry.Item.Attribute := True;
      Keep(mEntry);
    end;
  end;
end;

function TAttributeList.Items: TArray<TCompletionItem>;
var
  mSorted: TArray<TAttributeEntry>;
  mIndex: Integer;
begin
  mSorted := FEntries.ToArray;
  TArray.Sort<TAttributeEntry>(mSorted, TComparer<TAttributeEntry>.Construct(
    function(const A, B: TAttributeEntry): Integer
    begin
      Result := CompareEntries(A, B);
    end));
  SetLength(Result, Length(mSorted));
  for mIndex := 0 to High(mSorted) do
  begin
    Result[mIndex] := mSorted[mIndex].Item;
  end;
end;

class function TCompletionAttributes.Apply(ARequest: TCompletionRequest; const AContext: TCompletionContext;
  const AItems: TArray<TCompletionItem>): TArray<TCompletionItem>;
var
  mList: TAttributeList;
  mItem: TCompletionItem;
begin
  mList := TAttributeList.Create(ARequest, AContext.Prefix);
  try
    for mItem in AItems do
    begin
      mList.AddItem(mItem);
    end;
    mList.AddCompilerNames;
    Result := mList.Items;
  finally
    mList.Free;
  end;
end;

end.
