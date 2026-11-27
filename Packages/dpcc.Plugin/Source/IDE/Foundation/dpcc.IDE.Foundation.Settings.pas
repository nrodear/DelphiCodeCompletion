unit dpcc.IDE.Foundation.Settings;

// Einstellungen des Plugins in der Registry (HKCU\Software\dpcc\IdePlugin, #227) und der aktuelle Stand für alle
// Teile des Plugins. Gelesen wird einmal beim ersten Zugriff, geschrieben über Update (Optionsseite, gezogene Breite
// der Liste).
// Ort der Einstellungen: index.extraSourceFolders (geschrieben) und hints.xmlDocMaxLines (nur gelesen) liegen in
// %APPDATA%\dpcc\settings.json (TDpccRoutedSettingsStore); der Server liest die Datei selbst und beobachtet sie.
// Fest verdrahtet (OPT1): Die Optionen, die es auf der Seite nicht mehr gibt, lesen ihre Stellen aus
// TDpccFixedSettings (dpcc.Core.Settings.CompletionView); alte Registry-Werte dazu bleiben liegen.
// Seit OPT2 gibt es keine Schnellschalter-Sitzungswerte, Modul-Schalter, experimentellen Schalter, Umbenennungen,
// Abfrage-Übernahme und keinen Einstellungsverlauf (settings-history.json) mehr: Current ist genau der gespeicherte
// Stand, und Update schreibt nur noch die Werte der Seite (TDpccPluginSettings.StoredNames). Eine vorhandene
// settings-history.json und alte Registry-Werte bleiben liegen und werden nicht gelesen.
// Seit LOG1 gehört der DWORD Diagnose („Ablauf protokollieren (Log)“) zu den Werten der Seite. Weil der Support ihn
// auch von Hand setzt, liest RefreshDiagnose ihn vor dem Laden der Seite neu, und Update übernimmt den Stand der
// Registry, wenn der Aufrufer den Wert nicht geändert hat.
// Seit Stufe 2 von dpcc.LspServer.exe gilt die Betriebsart (Aus, Plugin, Server) je Delphi-Version
// ("OperatingMode 23.0" bzw. "OperatingMode 37.0", Version nach CompilerVersion, IdeVersion). Fehlt der Wert einer
// Version, überführt EnsureLoaded den früheren gemeinsamen DWORD Enabled (0 → Aus, sonst Plugin, ohne ihn Plugin) und
// schreibt das Ergebnis sofort unter dem Namen der Version; Enabled schreibt dpcc nicht mehr.

interface

uses
  System.SysUtils,
  dpcc.Core.Settings.Plugin;

type
  TDpccIdeSettings = class
  private class var
    FOnChanged: TProc;
  private
    class procedure EnsureLoaded; static;
  public
    /// <summary>Gespeicherte Werte (Registry, settings.json); Grundlage für alle Teile des Plugins, die Optionsseite
    /// und Update.</summary>
    class function Current: TDpccPluginSettings; static;
    /// <summary>Übernimmt und speichert ASettings: die Werte der Seite in die Registry, index.extraSourceFolders
    /// nach settings.json.</summary>
    class procedure Update(const ASettings: TDpccPluginSettings); static;
    /// <summary>„Ablauf protokollieren“ (LOG1, DWORD Diagnose) neu aus der Registry in den aktuellen Stand: Der Support
    /// setzt den Wert auch von Hand, während die IDE läuft. Vor dem Laden der Optionsseite; ändert sonst nichts und
    /// löst OnChanged nicht aus.</summary>
    class procedure RefreshDiagnose; static;
    /// <summary>Beim Entladen: Stand verwerfen; der nächste Zugriff liest neu.</summary>
    class procedure Release; static;
    /// <summary>Version der IDE, deren Betriebsart gilt ("23.0" für Delphi 12, "37.0" für Delphi 13).</summary>
    class function IdeVersion: string; static;
    /// <summary>Einmal True, wenn beim Laden für diese Version weder ein eigener Wert der Betriebsart noch das frühere
    /// Enabled stand (erster Start nach der Installation): Dann gilt die Vorgabe Plugin auch gegen DelphiLSP.</summary>
    class function TakeFreshDefault: Boolean; static;
    /// <summary>Nach Update (Optionsseite, gezogene Breite): z. B. Hauptschalter und Tooltips abgleichen (#494).
    /// </summary>
    class property OnChanged: TProc read FOnChanged write FOnChanged;
  end;

const
  cDpccRegistryKey = 'Software\dpcc\IdePlugin';

implementation

uses
  Winapi.Windows,
  System.IOUtils,
  System.Win.Registry,
  dpcc.Core.Files.TextFile,
  dpcc.Core.Settings.Scopes,
  dpcc.Core.Settings.OperatingMode,
  dpcc.Core.Diagnostics.Guard;

type
  TRegistryStore = class(TInterfacedObject, IDpccSettingsStore)
  private
    FRegistry: TRegistry;
    FWritable: Boolean;
  public
    constructor Create(AWrite: Boolean);
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

{ TRegistryStore }

constructor TRegistryStore.Create(AWrite: Boolean);
begin
  inherited Create;
  if AWrite then
  begin
    FRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  end
  else
  begin
    FRegistry := TRegistry.Create(KEY_READ);
  end;
  FRegistry.RootKey := HKEY_CURRENT_USER;
  if AWrite then
  begin
    FWritable := FRegistry.OpenKey(cDpccRegistryKey, True);
  end
  else
  begin
    FRegistry.OpenKeyReadOnly(cDpccRegistryKey);
  end;
end;

destructor TRegistryStore.Destroy;
begin
  FRegistry.Free;
  inherited Destroy;
end;

function TRegistryStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  Result := ADefault;
  try
    if (FRegistry.CurrentKey <> 0) and FRegistry.ValueExists(AName) and
      (FRegistry.GetDataType(AName) = rdInteger) then
    begin
      Result := FRegistry.ReadInteger(AName);
    end;
  except
    on ERegistryException do
      Result := ADefault;
  end;
end;

procedure TRegistryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  if not FWritable then
  begin
    Exit;
  end;
  try
    FRegistry.WriteInteger(AName, AValue);
  except
    // Ohne Schreibrecht bleiben die Werte für diese Sitzung bestehen.
    on ERegistryException do
      ;
  end;
end;

function TRegistryStore.ReadString(const AName, ADefault: string): string;
begin
  Result := ADefault;
  try
    if (FRegistry.CurrentKey <> 0) and FRegistry.ValueExists(AName) and
      (FRegistry.GetDataType(AName) in [rdString, rdExpandString]) then
    begin
      Result := FRegistry.ReadString(AName);
    end;
  except
    on ERegistryException do
      Result := ADefault;
  end;
end;

procedure TRegistryStore.WriteString(const AName, AValue: string);
begin
  if not FWritable then
  begin
    Exit;
  end;
  try
    FRegistry.WriteString(AName, AValue);
  except
    // Ohne Schreibrecht bleiben die Werte für diese Sitzung bestehen.
    on ERegistryException do
      ;
  end;
end;

type
  /// <summary>Zustand von TDpccIdeSettings.</summary>
  TSettingsState = record
    Settings: TDpccPluginSettings;
    Loaded: Boolean;
  end;

var
  GState: TSettingsState;
  /// <summary>Beim ersten Laden ohne jeden gespeicherten Wert der Betriebsart (TakeFreshDefault).</summary>
  GFreshDefault: Boolean;

function GlobalFile: string;
begin
  Result := TDpccSettingsFiles.GlobalFile(GetEnvironmentVariable('APPDATA'));
end;

/// <summary>False, wenn die Datei da, aber nicht lesbar ist; dann wird sie auch nicht geschrieben.</summary>
function LoadGlobal(out AContent: TDpccTextFileContent): Boolean;
begin
  AContent := Default(TDpccTextFileContent);
  AContent.Encoding := TDpccTextEncoding.Utf8;
  Result := True;
  try
    if (GlobalFile <> '') and TFile.Exists(GlobalFile) then
    begin
      AContent := TDpccTextFile.Load(GlobalFile);
    end;
  except
    // Gesperrt oder unlesbar: wie keine Datei für diese Sitzung, aber nicht überschreiben.
    on Exception do
    begin
      AContent.Text := '';
      Result := False;
    end;
  end;
end;

procedure SaveGlobal(const AContent: TDpccTextFileContent; const AText: string);
var
  mContent: TDpccTextFileContent;
begin
  if (GlobalFile = '') or (AText = AContent.Text) then
  begin
    Exit;
  end;
  mContent := AContent;
  mContent.Text := AText;
  try
    ForceDirectories(ExtractFileDir(GlobalFile));
    TDpccTextFile.Save(GlobalFile, mContent);
  except
    // Ohne Schreibrecht oder bei fremder Sperre bleiben die Werte für diese Sitzung bestehen. Ins
    // Protokoll ohne Pfad: Die Meldung von EDpccTextFileError nennt keinen, andere nur mit Klasse.
    on E: EDpccTextFileError do
      TDpccGuard.Log('Einstellungen nicht gespeichert: ' + TDpccGuard.MessageText(E.Message));
    on E: Exception do
      TDpccGuard.Log('Einstellungen nicht gespeichert: ' + E.ClassName);
  end;
end;

/// <summary>DWORD Diagnose (LOG1) jetzt in der Registry, wie TDpccPluginSettings ihn liest (ungleich 0 = an); ohne
/// Wert oder ohne Schlüssel ADefault.</summary>
function RegistryDiagnose(ADefault: Boolean): Boolean;
var
  mStore: IDpccSettingsStore;
  mDefault: Integer;
begin
  mDefault := 0;
  if ADefault then
  begin
    mDefault := 1;
  end;
  mStore := TRegistryStore.Create(False);
  Result := mStore.ReadInteger('Diagnose', mDefault) <> 0;
end;

{ TDpccIdeSettings }

class procedure TDpccIdeSettings.EnsureLoaded;
var
  mContent: TDpccTextFileContent;
  mStore: IDpccSettingsStore;
begin
  if GState.Loaded then
  begin
    Exit;
  end;
  LoadGlobal(mContent);
  mStore := TDpccRoutedSettingsStore.Create(TRegistryStore.Create(False), mContent.Text);
  // Betriebsart je Delphi-Version: Load liest "OperatingMode <Version>", ohne ihn das frühere Enabled.
  GState.Settings.IdeVersion := IdeVersion;
  GState.Settings.Load(mStore);
  GState.Loaded := True;
  // Weder eigener Wert noch früheres Enabled: erster Start nach der Installation, Vorgabe Plugin (ApplyAtStart).
  GFreshDefault := GState.Settings.ModeFromDefault;
  GState.Settings.ModeFromDefault := False;
  if GState.Settings.ModeFromLegacy then
  begin
    // Überführung einmal festschreiben: ab jetzt gilt für diese Version der eigene Wert; Enabled bleibt, wie er ist
    // (andere Versionen ohne eigenen Wert überführen ihn genauso).
    GState.Settings.ModeFromLegacy := False;
    mStore := TRegistryStore.Create(True);
    mStore.WriteString(TDpccOperatingModes.ValueName(IdeVersion), TDpccOperatingModes.IdOf(GState.Settings.Mode));
    TDpccGuard.Log(Format('Betriebsart für Delphi %s aus dem früheren Hauptschalter übernommen: %s', [IdeVersion,
      TDpccOperatingModes.LogName(GState.Settings.Mode)]));
  end;
end;

class function TDpccIdeSettings.TakeFreshDefault: Boolean;
begin
  EnsureLoaded;
  Result := GFreshDefault;
  GFreshDefault := False;
end;

class function TDpccIdeSettings.IdeVersion: string;
begin
  // Die Registry-Version der IDE, für die dieses Plugin gebaut ist (Delphi 12 = BDS 23.0, Delphi 13 = BDS 37.0);
  // ohne Open Tools API, damit es auch aus Hintergrund-Threads gilt.
{$IF CompilerVersion >= 37.0}
  Result := '37.0';
{$ELSE}
  Result := '23.0';
{$IFEND}
end;

class function TDpccIdeSettings.Current: TDpccPluginSettings;
begin
  EnsureLoaded;
  Result := GState.Settings;
end;

class procedure TDpccIdeSettings.Update(const ASettings: TDpccPluginSettings);
var
  mContent: TDpccTextFileContent;
  mReadable: Boolean;
  mRouted: TDpccRoutedSettingsStore;
  mStore: IDpccSettingsStore;
  mNext: TDpccPluginSettings;
begin
  EnsureLoaded;
  mNext := ASettings;
  // Immer unter der Version dieser IDE (die Betriebsart gilt je Version).
  mNext.IdeVersion := IdeVersion;
  mNext.ModeFromLegacy := False;
  mNext.Normalize;
  // Diagnose (LOG1) setzt der Support auch von Hand in der Registry: Ändert der Aufrufer den Wert nicht (gezogene
  // Breite der Liste, Betriebsart), gilt der Stand dort, statt ihn mit einem älteren zu überschreiben.
  if mNext.Diagnose = GState.Settings.Diagnose then
  begin
    mNext.Diagnose := RegistryDiagnose(mNext.Diagnose);
  end;
  GState.Settings := mNext;
  GState.Loaded := True;
  // settings.json frisch lesen: Der Server und andere Werkzeuge schreiben dieselbe Datei.
  mReadable := LoadGlobal(mContent);
  mRouted := TDpccRoutedSettingsStore.Create(TRegistryStore.Create(True), mContent.Text);
  mStore := mRouted;
  GState.Settings.Save(mStore);
  if mReadable then
  begin
    SaveGlobal(mContent, mRouted.Text);
  end;
  if Assigned(FOnChanged) then
  begin
    FOnChanged();
  end;
end;

class procedure TDpccIdeSettings.RefreshDiagnose;
begin
  EnsureLoaded;
  GState.Settings.Diagnose := RegistryDiagnose(GState.Settings.Diagnose);
end;

class procedure TDpccIdeSettings.Release;
begin
  GState := Default(TSettingsState);
end;

end.
