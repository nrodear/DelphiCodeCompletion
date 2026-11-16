unit Shell.Composition.Protocol;

// Teilwurzel Protokoll der Komposition: Verteiler mit Watchdog, Statistik und den letzten Nachrichten und
// Lebenszyklus (initialize/shutdown). Die Komposition reicht Logger, Transport, Zeitlimit und die Fähigkeiten für
// initialize herein. Absturzfälle samt Sicherheitsnetz (#1355, dpcc/crashCase, dpcc/crashSkip) gibt es seit
// Rückbau R3 (Frage 14) nicht mehr; fehlgeschlagene Anfragen stehen nur im Log.

interface

uses
  System.SysUtils,
  System.JSON,
  dpcc.Common.Logging.Contract,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.JsonRpc.Statistics,
  dpcc.Common.JsonRpc.RecentMessages,
  dpcc.Common.Lsp.Contract,
  dpcc.Common.Lsp.Lifecycle;

type
  /// <summary>Was das Protokoll von der Komposition braucht.</summary>
  TShellProtocolServices = record
    Logger: ILogger;
    /// <summary>Anfragen, die länger laufen, bricht der Watchdog ab und meldet sie.</summary>
    TimeoutMs: Cardinal;
    /// <summary>Fähigkeiten für die Antwort auf initialize.</summary>
    Capabilities: TLspCapabilitiesFactory;
  end;

  /// <summary>Hält Verteiler, Statistik, letzte Nachrichten und Lebenszyklus.</summary>
  TShellProtocol = class
  private
    FServices: TShellProtocolServices;
    FDispatcher: TJsonRpcDispatcher;
    FStatistics: IJsonRpcStatistics;
    /// <summary>Die letzten Nachrichten des Clients für das Diagnoselog.</summary>
    FRecent: IJsonRpcRecentMessages;
    FLifecycle: TLspLifecycle;
    /// <summary>Meldung des Watchdogs, wenn eine Anfrage ihr Zeitlimit überschreitet.</summary>
    procedure RequestTimedOut(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean);
    /// <summary>Protokolliert eine fehlgeschlagene Anfrage.</summary>
    procedure RequestFailed(const AMethod: string; const AParams: TJSONValue; const AError: Exception);
  public
    /// <summary>Verteiler mit Watchdog und Fehlerprotokoll, Lebenszyklus am Verteiler.</summary>
    constructor Create(const AServices: TShellProtocolServices);
    /// <summary>Gibt Lebenszyklus und Verteiler in dieser Reihenfolge frei.</summary>
    destructor Destroy; override;
    property Dispatcher: TJsonRpcDispatcher read FDispatcher;
    property Statistics: IJsonRpcStatistics read FStatistics;
    property Lifecycle: TLspLifecycle read FLifecycle;
  end;

implementation

uses
  dpcc.Common.JsonRpc.Watchdog,
  dpcc.Common.Product.Version,
  Shell.Platform,
  dpcc.Text.LogMarks;

constructor TShellProtocol.Create(const AServices: TShellProtocolServices);
var
  mWatchdog: TJsonRpcWatchdog;
begin
  inherited Create;
  FServices := AServices;
  FDispatcher := TJsonRpcDispatcher.Create;
  FStatistics := TJsonRpcStatistics.Create;
  FDispatcher.Statistics := FStatistics;
  FRecent := TJsonRpcRecentMessages.Create;
  FDispatcher.Recent := FRecent;
  mWatchdog := TJsonRpcWatchdog.Create(FDispatcher.PendingRequests, FServices.TimeoutMs, RequestTimedOut);
  FDispatcher.Watchdog := mWatchdog;
  FDispatcher.OnRequestFailed := RequestFailed;
  FLifecycle := TLspLifecycle.Create(TProductVersion.cName, TProductVersion.cVersion, FServices.Capabilities);
  FLifecycle.Attach(FDispatcher);
  // Ändert der Client ein Dokument, sind laufende Anfragen dazu überholt (#283).
  FDispatcher.PendingRequests.AddContentChangeMethod('textDocument/didChange');
end;

destructor TShellProtocol.Destroy;
begin
  FreeAndNil(FLifecycle);
  FreeAndNil(FDispatcher);
  inherited;
end;

procedure TShellProtocol.RequestTimedOut(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean);
begin
  // Nebenläufige Anfragen beantwortet der Watchdog selbst, die übrigen brechen nur ab.
  if AAnswered then
  begin
    FServices.Logger.Warning(Format('Anfrage %s nach %d ms mit RequestCancelled beantwortet (Zeitlimit)',
      [AMethod, ATimeoutMs]));
  end
  else
  begin
    FServices.Logger.Warning(Format('Anfrage %s hat das Zeitlimit von %d ms überschritten; Abbruch angefordert',
      [AMethod, ATimeoutMs]));
  end;
end;

procedure TShellProtocol.RequestFailed(const AMethod: string; const AParams: TJSONValue; const AError: Exception);
var
  mParams: string;
begin
  mParams := '';
  if AParams <> nil then
  begin
    mParams := AParams.ToJSON;
  end;
  if Length(mParams) > 500 then
  begin
    mParams := Copy(mParams, 1, 500) + '…';
  end;
  FServices.Logger.Error(Format('Anfrage %s fehlgeschlagen: %s: %s%sParameter: %s%s%s',
    [AMethod, AError.ClassName, TLogMarks.Text(AError.Message), sLineBreak,
      TLogMarks.Text(mParams), sLineBreak, TShellPlatform.StackTraceOf(AError)]));
end;

end.
