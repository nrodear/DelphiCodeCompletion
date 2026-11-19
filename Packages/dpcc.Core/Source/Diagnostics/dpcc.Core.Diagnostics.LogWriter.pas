unit dpcc.Core.Diagnostics.LogWriter;

// Schreib-Thread der Protokolle (perf1). Wer protokolliert, reiht die Zeile samt
// Zeitstempel vom Zeitpunkt des Aufrufs nur ein (Enqueue); ein eigener Thread
// schreibt sie in Reihenfolge und zeitnah (die erste Zeile weckt ihn sofort),
// mehrere gesammelt in einem Schreibvorgang je Ziel. Vorher öffnete jede Zeile
// im aufrufenden Thread – oft dem Hauptthread der IDE – den benannten Mutex des
// Log-Ordners (bis 2 s Wartezeit; D12 und D13 teilen sich den Ordner), prüfte
// Größe und Rotation und hängte an; das Diagnoselog des Managers schrieb mit
// Diagnose = 1 je Aufruf der IDE eine Zeile samt Regex.
// - Ziel (IDpccLogTarget): formatiert und schreibt; Format und Ort der Dateien
//   bestimmt allein das Ziel (TDpccRotatingLog, Diagnoselog des Managers).
// - Begrenzt: Warten mehr als Capacity Zeilen, wird verworfen; die Zahl steht
//   später als eine Zeile „Protokoll: n Zeilen verworfen“ im Ziel der
//   verworfenen Zeilen.
// - Läuft der Thread nicht (vor Start, nach Stop, im Testprogramm ohne Start),
//   liefert Enqueue False und der Aufrufer schreibt wie bisher selbst: keine
//   Zeile geht verloren, nichts stürzt ab.
// - Stop schreibt alles Ausstehende bis zur Zeitgrenze weg (Entladen: zuletzt
//   die Zeile „dpcc entladen in n ms“). Zeilen, die während Stop kommen, nimmt
//   die Warteschlange noch an. Hängt ein Schreibvorgang länger, geht der Thread
//   an TDpccOverdueThreads (hält alle dpcc-Packages, bis er endet) und schreibt
//   seine Warteschlange zu Ende; ein neues Start beginnt mit einer neuen.
// - Flush wartet, bis alles bis dahin Eingereihte geschrieben ist (Tests).
// - Der Thread wartet bewusst nicht auf TDpccShutdown: Gerade während des Abbaus
//   (nach dem Abbruchsignal) soll er weiterschreiben. Er endet nur über Stop;
//   sein Warten auf neue Zeilen ist ein eigenes Ereignis mit Zeitgrenze.
// - Shared: der Schreiber des Plugins; dpcc.IDE.Completion.Register startet ihn
//   beim Anmelden und stoppt ihn als Letztes beim Abbau.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
  /// <summary>Eine Protokollzeile: Zeitpunkt des Aufrufs und Text (ohne Zeitstempel und Zeilenende).</summary>
  TDpccLogLine = record
    Stamp: TDateTime;
    Text: string;
    /// <summary>Zeile mit AText und dem Zeitpunkt jetzt.</summary>
    class function Create(const AText: string): TDpccLogLine; static;
  end;

  /// <summary>Ziel des Schreib-Threads: schreibt ALines in dieser Reihenfolge an einem Stück. Läuft im Schreib-Thread
  /// (bzw. im Aufrufer, wenn er nicht läuft) und darf nicht werfen.</summary>
  IDpccLogTarget = interface
    ['{8E4B2C71-3D5A-4F0E-9B6C-1A7D2E5F8C40}']
    procedure WriteLines(const ALines: TArray<TDpccLogLine>);
  end;

  TDpccLogWriter = class
  public const
    /// <summary>Höchstens so viele Zeilen warten; weitere werden verworfen und später gezählt gemeldet.</summary>
    cDefaultCapacity = 10000;
    /// <summary>Takt, in dem der wartende Thread auch ohne Wecken nachsieht.</summary>
    cIdleWaitMs = 1000;
  private type
    TItem = record
      Target: IDpccLogTarget;
      Line: TDpccLogLine;
    end;
    TDropCount = TPair<IDpccLogTarget, Integer>;

    /// <summary>Warteschlange samt Zustand eines Laufs (Start bis Stop); lebt, solange Schreiber oder Thread sie
    /// halten.</summary>
    TQueueState = class(TInterfacedObject)
    private
      FLock: TCriticalSection;
      FItems: TQueue<TItem>;
      FDropped: TDictionary<IDpccLogTarget, Integer>;
      /// <summary>Auto-Reset: weckt den Thread.</summary>
      FWake: TEvent;
      /// <summary>Gesetzt, solange nichts wartet und nichts geschrieben wird (Flush).</summary>
      FIdle: TEvent;
      FCapacity: Integer;
      FStopping: Boolean;
      /// <summary>Der Thread ist beendet: Add nimmt nichts mehr an.</summary>
      FStopped: Boolean;
      FWriting: Boolean;
    public
      constructor Create(ACapacity: Integer);
      destructor Destroy; override;
      /// <summary>Zeile einreihen oder (voll) als verworfen zählen; False, wenn der Thread beendet ist.</summary>
      function Add(const ATarget: IDpccLogTarget; const ALine: TDpccLogLine): Boolean;
      /// <summary>Im Thread: wartet auf Zeilen und nimmt alle; False, wenn gestoppt und leer.</summary>
      function Take(out AItems: TArray<TItem>; out ADropped: TArray<TDropCount>): Boolean;
      procedure Stop;
      function WaitIdle(AMs: Cardinal): Boolean;
    end;

    TWorker = class(TThread)
    private
      FState: TQueueState;
      FStateRef: IInterface;
    protected
      procedure Execute; override;
    public
      constructor Create(AState: TQueueState);
    end;
  private class var
    FShared: TDpccLogWriter;
  private
    FLock: TCriticalSection;
    FCapacity: Integer;
    FState: TQueueState;
    FStateRef: IInterface;
    FThread: TWorker;
    /// <summary>Zustand des laufenden Threads (ARef hält ihn); nil, wenn keiner läuft.</summary>
    function CurrentState(out ARef: IInterface): TQueueState;
    /// <summary>Im Thread: AItems je Ziel am Stück schreiben, danach die Zahl verworfener Zeilen.</summary>
    class procedure WriteItems(const AItems: TArray<TItem>; const ADropped: TArray<TDropCount>); static;
  public
    /// <summary>Legt Shared an (gestoppt).</summary>
    class constructor CreateShared;
    /// <summary>Stoppt Shared (falls noch nicht geschehen) und gibt ihn frei.</summary>
    class destructor DestroyShared;
    /// <summary>ACapacity: höchstens so viele wartende Zeilen.</summary>
    constructor Create(ACapacity: Integer); overload;
    /// <summary>Wie oben mit ACapacity = DefaultCapacity.</summary>
    constructor Create; overload;
    /// <summary>Stop(1000), dann freigeben.</summary>
    destructor Destroy; override;
    /// <summary>Schreib-Thread starten; läuft er schon, nichts.</summary>
    procedure Start;
    /// <summary>Ausstehendes wegschreiben und den Thread beenden, zusammen höchstens AMs; True, wenn er beendet ist.
    /// Danach liefert Enqueue False (die Aufrufer schreiben selbst).</summary>
    function Stop(AMs: Cardinal): Boolean;
    function Running: Boolean;
    /// <summary>ALine für ATarget einreihen; True = übernommen (oder bei voller Warteschlange gezählt verworfen),
    /// False = kein Thread, der Aufrufer schreibt selbst. Aus jedem Thread, wartet nie auf Dateien.</summary>
    function Enqueue(const ATarget: IDpccLogTarget; const ALine: TDpccLogLine): Boolean;
    /// <summary>Bis AMs warten, bis alles bis jetzt Eingereihte geschrieben ist; True, wenn ja (auch ohne Thread).
    /// </summary>
    function Flush(AMs: Cardinal): Boolean;
    /// <summary>Schreiber des Plugins (gehört dieser Unit).</summary>
    class property Shared: TDpccLogWriter read FShared;
  end;

implementation

uses
  dpcc.Core.Diagnostics.PluginModules,
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Diagnostics.WorkerSlot;

{ TDpccLogLine }

class function TDpccLogLine.Create(const AText: string): TDpccLogLine;
begin
  Result.Stamp := Now;
  Result.Text := AText;
end;

{ TDpccLogWriter.TQueueState }

constructor TDpccLogWriter.TQueueState.Create(ACapacity: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FItems := TQueue<TItem>.Create;
  FDropped := TDictionary<IDpccLogTarget, Integer>.Create;
  FWake := TEvent.Create(nil, False, False, '');
  FIdle := TEvent.Create(nil, True, True, '');
  FCapacity := ACapacity;
end;

destructor TDpccLogWriter.TQueueState.Destroy;
begin
  FIdle.Free;
  FWake.Free;
  FDropped.Free;
  FItems.Free;
  FLock.Free;
  inherited;
end;

function TDpccLogWriter.TQueueState.Add(const ATarget: IDpccLogTarget; const ALine: TDpccLogLine): Boolean;
var
  mItem: TItem;
  mCount: Integer;
  mWake: Boolean;
begin
  FLock.Enter;
  try
    if FStopped then
    begin
      Exit(False);
    end;
    Result := True;
    if FItems.Count >= FCapacity then
    begin
      // Voll: nicht warten, nur zählen; die Zahl schreibt der Thread später als eine Zeile.
      if not FDropped.TryGetValue(ATarget, mCount) then
      begin
        mCount := 0;
      end;
      FDropped.AddOrSetValue(ATarget, mCount + 1);
      Exit;
    end;
    mItem.Target := ATarget;
    mItem.Line := ALine;
    FItems.Enqueue(mItem);
    FIdle.ResetEvent;
    // Schreibt der Thread gerade, holt er die Zeile ohnehin gleich ab; sonst sofort wecken.
    mWake := (FItems.Count = 1) and not FWriting;
  finally
    FLock.Leave;
  end;
  if mWake then
  begin
    FWake.SetEvent;
  end;
end;

function TDpccLogWriter.TQueueState.Take(out AItems: TArray<TItem>; out ADropped: TArray<TDropCount>): Boolean;
begin
  AItems := nil;
  ADropped := nil;
  while True do
  begin
    FLock.Enter;
    try
      if (FItems.Count > 0) or (FDropped.Count > 0) then
      begin
        AItems := FItems.ToArray;
        FItems.Clear;
        ADropped := FDropped.ToArray;
        FDropped.Clear;
        FWriting := True;
        Exit(True);
      end;
      FWriting := False;
      FIdle.SetEvent;
      if FStopping then
      begin
        FStopped := True;
        Exit(False);
      end;
    finally
      FLock.Leave;
    end;
    // Auto-Reset: Ein Wecken zwischen Prüfung und Warten bleibt gesetzt und weckt sofort.
    FWake.WaitFor(TDpccLogWriter.cIdleWaitMs);
  end;
end;

procedure TDpccLogWriter.TQueueState.Stop;
begin
  FLock.Enter;
  try
    FStopping := True;
  finally
    FLock.Leave;
  end;
  FWake.SetEvent;
end;

function TDpccLogWriter.TQueueState.WaitIdle(AMs: Cardinal): Boolean;
begin
  Result := FIdle.WaitFor(AMs) = wrSignaled;
end;

{ TDpccLogWriter.TWorker }

constructor TDpccLogWriter.TWorker.Create(AState: TQueueState);
begin
  FState := AState;
  FStateRef := AState;
  inherited Create(False);
end;

procedure TDpccLogWriter.TWorker.Execute;
var
  mItems: TArray<TItem>;
  mDropped: TArray<TDropCount>;
begin
  NameThreadForDebugging('dpcc.LogWriter');
  while FState.Take(mItems, mDropped) do
  begin
    TDpccLogWriter.WriteItems(mItems, mDropped);
    // Ziele und Texte gleich loslassen, nicht erst beim nächsten Wecken.
    mItems := nil;
    mDropped := nil;
  end;
end;

{ TDpccLogWriter }

class constructor TDpccLogWriter.CreateShared;
begin
  FShared := TDpccLogWriter.Create(cDefaultCapacity);
end;

class destructor TDpccLogWriter.DestroyShared;
begin
  FreeAndNil(FShared);
end;

constructor TDpccLogWriter.Create(ACapacity: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FCapacity := ACapacity;
  if FCapacity < 1 then
  begin
    FCapacity := 1;
  end;
end;

constructor TDpccLogWriter.Create;
begin
  Create(cDefaultCapacity);
end;

destructor TDpccLogWriter.Destroy;
begin
  Stop(TDpccShutdown.cStopMs);
  FLock.Free;
  inherited;
end;

/// <summary>AItems[AFirst..ALast] als Zeilen.</summary>
function LinesOf(const AItems: TArray<TDpccLogWriter.TItem>; AFirst, ALast: Integer): TArray<TDpccLogLine>;
var
  mIndex: Integer;
begin
  SetLength(Result, ALast - AFirst + 1);
  for mIndex := AFirst to ALast do
  begin
    Result[mIndex - AFirst] := AItems[mIndex].Line;
  end;
end;

/// <summary>ALines an ATarget; ein Fehler des Ziels beendet den Schreib-Thread nicht.</summary>
procedure WriteSafe(const ATarget: IDpccLogTarget; const ALines: TArray<TDpccLogLine>);
begin
  try
    ATarget.WriteLines(ALines);
  except
    // Das Ziel zählt seine Schreibfehler selbst (TDpccRotatingLog); hier darf nichts den Thread beenden.
  end;
end;

class procedure TDpccLogWriter.WriteItems(const AItems: TArray<TItem>; const ADropped: TArray<TDropCount>);
var
  mFirst, mIndex: Integer;
  mDrop: TDropCount;
begin
  mFirst := 0;
  for mIndex := 0 to High(AItems) do
  begin
    // Aufeinanderfolgende Zeilen desselben Ziels in einem Schreibvorgang (eine Sperre, ein Anhängen).
    if (mIndex = High(AItems)) or (AItems[mIndex + 1].Target <> AItems[mIndex].Target) then
    begin
      WriteSafe(AItems[mIndex].Target, LinesOf(AItems, mFirst, mIndex));
      mFirst := mIndex + 1;
    end;
  end;
  for mDrop in ADropped do
  begin
    WriteSafe(mDrop.Key, TArray<TDpccLogLine>.Create(TDpccLogLine.Create(
      Format('Protokoll: %d Zeilen verworfen (Warteschlange voll)', [mDrop.Value]))));
  end;
end;

function TDpccLogWriter.CurrentState(out ARef: IInterface): TQueueState;
begin
  FLock.Enter;
  try
    Result := FState;
    ARef := FStateRef;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccLogWriter.Start;
begin
  FLock.Enter;
  try
    if FThread <> nil then
    begin
      Exit;
    end;
    FState := TQueueState.Create(FCapacity);
    FStateRef := FState;
    FThread := TWorker.Create(FState);
  finally
    FLock.Leave;
  end;
end;

function TDpccLogWriter.Stop(AMs: Cardinal): Boolean;
var
  mThread: TWorker;
  mState: TQueueState;
  mStateRef: IInterface;
begin
  FLock.Enter;
  try
    mThread := FThread;
    mState := FState;
    mStateRef := FStateRef;
  finally
    FLock.Leave;
  end;
  if mThread = nil then
  begin
    Exit(True);
  end;
  // Bis der Thread leer ist, nimmt die Warteschlange noch Zeilen an; danach schreibt jeder selbst.
  mState.Stop;
  Result := TDpccShutdown.WaitForThreads(TArray<TThread>.Create(mThread), AMs);
  FLock.Enter;
  try
    FThread := nil;
    FState := nil;
    FStateRef := nil;
  finally
    FLock.Leave;
  end;
  if Result then
  begin
    mThread.Free;
  end
  else
  begin
    // Ein Schreibvorgang hängt (Sperre eines anderen Prozesses, langsames Laufwerk): Der Thread schreibt seine
    // Warteschlange noch zu Ende; bis dahin hält TDpccOverdueThreads die dpcc-Packages im Speicher.
    TDpccOverdueThreads.Adopt(mThread, TDpccPluginModules.All);
  end;
end;

function TDpccLogWriter.Running: Boolean;
begin
  FLock.Enter;
  try
    Result := FThread <> nil;
  finally
    FLock.Leave;
  end;
end;

function TDpccLogWriter.Enqueue(const ATarget: IDpccLogTarget; const ALine: TDpccLogLine): Boolean;
var
  mState: TQueueState;
  mRef: IInterface;
begin
  Result := False;
  if ATarget = nil then
  begin
    Exit;
  end;
  mState := CurrentState(mRef);
  if mState <> nil then
  begin
    Result := mState.Add(ATarget, ALine);
  end;
end;

function TDpccLogWriter.Flush(AMs: Cardinal): Boolean;
var
  mState: TQueueState;
  mRef: IInterface;
begin
  mState := CurrentState(mRef);
  Result := (mState = nil) or mState.WaitIdle(AMs);
end;

end.
