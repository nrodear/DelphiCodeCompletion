unit dpcc.Core.Diagnostics.Teardown;

// Abbau beim Entladen in Schritten (#886): Jeder Schritt läuft für sich; eine
// Ausnahme bricht den Abbau nicht ab. Früher endete Unregister beim ersten
// Fehler, etwa wenn die IDE dpcc mitten im Gruppen-Build entlud. Dann blieben
// Notifier, Fenster-Hooks und Ereignisse der alten Instanz angemeldet, und die
// IDE stürzte beim Beenden in fremdem Speicher ab; „dpcc entladen“ fehlte im
// Protokoll. Festgehalten werden nur Schritt und Ausnahmeklasse, nie der
// Meldungstext, weil er Pfade enthalten kann (anonymes Protokoll).

interface

uses
  System.SysUtils;

type
  TDpccTeardown = record
  private
    FFailures: TArray<string>;
  public
    /// <summary>Leerer Abbau ohne Fehler.</summary>
    class function Create: TDpccTeardown; static;
    /// <summary>AStep ausführen; eine Ausnahme wird als „AName: Klasse“ vermerkt und nicht weitergereicht.</summary>
    procedure Step(const AName: string; const AStep: TProc);
    /// <summary>Fehler eines anderen Abbaus (etwa der Feature-Tabelle) übernehmen.</summary>
    procedure AddFailures(const AFailures: TArray<string>);
    /// <summary>Fehlgeschlagene Schritte in Reihenfolge, je „Name: Klasse“.</summary>
    function Failures: TArray<string>;
    /// <summary>„keine“ bzw. die fehlgeschlagenen Schritte mit Komma getrennt.</summary>
    function Summary: string;
  end;

implementation

{ TDpccTeardown }

class function TDpccTeardown.Create: TDpccTeardown;
begin
  Result.FFailures := nil;
end;

procedure TDpccTeardown.Step(const AName: string; const AStep: TProc);
begin
  try
    if Assigned(AStep) then
    begin
      AStep();
    end;
  except
    on E: Exception do
      FFailures := FFailures + [AName + ': ' + E.ClassName];
  end;
end;

procedure TDpccTeardown.AddFailures(const AFailures: TArray<string>);
begin
  FFailures := FFailures + AFailures;
end;

function TDpccTeardown.Failures: TArray<string>;
begin
  Result := FFailures;
end;

function TDpccTeardown.Summary: string;
begin
  if Length(FFailures) = 0 then
  begin
    Result := 'keine';
  end
  else
  begin
    Result := string.Join(', ', FFailures);
  end;
end;

end.
