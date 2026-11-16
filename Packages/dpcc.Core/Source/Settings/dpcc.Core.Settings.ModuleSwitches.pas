unit dpcc.Core.Settings.ModuleSwitches;

// Modul-Schalter (#1454), ohne VCL und ohne Open Tools API. Ein Modul ist eine
// Gruppe von Funktionen, die ab 2.0 ein eigenes Package wird:
// Debugger, Issue-Tracker, Analyse, Tests, Build-Werkzeuge, Lesezeichen,
// Designer, Prüfregeln, Suche, Willkommensseite. Sein Schalter ist eine
// boolesche Plugin-Einstellung mit "x-module": "<Kennung>" im Plugin-Katalog;
// zum Modul gehört alles, was darunter liegt (x-parent bzw. Präfixregel, wie
// die Sperren der Optionsseite in dpcc.Core.Settings.Groups).
// Ist ein Schalter aus, liefern die wirksamen Werte (TDpccIdeSettings.Current)
// für jede boolesche Einstellung des Moduls „aus“ und für eine mit x-offValue
// diesen Wert. So startet kein Teil des Moduls, und jedes laufende Teil hört
// über seine eigene Einstellung auf, ohne Neustart. Gespeichert bleiben die
// eigenen Werte (Optionsseite, Export); nach dem Wiedereinschalten gelten sie
// wieder. Zustände (x-state) und Rechnerwerte (x-machine) bleiben unberührt.

interface

uses
  System.SysUtils,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.Catalog;

type
  TDpccModuleSwitch = record
    /// <summary>Kennung aus x-module, z. B. "debug".</summary>
    Module: string;
    /// <summary>Name des Schalters in TDpccPluginSettings.Load/Save, z. B. "DebugEnabled".</summary>
    Name: string;
    /// <summary>x-key des Schalters, z. B. "debug.enabled".</summary>
    Key: string;
    Caption: string;
    CaptionEn: string;
    /// <summary>Einstellungen des Moduls mit einem Wert für „aus“ (boolesch oder x-offValue).</summary>
    Members: TArray<TDpccCatalogEntry>;
  end;

  TDpccModuleSwitches = class
  public
    /// <summary>Alle Modul-Schalter des Plugin-Katalogs in Katalogreihenfolge, mit ihren Einstellungen.</summary>
    class function Read(ACatalog: TDpccSettingsCatalog): TArray<TDpccModuleSwitch>; static;
    /// <summary>Wirksame Werte: Für jeden ausgeschalteten Modul-Schalter in ASettings bekommen die Einstellungen
    /// des Moduls ihren Wert für „aus“; sonst genau ASettings.</summary>
    class function Apply(const ASettings: TDpccPluginSettings;
      const ASwitches: TArray<TDpccModuleSwitch>): TDpccPluginSettings; static;
    /// <summary>Ist das Modul AModule in ASettings an? Unbekannte Kennung = an.</summary>
    class function IsOn(const ASettings: TDpccPluginSettings; const ASwitches: TArray<TDpccModuleSwitch>;
      const AModule: string): Boolean; static;
    /// <summary>Kennungen der ausgeschalteten Module in Katalogreihenfolge.</summary>
    class function OffModules(const ASettings: TDpccPluginSettings;
      const ASwitches: TArray<TDpccModuleSwitch>): TArray<string>; static;
    /// <summary>Kennung des Moduls, zu dem die Einstellung AName (Name oder x-key) gehört; '' = Kern.</summary>
    class function ModuleOf(const ASwitches: TArray<TDpccModuleSwitch>; const AName: string): string; static;
  end;

implementation

uses
  dpcc.Core.Settings.Groups,
  dpcc.Core.Settings.History;

function HasOffValue(const AEntry: TDpccCatalogEntry): Boolean;
begin
  Result := not AEntry.State and not AEntry.Machine and
    ((AEntry.Kind = akBoolean) or ((AEntry.Kind = akString) and (AEntry.OffJson <> '')));
end;

function Contains(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in ANames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Wert eines Schalters aus dem Speicher; ohne Eintrag an (Vorgabe der Modul-Schalter).</summary>
function SwitchOn(const AStore: IDpccMemorySettingsStore; const ASwitch: TDpccModuleSwitch): Boolean;
begin
  Result := AStore.ReadInteger(ASwitch.Name, 1) <> 0;
end;

procedure WriteOff(const AStore: IDpccMemorySettingsStore; const AEntry: TDpccCatalogEntry);
var
  mValue: string;
begin
  if AEntry.Kind = akBoolean then
  begin
    AStore.WriteInteger(AEntry.Name, 0);
  end
  else
  begin
    mValue := TDpccJsonValues.Display(AEntry.OffJson);
    AStore.WriteString(AEntry.Name, mValue);
  end;
end;

{ TDpccModuleSwitches }

class function TDpccModuleSwitches.Read(ACatalog: TDpccSettingsCatalog): TArray<TDpccModuleSwitch>;
var
  mGroups: TDpccSettingsGroups;
  mIndex, mOther: Integer;
  mSwitch: TDpccModuleSwitch;
  mEntry: TDpccCatalogEntry;
begin
  Result := nil;
  mGroups := TDpccSettingsGroups.Create(ACatalog);
  try
    for mIndex := 0 to ACatalog.Count - 1 do
    begin
      mEntry := ACatalog[mIndex];
      if (mEntry.Source <> asPlugin) or (mEntry.Module = '') or (mEntry.Kind <> akBoolean) then
      begin
        Continue;
      end;
      mSwitch := Default(TDpccModuleSwitch);
      mSwitch.Module := mEntry.Module;
      mSwitch.Name := mEntry.Name;
      mSwitch.Key := mEntry.Key;
      mSwitch.Caption := mEntry.Caption;
      mSwitch.CaptionEn := mEntry.CaptionEn;
      for mOther := 0 to ACatalog.Count - 1 do
      begin
        if (ACatalog[mOther].Source = asPlugin) and HasOffValue(ACatalog[mOther]) and
          Contains(mGroups.AncestorsOf(ACatalog[mOther].Name), mEntry.Name) then
        begin
          mSwitch.Members := mSwitch.Members + [ACatalog[mOther]];
        end;
      end;
      Result := Result + [mSwitch];
    end;
  finally
    mGroups.Free;
  end;
end;

class function TDpccModuleSwitches.Apply(const ASettings: TDpccPluginSettings;
  const ASwitches: TArray<TDpccModuleSwitch>): TDpccPluginSettings;
var
  mStore: IDpccMemorySettingsStore;
  mSwitch: TDpccModuleSwitch;
  mEntry: TDpccCatalogEntry;
  mChanged: Boolean;
begin
  Result := ASettings;
  if Length(ASwitches) = 0 then
  begin
    Exit;
  end;
  mStore := TDpccMemorySettingsStore.FromSettings(ASettings);
  mChanged := False;
  for mSwitch in ASwitches do
  begin
    if not SwitchOn(mStore, mSwitch) then
    begin
      for mEntry in mSwitch.Members do
      begin
        WriteOff(mStore, mEntry);
      end;
      mChanged := True;
    end;
  end;
  if mChanged then
  begin
    Result.Load(mStore);
  end;
end;

class function TDpccModuleSwitches.IsOn(const ASettings: TDpccPluginSettings;
  const ASwitches: TArray<TDpccModuleSwitch>; const AModule: string): Boolean;
var
  mStore: IDpccMemorySettingsStore;
  mSwitch: TDpccModuleSwitch;
begin
  Result := True;
  for mSwitch in ASwitches do
  begin
    if SameText(mSwitch.Module, AModule) then
    begin
      mStore := TDpccMemorySettingsStore.FromSettings(ASettings);
      Exit(SwitchOn(mStore, mSwitch));
    end;
  end;
end;

class function TDpccModuleSwitches.OffModules(const ASettings: TDpccPluginSettings;
  const ASwitches: TArray<TDpccModuleSwitch>): TArray<string>;
var
  mStore: IDpccMemorySettingsStore;
  mSwitch: TDpccModuleSwitch;
begin
  Result := nil;
  if Length(ASwitches) = 0 then
  begin
    Exit;
  end;
  mStore := TDpccMemorySettingsStore.FromSettings(ASettings);
  for mSwitch in ASwitches do
  begin
    if not SwitchOn(mStore, mSwitch) then
    begin
      Result := Result + [mSwitch.Module];
    end;
  end;
end;

class function TDpccModuleSwitches.ModuleOf(const ASwitches: TArray<TDpccModuleSwitch>;
  const AName: string): string;
var
  mSwitch: TDpccModuleSwitch;
  mEntry: TDpccCatalogEntry;
begin
  Result := '';
  for mSwitch in ASwitches do
  begin
    if SameText(mSwitch.Name, AName) or SameText(mSwitch.Key, AName) then
    begin
      Exit(mSwitch.Module);
    end;
    for mEntry in mSwitch.Members do
    begin
      if SameText(mEntry.Name, AName) or SameText(mEntry.Key, AName) then
      begin
        Exit(mSwitch.Module);
      end;
    end;
  end;
end;

end.
