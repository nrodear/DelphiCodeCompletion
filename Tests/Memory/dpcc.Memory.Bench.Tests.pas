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
// Je Messpunkt eine Zeile "[lazy]" mit geladenen, gepinnten, verdrängbaren und verdrängten Units, Katalog und
// Dauer des Nachladens (Median, Höchstwert, größte Unit).
// Der Cache gehört nicht dem Benutzer: Der Aufrufer setzt LOCALAPPDATA bzw. DPCC_CACHE_ROOT auf einen eigenen Ordner
// (z. B. mit einer Kopie des Bibliotheks-Caches) und APPDATA auf einen leeren. Rohdaten gehören nicht ins Repository.
// Fehler im Server (ERangeError, EIntOverflow, EAccessViolation) schreibt das Messprogramm mit Fehleradresse und
// Rücksprungadressen nach <Datei>-exceptions.txt (Speicher-Optimierung Phase 2: gescheiterte Anfragen); die Adressen
// löst die .map-Datei des Testprogramms auf. Nur im Testprogramm und nur während der Messung.

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
  System.RegularExpressions,
  System.Diagnostics,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.Adapters.InProcess,
  dpcc.Core.Files.WatchedChanges,
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
    procedure LoadProjects;
    procedure PickFiles;
    procedure StartServer;
    procedure StopServer;
    procedure WaitForIndex(const APhase: string);
    procedure Point(const AName: string);
    procedure Requests(ACount: Integer);
    procedure OneRequest;
    /// <summary>Vervollständigungen auf Units der Bibliothek (Nachladen, Phase 3).</summary>
    procedure ColdRequests(ACount: Integer);
    procedure EnsureOpen(const AFileName: string);
    procedure Rebuild;
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
  FSampler := TBenchSampler.Create;
end;

destructor TBench.Destroy;
begin
  StopServer;
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
    // Eine gescheiterte Anfrage zählt nur; das Messprogramm misst Speicher, nicht Antworten.
    on Exception do
      Inc(FFailures);
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

procedure TBench.ColdRequests(ACount: Integer);
var
  mFolder, mFile, mOwn, mName, mText: string;
  mAll: TArray<string>;
  mIndex, mFailed: Integer;
  mWatch: TStopwatch;
  mTotal, mMax, mMs: Double;
  mResponse: TJSONValue;
begin
  mFolder := Trim(GetEnvironmentVariable('DPCC_MEMBENCH_LIBDIR'));
  if mFolder = '' then
  begin
    mFolder := 'C:\Program Files (x86)\Embarcadero\Studio\37.0\source';
  end;
  if (ACount <= 0) or not TDirectory.Exists(mFolder) then
  begin
    Exit;
  end;
  // Ohne WinRT: Diese Units stehen nicht im Bibliotheks-Cache (c1) und würden neu gelesen.
  mAll := nil;
  for mName in TDirectory.GetFiles(mFolder, '*.pas', TSearchOption.soAllDirectories) do
  begin
    if Pos('\winrt\', LowerCase(mName)) = 0 then
    begin
      mAll := mAll + [mName];
    end;
  end;
  if Length(mAll) = 0 then
  begin
    Exit;
  end;
  TArray.Sort<string>(mAll);
  RandSeed := 815;
  mFile := FFiles[0];
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
  System.Writeln(Format('[cold] %d Vervollständigungen auf Bibliotheks-Units, gescheitert %d, Mittel %s ms, max %s ms',
    [ACount, mFailed, FormatFloat('0.0', mTotal / ACount, TFormatSettings.Invariant), FormatFloat('0.0', mMax,
    TFormatSettings.Invariant)]));
end;

procedure TBench.Rebuild;
begin
  // Wie „.dproj gespeichert“: Der Server lädt das Projekt neu und baut den Index auf (Reload). Die Sitzung schickt
  // gesammelte Änderungen mit der nächsten Anfrage.
  FSession.FilesChanged([TDpccFileChange.Create(FProjects[0], TDpccFileChangeKind.Changed)]);
  OneRequest;
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
  FSampler.SetPhase('requests');
  Requests(ARequests);
  Point(Format('requests %d', [ARequests]));
  if EnvInt('DPCC_MEMBENCH_COLD', 0) > 0 then
  begin
    FSampler.SetPhase('cold');
    ColdRequests(EnvInt('DPCC_MEMBENCH_COLD', 0));
    Point(Format('cold %d', [EnvInt('DPCC_MEMBENCH_COLD', 0)]));
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
