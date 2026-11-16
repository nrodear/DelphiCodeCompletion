unit dpcc.IDE.CodeInsight.Manager.Paths;

// Protokoll des Code Insight-Managers: Diagnose = 1 (DWORD) in HKCU\Software\dpcc\IdePlugin protokolliert die Aufrufe
// der IDE in dpcc.IDE.Expert<Version>.log neben dem Plugin (Name der BPL bis 1.x).
// Pfad, Argumente und Betriebsart eines eigenen Server-Prozesses liest dpcc seit S1 nicht mehr: Der Server läuft nur
// noch im IDE-Prozess. Vorhandene Registry-Werte dazu bleiben unangetastet und werden ignoriert.

interface

type
  /// <summary>Pfad des Protokolls und Zeilen im Protokoll des Managers.</summary>
  TDpccCodeInsightPaths = record
  public
    /// <summary>Protokolldatei neben dem Plugin.</summary>
    class function DiagnoseLog: string; static;
    /// <summary>Diagnose = 1 (DWORD): Aufrufe der IDE und Ergebnisse in DiagnoseLog.</summary>
    class function DiagnoseEnabled: Boolean; static;
    /// <summary>Pfade und Benutzername aus einer Zeile des Diagnoselogs (#647); Meldungen wie
    /// „Datei nicht gefunden: C:\…“ dürfen so weitergegeben werden.</summary>
    class function WithoutPaths(const AText: string): string; static;
    /// <summary>Zeile mit Uhrzeit und ohne Pfade ins Protokoll; ein gesperrtes Protokoll stört die IDE nie.</summary>
    class procedure Append(const AMessage: string); static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.RegularExpressions,
  System.Win.Registry;

const
  cRegistryKey = 'Software\dpcc\IdePlugin';

/// <summary>Öffnet den Schlüssel der Einstellungen; liefert den geöffneten Schlüssel oder ''.</summary>
function OpenSettingsKey(ARegistry: TRegistry): string;
begin
  ARegistry.RootKey := HKEY_CURRENT_USER;
  if ARegistry.OpenKeyReadOnly(cRegistryKey) then
  begin
    Result := cRegistryKey;
  end
  else
  begin
    Result := '';
  end;
end;

class function TDpccCodeInsightPaths.DiagnoseEnabled: Boolean;
var
  mRegistry: TRegistry;
begin
  Result := False;
  mRegistry := TRegistry.Create(KEY_READ);
  try
    if (OpenSettingsKey(mRegistry) <> '') and mRegistry.ValueExists('Diagnose') and
      (mRegistry.GetDataType('Diagnose') = rdInteger) then
    begin
      Result := mRegistry.ReadInteger('Diagnose') <> 0;
    end;
  finally
    mRegistry.Free;
  end;
end;

class function TDpccCodeInsightPaths.DiagnoseLog: string;
const
  cBaseName = 'dpcc.IDE.Base';
  cLogName = 'dpcc.IDE.Expert';
var
  mModule, mName: string;
begin
  // Neben dem Plugin, nicht im Temp-Ordner: Den hat die IDE nicht in jedem Fall gemeinsam mit uns.
  mModule := GetModuleName(HInstance);
  mName := ChangeFileExt(ExtractFileName(mModule), '.log');
  // Der Name bleibt trotz neuem BPL-Namen (#1456): dpcc.IDE.Base370.bpl schreibt dpcc.IDE.Expert370.log.
  if SameText(Copy(mName, 1, Length(cBaseName)), cBaseName) then
  begin
    mName := cLogName + Copy(mName, Length(cBaseName) + 1, MaxInt);
  end;
  Result := ExtractFilePath(mModule) + mName;
end;

class function TDpccCodeInsightPaths.WithoutPaths(const AText: string): string;
var
  mUserName: string;
begin
  Result := TRegEx.Replace(AText, '(?:\b[A-Za-z]:|\\\\)[\\/]\S*|file:\S+|\S*\\\S*', '<pfad>');
  mUserName := GetEnvironmentVariable('USERNAME');
  if Length(mUserName) >= 3 then
  begin
    Result := StringReplace(Result, mUserName, '<benutzer>', [rfReplaceAll, rfIgnoreCase]);
  end;
end;

class procedure TDpccCodeInsightPaths.Append(const AMessage: string);
begin
  try
    TFile.AppendAllText(DiagnoseLog, FormatDateTime('hh":"nn":"ss.zzz', Now) + ' ' + WithoutPaths(AMessage) +
      sLineBreak, TEncoding.UTF8);
  except
    // Protokoll ist Beiwerk; ein gesperrtes Log darf die IDE nicht stören.
  end;
end;

end.
