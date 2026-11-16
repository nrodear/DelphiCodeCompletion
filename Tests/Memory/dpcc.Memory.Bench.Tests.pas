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
//   DPCC_MEMBENCH_BETWEEN (Anfragen zwischen zwei Neuaufbauten, 100).
// Der Cache gehört nicht dem Benutzer: Der Aufrufer setzt LOCALAPPDATA bzw. DPCC_CACHE_ROOT auf einen eigenen Ordner
// (z. B. mit einer Kopie des Bibliotheks-Caches) und APPDATA auf einen leeren. Rohdaten gehören nicht ins Repository.

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
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Math,
  System.JSON,
  System.SyncObjs,
  System.Generics.Collections,
  System.RegularExpressions,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Lsp.Adapters.InProcess,
  dpcc.Core.Files.WatchedChanges,
  dpcc.Windows.Diagnostics.ProcessInfo,
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
    procedure EnsureOpen(const AFileName: string);
    procedure Rebuild;
  public
    constructor Create(const AGroupFile: string);
    destructor Destroy; override;
    procedure Run(ARequests, ARebuilds, ARestarts, ABetween: Integer);
    procedure Save(const AFileName: string);
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
  mPoint.Report := TShellMemoryReport.Latest;
  FPoints.Add(mPoint);
  System.Writeln(Format('[mem] %-14s private %s MB peak %s MB max %s MB free %s MB index %s MB units %d',
    [AName, Mb(mPoint.Memory.PrivateBytes), Mb(mPoint.Memory.PeakPrivateBytes), Mb(mPoint.MaxPrivate),
     Mb(mPoint.Memory.LargestFreeBytes), Mb(mPoint.Report.IndexBytes), mPoint.Report.Units]));
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
      'trees,tree_mb,dcp_files,dcp_kb');
    for mPoint in FPoints do
    begin
      mPoints.Add(Format('%s,%d,%s,%s,%s,%s,%s,%s,%s,%d,%d,%d,%d,%s,%d,%d', [mPoint.Name, mPoint.ElapsedMs,
        Mb(mPoint.Memory.PrivateBytes), Mb(mPoint.Memory.PeakPrivateBytes), Mb(mPoint.MaxPrivate),
        Mb(mPoint.Memory.WorkingSetBytes), Mb(mPoint.Memory.LargestFreeBytes), Mb(mPoint.MinFree),
        Mb(mPoint.Report.IndexBytes), mPoint.Report.Units, mPoint.Report.LibraryUnits, mPoint.Report.Documents,
        mPoint.Report.Trees, Mb(mPoint.Report.TreeBytes), mPoint.Report.PackageFiles,
        mPoint.Report.PackageBytes div 1024]));
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
  mBench := TBench.Create(mGroup);
  try
    mBench.Run(EnvInt('DPCC_MEMBENCH_REQUESTS', 2000), EnvInt('DPCC_MEMBENCH_REBUILDS', 5),
      EnvInt('DPCC_MEMBENCH_RESTARTS', 1), EnvInt('DPCC_MEMBENCH_BETWEEN', 100));
    mBench.Save(mOut);
  finally
    mBench.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccMemoryBenchTests);

end.
