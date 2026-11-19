unit dpcc.Core.Lsp.SessionLifecycle;

// Zustand von Start und Stopp der Sitzung des Code Insight-Managers, ohne IDE und ohne Threads (testbar). Die
// IDE-Schicht (dpcc.IDE.CodeInsight.Manager.Session) startet den Server in einem Hintergrund-Thread und stoppt ihn
// dort; der Hauptthread fragt nur diesen Zustand, damit er nie auf Start oder Stopp wartet.
//   - Idle: keine Sitzung, kein Start. TryBeginStart wechselt nach Starting und vergibt eine neue Generation.
//   - Starting: ein Start läuft im Hintergrund. FinishStart mit seiner Generation entscheidet: übernehmen (Ready),
//     verwerfen (inzwischen abgebrochen, Hauptschalter aus, Manager abgebaut) oder fehlgeschlagen (Idle mit
//     Sperrzeit cRetryBlockMs: kein Endlos-Neustart, die nächste Anfrage startet frühestens danach).
//   - Ready: die Sitzung läuft. Cancel (Stopp) oder SessionLost (Server von selbst beendet) führen nach Idle.
//   - Stopping: daneben zählt StopBegun/StopEnded die Stopps im Hintergrund (aus jedem Thread).
// Cancel während Starting erhöht die Generation: Ein später fertiger Start bekommt Discard und wird gestoppt.
// Close (Entladen) nimmt keine Starts mehr an. Alles außer StopBegun/StopEnded/Stops nur aus einem Thread
// (Hauptthread der IDE).

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Zustand der Sitzung (ohne die Stopps im Hintergrund, siehe TDpccSessionLifecycle.Stopping).</summary>
  TDpccSessionPhase = (Idle, Starting, Ready);

  /// <summary>Was mit einem fertigen Start geschieht.</summary>
  TDpccStartOutcome = (Adopt, Discard, Failed);

  TDpccSessionLifecycle = class
  public const
    /// <summary>Nach einem fehlgeschlagenen Start so lange kein neuer Versuch.</summary>
    cRetryBlockMs = 30000;
  private
    FPhase: TDpccSessionPhase;
    FGeneration: Cardinal;
    FBlockedUntil: UInt64;
    FStops: Integer;
    FClosed: Boolean;
    FLastError: string;
  public
    /// <summary>Darf jetzt (ANow in ms) ein Start beginnen? Dann Starting und AGeneration = neue Generation.
    /// False, wenn schon einer läuft, eine Sitzung bereit ist, die Sperrzeit läuft oder Close aufgerufen wurde.
    /// </summary>
    function TryBeginStart(ANow: UInt64; out AGeneration: Cardinal): Boolean;
    /// <summary>Läuft die Sperrzeit nach einem Fehlschlag noch?</summary>
    function Blocked(ANow: UInt64): Boolean;
    /// <summary>Restliche Sperrzeit in ms; 0 ohne Sperre.</summary>
    function BlockLeftMs(ANow: UInt64): UInt64;
    /// <summary>Start AGeneration ist fertig. ASucceeded: Server und Sitzung stehen; AAllowed: Manager will die
    /// Sitzung noch (Hauptschalter an, nicht abgebaut). Adopt → Ready; Failed → Idle mit Sperrzeit (AError wird
    /// gemerkt); Discard: veraltete Generation, inzwischen abgebrochen oder nicht mehr erwünscht (Idle, ohne
    /// Sperre). Bei Discard und Failed muss der Aufrufer Server und Sitzung stoppen.</summary>
    function FinishStart(AGeneration: Cardinal; ASucceeded, AAllowed: Boolean; ANow: UInt64;
      const AError: string = ''): TDpccStartOutcome;
    /// <summary>Start abbrechen bzw. Sitzung aufgeben (Stopp): nach Idle. Ergebnis: Zustand davor. Aus Starting
    /// erhöht es die Generation, der laufende Start wird beim Fertigwerden verworfen.</summary>
    function Cancel: TDpccSessionPhase;
    /// <summary>Der Server der bereiten Sitzung endete von selbst: Ready → Idle, ohne Sperre (die Absturzregeln
    /// entscheiden über einen Neustart).</summary>
    procedure SessionLost;
    /// <summary>Sperrzeit aufheben (Start von Hand).</summary>
    procedure ClearBlock;
    /// <summary>Entladen: laufenden Start abbrechen, keine neuen annehmen.</summary>
    procedure Close;
    /// <summary>Ein Stopp im Hintergrund beginnt bzw. ist fertig; aus jedem Thread.</summary>
    procedure StopBegun;
    procedure StopEnded;
    /// <summary>Laufende Stopps im Hintergrund; aus jedem Thread.</summary>
    function Stops: Integer;
    function Stopping: Boolean;
    property Phase: TDpccSessionPhase read FPhase;
    property Generation: Cardinal read FGeneration;
    property Closed: Boolean read FClosed;
    /// <summary>Fehler des letzten fehlgeschlagenen Starts; '' nach einem erfolgreichen.</summary>
    property LastError: string read FLastError;
  end;

implementation

{ TDpccSessionLifecycle }

function TDpccSessionLifecycle.Blocked(ANow: UInt64): Boolean;
begin
  Result := ANow < FBlockedUntil;
end;

function TDpccSessionLifecycle.BlockLeftMs(ANow: UInt64): UInt64;
begin
  Result := 0;
  if ANow < FBlockedUntil then
  begin
    Result := FBlockedUntil - ANow;
  end;
end;

function TDpccSessionLifecycle.TryBeginStart(ANow: UInt64; out AGeneration: Cardinal): Boolean;
begin
  AGeneration := FGeneration;
  Result := not FClosed and (FPhase = TDpccSessionPhase.Idle) and not Blocked(ANow);
  if not Result then
  begin
    Exit;
  end;
  Inc(FGeneration);
  AGeneration := FGeneration;
  FPhase := TDpccSessionPhase.Starting;
end;

function TDpccSessionLifecycle.FinishStart(AGeneration: Cardinal; ASucceeded, AAllowed: Boolean; ANow: UInt64;
  const AError: string): TDpccStartOutcome;
begin
  // Veraltet oder abgebrochen: Der Zustand gehört schon einem anderen Start bzw. dem Stopp.
  if FClosed or (FPhase <> TDpccSessionPhase.Starting) or (AGeneration <> FGeneration) then
  begin
    Exit(TDpccStartOutcome.Discard);
  end;
  if not ASucceeded then
  begin
    FPhase := TDpccSessionPhase.Idle;
    FBlockedUntil := ANow + cRetryBlockMs;
    FLastError := AError;
    Exit(TDpccStartOutcome.Failed);
  end;
  if not AAllowed then
  begin
    FPhase := TDpccSessionPhase.Idle;
    Exit(TDpccStartOutcome.Discard);
  end;
  FPhase := TDpccSessionPhase.Ready;
  FLastError := '';
  Result := TDpccStartOutcome.Adopt;
end;

function TDpccSessionLifecycle.Cancel: TDpccSessionPhase;
begin
  Result := FPhase;
  if FPhase = TDpccSessionPhase.Starting then
  begin
    // Der laufende Start meldet sich mit der alten Generation und wird verworfen.
    Inc(FGeneration);
  end;
  FPhase := TDpccSessionPhase.Idle;
end;

procedure TDpccSessionLifecycle.SessionLost;
begin
  if FPhase = TDpccSessionPhase.Ready then
  begin
    FPhase := TDpccSessionPhase.Idle;
  end;
end;

procedure TDpccSessionLifecycle.ClearBlock;
begin
  FBlockedUntil := 0;
end;

procedure TDpccSessionLifecycle.Close;
begin
  Cancel;
  FClosed := True;
end;

procedure TDpccSessionLifecycle.StopBegun;
begin
  AtomicIncrement(FStops);
end;

procedure TDpccSessionLifecycle.StopEnded;
begin
  if AtomicDecrement(FStops) < 0 then
  begin
    AtomicExchange(FStops, 0);
  end;
end;

function TDpccSessionLifecycle.Stops: Integer;
begin
  Result := AtomicCmpExchange(FStops, 0, 0);
end;

function TDpccSessionLifecycle.Stopping: Boolean;
begin
  Result := Stops > 0;
end;

end.
