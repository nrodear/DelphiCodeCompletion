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
// Quelle ab.
// Ohne Warten (perf1): Query startet alle Quellen gleichzeitig auf Arbeitern
// (TDpccTimeLimit.Post) und kehrt sofort zurück. Das Zeitlimit überwacht der
// Arbeiter (Run darin); was die Quellen liefern, kommt wie bisher über die
// Teilsenken. Vorher wartete der Hauptthread nacheinander bis zu 200 ms je
// Quelle (Strg+Leertaste, „.“, jedes Requery).
// Spur je Quelle: Es läuft höchstens ein Aufruf einer Quelle zugleich, in der
// Reihenfolge der Abfragen. Kommt eine neue Abfrage, solange der vorige Aufruf
// noch innerhalb des Zeitlimits läuft, wartet sie (nur die neueste) und startet
// gleich danach; eine ältere wartende entfällt. Läuft der vorige Aufruf schon
// länger als das Zeitlimit (aufgegeben), wird die Quelle diesmal übersprungen,
// damit eine hängende Quelle nicht bei jedem Tastendruck einen weiteren
// Arbeiter belegt. Abbrechen einer aufgegebenen Quelle geschieht unter der
// Sperre ihrer Spur, damit es nie einen danach gestarteten Aufruf trifft.
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
    /// <summary>Ein Aufruf einer Quelle: Abfrage, Teilsenke und Zeitlimit (ms, aufgelöst).</summary>
    TJob = record
      Context: TDpccContext;
      Part: IDpccCompletionSink;
      LimitMs: Integer;
    end;
    /// <summary>Spur einer Quelle (perf1): höchstens ein laufender und ein wartender Aufruf. Alle Felder unter
    /// Lock. Lebt, solange die Quellen oder ein Arbeiter sie halten.</summary>
    TRunning = class(TInterfacedObject)
    public
      Lock: TCriticalSection;
      /// <summary>Ein Aufruf läuft (auch ein aufgegebener).</summary>
      Busy: Boolean;
      /// <summary>Beginn des laufenden Aufrufs (GetTickCount64).</summary>
      Started: Int64;
      /// <summary>Nummer des laufenden Aufrufs; Done: seine Arbeit ist zu Ende; Abandoned: nach dem Zeitlimit
      /// aufgegeben.</summary>
      Serial: Integer;
      Done: Boolean;
      Abandoned: Boolean;
      /// <summary>Neueste Abfrage, die auf das Ende des laufenden Aufrufs wartet.</summary>
      HasPending: Boolean;
      Pending: TJob;
      constructor Create;
      destructor Destroy; override;
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
    /// <summary>Im Hauptthread: AEntry starten, merken oder überspringen; wartet nie.</summary>
    procedure QueryOne(const AEntry: TEntry; const AContext: TDpccContext; const APart: IDpccCompletionSink);
    /// <summary>AJob (Nummer ASerial, Spur schon belegt) auf einem Arbeiter starten; dieser überwacht das
    /// Zeitlimit. Aus jedem Thread.</summary>
    class procedure Launch(const AEntry: TEntry; const AJob: TJob; ASerial: Integer); static;
    /// <summary>Arbeit eines Arbeiters für AEntry: fragt die Quelle, misst sie und gibt die Spur frei.</summary>
    class function Work(const AEntry: TEntry; const AJob: TJob; ASerial: Integer): TProc; static;
    /// <summary>Arbeit des Aufrufs ASerial ist zu Ende (auch ohne Start): wartende Abfrage starten oder Spur frei.
    /// Mehrfach aufgerufen wirkt es einmal.</summary>
    class procedure Finished(const AEntry: TEntry; ASerial: Integer); static;
    /// <summary>Quelle antwortet nicht in der Zeit: Teil abschließen, Abbruch anfordern, melden; eine wartende
    /// Abfrage entfällt. Ohne Wirkung, wenn der Aufruf inzwischen fertig ist.</summary>
    class procedure Abandon(const AEntry: TEntry; const AJob: TJob; ASerial: Integer); static;
    /// <summary>Wartende Abfrage von AEntry verwerfen (ihr Teil gilt als fertig); ohne wartende nichts.</summary>
    class procedure DropPending(const AEntry: TEntry); static;
  public
    /// <summary>Name einer Quelle ohne IDpccNamedProvider, in der Sprache der Oberfläche.</summary>
    class function DefaultName: string; static;
    constructor Create;
    destructor Destroy; override;
    /// <summary>Quelle anmelden; ihr Name (IDpccNamedProvider) gilt für die Sicherung je Quelle.</summary>
    procedure Add(const AProvider: IDpccCompletionProvider);
    /// <summary>Zeitlimit je Quelle, überwacht im Arbeiter (der Aufrufer wartet nicht); -1 (Standard) =
    /// TDpccTimeLimit.LimitMs.</summary>
    property TimeLimitMs: Integer read FTimeLimitMs write FTimeLimitMs;
    { IDpccCompletionProvider }
    procedure Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
    procedure Cancel;
  end;

implementation

uses
  System.Classes,
  dpcc.Core.Diagnostics.PluginTimings,
  dpcc.Core.Diagnostics.Shutdown,
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

{ TDpccCompletionProviders.TRunning }

constructor TDpccCompletionProviders.TRunning.Create;
begin
  inherited Create;
  Lock := TCriticalSection.Create;
end;

destructor TDpccCompletionProviders.TRunning.Destroy;
begin
  Lock.Free;
  inherited;
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

class function TDpccCompletionProviders.Work(const AEntry: TEntry; const AJob: TJob; ASerial: Integer): TProc;
var
  mEntry: TEntry;
  mProvider: IDpccCompletionProvider;
  mPart: IDpccCompletionSink;
  mContext: TDpccContext;
  mSerial: Integer;
  mName: string;
begin
  mEntry := AEntry;
  mProvider := AEntry.Provider;
  mPart := AJob.Part;
  mContext := AJob.Context;
  mSerial := ASerial;
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
        // Über mEntry.RunningRef lebt die Spur, auch wenn die Quellen inzwischen freigegeben sind.
        TDpccCompletionProviders.Finished(mEntry, mSerial);
      end;
    end;
end;

class procedure TDpccCompletionProviders.Launch(const AEntry: TEntry; const AJob: TJob; ASerial: Integer);
var
  mEntry: TEntry;
  mJob: TJob;
  mSerial: Integer;
  mWork: TProc;
begin
  mEntry := AEntry;
  mJob := AJob;
  mSerial := ASerial;
  mWork := Work(AEntry, AJob, ASerial);
  // Der Arbeiter wartet (höchstens das Zeitlimit) auf einen zweiten, der die Quelle fragt; der Aufrufer nie.
  if TDpccTimeLimit.Post(
    procedure
    var
      mError: string;
    begin
      try
        case TDpccTimeLimit.Run(mWork, mError, mJob.LimitMs) of
          TDpccTimedOutcome.Done:
            ;
          TDpccTimedOutcome.Failed:
            begin
              // Auch ohne gestarteten Aufruf (dpcc wird beendet) wieder frei.
              TDpccCompletionProviders.Finished(mEntry, mSerial);
              mJob.Part.Complete;
              TDpccGuard.ReportProvider(mEntry.Name, mError);
            end;
        else
          TDpccCompletionProviders.Abandon(mEntry, mJob, mSerial);
        end;
      except
        // Arbeiter: nie eine Ausnahme nach außen; der Teil gilt als fertig.
        on E: Exception do
        begin
          mJob.Part.Complete;
          TDpccGuard.ReportProvider(mEntry.Name, E);
        end;
      end;
    end) then
  begin
    Exit;
  end;
  // dpcc wird beendet: nichts gestartet; Spur frei, Teil fertig.
  Finished(AEntry, ASerial);
  AJob.Part.Complete;
end;

class procedure TDpccCompletionProviders.Finished(const AEntry: TEntry; ASerial: Integer);
var
  mRunning: TRunning;
  mNext: TJob;
  mDropped: IDpccCompletionSink;
  mLaunch: Boolean;
  mSerial: Integer;
begin
  mRunning := AEntry.Running;
  mNext := Default(TJob);
  mDropped := nil;
  mLaunch := False;
  mSerial := 0;
  mRunning.Lock.Enter;
  try
    if (mRunning.Serial <> ASerial) or mRunning.Done then
    begin
      Exit;
    end;
    mRunning.Done := True;
    if mRunning.HasPending then
    begin
      mNext := mRunning.Pending;
      mRunning.HasPending := False;
      mRunning.Pending := Default(TJob);
      if mRunning.Abandoned or TDpccShutdown.Signalled then
      begin
        mDropped := mNext.Part;
      end
      else
      begin
        // Die neueste Abfrage gleich anschließen; die Spur bleibt belegt.
        Inc(mRunning.Serial);
        mSerial := mRunning.Serial;
        mRunning.Done := False;
        mRunning.Abandoned := False;
        mRunning.Started := Int64(TThread.GetTickCount64);
        mLaunch := True;
      end;
    end;
    if not mLaunch then
    begin
      mRunning.Busy := False;
    end;
  finally
    mRunning.Lock.Leave;
  end;
  if mDropped <> nil then
  begin
    mDropped.Complete;
  end;
  if mLaunch then
  begin
    Launch(AEntry, mNext, mSerial);
  end;
end;

class procedure TDpccCompletionProviders.Abandon(const AEntry: TEntry; const AJob: TJob; ASerial: Integer);
var
  mRunning: TRunning;
  mDropped: IDpccCompletionSink;
  mElapsed: Int64;
  mCancelError: string;
begin
  mRunning := AEntry.Running;
  mDropped := nil;
  mCancelError := '';
  mRunning.Lock.Enter;
  try
    // Gerade noch fertig geworden (oder schon die nächste Abfrage gestartet): nichts aufzugeben.
    if (mRunning.Serial <> ASerial) or mRunning.Done then
    begin
      Exit;
    end;
    mRunning.Abandoned := True;
    mElapsed := Int64(TThread.GetTickCount64) - mRunning.Started;
    if mRunning.HasPending then
    begin
      mDropped := mRunning.Pending.Part;
      mRunning.HasPending := False;
      mRunning.Pending := Default(TJob);
    end;
    // Unter der Sperre: Solange dieser Aufruf die Spur belegt, startet kein neuer, den der Abbruch träfe.
    try
      AEntry.Provider.Cancel;
    except
      on E: Exception do
      begin
        mCancelError := E.ClassName + ': ' + E.Message;
      end;
    end;
  finally
    mRunning.Lock.Leave;
  end;
  // Langsam: nicht länger warten; was später noch kommt, verwirft die Teilsenke. Kein Fehler.
  AJob.Part.Complete;
  if mCancelError <> '' then
  begin
    TDpccGuard.ReportProvider(AEntry.Name, mCancelError);
  end;
  TDpccGuard.ReportProviderSlow(AEntry.Name, Format('keine Antwort innerhalb von %d ms', [AJob.LimitMs]));
  // Die wartende Abfrage hinge sonst am aufgegebenen Aufruf.
  if mDropped <> nil then
  begin
    mDropped.Complete;
    TDpccGuard.ReportProviderSlow(AEntry.Name, Format('vorige Anfrage läuft seit %d ms, übersprungen', [mElapsed]));
  end;
end;

class procedure TDpccCompletionProviders.DropPending(const AEntry: TEntry);
var
  mDropped: IDpccCompletionSink;
begin
  mDropped := nil;
  AEntry.Running.Lock.Enter;
  try
    if AEntry.Running.HasPending then
    begin
      mDropped := AEntry.Running.Pending.Part;
      AEntry.Running.HasPending := False;
      AEntry.Running.Pending := Default(TJob);
    end;
  finally
    AEntry.Running.Lock.Leave;
  end;
  if mDropped <> nil then
  begin
    mDropped.Complete;
  end;
end;

procedure TDpccCompletionProviders.QueryOne(const AEntry: TEntry; const AContext: TDpccContext;
  const APart: IDpccCompletionSink);
var
  mRunning: TRunning;
  mJob: TJob;
  mDropped: IDpccCompletionSink;
  mNow, mElapsed: Int64;
  mSerial: Integer;
  mLaunch, mSkip: Boolean;
begin
  if TDpccGuard.ProviderDisabled(AEntry.Name) then
  begin
    APart.Complete;
    Exit;
  end;
  mJob := Default(TJob);
  mJob.Context := AContext;
  mJob.Part := APart;
  mJob.LimitMs := TimeLimitOf(FTimeLimitMs);
  mRunning := AEntry.Running;
  mDropped := nil;
  mLaunch := False;
  mSkip := False;
  mSerial := 0;
  mElapsed := 0;
  mNow := Int64(TThread.GetTickCount64);
  mRunning.Lock.Enter;
  try
    if not mRunning.Busy then
    begin
      mRunning.Busy := True;
      Inc(mRunning.Serial);
      mSerial := mRunning.Serial;
      mRunning.Done := False;
      mRunning.Abandoned := False;
      mRunning.Started := mNow;
      mLaunch := True;
    end
    else
    begin
      // Eine ältere wartende Abfrage ist überholt (ihre Senke ist schon abgebrochen).
      if mRunning.HasPending then
      begin
        mDropped := mRunning.Pending.Part;
        mRunning.HasPending := False;
        mRunning.Pending := Default(TJob);
      end;
      mElapsed := mNow - mRunning.Started;
      if mRunning.Abandoned or (mElapsed > mJob.LimitMs) then
      begin
        // Der vorige Aufruf hängt: keinen weiteren Arbeiter belegen, diesmal ohne diese Quelle.
        mSkip := True;
      end
      else
      begin
        // Der vorige Aufruf läuft noch kurz: diese Abfrage gleich danach starten (Finished).
        mRunning.Pending := mJob;
        mRunning.HasPending := True;
      end;
    end;
  finally
    mRunning.Lock.Leave;
  end;
  if mDropped <> nil then
  begin
    mDropped.Complete;
  end;
  if mLaunch then
  begin
    Launch(AEntry, mJob, mSerial);
  end
  else if mSkip then
  begin
    APart.Complete;
    TDpccGuard.ReportProviderSlow(AEntry.Name, Format('vorige Anfrage läuft seit %d ms, übersprungen', [mElapsed]));
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
    // Eine wartende Abfrage gehört zum abgebrochenen Query: nicht mehr starten.
    DropPending(mEntry);
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
