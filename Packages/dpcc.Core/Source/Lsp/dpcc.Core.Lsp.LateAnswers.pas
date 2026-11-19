unit dpcc.Core.Lsp.LateAnswers;

// Antworten des Servers, auf die der Hauptthread nur kurz wartet (Strg+Klick und „Deklaration suchen“, Symbolhinweis
// der IDE), ohne IDE und ohne VCL. Die Anfrage läuft von Anfang an im Hintergrund; der Hauptthread wartet höchstens
// cWaitMs. Kommt die Antwort später, wird sie nachgereicht statt verworfen:
//   - IDpccAnswerSlot: Übergabe zwischen Hintergrund-Thread und Hauptthread. Await wartet höchstens die angegebene
//     Zeit (abbrechbar über TDpccShutdown); danach gilt die Antwort als nachgereicht, und Complete meldet dem Thread
//     False: Er reicht das Ergebnis über TDpccMainThread.Queue nach. Referenzgezählt: Der Thread hält nur den Slot,
//     nie den Manager.
//   - TDpccLateGoto: Passt ein nachgereichtes Sprungziel noch? Nur mit Ziel, ohne neueren Sprungwunsch (Generation),
//     höchstens cMaxAgeMs nach der Anfrage, in derselben Datei und mit dem Cursor an der Ausgangsstelle (oder an der
//     Stelle der Anfrage, falls die IDE ihn bei Strg+Klick dorthin setzt). Sonst still verwerfen.
//   - TDpccHintCache: Symbolhinweise für wenige Sekunden (nachgereicht oder rechtzeitig), damit der nächste Aufruf der
//     IDE für dasselbe Wort im selben Textstand sofort antwortet. Ein geänderter Text (anderer Hash) macht die
//     Einträge der Datei ungültig. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.SyncObjs;

type
  /// <summary>Zeiten für kurz erwartete Antworten.</summary>
  TDpccLateAnswers = record
  public const
    /// <summary>So lange wartet der Hauptthread höchstens auf eine Antwort (Strg+Klick, Symbolhinweis der IDE).
    /// </summary>
    cWaitMs = 250;
    /// <summary>Zeitlimit der Anfrage im Hintergrund und Obergrenze für ein nachgereichtes Sprungziel.</summary>
    cMaxAgeMs = 3000;
    /// <summary>So lange gilt ein gemerkter Symbolhinweis.</summary>
    cHintLifetimeMs = 5000;
    /// <summary>Höchstens so viele gemerkte Symbolhinweise.</summary>
    cHintEntries = 8;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Fehler einer Anfrage im Hintergrund.</summary>
  TDpccAnswerError = (
    /// <summary>Kein Fehler.</summary>
    None,
    /// <summary>Der Server bietet die Methode nicht an (ELspMethodNotFound).</summary>
    MethodNotFound,
    /// <summary>Zeitlimit oder beendeter Server (ELspClientError): erwartbar.</summary>
    ClientError,
    /// <summary>Unerwarteter Fehler.</summary>
    Other);

  /// <summary>Urteil über ein nachgereichtes Sprungziel.</summary>
  TDpccGotoVerdict = (
    /// <summary>Passt noch: springen.</summary>
    Jump,
    /// <summary>Der Server kennt kein Ziel (oder Fehler).</summary>
    NoTarget,
    /// <summary>Inzwischen gab es einen neueren Sprungwunsch.</summary>
    Superseded,
    /// <summary>Älter als die Obergrenze.</summary>
    TooOld,
    /// <summary>Eine andere Datei ist aktiv.</summary>
    OtherFile,
    /// <summary>Der Cursor steht nicht mehr an der Ausgangsstelle.</summary>
    CursorMoved);
{$SCOPEDENUMS OFF}

  /// <summary>Ergebnis einer Anfrage im Hintergrund: Sprungziel (Datei, Zeile und Zeichen 0-basiert) oder Text.
  /// </summary>
  TDpccAnswer = record
    Found: Boolean;
    FileName: string;
    Line: Integer;
    Character: Integer;
    Text: string;
    Error: TDpccAnswerError;
    /// <summary>„Klasse: Meldung“ des Fehlers; '' ohne.</summary>
    ErrorText: string;
  end;

  /// <summary>Übergabe einer Antwort vom Hintergrund-Thread an den Hauptthread. Threadsicher.</summary>
  IDpccAnswerSlot = interface
    ['{5B0C2F57-3B8E-4D0F-9A55-7E1C4C2D9A61}']
    /// <summary>Hintergrund-Thread: Antwort abgeben. True, solange der Hauptthread noch nicht aufgegeben hat (er
    /// holt sie selbst ab); False: Er hat aufgegeben, der Thread reicht die Antwort nach.</summary>
    function Complete(const AAnswer: TDpccAnswer): Boolean;
    /// <summary>Hauptthread: höchstens AMs auf die Antwort warten (0 = nur nachsehen); vorzeitig beim Abbruchsignal.
    /// True: Antwort da (Answer). False: Sie kommt später und wird nachgereicht.</summary>
    function Await(AMs: Cardinal): Boolean;
    /// <summary>Antwort abgegeben?</summary>
    function Done: Boolean;
    function Answer: TDpccAnswer;
    /// <summary>Beginn der Anfrage (TThread.GetTickCount64 des Aufrufers).</summary>
    function StartedMs: UInt64;
  end;

  TDpccAnswerSlot = class(TInterfacedObject, IDpccAnswerSlot)
  private
    FLock: TCriticalSection;
    FReady: TEvent;
    FAnswer: TDpccAnswer;
    FDone: Boolean;
    FDeferred: Boolean;
    FStartedMs: UInt64;
  public
    constructor Create(AStartedMs: UInt64);
    destructor Destroy; override;
    function Complete(const AAnswer: TDpccAnswer): Boolean;
    function Await(AMs: Cardinal): Boolean;
    function Done: Boolean;
    function Answer: TDpccAnswer;
    function StartedMs: UInt64;
  end;

  /// <summary>Sprungwunsch, wie er beim Fragen war: Zeilen 1-basiert wie im Editor, Zeichen 0-basiert.</summary>
  TDpccGotoOrigin = record
    /// <summary>Laufende Nummer des Sprungwunschs; ein neuerer macht ältere Antworten ungültig.</summary>
    Generation: Cardinal;
    FileName: string;
    /// <summary>Cursor beim Fragen.</summary>
    CaretLine: Integer;
    CaretCharacter: Integer;
    /// <summary>Stelle der Anfrage (Maus bei Strg+Klick, sonst Cursor).</summary>
    AtLine: Integer;
    AtCharacter: Integer;
    /// <summary>Beginn der Anfrage (TThread.GetTickCount64).</summary>
    StartedMs: UInt64;
  end;

  /// <summary>Zustand beim Eintreffen der nachgereichten Antwort; CaretLine &lt; 1 ohne Editoransicht.</summary>
  TDpccGotoNow = record
    Generation: Cardinal;
    FileName: string;
    CaretLine: Integer;
    CaretCharacter: Integer;
    NowMs: UInt64;
  end;

  /// <summary>Regeln für ein nachgereichtes Sprungziel.</summary>
  TDpccLateGoto = record
  public
    /// <summary>Passt das Ziel (AFound) noch zum Zustand ANow? Reihenfolge der Prüfung: Ziel, Generation, Alter
    /// (höchstens AMaxAgeMs), Datei (ohne Groß-/Kleinschreibung), Cursor (an der Ausgangsstelle oder an der Stelle der
    /// Anfrage).</summary>
    class function Verdict(const AOrigin: TDpccGotoOrigin; const ANow: TDpccGotoNow; AFound: Boolean;
      AMaxAgeMs: Cardinal): TDpccGotoVerdict; static;
    /// <summary>Kurzer Text fürs Diagnoseprotokoll.</summary>
    class function VerdictText(AVerdict: TDpccGotoVerdict): string; static;
  end;

  /// <summary>Schlüssel eines Symbolhinweises: Datei, Zeile (0-basiert), Beginn des Worts (0-basiert) und Hash des
  /// ganzen Texts (Dokumentstand).</summary>
  TDpccHintKey = record
    FileName: string;
    Line: Integer;
    WordStart: Integer;
    TextHash: Integer;
    /// <summary>Schlüssel für Zeichen ACharacter in ALineText (Zeile ALine von AFileName). Steht ACharacter in einem
    /// Bezeichner, zählt dessen Beginn: jede Stelle im selben Wort ergibt denselben Schlüssel.</summary>
    class function Make(const AFileName, ALineText: string; ALine, ACharacter, ATextHash: Integer): TDpccHintKey;
      static;
    /// <summary>Hash des Texts für TextHash.</summary>
    class function HashOf(const AText: string): Integer; static;
    function SameAs(const AOther: TDpccHintKey): Boolean;
  end;

  /// <summary>Gemerkte Symbolhinweise; nur im Hauptthread.</summary>
  IDpccHintCache = interface
    ['{C7E4B0D2-8F31-4A6B-9C2E-1D5F7A3B6E80}']
    /// <summary>AText (auch '') für AKey merken; ersetzt einen gleichen Schlüssel und verdrängt den ältesten Eintrag.
    /// </summary>
    procedure Store(const AKey: TDpccHintKey; const AText: string; ANowMs: UInt64);
    /// <summary>Gemerkter Text für AKey, solange nicht verfallen; Einträge derselben Datei mit anderem Textstand
    /// fallen dabei weg.</summary>
    function Lookup(const AKey: TDpccHintKey; ANowMs: UInt64; out AText: string): Boolean;
    function Count: Integer;
    procedure Clear;
  end;

  TDpccHintCache = class(TInterfacedObject, IDpccHintCache)
  private type
    TEntry = record
      Key: TDpccHintKey;
      Text: string;
      StoredMs: UInt64;
    end;
  private
    FEntries: TArray<TEntry>;
    FMaxEntries: Integer;
    FLifetimeMs: Cardinal;
    /// <summary>Verfallene Einträge und solche derselben Datei mit anderem Textstand als AKey entfernen.</summary>
    procedure Prune(const AKey: TDpccHintKey; ANowMs: UInt64);
    procedure Remove(AIndex: Integer);
  public
    /// <summary>Mit cHintEntries und cHintLifetimeMs.</summary>
    constructor Create; overload;
    constructor Create(AMaxEntries: Integer; ALifetimeMs: Cardinal); overload;
    procedure Store(const AKey: TDpccHintKey; const AText: string; ANowMs: UInt64);
    function Lookup(const AKey: TDpccHintKey; ANowMs: UInt64; out AText: string): Boolean;
    function Count: Integer;
    procedure Clear;
  end;

implementation

uses
  System.Hash,
  dpcc.Core.Diagnostics.Shutdown;

function IsNameChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

{ TDpccAnswerSlot }

constructor TDpccAnswerSlot.Create(AStartedMs: UInt64);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FReady := TEvent.Create(nil, True, False, '');
  FStartedMs := AStartedMs;
  FAnswer := Default(TDpccAnswer);
end;

destructor TDpccAnswerSlot.Destroy;
begin
  FReady.Free;
  FLock.Free;
  inherited;
end;

function TDpccAnswerSlot.Complete(const AAnswer: TDpccAnswer): Boolean;
begin
  FLock.Enter;
  try
    FAnswer := AAnswer;
    FDone := True;
    Result := not FDeferred;
  finally
    FLock.Leave;
  end;
  FReady.SetEvent;
end;

function TDpccAnswerSlot.Await(AMs: Cardinal): Boolean;
begin
  if (AMs > 0) and not Done then
  begin
    // Abbrechbar: Beim Entladen kehrt das Warten sofort zurück.
    TDpccShutdown.WaitFor(FReady, AMs);
  end;
  FLock.Enter;
  try
    Result := FDone;
    if not Result then
    begin
      // Ab jetzt reicht der Thread die Antwort nach.
      FDeferred := True;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDpccAnswerSlot.Done: Boolean;
begin
  FLock.Enter;
  try
    Result := FDone;
  finally
    FLock.Leave;
  end;
end;

function TDpccAnswerSlot.Answer: TDpccAnswer;
begin
  FLock.Enter;
  try
    Result := FAnswer;
  finally
    FLock.Leave;
  end;
end;

function TDpccAnswerSlot.StartedMs: UInt64;
begin
  Result := FStartedMs;
end;

{ TDpccLateGoto }

class function TDpccLateGoto.Verdict(const AOrigin: TDpccGotoOrigin; const ANow: TDpccGotoNow; AFound: Boolean;
  AMaxAgeMs: Cardinal): TDpccGotoVerdict;
var
  mAge: UInt64;
  mAtOrigin, mAtRequest: Boolean;
begin
  if not AFound then
  begin
    Exit(TDpccGotoVerdict.NoTarget);
  end;
  if ANow.Generation <> AOrigin.Generation then
  begin
    Exit(TDpccGotoVerdict.Superseded);
  end;
  mAge := 0;
  if ANow.NowMs > AOrigin.StartedMs then
  begin
    mAge := ANow.NowMs - AOrigin.StartedMs;
  end;
  if mAge > AMaxAgeMs then
  begin
    Exit(TDpccGotoVerdict.TooOld);
  end;
  if (ANow.FileName = '') or not SameText(ANow.FileName, AOrigin.FileName) then
  begin
    Exit(TDpccGotoVerdict.OtherFile);
  end;
  mAtOrigin := (ANow.CaretLine = AOrigin.CaretLine) and (ANow.CaretCharacter = AOrigin.CaretCharacter);
  // Setzt die IDE den Cursor bei Strg+Klick erst nach der Antwort auf die Klickstelle, steht er dort.
  mAtRequest := (ANow.CaretLine = AOrigin.AtLine) and (ANow.CaretCharacter = AOrigin.AtCharacter);
  if (ANow.CaretLine < 1) or not (mAtOrigin or mAtRequest) then
  begin
    Exit(TDpccGotoVerdict.CursorMoved);
  end;
  Result := TDpccGotoVerdict.Jump;
end;

class function TDpccLateGoto.VerdictText(AVerdict: TDpccGotoVerdict): string;
begin
  case AVerdict of
    TDpccGotoVerdict.Jump:
      Result := 'springt';
    TDpccGotoVerdict.NoTarget:
      Result := 'kein Ziel';
    TDpccGotoVerdict.Superseded:
      Result := 'neuerer Sprungwunsch';
    TDpccGotoVerdict.TooOld:
      Result := 'zu spät';
    TDpccGotoVerdict.OtherFile:
      Result := 'andere Datei aktiv';
    TDpccGotoVerdict.CursorMoved:
      Result := 'Cursor bewegt';
  else
    Result := '';
  end;
end;

{ TDpccHintKey }

class function TDpccHintKey.Make(const AFileName, ALineText: string; ALine, ACharacter,
  ATextHash: Integer): TDpccHintKey;
var
  mStart: Integer;
begin
  Result := Default(TDpccHintKey);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.TextHash := ATextHash;
  mStart := ACharacter;
  // Nur im Bezeichner zum Wortanfang: ALineText[mStart] ist das Zeichen vor der Stelle mStart (0-basiert).
  if (mStart >= 0) and (mStart < Length(ALineText)) and IsNameChar(ALineText[mStart + 1]) then
  begin
    while (mStart > 0) and IsNameChar(ALineText[mStart]) do
    begin
      Dec(mStart);
    end;
  end;
  Result.WordStart := mStart;
end;

class function TDpccHintKey.HashOf(const AText: string): Integer;
begin
  Result := THashBobJenkins.GetHashValue(AText);
end;

function TDpccHintKey.SameAs(const AOther: TDpccHintKey): Boolean;
begin
  Result := SameText(FileName, AOther.FileName) and (Line = AOther.Line) and (WordStart = AOther.WordStart) and
    (TextHash = AOther.TextHash);
end;

{ TDpccHintCache }

constructor TDpccHintCache.Create;
begin
  Create(TDpccLateAnswers.cHintEntries, TDpccLateAnswers.cHintLifetimeMs);
end;

constructor TDpccHintCache.Create(AMaxEntries: Integer; ALifetimeMs: Cardinal);
begin
  inherited Create;
  FMaxEntries := AMaxEntries;
  if FMaxEntries < 1 then
  begin
    FMaxEntries := 1;
  end;
  FLifetimeMs := ALifetimeMs;
end;

procedure TDpccHintCache.Remove(AIndex: Integer);
begin
  System.Delete(FEntries, AIndex, 1);
end;

procedure TDpccHintCache.Prune(const AKey: TDpccHintKey; ANowMs: UInt64);
var
  mIndex: Integer;
  mExpired, mChanged: Boolean;
begin
  for mIndex := High(FEntries) downto 0 do
  begin
    mExpired := (ANowMs < FEntries[mIndex].StoredMs) or (ANowMs - FEntries[mIndex].StoredMs > FLifetimeMs);
    // Dieselbe Datei mit anderem Textstand: Das Dokument hat sich geändert.
    mChanged := SameText(FEntries[mIndex].Key.FileName, AKey.FileName) and
      (FEntries[mIndex].Key.TextHash <> AKey.TextHash);
    if mExpired or mChanged then
    begin
      Remove(mIndex);
    end;
  end;
end;

procedure TDpccHintCache.Store(const AKey: TDpccHintKey; const AText: string; ANowMs: UInt64);
var
  mIndex: Integer;
  mEntry: TEntry;
begin
  Prune(AKey, ANowMs);
  for mIndex := High(FEntries) downto 0 do
  begin
    if FEntries[mIndex].Key.SameAs(AKey) then
    begin
      Remove(mIndex);
    end;
  end;
  // Die Einträge stehen in der Reihenfolge des Merkens: vorne der älteste.
  while Length(FEntries) >= FMaxEntries do
  begin
    Remove(0);
  end;
  mEntry.Key := AKey;
  mEntry.Text := AText;
  mEntry.StoredMs := ANowMs;
  FEntries := FEntries + [mEntry];
end;

function TDpccHintCache.Lookup(const AKey: TDpccHintKey; ANowMs: UInt64; out AText: string): Boolean;
var
  mIndex: Integer;
begin
  AText := '';
  Prune(AKey, ANowMs);
  for mIndex := 0 to High(FEntries) do
  begin
    if FEntries[mIndex].Key.SameAs(AKey) then
    begin
      AText := FEntries[mIndex].Text;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDpccHintCache.Count: Integer;
begin
  Result := Length(FEntries);
end;

procedure TDpccHintCache.Clear;
begin
  FEntries := nil;
end;

end.
