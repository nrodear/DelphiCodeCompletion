unit dpcc.IDE.CodeInsight.Manager.Paths;

// Protokoll des Code Insight-Managers: Diagnose = 1 (DWORD) in HKCU\Software\dpcc\IdePlugin protokolliert die Aufrufe
// der IDE in dpcc.IDE.Expert<Version>.log neben dem Plugin (Name der BPL bis 1.x).
// Pfad, Argumente und Betriebsart eines eigenen Server-Prozesses liest dpcc seit S1 nicht mehr: Der Server läuft nur
// noch im IDE-Prozess. Vorhandene Registry-Werte dazu bleiben unangetastet und werden ignoriert.
// Schreiben (perf1): Append reiht die Zeile mit der Uhrzeit des Aufrufs beim Schreib-Thread ein
// (TDpccLogWriter.Shared); Pfade entfernen und Anhängen laufen dort, mehrere Zeilen gesammelt. Läuft er nicht, schreibt
// Append wie bisher selbst. Format und Datei bleiben gleich.
// Seit LOG1 schaltet derselbe Wert auch das Häkchen „Ablauf protokollieren (Log)“ der Seite dpcc
// (TDpccPluginSettings.Diagnose); wirksam ist zur Laufzeit TDpccFlow.Enabled (dpcc.Core.Diagnostics.Flow), das die
// Wurzel beim Anmelden und nach OK setzt. DiagnoseEnabled liest die Registry selbst (Wächter beim Anmelden). Weil das
// Ablaufprotokoll viele Zeilen schreibt, ist die Datei begrenzt wie dpcc.log: ab 1 MB rotiert sie
// (dpcc.IDE.Expert<Version>.1.log … .4.log, höchstens 5 Dateien); scheitert das Rotieren, wird weiter angehängt.

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
  System.Win.Registry,
  dpcc.Core.Diagnostics.LogWriter;

const
  cRegistryKey = 'Software\dpcc\IdePlugin';
  /// <summary>Ab dieser Größe rotiert das Diagnoseprotokoll (wie dpcc.log, TDpccRotatingLog).</summary>
  cMaxLogBytes = 1024 * 1024;
  /// <summary>Höchstens so viele Dateien samt der aktuellen.</summary>
  cMaxLogFiles = 5;

type
  /// <summary>Diagnoselog als Ziel des Schreib-Threads (perf1).</summary>
  TDiagnoseTarget = class(TInterfacedObject, IDpccLogTarget)
  public
    procedure WriteLines(const ALines: TArray<TDpccLogLine>);
  end;

var
  // Ziel für Append; lebt bis zur Finalisierung (eingereihte Zeilen halten es selbst).
  DiagnoseTarget: IDpccLogTarget;

/// <summary>Ältere Datei Nummer AIndex zu ALog: dpcc.IDE.Expert370.log → dpcc.IDE.Expert370.1.log.</summary>
function RotatedLog(const ALog: string; AIndex: Integer): string;
begin
  Result := ChangeFileExt(ALog, Format('.%d.log', [AIndex]));
end;

/// <summary>Hat ALog cMaxLogBytes erreicht: ALog → .1 → … → .(cMaxLogFiles - 1), die älteste fällt weg. Ein Fehler
/// (Datei in einer anderen IDE offen) bleibt still; dann wird weiter angehängt.</summary>
procedure RotateIfFull(const ALog: string);
var
  mIndex: Integer;
  mOlder, mNewer: string;
begin
  try
    if not TFile.Exists(ALog) or (TFile.GetSize(ALog) < cMaxLogBytes) then
    begin
      Exit;
    end;
    for mIndex := cMaxLogFiles - 1 downto 1 do
    begin
      mOlder := RotatedLog(ALog, mIndex);
      if mIndex = 1 then
      begin
        mNewer := ALog;
      end
      else
      begin
        mNewer := RotatedLog(ALog, mIndex - 1);
      end;
      if TFile.Exists(mOlder) then
      begin
        TFile.Delete(mOlder);
      end;
      if TFile.Exists(mNewer) then
      begin
        TFile.Move(mNewer, mOlder);
      end;
    end;
  except
    // Rotieren ist Beiwerk wie das Protokoll selbst.
  end;
end;

/// <summary>ALines mit Uhrzeit des Aufrufs und ohne Pfade an einem Stück anhängen; ein gesperrtes Protokoll stört
/// nie. Vorher rotiert eine volle Datei (LOG1).</summary>
procedure WriteDiagnose(const ALines: TArray<TDpccLogLine>);
var
  mBuilder: TStringBuilder;
  mLine: TDpccLogLine;
begin
  try
    RotateIfFull(TDpccCodeInsightPaths.DiagnoseLog);
    mBuilder := TStringBuilder.Create;
    try
      for mLine in ALines do
      begin
        mBuilder.Append(FormatDateTime('hh":"nn":"ss.zzz', mLine.Stamp)).Append(' ')
          .Append(TDpccCodeInsightPaths.WithoutPaths(mLine.Text)).Append(sLineBreak);
      end;
      TFile.AppendAllText(TDpccCodeInsightPaths.DiagnoseLog, mBuilder.ToString, TEncoding.UTF8);
    finally
      mBuilder.Free;
    end;
  except
    // Protokoll ist Beiwerk; ein gesperrtes Log darf die IDE nicht stören.
  end;
end;

procedure TDiagnoseTarget.WriteLines(const ALines: TArray<TDpccLogLine>);
begin
  WriteDiagnose(ALines);
end;

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
var
  mLine: TDpccLogLine;
  mWriter: TDpccLogWriter;
  mTarget: IDpccLogTarget;
begin
  // Uhrzeit jetzt; Pfade entfernen und Schreiben im Schreib-Thread.
  mLine := TDpccLogLine.Create(AMessage);
  mWriter := TDpccLogWriter.Shared;
  mTarget := DiagnoseTarget;
  if (mWriter <> nil) and (mTarget <> nil) and mWriter.Enqueue(mTarget, mLine) then
  begin
    Exit;
  end;
  WriteDiagnose(TArray<TDpccLogLine>.Create(mLine));
end;

initialization
  DiagnoseTarget := TDiagnoseTarget.Create;

finalization
  DiagnoseTarget := nil;

end.
