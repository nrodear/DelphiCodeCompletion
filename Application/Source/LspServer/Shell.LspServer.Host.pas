unit Shell.LspServer.Host;

// Host-Rolle Shell, nur in dpcc.LspServer.exe (und im Testprogramm): der eigenständige LSP-Server über zwei Streams.
// Er nimmt die Wurzel des Completion-Servers (Shell.Composition.CompletionServer, dieselbe wie im Plugin) und setzt
// davor den Übersetzer für den Dialekt der RAD-Studio-IDE (Shell.LspServer.RadStudio.Dialect). Dazu kommt, was der
// eingebaute Server nicht hat:
// - textDocument/documentSymbol für die Strukturansicht (Shell.LspServer.DocumentSymbols);
// - exit auch als Anfrage mit id (so schickt es die IDE): Antwort null, danach endet die Schleife wie bei exit;
// - workspace/didChangeConfiguration liest außer dem Abschnitt "dpcc" (Editor-Einstellungen wie bisher) die
//   Projektdaten der IDE (Shell.LspServer.RadStudio.Settings): Sie gehen als dpcc/projectContext an die Wurzel
//   (Delphi-Version, Plattform, Symbole, Suchpfade, Namespaces, Bibliotheks- und Browsing-Pfade, Profil), und gibt
//   es die .dproj, wird sie als Arbeitsbereich angelegt, sofern noch keiner sie hat. Ohne .dproj bleibt es beim
//   Ableiten aus den geöffneten Dateien.
// - Haken des Übersetzers in den Index des Editors: die Symbole einer Unit (kind, detail und DCC_Flags der
//   Vervollständigung, Überladungen einzeln, Ordnung von Aufzählungswerten) und die Deklaration eines Typs nach
//   Namen (Bits für Klassen-, Record-, Interface- und Prozedurtypen). textDocument/implementation beantwortet der
//   Übersetzer selbst über definition (nur im Dialekt; definition läuft nebenläufig, eine Weitergabe aus einem
//   Handler käme über den Responder mit der falschen id zurück).
// Der Server antwortet auf initialize sofort; Projekte und Index laden im Hintergrund (wie im Plugin). Was er nicht
// kann, beantwortet der Verteiler mit -32601 (Methode nicht gefunden); unbekannte Benachrichtigungen verwirft er.
// ReleaseProcessState gibt nach dem Ende die prozessweiten Merker frei (wie TShellInProcessServer.Release); im
// Programm endet ohnehin der Prozess, im Testprogramm bleibt sonst Speicher stehen.

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  dpcc.Common.Logging.Contract,
  dpcc.Common.JsonRpc.Contract,
  Shell.Composition.CompletionServer,
  Shell.LspServer.RadStudio.Dialect,
  Shell.LspServer.RadStudio.Settings,
  Shell.LspServer.DocumentSymbols;

type
  TLspServerHost = class
  public const
    cExitMethod = 'exit';
    cProjectContextMethod = 'dpcc/projectContext';
  private
    FLogger: ILogger;
    FDialect: TRadStudioDialect;
    FTransport: IJsonRpcTransport;
    FRoot: TShellCompletionServer;
    FSymbols: TLspDocumentSymbols;
    FLastProjectKey: string;
    FOnClientProcess: TProc<Cardinal>;
    procedure Attach;
    procedure DidChangeConfiguration(const AParams: TJSONValue);
    procedure ApplyProject(const AProject: TRadStudioProject);
    /// <summary>Gibt es schon einen Arbeitsbereich, der AProjectFile lädt?</summary>
    function HasWorkspaceFor(const AProjectFile: string): Boolean;
    function DispatchNotification(const AMethod: string; AParams: TJSONObject): Boolean;
  public
    /// <summary>Server über AInput (Nachrichten des Clients) und AOutput (eigene); mit AOwnsStreams gibt der
    /// Transport sie frei. ALogger bekommt das Protokoll des Servers (nie stdout).</summary>
    constructor Create(AInput, AOutput: TStream; AOwnsStreams: Boolean; const ALogger: ILogger);
    destructor Destroy; override;
    /// <summary>Verarbeitet Nachrichten bis exit oder Ende der Eingabe; liefert den Exit-Code (0 nach shutdown).
    /// </summary>
    function Run: Integer;
    /// <summary>Prozessweite Merker des Servers freigeben, wenn keiner mehr läuft.</summary>
    class procedure ReleaseProcessState; static;
    property Root: TShellCompletionServer read FRoot;
    property Dialect: TRadStudioDialect read FDialect;
    /// <summary>Nach initialize mit processId (Thread der Verbindung): der Prozess des Clients, etwa zum
    /// Beobachten. Vor Run setzen.</summary>
    property OnClientProcess: TProc<Cardinal> read FOnClientProcess write FOnClientProcess;
  end;

implementation

uses
  System.IOUtils,
  dpcc.Common.JsonRpc.Messages,
  dpcc.Common.JsonRpc.StreamTransport,
  dpcc.Common.Diagnostics.Anonymizer,
  dpcc.Common.Index.Contract,
  dpcc.Common.Index.NameIndex,
  dpcc.Common.Index.Service,
  dpcc.Common.Lsp.Configuration,
  dpcc.Common.Lsp.WorkspaceFolders,
  dpcc.Common.Lsp.PublishedMembers,
  dpcc.Common.Projects.Contract,
  dpcc.Text.LogMarks,
  Shell.Platform,
  Shell.Workspace,
  Shell.Workspace.Listings,
  Shell.Composition.Workspaces;

{ TLspServerHost }

constructor TLspServerHost.Create(AInput, AOutput: TStream; AOwnsStreams: Boolean; const ALogger: ILogger);
begin
  inherited Create;
  FLogger := ALogger;
  FDialect := TRadStudioDialect.Create(TJsonRpcStreamTransport.Create(AInput, AOutput, AOwnsStreams));
  FTransport := FDialect;
  FDialect.OnInitialize :=
    procedure(const AClientName: string; AProcessId: Cardinal)
    begin
      FLogger.Info(Format('initialize von %s (Prozess %d), Dialekt RAD Studio: %s', [TLogMarks.Name(AClientName),
        AProcessId, BoolToStr(SameText(AClientName, TRadStudioDialect.cClientName), True)]));
      if Assigned(FOnClientProcess) and (AProcessId <> 0) then
      begin
        FOnClientProcess(AProcessId);
      end;
    end;
  FRoot := TShellCompletionServer.Create(FTransport, FLogger);
  // Wie CreateForStreams: sammelt die Namen der Projekte für das anonyme Diagnoselog.
  FRoot.Parts.Channel.Anonymizer := TLogAnonymizer.Create(TProcessInfo.IdentityNames);
  Attach;
end;

destructor TLspServerHost.Destroy;
begin
  // Erst die Wurzel (hält Verbindung und Worker), dann die Teile, die ihre Handler benutzen.
  FreeAndNil(FRoot);
  FreeAndNil(FSymbols);
  if FDialect <> nil then
  begin
    FDialect.UnitSymbols := nil;
    FDialect.TypeLookup := nil;
    FDialect.OnInitialize := nil;
  end;
  FDialect := nil;
  FTransport := nil;
  FLogger := nil;
  inherited;
end;

procedure TLspServerHost.Attach;
var
  mParts: TShellCompletionServerParts;
begin
  mParts := FRoot.Parts;
  FSymbols := TLspDocumentSymbols.Create(mParts.Documents);
  FSymbols.Attach(mParts.Protocol.Dispatcher);
  // exit als Anfrage (RAD Studio): antworten, dann wie die Benachrichtigung (Zustand, Ende der Schleife).
  mParts.Protocol.Dispatcher.RegisterRequest(cExitMethod,
    function(const AParams: TJSONValue): TJSONValue
    begin
      DispatchNotification(cExitMethod, nil);
      Result := TJSONNull.Create;
    end);
  mParts.Protocol.Dispatcher.RegisterNotification(TLspConfiguration.cDidChangeConfigurationMethod,
    DidChangeConfiguration);
  // Symbole der Unit einer Vervollständigung für kind, detail und DCC_Flags im Format der IDE.
  FDialect.UnitSymbols :=
    function(const AFileName: string; out ASymbols: TArray<TIndexSymbol>): Boolean
    var
      mIndex: ISymbolIndex;
      mUnit: TUnitIndex;
    begin
      Result := False;
      ASymbols := nil;
      if (FRoot = nil) or (FRoot.Parts.IndexArea = nil) then
      begin
        Exit;
      end;
      mIndex := FRoot.Parts.IndexArea.EditorIndex;
      if (mIndex = nil) or not mIndex.FindFile(AFileName, mUnit) then
      begin
        Exit;
      end;
      ASymbols := mUnit.Symbols;
      Result := True;
    end;
  // Typ einer Variablen, eines Felds oder einer Property nach Namen: Klasse, Record, Interface oder Prozedurtyp.
  FDialect.TypeLookup :=
    function(const ATypeName: string; out ASymbol: TIndexSymbol): Boolean
    var
      mIndex: ISymbolIndex;
      mLocation: TSymbolLocation;
    begin
      Result := False;
      if (FRoot = nil) or (FRoot.Parts.IndexArea = nil) then
      begin
        Exit;
      end;
      mIndex := FRoot.Parts.IndexArea.EditorIndex;
      if mIndex = nil then
      begin
        Exit;
      end;
      for mLocation in mIndex.FindSymbols(ATypeName) do
      begin
        if (mLocation.Symbol.Container = '') and not mLocation.Symbol.Unavailable and
          (mLocation.Symbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
          TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType,
          TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias]) then
        begin
          ASymbol := mLocation.Symbol;
          Exit(True);
        end;
      end;
    end;
end;

function TLspServerHost.DispatchNotification(const AMethod: string; AParams: TJSONObject): Boolean;
var
  mMessage, mResponse: TJSONObject;
begin
  mMessage := TJsonRpcMessages.Notification(AMethod, AParams);
  try
    // Läuft im Thread der Nachrichtenschleife wie eine Meldung des Clients; Benachrichtigungen haben keine Antwort.
    mResponse := FRoot.Parts.Protocol.Dispatcher.DispatchMessage(mMessage);
    mResponse.Free;
    Result := True;
  finally
    mMessage.Free;
  end;
end;

procedure TLspServerHost.DidChangeConfiguration(const AParams: TJSONValue);
var
  mParts: TShellCompletionServerParts;
  mWorkspace: TShellWorkspace;
  mProject: TRadStudioProject;
begin
  mParts := FRoot.Parts;
  // Wie Shell.Composition.Configuration: Abschnitt "dpcc" als Editor-Einstellungen.
  mParts.Core.Settings.SetEditorSettings(TLspConfiguration.EditorSettingsFromParams(AParams));
  for mWorkspace in mParts.Core.Workspaces.Items.ToArray do
  begin
    mWorkspace.Configuration.SetEditorSettings(mParts.Core.Settings.EditorSettings);
  end;
  mProject := TRadStudioProject.FromSettings(AParams);
  if mProject.HasProject then
  begin
    ApplyProject(mProject);
  end;
end;

function TLspServerHost.HasWorkspaceFor(const AProjectFile: string): Boolean;
var
  mRegistry: TShellWorkspaceRegistry;
  mWorkspace: TShellWorkspace;
  mInfo: TProjectInfo;
  mFolder: string;
begin
  // Ein aus den geöffneten Dateien abgeleiteter Ordner lädt die einzige .dproj darin selbst (ohne ProjectFile im
  // Setup): Er zählt wie ein Arbeitsbereich für das Projekt, sonst entstünde ein zweiter für dieselben Units.
  Result := False;
  mFolder := ExcludeTrailingPathDelimiter(ExtractFileDir(AProjectFile));
  mRegistry := FRoot.Parts.Core.Workspaces;
  System.TMonitor.Enter(mRegistry.Lock);
  try
    for mWorkspace in mRegistry.Items do
    begin
      if SameText(mWorkspace.Setup.ProjectFile, AProjectFile) or
        (mWorkspace.State.Project(mInfo) and SameText(mInfo.FileName, AProjectFile)) or
        ((mWorkspace.Setup.ProjectFile = '') and SameText(ExcludeTrailingPathDelimiter(mWorkspace.Root), mFolder)) then
      begin
        Exit(True);
      end;
    end;
  finally
    System.TMonitor.Exit(mRegistry.Lock);
  end;
end;

procedure TLspServerHost.ApplyProject(const AProject: TRadStudioProject);
var
  mParts: TShellCompletionServerParts;
  mContext: TJSONObject;
  mKey: string;
begin
  mParts := FRoot.Parts;
  mContext := AProject.ToContextJson;
  try
    mKey := mContext.ToJSON;
  except
    mContext.Free;
    raise;
  end;
  // Die IDE schickt dieselben Einstellungen zweimal; protokolliert wird nur eine Änderung.
  if mKey <> FLastProjectKey then
  begin
    FLastProjectKey := mKey;
    FLogger.Info('Projekt aus der IDE: ' + TLogMarks.Path(ExtractFileName(AProject.MainFile)) + ' (' +
      AProject.Describe + ')');
  end;
  if not FileExists(AProject.ProjectFile) then
  begin
    mContext.Free;
    FLogger.Info('Keine .dproj neben ' + TLogMarks.Path(ExtractFileName(AProject.MainFile)) +
      '; Arbeitsbereiche aus den geöffneten Dateien');
    Exit;
  end;
  // Erst der Kontext (lädt vorhandene Arbeitsbereiche dieses Projekts neu, wenn er sich ändert), dann der
  // Arbeitsbereich, falls ihn die geöffneten Dateien noch nicht ergeben haben.
  DispatchNotification(cProjectContextMethod, mContext);
  if not HasWorkspaceFor(AProject.ProjectFile) then
  begin
    mParts.Core.Folders.AddAll([TWorkspaceFolder.Create(ExtractFileDir(AProject.ProjectFile),
      ChangeFileExt(ExtractFileName(AProject.ProjectFile), ''), AProject.ProjectFile)]);
    mParts.Core.Configuration.UpdateWatchedFiles;
  end;
end;

function TLspServerHost.Run: Integer;
begin
  Result := FRoot.Run;
end;

class procedure TLspServerHost.ReleaseProcessState;
begin
  // Wie TShellInProcessServer.Release mit dem letzten Server.
  TPublishedMembers.UseCache(False);
  TImportNames.Clear;
  TIndexService.ForgetSharedStates;
  TSharedUnitListings.Clear;
end;

end.
