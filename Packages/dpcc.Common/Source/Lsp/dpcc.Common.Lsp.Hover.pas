unit dpcc.Common.Lsp.Hover;

// Hover (textDocument/hover): Deklaration und XML-Dokumentation (///) des
// Symbols unter dem Cursor als Markdown.
//
// Den Inhalt sammelt TLspHoverLookup (dpcc.Common.Lsp.Hover.Lookup), die
// Darstellungen liefert THoverInfo (dpcc.Common.Lsp.Hover.Info): als Markdown
// in contents, als Klartext für Clients ohne Markdown und strukturiert mit den
// Fundorten der cref-Verweise in dpcc.documentation.
//
// Clients ohne Markdown (RAD Studio meldet hover.contentFormat ["plaintext"])
// bekommen denselben Inhalt als Klartext (#175).
//
// Für den dpcc-Tooltip (#588) kommen Art, Herkunft, Fundort, Typverweise in der
// Deklaration und die Vererbungskette dazu (dpcc.Common.Lsp.HoverTypes). Ist die
// Datei nicht geöffnet, liest der Hover sie selbst: So fragt das Plugin einen
// angeklickten Typ über seinen Fundort ab.
//
// Rückbau R3 (Frage 17): keine Begründungen (Rationale), keine Hinweise zu
// Feld- und Parameternamen von Datenmengen (DataSet/SQL), kein „neu zugewiesen“,
// keine Doku-Links (DocWiki, Microsoft). Der Hover zeigt Signatur, Unit und XMLDoc.
//
// Über einem Unit-Namen (#1921) kommt der Inhalt der Unit dazu, ausgewählt nach
// hints.unitContents (dpcc.Common.Lsp.Hover.UnitContents).

interface

uses
  System.JSON,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.Contract,
  dpcc.Common.Pascal.SyntaxTree,
  dpcc.Common.Pascal.TreeCache,
  dpcc.Common.Index.Contract,
  dpcc.Common.Semantics.NameResolver,
  dpcc.Common.Lsp.Documentation,
  dpcc.Common.Lsp.ConditionalSymbols,
  dpcc.Common.Lsp.Hover.Info;

type
  /// <summary>Liefert den Text einer Datei; False, wenn sie nicht lesbar ist.</summary>
  THoverReadText = TDocReadText;
  /// <summary>Delphi-Version des Dokuments AUri (z. B. "23.0"); '' = unbekannt.</summary>
  THoverVersionProvider = reference to function(const AUri: string): string;
  /// <summary>Inhalt eines Hovers, siehe dpcc.Common.Lsp.Hover.Info.</summary>
  THoverInfo = dpcc.Common.Lsp.Hover.Info.THoverInfo;
  /// <summary>Namensauflösung, Index und Lesen anderer Dateien für InfoAt.</summary>
  THoverSource = dpcc.Common.Lsp.Hover.Info.THoverSource;

  TLspHover = class
  public const
    cMethod = 'textDocument/hover';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: THoverReadText;
    FNamespaces: TArray<string>;
    FVersionProvider: THoverVersionProvider;
    FHintsFor: TDocHintsProvider;
    FSymbolsFor: TConditionalContextFunc;
    FMarkdown: Boolean;
    function HandleHover(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function OpenTree(const AUri: string; const ACancellation: IPascalCancellation; out AText: string;
      out AShared: ISharedSyntaxTree; out AOwnTree: TSyntaxTree): TSyntaxTree;
    function AnswerAt(const AUri, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function DirectiveHover(const AUri, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ADelphiVersion: string; out AMarkdown: string): Boolean;
    function SymbolInfo(const AUri, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ADelphiVersion: string): THoverInfo;
    procedure ApplySettings(const AUri: string; var AInfo: THoverInfo);
    function InfoAnswer(const AUri: string; const AInfo: THoverInfo): TJSONObject;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt: Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: THoverReadText;
      const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
      const AReadText: THoverReadText); overload;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Hover-Inhalt an APosition; ATreeText ist der Text von ATree.</summary>
    class function InfoAt(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText, AFileName: string;
      const APosition: TTextPosition; const ADelphiVersion: string): THoverInfo; overload; static;
    /// <summary>Wie oben mit ADelphiVersion = ''.</summary>
    class function InfoAt(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText, AFileName: string;
      const APosition: TTextPosition): THoverInfo; overload; static;
    /// <summary>False, wenn der Client in initialize nur Klartext für Hover meldet.</summary>
    class function ClientSupportsMarkdown(const AInitializeParams: TJSONObject): Boolean; static;
    /// <summary>Teile des Hovers für den dpcc-Tooltip (#442): Doku strukturiert in documentation (#654) und
    /// als Klartext in documentationText, Hinweis als Klartext.</summary>
    class function DpccJson(const AInfo: THoverInfo): TJSONObject; static;
    /// <summary>Antwort als Markdown (Vorgabe) oder als Klartext.</summary>
    property Markdown: Boolean read FMarkdown write FMarkdown;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Delphi-Version für Direktiven und Schlüsselwörter; ohne Provider gilt die neueste Version.</summary>
    property VersionProvider: THoverVersionProvider read FVersionProvider write FVersionProvider;
    /// <summary>Anzeige von XMLDoc (#654) als dpcc.xmlDoc; ohne Provider fehlt das Feld.</summary>
    property HintsFor: TDocHintsProvider read FHintsFor write FHintsFor;
    /// <summary>Symbole des Dokuments und Schalter directives.hover (#102); ohne Provider an, ohne Projekt.
    /// </summary>
    property SymbolsFor: TConditionalContextFunc read FSymbolsFor write FSymbolsFor;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Diagnostics,
  dpcc.Common.Lsp.Internals.Namespaces,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Lsp.Positions,
  dpcc.Common.Lsp.CompilerDirectives,
  dpcc.Common.Lsp.KeywordReference,
  dpcc.Common.Lsp.Hover.Lookup,
  dpcc.Common.Diagnostics.RequestScope,
  dpcc.Common.Lsp.Internals.Cancellation,
  dpcc.Common.Lsp.Hover.UnitContents,
  dpcc.Common.Configuration.Contract,
  dpcc.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  THoverText = (FieldsTextDocumentUriAndPosition);

const
  cTexts: array[THoverText] of TDpccText = (
    (De: 'Felder "textDocument.uri" und "position" fehlen in ';
     En: 'Fields "textDocument.uri" and "position" missing in '));

{$SCOPEDENUMS OFF}

const
  cSectionBreak = #10#10'---'#10#10;

/// <summary>Antwort mit AMarkdown als Inhalt.</summary>
function MarkdownAnswer(const AMarkdown: string): TJSONObject;
var
  mContents: TJSONObject;
begin
  mContents := TJSONObject.Create;
  mContents.AddPair('kind', 'markdown');
  mContents.AddPair('value', AMarkdown);
  Result := TJSONObject.Create;
  Result.AddPair('contents', mContents);
end;

/// <summary>Bedingtes Symbol an APosition und Wert der Bedingung mit Teilwerten (#847), Bedingung zuerst.</summary>
function SymbolHover(const AText: string; const APosition: TTextPosition; const ASymbols: TConditionalContext;
  out AMarkdown: string): Boolean;
var
  mCondition: string;
begin
  Result := TConditionalSymbols.Hover(AText, APosition, ASymbols, AMarkdown);
  if TConditionalSymbols.ConditionHover(AText, APosition, ASymbols, mCondition) then
  begin
    if Result then
    begin
      AMarkdown := mCondition + cSectionBreak + AMarkdown;
    end
    else
    begin
      AMarkdown := mCondition;
    end;
    Result := True;
  end;
end;

/// <summary>Werte von textDocument.uri und position; Fehler der Anfrage, wenn eins fehlt.</summary>
procedure ReadParams(const AParams: TJSONValue; out AUri: string; out APosition: TTextPosition);
var
  mPosition: TJSONValue;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', AUri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', mPosition)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[THoverText.FieldsTextDocumentUriAndPosition].Text + TLspHover.cMethod);
  end;
  APosition := TLspPositions.ReadPosition(mPosition);
end;

{ TLspHover }

function TLspHover.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspHover.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspHover.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText);
begin
  Create(AStore, AIndex, AReadText, nil);
end;

constructor TLspHover.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: THoverReadText; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FEnsureUnit := AEnsureUnit;
  FMarkdown := True;
end;

procedure TLspHover.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(cMethod, HandleHover);
end;

class function TLspHover.ClientSupportsMarkdown(const AInitializeParams: TJSONObject): Boolean;
var
  mFormats: TJSONArray;
  mItem: TJSONValue;
begin
  // Ohne Angabe bleibt es bei Markdown, wie bisher.
  if (AInitializeParams = nil) or
    not AInitializeParams.TryGetValue<TJSONArray>('capabilities.textDocument.hover.contentFormat', mFormats) or
    (mFormats.Count = 0) then
  begin
    Exit(True);
  end;
  for mItem in mFormats do
  begin
    if SameText(mItem.Value, 'markdown') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TLspHover.InfoAt(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText,
  AFileName: string; const APosition: TTextPosition): THoverInfo;
begin
  Result := InfoAt(ASource, ATree, ATreeText, AFileName, APosition, '');
end;

class function TLspHover.InfoAt(const ASource: THoverSource; ATree: TSyntaxTree; const ATreeText,
  AFileName: string; const APosition: TTextPosition; const ADelphiVersion: string): THoverInfo;
begin
  Result := TLspHoverLookup.InfoAt(ASource, ATree, ATreeText, AFileName, APosition, ADelphiVersion);
end;

class function TLspHover.DpccJson(const AInfo: THoverInfo): TJSONObject;
begin
  Result := AInfo.ToDpccJson;
end;

function TLspHover.OpenTree(const AUri: string; const ACancellation: IPascalCancellation; out AText: string;
  out AShared: ISharedSyntaxTree; out AOwnTree: TSyntaxTree): TSyntaxTree;
var
  mDocument: ITextDocument;
  mWatch: TStopwatch;
begin
  Result := nil;
  AShared := nil;
  AOwnTree := nil;
  if FStore.TryGet(AUri, mDocument) then
  begin
    AText := mDocument.Text;
    // Wartet, wenn ein anderer Thread dieselbe Version gerade parst (#647).
    mWatch := TStopwatch.StartNew;
    AShared := TSyntaxTreeCache.Get(mDocument, ACancellation);
    TRequestDiagnostics.Note('treeMs', Integer(mWatch.ElapsedMilliseconds));
    // Der Baum lebt, solange der Aufrufer AShared hält.
    Result := AShared.Tree;
  end
  // Nicht geöffnete Datei (Typ aus dem dpcc-Tooltip angeklickt, #588): selbst lesen.
  else if Assigned(FReadText) and FReadText(TDocumentUris.ToPath(AUri), AText) then
  begin
    AOwnTree := TSyntaxTreeCache.Parse(AText, ACancellation);
    Result := AOwnTree;
  end;
end;

function TLspHover.DirectiveHover(const AUri, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ADelphiVersion: string; out AMarkdown: string): Boolean;
var
  mSymbols: TConditionalContext;
  mSymbol: string;
  mHasDirective: Boolean;
begin
  // Compiler-Direktiven wie {$R+} oder {$WARN …} und bedingte Symbole mit Zustand und Herkunft (#102).
  AMarkdown := '';
  mSymbols := TConditionalContext.Default;
  if Assigned(FSymbolsFor) then
  begin
    mSymbols := FSymbolsFor(AUri);
  end;
  Result := False;
  if not mSymbols.HoverEnabled then
  begin
    Exit;
  end;
  Result := SymbolHover(AText, APosition, mSymbols, mSymbol);
  mHasDirective := TCompilerDirectives.HoverAt(ATree, APosition, ADelphiVersion, AMarkdown);
  if Result and mHasDirective then
  begin
    AMarkdown := mSymbol + cSectionBreak + AMarkdown;
  end
  else if Result then
  begin
    AMarkdown := mSymbol;
  end;
  Result := Result or mHasDirective;
end;

procedure TLspHover.ApplySettings(const AUri: string; var AInfo: THoverInfo);
var
  mHints: THintSettings;
begin
  mHints := THintSettings.Default;
  if Assigned(FHintsFor) then
  begin
    mHints := FHintsFor(AUri);
  end;
  // published-Mitglieder abschaltbar (hints.publishedMembers, #110).
  if not mHints.PublishedMembers then
  begin
    AInfo.Members := '';
    AInfo.PublishedItems := nil;
    AInfo.DefaultProperty := '';
  end;
  // Inhalt der Unit nach hints.unitContents (#1921).
  AInfo.UnitContents := TLspHoverUnitContents.Select(AInfo.UnitContents.Entries,
    TLspHoverUnitContents.ModeOf(mHints.UnitContents));
end;

function TLspHover.SymbolInfo(const AUri, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ADelphiVersion: string): THoverInfo;
var
  mResolver: TNameResolver;
begin
  mResolver := TNameResolver.Create(FIndex, FEnsureUnit);
  try
    mResolver.Namespaces := Namespaces;
    Result := InfoAt(THoverSource.Create(mResolver, FIndex, FReadText), ATree, AText, TDocumentUris.ToPath(AUri),
      APosition, ADelphiVersion);
  finally
    mResolver.Free;
  end;
  ApplySettings(AUri, Result);
end;

function TLspHover.InfoAnswer(const AUri: string; const AInfo: THoverInfo): TJSONObject;
var
  mDpcc: TJSONObject;
begin
  if FMarkdown then
  begin
    Result := MarkdownAnswer(AInfo.ToMarkdown);
  end
  else
  begin
    // Klartext als einfacher String und ohne "range", genau wie DelphiLSP
    // antwortet. RAD Studio zeigt den Hover benutzerdefinierter Server trotzdem
    // nicht als Tooltip an; dafür braucht es ein IDE-Plugin (#175).
    Result := TJSONObject.Create;
    Result.AddPair('contents', AInfo.ToPlainText);
  end;
  // Für den dpcc-Tooltip (#442, #588) die Teile einzeln; andere Clients ignorieren das Feld.
  mDpcc := AInfo.ToDpccJson;
  if Assigned(FHintsFor) then
  begin
    mDpcc.AddPair('xmlDoc', TLspDocumentation.HintsJson(FHintsFor(AUri)));
  end;
  Result.AddPair('dpcc', mDpcc);
end;

function TLspHover.AnswerAt(const AUri, AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mDelphiVersion, mMarkdown: string;
  mInfo: THoverInfo;
begin
  TRequestDiagnostics.Note('syntaxErr', Length(ATree.Diagnostics));
  mDelphiVersion := '';
  if Assigned(FVersionProvider) then
  begin
    mDelphiVersion := FVersionProvider(AUri);
  end;
  ACancellation.ThrowIfCancellationRequested;
  // Direktiven und bedingte Symbole.
  if DirectiveHover(AUri, AText, ATree, APosition, mDelphiVersion, mMarkdown) then
  begin
    Exit(MarkdownAnswer(mMarkdown));
  end;
  mInfo := SymbolInfo(AUri, AText, ATree, APosition, mDelphiVersion);
  if mInfo.Found then
  begin
    Result := InfoAnswer(AUri, mInfo);
  end
  // Seltene Schlüsselwörter und Direktiven (#187), wenn kein Symbol so heißt.
  else if TKeywordReference.HoverAt(AText, APosition, mDelphiVersion, mMarkdown) then
  begin
    Result := MarkdownAnswer(mMarkdown);
  end
  else
  begin
    TRequestDiagnostics.DefaultReason('noSymbol');
    Result := TJSONNull.Create;
  end;
end;

function TLspHover.HandleHover(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  mCancellation: IPascalCancellation;
  mUri, mText: string;
  mPosition: TTextPosition;
  mTree, mOwnTree: TSyntaxTree;
  mShared: ISharedSyntaxTree;
begin
  ReadParams(AParams, mUri, mPosition);
  // Erst in einer Variablen halten: Bei Übergabe als const würde das Objekt nie freigegeben.
  mCancellation := TRequestCancellation.Create(ACancellation);
  mTree := OpenTree(mUri, mCancellation, mText, mShared, mOwnTree);
  if mTree = nil then
  begin
    TRequestDiagnostics.Reason('documentNotOpen');
    Exit(TJSONNull.Create);
  end;
  try
    Result := AnswerAt(mUri, mText, mTree, mPosition, ACancellation);
  finally
    mOwnTree.Free;
  end;
end;

initialization
  TDpccTextTables.Add('dpcc.Common.Lsp.Hover', cTexts);

end.
