unit dpcc.Core.Settings.Scopes;

// Wo die Plugin-Einstellungen liegen (#227): fast alle in der Registry (HKCU\Software\dpcc\IdePlugin), zwei in
// %APPDATA%\dpcc\settings.json, weil der Server sie aus derselben Datei liest:
// - index.extraSourceFolders (L2, Text mit ";"): Option der Seite „dpcc“, gelesen und geschrieben;
// - hints.xmlDocMaxLines: nur gelesen; über settings.json einstellbar, dpcc schreibt den Wert nicht.
// TDpccRoutedSettingsStore leitet diese Namen in den Text von settings.json um, alle übrigen in die Registry. Steht
// ein umgeleiteter Wert noch nicht in der Datei, gilt ein alter Registry-Wert (aus der Zeit vor der Umleitung), sonst
// die Vorgabe. Eine kaputte Datei wird nicht angefasst; ein geschriebener Wert geht dann für diese Sitzung in die
// Registry.
// Seit OPT2 leitet dpcc nichts weiter um: Schnellbefehle, Code-Metriken, Kompilieren nach dem Speichern, Architektur,
// Abfragen, Prüfregeln, Hotspots, Verwendungen, Navigation, betroffene Tests, Tracker, Versionsverwaltung und
// experimental.enabled schreibt das Plugin nicht mehr in settings.json. Werte, die dort schon stehen, bleiben liegen;
// der Server kennt die Schlüssel weiter (keine Meldung) und nimmt ohne sie seine eigenen Vorgaben, die den früheren
// des Plugins gleichen. Die einmalige Übernahme alter Registry-Werte in die Datei (Migrate) entfällt: Das Lesen fällt
// ohnehin auf die Registry zurück.

interface

uses
  System.SysUtils,
  dpcc.Core.Settings.Plugin;

type
  TDpccRoutedSetting = record
    /// <summary>Name in TDpccPluginSettings.Load/Save, z. B. "XmlDocMaxLines".</summary>
    Name: string;
    /// <summary>Pfad in settings.json, z. B. "hints.xmlDocMaxLines".</summary>
    Path: string;
    /// <summary>Wahrheitswert (true/false); sonst ganze Zahl.</summary>
    Flag: Boolean;
    /// <summary>Zeichenkette (ReadString/WriteString), z. B. "IndexExtraSourceFolders".</summary>
    Text: Boolean;
    /// <summary>Nur gelesen: dpcc schreibt den Wert nie (hints.xmlDocMaxLines).</summary>
    ReadOnly: Boolean;
  end;

  TDpccSettingsScopes = class
  public
    /// <summary>Plugin-Einstellungen, die in settings.json liegen.</summary>
    class function Routed: TArray<TDpccRoutedSetting>; static;
    class function TryRouted(const AName: string; out ASetting: TDpccRoutedSetting): Boolean; static;
  end;

  /// <summary>Speicher für TDpccPluginSettings: umgeleitete Namen in den Text von settings.json, alle übrigen
  /// in AInner (Registry). Text ist danach der neue Inhalt der Datei.</summary>
  TDpccRoutedSettingsStore = class(TInterfacedObject, IDpccSettingsStore)
  private
    FInner: IDpccSettingsStore;
    FText: string;
    function JsonValue(const APath: string): string;
    function Writable: Boolean;
  public
    constructor Create(const AInner: IDpccSettingsStore; const AGlobalText: string);
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
    property Text: string read FText;
  end;

  /// <summary>Die globale Datei settings.json (wie im Server).</summary>
  TDpccSettingsFiles = class
  public const
    cGlobalFolder = 'dpcc';
    cGlobalName = 'settings.json';
  public
    /// <summary>Globale Datei unter AAppData (%APPDATA%); '' ohne AAppData.</summary>
    class function GlobalFile(const AAppData: string): string; static;
  end;

implementation

uses
  System.IOUtils,
  System.JSON,
  dpcc.Core.Settings.JsonText;

function Setting(const AName, APath: string; AFlag: Boolean): TDpccRoutedSetting;
begin
  Result := Default(TDpccRoutedSetting);
  Result.Name := AName;
  Result.Path := APath;
  Result.Flag := AFlag;
end;

function TextSetting(const AName, APath: string): TDpccRoutedSetting;
begin
  Result := Setting(AName, APath, False);
  Result.Text := True;
end;

function ReadOnlySetting(const AName, APath: string; AFlag: Boolean): TDpccRoutedSetting;
begin
  Result := Setting(AName, APath, AFlag);
  Result.ReadOnly := True;
end;

{ TDpccSettingsScopes }

class function TDpccSettingsScopes.Routed: TArray<TDpccRoutedSetting>;
begin
  Result := [
    // Zeilen des XMLDoc-Texts im Tooltip: fest 0 (alle), über settings.json einstellbar; Server und Plugin lesen
    // denselben Wert.
    ReadOnlySetting('XmlDocMaxLines', 'hints.xmlDocMaxLines', False),
    // L2: zusätzliche Quellordner (Text mit ";"); der Server liest denselben Wert.
    TextSetting('IndexExtraSourceFolders', 'index.extraSourceFolders')];
end;

class function TDpccSettingsScopes.TryRouted(const AName: string; out ASetting: TDpccRoutedSetting): Boolean;
var
  mItem: TDpccRoutedSetting;
begin
  for mItem in Routed do
  begin
    if SameText(mItem.Name, AName) then
    begin
      ASetting := mItem;
      Exit(True);
    end;
  end;
  ASetting := Default(TDpccRoutedSetting);
  Result := False;
end;

/// <summary>Text eines JSON-Strings, sonst ADefault.</summary>
function StringValue(const AJson, ADefault: string): string;
var
  mValue: TJSONValue;
begin
  Result := ADefault;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONString then
    begin
      Result := TJSONString(mValue).Value;
    end;
  finally
    mValue.Free;
  end;
end;

{ TDpccRoutedSettingsStore }

constructor TDpccRoutedSettingsStore.Create(const AInner: IDpccSettingsStore; const AGlobalText: string);
begin
  inherited Create;
  FInner := AInner;
  FText := AGlobalText;
end;

function TDpccRoutedSettingsStore.JsonValue(const APath: string): string;
var
  mRoot: TJSONObject;
begin
  Result := '';
  mRoot := TDpccJsonText.Parse(FText);
  try
    if mRoot <> nil then
    begin
      Result := TDpccJsonText.ValueAt(mRoot, APath);
    end;
  finally
    mRoot.Free;
  end;
end;

function TDpccRoutedSettingsStore.Writable: Boolean;
var
  mRoot: TJSONObject;
begin
  // Eine kaputte Datei wird nicht angefasst; die Werte bleiben dann für diese Sitzung.
  if Trim(FText) = '' then
  begin
    Exit(True);
  end;
  mRoot := TDpccJsonText.Parse(FText);
  Result := mRoot <> nil;
  mRoot.Free;
end;

function TDpccRoutedSettingsStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
var
  mRouted: TDpccRoutedSetting;
  mValue: string;
begin
  if not TDpccSettingsScopes.TryRouted(AName, mRouted) then
  begin
    Exit(FInner.ReadInteger(AName, ADefault));
  end;
  mValue := JsonValue(mRouted.Path);
  if mValue = 'true' then
  begin
    Result := 1;
  end
  else if mValue = 'false' then
  begin
    Result := 0;
  end
  else if mValue <> '' then
  begin
    Result := StrToIntDef(mValue, ADefault);
  end
  else
  begin
    // Noch nicht in settings.json: alter Wert aus der Registry, sonst die Vorgabe.
    Result := FInner.ReadInteger(AName, ADefault);
  end;
end;

procedure TDpccRoutedSettingsStore.WriteInteger(const AName: string; AValue: Integer);
var
  mRouted: TDpccRoutedSetting;
  mJson: string;
begin
  if not TDpccSettingsScopes.TryRouted(AName, mRouted) then
  begin
    FInner.WriteInteger(AName, AValue);
    Exit;
  end;
  // Nur gelesen: weder in die Datei noch in die Registry.
  if mRouted.ReadOnly then
  begin
    Exit;
  end;
  if not Writable then
  begin
    FInner.WriteInteger(AName, AValue);
    Exit;
  end;
  if not mRouted.Flag then
  begin
    mJson := IntToStr(AValue);
  end
  else if AValue <> 0 then
  begin
    mJson := 'true';
  end
  else
  begin
    mJson := 'false';
  end;
  if JsonValue(mRouted.Path) <> mJson then
  begin
    FText := TDpccJsonText.SetValue(FText, mRouted.Path, mJson);
  end;
end;

function TDpccRoutedSettingsStore.ReadString(const AName, ADefault: string): string;
var
  mRouted: TDpccRoutedSetting;
  mJson: string;
begin
  if not TDpccSettingsScopes.TryRouted(AName, mRouted) or not mRouted.Text then
  begin
    Exit(FInner.ReadString(AName, ADefault));
  end;
  mJson := JsonValue(mRouted.Path);
  if mJson = '' then
  begin
    // Noch nicht in settings.json: alter Wert aus der Registry, sonst die Vorgabe.
    Result := FInner.ReadString(AName, ADefault);
  end
  else
  begin
    Result := StringValue(mJson, ADefault);
  end;
end;

procedure TDpccRoutedSettingsStore.WriteString(const AName, AValue: string);
var
  mRouted: TDpccRoutedSetting;
  mJson: string;
begin
  if not TDpccSettingsScopes.TryRouted(AName, mRouted) or not mRouted.Text then
  begin
    FInner.WriteString(AName, AValue);
    Exit;
  end;
  // Nur gelesen: weder in die Datei noch in die Registry.
  if mRouted.ReadOnly then
  begin
    Exit;
  end;
  if not Writable then
  begin
    FInner.WriteString(AName, AValue);
    Exit;
  end;
  mJson := TDpccJsonText.Quote(AValue);
  if JsonValue(mRouted.Path) <> mJson then
  begin
    FText := TDpccJsonText.SetValue(FText, mRouted.Path, mJson);
  end;
end;

{ TDpccSettingsFiles }

class function TDpccSettingsFiles.GlobalFile(const AAppData: string): string;
begin
  Result := '';
  if AAppData <> '' then
  begin
    Result := TPath.Combine(TPath.Combine(AAppData, cGlobalFolder), cGlobalName);
  end;
end;

end.
