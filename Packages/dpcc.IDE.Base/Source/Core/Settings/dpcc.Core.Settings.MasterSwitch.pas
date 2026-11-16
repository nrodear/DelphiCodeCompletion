unit dpcc.Core.Settings.MasterSwitch;

// Hauptschalter (#407, completion.enabled) ohne Neustart der IDE: merkt den zuletzt gesehenen Stand und meldet, ob
// eine Änderung der Einstellungen ihn umgeschaltet hat. Die Kompositionswurzel (dpcc.IDE.Completion.Register) fragt
// nach jeder Änderung (TDpccIdeSettings.OnChanged) und lässt den Code Insight-Manager reagieren:
//   - an: Sitzung und Server starten, falls sie nicht laufen (sonst käme der Start erst mit der ersten Anfrage);
//   - aus: offene Liste, Parameter-Hint und Tooltip von dpcc schließen; die eingebaute Code Insight übernimmt,
//     weil HandlesFile den Schalter bei jedem Aufruf liest. Der Server läuft weiter (siehe Manager).
// Ohne IDE und ohne Registry, damit testbar.

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Was eine Änderung der Einstellungen am Hauptschalter bewirkt hat.</summary>
  TDpccMasterSwitchChange = (None, TurnedOn, TurnedOff);

  /// <summary>Zuletzt gesehener Stand des Hauptschalters.</summary>
  TDpccMasterSwitch = record
  private
    FKnown: Boolean;
    FEnabled: Boolean;
  public
    /// <summary>Stand beim Anmelden; danach zählt nur, was sich gegenüber AEnabled ändert.</summary>
    procedure Reset(AEnabled: Boolean);
    /// <summary>Neuer Stand nach einer Änderung der Einstellungen. Ohne vorheriges Reset gilt der erste Stand als
    /// bekannt (None).</summary>
    function Update(AEnabled: Boolean): TDpccMasterSwitchChange;
    /// <summary>Zuletzt gesehener Stand (False ohne Reset und Update).</summary>
    function Enabled: Boolean;
  end;

{$SCOPEDENUMS OFF}

implementation

{ TDpccMasterSwitch }

procedure TDpccMasterSwitch.Reset(AEnabled: Boolean);
begin
  FKnown := True;
  FEnabled := AEnabled;
end;

function TDpccMasterSwitch.Update(AEnabled: Boolean): TDpccMasterSwitchChange;
begin
  Result := TDpccMasterSwitchChange.None;
  if FKnown and (AEnabled <> FEnabled) then
  begin
    if AEnabled then
    begin
      Result := TDpccMasterSwitchChange.TurnedOn;
    end
    else
    begin
      Result := TDpccMasterSwitchChange.TurnedOff;
    end;
  end;
  Reset(AEnabled);
end;

function TDpccMasterSwitch.Enabled: Boolean;
begin
  Result := FEnabled;
end;

end.
