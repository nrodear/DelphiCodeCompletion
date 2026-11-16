unit Shell.Platform;

// Plattformadapter des Servers an einer Stelle (#1109): Unter Windows die
// Units aus dpcc.Windows, unter Linux (Free Pascal, Tools/Linux) die aus
// dpcc.Linux. Die übrigen Shell-Units binden nur diese Unit ein und kennen
// keine Plattform. Typen mit gleicher Form heißen auf beiden Plattformen
// gleich; was es nur unter einer Plattform gibt, kapselt TShellPlatform.
// Konsolen-Streams, den Wächter des Editor-Prozesses und unter Windows die Stacktraces (TStackTrace.Install) brauchte
// nur der eigene Server-Prozess; sie entfallen seit S1. Im IDE-Prozess liefert Exception.StackTrace, was die IDE
// selbst eingerichtet hat.

interface

uses
  System.SysUtils,
  dpcc.Common.Editing.Colors,
  dpcc.Common.Logging.Contract,
{$IFDEF MSWINDOWS}
  dpcc.Windows.Process.Instances,
  dpcc.Windows.Documents.FileWatcher,
  dpcc.Windows.Compiler.Adapters.ProcessRunner,
  dpcc.Windows.Projects.DelphiInstallation,
  dpcc.Windows.Diagnostics.DebugOutput,
  dpcc.Windows.Diagnostics.ProcessInfo;
{$ELSE}
  dpcc.Linux.Process.Instances,
  dpcc.Linux.Documents.FileWatcher,
  dpcc.Linux.Compiler.Adapters.ProcessRunner,
  dpcc.Linux.Projects.DelphiInstallation,
  dpcc.Linux.Diagnostics.DebugOutput,
  dpcc.Linux.Diagnostics.StackTrace,
  dpcc.Linux.Diagnostics.ProcessInfo;
{$ENDIF}

type
{$IFDEF MSWINDOWS}
  TProcessInstances = dpcc.Windows.Process.Instances.TProcessInstances;
  TFileWatcherChanged = dpcc.Windows.Documents.FileWatcher.TFileWatcherChanged;
  TFileWatcher = dpcc.Windows.Documents.FileWatcher.TFileWatcher;
  TProcessRunner = dpcc.Windows.Compiler.Adapters.ProcessRunner.TProcessRunner;
  TDelphiInstallation = dpcc.Windows.Projects.DelphiInstallation.TDelphiInstallation;
  TDebugOutput = dpcc.Windows.Diagnostics.DebugOutput.TDebugOutput;
  TProcessInfo = dpcc.Windows.Diagnostics.ProcessInfo.TProcessInfo;
{$ELSE}
  TProcessInstances = dpcc.Linux.Process.Instances.TProcessInstances;
  TFileWatcherChanged = dpcc.Linux.Documents.FileWatcher.TFileWatcherChanged;
  TFileWatcher = dpcc.Linux.Documents.FileWatcher.TFileWatcher;
  TProcessRunner = dpcc.Linux.Compiler.Adapters.ProcessRunner.TProcessRunner;
  TDelphiInstallation = dpcc.Linux.Projects.DelphiInstallation.TDelphiInstallation;
  TDebugOutput = dpcc.Linux.Diagnostics.DebugOutput.TDebugOutput;
  TStackTrace = dpcc.Linux.Diagnostics.StackTrace.TStackTrace;
  TProcessInfo = dpcc.Linux.Diagnostics.ProcessInfo.TProcessInfo;
{$ENDIF}

  TShellPlatform = record
  public
    /// <summary>Pfad in der Schreibweise des Dateisystems (Windows: echte Groß- und Kleinschreibung, langer
    /// Name; Linux: ohne symbolische Verweise); unverändert, wenn es ihn nicht gibt.</summary>
    class function CanonicalizePath(const APath: string): string; static;
    /// <summary>Nummer des eigenen Prozesses.</summary>
    class function CurrentProcessId: Cardinal; static;
    /// <summary>Schutz, den nur eine Plattform braucht: unter Windows die Schutzseite nach einem
    /// Stapelüberlauf (#1094) und Lesen mit FILE_SHARE_DELETE. Linux ersetzt geöffnete Dateien
    /// ohnehin und meldet einen Stapelüberlauf als Signal; dort tut Install nichts.</summary>
    class procedure InstallGuards; static;
    /// <summary>Nimmt InstallGuards zurück (In-Process-Modus, Schritt 2b: beim Beenden des Servers im IDE-Prozess).
    /// Beide Haken wirken nur auf dpcc.Common (TStackGuard.Restore, TFileEncoding.Reader), nicht auf die RTL.
    /// </summary>
    class procedure UninstallGuards; static;
    /// <summary>Senke für Debug-Ausgaben an den Debugger (Windows: OutputDebugString); nil unter Linux, wo
    /// stderr schon das Protokoll des Servers trägt.</summary>
    class function DebugLogSink: ILogSink; static;
    /// <summary>Aufrufkette der Exception AError bis zum raise.</summary>
    class function StackTraceOf(AError: Exception): string; static;
    /// <summary>Benennt ASource in ATarget um und ersetzt ein vorhandenes ATarget in einem Schritt.</summary>
    class function MoveReplacing(const ASource, ATarget: string): Boolean; static;
    // Prozessläufer für git und svn (CreateVcsRunner) seit Schritt 2b in Shell.Platform.Vcs: Er zieht Units des
    // Plugins (dpcc.Core.VersionControl.*), die nicht ins Package dpcc.Server gehören.
  end;

/// <summary>Systemfarbe AIndex (GetSysColor) für Farbangaben im Quelltext; unter Linux keine.</summary>
function PlatformSystemColor(AIndex: Integer; out AColor: TRgbColor): Boolean;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
  dpcc.Windows.Documents.PathCanonicalizer,
  dpcc.Windows.Documents.SharedRead,
  dpcc.Windows.Diagnostics.StackGuard,
  dpcc.Windows.Diagnostics.Adapters.DebugOutputSink,
  dpcc.Windows.Editing.SystemColors;
{$ELSE}
  BaseUnix,
  dpcc.Linux.Documents.PathCanonicalizer;
{$ENDIF}

function PlatformSystemColor(AIndex: Integer; out AColor: TRgbColor): Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := WindowsSystemColor(AIndex, AColor);
{$ELSE}
  AColor := Default(TRgbColor);
  Result := False;
{$ENDIF}
end;

{ TShellPlatform }

class function TShellPlatform.CanonicalizePath(const APath: string): string;
begin
{$IFDEF MSWINDOWS}
  Result := TWindowsPathCanonicalizer.Canonicalize(APath);
{$ELSE}
  Result := TLinuxPathCanonicalizer.Canonicalize(APath);
{$ENDIF}
end;

class function TShellPlatform.CurrentProcessId: Cardinal;
begin
{$IFDEF MSWINDOWS}
  Result := GetCurrentProcessId;
{$ELSE}
  Result := Cardinal(FpGetpid);
{$ENDIF}
end;

class procedure TShellPlatform.InstallGuards;
begin
{$IFDEF MSWINDOWS}
  // Ohne neue Schutzseite beendet Windows den Prozess beim nächsten Überlauf (#1094).
  TWindowsStackGuard.Install;
  // Lesen teilt auch Löschen, damit Plugin und zweiter Server Dateien atomar ersetzen können.
  TWindowsSharedRead.Install;
{$ENDIF}
end;

class procedure TShellPlatform.UninstallGuards;
begin
{$IFDEF MSWINDOWS}
  TWindowsSharedRead.Uninstall;
  TWindowsStackGuard.Uninstall;
{$ENDIF}
end;

class function TShellPlatform.DebugLogSink: ILogSink;
begin
{$IFDEF MSWINDOWS}
  Result := TDebugOutputLogSink.Create;
{$ELSE}
  Result := nil;
{$ENDIF}
end;

class function TShellPlatform.StackTraceOf(AError: Exception): string;
begin
{$IFDEF MSWINDOWS}
  Result := AError.StackTrace;
{$ELSE}
  Result := TStackTrace.OfException(AError);
{$ENDIF}
end;

class function TShellPlatform.MoveReplacing(const ASource, ATarget: string): Boolean;
begin
{$IFDEF MSWINDOWS}
  Result := MoveFileEx(PChar(ASource), PChar(ATarget), MOVEFILE_REPLACE_EXISTING);
{$ELSE}
  // rename(2) ersetzt ein vorhandenes Ziel atomar.
  Result := FpRename(UTF8String(ASource), UTF8String(ATarget)) = 0;
{$ENDIF}
end;

end.
