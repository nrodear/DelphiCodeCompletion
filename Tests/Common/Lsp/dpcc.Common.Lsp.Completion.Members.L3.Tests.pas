unit dpcc.Common.Lsp.Completion.Members.L3.Tests;

// Auflösung im Editor (L3): Mitglieder nach Ausdrücken (Liste[i]., (X as T)., P^., Literale), Elementtyp der
// for-in-Variablen, Typen von Inline-Variablen aus Operatoren, @, ^ und anonymen Methoden, Arrays und Zeiger als
// Typ, verschachtelte Typen als Typ eines Mitglieds, generische Routinen ohne Typargumente und nach einem
// Typnamen nur die Klassenmitglieder.

interface

uses
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Lsp.Completion;

type
  [TestFixture]
  TCompletionMembersL3Tests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    /// <summary>Namen der Vorschläge hinter ACode, das im Rumpf von TForm.Tu steht; durch Leerzeichen getrennt
    /// und umschlossen.</summary>
    function MembersAfter(const ACode: string): string;
    /// <summary>Prüft, dass hinter ACode alle Namen aus AWanted (durch Leerzeichen getrennt) stehen und keiner aus
    /// AUnwanted.</summary>
    procedure Check(const ACode, AWanted, AUnwanted: string);
    /// <summary>Typname der Inline-Variablen AName, die ACode deklariert; '' ohne Typ.</summary>
    function InlineType(const ACode, AName: string): string;
  public
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Punkt 1: Liste[i]., Items[0]. und Felder nach ].</summary>
    [Test]
    procedure MembersAfterIndex;
    /// <summary>Punkt 1: (Sender as TKnopf). und TKnopf(Sender).</summary>
    [Test]
    procedure MembersAfterParenthesisAndCast;
    /// <summary>Punkt 1 und 5: P^. und P. bei einem Zeiger auf einen Record.</summary>
    [Test]
    procedure MembersAfterDereference;
    /// <summary>Punkt 1: 'abc'. und 42. über die Helfer der eingebauten Typen.</summary>
    [Test]
    procedure MembersOfLiterals;
    /// <summary>Punkt 1: Aufruf über eine Prozedurtyp-Variable vor dem Punkt (M(1)., Rr().).</summary>
    [Test]
    procedure MembersAfterProceduralCall;
    /// <summary>Punkt 3: for var E in Liste do E.</summary>
    [Test]
    procedure ForInVariableHasElementType;
    /// <summary>Punkt 4: var S := A + IntToStr(1); var Q := R + R (class operator); @, ^.</summary>
    [Test]
    procedure InlineVarFromOperators;
    /// <summary>Punkt 4: Ergebnistypen nach Delphi-Regeln (string, Integer, Extended, Boolean, Zeiger).</summary>
    [Test]
    procedure InlineVarTypesFollowDelphiRules;
    /// <summary>Punkt 4: anonyme Methode als Initialisierung, Aufruf danach.</summary>
    [Test]
    procedure InlineVarFromAnonymousMethod;
    /// <summary>Punkt 5: array of T, statische Arrays, anonyme Array-Felder, lokale Arrays.</summary>
    [Test]
    procedure ArrayTypesGiveElements;
    /// <summary>Punkt 6: W.Werte., L.GetEnumerator., Feld mit verschachteltem Typ.</summary>
    [Test]
    procedure NestedTypesOfMembers;
    /// <summary>Punkt 9: Gleich(K). bindet T an den Typ des Arguments.</summary>
    [Test]
    procedure GenericRoutineInfersTypeArgument;
    /// <summary>Punkt 11: TKnopf. nur Klassenmitglieder, TPunkt. nur statische, Self. und K. alle.</summary>
    [Test]
    procedure TypeNameOffersClassMembersOnly;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Pascal.Parser,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.Extractor,
  dpcc.Common.Lsp.CompletionRequest,
  dpcc.Common.Lsp.Completion.Lists,
  dpcc.Common.Lsp.Completion.TestSupport;

const
  cHauptFile = 'C:\P\Haupt.pas';

  UnitSystemL3 =
    'unit System;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TObject = class'#10 +
    '    procedure Free;'#10 +
    '  end;'#10 +
    '  TArray<T> = array of T;'#10 +
    '  TStringHelper = record helper for string'#10 +
    '    function Laenge: Integer;'#10 +
    '    function Gross: string;'#10 +
    '  end;'#10 +
    '  TIntegerHelper = record helper for Integer'#10 +
    '    function ToHex: string;'#10 +
    '  end;'#10 +
    '  TBooleanHelper = record helper for Boolean'#10 +
    '    function AlsText: string;'#10 +
    '  end;'#10 +
    '  TExtendedHelper = record helper for Extended'#10 +
    '    function Runde: Integer;'#10 +
    '  end;'#10 +
    '  TCharHelper = record helper for Char'#10 +
    '    function IstZiffer: Boolean;'#10 +
    '  end;'#10 +
    'function IntToStr(A: Integer): string;'#10 +
    'implementation'#10 +
    'end.';

  UnitDaten =
    'unit Daten;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TArt = (Klein, Gross);'#10 +
    '  TPunkt = record'#10 +
    '    X, Y: Integer;'#10 +
    '    class function Null: TPunkt; static;'#10 +
    '    function Laenge: Double;'#10 +
    '    class operator Add(const A, B: TPunkt): TPunkt;'#10 +
    '  end;'#10 +
    '  PPunkt = ^TPunkt;'#10 +
    '  TKnopf = class'#10 +
    '  public'#10 +
    '    type'#10 +
    '      TInnen = class'#10 +
    '        Tiefe: Integer;'#10 +
    '      end;'#10 +
    '    const cMax = 10;'#10 +
    '    class var Anzahl: Integer;'#10 +
    '  public'#10 +
    '    Caption: string;'#10 +
    '    Innen: TInnen;'#10 +
    '    constructor Create;'#10 +
    '    procedure Klick;'#10 +
    '    class function Standard: TKnopf;'#10 +
    '  end;'#10 +
    '  TKnopfListe = array of TKnopf;'#10 +
    '  TKnopfFeld = array[0..9] of TKnopf;'#10 +
    '  PKnopfFeld = ^TKnopfFeld;'#10 +
    '  TListe<T> = class'#10 +
    '  public'#10 +
    '    type'#10 +
    '      TAufzaehler = class'#10 +
    '        FAktuell: T;'#10 +
    '        function MoveNext: Boolean;'#10 +
    '        property Current: T read FAktuell;'#10 +
    '      end;'#10 +
    '    function GetEnumerator: TAufzaehler;'#10 +
    '    function Erstes: T;'#10 +
    '    function GetItem(Index: Integer): T;'#10 +
    '    property Items[Index: Integer]: T read GetItem; default;'#10 +
    '  end;'#10 +
    '  TWoerterbuch<K, V> = class'#10 +
    '  public'#10 +
    '    type'#10 +
    '      TWerte = class'#10 +
    '        function Zahl: Integer;'#10 +
    '        function Liste: TArray<V>;'#10 +
    '      end;'#10 +
    '    function GetWerte: TWerte;'#10 +
    '    property Werte: TWerte read GetWerte;'#10 +
    '  end;'#10 +
    '  TMeldung = function(A: Integer): TKnopf of object;'#10 +
    '  TRueckruf = reference to function: TPunkt;'#10 +
    'function Gleich<T>(const A: T): T;'#10 +
    'implementation'#10 +
    'end.';

  UnitHauptL3 =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Daten;'#10 +
    'type'#10 +
    '  TForm = class'#10 +
    '    FArr: array of TKnopf;'#10 +
    '    FFeld: array[0..2] of TPunkt;'#10 +
    '    FListe: TKnopfListe;'#10 +
    '    procedure Tu(Sender: TObject);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TForm.Tu(Sender: TObject);'#10 +
    'var'#10 +
    '  L: TListe<TKnopf>;'#10 +
    '  P: PPunkt;'#10 +
    '  R: TPunkt;'#10 +
    '  K: TKnopf;'#10 +
    '  F: TKnopfFeld;'#10 +
    '  W: TWoerterbuch<string, TKnopf>;'#10 +
    '  Lok: array of TKnopf;'#10 +
    '  M: TMeldung;'#10 +
    '  Rr: TRueckruf;'#10 +
    '  S: string;'#10 +
    '  PF: PKnopfFeld;'#10 +
    '  B: Boolean;'#10 +
    '  I: Integer;'#10 +
    'begin'#10 +
    '  {CODE}'#10 +
    'end;'#10 +
    'end.';

procedure TCompletionMembersL3Tests.WarmUp;
begin
  // Erste Nutzung (Texttabellen, Klassenregister) außerhalb der Lecktests.
  Setup;
  try
    MembersAfter('K.');
    InlineType('var Z := 1;', 'Z');
  finally
    TearDown;
  end;
end;

procedure TCompletionMembersL3Tests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitSystemL3, 'C:\Lib\System.pas', nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitDaten, 'C:\P\Daten.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TCompletionMembersL3Tests.TearDown;
begin
  FreeAndNil(FResolver);
  FIndex := nil;
end;

function TCompletionMembersL3Tests.MembersAfter(const ACode: string): string;
var
  mText: string;
  mTree: TSyntaxTree;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mText := StringReplace(UnitHauptL3, '{CODE}', ACode, []);
  mTree := TPascalParser.Parse(mText);
  try
    mItems := TCompletionLists.Collect(FResolver, FIndex, mTree, cHauptFile, PositionOf(mText, '  ' + ACode),
      TCompletionMatching.Prefix);
  finally
    mTree.Free;
  end;
  Result := ' ';
  for mItem in mItems.Items do
  begin
    Result := Result + mItem.Name + ' ';
  end;
end;

procedure TCompletionMembersL3Tests.Check(const ACode, AWanted, AUnwanted: string);
var
  mNames, mName: string;
begin
  mNames := MembersAfter(ACode);
  for mName in AWanted.Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    Assert.IsTrue(Pos(' ' + mName + ' ', mNames) > 0, Format('%s fehlt nach "%s": [%s]', [mName, ACode, mNames]));
  end;
  for mName in AUnwanted.Split([' '], TStringSplitOptions.ExcludeEmpty) do
  begin
    Assert.IsFalse(Pos(' ' + mName + ' ', mNames) > 0, Format('%s unerwartet nach "%s": [%s]',
      [mName, ACode, mNames]));
  end;
end;

function TCompletionMembersL3Tests.InlineType(const ACode, AName: string): string;
var
  mText: string;
  mTree: TSyntaxTree;
  mSymbol, mType: TResolvedSymbol;
begin
  mText := StringReplace(UnitHauptL3, '{CODE}', ACode + ' Zeige(' + AName + ');', []);
  mTree := TPascalParser.Parse(mText);
  try
    // Der Name hinter der Deklaration ("Zeige(Z)"), dort ist die Inline-Variable bekannt.
    mSymbol := FResolver.Resolve(mTree, cHauptFile, PositionOf(mText, 'Zeige('));
    if mSymbol.Found and FResolver.TypeOf(mSymbol, mType) then
    begin
      Result := mType.Name;
    end
    else
    begin
      Result := '';
    end;
  finally
    mTree.Free;
  end;
end;

procedure TCompletionMembersL3Tests.MembersAfterIndex;
begin
  Check('L[0].', 'Caption Klick', '');
  Check('L.Items[0].', 'Caption Klick', '');
  Check('L.Erstes.', 'Caption Klick', '');
  Check('L[0].Innen.', 'Tiefe', 'Caption');
end;

procedure TCompletionMembersL3Tests.MembersAfterParenthesisAndCast;
begin
  Check('(Sender as TKnopf).', 'Caption Klick', '');
  Check('TKnopf(Sender).', 'Caption Klick', '');
  Check('(K).', 'Caption Klick', '');
end;

procedure TCompletionMembersL3Tests.MembersAfterDereference;
begin
  Check('P^.', 'X Y Laenge', '');
  Check('P.', 'X Y Laenge', '');
end;

procedure TCompletionMembersL3Tests.MembersOfLiterals;
begin
  Check('''abc''.', 'Laenge Gross', '');
  Check('42.', 'ToHex', 'Laenge');
end;

procedure TCompletionMembersL3Tests.MembersAfterProceduralCall;
begin
  Check('M(1).', 'Caption Klick', '');
  Check('Rr().', 'X Y', '');
end;

procedure TCompletionMembersL3Tests.ForInVariableHasElementType;
begin
  Check('for var E in L do E.', 'Caption Klick', '');
  Check('for var E in Lok do E.', 'Caption Klick', '');
  Check('for var E in FListe do E.', 'Caption Klick', '');
  Check('for var E in F do E.', 'Caption Klick', '');
  Check('for var E in S do E.', 'IstZiffer', 'Laenge');
end;

procedure TCompletionMembersL3Tests.InlineVarFromOperators;
begin
  Check('var T := S + IntToStr(1); T.', 'Laenge Gross', '');
  Check('var Q := R + R; Q.', 'X Y Laenge', '');
  Check('var Z := @R; Z^.', 'X Y', '');
  Check('var V := P^; V.', 'X Y', '');
end;

procedure TCompletionMembersL3Tests.InlineVarTypesFollowDelphiRules;
begin
  Assert.AreEqual('string', InlineType('var Z := S + ''x'';', 'Z'));
  Assert.AreEqual('string', InlineType('var Z := ''a'' + ''b'';', 'Z'));
  Assert.AreEqual('Integer', InlineType('var Z := I * 2 + 1;', 'Z'));
  Assert.AreEqual('Integer', InlineType('var Z := I div 2;', 'Z'));
  Assert.AreEqual('Extended', InlineType('var Z := I / 2;', 'Z'));
  Assert.AreEqual('Boolean', InlineType('var Z := I > 2;', 'Z'));
  Assert.AreEqual('Boolean', InlineType('var Z := not B;', 'Z'));
  Assert.AreEqual('Boolean', InlineType('var Z := B and (I = 1);', 'Z'));
  Assert.AreEqual('Integer', InlineType('var Z := -I;', 'Z'));
  Assert.AreEqual('TPunkt', InlineType('var Z := P^;', 'Z'));
  Assert.AreEqual('TPunkt', InlineType('var Z := R + R;', 'Z'));
end;

procedure TCompletionMembersL3Tests.InlineVarFromAnonymousMethod;
begin
  Check('var Fn := function(A: Integer): TKnopf begin Result := nil; end; Fn(1).', 'Caption Klick', '');
end;

procedure TCompletionMembersL3Tests.ArrayTypesGiveElements;
begin
  Check('FArr[0].', 'Caption Klick', '');
  Check('FFeld[1].', 'X Y', '');
  Check('FListe[0].', 'Caption Klick', '');
  Check('F[1].', 'Caption Klick', '');
  Check('Lok[0].', 'Caption Klick', '');
  // Zeiger auf ein Array: PF[1] ist PF^[1].
  Check('PF[1].', 'Caption Klick', '');
  Check('PF^[1].', 'Caption Klick', '');
end;

procedure TCompletionMembersL3Tests.NestedTypesOfMembers;
begin
  Check('W.Werte.', 'Zahl Liste', '');
  Check('L.GetEnumerator.', 'MoveNext Current', '');
  Check('L.GetEnumerator.Current.', 'Caption Klick', '');
  Check('K.Innen.', 'Tiefe', 'Caption');
end;

procedure TCompletionMembersL3Tests.GenericRoutineInfersTypeArgument;
begin
  Check('Gleich(K).', 'Caption Klick', '');
  Check('Gleich(R).', 'X Y', '');
end;

procedure TCompletionMembersL3Tests.TypeNameOffersClassMembersOnly;
begin
  Check('TKnopf.', 'Create Standard Anzahl cMax TInnen', 'Caption Klick Innen');
  Check('TPunkt.', 'Null', 'X Y Laenge Add');
  Check('Self.', 'FArr Tu', '');
  Check('K.', 'Caption Klick Standard', '');
  Check('TKnopf.Create.', 'Caption Klick', '');
  Check('TListe<TKnopf>.', 'TAufzaehler', 'Erstes GetItem');
  Check('L.GetEnumerator.Current.Innen.', 'Tiefe', '');
end;

end.
