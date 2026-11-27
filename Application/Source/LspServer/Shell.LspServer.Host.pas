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
  System.Generics.Collections,
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
    /// <summary>Delphi-Version (z. B. "23.0") der IDE AExeFile (…\bin\bds.exe): die aus AInstalled (Version,
    /// Installationsordner), deren Ordner den Ordner bin enthält; '' ohne Treffer.</summary>
    class function BdsVersionOfIde(const AExeFile: string;
      const AInstalled: TArray<TPair<string, string>>): string; static;
    /// <summary>Wie oben für den Prozess AProcessId (processId aus initialize) und die installierten Versionen;
    /// '' wenn er nicht zu öffnen ist.</summary>
    class function BdsVersionOfProcess(AProcessId: Cardinal): string; static;
    property Root: TShellCompletionServer read FRoot;
    property Dialect: TRadStudioDialect read FDialect;
    /// <summary>Nach initialize mit processId (Thread der Verbindung): der Prozess des Clients, etwa zum
    /// Beobachten. Vor Run setzen.</summary>
    property OnClientProcess: TProc<Cardinal> read FOnClientProcess write FOnClientProcess;
  end;

implementation

uses
{$IFDEF MSWINDOWS}
  Winapi.Windows,
{$ENDIF}
  System.IOUtils,
  System.StrUtils,
  dpcc.Common.Lsp.IdeProject,
  dpcc.Common.Lsp.CompletionCollector,
  Shell.Composition.Ide,
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

const
  /// <summary>Höchstzahl der Einträge einer Vervollständigung für RAD Studio (CompletionMaxItems); DelphiLSP
  /// schickte im Testprojekt 2475 Bezeichner und 2381 Units.</summary>
  cRadStudioMaxItems = 5000;

{ TLspServerHost }

constructor TLspServerHost.Create(AInput, AOutput: TStream; AOwnsStreams: Boolean; const ALogger: ILogger);
begin
  inherited Create;
  FLogger := ALogger;
  FDialect := TRadStudioDialect.Create(TJsonRpcStreamTransport.Create(AInput, AOutput, AOwnsStreams));
  FTransport := FDialect;
  FDialect.OnInitialize :=
    procedure(const AClientName: string; AProcessId: Cardinal)
    var
      mVersion: string;
    begin
      FLogger.Info(Format('initialize von %s (Prozess %d), Dialekt RAD Studio: %s', [TLogMarks.Name(AClientName),
        AProcessId, BoolToStr(SameText(AClientName, TRadStudioDialect.cClientName), True)]));
      // Die IDE schickt ihre Projektdaten erst nach den ersten Dateien: Ihre Version schon jetzt festlegen, sonst
      // begänne der Index nach der ProjectVersion der .dproj mit einer anderen Installation (Stufe 4).
      if SameText(AClientName, TRadStudioDialect.cClientName) and (FRoot <> nil) then
      begin
        mVersion := '';
        if AProcessId <> 0 then
        begin
          mVersion := BdsVersionOfProcess(AProcessId);
        end;
        FRoot.Parts.Ide.Project.ClientBdsVersion := mVersion;
        // Auch wenn die Version hier unbekannt bleibt: Wechselt sie mit den Projektdaten, bleibt nichts gemischt.
        FRoot.Parts.Ide.Project.SeparateInstallations := True;
        FLogger.Info(Format('Delphi-Version der IDE: %s', [IfThen(mVersion = '', 'unbekannt', mVersion)]));
        // Wie DelphiLSP die ganze Liste (Bezeichner, Units der uses-Klausel), nicht nur die ersten 1000.
        CompletionMaxItems := cRadStudioMaxItems;
      end;
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
  CompletionMaxItems := cCompletionMaxItems;
end;

class function TLspServerHost.BdsVersionOfIde(const AExeFile: string;
  const AInstalled: TArray<TPair<string, string>>): string;
var
  mFolder: string;
  mPair: TPair<string, string>;
begin
  Result := '';
  // …\<Installation>\bin\bds.exe
  mFolder := ExcludeTrailingPathDelimiter(ExtractFileDir(ExtractFileDir(AExeFile)));
  if mFolder = '' then
  begin
    Exit;
  end;
  for mPair in AInstalled do
  begin
    if (mPair.Value <> '') and SameText(ExcludeTrailingPathDelimiter(mPair.Value), mFolder) then
    begin
      Exit(mPair.Key);
    end;
  end;
end;

{$IFDEF MSWINDOWS}
const
  /// <summary>PROCESS_QUERY_LIMITED_INFORMATION (fehlt in Winapi.Windows): reicht für den Pfad des Programms.
  /// </summary>
  cProcessQueryLimitedInformation = $1000;

function QueryImageName(hProcess: THandle; dwFlags: DWORD; lpExeName: PWideChar; var lpdwSize: DWORD): BOOL;
  stdcall; external kernel32 name 'QueryFullProcessImageNameW';
{$ENDIF}

class function TLspServerHost.BdsVersionOfProcess(AProcessId: Cardinal): string;
{$IFDEF MSWINDOWS}
var
  mProcess: THandle;
  mBuffer: array[0..MAX_PATH * 4] of WideChar;
  mSize: DWORD;
  mInstalled: TArray<TPair<string, string>>;
  mVersion: string;
begin
  Result := '';
  mProcess := OpenProcess(cProcessQueryLimitedInformation, False, AProcessId);
  if mProcess = 0 then
  begin
    Exit;
  end;
  try
    mSize := Length(mBuffer);
    if not QueryImageName(mProcess, 0, mBuffer, mSize) then
    begin
      Exit;
    end;
  finally
    CloseHandle(mProcess);
  end;
  mInstalled := nil;
  for mVersion in TDelphiInstallation.Versions do
  begin
    mInstalled := mInstalled + [TPair<string, string>.Create(mVersion, TDelphiInstallation.RootDirOf(mVersion))];
  end;
  Result := BdsVersionOfIde(string(PWideChar(@mBuffer[0])), mInstalled);
end;
{$ELSE}
begin
  Result := '';
end;
{$ENDIF}

end.
