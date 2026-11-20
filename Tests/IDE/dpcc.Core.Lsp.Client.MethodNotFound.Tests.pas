unit dpcc.Core.Lsp.Client.MethodNotFound.Tests;

// Fehlende Methoden beim schlanken Server (Schritt 2, Konzept-Completion-Schnitt 4.6): Die Fehlerantwort -32601 wird
// zu ELspMethodNotFound, der Client schickt die Methode danach nicht mehr und meldet sie nur einmal; bei
// workspace/executeCommand gilt das je Befehl. Capabilities aus initialize sperren Anfragen ohne Anbieter, ohne sie zu
// senden. Eine neue Sitzung (neues initialize bzw. neuer Client) beginnt von vorn.
// Ohne Server und ohne IDE: Der Testserver antwortet schon im Sendeaufruf des Clients.
// NAV: Der schlanke Server meldet seit dem Auftrag NAV auch definitionProvider, declarationProvider und
// typeDefinitionProvider (cSlimCapabilities wie er); als fehlende Methode dient jetzt textDocument/references.
// Strg+Klick (TLspSession.GotoTarget): declaration, auf der Deklaration selbst danach definition; ohne
// declarationProvider bzw. nach -32601 nur definition.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  DUnitX.TestFramework,
  dpcc.Core.Lsp.Client;

type
  /// <summary>Testserver am Client: beantwortet jede Anfrage sofort, mit Fehler für die Methoden in Errors (Schlüssel
  /// wie TLspClient.MethodKey), sonst mit {"ok": true}; initialize mit Capabilities, falls gesetzt.</summary>
  TFakeLspServer = class
  private
    FClient: TLspClient;
    FRequests: TList<string>;
    FErrors: TDictionary<string, Integer>;
    FCapabilities: string;
    FReported: TList<string>;
    FReplies: TDictionary<string, string>;
    FNotices: TDictionary<string, string>;
    procedure Answer(const ABytes: TBytes);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Wie oft ging AKey (MethodKey) an den Server?</summary>
    function Sent(const AKey: string): Integer;
    property Client: TLspClient read FClient;
    property Errors: TDictionary<string, Integer> read FErrors;
    /// <summary>JSON der Capabilities für initialize; '' = Antwort ohne capabilities.</summary>
    property Capabilities: string read FCapabilities write FCapabilities;
    /// <summary>Meldungen von OnMethodNotFound: "Methode|server" bzw. "Methode|capabilities".</summary>
    property Reported: TList<string> read FReported;
    /// <summary>Ergebnis (JSON) je Methode statt {"ok": true}.</summary>
    property Replies: TDictionary<string, string> read FReplies;
    /// <summary>Parameter (JSON) einer Benachrichtigung dpcc/noTarget, die der Server je Methode vor der Antwort
    /// schickt.</summary>
    property Notices: TDictionary<string, string> read FNotices;
  end;

  [TestFixture]
  TLspMethodNotFoundTests = class
  private
    FServer: TFakeLspServer;
    /// <summary>Anfrage AMethod (bzw. Befehl ACommand) über den Client; das Ergebnis wird freigegeben.</summary>
    procedure Ask(const AMethod: string; const ACommand: string = '');
    /// <summary>Capabilities aus JSON setzen.</summary>
    procedure SetCapabilities(const AJson: string);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ErrorCodeMinus32601RaisesMethodNotFound;
    [Test]
    procedure OtherErrorCodeStaysClientError;
    [Test]
    procedure MissingMethodIsNotSentAgain;
    [Test]
    procedure MissingMethodIsReportedOnce;
    [Test]
    procedure ExecuteCommandCountsPerCommand;
    [Test]
    procedure UnknownCapabilitiesAllowEverything;
    [Test]
    procedure CapabilitiesBlockWithoutSending;
    [Test]
    procedure FalseProviderIsNotSupported;
    [Test]
    procedure ExecuteCommandNeedsProvider;
    [Test]
    procedure DpccRequestsFollowExperimentalList;
    [Test]
    procedure DpccRequestsWithoutListAreAllowed;
    [Test]
    procedure HierarchyMethodsMapToTheirProvider;
    [Test]
    procedure NewCapabilitiesResetMissingMethods;
    [Test]
    procedure NewClientStartsWithoutMissingMethods;
    [Test]
    procedure SessionInitializeStoresCapabilities;
    [Test]
    procedure SessionWithoutCapabilitiesLearnsFromServer;
    /// <summary>Strg+Klick auf eine Verwendung: nur declaration, deren Ziel gilt.</summary>
    [Test]
    procedure GotoTargetOnUsageTakesDeclaration;
    /// <summary>Strg+Klick auf die Deklaration selbst: danach definition (Implementierung).</summary>
    [Test]
    procedure GotoTargetOnDeclarationAsksDefinition;
    /// <summary>Ohne declarationProvider: nur definition, declaration geht nicht hinaus.</summary>
    [Test]
    procedure GotoTargetWithoutDeclarationProvider;
    /// <summary>Unbekannte Capabilities und -32601 für declaration: weiter mit definition, danach nur noch sie.
    /// </summary>
    [Test]
    procedure GotoTargetLearnsMissingDeclaration;
    /// <summary>Kein Ziel: False ohne Ausnahme.</summary>
    [Test]
    procedure GotoTargetWithoutTarget;
    /// <summary>Kein Ziel mit dpcc/noTarget vor der leeren Antwort: GotoTargetAt liefert den Grund; ohne
    /// Benachrichtigung (älterer Server) Unknown.</summary>
    [Test]
    procedure GotoTargetAtReportsNoTargetReason;
  end;

implementation

uses
  dpcc.Core.Lsp.LateAnswers,
  dpcc.Core.Lsp.Session;

const
  cTimeoutMs = 2000;
  cSlimCapabilities = '{"textDocumentSync":2,"completionProvider":{"resolveProvider":true},"hoverProvider":true,' +
    '"signatureHelpProvider":{"triggerCharacters":["("]},"definitionProvider":true,"declarationProvider":true,' +
    '"typeDefinitionProvider":true,"workspace":{},"experimental":{"dpcc":{"requests":' +
    '["dpcc/expressionCompletion"],"notifications":["dpcc/postfixTemplates","dpcc/ideTypes"]}}}';
  cUnitFile = 'C:\Projekt\Unit1.pas';
  cUnitText =
    'unit Unit1;'#13#10 +            // 0
    'interface'#13#10 +              // 1
    'procedure Bar;'#13#10 +         // 2
    'implementation'#13#10 +         // 3
    'procedure Bar;'#13#10 +         // 4
    'begin'#13#10 +                  // 5
    'end;'#13#10 +                   // 6
    'end.';

/// <summary>Location[] mit einem Ort in cUnitFile.</summary>
function LocationAt(ALine, ACharacter: Integer): string;
begin
  Result := Format('[{"uri":"file:///C:/Projekt/Unit1.pas","range":{"start":{"line":%0:d,"character":%1:d},' +
    '"end":{"line":%0:d,"character":%2:d}}}]', [ALine, ACharacter, ACharacter + 3]);
end;

{ TFakeLspServer }

constructor TFakeLspServer.Create;
begin
  inherited Create;
  FRequests := TList<string>.Create;
  FErrors := TDictionary<string, Integer>.Create;
  FReported := TList<string>.Create;
  FReplies := TDictionary<string, string>.Create;
  FNotices := TDictionary<string, string>.Create;
  FClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
      Answer(ABytes);
    end);
  FClient.OnMethodNotFound :=
    procedure(const AMethod: string; AReported: Boolean)
    begin
      if AReported then
      begin
        FReported.Add(AMethod + '|server');
      end
      else
      begin
        FReported.Add(AMethod + '|capabilities');
      end;
    end;
end;

destructor TFakeLspServer.Destroy;
begin
  FClient.Free;
  FNotices.Free;
  FReplies.Free;
  FReported.Free;
  FErrors.Free;
  FRequests.Free;
  inherited;
end;

procedure TFakeLspServer.Answer(const ABytes: TBytes);
var
  mText: string;
  mStart: Integer;
  mMessage: TJSONValue;
  mId: Integer;
  mMethod, mKey, mReply, mResult, mNotice: string;
  mCode: Integer;
  mBytes: TBytes;
begin
  mText := TEncoding.UTF8.GetString(ABytes);
  mStart := Pos(#13#10#13#10, mText);
  mMessage := TJSONObject.ParseJSONValue(Copy(mText, mStart + 4, MaxInt));
  try
    // Benachrichtigungen (initialized, didOpen) bleiben ohne Antwort.
    if not (mMessage is TJSONObject) or not TJSONObject(mMessage).TryGetValue<Integer>('id', mId) then
    begin
      Exit;
    end;
    mMethod := TJSONObject(mMessage).GetValue<string>('method', '');
    mKey := TLspClient.MethodKey(mMethod, TJSONObject(mMessage).GetValue('params'));
    FRequests.Add(mKey);
    FNotices.TryGetValue(mKey, mNotice);
    if FErrors.TryGetValue(mKey, mCode) then
    begin
      mReply := Format('{"jsonrpc":"2.0","id":%d,"error":{"code":%d,"message":"Method not supported: %s"}}',
        [mId, mCode, mKey]);
    end
    else if FReplies.TryGetValue(mKey, mResult) then
    begin
      mReply := Format('{"jsonrpc":"2.0","id":%d,"result":%s}', [mId, mResult]);
    end
    else if (mMethod = 'initialize') and (FCapabilities <> '') then
    begin
      mReply := Format('{"jsonrpc":"2.0","id":%d,"result":{"capabilities":%s,"serverInfo":{"version":"9.9"}}}',
        [mId, FCapabilities]);
    end
    else
    begin
      mReply := Format('{"jsonrpc":"2.0","id":%d,"result":{"ok":true}}', [mId]);
    end;
  finally
    mMessage.Free;
  end;
  // Wie der Server: dpcc/noTarget auf demselben Kanal vor der leeren Antwort.
  if mNotice <> '' then
  begin
    mBytes := TLspClient.Frame('{"jsonrpc":"2.0","method":"dpcc/noTarget","params":' + mNotice + '}');
    FClient.Receive(mBytes, Length(mBytes));
  end;
  // Im Sendeaufruf: Die Anfrage ist schon angemeldet, die Antwort setzt ihr Ereignis vor dem Warten.
  mBytes := TLspClient.Frame(mReply);
  FClient.Receive(mBytes, Length(mBytes));
end;

function TFakeLspServer.Sent(const AKey: string): Integer;
var
  mKey: string;
begin
  Result := 0;
  for mKey in FRequests do
  begin
    if mKey = AKey then
    begin
      Inc(Result);
    end;
  end;
end;

{ TLspMethodNotFoundTests }

procedure TLspMethodNotFoundTests.Setup;
begin
  FServer := TFakeLspServer.Create;
end;

procedure TLspMethodNotFoundTests.TearDown;
begin
  FreeAndNil(FServer);
end;

procedure TLspMethodNotFoundTests.Ask(const AMethod: string; const ACommand: string);
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  if ACommand <> '' then
  begin
    mParams.AddPair('command', ACommand).AddPair('arguments', TJSONArray.Create);
  end;
  FServer.Client.Request(AMethod, mParams, cTimeoutMs).Free;
end;

procedure TLspMethodNotFoundTests.SetCapabilities(const AJson: string);
begin
  FServer.Client.SetCapabilities(TJSONObject.ParseJSONValue(AJson) as TJSONObject);
end;

procedure TLspMethodNotFoundTests.ErrorCodeMinus32601RaisesMethodNotFound;
var
  mMethod: string;
begin
  FServer.Errors.Add('textDocument/definition', TLspClient.cMethodNotFound);
  mMethod := '';
  try
    Ask('textDocument/definition');
  except
    on E: ELspMethodNotFound do
    begin
      mMethod := E.Method;
      Assert.Contains(E.Message, 'textDocument/definition');
    end;
  end;
  Assert.AreEqual('textDocument/definition', mMethod);
  Assert.IsFalse(FServer.Client.Offers('textDocument/definition'));
end;

procedure TLspMethodNotFoundTests.OtherErrorCodeStaysClientError;
var
  mRaised: Boolean;
begin
  FServer.Errors.Add('textDocument/hover', -32603);
  mRaised := False;
  try
    Ask('textDocument/hover');
  except
    on E: ELspClientError do
    begin
      mRaised := True;
      Assert.IsFalse(E is ELspMethodNotFound, 'nur -32601 heißt "fehlt"');
    end;
  end;
  Assert.IsTrue(mRaised);
  // Andere Fehler sperren nichts: nächster Versuch geht wieder hinaus.
  Assert.IsTrue(FServer.Client.Offers('textDocument/hover'));
  Assert.WillRaise(
    procedure
    begin
      Ask('textDocument/hover');
    end, ELspClientError);
  Assert.AreEqual(2, FServer.Sent('textDocument/hover'));
end;

procedure TLspMethodNotFoundTests.MissingMethodIsNotSentAgain;
var
  mRound: Integer;
begin
  FServer.Errors.Add('textDocument/documentSymbol', TLspClient.cMethodNotFound);
  for mRound := 1 to 3 do
  begin
    Assert.WillRaise(
      procedure
      begin
        Ask('textDocument/documentSymbol');
      end, ELspMethodNotFound);
  end;
  Assert.AreEqual(1, FServer.Sent('textDocument/documentSymbol'));
  Assert.AreEqual(1, Length(FServer.Client.MissingMethods));
  // Andere Methoden gehen weiter hinaus.
  Ask('textDocument/hover');
  Assert.AreEqual(1, FServer.Sent('textDocument/hover'));
end;

procedure TLspMethodNotFoundTests.MissingMethodIsReportedOnce;
var
  mRound: Integer;
begin
  FServer.Errors.Add('textDocument/inlayHint', TLspClient.cMethodNotFound);
  for mRound := 1 to 3 do
  begin
    Assert.WillRaise(
      procedure
      begin
        Ask('textDocument/inlayHint');
      end, ELspMethodNotFound);
  end;
  Assert.AreEqual(1, FServer.Reported.Count);
  Assert.AreEqual('textDocument/inlayHint|server', FServer.Reported[0]);
end;

procedure TLspMethodNotFoundTests.ExecuteCommandCountsPerCommand;
begin
  FServer.Errors.Add('workspace/executeCommand dpcc.server.status', TLspClient.cMethodNotFound);
  Assert.WillRaise(
    procedure
    begin
      Ask('workspace/executeCommand', 'dpcc.server.status');
    end, ELspMethodNotFound);
  Assert.WillRaise(
    procedure
    begin
      Ask('workspace/executeCommand', 'dpcc.server.status');
    end, ELspMethodNotFound);
  Ask('workspace/executeCommand', 'dpcc.server.other');
  Assert.AreEqual(1, FServer.Sent('workspace/executeCommand dpcc.server.status'));
  Assert.AreEqual(1, FServer.Sent('workspace/executeCommand dpcc.server.other'));
  Assert.IsFalse(FServer.Client.Offers('workspace/executeCommand', 'dpcc.server.status'));
  Assert.IsTrue(FServer.Client.Offers('workspace/executeCommand', 'dpcc.server.other'));
  Assert.IsTrue(FServer.Client.Offers('workspace/executeCommand'));
end;

procedure TLspMethodNotFoundTests.UnknownCapabilitiesAllowEverything;
begin
  Assert.IsFalse(FServer.Client.CapabilitiesKnown);
  Assert.IsTrue(FServer.Client.Offers('textDocument/definition'));
  Assert.IsTrue(FServer.Client.Offers('workspace/executeCommand', 'dpcc.server.status'));
  Assert.IsTrue(FServer.Client.Supports('definitionProvider'));
  Ask('textDocument/definition');
  Assert.AreEqual(1, FServer.Sent('textDocument/definition'));
end;

procedure TLspMethodNotFoundTests.CapabilitiesBlockWithoutSending;
var
  mRound: Integer;
begin
  SetCapabilities(cSlimCapabilities);
  Assert.IsTrue(FServer.Client.CapabilitiesKnown);
  Assert.IsTrue(FServer.Client.Supports('hoverProvider'));
  // Seit NAV meldet der schlanke Server Sprungziele; Referenzen weiter nicht.
  Assert.IsTrue(FServer.Client.Supports('definitionProvider'));
  Assert.IsFalse(FServer.Client.Supports('referencesProvider'));
  for mRound := 1 to 2 do
  begin
    Assert.WillRaise(
      procedure
      begin
        Ask('textDocument/references');
      end, ELspMethodNotFound);
  end;
  Assert.AreEqual(0, FServer.Sent('textDocument/references'));
  Assert.AreEqual(1, FServer.Reported.Count);
  Assert.AreEqual('textDocument/references|capabilities', FServer.Reported[0]);
  // Gemeldete Anbieter gehen hinaus.
  Ask('textDocument/hover');
  Ask('completionItem/resolve');
  Assert.AreEqual(1, FServer.Sent('textDocument/hover'));
  Assert.AreEqual(1, FServer.Sent('completionItem/resolve'));
  // Methoden ohne Zuordnung entscheidet der Server.
  Assert.IsTrue(FServer.Client.Offers('shutdown'));
end;

procedure TLspMethodNotFoundTests.FalseProviderIsNotSupported;
begin
  SetCapabilities('{"definitionProvider":false,"referencesProvider":null,"hoverProvider":{}}');
  Assert.IsFalse(FServer.Client.Supports('definitionProvider'));
  Assert.IsFalse(FServer.Client.Supports('referencesProvider'));
  Assert.IsTrue(FServer.Client.Supports('hoverProvider'));
  Assert.IsFalse(FServer.Client.Offers('textDocument/definition'));
  Assert.IsFalse(FServer.Client.Offers('textDocument/references'));
end;

procedure TLspMethodNotFoundTests.ExecuteCommandNeedsProvider;
begin
  SetCapabilities(cSlimCapabilities);
  Assert.IsFalse(FServer.Client.Offers('workspace/executeCommand', 'dpcc.server.selectBuild'));
  Assert.WillRaise(
    procedure
    begin
      Ask('workspace/executeCommand', 'dpcc.server.selectBuild');
    end, ELspMethodNotFound);
  Assert.AreEqual(0, FServer.Sent('workspace/executeCommand dpcc.server.selectBuild'));
  // Mit Anbieter entscheidet je Befehl der Server (die Liste der alten Wurzel war nicht vollständig).
  SetCapabilities('{"executeCommandProvider":{"commands":["dpcc.server.status"]}}');
  Assert.IsTrue(FServer.Client.Offers('workspace/executeCommand', 'dpcc.server.interfaceMethods'));
end;

procedure TLspMethodNotFoundTests.DpccRequestsFollowExperimentalList;
begin
  SetCapabilities(cSlimCapabilities);
  Assert.IsTrue(FServer.Client.Offers('dpcc/expressionCompletion'));
  Assert.IsFalse(FServer.Client.Offers('dpcc/impact'));
  Assert.WillRaise(
    procedure
    begin
      Ask('dpcc/dataFlow');
    end, ELspMethodNotFound);
  Assert.AreEqual(0, FServer.Sent('dpcc/dataFlow'));
  Ask('dpcc/expressionCompletion');
  Assert.AreEqual(1, FServer.Sent('dpcc/expressionCompletion'));
end;

procedure TLspMethodNotFoundTests.DpccRequestsWithoutListAreAllowed;
begin
  // Ältere Server melden kein experimental.dpcc: Eigenmethoden entscheidet dann die Antwort.
  SetCapabilities('{"hoverProvider":true}');
  Assert.IsTrue(FServer.Client.Offers('dpcc/impact'));
end;

procedure TLspMethodNotFoundTests.HierarchyMethodsMapToTheirProvider;
begin
  Assert.AreEqual('callHierarchyProvider', TLspServerCapabilities.ProviderOf('callHierarchy/incomingCalls'));
  Assert.AreEqual('typeHierarchyProvider', TLspServerCapabilities.ProviderOf('typeHierarchy/subtypes'));
  Assert.AreEqual('diagnosticProvider', TLspServerCapabilities.ProviderOf('workspace/diagnostic'));
  Assert.AreEqual('executeCommandProvider', TLspServerCapabilities.ProviderOf('workspace/executeCommand'));
  Assert.AreEqual('', TLspServerCapabilities.ProviderOf('initialize'));
end;

procedure TLspMethodNotFoundTests.NewCapabilitiesResetMissingMethods;
begin
  FServer.Errors.Add('textDocument/codeAction', TLspClient.cMethodNotFound);
  Assert.WillRaise(
    procedure
    begin
      Ask('textDocument/codeAction');
    end, ELspMethodNotFound);
  Assert.IsFalse(FServer.Client.Offers('textDocument/codeAction'));
  // Neue Sitzung (initialize ohne Capabilities): wieder fragen.
  FServer.Client.SetCapabilities(nil);
  Assert.IsTrue(FServer.Client.Offers('textDocument/codeAction'));
  FServer.Errors.Remove('textDocument/codeAction');
  Ask('textDocument/codeAction');
  Assert.AreEqual(2, FServer.Sent('textDocument/codeAction'));
  // Auch von Hand.
  FServer.Errors.Add('textDocument/codeLens', TLspClient.cMethodNotFound);
  Assert.WillRaise(
    procedure
    begin
      Ask('textDocument/codeLens');
    end, ELspMethodNotFound);
  FServer.Client.ResetMissingMethods;
  Assert.AreEqual(0, Length(FServer.Client.MissingMethods));
end;

procedure TLspMethodNotFoundTests.NewClientStartsWithoutMissingMethods;
var
  mRestarted: TFakeLspServer;
begin
  FServer.Errors.Add('textDocument/definition', TLspClient.cMethodNotFound);
  Assert.WillRaise(
    procedure
    begin
      Ask('textDocument/definition');
    end, ELspMethodNotFound);
  // Serverneustart: eigener Prozess, eigener Client.
  mRestarted := TFakeLspServer.Create;
  try
    Assert.IsTrue(mRestarted.Client.Offers('textDocument/definition'));
    mRestarted.Client.Request('textDocument/definition', TJSONObject.Create, cTimeoutMs).Free;
    Assert.AreEqual(1, mRestarted.Sent('textDocument/definition'));
  finally
    mRestarted.Free;
  end;
end;

procedure TLspMethodNotFoundTests.SessionInitializeStoresCapabilities;
var
  mSession: TLspSession;
begin
  FServer.Capabilities := cSlimCapabilities;
  mSession := TLspSession.Create(FServer.Client, cTimeoutMs);
  try
    mSession.Initialize;
    Assert.AreEqual('9.9', mSession.ServerVersion);
    Assert.IsTrue(mSession.Supports('hoverProvider'));
    Assert.IsTrue(mSession.Supports('definitionProvider'), 'seit NAV');
    Assert.IsTrue(mSession.Offers('textDocument/definition'), 'seit NAV');
    Assert.IsTrue(mSession.Offers('textDocument/declaration'), 'seit NAV');
    Assert.IsTrue(mSession.Offers('textDocument/completion'));
    Assert.IsFalse(mSession.Offers('textDocument/documentSymbol'));
    Assert.IsFalse(mSession.Offers('textDocument/diagnostic'));
    Assert.IsFalse(mSession.Offers('workspace/executeCommand', 'dpcc.server.status'));
    Assert.WillRaise(
      procedure
      begin
        mSession.References('C:\Projekt\Unit1.pas', 0, 5);
      end, ELspMethodNotFound);
    Assert.AreEqual(0, FServer.Sent('textDocument/references'));
    Assert.AreEqual(1, FServer.Sent('initialize'));
  finally
    mSession.Free;
  end;
end;

procedure TLspMethodNotFoundTests.GotoTargetOnUsageTakesDeclaration;
var
  mSession: TLspSession;
  mLocation: TLspLocation;
begin
  FServer.Capabilities := cSlimCapabilities;
  FServer.Replies.Add('textDocument/declaration', LocationAt(2, 10));
  FServer.Replies.Add('textDocument/definition', LocationAt(4, 10));
  mSession := TLspSession.Create(FServer.Client, cTimeoutMs);
  try
    mSession.Initialize;
    // Stelle in Zeile 6, das Ziel der Deklaration liegt in Zeile 2: kein zweiter Schritt.
    Assert.IsTrue(mSession.GotoTarget(cUnitFile, cUnitText, 6, 0, cTimeoutMs, mLocation), 'Ziel');
    Assert.AreEqual(2, mLocation.Line, 'Deklaration');
    Assert.AreEqual(1, FServer.Sent('textDocument/declaration'));
    Assert.AreEqual(0, FServer.Sent('textDocument/definition'));
  finally
    mSession.Free;
  end;
end;

procedure TLspMethodNotFoundTests.GotoTargetOnDeclarationAsksDefinition;
var
  mSession: TLspSession;
  mLocation: TLspLocation;
begin
  FServer.Capabilities := cSlimCapabilities;
  FServer.Replies.Add('textDocument/declaration', LocationAt(2, 10));
  FServer.Replies.Add('textDocument/definition', LocationAt(4, 10));
  mSession := TLspSession.Create(FServer.Client, cTimeoutMs);
  try
    mSession.Initialize;
    // Stelle auf "Bar" in "procedure Bar;" (Zeile 2, Zeichen 11): Das ist die Deklaration selbst.
    Assert.IsTrue(mSession.GotoTarget(cUnitFile, cUnitText, 2, 11, cTimeoutMs, mLocation), 'Ziel');
    Assert.AreEqual(4, mLocation.Line, 'Implementierung');
    Assert.AreEqual(1, FServer.Sent('textDocument/declaration'));
    Assert.AreEqual(1, FServer.Sent('textDocument/definition'));
  finally
    mSession.Free;
  end;
end;

procedure TLspMethodNotFoundTests.GotoTargetWithoutDeclarationProvider;
var
  mSession: TLspSession;
  mLocation: TLspLocation;
begin
  FServer.Capabilities := '{"hoverProvider":true,"definitionProvider":true}';
  FServer.Replies.Add('textDocument/definition', LocationAt(4, 10));
  mSession := TLspSession.Create(FServer.Client, cTimeoutMs);
  try
    mSession.Initialize;
    Assert.IsTrue(mSession.GotoTarget(cUnitFile, cUnitText, 2, 11, cTimeoutMs, mLocation), 'Ziel');
    Assert.AreEqual(4, mLocation.Line);
    Assert.AreEqual(0, FServer.Sent('textDocument/declaration'));
    Assert.AreEqual(1, FServer.Sent('textDocument/definition'));
  finally
    mSession.Free;
  end;
end;

procedure TLspMethodNotFoundTests.GotoTargetLearnsMissingDeclaration;
var
  mSession: TLspSession;
  mLocation: TLspLocation;
begin
  FServer.Errors.Add('textDocument/declaration', TLspClient.cMethodNotFound);
  FServer.Replies.Add('textDocument/definition', LocationAt(4, 10));
  mSession := TLspSession.Create(FServer.Client, cTimeoutMs);
  try
    mSession.Initialize;
    Assert.IsTrue(mSession.GotoTarget(cUnitFile, cUnitText, 6, 0, cTimeoutMs, mLocation), 'erstes Mal');
    Assert.AreEqual(4, mLocation.Line);
    Assert.IsTrue(mSession.GotoTarget(cUnitFile, cUnitText, 6, 0, cTimeoutMs, mLocation), 'zweites Mal');
    Assert.AreEqual(1, FServer.Sent('textDocument/declaration'), 'declaration nur einmal');
    Assert.AreEqual(2, FServer.Sent('textDocument/definition'));
  finally
    mSession.Free;
  end;
end;

procedure TLspMethodNotFoundTests.GotoTargetWithoutTarget;
var
  mSession: TLspSession;
  mLocation: TLspLocation;
begin
  FServer.Capabilities := cSlimCapabilities;
  FServer.Replies.Add('textDocument/declaration', 'null');
  mSession := TLspSession.Create(FServer.Client, cTimeoutMs);
  try
    mSession.Initialize;
    Assert.IsFalse(mSession.GotoTarget(cUnitFile, cUnitText, 6, 0, cTimeoutMs, mLocation), 'kein Ziel');
    Assert.AreEqual('', mLocation.FileName);
    Assert.AreEqual(0, FServer.Sent('textDocument/definition'));
  finally
    mSession.Free;
  end;
end;

procedure TLspMethodNotFoundTests.GotoTargetAtReportsNoTargetReason;
var
  mSession: TLspSession;
  mLocation: TLspLocation;
  mNoTarget: TDpccNoTarget;
begin
  FServer.Capabilities := cSlimCapabilities;
  FServer.Replies.Add('textDocument/declaration', 'null');
  FServer.Notices.Add('textDocument/declaration', '{"method":"textDocument/declaration",' +
    '"uri":"file:///C:/Projekt/Unit1.pas","line":6,"character":0,"reason":"unitNotFound","name":"Werkzeuge",' +
    '"indexing":true}');
  mSession := TLspSession.Create(FServer.Client, cTimeoutMs);
  try
    mSession.Initialize;
    Assert.IsFalse(mSession.GotoTargetAt(cUnitFile, 'end;', 6, 0, cTimeoutMs, mLocation, mNoTarget), 'kein Ziel');
    Assert.AreEqual(Ord(TDpccNoTargetReason.UnitNotFound), Ord(mNoTarget.Reason), 'Grund des Servers');
    Assert.AreEqual('Werkzeuge', mNoTarget.Name);
    Assert.IsTrue(mNoTarget.Indexing);
    // Abgeholt: Die nächste leere Antwort ohne Benachrichtigung hat keinen Grund mehr.
    FServer.Notices.Clear;
    Assert.IsFalse(mSession.GotoTargetAt(cUnitFile, 'end;', 6, 0, cTimeoutMs, mLocation, mNoTarget), 'wieder');
    Assert.AreEqual(Ord(TDpccNoTargetReason.Unknown), Ord(mNoTarget.Reason), 'älterer Server: unbekannt');
    Assert.AreEqual('textDocument/declaration', mNoTarget.Method);
  finally
    mSession.Free;
  end;
end;

procedure TLspMethodNotFoundTests.SessionWithoutCapabilitiesLearnsFromServer;
var
  mSession: TLspSession;
  mLocation: TLspLocation;
begin
  // Seit Rückbau R6 ohne Inlay Hints in der Sitzung: gelernt wird an textDocument/definition.
  FServer.Errors.Add('textDocument/definition', TLspClient.cMethodNotFound);
  mSession := TLspSession.Create(FServer.Client, cTimeoutMs);
  try
    mSession.Initialize;
    Assert.IsFalse(FServer.Client.CapabilitiesKnown);
    Assert.IsTrue(mSession.Offers('textDocument/definition'));
    Assert.WillRaise(
      procedure
      begin
        mSession.Definition('C:\Projekt\Unit1.pas', 'unit Unit1;', 0, 5, mLocation);
      end, ELspMethodNotFound);
    Assert.IsFalse(mSession.Offers('textDocument/definition'));
    Assert.WillRaise(
      procedure
      begin
        mSession.Definition('C:\Projekt\Unit1.pas', 'unit Unit1;', 0, 5, mLocation);
      end, ELspMethodNotFound);
    Assert.AreEqual(1, FServer.Sent('textDocument/definition'));
  finally
    mSession.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMethodNotFoundTests);

end.
