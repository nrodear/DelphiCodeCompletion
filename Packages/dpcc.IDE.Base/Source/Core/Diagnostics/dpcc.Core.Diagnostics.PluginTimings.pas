unit dpcc.Core.Diagnostics.PluginTimings;

// Zeiten des ganzen Plugins für das Diagnose-Fenster (Variante A, Punkt 5 der
// Liste vom 03.11.2026), Teil ohne VCL und Open Tools API:
// - Hauptthread je Funktion: TDpccGuard.Run meldet jeden Aufruf über
//   TDpccGuardTiming (Enter/Leave). Gezählt wird die eigene Zeit eines
//   Aufrufs, also ohne die darin verschachtelten Aufrufe anderer Funktionen,
//   damit die Summe nicht doppelt zählt und der Verursacher oben steht.
//   Aufrufe aus anderen Threads zählen hier nicht (dort hält niemand die IDE
//   auf).
// - Langsame Aufrufe: ab ThresholdMs eigener Zeit ein Eintrag im Ring der
//   letzten 200, mit der längsten dpcc-Aktion (TDpccActivity) des
//   Aufrufs. Wartet der Hauptthread auf den Server, zählt die Anfrage als
//   Aktion („dpcc.server.testUnit“), damit der Verursacher dabeisteht.
// - Modale Dialoge: Zwischen ModalBegin und ModalEnd verarbeitet die IDE
//   Nachrichten, sie hängt nicht. Diese Zeit zählt nicht als eigene Zeit des
//   Aufrufs, der den Dialog öffnete, und nicht zur Belegung (Diagnose vom
//   06.11.2026: Tracker 34 s, Willkommensseite 11,8 s ohne Hänger).
//   Ebenso Arbeit der IDE in einem dpcc-Aufruf (TDpccGuard.RunIde, etwa
//   das Laden eines Projekts, #1987): Sie gehört nicht dpcc; Aufrufe von
//   dpcc darin (Notifier) zählen für sich.
// - Eigene Nachrichtenschleifen von Windows: Ein Kontextmenü (TrackPopupMenu,
//   TPopupMenu.Popup) und Verschieben oder Größe ändern eines Fensters
//   blockieren den Aufruf ebenso, ohne dass die IDE hängt; die IDE meldet sie
//   wie einen modalen Dialog (TDpccMessageLoop.Change ordnet die Nachrichten
//   zu). Vorher zählte die Zeit eines offenen Menüs als dpcc-Zeit (#1986:
//   Designer-Leiste 5,9 s).
// - Belegung: Wie viel jeder Sekunde der äußerste dpcc-Aufruf den Hauptthread
//   hielt, für die letzten 60 Sekunden (TDpccBusyMeter).
// - Server: Dauer, Zeitüberschreitung und Abbruch je Anfrage (TLspClient) und
//   die Zeit, die dabei der Hauptthread wartete: Anzahl und Mittel je
//   wartender Anfrage (#1990; vorher stand die Summe neben Mittel und
//   Maximum und las sich wie eine Wartezeit je Anfrage).
// - Hintergrund: Dauer je Quelle (Vervollständigung u. a.) und wie oft sie zu
//   langsam war (TDpccGuard.ReportProviderSlow).
// - Hänger: die Meldungen des Einfrier-Wächters (#501) dieser Sitzung.
// Aus (Vorgabe) ist TDpccGuard.Timing nil, und die übrigen Messpunkte prüfen
// nur Enabled: kein Zeitstempel, keine Sperre. Anonym: gespeichert werden nur
// Namen von Funktionen, Aktionen, Anfragen und Quellen, Zeiten und Anzahlen.
// Threads: Enter, Leave und ActivityDone kommen aus dem Hauptthread (der
// Stapel der laufenden Aufrufe gehört ihm); alles Übrige ist threadsicher.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  dpcc.Core.Diagnostics.Guard;

type
{$SCOPEDENUMS ON}
  TDpccRequestOutcome = (Done, TimedOut, Cancelled, Failed);
{$SCOPEDENUMS OFF}

  /// <summary>Anzahl, Summe und Maximum in ms; SlowCalls = Aufrufe ab der Schwelle.</summary>
  TDpccCallStat = record
    Calls: Integer;
    TotalMs: Double;
    MaxMs: Double;
    SlowCalls: Integer;
    procedure Add(AMs: Double; ASlow: Boolean);
    /// <summary>Mittelwert; 0 ohne Aufrufe.</summary>
    function MeanMs: Double;
  end;

  TDpccFeatureTiming = record
    Feature: TDpccFeature;
    Stat: TDpccCallStat;
  end;

  TDpccSlowCall = record
    At: TDateTime;
    Feature: TDpccFeature;
    /// <summary>Längste dpcc-Aktion im Aufruf; '' ohne.</summary>
    Activity: string;
    Ms: Double;
  end;

  TDpccRequestTiming = record
    Method: string;
    Stat: TDpccCallStat;
    /// <summary>So lange stand der Hauptthread insgesamt auf Antworten dieser Anfrage.</summary>
    WaitedMs: Double;
    /// <summary>So oft wartete der Hauptthread auf diese Anfrage.</summary>
    WaitedCalls: Integer;
    TimedOut: Integer;
    Cancelled: Integer;
    Failed: Integer;
    /// <summary>Mittlere Wartezeit des Hauptthreads je wartender Anfrage; 0 ohne.</summary>
    function WaitedMeanMs: Double;
  end;

  TDpccSourceTiming = record
    Name: string;
    Stat: TDpccCallStat;
    /// <summary>Über dem Zeitlimit oder übersprungen, weil die vorige Anfrage noch lief.</summary>
    Slow: Integer;
  end;

  TDpccHangEntry = record
    At: TDateTime;
    DurationMs: Int64;
    Activity: string;
    WithDpcc: Boolean;
  end;

  TDpccPluginSnapshot = record
    Since: TDateTime;
    ThresholdMs: Integer;
    Paused: Boolean;
    /// <summary>Nur Funktionen mit Aufrufen, in der Reihenfolge von TDpccFeature.</summary>
    Features: TArray<TDpccFeatureTiming>;
    /// <summary>Älteste zuerst.</summary>
    Slow: TArray<TDpccSlowCall>;
    Requests: TArray<TDpccRequestTiming>;
    Sources: TArray<TDpccSourceTiming>;
    /// <summary>Älteste zuerst.</summary>
    Hangs: TArray<TDpccHangEntry>;
    /// <summary>Belegung des Hauptthreads je abgeschlossener Sekunde in Prozent, älteste zuerst.</summary>
    Busy: TArray<Double>;
    /// <summary>Mittel über Busy; 0 ohne Werte.</summary>
    function BusyPercent: Double;
  end;

  /// <summary>Mikrosekunden einer stetigen Uhr.</summary>
  TDpccMicroClock = reference to function: Int64;

  /// <summary>Belegung des Hauptthreads je Sekunde, Ring der letzten cSeconds Sekunden.</summary>
  TDpccBusyMeter = record
  public const
    cSeconds = 60;
  private
    FUs: array[0..cSeconds - 1] of Int64;
    FSecond: array[0..cSeconds - 1] of Int64;
    FStartSecond: Int64;
    procedure AddSecond(ASecond, AUs: Int64);
  public
    /// <summary>Alles verwerfen; gezählt wird ab der Sekunde von ANowUs.</summary>
    procedure Reset(ANowUs: Int64);
    /// <summary>Ein Aufruf von AStart bis AStop (µs); über eine Sekundengrenze anteilig zu beiden.</summary>
    procedure Add(AStart, AStop: Int64);
    /// <summary>Prozent je abgeschlossener Sekunde seit Reset, höchstens cSeconds, älteste zuerst.</summary>
    function Values(ANowUs: Int64): TArray<Double>;
  end;

  /// <summary>Ein laufender Aufruf im Hauptthread.</summary>
  TDpccCallFrame = record
    Start: Int64;
    ChildUs: Int64;
    Activity: string;
    ActivityUs: Int64;
    /// <summary>Darin offene modale Dialoge; zählt nicht zur Belegung.</summary>
    IdleUs: Int64;
  end;

  /// <summary>Stapel der laufenden Aufrufe im Hauptthread; gehört dem Hauptthread allein.</summary>
  TDpccCallStack = record
  public const
    cMaxDepth = 32;
  private
    FFrames: array[0..cMaxDepth - 1] of TDpccCallFrame;
    FDepth: Integer;
  public
    /// <summary>Neuer Aufruf ab AStart; Ergebnis: Zeichen für Pop, -1 bei vollem Stapel.</summary>
    function Push(AStart: Int64): Integer;
    /// <summary>Nimmt den obersten Aufruf, wenn AToken zu ihm gehört: eigene Zeit ohne verschachtelte Aufrufe
    /// in AOwnUs, AOuter = es war der äußerste.</summary>
    function Pop(AToken: Integer; AStop: Int64; out AFrame: TDpccCallFrame; out AOwnUs: Int64;
      out AOuter: Boolean): Boolean;
    /// <summary>Eine Aktion von AUs µs im obersten Aufruf; die längste bleibt.</summary>
    procedure Activity(const AName: string; AUs: Int64);
    /// <summary>Verschachtelte Zeit des obersten Aufrufs; 0 ohne Aufruf.</summary>
    function TopChildUs: Int64;
    /// <summary>Im obersten Aufruf stand AUs µs ein modaler Dialog offen; vorher hatte er AChildUsBefore
    /// verschachtelte Zeit. Danach zählt die ganze Dialogzeit als verschachtelt, nicht als eigene.</summary>
    procedure Waited(AChildUsBefore, AUs: Int64);
    property Depth: Integer read FDepth;
  end;

  /// <summary>Offene modale Dialoge im Hauptthread; gezählt wird nur der äußerste.</summary>
  TDpccModalWatch = record
  private
    FDepth: Integer;
    FStart: Int64;
    FFrame: Integer;
    FChildUs: Int64;
  public
    /// <summary>Ein Dialog öffnet sich bei ANowUs, während AStack läuft.</summary>
    procedure Opened(const AStack: TDpccCallStack; ANowUs: Int64);
    /// <summary>Ein Dialog schließt sich bei ANowUs: Steht noch derselbe Aufruf oben, zählt die Dialogzeit
    /// nicht als seine eigene.</summary>
    procedure Closed(var AStack: TDpccCallStack; ANowUs: Int64);
    procedure Reset;
  end;

  /// <summary>Nachrichten, mit denen Windows eine eigene Nachrichtenschleife beginnt oder beendet.</summary>
  TDpccMessageLoop = record
  public const
    cEnterMenuLoop = $0211;
    cExitMenuLoop = $0212;
    cEnterSizeMove = $0231;
    cExitSizeMove = $0232;
  public
    /// <summary>1: Menü (auch Kontextmenü) oder Verschieben/Größe ändern beginnt, -1: endet, 0: sonst.</summary>
    class function Change(AMessage: Cardinal): Integer; static;
  end;

  /// <summary>Rekorder der Plugin-Zeiten; eine gemeinsame Instanz über TDpccPluginTimings.Shared.</summary>
  TDpccPluginRecorder = class(TDpccGuardTiming)
  public const
    cSlowCapacity = 200;
    cHangCapacity = 50;
    cDefaultThresholdMs = 16;
    cMinThresholdMs = 1;
    cMaxThresholdMs = 1000;
  private
    FLock: TCriticalSection;
    FClock: TDpccMicroClock;
    FNow: TFunc<TDateTime>;
    FIsMainThread: TFunc<Boolean>;
    FStack: TDpccCallStack;
    FFeatures: array[TDpccFeature] of TDpccCallStat;
    FSlow: TList<TDpccSlowCall>;
    FRequests: TDictionary<string, TDpccRequestTiming>;
    FSources: TDictionary<string, TDpccSourceTiming>;
    FHangs: TList<TDpccHangEntry>;
    FBusy: TDpccBusyMeter;
    FSince: TDateTime;
    FThresholdMs: Integer;
    FPaused: Boolean;
    FVersion: Integer;
    FModal: TDpccModalWatch;
    procedure AddSlow(AFeature: TDpccFeature; const AActivity: string; AMs: Double);
    procedure RecordCall(AFeature: TDpccFeature; const AFrame: TDpccCallFrame; AOwnUs, AStop: Int64;
      AOuter: Boolean);
    procedure SetThresholdMs(AValue: Integer);
    procedure SetPaused(AValue: Boolean);
  public
    /// <summary>AClock: Mikrosekunden; ANow: Uhrzeit der Einträge; AIsMainThread: läuft der Aufrufer im
    /// Hauptthread? Tests setzen alle drei.</summary>
    constructor Create(const AClock: TDpccMicroClock; const ANow: TFunc<TDateTime>;
      const AIsMainThread: TFunc<Boolean>); overload;
    /// <summary>Stoppuhr, Now und MainThreadID.</summary>
    constructor Create; overload;
    destructor Destroy; override;
    /// <summary>Mikrosekunden der Uhr dieses Rekorders.</summary>
    function Stamp: Int64;
    /// <summary>Läuft der Aufrufer im Hauptthread?</summary>
    function OnMainThread: Boolean;
    function Enter: Integer; override;
    procedure Leave(AFeature: TDpccFeature; AToken: Integer); override;
    procedure ProviderSlow(const AName: string); override;
    /// <summary>Eine Aktion (TDpccActivity) begann bei AStarted (Stamp) und endet jetzt; nur im Hauptthread.
    /// </summary>
    procedure ActivityDone(const AName: string; AStarted: Int64);
    /// <summary>Anfrage AMethod an den Server ist beendet; AMainThread: der Hauptthread hat gewartet.</summary>
    procedure RequestDone(const AMethod: string; AMs: Double; AOutcome: TDpccRequestOutcome;
      AMainThread: Boolean);
    /// <summary>Quelle AName hat AMs gearbeitet (aus jedem Thread).</summary>
    procedure SourceDone(const AName: string; AMs: Double);
    procedure HangDone(const AHang: TDpccHangEntry);
    /// <summary>Ein modaler Dialog, eine eigene Nachrichtenschleife (Menü, Verschieben; Application.OnModalBegin,
    /// TDpccMessageLoop) oder Arbeit der IDE (TDpccGuard.RunIde) beginnt; nur im Hauptthread.</summary>
    procedure ModalBegin; override;
    /// <summary>Der modale Dialog, die Nachrichtenschleife bzw. die Arbeit der IDE ist zu Ende.</summary>
    procedure ModalEnd; override;
    /// <summary>Alle Werte verwerfen; „Messung seit“ beginnt neu.</summary>
    procedure Reset;
    function Snapshot: TDpccPluginSnapshot;
    /// <summary>Zählt jede Änderung; das Fenster zeichnet nur bei neuem Stand neu.</summary>
    function Version: Integer;
    /// <summary>Langsam ab so viel eigener Zeit (cMinThresholdMs bis cMaxThresholdMs).</summary>
    property ThresholdMs: Integer read FThresholdMs write SetThresholdMs;
    /// <summary>Angehalten zählt nichts Neues; die Werte bleiben stehen.</summary>
    property Paused: Boolean read FPaused write SetPaused;
  end;

  /// <summary>Schalter und Messpunkte für den übrigen Code; aus prüft jeder Messpunkt nur Enabled.</summary>
  TDpccPluginTimings = class
  private class var
    FShared: TDpccPluginRecorder;
    FEnabled: Boolean;
    class procedure SetEnabled(AValue: Boolean); static;
  public
    class destructor DestroyShared;
    /// <summary>Gemeinsamer Rekorder; lebt bis zum Entladen des Packages.</summary>
    class function Shared: TDpccPluginRecorder; static;
    /// <summary>Messung an: TDpccGuard.Timing zeigt auf Shared. Aus (Vorgabe): nil.</summary>
    class property Enabled: Boolean read FEnabled write SetEnabled;
    /// <summary>Zeitstempel für NoteActivity bzw. NoteSource; 0, wenn die Messung aus ist.</summary>
    class function StampIfEnabled: Int64; static;
    /// <summary>Messpunkt TDpccActivity: Aktion AName begann bei AStarted (StampIfEnabled); 0 tut nichts.
    /// </summary>
    class procedure NoteActivity(const AName: string; AStarted: Int64); static;
    /// <summary>Messpunkt der Quellen: AName arbeitete seit AStarted (StampIfEnabled); 0 tut nichts.</summary>
    class procedure NoteSource(const AName: string; AStarted: Int64); static;
    /// <summary>Messpunkt TLspClient; ob der Hauptthread wartete, bestimmt der Rekorder.</summary>
    class procedure NoteRequest(const AMethod: string; AMs: Double; AOutcome: TDpccRequestOutcome); static;
    /// <summary>Messpunkt des Einfrier-Wächters: ein gemeldeter Hänger.</summary>
    class procedure NoteHang(AAt: TDateTime; ADurationMs: Int64; const AActivity: string;
      AWithDpcc: Boolean); static;
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.Diagnostics;

const
  cUsPerSecond = 1000000;
  cUsPerMs = 1000;

{ TDpccCallStat }

procedure TDpccCallStat.Add(AMs: Double; ASlow: Boolean);
begin
  Inc(Calls);
  TotalMs := TotalMs + AMs;
  if AMs > MaxMs then
  begin
    MaxMs := AMs;
  end;
  if ASlow then
  begin
    Inc(SlowCalls);
  end;
end;

function TDpccCallStat.MeanMs: Double;
begin
  Result := 0;
  if Calls > 0 then
  begin
    Result := TotalMs / Calls;
  end;
end;

{ TDpccRequestTiming }

function TDpccRequestTiming.WaitedMeanMs: Double;
begin
  Result := 0;
  if WaitedCalls > 0 then
  begin
    Result := WaitedMs / WaitedCalls;
  end;
end;

{ TDpccPluginSnapshot }

function TDpccPluginSnapshot.BusyPercent: Double;
var
  mValue: Double;
begin
  Result := 0;
  if Length(Busy) = 0 then
  begin
    Exit;
  end;
  for mValue in Busy do
  begin
    Result := Result + mValue;
  end;
  Result := Result / Length(Busy);
end;

{ TDpccBusyMeter }

procedure TDpccBusyMeter.Reset(ANowUs: Int64);
begin
  FillChar(FUs, SizeOf(FUs), 0);
  FillChar(FSecond, SizeOf(FSecond), 0);
  FStartSecond := ANowUs div cUsPerSecond;
end;

procedure TDpccBusyMeter.Add(AStart, AStop: Int64);
var
  mSecond, mEnd, mFrom: Int64;
begin
  mFrom := AStart;
  while mFrom < AStop do
  begin
    mSecond := mFrom div cUsPerSecond;
    mEnd := Min(AStop, (mSecond + 1) * cUsPerSecond);
    AddSecond(mSecond, mEnd - mFrom);
    mFrom := mEnd;
  end;
end;

procedure TDpccBusyMeter.AddSecond(ASecond, AUs: Int64);
var
  mSlot: Integer;
begin
  if ASecond < FStartSecond then
  begin
    Exit;
  end;
  mSlot := ASecond mod cSeconds;
  if FSecond[mSlot] <> ASecond then
  begin
    FSecond[mSlot] := ASecond;
    FUs[mSlot] := 0;
  end;
  Inc(FUs[mSlot], AUs);
end;

function TDpccBusyMeter.Values(ANowUs: Int64): TArray<Double>;
var
  mCurrent, mFirst, mSecond: Int64;
  mSlot, mIndex: Integer;
begin
  // Nur abgeschlossene Sekunden; die laufende Sekunde wäre zu niedrig.
  mCurrent := ANowUs div cUsPerSecond;
  mFirst := Max(FStartSecond, mCurrent - cSeconds);
  Result := nil;
  if mCurrent <= mFirst then
  begin
    Exit;
  end;
  SetLength(Result, mCurrent - mFirst);
  mIndex := 0;
  mSecond := mFirst;
  while mSecond < mCurrent do
  begin
    mSlot := mSecond mod cSeconds;
    Result[mIndex] := 0;
    if FSecond[mSlot] = mSecond then
    begin
      Result[mIndex] := Min(100.0, FUs[mSlot] * 100.0 / cUsPerSecond);
    end;
    Inc(mIndex);
    Inc(mSecond);
  end;
end;

{ TDpccCallStack }

function TDpccCallStack.Push(AStart: Int64): Integer;
begin
  Result := -1;
  if FDepth >= cMaxDepth then
  begin
    Exit;
  end;
  FFrames[FDepth] := Default(TDpccCallFrame);
  FFrames[FDepth].Start := AStart;
  Inc(FDepth);
  Result := FDepth;
end;

function TDpccCallStack.Pop(AToken: Integer; AStop: Int64; out AFrame: TDpccCallFrame; out AOwnUs: Int64;
  out AOuter: Boolean): Boolean;
var
  mElapsed: Int64;
begin
  AFrame := Default(TDpccCallFrame);
  AOwnUs := 0;
  AOuter := False;
  // Nur der oberste Aufruf; ein fremdes Zeichen (anderer Thread, voller Stapel) zählt nicht.
  Result := (AToken > 0) and (AToken = FDepth);
  if not Result then
  begin
    Exit;
  end;
  Dec(FDepth);
  AFrame := FFrames[FDepth];
  FFrames[FDepth].Activity := '';
  mElapsed := Max(Int64(0), AStop - AFrame.Start);
  AOwnUs := Max(Int64(0), mElapsed - AFrame.ChildUs);
  AOuter := FDepth = 0;
  if not AOuter then
  begin
    Inc(FFrames[FDepth - 1].ChildUs, mElapsed);
    Inc(FFrames[FDepth - 1].IdleUs, AFrame.IdleUs);
  end;
end;

function TDpccCallStack.TopChildUs: Int64;
begin
  Result := 0;
  if FDepth > 0 then
  begin
    Result := FFrames[FDepth - 1].ChildUs;
  end;
end;

procedure TDpccCallStack.Waited(AChildUsBefore, AUs: Int64);
begin
  if (FDepth = 0) or (AUs <= 0) then
  begin
    Exit;
  end;
  // Aufrufe im Dialog sind darin enthalten; sie zählen für sich, aber nicht doppelt.
  FFrames[FDepth - 1].ChildUs := AChildUsBefore + AUs;
  Inc(FFrames[FDepth - 1].IdleUs, AUs);
end;

procedure TDpccCallStack.Activity(const AName: string; AUs: Int64);
begin
  if (FDepth > 0) and (AUs > FFrames[FDepth - 1].ActivityUs) then
  begin
    FFrames[FDepth - 1].ActivityUs := AUs;
    FFrames[FDepth - 1].Activity := AName;
  end;
end;

{ TDpccModalWatch }

procedure TDpccModalWatch.Opened(const AStack: TDpccCallStack; ANowUs: Int64);
begin
  Inc(FDepth);
  if FDepth = 1 then
  begin
    FStart := ANowUs;
    FFrame := AStack.Depth;
    FChildUs := AStack.TopChildUs;
  end;
end;

procedure TDpccModalWatch.Closed(var AStack: TDpccCallStack; ANowUs: Int64);
begin
  if FDepth = 0 then
  begin
    Exit;
  end;
  Dec(FDepth);
  // Nur, wenn noch derselbe Aufruf oben steht, der den Dialog geöffnet hat.
  if (FDepth = 0) and (FFrame > 0) and (AStack.Depth = FFrame) then
  begin
    AStack.Waited(FChildUs, ANowUs - FStart);
  end;
end;

procedure TDpccModalWatch.Reset;
begin
  FDepth := 0;
end;

{ TDpccMessageLoop }

class function TDpccMessageLoop.Change(AMessage: Cardinal): Integer;
begin
  case AMessage of
    cEnterMenuLoop, cEnterSizeMove:
      Result := 1;
    cExitMenuLoop, cExitSizeMove:
      Result := -1;
  else
    Result := 0;
  end;
end;

{ TDpccPluginRecorder }

function StopwatchMicros: Int64;
begin
  Result := Round(TStopwatch.GetTimeStamp * (cUsPerSecond / TStopwatch.Frequency));
end;

function CurrentIsMainThread: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

function LocalNow: TDateTime;
begin
  Result := Now;
end;

constructor TDpccPluginRecorder.Create(const AClock: TDpccMicroClock; const ANow: TFunc<TDateTime>;
  const AIsMainThread: TFunc<Boolean>);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FClock := AClock;
  FNow := ANow;
  FIsMainThread := AIsMainThread;
  FSlow := TList<TDpccSlowCall>.Create;
  FRequests := TDictionary<string, TDpccRequestTiming>.Create;
  FSources := TDictionary<string, TDpccSourceTiming>.Create;
  FHangs := TList<TDpccHangEntry>.Create;
  FThresholdMs := cDefaultThresholdMs;
  Reset;
end;

constructor TDpccPluginRecorder.Create;
begin
  Create(StopwatchMicros, LocalNow, CurrentIsMainThread);
end;

destructor TDpccPluginRecorder.Destroy;
begin
  if TDpccGuard.Timing = Self then
  begin
    TDpccGuard.Timing := nil;
  end;
  FHangs.Free;
  FSources.Free;
  FRequests.Free;
  FSlow.Free;
  FLock.Free;
  inherited;
end;

function TDpccPluginRecorder.Stamp: Int64;
begin
  Result := FClock();
end;

function TDpccPluginRecorder.OnMainThread: Boolean;
begin
  Result := FIsMainThread();
end;

function TDpccPluginRecorder.Enter: Integer;
begin
  Result := -1;
  if FIsMainThread() and not FPaused then
  begin
    Result := FStack.Push(FClock());
  end;
end;

procedure TDpccPluginRecorder.Leave(AFeature: TDpccFeature; AToken: Integer);
var
  mStop, mOwn: Int64;
  mFrame: TDpccCallFrame;
  mOuter: Boolean;
begin
  if AToken <= 0 then
  begin
    Exit;
  end;
  mStop := FClock();
  if FStack.Pop(AToken, mStop, mFrame, mOwn, mOuter) then
  begin
    RecordCall(AFeature, mFrame, mOwn, mStop, mOuter);
  end;
end;

procedure TDpccPluginRecorder.RecordCall(AFeature: TDpccFeature; const AFrame: TDpccCallFrame;
  AOwnUs, AStop: Int64; AOuter: Boolean);
var
  mMs: Double;
  mSlow: Boolean;
begin
  mMs := AOwnUs / cUsPerMs;
  FLock.Enter;
  try
    mSlow := mMs >= FThresholdMs;
    FFeatures[AFeature].Add(mMs, mSlow);
    if mSlow then
    begin
      AddSlow(AFeature, AFrame.Activity, mMs);
    end;
    if AOuter then
    begin
      FBusy.Add(AFrame.Start, Max(AFrame.Start, AStop - AFrame.IdleUs));
    end;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccPluginRecorder.AddSlow(AFeature: TDpccFeature; const AActivity: string; AMs: Double);
var
  mCall: TDpccSlowCall;
begin
  mCall := Default(TDpccSlowCall);
  mCall.At := FNow();
  mCall.Feature := AFeature;
  mCall.Activity := AActivity;
  mCall.Ms := AMs;
  if FSlow.Count >= cSlowCapacity then
  begin
    FSlow.Delete(0);
  end;
  FSlow.Add(mCall);
end;

procedure TDpccPluginRecorder.ModalBegin;
begin
  if FIsMainThread() then
  begin
    FModal.Opened(FStack, FClock());
  end;
end;

procedure TDpccPluginRecorder.ModalEnd;
begin
  if FIsMainThread() then
  begin
    FModal.Closed(FStack, FClock());
  end;
end;

procedure TDpccPluginRecorder.ActivityDone(const AName: string; AStarted: Int64);
begin
  if FIsMainThread() then
  begin
    FStack.Activity(AName, FClock() - AStarted);
  end;
end;

procedure TDpccPluginRecorder.ProviderSlow(const AName: string);
var
  mSource: TDpccSourceTiming;
begin
  FLock.Enter;
  try
    if FPaused then
    begin
      Exit;
    end;
    if not FSources.TryGetValue(AName, mSource) then
    begin
      mSource := Default(TDpccSourceTiming);
      mSource.Name := AName;
    end;
    Inc(mSource.Slow);
    FSources.AddOrSetValue(AName, mSource);
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccPluginRecorder.SourceDone(const AName: string; AMs: Double);
var
  mSource: TDpccSourceTiming;
begin
  FLock.Enter;
  try
    if FPaused then
    begin
      Exit;
    end;
    if not FSources.TryGetValue(AName, mSource) then
    begin
      mSource := Default(TDpccSourceTiming);
      mSource.Name := AName;
    end;
    mSource.Stat.Add(AMs, AMs >= FThresholdMs);
    FSources.AddOrSetValue(AName, mSource);
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccPluginRecorder.RequestDone(const AMethod: string; AMs: Double; AOutcome: TDpccRequestOutcome;
  AMainThread: Boolean);
var
  mRequest: TDpccRequestTiming;
begin
  FLock.Enter;
  try
    if FPaused then
    begin
      Exit;
    end;
    if not FRequests.TryGetValue(AMethod, mRequest) then
    begin
      mRequest := Default(TDpccRequestTiming);
      mRequest.Method := AMethod;
    end;
    mRequest.Stat.Add(AMs, AMs >= FThresholdMs);
    if AMainThread then
    begin
      mRequest.WaitedMs := mRequest.WaitedMs + AMs;
      Inc(mRequest.WaitedCalls);
    end;
    if AOutcome = TDpccRequestOutcome.TimedOut then
    begin
      Inc(mRequest.TimedOut);
    end
    else if AOutcome = TDpccRequestOutcome.Cancelled then
    begin
      Inc(mRequest.Cancelled);
    end
    else if AOutcome = TDpccRequestOutcome.Failed then
    begin
      Inc(mRequest.Failed);
    end;
    FRequests.AddOrSetValue(AMethod, mRequest);
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccPluginRecorder.HangDone(const AHang: TDpccHangEntry);
begin
  FLock.Enter;
  try
    if FPaused then
    begin
      Exit;
    end;
    if FHangs.Count >= cHangCapacity then
    begin
      FHangs.Delete(0);
    end;
    FHangs.Add(AHang);
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccPluginRecorder.Reset;
var
  mFeature: TDpccFeature;
begin
  FLock.Enter;
  try
    for mFeature := Low(TDpccFeature) to High(TDpccFeature) do
    begin
      FFeatures[mFeature] := Default(TDpccCallStat);
    end;
    FSlow.Clear;
    FRequests.Clear;
    FSources.Clear;
    FHangs.Clear;
    FBusy.Reset(FClock());
    FModal.Reset;
    FSince := FNow();
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

function TDpccPluginRecorder.Snapshot: TDpccPluginSnapshot;
var
  mFeature: TDpccFeature;
  mCount: Integer;
begin
  Result := Default(TDpccPluginSnapshot);
  FLock.Enter;
  try
    Result.Since := FSince;
    Result.ThresholdMs := FThresholdMs;
    Result.Paused := FPaused;
    SetLength(Result.Features, Ord(High(TDpccFeature)) + 1);
    mCount := 0;
    for mFeature := Low(TDpccFeature) to High(TDpccFeature) do
    begin
      if FFeatures[mFeature].Calls > 0 then
      begin
        Result.Features[mCount].Feature := mFeature;
        Result.Features[mCount].Stat := FFeatures[mFeature];
        Inc(mCount);
      end;
    end;
    SetLength(Result.Features, mCount);
    Result.Slow := FSlow.ToArray;
    Result.Requests := FRequests.Values.ToArray;
    Result.Sources := FSources.Values.ToArray;
    Result.Hangs := FHangs.ToArray;
    Result.Busy := FBusy.Values(FClock());
  finally
    FLock.Leave;
  end;
end;

function TDpccPluginRecorder.Version: Integer;
begin
  FLock.Enter;
  try
    Result := FVersion;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccPluginRecorder.SetThresholdMs(AValue: Integer);
begin
  FLock.Enter;
  try
    FThresholdMs := EnsureRange(AValue, cMinThresholdMs, cMaxThresholdMs);
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccPluginRecorder.SetPaused(AValue: Boolean);
begin
  FLock.Enter;
  try
    FPaused := AValue;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

{ TDpccPluginTimings }

class destructor TDpccPluginTimings.DestroyShared;
begin
  Enabled := False;
  FreeAndNil(FShared);
end;

class function TDpccPluginTimings.Shared: TDpccPluginRecorder;
begin
  if FShared = nil then
  begin
    FShared := TDpccPluginRecorder.Create;
  end;
  Result := FShared;
end;

class procedure TDpccPluginTimings.SetEnabled(AValue: Boolean);
begin
  if AValue then
  begin
    TDpccGuard.Timing := Shared;
  end
  else if (FShared <> nil) and (TDpccGuard.Timing = FShared) then
  begin
    TDpccGuard.Timing := nil;
  end;
  FEnabled := AValue;
end;

class function TDpccPluginTimings.StampIfEnabled: Int64;
begin
  Result := 0;
  if FEnabled then
  begin
    Result := Shared.Stamp;
  end;
end;

class procedure TDpccPluginTimings.NoteActivity(const AName: string; AStarted: Int64);
begin
  if FEnabled and (AStarted <> 0) then
  begin
    Shared.ActivityDone(AName, AStarted);
  end;
end;

class procedure TDpccPluginTimings.NoteSource(const AName: string; AStarted: Int64);
var
  mShared: TDpccPluginRecorder;
begin
  if FEnabled and (AStarted <> 0) then
  begin
    mShared := Shared;
    mShared.SourceDone(AName, Max(Int64(0), mShared.Stamp - AStarted) / cUsPerMs);
  end;
end;

class procedure TDpccPluginTimings.NoteRequest(const AMethod: string; AMs: Double; AOutcome: TDpccRequestOutcome);
var
  mShared: TDpccPluginRecorder;
begin
  if FEnabled then
  begin
    mShared := Shared;
    mShared.RequestDone(AMethod, AMs, AOutcome, mShared.OnMainThread);
    // Hat der Hauptthread gewartet, steht die Anfrage als Aktion beim langsamen Aufruf.
    if mShared.OnMainThread then
    begin
      mShared.ActivityDone(AMethod, mShared.Stamp - Round(AMs * cUsPerMs));
    end;
  end;
end;

class procedure TDpccPluginTimings.NoteHang(AAt: TDateTime; ADurationMs: Int64; const AActivity: string;
  AWithDpcc: Boolean);
var
  mHang: TDpccHangEntry;
begin
  if not FEnabled then
  begin
    Exit;
  end;
  mHang.At := AAt;
  mHang.DurationMs := ADurationMs;
  mHang.Activity := AActivity;
  mHang.WithDpcc := AWithDpcc;
  Shared.HangDone(mHang);
end;

end.
