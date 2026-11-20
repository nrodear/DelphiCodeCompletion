unit Shell.Composition.ClientStart;

// Start des Clients nach initialized: Name, Fähigkeiten und Editor-Einstellungen aus initialize, Projektkontext der
// IDE, erste Arbeitsbereiche und Beobachtung der Dateien. Seit Schritt 2 bekommt
// es die beteiligten Teile einzeln (TShellClientStartParts) statt aller Teile der alten Komposition; so nutzen es die
// alte Wurzel (Shell.Composition) und die Wurzel der Completion (Shell.Composition.CompletionServer). Die gemeldeten
// Projekte legt es zusammen an (TShellFolders.AddAll), damit requires-Packages unabhängig von der Reihenfolge
// gefunden werden.

interface

uses
  System.SysUtils,
  System.JSON,
  dpcc.Common.Logging.Contract,
  dpcc.Common.Lsp.Lifecycle,
  dpcc.Common.Lsp.IdeProject,
  dpcc.Common.Lsp.Hover,
  dpcc.Common.Lsp.Completion,
  Shell.Composition.CoreBase,
  Shell.Composition.Session,
  Shell.Composition.FileChanges;

type
  /// <summary>Die Teile, die der Start des Clients anfasst; alle müssen bestehen.</summary>
  TShellClientStartParts = record
    Logger: ILogger;
    Lifecycle: TLspLifecycle;
    Session: TShellSession;
    Core: TShellCoreBase;
    IdeProject: TLspIdeProject;
    FileChanges: TShellFileChanges;
    Hover: TLspHover;
    Completion: TLspCompletion;
    /// <summary>Ordner aus geöffneten Dateien ableiten (RAD Studio, #175)? Gesetzt vor dem ersten Laden.</summary>
    SetDeriveWorkspaces: TProc<Boolean>;
  end;

  /// <summary>Was nach initialized mit den Teilen der Komposition geschieht.</summary>
  TShellClientStart = class abstract
  private
    /// <summary>Name, Fähigkeiten und Editor-Einstellungen des Clients aus initialize.</summary>
    class procedure ApplyClientInfo(const AParts: TShellClientStartParts; const AParams: TJSONObject); static;
  public
    /// <summary>Nach initialized: Client, Einstellungen, Beobachtung und erste Arbeitsbereiche.</summary>
    class procedure Initialized(const AParts: TShellClientStartParts); static;
  end;

implementation

uses
  dpcc.Common.Lsp.WorkspaceFolders,
  dpcc.Common.Lsp.Configuration,
  dpcc.Common.Lsp.Completion.Details;

class procedure TShellClientStart.Initialized(const AParts: TShellClientStartParts);
var
  mParams: TJSONObject;
  mFolders: TArray<TWorkspaceFolder>;
  mFolder: TWorkspaceFolder;
  mDerive: Boolean;
begin
  mParams := AParts.Lifecycle.InitializeParams;
  ApplyClientInfo(AParts, mParams);
  mFolders := TLspWorkspaceFolders.FromInitialize(mParams);
  // Vor dem ersten Laden, damit die Projekte nicht zweimal indiziert werden (#396).
  AParts.IdeProject.LoadInitialize(mParams);
  // Meldet der Client nur Projektdateien (IDE-Plugin, #648), bekommen Dateien außerhalb dieser
  // Projekte weiter einen abgeleiteten Arbeitsbereich.
  mDerive := True;
  for mFolder in mFolders do
  begin
    if mFolder.ProjectFile = '' then
    begin
      mDerive := False;
    end;
  end;
  AParts.SetDeriveWorkspaces(mDerive);
  if Length(mFolders) = 0 then
  begin
    AParts.Logger.Info('Kein Arbeitsbereichsordner gemeldet; Ordner werden aus den geöffneten Dateien abgeleitet');
  end;
  AParts.Core.Configuration.Start;
  // Alle auf einmal: Das zuerst angelegte (aktive) Projekt kennt so die Ordner der übrigen und findet die .dpk seiner
  // requires (Sprung in ein anderes Package).
  AParts.Core.Folders.AddAll(mFolders);
  AParts.Core.Configuration.UpdateWatchedFiles;
  AParts.FileChanges.RegisterWatchers(mParams);
end;

class procedure TShellClientStart.ApplyClientInfo(const AParts: TShellClientStartParts; const AParams: TJSONObject);
begin
  if AParams <> nil then
  begin
    // Name des Clients für die Anmeldung am Index-Cache (#62); vor dem Anlegen der Arbeitsbereiche.
    AParts.Session.ClientName := AParams.GetValue<string>('clientInfo.name', '');
  end;
  // Sprache des Clients (#1458) vor SetEditorSettings, das die Sprache der Texte wählt.
  AParts.Core.Settings.SetClientLocale(TLspClientLocale.FromInitialize(AParams));
  // Editor-Ebene: initializationOptions.settings.dpcc wie bei didChangeConfiguration, schon vor dem
  // ersten Indexaufbau; sie zählt wie global (TConfigurationScopes). Das IDE-Plugin schickt keine
  // Einstellungen mehr: Es schreibt settings.json, die der Server selbst liest und beobachtet.
  if AParams <> nil then
  begin
    AParts.Core.Settings.SetEditorSettings(
      TLspConfiguration.EditorSettingsFromParams(AParams.GetValue('initializationOptions')));
  end
  else
  begin
    // Ohne Parameter bleibt die Editor-Ebene leer; die Einstellungen ohne Arbeitsbereich gelten trotzdem neu.
    AParts.Core.Settings.SetEditorSettings(AParts.Core.Settings.EditorSettings);
  end;
  AParts.Hover.Markdown := TLspHover.ClientSupportsMarkdown(AParams);
  // Code-Vorlagen mit Platzhaltern nur an Clients mit snippetSupport (#51).
  AParts.Completion.Hooks.SnippetSupport := TLspCompletion.ClientSupportsSnippets(AParams);
  AParts.Completion.Hooks.DocumentationMarkdown := TCompletionDetails.ClientPrefersMarkdown(AParams);
end;

end.
