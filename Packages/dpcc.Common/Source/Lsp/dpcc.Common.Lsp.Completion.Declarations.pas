unit dpcc.Common.Lsp.Completion.Declarations;

// Vervollständigung in Deklarationen: Zugriffe in "property … read/write" (#31) samt Feld und
// Zugriffsmethoden anlegen (#467), überschreibbare Methoden (#443), fehlende Interface-Methoden (#466) und
// String-Literal als resourcestring auslagern (#473). Aus dpcc.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  dpcc.Common.Lsp.CompletionRequest;

type
  TCompletionDeclarations = class
  public
    /// <summary>In "property Name: T read " bzw. "write " im Klassenrumpf (#31): Felder vom Typ T und Methoden
    /// mit passender Signatur (read: Funktion mit Ergebnis T und den Indexparametern; write: Prozedur mit den
    /// Indexparametern und einem Parameter vom Typ T), auch geerbte. Mit completion.createAccessors kommen
    /// davor „Feld F&lt;Name&gt; anlegen“ und „Get&lt;Name&gt;/Set&lt;Name&gt; anlegen“ (#467). False außerhalb
    /// dieses Kontexts.</summary>
    class function PropertyItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; static;
    /// <summary>In einer Klassendeklaration nach "procedure " bzw. "function " (#443): überschreibbare
    /// Methoden der Vorfahren; Übernehmen setzt den Rest der Deklaration mit override und erzeugt den Rumpf
    /// mit inherited. Nach "override " beide Arten (#31). False außerhalb dieses Kontexts.</summary>
    class function OverrideItems(ARequest: TCompletionRequest; out AItems: TCompletionItems): Boolean; static;
    /// <summary>In der Deklaration einer Klasse mit Interfaces in der Vorfahrenliste (#466), wenn Methoden fehlen.
    /// Leere Zeile bis zum Cursor: je fehlender Methode ein Eintrag mit Kontrollkästchen (Batch), ABatch True.
    /// Angefangenes Wort: je Interface ein Hinweis „n Methoden von I fehlen“ (Hint), der alle seine fehlenden
    /// Methoden anlegt. Deklarationen kommen in den Abschnitt Settings.InterfaceSection (mit Kommentar
    /// "{ I }"), Rümpfe wie bei #443 ohne inherited. False außerhalb dieses Kontexts oder ohne fehlende
    /// Methoden.</summary>
    class function InterfaceItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>;
      out ABatch: Boolean): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Index.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Rules.Contract,
  dpcc.Common.Editing.Contract,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Pascal.Lexer,
  dpcc.Common.Editing.UsesClause,
  dpcc.Common.Editing.CommandSource,
  dpcc.Common.Editing.AccessorCreation,
  dpcc.Common.Editing.ClassCompletion,
  dpcc.Common.Editing.InterfaceStubs,
  dpcc.Common.Lsp.FuzzyMatch,
  dpcc.Common.Lsp.CompletionCollector,
  dpcc.Common.Lsp.Internals.CompletionSource,
  dpcc.Common.Localization.Texts;

type
  /// <summary>Texte der Deklarations-Vervollständigung in beiden Sprachen (#1458).</summary>
  TDeclarationText = (MissingMethod, MissingMethods, ImplementInterface, CreateField, CreateMethod);

const
  cTexts: array[TDeclarationText] of TDpccText = (
    (De: '1 Methode von %s fehlt'; En: '1 method of %s is missing'),
    (De: '%d Methoden von %s fehlen'; En: '%d methods of %s are missing'),
    (De: 'Interface implementieren'; En: 'Implement interface'),
    (De: 'Feld %s anlegen'; En: 'Create field %s'),
    (De: '%s anlegen'; En: 'Create %s'));
  cInterfaceSections: array[TCompletionInterfaceSection] of string = ('private', 'protected', 'public');
  cAccessorTitles: array[TAccessorKind] of TDeclarationText = (TDeclarationText.CreateField,
    TDeclarationText.CreateMethod, TDeclarationText.CreateMethod);

type
  /// <summary>Eine Property-Zeile "property Name[Index]: Typ read|write Anfang" im Klassenrumpf.</summary>
  TPropertySite = record
    Name: string;
    IndexParameters: string;
    PropertyType: string;
    IsWrite: Boolean;
    Prefix: string;
    TypeName: string;
  end;

  /// <summary>Eine Zeile "procedure Na", "class function " oder "override Na" im Klassenrumpf.</summary>
  TOverrideSite = record
    AfterOverride: Boolean;
    TypedClass: Boolean;
    TypedKind: string;
    /// <summary>Einrückung vor "override".</summary>
    IndentLength: Integer;
    TypeName: string;
  end;

  /// <summary>Zerlegte Deklaration einer überschreibbaren Methode.</summary>
  TOverrideDeclaration = record
    Declaration: string;
    IsClass: Boolean;
    Kind: string;
    Head: string;
    Directives: string;
  end;

  /// <summary>Baut die Einträge für fehlende Interface-Methoden (#466) einer Klasse.</summary>
  TInterfaceItemsBuilder = class
  private
    FRequest: TCompletionRequest;
    FBatch: Boolean;
    FItems: TArray<TCompletionItem>;
    FInterfaces: TArray<string>;
    FGroup: TArray<TRuleEdit>;
    FCount: Integer;
    FWordRange: TTextRange;
    FTypeName: string;
    FEndLine: Integer;
    FIndent: string;
    FSection: string;
    FNeedHeader: Boolean;
    function Prepare(out ATypeSymbol: TIndexSymbol): Boolean;
    function StubOf(const AMissing: TResolvedSymbol; const ASourceLines: TArray<string>;
      out AStub: TInterfaceStub): Boolean;
    function StubEdits(const AStub: TInterfaceStub): TArray<TRuleEdit>;
    procedure StartInterface(const AInterface: string);
    procedure AddHint;
    procedure AddBatchItem(const AStub: TInterfaceStub; const AMissing: TResolvedSymbol;
      const AEdits: TArray<TRuleEdit>);
    procedure AddMissing(const AMissing: TArray<TResolvedSymbol>);
    procedure MarkBatch;
  public
    constructor Create(ARequest: TCompletionRequest);
    function Build(out AItems: TArray<TCompletionItem>; out ABatch: Boolean): Boolean;
  end;

{ Property-Zugriffe }

/// <summary>Innerster Klassen- bzw. Objekttyp (mit ARecords auch Record), in dessen Deklaration ALine liegt;
/// ATypeName samt umgebendem Typ.</summary>
function EnclosingType(const AUnit: TUnitIndex; ALine: Integer; ARecords: Boolean; out ATypeName: string): Boolean;
var
  mKinds: TIndexSymbolKinds;
  mTypeSymbol: TIndexSymbol;
begin
  ATypeName := '';
  mKinds := [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType];
  if ARecords then
  begin
    Include(mKinds, TIndexSymbolKind.RecordType);
  end;
  Result := EnclosingTypeAt(AUnit, ALine, mKinds, 0, True, mTypeSymbol);
  if Result then
  begin
    ATypeName := QualifiedTypeName(mTypeSymbol);
  end;
end;

/// <summary>Erkennt "  property Wert[I: Integer]: Double read |", auch mit "index 3" und schon gesetztem read
/// vor write, im Rumpf einer Klasse bzw. eines Records.</summary>
function PropertySiteAt(ARequest: TCompletionRequest; out ASite: TPropertySite): Boolean;
var
  mMatch: TMatch;
begin
  ASite := Default(TPropertySite);
  mMatch := TRegEx.Match(ARequest.LineBefore, '^\s*(?:class\s+)?property\s+(\w+)\s*(\[[^\]]*\])?\s*:\s*' +
    '([\w.<>, ]+?)\s+(?:index\s+\S+\s+)?(?:read\s+\w+\s+)?(read|write)\s+(\w*)$', [roIgnoreCase]);
  Result := mMatch.Success and EnclosingType(ARequest.UnitIndex, ARequest.Position.Line, True, ASite.TypeName);
  if not Result then
  begin
    Exit;
  end;
  ASite.Name := mMatch.Groups[1].Value;
  ASite.IndexParameters := mMatch.Groups[2].Value.Trim(['[', ']']).Trim;
  ASite.PropertyType := mMatch.Groups[3].Value;
  ASite.IsWrite := SameText(mMatch.Groups[4].Value, 'write');
  ASite.Prefix := mMatch.Groups[5].Value;
end;

/// <summary>Zahl der Indexparameter: "I, J: Integer; const S: string" sind drei.</summary>
function IndexParameterCount(const AParameters: string): Integer;
var
  mParam: string;
begin
  Result := 0;
  for mParam in AParameters.Split([';']) do
  begin
    if Pos(':', mParam) > 0 then
    begin
      Inc(Result, Length(Copy(mParam, 1, Pos(':', mParam) - 1).Split([','])));
    end;
  end;
end;

/// <summary>Passt ACandidate als Zugriff: Feld vom Typ (ohne Index), Setter bzw. Getter mit den
/// Indexparametern.</summary>
function AccessorFits(const ACandidate: TResolvedSymbol; const ASite: TPropertySite; AIndexCount: Integer): Boolean;
begin
  if ACandidate.SymbolKind = TIndexSymbolKind.Field then
  begin
    Result := (AIndexCount = 0) and (PlainType(ACandidate.TypeName) = PlainType(ASite.PropertyType));
  end
  else if ASite.IsWrite then
  begin
    Result := (ACandidate.TypeName = '') and (ACandidate.MinArgs <= AIndexCount + 1) and
      (ACandidate.MaxArgs >= AIndexCount + 1) and (Length(ACandidate.ParamTypes) > AIndexCount);
    Result := Result and (PlainType(ACandidate.ParamTypes[AIndexCount]) = PlainType(ASite.PropertyType));
  end
  else
  begin
    Result := (ACandidate.TypeName <> '') and (PlainType(ACandidate.TypeName) = PlainType(ASite.PropertyType)) and
      (ACandidate.MinArgs <= AIndexCount) and (ACandidate.MaxArgs >= AIndexCount);
  end;
end;

/// <summary>Eintrag für ein passendes Feld bzw. eine passende Methode.</summary>
function AccessorCandidateItem(const ACandidate: TResolvedSymbol; const APrefix: string;
  AMatching: TCompletionMatching): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := ACandidate.Name;
  Result.Kind := CompletionKindOf(ACandidate.SymbolKind);
  Result.Detail := ACandidate.TypeName;
  if ACandidate.TypeName = '' then
  begin
    Result.Detail := ACandidate.Container;
  end;
  Result.Container := ACandidate.Container;
  Result.Depth := ACandidate.Depth;
  Result.SourceFile := ACandidate.FileName;
  Result.SourcePosition := ACandidate.SelectionRange.StartPos;
  if (AMatching = TCompletionMatching.Fuzzy) and not ACandidate.Name.StartsWith(APrefix, True) then
  begin
    Result.FilterText := APrefix;
  end;
end;

/// <summary>Arten zum Anlegen: ein Feld nur ohne Indexparameter (read FWert[I] gibt es nicht), dazu Getter
/// bzw. Setter.</summary>
function AccessorKinds(const ASite: TPropertySite): TArray<TAccessorKind>;
begin
  Result := nil;
  if ASite.IndexParameters = '' then
  begin
    Result := [TAccessorKind.Field];
  end;
  if ASite.IsWrite then
  begin
    Result := Result + [TAccessorKind.Setter];
  end
  else
  begin
    Result := Result + [TAccessorKind.Getter];
  end;
end;

/// <summary>Quelle der Klasse am Cursor für TAccessorCreation; der Aufrufer gibt sie frei.</summary>
function AccessorSource(ARequest: TCompletionRequest): TCommandSource;
var
  mSlash: TSlashContext;
  mLines: TArray<string>;
begin
  mLines := ARequest.Lines;
  mSlash := Default(TSlashContext);
  mSlash.Text := ARequest.Text;
  mSlash.Line := ARequest.Position.Line;
  if ARequest.Position.Line <= High(mLines) then
  begin
    mSlash.LineText := mLines[ARequest.Position.Line];
  end;
  mSlash.Index := ARequest.Index;
  Result := TCommandSource.Create(mSlash);
end;

/// <summary>Plan für eine Art: Abschnitt der Methoden aus completion.accessorSection.</summary>
function AccessorPlan(ARequest: TCompletionRequest; const ASite: TPropertySite; AKind: TAccessorKind): TAccessorPlan;
begin
  Result := Default(TAccessorPlan);
  Result.Kind := AKind;
  Result.PropertyName := ASite.Name;
  Result.PropertyType := ASite.PropertyType.Trim;
  Result.IndexParameters := ASite.IndexParameters;
  Result.MethodSection := 'private';
  if ARequest.Settings.AccessorSection = TCompletionAccessorSection.Protected then
  begin
    Result.MethodSection := 'protected';
  end;
end;

/// <summary>Eintrag „Feld F&lt;Name&gt; anlegen“, „Get…“ bzw. „Set… anlegen“ zum Plan.</summary>
function AccessorItem(ARequest: TCompletionRequest; const ASite: TPropertySite; APlan: TAccessorPlan;
  const AEdits: TArray<TTextEdit>; AWithField: Boolean): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := cTexts[cAccessorTitles[APlan.Kind]].Fmt([APlan.Name]);
  Result.Kind := cKindMethod;
  if APlan.Kind = TAccessorKind.Field then
  begin
    Result.Kind := cKindField;
  end;
  Result.Detail := TAccessorCreation.Declaration(APlan);
  Result.Fits := True;
  Result.Pinned := True;
  Result.Action := 'create';
  Result.HasTextEdit := True;
  // Der getippte Anfang wird zum Namen: "read Ca|" → "read FCaption".
  Result.TextEdit := TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(ARequest.Position.Line,
    ARequest.Position.Character - Length(ASite.Prefix)), ARequest.Position), APlan.Name);
  Result.AdditionalEdits := AEdits;
  if AWithField then
  begin
    APlan.Kind := TAccessorKind.Field;
    Result.Detail := Result.Detail + ' + ' + TAccessorCreation.Declaration(APlan);
  end;
end;

/// <summary>„Feld F&lt;Name&gt; anlegen“, „Get&lt;Name&gt; anlegen“ bzw. „Set&lt;Name&gt; anlegen“ (#467).</summary>
function AccessorItems(ARequest: TCompletionRequest; const ASite: TPropertySite): TArray<TCompletionItem>;
var
  mSource: TCommandSource;
  mClass: TIndexSymbol;
  mKind: TAccessorKind;
  mPlan: TAccessorPlan;
  mEdits: TArray<TTextEdit>;
  mWithField: Boolean;
begin
  Result := nil;
  mSource := AccessorSource(ARequest);
  try
    if not mSource.ClassAt(mClass) then
    begin
      Exit;
    end;
    for mKind in AccessorKinds(ASite) do
    begin
      mPlan := AccessorPlan(ARequest, ASite, mKind);
      if TAccessorCreation.Edits(mSource, ARequest.Index, mClass, mPlan, mEdits, mWithField) then
      begin
        Result := Result + [AccessorItem(ARequest, ASite, mPlan, mEdits, mWithField)];
      end;
    end;
  finally
    mSource.Free;
  end;
end;

class function TCompletionDeclarations.PropertyItems(ARequest: TCompletionRequest;
  out AItems: TCompletionItems): Boolean;
var
  mSite: TPropertySite;
  mIndexCount: Integer;
  mCandidate: TResolvedSymbol;
begin
  AItems := Default(TCompletionItems);
  Result := PropertySiteAt(ARequest, mSite);
  if not Result then
  begin
    Exit;
  end;
  // Feld und Zugriffsmethoden anlegen (#467): oben vor den passenden Mitgliedern.
  if ARequest.Settings.CreateAccessors then
  begin
    AItems.Items := AccessorItems(ARequest, mSite);
  end;
  mIndexCount := IndexParameterCount(mSite.IndexParameters);
  for mCandidate in ARequest.Resolver.Queries.AccessorCandidates(ARequest.UnitIndex, mSite.TypeName) do
  begin
    if AccessorFits(mCandidate, mSite, mIndexCount) and
      (MatchScore(mCandidate.Name, mSite.Prefix, ARequest.Matching) <> TFuzzyMatch.cNoMatch) then
    begin
      AItems.Items := AItems.Items + [AccessorCandidateItem(mCandidate, mSite.Prefix, ARequest.Matching)];
    end;
  end;
end;

{ resourcestring }

{ override }

/// <summary>Parameternamen aus "Name(const A, B: T; var C: U): R" in Reihenfolge (#443).</summary>
function OverrideParamNames(const AHead: string): TArray<string>;
var
  mOpen, mClose: Integer;
  mGroup, mNames, mName: string;
begin
  Result := nil;
  mOpen := Pos('(', AHead);
  mClose := LastDelimiter(')', AHead);
  if (mOpen = 0) or (mClose <= mOpen) then
  begin
    Exit;
  end;
  for mGroup in Copy(AHead, mOpen + 1, mClose - mOpen - 1).Split([';']) do
  begin
    mNames := mGroup;
    if Pos(':', mNames) > 0 then
    begin
      mNames := Copy(mNames, 1, Pos(':', mNames) - 1);
    end;
    mNames := Trim(mNames);
    for mName in ['const ', 'var ', 'out ', 'constref '] do
    begin
      if StartsText(mName, mNames) then
      begin
        mNames := Trim(Copy(mNames, Length(mName) + 1, MaxInt));
      end;
    end;
    for mName in mNames.Split([',']) do
    begin
      if Trim(mName) <> '' then
      begin
        Result := Result + [Trim(mName)];
      end;
    end;
  end;
end;

/// <summary>"    procedure Ch|", "    function |", "    class procedure |" oder "    override Ch|" (#31) im
/// Rumpf einer Klasse.</summary>
function OverrideSiteAt(ARequest: TCompletionRequest; out ASite: TOverrideSite): Boolean;
var
  mMatch: TMatch;
begin
  ASite := Default(TOverrideSite);
  mMatch := TRegEx.Match(ARequest.LineBefore, '^\s*(class\s+)?(procedure|function)\s+(\w*)$', [roIgnoreCase]);
  if mMatch.Success then
  begin
    ASite.TypedClass := mMatch.Groups[1].Length > 0;
    ASite.TypedKind := LowerCase(mMatch.Groups[2].Value);
  end
  else
  begin
    // Nach override beide Arten; Übernehmen macht aus der Zeile die Deklaration.
    mMatch := TRegEx.Match(ARequest.LineBefore, '^(\s*)override\s+(\w*)$', [roIgnoreCase]);
    ASite.AfterOverride := mMatch.Success;
    if ASite.AfterOverride then
    begin
      ASite.IndentLength := mMatch.Groups[1].Length;
    end;
  end;
  Result := mMatch.Success and EnclosingType(ARequest.UnitIndex, ARequest.Position.Line, False, ASite.TypeName);
end;

/// <summary>Zerlegt die Deklaration des Kandidaten; False, wenn sie nicht zur getippten Art passt.</summary>
function OverrideDeclarationOf(const ASite: TOverrideSite; const ADeclaration: string;
  out ADecl: TOverrideDeclaration): Boolean;
begin
  ADecl := Default(TOverrideDeclaration);
  ADecl.Declaration := ADeclaration;
  Result := TInterfaceStubs.Split(ADeclaration, ADecl.IsClass, ADecl.Kind, ADecl.Head, ADecl.Directives);
  Result := Result and (ASite.AfterOverride or ((ADecl.Kind = ASite.TypedKind) and
    (ADecl.IsClass = ASite.TypedClass)));
end;

/// <summary>Einfügetext "Kopf; [overload;] override;".</summary>
function OverrideInsert(const ADecl: TOverrideDeclaration): string;
begin
  Result := ADecl.Head + ';';
  if ADecl.Directives.Contains(' overload ') then
  begin
    Result := Result + ' overload;';
  end;
  Result := Result + ' override;';
end;

/// <summary>Anweisung im Rumpf: inherited bzw. Result := inherited …; abstrakt ohne inherited.</summary>
function InheritedCall(const ADecl: TOverrideDeclaration; const AMethodName, ALineBreak: string): string;
var
  mArgs: string;
begin
  mArgs := string.Join(', ', OverrideParamNames(ADecl.Head));
  if ADecl.Directives.Contains(' abstract ') then
  begin
    Result := ALineBreak;
  end
  else if ADecl.Kind = 'procedure' then
  begin
    Result := '  inherited;' + ALineBreak;
  end
  else if mArgs <> '' then
  begin
    Result := '  Result := inherited ' + AMethodName + '(' + mArgs + ');' + ALineBreak;
  end
  else
  begin
    Result := '  Result := inherited ' + AMethodName + ';' + ALineBreak;
  end;
end;

/// <summary>Rumpf mit Kopf samt Typ; Standardwerte (ADefaultValue) stehen nur in der Deklaration.</summary>
function OverrideBody(const ADecl: TOverrideDeclaration; const ATypeName, AMethodName, ALineBreak: string;
  const ADefaultValue: TRegEx): string;
begin
  Result := ADecl.Kind + ' ' + ATypeName + '.' + ADefaultValue.Replace(ADecl.Head, '') + ';';
  if ADecl.IsClass then
  begin
    Result := 'class ' + Result;
  end;
  Result := Result + ALineBreak + 'begin' + ALineBreak + InheritedCall(ADecl, AMethodName, ALineBreak) + 'end;';
end;

/// <summary>"override Name" wird zu "procedure Name(...); override;".</summary>
procedure ReplaceOverrideLine(ARequest: TCompletionRequest; var AItem: TCompletionItem; const ASite: TOverrideSite;
  const ADecl: TOverrideDeclaration);
var
  mLead: string;
begin
  mLead := ADecl.Kind + ' ';
  if ADecl.IsClass then
  begin
    mLead := 'class ' + mLead;
  end;
  AItem.HasTextEdit := True;
  AItem.TextEdit := TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(ARequest.Position.Line,
    ASite.IndentLength), ARequest.Position), mLead + AItem.InsertText);
  AItem.InsertText := '';
  AItem.FilterText := 'override ' + AItem.Name;
end;

/// <summary>Eintrag für eine überschreibbare Methode samt Rumpf.</summary>
function OverrideItem(ARequest: TCompletionRequest; const ASite: TOverrideSite; const ACandidate: TResolvedSymbol;
  const ADecl: TOverrideDeclaration; const ADefaultValue: TRegEx): TCompletionItem;
var
  mEdit: TRuleEdit;
begin
  Result := Default(TCompletionItem);
  Result.Name := ACandidate.Name;
  Result.Kind := cKindMethod;
  Result.Detail := ADecl.Declaration;
  Result.InsertText := OverrideInsert(ADecl);
  Result.Action := 'override';
  Result.Container := ACandidate.Container;
  Result.Depth := ACandidate.Depth;
  Result.SourceFile := ACandidate.FileName;
  Result.SourcePosition := ACandidate.SelectionRange.StartPos;
  if ASite.AfterOverride then
  begin
    ReplaceOverrideLine(ARequest, Result, ASite, ADecl);
  end;
  if TClassCompletion.BodyEdit(ARequest.Tree, ARequest.Text, ASite.TypeName,
    OverrideBody(ADecl, ASite.TypeName, ACandidate.Name, ARequest.LineBreak, ADefaultValue), mEdit) then
  begin
    Result.AdditionalEdits := [mEdit];
  end;
end;

class function TCompletionDeclarations.OverrideItems(ARequest: TCompletionRequest;
  out AItems: TCompletionItems): Boolean;
var
  mSite: TOverrideSite;
  mCandidate: TResolvedSymbol;
  mDecl: TOverrideDeclaration;
  mSourceLines: TArray<string>;
  mFiles: TDictionary<string, TArray<string>>;
  mDefaultValue: TRegEx;
begin
  AItems := Default(TCompletionItems);
  Result := OverrideSiteAt(ARequest, mSite);
  if not Result then
  begin
    Exit;
  end;
  // Je Vorfahren-Unit einmal lesen und zerlegen statt je Kandidat; das Muster für
  // Standardwerte einmal übersetzen. Lokal, weil die Vervollständigung nebenläufig läuft.
  mDefaultValue := TRegEx.Create('\s*=\s*[^;)]+');
  mFiles := TDictionary<string, TArray<string>>.Create;
  try
    for mCandidate in ARequest.Resolver.Queries.OverridableMembers(ARequest.UnitIndex, mSite.TypeName) do
    begin
      if CachedLines(mFiles, mCandidate.FileName, ARequest.FileName, ARequest.Text, ARequest.ReadText,
        mSourceLines) and OverrideDeclarationOf(mSite, TInterfaceStubs.DeclarationOf(mSourceLines,
        mCandidate.Range), mDecl) then
      begin
        AItems.Items := AItems.Items + [OverrideItem(ARequest, mSite, mCandidate, mDecl, mDefaultValue)];
      end;
    end;
  finally
    mFiles.Free;
  end;
end;

{ TInterfaceItemsBuilder }

constructor TInterfaceItemsBuilder.Create(ARequest: TCompletionRequest);
begin
  inherited Create;
  FRequest := ARequest;
end;

function TInterfaceItemsBuilder.Prepare(out ATypeSymbol: TIndexSymbol): Boolean;
var
  mMatch: TMatch;
  mLines: TArray<string>;
  mLine: TTextPosition;
begin
  ATypeSymbol := Default(TIndexSymbol);
  mLine := FRequest.Position;
  // "    |" (Strg+Leer auf leerer Zeile) bzw. "    Exp|"
  mMatch := TRegEx.Match(FRequest.LineBefore, '^(\s*)(\w*)$');
  mLines := FRequest.Lines;
  Result := mMatch.Success and (mLine.Line >= 0) and (mLine.Line <= High(mLines));
  if not Result then
  begin
    Exit;
  end;
  FBatch := mMatch.Groups[2].Length = 0;
  FWordRange := TTextRange.Create(mLine.Line, mMatch.Groups[1].Length, mLine.Line, mLine.Character);
  // Leere Zeile nur, wenn auch dahinter nichts steht; vor einer vorhandenen Deklaration bleibt Strg+Leer
  // normal. Nur Klassen mit Interfaces in der Vorfahrenliste; "end" in der Zeile des Cursors zählt nicht mehr
  // dazu.
  Result := not (FBatch and (Trim(Copy(mLines[mLine.Line], mLine.Character + 1, MaxInt)) <> '')) and
    EnclosingTypeAt(FRequest.UnitIndex, mLine.Line, [TIndexSymbolKind.ClassType], 2, False, ATypeSymbol);
  FEndLine := ATypeSymbol.Range.EndPos.Line;
  Result := Result and (FEndLine <= High(mLines)) and TRegEx.IsMatch(mLines[FEndLine], '^\s*end\b',
    [roIgnoreCase]);
  if Result then
  begin
    FIndent := Copy(mLines[FEndLine], 1, Length(mLines[FEndLine]) - Length(TrimLeft(mLines[FEndLine])));
    FTypeName := QualifiedTypeName(ATypeSymbol);
  end;
end;

function TInterfaceItemsBuilder.StubOf(const AMissing: TResolvedSymbol; const ASourceLines: TArray<string>;
  out AStub: TInterfaceStub): Boolean;
begin
  // Generische Interfaces: Typargumente in die Deklaration einsetzen (IComparer<TKunde>: T → TKunde).
  Result := TInterfaceStubs.Make(TInterfaceStubs.GenericName(AMissing.Container, AMissing.Bindings), FTypeName,
    TInterfaceStubs.SubstituteWords(TInterfaceStubs.DeclarationOf(ASourceLines, AMissing.Range),
    AMissing.Bindings), FRequest.LineBreak, AStub);
end;

function TInterfaceItemsBuilder.StubEdits(const AStub: TInterfaceStub): TArray<TRuleEdit>;
var
  mEdit: TRuleEdit;
begin
  Result := TInterfaceStubs.ClassEdits(AStub, FEndLine, FIndent, FSection, FNeedHeader, FRequest.LineBreak);
  if TClassCompletion.BodyEdit(FRequest.Tree, FRequest.Text, FTypeName, AStub.Body, mEdit) then
  begin
    Result := Result + [mEdit];
  end;
end;

procedure TInterfaceItemsBuilder.StartInterface(const AInterface: string);
begin
  if (Length(FInterfaces) > 0) and SameText(FInterfaces[High(FInterfaces)], AInterface) then
  begin
    Exit;
  end;
  if not FBatch then
  begin
    AddHint;
  end;
  FInterfaces := FInterfaces + [AInterface];
  FGroup := nil;
  FCount := 0;
end;

procedure TInterfaceItemsBuilder.AddHint;
var
  mHint: TCompletionItem;
  mInterface: string;
begin
  if (FCount = 0) or (Length(FInterfaces) = 0) then
  begin
    Exit;
  end;
  mInterface := FInterfaces[High(FInterfaces)];
  mHint := Default(TCompletionItem);
  mHint.Name := cTexts[TDeclarationText.MissingMethods].Fmt([FCount, mInterface]);
  if FCount = 1 then
  begin
    mHint.Name := cTexts[TDeclarationText.MissingMethod].Fmt([mInterface]);
  end;
  mHint.Detail := cTexts[TDeclarationText.ImplementInterface].Text;
  mHint.Kind := cKindSnippet;
  mHint.Hint := True;
  mHint.Action := 'implement';
  mHint.Container := mInterface;
  // Das angefangene Wort verschwindet, die Methoden kommen über die weiteren Änderungen.
  mHint.HasTextEdit := True;
  mHint.TextEdit := TRuleEdit.Create(FWordRange, '');
  mHint.AdditionalEdits := TInterfaceStubs.Merge(FGroup);
  FItems := FItems + [mHint];
end;

procedure TInterfaceItemsBuilder.AddBatchItem(const AStub: TInterfaceStub; const AMissing: TResolvedSymbol;
  const AEdits: TArray<TRuleEdit>);
var
  mItem: TCompletionItem;
begin
  mItem := Default(TCompletionItem);
  mItem.Name := AStub.Name;
  mItem.Kind := cKindMethod;
  mItem.Detail := AStub.Declaration;
  mItem.Container := AStub.InterfaceName;
  mItem.Action := 'implement';
  mItem.Batch := True;
  mItem.Ordinal := Length(FItems) + 1;
  mItem.SetChecked := True;
  mItem.SetRange := FWordRange;
  mItem.AdditionalEdits := AEdits;
  mItem.SourceFile := AMissing.FileName;
  mItem.SourcePosition := AMissing.SelectionRange.StartPos;
  FItems := FItems + [mItem];
end;

procedure TInterfaceItemsBuilder.AddMissing(const AMissing: TArray<TResolvedSymbol>);
var
  mFiles: TDictionary<string, TArray<string>>;
  mSourceLines: TArray<string>;
  mMissing: TResolvedSymbol;
  mStub: TInterfaceStub;
  mEdits: TArray<TRuleEdit>;
begin
  // Je Datei einmal lesen, auch wenn die Interfaces abwechselnd aus mehreren Units stammen.
  mFiles := TDictionary<string, TArray<string>>.Create;
  try
    for mMissing in AMissing do
    begin
      if not CachedLines(mFiles, mMissing.FileName, FRequest.FileName, FRequest.Text, FRequest.ReadText,
        mSourceLines) then
      begin
        mSourceLines := TextLines('');
      end;
      if not StubOf(mMissing, mSourceLines, mStub) then
      begin
        Continue;
      end;
      StartInterface(mStub.InterfaceName);
      mEdits := StubEdits(mStub);
      FGroup := FGroup + mEdits;
      Inc(FCount);
      if FBatch then
      begin
        AddBatchItem(mStub, mMissing, mEdits);
      end;
    end;
  finally
    mFiles.Free;
  end;
end;

procedure TInterfaceItemsBuilder.MarkBatch;
var
  mIndex: Integer;
begin
  // Eine Überschrift über der ganzen Liste: „Fehlende Methoden von IExporter, IInterface“.
  for mIndex := 0 to High(FItems) do
  begin
    if FItems[mIndex].Batch then
    begin
      FItems[mIndex].SetOf := string.Join(', ', FInterfaces);
      FItems[mIndex].Expected := FItems[mIndex].SetOf;
      FItems[mIndex].Fits := True;
    end;
  end;
end;

function TInterfaceItemsBuilder.Build(out AItems: TArray<TCompletionItem>; out ABatch: Boolean): Boolean;
var
  mTypeSymbol: TIndexSymbol;
  mMissing: TArray<TResolvedSymbol>;
begin
  AItems := nil;
  Result := Prepare(mTypeSymbol);
  ABatch := FBatch;
  if not Result then
  begin
    Exit;
  end;
  // Vorfahrenliste aus dem Quelltext: Der Index kennt die Typargumente nur beim ersten Vorfahren.
  mMissing := FRequest.Resolver.Queries.MissingInterfaceMembers(FRequest.UnitIndex, FTypeName,
    TInterfaceStubs.HeaderAncestors(FRequest.Lines, mTypeSymbol.Range.StartPos.Line));
  Result := Length(mMissing) > 0;
  if not Result then
  begin
    Exit;
  end;
  FSection := cInterfaceSections[FRequest.Settings.InterfaceSection];
  FNeedHeader := TInterfaceStubs.LastSection(FRequest.Tree.Tokens, mTypeSymbol.Range.StartPos.Line, FEndLine) <>
    FSection;
  AddMissing(mMissing);
  if not FBatch then
  begin
    AddHint;
  end;
  MarkBatch;
  AItems := FItems;
  Result := Length(AItems) > 0;
end;

class function TCompletionDeclarations.InterfaceItems(ARequest: TCompletionRequest;
  out AItems: TArray<TCompletionItem>; out ABatch: Boolean): Boolean;
var
  mBuilder: TInterfaceItemsBuilder;
begin
  mBuilder := TInterfaceItemsBuilder.Create(ARequest);
  try
    Result := mBuilder.Build(AItems, ABatch);
  finally
    mBuilder.Free;
  end;
end;

initialization
  TDpccTextTables.Add('dpcc.Common.Lsp.Completion.Declarations', cTexts);

end.
