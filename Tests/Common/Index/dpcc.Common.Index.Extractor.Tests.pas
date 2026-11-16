unit dpcc.Common.Index.Extractor.Tests;

// Extractor-Tests aus dem früheren Testprojekt (_deleteMe\Tests\Common\Index, Index-Inhalte L1 zurückgeholt):
// Typen, Mitglieder, Vorfahren, Vorwärtsdeklarationen, uses-Listen, interface-Merker, Zweige der bedingten
// Kompilierung und Programme. An den heutigen Stand angepasst (Namensraum dpcc).

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract;

type
  [TestFixture]
  TIndexExtractorTests = class
  public
    [Test]
    procedure ExtractsTypesMembersAndRoutines;
    [Test]
    procedure ExtractsAncestors;
    /// <summary>Typargumente stehen je Vorfahr im Index und überstehen den Cache.</summary>
    [Test]
    procedure ExtractsAncestorArgsOfEveryAncestor;
    [Test]
    procedure ForwardDeclarationGivesWayToFullType;
    [Test]
    procedure ExtractsUsesLists;
    [Test]
    procedure MarksInterfaceSymbols;
    [Test]
    procedure SkipsInactiveBranches;
    [Test]
    procedure ExtractsProgramDeclarations;
    [Test]
    procedure RecordsConditionsAndUnavailableDeclarations;
    /// <summary>Mitglieder in bedingten Teilen eines Klassenrumpfs (#476).</summary>
    [Test]
    procedure RecordsConditionsOfMembers;
    /// <summary>string[N] behält die Länge in der Signatur, der Typname bleibt string (#1036).</summary>
    [Test]
    procedure KeepsShortStringLengthInSignature;
    /// <summary>Routinen nur im implementation-Teil unter einem nicht geltenden Zweig (#476).</summary>
    [Test]
    procedure RecordsUnavailableImplementationRoutines;
  end;

const
  /// <summary>Unit A der Tests (wie im früheren Builder-Test).</summary>
  UnitA =
    'unit A;'#10 +
    'interface'#10 +
    'uses System.SysUtils, B;'#10 +
    'type'#10 +
    '  TBase = class'#10 +
    '  end;'#10 +
    '  TFoo = class(TBase, IInterface)'#10 +
    '  private'#10 +
    '    FValue: Integer;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    procedure Run;'#10 +
    '    property Value: Integer read FValue;'#10 +
    '  end;'#10 +
    '  TFarbe = (Rot, Gruen);'#10 +
    'const'#10 +
    '  Max = 10;'#10 +
    'var'#10 +
    '  Global: Integer;'#10 +
    'procedure Hilfe;'#10 +
    'implementation'#10 +
    'uses C;'#10 +
    'procedure Hilfe; begin end;'#10 +
    'constructor TFoo.Create; begin end;'#10 +
    'procedure TFoo.Run; begin end;'#10 +
    'end.';

implementation

uses
  dpcc.Common.Index.Extractor,
  dpcc.Common.Index.Cache;

function Extract(const AText: string; const ADefines: TArray<string> = nil): TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(AText, 'C:\Projekt\A.pas', ADefines);
end;

function FindSymbol(const AUnit: TUnitIndex; const AQualifiedName: string; out ASymbol: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
  begin
    if SameText(Symbol.QualifiedName, AQualifiedName) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

function Count(const AUnit: TUnitIndex; const AQualifiedName: string): Integer;
var
  Symbol: TIndexSymbol;
begin
  Result := 0;
  for Symbol in AUnit.Symbols do
  begin
    if SameText(Symbol.QualifiedName, AQualifiedName) then
    begin
      Inc(Result);
    end;
  end;
end;

{ TIndexExtractorTests }

procedure TIndexExtractorTests.ExtractsTypesMembersAndRoutines;
var
  U: TUnitIndex;
  S: TIndexSymbol;
begin
  U := Extract(UnitA);
  Assert.AreEqual('A', U.UnitName);
  Assert.IsTrue(FindSymbol(U, 'TFoo', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.ClassType);
  Assert.AreEqual(6, S.SelectionRange.StartPos.Line);
  Assert.AreEqual(2, S.SelectionRange.StartPos.Character);
  Assert.IsTrue(FindSymbol(U, 'TFoo.FValue', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.Field);
  Assert.IsTrue(FindSymbol(U, 'TFoo.Value', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.Property_);
  Assert.IsTrue(FindSymbol(U, 'TFoo.Create', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.Constructor_);
  // Deklaration im interface und Rumpf in implementation
  Assert.AreEqual(2, Count(U, 'TFoo.Run'));
  Assert.IsTrue(FindSymbol(U, 'TFarbe.Gruen', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.EnumMember);
  Assert.IsTrue(FindSymbol(U, 'Max', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.Constant);
  Assert.IsTrue(FindSymbol(U, 'Global', S));
  Assert.IsTrue(S.Kind = TIndexSymbolKind.Variable);
  Assert.AreEqual(2, Count(U, 'Hilfe'));
end;

procedure TIndexExtractorTests.ExtractsAncestors;
var
  U: TUnitIndex;
  S: TIndexSymbol;
begin
  U := Extract(UnitA);
  Assert.IsTrue(FindSymbol(U, 'TFoo', S));
  Assert.AreEqual<NativeInt>(2, Length(S.Ancestors));
  Assert.AreEqual('TBase', S.Ancestors[0]);
  Assert.AreEqual('IInterface', S.Ancestors[1]);
  Assert.IsTrue(FindSymbol(U, 'TBase', S));
  Assert.AreEqual<NativeInt>(0, Length(S.Ancestors));
end;

procedure TIndexExtractorTests.ExtractsAncestorArgsOfEveryAncestor;
const
  Text = 'unit G;'#10'interface'#10'type'#10 +
    '  TVergleich = class(TInterfacedObject, IComparer<TKunde>, IMap<string, TArray<Integer>>)'#10'  end;'#10 +
    '  TListe = class(TObjectList<TKunde>)'#10'  end;'#10 +
    '  TEinfach = class(TObject, IInterface)'#10'  end;'#10 +
    'implementation'#10'end.';
var
  U: TUnitIndex;
  Loaded: TArray<TUnitIndex>;
  S: TIndexSymbol;
begin
  U := Extract(Text);
  Assert.IsTrue(FindSymbol(U, 'TVergleich', S));
  Assert.AreEqual<NativeInt>(3, Length(S.AncestorArgs));
  Assert.AreEqual('', S.AncestorArgs[0]);
  Assert.AreEqual('TKunde', S.AncestorArgs[1]);
  Assert.AreEqual('string,TArray<Integer>', StringReplace(S.AncestorArgs[2], ' ', '', [rfReplaceAll]));
  Assert.IsTrue(FindSymbol(U, 'TListe', S));
  Assert.AreEqual<NativeInt>(1, Length(S.AncestorArgs));
  Assert.AreEqual('TKunde', S.AncestorArgs[0]);
  // Ohne Typargumente bleibt die Liste leer.
  Assert.IsTrue(FindSymbol(U, 'TEinfach', S));
  Assert.AreEqual<NativeInt>(0, Length(S.AncestorArgs));
  Loaded := TIndexCache.Deserialize(TIndexCache.Serialize([U]));
  Assert.IsTrue(FindSymbol(Loaded[0], 'TVergleich', S));
  Assert.AreEqual<NativeInt>(3, Length(S.AncestorArgs));
  Assert.AreEqual('TKunde', S.AncestorArgs[1]);
end;

procedure TIndexExtractorTests.ForwardDeclarationGivesWayToFullType;
var
  U: TUnitIndex;
  S: TIndexSymbol;
begin
  // Wie Data.DB: TDataSource = class; weit oben, die volle Deklaration später.
  U := Extract('unit D;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TDataSource = class;'#10 +
    '  TNurVorwaerts = class;'#10 +
    '  IFeld = interface;'#10 +
    '  TComponent = class end;'#10 +
    '  IFeld = interface end;'#10 +
    '  TDataSource = class(TComponent)'#10 +
    '  type'#10 +
    '    TInnen = class;'#10 +
    '    TInnen = class(TComponent) end;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.');
  Assert.AreEqual(1, Count(U, 'TDataSource'));
  Assert.IsTrue(FindSymbol(U, 'TDataSource', S));
  Assert.AreEqual(8, S.SelectionRange.StartPos.Line);
  Assert.AreEqual<NativeInt>(1, Length(S.Ancestors));
  Assert.AreEqual('TComponent', S.Ancestors[0]);
  Assert.AreEqual(1, Count(U, 'IFeld'));
  Assert.AreEqual(1, Count(U, 'TDataSource.TInnen'));
  Assert.IsTrue(FindSymbol(U, 'TDataSource.TInnen', S));
  Assert.AreEqual(11, S.SelectionRange.StartPos.Line);
  // Ohne volle Deklaration bleibt die Vorwärtsdeklaration stehen.
  Assert.AreEqual(1, Count(U, 'TNurVorwaerts'));
end;

procedure TIndexExtractorTests.ExtractsUsesLists;
var
  U: TUnitIndex;
begin
  U := Extract(UnitA);
  Assert.AreEqual<NativeInt>(2, Length(U.InterfaceUses));
  Assert.AreEqual('System.SysUtils', U.InterfaceUses[0]);
  Assert.AreEqual('B', U.InterfaceUses[1]);
  Assert.AreEqual<NativeInt>(1, Length(U.ImplementationUses));
  Assert.AreEqual('C', U.ImplementationUses[0]);
end;

procedure TIndexExtractorTests.MarksInterfaceSymbols;
var
  U: TUnitIndex;
  S: TIndexSymbol;
  Seen: Boolean;
begin
  U := Extract(UnitA);
  Assert.IsTrue(FindSymbol(U, 'TFoo', S));
  Assert.IsTrue(S.InInterface);
  Seen := False;
  for S in U.Symbols do
  begin
    if (S.QualifiedName = 'TFoo.Run') and not S.InInterface then
    begin
      Seen := True;
    end;
  end;
  Assert.IsTrue(Seen, 'Rumpf in implementation');
end;

procedure TIndexExtractorTests.SkipsInactiveBranches;
const
  Source =
    'unit D;'#13#10 +
    'interface'#13#10 +
    '{$IFDEF MSWINDOWS}'#13#10 +
    'procedure NurWindows;'#13#10 +
    '{$ELSE}'#13#10 +
    'procedure NurAndere;'#13#10 +
    '{$ENDIF}'#13#10 +
    'implementation'#13#10 +
    'end.';
var
  U: TUnitIndex;
  S: TIndexSymbol;
begin
  U := Extract(Source, ['MSWINDOWS']);
  Assert.IsTrue(FindSymbol(U, 'NurWindows', S));
  Assert.AreEqual(3, S.SelectionRange.StartPos.Line);
  Assert.IsFalse(FindSymbol(U, 'NurAndere', S));
  U := Extract(Source, []);
  Assert.IsFalse(FindSymbol(U, 'NurWindows', S));
  Assert.IsTrue(FindSymbol(U, 'NurAndere', S));
  Assert.AreEqual(5, S.SelectionRange.StartPos.Line);
end;

procedure TIndexExtractorTests.RecordsConditionsAndUnavailableDeclarations;
const
  Source =
    'unit Plattform;'#10 +
    'interface'#10 +
    'type'#10 +
    '{$IFDEF WIN64}'#10 +
    '  TNur64 = class end;'#10 +
    '{$ELSE}'#10 +
    '  TNur32 = class end;'#10 +
    '{$ENDIF}'#10 +
    '  TImmer = record end;'#10 +
    '{$IFDEF MSWINDOWS}'#10 +
    'procedure NurWindows;'#10 +
    '{$ENDIF}'#10 +
    'procedure Alt; platform;'#10 +
    'implementation'#10 +
    'procedure NurWindows; begin end;'#10 +
    'procedure Alt; begin end;'#10 +
    'end.';
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
  Conditions, Missing: string;
begin
  U := TIndexExtractor.ExtractText(Source, 'C:\P\Plattform.pas', ['WIN32', 'MSWINDOWS']);
  Conditions := '';
  for Symbol in U.Symbols do
  begin
    if Symbol.Container = '' then
    begin
      Conditions := Conditions + Symbol.Name + '=' + Symbol.Condition + ';';
    end;
  end;
  Assert.Contains(Conditions, 'TNur32=not WIN64;');
  Assert.Contains(Conditions, 'TImmer=;');
  Assert.Contains(Conditions, 'NurWindows=MSWINDOWS;');
  Assert.Contains(Conditions, 'Alt=platform;');
  Assert.DoesNotContain(Conditions, 'TNur64');
  Missing := '';
  for Symbol in U.Unavailable do
  begin
    Missing := Missing + Symbol.Name + '=' + Symbol.Condition + ';';
  end;
  Assert.AreEqual('TNur64=WIN64;', Missing);
  Assert.IsTrue(U.Unavailable[0].InInterface);
  Assert.IsTrue(U.Unavailable[0].Kind = TIndexSymbolKind.ClassType);
end;

procedure TIndexExtractorTests.KeepsShortStringLengthInSignature;
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
  Found: string;
begin
  U := TIndexExtractor.ExtractText('unit Satz;'#10'interface'#10'const'#10'  Laenge = 4;'#10'type'#10 +
    '  TSatz = record'#10'    Kennung: string[8];'#10'    Kurz: string[Laenge];'#10'    Name: string;'#10 +
    '    Liste: TList<string>;'#10'  end;'#10'var'#10'  Global: string [ 5 ];'#10'implementation'#10'end.',
    'Satz.pas', nil);
  Found := '';
  for Symbol in U.Symbols do
  begin
    if Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Variable] then
    begin
      Found := Found + Symbol.Signature + '|' + Symbol.TypeName + #10;
    end;
  end;
  Assert.AreEqual('Kennung: string[8]|string'#10'Kurz: string[Laenge]|string'#10'Name: string|string'#10 +
    'Liste: TList<string>|TList'#10'Global: string[5]|string'#10, Found);
end;

procedure TIndexExtractorTests.RecordsConditionsOfMembers;
const
  Source =
    'unit Mitglieder;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TGeraet = class'#10 +
    '  public'#10 +
    '{$IFDEF WIN64}'#10 +
    '    FHandle64, FExtra: Int64;'#10 +
    '    procedure Nur64;'#10 +
    '    property Groesse64: Int64 read FHandle64;'#10 +
    '{$ELSE}'#10 +
    '    FHandle32: Integer;'#10 +
    '    function Nur32: Integer;'#10 +
    '{$ENDIF}'#10 +
    '    procedure Immer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TGeraet.Nur32; begin end;'#10 +
    'procedure TGeraet.Immer; begin end;'#10 +
    'end.';
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
  Conditions, Missing: string;
begin
  U := TIndexExtractor.ExtractText(Source, 'C:\P\Mitglieder.pas', ['WIN32', 'MSWINDOWS']);
  Conditions := '';
  for Symbol in U.Symbols do
  begin
    if Symbol.Container = 'TGeraet' then
    begin
      Conditions := Conditions + Symbol.Name + '=' + Symbol.Condition + ';';
    end;
  end;
  Assert.Contains(Conditions, 'FHandle32=not WIN64;');
  Assert.Contains(Conditions, 'Nur32=not WIN64;');
  Assert.Contains(Conditions, 'Immer=;');
  Missing := '';
  for Symbol in U.Unavailable do
  begin
    Missing := Missing + Symbol.Container + '.' + Symbol.Name + '=' + Symbol.Condition + ';';
  end;
  Assert.AreEqual('TGeraet.FHandle64=WIN64;TGeraet.FExtra=WIN64;TGeraet.Nur64=WIN64;TGeraet.Groesse64=WIN64;',
    Missing);
  Assert.IsTrue(U.Unavailable[0].Kind = TIndexSymbolKind.Field);
  Assert.IsTrue(U.Unavailable[2].Kind = TIndexSymbolKind.Method);
  Assert.IsTrue(U.Unavailable[3].Kind = TIndexSymbolKind.Property_);
  Assert.AreEqual(15, U.Unavailable[1].SelectionRange.StartPos.Character, 'Spalte des zweiten Felds');
end;

procedure TIndexExtractorTests.RecordsUnavailableImplementationRoutines;
const
  Source =
    'unit Start;'#10 +
    'interface'#10 +
    'implementation'#10 +
    '{$IFDEF FPC}'#10 +
    'procedure ApplyAppIcon;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TFoo.Bar;'#10 +
    'begin'#10 +
    'end;'#10 +
    '{$ENDIF}'#10 +
    'procedure Immer;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
  Missing: string;
begin
  U := TIndexExtractor.ExtractText(Source, 'C:\P\Start.pas', ['WIN32', 'MSWINDOWS']);
  Missing := '';
  for Symbol in U.Unavailable do
  begin
    Missing := Missing + Symbol.Name + '=' + Symbol.Condition + ';';
  end;
  Assert.AreEqual('ApplyAppIcon=FPC;', Missing);
  Assert.IsFalse(U.Unavailable[0].InInterface);
  Assert.IsTrue(U.Unavailable[0].Kind = TIndexSymbolKind.Routine);
end;

procedure TIndexExtractorTests.ExtractsProgramDeclarations;
var
  U: TUnitIndex;
  S: TIndexSymbol;
begin
  U := TIndexExtractor.ExtractText('program P;'#10'uses A in ''A.pas'';'#10'var X: Integer;'#10'begin end.',
    'C:\Projekt\P.dpr', nil);
  Assert.AreEqual('P', U.UnitName);
  Assert.AreEqual<NativeInt>(1, Length(U.ImplementationUses));
  Assert.IsTrue(FindSymbol(U, 'X', S));
  Assert.IsFalse(S.InInterface);
end;


initialization
  TDUnitX.RegisterTestFixture(TIndexExtractorTests);

end.
