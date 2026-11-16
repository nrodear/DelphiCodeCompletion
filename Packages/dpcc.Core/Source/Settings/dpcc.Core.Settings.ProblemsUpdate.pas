unit dpcc.Core.Settings.ProblemsUpdate;

// Werte der Einstellungen problems.update (live, save, manual) und
// problems.liveDelayMs (100 bis 10000 ms), ohne VCL und Open Tools API.
// Vor problems.update gab es nur problems.live (an = live, aus = save).
// Wann geprüft wird, entscheidet dpcc.Core.Problems.Refresh.

interface

type
  {$SCOPEDENUMS ON}
  TDpccProblemsUpdate = (Live, Save, Manual);
  {$SCOPEDENUMS OFF}

  TDpccProblemsUpdateSetting = record
  public const
    cDefaultDelayMs = 400;
    cMinDelayMs = 100;
    cMaxDelayMs = 10000;
    /// <summary>Werte von problems.update in der Reihenfolge von TDpccProblemsUpdate.</summary>
    cValues: array[TDpccProblemsUpdate] of string = ('live', 'save', 'manual');
  public
    /// <summary>Art zu AValue (Groß-/Kleinschreibung egal); Unbekanntes = live.</summary>
    class function Parse(const AValue: string): TDpccProblemsUpdate; static;
    /// <summary>Text zu AMode, wie er in den Einstellungen steht.</summary>
    class function Name(AMode: TDpccProblemsUpdate): string; static;
    /// <summary>AValue als gültiger Wert von problems.update; Unbekanntes = live.</summary>
    class function Normalize(const AValue: string): string; static;
    /// <summary>Wert von problems.update aus dem früheren problems.live (#909): an = live, aus = save.</summary>
    class function FromLive(ALive: Boolean): string; static;
    /// <summary>Verzögerung auf 100 bis 10000 ms begrenzt.</summary>
    class function ClampDelay(ADelayMs: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TDpccProblemsUpdateSetting }

class function TDpccProblemsUpdateSetting.Parse(const AValue: string): TDpccProblemsUpdate;
var
  mMode: TDpccProblemsUpdate;
begin
  for mMode := Low(TDpccProblemsUpdate) to High(TDpccProblemsUpdate) do
  begin
    if SameText(Trim(AValue), cValues[mMode]) then
    begin
      Exit(mMode);
    end;
  end;
  Result := TDpccProblemsUpdate.Live;
end;

class function TDpccProblemsUpdateSetting.Name(AMode: TDpccProblemsUpdate): string;
begin
  Result := cValues[AMode];
end;

class function TDpccProblemsUpdateSetting.Normalize(const AValue: string): string;
begin
  Result := Name(Parse(AValue));
end;

class function TDpccProblemsUpdateSetting.FromLive(ALive: Boolean): string;
begin
  if ALive then
  begin
    Result := Name(TDpccProblemsUpdate.Live);
  end
  else
  begin
    Result := Name(TDpccProblemsUpdate.Save);
  end;
end;

class function TDpccProblemsUpdateSetting.ClampDelay(ADelayMs: Integer): Integer;
begin
  Result := EnsureRange(ADelayMs, cMinDelayMs, cMaxDelayMs);
end;

end.
