unit dpcc.Core.Diagnostics.Hangs;

// Einfrier-Wächter (#501), Teil ohne Windows und Open Tools API:
// - TDpccActivity: dpcc-Arbeit im Hauptthread meldet sich mit Scope an; der
//   Wächter liest den Namen aus seinem Thread (threadsicher, ohne zu warten).
//   Während des Starts zählt TimeInto die Dauer jeder äußersten Aktion zu den
//   Startanteilen. Running ergänzt die laufende Funktion
//   aus TDpccGuard.Run, wenn keine Aktion angemeldet ist (#1988).
// - TDpccHangMonitor: Schwelle, Statistik je Sitzung und Bericht.
// - TDpccStackScan: ordnet Adressen eines rohen Stapelabzugs Modulen zu
//   (Modul+Offset), ohne Symbole; der Bericht zeigt so, ob dpcc beteiligt ist.
//   Angezeigt werden die obersten 24 Rahmen; ob dpcc beteiligt ist, sucht
//   FirstIn über den ganzen Abzug (#1989). Vorher zählte ein Hänger ohne
//   dpcc-Rahmen unter den obersten 24 als „ohne dpcc“, etwa wenn dpcc eine
//   lange Arbeit der IDE aufrief und deren Stapel tiefer war.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  dpcc.Core.Diagnostics.StartTimes;

type
  TDpccActivity = class
  public const
    /// <summary>Name der Aktion des künstlichen Hängers im Protokoll.</summary>
    cHangTestName = 'Watchdog test';
    /// <summary>Dauer des künstlichen Hängers; über der Schwelle des Wächters.</summary>
    cHangTestMs = 1000;
  private class var
    FLock: TCriticalSection;
    FNames: TArray<string>;
    FTimes: TDpccStartTimes;
  private
    /// <summary>ATimed: äußerste Aktion, begonnen bei AStarted (Uhr der Startanteile).</summary>
    class procedure Leave(const AName: string; ATimed: Boolean; AStarted: Int64); static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Meldet AName an, bis das Ergebnis freigegeben wird (Ende der Routine).</summary>
    class function Scope(const AName: string): IInterface; static;
    /// <summary>Ab jetzt die Dauer jeder äußersten Aktion als „Aktion Name“ zu ATimes addieren
    /// (Startanteile); nil beendet das. ATimes gehört dem Aufrufer und darf nach TimeInto(nil) freigegeben werden.
    /// </summary>
    class procedure TimeInto(ATimes: TDpccStartTimes); static;
    /// <summary>Innerste laufende Aktion; '' ohne oder wenn gerade gesperrt.</summary>
    class function Current: string; static;
    /// <summary>Current, sonst die innerste Funktion aus TDpccGuard.Run; für den Einfrier-Wächter.</summary>
    class function Running: string; static;
    /// <summary>Künstlicher Hänger für den Einfrier-Wächter (#501): blockiert den aufrufenden Thread AMs lang
    /// unter cHangTestName. Aus der Befehlspalette und den Einstellungen, beide nur im Diagnosemodus.</summary>
    class procedure HangTest(AMs: Cardinal); overload; static;
    /// <summary>HangTest mit cHangTestMs.</summary>
    class procedure HangTest; overload; static;
  end;

  TDpccModuleRange = record
    Name: string;
    Base: UInt64;
    Size: UInt64;
  end;

  TDpccStackScan = class
  public
    /// <summary>Adressen, die in einem Modul liegen, als "Modul+Offset" (hex); höchstens AMax,
    /// gleiche Einträge direkt hintereinander nur einmal.</summary>
    class function Frames(const AAddresses: TArray<UInt64>; const AModules: TArray<TDpccModuleRange>;
      AMax: Integer): TArray<string>; overload; static;
    /// <summary>Wie oben mit AMax = 24.</summary>
    class function Frames(const AAddresses: TArray<UInt64>;
      const AModules: TArray<TDpccModuleRange>): TArray<string>; overload; static;
    /// <summary>Erste Adresse (von oben) in einem Modul, dessen Name mit APrefix beginnt, als "Modul+Offset";
    /// '' ohne. Durchsucht alle Adressen.</summary>
    class function FirstIn(const AAddresses: TArray<UInt64>; const AModules: TArray<TDpccModuleRange>;
      const APrefix: string): string; static;
  end;

  TDpccHang = record
    DurationMs: Int64;
    At: TDateTime;
    Activity: string;
    Window: string;
    Frames: TArray<string>;
    /// <summary>Oberster Rahmen aus einem dpcc-Modul im ganzen Abzug, auch unterhalb von Frames; '' ohne.
    /// </summary>
    DpccFrame: string;
    /// <summary>Code-Insight-Kompilierungen bisher (#527).</summary>
    CodeInsightCount: Integer;
    CodeInsightMs: Int64;
  end;

  TDpccHangMonitor = class
  public const
    /// <summary>Ab so vielen ms gilt ein Stillstand als Hänger (fest seit S3; vorher robustness.hangThresholdMs).
    /// </summary>
    cDefaultThresholdMs = 500;
  private
    FThresholdMs: Integer;
    FCount: Integer;
    FWithDpcc: Integer;
    FLongestMs: Int64;
  public
    constructor Create(AThresholdMs: Integer); overload;
    /// <summary>Wie oben mit AThresholdMs = cDefaultThresholdMs.</summary>
    constructor Create; overload;
    /// <summary>Wertet einen beendeten Hänger aus: '' unter der Schwelle, sonst der Bericht; zählt mit.</summary>
    function Finish(const AHang: TDpccHang): string;
    /// <summary>Statistik der Sitzung in einer Zeile.</summary>
    function Summary: string;
    /// <summary>dpcc beteiligt: laufende Aktion oder ein Rahmen aus einem dpcc-Modul.</summary>
    class function InvolvesDpcc(const AHang: TDpccHang): Boolean; static;
    property ThresholdMs: Integer read FThresholdMs write FThresholdMs;
    property Count: Integer read FCount;
    property WithDpcc: Integer read FWithDpcc;
  end;

implementation

uses
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.PluginTimings;

type
  TActivityScope = class(TInterfacedObject)
  private
    FName: string;
    FTimed: Boolean;
    FStarted: Int64;
    // Diagnose-Fenster, Reiter „Hauptthread“: Dauer der Aktion als Zeile der langsamen Aufrufe.
    FPluginStarted: Int64;
  public
    constructor Create(const AName: string; ATimed: Boolean; AStarted: Int64);
    destructor Destroy; override;
  end;

constructor TActivityScope.Create(const AName: string; ATimed: Boolean; AStarted: Int64);
begin
  inherited Create;
  FName := AName;
  FTimed := ATimed;
  FStarted := AStarted;
  FPluginStarted := TDpccPluginTimings.StampIfEnabled;
end;

destructor TActivityScope.Destroy;
begin
  TDpccPluginTimings.NoteActivity(FName, FPluginStarted);
  TDpccActivity.Leave(FName, FTimed, FStarted);
  inherited;
end;

{ TDpccActivity }

class constructor TDpccActivity.Create;
begin
  FLock := TCriticalSection.Create;
end;

class destructor TDpccActivity.Destroy;
begin
  FLock.Free;
end;

class function TDpccActivity.Scope(const AName: string): IInterface;
var
  mTimed: Boolean;
  mStarted: Int64;
begin
  mStarted := 0;
  FLock.Enter;
  try
    // Nur die äußerste Aktion zählt: Verschachtelte stecken in ihrer Dauer.
    mTimed := (Length(FNames) = 0) and (FTimes <> nil);
    if mTimed then
    begin
      mStarted := FTimes.Clock;
    end;
    FNames := FNames + [AName];
  finally
    FLock.Leave;
  end;
  Result := TActivityScope.Create(AName, mTimed, mStarted);
end;

class procedure TDpccActivity.Leave(const AName: string; ATimed: Boolean; AStarted: Int64);
begin
  FLock.Enter;
  try
    if Length(FNames) > 0 then
    begin
      SetLength(FNames, Length(FNames) - 1);
    end;
    // Unter der Sperre: Nach TimeInto(nil) schreibt keine Aktion mehr in die freigegebenen Startanteile.
    if ATimed and (FTimes <> nil) then
    begin
      FTimes.Add('Aktion ' + AName, FTimes.Clock - AStarted);
    end;
  finally
    FLock.Leave;
  end;
end;

class procedure TDpccActivity.TimeInto(ATimes: TDpccStartTimes);
begin
  FLock.Enter;
  try
    FTimes := ATimes;
  finally
    FLock.Leave;
  end;
end;

class function TDpccActivity.Current: string;
begin
  Result := '';
  if not FLock.TryEnter then
  begin
    Exit;
  end;
  try
    if Length(FNames) > 0 then
    begin
      Result := FNames[High(FNames)];
    end;
  finally
    FLock.Leave;
  end;
end;

class function TDpccActivity.Running: string;
begin
  Result := Current;
  if Result = '' then
  begin
    Result := TDpccGuard.CurrentFeatureName;
  end;
end;

class procedure TDpccActivity.HangTest(AMs: Cardinal);
var
  mActivity: IInterface;
begin
  mActivity := Scope(cHangTestName);
  Sleep(AMs);
end;

class procedure TDpccActivity.HangTest;
begin
  HangTest(cHangTestMs);
end;

{ TDpccStackScan }

class function TDpccStackScan.Frames(const AAddresses: TArray<UInt64>;
  const AModules: TArray<TDpccModuleRange>): TArray<string>;
begin
  Result := Frames(AAddresses, AModules, 24);
end;

class function TDpccStackScan.Frames(const AAddresses: TArray<UInt64>; const AModules: TArray<TDpccModuleRange>;
  AMax: Integer): TArray<string>;
var
  mAddress: UInt64;
  mModule: TDpccModuleRange;
  mFrame: string;
begin
  Result := nil;
  for mAddress in AAddresses do
  begin
    if Length(Result) >= AMax then
    begin
      Break;
    end;
    for mModule in AModules do
    begin
      if (mAddress >= mModule.Base) and (mAddress < mModule.Base + mModule.Size) then
      begin
        mFrame := Format('%s+%x', [mModule.Name, mAddress - mModule.Base]);
        if (Length(Result) = 0) or (Result[High(Result)] <> mFrame) then
        begin
          Result := Result + [mFrame];
        end;
        Break;
      end;
    end;
  end;
end;

class function TDpccStackScan.FirstIn(const AAddresses: TArray<UInt64>; const AModules: TArray<TDpccModuleRange>;
  const APrefix: string): string;
var
  mCandidates: TArray<TDpccModuleRange>;
  mModule: TDpccModuleRange;
  mAddress: UInt64;
begin
  Result := '';
  // Erst die wenigen passenden Module: Der Abzug hat bis zu 64K Adressen, die IDE Hunderte Module.
  mCandidates := nil;
  for mModule in AModules do
  begin
    if mModule.Name.StartsWith(APrefix, True) then
    begin
      mCandidates := mCandidates + [mModule];
    end;
  end;
  if mCandidates = nil then
  begin
    Exit;
  end;
  for mAddress in AAddresses do
  begin
    for mModule in mCandidates do
    begin
      if (mAddress >= mModule.Base) and (mAddress < mModule.Base + mModule.Size) then
      begin
        Exit(Format('%s+%x', [mModule.Name, mAddress - mModule.Base]));
      end;
    end;
  end;
end;

{ TDpccHangMonitor }

function Shown(const AFrames: TArray<string>; const AFrame: string): Boolean;
var
  mFrame: string;
begin
  Result := False;
  for mFrame in AFrames do
  begin
    if mFrame = AFrame then
    begin
      Exit(True);
    end;
  end;
end;

constructor TDpccHangMonitor.Create;
begin
  Create(cDefaultThresholdMs);
end;

constructor TDpccHangMonitor.Create(AThresholdMs: Integer);
begin
  inherited Create;
  FThresholdMs := AThresholdMs;
end;

class function TDpccHangMonitor.InvolvesDpcc(const AHang: TDpccHang): Boolean;
var
  mFrame: string;
begin
  Result := (AHang.Activity <> '') or (AHang.DpccFrame <> '');
  for mFrame in AHang.Frames do
  begin
    if mFrame.StartsWith('dpcc.', True) then
    begin
      Result := True;
    end;
  end;
end;

function TDpccHangMonitor.Finish(const AHang: TDpccHang): string;
var
  mLines: TStringBuilder;
  mFrame: string;
begin
  Result := '';
  if AHang.DurationMs < FThresholdMs then
  begin
    Exit;
  end;
  Inc(FCount);
  if AHang.DurationMs > FLongestMs then
  begin
    FLongestMs := AHang.DurationMs;
  end;
  if InvolvesDpcc(AHang) then
  begin
    Inc(FWithDpcc);
  end;
  // Diagnose-Fenster, Reiter „Hänger“.
  TDpccPluginTimings.NoteHang(AHang.At, AHang.DurationMs, AHang.Activity, InvolvesDpcc(AHang));
  mLines := TStringBuilder.Create;
  try
    mLines.AppendFormat('Hänger %d ms um %s', [AHang.DurationMs, FormatDateTime('hh":"nn":"ss', AHang.At)]);
    if AHang.Activity <> '' then
    begin
      mLines.AppendFormat('; dpcc: %s, %d ms', [AHang.Activity, AHang.DurationMs]);
    end
    else if InvolvesDpcc(AHang) then
    begin
      mLines.Append('; dpcc im Aufrufstapel');
    end;
    if AHang.Window <> '' then
    begin
      mLines.AppendFormat('; Fenster: %s', [AHang.Window]);
    end;
    if AHang.CodeInsightCount > 0 then
    begin
      mLines.AppendFormat('; Code Insight bisher %d-mal, %d ms', [AHang.CodeInsightCount, AHang.CodeInsightMs]);
    end;
    for mFrame in AHang.Frames do
    begin
      mLines.Append(sLineBreak).Append('    ').Append(mFrame);
    end;
    if (AHang.DpccFrame <> '') and not Shown(AHang.Frames, AHang.DpccFrame) then
    begin
      mLines.Append(sLineBreak).Append('    … ').Append(AHang.DpccFrame);
    end;
    mLines.Append(sLineBreak).Append('    ').Append(Summary);
    Result := mLines.ToString;
  finally
    mLines.Free;
  end;
end;

function TDpccHangMonitor.Summary: string;
begin
  Result := Format('Sitzung: %d Hänger, längster %d ms, %d mit dpcc', [FCount, FLongestMs, FWithDpcc]);
end;

end.