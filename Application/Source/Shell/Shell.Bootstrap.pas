unit Shell.Bootstrap;

// Host-Rolle Shell: gemeinsamer Aufbau für LSP-Server, MCP-Modus und Linter
//. Bisher hatte jeder Modus eigene Kopien:
// - Dateien lesen wie der Server (Kodierung erkennen),
// - Projekte einer Projektgruppe im Ordner,
// - globale Einstellungen aus %APPDATA%\dpcc\settings.json,
// - dpcc.json eines Ordners ohne Editor.
// Logdatei (--log) und Sprache ohne Client (--locale) gab es nur im eigenen Server-Prozess; sie entfallen seit S1.
// Bewusst ohne Windows-Units, damit die Tests auch ohne Windows laufen.

interface

uses
  dpcc.Common.Logging.Contract,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Configuration.Contract;

type
  TShellBootstrap = class
  public
    /// <summary>Datei lesen wie der Server (Kodierung erkennen); False und '' ohne Datei.</summary>
    class function ReadSourceText(const AFileName: string; out AText: string): Boolean; overload; static;
    /// <summary>Wie oben, geöffnete Dokumente aus ADocuments haben aber Vorrang vor der Datei auf der Platte.
    /// </summary>
    class function ReadSourceText(const ADocuments: IDocumentStore; const AFileName: string;
      out AText: string): Boolean; overload; static;
    /// <summary>Projekte der einzigen .groupproj in ARoot (#648); leer ohne oder mit mehreren Gruppen.</summary>
    class function GroupProjects(const ARoot: string; const ALogger: ILogger): TArray<string>; static;
    /// <summary>Projekte der Projektgruppe AGroupFile; leer, wenn sie nicht lesbar ist (Warnung im Log).</summary>
    class function LoadGroup(const AGroupFile: string; const ALogger: ILogger): TArray<string>; static;
    /// <summary>%APPDATA%\dpcc\settings.json; '' ohne APPDATA.</summary>
    class function GlobalSettingsFile: string; overload; static;
    /// <summary>settings.json unter AAppData\dpcc; '' ohne AAppData.</summary>
    class function GlobalSettingsFile(const AAppData: string): string; overload; static;
    /// <summary>Text der globalen settings.json oder ''. Ist sie nicht lesbar, steht eine Warnung in
    /// ALogger; ohne ALogger geht die Ausnahme an den Aufrufer.</summary>
    class function LoadGlobalSettings(const ALogger: ILogger): string; overload; static;
    class function LoadGlobalSettings(const AFileName: string; const ALogger: ILogger): string; overload; static;
    /// <summary>Einstellungen aus dpcc.json (oder der früheren Datei) in ARoot, ohne globale Datei und
    /// Editor; ohne Datei die Vorgaben.</summary>
    class function ProjectSettings(const ARoot: string): TServerSettings; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  dpcc.Common.Configuration.Parser,
  dpcc.Common.Configuration.Scopes,
  dpcc.Common.Documents.FileEncoding,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Projects.GroupReader,
  dpcc.Text.LogMarks;

class function TShellBootstrap.ReadSourceText(const AFileName: string; out AText: string): Boolean;
var
  mFileFormat: TFileFormat;
begin
  Result := (AFileName <> '') and FileExists(AFileName);
  if Result then
  begin
    AText := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
  end
  else
  begin
    AText := '';
  end;
end;

class function TShellBootstrap.ReadSourceText(const ADocuments: IDocumentStore; const AFileName: string;
  out AText: string): Boolean;
var
  mDocument: ITextDocument;
begin
  if (ADocuments <> nil) and ADocuments.TryGet(TDocumentUris.FromPath(AFileName), mDocument) then
  begin
    AText := mDocument.Text;
    Exit(True);
  end;
  Result := ReadSourceText(AFileName, AText);
end;

class function TShellBootstrap.LoadGroup(const AGroupFile: string; const ALogger: ILogger): TArray<string>;
begin
  Result := nil;
  try
    Result := TGroupProjReader.Load(AGroupFile);
    if ALogger <> nil then
    begin
      ALogger.Info(Format('Projektgruppe %s: %d Projekte', [TLogMarks.Path(AGroupFile), Length(Result)]));
    end;
  except
    on E: Exception do
    begin
      if ALogger <> nil then
      begin
        ALogger.Warning(Format('Projektgruppe %s nicht lesbar: %s', [TLogMarks.Path(AGroupFile),
          TLogMarks.Text(E.Message)]));
      end;
      Result := nil;
    end;
  end;
end;

class function TShellBootstrap.GroupProjects(const ARoot: string; const ALogger: ILogger): TArray<string>;
var
  mGroups: TArray<string>;
begin
  Result := nil;
  try
    mGroups := TDirectory.GetFiles(ARoot, '*.groupproj');
  except
    // Nicht lesbare Ordner haben keine Gruppe.
    on Exception do
      mGroups := nil;
  end;
  if Length(mGroups) = 1 then
  begin
    Result := LoadGroup(mGroups[0], ALogger);
  end;
end;

class function TShellBootstrap.GlobalSettingsFile: string;
begin
  Result := GlobalSettingsFile(GetEnvironmentVariable('APPDATA'));
end;

class function TShellBootstrap.GlobalSettingsFile(const AAppData: string): string;
begin
  Result := TConfigurationScopes.GlobalFile(AAppData);
end;

class function TShellBootstrap.LoadGlobalSettings(const ALogger: ILogger): string;
begin
  Result := LoadGlobalSettings(GlobalSettingsFile, ALogger);
end;

class function TShellBootstrap.LoadGlobalSettings(const AFileName: string; const ALogger: ILogger): string;
var
  mFileFormat: TFileFormat;
begin
  Result := '';
  if (AFileName = '') or not FileExists(AFileName) then
  begin
    Exit;
  end;
  try
    Result := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
  except
    // Gerade geschrieben oder gesperrt: Der Server liest sie beim nächsten Ereignis erneut.
    on E: Exception do
    begin
      if ALogger = nil then
      begin
        raise;
      end;
      ALogger.Warning('Globale Einstellungen nicht lesbar: ' + TLogMarks.Text(E.Message));
    end;
  end;
end;

class function TShellBootstrap.ProjectSettings(const ARoot: string): TServerSettings;
var
  mText: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  if not ReadSourceText(ExistingOrLegacyFile(ARoot, cConfigurationFileName, cLegacyConfigurationFileName), mText) then
  begin
    Exit(TServerSettings.Default);
  end;
  Result := TConfigurationParser.Parse(TConfigurationScopes.Filter(mText, TConfigurationScope.Project), mIssues);
end;

end.
