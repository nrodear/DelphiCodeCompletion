unit dpcc.Core.Modules.Registry;

// Modul-Registry von Base (#1455, Regeln 1–5, 8, 9):
// - DpccModuleRegistry besteht ab der Unit-Initialisierung (verzögert
//   erzeugt); nach dem Abbau in der Finalisierung liefert es nil, damit Module
//   sich in ihrer Finalisierung nur abmelden, solange Base läuft (Regel 5).
// - Die Modulliste entsteht nur aus Anmeldungen (Regel 9). Jedes Modul, das
//   sich einmal angemeldet hat, bleibt mit Id, Name und Version bekannt und
//   steht unter „$modules.known“ in der Ablage der Einstellungen, sobald Base
//   sie mit UseStorage setzt.
// - Abmelden stoppt ein aktives Modul und löst seinen Scope rückwärts; ein
//   Fehler hält den Abbau nicht an (wie TDpccFeatureTable.StopAll, #886).
//   Zuerst ruft es OnModuleClosing mit Info.Handle (die Komposition verbindet
//   es mit TDpccMainThread.CloseModule: wartende Einträge des Moduls liefen
//   sonst nach dem Entladen seines Packages in nicht mehr geladenem Code),
//   Anmelden ruft OnModuleOpened. Als Haken, damit Core.Modules nicht von
//   Core.Diagnostics abhängt (sonst ein Feature-Zyklus).
// - Objekte nach Interface-GUID (Provide/FindAll); die Registry versteht
//   nicht, was dahinter steckt.
// - Änderungsmeldung außerhalb der Sperre; ein gelöster Hörer wird auch
//   mitten in einer Meldung nicht mehr gerufen (Regel 3). Wirft ein Hörer,
//   erfahren die übrigen die Änderung trotzdem; danach meldet die Registry den
//   Fehler (EDpccModuleRegistry), beim Abmelden im Ergebnis.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  dpcc.Core.Modules.Contract,
  dpcc.Core.Modules.Registration,
  dpcc.Core.Settings.Contract;

const
  /// <summary>Name der Liste bekannter Module in der Ablage der Einstellungen.</summary>
  cDpccKnownModulesName = '$modules.known';

type
  /// <summary>Liste bekannter Module als Text: je Modul eine Zeile „Id Tab Name Tab Version“. Tabulatoren und
  /// Zeilenumbrüche in den Angaben werden zu Leerzeichen.</summary>
  TDpccKnownModulesText = class
  public
    class function Encode(const AModules: TArray<TDpccModuleInfo>): string; static;
    /// <summary>Zeilen ohne Id und doppelte Ids werden übergangen; Handle ist immer 0.</summary>
    class function Decode(const AText: string): TArray<TDpccModuleInfo>; static;
  end;

  TDpccModuleRegistry = class(TInterfacedObject, IDpccModuleRegistry)
  private type
    TModuleEntry = record
      Module: IDpccModule;
      Info: TDpccModuleInfo;
      Scope: TObject;
      ScopeRef: IDpccModuleScope;
    end;

    TProvision = record
      IID: TGUID;
      Instance: IInterface;
      OwnerId: string;
      Item: TDpccRegistration;
      Ref: IDpccRegistration;
    end;

    TListenerEntry = record
      Listener: IDpccRegistryListener;
      OwnerId: string;
      Item: TDpccRegistration;
      Ref: IDpccRegistration;
    end;
  private
    FLock: TCriticalSection;
    FModules: TList<TModuleEntry>;
    FProvisions: TList<TProvision>;
    FListeners: TList<TListenerEntry>;
    FKnown: TList<TDpccModuleInfo>;
    FStorage: IDpccSettingsStorage;
    FShutDown: Boolean;
    function IndexOfModule(const AModuleId: string): Integer;
    function IndexOfKnown(const AModuleId: string): Integer;
    procedure RememberModule(const AInfo: TDpccModuleInfo);
    procedure SaveKnown;
    function Notify(AKind: TDpccRegistryChangeKind; const AModuleId: string; const AIID: TGUID): TArray<string>;
    function NotifyModule(AKind: TDpccRegistryChangeKind; const AModuleId: string): TArray<string>;
    function AddProvision(const AOwnerId: string; const AIID: TGUID; const AObject: IInterface): IDpccRegistration;
    function AddListener(const AOwnerId: string; const AListener: IDpccRegistryListener): IDpccRegistration;
    procedure RemoveProvision(AItem: TDpccRegistration);
    procedure RemoveListener(AItem: TDpccRegistration);
    class procedure RaiseFailures(const AFailures: TArray<string>); static;
  public
    constructor Create;
    destructor Destroy; override;
    function RegisterModule(const AModule: IDpccModule): IDpccModuleScope;
    function UnregisterModule(const AModuleId: string): TArray<string>;
    function Modules: TArray<IDpccModule>;
    function FindModule(const AModuleId: string; out AModule: IDpccModule): Boolean;
    function Known: TArray<TDpccKnownModule>;
    function ForgetModule(const AModuleId: string): Boolean;
    function IsModuleHandle(AHandle: NativeUInt): Boolean;
    function Provide(const AIID: TGUID; const AObject: IInterface): IDpccRegistration;
    function FindAll(const AIID: TGUID): TArray<IInterface>;
    function Provisions(const AIID: TGUID): TArray<TDpccProvided>;
    function Subscribe(const AListener: IDpccRegistryListener): IDpccRegistration;
    /// <summary>Ablage der Einstellungen setzen (Base beim Laden): Die dort gespeicherte Liste bekannter Module
    /// kommt zuerst, bisher bekannte, die dort fehlen, folgen; das Ergebnis wird zurückgeschrieben.</summary>
    procedure UseStorage(const AStorage: IDpccSettingsStorage);
    /// <summary>Alle Module rückwärts abmelden und keine neuen mehr annehmen (Finalisierung von Base, Regel 5).
    /// Ergebnis wie UnregisterModule, über alle Module.</summary>
    function ShutDown: TArray<string>;
  public class var
    /// <summary>Vor dem Stopp eines abmeldenden Moduls, mit dessen Info.Handle (auch 0); vor jedem Anmelden
    /// von Modulen gesetzt (Initialisierung der Komposition).</summary>
    OnModuleClosing: TProc<NativeUInt>;
    /// <summary>Nach dem Anmelden eines Moduls, mit dessen Info.Handle (auch 0).</summary>
    OnModuleOpened: TProc<NativeUInt>;
  end;

/// <summary>Die Registry von Base; nil nach dem Abbau in der Finalisierung (Regel 5).</summary>
function DpccModuleRegistry: IDpccModuleRegistry;
/// <summary>Dieselbe Registry für Base selbst (UseStorage); nil nach dem Abbau.</summary>
function DpccModuleRegistryInstance: TDpccModuleRegistry;

implementation

uses
  dpcc.Text.LogMarks;

type
  TDpccModuleScope = class(TInterfacedObject, IDpccModuleScope)
  private
    FLock: TCriticalSection;
    FRegistry: TDpccModuleRegistry;
    FModuleId: string;
    FOpen: Boolean;
    FOwned: TList<IDpccRegistration>;
    function Registry: TDpccModuleRegistry;
  public
    constructor Create(ARegistry: TDpccModuleRegistry; const AModuleId: string);
    destructor Destroy; override;
    function ModuleId: string;
    function IsOpen: Boolean;
    procedure Own(const ARegistration: IDpccRegistration);
    function Provide(const AIID: TGUID; const AObject: IInterface): IDpccRegistration;
    function Subscribe(const AListener: IDpccRegistryListener): IDpccRegistration;
    /// <summary>Schließen und jede Anmeldung rückwärts lösen; Ergebnis: fehlgeschlagene als „Klasse:
    /// Meldung“.</summary>
    function Close: TArray<string>;
    /// <summary>Registry abgebaut: schließen, ohne die Anmeldungen zu lösen (sie sind schon abgetrennt).</summary>
    procedure Detach;
  end;

  TDpccProvisionRegistration = class(TDpccRegistration)
  private
    FRegistry: TDpccModuleRegistry;
  protected
    procedure DoRevoke; override;
  public
    constructor Create(ARegistry: TDpccModuleRegistry);
  end;

  TDpccListenerRegistration = class(TDpccRegistration)
  private
    FRegistry: TDpccModuleRegistry;
  protected
    procedure DoRevoke; override;
  public
    constructor Create(ARegistry: TDpccModuleRegistry);
  end;

const
  cNoIID: TGUID = '{00000000-0000-0000-0000-000000000000}';

var
  GRegistry: IDpccModuleRegistry;
  GRegistryInstance: TDpccModuleRegistry;
  GTornDown: Boolean;

function DpccModuleRegistry: IDpccModuleRegistry;
begin
  if (GRegistry = nil) and not GTornDown then
  begin
    GRegistryInstance := TDpccModuleRegistry.Create;
    GRegistry := GRegistryInstance;
  end;
  Result := GRegistry;
end;

function DpccModuleRegistryInstance: TDpccModuleRegistry;
begin
  DpccModuleRegistry;
  Result := GRegistryInstance;
end;

function FailureOf(const AStep: string; AError: Exception): string;
begin
  Result := AStep + ': ' + AError.ClassName + ': ' + TLogMarks.Text(AError.Message);
end;

procedure AppendFailures(var AList: TArray<string>; const AMore: TArray<string>);
var
  mItem: string;
begin
  for mItem in AMore do
  begin
    AList := AList + [mItem];
  end;
end;

function CleanField(const AText: string): string;
begin
  Result := StringReplace(AText, #9, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
end;

{ TDpccKnownModulesText }

class function TDpccKnownModulesText.Encode(const AModules: TArray<TDpccModuleInfo>): string;
var
  mInfo: TDpccModuleInfo;
begin
  Result := '';
  for mInfo in AModules do
  begin
    if Result <> '' then
    begin
      Result := Result + #10;
    end;
    Result := Result + CleanField(mInfo.Id) + #9 + CleanField(mInfo.Name) + #9 + CleanField(mInfo.Version);
  end;
end;

class function TDpccKnownModulesText.Decode(const AText: string): TArray<TDpccModuleInfo>;
var
  mLines: TArray<string>;
  mFields: TArray<string>;
  mLine: string;
  mInfo: TDpccModuleInfo;
  mSeen: TList<string>;
begin
  Result := nil;
  mLines := StringReplace(AText, #13, '', [rfReplaceAll]).Split([#10]);
  mSeen := TList<string>.Create;
  try
    for mLine in mLines do
    begin
      mFields := mLine.Split([#9]);
      if (Length(mFields) = 0) or (Trim(mFields[0]) = '') or mSeen.Contains(Trim(mFields[0])) then
      begin
        Continue;
      end;
      mInfo := Default(TDpccModuleInfo);
      mInfo.Id := Trim(mFields[0]);
      if Length(mFields) > 1 then
      begin
        mInfo.Name := mFields[1];
      end;
      if Length(mFields) > 2 then
      begin
        mInfo.Version := mFields[2];
      end;
      mSeen.Add(mInfo.Id);
      Result := Result + [mInfo];
    end;
  finally
    mSeen.Free;
  end;
end;

{ TDpccModuleScope }

constructor TDpccModuleScope.Create(ARegistry: TDpccModuleRegistry; const AModuleId: string);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FRegistry := ARegistry;
  FModuleId := AModuleId;
  FOpen := True;
  FOwned := TList<IDpccRegistration>.Create;
end;

destructor TDpccModuleScope.Destroy;
begin
  FOwned.Free;
  FLock.Free;
  inherited;
end;

function TDpccModuleScope.Registry: TDpccModuleRegistry;
begin
  FLock.Acquire;
  try
    if not FOpen then
    begin
      raise EDpccModuleRegistry.CreateFmt('Modul %s ist abgemeldet; es kann nichts mehr anmelden', [FModuleId]);
    end;
    Result := FRegistry;
  finally
    FLock.Release;
  end;
end;

function TDpccModuleScope.ModuleId: string;
begin
  Result := FModuleId;
end;

function TDpccModuleScope.IsOpen: Boolean;
begin
  FLock.Acquire;
  try
    Result := FOpen;
  finally
    FLock.Release;
  end;
end;

procedure TDpccModuleScope.Own(const ARegistration: IDpccRegistration);
var
  mOpen: Boolean;
  mIndex: Integer;
begin
  if ARegistration = nil then
  begin
    Exit;
  end;
  FLock.Acquire;
  try
    mOpen := FOpen;
    if mOpen then
    begin
      // Schon gelöste Anmeldungen (etwa gelieferte Antworten) fallen weg, damit die Liste nicht wächst.
      for mIndex := FOwned.Count - 1 downto 0 do
      begin
        if FOwned[mIndex].IsRevoked then
        begin
          FOwned.Delete(mIndex);
        end;
      end;
      FOwned.Add(ARegistration);
    end;
  finally
    FLock.Release;
  end;
  if not mOpen then
  begin
    ARegistration.Revoke;
  end;
end;

function TDpccModuleScope.Provide(const AIID: TGUID; const AObject: IInterface): IDpccRegistration;
begin
  Result := Registry.AddProvision(FModuleId, AIID, AObject);
  Own(Result);
end;

function TDpccModuleScope.Subscribe(const AListener: IDpccRegistryListener): IDpccRegistration;
begin
  Result := Registry.AddListener(FModuleId, AListener);
  Own(Result);
end;

function TDpccModuleScope.Close: TArray<string>;
var
  mOwned: TArray<IDpccRegistration>;
  mIndex: Integer;
begin
  Result := nil;
  FLock.Acquire;
  try
    FOpen := False;
    mOwned := FOwned.ToArray;
    FOwned.Clear;
  finally
    FLock.Release;
  end;
  for mIndex := High(mOwned) downto 0 do
  begin
    try
      mOwned[mIndex].Revoke;
    except
      on mError: Exception do
        Result := Result + [FailureOf(FModuleId + ' Anmeldung ' + IntToStr(mIndex + 1), mError)];
    end;
  end;
end;

procedure TDpccModuleScope.Detach;
begin
  FLock.Acquire;
  try
    FOpen := False;
    FOwned.Clear;
    FRegistry := nil;
  finally
    FLock.Release;
  end;
end;

{ TDpccProvisionRegistration }

constructor TDpccProvisionRegistration.Create(ARegistry: TDpccModuleRegistry);
begin
  inherited Create;
  FRegistry := ARegistry;
end;

procedure TDpccProvisionRegistration.DoRevoke;
begin
  FRegistry.RemoveProvision(Self);
end;

{ TDpccListenerRegistration }

constructor TDpccListenerRegistration.Create(ARegistry: TDpccModuleRegistry);
begin
  inherited Create;
  FRegistry := ARegistry;
end;

procedure TDpccListenerRegistration.DoRevoke;
begin
  FRegistry.RemoveListener(Self);
end;

{ TDpccModuleRegistry }

constructor TDpccModuleRegistry.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FModules := TList<TModuleEntry>.Create;
  FProvisions := TList<TProvision>.Create;
  FListeners := TList<TListenerEntry>.Create;
  FKnown := TList<TDpccModuleInfo>.Create;
end;

destructor TDpccModuleRegistry.Destroy;
var
  mModule: TModuleEntry;
  mProvision: TProvision;
  mListener: TListenerEntry;
begin
  // Was noch angemeldet ist, verweist auf diese Registry: abtrennen, damit ein späteres Revoke ins Leere geht.
  for mModule in FModules do
  begin
    TDpccModuleScope(mModule.Scope).Detach;
  end;
  for mProvision in FProvisions do
  begin
    mProvision.Item.Detach;
  end;
  for mListener in FListeners do
  begin
    mListener.Item.Detach;
  end;
  FKnown.Free;
  FListeners.Free;
  FProvisions.Free;
  FModules.Free;
  FLock.Free;
  inherited;
end;

class procedure TDpccModuleRegistry.RaiseFailures(const AFailures: TArray<string>);
begin
  if Length(AFailures) > 0 then
  begin
    raise EDpccModuleRegistry.Create(string.Join(sLineBreak, AFailures));
  end;
end;

function TDpccModuleRegistry.IndexOfModule(const AModuleId: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to FModules.Count - 1 do
  begin
    if SameText(FModules[mIndex].Info.Id, AModuleId) then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TDpccModuleRegistry.IndexOfKnown(const AModuleId: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to FKnown.Count - 1 do
  begin
    if SameText(FKnown[mIndex].Id, AModuleId) then
    begin
      Exit(mIndex);
    end;
  end;
end;

procedure TDpccModuleRegistry.RememberModule(const AInfo: TDpccModuleInfo);
var
  mInfo: TDpccModuleInfo;
  mIndex: Integer;
begin
  mInfo := AInfo;
  mInfo.Handle := 0;
  mIndex := IndexOfKnown(AInfo.Id);
  if mIndex < 0 then
  begin
    FKnown.Add(mInfo);
  end
  else
  begin
    FKnown[mIndex] := mInfo;
  end;
  SaveKnown;
end;

procedure TDpccModuleRegistry.SaveKnown;
begin
  if FStorage <> nil then
  begin
    FStorage.WriteText(cDpccKnownModulesName, TDpccKnownModulesText.Encode(FKnown.ToArray));
  end;
end;

function TDpccModuleRegistry.Notify(AKind: TDpccRegistryChangeKind; const AModuleId: string;
  const AIID: TGUID): TArray<string>;
var
  mListeners: TArray<TListenerEntry>;
  mListener: TListenerEntry;
  mChange: TDpccRegistryChange;
begin
  Result := nil;
  FLock.Acquire;
  try
    mListeners := FListeners.ToArray;
  finally
    FLock.Release;
  end;
  mChange.Kind := AKind;
  mChange.ModuleId := AModuleId;
  mChange.IID := AIID;
  for mListener in mListeners do
  begin
    // Ein früherer Hörer kann diesen gelöst haben (Regel 3).
    if mListener.Item.IsRevoked then
    begin
      Continue;
    end;
    try
      mListener.Listener.RegistryChanged(mChange);
    except
      on mError: Exception do
        Result := Result + [FailureOf('Hörer von ' + mListener.OwnerId, mError)];
    end;
  end;
end;

function TDpccModuleRegistry.NotifyModule(AKind: TDpccRegistryChangeKind; const AModuleId: string): TArray<string>;
begin
  Result := Notify(AKind, AModuleId, cNoIID);
end;

function TDpccModuleRegistry.RegisterModule(const AModule: IDpccModule): IDpccModuleScope;
var
  mEntry: TModuleEntry;
  mScope: TDpccModuleScope;
begin
  if AModule = nil then
  begin
    raise EDpccModuleRegistry.Create('Kein Modul angegeben');
  end;
  mEntry.Module := AModule;
  mEntry.Info := AModule.Info;
  mEntry.Info.Id := Trim(mEntry.Info.Id);
  if mEntry.Info.Id = '' then
  begin
    raise EDpccModuleRegistry.Create('Modul ohne Id');
  end;
  FLock.Acquire;
  try
    if FShutDown then
    begin
      raise EDpccModuleRegistry.CreateFmt('Base ist abgebaut; Modul %s wird nicht angemeldet', [mEntry.Info.Id]);
    end;
    if IndexOfModule(mEntry.Info.Id) >= 0 then
    begin
      raise EDpccModuleRegistry.CreateFmt('Modul %s ist schon angemeldet', [mEntry.Info.Id]);
    end;
    mScope := TDpccModuleScope.Create(Self, mEntry.Info.Id);
    mEntry.Scope := mScope;
    mEntry.ScopeRef := mScope;
    FModules.Add(mEntry);
    RememberModule(mEntry.Info);
  finally
    FLock.Release;
  end;
  Result := mEntry.ScopeRef;
  if Assigned(OnModuleOpened) then
  begin
    OnModuleOpened(mEntry.Info.Handle);
  end;
  RaiseFailures(NotifyModule(rcModuleAdded, mEntry.Info.Id));
end;

function TDpccModuleRegistry.UnregisterModule(const AModuleId: string): TArray<string>;
var
  mIndex: Integer;
  mEntry: TModuleEntry;
begin
  Result := nil;
  FLock.Acquire;
  try
    mIndex := IndexOfModule(AModuleId);
    if mIndex < 0 then
    begin
      Exit;
    end;
    mEntry := FModules[mIndex];
    FModules.Delete(mIndex);
  finally
    FLock.Release;
  end;
  // Was jetzt noch für das Modul wartet oder eingereiht wird, liefe nach dem Entladen seines Packages.
  if Assigned(OnModuleClosing) then
  begin
    OnModuleClosing(mEntry.Info.Handle);
  end;
  // Erst stoppen, dann die Anmeldungen lösen: Stop darf noch auf eigene Anmeldungen zugreifen.
  try
    if mEntry.Module.IsActive then
    begin
      mEntry.Module.Stop;
    end;
  except
    on mError: Exception do
      Result := Result + [FailureOf(mEntry.Info.Id + ' Stop', mError)];
  end;
  AppendFailures(Result, TDpccModuleScope(mEntry.Scope).Close);
  AppendFailures(Result, NotifyModule(rcModuleRemoved, mEntry.Info.Id));
end;

function TDpccModuleRegistry.Modules: TArray<IDpccModule>;
var
  mEntry: TModuleEntry;
begin
  Result := nil;
  FLock.Acquire;
  try
    for mEntry in FModules do
    begin
      Result := Result + [mEntry.Module];
    end;
  finally
    FLock.Release;
  end;
end;

function TDpccModuleRegistry.FindModule(const AModuleId: string; out AModule: IDpccModule): Boolean;
var
  mIndex: Integer;
begin
  AModule := nil;
  FLock.Acquire;
  try
    mIndex := IndexOfModule(AModuleId);
    Result := mIndex >= 0;
    if Result then
    begin
      AModule := FModules[mIndex].Module;
    end;
  finally
    FLock.Release;
  end;
end;

function TDpccModuleRegistry.Known: TArray<TDpccKnownModule>;
var
  mIndex: Integer;
  mModule: Integer;
  mKnown: TDpccKnownModule;
begin
  Result := nil;
  FLock.Acquire;
  try
    SetLength(Result, FKnown.Count);
    for mIndex := 0 to FKnown.Count - 1 do
    begin
      mModule := IndexOfModule(FKnown[mIndex].Id);
      mKnown.Installed := mModule >= 0;
      if mKnown.Installed then
      begin
        mKnown.Info := FModules[mModule].Info;
      end
      else
      begin
        mKnown.Info := FKnown[mIndex];
      end;
      Result[mIndex] := mKnown;
    end;
  finally
    FLock.Release;
  end;
end;

function TDpccModuleRegistry.ForgetModule(const AModuleId: string): Boolean;
var
  mIndex: Integer;
begin
  FLock.Acquire;
  try
    mIndex := IndexOfKnown(AModuleId);
    Result := (mIndex >= 0) and (IndexOfModule(AModuleId) < 0);
    if Result then
    begin
      FKnown.Delete(mIndex);
      SaveKnown;
    end;
  finally
    FLock.Release;
  end;
  if Result then
  begin
    RaiseFailures(NotifyModule(rcKnownChanged, AModuleId));
  end;
end;

function TDpccModuleRegistry.IsModuleHandle(AHandle: NativeUInt): Boolean;
var
  mEntry: TModuleEntry;
begin
  Result := False;
  if AHandle = 0 then
  begin
    Exit;
  end;
  FLock.Acquire;
  try
    for mEntry in FModules do
    begin
      if mEntry.Info.Handle = AHandle then
      begin
        Exit(True);
      end;
    end;
  finally
    FLock.Release;
  end;
end;

function TDpccModuleRegistry.AddProvision(const AOwnerId: string; const AIID: TGUID;
  const AObject: IInterface): IDpccRegistration;
var
  mProvision: TProvision;
  mItem: TDpccProvisionRegistration;
begin
  if (AObject = nil) or not Supports(AObject, AIID) then
  begin
    raise EDpccModuleRegistry.CreateFmt('Objekt unterstützt %s nicht', [GUIDToString(AIID)]);
  end;
  mItem := TDpccProvisionRegistration.Create(Self);
  mProvision.IID := AIID;
  mProvision.Instance := AObject;
  mProvision.OwnerId := AOwnerId;
  mProvision.Item := mItem;
  mProvision.Ref := mItem;
  FLock.Acquire;
  try
    FProvisions.Add(mProvision);
  finally
    FLock.Release;
  end;
  Result := mProvision.Ref;
  RaiseFailures(Notify(rcProvided, AOwnerId, AIID));
end;

function TDpccModuleRegistry.AddListener(const AOwnerId: string;
  const AListener: IDpccRegistryListener): IDpccRegistration;
var
  mEntry: TListenerEntry;
  mItem: TDpccListenerRegistration;
begin
  if AListener = nil then
  begin
    raise EDpccModuleRegistry.Create('Kein Hörer angegeben');
  end;
  mItem := TDpccListenerRegistration.Create(Self);
  mEntry.Listener := AListener;
  mEntry.OwnerId := AOwnerId;
  mEntry.Item := mItem;
  mEntry.Ref := mItem;
  FLock.Acquire;
  try
    FListeners.Add(mEntry);
  finally
    FLock.Release;
  end;
  Result := mEntry.Ref;
end;

procedure TDpccModuleRegistry.RemoveProvision(AItem: TDpccRegistration);
var
  mIndex: Integer;
  mProvision: TProvision;
  mFound: Boolean;
begin
  mFound := False;
  FLock.Acquire;
  try
    for mIndex := 0 to FProvisions.Count - 1 do
    begin
      if FProvisions[mIndex].Item = AItem then
      begin
        mProvision := FProvisions[mIndex];
        FProvisions.Delete(mIndex);
        mFound := True;
        Break;
      end;
    end;
  finally
    FLock.Release;
  end;
  if mFound then
  begin
    RaiseFailures(Notify(rcRevoked, mProvision.OwnerId, mProvision.IID));
  end;
end;

procedure TDpccModuleRegistry.RemoveListener(AItem: TDpccRegistration);
var
  mIndex: Integer;
begin
  // Wer Revoke ruft, hält selbst eine Referenz: AItem lebt über das Löschen hinaus.
  FLock.Acquire;
  try
    for mIndex := 0 to FListeners.Count - 1 do
    begin
      if FListeners[mIndex].Item = AItem then
      begin
        FListeners.Delete(mIndex);
        Break;
      end;
    end;
  finally
    FLock.Release;
  end;
end;

function TDpccModuleRegistry.Provide(const AIID: TGUID; const AObject: IInterface): IDpccRegistration;
begin
  Result := AddProvision('', AIID, AObject);
end;

function TDpccModuleRegistry.FindAll(const AIID: TGUID): TArray<IInterface>;
var
  mProvision: TProvision;
begin
  Result := nil;
  FLock.Acquire;
  try
    for mProvision in FProvisions do
    begin
      if IsEqualGUID(mProvision.IID, AIID) then
      begin
        Result := Result + [mProvision.Instance];
      end;
    end;
  finally
    FLock.Release;
  end;
end;

function TDpccModuleRegistry.Provisions(const AIID: TGUID): TArray<TDpccProvided>;
var
  mProvision: TProvision;
  mItem: TDpccProvided;
begin
  Result := nil;
  FLock.Acquire;
  try
    for mProvision in FProvisions do
    begin
      if IsEqualGUID(mProvision.IID, AIID) then
      begin
        mItem.OwnerId := mProvision.OwnerId;
        mItem.Instance := mProvision.Instance;
        Result := Result + [mItem];
      end;
    end;
  finally
    FLock.Release;
  end;
end;

function TDpccModuleRegistry.Subscribe(const AListener: IDpccRegistryListener): IDpccRegistration;
begin
  Result := AddListener('', AListener);
end;

/// <summary>AInfo in AList ersetzen oder anhängen: Angaben eines in dieser Sitzung angemeldeten Moduls sind neuer
/// als die gespeicherten.</summary>
procedure PutKnown(AList: TList<TDpccModuleInfo>; const AInfo: TDpccModuleInfo);
var
  mIndex: Integer;
begin
  for mIndex := 0 to AList.Count - 1 do
  begin
    if SameText(AList[mIndex].Id, AInfo.Id) then
    begin
      AList[mIndex] := AInfo;
      Exit;
    end;
  end;
  AList.Add(AInfo);
end;
procedure TDpccModuleRegistry.UseStorage(const AStorage: IDpccSettingsStorage);
var
  mMerged: TList<TDpccModuleInfo>;
  mInfo: TDpccModuleInfo;
begin
  FLock.Acquire;
  try
    FStorage := AStorage;
    if FStorage = nil then
    begin
      Exit;
    end;
    mMerged := TList<TDpccModuleInfo>.Create;
    try
      mMerged.AddRange(TDpccKnownModulesText.Decode(FStorage.ReadText(cDpccKnownModulesName)));
      for mInfo in FKnown do
      begin
        PutKnown(mMerged, mInfo);
      end;
      FKnown.Clear;
      FKnown.AddRange(mMerged);
    finally
      mMerged.Free;
    end;
    SaveKnown;
  finally
    FLock.Release;
  end;
end;

function TDpccModuleRegistry.ShutDown: TArray<string>;
var
  mIds: TArray<string>;
  mEntry: TModuleEntry;
  mIndex: Integer;
begin
  Result := nil;
  FLock.Acquire;
  try
    FShutDown := True;
    mIds := nil;
    for mEntry in FModules do
    begin
      mIds := mIds + [mEntry.Info.Id];
    end;
  finally
    FLock.Release;
  end;
  for mIndex := High(mIds) downto 0 do
  begin
    AppendFailures(Result, UnregisterModule(mIds[mIndex]));
  end;
end;

initialization
  DpccModuleRegistry;

finalization
  // Regel 5: zuerst alle Module stoppen und abmelden, dann die Registry abbauen. Base ruft ShutDown mit der
  // Verdrahtung (#1456) schon vorher und protokolliert die Fehler; das hier ist nur das Sicherheitsnetz für den
  // Fall, dass die Finalisierung ohne diesen Schritt erreicht wird.
  if GRegistryInstance <> nil then
  begin
    GRegistryInstance.ShutDown;
  end;
  GTornDown := True;
  GRegistryInstance := nil;
  GRegistry := nil;

end.
