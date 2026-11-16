unit dpcc.IDE.Foundation.TeamFile;

// Projektdatei .dpcc des aktiven Projekts (#486) für alle Teile des Plugins.
// Foundation: nur Open Tools API, VCL-Zeitgeber und dpcc.Core; Lesen
// und Prüfen in dpcc.Core.Settings.TeamFile.
// - Current: gelesener Stand für das aktive Projekt; ohne Projekt, ohne Datei,
//   mit ausgeschalteter Einstellung TeamFile oder vor Start leer (Empty). Eine
//   fehlerhafte Datei ergibt Valid = False: Es gelten die persönlichen
//   Einstellungen.
// - Ort: TDpccTeamFile.Locate mit dem Ordner der .dproj und dem der
//   geöffneten .groupproj (LocateFor).
// - Ein Zeitgeber prüft alle 2 s im Hauptthread, ob sich aktives Projekt,
//   Ort oder Zeitstempel der Datei geändert haben; nur dann wird neu gelesen
//   und die Version erhöht. Den Ort sucht er (Ordner aufwärts bis zur Wurzel
//   des Repositorys) nur bei anderem Projekt oder anderer Gruppe, nach
//   Refresh, wenn die Datei verschwunden ist, und sonst alle 10 s; je Takt
//   fragt er nur den Zeitstempel der Datei (Dateizugriffe im Hauptthread). Ist die Datei gerade gesperrt, folgt der
//   nächste
//   Versuch beim nächsten Takt.
// - Meldungen zur Datei (fehlerhaft, Zugangsdaten, absolute Pfade …) stehen
//   einmal je gelesenem Stand in der Meldungsansicht (Gruppe dpcc), nie als
//   Dialog und nicht im Protokoll (sie nennen Einträge der Datei).
// - ForProject: Stand für eine beliebige .dproj ohne Meldungen (etwa für die
//   Willkommensseite: Build-Server #763, Tracker #765, Startprofile #764).
// - Version zählt jeden neu gelesenen Stand (für Zwischenspeicher wie die
//   ausgeblendeten Stellen, #628).
// - OpenInEditor: legt die Datei mit Gerüst (TDpccTeamFile.Skeleton, UTF-8
//   ohne BOM) neben der .dproj an, wenn es noch keine gibt, und öffnet sie.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.ExtCtrls,
  dpcc.Core.Settings.TeamFile;

type
  TDpccIdeTeamFile = class
  private class var
    FInstance: TDpccIdeTeamFile;
    FVersion: Integer;
  private
    FTimer: TTimer;
    FCurrent: TDpccTeamSettings;
    FStamp: string;
    /// <summary>Projekt und Gruppe der letzten Suche nach dem Ort, ihr Ergebnis und Zeitpunkt.</summary>
    FLocateKey: string;
    FLocated: string;
    FLocatedAt: UInt64;
    procedure Tick(Sender: TObject);
    /// <summary>Ort der Datei für AProject; sucht nur neu, wenn nötig (siehe Kopf).</summary>
    function LocatedFor(const AProject: string): string;
    procedure Check;
    class function PathExists(const APath: string): Boolean; static;
    /// <summary>Liest AFileName; False, wenn die Datei nicht lesbar ist (gesperrt, gelöscht).</summary>
    class function Load(const AFileName: string; out ATeam: TDpccTeamSettings): Boolean; static;
    class procedure Report(const ATeam: TDpccTeamSettings); static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Gilt die .dpcc (Hauptschalter und Einstellung TeamFile)? Nur im Hauptthread.</summary>
    class function Wanted: Boolean; static;
    /// <summary>Zeitgeber anlegen und gleich prüfen (Feature TeamFile).</summary>
    class procedure Start; static;
    class procedure Stop; static;
    class function Started: Boolean; static;
    /// <summary>Stand für das aktive Projekt (siehe Kopf).</summary>
    class function Current: TDpccTeamSettings; static;
    /// <summary>Zählt jeden neu gelesenen Stand von Current (auch Start und Stop).</summary>
    class function Version: Integer; static;
    /// <summary>Stand für AProject (.dproj) ohne Meldungen; leer, wenn die Einstellung TeamFile aus ist.</summary>
    class function ForProject(const AProject: string): TDpccTeamSettings; static;
    /// <summary>Wie ForProject, aber auch bei ausgeschalteter Einstellung (Anzeige auf der Optionsseite).</summary>
    class function Read(const AProject: string): TDpccTeamSettings; static;
    /// <summary>Ordner der geöffneten .groupproj; '' ohne Projektgruppe.</summary>
    class function ActiveGroupFolder: string; static;
    /// <summary>Projektdatei für AProject (.dproj) samt geöffneter Projektgruppe; '' ohne.</summary>
    class function LocateFor(const AProject: string): string; static;
    /// <summary>Sofort neu lesen (nach Speichern der Optionen oder Anlegen der Datei).</summary>
    class procedure Refresh; static;
    /// <summary>Befehl dpcc.TeamFile: anlegen, falls nötig, und im Editor öffnen.</summary>
    class procedure OpenInEditor; static;
  end;

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  ToolsAPI,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Files.TextFile,
  dpcc.IDE.Foundation.Settings,
  dpcc.UI.Foundation.Strings,
  dpcc.IDE.Foundation.Files,
  dpcc.IDE.Foundation.Host;

const
  cCheckMs = 2000;
  /// <summary>Spätestens nach dieser Zeit den Ort neu suchen (neu angelegte Datei weiter oben).</summary>
  cRelocateMs = 10000;

{ TDpccIdeTeamFile }

constructor TDpccIdeTeamFile.Create;
begin
  inherited Create;
  FCurrent := TDpccTeamFile.Empty;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cCheckMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TDpccIdeTeamFile.Destroy;
begin
  FTimer.Free;
  inherited Destroy;
end;

class function TDpccIdeTeamFile.Wanted: Boolean;
begin
  Result := TDpccIdeSettings.Current.Enabled and TDpccIdeSettings.Current.TeamFile;
end;

class function TDpccIdeTeamFile.PathExists(const APath: string): Boolean;
begin
  // .git ist ein Ordner oder bei Worktrees eine Datei.
  Result := FileExists(APath) or DirectoryExists(APath);
end;

class function TDpccIdeTeamFile.ActiveGroupFolder: string;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  // Ohne gespeicherte Gruppe ist der Name ohne Ordner (z. B. „ProjectGroup1.groupproj“).
  if (mGroup <> nil) and (ExtractFileDir(mGroup.FileName) <> '') then
  begin
    Result := ExtractFileDir(mGroup.FileName);
  end;
end;

class function TDpccIdeTeamFile.LocateFor(const AProject: string): string;
begin
  Result := '';
  if AProject <> '' then
  begin
    Result := TDpccTeamFile.Locate(ExtractFileDir(AProject), ActiveGroupFolder, PathExists);
  end;
end;

class function TDpccIdeTeamFile.Load(const AFileName: string; out ATeam: TDpccTeamSettings): Boolean;
var
  mContent: TDpccTextFileContent;
begin
  ATeam := TDpccTeamFile.Empty;
  try
    mContent := TDpccTextFile.Load(AFileName);
  except
    // Gesperrt (gerade gespeichert) oder gelöscht: wie noch nicht gelesen.
    on Exception do
      Exit(False);
  end;
  ATeam := TDpccTeamFile.Parse(mContent.Text, AFileName,
    TDpccTeamFile.RootOf(ExtractFileDir(AFileName), PathExists));
  Result := True;
end;

class function TDpccIdeTeamFile.Read(const AProject: string): TDpccTeamSettings;
var
  mFileName: string;
begin
  Result := TDpccTeamFile.Empty;
  if AProject <> '' then
  begin
    mFileName := LocateFor(AProject);
    if (mFileName <> '') and not Load(mFileName, Result) then
    begin
      // Nicht lesbar: als fehlerhaft zeigen, es gelten die persönlichen Einstellungen.
      Result := TDpccTeamFile.Parse('', mFileName, '');
    end;
  end;
  Result.Project := AProject;
end;

class function TDpccIdeTeamFile.ForProject(const AProject: string): TDpccTeamSettings;
begin
  if (FInstance <> nil) and SameText(FInstance.FCurrent.Project, AProject) then
  begin
    Exit(FInstance.FCurrent);
  end;
  Result := TDpccTeamFile.Empty;
  Result.Project := AProject;
  if Wanted then
  begin
    Result := Read(AProject);
  end;
end;

class procedure TDpccIdeTeamFile.Report(const ATeam: TDpccTeamSettings);
var
  mIssue: TDpccTeamIssue;
begin
  for mIssue in ATeam.Issues do
    case mIssue.Kind of
      TDpccTeamIssueKind.Syntax:
        if mIssue.Line > 0 then
        begin
          TDpccIdeHost.Message(TDpccFoundationStrings.Fmt(TDpccFoundationTextId.TeamFileIssueSyntaxAt,
            [ATeam.FileName, mIssue.Line, mIssue.Column]));
        end
        else
        begin
          TDpccIdeHost.Message(TDpccFoundationStrings.Text(TDpccFoundationTextId.TeamFileIssueSyntax));
        end;
      TDpccTeamIssueKind.Version:
        TDpccIdeHost.Message(TDpccFoundationStrings.Text(TDpccFoundationTextId.TeamFileIssueVersion));
      TDpccTeamIssueKind.UnknownKey:
        TDpccIdeHost.Message(TDpccFoundationStrings.Fmt(TDpccFoundationTextId.TeamFileIssueUnknownKey,
          [mIssue.Path]));
      TDpccTeamIssueKind.WrongType:
        TDpccIdeHost.Message(TDpccFoundationStrings.Fmt(TDpccFoundationTextId.TeamFileIssueWrongType,
          [mIssue.Path]));
      TDpccTeamIssueKind.InvalidValue:
        TDpccIdeHost.Message(TDpccFoundationStrings.Fmt(TDpccFoundationTextId.TeamFileIssueInvalidValue,
          [mIssue.Path]));
      TDpccTeamIssueKind.Credential:
        TDpccIdeHost.Message(TDpccFoundationStrings.Fmt(TDpccFoundationTextId.TeamFileIssueCredential,
          [mIssue.Path]));
      TDpccTeamIssueKind.AbsolutePath:
        TDpccIdeHost.Message(TDpccFoundationStrings.Fmt(TDpccFoundationTextId.TeamFileIssueAbsolutePath,
          [mIssue.Path]));
      TDpccTeamIssueKind.OutsidePath:
        TDpccIdeHost.Message(TDpccFoundationStrings.Fmt(TDpccFoundationTextId.TeamFileIssueOutsidePath,
          [mIssue.Path]));
    end;
end;

procedure TDpccIdeTeamFile.Check;
var
  mProject, mFileName, mStamp: string;
  mTeam: TDpccTeamSettings;
  mAge: TDateTime;
begin
  mProject := '';
  if Wanted then
  begin
    mProject := TDpccIdeFiles.ActiveProjectFile;
  end;
  mFileName := LocatedFor(mProject);
  mStamp := mProject + '|' + mFileName;
  if mFileName <> '' then
  begin
    if FileAge(mFileName, mAge) then
    begin
      mStamp := mStamp + '|' + FloatToStr(mAge, TFormatSettings.Invariant);
    end
    else
    begin
      // Verschwunden: beim nächsten Takt den Ort neu suchen.
      FLocatedAt := 0;
    end;
  end;
  if mStamp = FStamp then
  begin
    Exit;
  end;
  mTeam := TDpccTeamFile.Empty;
  if (mFileName <> '') and not Load(mFileName, mTeam) then
  begin
    Exit;
  end;
  mTeam.Project := mProject;
  FStamp := mStamp;
  FCurrent := mTeam;
  Inc(FVersion);
  Report(mTeam);
end;

function TDpccIdeTeamFile.LocatedFor(const AProject: string): string;
var
  mKey: string;
  mNow: UInt64;
begin
  mKey := AProject + '|' + ActiveGroupFolder;
  mNow := GetTickCount64;
  if (mKey <> FLocateKey) or (FLocatedAt = 0) or (mNow - FLocatedAt >= cRelocateMs) then
  begin
    FLocated := LocateFor(AProject);
    FLocateKey := mKey;
    FLocatedAt := mNow;
  end;
  Result := FLocated;
end;

procedure TDpccIdeTeamFile.Tick(Sender: TObject);
begin
  TDpccGuard.Run(TDpccFeature.Settings,
    procedure
    begin
      Check;
    end);
end;

class procedure TDpccIdeTeamFile.Start;
begin
  if FInstance <> nil then
  begin
    Exit;
  end;
  FInstance := TDpccIdeTeamFile.Create;
  FInstance.Check;
end;

class procedure TDpccIdeTeamFile.Stop;
begin
  FreeAndNil(FInstance);
  Inc(FVersion);
end;

class function TDpccIdeTeamFile.Version: Integer;
begin
  Result := FVersion;
end;

class function TDpccIdeTeamFile.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TDpccIdeTeamFile.Current: TDpccTeamSettings;
begin
  if FInstance = nil then
  begin
    Exit(TDpccTeamFile.Empty);
  end;
  Result := FInstance.FCurrent;
end;

class procedure TDpccIdeTeamFile.Refresh;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  FInstance.FStamp := '';
  FInstance.FLocatedAt := 0;
  FInstance.Check;
end;

class procedure TDpccIdeTeamFile.OpenInEditor;
var
  mProject, mFileName: string;
  mContent: TDpccTextFileContent;
  mActions: IOTAActionServices;
begin
  mProject := TDpccIdeFiles.ActiveProjectFile;
  if mProject = '' then
  begin
    TDpccIdeHost.Message(TDpccFoundationStrings.Text(TDpccFoundationTextId.TeamFileNoProject));
    Exit;
  end;
  mFileName := LocateFor(mProject);
  if mFileName = '' then
  begin
    mFileName := TPath.Combine(ExtractFileDir(mProject), TDpccTeamFile.cFileName);
    mContent := Default(TDpccTextFileContent);
    mContent.Text := TDpccTeamFile.Skeleton;
    mContent.Encoding := TDpccTextEncoding.Utf8;
    try
      TDpccTextFile.Save(mFileName, mContent);
    except
      on E: Exception do
      begin
        TDpccIdeHost.Message(TDpccFoundationStrings.Fmt(TDpccFoundationTextId.TeamFileCreateFailed, [E.Message]));
        Exit;
      end;
    end;
    TDpccIdeHost.Message(TDpccFoundationStrings.Text(TDpccFoundationTextId.TeamFileCreated));
  end;
  if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    mActions.OpenFile(mFileName);
  end;
  Refresh;
end;

end.
