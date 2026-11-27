unit Shell.LspServer.DocumentSymbols;

// Host-Rolle Shell, nur in dpcc.LspServer.exe: textDocument/documentSymbol für die Strukturansicht der IDE.
// Hierarchisch wie DelphiLSP (gemessen am 26.11.2026 in Delphi 12 und 13, nachgemessen am 27.11.2026 über
// Stellvertreter in der IDE):
//   interface / implementation   kind 2 (Namespace), detail "section", Bereich vom Schlüsselwort bis zur letzten
//                                Deklaration; implementation ohne initialization bis zum end von "end."
//   uses                         kind 2, detail "section", Bereich vom Wort uses bis zum Ende der letzten Unit, vorn
//                                im Abschnitt; je Unit kind 1 (File), detail "", Bereich der Name
//   Klasse, Objekt, Helper        kind 5 (Class), Bereich vom Wort class bis end; Record kind 23, Interface kind 11,
//                                Aufzählung, Alias und übrige Typen kind 23
//   Feld                         kind 8, Name "FWert: Integer", Bereich nur der Name
//   Property                     kind 7, Name "Wert: Integer", detail der Zugriff ("read FWert write FWert")
//   Methode in der Klasse        kind 6 (auch Konstruktoren), Name "Twice(const A: Integer): Integer", detail
//                                "declaration", Bereich vom Namen bis zum Ergebnistyp
//   Routine im interface         kind 6, detail "declaration"
//   Routine im implementation    kind 6, Name "TProbe.Twice(const A: Integer): Integer", detail "implementation",
//                                Bereich vom Schlüsselwort bis end
//   Variable / Konstante         kind 13 / 14
// Nicht nachgebaut: Bereiche von Konstanten und Typen enden bei DelphiLSP eins vor dem Namensende, Deklarationen von
// Methoden reichen dort bis zum Ende der Direktiven.
// selectionRange gleich range, Blätter mit leerem children (wie DelphiLSP). Programme und Packages ohne Abschnitte
// liefern die Deklarationen direkt. Der Baum kommt aus dem Baum-Cache (TSyntaxTreeCache, aktive Zweige); ist das
// Dokument nicht geöffnet oder scheitert etwas, ist die Antwort leer statt ein Fehler.

interface

uses
  System.SysUtils,
  System.JSON,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.SyntaxTree;

type
  TLspDocumentSymbols = class
  public const
    cMethod = 'textDocument/documentSymbol';
    cKindFile = 1;
    cKindNamespace = 2;
    cKindClass = 5;
    cKindMethod = 6;
    cKindProperty = 7;
    cKindField = 8;
    /// <summary>Wie DelphiLSP: Konstruktoren wie Methoden.</summary>
    cKindConstructor = 6;
    /// <summary>Wie DelphiLSP: Aufzählungen und übrige Typen wie Records.</summary>
    cKindEnum = 23;
    cKindInterface = 11;
    cKindVariable = 13;
    cKindConstant = 14;
    cKindStruct = 23;
  private
    FDocuments: IDocumentStore;
    function Handle(const AParams: TJSONValue): TJSONValue;
  public
    constructor Create(const ADocuments: IDocumentStore);
    /// <summary>Meldet textDocument/documentSymbol als nebenläufige Anfrage an.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Symbolbaum zu ATree über AText (Text des Baums); der Aufrufer übernimmt das Array.</summary>
    class function Build(ATree: TSyntaxTree; const AText: string): TJSONArray; static;
  end;

implementation

uses
  System.StrUtils,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.Pascal.Contract,
  dpcc.Common.Pascal.TreeCache,
  dpcc.Common.Lsp.Positions;

type
  /// <summary>Baut die Symbole eines Baums.</summary>
  TSymbolBuilder = class
  private
    FTree: TSyntaxTree;
    FText: string;
    function NodeText(ANode: TSyntaxNode): string;
    /// <summary>Ende des letzten Tokens im Knoten ohne abschließendes ";" und Kommentare.</summary>
    function TrimmedEnd(ANode: TSyntaxNode): TTextPosition;
    /// <summary>Erstes Bezeichner-Token ab AOffset (vor AEndOffset) mit dem Text AName; -1 ohne.</summary>
    function NameToken(AOffset, AEndOffset: Integer; const AName: string): Integer;
    /// <summary>Token des Routinennamens im Kopf AHeader (hinter class, procedure, function …); -1 ohne.</summary>
    function RoutineNameToken(AHeader: TSyntaxNode): Integer;
    function Symbol(const AName, ADetail: string; AKind: Integer; const AStart, AEnd: TTextPosition): TJSONObject;
    function Children(ASymbol: TJSONObject): TJSONArray;
    /// <summary>Text des ersten Typknotens unter ANode ('' ohne).</summary>
    function TypeTextOf(ANode: TSyntaxNode): string;
    function RoutineLabel(AHeader: TSyntaxNode; AQualified: Boolean): string;
    /// <summary>Zugriffsteil einer Property hinter dem Typ ("read FWert write FWert"); '' ohne.</summary>
    function PropertyAccess(ANode: TSyntaxNode): string;
    /// <summary>Bereich des Unit-Namens in einem Eintrag der uses-Klausel (ohne "in 'Datei'"); False ohne.</summary>
    function UnitNameRange(AItem: TSyntaxNode; out AStart, AEnd: TTextPosition): Boolean;
    /// <summary>Ende des Worts end in "end." am Dateiende; False ohne.</summary>
    function FinalEnd(out APosition: TTextPosition): Boolean;
    procedure AddNamed(ANode: TSyntaxNode; AKind: Integer; const AType, ADetail: string; ATarget: TJSONArray);
    procedure AddUses(AClause: TSyntaxNode; ATarget: TJSONArray);
    procedure AddRoutine(ADecl, AHeader: TSyntaxNode; AImplementation: Boolean; ATarget: TJSONArray);
    procedure AddType(ADecl: TSyntaxNode; ATarget: TJSONArray);
    procedure AddMembers(AType: TSyntaxNode; ATarget: TJSONArray);
    procedure AddDeclarations(ANode: TSyntaxNode; AImplementation: Boolean; ATarget: TJSONArray);
  public
    constructor Create(ATree: TSyntaxTree; const AText: string);
    function Build: TJSONArray;
  end;

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

function IsCodeToken(const AToken: TPascalToken): Boolean;
begin
  Result := not (AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]);
end;

{ TSymbolBuilder }

constructor TSymbolBuilder.Create(ATree: TSyntaxTree; const AText: string);
begin
  inherited Create;
  FTree := ATree;
  FText := AText;
end;

function TSymbolBuilder.NodeText(ANode: TSyntaxNode): string;
begin
  Result := '';
  if (ANode <> nil) and (ANode.EndOffset > ANode.StartOffset) then
  begin
    Result := CollapseSpaces(Copy(FText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;
end;

function TSymbolBuilder.TrimmedEnd(ANode: TSyntaxNode): TTextPosition;
var
  mIndex: Integer;
  mTokens: TArray<TPascalToken>;
begin
  Result := ANode.EndPos;
  mTokens := FTree.Tokens;
  mIndex := FTree.FirstTokenFrom(ANode.EndOffset) - 1;
  while (mIndex >= 0) and (mTokens[mIndex].Offset >= ANode.StartOffset) and
    (not IsCodeToken(mTokens[mIndex]) or mTokens[mIndex].IsSymbol(';')) do
  begin
    Dec(mIndex);
  end;
  if (mIndex >= 0) and (mTokens[mIndex].Offset >= ANode.StartOffset) then
  begin
    Result := mTokens[mIndex].EndPos;
  end;
end;

function TSymbolBuilder.NameToken(AOffset, AEndOffset: Integer; const AName: string): Integer;
var
  mIndex: Integer;
  mTokens: TArray<TPascalToken>;
  mText: string;
begin
  Result := -1;
  mTokens := FTree.Tokens;
  mIndex := FTree.FirstTokenFrom(AOffset);
  while (mIndex < Length(mTokens)) and (mTokens[mIndex].Offset < AEndOffset) do
  begin
    mText := mTokens[mIndex].Text;
    if StartsStr('&', mText) then
    begin
      mText := Copy(mText, 2, MaxInt);
    end;
    if (mTokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) and SameText(mText, AName) then
    begin
      Exit(mIndex);
    end;
    Inc(mIndex);
  end;
end;

function TSymbolBuilder.RoutineNameToken(AHeader: TSyntaxNode): Integer;
const
  cHeadWords: array[0..5] of string = ('class', 'procedure', 'function', 'constructor', 'destructor', 'operator');
var
  mIndex: Integer;
  mTokens: TArray<TPascalToken>;
begin
  Result := -1;
  mTokens := FTree.Tokens;
  mIndex := FTree.FirstTokenFrom(AHeader.StartOffset);
  while (mIndex < Length(mTokens)) and (mTokens[mIndex].Offset < AHeader.EndOffset) do
  begin
    if IsCodeToken(mTokens[mIndex]) and not (mTokens[mIndex].IsSymbol('[') or mTokens[mIndex].IsSymbol(']')) and
      (IndexText(mTokens[mIndex].Text, cHeadWords) < 0) then
    begin
      Exit(mIndex);
    end;
    Inc(mIndex);
  end;
end;

function TSymbolBuilder.Symbol(const AName, ADetail: string; AKind: Integer; const AStart,
  AEnd: TTextPosition): TJSONObject;
var
  mRange: TTextRange;
begin
  mRange := TTextRange.Create(AStart, AEnd);
  Result := TJSONObject.Create;
  Result.AddPair('name', AName);
  Result.AddPair('detail', ADetail);
  Result.AddPair('kind', TJSONNumber.Create(AKind));
  Result.AddPair('range', TLspPositions.RangeToJson(mRange));
  Result.AddPair('selectionRange', TLspPositions.RangeToJson(mRange));
  Result.AddPair('children', TJSONArray.Create);
end;

function TSymbolBuilder.Children(ASymbol: TJSONObject): TJSONArray;
begin
  Result := ASymbol.GetValue('children') as TJSONArray;
end;

function TSymbolBuilder.TypeTextOf(ANode: TSyntaxNode): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    if not (ANode[mIndex].Kind in [TSyntaxKind.Attribute, TSyntaxKind.Error, TSyntaxKind.Parameters,
      TSyntaxKind.Directive, TSyntaxKind.GenericParams]) then
    begin
      Exit(NodeText(ANode[mIndex]));
    end;
  end;
end;

function TSymbolBuilder.RoutineLabel(AHeader: TSyntaxNode; AQualified: Boolean): string;
var
  mParams, mResult: TSyntaxNode;
  mIndex: Integer;
begin
  Result := AHeader.Name;
  if not AQualified and (LastDelimiter('.', Result) > 0) then
  begin
    Result := Copy(Result, LastDelimiter('.', Result) + 1, MaxInt);
  end;
  mParams := AHeader.FindChild(TSyntaxKind.Parameters);
  if mParams <> nil then
  begin
    Result := Result + NodeText(mParams);
  end;
  mResult := nil;
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if AHeader[mIndex].Kind in [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType] then
    begin
      mResult := AHeader[mIndex];
    end;
  end;
  if mResult <> nil then
  begin
    Result := Result + ': ' + NodeText(mResult);
  end;
end;

function TSymbolBuilder.PropertyAccess(ANode: TSyntaxNode): string;
var
  mType: TSyntaxNode;
begin
  Result := '';
  mType := ANode.FindChild(TSyntaxKind.TypeReference);
  if (mType = nil) or (ANode.EndOffset <= mType.EndOffset) then
  begin
    Exit;
  end;
  Result := Trim(CollapseSpaces(Copy(FText, mType.EndOffset + 1, ANode.EndOffset - mType.EndOffset)));
  while EndsStr(';', Result) do
  begin
    Result := TrimRight(Copy(Result, 1, Length(Result) - 1));
  end;
end;

function TSymbolBuilder.UnitNameRange(AItem: TSyntaxNode; out AStart, AEnd: TTextPosition): Boolean;
var
  mIndex: Integer;
  mTokens: TArray<TPascalToken>;
begin
  Result := False;
  AStart := AItem.StartPos;
  AEnd := AItem.StartPos;
  mTokens := FTree.Tokens;
  mIndex := FTree.FirstTokenFrom(AItem.StartOffset);
  while (mIndex < Length(mTokens)) and (mTokens[mIndex].Offset < AItem.EndOffset) do
  begin
    if IsCodeToken(mTokens[mIndex]) then
    begin
      // "System.SysUtils" aus Bezeichnern und Punkten; "in 'Datei.pas'" gehört nicht dazu.
      if mTokens[mIndex].IsKeyword('in') or (mTokens[mIndex].Kind = TPascalTokenKind.StringLiteral) then
      begin
        Break;
      end;
      if mTokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
      begin
        if not Result then
        begin
          AStart := mTokens[mIndex].StartPos;
        end;
        AEnd := mTokens[mIndex].EndPos;
        Result := True;
      end
      else if not mTokens[mIndex].IsSymbol('.') then
      begin
        Break;
      end;
    end;
    Inc(mIndex);
  end;
end;

function TSymbolBuilder.FinalEnd(out APosition: TTextPosition): Boolean;
var
  mIndex, mPrevious: Integer;
  mTokens: TArray<TPascalToken>;
begin
  Result := False;
  APosition := TTextPosition.Create(0, 0);
  mTokens := FTree.Tokens;
  // Von hinten der erste Punkt, vor dem (ohne Kommentare) end steht.
  for mIndex := High(mTokens) downto 1 do
  begin
    if not mTokens[mIndex].IsSymbol('.') then
    begin
      Continue;
    end;
    mPrevious := mIndex - 1;
    while (mPrevious >= 0) and not IsCodeToken(mTokens[mPrevious]) do
    begin
      Dec(mPrevious);
    end;
    if (mPrevious >= 0) and mTokens[mPrevious].IsKeyword('end') then
    begin
      APosition := mTokens[mPrevious].EndPos;
      Exit(True);
    end;
  end;
end;

procedure TSymbolBuilder.AddUses(AClause: TSyntaxNode; ATarget: TJSONArray);
var
  mIndex, mToken: Integer;
  mStart, mEnd, mNameStart, mNameEnd: TTextPosition;
  mSection: TJSONObject;
  mTokens: TArray<TPascalToken>;
  mNames: TArray<string>;
  mStarts, mEnds: TArray<TTextPosition>;
begin
  mTokens := FTree.Tokens;
  mStart := AClause.StartPos;
  mToken := FTree.FirstTokenFrom(AClause.StartOffset);
  if mToken < Length(mTokens) then
  begin
    mStart := mTokens[mToken].StartPos;
    mEnd := mTokens[mToken].EndPos;
  end
  else
  begin
    mEnd := mStart;
  end;
  mNames := nil;
  mStarts := nil;
  mEnds := nil;
  for mIndex := 0 to AClause.ChildCount - 1 do
  begin
    if (AClause[mIndex].Kind = TSyntaxKind.UsedUnit) and (AClause[mIndex].Name <> '') and
      UnitNameRange(AClause[mIndex], mNameStart, mNameEnd) then
    begin
      mNames := mNames + [AClause[mIndex].Name];
      mStarts := mStarts + [mNameStart];
      mEnds := mEnds + [mNameEnd];
      mEnd := mNameEnd;
    end;
  end;
  // Wie DelphiLSP: vom Wort uses bis zum Ende der letzten Unit, je Unit der Name.
  mSection := Symbol('uses', 'section', TLspDocumentSymbols.cKindNamespace, mStart, mEnd);
  ATarget.AddElement(mSection);
  for mIndex := 0 to High(mNames) do
  begin
    Children(mSection).AddElement(Symbol(mNames[mIndex], '', TLspDocumentSymbols.cKindFile, mStarts[mIndex],
      mEnds[mIndex]));
  end;
end;

procedure TSymbolBuilder.AddNamed(ANode: TSyntaxNode; AKind: Integer; const AType, ADetail: string;
  ATarget: TJSONArray);
var
  mName, mLabel: string;
  mToken: Integer;
  mTokens: TArray<TPascalToken>;
begin
  mTokens := FTree.Tokens;
  // "A, B: Integer": je Name ein Eintrag.
  for mName in ANode.Name.Split([',']) do
  begin
    if Trim(mName) = '' then
    begin
      Continue;
    end;
    mLabel := Trim(mName);
    if AType <> '' then
    begin
      mLabel := mLabel + ': ' + AType;
    end;
    mToken := NameToken(ANode.StartOffset, ANode.EndOffset, Trim(mName));
    if mToken >= 0 then
    begin
      ATarget.AddElement(Symbol(mLabel, ADetail, AKind, mTokens[mToken].StartPos, mTokens[mToken].EndPos));
    end
    else
    begin
      ATarget.AddElement(Symbol(mLabel, ADetail, AKind, ANode.StartPos, ANode.StartPos));
    end;
  end;
end;

procedure TSymbolBuilder.AddRoutine(ADecl, AHeader: TSyntaxNode; AImplementation: Boolean; ATarget: TJSONArray);
var
  mKind, mToken, mIndex: Integer;
  mStart, mEnd: TTextPosition;
  mTokens: TArray<TPascalToken>;
  mWord: string;
begin
  if AHeader.IsMethodResolution then
  begin
    Exit;
  end;
  mTokens := FTree.Tokens;
  mKind := TLspDocumentSymbols.cKindMethod;
  mIndex := FTree.FirstTokenFrom(AHeader.StartOffset);
  if mIndex < Length(mTokens) then
  begin
    mWord := LowerCase(mTokens[mIndex].Text);
    if (mWord = 'constructor') and not AImplementation then
    begin
      mKind := TLspDocumentSymbols.cKindConstructor;
    end;
  end;
  if AImplementation then
  begin
    // Ganze Routine vom Schlüsselwort bis end, Name qualifiziert (TProbe.Twice(…)).
    mStart := ADecl.StartPos;
    mEnd := TrimmedEnd(ADecl);
    ATarget.AddElement(Symbol(RoutineLabel(AHeader, True), 'implementation', mKind, mStart, mEnd));
    Exit;
  end;
  // Deklaration: vom Namen bis zum Ende von Parametern und Ergebnistyp, ohne Direktiven.
  mToken := RoutineNameToken(AHeader);
  if mToken < 0 then
  begin
    mStart := AHeader.StartPos;
    mEnd := AHeader.StartPos;
  end
  else
  begin
    mStart := mTokens[mToken].StartPos;
    mEnd := mTokens[mToken].EndPos;
  end;
  for mIndex := 0 to AHeader.ChildCount - 1 do
  begin
    if (AHeader[mIndex].Kind in [TSyntaxKind.Parameters, TSyntaxKind.TypeReference, TSyntaxKind.ArrayType,
      TSyntaxKind.GenericParams]) and (AHeader[mIndex].EndOffset > AHeader[mIndex].StartOffset) then
    begin
      mEnd := AHeader[mIndex].EndPos;
    end;
  end;
  ATarget.AddElement(Symbol(RoutineLabel(AHeader, False), 'declaration', mKind, mStart, mEnd));
end;

procedure TSymbolBuilder.AddType(ADecl: TSyntaxNode; ATarget: TJSONArray);
var
  mIndex, mKind, mToken: Integer;
  mType: TSyntaxNode;
  mSymbol: TJSONObject;
  mTokens: TArray<TPascalToken>;
begin
  mType := nil;
  for mIndex := 0 to ADecl.ChildCount - 1 do
  begin
    if not (ADecl[mIndex].Kind in [TSyntaxKind.GenericParams, TSyntaxKind.Attribute, TSyntaxKind.Error]) then
    begin
      mType := ADecl[mIndex];
      Break;
    end;
  end;
  if (mType <> nil) and (mType.Kind = TSyntaxKind.ForwardType) then
  begin
    // Vorwärtsdeklaration (TFoo = class;): die eigentliche Deklaration folgt.
    Exit;
  end;
  mTokens := FTree.Tokens;
  if (mType <> nil) and (mType.Kind in [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.HelperType,
    TSyntaxKind.RecordType, TSyntaxKind.InterfaceType]) then
  begin
    case mType.Kind of
      TSyntaxKind.RecordType:
        mKind := TLspDocumentSymbols.cKindStruct;
      TSyntaxKind.InterfaceType:
        mKind := TLspDocumentSymbols.cKindInterface;
    else
      mKind := TLspDocumentSymbols.cKindClass;
    end;
    // Wie DelphiLSP: vom Wort class bis end.
    mSymbol := Symbol(ADecl.Name, '', mKind, mType.StartPos, TrimmedEnd(mType));
    ATarget.AddElement(mSymbol);
    AddMembers(mType, Children(mSymbol));
    Exit;
  end;
  // Wie DelphiLSP: Aufzählungen, Aliase und übrige Typen kind 23.
  mKind := TLspDocumentSymbols.cKindStruct;
  if (mType <> nil) and (mType.Kind = TSyntaxKind.EnumType) then
  begin
    mKind := TLspDocumentSymbols.cKindEnum;
  end;
  mToken := NameToken(ADecl.StartOffset, ADecl.EndOffset, ADecl.Name);
  if mToken >= 0 then
  begin
    ATarget.AddElement(Symbol(ADecl.Name, '', mKind, mTokens[mToken].StartPos, TrimmedEnd(ADecl)));
  end
  else
  begin
    ATarget.AddElement(Symbol(ADecl.Name, '', mKind, ADecl.StartPos, TrimmedEnd(ADecl)));
  end;
end;

procedure TSymbolBuilder.AddMembers(AType: TSyntaxNode; ATarget: TJSONArray);
var
  mIndex, mInner: Integer;
  mChild, mSection: TSyntaxNode;
begin
  for mIndex := 0 to AType.ChildCount - 1 do
  begin
    mChild := AType[mIndex];
    case mChild.Kind of
      TSyntaxKind.Field:
        AddNamed(mChild, TLspDocumentSymbols.cKindField, TypeTextOf(mChild), '', ATarget);
      TSyntaxKind.PropertyDecl:
        AddNamed(mChild, TLspDocumentSymbols.cKindProperty, NodeText(mChild.FindChild(TSyntaxKind.TypeReference)),
          PropertyAccess(mChild), ATarget);
      TSyntaxKind.RoutineHeader:
        AddRoutine(mChild, mChild, False, ATarget);
      TSyntaxKind.VarSection:
        for mInner := 0 to mChild.ChildCount - 1 do
        begin
          if mChild[mInner].Kind = TSyntaxKind.VarDecl then
          begin
            AddNamed(mChild[mInner], TLspDocumentSymbols.cKindField, TypeTextOf(mChild[mInner]), '', ATarget);
          end;
        end;
      TSyntaxKind.ConstSection:
        for mInner := 0 to mChild.ChildCount - 1 do
        begin
          if mChild[mInner].Kind = TSyntaxKind.ConstDecl then
          begin
            AddNamed(mChild[mInner], TLspDocumentSymbols.cKindConstant, '', '', ATarget);
          end;
        end;
      TSyntaxKind.TypeSection:
        begin
          mSection := mChild;
          for mInner := 0 to mSection.ChildCount - 1 do
          begin
            if mSection[mInner].Kind = TSyntaxKind.TypeDecl then
            begin
              AddType(mSection[mInner], ATarget);
            end;
          end;
        end;
    else
      // Sichtbarkeit, Attribute, variante Teile und Fehlerknoten: kein eigener Eintrag.
    end;
  end;
end;

procedure TSymbolBuilder.AddDeclarations(ANode: TSyntaxNode; AImplementation: Boolean; ATarget: TJSONArray);
var
  mIndex, mInner: Integer;
  mChild, mHeader: TSyntaxNode;
begin
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    mChild := ANode[mIndex];
    case mChild.Kind of
      TSyntaxKind.UsesClause:
        begin
          // Wie DelphiLSP vorn im interface- bzw. implementation-Abschnitt; contains/requires der Packages nicht.
          if (ANode.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection]) and
            SameText(mChild.Name, 'uses') then
          begin
            AddUses(mChild, ATarget);
          end;
        end;
      TSyntaxKind.TypeSection:
        for mInner := 0 to mChild.ChildCount - 1 do
        begin
          if mChild[mInner].Kind = TSyntaxKind.TypeDecl then
          begin
            AddType(mChild[mInner], ATarget);
          end;
        end;
      TSyntaxKind.VarSection:
        for mInner := 0 to mChild.ChildCount - 1 do
        begin
          if mChild[mInner].Kind = TSyntaxKind.VarDecl then
          begin
            AddNamed(mChild[mInner], TLspDocumentSymbols.cKindVariable, TypeTextOf(mChild[mInner]), '', ATarget);
          end;
        end;
      TSyntaxKind.ConstSection:
        for mInner := 0 to mChild.ChildCount - 1 do
        begin
          if mChild[mInner].Kind = TSyntaxKind.ConstDecl then
          begin
            AddNamed(mChild[mInner], TLspDocumentSymbols.cKindConstant, '', '', ATarget);
          end;
        end;
      TSyntaxKind.RoutineDecl:
        begin
          mHeader := mChild.FindChild(TSyntaxKind.RoutineHeader);
          if mHeader <> nil then
          begin
            AddRoutine(mChild, mHeader, AImplementation, ATarget);
          end;
        end;
    else
      // uses der Programme, Attribute, Rumpf des Programms und Fehlerknoten: kein eigener Eintrag.
    end;
  end;
end;

function TSymbolBuilder.Build: TJSONArray;
var
  mIndex: Integer;
  mRoot, mChild: TSyntaxNode;
  mSection: TJSONObject;
  mTokens: TArray<TPascalToken>;
  mStart, mEnd, mFinal: TTextPosition;
  mToken: Integer;
begin
  Result := TJSONArray.Create;
  try
    mRoot := FTree.Root;
    if mRoot = nil then
    begin
      Exit;
    end;
    mTokens := FTree.Tokens;
    for mIndex := 0 to mRoot.ChildCount - 1 do
    begin
      mChild := mRoot[mIndex];
      if mChild.Kind in [TSyntaxKind.InterfaceSection, TSyntaxKind.ImplementationSection] then
      begin
        mStart := mChild.StartPos;
        mToken := FTree.FirstTokenFrom(mChild.StartOffset);
        if mToken < Length(mTokens) then
        begin
          mStart := mTokens[mToken].StartPos;
        end;
        if mChild.Kind = TSyntaxKind.InterfaceSection then
        begin
          mSection := Symbol('interface', 'section', TLspDocumentSymbols.cKindNamespace, mStart, TrimmedEnd(mChild));
        end
        else
        begin
          // Wie DelphiLSP bis "end." am Ende der Unit, wenn kein initialization-Teil folgt.
          mEnd := TrimmedEnd(mChild);
          if (mIndex = mRoot.ChildCount - 1) or not (mRoot[mIndex + 1].Kind in [TSyntaxKind.InitializationSection,
            TSyntaxKind.FinalizationSection]) then
          begin
            if FinalEnd(mFinal) then
            begin
              mEnd := mFinal;
            end;
          end;
          mSection := Symbol('implementation', 'section', TLspDocumentSymbols.cKindNamespace, mStart, mEnd);
        end;
        Result.AddElement(mSection);
        AddDeclarations(mChild, mChild.Kind = TSyntaxKind.ImplementationSection, Children(mSection));
      end
      else if mRoot.Kind <> TSyntaxKind.UnitFile then
      begin
        // Programm, Library, Package: Deklarationen ohne Abschnitt, Routinen mit Rumpf.
        AddDeclarations(mRoot, True, Result);
        Break;
      end;
    end;
  except
    // Ein unvollständiger Baum darf die Strukturansicht nicht verhindern: was bis dahin da ist.
    on Exception do
      ;
  end;
end;

{ TLspDocumentSymbols }

constructor TLspDocumentSymbols.Create(const ADocuments: IDocumentStore);
begin
  inherited Create;
  FDocuments := ADocuments;
end;

procedure TLspDocumentSymbols.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod,
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      ACancellation.ThrowIfCancellationRequested;
      Result := Handle(AParams);
    end);
end;

class function TLspDocumentSymbols.Build(ATree: TSyntaxTree; const AText: string): TJSONArray;
var
  mBuilder: TSymbolBuilder;
begin
  mBuilder := TSymbolBuilder.Create(ATree, AText);
  try
    Result := mBuilder.Build;
  finally
    mBuilder.Free;
  end;
end;

function TLspDocumentSymbols.Handle(const AParams: TJSONValue): TJSONValue;
var
  mUri: string;
  mDocument: ITextDocument;
  mShared: ISharedSyntaxTree;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) and
    FDocuments.TryGet(mUri, mDocument)) then
  begin
    Exit(TJSONArray.Create);
  end;
  try
    mShared := TSyntaxTreeCache.Get(mDocument);
    Result := Build(mShared.Tree, mDocument.Text);
  except
    // Nie ein Fehler an die IDE: leere Strukturansicht.
    on Exception do
      Result := TJSONArray.Create;
  end;
end;

end.
