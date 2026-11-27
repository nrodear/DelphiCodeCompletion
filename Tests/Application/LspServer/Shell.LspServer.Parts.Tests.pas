unit Shell.LspServer.Parts.Tests;

// Teile von dpcc.LspServer ohne laufenden Server: Abbildung der IDE-Einstellungen (dccOptions, dllname,
// browsingPaths, CommonAppData) auf den Projektkontext, Befehlszeile und Ablageort, Formate des RAD-Studio-Dialekts
// (kind, detail, DCC_Flags, Kopfzeilen, Parameterhilfe, Hover-HTML, kibitzkind, Capabilities) und der Baum für
// documentSymbol. Dazu der Übersetzer über einem Transport ohne Server (Wiedergabe der IDE): Vervollständigung mit
// hexadezimalem sortText, einzelnen Überladungen und ohne nicht geltende Zweige, resolve mit dem Eintrag der Liste,
// Sprungziele als ein Location-Objekt in der Schreibweise der IDE. Alle Daten synthetisch nach dem am 27.11.2026
// gemessenen Format (Stellvertreter in der IDE, DelphiLSP in Delphi 12 und 13).

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
    /// <summary>Tabelle der DCC_Flags je Art (Mitglieder, Routinen, Typen, Konstanten, Aufzählungen).</summary>
    [Test]
    procedure DccFlagsAsMeasured;
    /// <summary>kind der IDE je Art: Destruktor 2, Alias 12, Zeiger 18, reference to 8 …</summary>
    [Test]
    procedure KindsAsMeasured;
    [Test]
    procedure DetailAsDelphiLsp;
    /// <summary>Parameterlisten einzeln mit Typ (Gruppen aufgelöst) und Routinenköpfe zerlegt.</summary>
    [Test]
    procedure ParametersResolved;
    /// <summary>Kopfzeile des Hovers je Art wie DelphiLSP.</summary>
    [Test]
    procedure HoverCaptionAsMeasured;
    /// <summary>Parameterhilfe: label ohne Gruppen, Parameter einzeln mit Typ, documentation im Gerüst doppelt
    /// maskiert (wörtlich \r\n und \"), Parameter-Doku kind xml.</summary>
    [Test]
    procedure SignatureHelpForIde;
    /// <summary>Hover-HTML byte-genau (CRLF, Tabs vor dem Verweis) für Methode mit Doku, lokale Variable und Klasse
    /// mit Remarks; contents ist ein String ohne range.</summary>
    [Test]
    procedure HoverHtmlAsMeasured;
    [Test]
    procedure KibitzKindByContext;
    [Test]
    procedure CapabilitiesOnlyWhatServerCan;
    /// <summary>Vervollständigung über den Übersetzer: Form der Einträge, Überladungen einzeln, nicht geltende Zweige
    /// und Einträge mit Änderungen weg, lokale Variable, Schlüsselwort hinten; danach resolve.</summary>
    [Test]
    procedure CompletionReplayAsMeasured;
    /// <summary>sortText-Breite nach der Anzahl, kibitzkind 7 und 15, Units als kind 17.</summary>
    [Test]
    procedure CompletionSortTextAndKibitz;
    /// <summary>definition, implementation, declaration: ein Location-Objekt, URI wie von der IDE geöffnet, leere
    /// Liste und null als null.</summary>
    [Test]
    procedure LocationsAsSingleObject;
    /// <summary>Anderer Client: Antworten und Anfragen unverändert.</summary>
    [Test]
    procedure StandardClientUnchanged;
    /// <summary>documentSymbol: Abschnitte, Klasse mit Feld, Property und Methoden, Record, Aufzählung, Routinen
    /// im interface und im implementation-Teil, Bereiche wie DelphiLSP.</summary>
    [Test]
    procedure DocumentSymbolTree;
    /// <summary>uses-Abschnitt mit den Units in interface und implementation.</summary>
    [Test]
    procedure DocumentSymbolUses;
    [Test]
    procedure DocumentSymbolOfProgram;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  dpcc.Common.Logging.Contract,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Index.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Pascal.Parser,
  Shell.LspServer.Options,
  Shell.LspServer.RadStudio.Settings,
  Shell.LspServer.RadStudio.Dialect,
  Shell.LspServer.DocumentSymbols;

const
  cProbeFile = 'C:\Projekt\uMain.pas';
  cProbeFileJson = 'C:\\Projekt\\uMain.pas';
  cProbeUri = 'file:///C%3A/Projekt/uMain.pas';

type
  /// <summary>Transport ohne Server: Nachrichten der IDE aus einer Warteschlange, Geschriebenes in einer Liste.
  /// </summary>
  TFakeTransport = class(TInterfacedObject, IJsonRpcTransport)
  private
    FInput: TQueue<string>;
    FOutput: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
    property Input: TQueue<string> read FInput;
    property Output: TList<string> read FOutput;
  end;

  /// <summary>Übersetzer über TFakeTransport, nach initialize mit AClientName.</summary>
  TDialectSession = class
  private
    FFake: TFakeTransport;
    FTransport: IJsonRpcTransport;
    FDialect: TRadStudioDialect;
    FDialectRef: IJsonRpcTransport;
  public
    constructor Create(const AClientName: string);
    destructor Destroy; override;
    /// <summary>Nachricht der IDE durch den Übersetzer; der Aufrufer gibt das Ergebnis frei.</summary>
    function FromIde(const AJson: string): TJSONObject;
    /// <summary>Antwort des Servers durch den Übersetzer; liefert, was bei der IDE ankommt (der Aufrufer gibt es
    /// frei).</summary>
    function FromServer(const AJson: string): TJSONObject;
    procedure Open(const AUri, AText: string);
    property Dialect: TRadStudioDialect read FDialect;
  end;

function Parse(const AText: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(AText);
  Assert.IsNotNull(Result, 'JSON: ' + AText);
end;

function ParseObject(const AText: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  Result := nil;
  mValue := Parse(AText);
  if mValue is TJSONObject then
  begin
    Exit(TJSONObject(mValue));
  end;
  mValue.Free;
  Assert.Fail('Kein JSON-Objekt: ' + AText);
end;

{ TFakeTransport }

constructor TFakeTransport.Create;
begin
  inherited Create;
  FInput := TQueue<string>.Create;
  FOutput := TList<string>.Create;
end;

destructor TFakeTransport.Destroy;
begin
  FOutput.Free;
  FInput.Free;
  inherited;
end;

function TFakeTransport.ReadMessage: TJSONObject;
begin
  Result := ParseObject(FInput.Dequeue);
end;

procedure TFakeTransport.WriteMessage(const AMessage: TJSONObject);
begin
  FOutput.Add(AMessage.ToJSON);
end;

{ TDialectSession }

constructor TDialectSession.Create(const AClientName: string);
begin
  inherited Create;
  FFake := TFakeTransport.Create;
  // Die Schnittstellen halten Transport und Übersetzer; freigegeben wird über sie.
  FTransport := FFake;
  FDialect := TRadStudioDialect.Create(FTransport);
  FDialectRef := FDialect;
  FromIde('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":0,"clientInfo":{"name":"' +
    AClientName + '"},"capabilities":{}}}').Free;
end;

destructor TDialectSession.Destroy;
begin
  FDialectRef := nil;
  FTransport := nil;
  inherited;
end;

function TDialectSession.FromIde(const AJson: string): TJSONObject;
begin
  FFake.Input.Enqueue(AJson);
  Result := FDialect.ReadMessage;
end;

function TDialectSession.FromServer(const AJson: string): TJSONObject;
var
  mMessage: TJSONObject;
  mCount: Integer;
begin
  mCount := FFake.Output.Count;
  mMessage := ParseObject(AJson);
  try
    FDialect.WriteMessage(mMessage);
  finally
    mMessage.Free;
  end;
  Assert.AreEqual(mCount + 1, FFake.Output.Count, 'eine Nachricht an die IDE');
  Result := ParseObject(FFake.Output.Last);
end;

procedure TDialectSession.Open(const AUri, AText: string);
var
  mMessage, mParams, mDocument: TJSONObject;
begin
  mDocument := TJSONObject.Create;
  mDocument.AddPair('uri', AUri);
  mDocument.AddPair('languageId', 'pascal');
  mDocument.AddPair('version', TJSONNumber.Create(1));
  mDocument.AddPair('text', AText);
  mParams := TJSONObject.Create(TJSONPair.Create('textDocument', mDocument));
  mMessage := TJSONObject.Create;
  try
    mMessage.AddPair('jsonrpc', '2.0');
    mMessage.AddPair('method', 'textDocument/didOpen');
    mMessage.AddPair('params', mParams);
    FromIde(mMessage.ToJSON).Free;
  finally
    mMessage.Free;
  end;
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

/// <summary>ASymbol im Typ AContainer mit dem Namen bei ALine/ACharacter.</summary>
function Placed(const ASymbol: TIndexSymbol; const AContainer: string; ALine, ACharacter: Integer): TIndexSymbol;
begin
  Result := ASymbol;
  Result.Container := AContainer;
  Result.SelectionRange := TTextRange.Create(ALine, ACharacter, ALine, ACharacter + Length(ASymbol.Name));
  Result.Range := Result.SelectionRange;
end;

function FlagsOf(const ASymbol: TIndexSymbol): Int64;
begin
  Assert.IsTrue(TRadStudioDialect.DccFlagsOf(ASymbol, Result), 'DCC_Flags für ' + ASymbol.Name);
end;

procedure TLspServerPartsTests.DccFlagsAsMeasured;
var
  mFlags: Int64;
  mSymbol: TIndexSymbol;
begin
  // Werte aus den Mitschnitten von DelphiLSP (TObject, TStringList und die Testunit in Delphi 12/13).
  Assert.IsTrue(TRadStudioDialect.DccFlagsOf(Symbol(TIndexSymbolKind.Field, 'FWert', 'FWert: Integer;', 'Integer',
    nil), mFlags));
  Assert.AreEqual(Int64(19), mFlags, 'Feld');
  mSymbol := Symbol(TIndexSymbolKind.Field, 'FName', 'FName: string;', 'string', nil);
  mSymbol.Visibility := TIndexVisibility.Private;
  Assert.AreEqual(Int64($113), FlagsOf(mSymbol), 'Feld, private');
  Assert.AreEqual(Int64(52), FlagsOf(Symbol(TIndexSymbolKind.Method, 'Free', 'procedure Free;', '', nil)),
    'Prozedur');
  Assert.AreEqual(Int64(53), FlagsOf(Symbol(TIndexSymbolKind.Method, 'ClassType',
    'function ClassType: TClass; inline;', 'TClass', ['inline'])), 'Funktion, inline ohne eigenes Bit');
  Assert.AreEqual(Int64(131124), FlagsOf(Symbol(TIndexSymbolKind.Constructor_, 'Create', 'constructor Create;', '',
    nil)), 'Konstruktor');
  mSymbol := Symbol(TIndexSymbolKind.Method, 'Destroy', 'destructor Destroy; virtual;', '', ['virtual',
    'destructor']);
  mSymbol.IsVirtual := True;
  Assert.AreEqual(Int64(262708), FlagsOf(mSymbol), 'Destruktor, virtual');
  // Der Index führt Destruktoren auch als Constructor_: ohne Konstruktor-Bit.
  mSymbol := Symbol(TIndexSymbolKind.Constructor_, 'Destroy', 'destructor Destroy; override;', '', ['override',
    'destructor']);
  mSymbol.IsVirtual := True;
  Assert.AreEqual(Int64($40234), FlagsOf(mSymbol), 'Destruktor als Constructor_');
  Assert.AreEqual(Int64(8388661), FlagsOf(Symbol(TIndexSymbolKind.Method, 'ClassName',
    'class function ClassName: string;', 'string', nil)), 'Klassenmethode');
  Assert.AreEqual(Int64(75497525), FlagsOf(Symbol(TIndexSymbolKind.Method, 'MethodAddress',
    'class function MethodAddress(const Name: string): Pointer; overload;', 'Pointer', ['overload'])),
    'Klassenmethode, overload');
  Assert.AreEqual(Int64(268435508), FlagsOf(Symbol(TIndexSymbolKind.Method, 'DisposeOf', 'procedure DisposeOf; ' +
    'inline; deprecated ''Use Free instead'';', '', ['inline', 'deprecated'])), 'deprecated');
  // Property: 0x4000 mit write, 0x8000 nur lesbar (Disposed, Count), 0x200000 Array-Property.
  Assert.AreEqual(Int64($4018), FlagsOf(Symbol(TIndexSymbolKind.Property_, 'Name',
    'property Name: string read FName write FName;', 'string', nil)), 'Property mit write');
  mSymbol := Symbol(TIndexSymbolKind.Property_, 'Disposed', 'property Disposed: Boolean read GetDisposed;',
    'Boolean', nil);
  mSymbol.Visibility := TIndexVisibility.Protected;
  Assert.AreEqual(Int64(33816), FlagsOf(mSymbol), 'Property nur lesbar, protected (0x8418)');
  Assert.AreEqual(Int64($208018), FlagsOf(Symbol(TIndexSymbolKind.Property_, 'Names',
    'property Names[Index: Integer]: string read GetName;', 'string', nil)), 'Array-Property nur lesbar');
  // Globale Routinen, Variablen, Konstanten, Aufzählungen und Typen.
  Assert.AreEqual(Int64($800024), FlagsOf(Symbol(TIndexSymbolKind.Routine, 'Run', 'procedure Run;', '', nil)),
    'globale Prozedur');
  Assert.AreEqual(Int64($800025), FlagsOf(Symbol(TIndexSymbolKind.Routine, 'Helper',
    'function Helper(const S: string): Integer;', 'Integer', nil)), 'globale Funktion');
  Assert.AreEqual(Int64($4800025), FlagsOf(Symbol(TIndexSymbolKind.Routine, 'IntToStr',
    'function IntToStr(Value: Integer): string; overload;', 'string', ['overload'])), 'globale Funktion, overload');
  Assert.AreEqual(Int64($3), FlagsOf(Symbol(TIndexSymbolKind.Variable, 'GCounter', 'GCounter: TCount;', 'TCount',
    nil)), 'globale Variable');
  Assert.AreEqual(Int64($1), FlagsOf(Symbol(TIndexSymbolKind.Constant, 'cMaxCount', 'cMaxCount = 42;', '', nil)),
    'Konstante');
  Assert.AreEqual(Int64($10000001), FlagsOf(Symbol(TIndexSymbolKind.Constant, 'MaxListSize',
    'MaxListSize = Maxint div 16;', '', ['deprecated'])), 'Konstante, deprecated');
  Assert.AreEqual(Int64($11), FlagsOf(Symbol(TIndexSymbolKind.EnumMember, 'ckGreen', 'ckGreen', '', nil)),
    'Aufzählungswert');
  Assert.AreEqual(Int64($2), FlagsOf(Symbol(TIndexSymbolKind.EnumType, 'TColorKind',
    'TColorKind = (ckRed, ckGreen, ckBlue);', '', nil)), 'Aufzählungstyp');
  Assert.AreEqual(Int64($E2), FlagsOf(Symbol(TIndexSymbolKind.ClassType, 'TProbe', 'TProbe = class', '', nil)),
    'Klasse');
  Assert.AreEqual(Int64($62), FlagsOf(Symbol(TIndexSymbolKind.RecordType, 'TPoint2', 'TPoint2 = record', '', nil)),
    'Record');
  Assert.AreEqual(Int64($80000E2), FlagsOf(Symbol(TIndexSymbolKind.InterfaceType, 'IShape', 'IShape = interface',
    '', nil)), 'Interface');
  Assert.AreEqual(Int64($2), FlagsOf(Symbol(TIndexSymbolKind.TypeAlias, 'TCount', 'TCount = Integer;', '', nil)),
    'Typalias');
  Assert.AreEqual(Int64($E2), FlagsOf(Symbol(TIndexSymbolKind.TypeAlias, 'TPersistentClass',
    'TPersistentClass = class of TPersistent;', '', nil)), 'class of');
  Assert.AreEqual(Int64($C0000E2), FlagsOf(Symbol(TIndexSymbolKind.TypeAlias, 'TProc',
    'TProc = reference to procedure;', '', nil)), 'reference to');
end;

procedure TLspServerPartsTests.KindsAsMeasured;
var
  mSymbol: TIndexSymbol;
begin
  Assert.AreEqual(5, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.Field, 'FWert', '', 'Integer', nil)), 'Feld');
  Assert.AreEqual(6, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.Variable, 'G', '', 'Integer', nil)),
    'Variable');
  Assert.AreEqual(10, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.Property_, 'Name', '', 'string', nil)),
    'Property');
  Assert.AreEqual(2, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.Method, 'Twice', '', 'Integer', nil)),
    'Methode');
  Assert.AreEqual(4, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.Constructor_, 'Create',
    'constructor Create;', '', nil)), 'Konstruktor');
  mSymbol := Symbol(TIndexSymbolKind.Constructor_, 'Destroy', 'destructor Destroy; override;', '', ['override',
    'destructor']);
  Assert.AreEqual(2, TRadStudioDialect.KindOf(mSymbol), 'Destruktor wie Methode');
  Assert.AreEqual(3, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.Routine, 'Run', 'procedure Run;', '', nil)),
    'globale Routine');
  Assert.AreEqual(21, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.Constant, 'c', 'c = 1;', '', nil)),
    'Konstante');
  Assert.AreEqual(20, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.EnumMember, 'ckRed', '', '', nil)),
    'Aufzählungswert');
  Assert.AreEqual(13, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.EnumType, 'TColorKind', '', '', nil)),
    'Aufzählungstyp');
  Assert.AreEqual(7, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.ClassType, 'TProbe', 'TProbe = class', '',
    nil)), 'Klasse');
  Assert.AreEqual(22, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.RecordType, 'TPoint2', 'TPoint2 = record',
    '', nil)), 'Record');
  Assert.AreEqual(8, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.InterfaceType, 'IShape',
    'IShape = interface', '', nil)), 'Interface');
  Assert.AreEqual(12, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.TypeAlias, 'TCount', 'TCount = Integer;',
    '', nil)), 'Typalias');
  Assert.AreEqual(18, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.TypeAlias, 'PPointerList',
    'PPointerList = ^TPointerList;', '', nil)), 'Zeigertyp');
  Assert.AreEqual(7, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.TypeAlias, 'TClass',
    'TClass = class of TObject;', '', nil)), 'class of');
  Assert.AreEqual(8, TRadStudioDialect.KindOf(Symbol(TIndexSymbolKind.TypeAlias, 'TProc',
    'TProc = reference to procedure;', '', nil)), 'reference to');
end;

procedure TLspServerPartsTests.DetailAsDelphiLsp;
var
  mSymbols: TArray<TIndexSymbol>;
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
  // Konstante mit Hinweis-Direktive: die Direktive gehört nicht zum Wert (gemessen: MaxListSize).
  Assert.AreEqual(' = MaxInt div 16;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.Constant, 'MaxListSize',
    'MaxListSize = MaxInt div 16 deprecated;', '', ['deprecated'])));
  // Gruppen aufgelöst, der Modifizierer je Parameter.
  Assert.AreEqual('(A: Integer; B: Integer): Integer;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.Method,
    'Add', 'function Add(A, B: Integer): Integer; overload;', 'Integer', ['overload'])));
  Assert.AreEqual('(const A: string; const B: string): string;', TRadStudioDialect.DetailOf(
    Symbol(TIndexSymbolKind.Method, 'Add', 'function Add(const A, B: string): string; overload;', 'string',
    ['overload'])));
  Assert.AreEqual('(var Message);', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.Method, 'Dispatch',
    'procedure Dispatch(var Message); virtual;', '', ['virtual'])));
  Assert.AreEqual(': string;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.Property_, 'Name',
    'property Name: string read FName write FName;', 'string', nil)));
  Assert.AreEqual(': [Index: Integer]: string;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.Property_,
    'Names', 'property Names[Index: Integer]: string read GetName;', 'string', nil)));
  Assert.AreEqual(': TCount;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.Variable, 'GCounter',
    'GCounter: TCount;', 'TCount', nil)));
  Assert.AreEqual(' = 42;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.Constant, 'cMaxCount',
    'cMaxCount = 42;', '', nil)));
  Assert.AreEqual(': Integer;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.TypeAlias, 'TCount',
    'TCount = Integer;', '', nil)));
  Assert.AreEqual(': ^TPointerList;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.TypeAlias, 'PPointerList',
    'PPointerList = ^TPointerList;', '', nil)));
  Assert.AreEqual(': class of TPersistent;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.TypeAlias,
    'TPersistentClass', 'TPersistentClass = class of TPersistent;', '', nil)));
  Assert.AreEqual(': record;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.RecordType, 'TPoint2',
    'TPoint2 = record', '', nil)));
  Assert.AreEqual(': class(TObject);', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.ClassType, 'TProbe',
    'TProbe = class', '', nil)), 'ohne Vorfahr mit TObject');
  Assert.AreEqual(': class(TStrings);', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.ClassType, 'TStringList',
    'TStringList = class(TStrings)', '', nil)));
  Assert.AreEqual(': class;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.ClassType, 'TObject',
    'TObject = class', '', nil)), 'TObject selbst');
  Assert.AreEqual(': interface(IInterface);', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.InterfaceType,
    'IShape', 'IShape = interface', '', nil)));
  Assert.AreEqual(': ckRed..ckBlue;', TRadStudioDialect.DetailOf(Symbol(TIndexSymbolKind.EnumType, 'TColorKind',
    'TColorKind = (ckRed, ckGreen, ckBlue);', '', nil)), 'Grenzen aus der Signatur');
  // Ordnung und Grenzen aus den Symbolen der Unit.
  mSymbols := [Placed(Symbol(TIndexSymbolKind.EnumType, 'TColorKind', 'TColorKind = (', '', nil), '', 13, 2),
    Placed(Symbol(TIndexSymbolKind.EnumMember, 'ckRed', 'ckRed', '', nil), 'TColorKind', 13, 16),
    Placed(Symbol(TIndexSymbolKind.EnumMember, 'ckGreen', 'ckGreen', '', nil), 'TColorKind', 13, 23),
    Placed(Symbol(TIndexSymbolKind.EnumMember, 'ckBlue', 'ckBlue', '', nil), 'TColorKind', 13, 32)];
  Assert.AreEqual(' = TColorKind(1);', TRadStudioDialect.DetailWith(mSymbols[2], mSymbols), 'Aufzählungswert');
  Assert.AreEqual(' = TColorKind(0);', TRadStudioDialect.DetailWith(mSymbols[1], mSymbols));
  Assert.AreEqual(': ckRed..ckBlue;', TRadStudioDialect.DetailWith(mSymbols[0], mSymbols), 'Grenzen aus der Unit');
end;

procedure TLspServerPartsTests.ParametersResolved;
var
  mHead: TRadRoutineHead;
begin
  Assert.AreEqual('A: Integer|B: Integer', string.Join('|', TRadStudioDialect.ResolveParameters('A, B: Integer')));
  Assert.AreEqual('const A: string|const B: string|var Message|out X: TObject|Index: Integer = 0',
    string.Join('|', TRadStudioDialect.ResolveParameters('const A, B: string; var Message; out X: TObject; ' +
    'Index: Integer = 0')));
  Assert.AreEqual('const Args: array of const', string.Join('|',
    TRadStudioDialect.ResolveParameters('const Args: array of const')));
  Assert.AreEqual(0, Length(TRadStudioDialect.ResolveParameters('')), 'ohne Parameter');
  Assert.IsTrue(TRadStudioDialect.ParseRoutine('class function MethodAddress(const Name: string): Pointer; overload;',
    mHead));
  Assert.AreEqual('class function', mHead.Head);
  Assert.AreEqual('MethodAddress', mHead.Name);
  Assert.AreEqual('const Name: string', string.Join('|', mHead.Parameters));
  Assert.AreEqual('Pointer', mHead.ResultType);
  Assert.AreEqual('class function TObject.MethodAddress(const Name: string): Pointer',
    TRadStudioDialect.RoutineCaption(mHead, 'TObject.'));
  Assert.IsTrue(TRadStudioDialect.ParseRoutine('procedure Reset', mHead));
  Assert.AreEqual('procedure Reset', TRadStudioDialect.RoutineCaption(mHead, ''), 'ohne Klammern');
  Assert.IsFalse(TRadStudioDialect.ParseRoutine('TProbe = class', mHead), 'kein Routinenkopf');
end;

procedure TLspServerPartsTests.HoverCaptionAsMeasured;
begin
  // Kopfzeilen aus dem Mitschnitt (DelphiLSP, Testunit uMain).
  Assert.AreEqual('function TProbe.Twice(const A: Integer): Integer', TRadStudioDialect.HoverCaption(
    'function Twice(const A: Integer): Integer;', 'method', 'TProbe', '', cProbeFile, ''));
  Assert.AreEqual('function TProbe.Add(A: Integer; B: Integer): Integer', TRadStudioDialect.HoverCaption(
    'function Add(A, B: Integer): Integer; overload;', 'method', 'TProbe', '', cProbeFile, ''), 'Gruppen aufgelöst');
  Assert.AreEqual('constructor TProbe.Create(const AName: string)', TRadStudioDialect.HoverCaption(
    'constructor Create(const AName: string);', 'constructor', 'TProbe', '', cProbeFile, ''));
  Assert.AreEqual('function TPoint2.Sum: Integer', TRadStudioDialect.HoverCaption('function Sum: Integer;',
    'method', 'TPoint2', '', cProbeFile, ''));
  Assert.AreEqual('function TProbe.OldStyle: Integer', TRadStudioDialect.HoverCaption(
    'function OldStyle: Integer; deprecated ''Nicht mehr benutzen'';', 'method', 'TProbe', '', cProbeFile, ''),
    'ohne deprecated');
  Assert.AreEqual('function Helper(const S: string): Integer', TRadStudioDialect.HoverCaption(
    'function Helper(const S: string): Integer;', 'routine', '', '', cProbeFile, ''));
  Assert.AreEqual('function System.SysUtils.IntToStr(Value: Integer): string', TRadStudioDialect.HoverCaption(
    'function IntToStr(Value: Integer): string; overload;', 'routine', '', 'System.SysUtils', 'C:\Rtl\x.pas', ''));
  Assert.AreEqual('function System.SysUtils.Format(const Format: string; const Args: array of const): string',
    TRadStudioDialect.HoverCaption('function Format(const Format: string; const Args: array of const): string; ' +
    'overload;', 'routine', '', 'System.SysUtils', 'C:\Rtl\x.pas', ''));
  Assert.AreEqual('type TProbe = class(TObject)', TRadStudioDialect.HoverCaption('TProbe = class', 'class', '', '',
    cProbeFile, ''), 'Klasse ohne Vorfahr');
  Assert.AreEqual('type System.Classes.TStringList = class(TStrings)', TRadStudioDialect.HoverCaption(
    'TStringList = class(TStrings)', 'class', '', 'System.Classes', 'C:\Rtl\x.pas', ''));
  Assert.AreEqual('var TProbe.FValue: Integer', TRadStudioDialect.HoverCaption('FValue: Integer;', 'field',
    'TProbe', '', cProbeFile, ''));
  Assert.AreEqual('property TProbe.Name: string', TRadStudioDialect.HoverCaption(
    'property Name: string read FName write FName;', 'property', 'TProbe', '', cProbeFile, ''));
  Assert.AreEqual('property TList.Items[Index: Integer]: TObject', TRadStudioDialect.HoverCaption(
    'property Items[Index: Integer]: TObject read GetItem; default;', 'property', 'TList', '', cProbeFile, ''));
  Assert.AreEqual('var P: TProbe', TRadStudioDialect.HoverCaption('P: TProbe;', '', '', '', cProbeFile, ''),
    'lokale Variable');
  Assert.AreEqual('var GCounter: TCount', TRadStudioDialect.HoverCaption('GCounter: TCount;', 'variable', '', '',
    cProbeFile, ''));
  Assert.AreEqual('const cMaxCount = 42', TRadStudioDialect.HoverCaption('cMaxCount = 42;', 'constant', '', '',
    cProbeFile, '42 · $2A'));
  Assert.AreEqual('const uMain.ckGreen = TColorKind(1)', TRadStudioDialect.HoverCaption('ckGreen, ckBlue);',
    'enumMember', 'TColorKind', '', cProbeFile, 'Ord = 1'), 'Aufzählungswert mit Unit');
end;

procedure TLspServerPartsTests.SignatureHelpForIde;
const
  // Wörtlich \r\n und \" (doppelt maskiert wie DelphiLSP).
  cDocumentation =
    '<html>\r\n<head>\r\n<META http-equiv=\"Content-Type\" content=\"text/html\">\r\n' +
    '<link type=\"text/css\" rel=\"Stylesheet\" href=\"HelpInsight.css\">\r\n<title></title>\r\n</head>\r\n' +
    '<body>\r\n<div name=\"main\">\r\n<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\">\r\n<tr>\r\n' +
    '<td nowrap=\"true\">\r\n<div class=\"maincaption\"></div>\r\n</td>\r\n</tr>\r\n</table>\r\n' +
    '<p>Addiert zwei Ganzzahlen.</p>\r\n<h4>Returns</h4>\r\n<P>\r\n<DL>Summe</DL>\r\n</P>\r\n' +
    '</div>\r\n</body>\r\n</html>\r\n';
var
  mServer: TJSONValue;
  mAnswer: TJSONValue;
begin
  mServer := Parse('{"signatures":[{"label":"function Add(A, B: Integer): Integer",' +
    '"documentation":{"kind":"markdown","value":"**Addiert** zwei Ganzzahlen.\n\n\u2192 Summe"},' +
    '"parameters":[{"label":[13,14]},{"label":[16,17],"documentation":"Zweiter"}]}],' +
    '"activeSignature":0,"activeParameter":1}');
  try
    mAnswer := TRadStudioDialect.SignatureAnswer(mServer);
    try
      Assert.AreEqual('function Add(A: Integer; B: Integer): Integer',
        mAnswer.GetValue<string>('signatures[0].label'), 'Gruppen aufgelöst');
      Assert.AreEqual('html', mAnswer.GetValue<string>('signatures[0].documentation.kind'));
      Assert.AreEqual(cDocumentation, mAnswer.GetValue<string>('signatures[0].documentation.value'));
      Assert.IsTrue(ContainsStr(mAnswer.ToJSON, '<html>\\r\\n<head>\\r\\n<META http-equiv=\\\"Content-Type'),
        'auf der Leitung doppelt maskiert: ' + mAnswer.ToJSON);
      Assert.AreEqual('A: Integer', mAnswer.GetValue<string>('signatures[0].parameters[0].label'));
      Assert.AreEqual('B: Integer', mAnswer.GetValue<string>('signatures[0].parameters[1].label'));
      Assert.AreEqual('xml', mAnswer.GetValue<string>('signatures[0].parameters[0].documentation.kind'));
      Assert.AreEqual('', mAnswer.GetValue<string>('signatures[0].parameters[0].documentation.value'));
      Assert.AreEqual('Zweiter', mAnswer.GetValue<string>('signatures[0].parameters[1].documentation.value'));
      Assert.AreEqual(1, mAnswer.GetValue<Integer>('activeParameter'));
    finally
      mAnswer.Free;
    end;
  finally
    mServer.Free;
  end;
end;

/// <summary>contents der Antwort im Format der IDE auf den Hover AServerJson.</summary>
function HoverContents(const AServerJson: string): string;
var
  mServer, mAnswer: TJSONValue;
begin
  mServer := Parse(AServerJson);
  try
    mAnswer := TRadStudioDialect.HoverAnswer(mServer);
    try
      Assert.IsTrue(TJSONObject(mAnswer).GetValue('contents') is TJSONString, 'contents als String');
      Assert.IsNull(TJSONObject(mAnswer).GetValue('range'), 'ohne range');
      Assert.IsNull(TJSONObject(mAnswer).GetValue('dpcc'), 'ohne dpcc-Teile');
      Result := mAnswer.GetValue<string>('contents');
    finally
      mAnswer.Free;
    end;
  finally
    mServer.Free;
  end;
end;

procedure TLspServerPartsTests.HoverHtmlAsMeasured;
const
  cHead = '<html>'#13#10'<head>'#13#10'<META http-equiv="Content-Type" content="text/html">'#13#10 +
    '<link type="text/css" rel="Stylesheet" href="HelpInsight.css">'#13#10'<title>';
  cBodyStart = '</title>'#13#10'</head>'#13#10'<body>'#13#10'<div name="main">'#13#10 +
    '<table width="100%" cellpadding="0" cellspacing="0">'#13#10'<tr>'#13#10'<td nowrap="true">'#13#10 +
    '<div class="maincaption">';
  cLink = #13#10#9#9#9#9#9'-'#13#10#9#9'<a class="codelink" href="helpinsight:/filelink:C:\Projekt\uMain.pas?';
  cTableEnd = '</a></div>'#13#10'</td>'#13#10'</tr>'#13#10'</table>'#13#10;
  cTail = '</div>'#13#10'</body>'#13#10'</html>'#13#10;
  cTwice = 'function TProbe.Twice(const A: Integer): Integer';
begin
  // Methode mit Summary, Parameter-Doku und Returns.
  Assert.AreEqual(cHead + cTwice + cBodyStart + cTwice + cLink + '47,1">uMain.pas (47)' + cTableEnd +
    '<p>Verdoppelt A.</p>'#13#10'<h4>Parameters</h4>'#13#10'<P>'#13#10'<DL>'#13#10'<DT><I>A</I></DT>'#13#10 +
    '<DD>Integer</DD>'#13#10'<DD>Eingabewert</DD>'#13#10'</DL>'#13#10'</P>'#13#10'<h4>Returns</h4>'#13#10 +
    '<P>'#13#10'<DL>Das Doppelte</DL>'#13#10'</P>'#13#10 + cTail,
    HoverContents('{"contents":{"kind":"markdown","value":"x"},"dpcc":{"declaration":' +
    '"function Twice(const A: Integer): Integer;","container":"TProbe","documentation":{"sections":[' +
    '{"kind":"summary","runs":[{"kind":"text","text":"Verdoppelt A."}]},' +
    '{"kind":"param","name":"A","runs":[{"kind":"text","text":"Eingabewert"}]},' +
    '{"kind":"returns","runs":[{"kind":"text","text":"Das Doppelte"}]}]},"documentationText":"Verdoppelt A.",' +
    '"kind":"method","file":"' + cProbeFileJson + '","line":46,"character":13}}'), 'Methode');
  // Lokale Variable ohne Doku: kein Block.
  Assert.AreEqual(cHead + 'var P: TProbe' + cBodyStart + 'var P: TProbe' + cLink + '124,1">uMain.pas (124)' +
    cTableEnd + cTail, HoverContents('{"contents":"P: TProbe;","dpcc":{"declaration":"P: TProbe;","file":"' +
    cProbeFileJson + '","line":123,"character":2}}'), 'lokale Variable');
  // Klasse mit Remarks; Parameter ohne Doku bekommen ein leeres DD.
  Assert.AreEqual(cHead + 'type TProbe = class(TObject)' + cBodyStart + 'type TProbe = class(TObject)' + cLink +
    '35,1">uMain.pas (35)' + cTableEnd + '<p>Eine Testklasse.</p>'#13#10'<h4>Remarks</h4>'#13#10'<P>'#13#10 +
    '<DL>Mit Bemerkung.</DL>'#13#10'</P>'#13#10 + cTail, HoverContents('{"contents":"x","dpcc":{' +
    '"declaration":"TProbe = class","documentation":{"sections":[{"kind":"summary","runs":[{"kind":"text",' +
    '"text":"Eine Testklasse."}]},{"kind":"remarks","runs":[{"kind":"text","text":"Mit Bemerkung."}]}]},' +
    '"kind":"class","file":"' + cProbeFileJson + '","line":34,"character":2}}'), 'Klasse');
  Assert.IsTrue(ContainsStr(HoverContents('{"contents":"x","dpcc":{"declaration":' +
    '"function Helper(const S: string): Integer;","kind":"routine","file":"' + cProbeFileJson +
    '","line":116,"character":9}}'), '<h4>Parameters</h4>'#13#10'<P>'#13#10'<DL>'#13#10'<DT><I>S</I></DT>'#13#10 +
    '<DD>string</DD>'#13#10'<DD></DD>'#13#10'</DL>'#13#10'</P>'#13#10'</div>'), 'Parameter auch ohne Doku');
  // Ohne dpcc-Teil: Kopfzeile aus dem Klartext, ohne Verweis.
  Assert.AreEqual(cHead + 'function Twice: Integer' + cBodyStart + 'function Twice: Integer' + '</div>'#13#10 +
    '</td>'#13#10'</tr>'#13#10'</table>'#13#10'<p>Doku mit Code</p>'#13#10 + cTail,
    HoverContents('{"contents":{"kind":"markdown","value":"```pascal\nfunction Twice: Integer;\n```\n---\n' +
    '**Doku** mit `Code`"}}'), 'Rückfall ohne dpcc');
end;

procedure TLspServerPartsTests.KibitzKindByContext;
const
  cText =
    'unit uMain;'#13#10 +                           // 0
    'interface'#13#10 +                             // 1
    'uses'#13#10 +                                  // 2
    '  System.SysUtils, System.Classes;'#13#10 +    // 3
    'implementation'#13#10 +                        // 4
    'procedure Run;'#13#10 +                        // 5
    'begin'#13#10 +                                 // 6
    '  P.Reset;'#13#10 +                            // 7
    '  { uses } P.Paint;'#13#10 +                   // 8
    'end;'#13#10 +                                  // 9
    'end.'#13#10;
begin
  Assert.AreEqual(15, TRadStudioDialect.KibitzKindAt(cText, 3, 2), 'erste Unit der uses-Klausel');
  Assert.AreEqual(15, TRadStudioDialect.KibitzKindAt(cText, 3, 19), 'zweite Unit');
  Assert.AreEqual(15, TRadStudioDialect.KibitzKindAt(cText, 2, 4), 'direkt nach uses');
  Assert.AreEqual(2, TRadStudioDialect.KibitzKindAt(cText, 7, 4), 'nach P.');
  Assert.AreEqual(2, TRadStudioDialect.KibitzKindAt(cText, 7, 6), 'nach P.Re');
  Assert.AreEqual(7, TRadStudioDialect.KibitzKindAt(cText, 7, 2), 'vor P');
  Assert.AreEqual(7, TRadStudioDialect.KibitzKindAt(cText, 8, 11), 'uses im Kommentar zählt nicht');
  Assert.AreEqual(2, TRadStudioDialect.KibitzKindAt(cText, 8, 13), 'nach P. hinter dem Kommentar');
  Assert.AreEqual(7, TRadStudioDialect.KibitzKindAt(cText, 6, 5), 'nach begin');
  Assert.AreEqual(7, TRadStudioDialect.KibitzKindAt(cText, 6, 99), 'Spalte hinter dem Zeilenende');
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
      Assert.IsTrue(mCaps.GetValue<Boolean>('implementationProvider'), 'implementation über definition');
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
  cProbeText =
    'unit uMain;'#13#10 +               // 0
    'interface'#13#10 +                 // 1
    'uses'#13#10 +                      // 2
    '  System.Classes;'#13#10 +         // 3
    'implementation'#13#10 +            // 4
    'procedure Run;'#13#10 +            // 5
    'var'#13#10 +                       // 6
    '  P: TProbe;'#13#10 +              // 7
    'begin'#13#10 +                     // 8
    '  P.'#13#10 +                      // 9
    'end;'#13#10 +                      // 10
    'end.'#13#10;

function CompletionRequest(AId, ALine, ACharacter: Integer): string;
begin
  Result := '{"jsonrpc":"2.0","id":' + IntToStr(AId) + ',"method":"textDocument/completion","params":' +
    '{"textDocument":{"uri":"' + cProbeUri + '"},"position":{"line":' + IntToStr(ALine) + ',"character":' +
    IntToStr(ACharacter) + '}}}';
end;

function DataOf(ALine, ACharacter: Integer): string;
begin
  Result := '"data":{"file":"' + cProbeFileJson + '","line":' + IntToStr(ALine) + ',"character":' +
    IntToStr(ACharacter) + '}';
end;

/// <summary>Index der Testunit: Mitglieder von TProbe mit dem Namen in Zeile 20 bis 25.</summary>
function ProbeSymbols: TArray<TIndexSymbol>;
var
  mPrivate, mDestroy: TIndexSymbol;
begin
  mPrivate := Placed(Symbol(TIndexSymbolKind.Field, 'FName', 'FName: string;', 'string', nil), 'TProbe', 20, 4);
  mPrivate.Visibility := TIndexVisibility.Private;
  mDestroy := Placed(Symbol(TIndexSymbolKind.Constructor_, 'Destroy', 'destructor Destroy; override;', '',
    ['override', 'destructor']), 'TProbe', 25, 15);
  mDestroy.IsVirtual := True;
  Result := [mPrivate,
    Placed(Symbol(TIndexSymbolKind.Method, 'Add', 'function Add(A, B: Integer): Integer; overload;', 'Integer',
    ['overload']), 'TProbe', 21, 13),
    Placed(Symbol(TIndexSymbolKind.Method, 'Add', 'function Add(const A, B: string): string; overload;', 'string',
    ['overload']), 'TProbe', 22, 13),
    Placed(Symbol(TIndexSymbolKind.Property_, 'Name', 'property Name: string read FName write FName;', 'string',
    nil), 'TProbe', 23, 13),
    Placed(Symbol(TIndexSymbolKind.Property_, 'OnChange', 'property OnChange: TNotifyEvent read FOnChange write ' +
    'FOnChange;', 'TNotifyEvent', nil), 'TProbe', 24, 13),
    mDestroy];
end;

/// <summary>Hängt die Haken für die Testunit an den Übersetzer.</summary>
procedure AttachProbeIndex(ADialect: TRadStudioDialect);
var
  mSymbols: TArray<TIndexSymbol>;
begin
  mSymbols := ProbeSymbols;
  ADialect.UnitSymbols :=
    function(const AFileName: string; out ASymbols: TArray<TIndexSymbol>): Boolean
    begin
      Result := SameText(AFileName, cProbeFile);
      ASymbols := nil;
      if Result then
      begin
        ASymbols := mSymbols;
      end;
    end;
  ADialect.TypeLookup :=
    function(const ATypeName: string; out ASymbol: TIndexSymbol): Boolean
    begin
      Result := True;
      if SameText(ATypeName, 'TProbe') then
      begin
        ASymbol := Symbol(TIndexSymbolKind.ClassType, 'TProbe', 'TProbe = class', '', nil);
      end
      else if SameText(ATypeName, 'TNotifyEvent') then
      begin
        ASymbol := Symbol(TIndexSymbolKind.TypeAlias, 'TNotifyEvent',
          'TNotifyEvent = procedure(Sender: TObject) of object;', '', nil);
      end
      else
      begin
        Result := False;
      end;
    end;
end;

/// <summary>Eintrag AIndex der Liste in AResponse als "label|kind|detail|DCC_Flags|sortText".</summary>
function ItemText(AResponse: TJSONObject; AIndex: Integer): string;
var
  mItem: TJSONObject;
  mFlags: string;
begin
  mItem := AResponse.GetValue<TJSONArray>('result.items').Items[AIndex] as TJSONObject;
  mFlags := '-';
  if mItem.GetValue('DCC_Flags') <> nil then
  begin
    mFlags := '$' + IntToHex(mItem.GetValue<Int64>('DCC_Flags'), 1);
  end;
  Result := mItem.GetValue<string>('label', '') + '|' + IntToStr(mItem.GetValue<Integer>('kind', 0)) + '|' +
    mItem.GetValue<string>('detail', '') + '|' + mFlags + '|' + mItem.GetValue<string>('sortText', '');
end;

procedure TLspServerPartsTests.CompletionReplayAsMeasured;
var
  mSession: TDialectSession;
  mResponse, mRequest: TJSONObject;
begin
  mSession := TDialectSession.Create('RAD Studio');
  try
    AttachProbeIndex(mSession.Dialect);
    mSession.Open(cProbeUri, cProbeText);
    mSession.FromIde(CompletionRequest(10, 9, 4)).Free;
    mResponse := mSession.FromServer('{"jsonrpc":"2.0","id":10,"result":{"isIncomplete":true,"items":[' +
      '{"label":"FName","kind":5,"detail":"string","sortText":"00000",' + DataOf(20, 4) + '},' +
      '{"label":"Add","kind":2,"detail":"(A, B: Integer): Integer;","sortText":"00001",' + DataOf(21, 13) + '},' +
      '{"label":"Name","kind":10,"detail":"string","sortText":"00002",' + DataOf(23, 13) + '},' +
      '{"label":"OnChange","kind":10,"detail":"TNotifyEvent","sortText":"00003",' + DataOf(24, 13) + '},' +
      '{"label":"Destroy","kind":4,"detail":";","sortText":"00004",' + DataOf(25, 15) + '},' +
      '{"label":"CPP_ABI_1","kind":2,"detail":"TObject","sortText":"00005","data":{"file":"' + cProbeFileJson +
      '","line":26,"character":4,"unavailable":true}},' +
      '{"label":"Mit uses","kind":7,"sortText":"00006","additionalTextEdits":[{"range":{"start":{"line":3,' +
      '"character":16},"end":{"line":3,"character":16}},"newText":", System.Types"}]},' +
      '{"label":"P","kind":6,"detail":"TProbe","sortText":"00007"},' +
      '{"label":"begin","kind":14,"sortText":"00008"}]}}');
    try
      Assert.IsTrue(mResponse.GetValue<Boolean>('result.isIncomplete'), 'isIncomplete wie vom Server');
      Assert.AreEqual(2, mResponse.GetValue<Integer>('result.kibitzkind'), 'nach P.');
      Assert.AreEqual(8, mResponse.GetValue<TJSONArray>('result.items').Count,
        'ohne nicht geltenden Zweig und ohne Eintrag mit Änderungen, Add zweimal');
      Assert.AreEqual('FName|5|: string;|$113|0', ItemText(mResponse, 0), 'Feld, private');
      Assert.AreEqual('Add|2|(A: Integer; B: Integer): Integer;|$4000035|1', ItemText(mResponse, 1),
        'erste Überladung');
      Assert.AreEqual('Add|2|(const A: string; const B: string): string;|$4000035|2', ItemText(mResponse, 2),
        'zweite Überladung');
      Assert.AreEqual('Name|10|: string;|$4018|3', ItemText(mResponse, 3), 'Property');
      Assert.AreEqual('OnChange|23|: TNotifyEvent;|$14038|4', ItemText(mResponse, 4), 'Ereignis');
      Assert.AreEqual('Destroy|2|;|$40234|5', ItemText(mResponse, 5), 'Destruktor');
      Assert.AreEqual('P|6|: TProbe;|$E3|6', ItemText(mResponse, 6), 'lokale Variable eines Klassentyps');
      Assert.AreEqual('begin|14||$0|k000', ItemText(mResponse, 7), 'Schlüsselwort hinten');
      Assert.IsNull(mResponse.FindValue('result.items[1].data'), 'kein data');
    finally
      mResponse.Free;
    end;
    // resolve wie die IDE: kind als Zeichenkette, ohne data; zurück kommt der Eintrag der Liste.
    mRequest := mSession.FromIde('{"jsonrpc":"2.0","id":11,"method":"completionItem/resolve","params":' +
      '{"label":"Add","kind":"2","detail":"(const A: string; const B: string): string;","DCC_Flags":67108917,' +
      '"sortText":"2","insertTextFormat":"1"}}');
    try
      Assert.AreEqual(21, mRequest.GetValue<Integer>('params.data.line'), 'Eintrag des Servers eingesetzt');
    finally
      mRequest.Free;
    end;
    mResponse := mSession.FromServer('{"jsonrpc":"2.0","id":11,"result":{"label":"Add","kind":2,' +
      '"detail":"(A, B: Integer): Integer;","documentation":{"kind":"markdown","value":"Doku"}}}');
    try
      Assert.AreEqual('Add', mResponse.GetValue<string>('result.label'));
      Assert.AreEqual(2, mResponse.GetValue<Integer>('result.kind'));
      Assert.AreEqual('(const A: string; const B: string): string;', mResponse.GetValue<string>('result.detail'),
        'derselbe Eintrag wie in der Liste');
      Assert.AreEqual(Int64($4000035), mResponse.GetValue<Int64>('result.DCC_Flags'), 'DCC_Flags der Liste');
      Assert.AreEqual('2', mResponse.GetValue<string>('result.sortText'));
      Assert.IsNull(mResponse.FindValue('result.documentation'), 'ohne documentation');
    finally
      mResponse.Free;
    end;
    // Ein Eintrag, der nicht (mehr) aus der letzten Liste stammt (gemessen: der IDE-Mitschnitt fragt auch nach
    // weiteren Listen): der Eintrag, wie die IDE ihn schickte, samt DCC_Flags, kind als Zahl.
    mSession.FromIde('{"jsonrpc":"2.0","id":12,"method":"completionItem/resolve","params":' +
      '{"label":"Twice","kind":"2","detail":"(const A: Integer): Integer;","DCC_Flags":53,"sortText":"04"}}').Free;
    mResponse := mSession.FromServer('{"jsonrpc":"2.0","id":12,"result":{"label":"Twice","kind":2,' +
      '"detail":"(const A: Integer): Integer;"}}');
    try
      Assert.AreEqual(2, mResponse.GetValue<Integer>('result.kind'), 'kind als Zahl');
      Assert.AreEqual(Int64(53), mResponse.GetValue<Int64>('result.DCC_Flags'), 'DCC_Flags aus dem Eintrag der IDE');
      Assert.AreEqual('04', mResponse.GetValue<string>('result.sortText'));
      Assert.IsNull(mResponse.FindValue('result.documentation'), 'ohne documentation');
    finally
      mResponse.Free;
    end;
  finally
    mSession.Free;
  end;
end;

procedure TLspServerPartsTests.CompletionSortTextAndKibitz;
var
  mSession: TDialectSession;
  mResponse: TJSONObject;
  mItems: string;
  mIndex: Integer;
begin
  mSession := TDialectSession.Create('RAD Studio');
  try
    mSession.Open(cProbeUri, cProbeText);
    mItems := '';
    for mIndex := 0 to 16 do
    begin
      if mItems <> '' then
      begin
        mItems := mItems + ',';
      end;
      mItems := mItems + '{"label":"c' + IntToStr(mIndex) + '","kind":21,"detail":";"}';
    end;
    mSession.FromIde(CompletionRequest(20, 8, 5)).Free;
    mResponse := mSession.FromServer('{"jsonrpc":"2.0","id":20,"result":{"isIncomplete":false,"items":[' + mItems +
      ']}}');
    try
      Assert.AreEqual(7, mResponse.GetValue<Integer>('result.kibitzkind'), 'Bezeichner ohne Punkt');
      Assert.IsFalse(mResponse.GetValue<Boolean>('result.isIncomplete'));
      Assert.AreEqual('00', mResponse.GetValue<string>('result.items[0].sortText'), '17 Einträge: zwei Stellen');
      Assert.AreEqual('0A', mResponse.GetValue<string>('result.items[10].sortText'), 'hexadezimal, groß');
      Assert.AreEqual('10', mResponse.GetValue<string>('result.items[16].sortText'));
    finally
      mResponse.Free;
    end;
    mSession.FromIde(CompletionRequest(21, 3, 2)).Free;
    mResponse := mSession.FromServer('{"jsonrpc":"2.0","id":21,"result":{"isIncomplete":false,"items":[' +
      '{"label":"System.SysUtils","kind":9}]}}');
    try
      Assert.AreEqual(15, mResponse.GetValue<Integer>('result.kibitzkind'), 'uses-Klausel');
      Assert.AreEqual('System.SysUtils|17|;|$4026|0', ItemText(mResponse, 0), 'Unit');
    finally
      mResponse.Free;
    end;
  finally
    mSession.Free;
  end;
end;

procedure TLspServerPartsTests.LocationsAsSingleObject;
const
  cRange = '"range":{"start":{"line":7,"character":2},"end":{"line":7,"character":3}}';
var
  mSession: TDialectSession;
  mResponse, mRequest: TJSONObject;
  mPosition: string;
begin
  mPosition := '"params":{"textDocument":{"uri":"' + cProbeUri + '"},"position":{"line":9,"character":2}}}';
  mSession := TDialectSession.Create('RAD Studio');
  try
    mSession.Open(cProbeUri, cProbeText);
    mSession.FromIde('{"jsonrpc":"2.0","id":12,"method":"textDocument/definition",' + mPosition).Free;
    mResponse := mSession.FromServer('{"jsonrpc":"2.0","id":12,"result":[{"uri":"file:///c%3A/projekt/umain.pas",' +
      cRange + '},{"uri":"file:///c%3A/andere/uandere.pas",' + cRange + '}]}');
    try
      Assert.IsTrue(mResponse.GetValue('result') is TJSONObject, 'ein Location-Objekt: ' + mResponse.ToJSON);
      Assert.AreEqual(cProbeUri, mResponse.GetValue<string>('result.uri'), 'Schreibweise der IDE');
      Assert.AreEqual(7, mResponse.GetValue<Integer>('result.range.start.line'));
    finally
      mResponse.Free;
    end;
    // implementation geht als definition an den Server und kommt als implementation zurück.
    mRequest := mSession.FromIde('{"jsonrpc":"2.0","id":13,"method":"textDocument/implementation",' + mPosition);
    try
      Assert.AreEqual('textDocument/definition', mRequest.GetValue<string>('method'), 'wie definition');
    finally
      mRequest.Free;
    end;
    mResponse := mSession.FromServer('{"jsonrpc":"2.0","id":13,"result":[]}');
    try
      Assert.IsTrue(mResponse.GetValue('result') is TJSONNull, 'leere Liste als null');
    finally
      mResponse.Free;
    end;
    mSession.FromIde('{"jsonrpc":"2.0","id":14,"method":"textDocument/declaration",' + mPosition).Free;
    mResponse := mSession.FromServer('{"jsonrpc":"2.0","id":14,"result":[{"targetUri":' +
      '"file:///c%3A/andere/uandere.pas","targetRange":{"start":{"line":3,"character":0},"end":{"line":5,' +
      '"character":0}},"targetSelectionRange":{"start":{"line":4,"character":2},"end":{"line":4,"character":8}}}]}');
    try
      Assert.AreEqual('file:///c%3A/andere/uandere.pas', mResponse.GetValue<string>('result.uri'),
        'nicht geöffnet: unverändert');
      Assert.AreEqual(4, mResponse.GetValue<Integer>('result.range.start.line'), 'LocationLink: Ziel des Namens');
    finally
      mResponse.Free;
    end;
    mSession.FromIde('{"jsonrpc":"2.0","id":15,"method":"textDocument/typeDefinition",' + mPosition).Free;
    mResponse := mSession.FromServer('{"jsonrpc":"2.0","id":15,"result":null}');
    try
      Assert.IsTrue(mResponse.GetValue('result') is TJSONNull, 'null bleibt null');
    finally
      mResponse.Free;
    end;
  finally
    mSession.Free;
  end;
end;

procedure TLspServerPartsTests.StandardClientUnchanged;
const
  cAnswer = '{"jsonrpc":"2.0","id":10,"result":{"isIncomplete":false,"items":[{"label":"Add","kind":2,' +
    '"detail":"(A, B: Integer): Integer;","sortText":"00000"}]}}';
var
  mSession: TDialectSession;
  mResponse, mRequest, mExpected: TJSONObject;
begin
  mSession := TDialectSession.Create('Testclient');
  try
    Assert.IsFalse(mSession.Dialect.Active, 'kein Dialekt');
    mSession.Open(cProbeUri, cProbeText);
    mSession.FromIde(CompletionRequest(10, 9, 4)).Free;
    mResponse := mSession.FromServer(cAnswer);
    mExpected := ParseObject(cAnswer);
    try
      Assert.AreEqual(mExpected.ToJSON, mResponse.ToJSON, 'unverändert');
    finally
      mExpected.Free;
      mResponse.Free;
    end;
    mRequest := mSession.FromIde('{"jsonrpc":"2.0","id":11,"method":"textDocument/implementation","params":{}}');
    try
      Assert.AreEqual('textDocument/implementation', mRequest.GetValue<string>('method'), 'unverändert');
    finally
      mRequest.Free;
    end;
  finally
    mSession.Free;
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
    Assert.AreEqual(6, mClass.GetValue<Integer>('children[4].kind'), 'Konstruktor wie Methode');
    Assert.AreEqual('Value: Integer', mClass.GetValue<string>('children[5].name'));
    Assert.AreEqual(7, mClass.GetValue<Integer>('children[5].kind'), 'Property');
    Assert.AreEqual('read FValue', mClass.GetValue<string>('children[5].detail'), 'Zugriff der Property');
    Assert.AreEqual('TPunkt', mInterface.GetValue<string>('children[1].name'));
    Assert.AreEqual(23, mInterface.GetValue<Integer>('children[1].kind'), 'Record');
    Assert.AreEqual('X: Integer', mInterface.GetValue<string>('children[1].children[0].name'));
    Assert.AreEqual(23, mInterface.GetValue<Integer>('children[2].kind'), 'Aufzählung');
    Assert.AreEqual('Run', mInterface.GetValue<string>('children[3].name'));
    Assert.AreEqual('18:10-18:13', RangeText(mInterface, 'children[3].range'));
    mImplementation := mSymbols.Items[1];
    Assert.AreEqual('implementation', mImplementation.GetValue<string>('name'));
    Assert.AreEqual('20:0-39:3', RangeText(mImplementation, 'range'), 'bis end. am Ende der Unit');
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

procedure TLspServerPartsTests.DocumentSymbolUses;
const
  cUsesUnit =
    'unit uUses;'#13#10 +                           // 0
    'interface'#13#10 +                             // 1
    'uses'#13#10 +                                  // 2
    '  System.SysUtils, System.Classes;'#13#10 +    // 3
    'type'#13#10 +                                  // 4
    '  TZahl = Integer;'#13#10 +                    // 5
    'implementation'#13#10 +                        // 6
    'uses'#13#10 +                                  // 7
    '  uHilfe in ''uHilfe.pas'';'#13#10 +           // 8
    'initialization'#13#10 +                        // 9
    'end.'#13#10;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
  mUses: TJSONValue;
begin
  mTree := TPascalParser.Parse(cUsesUnit);
  try
    mSymbols := TLspDocumentSymbols.Build(mTree, cUsesUnit);
  finally
    mTree.Free;
  end;
  try
    Assert.AreEqual(2, mSymbols.Count, 'zwei Abschnitte');
    mUses := mSymbols.Items[0].GetValue<TJSONArray>('children').Items[0];
    Assert.AreEqual('uses', mUses.GetValue<string>('name'), 'uses vorn im interface');
    Assert.AreEqual('section', mUses.GetValue<string>('detail'));
    Assert.AreEqual(2, mUses.GetValue<Integer>('kind'));
    Assert.AreEqual('2:0-3:33', RangeText(mUses, 'range'), 'vom Wort uses bis zum Ende der letzten Unit');
    Assert.AreEqual(2, mUses.GetValue<TJSONArray>('children').Count);
    Assert.AreEqual('System.SysUtils', mUses.GetValue<string>('children[0].name'));
    Assert.AreEqual(1, mUses.GetValue<Integer>('children[0].kind'), 'Unit als File');
    Assert.AreEqual('', mUses.GetValue<string>('children[0].detail'));
    Assert.AreEqual('3:2-3:17', RangeText(mUses, 'children[0].range'), 'nur der Name');
    Assert.AreEqual('System.Classes', mUses.GetValue<string>('children[1].name'));
    Assert.AreEqual('3:19-3:33', RangeText(mUses, 'children[1].range'));
    Assert.AreEqual('TZahl', mSymbols.Items[0].GetValue<string>('children[1].name'));
    Assert.AreEqual(23, mSymbols.Items[0].GetValue<Integer>('children[1].kind'), 'Alias wie DelphiLSP');
    mUses := mSymbols.Items[1].GetValue<TJSONArray>('children').Items[0];
    Assert.AreEqual('uses', mUses.GetValue<string>('name'), 'uses im implementation-Teil');
    Assert.AreEqual('7:0-8:8', RangeText(mUses, 'range'));
    Assert.AreEqual('uHilfe', mUses.GetValue<string>('children[0].name'));
    Assert.AreEqual('8:2-8:8', RangeText(mUses, 'children[0].range'), 'ohne in ''Datei''');
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
