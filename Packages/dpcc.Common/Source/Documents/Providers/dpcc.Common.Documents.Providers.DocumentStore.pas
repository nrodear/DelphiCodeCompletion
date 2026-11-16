unit dpcc.Common.Documents.Providers.DocumentStore;

// Speicher der geöffneten Dokumente. Ändern ist für den Thread der
// Nachrichtenschleife gedacht, Lesen (TryGet, Documents) geht aus jedem Thread.
// Listener werden außerhalb der Sperre aufgerufen.
//
// Schlüssel ist TDocumentUris.Key: verschiedene Schreibweisen derselben Datei
// (c%3A/C:, Umlaute kodiert oder nicht, Groß-/Kleinschreibung) führen zum
// selben Dokument. Das Dokument behält die URI, mit der der Client es öffnete.
//
// Speicher (Speicher-Optimierung Phase 2, a1): Abgeleitete Daten (Syntaxbaum, Auszüge) kosten das 10- bis 30-Fache
// des Texts und blieben an jedem je geöffneten Dokument. Nur die cKeepDerived zuletzt benutzten Dokumente behalten
// sie; die übrigen ersetzt der Speicher nach dem Öffnen oder Ändern eines Dokuments durch eine gleiche
// Momentaufnahme (URI, Version, Text) ohne abgeleitete Daten. Wer die alte noch hält, nutzt sie weiter; der nächste
// Zugriff baut den Baum neu. Die URI-Schlüssel merkt sich der Speicher nur für geöffnete Dokumente (TryGet auf eine
// nie geöffnete Datei legte sonst je Datei einen Eintrag an).

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Documents.Uris;

type
  TDocumentStore = class(TInterfacedObject, IDocumentStore)
  public const
    /// <summary>So viele zuletzt benutzte Dokumente behalten ihre abgeleiteten Daten (a1).</summary>
    cKeepDerived = 16;
  private
    FLock: TCriticalSection;
    FDocuments: TDictionary<string, ITextDocument>;
    FListeners: TList<TDocumentListener>;
    FCanonicalize: TPathCanonicalizer;
    // URI → Schlüssel; spart den Plattenzugriff des Canonicalizers je Änderung. Nur für geöffnete Dokumente.
    FKeys: TDictionary<string, string>;
    // Schlüssel → letzte Benutzung (Zähler FClock); FBare: Momentaufnahme ohne abgeleitete Daten seit dem Kürzen.
    FUsed: TDictionary<string, Int64>;
    FBare: TDictionary<string, Boolean>;
    FClock: Int64;
    /// <summary>Schlüssel zu AUri; ARemember: für später merken (Open), sonst nur, wenn das Dokument offen ist.
    /// </summary>
    function KeyOf(const AUri: string; ARemember: Boolean = False): string;
    procedure Notify(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    function Take(const AUri: string; out ADocument: ITextDocument): Boolean;
    /// <summary>Unter FLock: AKey eben benutzt.</summary>
    procedure TouchLocked(const AKey: string);
    /// <summary>Ersetzt die länger nicht benutzten Dokumente jenseits von cKeepDerived durch Momentaufnahmen ohne
    /// abgeleitete Daten.</summary>
    procedure TrimDerived;
  public
    constructor Create; overload;
    /// <summary>Mit Auflösung von Symlinks und Junctions für die Schlüssel.</summary>
    constructor Create(const ACanonicalize: TPathCanonicalizer); overload;
    destructor Destroy; override;
    { IDocumentStore }
    function Open(const AUri, ALanguageId: string; AVersion: Integer; const AText: string): ITextDocument;
    function Change(const AUri: string; AVersion: Integer; const AChanges: TArray<TTextChange>): ITextDocument;
    procedure Save(const AUri: string);
    procedure Close(const AUri: string);
    function TryGet(const AUri: string; out ADocument: ITextDocument): Boolean;
    function Documents: TArray<ITextDocument>;
    procedure Subscribe(const AListener: TDocumentListener);
  end;

implementation

uses
  System.Generics.Defaults,
  dpcc.Common.Documents.TextDocument,
  dpcc.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TDocumentStoreText = (DocumentIsNotOpen);

const
  cTexts: array[TDocumentStoreText] of TDpccText = (
    (De: 'Dokument ist nicht geöffnet: %s'; En: 'Document is not open: %s'));

{$SCOPEDENUMS OFF}

{ TDocumentStore }

constructor TDocumentStore.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FDocuments := TDictionary<string, ITextDocument>.Create;
  FListeners := TList<TDocumentListener>.Create;
  FKeys := TDictionary<string, string>.Create;
  FUsed := TDictionary<string, Int64>.Create;
  FBare := TDictionary<string, Boolean>.Create;
end;

constructor TDocumentStore.Create(const ACanonicalize: TPathCanonicalizer);
begin
  Create;
  FCanonicalize := ACanonicalize;
end;

function TDocumentStore.KeyOf(const AUri: string; ARemember: Boolean): string;
var
  mFound: Boolean;
begin
  FLock.Enter;
  try
    mFound := FKeys.TryGetValue(AUri, Result);
  finally
    FLock.Leave;
  end;
  if mFound then
  begin
    Exit;
  end;
  Result := TDocumentUris.Key(AUri, FCanonicalize);
  FLock.Enter;
  try
    if ARemember or FDocuments.ContainsKey(Result) then
    begin
      FKeys.AddOrSetValue(AUri, Result);
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TDocumentStore.TouchLocked(const AKey: string);
begin
  Inc(FClock);
  FUsed.AddOrSetValue(AKey, FClock);
  FBare.Remove(AKey);
end;

procedure TDocumentStore.TrimDerived;
var
  mOrder: TArray<TPair<string, Int64>>;
  mIndex: Integer;
  mKey: string;
  mDocument: ITextDocument;
begin
  FLock.Enter;
  try
    if FDocuments.Count <= cKeepDerived then
    begin
      Exit;
    end;
    // Zuletzt benutzte zuerst; dahinter alles kürzen, was nicht schon gekürzt ist.
    mOrder := FUsed.ToArray;
    TArray.Sort<TPair<string, Int64>>(mOrder, TComparer<TPair<string, Int64>>.Construct(
      function(const ALeft, ARight: TPair<string, Int64>): Integer
      begin
        if ALeft.Value > ARight.Value then
        begin
          Result := -1;
        end
        else if ALeft.Value < ARight.Value then
        begin
          Result := 1;
        end
        else
        begin
          Result := 0;
        end;
      end));
    for mIndex := cKeepDerived to High(mOrder) do
    begin
      mKey := mOrder[mIndex].Key;
      if FBare.ContainsKey(mKey) or not FDocuments.TryGetValue(mKey, mDocument) then
      begin
        Continue;
      end;
      FDocuments[mKey] := TTextDocument.Create(mDocument.Uri, mDocument.LanguageId, mDocument.Version,
        mDocument.Text);
      FBare.AddOrSetValue(mKey, True);
    end;
  finally
    FLock.Leave;
  end;
end;

destructor TDocumentStore.Destroy;
begin
  FBare.Free;
  FUsed.Free;
  FKeys.Free;
  FListeners.Free;
  FDocuments.Free;
  FLock.Free;
  inherited;
end;

procedure TDocumentStore.Notify(AKind: TDocumentEventKind; const ADocument: ITextDocument);
var
  mListeners: TArray<TDocumentListener>;
  mListener: TDocumentListener;
begin
  FLock.Enter;
  try
    mListeners := FListeners.ToArray;
  finally
    FLock.Leave;
  end;
  for mListener in mListeners do
  begin
    mListener(AKind, ADocument);
  end;
end;

function TDocumentStore.Take(const AUri: string; out ADocument: ITextDocument): Boolean;
var
  mKey: string;
begin
  mKey := KeyOf(AUri);
  FLock.Enter;
  try
    Result := FDocuments.TryGetValue(mKey, ADocument);
    if Result then
    begin
      FDocuments.Remove(mKey);
      FKeys.Remove(AUri);
      FUsed.Remove(mKey);
      FBare.Remove(mKey);
    end;
  finally
    FLock.Leave;
  end;
end;

function TDocumentStore.Open(const AUri, ALanguageId: string; AVersion: Integer;
  const AText: string): ITextDocument;
var
  mKey: string;
begin
  mKey := KeyOf(AUri, True);
  Result := TTextDocument.Create(AUri, ALanguageId, AVersion, AText);
  FLock.Enter;
  try
    FDocuments.AddOrSetValue(mKey, Result);
    TouchLocked(mKey);
  finally
    FLock.Leave;
  end;
  TrimDerived;
  Notify(TDocumentEventKind.Opened, Result);
end;

function TDocumentStore.Change(const AUri: string; AVersion: Integer;
  const AChanges: TArray<TTextChange>): ITextDocument;
var
  mCurrent: ITextDocument;
  mKey: string;
begin
  if not TryGet(AUri, mCurrent) then
  begin
    raise EDocumentError.CreateFmt(cTexts[TDocumentStoreText.DocumentIsNotOpen].Text, [AUri]);
  end;
  mKey := KeyOf(AUri);
  Result := mCurrent.ApplyChanges(AChanges, AVersion);
  FLock.Enter;
  try
    FDocuments.AddOrSetValue(mKey, Result);
    TouchLocked(mKey);
  finally
    FLock.Leave;
  end;
  TrimDerived;
  Notify(TDocumentEventKind.Changed, Result);
end;

procedure TDocumentStore.Save(const AUri: string);
var
  mDocument: ITextDocument;
begin
  if TryGet(AUri, mDocument) then
  begin
    Notify(TDocumentEventKind.Saved, mDocument);
  end;
end;

procedure TDocumentStore.Close(const AUri: string);
var
  mDocument: ITextDocument;
begin
  if Take(AUri, mDocument) then
  begin
    Notify(TDocumentEventKind.Closed, mDocument);
  end;
end;

function TDocumentStore.TryGet(const AUri: string; out ADocument: ITextDocument): Boolean;
var
  mKey: string;
begin
  mKey := KeyOf(AUri);
  FLock.Enter;
  try
    Result := FDocuments.TryGetValue(mKey, ADocument);
    if Result then
    begin
      // Wer es holt, legt womöglich wieder abgeleitete Daten an.
      TouchLocked(mKey);
    end;
  finally
    FLock.Leave;
  end;
end;

function TDocumentStore.Documents: TArray<ITextDocument>;
begin
  FLock.Enter;
  try
    Result := FDocuments.Values.ToArray;
  finally
    FLock.Leave;
  end;
end;

procedure TDocumentStore.Subscribe(const AListener: TDocumentListener);
begin
  FLock.Enter;
  try
    FListeners.Add(AListener);
  finally
    FLock.Leave;
  end;
end;

initialization
  TDpccTextTables.Add('dpcc.Common.Documents.Providers.DocumentStore', cTexts);

end.
