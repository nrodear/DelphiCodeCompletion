unit Shell.Composition.Ide;

// Internals-Rolle Shell: Nachrichten aus der IDE. Der Projektkontext (#396), der betroffene Projekte neu lädt,
// neue Präfixe aus .dpcc (#1111) und die Typen aus den Packages der IDE (dpcc/ideTypes). Ist der Index fertig,
// fragt sie nach den Mitgliedern der Units ohne Quelltext (dpcc/ideMembersWanted); die Antwort (dpcc/ideMembers)
// wird zu Ersatz-Units für Hover, Vervollständigung und Parameterhilfe. Build-Nachrichten der IDE
// (dpcc/compileStarted, dpcc/compileFinished, dpcc/compilerMessages) meldet der Server nicht mehr an; der
// Verteiler verwirft sie still (R1, K8).
// L2: Die IDE meldet auch die Typen der Installation ohne Quelltext (DUnitX, FireDAC …). Mitglieder fragt der Server
// nur für Units, die eine geladene Unit des Index in ihren uses nennt (bei Bedarf); die Namen aller Typen kennt er
// über dpcc/ideTypes sofort.

interface

uses
  System.JSON,
  dpcc.Common.Logging.Contract,
  dpcc.Common.Index.Contract,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.Lsp.IdeProject,
  dpcc.Common.Lsp.IdeTypes,
  dpcc.Common.Lsp.IdeUnits,
  Shell.Workspace,
  Shell.Composition.Workspaces;

type
  TShellIdeRefreshProc = reference to procedure;
  /// <summary>Benachrichtigung an die IDE; übernimmt AParams.</summary>
  TShellIdeNotifyProc = reference to procedure(const AMethod: string; AParams: TJSONObject);

  /// <summary>Was die IDE-Nachrichten von der Komposition brauchen.</summary>
  TShellIdeServices = record
    Logger: ILogger;
    Workspaces: TShellWorkspaceRegistry;
    /// <summary>Namenskonvention geändert: offene Dateien neu prüfen. Wie TypesChanged optional (Wurzel der
    /// Completion ohne Diagnosen, Schritt 2).</summary>
    NamingChanged: TShellIdeRefreshProc;
    /// <summary>Typen der IDE geändert: offene Dateien neu prüfen.</summary>
    TypesChanged: TShellIdeRefreshProc;
    /// <summary>Ersatz-Units der IDE und gemeinsamer Index (ohne sie).</summary>
    IdeUnits: TIdeUnits;
    Index: ISymbolIndex;
    Notify: TShellIdeNotifyProc;
  end;

  /// <summary>Projektkontext und Typen aus der IDE.</summary>
  TShellIde = class
  private
    FServices: TShellIdeServices;
    FProject: TLspIdeProject;
    FTypes: TLspIdeTypes;
    // Der Index ist einmal ganz aufgebaut; erst dann gilt eine Unit ohne Eintrag als ohne Quelltext.
    FIndexFinished: Boolean;
    /// <summary>Arbeitsbereiche, deren Projekt AProject ist.</summary>
    function WorkspacesOfProject(const AProject: string): TArray<TShellWorkspace>;
    procedure ProjectChanged(const AContext: TIdeProjectContext);
    procedure NamingChanged(const AContext: TIdeProjectContext);
    procedure TypesChanged(ACount: Integer);
    /// <summary>Fragt nach den Mitgliedern der Units aus dem Typkatalog, die der Index nicht kennt.</summary>
    procedure RequestMembers;
    procedure MembersChanged(ACount: Integer);
  public
    constructor Create(const AServices: TShellIdeServices);
    destructor Destroy; override;
    /// <summary>Meldet die Nachrichten der IDE am Dispatcher an.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Der Indexaufbau ist fertig: nach den Units ohne Quelltext fragen.</summary>
    procedure IndexFinished;
    property Project: TLspIdeProject read FProject;
    /// <summary>Typen aus den Packages der IDE (dpcc/ideTypes).</summary>
    property Types: TLspIdeTypes read FTypes;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Common.Projects.Contract,
  dpcc.Text.LogMarks;

constructor TShellIde.Create(const AServices: TShellIdeServices);
begin
  inherited Create;
  FServices := AServices;
  // Konfiguration, Plattform und Optionen aus der IDE (#396): betroffene Projekte neu laden.
  FProject := TLspIdeProject.Create;
  FProject.OnChanged := ProjectChanged;
  // Neue Präfixe aus .dpcc (#1111): naming-prefix und shadowed-name prüfen neu, das Projekt bleibt geladen.
  FProject.OnNamingChanged := NamingChanged;
  // Typen aus den Packages der IDE: unresolved-type und unresolved-identifier schweigen für sie, offene Dateien
  // prüfen neu.
  FTypes := TLspIdeTypes.Create;
  FTypes.OnChanged := TypesChanged;
  if FServices.IdeUnits <> nil then
  begin
    FServices.IdeUnits.OnChanged := MembersChanged;
  end;
end;

destructor TShellIde.Destroy;
begin
  FreeAndNil(FProject);
  FreeAndNil(FTypes);
  inherited Destroy;
end;

procedure TShellIde.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FProject.Attach(ADispatcher);
  FTypes.Attach(ADispatcher);
  if FServices.IdeUnits <> nil then
  begin
    FServices.IdeUnits.Attach(ADispatcher);
  end;
end;

function TShellIde.WorkspacesOfProject(const AProject: string): TArray<TShellWorkspace>;
var
  mWorkspace: TShellWorkspace;
  mProject: TProjectInfo;
begin
  Result := nil;
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    for mWorkspace in FServices.Workspaces.Items do
    begin
      if SameText(mWorkspace.Setup.ProjectFile, AProject) or
        (mWorkspace.State.Project(mProject) and SameText(mProject.FileName, AProject)) then
      begin
        Result := Result + [mWorkspace];
      end;
    end;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
end;

procedure TShellIde.ProjectChanged(const AContext: TIdeProjectContext);
var
  mWorkspace: TShellWorkspace;
begin
  FServices.Logger.Info(Format('Projektkontext aus der IDE: %s (%s, %s)',
    [TLogMarks.Path(ExtractFileName(AContext.Project)),
      TLogMarks.Name(AContext.Configuration), TLogMarks.Name(AContext.Platform)]));
  for mWorkspace in WorkspacesOfProject(AContext.Project) do
  begin
    mWorkspace.Reload;
  end;
end;

procedure TShellIde.NamingChanged(const AContext: TIdeProjectContext);
begin
  if Assigned(FServices.NamingChanged) then
  begin
    FServices.NamingChanged();
  end;
end;

procedure TShellIde.TypesChanged(ACount: Integer);
begin
  FServices.Logger.Info(Format('IDE-Typen: %d', [ACount]));
  if Assigned(FServices.TypesChanged) then
  begin
    FServices.TypesChanged();
  end;
  if FIndexFinished then
  begin
    RequestMembers;
  end;
end;

procedure TShellIde.IndexFinished;
begin
  FIndexFinished := True;
  RequestMembers;
end;

/// <summary>Units der Einträge ohne Doppelte, in der Reihenfolge des Katalogs.</summary>
function UnitsOf(const AEntries: TArray<TIdeTypeEntry>): TArray<string>;
var
  mSeen: TDictionary<string, Boolean>;
  mEntry: TIdeTypeEntry;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mEntry in AEntries do
    begin
      if not mSeen.ContainsKey(UpperCase(mEntry.UnitName)) then
      begin
        mSeen.Add(UpperCase(mEntry.UnitName), True);
        Result := Result + [mEntry.UnitName];
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

/// <summary>Unit-Namen (groß) aus den uses der gepinnten Units von AIndex (Projekte und ihre Hülle, L2).</summary>
function UsedNames(const AIndex: ISymbolIndex): TDictionary<string, Boolean>;
var
  mStored: TIndexStoredUnit;
  mName: string;
begin
  Result := TDictionary<string, Boolean>.Create;
  if AIndex = nil then
  begin
    Exit;
  end;
  for mStored in AIndex.StoredUnits do
  begin
    if not mStored.Pinned then
    begin
      Continue;
    end;
    for mName in mStored.Unit_.InterfaceUses + mStored.Unit_.ImplementationUses do
    begin
      Result.AddOrSetValue(UpperCase(mName), True);
    end;
  end;
end;

/// <summary>Die Units aus ACandidates, die AUsed nennt.</summary>
function UsedOnly(const ACandidates: TArray<string>; AUsed: TDictionary<string, Boolean>): TArray<string>;
var
  mUnit: string;
begin
  Result := nil;
  for mUnit in ACandidates do
  begin
    if AUsed.ContainsKey(UpperCase(mUnit)) then
    begin
      Result := Result + [mUnit];
    end;
  end;
end;

procedure TShellIde.RequestMembers;
var
  mUsed: TDictionary<string, Boolean>;
  mWanted: TArray<string>;
  mParams: TJSONObject;
  mUnits: TJSONArray;
  mUnit: string;
begin
  if (FServices.IdeUnits = nil) or not Assigned(FServices.Notify) then
  begin
    Exit;
  end;
  // L2: nur Units, die die Projekte nennen; die übrigen kennt "+ Unit" über ihre Typnamen.
  mUsed := UsedNames(FServices.Index);
  try
    mWanted := FServices.IdeUnits.Wanted(UsedOnly(UnitsOf(FTypes.Catalog.Entries), mUsed), FServices.Index);
  finally
    mUsed.Free;
  end;
  if mWanted = nil then
  begin
    Exit;
  end;
  mUnits := TJSONArray.Create;
  for mUnit in mWanted do
  begin
    mUnits.Add(mUnit);
  end;
  mParams := TJSONObject.Create;
  mParams.AddPair('units', mUnits);
  FServices.Logger.Info(Format('IDE-Units ohne Quelltext erfragt: %d', [Length(mWanted)]));
  FServices.Notify(TIdeUnits.cWantedMethod, mParams);
end;

procedure TShellIde.MembersChanged(ACount: Integer);
begin
  FServices.Logger.Info(Format('IDE-Ersatz-Units: %d', [ACount]));
end;

end.
