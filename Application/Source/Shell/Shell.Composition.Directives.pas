unit Shell.Composition.Directives;

// Internals-Rolle Shell: Direktiven je Datei aus dem Projekt ihres Arbeitsbereichs. Bedingte Symbole für das
// Abblenden inaktiver Zweige (#615, #845), Include-Pfade (#264), Kontext für Hover und Vervollständigung in
// Direktiven (#102). Herkunft der Compilerschalter, Plattform und Konfiguration des Builds und die Symbole für
// Diagnosen und uses-Suche gibt es seit Rückbau R3 (K9) nicht mehr; ihre Typen hingen an SyntaxDiagnostics,
// CompilerSwitches und UsesLocator.

interface

uses
  dpcc.Common.Projects.Contract,
  dpcc.Common.Pascal.Preprocessor,
  dpcc.Common.Pascal.TreeCache,
  dpcc.Common.Lsp.ConditionalSymbols,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings;

type
  /// <summary>Direktiven der Dateien aus den Projekten der Arbeitsbereiche.</summary>
  TShellDirectives = class
  private
    FWorkspaces: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    /// <summary>Bedingte Symbole des Projekts der Datei; ohne Zuordnung die des ersten (aktiven) Projekts.
    /// </summary>
    function DefinesFor(const AUri: string; out ADefines: TArray<string>): Boolean;
    /// <summary>Include-Pfade des Projekts; ohne Projekt sucht der Resolver im Ordner der Datei.</summary>
    function IncludeResolverFor(const AUri: string): TIncludeResolver;
    /// <summary>Include-Pfade, Projekt und Erfolg des Projekts zur Datei unter der Sperre.</summary>
    function ProjectOf(const AFileName: string; out AIncludePaths: TArray<string>; out AProject: TProjectInfo): Boolean;
    function ConditionalContextFor(const AUri: string): TConditionalContext;
  public
    constructor Create(AWorkspaces: TShellWorkspaceRegistry; ASettings: TShellSettings);
    function TreeDefines: TTreeDefinesProvider;
    function TreeIncludes: TTreeIncludeProvider;
    /// <summary>Hover und Vervollständigung in Direktiven (#102): Symbole mit Herkunft aus der .dproj,
    /// Compiler-Vorgaben, Include-Pfade und der Schalter "directives".</summary>
    function ConditionalContext: TConditionalContextFunc;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Pascal.IncludeFiles,
  dpcc.Common.Documents.Uris,
  Shell.Workspace;

/// <summary>Bedingte Symbole aus ADefines ohne Vorgaben des Compilers und ohne Schalterstände.</summary>
function OwnDefines(const ADefines, APredefined: TArray<string>): TArray<string>;
var
  mDefine: string;
begin
  Result := nil;
  for mDefine in ADefines do
  begin
    if (IndexText(mDefine, APredefined) < 0) and not TPascalPreprocessor.IsSwitchEntry(mDefine) then
    begin
      Result := Result + [mDefine];
    end;
  end;
end;

constructor TShellDirectives.Create(AWorkspaces: TShellWorkspaceRegistry; ASettings: TShellSettings);
begin
  inherited Create;
  FWorkspaces := AWorkspaces;
  FSettings := ASettings;
end;

function TShellDirectives.TreeDefines: TTreeDefinesProvider;
begin
  Result := DefinesFor;
end;

function TShellDirectives.TreeIncludes: TTreeIncludeProvider;
begin
  Result := IncludeResolverFor;
end;

function TShellDirectives.ConditionalContext: TConditionalContextFunc;
begin
  Result := ConditionalContextFor;
end;

function TShellDirectives.DefinesFor(const AUri: string; out ADefines: TArray<string>): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  ADefines := nil;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
    Result := (mWorkspace <> nil) and mWorkspace.State.Defines(ADefines);
    // Datei keinem Projekt zugeordnet oder dessen Projekt noch nicht geladen (Projektgruppe): wie das
    // aktive Projekt, das die IDE zuerst meldet. Sonst blieben inaktive Zweige dort ungedimmt (#615).
    if not Result and (FWorkspaces.Items.Count > 0) then
    begin
      Result := FWorkspaces.Items[0].State.Defines(ADefines);
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TShellDirectives.ProjectOf(const AFileName: string; out AIncludePaths: TArray<string>;
  out AProject: TProjectInfo): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  AIncludePaths := nil;
  Result := False;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(AFileName);
    if mWorkspace <> nil then
    begin
      AIncludePaths := mWorkspace.State.IncludePaths;
      Result := mWorkspace.State.Project(AProject);
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
  if not Result then
  begin
    AProject := Default(TProjectInfo);
  end;
end;

function TShellDirectives.IncludeResolverFor(const AUri: string): TIncludeResolver;
var
  mIncludePaths: TArray<string>;
  mProject: TProjectInfo;
begin
  ProjectOf(TDocumentUris.ToPath(AUri), mIncludePaths, mProject);
  Result := TIncludeFiles.Resolver(mIncludePaths);
end;

function TShellDirectives.ConditionalContextFor(const AUri: string): TConditionalContext;
var
  mSettings: TDirectiveSettings;
  mProject: TProjectInfo;
  mDefines, mPredefined, mIncludePaths: TArray<string>;
begin
  mSettings := FSettings.SettingsFor(AUri).Directives;
  Result := TConditionalContext.Default;
  Result.CompletionEnabled := mSettings.Completion;
  Result.HoverEnabled := mSettings.Hover;
  Result.FileName := TDocumentUris.ToPath(AUri);
  if not (mSettings.Completion or mSettings.Hover) then
  begin
    Exit;
  end;
  ProjectOf(Result.FileName, mIncludePaths, mProject);
  Result.ResolveInclude := TIncludeFiles.Resolver(mIncludePaths);
  // Dieselben Symbole wie beim Abblenden inaktiver Zweige.
  Result.HasDefines := DefinesFor(AUri, mDefines);
  if not Result.HasDefines then
  begin
    Exit;
  end;
  Result.Defines := mDefines;
  mPredefined := TPascalPreprocessor.PredefinedSymbols(mProject.Platform,
    TPascalPreprocessor.CompilerVersionFromDefines(mDefines));
  Result.Config := mProject.Config;
  Result.Platform := mProject.Platform;
  Result.Sources := TConditionalSymbols.SourcesOf(OwnDefines(mDefines, mPredefined), mProject.DefineOrigins,
    mPredefined, mProject.Platform);
end;

end.
