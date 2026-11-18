unit dpcc.Core.Settings.IdeCheck;

// Betriebsart von dpcc in der IDE und die Code-Insight-Schalter dazu (Auftrag IDECHECK), ohne VCL und ohne Registry.
// Zwei Betriebsarten, die sich ausschließen:
//   - „IDE“: Ein anderer Code-Insight-Anbieter (Vorgabe DelphiLSP) bedient Delphi-Dateien. dpcc ist aus
//     (Hauptschalter), und dpcc dreht zurück, was es selbst an den Schaltern der IDE geändert hatte.
//   - „dpcc“: dpcc ist der Anbieter. Hauptschalter an; dpcc setzt die Schalter, die es braucht (Targets), im
//     Schlüssel seines Option Sets (GetOptionSetName = Borland.EditOptions.Pascal) und in InsightGlobalOptions.
// Wer entscheidet: beim Start von Delphi der Wert "Insight Manager" (TDpccIdeContextTrigger.Start); der Hauptschalter
// der Optionsseite mit OK (MasterOn stellt den Anbieter auf dpcc, MasterOff zurück auf den gemerkten bzw. DelphiLSP).
// Jede Änderung hält ein Merker fest (geschriebener Wert und Wert davor, TDpccIdeMarker unter
// HKCU\Software\dpcc\IdePlugin, je Version). Zurückgedreht wird nur, was noch so steht, wie dpcc es geschrieben hat;
// hat der Nutzer oder die IDE den Wert seither geändert, bleibt er, und nur der Merker entfällt.
// Versionsneutral für Delphi 12 (BDS 23.0) und Delphi 13 (BDS 37.0); Orte relativ zum Basisschlüssel der IDE
// (IOTAServices.GetBaseRegistryKey):
//   - Anbieter: Editor\Source Options\Borland.EditOptions.Pascal, Wert "Insight Manager"
//     (Borland.CodeInsight.LSP.Pascal = DelphiLSP, dpcc.CodeInsight = dpcc, die IDString des Managers);
//   - DelphiLSP: Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal, unter 12 und 13 gleich (Delphi 12
//     hatte auf dem Prüfrechner gar kein Borland.EditOptions.Pascal; den früheren Ersatz "Ort der Version"
//     Borland.EditOptions.Pascal unter 23.0 gibt es seit D12-PREP nicht mehr, das ist das Option Set von dpcc);
//   - dpcc: Code Insight\Borland.EditOptions.Pascal (Option Set des dpcc-Managers);
//   - InsightGlobalOptions: AutoInvokeCompletionOnParameterInsight.
// Ein fehlender Wert gilt mit der Vorgabe der IDE (an bzw. -1); fehlt der geprüfte Schlüssel ganz, ist das kein
// Fehler, sondern ein Hinweis „Schlüssel fehlt (IDE-Vorgabe)“. Evaluate prüft nur und liefert Befunde (für das
// Protokoll und die Optionsseite); TDpccIdeContext.Plan liefert die Schreibaktionen, die die IDE-Schicht
// (dpcc.IDE.Foundation.InsightSwitch) ausführt. Die IDE liest die Werte beim Start; ein Wechsel wirkt nach dem
// nächsten Start von Delphi.

interface

uses
  dpcc.Core.Settings.Plugin;

{$SCOPEDENUMS ON}

type
  /// <summary>Gewählter Code-Insight-Anbieter für Delphi-Dateien.</summary>
  TDpccIdeProvider = (Unknown, DelphiLsp, Dpcc, Other);

  /// <summary>Ergebnis einer Prüfregel: passt, weicht ab oder nur ein Hinweis.</summary>
  TDpccIdeSeverity = (Ok, Deviation, Hint);

  /// <summary>Betriebsart: IDE = ein anderer Anbieter, dpcc aus; Dpcc = dpcc ist Anbieter und an.</summary>
  TDpccIdeMode = (Ide, Dpcc);

  /// <summary>Anlass: Start von Delphi (auch Abgleich nach OK ohne Wechsel des Hauptschalters), Hauptschalter mit OK
  /// ein- bzw. ausgeschaltet.</summary>
  TDpccIdeContextTrigger = (Start, MasterOn, MasterOff);

  /// <summary>Art eines Werts für den Vergleich.</summary>
  TDpccIdeValueKind = (Flag, Number, Text);

  /// <summary>Ein gelesener Wert der IDE-Registry.</summary>
  TDpccIdeRegValue = record
    /// <summary>Schlüssel relativ zum Basisschlüssel, z. B. "Code Insight\Borland.EditOptions.Pascal".</summary>
    Key: string;
    Name: string;
    /// <summary>Text des Werts; bei REG_DWORD die Zahl dezimal.</summary>
    Value: string;
    IsDword: Boolean;
  end;

  /// <summary>Was dpcc an einem Wert der IDE geändert hat.</summary>
  TDpccIdeMarker = record
    Key: string;
    Name: string;
    /// <summary>Von dpcc geschriebener Wert.</summary>
    Written: string;
    /// <summary>Gab es den Wert vorher? Sonst löscht der Rückweg ihn.</summary>
    OriginalExists: Boolean;
    Original: string;
    /// <summary>Name des Merkers unter HKCU\Software\dpcc\IdePlugin.</summary>
    StoreName: string;
  end;

  /// <summary>Die dpcc-Einstellungen, von denen die Regeln abhängen.</summary>
  TDpccIdeDpccState = record
    Enabled: Boolean;
    HoverTooltip: Boolean;
    DebugHoverValues: Boolean;
    AutoMinChars: Integer;
    class function From(const ASettings: TDpccPluginSettings): TDpccIdeDpccState; static;
  end;

  /// <summary>Eingabe: Basisschlüssel, Anbieter, gelesene Werte (nur vorhandene), Schlüssel, Merker, dpcc-Stand.
  /// </summary>
  TDpccIdeCheckInput = record
    /// <summary>Basisschlüssel der IDE unter HKEY_CURRENT_USER, z. B. "Software\Embarcadero\BDS\37.0".</summary>
    BaseKey: string;
    /// <summary>Kennung des gewählten Anbieters ("Insight Manager"); '' = nicht ermittelt.</summary>
    ProviderId: string;
    Values: TArray<TDpccIdeRegValue>;
    /// <summary>Schlüssel, die es gibt (auch ohne einen der gelesenen Werte).</summary>
    Keys: TArray<string>;
    /// <summary>Merker dieser Version.</summary>
    Markers: TArray<TDpccIdeMarker>;
    Dpcc: TDpccIdeDpccState;
    procedure Add(const AKey, AName, AValue: string; AIsDword: Boolean = False);
    /// <summary>Den Schlüssel AKey gibt es.</summary>
    procedure AddKey(const AKey: string);
    /// <summary>Wert setzen (als Zeichenkette) bzw. löschen; für Tests und um einen Plan nachzuvollziehen.</summary>
    procedure SetValue(const AKey, AName, AValue: string);
    procedure RemoveValue(const AKey, AName: string);
    function TryGet(const AKey, AName: string; out AValue: TDpccIdeRegValue): Boolean;
    function TryGetMarker(const AKey, AName: string; out AMarker: TDpccIdeMarker): Boolean;
    /// <summary>Gibt es AKey (AddKey) oder wurde darunter ein Wert gelesen?</summary>
    function HasKey(const AKey: string): Boolean;
  end;

  /// <summary>Befund einer Prüfregel.</summary>
  TDpccIdeFinding = record
    /// <summary>Anzeigename wie in den Optionen der IDE (aktuelle Sprache).</summary>
    Caption: string;
    Key: string;
    /// <summary>Wertname; '' bei einem Befund zum Schlüssel selbst.</summary>
    ValueName: string;
    Exists: Boolean;
    Actual: string;
    /// <summary>Geltender Wert: gelesen oder Vorgabe der IDE.</summary>
    Effective: string;
    /// <summary>Soll; '' bei einem Hinweis.</summary>
    Expected: string;
    Reason: string;
    Severity: TDpccIdeSeverity;
  end;

  TDpccIdeCheckResult = record
    BaseKey: string;
    ProviderId: string;
    Provider: TDpccIdeProvider;
    /// <summary>Betriebsart nach dem Hauptschalter (an = dpcc).</summary>
    Mode: TDpccIdeMode;
    /// <summary>Geprüfter Ort der Code-Insight-Schalter (relativ zum Basisschlüssel).</summary>
    ActiveKey: string;
    ActiveKeyMissing: Boolean;
    Findings: TArray<TDpccIdeFinding>;
    function Count(ASeverity: TDpccIdeSeverity): Integer;
    /// <summary>Wertnamen der Abweichungen in der Reihenfolge der Befunde.</summary>
    function DeviationNames: TArray<string>;
    /// <summary>Eine Zeile (aktuelle Sprache), z. B. „1 Abweichung: Auto Code Completions“.</summary>
    function Summary: string;
    /// <summary>Zeile fürs Protokoll (nie übersetzt), z. B. „IDE-Einstellungen: 1 Abweichung: Auto Code Completions;
    /// …“.</summary>
    function LogLine: string;
    /// <summary>Alle Befunde als Text (aktuelle Sprache): Ist → Soll und Grund.</summary>
    function Report: string;
  end;

  /// <summary>Ein Wert, den dpcc in der Betriebsart dpcc braucht.</summary>
  TDpccIdeTarget = record
    Key: string;
    Name: string;
    Value: string;
    Kind: TDpccIdeValueKind;
    Caption: string;
    Reason: string;
  end;

  /// <summary>Eine Schreibaktion in der Registry der IDE.</summary>
  TDpccIdeWrite = record
    Key: string;
    Name: string;
    /// <summary>True: Wert löschen; sonst Value als Zeichenkette (REG_SZ) schreiben, wie die IDE es tut.</summary>
    Delete: Boolean;
    Value: string;
  end;

  TDpccIdeContextPlan = record
    Trigger: TDpccIdeContextTrigger;
    Mode: TDpccIdeMode;
    ProviderBefore: string;
    ProviderAfter: string;
    /// <summary>Hauptschalter danach.</summary>
    Enabled: Boolean;
    EnabledChanged: Boolean;
    Writes: TArray<TDpccIdeWrite>;
    /// <summary>Zu schreibende Merker (StoreName und Inhalt).</summary>
    MarkerWrites: TArray<TDpccIdeMarker>;
    /// <summary>Zu löschende Merker (StoreName).</summary>
    MarkerDeletes: TArray<string>;
    /// <summary>Wertnamen, die dpcc gesetzt bzw. zurückgedreht hat, und solche, die seit dpcc fremd geändert sind
    /// (bleiben, nur der Merker entfällt).</summary>
    SetNames: TArray<string>;
    RestoredNames: TArray<string>;
    KeptNames: TArray<string>;
    /// <summary>Der Anbieter wurde umgestellt: wirkt nach dem Neustart von Delphi.</summary>
    ProviderChanged: Boolean;
    /// <summary>Hinweis für das Meldungsfenster (aktuelle Sprache); '' ohne.</summary>
    Notice: string;
    function HasChanges: Boolean;
    /// <summary>Zeile fürs Protokoll (nie übersetzt), z. B. „IDE-Kontext (Start): Borland.CodeInsight.LSP.Pascal →
    /// dpcc aus, …; zurückgedreht: Help Insight“.</summary>
    function LogLine: string;
    /// <summary>Schreibaktionen auf AInput anwenden (Werte, Anbieter, Merker, Hauptschalter), wie die IDE-Schicht sie
    /// ausführt.</summary>
    procedure ApplyTo(var AInput: TDpccIdeCheckInput);
  end;

  TDpccIdeCheck = class
  public const
    cSourceOptionsKey = 'Editor\Source Options\Borland.EditOptions.Pascal';
    cProviderValue = 'Insight Manager';
    cDelphiLspId = 'Borland.CodeInsight.LSP.Pascal';
    /// <summary>IDString des dpcc-Managers (cManagerId in dpcc.IDE.CodeInsight.Manager).</summary>
    cDpccId = 'dpcc.CodeInsight';
    cCodeInsightRoot = 'Code Insight';
    cEditOptionsPrefix = 'Borland.EditOptions.';
    cLspKey = 'Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal';
    /// <summary>Option Set des dpcc-Managers (GetOptionSetName), unter Delphi 12 und 13 gleich.</summary>
    cPascalKey = 'Code Insight\Borland.EditOptions.Pascal';
    cGlobalKey = 'InsightGlobalOptions';
    cAutoCodeCompletions = 'Auto Code Completions';
    cAutoInvokeDelay = 'Auto Invoke Delay';
    cAutoCodeParameters = 'Auto Code Parameters';
    cDeclarationInformation = 'Declaration Information';
    cHelpInsight = 'Help Insight';
    cToolTipWatches = 'ToolTip Watches';
    cErrorInsight = 'Error Insight';
    cAutoInvokeOnParameterInsight = 'AutoInvokeCompletionOnParameterInsight';
  public
    class function ProviderOf(const AId: string): TDpccIdeProvider; static;
    /// <summary>Ort der Schalter eines Anbieters: Code Insight\Borland.EditOptions.&lt;AId&gt;.</summary>
    class function ProviderKey(const AId: string): string; static;
    /// <summary>Schlüssel, deren Code-Insight-Werte die IDE-Schicht lesen soll (ohne Doppel).</summary>
    class function KeysToRead(const AProviderId: string): TArray<string>; static;
    /// <summary>Wertnamen unter Code Insight\…, die die Regeln brauchen.</summary>
    class function CodeInsightValueNames: TArray<string>; static;
    /// <summary>Ort, den die IDE für den gewählten Anbieter liest (siehe Kopf der Unit).</summary>
    class function ActiveKey(const AInput: TDpccIdeCheckInput): string; static;
    /// <summary>Prüfen ohne zu ändern: mit Hauptschalter an gegen Targets, sonst die Regeln für DelphiLSP.
    /// </summary>
    class function Evaluate(const AInput: TDpccIdeCheckInput): TDpccIdeCheckResult; static;
  end;

  TDpccIdeContext = class
  public const
    /// <summary>Anfang der Merker-Namen: "IdeSet &lt;Version&gt; &lt;Schlüssel&gt;\&lt;Wert&gt;".</summary>
    cMarkerPrefix = 'IdeSet ';
  public
    /// <summary>Werte, die dpcc in der Betriebsart dpcc setzt, nach den dpcc-Einstellungen: Anbieter = dpcc, Auto Code
    /// Completions = True, Auto Invoke Delay = -1, Auto Code Parameters = True, bei eigenem Tooltip Help Insight und
    /// Declaration Information = False, mit Werten beim Debuggen ToolTip Watches = False,
    /// AutoInvokeCompletionOnParameterInsight = False.</summary>
    class function Targets(const ADpcc: TDpccIdeDpccState): TArray<TDpccIdeTarget>; static;
    /// <summary>Passt der Wert (fehlend: Vorgabe der IDE) zu ATarget?</summary>
    class function Matches(AExists: Boolean; const AValue: TDpccIdeRegValue; const ATarget: string;
      AKind: TDpccIdeValueKind): Boolean; static;
    /// <summary>Schreibaktionen für den Anlass ATrigger (siehe Kopf der Unit).</summary>
    class function Plan(const AInput: TDpccIdeCheckInput; ATrigger: TDpccIdeContextTrigger): TDpccIdeContextPlan;
      static;
    /// <summary>Name des Merkers für AKey\AName unter der Version von ABaseKey.</summary>
    class function MarkerName(const ABaseKey, AKey, AName: string): string; static;
    /// <summary>Inhalt eines Merkers: geschriebener Wert, Tab, "=" und Wert davor bzw. "-" ohne.</summary>
    class function EncodeMarker(const AMarker: TDpccIdeMarker): string; static;
    /// <summary>Merker aus Name und Inhalt; False, wenn der Name nicht zu dieser Version gehört oder der Inhalt nicht
    /// passt.</summary>
    class function DecodeMarker(const ABaseKey, AStoreName, AText: string; out AMarker: TDpccIdeMarker): Boolean;
      static;
    /// <summary>Älterer Merker (DWORD, vor IDECHECK) für Help Insight bzw. ToolTip Watches: "IdeHelpInsightDisabled
    /// &lt;Version&gt; &lt;Unterschlüssel&gt;" oder ohne Version und Ort (nur ab Delphi 13, Ort von DelphiLSP). Wert
    /// ungleich 0 = dpcc hat den Schalter von True auf False gestellt.</summary>
    class function DecodeLegacyMarker(const ABaseKey, AStoreName: string; AValue: Int64;
      out AMarker: TDpccIdeMarker): Boolean; static;
    /// <summary>Statuszeilen für die Optionsseite (aktuelle Sprache): Betriebsart und Anbieter, was dpcc gesetzt
    /// hat, Ergebnis der Prüfung.</summary>
    class function StatusText(const AInput: TDpccIdeCheckInput): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  dpcc.Core.Localization.Language,
  dpcc.Core.Editor.CodeInsightKeys;

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TIdeCheckText = (CaptionProvider, CaptionAutoCompletions, CaptionAutoInvokeDelay, CaptionAutoParameters,
    CaptionDeclaration, CaptionHelpInsight, CaptionTooltipWatches, CaptionErrorInsight, CaptionParameterInsight,
    ReasonProvider, ReasonAutoCompletions, ReasonAutoInvokeDelay, ReasonAutoParameters, ReasonDeclaration,
    ReasonHelpInsight, ReasonTooltipWatches, ReasonErrorInsight, ReasonParameterInsight, ReasonProviderDpcc,
    ReasonProviderUnknown, ReasonProviderOther, CaptionKey, ReasonKeyMissing, KeyMissing, ProviderNameUnknown,
    MissingValue, SeverityOk, SeverityDeviation, SeverityHint, ReportProvider, ReportKey, ReportActualExpected,
    ReportActual, ReportReason, SummaryNone, SummaryOne, SummaryMore, SummaryHintOne, SummaryHintMore, StatusModeDpcc,
    StatusModeIde, StatusPendingDpcc, StatusPendingIde, StatusSet, StatusSetNone, NoticeSwitchedToDpcc,
    NoticeSwitchedToIde, NoticeProviderLost);

const
  cTexts: array[TDpccLanguage, TIdeCheckText] of string = (
    ('Code-Insight-Anbieter für Delphi',
     'Code-Vervollständigung: Automatisch aufrufen',
     'Code-Vervollständigung: Verzögerung beim Tippen',
     'Code-Parameter: Automatisch aufrufen',
     'Kurzhinweis Symbol-Insight',
     'Kurzhinweis Hilfe-Insight',
     'Kurzhinweis Ausdrucksauswertung',
     'Error Insight',
     'Code-Vervollständigung mit dem Parameter-Insight öffnen',
     'Hauptschalter an: dpcc bedient Delphi-Dateien selbst.',
     'Aus: Nach „.“ öffnet keine Liste.',
     'Ab 0 öffnet die IDE beim Tippen nach dieser Verzögerung zusätzlich ihre eigene Liste.',
     'Aus: Der Parameter-Hint öffnet bei „(“ und „,“ nicht von selbst.',
     'An: Die IDE zeigt ihren Kurzhinweis neben dem dpcc-Tooltip.',
     'An: Die IDE zeigt Help Insight neben dem dpcc-Tooltip.',
     'An: Die IDE zeigt beim Debuggen ihren Wert-Tooltip neben dem dpcc-Hover.',
     'Aus: Die Fehlermarkierungen von DelphiLSP fehlen im Editor.',
     'An: Die IDE öffnet mit dem Parameter-Hint zusätzlich ihre eigene Liste.',
     'dpcc ist der Code-Insight-Anbieter: Error Insight fehlt, Strg+Klick läuft über dpcc. Zurück zu DelphiLSP: ' +
       'Hauptschalter aus oder in den Optionen der IDE DelphiLSP wählen.',
     'Der gewählte Anbieter ließ sich nicht ermitteln; geprüft wird der Ort von DelphiLSP.',
     'Gewählt ist ein anderer Anbieter (%s); dpcc ist aus.',
     'Ort der Code-Insight-Schalter',
     'Der Schlüssel fehlt; die IDE nutzt ihre Vorgaben. Er entsteht, sobald die Code-Insight-Optionen einmal mit ' +
       'OK gespeichert werden.',
     'Schlüssel fehlt (IDE-Vorgabe)',
     'nicht ermittelt',
     'fehlt, Vorgabe %s',
     'passt',
     'abweichend',
     'Hinweis',
     'Anbieter: %s',
     'Geprüfter Ort: %s',
     'Ist: %s → Soll: %s',
     'Ist: %s',
     'Grund: %s',
     'Keine Abweichung (%d Einstellungen geprüft).',
     '1 Abweichung: %s',
     '%d Abweichungen: %s',
     '1 Hinweis',
     '%d Hinweise',
     'Betriebsart dpcc: dpcc ist der Code-Insight-Anbieter (%s).',
     'Betriebsart IDE: Anbieter %s, dpcc ist aus.',
     'Der Anbieter wird beim nächsten Start von Delphi dpcc.',
     'Der Anbieter wird beim nächsten Start von Delphi wieder %s.',
     'Von dpcc gesetzt: %s',
     'Von dpcc gesetzt: nichts',
     'dpcc hat den Code-Insight-Anbieter der IDE auf dpcc umgestellt; wirkt nach dem Neustart von Delphi.',
     'dpcc hat den Code-Insight-Anbieter der IDE wieder auf %s gestellt; wirkt nach dem Neustart von Delphi. Bis ' +
       'dahin ruft die IDE weiter den bisherigen Anbieter.',
     'Der Code-Insight-Anbieter ist nicht mehr dpcc (in den Optionen der IDE geändert oder von der IDE ' +
       'zurückgeschrieben); dpcc ist aus. Zum Einschalten den Hauptschalter der Seite dpcc wieder setzen.'),
    ('Code Insight provider for Delphi',
     'Code completion: Auto invoke',
     'Code completion: Delay while typing',
     'Code parameters: Auto invoke',
     'Tooltip symbol insight',
     'Tooltip help insight',
     'Tooltip expression evaluation',
     'Error Insight',
     'Open code completion with parameter insight',
     'Master switch on: dpcc serves Delphi files itself.',
     'Off: no list opens after “.”.',
     'From 0 on, the IDE additionally opens its own list while typing after this delay.',
     'Off: the parameter hint does not open on “(” and “,” by itself.',
     'On: the IDE shows its tooltip next to the dpcc tooltip.',
     'On: the IDE shows Help Insight next to the dpcc tooltip.',
     'On: while debugging, the IDE shows its value tooltip next to the dpcc hover.',
     'Off: the DelphiLSP error marks are missing in the editor.',
     'On: the IDE additionally opens its own list with the parameter hint.',
     'dpcc is the Code Insight provider: Error Insight is missing, Ctrl+click goes through dpcc. Back to DelphiLSP: ' +
       'master switch off or select DelphiLSP in the IDE options.',
     'The selected provider could not be determined; the DelphiLSP location is checked.',
     'Another provider is selected (%s); dpcc is off.',
     'Location of the Code Insight switches',
     'The key is missing; the IDE uses its defaults. It is created as soon as the Code Insight options are saved ' +
       'with OK once.',
     'key missing (IDE default)',
     'not determined',
     'missing, default %s',
     'ok',
     'differs',
     'note',
     'Provider: %s',
     'Checked location: %s',
     'Current: %s → expected: %s',
     'Current: %s',
     'Reason: %s',
     'No difference (%d settings checked).',
     '1 difference: %s',
     '%d differences: %s',
     '1 note',
     '%d notes',
     'Mode dpcc: dpcc is the Code Insight provider (%s).',
     'Mode IDE: provider %s, dpcc is off.',
     'The provider becomes dpcc at the next start of Delphi.',
     'The provider becomes %s again at the next start of Delphi.',
     'Set by dpcc: %s',
     'Set by dpcc: nothing',
     'dpcc switched the IDE''s Code Insight provider to dpcc; takes effect after restarting Delphi.',
     'dpcc switched the IDE''s Code Insight provider back to %s; takes effect after restarting Delphi. Until then ' +
       'the IDE keeps calling the previous provider.',
     'The Code Insight provider is no longer dpcc (changed in the IDE options or written back by the IDE); dpcc ' +
       'is off. To turn it on, set the master switch on the dpcc page again.'));

function Txt(AId: TIdeCheckText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

function SwitchText(AEnabled: Boolean): string;
begin
  Result := 'False';
  if AEnabled then
  begin
    Result := 'True';
  end;
end;

/// <summary>Schalter aus einem Wert: "True"/"False" wie die IDE sie schreibt, REG_DWORD ungleich 0; sonst ADefault.
/// </summary>
function FlagOf(const AValue: TDpccIdeRegValue; ADefault: Boolean): Boolean;
begin
  if AValue.IsDword then
  begin
    Result := StrToInt64Def(AValue.Value, 0) <> 0;
  end
  else if SameText(Trim(AValue.Value), 'True') then
  begin
    Result := True;
  end
  else if SameText(Trim(AValue.Value), 'False') then
  begin
    Result := False;
  end
  else
  begin
    Result := ADefault;
  end;
end;

/// <summary>An AList anhängen, ohne Doppel.</summary>
procedure AddName(var AList: TArray<string>; const AName: string);
var
  mKnown: string;
begin
  for mKnown in AList do
  begin
    if SameText(mKnown, AName) then
    begin
      Exit;
    end;
  end;
  AList := AList + [AName];
end;

function ProviderName(AProvider: TDpccIdeProvider; const AId: string): string;
begin
  case AProvider of
    TDpccIdeProvider.DelphiLsp:
      Result := 'DelphiLSP';
    TDpccIdeProvider.Dpcc:
      Result := 'dpcc';
    TDpccIdeProvider.Other:
      Result := AId;
  else
    Result := Txt(TIdeCheckText.ProviderNameUnknown);
  end;
end;

{ TDpccIdeDpccState }

class function TDpccIdeDpccState.From(const ASettings: TDpccPluginSettings): TDpccIdeDpccState;
begin
  Result.Enabled := ASettings.Enabled;
  Result.HoverTooltip := ASettings.HoverTooltip;
  Result.DebugHoverValues := ASettings.DebugHoverValues;
  Result.AutoMinChars := ASettings.AutoMinChars;
end;

{ TDpccIdeCheckInput }

procedure TDpccIdeCheckInput.Add(const AKey, AName, AValue: string; AIsDword: Boolean);
var
  mValue: TDpccIdeRegValue;
begin
  mValue.Key := AKey;
  mValue.Name := AName;
  mValue.Value := AValue;
  mValue.IsDword := AIsDword;
  Values := Values + [mValue];
end;

procedure TDpccIdeCheckInput.AddKey(const AKey: string);
var
  mKey: string;
begin
  for mKey in Keys do
  begin
    if SameText(mKey, AKey) then
    begin
      Exit;
    end;
  end;
  Keys := Keys + [AKey];
end;

procedure TDpccIdeCheckInput.SetValue(const AKey, AName, AValue: string);
var
  mIndex: Integer;
begin
  AddKey(AKey);
  for mIndex := 0 to High(Values) do
  begin
    if SameText(Values[mIndex].Key, AKey) and SameText(Values[mIndex].Name, AName) then
    begin
      Values[mIndex].Value := AValue;
      Values[mIndex].IsDword := False;
      Exit;
    end;
  end;
  Add(AKey, AName, AValue);
end;

procedure TDpccIdeCheckInput.RemoveValue(const AKey, AName: string);
var
  mIndex: Integer;
begin
  for mIndex := High(Values) downto 0 do
  begin
    if SameText(Values[mIndex].Key, AKey) and SameText(Values[mIndex].Name, AName) then
    begin
      Delete(Values, mIndex, 1);
    end;
  end;
end;

function TDpccIdeCheckInput.TryGet(const AKey, AName: string; out AValue: TDpccIdeRegValue): Boolean;
var
  mValue: TDpccIdeRegValue;
begin
  for mValue in Values do
  begin
    if SameText(mValue.Key, AKey) and SameText(mValue.Name, AName) then
    begin
      AValue := mValue;
      Exit(True);
    end;
  end;
  AValue := Default(TDpccIdeRegValue);
  Result := False;
end;

function TDpccIdeCheckInput.TryGetMarker(const AKey, AName: string; out AMarker: TDpccIdeMarker): Boolean;
var
  mMarker: TDpccIdeMarker;
begin
  for mMarker in Markers do
  begin
    if SameText(mMarker.Key, AKey) and SameText(mMarker.Name, AName) then
    begin
      AMarker := mMarker;
      Exit(True);
    end;
  end;
  AMarker := Default(TDpccIdeMarker);
  Result := False;
end;

function TDpccIdeCheckInput.HasKey(const AKey: string): Boolean;
var
  mValue: TDpccIdeRegValue;
  mKey: string;
begin
  for mKey in Keys do
  begin
    if SameText(mKey, AKey) then
    begin
      Exit(True);
    end;
  end;
  for mValue in Values do
  begin
    if SameText(mValue.Key, AKey) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TDpccIdeCheckResult }

function TDpccIdeCheckResult.Count(ASeverity: TDpccIdeSeverity): Integer;
var
  mFinding: TDpccIdeFinding;
begin
  Result := 0;
  for mFinding in Findings do
  begin
    if mFinding.Severity = ASeverity then
    begin
      Inc(Result);
    end;
  end;
end;

function TDpccIdeCheckResult.DeviationNames: TArray<string>;
var
  mFinding: TDpccIdeFinding;
begin
  Result := nil;
  for mFinding in Findings do
  begin
    if mFinding.Severity = TDpccIdeSeverity.Deviation then
    begin
      Result := Result + [mFinding.ValueName];
    end;
  end;
end;

function TDpccIdeCheckResult.Summary: string;
var
  mDeviations, mHints: Integer;
begin
  mDeviations := Count(TDpccIdeSeverity.Deviation);
  mHints := Count(TDpccIdeSeverity.Hint);
  case mDeviations of
    0:
      Result := Format(Txt(TIdeCheckText.SummaryNone), [Length(Findings) - mHints]);
    1:
      Result := Format(Txt(TIdeCheckText.SummaryOne), [string.Join(', ', DeviationNames)]);
  else
    Result := Format(Txt(TIdeCheckText.SummaryMore), [mDeviations, string.Join(', ', DeviationNames)]);
  end;
  if mHints = 1 then
  begin
    Result := Result + ' · ' + Txt(TIdeCheckText.SummaryHintOne);
  end
  else if mHints > 1 then
  begin
    Result := Result + ' · ' + Format(Txt(TIdeCheckText.SummaryHintMore), [mHints]);
  end;
end;

function TDpccIdeCheckResult.LogLine: string;
var
  mDeviations, mHints: Integer;
begin
  mDeviations := Count(TDpccIdeSeverity.Deviation);
  mHints := Count(TDpccIdeSeverity.Hint);
  case mDeviations of
    0:
      Result := 'IDE-Einstellungen: keine Abweichung';
    1:
      Result := 'IDE-Einstellungen: 1 Abweichung: ' + string.Join(', ', DeviationNames);
  else
    Result := Format('IDE-Einstellungen: %d Abweichungen: %s', [mDeviations, string.Join(', ', DeviationNames)]);
  end;
  if mHints = 1 then
  begin
    Result := Result + '; 1 Hinweis';
  end
  else if mHints > 1 then
  begin
    Result := Result + Format('; %d Hinweise', [mHints]);
  end;
  Result := Result + Format('; Anbieter „%s“, geprüft %s', [ProviderId, ActiveKey]);
  if ActiveKeyMissing then
  begin
    Result := Result + ' (Schlüssel fehlt, IDE-Vorgabe)';
  end;
end;

function ActualText(const AFinding: TDpccIdeFinding): string;
begin
  if AFinding.Exists then
  begin
    Result := AFinding.Actual;
  end
  else
  begin
    Result := Format(Txt(TIdeCheckText.MissingValue), [AFinding.Effective]);
  end;
end;

/// <summary>Voller Schlüssel für die Anzeige: HKCU\&lt;ABaseKey&gt;\&lt;AKey&gt;.</summary>
function RootedKey(const ABaseKey, AKey: string): string;
begin
  Result := 'HKCU';
  if ABaseKey <> '' then
  begin
    Result := Result + '\' + ABaseKey;
  end;
  if AKey <> '' then
  begin
    Result := Result + '\' + AKey;
  end;
end;

function TDpccIdeCheckResult.Report: string;
const
  cSeverity: array[TDpccIdeSeverity] of TIdeCheckText = (TIdeCheckText.SeverityOk, TIdeCheckText.SeverityDeviation,
    TIdeCheckText.SeverityHint);
var
  mLines: TStringList;
  mFinding: TDpccIdeFinding;
begin
  mLines := TStringList.Create;
  try
    mLines.Add(Format(Txt(TIdeCheckText.ReportProvider), [ProviderName(Provider, ProviderId)]));
    mLines.Add(Format(Txt(TIdeCheckText.ReportKey), [RootedKey(BaseKey, ActiveKey)]));
    mLines.Add(Summary);
    for mFinding in Findings do
    begin
      mLines.Add('');
      if mFinding.ValueName = '' then
      begin
        mLines.Add('[' + Txt(cSeverity[mFinding.Severity]) + '] ' + mFinding.Caption + ': ' +
          RootedKey(BaseKey, mFinding.Key));
      end
      else
      begin
        mLines.Add('[' + Txt(cSeverity[mFinding.Severity]) + '] ' + mFinding.Caption + ' (' + mFinding.ValueName +
          ')');
      end;
      if mFinding.Expected = '' then
      begin
        mLines.Add('    ' + Format(Txt(TIdeCheckText.ReportActual), [ActualText(mFinding)]));
      end
      else
      begin
        mLines.Add('    ' + Format(Txt(TIdeCheckText.ReportActualExpected), [ActualText(mFinding),
          mFinding.Expected]));
      end;
      if mFinding.Reason <> '' then
      begin
        mLines.Add('    ' + Format(Txt(TIdeCheckText.ReportReason), [mFinding.Reason]));
      end;
    end;
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

{ TDpccIdeCheck }

class function TDpccIdeCheck.ProviderOf(const AId: string): TDpccIdeProvider;
begin
  if Trim(AId) = '' then
  begin
    Result := TDpccIdeProvider.Unknown;
  end
  else if SameText(Trim(AId), cDelphiLspId) then
  begin
    Result := TDpccIdeProvider.DelphiLsp;
  end
  else if SameText(Trim(AId), cDpccId) then
  begin
    Result := TDpccIdeProvider.Dpcc;
  end
  else
  begin
    Result := TDpccIdeProvider.Other;
  end;
end;

class function TDpccIdeCheck.ProviderKey(const AId: string): string;
begin
  Result := cCodeInsightRoot + '\' + cEditOptionsPrefix + Trim(AId);
end;

class function TDpccIdeCheck.KeysToRead(const AProviderId: string): TArray<string>;
begin
  Result := nil;
  AddName(Result, cLspKey);
  AddName(Result, cPascalKey);
  if ProviderOf(AProviderId) = TDpccIdeProvider.Other then
  begin
    AddName(Result, ProviderKey(AProviderId));
  end;
end;

class function TDpccIdeCheck.CodeInsightValueNames: TArray<string>;
begin
  Result := nil;
  AddName(Result, cAutoCodeCompletions);
  AddName(Result, cAutoInvokeDelay);
  AddName(Result, cAutoCodeParameters);
  AddName(Result, cDeclarationInformation);
  AddName(Result, cHelpInsight);
  AddName(Result, cToolTipWatches);
  AddName(Result, cErrorInsight);
end;

/// <summary>Orte in der Reihenfolge, in der ActiveKey sie versucht; der erste ist der Ersatz, wenn keiner da ist.
/// </summary>
function KeyCandidates(const AInput: TDpccIdeCheckInput): TArray<string>;
begin
  Result := nil;
  case TDpccIdeCheck.ProviderOf(AInput.ProviderId) of
    TDpccIdeProvider.Dpcc:
      // Option Set des dpcc-Managers, unter Delphi 12 und 13 derselbe.
      AddName(Result, TDpccIdeCheck.cPascalKey);
    TDpccIdeProvider.Other:
      begin
        AddName(Result, TDpccIdeCheck.ProviderKey(AInput.ProviderId));
        AddName(Result, TDpccIdeCheck.cLspKey);
      end;
  else
    // DelphiLSP, und ohne ermittelten Anbieter dessen Ort (Vorgabe der IDE).
    AddName(Result, TDpccIdeCheck.cLspKey);
  end;
  // Kein Ersatz über die Version mehr: Delphi 12 liest DelphiLSP wie Delphi 13 nur am Ort von DelphiLSP;
  // Borland.EditOptions.Pascal ist das Option Set von dpcc (gelesener Stand von 23.0, D12-PREP).
end;

class function TDpccIdeCheck.ActiveKey(const AInput: TDpccIdeCheckInput): string;
var
  mCandidates: TArray<string>;
  mKey: string;
begin
  // Versionsneutral (Delphi 12 und 13): der erste Ort, den es gibt; sonst der erste Kandidat (Schlüssel fehlt).
  mCandidates := KeyCandidates(AInput);
  for mKey in mCandidates do
  begin
    if AInput.HasKey(mKey) then
    begin
      Exit(mKey);
    end;
  end;
  Result := mCandidates[0];
end;

/// <summary>Befund zu einem Ziel: gelesener bzw. Vorgabewert gegen ATarget.</summary>
function TargetFinding(const AInput: TDpccIdeCheckInput; const ATarget: TDpccIdeTarget): TDpccIdeFinding;
var
  mValue: TDpccIdeRegValue;
begin
  Result := Default(TDpccIdeFinding);
  Result.Caption := ATarget.Caption;
  Result.Key := ATarget.Key;
  Result.ValueName := ATarget.Name;
  Result.Reason := ATarget.Reason;
  Result.Expected := ATarget.Value;
  Result.Exists := AInput.TryGet(ATarget.Key, ATarget.Name, mValue);
  if Result.Exists then
  begin
    Result.Actual := mValue.Value;
  end;
  case ATarget.Kind of
    TDpccIdeValueKind.Flag:
      begin
        Result.Effective := SwitchText(not Result.Exists or FlagOf(mValue, True));
      end;
    TDpccIdeValueKind.Number:
      begin
        Result.Effective := '-1';
        if Result.Exists then
        begin
          Result.Effective := IntToStr(StrToIntDef(Trim(mValue.Value), -1));
        end;
      end;
  else
    begin
      Result.Effective := TDpccIdeCheck.cDelphiLspId;
      if Result.Exists and (Trim(mValue.Value) <> '') then
      begin
        Result.Effective := Trim(mValue.Value);
      end;
    end;
  end;
  if TDpccIdeContext.Matches(Result.Exists, mValue, ATarget.Value, ATarget.Kind) then
  begin
    Result.Severity := TDpccIdeSeverity.Ok;
  end
  else
  begin
    Result.Severity := TDpccIdeSeverity.Deviation;
  end;
end;

function NewTarget(const AKey, AName, AValue: string; AKind: TDpccIdeValueKind; ACaption,
  AReason: TIdeCheckText): TDpccIdeTarget;
begin
  Result.Key := AKey;
  Result.Name := AName;
  Result.Value := AValue;
  Result.Kind := AKind;
  Result.Caption := Txt(ACaption);
  Result.Reason := Txt(AReason);
end;

procedure AddFinding(var AResult: TDpccIdeCheckResult; const AFinding: TDpccIdeFinding);
begin
  AResult.Findings := AResult.Findings + [AFinding];
end;

/// <summary>Hinweis ohne Soll.</summary>
function HintFinding(const AKey, AName: string; ACaption: TIdeCheckText; const AActual, AReason: string):
  TDpccIdeFinding;
begin
  Result := Default(TDpccIdeFinding);
  Result.Caption := Txt(ACaption);
  Result.Key := AKey;
  Result.ValueName := AName;
  Result.Exists := True;
  Result.Actual := AActual;
  Result.Effective := AActual;
  Result.Reason := AReason;
  Result.Severity := TDpccIdeSeverity.Hint;
end;

class function TDpccIdeCheck.Evaluate(const AInput: TDpccIdeCheckInput): TDpccIdeCheckResult;
var
  mKey, mProviderText: string;
  mTarget: TDpccIdeTarget;
begin
  Result := Default(TDpccIdeCheckResult);
  Result.BaseKey := AInput.BaseKey;
  Result.ProviderId := Trim(AInput.ProviderId);
  Result.Provider := ProviderOf(AInput.ProviderId);
  if AInput.Dpcc.Enabled then
  begin
    Result.Mode := TDpccIdeMode.Dpcc;
  end
  else
  begin
    Result.Mode := TDpccIdeMode.Ide;
  end;
  mKey := ActiveKey(AInput);
  Result.ActiveKey := mKey;
  Result.ActiveKeyMissing := not AInput.HasKey(mKey);
  mProviderText := Result.ProviderId;
  if mProviderText = '' then
  begin
    mProviderText := Txt(TIdeCheckText.ProviderNameUnknown);
  end;
  case Result.Provider of
    TDpccIdeProvider.Dpcc:
      AddFinding(Result, HintFinding(cSourceOptionsKey, cProviderValue, TIdeCheckText.CaptionProvider, mProviderText,
        Txt(TIdeCheckText.ReasonProviderDpcc)));
    TDpccIdeProvider.Other:
      AddFinding(Result, HintFinding(cSourceOptionsKey, cProviderValue, TIdeCheckText.CaptionProvider, mProviderText,
        Format(Txt(TIdeCheckText.ReasonProviderOther), [Result.ProviderId])));
    TDpccIdeProvider.Unknown:
      AddFinding(Result, HintFinding(cSourceOptionsKey, cProviderValue, TIdeCheckText.CaptionProvider, mProviderText,
        Txt(TIdeCheckText.ReasonProviderUnknown)));
  end;
  // Den geprüften Ort gibt es nicht: kein Fehler, die Regeln gelten mit den Vorgaben der IDE.
  if Result.ActiveKeyMissing then
  begin
    AddFinding(Result, HintFinding(mKey, '', TIdeCheckText.CaptionKey, Txt(TIdeCheckText.KeyMissing),
      Txt(TIdeCheckText.ReasonKeyMissing)));
  end;
  if Result.Mode = TDpccIdeMode.Dpcc then
  begin
    // Hauptschalter an: genau die Werte, die dpcc setzt (der Anbieter selbst steht oben bzw. in StatusText).
    for mTarget in TDpccIdeContext.Targets(AInput.Dpcc) do
    begin
      if not SameText(mTarget.Key, cSourceOptionsKey) then
      begin
        AddFinding(Result, TargetFinding(AInput, mTarget));
      end;
    end;
  end
  else
  begin
    // Betriebsart IDE: was DelphiLSP (bzw. der andere Anbieter) braucht; dpcc ändert hier nichts, nur Protokoll.
    AddFinding(Result, TargetFinding(AInput, NewTarget(mKey, cAutoCodeCompletions, 'True', TDpccIdeValueKind.Flag,
      TIdeCheckText.CaptionAutoCompletions, TIdeCheckText.ReasonAutoCompletions)));
    AddFinding(Result, TargetFinding(AInput, NewTarget(mKey, cAutoCodeParameters, 'True', TDpccIdeValueKind.Flag,
      TIdeCheckText.CaptionAutoParameters, TIdeCheckText.ReasonAutoParameters)));
    // Error Insight liefert nur DelphiLSP; ohne Wert gilt die Vorgabe der IDE: an.
    if Result.Provider in [TDpccIdeProvider.DelphiLsp, TDpccIdeProvider.Unknown] then
    begin
      AddFinding(Result, TargetFinding(AInput, NewTarget(mKey, cErrorInsight, 'True', TDpccIdeValueKind.Flag,
        TIdeCheckText.CaptionErrorInsight, TIdeCheckText.ReasonErrorInsight)));
    end;
  end;
end;

{ TDpccIdeContext }

class function TDpccIdeContext.Targets(const ADpcc: TDpccIdeDpccState): TArray<TDpccIdeTarget>;
const
  cKey = TDpccIdeCheck.cPascalKey;
begin
  Result := nil;
  Result := Result + [NewTarget(TDpccIdeCheck.cSourceOptionsKey, TDpccIdeCheck.cProviderValue,
    TDpccIdeCheck.cDpccId, TDpccIdeValueKind.Text, TIdeCheckText.CaptionProvider, TIdeCheckText.ReasonProvider)];
  Result := Result + [NewTarget(cKey, TDpccIdeCheck.cAutoCodeCompletions, 'True', TDpccIdeValueKind.Flag,
    TIdeCheckText.CaptionAutoCompletions, TIdeCheckText.ReasonAutoCompletions)];
  Result := Result + [NewTarget(cKey, TDpccIdeCheck.cAutoInvokeDelay, '-1', TDpccIdeValueKind.Number,
    TIdeCheckText.CaptionAutoInvokeDelay, TIdeCheckText.ReasonAutoInvokeDelay)];
  Result := Result + [NewTarget(cKey, TDpccIdeCheck.cAutoCodeParameters, 'True', TDpccIdeValueKind.Flag,
    TIdeCheckText.CaptionAutoParameters, TIdeCheckText.ReasonAutoParameters)];
  if ADpcc.HoverTooltip then
  begin
    Result := Result + [NewTarget(cKey, TDpccIdeCheck.cHelpInsight, 'False', TDpccIdeValueKind.Flag,
      TIdeCheckText.CaptionHelpInsight, TIdeCheckText.ReasonHelpInsight)];
    Result := Result + [NewTarget(cKey, TDpccIdeCheck.cDeclarationInformation, 'False', TDpccIdeValueKind.Flag,
      TIdeCheckText.CaptionDeclaration, TIdeCheckText.ReasonDeclaration)];
    if ADpcc.DebugHoverValues then
    begin
      Result := Result + [NewTarget(cKey, TDpccIdeCheck.cToolTipWatches, 'False', TDpccIdeValueKind.Flag,
        TIdeCheckText.CaptionTooltipWatches, TIdeCheckText.ReasonTooltipWatches)];
    end;
  end;
  Result := Result + [NewTarget(TDpccIdeCheck.cGlobalKey, TDpccIdeCheck.cAutoInvokeOnParameterInsight, 'False',
    TDpccIdeValueKind.Flag, TIdeCheckText.CaptionParameterInsight, TIdeCheckText.ReasonParameterInsight)];
end;

class function TDpccIdeContext.Matches(AExists: Boolean; const AValue: TDpccIdeRegValue; const ATarget: string;
  AKind: TDpccIdeValueKind): Boolean;
var
  mText: string;
begin
  case AKind of
    TDpccIdeValueKind.Flag:
      begin
        // Ohne Wert gilt die Vorgabe der IDE: an.
        Result := (not AExists or FlagOf(AValue, True)) = SameText(ATarget, 'True');
      end;
    TDpccIdeValueKind.Number:
      begin
        // Ohne Wert -1; alle Werte unter 0 heißen „aus“.
        mText := '-1';
        if AExists then
        begin
          mText := Trim(AValue.Value);
        end;
        if StrToIntDef(ATarget, 0) < 0 then
        begin
          Result := StrToIntDef(mText, -1) < 0;
        end
        else
        begin
          Result := StrToIntDef(mText, -1) = StrToIntDef(ATarget, 0);
        end;
      end;
  else
    begin
      // Anbieter: ohne Wert gilt die Vorgabe DelphiLSP.
      mText := TDpccIdeCheck.cDelphiLspId;
      if AExists and (Trim(AValue.Value) <> '') then
      begin
        mText := Trim(AValue.Value);
      end;
      Result := SameText(mText, Trim(ATarget));
    end;
  end;
end;

/// <summary>Art des Werts AKey\AName für den Vergleich beim Rückweg.</summary>
function KindOf(const AKey, AName: string): TDpccIdeValueKind;
begin
  if SameText(AName, TDpccIdeCheck.cAutoInvokeDelay) then
  begin
    Result := TDpccIdeValueKind.Number;
  end
  else if SameText(AKey, TDpccIdeCheck.cSourceOptionsKey) then
  begin
    Result := TDpccIdeValueKind.Text;
  end
  else
  begin
    Result := TDpccIdeValueKind.Flag;
  end;
end;

procedure AddWrite(var APlan: TDpccIdeContextPlan; const AKey, AName, AValue: string; ADelete: Boolean);
var
  mWrite: TDpccIdeWrite;
begin
  mWrite.Key := AKey;
  mWrite.Name := AName;
  mWrite.Delete := ADelete;
  mWrite.Value := AValue;
  APlan.Writes := APlan.Writes + [mWrite];
end;

function IsProviderValue(const AKey, AName: string): Boolean;
begin
  Result := SameText(AKey, TDpccIdeCheck.cSourceOptionsKey) and SameText(AName, TDpccIdeCheck.cProviderValue);
end;

/// <summary>Rückweg eines Merkers: nur wenn der Wert noch so steht, wie dpcc ihn schrieb (nur zurückdrehen, was
/// dpcc selbst geändert hat).</summary>
procedure Restore(var APlan: TDpccIdeContextPlan; const AInput: TDpccIdeCheckInput; const AMarker: TDpccIdeMarker);
var
  mValue: TDpccIdeRegValue;
begin
  if AInput.TryGet(AMarker.Key, AMarker.Name, mValue) and
    TDpccIdeContext.Matches(True, mValue, AMarker.Written, KindOf(AMarker.Key, AMarker.Name)) then
  begin
    if AMarker.OriginalExists then
    begin
      AddWrite(APlan, AMarker.Key, AMarker.Name, AMarker.Original, False);
    end
    else
    begin
      AddWrite(APlan, AMarker.Key, AMarker.Name, '', True);
    end;
    AddName(APlan.RestoredNames, AMarker.Name);
    if IsProviderValue(AMarker.Key, AMarker.Name) then
    begin
      APlan.ProviderAfter := AMarker.Original;
      APlan.ProviderChanged := True;
    end;
  end
  else
  begin
    // Seit dpcc fremd geändert (Nutzer oder IDE): Der Wert bleibt.
    AddName(APlan.KeptNames, AMarker.Name);
  end;
  AddName(APlan.MarkerDeletes, AMarker.StoreName);
end;

/// <summary>Ziel setzen, wenn es nicht schon passt; der Merker behält den Wert vor der ersten Änderung durch dpcc.
/// </summary>
procedure Ensure(var APlan: TDpccIdeContextPlan; const AInput: TDpccIdeCheckInput; const ATarget: TDpccIdeTarget);
var
  mValue: TDpccIdeRegValue;
  mExists: Boolean;
  mMarker, mOld: TDpccIdeMarker;
begin
  mExists := AInput.TryGet(ATarget.Key, ATarget.Name, mValue);
  if TDpccIdeContext.Matches(mExists, mValue, ATarget.Value, ATarget.Kind) then
  begin
    Exit;
  end;
  AddWrite(APlan, ATarget.Key, ATarget.Name, ATarget.Value, False);
  AddName(APlan.SetNames, ATarget.Name);
  mMarker := Default(TDpccIdeMarker);
  mMarker.Key := ATarget.Key;
  mMarker.Name := ATarget.Name;
  mMarker.Written := ATarget.Value;
  mMarker.StoreName := TDpccIdeContext.MarkerName(AInput.BaseKey, ATarget.Key, ATarget.Name);
  if AInput.TryGetMarker(ATarget.Key, ATarget.Name, mOld) then
  begin
    // Schon einmal von dpcc gesetzt und seither geändert: der Wert vor der ersten Änderung bleibt der Rückweg.
    mMarker.OriginalExists := mOld.OriginalExists;
    mMarker.Original := mOld.Original;
    // Ein älterer Merker (DWORD) hat einen anderen Namen: durch den neuen ersetzen.
    if not SameText(mOld.StoreName, mMarker.StoreName) then
    begin
      AddName(APlan.MarkerDeletes, mOld.StoreName);
    end;
  end
  else
  begin
    mMarker.OriginalExists := mExists;
    mMarker.Original := mValue.Value;
  end;
  APlan.MarkerWrites := APlan.MarkerWrites + [mMarker];
end;

function IsTarget(const ATargets: TArray<TDpccIdeTarget>; const AKey, AName: string): Boolean;
var
  mTarget: TDpccIdeTarget;
begin
  for mTarget in ATargets do
  begin
    if SameText(mTarget.Key, AKey) and SameText(mTarget.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDpccIdeContext.Plan(const AInput: TDpccIdeCheckInput;
  ATrigger: TDpccIdeContextTrigger): TDpccIdeContextPlan;
var
  mTargets: TArray<TDpccIdeTarget>;
  mTarget: TDpccIdeTarget;
  mMarker, mProviderMarker: TDpccIdeMarker;
  mState: TDpccIdeDpccState;
  mBack: string;
  mHasProviderMarker, mExplicitBack: Boolean;
begin
  Result := Default(TDpccIdeContextPlan);
  Result.Trigger := ATrigger;
  Result.ProviderBefore := Trim(AInput.ProviderId);
  Result.ProviderAfter := Result.ProviderBefore;
  case ATrigger of
    TDpccIdeContextTrigger.MasterOn:
      Result.Mode := TDpccIdeMode.Dpcc;
    TDpccIdeContextTrigger.MasterOff:
      Result.Mode := TDpccIdeMode.Ide;
  else
    begin
      // Beim Start entscheidet der gewählte Anbieter.
      if TDpccIdeCheck.ProviderOf(AInput.ProviderId) = TDpccIdeProvider.Dpcc then
      begin
        Result.Mode := TDpccIdeMode.Dpcc;
      end
      else
      begin
        Result.Mode := TDpccIdeMode.Ide;
      end;
    end;
  end;
  Result.Enabled := Result.Mode = TDpccIdeMode.Dpcc;
  Result.EnabledChanged := Result.Enabled <> AInput.Dpcc.Enabled;
  mHasProviderMarker := AInput.TryGetMarker(TDpccIdeCheck.cSourceOptionsKey, TDpccIdeCheck.cProviderValue,
    mProviderMarker);
  if Result.Mode = TDpccIdeMode.Dpcc then
  begin
    // Die Schalter nach den dpcc-Einstellungen mit Hauptschalter an.
    mState := AInput.Dpcc;
    mState.Enabled := True;
    mTargets := Targets(mState);
    for mTarget in mTargets do
    begin
      Ensure(Result, AInput, mTarget);
    end;
    // Was dpcc gesetzt hatte und jetzt nicht mehr braucht (etwa Tooltip aus), zurückdrehen.
    for mMarker in AInput.Markers do
    begin
      if not IsTarget(mTargets, mMarker.Key, mMarker.Name) then
      begin
        Restore(Result, AInput, mMarker);
      end;
    end;
    if not SameText(Result.ProviderBefore, TDpccIdeCheck.cDpccId) then
    begin
      Result.ProviderAfter := TDpccIdeCheck.cDpccId;
      Result.ProviderChanged := True;
      Result.Notice := Txt(TIdeCheckText.NoticeSwitchedToDpcc);
    end;
    Exit;
  end;
  // Betriebsart IDE: alles zurückdrehen, was dpcc selbst geändert hat (nur, was noch so steht). Hauptschalter
  // ausdrücklich aus, während dpcc Anbieter ist: Der Anbieter geht in jedem Fall zurück (gemerkter Wert, sonst
  // DelphiLSP), auch wenn der Nutzer dpcc in den Optionen der IDE selbst gewählt hatte.
  mExplicitBack := (ATrigger = TDpccIdeContextTrigger.MasterOff) and
    (TDpccIdeCheck.ProviderOf(AInput.ProviderId) = TDpccIdeProvider.Dpcc);
  for mMarker in AInput.Markers do
  begin
    if mExplicitBack and IsProviderValue(mMarker.Key, mMarker.Name) then
    begin
      AddName(Result.MarkerDeletes, mMarker.StoreName);
    end
    else
    begin
      Restore(Result, AInput, mMarker);
    end;
  end;
  if mExplicitBack then
  begin
    mBack := TDpccIdeCheck.cDelphiLspId;
    if mHasProviderMarker and mProviderMarker.OriginalExists and (Trim(mProviderMarker.Original) <> '') and
      (TDpccIdeCheck.ProviderOf(mProviderMarker.Original) <> TDpccIdeProvider.Dpcc) then
    begin
      mBack := Trim(mProviderMarker.Original);
    end;
    AddWrite(Result, TDpccIdeCheck.cSourceOptionsKey, TDpccIdeCheck.cProviderValue, mBack, False);
    AddName(Result.RestoredNames, TDpccIdeCheck.cProviderValue);
    Result.ProviderAfter := mBack;
    Result.ProviderChanged := True;
  end;
  if Result.ProviderChanged then
  begin
    Result.Notice := Format(Txt(TIdeCheckText.NoticeSwitchedToIde),
      [ProviderName(TDpccIdeCheck.ProviderOf(Result.ProviderAfter), Result.ProviderAfter)]);
  end
  else if (ATrigger = TDpccIdeContextTrigger.Start) and mHasProviderMarker and
    SameText(mProviderMarker.Written, TDpccIdeCheck.cDpccId) and AInput.Dpcc.Enabled then
  begin
    // dpcc hatte den Anbieter gesetzt; beim Start ist er es nicht mehr.
    Result.Notice := Txt(TIdeCheckText.NoticeProviderLost);
  end;
end;

class function TDpccIdeContext.MarkerName(const ABaseKey, AKey, AName: string): string;
begin
  Result := cMarkerPrefix + TDpccCodeInsightKeys.VersionText(ABaseKey) + ' ' + AKey + '\' + AName;
end;

class function TDpccIdeContext.EncodeMarker(const AMarker: TDpccIdeMarker): string;
begin
  Result := AMarker.Written + #9;
  if AMarker.OriginalExists then
  begin
    Result := Result + '=' + AMarker.Original;
  end
  else
  begin
    Result := Result + '-';
  end;
end;

class function TDpccIdeContext.DecodeMarker(const ABaseKey, AStoreName, AText: string;
  out AMarker: TDpccIdeMarker): Boolean;
var
  mVersion, mPrefix, mPath, mRest: string;
  mSlash, mTab: Integer;
begin
  AMarker := Default(TDpccIdeMarker);
  Result := False;
  mVersion := TDpccCodeInsightKeys.VersionText(ABaseKey);
  mPrefix := cMarkerPrefix + mVersion + ' ';
  if (mVersion = '') or not AStoreName.StartsWith(mPrefix, True) then
  begin
    Exit;
  end;
  mPath := AStoreName.Substring(mPrefix.Length);
  mSlash := mPath.LastIndexOf('\');
  mTab := AText.IndexOf(#9);
  if (mSlash <= 0) or (mSlash = mPath.Length - 1) or (mTab < 0) then
  begin
    Exit;
  end;
  mRest := AText.Substring(mTab + 1);
  if mRest.StartsWith('=') then
  begin
    AMarker.OriginalExists := True;
    AMarker.Original := mRest.Substring(1);
  end
  else if mRest = '-' then
  begin
    AMarker.OriginalExists := False;
  end
  else
  begin
    Exit;
  end;
  AMarker.Key := mPath.Substring(0, mSlash);
  AMarker.Name := mPath.Substring(mSlash + 1);
  AMarker.Written := AText.Substring(0, mTab);
  AMarker.StoreName := AStoreName;
  Result := True;
end;

class function TDpccIdeContext.DecodeLegacyMarker(const ABaseKey, AStoreName: string; AValue: Int64;
  out AMarker: TDpccIdeMarker): Boolean;
const
  cHelp = 'IdeHelpInsightDisabled';
  cWatches = 'IdeTooltipWatchesDisabled';
var
  mBase, mValueName, mPrefix, mSubKey: string;
begin
  AMarker := Default(TDpccIdeMarker);
  Result := False;
  if AValue = 0 then
  begin
    Exit;
  end;
  if AStoreName.StartsWith(cHelp, True) then
  begin
    mBase := cHelp;
    mValueName := TDpccIdeCheck.cHelpInsight;
  end
  else if AStoreName.StartsWith(cWatches, True) then
  begin
    mBase := cWatches;
    mValueName := TDpccIdeCheck.cToolTipWatches;
  end
  else
  begin
    Exit;
  end;
  if AStoreName.Length = mBase.Length then
  begin
    // Merker vor #1246: ohne Version und Ort, nur ab Delphi 13 und nur am Ort von DelphiLSP.
    if not TDpccCodeInsightKeys.UsesLegacyMarker(ABaseKey, TDpccCodeInsightKeys.cProviderKey) then
    begin
      Exit;
    end;
    mSubKey := TDpccCodeInsightKeys.cProviderKey;
  end
  else
  begin
    mPrefix := mBase + ' ' + TDpccCodeInsightKeys.VersionText(ABaseKey) + ' ';
    if (TDpccCodeInsightKeys.VersionText(ABaseKey) = '') or not AStoreName.StartsWith(mPrefix, True) then
    begin
      Exit;
    end;
    mSubKey := AStoreName.Substring(mPrefix.Length);
    if mSubKey = '' then
    begin
      Exit;
    end;
  end;
  AMarker.Key := TDpccIdeCheck.cCodeInsightRoot + '\' + mSubKey;
  AMarker.Name := mValueName;
  AMarker.Written := 'False';
  AMarker.OriginalExists := True;
  AMarker.Original := 'True';
  AMarker.StoreName := AStoreName;
  Result := True;
end;

class function TDpccIdeContext.StatusText(const AInput: TDpccIdeCheckInput): string;
var
  mLines: TStringList;
  mResult: TDpccIdeCheckResult;
  mProvider: TDpccIdeProvider;
  mSet: TArray<string>;
  mMarker: TDpccIdeMarker;
begin
  mProvider := TDpccIdeCheck.ProviderOf(AInput.ProviderId);
  mResult := TDpccIdeCheck.Evaluate(AInput);
  mLines := TStringList.Create;
  try
    if mProvider = TDpccIdeProvider.Dpcc then
    begin
      mLines.Add(Format(Txt(TIdeCheckText.StatusModeDpcc), [Trim(AInput.ProviderId)]));
    end
    else
    begin
      mLines.Add(Format(Txt(TIdeCheckText.StatusModeIde), [ProviderName(mProvider, Trim(AInput.ProviderId))]));
    end;
    // Hauptschalter und Anbieter passen nicht zusammen: Der Wechsel wirkt erst nach dem Neustart.
    if AInput.Dpcc.Enabled and (mProvider <> TDpccIdeProvider.Dpcc) then
    begin
      mLines.Add(Txt(TIdeCheckText.StatusPendingDpcc));
    end
    else if not AInput.Dpcc.Enabled and (mProvider = TDpccIdeProvider.Dpcc) then
    begin
      mLines.Add(Format(Txt(TIdeCheckText.StatusPendingIde), ['DelphiLSP']));
    end;
    mSet := nil;
    for mMarker in AInput.Markers do
    begin
      AddName(mSet, mMarker.Name);
    end;
    if Length(mSet) = 0 then
    begin
      mLines.Add(Txt(TIdeCheckText.StatusSetNone));
    end
    else
    begin
      mLines.Add(Format(Txt(TIdeCheckText.StatusSet), [string.Join(', ', mSet)]));
    end;
    mLines.Add(mResult.Summary);
    Result := TrimRight(mLines.Text);
  finally
    mLines.Free;
  end;
end;

{ TDpccIdeContextPlan }

function TDpccIdeContextPlan.HasChanges: Boolean;
begin
  Result := (Length(Writes) > 0) or (Length(MarkerWrites) > 0) or (Length(MarkerDeletes) > 0) or EnabledChanged;
end;

function TDpccIdeContextPlan.LogLine: string;
const
  cTriggers: array[TDpccIdeContextTrigger] of string = ('Start', 'Hauptschalter an', 'Hauptschalter aus');
var
  mProvider: string;
begin
  mProvider := ProviderBefore;
  if mProvider = '' then
  begin
    mProvider := '(nicht ermittelt)';
  end;
  if Mode = TDpccIdeMode.Dpcc then
  begin
    Result := Format('IDE-Kontext (%s): %s → dpcc an', [cTriggers[Trigger], mProvider]);
  end
  else
  begin
    Result := Format('IDE-Kontext (%s): %s → dpcc aus', [cTriggers[Trigger], mProvider]);
  end;
  if ProviderChanged then
  begin
    Result := Result + Format('; Anbieter → %s (wirkt nach dem Neustart)', [ProviderAfter]);
  end;
  if Length(SetNames) > 0 then
  begin
    Result := Result + '; gesetzt: ' + string.Join(', ', SetNames);
  end;
  if Length(RestoredNames) > 0 then
  begin
    Result := Result + '; zurückgedreht: ' + string.Join(', ', RestoredNames);
  end;
  if Length(KeptNames) > 0 then
  begin
    Result := Result + '; fremd geändert, belassen: ' + string.Join(', ', KeptNames);
  end;
  if not HasChanges then
  begin
    Result := Result + '; nichts zu ändern';
  end;
end;

procedure TDpccIdeContextPlan.ApplyTo(var AInput: TDpccIdeCheckInput);
var
  mWrite: TDpccIdeWrite;
  mName: string;
  mMarker: TDpccIdeMarker;
  mIndex: Integer;
begin
  for mWrite in Writes do
  begin
    if mWrite.Delete then
    begin
      AInput.RemoveValue(mWrite.Key, mWrite.Name);
    end
    else
    begin
      AInput.SetValue(mWrite.Key, mWrite.Name, mWrite.Value);
    end;
    if IsProviderValue(mWrite.Key, mWrite.Name) then
    begin
      AInput.ProviderId := mWrite.Value;
    end;
  end;
  for mName in MarkerDeletes do
  begin
    for mIndex := High(AInput.Markers) downto 0 do
    begin
      if SameText(AInput.Markers[mIndex].StoreName, mName) then
      begin
        Delete(AInput.Markers, mIndex, 1);
      end;
    end;
  end;
  for mMarker in MarkerWrites do
  begin
    for mIndex := High(AInput.Markers) downto 0 do
    begin
      if SameText(AInput.Markers[mIndex].StoreName, mMarker.StoreName) then
      begin
        Delete(AInput.Markers, mIndex, 1);
      end;
    end;
    AInput.Markers := AInput.Markers + [mMarker];
  end;
  AInput.Dpcc.Enabled := Enabled;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Settings.IdeCheck', cTexts[TDpccLanguage.German],
    cTexts[TDpccLanguage.English]);

end.
