unit dpcc.Memory.Bench.Tests;

// Messprogramm Speicher (Speicher-Optimierung, Phase 0): startet den Completion-Server im eigenen Prozess wie das
// Plugin (TLspInProcessServer), öffnet eine echte Projektgruppe mit der Bibliothek der Delphi-Installation und misst
// Private Bytes, Spitze und die größte freie Region des Adressraums (GetProcessMemoryInfo, VirtualQuery):
// nach dem Start, nach dem Indexaufbau, nach N Anfragen, nach jedem Neuaufbau (.dproj „gespeichert“) und nach einem
// Neustart des Servers. Jede Sekunde eine Zeile in die CSV-Datei, dazu je Messpunkt eine Zeile in
// <Datei>-points.csv mit dem geschätzten Index (TShellMemoryReport) und dem höchsten Wert seit dem vorigen Punkt.
//
// Kategorie Benchmark: Der Standardlauf (--exclude:Benchmark) überspringt den Test. Er misst nur, wenn
// DPCC_MEMBENCH_OUT gesetzt ist, sonst endet er sofort. Weitere Umgebungsvariablen:
// - DPCC_MEMBENCH_GROUP: .groupproj (Pflicht), deren Projekte als Arbeitsbereich dienen;
// - DPCC_MEMBENCH_REQUESTS (Vorgabe 2000), DPCC_MEMBENCH_REBUILDS (5), DPCC_MEMBENCH_RESTARTS (1),
//   DPCC_MEMBENCH_BETWEEN (Anfragen zwischen zwei Neuaufbauten, 100);
// - DPCC_MEMBENCH_COLD (Vorgabe 0): so viele Vervollständigungen "Unit." auf zufällige Units der Bibliothek
//   (DPCC_MEMBENCH_LIBDIR, Vorgabe der source-Ordner von Delphi 13) nach den Anfragen, im Text einer Projekt-Unit;
//   misst Nachladen und Verdrängen (Speicher-Optimierung Phase 3). Danach gilt wieder der Originaltext.
// - DPCC_MEMBENCH_TYPING (Vorgabe 0): so viele Tipp-Runden in einer Projekt-Unit (je vier Tastendrücke im Abstand von
//   100 ms, dann eine Pause, in der der Server den Text übernimmt), während ein zweiter Thread ununterbrochen
//   Vervollständigung (auch nach ":="), Hover und Parameterhilfe in anderen offenen Units anfragt
//   (Speicher-Optimierung Phase 4). Die Zeile "[typing]" nennt Zahl, Median, 95. und 99. Perzentil und Höchstwert der
//   Antwortzeiten; jede einzelne steht in <Datei>-latency.csv.
//   L5: Die Vervollständigung nach ":=" folgt der Regel der IDE für das Öffnen beim Tippen (TDpccAutoOpen,
//   completion.autoMinChars): Der Name hinter ":=" wird Zeichen für Zeichen getippt; gefragt wird einmal, sobald die
//   Regel Query meldet (Vorgabe ab 5 Zeichen), danach filtert die Liste lokal. Ist der Name kürzer oder kein
//   Bezeichner, gibt es keine Anfrage ("ohne Anfrage" in der Zeile "[typing]"). DPCC_MEMBENCH_AUTOMIN setzt die
//   Schwelle (0 = Tippen öffnet nie); -1 fragt wie vor L5 direkt hinter "=" ohne Buchstaben.
// - DPCC_MEMBENCH_PINNED (Vorgabe 0): Eine Projekt-Unit nennt die größten Units der Bibliothek in ihren uses
//   (DPCC_MEMBENCH_PINNEDUNITS, kommagetrennt; Vorgabe die DPCC_MEMBENCH_PINNEDCOUNT größten Dateien unter
//   DPCC_MEMBENCH_LIBDIR, 80) und lädt sie
//   über Vervollständigungen; danach so viele Vervollständigungen auf zufällige Units der Bibliothek in einer anderen
//   Unit. Die Zeile "[pinned]" nennt Nachladen und Verdrängen während dieser Vervollständigungen (Phase 4: Units aus
//   den uses zählen nicht gegen die Grenze der verdrängbaren Units).
// - DPCC_MEMBENCH_FREQUENT (Vorgabe 0): so viele Runden mit einem häufigen Namen oberster Ebene
//   (DPCC_MEMBENCH_FREQNAMES, kommagetrennt, Vorgabe "Register"): eine Vervollständigung nach ":=" auf eine Variable
//   dieses Typs (der Server sucht ihn über FindSymbols und lädt alle kalten Units mit diesem Namen), dann fünf
//   Vervollständigungen auf zufällige Units der Bibliothek in einer anderen Unit, die wieder verdrängen. Die Zeile
//   "[frequent]" nennt Nachladen, Verdrängen, die Antwortzeiten der Suche und die größten verdrängbaren Units nach ihr
//   (Speicher-Optimierung Phase 5).
// - DPCC_MEMBENCH_IMPORTS (L2): kommagetrennte Namen oberster Ebene (etwa aus Word2010, WinRT, DUnitX). Je Name eine
//   Vervollständigung auf den Namen in einer Projekt-Unit, die ihn nicht kennt; die Zeile "[import]" nennt, ob die
//   Liste ihn anbietet (mit "+ Unit"), die Antwortzeit und den Eintrag.
// - DPCC_MEMBENCH_LISTS (L4): durch "|" getrennte Zeilen, je eine Vervollständigung an ihrem Ende in einer Projekt-Unit,
//   die nur System.SysUtils einbindet: im Rumpf einer Routine (etwa "raise E", "on E: EC" nach "try except") bzw.
//   mit "[" am Anfang vor einer Deklaration (Attribut). Die Zeile "[lists]" nennt Einträge, Antwortzeit und die
//   dabei nachgeladenen Units (raise und Attribute laden seit L4 keine kalte Unit mehr nach).
// - DPCC_MEMBENCH_DEFINITIONS (NAV): durch "|" getrennte Fälle "Units#Zeile#Wort": eine Projekt-Unit mit diesen
//   uses und der Zeile im Rumpf einer Routine, darin Strg+Klick auf das Wort (TLspSession.GotoTarget mit eigener
//   Grenze cDefinitionLimitMs = 1 s, dem früheren Zeitlimit der IDE). Die Zeile "[definition]" nennt Ziel (Datei,
//   Zeile), Antwortzeit und die dabei nachgeladenen Units; "[definition] Summe" Treffer, Median, Höchstwert und
//   zuletzt, wie viele Antworten über der heutigen Wartezeit der IDE lagen (cMainThreadTimeoutMs, 250 ms; dort käme
//   der Sprung nachgereicht).
// Je Messpunkt eine Zeile "[lazy]" mit geladenen, gepinnten, verdrängbaren und verdrängten Units, Katalog und
// Dauer des Nachladens (Median, Höchstwert, größte Unit).
// Der Cache gehört nicht dem Benutzer: Der Aufrufer setzt LOCALAPPDATA bzw. DPCC_CACHE_ROOT auf einen eigenen Ordner
// (z. B. mit einer Kopie des Bibliotheks-Caches) und APPDATA auf einen leeren. Rohdaten gehören nicht ins Repository.
// Fehler im Server (ERangeError, EIntOverflow, EAccessViolation) schreibt das Messprogramm mit Fehleradresse und
// Rücksprungadressen nach <Datei>-exceptions.txt (Speicher-Optimierung Phase 2: gescheiterte Anfragen); die Adressen
// löst die .map-Datei des Testprogramms auf. Nur im Testprogramm und nur während der Messung.
// Jede gescheiterte Anfrage steht mit Art, Datei, Zeile, Zeichen (0-basiert), Exception-Klasse und Meldung in
// <Datei>-failures.txt (L4: Die 8 gescheiterten Anfragen des Tipp-Szenarios waren ERegularExpressionError aus der
// Ereignis-Vervollständigung nach ":=", ein Fehler im Server, kein Artefakt der Messung).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Benchmark')]
  TDpccMemoryBenchTests = class
  public
    /// <summary>Speicherverlauf mit echter Bibliothek; ohne DPCC_MEMBENCH_OUT sofort fertig.</summary>
    [Test]
    procedure MeasuresLibraryIndex;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections,
  System.Generics.Defaults,
  System.RegularExpressions,
  System.Diagnostics,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.Adapters.InProcess,
  dpcc.Core.Files.WatchedChanges,
  dpcc.Core.Completion.Word,
  dpcc.Core.Completion.AutoOpen,
  dpcc.Common.Index.Contract,
  dpcc.Windows.Diagnostics.ProcessInfo,
  dpcc.Common.Diagnostics.ShutdownLeaks,
  Shell.Diagnostics;

const
  cRequestTimeoutMs = 20000;
  /// <summary>So lange darf der Aufbau auf sich warten lassen, bevor er als fertig gilt (nichts zu tun).</summary>
  cIndexAppearMs = 30000;
  /// <summary>So lange ohne $/progress gilt der Aufbau als fertig.</summary>
  cIndexIdleMs = 3000;
  cIndexMaxMs = 45 * 60 * 1000;
  cOpenMax = 10;
  cFileCount = 50;
  /// <summary>Strg+Klick (NAV): eigene Grenze des Messprogramms für GotoTarget, wie früher das Zeitlimit der IDE.
  /// Die IDE wartet heute nur TLspSession.cMainThreadTimeoutMs und reicht spätere Sprünge nach; wie oft das nötig
  /// wäre, zählt "[definition] Summe".</summary>
  cDefinitionLimitMs = 1000;

type
  TBenchPoint = record
    Name: string;
    ElapsedMs: Int64;
    Memory: TProcessMemory;
    /// <summary>Höchste Private Bytes der Abtastung seit dem vorigen Punkt.</summary>
    MaxPrivate: Int64;
    /// <summary>Kleinste größte freie Region seit dem vorigen Punkt.</summary>
    MinFree: Int64;
    /// <summary>Vom Speichermanager belegte Bytes (ohne seine Pools und Lücken); Private Bytes minus dieser Wert ist
    /// der Verschnitt.</summary>
    Allocated: Int64;
    Report: TShellMemoryReport;
  end;

  /// <summary>Tastet jede Sekunde den Speicher ab und schreibt die CSV.</summary>
  TBenchSampler = class(TThread)
  private
    FLock: TObject;
    FStop: TEvent;
    FLines: TStringList;
    FStarted: UInt64;
    FPhase: string;
    FMaxPrivate: Int64;
    FMinFree: Int64;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Sample;
    procedure SetPhase(const APhase: string);
    /// <summary>Höchste Private Bytes und kleinste freie Region seit dem letzten Aufruf.</summary>
    procedure TakeExtremes(out AMaxPrivate, AMinFree: Int64);
    function ElapsedMs: Int64;
    procedure Finish;
    property Lines: TStringList read FLines;
  end;

  /// <summary>Fragt ununterbrochen in den Dateien AFiles an (Phase 4, Tippen mit gleichzeitigen Anfragen) und misst
  /// jede Antwortzeit. Eigener Zufallsgenerator: Random ist nicht threadsicher.</summary>
  TBenchRequester = class(TThread)
  private
    FSession: TLspSession;
    FFiles: TArray<string>;
    FTexts: TArray<string>;
    FSeed: Cardinal;
    FStop: Boolean;
    /// <summary>Schwelle für das Öffnen beim Tippen (L5); -1 = wie vor L5 ohne Schwelle.</summary>
    FMinChars: Integer;
    function NextRandom(ARange: Integer): Integer;
    procedure Place(const AText: string; const AMark: Char; out ALine, ACharacter: Integer);
    /// <summary>Tippt den Namen ab ACharacter (nach Leerzeichen) in Zeile ALine von AText wie die IDE (L5): True mit
    /// ACharacter hinter dem Zeichen, bei dem TDpccAutoOpen fragt; False, wenn beim ganzen Namen nicht.</summary>
    function TypedPlace(const AText: string; ALine: Integer; var ACharacter: Integer): Boolean;
  protected
    procedure Execute; override;
  public
    Latencies: TList<Double>;
    Failures: Integer;
    /// <summary>Stellen nach ":=" ohne Anfrage, weil die Regel der IDE dort nicht öffnet (L5).</summary>
    AutoSkipped: Integer;
    constructor Create(ASession: TLspSession; const AFiles, ATexts: TArray<string>; AMinChars: Integer);
    destructor Destroy; override;
    procedure Finish;
  end;

  TBench = class
  private
    FGroupFile: string;
    FProjects: TArray<string>;
    FFiles: TArray<string>;
    FTexts: TDictionary<string, string>;
    FOpen: TList<string>;
    FSampler: TBenchSampler;
    FPoints: TList<TBenchPoint>;
    FServer: IDpccLspServer;
    FSession: TLspSession;
    FFailures: Integer;
    FRequests: Integer;
    /// <summary>Antwortzeiten der Anfragen beim Tippen (ms), für &lt;Datei&gt;-latency.csv.</summary>
    FLatencies: TList<Double>;
    procedure LoadProjects;
    procedure PickFiles;
    procedure StartServer;
    procedure StopServer;
    procedure WaitForIndex(const APhase: string);
    procedure Point(const AName: string);
    procedure Requests(ACount: Integer);
    procedure OneRequest;
    /// <summary>Vervollständigungen auf Units der Bibliothek (Nachladen, Phase 3) im Text von AFile.</summary>
    procedure ColdRequests(ACount: Integer; const AFile, ATag: string);
    procedure EnsureOpen(const AFileName: string);
    procedure Rebuild;
    /// <summary>Tippen in einer Unit mit gleichzeitigen Anfragen (Phase 4); misst die Antwortzeiten.</summary>
    procedure Typing(ARounds: Integer);
    /// <summary>Units aus den uses einer Projekt-Unit über der Grenze, dann Nachladen (Phase 4).</summary>
    procedure PinnedLoad(ACount: Integer);
    /// <summary>Suche nach einem häufigen Namen oberster Ebene im Wechsel mit Nachladen (Phase 5).</summary>
    procedure FrequentName(ARounds: Integer);
    /// <summary>Zustand des Nachladens nach einer Anfrage auf AFile.</summary>
    function LazyNow(const AFile: string): TIndexLazyStats;
    /// <summary>"+ Unit" für die Namen aus DPCC_MEMBENCH_IMPORTS (L2).</summary>
    procedure ImportProbe(const ANames: TArray<string>);
    /// <summary>Listen nach raise, on und in Attributklammern aus DPCC_MEMBENCH_LISTS (L4): Einträge, Zeit,
    /// nachgeladene Units.</summary>
    procedure ListProbe(const ALines: TArray<string>);
    /// <summary>Strg+Klick aus DPCC_MEMBENCH_DEFINITIONS (NAV): Ziel, Zeit, nachgeladene Units.</summary>
    procedure DefinitionProbe(const ACases: TArray<string>);
    /// <summary>Die ausgewählten Dateien unter Packages (Units der Projekte).</summary>
    function PackageFiles: TArray<string>;
  public
    constructor Create(const AGroupFile: string);
    destructor Destroy; override;
    procedure Run(ARequests, ARebuilds, ARestarts, ABetween: Integer);
    procedure Save(const AFileName: string);
  end;

type
  /// <summary>Fehleradresse und Aufrufer einer Exception (nur für die Protokolldatei).</summary>
  TBenchStackInfo = record
    Count: Integer;
    Frames: array[0..47] of Pointer;
  end;
  PBenchStackInfo = ^TBenchStackInfo;

const
  /// <summary>Code der Delphi-Exceptions (System, cDelphiException).</summary>
  cBenchDelphiException = $0EEDFADE;
  /// <summary>Höchstens so viele Zeilen je Messung.</summary>
  cBenchExceptionLines = 400;

var
  BenchExceptionFile: string;
  BenchExceptionLock: TObject;
  BenchExceptionLines: Integer;
  /// <summary>Zeilen der gescheiterten Anfragen (L4); '' = aus.</summary>
  BenchFailureFile: string;
  BenchFailureLines: Integer;

function RtlCaptureStackBackTrace(AFramesToSkip, AFramesToCapture: Cardinal; ABackTrace: Pointer;
  ABackTraceHash: PCardinal): Word; stdcall; external kernel32 name 'RtlCaptureStackBackTrace';

/// <summary>Oberes Ende des Stapels dieses Threads (TIB, StackBase).</summary>
{$IFDEF CPUX86}
function BenchStackBase: NativeUInt;
asm
  mov eax, fs:[4]
end;
{$ELSE}
function BenchStackBase: NativeUInt;
asm
  mov rax, gs:[8]
end;
{$ENDIF}

/// <summary>Werte auf dem Stapel, die in den Code des Programms zeigen (Rücksprungadressen, auch bei Routinen
/// ohne Stapelrahmen); höchstens AMax.</summary>
function BenchStackScan(AMax: Integer): string;
var
  mHeaders: PImageNtHeaders;
  mLow, mHigh, mTop, mAddress, mValue: NativeUInt;
  mCount: Integer;
begin
  Result := '';
  mHeaders := PImageNtHeaders(HInstance + NativeUInt(PImageDosHeader(HInstance)^._lfanew));
  mLow := HInstance + mHeaders^.OptionalHeader.BaseOfCode;
  mHigh := mLow + mHeaders^.OptionalHeader.SizeOfCode;
  mAddress := NativeUInt(@mHeaders);
  mTop := BenchStackBase;
  if mTop > mAddress + 64 * 1024 then
  begin
    mTop := mAddress + 64 * 1024;
  end;
  mCount := 0;
  while (mAddress + SizeOf(NativeUInt) <= mTop) and (mCount < AMax) do
  begin
    mValue := PNativeUInt(mAddress)^;
    if (mValue >= mLow) and (mValue < mHigh) then
    begin
      Result := Result + ' ' + IntToHex(mValue, 8);
      Inc(mCount);
    end;
    Inc(mAddress, SizeOf(NativeUInt));
  end;
end;

function BenchCaptureStack(P: System.PExceptionRecord): Pointer;
var
  mInfo: PBenchStackInfo;
  mObject: TObject;
  mLine: string;
  mIndex: Integer;
begin
  Result := nil;
  if (P = nil) or (P^.ExceptionCode <> cBenchDelphiException) or (P^.ExceptObject = nil) then
  begin
    Exit;
  end;
  mObject := TObject(P^.ExceptObject);
  if not ((mObject is ERangeError) or (mObject is EIntOverflow) or (mObject is EAccessViolation)) then
  begin
    Exit;
  end;
  New(mInfo);
  mInfo^.Count := RtlCaptureStackBackTrace(0, Length(mInfo^.Frames), @mInfo^.Frames[0], nil);
  Result := mInfo;
  mLine := Format('%s base %s at %s frames', [mObject.ClassName, IntToHex(NativeUInt(HInstance), 8),
    IntToHex(NativeUInt(P^.ExceptAddr), 8)]);
  for mIndex := 0 to mInfo^.Count - 1 do
  begin
    mLine := mLine + ' ' + IntToHex(NativeUInt(mInfo^.Frames[mIndex]), 8);
  end;
  mLine := mLine + ' raw' + BenchStackScan(64);
  TMonitor.Enter(BenchExceptionLock);
  try
    if (BenchExceptionFile <> '') and (BenchExceptionLines < cBenchExceptionLines) then
    begin
      Inc(BenchExceptionLines);
      TFile.AppendAllText(BenchExceptionFile, mLine + sLineBreak, TEncoding.ASCII);
    end;
  finally
    TMonitor.Exit(BenchExceptionLock);
  end;
end;

function BenchStackString(AInfo: Pointer): string;
begin
  Result := '';
end;

/// <summary>Gescheiterte Anfrage festhalten (L4): Art, Datei, Zeile, Zeichen, Exception; threadsicher.</summary>
procedure BenchNoteFailure(const AKind, AFileName: string; ALine, ACharacter: Integer; E: Exception);
var
  mLine: string;
begin
  mLine := Format('%s %s:%d:%d %s: %s', [AKind, ExtractFileName(AFileName), ALine, ACharacter, E.ClassName,
    E.Message.Replace(#13, ' ').Replace(#10, ' ')]);
  TMonitor.Enter(BenchExceptionLock);
  try
    if (BenchFailureFile <> '') and (BenchFailureLines < cBenchExceptionLines) then
    begin
      Inc(BenchFailureLines);
      TFile.AppendAllText(BenchFailureFile, mLine + sLineBreak, TEncoding.UTF8);
    end;
  finally
    TMonitor.Exit(BenchExceptionLock);
  end;
end;

procedure BenchCleanUpStack(AInfo: Pointer);
begin
  Dispose(PBenchStackInfo(AInfo));
end;

function EnvInt(const AName: string; ADefault: Integer): Integer;
begin
  Result := StrToIntDef(Trim(GetEnvironmentVariable(AName)), ADefault);
end;

function Mb(ABytes: Int64): string;
begin
  if ABytes < 0 then
  begin
    Exit('-1');
  end;
  Result := FormatFloat('0.0', ABytes / (1024 * 1024), TFormatSettings.Invariant);
end;

{ TBenchSampler }

constructor TBenchSampler.Create;
begin
  FLock := TObject.Create;
  FStop := TEvent.Create(nil, True, False, '');
  FLines := TStringList.Create;
  FLines.Add('ms,phase,private_mb,peak_mb,ws_mb,free_mb');
  FStarted := TThread.GetTickCount64;
  FPhase := 'start';
  FMaxPrivate := 0;
  FMinFree := High(Int64);
  inherited Create(False);
end;

destructor TBenchSampler.Destroy;
begin
  Finish;
  inherited;
  FLines.Free;
  FStop.Free;
  FLock.Free;
end;

function TBenchSampler.ElapsedMs: Int64;
begin
  Result := Int64(TThread.GetTickCount64 - FStarted);
end;

procedure TBenchSampler.Sample;
var
  mMemory: TProcessMemory;
begin
  mMemory := TProcessInfo.Memory;
  TMonitor.Enter(FLock);
  try
    FLines.Add(Format('%d,%s,%s,%s,%s,%s', [ElapsedMs, FPhase, Mb(mMemory.PrivateBytes),
      Mb(mMemory.PeakPrivateBytes), Mb(mMemory.WorkingSetBytes), Mb(mMemory.LargestFreeBytes)]));
    FMaxPrivate := Max(FMaxPrivate, mMemory.PrivateBytes);
    if mMemory.LargestFreeBytes >= 0 then
    begin
      FMinFree := Min(FMinFree, mMemory.LargestFreeBytes);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TBenchSampler.Execute;
begin
  NameThreadForDebugging('dpcc.MemoryBench');
  while FStop.WaitFor(1000) = wrTimeout do
  begin
    Sample;
  end;
end;

procedure TBenchSampler.SetPhase(const APhase: string);
begin
  TMonitor.Enter(FLock);
  try
    FPhase := APhase;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TBenchSampler.TakeExtremes(out AMaxPrivate, AMinFree: Int64);
begin
  Sample;
  TMonitor.Enter(FLock);
  try
    AMaxPrivate := FMaxPrivate;
    AMinFree := FMinFree;
    FMaxPrivate := 0;
    FMinFree := High(Int64);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TBenchSampler.Finish;
begin
  if not Finished then
  begin
    FStop.SetEvent;
    WaitFor;
  end;
end;

{ TBench }

constructor TBench.Create(const AGroupFile: string);
begin
  inherited Create;
  FGroupFile := AGroupFile;
  FTexts := TDictionary<string, string>.Create;
  FOpen := TList<string>.Create;
  FPoints := TList<TBenchPoint>.Create;
  FLatencies := TList<Double>.Create;
  FSampler := TBenchSampler.Create;
end;

destructor TBench.Destroy;
begin
  StopServer;
  FLatencies.Free;
  FSampler.Free;
  FPoints.Free;
  FOpen.Free;
  FTexts.Free;
  inherited;
end;

procedure TBench.LoadProjects;
var
  mMatch: TMatch;
  mFolder: string;
begin
  mFolder := ExtractFilePath(FGroupFile);
  FProjects := nil;
  for mMatch in TRegEx.Matches(TFile.ReadAllText(FGroupFile), '<Projects Include="([^"]+)"') do
  begin
    FProjects := FProjects + [ExpandFileName(TPath.Combine(mFolder, mMatch.Groups[1].Value))];
  end;
  Assert.IsTrue(Length(FProjects) > 0, 'Projekte in ' + FGroupFile);
end;

procedure TBench.PickFiles;
var
  mAll: TArray<string>;
  mFolder, mFile: string;
  mIndex, mPick: Integer;
begin
  mAll := nil;
  for mFolder in ['Packages', 'Application'] do
  begin
    if TDirectory.Exists(TPath.Combine(ExtractFilePath(FGroupFile), mFolder)) then
    begin
      mAll := mAll + TDirectory.GetFiles(TPath.Combine(ExtractFilePath(FGroupFile), mFolder), '*.pas',
        TSearchOption.soAllDirectories);
    end;
  end;
  TArray.Sort<string>(mAll);
  // Immer dieselbe Auswahl: Läufe vor und nach einer Änderung bleiben vergleichbar.
  RandSeed := 4711;
  FFiles := nil;
  for mIndex := 1 to Min(cFileCount, Length(mAll)) do
  begin
    mPick := Random(Length(mAll));
    mFile := mAll[mPick];
    if not FTexts.ContainsKey(mFile) then
    begin
      FTexts.Add(mFile, TFile.ReadAllText(mFile));
      FFiles := FFiles + [mFile];
    end;
  end;
end;

procedure TBench.StartServer;
begin
  FServer := TLspInProcessServer.Create;
  FSession := TLspSession.Create(FServer.Client, cRequestTimeoutMs);
  FSession.SetProjects(FProjects);
  FSession.Initialize;
  Assert.IsTrue(FSession.Initialized, 'initialize beantwortet');
  FOpen.Clear;
end;

procedure TBench.StopServer;
begin
  if FServer = nil then
  begin
    Exit;
  end;
  // Wie StopSessionNow im Plugin: Client schließen, Sitzung freigeben, dann den Server.
  FServer.Client.Close;
  FreeAndNil(FSession);
  FServer := nil;
end;

procedure TBench.WaitForIndex(const APhase: string);
var
  mStarted, mBusy: UInt64;
  mSeen: Boolean;
  mPercent: Integer;
begin
  FSampler.SetPhase(APhase);
  mStarted := TThread.GetTickCount64;
  mBusy := mStarted;
  mSeen := False;
  while TThread.GetTickCount64 - mStarted < cIndexMaxMs do
  begin
    if FSession.Indexing(mPercent) then
    begin
      mSeen := True;
      mBusy := TThread.GetTickCount64;
    end
    else if (mSeen and (TThread.GetTickCount64 - mBusy >= cIndexIdleMs)) or
      (not mSeen and (TThread.GetTickCount64 - mStarted >= cIndexAppearMs)) then
    begin
      Exit;
    end;
    TThread.Sleep(100);
  end;
end;

procedure TBench.Point(const AName: string);
var
  mPoint: TBenchPoint;
begin
  // Frischer Stand des Index: Die nächste Anfrage misst und schreibt die Zeile „mem“ (TShellMemoryReport.Latest).
  if FSession <> nil then
  begin
    TShellMemoryReport.Request;
    OneRequest;
  end;
  mPoint.Name := AName;
  mPoint.ElapsedMs := FSampler.ElapsedMs;
  FSampler.TakeExtremes(mPoint.MaxPrivate, mPoint.MinFree);
  mPoint.Memory := TProcessInfo.Memory;
  mPoint.Allocated := TShutdownLeaks.AllocatedBytes;
  mPoint.Report := TShellMemoryReport.Latest;
  FPoints.Add(mPoint);
  System.Writeln(Format('[mem] %-14s private %s MB peak %s MB max %s MB free %s MB index %s MB units %d alloc %s MB',
    [AName, Mb(mPoint.Memory.PrivateBytes), Mb(mPoint.Memory.PeakPrivateBytes), Mb(mPoint.MaxPrivate),
     Mb(mPoint.Memory.LargestFreeBytes), Mb(mPoint.Report.IndexBytes), mPoint.Report.Units,
     Mb(mPoint.Allocated)]));
  System.Writeln(Format('[lazy] %-13s loaded %d pinned %d evictable %d (%s MB) cold %d catalog %s MB loads %d ' +
    'evicted %d loadms median %s max %s largest %d KB in %s ms', [AName, mPoint.Report.Lazy.Loaded,
    mPoint.Report.Lazy.Pinned, mPoint.Report.Lazy.Evictable, Mb(mPoint.Report.Lazy.EvictableBytes),
    mPoint.Report.Lazy.Cold, Mb(mPoint.Report.Lazy.CatalogBytes), mPoint.Report.Lazy.Loads,
    mPoint.Report.Lazy.Evictions, FormatFloat('0.0', mPoint.Report.Lazy.LoadMedianMs, TFormatSettings.Invariant),
    FormatFloat('0.0', mPoint.Report.Lazy.LoadMaxMs, TFormatSettings.Invariant),
    mPoint.Report.Lazy.LargestLoadBytes div 1024, FormatFloat('0.0', mPoint.Report.Lazy.LargestLoadMs,
    TFormatSettings.Invariant)]));
end;

procedure TBench.EnsureOpen(const AFileName: string);
begin
  if FOpen.Contains(AFileName) then
  begin
    Exit;
  end;
  // Höchstens cOpenMax Dateien offen, wie ein Editor mit wenigen Reitern.
  if FOpen.Count >= cOpenMax then
  begin
    FSession.Close(FOpen[0]);
    FOpen.Delete(0);
  end;
  FSession.Sync(AFileName, FTexts[AFileName]);
  FOpen.Add(AFileName);
end;

/// <summary>Zeile und Spalte (0-basiert) einer zufälligen Stelle: hinter dem letzten "." bzw. "(" einer Zeile,
/// sonst am Zeilenende.</summary>
procedure RandomPlace(const AText: string; const AMark: Char; out ALine, ACharacter: Integer);
var
  mLines: TArray<string>;
  mTry, mPos: Integer;
begin
  mLines := AText.Split([#10]);
  ALine := 0;
  ACharacter := 0;
  if Length(mLines) = 0 then
  begin
    Exit;
  end;
  for mTry := 1 to 20 do
  begin
    ALine := Random(Length(mLines));
    mPos := mLines[ALine].TrimRight([#13]).LastIndexOf(AMark);
    if mPos >= 0 then
    begin
      ACharacter := mPos + 1;
      Exit;
    end;
  end;
  ACharacter := Length(mLines[ALine].TrimRight([#13]));
end;

procedure TBench.OneRequest;
var
  mFile: string;
  mKind, mLine, mCharacter: Integer;
  mResponse: TJSONValue;
begin
  mFile := FFiles[Random(Length(FFiles))];
  mKind := Random(100);
  mLine := 0;
  mCharacter := 0;
  try
    EnsureOpen(mFile);
    // 60 % Vervollständigung, 25 % Hover, 10 % Parameterhilfe, 5 % Vervollständigung ohne Punkt.
    if mKind < 60 then
    begin
      RandomPlace(FTexts[mFile], '.', mLine, mCharacter);
      mResponse := FSession.Completion(mFile, mLine, mCharacter, cRequestTimeoutMs);
      mResponse.Free;
    end
    else if mKind < 85 then
    begin
      RandomPlace(FTexts[mFile], ' ', mLine, mCharacter);
      FSession.Hover(mFile, FTexts[mFile], mLine, mCharacter, cRequestTimeoutMs);
    end
    else if mKind < 95 then
    begin
      RandomPlace(FTexts[mFile], '(', mLine, mCharacter);
      mResponse := FSession.SignatureHelp(mFile, mLine, mCharacter, cRequestTimeoutMs);
      mResponse.Free;
    end
    else
    begin
      RandomPlace(FTexts[mFile], #0, mLine, mCharacter);
      mResponse := FSession.Completion(mFile, mLine, mCharacter, cRequestTimeoutMs);
      mResponse.Free;
    end;
    Inc(FRequests);
  except
    // Eine gescheiterte Anfrage zählt und steht in <Datei>-failures.txt; das Messprogramm misst Speicher.
    on E: Exception do
    begin
      Inc(FFailures);
      BenchNoteFailure(Format('request %d', [mKind]), mFile, mLine, mCharacter, E);
    end;
  end;
end;

procedure TBench.Requests(ACount: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 1 to ACount do
  begin
    OneRequest;
  end;
end;

function LibraryFolder: string;
begin
  Result := Trim(GetEnvironmentVariable('DPCC_MEMBENCH_LIBDIR'));
  if Result = '' then
  begin
    Result := 'C:\Program Files (x86)\Embarcadero\Studio\37.0\source';
  end;
end;

/// <summary>Alle .pas unter dem Ordner der Bibliothek ohne WinRT (nicht im Bibliotheks-Cache, c1), sortiert.</summary>
function LibraryFiles: TArray<string>;
var
  mName: string;
begin
  Result := nil;
  if not TDirectory.Exists(LibraryFolder) then
  begin
    Exit;
  end;
  for mName in TDirectory.GetFiles(LibraryFolder, '*.pas', TSearchOption.soAllDirectories) do
  begin
    if Pos('\winrt\', LowerCase(mName)) = 0 then
    begin
      Result := Result + [mName];
    end;
  end;
  TArray.Sort<string>(Result);
end;

procedure TBench.ColdRequests(ACount: Integer; const AFile, ATag: string);
var
  mFile, mOwn, mName, mText: string;
  mAll: TArray<string>;
  mIndex, mFailed: Integer;
  mWatch: TStopwatch;
  mTotal, mMax, mMs: Double;
  mResponse: TJSONValue;
begin
  if ACount <= 0 then
  begin
    Exit;
  end;
  mAll := LibraryFiles;
  if Length(mAll) = 0 then
  begin
    Exit;
  end;
  RandSeed := 815;
  mFile := AFile;
  mOwn := ChangeFileExt(ExtractFileName(mFile), '');
  EnsureOpen(mFile);
  mTotal := 0;
  mMax := 0;
  mFailed := 0;
  for mIndex := 1 to ACount do
  begin
    mName := ChangeFileExt(ExtractFileName(mAll[Random(Length(mAll))]), '');
    mText := Format('unit %s;'#13#10'interface'#13#10'uses %s;'#13#10'implementation'#13#10'procedure BenchProbe;' +
      #13#10'begin'#13#10'  %s.'#13#10'end;'#13#10'end.'#13#10, [mOwn, mName, mName]);
    try
      FSession.Sync(mFile, mText);
      mWatch := TStopwatch.StartNew;
      mResponse := FSession.Completion(mFile, 6, Length(mName) + 3, cRequestTimeoutMs);
      mResponse.Free;
      mMs := mWatch.Elapsed.TotalMilliseconds;
      mTotal := mTotal + mMs;
      mMax := Max(mMax, mMs);
      Inc(FRequests);
    except
      on Exception do
      begin
        Inc(FFailures);
        Inc(mFailed);
      end;
    end;
  end;
  // Wieder der Originaltext (uses der Projekt-Unit wie vorher).
  FSession.Sync(mFile, FTexts[mFile]);
  System.Writeln(Format('[%s] %d Vervollständigungen auf Bibliotheks-Units, gescheitert %d, Mittel %s ms, max %s ms',
    [ATag, ACount, mFailed, FormatFloat('0.0', mTotal / ACount, TFormatSettings.Invariant), FormatFloat('0.0', mMax,
    TFormatSettings.Invariant)]));
end;

{ TBenchRequester }

constructor TBenchRequester.Create(ASession: TLspSession; const AFiles, ATexts: TArray<string>; AMinChars: Integer);
begin
  FMinChars := AMinChars;
  FSession := ASession;
  FFiles := AFiles;
  FTexts := ATexts;
  FSeed := 4242;
  Latencies := TList<Double>.Create;
  inherited Create(False);
end;

destructor TBenchRequester.Destroy;
begin
  Finish;
  inherited;
  Latencies.Free;
end;

procedure TBenchRequester.Finish;
begin
  FStop := True;
  if not Finished then
  begin
    WaitFor;
  end;
end;

function TBenchRequester.NextRandom(ARange: Integer): Integer;
begin
  // Lineare Kongruenz (Numerical Recipes); reicht für die Auswahl von Stellen.
  FSeed := Cardinal(UInt64(FSeed) * 1664525 + 1013904223);
  Result := Integer((UInt64(FSeed shr 8) * UInt64(ARange)) shr 24);
end;

procedure TBenchRequester.Place(const AText: string; const AMark: Char; out ALine, ACharacter: Integer);
var
  mLines: TArray<string>;
  mTry, mPos: Integer;
begin
  mLines := AText.Split([#10]);
  ALine := 0;
  ACharacter := 0;
  if Length(mLines) = 0 then
  begin
    Exit;
  end;
  for mTry := 1 to 20 do
  begin
    ALine := NextRandom(Length(mLines));
    mPos := mLines[ALine].TrimRight([#13]).LastIndexOf(AMark);
    if mPos >= 0 then
    begin
      ACharacter := mPos + 1;
      Exit;
    end;
  end;
  ACharacter := Length(mLines[ALine].TrimRight([#13]));
end;

function TBenchRequester.TypedPlace(const AText: string; ALine: Integer; var ACharacter: Integer): Boolean;
var
  mLines: TArray<string>;
  mLineText: string;
  mStart, mEnd, mTyped: Integer;
begin
  Result := False;
  mLines := AText.Split([#10]);
  if (ALine < 0) or (ALine > High(mLines)) then
  begin
    Exit;
  end;
  mLineText := mLines[ALine].TrimRight([#13]);
  mStart := ACharacter;
  while (mStart < Length(mLineText)) and (mLineText[mStart + 1] = ' ') do
  begin
    Inc(mStart);
  end;
  mEnd := TDpccWord.EndAfter(mLineText, mStart);
  // Zeile, wie sie beim Tippen aussieht: bis zum Cursor. Ab der ersten Anfrage filtert die Liste nur noch.
  for mTyped := mStart + 1 to mEnd do
  begin
    if TDpccAutoOpen.Action(TDpccCompletionSource.Typing, Copy(mLineText, 1, mTyped), mTyped, False,
      FMinChars) = TDpccAutoOpenAction.Query then
    begin
      ACharacter := mTyped;
      Exit(True);
    end;
  end;
end;

procedure TBenchRequester.Execute;
var
  mPick, mKind, mLine, mCharacter: Integer;
  mWatch: TStopwatch;
  mResponse: TJSONValue;
  mWhat: string;
begin
  NameThreadForDebugging('dpcc.MemoryBench.Requests');
  while not FStop do
  begin
    mPick := NextRandom(Length(FFiles));
    mKind := NextRandom(100);
    mLine := 0;
    mCharacter := 0;
    mWhat := 'completion.';
    try
      mWatch := TStopwatch.StartNew;
      // 50 % Vervollständigung nach ".", 20 % Hover, 15 % Parameterhilfe, 15 % Vervollständigung nach ":=" (Werte,
      // sucht Typen über FindSymbols).
      if mKind < 50 then
      begin
        Place(FTexts[mPick], '.', mLine, mCharacter);
        mResponse := FSession.Completion(FFiles[mPick], mLine, mCharacter, cRequestTimeoutMs);
        mResponse.Free;
      end
      else if mKind < 70 then
      begin
        mWhat := 'hover';
        Place(FTexts[mPick], ' ', mLine, mCharacter);
        FSession.Hover(FFiles[mPick], FTexts[mPick], mLine, mCharacter, cRequestTimeoutMs);
      end
      else if mKind < 85 then
      begin
        mWhat := 'signature';
        Place(FTexts[mPick], '(', mLine, mCharacter);
        mResponse := FSession.SignatureHelp(FFiles[mPick], mLine, mCharacter, cRequestTimeoutMs);
        mResponse.Free;
      end
      else
      begin
        mWhat := 'completion:=';
        Place(FTexts[mPick], '=', mLine, mCharacter);
        Inc(mCharacter);
        // L5: wie die IDE erst ab completion.autoMinChars getippten Zeichen; darunter keine Anfrage.
        if (FMinChars >= 0) and not TypedPlace(FTexts[mPick], mLine, mCharacter) then
        begin
          Inc(AutoSkipped);
          Continue;
        end;
        mWatch := TStopwatch.StartNew;
        mResponse := FSession.Completion(FFiles[mPick], mLine, mCharacter, cRequestTimeoutMs);
        mResponse.Free;
      end;
      Latencies.Add(mWatch.Elapsed.TotalMilliseconds);
    except
      on E: Exception do
      begin
        Inc(Failures);
        BenchNoteFailure('typing ' + mWhat, FFiles[mPick], mLine, mCharacter, E);
      end;
    end;
  end;
end;

/// <summary>Stelle hinter "implementation" für die Tipp-Zeile; -1, wenn es keine gibt.</summary>
function TypingAt(const AText: string): Integer;
var
  mPos: Integer;
begin
  mPos := Pos(#10'implementation', AText);
  if mPos = 0 then
  begin
    Exit(-1);
  end;
  Result := Pos(#10, AText, mPos + 1);
end;

function Percentile(const ASorted: TArray<Double>; APercent: Integer): Double;
begin
  if Length(ASorted) = 0 then
  begin
    Exit(0);
  end;
  Result := ASorted[Min(High(ASorted), (Length(ASorted) * APercent) div 100)];
end;

procedure TBench.Typing(ARounds: Integer);
var
  mFile, mText, mTyped: string;
  mFiles, mTexts: TArray<string>;
  mAt, mRound, mKey, mIndex, mMinChars: Integer;
  mRequester: TBenchRequester;
  mSorted: TArray<Double>;
begin
  if (ARounds <= 0) or (Length(FFiles) < 3) then
  begin
    Exit;
  end;
  // Getippt wird in einer Unit mit implementation-Teil; die anderen fragt der zweite Thread an.
  mFile := '';
  mFiles := nil;
  mTexts := nil;
  for mIndex := 0 to High(FFiles) do
  begin
    if (mFile = '') and (Pos('\Packages\', FFiles[mIndex]) > 0) and (TypingAt(FTexts[FFiles[mIndex]]) > 0) then
    begin
      mFile := FFiles[mIndex];
    end
    else if Length(mFiles) < 6 then
    begin
      mFiles := mFiles + [FFiles[mIndex]];
      mTexts := mTexts + [FTexts[FFiles[mIndex]]];
    end;
  end;
  if mFile = '' then
  begin
    Exit;
  end;
  // Alle vorher öffnen: Der zweite Thread benutzt die Sitzung, EnsureOpen nicht.
  EnsureOpen(mFile);
  for mIndex := 0 to High(mFiles) do
  begin
    EnsureOpen(mFiles[mIndex]);
  end;
  mText := FTexts[mFile];
  mAt := TypingAt(mText);
  mTyped := '';
  // Messszenario: Vorgabe 5 (die Einstellung hat seit NAV die Vorgabe 0 = aus).
  mMinChars := EnvInt('DPCC_MEMBENCH_AUTOMIN', 5);
  mRequester := TBenchRequester.Create(FSession, mFiles, mTexts, mMinChars);
  try
    for mRound := 1 to ARounds do
    begin
      // Vier Tastendrücke wie beim Tippen, dann die Tipp-Pause: Der Server übernimmt den Text (ApplyText).
      for mKey := 1 to 4 do
      begin
        mTyped := mTyped + Chr(Ord('a') + (mRound + mKey) mod 26);
        FSession.Sync(mFile, Copy(mText, 1, mAt) + '// ' + mTyped + #13#10 + Copy(mText, mAt + 1, MaxInt));
        TThread.Sleep(100);
      end;
      TThread.Sleep(700);
    end;
    mRequester.Finish;
    FLatencies.AddRange(mRequester.Latencies);
    mSorted := mRequester.Latencies.ToArray;
    TArray.Sort<Double>(mSorted);
    System.Writeln(Format('[typing] Runden %d Anfragen %d gescheitert %d median %s ms p95 %s ms p99 %s ms max %s ms',
      [ARounds, Length(mSorted), mRequester.Failures, FormatFloat('0.0', Percentile(mSorted, 50),
      TFormatSettings.Invariant), FormatFloat('0.0', Percentile(mSorted, 95), TFormatSettings.Invariant),
      FormatFloat('0.0', Percentile(mSorted, 99), TFormatSettings.Invariant), FormatFloat('0.0',
      Percentile(mSorted, 100), TFormatSettings.Invariant)]));
    System.Writeln(Format('[typing] nach ":=" ab %d Zeichen (-1 = ohne Schwelle): ohne Anfrage %d',
      [mMinChars, mRequester.AutoSkipped]));
    Inc(FRequests, Length(mSorted));
    Inc(FFailures, mRequester.Failures);
  finally
    mRequester.Free;
  end;
  FSession.Sync(mFile, FTexts[mFile]);
end;

function TBench.PackageFiles: TArray<string>;
var
  mFile: string;
begin
  Result := nil;
  for mFile in FFiles do
  begin
    if Pos('\Packages\', mFile) > 0 then
    begin
      Result := Result + [mFile];
    end;
  end;
end;

function TBench.LazyNow(const AFile: string): TIndexLazyStats;
var
  mResponse: TJSONValue;
begin
  TShellMemoryReport.Request;
  try
    // Billig und ohne den Text neu zu schicken (Hover gliche ihn an; eine Vervollständigung am Anfang listete alles
    // Sichtbare).
    mResponse := FSession.SignatureHelp(AFile, 0, 0, cRequestTimeoutMs);
    mResponse.Free;
  except
    on Exception do
      Inc(FFailures);
  end;
  Result := TShellMemoryReport.Latest.Lazy;
end;

/// <summary>Units für die uses (DPCC_MEMBENCH_PINNEDUNITS, sonst die DPCC_MEMBENCH_PINNEDCOUNT größten Dateien der
/// Bibliothek; viele davon stehen schon in der Hülle der Projekte).</summary>
function PinnedUnitNames: TArray<string>;
var
  mList: string;
  mFiles: TArray<string>;
  mSizes: TArray<TPair<Int64, string>>;
  mIndex: Integer;
begin
  mList := Trim(GetEnvironmentVariable('DPCC_MEMBENCH_PINNEDUNITS'));
  if mList <> '' then
  begin
    Exit(mList.Split([','], TStringSplitOptions.ExcludeEmpty));
  end;
  mFiles := LibraryFiles;
  SetLength(mSizes, Length(mFiles));
  for mIndex := 0 to High(mFiles) do
  begin
    mSizes[mIndex] := TPair<Int64, string>.Create(TFile.GetSize(mFiles[mIndex]), mFiles[mIndex]);
  end;
  TArray.Sort<TPair<Int64, string>>(mSizes, TComparer<TPair<Int64, string>>.Construct(
    function(const ALeft, ARight: TPair<Int64, string>): Integer
    begin
      Result := CompareValue(ARight.Key, ALeft.Key);
      if Result = 0 then
      begin
        Result := CompareText(ALeft.Value, ARight.Value);
      end;
    end));
  Result := nil;
  for mIndex := 0 to Min(EnvInt('DPCC_MEMBENCH_PINNEDCOUNT', 80) - 1, High(mSizes)) do
  begin
    Result := Result + [ChangeFileExt(ExtractFileName(mSizes[mIndex].Value), '')];
  end;
end;

procedure TBench.PinnedLoad(ACount: Integer);
var
  mFile, mOther, mOwn, mText: string;
  mNames, mFiles: TArray<string>;
  mIndex: Integer;
  mResponse: TJSONValue;
  mBefore, mAfter: TIndexLazyStats;
begin
  if ACount <= 0 then
  begin
    Exit;
  end;
  mNames := PinnedUnitNames;
  if Length(mNames) = 0 then
  begin
    Exit;
  end;
  // Units der Projekte (unter Packages): Nur deren getippte uses kennt der Index.
  mFiles := PackageFiles;
  if Length(mFiles) < 2 then
  begin
    Exit;
  end;
  mFile := mFiles[0];
  mOther := mFiles[1];
  mOwn := ChangeFileExt(ExtractFileName(mFile), '');
  mText := Format('unit %s;'#13#10'interface'#13#10'uses %s;'#13#10'implementation'#13#10'procedure BenchPinned;'#13#10 +
    'begin'#13#10, [mOwn, string.Join(', ', mNames)]);
  for mIndex := 0 to High(mNames) do
  begin
    mText := mText + '  ' + mNames[mIndex] + '.;'#13#10;
  end;
  mText := mText + 'end;'#13#10'end.'#13#10;
  // Beide offen (die andere zuerst, damit sie mFile nicht schließt): Erst eine Änderung (didChange) übernimmt der
  // Server nach der Tipp-Pause in den Index, das Öffnen (didOpen) nicht.
  EnsureOpen(mOther);
  EnsureOpen(mFile);
  FSession.Sync(mFile, mText);
  // Tipp-Pause abwarten: erst dann stehen die uses im Index und halten die Units.
  TThread.Sleep(1500);
  for mIndex := 0 to High(mNames) do
  begin
    try
      mResponse := FSession.Completion(mFile, 6 + mIndex, Length(mNames[mIndex]) + 3, cRequestTimeoutMs);
      mResponse.Free;
    except
      on Exception do
        Inc(FFailures);
    end;
  end;
  mBefore := LazyNow(mFile);
  ColdRequests(ACount, mOther, 'pinned-cold');
  mAfter := LazyNow(mFile);
  System.Writeln(Format('[pinned] uses %d Units, danach %d Vervollständigungen: nachgeladen %d verdrängt %d; ' +
    'geladen %d gepinnt %d verdrängbar %d (%s MB)', [Length(mNames), ACount, mAfter.Loads - mBefore.Loads,
    mAfter.Evictions - mBefore.Evictions, mAfter.Loaded, mAfter.Pinned, mAfter.Evictable,
    Mb(mAfter.EvictableBytes)]));
  FSession.Sync(mFile, FTexts[mFile]);
end;

procedure TBench.FrequentName(ARounds: Integer);
var
  mFile, mOther, mOwn, mOtherOwn, mName, mUnit: string;
  mNames, mFiles, mAll: TArray<string>;
  mRound, mCold, mFailed: Integer;
  mWatch: TStopwatch;
  mResponse: TJSONValue;
  mTimes: TList<Double>;
  mSorted: TArray<Double>;
  mBefore, mAfter, mNow: TIndexLazyStats;
  mMaxEvictable: Int64;
  mMaxLoaded: Integer;
begin
  mNames := Trim(GetEnvironmentVariable('DPCC_MEMBENCH_FREQNAMES')).Split([','], TStringSplitOptions.ExcludeEmpty);
  if Length(mNames) = 0 then
  begin
    mNames := ['Register'];
  end;
  mFiles := PackageFiles;
  mAll := LibraryFiles;
  if (ARounds <= 0) or (Length(mFiles) < 2) or (Length(mAll) = 0) then
  begin
    Exit;
  end;
  mFile := mFiles[0];
  mOther := mFiles[1];
  mOwn := ChangeFileExt(ExtractFileName(mFile), '');
  mOtherOwn := ChangeFileExt(ExtractFileName(mOther), '');
  EnsureOpen(mOther);
  EnsureOpen(mFile);
  RandSeed := 2025;
  mTimes := TList<Double>.Create;
  try
    mFailed := 0;
    mMaxEvictable := 0;
    mMaxLoaded := 0;
    mBefore := LazyNow(mFile);
    for mRound := 1 to ARounds do
    begin
      mName := mNames[(mRound - 1) mod Length(mNames)];
      // Variable eines Typs, den der Bereich nicht kennt: Die Vervollständigung nach ":=" sucht ihn im ganzen Index
      // (FindSymbols) und lädt dafür alle kalten Units, deren Katalog den Namen hat.
      try
        FSession.Sync(mFile, Format('unit %s;'#13#10'interface'#13#10'implementation'#13#10'procedure BenchFrequent;' +
          #13#10'var'#13#10'  V: %s;'#13#10'begin'#13#10'  V := '#13#10'end;'#13#10'end.'#13#10, [mOwn, mName]));
        mWatch := TStopwatch.StartNew;
        mResponse := FSession.Completion(mFile, 7, 7, cRequestTimeoutMs);
        mResponse.Free;
        mTimes.Add(mWatch.Elapsed.TotalMilliseconds);
        Inc(FRequests);
      except
        on Exception do
        begin
          Inc(FFailures);
          Inc(mFailed);
        end;
      end;
      mNow := LazyNow(mFile);
      mMaxEvictable := Max(mMaxEvictable, mNow.EvictableBytes);
      mMaxLoaded := Max(mMaxLoaded, mNow.Loaded);
      // Dann Nachladen anderer Units: verdrängt wieder.
      for mCold := 1 to 5 do
      begin
        mUnit := ChangeFileExt(ExtractFileName(mAll[Random(Length(mAll))]), '');
        try
          FSession.Sync(mOther, Format('unit %s;'#13#10'interface'#13#10'uses %s;'#13#10'implementation'#13#10 +
            'procedure BenchProbe;'#13#10'begin'#13#10'  %s.'#13#10'end;'#13#10'end.'#13#10,
            [mOtherOwn, mUnit, mUnit]));
          mResponse := FSession.Completion(mOther, 6, Length(mUnit) + 3, cRequestTimeoutMs);
          mResponse.Free;
          Inc(FRequests);
        except
          on Exception do
          begin
            Inc(FFailures);
            Inc(mFailed);
          end;
        end;
      end;
    end;
    mAfter := LazyNow(mFile);
    mSorted := mTimes.ToArray;
    TArray.Sort<Double>(mSorted);
    System.Writeln(Format('[frequent] Namen %s Runden %d gescheitert %d: nachgeladen %d verdrängt %d; ' +
      'Suche median %s ms max %s ms; nach der Suche höchstens %s MB verdrängbar, %d geladen',
      [string.Join(',', mNames), ARounds, mFailed, mAfter.Loads - mBefore.Loads, mAfter.Evictions - mBefore.Evictions, FormatFloat('0.0', Percentile(mSorted, 50),
      TFormatSettings.Invariant), FormatFloat('0.0', Percentile(mSorted, 100), TFormatSettings.Invariant),
      Mb(mMaxEvictable), mMaxLoaded]));
  finally
    mTimes.Free;
  end;
  FSession.Sync(mFile, FTexts[mFile]);
  FSession.Sync(mOther, FTexts[mOther]);
end;

procedure TBench.Rebuild;
begin
  // Wie „.dproj gespeichert“: Der Server lädt das Projekt neu und baut den Index auf (Reload). Die Sitzung schickt
  // gesammelte Änderungen mit der nächsten Anfrage.
  FSession.FilesChanged([TDpccFileChange.Create(FProjects[0], TDpccFileChangeKind.Changed)]);
  OneRequest;
end;

procedure TBench.ImportProbe(const ANames: TArray<string>);
var
  mFile, mOwn, mName, mText, mJson, mItem: string;
  mWatch: TStopwatch;
  mResponse: TJSONValue;
  mAt, mEnd: Integer;
  mState: string;
begin
  mFile := FFiles[0];
  mOwn := ChangeFileExt(ExtractFileName(mFile), '');
  EnsureOpen(mFile);
  for mName in ANames do
  begin
    mText := Format('unit %s;'#13#10'interface'#13#10'implementation'#13#10'procedure BenchProbe;'#13#10'begin'#13#10 +
      '  %s'#13#10'end;'#13#10'end.'#13#10, [mOwn, Trim(mName)]);
    try
      FSession.Sync(mFile, mText);
      mWatch := TStopwatch.StartNew;
      mResponse := FSession.Completion(mFile, 5, Length(Trim(mName)) + 2, cRequestTimeoutMs);
      try
        mJson := mResponse.ToJSON;
      finally
        mResponse.Free;
      end;
      Inc(FRequests);
      // Der Eintrag mit genau diesem Namen.
      mItem := '';
      mAt := Pos('"label":"' + Trim(mName) + '"', mJson);
      if mAt > 0 then
      begin
        mEnd := Pos('"label":', mJson, mAt + 8);
        if mEnd = 0 then
        begin
          mEnd := mAt + 400;
        end;
        mItem := Copy(mJson, mAt, Min(mEnd - mAt, 400));
      end;
      mState := 'nicht angeboten';
      if mItem <> '' then
      begin
        mState := 'angeboten';
      end;
      System.Writeln(Format('[import] %s: %s, %s ms, %s', [Trim(mName), mState,
        FormatFloat('0.0', mWatch.Elapsed.TotalMilliseconds, TFormatSettings.Invariant), mItem]));
    except
      on E: Exception do
      begin
        Inc(FFailures);
        System.Writeln(Format('[import] %s: Fehler %s', [Trim(mName), E.ClassName]));
      end;
    end;
  end;
  FSession.Sync(mFile, FTexts[mFile]);
end;

procedure TBench.ListProbe(const ALines: TArray<string>);
var
  mFile, mOwn, mLine, mText, mJson: string;
  mWatch: TStopwatch;
  mResponse: TJSONValue;
  mBefore, mAfter: TIndexLazyStats;
  mRow, mIndent, mItems, mAt: Integer;
begin
  mFile := FFiles[0];
  mOwn := ChangeFileExt(ExtractFileName(mFile), '');
  EnsureOpen(mFile);
  for mLine in ALines do
  begin
    // Zeile 6 (0-basiert 5): im Rumpf bzw. vor der Deklaration.
    if Trim(mLine).StartsWith('[') then
    begin
      mText := Format('unit %s;'#13#10'interface'#13#10'uses System.SysUtils;'#13#10'type'#13#10'  TBenchProbe = class'#13#10 +
        '    %s'#13#10'    procedure Run;'#13#10'  end;'#13#10'implementation'#13#10'procedure TBenchProbe.Run;'#13#10 +
        'begin'#13#10'end;'#13#10'end.'#13#10, [mOwn, Trim(mLine)]);
      mRow := 5;
      mIndent := 4;
    end
    else
    begin
      mText := Format('unit %s;'#13#10'interface'#13#10'uses System.SysUtils;'#13#10'implementation'#13#10 +
        'procedure BenchProbe;'#13#10'begin'#13#10'  %s'#13#10'end;'#13#10'end.'#13#10, [mOwn, Trim(mLine)]);
      mRow := 6;
      mIndent := 2;
    end;
    try
      FSession.Sync(mFile, mText);
      mBefore := LazyNow(mFile);
      mWatch := TStopwatch.StartNew;
      mResponse := FSession.Completion(mFile, mRow, mIndent + Length(Trim(mLine)), cRequestTimeoutMs);
      try
        mJson := mResponse.ToJSON;
      finally
        mResponse.Free;
      end;
      mWatch.Stop;
      mAfter := LazyNow(mFile);
      Inc(FRequests);
      mItems := 0;
      mAt := Pos('"label":', mJson);
      while mAt > 0 do
      begin
        Inc(mItems);
        mAt := Pos('"label":', mJson, mAt + 8);
      end;
      System.Writeln(Format('[lists] %s: %d Einträge, %s ms, nachgeladen %d, kalt vorher %d nachher %d',
        [Trim(mLine), mItems, FormatFloat('0.0', mWatch.Elapsed.TotalMilliseconds, TFormatSettings.Invariant),
        mAfter.Loads - mBefore.Loads, mBefore.Cold, mAfter.Cold]));
    except
      on E: Exception do
      begin
        Inc(FFailures);
        System.Writeln(Format('[lists] %s: Fehler %s', [Trim(mLine), E.ClassName]));
      end;
    end;
  end;
  FSession.Sync(mFile, FTexts[mFile]);
end;

procedure TBench.DefinitionProbe(const ACases: TArray<string>);
var
  mFile, mOwn, mCase, mText, mWord, mLine: string;
  mParts: TArray<string>;
  mWatch: TStopwatch;
  mBefore, mAfter: TIndexLazyStats;
  mLocation: TLspLocation;
  mFound: Boolean;
  mTimes: TList<Double>;
  mHits, mAt, mLate: Integer;
  mMedian: Double;
begin
  mFile := FFiles[0];
  mOwn := ChangeFileExt(ExtractFileName(mFile), '');
  EnsureOpen(mFile);
  mHits := 0;
  mLate := 0;
  mTimes := TList<Double>.Create;
  try
    for mCase in ACases do
    begin
      mParts := mCase.Split(['#']);
      if Length(mParts) < 3 then
      begin
        Continue;
      end;
      mLine := mParts[1];
      mWord := Trim(mParts[2]);
      // Zeile 6 (0-basiert 5) im Rumpf von BenchProbe.
      mText := Format('unit %s;'#13#10'interface'#13#10'uses %s;'#13#10'implementation'#13#10 +
        'procedure BenchProbe;'#13#10'begin'#13#10'%s'#13#10'end;'#13#10'end.'#13#10, [mOwn, Trim(mParts[0]), mLine]);
      mAt := Pos(mWord, mLine) - 1;
      try
        FSession.Sync(mFile, mText);
        mBefore := LazyNow(mFile);
        mWatch := TStopwatch.StartNew;
        mFound := FSession.GotoTarget(mFile, mText, 6, mAt + 1, cDefinitionLimitMs, mLocation);
        mWatch.Stop;
        mAfter := LazyNow(mFile);
        Inc(FRequests);
        mTimes.Add(mWatch.Elapsed.TotalMilliseconds);
        // Über der Wartezeit der IDE: Dort käme der Sprung nachgereicht (TDpccLateGoto).
        if mWatch.Elapsed.TotalMilliseconds > TLspSession.cMainThreadTimeoutMs then
        begin
          Inc(mLate);
        end;
        if mFound then
        begin
          Inc(mHits);
          System.Writeln(Format('[definition] %s: %s Zeile %d, %s ms, nachgeladen %d',
            [mWord, ExtractFileName(mLocation.FileName), mLocation.Line + 1,
            FormatFloat('0.0', mWatch.Elapsed.TotalMilliseconds, TFormatSettings.Invariant),
            mAfter.Loads - mBefore.Loads]));
        end
        else
        begin
          System.Writeln(Format('[definition] %s: kein Ziel, %s ms, nachgeladen %d', [mWord,
            FormatFloat('0.0', mWatch.Elapsed.TotalMilliseconds, TFormatSettings.Invariant),
            mAfter.Loads - mBefore.Loads]));
        end;
      except
        on E: Exception do
        begin
          Inc(FFailures);
          System.Writeln(Format('[definition] %s: Fehler %s %s', [mWord, E.ClassName, E.Message]));
        end;
      end;
    end;
    mTimes.Sort;
    if mTimes.Count > 0 then
    begin
      mMedian := mTimes[mTimes.Count div 2];
      if not Odd(mTimes.Count) then
      begin
        mMedian := (mTimes[mTimes.Count div 2 - 1] + mTimes[mTimes.Count div 2]) / 2;
      end;
      // Neue Angaben nur hinten anhängen: Auswertungen lesen die Zeile von vorn.
      System.Writeln(Format('[definition] Summe: %d von %d mit Ziel, Median %s ms, Höchstwert %s ms, über %d ms %d',
        [mHits, mTimes.Count, FormatFloat('0.0', mMedian, TFormatSettings.Invariant),
        FormatFloat('0.0', mTimes.Last, TFormatSettings.Invariant), TLspSession.cMainThreadTimeoutMs, mLate]));
    end;
  finally
    mTimes.Free;
  end;
  FSession.Sync(mFile, FTexts[mFile]);
end;

procedure TBench.Run(ARequests, ARebuilds, ARestarts, ABetween: Integer);
var
  mIndex: Integer;
begin
  LoadProjects;
  PickFiles;
  Point('start');
  StartServer;
  WaitForIndex('index');
  Point('indexed');
  if Trim(GetEnvironmentVariable('DPCC_MEMBENCH_IMPORTS')) <> '' then
  begin
    FSampler.SetPhase('imports');
    ImportProbe(Trim(GetEnvironmentVariable('DPCC_MEMBENCH_IMPORTS')).Split([','], TStringSplitOptions.ExcludeEmpty));
    Point('imports');
  end;
  if Trim(GetEnvironmentVariable('DPCC_MEMBENCH_LISTS')) <> '' then
  begin
    FSampler.SetPhase('lists');
    ListProbe(Trim(GetEnvironmentVariable('DPCC_MEMBENCH_LISTS')).Split(['|'], TStringSplitOptions.ExcludeEmpty));
    Point('lists');
  end;
  if Trim(GetEnvironmentVariable('DPCC_MEMBENCH_DEFINITIONS')) <> '' then
  begin
    FSampler.SetPhase('definitions');
    DefinitionProbe(Trim(GetEnvironmentVariable('DPCC_MEMBENCH_DEFINITIONS')).Split(['|'],
      TStringSplitOptions.ExcludeEmpty));
    Point('definitions');
  end;
  FSampler.SetPhase('requests');
  Requests(ARequests);
  Point(Format('requests %d', [ARequests]));
  if EnvInt('DPCC_MEMBENCH_COLD', 0) > 0 then
  begin
    FSampler.SetPhase('cold');
    ColdRequests(EnvInt('DPCC_MEMBENCH_COLD', 0), FFiles[0], 'cold');
    Point(Format('cold %d', [EnvInt('DPCC_MEMBENCH_COLD', 0)]));
  end;
  if EnvInt('DPCC_MEMBENCH_TYPING', 0) > 0 then
  begin
    FSampler.SetPhase('typing');
    Typing(EnvInt('DPCC_MEMBENCH_TYPING', 0));
    Point(Format('typing %d', [EnvInt('DPCC_MEMBENCH_TYPING', 0)]));
  end;
  if EnvInt('DPCC_MEMBENCH_PINNED', 0) > 0 then
  begin
    FSampler.SetPhase('pinned');
    PinnedLoad(EnvInt('DPCC_MEMBENCH_PINNED', 0));
    Point(Format('pinned %d', [EnvInt('DPCC_MEMBENCH_PINNED', 0)]));
  end;
  if EnvInt('DPCC_MEMBENCH_FREQUENT', 0) > 0 then
  begin
    FSampler.SetPhase('frequent');
    FrequentName(EnvInt('DPCC_MEMBENCH_FREQUENT', 0));
    Point(Format('frequent %d', [EnvInt('DPCC_MEMBENCH_FREQUENT', 0)]));
  end;
  for mIndex := 1 to ARebuilds do
  begin
    Rebuild;
    WaitForIndex(Format('rebuild%d', [mIndex]));
    FSampler.SetPhase(Format('between%d', [mIndex]));
    Requests(ABetween);
    Point(Format('rebuild %d', [mIndex]));
  end;
  for mIndex := 1 to ARestarts do
  begin
    FSampler.SetPhase(Format('restart%d', [mIndex]));
    StopServer;
    Point(Format('stopped %d', [mIndex]));
    StartServer;
    WaitForIndex(Format('restart%d', [mIndex]));
    Requests(ABetween);
    Point(Format('restart %d', [mIndex]));
  end;
  StopServer;
  Point('end');
  System.Writeln(Format('[mem] Anfragen %d, gescheitert %d', [FRequests, FFailures]));
end;

procedure TBench.Save(const AFileName: string);
var
  mPoints: TStringList;
  mPoint: TBenchPoint;
  mLatency: Double;
begin
  FSampler.Finish;
  ForceDirectories(ExtractFilePath(ExpandFileName(AFileName)));
  FSampler.Lines.SaveToFile(AFileName, TEncoding.UTF8);
  mPoints := TStringList.Create;
  try
    mPoints.Add('point,ms,private_mb,peak_mb,max_private_mb,ws_mb,free_mb,min_free_mb,index_mb,units,lib,docs,' +
      'trees,tree_mb,dcp_files,dcp_kb,alloc_mb,loaded,pinned,evictable,evictable_mb,cold,catalog_mb,loads,' +
      'evictions,load_median_ms,load_max_ms,largest_load_kb,largest_load_ms');
    for mPoint in FPoints do
    begin
      mPoints.Add(Format('%s,%d,%s,%s,%s,%s,%s,%s,%s,%d,%d,%d,%d,%s,%d,%d,%s', [mPoint.Name, mPoint.ElapsedMs,
        Mb(mPoint.Memory.PrivateBytes), Mb(mPoint.Memory.PeakPrivateBytes), Mb(mPoint.MaxPrivate),
        Mb(mPoint.Memory.WorkingSetBytes), Mb(mPoint.Memory.LargestFreeBytes), Mb(mPoint.MinFree),
        Mb(mPoint.Report.IndexBytes), mPoint.Report.Units, mPoint.Report.LibraryUnits, mPoint.Report.Documents,
        mPoint.Report.Trees, Mb(mPoint.Report.TreeBytes), mPoint.Report.PackageFiles,
        mPoint.Report.PackageBytes div 1024, Mb(mPoint.Allocated)]) + Format(',%d,%d,%d,%s,%d,%s,%d,%d,%s,%s,%d,%s',
        [mPoint.Report.Lazy.Loaded, mPoint.Report.Lazy.Pinned, mPoint.Report.Lazy.Evictable,
        Mb(mPoint.Report.Lazy.EvictableBytes), mPoint.Report.Lazy.Cold, Mb(mPoint.Report.Lazy.CatalogBytes),
        mPoint.Report.Lazy.Loads, mPoint.Report.Lazy.Evictions, FormatFloat('0.0', mPoint.Report.Lazy.LoadMedianMs,
        TFormatSettings.Invariant), FormatFloat('0.0', mPoint.Report.Lazy.LoadMaxMs, TFormatSettings.Invariant),
        mPoint.Report.Lazy.LargestLoadBytes div 1024, FormatFloat('0.0', mPoint.Report.Lazy.LargestLoadMs,
        TFormatSettings.Invariant)]));
    end;
    mPoints.SaveToFile(ChangeFileExt(AFileName, '') + '-points.csv', TEncoding.UTF8);
    if FLatencies.Count > 0 then
    begin
      mPoints.Clear;
      mPoints.Add('ms');
      for mLatency in FLatencies do
      begin
        mPoints.Add(FormatFloat('0.00', mLatency, TFormatSettings.Invariant));
      end;
      mPoints.SaveToFile(ChangeFileExt(AFileName, '') + '-latency.csv', TEncoding.UTF8);
    end;
  finally
    mPoints.Free;
  end;
end;

{ TDpccMemoryBenchTests }

procedure TDpccMemoryBenchTests.MeasuresLibraryIndex;
var
  mOut, mGroup: string;
  mBench: TBench;
begin
  mOut := Trim(GetEnvironmentVariable('DPCC_MEMBENCH_OUT'));
  if mOut = '' then
  begin
    Assert.Pass('DPCC_MEMBENCH_OUT nicht gesetzt: keine Messung');
    Exit;
  end;
  mGroup := Trim(GetEnvironmentVariable('DPCC_MEMBENCH_GROUP'));
  Assert.IsTrue(FileExists(mGroup), 'DPCC_MEMBENCH_GROUP: ' + mGroup);
  // Fehler im Server mit Adressen festhalten (nur das Testprogramm, nur während der Messung).
  BenchExceptionFile := ChangeFileExt(mOut, '') + '-exceptions.txt';
  ForceDirectories(ExtractFilePath(ExpandFileName(BenchExceptionFile)));
  if FileExists(BenchExceptionFile) then
  begin
    TFile.Delete(BenchExceptionFile);
  end;
  BenchExceptionLines := 0;
  BenchFailureFile := ChangeFileExt(mOut, '') + '-failures.txt';
  if FileExists(BenchFailureFile) then
  begin
    TFile.Delete(BenchFailureFile);
  end;
  BenchFailureLines := 0;
  Exception.GetExceptionStackInfoProc := BenchCaptureStack;
  Exception.GetStackInfoStringProc := BenchStackString;
  Exception.CleanUpStackInfoProc := BenchCleanUpStack;
  try
    mBench := TBench.Create(mGroup);
    try
      mBench.Run(EnvInt('DPCC_MEMBENCH_REQUESTS', 2000), EnvInt('DPCC_MEMBENCH_REBUILDS', 5),
        EnvInt('DPCC_MEMBENCH_RESTARTS', 1), EnvInt('DPCC_MEMBENCH_BETWEEN', 100));
      mBench.Save(mOut);
    finally
      mBench.Free;
    end;
  finally
    Exception.GetExceptionStackInfoProc := nil;
    Exception.GetStackInfoStringProc := nil;
    Exception.CleanUpStackInfoProc := nil;
    TMonitor.Enter(BenchExceptionLock);
    try
      BenchExceptionFile := '';
      BenchFailureFile := '';
    finally
      TMonitor.Exit(BenchExceptionLock);
    end;
  end;
end;

initialization
  BenchExceptionLock := TObject.Create;
  // Monitor gleich anlegen: sonst entsteht er beim ersten Fehler und zählt als Leck.
  TMonitor.Enter(BenchExceptionLock);
  TMonitor.Exit(BenchExceptionLock);
  TDUnitX.RegisterTestFixture(TDpccMemoryBenchTests);

finalization
  FreeAndNil(BenchExceptionLock);

end.
