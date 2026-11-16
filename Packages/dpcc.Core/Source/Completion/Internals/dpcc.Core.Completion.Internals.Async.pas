unit dpcc.Core.Completion.Internals.Async;

// Basis für Datenquellen der Vervollständigung, die im Hintergrund arbeiten
// (#408). Query ruft Prepare im aufrufenden Thread – seit #493 meist ein
// Arbeiter von TDpccTimeLimit (Composite.QueryOne), nicht der Hauptthread –
// und Fetch in einem eigenen Thread; dessen Ergebnis geht nur an die Senke,
// wenn der Query noch aktuell ist. Mehrere Threads dürfen gleichzeitig laufen,
// damit ein neuer Query nie auf einen langsamen alten warten muss. Beim
// Freigeben wartet die Quelle auf alle Threads (Entladen des Packages, #493).
// Fehler in Fetch und in RunInBackground zählt die Sicherung je Quelle
// (ProviderName, #493); IsFailure nimmt erwartbare Fälle aus (Server weg).

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Diagnostics.Guard;

type
  /// <summary>True, sobald der Query abgebrochen oder durch einen neuen ersetzt ist.</summary>
  TDpccCancelledFunc = reference to function: Boolean;

  /// <summary>Teilergebnis während Fetch (#616): geht sofort an die Senke, solange der Query aktuell ist.</summary>
  TDpccEmitProc = reference to procedure(const AItems: TDpccCompletionItems);

  /// <summary>Merker, ob die Quelle noch lebt; eingereihte Aufrufe halten ihn selbst.</summary>
  TDpccAliveToken = class(TInterfacedObject)
  public
    Alive: Boolean;
  end;

  TDpccAsyncCompletionProvider = class(TInterfacedObject, IDpccCompletionProvider, IDpccNamedProvider)
  private
    FName: string;
    FToken: TDpccAliveToken;
    FTokenRef: IInterface;
    FLock: TCriticalSection;
    FGeneration: Integer;
    FWorkers: TList<TThread>;
    procedure ReapWorkers;
    function IsCurrent(AGeneration: Integer): Boolean;
    procedure Failed(AE: Exception);
    /// <summary>Arbeit eines Hintergrund-Threads von Query: Fetch mit Teilergebnissen, dann das Ergebnis an
    /// ASink, solange AGeneration aktuell ist.</summary>
    procedure RunFetch(const AContext: TDpccContext; AData: TObject; const ASink: IDpccCompletionSink;
      AGeneration: Integer);
  protected
    /// <summary>Zählt E als Fehler der Quelle? Standard: ja.</summary>
    function IsFailure(AE: Exception): Boolean; virtual;
    /// <summary>Im aufrufenden Thread vor dem Start, meist im Zeitlimit-Arbeiter (#493): weder VCL noch Open Tools
    /// API, kein Serverstart. False = nichts zu tun (Complete sofort).
    /// AData geht unverändert an Fetch (nicht übernommen, muss bis zum Ende von Fetch leben).</summary>
    function Prepare(const AContext: TDpccContext; out AData: TObject): Boolean; virtual;
    /// <summary>Im Hintergrund. Ausnahmen gelten als leeres Ergebnis. AState.Incomplete: Die Liste ist
    /// gekürzt, beim Weitertippen neu fragen (#431); AState.Syntax: Hinweis bei unvollständigem Code (#457).
    /// AEmit liefert Teilergebnisse vorab (#616), auch aus
    /// anderen Threads, aber nur bis Fetch zurückkehrt; das Ergebnis kommt danach dazu.</summary>
    function Fetch(const AContext: TDpccContext; AData: TObject; const ACancelled: TDpccCancelledFunc;
      const AEmit: TDpccEmitProc; out AState: TDpccFetchState): TDpccCompletionItems; virtual; abstract;
    /// <summary>Weitere Arbeit im Hintergrund (z. B. Details nachfragen); Shutdown wartet auch darauf.</summary>
    procedure RunInBackground(const AWork: TProc);
    /// <summary>Für Aufrufe per TDpccMainThread.Queue: nur ausführen, solange Token.Alive gilt.</summary>
    property Token: TDpccAliveToken read FToken;
    property TokenRef: IInterface read FTokenRef;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Bricht ab und wartet auf alle laufenden Threads.</summary>
    procedure Shutdown;
    { IDpccCompletionProvider }
    procedure Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
    procedure Cancel;
    { IDpccNamedProvider }
    function ProviderName: string;
    /// <summary>Name für Sicherung, Meldungen und Einstellungsseite; '' = Klassenname.</summary>
    property Name: string read FName write FName;
  end;

implementation

{ TDpccAsyncCompletionProvider }

constructor TDpccAsyncCompletionProvider.Create;
begin
  inherited Create;
  FToken := TDpccAliveToken.Create;
  FToken.Alive := True;
  FTokenRef := FToken;
  FLock := TCriticalSection.Create;
  FWorkers := TList<TThread>.Create;
end;

destructor TDpccAsyncCompletionProvider.Destroy;
begin
  Shutdown;
  FToken.Alive := False;
  FTokenRef := nil;
  FWorkers.Free;
  FLock.Free;
  inherited;
end;

function TDpccAsyncCompletionProvider.Prepare(const AContext: TDpccContext; out AData: TObject): Boolean;
begin
  AData := nil;
  Result := True;
end;

function TDpccAsyncCompletionProvider.ProviderName: string;
begin
  Result := FName;
  if Result = '' then
  begin
    Result := ClassName;
  end;
end;

function TDpccAsyncCompletionProvider.IsFailure(AE: Exception): Boolean;
begin
  Result := not (AE is EAbort);
end;

procedure TDpccAsyncCompletionProvider.Failed(AE: Exception);
begin
  try
    if IsFailure(AE) then
    begin
      TDpccGuard.ReportProvider(ProviderName, AE);
    end;
  except
    // Melden darf den Hintergrund-Thread nicht beenden.
  end;
end;

function TDpccAsyncCompletionProvider.IsCurrent(AGeneration: Integer): Boolean;
begin
  Result := TInterlocked.CompareExchange(FGeneration, 0, 0) = AGeneration;
end;

procedure TDpccAsyncCompletionProvider.RunInBackground(const AWork: TProc);
var
  mWorker: TThread;
begin
  ReapWorkers;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    begin
      try
        AWork();
      except
        // Hintergrundarbeit darf die IDE nie stören (#493); gezählt je Quelle.
        on E: Exception do
          Failed(E);
      end;
    end);
  mWorker.FreeOnTerminate := False;
  FLock.Enter;
  try
    FWorkers.Add(mWorker);
  finally
    FLock.Leave;
  end;
  mWorker.Start;
end;

procedure TDpccAsyncCompletionProvider.ReapWorkers;
var
  mIndex: Integer;
begin
  FLock.Enter;
  try
    for mIndex := FWorkers.Count - 1 downto 0 do
    begin
      if FWorkers[mIndex].Finished then
      begin
        FWorkers[mIndex].Free;
        FWorkers.Delete(mIndex);
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TDpccAsyncCompletionProvider.Shutdown;
var
  mWorkers: TArray<TThread>;
  mWorker: TThread;
begin
  Cancel;
  FLock.Enter;
  try
    mWorkers := FWorkers.ToArray;
    FWorkers.Clear;
  finally
    FLock.Leave;
  end;
  for mWorker in mWorkers do
  begin
    mWorker.WaitFor;
    mWorker.Free;
  end;
end;

procedure TDpccAsyncCompletionProvider.Cancel;
begin
  TInterlocked.Increment(FGeneration);
end;

/// <summary>Ergebnis von Fetch an ASink: Einträge, Kürzung, Syntaxhinweis und Ende.</summary>
procedure Deliver(const ASink: IDpccCompletionSink; const AItems: TDpccCompletionItems;
  const AState: TDpccFetchState);
begin
  ASink.AddItems(AItems);
  if AState.Incomplete then
  begin
    ASink.MarkIncomplete;
  end;
  if AState.Syntax.Trust <> TDpccSyntaxTrust.Sure then
  begin
    ASink.MarkSyntax(AState.Syntax);
  end;
  ASink.Complete;
end;

procedure TDpccAsyncCompletionProvider.RunFetch(const AContext: TDpccContext; AData: TObject;
  const ASink: IDpccCompletionSink; AGeneration: Integer);
var
  mSink: IDpccCompletionSink;
  mGeneration: Integer;
  mItems: TDpccCompletionItems;
  mState: TDpccFetchState;
begin
  mSink := ASink;
  mGeneration := AGeneration;
  mItems := nil;
  mState := Default(TDpccFetchState);
  try
    mItems := Fetch(AContext, AData,
      function: Boolean
      begin
        Result := not IsCurrent(mGeneration);
      end,
      procedure(const AItems: TDpccCompletionItems)
      begin
        if (Length(AItems) > 0) and IsCurrent(mGeneration) then
        begin
          mSink.AddItems(AItems);
        end;
      end, mState);
  except
    // Server weg, Zeitlimit oder unerwartete Antwort: keine Einträge; Fehler zählt die Sicherung (#493).
    on E: Exception do
    begin
      mItems := nil;
      mState := Default(TDpccFetchState);
      Failed(E);
    end;
  end;
  if IsCurrent(mGeneration) then
  begin
    Deliver(mSink, mItems, mState);
  end;
end;

procedure TDpccAsyncCompletionProvider.Query(const AContext: TDpccContext; const ASink: IDpccCompletionSink);
var
  mGeneration: Integer;
  mContext: TDpccContext;
  mSink: IDpccCompletionSink;
  mData: TObject;
  mWorker: TThread;
begin
  mGeneration := TInterlocked.Increment(FGeneration);
  ReapWorkers;
  if not Prepare(AContext, mData) then
  begin
    ASink.Complete;
    Exit;
  end;
  mContext := AContext;
  mSink := ASink;
  mWorker := nil;
  FLock.Enter;
  try
    // Prepare läuft im Zeitlimit-Arbeiter und kann das Zeitlimit überdauern: Ist die Anfrage
    // inzwischen überholt, abgebrochen oder hat Shutdown die Arbeiter eingesammelt, keine Vollanfrage mehr stellen.
    // Unter FLock und mit Start in der Sperre, damit Shutdown keinen danach gestarteten Arbeiter übersieht.
    if IsCurrent(mGeneration) then
    begin
      mWorker := TThread.CreateAnonymousThread(
        procedure
        begin
          RunFetch(mContext, mData, mSink, mGeneration);
        end);
      mWorker.FreeOnTerminate := False;
      FWorkers.Add(mWorker);
      mWorker.Start;
    end;
  finally
    FLock.Leave;
  end;
  // Überholt: Die Senken verwerfen veraltete Aufrufe; Composite erwartet je Teil ein Complete.
  if mWorker = nil then
  begin
    ASink.Complete;
  end;
end;

end.
