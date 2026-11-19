unit dpcc.Core.Diagnostics.MainThread;

// Einreihen in den Hauptthread der IDE, ohne dass ein Eintrag das Entladen des
// Packages überlebt. TThread.Queue(nil, …) und
// ForceQueue(nil, …) gehören keinem Thread: Nichts räumt sie beim Entladen
// weg, und CheckSynchronize ruft sie danach in nicht mehr geladenem Code auf.
// Hier gehört jeder Eintrag einem eigenen, ruhenden Besitzer-Thread. Stop (die
// Komposition ruft es direkt nach TDpccShutdown.Signal) entfernt alle noch
// wartenden Einträge und nimmt keine neuen mehr an.
// Nicht an den aufrufenden Arbeiter gebunden: Hover und Vervollständigung geben
// fertige Arbeiter frei (ReapWorkers), bevor CheckSynchronize ihre Einträge
// ausführt; TThread.Destroy würde die Ergebnisse dann entfernen.
// Jeder Eintrag läuft unter der Sicherung (#493): Eine Ausnahme zählt für das
// angegebene Feature und erreicht nie TApplication.HandleException.
// Queue führt im Hauptthread sofort aus (wie TThread.Queue), ForceQueue reiht
// immer ein. Beide sind aus jedem Thread aufrufbar.
// Einträge je Modul: Base bleibt geladen, wenn ein Modul-Package einzeln
// entladen wird; Stop läuft dann nicht. Ein Eintrag, dessen Code im Modul liegt,
// lief früher danach in nicht mehr geladenem Code (Zugriffsverletzung in
// Guarded). Jeder Eintrag merkt sich daher das Modul seines Codes
// (FindHInstance der anonymen Methode). Die Registry ruft beim Abmelden
// CloseModule (wartende Einträge verwerfen, keine neuen annehmen), beim Anmelden
// OpenModule; beim Entladen jedes Packages verwirft ModuleUnloaded (über
// AddModuleUnloadProc) als Sicherheitsnetz, was noch wartet. Nicht erfasst:
// Einträge, deren Code in Base liegt, die aber Objekte eines Moduls einfangen.
// Name für den Einfrier-Wächter: Jeder Eintrag läuft als dpcc-Aktivität
// (TDpccActivity.Scope) mit dem Namen aus der Überladung mit AName, sonst
// „Hauptthread-Eintrag <Feature>“. So nennt ein Hänger oder eine langsame
// Zeile im dpcc.log auch eingereihte Arbeit.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  dpcc.Core.Diagnostics.Guard;

type
  TDpccMainThread = class
  private type
    /// <summary>Besitzer der Einträge; schläft, bis Stop ihn beendet.</summary>
    TOwner = class(TThread)
    private
      FWake: TEvent;
    protected
      procedure Execute; override;
      procedure TerminatedSet; override;
    public
      constructor Create;
      destructor Destroy; override;
    end;
    /// <summary>Wartender Eintrag: Modul seines Codes und die Prozedur.</summary>
    TPending = record
      Module: NativeUInt;
      Proc: TThreadProcedure;
    end;
  private class var
    FLock: TCriticalSection;
    FOwner: TOwner;
    FStopped: Boolean;
    /// <summary>Wartende Einträge nach laufender Nummer (nicht nach Adresse: die könnte neu vergeben sein).</summary>
    FPending: TDictionary<UInt64, TPending>;
    FNextId: UInt64;
    /// <summary>Abgemeldete Module: Einträge mit Code darin werden nicht mehr angenommen.</summary>
    FClosed: TList<NativeUInt>;
    /// <summary>AProc unter der Sicherung von AFeature und als Aktivität AName ('' = „Hauptthread-Eintrag
    /// Feature“).</summary>
    class function Guarded(AFeature: TDpccFeature; const AName: string;
      const AProc: TThreadProcedure): TThreadProcedure; static;
    class procedure Post(AFeature: TDpccFeature; const AName: string; const AProc: TThreadProcedure;
      AForce: Boolean); static;
    /// <summary>Unter FLock: AProc als wartenden Eintrag führen; Ergebnis die Prozedur, die ihn ausführt.</summary>
    class function AddPending(AModule: NativeUInt; const AProc: TThreadProcedure): TThreadProcedure; static;
    /// <summary>Eintrag AId aus der Liste nehmen und ausführen, falls er nicht verworfen ist.</summary>
    class procedure RunPending(AId: UInt64); static;
    /// <summary>Wartende Einträge von AModule (0 = alle) aus der Liste nehmen; Ergebnis ihre Prozeduren, die der
    /// Aufrufer außerhalb von FLock freigibt.</summary>
    class function TakePending(AModule: NativeUInt): TArray<TThreadProcedure>; static;
    class procedure DropModule(AModule: NativeUInt; AClose: Boolean); static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Im Hauptthread sofort, aus anderen Threads eingereiht. Ausnahmen zählen für AFeature.</summary>
    class procedure Queue(AFeature: TDpccFeature; const AProc: TThreadProcedure); overload; static;
    /// <summary>Wie oben; AName nennt die Arbeit als dpcc-Aktivität (Wächter, dpcc.log).</summary>
    class procedure Queue(AFeature: TDpccFeature; const AName: string; const AProc: TThreadProcedure); overload;
      static;
    /// <summary>Immer eingereiht, auch aus dem Hauptthread (läuft nach dem laufenden Ereignis).
    /// Nach Stop verworfen.</summary>
    class procedure ForceQueue(AFeature: TDpccFeature; const AProc: TThreadProcedure); overload; static;
    /// <summary>Wie oben; AName nennt die Arbeit als dpcc-Aktivität (Wächter, dpcc.log).</summary>
    class procedure ForceQueue(AFeature: TDpccFeature; const AName: string; const AProc: TThreadProcedure);
      overload; static;
    /// <summary>Nach dem Laden (Register): Einträge wieder annehmen.</summary>
    class procedure Start; static;
    /// <summary>Beim Entladen, nur im Hauptthread: wartende Einträge verwerfen, keine neuen annehmen.</summary>
    class procedure Stop; static;
    /// <summary>Läuft der Aufrufer im Hauptthread?</summary>
    class function IsMain: Boolean; static;
    /// <summary>Modul (HInstance), in dem der Code der anonymen Methode AProc liegt; 0 ohne Methode.</summary>
    class function ModuleOf(const AProc: TThreadProcedure): NativeUInt; static;
    /// <summary>Modul AModule meldet sich ab: seine wartenden Einträge verwerfen, neue nicht mehr annehmen.
    /// 0 wird übergangen.</summary>
    class procedure CloseModule(AModule: NativeUInt); static;
    /// <summary>Modul AModule meldet sich (wieder) an: seine Einträge wieder annehmen.</summary>
    class procedure OpenModule(AModule: NativeUInt); static;
    /// <summary>Package AModule wird entladen: wartende Einträge verwerfen; ein später unter demselben Handle
    /// geladenes Package beginnt offen.</summary>
    class procedure ModuleUnloaded(AModule: NativeUInt); static;
    /// <summary>Anzahl wartender, nicht verworfener Einträge (Tests, Diagnose).</summary>
    class function PendingCount: Integer; static;
  end;

implementation

uses
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Diagnostics.Hangs;

const
  /// <summary>Platz der Methode Invoke in der Schnittstellentabelle einer anonymen Methode (nach QueryInterface,
  /// _AddRef und _Release).</summary>
  cInvokeSlot = 3;
  /// <summary>Anfangsgrößen: Erst beim Wachsen angelegter Speicher zählte im ersten Test, der einreiht, als Leck.
  /// </summary>
  cPendingCapacity = 256;
  cClosedCapacity = 32;

type
  TCodeTable = array[0..cInvokeSlot] of Pointer;
  PCodeTable = ^TCodeTable;

/// <summary>Modul der Methode Invoke einer Methodenreferenz; untypisiert, damit kein @ die Referenz aufruft.
/// </summary>
function CodeModuleOf(const AReference): NativeUInt;
var
  mInstance: Pointer;
  mTable: PCodeTable;
begin
  Result := 0;
  mInstance := Pointer(AReference);
  if mInstance = nil then
  begin
    Exit;
  end;
  // Eine anonyme Methode ist eine Schnittstelle; Invoke liegt im Modul, das sie übersetzt hat.
  mTable := PPointer(mInstance)^;
  Result := NativeUInt(FindHInstance(mTable^[cInvokeSlot]));
end;

/// <summary>Beim Entladen jedes Packages (AddModuleUnloadProc), solange sein Code noch geladen ist.</summary>
procedure DpccMainThreadModuleUnload(AInstance: NativeInt);
begin
  TDpccMainThread.ModuleUnloaded(NativeUInt(AInstance));
end;

{ TDpccMainThread.TOwner }

constructor TDpccMainThread.TOwner.Create;
begin
  FWake := TEvent.Create(nil, True, False, '');
  inherited Create(False);
end;

destructor TDpccMainThread.TOwner.Destroy;
begin
  inherited Destroy;
  FWake.Free;
end;

procedure TDpccMainThread.TOwner.Execute;
begin
  NameThreadForDebugging('dpcc.MainThread');
  // Der Thread führt nichts aus; er besitzt nur die Einträge (RemoveQueuedEvents in Stop).
  while not Terminated do
  begin
    FWake.WaitFor(1000);
  end;
end;

procedure TDpccMainThread.TOwner.TerminatedSet;
begin
  inherited;
  FWake.SetEvent;
end;

{ TDpccMainThread }

class constructor TDpccMainThread.Create;
begin
  FLock := TCriticalSection.Create;
  // Gleich beim Laden: Ein späteres Anlegen zählte im ersten Test, der einreiht, als Leck.
  FOwner := TOwner.Create;
  FStopped := False;
  FPending := TDictionary<UInt64, TPending>.Create(cPendingCapacity);
  FClosed := TList<NativeUInt>.Create;
  FClosed.Capacity := cClosedCapacity;
  FNextId := 0;
  AddModuleUnloadProc(DpccMainThreadModuleUnload);
end;

class destructor TDpccMainThread.Destroy;
begin
  RemoveModuleUnloadProc(DpccMainThreadModuleUnload);
  Stop;
  FreeAndNil(FPending);
  FreeAndNil(FClosed);
  FreeAndNil(FLock);
end;

class function TDpccMainThread.IsMain: Boolean;
begin
  Result := TThread.CurrentThread.ThreadID = MainThreadID;
end;

class function TDpccMainThread.Guarded(AFeature: TDpccFeature; const AName: string;
  const AProc: TThreadProcedure): TThreadProcedure;
var
  mFeature: TDpccFeature;
  mName: string;
  mProc: TThreadProcedure;
begin
  mFeature := AFeature;
  mName := AName;
  mProc := AProc;
  Result :=
    procedure
    var
      mActivity: IInterface;
    begin
      try
        // Name erst bei der Ausführung (Sprache der Oberfläche); außerhalb des Hauptthreads nil.
        if mName <> '' then
        begin
          mActivity := TDpccActivity.Scope(mName);
        end
        else
        begin
          mActivity := TDpccActivity.Scope('Hauptthread-Eintrag ' + TDpccGuard.FeatureName(mFeature));
        end;
        mProc();
      except
        on EAbort do
          ;
        on E: Exception do
          TDpccGuard.Report(mFeature, E);
      end;
    end;
end;

class function TDpccMainThread.ModuleOf(const AProc: TThreadProcedure): NativeUInt;
begin
  Result := CodeModuleOf(AProc);
end;

class function TDpccMainThread.AddPending(AModule: NativeUInt; const AProc: TThreadProcedure): TThreadProcedure;
var
  mId: UInt64;
  mPending: TPending;
begin
  Inc(FNextId);
  mId := FNextId;
  mPending.Module := AModule;
  mPending.Proc := AProc;
  FPending.Add(mId, mPending);
  Result :=
    procedure
    begin
      RunPending(mId);
    end;
end;

class procedure TDpccMainThread.RunPending(AId: UInt64);
var
  mPending: TPending;
  mFound: Boolean;
begin
  if FLock = nil then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    mFound := FPending.TryGetValue(AId, mPending);
    if mFound then
    begin
      FPending.Remove(AId);
    end;
  finally
    FLock.Leave;
  end;
  if mFound and Assigned(mPending.Proc) then
  begin
    mPending.Proc();
  end;
end;

class function TDpccMainThread.TakePending(AModule: NativeUInt): TArray<TThreadProcedure>;
var
  mIds: TArray<UInt64>;
  mPair: TPair<UInt64, TPending>;
  mCount: Integer;
  mIndex: Integer;
begin
  SetLength(mIds, FPending.Count);
  SetLength(Result, FPending.Count);
  mCount := 0;
  for mPair in FPending do
  begin
    if (AModule = 0) or (mPair.Value.Module = AModule) then
    begin
      mIds[mCount] := mPair.Key;
      Result[mCount] := mPair.Value.Proc;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
  for mIndex := 0 to mCount - 1 do
  begin
    FPending.Remove(mIds[mIndex]);
  end;
end;

class procedure TDpccMainThread.DropModule(AModule: NativeUInt; AClose: Boolean);
var
  mDropped: TArray<TThreadProcedure>;
begin
  if (AModule = 0) or (FLock = nil) then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    mDropped := TakePending(AModule);
    if not AClose then
    begin
      FClosed.Remove(AModule);
    end
    else if FClosed.IndexOf(AModule) < 0 then
    begin
      FClosed.Add(AModule);
    end;
  finally
    FLock.Leave;
  end;
  if mDropped <> nil then
  begin
    TDpccGuard.Log(Format('dpcc: dropped %d queued main thread entries of module $%x', [Length(mDropped), AModule]));
  end;
  // mDropped wird erst beim Verlassen frei, außerhalb der Sperre: Was die Einträge einfangen, darf beim Freigeben
  // wieder einreihen.
end;

class procedure TDpccMainThread.CloseModule(AModule: NativeUInt);
begin
  DropModule(AModule, True);
end;

class procedure TDpccMainThread.ModuleUnloaded(AModule: NativeUInt);
begin
  DropModule(AModule, False);
end;

class procedure TDpccMainThread.OpenModule(AModule: NativeUInt);
begin
  if (AModule = 0) or (FLock = nil) then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    FClosed.Remove(AModule);
  finally
    FLock.Leave;
  end;
end;

class function TDpccMainThread.PendingCount: Integer;
begin
  Result := 0;
  if FLock = nil then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    Result := FPending.Count;
  finally
    FLock.Leave;
  end;
end;

class procedure TDpccMainThread.Post(AFeature: TDpccFeature; const AName: string; const AProc: TThreadProcedure;
  AForce: Boolean);
var
  mProc: TThreadProcedure;
  mModule: NativeUInt;
begin
  if FLock = nil then
  begin
    Exit;
  end;
  mModule := ModuleOf(AProc);
  // Unter FLock nur einreihen, nie ausführen (AForce oder Arbeiter-Thread): Kein fremder Code hält die Sperre,
  // ein Hauptthread in Stop kann nicht auf einen Arbeiter warten, der hier wartet.
  FLock.Enter;
  try
    // Nach Stop (Entladen) oder Abmelden des Moduls: verwerfen; der Code dahinter ist gleich nicht mehr geladen.
    if FStopped or (FOwner = nil) or (FClosed.IndexOf(mModule) >= 0) then
    begin
      Exit;
    end;
    mProc := Guarded(AFeature, AName, AddPending(mModule, AProc));
    if AForce then
    begin
      TThread.ForceQueue(FOwner, mProc);
    end
    else
    begin
      TThread.Queue(FOwner, mProc);
    end;
  finally
    FLock.Leave;
  end;
end;

class procedure TDpccMainThread.Queue(AFeature: TDpccFeature; const AProc: TThreadProcedure);
begin
  Queue(AFeature, '', AProc);
end;

class procedure TDpccMainThread.Queue(AFeature: TDpccFeature; const AName: string; const AProc: TThreadProcedure);
var
  mProc: TThreadProcedure;
begin
  // Wie TThread.Queue: im Hauptthread sofort, auch nach Stop (das Entladen ruft noch Code im Hauptthread).
  if IsMain then
  begin
    mProc := Guarded(AFeature, AName, AProc);
    mProc();
  end
  else
  begin
    Post(AFeature, AName, AProc, False);
  end;
end;

class procedure TDpccMainThread.ForceQueue(AFeature: TDpccFeature; const AProc: TThreadProcedure);
begin
  Post(AFeature, '', AProc, True);
end;

class procedure TDpccMainThread.ForceQueue(AFeature: TDpccFeature; const AName: string;
  const AProc: TThreadProcedure);
begin
  Post(AFeature, AName, AProc, True);
end;

class procedure TDpccMainThread.Start;
begin
  if FLock = nil then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    FStopped := False;
    if FOwner = nil then
    begin
      FOwner := TOwner.Create;
    end;
  finally
    FLock.Leave;
  end;
end;

class procedure TDpccMainThread.Stop;
var
  mOwner: TOwner;
  mDropped: TArray<TThreadProcedure>;
begin
  if FLock = nil then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    FStopped := True;
    mOwner := FOwner;
    FOwner := nil;
    // Auch Einträge, die CheckSynchronize schon aus der Warteschlange genommen hat, laufen dann leer.
    mDropped := TakePending(0);
  finally
    FLock.Leave;
  end;
  if mDropped <> nil then
  begin
    TDpccGuard.Log(Format('dpcc: dropped %d queued main thread entries on unload', [Length(mDropped)]));
  end;
  // mDropped wird erst beim Verlassen frei, außerhalb der Sperre (wie DropModule).
  if mOwner = nil then
  begin
    Exit;
  end;
  // Ab hier kommt kein Eintrag mehr dazu (Post prüft unter FLock); alle wartenden verwerfen.
  TThread.RemoveQueuedEvents(mOwner);
  mOwner.Terminate;
  // Nicht Owner.WaitFor (arbeitet im Hauptthread die Warteschlange ab) und nicht das Handle (braucht beim
  // Prozessende die Ladersperre): auf Finished warten wie TDpccTimeLimit.StopAll.
  if TDpccShutdown.WaitForThreads([TThread(mOwner)], TDpccShutdown.cStopMs) then
  begin
    mOwner.Free;
  end
  else
  begin
    TDpccGuard.Log('dpcc: Besitzer der Hauptthread-Einträge endet nicht; er gibt sich bei Rückkehr selbst frei');
    mOwner.FreeOnTerminate := True;
  end;
end;

end.
