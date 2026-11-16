unit dpcc.Core.Projects.Setup;

// Einrichtung eines Projekts für dpcc (#759), ohne VCL und Open Tools API:
// Vorlagen für dpcc.json, wohin die Datei kommt und welche Schritte offen
// sind. Anders als die Einrichtungs-Prüfliste (#625, dpcc.Core.Setup.Checklist)
// gilt sie je Projekt.
//
// Schritte (Karte auf der Willkommensseite):
//   1. Projekt gefunden – erledigt, sobald es ein Projekt gibt.
//   2. dpcc.json anlegen – erledigt, wenn neben der Projektdatei (.dproj bzw.
//      .groupproj) eine dpcc.json (oder die frühere delphi-lsp.json) liegt.
//   3. Baseline erzeugen (#97) – erledigt, wenn im Projektordner eine Baseline
//      liegt (dpcc-baseline.json oder der frühere Name).
//   4. Suchpfade und Defines prüfen – erledigt, wenn die letzte Prüfung
//      (Abschnitt "setup.paths" der Projekt-Zusammenfassung) nichts fand.
// Vollständig eingerichtet ist ein Projekt, wenn alle Schritte erledigt sind;
// „Für dieses Projekt nicht mehr fragen“ ("setup.dismissed") blendet die
// Karte ebenfalls aus.
//
// Vorlagen: Setup\Vorlagen\dpcc-<kennung>.json liegen der Installation bei
// (Ordner Vorlagen neben der BPL oder eine Ebene darüber, wie die Doku #766);
// fehlt eine Datei, gilt die eingebaute Fassung (gleicher Inhalt, die Tests
// vergleichen beide). Vor dem Schreiben prüft TDpccSchemaCheck den Inhalt
// gegen dpcc.schema.json (nur Schlüssel des Projekts).

interface

uses
  System.SysUtils,
  dpcc.Core.Projects.Summary;

type
{$SCOPEDENUMS ON}
  /// <summary>Vorlagen in der Reihenfolge der Auswahlliste; Existing ist die Vorgabe.</summary>
  TDpccSetupTemplate = (Existing, NewStrict, Legacy);
  TDpccSetupStep = (Found, Config, Baseline, Paths);
{$SCOPEDENUMS OFF}

  TDpccSetupFileExists = reference to function(const AFileName: string): Boolean;
  TDpccSetupReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Was die Schritte brauchen: Dateien neben dem Projekt und der Abschnitt "setup".</summary>
  TDpccSetupFacts = record
    /// <summary>Projektdatei (.dproj, .groupproj); '' = kein Projekt.</summary>
    Project: string;
    /// <summary>dpcc.json oder delphi-lsp.json liegt neben der Projektdatei.</summary>
    ConfigExists: Boolean;
    /// <summary>Baseline liegt im Projektordner.</summary>
    BaselineExists: Boolean;
    Setup: TDpccProjectSetup;
  end;

  TDpccProjectSetups = class
  public const
    cConfigName = 'dpcc.json';
    cLegacyConfigName = 'delphi-lsp.json';
    /// <summary>Ordner der Vorlagen im Release-Paket (Setup/Vorlagen im Repository).</summary>
    cTemplatesFolder = 'Vorlagen';
  public
    /// <summary>"existing", "strict", "legacy".</summary>
    class function TemplateId(ATemplate: TDpccSetupTemplate): string; static;
    /// <summary>Umkehrung von TemplateId (Groß-/Kleinschreibung egal); False bei unbekannter Kennung.</summary>
    class function TemplateOf(const AId: string; out ATemplate: TDpccSetupTemplate): Boolean; static;
    /// <summary>"dpcc-existing.json" usw.</summary>
    class function TemplateFile(ATemplate: TDpccSetupTemplate): string; static;
    /// <summary>Eingebaute Fassung der Vorlage (Zeilen mit #10), gleich der Datei in Setup\Vorlagen.</summary>
    class function BuiltIn(ATemplate: TDpccSetupTemplate): string; static;
    /// <summary>Ordner Vorlagen in APluginDir oder eine Ebene darüber, wenn die Vorlage der Vorgabe dort liegt;
    /// '' ohne.</summary>
    class function TemplateFolder(const APluginDir: string; const AExists: TDpccSetupFileExists): string; static;
    /// <summary>Text der Vorlage aus AFolder, sonst die eingebaute Fassung.</summary>
    class function TemplateText(ATemplate: TDpccSetupTemplate; const AFolder: string;
      const ARead: TDpccSetupReadText): string; static;
    /// <summary>Ziel der neuen Datei: dpcc.json im Ordner der Projektdatei; '' ohne Projekt.</summary>
    class function ConfigTarget(const AProject: string): string; static;
    /// <summary>Vorhandene Konfiguration neben AProject (dpcc.json vor delphi-lsp.json); '' ohne.</summary>
    class function ExistingConfig(const AProject: string; const AExists: TDpccSetupFileExists): string; static;
    /// <summary>Prüft ATemplateText gegen ASchemaJson (Ort "project"); AIssues wie TDpccSchemaCheck.</summary>
    class function ValidTemplate(const ATemplateText, ASchemaJson: string; out AIssues: TArray<string>): Boolean;
      static;
    /// <summary>Ist der Schritt erledigt?</summary>
    class function StepDone(AStep: TDpccSetupStep; const AFacts: TDpccSetupFacts): Boolean; static;
    /// <summary>Alle Schritte erledigt.</summary>
    class function Complete(const AFacts: TDpccSetupFacts): Boolean; static;
    /// <summary>Offene Schritte in ihrer Reihenfolge.</summary>
    class function OpenSteps(const AFacts: TDpccSetupFacts): TArray<TDpccSetupStep>; static;
    /// <summary>Karte zeigen: mit Projekt, nicht abgewählt und nicht vollständig eingerichtet.</summary>
    class function NeedsCard(const AFacts: TDpccSetupFacts): Boolean; static;
  end;

implementation

uses
  dpcc.Core.Settings.SchemaCheck;

const
  cTemplateIds: array[TDpccSetupTemplate] of string = ('existing', 'strict', 'legacy');

  // Gleich Setup\Vorlagen\dpcc-*.json (dpcc.Core.Projects.Setup.Tests vergleicht beide).
  cExistingText =
    '{' + #10 +
    '  "profile": "standard",' + #10 +
    '  "minConfidence": "medium",' + #10 +
    '  "testProfile": "fast",' + #10 +
    '  "exclude": ["ThirdParty/**", "__history/**", "__recovery/**"]' + #10 +
    '}' + #10;
  cStrictText =
    '{' + #10 +
    '  "profile": "strict",' + #10 +
    '  "minConfidence": "low",' + #10 +
    '  "testProfile": "standard",' + #10 +
    '  "exclude": ["__history/**", "__recovery/**"]' + #10 +
    '}' + #10;
  cLegacyText =
    '{' + #10 +
    '  "profile": "standard",' + #10 +
    '  "minConfidence": "high",' + #10 +
    '  "excludeTests": true,' + #10 +
    '  "exclude": ["ThirdParty/**", "__history/**", "__recovery/**"],' + #10 +
    '  "overrides": [' + #10 +
    '    { "files": ["Generated/**"], "rules": { "*": "off" } }' + #10 +
    '  ]' + #10 +
    '}' + #10;

function FolderOf(const AFileName: string): string;
var
  mIndex: Integer;
begin
  // Ohne ExtractFileDir: Pfade haben immer „\“, auch wenn die Tests nicht unter Windows laufen.
  Result := '';
  for mIndex := Length(AFileName) downto 1 do
  begin
    if CharInSet(AFileName[mIndex], ['\', '/']) then
    begin
      Exit(Copy(AFileName, 1, mIndex - 1));
    end;
  end;
end;

function Joined(const AFolder, AName: string): string;
begin
  if (AFolder = '') or CharInSet(AFolder[Length(AFolder)], ['\', '/']) then
  begin
    Result := AFolder + AName;
  end
  else
  begin
    Result := AFolder + '\' + AName;
  end;
end;

{ TDpccProjectSetups }

class function TDpccProjectSetups.TemplateId(ATemplate: TDpccSetupTemplate): string;
begin
  Result := cTemplateIds[ATemplate];
end;

class function TDpccProjectSetups.TemplateOf(const AId: string; out ATemplate: TDpccSetupTemplate): Boolean;
var
  mEach: TDpccSetupTemplate;
begin
  ATemplate := TDpccSetupTemplate.Existing;
  for mEach := Low(TDpccSetupTemplate) to High(TDpccSetupTemplate) do
  begin
    if SameText(Trim(AId), cTemplateIds[mEach]) then
    begin
      ATemplate := mEach;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDpccProjectSetups.TemplateFile(ATemplate: TDpccSetupTemplate): string;
begin
  Result := 'dpcc-' + cTemplateIds[ATemplate] + '.json';
end;

class function TDpccProjectSetups.BuiltIn(ATemplate: TDpccSetupTemplate): string;
begin
  case ATemplate of
    TDpccSetupTemplate.NewStrict:
      Result := cStrictText;
    TDpccSetupTemplate.Legacy:
      Result := cLegacyText;
  else
    Result := cExistingText;
  end;
end;

class function TDpccProjectSetups.TemplateFolder(const APluginDir: string;
  const AExists: TDpccSetupFileExists): string;
var
  mFolder, mParent, mCandidate: string;
begin
  Result := '';
  if (Trim(APluginDir) = '') or not Assigned(AExists) then
  begin
    Exit;
  end;
  mFolder := APluginDir;
  while (mFolder <> '') and CharInSet(mFolder[Length(mFolder)], ['\', '/']) do
  begin
    Delete(mFolder, Length(mFolder), 1);
  end;
  mCandidate := Joined(mFolder, cTemplatesFolder);
  if AExists(Joined(mCandidate, TemplateFile(TDpccSetupTemplate.Existing))) then
  begin
    Exit(mCandidate);
  end;
  // BPL in Win32\ bzw. Win64\: Vorlagen eine Ebene darüber.
  mParent := FolderOf(mFolder);
  if mParent = '' then
  begin
    Exit;
  end;
  mCandidate := Joined(mParent, cTemplatesFolder);
  if AExists(Joined(mCandidate, TemplateFile(TDpccSetupTemplate.Existing))) then
  begin
    Result := mCandidate;
  end;
end;

class function TDpccProjectSetups.TemplateText(ATemplate: TDpccSetupTemplate; const AFolder: string;
  const ARead: TDpccSetupReadText): string;
var
  mText: string;
begin
  Result := BuiltIn(ATemplate);
  if (AFolder = '') or not Assigned(ARead) then
  begin
    Exit;
  end;
  if ARead(Joined(AFolder, TemplateFile(ATemplate)), mText) and (Trim(mText) <> '') then
  begin
    Result := mText;
  end;
end;

class function TDpccProjectSetups.ConfigTarget(const AProject: string): string;
begin
  Result := '';
  if Trim(AProject) = '' then
  begin
    Exit;
  end;
  Result := Joined(FolderOf(Trim(AProject)), cConfigName);
end;

class function TDpccProjectSetups.ExistingConfig(const AProject: string;
  const AExists: TDpccSetupFileExists): string;
var
  mFolder: string;
begin
  Result := '';
  if (Trim(AProject) = '') or not Assigned(AExists) then
  begin
    Exit;
  end;
  mFolder := FolderOf(Trim(AProject));
  if AExists(Joined(mFolder, cConfigName)) then
  begin
    Result := Joined(mFolder, cConfigName);
  end
  else if AExists(Joined(mFolder, cLegacyConfigName)) then
  begin
    Result := Joined(mFolder, cLegacyConfigName);
  end;
end;

class function TDpccProjectSetups.ValidTemplate(const ATemplateText, ASchemaJson: string;
  out AIssues: TArray<string>): Boolean;
begin
  Result := TDpccSchemaCheck.Validate(ATemplateText, ASchemaJson, 'project', AIssues);
end;

class function TDpccProjectSetups.StepDone(AStep: TDpccSetupStep; const AFacts: TDpccSetupFacts): Boolean;
begin
  case AStep of
    TDpccSetupStep.Found:
      Result := Trim(AFacts.Project) <> '';
    TDpccSetupStep.Config:
      Result := AFacts.ConfigExists;
    TDpccSetupStep.Baseline:
      Result := AFacts.BaselineExists;
  else
    Result := AFacts.Setup.PathsClean;
  end;
end;

class function TDpccProjectSetups.Complete(const AFacts: TDpccSetupFacts): Boolean;
begin
  Result := Length(OpenSteps(AFacts)) = 0;
end;

class function TDpccProjectSetups.OpenSteps(const AFacts: TDpccSetupFacts): TArray<TDpccSetupStep>;
var
  mStep: TDpccSetupStep;
begin
  Result := nil;
  for mStep := Low(TDpccSetupStep) to High(TDpccSetupStep) do
  begin
    if not StepDone(mStep, AFacts) then
    begin
      Result := Result + [mStep];
    end;
  end;
end;

class function TDpccProjectSetups.NeedsCard(const AFacts: TDpccSetupFacts): Boolean;
begin
  Result := (Trim(AFacts.Project) <> '') and not AFacts.Setup.Dismissed and not Complete(AFacts);
end;

end.
