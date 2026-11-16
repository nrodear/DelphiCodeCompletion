unit Shell.Composition.LanguageOptions;

// Internals-Rolle Shell: Sprachvorgaben je Datei, die auch der schlanke Kern der Completion braucht: Delphi-Version
// (#47), Sprachstand (#1126) und Doku-Kommentare (#88). Ohne Formatierung und ohne
// Regel-Engine; TShellFileOptions erbt davon und ergänzt Formatstil, Einrückung, gelernte Vorschläge und Präfixe.

interface

uses
  dpcc.Common.Editing.Contract,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings;

type
  /// <summary>Sprachvorgaben je Datei aus dem Arbeitsbereich bzw. den Einstellungen ohne Ordner.</summary>
  TShellLanguageOptions = class
  protected
    FWorkspaces: TShellWorkspaceRegistry;
    FSettings: TShellSettings;
  public
    constructor Create(AWorkspaces: TShellWorkspaceRegistry; ASettings: TShellSettings);
    /// <summary>Tatsächlich gewählte Installation (#47), sonst die konfigurierte Version; '' ohne Arbeitsbereich.
    /// </summary>
    function DelphiVersionFor(const AUri: string): string;
    /// <summary>Sprachstand (#1126): die ältere aus DelphiVersionFor und minDelphiVersion des Projekts. Gilt für
    /// Diagnosen, Code-Aktionen, Schnellbefehle und Formatieren; Hover und Hilfe-Links nehmen DelphiVersionFor.
    /// </summary>
    function LanguageLevelFor(const AUri: string): string;
    /// <summary>"completeBlocks.docComment" (#88).</summary>
    function DocCommentsFor(const AUri: string): Boolean;
  end;

implementation

uses
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Pascal.LanguageFeatures,
  Shell.Workspace;

constructor TShellLanguageOptions.Create(AWorkspaces: TShellWorkspaceRegistry; ASettings: TShellSettings);
begin
  inherited Create;
  FWorkspaces := AWorkspaces;
  FSettings := ASettings;
end;

function TShellLanguageOptions.DelphiVersionFor(const AUri: string): string;
var
  mWorkspace: TShellWorkspace;
begin
  System.TMonitor.Enter(FWorkspaces.Lock);
  try
    mWorkspace := FWorkspaces.Pick(TDocumentUris.ToPath(AUri));
    Result := '';
    if mWorkspace <> nil then
    begin
      Result := mWorkspace.State.DelphiVersion;
      if Result = '' then
      begin
        Result := mWorkspace.Configuration.Settings.DelphiVersion;
      end;
    end;
  finally
    System.TMonitor.Exit(FWorkspaces.Lock);
  end;
end;

function TShellLanguageOptions.LanguageLevelFor(const AUri: string): string;
begin
  Result := TLanguageFeatures.LanguageLevel(DelphiVersionFor(AUri), FSettings.SettingsFor(AUri).MinDelphiVersion);
end;

function TShellLanguageOptions.DocCommentsFor(const AUri: string): Boolean;
begin
  Result := FSettings.SettingsFor(AUri).CompleteBlocksDocComment;
end;

end.
