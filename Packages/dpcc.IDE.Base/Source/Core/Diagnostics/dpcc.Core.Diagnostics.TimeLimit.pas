unit dpcc.Core.Diagnostics.TimeLimit;

// Blockierschutz (#493): Aufrufe von Datenquellen, die der Hauptthread der IDE
// auslöst, laufen in einem Arbeiter-Thread; der Hauptthread wartet höchstens
// LimitMs (Standard 200 ms) auf das Ende. Dauert es länger, kehrt Run mit
// TimedOut zurück, der Aufrufer bricht ab und zählt es wie einen Fehler. Der
// Arbeiter läuft dann zu Ende und kehrt erst danach in den Vorrat zurück;
// für den nächsten Aufruf startet bei Bedarf ein weiterer. Exceptions im
// Aufruf kommen als Failed mit Klasse und Meldung zurück, nie in die IDE.
// Die Arbeiter warten über TDpccShutdown und enden beim Entladen (StopAll).

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  TDpccTimedOutcome = (Done, Failed, TimedOut);
{$SCOPEDENUMS OFF}

  TDpccTimeLimit = class
  public const
    cDefaultMs = 200;
    cMinMs = 50;
    cMaxMs = 5000;
    /// <summary>Nachwarten auf hängende Arbeiter beim Beenden.</summary>
    cHangGraceMs = 2000;
  private type
    TWorker = class(TThread)
    private
      FStart: TEvent;
      FDone: TEvent;
      FProc: TProc;
      FError: string;
      // Unter FLock: fertig mit dem aktuellen Aufruf bzw. vom Aufrufer aufgegeben.
      FFinished: Boolean;
      FAbandoned: Boolean;
      /// <summary>Wartet auf den nächsten Auftrag; False bei Ende oder Herunterfahren.</summary>
      function WaitForStart: Boolean;
      /// <summary>Führt FProc aus; Fehlertext oder ''.</summary>
      function RunCurrent: string;
      /// <summary>Meldet den Aufruf fertig; True, wenn der Aufrufer aufgegeben hatte.</summary>
      function Finish(const AError: string): Boolean;
    protected
      procedure Execute; override;
    public
      constructor Create;
      destructor Destroy; override;
    end;
  private class var
    FLock: TCriticalSection;
    FIdle: TList<TWorker>;
    FAll: TList<TWorker>;
    FLimitMs: Integer;
    /// <summary>Auto-Reset; gesetzt, sobald ein Arbeiter frei wird (WaitIdle).</summary>
    FReleased: TEvent;
    class function Take: TWorker; static;
    class procedure Release(AWorker: TWorker); static;
    class procedure SetLimitMs(AValue: Integer); static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>AProc mit Zeitlimit ausführen (ALimitMs &lt; 0: LimitMs). AError: Klasse und Meldung bei
    /// Failed.</summary>
    class function Run(const AProc: TProc; out AError: string; ALimitMs: Integer): TDpccTimedOutcome;
      overload; static;
    /// <summary>Wie oben mit ALimitMs = -1 (LimitMs).</summary>
    class function Run(const AProc: TProc; out AError: string): TDpccTimedOutcome; overload; static;
    /// <summary>Alle Arbeiter beenden (nach TDpccShutdown.Signal); True, wenn alle innerhalb von AMs enden.</summary>
    class function StopAll(AMs: Cardinal): Boolean; overload; static;
    /// <summary>Wie oben mit AMs = 1000.</summary>
    class function StopAll: Boolean; overload; static;
    /// <summary>Arbeiter, die gerade einen Aufruf ausführen (auch aufgegebene).</summary>
    class function BusyCount: Integer; static;
    /// <summary>Bis zu AMs warten, bis kein Arbeiter mehr einen Aufruf ausführt (auch aufgegebene); True, wenn
    /// alle frei sind. Vor dem Freigeben einer Sitzung, die aufgegebene Aufrufe noch nutzen könnten.</summary>
    class function WaitIdle(AMs: Cardinal): Boolean; static;
    /// <summary>Zeitlimit für Aufrufe aus dem Hauptthread, MinMs bis MaxMs.</summary>
    class property LimitMs: Integer read FLimitMs write SetLimitMs;
  end;

implementation

uses
  System.Diagnostics,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TTimeLimitText = (DpccIsShuttingDown);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TTimeLimitText] of string = (
    ('dpcc wird beendet'),
    ('dpcc is shutting down'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TTimeLimitText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

{ TDpccTimeLimit.TWorker }

constructor TDpccTimeLimit.TWorker.Create;
begin
  FStart := TEvent.Create(nil, False, False, '');
  FDone := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TDpccTimeLimit.TWorker.Destroy;
begin
  inherited Destroy;
  FDone.Free;
  FStart.Free;
end;

function TDpccTimeLimit.TWorker.WaitForStart: Boolean;
begin
  Result := False;
  while not Terminated do
  begin
    if TDpccShutdown.WaitFor(FStart, 1000) = wrSignaled then
    begin
      Exit(not Terminated);
    end;
    if TDpccShutdown.Signalled then
    begin
      Exit;
    end;
  end;
end;

function TDpccTimeLimit.TWorker.RunCurrent: string;
var
  mProc: TProc;
begin
  Result := '';
  mProc := FProc;
  try
    if Assigned(mProc) then
    begin
      mProc();
    end;
  except
    on E: Exception do
    begin
      Result := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

function TDpccTimeLimit.TWorker.Finish(const AError: string): Boolean;
begin
  TDpccTimeLimit.FLock.Enter;
  try
    FProc := nil;
    FError := AError;
    FFinished := True;
    Result := FAbandoned;
    FAbandoned := False;
    FDone.SetEvent;
  finally
    TDpccTimeLimit.FLock.Leave;
  end;
end;

procedure TDpccTimeLimit.TWorker.Execute;
var
  mError: string;
begin
  while WaitForStart do
  begin
    mError := RunCurrent;
    // StopAll hat aufgegeben (Entladen): nichts mehr anfassen, was dem Vorrat gehört.
    if Terminated then
    begin
      Exit;
    end;
    // Der Aufrufer hat aufgegeben: Erst jetzt ist der Arbeiter wieder frei.
    if Finish(mError) then
    begin
      TDpccTimeLimit.Release(Self);
    end;
  end;
end;

{ TDpccTimeLimit }

class constructor TDpccTimeLimit.Create;
begin
  FLock := TCriticalSection.Create;
  FIdle := TList<TWorker>.Create;
  FAll := TList<TWorker>.Create;
  FLimitMs := cDefaultMs;
  FReleased := TEvent.Create(nil, False, False, '');
end;

class destructor TDpccTimeLimit.Destroy;
begin
  StopAll;
  FreeAndNil(FReleased);
  FreeAndNil(FAll);
  FreeAndNil(FIdle);
  FreeAndNil(FLock);
end;

class procedure TDpccTimeLimit.SetLimitMs(AValue: Integer);
begin
  if AValue < cMinMs then
  begin
    AValue := cMinMs;
  end;
  if AValue > cMaxMs then
  begin
    AValue := cMaxMs;
  end;
  FLimitMs := AValue;
end;

class function TDpccTimeLimit.Take: TWorker;
begin
  FLock.Enter;
  try
    Result := nil;
    while (Result = nil) and (FIdle.Count > 0) do
    begin
      Result := FIdle.Last;
      FIdle.Delete(FIdle.Count - 1);
      // Nach einem Abbruchsignal beendet: verwerfen.
      if Result.Finished then
      begin
        FAll.Remove(Result);
        Result.Free;
        Result := nil;
      end;
    end;
    if Result = nil then
    begin
      Result := TWorker.Create;
      FAll.Add(Result);
    end;
    Result.FFinished := False;
    Result.FAbandoned := False;
    Result.FError := '';
    Result.FDone.ResetEvent;
  finally
    FLock.Leave;
  end;
end;

class procedure TDpccTimeLimit.Release(AWorker: TWorker);
begin
  FLock.Enter;
  try
    if FAll.Contains(AWorker) and not FIdle.Contains(AWorker) then
    begin
      FIdle.Add(AWorker);
      FReleased.SetEvent;
    end;
  finally
    FLock.Leave;
  end;
end;

class function TDpccTimeLimit.Run(const AProc: TProc; out AError: string): TDpccTimedOutcome;
begin
  Result := Run(AProc, AError, -1);
end;

class function TDpccTimeLimit.Run(const AProc: TProc; out AError: string; ALimitMs: Integer): TDpccTimedOutcome;
var
  mWorker: TWorker;
  mLimit: Cardinal;
  mFinished: Boolean;
begin
  AError := '';
  if TDpccShutdown.Signalled then
  begin
    AError := UiText(TTimeLimitText.DpccIsShuttingDown);
    Exit(TDpccTimedOutcome.Failed);
  end;
  if ALimitMs < 0 then
  begin
    mLimit := FLimitMs;
  end
  else
  begin
    mLimit := ALimitMs;
  end;
  mWorker := Take;
  mWorker.FProc := AProc;
  mWorker.FStart.SetEvent;
  mWorker.FDone.WaitFor(mLimit);
  FLock.Enter;
  try
    mFinished := mWorker.FFinished;
    if mFinished then
    begin
      AError := mWorker.FError;
    end
    else
    begin
      mWorker.FAbandoned := True;
    end;
  finally
    FLock.Leave;
  end;
  if not mFinished then
  begin
    Exit(TDpccTimedOutcome.TimedOut);
  end;
  Release(mWorker);
  if AError <> '' then
  begin
    Result := TDpccTimedOutcome.Failed;
  end
  else
  begin
    Result := TDpccTimedOutcome.Done;
  end;
end;

class function TDpccTimeLimit.BusyCount: Integer;
begin
  FLock.Enter;
  try
    Result := FAll.Count - FIdle.Count;
  finally
    FLock.Leave;
  end;
end;

class function TDpccTimeLimit.WaitIdle(AMs: Cardinal): Boolean;
var
  mWatch: TStopwatch;
  mLeft: Int64;
begin
  if (FLock = nil) or (FReleased = nil) then
  begin
    Exit(True);
  end;
  mWatch := TStopwatch.StartNew;
  Result := BusyCount = 0;
  while not Result do
  begin
    mLeft := Int64(AMs) - mWatch.ElapsedMilliseconds;
    if mLeft <= 0 then
    begin
      Exit;
    end;
    // Auto-Reset: Ein Release zwischen Prüfung und Warten bleibt gesetzt und weckt sofort.
    FReleased.WaitFor(Cardinal(mLeft));
    Result := BusyCount = 0;
  end;
end;

class function TDpccTimeLimit.StopAll: Boolean;
begin
  Result := StopAll(1000);
end;

class function TDpccTimeLimit.StopAll(AMs: Cardinal): Boolean;
var
  mWorkers: TArray<TWorker>;
  mWorker: TWorker;
  mThreads: TArray<TThread>;
  mHung: Integer;
begin
  if FLock = nil then
  begin
    Exit(True);
  end;
  FLock.Enter;
  try
    mWorkers := FAll.ToArray;
    FAll.Clear;
    FIdle.Clear;
  finally
    FLock.Leave;
  end;
  mThreads := nil;
  for mWorker in mWorkers do
  begin
    mWorker.Terminate;
    mWorker.FStart.SetEvent;
    mThreads := mThreads + [TThread(mWorker)];
  end;
  Result := TDpccShutdown.WaitForThreads(mThreads, AMs);
  if not Result then
  begin
    mHung := 0;
    for mWorker in mWorkers do
    begin
      if not mWorker.Finished then
      begin
        Inc(mHung);
      end;
    end;
    // Ein Aufruf steckt in nicht abbrechbarem Code. Kehrt er erst nach dem Entladen zurück, läuft er in
    // nicht mehr geladenem Code: protokollieren und noch etwas warten.
    TDpccGuard.Log(Format('Zeitlimit: %d Arbeiter beim Beenden noch beschäftigt, warte bis %d ms nach',
      [mHung, cHangGraceMs]));
    Result := TDpccShutdown.WaitForThreads(mThreads, cHangGraceMs);
  end;
  for mWorker in mWorkers do
  begin
    if mWorker.Finished then
    begin
      mWorker.Free;
    end
    else
    begin
      TDpccGuard.Log('Zeitlimit: Arbeiter hängt weiter; er gibt sich bei Rückkehr selbst frei');
      // Letzter Ausweg: Ohne FreeOnTerminate bliebe das Objekt liegen, und der Thread kehrte trotzdem in diesen
      // Code zurück. Liest der Thread FreeOnTerminate vor dem Setzen, bleibt im ungünstigsten Fall ein Leck,
      // nie eine Doppelfreigabe.
      mWorker.FreeOnTerminate := True;
    end;
  end;
  // WaitIdle nicht länger warten lassen: Die Arbeiter gehören nicht mehr zum Vorrat.
  if FReleased <> nil then
  begin
    FReleased.SetEvent;
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Diagnostics.TimeLimit', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
