unit dpcc.Core.Diagnostics.Timing;

// Diagnosemodus (#479), Teil ohne VCL und Open Tools API: misst je Abfrage der
// Vervollständigung die Dauer der Schritte, für die #409 ein Zeitbudget
// festlegt, und hält die letzten 50 Abfragen vor.
// - Eine Abfrage beginnt mit TDpccCompletionController.Start (Kontext: vom
//   auslösenden Ereignis bis zur Anfrage). Danach melden sich die Quellen
//   (TDpccCompletionProviders, Zeit bis Complete samt Anzahl ihrer Einträge),
//   jedes Filtern und Sortieren (Refresh), das erste Zeigen einer Liste (bis
//   zu den ersten Einträgen) und jedes Zeichnen des Popups.
// - Ausgeschaltet (Enabled = False, Vorgabe) prüfen die Messpunkte nur diese
//   Klassenvariable: kein Zeitstempel, keine Sperre, keine Liste.
// - Anonym: Gespeichert werden Art des Kontexts, Name der Quelle, Zeiten und
//   Anzahlen, dazu nur der Dateiname ohne Ordner. Präfix, Zeile und Quelltext
//   kommen nie hinein; der Bericht nennt Dateinamen nur auf Wunsch und kürzt
//   Pfade in den Einstellungen wie der Fehlerbericht (#108).
// - TDpccTimingRows bereitet die Zeilen des Diagnosefensters auf (letzte
//   Abfrage, Mittelwert und Maximum, Überschreitung je Wert), TDpccTimingReport
//   den Text für „Bericht kopieren“ und für die letzten Diagnosedaten (#766).
// Threads: Quellen melden sich aus Hintergrund-Threads; alle Methoden des
// Rekorders sind threadsicher.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  /// <summary>Gemessene Schritte einer Abfrage mit Budget aus #409.</summary>
  TDpccTimingStep = (Context, Provider, FilterSort, Draw, FirstVisible);
  TDpccTimingRowKind = (Step, Provider, Entries);
{$SCOPEDENUMS OFF}

  /// <summary>Zeitbudget aus #409 je Schritt in Millisekunden.</summary>
  TDpccTimingBudget = record
  public const
    cContextMs = 8;
    /// <summary>Eine Quelle darf so lange brauchen wie die ganze Abfrage bis zu den ersten Einträgen.</summary>
    cProviderMs = 50;
    cFilterSortMs = 12;
    cDrawMs = 10;
    cFirstVisibleMs = 50;
  public
    class function LimitMs(AStep: TDpccTimingStep): Double; static;
    /// <summary>Liegt AMs über dem Budget von AStep? Nicht gemessene Werte (&lt; 0) nie.</summary>
    class function Exceeded(AStep: TDpccTimingStep; AMs: Double): Boolean; static;
  end;

  TDpccProviderTiming = record
    Name: string;
    Ms: Double;
    /// <summary>Einträge dieser Quelle.</summary>
    Count: Integer;
  end;

  /// <summary>Eine Abfrage; Zeiten in ms, -1 = nicht gemessen.</summary>
  TDpccQueryTiming = record
    Id: Integer;
    Started: TDateTime;
    /// <summary>Art des Kontexts, z. B. "Bezeichner, automatisch"; nie Text aus dem Editor.</summary>
    Kind: string;
    /// <summary>Dateiname ohne Ordner; im Bericht nur auf Wunsch.</summary>
    FileName: string;
    ContextMs: Double;
    Providers: TArray<TDpccProviderTiming>;
    /// <summary>Längster Filter- und Sortierschritt und Zahl der Schritte.</summary>
    FilterSortMs: Double;
    FilterSortSteps: Integer;
    /// <summary>Längstes Zeichnen des Popups und Zahl der Zeichenvorgänge.</summary>
    DrawMs: Double;
    DrawSteps: Integer;
    /// <summary>Vom auslösenden Ereignis bis zur ersten sichtbaren Liste.</summary>
    FirstVisibleMs: Double;
    /// <summary>Einträge aller Quellen und davon nach dem Filtern sichtbar (beim letzten Filtern).</summary>
    Count: Integer;
    Shown: Integer;
    /// <summary>Wert eines Schritts; Provider = langsamste Quelle.</summary>
    function Value(AStep: TDpccTimingStep): Double;
    function ProviderIndex(const AName: string): Integer;
    /// <summary>Liegt irgendein Schritt über dem Budget?</summary>
    function Exceeded: Boolean;
  end;

  TDpccTimingStat = record
    Count: Integer;
    Sum: Double;
    Maximum: Double;
    procedure Add(AValue: Double);
    /// <summary>Mittelwert; -1 ohne Werte.</summary>
    function Mean: Double;
    /// <summary>Maximum; -1 ohne Werte.</summary>
    function Peak: Double;
  end;

  /// <summary>Mittelwert und Maximum über mehrere Abfragen; nicht gemessene Werte zählen nicht.</summary>
  TDpccTimingStats = record
    Queries: Integer;
    Steps: array[TDpccTimingStep] of TDpccTimingStat;
    Entries: TDpccTimingStat;
    /// <summary>Quellen in der Reihenfolge ihres ersten Auftretens.</summary>
    ProviderNames: TArray<string>;
    Providers: TArray<TDpccTimingStat>;
    class function From(const AQueries: TArray<TDpccQueryTiming>): TDpccTimingStats; static;
    function Provider(const AName: string): TDpccTimingStat;
  end;

  /// <summary>Zeile des Diagnosefensters; Werte -1 = keine Angabe.</summary>
  TDpccTimingRow = record
    Kind: TDpccTimingRowKind;
    Step: TDpccTimingStep;
    /// <summary>Name der Quelle (Kind = Provider).</summary>
    Name: string;
    Last: Double;
    Mean: Double;
    Maximum: Double;
    /// <summary>Budget in ms; 0 bei der Zeile „Einträge“.</summary>
    Budget: Double;
    LastWarn: Boolean;
    MeanWarn: Boolean;
    MaxWarn: Boolean;
  end;

  TDpccTimingRows = record
  public
    /// <summary>Zeilen: Kontext, je Quelle eine, Filtern und Sortieren, Zeichnen, bis zur Liste, Einträge.
    /// AQueries älteste zuerst; „letzte“ ist die neueste.</summary>
    class function Build(const AQueries: TArray<TDpccQueryTiming>): TArray<TDpccTimingRow>; static;
    /// <summary>"3.2" bzw. "–" ohne Wert.</summary>
    class function Ms(AValue: Double): string; static;
    /// <summary>Anzahl ohne Nachkommastellen bzw. "–".</summary>
    class function CountText(AValue: Double): string; static;
  end;

  /// <summary>Messpunkte und die letzten Abfragen (#479); eine Instanz je Prozess (Shared).</summary>
  TDpccQueryTimings = class
  public const
    cCapacity = 50;
  private class var
    FEnabled: Boolean;
    FShared: TDpccQueryTimings;
  private
    FLock: TCriticalSection;
    FQueries: TList<TDpccQueryTiming>;
    FNextId: Integer;
    FCurrent: Integer;
    FCurrentStart: Int64;
    FVersion: Integer;
    function IndexOf(AId: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Gemeinsame Instanz der Messpunkte; lebt bis zum Entladen des Packages.</summary>
    class function Shared: TDpccQueryTimings; static;
    /// <summary>Messung an; aus (Vorgabe) tun die Messpunkte nichts.</summary>
    class property Enabled: Boolean read FEnabled write FEnabled;
    /// <summary>Hochauflösender Zeitstempel für MsSince.</summary>
    class function Stamp: Int64; static;
    class function MsSince(AStamp: Int64): Double; static;
    /// <summary>Neue Abfrage; Kontext = Zeit seit AStart (0 = nicht gemessen). Ergebnis: Kennung.</summary>
    function BeginQuery(AStart: Int64; const AKind, AFileName: string): Integer;
    /// <summary>Kennung der laufenden Abfrage; 0 ohne.</summary>
    function Current: Integer;
    /// <summary>Quelle AName der Abfrage AId ist fertig (auch abgebrochen oder über dem Zeitlimit).</summary>
    procedure ProviderDone(AId: Integer; const AName: string; AMs: Double; ACount: Integer);
    procedure FilterSorted(AMs: Double; ACount, AShown: Integer);
    /// <summary>Die laufende Abfrage zeigt ihre erste Liste; zählt nur einmal je Abfrage.</summary>
    procedure ListShown;
    procedure Drawn(AMs: Double);
    procedure Clear;
    /// <summary>Kopie der letzten Abfragen, älteste zuerst.</summary>
    function Snapshot: TArray<TDpccQueryTiming>;
    /// <summary>Zählt jede Änderung; das Fenster zeichnet nur bei neuem Stand neu.</summary>
    function Version: Integer;
  end;

  TDpccTimingReportInput = record
    DpccVersion: string;
    IdeVersion: string;
    Platform: string;
    /// <summary>Einstellungen des Plugins als JSON; Pfade werden gekürzt.</summary>
    Settings: string;
    /// <summary>Benutzer-, Rechner- und Domänenname; werden zu &lt;benutzer&gt;.</summary>
    Identity: TArray<string>;
    /// <summary>Dateinamen der Abfragen aufnehmen (nur auf Wunsch).</summary>
    FileNames: Boolean;
    Created: TDateTime;
    /// <summary>Abschnitt „Plugin-Zeiten“ (TDpccPluginReport) vor den Einstellungen; '' ohne.</summary>
    Plugin: string;
  end;

  TDpccTimingReport = record
  public const
    /// <summary>Letzte Diagnosedaten neben den Diagnoselogs (%LOCALAPPDATA%\dpcc\Logs\Diagnose).</summary>
    cFileName = 'dpcc-diagnosemodus.txt';
  public
    /// <summary>Text für „Bericht kopieren“: Versionen, Budgets, letzte Abfrage, Mittelwert und Maximum, die
    /// Abfragen einzeln (neueste zuerst) und die Einstellungen. Kein Quelltext; Dateinamen nur mit
    /// AInput.FileNames.</summary>
    class function Build(const AQueries: TArray<TDpccQueryTiming>; const AInput: TDpccTimingReportInput): string;
      static;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.Math,
  dpcc.Text.Anonymize,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TTimingText = (Context, Entries, Visible, Source, Entries2, StepLastMeanMaximumBudget, DpccDiagnosticMode479,
    Created, Platform, Budget409ContextMsSource, ContainsNoSourceCodeFile, TimesInMsLastQuery, QueriesNewestFirst,
    NoQueryMeasuredYet, Settings);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TTimingText] of string = (
    (' | Kontext ',
     ' | Einträge ',
     ', sichtbar ',
     'Quelle ',
     'Einträge',
     'Schritt | letzte | Mittel | Maximum | Budget',
     '# dpcc-Diagnosemodus (#479)',
     'Erstellt: ',
     ', Plattform: ',
     'Budget (#409): Kontext %d ms, Quelle %d ms, Filtern und Sortieren %d ms, Zeichnen %d ms, bis zur Liste %d ms. (!) = über dem Budget.',
     'Enthält keinen Quelltext; Dateinamen: ',
     '## Zeiten in ms: letzte Abfrage, Mittelwert und Maximum der letzten %d',
     '## Abfragen, neueste zuerst',
     'Noch keine Abfrage gemessen.',
     '## Einstellungen'),
    (' | Context ',
     ' | Entries ',
     ', visible ',
     'Source ',
     'Entries',
     'Step | last | mean | maximum | budget',
     '# dpcc diagnostic mode (#479)',
     'Created: ',
     ', platform: ',
     'Budget (#409): context %d ms, source %d ms, filter and sort %d ms, draw %d ms, until the list %d ms. (!) = over budget.',
     'Contains no source code; file names: ',
     '## Times in ms: last query, mean and maximum of the last %d',
     '## Queries, newest first',
     'No query measured yet.',
     '## Settings'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TTimingText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

const
  cStepNames: array[TDpccLanguage, TDpccTimingStep] of string = (
    ('Kontext', 'Quelle', 'Filtern und Sortieren', 'Zeichnen', 'Bis zur Liste'),
    ('Context', 'Source', 'Filter and sort', 'Draw', 'Until the list'));
  cNoValue = '–';

function Invariant: TFormatSettings;
begin
  Result := FormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := ',';
end;

{ TDpccTimingBudget }

class function TDpccTimingBudget.LimitMs(AStep: TDpccTimingStep): Double;
begin
  case AStep of
    TDpccTimingStep.Context:
      Result := cContextMs;
    TDpccTimingStep.Provider:
      Result := cProviderMs;
    TDpccTimingStep.FilterSort:
      Result := cFilterSortMs;
    TDpccTimingStep.Draw:
      Result := cDrawMs;
  else
    Result := cFirstVisibleMs;
  end;
end;

class function TDpccTimingBudget.Exceeded(AStep: TDpccTimingStep; AMs: Double): Boolean;
begin
  Result := (AMs >= 0) and (AMs > LimitMs(AStep));
end;

{ TDpccQueryTiming }

function TDpccQueryTiming.Value(AStep: TDpccTimingStep): Double;
var
  mProvider: TDpccProviderTiming;
begin
  case AStep of
    TDpccTimingStep.Context:
      Result := ContextMs;
    TDpccTimingStep.Provider:
      begin
        Result := -1;
        for mProvider in Providers do
        begin
          Result := Max(Result, mProvider.Ms);
        end;
      end;
    TDpccTimingStep.FilterSort:
      Result := FilterSortMs;
    TDpccTimingStep.Draw:
      Result := DrawMs;
  else
    Result := FirstVisibleMs;
  end;
end;

function TDpccQueryTiming.ProviderIndex(const AName: string): Integer;
begin
  for Result := 0 to High(Providers) do
  begin
    if Providers[Result].Name = AName then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function TDpccQueryTiming.Exceeded: Boolean;
var
  mStep: TDpccTimingStep;
begin
  for mStep := Low(TDpccTimingStep) to High(TDpccTimingStep) do
  begin
    if TDpccTimingBudget.Exceeded(mStep, Value(mStep)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TDpccTimingStat }

procedure TDpccTimingStat.Add(AValue: Double);
begin
  if AValue < 0 then
  begin
    Exit;
  end;
  if (Count = 0) or (AValue > Maximum) then
  begin
    Maximum := AValue;
  end;
  Inc(Count);
  Sum := Sum + AValue;
end;

function TDpccTimingStat.Mean: Double;
begin
  if Count = 0 then
  begin
    Result := -1;
  end
  else
  begin
    Result := Sum / Count;
  end;
end;

function TDpccTimingStat.Peak: Double;
begin
  if Count = 0 then
  begin
    Result := -1;
  end
  else
  begin
    Result := Maximum;
  end;
end;

{ TDpccTimingStats }

class function TDpccTimingStats.From(const AQueries: TArray<TDpccQueryTiming>): TDpccTimingStats;
var
  mQuery: TDpccQueryTiming;
  mProvider: TDpccProviderTiming;
  mStep: TDpccTimingStep;
  mIndex: Integer;
begin
  Result := Default(TDpccTimingStats);
  Result.ProviderNames := nil;
  Result.Providers := nil;
  for mQuery in AQueries do
  begin
    Inc(Result.Queries);
    for mStep := Low(TDpccTimingStep) to High(TDpccTimingStep) do
    begin
      Result.Steps[mStep].Add(mQuery.Value(mStep));
    end;
    if mQuery.Count > 0 then
    begin
      Result.Entries.Add(mQuery.Count);
    end;
    for mProvider in mQuery.Providers do
    begin
      mIndex := Length(Result.ProviderNames) - 1;
      while (mIndex >= 0) and (Result.ProviderNames[mIndex] <> mProvider.Name) do
      begin
        Dec(mIndex);
      end;
      if mIndex < 0 then
      begin
        Result.ProviderNames := Result.ProviderNames + [mProvider.Name];
        SetLength(Result.Providers, Length(Result.Providers) + 1);
        Result.Providers[High(Result.Providers)] := Default(TDpccTimingStat);
        mIndex := High(Result.Providers);
      end;
      Result.Providers[mIndex].Add(mProvider.Ms);
    end;
  end;
end;

function TDpccTimingStats.Provider(const AName: string): TDpccTimingStat;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ProviderNames) do
  begin
    if ProviderNames[mIndex] = AName then
    begin
      Exit(Providers[mIndex]);
    end;
  end;
  Result := Default(TDpccTimingStat);
end;

{ TDpccTimingRows }

function StepRow(AStep: TDpccTimingStep; ALast: Double; const AStat: TDpccTimingStat): TDpccTimingRow;
begin
  Result := Default(TDpccTimingRow);
  Result.Kind := TDpccTimingRowKind.Step;
  Result.Step := AStep;
  Result.Name := '';
  Result.Last := ALast;
  Result.Mean := AStat.Mean;
  Result.Maximum := AStat.Peak;
  Result.Budget := TDpccTimingBudget.LimitMs(AStep);
  Result.LastWarn := TDpccTimingBudget.Exceeded(AStep, Result.Last);
  Result.MeanWarn := TDpccTimingBudget.Exceeded(AStep, Result.Mean);
  Result.MaxWarn := TDpccTimingBudget.Exceeded(AStep, Result.Maximum);
end;

class function TDpccTimingRows.Build(const AQueries: TArray<TDpccQueryTiming>): TArray<TDpccTimingRow>;
var
  mStats: TDpccTimingStats;
  mLast: TDpccQueryTiming;
  mRow: TDpccTimingRow;
  mIndex, mAt: Integer;
  mStep: TDpccTimingStep;
begin
  Result := nil;
  mStats := TDpccTimingStats.From(AQueries);
  mLast := Default(TDpccQueryTiming);
  mLast.ContextMs := -1;
  mLast.FilterSortMs := -1;
  mLast.DrawMs := -1;
  mLast.FirstVisibleMs := -1;
  mLast.Providers := nil;
  if Length(AQueries) > 0 then
  begin
    mLast := AQueries[High(AQueries)];
  end;
  Result := Result + [StepRow(TDpccTimingStep.Context, mLast.ContextMs, mStats.Steps[TDpccTimingStep.Context])];
  // Je Quelle eine Zeile mit ihrem Namen; fehlt sie in der letzten Abfrage, bleibt „letzte“ leer.
  for mIndex := 0 to High(mStats.ProviderNames) do
  begin
    mRow := StepRow(TDpccTimingStep.Provider, -1, mStats.Providers[mIndex]);
    mRow.Kind := TDpccTimingRowKind.Provider;
    mRow.Name := mStats.ProviderNames[mIndex];
    mAt := mLast.ProviderIndex(mRow.Name);
    if mAt >= 0 then
    begin
      mRow.Last := mLast.Providers[mAt].Ms;
    end;
    mRow.LastWarn := TDpccTimingBudget.Exceeded(TDpccTimingStep.Provider, mRow.Last);
    Result := Result + [mRow];
  end;
  for mStep in [TDpccTimingStep.FilterSort, TDpccTimingStep.Draw, TDpccTimingStep.FirstVisible] do
  begin
    Result := Result + [StepRow(mStep, mLast.Value(mStep), mStats.Steps[mStep])];
  end;
  mRow := Default(TDpccTimingRow);
  mRow.Kind := TDpccTimingRowKind.Entries;
  mRow.Name := '';
  mRow.Last := -1;
  if Length(AQueries) > 0 then
  begin
    mRow.Last := mLast.Count;
  end;
  mRow.Mean := mStats.Entries.Mean;
  mRow.Maximum := mStats.Entries.Peak;
  Result := Result + [mRow];
end;

class function TDpccTimingRows.Ms(AValue: Double): string;
begin
  if AValue < 0 then
  begin
    Result := cNoValue;
  end
  else
  begin
    Result := FormatFloat('0.0', AValue, Invariant);
  end;
end;

class function TDpccTimingRows.CountText(AValue: Double): string;
begin
  if AValue < 0 then
  begin
    Result := cNoValue;
  end
  else
  begin
    Result := IntToStr(Round(AValue));
  end;
end;

{ TDpccQueryTimings }

constructor TDpccQueryTimings.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FQueries := TList<TDpccQueryTiming>.Create;
end;

destructor TDpccQueryTimings.Destroy;
begin
  FQueries.Free;
  FLock.Free;
  inherited;
end;

class function TDpccQueryTimings.Shared: TDpccQueryTimings;
begin
  Result := FShared;
end;

class function TDpccQueryTimings.Stamp: Int64;
begin
  Result := TStopwatch.GetTimeStamp;
end;

class function TDpccQueryTimings.MsSince(AStamp: Int64): Double;
begin
  Result := (TStopwatch.GetTimeStamp - AStamp) * 1000.0 / TStopwatch.Frequency;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

function TDpccQueryTimings.IndexOf(AId: Integer): Integer;
begin
  // Neueste zuerst: Meldungen betreffen fast immer die laufende Abfrage.
  for Result := FQueries.Count - 1 downto 0 do
  begin
    if FQueries[Result].Id = AId then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function TDpccQueryTimings.BeginQuery(AStart: Int64; const AKind, AFileName: string): Integer;
var
  mQuery: TDpccQueryTiming;
begin
  mQuery := Default(TDpccQueryTiming);
  mQuery.Started := Now;
  mQuery.Kind := AKind;
  mQuery.FileName := AFileName;
  mQuery.ContextMs := -1;
  if AStart <> 0 then
  begin
    mQuery.ContextMs := MsSince(AStart);
  end;
  mQuery.Providers := nil;
  mQuery.FilterSortMs := -1;
  mQuery.DrawMs := -1;
  mQuery.FirstVisibleMs := -1;
  FLock.Enter;
  try
    Inc(FNextId);
    mQuery.Id := FNextId;
    FCurrent := mQuery.Id;
    FCurrentStart := AStart;
    if FCurrentStart = 0 then
    begin
      FCurrentStart := Stamp;
    end;
    FQueries.Add(mQuery);
    while FQueries.Count > cCapacity do
    begin
      FQueries.Delete(0);
    end;
    Inc(FVersion);
    Result := mQuery.Id;
  finally
    FLock.Leave;
  end;
end;

function TDpccQueryTimings.Current: Integer;
begin
  FLock.Enter;
  try
    Result := FCurrent;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccQueryTimings.ProviderDone(AId: Integer; const AName: string; AMs: Double; ACount: Integer);
var
  mIndex, mAt: Integer;
  mQuery: TDpccQueryTiming;
  mProvider: TDpccProviderTiming;
begin
  FLock.Enter;
  try
    mIndex := IndexOf(AId);
    if mIndex < 0 then
    begin
      Exit;
    end;
    mQuery := FQueries[mIndex];
    mProvider.Name := AName;
    mProvider.Ms := AMs;
    mProvider.Count := ACount;
    // Neu fragen (#431) ersetzt die Zeit derselben Quelle; die Liste wird kopiert, die Momentaufnahmen bleiben.
    mQuery.Providers := Copy(mQuery.Providers);
    mAt := mQuery.ProviderIndex(AName);
    if mAt >= 0 then
    begin
      mQuery.Providers[mAt] := mProvider;
    end
    else
    begin
      mQuery.Providers := mQuery.Providers + [mProvider];
    end;
    FQueries[mIndex] := mQuery;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccQueryTimings.FilterSorted(AMs: Double; ACount, AShown: Integer);
var
  mIndex: Integer;
  mQuery: TDpccQueryTiming;
begin
  FLock.Enter;
  try
    mIndex := IndexOf(FCurrent);
    if mIndex < 0 then
    begin
      Exit;
    end;
    mQuery := FQueries[mIndex];
    mQuery.FilterSortMs := Max(mQuery.FilterSortMs, AMs);
    Inc(mQuery.FilterSortSteps);
    mQuery.Count := ACount;
    mQuery.Shown := AShown;
    FQueries[mIndex] := mQuery;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccQueryTimings.ListShown;
var
  mIndex: Integer;
  mQuery: TDpccQueryTiming;
begin
  FLock.Enter;
  try
    mIndex := IndexOf(FCurrent);
    if (mIndex < 0) or (FQueries[mIndex].FirstVisibleMs >= 0) then
    begin
      Exit;
    end;
    mQuery := FQueries[mIndex];
    mQuery.FirstVisibleMs := MsSince(FCurrentStart);
    FQueries[mIndex] := mQuery;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccQueryTimings.Drawn(AMs: Double);
var
  mIndex: Integer;
  mQuery: TDpccQueryTiming;
begin
  FLock.Enter;
  try
    mIndex := IndexOf(FCurrent);
    if mIndex < 0 then
    begin
      Exit;
    end;
    mQuery := FQueries[mIndex];
    mQuery.DrawMs := Max(mQuery.DrawMs, AMs);
    Inc(mQuery.DrawSteps);
    FQueries[mIndex] := mQuery;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccQueryTimings.Clear;
begin
  FLock.Enter;
  try
    FQueries.Clear;
    FCurrent := 0;
    Inc(FVersion);
  finally
    FLock.Leave;
  end;
end;

function TDpccQueryTimings.Snapshot: TArray<TDpccQueryTiming>;
begin
  FLock.Enter;
  try
    Result := FQueries.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TDpccQueryTimings.Version: Integer;
begin
  FLock.Enter;
  try
    Result := FVersion;
  finally
    FLock.Leave;
  end;
end;

{ TDpccTimingReport }

function Mark(AWarn: Boolean): string;
begin
  if AWarn then
  begin
    Result := ' (!)';
  end
  else
  begin
    Result := '';
  end;
end;

function QueryLine(const AQuery: TDpccQueryTiming; AFileNames: Boolean): string;
var
  mProvider: TDpccProviderTiming;
  mStep: TDpccTimingStep;
begin
  Result := FormatDateTime('hh":"nn":"ss', AQuery.Started) + ' ' + AQuery.Kind;
  if AFileNames and (AQuery.FileName <> '') then
  begin
    Result := Result + ', ' + AQuery.FileName;
  end;
  Result := Result + UiText(TTimingText.Context) + TDpccTimingRows.Ms(AQuery.ContextMs) +
    Mark(TDpccTimingBudget.Exceeded(TDpccTimingStep.Context, AQuery.ContextMs));
  for mProvider in AQuery.Providers do
  begin
    Result := Result + ' | ' + mProvider.Name + ' ' + TDpccTimingRows.Ms(mProvider.Ms) +
      Mark(TDpccTimingBudget.Exceeded(TDpccTimingStep.Provider, mProvider.Ms)) + ' (' + IntToStr(mProvider.Count) +
      ')';
  end;
  for mStep in [TDpccTimingStep.FilterSort, TDpccTimingStep.Draw, TDpccTimingStep.FirstVisible] do
  begin
    Result := Result + ' | ' + cStepNames[TDpccTextLanguage.Current, mStep] + ' ' +
      TDpccTimingRows.Ms(AQuery.Value(mStep)) +
      Mark(TDpccTimingBudget.Exceeded(mStep, AQuery.Value(mStep)));
  end;
  Result := Result + UiText(TTimingText.Entries) + IntToStr(AQuery.Count) + UiText(TTimingText.Visible) +
    IntToStr(AQuery.Shown);
end;

function RowCaption(const ARow: TDpccTimingRow): string;
begin
  case ARow.Kind of
    TDpccTimingRowKind.Provider:
      Result := UiText(TTimingText.Source) + ARow.Name;
    TDpccTimingRowKind.Entries:
      Result := UiText(TTimingText.Entries2);
  else
    Result := cStepNames[TDpccTextLanguage.Current, ARow.Step];
  end;
end;

function RowLine(const ARow: TDpccTimingRow): string;
begin
  if ARow.Kind = TDpccTimingRowKind.Entries then
  begin
    Result := RowCaption(ARow) + ' | ' + TDpccTimingRows.CountText(ARow.Last) + ' | ' +
      TDpccTimingRows.CountText(ARow.Mean) + ' | ' + TDpccTimingRows.CountText(ARow.Maximum) + ' | ' + cNoValue;
  end
  else
  begin
    Result := RowCaption(ARow) + ' | ' + TDpccTimingRows.Ms(ARow.Last) + Mark(ARow.LastWarn) + ' | ' +
      TDpccTimingRows.Ms(ARow.Mean) + Mark(ARow.MeanWarn) + ' | ' + TDpccTimingRows.Ms(ARow.Maximum) +
      Mark(ARow.MaxWarn) + ' | ' + TDpccTimingRows.Ms(ARow.Budget);
  end;
end;

/// <summary>Tabelle „Schritt | letzte | Mittel | Maximum | Budget“ des Berichts.</summary>
procedure AddStepTable(ALines: TStrings; const AQueries: TArray<TDpccQueryTiming>);
var
  mRow: TDpccTimingRow;
begin
  ALines.Add(UiText(TTimingText.StepLastMeanMaximumBudget));
  ALines.Add('--- | --- | --- | --- | ---');
  for mRow in TDpccTimingRows.Build(AQueries) do
  begin
    ALines.Add(RowLine(mRow));
  end;
end;

class function TDpccTimingReport.Build(const AQueries: TArray<TDpccQueryTiming>;
  const AInput: TDpccTimingReportInput): string;
var
  mLines: TStringList;
  mIndex: Integer;
  mSettings: string;
begin
  mLines := TStringList.Create;
  try
    mLines.Add(UiText(TTimingText.DpccDiagnosticMode479));
    mLines.Add('');
    mLines.Add(UiText(TTimingText.Created) + FormatDateTime('yyyy-mm-dd hh":"nn', AInput.Created));
    mLines.Add('dpcc: ' + AInput.DpccVersion + ', IDE: ' + AInput.IdeVersion + UiText(TTimingText.Platform) + AInput.Platform);
    mLines.Add(Format(UiText(TTimingText.Budget409ContextMsSource),
      [TDpccTimingBudget.cContextMs, TDpccTimingBudget.cProviderMs,
      TDpccTimingBudget.cFilterSortMs, TDpccTimingBudget.cDrawMs, TDpccTimingBudget.cFirstVisibleMs]));
    mLines.Add(UiText(TTimingText.ContainsNoSourceCodeFile) + BoolToStr(AInput.FileNames, True) + '.');
    mLines.Add('');
    mLines.Add(Format(UiText(TTimingText.TimesInMsLastQuery),
      [Length(AQueries)]));
    mLines.Add('');
    AddStepTable(mLines, AQueries);
    mLines.Add('');
    mLines.Add(UiText(TTimingText.QueriesNewestFirst));
    mLines.Add('');
    for mIndex := High(AQueries) downto 0 do
    begin
      mLines.Add(QueryLine(AQueries[mIndex], AInput.FileNames));
    end;
    if Length(AQueries) = 0 then
    begin
      mLines.Add(UiText(TTimingText.NoQueryMeasuredYet));
    end;
    mLines.Add('');
    if AInput.Plugin <> '' then
    begin
      mLines.Add(AInput.Plugin);
    end;
    mLines.Add(UiText(TTimingText.Settings));
    mLines.Add('');
    // Pfade (Serverpfad u. a.) wie im Fehlerbericht kürzen; Benutzer- und Rechnername ersetzen.
    mSettings := TTextAnonymizer.AnonymizePaths(AInput.Settings, nil, AInput.Identity);
    mLines.Add(mSettings);
    Result := mLines.Text;
  finally
    mLines.Free;
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Diagnostics.Timing', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);
  TDpccQueryTimings.FShared := TDpccQueryTimings.Create;

finalization
  TDpccQueryTimings.FEnabled := False;
  FreeAndNil(TDpccQueryTimings.FShared);

end.
