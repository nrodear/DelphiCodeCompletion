unit dpcc.Core.Diagnostics.SafeMode;

// Abgesicherter Start nach einem Absturz (#722), Teil ohne Windows und ohne
// Open Tools API:
// - Startmarke: Beim Laden schreibt dpcc je IDE-Prozess eine Marke „Sitzung
//   läuft“ (Prozess, dpcc-Version, Startzeit, aktive Funktionen, Fehler je
//   Feature aus #493) und löscht sie beim sauberen Beenden. Eine Marke, deren
//   Prozess nicht mehr läuft, heißt: Die Sitzung ist abgestürzt.
// - Zustand zwischen den Sitzungen: Anzahl der Abstürze hintereinander, Zeit
//   des letzten und Marke der abgestürzten Sitzung (für „Details“).
// - Ein langsamer Start ist kein Absturz: Er schaltet beim
//   nächsten Start nichts ab. dpcc misst stattdessen seine Startanteile
//   (TDpccStartTimes) und nennt sie, damit sich die Ursache beheben lässt.
// - Entscheidung beim Start: Umschalt/Strg beim Laden, Kommandozeile
//   -DpccSafeMode oder DPCC_SAFE_MODE=1 → nur Einstellungsseite und
//   Statusfeld (Minimal); zwei Abstürze innerhalb von RepeatWindowMinutes →
//   abgesichert ohne Rückfrage; ein Absturz → abgesichert, bis die Rückfrage
//   beantwortet ist; sonst normal.
// - Abgesichert heißt: alle Schnellschalter (#604) für diese Sitzung aus;
//   Suggest nennt, womit man beim Wiedereinschalten anfängt (zuletzt
//   geänderte Einstellungen, dann Funktionen mit Fehlern).
// - Sitzungen ohne Marke: Ein Prozess mit DPCC_NO_SESSION_MARKER=1 (z. B.
//   die Bau-IDE von Tools/Build-Ide.ps1, die abgewürgt werden darf) schreibt keine Marke,
//   wertet keine fremden aus und lässt den Zustand unberührt
//   (TDpccSessionBook). Sonst zählte jede abgewürgte Bau-IDE als Absturz
//   und brachte die nächste echte Sitzung in Stufe Safe.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  dpcc.Core.Settings.QuickToggles,
  // TDpccSafeLevel (Stufe des abgesicherten Starts) steht im Modulvertrag (#1455).
  dpcc.Core.Modules.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Warum nicht normal: nach einem Absturz (Rückfrage offen), nach wiederholtem Absturz, Taste beim
  /// Start, Kommandozeile bzw. Umgebungsvariable.</summary>
  TDpccSafeReason = (None, Crash, RepeatedCrash, StartupKey, Forced);
  TDpccStartupKey = (None, Shift, Ctrl);
{$SCOPEDENUMS OFF}

  TDpccSessionMarker = record
    ProcessId: Cardinal;
    Version: string;
    /// <summary>UTC.</summary>
    StartedAt: TDateTime;
    /// <summary>Laden fertig (Nachrichtenschleife frei) und wie lange es gedauert hat.</summary>
    Loaded: Boolean;
    LoadMs: Int64;
    Level: TDpccSafeLevel;
    /// <summary>Aktive Funktionen (Namen der eingeschalteten Schnellschalter).</summary>
    Features: TArray<string>;
    /// <summary>Fehler je Feature (#493) in dieser Sitzung.</summary>
    Failures: TArray<TPair<string, Integer>>;
    class function Create(AProcessId: Cardinal; const AVersion: string; AStartedAt: TDateTime): TDpccSessionMarker;
      static;
    procedure AddFailure(const AFeature: string);
    function FailureCount(const AFeature: string): Integer;
    function ToJson: string;
    /// <summary>False bei ungültigem Text.</summary>
    class function FromJson(const AText: string; out AMarker: TDpccSessionMarker): Boolean; static;
  end;

  TDpccSafeOptions = record
    AskAfterCrash: Boolean;
    AutoAfterRepeatedCrash: Boolean;
    StartupKey: TDpccStartupKey;
    class function Create(AAsk, AAuto: Boolean; AKey: TDpccStartupKey): TDpccSafeOptions; static;
  end;

  /// <summary>Was zwischen den Sitzungen bleibt.</summary>
  TDpccSafeState = record
    /// <summary>Abstürze hintereinander; ein sauberes Ende setzt auf 0.</summary>
    CrashCount: Integer;
    /// <summary>UTC; 0 ohne.</summary>
    LastCrashAt: TDateTime;
    /// <summary>Marke der zuletzt abgestürzten Sitzung als JSON; '' ohne.</summary>
    CrashedMarker: string;
    function ToJson: string;
    class function FromJson(const AText: string): TDpccSafeState; static;
  end;

  TDpccSafeDecision = record
    Level: TDpccSafeLevel;
    Reason: TDpccSafeReason;
    /// <summary>Letzte Sitzung abgestürzt (ein langsamer Start zählt nicht).</summary>
    Crashed: Boolean;
    /// <summary>Rückfrage zeigen („Abgesichert starten“, „Normal starten“, „Details“).</summary>
    Ask: Boolean;
  end;

  TDpccSafeMode = class
  public const
    /// <summary>Zwei Abstürze in dieser Zeit gelten als wiederholt.</summary>
    cRepeatWindowMinutes = 10;
    cEnvironmentName = 'DPCC_SAFE_MODE';
    cSwitchName = 'DpccSafeMode';
    /// <summary>Gesetzt ("1", "true", "yes"): Diese Sitzung führt kein Sitzungsbuch (TDpccSessionBook).</summary>
    cNoMarkerEnvironmentName = 'DPCC_NO_SESSION_MARKER';
  public
    /// <summary>Entscheidung beim Start und neuer Zustand. ACrashed: Marken früherer Sitzungen, deren Prozess
    /// nicht mehr läuft; AKeyDown: welche Taste beim Laden gedrückt ist; AForced: Kommandozeile bzw.
    /// Umgebungsvariable.</summary>
    class function Decide(var AState: TDpccSafeState; const ACrashed: TArray<TDpccSessionMarker>;
      ANow: TDateTime; const AOptions: TDpccSafeOptions; AKeyDown: TDpccStartupKey;
      AForced: Boolean): TDpccSafeDecision; static;
    /// <summary>Sauberes Ende: keine Abstürze mehr in Folge.</summary>
    class procedure CleanExit(var AState: TDpccSafeState); static;
    /// <summary>Umgebungsvariable ("1", "true", "yes") oder Kommandozeile -DpccSafeMode bzw. /DpccSafeMode.</summary>
    class function IsForced(const AEnvironment: string; const AArgs: TArray<string>): Boolean; static;
    /// <summary>Wert einer Schalter-Umgebungsvariable gesetzt: "1", "true" oder "yes" (ohne Rücksicht auf
    /// Groß-/Kleinschreibung und Leerraum).</summary>
    class function IsSwitchOn(const AEnvironment: string): Boolean; static;
    /// <summary>Taste aus safeMode.startupKey ("shift", "ctrl", "none").</summary>
    class function KeyOf(const AText: string): TDpccStartupKey; static;
    class function KeyText(AKey: TDpccStartupKey): string; static;
    /// <summary>Sitzungswerte für den abgesicherten Start: alle Schnellschalter aus.</summary>
    class function SafeSession(const AToggles: TArray<TDpccQuickToggle>): TDpccToggleSession; static;
    /// <summary>Womit man beim Wiedereinschalten anfängt: zuletzt geänderte Einstellungen, dann Funktionen mit
    /// den meisten Fehlern der abgestürzten Sitzung (x-feature), jeweils nur Schnellschalter.</summary>
    class function Suggest(const AToggles: TArray<TDpccQuickToggle>; const AChangedKeys: TArray<string>;
      const ACrashed: TDpccSessionMarker): TArray<string>; static;
    /// <summary>Text der Details: Version, Start, Ladezeit, aktive Funktionen, Fehler je Feature.</summary>
    class function Details(const AMarker: TDpccSessionMarker): TArray<string>; static;
    /// <summary>Zeilen des Plugin-Protokolls (Zeitstempel "yyyy-mm-dd hh:nn:ss.zzz" in Ortszeit) ab AFrom und vor
    /// ATo (0 = ohne Ende), höchstens die letzten AMax; Zeilen ohne Zeitstempel gehören zur vorigen.</summary>
    class function LogLinesBetween(const ALines: TArray<string>; AFrom, ATo: TDateTime;
      AMax: Integer): TArray<string>; static;
  end;

  /// <summary>Läuft der Prozess AProcessId noch und ist er nicht nach AStartedAt (UTC) gestartet (sonst hat ein
  /// neuer Prozess die Nummer übernommen)?</summary>
  TDpccProcessAlive = reference to function(AProcessId: Cardinal; AStartedAt: TDateTime): Boolean;

  /// <summary>Dateien des abgesicherten Starts in AFolder (in der IDE %LOCALAPPDATA%\dpcc\Session): je Prozess
  /// session-&lt;pid&gt;.json und der Zustand safemode.json. Geschrieben wird über eine temporäre Datei, damit
  /// ein Absturz mitten im Schreiben keine halbe Marke hinterlässt.</summary>
  TDpccSessionFiles = class
  public
    class function MarkerFile(const AFolder: string; AProcessId: Cardinal): string; static;
    class function StateFile(const AFolder: string): string; static;
    class procedure WriteMarker(const AFolder: string; const AMarker: TDpccSessionMarker); static;
    class procedure DeleteMarker(const AFolder: string; AProcessId: Cardinal); static;
    /// <summary>Marken früherer Sitzungen, deren Prozess nicht mehr läuft; ihre Dateien werden gelöscht.
    /// Die eigene Marke (AOwnProcessId) und Marken laufender IDEs bleiben; unlesbare Marken fallen weg.</summary>
    class function TakeCrashed(const AFolder: string; AOwnProcessId: Cardinal;
      const AAlive: TDpccProcessAlive): TArray<TDpccSessionMarker>; static;
    class function ReadState(const AFolder: string): TDpccSafeState; static;
    class procedure WriteState(const AFolder: string; const AState: TDpccSafeState); static;
  end;

  /// <summary>Sitzungsbuch eines IDE-Prozesses: eigene Marke, Marken abgestürzter Sitzungen und Zustand in
  /// Folder. Ohne Buch (Tracked = False, DPCC_NO_SESSION_MARKER) schreibt die Sitzung nichts und liest keine
  /// fremden Marken: Ihr Ende sagt nichts über Abstürze, und abgestürzte Sitzungen bleiben für die nächste
  /// Sitzung mit Buch liegen.</summary>
  TDpccSessionBook = record
    Folder: string;
    ProcessId: Cardinal;
    Tracked: Boolean;
    /// <summary>ANoMarkerEnvironment: Wert von DPCC_NO_SESSION_MARKER.</summary>
    class function Create(const AFolder: string; AProcessId: Cardinal;
      const ANoMarkerEnvironment: string): TDpccSessionBook; static;
    /// <summary>Zustand und Marken früherer Sitzungen, deren Prozess nicht mehr läuft (TakeCrashed); ohne Buch
    /// leer.</summary>
    procedure Open(const AAlive: TDpccProcessAlive; out AState: TDpccSafeState;
      out ACrashed: TArray<TDpccSessionMarker>);
    procedure SaveState(const AState: TDpccSafeState);
    procedure SaveMarker(const AMarker: TDpccSessionMarker);
    /// <summary>Sauberes Ende: eigene Marke löschen, Absturzzähler zurücksetzen.</summary>
    procedure Close;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TSafeModeText = (LoadingMs, LoadingNotFinished, Mode, ActiveFeatures, ErrorsNone, Errors);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TSafeModeText] of string = (
    ('Laden: %d ms',
     'Laden: nicht abgeschlossen',
     'Modus: ',
     'Aktive Funktionen: ',
     'Fehler: keine',
     'Fehler %s: %d'),
    ('Loading: %d ms',
     'Loading: not finished',
     'Mode: ',
     'Active features: ',
     'Errors: none',
     'Errors %s: %d'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TSafeModeText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

const
  cLevelNames: array[TDpccSafeLevel] of string = ('normal', 'safe', 'minimal');

function LevelOf(const AText: string): TDpccSafeLevel;
var
  mLevel: TDpccSafeLevel;
begin
  for mLevel := Low(TDpccSafeLevel) to High(TDpccSafeLevel) do
  begin
    if SameText(cLevelNames[mLevel], AText) then
    begin
      Exit(mLevel);
    end;
  end;
  Result := TDpccSafeLevel.Normal;
end;

{ TDpccSessionMarker }

class function TDpccSessionMarker.Create(AProcessId: Cardinal; const AVersion: string;
  AStartedAt: TDateTime): TDpccSessionMarker;
begin
  Result := Default(TDpccSessionMarker);
  Result.ProcessId := AProcessId;
  Result.Version := AVersion;
  Result.StartedAt := AStartedAt;
  Result.LoadMs := -1;
end;

procedure TDpccSessionMarker.AddFailure(const AFeature: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Failures) do
  begin
    if SameText(Failures[mIndex].Key, AFeature) then
    begin
      Failures[mIndex] := TPair<string, Integer>.Create(Failures[mIndex].Key, Failures[mIndex].Value + 1);
      Exit;
    end;
  end;
  Failures := Failures + [TPair<string, Integer>.Create(AFeature, 1)];
end;

function TDpccSessionMarker.FailureCount(const AFeature: string): Integer;
var
  mPair: TPair<string, Integer>;
begin
  for mPair in Failures do
  begin
    if SameText(mPair.Key, AFeature) then
    begin
      Exit(mPair.Value);
    end;
  end;
  Result := 0;
end;

function TDpccSessionMarker.ToJson: string;
var
  mRoot, mCounts: TJSONObject;
  mList: TJSONArray;
  mName: string;
  mPair: TPair<string, Integer>;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('processId', TJSONNumber.Create(Int64(ProcessId)));
    mRoot.AddPair('version', TJSONString.Create(Version));
    mRoot.AddPair('startedAt', TJSONString.Create(DateToISO8601(StartedAt, True)));
    mRoot.AddPair('loaded', TJSONBool.Create(Loaded));
    mRoot.AddPair('loadMs', TJSONNumber.Create(LoadMs));
    mRoot.AddPair('level', TJSONString.Create(cLevelNames[Level]));
    mList := TJSONArray.Create;
    for mName in Features do
    begin
      mList.Add(mName);
    end;
    mRoot.AddPair('features', mList);
    mCounts := TJSONObject.Create;
    for mPair in Failures do
    begin
      mCounts.AddPair(mPair.Key, TJSONNumber.Create(mPair.Value));
    end;
    mRoot.AddPair('failures', mCounts);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

/// <summary>ISO-8601-Zeitpunkt (UTC); 0 bei leerem oder ungültigem Text.</summary>
function MarkerDateOf(const AStamp: string): TDateTime;
begin
  Result := 0;
  if AStamp = '' then
  begin
    Exit;
  end;
  try
    Result := ISO8601ToDate(AStamp, True);
  except
    on EConvertError do
    begin
      Result := 0;
    end;
  end;
end;

function MarkerFeaturesOf(const AValue: TJSONValue): TArray<string>;
var
  mElement: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mElement in TJSONArray(AValue) do
  begin
    if mElement is TJSONString then
    begin
      Result := Result + [TJSONString(mElement).Value];
    end;
  end;
end;

function MarkerFailuresOf(const AValue: TJSONValue): TArray<TPair<string, Integer>>;
var
  mPair: TJSONPair;
begin
  Result := nil;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  for mPair in TJSONObject(AValue) do
  begin
    if mPair.JsonValue is TJSONNumber then
    begin
      Result := Result + [TPair<string, Integer>.Create(mPair.JsonString.Value, TJSONNumber(mPair.JsonValue).AsInt)];
    end;
  end;
end;

class function TDpccSessionMarker.FromJson(const AText: string; out AMarker: TDpccSessionMarker): Boolean;
var
  mRoot, mValue: TJSONValue;
begin
  AMarker := Default(TDpccSessionMarker);
  Result := False;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mValue := TJSONObject(mRoot).GetValue('processId');
    if not (mValue is TJSONNumber) then
    begin
      Exit;
    end;
    AMarker.ProcessId := Cardinal(TJSONNumber(mValue).AsInt64);
    AMarker.Version := TJSONObject(mRoot).GetValue<string>('version', '');
    AMarker.StartedAt := MarkerDateOf(TJSONObject(mRoot).GetValue<string>('startedAt', ''));
    mValue := TJSONObject(mRoot).GetValue('loaded');
    AMarker.Loaded := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
    mValue := TJSONObject(mRoot).GetValue('loadMs');
    AMarker.LoadMs := -1;
    if mValue is TJSONNumber then
    begin
      AMarker.LoadMs := TJSONNumber(mValue).AsInt64;
    end;
    AMarker.Level := LevelOf(TJSONObject(mRoot).GetValue<string>('level', ''));
    AMarker.Features := MarkerFeaturesOf(TJSONObject(mRoot).GetValue('features'));
    AMarker.Failures := MarkerFailuresOf(TJSONObject(mRoot).GetValue('failures'));
    Result := True;
  finally
    mRoot.Free;
  end;
end;

{ TDpccSafeOptions }

class function TDpccSafeOptions.Create(AAsk, AAuto: Boolean; AKey: TDpccStartupKey): TDpccSafeOptions;
begin
  Result.AskAfterCrash := AAsk;
  Result.AutoAfterRepeatedCrash := AAuto;
  Result.StartupKey := AKey;
end;

{ TDpccSafeState }

function TDpccSafeState.ToJson: string;
var
  mRoot: TJSONObject;
  mCrashed: TJSONValue;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('crashCount', TJSONNumber.Create(CrashCount));
    if LastCrashAt > 0 then
    begin
      mRoot.AddPair('lastCrashAt', TJSONString.Create(DateToISO8601(LastCrashAt, True)));
    end;
    mCrashed := nil;
    if CrashedMarker <> '' then
    begin
      mCrashed := TJSONObject.ParseJSONValue(CrashedMarker);
    end;
    if mCrashed is TJSONObject then
    begin
      mRoot.AddPair('crashed', mCrashed);
    end
    else
    begin
      mCrashed.Free;
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

class function TDpccSafeState.FromJson(const AText: string): TDpccSafeState;
var
  mRoot, mValue: TJSONValue;
  mStamp: string;
begin
  Result := Default(TDpccSafeState);
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mValue := TJSONObject(mRoot).GetValue('crashCount');
    if mValue is TJSONNumber then
    begin
      Result.CrashCount := Max(0, TJSONNumber(mValue).AsInt);
    end;
    mStamp := TJSONObject(mRoot).GetValue<string>('lastCrashAt', '');
    if mStamp <> '' then
      try
        Result.LastCrashAt := ISO8601ToDate(mStamp, True);
      except
        on EConvertError do
          Result.LastCrashAt := 0;
      end;
    // "slowStart" älterer Fassungen bleibt unbeachtet: Ein langsamer Start ist kein Absturz.
    mValue := TJSONObject(mRoot).GetValue('crashed');
    if mValue is TJSONObject then
    begin
      Result.CrashedMarker := mValue.ToJSON;
    end;
  finally
    mRoot.Free;
  end;
end;

{ TDpccSafeMode }

/// <summary>Zählt einen Absturz in AState und merkt die zuletzt gestartete abgestürzte Sitzung; True, wenn er
/// binnen ARepeatMinutes nach dem letzten kam.</summary>
function RecordCrash(var AState: TDpccSafeState; const ACrashed: TArray<TDpccSessionMarker>; ANow: TDateTime;
  ARepeatMinutes: Integer): Boolean;
var
  mLatest, mMarker: TDpccSessionMarker;
begin
  Result := (AState.CrashCount > 0) and (AState.LastCrashAt > 0) and
    (MinutesBetween(ANow, AState.LastCrashAt) < ARepeatMinutes) and (ANow >= AState.LastCrashAt);
  if Result then
  begin
    Inc(AState.CrashCount);
  end
  else
  begin
    AState.CrashCount := 1;
  end;
  AState.LastCrashAt := ANow;
  // Für „Details“ die zuletzt gestartete abgestürzte Sitzung.
  mLatest := ACrashed[0];
  for mMarker in ACrashed do
  begin
    if mMarker.StartedAt > mLatest.StartedAt then
    begin
      mLatest := mMarker;
    end;
  end;
  AState.CrashedMarker := mLatest.ToJson;
end;

class function TDpccSafeMode.Decide(var AState: TDpccSafeState; const ACrashed: TArray<TDpccSessionMarker>;
  ANow: TDateTime; const AOptions: TDpccSafeOptions; AKeyDown: TDpccStartupKey;
  AForced: Boolean): TDpccSafeDecision;
var
  mRepeated: Boolean;
begin
  Result := Default(TDpccSafeDecision);
  Result.Crashed := Length(ACrashed) > 0;
  mRepeated := Result.Crashed and RecordCrash(AState, ACrashed, ANow, cRepeatWindowMinutes);
  if AForced then
  begin
    Result.Level := TDpccSafeLevel.Minimal;
    Result.Reason := TDpccSafeReason.Forced;
  end
  else if (AOptions.StartupKey <> TDpccStartupKey.None) and (AKeyDown = AOptions.StartupKey) then
  begin
    Result.Level := TDpccSafeLevel.Minimal;
    Result.Reason := TDpccSafeReason.StartupKey;
  end
  else if mRepeated and AOptions.AutoAfterRepeatedCrash then
  begin
    Result.Level := TDpccSafeLevel.Safe;
    Result.Reason := TDpccSafeReason.RepeatedCrash;
  end
  else if Result.Crashed and AOptions.AskAfterCrash then
  begin
    // Bis zur Antwort abgesichert: Die Rückfrage blockiert den Start nicht.
    Result.Level := TDpccSafeLevel.Safe;
    Result.Reason := TDpccSafeReason.Crash;
    Result.Ask := True;
  end;
end;

class procedure TDpccSafeMode.CleanExit(var AState: TDpccSafeState);
begin
  AState.CrashCount := 0;
end;

class function TDpccSafeMode.IsSwitchOn(const AEnvironment: string): Boolean;
var
  mValue: string;
begin
  mValue := Trim(AEnvironment);
  Result := SameText(mValue, '1') or SameText(mValue, 'true') or SameText(mValue, 'yes');
end;

class function TDpccSafeMode.IsForced(const AEnvironment: string; const AArgs: TArray<string>): Boolean;
var
  mArg: string;
begin
  if IsSwitchOn(AEnvironment) then
  begin
    Exit(True);
  end;
  for mArg in AArgs do
  begin
    if SameText(mArg, '-' + cSwitchName) or SameText(mArg, '/' + cSwitchName) or SameText(mArg, '--' + cSwitchName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDpccSafeMode.KeyOf(const AText: string): TDpccStartupKey;
begin
  if SameText(AText, 'ctrl') then
  begin
    Result := TDpccStartupKey.Ctrl;
  end
  else if SameText(AText, 'none') then
  begin
    Result := TDpccStartupKey.None;
  end
  else
  begin
    Result := TDpccStartupKey.Shift;
  end;
end;

class function TDpccSafeMode.KeyText(AKey: TDpccStartupKey): string;
begin
  case AKey of
    TDpccStartupKey.Ctrl:
      Result := 'ctrl';
    TDpccStartupKey.None:
      Result := 'none';
  else
    Result := 'shift';
  end;
end;

class function TDpccSafeMode.SafeSession(const AToggles: TArray<TDpccQuickToggle>): TDpccToggleSession;
var
  mToggle: TDpccQuickToggle;
begin
  Result := Default(TDpccToggleSession);
  for mToggle in AToggles do
  begin
    Result.Put(mToggle.Key, False);
  end;
end;

class function TDpccSafeMode.Suggest(const AToggles: TArray<TDpccQuickToggle>; const AChangedKeys: TArray<string>;
  const ACrashed: TDpccSessionMarker): TArray<string>;
var
  mToggle: TDpccQuickToggle;
  mKey: string;
  mCandidates: TArray<TPair<string, Integer>>;
  mIndex, mOther: Integer;
  mSwap: TPair<string, Integer>;
begin
  Result := nil;
  // Zuerst, was zuletzt geändert wurde: das ist am ehesten die Ursache.
  for mKey in AChangedKeys do
  begin
    if TDpccQuickToggles.Find(AToggles, mKey, mToggle) and not MatchText(mToggle.Key, Result) then
    begin
      Result := Result + [mToggle.Key];
    end;
  end;
  // Dann Funktionen mit Fehlern in der abgestürzten Sitzung, die meisten zuerst; bei Gleichstand Katalog.
  mCandidates := nil;
  for mToggle in AToggles do
  begin
    if (mToggle.Feature <> '') and (ACrashed.FailureCount(mToggle.Feature) > 0) and
      not MatchText(mToggle.Key, Result) then
    begin
      mCandidates := mCandidates + [TPair<string, Integer>.Create(mToggle.Key, ACrashed.FailureCount(mToggle.Feature))];
    end;
  end;
  for mIndex := 1 to High(mCandidates) do
  begin
    mOther := mIndex;
    while (mOther > 0) and (mCandidates[mOther - 1].Value < mCandidates[mOther].Value) do
    begin
      mSwap := mCandidates[mOther - 1];
      mCandidates[mOther - 1] := mCandidates[mOther];
      mCandidates[mOther] := mSwap;
      Dec(mOther);
    end;
  end;
  for mIndex := 0 to High(mCandidates) do
  begin
    Result := Result + [mCandidates[mIndex].Key];
  end;
end;

function LineStamp(const ALine: string; out AStamp: TDateTime): Boolean;
var
  mYear, mMonth, mDay, mHour, mMinute, mSecond, mMilli: Integer;
begin
  AStamp := 0;
  Result := (Length(ALine) >= 23) and (ALine[5] = '-') and (ALine[8] = '-') and (ALine[11] = ' ') and
    (ALine[14] = ':') and (ALine[17] = ':') and (ALine[20] = '.') and
    TryStrToInt(Copy(ALine, 1, 4), mYear) and TryStrToInt(Copy(ALine, 6, 2), mMonth) and
    TryStrToInt(Copy(ALine, 9, 2), mDay) and TryStrToInt(Copy(ALine, 12, 2), mHour) and
    TryStrToInt(Copy(ALine, 15, 2), mMinute) and TryStrToInt(Copy(ALine, 18, 2), mSecond) and
    TryStrToInt(Copy(ALine, 21, 3), mMilli);
  if Result then
  begin
    Result := TryEncodeDateTime(mYear, mMonth, mDay, mHour, mMinute, mSecond, mMilli, AStamp);
  end;
end;

class function TDpccSafeMode.LogLinesBetween(const ALines: TArray<string>; AFrom, ATo: TDateTime;
  AMax: Integer): TArray<string>;
var
  mLine: string;
  mStamp: TDateTime;
  mInside: Boolean;
begin
  Result := nil;
  mInside := False;
  for mLine in ALines do
  begin
    if LineStamp(mLine, mStamp) then
    begin
      mInside := (mStamp >= AFrom) and ((ATo = 0) or (mStamp < ATo));
    end;
    if mInside then
    begin
      Result := Result + [mLine];
    end;
  end;
  if (AMax >= 0) and (Length(Result) > AMax) then
  begin
    Result := Copy(Result, Length(Result) - AMax, AMax);
  end;
end;

class function TDpccSafeMode.Details(const AMarker: TDpccSessionMarker): TArray<string>;
var
  mPair: TPair<string, Integer>;
  mNames: string;
begin
  Result := ['dpcc ' + AMarker.Version, 'Start: ' + DateToISO8601(AMarker.StartedAt, True)];
  if AMarker.Loaded then
  begin
    Result := Result + [Format(UiText(TSafeModeText.LoadingMs), [AMarker.LoadMs])];
  end
  else
  begin
    Result := Result + [UiText(TSafeModeText.LoadingNotFinished)];
  end;
  Result := Result + [UiText(TSafeModeText.Mode) + cLevelNames[AMarker.Level]];
  mNames := string.Join(', ', AMarker.Features);
  if mNames = '' then
  begin
    mNames := '–';
  end;
  Result := Result + [UiText(TSafeModeText.ActiveFeatures) + mNames];
  if Length(AMarker.Failures) = 0 then
  begin
    Result := Result + [UiText(TSafeModeText.ErrorsNone)];
  end
  else
  begin
    for mPair in AMarker.Failures do
    begin
      Result := Result + [Format(UiText(TSafeModeText.Errors), [mPair.Key, mPair.Value])];
    end;
  end;
end;

{ TDpccSessionFiles }

const
  cMarkerPrefix = 'session-';

/// <summary>
/// Ersetzt AFileName in einem Schritt: erst vollständig daneben schreiben, dann TFile.Replace
/// (unter Windows ReplaceFile). Früher erst löschen, dann umbenennen: Ein Absturz dazwischen ließ keine Marke
/// bzw. keinen Zustand zurück. Ohne TDpccDataFile, weil das über TDpccGuard protokolliert und Core.Diagnostics
/// Core.Files nicht verwenden darf (Feature-Zyklus). EInOutError, wenn die Datei nicht ersetzt wurde; sie bleibt
/// dann, wie sie war.
/// </summary>
procedure WriteFileSafely(const AFileName, AText: string);
var
  mTemp, mBackup: string;
begin
  ForceDirectories(ExtractFileDir(AFileName));
  mTemp := AFileName + '.tmp';
  // TFile.Replace braucht eine Sicherungsdatei, sobald das Ziel existiert.
  mBackup := AFileName + '.bak';
  TFile.WriteAllText(mTemp, AText, TEncoding.UTF8);
  try
    if TFile.Exists(AFileName) then
    begin
      TFile.Replace(mTemp, AFileName, mBackup);
    end
    else
    begin
      TFile.Move(mTemp, AFileName);
    end;
    // TFile.Replace meldet ein Scheitern von ReplaceFile nicht. Hat es das Ziel schon zur Sicherung umbenannt,
    // ohne die neue Datei nachzuschieben, gehört die vollständige neue an seine Stelle.
    if TFile.Exists(mTemp) and not TFile.Exists(AFileName) then
    begin
      TFile.Move(mTemp, AFileName);
    end;
    if TFile.Exists(mTemp) then
    begin
      raise EInOutError.Create('Datei des abgesicherten Starts nicht ersetzt');
    end;
  finally
    if TFile.Exists(mTemp) then
    begin
      TFile.Delete(mTemp);
    end;
    if TFile.Exists(mBackup) then
    begin
      TFile.Delete(mBackup);
    end;
  end;
end;

class function TDpccSessionFiles.MarkerFile(const AFolder: string; AProcessId: Cardinal): string;
begin
  Result := TPath.Combine(AFolder, cMarkerPrefix + UIntToStr(AProcessId) + '.json');
end;

class function TDpccSessionFiles.StateFile(const AFolder: string): string;
begin
  Result := TPath.Combine(AFolder, 'safemode.json');
end;

class procedure TDpccSessionFiles.WriteMarker(const AFolder: string; const AMarker: TDpccSessionMarker);
begin
  WriteFileSafely(MarkerFile(AFolder, AMarker.ProcessId), AMarker.ToJson);
end;

class procedure TDpccSessionFiles.DeleteMarker(const AFolder: string; AProcessId: Cardinal);
begin
  if TFile.Exists(MarkerFile(AFolder, AProcessId)) then
  begin
    TFile.Delete(MarkerFile(AFolder, AProcessId));
  end;
end;

class function TDpccSessionFiles.TakeCrashed(const AFolder: string; AOwnProcessId: Cardinal;
  const AAlive: TDpccProcessAlive): TArray<TDpccSessionMarker>;
var
  mFileName: string;
  mMarker: TDpccSessionMarker;
  mValid: Boolean;
begin
  Result := nil;
  if not TDirectory.Exists(AFolder) then
  begin
    Exit;
  end;
  for mFileName in TDirectory.GetFiles(AFolder, cMarkerPrefix + '*.json') do
  begin
    try
      mValid := TDpccSessionMarker.FromJson(TFile.ReadAllText(mFileName, TEncoding.UTF8), mMarker);
    except
      mValid := False;
    end;
    if mValid and (mMarker.ProcessId = AOwnProcessId) then
    begin
      Continue;
    end;
    if mValid and Assigned(AAlive) and AAlive(mMarker.ProcessId, mMarker.StartedAt) then
    begin
      Continue;
    end;
    if mValid then
    begin
      Result := Result + [mMarker];
    end;
    try
      TFile.Delete(mFileName);
    except
      // Gesperrt: beim nächsten Start noch einmal.
      on Exception do
        ;
    end;
  end;
end;

class function TDpccSessionFiles.ReadState(const AFolder: string): TDpccSafeState;
begin
  Result := Default(TDpccSafeState);
  try
    if TFile.Exists(StateFile(AFolder)) then
    begin
      Result := TDpccSafeState.FromJson(TFile.ReadAllText(StateFile(AFolder), TEncoding.UTF8));
    end;
  except
    on Exception do
      Result := Default(TDpccSafeState);
  end;
end;

class procedure TDpccSessionFiles.WriteState(const AFolder: string; const AState: TDpccSafeState);
begin
  WriteFileSafely(StateFile(AFolder), AState.ToJson);
end;

{ TDpccSessionBook }

class function TDpccSessionBook.Create(const AFolder: string; AProcessId: Cardinal;
  const ANoMarkerEnvironment: string): TDpccSessionBook;
begin
  Result.Folder := AFolder;
  Result.ProcessId := AProcessId;
  Result.Tracked := not TDpccSafeMode.IsSwitchOn(ANoMarkerEnvironment);
end;

procedure TDpccSessionBook.Open(const AAlive: TDpccProcessAlive; out AState: TDpccSafeState;
  out ACrashed: TArray<TDpccSessionMarker>);
begin
  AState := Default(TDpccSafeState);
  ACrashed := nil;
  if not Tracked then
  begin
    Exit;
  end;
  AState := TDpccSessionFiles.ReadState(Folder);
  ACrashed := TDpccSessionFiles.TakeCrashed(Folder, ProcessId, AAlive);
end;

procedure TDpccSessionBook.SaveState(const AState: TDpccSafeState);
begin
  if Tracked then
  begin
    TDpccSessionFiles.WriteState(Folder, AState);
  end;
end;

procedure TDpccSessionBook.SaveMarker(const AMarker: TDpccSessionMarker);
begin
  if Tracked then
  begin
    TDpccSessionFiles.WriteMarker(Folder, AMarker);
  end;
end;

procedure TDpccSessionBook.Close;
var
  mState: TDpccSafeState;
begin
  if not Tracked then
  begin
    Exit;
  end;
  TDpccSessionFiles.DeleteMarker(Folder, ProcessId);
  mState := TDpccSessionFiles.ReadState(Folder);
  TDpccSafeMode.CleanExit(mState);
  TDpccSessionFiles.WriteState(Folder, mState);
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Diagnostics.SafeMode', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
