unit dpcc.IDE.Foundation.FpuWatch;

// Gleitkomma-Einstellung der IDE im dpcc.log (FPU1), nur lesend: dpcc setzt weder Default8087CW noch das Steuerwort
// eines Threads. Hintergrund und Texte in dpcc.Core.Diagnostics.FpuState.
// - Start (beim Anmelden, im Hauptthread, aus TDpccWatchdog.Start nach der Zeile „Wächter des Hauptthreads an …“):
//   eine Zeile mit System.Default8087CW (Vorgabe der gemeinsamen RTL für den Prozess) und Get8087CW (Steuerwort des
//   Hauptthreads), dazu DefaultMXCSR und GetMXCSR als Hex.
// - Check (im Hauptthread, bei jeder Antwort des Fensters des Wächters auf seine Nachricht, also etwa alle 50 ms,
//   solange dpcc angemeldet ist): zwei Lesezugriffe und ein Vergleich. Nur bei Änderung gegenüber dem zuletzt
//   gemeldeten Stand eine Zeile ins dpcc.log, bei eingeschaltetem Ablaufprotokoll (TDpccFlow) auch ins
//   Diagnoseprotokoll; höchstens TDpccFpuState.cMaxReports Meldungen je Sitzung. Geschrieben wird über den
//   Schreib-Thread (TDpccGuard.Log, TDpccCodeInsightPaths.Append): Der Hauptthread wartet nie auf eine Datei.
// - Stop (beim Abmelden, aus TDpccWatchdog.Stop): Zustand zurücksetzen; das Paket kann in derselben Sitzung neu
//   geladen werden.
// - Gelesen wird nur unter x86/x64 (Windows); die Symbole sind in System als platform markiert, die Warnung ist nur um
//   genau diese Zugriffe abgeschaltet.

interface

type
  TDpccIdeFpuWatch = class
  public
    /// <summary>Beim Anmelden, im Hauptthread: Ausgangsstand merken und die Startzeile schreiben.</summary>
    class procedure Start; static;
    /// <summary>Im Hauptthread: beide Werte lesen; nur bei Änderung eine Zeile.</summary>
    class procedure Check; static;
    /// <summary>Beim Abmelden, im Hauptthread: Zustand zurücksetzen.</summary>
    class procedure Stop; static;
  end;

implementation

uses
  System.Classes,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Flow,
  dpcc.Core.Diagnostics.FpuState,
  dpcc.IDE.CodeInsight.Manager.Paths;

var
  // Nur im Hauptthread benutzt (Start, Check, Stop).
  Watch: TDpccFpuWatch;
  // Zeitpunkt von Start (TThread.GetTickCount64) für die Sekunden in der Änderungszeile.
  StartedAt: UInt64;

{$IF (Defined(CPUX86) or Defined(CPUX64)) and Defined(MSWINDOWS)}

/// <summary>Vorgabe des Prozesses: System.Default8087CW der gemeinsamen RTL; nur lesen.</summary>
function ProcessControlWord: Word;
begin
{$WARN SYMBOL_PLATFORM OFF}
  Result := System.Default8087CW;
{$WARN SYMBOL_PLATFORM DEFAULT}
end;

/// <summary>x87-Steuerwort des aufrufenden Threads (hier immer der Hauptthread); nur lesen.</summary>
function ThreadControlWord: Word;
begin
{$WARN SYMBOL_PLATFORM OFF}
  Result := System.Get8087CW;
{$WARN SYMBOL_PLATFORM DEFAULT}
end;

/// <summary>Vorgabe des Prozesses für MXCSR (System.DefaultMXCSR); nur lesen.</summary>
function ProcessMxcsr: Cardinal;
begin
{$WARN SYMBOL_PLATFORM OFF}
  Result := System.DefaultMXCSR;
{$WARN SYMBOL_PLATFORM DEFAULT}
end;

/// <summary>MXCSR des aufrufenden Threads; nur lesen.</summary>
function ThreadMxcsr: Cardinal;
begin
{$WARN SYMBOL_PLATFORM OFF}
  Result := System.GetMXCSR;
{$WARN SYMBOL_PLATFORM DEFAULT}
end;

procedure StartReading;
var
  mDefault, mMain: Word;
begin
  mDefault := ProcessControlWord;
  mMain := ThreadControlWord;
  StartedAt := TThread.GetTickCount64;
  Watch.Reset(mDefault, mMain);
  TDpccGuard.Log(TDpccFpuState.StartLine(mDefault, mMain, ProcessMxcsr, ThreadMxcsr));
end;

procedure CheckReading;
var
  mDefault, mMain: Word;
  mLine: string;
begin
  mDefault := ProcessControlWord;
  mMain := ThreadControlWord;
  if not Watch.Differs(mDefault, mMain) then
  begin
    Exit;
  end;
  mLine := Watch.Take(mDefault, mMain, Int64((TThread.GetTickCount64 - StartedAt) div 1000));
  TDpccGuard.Log(mLine);
  if TDpccFlow.Enabled then
  begin
    TDpccCodeInsightPaths.Append(mLine);
  end;
end;

{$ENDIF}

{ TDpccIdeFpuWatch }

class procedure TDpccIdeFpuWatch.Start;
begin
  try
{$IF (Defined(CPUX86) or Defined(CPUX64)) and Defined(MSWINDOWS)}
    StartReading;
{$ENDIF}
  except
    // Reine Beobachtung: Ein Fehler hier kostet nur die Zeile, nie das Anmelden.
    Watch.Clear;
  end;
end;

class procedure TDpccIdeFpuWatch.Check;
begin
  if not Watch.Active then
  begin
    Exit;
  end;
{$IF (Defined(CPUX86) or Defined(CPUX64)) and Defined(MSWINDOWS)}
  CheckReading;
{$ENDIF}
end;

class procedure TDpccIdeFpuWatch.Stop;
begin
  Watch.Clear;
  StartedAt := 0;
end;

end.
