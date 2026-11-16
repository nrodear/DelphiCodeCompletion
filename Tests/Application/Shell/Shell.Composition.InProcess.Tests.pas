unit Shell.Composition.InProcess.Tests;

// Abbau des In-Process-Servers ohne IDE (Rückbau R4, Befunde 4.1/4.3 in docs\Review\server\liste.md): Stop während
// laufender Anfrage, Wartezeit für Anfragen, die ihr Abbruchsignal nicht prüfen, Zeitgrenze von Stop (Abandoned,
// der Thread endet später allein), Neustart mit den globalen Anbietern des neuen Servers, Fehler beim Verdrahten
// ohne Leck, begrenzte Speicher-Pipes. Die Anfragen sind Testmethoden am Verteiler der Wurzel (Configure-Haken),
// ohne Projekt und ohne Index. Jeder Test wartet, bis die Threads des Servers fort sind.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellInProcessServerTests = class
  public
    /// <summary>Einmal-Belegungen (Texttabellen, Sperrobjekte, Thread-Pools) vor der Messung.</summary>
    [SetupFixture]
    procedure WarmUp;
    /// <summary>Volle Pipe ohne Wartezeit: geschlossen statt wachsen; der Leser bekommt den Rest und dann 0.
    /// </summary>
    [Test]
    procedure PipeOverflowWithoutWaitCloses;
    /// <summary>Ein Stück über der Obergrenze passt in einen leeren Puffer.</summary>
    [Test]
    procedure PipeLargeChunkPassesEmptyBuffer;
    /// <summary>Volle Pipe mit Wartezeit: Der Schreiber wartet, bis gelesen wird.</summary>
    [Test]
    procedure PipeWriterWaitsForReader;
    /// <summary>Volle Pipe mit Wartezeit ohne Leser: nach der Wartezeit geschlossen.</summary>
    [Test]
    procedure PipeWriterGivesUpWithoutReader;
    /// <summary>Stop während einer Anfrage, die ihr Abbruchsignal prüft: schnell, sauber, abgemeldet.</summary>
    [Test]
    procedure StopCancelsRunningRequest;
    /// <summary>Stop während einer Anfrage, die das Abbruchsignal nicht prüft und länger läuft als Schleife und
    /// Pool warten: Die Wurzel wartet weiter und gibt dann alles frei.</summary>
    [Test]
    procedure StopWaitsForUnfinishedRequest;
    /// <summary>Hängt eine Anfrage über die Zeitgrenze von Stop: False, Abandoned; endet sie später, gibt der
    /// Thread sich und die Wurzel frei und meldet den Server ab.</summary>
    [Test]
    procedure StopTimeoutAbandonsServer;
    /// <summary>Zwei Server nacheinander im Prozess: Der Abbau des alten lässt die Anbieter des neuen gesetzt.
    /// </summary>
    [Test]
    procedure StoppingOldServerKeepsProvidersOfNew;
    /// <summary>Fehler beim Verdrahten: Exception, kein Leck, kein Server angemeldet.</summary>
    [Test]
    procedure ConfigureFailureLeavesNothing;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.Pascal.TreeCache,
  dpcc.Common.Pascal.Preprocessor,
  dpcc.Tests.LeakMonitor,
  Shell.Composition.CompletionServer,
  Shell.Composition.InProcess;

const
  cWaitMethod = 'test/wait';
  cInitialize = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":null,"rootUri":null,' +
    '"capabilities":{}}}';
  cWaitRequest = '{"jsonrpc":"2.0","id":2,"method":"' + cWaitMethod + '","params":{}}';
  cStartMs = 10000;
  cSettleMs = 10000;

type
  /// <summary>Wie sich die Testanfrage verhält.</summary>
  TWaitMode = (
    /// <summary>Prüft das Abbruchsignal alle 10 ms.</summary>
    Cooperative,
    /// <summary>Schläft eine feste Zeit, ohne das Signal zu prüfen.</summary>
    Sleeps,
    /// <summary>Wartet auf Release, ohne das Signal zu prüfen.</summary>
    Blocks);

  /// <summary>Zustand einer Testanfrage; gehört dem Test, die Anfrage hält eine Referenz.</summary>
  TWaitProbe = class
  public
    Started: TEvent;
    Release: TEvent;
    Finished: TEvent;
    SawCancel: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TWaitProbe.Create;
begin
  inherited Create;
  Started := TEvent.Create(nil, True, False, '');
  Release := TEvent.Create(nil, True, False, '');
  Finished := TEvent.Create(nil, True, False, '');
end;

destructor TWaitProbe.Destroy;
begin
  Finished.Free;
  Release.Free;
  Started.Free;
  inherited;
end;

function Frame(const AJson: string): TBytes;
var
  mBody: TBytes;
begin
  mBody := TEncoding.UTF8.GetBytes(AJson);
  Result := TEncoding.ASCII.GetBytes(Format('Content-Length: %d'#13#10#13#10, [Length(mBody)])) + mBody;
end;

procedure Send(AServer: TShellInProcessServer; const AJson: string);
var
  mBytes: TBytes;
begin
  mBytes := Frame(AJson);
  AServer.ClientOutput.WriteBuffer(mBytes[0], Length(mBytes));
end;

/// <summary>Meldet test/wait an. AProbe gehört dem Test; er gibt sie erst nach dem Ende der Anfrage frei.</summary>
function WaitConfigure(AMode: TWaitMode; ASleepMs: Cardinal; const AProbe: TWaitProbe;
  AWorkTimeoutMs: Cardinal): TShellInProcessConfigure;
var
  mProbe: TWaitProbe;
begin
  mProbe := AProbe;
  Result :=
    procedure(AServer: TShellCompletionServer)
    begin
      if AWorkTimeoutMs > 0 then
      begin
        AServer.Parts.Connection.WorkTimeout := AWorkTimeoutMs;
      end;
      AServer.Parts.Protocol.Dispatcher.RegisterConcurrentRequest(cWaitMethod,
        function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
        begin
          mProbe.Started.SetEvent;
          try
            case AMode of
              TWaitMode.Cooperative:
                while not ACancellation.IsCancellationRequested do
                begin
                  TThread.Sleep(10);
                end;
              TWaitMode.Sleeps:
                TThread.Sleep(ASleepMs);
              TWaitMode.Blocks:
                mProbe.Release.WaitFor;
            end;
            mProbe.SawCancel := ACancellation.IsCancellationRequested;
          finally
            mProbe.Finished.SetEvent;
          end;
          Result := TJSONNull.Create;
        end);
    end;
end;

/// <summary>Startet den Server mit test/wait und wartet, bis die Anfrage läuft.</summary>
function StartWaiting(const AConfigure: TShellInProcessConfigure; const AProbe: TWaitProbe): TShellInProcessServer;
begin
  Result := TShellInProcessServer.Create(nil, AConfigure);
  Send(Result, cInitialize);
  Send(Result, cWaitRequest);
  Assert.IsTrue(AProbe.Started.WaitFor(cStartMs) = TWaitResult.wrSignaled, 'Anfrage läuft');
end;

procedure WaitForThreads(AThreads: Integer);
var
  mStarted: UInt64;
begin
  mStarted := TThread.GetTickCount64;
  while (ProcessThreadCount > AThreads) and (TThread.GetTickCount64 - mStarted < cSettleMs) do
  begin
    TThread.Sleep(20);
  end;
  Assert.IsTrue(ProcessThreadCount <= AThreads, Format('Threads vorher %d, nachher %d', [AThreads,
    ProcessThreadCount]));
end;

{ TShellInProcessServerTests }

procedure TShellInProcessServerTests.WarmUp;
var
  mServer: TShellInProcessServer;
  mProbe: TWaitProbe;
begin
  mProbe := TWaitProbe.Create;
  try
    mServer := StartWaiting(WaitConfigure(TWaitMode.Cooperative, 0, mProbe, 0), mProbe);
    mServer.Free;
  except
    // Scheitert der Lauf, meldet das der Test selbst.
    on Exception do
      ;
  end;
  mProbe.Free;
end;

procedure TShellInProcessServerTests.PipeOverflowWithoutWaitCloses;
var
  mPipe: IShellMemoryPipe;
  mData: TBytes;
  mBuffer: array[0..31] of Byte;
begin
  mPipe := TShellMemoryPipe.Create(10, 0);
  SetLength(mData, 8);
  FillChar(mData[0], Length(mData), 1);
  mPipe.Write(mData[0], 8);
  Assert.IsFalse(mPipe.Closed, 'unter der Grenze offen');
  mPipe.Write(mData[0], 5);
  Assert.IsTrue(mPipe.Overflowed, 'übergelaufen');
  Assert.IsTrue(mPipe.Closed, 'geschlossen');
  Assert.AreEqual(8, mPipe.Read(mBuffer, SizeOf(mBuffer)), 'Rest');
  Assert.AreEqual(0, mPipe.Read(mBuffer, SizeOf(mBuffer)), 'Ende');
end;

procedure TShellInProcessServerTests.PipeLargeChunkPassesEmptyBuffer;
var
  mPipe: IShellMemoryPipe;
  mData: TBytes;
begin
  mPipe := TShellMemoryPipe.Create(4, 0);
  SetLength(mData, 10);
  mPipe.Write(mData[0], 10);
  Assert.IsFalse(mPipe.Overflowed, 'nicht übergelaufen');
  Assert.AreEqual(Int64(10), mPipe.Buffered, 'gepuffert');
end;

procedure TShellInProcessServerTests.PipeWriterWaitsForReader;
var
  mPipe: IShellMemoryPipe;
  mData: TBytes;
  mReader: TThread;
  mRead: Integer;
begin
  mPipe := TShellMemoryPipe.Create(8, 5000);
  SetLength(mData, 8);
  mPipe.Write(mData[0], 8);
  mRead := 0;
  mReader := TThread.CreateAnonymousThread(
    procedure
    var
      mBuffer: array[0..15] of Byte;
    begin
      TThread.Sleep(100);
      mRead := mPipe.Read(mBuffer, SizeOf(mBuffer));
    end);
  mReader.FreeOnTerminate := False;
  try
    mReader.Start;
    // Wartet, bis der Leser Platz macht.
    mPipe.Write(mData[0], 4);
    mReader.WaitFor;
  finally
    mReader.Free;
  end;
  Assert.AreEqual(8, mRead, 'gelesen');
  Assert.IsFalse(mPipe.Overflowed, 'nicht übergelaufen');
  Assert.AreEqual(Int64(4), mPipe.Buffered, 'zweites Stück gepuffert');
end;

procedure TShellInProcessServerTests.PipeWriterGivesUpWithoutReader;
var
  mPipe: IShellMemoryPipe;
  mData: TBytes;
  mStarted: UInt64;
begin
  mPipe := TShellMemoryPipe.Create(8, 200);
  SetLength(mData, 8);
  mPipe.Write(mData[0], 8);
  mStarted := TThread.GetTickCount64;
  mPipe.Write(mData[0], 4);
  Assert.IsTrue(TThread.GetTickCount64 - mStarted >= 150, 'gewartet');
  Assert.IsTrue(mPipe.Overflowed, 'übergelaufen');
  Assert.IsTrue(mPipe.Closed, 'geschlossen');
end;

procedure TShellInProcessServerTests.StopCancelsRunningRequest;
var
  mThreads: Integer;
  mServer: TShellInProcessServer;
  mProbe: TWaitProbe;
  mStarted: UInt64;
begin
  mThreads := ProcessThreadCount;
  mProbe := TWaitProbe.Create;
  mServer := StartWaiting(WaitConfigure(TWaitMode.Cooperative, 0, mProbe, 0), mProbe);
  try
    mStarted := TThread.GetTickCount64;
    Assert.IsTrue(mServer.Stop, 'Stop sauber');
    Assert.IsTrue(TThread.GetTickCount64 - mStarted < 5000, 'Stop ohne Warten auf Zeitgrenzen');
    Assert.IsFalse(mServer.Abandoned, 'nicht aufgegeben');
    Assert.IsFalse(mServer.LeftWork, 'nichts stehen gelassen');
  finally
    mServer.Free;
  end;
  Assert.IsTrue(mProbe.Finished.WaitFor(0) = TWaitResult.wrSignaled, 'Anfrage zu Ende');
  Assert.IsTrue(mProbe.SawCancel, 'Abbruchsignal gesehen');
  Assert.AreEqual(0, TShellInProcessServer.ActiveCount, 'abgemeldet');
  mProbe.Free;
  WaitForThreads(mThreads);
end;

procedure TShellInProcessServerTests.StopWaitsForUnfinishedRequest;
var
  mThreads: Integer;
  mServer: TShellInProcessServer;
  mProbe: TWaitProbe;
begin
  mThreads := ProcessThreadCount;
  mProbe := TWaitProbe.Create;
  // 3 s: länger als die Schleife (100 ms) und der Pool (2 s) warten, kürzer als die Wurzel (8 s).
  mServer := StartWaiting(WaitConfigure(TWaitMode.Sleeps, 3000, mProbe, 100), mProbe);
  try
    Assert.IsTrue(mServer.Stop, 'Stop sauber');
    Assert.IsFalse(mServer.Abandoned, 'nicht aufgegeben');
    Assert.IsFalse(mServer.LeftWork, 'Features freigegeben');
  finally
    mServer.Free;
  end;
  Assert.IsTrue(mProbe.Finished.WaitFor(0) = TWaitResult.wrSignaled, 'Anfrage vor dem Ende fertig');
  Assert.AreEqual(0, TShellInProcessServer.ActiveCount, 'abgemeldet');
  mProbe.Free;
  WaitForThreads(mThreads);
end;

procedure TShellInProcessServerTests.StopTimeoutAbandonsServer;
var
  mThreads: Integer;
  mServer: TShellInProcessServer;
  mProbe: TWaitProbe;
  mStarted: UInt64;
  mStopped: Boolean;
begin
  mThreads := ProcessThreadCount;
  mProbe := TWaitProbe.Create;
  mServer := StartWaiting(WaitConfigure(TWaitMode.Blocks, 0, mProbe, 100), mProbe);
  try
    mStarted := TThread.GetTickCount64;
    mStopped := mServer.Stop(500);
    Assert.IsFalse(mStopped, 'Stop meldet die Zeitüberschreitung');
    Assert.IsTrue(TThread.GetTickCount64 - mStarted < 3000, 'Zeitgrenze eingehalten');
    Assert.IsTrue(mServer.Abandoned, 'aufgegeben');
    Assert.IsFalse(mServer.Running, 'Schleife läuft nicht mehr');
    Assert.AreEqual(1, TShellInProcessServer.ActiveCount, 'noch angemeldet, solange der Thread läuft');
    Assert.IsFalse(TShellInProcessServer.CodeKeptLoaded, 'statisch gelinkt: nichts festzuhalten');
  finally
    // Freigeben, während der Thread noch läuft: Er gibt sich später selbst frei.
    mServer.Free;
  end;
  mProbe.Release.SetEvent;
  mStarted := TThread.GetTickCount64;
  while (TShellInProcessServer.ActiveCount > 0) and (TThread.GetTickCount64 - mStarted < cSettleMs) do
  begin
    TThread.Sleep(20);
  end;
  Assert.AreEqual(0, TShellInProcessServer.ActiveCount, 'der Thread meldet den Server selbst ab');
  mProbe.Free;
  WaitForThreads(mThreads);
end;

procedure TShellInProcessServerTests.StoppingOldServerKeepsProvidersOfNew;
var
  mThreads: Integer;
  mOld, mNew: TShellInProcessServer;
begin
  mThreads := ProcessThreadCount;
  mOld := TShellInProcessServer.Create(nil);
  try
    mNew := TShellInProcessServer.Create(nil);
    try
      Assert.IsTrue(mOld.Stop, 'alter Server sauber beendet');
      FreeAndNil(mOld);
      Assert.IsTrue(TSyntaxTreeCache.HasDefinesProvider, 'Symbole des neuen Servers');
      Assert.IsTrue(TSyntaxTreeCache.HasIncludeProvider, 'Include-Dateien des neuen Servers');
      Assert.IsTrue(TPascalPreprocessor.HasDeclaredProvider, 'Declared(X) des neuen Servers');
      Assert.AreEqual(1, TShellInProcessServer.ActiveCount, 'neuer Server angemeldet');
      Assert.IsTrue(mNew.Stop, 'neuer Server sauber beendet');
    finally
      mNew.Free;
    end;
  finally
    mOld.Free;
  end;
  Assert.IsFalse(TSyntaxTreeCache.HasDefinesProvider, 'Symbole zurückgenommen');
  Assert.IsFalse(TSyntaxTreeCache.HasIncludeProvider, 'Include-Dateien zurückgenommen');
  Assert.IsFalse(TPascalPreprocessor.HasDeclaredProvider, 'Declared(X) zurückgenommen');
  Assert.AreEqual(0, TShellInProcessServer.ActiveCount, 'abgemeldet');
  WaitForThreads(mThreads);
end;

procedure TShellInProcessServerTests.ConfigureFailureLeavesNothing;
var
  mThreads: Integer;
begin
  mThreads := ProcessThreadCount;
  Assert.WillRaise(
    procedure
    begin
      TShellInProcessServer.Create(nil,
        procedure(AServer: TShellCompletionServer)
        begin
          raise EAbort.Create('Verdrahtung scheitert');
        end).Free;
    end, EAbort);
  Assert.AreEqual(0, TShellInProcessServer.ActiveCount, 'nicht angemeldet');
  Assert.IsFalse(TSyntaxTreeCache.HasDefinesProvider, 'keine Symbole übrig');
  Assert.IsFalse(TPascalPreprocessor.HasDeclaredProvider, 'kein Declared(X) übrig');
  WaitForThreads(mThreads);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellInProcessServerTests);

end.
