unit dpcc.IDE.Foundation.Watchdog;

// Einfrier-Wächter des Hauptthreads, abgespeckt (Nachfolger von
// dpcc.IDE.Diagnostics.Watchdog bis R56): misst nur und schreibt Zeilen, ohne
// SuspendThread und ohne Stapelabzug.
// - Ein Hintergrund-Thread schickt alle 50 ms eine Nachricht (PostMessage) an
//   ein eigenes Fenster des Hauptthreads (AllocateHWnd) und merkt, wann die
//   Antwort ausbleibt. Die Logik (Schwelle 250 ms, Drosselung, Pausen) liegt in
//   TDpccHangTracker (dpcc.Core.Diagnostics.Hangs), getestet ohne Thread.
// - Bleibt die Antwort ab 250 ms aus und läuft eine dpcc-Aktivität
//   (TDpccActivity.Running, ohne Sperre gelesen), schreibt der Thread sofort
//   „Hauptthread hängt seit n ms in <Aktivität>“ ins dpcc.log, mit der
//   Antwort „Hauptthread hing n ms in <Aktivität>“. Ohne dpcc-Aktivität (die
//   IDE kompiliert o. ä.) nur mit Diagnose = 1, dann „… ohne dpcc-Aktivität“
//   ins Diagnoselog (dpcc.IDE.Expert<Ver>.log). Beim Entladen eine
//   Zusammenfassung, wenn es Hänger gab.
// - Der Thread schreibt auch die gesammelten Zeilen des Hauptthreads
//   (TDpccSlowLog: Dauer von Aktivitäten ab 50 ms, Warten auf den Server ab
//   100 ms) ins dpcc.log: Der Hauptthread wartet so nie auf die Datei.
// - Keine Fehlalarme bei modalen Dialogen: Deren Nachrichtenschleife (ShowModal,
//   MessageBox, Menüs, Verschieben eines Fensters) verteilt auch die Nachricht an
//   dieses Fenster; die Antwort kommt also. Jede Antwort meldet zudem
//   TDpccActivity.MessagePumped: Ein Scope, in dem die Schleife lief, schreibt
//   keine Dauerzeile. Steht die IDE selbst im Debugger (alle Threads
//   angehalten) oder im Ruhezustand, setzt auch der Takt dieses Threads aus;
//   TDpccHangTracker.Tick zieht diese Lücke ab. Debuggt die IDE ein anderes
//   Programm, das angehalten ist, läuft die Nachrichtenschleife der IDE normal.
// - Gemessen wird erst, wenn die Nachrichtenschleife nach dem Laden frei ist
//   (Startnachricht), und nur, solange das Hauptfenster sichtbar ist und die
//   IDE nicht beendet wird.
// - Diagnose = 1 schaltet beim Start zusätzlich TDpccPluginTimings und
//   TDpccQueryTimings ein; beim Entladen stehen die 10 langsamsten Aufrufe,
//   Server-Anfragen und Abfragen im Diagnoselog.
// - Threads (wie dpcc.Core.Lsp.SessionStart): Der Thread hält keinen Verweis
//   auf Formulare, Manager oder IDE-Objekte, nur seinen eigenen Zustand und das
//   Fensterhandle. Stop (Entladen, nach TDpccShutdown.Signal) beendet ihn
//   begrenzt (TDpccShutdown.WaitForThreads), bevor Fenster und Protokoll weg
//   sind; endet er nicht rechtzeitig, gibt er sich selbst frei.
// - Gleitkomma-Einstellung (FPU1, TDpccIdeFpuWatch, nur lesend): beim Start eine Zeile mit Default8087CW und dem
//   Steuerwort des Hauptthreads; danach prüft jede Antwort des Fensters (Hauptthread, etwa alle 50 ms) beide Werte
//   und schreibt nur bei einer Änderung eine Zeile. Stop setzt den Zustand zurück.

interface

type
  TDpccWatchdog = class
  public
    /// <summary>Beim Anmelden, im Hauptthread: Fenster und Thread anlegen, TDpccSlowLog einschalten; im
    /// Diagnosemodus auch die Plugin- und Abfragezeiten.</summary>
    class procedure Start; static;
    /// <summary>Beim Entladen, im Hauptthread, vor dem Abbau von Protokoll und Fenstern: Thread begrenzt beenden,
    /// Zusammenfassung schreiben, Fenster freigeben.</summary>
    class procedure Stop; static;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  Vcl.Forms,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Diagnostics.Hangs,
  dpcc.Core.Diagnostics.PluginTimings,
  dpcc.Core.Diagnostics.Timing,
  dpcc.IDE.CodeInsight.Manager.Paths,
  dpcc.IDE.Foundation.FpuWatch;

const
  cWM_DPCC_PING = WM_APP + $4A1;
  cWM_DPCC_STARTUP = WM_APP + $4A2;
  /// <summary>Takt des Wächters.</summary>
  cPeriodMs = 50;
  /// <summary>So viele langsamste Einträge je Liste beim Entladen (Diagnosemodus).</summary>
  cSlowestCount = 10;

/// <summary>Stetige Uhr in ms.</summary>
function NowMs: Int64;
begin
  Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
end;

/// <summary>IDE läuft normal: Hauptfenster sichtbar, nicht im Beenden; nur im Hauptthread.</summary>
function IdeRunning: Boolean;
begin
  Result := not Application.Terminated and (Application.MainForm <> nil) and Application.MainForm.Visible;
end;

/// <summary>Zeilen des Wächters ins dpcc.log bzw. (Diagnostic) ins Diagnoselog; aus jedem Thread.</summary>
procedure WriteLines(const ALines: TArray<TDpccHangLine>);
var
  mLine: TDpccHangLine;
begin
  for mLine in ALines do
  begin
    if mLine.Diagnostic then
    begin
      TDpccCodeInsightPaths.Append(mLine.Text);
    end
    else
    begin
      TDpccGuard.Log(mLine.Text);
    end;
  end;
end;

/// <summary>Gesammelte Zeilen des Hauptthreads (TDpccSlowLog) ins dpcc.log.</summary>
procedure FlushSlowLog;
var
  mLine: string;
begin
  for mLine in TDpccSlowLog.Take do
  begin
    TDpccGuard.Log(mLine);
  end;
end;

type
  /// <summary>Wächter-Thread; besitzt seinen Zustand allein. Die Felder FPong, FPongAt, FReady und FStarted schreibt
  /// das Fenster im Hauptthread (atomar).</summary>
  TWatchThread = class(TThread)
  private
    FWindow: HWND;
    FWake: TEvent;
    FTracker: TDpccHangTracker;
    /// <summary>Nummer der zuletzt beantworteten Nachricht.</summary>
    FPong: Integer;
    /// <summary>Zeitpunkt dieser Antwort (NowMs).</summary>
    FPongAt: Int64;
    /// <summary>1: IDE läuft normal (beim letzten Beantworten).</summary>
    FReady: Integer;
    /// <summary>1: Die Nachrichtenschleife nach dem Laden ist frei.</summary>
    FStarted: Integer;
  protected
    procedure Execute; override;
    procedure TerminatedSet; override;
  public
    constructor Create(AWindow: HWND; ADiagnose: Boolean);
    destructor Destroy; override;
  end;

  /// <summary>Fenster des Hauptthreads, das die Nachrichten des Wächters beantwortet.</summary>
  TPingWindow = class
  private
    FHandle: HWND;
    /// <summary>nil, sobald Stop den Thread abgibt.</summary>
    FThread: TWatchThread;
    procedure WndProc(var AMessage: TMessage);
  public
    constructor Create;
    destructor Destroy; override;
    property Handle: HWND read FHandle;
  end;

var
  PingWindow: TPingWindow;
  Watcher: TWatchThread;
  DiagnoseOn: Boolean;

{ TWatchThread }

constructor TWatchThread.Create(AWindow: HWND; ADiagnose: Boolean);
begin
  FWindow := AWindow;
  FWake := TEvent.Create(nil, False, False, '');
  FTracker := TDpccHangTracker.Create(ADiagnose);
  FPong := 0;
  FPongAt := 0;
  FReady := 0;
  FStarted := 0;
  inherited Create(True);
  FreeOnTerminate := False;
end;

destructor TWatchThread.Destroy;
begin
  inherited Destroy;
  FTracker.Free;
  FWake.Free;
end;

procedure TWatchThread.TerminatedSet;
begin
  inherited;
  FWake.SetEvent;
end;

procedure TWatchThread.Execute;
var
  mSeq: Integer;
  mAwaiting: Boolean;
  mNow: Int64;
begin
  NameThreadForDebugging('dpcc.Watchdog');
  mSeq := 0;
  mAwaiting := False;
  try
    while not Terminated and not TDpccShutdown.Signalled do
    begin
      FWake.WaitFor(cPeriodMs);
      if Terminated or TDpccShutdown.Signalled then
      begin
        Break;
      end;
      mNow := NowMs;
      FTracker.Tick(mNow);
      FlushSlowLog;
      if AtomicCmpExchange(FStarted, 0, 0) = 0 then
      begin
        Continue;
      end;
      if mAwaiting then
      begin
        if AtomicCmpExchange(FPong, 0, 0) = mSeq then
        begin
          mAwaiting := False;
          WriteLines(FTracker.Answered(TInterlocked.Read(FPongAt)));
        end
        else if AtomicCmpExchange(FReady, 0, 0) = 1 then
        begin
          // Liest den Aktivitätsstapel ohne Sperre: Der Hauptthread steht vielleicht gerade.
          WriteLines(FTracker.Waiting(mNow, TDpccActivity.Running));
        end;
      end;
      if not mAwaiting then
      begin
        Inc(mSeq);
        if PostMessage(FWindow, cWM_DPCC_PING, WPARAM(mSeq), 0) then
        begin
          FTracker.Sent(mNow);
          mAwaiting := True;
        end;
      end;
    end;
    FlushSlowLog;
  except
    // Der Wächter selbst darf die IDE nie stören (#493).
    on E: Exception do
    begin
      TDpccGuard.Log('Wächter des Hauptthreads beendet: ' + TDpccGuard.ErrorText(E));
    end;
  end;
end;

{ TPingWindow }

constructor TPingWindow.Create;
begin
  inherited Create;
  FHandle := AllocateHWnd(WndProc);
end;

destructor TPingWindow.Destroy;
begin
  FThread := nil;
  if FHandle <> 0 then
  begin
    DeallocateHWnd(FHandle);
    FHandle := 0;
  end;
  inherited;
end;

procedure TPingWindow.WndProc(var AMessage: TMessage);
var
  mThread: TWatchThread;
begin
  try
    case AMessage.Msg of
      cWM_DPCC_PING:
        begin
          // Die Nachrichtenschleife lief: Laufende Scopes standen nicht (modaler Dialog o. ä.).
          TDpccActivity.MessagePumped;
          mThread := FThread;
          if mThread <> nil then
          begin
            AtomicExchange(mThread.FReady, Ord(IdeRunning));
            TInterlocked.Exchange(mThread.FPongAt, NowMs);
            // Zuletzt die Nummer: Der Thread liest danach FPongAt.
            AtomicExchange(mThread.FPong, Integer(AMessage.WParam));
          end;
          // Gleitkomma-Einstellung (FPU1): zwei Lesezugriffe; eine Zeile nur, wenn sich etwas geändert hat.
          TDpccIdeFpuWatch.Check;
        end;
      cWM_DPCC_STARTUP:
        begin
          mThread := FThread;
          if mThread <> nil then
          begin
            AtomicExchange(mThread.FStarted, 1);
          end;
        end;
    else
      AMessage.Result := DefWindowProc(FHandle, AMessage.Msg, AMessage.WParam, AMessage.LParam);
    end;
  except
    on E: Exception do
    begin
      TDpccGuard.Log('Wächter des Hauptthreads, Fenster: ' + TDpccGuard.ErrorText(E));
    end;
  end;
end;

{ TDpccWatchdog }

class procedure TDpccWatchdog.Start;
begin
  if PingWindow <> nil then
  begin
    Exit;
  end;
  // Registry lesen ist kurz; einmal beim Anmelden.
  DiagnoseOn := TDpccCodeInsightPaths.DiagnoseEnabled;
  if DiagnoseOn then
  begin
    TDpccPluginTimings.Enabled := True;
    TDpccQueryTimings.Enabled := True;
  end;
  PingWindow := TPingWindow.Create;
  Watcher := TWatchThread.Create(PingWindow.Handle, DiagnoseOn);
  PingWindow.FThread := Watcher;
  // Erst wenn die Nachrichtenschleife nach dem Laden frei ist, wird gemessen.
  PostMessage(PingWindow.Handle, cWM_DPCC_STARTUP, 0, 0);
  TDpccSlowLog.Enabled := True;
  Watcher.Start;
  TDpccGuard.Log(Format('Wächter des Hauptthreads an: Takt %d ms, Hänger ab %d ms, Dauer ab %d ms, ' +
    'Warten auf den Server ab %d ms; Diagnose: %s', [cPeriodMs, TDpccHangMonitor.cDefaultThresholdMs,
    TDpccSlowLog.cActivityMs, TDpccSlowLog.cWaitMs, BoolToStr(DiagnoseOn, True)]));
  // Gleitkomma-Einstellung beim Start (FPU1), nur lesend; danach prüft das Fenster bei jeder Antwort.
  TDpccIdeFpuWatch.Start;
end;

/// <summary>Diagnosemodus, beim Entladen: die langsamsten Aufrufe, Anfragen und Abfragen ins Diagnoselog.</summary>
procedure WriteSlowest;
var
  mLines: TArray<string>;
  mLine: string;
begin
  mLines := nil;
  if TDpccPluginTimings.Enabled then
  begin
    mLines := TDpccPluginTimings.Shared.SlowestLines(cSlowestCount);
  end;
  if TDpccQueryTimings.Enabled and (TDpccQueryTimings.Shared <> nil) then
  begin
    mLines := mLines + TDpccTimingReport.SlowestLines(TDpccQueryTimings.Shared.Snapshot, cSlowestCount);
  end;
  if mLines = nil then
  begin
    Exit;
  end;
  TDpccCodeInsightPaths.Append('Langsamste Aufrufe dieser Sitzung (dpcc wird entladen):');
  for mLine in mLines do
  begin
    TDpccCodeInsightPaths.Append(mLine);
  end;
end;

class procedure TDpccWatchdog.Stop;
var
  mThread: TWatchThread;
begin
  TDpccSlowLog.Enabled := False;
  mThread := Watcher;
  Watcher := nil;
  // Ab hier schreibt das Fenster nicht mehr in den Thread (beide im Hauptthread, keine Überschneidung).
  if PingWindow <> nil then
  begin
    PingWindow.FThread := nil;
  end;
  try
    if mThread <> nil then
    begin
      mThread.Terminate;
      if TDpccShutdown.WaitForThreads([TThread(mThread)], TDpccShutdown.cStopMs) then
      begin
        WriteLines(mThread.FTracker.Summary);
        mThread.Free;
      end
      else
      begin
        TDpccGuard.Log('Wächter des Hauptthreads endet nicht; er gibt sich bei Rückkehr selbst frei');
        mThread.FreeOnTerminate := True;
      end;
    end;
    // Was nach dem letzten Takt kam.
    FlushSlowLog;
    if DiagnoseOn then
    begin
      WriteSlowest;
    end;
  finally
    if DiagnoseOn then
    begin
      TDpccPluginTimings.Enabled := False;
      TDpccQueryTimings.Enabled := False;
    end;
    DiagnoseOn := False;
    // Gleitkomma-Einstellung (FPU1): ab hier prüft das Fenster nichts mehr; neu geladen beginnt es von vorn.
    TDpccIdeFpuWatch.Stop;
    // Nach dem Thread: Eine späte Nachricht an ein freigegebenes Fenster scheitert nur (PostMessage).
    FreeAndNil(PingWindow);
  end;
end;

end.
