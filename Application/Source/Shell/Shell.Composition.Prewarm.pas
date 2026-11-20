unit Shell.Composition.Prewarm;

// Vorladen beim Öffnen und Aktivieren einer Datei (dpcc/prewarm). Die IDE-Seite meldet nach kurzer Ruhe die Datei
// vorn, gleich nach ihrem Abgleich (didOpen bzw. didChange); der Server verarbeitet Benachrichtigungen der Reihe nach
// und kennt den Stand also schon. Ein Auftrag im Hintergrund macht dann, was sonst die erste Anfrage (hover,
// definition, completion) nach dem Öffnen täte, und legt es in deren Zwischenspeicher:
// - den Syntaxbaum des Dokuments (TSyntaxTreeCache.Get: an der Momentaufnahme, je Version und Symbolstand einmal
//   geparst) samt extrahierter Unit (TTreeExtracts am Baum, wie PinTree der Namensauflösung),
// - für jede Unit der uses (interface und implementation, dazu System) die Auflösung wie TResolverUnits.SearchUnit:
//   erst der Index samt Namespaces des Projekts (FindUnit lädt eine kalte Unit aus ihrem Block im Katalog), sonst
//   EnsureUnit (Suchpfade, neu parsen). Nacheinander, mit Abbruchprüfung vor jeder Unit.
// Regeln:
// - Höchstens ein Auftrag je Server, auf einem eigenen Thread mit niedriger Priorität, nie dem Thread der
//   Nachrichtenschleife (der Handler reiht nur ein). Eine Meldung für eine andere Datei bricht den laufenden Auftrag
//   ab (vor der nächsten Unit; ein EnsureUnit bricht über das Abbruchsignal der laufenden Anfrage ab, das der Thread
//   wie ein Handler setzt) und ersetzt den wartenden.
// - Nur berühren, nicht pinnen: geladen wird über FindUnit wie bei einer Anfrage (Nutzungszähler). Kalte Units lädt
//   der Auftrag nur, solange die verdrängbaren unter drei Vierteln des Deckels liegen (TSymbolIndex.cEvictableBudget);
//   so verdrängt Vorladen keine benutzte Unit und hebelt den Deckel nicht aus. Gepinnte und geschützte Units (uses
//   einer Projekt-Unit, oft genutzte) zählen dort ohnehin nicht.
// - Sperren: keine eigene über Index oder Arbeitsbereiche hinweg. FindUnit nimmt die Sperre des Index nur kurz (Block
//   lesen und dekodieren außerhalb), LazyStats einmal je kalter Unit kurz; EnsureUnit die der Arbeitsbereiche nur zum
//   Kopieren der Liste (Parsen außerhalb, #647). Ein laufender Parse lässt sich nicht unterbrechen.
// - Während des Indexaufbaus nichts; die zuletzt gemeldete Datei läuft einmal, wenn der Aufbau fertig ist.
// - Diagnoselog: eine Zeile je Auftrag, "prewarm doc#n units … warm … catalog … parsed … missing … skipped … ms …
//   cancelled yes|no".

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  dpcc.Common.JsonRpc.Contract,
  dpcc.Common.JsonRpc.Dispatcher,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Index.Contract,
  dpcc.Common.Pascal.Contract;

type
  /// <summary>Was ein Auftrag braucht; alles threadsicher.</summary>
  TShellPrewarmInput = record
    Document: ITextDocument;
    /// <summary>Index der Anfragen (samt Ersatz-Units der IDE); nil = nur der Baum.</summary>
    Index: ISymbolIndex;
    /// <summary>Nachladen über die Suchpfade; nil = nur der Index.</summary>
    EnsureUnit: TEnsureUnitFunc;
    /// <summary>Unit-Namespaces aller Projekte (wie TLspDefinition.Namespaces); das Projekt der Datei geht vor.
    /// </summary>
    Namespaces: TArray<string>;
    /// <summary>Kalte Units nur laden, solange die verdrängbaren darunter liegen (Byte, LazyStats.EvictableBytes).
    /// </summary>
    EvictableLimit: Int64;
  end;

  /// <summary>Ergebnis eines Auftrags für das Diagnoselog.</summary>
  TShellPrewarmStats = record
    /// <summary>Units der uses samt System, ohne Doppelte und ohne die eigene.</summary>
    Units: Integer;
    /// <summary>Schon geladen; nur berührt.</summary>
    Warm: Integer;
    /// <summary>Kalt, aus ihrem Block im Katalog geladen.</summary>
    Catalog: Integer;
    /// <summary>Über EnsureUnit neu eingelesen.</summary>
    Parsed: Integer;
    /// <summary>Weder im Index noch über die Suchpfade.</summary>
    Missing: Integer;
    /// <summary>Kalt, wegen des Deckels nicht geladen.</summary>
    Skipped: Integer;
    Cancelled: Boolean;
    ElapsedMs: Int64;
    /// <summary>Zeile fürs Diagnoselog; ADocument kennzeichnet die Datei (doc#n).</summary>
    function Text(const ADocument: string): string;
  end;

  /// <summary>Abbruchsignal eines Auftrags; auch für den Parser.</summary>
  IShellPrewarmCancel = interface(IJsonRpcCancellationToken)
    ['{6E1B4C2A-8D37-4F95-B2A6-3C9E0D7F5A18}']
    procedure Cancel;
  end;

  TShellPrewarmCancel = class(TInterfacedObject, IShellPrewarmCancel, IJsonRpcCancellationToken, IPascalCancellation)
  private
    FCancelled: Integer;
  public
    procedure Cancel;
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
    function IsCancelled: Boolean;
  end;

  /// <summary>Ein Auftrag: Baum und Units der uses vorladen.</summary>
  TShellPrewarmJob = class
  public
    /// <summary>Lädt vor und zählt; prüft ACancel (nil = nie) vor jeder Unit. Fehlende Units sind kein Fehler.
    /// </summary>
    class function Run(const AInput: TShellPrewarmInput; const ACancel: IJsonRpcCancellationToken):
      TShellPrewarmStats; static;
  end;

  /// <summary>Was das Vorladen von der Komposition braucht; die Funktionen fragen erst beim Auftrag.</summary>
  TShellPrewarmServices = record
    Documents: IDocumentStore;
    Index: TFunc<ISymbolIndex>;
    EnsureUnit: TEnsureUnitFunc;
    Namespaces: TFunc<TArray<string>>;
    /// <summary>Wird ein Index aufgebaut? Dann nicht vorladen.</summary>
    IndexBuilding: TFunc<Boolean>;
    /// <summary>Zeile ins Diagnoselog (aus dem Thread des Vorladens).</summary>
    Log: TProc<string>;
    /// <summary>Kennzeichen einer Datei im Diagnoselog (doc#n).</summary>
    DocumentLabel: TFunc<string, string>;
  end;

  /// <summary>Nimmt dpcc/prewarm an und lässt höchstens einen Auftrag zugleich im eigenen Thread laufen.</summary>
  TShellPrewarm = class
  public const
    cMethod = 'dpcc/prewarm';
  private
    FServices: TShellPrewarmServices;
    FLock: TObject;
    /// <summary>Weckt den Thread (Auto-Reset).</summary>
    FWake: TEvent;
    /// <summary>Gesetzt, solange kein Auftrag läuft oder wartet.</summary>
    FIdle: TEvent;
    FThread: TThread;
    /// <summary>Unter FLock: URI des wartenden und des laufenden Auftrags ('' = keiner), dessen Abbruchsignal.
    /// </summary>
    FPending: string;
    FRunning: string;
    FCancel: IShellPrewarmCancel;
    /// <summary>Unter FLock: während des Indexaufbaus gemeldete Datei, läuft nach IndexFinished.</summary>
    FDeferred: string;
    FStopped: Boolean;
    /// <summary>Schleife des Threads.</summary>
    procedure Work;
    function Stopped: Boolean;
    /// <summary>Nächsten Auftrag übernehmen; False ohne (dann gilt der Thread als frei).</summary>
    function Take(out AUri: string; out ACancel: IShellPrewarmCancel): Boolean;
    procedure Finish;
    procedure RunOne(const AUri: string; const ACancel: IShellPrewarmCancel);
    /// <summary>Auftrag für AUri einreihen, ohne auf den Indexaufbau zu achten.</summary>
    procedure Enqueue(const AUri: string);
    procedure Log(const AText: string);
  public
    /// <summary>Startet den Thread; Aufträge erst nach Request.</summary>
    constructor Create(const AServices: TShellPrewarmServices);
    /// <summary>Stop und Freigeben.</summary>
    destructor Destroy; override;
    /// <summary>Meldet dpcc/prewarm (params.uri) am Verteiler an.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Datei AUri vorladen; kehrt sofort zurück. Eine andere Datei bricht den laufenden Auftrag ab, ein
    /// wartender wird ersetzt. Während des Indexaufbaus nur gemerkt (IndexFinished). Threadsicher.</summary>
    procedure Request(const AUri: string);
    /// <summary>Der Indexaufbau ist fertig: die währenddessen gemeldete Datei einmal vorladen.</summary>
    procedure IndexFinished;
    /// <summary>Bricht ab, nimmt nichts mehr an und wartet auf das Ende des Threads (höchstens ein laufender Parse).
    /// Vor dem Freigeben von Index, Ordnern und Sitzung aufrufen.</summary>
    procedure Stop;
    /// <summary>Bis zu AMs warten, bis kein Auftrag mehr läuft oder wartet (Tests).</summary>
    function WaitIdle(AMs: Cardinal): Boolean;
  end;

implementation

uses
  System.StrUtils,
  System.JSON,
  System.Diagnostics,
  System.Generics.Collections,
  dpcc.Common.JsonRpc.CurrentRequest,
  dpcc.Common.Documents.Uris,
  dpcc.Common.Index.SymbolIndex,
  dpcc.Common.Pascal.TreeCache,
  dpcc.Common.Semantics.TreeUnits;

const
  /// <summary>So lange schläft der Thread höchstens, bevor er Stop prüft.</summary>
  cWakeMs = 1000;

type
  TPrewarmThread = class(TThread)
  private
    FOwner: TShellPrewarm;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TShellPrewarm);
  end;

{ TPrewarmThread }

constructor TPrewarmThread.Create(AOwner: TShellPrewarm);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOwner := AOwner;
end;

procedure TPrewarmThread.Execute;
begin
  NameThreadForDebugging('dpcc.Server (prewarm)');
  FOwner.Work;
end;

{ TShellPrewarmStats }

function TShellPrewarmStats.Text(const ADocument: string): string;
begin
  Result := Format('prewarm %s units %d warm %d catalog %d parsed %d missing %d skipped %d ms %d cancelled %s',
    [ADocument, Units, Warm, Catalog, Parsed, Missing, Skipped, ElapsedMs, IfThen(Cancelled, 'yes', 'no')]);
end;

{ TShellPrewarmCancel }

procedure TShellPrewarmCancel.Cancel;
begin
  TInterlocked.Exchange(FCancelled, 1);
end;

function TShellPrewarmCancel.IsCancellationRequested: Boolean;
begin
  Result := TInterlocked.CompareExchange(FCancelled, 0, 0) = 1;
end;

procedure TShellPrewarmCancel.ThrowIfCancellationRequested;
begin
  if IsCancellationRequested then
  begin
    raise EJsonRpcRequestCancelled.Create;
  end;
end;

function TShellPrewarmCancel.IsCancelled: Boolean;
begin
  Result := IsCancellationRequested;
end;

{ TShellPrewarmJob }

function Cancelled(const ACancel: IJsonRpcCancellationToken): Boolean;
begin
  Result := (ACancel <> nil) and ACancel.IsCancellationRequested;
end;

/// <summary>Units aus uses (interface, implementation) und System, ohne Doppelte und ohne AUnit selbst; Reihenfolge
/// wie im Quelltext.</summary>
function UsedUnits(const AUnit: TUnitIndex): TArray<string>;
var
  mSeen: TDictionary<string, Boolean>;
  mAll: TArray<string>;
  mName: string;
begin
  Result := nil;
  mAll := AUnit.InterfaceUses + AUnit.ImplementationUses;
  mAll := mAll + ['System'];
  mSeen := TDictionary<string, Boolean>.Create;
  try
    mSeen.Add(UpperCase(AUnit.UnitName), True);
    for mName in mAll do
    begin
      if (mName <> '') and not mSeen.ContainsKey(UpperCase(mName)) then
      begin
        mSeen.Add(UpperCase(mName), True);
        Result := Result + [mName];
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

/// <summary>Unit-Namespaces für AOrigin wie TResolverUnits.SearchIndex: die des eigenen Projekts, sonst ADefault.
/// </summary>
function NamespacesFor(const AIndex: ISymbolIndex; const AOrigin: string;
  const ADefault: TArray<string>): TArray<string>;
var
  mScopes: IIndexUnitScopes;
  mOwn: TArray<string>;
begin
  Result := ADefault;
  mScopes := AIndex.UnitScopes;
  if (mScopes <> nil) and (AOrigin <> '') and mScopes.NamespacesOf(AOrigin, mOwn) and (Length(mOwn) > 0) then
  begin
    Result := mOwn;
  end;
end;

/// <summary>Kopf der Unit AName bzw. Namespace.AName, ohne zu laden; AFound ist der Name, unter dem sie steht.
/// </summary>
function FindHeader(const AIndex: ISymbolIndex; const AName: string; const ANamespaces: TArray<string>;
  out AFound: string; out AHeader: TUnitIndex): Boolean;
var
  mNamespace: string;
begin
  AFound := AName;
  if AIndex.FindUnitHeader(AName, AHeader) then
  begin
    Exit(True);
  end;
  for mNamespace in ANamespaces do
  begin
    AFound := mNamespace + '.' + AName;
    if AIndex.FindUnitHeader(AFound, AHeader) then
    begin
      Exit(True);
    end;
  end;
  AFound := '';
  Result := False;
end;

/// <summary>Unit AName laden bzw. berühren wie TResolverUnits.FindChosen: bei gleichnamigen Units die des Projekts
/// von AOrigin (L2), sonst FindUnit.</summary>
function LoadUnit(const AIndex: ISymbolIndex; const AOrigin, AName: string): Boolean;
var
  mScopes: IIndexUnitScopes;
  mFiles: TArray<string>;
  mChosen: string;
  mUnit: TUnitIndex;
begin
  mScopes := AIndex.UnitScopes;
  if (mScopes <> nil) and (AOrigin <> '') then
  begin
    mFiles := AIndex.UnitFiles(AName);
    if Length(mFiles) > 1 then
    begin
      mChosen := mScopes.ChooseUnit(AOrigin, AName, mFiles);
      if (mChosen <> '') and AIndex.FindFile(mChosen, mUnit) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := AIndex.FindUnit(AName, mUnit);
end;

/// <summary>Eine Unit der uses vorladen und zählen.</summary>
procedure TouchUnit(const AInput: TShellPrewarmInput; const AOrigin, AName: string;
  const ANamespaces: TArray<string>; var AStats: TShellPrewarmStats);
var
  mFound: string;
  mHeader: TUnitIndex;
begin
  if FindHeader(AInput.Index, AName, ANamespaces, mFound, mHeader) then
  begin
    if Length(mHeader.Symbols) > 0 then
    begin
      // Geladen: nur berühren wie eine Anfrage (Nutzungszähler), nichts pinnen.
      LoadUnit(AInput.Index, AOrigin, mFound);
      Inc(AStats.Warm);
    end
    else if AInput.Index.LazyStats.EvictableBytes >= AInput.EvictableLimit then
    begin
      // Kalt, aber die verdrängbaren füllen den Deckel schon: nicht für eine Vermutung verdrängen.
      Inc(AStats.Skipped);
    end
    else if LoadUnit(AInput.Index, AOrigin, mFound) then
    begin
      Inc(AStats.Catalog);
    end
    else
    begin
      Inc(AStats.Missing);
    end;
    Exit;
  end;
  // Weder im Index noch im Katalog: über die Suchpfade wie TResolverUnits.EnsureAndSearch.
  if Assigned(AInput.EnsureUnit) and AInput.EnsureUnit(AName) and
    FindHeader(AInput.Index, AName, ANamespaces, mFound, mHeader) then
  begin
    Inc(AStats.Parsed);
  end
  else
  begin
    Inc(AStats.Missing);
  end;
end;

/// <summary>Baum, extrahierte Unit und Units der uses; bricht bei ACancel vor der nächsten Unit ab.</summary>
procedure RunSteps(const AInput: TShellPrewarmInput; const ACancel: IJsonRpcCancellationToken;
  var AStats: TShellPrewarmStats);
var
  mParse: IPascalCancellation;
  mShared: ISharedSyntaxTree;
  mFileName, mName: string;
  mNames, mNamespaces: TArray<string>;
begin
  if Cancelled(ACancel) then
  begin
    AStats.Cancelled := True;
    Exit;
  end;
  if (ACancel = nil) or not Supports(ACancel, IPascalCancellation, mParse) then
  begin
    mParse := nil;
  end;
  mFileName := TDocumentUris.ToPath(AInput.Document.Uri);
  // Derselbe Baum wie bei hover, definition und completion: an der Momentaufnahme, je Version einmal geparst.
  mShared := TSyntaxTreeCache.Get(AInput.Document, mParse);
  // Die extrahierte Unit hängt am Baum (wie PinTree der Namensauflösung): Anfragen derselben Version werten ihn
  // nicht noch einmal aus.
  mNames := UsedUnits(TTreeExtracts.ForTree(mShared.Tree).Extracted(mFileName));
  AStats.Units := Length(mNames);
  if AInput.Index = nil then
  begin
    Exit;
  end;
  mNamespaces := NamespacesFor(AInput.Index, mFileName, AInput.Namespaces);
  for mName in mNames do
  begin
    if Cancelled(ACancel) then
    begin
      AStats.Cancelled := True;
      Exit;
    end;
    TouchUnit(AInput, mFileName, mName, mNamespaces, AStats);
  end;
end;

class function TShellPrewarmJob.Run(const AInput: TShellPrewarmInput;
  const ACancel: IJsonRpcCancellationToken): TShellPrewarmStats;
var
  mWatch: TStopwatch;
begin
  Result := Default(TShellPrewarmStats);
  mWatch := TStopwatch.StartNew;
  try
    try
      RunSteps(AInput, ACancel, Result);
    except
      // Abbruch in EnsureUnit (Signal der laufenden Anfrage): wie ein Abbruch vor der nächsten Unit.
      on EJsonRpcRequestCancelled do
      begin
        Result.Cancelled := True;
      end;
    end;
  finally
    Result.ElapsedMs := mWatch.ElapsedMilliseconds;
  end;
end;

{ TShellPrewarm }

constructor TShellPrewarm.Create(const AServices: TShellPrewarmServices);
begin
  inherited Create;
  FServices := AServices;
  FLock := TObject.Create;
  FWake := TEvent.Create(nil, False, False, '');
  FIdle := TEvent.Create(nil, True, True, '');
  FThread := TPrewarmThread.Create(Self);
  // Echte Anfragen haben Vorrang. Nur eine Stufe tiefer: Wartet eine Anfrage auf denselben Parse bzw. dieselbe kalte
  // Unit (gemeinsamer Lauf im Zwischenspeicher), soll das Vorladen sie nicht lange aufhalten.
  FThread.Priority := tpLower;
  FThread.Start;
end;

destructor TShellPrewarm.Destroy;
begin
  Stop;
  FreeAndNil(FThread);
  FreeAndNil(FIdle);
  FreeAndNil(FWake);
  FreeAndNil(FLock);
  inherited;
end;

procedure TShellPrewarm.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterNotification(cMethod,
    procedure(const AParams: TJSONValue)
    var
      mUri: string;
    begin
      // Nur einreihen: Die Nachrichtenschleife wartet nie auf das Vorladen.
      if (AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('uri', mUri) and (mUri <> '') then
      begin
        Request(mUri);
      end;
    end);
end;

procedure TShellPrewarm.Request(const AUri: string);
var
  mBuilding: Boolean;
begin
  // Außerhalb der eigenen Sperre: fragt die Arbeitsbereiche.
  mBuilding := Assigned(FServices.IndexBuilding) and FServices.IndexBuilding();
  if mBuilding then
  begin
    System.TMonitor.Enter(FLock);
    try
      if not FStopped then
      begin
        FDeferred := AUri;
      end;
    finally
      System.TMonitor.Exit(FLock);
    end;
    Exit;
  end;
  Enqueue(AUri);
end;

procedure TShellPrewarm.IndexFinished;
var
  mUri: string;
begin
  System.TMonitor.Enter(FLock);
  try
    mUri := FDeferred;
    FDeferred := '';
  finally
    System.TMonitor.Exit(FLock);
  end;
  if mUri <> '' then
  begin
    Enqueue(mUri);
  end;
end;

procedure TShellPrewarm.Enqueue(const AUri: string);
begin
  System.TMonitor.Enter(FLock);
  try
    if FStopped then
    begin
      Exit;
    end;
    // Eine andere Datei ist vorn: Der laufende Auftrag lohnt nicht mehr (Abbruch vor der nächsten Unit).
    if (FCancel <> nil) and not SameText(FRunning, AUri) then
    begin
      FCancel.Cancel;
    end;
    FPending := AUri;
    FIdle.ResetEvent;
  finally
    System.TMonitor.Exit(FLock);
  end;
  FWake.SetEvent;
end;

procedure TShellPrewarm.Stop;
begin
  System.TMonitor.Enter(FLock);
  try
    FStopped := True;
    FPending := '';
    FDeferred := '';
    if FCancel <> nil then
    begin
      FCancel.Cancel;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  FWake.SetEvent;
  if FThread <> nil then
  begin
    FThread.WaitFor;
  end;
end;

function TShellPrewarm.WaitIdle(AMs: Cardinal): Boolean;
begin
  Result := FIdle.WaitFor(AMs) = wrSignaled;
end;

function TShellPrewarm.Stopped: Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FStopped;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TShellPrewarm.Work;
var
  mUri: string;
  mCancel: IShellPrewarmCancel;
begin
  while not Stopped do
  begin
    FWake.WaitFor(cWakeMs);
    while Take(mUri, mCancel) do
    begin
      try
        RunOne(mUri, mCancel);
      except
        // Nie aus dem Thread heraus: Im IDE-Prozess fängt sonst niemand.
        on Exception do
        begin
        end;
      end;
      Finish;
    end;
  end;
end;

function TShellPrewarm.Take(out AUri: string; out ACancel: IShellPrewarmCancel): Boolean;
begin
  AUri := '';
  ACancel := nil;
  System.TMonitor.Enter(FLock);
  try
    Result := not FStopped and (FPending <> '');
    if Result then
    begin
      AUri := FPending;
      FPending := '';
      FRunning := AUri;
      FCancel := TShellPrewarmCancel.Create;
      ACancel := FCancel;
    end
    else
    begin
      FIdle.SetEvent;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TShellPrewarm.Finish;
begin
  System.TMonitor.Enter(FLock);
  try
    FRunning := '';
    FCancel := nil;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TShellPrewarm.RunOne(const AUri: string; const ACancel: IShellPrewarmCancel);
var
  mDocument: ITextDocument;
  mInput: TShellPrewarmInput;
  mStats: TShellPrewarmStats;
  mLabel: string;
  mPrevious: Pointer;
begin
  // Inzwischen geschlossen: nichts zu tun.
  if (FServices.Documents = nil) or not FServices.Documents.TryGet(AUri, mDocument) then
  begin
    Exit;
  end;
  mInput := Default(TShellPrewarmInput);
  mInput.Document := mDocument;
  if Assigned(FServices.Index) then
  begin
    mInput.Index := FServices.Index();
  end;
  mInput.EnsureUnit := FServices.EnsureUnit;
  if Assigned(FServices.Namespaces) then
  begin
    mInput.Namespaces := FServices.Namespaces();
  end;
  mInput.EvictableLimit := TSymbolIndex.cEvictableBudget div 4 * 3;
  mLabel := 'doc';
  if Assigned(FServices.DocumentLabel) then
  begin
    mLabel := FServices.DocumentLabel(TDocumentUris.ToPath(AUri));
  end;
  // Wie ein Handler: EnsureUnit prüft das Signal der laufenden Anfrage zwischen den Arbeitsbereichen.
  mPrevious := TJsonRpcCurrentRequest.Enter(ACancel);
  try
    try
      mStats := TShellPrewarmJob.Run(mInput, ACancel);
      Log(mStats.Text(mLabel));
    except
      on E: Exception do
      begin
        Log(Format('prewarm %s failed %s', [mLabel, E.ClassName]));
      end;
    end;
  finally
    TJsonRpcCurrentRequest.Leave(mPrevious);
  end;
end;

procedure TShellPrewarm.Log(const AText: string);
begin
  if Assigned(FServices.Log) then
  begin
    FServices.Log(AText);
  end;
end;

end.
