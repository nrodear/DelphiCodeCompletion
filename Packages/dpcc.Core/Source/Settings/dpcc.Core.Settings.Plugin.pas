unit dpcc.Core.Settings.Plugin;

// Einstellungen des IDE-Plugins (#227), ohne VCL und ohne Registry: Vorgaben, Grenzen, Lesen und Schreiben über
// einen Speicher. Die IDE-Schicht speichert in HKCU\Software\dpcc\IdePlugin, Tests im Arbeitsspeicher
// (TDpccMemorySettingsStore). Breiten in logischen Pixeln (96 dpi, #412).
// Seit OPT2 steht hier nur noch, was wirkt:
// - Gespeichert (OK auf der Seite „dpcc“, gezogene Breite der Liste): der Hauptschalter und die dreizehn Optionen der
//   Seite (cPageItems in dpcc.Core.Settings.CompletionView). index.extraSourceFolders liegt in
//   %APPDATA%\dpcc\settings.json (TDpccRoutedSettingsStore, dpcc.Core.Settings.Scopes), alle übrigen in der Registry.
//   Seit LOOK1 auch die Darstellung der Popups (PopupLook, Text 'intense' | 'subtle' | 'plain', dpcc.Core.Style.Look).
// - Nur gelesen, nie geschrieben: hints.xmlDocMaxLines (settings.json; der Server liest dieselbe Datei) und der
//   Support-Schalter LogNames (diagnostics.log.names, Registry-DWORD).
// - Fest verdrahtet und deshalb kein Feld mehr: Verzögerung bis zum Öffnen, Favoriten, geerbte Member gruppieren,
//   Zweig varianter Record-Felder, Geltungsbereich des Listenmodus, Schreibweise korrigieren und Platzhalter im
//   Parameter-Hint (TDpccFixedSettings, dpcc.Core.Settings.CompletionView). Die Vorschau im Editor gibt es nicht mehr.
// Alle übrigen früheren Namen (Reiter Editor, Befehle, Debuggen, Willkommensseite …, Tasten, Modul-Schalter,
// experimentelle Schalter, Einstellungsverlauf) liest und schreibt dpcc nicht mehr; vorhandene Werte bleiben in der
// Registry liegen und wirken nicht.

interface

uses
  System.Generics.Collections,
  dpcc.Core.Settings.Plugin.Store,
  dpcc.Core.Style.Look;

const
  /// <summary>Wie TDpccListModes.cModeNames (#497); Settings darf Completion nicht einbinden, der Test prüft
  /// Gleichheit.</summary>
  cCompletionListModeNames: array[0..2] of string = ('filter', 'all', 'rest');

type
  /// <summary>Ablage für Einstellungen (dpcc.Core.Settings.Plugin.Store).</summary>
  IDpccSettingsStore = dpcc.Core.Settings.Plugin.Store.IDpccSettingsStore;

  TDpccPluginSettings = record
  private
    /// <summary>Die gespeicherten Werte über AIo, jeder unter seinem Registry-Namen (Schlüssel der Doku dahinter).
    /// </summary>
    procedure Exchange(const AIo: TDpccSettingsExchange);
  public const
    cMinVisibleRows = 5;
    cMaxVisibleRows = 20;
    cMinListWidth = 240;
    cMaxListWidth = 720;
    /// <summary>Zeichen des Bezeichners, ab denen Tippen die Liste öffnet (L5, completion.autoMinChars); 0 = nie.
    /// Wie TDpccAutoOpen.cDefaultMinChars bzw. cMaxMinChars (der Test prüft Gleichheit).</summary>
    cDefaultAutoMinChars = 0;
    cMaxAutoMinChars = 10;
    /// <summary>Wie THintSettings.cMaxXmlDocLines des Servers.</summary>
    cMaxXmlDocLines = 50;
  public
    /// <summary>Hauptschalter (#407, completion.enabled): aus = eingebaute Code Insight der IDE.</summary>
    Enabled: Boolean;
    /// <summary>Beim Tippen eines Bezeichners ohne Punkt davor öffnet die Liste erst ab so vielen Zeichen
    /// (L5, completion.autoMinChars); 0 = Tippen öffnet nie. Strg+Leertaste gilt immer.</summary>
    AutoMinChars: Integer;
    /// <summary>Beim Tippen nur Treffer (filter), alle Einträge mit Treffern oben (all) oder Treffer und darunter
    /// gedämpft der Rest (rest) (completion.listMode, #497).</summary>
    CompletionListMode: string;
    /// <summary>Sichtbare Zeilen der Liste (#413, completion.visibleRows).</summary>
    VisibleRows: Integer;
    /// <summary>Von Hand gezogene Breite der Liste, 0 = automatisch (#416, completion.listWidth).</summary>
    ListWidth: Integer;
    /// <summary>Lernende Gewichtung (#418, completion.learning).</summary>
    Learning: Boolean;
    /// <summary>Klammern beim Übernehmen von Methoden (#430, completion.autoParentheses).</summary>
    AutoParentheses: Boolean;
    /// <summary>Übernehmen über "(", ";" und "." (#429, completion.commitCharacters).</summary>
    CommitCharacters: Boolean;
    /// <summary>Unit beim Übernehmen automatisch in uses eintragen (#180, completion.autoUses).</summary>
    AutoUses: Boolean;
    /// <summary>Parameter-Hint bei "(" und "," (#436, completion.parameterHints).</summary>
    ParameterHints: Boolean;
    /// <summary>Eigener Tooltip beim Verweilen über Bezeichnern (#442, editor.hoverTooltip).</summary>
    HoverTooltip: Boolean;
    /// <summary>Werte im Tooltip beim Debuggen (#891, debug.hoverValues); hängt nur an dieser Option (und auf der
    /// Seite am eigenen Tooltip), an keinem Modul-Schalter.</summary>
    DebugHoverValues: Boolean;
    /// <summary>Darstellung der Popups (LOOK1, editor.popupLook): intensiv, dezent (Vorgabe) oder unscheinbar. In der
    /// Registry als Text 'intense' | 'subtle' | 'plain' (DpccLookLevelToId); Unbekanntes oder Fehlendes ergibt die
    /// Vorgabe. Gilt für die Fenster von dpcc, nicht für die der IDE.</summary>
    PopupLook: TDpccLookLevel;
    /// <summary>index.extraSourceFolders (L2): zusätzliche Quellordner, durch ";" getrennt; Vorgabe leer. Liegt in
    /// settings.json.</summary>
    IndexExtraSourceFolders: string;
    /// <summary>hints.xmlDocMaxLines: Zeilen des XMLDoc-Texts im Tooltip, 0 = alle. Nur gelesen (settings.json).
    /// </summary>
    XmlDocMaxLines: Integer;
    /// <summary>Namen im Diagnoseprotokoll (#1478, diagnostics.log.names): Registry-Schalter für den Support, nur
    /// gelesen.</summary>
    LogNames: Boolean;
    class function Defaults: TDpccPluginSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Vorgaben, darüber die gespeicherten und die nur gelesenen Werte aus AStore.</summary>
    procedure Load(const AStore: IDpccSettingsStore);
    /// <summary>Schreibt genau die gespeicherten Werte (StoredNames) nach AStore, sonst nichts.</summary>
    procedure Save(const AStore: IDpccSettingsStore);
    /// <summary>Namen, die Save schreibt, in der Reihenfolge des Schreibens.</summary>
    class function StoredNames: TArray<string>; static;
    /// <summary>Namen, die Load nur liest.</summary>
    class function ReadOnlyNames: TArray<string>; static;
  end;

  /// <summary>Einstellungen im Arbeitsspeicher (Tests); Namen ohne Groß-/Kleinschreibung wie in der Registry.
  /// </summary>
  IDpccMemorySettingsStore = interface(IDpccSettingsStore)
    ['{8E1F4C62-3A7D-4B95-9C20-5D6E7F8A1B34}']
    function HasInteger(const AName: string): Boolean;
    /// <summary>Alle Namen in der Reihenfolge des ersten Schreibens.</summary>
    function Names: TArray<string>;
    /// <summary>Wert als Text (Zahl bzw. String) für Vergleiche; '' ohne.</summary>
    function Text(const AName: string): string;
  end;

  TDpccMemorySettingsStore = class(TInterfacedObject, IDpccSettingsStore, IDpccMemorySettingsStore)
  private
    FIntegers: TDictionary<string, Integer>;
    FStrings: TDictionary<string, string>;
    FNames: TList<string>;
    procedure Remember(const AName: string);
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
    function HasInteger(const AName: string): Boolean;
    function Names: TArray<string>;
    function Text(const AName: string): string;
    /// <summary>Speicher mit den Werten, die ASettings.Save schreibt.</summary>
    class function FromSettings(const ASettings: TDpccPluginSettings): IDpccMemorySettingsStore; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TDpccPluginSettings }

class function TDpccPluginSettings.Defaults: TDpccPluginSettings;
begin
  Result.Enabled := True;
  Result.AutoMinChars := cDefaultAutoMinChars;
  Result.CompletionListMode := cCompletionListModeNames[0];
  Result.VisibleRows := 9;
  Result.ListWidth := 0;
  Result.Learning := True;
  Result.AutoParentheses := True;
  Result.CommitCharacters := True;
  Result.AutoUses := True;
  Result.ParameterHints := True;
  Result.HoverTooltip := True;
  Result.DebugHoverValues := True;
  Result.PopupLook := cDpccLookLevelDefault;
  Result.IndexExtraSourceFolders := '';
  Result.XmlDocMaxLines := 0;
  Result.LogNames := False;
end;

procedure TDpccPluginSettings.Normalize;
begin
  AutoMinChars := EnsureRange(AutoMinChars, 0, cMaxAutoMinChars);
  CompletionListMode := Choice(CompletionListMode, cCompletionListModeNames);
  VisibleRows := EnsureRange(VisibleRows, cMinVisibleRows, cMaxVisibleRows);
  if ListWidth <> 0 then
  begin
    ListWidth := EnsureRange(ListWidth, cMinListWidth, cMaxListWidth);
  end;
  XmlDocMaxLines := EnsureRange(XmlDocMaxLines, 0, cMaxXmlDocLines);
  // Nur über eine Typumwandlung außerhalb der Aufzählung möglich: dann die Vorgabe.
  if not InRange(Integer(Ord(PopupLook)), Ord(Low(TDpccLookLevel)), Ord(High(TDpccLookLevel))) then
  begin
    PopupLook := cDpccLookLevelDefault;
  end;
end;

procedure TDpccPluginSettings.Exchange(const AIo: TDpccSettingsExchange);
var
  mPopupLook: string;
begin
  AIo.Flag('Enabled', Enabled); // completion.enabled
  AIo.Number('AutoMinChars', AutoMinChars); // completion.autoMinChars
  AIo.Text('CompletionListMode', CompletionListMode); // completion.listMode
  AIo.Number('VisibleRows', VisibleRows); // completion.visibleRows
  AIo.Number('ListWidth', ListWidth); // completion.listWidth
  AIo.Flag('Learning', Learning); // completion.learning
  AIo.Flag('AutoParentheses', AutoParentheses); // completion.autoParentheses
  AIo.Flag('CommitCharacters', CommitCharacters); // completion.commitCharacters
  AIo.Flag('AutoUses', AutoUses); // completion.autoUses
  AIo.Flag('ParameterHints', ParameterHints); // completion.parameterHints
  AIo.Flag('HoverTooltip', HoverTooltip); // editor.hoverTooltip
  AIo.Flag('DebugHoverValues', DebugHoverValues); // debug.hoverValues
  // Als Text: Schreiben legt die Kennung ab, Lesen wandelt zurück (Unbekanntes = Vorgabe; fehlt der Wert, bleibt die
  // bisherige Kennung, beim Laden also die Vorgabe).
  mPopupLook := DpccLookLevelToId(PopupLook);
  AIo.Text('PopupLook', mPopupLook); // editor.popupLook
  PopupLook := DpccLookLevelFromId(mPopupLook, cDpccLookLevelDefault);
  AIo.Text('IndexExtraSourceFolders', IndexExtraSourceFolders); // index.extraSourceFolders (settings.json)
end;

procedure TDpccPluginSettings.Load(const AStore: IDpccSettingsStore);
var
  mReader: TDpccSettingsExchange;
begin
  Self := Defaults;
  mReader := TDpccSettingsExchange.Reader(AStore);
  Exchange(mReader);
  // Nur gelesen: Save schreibt sie nicht zurück.
  mReader.Number('XmlDocMaxLines', XmlDocMaxLines); // hints.xmlDocMaxLines (settings.json)
  mReader.Flag('LogNames', LogNames); // diagnostics.log.names
  Normalize;
end;

procedure TDpccPluginSettings.Save(const AStore: IDpccSettingsStore);
begin
  Normalize;
  Exchange(TDpccSettingsExchange.Writer(AStore));
end;

class function TDpccPluginSettings.StoredNames: TArray<string>;
var
  mSettings: TDpccPluginSettings;
begin
  mSettings := Defaults;
  Result := TDpccMemorySettingsStore.FromSettings(mSettings).Names;
end;

class function TDpccPluginSettings.ReadOnlyNames: TArray<string>;
begin
  Result := ['XmlDocMaxLines', 'LogNames'];
end;

{ TDpccMemorySettingsStore }

constructor TDpccMemorySettingsStore.Create;
begin
  inherited Create;
  FIntegers := TDictionary<string, Integer>.Create;
  FStrings := TDictionary<string, string>.Create;
  FNames := TList<string>.Create;
end;

destructor TDpccMemorySettingsStore.Destroy;
begin
  FNames.Free;
  FStrings.Free;
  FIntegers.Free;
  inherited Destroy;
end;

procedure TDpccMemorySettingsStore.Remember(const AName: string);
begin
  if FNames.IndexOf(AName) < 0 then
  begin
    FNames.Add(AName);
  end;
end;

function TDpccMemorySettingsStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  if not FIntegers.TryGetValue(LowerCase(AName), Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TDpccMemorySettingsStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FIntegers.AddOrSetValue(LowerCase(AName), AValue);
  Remember(AName);
end;

function TDpccMemorySettingsStore.ReadString(const AName, ADefault: string): string;
begin
  if not FStrings.TryGetValue(LowerCase(AName), Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TDpccMemorySettingsStore.WriteString(const AName, AValue: string);
begin
  FStrings.AddOrSetValue(LowerCase(AName), AValue);
  Remember(AName);
end;

function TDpccMemorySettingsStore.HasInteger(const AName: string): Boolean;
begin
  Result := FIntegers.ContainsKey(LowerCase(AName));
end;

function TDpccMemorySettingsStore.Names: TArray<string>;
begin
  Result := FNames.ToArray;
end;

function TDpccMemorySettingsStore.Text(const AName: string): string;
var
  mValue: Integer;
begin
  if FIntegers.TryGetValue(LowerCase(AName), mValue) then
  begin
    Result := IntToStr(mValue);
  end
  else if not FStrings.TryGetValue(LowerCase(AName), Result) then
  begin
    Result := '';
  end;
end;

class function TDpccMemorySettingsStore.FromSettings(const ASettings: TDpccPluginSettings): IDpccMemorySettingsStore;
var
  mSettings: TDpccPluginSettings;
begin
  Result := TDpccMemorySettingsStore.Create;
  mSettings := ASettings;
  mSettings.Save(Result);
end;

end.
