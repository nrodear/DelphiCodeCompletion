unit Shell.Composition.CompletionServer;

// Host-Rolle Shell: Wurzel des Completion-Servers (Schritt 2). Sie verdrahtet nur, was die Code Completion braucht:
// Protokoll mit Lebenszyklus (Shell.Composition.Protocol), Sitzung (Shell.Composition.Session),
// Dokumente mit Synchronisation, den schlanken Kern mit Arbeitsbereichen, Ordnern, Einstellungen, dpcc.json und
// Direktiven (Shell.Composition.CoreBase), Index mit den Ersatz-Units der IDE (Shell.Composition.IndexArea),
// Nachrichten aus der IDE (Shell.Composition.Ide), Dateiänderungen (Shell.Composition.FileChanges), Vervollständigung
// samt resolve, dpcc/expressionCompletion und dpcc/postfixTemplates (Shell.Composition.Completion), Hover und
// Parameterhilfe. Keine Diagnosen, kein Compiler, keine Befehle (executeCommand), keine Refactorings, kein MCP,
// keine Absturzfälle (Rückbau R3).
//
// Der Transport kommt von außen (Create bzw. CreateForStreams); diese Unit liegt im Package dpcc.Server. Seit S1 ist
// der In-Process-Betrieb (Shell.Composition.InProcess, Konzept Abschnitt 4.5) der einzige: kein eigener
// Server-Prozess, kein stdin/stdout.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  dpcc.Common.Logging.Contract,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.JsonRpc.Connection,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Index.Contract,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Pascal.FormatRoutines,
  dpcc.Common.Projects.Selection,
  dpcc.Common.Lsp.TextDocumentSync,
  dpcc.Common.Lsp.Hover,
  dpcc.Common.Lsp.SignatureHelp,
  Shell.Composition.Channel,
  Shell.Composition.Protocol,
  Shell.Composition.Session,
  Shell.Composition.CoreBase,
  Shell.Composition.IndexArea,
  Shell.Composition.Ide,
  Shell.Composition.FileChanges,
  Shell.Composition.Completion;

type
  /// <summary>Teile des Completion-Servers; öffentliche Felder, weil nur die Wurzel sie setzt. Die Dienste der Teile
  /// sind Methoden, die die Felder erst beim Aufruf lesen. Destroy hält die Reihenfolge des Beendens.</summary>
  TShellCompletionServerParts = class
  public const
    /// <summary>Anfragen, die länger laufen, werden abgebrochen und gemeldet.</summary>
    cRequestTimeoutMs = 10000;
  private
    /// <summary>Teil von Destroy: gibt Features, Ordner und Index frei.</summary>
    procedure FreeFeatures;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function BuildCapabilities: TJSONObject;
    function CoreServices: TShellCoreBaseServices;
    function IndexServices: TShellIndexAreaServices;
    function SessionServices: TShellSessionServices;
    function IdeServices: TShellIdeServices;
    function FileChangesServices: TShellFileChangesServices;
    function CompletionServices: TShellCompletionServices;
    procedure CreateDocuments;
    procedure CreateCore;
    procedure CreateIde;
    procedure CreateFeatures;
    procedure SettingsChanged(ASettings: TServerSettings);
    procedure NamespacesChanged(const ANamespaces: TArray<string>);
    function Queue(const AWork: TProc): Boolean;
    function NamingPrefixFor(const AUri: string; AKind: TNamingKind): string;
    function FormatRoutinesFor(const AUri: string): TArray<TFormatRoutine>;
    procedure Initialized;
  public
    /// <summary>Logger, Transport und Anonymisierer.</summary>
    Channel: TShellServerChannel;
    Protocol: TShellProtocol;
    Session: TShellSession;
    Documents: IDocumentStore;
    TextDocumentSync: TLspTextDocumentSync;
    Core: TShellCoreBase;
    IndexArea: TShellIndexArea;
    Ide: TShellIde;
    /// <summary>Gemerkte Projektwahl über Neustarts (#46).</summary>
    Selection: TProjectSelection;
    FileChanges: TShellFileChanges;
    Completion: TShellCompletion;
    Hover: TLspHover;
    SignatureHelp: TLspSignatureHelp;
    Connection: TJsonRpcConnection;
    /// <summary>Der Client hat keinen brauchbaren Ordner gemeldet (RAD Studio, #175).</summary>
    DeriveWorkspaces: Boolean;
    /// <summary>Liefen beim Ende der Schleife noch Anfragen (UnfinishedWork), wartet Destroy so lange weiter auf
    /// sie, bevor es Index und Features freigibt. 0 = nicht warten, Objekte stehen lassen. Der In-Process-Betrieb
    /// setzt eine Zeitgrenze, weil der Prozess (die IDE) weiterläuft.</summary>
    UnfinishedWaitMs: Cardinal;
    /// <summary>Destroy ließ Features und Index stehen, weil Anfragen auch nach UnfinishedWaitMs noch liefen; ihr
    /// Code muss dann geladen bleiben (In-Process-Modus).</summary>
    OnLeftWork: TProc;
    /// <summary>Hält Wächter, Verbindung und Index-Threads an und gibt alle Teile rückwärts frei.</summary>
    destructor Destroy; override;
    /// <summary>Schickt eine Benachrichtigung an den Client.</summary>
    procedure NotifyClient(const AMethod: string; AParams: TJSONObject);
    /// <summary>Gemeinsamer Symbolindex; nil vor der Teilwurzel Index und nach dem Freigeben.</summary>
    function Index: ISymbolIndex;
  end;

  /// <summary>Wurzel des Completion-Servers.</summary>
  TShellCompletionServer = class
  private
    FParts: TShellCompletionServerParts;
    function GetDocuments: IDocumentStore;
  public
    /// <summary>Verdrahtet alle Teile am Transport ATransport mit dem Logger ALogger.</summary>
    constructor Create(const ATransport: IJsonRpcTransport; const ALogger: ILogger);
    destructor Destroy; override;
    /// <summary>Mit einem Paar aus Ein- und Ausgabe-Stream (Pipes, Speicher), etwa für Tests; mit AOwnsStreams gibt
    /// der Transport die Streams frei. Der Anonymisierer ist der Vorgabe-Anonymisierer.</summary>
    class function CreateForStreams(AInput, AOutput: TStream; AOwnsStreams: Boolean;
      const ALogger: ILogger): TShellCompletionServer; static;
    /// <summary>Verarbeitet Nachrichten bis exit oder Ende der Eingabe und liefert den Exit-Code.</summary>
    function Run: Integer;
    /// <summary>Gemeinsamer Symbolindex; nil vor dem Index und nach dem Freigeben.</summary>
    function Index: ISymbolIndex;
    property Documents: IDocumentStore read GetDocuments;
    /// <summary>Teile der Wurzel, für Tests und den In-Process-Modus.</summary>
    property Parts: TShellCompletionServerParts read FParts;
  end;

implementation

uses
  dpcc.Common.JsonRpc.Messages,
  dpcc.Common.JsonRpc.StreamTransport,
  dpcc.Common.Documents.Providers.DocumentStore,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Diagnostics.Contract,
  dpcc.Common.Diagnostics.Anonymizer,
  dpcc.Common.Projects.Contract,
  dpcc.Common.Index.Adapters.CacheDirectory,
  dpcc.Common.Lsp.IdeProject,
  dpcc.Common.Lsp.IdeTypes,
  dpcc.Common.Lsp.IdeUnits,
  dpcc.Common.Lsp.WatchedFiles,
  dpcc.Common.Lsp.Completion,
  dpcc.Common.Lsp.Completion.Names,
  dpcc.Common.Rules.Contract,
  System.IOUtils,
  Shell.Platform,
  Shell.Workspace,
  Shell.Composition.DocumentEvents,
  Shell.Composition.ClientStart,
  Shell.Composition.CompletionCapabilities;

/// <summary>Kanonischer Pfad für den Dokumentspeicher.</summary>
function CanonicalPath(const APath: string): string;
begin
  Result := TShellPlatform.CanonicalizePath(APath);
end;

{ TShellCompletionServerParts }

destructor TShellCompletionServerParts.Destroy;
var
  mUnfinished: Boolean;
begin
  // Globale Anbieter nur zurücknehmen, wenn noch die eigenen gesetzt sind: Im IDE-Prozess kann ein neuerer Server
  // sie schon ersetzt haben (Neustart).
  if IndexArea <> nil then
  begin
    IndexArea.ReleaseDeclaredProvider;
  end;
  // Zuerst: Eine laufende Übernahme greift auf die Ordner zu.
  if FileChanges <> nil then
  begin
    FileChanges.StopRefresh;
  end;
  // Vor der Verbindung: Der Wächter der Einstellungen ruft Connection.
  if Core <> nil then
  begin
    Core.Configuration.StopWatching;
  end;
  // Liefen beim Ende noch Handler, die ihr Abbruchsignal nicht prüfen, nutzen sie Features und Ordner weiter. Im
  // IDE-Prozess endet der Prozess nicht: weiter warten (abgebrochen sind sie schon), dann freigeben.
  mUnfinished := (Connection <> nil) and Connection.UnfinishedWork;
  if mUnfinished and (UnfinishedWaitMs > 0) then
  begin
    mUnfinished := not Connection.WaitForUnfinishedWork(UnfinishedWaitMs);
    if not mUnfinished then
    begin
      Channel.Logger.Info('Beim Beenden noch laufende Anfragen sind fertig');
    end;
  end;
  FreeAndNil(Connection);
  if Protocol <> nil then
  begin
    Protocol.Dispatcher.Watchdog := nil;
  end;
  // Index-Threads anhalten, solange das Diagnoselog noch lebt: Ein abgebrochener Aufbau meldet sich dort.
  if Core <> nil then
  begin
    Core.StopIndexThreads;
  end;
  // Der Baum-Cache ist global; ohne Projekte gelten wieder die Vordefinitionen (#845).
  if Core <> nil then
  begin
    Core.ReleaseTreeProviders;
  end;
  if Protocol <> nil then
  begin
    Protocol.Dispatcher.Observer := nil;
  end;
  FreeAndNil(Session);
  if mUnfinished then
  begin
    // Speicher stehen lassen, statt ihn unter einem laufenden Handler freizugeben; der Gastgeber muss den Code
    // geladen lassen (OnLeftWork).
    Channel.Logger.Warning('Beim Beenden liefen noch Anfragen; ihre Objekte werden nicht freigegeben');
    if Assigned(OnLeftWork) then
    begin
      OnLeftWork();
    end;
  end
  else
  begin
    FreeFeatures;
  end;
  Channel := Default(TShellServerChannel);
  inherited;
end;

procedure TShellCompletionServerParts.FreeFeatures;
begin
  // Ordner vor dem Index: ihre Index-Threads laufen noch.
  if Core <> nil then
  begin
    Core.FreeWorkspaces;
  end;
  FreeAndNil(Core);
  FreeAndNil(IndexArea);
  // Danach die Features; Protokoll und Absturzfälle zuletzt.
  FreeAndNil(SignatureHelp);
  FreeAndNil(Hover);
  FreeAndNil(Completion);
  FreeAndNil(FileChanges);
  FreeAndNil(Ide);
  FreeAndNil(Selection);
  FreeAndNil(TextDocumentSync);
  Documents := nil;
  // Nach der Verbindung und dem Watchdog.
  FreeAndNil(Protocol);
end;

procedure TShellCompletionServerParts.NotifyClient(const AMethod: string; AParams: TJSONObject);
var
  mNotification: TJSONObject;
begin
  mNotification := TJsonRpcMessages.Notification(AMethod, AParams);
  try
    Channel.Transport.WriteMessage(mNotification);
  finally
    mNotification.Free;
  end;
end;

function TShellCompletionServerParts.Index: ISymbolIndex;
begin
  Result := nil;
  if IndexArea <> nil then
  begin
    Result := IndexArea.Index;
  end;
end;

function TShellCompletionServerParts.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := Core.ReadText(AFileName, AText);
end;

function TShellCompletionServerParts.BuildCapabilities: TJSONObject;
begin
  // Aus dem Verteiler: gemeldet wird nur, was angemeldet ist. Eigen-Benachrichtigungen kennt der Verteiler nicht
  // als Liste; es sind die von Vervollständigung, Index und IDE-Nachrichten.
  Result := TShellCompletionCapabilities.Build(Protocol.Dispatcher.Methods,
    [TLspCompletion.cPostfixTemplatesMethod, TIdeUnits.cMethod, TLspIdeTypes.cMethod, TLspIdeProject.cMethod]);
end;

procedure TShellCompletionServerParts.CreateDocuments;
var
  mServices: TShellProtocolServices;
begin
  mServices.Logger := Channel.Logger;
  mServices.TimeoutMs := cRequestTimeoutMs;
  // Closure statt Methode: Eine Funktion ohne Parameter würde sonst sofort aufgerufen.
  mServices.Capabilities :=
    function: TJSONObject
    begin
      Result := BuildCapabilities;
    end;
  Protocol := TShellProtocol.Create(mServices);
  Documents := TDocumentStore.Create(CanonicalPath);
  TextDocumentSync := TLspTextDocumentSync.Create(Documents);
  TextDocumentSync.Attach(Protocol.Dispatcher);
end;

function TShellCompletionServerParts.CoreServices: TShellCoreBaseServices;
begin
  Result := Default(TShellCoreBaseServices);
  Result.Logger := Channel.Logger;
  Result.Transport := Channel.Transport;
  Result.Documents := Documents;
  Result.Index :=
    function: ISymbolIndex
    begin
      Result := Index;
    end;
  // Projektwahl, IDE und Index entstehen nach dem Kern; der Kern fragt erst beim Laden der Ordner.
  Result.SelectedProject :=
    function(const AOrigin: string): string
    begin
      Result := Selection.Project(AOrigin);
    end;
  Result.ActiveProject :=
    function: string
    begin
      Result := Ide.Project.ActiveProject;
    end;
  Result.IdeProject :=
    function: TLspIdeProject
    begin
      Result := Ide.Project;
    end;
  Result.IdeTypes :=
    function: IRuleIdeTypes
    begin
      Result := Ide.Types.Catalog;
    end;
  Result.IdeText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := (IndexArea <> nil) and IndexArea.IdeUnits.ReadText(AFileName, AText);
    end;
  Result.Selection :=
    function: TProjectSelection
    begin
      Result := Selection;
    end;
  Result.Anonymizer :=
    function: ILogAnonymizer
    begin
      Result := Channel.Anonymizer;
    end;
  Result.ClientName :=
    function: string
    begin
      Result := '';
      if Session <> nil then
      begin
        Result := Session.ClientName;
      end;
    end;
  Result.ProjectLoaded :=
    procedure
    begin
      IndexArea.ProjectLoaded;
    end;
  Result.IndexStageDone :=
    procedure(AProjectStage: Boolean)
    begin
      IndexArea.IndexStageDone(AProjectStage);
    end;
  Result.IndexEvent :=
    procedure(AText: string)
    begin
      // Absicherung: Beim Beenden ist das Diagnoselog schon fort.
      if Session <> nil then
      begin
        Session.Diagnostics.Log.LogEvent(AText);
      end;
    end;
  Result.SettingsChanged := SettingsChanged;
  // Im Thread der Nachrichtenschleife verarbeiten wie eine Meldung des Clients.
  Result.FilesChanged :=
    procedure(const AFiles: TArray<string>)
    begin
      Connection.Post(TLspWatchedFiles.Notification(AFiles));
    end;
end;

procedure TShellCompletionServerParts.SettingsChanged(ASettings: TServerSettings);
begin
  Protocol.Dispatcher.Watchdog.SetTimeout(ASettings.RequestTimeoutMs);
  Session.ApplySettings(ASettings);
end;

procedure TShellCompletionServerParts.CreateCore;
var
  mEvents: TShellDocumentEventServices;
begin
  Core := TShellCoreBase.Create(CoreServices);
  mEvents := Default(TShellDocumentEventServices);
  mEvents.Core :=
    function: TShellCoreBase
    begin
      Result := Core;
    end;
  // Ohne Compiler: CompileOnSave bleibt nil.
  mEvents.FileChanges :=
    function: TShellFileChanges
    begin
      Result := FileChanges;
    end;
  mEvents.DeriveWorkspaces :=
    function: Boolean
    begin
      Result := DeriveWorkspaces;
    end;
  TShellDocumentEvents.Attach(Documents, mEvents);
  Core.Attach(Protocol.Dispatcher);
end;

function TShellCompletionServerParts.Queue(const AWork: TProc): Boolean;
begin
  Result := (Connection <> nil) and Connection.Queue(AWork);
end;

procedure TShellCompletionServerParts.NamespacesChanged(const ANamespaces: TArray<string>);
begin
  Completion.Completion.Hooks.Namespaces := ANamespaces;
  Hover.Namespaces := ANamespaces;
  SignatureHelp.Namespaces := ANamespaces;
end;

function TShellCompletionServerParts.IndexServices: TShellIndexAreaServices;
begin
  // Ohne Diagnosen und Compiler: IndexStarted, Refresh, Recheck, RefreshLater und ProjectStarted bleiben nil.
  Result := Default(TShellIndexAreaServices);
  Result.Dispatcher := Protocol.Dispatcher;
  Result.Core :=
    function: TShellCoreBase
    begin
      Result := Core;
    end;
  Result.Anonymizer :=
    function: ILogAnonymizer
    begin
      Result := Channel.Anonymizer;
    end;
  Result.NamespacesChanged := NamespacesChanged;
  Result.LibraryRootsChanged :=
    procedure(const ARoots: TArray<string>)
    begin
      Session.Diagnostics.SetLibraryRoots(ARoots);
    end;
  Result.Queue := Queue;
  // Danach fragt die IDE-Seite nach den Mitgliedern der Units ohne Quelltext.
  Result.IndexFinished :=
    procedure
    begin
      if Ide <> nil then
      begin
        Ide.IndexFinished;
      end;
    end;
end;

function TShellCompletionServerParts.SessionServices: TShellSessionServices;
begin
  Result.Logger := Channel.Logger;
  Result.Documents := Documents;
  Result.Index := Index;
  Result.Dispatcher := Protocol.Dispatcher;
  Result.IndexLoading :=
    function: Integer
    begin
      Result := Core.Workspaces.IndexLoading;
    end;
end;

function TShellCompletionServerParts.IdeServices: TShellIdeServices;
begin
  // Ohne Diagnosen: neue Präfixe und IDE-Typen lösen nichts aus (NamingChanged und TypesChanged bleiben nil).
  Result := Default(TShellIdeServices);
  Result.Logger := Channel.Logger;
  Result.Workspaces := Core.Workspaces;
  Result.IdeUnits := IndexArea.IdeUnits;
  Result.Index := Index;
  Result.Notify := NotifyClient;
end;

function TShellCompletionServerParts.FileChangesServices: TShellFileChangesServices;
begin
  Result := Default(TShellFileChangesServices);
  Result.Logger := Channel.Logger;
  Result.Workspaces := Core.Workspaces;
  Result.Transport := Channel.Transport;
  Result.Configuration := Core.Configuration;
  // Ohne Diagnosen nichts neu zu prüfen.
  Result.RefreshLater :=
    procedure
    begin
    end;
  Result.Typed :=
    procedure
    begin
    end;
  Result.Affected :=
    procedure(const AFiles: TArray<string>)
    begin
    end;
end;

procedure TShellCompletionServerParts.CreateIde;
begin
  Ide := TShellIde.Create(IdeServices);
  Ide.Attach(Protocol.Dispatcher);
  // Projektwahl je Benutzer über Neustarts (#46).
  Selection := TProjectSelection.Create(TPath.Combine(TIndexCacheDirectory.DefaultRoot, 'projektauswahl.json'));
  FileChanges := TShellFileChanges.Create(FileChangesServices);
  FileChanges.Attach(Protocol.Dispatcher);
end;

function TShellCompletionServerParts.NamingPrefixFor(const AUri: string; AKind: TNamingKind): string;
var
  mWorkspace: TShellWorkspace;
  mProject: TProjectInfo;
  mContext: TIdeProjectContext;
  mFound: Boolean;
begin
  // Präfix der Namensvorschläge (#452): Vorgabe der Projektdatei .dpcc aus der IDE, sonst die Zählung im Index.
  System.TMonitor.Enter(Core.Workspaces.Lock);
  try
    mWorkspace := Core.Workspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
    mFound := (mWorkspace <> nil) and mWorkspace.State.Project(mProject);
  finally
    System.TMonitor.Exit(Core.Workspaces.Lock);
  end;
  if mFound and Ide.Project.Find(mProject.FileName, mContext) and mContext.HasNaming[AKind] then
  begin
    Exit(mContext.Naming[AKind]);
  end;
  Result := TCompletionNames.NamingPrefix(IndexArea.EditorIndex, AKind);
end;

function TShellCompletionServerParts.FormatRoutinesFor(const AUri: string): TArray<TFormatRoutine>;
var
  mWorkspace: TShellWorkspace;
  mProject: TProjectInfo;
  mContext: TIdeProjectContext;
  mFound: Boolean;
begin
  // Formatfunktionen (format-args in der Parameterhilfe): Vorgaben und die des IDE-Projekts. "formatMethods" aus
  // den Regeloptionen fehlt hier, weil die Wurzel keine Regel-Engine kennt.
  Result := TFormatRoutines.Defaults;
  System.TMonitor.Enter(Core.Workspaces.Lock);
  try
    mWorkspace := Core.Workspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
    mFound := (mWorkspace <> nil) and mWorkspace.State.Project(mProject);
  finally
    System.TMonitor.Exit(Core.Workspaces.Lock);
  end;
  if mFound and Ide.Project.Find(mProject.FileName, mContext) then
  begin
    Result := Result + mContext.FormatFunctions;
  end;
end;

function TShellCompletionServerParts.CompletionServices: TShellCompletionServices;
var
  mCore: TShellCoreBase;
begin
  mCore := Core;
  Result := Default(TShellCompletionServices);
  Result.Documents := Documents;
  // Mit den Ersatz-Units der IDE: Mitglieder von Typen aus Packages ohne Quelltext.
  Result.Index := IndexArea.EditorIndex;
  Result.EnsureUnit := mCore.Folders.EnsureUnitFunc();
  Result.ReadText := ReadText;
  Result.CompletionSettingsFor :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := mCore.Settings.Completion(AUri);
    end;
  // Nur für Postfix-Vorlagen (Inline-Variablen).
  Result.RefactoringSettingsFor :=
    function(const AUri: string): TRefactoringSettings
    begin
      Result := mCore.Settings.Refactoring(AUri);
    end;
  Result.LanguageLevelFor := mCore.Language.LanguageLevelFor;
  Result.NamingFor := NamingPrefixFor;
  Result.IdeTypesFor :=
    function: TArray<TIdeTypeEntry>
    begin
      Result := Ide.Types.Catalog.Entries;
    end;
  Result.HintsFor :=
    function(const AUri: string): THintSettings
    begin
      Result := mCore.Settings.Hints(AUri);
    end;
  Result.DocCommentsFor := mCore.Language.DocCommentsFor;
  Result.SymbolsFor := mCore.Directives.ConditionalContext();
  Result.Notify := NotifyClient;
  Result.Log :=
    procedure(const AText: string)
    begin
      Channel.Logger.Debug(AText);
    end;
end;

procedure TShellCompletionServerParts.CreateFeatures;
var
  mCore: TShellCoreBase;
begin
  mCore := Core;
  Completion := TShellCompletion.Create(CompletionServices);
  Completion.Attach(Protocol.Dispatcher);
  Hover := TLspHover.Create(Documents, IndexArea.EditorIndex, ReadText, mCore.Folders.EnsureUnitFunc());
  Hover.VersionProvider := mCore.Language.DelphiVersionFor;
  Hover.HintsFor :=
    function(const AUri: string): THintSettings
    begin
      Result := mCore.Settings.Hints(AUri);
    end;
  // Seit Rückbau R3 ohne Begründungen (Rationale), DataSet-Hinweise, "neu zugewiesen" und Doku-Links.
  Hover.SymbolsFor := mCore.Directives.ConditionalContext();
  Hover.Attach(Protocol.Dispatcher);
  SignatureHelp := TLspSignatureHelp.Create(Documents, IndexArea.EditorIndex, ReadText,
    mCore.Folders.EnsureUnitFunc());
  SignatureHelp.FormatRoutinesFor := FormatRoutinesFor;
  SignatureHelp.Attach(Protocol.Dispatcher);
end;

procedure TShellCompletionServerParts.Initialized;
var
  mStart: TShellClientStartParts;
begin
  mStart := Default(TShellClientStartParts);
  mStart.Logger := Channel.Logger;
  mStart.Lifecycle := Protocol.Lifecycle;
  mStart.Session := Session;
  mStart.Core := Core;
  mStart.IdeProject := Ide.Project;
  mStart.FileChanges := FileChanges;
  mStart.Hover := Hover;
  mStart.Completion := Completion.Completion;
  mStart.SetDeriveWorkspaces :=
    procedure(ADerive: Boolean)
    begin
      DeriveWorkspaces := ADerive;
    end;
  TShellClientStart.Initialized(mStart);
end;

{ TShellCompletionServer }

constructor TShellCompletionServer.Create(const ATransport: IJsonRpcTransport; const ALogger: ILogger);
var
  mParts: TShellCompletionServerParts;
begin
  inherited Create;
  mParts := TShellCompletionServerParts.Create;
  FParts := mParts;
  mParts.Channel.Transport := ATransport;
  mParts.Channel.Logger := ALogger;
  // Reihenfolge: Protokoll und Dokumente, Kern, Index, Sitzung, IDE, Features. Die Dienste fragen spätere Teile
  // erst beim Aufruf.
  mParts.CreateDocuments;
  mParts.CreateCore;
  mParts.IndexArea := TShellIndexArea.Create(mParts.IndexServices);
  mParts.Session := TShellSession.Create(mParts.SessionServices, TShellCompletionServerParts.cRequestTimeoutMs);
  mParts.CreateIde;
  mParts.CreateFeatures;
  mParts.Protocol.Lifecycle.OnInitialized := mParts.Initialized;
  mParts.Connection := TJsonRpcConnection.Create(mParts.Channel.Transport, mParts.Protocol.Dispatcher);
  mParts.Connection.OnError :=
    procedure(const AError: Exception)
    begin
      mParts.Channel.Logger.Error('Fehler bei der Verarbeitung: ' + mParts.Session.DescribeFailure(AError));
    end;
  mParts.Protocol.Lifecycle.OnExit :=
    procedure
    begin
      mParts.Session.EndReason := TDiagnosticEndReason.Clean;
      mParts.Connection.Stop;
    end;
end;

destructor TShellCompletionServer.Destroy;
begin
  FreeAndNil(FParts);
  inherited;
end;

class function TShellCompletionServer.CreateForStreams(AInput, AOutput: TStream; AOwnsStreams: Boolean;
  const ALogger: ILogger): TShellCompletionServer;
begin
  Result := TShellCompletionServer.Create(TJsonRpcStreamTransport.Create(AInput, AOutput, AOwnsStreams), ALogger);
  // Er sammelt die Namen der Projekte für den anonymen Status (#1356).
  Result.FParts.Channel.Anonymizer := TLogAnonymizer.Create(TProcessInfo.IdentityNames);
end;

function TShellCompletionServer.Run: Integer;
begin
  Result := FParts.Session.Run(FParts.Connection, FParts.Protocol.Lifecycle);
end;

function TShellCompletionServer.Index: ISymbolIndex;
begin
  Result := FParts.Index;
end;

function TShellCompletionServer.GetDocuments: IDocumentStore;
begin
  Result := FParts.Documents;
end;

end.
