unit dpcc.Common.Lsp.Completion.Values;

// Werte und Deklarationen in der Vervollständigung: Aufzählungen und Mengen (#448), fehlende case-Zweige
// (#449, #50), Muster fortsetzen (#671), unbekannte Namen deklarieren (#471) und „Alle Felder zuweisen“
// (#491). Aus dpcc.Common.Lsp.Completion herausgelöst.

interface

{$SCOPEDENUMS ON}

uses
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Index.Contract,
  dpcc.Common.Rules.Contract,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Lsp.CompletionRequest;

type
  /// <summary>Was die Auflösung von Aufzählungstypen braucht: Auflöser, Index, Baum und Text der Datei und das
  /// Lesen anderer Dateien.</summary>
  TEnumLookup = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    Tree: TSyntaxTree;
    Text: string;
    FileName: string;
    ReadText: TCompletionReadText;
    class function FromRequest(ARequest: TCompletionRequest): TEnumLookup; static;
  end;

  TCompletionValues = class
  public
    /// <summary>Aufzählungen und Mengen (#448). Erwartet die Stelle einen Aufzählungstyp (Zuweisung, Parameter,
    /// Vergleich, case-Zweig), kommen dessen Werte in Deklarationsreihenfolge (Ordinal, bei {$SCOPEDENUMS ON} mit
    /// Typpräfix im InsertText). In einem Mengenkonstruktor ("Anchors := [akLeft, ") kommen alle Werte des
    /// Elementtyps mit SetOf, SetChecked und SetRange; ASetMode ist dann True. False ohne Aufzählungstyp.</summary>
    class function EnumItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>;
      out ASetMode: Boolean): Boolean; static;
    /// <summary>„case vervollständigen“ (#50): Werte der Aufzählung, über die die case-Anweisung verzweigt, deren
    /// "of" vor APosition endet; APrefix ist "TAlign." bei {$SCOPEDENUMS ON}. False ohne Aufzählungstyp.</summary>
    class function CaseValues(const ALookup: TEnumLookup; const APosition: TTextPosition;
      out AValues: TArray<string>; out APrefix: string): Boolean; static;
    /// <summary>Muster fortsetzen (#671): alle Werte des Aufzählungstyps, zu dem der Wert an APosition gehört, in
    /// Deklarationsreihenfolge (ohne Typpräfix). False, wenn dort kein Aufzählungswert steht.</summary>
    class function EnumValuesAt(const ALookup: TEnumLookup; const APosition: TTextPosition;
      out AValues: TArray<string>): Boolean; static;
  end;

/// <summary>uses-Eintrag für ATypeName (#294, #180), wenn der Typ an AOffset nicht sichtbar ist und der Index
/// ihn in einer anderen Unit kennt; sonst leer.</summary>
function TypeUnitEdits(const ALookup: TEnumLookup; const ATypeName, ALineBreak: string;
  AOffset: Integer): TArray<TRuleEdit>;

implementation

uses
  dpcc.Common.Localization.Texts,
  dpcc.Common.Pascal.TokenCursor,
  dpcc.Text.Lines,
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  dpcc.Common.Pascal.Contract,
  dpcc.Common.Editing.Contract,
  dpcc.Common.Editing.CaseCompletion,
  dpcc.Common.Editing.UsesClause,
  dpcc.Common.Editing.InterfaceStubs,
  dpcc.Common.Lsp.FuzzyMatch,
  dpcc.Common.Lsp.CompletionCollector,
  dpcc.Common.Lsp.CompletionEnums,
  dpcc.Common.Lsp.Completion.Context;

type
  /// <summary>Texte der Werte-Vervollständigung in beiden Sprachen (#1458).</summary>
  TValuesText = (FillMissing, InsertAll);

const
  cTexts: array[TValuesText] of TDpccText = (
    (De: 'Fehlende Werte ergänzen (%d)'; En: 'Add missing values (%d)'),
    (De: 'Alle Werte einfügen'; En: 'Insert all values'));
  /// <summary>So oft folgt die Auflösung Aliasen und Mengen bis zur Aufzählung.</summary>
  cMaxAliasSteps = 4;
  /// <summary>Höchstens so viele Zeilen liest RangeText (lange Aufzählungen stehen über viele Zeilen).</summary>
  cMaxRangeLines = 400;

type
  /// <summary>Aufzählungstyp mit seinen Werten (#448).</summary>
  TEnumType = record
    Name: string;
    /// <summary>Mengentyp, über den er gefunden wurde ("TAnchors"); '' ohne.</summary>
    SetName: string;
    Values: TArray<string>;
    /// <summary>Namenspositionen der Werte in FileName; Line -1, wenn unbekannt.</summary>
    Positions: TArray<TTextPosition>;
    FileName: string;
    /// <summary>{$SCOPEDENUMS ON} an der Deklaration: Werte nur mit Typpräfix.</summary>
    Scoped: Boolean;
  end;

/// <summary>Text von ARange, über höchstens cMaxRangeLines Zeilen.</summary>
function RangeText(const AText: string; const ARange: TTextRange): string;
var
  mLines: TArray<string>;
  mLine: Integer;
begin
  Result := '';
  mLines := TextLines(AText);
  for mLine := Max(0, ARange.StartPos.Line) to Min(Min(ARange.EndPos.Line, ARange.StartPos.Line + cMaxRangeLines),
    High(mLines)) do
  begin
    if mLine = ARange.StartPos.Line then
    begin
      Result := Copy(mLines[mLine], ARange.StartPos.Character + 1, MaxInt);
    end
    else
    begin
      Result := Result + #10 + mLines[mLine];
    end;
  end;
end;

/// <summary>Offset (0-basiert) von APosition in AText.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  mIndex, mLine: Integer;
begin
  mLine := 0;
  mIndex := 1;
  while (mLine < APosition.Line) and (mIndex <= Length(AText)) do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
    end;
    Inc(mIndex);
  end;
  Result := mIndex - 1 + APosition.Character;
end;

/// <summary>Quelltext der Datei von ASymbol: das offene Dokument oder über ReadText.</summary>
function SourceOf(const ALookup: TEnumLookup; const ASymbol: TResolvedSymbol; out ASource: string): Boolean;
begin
  ASource := '';
  if SameText(ASymbol.FileName, ALookup.FileName) then
  begin
    ASource := ALookup.Text;
    Exit(True);
  end;
  Result := (ASymbol.FileName <> '') and Assigned(ALookup.ReadText) and ALookup.ReadText(ASymbol.FileName, ASource);
end;

/// <summary>Index-Eintrag der Unit von ASymbol; für das offene Dokument aus dessen Baum.</summary>
function OwnerUnit(const ALookup: TEnumLookup; const ASymbol: TResolvedSymbol; out AUnit: TUnitIndex): Boolean;
begin
  if SameText(ASymbol.FileName, ALookup.FileName) then
  begin
    AUnit := ALookup.Resolver.ExtractedUnit(ALookup.Tree, ALookup.FileName);
    Exit(True);
  end;
  Result := (ALookup.Index <> nil) and ALookup.Index.FindFile(ASymbol.FileName, AUnit);
end;

/// <summary>Typ ATypeName, wie er an AOffset stünde; sonst ein gleichnamiger Typ aus dem Index.</summary>
function TypeAt(const ALookup: TEnumLookup; AOffset: Integer; const ATypeName: string): TResolvedSymbol;
var
  mLocation: TSymbolLocation;
  mOwner: TUnitIndex;
begin
  Result := ALookup.Resolver.ResolveChain(ALookup.Tree, ALookup.FileName, ATypeName.Split(['.']), AOffset);
  // Eingebaute Typen (Integer, string) stehen nicht im Index: nicht danach suchen.
  if (Result.Found and Result.IsType) or (ALookup.Index = nil) or (Pos('.', ATypeName) > 0) or
    TResolverText.IsBuiltinTypeName(ATypeName) then
  begin
    Exit;
  end;
  // Typ einer Eigenschaft aus einer Unit, die hier nicht eingebunden ist (TAnchors aus Vcl.Controls).
  for mLocation in ALookup.Index.FindSymbols(ATypeName) do
  begin
    if (mLocation.Symbol.Container = '') and (mLocation.Symbol.Kind in [TIndexSymbolKind.EnumType,
      TIndexSymbolKind.TypeAlias]) and ALookup.Index.FindUnit(mLocation.UnitName, mOwner) and
      ALookup.Resolver.ResolveTypeFrom(mOwner, ATypeName, Result) then
    begin
      Exit;
    end;
  end;
end;

/// <summary>Ein Schritt von einem Alias oder einer Menge zum Typ dahinter, von der Unit der Deklaration aus;
/// False, wenn er nicht weiterführt.</summary>
function FollowAlias(const ALookup: TEnumLookup; const ADeclaration: string; AAllowSet: Boolean;
  var AType: TResolvedSymbol; var AEnum: TEnumType): Boolean;
var
  mOwner: TUnitIndex;
  mElement: string;
begin
  if not OwnerUnit(ALookup, AType, mOwner) then
  begin
    Exit(False);
  end;
  mElement := TCompletionEnums.SetElement(ADeclaration);
  if mElement = '' then
  begin
    Exit((AType.TypeName <> '') and ALookup.Resolver.ResolveTypeFrom(mOwner, AType.TypeName, AType));
  end;
  Result := AAllowSet and (AEnum.SetName = '');
  if Result then
  begin
    AEnum.SetName := AType.Name;
    Result := ALookup.Resolver.ResolveTypeFrom(mOwner, mElement, AType);
  end;
end;

/// <summary>Folgt Aliasen (und mit AAllowSet einer Menge) bis zur Aufzählung; ASource und ADeclaration sind dann
/// ihr Quelltext und ihre Deklaration.</summary>
function FindEnumDeclaration(const ALookup: TEnumLookup; AAllowSet: Boolean; var AType: TResolvedSymbol;
  var AEnum: TEnumType; out ASource, ADeclaration: string): Boolean;
var
  mStep: Integer;
begin
  ASource := '';
  ADeclaration := '';
  for mStep := 1 to cMaxAliasSteps do
  begin
    // Erst die Art prüfen: Klassen und eingebaute Typen brauchen den Quelltext nicht.
    if not AType.Found or not AType.IsType or not (AType.SymbolKind in [TIndexSymbolKind.EnumType,
      TIndexSymbolKind.TypeAlias]) or not SourceOf(ALookup, AType, ASource) then
    begin
      Exit(False);
    end;
    ADeclaration := RangeText(ASource, AType.Range);
    if AType.SymbolKind = TIndexSymbolKind.EnumType then
    begin
      Exit(True);
    end;
    // Alias oder Menge: von der Unit der Deklaration aus weiter auflösen.
    if not FollowAlias(ALookup, ADeclaration, AAllowSet, AType, AEnum) then
    begin
      Exit(False);
    end;
  end;
  Result := False;
end;

/// <summary>Namenspositionen der Werte für completionItem/resolve.</summary>
procedure FindEnumPositions(const ALookup: TEnumLookup; const AType: TResolvedSymbol; var AEnum: TEnumType);
var
  mOwner: TUnitIndex;
  mSymbol: TIndexSymbol;
  mIndex: Integer;
begin
  SetLength(AEnum.Positions, Length(AEnum.Values));
  for mIndex := 0 to High(AEnum.Positions) do
  begin
    AEnum.Positions[mIndex] := TTextPosition.Create(-1, 0);
  end;
  if not OwnerUnit(ALookup, AType, mOwner) then
  begin
    Exit;
  end;
  for mSymbol in mOwner.Symbols do
  begin
    if (mSymbol.Kind <> TIndexSymbolKind.EnumMember) or not SameText(mSymbol.Container, AType.QualifiedName) then
    begin
      Continue;
    end;
    for mIndex := 0 to High(AEnum.Values) do
    begin
      if SameText(AEnum.Values[mIndex], mSymbol.Name) then
      begin
        AEnum.Positions[mIndex] := mSymbol.SelectionRange.StartPos;
      end;
    end;
  end;
end;

/// <summary>Aufzählung zu AType, Aliase verfolgt; mit AAllowSet auch der Elementtyp einer Menge.</summary>
function EnumOf(const ALookup: TEnumLookup; AType: TResolvedSymbol; AAllowSet: Boolean;
  out AEnum: TEnumType): Boolean;
var
  mSource, mDeclaration: string;
begin
  AEnum := Default(TEnumType);
  Result := FindEnumDeclaration(ALookup, AAllowSet, AType, AEnum, mSource, mDeclaration);
  if Result then
  begin
    AEnum.Values := TCompletionEnums.EnumValues(mDeclaration);
    Result := AEnum.Values <> nil;
  end;
  if Result then
  begin
    AEnum.Name := AType.Name;
    AEnum.FileName := AType.FileName;
    AEnum.Scoped := TCompletionEnums.ScopedAt(mSource, OffsetOf(mSource, AType.Range.StartPos));
    FindEnumPositions(ALookup, AType, AEnum);
  end;
end;

/// <summary>Eintrag für den Wert AIndex von AEnum.</summary>
function EnumItem(const AEnum: TEnumType; AIndex: Integer): TCompletionItem;
begin
  Result := Default(TCompletionItem);
  Result.Name := AEnum.Values[AIndex];
  Result.Kind := cKindEnumMember;
  Result.Detail := AEnum.Name;
  Result.Container := AEnum.Name;
  Result.Ordinal := AIndex + 1;
  Result.Fits := True;
  if AEnum.Scoped then
  begin
    Result.InsertText := AEnum.Name + '.' + AEnum.Values[AIndex];
  end;
  if AEnum.Positions[AIndex].Line >= 0 then
  begin
    Result.SourceFile := AEnum.FileName;
    Result.SourcePosition := AEnum.Positions[AIndex];
  end;
end;

/// <summary>„Alle Werte einfügen“ bzw. „Fehlende Werte ergänzen (n)“ am Anfang eines case-Zweigs (#449).</summary>
function CaseItem(const AEnum: TEnumType; const AText: string; const ATokens: TArray<TPascalToken>;
  const APosition: TTextPosition; out AItem: TCompletionItem): Boolean;
var
  mSlot: TCaseBranchSlot;
  mMissing: TArray<string>;
  mPrefix, mLineBreak, mEndText: string;
begin
  AItem := Default(TCompletionItem);
  Result := TCaseCompletion.BranchSlot(AText, ATokens, APosition, mSlot) and
    TCaseCompletion.Missing(AEnum.Values, mSlot.Labels, mMissing) and (mMissing <> nil);
  if not Result then
  begin
    Exit;
  end;
  mLineBreak := TTextLines.LineBreakOf(AText);
  mPrefix := '';
  if AEnum.Scoped then
  begin
    mPrefix := AEnum.Name + '.';
  end;
  AItem.Name := cTexts[TValuesText.FillMissing].Fmt([Length(mMissing)]);
  if mSlot.Labels = nil then
  begin
    AItem.Name := cTexts[TValuesText.InsertAll].Text;
    AItem.Count := Length(mMissing);
  end;
  AItem.Kind := cKindSnippet;
  AItem.Detail := AEnum.Name;
  AItem.Fits := True;
  AItem.Pinned := True;
  // Erzeugt Code: dpcc wertet die Zusatzänderung ("end;") nicht als uses-Ergänzung.
  AItem.Action := 'case';
  AItem.HasTextEdit := True;
  AItem.TextEdit := TRuleEdit.Create(mSlot.EditRange, TCaseCompletion.BranchesText(mSlot, mMissing, mPrefix,
    mLineBreak));
  mEndText := TCaseCompletion.EndText(mSlot, mLineBreak);
  if mEndText <> '' then
  begin
    AItem.AdditionalEdits := [TRuleEdit.Create(TTextRange.Create(mSlot.EndInsert, mSlot.EndInsert), mEndText)];
  end;
end;

/// <summary>Ein schlichter Typname, der einen uses-Eintrag brauchen kann: nicht generisch, nicht qualifiziert,
/// kein Platzhalter, nicht eingebaut.</summary>
function IsImportableName(const ATypeName: string): Boolean;
begin
  Result := (ATypeName <> '') and (Pos('<', ATypeName) = 0) and (Pos('.', ATypeName) = 0) and
    (Pos('{', ATypeName) = 0) and not TResolverText.IsBuiltinTypeName(ATypeName);
end;

/// <summary>Ein Typ aus einer anderen Unit, die ATree noch nicht einbindet.</summary>
function IsForeignType(AResolver: TNameResolver; ATree: TSyntaxTree; const ALocation: TSymbolLocation): Boolean;
begin
  Result := (ALocation.Symbol.Container = '') and (ALocation.Symbol.Kind in [TIndexSymbolKind.ClassType,
    TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType,
    TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias]) and not SameText(ALocation.UnitName, 'System') and
    not SameText(ALocation.UnitName, TUsesClauses.OwnName(ATree.Tokens));
  Result := Result and not TUsesClauses.IsUsed(TUsesClauses.UsedUnits(ATree.Tokens), ALocation.UnitName,
    AResolver.Namespaces);
end;

/// <summary>uses-Eintrag für ATypeName (#180), wenn der Typ an AOffset nicht sichtbar ist und der Index ihn
/// in einer anderen Unit kennt; leer sonst.</summary>
function TypeUnitEdits(const ALookup: TEnumLookup; const ATypeName, ALineBreak: string;
  AOffset: Integer): TArray<TRuleEdit>;
var
  mLocation: TSymbolLocation;
  mEdit: TRuleEdit;
begin
  Result := nil;
  if (ALookup.Index = nil) or not IsImportableName(ATypeName) or ALookup.Resolver.ResolveChain(ALookup.Tree,
    ALookup.FileName, [ATypeName], AOffset).Found then
  begin
    Exit;
  end;
  for mLocation in ALookup.Index.FindSymbols(ATypeName) do
  begin
    if IsForeignType(ALookup.Resolver, ALookup.Tree, mLocation) and TUsesClauses.AddUnit(ALookup.Tree.Tokens,
      AOffset, mLocation.UnitName, ALineBreak, mEdit) then
    begin
      Result := [mEdit];
      Exit;
    end;
  end;
end;

{ TEnumLookup }

class function TEnumLookup.FromRequest(ARequest: TCompletionRequest): TEnumLookup;
begin
  Result.Resolver := ARequest.Resolver;
  Result.Index := ARequest.Index;
  Result.Tree := ARequest.Tree;
  Result.Text := ARequest.Text;
  Result.FileName := ARequest.FileName;
  Result.ReadText := ARequest.ReadText;
end;

{ Mengen und Werte }

/// <summary>Typ der Elemente im Mengenkonstruktor: "X in [" nimmt den Typ von X, sonst gilt der erwartete Typ an
/// der Klammer.</summary>
function SetElementType(ARequest: TCompletionRequest; const ASlot: TEnumSetSlot;
  out AType: TResolvedSymbol): Boolean;
var
  mTarget: TResolvedSymbol;
  mExpected: string;
  mLookup: TEnumLookup;
begin
  mLookup := TEnumLookup.FromRequest(ARequest);
  if ASlot.ElementOf <> nil then
  begin
    mTarget := ARequest.Resolver.ResolveChain(ARequest.Tree, ARequest.FileName, ASlot.ElementOf, ASlot.Offset);
    Result := mTarget.Found and not mTarget.IsType and (mTarget.TypeName <> '');
    mExpected := mTarget.TypeName;
  end
  else
  begin
    mExpected := TCompletionContexts.ExpectedType(ARequest.Resolver, ARequest.Tree, ARequest.FileName, ASlot.Bracket);
    Result := mExpected <> '';
  end;
  if Result then
  begin
    AType := TypeAt(mLookup, ASlot.Offset, mExpected);
  end;
end;

/// <summary>Alle Werte des Elementtyps im Mengenkonstruktor mit SetOf, SetChecked und SetRange.</summary>
function SetItems(ARequest: TCompletionRequest; const ASlot: TEnumSetSlot;
  out AItems: TArray<TCompletionItem>): Boolean;
var
  mType: TResolvedSymbol;
  mEnum: TEnumType;
  mChecked: TArray<Boolean>;
  mIndex: Integer;
  mItem: TCompletionItem;
begin
  AItems := nil;
  Result := SetElementType(ARequest, ASlot, mType) and EnumOf(TEnumLookup.FromRequest(ARequest), mType,
    ASlot.ElementOf = nil, mEnum) and TCompletionEnums.Checked(mEnum.Values, ASlot.Present, mChecked);
  if not Result then
  begin
    Exit;
  end;
  for mIndex := 0 to High(mEnum.Values) do
  begin
    mItem := EnumItem(mEnum, mIndex);
    mItem.Expected := 'set of ' + mEnum.Name;
    if mEnum.SetName <> '' then
    begin
      mItem.Expected := mEnum.SetName;
    end;
    mItem.SetOf := mEnum.Name;
    mItem.SetChecked := mChecked[mIndex];
    mItem.SetRange := ASlot.EditRange;
    AItems := AItems + [mItem];
  end;
end;

/// <summary>Werte des erwarteten Aufzählungstyps, am Anfang eines case-Zweigs zuerst die fehlenden Zweige.</summary>
function ValueItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>): Boolean;
var
  mContext: TCompletionContext;
  mExpected: string;
  mEnum: TEnumType;
  mIndex: Integer;
  mItem: TCompletionItem;
  mLookup: TEnumLookup;
begin
  AItems := nil;
  mLookup := TEnumLookup.FromRequest(ARequest);
  // Werte: nur ohne Punkt davor ("TAlign." zeigt die Mitglieder selbst).
  mContext := TCompletionContexts.Analyze(ARequest.Tree, ARequest.Position);
  mExpected := '';
  if mContext.Kind = TCompletionContextKind.Scope then
  begin
    mExpected := TCompletionContexts.ExpectedType(ARequest.Resolver, ARequest.Tree, ARequest.FileName,
      ARequest.Position);
  end;
  Result := (mExpected <> '') and EnumOf(mLookup, TypeAt(mLookup, mContext.Offset, mExpected), False, mEnum);
  if not Result then
  begin
    Exit;
  end;
  // Am Anfang eines case-Zweigs (#449): fehlende Zweige auf einmal, als erster Eintrag.
  if CaseItem(mEnum, ARequest.Text, ARequest.Tree.Tokens, ARequest.Position, mItem) then
  begin
    mItem.Expected := mExpected;
    AItems := AItems + [mItem];
  end;
  for mIndex := 0 to High(mEnum.Values) do
  begin
    if MatchScore(mEnum.Values[mIndex], mContext.Prefix, ARequest.Matching) <> TFuzzyMatch.cNoMatch then
    begin
      mItem := EnumItem(mEnum, mIndex);
      mItem.Expected := mExpected;
      AItems := AItems + [mItem];
    end;
  end;
end;

{ Alle Felder zuweisen }

{ TCompletionValues }

class function TCompletionValues.EnumItems(ARequest: TCompletionRequest; out AItems: TArray<TCompletionItem>;
  out ASetMode: Boolean): Boolean;
var
  mSlot: TEnumSetSlot;
begin
  AItems := nil;
  ASetMode := False;
  if ARequest.Tree = nil then
  begin
    Exit(False);
  end;
  // Mengenkonstruktor: "X in [" nimmt den Typ von X, sonst gilt der erwartete Typ an der Klammer.
  if TCompletionEnums.SetSlot(ARequest.Tree.Tokens, ARequest.Position, mSlot) then
  begin
    Result := SetItems(ARequest, mSlot, AItems);
    ASetMode := Result;
  end
  else
  begin
    Result := ValueItems(ARequest, AItems);
  end;
end;

class function TCompletionValues.CaseValues(const ALookup: TEnumLookup; const APosition: TTextPosition;
  out AValues: TArray<string>; out APrefix: string): Boolean;
var
  mExpected: string;
  mEnum: TEnumType;
begin
  AValues := nil;
  APrefix := '';
  mExpected := '';
  // Am Anfang eines Zweigs ist der erwartete Typ der des Selektors (#448).
  if ALookup.Tree <> nil then
  begin
    mExpected := TCompletionContexts.ExpectedType(ALookup.Resolver, ALookup.Tree, ALookup.FileName, APosition);
  end;
  Result := (mExpected <> '') and EnumOf(ALookup, TypeAt(ALookup, OffsetOf(ALookup.Text, APosition), mExpected),
    False, mEnum);
  if Result then
  begin
    AValues := mEnum.Values;
    if mEnum.Scoped then
    begin
      APrefix := mEnum.Name + '.';
    end;
  end;
end;

class function TCompletionValues.EnumValuesAt(const ALookup: TEnumLookup; const APosition: TTextPosition;
  out AValues: TArray<string>): Boolean;
var
  mMember, mType: TResolvedSymbol;
  mOwner: TUnitIndex;
  mEnum: TEnumType;
begin
  AValues := nil;
  if ALookup.Tree = nil then
  begin
    Exit(False);
  end;
  mMember := ALookup.Resolver.Resolve(ALookup.Tree, ALookup.FileName, APosition);
  if not mMember.Found or (mMember.SymbolKind <> TIndexSymbolKind.EnumMember) or (mMember.Container = '') then
  begin
    Exit(False);
  end;
  // Der Typ, wie er an der Stelle sichtbar ist; sonst von der Unit des Werts aus.
  mType := TypeAt(ALookup, OffsetOf(ALookup.Text, APosition), mMember.Container);
  if not (mType.Found and mType.IsType) and OwnerUnit(ALookup, mMember, mOwner) then
  begin
    ALookup.Resolver.ResolveTypeFrom(mOwner, mMember.Container, mType);
  end;
  Result := EnumOf(ALookup, mType, False, mEnum);
  if Result then
  begin
    AValues := mEnum.Values;
  end;
end;

initialization
  TDpccTextTables.Add('dpcc.Common.Lsp.Completion.Values', cTexts);

end.
