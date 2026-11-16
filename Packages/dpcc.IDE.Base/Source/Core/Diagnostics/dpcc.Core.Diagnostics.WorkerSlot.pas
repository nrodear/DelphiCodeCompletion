unit dpcc.Core.Diagnostics.WorkerSlot;

// Arbeiter-Threads eines Objekts und was mit überfälligen geschieht (Code-
// Review T-101). Vorher setzten acht Kopien bei überschrittener Zeitgrenze
// FreeOnTerminate und vergaßen den Thread: Endete er zwischen der Prüfung auf
// Finished und dem Setzen, blieb das Objekt liegen, und wurde das Package
// seines Codes bei laufender IDE entladen, lief er in nicht mehr geladenem
// Code weiter.
// - TDpccWorkerSlot hält die Threads eines Objekts (FreeOnTerminate aus),
//   gibt beendete frei und wartet in Stop bis zur Zeitgrenze. Wer dann noch
//   läuft, geht an TDpccOverdueThreads, zusammen mit dem Package seines
//   Codes (im Package: HInstance).
// - TDpccOverdueThreads gibt überfällige Threads frei, sobald sie enden.
//   Wird ein Package entladen (AddModuleUnloadProc, sein Code ist dann noch
//   geladen), wartet es auf dessen überfällige Threads noch bis
//   cUnloadGraceMs; läuft dann noch einer, hält TDpccUnloadSafety das
//   Package im Speicher und bittet um einen Neustart.
// Gewartet wird auf Finished wie in TDpccShutdown.WaitForThreads.

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections;

type
  TDpccOverdueThreads = class
  public const
    /// <summary>Nachwarten beim Entladen eines Packages mit überfälligen Threads.</summary>
    cUnloadGraceMs = 3000;
  private type
    TEntry = record
      Thread: TThread;
      Module: HMODULE;
    end;
  private class var
    FLock: TCriticalSection;
    FEntries: TList<TEntry>;
    /// <summary>Beendete Threads (nur von AModule, 0 = alle) aus der Liste nehmen und freigeben.</summary>
    class procedure Prune(AModule: HMODULE); static;
    class function ThreadsOf(AModule: HMODULE): TArray<TThread>; static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>AThread (FreeOnTerminate aus) hat seine Zeitgrenze überschritten; sein Code liegt in AModule.
    /// Die Liste gibt ihn frei, sobald er endet.</summary>
    class procedure Adopt(AThread: TThread; AModule: HMODULE); static;
    /// <summary>Überfällige Threads von AModule, die noch laufen.</summary>
    class function Pending(AModule: HMODULE): Integer; static;
    /// <summary>Bis AMs auf die überfälligen Threads von AModule warten und beendete freigeben; True, wenn keiner
    /// mehr läuft. Sonst ist AModule als unsicher gekennzeichnet (TDpccUnloadSafety).</summary>
    class function Settle(AModule: HMODULE; AMs: Cardinal): Boolean; static;
  end;

  /// <summary>Hält die Arbeiter-Threads eines Objekts; Stop wartet bis zur Zeitgrenze und übergibt überfällige an
  /// TDpccOverdueThreads.</summary>
  TDpccWorkerSlot = class
  public const
    /// <summary>Für Stop: ohne Zeitgrenze warten (Threads mit eigener Zeitgrenze, die Objekte des Aufrufers
    /// roh halten).</summary>
    cWaitForever = High(Cardinal);
  private
    FModule: HMODULE;
    FThreads: TList<TThread>;
  public
    /// <summary>AModule: Package, in dem der Code der Threads liegt (im Package HInstance).</summary>
    constructor Create(AModule: HMODULE);
    /// <summary>Wie Stop(TDpccShutdown.cStopMs).</summary>
    destructor Destroy; override;
    /// <summary>AThread (angehalten erzeugt) übernehmen und starten; gibt vorher beendete frei.</summary>
    procedure Start(AThread: TThread);
    /// <summary>Schon laufenden AThread (FreeOnTerminate aus) übernehmen, etwa einen abgelösten Vorgänger; nil wird
    /// ignoriert.</summary>
    procedure Keep(AThread: TThread);
    /// <summary>Läuft noch ein Thread?</summary>
    function Busy: Boolean;
    /// <summary>Threads, auch beendete, die noch nicht freigegeben sind.</summary>
    function Count: Integer;
    /// <summary>Beendete Threads freigeben, ohne zu warten.</summary>
    procedure Prune;
    /// <summary>Bis AWaitMs auf alle warten und sie freigeben; True, wenn alle beendet waren. Überfällige gehen an
    /// TDpccOverdueThreads; der Slot ist danach leer.</summary>
    function Stop(AWaitMs: Cardinal): Boolean;
    /// <summary>AWait: Stop(TDpccShutdown.cStopMs), sonst Prune.</summary>
    procedure Release(AWait: Boolean);
  end;

implementation

uses
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Diagnostics.UnloadSafety,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit: der Grund erscheint im Hinweis von TDpccUnloadSafety.</summary>
  TWorkerSlotText = (OverdueThreads);
{$SCOPEDENUMS OFF}

const
  /// <summary>Plätze, die die Liste der Einträge gleich zu Beginn bekommt.</summary>
  cInitialEntries = 4;
  cTexts: array[TDpccLanguage, TWorkerSlotText] of string = (
    ('%d Arbeiter-Thread(s) über ihrer Zeitgrenze'),
    ('%d worker thread(s) past their time limit'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TWorkerSlotText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

/// <summary>Beim Entladen jedes Packages (AddModuleUnloadProc), solange sein Code noch geladen ist.</summary>
procedure DpccOverdueModuleUnload(AInstance: NativeInt);
begin
  if TDpccOverdueThreads.Pending(HMODULE(AInstance)) > 0 then
  begin
    TDpccOverdueThreads.Settle(HMODULE(AInstance), TDpccOverdueThreads.cUnloadGraceMs);
  end;
end;

{ TDpccOverdueThreads }

class constructor TDpccOverdueThreads.Create;
begin
  FLock := TCriticalSection.Create;
  FEntries := TList<TEntry>.Create;
  // Platz für die üblichen wenigen Einträge gleich anlegen: Wüchse die Liste erst beim ersten Adopt, bliebe der
  // Speicher bis zum Entladen belegt und der Leckmonitor der Tests zählte ihn dem ersten Test zu.
  FEntries.Capacity := cInitialEntries;
  AddModuleUnloadProc(DpccOverdueModuleUnload);
end;

class destructor TDpccOverdueThreads.Destroy;
begin
  RemoveModuleUnloadProc(DpccOverdueModuleUnload);
  Prune(0);
  // Was jetzt noch läuft, hat beim Entladen von Base DpccOverdueModuleUnload schon festgehalten; die Objekte
  // bleiben bewusst liegen (ein Freigeben beendet den Thread nicht).
  FreeAndNil(FEntries);
  FreeAndNil(FLock);
end;

class procedure TDpccOverdueThreads.Adopt(AThread: TThread; AModule: HMODULE);
var
  mEntry: TEntry;
begin
  if AThread = nil then
  begin
    Exit;
  end;
  if FLock = nil then
  begin
    // Nach dem Abbau: letzter Ausweg wie früher.
    AThread.FreeOnTerminate := True;
    Exit;
  end;
  mEntry.Thread := AThread;
  mEntry.Module := AModule;
  FLock.Enter;
  try
    FEntries.Add(mEntry);
  finally
    FLock.Leave;
  end;
  TDpccGuard.Log(Format('dpcc: worker thread %d exceeded its time limit, freed once it ends',
    [AThread.ThreadID]));
  Prune(0);
end;

class procedure TDpccOverdueThreads.Prune(AModule: HMODULE);
var
  mDone: TArray<TThread>;
  mThread: TThread;
  mIndex: Integer;
begin
  if FLock = nil then
  begin
    Exit;
  end;
  mDone := nil;
  FLock.Enter;
  try
    for mIndex := FEntries.Count - 1 downto 0 do
    begin
      if ((AModule = 0) or (FEntries[mIndex].Module = AModule)) and FEntries[mIndex].Thread.Finished then
      begin
        mDone := mDone + [FEntries[mIndex].Thread];
        FEntries.Delete(mIndex);
      end;
    end;
  finally
    FLock.Leave;
  end;
  for mThread in mDone do
  begin
    mThread.Free;
  end;
end;

class function TDpccOverdueThreads.ThreadsOf(AModule: HMODULE): TArray<TThread>;
var
  mEntry: TEntry;
begin
  Result := nil;
  if FLock = nil then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    for mEntry in FEntries do
    begin
      if mEntry.Module = AModule then
      begin
        Result := Result + [mEntry.Thread];
      end;
    end;
  finally
    FLock.Leave;
  end;
end;

class function TDpccOverdueThreads.Pending(AModule: HMODULE): Integer;
begin
  Prune(AModule);
  Result := Length(ThreadsOf(AModule));
end;

class function TDpccOverdueThreads.Settle(AModule: HMODULE; AMs: Cardinal): Boolean;
var
  mThreads: TArray<TThread>;
begin
  mThreads := ThreadsOf(AModule);
  Result := TDpccShutdown.WaitForThreads(mThreads, AMs);
  Prune(AModule);
  if not Result then
  begin
    TDpccUnloadSafety.MarkUnsafe(AModule, Format(UiText(TWorkerSlotText.OverdueThreads),
      [Length(ThreadsOf(AModule))]));
  end;
end;

{ TDpccWorkerSlot }

constructor TDpccWorkerSlot.Create(AModule: HMODULE);
begin
  inherited Create;
  FModule := AModule;
  FThreads := TList<TThread>.Create;
end;

destructor TDpccWorkerSlot.Destroy;
begin
  if FThreads <> nil then
  begin
    Stop(TDpccShutdown.cStopMs);
  end;
  FThreads.Free;
  inherited;
end;

procedure TDpccWorkerSlot.Start(AThread: TThread);
begin
  Prune;
  AThread.FreeOnTerminate := False;
  FThreads.Add(AThread);
  AThread.Start;
end;

procedure TDpccWorkerSlot.Keep(AThread: TThread);
begin
  if AThread <> nil then
  begin
    AThread.FreeOnTerminate := False;
    FThreads.Add(AThread);
  end;
end;

function TDpccWorkerSlot.Busy: Boolean;
var
  mThread: TThread;
begin
  Result := False;
  for mThread in FThreads do
  begin
    if not mThread.Finished then
    begin
      Exit(True);
    end;
  end;
end;

function TDpccWorkerSlot.Count: Integer;
begin
  Result := FThreads.Count;
end;

procedure TDpccWorkerSlot.Prune;
var
  mIndex: Integer;
begin
  for mIndex := FThreads.Count - 1 downto 0 do
  begin
    if FThreads[mIndex].Finished then
    begin
      FThreads[mIndex].Free;
      FThreads.Delete(mIndex);
    end;
  end;
end;

function TDpccWorkerSlot.Stop(AWaitMs: Cardinal): Boolean;
var
  mThreads: TArray<TThread>;
  mThread: TThread;
begin
  // Kein Terminate: Ein Thread, der noch nicht angelaufen ist, übersprünge sonst Execute ganz. Abbrechen ist
  // Sache des Aufrufers (Abbruchsignal, Transport).
  mThreads := FThreads.ToArray;
  FThreads.Clear;
  Result := TDpccShutdown.WaitForThreads(mThreads, AWaitMs);
  for mThread in mThreads do
  begin
    if mThread.Finished then
    begin
      mThread.Free;
    end
    else
    begin
      TDpccOverdueThreads.Adopt(mThread, FModule);
    end;
  end;
end;

procedure TDpccWorkerSlot.Release(AWait: Boolean);
begin
  if AWait then
  begin
    Stop(TDpccShutdown.cStopMs);
  end
  else
  begin
    Prune;
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Diagnostics.WorkerSlot', cTexts[TDpccLanguage.German],
    cTexts[TDpccLanguage.English]);

end.
