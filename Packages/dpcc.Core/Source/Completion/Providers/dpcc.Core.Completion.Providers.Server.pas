unit dpcc.Core.Completion.Providers.Server;

// Standardquelle der Vervollständigung (#408): der dpcc-Server über die
// LSP-Sitzung des Plugins. Prepare gleicht im aufrufenden Thread
// (Zeitlimit-Arbeiter, #493) den Editortext ab (Sync ist threadsicher), Fetch
// fragt textDocument/completion im Hintergrund an
// und übersetzt die LSP-Einträge. Details für das Detailpanel (#405, #424)
// fragt Resolve über completionItem/resolve nach; der Server liefert sie
// strukturiert in data.dpcc.
//
// Gestaffelt (#616): Fetch fragt mit partialResultToken; der Server schickt zuerst den eigenen
// Gültigkeitsbereich, dann die Units aus uses, die Antwort bringt den Rest (Importe). Jedes Teilergebnis
// geht sofort ans Popup. Rank zählt über alle Teile fort.
//
// Lebensdauer: Die Sitzung gehört dem Aufrufer. Bevor er sie freigibt (Neustart
// des Servers, Entladen), muss er Shutdown aufrufen; das wartet auf laufende Anfragen.
//
// Befehl eines Eintrags (#473, perf1): RunCommand (IDpccCompletionCommandRunner) schickt
// workspace/executeCommand im Hintergrund (RunInBackground, Shutdown wartet darauf) und meldet
// Antwort bzw. Fehler im Hauptthread. Vorher wartete der Hauptthread beim Übernehmen bis zu 3 s.

interface

uses
  System.SysUtils,
  System.JSON,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Internals.Async,
  dpcc.Core.Lsp.Session;

type
  /// <summary>Alias für Bestandsnutzer; die Deklaration steht in dpcc.Core.Lsp.Session.</summary>
  TDpccSessionFunc = dpcc.Core.Lsp.Session.TDpccSessionFunc;
  /// <summary>Zeile fürs Diagnoselog des Plugins; ohne Namen aus dem Quelltext. Auch aus Hintergrund-Threads.</summary>
  TDpccProviderLog = reference to procedure(const AMessage: string);

  /// <summary>Ende eines Befehls im Hauptthread: Antwort als JSON ('' ohne Antwort) und Fehler (Klasse, '' ohne).
  /// </summary>
  TDpccCommandDone = reference to procedure(const AAnswerJson, AError: string);

  /// <summary>Befehl eines Eintrags (#473) im Hintergrund an den Server (perf1).</summary>
  IDpccCompletionCommandRunner = interface
    ['{5C1F7E2A-9B3D-4A61-8E0C-2D7B4F6A1C93}']
    /// <summary>workspace/executeCommand mit AArgumentsJson (JSON-Array; sonst leer) im Hintergrund; ADone im
    /// Hauptthread, solange die Quelle lebt. Nur im Hauptthread aufrufen. False ohne laufende Sitzung (ADone kommt
    /// dann nicht).</summary>
    function RunCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
      const ADone: TDpccCommandDone): Boolean;
  end;

  TDpccServerCompletionProvider = class(TDpccAsyncCompletionProvider, IDpccCompletionResolver,
    IDpccCompletionCommandRunner)
  public const
    cDefaultTimeoutMs = 2000;
  public
    /// <summary>Name der Quelle für die Sicherung (#493) und ihre Meldungen, in der Sprache der Oberfläche.
    /// </summary>
    class function ProviderTitle: string; static;
  private
    FSession: TDpccSessionFunc;
    FTimeoutMs: Cardinal;
    FResolveGeneration: Integer;
    FOnLog: TDpccProviderLog;
    procedure Log(const AMessage: string);
  protected
    /// <summary>Server weg oder Zeitlimit des Servers zählt nicht als Fehler der Quelle (#393 startet neu).</summary>
    function IsFailure(E: Exception): Boolean; override;
    function Prepare(const AContext: TDpccContext; out AData: TObject): Boolean; override;
    function Fetch(const AContext: TDpccContext; AData: TObject; const ACancelled: TDpccCancelledFunc;
      const AEmit: TDpccEmitProc; out AState: TDpccFetchState): TDpccCompletionItems; override;
  public
    constructor Create(const ASession: TDpccSessionFunc; ATimeoutMs: Cardinal); overload;
    /// <summary>Wie oben mit ATimeoutMs = DefaultTimeoutMs.</summary>
    constructor Create(const ASession: TDpccSessionFunc); overload;
    /// <summary>LSP-CompletionItemKind → Art des Eintrags.</summary>
    class function KindOf(ALspKind: Integer): TDpccItemKind; static;
    /// <summary>Ein CompletionItem des LSP; ARank ist seine Stelle in der Antwort.</summary>
    class function ItemFromLsp(AItem: TJSONObject; ARank: Integer): TDpccCompletionItem; static;
    /// <summary>Antwort auf textDocument/completion: CompletionList, CompletionItem[] oder null.</summary>
    class function ItemsFromLsp(AResponse: TJSONValue; AFirstRank: Integer): TDpccCompletionItems; overload; static;
    /// <summary>Wie oben mit AFirstRank = 0.</summary>
    class function ItemsFromLsp(AResponse: TJSONValue): TDpccCompletionItems; overload; static;
    /// <summary>Hinweis bei unvollständigem Code (#457) aus "syntaxNotice" der CompletionList; Sure ohne.</summary>
    class function SyntaxNoticeOf(AResponse: TJSONValue): TDpccSyntaxNotice; static;
    /// <summary>Details aus der Antwort auf completionItem/resolve (data.dpcc, sonst detail/documentation).</summary>
    class function DetailsFromLsp(AResponse: TJSONValue): TDpccItemDetails; static;
    { IDpccCompletionResolver }
    function Resolve(const AItem: TDpccCompletionItem; const ACallback: TDpccDetailsCallback): Boolean;
    { IDpccCompletionCommandRunner }
    function RunCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
      const ADone: TDpccCommandDone): Boolean;
    /// <summary>Warum die Liste leer bleibt (kein Server, keine Antwort) und wie lange der Server brauchte.</summary>
    property OnLog: TDpccProviderLog read FOnLog write FOnLog;
  end;

implementation

uses
  System.StrUtils,
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  System.Generics.Collections,
  dpcc.Core.Completion.Placeholders,
  dpcc.Core.Documentation.Contract,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Lsp.Client,
  dpcc.Core.Localization.Language,
  dpcc.Text.Json;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TServerText = (CompletionServer);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TServerText] of string = (
    ('Vervollständigung (Server)'),
    ('Completion (server)'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TServerText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

{ TDpccServerCompletionProvider }

class function TDpccServerCompletionProvider.ProviderTitle: string;
begin
  Result := UiText(TServerText.CompletionServer);
end;

constructor TDpccServerCompletionProvider.Create(const ASession: TDpccSessionFunc);
begin
  Create(ASession, cDefaultTimeoutMs);
end;

constructor TDpccServerCompletionProvider.Create(const ASession: TDpccSessionFunc; ATimeoutMs: Cardinal);
begin
  inherited Create;
  Name := ProviderTitle;
  FSession := ASession;
  FTimeoutMs := ATimeoutMs;
end;

function TDpccServerCompletionProvider.IsFailure(E: Exception): Boolean;
begin
  Result := inherited IsFailure(E) and not (E is ELspClientError);
end;

class function TDpccServerCompletionProvider.KindOf(ALspKind: Integer): TDpccItemKind;
const
  // Index: CompletionItemKind des LSP; nicht abgebildete Arten bleiben Unknown.
  cLspKinds: array[0..25] of TDpccItemKind = (
    TDpccItemKind.Unknown, // 0
    TDpccItemKind.Unknown, // 1
    TDpccItemKind.Method, // 2
    TDpccItemKind.Function_, // 3
    TDpccItemKind.Constructor_, // 4
    TDpccItemKind.Field, // 5
    TDpccItemKind.Variable, // 6
    TDpccItemKind.Class_, // 7
    TDpccItemKind.Interface_, // 8
    TDpccItemKind.Unit_, // 9
    TDpccItemKind.Property_, // 10
    TDpccItemKind.Unknown, // 11
    TDpccItemKind.Unknown, // 12
    TDpccItemKind.Enum, // 13
    TDpccItemKind.Keyword, // 14
    TDpccItemKind.Snippet, // 15
    TDpccItemKind.Unknown, // 16
    TDpccItemKind.Unknown, // 17
    TDpccItemKind.Unknown, // 18
    TDpccItemKind.Unknown, // 19
    TDpccItemKind.EnumMember, // 20
    TDpccItemKind.Constant, // 21
    TDpccItemKind.Record_, // 22
    TDpccItemKind.Event, // 23
    TDpccItemKind.Unknown, // 24
    TDpccItemKind.Type_); // 25
begin
  if (ALspKind < Low(cLspKinds)) or (ALspKind > High(cLspKinds)) then
  begin
    Exit(TDpccItemKind.Unknown);
  end;
  Result := cLspKinds[ALspKind];
end;

function EditFromLsp(AEdit: TJSONObject; out AResult: TDpccTextEdit): Boolean;
begin
  AResult := Default(TDpccTextEdit);
  Result := AEdit.TryGetValue<Integer>('range.start.line', AResult.StartLine) and
    AEdit.TryGetValue<Integer>('range.start.character', AResult.StartCharacter) and
    AEdit.TryGetValue<Integer>('range.end.line', AResult.EndLine) and
    AEdit.TryGetValue<Integer>('range.end.character', AResult.EndCharacter) and
    AEdit.TryGetValue<string>('newText', AResult.NewText);
end;

/// <summary>LSP-Range ohne Text (#448).</summary>
function RangeFromLsp(ARange: TJSONObject; out AResult: TDpccTextEdit): Boolean;
begin
  AResult := Default(TDpccTextEdit);
  Result := ARange.TryGetValue<Integer>('start.line', AResult.StartLine) and
    ARange.TryGetValue<Integer>('start.character', AResult.StartCharacter) and
    ARange.TryGetValue<Integer>('end.line', AResult.EndLine) and
    ARange.TryGetValue<Integer>('end.character', AResult.EndCharacter);
end;

/// <summary>Die Strings eines JSON-Arrays; leer, wenn AValue kein Array ist.</summary>
function StringsOf(AValue: TJSONValue): TArray<string>;
var
  mValue: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mValue in TJSONArray(AValue) do
    begin
      if mValue is TJSONString then
      begin
        Result := Result + [TJSONString(mValue).Value];
      end;
    end;
  end;
end;

/// <summary>documentation (string oder MarkupContent) und data unverändert für completionItem/resolve.</summary>
procedure ReadDocumentation(AItem: TJSONObject; var AResult: TDpccCompletionItem);
var
  mDocumentation: TJSONValue;
begin
  mDocumentation := AItem.GetValue('documentation');
  if mDocumentation is TJSONString then
  begin
    AResult.Documentation := TJSONString(mDocumentation).Value;
  end
  else if mDocumentation is TJSONObject then
  begin
    AResult.Documentation := TJSONObject(mDocumentation).GetValue<string>('value', '');
  end;
  if AItem.GetValue('data') <> nil then
  begin
    AResult.ResolveData := AItem.GetValue('data').ToJSON;
  end;
end;

/// <summary>Herkunft, Vererbungstiefe, Helper (#419, #425, #456), andere Unit und verdeckte Deklarationen (#488),
/// Mitglied eines with-Objekts (#481).</summary>
procedure ReadOrigin(AData: TJSONObject; var AResult: TDpccCompletionItem);
begin
  AResult.DeclaringClass := AData.GetValue<string>('container', '');
  AResult.Depth := AData.GetValue<Integer>('depth', 0);
  AResult.IsHelper := AData.GetValue('helper') is TJSONTrue;
  AResult.Condition := AData.GetValue<string>('condition', '');
  AResult.VariantBranch := AData.GetValue<string>('variant', '');
  AResult.Unavailable := AData.GetValue('unavailable') is TJSONTrue;
  AResult.Scope := AData.GetValue<Integer>('scope', 0);
  AResult.DeclaringUnit := AData.GetValue<string>('unit', '');
  AResult.Hides := StringsOf(AData.GetValue('hides'));
  AResult.WithOrigin := AData.GetValue<string>('withOrigin', '');
  AResult.WithShadows := StringsOf(AData.GetValue('withShadows'));
  AResult.HasParameters := AData.GetValue('parameters') is TJSONTrue;
  AResult.ExpectedType := AData.GetValue<string>('expected', '');
  AResult.Fits := AData.GetValue('fits') is TJSONTrue;
end;

/// <summary>Einträge, die Code erzeugen: Aktionen, Postfix-Vorlagen, Aufzählungen und Mengen, case, Interface,
/// Formular, Sender und Typkonvertierung.</summary>
procedure ReadActions(AItem, AData: TJSONObject; var AResult: TDpccCompletionItem);
begin
  // Neue Methode (#444), Deklarationen unbekannter Namen (#471) und „Parameter abgleichen“ (#88) erzeugen
  // Code und stehen am Ende; ihre Zusatzänderungen gelten auch ohne automatische uses-Einträge.
  AResult.IsAction := MatchText(AData.GetValue<string>('action', ''), ['create', 'declare', 'docParams']);
  // Postfix-Vorlagen (#188): Der Server filtert über "Ausdruck.Kürzel"; getippt ist hier nur das Wort hinter
  // dem Punkt, also gilt der Teil nach dem letzten Punkt.
  AResult.Postfix := AData.GetValue<string>('action', '') = 'postfix';
  if AResult.Postfix then
  begin
    AResult.FilterText := AItem.GetValue<string>('filterText', AResult.Name);
    AResult.FilterText := Copy(AResult.FilterText, LastDelimiter('.', AResult.FilterText) + 1, MaxInt);
  end;
  AResult.Unknown := AData.GetValue<string>('unknown', '');
  // Aufzählungen und Mengen (#448).
  AResult.Ordinal := AData.GetValue<Integer>('ordinal', 0);
  AResult.SetOf := AData.GetValue<string>('setOf', '');
  AResult.Checked := AData.GetValue('checked') is TJSONTrue;
  if (AResult.SetOf <> '') and not ((AData.GetValue('setRange') is TJSONObject) and
    RangeFromLsp(TJSONObject(AData.GetValue('setRange')), AResult.SetRange)) then
  begin
    AResult.SetOf := '';
  end;
  // case vervollständigen (#449).
  AResult.Pinned := AData.GetValue('pinned') is TJSONTrue;
  AResult.Count := AData.GetValue<Integer>('count', 0);
  // Interface implementieren (#466).
  AResult.Batch := AData.GetValue('batch') is TJSONTrue;
  AResult.Hint := AData.GetValue('hint') is TJSONTrue;
  // Komponenten aus dem Formular (#455).
  AResult.Form := AData.GetValue<string>('form', '');
  AResult.ByType := AData.GetValue('byType') is TJSONTrue;
  // Sender mit Typumwandlung (#480).
  AResult.Sender := AData.GetValue<string>('sender', '');
  AResult.SenderOf := AData.GetValue<string>('senderOf', '');
  // Typkonvertierung (#490): filtert nach dem Namen des Originals, nicht nach dem Ausdruck.
  AResult.Conversion := AData.GetValue<string>('conversion', '');
  AResult.ConvertFrom := AData.GetValue<string>('convertFrom', '');
  if AResult.Conversion <> '' then
  begin
    AResult.FilterText := AResult.ConvertFrom;
  end;
  AResult.Lossy := AData.GetValue<string>('lossy', '');
end;

/// <summary>Alle Felder zuweisen (#491): Zeilen für die Liste mit Kontrollkästchen.</summary>
function AssignmentsOf(AValue: TJSONValue): TArray<TDpccAssignment>;
var
  mValue: TJSONValue;
  mAssignment: TDpccAssignment;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mValue in TJSONArray(AValue) do
  begin
    if mValue is TJSONObject then
    begin
      mAssignment.Name := TJSONObject(mValue).GetValue<string>('name', '');
      mAssignment.Detail := TJSONObject(mValue).GetValue<string>('detail', '');
      mAssignment.Text := TJSONObject(mValue).GetValue<string>('text', '');
      if mAssignment.Name <> '' then
      begin
        Result := Result + [mAssignment];
      end;
    end;
  end;
end;

/// <summary>Feld- und Parameternamen (#461), Freigabe (#489), Typargumente (#450), Attribute (#465), anonyme
/// Methoden (#468), Exception-Klassen (#483).</summary>
procedure ReadNames(AData: TJSONObject; var AResult: TDpccCompletionItem);
begin
  AResult.DataSet := AData.GetValue<string>('dataSet', '');
  AResult.DataSource := AData.GetValue<string>('dataSource', '');
  AResult.Guard := AData.GetValue<string>('guard', '') <> '';
  AResult.TypeParam := AData.GetValue<string>('typeParam', '');
  AResult.Constraint := AData.GetValue<string>('constraint', '');
  AResult.ConstraintHint := AData.GetValue<string>('constraintHint', '');
  AResult.HiddenKinds := AData.GetValue<string>('hiddenKinds', '');
  AResult.Attribute := AData.GetValue('attribute') is TJSONTrue;
  AResult.MethodRef := AData.GetValue<string>('methodRef', '');
  AResult.ExceptionGroup := AData.GetValue<string>('exceptionGroup', '');
  AResult.Unreachable := AData.GetValue<string>('unreachable', '');
end;

/// <summary>uses-Abschnitt (#469), vollständiger inherited-Aufruf (#482), gleichnamige Bezeichner aus
/// verschiedenen Units (#475) und Platzhalter in weiteren Änderungen (#473).</summary>
procedure ReadUses(AData: TJSONObject; var AResult: TDpccCompletionItem);
begin
  // Gefiltert wird nach dem Namensteil ab dem Getippten ("Classes" für System.Classes).
  AResult.UsesGroup := AData.GetValue<string>('usesGroup', '');
  if AData.GetValue<string>('usesFilter', '') <> '' then
  begin
    AResult.FilterText := AData.GetValue<string>('usesFilter', '');
  end;
  AResult.UsesElsewhere := AData.GetValue<string>('usesElsewhere', '');
  AResult.UsesCycle := AData.GetValue<string>('usesCycle', '');
  AResult.UsesTypes := StringsOf(AData.GetValue('usesTypes'));
  AResult.UsesTypeCount := AData.GetValue<Integer>('usesTypeCount', 0);
  AResult.UsesHidden := StringsOf(AData.GetValue('usesHidden'));
  AResult.InheritedMatch := AData.GetValue<string>('inheritedMatch', '');
  AResult.InheritedAbstract := StringsOf(AData.GetValue('inheritedAbstract'));
  AResult.SameNameActive := AData.GetValue<Boolean>('sameNameActive', False);
  AResult.SameNameOf := AData.GetValue<string>('sameNameOf', '');
  AResult.SameNameInsert := AData.GetValue<string>('sameNameInsert', '');
  AResult.SameNameUnits := StringsOf(AData.GetValue('sameNameUnits'));
  AResult.SameNameHidden := StringsOf(AData.GetValue('sameNameHidden'));
  AResult.LinkedEdits := AData.GetValue<Boolean>('linkedEdits', False);
end;

/// <summary>Überladungen (#456): gleiche Datei, andere Position; ein data je Überladung für
/// completionItem/resolve.</summary>
function OverloadDataOf(AData: TJSONObject): TArray<string>;
var
  mValue: TJSONValue;
  mTwin: TJSONObject;
begin
  Result := nil;
  if not (AData.GetValue('overloads') is TJSONArray) then
  begin
    Exit;
  end;
  for mValue in TJSONArray(AData.GetValue('overloads')) do
  begin
    if mValue is TJSONObject then
    begin
      mTwin := AData.Clone as TJSONObject;
      try
        mTwin.RemovePair('overloads').Free;
        mTwin.RemovePair('line').Free;
        mTwin.RemovePair('character').Free;
        mTwin.AddPair('line', TJSONNumber.Create(TJSONObject(mValue).GetValue<Integer>('line', 0)));
        mTwin.AddPair('character', TJSONNumber.Create(TJSONObject(mValue).GetValue<Integer>('character', 0)));
        Result := Result + [mTwin.ToJSON];
      finally
        mTwin.Free;
      end;
    end;
  end;
end;

/// <summary>textEdit (#188) und additionalTextEdits; danach, ob die Unit schon eingebunden ist.</summary>
procedure ReadEdits(AItem: TJSONObject; var AResult: TDpccCompletionItem);
var
  mValue: TJSONValue;
  mEdit: TDpccTextEdit;
begin
  // textEdit ersetzt mehr als das getippte Wort, etwa den Ausdruck vor dem Punkt.
  // Ein textEdit ohne Text ersetzt nichts sinnvoll; ignorieren statt den Bereich zu löschen. Ausnahme: Der Hinweis
  // „Methoden fehlen“ (#466) entfernt das getippte Wort, der Code kommt über die weiteren Änderungen.
  if (AItem.GetValue('textEdit') is TJSONObject) and EditFromLsp(TJSONObject(AItem.GetValue('textEdit')), mEdit) and
    ((mEdit.NewText <> '') or AResult.Hint) then
  begin
    AResult.HasTextEdit := True;
    AResult.TextEdit := mEdit;
  end;
  if AItem.GetValue('additionalTextEdits') is TJSONArray then
  begin
    for mValue in TJSONArray(AItem.GetValue('additionalTextEdits')) do
    begin
      if (mValue is TJSONObject) and EditFromLsp(TJSONObject(mValue), mEdit) then
      begin
        AResult.AdditionalEdits := AResult.AdditionalEdits + [mEdit];
      end;
    end;
  end;
  // Bis #405 "Unit eingebunden" liefert: Ein Eintrag mit uses-Ergänzung (#180) kommt aus
  // einer noch nicht eingebundenen Unit. Einträge mit data.action (override, neue Methode;
  // #443, #444) ergänzen Code statt uses.
  AResult.UnitUsed := (Length(AResult.AdditionalEdits) = 0) or
    ((AItem.GetValue('data') is TJSONObject) and (TJSONObject(AItem.GetValue('data')).GetValue('action') <> nil));
end;

/// <summary>Eintrag des Servers mit Platzhaltern (#51, insertTextFormat 2 = LSP-Snippet): Text für den
/// Platzhalter-Modus im eigenen Format.</summary>
procedure ReadPlaceholders(AItem: TJSONObject; var AResult: TDpccCompletionItem);
var
  mIndex: Integer;
begin
  if (AItem.GetValue('insertTextFormat') is TJSONNumber) and
    (TJSONNumber(AItem.GetValue('insertTextFormat')).AsInt = 2) then
  begin
    if AResult.HasTextEdit then
    begin
      AResult.PlaceholderText := TDpccPlaceholderText.FromLsp(AResult.TextEdit.NewText);
    end
    else if AResult.InsertText <> '' then
    begin
      AResult.PlaceholderText := TDpccPlaceholderText.FromLsp(AResult.InsertText);
    end
    else
    begin
      AResult.PlaceholderText := TDpccPlaceholderText.FromLsp(AResult.Name);
    end;
  end;
  if AResult.PlaceholderText = '' then
  begin
    AResult.LinkedEdits := False;
  end;
  if AResult.LinkedEdits then
  begin
    for mIndex := 0 to High(AResult.AdditionalEdits) do
    begin
      AResult.AdditionalEdits[mIndex].NewText :=
        TDpccPlaceholderText.FromLsp(AResult.AdditionalEdits[mIndex].NewText);
    end;
  end;
end;

/// <summary>Befehl nach dem Übernehmen (#473), etwa den resourcestring in eine andere Unit schreiben.</summary>
procedure ReadCommand(AItem: TJSONObject; var AResult: TDpccCompletionItem);
begin
  if AItem.GetValue('command') is TJSONObject then
  begin
    AResult.Command := TJSONObject(AItem.GetValue('command')).GetValue<string>('command', '');
    AResult.CommandArguments := '[]';
    if TJSONObject(AItem.GetValue('command')).GetValue('arguments') is TJSONArray then
    begin
      AResult.CommandArguments := TJSONObject(AItem.GetValue('command')).GetValue('arguments').ToJSON;
    end;
  end;
end;

class function TDpccServerCompletionProvider.ItemFromLsp(AItem: TJSONObject; ARank: Integer): TDpccCompletionItem;
var
  mData: TJSONObject;
begin
  Result := Default(TDpccCompletionItem);
  Result.Name := AItem.GetValue<string>('label', '');
  Result.Kind := KindOf(AItem.GetValue<Integer>('kind', 0));
  Result.Signature := AItem.GetValue<string>('detail', '');
  Result.InsertText := AItem.GetValue<string>('insertText', '');
  // filterText nicht übernehmen: Der Server setzt dort bei unscharfen Treffern das getippte
  // Wort, damit VS Code sie nicht verwirft. dpcc filtert selbst gegen den Namen (#409);
  // sonst passt jeder Eintrag genau (in der IDE: "mylist" zeigte ERROR_TOO_MANY_LINKS).
  Result.Rank := ARank;
  ReadDocumentation(AItem, Result);
  if AItem.GetValue('data') is TJSONObject then
  begin
    mData := TJSONObject(AItem.GetValue('data'));
    ReadOrigin(mData, Result);
    ReadActions(AItem, mData, Result);
    Result.Assignments := AssignmentsOf(mData.GetValue('assign'));
    ReadNames(mData, Result);
    ReadUses(mData, Result);
    Result.OverloadData := OverloadDataOf(mData);
  end;
  ReadEdits(AItem, Result);
  ReadPlaceholders(AItem, Result);
  ReadCommand(AItem, Result);
end;

class function TDpccServerCompletionProvider.SyntaxNoticeOf(AResponse: TJSONValue): TDpccSyntaxNotice;
var
  mNotice: TJSONValue;
  mTrust: string;
begin
  Result := Default(TDpccSyntaxNotice);
  Result.Line := -1;
  Result.Character := -1;
  if not (AResponse is TJSONObject) then
  begin
    Exit;
  end;
  mNotice := TJSONObject(AResponse).GetValue('syntaxNotice');
  if not (mNotice is TJSONObject) then
  begin
    Exit;
  end;
  mTrust := TJSONObject(mNotice).GetValue<string>('trust', '');
  if mTrust = 'limited' then
  begin
    Result.Trust := TDpccSyntaxTrust.Limited;
  end
  else if mTrust = 'unknown' then
  begin
    Result.Trust := TDpccSyntaxTrust.Unknown;
  end
  else
  begin
    Exit;
  end;
  Result.Line := TJSONObject(mNotice).GetValue<Integer>('line', -1);
  Result.Character := TJSONObject(mNotice).GetValue<Integer>('character', -1);
  Result.Message := TJSONObject(mNotice).GetValue<string>('message', '');
end;

class function TDpccServerCompletionProvider.ItemsFromLsp(AResponse: TJSONValue): TDpccCompletionItems;
begin
  Result := ItemsFromLsp(AResponse, 0);
end;

class function TDpccServerCompletionProvider.ItemsFromLsp(AResponse: TJSONValue;
  AFirstRank: Integer): TDpccCompletionItems;
var
  mItems: TJSONValue;
  mIndex, mCount: Integer;
begin
  Result := nil;
  if AResponse is TJSONObject then
  begin
    mItems := TJSONObject(AResponse).GetValue('items');
  end
  else
  begin
    mItems := AResponse;
  end;
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  // Einmal anlegen statt je Eintrag anzuhängen: Das kopierte bei 1000 Einträgen die ganze Liste jedes Mal (#616).
  SetLength(Result, TJSONArray(mItems).Count);
  mCount := 0;
  for mIndex := 0 to TJSONArray(mItems).Count - 1 do
  begin
    if TJSONArray(mItems).Items[mIndex] is TJSONObject then
    begin
      Result[mCount] := ItemFromLsp(TJSONObject(TJSONArray(mItems).Items[mIndex]), AFirstRank + mIndex);
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

procedure TDpccServerCompletionProvider.Log(const AMessage: string);
begin
  if Assigned(FOnLog) then
  begin
    FOnLog(AMessage);
  end;
end;

function TDpccServerCompletionProvider.Prepare(const AContext: TDpccContext; out AData: TObject): Boolean;
var
  mSession: TLspSession;
begin
  AData := nil;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  Result := (mSession <> nil) and (AContext.FileName <> '');
  if not Result then
  begin
    if mSession = nil then
    begin
      Log('Vervollständigung: kein Server verbunden');
    end;
    Exit;
  end;
  // Sync ist threadsicher (FDocLock in TLspSession); hier im Zeitlimit-Arbeiter.
  mSession.Sync(AContext.FileName, AContext.Text);
  AData := mSession;
end;

function TDpccServerCompletionProvider.Fetch(const AContext: TDpccContext; AData: TObject;
  const ACancelled: TDpccCancelledFunc; const AEmit: TDpccEmitProc;
    out AState: TDpccFetchState): TDpccCompletionItems;
var
  mResponse: TJSONValue;
  mNextRank: Integer;
  mEmit: TDpccEmitProc;
  mWatch: TStopwatch;
begin
  AState := Default(TDpccFetchState);
  mNextRank := 0;
  mEmit := AEmit;
  mWatch := TStopwatch.StartNew;
  // Teilergebnisse kommen im Lese-Thread nacheinander und alle vor der Antwort.
  mResponse := TLspSession(AData).Completion(AContext.FileName, AContext.Line, AContext.Character, FTimeoutMs,
    AContext.Trigger,
    procedure(const AValue: TJSONValue)
    var
      Items: TDpccCompletionItems;
    begin
      if not (AValue is TJSONArray) then
      begin
        Exit;
      end;
      Items := ItemsFromLsp(AValue, mNextRank);
      Inc(mNextRank, TJSONArray(AValue).Count);
      mEmit(Items);
    end);
  try
    // Ohne Antwort bleibt die Liste leer; das Zeitlimit ist FTimeoutMs.
    if mResponse = nil then
    begin
      Log(Format('Vervollständigung: keine Antwort nach %d ms (%d Teilergebnisse)',
        [mWatch.ElapsedMilliseconds, mNextRank]));
    end
    else
    begin
      Log(Format('Vervollständigung: Antwort nach %d ms', [mWatch.ElapsedMilliseconds]));
    end;
    if ACancelled() then
    begin
      Exit(nil);
    end;
    // CompletionList mit isIncomplete: Der Server hat gekürzt und will beim Weitertippen neu gefragt werden.
    // Ohne GetValue<Boolean>: das lässt über TValue Speicher liegen (Leck-Monitor).
    AState.Incomplete := (mResponse is TJSONObject) and (TJSONObject(mResponse).GetValue('isIncomplete') is TJSONBool) and
      TJSONBool(TJSONObject(mResponse).GetValue('isIncomplete')).AsBoolean;
    AState.Syntax := SyntaxNoticeOf(mResponse);
    Result := ItemsFromLsp(mResponse, mNextRank);
  finally
    mResponse.Free;
  end;
end;

function EntriesOf(AObject: TJSONObject; const AName: string): TArray<TDpccDocEntry>;
var
  mValue, mItem: TJSONValue;
  mEntry: TDpccDocEntry;
begin
  Result := nil;
  mValue := AObject.GetValue(AName);
  if not (mValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mValue) do
  begin
    if mItem is TJSONObject then
    begin
      mEntry.Name := TJsonRead.Text(TJSONObject(mItem), 'name');
      mEntry.Text := TJsonRead.Text(TJSONObject(mItem), 'text');
      Result := Result + [mEntry];
    end;
  end;
end;

class function TDpccServerCompletionProvider.DetailsFromLsp(AResponse: TJSONValue): TDpccItemDetails;
var
  mData, mDpcc, mDirectives, mItem: TJSONValue;
  mDocumentation: TJSONValue;
begin
  Result := Default(TDpccItemDetails);
  if not (AResponse is TJSONObject) then
  begin
    Exit;
  end;
  mData := TJSONObject(AResponse).GetValue('data');
  mDpcc := nil;
  if mData is TJSONObject then
  begin
    mDpcc := TJSONObject(mData).GetValue('dpcc');
  end;
  if mDpcc is TJSONObject then
  begin
    Result.Declaration := TJsonRead.Text(TJSONObject(mDpcc), 'declaration');
    Result.UnitName := TJsonRead.Text(TJSONObject(mDpcc), 'unit');
    Result.Container := TJsonRead.Text(TJSONObject(mDpcc), 'container');
    Result.IsHelper := TJSONObject(mDpcc).GetValue('helper') is TJSONTrue;
    Result.Visibility := TJsonRead.Text(TJSONObject(mDpcc), 'visibility');
    Result.IsDeprecated := TJSONObject(mDpcc).GetValue('deprecated') <> nil;
    Result.DeprecatedText := TJsonRead.Text(TJSONObject(mDpcc), 'deprecated');
    Result.Summary := TJsonRead.Text(TJSONObject(mDpcc), 'summary');
    Result.Returns := TJsonRead.Text(TJSONObject(mDpcc), 'returns');
    Result.Remarks := TJsonRead.Text(TJSONObject(mDpcc), 'remarks');
    Result.Params := EntriesOf(TJSONObject(mDpcc), 'params');
    Result.Exceptions := EntriesOf(TJSONObject(mDpcc), 'exceptions');
    Result.Doc := TDpccDoc.FromJson(TJSONObject(mDpcc).GetValue('documentation'));
    Result.Display := TDpccDocDisplay.FromJson(TJSONObject(mDpcc).GetValue('xmlDoc'),
      TDpccDocDisplay.Create(TDpccDocExpand.Last, 0));
    mDirectives := TJSONObject(mDpcc).GetValue('directives');
    if mDirectives is TJSONArray then
    begin
      for mItem in TJSONArray(mDirectives) do
      begin
        if mItem is TJSONString then
        begin
          Result.Directives := Result.Directives + [TJSONString(mItem).Value];
        end;
      end;
    end;
    Exit;
  end;
  // Andere Server: detail als Deklaration, documentation als Beschreibung.
  Result.Declaration := TJsonRead.Text(TJSONObject(AResponse), 'detail');
  mDocumentation := TJSONObject(AResponse).GetValue('documentation');
  if mDocumentation is TJSONString then
  begin
    Result.Summary := TJSONString(mDocumentation).Value;
  end
  else if mDocumentation is TJSONObject then
  begin
    Result.Summary := TJsonRead.Text(TJSONObject(mDocumentation), 'value');
  end;
end;

/// <summary>Anfrage für completionItem/resolve: nur label und data, mehr braucht der Server nicht.</summary>
function ResolveRequest(const AItem: TDpccCompletionItem): string;
var
  mItem: TJSONObject;
begin
  mItem := TJSONObject.Create;
  try
    mItem.AddPair('label', AItem.Name);
    mItem.AddPair('data', TJSONObject.ParseJSONValue(AItem.ResolveData));
    Result := mItem.ToJSON;
  finally
    mItem.Free;
  end;
end;

/// <summary>ADetails mit dem, was der Eintrag selbst schon weiß: verdeckte Deklarationen, with-Objekt und
/// verlustbehaftete Konvertierung.</summary>
function WithItemFacts(const ADetails: TDpccItemDetails; const AItem: TDpccCompletionItem): TDpccItemDetails;
begin
  Result := ADetails;
  Result.Hides := AItem.Hides;
  Result.WithOrigin := AItem.WithOrigin;
  Result.LossyFrom := AItem.Lossy;
  Result.LossyTo := '';
  if AItem.Lossy <> '' then
  begin
    Result.LossyTo := AItem.ExpectedType;
  end;
end;

function TDpccServerCompletionProvider.Resolve(const AItem: TDpccCompletionItem;
  const ACallback: TDpccDetailsCallback): Boolean;
var
  mSession: TLspSession;
  mRequest: string;
  mGeneration: Integer;
  mAliveToken: TDpccAliveToken;
  mAliveRef: IInterface;
  mProvider: TDpccServerCompletionProvider;
  mCallback: TDpccDetailsCallback;
  mItem: TDpccCompletionItem;
begin
  Result := False;
  if AItem.ResolveData = '' then
  begin
    Exit;
  end;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if mSession = nil then
  begin
    Exit;
  end;
  mRequest := ResolveRequest(AItem);
  mItem := AItem;
  mGeneration := TInterlocked.Increment(FResolveGeneration);
  mAliveToken := Token;
  mAliveRef := TokenRef;
  mProvider := Self;
  mCallback := ACallback;
  RunInBackground(
    procedure
    var
      Response: TJSONValue;
      Details: TDpccItemDetails;
    begin
      Response := mSession.ResolveCompletion(TJSONObject.ParseJSONValue(mRequest) as TJSONObject, FTimeoutMs);
      try
        Details := WithItemFacts(DetailsFromLsp(Response), mItem);
      finally
        Response.Free;
      end;
      // Der Rückruf zeigt das Detailpanel; die Hülle zählt seine Fehler für die Vervollständigung.
      TDpccMainThread.Queue(TDpccFeature.Completion,
        procedure
        begin
          if mAliveToken.Alive and (mAliveRef <> nil) and
            (TInterlocked.CompareExchange(mProvider.FResolveGeneration, 0, 0) = mGeneration) then
          begin
            mCallback(Details);
          end;
        end);
    end);
  Result := True;
end;

function TDpccServerCompletionProvider.RunCommand(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
  const ADone: TDpccCommandDone): Boolean;
var
  mSession: TLspSession;
  mCommand, mArgumentsJson: string;
  mTimeoutMs: Cardinal;
  mAliveToken: TDpccAliveToken;
  mAliveRef: IInterface;
  mDone: TDpccCommandDone;
begin
  Result := False;
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if (mSession = nil) or not mSession.Initialized then
  begin
    Exit;
  end;
  mCommand := ACommand;
  mArgumentsJson := AArgumentsJson;
  mTimeoutMs := ATimeoutMs;
  mAliveToken := Token;
  mAliveRef := TokenRef;
  mDone := ADone;
  // Im Hintergrund: Shutdown wartet auf diesen Thread, bevor der Aufrufer die Sitzung freigibt.
  RunInBackground(
    procedure
    var
      mArguments: TJSONValue;
      mAnswer: TJSONValue;
      mAnswerJson, mError: string;
    begin
      mAnswerJson := '';
      mError := '';
      try
        mArguments := TJSONObject.ParseJSONValue(mArgumentsJson);
        if not (mArguments is TJSONArray) then
        begin
          mArguments.Free;
          mArguments := TJSONArray.Create;
        end;
        // ExecuteCommand übernimmt die Argumente.
        mAnswer := mSession.ExecuteCommand(mCommand, TJSONArray(mArguments), mTimeoutMs);
        try
          if mAnswer <> nil then
          begin
            mAnswerJson := mAnswer.ToJSON;
          end;
        finally
          mAnswer.Free;
        end;
      except
        // Nur die Klasse: Die Meldung könnte Quelltext oder Pfade enthalten.
        on E: Exception do
        begin
          mError := E.ClassName;
        end;
      end;
      TDpccMainThread.Queue(TDpccFeature.Completion,
        procedure
        begin
          if mAliveToken.Alive and (mAliveRef <> nil) and Assigned(mDone) then
          begin
            mDone(mAnswerJson, mError);
          end;
        end);
    end);
  Result := True;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Completion.Providers.Server', cTexts[TDpccLanguage.German], cTexts[TDpccLanguage.English]);

end.