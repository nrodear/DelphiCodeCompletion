unit dpcc.Core.Lsp.Client;

// Schlanker LSP-Client für das IDE-Plugin: JSON-RPC mit
// Content-Length-Rahmung, Zuordnung der Antworten zu Anfragen und Warten mit
// Zeitlimit. Der Transport ist ausgelagert: Gesendet wird über ASend (fertig
// gerahmte Bytes), empfangene Bytes kommen über Receive herein, auch in
// beliebigen Stücken und aus einem anderen Thread.
// Anfragen des Servers (z. B. window/workDoneProgress/create) beantwortet der
// Client mit null; Anfragen und Benachrichtigungen gehen außerdem an
// OnServerMessage (im Lese-Thread, z. B. workspace/diagnostic/refresh, #398).
// Anfragen, die OnServerRequest übernimmt (z. B. workspace/applyEdit, #397),
// beantwortet der Empfänger später selbst mit Respond.
// Teilergebnisse (#616): Request mit AOnPartial schickt einen partialResultToken mit; $/progress zu diesem
// Token geht an AOnPartial (im Lese-Thread, vor der Antwort), nicht an OnServerMessage.
// Das Warten auf eine Antwort endet auch beim gemeinsamen Abbruchsignal
// (TDpccShutdown, #493), damit beim Entladen kein Thread im Zeitlimit hängt.
// Für das Statusfeld (#591) merkt sich der Client die Antwortzeiten der
// letzten 50 Anfragen (AverageMs) und meldet das Ende der Verbindung über
// OnClosed (etwa wenn der Serverprozess beendet wurde). workspace/diagnostic
// zählt nicht mit: Der Server hält es absichtlich bis zu 10 s offen
// (Long-Polling), das Statusfeld meldete sonst dauerhaft "langsam"
// (Rückmeldung 15.10.2026).
// Ende der Verbindung: CloseInfo nennt die zuletzt gesendete
// Anfrage, die beim Ende noch offenen und, wenn der Transport sie über
// CloseWith mitgibt, Exit-Code, Laufzeit und Zeilen auf stderr des Servers.
// Fehlende Methoden (Schritt 2, schlanker Server): Antwortet der Server mit
// -32601 (Method not found), merkt sich der Client die Methode, bei
// workspace/executeCommand den Befehl, und schickt sie nicht wieder; weitere
// Anfragen scheitern sofort lokal mit ELspMethodNotFound. Ebenso Anfragen,
// deren Anbieter die Capabilities aus initialize (SetCapabilities) nicht
// nennen. OnMethodNotFound meldet jede fehlende Methode einmal. Der Stand gilt
// je Server-Sitzung: Jeder Serverstart hat einen eigenen Client, und
// SetCapabilities (neues initialize) setzt ihn zurück.
// Wartezeit des Hauptthreads: Ruft der Hauptthread RequestCancellable (bzw.
// Request), misst der Client immer, nennt die Anfrage für den Einfrier-Wächter
// als Aktivität „Warten auf Server <Methode>“ und meldet ab 100 ms eine
// gedrosselte Zeile „Hauptthread wartete n ms auf Server <Methode>: <Ausgang>“
// (Antwort, Zeitlimit, abgebrochen, Fehler) an TDpccSlowLog.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.JSON,
  System.Diagnostics,
  System.Generics.Collections;

type
  TLspSendProc = reference to procedure(const ABytes: TBytes);
  /// <summary>Anfrage oder Benachrichtigung des Servers; läuft im Lese-Thread, AParams gehört dem Client.</summary>
  TLspServerMessageProc = reference to procedure(const AMethod: string; const AParams: TJSONValue);
  /// <summary>Teilergebnis zu einer Anfrage (#616); läuft im Lese-Thread, AValue gehört dem Client.</summary>
  TLspPartialProc = reference to procedure(const AValue: TJSONValue);
  /// <summary>Anfrage des Servers (#397); läuft im Lese-Thread. True: Der Empfänger antwortet später mit
  /// Respond(AId, …), AId gehört dann ihm. False: Der Client antwortet mit null und gibt AId frei.</summary>
  TLspServerRequestFunc = reference to function(const AMethod: string; const AParams: TJSONValue;
    AId: TJSONValue): Boolean;

  ELspClientError = class(Exception);
  /// <summary>Keine Antwort innerhalb des Zeitlimits.</summary>
  ELspTimeoutError = class(ELspClientError);
  /// <summary>Der Aufrufer hat die Anfrage abgebrochen.</summary>
  ELspCancelledError = class(ELspClientError);
  /// <summary>Der Server bietet die Methode nicht an: Fehlerantwort -32601 oder nicht in den Capabilities.</summary>
  ELspMethodNotFound = class(ELspClientError)
  private
    FMethod: string;
  public
    constructor CreateFor(const AMethod, AMessage: string);
    /// <summary>Methode wie TLspClient.MethodKey, bei workspace/executeCommand mit dem Befehl.</summary>
    property Method: string read FMethod;
  end;

  /// <summary>Fehlende Methode AMethod (wie TLspClient.MethodKey), einmal je Sitzung. AReported: Der Server
  /// antwortete -32601; sonst fehlt der Anbieter in den Capabilities.</summary>
  TLspMethodNotFoundProc = reference to procedure(const AMethod: string; AReported: Boolean);

  /// <summary>Capabilities des Servers aus der Antwort auf initialize (nur lesen; TLspClient sperrt).</summary>
  TLspServerCapabilities = class
  private
    FValue: TJSONObject;
  public
    /// <summary>Übernimmt AValue (Objekt "capabilities").</summary>
    constructor Create(AValue: TJSONObject);
    destructor Destroy; override;
    /// <summary>Anbieter zu einer Standardmethode, etwa definitionProvider zu textDocument/definition; '' ohne
    /// Zuordnung (dann entscheidet nur die Antwort des Servers).</summary>
    class function ProviderOf(const AMethod: string): string; static;
    /// <summary>Ist AProvider gesetzt und nicht false oder null?</summary>
    function Supports(const AProvider: string): Boolean;
    /// <summary>Nennt experimental.dpcc.requests die Eigenmethode AMethod? True ohne diese Liste (älterer Server).
    /// </summary>
    function SupportsDpccRequest(const AMethod: string): Boolean;
    /// <summary>Darf die Anfrage AMethod an den Server gehen? Standardmethoden nach ihrem Anbieter, dpcc/… nach
    /// experimental.dpcc.requests; Methoden ohne Zuordnung immer.</summary>
    function Offers(const AMethod: string): Boolean;
  end;

  /// <summary>Wie die Verbindung endete; Exit-Angaben setzt der Transport über CloseWith.</summary>
  TLspCloseInfo = record
    /// <summary>Exit-Code des Servers bekannt?</summary>
    ExitKnown: Boolean;
    ExitCode: Cardinal;
    /// <summary>Laufzeit des Servers in ms; 0 = unbekannt.</summary>
    RuntimeMs: Int64;
    /// <summary>Zuletzt gesendete Anfrage ohne Long-Polling; setzt der Client.</summary>
    LastMethod: string;
    /// <summary>Beim Ende noch offene Anfragen ohne Long-Polling; setzt der Client.</summary>
    OpenMethods: TArray<string>;
  end;

  /// <summary>Ringpuffer der Antwortzeiten der letzten Samples Anfragen (#591); nicht threadsicher, TLspClient
  /// sperrt.</summary>
  TLspResponseTimes = record
  public const
    cSamples = 50;
  private
    FTimes: array[0..cSamples - 1] of Int64;
    FCount: Integer;
    FNext: Integer;
  public
    /// <summary>Nimmt eine Antwortzeit auf; die älteste fällt heraus, wenn Samples erreicht sind.</summary>
    procedure Add(AMilliseconds: Int64);
    /// <summary>Mittelwert der gemerkten Zeiten, 0 ohne Zeiten; ASamples ist ihre Anzahl.</summary>
    function Average(out ASamples: Integer): Double;
  end;

  TLspClient = class
  public const
    /// <summary>Obergrenzen der Rahmung wie im Server (dpcc.Common.JsonRpc.StreamTransport): Kopf 8 KB,
    /// Inhalt 256 MB. Darüber gilt die Verbindung als kaputt.</summary>
    cMaxHeaderLength = 8 * 1024;
    cMaxContentLength = 256 * 1024 * 1024;
    /// <summary>JSON-RPC: Methode unbekannt.</summary>
    cMethodNotFound = -32601;
  private type
    TPending = class
    public
      Method: string;
      Done: TEvent;
      Result: TJSONValue;
      Error: string;
      /// <summary>error.code der Fehlerantwort; 0 ohne.</summary>
      ErrorCode: Integer;
      constructor Create;
      destructor Destroy; override;
    end;
  private
    FSend: TLspSendProc;
    FLock: TObject;
    FPending: TDictionary<Integer, TPending>;
    FPartials: TDictionary<string, TLspPartialProc>;
    FNextId: Integer;
    FNextPartial: Integer;
    FBuffer: TBytes;
    FClosed: Boolean;
    FLastMethod: string;
    FCloseInfo: TLspCloseInfo;
    FOnServerMessage: TLspServerMessageProc;
    FOnServerRequest: TLspServerRequestFunc;
    FOnClosed: TProc;
    FTimes: TLspResponseTimes;
    /// <summary>Capabilities aus initialize; nil = unbekannt (dann wird alles gesendet).</summary>
    FCapabilities: TLspServerCapabilities;
    /// <summary>Fehlende Methoden (MethodKey) dieser Sitzung.</summary>
    FMissing: TDictionary<string, Boolean>;
    FOnMethodNotFound: TLspMethodNotFoundProc;
    procedure SendText(const AText: string);
    /// <summary>Merkt AKey als fehlend; True beim ersten Mal (dann meldet der Aufrufer es über OnMethodNotFound).
    /// Ohne Sperre aufrufen.</summary>
    function NoteMissing(const AKey: string): Boolean;
    /// <summary>OnMethodNotFound für AKey, Fehler des Empfängers verschluckt.</summary>
    procedure ReportMissing(const AKey: string; AReported: Boolean);
    /// <summary>Fehlt AMethod (bzw. der Befehl in AParams)? Dann AParams freigeben und ELspMethodNotFound, ohne zu
    /// senden.</summary>
    procedure RefuseMissing(const AMethod: string; AParams: TJSONValue);
    /// <summary>$/cancelRequest für eine Anfrage, auf die der Client nicht mehr wartet.</summary>
    procedure CancelOnServer(AId: Integer);
    procedure HandleMessage(const AText: string);
    /// <summary>$/progress zu einem Token aus Request mit Teilergebnissen; False, wenn es keines ist.</summary>
    function HandlePartial(AMessage: TJSONObject): Boolean;
    function TakeMessage(out AText: string): Boolean;
    function DoRequest(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
      const ACancelled: TFunc<Boolean>): TJSONValue;
  public const
    /// <summary>So oft fragt Request mit Abbruch nach, ob abgebrochen wurde.</summary>
    cCancelPollMs = 100;
  public
    constructor Create(const ASend: TLspSendProc);
    destructor Destroy; override;
    /// <summary>Rahmt AText mit Content-Length.</summary>
    class function Frame(const AText: string): TBytes; static;
    /// <summary>
    /// Sendet eine Anfrage und wartet auf die Antwort. Übernimmt AParams.
    /// Liefert das Ergebnis (nil bei null), der Aufrufer gibt es frei.
    /// Löst ELspClientError bei Fehlerantwort, Zeitüberschreitung oder beendeter Verbindung aus.
    /// </summary>
    function Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal): TJSONValue; overload;
    /// <summary>Wie oben, abbrechbar (#1351): Meldet ACancelled True, schickt der Client $/cancelRequest und löst
    /// ELspClientError aus, ohne auf die Antwort zu warten.</summary>
    function RequestCancellable(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
      const ACancelled: TFunc<Boolean>): TJSONValue;
    /// <summary>Wie oben mit Teilergebnissen (#616): AParams muss ein Objekt sein; es bekommt einen
    /// partialResultToken. AOnPartial läuft im Lese-Thread für jedes Teilergebnis vor der Antwort.</summary>
    function Request(const AMethod: string; AParams: TJSONObject; ATimeoutMs: Cardinal;
      const AOnPartial: TLspPartialProc): TJSONValue; overload;
    /// <summary>Sendet eine Benachrichtigung. Übernimmt AParams.</summary>
    procedure Notify(const AMethod: string; AParams: TJSONValue);
    /// <summary>Antwort auf eine Anfrage des Servers, die OnServerRequest übernommen hat; übernimmt AId und
    /// AResult (nil = null). Ohne Wirkung nach Close.</summary>
    procedure Respond(AId, AResult: TJSONValue);
    /// <summary>Empfangene Bytes vom Server; threadsicher.</summary>
    procedure Receive(const ABytes: TBytes; ACount: Integer);
    /// <summary>Verbindung beendet: Wartende Anfragen schlagen fehl, neue auch.</summary>
    procedure Close;
    /// <summary>Wie Close, mit den Angaben des Transports zum Ende des Servers (Exit-Code, Laufzeit, stderr).
    /// Nur das erste Close zählt.</summary>
    procedure CloseWith(const AInfo: TLspCloseInfo);
    /// <summary>Angaben zum Ende der Verbindung; leer, solange sie offen ist.</summary>
    function CloseInfo: TLspCloseInfo;
    /// <summary>Antwortzeit einer Anfrage merken; Request ruft das selbst (öffentlich für Tests).</summary>
    procedure AddResponseTime(AMilliseconds: Int64);
    /// <summary>Mittlere Antwortzeit der letzten TLspResponseTimes.cSamples Anfragen in ms; ASamples = deren
    /// Anzahl.</summary>
    function AverageMs(out ASamples: Integer): Double;
    /// <summary>Geht die Antwortzeit von AMethod in AverageMs ein? Nicht bei Long-Polling.</summary>
    class function CountsResponseTime(const AMethod: string): Boolean; static;
    /// <summary>Schlüssel für fehlende Methoden: AMethod, bei workspace/executeCommand "workspace/executeCommand
    /// Befehl".</summary>
    class function MethodKey(const AMethod: string; AParams: TJSONValue): string; static;
    /// <summary>Capabilities aus der Antwort auf initialize; übernimmt AValue, nil = unbekannt. Setzt die
    /// fehlenden Methoden zurück (neue Sitzung).</summary>
    procedure SetCapabilities(AValue: TJSONObject);
    /// <summary>Sind die Capabilities bekannt?</summary>
    function CapabilitiesKnown: Boolean;
    /// <summary>Meldet der Server den Anbieter AProvider (etwa 'hoverProvider')? True, solange die Capabilities
    /// unbekannt sind.</summary>
    function Supports(const AProvider: string): Boolean;
    /// <summary>Darf AMethod (bei workspace/executeCommand mit ACommand) an den Server gehen? False, wenn der Server
    /// sie mit -32601 abgelehnt hat oder die Capabilities sie nicht nennen. Threadsicher.</summary>
    function Offers(const AMethod: string; const ACommand: string = ''): Boolean;
    /// <summary>Fehlende Methoden dieser Sitzung (MethodKey), sortiert.</summary>
    function MissingMethods: TArray<string>;
    /// <summary>Fehlende Methoden vergessen; die nächste Anfrage geht wieder an den Server.</summary>
    procedure ResetMissingMethods;
    property Closed: Boolean read FClosed;
    /// <summary>Vor der ersten Anfrage setzen: je fehlender Methode einmal, im Thread des Aufrufers.</summary>
    property OnMethodNotFound: TLspMethodNotFoundProc read FOnMethodNotFound write FOnMethodNotFound;
    /// <summary>Einmal beim Schließen der Verbindung, im Thread des Schließenden (Lese-Thread bei
    /// beendetem Prozess).</summary>
    property OnClosed: TProc read FOnClosed write FOnClosed;
    /// <summary>Vor dem ersten Receive setzen.</summary>
    property OnServerMessage: TLspServerMessageProc read FOnServerMessage write FOnServerMessage;
    /// <summary>Vor dem ersten Receive setzen.</summary>
    property OnServerRequest: TLspServerRequestFunc read FOnServerRequest write FOnServerRequest;
  end;

  /// <summary>Laufender Sprachserver mit seinem Client; die Freigabe beendet ihn. Den Server im IDE-Prozess
  /// startet die Kompositionswurzel (TLspInProcessServer).</summary>
  IDpccLspServer = interface
    ['{EAC5AE10-77D6-42EA-8AD8-CF869F7B79EC}']
    function Running: Boolean;
    function GetClient: TLspClient;
    property Client: TLspClient read GetClient;
  end;

implementation

uses
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Diagnostics.PluginTimings,
  dpcc.Core.Diagnostics.Hangs,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TClientText = (ErrorResponseFromTheServer, ServerMessageWithoutEndOf, ServerMessageWithBytesExceeds,
    ConnectionToTheServerHas, Cancelled, NoAnswerToDpccIs, NoAnswerToWithinMs, MethodNotSupported);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TClientText] of string = (
    ('Fehlerantwort des Servers',
     'Servernachricht ohne Kopfende',
     'Servernachricht mit %d Bytes über der Grenze von %d Bytes',
     'Verbindung zum Server ist beendet',
     '%s abgebrochen',
     'Keine Antwort auf %s: dpcc wird beendet',
     'Keine Antwort auf %s innerhalb von %d ms',
     'Methode nicht unterstützt: %s'),
    ('Error response from the server',
     'Server message without end of header',
     'Server message with %d bytes exceeds the limit of %d bytes',
     'Connection to the server has ended',
     '%s cancelled',
     'No answer to %s: dpcc is shutting down',
     'No answer to %s within %d ms',
     'Method not supported: %s'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TClientText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

const
  cHeaderEnd: array[0..3] of Byte = (13, 10, 13, 10);

type
  /// <summary>Ablauf einer Anfrage aus TLspClient.DoRequest: anmelden, senden, auf die Antwort warten,
  /// auswerten und abmelden.</summary>
  TLspRequestRun = class
  private
    FClient: TLspClient;
    FPending: TLspClient.TPending;
    FId: Integer;
    FMethod: string;
    /// <summary>TLspClient.MethodKey der Anfrage (für -32601).</summary>
    FKey: string;
    FTimeoutMs: Cardinal;
    FCancelled: TFunc<Boolean>;
    procedure Register(AParams: TJSONValue);
    procedure Unregister;
    function WaitSliced: TWaitResult;
    function Wait: TWaitResult;
    procedure Check(AWait: TWaitResult; AElapsedMs: Int64);
  public
    constructor Create(AClient: TLspClient; const AMethod: string; ATimeoutMs: Cardinal;
      const ACancelled: TFunc<Boolean>);
    destructor Destroy; override;
    /// <summary>Sendet die Anfrage mit AParams (gehen in jedem Fall in den Besitz des Ablaufs über) und liefert
    /// das Ergebnis; ELspClientError bei Fehlerantwort, Zeitlimit, Abbruch oder beendeter Verbindung.</summary>
    function Execute(AParams: TJSONValue): TJSONValue;
  end;

/// <summary>JSON-RPC-Nachricht mit jsonrpc, id (nur wenn AId > 0), method und params (AParams geht in die
/// Nachricht über).</summary>
function MessageText(AId: Integer; const AMethod: string; AParams: TJSONValue): string;
var
  mMessage: TJSONObject;
begin
  mMessage := TJSONObject.Create;
  try
    mMessage.AddPair('jsonrpc', '2.0');
    if AId > 0 then
    begin
      mMessage.AddPair('id', TJSONNumber.Create(AId));
    end;
    mMessage.AddPair('method', AMethod);
    if AParams <> nil then
    begin
      mMessage.AddPair('params', AParams);
    end;
    Result := mMessage.ToJSON;
  finally
    mMessage.Free;
  end;
end;

/// <summary>Antwort mit result null auf die Anfrage mit AId (AId bleibt beim Aufrufer).</summary>
function NullReplyText(AId: TJSONValue): string;
var
  mReply: TJSONObject;
begin
  mReply := TJSONObject.Create;
  try
    mReply.AddPair('jsonrpc', '2.0');
    mReply.AddPair('id', TJSONValue(AId.Clone));
    mReply.AddPair('result', TJSONNull.Create);
    Result := mReply.ToJSON;
  finally
    mReply.Free;
  end;
end;

/// <summary>Gibt die Anfrage AMessage an OnServerRequest; True, wenn der Empfänger sie übernommen hat und
/// später selbst antwortet.</summary>
function OfferServerRequest(AClient: TLspClient; AMessage: TJSONObject; AIdValue: TJSONValue): Boolean;
var
  mIdCopy: TJSONValue;
begin
  Result := False;
  if not Assigned(AClient.FOnServerRequest) then
  begin
    Exit;
  end;
  mIdCopy := TJSONValue(AIdValue.Clone);
  try
    Result := AClient.FOnServerRequest(AMessage.GetValue<string>('method', ''), AMessage.GetValue('params'), mIdCopy);
  except
    on Exception do
      Result := False;
  end;
  if not Result then
  begin
    mIdCopy.Free;
  end;
end;

/// <summary>Anfrage oder Benachrichtigung des Servers: Teilergebnis, OnServerMessage und bei Anfragen
/// OnServerRequest oder eine Antwort mit null, damit der Server nicht wartet.</summary>
procedure HandleServerMessage(AClient: TLspClient; AMessage: TJSONObject; AIdValue: TJSONValue);
begin
  if (AIdValue = nil) and AClient.HandlePartial(AMessage) then
  begin
    Exit;
  end;
  if Assigned(AClient.FOnServerMessage) then
    try
      AClient.FOnServerMessage(AMessage.GetValue<string>('method', ''), AMessage.GetValue('params'));
    except
      // Ein Fehler im Empfänger darf den Lese-Thread nicht beenden.
      on Exception do
        ;
    end;
  if (AIdValue <> nil) and not OfferServerRequest(AClient, AMessage, AIdValue) then
  begin
    AClient.SendText(NullReplyText(AIdValue));
  end;
end;

/// <summary>Antwort auf die eigene Anfrage AId: Ergebnis oder Fehler an die wartende Anfrage geben.</summary>
procedure AnswerPending(AClient: TLspClient; AMessage: TJSONObject; AId: Integer);
var
  mPending: TLspClient.TPending;
  mResultValue, mErrorValue: TJSONValue;
begin
  TMonitor.Enter(AClient.FLock);
  try
    if not AClient.FPending.TryGetValue(AId, mPending) then
    begin
      Exit;
    end;
    mErrorValue := AMessage.GetValue('error');
    mResultValue := AMessage.GetValue('result');
    if mErrorValue is TJSONObject then
    begin
      mPending.Error := TJSONObject(mErrorValue).GetValue<string>('message', UiText(TClientText.ErrorResponseFromTheServer));
      // Leere Meldung hieße sonst Erfolg.
      if mPending.Error = '' then
      begin
        mPending.Error := UiText(TClientText.ErrorResponseFromTheServer);
      end;
      mPending.ErrorCode := TJSONObject(mErrorValue).GetValue<Integer>('code', 0);
    end
    else if (mResultValue <> nil) and not (mResultValue is TJSONNull) then
    begin
      mPending.Result := TJSONValue(mResultValue.Clone);
    end;
    mPending.Done.SetEvent;
  finally
    TMonitor.Exit(AClient.FLock);
  end;
end;

/// <summary>Index des Kopfendes (CR LF CR LF) in den ersten MaxHeaderLength Bytes, -1 ohne.</summary>
function HeaderEndIndex(const ABuffer: TBytes): Integer;
var
  mIndex, mLast: Integer;
begin
  Result := -1;
  // Nur im möglichen Kopf suchen, nicht im ganzen Puffer.
  mLast := Length(ABuffer) - Length(cHeaderEnd);
  if mLast > TLspClient.cMaxHeaderLength then
  begin
    mLast := TLspClient.cMaxHeaderLength;
  end;
  mIndex := 0;
  while (Result < 0) and (mIndex <= mLast) do
  begin
    if CompareMem(@ABuffer[mIndex], @cHeaderEnd[0], Length(cHeaderEnd)) then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Kein Kopfende in den ersten MaxHeaderLength Bytes: kein LSP, Verbindung aufgeben statt den
/// Speicher zu füllen.</summary>
procedure RejectEndlessHeader(var ABuffer: TBytes);
begin
  if Length(ABuffer) >= TLspClient.cMaxHeaderLength + Length(cHeaderEnd) then
  begin
    ABuffer := nil;
    raise ELspClientError.Create(UiText(TClientText.ServerMessageWithoutEndOf));
  end;
end;

/// <summary>Nachricht über MaxContentLength: Verbindung aufgeben statt den Speicher zu füllen.</summary>
procedure RejectOversizedBody(var ABuffer: TBytes; ABodyLength: Integer);
begin
  if ABodyLength > TLspClient.cMaxContentLength then
  begin
    ABuffer := nil;
    raise ELspClientError.CreateFmt(UiText(TClientText.ServerMessageWithBytesExceeds),
      [ABodyLength, TLspClient.cMaxContentLength]);
  end;
end;

/// <summary>Wert von Content-Length im Kopf, -1 ohne oder bei ungültiger Zahl.</summary>
function ContentLengthOf(const AHeader: string): Integer;
var
  mLine: string;
begin
  Result := -1;
  for mLine in AHeader.Split([#13#10]) do
  begin
    if mLine.StartsWith('Content-Length:', True) then
    begin
      Result := StrToIntDef(mLine.Substring(Length('Content-Length:')).Trim, -1);
    end;
  end;
end;

{ TLspRequestRun }

constructor TLspRequestRun.Create(AClient: TLspClient; const AMethod: string; ATimeoutMs: Cardinal;
  const ACancelled: TFunc<Boolean>);
begin
  inherited Create;
  FClient := AClient;
  FMethod := AMethod;
  FTimeoutMs := ATimeoutMs;
  FCancelled := ACancelled;
  FPending := TLspClient.TPending.Create;
  FPending.Method := AMethod;
end;

destructor TLspRequestRun.Destroy;
begin
  FPending.Free;
  inherited;
end;

procedure TLspRequestRun.Register(AParams: TJSONValue);
begin
  TMonitor.Enter(FClient.FLock);
  try
    if FClient.FClosed then
    begin
      AParams.Free;
      raise ELspClientError.Create(UiText(TClientText.ConnectionToTheServerHas));
    end;
    Inc(FClient.FNextId);
    FId := FClient.FNextId;
    FClient.FPending.Add(FId, FPending);
    if TLspClient.CountsResponseTime(FMethod) then
    begin
      FClient.FLastMethod := FMethod;
    end;
  finally
    TMonitor.Exit(FClient.FLock);
  end;
end;

procedure TLspRequestRun.Unregister;
begin
  TMonitor.Enter(FClient.FLock);
  try
    FClient.FPending.Remove(FId);
  finally
    TMonitor.Exit(FClient.FLock);
  end;
end;

function TLspRequestRun.WaitSliced: TWaitResult;
var
  mSlice, mWaited: Cardinal;
begin
  // In Scheiben warten, damit „Abbrechen“ nicht bis zum Zeitlimit hängt.
  mWaited := 0;
  repeat
    mSlice := TLspClient.cCancelPollMs;
    if FTimeoutMs - mWaited < mSlice then
    begin
      mSlice := FTimeoutMs - mWaited;
    end;
    Result := TDpccShutdown.WaitFor(FPending.Done, mSlice);
    Inc(mWaited, mSlice);
    if (Result = wrTimeout) and FCancelled() then
    begin
      FClient.CancelOnServer(FId);
      raise ELspCancelledError.CreateFmt(UiText(TClientText.Cancelled), [FMethod]);
    end;
  until (Result <> wrTimeout) or (mWaited >= FTimeoutMs);
end;

function TLspRequestRun.Wait: TWaitResult;
begin
  if Assigned(FCancelled) then
  begin
    Result := WaitSliced;
  end
  else
  begin
    Result := TDpccShutdown.WaitFor(FPending.Done, FTimeoutMs);
  end;
end;

procedure TLspRequestRun.Check(AWait: TWaitResult; AElapsedMs: Int64);
var
  mCounts: Boolean;
begin
  mCounts := TLspClient.CountsResponseTime(FMethod);
  case AWait of
    wrSignaled:
      // Beendete Verbindung ist keine Antwort und zählt nicht.
      if not FClient.FClosed and mCounts then
      begin
        FClient.AddResponseTime(AElapsedMs);
      end;
    wrAbandoned:
      raise ELspClientError.CreateFmt(UiText(TClientText.NoAnswerToDpccIs), [FMethod]);
  else
    begin
      if mCounts then
      begin
        FClient.AddResponseTime(FTimeoutMs);
      end;
      // Sonst rechnet der Server weiter, während schon die nächste Anfrage kommt (CPU-Last).
      FClient.CancelOnServer(FId);
      raise ELspTimeoutError.CreateFmt(UiText(TClientText.NoAnswerToWithinMs), [FMethod, FTimeoutMs]);
    end;
  end;
end;

function TLspRequestRun.Execute(AParams: TJSONValue): TJSONValue;
var
  mText: string;
  mWatch: TStopwatch;
begin
  Register(AParams);
  mText := MessageText(FId, FMethod, AParams);
  try
    mWatch := TStopwatch.StartNew;
    FClient.SendText(mText);
    Check(Wait, mWatch.ElapsedMilliseconds);
  finally
    Unregister;
  end;
  if FPending.Error <> '' then
  begin
    if FPending.ErrorCode = TLspClient.cMethodNotFound then
    begin
      // Nicht wieder senden; die Meldung nur beim ersten Mal.
      if FClient.NoteMissing(FKey) then
      begin
        FClient.ReportMissing(FKey, True);
      end;
      raise ELspMethodNotFound.CreateFor(FKey, FPending.Error);
    end;
    raise ELspClientError.Create(FPending.Error);
  end;
  Result := FPending.Result;
  FPending.Result := nil;
end;

{ TLspClient.TPending }

constructor TLspClient.TPending.Create;
begin
  inherited Create;
  Done := TEvent.Create(nil, True, False, '');
end;

destructor TLspClient.TPending.Destroy;
begin
  Result.Free;
  Done.Free;
  inherited;
end;

{ TLspClient }

constructor TLspClient.Create(const ASend: TLspSendProc);
begin
  inherited Create;
  FSend := ASend;
  FLock := TObject.Create;
  FPending := TDictionary<Integer, TPending>.Create;
  FPartials := TDictionary<string, TLspPartialProc>.Create;
  FMissing := TDictionary<string, Boolean>.Create;
end;

destructor TLspClient.Destroy;
begin
  Close;
  FCapabilities.Free;
  FMissing.Free;
  FPartials.Free;
  FPending.Free;
  FLock.Free;
  inherited;
end;

class function TLspClient.Frame(const AText: string): TBytes;
var
  mBody: TBytes;
  mHeader: TBytes;
begin
  mBody := TEncoding.UTF8.GetBytes(AText);
  mHeader := TEncoding.UTF8.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(mBody)]));
  Result := mHeader + mBody;
end;

procedure TLspClient.SendText(const AText: string);
begin
  FSend(Frame(AText));
end;

function TLspClient.Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := RequestCancellable(AMethod, AParams, ATimeoutMs, nil);
end;

const
  cExecuteCommand = 'workspace/executeCommand';

/// <summary>Auch der Name der Anfrage im Diagnose-Fenster: bei workspace/executeCommand mit dem Befehl
/// (2.0-stable: alle Serverbefehle standen in einer Zeile, ohne zu zeigen, welcher scheitert).</summary>
class function TLspClient.MethodKey(const AMethod: string; AParams: TJSONValue): string;
var
  mCommand: string;
begin
  Result := AMethod;
  if (AMethod = cExecuteCommand) and (AParams is TJSONObject) and
    TJSONObject(AParams).TryGetValue<string>('command', mCommand) then
  begin
    Result := AMethod + ' ' + mCommand;
  end;
end;

function TLspClient.NoteMissing(const AKey: string): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := not FMissing.ContainsKey(AKey);
    if Result then
    begin
      FMissing.Add(AKey, True);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspClient.ReportMissing(const AKey: string; AReported: Boolean);
var
  mHandler: TLspMethodNotFoundProc;
begin
  mHandler := FOnMethodNotFound;
  if Assigned(mHandler) then
    try
      mHandler(AKey, AReported);
    except
      // Ein Fehler im Empfänger darf die Anfrage nicht anders scheitern lassen.
      on Exception do
        ;
    end;
end;

procedure TLspClient.RefuseMissing(const AMethod: string; AParams: TJSONValue);
var
  mKey: string;
  mMissing, mFirst: Boolean;
begin
  mKey := MethodKey(AMethod, AParams);
  mFirst := False;
  TMonitor.Enter(FLock);
  try
    mMissing := FMissing.ContainsKey(mKey);
    if not mMissing and (FCapabilities <> nil) and not FCapabilities.Offers(AMethod) then
    begin
      // Nicht in den Capabilities: ab jetzt wie eine abgelehnte Methode.
      FMissing.Add(mKey, True);
      mMissing := True;
      mFirst := True;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  if not mMissing then
  begin
    Exit;
  end;
  AParams.Free;
  if mFirst then
  begin
    ReportMissing(mKey, False);
  end;
  raise ELspMethodNotFound.CreateFor(mKey, Format(UiText(TClientText.MethodNotSupported), [mKey]));
end;

/// <summary>Ausgang einer Anfrage für die Zeile „Hauptthread wartete …“ im dpcc.log.</summary>
function OutcomeText(AOutcome: TDpccRequestOutcome): string;
begin
  case AOutcome of
    TDpccRequestOutcome.Done:
      Result := 'Antwort';
    TDpccRequestOutcome.TimedOut:
      Result := 'Zeitlimit';
    TDpccRequestOutcome.Cancelled:
      Result := 'abgebrochen';
  else
    Result := 'Fehler';
  end;
end;

function TLspClient.RequestCancellable(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
  const ACancelled: TFunc<Boolean>): TJSONValue;
var
  mWatch: TStopwatch;
  mOutcome: TDpccRequestOutcome;
  mLabel: string;
  mMain: Boolean;
  mActivity: IInterface;
begin
  // Fehlende Methode: gar nicht erst senden, auch nicht im Diagnose-Fenster zählen.
  RefuseMissing(AMethod, AParams);
  // Wartet der Hauptthread, wird immer gemessen (dpcc.log ab TDpccSlowLog.cWaitMs); sonst nur im Diagnosemodus.
  mMain := TDpccActivity.IsMainThread;
  if not mMain and not TDpccPluginTimings.Enabled then
  begin
    Exit(DoRequest(AMethod, AParams, ATimeoutMs, ACancelled));
  end;
  // Diagnose-Fenster, Reiter „Server“: Dauer und Ausgang jeder Anfrage. Der Name vorher: DoRequest übernimmt
  // AParams.
  mLabel := MethodKey(AMethod, AParams);
  if mMain then
  begin
    // Name für den Einfrier-Wächter, solange der Hauptthread auf die Antwort wartet; die Dauer meldet NoteWait.
    mActivity := TDpccActivity.Waiting('Warten auf Server ' + mLabel);
  end;
  mWatch := TStopwatch.StartNew;
  mOutcome := TDpccRequestOutcome.Failed;
  try
    try
      Result := DoRequest(AMethod, AParams, ATimeoutMs, ACancelled);
      mOutcome := TDpccRequestOutcome.Done;
    except
      on ELspTimeoutError do
      begin
        mOutcome := TDpccRequestOutcome.TimedOut;
        raise;
      end;
      on ELspCancelledError do
      begin
        mOutcome := TDpccRequestOutcome.Cancelled;
        raise;
      end;
    end;
  finally
    if TDpccPluginTimings.Enabled then
    begin
      TDpccPluginTimings.NoteRequest(mLabel, mWatch.Elapsed.TotalMilliseconds, mOutcome);
    end;
    if mMain then
    begin
      TDpccSlowLog.NoteWait(mLabel, mWatch.ElapsedMilliseconds, OutcomeText(mOutcome));
    end;
  end;
end;

function TLspClient.DoRequest(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
  const ACancelled: TFunc<Boolean>): TJSONValue;
var
  mRun: TLspRequestRun;
begin
  mRun := TLspRequestRun.Create(Self, AMethod, ATimeoutMs, ACancelled);
  try
    // Vor Execute: Execute übernimmt AParams.
    mRun.FKey := MethodKey(AMethod, AParams);
    Result := mRun.Execute(AParams);
  finally
    mRun.Free;
  end;
end;

function TLspClient.Request(const AMethod: string; AParams: TJSONObject; ATimeoutMs: Cardinal;
  const AOnPartial: TLspPartialProc): TJSONValue;
var
  mToken: string;
begin
  if not Assigned(AOnPartial) then
  begin
    Exit(Request(AMethod, AParams, ATimeoutMs));
  end;
  TMonitor.Enter(FLock);
  try
    Inc(FNextPartial);
    mToken := 'dpcc-partial-' + IntToStr(FNextPartial);
    FPartials.Add(mToken, AOnPartial);
  finally
    TMonitor.Exit(FLock);
  end;
  try
    AParams.AddPair('partialResultToken', mToken);
    Result := Request(AMethod, AParams, ATimeoutMs);
  finally
    TMonitor.Enter(FLock);
    try
      FPartials.Remove(mToken);
    finally
      TMonitor.Exit(FLock);
    end;
  end;
end;

procedure TLspClient.Notify(const AMethod: string; AParams: TJSONValue);
var
  mText: string;
begin
  mText := MessageText(0, AMethod, AParams);
  if not FClosed then
  begin
    SendText(mText);
  end;
end;

procedure TLspClient.CancelOnServer(AId: Integer);
begin
  try
    Notify('$/cancelRequest', TJSONObject.Create.AddPair('id', TJSONNumber.Create(AId)));
  except
    // Abbruch ist ein Hinweis an den Server; scheitert das Senden, bleibt es bei der Zeitüberschreitung.
    on Exception do
      ;
  end;
end;

function TLspClient.HandlePartial(AMessage: TJSONObject): Boolean;
var
  mParams, mToken: TJSONValue;
  mPartial: TLspPartialProc;
begin
  Result := False;
  if AMessage.GetValue<string>('method', '') <> '$/progress' then
  begin
    Exit;
  end;
  mParams := AMessage.GetValue('params');
  if not (mParams is TJSONObject) then
  begin
    Exit;
  end;
  mToken := TJSONObject(mParams).GetValue('token');
  if not (mToken is TJSONString) then
  begin
    Exit;
  end;
  TMonitor.Enter(FLock);
  try
    if not FPartials.TryGetValue(TJSONString(mToken).Value, mPartial) then
    begin
      Exit;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := True;
  try
    mPartial(TJSONObject(mParams).GetValue('value'));
  except
    // Ein Fehler im Empfänger darf den Lese-Thread nicht beenden.
    on Exception do
      ;
  end;
end;

procedure TLspClient.HandleMessage(const AText: string);
var
  mValue: TJSONValue;
  mMessage: TJSONObject;
  mIdValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AText);
  try
    if mValue is TJSONObject then
    begin
      mMessage := TJSONObject(mValue);
      mIdValue := mMessage.GetValue('id');
      if mMessage.GetValue('method') <> nil then
      begin
        HandleServerMessage(Self, mMessage, mIdValue);
      end
      else if mIdValue is TJSONNumber then
      begin
        AnswerPending(Self, mMessage, TJSONNumber(mIdValue).AsInt);
      end;
    end;
  finally
    mValue.Free;
  end;
end;

procedure TLspClient.Respond(AId, AResult: TJSONValue);
var
  mReply: TJSONObject;
  mText: string;
begin
  mReply := TJSONObject.Create;
  try
    mReply.AddPair('jsonrpc', '2.0');
    mReply.AddPair('id', AId);
    if AResult = nil then
    begin
      mReply.AddPair('result', TJSONNull.Create);
    end
    else
    begin
      mReply.AddPair('result', AResult);
    end;
    mText := mReply.ToJSON;
  finally
    mReply.Free;
  end;
  if not FClosed then
  begin
    SendText(mText);
  end;
end;

function TLspClient.TakeMessage(out AText: string): Boolean;
var
  mHeaderLength, mLen, mBodyLength: Integer;
begin
  Result := False;
  mHeaderLength := HeaderEndIndex(FBuffer);
  if mHeaderLength < 0 then
  begin
    RejectEndlessHeader(FBuffer);
    Exit;
  end;
  mBodyLength := ContentLengthOf(TEncoding.UTF8.GetString(FBuffer, 0, mHeaderLength));
  mLen := mHeaderLength + Length(cHeaderEnd);
  if mBodyLength < 0 then
  begin
    // Kaputter Kopf: verwerfen und weitermachen.
    Delete(FBuffer, 0, mLen);
    Exit(True);
  end;
  RejectOversizedBody(FBuffer, mBodyLength);
  if Length(FBuffer) >= mLen + mBodyLength then
  begin
    AText := TEncoding.UTF8.GetString(FBuffer, mLen, mBodyLength);
    Delete(FBuffer, 0, mLen + mBodyLength);
    Result := True;
  end;
end;

procedure TLspClient.Receive(const ABytes: TBytes; ACount: Integer);
var
  mMessages: TList<string>;
  mText: string;
  mStart: Integer;
begin
  mMessages := TList<string>.Create;
  try
    TMonitor.Enter(FLock);
    try
      mStart := Length(FBuffer);
      SetLength(FBuffer, mStart + ACount);
      if ACount > 0 then
      begin
        Move(ABytes[0], FBuffer[mStart], ACount);
      end;
      mText := '';
      while TakeMessage(mText) do
      begin
        if mText <> '' then
        begin
          mMessages.Add(mText);
          mText := '';
        end;
      end;
    finally
      TMonitor.Exit(FLock);
    end;
    // Außerhalb der Sperre: HandleMessage sperrt selbst und sendet ggf.
    for mText in mMessages do
    begin
      HandleMessage(mText);
    end;
  finally
    mMessages.Free;
  end;
end;

procedure TLspClient.Close;
begin
  CloseWith(Default(TLspCloseInfo));
end;

procedure TLspClient.CloseWith(const AInfo: TLspCloseInfo);
var
  mPending: TPending;
  mWasOpen: Boolean;
  mHandler: TProc;
begin
  TMonitor.Enter(FLock);
  try
    mWasOpen := not FClosed;
    FClosed := True;
    if mWasOpen then
    begin
      FCloseInfo := AInfo;
      FCloseInfo.LastMethod := FLastMethod;
      FCloseInfo.OpenMethods := nil;
      for mPending in FPending.Values do
      begin
        if CountsResponseTime(mPending.Method) then
        begin
          FCloseInfo.OpenMethods := FCloseInfo.OpenMethods + [mPending.Method];
        end;
      end;
    end;
    for mPending in FPending.Values do
    begin
      mPending.Error := UiText(TClientText.ConnectionToTheServerHas);
      mPending.Done.SetEvent;
    end;
    mHandler := FOnClosed;
  finally
    TMonitor.Exit(FLock);
  end;
  if mWasOpen and Assigned(mHandler) then
    try
      mHandler();
    except
      // Ein Fehler im Empfänger darf das Schließen nicht abbrechen.
      on Exception do
        ;
    end;
end;

function TLspClient.CloseInfo: TLspCloseInfo;
begin
  TMonitor.Enter(FLock);
  try
    Result := FCloseInfo;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspClient.AddResponseTime(AMilliseconds: Int64);
begin
  TMonitor.Enter(FLock);
  try
    FTimes.Add(AMilliseconds);
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TLspClient.CountsResponseTime(const AMethod: string): Boolean;
begin
  Result := not SameText(AMethod, 'workspace/diagnostic');
end;

function TLspClient.AverageMs(out ASamples: Integer): Double;
begin
  TMonitor.Enter(FLock);
  try
    Result := FTimes.Average(ASamples);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspClient.SetCapabilities(AValue: TJSONObject);
var
  mNew: TLspServerCapabilities;
begin
  mNew := nil;
  if AValue <> nil then
  begin
    mNew := TLspServerCapabilities.Create(AValue);
  end;
  TMonitor.Enter(FLock);
  try
    FCapabilities.Free;
    FCapabilities := mNew;
    FMissing.Clear;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspClient.CapabilitiesKnown: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FCapabilities <> nil;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspClient.Supports(const AProvider: string): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := (FCapabilities = nil) or FCapabilities.Supports(AProvider);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspClient.Offers(const AMethod: string; const ACommand: string): Boolean;
var
  mKey: string;
begin
  mKey := AMethod;
  if ACommand <> '' then
  begin
    mKey := AMethod + ' ' + ACommand;
  end;
  TMonitor.Enter(FLock);
  try
    Result := not FMissing.ContainsKey(mKey) and ((FCapabilities = nil) or FCapabilities.Offers(AMethod));
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TLspClient.MissingMethods: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FMissing.Keys.ToArray;
  finally
    TMonitor.Exit(FLock);
  end;
  TArray.Sort<string>(Result);
end;

procedure TLspClient.ResetMissingMethods;
begin
  TMonitor.Enter(FLock);
  try
    FMissing.Clear;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ ELspMethodNotFound }

constructor ELspMethodNotFound.CreateFor(const AMethod, AMessage: string);
begin
  inherited Create(AMessage);
  FMethod := AMethod;
end;

{ TLspServerCapabilities }

constructor TLspServerCapabilities.Create(AValue: TJSONObject);
begin
  inherited Create;
  FValue := AValue;
end;

destructor TLspServerCapabilities.Destroy;
begin
  FValue.Free;
  inherited;
end;

class function TLspServerCapabilities.ProviderOf(const AMethod: string): string;
const
  // Methode und Anbieter in initialize.capabilities (LSP 3.17).
  cProviders: array[0..30, 0..1] of string = (
    ('textDocument/completion', 'completionProvider'),
    ('completionItem/resolve', 'completionProvider'),
    ('textDocument/hover', 'hoverProvider'),
    ('textDocument/signatureHelp', 'signatureHelpProvider'),
    ('textDocument/definition', 'definitionProvider'),
    ('textDocument/declaration', 'declarationProvider'),
    ('textDocument/typeDefinition', 'typeDefinitionProvider'),
    ('textDocument/implementation', 'implementationProvider'),
    ('textDocument/references', 'referencesProvider'),
    ('textDocument/documentHighlight', 'documentHighlightProvider'),
    ('textDocument/documentSymbol', 'documentSymbolProvider'),
    ('workspace/symbol', 'workspaceSymbolProvider'),
    ('textDocument/codeAction', 'codeActionProvider'),
    ('textDocument/codeLens', 'codeLensProvider'),
    ('textDocument/formatting', 'documentFormattingProvider'),
    ('textDocument/rangeFormatting', 'documentRangeFormattingProvider'),
    ('textDocument/onTypeFormatting', 'documentOnTypeFormattingProvider'),
    ('textDocument/prepareRename', 'renameProvider'),
    ('textDocument/rename', 'renameProvider'),
    ('textDocument/selectionRange', 'selectionRangeProvider'),
    ('textDocument/linkedEditingRange', 'linkedEditingRangeProvider'),
    ('textDocument/foldingRange', 'foldingRangeProvider'),
    ('textDocument/inlayHint', 'inlayHintProvider'),
    ('textDocument/inlineValue', 'inlineValueProvider'),
    ('textDocument/diagnostic', 'diagnosticProvider'),
    ('workspace/diagnostic', 'diagnosticProvider'),
    ('textDocument/prepareCallHierarchy', 'callHierarchyProvider'),
    ('textDocument/prepareTypeHierarchy', 'typeHierarchyProvider'),
    ('callHierarchy/', 'callHierarchyProvider'),
    ('typeHierarchy/', 'typeHierarchyProvider'),
    (cExecuteCommand, 'executeCommandProvider'));
var
  mIndex: Integer;
begin
  for mIndex := Low(cProviders) to High(cProviders) do
  begin
    // Einträge mit "/" am Ende gelten für alle Methoden der Gruppe (callHierarchy/incomingCalls …).
    if (cProviders[mIndex, 0].EndsWith('/') and AMethod.StartsWith(cProviders[mIndex, 0])) or
      (AMethod = cProviders[mIndex, 0]) then
    begin
      Exit(cProviders[mIndex, 1]);
    end;
  end;
  Result := '';
end;

function TLspServerCapabilities.Supports(const AProvider: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := FValue.GetValue(AProvider);
  Result := (mValue <> nil) and not (mValue is TJSONNull) and
    not ((mValue is TJSONBool) and not TJSONBool(mValue).AsBoolean);
end;

function TLspServerCapabilities.SupportsDpccRequest(const AMethod: string): Boolean;
var
  mRequests: TJSONArray;
  mItem: TJSONValue;
begin
  if not FValue.TryGetValue<TJSONArray>('experimental.dpcc.requests', mRequests) then
  begin
    Exit(True);
  end;
  for mItem in mRequests do
  begin
    if (mItem is TJSONString) and SameText(TJSONString(mItem).Value, AMethod) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TLspServerCapabilities.Offers(const AMethod: string): Boolean;
var
  mProvider: string;
begin
  if AMethod.StartsWith('dpcc/') then
  begin
    Exit(SupportsDpccRequest(AMethod));
  end;
  mProvider := ProviderOf(AMethod);
  Result := (mProvider = '') or Supports(mProvider);
end;

{ TLspResponseTimes }

procedure TLspResponseTimes.Add(AMilliseconds: Int64);
begin
  FTimes[FNext] := AMilliseconds;
  FNext := (FNext + 1) mod cSamples;
  if FCount < cSamples then
  begin
    Inc(FCount);
  end;
end;

function TLspResponseTimes.Average(out ASamples: Integer): Double;
var
  mIndex: Integer;
  mSum: Int64;
begin
  ASamples := FCount;
  mSum := 0;
  for mIndex := 0 to FCount - 1 do
  begin
    Inc(mSum, FTimes[mIndex]);
  end;
  Result := 0;
  if ASamples > 0 then
  begin
    Result := mSum / ASamples;
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Lsp.Client', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
