unit dpcc.Core.Settings.Plugin;

// Einstellungen des IDE-Plugins (#227), ohne VCL und ohne Registry: Vorgaben, Grenzen, Lesen und Schreiben über
// einen Speicher. Die IDE-Schicht speichert in HKCU\Software\dpcc\IdePlugin, Tests im Arbeitsspeicher
// (TDpccMemorySettingsStore). Breiten in logischen Pixeln (96 dpi, #412).
// Seit OPT2 steht hier nur noch, was wirkt:
// - Seit Stufe 2 von dpcc.LspServer.exe ist der Hauptschalter die Betriebsart (Mode: Aus, Plugin, Server) je
//   Delphi-Version, gespeichert als Text "OperatingMode <Version>"; Enabled ist nur noch abgeleitet (Mode = Plugin)
//   und der frühere DWORD Enabled nur noch gelesen (Überführung, dpcc.Core.Settings.OperatingMode).
// - Gespeichert (OK auf der Seite „dpcc“, gezogene Breite der Liste): der Hauptschalter und die (seit LOG1) vierzehn
//   Optionen der Seite (cPageItems in dpcc.Core.Settings.CompletionView). index.extraSourceFolders liegt in
//   %APPDATA%\dpcc\settings.json (TDpccRoutedSettingsStore, dpcc.Core.Settings.Scopes), alle übrigen in der Registry.
//   Seit LOOK1 auch die Darstellung der Popups (PopupLook, Text 'intense' | 'subtle' | 'plain', dpcc.Core.Style.Look).
//   Seit LOG1 der Schalter „Ablauf protokollieren (Log)“ als DWORD Diagnose: derselbe Registry-Wert, den der Support
//   bisher von Hand setzte (Diagnose = 1); ein so gesetzter Wert gilt weiter und erscheint auf der Seite angehakt.
// - Nur gelesen, nie geschrieben: hints.xmlDocMaxLines (settings.json; der Server liest dieselbe Datei) und der
//   Support-Schalter LogNames (diagnostics.log.names, Registry-DWORD).
// - Fest verdrahtet und deshalb kein Feld mehr: Verzögerung bis zum Öffnen, Favoriten, geerbte Member gruppieren,
//   Zweig varianter Record-Felder, Geltungsbereich des Listenmodus, Schreibweise korrigieren und Platzhalter im
//   Parameter-Hint (TDpccFixedSettings, dpcc.Core.Settings.CompletionView). Die Vorschau im Editor gibt es nicht mehr.
// Alle übrigen früheren Namen (Reiter Editor, Befehle, Debuggen, Willkommensseite …, Tasten, Modul-Schalter,
// experimentelle Schalter, Einstellungsverlauf) liest und schreibt dpcc nicht mehr; vorhandene Werte bleiben in der
// Registry liegen und wirken nicht.
// Seit CI-OPT zwei Schalter mehr im Abschnitt Vervollständigung (sechzehn Optionen): „Nach dem Punkt automatisch
// öffnen“ (DWORD OpenAfterDot, nur Plugin) und „Reservierte Wörter in der Liste zeigen“ (CompletionKeywords, liegt als
// completion.keywords in settings.json, der Server liest denselben Wert). Ihre Startwerte übernimmt dpcc einmal aus
// den Code-Insight-Optionen der IDE (TDpccIdeStartValues in dpcc.Core.Settings.IdeCheck); was schon übernommen ist,
// halten die Merker „IdeAdopted …“ fest. Sie schreibt nur SaveAdoption, nie Save (sie stehen nicht auf der Seite).

interface

uses
  System.Generics.Collections,
  dpcc.Core.Settings.Plugin.Store,
  dpcc.Core.Settings.OperatingMode,
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
    function GetEnabled: Boolean;
    procedure SetEnabled(AValue: Boolean);
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
    /// <summary>Registry-Namen der beiden Schalter aus CI-OPT (CompletionKeywords liegt in settings.json).</summary>
    cOpenAfterDotName = 'OpenAfterDot';
    cKeywordsName = 'CompletionKeywords';
    /// <summary>Anfang der Merker „aus der IDE übernommen“ (DWORD 1): "IdeAdopted OpenAfterDot",
    /// "IdeAdopted CompletionKeywords" (je Schalter, für alle Delphi-Versionen) und "IdeAdopted &lt;Version&gt;
    /// IdeFeatures" (je Version: Funktionen der IDE in den Satz von dpcc übernommen).</summary>
    cAdoptedPrefix = 'IdeAdopted ';
    cAdoptedFeatures = 'IdeFeatures';
  public
    /// <summary>Betriebsart dieser Delphi-Version (Aus, Plugin, Server; dpcc.Core.Settings.OperatingMode), in der
    /// Registry als Text unter "OperatingMode &lt;IdeVersion&gt;". Fehlt er, gilt beim Laden der frühere gemeinsame
    /// DWORD Enabled (0 → Aus, sonst Plugin; ohne Wert Plugin), und ModeFromLegacy ist gesetzt.</summary>
    Mode: TDpccOperatingMode;
    /// <summary>Version der IDE, deren Betriebsart Load und Save lesen bzw. schreiben ("23.0", "37.0"); '' = ohne
    /// Version (Tests). Nicht gespeichert; Load lässt sie stehen.</summary>
    IdeVersion: string;
    /// <summary>Nach Load: Die Betriebsart kam aus dem früheren Enabled (oder der Vorgabe), nicht aus einem eigenen
    /// Wert dieser Version. Nicht gespeichert.</summary>
    ModeFromLegacy: Boolean;
    /// <summary>Nach Load: weder ein eigener Wert dieser Version noch das frühere Enabled, also die Vorgabe nach der
    /// Installation (Plugin). Nicht gespeichert.</summary>
    ModeFromDefault: Boolean;
    /// <summary>Nach „.“ öffnet die Liste von selbst (CI-OPT, DWORD OpenAfterDot); aus: GetCodeInsightType('.')
    /// meldet der IDE keine Code Insight, Strg+Leertaste öffnet weiter. Vorgabe an.</summary>
    OpenAfterDot: Boolean;
    /// <summary>Reservierte Wörter (Schlüsselwörter) in der Liste (CI-OPT, completion.keywords in settings.json);
    /// Vorgabe an.</summary>
    ShowKeywords: Boolean;
    /// <summary>Nach Load: Für OpenAfterDot bzw. completion.keywords stand schon ein Wert im Speicher (dann gilt er,
    /// und die Übernahme aus der IDE liest nichts). Nicht gespeichert.</summary>
    OpenAfterDotStored: Boolean;
    KeywordsStored: Boolean;
    /// <summary>Merker „aus der IDE übernommen“ (nur gelesen; geschrieben von SaveAdoption): die Startwerte von
    /// OpenAfterDot bzw. ShowKeywords (für alle Versionen) und die Funktionen der IDE im Satz von dpcc (je Version
    /// IdeVersion).</summary>
    OpenAfterDotAdopted: Boolean;
    KeywordsAdopted: Boolean;
    IdeFeaturesAdopted: Boolean;
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
    /// <summary>Ablauf protokollieren (LOG1, nur Registry): DWORD Diagnose, Vorgabe aus. Derselbe Wert wie das
    /// früher nur von Hand gesetzte Diagnose = 1 (jeder Wert ungleich 0 gilt als an); schreibt die Kette jeder Aktion
    /// ins Diagnoseprotokoll (dpcc.Core.Diagnostics.Flow).</summary>
    Diagnose: Boolean;
    /// <summary>hints.xmlDocMaxLines: Zeilen des XMLDoc-Texts im Tooltip, 0 = alle. Nur gelesen (settings.json).
    /// </summary>
    XmlDocMaxLines: Integer;
    /// <summary>Namen im Diagnoseprotokoll (#1478, diagnostics.log.names): Registry-Schalter für den Support, nur
    /// gelesen.</summary>
    LogNames: Boolean;
    /// <summary>Früherer Hauptschalter, jetzt abgeleitet: an genau in der Betriebsart Plugin (nur dann arbeiten der
    /// eingebaute Server und die Fenster von dpcc). Setzen auf True wählt Plugin, auf False aus Plugin heraus Aus
    /// (Server bleibt Server).</summary>
    property Enabled: Boolean read GetEnabled write SetEnabled;
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
    /// <summary>Name eines Merkers „aus der IDE übernommen“: AName = cOpenAfterDotName, cKeywordsName (für alle
    /// Versionen) bzw. cAdoptedFeatures (je Version AVersion).</summary>
    class function AdoptedName(const AName: string; const AVersion: string = ''): string; static;
    /// <summary>Die übernommenen Startwerte (OpenAfterDot, ShowKeywords) und die gesetzten Merker „IdeAdopted …“
    /// nach AStore; sonst nichts (die übrigen Werte schreibt nur Save mit OK).</summary>
    procedure SaveAdoption(const AStore: IDpccSettingsStore);
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
  Result.Mode := TDpccOperatingModes.cDefault;
  Result.IdeVersion := '';
  Result.ModeFromLegacy := False;
  Result.ModeFromDefault := False;
  Result.OpenAfterDot := True;
  Result.ShowKeywords := True;
  Result.OpenAfterDotStored := False;
  Result.KeywordsStored := False;
  Result.OpenAfterDotAdopted := False;
  Result.KeywordsAdopted := False;
  Result.IdeFeaturesAdopted := False;
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
  Result.Diagnose := False;
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
  if not InRange(Integer(Ord(Mode)), Ord(Low(TDpccOperatingMode)), Ord(High(TDpccOperatingMode))) then
  begin
    Mode := TDpccOperatingModes.cDefault;
  end;
end;

function TDpccPluginSettings.GetEnabled: Boolean;
begin
  Result := Mode = TDpccOperatingMode.Plugin;
end;

procedure TDpccPluginSettings.SetEnabled(AValue: Boolean);
begin
  if AValue then
  begin
    Mode := TDpccOperatingMode.Plugin;
  end
  else if Mode = TDpccOperatingMode.Plugin then
  begin
    Mode := TDpccOperatingMode.Off;
  end;
end;

procedure TDpccPluginSettings.Exchange(const AIo: TDpccSettingsExchange);
const
  // Marke „kein Wert“ beim Lesen (kein gültiger Text und keine sinnvolle Zahl).
  cMissingText = #0;
  cMissingNumber = Low(Integer);
var
  mPopupLook, mMode: string;
  mLegacy, mStored: Integer;
begin
  // Betriebsart je Delphi-Version; beim Lesen ohne eigenen Wert die Überführung aus dem früheren Enabled. Enabled
  // selbst schreibt dpcc nicht mehr (andere Versionen ohne eigenen Wert überführen ihn weiter so, wie er war).
  if AIo.Writing then
  begin
    mMode := TDpccOperatingModes.IdOf(Mode);
    AIo.Text(TDpccOperatingModes.ValueName(IdeVersion), mMode); // operatingMode je Version
  end
  else
  begin
    mMode := cMissingText;
    AIo.Text(TDpccOperatingModes.ValueName(IdeVersion), mMode);
    mLegacy := cMissingNumber;
    AIo.Number(TDpccOperatingModes.cLegacyName, mLegacy);
    Mode := TDpccOperatingModes.Resolve(mMode <> cMissingText, mMode, mLegacy <> cMissingNumber, mLegacy,
      ModeFromLegacy);
    ModeFromDefault := ModeFromLegacy and (mLegacy = cMissingNumber);
  end;
  // CI-OPT: Beim Lesen auch, ob ein Wert da war (dann übernimmt dpcc keinen Startwert aus der IDE).
  if AIo.Writing then
  begin
    AIo.Flag(cOpenAfterDotName, OpenAfterDot); // nur Plugin, kein Schlüssel in settings.json
  end
  else
  begin
    mStored := cMissingNumber;
    AIo.Number(cOpenAfterDotName, mStored);
    OpenAfterDotStored := mStored <> cMissingNumber;
    if OpenAfterDotStored then
    begin
      OpenAfterDot := mStored <> 0;
    end;
  end;
  AIo.Number('AutoMinChars', AutoMinChars); // completion.autoMinChars
  AIo.Text('CompletionListMode', CompletionListMode); // completion.listMode
  AIo.Number('VisibleRows', VisibleRows); // completion.visibleRows
  AIo.Number('ListWidth', ListWidth); // completion.listWidth
  if AIo.Writing then
  begin
    AIo.Flag(cKeywordsName, ShowKeywords); // completion.keywords (settings.json)
  end
  else
  begin
    mStored := cMissingNumber;
    AIo.Number(cKeywordsName, mStored);
    KeywordsStored := mStored <> cMissingNumber;
    if KeywordsStored then
    begin
      ShowKeywords := mStored <> 0;
    end;
  end;
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
  // Zuletzt wie auf der Seite (Abschnitt IDE); derselbe DWORD wie das frühere Diagnose = 1 von Hand.
  AIo.Flag('Diagnose', Diagnose); // nur Registry, kein Schlüssel in settings.json
end;

procedure TDpccPluginSettings.Load(const AStore: IDpccSettingsStore);
var
  mReader: TDpccSettingsExchange;
  mVersion: string;
begin
  // Die Version bestimmt, welche Betriebsart gilt; sie gehört dem Aufrufer und bleibt.
  mVersion := IdeVersion;
  Self := Defaults;
  IdeVersion := mVersion;
  mReader := TDpccSettingsExchange.Reader(AStore);
  Exchange(mReader);
  // Nur gelesen: Save schreibt sie nicht zurück.
  mReader.Number('XmlDocMaxLines', XmlDocMaxLines); // hints.xmlDocMaxLines (settings.json)
  mReader.Flag('LogNames', LogNames); // diagnostics.log.names
  // CI-OPT: Merker der einmaligen Übernahme aus der IDE (schreibt nur SaveAdoption).
  mReader.Flag(AdoptedName(cOpenAfterDotName), OpenAfterDotAdopted);
  mReader.Flag(AdoptedName(cKeywordsName), KeywordsAdopted);
  if IdeVersion <> '' then
  begin
    mReader.Flag(AdoptedName(cAdoptedFeatures, IdeVersion), IdeFeaturesAdopted);
  end;
  Normalize;
end;

procedure TDpccPluginSettings.Save(const AStore: IDpccSettingsStore);
begin
  Normalize;
  Exchange(TDpccSettingsExchange.Writer(AStore));
end;

class function TDpccPluginSettings.AdoptedName(const AName, AVersion: string): string;
begin
  Result := cAdoptedPrefix + AName;
  if AVersion <> '' then
  begin
    Result := cAdoptedPrefix + AVersion + ' ' + AName;
  end;
end;

procedure TDpccPluginSettings.SaveAdoption(const AStore: IDpccSettingsStore);
var
  mWriter: TDpccSettingsExchange;
begin
  Normalize;
  mWriter := TDpccSettingsExchange.Writer(AStore);
  // Wert und Merker zusammen: Ohne Merker liest der nächste Start den Wert erneut aus der IDE.
  if OpenAfterDotAdopted then
  begin
    mWriter.Flag(cOpenAfterDotName, OpenAfterDot);
    mWriter.Flag(AdoptedName(cOpenAfterDotName), OpenAfterDotAdopted);
  end;
  if KeywordsAdopted then
  begin
    mWriter.Flag(cKeywordsName, ShowKeywords);
    mWriter.Flag(AdoptedName(cKeywordsName), KeywordsAdopted);
  end;
  if IdeFeaturesAdopted and (IdeVersion <> '') then
  begin
    mWriter.Flag(AdoptedName(cAdoptedFeatures, IdeVersion), IdeFeaturesAdopted);
  end;
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
  // Enabled: der frühere Hauptschalter, nur noch Quelle der Überführung der Betriebsart. Die Merker der Übernahme aus
  // der IDE (CI-OPT) schreibt nur SaveAdoption; der Merker je Version ("IdeAdopted <Version> IdeFeatures") hängt an
  // IdeVersion und steht deshalb nicht in dieser Liste.
  Result := ['XmlDocMaxLines', 'LogNames', TDpccOperatingModes.cLegacyName, AdoptedName(cOpenAfterDotName),
    AdoptedName(cKeywordsName)];
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
