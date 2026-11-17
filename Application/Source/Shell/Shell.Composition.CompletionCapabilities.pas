unit Shell.Composition.CompletionCapabilities;

// Capabilities der Wurzel der Completion (Schritt 2): Sie folgen aus dem, was am Verteiler hängt. Gemeldet werden nur
// Synchronisation, Ordner des Arbeitsbereichs, Vervollständigung samt resolve, Hover, Parameterhilfe und die
// Sprungziele (definition, declaration, typeDefinition; Auftrag NAV); dazu unter experimental.dpcc die Eigenmethoden
// (dpcc/…), die der Server versteht. Kein executeCommand, keine Diagnosen,
// keine Code-Aktionen. Die Capabilities der alten Wurzel stehen weiter in Shell.Composition.Capabilities.

interface

uses
  System.JSON;

type
  /// <summary>Baut die Capabilities für initialize aus den angemeldeten Anfragen.</summary>
  TShellCompletionCapabilities = class
  public
    /// <summary>Neue Capabilities; der Aufrufer gibt sie frei. ARequests: die Anfragen am Verteiler
    /// (TJsonRpcDispatcher.Methods); ANotifications: die angemeldeten Eigen-Benachrichtigungen (dpcc/…).</summary>
    class function Build(const ARequests, ANotifications: TArray<string>): TJSONObject; static;
    /// <summary>Vervollständigung ohne das Auslösezeichen "/" der Schnellbefehle (#293), die hier fehlen.</summary>
    class function CompletionCapability: TJSONObject; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  dpcc.Common.Lsp.TextDocumentSync,
  dpcc.Common.Lsp.Completion,
  dpcc.Common.Lsp.Hover,
  dpcc.Common.Lsp.SignatureHelp,
  dpcc.Common.Lsp.Definition,
  dpcc.Common.Lsp.WorkspaceFolders;

/// <summary>Liste der Methoden mit dem Präfix "dpcc/" als JSON.</summary>
function DpccMethods(const AMethods: TArray<string>): TJSONArray;
var
  mMethod: string;
begin
  Result := TJSONArray.Create;
  for mMethod in AMethods do
  begin
    if StartsText('dpcc/', mMethod) then
    begin
      Result.Add(mMethod);
    end;
  end;
end;

class function TShellCompletionCapabilities.CompletionCapability: TJSONObject;
var
  mTriggers: TJSONArray;
  mKept: TJSONArray;
  mTrigger: TJSONValue;
begin
  Result := TLspCompletion.Capability;
  if not Result.TryGetValue<TJSONArray>('triggerCharacters', mTriggers) then
  begin
    Exit;
  end;
  mKept := TJSONArray.Create;
  for mTrigger in mTriggers do
  begin
    if mTrigger.Value <> '/' then
    begin
      mKept.Add(mTrigger.Value);
    end;
  end;
  Result.RemovePair('triggerCharacters').Free;
  Result.AddPair('triggerCharacters', mKept);
end;

class function TShellCompletionCapabilities.Build(const ARequests, ANotifications: TArray<string>): TJSONObject;
var
  mExperimental: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('textDocumentSync', TLspTextDocumentSync.Capability);
  if MatchText(TLspCompletion.cMethod, ARequests) then
  begin
    Result.AddPair('completionProvider', CompletionCapability);
  end;
  if MatchText(TLspHover.cMethod, ARequests) then
  begin
    Result.AddPair('hoverProvider', TJSONBool.Create(True));
  end;
  if MatchText(TLspSignatureHelp.cMethod, ARequests) then
  begin
    Result.AddPair('signatureHelpProvider', TLspSignatureHelp.Capability);
  end;
  // Sprungziele (NAV): Ohne definitionProvider fragt die IDE-Seite (Strg+Klick) gar nicht erst.
  if MatchText(TLspDefinition.cDefinitionMethod, ARequests) then
  begin
    Result.AddPair('definitionProvider', TJSONBool.Create(True));
  end;
  if MatchText(TLspDefinition.cDeclarationMethod, ARequests) then
  begin
    Result.AddPair('declarationProvider', TJSONBool.Create(True));
  end;
  if MatchText(TLspDefinition.cTypeDefinitionMethod, ARequests) then
  begin
    Result.AddPair('typeDefinitionProvider', TJSONBool.Create(True));
  end;
  Result.AddPair('workspace', TLspWorkspaceFolders.Capability);
  // Eigenmethoden für das IDE-Plugin; Clients ohne dpcc übergehen experimental.
  mExperimental := TJSONObject.Create;
  mExperimental.AddPair('requests', DpccMethods(ARequests));
  mExperimental.AddPair('notifications', DpccMethods(ANotifications));
  Result.AddPair('experimental', TJSONObject.Create(TJSONPair.Create('dpcc', mExperimental)));
end;

end.
