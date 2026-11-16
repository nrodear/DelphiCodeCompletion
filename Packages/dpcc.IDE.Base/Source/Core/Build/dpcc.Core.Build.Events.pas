unit dpcc.Core.Build.Events;

// Compile-Ereignisse der IDE (#527), ohne Open Tools API: Die IDE-Schicht
// meldet Beginn und Ende von Gruppenlauf und Projekten, der Dienst misst die
// Dauer, verteilt die Ereignisse an die Teilnehmer und sendet sie als
// dpcc/compileStarted bzw. dpcc/compileFinished an den Server.
//
// - Vor dem Compile fragt BeforeCompile alle Teilnehmer, ob abgebrochen
//   werden soll; der erste Grund gewinnt. Die Teilnehmer sehen dabei schon
//   Background und RequestedBy des beginnenden Laufs (Release-Wächter #533);
//   nach einem Abbruch erfahren alle über CompileCancelled davon (Läufer #261,
//   Schnellaktion „Öffnen und bauen“ #764).
// - Hintergrund-Kompilierungen der Code Insight zählen nur mit (Anzahl,
//   Dauer); sie lösen keine Teilnehmer und keine Abbrüche aus.
// - Ein Projekt, das schon läuft, beginnt nicht noch einmal (zwei Notifier
//   der IDE melden denselben Lauf).
// - Ausnahmen eines Teilnehmers gehen ins Protokoll; der Build und die
//   übrigen Teilnehmer laufen weiter.
// - Remove meldet einen Teilnehmer ab und gibt ihn frei (Module, #1455:
//   nach dem Abmelden erreicht ihn kein Ereignis mehr). Während einer
//   Verteilung bekommt er keine weiteren Aufrufe und wird danach frei.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  TDpccCompileKind = (Make, Build, Check, MakeUnit, Clean, Link);

  TDpccCompileProject = record
    FileName: string;
    Kind: TDpccCompileKind;
    Configuration: string;
    Platform: string;
    OutputFile: string;
    /// <summary>Eigene Hintergrundprüfung von dpcc (#548), kein Build des Benutzers.</summary>
    Background: Boolean;
    /// <summary>Wer den Build angestoßen hat: '' = Benutzer, "mcp" = ein KI-Assistent über build_project (#261).
    /// </summary>
    RequestedBy: string;
    /// <summary>Dauer des Compiles in ms (#758); setzt nur der Leser des Meldungsfensters nach dem Ende, sonst 0.
    /// </summary>
    DurationMs: Int64;
    /// <summary>Dauer des ganzen Laufs (Gruppe) in ms (#758); 0 = unbekannt.</summary>
    GroupDurationMs: Int64;
  end;

  /// <summary>Teilnehmer an den Compile-Ereignissen; alle Methoden sind optional.</summary>
  TDpccCompileParticipant = class
  public
    procedure GroupStarted(AKind: TDpccCompileKind); virtual;
    procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); virtual;
    /// <summary>True bricht den Compile ab; AReason erscheint im Meldungsfenster.</summary>
    function CancelCompile(const AProject: TDpccCompileProject; out AReason: string): Boolean; virtual;
    /// <summary>Ein Teilnehmer hat den Compile von AProject abgebrochen; AReason wie im Meldungsfenster.</summary>
    procedure CompileCancelled(const AProject: TDpccCompileProject; const AReason: string); virtual;
    procedure ProjectStarted(const AProject: TDpccCompileProject); virtual;
    procedure ProjectFinished(const AProject: TDpccCompileProject; ASucceeded: Boolean; ADurationMs: Int64); virtual;
  end;

  TDpccClockFunc = reference to function: Int64;
  TDpccNotifyProc = reference to procedure(const AMethod: string; AParams: TJSONObject);
  TDpccTextProc = reference to procedure(const AText: string);

  TDpccCompileEvents = class
  private type
    TRunning = record
      Project: TDpccCompileProject;
      Started: Int64;
    end;
  private
    FParticipants: TObjectList<TDpccCompileParticipant>;
    /// <summary>Während einer Verteilung abgemeldet; frei nach deren Ende.</summary>
    FRetired: TObjectList<TDpccCompileParticipant>;
    FDispatching: Integer;
    FRunning: TList<TRunning>;
    FClock: TDpccClockFunc;
    FOnNotify: TDpccNotifyProc;
    FOnLog: TDpccTextProc;
    FGroupStarted: Int64;
    FInGroup: Boolean;
    FCodeInsightStarted: Int64;
    FCodeInsightCount: Integer;
    FCodeInsightMs: Int64;
    FBackground: Boolean;
    FRequestedBy: string;
    function Now_: Int64;
    function RunningIndex(const AFileName: string): Integer;
    procedure Notify(const AMethod: string; AParams: TJSONObject);
    procedure Guard(const AWhat: string; const AAction: TProc);
    /// <summary>Teilnehmer zu Beginn einer Verteilung; mit LeaveDispatch paaren.</summary>
    function EnterDispatch: TArray<TDpccCompileParticipant>;
    procedure LeaveDispatch;
    function IsLive(AParticipant: TDpccCompileParticipant): Boolean;
  public
    constructor Create(const AClock: TDpccClockFunc); overload;
    /// <summary>Wie oben mit AClock = nil.</summary>
    constructor Create; overload;
    destructor Destroy; override;
    /// <summary>Der Dienst übernimmt AParticipant.</summary>
    procedure Add(AParticipant: TDpccCompileParticipant);
    /// <summary>AParticipant abmelden und freigeben; unbekannte Teilnehmer: nichts.</summary>
    procedure Remove(AParticipant: TDpccCompileParticipant);
    procedure GroupStarted(AKind: TDpccCompileKind);
    procedure GroupFinished(ASucceeded: Boolean);
    /// <summary>Vor einem Compile: True = abbrechen, AReason nennt den Grund. Code Insight bricht nie ab.</summary>
    function BeforeCompile(const AProject: TDpccCompileProject; AIsCodeInsight: Boolean; out AReason: string): Boolean;
    /// <summary>Ende einer Code-Insight-Kompilierung (nur gezählt).</summary>
    procedure CodeInsightFinished;
    procedure ProjectStarted(const AProject: TDpccCompileProject);
    procedure ProjectFinished(const AFileName: string; ASucceeded: Boolean);
    class function KindText(AKind: TDpccCompileKind): string; static;
    property CodeInsightCount: Integer read FCodeInsightCount;
    property CodeInsightMs: Int64 read FCodeInsightMs;
    /// <summary>Solange True, sind beginnende Läufe dpcc-eigene Hintergrundprüfungen (#548).</summary>
    property Background: Boolean read FBackground write FBackground;
    /// <summary>Solange gesetzt, tragen beginnende Läufe diesen Auftraggeber (#261), z. B. "mcp".</summary>
    property RequestedBy: string read FRequestedBy write FRequestedBy;
    property OnNotify: TDpccNotifyProc read FOnNotify write FOnNotify;
    property OnLog: TDpccTextProc read FOnLog write FOnLog;
  end;

  /// <summary>Schreibt jedes Ereignis als Zeile, z. B. ins Diagnoseprotokoll.</summary>
  TDpccCompileLog = class(TDpccCompileParticipant)
  private
    FEvents: TDpccCompileEvents;
    FWrite: TDpccTextProc;
  public
    /// <summary>AEvents liefert die Zahlen der Code-Insight-Kompilierungen.</summary>
    constructor Create(AEvents: TDpccCompileEvents; const AWrite: TDpccTextProc);
    procedure GroupStarted(AKind: TDpccCompileKind); override;
    procedure GroupFinished(ASucceeded: Boolean; ADurationMs: Int64); override;
    procedure ProjectStarted(const AProject: TDpccCompileProject); override;
    procedure ProjectFinished(const AProject: TDpccCompileProject; ASucceeded: Boolean; ADurationMs: Int64); override;
  end;

implementation

uses
  System.Diagnostics;

{ TDpccCompileLog }

constructor TDpccCompileLog.Create(AEvents: TDpccCompileEvents; const AWrite: TDpccTextProc);
begin
  inherited Create;
  FEvents := AEvents;
  FWrite := AWrite;
end;

procedure TDpccCompileLog.GroupStarted(AKind: TDpccCompileKind);
begin
  FWrite(Format('Compile: Gruppe %s beginnt', [TDpccCompileEvents.KindText(AKind)]));
end;

procedure TDpccCompileLog.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
const
  cResults: array[Boolean] of string = ('fehlgeschlagen', 'erfolgreich');
begin
  FWrite(Format('Compile: Gruppe %s nach %d ms; Code Insight bisher %d-mal, %d ms',
    [cResults[ASucceeded], ADurationMs, FEvents.CodeInsightCount, FEvents.CodeInsightMs]));
end;

procedure TDpccCompileLog.ProjectStarted(const AProject: TDpccCompileProject);
begin
  FWrite(Format('Compile: %s %s (%s, %s) beginnt', [TDpccCompileEvents.KindText(AProject.Kind),
    ExtractFileName(AProject.FileName), AProject.Configuration, AProject.Platform]));
end;

procedure TDpccCompileLog.ProjectFinished(const AProject: TDpccCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
const
  cResults: array[Boolean] of string = ('fehlgeschlagen', 'erfolgreich');
begin
  FWrite(Format('Compile: %s %s nach %d ms', [ExtractFileName(AProject.FileName), cResults[ASucceeded], ADurationMs]));
end;

{ TDpccCompileParticipant }

procedure TDpccCompileParticipant.GroupStarted(AKind: TDpccCompileKind);
begin
end;

procedure TDpccCompileParticipant.GroupFinished(ASucceeded: Boolean; ADurationMs: Int64);
begin
end;

function TDpccCompileParticipant.CancelCompile(const AProject: TDpccCompileProject; out AReason: string): Boolean;
begin
  AReason := '';
  Result := False;
end;

procedure TDpccCompileParticipant.CompileCancelled(const AProject: TDpccCompileProject; const AReason: string);
begin
end;

procedure TDpccCompileParticipant.ProjectStarted(const AProject: TDpccCompileProject);
begin
end;

procedure TDpccCompileParticipant.ProjectFinished(const AProject: TDpccCompileProject; ASucceeded: Boolean;
  ADurationMs: Int64);
begin
end;

{ TDpccCompileEvents }

constructor TDpccCompileEvents.Create;
begin
  Create(nil);
end;

constructor TDpccCompileEvents.Create(const AClock: TDpccClockFunc);
begin
  inherited Create;
  FParticipants := TObjectList<TDpccCompileParticipant>.Create(True);
  FRetired := TObjectList<TDpccCompileParticipant>.Create(True);
  FRunning := TList<TRunning>.Create;
  FClock := AClock;
end;

destructor TDpccCompileEvents.Destroy;
begin
  FRunning.Free;
  FParticipants.Free;
  FRetired.Free;
  inherited;
end;

function TDpccCompileEvents.Now_: Int64;
begin
  if Assigned(FClock) then
  begin
    Result := FClock();
  end
  else
  begin
    Result := TStopwatch.GetTimeStamp div (TStopwatch.Frequency div 1000);
  end;
end;

procedure TDpccCompileEvents.Add(AParticipant: TDpccCompileParticipant);
begin
  FParticipants.Add(AParticipant);
end;

procedure TDpccCompileEvents.Remove(AParticipant: TDpccCompileParticipant);
begin
  if (AParticipant = nil) or not FParticipants.Contains(AParticipant) then
  begin
    Exit;
  end;
  FParticipants.Extract(AParticipant);
  if FDispatching > 0 then
  begin
    FRetired.Add(AParticipant);
  end
  else
  begin
    AParticipant.Free;
  end;
end;

function TDpccCompileEvents.EnterDispatch: TArray<TDpccCompileParticipant>;
begin
  Inc(FDispatching);
  Result := FParticipants.ToArray;
end;

procedure TDpccCompileEvents.LeaveDispatch;
begin
  Dec(FDispatching);
  if FDispatching = 0 then
  begin
    FRetired.Clear;
  end;
end;

function TDpccCompileEvents.IsLive(AParticipant: TDpccCompileParticipant): Boolean;
begin
  Result := FParticipants.Contains(AParticipant);
end;

class function TDpccCompileEvents.KindText(AKind: TDpccCompileKind): string;
const
  cTexts: array[TDpccCompileKind] of string = ('make', 'build', 'check', 'makeUnit', 'clean', 'link');
begin
  Result := cTexts[AKind];
end;

procedure TDpccCompileEvents.Notify(const AMethod: string; AParams: TJSONObject);
begin
  if Assigned(FOnNotify) then
  begin
    FOnNotify(AMethod, AParams);
  end
  else
  begin
    AParams.Free;
  end;
end;

procedure TDpccCompileEvents.Guard(const AWhat: string; const AAction: TProc);
begin
  try
    AAction();
  except
    on E: Exception do
      if Assigned(FOnLog) then
      begin
        FOnLog(Format('Compile-Ereignis %s: %s: %s', [AWhat, E.ClassName, E.Message]));
      end;
  end;
end;

function TDpccCompileEvents.RunningIndex(const AFileName: string): Integer;
begin
  for Result := 0 to FRunning.Count - 1 do
  begin
    if SameText(FRunning[Result].Project.FileName, AFileName) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

procedure TDpccCompileEvents.GroupStarted(AKind: TDpccCompileKind);
var
  mParticipants: TArray<TDpccCompileParticipant>;
  mParticipant: TDpccCompileParticipant;
begin
  // Ein neuer Gruppenlauf ersetzt einen nicht beendeten (z. B. Hintergrund-Compile ohne Ende).
  FInGroup := True;
  FGroupStarted := Now_;
  mParticipants := EnterDispatch;
  try
    for mParticipant in mParticipants do
    begin
      if IsLive(mParticipant) then
      begin
        Guard(mParticipant.ClassName, procedure begin mParticipant.GroupStarted(AKind); end);
      end;
    end;
  finally
    LeaveDispatch;
  end;
  Notify('dpcc/compileStarted', TJSONObject.Create.AddPair('group', TJSONBool.Create(True))
    .AddPair('kind', KindText(AKind)));
end;

procedure TDpccCompileEvents.GroupFinished(ASucceeded: Boolean);
var
  mParticipants: TArray<TDpccCompileParticipant>;
  mParticipant: TDpccCompileParticipant;
  mDuration: Int64;
begin
  if not FInGroup then
  begin
    Exit;
  end;
  FInGroup := False;
  mDuration := Now_ - FGroupStarted;
  mParticipants := EnterDispatch;
  try
    for mParticipant in mParticipants do
    begin
      if IsLive(mParticipant) then
      begin
        Guard(mParticipant.ClassName, procedure begin mParticipant.GroupFinished(ASucceeded, mDuration); end);
      end;
    end;
  finally
    LeaveDispatch;
  end;
  Notify('dpcc/compileFinished', TJSONObject.Create.AddPair('group', TJSONBool.Create(True))
    .AddPair('success', TJSONBool.Create(ASucceeded)).AddPair('durationMs', TJSONNumber.Create(mDuration)));
end;

function TDpccCompileEvents.BeforeCompile(const AProject: TDpccCompileProject; AIsCodeInsight: Boolean;
  out AReason: string): Boolean;
var
  mParticipants: TArray<TDpccCompileParticipant>;
  mParticipant: TDpccCompileParticipant;
  mCancel: Boolean;
  mReason, mText: string;
  mInfo: TDpccCompileProject;
begin
  AReason := '';
  Result := False;
  if AIsCodeInsight then
  begin
    FCodeInsightStarted := Now_;
    Inc(FCodeInsightCount);
    Exit;
  end;
  // Wie ProjectStarted: Hintergrundprüfung (#548) und Auftraggeber (#261) gelten schon hier.
  mInfo := AProject;
  mInfo.Background := FBackground;
  mInfo.RequestedBy := FRequestedBy;
  mParticipants := EnterDispatch;
  try
    for mParticipant in mParticipants do
    begin
      if not IsLive(mParticipant) then
      begin
        Continue;
      end;
      mCancel := False;
      mReason := '';
      Guard(mParticipant.ClassName, procedure begin mCancel := mParticipant.CancelCompile(mInfo, mReason); end);
      if mCancel then
      begin
        AReason := Format('%s: %s', [ExtractFileName(AProject.FileName), mReason]);
        Result := True;
        Break;
      end;
    end;
  finally
    LeaveDispatch;
  end;
  if not Result then
  begin
    Exit;
  end;
  mText := AReason;
  mParticipants := EnterDispatch;
  try
    for mParticipant in mParticipants do
    begin
      if IsLive(mParticipant) then
      begin
        Guard(mParticipant.ClassName, procedure begin mParticipant.CompileCancelled(mInfo, mText); end);
      end;
    end;
  finally
    LeaveDispatch;
  end;
end;

procedure TDpccCompileEvents.CodeInsightFinished;
begin
  if FCodeInsightStarted <> 0 then
  begin
    Inc(FCodeInsightMs, Now_ - FCodeInsightStarted);
  end;
  FCodeInsightStarted := 0;
end;

function ProjectJson(const AProject: TDpccCompileProject): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', AProject.FileName);
  Result.AddPair('kind', TDpccCompileEvents.KindText(AProject.Kind));
  Result.AddPair('configuration', AProject.Configuration);
  Result.AddPair('platform', AProject.Platform);
  if AProject.OutputFile <> '' then
  begin
    Result.AddPair('output', AProject.OutputFile);
  end;
  if AProject.Background then
  begin
    Result.AddPair('background', TJSONBool.Create(True));
  end;
  if AProject.RequestedBy <> '' then
  begin
    Result.AddPair('requestedBy', AProject.RequestedBy);
  end;
end;

procedure TDpccCompileEvents.ProjectStarted(const AProject: TDpccCompileProject);
var
  mParticipants: TArray<TDpccCompileParticipant>;
  mParticipant: TDpccCompileParticipant;
  mRunning: TRunning;
begin
  if (AProject.FileName = '') or (RunningIndex(AProject.FileName) >= 0) then
  begin
    Exit;
  end;
  mRunning.Project := AProject;
  mRunning.Project.Background := FBackground;
  mRunning.Project.RequestedBy := FRequestedBy;
  mRunning.Started := Now_;
  FRunning.Add(mRunning);
  mParticipants := EnterDispatch;
  try
    for mParticipant in mParticipants do
    begin
      if IsLive(mParticipant) then
      begin
        Guard(mParticipant.ClassName, procedure begin mParticipant.ProjectStarted(mRunning.Project); end);
      end;
    end;
  finally
    LeaveDispatch;
  end;
  Notify('dpcc/compileStarted', ProjectJson(mRunning.Project));
end;

procedure TDpccCompileEvents.ProjectFinished(const AFileName: string; ASucceeded: Boolean);
var
  mParticipants: TArray<TDpccCompileParticipant>;
  mParticipant: TDpccCompileParticipant;
  mIndex: Integer;
  mRunning: TRunning;
  mDuration: Int64;
  mParams: TJSONObject;
begin
  mIndex := RunningIndex(AFileName);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mRunning := FRunning[mIndex];
  FRunning.Delete(mIndex);
  mDuration := Now_ - mRunning.Started;
  mParticipants := EnterDispatch;
  try
    for mParticipant in mParticipants do
    begin
      if IsLive(mParticipant) then
      begin
        Guard(mParticipant.ClassName,
          procedure
          begin
            mParticipant.ProjectFinished(mRunning.Project, ASucceeded, mDuration);
          end);
      end;
    end;
  finally
    LeaveDispatch;
  end;
  mParams := ProjectJson(mRunning.Project);
  mParams.AddPair('success', TJSONBool.Create(ASucceeded));
  mParams.AddPair('durationMs', TJSONNumber.Create(mDuration));
  Notify('dpcc/compileFinished', mParams);
end;

end.