unit dpcc.Core.Completion.Composite;

// Führt mehrere Datenquellen der Vervollständigung zusammen (#408). Ein Query
// geht an alle Quellen; ihre Teilmengen werden sofort weitergereicht, Complete
// kommt einmal, wenn alle Quellen fertig sind. Nach Cancel oder einem neuen
// Query gelangt nichts mehr aus dem alten Query an dessen Senke, auch wenn sich
// eine Quelle nicht daran hält.
// Absturzsicherheit (#493): Jede Quelle läuft mit Zeitlimit (TDpccTimeLimit,
// Standard 200 ms) und über die Sicherung je Quelle. Wirft eine Quelle, hängt
// sie oder ist sie abgeschaltet, gilt ihr Teil als fertig; die übrigen Quellen
// liefern weiter. Nach 3 Fehlern in 5 Minuten fällt nur diese Quelle aus.
// Eine Zeitüberschreitung ist kein Fehler: Sie zählt nicht zur Sicherung,
// sondern steht als „langsam“ im Protokoll (ReportProviderSlow). Früher
// schaltete ein beschäftigter Rechner so nach drei langsamen Anfragen die
// Quelle ab. Damit eine Quelle, die länger braucht, nicht bei jedem Tastendruck
// einen weiteren Arbeiter belegt, wird sie übersprungen, solange ihr voriger
// Aufruf noch läuft.
// Diagnosemodus (#479): Ist die Messung an, meldet jede Teilsenke beim ersten
// Complete Name, Dauer seit ihrem Query und Zahl ihrer Einträge an
// TDpccQueryTimings (auch bei Fehler oder Zeitlimit); aus nimmt sie keinen
// Zeitstempel.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.TimeLimit;

type
  TDpccCompletionProviders = class(TInterfacedObject, IDpccCompletionProvider)
  private type
    /// <summary>Gemeinsamer Zustand eines Query; lebt, solange eine Teilsenke ihn hält.</summary>
    TQueryState = class(TInterfacedObject)
    private
      FLock: TCriticalSection;
      FSink: IDpccCompletionSink;
      FRemaining: Integer;
    public
      constructor Create(const ASink: IDpccCompletionSink; ACount: Integer);
      destructor Destroy; override;
      procedure Add(const AItems: TDpccCompletionItems);
      procedure Incomplete;
      procedure Syntax(const ANotice: TDpccSyntaxNotice);
      procedure PartDone;
      procedure Cancel;
    end;

    /// <summary>Senke je Quelle; zählt deren Complete nur einmal.</summary>
    TPartSink = class(TInterfacedObject, IDpccCompletionSink)
    private
      FState: TQueryState;
      FStateRef: IInterface;
      FDone: Integer;
      // Diagnosemodus (#479): Name der Quelle, Abfrage (0 = keine Messung), Beginn und Zahl der Einträge.
      FName: string;
      FTimingId: Integer;
      FStarted: Int64;
      FCount: Integer;
    public
      constructor Create(AState: TQueryState; const AName: string; ATimingId: Integer);
      procedure AddItems(const AItems: TDpccCompletionItems);
      procedure MarkIncomplete;
      procedure MarkSyntax(const ANotice: TDpccSyntaxNotice);
      procedure Complete;
    end;
    /// <summary>Läuft der vorige Aufruf einer Quelle noch (nach dem Zeitlimit aufgegeben)? Lebt, solange ein
    /// Arbeiter ihn hält.</summary>
    TRunning = class(TInterfacedObject)
    public
      Active: Integer;
      Started: Int64;
    end;
    TEntry = record
      Provider: IDpccCompletionProvider;
      Name: string;
      Running: TRunning;
      RunningRef: IInterface;
    end;
  private
    FLock: TCriticalSection;
    FProviders: TArray<TEntry>;
    FCurrent: TQueryState;
    FCurrentRef: IInterface;
    FTimeLimitMs: Integer;
    /// <summary>Quelle antwortet nicht in der Zeit: Teil abschließen, Abbruch anfordern, melden.</summary>
    procedure Abandon(const AEntry: TEntry; const APart: IDpccCompletionSink);
    procedure QueryOne(const AEntry: TEntry; const AContext: TDpccContext; const APart: IDpccCompletionSink);
    /// <summary>Arbeit eines Arbeiters für AEntry: fragt die Quelle, misst sie und gibt Running wieder frei.
    /// </summary>
    class function Work(const AEntry: TEntry; const AContext: TDpccContext;
      const APart: IDpccCompletionSink): TProc; static;
  public
    /// <summary>Name einer Quelle ohne IDpccNamedProvider, in der Sprache der Oberfläche.</summary>
    class function DefaultName: string; static;
    constructor Create;
    destructor Destroy; override;
    /// <summary>Quelle anmelden; ihr Name (IDpccNamedProvider) gilt für die Sicherung je Quelle.</summary>
    procedure Add(const AProvider: IDpccCompletionProvider);
    /// <summary>Zeitlimit je Quelle im aufrufenden Thread; -1 (Standard) = TDpccTimeLimit.LimitMs.</summary>
    property TimeLimitMs: Integer read FTimeLimitMs write FTimeLimitMs;
    { IDpccCompletionProvider }
    procedure Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
    procedure Cancel;
  end;

implementation

uses
  System.Classes,
  dpcc.Core.Diagnostics.PluginTimings,
  dpcc.Core.Diagnostics.Timing,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TCompositeText = (Completion);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TCompositeText] of string = (
    ('Vervollständigung'),
    ('Completion'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TCompositeText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

function TimeLimitOf(ALimitMs: Integer): Integer;
begin
  Result := ALimitMs;
  if Result < 0 then
  begin
    Result := TDpccTimeLimit.LimitMs;
  end;
end;

{ TDpccCompletionProviders.TQueryState }

constructor TDpccCompletionProviders.TQueryState.Create(const ASink: IDpccCompletionSink; ACount: Integer);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FSink := ASink;
  FRemaining := ACount;
end;

destructor TDpccCompletionProviders.TQueryState.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TDpccCompletionProviders.TQueryState.Add(const AItems: TDpccCompletionItems);
begin
  if Length(AItems) = 0 then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    if FSink <> nil then
    begin
      FSink.AddItems(AItems);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccCompletionProviders.TQueryState.Incomplete;
begin
  // Ist eine Quelle gekürzt, ist es die ganze Liste.
  FLock.Enter;
  try
    if FSink <> nil then
    begin
      FSink.MarkIncomplete;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccCompletionProviders.TQueryState.Syntax(const ANotice: TDpccSyntaxNotice);
begin
  // Hinweis bei unvollständigem Code (#457): Ihn meldet nur der Server; weiterreichen wie gekürzt.
  FLock.Enter;
  try
    if FSink <> nil then
    begin
      FSink.MarkSyntax(ANotice);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccCompletionProviders.TQueryState.PartDone;
begin
  FLock.Enter;
  try
    Dec(FRemaining);
    if (FRemaining = 0) and (FSink <> nil) then
    begin
      FSink.Complete;
      FSink := nil;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccCompletionProviders.TQueryState.Cancel;
begin
  FLock.Enter;
  try
    FSink := nil;
  finally
    FLock.Leave;
  end;
end;

{ TDpccCompletionProviders.TPartSink }

constructor TDpccCompletionProviders.TPartSink.Create(AState: TQueryState; const AName: string;
  ATimingId: Integer);
begin
  inherited Create;
  FState := AState;
  FStateRef := AState;
  FName := AName;
  FTimingId := ATimingId;
  if FTimingId > 0 then
  begin
    FStarted := TDpccQueryTimings.Stamp;
  end;
end;

procedure TDpccCompletionProviders.TPartSink.AddItems(const AItems: TDpccCompletionItems);
begin
  if TInterlocked.CompareExchange(FDone, 0, 0) = 0 then
  begin
    if FTimingId > 0 then
    begin
      TInterlocked.Add(FCount, Length(AItems));
    end;
    FState.Add(AItems);
  end;
end;

procedure TDpccCompletionProviders.TPartSink.MarkIncomplete;
begin
  if TInterlocked.CompareExchange(FDone, 0, 0) = 0 then
  begin
    FState.Incomplete;
  end;
end;

procedure TDpccCompletionProviders.TPartSink.MarkSyntax(const ANotice: TDpccSyntaxNotice);
begin
  if TInterlocked.CompareExchange(FDone, 0, 0) = 0 then
  begin
    FState.Syntax(ANotice);
  end;
end;

procedure TDpccCompletionProviders.TPartSink.Complete;
var
  mTimings: TDpccQueryTimings;
begin
  if TInterlocked.Exchange(FDone, 1) <> 0 then
  begin
    Exit;
  end;
  // Vor PartDone: Das Popup soll die Zeit der Quelle schon kennen, wenn die Liste fertig ist.
  mTimings := TDpccQueryTimings.Shared;
  if (FTimingId > 0) and TDpccQueryTimings.Enabled and (mTimings <> nil) then
  begin
    mTimings.ProviderDone(FTimingId, FName, TDpccQueryTimings.MsSince(FStarted),
      TInterlocked.CompareExchange(FCount, 0, 0));
  end;
  FState.PartDone;
end;

{ TDpccCompletionProviders }

class function TDpccCompletionProviders.DefaultName: string;
begin
  Result := UiText(TCompositeText.Completion);
end;

constructor TDpccCompletionProviders.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FTimeLimitMs := -1;
end;

destructor TDpccCompletionProviders.Destroy;
begin
  Cancel;
  FLock.Free;
  inherited;
end;

procedure TDpccCompletionProviders.Add(const AProvider: IDpccCompletionProvider);
var
  mEntry: TEntry;
  mNamed: IDpccNamedProvider;
begin
  mEntry.Provider := AProvider;
  mEntry.Name := DefaultName;
  if Supports(AProvider, IDpccNamedProvider, mNamed) and (mNamed.ProviderName <> '') then
  begin
    mEntry.Name := mNamed.ProviderName;
  end;
  mEntry.Running := TRunning.Create;
  mEntry.RunningRef := mEntry.Running;
  FLock.Enter;
  try
    FProviders := FProviders + [mEntry];
  finally
    FLock.Leave;
  end;
end;

class function TDpccCompletionProviders.Work(const AEntry: TEntry; const AContext: TDpccContext;
  const APart: IDpccCompletionSink): TProc;
var
  mProvider: IDpccCompletionProvider;
  mPart: IDpccCompletionSink;
  mContext: TDpccContext;
  mRunning: TRunning;
  mRunningRef: IInterface;
  mName: string;
begin
  mProvider := AEntry.Provider;
  mPart := APart;
  mContext := AContext;
  mRunning := AEntry.Running;
  mRunningRef := AEntry.RunningRef;
  mName := AEntry.Name;
  Result :=
    procedure
    var
      mStarted: Int64;
    begin
      // Diagnose-Fenster, Reiter „Hintergrund“: Arbeitszeit der Quelle, auch über dem Zeitlimit.
      mStarted := TDpccPluginTimings.StampIfEnabled;
      try
        mProvider.Query(mContext, mPart);
      finally
        TDpccPluginTimings.NoteSource(mName, mStarted);
        // Über mRunningRef lebt der Zustand, auch wenn die Quellen inzwischen freigegeben sind.
        if mRunningRef <> nil then
        begin
          TInterlocked.Exchange(mRunning.Active, 0);
        end;
      end;
    end;
end;

procedure TDpccCompletionProviders.Abandon(const AEntry: TEntry; const APart: IDpccCompletionSink);
begin
  // Langsam: nicht länger warten und abbrechen; was später noch kommt, verwirft die Teilsenke. Kein Fehler.
  APart.Complete;
  try
    AEntry.Provider.Cancel;
  except
    on E: Exception do
      TDpccGuard.ReportProvider(AEntry.Name, E);
  end;
  TDpccGuard.ReportProviderSlow(AEntry.Name, Format('keine Antwort innerhalb von %d ms',
    [TimeLimitOf(FTimeLimitMs)]));
end;

procedure TDpccCompletionProviders.QueryOne(const AEntry: TEntry; const AContext: TDpccContext;
  const APart: IDpccCompletionSink);
var
  mPart: IDpccCompletionSink;
  mRunning: TRunning;
  mError: string;
begin
  if TDpccGuard.ProviderDisabled(AEntry.Name) then
  begin
    APart.Complete;
    Exit;
  end;
  mRunning := AEntry.Running;
  // Der vorige Aufruf läuft noch: keinen weiteren Arbeiter belegen, diesmal ohne diese Quelle.
  if TInterlocked.CompareExchange(mRunning.Active, 1, 0) <> 0 then
  begin
    APart.Complete;
    TDpccGuard.ReportProviderSlow(AEntry.Name, Format('vorige Anfrage läuft seit %d ms, übersprungen',
      [Int64(TThread.GetTickCount64) - TInterlocked.Read(mRunning.Started)]));
    Exit;
  end;
  TInterlocked.Exchange(mRunning.Started, Int64(TThread.GetTickCount64));
  mPart := APart;
  case TDpccTimeLimit.Run(Work(AEntry, AContext, APart), mError, FTimeLimitMs) of
    TDpccTimedOutcome.Done:
      ;
    TDpccTimedOutcome.Failed:
      begin
        // Auch ohne gestarteten Aufruf (dpcc wird beendet) wieder frei.
        TInterlocked.Exchange(mRunning.Active, 0);
        mPart.Complete;
        TDpccGuard.ReportProvider(AEntry.Name, mError);
      end;
  else
    Abandon(AEntry, mPart);
  end;
end;

procedure TDpccCompletionProviders.Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
var
  mProviders: TArray<TEntry>;
  mState: TQueryState;
  mStateRef: IInterface;
  mEntry: TEntry;
  mPart: IDpccCompletionSink;
  mTimingId: Integer;
begin
  Cancel;
  // Diagnosemodus (#479): Zeiten gehören zur laufenden Abfrage; aus wird nichts gemessen.
  mTimingId := 0;
  if TDpccQueryTimings.Enabled and (TDpccQueryTimings.Shared <> nil) then
  begin
    mTimingId := TDpccQueryTimings.Shared.Current;
  end;
  FLock.Enter;
  try
    mProviders := FProviders;
    mState := TQueryState.Create(ASink, Length(mProviders));
    mStateRef := mState;
    FCurrent := mState;
    FCurrentRef := mStateRef;
  finally
    FLock.Leave;
  end;
  if Length(mProviders) = 0 then
  begin
    ASink.Complete;
    Exit;
  end;
  for mEntry in mProviders do
  begin
    // Nicht direkt an den const-Parameter übergeben, sonst zählt niemand die Referenz.
    mPart := TPartSink.Create(mState, mEntry.Name, mTimingId);
    QueryOne(mEntry, AContext, mPart);
  end;
end;

procedure TDpccCompletionProviders.Cancel;
var
  mProviders: TArray<TEntry>;
  mEntry: TEntry;
  mProvider: IDpccCompletionProvider;
begin
  FLock.Enter;
  try
    mProviders := FProviders;
    if FCurrent <> nil then
    begin
      FCurrent.Cancel;
    end;
    FCurrent := nil;
    // Teilsenken, die noch laufen, halten den Zustand selbst am Leben.
    FCurrentRef := nil;
  finally
    FLock.Leave;
  end;
  for mEntry in mProviders do
  begin
    mProvider := mEntry.Provider;
    TDpccGuard.RunProvider(mEntry.Name,
      procedure
      begin
        mProvider.Cancel;
      end);
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Completion.Composite', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
