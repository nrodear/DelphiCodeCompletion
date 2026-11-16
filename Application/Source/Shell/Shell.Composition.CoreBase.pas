unit Shell.Composition.CoreBase;

// Schlanker Kern der Komposition (Schritt 2): Arbeitsbereiche, Einstellungen, dpcc.json, Ordner, Direktiven und
// Sprachvorgaben je Datei, ohne Regelkontext, Quellen (Hotspots) und Formatvorgaben. Die Wurzel der Completion
// (Shell.Composition.CompletionServer) benutzt ihn direkt; TShellCore (Shell.Composition.Core) erbt davon und ergänzt
// die Teile der Prüfregeln.

interface

uses
  System.SysUtils,
  dpcc.Common.Logging.Contract,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Pascal.TreeCache,
  Shell.Platform,
  Shell.Workspace,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.Configuration,
  Shell.Composition.Folders,
  Shell.Composition.Directives,
  Shell.Composition.LanguageOptions;

type
  /// <summary>Was der schlanke Kern von der Komposition braucht. Die Funktionen fragen erst beim Aufruf; was sie
  /// liefern, entsteht nach dem Kern.</summary>
  TShellCoreBaseServices = record
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    Documents: IDocumentStore;
    Index: TShellFoldersIndexFunc;
    /// <summary>Gewähltes Projekt einer Projektgruppe (#648).</summary>
    SelectedProject: TShellRegistrySelectedFunc;
    /// <summary>Aktives Projekt der IDE.</summary>
    ActiveProject: TShellRegistryActiveFunc;
    IdeProject: TShellFoldersIdeProjectFunc;
    /// <summary>Typen der laufenden IDE (dpcc/ideTypes).</summary>
    IdeTypes: TShellFoldersIdeTypesFunc;
    /// <summary>Text einer Ersatz-Unit der IDE ("dpcc-ide:…"); False für andere Pfade.</summary>
    IdeText: TShellFoldersReadText;
    Selection: TShellFoldersSelectionFunc;
    Anonymizer: TShellFoldersAnonymizerFunc;
    ClientName: TShellFoldersTextFunc;
    ProjectLoaded: TProc;
    IndexStageDone: TProc<Boolean>;
    IndexEvent: TProc<string>;
    SettingsChanged: TProc<TServerSettings>;
    /// <summary>Beobachtete Dateien geändert; im Thread der Nachrichtenschleife verarbeiten.</summary>
    FilesChanged: TFileWatcherChanged;
  end;

  /// <summary>Hält die Arbeitsbereiche und die Vorgaben, die je Datei aus ihnen folgen.</summary>
  TShellCoreBase = class
  private
    FBaseServices: TShellCoreBaseServices;
    FWorkspaces: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
    FConfiguration: TShellConfiguration;
    FFolders: TShellFolders;
    FDirectives: TShellDirectives;
    FLanguage: TShellLanguageOptions;
    /// <summary>Die an TSyntaxTreeCache gemeldeten Quellen; ReleaseTreeProviders nimmt nur diese zurück.</summary>
    FTreeDefines: TTreeDefinesProvider;
    FTreeIncludes: TTreeIncludeProvider;
    function RegistryServices: TShellWorkspaceRegistryServices;
    function ConfigurationServices: TShellConfigurationServices;
    function FoldersServices: TShellFoldersServices;
  public
    constructor Create(const AServices: TShellCoreBaseServices);
    /// <summary>Gibt Sprachvorgaben, Direktiven, Einstellungen, Arbeitsbereiche, Ordner und dpcc.json frei; vorher
    /// FreeWorkspaces.</summary>
    destructor Destroy; override;
    /// <summary>dpcc.json am Verteiler; Editor-Baum nur aus den aktiven Zweigen (#845) und mit den $I-Dateien der
    /// Suchpfade (#264, #860).</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Beenden: meldet die Quellen des Baum-Caches ab, sofern kein neuerer Server sie ersetzt hat
    /// (In-Process-Modus).</summary>
    procedure ReleaseTreeProviders;
    /// <summary>Beenden: Index-Threads aller Ordner anhalten.</summary>
    procedure StopIndexThreads;
    /// <summary>Beenden: gibt die Ordner frei, solange Index und Syntaxprüfung noch leben.</summary>
    procedure FreeWorkspaces;
    /// <summary>Text einer Datei; Ersatz-Units der IDE und geöffnete Dokumente haben Vorrang vor der Platte.
    /// </summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Projektdateien aller Ordner und geöffnete Dateien außerhalb der Projekte.</summary>
    function ProjectFiles: TArray<string>;
    /// <summary>Einstellungsdateien zu AUri für Absturzfälle (#1355): settings.json und dpcc.json des Ordners.
    /// </summary>
    function SettingsFilesFor(const AUri: string): TArray<string>;
    property Workspaces: TShellWorkspaceRegistry read FWorkspaces;
    property Settings: TShellSettings read FSettings;
    property Configuration: TShellConfiguration read FConfiguration;
    property Folders: TShellFolders read FFolders;
    property Directives: TShellDirectives read FDirectives;
    /// <summary>Delphi-Version, Sprachstand, Schnellbefehle und Doku-Kommentare je Datei.</summary>
    property Language: TShellLanguageOptions read FLanguage;
  end;

implementation

uses
  System.StrUtils,
  dpcc.Common.Documents.Uris,
  Shell.Bootstrap;

constructor TShellCoreBase.Create(const AServices: TShellCoreBaseServices);
begin
  inherited Create;
  FBaseServices := AServices;
  FWorkspaces := TShellWorkspaceRegistry.Create(RegistryServices);
  FSettings := TShellSettings.Create(FWorkspaces,
    function(const AUri: string): string
    begin
      Result := FLanguage.LanguageLevelFor(AUri);
    end);
  FConfiguration := TShellConfiguration.Create(ConfigurationServices);
  FFolders := TShellFolders.Create(FoldersServices);
  FDirectives := TShellDirectives.Create(FWorkspaces, FSettings);
  FLanguage := TShellLanguageOptions.Create(FWorkspaces, FSettings);
end;

destructor TShellCoreBase.Destroy;
begin
  FreeAndNil(FLanguage);
  FreeAndNil(FDirectives);
  FreeAndNil(FSettings);
  FreeAndNil(FWorkspaces);
  // Nach den Ordnern: Ihre Index-Threads sind beendet und abgemeldet.
  FreeAndNil(FFolders);
  FreeAndNil(FConfiguration);
  FBaseServices := Default(TShellCoreBaseServices);
  inherited Destroy;
end;

procedure TShellCoreBase.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FConfiguration.Attach(ADispatcher);
  // Editor-Baum nur aus den aktiven Zweigen des Projekts (#845).
  FTreeDefines := FDirectives.TreeDefines();
  TSyntaxTreeCache.SetDefinesProvider(FTreeDefines);
  // $I-Dateien im Editor-Baum, in Syntaxprüfung und Abblenden (#264, #860): Suchpfade des Projekts.
  FTreeIncludes := FDirectives.TreeIncludes();
  TSyntaxTreeCache.SetIncludeProvider(FTreeIncludes);
end;

procedure TShellCoreBase.ReleaseTreeProviders;
begin
  // Der Baum-Cache ist global; ohne Projekte gelten wieder die Vordefinitionen (#845). Hat ein neuerer Server im
  // selben Prozess seine Quellen gesetzt, bleiben sie.
  if Assigned(FTreeDefines) then
  begin
    TSyntaxTreeCache.ReleaseDefinesProvider(FTreeDefines);
  end;
  if Assigned(FTreeIncludes) then
  begin
    TSyntaxTreeCache.ReleaseIncludeProvider(FTreeIncludes);
  end;
  FTreeDefines := nil;
  FTreeIncludes := nil;
end;

procedure TShellCoreBase.StopIndexThreads;
var
  mWorkspace: TShellWorkspace;
begin
  for mWorkspace in FWorkspaces.Items do
  begin
    mWorkspace.Stop;
  end;
end;

procedure TShellCoreBase.FreeWorkspaces;
begin
  FWorkspaces.FreeWorkspaces;
end;

function TShellCoreBase.RegistryServices: TShellWorkspaceRegistryServices;
begin
  Result := Default(TShellWorkspaceRegistryServices);
  Result.Logger := FBaseServices.Logger;
  Result.SelectedProject := FBaseServices.SelectedProject;
  Result.ActiveProject := FBaseServices.ActiveProject;
end;

function TShellCoreBase.ConfigurationServices: TShellConfigurationServices;
begin
  Result := Default(TShellConfigurationServices);
  Result.Logger := FBaseServices.Logger;
  Result.Workspaces := FWorkspaces;
  Result.Settings := FSettings;
  Result.Documents := FBaseServices.Documents;
  Result.Transport := FBaseServices.Transport;
  Result.FilesChanged := FBaseServices.FilesChanged;
end;

function TShellCoreBase.FoldersServices: TShellFoldersServices;
begin
  Result := Default(TShellFoldersServices);
  Result.Logger := FBaseServices.Logger;
  Result.Transport := FBaseServices.Transport;
  Result.Documents := FBaseServices.Documents;
  Result.Workspaces := FWorkspaces;
  Result.Settings := FSettings;
  Result.Configuration := FConfiguration;
  Result.Index := FBaseServices.Index;
  Result.IdeProject := FBaseServices.IdeProject;
  Result.IdeTypes := FBaseServices.IdeTypes;
  Result.Selection := FBaseServices.Selection;
  Result.Anonymizer := FBaseServices.Anonymizer;
  Result.ClientName := FBaseServices.ClientName;
  Result.ReadText := ReadText;
  Result.ProjectLoaded := FBaseServices.ProjectLoaded;
  Result.IndexStageDone := FBaseServices.IndexStageDone;
  Result.IndexEvent := FBaseServices.IndexEvent;
  Result.SettingsChanged := FBaseServices.SettingsChanged;
end;

function TShellCoreBase.ReadText(const AFileName: string; out AText: string): Boolean;
var
  mDocument: ITextDocument;
begin
  // Ersatz-Units der IDE gibt es nur im Speicher.
  if Assigned(FBaseServices.IdeText) and FBaseServices.IdeText(AFileName, AText) then
  begin
    Exit(True);
  end;
  // Geöffnete Dokumente haben Vorrang vor der Datei auf der Platte.
  if FBaseServices.Documents.TryGet(TDocumentUris.FromPath(AFileName), mDocument) then
  begin
    AText := mDocument.Text;
    Exit(True);
  end;
  Result := TShellBootstrap.ReadSourceText(AFileName, AText);
end;

function TShellCoreBase.ProjectFiles: TArray<string>;
var
  mWorkspace: TShellWorkspace;
  mDocument: ITextDocument;
  mFileName: string;
begin
  Result := nil;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    for mWorkspace in FWorkspaces.Items do
    begin
      for mFileName in mWorkspace.State.ProjectFiles do
      begin
        Result := Result + [mFileName];
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
  // Geöffnete Dateien außerhalb des Projekts zählen mit.
  for mDocument in FBaseServices.Documents.Documents do
  begin
    Result := Result + [TDocumentUris.ToPath(mDocument.Uri)];
  end;
end;

function TShellCoreBase.SettingsFilesFor(const AUri: string): TArray<string>;
var
  mWorkspace: TShellWorkspace;
begin
  Result := nil;
  if FConfiguration.GlobalSettingsFile <> '' then
  begin
    Result := Result + [FConfiguration.GlobalSettingsFile];
  end;
  if not StartsText('file:', AUri) then
  begin
    Exit;
  end;
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
    if mWorkspace <> nil then
    begin
      Result := Result + [ExistingOrLegacyFile(mWorkspace.Root, cConfigurationFileName,
        cLegacyConfigurationFileName)];
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

end.
