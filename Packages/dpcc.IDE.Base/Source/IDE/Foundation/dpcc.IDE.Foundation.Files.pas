unit dpcc.IDE.Foundation.Files;

// Dateien aus Sicht der IDE (#397, #121, #721): geladenes Projekt, Kodierung auf der Platte.
// Foundation des Plugins: importiert kein dpcc.IDE-Feature, nur Open Tools API und dpcc.Core.
// Bis S-03b Teil von TDpccIdeWorkspaceEdit. Nur im Hauptthread.
// Ohne ProjectModified, BufferOf, SourceText und ReadLines (ohne Aufrufer): Sie liefen über ModuleFileEditors aller
// Module, und das kann Designer laden (früher Ursache eines Hängers).

interface

uses
  ToolsAPI,
  dpcc.Core.Files.TextFile;

type
  TDpccIdeFiles = class
  public
    /// <summary>Geladenes Modul zu einer Projektdatei (.dproj, .groupproj); nil, wenn keins.</summary>
    class function ProjectModule(const AFileName: string): IOTAModule; static;
    /// <summary>Kodierung der Datei auf der Platte (Text leer); UTF-8 mit BOM, wenn sie fehlt oder nicht
    /// lesbar ist (#121).</summary>
    class function DiskEncoding(const AFileName: string): TDpccTextFileContent; static;
    /// <summary>Datei des aktiven Projekts der IDE; '' ohne Projekt.</summary>
    class function ActiveProjectFile: string; static;
    /// <summary>Projektdatei des Projekts der Projektgruppe, das AFileName enthält; '' wenn keins.</summary>
    class function ProjectOfFile(const AFileName: string): string; static;
    /// <summary>Projekt der Projektgruppe mit der Projektdatei AProjectFile (.dproj); nil, wenn keins.</summary>
    class function GroupProject(const AProjectFile: string): IOTAProject; static;
    /// <summary>Gespeicherte .groupproj der geöffneten Projektgruppe, wenn sie AProjectFile (.dproj) enthält; sonst
    /// '' (auch für die ungespeicherte Vorgabegruppe der IDE).</summary>
    class function GroupOfProject(const AProjectFile: string): string; static;
    /// <summary>Aktives Projekt für eine neue Unit (.pas unter dessen Ordner); sonst ''.</summary>
    class function ProjectForNewFile(const AFileName: string): string; static;
    /// <summary>.dproj oder .groupproj?</summary>
    class function IsProjectFile(const AFileName: string): Boolean; static;
    /// <summary>.dpr oder .dpk?</summary>
    class function IsProjectSource(const AFileName: string): Boolean; static;
    /// <summary>.dfm oder .fmx?</summary>
    class function IsFormFile(const AFileName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Files.EncodingDefault;

class function TDpccIdeFiles.ProjectModule(const AFileName: string): IOTAModule;
var
  mServices: IOTAModuleServices;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    if SameText(mServices.Modules[mIndex].FileName, AFileName) then
    begin
      Exit(mServices.Modules[mIndex]);
    end;
  end;
end;

class function TDpccIdeFiles.DiskEncoding(const AFileName: string): TDpccTextFileContent;
begin
  Result := Default(TDpccTextFileContent);
  Result.Encoding := TDpccTextEncoding.Utf8Bom;
  try
    if FileExists(AFileName) then
    begin
      Result := TDpccTextFile.Load(AFileName, TDpccEncodingDefault.CodePageFor(AFileName));
    end;
  except
    on Exception do
      Result.Encoding := TDpccTextEncoding.Utf8Bom;
  end;
  Result.Text := '';
end;

class function TDpccIdeFiles.ActiveProjectFile: string;
var
  mServices: IOTAModuleServices;
  mProject: IOTAProject;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mProject := mServices.GetActiveProject;
  if mProject <> nil then
  begin
    Result := mProject.FileName;
  end;
end;

class function TDpccIdeFiles.ProjectOfFile(const AFileName: string): string;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  Result := '';
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    if mGroup.Projects[mIndex].FindModuleInfo(AFileName) <> nil then
    begin
      Exit(mGroup.Projects[mIndex].FileName);
    end;
  end;
end;

class function TDpccIdeFiles.GroupProject(const AProjectFile: string): IOTAProject;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  Result := nil;
  if (AProjectFile = '') or not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    if SameFileName(mGroup.Projects[mIndex].FileName, AProjectFile) then
    begin
      Exit(mGroup.Projects[mIndex]);
    end;
  end;
end;

class function TDpccIdeFiles.GroupOfProject(const AProjectFile: string): string;
var
  mServices: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
begin
  Result := '';
  if (GroupProject(AProjectFile) = nil) or not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mGroup := mServices.MainProjectGroup;
  // Die Vorgabegruppe „ProjectGroup1“ hat keinen Pfad und keine Datei: Eine Zeile kann nicht für sie gelten.
  if (mGroup <> nil) and SameText(ExtractFileExt(mGroup.FileName), '.groupproj') and FileExists(mGroup.FileName) then
  begin
    Result := mGroup.FileName;
  end;
end;

class function TDpccIdeFiles.ProjectForNewFile(const AFileName: string): string;
var
  mServices: IOTAModuleServices;
  mProject: IOTAProject;
begin
  Result := '';
  if not SameText(ExtractFileExt(AFileName), '.pas') or
    not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mProject := mServices.GetActiveProject;
  if (mProject <> nil) and
    AFileName.StartsWith(IncludeTrailingPathDelimiter(ExtractFilePath(mProject.FileName)), True) then
  begin
    Result := mProject.FileName;
  end;
end;

class function TDpccIdeFiles.IsProjectFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dproj') or SameText(ExtractFileExt(AFileName), '.groupproj');
end;

class function TDpccIdeFiles.IsProjectSource(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dpr') or SameText(ExtractFileExt(AFileName), '.dpk');
end;

class function TDpccIdeFiles.IsFormFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dfm') or SameText(ExtractFileExt(AFileName), '.fmx');
end;

end.
