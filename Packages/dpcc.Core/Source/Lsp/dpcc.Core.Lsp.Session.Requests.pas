unit dpcc.Core.Lsp.Session.Requests;

// Anfragen der LSP-Sitzung (aus dpcc.Core.Lsp.Session ausgelagert): Hover, Referenzen, Definitionen,
// Implementierungen, Symbole, Code-Aktionen und Befehle, Formatieren, Auswahlbereiche, Vervollständigung,
// Parameterhilfe und Umbenennen. Der Aufrufer gleicht die Puffer vorher ab (Sync).
// Strg+Klick und der Symbolhinweis der IDE fragen im Hintergrund (GotoTargetAt, HoverAt: ohne Abgleich, aus jedem
// Thread); der Hauptthread gleicht vorher ab und wartet höchstens cMainThreadTimeoutMs (dpcc.Core.Lsp.LateAnswers).
// Ohne Sprungziel liefert GotoTargetAt den Grund des Servers mit (dpcc/noTarget, im Lese-Thread abgelegt, kommt vor
// der leeren Antwort); fehlt die Benachrichtigung (älterer Server), bleibt er Unknown.
// Ablaufprotokoll (LOG1): Mit einer Kennung (GotoTargetAt mit AFlowId) schreibt jeder Schritt eine Zeile
// (dpcc.Core.Diagnostics.Flow): Antwort auf declaration, Urteil von OnTarget samt Teilen (OnTargetWhy), ob definition
// gefragt wurde und was sie lieferte. Das Ergebnis bleibt dasselbe; ausgeschaltet wird kein Text gebaut.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Lsp.Progress,
  dpcc.Core.Hover.Contract,
  dpcc.Core.Lsp.Contract,
  dpcc.Core.Files.WatchedChanges,
  dpcc.Core.Lsp.TextChanges,
  dpcc.Core.Lsp.WorkspaceEdits,
  dpcc.Core.Lsp.LateAnswers,
  dpcc.Core.Lsp.Session.Json,
  dpcc.Core.Lsp.Session.Base;

type
  /// <summary>Anfragen der LSP-Sitzung zu Hover, Orten, Symbolen, Code-Aktionen, Formatieren, Vervollständigung
  /// und Umbenennen; der Aufrufer gleicht die Puffer vorher ab (Sync). Vorfahr von TLspSession.</summary>
  TLspSessionRequests = class(TLspSessionBase)
  public const
    /// <summary>Höchstens so lange wartet der Hauptthread auf eine Antwort (Strg+Klick, Symbolhinweis der IDE): Ein
    /// beschäftigter Server soll die IDE nicht anhalten. Die Anfrage selbst läuft im Hintergrund weiter, ihr
    /// Ergebnis wird nachgereicht (TDpccLateAnswers).</summary>
    cMainThreadTimeoutMs = TDpccLateAnswers.cWaitMs;
  public
    /// <summary>Benachrichtigung ohne Antwort, z. B. dpcc/compileStarted (#527); übernimmt AParams.</summary>
    procedure Notify(const AMethod: string; AParams: TJSONObject);
    /// <summary>didSave für eine abgeglichene Datei: Der Server prüft dann mit dcc (compiler.onSave, #40).</summary>
    procedure Saved(const AFileName: string);
    /// <summary>workspace/didChangeWatchedFiles für Änderungen außerhalb der IDE (#395).
    /// Geänderte Dateien, die gerade abgeglichen sind, entfallen: Für sie gilt der Editortext.</summary>
    procedure FilesChanged(const AChanges: TArray<TDpccFileChange>);
    /// <summary>ATimeoutMs 0 = Zeitlimit der Sitzung. Aufrufe im Hauptthread geben ein kurzes Zeitlimit mit: Die IDE
    /// steht, bis die Antwort kommt.</summary>
    function Hover(const AFileName, AText: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): string;
    /// <summary>Hover-Text wie Hover, aber ohne Abgleich (Sync vorher im Hauptthread); aus jedem Thread, solange die
    /// Sitzung lebt. ATimeoutMs 0 = Zeitlimit der Sitzung.</summary>
    function HoverAt(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): string;
    /// <summary>Hover an einem Fundort ohne Abgleich: Der Server liest nicht geöffnete Dateien selbst (#588).</summary>
    function HoverDataAt(const AFileName: string; ALine, ACharacter: Integer;
      ATimeoutMs: Cardinal): TDpccHoverData;
    /// <summary>Verwendungen des Symbols am Fundort ohne die Deklaration (textDocument/references).</summary>
    function References(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>Implementierungen des Symbols (textDocument/implementation, #400).</summary>
    function Implementations(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>Projektweite Symbolsuche (workspace/symbol, #400); unscharf filtert der Server.</summary>
    function WorkspaceSymbols(const AQuery: string; ATimeoutMs: Cardinal): TArray<TDpccSymbol>;
    /// <summary>Gliederung einer Datei (textDocument/documentSymbol, #503), flach in Dateireihenfolge.</summary>
    function DocumentSymbols(const AFileName: string; ATimeoutMs: Cardinal): TArray<TDpccSymbol>;
    /// <summary>Unveränderte Antwort von textDocument/documentSymbol samt dpcc-Angaben (Gliederungsfenster,
    /// #537); der Aufrufer gibt sie frei, nil ohne Antwort.</summary>
    function DocumentSymbolTree(const AFileName: string; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>Code-Aktionen für ARange (textDocument/codeAction, #399), Reihenfolge des Servers.</summary>
    function CodeActions(const AFileName: string; const ARange: TLspRange): TArray<TLspCodeAction>; overload;
    /// <summary>Wie oben mit eigener Wartezeit, etwa für die Glühbirne der Zeilenleiste (#768), die den Editor
    /// nicht bremsen darf.</summary>
    function CodeActions(const AFileName: string; const ARange: TLspRange;
      ATimeoutMs: Cardinal): TArray<TLspCodeAction>; overload;
    /// <summary>workspace/executeCommand mit Argumenten (JSON-Array, '' = keine, #399); ELspClientError bei
    /// Fehler oder Zeitlimit. Ergebnis gehört dem Aufrufer.</summary>
    function RunCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>Anfrage AMethod mit Parametern (JSON-Objekt, '' = keine), abbrechbar über ACancelled (#1351:
    /// dpcc/query); ELspClientError bei Fehler, Abbruch oder Zeitlimit. Ergebnis gehört dem Aufrufer.</summary>
    function RunRequest(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal;
      const ACancelled: TFunc<Boolean>): TJSONValue;
    /// <summary>textDocument/onTypeFormatting (#399): Schnellbefehle nach Enter (ACh = #10) und
    /// ///-Gerüste (ACh = '/'). Leer, wenn der Server nichts ändert.</summary>
    function OnTypeFormatting(const AFileName: string; ALine, ACharacter: Integer; const ACh: string;
      const AOptions: TLspFormatOptions; ATimeoutMs: Cardinal): TArray<TLspTextEdit>;
    /// <summary>textDocument/formatting (#43): Änderungen für die ganze Datei; leer, wenn nichts zu tun ist.
    /// ELspClientError bei Fehler oder Zeitlimit.</summary>
    function Formatting(const AFileName: string; ATabSize: Integer; AInsertSpaces: Boolean;
      ATimeoutMs: Cardinal): TArray<TLspTextEdit>; overload;
    /// <summary>textDocument/rangeFormatting (#43): nur die Zeilen von ARange.</summary>
    function Formatting(const AFileName: string; const ARange: TLspRange; ATabSize: Integer; AInsertSpaces: Boolean;
      ATimeoutMs: Cardinal): TArray<TLspTextEdit>; overload;
    /// <summary>Umgebende Bereiche am Fundort, innen zuerst (textDocument/selectionRange, #399).</summary>
    function SelectionRanges(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspRange>;
    /// <summary>textDocument/linkedEditingRange nur für lokale Bezeichner ("dpccLocals", #658): Antwort des
    /// Servers (Aufrufer gibt frei), nil ohne Antwort. Threadsicher wie die übrigen Anfragen.</summary>
    function LinkedLocals(const AFileName: string; ALine, ACharacter: Integer): TJSONValue;
    /// <summary>Typ des Symbols (textDocument/typeDefinition, #399).</summary>
    function TypeDefinition(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>textDocument/definition mit Abgleich: das erste Ziel; Zeitlimit der Sitzung.</summary>
    function Definition(const AFileName, AText: string; ALine, ACharacter: Integer;
      out ALocation: TLspLocation): Boolean; overload;
    /// <summary>Wie oben mit eigenem Zeitlimit (0 = das der Sitzung).</summary>
    function Definition(const AFileName, AText: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
      out ALocation: TLspLocation): Boolean; overload;
    /// <summary>Ziel für Strg+Klick und „Deklaration suchen“ der IDE (Auftrag NAV), mit Abgleich: wie die IDE von
    /// einer Verwendung zur Deklaration (textDocument/declaration); steht die Stelle schon auf der Deklaration selbst,
    /// zur Implementierung (textDocument/definition), von dort zurück. Ohne declarationProvider nur definition.
    /// ATimeoutMs gilt für beide Anfragen zusammen. False ohne Ziel; ELspClientError bei Zeitlimit oder beendetem
    /// Server, ELspMethodNotFound ohne Sprungziele.</summary>
    function GotoTarget(const AFileName, AText: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
      out ALocation: TLspLocation): Boolean;
    /// <summary>Wie GotoTarget ohne Abgleich (Sync vorher im Hauptthread): ALineText ist die Zeile ALine des
    /// abgeglichenen Texts. Aus jedem Thread, solange die Sitzung lebt (Strg+Klick im Hintergrund).</summary>
    function GotoTargetAt(const AFileName, ALineText: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
      out ALocation: TLspLocation): Boolean; overload;
    /// <summary>Wie oben; ohne Ziel in ANoTarget der Grund des Servers (dpcc/noTarget, kam vor der leeren Antwort),
    /// bei mehreren Anfragen der aussagekräftigste; ohne Benachrichtigung Reason = Unknown.</summary>
    function GotoTargetAt(const AFileName, ALineText: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
      out ALocation: TLspLocation; out ANoTarget: TDpccNoTarget): Boolean; overload;
    /// <summary>Wie oben; AFlowId &gt; 0: Jeder Schritt steht unter dieser Kennung im Ablaufprotokoll (LOG1,
    /// TDpccFlow): Antwort auf declaration, Urteil von OnTarget mit seinen Teilen, ob definition gefragt wurde und was
    /// sie lieferte. Das Ergebnis ist dasselbe wie ohne.</summary>
    function GotoTargetAt(const AFileName, ALineText: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
      out ALocation: TLspLocation; out ANoTarget: TDpccNoTarget; AFlowId: Integer): Boolean; overload;
    /// <summary>textDocument/definition ohne Abgleich (#505): alle Ziele; Sync vorher.</summary>
    function Definitions(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>textDocument/declaration ohne Abgleich (#505): alle Ziele; Sync vorher.</summary>
    function Declarations(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
    /// <summary>
    /// textDocument/completion ohne Abgleich: Sync vorher im Hauptthread. Darf aus einem
    /// anderen Thread kommen, solange die Sitzung lebt. Liefert die Antwort (CompletionList,
    /// CompletionItem[] oder nil); der Aufrufer gibt sie frei.
    /// </summary>
    function Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
      overload;
    /// <summary>Wie oben, gestaffelt (#616): AOnPartial bekommt Teilergebnisse (CompletionItem[]) im
    /// Lese-Thread, bevor die Antwort den Rest bringt. ATrigger: Zeichen, nach dem automatisch geöffnet wurde
    /// (context.triggerCharacter, #448); '' bei Strg+Leer.</summary>
    function Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
      const ATrigger: string; const AOnPartial: TLspPartialProc): TJSONValue; overload;
    /// <summary>textDocument/signatureHelp ohne Abgleich, wie Completion.</summary>
    function SignatureHelp(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>textDocument/prepareRename (#397): Lässt sich hier umbenennen? APlaceholder ist der
    /// bisherige Name (aus placeholder, sonst aus dem Bereich in AText).</summary>
    function PrepareRename(const AFileName, AText: string; ALine, ACharacter: Integer;
      out APlaceholder: string): Boolean;
    /// <summary>textDocument/rename (#397): WorkspaceEdit des Servers, gehört dem Aufrufer; nil ohne.</summary>
    function Rename(const AFileName: string; ALine, ACharacter: Integer; const ANewName: string;
      ATimeoutMs: Cardinal): TJSONValue;
    /// <summary>completionItem/resolve für AItem (wird übernommen); threadsicher wie Completion.</summary>
    function ResolveCompletion(AItem: TJSONObject; ATimeoutMs: Cardinal): TJSONValue;
  end;

implementation

uses
  System.Classes,
  dpcc.Text.Lines,
  dpcc.Core.Diagnostics.Flow,
  dpcc.Core.Editor.Navigation;

function RangeToJson(const ARange: TLspRange): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('start', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ARange.StartPos.Line))
    .AddPair('character', TJSONNumber.Create(ARange.StartPos.Character)));
  Result.AddPair('end', TJSONObject.Create.AddPair('line', TJSONNumber.Create(ARange.EndPos.Line))
    .AddPair('character', TJSONNumber.Create(ARange.EndPos.Character)));
end;

function RangeOf(const AValue: TJSONValue; out ARange: TLspRange): Boolean;
var
  mRange: TJSONObject;
begin
  ARange := Default(TLspRange);
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<TJSONObject>('range', mRange) and
    mRange.TryGetValue<Integer>('start.line', ARange.StartPos.Line) and
    mRange.TryGetValue<Integer>('start.character', ARange.StartPos.Character) and
    mRange.TryGetValue<Integer>('end.line', ARange.EndPos.Line) and
    mRange.TryGetValue<Integer>('end.character', ARange.EndPos.Character);
end;

/// <summary>Parameter von formatting und rangeFormatting ohne Bereich.</summary>
function FormattingParams(const AUri: string; ATabSize: Integer; AInsertSpaces: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', AUri)));
  Result.AddPair('options', TJSONObject.Create.AddPair('tabSize', TJSONNumber.Create(ATabSize))
    .AddPair('insertSpaces', TJSONBool.Create(AInsertSpaces)));
end;

/// <summary>TextEdit[] einer Antwort; gibt AResponse frei.</summary>
function TextEditsOf(AResponse: TJSONValue): TArray<TLspTextEdit>;
var
  mItem: TJSONValue;
  mEdit: TLspTextEdit;
begin
  Result := nil;
  try
    if AResponse is TJSONArray then
    begin
      for mItem in TJSONArray(AResponse) do
      begin
        if TLspTextEdit.FromJson(mItem, mEdit) then
        begin
          Result := Result + [mEdit];
        end;
      end;
    end;
  finally
    AResponse.Free;
  end;
end;

/// <summary>Orte der Antwort auf textDocument/references mit Sicherheit; Einträge ohne Datei fallen weg.</summary>
function ReferenceLocationsOf(const AResponse: TJSONValue): TArray<TLspLocation>;
var
  mItem: TJSONValue;
  mLocation: TLspLocation;
begin
  Result := nil;
  if not (AResponse is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AResponse) do
  begin
    if not (mItem is TJSONObject) then
    begin
      Continue;
    end;
    mLocation.FileName := TLspSessionJson.UriToPath(TJSONObject(mItem).GetValue<string>('uri', ''));
    mLocation.Line := TJSONObject(mItem).GetValue<Integer>('range.start.line', 0);
    mLocation.Character := TJSONObject(mItem).GetValue<Integer>('range.start.character', 0);
    mLocation.Confidence := TDpccConfidence.FromJson(mItem);
    if mLocation.FileName <> '' then
    begin
      Result := Result + [mLocation];
    end;
  end;
end;

function TLspSessionRequests.References(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  mParams: TJSONObject;
  mContext: TJSONObject;
  mResponse: TJSONValue;
begin
  mParams := PositionParams(AFileName, ALine, ACharacter);
  mContext := TJSONObject.Create;
  mContext.AddPair('includeDeclaration', TJSONBool.Create(False));
  mParams.AddPair('context', mContext);
  // Die Suche geht über das ganze Projekt; dafür mehr Zeit als für einen Hover.
  mResponse := FClient.Request('textDocument/references', mParams, FTimeoutMs * 10);
  try
    Result := ReferenceLocationsOf(mResponse);
  finally
    mResponse.Free;
  end;
end;

{ TLspSessionRequests }

procedure TLspSessionRequests.Notify(const AMethod: string; AParams: TJSONObject);
begin
  FClient.Notify(AMethod, AParams);
end;

procedure TLspSessionRequests.Saved(const AFileName: string);
begin
  if not IsSynced(AFileName) then
  begin
    Exit;
  end;
  FClient.Notify('textDocument/didSave', TJSONObject.Create(TJSONPair.Create('textDocument',
    TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))))));
end;

procedure TLspSessionRequests.FilesChanged(const AChanges: TArray<TDpccFileChange>);
var
  mChange: TDpccFileChange;
  mItems: TJSONArray;
  mItem: TJSONObject;
begin
  mItems := TJSONArray.Create;
  for mChange in AChanges do
  begin
    if (mChange.Kind = TDpccFileChangeKind.Changed) and IsSynced(mChange.FileName) then
    begin
      Continue;
    end;
    mItem := TJSONObject.Create;
    mItem.AddPair('uri', PathToUri(mChange.FileName));
    mItem.AddPair('type', TJSONNumber.Create(Ord(mChange.Kind)));
    mItems.AddElement(mItem);
  end;
  if mItems.Count = 0 then
  begin
    mItems.Free;
    Exit;
  end;
  FClient.Notify('workspace/didChangeWatchedFiles', TJSONObject.Create(TJSONPair.Create('changes', mItems)));
end;

function TLspSessionRequests.Hover(const AFileName, AText: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): string;
begin
  Sync(AFileName, AText);
  Result := HoverAt(AFileName, ALine, ACharacter, ATimeoutMs);
end;

function TLspSessionRequests.HoverAt(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): string;
var
  mResponse: TJSONValue;
begin
  mResponse := FClient.Request('textDocument/hover', PositionParams(AFileName, ALine, ACharacter),
    TimeoutOr(ATimeoutMs));
  try
    Result := HoverText(mResponse);
  finally
    mResponse.Free;
  end;
end;

function TLspSessionRequests.HoverDataAt(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TDpccHoverData;
var
  mResponse: TJSONValue;
begin
  mResponse := FClient.Request('textDocument/hover', PositionParams(AFileName, ALine, ACharacter),
    TimeoutOr(ATimeoutMs));
  try
    Result := TDpccHoverData.FromHover(mResponse);
  finally
    mResponse.Free;
  end;
end;

function TLspSessionRequests.Implementations(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  mResponse: TJSONValue;
begin
  mResponse := FClient.Request('textDocument/implementation', PositionParams(AFileName, ALine, ACharacter),
    FTimeoutMs * 10);
  try
    Result := LocationsOf(mResponse);
  finally
    mResponse.Free;
  end;
end;

function TLspSessionRequests.CodeActions(const AFileName: string; const ARange: TLspRange): TArray<TLspCodeAction>;
begin
  Result := CodeActions(AFileName, ARange, FTimeoutMs * 2);
end;

function TLspSessionRequests.CodeActions(const AFileName: string; const ARange: TLspRange;
  ATimeoutMs: Cardinal): TArray<TLspCodeAction>;
var
  mParams, mContext: TJSONObject;
  mResponse, mItem: TJSONValue;
  mAction: TLspCodeAction;
begin
  Result := nil;
  mContext := TJSONObject.Create;
  // Die Befunde der Regeln ermittelt der Server selbst; 1 = ausdrücklich aufgerufen.
  mContext.AddPair('diagnostics', TJSONArray.Create);
  mContext.AddPair('triggerKind', TJSONNumber.Create(1));
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  mParams.AddPair('range', RangeToJson(ARange));
  mParams.AddPair('context', mContext);
  mResponse := FClient.Request('textDocument/codeAction', mParams, ATimeoutMs);
  try
    if mResponse is TJSONArray then
    begin
      for mItem in TJSONArray(mResponse) do
      begin
        if TLspCodeAction.FromJson(mItem, mAction) then
        begin
          Result := Result + [mAction];
        end;
      end;
    end;
  finally
    mResponse.Free;
  end;
end;

function TLspSessionRequests.RunCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal): TJSONValue;
var
  mArguments: TJSONValue;
begin
  mArguments := nil;
  if Trim(AArgumentsJson) <> '' then
  begin
    mArguments := TJSONObject.ParseJSONValue(AArgumentsJson);
  end;
  if not (mArguments is TJSONArray) then
  begin
    mArguments.Free;
    mArguments := TJSONArray.Create;
  end;
  Result := FClient.Request('workspace/executeCommand',
    TJSONObject.Create.AddPair('command', ACommand).AddPair('arguments', mArguments), ATimeoutMs);
end;

function TLspSessionRequests.RunRequest(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal;
  const ACancelled: TFunc<Boolean>): TJSONValue;
var
  mParams: TJSONValue;
begin
  mParams := nil;
  if Trim(AParamsJson) <> '' then
  begin
    mParams := TJSONObject.ParseJSONValue(AParamsJson);
  end;
  if not (mParams is TJSONObject) then
  begin
    mParams.Free;
    mParams := TJSONObject.Create;
  end;
  Result := FClient.RequestCancellable(AMethod, mParams, ATimeoutMs, ACancelled);
end;

function TLspSessionRequests.OnTypeFormatting(const AFileName: string; ALine, ACharacter: Integer;
  const ACh: string; const AOptions: TLspFormatOptions; ATimeoutMs: Cardinal): TArray<TLspTextEdit>;
var
  mParams: TJSONObject;
begin
  mParams := PositionParams(AFileName, ALine, ACharacter);
  mParams.AddPair('ch', ACh);
  mParams.AddPair('options', TJSONObject.Create.AddPair('tabSize', TJSONNumber.Create(AOptions.TabSize))
    .AddPair('insertSpaces', TJSONBool.Create(AOptions.InsertSpaces)));
  Result := TextEditsOf(FClient.Request('textDocument/onTypeFormatting', mParams, ATimeoutMs));
end;

function TLspSessionRequests.Formatting(const AFileName: string; ATabSize: Integer; AInsertSpaces: Boolean;
  ATimeoutMs: Cardinal): TArray<TLspTextEdit>;
begin
  Result := TextEditsOf(FClient.Request('textDocument/formatting',
    FormattingParams(PathToUri(AFileName), ATabSize, AInsertSpaces), ATimeoutMs));
end;

function TLspSessionRequests.Formatting(const AFileName: string; const ARange: TLspRange; ATabSize: Integer;
  AInsertSpaces: Boolean; ATimeoutMs: Cardinal): TArray<TLspTextEdit>;
var
  mParams: TJSONObject;
begin
  mParams := FormattingParams(PathToUri(AFileName), ATabSize, AInsertSpaces);
  mParams.AddPair('range', RangeToJson(ARange));
  Result := TextEditsOf(FClient.Request('textDocument/rangeFormatting', mParams, ATimeoutMs));
end;

function TLspSessionRequests.SelectionRanges(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspRange>;
var
  mParams, mPosition: TJSONObject;
  mPositions: TJSONArray;
  mResponse, mCurrent: TJSONValue;
  mRange: TLspRange;
begin
  Result := nil;
  // selectionRange will eine Liste von Positionen statt "position".
  mPosition := TJSONObject.Create;
  mPosition.AddPair('line', TJSONNumber.Create(ALine));
  mPosition.AddPair('character', TJSONNumber.Create(ACharacter));
  mPositions := TJSONArray.Create;
  mPositions.AddElement(mPosition);
  mParams := TJSONObject.Create;
  mParams.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', PathToUri(AFileName))));
  mParams.AddPair('positions', mPositions);
  mResponse := FClient.Request('textDocument/selectionRange', mParams, FTimeoutMs);
  try
    if not (mResponse is TJSONArray) or (TJSONArray(mResponse).Count = 0) then
    begin
      Exit;
    end;
    mCurrent := TJSONArray(mResponse).Items[0];
    while RangeOf(mCurrent, mRange) do
    begin
      Result := Result + [mRange];
      mCurrent := TJSONObject(mCurrent).GetValue('parent');
    end;
  finally
    mResponse.Free;
  end;
end;

function TLspSessionRequests.LinkedLocals(const AFileName: string; ALine, ACharacter: Integer): TJSONValue;
var
  mParams: TJSONObject;
begin
  mParams := PositionParams(AFileName, ALine, ACharacter);
  mParams.AddPair('dpccLocals', TJSONBool.Create(True));
  Result := FClient.Request('textDocument/linkedEditingRange', mParams, FTimeoutMs);
end;

function TLspSessionRequests.TypeDefinition(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  mResponse: TJSONValue;
begin
  mResponse := FClient.Request('textDocument/typeDefinition', PositionParams(AFileName, ALine, ACharacter),
    FTimeoutMs * 2);
  try
    Result := LocationsOf(mResponse);
  finally
    mResponse.Free;
  end;
end;

function TLspSessionRequests.WorkspaceSymbols(const AQuery: string; ATimeoutMs: Cardinal): TArray<TDpccSymbol>;
var
  mResponse, mItem: TJSONValue;
  mEntry: TJSONObject;
  mSymbol: TDpccSymbol;
  mLocations: TArray<TLspLocation>;
  mLocation: TJSONValue;
begin
  Result := nil;
  mResponse := FClient.Request('workspace/symbol', TJSONObject.Create(TJSONPair.Create('query', AQuery)), ATimeoutMs);
  try
    if not (mResponse is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mResponse) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mEntry := TJSONObject(mItem);
      mSymbol := Default(TDpccSymbol);
      mSymbol.Name := mEntry.GetValue<string>('name', '');
      mSymbol.Container := mEntry.GetValue<string>('containerName', '');
      mSymbol.Kind := mEntry.GetValue<Integer>('kind', 0);
      mLocation := mEntry.GetValue('location');
      mLocations := LocationsOf(mLocation);
      if (mSymbol.Name = '') or (Length(mLocations) = 0) then
      begin
        Continue;
      end;
      mSymbol.FileName := mLocations[0].FileName;
      mSymbol.Line := mLocations[0].Line;
      mSymbol.Character := mLocations[0].Character;
      Result := Result + [mSymbol];
    end;
  finally
    mResponse.Free;
  end;
end;

function TLspSessionRequests.DocumentSymbolTree(const AFileName: string; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/documentSymbol',
    TJSONObject.Create(TJSONPair.Create('textDocument', TJSONObject.Create(TJSONPair.Create('uri',
    PathToUri(AFileName))))), ATimeoutMs);
end;

function TLspSessionRequests.DocumentSymbols(const AFileName: string; ATimeoutMs: Cardinal): TArray<TDpccSymbol>;
var
  mResponse: TJSONValue;
begin
  mResponse := DocumentSymbolTree(AFileName, ATimeoutMs);
  try
    Result := SymbolsOfDocument(mResponse, AFileName);
  finally
    mResponse.Free;
  end;
end;

function TLspSessionRequests.Definition(const AFileName, AText: string; ALine, ACharacter: Integer;
  out ALocation: TLspLocation): Boolean;
begin
  Result := Definition(AFileName, AText, ALine, ACharacter, FTimeoutMs, ALocation);
end;

/// <summary>Erstes Ziel der Anfrage AMethod (Location, Location[] oder LocationLink[]) an der Stelle.</summary>
function FirstLocation(AClient: TLspClient; const AMethod: string; AParams: TJSONObject; ATimeoutMs: Cardinal;
  out ALocation: TLspLocation): Boolean;
var
  mResponse: TJSONValue;
  mLocations: TArray<TLspLocation>;
begin
  ALocation := Default(TLspLocation);
  mResponse := AClient.Request(AMethod, AParams, ATimeoutMs);
  try
    mLocations := TLspSessionJson.LocationsOf(mResponse);
  finally
    mResponse.Free;
  end;
  // Nur das erste Ziel zählt: Die IDE springt an genau eine Stelle.
  Result := Length(mLocations) > 0;
  if Result then
  begin
    ALocation := mLocations[0];
  end;
end;

/// <summary>Rest der Wartezeit ATimeoutMs seit AStarted (TThread.GetTickCount64), mindestens 1 ms.</summary>
function RestOf(ATimeoutMs: Cardinal; AStarted: UInt64): Cardinal;
var
  mElapsed: UInt64;
begin
  mElapsed := TThread.GetTickCount64 - AStarted;
  if mElapsed >= ATimeoutMs then
  begin
    Result := 1;
  end
  else
  begin
    Result := ATimeoutMs - Cardinal(mElapsed);
  end;
end;

function TLspSessionRequests.Definition(const AFileName, AText: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal; out ALocation: TLspLocation): Boolean;
begin
  Sync(AFileName, AText);
  Result := FirstLocation(FClient, 'textDocument/definition', PositionParams(AFileName, ALine, ACharacter),
    TimeoutOr(ATimeoutMs), ALocation);
end;

function TLspSessionRequests.GotoTarget(const AFileName, AText: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal; out ALocation: TLspLocation): Boolean;
var
  mTable: TLineTable;
  mLineText: string;
begin
  Sync(AFileName, AText);
  // Nur die eine Zeile: Die Zeilentabelle zerlegt den Text nicht in Strings.
  mLineText := '';
  mTable := TLineTable.Build(AText);
  if (ALine >= 0) and (ALine < mTable.LineCount) then
  begin
    mLineText := Copy(AText, mTable.LineStart(ALine) + 1, mTable.LineContentEnd(ALine) - mTable.LineStart(ALine));
  end;
  Result := GotoTargetAt(AFileName, mLineText, ALine, ACharacter, ATimeoutMs, ALocation);
end;

const
  cDeclarationMethod = 'textDocument/declaration';
  cDefinitionMethod = 'textDocument/definition';

/// <summary>Grund aus dpcc/noTarget zur Anfrage AMethod an der Stelle aus ANoTargets abholen und mit ANoTarget
/// zusammenführen (der aussagekräftigere zählt). Ohne Benachrichtigung bleibt ANoTarget, mit AMethod.</summary>
procedure MergeNoTarget(const ANoTargets: IDpccNoTargets; const AMethod, AFileName: string; ALine,
  ACharacter: Integer; var ANoTarget: TDpccNoTarget);
var
  mFound: TDpccNoTarget;
begin
  if (ANoTargets <> nil) and ANoTargets.Take(AMethod, AFileName, ALine, ACharacter, TThread.GetTickCount64,
    mFound) then
  begin
    if mFound.Method = '' then
    begin
      mFound.Method := AMethod;
    end;
    ANoTarget := TDpccNoTarget.Better(ANoTarget, mFound);
  end
  else if ANoTarget.Method = '' then
  begin
    ANoTarget.Method := AMethod;
  end;
end;

function TLspSessionRequests.GotoTargetAt(const AFileName, ALineText: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal; out ALocation: TLspLocation): Boolean;
var
  mNoTarget: TDpccNoTarget;
begin
  Result := GotoTargetAt(AFileName, ALineText, ALine, ACharacter, ATimeoutMs, ALocation, mNoTarget);
end;

function TLspSessionRequests.GotoTargetAt(const AFileName, ALineText: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal; out ALocation: TLspLocation; out ANoTarget: TDpccNoTarget): Boolean;
begin
  Result := GotoTargetAt(AFileName, ALineText, ALine, ACharacter, ATimeoutMs, ALocation, ANoTarget, 0);
end;

/// <summary>Ziel fürs Ablaufprotokoll: „Datei Zeile:Spalte“ (Datei ohne Ordner, beides 1-basiert).</summary>
function FlowPlace(const ALocation: TLspLocation): string;
begin
  Result := TDpccFlow.PlaceText(ALocation.FileName, ALocation.Line + 1, ALocation.Character);
end;

/// <summary>Grund aus dpcc/noTarget fürs Ablaufprotokoll (Code, ohne Namen).</summary>
function FlowNoTarget(const ANoTarget: TDpccNoTarget): string;
begin
  Result := 'Grund ' + TDpccNoTarget.CodeOf(ANoTarget.Reason);
  if ANoTarget.Indexing then
  begin
    Result := Result + ', Index im Aufbau';
  end;
end;

function TLspSessionRequests.GotoTargetAt(const AFileName, ALineText: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal; out ALocation: TLspLocation; out ANoTarget: TDpccNoTarget; AFlowId: Integer): Boolean;
var
  mStarted: UInt64;
  mTimeout: Cardinal;
  mDeclared, mOffered, mFlow: Boolean;
  mImplementation: TLspLocation;
  mKey: string;
begin
  Result := False;
  ALocation := Default(TLspLocation);
  ANoTarget := Default(TDpccNoTarget);
  // Ablaufprotokoll (LOG1): ohne Kennung oder ausgeschaltet kein Text und kein Format.
  mFlow := (AFlowId > 0) and TDpccFlow.Enabled;
  // Wie der Empfänger die URI der Benachrichtigung liest: über die URI zum Pfad.
  mKey := UriToPath(PathToUri(AFileName));
  mTimeout := TimeoutOr(ATimeoutMs);
  mStarted := TThread.GetTickCount64;
  mDeclared := Offers(cDeclarationMethod);
  mOffered := mDeclared;
  if mDeclared then
  try
    Result := FirstLocation(FClient, cDeclarationMethod, PositionParams(AFileName, ALine, ACharacter),
      mTimeout, ALocation);
  except
    // Ein Server ohne declaration (erst die Antwort zeigt es): wie ohne declarationProvider.
    on ELspMethodNotFound do
      mDeclared := False;
    on E: Exception do
    begin
      // Nur festhalten, wo es endet; die Ausnahme geht wie bisher an den Aufrufer.
      if mFlow then
      begin
        TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, Format('declaration: Abbruch (%s) nach %d ms', [E.ClassName,
          Int64(TThread.GetTickCount64 - mStarted)]));
      end;
      raise;
    end;
  end;
  if not mDeclared then
  begin
    if mFlow then
    begin
      if mOffered then
      begin
        TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, 'declaration: -32601 (nicht unterstützt), frage definition');
      end
      else
      begin
        TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, 'declaration: vom Server nicht angeboten, frage definition');
      end;
    end;
    Result := FirstLocation(FClient, cDefinitionMethod, PositionParams(AFileName, ALine, ACharacter),
      RestOf(mTimeout, mStarted), ALocation);
    if not Result then
    begin
      MergeNoTarget(FNoTargets, cDefinitionMethod, mKey, ALine, ACharacter, ANoTarget);
    end;
    if mFlow then
    begin
      if Result then
      begin
        TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, 'definition: ' + FlowPlace(ALocation));
      end
      else
      begin
        TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, 'definition: leer (' + FlowNoTarget(ANoTarget) + ')');
      end;
    end;
    Exit;
  end;
  if not Result then
  begin
    MergeNoTarget(FNoTargets, cDeclarationMethod, mKey, ALine, ACharacter, ANoTarget);
    if mFlow then
    begin
      TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, 'declaration: leer (' + FlowNoTarget(ANoTarget) +
        '), definition nicht gefragt');
    end;
    Exit;
  end;
  if mFlow then
  begin
    TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, Format('declaration: %s nach %d ms', [FlowPlace(ALocation),
      Int64(TThread.GetTickCount64 - mStarted)]));
  end;
  if not Offers(cDefinitionMethod) then
  begin
    if mFlow then
    begin
      TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, 'definition: vom Server nicht angeboten, Ziel bleibt die ' +
        'Deklaration');
    end;
    Exit;
  end;
  if mFlow then
  begin
    // Das Urteil selbst fällt unten wie bisher über OnTarget; hier nur seine Teile.
    TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, 'OnTarget ' + TDpccGotoDefinition.OnTargetWhy(AFileName, ALine,
      ACharacter, ALineText, ALocation.FileName, ALocation.Line, ALocation.Character));
  end;
  if not TDpccGotoDefinition.OnTarget(AFileName, ALine, ACharacter, ALineText, ALocation.FileName, ALocation.Line,
    ALocation.Character) then
  begin
    if mFlow then
    begin
      TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, 'definition nicht gefragt: Klickstelle liegt nicht auf dem Ziel, ' +
        'Ziel bleibt die Deklaration');
    end;
    Exit;
  end;
  // Auf der Deklaration selbst: zur Implementierung, mit dem Rest der Wartezeit. Ohne Rest bleibt es beim Ziel.
  if Cardinal(TThread.GetTickCount64 - mStarted) >= mTimeout then
  begin
    if mFlow then
    begin
      TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, Format('definition nicht gefragt: Zeitlimit %d ms schon ' +
        'erreicht, Ziel bleibt die Deklaration', [Int64(mTimeout)]));
    end;
    Exit;
  end;
  try
    if FirstLocation(FClient, cDefinitionMethod, PositionParams(AFileName, ALine, ACharacter),
      RestOf(mTimeout, mStarted), mImplementation) then
    begin
      ALocation := mImplementation;
      if mFlow then
      begin
        TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, 'definition: ' + FlowPlace(mImplementation));
      end;
    end
    else
    begin
      // Die Deklaration bleibt das Ziel; den Grund zur leeren definition nur abholen, damit er nicht liegen bleibt.
      MergeNoTarget(FNoTargets, cDefinitionMethod, mKey, ALine, ACharacter, ANoTarget);
      if mFlow then
      begin
        TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, 'definition: leer, Ziel bleibt die Deklaration');
      end;
    end;
  except
    // Zeitlimit beim zweiten Schritt: Die Deklaration ist schon ein Ziel.
    on E: ELspClientError do
    begin
      if mFlow then
      begin
        TDpccFlow.Step(AFlowId, TDpccFlowArea.Jump, Format('definition: Abbruch (%s), Ziel bleibt die Deklaration',
          [E.ClassName]));
      end;
    end;
  end;
end;

function TLspSessionRequests.Definitions(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  mResponse: TJSONValue;
begin
  mResponse := FClient.Request('textDocument/definition', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := LocationsOf(mResponse);
  finally
    mResponse.Free;
  end;
end;

function TLspSessionRequests.Declarations(const AFileName: string; ALine, ACharacter: Integer): TArray<TLspLocation>;
var
  mResponse: TJSONValue;
begin
  mResponse := FClient.Request('textDocument/declaration', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    Result := LocationsOf(mResponse);
  finally
    mResponse.Free;
  end;
end;

function TLspSessionRequests.PrepareRename(const AFileName, AText: string; ALine, ACharacter: Integer;
  out APlaceholder: string): Boolean;
var
  mResponse: TJSONValue;
  mRange: TJSONObject;
  mPosition: TLspTextPosition;
  mStartOffset, mEndOffset: Integer;
begin
  APlaceholder := '';
  Sync(AFileName, AText);
  mResponse := FClient.Request('textDocument/prepareRename', PositionParams(AFileName, ALine, ACharacter), FTimeoutMs);
  try
    // Range, {range, placeholder} oder {defaultBehavior}; null heißt: hier nicht.
    if not (mResponse is TJSONObject) then
    begin
      Exit(False);
    end;
    if TJSONObject(mResponse).TryGetValue<string>('placeholder', APlaceholder) then
    begin
      Exit(True);
    end;
    if not TJSONObject(mResponse).TryGetValue<TJSONObject>('range', mRange) then
    begin
      mRange := TJSONObject(mResponse);
    end;
    if mRange.TryGetValue<Integer>('start.line', mPosition.Line) and
      mRange.TryGetValue<Integer>('start.character', mPosition.Character) then
    begin
      mStartOffset := TLspTextChanges.OffsetOf(AText, mPosition);
      mPosition.Line := mRange.GetValue<Integer>('end.line', mPosition.Line);
      mPosition.Character := mRange.GetValue<Integer>('end.character', mPosition.Character);
      mEndOffset := TLspTextChanges.OffsetOf(AText, mPosition);
      APlaceholder := Copy(AText, mStartOffset + 1, mEndOffset - mStartOffset);
    end;
    Result := True;
  finally
    mResponse.Free;
  end;
end;

function TLspSessionRequests.Rename(const AFileName: string; ALine, ACharacter: Integer; const ANewName: string;
  ATimeoutMs: Cardinal): TJSONValue;
var
  mParams: TJSONObject;
begin
  mParams := PositionParams(AFileName, ALine, ACharacter);
  mParams.AddPair('newName', ANewName);
  Result := FClient.Request('textDocument/rename', mParams, ATimeoutMs);
end;

function TLspSessionRequests.Completion(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/completion', PositionParams(AFileName, ALine, ACharacter), ATimeoutMs);
end;

function TLspSessionRequests.Completion(const AFileName: string; ALine, ACharacter: Integer; ATimeoutMs: Cardinal;
  const ATrigger: string; const AOnPartial: TLspPartialProc): TJSONValue;
var
  mParams: TJSONObject;
begin
  mParams := PositionParams(AFileName, ALine, ACharacter);
  // CompletionContext: triggerKind 2 = TriggerCharacter, 1 = Invoked.
  if ATrigger <> '' then
  begin
    mParams.AddPair('context', TJSONObject.Create.AddPair('triggerKind', TJSONNumber.Create(2))
      .AddPair('triggerCharacter', ATrigger));
  end;
  Result := FClient.Request('textDocument/completion', mParams, ATimeoutMs, AOnPartial);
end;

function TLspSessionRequests.SignatureHelp(const AFileName: string; ALine, ACharacter: Integer;
  ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('textDocument/signatureHelp', PositionParams(AFileName, ALine, ACharacter), ATimeoutMs);
end;

function TLspSessionRequests.ResolveCompletion(AItem: TJSONObject; ATimeoutMs: Cardinal): TJSONValue;
begin
  Result := FClient.Request('completionItem/resolve', AItem, ATimeoutMs);
end;

end.
