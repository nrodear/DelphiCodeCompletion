unit dpcc.Core.Completion.Providers.Expression;

// Datenquelle für die Vervollständigung in den Debugger-Dialogen (#538) über
// den Controller (#410). Der Kontext trägt hier den Ausdruck in Text, die
// Bezugszeile (0-basiert) in Line und die Schreibmarke im Feld in Character;
// FileName ist die Datei der Bezugszeile. Die IDE-Schicht gleicht diese Datei
// vorher im Hauptthread ab; Fetch fragt dpcc/expressionCompletion im
// Hintergrund. Mit Trigger = TDpccTriggers.cHistory kommt statt der
// Anfrage der Verlauf (dpcc.Core.Debug.DialogCompletion). Die LSP-Einträge
// übersetzt AItemsOf, das die Komposition mit der Übersetzung der Quelle
// Server belegt (Rollenmatrix: keine Providers untereinander).

interface

uses
  System.SysUtils,
  System.JSON,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Internals.Async,
  dpcc.Core.Lsp.Session;

{$SCOPEDENUMS ON}

type
  /// <summary>Antwort des Servers als Einträge.</summary>
  TDpccLspItemsFunc = reference to function(AResponse: TJSONValue): TDpccCompletionItems;

  TDpccExpressionCompletionProvider = class(TDpccAsyncCompletionProvider)
  public const
    cDefaultTimeoutMs = 2000;
  public
    /// <summary>Name der Quelle für die Sicherung (#493) und ihre Meldungen, in der Sprache der Oberfläche.
    /// </summary>
    class function ProviderTitle: string; static;
  private
    FSession: TDpccSessionFunc;
    FHistory: TFunc<TArray<string>>;
    FItemsOf: TDpccLspItemsFunc;
    FTimeoutMs: Cardinal;
    FHistoryCaption: string;
  protected
    function IsFailure(E: Exception): Boolean; override;
    function Prepare(const AContext: TDpccContext; out AData: TObject): Boolean; override;
    function Fetch(const AContext: TDpccContext; AData: TObject; const ACancelled: TDpccCancelledFunc;
      const AEmit: TDpccEmitProc; out AState: TDpccFetchState): TDpccCompletionItems; override;
  public
    /// <summary>AHistory: Verlauf des aktuellen Projekts, im Hintergrund aufgerufen (sperrt selbst).</summary>
    constructor Create(const ASession: TDpccSessionFunc; const AHistory: TFunc<TArray<string>>;
      const AItemsOf: TDpccLspItemsFunc; ATimeoutMs: Cardinal);
    /// <summary>Einträge des Verlaufs: der ganze Ausdruck ersetzt das Feld.</summary>
    class function HistoryItems(const AExpressions: TArray<string>; const ACaption: string):
      TDpccCompletionItems; static;
    /// <summary>Beschriftung der Verlaufseinträge (Signatur-Spalte).</summary>
    property HistoryCaption: string read FHistoryCaption write FHistoryCaption;
  end;

implementation

uses
  dpcc.Core.Lsp.Client,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TExpressionText = (CompletionDebugDialogs);

const
  cTexts: array[TDpccLanguage, TExpressionText] of string = (
    ('Vervollständigung (Debug-Dialoge)'),
    ('Completion (debug dialogs)'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TExpressionText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

{ TDpccExpressionCompletionProvider }

class function TDpccExpressionCompletionProvider.ProviderTitle: string;
begin
  Result := UiText(TExpressionText.CompletionDebugDialogs);
end;

constructor TDpccExpressionCompletionProvider.Create(const ASession: TDpccSessionFunc;
  const AHistory: TFunc<TArray<string>>; const AItemsOf: TDpccLspItemsFunc; ATimeoutMs: Cardinal);
begin
  inherited Create;
  Name := ProviderTitle;
  FSession := ASession;
  FHistory := AHistory;
  FItemsOf := AItemsOf;
  FTimeoutMs := ATimeoutMs;
end;

function TDpccExpressionCompletionProvider.IsFailure(E: Exception): Boolean;
begin
  // Server weg oder Zeitlimit: wie bei der Vervollständigung im Editor kein Fehler der Quelle.
  Result := inherited IsFailure(E) and not (E is ELspClientError);
end;

function TDpccExpressionCompletionProvider.Prepare(const AContext: TDpccContext; out AData: TObject): Boolean;
var
  mSession: TLspSession;
begin
  AData := nil;
  if AContext.Trigger = TDpccTriggers.cHistory then
  begin
    Exit(Assigned(FHistory));
  end;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  Result := (mSession <> nil) and (AContext.FileName <> '') and (AContext.Line >= 0);
  AData := mSession;
end;

function TDpccExpressionCompletionProvider.Fetch(const AContext: TDpccContext; AData: TObject;
  const ACancelled: TDpccCancelledFunc; const AEmit: TDpccEmitProc; out AState: TDpccFetchState):
  TDpccCompletionItems;
var
  mResponse: TJSONValue;
begin
  AState := Default(TDpccFetchState);
  if AContext.Trigger = TDpccTriggers.cHistory then
  begin
    Exit(HistoryItems(FHistory(), FHistoryCaption));
  end;
  mResponse := TLspSession(AData).ExpressionCompletion(AContext.FileName, AContext.Line, AContext.Text,
    AContext.Character, FTimeoutMs);
  try
    if ACancelled() then
    begin
      Exit(nil);
    end;
    // Antwort {prefix, items} in der Form einer CompletionList.
    Result := nil;
    if Assigned(FItemsOf) then
    begin
      Result := FItemsOf(mResponse);
    end;
  finally
    mResponse.Free;
  end;
end;

class function TDpccExpressionCompletionProvider.HistoryItems(const AExpressions: TArray<string>;
  const ACaption: string): TDpccCompletionItems;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AExpressions));
  for mIndex := 0 to High(AExpressions) do
  begin
    Result[mIndex] := Default(TDpccCompletionItem);
    Result[mIndex].Name := AExpressions[mIndex];
    Result[mIndex].Kind := TDpccItemKind.Unknown;
    Result[mIndex].Signature := ACaption;
    Result[mIndex].Rank := mIndex;
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Completion.Providers.Expression', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.
