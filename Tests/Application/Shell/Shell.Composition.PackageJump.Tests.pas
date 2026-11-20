unit Shell.Composition.PackageJump.Tests;

// Sprung in ein anderes Package (Strg+Klick, textDocument/declaration) über die ganze Komposition: In-Process-Server,
// echte Projekte im Temp-Ordner. Package P (UnitA) verlangt Package Q (UnitB, TQType); gesprungen wird von TQType in
// UnitA. Fälle: P vor Q gemeldet (das aktive Projekt zuerst, wie die IDE), umgekehrt, Q kommt später dazu, P allein
// mit Q.dpk im Geschwisterordner und Q nirgends (dpcc/noTarget unitNotFound vor der leeren Antwort). Dazu der
// Builder: Eine nicht gefundene Unit bleibt nach ForgetFailedUnits nicht hängen.
// Caches, Diagnoselog und globale Einstellungen liegen für die Dauer eines Tests im Temp-Ordner (DPCC_CACHE_ROOT und
// APPDATA nur im Testprozess), nie im Profil des Benutzers.
// Deterministisch für den Leckmonitor: Die Testprojekte schließen per dpcc.json alle Units aus Such- und
// Bibliothekspfaden aus (die Units der requires-Packages kommen trotzdem), und der Abbau wartet, bis kein Aufbau mehr
// läuft. Vorher las jeder Test die RTL in einen leeren Cache und wurde mitten darin abgebaut; je nach Zeitpunkt blieb
// bis zu ~10 MB über das Testende hinaus belegt (nicht dauerhaft: der Rest beim Programmende war gleich).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  DUnitX.TestFramework,
  Shell.Composition.CompletionServer,
  Shell.Composition.InProcess;

type
  /// <summary>Nachrichten des Servers in der Reihenfolge des Eintreffens; threadsicher.</summary>
  TJumpMessageLog = class
  private
    FLock: TObject;
    FItems: TList<string>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AText: string);
    function Snapshot: TArray<string>;
    function Count: Integer;
  end;

  /// <summary>Liest die Ausgabe des Servers (Content-Length-Rahmen) bis zu ihrem Ende.</summary>
  TJumpServerReader = class(TThread)
  private
    FInput: TStream;
    FLog: TJumpMessageLog;
  protected
    procedure Execute; override;
  public
    constructor Create(AInput: TStream; ALog: TJumpMessageLog);
  end;

  [TestFixture]
  TShellPackageJumpTests = class
  private
    FFolder: string;
    FOldCacheRoot: string;
    FOldAppData: string;
    FServer: TShellInProcessServer;
    FRoot: TShellCompletionServer;
    FLog: TJumpMessageLog;
    FReader: TJumpServerReader;
    FNextId: Integer;
    /// <summary>Package AName in AFolder: .dproj, .dpk (requires ARequires, '' = keine) und die Unit.</summary>
    procedure WritePackage(const AFolder, AName, ARequires, AUnitName, AUnitText: string);
    function ProjectFile(const AFolder, AName: string): string;
    procedure StartServer(const AProjects: TArray<string>);
    procedure StopServer;
    /// <summary>Schickt AMessage mit Kopfzeile an den Server und gibt sie frei.</summary>
    procedure Send(AMessage: TJSONObject);
    /// <summary>Wartet auf die Antwort zu AId; liefert ihre Stelle im Log und ihren Text.</summary>
    function WaitForResponse(AId: Integer; out AText: string): Integer;
    procedure OpenUnitA(const AFileName: string);
    /// <summary>Ein Sprung von TQType in UnitA; ADone: Stelle der Antwort, ABefore: Zahl der Nachrichten vorher.
    /// Ergebnis: Dateiname des ersten Ziels, '' ohne Ziel.</summary>
    function Jump(const AFileName: string; out ABefore, ADone: Integer): string;
    /// <summary>Springt, bis ein Ziel kommt oder die Wartezeit um ist; Dateiname des Ziels.</summary>
    function JumpUntilTarget(const AFileName: string): string;
    /// <summary>Feld AField von dpcc/noTarget zwischen ABefore und ADone; '' ohne Meldung.</summary>
    function NoTargetField(ABefore, ADone: Integer; const AField: string): string;
    /// <summary>Kennt P die Unit B aus Q als Suchpfad-Unit (über requires)? Den Pfad nennt der Arbeitsbereich von Q.
    /// </summary>
    function PSeesUnitB: Boolean;
    /// <summary>PSeesUnitB als Rückruf (eine Methode ohne Parameter würde sonst sofort aufgerufen).</summary>
    function SeesUnitB: TFunc<Boolean>;
    /// <summary>Rückruf: Kein Arbeitsbereich baut seinen Index noch auf (Projektstufe offen oder Fortschritt aktiv).
    /// </summary>
    function IndexIdle: TFunc<Boolean>;
    function WaitUntil(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal): Boolean;
  public
    /// <summary>Einmal-Belegungen (Server-Thread, Ordnerlisten der Installation, Texttabellen) vor dem Leckmonitor.
    /// </summary>
    [SetupFixture]
    procedure WarmUp;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>(a) P vor Q gemeldet: P kennt UnitB schon beim ersten Aufbau, der Sprung trifft Q.</summary>
    [Test]
    procedure RequiringProjectFirst;
    /// <summary>(b) Q vor P gemeldet: ebenso.</summary>
    [Test]
    procedure RequiredProjectFirst;
    /// <summary>(c) Nur P, Sprung ohne Ziel (unitNotFound vor der Antwort); Q kommt über
    /// didChangeWorkspaceFolders dazu: P lädt neu und kennt UnitB, der Sprung trifft Q.</summary>
    [Test]
    procedure RequiredProjectAddedLater;
    /// <summary>(f) Nur P, Q ist kein Projekt, aber Q.dpk liegt im Geschwisterordner: Der Sprung trifft Q.</summary>
    [Test]
    procedure SiblingPackageWithoutProject;
    /// <summary>(f) Gegenprobe: Q nirgends: dpcc/noTarget mit unitNotFound und UnitB vor der leeren Antwort.</summary>
    [Test]
    procedure MissingPackageReportsUnitNotFound;
    /// <summary>(d) Builder: Eine nicht gefundene Unit merkt er sich; nach ForgetFailedUnits findet er sie.</summary>
    [Test]
    procedure FailedUnitDoesNotStick;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  Winapi.Windows,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Index.Contract,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Index.Builder,
  dpcc.Common.Index.Adapters.CacheDirectory,
  dpcc.Common.Memory.Phase1.Tests,
  Shell.Workspace;

const
  /// <summary>So lange darf das Laden eines Projekts samt Projekt- und Suchpfadstufe dauern.</summary>
  cIndexWaitMs = 120000;
  cResponseWaitMs = 30000;
  /// <summary>dpcc.json der Testprojekte: alle Units aus Such- und Bibliothekspfaden ausgeschlossen.</summary>
  cNoLibrary = '{"index": {"exclude": ["**"]}}';

  cUnitA =
    'unit UnitA;'#13#10 +
    'interface'#13#10 +
    'uses UnitB;'#13#10 +
    'var'#13#10 +
    '  Wert: TQType;'#13#10 +
    'implementation'#13#10 +
    'end.'#13#10;
  /// <summary>Stelle von TQType in cUnitA (0-basiert).</summary>
  cJumpLine = 4;
  cJumpCharacter = 8;

  cUnitB =
    'unit UnitB;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TQType = class'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'end.'#13#10;

  cDproj =
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'#13#10 +
    '    <PropertyGroup>'#13#10 +
    '        <ProjectGuid>%s</ProjectGuid>'#13#10 +
    '        <MainSource>%s.dpk</MainSource>'#13#10 +
    '        <Base>True</Base>'#13#10 +
    '        <Config Condition="''$(Config)''==''''">Debug</Config>'#13#10 +
    '        <Platform Condition="''$(Platform)''==''''">Win32</Platform>'#13#10 +
    '        <TargetedPlatforms>1</TargetedPlatforms>'#13#10 +
    '        <AppType>Package</AppType>'#13#10 +
    '    </PropertyGroup>'#13#10 +
    '    <ItemGroup>'#13#10 +
    '        <DelphiCompile Include="$(MainSource)">'#13#10 +
    '            <MainSource>MainSource</MainSource>'#13#10 +
    '        </DelphiCompile>'#13#10 +
    '        <DCCReference Include="%s.pas"/>'#13#10 +
    '    </ItemGroup>'#13#10 +
    '</Project>'#13#10;

/// <summary>Setzt eine Umgebungsvariable des Testprozesses; '' entfernt sie.</summary>
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

{ TJumpMessageLog }

constructor TJumpMessageLog.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FItems := TList<string>.Create;
end;

destructor TJumpMessageLog.Destroy;
begin
  FItems.Free;
  FLock.Free;
  inherited;
end;

procedure TJumpMessageLog.Add(const AText: string);
begin
  TMonitor.Enter(FLock);
  try
    FItems.Add(AText);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TJumpMessageLog.Snapshot: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FItems.ToArray;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TJumpMessageLog.Count: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := FItems.Count;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TJumpServerReader }

constructor TJumpServerReader.Create(AInput: TStream; ALog: TJumpMessageLog);
begin
  FInput := AInput;
  FLog := ALog;
  inherited Create(False);
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
  if mLength < 0 then
  begin
    raise Exception.Create('Rahmen ohne Content-Length');
  end;
  mTotal := mHeaderEnd + 4 + mLength;
  if Length(ABuffer) < mTotal then
  begin
    Exit(False);
  end;
  AText := TEncoding.UTF8.GetString(ABuffer, mHeaderEnd + 4, mLength);
  ABuffer := Copy(ABuffer, mTotal, MaxInt);
  Result := True;
end;

procedure TJumpServerReader.Execute;
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

{ TShellPackageJumpTests }

procedure TShellPackageJumpTests.WarmUp;
begin
  // Beide Wege einmal ungemessen: ohne Ziel und mit Ziel (Nachladen von System über die Unit-Suche).
  Setup;
  try
    try
      MissingPackageReportsUnitNotFound;
    except
      // Scheitert der Lauf, meldet das der Test selbst.
      on Exception do
        ;
    end;
  finally
    TearDown;
  end;
  Setup;
  try
    try
      RequiringProjectFirst;
    except
      // Scheitert der Lauf, meldet das der Test selbst.
      on Exception do
        ;
    end;
  finally
    TearDown;
  end;
end;

procedure TShellPackageJumpTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, Format('dpcc-goto-%d-%d', [GetCurrentProcessId,
    TThread.GetTickCount64]));
  ForceDirectories(TPath.Combine(FFolder, 'Cache'));
  ForceDirectories(TPath.Combine(FFolder, 'AppData'));
  FOldCacheRoot := System.SysUtils.GetEnvironmentVariable(TIndexCacheDirectory.cRootVariable);
  FOldAppData := System.SysUtils.GetEnvironmentVariable('APPDATA');
  // Nur im Testprozess: Caches, Projektwahl und Diagnoselog im Temp-Ordner, keine globalen Einstellungen des
  // Benutzers (index.extraSourceFolders u. a.).
  SetProcessVariable(TIndexCacheDirectory.cRootVariable, TPath.Combine(FFolder, 'Cache'));
  SetProcessVariable('APPDATA', TPath.Combine(FFolder, 'AppData'));
  FNextId := 10;
end;

procedure TShellPackageJumpTests.TearDown;
begin
  StopServer;
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

function TShellPackageJumpTests.ProjectFile(const AFolder, AName: string): string;
begin
  Result := TPath.Combine(TPath.Combine(FFolder, AFolder), AName + '.dproj');
end;

procedure TShellPackageJumpTests.WritePackage(const AFolder, AName, ARequires, AUnitName, AUnitText: string);
var
  mDir, mDpk: string;
begin
  mDir := TPath.Combine(FFolder, AFolder);
  ForceDirectories(mDir);
  mDpk := 'package ' + AName + ';'#13#10;
  if ARequires <> '' then
  begin
    mDpk := mDpk + 'requires'#13#10'  ' + ARequires + ';'#13#10;
  end;
  mDpk := mDpk + 'contains'#13#10'  ' + AUnitName + ' in ''' + AUnitName + '.pas'';'#13#10'end.'#13#10;
  TFile.WriteAllText(TPath.Combine(mDir, AName + '.dpk'), mDpk, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(mDir, AUnitName + '.pas'), AUnitText, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(mDir, AName + '.dproj'), Format(cDproj, [TGUID.NewGuid.ToString, AName,
    AUnitName]), TEncoding.UTF8);
  // Ohne Bibliotheks- und Suchpfadstufe aus Ordnern der Installation: Units der requires-Packages kommen trotzdem
  // (AddPackageFiles prüft index.exclude nicht), die Projektdateien ebenso. Sonst las jeder Test die RTL in einen
  // leeren Cache, und wie weit er beim Abbau war, entschied über den Speicherstand danach.
  TFile.WriteAllText(TPath.Combine(mDir, 'dpcc.json'), cNoLibrary, TEncoding.ASCII);
end;

procedure TShellPackageJumpTests.Send(AMessage: TJSONObject);
var
  mBody, mBytes: TBytes;
begin
  try
    mBody := TEncoding.UTF8.GetBytes(AMessage.ToJSON);
  finally
    AMessage.Free;
  end;
  mBytes := TEncoding.ASCII.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(mBody)])) + mBody;
  FServer.ClientOutput.WriteBuffer(mBytes[0], Length(mBytes));
end;

/// <summary>workspaceFolders-Einträge wie vom Plugin: uri ist die .dproj.</summary>
function ProjectFolders(const AProjects: TArray<string>): TJSONArray;
var
  mProject: string;
  mEntry: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mProject in AProjects do
  begin
    mEntry := TJSONObject.Create;
    mEntry.AddPair('uri', TDocumentUris.FromPath(mProject));
    mEntry.AddPair('name', ChangeFileExt(ExtractFileName(mProject), ''));
    Result.AddElement(mEntry);
  end;
end;

/// <summary>Anfrage (AId &gt;= 0) bzw. Benachrichtigung (AId &lt; 0); übernimmt AParams.</summary>
function RpcMessage(const AMethod: string; AId: Integer; AParams: TJSONObject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('jsonrpc', '2.0');
  if AId >= 0 then
  begin
    Result.AddPair('id', TJSONNumber.Create(AId));
  end;
  Result.AddPair('method', AMethod);
  Result.AddPair('params', AParams);
end;

procedure TShellPackageJumpTests.StartServer(const AProjects: TArray<string>);
var
  mParams: TJSONObject;
  mRoot: TShellCompletionServer;
  mText: string;
begin
  mRoot := nil;
  FLog := TJumpMessageLog.Create;
  FServer := TShellInProcessServer.Create(nil,
    procedure(AServer: TShellCompletionServer)
    begin
      mRoot := AServer;
    end);
  FRoot := mRoot;
  FReader := TJumpServerReader.Create(FServer.ClientInput, FLog);
  mParams := TJSONObject.Create;
  mParams.AddPair('processId', TJSONNull.Create);
  mParams.AddPair('rootUri', TJSONNull.Create);
  mParams.AddPair('capabilities', TJSONObject.Create);
  mParams.AddPair('workspaceFolders', ProjectFolders(AProjects));
  Send(RpcMessage('initialize', 1, mParams));
  Assert.IsTrue(WaitForResponse(1, mText) >= 0, 'initialize beantwortet');
  Send(RpcMessage('initialized', -1, TJSONObject.Create));
end;

procedure TShellPackageJumpTests.StopServer;
begin
  if FServer = nil then
  begin
    Exit;
  end;
  // Erst abbauen, wenn kein Aufbau mehr läuft: Ein mitten in einer Stufe abgebrochener Aufbau ließ je nach Zeitpunkt
  // verschieden viel Speicher hinter sich, der erst später frei wurde (Leckmonitor schwankend).
  if FRoot <> nil then
  begin
    WaitUntil(IndexIdle(), cIndexWaitMs);
  end;
  // Stop schließt am Ende die Ausgabe; danach endet der Leser.
  FServer.Stop;
  FReader.WaitFor;
  FreeAndNil(FReader);
  FreeAndNil(FServer);
  FRoot := nil;
  FreeAndNil(FLog);
end;

function TShellPackageJumpTests.WaitUntil(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal): Boolean;
var
  mStarted: UInt64;
begin
  mStarted := TThread.GetTickCount64;
  Result := ACondition();
  while not Result and (TThread.GetTickCount64 - mStarted < ATimeoutMs) do
  begin
    TThread.Sleep(50);
    Result := ACondition();
  end;
end;

function TShellPackageJumpTests.WaitForResponse(AId: Integer; out AText: string): Integer;
var
  mStarted: UInt64;
  mItems: TArray<string>;
  mIndex, mId: Integer;
  mValue: TJSONValue;
begin
  AText := '';
  mStarted := TThread.GetTickCount64;
  repeat
    mItems := FLog.Snapshot;
    for mIndex := 0 to High(mItems) do
    begin
      mValue := TJSONObject.ParseJSONValue(mItems[mIndex]);
      try
        if (mValue is TJSONObject) and (TJSONObject(mValue).GetValue('method') = nil) and
          TJSONObject(mValue).TryGetValue<Integer>('id', mId) and (mId = AId) then
        begin
          AText := mItems[mIndex];
          Exit(mIndex);
        end;
      finally
        mValue.Free;
      end;
    end;
    TThread.Sleep(20);
  until TThread.GetTickCount64 - mStarted > cResponseWaitMs;
  Result := -1;
end;

procedure TShellPackageJumpTests.OpenUnitA(const AFileName: string);
var
  mDocument: TJSONObject;
begin
  mDocument := TJSONObject.Create;
  mDocument.AddPair('uri', TDocumentUris.FromPath(AFileName));
  mDocument.AddPair('languageId', 'pascal');
  mDocument.AddPair('version', TJSONNumber.Create(1));
  mDocument.AddPair('text', cUnitA);
  Send(RpcMessage('textDocument/didOpen', -1, TJSONObject.Create(TJSONPair.Create('textDocument', mDocument))));
end;

function TShellPackageJumpTests.Jump(const AFileName: string; out ABefore, ADone: Integer): string;
var
  mParams: TJSONObject;
  mId: Integer;
  mText: string;
  mResponse: TJSONValue;
  mResult: TJSONValue;
  mUri: string;
begin
  Inc(FNextId);
  mId := FNextId;
  ABefore := FLog.Count;
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', TDocumentUris.FromPath(AFileName))));
  mParams.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(cJumpLine))
    .AddPair('character', TJSONNumber.Create(cJumpCharacter)));
  Send(RpcMessage('textDocument/declaration', mId, mParams));
  ADone := WaitForResponse(mId, mText);
  Assert.IsTrue(ADone >= 0, 'Antwort auf den Sprung');
  Result := '';
  mResponse := TJSONObject.ParseJSONValue(mText);
  try
    mResult := TJSONObject(mResponse).GetValue('result');
    if (mResult is TJSONArray) and (TJSONArray(mResult).Count > 0) and
      TJSONArray(mResult).Items[0].TryGetValue<string>('uri', mUri) then
    begin
      Result := TDocumentUris.ToPath(mUri);
    end;
  finally
    mResponse.Free;
  end;
end;

function TShellPackageJumpTests.JumpUntilTarget(const AFileName: string): string;
var
  mStarted: UInt64;
  mBefore, mDone: Integer;
begin
  mStarted := TThread.GetTickCount64;
  Result := Jump(AFileName, mBefore, mDone);
  while (Result = '') and (TThread.GetTickCount64 - mStarted < cIndexWaitMs) do
  begin
    TThread.Sleep(250);
    Result := Jump(AFileName, mBefore, mDone);
  end;
end;

function TShellPackageJumpTests.NoTargetField(ABefore, ADone: Integer; const AField: string): string;
var
  mItems: TArray<string>;
  mIndex: Integer;
  mValue: TJSONValue;
  mMethod: string;
begin
  Result := '';
  mItems := FLog.Snapshot;
  for mIndex := ABefore to ADone - 1 do
  begin
    mValue := TJSONObject.ParseJSONValue(mItems[mIndex]);
    try
      if (mValue is TJSONObject) and TJSONObject(mValue).TryGetValue<string>('method', mMethod) and
        SameText(mMethod, 'dpcc/noTarget') then
      begin
        Result := TJSONObject(mValue).GetValue<string>('params.' + AField);
      end;
    finally
      mValue.Free;
    end;
  end;
end;

function TShellPackageJumpTests.PSeesUnitB: Boolean;
var
  mWorkspace, mP, mQ: TShellWorkspace;
  mFileName, mUnitB: string;
begin
  mP := nil;
  mQ := nil;
  mUnitB := '';
  System.TMonitor.Enter(FRoot.Parts.Core.Workspaces.Lock);
  try
    for mWorkspace in FRoot.Parts.Core.Workspaces.Items do
    begin
      if SameText(ExtractFileName(mWorkspace.State.ProjectFileName), 'P.dproj') then
      begin
        mP := mWorkspace;
      end
      else if SameText(ExtractFileName(mWorkspace.State.ProjectFileName), 'Q.dproj') then
      begin
        mQ := mWorkspace;
      end;
    end;
    if mQ <> nil then
    begin
      for mFileName in mQ.State.ProjectFiles do
      begin
        if SameText(ExtractFileName(mFileName), 'UnitB.pas') then
        begin
          mUnitB := mFileName;
        end;
      end;
    end;
    Result := (mP <> nil) and (mUnitB <> '') and mP.State.ContainsFile(mUnitB);
  finally
    System.TMonitor.Exit(FRoot.Parts.Core.Workspaces.Lock);
  end;
end;

function TShellPackageJumpTests.SeesUnitB: TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := PSeesUnitB;
    end;
end;

function TShellPackageJumpTests.IndexIdle: TFunc<Boolean>;
var
  mRoot: TShellCompletionServer;
begin
  mRoot := FRoot;
  Result :=
    function: Boolean
    begin
      Result := (mRoot.Parts.Core.Workspaces.IndexLoading < 0) and not mRoot.Parts.Core.Workspaces.ProjectIndexPending;
    end;
end;

procedure TShellPackageJumpTests.RequiringProjectFirst;
var
  mUnitA: string;
begin
  // Getrennte Elternordner: Geschwister helfen hier nicht, nur die gemerkten Projekte der Meldung.
  WritePackage('A\P', 'P', 'Q', 'UnitA', cUnitA);
  WritePackage('B\Q', 'Q', '', 'UnitB', cUnitB);
  mUnitA := TPath.Combine(TPath.Combine(FFolder, 'A\P'), 'UnitA.pas');
  StartServer([ProjectFile('A\P', 'P'), ProjectFile('B\Q', 'Q')]);
  Assert.IsTrue(WaitUntil(SeesUnitB(), cIndexWaitMs), 'P kennt UnitB über requires schon beim ersten Laden');
  OpenUnitA(mUnitA);
  Assert.AreEqual('UnitB.pas', ExtractFileName(JumpUntilTarget(mUnitA)), 'Sprung in das Package Q');
end;

procedure TShellPackageJumpTests.RequiredProjectFirst;
var
  mUnitA: string;
begin
  WritePackage('A\P', 'P', 'Q', 'UnitA', cUnitA);
  WritePackage('B\Q', 'Q', '', 'UnitB', cUnitB);
  mUnitA := TPath.Combine(TPath.Combine(FFolder, 'A\P'), 'UnitA.pas');
  StartServer([ProjectFile('B\Q', 'Q'), ProjectFile('A\P', 'P')]);
  Assert.IsTrue(WaitUntil(SeesUnitB(), cIndexWaitMs), 'P kennt UnitB über requires');
  OpenUnitA(mUnitA);
  Assert.AreEqual('UnitB.pas', ExtractFileName(JumpUntilTarget(mUnitA)), 'Sprung in das Package Q');
end;

procedure TShellPackageJumpTests.RequiredProjectAddedLater;
var
  mUnitA, mTarget: string;
  mBefore, mDone: Integer;
  mEvent: TJSONObject;
begin
  WritePackage('A\P', 'P', 'Q', 'UnitA', cUnitA);
  WritePackage('B\Q', 'Q', '', 'UnitB', cUnitB);
  mUnitA := TPath.Combine(TPath.Combine(FFolder, 'A\P'), 'UnitA.pas');
  StartServer([ProjectFile('A\P', 'P')]);
  OpenUnitA(mUnitA);
  mTarget := Jump(mUnitA, mBefore, mDone);
  Assert.AreEqual('', mTarget, 'ohne Q kein Ziel');
  Assert.AreEqual('unitNotFound', NoTargetField(mBefore, mDone, 'reason'), 'Grund vor der Antwort');
  Assert.AreEqual('UnitB', NoTargetField(mBefore, mDone, 'name'), 'fehlende Unit');
  Assert.AreEqual('textDocument/declaration', NoTargetField(mBefore, mDone, 'method'), 'Methode');
  // Gruppe geändert: Q kommt dazu.
  mEvent := TJSONObject.Create;
  mEvent.AddPair('added', ProjectFolders([ProjectFile('B\Q', 'Q')]));
  mEvent.AddPair('removed', TJSONArray.Create);
  Send(RpcMessage('workspace/didChangeWorkspaceFolders', -1, TJSONObject.Create(TJSONPair.Create('event', mEvent))));
  Assert.IsTrue(WaitUntil(SeesUnitB(), cIndexWaitMs), 'P lädt neu und kennt UnitB');
  Assert.AreEqual('UnitB.pas', ExtractFileName(JumpUntilTarget(mUnitA)), 'der frühere Fehlschlag bleibt nicht');
end;

procedure TShellPackageJumpTests.SiblingPackageWithoutProject;
var
  mUnitA: string;
begin
  // Gängiges Layout Packages\<Name>\<Name>.dpk; Q ist kein Projekt der Gruppe und liegt in keinem Suchpfad.
  WritePackage('Packages\P', 'P', 'Q', 'UnitA', cUnitA);
  WritePackage('Packages\Q', 'Q', '', 'UnitB', cUnitB);
  mUnitA := TPath.Combine(TPath.Combine(FFolder, 'Packages\P'), 'UnitA.pas');
  StartServer([ProjectFile('Packages\P', 'P')]);
  OpenUnitA(mUnitA);
  Assert.AreEqual('UnitB.pas', ExtractFileName(JumpUntilTarget(mUnitA)), 'Sprung in das Package Q');
end;

procedure TShellPackageJumpTests.MissingPackageReportsUnitNotFound;
var
  mUnitA, mTarget: string;
  mBefore, mDone: Integer;
begin
  WritePackage('Packages\P', 'P', 'Q', 'UnitA', cUnitA);
  mUnitA := TPath.Combine(TPath.Combine(FFolder, 'Packages\P'), 'UnitA.pas');
  StartServer([ProjectFile('Packages\P', 'P')]);
  OpenUnitA(mUnitA);
  mTarget := Jump(mUnitA, mBefore, mDone);
  Assert.AreEqual('', mTarget, 'kein Ziel');
  Assert.AreEqual('unitNotFound', NoTargetField(mBefore, mDone, 'reason'), 'Grund vor der Antwort');
  Assert.AreEqual('UnitB', NoTargetField(mBefore, mDone, 'name'), 'fehlende Unit');
  Assert.AreEqual(IntToStr(cJumpLine), NoTargetField(mBefore, mDone, 'line'), 'Zeile');
  Assert.AreEqual(IntToStr(cJumpCharacter), NoTargetField(mBefore, mDone, 'character'), 'Zeichen');
end;

procedure TShellPackageJumpTests.FailedUnitDoesNotStick;
const
  cFile = 'C:\Q\UnitB.pas';
var
  mFiles: TCountingIndexFileSystem;
  mFileSystem: IIndexFileSystem;
  mIndex: ISymbolIndex;
  mBuilder: TIndexBuilder;
  mKnown: string;
  mFound: TUnitIndex;
begin
  mFiles := TCountingIndexFileSystem.Create;
  mFileSystem := mFiles;
  mFiles.Put(cFile, cUnitB, 1);
  mIndex := TSymbolIndex.Create;
  // Die Unit-Suche kennt den Ordner von Q erst später (Projekt kommt dazu, Aufbau fertig).
  mKnown := '';
  mBuilder := TIndexBuilder.Create(mIndex, mFileSystem, TArray<string>.Create('MSWINDOWS'),
    function(const AUnitName: string): string
    begin
      Result := '';
      if SameText(AUnitName, 'UnitB') then
      begin
        Result := mKnown;
      end;
    end);
  try
    Assert.IsFalse(mBuilder.EnsureUnit('UnitB'), 'noch nicht zu finden');
    mKnown := cFile;
    Assert.IsFalse(mBuilder.EnsureUnit('UnitB'), 'der Fehlschlag ist gemerkt');
    mBuilder.ForgetFailedUnits;
    Assert.IsTrue(mBuilder.EnsureUnit('UnitB'), 'nach ForgetFailedUnits gefunden');
  finally
    mBuilder.Free;
  end;
  Assert.IsTrue(mIndex.FindUnit('UnitB', mFound), 'im Index');
  Assert.AreEqual(cFile, mFound.FileName, 'Datei');
end;

initialization
  TDUnitX.RegisterTestFixture(TShellPackageJumpTests);

end.
