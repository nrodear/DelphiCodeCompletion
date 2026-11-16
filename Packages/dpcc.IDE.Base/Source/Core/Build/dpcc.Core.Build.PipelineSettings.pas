unit dpcc.Core.Build.PipelineSettings;

// Werte der Einstellungen der Build-Pipeline (#529, #533, #1455), ohne VCL und
// Open Tools API: build.gate, build.gateTimeoutMs, build.releaseConfigs und
// build.releaseChecks. Base: Einstellungen und Optionsdialog lesen und
// schreiben sie, auch ohne das Modul dpcc.buildpipeline; Prüfung vor dem
// Kompilieren und Release-Wächter (Modul) werten sie aus.
// Textform von build.releaseChecks: durch Komma getrennt „name“ (an), „-name“
// (aus), mit Sollwert „name=off“ bzw. „name=on“ (auch „-name=on“). Fehlende
// Namen gelten mit ihrer Vorgabe (alle an, Sollwerte aus); unbekannte
// entfallen. Normalized schreibt alle in fester Reihenfolge.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  /// <summary>Einzeln abschaltbare Prüfung (build.releaseChecks).</summary>
  TDpccReleaseCheck = (DebugDefine, DebugInfo, StackFrames, Assertions, RangeChecks, OverflowChecks, MemoryLeaks,
    VersionInfo, OutputFolder);
  /// <summary>build.gate (#529): off und warn melden nur, block bricht den Build ab.</summary>
  TDpccBuildGate = (Off, Warn, Block);
{$SCOPEDENUMS OFF}

  TDpccReleaseCheckSetting = record
    Enabled: Boolean;
    /// <summary>Sollwert der Compileroption (nur für Prüfungen mit Sollwert): True = an.</summary>
    Expected: Boolean;
  end;

  TDpccReleaseChecks = record
    Items: array[TDpccReleaseCheck] of TDpccReleaseCheckSetting;
    /// <summary>Alle an, Sollwerte aus.</summary>
    class function Defaults: TDpccReleaseChecks; static;
    /// <summary>Liest die Textform (siehe Kopf); fehlende Namen mit Vorgabe, unbekannte entfallen.</summary>
    class function Parse(const AText: string): TDpccReleaseChecks; static;
    /// <summary>Textform in fester Reihenfolge mit allen Prüfungen.</summary>
    function ToText: string;
    /// <summary>Parse und ToText in einem: einheitliche Schreibweise für die Ablage.</summary>
    class function Normalized(const AText: string): string; static;
  end;

  TDpccBuildPipelineSettings = class
  public const
    cReleaseConfiguration = 'Release';
    cCheckNames: array[TDpccReleaseCheck] of string = ('debugDefine', 'debugInfo', 'stackFrames', 'assertions',
      'rangeChecks', 'overflowChecks', 'memoryLeaks', 'versionInfo', 'outputFolder');
    /// <summary>Prüfungen mit Sollwert (Compileroptionen).</summary>
    cHasTarget: array[TDpccReleaseCheck] of Boolean = (False, True, True, True, True, True, False, False, False);
    cGateNames: array[TDpccBuildGate] of string = ('off', 'warn', 'block');
    /// <summary>build.gateTimeoutMs: Vorgabe und Grenzen.</summary>
    cGateDefaultTimeoutMs = 300;
    cGateMinTimeoutMs = 50;
    cGateMaxTimeoutMs = 10000;
  public
    /// <summary>"off", "warn" oder "block" (Groß-/Kleinschreibung egal); sonst off.</summary>
    class function GateOf(const AText: string): TDpccBuildGate; static;
    /// <summary>Konfigurationen durch Komma oder Semikolon getrennt, ohne Leere und Doppelte; Schreibweise der
    /// ersten Nennung.</summary>
    class function ConfigurationList(const AText: string): TArray<string>; static;
    /// <summary>Einheitliche Schreibweise von build.releaseConfigs: Liste durch ", " getrennt.</summary>
    class function NormalizedConfigurations(const AText: string): string; static;
  end;

implementation

{ TDpccReleaseChecks }

class function TDpccReleaseChecks.Defaults: TDpccReleaseChecks;
var
  mCheck: TDpccReleaseCheck;
begin
  for mCheck := Low(TDpccReleaseCheck) to High(TDpccReleaseCheck) do
  begin
    Result.Items[mCheck].Enabled := True;
    Result.Items[mCheck].Expected := False;
  end;
end;

function CheckOf(const AName: string; out ACheck: TDpccReleaseCheck): Boolean;
var
  mCheck: TDpccReleaseCheck;
begin
  for mCheck := Low(TDpccReleaseCheck) to High(TDpccReleaseCheck) do
  begin
    if SameText(AName, TDpccBuildPipelineSettings.cCheckNames[mCheck]) then
    begin
      ACheck := mCheck;
      Exit(True);
    end;
  end;
  ACheck := TDpccReleaseCheck.DebugDefine;
  Result := False;
end;

class function TDpccReleaseChecks.Parse(const AText: string): TDpccReleaseChecks;
var
  mPart, mName, mTarget: string;
  mEnabled: Boolean;
  mEquals: Integer;
  mCheck: TDpccReleaseCheck;
begin
  Result := Defaults;
  for mPart in AText.Split([',', ';']) do
  begin
    mName := Trim(mPart);
    mEnabled := True;
    if mName.StartsWith('-') or mName.StartsWith('!') then
    begin
      mEnabled := False;
      mName := Trim(Copy(mName, 2, MaxInt));
    end;
    mTarget := '';
    mEquals := Pos('=', mName);
    if mEquals > 0 then
    begin
      mTarget := Trim(Copy(mName, mEquals + 1, MaxInt));
      mName := Trim(Copy(mName, 1, mEquals - 1));
    end;
    if not CheckOf(mName, mCheck) then
    begin
      Continue;
    end;
    Result.Items[mCheck].Enabled := mEnabled;
    if TDpccBuildPipelineSettings.cHasTarget[mCheck] and (mTarget <> '') then
    begin
      Result.Items[mCheck].Expected := SameText(mTarget, 'on') or SameText(mTarget, 'true') or (mTarget = '1');
    end;
  end;
end;

function TDpccReleaseChecks.ToText: string;
const
  cTargets: array[Boolean] of string = ('=off', '=on');
var
  mCheck: TDpccReleaseCheck;
  mItem: string;
begin
  Result := '';
  for mCheck := Low(TDpccReleaseCheck) to High(TDpccReleaseCheck) do
  begin
    mItem := TDpccBuildPipelineSettings.cCheckNames[mCheck];
    if not Items[mCheck].Enabled then
    begin
      mItem := '-' + mItem;
    end;
    if TDpccBuildPipelineSettings.cHasTarget[mCheck] then
    begin
      mItem := mItem + cTargets[Items[mCheck].Expected];
    end;
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mItem;
  end;
end;

class function TDpccReleaseChecks.Normalized(const AText: string): string;
begin
  Result := Parse(AText).ToText;
end;

class function TDpccBuildPipelineSettings.GateOf(const AText: string): TDpccBuildGate;
var
  mGate: TDpccBuildGate;
begin
  for mGate := Low(TDpccBuildGate) to High(TDpccBuildGate) do
  begin
    if SameText(Trim(AText), cGateNames[mGate]) then
    begin
      Exit(mGate);
    end;
  end;
  Result := TDpccBuildGate.Off;
end;

class function TDpccBuildPipelineSettings.ConfigurationList(const AText: string): TArray<string>;
var
  mPart, mName, mKnown: string;
  mSeen: Boolean;
begin
  Result := nil;
  for mPart in AText.Split([',', ';']) do
  begin
    mName := Trim(mPart);
    // JSON-artige Eingabe ["Release", "Ship"] verträgt die Liste auch.
    mName := Trim(StringReplace(StringReplace(StringReplace(mName, '"', '', [rfReplaceAll]), '[', '',
      [rfReplaceAll]), ']', '', [rfReplaceAll]));
    if mName = '' then
    begin
      Continue;
    end;
    mSeen := False;
    for mKnown in Result do
    begin
      if SameText(mKnown, mName) then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mName];
    end;
  end;
end;

class function TDpccBuildPipelineSettings.NormalizedConfigurations(const AText: string): string;
begin
  Result := string.Join(', ', ConfigurationList(AText));
end;

end.
