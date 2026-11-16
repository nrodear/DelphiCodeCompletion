unit dpcc.Core.Settings.StoreValues;

// Werte der Plugin-Einstellungen nach Schlüssel (#1455): IDpccSettingsValues
// über einen Speicher mit den Werten von TDpccPluginSettings. Die Optionsseite
// gibt damit den Abschnitten der Module (IDpccSettingsSection) die Werte, die
// noch im zentralen Record stehen: Schlüssel (x-key) und Art kommen aus dem
// Katalog, der Wert steht unter dem Registry-Namen im Speicher. Wahrheitswerte
// stehen dort als Zahl 0/1 (wie TDpccPluginSettings.Save), Listen und
// Objekte (issues.connections …) als JSON-Text: ReadString und WriteString
// gelten für Text und JSON.

interface

uses
  System.SysUtils,
  dpcc.Core.Settings.Contract,
  dpcc.Core.Settings.Catalog,
  dpcc.Core.Settings.History;

type
  TDpccSettingsStoreValues = class(TInterfacedObject, IDpccSettingsValues)
  private
    FCatalog: TDpccSettingsCatalog;
    FStore: IDpccMemorySettingsStore;
    FDefaults: IDpccMemorySettingsStore;
    /// <summary>Registry-Name zu AKey in der Art AKind; sonst EDpccSettingsKey.</summary>
    function NameOf(const AKey: string; AKind: TDpccSettingKind): string;
    /// <summary>Wie NameOf für Text: Text oder JSON (als Text gespeichert).</summary>
    function TextNameOf(const AKey: string): string;
  public
    /// <summary>ACatalog gehört weiter dem Aufrufer und muss länger leben. ADefaults: Speicher mit den Vorgaben
    /// (Reset).</summary>
    constructor Create(ACatalog: TDpccSettingsCatalog; const AStore, ADefaults: IDpccMemorySettingsStore);
    function Contains(const AKey: string): Boolean;
    function ReadBoolean(const AKey: string): Boolean;
    function ReadInteger(const AKey: string): Integer;
    function ReadString(const AKey: string): string;
    procedure WriteBoolean(const AKey: string; AValue: Boolean);
    procedure WriteInteger(const AKey: string; AValue: Integer);
    procedure WriteString(const AKey, AValue: string);
    procedure Reset(const AKey: string);
    function StoredKeys: TArray<string>;
    /// <summary>Registry-Name zu AKey (Plugin-Einstellung); '' ohne.</summary>
    class function PluginName(ACatalog: TDpccSettingsCatalog; const AKey: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  dpcc.Core.Settings.Plugin;

constructor TDpccSettingsStoreValues.Create(ACatalog: TDpccSettingsCatalog;
  const AStore, ADefaults: IDpccMemorySettingsStore);
begin
  inherited Create;
  FCatalog := ACatalog;
  FStore := AStore;
  FDefaults := ADefaults;
end;

class function TDpccSettingsStoreValues.PluginName(ACatalog: TDpccSettingsCatalog; const AKey: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := ACatalog.IndexOfKey(AKey);
  if (mIndex >= 0) and (ACatalog[mIndex].Source = asPlugin) then
  begin
    Result := ACatalog[mIndex].Name;
  end;
end;

function TDpccSettingsStoreValues.NameOf(const AKey: string; AKind: TDpccSettingKind): string;
var
  mIndex: Integer;
begin
  mIndex := FCatalog.IndexOfKey(AKey);
  if (mIndex < 0) or (FCatalog[mIndex].Source <> asPlugin) then
  begin
    raise EDpccSettingsKey.CreateFmt('Einstellung %s ist keine Plugin-Einstellung', [AKey]);
  end;
  if FCatalog[mIndex].Kind <> AKind then
  begin
    raise EDpccSettingsKey.CreateFmt('Einstellung %s hat eine andere Art', [AKey]);
  end;
  Result := FCatalog[mIndex].Name;
end;

function TDpccSettingsStoreValues.TextNameOf(const AKey: string): string;
var
  mIndex: Integer;
begin
  mIndex := FCatalog.IndexOfKey(AKey);
  if (mIndex >= 0) and (FCatalog[mIndex].Kind = akJson) then
  begin
    Exit(NameOf(AKey, akJson));
  end;
  Result := NameOf(AKey, akString);
end;

function TDpccSettingsStoreValues.Contains(const AKey: string): Boolean;
var
  mName: string;
begin
  mName := PluginName(FCatalog, AKey);
  Result := (mName <> '') and (FStore as IDpccSettingsNames).Contains(mName);
end;

function TDpccSettingsStoreValues.ReadBoolean(const AKey: string): Boolean;
var
  mName: string;
begin
  mName := NameOf(AKey, akBoolean);
  Result := FStore.ReadInteger(mName, FDefaults.ReadInteger(mName, 0)) <> 0;
end;

function TDpccSettingsStoreValues.ReadInteger(const AKey: string): Integer;
var
  mName: string;
begin
  mName := NameOf(AKey, akInteger);
  Result := FStore.ReadInteger(mName, FDefaults.ReadInteger(mName, 0));
end;

function TDpccSettingsStoreValues.ReadString(const AKey: string): string;
var
  mName: string;
begin
  mName := TextNameOf(AKey);
  Result := FStore.ReadString(mName, FDefaults.ReadString(mName, ''));
end;

procedure TDpccSettingsStoreValues.WriteBoolean(const AKey: string; AValue: Boolean);
begin
  if AValue then
  begin
    FStore.WriteInteger(NameOf(AKey, akBoolean), 1);
  end
  else
  begin
    FStore.WriteInteger(NameOf(AKey, akBoolean), 0);
  end;
end;

procedure TDpccSettingsStoreValues.WriteInteger(const AKey: string; AValue: Integer);
begin
  FStore.WriteInteger(NameOf(AKey, akInteger), AValue);
end;

procedure TDpccSettingsStoreValues.WriteString(const AKey, AValue: string);
begin
  FStore.WriteString(TextNameOf(AKey), AValue);
end;

procedure TDpccSettingsStoreValues.Reset(const AKey: string);
var
  mName: string;
begin
  mName := PluginName(FCatalog, AKey);
  if mName = '' then
  begin
    raise EDpccSettingsKey.CreateFmt('Einstellung %s ist keine Plugin-Einstellung', [AKey]);
  end;
  if FDefaults.HasInteger(mName) then
  begin
    FStore.WriteInteger(mName, FDefaults.ReadInteger(mName, 0));
  end
  else
  begin
    FStore.WriteString(mName, FDefaults.ReadString(mName, ''));
  end;
end;

function TDpccSettingsStoreValues.StoredKeys: TArray<string>;
var
  mName: string;
  mIndex: Integer;
  mKeys: TList<string>;
begin
  mKeys := TList<string>.Create;
  try
    for mName in FStore.Names do
    begin
      mIndex := FCatalog.IndexOfName(mName);
      if mIndex >= 0 then
      begin
        mKeys.Add(FCatalog[mIndex].Key);
      end;
    end;
    mKeys.Sort(TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareStr(ALeft, ARight);
      end));
    Result := mKeys.ToArray;
  finally
    mKeys.Free;
  end;
end;

end.
