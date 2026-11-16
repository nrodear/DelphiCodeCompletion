unit dpcc.IDE.Completion.History;

// Verlauf der lernenden Gewichtung (#418) für die IDE: eine Instanz für das
// ganze Plugin, gelesen aus %APPDATA%\dpcc\usage.json beim ersten Zugriff,
// gespeichert alle paar Übernahmen und beim Entladen. „Verlauf zurücksetzen“
// auf der Optionsseite leert ihn sofort.

interface

uses
  dpcc.Core.Completion.Usage;

type
  TDpccIdeHistory = class
  private class var
    FUsage: TDpccUsage;
    FCommits: Integer;
  public
    class function FileName: string; static;
    class function Instance: TDpccUsage; static;
    /// <summary>Nach einer Übernahme: alle 10 Übernahmen speichern.</summary>
    class procedure Committed; static;
    class procedure Save; static;
    class procedure Reset; static;
    class procedure Release; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  dpcc.Core.Files.DataFile;

{ TDpccIdeHistory }

class function TDpccIdeHistory.FileName: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'dpcc'), 'usage.json');
end;

class function TDpccIdeHistory.Instance: TDpccUsage;
begin
  if FUsage = nil then
  begin
    FUsage := TDpccUsage.Create;
    // Fehlt, unbrauchbar oder gesperrt: leer beginnen; TDpccDataFile legt Unbrauchbares beiseite und
    // protokolliert, eine gesperrte Datei schreibt Save nicht.
    FUsage.LoadFromFile(FileName);
  end;
  Result := FUsage;
end;

class procedure TDpccIdeHistory.Committed;
begin
  Inc(FCommits);
  if FCommits mod 10 = 0 then
  begin
    Save;
  end;
end;

class procedure TDpccIdeHistory.Save;
begin
  if (FUsage = nil) or not FUsage.Changed then
  begin
    Exit;
  end;
  try
    FUsage.SaveToFile(FileName);
  except
    // Speichern darf die IDE nie stören; der Grund steht einmal im Protokoll, Changed bleibt gesetzt.
    on E: Exception do
      TDpccDataFile.ReportNotWritten('Lernende Gewichtung', E);
  end;
end;

class procedure TDpccIdeHistory.Reset;
begin
  Instance.Clear;
  Save;
end;

class procedure TDpccIdeHistory.Release;
begin
  Save;
  FreeAndNil(FUsage);
end;

end.
