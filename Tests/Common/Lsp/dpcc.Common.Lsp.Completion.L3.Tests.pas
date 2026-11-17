unit dpcc.Common.Lsp.Completion.L3.Tests;

// Auftrag L3 (Auflösung im Editor), Punkte 10 und 13:
// - raise und [Attribut]: Der Vorfilter prüft Klassen aus nicht eingebundenen Units über die Vorfahren im Katalog und
//   lädt dafür keine kalte Unit nach; Typen aus Packages der IDE ohne Quelltext kommen über ihren Vorfahren (Parent)
//   dazu.
// - {$I und {$INCLUDE: Dateinamen aus dem Ordner der Datei, einem getippten Unterordner und den Ordnern der
//   Include-Dateien, die die Unit schon einbindet.
// Nur APIs, die es vor L3 schon gab: Die Tests lassen sich gegen den alten Stand gegenprüfen (dort schlagen
// RaiseAdmitLoadsNoColdUnit, RaiseOffersIdeExceptionClasses, AttributeOffersIdeAttributeClasses und die
// Include-Tests fehl). Testquellen in ASCII.
// L4: Auch die Nachbearbeitung der Listen (TCompletionExceptions.Apply, TCompletionAttributes.Apply) lädt keine
// kalte Unit mehr (RaiseListLoadsNoColdUnit, HandlerListLoadsNoColdUnit, AttributeListLoadsNoColdUnit; vor L4 rot:
// zwei bzw. eine Unit nachgeladen).

interface

uses
  DUnitX.TestFramework,
  dpcc.Common.Index.Contract,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Lsp.IdeTypes,
  dpcc.Common.Lsp.CompletionRequest;

type
  [TestFixture]
  TCompletionL3Tests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    FFolder: string;
    /// <summary>Vervollständigung in Haupt: AMarked ersetzt "{ Code }" bzw. mit "A:" davor "{ Attr }".</summary>
    function ItemsAt(const AMarked: string; const AIdeTypes: TArray<TIdeTypeEntry>): TCompletionItems;
    /// <summary>Vorschläge in einer Direktive (TCompletionDirectives.DirectiveItems) für die Zeile AMarked in einer
    /// Datei im Ordner proj.</summary>
    function DirectiveAt(const AMarked: string; out AItems: TCompletionItems): Boolean;
    function Find(const AItems: TCompletionItems; const AName: string; out AItem: TCompletionItem): Boolean;
    function ProjectFile: string;
    procedure AddColdLibrary;
  public
    /// <summary>Ordner mit Include-Dateien und Einmal-Belegungen vor dem Leckmonitor.</summary>
    [SetupFixture]
    procedure WarmUp;
    [TearDownFixture]
    procedure CleanUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>raise TVendor: Klassen aus kalten Units, deren Kette nicht zu Exception führt, fallen weg, ohne dass
    /// der Vorfilter eine Unit nachlädt (vorher lud die Namensauflösung die Units der Vorfahren).</summary>
    [Test]
    procedure RaiseAdmitLoadsNoColdUnit;
    /// <summary>raise EVendor: Exception-Klassen aus kalten Units, auch über einen Vorfahren in einer zweiten kalten
    /// Unit.</summary>
    [Test]
    procedure RaiseFindsColdExceptionChain;
    /// <summary>raise EVendorB: Exception-Klassen aus Packages der IDE ohne Quelltext, über Parent bis Exception (auch
    /// über einen zweiten IDE-Typ); andere Klassen nicht.</summary>
    [Test]
    procedure RaiseOffersIdeExceptionClasses;
    /// <summary>[VendorT: Attributklassen aus Packages der IDE über Parent bis TCustomAttribute, ohne die Endung.
    /// </summary>
    [Test]
    procedure AttributeOffersIdeAttributeClasses;
    /// <summary>L4: raise EVendor zeigt die Exception-Klassen aus zwei kalten Units, ohne dass die Nachbearbeitung
    /// der Liste eine davon nachlädt (vorher: beide).</summary>
    [Test]
    procedure RaiseListLoadsNoColdUnit;
    /// <summary>L4: on E: nach einem Zweig für EVendorBase: EVendorThingError aus einer kalten Unit trägt die
    /// Warnung zur Reihenfolge (Vorfahren aus dem Katalog), ohne Nachladen.</summary>
    [Test]
    procedure HandlerListLoadsNoColdUnit;
    /// <summary>L4: [VendorM zeigt die Attributklasse aus einer kalten Unit ohne Endung, mit der Unit als Detail,
    /// ohne sie nachzuladen (vorher: nachgeladen).</summary>
    [Test]
    procedure AttributeListLoadsNoColdUnit;
    /// <summary>{$I : die .inc-Dateien im Ordner der Datei, eingefügt per textEdit ab dem Namen.</summary>
    [Test]
    procedure IncludeOffersFilesOfFolder;
    /// <summary>{$INCLUDE sub\D: nur der getippte Unterordner, eingefügt samt Ordner.</summary>
    [Test]
    procedure IncludeWithSubfolder;
    /// <summary>{$I : auch die Ordner der Include-Dateien, die die Unit laut Index schon einbindet.</summary>
    [Test]
    procedure IncludeOffersKnownIncludeFolders;
    /// <summary>{$I+ und {$IFDEF bieten keine Dateinamen an.</summary>
    [Test]
    procedure IncludeSwitchIsNoFileName;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Pascal.Parser,
  dpcc.Common.Index.Extractor,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.Cache,
  dpcc.Common.Lsp.Completion.Postfix,
  dpcc.Common.Lsp.Completion.Lists,
  dpcc.Common.Lsp.Completion.Directives;

const
  HauptFile = 'C:\P\Haupt.pas';
  SysUtilsFile = 'C:\Rtl\System.SysUtils.pas';
  VendorBaseFile = 'C:\Lib\Vendor.Base.pas';
  VendorThingsFile = 'C:\Lib\Vendor.Things.pas';

  UnitSysUtils =
    'unit System.SysUtils;'#10 +
    'interface'#10 +
    'type'#10 +
    '  Exception = class(TObject)'#10 +
    '  public'#10 +
    '    constructor Create(const Msg: string);'#10 +
    '  end;'#10 +
    '  EConvertError = class(Exception);'#10 +
    'implementation'#10 +
    'constructor Exception.Create(const Msg: string); begin end;'#10 +
    'end.';

  UnitVendorBase =
    'unit Vendor.Base;'#10 +
    'interface'#10 +
    'uses'#10 +
    '  System.SysUtils;'#10 +
    'type'#10 +
    '  EVendorBase = class(Exception);'#10 +
    '  TVendorBaseThing = class(TObject);'#10 +
    '  VendorMarkAttribute = class(TCustomAttribute);'#10 +
    'implementation'#10 +
    'end.';

  UnitVendorThings =
    'unit Vendor.Things;'#10 +
    'interface'#10 +
    'uses'#10 +
    '  Vendor.Base;'#10 +
    'type'#10 +
    '  TVendorThing = class(TVendorBaseThing);'#10 +
    '  TVendorWidget = class(TVendorThing);'#10 +
    '  EVendorThingError = class(EVendorBase);'#10 +
    'implementation'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses'#10 +
    '  System.SysUtils;'#10 +
    'type'#10 +
    '  TWorker = class'#10 +
    '  public'#10 +
    '    { Attr }'#10 +
    '    procedure Run;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TWorker.Run;'#10 +
    'begin'#10 +
    '  { Code }'#10 +
    'end;'#10 +
    'end.';

/// <summary>Text ohne "|" und die Position des "|".</summary>
function Split(const AMarked: string; out APosition: TTextPosition): string;
var
  mIndex, mLine, mCharacter: Integer;
begin
  mLine := 0;
  mCharacter := 0;
  for mIndex := 1 to Pos('|', AMarked) - 1 do
  begin
    if AMarked[mIndex] = #10 then
    begin
      Inc(mLine);
      mCharacter := 0;
    end
    else
    begin
      Inc(mCharacter);
    end;
  end;
  APosition := TTextPosition.Create(mLine, mCharacter);
  Result := StringReplace(AMarked, '|', '', []);
end;

/// <summary>Bibliotheks-Unit aus AText.</summary>
function LibraryUnit(const AText, AFileName: string): TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(AText, AFileName, nil);
  Result.Library_ := True;
  Result.Stamp := 7;
  Result.Hash := 'H' + AFileName;
end;

/// <summary>IDE-Typ mit Unit und Vorfahr.</summary>
function IdeType(const AName, AUnitName, AParent: string): TIdeTypeEntry;
begin
  Result := Default(TIdeTypeEntry);
  Result.Name := AName;
  Result.UnitName := AUnitName;
  Result.Parent := AParent;
end;

{ TCompletionL3Tests }

procedure TCompletionL3Tests.WarmUp;
var
  mItems: TCompletionItems;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'dpcc-l3-' + IntToStr(MainThreadID));
  ForceDirectories(TPath.Combine(FFolder, 'proj\sub'));
  ForceDirectories(TPath.Combine(FFolder, 'shared'));
  TFile.WriteAllText(TPath.Combine(FFolder, 'proj\Vendor.inc'), '// Vendor');
  TFile.WriteAllText(TPath.Combine(FFolder, 'proj\Other.inc'), '// Other');
  TFile.WriteAllText(TPath.Combine(FFolder, 'proj\readme.txt'), 'kein Include');
  TFile.WriteAllText(TPath.Combine(FFolder, 'proj\sub\Deep.inc'), '// Deep');
  TFile.WriteAllText(TPath.Combine(FFolder, 'shared\Common.inc'), '// Common');
  // Einmal-Belegungen (Texttabellen, Namensindex, Cache-Kodierung) vor dem Leckmonitor.
  Setup;
  try
    ItemsAt('raise EVendor|', [IdeType('EVendorBplError', 'Vendor.Bpl', 'System.SysUtils.Exception')]);
    ItemsAt('A:[VendorT|', [IdeType('VendorTagAttribute', 'Vendor.Bpl', 'System.TCustomAttribute')]);
    DirectiveAt('{$I |', mItems);
    DirectiveAt('{$R|', mItems);
  finally
    TearDown;
  end;
end;

procedure TCompletionL3Tests.CleanUp;
begin
  if (FFolder <> '') and TDirectory.Exists(FFolder) then
  try
    TDirectory.Delete(FFolder, True);
  except
    // Ein Rest im Temp-Ordner stört keinen Test.
    on Exception do
      ;
  end;
end;

procedure TCompletionL3Tests.Setup;
var
  mRtl: TUnitIndex;
begin
  FIndex := TSymbolIndex.Create;
  mRtl := LibraryUnit(UnitSysUtils, SysUtilsFile);
  FIndex.AddUnit(mRtl);
  AddColdLibrary;
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TCompletionL3Tests.TearDown;
begin
  FreeAndNil(FResolver);
  FIndex := nil;
end;

procedure TCompletionL3Tests.AddColdLibrary;
var
  mEntries: TArray<TIndexCacheEntry>;
  mEntry: TIndexCacheEntry;
begin
  // Wie die Bibliotheksstufe beim Start aus dem Cache: nur Kopf, Katalog und Block.
  mEntries := TIndexCache.ReadEntries(TIndexCache.Serialize([LibraryUnit(UnitVendorBase, VendorBaseFile),
    LibraryUnit(UnitVendorThings, VendorThingsFile)]));
  Assert.AreEqual(2, Integer(Length(mEntries)), 'Cache gelesen');
  for mEntry in mEntries do
  begin
    FIndex.AddCold(mEntry.Header, mEntry.Catalog, mEntry.Source, mEntry.SymbolCount, mEntry.UnavailableCount,
      mEntry.UsageCount);
  end;
end;

function TCompletionL3Tests.ItemsAt(const AMarked: string; const AIdeTypes: TArray<TIdeTypeEntry>): TCompletionItems;
var
  mText: string;
  mPosition: TTextPosition;
  mTree: TSyntaxTree;
  mRequest: TCompletionRequest;
begin
  if AMarked.StartsWith('A:') then
  begin
    mText := Split(StringReplace(UnitHaupt, '{ Attr }', Copy(AMarked, 3, MaxInt), []), mPosition);
  end
  else
  begin
    mText := Split(StringReplace(UnitHaupt, '{ Code }', AMarked, []), mPosition);
  end;
  mTree := TPascalParser.Parse(mText);
  FIndex.AddUnit(TIndexExtractor.ExtractText(mText, HauptFile, nil));
  mRequest := TCompletionRequest.Create(mText, HauptFile, mPosition);
  try
    mRequest.Tree := mTree;
    mRequest.Resolver := FResolver;
    mRequest.Index := FIndex;
    mRequest.Matching := TCompletionMatching.Prefix;
    mRequest.Settings := TCompletionSettings.Default;
    mRequest.IdeTypes := AIdeTypes;
    Result := TCompletionLists.Collect(mRequest, Default(TPostfixOptions), nil);
  finally
    mRequest.Free;
    mTree.Free;
  end;
end;

function TCompletionL3Tests.ProjectFile: string;
begin
  Result := TPath.Combine(FFolder, 'proj\Haupt.pas');
end;

function TCompletionL3Tests.DirectiveAt(const AMarked: string; out AItems: TCompletionItems): Boolean;
var
  mText: string;
  mPosition: TTextPosition;
  mRequest: TCompletionRequest;
begin
  mText := Split('unit Haupt;'#10'interface'#10 + AMarked + #10'implementation'#10'end.', mPosition);
  mRequest := TCompletionRequest.Create(mText, ProjectFile, mPosition);
  try
    mRequest.Index := FIndex;
    Result := TCompletionDirectives.DirectiveItems(mRequest, AItems);
  finally
    mRequest.Free;
  end;
end;

function TCompletionL3Tests.Find(const AItems: TCompletionItems; const AName: string;
  out AItem: TCompletionItem): Boolean;
var
  mItem: TCompletionItem;
begin
  for mItem in AItems.Items do
  begin
    if mItem.Name = AName then
    begin
      AItem := mItem;
      Exit(True);
    end;
  end;
  AItem := Default(TCompletionItem);
  Result := False;
end;

procedure TCompletionL3Tests.RaiseAdmitLoadsNoColdUnit;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mLoads: Integer;
begin
  mLoads := FIndex.LazyStats.Loads;
  Assert.AreEqual(2, FIndex.LazyStats.Cold, 'Vendor.Base und Vendor.Things nur im Katalog');
  mItems := ItemsAt('raise TVendor|', nil);
  Assert.IsFalse(Find(mItems, 'TVendorThing', mItem), 'keine Exception-Klasse');
  Assert.IsFalse(Find(mItems, 'TVendorWidget', mItem), 'keine Exception-Klasse (zwei Stufen)');
  Assert.IsFalse(Find(mItems, 'TVendorBaseThing', mItem), 'keine Exception-Klasse (TObject)');
  Assert.AreEqual(mLoads, FIndex.LazyStats.Loads, 'der Vorfilter lädt keine kalte Unit nach');
  Assert.AreEqual(2, FIndex.LazyStats.Cold, 'beide Units weiter kalt');
end;

procedure TCompletionL3Tests.RaiseFindsColdExceptionChain;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt('raise EVendor|', nil);
  Assert.IsTrue(Find(mItems, 'EVendorBase', mItem), 'Exception-Klasse aus kalter Unit');
  Assert.IsTrue(Find(mItems, 'EVendorThingError', mItem), 'Vorfahr in einer zweiten kalten Unit');
  Assert.AreEqual(1, Integer(Length(mItem.AdditionalEdits)), 'mit uses-Eintrag');
end;

procedure TCompletionL3Tests.RaiseOffersIdeExceptionClasses;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt('raise EVendorB|', [
    IdeType('EVendorBplError', 'Vendor.Bpl', 'System.SysUtils.Exception'),
    IdeType('EVendorBplSubError', 'Vendor.Bpl', 'Vendor.Bpl.EVendorBplError'),
    IdeType('EVendorBplHelper', 'Vendor.Bpl', 'System.Classes.TComponent'),
    IdeType('EVendorBplKind', 'Vendor.Bpl', '')]);
  Assert.IsTrue(Find(mItems, 'EVendorBplError', mItem), 'IDE-Typ mit Exception als Vorfahr');
  Assert.AreEqual(1, Integer(Length(mItem.AdditionalEdits)), 'mit uses-Eintrag');
  Assert.IsTrue(Find(mItems, 'EVendorBplSubError', mItem), 'Vorfahr ist selbst ein IDE-Typ');
  Assert.IsFalse(Find(mItems, 'EVendorBplHelper', mItem), 'Vorfahr TComponent: keine Exception');
  Assert.IsFalse(Find(mItems, 'EVendorBplKind', mItem), 'ohne Vorfahr: keine Klasse');
end;

procedure TCompletionL3Tests.AttributeOffersIdeAttributeClasses;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt('A:[VendorT|', [
    IdeType('VendorTagAttribute', 'Vendor.Bpl', 'System.TCustomAttribute'),
    IdeType('VendorTool', 'Vendor.Bpl', 'System.Classes.TComponent')]);
  Assert.IsTrue(Find(mItems, 'VendorTag', mItem), 'Attributklasse aus der IDE ohne Endung');
  Assert.IsTrue(mItem.Attribute, 'als Attribut');
  Assert.AreEqual('Vendor.Bpl', mItem.Detail, 'Unit als Detail');
  Assert.IsFalse(Find(mItems, 'VendorTool', mItem), 'keine Attributklasse');
end;

procedure TCompletionL3Tests.RaiseListLoadsNoColdUnit;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mLoads: Integer;
begin
  mLoads := FIndex.LazyStats.Loads;
  mItems := ItemsAt('raise EVendor|', nil);
  Assert.IsTrue(Find(mItems, 'EVendorBase', mItem), 'Exception-Klasse aus kalter Unit');
  Assert.AreEqual('EVendorBase.Create('''')', mItem.InsertText, 'Übernahme als raise');
  Assert.IsTrue(Find(mItems, 'EVendorThingError', mItem), 'Vorfahr in einer zweiten kalten Unit');
  Assert.AreEqual(mLoads, FIndex.LazyStats.Loads, 'die Nachbearbeitung lädt keine kalte Unit nach');
  Assert.AreEqual(2, FIndex.LazyStats.Cold, 'beide Units weiter kalt');
end;

procedure TCompletionL3Tests.HandlerListLoadsNoColdUnit;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mLoads: Integer;
begin
  mLoads := FIndex.LazyStats.Loads;
  mItems := ItemsAt('try'#10'  except'#10'    on E: EVendorBase do ;'#10'    on E: EVendorT|', nil);
  Assert.IsTrue(Find(mItems, 'EVendorThingError', mItem), 'Exception-Klasse aus kalter Unit');
  Assert.AreEqual('EVendorBase', mItem.Unreachable, 'früherer Zweig fängt schon den Vorfahren');
  Assert.AreEqual(mLoads, FIndex.LazyStats.Loads, 'die Nachbearbeitung lädt keine kalte Unit nach');
  Assert.AreEqual(2, FIndex.LazyStats.Cold, 'beide Units weiter kalt');
end;

procedure TCompletionL3Tests.AttributeListLoadsNoColdUnit;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mLoads: Integer;
begin
  mLoads := FIndex.LazyStats.Loads;
  mItems := ItemsAt('A:[VendorM|', nil);
  Assert.IsTrue(Find(mItems, 'VendorMark', mItem), 'Attributklasse aus kalter Unit ohne Endung');
  Assert.IsTrue(mItem.Attribute, 'als Attribut');
  Assert.AreEqual('Vendor.Base', mItem.Detail, 'Unit als Detail');
  Assert.AreEqual(1, Integer(Length(mItem.AdditionalEdits)), 'mit uses-Eintrag');
  Assert.AreEqual(mLoads, FIndex.LazyStats.Loads, 'die Nachbearbeitung lädt keine kalte Unit nach');
  Assert.AreEqual(2, FIndex.LazyStats.Cold, 'beide Units weiter kalt');
end;

procedure TCompletionL3Tests.IncludeOffersFilesOfFolder;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  Assert.IsTrue(DirectiveAt('{$I |', mItems), 'Dateinamen nach {$I');
  Assert.IsTrue(Find(mItems, 'Vendor.inc', mItem), 'Vendor.inc');
  Assert.IsTrue(mItem.HasTextEdit, 'per textEdit');
  Assert.AreEqual(2, mItem.TextEdit.Range.StartPos.Line, 'Zeile');
  Assert.AreEqual(4, mItem.TextEdit.Range.StartPos.Character, 'ab dem Namen');
  Assert.AreEqual(4, mItem.TextEdit.Range.EndPos.Character, 'bis zum Cursor');
  Assert.AreEqual('Vendor.inc', mItem.TextEdit.NewText, 'eingefügter Name');
  Assert.IsTrue(Find(mItems, 'Other.inc', mItem), 'Other.inc');
  Assert.IsFalse(Find(mItems, 'readme.txt', mItem), 'nur .inc');
  Assert.IsTrue(DirectiveAt('{$INCLUDE ''Ven|', mItems), 'mit Anführungszeichen');
  Assert.IsTrue(Find(mItems, 'Vendor.inc', mItem), 'Vendor.inc in Anführungszeichen');
  Assert.AreEqual(11, mItem.TextEdit.Range.StartPos.Character, 'ab dem Namen hinter dem Anführungszeichen');
end;

procedure TCompletionL3Tests.IncludeWithSubfolder;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  Assert.IsTrue(DirectiveAt('{$INCLUDE sub\D|', mItems), 'Unterordner');
  Assert.IsTrue(Find(mItems, 'sub\Deep.inc', mItem), 'Datei samt Ordner');
  Assert.AreEqual('sub\Deep.inc', mItem.TextEdit.NewText, 'eingefügt samt Ordner');
  Assert.AreEqual(10, mItem.TextEdit.Range.StartPos.Character, 'ab dem Ordner');
  Assert.AreEqual('Deep.inc', mItem.FilterText, 'gefiltert über den Dateinamen');
  Assert.IsFalse(Find(mItems, 'Vendor.inc', mItem), 'nur der getippte Ordner');
end;

procedure TCompletionL3Tests.IncludeOffersKnownIncludeFolders;
var
  mUnit: TUnitIndex;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  // Die Unit bindet schon eine Datei aus einem Ordner der Suchpfade ein (außerhalb ihres Ordners).
  mUnit := Default(TUnitIndex);
  mUnit.UnitName := 'Haupt';
  mUnit.FileName := ProjectFile;
  mUnit.Includes := [TPath.Combine(FFolder, 'shared\Common.inc')];
  FIndex.AddUnit(mUnit);
  Assert.IsTrue(DirectiveAt('{$I |', mItems), 'Dateinamen nach {$I');
  Assert.IsTrue(Find(mItems, 'Common.inc', mItem), 'aus dem Ordner der bekannten Include-Datei');
  Assert.IsTrue(Find(mItems, 'Vendor.inc', mItem), 'und aus dem eigenen Ordner');
end;

procedure TCompletionL3Tests.IncludeSwitchIsNoFileName;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  DirectiveAt('{$I+|', mItems);
  Assert.IsFalse(Find(mItems, 'Vendor.inc', mItem), '{$I+ ist der Schalter');
  DirectiveAt('{$IFDEF |', mItems);
  Assert.IsFalse(Find(mItems, 'Vendor.inc', mItem), '{$IFDEF');
  DirectiveAt('{$I Vendor.inc |', mItems);
  Assert.IsFalse(Find(mItems, 'Other.inc', mItem), 'hinter dem Namen');
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionL3Tests);

end.
