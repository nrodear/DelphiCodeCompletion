unit dpcc.Core.Diagnostics.Hangs;

// Einfrier-Wächter (#501), Teil ohne Windows und Open Tools API. Den Thread
// mit dem Ping-Fenster stellt dpcc.IDE.Foundation.Watchdog; hier liegt die
// reine Logik (Tests mit einstellbarer Uhr, ohne Thread und Fenster):
// - TDpccActivity: dpcc-Arbeit im Hauptthread meldet sich mit Scope an. Die
//   Namen liegen in einem Stapel fester Größe (TDpccActivityStack): Der
//   Hauptthread kopiert den Namen in einen festen Puffer (kein Speicher, keine
//   Sperre), der Wächter liest den innersten ohne Sperre und ohne Warten
//   (Sequenzzähler; ein zerrissenes Lesen wird verworfen). Scopes aus
//   anderen Threads zählen nicht als Aktivität des Hauptthreads (Ergebnis nil).
//   Jeder Scope misst seine Dauer im Hauptthread; ab cSlowMs (50 ms) geht eine
//   Zeile an TDpccSlowLog, je Name höchstens eine je Minute. Verschachtelt:
//   Der Wächter sieht den innersten Namen, die Dauer gilt je Scope. Arbeit der
//   IDE (IdeWork, aus TDpccGuard.RunIde) ist keine dpcc-Aktivität, und ihre
//   Zeit zählt nicht zur Dauer der umgebenden Scopes. Lief während eines
//   Scopes die Nachrichtenschleife (modaler Dialog, Menü; MessagePumped aus dem
//   Wächter-Fenster), stand der Hauptthread nicht, und es gibt keine Zeile.
//   Während des Starts zählt TimeInto die Dauer jeder äußersten Aktion zu den
//   Startanteilen. Running ergänzt die laufende Funktion
//   aus TDpccGuard.Run, wenn keine Aktion angemeldet ist (#1988).
// - TDpccSlowLog: gedrosselte Zeilen „Hauptthread: <Aktivität>: n ms“ und
//   „Hauptthread wartete n ms auf Server …“ (TLspClient), gesammelt im
//   Speicher; der Wächter-Thread schreibt sie ins dpcc.log, damit der
//   Hauptthread nie auf die Datei wartet. Aus (Vorgabe, Tests) tut es nichts.
// - TDpccHangTracker: Zustand des Wächters je Ping. Bleibt die Antwort ab der
//   Schwelle (250 ms) aus, sofort eine Zeile „Hauptthread hängt seit n ms in
//   <Aktivität>“, mit der Antwort eine Zeile mit der Gesamtdauer
//   (TDpccHangMonitor.Finish). Ohne dpcc-Aktivität nur im Diagnosemodus,
//   dann fürs Diagnoselog. Höchstens 5 Hänger je Minute und Art einzeln; die
//   übrigen zählen und stehen als Summe bei der nächsten Zeile und in der
//   Zusammenfassung beim Entladen. Stand der ganze Prozess (Debugger hält an,
//   Ruhezustand: der Takt des Wächters selbst setzt länger aus), zählt diese
//   Zeit nicht.
// - TDpccHangMonitor: Schwelle, Statistik je Sitzung und Bericht.
// - TDpccStackScan: ordnet Adressen eines rohen Stapelabzugs Modulen zu
//   (Modul+Offset), ohne Symbole; der Bericht zeigt so, ob dpcc beteiligt ist.
//   Angezeigt werden die obersten 24 Rahmen; ob dpcc beteiligt ist, sucht
//   FirstIn über den ganzen Abzug (#1989). Vorher zählte ein Hänger ohne
//   dpcc-Rahmen unter den obersten 24 als „ohne dpcc“, etwa wenn dpcc eine
//   lange Arbeit der IDE aufrief und deren Stapel tiefer war. Der heutige
//   Wächter zieht keinen Stapel mehr ab (kein SuspendThread).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  dpcc.Core.Diagnostics.StartTimes;

type
{$SCOPEDENUMS ON}
  /// <summary>Art eines Eintrags im Aktivitätsstapel: Timed misst die Dauer und meldet sie dem Diagnose-Fenster,
  /// Feature misst nur (TDpccGuard.Run), Named nennt nur den Namen (Warten auf den Server; die Dauer meldet der
  /// Aufrufer), Ide ist Arbeit der IDE (keine dpcc-Aktivität, ihre Zeit zählt nicht zur Dauer der äußeren).</summary>
  TDpccActivityKind = (Timed, Feature, Named, Ide);
{$SCOPEDENUMS OFF}

  /// <summary>Stapel der laufenden Aktivitäten des Hauptthreads, feste Größe. Push und Pop nur aus einem Thread (dem
  /// Hauptthread), Top aus jedem Thread ohne Sperre und ohne Warten.</summary>
  TDpccActivityStack = class
  public const
    cMaxDepth = 32;
    /// <summary>Längere Namen werden gekürzt.</summary>
    cMaxNameLength = 80;
  private type
    TSlot = record
      Kind: TDpccActivityKind;
      NameLength: Integer;
      Chars: array[0..cMaxNameLength - 1] of Char;
      Started: Int64;
      /// <summary>Darin verbrachte Zeit, die nicht zählt (Arbeit der IDE).</summary>
      Excluded: Int64;
      /// <summary>Stand von FPumps beim Eintritt.</summary>
      Pumps: Integer;
    end;
  private
    FClock: TFunc<Int64>;
    FSlots: array[0..cMaxDepth - 1] of TSlot;
    FDepth: Integer;
    /// <summary>Sequenzzähler: ungerade, während der Hauptthread schreibt.</summary>
    FSeq: Integer;
    FPumps: Integer;
  public
    /// <summary>AClock liefert ms (Tests).</summary>
    constructor Create(const AClock: TFunc<Int64>); overload;
    /// <summary>Stoppuhr in ms.</summary>
    constructor Create; overload;
    /// <summary>AName (gekürzt auf cMaxNameLength) als innersten Eintrag; Ergebnis das Zeichen für Pop.</summary>
    function Push(const AName: string; AKind: TDpccActivityKind): Integer;
    /// <summary>Nimmt den Eintrag AToken samt allem darüber. AElapsedMs: Dauer ohne darin verbrachte Arbeit der IDE;
    /// APumped: Die Nachrichtenschleife lief dazwischen (Pumped). False, wenn AToken nicht (mehr) auf dem Stapel liegt
    /// oder über cMaxDepth lag.</summary>
    function Pop(AToken: Integer; out AElapsedMs: Int64; out APumped: Boolean): Boolean;
    /// <summary>Name des innersten Eintrags; '' ohne, bei Arbeit der IDE oder wenn das Lesen mehrfach mit dem
    /// Hauptthread kollidierte. Aus jedem Thread.</summary>
    function Top: string;
    /// <summary>Die Nachrichtenschleife hat eine Nachricht verarbeitet (aus jedem Thread).</summary>
    procedure Pumped;
    /// <summary>Jetzt nach der Uhr in ms.</summary>
    function Clock: Int64;
    property Depth: Integer read FDepth;
  end;

  TDpccActivity = class
  public const
    /// <summary>Name der Aktion des künstlichen Hängers im Protokoll.</summary>
    cHangTestName = 'Watchdog test';
    /// <summary>Dauer des künstlichen Hängers; über der Schwelle des Wächters.</summary>
    cHangTestMs = 1000;
  private class var
    FLock: TCriticalSection;
    FTimes: TDpccStartTimes;
    FStack: TDpccActivityStack;
  private
    /// <summary>Im Hauptthread AName mit AKind auf den Stapel; in anderen Threads nil.</summary>
    class function Enter(const AName: string; AKind: TDpccActivityKind): IInterface; static;
    /// <summary>Äußerste Aktion AName, begonnen bei AStarted (Uhr der Startanteile), ist zu Ende.</summary>
    class procedure Leave(const AName: string; AStarted: Int64); static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Meldet AName an, bis das Ergebnis freigegeben wird (Ende der Routine); misst die Dauer. Nur im
    /// Hauptthread; in anderen Threads nil (zählt nicht als Aktivität des Hauptthreads).</summary>
    class function Scope(const AName: string): IInterface; static;
    /// <summary>Wie Scope für TDpccGuard.Run (Name des Features), ohne Eintrag im Diagnose-Fenster.</summary>
    class function Feature(const AName: string): IInterface; static;
    /// <summary>Nur der Name für den Wächter, ohne eigene Dauerzeile: Der Hauptthread wartet (etwa auf den Server),
    /// die Dauer meldet der Aufrufer selbst.</summary>
    class function Waiting(const AName: string): IInterface; static;
    /// <summary>Arbeit der IDE in einer dpcc-Aktion (TDpccGuard.RunIde): keine dpcc-Aktivität, ihre Zeit zählt nicht
    /// zur Dauer der umgebenden Scopes.</summary>
    class function IdeWork: IInterface; static;
    /// <summary>Ab jetzt die Dauer jeder äußersten Aktion als „Aktion Name“ zu ATimes addieren
    /// (Startanteile); nil beendet das. ATimes gehört dem Aufrufer und darf nach TimeInto(nil) freigegeben werden.
    /// </summary>
    class procedure TimeInto(ATimes: TDpccStartTimes); static;
    /// <summary>Innerste laufende Aktion; '' ohne. Aus jedem Thread, ohne Sperre und ohne Warten.</summary>
    class function Current: string; static;
    /// <summary>Current, sonst die innerste Funktion aus TDpccGuard.Run; für den Einfrier-Wächter.</summary>
    class function Running: string; static;
    /// <summary>Die Nachrichtenschleife des Hauptthreads lief (Wächter-Fenster): Laufende Scopes standen nicht.
    /// </summary>
    class procedure MessagePumped; static;
    /// <summary>Läuft der Aufrufer im Hauptthread?</summary>
    class function IsMainThread: Boolean; static;
    /// <summary>Künstlicher Hänger für den Einfrier-Wächter (#501): blockiert den aufrufenden Thread AMs lang
    /// unter cHangTestName. Aus der Befehlspalette und den Einstellungen, beide nur im Diagnosemodus.</summary>
    class procedure HangTest(AMs: Cardinal); overload; static;
    /// <summary>HangTest mit cHangTestMs.</summary>
    class procedure HangTest; overload; static;
  end;

  /// <summary>Gedrosselte Zeilen je Schlüssel: die erste, danach höchstens eine je Abstand; übergangene Meldungen
  /// zählen mit (Muster TDpccFuse.ProviderSlow). Threadsicher; die Zeit kommt vom Aufrufer (Tests).</summary>
  TDpccLogThrottle = class
  private type
    TEntry = record
      LastMs: Int64;
      Skipped: Integer;
      SkippedMaxMs: Int64;
    end;
  private
    FIntervalMs: Int64;
    FLock: TCriticalSection;
    FEntries: TDictionary<string, TEntry>;
  public
    constructor Create(AIntervalMs: Int64);
    destructor Destroy; override;
    /// <summary>Meldung zu AKey (ohne Groß-/Kleinschreibung) mit dem Wert AValueMs zur Zeit ANowMs: True, wenn eine
    /// Zeile fällig ist. ASkipped und ASkippedMaxMs: seit der letzten Zeile übergangene Meldungen und ihr größter
    /// Wert; nur bei True gesetzt, sonst 0.</summary>
    function Allow(const AKey: string; ANowMs, AValueMs: Int64; out ASkipped: Integer;
      out ASkippedMaxMs: Int64): Boolean;
  end;

  /// <summary>Zeilen des Hauptthreads für dpcc.log: Dauer einer Aktivität, Warten auf den Server. Gesammelt im
  /// Speicher, geschrieben vom Wächter-Thread (Take); je Name höchstens eine Zeile je Minute.</summary>
  TDpccSlowLog = class
  public const
    /// <summary>Ab so vielen ms schreibt eine Aktivität im Hauptthread eine Zeile.</summary>
    cActivityMs = 50;
    /// <summary>Ab so vielen ms Warten des Hauptthreads auf den Server eine Zeile.</summary>
    cWaitMs = 100;
    cIntervalMs = 60 * 1000;
    /// <summary>Mehr wartende Zeilen nimmt das Sammeln nicht an (zählt sie nur).</summary>
    cMaxPending = 200;
  private class var
    FEnabled: Boolean;
    FLock: TCriticalSection;
    FThrottle: TDpccLogThrottle;
    FPending: TList<string>;
    FDropped: Integer;
    FClock: TFunc<Int64>;
    class procedure Add(const AKey, ALine: string; AMs: Int64); static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>An nur in der IDE (Wächter läuft); aus (Vorgabe) tun NoteActivity und NoteWait nichts.</summary>
    class property Enabled: Boolean read FEnabled write FEnabled;
    /// <summary>Aktivität AName lief AMs im Hauptthread; ab cActivityMs eine Zeile.</summary>
    class procedure NoteActivity(const AName: string; AMs: Int64); static;
    /// <summary>Der Hauptthread wartete AMs auf die Anfrage AMethod mit Ausgang AOutcome; ab cWaitMs eine Zeile.
    /// </summary>
    class procedure NoteWait(const AMethod: string; AMs: Int64; const AOutcome: string); static;
    /// <summary>Gesammelte Zeilen abholen (und vergessen); aus jedem Thread.</summary>
    class function Take: TArray<string>; static;
    /// <summary>„Hauptthread: AName: AMs ms“.</summary>
    class function ActivityLine(const AName: string; AMs: Int64): string; static;
    /// <summary>„Hauptthread wartete AMs ms auf Server AMethod: AOutcome“.</summary>
    class function WaitLine(const AMethod: string; AMs: Int64; const AOutcome: string): string; static;
    /// <summary>„ (dazu n weitere seit der letzten Meldung, längste m ms)“; '' ohne.</summary>
    class function SkippedText(ASkipped: Integer; AMaxMs: Int64): string; static;
  end;

  TDpccModuleRange = record
    Name: string;
    Base: UInt64;
    Size: UInt64;
  end;

  TDpccStackScan = class
  public
    /// <summary>Adressen, die in einem Modul liegen, als "Modul+Offset" (hex); höchstens AMax,
    /// gleiche Einträge direkt hintereinander nur einmal.</summary>
    class function Frames(const AAddresses: TArray<UInt64>; const AModules: TArray<TDpccModuleRange>;
      AMax: Integer): TArray<string>; overload; static;
    /// <summary>Wie oben mit AMax = 24.</summary>
    class function Frames(const AAddresses: TArray<UInt64>;
      const AModules: TArray<TDpccModuleRange>): TArray<string>; overload; static;
    /// <summary>Erste Adresse (von oben) in einem Modul, dessen Name mit APrefix beginnt, als "Modul+Offset";
    /// '' ohne. Durchsucht alle Adressen.</summary>
    class function FirstIn(const AAddresses: TArray<UInt64>; const AModules: TArray<TDpccModuleRange>;
      const APrefix: string): string; static;
  end;

  TDpccHang = record
    DurationMs: Int64;
    At: TDateTime;
    Activity: string;
    Window: string;
    Frames: TArray<string>;
    /// <summary>Oberster Rahmen aus einem dpcc-Modul im ganzen Abzug, auch unterhalb von Frames; '' ohne.
    /// </summary>
    DpccFrame: string;
    /// <summary>Code-Insight-Kompilierungen bisher (#527).</summary>
    CodeInsightCount: Integer;
    CodeInsightMs: Int64;
  end;

  TDpccHangMonitor = class
  public const
    /// <summary>Ab so vielen ms ohne Antwort gilt ein Stillstand des Hauptthreads als Hänger (vorher 500).
    /// </summary>
    cDefaultThresholdMs = 250;
  private
    FThresholdMs: Integer;
    FCount: Integer;
    FWithDpcc: Integer;
    FLongestMs: Int64;
    FLongestDpccMs: Int64;
    FLongestOtherMs: Int64;
  public
    constructor Create(AThresholdMs: Integer); overload;
    /// <summary>Wie oben mit AThresholdMs = cDefaultThresholdMs.</summary>
    constructor Create; overload;
    /// <summary>Wertet einen beendeten Hänger aus: '' unter der Schwelle, sonst die Zeile „Hauptthread hing n ms in
    /// Aktivität“ bzw. „… ohne dpcc-Aktivität“ (Rahmen eines Stapelabzugs, falls vorhanden, als Folgezeilen); zählt
    /// mit.</summary>
    function Finish(const AHang: TDpccHang): string;
    /// <summary>Statistik der Sitzung in einer Zeile.</summary>
    function Summary: string;
    /// <summary>dpcc beteiligt: laufende Aktion oder ein Rahmen aus einem dpcc-Modul.</summary>
    class function InvolvesDpcc(const AHang: TDpccHang): Boolean; static;
    property ThresholdMs: Integer read FThresholdMs write FThresholdMs;
    property Count: Integer read FCount;
    property WithDpcc: Integer read FWithDpcc;
    property LongestMs: Int64 read FLongestMs;
    property LongestDpccMs: Int64 read FLongestDpccMs;
    property LongestOtherMs: Int64 read FLongestOtherMs;
  end;

  /// <summary>Höchstens Max Zeilen je Fenster von WindowMs (festes Fenster ab der ersten Zeile).</summary>
  TDpccLineBudget = record
  private
    FMax: Integer;
    FWindowMs: Int64;
    FWindowStart: Int64;
    FUsed: Integer;
    FOpen: Boolean;
  public
    procedure Init(AMax: Integer; AWindowMs: Int64);
    /// <summary>True, wenn zur Zeit ANowMs noch eine Zeile ins Fenster passt (und zählt sie).</summary>
    function Allow(ANowMs: Int64): Boolean;
  end;

  /// <summary>Zeile des Wächters.</summary>
  TDpccHangLine = record
    Text: string;
    /// <summary>True: Hänger ohne dpcc-Aktivität, gehört ins Diagnoselog; sonst dpcc.log.</summary>
    Diagnostic: Boolean;
  end;

  /// <summary>Zustand des Wächters, nur aus seinem Thread (Summary nach dessen Ende). Zeiten in ms von außen.
  /// Ablauf je Takt: Tick, dann bei offener Nachricht Waiting oder (beantwortet) Answered, danach Sent für die
  /// nächste.</summary>
  TDpccHangTracker = class
  public const
    /// <summary>Höchstens so viele Hänger je Art und Minute einzeln im Protokoll.</summary>
    cMaxPerMinute = 5;
    cMinuteMs = 60 * 1000;
    /// <summary>Setzt der Takt des Wächters selbst länger aus, stand der ganze Prozess (Debugger hält die IDE an,
    /// Ruhezustand); diese Zeit zählt nicht als Hänger.</summary>
    cPauseMs = 1000;
  private
    FMonitor: TDpccHangMonitor;
    FDiagnose: Boolean;
    FNow: TFunc<TDateTime>;
    FLastTick: Int64;
    FSentAt: Int64;
    FHanging: Boolean;
    FHangStart: Int64;
    FActivity: string;
    FDpccDecided: Boolean;
    FDpccLogged: Boolean;
    FOtherDecided: Boolean;
    FOtherLogged: Boolean;
    FDpccBudget: TDpccLineBudget;
    FOtherBudget: TDpccLineBudget;
    // Nicht einzeln protokolliert: seit der letzten Zeile (Anzahl, ms) und in der Sitzung.
    FDpccSkipped: Integer;
    FDpccSkippedMs: Int64;
    FDpccSkippedTotal: Integer;
    FOtherSkipped: Integer;
    FOtherSkippedMs: Int64;
    FOtherSkippedTotal: Integer;
    FPausedMs: Int64;
    /// <summary>„ (dazu n Hänger … zusammen m ms)“ für ASkipped/ASkippedMs, die danach auf 0 stehen.</summary>
    class function Suffix(var ASkipped: Integer; var ASkippedMs: Int64): string; static;
    class function Line(const AText: string; ADiagnostic: Boolean): TDpccHangLine; static;
  public
    /// <summary>ADiagnose: Hänger ohne dpcc-Aktivität fürs Diagnoselog melden; ANow: Uhrzeit (Tests).</summary>
    constructor Create(ADiagnose: Boolean; const ANow: TFunc<TDateTime>); overload;
    constructor Create(ADiagnose: Boolean); overload;
    destructor Destroy; override;
    /// <summary>Jeder Takt des Wächters zuerst: Lag der letzte Takt mehr als cPauseMs zurück, verschiebt sich der
    /// Beginn des laufenden Wartens um die Lücke.</summary>
    procedure Tick(ANowMs: Int64);
    /// <summary>Nachricht an den Hauptthread geschickt.</summary>
    procedure Sent(ANowMs: Int64);
    /// <summary>Die Nachricht ist zur Zeit ANowMs noch nicht beantwortet; AActivity ist die laufende
    /// dpcc-Aktivität ('' ohne). Ergebnis: höchstens eine Zeile beim Überschreiten der Schwelle.</summary>
    function Waiting(ANowMs: Int64; const AActivity: string): TArray<TDpccHangLine>;
    /// <summary>Die Nachricht wurde zur Zeit AAnsweredMs beantwortet. Ergebnis: die Zeile mit der Gesamtdauer, wenn
    /// der Hänger gemeldet war.</summary>
    function Answered(AAnsweredMs: Int64): TArray<TDpccHangLine>;
    /// <summary>Zusammenfassung beim Entladen: eine Zeile, wenn es Hänger mit dpcc-Aktivität gab, im Diagnosemodus
    /// eine fürs Diagnoselog, wenn es andere gab.</summary>
    function Summary: TArray<TDpccHangLine>;
    property Monitor: TDpccHangMonitor read FMonitor;
    property Hanging: Boolean read FHanging;
    /// <summary>Nicht einzeln protokollierte Hänger mit bzw. ohne dpcc-Aktivität in der Sitzung.</summary>
    property DpccSkippedTotal: Integer read FDpccSkippedTotal;
    property OtherSkippedTotal: Integer read FOtherSkippedTotal;
    /// <summary>Summe der Lücken, in denen der Prozess stand (Tick).</summary>
    property PausedMs: Int64 read FPausedMs;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.PluginTimings;

/// <summary>Stetige Uhr in ms.</summary>
function StopwatchMs: Int64;
begin
  Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
end;

function LocalNow: TDateTime;
begin
  Result := Now;
end;

{ TDpccActivityStack }

constructor TDpccActivityStack.Create(const AClock: TFunc<Int64>);
begin
  inherited Create;
  FClock := AClock;
end;

constructor TDpccActivityStack.Create;
begin
  Create(StopwatchMs);
end;

function TDpccActivityStack.Clock: Int64;
begin
  Result := FClock();
end;

function TDpccActivityStack.Push(const AName: string; AKind: TDpccActivityKind): Integer;
var
  mIndex, mLength: Integer;
  mStarted: Int64;
begin
  mIndex := FDepth;
  Result := mIndex + 1;
  mStarted := FClock();
  mLength := Length(AName);
  if mLength > cMaxNameLength then
  begin
    mLength := cMaxNameLength;
  end;
  // Ungerade: Ein Leser, der jetzt liest, verwirft sein Ergebnis.
  AtomicIncrement(FSeq);
  if mIndex < cMaxDepth then
  begin
    FSlots[mIndex].Kind := AKind;
    FSlots[mIndex].NameLength := mLength;
    if mLength > 0 then
    begin
      Move(PChar(AName)^, FSlots[mIndex].Chars[0], mLength * SizeOf(Char));
    end;
    FSlots[mIndex].Started := mStarted;
    FSlots[mIndex].Excluded := 0;
    FSlots[mIndex].Pumps := FPumps;
  end;
  FDepth := Result;
  AtomicIncrement(FSeq);
end;

function TDpccActivityStack.Pop(AToken: Integer; out AElapsedMs: Int64; out APumped: Boolean): Boolean;
var
  mIndex: Integer;
  mElapsed, mExcluded: Int64;
begin
  AElapsedMs := 0;
  APumped := False;
  // Schon abgebaut (ein äußerer Eintrag endete vorher) oder kein Zeichen: nichts zu tun.
  if (AToken <= 0) or (AToken > FDepth) then
  begin
    Exit(False);
  end;
  mIndex := AToken - 1;
  Result := mIndex < cMaxDepth;
  if Result then
  begin
    mElapsed := FClock() - FSlots[mIndex].Started;
    if mElapsed < 0 then
    begin
      mElapsed := 0;
    end;
    mExcluded := FSlots[mIndex].Excluded;
    APumped := FPumps <> FSlots[mIndex].Pumps;
    AElapsedMs := mElapsed - mExcluded;
    if AElapsedMs < 0 then
    begin
      AElapsedMs := 0;
    end;
    // Zeit der IDE zählt auch für alle umgebenden Einträge nicht.
    if (mIndex > 0) and (mIndex - 1 < cMaxDepth) then
    begin
      if FSlots[mIndex].Kind = TDpccActivityKind.Ide then
      begin
        Inc(FSlots[mIndex - 1].Excluded, mElapsed);
      end
      else
      begin
        Inc(FSlots[mIndex - 1].Excluded, mExcluded);
      end;
    end;
  end;
  AtomicIncrement(FSeq);
  FDepth := mIndex;
  AtomicIncrement(FSeq);
end;

function TDpccActivityStack.Top: string;
const
  cTries = 8;
var
  mTry, mBefore, mDepth, mLength: Integer;
  mKind: TDpccActivityKind;
begin
  for mTry := 1 to cTries do
  begin
    Result := '';
    // AtomicCmpExchange(x, 0, 0) liest mit Speicherbarriere, ohne den Wert zu ändern.
    mBefore := AtomicCmpExchange(FSeq, 0, 0);
    if Odd(mBefore) then
    begin
      Continue;
    end;
    mDepth := FDepth;
    if mDepth > cMaxDepth then
    begin
      mDepth := cMaxDepth;
    end;
    if mDepth > 0 then
    begin
      mKind := FSlots[mDepth - 1].Kind;
      mLength := FSlots[mDepth - 1].NameLength;
      if (mKind <> TDpccActivityKind.Ide) and (mLength > 0) and (mLength <= cMaxNameLength) then
      begin
        SetString(Result, PChar(@FSlots[mDepth - 1].Chars[0]), mLength);
      end;
    end;
    if AtomicCmpExchange(FSeq, 0, 0) = mBefore then
    begin
      Exit;
    end;
  end;
  Result := '';
end;

procedure TDpccActivityStack.Pumped;
begin
  AtomicIncrement(FPumps);
end;

type
  TActivityScope = class(TInterfacedObject)
  private
    FName: string;
    FKind: TDpccActivityKind;
    FToken: Integer;
    /// <summary>Äußerste Aktion während der Startanteile (TimeInto).</summary>
    FTimed: Boolean;
    FStarted: Int64;
    // Diagnose-Fenster, Reiter „Hauptthread“: Dauer der Aktion als Zeile der langsamen Aufrufe.
    FPluginStarted: Int64;
  public
    constructor Create(const AName: string; AKind: TDpccActivityKind; AToken: Integer; ATimed: Boolean;
      AStarted: Int64);
    destructor Destroy; override;
  end;

constructor TActivityScope.Create(const AName: string; AKind: TDpccActivityKind; AToken: Integer; ATimed: Boolean;
  AStarted: Int64);
begin
  inherited Create;
  FName := AName;
  FKind := AKind;
  FToken := AToken;
  FTimed := ATimed;
  FStarted := AStarted;
  FPluginStarted := 0;
  if FKind = TDpccActivityKind.Timed then
  begin
    FPluginStarted := TDpccPluginTimings.StampIfEnabled;
  end;
end;

destructor TActivityScope.Destroy;
var
  mStack: TDpccActivityStack;
  mMs: Int64;
  mPumped: Boolean;
begin
  try
    if FKind = TDpccActivityKind.Timed then
    begin
      TDpccPluginTimings.NoteActivity(FName, FPluginStarted);
    end;
    mStack := TDpccActivity.FStack;
    // Lief dazwischen die Nachrichtenschleife (modaler Dialog), stand der Hauptthread nicht: keine Zeile.
    if (mStack <> nil) and mStack.Pop(FToken, mMs, mPumped) and
      (FKind in [TDpccActivityKind.Timed, TDpccActivityKind.Feature]) and not mPumped then
    begin
      TDpccSlowLog.NoteActivity(FName, mMs);
    end;
    if FTimed then
    begin
      TDpccActivity.Leave(FName, FStarted);
    end;
  except
    // Die Freigabe eines Scopes darf nie eine Ausnahme in die Routine des Aufrufers tragen.
  end;
  inherited;
end;

{ TDpccActivity }

class constructor TDpccActivity.Create;
begin
  FLock := TCriticalSection.Create;
  FStack := TDpccActivityStack.Create;
end;

class destructor TDpccActivity.Destroy;
begin
  FreeAndNil(FStack);
  FreeAndNil(FLock);
end;

class function TDpccActivity.IsMainThread: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

class function TDpccActivity.Enter(const AName: string; AKind: TDpccActivityKind): IInterface;
var
  mTimed: Boolean;
  mStarted: Int64;
  mToken: Integer;
begin
  Result := nil;
  // Hintergrund-Threads halten den Hauptthread nicht auf: kein Eintrag, keine Dauer.
  if (FStack = nil) or not IsMainThread then
  begin
    Exit;
  end;
  mTimed := False;
  mStarted := 0;
  // Startanteile: Nur die äußerste Aktion zählt; verschachtelte stecken in ihrer Dauer.
  if (AKind <> TDpccActivityKind.Ide) and (FStack.Depth = 0) and (FTimes <> nil) then
  begin
    FLock.Enter;
    try
      mTimed := FTimes <> nil;
      if mTimed then
      begin
        mStarted := FTimes.Clock;
      end;
    finally
      FLock.Leave;
    end;
  end;
  mToken := FStack.Push(AName, AKind);
  Result := TActivityScope.Create(AName, AKind, mToken, mTimed, mStarted);
end;

class function TDpccActivity.Scope(const AName: string): IInterface;
begin
  Result := Enter(AName, TDpccActivityKind.Timed);
end;

class function TDpccActivity.Feature(const AName: string): IInterface;
begin
  Result := Enter(AName, TDpccActivityKind.Feature);
end;

class function TDpccActivity.Waiting(const AName: string): IInterface;
begin
  Result := Enter(AName, TDpccActivityKind.Named);
end;

class function TDpccActivity.IdeWork: IInterface;
begin
  Result := Enter('IDE', TDpccActivityKind.Ide);
end;

class procedure TDpccActivity.Leave(const AName: string; AStarted: Int64);
begin
  if FLock = nil then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    // Unter der Sperre: Nach TimeInto(nil) schreibt keine Aktion mehr in die freigegebenen Startanteile.
    if FTimes <> nil then
    begin
      FTimes.Add('Aktion ' + AName, FTimes.Clock - AStarted);
    end;
  finally
    FLock.Leave;
  end;
end;

class procedure TDpccActivity.TimeInto(ATimes: TDpccStartTimes);
begin
  FLock.Enter;
  try
    FTimes := ATimes;
  finally
    FLock.Leave;
  end;
end;

class function TDpccActivity.Current: string;
begin
  Result := '';
  if FStack <> nil then
  begin
    Result := FStack.Top;
  end;
end;

class procedure TDpccActivity.MessagePumped;
begin
  if FStack <> nil then
  begin
    FStack.Pumped;
  end;
end;

class function TDpccActivity.Running: string;
begin
  Result := Current;
  if Result = '' then
  begin
    Result := TDpccGuard.CurrentFeatureName;
  end;
end;

class procedure TDpccActivity.HangTest(AMs: Cardinal);
var
  mActivity: IInterface;
begin
  mActivity := Scope(cHangTestName);
  Sleep(AMs);
end;

class procedure TDpccActivity.HangTest;
begin
  HangTest(cHangTestMs);
end;

{ TDpccStackScan }

class function TDpccStackScan.Frames(const AAddresses: TArray<UInt64>;
  const AModules: TArray<TDpccModuleRange>): TArray<string>;
begin
  Result := Frames(AAddresses, AModules, 24);
end;

class function TDpccStackScan.Frames(const AAddresses: TArray<UInt64>; const AModules: TArray<TDpccModuleRange>;
  AMax: Integer): TArray<string>;
var
  mAddress: UInt64;
  mModule: TDpccModuleRange;
  mFrame: string;
begin
  Result := nil;
  for mAddress in AAddresses do
  begin
    if Length(Result) >= AMax then
    begin
      Break;
    end;
    for mModule in AModules do
    begin
      if (mAddress >= mModule.Base) and (mAddress < mModule.Base + mModule.Size) then
      begin
        mFrame := Format('%s+%x', [mModule.Name, mAddress - mModule.Base]);
        if (Length(Result) = 0) or (Result[High(Result)] <> mFrame) then
        begin
          Result := Result + [mFrame];
        end;
        Break;
      end;
    end;
  end;
end;

class function TDpccStackScan.FirstIn(const AAddresses: TArray<UInt64>; const AModules: TArray<TDpccModuleRange>;
  const APrefix: string): string;
var
  mCandidates: TArray<TDpccModuleRange>;
  mModule: TDpccModuleRange;
  mAddress: UInt64;
begin
  Result := '';
  // Erst die wenigen passenden Module: Der Abzug hat bis zu 64K Adressen, die IDE Hunderte Module.
  mCandidates := nil;
  for mModule in AModules do
  begin
    if mModule.Name.StartsWith(APrefix, True) then
    begin
      mCandidates := mCandidates + [mModule];
    end;
  end;
  if mCandidates = nil then
  begin
    Exit;
  end;
  for mAddress in AAddresses do
  begin
    for mModule in mCandidates do
    begin
      if (mAddress >= mModule.Base) and (mAddress < mModule.Base + mModule.Size) then
      begin
        Exit(Format('%s+%x', [mModule.Name, mAddress - mModule.Base]));
      end;
    end;
  end;
end;

{ TDpccHangMonitor }

function Shown(const AFrames: TArray<string>; const AFrame: string): Boolean;
var
  mFrame: string;
begin
  Result := False;
  for mFrame in AFrames do
  begin
    if mFrame = AFrame then
    begin
      Exit(True);
    end;
  end;
end;

constructor TDpccHangMonitor.Create;
begin
  Create(cDefaultThresholdMs);
end;

constructor TDpccHangMonitor.Create(AThresholdMs: Integer);
begin
  inherited Create;
  FThresholdMs := AThresholdMs;
end;

class function TDpccHangMonitor.InvolvesDpcc(const AHang: TDpccHang): Boolean;
var
  mFrame: string;
begin
  Result := (AHang.Activity <> '') or (AHang.DpccFrame <> '');
  for mFrame in AHang.Frames do
  begin
    if mFrame.StartsWith('dpcc.', True) then
    begin
      Result := True;
    end;
  end;
end;

function TDpccHangMonitor.Finish(const AHang: TDpccHang): string;
var
  mLines: TStringBuilder;
  mFrame: string;
  mDpcc: Boolean;
begin
  Result := '';
  if AHang.DurationMs < FThresholdMs then
  begin
    Exit;
  end;
  mDpcc := InvolvesDpcc(AHang);
  Inc(FCount);
  if AHang.DurationMs > FLongestMs then
  begin
    FLongestMs := AHang.DurationMs;
  end;
  if mDpcc then
  begin
    Inc(FWithDpcc);
    if AHang.DurationMs > FLongestDpccMs then
    begin
      FLongestDpccMs := AHang.DurationMs;
    end;
  end
  else if AHang.DurationMs > FLongestOtherMs then
  begin
    FLongestOtherMs := AHang.DurationMs;
  end;
  // Diagnose-Fenster, Reiter „Hänger“ (nur im Diagnosemodus; threadsicher).
  TDpccPluginTimings.NoteHang(AHang.At, AHang.DurationMs, AHang.Activity, mDpcc);
  mLines := TStringBuilder.Create;
  try
    mLines.AppendFormat('Hauptthread hing %d ms', [AHang.DurationMs]);
    if AHang.Activity <> '' then
    begin
      mLines.Append(' in ').Append(AHang.Activity);
    end
    else if mDpcc then
    begin
      mLines.Append('; dpcc im Aufrufstapel');
    end
    else
    begin
      mLines.Append(' ohne dpcc-Aktivität');
    end;
    if AHang.Window <> '' then
    begin
      mLines.AppendFormat('; Fenster: %s', [AHang.Window]);
    end;
    if AHang.CodeInsightCount > 0 then
    begin
      mLines.AppendFormat('; Code Insight bisher %d-mal, %d ms', [AHang.CodeInsightCount, AHang.CodeInsightMs]);
    end;
    for mFrame in AHang.Frames do
    begin
      mLines.Append(sLineBreak).Append('    ').Append(mFrame);
    end;
    if (AHang.DpccFrame <> '') and not Shown(AHang.Frames, AHang.DpccFrame) then
    begin
      mLines.Append(sLineBreak).Append('    … ').Append(AHang.DpccFrame);
    end;
    Result := mLines.ToString;
  finally
    mLines.Free;
  end;
end;

function TDpccHangMonitor.Summary: string;
begin
  Result := Format('Sitzung: %d Hänger, längster %d ms, %d mit dpcc', [FCount, FLongestMs, FWithDpcc]);
end;

{ TDpccLogThrottle }

constructor TDpccLogThrottle.Create(AIntervalMs: Int64);
begin
  inherited Create;
  FIntervalMs := AIntervalMs;
  FLock := TCriticalSection.Create;
  FEntries := TDictionary<string, TEntry>.Create;
end;

destructor TDpccLogThrottle.Destroy;
begin
  FEntries.Free;
  FLock.Free;
  inherited;
end;

function TDpccLogThrottle.Allow(const AKey: string; ANowMs, AValueMs: Int64; out ASkipped: Integer;
  out ASkippedMaxMs: Int64): Boolean;
var
  mKey: string;
  mEntry: TEntry;
begin
  ASkipped := 0;
  ASkippedMaxMs := 0;
  mKey := AnsiLowerCase(AKey);
  FLock.Enter;
  try
    if not FEntries.TryGetValue(mKey, mEntry) then
    begin
      mEntry := Default(TEntry);
      mEntry.LastMs := ANowMs;
      FEntries.Add(mKey, mEntry);
      Exit(True);
    end;
    if ANowMs - mEntry.LastMs >= FIntervalMs then
    begin
      ASkipped := mEntry.Skipped;
      ASkippedMaxMs := mEntry.SkippedMaxMs;
      mEntry := Default(TEntry);
      mEntry.LastMs := ANowMs;
      FEntries[mKey] := mEntry;
      Exit(True);
    end;
    Inc(mEntry.Skipped);
    if AValueMs > mEntry.SkippedMaxMs then
    begin
      mEntry.SkippedMaxMs := AValueMs;
    end;
    FEntries[mKey] := mEntry;
    Result := False;
  finally
    FLock.Leave;
  end;
end;

{ TDpccSlowLog }

class constructor TDpccSlowLog.Create;
begin
  FEnabled := False;
  FLock := TCriticalSection.Create;
  FThrottle := TDpccLogThrottle.Create(cIntervalMs);
  FPending := TList<string>.Create;
  FDropped := 0;
  FClock := StopwatchMs;
end;

class destructor TDpccSlowLog.Destroy;
begin
  FEnabled := False;
  FClock := nil;
  FreeAndNil(FPending);
  FreeAndNil(FThrottle);
  FreeAndNil(FLock);
end;

class function TDpccSlowLog.ActivityLine(const AName: string; AMs: Int64): string;
begin
  Result := Format('Hauptthread: %s: %d ms', [AName, AMs]);
end;

class function TDpccSlowLog.WaitLine(const AMethod: string; AMs: Int64; const AOutcome: string): string;
begin
  Result := Format('Hauptthread wartete %d ms auf Server %s: %s', [AMs, AMethod, AOutcome]);
end;

class function TDpccSlowLog.SkippedText(ASkipped: Integer; AMaxMs: Int64): string;
begin
  Result := '';
  if ASkipped > 0 then
  begin
    Result := Format(' (dazu %d weitere seit der letzten Meldung, längste %d ms)', [ASkipped, AMaxMs]);
  end;
end;

class procedure TDpccSlowLog.Add(const AKey, ALine: string; AMs: Int64);
var
  mSkipped: Integer;
  mMaxMs: Int64;
begin
  if (FLock = nil) or not FThrottle.Allow(AKey, FClock(), AMs, mSkipped, mMaxMs) then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    if FPending.Count >= cMaxPending then
    begin
      Inc(FDropped);
      Exit;
    end;
    FPending.Add(ALine + SkippedText(mSkipped, mMaxMs));
  finally
    FLock.Leave;
  end;
end;

class procedure TDpccSlowLog.NoteActivity(const AName: string; AMs: Int64);
begin
  if not FEnabled or (AMs < cActivityMs) then
  begin
    Exit;
  end;
  Add(AName, ActivityLine(AName, AMs), AMs);
end;

class procedure TDpccSlowLog.NoteWait(const AMethod: string; AMs: Int64; const AOutcome: string);
begin
  if not FEnabled or (AMs < cWaitMs) then
  begin
    Exit;
  end;
  Add('Warten auf ' + AMethod, WaitLine(AMethod, AMs, AOutcome), AMs);
end;

class function TDpccSlowLog.Take: TArray<string>;
begin
  Result := nil;
  if FLock = nil then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    if FPending.Count > 0 then
    begin
      Result := FPending.ToArray;
      FPending.Clear;
    end;
    if FDropped > 0 then
    begin
      Result := Result + [Format('Hauptthread: %d Zeilen nicht geschrieben (zu viele auf einmal)', [FDropped])];
      FDropped := 0;
    end;
  finally
    FLock.Leave;
  end;
end;

{ TDpccLineBudget }

procedure TDpccLineBudget.Init(AMax: Integer; AWindowMs: Int64);
begin
  FMax := AMax;
  FWindowMs := AWindowMs;
  FWindowStart := 0;
  FUsed := 0;
  FOpen := False;
end;

function TDpccLineBudget.Allow(ANowMs: Int64): Boolean;
begin
  if not FOpen or (ANowMs - FWindowStart >= FWindowMs) then
  begin
    FOpen := True;
    FWindowStart := ANowMs;
    FUsed := 0;
  end;
  Result := FUsed < FMax;
  if Result then
  begin
    Inc(FUsed);
  end;
end;

{ TDpccHangTracker }

constructor TDpccHangTracker.Create(ADiagnose: Boolean; const ANow: TFunc<TDateTime>);
begin
  inherited Create;
  FMonitor := TDpccHangMonitor.Create;
  FDiagnose := ADiagnose;
  FNow := ANow;
  FLastTick := -1;
  FSentAt := -1;
  FHanging := False;
  FDpccBudget.Init(cMaxPerMinute, cMinuteMs);
  FOtherBudget.Init(cMaxPerMinute, cMinuteMs);
end;

constructor TDpccHangTracker.Create(ADiagnose: Boolean);
begin
  Create(ADiagnose, LocalNow);
end;

destructor TDpccHangTracker.Destroy;
begin
  FMonitor.Free;
  inherited;
end;

class function TDpccHangTracker.Line(const AText: string; ADiagnostic: Boolean): TDpccHangLine;
begin
  Result.Text := AText;
  Result.Diagnostic := ADiagnostic;
end;

class function TDpccHangTracker.Suffix(var ASkipped: Integer; var ASkippedMs: Int64): string;
begin
  Result := '';
  if ASkipped > 0 then
  begin
    Result := Format(' (seit der letzten Meldung %d Hänger nicht einzeln protokolliert, zusammen %d ms)',
      [ASkipped, ASkippedMs]);
  end;
  ASkipped := 0;
  ASkippedMs := 0;
end;

procedure TDpccHangTracker.Tick(ANowMs: Int64);
var
  mGap: Int64;
begin
  if FLastTick >= 0 then
  begin
    mGap := ANowMs - FLastTick;
    // Der Wächter selbst stand: Der ganze Prozess war angehalten (Debugger, Ruhezustand). Das zählt nicht.
    if mGap > cPauseMs then
    begin
      Inc(FPausedMs, mGap);
      if FSentAt >= 0 then
      begin
        Inc(FSentAt, mGap);
      end;
      if FHanging then
      begin
        Inc(FHangStart, mGap);
      end;
    end;
  end;
  FLastTick := ANowMs;
end;

procedure TDpccHangTracker.Sent(ANowMs: Int64);
begin
  FSentAt := ANowMs;
  FHanging := False;
end;

function TDpccHangTracker.Waiting(ANowMs: Int64; const AActivity: string): TArray<TDpccHangLine>;
var
  mElapsed: Int64;
begin
  Result := nil;
  if FSentAt < 0 then
  begin
    Exit;
  end;
  mElapsed := ANowMs - FSentAt;
  if mElapsed < FMonitor.ThresholdMs then
  begin
    Exit;
  end;
  if not FHanging then
  begin
    FHanging := True;
    FHangStart := FSentAt;
    FActivity := '';
    FDpccDecided := False;
    FDpccLogged := False;
    FOtherDecided := False;
    FOtherLogged := False;
  end;
  // Die erste dpcc-Aktivität im Hänger gilt; beginnt sie erst später (der Hauptthread arbeitet ohne Nachrichten
  // weiter), wird der Hänger dann noch als dpcc-Hänger gemeldet.
  if (FActivity = '') and (AActivity <> '') then
  begin
    FActivity := AActivity;
  end;
  if FActivity <> '' then
  begin
    if not FDpccDecided then
    begin
      FDpccDecided := True;
      FDpccLogged := FDpccBudget.Allow(ANowMs);
      if FDpccLogged then
      begin
        Result := [Line(Format('Hauptthread hängt seit %d ms in %s', [mElapsed, FActivity]) +
          Suffix(FDpccSkipped, FDpccSkippedMs), False)];
      end;
    end;
  end
  else if FDiagnose and not FOtherDecided then
  begin
    FOtherDecided := True;
    FOtherLogged := FOtherBudget.Allow(ANowMs);
    if FOtherLogged then
    begin
      Result := [Line(Format('Hauptthread hängt seit %d ms ohne dpcc-Aktivität', [mElapsed]) +
        Suffix(FOtherSkipped, FOtherSkippedMs), True)];
    end;
  end;
end;

function TDpccHangTracker.Answered(AAnsweredMs: Int64): TArray<TDpccHangLine>;
var
  mHang: TDpccHang;
  mText: string;
begin
  Result := nil;
  if FHanging then
  begin
    mHang := Default(TDpccHang);
    mHang.DurationMs := AAnsweredMs - FHangStart;
    // Der Takt hat die Schwelle schon gesehen; eine knapp davor gestempelte Antwort zählt trotzdem als Hänger.
    if mHang.DurationMs < FMonitor.ThresholdMs then
    begin
      mHang.DurationMs := FMonitor.ThresholdMs;
    end;
    mHang.At := FNow();
    mHang.Activity := FActivity;
    mText := FMonitor.Finish(mHang);
    if mText <> '' then
    begin
      if FActivity <> '' then
      begin
        if FDpccLogged then
        begin
          Result := [Line(mText, False)];
        end
        else
        begin
          Inc(FDpccSkipped);
          Inc(FDpccSkippedMs, mHang.DurationMs);
          Inc(FDpccSkippedTotal);
        end;
      end
      else if FDiagnose then
      begin
        if FOtherLogged then
        begin
          Result := [Line(mText, True)];
        end
        else
        begin
          Inc(FOtherSkipped);
          Inc(FOtherSkippedMs, mHang.DurationMs);
          Inc(FOtherSkippedTotal);
        end;
      end;
    end;
  end;
  FHanging := False;
  FSentAt := -1;
end;

function TDpccHangTracker.Summary: TArray<TDpccHangLine>;
begin
  Result := nil;
  if FMonitor.WithDpcc > 0 then
  begin
    Result := Result + [Line(Format('Hänger mit dpcc-Aktivität in dieser Sitzung: %d, längster %d ms, ' +
      'nicht einzeln protokolliert: %d', [FMonitor.WithDpcc, FMonitor.LongestDpccMs, FDpccSkippedTotal]), False)];
  end;
  if FDiagnose and (FMonitor.Count > FMonitor.WithDpcc) then
  begin
    Result := Result + [Line(Format('Hänger ohne dpcc-Aktivität in dieser Sitzung: %d, längster %d ms, ' +
      'nicht einzeln protokolliert: %d', [FMonitor.Count - FMonitor.WithDpcc, FMonitor.LongestOtherMs,
      FOtherSkippedTotal]), True)];
  end;
end;

end.