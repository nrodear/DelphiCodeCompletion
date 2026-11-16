unit dpcc.Core.Notifications.Center;

// Benachrichtigungszentrale (#601), ohne VCL:
// - TDpccNotificationCenter: threadsichere Liste der Einträge der IDE-Sitzung,
//   neueste zuerst, höchstens MaxEntries (Vorgabe 200, ältere fallen weg), mit
//   Beobachtern für Änderungen. Default ist die Zentrale des Plugins; Tests
//   legen eigene mit eigener Uhr an.
// - Zusammenfassen: Ein Hinweis mit derselben Quelle und demselben Titel
//   innerhalb von cMergeSeconds (10 s) nach dem letzten gleichartigen erhöht
//   dessen Zähler („3 × Server neu gestartet“), übernimmt Text, Aktionen und
//   die höhere Schwere, wird wieder ungelesen und rückt nach oben.
// - Verhalten je Quelle (notifications.sources): Show (Vorgabe) und Collect
//   legen einen Eintrag an, Off nicht; die meldende Funktion zeigt ihre eigene
//   Einblendung nur bei Show. Ausgeschaltet (Enabled = False, Vorgabe bis das
//   Plugin sie einschaltet) gilt für alle Quellen Show und es entsteht kein
//   Eintrag: Alles verhält sich wie vor #601.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  dpcc.Core.Notifications.Contract;

type
  TDpccNotificationClock = reference to function: TDateTime;

  TDpccNotificationCenter = class(TInterfacedObject, IDpccNotificationCenter)
  public const
    cDefaultMaxEntries = 200;
    cMinEntries = 10;
    cMaxMaxEntries = 1000;
  private type
    TEntry = class(TInterfacedObject, IDpccNotification)
    private
      FId: Integer;
      FSource: string;
      FSeverity: TDpccNotificationSeverity;
      FTitle: string;
      FText: string;
      FTime: TDateTime;
      FCount: Integer;
      FRead: Boolean;
      FActions: TArray<TDpccNotificationAction>;
    public
      function Id: Integer;
      function Source: string;
      function Severity: TDpccNotificationSeverity;
      function Title: string;
      function Text: string;
      function Time: TDateTime;
      function Count: Integer;
      function Read: Boolean;
      function Actions: TArray<TDpccNotificationAction>;
      function Caption: string;
    end;
  private
    FLock: TCriticalSection;
    // Neueste zuerst. Die Einträge sind unveränderlich nach außen: Änderungen ersetzen sie durch Kopien.
    FItems: TList<IDpccNotification>;
    FModes: TDictionary<string, TDpccNotificationMode>;
    FListeners: TDictionary<Integer, TProc>;
    FNextListener: Integer;
    FNextId: Integer;
    FVersion: Integer;
    FMaxEntries: Integer;
    FEnabled: Boolean;
    FClock: TDpccNotificationClock;
    procedure SetEnabled(AValue: Boolean);
    function GetEnabled: Boolean;
  public
    constructor Create; overload;
    /// <summary>AClock liefert die Zeit (Tests); nil = Now.</summary>
    constructor Create(const AClock: TDpccNotificationClock); overload;
    destructor Destroy; override;
    { IDpccNotificationCenter }
    function Notify(const ASource: string; ASeverity: TDpccNotificationSeverity;
      const ATitle, AText: string): TDpccNotificationMode; overload;
    function Notify(const ASource: string; ASeverity: TDpccNotificationSeverity; const ATitle, AText: string;
      const AActions: TArray<TDpccNotificationAction>): TDpccNotificationMode; overload;
    function ModeOf(const ASource: string): TDpccNotificationMode;
    procedure SetMode(const ASource: string; AMode: TDpccNotificationMode);
    function Items: TArray<IDpccNotification>; overload;
    function Items(const ASource: string): TArray<IDpccNotification>; overload;
    function Find(AId: Integer): IDpccNotification;
    function Sources: TArray<string>;
    procedure MarkRead(AId: Integer);
    procedure MarkAllRead;
    procedure Clear;
    function RunAction(AId, AIndex: Integer): Boolean;
    function UnreadCount: Integer;
    function WorstUnread(out ASeverity: TDpccNotificationSeverity): Boolean;
    function MaxEntries: Integer;
    procedure SetMaxEntries(AValue: Integer);
    function Version: Integer;
    function AddListener(const AListener: TProc): Integer;
    procedure RemoveListener(AHandle: Integer);
    /// <summary>Alle Verhalten aus notifications.sources setzen; nicht genannte Quellen zeigen wieder (Show).
    /// </summary>
    procedure ApplyModes(const ASpec: string);
    /// <summary>Zentrale an (Plugin-Einstellung Notifications); aus = kein Sammeln, alle Quellen zeigen.</summary>
    property Enabled: Boolean read GetEnabled write SetEnabled;
    /// <summary>Zentrale des Plugins; andere Funktionen melden hier ihre Hinweise.</summary>
    class function Default: IDpccNotificationCenter; static;
    /// <summary>Dieselbe Zentrale als Objekt (Einschalten, Verhalten setzen); nur für die Komposition.</summary>
    class function DefaultCenter: TDpccNotificationCenter; static;
    /// <summary>Gibt die Zentrale des Plugins frei (Entladen).</summary>
    class procedure ReleaseDefault; static;
    /// <summary>Aktion mit Beschriftung.</summary>
    class function Action(const ACaption: string; const ARun: TProc): TDpccNotificationAction; static;
  end;

implementation

uses
  System.Math,
  dpcc.Core.Notifications.Sources;

const
  /// <summary>Gleichartige Hinweise innerhalb dieser Sekunden werden zusammengefasst.</summary>
  cMergeSeconds = 10;

var
  /// <summary>Zentrale des Plugins (Default) und dieselbe als Objekt (DefaultCenter).</summary>
  GDefaultCenter: IDpccNotificationCenter;
  GDefaultCenterObject: TDpccNotificationCenter;

/// <summary>Höhere der beiden Schweren.</summary>
function Worse(ALeft, ARight: TDpccNotificationSeverity): TDpccNotificationSeverity;
begin
  if Ord(ARight) > Ord(ALeft) then
  begin
    Result := ARight;
  end
  else
  begin
    Result := ALeft;
  end;
end;

/// <summary>"3 × Titel" ab ACount = 2, sonst ATitle.</summary>
function CaptionOf(const ATitle: string; ACount: Integer): string;
begin
  if ACount > 1 then
  begin
    Result := IntToStr(ACount) + ' × ' + ATitle;
  end
  else
  begin
    Result := ATitle;
  end;
end;

{ TDpccNotificationCenter.TEntry }

function TDpccNotificationCenter.TEntry.Id: Integer;
begin
  Result := FId;
end;

function TDpccNotificationCenter.TEntry.Source: string;
begin
  Result := FSource;
end;

function TDpccNotificationCenter.TEntry.Severity: TDpccNotificationSeverity;
begin
  Result := FSeverity;
end;

function TDpccNotificationCenter.TEntry.Title: string;
begin
  Result := FTitle;
end;

function TDpccNotificationCenter.TEntry.Text: string;
begin
  Result := FText;
end;

function TDpccNotificationCenter.TEntry.Time: TDateTime;
begin
  Result := FTime;
end;

function TDpccNotificationCenter.TEntry.Count: Integer;
begin
  Result := FCount;
end;

function TDpccNotificationCenter.TEntry.Read: Boolean;
begin
  Result := FRead;
end;

function TDpccNotificationCenter.TEntry.Actions: TArray<TDpccNotificationAction>;
begin
  Result := FActions;
end;

function TDpccNotificationCenter.TEntry.Caption: string;
begin
  Result := CaptionOf(FTitle, FCount);
end;

{ TDpccNotificationCenter }

constructor TDpccNotificationCenter.Create;
begin
  Create(nil);
end;

constructor TDpccNotificationCenter.Create(const AClock: TDpccNotificationClock);
begin
  inherited Create;
  FClock := AClock;
  FLock := TCriticalSection.Create;
  FItems := TList<IDpccNotification>.Create;
  FModes := TDictionary<string, TDpccNotificationMode>.Create;
  FListeners := TDictionary<Integer, TProc>.Create;
  FMaxEntries := cDefaultMaxEntries;
  FEnabled := True;
end;

destructor TDpccNotificationCenter.Destroy;
begin
  FListeners.Free;
  FModes.Free;
  FItems.Free;
  FLock.Free;
  inherited;
end;

class function TDpccNotificationCenter.Default: IDpccNotificationCenter;
begin
  if GDefaultCenter = nil then
  begin
    GDefaultCenterObject := TDpccNotificationCenter.Create;
    // Bis das Plugin sie nach seinen Einstellungen einschaltet, verhält sich alles wie vor #601.
    GDefaultCenterObject.FEnabled := False;
    GDefaultCenter := GDefaultCenterObject;
  end;
  Result := GDefaultCenter;
end;

class function TDpccNotificationCenter.DefaultCenter: TDpccNotificationCenter;
begin
  Default;
  Result := GDefaultCenterObject;
end;

class procedure TDpccNotificationCenter.ReleaseDefault;
begin
  GDefaultCenterObject := nil;
  GDefaultCenter := nil;
end;

class function TDpccNotificationCenter.Action(const ACaption: string; const ARun: TProc): TDpccNotificationAction;
begin
  Result.Caption := ACaption;
  Result.Run := ARun;
end;

function Copy_(const AEntry: IDpccNotification): TDpccNotificationCenter.TEntry;
begin
  Result := TDpccNotificationCenter.TEntry.Create;
  Result.FId := AEntry.Id;
  Result.FSource := AEntry.Source;
  Result.FSeverity := AEntry.Severity;
  Result.FTitle := AEntry.Title;
  Result.FText := AEntry.Text;
  Result.FTime := AEntry.Time;
  Result.FCount := AEntry.Count;
  Result.FRead := AEntry.Read;
  Result.FActions := AEntry.Actions;
end;

function ClockNow(const AClock: TDpccNotificationClock): TDateTime;
begin
  if Assigned(AClock) then
  begin
    Result := AClock();
  end
  else
  begin
    Result := Now;
  end;
end;

function IndexOfId(AItems: TList<IDpccNotification>; AId: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AItems.Count - 1 do
  begin
    if AItems[mIndex].Id = AId then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function ModeIn(AEnabled: Boolean; AModes: TDictionary<string, TDpccNotificationMode>;
  const ASource: string): TDpccNotificationMode;
begin
  if not AEnabled or not AModes.TryGetValue(LowerCase(ASource), Result) then
  begin
    Result := TDpccNotificationMode.Show;
  end;
end;

procedure TrimTo(AItems: TList<IDpccNotification>; AMax: Integer);
begin
  while AItems.Count > AMax do
  begin
    AItems.Delete(AItems.Count - 1);
  end;
end;

/// <summary>Version erhöhen und die Beobachter von ACenter rufen.</summary>
procedure NotifyChanged(ACenter: TDpccNotificationCenter);
var
  mListeners: TArray<TProc>;
  mListener: TProc;
begin
  ACenter.FLock.Enter;
  try
    Inc(ACenter.FVersion);
    mListeners := ACenter.FListeners.Values.ToArray;
  finally
    ACenter.FLock.Leave;
  end;
  // Außerhalb der Sperre: Beobachter dürfen die Zentrale lesen.
  for mListener in mListeners do
    try
      mListener();
    except
      // Ein Fehler im Beobachter darf die meldende Funktion nicht stören.
      on Exception do
        ;
    end;
end;

function TDpccNotificationCenter.Notify(const ASource: string; ASeverity: TDpccNotificationSeverity;
  const ATitle, AText: string): TDpccNotificationMode;
begin
  Result := Notify(ASource, ASeverity, ATitle, AText, nil);
end;

function TDpccNotificationCenter.Notify(const ASource: string; ASeverity: TDpccNotificationSeverity;
  const ATitle, AText: string; const AActions: TArray<TDpccNotificationAction>): TDpccNotificationMode;
var
  mStamp, mLimit: TDateTime;
  mIndex, mFound: Integer;
  mEntry: TEntry;
  mExisting: IDpccNotification;
begin
  mStamp := ClockNow(FClock);
  FLock.Enter;
  try
    Result := ModeIn(FEnabled, FModes, ASource);
    if not FEnabled or (Result = TDpccNotificationMode.Off) then
    begin
      Exit;
    end;
    // Gleichartig: dieselbe Quelle und derselbe Titel, letzte Meldung höchstens MergeSeconds zurück.
    mLimit := mStamp - cMergeSeconds / SecsPerDay;
    mFound := -1;
    for mIndex := 0 to FItems.Count - 1 do
    begin
      mExisting := FItems[mIndex];
      if SameText(mExisting.Source, ASource) and (mExisting.Title = ATitle) and (mExisting.Time >= mLimit) then
      begin
        mFound := mIndex;
        Break;
      end;
    end;
    if mFound >= 0 then
    begin
      mEntry := Copy_(FItems[mFound]);
      FItems.Delete(mFound);
      Inc(mEntry.FCount);
      mEntry.FSeverity := Worse(mEntry.FSeverity, ASeverity);
    end
    else
    begin
      mEntry := TEntry.Create;
      Inc(FNextId);
      mEntry.FId := FNextId;
      mEntry.FSource := ASource;
      mEntry.FSeverity := ASeverity;
      mEntry.FTitle := ATitle;
      mEntry.FCount := 1;
    end;
    mEntry.FText := AText;
    mEntry.FTime := mStamp;
    mEntry.FRead := False;
    mEntry.FActions := Copy(AActions);
    FItems.Insert(0, mEntry);
    TrimTo(FItems, FMaxEntries);
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

function TDpccNotificationCenter.ModeOf(const ASource: string): TDpccNotificationMode;
begin
  FLock.Enter;
  try
    Result := ModeIn(FEnabled, FModes, ASource);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccNotificationCenter.SetMode(const ASource: string; AMode: TDpccNotificationMode);
begin
  if Trim(ASource) = '' then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    if AMode = TDpccNotificationMode.Show then
    begin
      FModes.Remove(LowerCase(ASource));
    end
    else
    begin
      FModes.AddOrSetValue(LowerCase(ASource), AMode);
    end;
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

procedure TDpccNotificationCenter.ApplyModes(const ASpec: string);
var
  mEntry: TDpccNotificationSourceMode;
begin
  FLock.Enter;
  try
    FModes.Clear;
    for mEntry in TDpccNotificationSources.Parse(ASpec) do
    begin
      if mEntry.Mode <> TDpccNotificationMode.Show then
      begin
        FModes.AddOrSetValue(LowerCase(mEntry.Source), mEntry.Mode);
      end;
    end;
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

function TDpccNotificationCenter.Items: TArray<IDpccNotification>;
begin
  FLock.Enter;
  try
    Result := FItems.ToArray;
  finally
    FLock.Leave;
  end;
end;

function TDpccNotificationCenter.Items(const ASource: string): TArray<IDpccNotification>;
var
  mEntry: IDpccNotification;
begin
  if ASource = '' then
  begin
    Exit(Items);
  end;
  Result := nil;
  for mEntry in Items do
  begin
    if SameText(mEntry.Source, ASource) then
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

function TDpccNotificationCenter.Find(AId: Integer): IDpccNotification;
var
  mIndex: Integer;
begin
  Result := nil;
  FLock.Enter;
  try
    mIndex := IndexOfId(FItems, AId);
    if mIndex >= 0 then
    begin
      Result := FItems[mIndex];
    end;
  finally
    FLock.Leave;
  end;
end;

function TDpccNotificationCenter.Sources: TArray<string>;
var
  mEntry: IDpccNotification;
  mSource: string;
  mKnown: Boolean;
begin
  Result := nil;
  for mEntry in Items do
  begin
    mKnown := False;
    for mSource in Result do
    begin
      if SameText(mSource, mEntry.Source) then
      begin
        mKnown := True;
      end;
    end;
    if not mKnown then
    begin
      Result := Result + [mEntry.Source];
    end;
  end;
end;

procedure TDpccNotificationCenter.MarkRead(AId: Integer);
var
  mIndex: Integer;
  mEntry: TEntry;
begin
  FLock.Enter;
  try
    mIndex := IndexOfId(FItems, AId);
    if (mIndex < 0) or FItems[mIndex].Read then
    begin
      Exit;
    end;
    mEntry := Copy_(FItems[mIndex]);
    mEntry.FRead := True;
    FItems[mIndex] := mEntry;
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

procedure TDpccNotificationCenter.MarkAllRead;
var
  mIndex: Integer;
  mEntry: TEntry;
  mChanged: Boolean;
begin
  mChanged := False;
  FLock.Enter;
  try
    for mIndex := 0 to FItems.Count - 1 do
    begin
      if not FItems[mIndex].Read then
      begin
        mEntry := Copy_(FItems[mIndex]);
        mEntry.FRead := True;
        FItems[mIndex] := mEntry;
        mChanged := True;
      end;
    end;
  finally
    FLock.Leave;
  end;
  if mChanged then
  begin
    NotifyChanged(Self);
  end;
end;

procedure TDpccNotificationCenter.Clear;
begin
  FLock.Enter;
  try
    FItems.Clear;
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

function TDpccNotificationCenter.RunAction(AId, AIndex: Integer): Boolean;
var
  mEntry: IDpccNotification;
  mActions: TArray<TDpccNotificationAction>;
  mRun: TProc;
begin
  mEntry := Find(AId);
  Result := False;
  if mEntry = nil then
  begin
    Exit;
  end;
  mActions := mEntry.Actions;
  if (AIndex < 0) or (AIndex > High(mActions)) then
  begin
    Exit;
  end;
  mRun := mActions[AIndex].Run;
  // Erst gelesen, dann die Aktion: Sie kann ein Fenster öffnen oder die Liste ändern.
  MarkRead(AId);
  if Assigned(mRun) then
  begin
    mRun();
  end;
  Result := True;
end;

function TDpccNotificationCenter.UnreadCount: Integer;
var
  mEntry: IDpccNotification;
begin
  Result := 0;
  FLock.Enter;
  try
    for mEntry in FItems do
    begin
      if not mEntry.Read then
      begin
        Inc(Result);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDpccNotificationCenter.WorstUnread(out ASeverity: TDpccNotificationSeverity): Boolean;
var
  mEntry: IDpccNotification;
begin
  Result := False;
  ASeverity := TDpccNotificationSeverity.Info;
  FLock.Enter;
  try
    for mEntry in FItems do
    begin
      if not mEntry.Read then
      begin
        if not Result then
        begin
          ASeverity := mEntry.Severity;
        end
        else
        begin
          ASeverity := Worse(ASeverity, mEntry.Severity);
        end;
        Result := True;
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDpccNotificationCenter.MaxEntries: Integer;
begin
  FLock.Enter;
  try
    Result := FMaxEntries;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccNotificationCenter.SetMaxEntries(AValue: Integer);
var
  mBefore: Integer;
begin
  FLock.Enter;
  try
    mBefore := FItems.Count;
    FMaxEntries := EnsureRange(AValue, cMinEntries, cMaxMaxEntries);
    TrimTo(FItems, FMaxEntries);
    if FItems.Count = mBefore then
    begin
      Exit;
    end;
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

function TDpccNotificationCenter.Version: Integer;
begin
  FLock.Enter;
  try
    Result := FVersion;
  finally
    FLock.Leave;
  end;
end;

function TDpccNotificationCenter.AddListener(const AListener: TProc): Integer;
begin
  FLock.Enter;
  try
    Inc(FNextListener);
    Result := FNextListener;
    FListeners.Add(Result, AListener);
  finally
    FLock.Leave;
  end;
end;

procedure TDpccNotificationCenter.RemoveListener(AHandle: Integer);
begin
  FLock.Enter;
  try
    FListeners.Remove(AHandle);
  finally
    FLock.Leave;
  end;
end;

function TDpccNotificationCenter.GetEnabled: Boolean;
begin
  FLock.Enter;
  try
    Result := FEnabled;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccNotificationCenter.SetEnabled(AValue: Boolean);
begin
  FLock.Enter;
  try
    if FEnabled = AValue then
    begin
      Exit;
    end;
    FEnabled := AValue;
    // Ausgeschaltet: keine Liste, kein Zähler.
    if not AValue then
    begin
      FItems.Clear;
    end;
  finally
    FLock.Leave;
  end;
  NotifyChanged(Self);
end;

end.
