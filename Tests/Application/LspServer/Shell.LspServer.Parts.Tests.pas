unit Shell.LspServer.Parts.Tests;

// Teile von dpcc.LspServer ohne laufenden Server: Abbildung der IDE-Einstellungen (dccOptions, dllname,
// browsingPaths, CommonAppData) auf den Projektkontext, Befehlszeile und Ablageort, Formate des RAD-Studio-Dialekts
// (detail, DCC_Flags, Parameterhilfe, Hover, Capabilities) und der Baum für documentSymbol. Alle Daten synthetisch
// nach dem gemessenen Format.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspServerPartsTests = class
  public
    [Test]
    procedure VersionAndPlatformFromDllName;
    /// <summary>dccOptions: Defines, Namespaces, Aliase, Include-Pfade; -U geteilt in Bibliothek (Studio-Ordner) und
    /// Suchpfad des Projekts; Anführungszeichen mit Leerzeichen; Ausgabeschalter übergangen.</summary>
    [Test]
    procedure DccOptionsToContext;
    [Test]
    procedure ContextJsonForProjectContext;
    [Test]
    procedure SettingsWithoutProject;
    [Test]
    procedure RegistryKeyOfProfileFolder;
    /// <summary>Ablage: --cache-root vor Umgebungsvariable vor LOCALAPPDATA\dpcc.LspServer; fremde Parameter
    /// (Pfad von DelphiLSP, -LogModes) werden übergangen.</summary>
    [Test]
    procedure CacheRootPrecedence;
    [Test]
    procedure DccFlagsAsMeasured;
    [Test]
    procedure DetailAsDelphiLsp;
    /// <summary>Parameterhilfe: Bereich im Label wird Text, documentation in Signatur (html) und Parameter (xml).
    /// </summary>
    [Test]
    procedure SignatureHelpForIde;
    [Test]
    procedure HoverAsPlainString;
    [Test]
    procedure CapabilitiesOnlyWhatServerCan;
    /// <summary>documentSymbol: Abschnitte, Klasse mit Feld, Property und Methoden, Record, Aufzählung, Routinen
    /// im interface und im implementation-Teil, Bereiche wie DelphiLSP.</summary>
    [Test]
    procedure DocumentSymbolTree;
    [Test]
    procedure DocumentSymbolOfProgram;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  dpcc.Common.Logging.Contract,
  dpcc.Common.Index.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Pascal.Parser,
  Shell.LspServer.Options,
  Shell.LspServer.RadStudio.Settings,
  Shell.LspServer.RadStudio.Dialect,
  Shell.LspServer.DocumentSymbols;

function Parse(const AText: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(AText);
  Assert.IsNotNull(Result, 'JSON: ' + AText);
end;

function SettingsJson(const AOptions: string): string;
begin
  Result := '{"settings":{"project":"file:///C%3A/Arbeit/Demo/DemoProj.dpr","dllname":"dcc32370.dll",' +
    '"dccOptions":"' + StringReplace(StringReplace(AOptions, '\', '\\', [rfReplaceAll]), '"', '\"', [rfReplaceAll]) +
    '","projectFiles":[{"name":"uDemo","file":"file:///C%3A/Arbeit/Demo/uDemo.pas"}],' +
    '"browsingPaths":["file:///c%3A/programme/embarcadero/studio/37.0/source/rtl/sys",' +
    '"file:///c%3A/programme/embarcadero/studio/37.0/SOURCE/VCL"],' +
    '"CommonAppData":"file:///C%3A/Benutzer/Test/AppData/Roaming/Embarcadero/BDS/37.0/"}}';
end;

procedure TLspServerPartsTests.VersionAndPlatformFromDllName;
begin
  Assert.AreEqual('23.0', TRadStudioProject.VersionOfDll('dcc32290.dll'), 'Delphi 12');
  Assert.AreEqual('37.0', TRadStudioProject.VersionOfDll('dcc32370.dll'), 'Delphi 13');
  Assert.AreEqual('22.0', TRadStudioProject.VersionOfDll('dcc32280.dll'), 'Delphi 11');
  Assert.AreEqual('37.0', TRadStudioProject.VersionOfDll('C:\x\dcc64370.dll'), 'mit Pfad');
  Assert.AreEqual('', TRadStudioProject.VersionOfDll('dcc.dll'), 'ohne Nummer');
  Assert.AreEqual('Win32', TRadStudioProject.PlatformOfDll('dcc32370.dll'));
  Assert.AreEqual('Win64', TRadStudioProject.PlatformOfDll('dcc64370.dll'));
  Assert.AreEqual('Android64', TRadStudioProject.PlatformOfDll('dccaarm64370.dll'));
  Assert.AreEqual('', TRadStudioProject.PlatformOfDll('anders.dll'));
end;

procedure TLspServerPartsTests.DccOptionsToContext;
var
  mJson: TJSONValue;
  mProject: TRadStudioProject;
begin
  mJson := Parse(SettingsJson('-$O- --no-config -Q -TX.exe ' +
    '-AGenerics.Collections=System.Generics.Collections;WinTypes=Winapi.Windows -DDEBUG;Demo -E.\out ' +
    '-I"c:\programme\embarcadero\studio\37.0\lib\Win32\release";c:\inc ' +
    '-LEC:\Users\Public\Documents\Embarcadero\Studio\37.0\Bpl -NU.\out\dcu ' +
    '-NSWinapi;System.Win;System; -O"c:\x y\obj" ' +
    '-U"c:\programme\embarcadero\studio\37.0\lib\Win32\release";C:\Users\Public\Documents\Embarcadero\Studio\37.0\Dcp;' +
    '.\extra;"C:\Komponenten mit Leerzeichen\Quelle" -NBC:\dcp -LU'));
  try
    mProject := TRadStudioProject.FromSettings(mJson);
  finally
    mJson.Free;
  end;
  Assert.IsTrue(mProject.HasProject);
  Assert.AreEqual('C:\Arbeit\Demo\DemoProj.dpr', mProject.MainFile);
  Assert.AreEqual('C:\Arbeit\Demo\DemoProj.dproj', mProject.ProjectFile);
  Assert.AreEqual('37.0', mProject.BdsVersion);
  Assert.AreEqual('Win32', mProject.Platform);
  Assert.AreEqual('DEBUG;DEMO', string.Join(';', mProject.Defines), 'Defines groß');
  Assert.AreEqual('Winapi;System.Win;System', string.Join(';', mProject.Namespaces));
  Assert.AreEqual(2, Length(mProject.Aliases), 'Aliase');
  Assert.AreEqual(2, Length(mProject.IncludePaths), 'Include-Pfade');
  Assert.AreEqual('.\extra;C:\Komponenten mit Leerzeichen\Quelle', string.Join(';', mProject.SearchPaths),
    'Suchpfad des Projekts');
  Assert.AreEqual(2, Length(mProject.LibraryPaths), 'Bibliothek aus den Studio-Ordnern');
  Assert.AreEqual('c:\programme\embarcadero\studio\37.0\source\rtl\sys', mProject.BrowsingPaths[0],
    'Browsing Path als Pfad');
  Assert.AreEqual('Software\Embarcadero\BDS\37.0', mProject.RegistryKey, 'Profil');
  Assert.AreEqual(1, mProject.UnitCount);
end;

procedure TLspServerPartsTests.ContextJsonForProjectContext;
var
  mJson: TJSONValue;
  mContext: TJSONObject;
  mProject: TRadStudioProject;
begin
  mJson := Parse(SettingsJson('-DDEBUG -NSSystem -U.\extra'));
  try
    mProject := TRadStudioProject.FromSettings(mJson);
  finally
    mJson.Free;
  end;
  mContext := mProject.ToContextJson;
  try
    // Format von dpcc/projectContext (dpcc.Common.Lsp.IdeProject).
    Assert.AreEqual('C:\Arbeit\Demo\DemoProj.dproj', mContext.GetValue<string>('project'));
    Assert.AreEqual('37.0', mContext.GetValue<string>('bdsVersion'));
    Assert.AreEqual('Win32', mContext.GetValue<string>('platform'));
    Assert.AreEqual('DEBUG', mContext.GetValue<string>('defines[0]'));
    Assert.AreEqual('.\extra', mContext.GetValue<string>('searchPaths[0]'));
    Assert.AreEqual('System', mContext.GetValue<string>('namespaces[0]'));
    Assert.AreEqual(2, mContext.GetValue<TJSONArray>('browsingPaths').Count);
    Assert.AreEqual('Software\Embarcadero\BDS\37.0', mContext.GetValue<string>('registryKey'));
    Assert.IsTrue(mContext.GetValue<Boolean>('active'));
  finally
    mContext.Free;
  end;
end;

procedure TLspServerPartsTests.SettingsWithoutProject;
var
  mJson: TJSONValue;
begin
  // VS Code und andere Clients: nur der Abschnitt dpcc.
  mJson := Parse('{"settings":{"dpcc":{"completion":{}}}}');
  try
    Assert.IsFalse(TRadStudioProject.FromSettings(mJson).HasProject);
  finally
    mJson.Free;
  end;
  Assert.IsFalse(TRadStudioProject.FromSettings(nil).HasProject);
end;

procedure TLspServerPartsTests.RegistryKeyOfProfileFolder;
begin
  Assert.AreEqual('Software\Embarcadero\Testprofil\23.0',
    TRadStudioProject.RegistryKeyOfAppData('C:\Benutzer\X\AppData\Roaming\Embarcadero\Testprofil\23.0\'));
  Assert.AreEqual('', TRadStudioProject.RegistryKeyOfAppData('C:\Benutzer\X\AppData\Roaming\Anders\23.0'));
end;

procedure TLspServerPartsTests.CacheRootPrecedence;
var
  mOptions: TLspServerOptions;
begin
  mOptions := TLspServerOptions.Parse(['C:\x\DelphiLSP.exe', '-LogModes', '0', '--cache-root', 'C:\Ablage\A'],
    'C:\Ablage\B', 'C:\Lokal');
  Assert.AreEqual('C:\Ablage\A', mOptions.CacheRoot, 'Parameter zuerst');
  mOptions := TLspServerOptions.Parse(['--cache-root=C:\Ablage\C\'], '', 'C:\Lokal');
  Assert.AreEqual('C:\Ablage\C', mOptions.CacheRoot, 'mit =');
  mOptions := TLspServerOptions.Parse(['-Name', 'Agent0'], 'C:\Ablage\B', 'C:\Lokal');
  Assert.AreEqual('C:\Ablage\B', mOptions.CacheRoot, 'Umgebungsvariable');
  mOptions := TLspServerOptions.Parse([], '', 'C:\Lokal');
  Assert.AreEqual('C:\Lokal\dpcc.LspServer', mOptions.CacheRoot, 'eigener Ordner, nicht der des Plugins');
  Assert.AreEqual('C:\Lokal\dpcc.LspServer\Logs\LspServer', mOptions.LogFolder);
  mOptions := TLspServerOptions.Parse(['--log-level', 'debug', '--no-log'], '', 'C:\Lokal');
  Assert.IsTrue(mOptions.NoLog);
  Assert.IsTrue(mOptions.LogLevel = TLogLevel.Debug, 'debug');
end;

function Symbol(AKind: TIndexSymbolKind; const AName, ASignature, ATypeName: string;
  const ADirectives: TArray<string>): TIndexSymbol;
begin
  Result := Default(TIndexSymbol);
  Result.Kind := AKind;
  Result.Name := AName;
  Result.Signature := ASignature;
  Result.TypeName := ATypeName;
  Result.Directives := ADirectives;
end;

procedure TLspServerPartsTests.DccFlagsAsMeasured;
var
  mFlags: Int64;
  mSymbol: TIndexSymbol;
begin
  // Werte aus dem Mitschnitt von DelphiLSP (TObject in Delphi 12/13).
  Assert.IsTrue(TRadStudioDialect.DccFlagsOf(Symbol(TIndexSymbolKind.Field, 'FWert', 'FWert: Integer;', 'Integer',
    nil), mFlags));
  Assert.AreEqual(Int64(19), mFlags, 'Feld');
  TRadStudioDialect.DccFlagsOf(Symbol(TIndexSymbolKind.Method, 'Free', 'procedure Free;', '', nil), mFlags);
  Assert.AreEqual(Int64(52), mFlags, 'Prozedur');
  TRadStudioDialect.DccFlagsOf(Symbol(TIndexSymbolKind.Method, 'ClassType', 'function ClassType: TClass; inline;',
    'TClass', ['inline']), mFlags);
  Assert.AreEqual(Int64(53), mFlags, 'Funktion, inline ohne eigenes Bit');
  TRadStudioDialect.DccFlagsOf(Symbol(TIndexSymbolKind.Constructor_, 'Create', 'constructor Create;', '', nil),
    mFlags);
  Assert.AreEqual(Int64(131124), mFlags, 'Konstruktor');
  mSymbol := Symbol(TIndexSymbolKind.Method, 'Destroy', 'destructor Destroy; virtual;', '', ['virtual',
    'destructor']);
  mSymbol.IsVirtual := True;
  TRadStudioDialect.DccFlagsOf(mSymbol, mFlags);
  Assert.AreEqual(Int64(262708), mFlags, 'Destruktor, virtual');
  TRadStudioDialect.DccFlagsOf(Symbol(TIndexSymbolKind.Method, 'ClassName', 'class function ClassName: string;',
    'string', nil), mFlags);
  Assert.AreEqual(Int64(8388661), mFlags, 'Klassenmethode');
  TRadStudioDialect.DccFlagsOf(Symbol(TIndexSymbolKind.Method, 'MethodAddress',
    'class function MethodAddress(const Name: string): Pointer; overload;', 'Pointer', ['overload']), mFlags);
  Assert.AreEqual(Int64(75497525), mFlags, 'Klassenmethode, overload');
  TRadStudioDialect.DccFlagsOf(Symbol(TIndexSymbolKind.Method, 'DisposeOf', 'procedure DisposeOf; inline; ' +
    'deprecated ''Use Free instead'';', '', ['inline', 'deprecated']), mFlags);
  Assert.AreEqual(Int64(268435508), mFlags, 'deprecated');
  mSymbol := Symbol(TIndexSymbolKind.Property_, 'Disposed', 'property Disposed: Boolean read GetDisposed;',
    'Boolean', nil);
  mSymbol.Visibility := TIndexVisibility.Protected;
  TRadStudioDialect.DccFlagsOf(mSymbol, mFlags);
  Assert.AreEqual(Int64(33816), mFlags, 'Property, protected');
  Assert.IsFalse(TRadStudioDialect.DccFlagsOf(Symbol(TIndexSymbolKind.ClassType, 'TDemo', 'TDemo = class', '', nil),
    mFlags), 'Typen: kein gemessener Wert');
end;

procedure TLspServerPartsTests.DetailAsDelphiLsp;
begin
  Assert.AreEqual(': Integer;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.Field, 'FWert', '', 'Integer',
    nil)));
  Assert.AreEqual('(const A: Integer): Integer;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.Method,
    'Twice', 'function Twice(const A: Integer): Integer; overload;', 'Integer', nil)));
  Assert.AreEqual(';', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.Method, 'Reset', 'procedure Reset;', '',
    nil)));
  Assert.AreEqual(': TClass;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.Method, 'ClassType',
    'function ClassType: TClass; inline;', 'TClass', nil)));
  Assert.AreEqual('(Instance: Pointer): TObject;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.Method,
    'InitInstance', 'class function InitInstance(Instance: Pointer): TObject;', 'TObject', nil)));
end;

procedure TLspServerPartsTests.SignatureHelpForIde;
var
  mServer: TJSONValue;
  mAnswer: TJSONValue;
begin
  mServer := Parse('{"signatures":[{"label":"function Twice(const A: Integer; B: string): Integer",' +
    '"documentation":{"kind":"markdown","value":"**Verdoppelt** A"},"parameters":[{"label":[15,31]},' +
    '{"label":[33,42],"documentation":"Text"}]}],"activeSignature":0,"activeParameter":1}');
  try
    mAnswer := TRadStudioDialect.SignatureAnswer(mServer);
    try
      Assert.AreEqual('html', mAnswer.GetValue<string>('signatures[0].documentation.kind'));
      Assert.AreEqual('<html><body>Verdoppelt A</body></html>',
        mAnswer.GetValue<string>('signatures[0].documentation.value'));
      Assert.AreEqual('const A: Integer', mAnswer.GetValue<string>('signatures[0].parameters[0].label'));
      Assert.AreEqual('B: string', mAnswer.GetValue<string>('signatures[0].parameters[1].label'));
      Assert.AreEqual('xml', mAnswer.GetValue<string>('signatures[0].parameters[0].documentation.kind'));
      Assert.AreEqual('', mAnswer.GetValue<string>('signatures[0].parameters[0].documentation.value'));
      Assert.AreEqual('Text', mAnswer.GetValue<string>('signatures[0].parameters[1].documentation.value'));
      Assert.AreEqual(1, mAnswer.GetValue<Integer>('activeParameter'));
    finally
      mAnswer.Free;
    end;
  finally
    mServer.Free;
  end;
end;

procedure TLspServerPartsTests.HoverAsPlainString;
var
  mServer, mAnswer: TJSONValue;
begin
  mServer := Parse('{"contents":{"kind":"markdown","value":"```pascal\nfunction Twice: Integer;\n```\n---\n' +
    '**Doku** mit `Code`"},"dpcc":{"name":"Twice"}}');
  try
    mAnswer := TRadStudioDialect.HoverAnswer(mServer);
    try
      Assert.AreEqual('function Twice: Integer;'#13#10'Doku mit Code', mAnswer.GetValue<string>('contents'));
      Assert.IsNull(TJSONObject(mAnswer).GetValue('dpcc'), 'ohne dpcc-Teile');
    finally
      mAnswer.Free;
    end;
  finally
    mServer.Free;
  end;
end;

procedure TLspServerPartsTests.CapabilitiesOnlyWhatServerCan;
var
  mServer: TJSONValue;
  mCaps: TJSONObject;
begin
  mServer := Parse('{"textDocumentSync":{"change":2},"completionProvider":{"triggerCharacters":["."]},' +
    '"hoverProvider":true,"definitionProvider":true,"experimental":{"dpcc":{}}}');
  try
    mCaps := TRadStudioDialect.RadCapabilities(TJSONObject(mServer));
    try
      Assert.AreEqual(1, mCaps.GetValue<Integer>('textDocumentSync'));
      Assert.AreEqual(4, mCaps.GetValue<TJSONArray>('completionProvider.triggerCharacters').Count);
      Assert.IsTrue(mCaps.GetValue<Boolean>('documentSymbolProvider'));
      Assert.IsTrue(mCaps.GetValue<Boolean>('definitionProvider'));
      Assert.IsNull(mCaps.GetValue('declarationProvider'), 'nur was der Server meldet');
      Assert.IsNull(mCaps.GetValue('signatureHelpProvider'));
      Assert.IsNull(mCaps.GetValue('experimental'));
    finally
      mCaps.Free;
    end;
  finally
    mServer.Free;
  end;
end;

const
  cUnit =
    'unit uProbe;'#13#10 +                                   // 0
    ''#13#10 +                                               // 1
    'interface'#13#10 +                                      // 2
    ''#13#10 +                                               // 3
    'type'#13#10 +                                           // 4
    '  TProbe = class'#13#10 +                               // 5
    '  public'#13#10 +                                       // 6
    '    FValue, FOther: Integer;'#13#10 +                   // 7
    '    function Twice(const A: Integer): Integer;'#13#10 + // 8
    '    procedure Reset;'#13#10 +                           // 9
    '    constructor Create;'#13#10 +                        // 10
    '    property Value: Integer read FValue;'#13#10 +       // 11
    '  end;'#13#10 +                                         // 12
    '  TPunkt = record'#13#10 +                              // 13
    '    X: Integer;'#13#10 +                                // 14
    '  end;'#13#10 +                                         // 15
    '  TFarbe = (Rot, Gruen);'#13#10 +                       // 16
    ''#13#10 +                                               // 17
    'procedure Run;'#13#10 +                                 // 18
    ''#13#10 +                                               // 19
    'implementation'#13#10 +                                 // 20
    ''#13#10 +                                               // 21
    'function TProbe.Twice(const A: Integer): Integer;'#13#10 + // 22
    'begin'#13#10 +                                          // 23
    '  Result := A * 2;'#13#10 +                             // 24
    'end;'#13#10 +                                           // 25
    ''#13#10 +                                               // 26
    'procedure TProbe.Reset;'#13#10 +                        // 27
    'begin'#13#10 +                                          // 28
    'end;'#13#10 +                                           // 29
    ''#13#10 +                                               // 30
    'constructor TProbe.Create;'#13#10 +                     // 31
    'begin'#13#10 +                                          // 32
    'end;'#13#10 +                                           // 33
    ''#13#10 +                                               // 34
    'procedure Run;'#13#10 +                                 // 35
    'begin'#13#10 +                                          // 36
    'end;'#13#10 +                                           // 37
    ''#13#10 +                                               // 38
    'end.'#13#10;

function RangeText(AValue: TJSONValue; const APath: string): string;
begin
  Result := Format('%d:%d-%d:%d', [AValue.GetValue<Integer>(APath + '.start.line'),
    AValue.GetValue<Integer>(APath + '.start.character'), AValue.GetValue<Integer>(APath + '.end.line'),
    AValue.GetValue<Integer>(APath + '.end.character')]);
end;

procedure TLspServerPartsTests.DocumentSymbolTree;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
  mInterface, mImplementation, mClass: TJSONValue;
begin
  mTree := TPascalParser.Parse(cUnit);
  try
    mSymbols := TLspDocumentSymbols.Build(mTree, cUnit);
  finally
    mTree.Free;
  end;
  try
    Assert.AreEqual(2, mSymbols.Count, 'zwei Abschnitte');
    mInterface := mSymbols.Items[0];
    Assert.AreEqual('interface', mInterface.GetValue<string>('name'));
    Assert.AreEqual(2, mInterface.GetValue<Integer>('kind'));
    Assert.AreEqual('section', mInterface.GetValue<string>('detail'));
    Assert.AreEqual('2:0-18:13', RangeText(mInterface, 'range'), 'bis zur letzten Deklaration');
    mClass := mInterface.GetValue<TJSONArray>('children').Items[0];
    Assert.AreEqual('TProbe', mClass.GetValue<string>('name'));
    Assert.AreEqual(5, mClass.GetValue<Integer>('kind'));
    Assert.AreEqual('5:11-12:5', RangeText(mClass, 'range'), 'vom Wort class bis end');
    Assert.AreEqual('FValue: Integer', mClass.GetValue<string>('children[0].name'));
    Assert.AreEqual(8, mClass.GetValue<Integer>('children[0].kind'));
    Assert.AreEqual('7:4-7:10', RangeText(mClass, 'children[0].range'), 'nur der Name');
    Assert.AreEqual('FOther: Integer', mClass.GetValue<string>('children[1].name'), 'zweiter Name einzeln');
    Assert.AreEqual('Twice(const A: Integer): Integer', mClass.GetValue<string>('children[2].name'));
    Assert.AreEqual('declaration', mClass.GetValue<string>('children[2].detail'));
    Assert.AreEqual(6, mClass.GetValue<Integer>('children[2].kind'));
    Assert.AreEqual('8:13-8:45', RangeText(mClass, 'children[2].range'), 'Name bis Ergebnistyp');
    Assert.AreEqual('Reset', mClass.GetValue<string>('children[3].name'));
    Assert.AreEqual('9:14-9:19', RangeText(mClass, 'children[3].range'));
    Assert.AreEqual(9, mClass.GetValue<Integer>('children[4].kind'), 'Konstruktor');
    Assert.AreEqual('Value: Integer', mClass.GetValue<string>('children[5].name'));
    Assert.AreEqual(7, mClass.GetValue<Integer>('children[5].kind'), 'Property');
    Assert.AreEqual('TPunkt', mInterface.GetValue<string>('children[1].name'));
    Assert.AreEqual(23, mInterface.GetValue<Integer>('children[1].kind'), 'Record');
    Assert.AreEqual('X: Integer', mInterface.GetValue<string>('children[1].children[0].name'));
    Assert.AreEqual(10, mInterface.GetValue<Integer>('children[2].kind'), 'Aufzählung');
    Assert.AreEqual('Run', mInterface.GetValue<string>('children[3].name'));
    Assert.AreEqual('18:10-18:13', RangeText(mInterface, 'children[3].range'));
    mImplementation := mSymbols.Items[1];
    Assert.AreEqual('implementation', mImplementation.GetValue<string>('name'));
    Assert.AreEqual('TProbe.Twice(const A: Integer): Integer',
      mImplementation.GetValue<string>('children[0].name'));
    Assert.AreEqual('implementation', mImplementation.GetValue<string>('children[0].detail'));
    Assert.AreEqual('22:0-25:3', RangeText(mImplementation, 'children[0].range'), 'Schlüsselwort bis end');
    Assert.AreEqual('TProbe.Reset', mImplementation.GetValue<string>('children[1].name'));
    Assert.AreEqual('Run', mImplementation.GetValue<string>('children[3].name'));
    Assert.AreEqual(0, mImplementation.GetValue<TJSONArray>('children[3].children').Count, 'Blatt mit children');
  finally
    mSymbols.Free;
  end;
end;

procedure TLspServerPartsTests.DocumentSymbolOfProgram;
const
  cProgram = 'program Demo;'#13#10'uses SysUtils;'#13#10'var Zahl: Integer;'#13#10 +
    'procedure Tu;'#13#10'begin'#13#10'end;'#13#10'begin'#13#10'  Tu;'#13#10'end.'#13#10;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(cProgram);
  try
    mSymbols := TLspDocumentSymbols.Build(mTree, cProgram);
  finally
    mTree.Free;
  end;
  try
    Assert.AreEqual(2, mSymbols.Count, 'Variable und Routine ohne Abschnitt');
    Assert.AreEqual('Zahl: Integer', mSymbols.Items[0].GetValue<string>('name'));
    Assert.AreEqual(13, mSymbols.Items[0].GetValue<Integer>('kind'));
    Assert.AreEqual('Tu', mSymbols.Items[1].GetValue<string>('name'));
    Assert.AreEqual('implementation', mSymbols.Items[1].GetValue<string>('detail'));
  finally
    mSymbols.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspServerPartsTests);

end.
