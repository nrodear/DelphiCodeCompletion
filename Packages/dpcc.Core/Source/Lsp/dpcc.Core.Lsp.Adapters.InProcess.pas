unit dpcc.Core.Lsp.Adapters.InProcess;

// Completion-Server im IDE-Prozess (Schritt 2b, docs\Konzept-Completion-Schnitt.md Abschnitt 4.5), seit S1 der
// einzige Betrieb: Einen eigenen Server-Prozess gibt es nicht mehr. Schnittstelle IDpccLspServer: Der Server
// (Shell.Composition.InProcess, Package dpcc.Server) läuft auf einem eigenen Thread, die Verbindung sind zwei
// Speicher-Pipes mit LSP über JSON-RPC; Manager-Kette, Completion und Hover sprechen nur mit TLspClient.
// - Schreiben legt die gerahmte Nachricht nur in die Pipe zum Server und kehrt sofort zurück; der Hauptthread
//   der IDE wartet nie auf den Server.
// - Ein Lese-Thread reicht die Ausgabe des Servers an TLspClient.Receive weiter. Endet der Server von selbst
//   (exit, Abbruch), schließt er seine Ausgabe; der Client wird dann mit Exit-Code und Laufzeit geschlossen.
// - Destroy: Client schließen, shutdown und exit über das Protokoll, Eingabe schließen, auf Schleife und Abbau der
//   Wurzel warten (Wächter, Verbindung, Worker-Pool, Index-Threads, Dateibeobachter), Lese-Thread beenden. Beim
//   Entladen bzw. Schließen der IDE (TDpccShutdown, #493) mit kürzerer Wartezeit. Einen hängenden Server kann
//   dpcc im eigenen Prozess nicht beenden; er läuft dann allein zu Ende (Protokollzeile). Damit er nicht in
//   entladenen Code springt, hält Shell.Composition.InProcess dann den Code von dpcc.Server und seinen
//   Abhängigkeiten bis zum Ende der IDE geladen und hängt die Protokollsenke des Plugins ab (KeepCodeLoaded).

interface

uses
  System.SysUtils,
  System.Classes,
  dpcc.Core.Lsp.Client,
  Shell.Composition.InProcess;

type
  TLspInProcessServer = class(TInterfacedObject, IDpccLspServer)
  public const
    /// <summary>So lange wartet Destroy auf das Ende des Servers; beim Entladen der IDE cShutdownStopMs.</summary>
    cStopMs = TShellInProcessServer.cStopTimeoutMs;
    /// <summary>Über den Wartezeiten des Servers für abgebrochene Anfragen (5 s Schleife, 2 s Pool): Im Normalfall
    /// ist er vor dem Entladen fertig.</summary>
    cShutdownStopMs = 10000;
  private
    FServer: TShellInProcessServer;
    FClient: TLspClient;
    FReader: TThread;
    // Schützt FWritable: Der Lese-Thread antwortet über Write noch, während Destroy abbaut.
    FLock: TObject;
    FWritable: Boolean;
    FStarted: UInt64;
    procedure Write(const ABytes: TBytes);
    /// <summary>shutdown und exit an den Server, an TLspClient vorbei (der ist schon geschlossen).</summary>
    procedure SendShutdown;
    /// <summary>Exit-Code und Laufzeit für TLspClient.CloseWith; leer, wenn dpcc den Server selbst beendet.</summary>
    function EndInfo: TLspCloseInfo;
  public
    /// <summary>Verdrahtet den Server im eigenen Prozess und startet ihn; Fehler der Wurzel lösen eine Exception
    /// aus.</summary>
    constructor Create;
    destructor Destroy; override;
    function Running: Boolean;
    function GetClient: TLspClient;
    property Client: TLspClient read FClient;
    /// <summary>Der Server dahinter (für Tests).</summary>
    property Server: TShellInProcessServer read FServer;
  end;

implementation

uses
  dpcc.Common.Logging.Contract,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Shutdown;

type
  /// <summary>Warnungen und Fehler des Servers ins Protokoll des Plugins (dpcc.log).</summary>
  TGuardLogSink = class(TInterfacedObject, ILogSink)
  public
    procedure Write(const AEntry: TLogEntry);
  end;

  TReaderThread = class(TThread)
  private
    FInput: TStream;
    FClient: TLspClient;
    FOwner: TLspInProcessServer;
  protected
    procedure Execute; override;
  public
    constructor Create(AInput: TStream; AClient: TLspClient; AOwner: TLspInProcessServer);
  end;

{ TGuardLogSink }

procedure TGuardLogSink.Write(const AEntry: TLogEntry);
begin
  // Der Text trägt die Kennzeichen (TLogMarks) des Servers; dpcc.log anonymisiert sie wie eigene Zeilen.
  TDpccGuard.Log('Server (in-process): ' + AEntry.Text);
end;

{ TReaderThread }

constructor TReaderThread.Create(AInput: TStream; AClient: TLspClient; AOwner: TLspInProcessServer);
begin
  FInput := AInput;
  FClient := AClient;
  FOwner := AOwner;
  inherited Create(False);
end;

procedure TReaderThread.Execute;
var
  mBuffer: TBytes;
  mRead: Integer;
begin
  NameThreadForDebugging('dpcc.LspReader (in-process)');
  SetLength(mBuffer, 65536);
  try
    try
      while not Terminated do
      begin
        // 0 erst, wenn der Server seine Ausgabe geschlossen hat (Ende oder Stop).
        mRead := FInput.Read(mBuffer[0], Length(mBuffer));
        if mRead <= 0 then
        begin
          Break;
        end;
        FClient.Receive(mBuffer, mRead);
      end;
    except
      // Kein stilles Ende (#493): protokollieren; die Sitzung gilt dann als beendet.
      on E: Exception do
        TDpccGuard.Report(TDpccFeature.Server, E);
    end;
  finally
    FClient.CloseWith(FOwner.EndInfo);
  end;
end;

{ TLspInProcessServer }

constructor TLspInProcessServer.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FServer := TShellInProcessServer.Create(TGuardLogSink.Create);
  FStarted := TThread.GetTickCount64;
  FWritable := True;
  FClient := TLspClient.Create(Write);
  FReader := TReaderThread.Create(FServer.ClientInput, FClient, Self);
end;

destructor TLspInProcessServer.Destroy;
var
  mTimeout: Cardinal;
begin
  if FClient <> nil then
  begin
    FClient.Close;
  end;
  if FServer <> nil then
  begin
    SendShutdown;
    mTimeout := cStopMs;
    if TDpccShutdown.Signalled then
    begin
      mTimeout := cShutdownStopMs;
    end;
    if not FServer.Stop(mTimeout) then
    begin
      if FServer.Abandoned then
      begin
        TDpccGuard.Log(Format('In-Process-Server endete nicht binnen %d ms; er läuft allein zu Ende', [mTimeout]));
      end
      else
      begin
        TDpccGuard.Log('In-Process-Server: Anfragen liefen beim Beenden weiter; ihre Objekte bleiben stehen');
      end;
      if TShellInProcessServer.CodeKeptLoaded then
      begin
        TDpccGuard.Log('In-Process-Server: Code von dpcc.Server bleibt bis zum Ende der IDE geladen');
      end;
    end;
  end;
  // Stop hat die Ausgabe geschlossen: Der Lese-Thread endet.
  if FReader <> nil then
  begin
    FReader.WaitFor;
    FReader.Free;
  end;
  System.TMonitor.Enter(FLock);
  try
    FWritable := False;
  finally
    System.TMonitor.Exit(FLock);
  end;
  FServer.Free;
  FClient.Free;
  FLock.Free;
  inherited;
end;

procedure TLspInProcessServer.SendShutdown;
const
  // Eigene Kennung außerhalb der Nummern des Clients; die Antwort geht an den geschlossenen Client.
  cShutdown = '{"jsonrpc":"2.0","id":2147483647,"method":"shutdown"}';
  cExit = '{"jsonrpc":"2.0","method":"exit"}';
var
  mBytes: TBytes;
begin
  // shutdown, exit, dann Ende der Eingabe (Stop). Der Server beendet die Schleife nach exit mit
  // Exit-Code 0; ohne exit endet sie am Ende der Eingabe.
  mBytes := TLspClient.Frame(cShutdown) + TLspClient.Frame(cExit);
  Write(mBytes);
end;

procedure TLspInProcessServer.Write(const ABytes: TBytes);
begin
  if Length(ABytes) = 0 then
  begin
    Exit;
  end;
  System.TMonitor.Enter(FLock);
  try
    // False: Destroy baut gerade ab (Antwort des Lese-Threads beim Beenden).
    if FWritable then
    begin
      // Blockiert nie: Die Pipe puffert im Speicher.
      FServer.ClientOutput.WriteBuffer(ABytes[0], Length(ABytes));
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TLspInProcessServer.EndInfo: TLspCloseInfo;
begin
  Result := Default(TLspCloseInfo);
  // dpcc beendet den Server selbst (Destroy schließt den Client vorher): kein Absturz.
  if (FClient = nil) or FClient.Closed then
  begin
    Exit;
  end;
  Result.RuntimeMs := Int64(TThread.GetTickCount64 - FStarted);
  if FServer.WaitFor(0) then
  begin
    Result.ExitKnown := True;
    Result.ExitCode := Cardinal(FServer.ExitCode);
  end;
end;

function TLspInProcessServer.GetClient: TLspClient;
begin
  Result := FClient;
end;

function TLspInProcessServer.Running: Boolean;
begin
  Result := (FServer <> nil) and FServer.Running and not FClient.Closed;
end;

end.
