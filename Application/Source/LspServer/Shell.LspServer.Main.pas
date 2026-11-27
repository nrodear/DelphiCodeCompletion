unit Shell.LspServer.Main;

// Host-Rolle Shell, nur in dpcc.LspServer.exe: Programmstart. Befehlszeile und Ablage (Shell.LspServer.Options),
// Protokoll in eine Datei (Shell.LspServer.FileLog), stdin/stdout (Shell.LspServer.StdStreams), Server
// (Shell.LspServer.Host). stdout gehört ausschließlich dem Protokoll.
// Ende: exit (auch als Anfrage), Ende der Eingabe oder Ende des Client-Prozesses (processId aus initialize). Die IDE
// beendet den Prozess nach shutdown ohnehin hart; der Abbau der Wurzel darf deshalb höchstens cTeardownMs dauern,
// danach endet der Prozess ohne weiteres Warten. Index-Caches schreibt der Server über eine Zwischendatei mit
// Umbenennen, ein hartes Ende lässt also keinen halben Cache zurück.

interface

type
  TLspServerMain = class
  public const
    cTeardownMs = 5000;
    cLogMaxAgeDays = 14;
  public
    /// <summary>Führt den Server aus und liefert den Exit-Code.</summary>
    class function Run: Integer; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  dpcc.Common.Logging.Contract,
  dpcc.Common.Logging.Providers.Logger,
  dpcc.Common.Lsp.PublishedMembers,
  dpcc.Common.Product.Version,
  dpcc.Common.Index.Adapters.CacheDirectory,
  dpcc.Text.LogMarks,
  Shell.Platform,
  Shell.LspServer.Options,
  Shell.LspServer.FileLog,
  Shell.LspServer.StdStreams,
  Shell.LspServer.Host;

/// <summary>Beendet den Prozess, sobald der Client-Prozess AProcessId endet (die IDE schließt die Pipe nicht
/// immer).</summary>
procedure WatchClient(AProcessId: Cardinal; const ALogger: ILogger);
var
  mHandle: THandle;
  mLogger: ILogger;
  mThread: TThread;
begin
  mHandle := OpenProcess(SYNCHRONIZE, False, AProcessId);
  if mHandle = 0 then
  begin
    ALogger.Warning(Format('Client-Prozess %d nicht beobachtbar (Fehler %d)', [AProcessId, GetLastError]));
    Exit;
  end;
  mLogger := ALogger;
  mThread := TThread.CreateAnonymousThread(
    procedure
    begin
      TThread.NameThreadForDebugging('dpcc.LspServer (Client-Wächter)');
      if WaitForSingleObject(mHandle, INFINITE) = WAIT_OBJECT_0 then
      begin
        mLogger.Info(Format('Client-Prozess %d beendet; Server endet', [AProcessId]));
        ExitProcess(1);
      end;
    end);
  mThread.FreeOnTerminate := True;
  mThread.Start;
end;

/// <summary>Beendet den Prozess nach AMs mit AExitCode, falls der Abbau hängt.</summary>
procedure LimitTeardown(AExitCode: Integer; AMs: Cardinal);
var
  mThread: TThread;
begin
  mThread := TThread.CreateAnonymousThread(
    procedure
    begin
      TThread.Sleep(AMs);
      ExitProcess(Cardinal(AExitCode));
    end);
  mThread.FreeOnTerminate := True;
  mThread.Start;
end;

class function TLspServerMain.Run: Integer;
var
  mOptions: TLspServerOptions;
  mLoggerImpl: TLogger;
  mLogger: ILogger;
  mSink: ILogSink;
  mHost: TLspServerHost;
  mInput, mOutput: TStream;
  mLogFile: string;
begin
  mOptions := TLspServerOptions.FromProcess;
  if mOptions.ShowHelp then
  begin
    TLspStdStreams.WriteOutput(TLspServerOptions.HelpText);
    Exit(0);
  end;
  if mOptions.ShowVersion then
  begin
    TLspStdStreams.WriteOutput('dpcc.LspServer ' + TProductVersion.cVersion);
    Exit(0);
  end;
  // Eigene Ablage für alle Teile des Servers (Index, Projektwahl, Diagnoselog), nie die des Plugins.
  Winapi.Windows.SetEnvironmentVariable(PChar(TIndexCacheDirectory.cRootVariable), PChar(mOptions.CacheRoot));
  mLoggerImpl := TLogger.Create;
  mLogger := mLoggerImpl;
  mLogFile := '';
  try
    if not mOptions.NoLog then
    begin
      try
        TLspFileLogSink.RemoveOld(mOptions.LogFolder, cLogMaxAgeDays);
        mLogFile := TLspFileLogSink.FileFor(mOptions.LogFolder, GetCurrentProcessId);
        mSink := TLspFileLogSink.Create(mLogFile);
        mLoggerImpl.AddSink(mSink, mOptions.LogLevel);
      except
        // Ohne beschreibbare Ablage läuft der Server ohne Protokoll.
        on Exception do
          mLogFile := '';
      end;
    end;
    mSink := TShellPlatform.DebugLogSink;
    if mSink <> nil then
    begin
      mLoggerImpl.AddSink(mSink, TLogLevel.Debug);
    end;
    mLogger.Info(Format('dpcc.LspServer %s (%d Bit) gestartet, Prozess %d, Ablage %s, %d Parameter',
      [TProductVersion.cVersion, SizeOf(Pointer) * 8, GetCurrentProcessId, TLogMarks.Path(mOptions.CacheRoot),
      ParamCount]));
    // Schutzseite nach Stapelüberlauf und Lesen mit FILE_SHARE_DELETE; Cache der published-Mitglieder (Hover auf
    // VCL-Klassen kostet sonst jedes Mal rund 1 s).
    TShellPlatform.InstallGuards;
    TPublishedMembers.UseCache(True);
    mInput := TLspStdStreams.CreateInput;
    try
      mOutput := TLspStdStreams.ReserveOutputForProtocol;
    except
      mInput.Free;
      raise;
    end;
    mHost := TLspServerHost.Create(mInput, mOutput, True, mLogger);
    try
      mHost.OnClientProcess :=
        procedure(AProcessId: Cardinal)
        begin
          WatchClient(AProcessId, mLogger);
        end;
      Result := mHost.Run;
      mLogger.Info(Format('Verbindung zu Ende, Exit-Code %d, %d Nachrichten an die IDE verworfen',
        [Result, mHost.Dialect.Dropped]));
      LimitTeardown(Result, cTeardownMs);
    finally
      mHost.Free;
    end;
    TLspServerHost.ReleaseProcessState;
    mLogger.Info('Beendet');
  except
    on E: Exception do
    begin
      mLogger.Error(Format('Server abgebrochen: %s: %s%s%s', [E.ClassName, TLogMarks.Text(E.Message), sLineBreak,
        TShellPlatform.StackTraceOf(E)]));
      Result := 1;
    end;
  end;
end;

end.
