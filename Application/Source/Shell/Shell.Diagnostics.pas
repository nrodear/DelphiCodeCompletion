unit Shell.Diagnostics;

// Host-Rolle Shell: Anbindung des anonymisierten Diagnoselogs (#647).
// - Beobachter des Dispatchers: je Anfrage Dauer, Wartezeit, Ergebnis mit
//   Grundcode, Dokument als Kurz-ID mit Version, Länge und Prüfsumme, Position
//   als Zahlen und Zustand des Index.
// - Start und Ende des Serverlaufs mit Grund, Speicher und Threads; bei einer
//   Exception Klasse und Aufrufstapel (Adressen und dpcc-eigene Routinen aus
//   der Map-Datei, ohne Dateinamen).
// - Läufe, die ohne Endzeile aufhörten (Prozess von der IDE beendet oder
//   abgestürzt), meldet der nächste Start; im Server-Log ebenso (#175).
// - Selbstmessung (a0): Private Bytes, Spitze, Working Set und größte freie Region des Prozesses
//   (GetProcessMemoryInfo, VirtualQuery) mit den Anteilen von dpcc (geschätzter Index, Units, Dokumente,
//   Syntaxbäume, .dcp) als Zeile „mem …“: bei Indexstart und -ende und spätestens alle 10 Minuten, sobald eine
//   Anfrage endet. Die Speicherangaben „mem n MB“ der übrigen Zeilen sind ebenfalls Private Bytes; vorher kamen sie
//   aus GetMemoryManagerState, das in der IDE (gemeinsamer Speichermanager borlndmm.dll) immer 0 meldete.
// Ordner: %LOCALAPPDATA%\dpcc\Logs\Diagnose (TIndexCacheDirectory.DefaultRoot), eine Datei je Tag und Prozess.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Index.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Logging.Contract,
  dpcc.Common.Diagnostics.Contract,
  dpcc.Common.Diagnostics.Anonymizer,
  dpcc.Common.Diagnostics.Providers.Log,
  dpcc.Common.Diagnostics.Adapters.LogFolder,
  Shell.Platform;

type
  /// <summary>Selbstmessung (a0): Speicher des Prozesses und die Anteile von dpcc, soweit bekannt (-1 =
  /// unbekannt).</summary>
  TShellMemoryReport = record
  public
    Process: TProcessMemory;
    /// <summary>Geschätzter Bedarf des Symbolindex (ISymbolIndex.MemoryBytes).</summary>
    IndexBytes: Int64;
    Units: Integer;
    LibraryUnits: Integer;
    Documents: Integer;
    /// <summary>Lebende gemeinsame Syntaxbäume und ihr geschätzter Speicher.</summary>
    Trees: Integer;
    TreeBytes: Int64;
    /// <summary>Gemerkte übersetzte Packages (.dcp) und was davon im Speicher liegt.</summary>
    PackageFiles: Integer;
    PackageBytes: Int64;
    /// <summary>Misst jetzt und merkt den Stand für Latest; AIndex und ADocuments dürfen nil sein, ALibraryUnits -1 (dann gezählt).</summary>
    class function Take(const AIndex: ISymbolIndex; const ADocuments: IDocumentStore;
      ALibraryUnits: Integer): TShellMemoryReport; static;
    /// <summary>Zuletzt gemessener Stand (Messprogramm); Process.Valid = False vor der ersten Messung.</summary>
    class function Latest: TShellMemoryReport; static;
    /// <summary>Die nächste beendete Anfrage misst und schreibt die Zeile, auch vor Ablauf der 10 Minuten.</summary>
    class procedure Request; static;
    /// <summary>"private 210 MB peak 260 MB ws 180 MB free 900 MB index 120 MB units 2192 lib 1557 docs 5 trees
    /// 3 2 MB dcp 4 1 MB".</summary>
    function Text: string;
    /// <summary>Kurz fürs Server-Log: "privat 210 MB, Spitze 260 MB, größter freier Block 900 MB, Index ~120 MB".
    /// </summary>
    function LogText: string;
  end;

type
  TShellDiagnostics = class(TInterfacedObject, IJsonRpcRequestObserver)
  private
    FLogImpl: TDiagnosticLog;
    FLog: IDiagnosticLog;
    FFolder: TDiagnosticLogFolder;
    FWriter: IDiagnosticWriter;
    FIds: TDiagnosticIds;
    FDocuments: IDocumentStore;
    FIndex: ISymbolIndex;
    FLock: TObject;
    FLibraryGeneration: Int64;
    FLibraryCount: Integer;
    /// <summary>Laufende Anfragen je Kurzname (hover, diagnostic, wsDiagnostic); unter FLock.</summary>
    FRunning: TDictionary<string, Integer>;
    FMapFile: Boolean;
    FIndexLoading: TFunc<Integer>;
    FTimeoutMs: TFunc<Cardinal>;
    /// <summary>Endzeile geschrieben; danach keine Zeilen mehr.</summary>
    FEnded: Boolean;
    /// <summary>Letzte Zeile „mem“ (TThread.GetTickCount64); 0 = noch keine.</summary>
    FMemoryTicks: UInt64;
    /// <summary>Schreibt die Zeile „mem“, wenn sie fällig ist (10 Minuten oder TShellMemoryReport.Request).
    /// </summary>
    procedure LogMemoryWhenDue;
    class function ShortMethod(const AMethod: string): string; static;
    function LibraryCount: Integer;
    procedure DescribeDocument(const AParams: TJSONValue; var ARequest: TDiagnosticRequest);
    class function CountOf(const AResult: TJSONValue): Integer; static;
    /// <summary>Zählt AName als beendet; liefert, was danach noch läuft.</summary>
    function EndRunning(const AName: string): string;
    procedure SetOutcome(var ARequest: TDiagnosticRequest; const AResult: TJSONValue; const AError: Exception;
      ANoteCount: Integer);
    procedure AddIndexState(var ARequest: TDiagnosticRequest);
  public
    /// <summary>AFolder: Ordner der Tagesdateien; ATag unterscheidet die Prozesse.</summary>
    constructor Create(const AFolder, ATag: string; const ADocuments: IDocumentStore; const AIndex: ISymbolIndex);
    destructor Destroy; override;
    class function DefaultFolder: string; static;
    { IJsonRpcRequestObserver }
    procedure Started(const AMethod: string);
    procedure Finished(const AMethod: string; const AParams, AResult: TJSONValue; const AError: Exception;
      AQueueMs, AElapsedMs: Int64);
    /// <summary>Startzeile und Meldung früherer Läufe ohne Ende; liefert deren Zahl.</summary>
    function BeginRun(const AVersion: string; AMemoryBytes: Int64): Integer;
    /// <summary>Lesbarer Grund für das Server-Log, z. B. „Eingabe geschlossen ohne exit“ (#175).</summary>
    class function EndReasonText(AReason: TDiagnosticEndReason): string; static;
    /// <summary>Endzeile; AError nur bei einer unbehandelten Exception. Nur der erste Aufruf zählt.</summary>
    procedure EndRun(AReason: TDiagnosticEndReason; AExitCode: Integer; AMemoryBytes: Int64;
      const AError: Exception); overload;
    /// <summary>Wie oben ohne Exception (AError = nil).</summary>
    procedure EndRun(AReason: TDiagnosticEndReason; AExitCode: Integer; AMemoryBytes: Int64); overload;
    procedure ApplySettings(const ASettings: TServerSettings);
    /// <summary>Feste Methodennamen, die "/" enthalten dürfen.</summary>
    procedure AllowMethods(const AMethods: TArray<string>);
    /// <summary>Ordner der Delphi-Installation: Units darunter erscheinen mit Namen.</summary>
    procedure SetLibraryRoots(const ARoots: TArray<string>);
    /// <summary>Anonymes Kennzeichen einer Quelldatei für das Diagnoselog (#1094): "unit#N", unter einem
    /// Bibliothekspfad der Unit-Name.</summary>
    function FileLabel(const AFileName: string): string;
    /// <summary>Speicher jetzt (a0) mit Index und Dokumenten dieses Servers.</summary>
    function MemoryReport: TShellMemoryReport;
    /// <summary>Zeile "mem &lt;AReason&gt; private … MB …" ins Diagnoselog (a0).</summary>
    procedure LogMemory(const AReason: string);
    /// <summary>Ereignis des Indexaufbaus ins Diagnoselog; nach Start und Ende eines Aufbaus („index project#n
    /// start …“ bzw. „… done …“) dazu die Zeile „mem“ (a0).</summary>
    procedure IndexEvent(const AText: string);
    property Log: IDiagnosticLog read FLog;
    /// <summary>Fortschritt des Indexaufbaus in Prozent, -1 ohne Aufbau.</summary>
    property IndexLoading: TFunc<Integer> read FIndexLoading write FIndexLoading;
    /// <summary>Zeitlimit für Anfragen; abgebrochene Anfragen ab dieser Dauer gelten als timeout.</summary>
    property TimeoutMs: TFunc<Cardinal> read FTimeoutMs write FTimeoutMs;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  System.Hash,
  System.StrUtils,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Diagnostics.RequestScope,
  dpcc.Common.Index.Adapters.CacheDirectory,
  dpcc.Common.Pascal.TreeCache,
  dpcc.Common.Projects.PackageLocator,
  dpcc.Text.LogMarks;

threadvar
  /// <summary>Rechenzeit des Handler-Threads beim Start der Anfrage.</summary>
  StartCpuMs: Int64;

const
  /// <summary>Abstand der Zeile „mem“ im Diagnoselog (a0), sobald eine Anfrage endet.</summary>
  cMemoryIntervalMs = 10 * 60 * 1000;

var
  /// <summary>Zuletzt gemessener Stand und Wunsch nach einer Messung (TShellMemoryReport.Latest/Request).</summary>
  MemoryLock: TObject;
  LatestMemory: TShellMemoryReport;
  MemoryRequested: Boolean;

function MegaBytes(ABytes: Int64): Int64;
begin
  Result := -1;
  if ABytes >= 0 then
  begin
    Result := (ABytes + 512 * 1024) div (1024 * 1024);
  end;
end;

{ TShellMemoryReport }

class function TShellMemoryReport.Take(const AIndex: ISymbolIndex; const ADocuments: IDocumentStore;
  ALibraryUnits: Integer): TShellMemoryReport;
var
  mUnit: TUnitIndex;
  mTrees: TSyntaxTreeCacheStats;
begin
  Result := Default(TShellMemoryReport);
  Result.Process := TProcessInfo.Memory;
  Result.IndexBytes := -1;
  Result.Units := -1;
  Result.LibraryUnits := ALibraryUnits;
  Result.Documents := -1;
  if AIndex <> nil then
  begin
    Result.IndexBytes := AIndex.MemoryBytes;
    Result.Units := AIndex.UnitCount;
    if Result.LibraryUnits < 0 then
    begin
      Result.LibraryUnits := 0;
      for mUnit in AIndex.Units do
      begin
        if mUnit.Library_ then
        begin
          Inc(Result.LibraryUnits);
        end;
      end;
    end;
  end;
  if ADocuments <> nil then
  begin
    Result.Documents := Length(ADocuments.Documents);
  end;
  mTrees := TSyntaxTreeCache.Stats;
  Result.Trees := mTrees.Trees;
  Result.TreeBytes := mTrees.Bytes;
  Result.PackageFiles := TPackageCompiledFiles.Count;
  Result.PackageBytes := TPackageCompiledFiles.Bytes;
  TMonitor.Enter(MemoryLock);
  try
    LatestMemory := Result;
  finally
    TMonitor.Exit(MemoryLock);
  end;
end;

class function TShellMemoryReport.Latest: TShellMemoryReport;
begin
  TMonitor.Enter(MemoryLock);
  try
    Result := LatestMemory;
  finally
    TMonitor.Exit(MemoryLock);
  end;
end;

class procedure TShellMemoryReport.Request;
begin
  TMonitor.Enter(MemoryLock);
  try
    MemoryRequested := True;
  finally
    TMonitor.Exit(MemoryLock);
  end;
end;

function TShellMemoryReport.Text: string;
begin
  // Kleinbuchstaben und Zahlen, ohne "/" (der Filter des Diagnoselogs verwirft Zeilen mit Schrägstrich).
  Result := Format('private %d MB peak %d MB ws %d MB free %d MB index %d MB units %d lib %d docs %d ' +
    'trees %d %d MB dcp %d %d kb', [MegaBytes(Process.PrivateBytes), MegaBytes(Process.PeakPrivateBytes),
    MegaBytes(Process.WorkingSetBytes), MegaBytes(Process.LargestFreeBytes), MegaBytes(IndexBytes), Units,
    LibraryUnits, Documents, Trees, MegaBytes(TreeBytes), PackageFiles, PackageBytes div 1024]);
end;

function TShellMemoryReport.LogText: string;
begin
  Result := Format('privat %d MB, Spitze %d MB, größter freier Block %d MB, Index ~%d MB (%d Units)',
    [MegaBytes(Process.PrivateBytes), MegaBytes(Process.PeakPrivateBytes), MegaBytes(Process.LargestFreeBytes),
     MegaBytes(IndexBytes), Units]);
end;

{ TShellDiagnostics }

constructor TShellDiagnostics.Create(const AFolder, ATag: string; const ADocuments: IDocumentStore;
  const AIndex: ISymbolIndex);
begin
  inherited Create;
  FLock := TObject.Create;
  FRunning := TDictionary<string, Integer>.Create;
  FFolder := TDiagnosticLogFolder.Create(AFolder, ATag);
  FWriter := FFolder;
  FLogImpl := TDiagnosticLog.Create(FWriter, TDiagnosticFilter.Create(TProcessInfo.IdentityNames));
  FLog := FLogImpl;
  FIds := TDiagnosticIds.Create;
  FDocuments := ADocuments;
  FIndex := AIndex;
  FLibraryGeneration := -1;
end;

destructor TShellDiagnostics.Destroy;
begin
  if FLogImpl <> nil then
  begin
    FLogImpl.Flush;
  end;
  FLog := nil;
  FWriter := nil;
  FIds.Free;
  FRunning.Free;
  FLock.Free;
  inherited;
end;

class function TShellDiagnostics.DefaultFolder: string;
begin
  // Wie die Index-Caches (DPCC_CACHE_ROOT bzw. LOCALAPPDATA der Umgebung): Tests und Messprogramm schreiben so
  // nicht in das Diagnoselog des Benutzers.
  Result := TPath.Combine(TPath.Combine(TIndexCacheDirectory.DefaultRoot, 'Logs'), 'Diagnose');
end;

function TShellDiagnostics.MemoryReport: TShellMemoryReport;
var
  mLibrary: Integer;
begin
  mLibrary := -1;
  if FIndex <> nil then
  begin
    mLibrary := LibraryCount;
  end;
  Result := TShellMemoryReport.Take(FIndex, FDocuments, mLibrary);
end;

procedure TShellDiagnostics.LogMemory(const AReason: string);
var
  mReport: TShellMemoryReport;
begin
  mReport := MemoryReport;
  TMonitor.Enter(FLock);
  try
    FMemoryTicks := TThread.GetTickCount64;
  finally
    TMonitor.Exit(FLock);
  end;
  if not FEnded then
  begin
    FLog.LogEvent('mem ' + AReason + ' ' + mReport.Text);
  end;
end;

procedure TShellDiagnostics.LogMemoryWhenDue;
var
  mDue: Boolean;
begin
  TMonitor.Enter(MemoryLock);
  try
    mDue := MemoryRequested;
    MemoryRequested := False;
  finally
    TMonitor.Exit(MemoryLock);
  end;
  TMonitor.Enter(FLock);
  try
    mDue := mDue or (FMemoryTicks = 0) or (TThread.GetTickCount64 - FMemoryTicks >= cMemoryIntervalMs);
  finally
    TMonitor.Exit(FLock);
  end;
  if mDue then
  begin
    LogMemory('periodic');
  end;
end;

procedure TShellDiagnostics.IndexEvent(const AText: string);
begin
  if FEnded then
  begin
    Exit;
  end;
  FLog.LogEvent(AText);
  // Feste Zeilenform aus Shell.Workspace.Indexing: "index project#n start files …" und "index project#n done …".
  if StartsText('index project#', AText) and (ContainsText(AText, ' start files ') or
    ContainsText(AText, ' done ')) then
  begin
    LogMemory(IfThen(ContainsText(AText, ' start files '), 'indexStart', 'indexDone'));
  end;
end;

procedure TShellDiagnostics.AllowMethods(const AMethods: TArray<string>);
begin
  // Nur beim Start gesetzt, bevor Anfragen laufen.
  FLogImpl.Filter.Allowed := AMethods;
end;

procedure TShellDiagnostics.SetLibraryRoots(const ARoots: TArray<string>);
begin
  FIds.SetLibraryRoots(ARoots);
end;

procedure TShellDiagnostics.ApplySettings(const ASettings: TServerSettings);
begin
  FMapFile := ASettings.DiagnosticsLogMapFile;
  FFolder.RetentionDays := ASettings.DiagnosticsLogDays;
  FLog.Configure(ASettings.DiagnosticsLog);
  if ASettings.DiagnosticsLog then
  begin
    FFolder.Cleanup(ASettings.DiagnosticsLogDays);
  end;
end;

function TShellDiagnostics.BeginRun(const AVersion: string; AMemoryBytes: Int64): Integer;
var
  mProcess: TDiagnosticProcess;
  mPrevious, mIndex: Integer;
begin
  mPrevious := FFolder.BeginRun;
  Result := mPrevious;
  mProcess.MemoryBytes := AMemoryBytes;
  mProcess.Threads := TProcessInfo.ThreadCount;
  FLog.LogStart(AVersion, mProcess);
  for mIndex := 1 to mPrevious do
  begin
    FLog.LogEvent('previous run ended without end line (process terminated or crashed)');
  end;
end;

class function TShellDiagnostics.EndReasonText(AReason: TDiagnosticEndReason): string;
begin
  case AReason of
    TDiagnosticEndReason.Clean:
      Result := 'shutdown und exit vom Client';
    TDiagnosticEndReason.InputClosed:
      Result := 'Eingabe geschlossen ohne exit (IDE hat die Verbindung getrennt)';
    TDiagnosticEndReason.ParentExited:
      Result := 'Editor-Prozess beendet';
  else
    Result := 'unbehandelte Exception';
  end;
end;

procedure TShellDiagnostics.EndRun(AReason: TDiagnosticEndReason; AExitCode: Integer; AMemoryBytes: Int64);
begin
  EndRun(AReason, AExitCode, AMemoryBytes, nil);
end;

procedure TShellDiagnostics.EndRun(AReason: TDiagnosticEndReason; AExitCode: Integer; AMemoryBytes: Int64;
  const AError: Exception);
var
  mProcess: TDiagnosticProcess;
  mErrorClass, mStack: string;
begin
  // Die Endzeile kommt schon, wenn die Eingabe endet (#647): Das Plugin wartet danach nur kurz und
  // beendet den Prozess, solange noch Anfragen laufen. Der spätere Aufruf aus Run zählt dann nicht.
  if FEnded then
  begin
    Exit;
  end;
  FEnded := True;
  mProcess.MemoryBytes := AMemoryBytes;
  mProcess.Threads := TProcessInfo.ThreadCount;
  mErrorClass := '';
  mStack := '';
  if AError <> nil then
  begin
    // Nur Klasse und Aufrufstapel: Die Meldung kann Pfade oder Namen aus dem Projekt enthalten.
    mErrorClass := AError.ClassName;
    mStack := TShellPlatform.StackTraceOf(AError);
  end;
  FLog.LogEnd(AReason, AExitCode, mProcess, mErrorClass, mStack);
  FLogImpl.Flush;
  if FMapFile and FLog.Enabled then
  begin
    FFolder.WriteMap(FIds.MapLines);
  end;
  FFolder.EndRun;
end;

function TShellDiagnostics.FileLabel(const AFileName: string): string;
begin
  Result := FIds.UnitLabel(ChangeFileExt(ExtractFileName(AFileName), ''), AFileName);
end;

function TShellDiagnostics.LibraryCount: Integer;
var
  mGeneration: Int64;
  mUnitIndex: TUnitIndex;
  mCount: Integer;
begin
  // Teuer bei vielen Units; nur neu zählen, wenn sich der Index geändert hat.
  mGeneration := FIndex.Generation;
  TMonitor.Enter(FLock);
  try
    if mGeneration = FLibraryGeneration then
    begin
      Exit(FLibraryCount);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  mCount := 0;
  for mUnitIndex in FIndex.Units do
  begin
    if mUnitIndex.Library_ then
    begin
      Inc(mCount);
    end;
  end;
  TMonitor.Enter(FLock);
  try
    FLibraryGeneration := mGeneration;
    FLibraryCount := mCount;
  finally
    TMonitor.Exit(FLock);
  end;
  Result := mCount;
end;

procedure TShellDiagnostics.DescribeDocument(const AParams: TJSONValue; var ARequest: TDiagnosticRequest);
var
  mUri: string;
  mLine, mCharacter: Integer;
  mDocument: ITextDocument;
  mText: string;
begin
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  if TJSONObject(AParams).TryGetValue<string>('textDocument.uri', mUri) then
  begin
    ARequest.Document := FIds.IdOf(TDiagnosticIdKind.Document, TDocumentUris.ToPath(mUri));
    ARequest.Version := -1;
    if (FDocuments <> nil) and FDocuments.TryGet(mUri, mDocument) then
    begin
      mText := mDocument.Text;
      ARequest.Version := mDocument.Version;
      ARequest.Length_ := Length(mText);
      ARequest.Checksum := IntToHex(Cardinal(THashFNV1a32.GetHashValue(mText)), 8);
      ARequest.LineCount := mDocument.LineCount;
    end;
  end;
  if TJSONObject(AParams).TryGetValue<Integer>('position.line', mLine) and
    TJSONObject(AParams).TryGetValue<Integer>('position.character', mCharacter) then
  begin
    ARequest.Line := mLine;
    ARequest.Column := mCharacter;
  end;
end;

class function TShellDiagnostics.CountOf(const AResult: TJSONValue): Integer;
var
  mItems: TJSONValue;
begin
  if (AResult = nil) or (AResult is TJSONNull) then
  begin
    Exit(0);
  end;
  if AResult is TJSONArray then
  begin
    Exit(TJSONArray(AResult).Count);
  end;
  if AResult is TJSONObject then
  begin
    mItems := TJSONObject(AResult).GetValue('items');
    if mItems is TJSONArray then
    begin
      Exit(TJSONArray(mItems).Count);
    end;
  end;
  Result := 1;
end;

class function TShellDiagnostics.ShortMethod(const AMethod: string): string;
var
  mSlash: Integer;
begin
  // Ohne "/": Der Filter des Diagnoselogs verwirft Zeilen mit Schrägstrich.
  mSlash := LastDelimiter('/', AMethod);
  Result := Copy(AMethod, mSlash + 1, MaxInt);
  if StartsText('workspace/', AMethod) and (Result <> '') then
  begin
    Result := 'ws' + UpperCase(Result[1]) + Copy(Result, 2, MaxInt);
  end;
end;

procedure TShellDiagnostics.Started(const AMethod: string);
var
  mName: string;
  mCount: Integer;
begin
  TRequestDiagnostics.Open;
  StartCpuMs := TProcessInfo.ThreadCpuMs;
  mName := ShortMethod(AMethod);
  TMonitor.Enter(FLock);
  try
    if FRunning.TryGetValue(mName, mCount) then
    begin
      FRunning[mName] := mCount + 1;
    end
    else
    begin
      FRunning.Add(mName, 1);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

// Was beim Ende einer Anfrage noch läuft, etwa „hover1,completion2“.
function RunningText(ARunning: TDictionary<string, Integer>): string;
var
  mPair: TPair<string, Integer>;
begin
  Result := '';
  for mPair in ARunning do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mPair.Key + IntToStr(mPair.Value);
  end;
end;

function TShellDiagnostics.EndRunning(const AName: string): string;
var
  mCount: Integer;
begin
  TMonitor.Enter(FLock);
  try
    if FRunning.TryGetValue(AName, mCount) then
    begin
      if mCount <= 1 then
      begin
        FRunning.Remove(AName);
      end
      else
      begin
        FRunning[AName] := mCount - 1;
      end;
    end;
    Result := RunningText(FRunning);
  finally
    TMonitor.Exit(FLock);
  end;
end;

// Zusätze am Ende einer Anfrage: Rechenzeit, Parallelität, Unit und Regel beim Fehler.
procedure AddEndNotes(var ANotes: TRequestNotes; const AParallel: string);
var
  mCpuMs: Int64;
begin
  // Rechenzeit gegen Laufzeit (#647): cpu weit unter ms heißt Warten (Sperre, volle CPU), nicht Rechnen.
  mCpuMs := TProcessInfo.ThreadCpuMs;
  if (mCpuMs >= 0) and (StartCpuMs >= 0) then
  begin
    ANotes.Notes := ANotes.Notes + ['cpu=' + IntToStr(mCpuMs - StartCpuMs)];
  end;
  if AParallel <> '' then
  begin
    ANotes.Notes := ANotes.Notes + ['parallel=' + AParallel];
  end;
  // Bei einem Fehler noch offen (#1094): die Unit und die Regel, an denen die Anfrage scheiterte.
  if ANotes.Subject <> '' then
  begin
    ANotes.Notes := ANotes.Notes + ['unit=' + ANotes.Subject];
  end;
  if ANotes.Rule <> '' then
  begin
    ANotes.Notes := ANotes.Notes + ['rule=' + ANotes.Rule];
  end;
end;

// Abbruch durch den Wächter (Zeitlimit) oder durch Client bzw. Änderung.
function CancelOutcome(const ATimeoutMs: TFunc<Cardinal>; AWaitedMs: Int64): TDiagnosticOutcome;
var
  mTimeout: Cardinal;
begin
  mTimeout := 0;
  if Assigned(ATimeoutMs) then
  begin
    mTimeout := ATimeoutMs();
  end;
  // Der Wächter bricht nach dem Zeitlimit ab; früher abgebrochen hat der Client oder eine Änderung.
  Result := TDiagnosticOutcome.Cancelled;
  if (mTimeout > 0) and (AWaitedMs >= Int64(mTimeout) - 50) then
  begin
    Result := TDiagnosticOutcome.Timeout;
  end;
end;

procedure TShellDiagnostics.SetOutcome(var ARequest: TDiagnosticRequest; const AResult: TJSONValue;
  const AError: Exception; ANoteCount: Integer);
begin
  if AError is EJsonRpcRequestCancelled then
  begin
    ARequest.Outcome := CancelOutcome(FTimeoutMs, ARequest.QueueMs + ARequest.ElapsedMs);
  end
  else if AError <> nil then
  begin
    ARequest.Outcome := TDiagnosticOutcome.Error;
    ARequest.Reason := AError.ClassName;
  end
  else
  begin
    ARequest.Count := ANoteCount;
    if ARequest.Count < 0 then
    begin
      ARequest.Count := CountOf(AResult);
    end;
    ARequest.Outcome := TDiagnosticOutcome.Empty;
    if ARequest.Count > 0 then
    begin
      ARequest.Outcome := TDiagnosticOutcome.Ok;
    end;
  end;
end;

procedure TShellDiagnostics.AddIndexState(var ARequest: TDiagnosticRequest);
begin
  if FIndex <> nil then
  begin
    ARequest.IndexUnits := FIndex.UnitCount;
    ARequest.IndexLibrary := LibraryCount;
  end;
  ARequest.IndexLoading := -1;
  if Assigned(FIndexLoading) then
  begin
    ARequest.IndexLoading := FIndexLoading();
  end;
end;

procedure TShellDiagnostics.Finished(const AMethod: string; const AParams, AResult: TJSONValue;
  const AError: Exception; AQueueMs, AElapsedMs: Int64);
var
  mNotes: TRequestNotes;
  mRequest: TDiagnosticRequest;
begin
  mNotes := TRequestDiagnostics.Close;
  AddEndNotes(mNotes, EndRunning(ShortMethod(AMethod)));
  if FEnded or not FLog.Enabled then
  begin
    Exit;
  end;
  mRequest := Default(TDiagnosticRequest);
  mRequest.Time := Now;
  mRequest.Method := AMethod;
  mRequest.ElapsedMs := AElapsedMs;
  mRequest.QueueMs := AQueueMs;
  mRequest.Line := -1;
  mRequest.Notes := mNotes.Notes;
  mRequest.Resolve := mNotes.Resolve;
  mRequest.Reason := mNotes.Reason;
  SetOutcome(mRequest, AResult, AError, mNotes.Count);
  DescribeDocument(AParams, mRequest);
  AddIndexState(mRequest);
  FLog.LogRequest(mRequest);
  LogMemoryWhenDue;
end;

initialization
  MemoryLock := TObject.Create;
  // Den Monitor gleich anlegen: TMonitor belegt ihn beim ersten Enter, im Test zählte das als Leck.
  TMonitor.Enter(MemoryLock);
  TMonitor.Exit(MemoryLock);

finalization
  FreeAndNil(MemoryLock);

end.
