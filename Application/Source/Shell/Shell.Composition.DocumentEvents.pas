unit Shell.Composition.DocumentEvents;

// Ereignisse des Dokumentspeichers: Tipp-Pause im Index (#492), abgeleitete und
// zurückgestellte Arbeitsbereiche (#175, #648), Index und Compiler nach dem Speichern (#500, #40) und Änderungen an
// dpcc.json. Ohne eigenen Zustand: Attach meldet einen Hörer an, der die Dienste festhält. Seit Schritt 2 kennt es
// nur den schlanken Kern (TShellCoreBase) und kompiliert nach dem Speichern über einen optionalen Rückruf; so nutzt
// es auch die Wurzel der Completion, die keinen Compiler hat.

interface

uses
  dpcc.Common.Documents.Contract,
  Shell.Workspace,
  Shell.Composition.CoreBase,
  Shell.Composition.FileChanges;

type
  /// <summary>Der Kern; besteht, sobald Ereignisse kommen.</summary>
  TShellDocumentCoreFunc = reference to function: TShellCoreBase;
  /// <summary>Compilerlauf nach dem Speichern von AFileName (#40).</summary>
  TShellDocumentCompileProc = reference to procedure(const AFileName: string);
  /// <summary>Dateiänderungen und Tipp-Pause; nil, solange sie noch nicht bestehen.</summary>
  TShellDocumentFileChangesFunc = reference to function: TShellFileChanges;
  /// <summary>Ordner aus geöffneten Dateien ableiten (RAD Studio, #175)?</summary>
  TShellDocumentDeriveFunc = reference to function: Boolean;

  /// <summary>Was die Ereignisse der Dokumente brauchen; die Funktionen fragen erst beim Ereignis.</summary>
  TShellDocumentEventServices = record
    Core: TShellDocumentCoreFunc;
    /// <summary>Optional: kompiliert nach dem Speichern, wenn compiler.onSave gilt; nil = nie.</summary>
    CompileOnSave: TShellDocumentCompileProc;
    FileChanges: TShellDocumentFileChangesFunc;
    DeriveWorkspaces: TShellDocumentDeriveFunc;
  end;

  /// <summary>Verteilt die Ereignisse des Dokumentspeichers.</summary>
  TShellDocumentEvents = class
  private
    class procedure IndexEvent(const AServices: TShellDocumentEventServices; AKind: TDocumentEventKind;
      const AFileName, AText: string); static;
    class procedure SourceSaved(const AServices: TShellDocumentEventServices; const AFileName: string); static;
    class function LockedWorkspaceOf(ACore: TShellCoreBase; const AFileName: string): TShellWorkspace; static;
  public
    /// <summary>Meldet am Dokumentspeicher einen Hörer an, der AServices festhält.</summary>
    class procedure Attach(const ADocuments: IDocumentStore; const AServices: TShellDocumentEventServices); static;
    /// <summary>Ein Ereignis an ADocument verteilen.</summary>
    class procedure Handle(const AServices: TShellDocumentEventServices; AKind: TDocumentEventKind;
      const ADocument: ITextDocument); static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Index.Contract;

class procedure TShellDocumentEvents.Attach(const ADocuments: IDocumentStore;
  const AServices: TShellDocumentEventServices);
var
  mServices: TShellDocumentEventServices;
begin
  mServices := AServices;
  ADocuments.Subscribe(
    procedure(AKind: TDocumentEventKind; const ADocument: ITextDocument)
    begin
      Handle(mServices, AKind, ADocument);
    end);
end;

class procedure TShellDocumentEvents.Handle(const AServices: TShellDocumentEventServices; AKind: TDocumentEventKind;
  const ADocument: ITextDocument);
var
  mFileName: string;
begin
  mFileName := TDocumentUris.ToPath(ADocument.Uri);
  if StartsText('file:', ADocument.Uri) then
  begin
    IndexEvent(AServices, AKind, mFileName, ADocument.Text);
  end;
  // Nach dem Speichern einer Quelldatei kompilieren (#40), abschaltbar über compiler.onSave.
  if (AKind = TDocumentEventKind.Saved) and MatchText(ExtractFileExt(mFileName), ['.pas', '.dpr', '.dpk', '.inc']) then
  begin
    SourceSaved(AServices, mFileName);
  end
  else if IsConfigurationFileName(ExtractFileName(mFileName)) then
  begin
    AServices.Core().Configuration.DocumentEvent(AKind, ADocument);
  end;
end;

class function TShellDocumentEvents.LockedWorkspaceOf(ACore: TShellCoreBase; const AFileName: string): TShellWorkspace;
begin
  System.TMonitor.Enter(ACore.Workspaces.Lock);
  try
    Result := ACore.Workspaces.WorkspaceOf(AFileName);
  finally
    System.TMonitor.Exit(ACore.Workspaces.Lock);
  end;
end;

class procedure TShellDocumentEvents.IndexEvent(const AServices: TShellDocumentEventServices;
  AKind: TDocumentEventKind; const AFileName, AText: string);
var
  mFileChanges: TShellFileChanges;
  mWorkspace: TShellWorkspace;
begin
  // Tipp-Pause (#492): ungespeicherten Stand in den Index; beim Schließen wieder den der Platte.
  mFileChanges := AServices.FileChanges();
  if mFileChanges <> nil then
  begin
    mFileChanges.DocumentEvent(AKind, AFileName, AText);
  end;
  if AKind <> TDocumentEventKind.Opened then
  begin
    Exit;
  end;
  if AServices.DeriveWorkspaces() then
  begin
    AServices.Core().Folders.Derive(AFileName);
  end;
  // Zurückgestelltes Projekt der Gruppe (index.projectGroup = false): jetzt indizieren (#648).
  mWorkspace := LockedWorkspaceOf(AServices.Core(), AFileName);
  // Nur der Thread der Nachrichtenschleife entfernt Arbeitsbereiche; mWorkspace bleibt gültig.
  if (mWorkspace <> nil) and mWorkspace.Setup.Deferred then
  begin
    mWorkspace.Activate;
  end;
end;

class procedure TShellDocumentEvents.SourceSaved(const AServices: TShellDocumentEventServices;
  const AFileName: string);
var
  mCore: TShellCoreBase;
  mWorkspace: TShellWorkspace;
  mOnSave: Boolean;
begin
  mCore := AServices.Core();
  // Index nachziehen (#500): Clients ohne Dateiüberwachung (IDE-Plugin) melden nur das Speichern;
  // bei einer .inc liest der Index die einbindenden Units neu ein.
  if not SameText(ExtractFileExt(AFileName), '.dpk') then
  begin
    AServices.FileChanges().Handle([TFileChange.Create(AFileName, TFileChangeKind.Changed)]);
  end;
  System.TMonitor.Enter(mCore.Workspaces.Lock);
  try
    mWorkspace := mCore.Workspaces.WorkspaceOf(AFileName);
    mOnSave := (mWorkspace <> nil) and mWorkspace.Configuration.Settings.Compiler.OnSave;
  finally
    System.TMonitor.Exit(mCore.Workspaces.Lock);
  end;
  if mOnSave and Assigned(AServices.CompileOnSave) then
  begin
    AServices.CompileOnSave(AFileName);
  end;
end;

end.
