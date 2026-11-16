unit dpcc.Common.Index.Content.Tests;

// Regressionstests zu Index-Inhalte L1: was aus einer gescannten Datei im Index landet (Aufzählungswerte, Katalog,
// Generik-Arität, Rümpfe der Bibliothek, Zieltypen, Attribute, Bedingungen, Signaturen, Arten, anonyme Typen,
// Einschränkungen, .dpk, Abstände in Signaturen, Formatversion und alte Cache-Dateien).

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Lsp.Completion.TestSupport;

type
  [TestFixture]
  TIndexContentTests = class(TLspCompletionTestCase)
  public
    /// <summary>Legt die Tabelle der eigenen Sperren einmal an: Sie wächst beim ersten Sperren und zählte sonst als
    /// Leck des ersten Tests, der eine Sperre prüft.</summary>
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>1: "A = B" zählt B nicht als weiteren Wert; der Wert steht in der Signatur.</summary>
    [Test]
    procedure EnumValueIsNoExtraMember;
    /// <summary>2: Werte ohne {$SCOPEDENUMS} eines Typs der obersten Ebene stehen im Katalog, Typ als TypeName.
    /// </summary>
    [Test]
    procedure CatalogListsUnscopedEnumValues;
    /// <summary>2: "+ Unit" bietet fsBold, ssShift und rfReplaceAll an.</summary>
    [Test]
    procedure PlusUnitOffersEnumValues;
    /// <summary>3: Der Katalog kennt die Zahl der Typparameter.</summary>
    [Test]
    procedure CatalogKnowsArity;
    /// <summary>3: "+ Unit" unterscheidet TList und TList&lt;T&gt; und wählt nach dem "&lt;" dahinter.</summary>
    [Test]
    procedure PlusUnitDistinguishesGenericTypes;
    /// <summary>4: Bibliotheks-Units ohne Rümpfe, die eine interface-Deklaration wiederholen; DLL-Angaben und Zeile
    /// am interface-Symbol.</summary>
    [Test]
    procedure LibraryDropsImplementationDuplicates;
    /// <summary>5: Zieltyp und Form für Zeiger, Arrays, Mengen, class of, Prozedurtypen, Teilbereiche.</summary>
    [Test]
    procedure RecordsTargetTypes;
    /// <summary>6: Attribute als "@Name".</summary>
    [Test]
    procedure RecordsAttributes;
    /// <summary>7: Konstanten der Unit, Declared(AnsiChar) und $IFOPT mit Standardständen.</summary>
    [Test]
    procedure EvaluatesUnitConstantsAndBuiltins;
    /// <summary>7: Die Bibliothek bekommt die Standard-Schalterstände.</summary>
    [Test]
    procedure LibraryDefinesCarrySwitches;
    /// <summary>8: Gleichnamige Variante und "A, B: T" unter nicht geltenden Zweigen; Signatur aus der Quelle.
    /// </summary>
    [Test]
    procedure KeepsVariantsAndReadsTheirSignature;
    /// <summary>9: Routinen bis 1000 Zeichen, Konstanten gekürzt mit voller Signatur aus der Quelle.</summary>
    [Test]
    procedure KeepsLongRoutineSignatures;
    /// <summary>10/Format: Cache Format 35 übersteht Schreiben und Lesen samt neuer Einträge und requires.</summary>
    [Test]
    procedure CacheKeepsNewEntries;
    /// <summary>11: resourcestring, threadvar, operator, destructor, message.</summary>
    [Test]
    procedure MarksKindsWithoutOwnKind;
    /// <summary>12: Mitglieder anonymer Typen.</summary>
    [Test]
    procedure ExtractsAnonymousTypeMembers;
    /// <summary>13: Einschränkungen der Typparameter.</summary>
    [Test]
    procedure RecordsTypeParameterConstraints;
    /// <summary>14: .dpk mit requires und contains.</summary>
    [Test]
    procedure ReadsPackageClauses;
    /// <summary>15: Abstände in Signaturen wie im Quelltext.</summary>
    [Test]
    procedure FormatsSignaturesLikeSource;
    /// <summary>Format: Beim Schreiben im neuen Format fallen alte Dateien index-NN.dpccidx im Ordner weg.</summary>
    [Test]
    procedure RemovesOlderCacheFormats;
  end;

implementation

uses
  System.IOUtils,
  System.Classes,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.Preprocessor,
  dpcc.Common.Projects.Contract,
  dpcc.Common.Index.Extractor,
  dpcc.Common.Index.Cache,
  dpcc.Common.Index.Files,
  dpcc.Common.Index.ProjectFiles,
  dpcc.Common.Index.Adapters.CacheDirectory,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Lsp.CompletionRequest;

const
  cFile = 'C:\P\Inhalt.pas';

function Extract(const AText: string; const ADefines: TArray<string> = nil): TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(AText, cFile, ADefines);
end;

function Lines(const ALines: array of string): string;
begin
  Result := string.Join(#10, ALines);
end;

function Find(const AUnit: TUnitIndex; const AQualified: string): TIndexSymbol;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.QualifiedName, AQualified) then
    begin
      Exit(mSymbol);
    end;
  end;
  raise Exception.CreateFmt('%s fehlt', [AQualified]);
end;

function FindUnavailable(const AUnit: TUnitIndex; const AName: string; out ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Unavailable do
  begin
    if SameText(mSymbol.Name, AName) then
    begin
      ASymbol := mSymbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

function CountNamed(const AUnit: TUnitIndex; const AQualified: string): Integer;
var
  mSymbol: TIndexSymbol;
begin
  Result := 0;
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.QualifiedName, AQualified) then
    begin
      Inc(Result);
    end;
  end;
end;

function HasActive(const AUnit: TUnitIndex; const AName: string): Boolean;
begin
  Result := CountNamed(AUnit, AName) > 0;
end;

function Catalog(const AUnit: TUnitIndex; const AName: string; out ASymbol: TCatalogSymbol): Boolean;
var
  mSymbol: TCatalogSymbol;
begin
  for mSymbol in TCatalogUnit.FromUnit(AUnit).Symbols do
  begin
    if SameText(mSymbol.Name, AName) then
    begin
      ASymbol := mSymbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

function LibraryUnit(const AText, AFileName: string): TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(AText, AFileName, nil);
  Result.Library_ := True;
  TIndexExtractor.DropImplementationDuplicates(Result);
end;

/// <summary>Position des ersten Eintrags mit Namen AName in AItems; -1 ohne.</summary>
function ItemIndex(const AItems: TCompletionItems; const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AItems.Items) do
  begin
    if AItems.Items[mIndex].Name = AName then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TIndexContentTests }

procedure TIndexContentTests.WarmUp;
var
  mFile: string;
begin
  mFile := TPath.Combine(TPath.GetTempPath, 'dpcc-l1-warmup-' + IntToStr(TThread.GetTickCount64) + '.dpccidx');
  TFile.WriteAllText(mFile + TIndexCacheDirectory.cLockExtension, '');
  try
    TIndexCacheDirectory.IsLocked(mFile);
  finally
    TFile.Delete(mFile + TIndexCacheDirectory.cLockExtension);
  end;
end;

procedure TIndexContentTests.Setup;
begin
  Prepare;
end;

procedure TIndexContentTests.TearDown;
begin
  Release;
end;

procedure TIndexContentTests.EnumValueIsNoExtraMember;
var
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mCount: Integer;
begin
  mUnit := Extract(Lines(['unit E;', 'interface', 'type',
    '  TInc = (incLocal = 1, incSystem = incLocal + 1, incOther = incLocal, incLast);', 'implementation', 'end.']));
  mCount := 0;
  for mSymbol in mUnit.Symbols do
  begin
    Inc(mCount, Ord(mSymbol.Kind = TIndexSymbolKind.EnumMember));
  end;
  // Vorher fünf: incLocal kam als Wert von incOther ein zweites Mal hinzu.
  Assert.AreEqual(4, mCount);
  Assert.AreEqual(1, CountNamed(mUnit, 'TInc.incLocal'));
  Assert.AreEqual('incLocal = 1', Find(mUnit, 'TInc.incLocal').Signature);
  Assert.AreEqual('incSystem = incLocal + 1', Find(mUnit, 'TInc.incSystem').Signature);
  Assert.AreEqual('incOther = incLocal', Find(mUnit, 'TInc.incOther').Signature);
  Assert.AreEqual('incLast', Find(mUnit, 'TInc.incLast').Signature);
  // end align (Ausdruck) ist kein weiterer Typ mit Aufzählungswert (Winapi.Winsock2).
  mUnit := Extract(Lines(['unit Ausrichtung;', 'interface', 'type', '  TSpeicher = record', '    A: Int64;',
    '  end align (8);', '  TDanach = Integer;', 'implementation', 'end.']));
  Assert.AreEqual(0, CountNamed(mUnit, 'align'));
  Assert.AreEqual(1, CountNamed(mUnit, 'TDanach'));
  mUnit := Extract(Lines(['unit E;', 'interface', 'type',
    '  TInc = (incLocal = 1, incSystem = incLocal + 1, incOther = incLocal, incLast);', 'implementation', 'end.']));
  // Der Name bleibt die Auswahl, der Bereich umfasst den Wert.
  mSymbol := Find(mUnit, 'TInc.incSystem');
  Assert.AreEqual(mSymbol.Range.StartPos.Character, mSymbol.SelectionRange.StartPos.Character);
  Assert.AreEqual(mSymbol.SelectionRange.StartPos.Character + Length('incSystem'),
    mSymbol.SelectionRange.EndPos.Character);
end;

procedure TIndexContentTests.CatalogListsUnscopedEnumValues;
var
  mUnit: TUnitIndex;
  mEntry: TCatalogSymbol;
  mSymbol: TIndexSymbol;
begin
  mUnit := Extract(Lines(['unit Grafik;', 'interface', 'type', '  TFontStyle = (fsBold, fsItalic);',
    '  TFontStyles = set of TFontStyle;', '{$SCOPEDENUMS ON}', '  TScoped = (scA);', '{$SCOPEDENUMS OFF}',
    '  TFoo = class', '  type', '    TInner = (inA);', '  end;', 'implementation', 'type', '  TIntern = (itA);',
    'end.']));
  Assert.IsTrue(Catalog(mUnit, 'fsBold', mEntry));
  Assert.IsTrue(mEntry.Kind = TIndexSymbolKind.EnumMember);
  Assert.AreEqual('TFontStyle', mEntry.TypeName);
  mSymbol := mEntry.ToSymbol;
  Assert.AreEqual('TFontStyle', mSymbol.Container);
  Assert.AreEqual('', mSymbol.TypeName);
  Assert.IsTrue(Catalog(mUnit, 'fsItalic', mEntry));
  // Mit {$SCOPEDENUMS ON}, verschachtelt oder im implementation-Teil nicht.
  Assert.IsFalse(Catalog(mUnit, 'scA', mEntry));
  Assert.IsFalse(Catalog(mUnit, 'inA', mEntry));
  Assert.IsFalse(Catalog(mUnit, 'itA', mEntry));
  // Die Typen bleiben wie bisher.
  Assert.IsTrue(Catalog(mUnit, 'TFontStyle', mEntry));
  Assert.AreEqual(4, TCatalogUnit.FromUnit(mUnit).ExportedTypeCount);
end;

procedure TIndexContentTests.PlusUnitOffersEnumValues;
var
  mItems: TCompletionItems;
  mIndex: Integer;
begin
  FIndex.AddUnit(LibraryUnit(Lines(['unit Vcl.Graphics;', 'interface', 'type', '  TFontStyle = (fsBold, fsItalic);',
    'implementation', 'end.']), 'C:\RTL\Vcl.Graphics.pas'));
  FIndex.AddUnit(LibraryUnit(Lines(['unit System.Classes;', 'interface', 'type',
    '  TShiftStateItem = (ssShift, ssAlt);', '  TShiftState = set of TShiftStateItem;', 'implementation', 'end.']),
    'C:\RTL\System.Classes.pas'));
  FIndex.AddUnit(LibraryUnit(Lines(['unit System.SysUtils;', 'interface', 'type',
    '  TReplaceFlags = set of (rfReplaceAll, rfIgnoreCase);', 'implementation', 'end.']),
    'C:\RTL\System.SysUtils.pas'));
  mItems := ItemsAt(WithCode('  fsBo'), '  fsBo', TCompletionMatching.Fuzzy);
  mIndex := ItemIndex(mItems, 'fsBold');
  Assert.IsTrue(mIndex >= 0, Names(mItems));
  Assert.AreEqual('Vcl.Graphics (uses ergänzen)', mItems.Items[mIndex].Detail);
  Assert.AreEqual(1, Integer(Length(mItems.Items[mIndex].AdditionalEdits)));
  mItems := ItemsAt(WithCode('  ssShi'), '  ssShi', TCompletionMatching.Fuzzy);
  mIndex := ItemIndex(mItems, 'ssShift');
  Assert.IsTrue(mIndex >= 0, Names(mItems));
  Assert.AreEqual('System.Classes (uses ergänzen)', mItems.Items[mIndex].Detail);
  // Werte einer anonymen Aufzählung in set of (…) gehören zur Menge (12) und stehen ebenso im Katalog.
  mItems := ItemsAt(WithCode('  rfReplaceA'), '  rfReplaceA', TCompletionMatching.Fuzzy);
  mIndex := ItemIndex(mItems, 'rfReplaceAll');
  Assert.IsTrue(mIndex >= 0, Names(mItems));
  Assert.AreEqual('System.SysUtils (uses ergänzen)', mItems.Items[mIndex].Detail);
end;

procedure TIndexContentTests.CatalogKnowsArity;
var
  mUnit: TUnitIndex;
  mEntry: TCatalogSymbol;
begin
  mUnit := Extract(Lines(['unit Listen;', 'interface', 'type', '  TList<T> = class end;',
    '  TDict<K, V> = class end;', '  TPlain = class end;', '  TFunc<A, B, R> = reference to function(X: A; Y: B): R;',
    'implementation', 'end.']));
  Assert.IsTrue(Catalog(mUnit, 'TList', mEntry));
  Assert.AreEqual(1, mEntry.Arity);
  Assert.IsTrue(Catalog(mUnit, 'TDict', mEntry));
  Assert.AreEqual(2, mEntry.Arity);
  Assert.IsTrue(Catalog(mUnit, 'TPlain', mEntry));
  Assert.AreEqual(0, mEntry.Arity);
  Assert.IsTrue(Catalog(mUnit, 'TFunc', mEntry));
  Assert.AreEqual(3, mEntry.Arity);
  // Die übrigen Merker bleiben getrennt.
  Assert.AreEqual(0, Integer(mEntry.Flags and (TCatalogSymbol.cCatalogUnavailable or
    TCatalogSymbol.cCatalogScopedEnum)));
  Assert.AreEqual(2, TCatalogSymbol.ArityOf('K, V'));
end;

procedure TIndexContentTests.PlusUnitDistinguishesGenericTypes;
var
  mItems: TCompletionItems;
  mPlain, mGeneric: Integer;
begin
  FIndex.AddUnit(LibraryUnit(Lines(['unit System.Classes;', 'interface', 'type', '  TList = class end;',
    'implementation', 'end.']), 'C:\RTL\System.Classes.pas'));
  FIndex.AddUnit(LibraryUnit(Lines(['unit System.Generics.Collections;', 'interface', 'type',
    '  TList<T> = class end;', 'implementation', 'end.']), 'C:\RTL\System.Generics.Collections.pas'));
  // Ohne "<" dahinter: TList aus System.Classes zuerst.
  mItems := ItemsAt(WithCode('  TLis'), '  TLis', TCompletionMatching.Fuzzy);
  mPlain := ItemIndex(mItems, 'TList');
  mGeneric := ItemIndex(mItems, 'TList<T>');
  Assert.IsTrue((mPlain >= 0) and (mGeneric >= 0), Names(mItems));
  Assert.IsTrue(mPlain < mGeneric, Names(mItems));
  Assert.AreEqual('System.Generics.Collections (uses ergänzen)', mItems.Items[mGeneric].Detail);
  // Eingefügt wird nur der Name.
  Assert.AreEqual('TList', mItems.Items[mGeneric].InsertText);
  // Mit "<" dahinter: der generische zuerst.
  mItems := ItemsAt(WithCode('  TLis<Integer>.Create;'), '  TLis', TCompletionMatching.Fuzzy);
  mPlain := ItemIndex(mItems, 'TList');
  mGeneric := ItemIndex(mItems, 'TList<T>');
  Assert.IsTrue((mPlain >= 0) and (mGeneric >= 0), Names(mItems));
  Assert.IsTrue(mGeneric < mPlain, Names(mItems));
end;

procedure TIndexContentTests.LibraryDropsImplementationDuplicates;
const
  cText =
    'unit W;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Run;'#10 +
    '    procedure Load(A: Integer); overload;'#10 +
    '    procedure Load(const S: string); overload;'#10 +
    '  end;'#10 +
    'function MessageBox(Wnd: Integer; Text: PChar): Integer; stdcall;'#10 +
    'implementation'#10 +
    'const user32 = ''user32.dll'';'#10 +
    'function MessageBox; external user32 name ''MessageBoxW'';'#10 +
    'procedure TFoo.Run; begin end;'#10 +
    'procedure TFoo.Load(A: Integer); begin end;'#10 +
    'procedure TFoo.Load(const S: string); begin end;'#10 +
    'procedure OnlyHere; begin end;'#10 +
    'end.';
var
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mLoads: string;
begin
  mUnit := Extract(cText);
  // Projekt-Units bleiben wie bisher: Deklaration und Rumpf.
  Assert.AreEqual(2, CountNamed(mUnit, 'MessageBox'));
  Assert.AreEqual(4, CountNamed(mUnit, 'TFoo.Load'));
  Assert.AreEqual(4, TIndexExtractor.DropImplementationDuplicates(mUnit));
  Assert.AreEqual(1, CountNamed(mUnit, 'MessageBox'));
  Assert.AreEqual(1, CountNamed(mUnit, 'TFoo.Run'));
  Assert.AreEqual(2, CountNamed(mUnit, 'TFoo.Load'));
  // Routinen nur im implementation-Teil bleiben.
  Assert.AreEqual(1, CountNamed(mUnit, 'OnlyHere'));
  mSymbol := Find(mUnit, 'MessageBox');
  Assert.IsTrue(mSymbol.InInterface);
  Assert.IsTrue(mSymbol.HasDirective('external'));
  Assert.AreEqual('user32', mSymbol.DirectiveValue('external'));
  Assert.AreEqual('MessageBoxW', mSymbol.DirectiveValue('name'));
  Assert.AreEqual(11, mSymbol.ImplementationLine);
  Assert.AreEqual(2, Integer(mSymbol.MaxArgs), 'Die Parameter bleiben die der Deklaration');
  Assert.AreEqual(12, Find(mUnit, 'TFoo.Run').ImplementationLine);
  // Überladungen nach Parametertypen.
  mLoads := '';
  for mSymbol in mUnit.Symbols do
  begin
    if SameText(mSymbol.QualifiedName, 'TFoo.Load') then
    begin
      mLoads := mLoads + mSymbol.ParamTypes[0] + '=' + IntToStr(mSymbol.ImplementationLine) + ';';
    end;
  end;
  Assert.AreEqual('Integer=13;string=14;', mLoads);
  Assert.AreEqual(-1, Find(mUnit, 'OnlyHere').ImplementationLine);
end;

procedure TIndexContentTests.RecordsTargetTypes;
var
  mUnit: TUnitIndex;

  procedure Check(const AName, AForm, AType: string);
  var
    mSymbol: TIndexSymbol;
  begin
    mSymbol := Find(mUnit, AName);
    Assert.AreEqual(AForm, mSymbol.TargetForm, AName);
    Assert.AreEqual(AType, mSymbol.TargetType, AName);
  end;

begin
  mUnit := Extract(Lines(['unit Ziele;', 'interface', 'type', '  PInteger2 = ^Integer;', '  TBytes2 = array of Byte;',
    '  TMatrix = array[0..2, 0..3] of Double;', '  TKind = (kA, kB);', '  TKinds = set of TKind;',
    '  TFooClass = class of TObject;', '  TFunc2 = function(A: Integer): Boolean;', '  TProc2 = procedure of object;',
    '  TDigit = 0..9;', '  TRec = record', '    Items: array of string;', '    P: ^Byte;', '  end;', 'var',
    '  G: array[1..3] of TList<Integer>;', '  N: Integer;', 'implementation', 'end.']));
  // Der Typname bleibt leer: Aus PInteger darf nicht Integer werden.
  Assert.AreEqual('', Find(mUnit, 'PInteger2').TypeName);
  Check('PInteger2', '^', 'Integer');
  Check('TBytes2', 'array of', 'Byte');
  Check('TMatrix', 'array[0..2, 0..3] of', 'Double');
  Check('TKinds', 'set of', 'TKind');
  Check('TFooClass', 'class of', 'TObject');
  Assert.IsTrue(Find(mUnit, 'TFooClass').Kind = TIndexSymbolKind.ClassType);
  Check('TFunc2', 'function', 'Boolean');
  Check('TProc2', 'procedure', '');
  Assert.IsTrue(Find(mUnit, 'TProc2').HasDirective('of object'));
  Check('TDigit', 'range', '0..9');
  Check('TRec.Items', 'array of', 'string');
  Check('TRec.P', '^', 'Byte');
  Check('G', 'array[1..3] of', 'TList<Integer>');
  // Mit Typnamen kein Eintrag.
  Check('N', '', '');
  Assert.AreEqual('Integer', TResolvedSymbol.FromIndex(mUnit, Find(mUnit, 'PInteger2')).TargetType);
  Assert.AreEqual('^', TResolvedSymbol.FromIndex(mUnit, Find(mUnit, 'PInteger2')).TargetForm);
end;

procedure TIndexContentTests.RecordsAttributes;
var
  mUnit: TUnitIndex;
begin
  mUnit := Extract(Lines(['unit Attribute;', 'interface', 'type', '  [MyAttr]', '  TBar = class end;',
    '  TBaz = class', '    [Weak] FOwner: TObject;', '    [Unsafe, Volatile] FCount: Integer;', '    FPlain: Integer;',
    '  public', '    [TestCase(''A'', ''1'')]', '    procedure Run;', '  end;', 'implementation', 'end.']));
  Assert.AreEqual('MyAttr', string.Join(',', Find(mUnit, 'TBar').Attributes));
  Assert.AreEqual('', string.Join(',', Find(mUnit, 'TBaz').Attributes));
  Assert.AreEqual('Weak', string.Join(',', Find(mUnit, 'TBaz.FOwner').Attributes));
  Assert.AreEqual('Unsafe,Volatile', string.Join(',', Find(mUnit, 'TBaz.FCount').Attributes));
  Assert.AreEqual('', string.Join(',', Find(mUnit, 'TBaz.FPlain').Attributes));
  Assert.AreEqual('TestCase', string.Join(',', Find(mUnit, 'TBaz.Run').Attributes));
  Assert.IsTrue(Find(mUnit, 'TBaz.FOwner').HasDirective('@Weak'));
end;

procedure TIndexContentTests.EvaluatesUnitConstantsAndBuiltins;
var
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  mUnit := Extract(Lines(['unit Konst;', 'interface', 'const', '  GenericUtils = False;',
    '  GenericArrays = GenericUtils;', '  Komplex = not GenericArrays;', '{$IF GenericArrays}', 'procedure A;',
    '{$ELSE}', 'procedure B;', '{$ENDIF}', '{$IF Komplex}', 'procedure C;', '{$ENDIF}', '{$IF Declared(AnsiChar)}',
    'procedure D;', '{$ELSE}', 'procedure E;', '{$ENDIF}', '{$IFOPT R+}', 'procedure F;', '{$ELSE}', 'procedure G;',
    '{$ENDIF}', '{$IF DECLARED(UTF8Char)}', 'procedure J;', '{$ELSE}', 'procedure K;', '{$ENDIF}', 'implementation',
    'end.']), ['MSWINDOWS', 'WIN32'] + TPascalPreprocessor.ProjectSwitches(nil));
  Assert.IsTrue(HasActive(mUnit, 'J'), 'J nicht aktiv');
  Assert.IsFalse(HasActive(mUnit, 'K'), 'K aktiv');
  // Vorher galten bei unbekanntem Wert beide Zweige.
  Assert.IsFalse(HasActive(mUnit, 'A'), 'A aktiv');
  Assert.IsTrue(HasActive(mUnit, 'B'), 'B nicht aktiv');
  Assert.IsTrue(HasActive(mUnit, 'C'), 'C nicht aktiv');
  Assert.IsTrue(HasActive(mUnit, 'D'), 'D nicht aktiv');
  Assert.IsFalse(HasActive(mUnit, 'E'), 'E aktiv');
  Assert.IsFalse(HasActive(mUnit, 'F'), 'F aktiv');
  Assert.IsTrue(HasActive(mUnit, 'G'), 'G nicht aktiv');
  Assert.IsTrue(FindUnavailable(mUnit, 'A', mSymbol), 'A nicht unter Unavailable');
  Assert.IsTrue(FindUnavailable(mUnit, 'E', mSymbol), 'E nicht unter Unavailable');
  // Zweige von $IFOPT führt der Präprozessor nicht als bedingte Bereiche (ohne Bedingungstext): F fehlt nur.
  Assert.IsFalse(FindUnavailable(mUnit, 'F', mSymbol), 'F unter Unavailable');
  // Konstanten aus anderen Units bleiben unbekannt: beide Zweige.
  mUnit := Extract(Lines(['unit Fremd;', 'interface', '{$IF Woanders}', 'procedure H;', '{$ELSE}', 'procedure I;',
    '{$ENDIF}', 'implementation', 'end.']), nil);
  Assert.IsTrue(HasActive(mUnit, 'H'), 'H nicht aktiv');
  Assert.IsTrue(HasActive(mUnit, 'I'), 'I nicht aktiv');
end;

procedure TIndexContentTests.LibraryDefinesCarrySwitches;
var
  mProject: TProjectInfo;
  mDefines: TArray<string>;
begin
  mProject := Default(TProjectInfo);
  mProject.Platform := 'Win32';
  mDefines := TIndexProjectFiles.LibraryDefines(mProject, '37.0');
  Assert.IsTrue(string.Join(';', mDefines).Contains('$R-*'), string.Join(';', mDefines));
  Assert.IsTrue(string.Join(';', mDefines).Contains('MSWINDOWS'));
end;

procedure TIndexContentTests.KeepsVariantsAndReadsTheirSignature;
var
  mText: string;
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mVariants: Integer;
begin
  mText := Lines(['unit Varianten;', 'interface', '{$IFDEF WIN64}', 'function Groesse(A: Int64;', '  B: Int64): Int64;',
    '{$ELSE}', 'function Groesse(A: Integer): Integer;', '{$ENDIF}', 'var', '{$IFDEF NIE}', '  Alt, Neu: Integer;',
    '{$ENDIF}', '  Immer: Integer;', 'implementation', '{$IFDEF WIN64}', 'function Groesse(A: Int64; B: Int64): Int64;',
    'begin', 'end;', '{$ELSE}', 'function Groesse(A: Integer): Integer;', 'begin', 'end;', '{$ENDIF}', 'end.']);
  mUnit := Extract(mText, ['WIN32', 'MSWINDOWS']);
  Assert.IsTrue(HasActive(mUnit, 'Groesse'));
  // Die Variante unter WIN64 bleibt erhalten, ihr Rumpf im implementation-Teil nicht (nur die andere
  // Implementierung).
  mVariants := 0;
  for mSymbol in mUnit.Unavailable do
  begin
    Inc(mVariants, Ord(SameText(mSymbol.Name, 'Groesse')));
  end;
  Assert.AreEqual(1, mVariants);
  Assert.IsTrue(FindUnavailable(mUnit, 'Groesse', mSymbol));
  Assert.AreEqual('WIN64', mSymbol.Condition);
  Assert.AreEqual('function Groesse(A: Int64; B: Int64): Int64', TIndexFiles.SourceSignature(mText, mSymbol));
  // "A, B: T" liefert beide Namen.
  Assert.IsTrue(FindUnavailable(mUnit, 'Alt', mSymbol));
  Assert.AreEqual('Alt, Neu: Integer', TIndexFiles.SourceSignature(mText, mSymbol));
  Assert.IsTrue(FindUnavailable(mUnit, 'Neu', mSymbol));
  Assert.IsTrue(mSymbol.Kind = TIndexSymbolKind.Variable);
  Assert.AreEqual(Pos('Neu', '  Alt, Neu: Integer;') - 1, mSymbol.SelectionRange.StartPos.Character);
end;

procedure TIndexContentTests.KeepsLongRoutineSignatures;
var
  mParams, mText, mLong: string;
  mIndex: Integer;
  mUnit: TUnitIndex;
  mSymbol: TIndexSymbol;
  mReader: TIndexReadText;
  mFull: string;
begin
  mParams := '';
  for mIndex := 1 to 30 do
  begin
    if mParams <> '' then
    begin
      mParams := mParams + '; ';
    end;
    mParams := mParams + Format('Parameter%.2d: Integer', [mIndex]);
  end;
  mLong := StringOfChar('x', 400);
  mText := Lines(['unit Lang;', 'interface', 'const', '  Text = ''' + mLong + ''';',
    'procedure Lang(' + mParams + ');', 'implementation', 'end.']);
  mUnit := Extract(mText);
  mSymbol := Find(mUnit, 'Lang');
  Assert.IsTrue(Length(mSymbol.Signature) > TIndexSymbol.cMaxSignature);
  Assert.AreEqual('procedure Lang(' + mParams + ')', mSymbol.Signature);
  Assert.AreEqual(mSymbol.Signature, TIndexFiles.SourceSignature(mText, mSymbol));
  // Konstanten bleiben gekürzt; die volle Signatur liest SourceSignature aus der Quelle.
  mSymbol := Find(mUnit, 'Text');
  Assert.AreEqual(TIndexSymbol.cMaxSignature, Length(mSymbol.Signature));
  Assert.IsTrue(mSymbol.Signature.EndsWith('…'));
  Assert.AreEqual('Text = ''' + mLong + '''', TIndexFiles.SourceSignature(mText, mSymbol));
  mReader :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := SameText(AFileName, cFile);
      AText := mText;
    end;
  Assert.IsTrue(TIndexFiles.SourceSignatureOf(mUnit, mSymbol, mReader, mFull));
  Assert.AreEqual('Text = ''' + mLong + '''', mFull);
  Assert.AreEqual(1000, TIndexSymbol.MaxSignatureOf(TIndexSymbolKind.Method));
  Assert.AreEqual(300, TIndexSymbol.MaxSignatureOf(TIndexSymbolKind.EnumType));
end;

procedure TIndexContentTests.CacheKeepsNewEntries;
var
  mUnit: TUnitIndex;
  mLoaded: TArray<TUnitIndex>;
  mSymbol: TIndexSymbol;
begin
  Assert.AreEqual(35, TIndexCache.cFormatVersion);
  Assert.AreEqual('index-35.dpccidx', TIndexCacheDirectory.CacheFileName);
  mUnit := Extract(Lines(['unit Cache;', 'interface', 'type', '  PInt = ^Integer;', '  TBox<T: class> = class',
    '    [Weak] FOwner: TObject;', '  end;', '/// <summary>Doku</summary>', 'procedure Run;', 'implementation',
    'procedure Run; begin end;', 'end.']));
  mUnit.Requires := ['rtl'];
  mLoaded := TIndexCache.Deserialize(TIndexCache.Serialize([mUnit]));
  Assert.AreEqual(1, Integer(Length(mLoaded)));
  Assert.AreEqual('rtl', string.Join(',', mLoaded[0].Requires));
  mSymbol := Find(mLoaded[0], 'PInt');
  Assert.AreEqual('Integer', mSymbol.TargetType);
  Assert.AreEqual('class', Find(mLoaded[0], 'TBox').ConstraintsOf('T'));
  Assert.AreEqual('Weak', string.Join(',', Find(mLoaded[0], 'TBox.FOwner').Attributes));
  Assert.AreEqual('procedure Run', Find(mLoaded[0], 'Run').Signature);
end;

procedure TIndexContentTests.MarksKindsWithoutOwnKind;
var
  mUnit: TUnitIndex;
begin
  mUnit := Extract(Lines(['unit Arten;', 'interface', 'resourcestring', '  SFehler = ''Fehler'';', 'const',
    '  CNormal = 1;', 'threadvar', '  TZaehler: Integer;', 'var', '  GNormal: Integer;', 'type',
    '  TVek = record', '    class operator Add(const A, B: TVek): TVek;', '  end;', '  TFenster = class',
    '    destructor Destroy; override;', '    procedure WMPaint(var M: TObject); message WM_PAINT;', '  end;',
    'implementation', 'end.']));
  Assert.IsTrue(Find(mUnit, 'SFehler').HasDirective('resourcestring'));
  Assert.IsTrue(Find(mUnit, 'SFehler').Kind = TIndexSymbolKind.Constant);
  Assert.IsFalse(Find(mUnit, 'CNormal').HasDirective('resourcestring'));
  Assert.IsTrue(Find(mUnit, 'TZaehler').HasDirective('threadvar'));
  Assert.IsFalse(Find(mUnit, 'GNormal').HasDirective('threadvar'));
  Assert.IsTrue(Find(mUnit, 'TVek.Add').HasDirective('operator'));
  Assert.IsTrue(Find(mUnit, 'TVek.Add').HasDirective('class'));
  Assert.IsTrue(Find(mUnit, 'TFenster.Destroy').HasDirective('destructor'));
  Assert.IsTrue(Find(mUnit, 'TFenster.Destroy').Kind = TIndexSymbolKind.Constructor_);
  Assert.AreEqual('WM_PAINT', Find(mUnit, 'TFenster.WMPaint').DirectiveValue('message'));
end;

procedure TIndexContentTests.ExtractsAnonymousTypeMembers;
var
  mUnit: TUnitIndex;
  mEntry: TCatalogSymbol;
begin
  mUnit := Extract(Lines(['unit Anonym;', 'interface', 'type', '  TS = set of (sa, sb);', '  TFoo = class',
    '    FData: record', '      X, Y: Integer;', '    end;', '    FMode: (mA, mB);', '  end;', 'var',
    '  GRec: record Z: Byte; end;', 'implementation', 'end.']));
  Assert.IsTrue(Find(mUnit, 'TS.sa').Kind = TIndexSymbolKind.EnumMember);
  Assert.IsTrue(Find(mUnit, 'TS.sb').Kind = TIndexSymbolKind.EnumMember);
  Assert.IsTrue(Find(mUnit, 'TFoo.FData.X').Kind = TIndexSymbolKind.Field);
  Assert.IsTrue(Find(mUnit, 'TFoo.FData.Y').Kind = TIndexSymbolKind.Field);
  Assert.IsTrue(Find(mUnit, 'TFoo.FMode.mA').Kind = TIndexSymbolKind.EnumMember);
  Assert.IsTrue(Find(mUnit, 'GRec.Z').Kind = TIndexSymbolKind.Field);
  Assert.AreEqual('record', Find(mUnit, 'TFoo.FData').TargetForm);
  Assert.AreEqual('enum', Find(mUnit, 'TFoo.FMode').TargetForm);
  // Werte der Menge auf oberster Ebene stehen im Katalog, die eines Felds nicht.
  Assert.IsTrue(Catalog(mUnit, 'sa', mEntry));
  Assert.AreEqual('TS', mEntry.TypeName);
  Assert.IsFalse(Catalog(mUnit, 'mA', mEntry));
end;

procedure TIndexContentTests.RecordsTypeParameterConstraints;
var
  mUnit: TUnitIndex;
begin
  mUnit := Extract(Lines(['unit Grenzen;', 'interface', 'type', '  TBox<T: class, constructor; K> = class',
    '    function Map<R: IInterface>(A: T): R;', '  end;', '  TPair<A, B: record> = record end;', 'implementation',
    'end.']));
  Assert.AreEqual('class,constructor', Find(mUnit, 'TBox').ConstraintsOf('T'));
  Assert.AreEqual('', Find(mUnit, 'TBox').ConstraintsOf('K'));
  Assert.AreEqual('IInterface', Find(mUnit, 'TBox.Map').ConstraintsOf('R'));
  Assert.AreEqual('record', Find(mUnit, 'TPair').ConstraintsOf('A'));
  Assert.AreEqual('record', Find(mUnit, 'TPair').ConstraintsOf('B'));
  Assert.IsTrue(Find(mUnit, 'TBox').HasDirective('<T:class,constructor>'));
end;

procedure TIndexContentTests.ReadsPackageClauses;
var
  mUnit: TUnitIndex;
begin
  mUnit := TIndexExtractor.ExtractText(Lines(['package Paket;', 'requires', '  rtl, vcl;', 'contains',
    '  A in ''A.pas'', B;', 'end.']), 'C:\P\Paket.dpk', nil);
  Assert.AreEqual('rtl,vcl', string.Join(',', mUnit.Requires));
  Assert.AreEqual('A,B', string.Join(',', mUnit.ImplementationUses));
  Assert.AreEqual(0, Integer(Length(mUnit.InterfaceUses)));
end;

procedure TIndexContentTests.FormatsSignaturesLikeSource;
var
  mUnit: TUnitIndex;
begin
  mUnit := Extract(Lines(['unit Abstand;', 'interface', 'type', '  PInt = ^Integer;', '  TSplitKind = (skA, skB);',
    '  TDigit = 0..9;', '  TListe<K, V> = class', '    function E: TEnumerator<TPair<K, V>>;', '  end;', 'const',
    '  Leer: TArray<Integer> = [];', '  Zeiger: PInt = nil;', 'implementation', 'end.']));
  Assert.AreEqual('PInt = ^Integer', Find(mUnit, 'PInt').Signature);
  Assert.AreEqual('TSplitKind = (skA, skB)', Find(mUnit, 'TSplitKind').Signature);
  Assert.AreEqual('TDigit = 0..9', Find(mUnit, 'TDigit').Signature);
  Assert.AreEqual('function E: TEnumerator<TPair<K, V>>', Find(mUnit, 'TListe.E').Signature);
  Assert.AreEqual('Leer: TArray<Integer> = []', Find(mUnit, 'Leer').Signature);
end;

procedure TIndexContentTests.RemovesOlderCacheFormats;
var
  mFolder, mCurrent: string;

  procedure Touch(const AName: string);
  begin
    TFile.WriteAllText(TPath.Combine(mFolder, AName), 'x');
  end;

begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'dpcc-l1-' + IntToStr(TThread.GetTickCount64));
  ForceDirectories(mFolder);
  try
    Touch('index-33.dpccidx');
    Touch('index-34.dpccidx');
    Touch('index-34.dpccidx.lock');
    Touch(TIndexCacheDirectory.CacheFileName);
    Touch('projekt.txt');
    Touch('anders-34.dpccidx');
    mCurrent := TPath.Combine(mFolder, TIndexCacheDirectory.CacheFileName);
    // Ein anderer Name als der des aktuellen Formats löscht nichts.
    Assert.AreEqual(0, TIndexCacheDirectory.RemoveOlderFormats(TPath.Combine(mFolder, 'index-34.dpccidx')));
    Assert.AreEqual(2, TIndexCacheDirectory.RemoveOlderFormats(mCurrent));
    Assert.IsFalse(TFile.Exists(TPath.Combine(mFolder, 'index-33.dpccidx')));
    Assert.IsFalse(TFile.Exists(TPath.Combine(mFolder, 'index-34.dpccidx')));
    Assert.IsFalse(TFile.Exists(TPath.Combine(mFolder, 'index-34.dpccidx.lock')));
    Assert.IsTrue(TFile.Exists(mCurrent));
    Assert.IsTrue(TFile.Exists(TPath.Combine(mFolder, 'projekt.txt')));
    Assert.IsTrue(TFile.Exists(TPath.Combine(mFolder, 'anders-34.dpccidx')));
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexContentTests);

end.
