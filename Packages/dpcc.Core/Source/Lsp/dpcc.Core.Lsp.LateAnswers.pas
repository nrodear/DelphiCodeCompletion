unit dpcc.Core.Lsp.LateAnswers;

// Antworten des Servers, auf die der Hauptthread nur kurz wartet (Strg+Klick und „Deklaration suchen“, Symbolhinweis
// der IDE), ohne IDE und ohne VCL. Die Anfrage läuft von Anfang an im Hintergrund; der Hauptthread wartet höchstens
// cWaitMs. Kommt die Antwort später, wird sie nachgereicht statt verworfen:
//   - IDpccAnswerSlot: Übergabe zwischen Hintergrund-Thread und Hauptthread. Await wartet höchstens die angegebene
//     Zeit (abbrechbar über TDpccShutdown); danach gilt die Antwort als nachgereicht, und Complete meldet dem Thread
//     False: Er reicht das Ergebnis über TDpccMainThread.Queue nach. Referenzgezählt: Der Thread hält nur den Slot,
//     nie den Manager.
//   - TDpccLateGoto: Passt ein nachgereichtes Sprungziel noch? Nur mit Ziel, ohne neueren Sprungwunsch (Generation),
//     höchstens cMaxAgeMs vom Klick bis zur Ankunft der Antwort im Hintergrund-Thread (nicht bis zur Zustellung im
//     Hauptthread), in derselben Datei und mit dem Cursor im selben Bezeichner wie die Klickstelle oder wie die
//     Ausgangsstelle des Cursors (nicht mehr exakt dieselbe Spalte: Ob die IDE den Cursor bei Strg+Klick vor oder nach
//     GotoDefinition auf die Klickstelle setzt, ist nicht geprüft). Sonst verwerfen; der Manager protokolliert den
//     Grund.
//   - TDpccNoTargets: Gründe des Servers für ein fehlendes Sprungziel (Benachrichtigung dpcc/noTarget, kommt auf
//     demselben Kanal vor der leeren Antwort). Der Lese-Thread legt sie ab (Sperre), GotoTargetAt holt sie nach einer
//     leeren Antwort zur selben Stelle (Datei, Zeile, Zeichen); nicht abgeholte verfallen nach cNoTargetLifetimeMs.
//     Ohne Benachrichtigung (älterer Server) bleibt der Grund Unknown.
//   - TDpccHintCache: Symbolhinweise für wenige Sekunden (nachgereicht oder rechtzeitig), damit der nächste Aufruf der
//     IDE für dasselbe Wort im selben Textstand sofort antwortet. Ein geänderter Text (anderer Hash) macht die
//     Einträge der Datei ungültig. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.JSON;

type
  /// <summary>Zeiten für kurz erwartete Antworten.</summary>
  TDpccLateAnswers = record
  public const
    /// <summary>So lange wartet der Hauptthread höchstens auf eine Antwort (Strg+Klick, Symbolhinweis der IDE).
    /// </summary>
    cWaitMs = 250;
    /// <summary>Zeitlimit der Sprunganfrage im Hintergrund und Obergrenze für ein nachgereichtes Sprungziel (vom Klick
    /// bis zur Ankunft der Antwort).</summary>
    cMaxAgeMs = 10000;
    /// <summary>Zeitlimit der Anfrage des Symbolhinweises im Hintergrund (bleibt kurz: ein später Hinweis nützt nur
    /// dem nächsten Aufruf der IDE).</summary>
    cHintTimeoutMs = 3000;
    /// <summary>So lange gilt ein gemerkter Symbolhinweis.</summary>
    cHintLifetimeMs = 5000;
    /// <summary>Höchstens so viele gemerkte Symbolhinweise.</summary>
    cHintEntries = 8;
    /// <summary>So lange hält die Sitzung einen Grund aus dpcc/noTarget, bis GotoTargetAt ihn abholt.</summary>
    cNoTargetLifetimeMs = 5000;
    /// <summary>Höchstens so viele abgelegte Gründe; der älteste fällt weg.</summary>
    cNoTargetEntries = 16;
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
    /// <summary>Der Cursor steht weder im Bezeichner der Klickstelle noch in dem der Ausgangsstelle.</summary>
    CursorMoved);

  /// <summary>Grund des Servers für ein fehlendes Sprungziel (dpcc/noTarget, Feld reason).</summary>
  TDpccNoTargetReason = (
    /// <summary>Keine Benachrichtigung (älterer Server oder sie fehlt).</summary>
    Unknown,
    /// <summary>"noDocument": Der Server kennt das Dokument nicht.</summary>
    NoDocument,
    /// <summary>"noIdentifier": An der Stelle steht kein Bezeichner.</summary>
    NoIdentifier,
    /// <summary>"unresolved": Name (Bezeichner) nicht aufgelöst.</summary>
    Unresolved,
    /// <summary>"unitNotFound": Name (Unit) nicht gefunden.</summary>
    UnitNotFound,
    /// <summary>"noSource": Name (Unit) nur als Package oder RTTI bekannt, ohne Quelltext.</summary>
    NoSource,
    /// <summary>"inactiveBranch": Stelle in einem nicht aktiven Zweig ({$IFDEF …}).</summary>
    InactiveBranch,
    /// <summary>"other" oder ein unbekannter Wert.</summary>
    Other);
{$SCOPEDENUMS OFF}

  /// <summary>Grund für ein fehlendes Sprungziel samt Name und Indexstand.</summary>
  TDpccNoTarget = record
    Reason: TDpccNoTargetReason;
    /// <summary>Bezeichner (Unresolved) bzw. Unit (UnitNotFound, NoSource); sonst meist ''.</summary>
    Name: string;
    /// <summary>Der Index wurde beim Antworten noch aufgebaut.</summary>
    Indexing: Boolean;
    /// <summary>Anfrage, zu der der Grund gehört (textDocument/declaration bzw. definition); '' unbekannt.</summary>
    Method: string;
    /// <summary>Grund zum Wert von reason; '' = Unknown, Unbekanntes = Other.</summary>
    class function ReasonOf(const ACode: string): TDpccNoTargetReason; static;
    /// <summary>Wert von reason zu AReason (fürs Protokoll); Unknown = "unknown".</summary>
    class function CodeOf(AReason: TDpccNoTargetReason): string; static;
    /// <summary>Der aussagekräftigere Grund (Kette declaration → definition): NoSource vor UnitNotFound vor
    /// Unresolved vor InactiveBranch vor NoIdentifier vor NoDocument vor Other vor Unknown; bei Gleichstand A.
    /// Indexing gilt, wenn einer der beiden es meldet.</summary>
    class function Better(const A, B: TDpccNoTarget): TDpccNoTarget; static;
  end;

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
    /// <summary>Ankunft der Antwort im Hintergrund-Thread (TThread.GetTickCount64); 0 = unbekannt.</summary>
    ArrivedMs: UInt64;
    /// <summary>Grund des Servers, wenn er kein Sprungziel kennt (Found = False, Error = None).</summary>
    NoTarget: TDpccNoTarget;
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
    /// <summary>Die Stelle der Anfrage ist die unter der Maus (fürs Protokoll).</summary>
    AtMouse: Boolean;
    /// <summary>Beginn der Anfrage, also der Klick (TThread.GetTickCount64).</summary>
    StartedMs: UInt64;
    /// <summary>Bezeichner an der Stelle der Anfrage (Zeichen, 0-basiert, Ende hinter dem letzten Zeichen); Ende ≤
    /// Anfang (Vorgabe 0/0): kein Bezeichner, es zählt nur AtCharacter selbst.</summary>
    AtWordStart: Integer;
    AtWordEnd: Integer;
    /// <summary>Bezeichner am Cursor beim Fragen, wie AtWordStart/AtWordEnd.</summary>
    CaretWordStart: Integer;
    CaretWordEnd: Integer;
    /// <summary>Kennung der Aktion im Ablaufprotokoll (LOG1, dpcc.Core.Diagnostics.Flow); 0 = nicht protokolliert.
    /// </summary>
    FlowId: Integer;
  end;

  /// <summary>Zustand beim Eintreffen der nachgereichten Antwort; CaretLine &lt; 1 ohne Editoransicht.</summary>
  TDpccGotoNow = record
    Generation: Cardinal;
    FileName: string;
    CaretLine: Integer;
    CaretCharacter: Integer;
    NowMs: UInt64;
    /// <summary>Ankunft der Antwort im Hintergrund-Thread (TDpccAnswer.ArrivedMs); 0 = unbekannt, dann zählt NowMs.
    /// </summary>
    ArrivedMs: UInt64;
  end;

  /// <summary>Regeln für ein nachgereichtes Sprungziel.</summary>
  TDpccLateGoto = record
  public
    /// <summary>Passt das Ziel (AFound) noch zum Zustand ANow? Reihenfolge der Prüfung: Ziel, Generation, Alter vom
    /// Klick bis zur Ankunft der Antwort (höchstens AMaxAgeMs), Datei (TTextUris.SamePath), Cursor (im
    /// Bezeichner der Klickstelle oder in dem der Ausgangsstelle; ohne Bezeichner genau an der Stelle).</summary>
    class function Verdict(const AOrigin: TDpccGotoOrigin; const ANow: TDpccGotoNow; AFound: Boolean;
      AMaxAgeMs: Cardinal): TDpccGotoVerdict; static;
    /// <summary>Alter der Antwort für Verdict: Ankunft (ArrivedMs, sonst NowMs) minus Klick; nie negativ.</summary>
    class function AgeMs(const AOrigin: TDpccGotoOrigin; const ANow: TDpccGotoNow): UInt64; static;
    /// <summary>Bezeichner in ALineText an Zeichen ACharacter (0-basiert): darin oder direkt dahinter. AStart und AEnd
    /// (hinter dem letzten Zeichen) 0-basiert; False und beide = ACharacter außerhalb eines Bezeichners.</summary>
    class function WordRange(const ALineText: string; ACharacter: Integer; out AStart, AEnd: Integer): Boolean;
      static;
    /// <summary>Kurzer Text fürs Protokoll.</summary>
    class function VerdictText(AVerdict: TDpccGotoVerdict): string; static;
  end;

  /// <summary>Ein abgelegter Grund aus dpcc/noTarget mit seiner Stelle (Zeile und Zeichen 0-basiert).</summary>
  TDpccNoTargetNote = record
    /// <summary>Datei der Anfrage; Parse liefert hier die URI, die Sitzung macht daraus den Pfad.</summary>
    FileName: string;
    Line: Integer;
    Character: Integer;
    Target: TDpccNoTarget;
    /// <summary>Zeitpunkt der Ablage (TThread.GetTickCount64).</summary>
    StoredMs: UInt64;
    /// <summary>Parameter von dpcc/noTarget lesen (method, uri, line, character, reason, name, indexing). False ohne
    /// uri, line oder character.</summary>
    class function Parse(const AParams: TJSONValue; out ANote: TDpccNoTargetNote): Boolean; static;
  end;

  /// <summary>Ablage der Gründe aus dpcc/noTarget. Threadsicher: Der Lese-Thread legt ab, der Thread von
  /// GotoTargetAt holt ab. Referenzgezählt: Der Empfänger im Lese-Thread hält nur die Ablage, nie die Sitzung.
  /// </summary>
  IDpccNoTargets = interface
    ['{2E7A1C64-58B3-4F0E-A9D2-6C1B8E4F3A97}']
    /// <summary>ANote ablegen (StoredMs = ANowMs); verfallene und überzählige (die ältesten) fallen weg.</summary>
    procedure Add(const ANote: TDpccNoTargetNote; ANowMs: UInt64);
    /// <summary>Grund zur Stelle AFileName (TTextUris.SamePath), ALine, ACharacter abholen und entfernen; bei
    /// AMethod &lt;&gt; '' nur Einträge ohne oder mit dieser Methode. Mehrere passende: der aussagekräftigste
    /// (TDpccNoTarget.Better). False, wenn keiner vorliegt oder alle verfallen sind.</summary>
    function Take(const AMethod, AFileName: string; ALine, ACharacter: Integer; ANowMs: UInt64;
      out ATarget: TDpccNoTarget): Boolean;
    function Count: Integer;
  end;

  TDpccNoTargets = class(TInterfacedObject, IDpccNoTargets)
  private
    FLock: TCriticalSection;
    FEntries: TArray<TDpccNoTargetNote>;
    FMaxEntries: Integer;
    FLifetimeMs: Cardinal;
    /// <summary>Verfallene Einträge entfernen; die Sperre hält der Aufrufer.</summary>
    procedure PruneLocked(ANowMs: UInt64);
  public
    /// <summary>Mit cNoTargetEntries und cNoTargetLifetimeMs.</summary>
    constructor Create; overload;
    constructor Create(AMaxEntries: Integer; ALifetimeMs: Cardinal); overload;
    destructor Destroy; override;
    procedure Add(const ANote: TDpccNoTargetNote; ANowMs: UInt64);
    function Take(const AMethod, AFileName: string; ALine, ACharacter: Integer; ANowMs: UInt64;
      out ATarget: TDpccNoTarget): Boolean;
    function Count: Integer;
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
  dpcc.Text.Uris,
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

/// <summary>Steht ACharacter in Zeile ALine im Bezeichner AStart..AEnd der Zeile AOriginLine (Ende eingeschlossen:
/// Cursor direkt hinter dem Namen)? Ohne Bezeichner (AEnd ≤ AStart) nur genau an AOriginCharacter.</summary>
function InWordOf(ALine, ACharacter, AOriginLine, AOriginCharacter, AStart, AEnd: Integer): Boolean;
begin
  if ALine <> AOriginLine then
  begin
    Exit(False);
  end;
  if AEnd > AStart then
  begin
    Result := (ACharacter >= AStart) and (ACharacter <= AEnd);
  end
  else
  begin
    Result := ACharacter = AOriginCharacter;
  end;
end;

class function TDpccLateGoto.AgeMs(const AOrigin: TDpccGotoOrigin; const ANow: TDpccGotoNow): UInt64;
var
  mArrived: UInt64;
begin
  // Zählt bis zur Ankunft im Hintergrund-Thread: Wie lange der Eintrag im Hauptthread wartete, gehört nicht dazu.
  mArrived := ANow.ArrivedMs;
  if mArrived = 0 then
  begin
    mArrived := ANow.NowMs;
  end;
  Result := 0;
  if mArrived > AOrigin.StartedMs then
  begin
    Result := mArrived - AOrigin.StartedMs;
  end;
end;

class function TDpccLateGoto.WordRange(const ALineText: string; ACharacter: Integer; out AStart,
  AEnd: Integer): Boolean;
begin
  AStart := ACharacter;
  AEnd := ACharacter;
  if (ACharacter < 0) or (ACharacter > Length(ALineText)) then
  begin
    Exit(False);
  end;
  // ALineText[i] ist das Zeichen an der Stelle i - 1 (0-basiert). Im Bezeichner oder direkt dahinter.
  Result := ((ACharacter < Length(ALineText)) and IsNameChar(ALineText[ACharacter + 1])) or
    ((ACharacter > 0) and IsNameChar(ALineText[ACharacter]));
  if not Result then
  begin
    Exit;
  end;
  while (AStart > 0) and IsNameChar(ALineText[AStart]) do
  begin
    Dec(AStart);
  end;
  while (AEnd < Length(ALineText)) and IsNameChar(ALineText[AEnd + 1]) do
  begin
    Inc(AEnd);
  end;
end;

class function TDpccLateGoto.Verdict(const AOrigin: TDpccGotoOrigin; const ANow: TDpccGotoNow; AFound: Boolean;
  AMaxAgeMs: Cardinal): TDpccGotoVerdict;
var
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
  if AgeMs(AOrigin, ANow) > AMaxAgeMs then
  begin
    Exit(TDpccGotoVerdict.TooOld);
  end;
  if (ANow.FileName = '') or not TTextUris.SamePath(ANow.FileName, AOrigin.FileName) then
  begin
    Exit(TDpccGotoVerdict.OtherFile);
  end;
  // Im selben Bezeichner wie der Cursor beim Fragen ...
  mAtOrigin := InWordOf(ANow.CaretLine, ANow.CaretCharacter, AOrigin.CaretLine, AOrigin.CaretCharacter,
    AOrigin.CaretWordStart, AOrigin.CaretWordEnd);
  // ... oder wie die Klickstelle: Setzt die IDE den Cursor bei Strg+Klick auf die Klickstelle (vor oder nach
  // GotoDefinition; nicht geprüft), steht er dort, aber nicht unbedingt in derselben Spalte.
  mAtRequest := InWordOf(ANow.CaretLine, ANow.CaretCharacter, AOrigin.AtLine, AOrigin.AtCharacter,
    AOrigin.AtWordStart, AOrigin.AtWordEnd);
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

{ TDpccNoTarget }

const
  /// <summary>Werte von reason in der Reihenfolge von TDpccNoTargetReason (Vertrag dpcc/noTarget).</summary>
  cReasonCodes: array[TDpccNoTargetReason] of string = ('unknown', 'noDocument', 'noIdentifier', 'unresolved',
    'unitNotFound', 'noSource', 'inactiveBranch', 'other');
  /// <summary>Rang für Better: höher = aussagekräftiger.</summary>
  cReasonRanks: array[TDpccNoTargetReason] of Integer = (0, 2, 3, 5, 6, 7, 4, 1);

class function TDpccNoTarget.ReasonOf(const ACode: string): TDpccNoTargetReason;
var
  mReason: TDpccNoTargetReason;
begin
  if Trim(ACode) = '' then
  begin
    Exit(TDpccNoTargetReason.Unknown);
  end;
  for mReason := Succ(Low(TDpccNoTargetReason)) to High(TDpccNoTargetReason) do
  begin
    if SameText(cReasonCodes[mReason], Trim(ACode)) then
    begin
      Exit(mReason);
    end;
  end;
  Result := TDpccNoTargetReason.Other;
end;

class function TDpccNoTarget.CodeOf(AReason: TDpccNoTargetReason): string;
begin
  Result := cReasonCodes[AReason];
end;

class function TDpccNoTarget.Better(const A, B: TDpccNoTarget): TDpccNoTarget;
begin
  if cReasonRanks[B.Reason] > cReasonRanks[A.Reason] then
  begin
    Result := B;
  end
  else
  begin
    Result := A;
  end;
  Result.Indexing := A.Indexing or B.Indexing;
end;

{ TDpccNoTargetNote }

class function TDpccNoTargetNote.Parse(const AParams: TJSONValue; out ANote: TDpccNoTargetNote): Boolean;
var
  mParams: TJSONObject;
begin
  ANote := Default(TDpccNoTargetNote);
  if not (AParams is TJSONObject) then
  begin
    Exit(False);
  end;
  mParams := TJSONObject(AParams);
  Result := mParams.TryGetValue<string>('uri', ANote.FileName) and (ANote.FileName <> '') and
    mParams.TryGetValue<Integer>('line', ANote.Line) and mParams.TryGetValue<Integer>('character', ANote.Character);
  if not Result then
  begin
    Exit;
  end;
  ANote.Target.Method := mParams.GetValue<string>('method', '');
  ANote.Target.Name := mParams.GetValue<string>('name', '');
  ANote.Target.Indexing := mParams.GetValue<Boolean>('indexing', False);
  // Mit Benachrichtigung, aber ohne reason: Der Server nennt keinen Grund.
  ANote.Target.Reason := TDpccNoTarget.ReasonOf(mParams.GetValue<string>('reason', ''));
  if ANote.Target.Reason = TDpccNoTargetReason.Unknown then
  begin
    ANote.Target.Reason := TDpccNoTargetReason.Other;
  end;
end;

{ TDpccNoTargets }

constructor TDpccNoTargets.Create;
begin
  Create(TDpccLateAnswers.cNoTargetEntries, TDpccLateAnswers.cNoTargetLifetimeMs);
end;

constructor TDpccNoTargets.Create(AMaxEntries: Integer; ALifetimeMs: Cardinal);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FMaxEntries := AMaxEntries;
  if FMaxEntries < 1 then
  begin
    FMaxEntries := 1;
  end;
  FLifetimeMs := ALifetimeMs;
end;

destructor TDpccNoTargets.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TDpccNoTargets.PruneLocked(ANowMs: UInt64);
var
  mIndex: Integer;
begin
  for mIndex := High(FEntries) downto 0 do
  begin
    if (ANowMs < FEntries[mIndex].StoredMs) or (ANowMs - FEntries[mIndex].StoredMs > FLifetimeMs) then
    begin
      System.Delete(FEntries, mIndex, 1);
    end;
  end;
end;

procedure TDpccNoTargets.Add(const ANote: TDpccNoTargetNote; ANowMs: UInt64);
var
  mNote: TDpccNoTargetNote;
begin
  mNote := ANote;
  mNote.StoredMs := ANowMs;
  FLock.Enter;
  try
    PruneLocked(ANowMs);
    // In der Reihenfolge der Ablage: vorne der älteste.
    while Length(FEntries) >= FMaxEntries do
    begin
      System.Delete(FEntries, 0, 1);
    end;
    FEntries := FEntries + [mNote];
  finally
    FLock.Leave;
  end;
end;

function TDpccNoTargets.Take(const AMethod, AFileName: string; ALine, ACharacter: Integer; ANowMs: UInt64;
  out ATarget: TDpccNoTarget): Boolean;
var
  mIndex: Integer;
  mEntry: TDpccNoTargetNote;
begin
  Result := False;
  ATarget := Default(TDpccNoTarget);
  FLock.Enter;
  try
    PruneLocked(ANowMs);
    for mIndex := High(FEntries) downto 0 do
    begin
      mEntry := FEntries[mIndex];
      // Der Pfad der Benachrichtigung kommt aus der URI des Servers, AFileName von der Sitzung: Vergleich wie OnTarget.
      if (mEntry.Line <> ALine) or (mEntry.Character <> ACharacter) or
        not TTextUris.SamePath(mEntry.FileName, AFileName) then
      begin
        Continue;
      end;
      if (AMethod <> '') and (mEntry.Target.Method <> '') and not SameText(mEntry.Target.Method, AMethod) then
      begin
        Continue;
      end;
      if Result then
      begin
        ATarget := TDpccNoTarget.Better(ATarget, mEntry.Target);
      end
      else
      begin
        ATarget := mEntry.Target;
        Result := True;
      end;
      System.Delete(FEntries, mIndex, 1);
    end;
  finally
    FLock.Leave;
  end;
end;

function TDpccNoTargets.Count: Integer;
begin
  FLock.Enter;
  try
    Result := Length(FEntries);
  finally
    FLock.Leave;
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
