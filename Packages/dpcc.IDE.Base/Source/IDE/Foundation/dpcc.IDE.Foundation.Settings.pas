unit dpcc.IDE.Foundation.Settings;

// Einstellungen des Plugins in der Registry (HKCU\Software\dpcc\IdePlugin,
// #227) und der aktuelle Stand für alle Teile des Plugins. Gelesen wird
// einmal beim ersten Zugriff, geschrieben über Update (Optionsseite, gezogene
// Breiten, eingeklapptes Panel).
// Schnellschalter (#604): Current liefert die wirksamen Werte, also die
// gespeicherten mit den Sitzungswerten darüber (nur für diese Sitzung, „Alles
// aus“); Stored die gespeicherten für Optionsseite und Update. Sitzungswerte
// landen nie in der Registry.
// Ort der Einstellungen: Index, Speicher, XMLDoc, Schnellbefehle
// und Kompilieren nach dem Speichern gelten auch für den Server und liegen in
// %APPDATA%\dpcc\settings.json (TDpccRoutedSettingsStore); der Server liest
// die Datei selbst und beobachtet sie. Alte Werte aus der Registry übernimmt
// das erste Lesen einmal in die Datei.
// Abgesicherter Start (#722): Vor jeder gespeicherten Änderung kommt der alte
// Stand in die Einstellungsstände (%APPDATA%\dpcc\settings-history.json),
// höchstens safeMode.keepSettingsHistory; Restore setzt auf einen davon zurück.
// Experimentelle Funktionen (#834): Ohne Hauptschalter experimental.enabled
// liefert Current für jede Einstellung mit x-experimental die Vorgabe; Stored
// behält den gespeicherten Wert.
// Modul-Schalter (#1454): Ist ein Modul aus, liefert Current für jede
// Einstellung des Moduls „aus“ (TDpccModuleSwitches); Stored behält die
// gespeicherten Werte.
// Umbenannte Einstellungen (#1280, x-renamedFrom): Vor dem ersten Lesen
// übernimmt TDpccSettingsRenames frühere Registry-Namen (z. B.
// WelcomePageIssuesTracker → IssuesTracker) und entfernt sie; jede Übernahme
// steht einmal im Protokoll.
// Abfragen (#1262): Ein früheres issues.query (Registry IssuesQuery bzw.
// WelcomePageIssuesQuery) wird einmal zur Abfrage „Standard“ in
// issues.queries (settings.json); der Registry-Name geht erst, wenn die Datei
// geschrieben ist.

interface

uses
  System.SysUtils,
  dpcc.Core.Files.TextFile,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Problems.InlineHints,
  dpcc.Core.Settings.History,
  dpcc.Core.Settings.Catalog,
  dpcc.Core.Settings.QuickToggles,
  dpcc.Core.Settings.ModuleSwitches;

type
  TDpccIdeSettings = class
  private class var
    FOnChanged: TProc;
  private
    class procedure EnsureLoaded; static;
    class procedure Changed; static;
  public
    /// <summary>Globale Einstellungsdatei; öffentlich für die Seite Prüfregeln und das Fenster dpcc-Prüfung
    /// (#909), die Regeln ohne Projekt dort speichern.</summary>
    class function GlobalFile: string; static;
    /// <summary>False, wenn die Datei da, aber nicht lesbar ist; dann wird sie auch nicht geschrieben.
    /// Öffentlich für die gezielten Änderungen der Prüfregeln (#909).</summary>
    class function LoadGlobal(out AContent: TDpccTextFileContent): Boolean; static;
    class procedure SaveGlobal(const AContent: TDpccTextFileContent; const AText: string); static;
    /// <summary>Wirksame Werte: gespeichert, darüber die Sitzungswerte der Schnellschalter (#604).</summary>
    class function Current: TDpccPluginSettings; static;
    /// <summary>Gespeicherte Werte (Registry) ohne Sitzungswerte; Grundlage für Optionsseite und Update.</summary>
    class function Stored: TDpccPluginSettings; static;
    /// <summary>Plugin eingeschaltet und Rekursionssymbole an (#623); ohne Kopie des Einstellungsrecords.</summary>
    class function RecursionMarkersOn: Boolean; static;
    /// <summary>editor.recursionMarkers.depth (#623).</summary>
    class function RecursionMarkersDepth: Integer; static;
    /// <summary>Plugin eingeschaltet und Austrittspunkte hervorheben an (#698); die Schalter aus
    /// editor.exitPoints.*, ohne Kopie des Einstellungsrecords.</summary>
    class function ExitPointsOn(out AExceptions, ALoops, ABadge: Boolean): Boolean; static;
    /// <summary>Plugin eingeschaltet und neu zugewiesene Variablen unterstreichen an (#712); Arten, Linie und Farbe
    /// aus highlight.reassigned.*, ohne Kopie des Einstellungsrecords.</summary>
    class function ReassignedOn(out ATargets, AStyle, AColor: string): Boolean; static;
    /// <summary>Plugin eingeschaltet und Problem-Markierungen an; ohne Kopie des Einstellungsrecords.</summary>
    class function ProblemMarksOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Marken folgen ihrer Zeile sofort (#1818, editor.trackLines); ohne Kopie des
    /// Einstellungsrecords.</summary>
    class function TrackLinesOn: Boolean; static;
    /// <summary>Fehlertext am Zeilenende (#509); Off, wenn das Plugin oder die Problem-Markierungen aus sind.
    /// </summary>
    class function InlineDiagnosticsMode: TDpccInlineDiagnosticsMode; static;
    /// <summary>Übernimmt und speichert ASettings (gespeicherte Werte, ohne Sitzungswerte).</summary>
    class procedure Update(const ASettings: TDpccPluginSettings); static;
    /// <summary>Inhalt von %APPDATA%\dpcc\settings.json ('' ohne Datei) für Export und Import (#723).</summary>
    class function GlobalText: string; static;
    /// <summary>Schreibt AText nach settings.json (#723); False, wenn die Datei da, aber nicht lesbar ist.
    /// Danach Update aufrufen, damit die umgeleiteten Plugin-Werte dazukommen.</summary>
    class function SaveGlobalText(const AText: string): Boolean; static;
    /// <summary>Sitzungswerte der Schnellschalter (#604).</summary>
    class function Session: TDpccToggleSession; static;
    class procedure SetSession(const ASession: TDpccToggleSession); static;
    /// <summary>Schnellschalter aus Plugin-Katalog und dpcc.schema.json in der Sprache der Oberfläche.</summary>
    class function QuickToggles: TArray<TDpccQuickToggle>; static;
    /// <summary>Modul-Schalter aus dem Katalog (#1454), einmal gelesen.</summary>
    class function ModuleSwitches: TArray<TDpccModuleSwitch>; static;
    /// <summary>Ist das Modul AModule (x-module, z. B. "debug") wirksam an, auch nach Schnellschaltern? Unbekannte
    /// Kennung = an.</summary>
    class function ModuleOn(const AModule: string): Boolean; static;
    /// <summary>Experimentelle Plugin-Einstellungen aus dem Katalog (#834), einmal gelesen.</summary>
    class function ExperimentalEntries: TArray<TDpccCatalogEntry>; static;
    /// <summary>Schlüssel der experimentellen Schalter, die gerade wirken (Plugin und settings.json); leer ohne
    /// Hauptschalter. Für Statusfeld, Fehlerbericht und Diagnoselog.</summary>
    class function ActiveExperimental: TArray<string>; static;
    /// <summary>Gemerkte Einstellungsstände, neuester zuerst (#722).</summary>
    class function History: TDpccSettingsHistory; static;
    /// <summary>Gespeicherte Einstellungen auf Stand AIndex zurücksetzen; der jetzige Stand wird selbst
    /// gemerkt.</summary>
    class procedure Restore(AIndex: Integer); static;
    /// <summary>Beim Entladen: Einstellungsstände freigeben.</summary>
    class procedure Release; static;
    /// <summary>Für Diagnose und Tests: beim nächsten Zugriff neu lesen.</summary>
    class procedure Reload; static;
    /// <summary>Nach Update (Optionsseite, Menü dpcc): z. B. Tastenkürzel neu belegen (#494).</summary>
    class property OnChanged: TProc read FOnChanged write FOnChanged;
  end;

const
  cDpccRegistryKey = 'Software\dpcc\IdePlugin';

implementation

uses
  dpcc.Core.Settings.QueryMigration,
  Winapi.Windows,
  System.IOUtils,
  System.DateUtils,
  System.Win.Registry,
  dpcc.Core.Settings.SchemaData,
  dpcc.Core.Settings.Layers,
  dpcc.Core.Settings.Scopes,
  dpcc.Core.Settings.Renames,
  dpcc.Core.Settings.Experimental,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Files.DataFile,
  dpcc.UI.Strings;

type
  TRegistryStore = class(TInterfacedObject, IDpccSettingsStore, IDpccSettingsNames)
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
    function Contains(const AName: string): Boolean;
    procedure Remove(const AName: string);
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

function TRegistryStore.Contains(const AName: string): Boolean;
begin
  try
    Result := (FRegistry.CurrentKey <> 0) and FRegistry.ValueExists(AName);
  except
    on ERegistryException do
      Result := False;
  end;
end;

procedure TRegistryStore.Remove(const AName: string);
begin
  if not FWritable then
  begin
    Exit;
  end;
  try
    if FRegistry.ValueExists(AName) then
    begin
      FRegistry.DeleteValue(AName);
    end;
  except
    // Ohne Schreibrecht bleibt der alte Wert; die Übernahme versucht es beim nächsten Start erneut.
    on ERegistryException do
      ;
  end;
end;

type
  /// <summary>Zustand von TDpccIdeSettings (gelesene, wirksame Werte, Schnellschalter, Stände, Katalogteile).
  /// </summary>
  TSettingsState = record
    Stored: TDpccPluginSettings;
    Effective: TDpccPluginSettings;
    Session: TDpccToggleSession;
    Toggles: TArray<TDpccQuickToggle>;
    TogglesEnglish: Boolean;
    TogglesBuilt: Boolean;
    History: TDpccSettingsHistory;
    /// <summary>settings-history.json war beim Lesen gesperrt: SaveHistory überschreibt sie nicht.
    /// </summary>
    HistoryKept: Boolean;
    Loaded: Boolean;
    Experimental: TArray<TDpccCatalogEntry>;
    ExperimentalRead: Boolean;
    Modules: TArray<TDpccModuleSwitch>;
    ModulesRead: Boolean;
  end;

var
  GState: TSettingsState;

/// <summary>Umbenannte Einstellungen (x-renamedFrom, #1280) in der Registry übernehmen; jede Übernahme steht
/// einmal im Protokoll.</summary>
procedure ApplyRenames;
var
  mRegistry: TRegistryStore;
  mStore: IDpccSettingsStore;
  mCatalog: TDpccSettingsCatalog;
  mRename: TDpccSettingsRename;
begin
  mRegistry := TRegistryStore.Create(True);
  mStore := mRegistry;
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    for mRename in TDpccSettingsRenames.Apply(mStore, mRegistry, mCatalog) do
    begin
      TDpccGuard.Log(mRename.LogLine);
    end;
  finally
    mCatalog.Free;
  end;
end;

/// <summary>issues.query als Abfrage „Standard“ nach issues.queries (#1262); True, wenn ARouted geändert
/// wurde. Der Registry-Name geht über RemoveLegacyQuery erst nach dem Speichern der Datei.</summary>
function MigrateQuery(const ARouted: IDpccSettingsStore;
  out AMigration: TDpccSettingsQueryMigration): Boolean;
var
  mRegistry: TRegistryStore;
  mLegacy: IDpccSettingsStore;
begin
  mRegistry := TRegistryStore.Create(False);
  mLegacy := mRegistry;
  AMigration := TDpccSettingsQueryMigrations.Migrate(mLegacy, mRegistry, ARouted);
  Result := AMigration.Moved;
end;

procedure RemoveLegacyQuery(const AMigration: TDpccSettingsQueryMigration);
var
  mRegistry: TRegistryStore;
  mNames: IDpccSettingsNames;
begin
  if not AMigration.Found then
  begin
    Exit;
  end;
  mRegistry := TRegistryStore.Create(True);
  mNames := mRegistry;
  TDpccSettingsQueryMigrations.RemoveLegacy(mNames);
  TDpccGuard.Log(AMigration.LogLine);
end;

function HistoryFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'dpcc'), 'settings-history.json');
end;

procedure SaveHistory;
var
  mSnapshots: TDpccSettingsHistory;
begin
  // Erst laden: Das setzt GState.HistoryKept.
  mSnapshots := TDpccIdeSettings.History;
  // Gesperrt gelesene Datei nicht mit den Ständen dieser Sitzung allein überschreiben.
  if not GState.HistoryKept then
  begin
    TDpccDataFile.Write(HistoryFile, mSnapshots.ToJson);
  end;
end;

/// <summary>Gespeichert, darüber Sitzungswerte, Einstellungen ausgeschalteter Module auf „aus“ (#1454), ohne
/// Hauptschalter experimentelle Werte auf Vorgabe.</summary>
function EffectiveSettings: TDpccPluginSettings;
begin
  Result := TDpccExperimental.Apply(TDpccModuleSwitches.Apply(GState.Session.Apply(GState.Stored,
    TDpccIdeSettings.QuickToggles), TDpccIdeSettings.ModuleSwitches), TDpccIdeSettings.ExperimentalEntries);
end;

{ TDpccIdeSettings }

class function TDpccIdeSettings.GlobalFile: string;
begin
  Result := TDpccSettingsFiles.GlobalFile(GetEnvironmentVariable('APPDATA'));
end;

class function TDpccIdeSettings.LoadGlobal(out AContent: TDpccTextFileContent): Boolean;
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

class procedure TDpccIdeSettings.SaveGlobal(const AContent: TDpccTextFileContent; const AText: string);
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

class procedure TDpccIdeSettings.EnsureLoaded;
var
  mContent: TDpccTextFileContent;
  mReadable: Boolean;
  mRouted: TDpccRoutedSettingsStore;
  mStore: IDpccSettingsStore;
  mChanged: Boolean;
  mMigration: TDpccSettingsQueryMigration;
begin
  if GState.Loaded then
  begin
    Exit;
  end;
  GState.Stored := TDpccPluginSettings.Defaults;
  ApplyRenames;
  mReadable := LoadGlobal(mContent);
  mRouted := TDpccRoutedSettingsStore.Create(TRegistryStore.Create(False), mContent.Text);
  mStore := mRouted;
  // Einmalig: Werte, die bis hierher in der Registry lagen, nach settings.json.
  mChanged := mRouted.Migrate;
  mMigration := Default(TDpccSettingsQueryMigration);
  // Eine nicht lesbare Datei wird nicht geschrieben: dann bleibt auch issues.query in der Registry.
  if mReadable and MigrateQuery(mStore, mMigration) then
  begin
    mChanged := True;
  end;
  if mChanged and mReadable then
  begin
    SaveGlobal(mContent, mRouted.Text);
  end;
  if mReadable then
  begin
    RemoveLegacyQuery(mMigration);
  end;
  GState.Stored.Load(mStore);
  GState.Loaded := True;
  GState.Effective := EffectiveSettings;
end;

class function TDpccIdeSettings.ExperimentalEntries: TArray<TDpccCatalogEntry>;
var
  mCatalog: TDpccSettingsCatalog;
begin
  if not GState.ExperimentalRead then
  begin
    mCatalog := TDpccSettingsCatalog.CreateDefault;
    try
      GState.Experimental := TDpccExperimental.PluginEntries(mCatalog);
    finally
      mCatalog.Free;
    end;
    GState.ExperimentalRead := True;
  end;
  Result := GState.Experimental;
end;


class function TDpccIdeSettings.ModuleSwitches: TArray<TDpccModuleSwitch>;
var
  mCatalog: TDpccSettingsCatalog;
begin
  if not GState.ModulesRead then
  begin
    mCatalog := TDpccSettingsCatalog.CreateDefault;
    try
      GState.Modules := TDpccModuleSwitches.Read(mCatalog);
    finally
      mCatalog.Free;
    end;
    GState.ModulesRead := True;
  end;
  Result := GState.Modules;
end;

class function TDpccIdeSettings.ModuleOn(const AModule: string): Boolean;
begin
  EnsureLoaded;
  // Der Schalter selbst gehört nicht zu seinen Mitgliedern: In GState.Effective steht sein Wert samt Sitzungswert.
  Result := TDpccModuleSwitches.IsOn(GState.Effective, ModuleSwitches, AModule);
end;

class function TDpccIdeSettings.ActiveExperimental: TArray<string>;
var
  mCatalog: TDpccSettingsCatalog;
begin
  EnsureLoaded;
  mCatalog := TDpccSettingsCatalog.CreateDefault;
  try
    Result := TDpccExperimental.Active(GState.Session.Apply(GState.Stored, QuickToggles), GlobalText, mCatalog);
  finally
    mCatalog.Free;
  end;
end;

class function TDpccIdeSettings.Current: TDpccPluginSettings;
begin
  EnsureLoaded;
  Result := GState.Effective;
end;

class function TDpccIdeSettings.RecursionMarkersOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.RecursionMarkers;
end;

class function TDpccIdeSettings.ExitPointsOn(out AExceptions, ALoops, ABadge: Boolean): Boolean;
begin
  EnsureLoaded;
  AExceptions := GState.Effective.ExitPointsExceptions;
  ALoops := GState.Effective.ExitPointsLoops;
  ABadge := GState.Effective.ExitPointsBadge;
  Result := GState.Effective.Enabled and GState.Effective.ExitPoints;
end;

class function TDpccIdeSettings.ReassignedOn(out ATargets, AStyle, AColor: string): Boolean;
begin
  EnsureLoaded;
  ATargets := GState.Effective.ReassignedTargets;
  AStyle := GState.Effective.ReassignedStyle;
  AColor := GState.Effective.ReassignedColor;
  Result := GState.Effective.Enabled and GState.Effective.Reassigned;
end;

class function TDpccIdeSettings.RecursionMarkersDepth: Integer;
begin
  EnsureLoaded;
  Result := GState.Effective.RecursionMarkersDepth;
end;

class function TDpccIdeSettings.ProblemMarksOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.Problems;
end;

class function TDpccIdeSettings.TrackLinesOn: Boolean;
begin
  EnsureLoaded;
  Result := GState.Effective.Enabled and GState.Effective.TrackLines;
end;

class function TDpccIdeSettings.InlineDiagnosticsMode: TDpccInlineDiagnosticsMode;
begin
  EnsureLoaded;
  if GState.Effective.Enabled and GState.Effective.Problems then
  begin
    Result := TDpccInlineDiagnostics.ModeOf(GState.Effective.InlineDiagnostics);
  end
  else
  begin
    Result := TDpccInlineDiagnosticsMode.Off;
  end;
end;

class function TDpccIdeSettings.Stored: TDpccPluginSettings;
begin
  EnsureLoaded;
  Result := GState.Stored;
end;

class procedure TDpccIdeSettings.Changed;
begin
  GState.Effective := EffectiveSettings;
  if Assigned(FOnChanged) then
  begin
    FOnChanged();
  end;
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
  mNext.Normalize;
  // Alten Stand merken (#722); Fehler beim Schreiben der Datei stören das Speichern nicht.
  try
    History.Push(GState.Stored, mNext, TTimeZone.Local.ToUniversalTime(Now), mNext.SafeKeepSettingsHistory);
    SaveHistory;
  except
    // Der Grund steht einmal im Protokoll (ohne Pfad).
    on E: Exception do
      TDpccDataFile.ReportNotWritten('Einstellungsverlauf', E);
  end;
  GState.Stored := mNext;
  GState.Loaded := True;
  // settings.json frisch lesen: Der Dialog der globalen Einstellungen schreibt dieselbe Datei.
  mReadable := LoadGlobal(mContent);
  mRouted := TDpccRoutedSettingsStore.Create(TRegistryStore.Create(True), mContent.Text);
  mStore := mRouted;
  GState.Stored.Save(mStore);
  if mReadable then
  begin
    SaveGlobal(mContent, mRouted.Text);
  end;
  Changed;
end;

class function TDpccIdeSettings.GlobalText: string;
var
  mContent: TDpccTextFileContent;
begin
  LoadGlobal(mContent);
  Result := mContent.Text;
end;

class function TDpccIdeSettings.SaveGlobalText(const AText: string): Boolean;
var
  mContent: TDpccTextFileContent;
begin
  Result := LoadGlobal(mContent);
  if Result then
  begin
    SaveGlobal(mContent, AText);
  end;
end;

class function TDpccIdeSettings.Session: TDpccToggleSession;
begin
  Result := GState.Session;
end;

class procedure TDpccIdeSettings.SetSession(const ASession: TDpccToggleSession);
begin
  EnsureLoaded;
  GState.Session := ASession;
  Changed;
end;

class function TDpccIdeSettings.History: TDpccSettingsHistory;
begin
  if GState.History = nil then
  begin
    GState.History := TDpccSettingsHistory.Create;
    // Fehlt, unbrauchbar (dann als .defekt beiseitegelegt) oder gesperrt: ohne gemerkte Stände weiter.
    GState.HistoryKept := not TDpccDataFile.Writable(TDpccDataFile.Load(HistoryFile, 'Einstellungsverlauf',
      function(const AText: string): Boolean
      begin
        Result := GState.History.LoadJson(AText);
      end));
    if GState.HistoryKept then
    begin
      GState.History.Clear;
    end;
  end;
  Result := GState.History;
end;

class procedure TDpccIdeSettings.Restore(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= History.Count) then
  begin
    Exit;
  end;
  Update(History[AIndex].Settings);
end;

class procedure TDpccIdeSettings.Release;
begin
  FreeAndNil(GState.History);
  GState.Experimental := nil;
  GState.ExperimentalRead := False;
  GState.Modules := nil;
  GState.ModulesRead := False;
end;

class function TDpccIdeSettings.QuickToggles: TArray<TDpccQuickToggle>;
var
  mEnglish: Boolean;
begin
  mEnglish := TDpccStrings.Language = TDpccLanguage.English;
  if not GState.TogglesBuilt or (mEnglish <> GState.TogglesEnglish) then
  begin
    GState.Toggles := TDpccQuickToggles.Build(TDpccQuickToggles.PluginCatalog, DpccSchemaJson, mEnglish);
    GState.TogglesEnglish := mEnglish;
    GState.TogglesBuilt := True;
  end;
  Result := GState.Toggles;
end;

class procedure TDpccIdeSettings.Reload;
begin
  GState.Loaded := False;
end;

end.
