unit dpcc.Core.Lsp.Session;

// LSP-Sitzung des IDE-Plugins: initialize, Dokumentabgleich und die
// Anfragen, die die IDE über den Code Insight-Manager stellt.
// Abgleich: Vor jeder Anfrage wird der aktuelle Editortext geschickt, beim
// ersten Mal als didOpen, danach als didChange mit dem geänderten Bereich
// (#395, TLspTextChanges), aber nur, wenn er sich geändert hat. Positionen
// sind 0-basiert in UTF-16-Einheiten (Delphi-String-Indizes), wie LSP sie
// erwartet.
// Diagnosen (#398) holt das Plugin selbst (Pull: textDocument/diagnostic und
// workspace/diagnostic); eine Anfrage workspace/diagnostic/refresh des Servers
// zählt RefreshCount hoch.
// Projektgruppe (#648): SetProjects vor Initialize schickt die Projekte als
// workspaceFolders (uri ist die .dproj, aktives Projekt zuerst); danach meldet
// es Änderungen als workspace/didChangeWorkspaceFolders.
// Serverneustart (#393): OpenDocuments der alten Sitzung, Reopen in der neuen
// schickt sie sofort wieder als didOpen.
// Änderungen außerhalb der IDE (#395): FilesChanged meldet sie als
// workspace/didChangeWatchedFiles.
// Projektkontext (#396): SetProjectContexts vor Initialize schickt die
// Kontexte in initializationOptions.projectContexts, danach jeden geänderten
// als dpcc/projectContext.
// workspace/applyEdit (#397): Mit OnApplyEdit kündigt die Sitzung applyEdit
// an; die Anfrage geht im Lese-Thread an OnApplyEdit, das später über AReply
// antwortet ({applied, failureReason}). Antwortet der Empfänger nicht (Sitzung
// beendet, Eintrag beim Entladen verworfen), gibt die Sitzung die Id frei
//; nur die erste Antwort zählt.
// Ergebnisfenster (#400): Implementierungen, workspace/symbol sowie Typ- und
// Aufrufhierarchie; der Aufrufer gleicht die Puffer vorher ab.
// Bedienung im Editor (#399): Code-Aktionen, Befehle mit Argumenten,
// onTypeFormatting für Schnellbefehle und ///-Gerüste, selectionRange und
// typeDefinition; auch hier gleicht der Aufrufer vorher ab.
// Formatieren (#43): formatting bzw. rangeFormatting, Abgleich wie oben.

// Aufbau (dpcc-Metriken): TLspSessionJson (dpcc.Core.Lsp.Session.Json, JSON ohne Zustand) <- TLspSessionBase
// (.Base, Zustand und Abgleich) <- TLspSessionRequests (.Requests, Anfragen) <- TLspSession (hier).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Progress,
  dpcc.Core.Lsp.Contract,
  dpcc.Core.Lsp.DataFlow,
  dpcc.Core.Lsp.AccessChains,
  dpcc.Core.Lsp.WorkspaceEdits,
  dpcc.Core.Lsp.Session.Json,
  dpcc.Core.Lsp.Session.Base,
  dpcc.Core.Lsp.Session.Requests;

type
  // Aliase: Die Typen stehen in dpcc.Core.Lsp.Session.Json; Aufrufer binden weiter nur diese Unit ein.
  TLspLocation = dpcc.Core.Lsp.Session.Json.TLspLocation;
  TLspCodeAction = dpcc.Core.Lsp.Session.Json.TLspCodeAction;
  TLspCodeActionChoice = dpcc.Core.Lsp.Session.Json.TLspCodeActionChoice;
  TLspHoverParts = dpcc.Core.Lsp.Session.Json.TLspHoverParts;
  TLspDiagnosticReport = dpcc.Core.Lsp.Session.Json.TLspDiagnosticReport;
  TLspWorkspaceRun = dpcc.Core.Lsp.Session.Json.TLspWorkspaceRun;
  TLspOpenDocument = dpcc.Core.Lsp.Session.Json.TLspOpenDocument;
  TLspApplyEditReply = dpcc.Core.Lsp.Session.Json.TLspApplyEditReply;
  TLspFormatOptions = dpcc.Core.Lsp.Session.Json.TLspFormatOptions;
  TLspInitializeOptions = dpcc.Core.Lsp.Session.Base.TLspInitializeOptions;

  /// <summary>LSP-Sitzung des Plugins: Zustand und Abgleich aus TLspSessionBase, Anfragen aus
  /// TLspSessionRequests, hier Hierarchien, Auswirkungen, betroffene Tests, Debug-Werte, Diagnosen,
  /// Fortschritt und Befehle.</summary>
  TLspSession = class(TLspSessionRequests)
  public
    /// <summary>Bezeichner für Werte beim Debuggen (#508, textDocument/inlineValue) in den Zeilen
    /// AFromLine..AToLine (0-basiert), Halt an AStoppedLine; ohne Abgleich: Sync vorher im Hauptthread.
    /// Threadsicher wie Completion.</summary>
    function InlineValues(const AFileName: string; AFromLine, AToLine, AStoppedLine: Integer;
      ATimeoutMs: Cardinal): TDpccInlineValueRefs;
    /// <summary>Wirksame Compiler-Schalter an ALine/ACharacter (0-basiert, #558, dpcc/compilerSwitches); ohne
    /// Abgleich: Sync vorher im Hauptthread. Threadsicher wie Completion. Gehört dem Aufrufer; nil ohne Antwort.
    /// </summary>
    function CompilerSwitches(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>dpcc/debugUnavailable (#840): Schalter D, L, O, Routine, Lebensdauer von AName und Korrekturen
    /// am Halt in ALine (0-basiert); gehört dem Aufrufer.</summary>
    function DebugUnavailable(const AFileName: string; ALine: Integer; const AName: string;
      ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>dpcc/expressionCompletion (#538): Vorschläge für AExpression im Gültigkeitsbereich der Zeile
    /// ALine (0-basiert) von AFileName, Schreibmarke ACharacter im Ausdruck. Ohne Abgleich; gehört dem Aufrufer.
    /// </summary>
    function ExpressionCompletion(const AFileName: string; ALine: Integer; const AExpression: string;
      ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>dpcc/accessChains (#865): Zugriffsketten der Anweisungen in ALine (0-basiert) von AFileName für
    /// einen Prozess mit APointerSize. Ohne Abgleich: Sync vorher im Hauptthread. Found = False ohne Antwort.
    /// </summary>
    function AccessChains(const AFileName: string; ALine, APointerSize: Integer; ATimeoutMs: Cardinal): TDpccAvChains;
    /// <summary>Wurzeln einer Hierarchie am Fundort (prepareCallHierarchy bzw. prepareTypeHierarchy, #400).</summary>
    function PrepareHierarchy(ADirection: TDpccHierarchyDirection; const AFileName: string; ALine,
      ACharacter: Integer): TArray<TDpccHierarchyItem>;
    /// <summary>Nächste Ebene unter AItem in Richtung ADirection (#400).</summary>
    function HierarchyChildren(ADirection: TDpccHierarchyDirection;
      const AItem: TDpccHierarchyItem): TArray<TDpccHierarchyItem>;
    /// <summary>Auswirkungen des Symbols am Fundort bis zur Tiefe ADepth (dpcc/impact, #1120); ohne Symbol leer.
    /// </summary>
    function Impact(const AFileName: string; ALine, ACharacter, ADepth: Integer): TDpccImpact;
    /// <summary>Betroffene Tests der Änderungen gegenüber ABase ('' = main bzw. BASE) im Arbeitsbereich von
    /// AFileName, mit nicht eingecheckten Änderungen (dpcc/affectedTests, #1353). Ein Fehler des Servers
    /// (tests.affected aus, keine Arbeitskopie) kommt als Exception.</summary>
    function AffectedTests(const AFileName, ABase: string): TDpccAffectedTests;
    /// <summary>Woher kommt bzw. wohin geht der Wert des Symbols an der Stelle (dpcc/dataFlow, #690).</summary>
    function DataFlow(const ARequest: TDpccDataFlowRequest): TDpccDataFlowResult;
    /// <summary>Diagnosen einer Datei (textDocument/diagnostic) ohne Abgleich; threadsicher wie Completion.</summary>
    function DocumentDiagnostics(const AFileName, APreviousResultId: string;
      ATimeoutMs: Cardinal): TLspDiagnosticReport;
    /// <summary>Diagnosen aller Projektdateien außer den geöffneten (workspace/diagnostic, Long-Polling);
    /// APrevious mit FileName und ResultId der bekannten Stände. Threadsicher wie Completion.</summary>
    function WorkspaceDiagnostics(const APrevious: TArray<TLspDiagnosticReport>;
      ATimeoutMs: Cardinal): TArray<TLspDiagnosticReport>; overload;
    /// <summary>Wie oben, dazu der Stand der Projektprüfung (#1247).</summary>
    function WorkspaceDiagnostics(const APrevious: TArray<TLspDiagnosticReport>; ATimeoutMs: Cardinal;
      out ARun: TLspWorkspaceRun): TArray<TLspDiagnosticReport>; overload;
    /// <summary>Anzahl der workspace/diagnostic/refresh-Anfragen des Servers.</summary>
    function RefreshCount: Integer;
    /// <summary>Laufende Indizierung o. Ä. des Servers ("Index 45 %"); '' ohne (#492).</summary>
    function ProgressText: string;
    /// <summary>Statusleiste: "dpcc indiziert … (45 %)"; '' ohne laufenden Vorgang (#492).</summary>
    function IndexingText: string;
    /// <summary>Läuft eine Indizierung? APercent = Fortschritt, -1 = unbekannt (#591).</summary>
    function Indexing(out APercent: Integer): Boolean;
    /// <summary>Läuft der Vorgang mit dem Token AToken (ein Projekt der Gruppe, #2142)?</summary>
    function IndexingOf(const AToken: string; out APercent: Integer): Boolean;
    /// <summary>Beobachter für $/progress, im Lese-Thread (#591).</summary>
    procedure SetOnProgress(const AProc: TProc);
    /// <summary>workspace/executeCommand; Ergebnis gehört dem Aufrufer (nil bei Fehler oder Zeitlimit).</summary>
    function ExecuteCommand(const ACommand: string; ATimeoutMs: Cardinal): TJSONValue; overload;
    /// <summary>Wie oben mit Argumenten; übernimmt AArguments.</summary>
    function ExecuteCommand(const ACommand: string; AArguments: TJSONArray; ATimeoutMs: Cardinal): TJSONValue;
      overload;
  end;

  /// <summary>Laufende Sitzung oder nil; startet nie einen Server. Aus beliebigem Thread
  /// aufgerufen, meist im Zeitlimit-Arbeiter. Steht hier, damit Anbieter verschiedener Features sie ohne
  /// gegenseitigen Import teilen.</summary>
  TDpccSessionFunc = reference to function: TLspSession;

implementation

/// <summary>previousResultIds für workspace/diagnostic aus den bekannten Berichten.</summary>
function PreviousResultIds(const APrevious: TArray<TLspDiagnosticReport>): TJSONArray;
var
  mKnown: TLspDiagnosticReport;
begin
  Result := TJSONArray.Create;
  for mKnown in APrevious do
  begin
    if mKnown.ResultId <> '' then
    begin
      Result.AddElement(TJSONObject.Create.AddPair('uri', TLspSessionJson.PathToUri(mKnown.FileName))
        .AddPair('value', mKnown.ResultId));
    end;
  end;
end;

/// <summary>Berichte aus items der Antwort auf workspace/diagnostic; Berichte ohne Datei fallen weg.</summary>
function DiagnosticReportsOf(const AItems: TJSONValue): TArray<TLspDiagnosticReport>;
var
  mItem: TJSONValue;
  mReport: TLspDiagnosticReport;
begin
  Result := nil;
  if not (AItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AItems) do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mReport := TLspDiagnosticReport.FromJson(TJSONObject(mItem), '');
    if mReport.FileName <> '' then
    begin
      Result := Result + [mReport];
    end;
  end;
end;

function TLspSession.WorkspaceDiagnostics(const APrevious: TArray<TLspDiagnosticReport>; ATimeoutMs: Cardinal;
  out ARun: TLspWorkspaceRun): TArray<TLspDiagnosticReport>;
var
  mResponse: TJSONValue;
begin
  Result := nil;
  ARun := Default(TLspWorkspaceRun);
  mResponse := FClient.Request('workspace/diagnostic',
    TJSONObject.Create(TJSONPair.Create('previousResultIds', PreviousResultIds(APrevious))), ATimeoutMs);
  try
    if mResponse is TJSONObject then
    begin
      ARun := TLspWorkspaceRun.FromJson(mResponse);
      Result := DiagnosticReportsOf(TJSONObject(mResponse).GetValue('items'));
    end;
  finally
    mResponse.Free;
  end;
end;

{ TLspSession }

function TLspSession.InlineValues(const AFileName: string; AFromLine, AToLine, AStoppedLine: Integer;
  ATimeoutMs: Cardinal): TDpccInlineValueRefs;
var
  mParams, mRange, mStopped: TJSONObject;
  mResponse: TJSONValue;
begin
  mRange := TJSONObject.Create;
  mRange.AddPair('start', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AFromLine))
    .AddPair('character', TJSONNumber.Create(0)));
  mRange.AddPair('end', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AToLine + 1))
    .AddPair('character', TJSONNumber.Create(0)));
  mStopped := TJSONObject.Create;
  mStopped.AddPair('start', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AStoppedLine))
    .AddPair('character', TJSONNumber.Create(0)));
  mStopped.AddPair('end', TJSONObject.Create.AddPair('line', TJSONNumber.Create(AStoppedLine))
    .AddPair('character', TJSONNumber.Create(0)));
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  mParams.AddPair('range', mRange);
  mParams.AddPair('context', TJSONObject.Create.AddPair('frameId', TJSONNumber.Create(0))
    .AddPair('stoppedLocation', mStopped));
  mResponse := FClient.Request('textDocument/inlineValue', mParams, ATimeoutMs);
  try
    Result := InlineValueRefsOf(mResponse);
  finally
    mResponse.Free;
  end;
end;

function TLspSession.CompilerSwitches(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  mParams.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ALine))
    .AddPair('character', TJSONNumber.Create(ACharacter)));
  Result := FClient.Request('dpcc/compilerSwitches', mParams, ATimeoutMs);
end;

function TLspSession.DebugUnavailable(const AFileName: string; ALine: Integer; const AName: string;
  ATimeoutMs: Cardinal): TJSONValue;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  mParams.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ALine))
    .AddPair('character', TJSONNumber.Create(0)));
  mParams.AddPair('name', AName);
  Result := FClient.Request('dpcc/debugUnavailable', mParams, ATimeoutMs);
end;

function TLspSession.AccessChains(const AFileName: string; ALine, APointerSize: Integer;
  ATimeoutMs: Cardinal): TDpccAvChains;
var
  mResponse: TJSONValue;
begin
  mResponse := FClient.Request(TDpccAvJson.cMethod, TDpccAvJson.Params(AFileName, ALine, APointerSize), ATimeoutMs);
  try
    Result := TDpccAvJson.Parse(mResponse);
  finally
    mResponse.Free;
  end;
end;

function TLspSession.ExpressionCompletion(const AFileName: string; ALine: Integer; const AExpression: string;
  ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
var
  mParams: TJSONObject;
begin
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  mParams.AddPair('position', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ALine))
    .AddPair('character', TJSONNumber.Create(0)));
  mParams.AddPair('expression', AExpression);
  mParams.AddPair('character', TJSONNumber.Create(ACharacter));
  Result := FClient.Request('dpcc/expressionCompletion', mParams, ATimeoutMs);
end;

function TLspSession.PrepareHierarchy(ADirection: TDpccHierarchyDirection; const AFileName: string; ALine,
  ACharacter: Integer): TArray<TDpccHierarchyItem>;
var
  mMethod: string;
  mResponse, mItem: TJSONValue;
begin
  Result := nil;
  mMethod := 'textDocument/prepareTypeHierarchy';
  if ADirection in [TDpccHierarchyDirection.Incoming, TDpccHierarchyDirection.Outgoing] then
  begin
    mMethod := 'textDocument/prepareCallHierarchy';
  end;
  mResponse := FClient.Request(mMethod, PositionParams(AFileName, ALine, ACharacter), FTimeoutMs * 10);
  try
    if mResponse is TJSONArray then
    begin
      for mItem in TJSONArray(mResponse) do
      begin
        if mItem is TJSONObject then
        begin
          Result := Result + [HierarchyItemOf(mItem)];
        end;
      end;
    end;
  finally
    mResponse.Free;
  end;
end;

function TLspSession.HierarchyChildren(ADirection: TDpccHierarchyDirection;
  const AItem: TDpccHierarchyItem): TArray<TDpccHierarchyItem>;
const
  cMethods: array[TDpccHierarchyDirection] of string = ('callHierarchy/incomingCalls',
    'callHierarchy/outgoingCalls', 'typeHierarchy/supertypes', 'typeHierarchy/subtypes');
  // Aufrufe stecken in {from|to, fromRanges}; Typen kommen direkt.
  cMembers: array[TDpccHierarchyDirection] of string = ('from', 'to', '', '');
var
  mRaw, mResponse, mItem, mInner: TJSONValue;
  mChild: TDpccHierarchyItem;
begin
  Result := nil;
  mRaw := TJSONObject.ParseJSONValue(AItem.Raw);
  if not (mRaw is TJSONObject) then
  begin
    mRaw.Free;
    Exit;
  end;
  mResponse := FClient.Request(cMethods[ADirection], TJSONObject.Create(TJSONPair.Create('item', mRaw)), FTimeoutMs * 10);
  try
    if not (mResponse is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mResponse) do
    begin
      mInner := mItem;
      if (cMembers[ADirection] <> '') and (mItem is TJSONObject) then
      begin
        mInner := TJSONObject(mItem).GetValue(cMembers[ADirection]);
      end;
      if mInner is TJSONObject then
      begin
        mChild := HierarchyItemOf(mInner);
        // Eingehende Aufrufe (#1119): dpccConfidence steht am Aufruf, nicht am Element.
        mChild.Confidence := TDpccConfidence.FromJson(mItem);
        // Aufruf über Interface oder virtuelle Methode (#1122), ebenfalls am Aufruf.
        if mItem is TJSONObject then
        begin
          mChild.Dispatch := TJSONObject(mItem).GetValue<string>('dpccDispatch.kind', '');
          mChild.Implementations := TJSONObject(mItem).GetValue<Integer>('dpccDispatch.implementations', 0);
        end;
        Result := Result + [mChild];
      end;
    end;
  finally
    mResponse.Free;
  end;
end;

function TLspSession.Impact(const AFileName: string; ALine, ACharacter, ADepth: Integer): TDpccImpact;
var
  mParams: TJSONObject;
  mResponse: TJSONValue;
begin
  mParams := PositionParams(AFileName, ALine, ACharacter);
  mParams.AddPair('depth', TJSONNumber.Create(ADepth));
  // Mehrere Referenzsuchen über das ganze Projekt; der Server begrenzt die Zeit selbst und meldet es.
  mResponse := FClient.Request('dpcc/impact', mParams, FTimeoutMs * 30);
  try
    Result := ImpactFromJson(mResponse);
  finally
    mResponse.Free;
  end;
end;

function TLspSession.AffectedTests(const AFileName, ABase: string): TDpccAffectedTests;
var
  mParams: TJSONObject;
  mResponse: TJSONValue;
begin
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  mParams.AddPair('base', ABase);
  mParams.AddPair('includeUncommitted', TJSONBool.Create(True));
  // git bzw. svn und eine Auswirkungsanalyse je geänderter Routine; der Server begrenzt die Zeit selbst.
  mResponse := FClient.Request('dpcc/affectedTests', mParams, FTimeoutMs * 30);
  try
    Result := AffectedTestsFromJson(mResponse);
  finally
    mResponse.Free;
  end;
end;

function TLspSession.DataFlow(const ARequest: TDpccDataFlowRequest): TDpccDataFlowResult;
var
  mResponse: TJSONValue;
begin
  // Projektweit über die Referenzsuche; dafür so viel Zeit wie für die Hierarchien.
  mResponse := FClient.Request(TDpccDataFlowJson.cMethod, TDpccDataFlowJson.Params(ARequest), FTimeoutMs * 10);
  try
    Result := TDpccDataFlowJson.Parse(mResponse);
  finally
    mResponse.Free;
  end;
end;

function TLspSession.DocumentDiagnostics(const AFileName, APreviousResultId: string;
  ATimeoutMs: Cardinal): TLspDiagnosticReport;
var
  mParams: TJSONObject;
  mResponse: TJSONValue;
begin
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  if APreviousResultId <> '' then
  begin
    mParams.AddPair('previousResultId', APreviousResultId);
  end;
  mResponse := FClient.Request('textDocument/diagnostic', mParams, ATimeoutMs);
  try
    if mResponse is TJSONObject then
    begin
      Result := TLspDiagnosticReport.FromJson(TJSONObject(mResponse), AFileName);
    end
    else
    begin
      Result := Default(TLspDiagnosticReport);
      Result.FileName := AFileName;
    end;
  finally
    mResponse.Free;
  end;
end;

function TLspSession.WorkspaceDiagnostics(const APrevious: TArray<TLspDiagnosticReport>;
  ATimeoutMs: Cardinal): TArray<TLspDiagnosticReport>;
var
  mRun: TLspWorkspaceRun;
begin
  Result := WorkspaceDiagnostics(APrevious, ATimeoutMs, mRun);
end;

function TLspSession.RefreshCount: Integer;
begin
  Result := FRefresh.Count;
end;

function TLspSession.ProgressText: string;
begin
  Result := FProgress.Text;
end;

function TLspSession.IndexingText: string;
begin
  Result := FProgress.IndexingText;
end;

function TLspSession.Indexing(out APercent: Integer): Boolean;
begin
  Result := FProgress.Active(APercent);
end;

function TLspSession.IndexingOf(const AToken: string; out APercent: Integer): Boolean;
begin
  Result := FProgress.ActiveOf(AToken, APercent);
end;

procedure TLspSession.SetOnProgress(const AProc: TProc);
begin
  FProgress.SetOnChanged(AProc);
end;

function TLspSession.ExecuteCommand(const ACommand: string; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := ExecuteCommand(ACommand, TJSONArray.Create, ATimeoutMs);
end;

function TLspSession.ExecuteCommand(const ACommand: string; AArguments: TJSONArray; ATimeoutMs: Cardinal): TJSONValue;
begin
  try
    Result := FClient.Request('workspace/executeCommand',
      TJSONObject.Create.AddPair('command', ACommand).AddPair('arguments', AArguments), ATimeoutMs);
  except
    Result := nil;
  end;
end;

end.
