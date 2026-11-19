unit dpcc.Core.Forms.Sync;

// Abgleich offener Formulare mit dem Server ohne spürbare Arbeit im Hauptthread (IDE hängt nicht beim Laden von
// Formularen), Teil ohne VCL und Open Tools API:
// - TDpccFormFingerprint: Größe und Hash des Binärstroms (TDpccFormText.WriteBinary). Gleicher Fingerabdruck wie
//   beim letzten Mal: nichts zu tun, weder Text noch Senden.
// - TDpccFormSyncPlan (nur Hauptthread): Reihenfolge je Formulardatei. Je Datei läuft höchstens ein Auftrag
//   (Umwandeln in Text, Senden); kommt währenddessen eine Änderung, wartet nur der neueste Stand und läuft danach genau
//   einmal. Insgesamt laufen höchstens MaxRunning Aufträge, weitere warten der Reihe nach. Ein älteres Ergebnis kann ein
//   neueres so nie überholen. Jeder Auftrag trägt die Epoche: Eine neue Sitzung (Reset) verwirft alle laufenden
//   Ergebnisse. Ein Formular, das während seines Auftrags schließt, meldet Finished zum Abmelden (didClose erst nach
//   dem letzten Senden, sonst öffnete der Auftrag die Datei beim Server wieder).
// - TickCount: Auswahl je Takt beim Abgleich aller Formulare; ein großes (oder noch nie gemessenes) nur allein.
// - TDpccModuleSources: gespeicherte Quelltexte eines Moduls aus seinem Dateinamen, ohne die Editoren des Moduls
//   (ModuleFileEditors kann einen Designer laden).

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  /// <summary>Fingerabdruck eines Binärstroms; leer (Size 0) = unbekannt.</summary>
  TDpccFormFingerprint = record
    Size: Int64;
    Hash: Integer;
    class function FromBinary(const ABinary: TBytes): TDpccFormFingerprint; static;
    function IsEmpty: Boolean;
    function SameAs(const AOther: TDpccFormFingerprint): Boolean;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Ergebnis von TDpccFormSyncPlan.Offer: unverändert, sofort starten oder wartet.</summary>
  TDpccFormOffer = (Unchanged, Start, Queued);
{$SCOPEDENUMS OFF}

  /// <summary>Auftrag für einen Hintergrund-Thread: nur Kopien, kein Verweis auf Formular oder Designer.</summary>
  TDpccFormSyncJob = record
    FileName: string;
    Binary: TBytes;
    Generation: Cardinal;
    Epoch: Cardinal;
  end;

  /// <summary>Ergebnis von TDpccFormSyncPlan.Finished.</summary>
  TDpccFormSyncDone = record
    /// <summary>Ergebnis gilt (gesendet, Epoche passt, Formular offen): als zuletzt gesendeter Text merken.</summary>
    Accepted: Boolean;
    /// <summary>Formular inzwischen geschlossen: diese Datei jetzt beim Server abmelden; sonst ''.</summary>
    CloseFile: string;
    /// <summary>Nächster Auftrag, der jetzt starten soll.</summary>
    HasNext: Boolean;
    Next: TDpccFormSyncJob;
  end;

  /// <summary>Reihenfolge der Formular-Aufträge je Datei. Nur Hauptthread.</summary>
  TDpccFormSyncPlan = class
  public const
    /// <summary>Höchstens so viele Aufträge gleichzeitig.</summary>
    cDefaultMaxRunning = 2;
  private type
    TState = record
      FileName: string;
      /// <summary>Neuester Stand (laufend oder wartend); leer nach einem Fehlschlag.</summary>
      Wanted: TDpccFormFingerprint;
      Running: Boolean;
      RunningGeneration: Cardinal;
      HasPending: Boolean;
      Pending: TBytes;
      PendingGeneration: Cardinal;
      /// <summary>Formular geschlossen, Auftrag läuft noch.</summary>
      Closing: Boolean;
    end;
  private
    FStates: TDictionary<string, TState>;
    /// <summary>Größe des letzten Binärstroms je Datei; übersteht Reset (neue Sitzung), nicht Close.</summary>
    FSizes: TDictionary<string, Int64>;
    /// <summary>Dateien mit wartendem Stand, deren Auftrag wegen MaxRunning noch nicht läuft (Reihenfolge).</summary>
    FWaiting: TList<string>;
    FRunning: Integer;
    FMaxRunning: Integer;
    FEpoch: Cardinal;
    FGeneration: Cardinal;
    /// <summary>Ersten wartenden Auftrag starten, falls Platz ist.</summary>
    function StartNext(out AJob: TDpccFormSyncJob): Boolean;
    /// <summary>AState als laufend führen und den Auftrag zu ABinary bilden.</summary>
    function Launch(var AState: TState; const ABinary: TBytes; AGeneration: Cardinal): TDpccFormSyncJob;
  public
    constructor Create(AMaxRunning: Integer = cDefaultMaxRunning);
    destructor Destroy; override;
    /// <summary>Neuer Binärstrom ABinary des Formulars AFileName. Start: AJob jetzt ausführen; Queued: läuft später
    /// (über Finished); Unchanged: gleicher Stand wie zuletzt, nichts zu tun.</summary>
    function Offer(const AFileName: string; const ABinary: TBytes; out AJob: TDpccFormSyncJob): TDpccFormOffer;
    /// <summary>Darf AJob weitermachen (Epoche passt, läuft noch, Formular offen)?</summary>
    function IsCurrent(const AJob: TDpccFormSyncJob): Boolean;
    /// <summary>AJob ist fertig (ASucceeded: Text gesendet). Veraltete Aufträge (andere Epoche) ändern nichts.
    /// </summary>
    function Finished(const AJob: TDpccFormSyncJob; ASucceeded: Boolean): TDpccFormSyncDone;
    /// <summary>Formular AFileName geschlossen. True: jetzt abmelden; False: Auftrag läuft, Finished meldet
    /// CloseFile.</summary>
    function Close(const AFileName: string): Boolean;
    /// <summary>Neue Sitzung: alles vergessen; laufende Aufträge gehören zur alten Epoche.</summary>
    procedure Reset;
    /// <summary>Größe des letzten Binärstroms von AFileName; 0 = unbekannt.</summary>
    function LastSize(const AFileName: string): Int64;
    property Running: Integer read FRunning;
    property Epoch: Cardinal read FEpoch;
    /// <summary>Schlüssel einer Datei (Großbuchstaben).</summary>
    class function Key(const AFileName: string): string; static;
    /// <summary>Groß: ab ALargeBytes oder unbekannt (ASize &lt;= 0).</summary>
    class function IsLarge(ASize, ALargeBytes: Int64): Boolean; static;
    /// <summary>Wie viele der nächsten Formulare (Größen ASizes in Reihenfolge) gehen in diesen Takt: höchstens AMax
    /// (mindestens 1), ein großes nur allein und nie hinter anderen.</summary>
    class function TickCount(const ASizes: TArray<Int64>; AMax: Integer; ALargeBytes: Int64): Integer; static;
  end;

  /// <summary>Quelltexte eines gespeicherten Moduls, nur aus seinem Dateinamen.</summary>
  TDpccModuleSources = class
  public
    /// <summary>Projekt (.dproj, .bdsproj): .dpr und .dpk daneben (welche es gibt, prüft der Empfänger über den
    /// Abgleich); Formular (.dfm, .fmx): die .pas daneben; sonst die Datei selbst. Formulardateien nicht: Ihren Stand
    /// schickt der Formular-Abgleich aus dem Designer. Leer ohne Namen.</summary>
    class function SavedSources(const AModuleFileName: string): TArray<string>; static;
  end;

implementation

uses
  System.Hash;

{ TDpccFormFingerprint }

class function TDpccFormFingerprint.FromBinary(const ABinary: TBytes): TDpccFormFingerprint;
begin
  Result.Size := Length(ABinary);
  Result.Hash := 0;
  if Result.Size > 0 then
  begin
    Result.Hash := THashBobJenkins.GetHashValue(ABinary[0], Integer(Length(ABinary)), 0);
  end;
end;

function TDpccFormFingerprint.IsEmpty: Boolean;
begin
  Result := Size = 0;
end;

function TDpccFormFingerprint.SameAs(const AOther: TDpccFormFingerprint): Boolean;
begin
  Result := (Size = AOther.Size) and (Hash = AOther.Hash);
end;

{ TDpccFormSyncPlan }

constructor TDpccFormSyncPlan.Create(AMaxRunning: Integer);
begin
  inherited Create;
  if AMaxRunning < 1 then
  begin
    AMaxRunning := 1;
  end;
  FMaxRunning := AMaxRunning;
  FStates := TDictionary<string, TState>.Create;
  FSizes := TDictionary<string, Int64>.Create;
  FWaiting := TList<string>.Create;
  FEpoch := 1;
end;

destructor TDpccFormSyncPlan.Destroy;
begin
  FWaiting.Free;
  FSizes.Free;
  FStates.Free;
  inherited;
end;

class function TDpccFormSyncPlan.Key(const AFileName: string): string;
begin
  Result := AnsiUpperCase(AFileName);
end;

function TDpccFormSyncPlan.Launch(var AState: TState; const ABinary: TBytes; AGeneration: Cardinal): TDpccFormSyncJob;
begin
  AState.Running := True;
  AState.RunningGeneration := AGeneration;
  Inc(FRunning);
  Result.FileName := AState.FileName;
  Result.Binary := ABinary;
  Result.Generation := AGeneration;
  Result.Epoch := FEpoch;
end;

function TDpccFormSyncPlan.Offer(const AFileName: string; const ABinary: TBytes;
  out AJob: TDpccFormSyncJob): TDpccFormOffer;
var
  mKey: string;
  mState: TState;
  mPrint: TDpccFormFingerprint;
begin
  AJob := Default(TDpccFormSyncJob);
  mKey := Key(AFileName);
  mPrint := TDpccFormFingerprint.FromBinary(ABinary);
  FSizes.AddOrSetValue(mKey, mPrint.Size);
  if not FStates.TryGetValue(mKey, mState) then
  begin
    mState := Default(TState);
  end;
  mState.FileName := AFileName;
  // Wieder angeboten: Das Formular ist (wieder) offen, kein Abmelden nach dem laufenden Auftrag.
  mState.Closing := False;
  if not mState.Wanted.IsEmpty and mState.Wanted.SameAs(mPrint) then
  begin
    FStates.AddOrSetValue(mKey, mState);
    Exit(TDpccFormOffer.Unchanged);
  end;
  Inc(FGeneration);
  mState.Wanted := mPrint;
  if mState.Running or (FRunning >= FMaxRunning) then
  begin
    // Nur der neueste Stand wartet; ein älterer wartender wird ersetzt.
    mState.HasPending := True;
    mState.Pending := ABinary;
    mState.PendingGeneration := FGeneration;
    if not mState.Running and not FWaiting.Contains(mKey) then
    begin
      FWaiting.Add(mKey);
    end;
    FStates.AddOrSetValue(mKey, mState);
    Exit(TDpccFormOffer.Queued);
  end;
  mState.HasPending := False;
  mState.Pending := nil;
  AJob := Launch(mState, ABinary, FGeneration);
  FStates.AddOrSetValue(mKey, mState);
  Result := TDpccFormOffer.Start;
end;

function TDpccFormSyncPlan.IsCurrent(const AJob: TDpccFormSyncJob): Boolean;
var
  mState: TState;
begin
  Result := (AJob.Epoch = FEpoch) and FStates.TryGetValue(Key(AJob.FileName), mState) and mState.Running and
    (mState.RunningGeneration = AJob.Generation) and not mState.Closing;
end;

function TDpccFormSyncPlan.Finished(const AJob: TDpccFormSyncJob; ASucceeded: Boolean): TDpccFormSyncDone;
var
  mKey: string;
  mState: TState;
begin
  Result := Default(TDpccFormSyncDone);
  // Alte Sitzung: Reset hat den Zähler schon zurückgesetzt.
  if AJob.Epoch <> FEpoch then
  begin
    Exit;
  end;
  mKey := Key(AJob.FileName);
  if not FStates.TryGetValue(mKey, mState) or not mState.Running or
    (mState.RunningGeneration <> AJob.Generation) then
  begin
    Exit;
  end;
  mState.Running := False;
  Dec(FRunning);
  if mState.Closing then
  begin
    // Erst jetzt abmelden: Das Senden des Auftrags ist vorbei.
    Result.CloseFile := mState.FileName;
    FStates.Remove(mKey);
    FSizes.Remove(mKey);
    FWaiting.Remove(mKey);
  end
  else
  begin
    Result.Accepted := ASucceeded;
    if not ASucceeded and not mState.HasPending then
    begin
      // Nicht angekommen: Der nächste Binärstrom geht neu los, auch wenn er gleich ist.
      mState.Wanted := Default(TDpccFormFingerprint);
    end;
    if mState.HasPending and not FWaiting.Contains(mKey) then
    begin
      FWaiting.Add(mKey);
    end;
    FStates.AddOrSetValue(mKey, mState);
  end;
  Result.HasNext := StartNext(Result.Next);
end;

function TDpccFormSyncPlan.StartNext(out AJob: TDpccFormSyncJob): Boolean;
var
  mKey: string;
  mState: TState;
  mBinary: TBytes;
begin
  AJob := Default(TDpccFormSyncJob);
  while (FWaiting.Count > 0) and (FRunning < FMaxRunning) do
  begin
    mKey := FWaiting[0];
    FWaiting.Delete(0);
    if FStates.TryGetValue(mKey, mState) and mState.HasPending and not mState.Running and not mState.Closing then
    begin
      mBinary := mState.Pending;
      mState.HasPending := False;
      mState.Pending := nil;
      AJob := Launch(mState, mBinary, mState.PendingGeneration);
      FStates.AddOrSetValue(mKey, mState);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDpccFormSyncPlan.Close(const AFileName: string): Boolean;
var
  mKey: string;
  mState: TState;
begin
  mKey := Key(AFileName);
  FWaiting.Remove(mKey);
  FSizes.Remove(mKey);
  if not FStates.TryGetValue(mKey, mState) then
  begin
    Exit(True);
  end;
  if not mState.Running then
  begin
    FStates.Remove(mKey);
    Exit(True);
  end;
  // Auftrag läuft: Wartendes verwerfen, abmelden erst nach seinem Ende (Finished).
  mState.Closing := True;
  mState.HasPending := False;
  mState.Pending := nil;
  FStates.AddOrSetValue(mKey, mState);
  Result := False;
end;

procedure TDpccFormSyncPlan.Reset;
begin
  Inc(FEpoch);
  FStates.Clear;
  FWaiting.Clear;
  FRunning := 0;
end;

function TDpccFormSyncPlan.LastSize(const AFileName: string): Int64;
begin
  if not FSizes.TryGetValue(Key(AFileName), Result) then
  begin
    Result := 0;
  end;
end;

class function TDpccFormSyncPlan.IsLarge(ASize, ALargeBytes: Int64): Boolean;
begin
  Result := (ASize <= 0) or (ASize >= ALargeBytes);
end;

class function TDpccFormSyncPlan.TickCount(const ASizes: TArray<Int64>; AMax: Integer; ALargeBytes: Int64): Integer;
var
  mIndex: Integer;
begin
  if AMax < 1 then
  begin
    AMax := 1;
  end;
  Result := 0;
  for mIndex := 0 to High(ASizes) do
  begin
    if Result >= AMax then
    begin
      Break;
    end;
    if IsLarge(ASizes[mIndex], ALargeBytes) then
    begin
      // Allein im Takt: als erstes nehmen, sonst im nächsten Takt.
      if Result = 0 then
      begin
        Result := 1;
      end;
      Break;
    end;
    Inc(Result);
  end;
end;

{ TDpccModuleSources }

class function TDpccModuleSources.SavedSources(const AModuleFileName: string): TArray<string>;
var
  mExt: string;
begin
  Result := nil;
  if AModuleFileName = '' then
  begin
    Exit;
  end;
  mExt := LowerCase(ExtractFileExt(AModuleFileName));
  if (mExt = '.dproj') or (mExt = '.bdsproj') then
  begin
    Result := [ChangeFileExt(AModuleFileName, '.dpr'), ChangeFileExt(AModuleFileName, '.dpk')];
  end
  else if (mExt = '.dfm') or (mExt = '.fmx') then
  begin
    Result := [ChangeFileExt(AModuleFileName, '.pas')];
  end
  else
  begin
    Result := [AModuleFileName];
  end;
end;

end.
