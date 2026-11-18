unit dpcc.Core.Settings.Plugin.Store;

// Ablage der Plugin-Einstellungen (#227): Lese- und Schreibschnittstelle und der gemeinsame Weg von Laden und
// Speichern (TDpccSettingsExchange). Seit OPT2 ohne die Hilfen der entfernten Bereiche (Tracker-Texte,
// Aufgaben vor dem Build, Lesezeichen, Methodenreihenfolge) und ohne IDpccSettingsNames (Übernahme umbenannter
// Registry-Namen, die nur entfernte Einstellungen betraf).

interface

type
  /// <summary>Ablage für Einstellungen; Werte als ganze Zahlen (Wahrheitswerte 0/1).</summary>
  IDpccSettingsStore = interface
    ['{4C8E2A17-9B3D-4F61-A5E2-7D0C1B9F3E84}']
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

  /// <summary>Liest oder schreibt Einstellungen über eine Ablage: Laden und Speichern gehen über dieselbe Liste
  /// (TDpccPluginSettings.Exchange), damit Name und Art jedes Werts nur einmal stehen.</summary>
  TDpccSettingsExchange = record
  private
    FStore: IDpccSettingsStore;
    FWriting: Boolean;
  public
    /// <summary>Liest; fehlt ein Wert in AStore, bleibt der bisherige (die Vorgabe).</summary>
    class function Reader(const AStore: IDpccSettingsStore): TDpccSettingsExchange; static;
    /// <summary>Schreibt jeden Wert nach AStore.</summary>
    class function Writer(const AStore: IDpccSettingsStore): TDpccSettingsExchange; static;
    /// <summary>Wahrheitswert unter AName (abgelegt als 0/1).</summary>
    procedure Flag(const AName: string; var AValue: Boolean);
    /// <summary>Ganze Zahl unter AName.</summary>
    procedure Number(const AName: string; var AValue: Integer);
    /// <summary>Text unter AName.</summary>
    procedure Text(const AName: string; var AValue: string);
  end;

/// <summary>AValue, wenn er (ohne Groß-/Kleinschreibung) unter AAllowed steht, in deren Schreibweise;
/// sonst der erste erlaubte Wert.</summary>
function Choice(const AValue: string; const AAllowed: array of string): string;
/// <summary>1 für True, 0 für False (Ablage der Wahrheitswerte).</summary>
function BoolValue(AValue: Boolean): Integer;

implementation

uses
  System.SysUtils;

function Choice(const AValue: string; const AAllowed: array of string): string;
var
  mItem: string;
begin
  for mItem in AAllowed do
  begin
    if SameText(Trim(AValue), mItem) then
    begin
      Exit(mItem);
    end;
  end;
  Result := AAllowed[0];
end;

function BoolValue(AValue: Boolean): Integer;
begin
  if AValue then
  begin
    Result := 1;
  end
  else
  begin
    Result := 0;
  end;
end;

{ TDpccSettingsExchange }

class function TDpccSettingsExchange.Reader(const AStore: IDpccSettingsStore): TDpccSettingsExchange;
begin
  Result.FStore := AStore;
  Result.FWriting := False;
end;

class function TDpccSettingsExchange.Writer(const AStore: IDpccSettingsStore): TDpccSettingsExchange;
begin
  Result.FStore := AStore;
  Result.FWriting := True;
end;

procedure TDpccSettingsExchange.Flag(const AName: string; var AValue: Boolean);
begin
  if FWriting then
  begin
    FStore.WriteInteger(AName, BoolValue(AValue));
  end
  else
  begin
    AValue := FStore.ReadInteger(AName, BoolValue(AValue)) <> 0;
  end;
end;

procedure TDpccSettingsExchange.Number(const AName: string; var AValue: Integer);
begin
  if FWriting then
  begin
    FStore.WriteInteger(AName, AValue);
  end
  else
  begin
    AValue := FStore.ReadInteger(AName, AValue);
  end;
end;

procedure TDpccSettingsExchange.Text(const AName: string; var AValue: string);
begin
  if FWriting then
  begin
    FStore.WriteString(AName, AValue);
  end
  else
  begin
    AValue := FStore.ReadString(AName, AValue);
  end;
end;

end.
