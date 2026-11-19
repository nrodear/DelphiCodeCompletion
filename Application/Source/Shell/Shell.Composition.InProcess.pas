unit Shell.Composition.InProcess;

// Host-Rolle Shell: Completion-Server im Prozess des Aufrufers (Schritt 2b, Konzept Abschnitt 4.5), im IDE-Prozess;
// seit S1 der einzige Betrieb (kein eigener Server-Prozess mehr). Die Verbindung sind zwei Speicher-Pipes
// (TShellMemoryPipe); das Protokoll ist LSP über JSON-RPC. Die Wurzel (Shell.Composition.CompletionServer) läuft auf einem
// eigenen Thread und wird dort nach dem Ende ihrer Schleife auch freigegeben.
//
// Härtung für den IDE-Prozess (Liste in docs\Konzept-Completion-Schnitt.md, Schritt 2b):
// - kein Wächter des Editor-Prozesses: Der Editor ist der eigene Prozess;
// - keine Stacktraces über TStackTrace.Install (Exception.GetExceptionStackInfoProc der RTL gilt für die ganze IDE),
//   kein SetUnhandledExceptionFilter, kein Halt/ExitProcess, keine Konsolen-Streams;
// - die Haken von TShellPlatform.InstallGuards wirken nur auf dpcc.Common (TStackGuard.Restore,
//   TFileEncoding.Reader) und bleiben deshalb an; Stop nimmt sie mit dem letzten Server zurück;
// - prozessweite Schalter von dpcc.Common setzt der erste Server und stellt der letzte zurück: Cache der
//   published-Mitglieder (TPublishedMembers.UseCache) und Sprache der Servertexte (TDpccLocale);
// - prozessweite Merker gibt der letzte Server frei (Speicher-Optimierung Phase 2): den Namensindex der
//   Import-Vorschläge (TImportNames, hielt sonst den ganzen Index des beendeten Servers), die bekannten Stände der
//   gemeinsamen Caches (TIndexService.ForgetSharedStates) und die Ordnerlisten (TSharedUnitListings);
// - globale Anbieter (TSyntaxTreeCache, TPascalPreprocessor) nimmt ein Server beim Abbau nur zurück, wenn noch
//   seine eigenen gesetzt sind; ein neuerer Server im selben Prozess behält sie;
// - Freigabe in fester Reihenfolge: Eingabe schließen (Ende der Eingabe), Schleife und Wurzel beenden
//   (Wächter, Verbindung, Worker-Pool, Index-Threads, Features), erst dann die Ausgabe schließen.
//
// Beenden (Rückbau R4): Die Schleife bricht beim Ende der Eingabe alle Anfragen ab (Abbruch-Token je Anfrage,
// Index-Threads über ihr Abbruchsignal) und wartet auf sie; die Wurzel wartet im IDE-Prozess bis cUnfinishedWaitMs
// weiter, statt Index und Features stehen zu lassen. Erst dann meldet der Thread "fertig". Stop wartet höchstens
// ATimeoutMs:
// - fertig: Thread abwarten (bis sein Code wirklich verlassen ist), freigeben, Release;
// - nicht fertig (Abandoned): Der Thread gibt sich am Ende selbst frei und ruft Release selbst. Damit er nie in
//   entladenen Code springt, hält Stop den Code des Packages dpcc.Server samt seinen Abhängigkeiten (dpcc.Common,
//   dpcc.Text, dpcc.Windows, dpcc.WinBase) bis zum Prozessende geladen und initialisiert (KeepCodeLoaded:
//   GetModuleHandleEx mit PIN und ein eigenes LoadPackage ohne UnloadPackage, sodass die Units beim Entladen des
//   Plugins nicht finalisiert werden). Die Senke des Gastgebers (Code des Plugins) hängt Stop vorher ab;
// - ließ die Wurzel Objekte stehen, weil Anfragen auch nach cUnfinishedWaitMs liefen (LeftWork), gilt dasselbe;
//   Release unterbleibt dann, weil diese Anfragen die prozessweiten Schalter noch nutzen. Ein eigener Thread der
//   Wurzel gibt Index und Features frei, sobald diese Anfragen enden, und ruft erst dann Release (a4,
//   Speicher-Optimierung Phase 2); vorher blieb der ganze alte Server bis zum Ende der IDE im Speicher.
// Im Testprogramm (statisch gelinkt) entlädt niemand Code; KeepCodeLoaded tut dort nichts.
// exit schließt die Eingabe sofort (Lifecycle.OnExit): Sonst hinge der Lese-Thread der Verbindung im Lesen der offenen
// Pipe, Run gäbe ihn nach 2 s auf, und er endete erst nach Stop, ohne dass jemand auf ihn wartete (hielt bis dahin
// Transport und Pipes; Leckmeldung von rund 67 KB in ExitClosesClient).
//
// Puffer: Beide Pipes sind begrenzt (cPipeCapacity). Zum Server (Schreiber: Plugin, auch der Hauptthread der IDE)
// wartet Schreiben nie: Ist der Puffer voll, liest der Server nicht mehr; die Pipe wird geschlossen (Overflowed), der
// Server sieht das Ende der Eingabe und beendet sich. Vom Server (Schreiber: Server-Threads) wartet Schreiben bis
// cServerWriteWaitMs auf Platz (Gegendruck) und schließt die Pipe erst dann; der Client sieht das Ende.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  dpcc.Common.Logging.Contract,
  dpcc.Common.Localization.Texts,
  Shell.Composition.CompletionServer;

type
  /// <summary>Gepufferte Einbahn-Verbindung im Speicher mit Obergrenze: Lesen wartet auf Daten oder das Ende.
  /// Threadsicher.</summary>
  IShellMemoryPipe = interface
    ['{4C0E3B1F-6D2A-4A57-9E0B-2F7D8C3A1B64}']
    /// <summary>Hängt ACount Bytes an; nach Close ohne Wirkung (wie eine Pipe ohne Leser, nur ohne Fehler). Passt
    /// es nicht mehr unter die Obergrenze, wartet Write bis zur Wartezeit der Pipe auf Platz (0 = gar nicht) und
    /// schließt die Pipe dann (Overflowed). Ein einzelnes Stück über der Grenze passt in einen leeren Puffer.</summary>
    procedure Write(const ABuffer; ACount: Integer);
    /// <summary>Liest bis zu ACount Bytes; wartet, bis Daten da sind. 0 = Ende (geschlossen und leer).</summary>
    function Read(var ABuffer; ACount: Integer): Integer;
    /// <summary>Ende: wartende Leser kehren mit dem Rest bzw. 0 zurück, wartende Schreiber ohne Wirkung.</summary>
    procedure Close;
    function Closed: Boolean;
    /// <summary>Geschlossen, weil der Puffer voll war und niemand las.</summary>
    function Overflowed: Boolean;
    /// <summary>Ungelesene Bytes.</summary>
    function Buffered: Int64;
  end;

  TShellMemoryPipe = class(TInterfacedObject, IShellMemoryPipe)
  public const
    cDefaultCapacity = 64 * 1024 * 1024;
  private
    FLock: TObject;
    FChunks: TQueue<TBytes>;
    /// <summary>Schon gelesener Anfang des ersten Stücks.</summary>
    FOffset: Integer;
    FSize: Int64;
    FCapacity: Int64;
    FWriteWaitMs: Cardinal;
    FClosed: Boolean;
    FOverflowed: Boolean;
  public
    /// <summary>ACapacity: Obergrenze ungelesener Bytes; AWriteWaitMs: so lange wartet Write auf Platz.</summary>
    constructor Create(ACapacity: Int64 = cDefaultCapacity; AWriteWaitMs: Cardinal = 0);
    destructor Destroy; override;
    procedure Write(const ABuffer; ACount: Integer);
    function Read(var ABuffer; ACount: Integer): Integer;
    procedure Close;
    function Closed: Boolean;
    function Overflowed: Boolean;
    function Buffered: Int64;
    /// <summary>Stream, der aus APipe liest (Schreiben löst EStreamError aus).</summary>
    class function ReadStream(const APipe: IShellMemoryPipe): TStream; static;
    /// <summary>Stream, der in APipe schreibt (Lesen liefert 0).</summary>
    class function WriteStream(const APipe: IShellMemoryPipe): TStream; static;
  end;

  /// <summary>Für Tests: Eingriff in die Wurzel vor dem Start ihres Threads (etwa eigene Methoden am Verteiler oder
  /// kürzere Wartezeiten). Eine Exception bricht Create ab.</summary>
  TShellInProcessConfigure = reference to procedure(AServer: TShellCompletionServer);

  /// <summary>Zustand eines Laufs, den Server-Thread und TShellInProcessServer teilen (Referenzzählung): Stop greift
  /// nie auf einen Thread zu, der sich selbst freigibt.</summary>
  IShellInProcessRun = interface
    ['{8E5D0B7A-3C21-4F6E-9A4D-61B2C7E0F395}']
    /// <summary>Thread: Schleife und Abbau fertig. True, wenn Stop vorher aufgab (Abandoned).</summary>
    function Finish(AExitCode: Integer): Boolean;
    /// <summary>Stop: aufgeben, falls noch nicht fertig. True = aufgegeben.</summary>
    function Abandon: Boolean;
    function WaitDone(ATimeoutMs: Cardinal): Boolean;
    function Done: Boolean;
    function ExitCode: Integer;
    /// <summary>Die Wurzel ließ Objekte stehen, weil Anfragen noch liefen.</summary>
    procedure SetLeftWork;
    function LeftWork: Boolean;
  end;

  /// <summary>Completion-Server auf eigenem Thread im Prozess des Aufrufers. ClientOutput nimmt die Nachrichten des
  /// Clients auf, ClientInput liefert die des Servers (beide gehören dem Objekt).</summary>
  TShellInProcessServer = class
  public const
    /// <summary>So lange wartet Stop auf das Ende der Schleife und das Freigeben der Wurzel. Darin: bis 5 s auf
    /// laufende Anfragen und 2 s auf den Worker-Pool (Schleife), bis cUnfinishedWaitMs weiter (Wurzel) und die
    /// Index-Threads.</summary>
    cStopTimeoutMs = 20000;
    /// <summary>So lange wartet die Wurzel beim Abbau weiter auf Anfragen, die ihr Abbruchsignal nicht rechtzeitig
    /// prüften, bevor sie Index und Features freigibt.</summary>
    cUnfinishedWaitMs = 8000;
    /// <summary>Obergrenze ungelesener Bytes je Richtung.</summary>
    cPipeCapacity = TShellMemoryPipe.cDefaultCapacity;
    /// <summary>So lange wartet ein Server-Thread auf Platz in der Ausgabe, bevor er sie schließt.</summary>
    cServerWriteWaitMs = 10000;
  private
    FToServer: IShellMemoryPipe;
    FFromServer: IShellMemoryPipe;
    FClientInput: TStream;
    FClientOutput: TStream;
    FThread: TThread;
    FRun: IShellInProcessRun;
    /// <summary>Senke des Gastgebers (THostSink); Stop hängt sie ab, wenn der Thread weiterläuft.</summary>
    FHostSink: TObject;
    FHostSinkRef: ILogSink;
    FStopped: Boolean;
    FStopResult: Boolean;
    FAbandoned: Boolean;
    FLeftWork: Boolean;
    procedure DetachHostSink;
    class procedure Acquire; static;
    class procedure Release; static;
    /// <summary>Hält den Code von dpcc.Server und seinen Abhängigkeiten bis Prozessende geladen und initialisiert;
    /// ohne Wirkung, wenn statisch gelinkt.</summary>
    class procedure KeepCodeLoaded; static;
  public
    /// <summary>Verdrahtet die Wurzel und startet ihre Schleife. AHostSink (optional) bekommt Warnungen und Fehler
    /// des Servers, etwa für das Protokoll des Plugins.</summary>
    constructor Create(const AHostSink: ILogSink); overload;
    /// <summary>Wie oben; AConfigure (Tests) greift vor dem Start in die Wurzel ein.</summary>
    constructor Create(const AHostSink: ILogSink; const AConfigure: TShellInProcessConfigure); overload;
    /// <summary>Ruft Stop.</summary>
    destructor Destroy; override;
    /// <summary>Beendet den Server: Eingabe schließen, bis ATimeoutMs auf Schleife und Freigabe warten, Ausgabe
    /// schließen. False, wenn der Thread nicht rechtzeitig endete (Abandoned) oder die Wurzel Objekte stehen ließ
    /// (LeftWork); der Code des Servers bleibt dann geladen. Mehrfacher Aufruf liefert das erste Ergebnis.</summary>
    function Stop(ATimeoutMs: Cardinal = cStopTimeoutMs): Boolean;
    /// <summary>Schleife des Servers läuft noch (weder exit noch Ende der Eingabe).</summary>
    function Running: Boolean;
    /// <summary>Wartet bis ATimeoutMs auf das Ende von Schleife und Abbau.</summary>
    function WaitFor(ATimeoutMs: Cardinal): Boolean;
    /// <summary>Exit-Code der Schleife (0 nach shutdown/exit); gültig nach dem Ende, vorher 1.</summary>
    function ExitCode: Integer;
    /// <summary>Die Pipe zum Server lief über (der Server las nicht mehr).</summary>
    function InputOverflowed: Boolean;
    /// <summary>Lies hier die Nachrichten des Servers (0 = Ende).</summary>
    property ClientInput: TStream read FClientInput;
    /// <summary>Schreib hier die Nachrichten an den Server; wartet nie.</summary>
    property ClientOutput: TStream read FClientOutput;
    /// <summary>Stop wartete vergeblich; der Thread gibt sich und die Wurzel selbst frei.</summary>
    property Abandoned: Boolean read FAbandoned;
    /// <summary>Die Wurzel ließ Index und Features beim Stopp stehen (Anfragen liefen weiter); sie gibt sie frei und
    /// meldet den Server ab, sobald diese Anfragen enden (a4).</summary>
    property LeftWork: Boolean read FLeftWork;
    /// <summary>Laufende In-Process-Server im Prozess (für Tests).</summary>
    class function ActiveCount: Integer; static;
    /// <summary>KeepCodeLoaded hat den Code festgehalten (für das Protokoll des Plugins).</summary>
    class function CodeKeptLoaded: Boolean; static;
  end;

implementation

uses
  System.SyncObjs,
  System.RTLConsts,
  {$IFDEF MSWINDOWS}
  Winapi.Windows,
  {$ENDIF}
  dpcc.Common.Logging.Providers.Logger,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.JsonRpc.StreamTransport,
  dpcc.Common.Lsp.Adapters.LogMessageSink,
  dpcc.Common.Lsp.PublishedMembers,
  dpcc.Common.Diagnostics.Anonymizer,
  dpcc.Common.Index.NameIndex,
  dpcc.Common.Index.Service,
  Shell.Workspace.Listings,
  Shell.Platform;

type
  TPipeReadStream = class(TStream)
  private
    FPipe: IShellMemoryPipe;
  public
    constructor Create(const APipe: IShellMemoryPipe);
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

  TPipeWriteStream = class(TStream)
  private
    FPipe: IShellMemoryPipe;
  public
    constructor Create(const APipe: IShellMemoryPipe);
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

  TShellInProcessRun = class(TInterfacedObject, IShellInProcessRun)
  private
    FLock: TObject;
    FDone: TEvent;
    FExitCode: Integer;
    FFinished: Boolean;
    FAbandoned: Boolean;
    FLeftWork: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Finish(AExitCode: Integer): Boolean;
    function Abandon: Boolean;
    function WaitDone(ATimeoutMs: Cardinal): Boolean;
    function Done: Boolean;
    function ExitCode: Integer;
    procedure SetLeftWork;
    function LeftWork: Boolean;
  end;

  TServerThread = class(TThread)
  private
    FServer: TShellCompletionServer;
    FHostSink: ILogSink;
    /// <summary>Ausgabe zum Client; nach dem Abbau geschlossen, damit der Client das Ende sieht.</summary>
    FOutput: IShellMemoryPipe;
    FRun: IShellInProcessRun;
  protected
    procedure Execute; override;
  public
    constructor Create(AServer: TShellCompletionServer; const AHostSink: ILogSink; const AOutput: IShellMemoryPipe;
      const ARun: IShellInProcessRun);
  end;

  /// <summary>Reicht Warnungen und Fehler an die Senke des Gastgebers weiter; deren Fehler verschluckt sie. Detach
  /// hängt sie ab (Code des Gastgebers kann danach entladen werden).</summary>
  THostSink = class(TInterfacedObject, ILogSink)
  private
    FLock: TObject;
    FTarget: ILogSink;
  public
    constructor Create(const ATarget: ILogSink);
    destructor Destroy; override;
    procedure Write(const AEntry: TLogEntry);
    procedure Detach;
  end;

var
  /// <summary>Schützt Active, die gemerkten Werte und CodeKept.</summary>
  StateLock: TObject;
  Active: Integer;
  SavedLanguage: TTextLanguage;
  CodeKept: Boolean;

{ TShellMemoryPipe }

constructor TShellMemoryPipe.Create(ACapacity: Int64; AWriteWaitMs: Cardinal);
begin
  inherited Create;
  FLock := TObject.Create;
  FChunks := TQueue<TBytes>.Create;
  FCapacity := ACapacity;
  if FCapacity < 1 then
  begin
    FCapacity := 1;
  end;
  FWriteWaitMs := AWriteWaitMs;
end;

destructor TShellMemoryPipe.Destroy;
begin
  FChunks.Free;
  FLock.Free;
  inherited;
end;

procedure TShellMemoryPipe.Write(const ABuffer; ACount: Integer);
var
  mChunk: TBytes;
  mDue, mNow: UInt64;

  function Full: Boolean;
  begin
    // Ein einzelnes großes Stück passt immer in einen leeren Puffer, sonst käme es nie durch.
    Result := (FSize > 0) and (FSize + ACount > FCapacity);
  end;

begin
  if ACount <= 0 then
  begin
    Exit;
  end;
  SetLength(mChunk, ACount);
  Move(ABuffer, mChunk[0], ACount);
  TMonitor.Enter(FLock);
  try
    if FClosed then
    begin
      Exit;
    end;
    if Full and (FWriteWaitMs > 0) then
    begin
      // Gegendruck: auf den Leser warten, aber nicht ewig.
      mDue := TThread.GetTickCount64 + FWriteWaitMs;
      while not FClosed and Full do
      begin
        mNow := TThread.GetTickCount64;
        if mNow >= mDue then
        begin
          Break;
        end;
        TMonitor.Wait(FLock, Cardinal(mDue - mNow));
      end;
    end;
    if FClosed then
    begin
      Exit;
    end;
    if Full then
    begin
      // Niemand liest: Ende statt unbegrenzt wachsen. Der Leser bekommt den Rest und dann 0.
      FOverflowed := True;
      FClosed := True;
      TMonitor.PulseAll(FLock);
      Exit;
    end;
    FChunks.Enqueue(mChunk);
    Inc(FSize, ACount);
    TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellMemoryPipe.Read(var ABuffer; ACount: Integer): Integer;
var
  mChunk: TBytes;
  mTarget: PByte;
  mCount: Integer;
begin
  Result := 0;
  if ACount <= 0 then
  begin
    Exit;
  end;
  mTarget := @ABuffer;
  TMonitor.Enter(FLock);
  try
    while (FChunks.Count = 0) and not FClosed do
    begin
      TMonitor.Wait(FLock, INFINITE);
    end;
    // Wie ReadFile auf einer Pipe: was da ist, höchstens ACount, auch über mehrere Stücke.
    while (Result < ACount) and (FChunks.Count > 0) do
    begin
      mChunk := FChunks.Peek;
      mCount := Length(mChunk) - FOffset;
      if mCount > ACount - Result then
      begin
        mCount := ACount - Result;
      end;
      Move(mChunk[FOffset], mTarget[Result], mCount);
      Inc(Result, mCount);
      Inc(FOffset, mCount);
      if FOffset >= Length(mChunk) then
      begin
        FChunks.Dequeue;
        FOffset := 0;
      end;
    end;
    if Result > 0 then
    begin
      Dec(FSize, Result);
      // Wartende Schreiber: Es ist wieder Platz.
      TMonitor.PulseAll(FLock);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellMemoryPipe.Close;
begin
  TMonitor.Enter(FLock);
  try
    FClosed := True;
    TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellMemoryPipe.Closed: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FClosed;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellMemoryPipe.Overflowed: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FOverflowed;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellMemoryPipe.Buffered: Int64;
begin
  TMonitor.Enter(FLock);
  try
    Result := FSize;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TShellMemoryPipe.ReadStream(const APipe: IShellMemoryPipe): TStream;
begin
  Result := TPipeReadStream.Create(APipe);
end;

class function TShellMemoryPipe.WriteStream(const APipe: IShellMemoryPipe): TStream;
begin
  Result := TPipeWriteStream.Create(APipe);
end;

{ TPipeReadStream }

constructor TPipeReadStream.Create(const APipe: IShellMemoryPipe);
begin
  inherited Create;
  FPipe := APipe;
end;

function TPipeReadStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result := FPipe.Read(Buffer, Count);
end;

function TPipeReadStream.Write(const Buffer; Count: Longint): Longint;
begin
  raise EStreamError.CreateRes(@SWriteError);
end;

function TPipeReadStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  // Nicht positionierbar, wie eine Pipe.
  Result := 0;
end;

{ TPipeWriteStream }

constructor TPipeWriteStream.Create(const APipe: IShellMemoryPipe);
begin
  inherited Create;
  FPipe := APipe;
end;

function TPipeWriteStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result := 0;
end;

function TPipeWriteStream.Write(const Buffer; Count: Longint): Longint;
begin
  FPipe.Write(Buffer, Count);
  Result := Count;
end;

function TPipeWriteStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  Result := 0;
end;

{ TShellInProcessRun }

constructor TShellInProcessRun.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FDone := TEvent.Create(nil, True, False, '');
  FExitCode := 1;
end;

destructor TShellInProcessRun.Destroy;
begin
  FDone.Free;
  FLock.Free;
  inherited;
end;

function TShellInProcessRun.Finish(AExitCode: Integer): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    FExitCode := AExitCode;
    FFinished := True;
    Result := FAbandoned;
    // Erst fertig melden, dann die Ausgabe schließen: Wer das Ende der Ausgabe sieht, findet den Exit-Code schon vor.
    FDone.SetEvent;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellInProcessRun.Abandon: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    // Unter derselben Sperre wie Finish: Entweder Stop gibt auf, oder der Thread war schon fertig.
    Result := not FFinished;
    if Result then
    begin
      FAbandoned := True;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellInProcessRun.WaitDone(ATimeoutMs: Cardinal): Boolean;
begin
  Result := FDone.WaitFor(ATimeoutMs) = TWaitResult.wrSignaled;
end;

function TShellInProcessRun.Done: Boolean;
begin
  Result := WaitDone(0);
end;

function TShellInProcessRun.ExitCode: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := 1;
    if FFinished then
    begin
      Result := FExitCode;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellInProcessRun.SetLeftWork;
begin
  TMonitor.Enter(FLock);
  try
    FLeftWork := True;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellInProcessRun.LeftWork: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FLeftWork;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ THostSink }

constructor THostSink.Create(const ATarget: ILogSink);
begin
  inherited Create;
  FLock := TObject.Create;
  FTarget := ATarget;
end;

destructor THostSink.Destroy;
begin
  FTarget := nil;
  FLock.Free;
  inherited;
end;

procedure THostSink.Write(const AEntry: TLogEntry);
begin
  // Unter der Sperre: Detach kehrt erst zurück, wenn kein Aufruf in den Code des Gastgebers mehr läuft.
  TMonitor.Enter(FLock);
  try
    if FTarget <> nil then
    try
      FTarget.Write(AEntry);
    except
      // Das Protokoll des Gastgebers darf den Server nie stören.
      on Exception do
        ;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure THostSink.Detach;
begin
  TMonitor.Enter(FLock);
  try
    FTarget := nil;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TServerThread }

constructor TServerThread.Create(AServer: TShellCompletionServer; const AHostSink: ILogSink;
  const AOutput: IShellMemoryPipe; const ARun: IShellInProcessRun);
begin
  FServer := AServer;
  FHostSink := AHostSink;
  FOutput := AOutput;
  FRun := ARun;
  // Nie FreeOnTerminate von außen: Execute entscheidet am Ende unter der Sperre des Laufs (Abandoned).
  inherited Create(False);
end;

procedure TServerThread.Execute;
var
  mExitCode: Integer;
  mAbandoned: Boolean;
begin
  NameThreadForDebugging('dpcc.Server (in-process)');
  try
    try
      mExitCode := FServer.Run;
    finally
      // Nach Run: Wächter, Verbindung, Worker-Pool, Index-Threads und Features in der Reihenfolge der
      // Wurzel (TShellCompletionServerParts.Destroy); im IDE-Prozess mit Wartezeit für noch laufende Anfragen.
      FreeAndNil(FServer);
    end;
  except
    // Nie aus dem Thread heraus: Im IDE-Prozess fängt sonst niemand.
    on E: Exception do
    begin
      mExitCode := 1;
      if FHostSink <> nil then
      begin
        FHostSink.Write(TLogEntry.Create(Now, TLogLevel.Error, 'In-Process-Server abgebrochen: ' + E.ClassName +
          ': ' + E.Message));
      end;
    end;
  end;
  FHostSink := nil;
  mAbandoned := FRun.Finish(mExitCode);
  if mAbandoned then
  begin
    // Stop wartet nicht mehr: ThreadProc liest FreeOnTerminate erst nach Execute, das Setzen hier ist sicher.
    FreeOnTerminate := True;
  end;
  // Ende der Ausgabe: Der Client sieht, dass der Server fort ist (auch nach exit oder einem Abbruch ohne Stop).
  FOutput.Close;
  FOutput := nil;
  if mAbandoned and not FRun.LeftWork then
  begin
    // Stop gab auf und rief Release nicht; jetzt läuft nichts mehr.
    TShellInProcessServer.Release;
  end;
end;

{ TShellInProcessServer }

class procedure TShellInProcessServer.Acquire;
begin
  TMonitor.Enter(StateLock);
  try
    Inc(Active);
    if Active = 1 then
    begin
      SavedLanguage := TDpccLocale.Language;
      // Liste der published-Mitglieder je Klasse merken (Hover auf VCL-Klassen kostet sonst jedes Mal rund 1 s).
      TPublishedMembers.UseCache(True);
      TShellPlatform.InstallGuards;
    end;
  finally
    TMonitor.Exit(StateLock);
  end;
end;

class procedure TShellInProcessServer.Release;
begin
  TMonitor.Enter(StateLock);
  try
    Dec(Active);
    if Active = 0 then
    begin
      TShellPlatform.UninstallGuards;
      // Gibt den Cache frei.
      TPublishedMembers.UseCache(False);
      TDpccLocale.Use(SavedLanguage);
      // Kein Server mehr, kein Index: prozessweite Merker freigeben, die sonst den Speicher eines beendeten Servers
      // hielten. Der nächste Server liest die Caches ohnehin neu.
      TImportNames.Clear;
      TIndexService.ForgetSharedStates;
      TSharedUnitListings.Clear;
    end;
  finally
    TMonitor.Exit(StateLock);
  end;
end;

class function TShellInProcessServer.ActiveCount: Integer;
begin
  TMonitor.Enter(StateLock);
  try
    Result := Active;
  finally
    TMonitor.Exit(StateLock);
  end;
end;

class function TShellInProcessServer.CodeKeptLoaded: Boolean;
begin
  TMonitor.Enter(StateLock);
  try
    Result := CodeKept;
  finally
    TMonitor.Exit(StateLock);
  end;
end;

{$IFDEF MSWINDOWS}
const
  GET_MODULE_HANDLE_EX_FLAG_PIN = $00000001;

function GetModuleHandleExW(dwFlags: DWORD; lpModuleName: PWideChar; var phModule: HMODULE): BOOL; stdcall;
  external kernel32 name 'GetModuleHandleExW';
{$ENDIF}

class procedure TShellInProcessServer.KeepCodeLoaded;
{$IFDEF MSWINDOWS}
var
  mName: string;
  mModule: HMODULE;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  // Statisch gelinkt (Testprogramm): Der Code gehört zum Programm und wird nie entladen.
  if HInstance = MainInstance then
  begin
    Exit;
  end;
  TMonitor.Enter(StateLock);
  try
    if CodeKept then
    begin
      Exit;
    end;
    CodeKept := True;
  finally
    TMonitor.Exit(StateLock);
  end;
  mName := GetModuleName(HInstance);
  // 1. Das Modul nie mehr entladen (bis Prozessende); es hält seine Abhängigkeiten dpcc.Common, dpcc.Text,
  //    dpcc.Windows und dpcc.WinBase über die Importtabelle.
  mModule := 0;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_PIN, PWideChar(mName), mModule);
  // 2. Ein eigenes LoadPackage ohne UnloadPackage: Es zählt die Units von dpcc.Server und den benutzten Units der
  //    Abhängigkeiten einmal mehr als initialisiert; beim Entladen des Plugins laufen ihre finalization-Abschnitte
  //    deshalb nicht, globale Sperren und Tabellen bleiben für den weiterlaufenden Thread gültig.
  try
    LoadPackage(mName);
  except
    // Dann bleibt nur 1. (Code geladen, Units womöglich finalisiert).
    on Exception do
      ;
  end;
  {$ENDIF}
end;

constructor TShellInProcessServer.Create(const AHostSink: ILogSink);
begin
  Create(AHostSink, nil);
end;

constructor TShellInProcessServer.Create(const AHostSink: ILogSink; const AConfigure: TShellInProcessConfigure);
var
  mLogger: TLogger;
  mLoggerRef: ILogger;
  mTransport: IJsonRpcTransport;
  mServer: TShellCompletionServer;
  mDebugSink: ILogSink;
  mRun: IShellInProcessRun;
  mHostSink: THostSink;
  mInput: IShellMemoryPipe;
  mOnExit: TProc;
begin
  inherited Create;
  // Zum Server schreibt auch der Hauptthread der IDE: nie warten. Vom Server: Gegendruck bis cServerWriteWaitMs.
  FToServer := TShellMemoryPipe.Create(cPipeCapacity, 0);
  FFromServer := TShellMemoryPipe.Create(cPipeCapacity, cServerWriteWaitMs);
  FClientInput := TShellMemoryPipe.ReadStream(FFromServer);
  FClientOutput := TShellMemoryPipe.WriteStream(FToServer);
  FRun := TShellInProcessRun.Create;
  mRun := FRun;
  // Für exit (unten): die Pipe selbst, nicht Self; der Thread kann das Objekt überleben (Abandoned).
  mInput := FToServer;
  FHostSink := nil;
  FHostSinkRef := nil;
  if AHostSink <> nil then
  begin
    mHostSink := THostSink.Create(AHostSink);
    FHostSink := mHostSink;
    FHostSinkRef := mHostSink;
  end;
  mServer := nil;
  Acquire;
  try
    // Der Transport gibt seine beiden Streams frei; die Pipes leben, solange eine Seite sie hält.
    mTransport := TJsonRpcStreamTransport.Create(TShellMemoryPipe.ReadStream(FToServer),
      TShellMemoryPipe.WriteStream(FFromServer), True);
    // Ohne Datei und ohne stderr: Debug-Ausgabe, window/logMessage an den Client und die Senke des Gastgebers.
    mLogger := TLogger.Create;
    mLoggerRef := mLogger;
    mDebugSink := TShellPlatform.DebugLogSink;
    if mDebugSink <> nil then
    begin
      mLogger.AddSink(mDebugSink, TLogLevel.Debug);
    end;
    mLogger.AddSink(TLspLogMessageSink.Create(mTransport), TLogLevel.Info);
    if FHostSinkRef <> nil then
    begin
      mLogger.AddSink(FHostSinkRef, TLogLevel.Warning);
    end;
    mServer := TShellCompletionServer.Create(mTransport, mLoggerRef);
    // Wie CreateForStreams.
    mServer.Parts.Channel.Anonymizer := TLogAnonymizer.Create(TProcessInfo.IdentityNames);
    // Der Prozess endet nicht mit dem Server: noch laufende Anfragen abwarten, statt Objekte stehen zu lassen.
    mServer.Parts.UnfinishedWaitMs := cUnfinishedWaitMs;
    mServer.Parts.OnLeftWork :=
      procedure
      begin
        mRun.SetLeftWork;
      end;
    // Erst wenn die stehen gelassenen Anfragen fertig und ihre Objekte frei sind (a4).
    mServer.Parts.OnLateRelease :=
      procedure
      begin
        TShellInProcessServer.Release;
      end;
    // exit beendet die Schleife, die Eingabe bliebe aber offen: Der Lese-Thread der Verbindung hinge dann im Lesen,
    // Run gäbe ihn erst nach TJsonRpcConnection.cDefaultReaderTimeout auf, und er endete erst nach dem Abbau (Stop),
    // ohne dass jemand auf ihn wartet; bis dahin hielt er den Transport (64 KB Lesepuffer) und beide Pipes. Nach exit
    // liest der Server nichts mehr: Eingabe gleich schließen, dann endet der Lese-Thread sofort und Run wartet auf ihn.
    mOnExit := mServer.Parts.Protocol.Lifecycle.OnExit;
    mServer.Parts.Protocol.Lifecycle.OnExit :=
      procedure
      begin
        try
          if Assigned(mOnExit) then
          begin
            mOnExit();
          end;
        finally
          mInput.Close;
        end;
      end;
    if Assigned(AConfigure) then
    begin
      AConfigure(mServer);
    end;
    FThread := TServerThread.Create(mServer, FHostSinkRef, FFromServer, FRun);
    // Ab hier gehört die Wurzel dem Thread.
    mServer := nil;
  except
    // Auch wenn TServerThread.Create scheitert: Die Wurzel gehört dann noch hier.
    mServer.Free;
    Release;
    FStopped := True;
    FStopResult := True;
    raise;
  end;
end;

destructor TShellInProcessServer.Destroy;
begin
  Stop;
  // Nach Stop gibt es keinen Thread mehr, den dieses Objekt freigeben müsste (Abandoned: er gibt sich selbst frei).
  FreeAndNil(FThread);
  FClientInput.Free;
  FClientOutput.Free;
  FToServer := nil;
  FFromServer := nil;
  FHostSink := nil;
  FHostSinkRef := nil;
  FRun := nil;
  inherited;
end;

procedure TShellInProcessServer.DetachHostSink;
begin
  if FHostSinkRef <> nil then
  begin
    THostSink(FHostSink).Detach;
  end;
end;

function TShellInProcessServer.Stop(ATimeoutMs: Cardinal): Boolean;
begin
  if FStopped then
  begin
    Exit(FStopResult);
  end;
  FStopped := True;
  // Ende der Eingabe: Die Schleife endet nach dem Schließen der Eingabe-Pipe, auch ohne exit, und bricht
  // die laufenden Anfragen ab.
  FToServer.Close;
  if not FRun.WaitDone(ATimeoutMs) and FRun.Abandon then
  begin
    // Kein TerminateThread: Der Thread hält Sperren des Speichermanagers und der Wurzel. Er gibt sich selbst frei und
    // ruft Release; sein Code bleibt geladen, der des Gastgebers wird nicht mehr gerufen.
    FAbandoned := True;
    FThread := nil;
    DetachHostSink;
    KeepCodeLoaded;
  end
  else
  begin
    // Fertig: Auf das wirkliche Ende des Threads warten (danach läuft kein Code der Wurzel mehr) und freigeben.
    FThread.WaitFor;
    FreeAndNil(FThread);
    if FRun.LeftWork then
    begin
      // Anfragen laufen weiter auf stehen gelassenen Objekten: Code geladen lassen, Schalter nicht zurücknehmen.
      FLeftWork := True;
      DetachHostSink;
      KeepCodeLoaded;
    end
    else
    begin
      Release;
    end;
  end;
  // Erst danach: Bis zuletzt schreiben Wurzel und Logger (window/logMessage) in die Ausgabe. Wartet ein Schreiber
  // auf Platz, kehrt er jetzt zurück.
  FFromServer.Close;
  Result := not FAbandoned and not FLeftWork;
  FStopResult := Result;
end;

function TShellInProcessServer.Running: Boolean;
begin
  Result := (FRun <> nil) and not FRun.Done and not FToServer.Closed;
end;

function TShellInProcessServer.WaitFor(ATimeoutMs: Cardinal): Boolean;
begin
  Result := (FRun = nil) or FRun.WaitDone(ATimeoutMs);
end;

function TShellInProcessServer.ExitCode: Integer;
begin
  Result := 1;
  if FRun <> nil then
  begin
    Result := FRun.ExitCode;
  end;
end;

function TShellInProcessServer.InputOverflowed: Boolean;
begin
  Result := FToServer.Overflowed;
end;

initialization
  StateLock := TObject.Create;

finalization
  FreeAndNil(StateLock);

end.
