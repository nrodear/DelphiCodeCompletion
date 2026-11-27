unit Shell.LspServer.Host.Tests;

// dpcc.LspServer über Streams (Wiedergabe wie die RAD-Studio-IDE, synthetische Daten nach dem am 27.11.2026
// gemessenen Format): initialize mit clientInfo "RAD Studio", initialized, didOpen, zweimal didChangeConfiguration mit
// Projekt, Compiler-Befehlszeile und DLL-Namen, documentSymbol, completion (DCC_Flags, kibitzkind, sortText
// hexadezimal), resolve mit kind als Zeichenkette (Eintrag der Liste zurück), signatureHelp mit doppelt maskierter
// documentation, hover als HTML-Gerüst, definition, declaration und implementation als ein Location-Objekt,
// unbekannte Methoden (-32601), Anfrage-IDs negativ und groß, shutdown und exit als Anfrage mit id. Dazu ein Client
// ohne Dialekt (Standard-LSP), das harte Ende (Eingabe zu ohne shutdown) und exit als Benachrichtigung.
// Projekt, Caches, Diagnoselog und globale Einstellungen liegen für die Dauer eines Tests in einem eigenen
// Temp-Ordner (DPCC_CACHE_ROOT und APPDATA nur im Testprozess), nie im Profil des Benutzers. dpcc.json schließt
// Such- und Bibliothekspfade aus: Der Test braucht nur die eigene Unit und liest so die RTL nicht ein.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  DUnitX.TestFramework,
  Shell.Composition.InProcess,
  Shell.LspServer.Host;

type
  /// <summary>Nachrichten des Servers in der Reihenfolge des Eintreffens; threadsicher.</summary>
  TLspTestLog = class
  private
    FLock: TObject;
    FItems: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AText: string);
    function Snapshot: TArray<string>;
  end;

  [TestFixture]
  TLspServerHostTests = class
  private
    FFolder: string;
    FOldCacheRoot: string;
    FOldAppData: string;
    FToServer: IShellMemoryPipe;
    FFromServer: IShellMemoryPipe;
    FHost: TLspServerHost;
    FServerThread: TThread;
    FReader: TThread;
    FLog: TLspTestLog;
    FClientOutput: TStream;
    FExitCode: Integer;
    FUnitFile: string;
    FMainFile: string;
    procedure WriteProject;
    procedure StartServer;
    /// <summary>Wartet auf das Ende von Run (höchstens ATimeoutMs) und baut ab; True, wenn Run endete.</summary>
    function StopServer(ATimeoutMs: Cardinal): Boolean;
    procedure SendText(const AJson: string);
    procedure Request(const AId, AMethod: string; AParams: TJSONValue);
    procedure Notify(const AMethod: string; AParams: TJSONValue);
    /// <summary>Antwort zu AId (als JSON-Text der id); nil nach ATimeoutMs. Der Aufrufer gibt sie frei.</summary>
    function WaitResponse(const AId: string; ATimeoutMs: Cardinal = 20000): TJSONObject;
    function Call(const AId, AMethod: string; AParams: TJSONValue): TJSONObject;
    function InitializeParams(const AClientName: string): TJSONObject;
    function Settings: TJSONObject;
    function DocumentParams(const APosition: string): TJSONObject;
    procedure OpenUnit(const AText: string);
    procedure ChangeUnit(const AText: string; AVersion: Integer);
    function UnitUri: string;
    function IndexIdle: Boolean;
  public
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ganzer Ablauf wie die IDE: Projektdaten kommen an, Strukturansicht, Vervollständigung,
    /// Parameterhilfe, Hover und Sprung im Format der IDE; shutdown und exit mit id beenden mit 0.</summary>
    [Test]
    procedure ReplayRadStudioSession;
    /// <summary>Negative und große IDs kommen unverändert zurück, unbekannte Methoden mit -32601.</summary>
    [Test]
    procedure IdsAndUnknownMethods;
    /// <summary>Anderer Client: Standard-LSP (Capabilities des Servers plus documentSymbolProvider, Markdown).
    /// </summary>
    [Test]
    procedure StandardClientKeepsLsp;
    /// <summary>Eingabe zu ohne shutdown (hartes Ende der IDE): Run endet zügig mit 1.</summary>
    [Test]
    procedure ClosedInputEndsServer;
    /// <summary>exit als Benachrichtigung (ohne id) nach shutdown: Run endet mit 0.</summary>
    [Test]
    procedure ExitNotificationEndsServer;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.SyncObjs,
  Winapi.Windows,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Logging.Contract,
  dpcc.Common.Logging.Providers.Logger,
  dpcc.Common.Index.Adapters.CacheDirectory;

const
  cIndexWaitMs = 60000;
  cNoLibrary = '{"index": {"exclude": ["**"]}}';
  cUnit =
    'unit uDemo;'#10 +
    ''#10 +
    'interface'#10 +
    ''#10 +
    'type'#10 +
    '  TDemo = class'#10 +
    '  public'#10 +
    '    FWert: Integer;'#10 +
    '    function Doppelt(const A: Integer): Integer;'#10 +
    '    procedure Leeren;'#10 +
    '  end;'#10 +
    ''#10 +
    'procedure Starte;'#10 +
    ''#10 +
    'implementation'#10 +
    ''#10 +
    'function TDemo.Doppelt(const A: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A * 2;'#10 +
    'end;'#10 +
    ''#10 +
    'procedure TDemo.Leeren;'#10 +
    'begin'#10 +
    '  FWert := 0;'#10 +
    'end;'#10 +
    ''#10 +
    'procedure Starte;'#10 +
    'var'#10 +
    '  D: TDemo;'#10 +
    'begin'#10 +
    '  D := TDemo.Create;'#10 +
    '  D.Leeren;'#10 +
    '%s' +
    '  D.Free;'#10 +
    'end;'#10 +
    ''#10 +
    'end.';
  /// <summary>Zeile der Einfügestelle %s in cUnit (0-basiert).</summary>
  cInsertLine = 32;
  cDpr = 'program DemoProj;'#13#10#13#10'uses'#13#10'  uDemo in ''uDemo.pas'';'#13#10#13#10'begin'#13#10'end.'#13#10;
  cDproj =
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '    <PropertyGroup>'#13#10 +
    '        <ProjectGuid>{7D2E8A41-3B6C-4F19-9E07-1C5A2B8D4F60}</ProjectGuid>'#13#10 +
    '        <MainSource>DemoProj.dpr</MainSource>'#13#10 +
    '        <Base>True</Base>'#13#10 +
    '        <Config Condition="''$(Config)''==''''">Debug</Config>'#13#10 +
    '        <Platform Condition="''$(Platform)''==''''">Win32</Platform>'#13#10 +
    '        <TargetedPlatforms>1</TargetedPlatforms>'#13#10 +
    '        <AppType>Console</AppType>'#13#10 +
    '    </PropertyGroup>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <DelphiCompile Include="$(MainSource)">'#13#10 +
    '            <MainSource>MainSource</MainSource>'#13#10 +
    '        </DelphiCompile>'#13#10 +
    '        <DCCReference Include="uDemo.pas"/>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>'#13#10;

type
  TServerThread = class(TThread)
  private
    FHost: TLspServerHost;
    FResult: PInteger;
  protected
    procedure Execute; override;
  public
    constructor Create(AHost: TLspServerHost; AResult: PInteger);
  end;

  TReaderThread = class(TThread)
  private
    FInput: TStream;
    FLog: TLspTestLog;
  protected
    procedure Execute; override;
  public
    constructor Create(AInput: TStream; ALog: TLspTestLog);
    destructor Destroy; override;
  end;

procedure SetProcessVariable(const AName, AValue: string);
begin
  if AValue = '' then
  begin
    Winapi.Windows.SetEnvironmentVariable(PChar(AName), nil);
  end
  else
  begin
    Winapi.Windows.SetEnvironmentVariable(PChar(AName), PChar(AValue));
  end;
end;

{ TLspTestLog }

constructor TLspTestLog.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FItems := TList<string>.Create;
end;

destructor TLspTestLog.Destroy;
begin
  FItems.Free;
  FLock.Free;
  inherited;
end;

procedure TLspTestLog.Add(const AText: string);
begin
  TMonitor.Enter(FLock);
  try
    FItems.Add(AText);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspTestLog.Snapshot: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FItems.ToArray;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TServerThread }

constructor TServerThread.Create(AHost: TLspServerHost; AResult: PInteger);
begin
  FHost := AHost;
  FResult := AResult;
  inherited Create(False);
end;

procedure TServerThread.Execute;
begin
  try
    FResult^ := FHost.Run;
  except
    on Exception do
      FResult^ := -1;
  end;
end;

{ TReaderThread }

constructor TReaderThread.Create(AInput: TStream; ALog: TLspTestLog);
begin
  FInput := AInput;
  FLog := ALog;
  inherited Create(False);
end;

destructor TReaderThread.Destroy;
begin
  inherited;
  FInput.Free;
end;

/// <summary>Nimmt einen vollständigen Rahmen vom Anfang von ABuffer; False, solange er nicht ganz da ist.</summary>
function TakeFrame(var ABuffer: TBytes; out AText: string): Boolean;
var
  mHeaderEnd, mIndex, mLength, mTotal: Integer;
  mLine: string;
begin
  AText := '';
  mHeaderEnd := -1;
  for mIndex := 0 to Length(ABuffer) - 4 do
  begin
    if (ABuffer[mIndex] = 13) and (ABuffer[mIndex + 1] = 10) and (ABuffer[mIndex + 2] = 13) and
      (ABuffer[mIndex + 3] = 10) then
    begin
      mHeaderEnd := mIndex;
      Break;
    end;
  end;
  if mHeaderEnd < 0 then
  begin
    Exit(False);
  end;
  mLength := -1;
  for mLine in TEncoding.ASCII.GetString(ABuffer, 0, mHeaderEnd).Split([#13#10]) do
  begin
    if StartsText('Content-Length:', mLine) then
    begin
      mLength := StrToInt(Trim(Copy(mLine, Length('Content-Length:') + 1, MaxInt)));
    end;
  end;
  mTotal := mHeaderEnd + 4 + mLength;
  if (mLength < 0) or (Length(ABuffer) < mTotal) then
  begin
    Exit(False);
  end;
  AText := TEncoding.UTF8.GetString(ABuffer, mHeaderEnd + 4, mLength);
  ABuffer := Copy(ABuffer, mTotal, MaxInt);
  Result := True;
end;

procedure TReaderThread.Execute;
var
  mChunk: array[0..8191] of Byte;
  mBuffer: TBytes;
  mRead, mStart: Integer;
  mText: string;
begin
  mBuffer := nil;
  while True do
  begin
    mRead := FInput.Read(mChunk, SizeOf(mChunk));
    if mRead <= 0 then
    begin
      Break;
    end;
    mStart := Length(mBuffer);
    SetLength(mBuffer, mStart + mRead);
    Move(mChunk[0], mBuffer[mStart], mRead);
    while TakeFrame(mBuffer, mText) do
    begin
      FLog.Add(mText);
    end;
  end;
end;

function Parse(const AText: string): TJSONObject;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AText);
  if not (mValue is TJSONObject) then
  begin
    mValue.Free;
    raise Exception.Create('Kein JSON-Objekt: ' + AText);
  end;
  Result := TJSONObject(mValue);
end;

{ TLspServerHostTests }

procedure TLspServerHostTests.WarmUp;
begin
  // Einmal ungemessen: Server-Thread, Texttabellen, Parser und Index belegen ihre Einmal-Speicher.
  Setup;
  try
    try
      ReplayRadStudioSession;
    except
      // Scheitert der Lauf, meldet das der Test selbst.
      on Exception do
        ;
    end;
  finally
    TearDown;
  end;
end;

procedure TLspServerHostTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, Format('dpcc-lspserver-%d-%d', [GetCurrentProcessId,
    TThread.GetTickCount64]));
  ForceDirectories(TPath.Combine(FFolder, 'Cache'));
  ForceDirectories(TPath.Combine(FFolder, 'AppData'));
  ForceDirectories(TPath.Combine(FFolder, 'Projekt'));
  FOldCacheRoot := System.SysUtils.GetEnvironmentVariable(TIndexCacheDirectory.cRootVariable);
  FOldAppData := System.SysUtils.GetEnvironmentVariable('APPDATA');
  SetProcessVariable(TIndexCacheDirectory.cRootVariable, TPath.Combine(FFolder, 'Cache'));
  SetProcessVariable('APPDATA', TPath.Combine(FFolder, 'AppData'));
  FUnitFile := TPath.Combine(TPath.Combine(FFolder, 'Projekt'), 'uDemo.pas');
  FMainFile := TPath.Combine(TPath.Combine(FFolder, 'Projekt'), 'DemoProj.dpr');
  FExitCode := -2;
end;

procedure TLspServerHostTests.TearDown;
begin
  StopServer(20000);
  SetProcessVariable(TIndexCacheDirectory.cRootVariable, FOldCacheRoot);
  SetProcessVariable('APPDATA', FOldAppData);
  try
    TDirectory.Delete(FFolder, True);
  except
    // Ein Rest im Temp-Ordner stört keinen Test.
    on Exception do
      ;
  end;
end;

procedure TLspServerHostTests.WriteProject;
var
  mDir: string;
begin
  mDir := TPath.Combine(FFolder, 'Projekt');
  TFile.WriteAllText(FUnitFile, Format(cUnit, ['']), TEncoding.UTF8);
  TFile.WriteAllText(FMainFile, cDpr, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(mDir, 'DemoProj.dproj'), cDproj, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(mDir, 'dpcc.json'), cNoLibrary, TEncoding.ASCII);
end;

procedure TLspServerHostTests.StartServer;
var
  mLogger: ILogger;
begin
  FLog := TLspTestLog.Create;
  FToServer := TShellMemoryPipe.Create(TShellMemoryPipe.cDefaultCapacity, 0);
  FFromServer := TShellMemoryPipe.Create(TShellMemoryPipe.cDefaultCapacity, 10000);
  FClientOutput := TShellMemoryPipe.WriteStream(FToServer);
  mLogger := TLogger.Create;
  FHost := TLspServerHost.Create(TShellMemoryPipe.ReadStream(FToServer), TShellMemoryPipe.WriteStream(FFromServer),
    True, mLogger);
  FReader := TReaderThread.Create(TShellMemoryPipe.ReadStream(FFromServer), FLog);
  FServerThread := TServerThread.Create(FHost, @FExitCode);
end;

function TLspServerHostTests.StopServer(ATimeoutMs: Cardinal): Boolean;
var
  mStarted: UInt64;
begin
  Result := True;
  if FServerThread = nil then
  begin
    Exit;
  end;
  // Erst abbauen, wenn kein Aufbau mehr läuft (wie Shell.Composition.PackageJump.Tests).
  mStarted := TThread.GetTickCount64;
  while not IndexIdle and (TThread.GetTickCount64 - mStarted < cIndexWaitMs) do
  begin
    TThread.Sleep(50);
  end;
  mStarted := TThread.GetTickCount64;
  while not FServerThread.Finished and (TThread.GetTickCount64 - mStarted < ATimeoutMs) do
  begin
    TThread.Sleep(20);
  end;
  Result := FServerThread.Finished;
  // Ende der Eingabe, falls Run noch läuft; dann auf den Thread warten.
  FToServer.Close;
  FServerThread.WaitFor;
  FreeAndNil(FServerThread);
  FreeAndNil(FHost);
  TLspServerHost.ReleaseProcessState;
  FFromServer.Close;
  FReader.WaitFor;
  FreeAndNil(FReader);
  FreeAndNil(FClientOutput);
  FToServer := nil;
  FFromServer := nil;
  FreeAndNil(FLog);
end;

function TLspServerHostTests.IndexIdle: Boolean;
begin
  Result := (FHost = nil) or (FHost.Root = nil) or ((FHost.Root.Parts.Core.Workspaces.IndexLoading < 0) and
    not FHost.Root.Parts.Core.Workspaces.ProjectIndexPending);
end;

procedure TLspServerHostTests.SendText(const AJson: string);
var
  mBody, mBytes: TBytes;
begin
  mBody := TEncoding.UTF8.GetBytes(AJson);
  mBytes := TEncoding.ASCII.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(mBody)])) + mBody;
  FClientOutput.WriteBuffer(mBytes[0], Length(mBytes));
end;

procedure TLspServerHostTests.Request(const AId, AMethod: string; AParams: TJSONValue);
var
  mText: string;
begin
  if AParams = nil then
  begin
    mText := 'null';
  end
  else
  begin
    try
      mText := AParams.ToJSON;
    finally
      AParams.Free;
    end;
  end;
  SendText(Format('{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}', [AId, AMethod, mText]));
end;

procedure TLspServerHostTests.Notify(const AMethod: string; AParams: TJSONValue);
var
  mText: string;
begin
  try
    mText := AParams.ToJSON;
  finally
    AParams.Free;
  end;
  SendText(Format('{"jsonrpc":"2.0","method":"%s","params":%s}', [AMethod, mText]));
end;

function TLspServerHostTests.WaitResponse(const AId: string; ATimeoutMs: Cardinal): TJSONObject;
var
  mStarted: UInt64;
  mItem: string;
  mMessage: TJSONObject;
begin
  mStarted := TThread.GetTickCount64;
  repeat
    for mItem in FLog.Snapshot do
    begin
      mMessage := Parse(mItem);
      if (mMessage.GetValue('method') = nil) and (mMessage.GetValue('id') <> nil) and
        (mMessage.GetValue('id').ToJSON = AId) then
      begin
        Exit(mMessage);
      end;
      mMessage.Free;
    end;
    TThread.Sleep(20);
  until TThread.GetTickCount64 - mStarted > ATimeoutMs;
  Result := nil;
end;

function TLspServerHostTests.Call(const AId, AMethod: string; AParams: TJSONValue): TJSONObject;
begin
  Request(AId, AMethod, AParams);
  Result := WaitResponse(AId);
  Assert.IsNotNull(Result, 'Antwort auf ' + AMethod + ' (id ' + AId + ')');
end;

function TLspServerHostTests.InitializeParams(const AClientName: string): TJSONObject;
var
  mCapabilities: string;
begin
  // Wie die IDE: rootUri "file:///", Hover und Doku nur als Klartext.
  mCapabilities := '{"textDocument":{"hover":{"contentFormat":["plaintext"]},"completion":{"completionItem":' +
    '{"snippetSupport":false,"documentationFormat":["plaintext"]}},"signatureHelp":{"signatureInformation":' +
    '{"documentationFormat":["plaintext"]}},"documentSymbol":{"hierarchicalDocumentSymbolSupport":true}}}';
  if AClientName <> 'RAD Studio' then
  begin
    mCapabilities := '{}';
  end;
  Result := Parse(Format('{"processId":0,"rootUri":"file:///","clientInfo":{"name":"%s"},' +
    '"initializationOptions":{"serverType":"controller","agentCount":2,"returnDccFlags":true,' +
    '"returnHoverModel":true,"storeProjectSettings":false},"capabilities":%s}', [AClientName, mCapabilities]));
end;

function TLspServerHostTests.Settings: TJSONObject;
var
  mFiles, mBrowsing: TJSONArray;
  mInner: TJSONObject;
begin
  // Synthetisch nach dem gemessenen Format (Delphi 13): Pfade der Bibliothek im Studio-Ordner, ein Suchpfad des
  // Projekts, Defines, Namespaces, Aliase.
  mInner := TJSONObject.Create;
  mInner.AddPair('project', TDocumentUris.FromPath(FMainFile));
  mInner.AddPair('dllname', 'dcc32370.dll');
  mInner.AddPair('dccOptions', '-$O- --no-config -Q -TX.exe -AWinTypes=Winapi.Windows;WinProcs=Winapi.Windows ' +
    '-DDEBUG;DEMO -E.\out -I"c:\programme\embarcadero\studio\37.0\lib\Win32\release" -NU.\out\dcu ' +
    '-NSWinapi;System.Win;System; -U"c:\programme\embarcadero\studio\37.0\lib\Win32\release";.\extra -LU');
  mFiles := TJSONArray.Create;
  mFiles.AddElement(TJSONObject.Create.AddPair('name', 'uDemo').AddPair('file', TDocumentUris.FromPath(FUnitFile)));
  mInner.AddPair('projectFiles', mFiles);
  mInner.AddPair('includeDCUsInUsesCompletion', TJSONBool.Create(True));
  mInner.AddPair('enableKeyWordCompletion', TJSONBool.Create(True));
  mBrowsing := TJSONArray.Create;
  mBrowsing.Add('file:///c%3A/programme/embarcadero/studio/37.0/source/rtl/sys');
  mInner.AddPair('browsingPaths', mBrowsing);
  mInner.AddPair('CommonAppData', 'file:///C%3A/Benutzer/Test/AppData/Roaming/Embarcadero/BDS/37.0/');
  Result := TJSONObject.Create(TJSONPair.Create('settings', mInner));
end;

function TLspServerHostTests.UnitUri: string;
begin
  Result := TDocumentUris.FromPath(FUnitFile);
end;

function TLspServerHostTests.DocumentParams(const APosition: string): TJSONObject;
begin
  Result := Parse(Format('{"textDocument":{"uri":"%s"},"position":%s}', [UnitUri, APosition]));
end;

procedure TLspServerHostTests.OpenUnit(const AText: string);
var
  mDocument: TJSONObject;
begin
  mDocument := TJSONObject.Create;
  mDocument.AddPair('uri', UnitUri);
  mDocument.AddPair('languageId', 'pascal');
  mDocument.AddPair('version', TJSONNumber.Create(1));
  mDocument.AddPair('text', AText);
  Notify('textDocument/didOpen', TJSONObject.Create(TJSONPair.Create('textDocument', mDocument)));
end;

procedure TLspServerHostTests.ChangeUnit(const AText: string; AVersion: Integer);
var
  mParams: TJSONObject;
  mChanges: TJSONArray;
begin
  // Wie die IDE: der ganze Text ohne range.
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create.AddPair('uri', UnitUri).AddPair('version',
    TJSONNumber.Create(AVersion)));
  mChanges := TJSONArray.Create;
  mChanges.AddElement(TJSONObject.Create.AddPair('text', AText));
  mParams.AddPair('contentChanges', mChanges);
  Notify('textDocument/didChange', mParams);
end;

/// <summary>Eintrag mit label ALabel aus den items von AResponse; nil ohne.</summary>
function ItemNamed(AResponse: TJSONObject; const ALabel: string): TJSONObject;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
begin
  Result := nil;
  if not AResponse.TryGetValue<TJSONArray>('result.items', mItems) then
  begin
    Exit;
  end;
  for mItem in mItems do
  begin
    if (mItem is TJSONObject) and (TJSONObject(mItem).GetValue<string>('label', '') = ALabel) then
    begin
      Exit(TJSONObject(mItem));
    end;
  end;
end;

procedure TLspServerHostTests.ReplayRadStudioSession;
var
  mResponse, mItem, mResolve: TJSONObject;
  mStarted: UInt64;
  mSymbols, mChildren, mItems: TJSONArray;
  mValue: TJSONValue;
  mId, mCount, mWidth: Integer;
  mText, mContents: string;
begin
  WriteProject;
  StartServer;
  mResponse := Call('33554434', 'initialize', InitializeParams('RAD Studio'));
  try
    // Capabilities wie DelphiLSP, aber nur, was der Server kann.
    Assert.AreEqual(1, mResponse.GetValue<Integer>('result.capabilities.textDocumentSync'), 'ganzer Text');
    Assert.IsTrue(mResponse.GetValue<Boolean>('result.capabilities.documentSymbolProvider'), 'documentSymbol');
    Assert.IsTrue(mResponse.GetValue<Boolean>('result.capabilities.completionProvider.resolveProvider'), 'resolve');
    Assert.IsTrue(mResponse.GetValue<Boolean>('result.capabilities.implementationProvider'),
      'implementation über definition');
    Assert.IsNull(mResponse.FindValue('result.capabilities.experimental'), 'keine dpcc-Eigenmethoden');
  finally
    mResponse.Free;
  end;
  Notify('initialized', TJSONObject.Create);
  OpenUnit(Format(cUnit, ['']));
  Notify('workspace/didChangeConfiguration', Settings);
  Notify('workspace/didChangeConfiguration', Settings);
  // Strukturansicht: Abschnitte, Klasse mit Feld und Methoden, Rümpfe im implementation-Teil.
  mResponse := Call('67108867', 'textDocument/documentSymbol', Parse(Format('{"textDocument":{"uri":"%s"}}',
    [UnitUri])));
  try
    mSymbols := mResponse.GetValue('result') as TJSONArray;
    Assert.AreEqual(2, mSymbols.Count, 'interface und implementation');
    Assert.AreEqual('interface', mSymbols.Items[0].GetValue<string>('name'));
    Assert.AreEqual('section', mSymbols.Items[0].GetValue<string>('detail'));
    mChildren := mSymbols.Items[0].GetValue<TJSONArray>('children');
    Assert.AreEqual('TDemo', mChildren.Items[0].GetValue<string>('name'));
    Assert.AreEqual(5, mChildren.Items[0].GetValue<Integer>('kind'));
    Assert.AreEqual('FWert: Integer', mChildren.Items[0].GetValue<string>('children[0].name'));
    Assert.AreEqual('Doppelt(const A: Integer): Integer', mChildren.Items[0].GetValue<string>('children[1].name'));
    Assert.AreEqual('declaration', mChildren.Items[0].GetValue<string>('children[1].detail'));
    Assert.AreEqual('TDemo.Doppelt(const A: Integer): Integer',
      mSymbols.Items[1].GetValue<string>('children[0].name'));
    Assert.AreEqual('implementation', mSymbols.Items[1].GetValue<string>('children[0].detail'));
  finally
    mResponse.Free;
  end;
  // Projektdaten der IDE sind angekommen: Projekt mit Delphi-Version und Symbolen der Befehlszeile.
  mStarted := TThread.GetTickCount64;
  while not FHost.Root.Parts.Core.Workspaces.HasProject(ChangeFileExt(FMainFile, '.dproj')) and
    not FHost.Root.Parts.Ide.Project.ActiveProject.EndsWith('DemoProj.dproj', True) and
    (TThread.GetTickCount64 - mStarted < 5000) do
  begin
    TThread.Sleep(20);
  end;
  Assert.IsTrue(SameText(FHost.Root.Parts.Ide.Project.ActiveProject, ChangeFileExt(FMainFile, '.dproj')),
    'Projektkontext aus didChangeConfiguration');
  // Vervollständigung nach "D." im Format der IDE; der Index braucht einen Moment.
  ChangeUnit(Format(cUnit, ['  D.'#10]), 2);
  mResponse := nil;
  mId := -2147483640;
  mStarted := TThread.GetTickCount64;
  repeat
    FreeAndNil(mResponse);
    mResponse := Call(IntToStr(mId), 'textDocument/completion',
      DocumentParams(Format('{"line":%d,"character":4}', [cInsertLine])));
    mItem := ItemNamed(mResponse, 'Doppelt');
    Inc(mId);
    if mItem = nil then
    begin
      TThread.Sleep(200);
    end;
  until (mItem <> nil) or (TThread.GetTickCount64 - mStarted > cIndexWaitMs);
  try
    Assert.IsNotNull(mItem, 'Doppelt in der Liste');
    Assert.AreEqual(2, mResponse.GetValue<Integer>('result.kibitzkind'), 'kibitzkind nach D.');
    Assert.AreEqual('(const A: Integer): Integer;', mItem.GetValue<string>('detail'), 'detail wie DelphiLSP');
    Assert.AreEqual(Int64($35), mItem.GetValue<Int64>('DCC_Flags'), 'Funktion');
    Assert.IsNull(mItem.GetValue('data'), 'kein data');
    mItems := mResponse.GetValue<TJSONArray>('result.items');
    mCount := 0;
    for mValue in mItems do
    begin
      if not StartsStr('k', mValue.GetValue<string>('sortText', '')) then
      begin
        Inc(mCount);
      end;
    end;
    mWidth := Length(IntToHex(mCount - 1, 1));
    Assert.AreEqual(StringOfChar('0', mWidth), mItems.Items[0].GetValue<string>('sortText'),
      'sortText hexadezimal, Breite nach der Anzahl');
    Assert.AreEqual(IntToHex(mCount - 1, mWidth), mItems.Items[mCount - 1].GetValue<string>('sortText'),
      'letzte Nummer');
    mItem := ItemNamed(mResponse, 'FWert');
    Assert.IsNotNull(mItem, 'FWert in der Liste');
    Assert.AreEqual(': Integer;', mItem.GetValue<string>('detail'));
    Assert.AreEqual(Int64($13), mItem.GetValue<Int64>('DCC_Flags'), 'Feld');
    mItem := ItemNamed(mResponse, 'Leeren');
    Assert.AreEqual(';', mItem.GetValue<string>('detail'));
    Assert.AreEqual(Int64($34), mItem.GetValue<Int64>('DCC_Flags'), 'Prozedur');
    // resolve wie die IDE: kind als Zeichenkette, ohne data.
    mText := Format('{"label":"Doppelt","kind":"2","detail":"%s","DCC_Flags":53,"sortText":"%s",' +
      '"insertTextFormat":"1"}', [ItemNamed(mResponse, 'Doppelt').GetValue<string>('detail'),
      ItemNamed(mResponse, 'Doppelt').GetValue<string>('sortText')]);
  finally
    mResponse.Free;
  end;
  mResolve := Call('2147483000', 'completionItem/resolve', Parse(mText));
  try
    Assert.AreEqual('Doppelt', mResolve.GetValue<string>('result.label'), 'resolve beantwortet');
    Assert.AreEqual(2, mResolve.GetValue<Integer>('result.kind'), 'kind als Zahl');
    Assert.AreEqual('(const A: Integer): Integer;', mResolve.GetValue<string>('result.detail'));
    Assert.AreEqual(Int64($35), mResolve.GetValue<Int64>('result.DCC_Flags'), 'DCC_Flags wie in der Liste');
    Assert.IsNull(mResolve.FindValue('result.documentation'), 'ohne documentation wie DelphiLSP');
  finally
    mResolve.Free;
  end;
  // Parameterhilfe: documentation in Signatur und Parameter, Parameter einzeln mit Typ.
  ChangeUnit(Format(cUnit, ['  D.Doppelt('#10]), 3);
  mResponse := Call('536870922', 'textDocument/signatureHelp',
    DocumentParams(Format('{"line":%d,"character":12}', [cInsertLine])));
  try
    Assert.AreEqual('function Doppelt(const A: Integer): Integer',
      mResponse.GetValue<string>('result.signatures[0].label'), 'label ohne ";" und Direktiven');
    Assert.AreEqual('html', mResponse.GetValue<string>('result.signatures[0].documentation.kind'));
    // Wörtlich \r\n und \" wie DelphiLSP (doppelt maskiert).
    Assert.IsTrue(StartsStr('<html>\r\n<head>\r\n<META http-equiv=\"Content-Type\"',
      mResponse.GetValue<string>('result.signatures[0].documentation.value')), 'Gerüst doppelt maskiert');
    Assert.AreEqual('const A: Integer', mResponse.GetValue<string>('result.signatures[0].parameters[0].label'));
    Assert.AreEqual('xml', mResponse.GetValue<string>('result.signatures[0].parameters[0].documentation.kind'));
  finally
    mResponse.Free;
  end;
  // Hover als HTML-Gerüst in einem String, Sprung zur Implementierung bzw. Deklaration.
  mResponse := Call('5', 'textDocument/hover', DocumentParams(Format('{"line":%d,"character":5}', [cInsertLine])));
  try
    Assert.IsTrue(mResponse.FindValue('result.contents') is TJSONString, 'contents als String: ' + mResponse.ToJSON);
    mContents := mResponse.GetValue<string>('result.contents');
    Assert.IsTrue(StartsStr('<html>'#13#10'<head>'#13#10'<META http-equiv="Content-Type" content="text/html">',
      mContents), 'HTML mit CRLF: ' + mContents);
    Assert.IsTrue(ContainsStr(mContents, '<div class="maincaption">function TDemo.Doppelt(const A: Integer): ' +
      'Integer'#13#10#9#9#9#9#9'-'#13#10#9#9'<a class="codelink" href="helpinsight:/filelink:'),
      'Kopfzeile mit Klasse und Verweis: ' + mContents);
    Assert.IsTrue(ContainsText(mContents, '">uDemo.pas ('), 'Verweis mit Dateiname');
    Assert.IsTrue(ContainsStr(mContents, '<DT><I>A</I></DT>'#13#10'<DD>Integer</DD>'#13#10'<DD></DD>'#13#10),
      'Parameter auch ohne Doku');
    Assert.IsTrue(EndsStr('</div>'#13#10'</body>'#13#10'</html>'#13#10, mContents), 'Ende des Gerüsts');
    Assert.IsNull(mResponse.FindValue('result.range'), 'ohne range');
    Assert.IsNull(mResponse.FindValue('result.dpcc'), 'ohne dpcc-Teile');
  finally
    mResponse.Free;
  end;
  mResponse := Call('6', 'textDocument/definition', DocumentParams(Format('{"line":%d,"character":5}',
    [cInsertLine])));
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONObject, 'ein Location-Objekt: ' + mResponse.ToJSON);
    Assert.AreEqual(16, mResponse.GetValue<Integer>('result.range.start.line'), 'Rumpf von TDemo.Doppelt');
    Assert.AreEqual(UnitUri, mResponse.GetValue<string>('result.uri'), 'URI wie von der IDE geöffnet');
  finally
    mResponse.Free;
  end;
  mResponse := Call('7', 'textDocument/declaration', DocumentParams(Format('{"line":%d,"character":5}',
    [cInsertLine])));
  try
    Assert.AreEqual(8, mResponse.GetValue<Integer>('result.range.start.line'), 'Deklaration in der Klasse');
  finally
    mResponse.Free;
  end;
  mResponse := Call('8', 'textDocument/implementation', DocumentParams(Format('{"line":%d,"character":5}',
    [cInsertLine])));
  try
    Assert.IsNull(mResponse.FindValue('error'), 'implementation beantwortet: ' + mResponse.ToJSON);
    Assert.AreEqual(16, mResponse.GetValue<Integer>('result.range.start.line'), 'dasselbe Ziel wie definition');
  finally
    mResponse.Free;
  end;
  mResponse := Call('11', 'shutdown', nil);
  mResponse.Free;
  mResponse := Call('12', 'exit', nil);
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONNull, 'exit mit id beantwortet');
  finally
    mResponse.Free;
  end;
  Assert.IsTrue(StopServer(10000), 'Run endet nach exit');
  Assert.AreEqual(0, FExitCode, 'Exit-Code nach shutdown');
end;

procedure TLspServerHostTests.IdsAndUnknownMethods;
var
  mResponse: TJSONObject;
begin
  WriteProject;
  StartServer;
  mResponse := Call('-2147483648', 'initialize', InitializeParams('RAD Studio'));
  mResponse.Free;
  Notify('initialized', TJSONObject.Create);
  mResponse := Call('2147483647', 'dpccprobe/unknownRequest', DocumentParams('{"line":0,"character":0}'));
  try
    Assert.AreEqual(-32601, mResponse.GetValue<Integer>('error.code'), 'nicht unterstützt');
    Assert.AreEqual('2147483647', mResponse.GetValue('id').ToJSON, 'große id unverändert');
  finally
    mResponse.Free;
  end;
  mResponse := Call('-7', 'textDocument/references', DocumentParams('{"line":0,"character":0}'));
  try
    Assert.AreEqual(-32601, mResponse.GetValue<Integer>('error.code'));
    Assert.AreEqual('-7', mResponse.GetValue('id').ToJSON, 'negative id unverändert');
  finally
    mResponse.Free;
  end;
  // Unbekannte Benachrichtigung: still verworfen, der Server antwortet weiter.
  Notify('dpccprobe/unknown', TJSONObject.Create);
  mResponse := Call('8', 'shutdown', nil);
  mResponse.Free;
  mResponse := Call('9', 'exit', nil);
  mResponse.Free;
  Assert.IsTrue(StopServer(10000), 'Run endet');
  Assert.AreEqual(0, FExitCode);
end;

procedure TLspServerHostTests.StandardClientKeepsLsp;
var
  mResponse: TJSONObject;
begin
  WriteProject;
  StartServer;
  mResponse := Call('1', 'initialize', InitializeParams('Testclient'));
  try
    Assert.IsTrue(mResponse.GetValue<Boolean>('result.capabilities.documentSymbolProvider'), 'documentSymbol dazu');
    Assert.IsNotNull(mResponse.FindValue('result.capabilities.experimental.dpcc'), 'Capabilities des Servers');
    Assert.IsFalse(FHost.Dialect.Active, 'kein Dialekt');
  finally
    mResponse.Free;
  end;
  Notify('initialized', TJSONObject.Create);
  OpenUnit(Format(cUnit, ['']));
  mResponse := Call('2', 'textDocument/hover', DocumentParams('{"line":8,"character":15}'));
  try
    // Ohne Angabe zum Format bleibt es bei Markdown (Standard des Servers).
    Assert.IsTrue((mResponse.GetValue('result') is TJSONNull) or (mResponse.FindValue('result.contents.kind') <> nil),
      'MarkupContent');
  finally
    mResponse.Free;
  end;
  mResponse := Call('3', 'shutdown', nil);
  mResponse.Free;
  Notify('exit', TJSONObject.Create);
  Assert.IsTrue(StopServer(10000), 'Run endet nach exit');
  Assert.AreEqual(0, FExitCode);
end;

procedure TLspServerHostTests.ClosedInputEndsServer;
var
  mResponse: TJSONObject;
  mStarted: UInt64;
begin
  WriteProject;
  StartServer;
  mResponse := Call('1', 'initialize', InitializeParams('RAD Studio'));
  mResponse.Free;
  Notify('initialized', TJSONObject.Create);
  OpenUnit(Format(cUnit, ['']));
  // Die IDE beendet hart: Die Eingabe endet ohne shutdown und exit.
  mStarted := TThread.GetTickCount64;
  FToServer.Close;
  while not FServerThread.Finished and (TThread.GetTickCount64 - mStarted < 15000) do
  begin
    TThread.Sleep(20);
  end;
  Assert.IsTrue(FServerThread.Finished, 'Run endet beim Ende der Eingabe');
  Assert.AreEqual(1, FExitCode, 'ohne shutdown Exit-Code 1');
end;

procedure TLspServerHostTests.ExitNotificationEndsServer;
var
  mResponse: TJSONObject;
begin
  StartServer;
  mResponse := Call('1', 'initialize', InitializeParams('RAD Studio'));
  mResponse.Free;
  mResponse := Call('2', 'shutdown', nil);
  mResponse.Free;
  Notify('exit', TJSONObject.Create);
  Assert.IsTrue(StopServer(10000), 'Run endet nach exit');
  Assert.AreEqual(0, FExitCode);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspServerHostTests);

end.
