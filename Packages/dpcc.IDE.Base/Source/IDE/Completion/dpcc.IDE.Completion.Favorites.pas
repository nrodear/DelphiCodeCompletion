unit dpcc.IDE.Completion.Favorites;

// Angeheftete Favoriten (#458) für die IDE: eine Instanz für das ganze Plugin, gelesen aus
// %APPDATA%\dpcc\favorites.json beim ersten Zugriff (neben usage.json der lernenden Gewichtung, #418) und
// nach jeder Änderung sofort gespeichert, damit ein Absturz der IDE keinen Favoriten kostet. Eine unbrauchbare
// Datei legt TDpccDataFile als favorites.json.defekt beiseite, eine gesperrte bleibt unverändert. Die
// Einstellungsseite listet und entfernt sie über Items und Remove. Andere Teile des Plugins (etwa der Reiter
// „Gemerkt“ der Willkommensseite, #755) lesen die Datei über FileName und TDpccFavorites.LoadFromFile, ohne
// Server.

interface

uses
  dpcc.Core.Completion.Favorites;

type
  TDpccIdeFavorites = class
  private class var
    FFavorites: TDpccFavorites;
  public
    /// <summary>%APPDATA%\dpcc\favorites.json.</summary>
    class function FileName: string; static;
    class function Instance: TDpccFavorites; static;
    /// <summary>Speichert, wenn sich etwas geändert hat; Fehler stören die IDE nie.</summary>
    class procedure Save; static;
    /// <summary>Alle Favoriten in der Reihenfolge des Anheftens.</summary>
    class function Items: TArray<TDpccFavorite>; static;
    /// <summary>Löst die Favoriten mit den Schlüsseln AKeys und speichert.</summary>
    class procedure Remove(const AKeys: TArray<string>); static;
    class procedure Release; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  dpcc.Core.Files.DataFile;

{ TDpccIdeFavorites }

class function TDpccIdeFavorites.FileName: string;
begin
  Result := TPath.Combine(TPath.Combine(TPath.GetHomePath, 'dpcc'), 'favorites.json');
end;

class function TDpccIdeFavorites.Instance: TDpccFavorites;
begin
  if FFavorites = nil then
  begin
    FFavorites := TDpccFavorites.Create;
    // Fehlt, unbrauchbar oder gesperrt: leer beginnen; TDpccDataFile legt Unbrauchbares beiseite und
    // protokolliert, eine gesperrte Datei schreibt Save nicht.
    FFavorites.LoadFromFile(FileName);
  end;
  Result := FFavorites;
end;

class procedure TDpccIdeFavorites.Save;
begin
  if (FFavorites = nil) or not FFavorites.Changed then
  begin
    Exit;
  end;
  try
    FFavorites.SaveToFile(FileName);
  except
    // Speichern darf die IDE nie stören; der Grund steht einmal im Protokoll, Changed bleibt gesetzt.
    on E: Exception do
      TDpccDataFile.ReportNotWritten('Favoriten', E);
  end;
end;

class function TDpccIdeFavorites.Items: TArray<TDpccFavorite>;
begin
  Result := Instance.Items;
end;

class procedure TDpccIdeFavorites.Remove(const AKeys: TArray<string>);
var
  mKey: string;
begin
  for mKey in AKeys do
  begin
    Instance.Remove(mKey);
  end;
  Save;
end;

class procedure TDpccIdeFavorites.Release;
begin
  Save;
  FreeAndNil(FFavorites);
end;

end.
