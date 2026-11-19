unit dpcc.Core.Lsp.SessionStart;

// Gemeinsame Objekte von Hauptthread und Start- bzw. Stopp-Threads der Sitzung (dpcc.IDE.CodeInsight.Manager.Session),
// ohne IDE. Alle sind referenzgezählt (Schnittstellen): Ein Thread, der beim Entladen überfällig ist, hält nur diese
// Objekte, nie den Manager; sie leben, bis der letzte Verweis fällt.
//   - TDpccStartJob: was der Hauptthread für einen Start sammelt (Open Tools API nur dort).
//   - IDpccStartTicket: Ergebnis eines Starts mit genau einem Besitzer. Der Start-Thread gibt ab (Deliver); der
//     Hauptthread übernimmt (Take) oder bricht ab (Cancel). Kam der Abbruch vor der Abgabe, gehört das Ergebnis dem
//     Start-Thread, der es selbst stoppt. Nach der Übernahme ist das Ticket die Kennung der Sitzung: Meldungen des
//     Servers (Lese-Thread) tragen es mit, der Hauptthread ordnet sie damit zu; TakeEndReport meldet das Ende des
//     Servers genau einmal, TryMarkProgress hält höchstens einen Fortschrittseintrag in der Warteschlange.
//   - IDpccStopGate: zählt die Stopps im Hintergrund; ein Start wartet, bis keiner mehr läuft.
//   - IDpccIdleSignals: „keine Statusabfrage“, „kein Befehl“, „kein Bedienbefehl“ im Hintergrund; der Stopp wartet
//     darauf, bevor er die Sitzung freigibt.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Projects.Contract;

type
  /// <summary>Was der Hauptthread für einen Start sammelt.</summary>
  TDpccStartJob = record
    Generation: Cardinal;
    /// <summary>Abgeglichene Dokumente der abgestürzten Sitzung, zum erneuten Öffnen (#393).</summary>
    Documents: TArray<TLspOpenDocument>;
    Projects: TArray<string>;
    Contexts: TArray<TDpccProjectContext>;
    Locale: string;
    /// <summary>Hauptschalter beim Anstoßen: War er an und ist inzwischen aus, wird die Sitzung verworfen.</summary>
    MasterOn: Boolean;
    /// <summary>Vom Server selbst beendet (für „Server neu gestartet“, #601).</summary>
    Crashed: Boolean;
    PreviousStart: TDateTime;
    /// <summary>Diagnoseprotokoll an (Start-Thread schreibt ohne den Manager).</summary>
    Diagnose: Boolean;
  end;

  /// <summary>Ergebnis eines Starts mit genau einem Besitzer und Kennung der übernommenen Sitzung. Threadsicher.
  /// </summary>
  IDpccStartTicket = interface
    ['{85736BCA-FE80-4535-BD49-4D863F1F1C38}']
    function Job: TDpccStartJob;
    /// <summary>Start-Thread: Ergebnis abgeben. False: abgebrochen, der Thread stoppt Server und Sitzung selbst.
    /// </summary>
    function Deliver(const AServer: IDpccLspServer; ASession: TLspSession; const AError: string;
      AElapsedMs: Int64): Boolean;
    /// <summary>Hauptthread: Ergebnis übernehmen; False, wenn abgebrochen, noch nicht abgegeben oder schon übernommen.
    /// </summary>
    function Take(out AServer: IDpccLspServer; out ASession: TLspSession; out AError: string;
      out AElapsedMs: Int64): Boolean;
    /// <summary>Hauptthread: abbrechen. True mit einem schon abgegebenen Ergebnis, das der Aufrufer stoppen muss.
    /// </summary>
    function Cancel(out AServer: IDpccLspServer; out ASession: TLspSession): Boolean;
    function Cancelled: Boolean;
    /// <summary>Ende des Servers melden: True nur beim ersten Aufruf.</summary>
    function TakeEndReport: Boolean;
    /// <summary>Fortschritt einreihen? True nur, wenn keiner wartet; ClearProgress, sobald er läuft.</summary>
    function TryMarkProgress: Boolean;
    procedure ClearProgress;
  end;

  TDpccStartTicket = class(TInterfacedObject, IDpccStartTicket)
  private
    FLock: TCriticalSection;
    FJob: TDpccStartJob;
    FServer: IDpccLspServer;
    FSession: TLspSession;
    FError: string;
    FElapsedMs: Int64;
    FDelivered: Boolean;
    FTaken: Boolean;
    FCancelled: Boolean;
    FEndReported: Integer;
    FProgress: Integer;
  public
    constructor Create(const AJob: TDpccStartJob);
    /// <summary>Gibt ein nie abgeholtes Ergebnis frei (sollte nicht vorkommen).</summary>
    destructor Destroy; override;
    function Job: TDpccStartJob;
    function Deliver(const AServer: IDpccLspServer; ASession: TLspSession; const AError: string;
      AElapsedMs: Int64): Boolean;
    function Take(out AServer: IDpccLspServer; out ASession: TLspSession; out AError: string;
      out AElapsedMs: Int64): Boolean;
    function Cancel(out AServer: IDpccLspServer; out ASession: TLspSession): Boolean;
    function Cancelled: Boolean;
    function TakeEndReport: Boolean;
    function TryMarkProgress: Boolean;
    procedure ClearProgress;
  end;

  /// <summary>Zählt die Stopps im Hintergrund. Threadsicher.</summary>
  IDpccStopGate = interface
    ['{6F5EBFCF-FE0B-4369-A77E-63641F29352C}']
    procedure Enter;
    procedure Leave;
    /// <summary>Bis zu AMs warten, bis kein Stopp mehr läuft; vorzeitig beim Abbruchsignal (TDpccShutdown).
    /// True, wenn keiner mehr läuft.</summary>
    function WaitIdle(AMs: Cardinal): Boolean;
    function Count: Integer;
  end;

  TDpccStopGate = class(TInterfacedObject, IDpccStopGate)
  private
    FCount: Integer;
    FIdle: TEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Enter;
    procedure Leave;
    function WaitIdle(AMs: Cardinal): Boolean;
    function Count: Integer;
  end;

  /// <summary>Statusabfrage, Befehl und Bedienbefehle im Hintergrund (#591, #66, #874). Threadsicher.</summary>
  IDpccIdleSignals = interface
    ['{B0A0CD0B-92F7-4C28-B41D-0A599FECBBDB}']
    /// <summary>Statusabfrage beginnen; False, wenn schon eine läuft.</summary>
    function TryBeginQuery: Boolean;
    procedure EndQuery;
    /// <summary>Befehl im Hintergrund beginnen; False, wenn schon einer läuft.</summary>
    function TryBeginCommand: Boolean;
    procedure EndCommand;
    /// <summary>Bedienbefehle: beliebig viele gleichzeitig.</summary>
    procedure BeginServerCommand;
    procedure EndServerCommand;
    function QueryRunning: Boolean;
    function CommandRunning: Boolean;
    function ServerCommands: Integer;
    /// <summary>Auf das Ende der Statusabfrage, des Befehls bzw. der Bedienbefehle warten (je bis AMs); True, wenn
    /// sie fertig sind.</summary>
    function WaitQuery(AMs: Cardinal): Boolean;
    function WaitCommand(AMs: Cardinal): Boolean;
    function WaitServerCommands(AMs: Cardinal): Boolean;
  end;

  TDpccIdleSignals = class(TInterfacedObject, IDpccIdleSignals)
  private
    FQuery: Integer;
    FCommand: Integer;
    FServerCommands: Integer;
    FQueryIdle: TEvent;
    FCommandIdle: TEvent;
    FServerCommandsIdle: TEvent;
  public
    constructor Create;
    destructor Destroy; override;
    function TryBeginQuery: Boolean;
    procedure EndQuery;
    function TryBeginCommand: Boolean;
    procedure EndCommand;
    procedure BeginServerCommand;
    procedure EndServerCommand;
    function QueryRunning: Boolean;
    function CommandRunning: Boolean;
    function ServerCommands: Integer;
    function WaitQuery(AMs: Cardinal): Boolean;
    function WaitCommand(AMs: Cardinal): Boolean;
    function WaitServerCommands(AMs: Cardinal): Boolean;
  end;

implementation

uses
  dpcc.Core.Diagnostics.Shutdown;

{ TDpccStartTicket }

constructor TDpccStartTicket.Create(const AJob: TDpccStartJob);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FJob := AJob;
end;

destructor TDpccStartTicket.Destroy;
begin
  FreeAndNil(FSession);
  FServer := nil;
  FLock.Free;
  inherited;
end;

function TDpccStartTicket.Job: TDpccStartJob;
begin
  Result := FJob;
end;

function TDpccStartTicket.Deliver(const AServer: IDpccLspServer; ASession: TLspSession; const AError: string;
  AElapsedMs: Int64): Boolean;
begin
  FLock.Enter;
  try
    Result := not FCancelled and not FDelivered;
    if Result then
    begin
      FServer := AServer;
      FSession := ASession;
      FError := AError;
      FElapsedMs := AElapsedMs;
      FDelivered := True;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDpccStartTicket.Take(out AServer: IDpccLspServer; out ASession: TLspSession; out AError: string;
  out AElapsedMs: Int64): Boolean;
begin
  AServer := nil;
  ASession := nil;
  AError := '';
  AElapsedMs := 0;
  FLock.Enter;
  try
    Result := FDelivered and not FTaken and not FCancelled;
    if Result then
    begin
      FTaken := True;
      AServer := FServer;
      ASession := FSession;
      AError := FError;
      AElapsedMs := FElapsedMs;
      FServer := nil;
      FSession := nil;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDpccStartTicket.Cancel(out AServer: IDpccLspServer; out ASession: TLspSession): Boolean;
begin
  AServer := nil;
  ASession := nil;
  FLock.Enter;
  try
    FCancelled := True;
    Result := FDelivered and not FTaken;
    if Result then
    begin
      FTaken := True;
      AServer := FServer;
      ASession := FSession;
      FServer := nil;
      FSession := nil;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDpccStartTicket.Cancelled: Boolean;
begin
  FLock.Enter;
  try
    Result := FCancelled;
  finally
    FLock.Leave;
  end;
end;

function TDpccStartTicket.TakeEndReport: Boolean;
begin
  Result := AtomicExchange(FEndReported, 1) = 0;
end;

function TDpccStartTicket.TryMarkProgress: Boolean;
begin
  Result := AtomicCmpExchange(FProgress, 1, 0) = 0;
end;

procedure TDpccStartTicket.ClearProgress;
begin
  AtomicExchange(FProgress, 0);
end;

{ TDpccStopGate }

constructor TDpccStopGate.Create;
begin
  inherited Create;
  FIdle := TEvent.Create(nil, True, True, '');
end;

destructor TDpccStopGate.Destroy;
begin
  FIdle.Free;
  inherited;
end;

procedure TDpccStopGate.Enter;
begin
  if AtomicIncrement(FCount) = 1 then
  begin
    FIdle.ResetEvent;
  end;
end;

procedure TDpccStopGate.Leave;
var
  mCount: Integer;
begin
  mCount := AtomicDecrement(FCount);
  if mCount <= 0 then
  begin
    if mCount < 0 then
    begin
      AtomicExchange(FCount, 0);
    end;
    FIdle.SetEvent;
  end;
end;

function TDpccStopGate.WaitIdle(AMs: Cardinal): Boolean;
begin
  Result := TDpccShutdown.WaitFor(FIdle, AMs) = wrSignaled;
end;

function TDpccStopGate.Count: Integer;
begin
  Result := AtomicCmpExchange(FCount, 0, 0);
end;

{ TDpccIdleSignals }

constructor TDpccIdleSignals.Create;
begin
  inherited Create;
  FQueryIdle := TEvent.Create(nil, True, True, '');
  FCommandIdle := TEvent.Create(nil, True, True, '');
  FServerCommandsIdle := TEvent.Create(nil, True, True, '');
end;

destructor TDpccIdleSignals.Destroy;
begin
  FQueryIdle.Free;
  FCommandIdle.Free;
  FServerCommandsIdle.Free;
  inherited;
end;

function TDpccIdleSignals.TryBeginQuery: Boolean;
begin
  Result := AtomicCmpExchange(FQuery, 1, 0) = 0;
  if Result then
  begin
    FQueryIdle.ResetEvent;
  end;
end;

procedure TDpccIdleSignals.EndQuery;
begin
  AtomicExchange(FQuery, 0);
  FQueryIdle.SetEvent;
end;

function TDpccIdleSignals.TryBeginCommand: Boolean;
begin
  Result := AtomicCmpExchange(FCommand, 1, 0) = 0;
  if Result then
  begin
    FCommandIdle.ResetEvent;
  end;
end;

procedure TDpccIdleSignals.EndCommand;
begin
  AtomicExchange(FCommand, 0);
  FCommandIdle.SetEvent;
end;

procedure TDpccIdleSignals.BeginServerCommand;
begin
  if AtomicIncrement(FServerCommands) = 1 then
  begin
    FServerCommandsIdle.ResetEvent;
  end;
end;

procedure TDpccIdleSignals.EndServerCommand;
var
  mCount: Integer;
begin
  mCount := AtomicDecrement(FServerCommands);
  if mCount <= 0 then
  begin
    if mCount < 0 then
    begin
      AtomicExchange(FServerCommands, 0);
    end;
    FServerCommandsIdle.SetEvent;
  end;
end;

function TDpccIdleSignals.QueryRunning: Boolean;
begin
  Result := AtomicCmpExchange(FQuery, 0, 0) <> 0;
end;

function TDpccIdleSignals.CommandRunning: Boolean;
begin
  Result := AtomicCmpExchange(FCommand, 0, 0) <> 0;
end;

function TDpccIdleSignals.ServerCommands: Integer;
begin
  Result := AtomicCmpExchange(FServerCommands, 0, 0);
end;

function TDpccIdleSignals.WaitQuery(AMs: Cardinal): Boolean;
begin
  Result := FQueryIdle.WaitFor(AMs) = wrSignaled;
end;

function TDpccIdleSignals.WaitCommand(AMs: Cardinal): Boolean;
begin
  Result := FCommandIdle.WaitFor(AMs) = wrSignaled;
end;

function TDpccIdleSignals.WaitServerCommands(AMs: Cardinal): Boolean;
begin
  Result := FServerCommandsIdle.WaitFor(AMs) = wrSignaled;
end;

end.
