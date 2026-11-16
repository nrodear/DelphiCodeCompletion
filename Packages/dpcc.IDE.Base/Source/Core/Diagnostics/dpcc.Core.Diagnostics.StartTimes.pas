unit dpcc.Core.Diagnostics.StartTimes;

// Startanteile (zum Einfrier-Wächter #501), ohne Windows und Open
// Tools API: Wie lange hat dpcc selbst den Start der IDE aufgehalten, und
// womit? Ein langsamer Start ist kein Absturz; früher schaltete er beim
// nächsten Start alle Funktionen ab (#722), ohne dass man erfuhr, woran es
// lag. Jetzt misst dpcc seine Anteile und nennt sie, damit sich die Ursache
// beheben lässt.
// - Teile: jedes Feature beim Anmelden (TDpccFeatureTable), die übrige
//   Anmeldung und dpcc-Aktionen (TDpccActivity) bis zur freien
//   Nachrichtenschleife. Gleiche Namen werden addiert.
// - Die Zeit bis zur freien Nachrichtenschleife enthält auch die übrigen
//   Packages, den Desktop und das Projekt; was nicht dpcc ist, ist der Rest.
// - Nur Namen und Millisekunden, keine Pfade (Protokolle anonym, #647).

interface

uses
  System.SysUtils,
  System.SyncObjs;

type
  TDpccStartPart = record
    Name: string;
    Ms: Int64;
  end;

  TDpccStartTimes = class
  public const
    /// <summary>Kürzere Teile fallen aus der Aufzählung (Rauschen).</summary>
    cMinPartMs = 20;
    /// <summary>Höchstens so viele Teile in der Aufzählung.</summary>
    cMaxParts = 5;
  private
    FLock: TCriticalSection;
    FParts: TArray<TDpccStartPart>;
    FClock: TFunc<Int64>;
  public
    /// <summary>Uhr in ms (monoton, TStopwatch).</summary>
    constructor Create; overload;
    /// <summary>AClock liefert ms; für Tests.</summary>
    constructor Create(const AClock: TFunc<Int64>); overload;
    destructor Destroy; override;
    /// <summary>Jetzt in ms nach der Uhr.</summary>
    function Clock: Int64;
    /// <summary>AMs zu AName addieren; aus jedem Thread. Negative Werte zählen als 0.</summary>
    procedure Add(const AName: string; AMs: Int64);
    /// <summary>AProc ausführen und seine Dauer zu AName addieren, auch wenn AProc eine Ausnahme wirft.</summary>
    procedure Measure(const AName: string; const AProc: TProc);
    /// <summary>Summe aller Teile: so lange hat dpcc den Start aufgehalten.</summary>
    function Total: Int64;
    /// <summary>Die AMax längsten Teile ab MinPartMs, absteigend; bei gleicher Dauer in der Reihenfolge des
    /// ersten Eintrags.</summary>
    function Slowest(AMax: Integer): TArray<TDpccStartPart>;
    /// <summary>"Manager 1200 ms, Forms 300 ms" (die MaxParts längsten); '' ohne.</summary>
    function SlowestText: string;
    /// <summary>Länger als ALimitMs (safeMode.startupTimeoutMs, von den Einstellungen begrenzt)? Ohne Limit
    /// (0 oder kleiner) nie.</summary>
    class function IsSlow(ALoadMs: Int64; ALimitMs: Integer): Boolean; static;
    /// <summary>Protokollzeile: Startzeit bis zur freien Nachrichtenschleife, dpcc-Anteil und die längsten Teile;
    /// mit Zeitlimit, wenn der Start zu langsam war.</summary>
    function LogLine(ALoadMs: Int64; ALimitMs: Integer): string;
  end;

implementation

uses
  System.Math,
  System.Diagnostics;

{ TDpccStartTimes }

constructor TDpccStartTimes.Create;
var
  mTicks: TFunc<Int64>;
begin
  // Typisierte Variable: Delphi wählt zwischen Überladungen mit anonymer Methode als Argument nicht (E2250).
  mTicks :=
    function: Int64
    begin
      Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
    end;
  Create(mTicks);
end;

constructor TDpccStartTimes.Create(const AClock: TFunc<Int64>);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FClock := AClock;
end;

destructor TDpccStartTimes.Destroy;
begin
  FLock.Free;
  inherited;
end;

function TDpccStartTimes.Clock: Int64;
begin
  Result := FClock();
end;

procedure TDpccStartTimes.Add(const AName: string; AMs: Int64);
var
  mIndex: Integer;
  mPart: TDpccStartPart;
begin
  FLock.Enter;
  try
    for mIndex := 0 to High(FParts) do
    begin
      if SameText(FParts[mIndex].Name, AName) then
      begin
        FParts[mIndex].Ms := FParts[mIndex].Ms + Max(AMs, Int64(0));
        Exit;
      end;
    end;
    mPart.Name := AName;
    mPart.Ms := Max(AMs, Int64(0));
    FParts := FParts + [mPart];
  finally
    FLock.Leave;
  end;
end;

procedure TDpccStartTimes.Measure(const AName: string; const AProc: TProc);
var
  mStarted: Int64;
begin
  mStarted := Clock;
  try
    AProc();
  finally
    Add(AName, Clock - mStarted);
  end;
end;

function TDpccStartTimes.Total: Int64;
var
  mPart: TDpccStartPart;
begin
  Result := 0;
  FLock.Enter;
  try
    for mPart in FParts do
    begin
      Inc(Result, mPart.Ms);
    end;
  finally
    FLock.Leave;
  end;
end;

function TDpccStartTimes.Slowest(AMax: Integer): TArray<TDpccStartPart>;
var
  mParts: TArray<TDpccStartPart>;
  mPart: TDpccStartPart;
  mTarget: Integer;
begin
  FLock.Enter;
  try
    mParts := Copy(FParts);
  finally
    FLock.Leave;
  end;
  // Einfügen nach Dauer: stabil, wenige Teile.
  Result := nil;
  for mPart in mParts do
  begin
    if mPart.Ms < cMinPartMs then
    begin
      Continue;
    end;
    mTarget := Length(Result);
    while (mTarget > 0) and (Result[mTarget - 1].Ms < mPart.Ms) do
    begin
      Dec(mTarget);
    end;
    Insert(mPart, Result, mTarget);
  end;
  if Length(Result) > Max(AMax, 0) then
  begin
    SetLength(Result, Max(AMax, 0));
  end;
end;

function TDpccStartTimes.SlowestText: string;
var
  mPart: TDpccStartPart;
begin
  Result := '';
  for mPart in Slowest(cMaxParts) do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + Format('%s %d ms', [mPart.Name, mPart.Ms]);
  end;
end;

class function TDpccStartTimes.IsSlow(ALoadMs: Int64; ALimitMs: Integer): Boolean;
begin
  Result := (ALimitMs > 0) and (ALoadMs > ALimitMs);
end;

function TDpccStartTimes.LogLine(ALoadMs: Int64; ALimitMs: Integer): string;
var
  mParts: string;
begin
  Result := Format('Start: %d ms bis zur freien Nachrichtenschleife', [ALoadMs]);
  if IsSlow(ALoadMs, ALimitMs) then
  begin
    Result := Result + Format(' (länger als %d ms)', [ALimitMs]);
  end;
  Result := Result + Format(', davon dpcc %d ms', [Total]);
  mParts := SlowestText;
  if mParts <> '' then
  begin
    Result := Result + ': ' + mParts;
  end;
end;

end.
