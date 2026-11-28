unit dpcc.Core.Settings.IdeCheck.Tests;

// Tests für die Betriebsart von dpcc in der IDE (Auftrag IDECHECK, dpcc.Core.Settings.IdeCheck), ohne Registry:
// Prüfregeln für Delphi 12 (BDS 23.0) und Delphi 13 (BDS 37.0), fehlende Werte und Schlüssel, die Schreibaktionen
// beim Start und mit dem Hauptschalter in beide Richtungen, Rückdrehen nur eigener Änderungen, fremd geänderte Werte
// bleiben, ältere Merker (IdeHelpInsightDisabled …) und das Format der neuen Merker. Die Eingaben spiegeln den
// gelesenen Stand der Prüfrechner (Delphi 13: Auto Code Completions = False unter DelphiLSP; Delphi 12: nur der Ort
// von DelphiLSP, kein Borland.EditOptions.Pascal). Orte der Betriebsart dpcc (D12KEY, seit HI1 ohne Sonderregel für
// Delphi 12): unter Delphi 12 wie unter Delphi 13 jeder vorhandene aus Borland.EditOptions.Pascal und dem Ort von
// DelphiLSP; die alten Merker für Borland.EditOptions.Pascal unter 23.0 gelten dann als eigene Merker der Betriebsart
// dpcc. Aufgeräumt (CleanedNames) wird nur noch ein Merker an einem Ort, der kein Ort der Betriebsart dpcc ist.
// Betriebsart Server: die vier Code-Insight-Optionen für den Server (ServerTargets) beim Wechsel aus Aus und Plugin,
// zurück nach Plugin und Aus, beim Start mit ausgeschalteten Optionen und mit den Merkern, die beim Nutzer vor dieser
// Fassung standen (UserDelphi12, UserDelphi13).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccIdeCheckTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Delphi 13, DelphiLSP gewählt: dpcc aus, nichts zu schreiben; geprüft wird der Ort von DelphiLSP,
    /// einzige Abweichung Auto Code Completions (nur Protokoll).</summary>
    [Test]
    procedure Delphi13StartWithDelphiLspTurnsDpccOff;
    /// <summary>Delphi 12, DelphiLSP gewählt: Ort von DelphiLSP auch unter 23.0; Error Insight fehlt = an.</summary>
    [Test]
    procedure Delphi12StartWithDelphiLspUsesProviderKey;
    /// <summary>Schlüssel fehlt ganz: Hinweis „Schlüssel fehlt“, kein Fehler; Regeln mit den Vorgaben der IDE. Gibt
    /// es nur Borland.EditOptions.Pascal (Option Set von dpcc), bleibt es unter 12 und 13 beim Ort von DelphiLSP
    /// (D12-PREP; vorher galt unter 23.0 Borland.EditOptions.Pascal als Ort der Version).</summary>
    [Test]
    [TestCase('Delphi 12', 'Software\Embarcadero\BDS\23.0')]
    [TestCase('Delphi 13', 'Software\Embarcadero\BDS\37.0')]
    procedure MissingKeyIsHintWithDefaults(ABaseKey: string);
    /// <summary>Hauptschalter an (Delphi 13): Anbieter auf dpcc, nur die abweichenden Schalter an beiden vorhandenen
    /// Orten (Borland.EditOptions.Pascal und Ort von DelphiLSP), je ein Merker mit dem Wert davor; danach keine
    /// Abweichung. Derselbe Wert an zwei Orten zählt als eine Abweichung.</summary>
    [Test]
    procedure Delphi13MasterOnSetsProviderAndSwitches;
    /// <summary>Delphi 13: nur vorhandene Orte werden gesetzt, ein fehlender nicht angelegt; fehlen beide, gilt der
    /// Ort von DelphiLSP. Unbekannte Version wie Delphi 13.</summary>
    [Test]
    procedure Delphi13DpccUsesExistingKeysOnly;
    /// <summary>Hauptschalter an, dann aus: alles wieder wie vorher, keine Merker.</summary>
    [Test]
    [TestCase('Delphi 12', 'Software\Embarcadero\BDS\23.0')]
    [TestCase('Delphi 13', 'Software\Embarcadero\BDS\37.0')]
    procedure MasterOnThenOffRestoresEverything(ABaseKey: string);
    /// <summary>Fremd geänderter Wert (Nutzer oder IDE) bleibt beim Rückweg; nur der Merker entfällt.</summary>
    [Test]
    procedure RestoreKeepsForeignChange;
    /// <summary>Delphi 12, dpcc gewählt (HI1): Plan und Prüfung an beiden vorhandenen Orten wie unter Delphi 13; Help
    /// Insight, Declaration Information, ToolTip Watches dort False, Merker mit Wert davor (True bzw. keiner). Gibt
    /// es nur den Ort von DelphiLSP, wird Borland.EditOptions.Pascal nicht angelegt.</summary>
    [Test]
    procedure Delphi12DpccUsesExistingKeys;
    /// <summary>Delphi 12 wie Delphi 13: nur vorhandene Orte, keiner angelegt; fehlen beide, gilt der Ort von
    /// DelphiLSP. Hauptschalter aus dreht an beiden Orten zurück.</summary>
    [Test]
    procedure Delphi12DpccUsesExistingKeysOnly;
    /// <summary>Delphi 12, zurück zu DelphiLSP (Hauptschalter aus bzw. DelphiLSP im Dialog der IDE): die Werte am Ort
    /// von DelphiLSP wieder True (geschrieben, nicht gelöscht), nichts an Borland.EditOptions.Pascal.</summary>
    [Test]
    procedure Delphi12BackToLspRestoresLspKey;
    /// <summary>Delphi 12 mit den alten Merkern für Borland.EditOptions.Pascal (Stand vor D12KEY): Seit HI1 ist der
    /// Schlüssel ein Ort der Betriebsart dpcc; die Merker bleiben gültig und werden nicht gegen das neue Schreiben
    /// aufgeräumt. Der Ort von DelphiLSP wird zusätzlich gesetzt; der Rückweg stellt ihn auf True und löscht die von
    /// dpcc angelegten Werte an Pascal; vom Nutzer geänderte bleiben in der Betriebsart IDE.</summary>
    [Test]
    procedure Delphi12OldPascalMarkersStayValid;
    /// <summary>Ein Merker an einem Ort unter Code Insight, der kein Ort der Betriebsart dpcc ist (anderer Anbieter):
    /// unter Delphi 12 und 13 an seinem eigenen Ort zurückgedreht, als „aufgeräumt (alter Ort)“ gemeldet.</summary>
    [Test]
    [TestCase('Delphi 12', 'Software\Embarcadero\BDS\23.0')]
    [TestCase('Delphi 13', 'Software\Embarcadero\BDS\37.0')]
    procedure MarkerOutsideDpccKeysIsCleanedUp(ABaseKey: string);
    /// <summary>In der Betriebsart dpcc: Tooltip aus → Help Insight und Declaration Information zurück, der Rest
    /// bleibt.</summary>
    [Test]
    procedure TooltipOffRestoresOnlyItsSwitches;
    /// <summary>Beim zweiten Plan nach dem Ausführen ist nichts mehr zu tun (Gegenprüfung nach OK, Beenden).</summary>
    [Test]
    procedure PlanIsIdempotent;
    /// <summary>Der Anbieter war von dpcc gesetzt, beim Start ist er es nicht mehr: dpcc aus und ein Hinweis.</summary>
    [Test]
    procedure ProviderLostAtStartGivesNotice;
    /// <summary>Ältere DWORD-Merker: Name mit Version und Ort, ohne (nur ab Delphi 13), andere Version, Wert 0.</summary>
    [Test]
    procedure LegacyMarkers;
    /// <summary>Beim Start mit DelphiLSP dreht ein älterer Merker Help Insight zurück und entfällt.</summary>
    [Test]
    procedure LegacyMarkerIsRestoredAtStart;
    /// <summary>Neue Merker: Name je Version, Inhalt mit und ohne Wert davor; falsche Version oder Inhalt.</summary>
    [Test]
    procedure MarkerRoundTrip;
    /// <summary>Vergleich mit Vorgaben: Schalter ohne Wert = an, Verzögerung unter 0 = aus, Anbieter ohne Wert =
    /// DelphiLSP.</summary>
    [Test]
    procedure MatchesUsesIdeDefaults;
    /// <summary>Error Insight aus unter DelphiLSP ist eine Abweichung; dpcc als Anbieter nur ein Hinweis.</summary>
    [Test]
    procedure ErrorInsightAndProviderHint;
    /// <summary>Statuszeilen und Protokollzeilen.</summary>
    [Test]
    procedure StatusAndLogLines;
    /// <summary>Auto Invoke („Automatisch aufrufen“) wird gelesen; in der Betriebsart dpcc Soll True: gesetzt mit
    /// Merker (Wert davor), mit dem Hauptschalter aus wieder zurück; fehlt er, passt die Vorgabe der IDE.</summary>
    [Test]
    procedure AutoInvokeIsSetAndRestored;
    /// <summary>Unter DelphiLSP ist Auto Invoke = False nur eine Abweichung im Protokoll, dpcc schreibt nichts.
    /// </summary>
    [Test]
    procedure AutoInvokeOnlyCheckedUnderDelphiLsp;
    /// <summary>Beschriftungen: Auto Code Completions = „Programmierhilfe“, Auto Invoke = „Automatisch aufrufen“
    /// (de/en).</summary>
    [Test]
    procedure AutoInvokeCaptions;
    /// <summary>Betriebsart Server beim Start (Delphi 12 und 13): bleibt mit DelphiLSP und ohne Anbieterwert (Vorgabe
    /// der IDE) stehen, ohne etwas zu schreiben; mit dpcc als Anbieter wird Plugin, mit einem anderen Anbieter Aus
    /// (mit Hinweis). Plugin mit DelphiLSP wird wie früher Aus.</summary>
    [Test]
    [TestCase('Delphi 12', 'Software\Embarcadero\BDS\23.0')]
    [TestCase('Delphi 13', 'Software\Embarcadero\BDS\37.0')]
    procedure ServerModeAtStart(ABaseKey: string);
    /// <summary>Server mit OK gewählt: aus Plugin (Anbieter dpcc) zurück auf DelphiLSP, auch wenn der Merker einen
    /// anderen Anbieter nennt, eigene Schalter zurück außer Declaration Information am Ort von DelphiLSP (braucht der
    /// Server, Merker bleibt), Hinweis „Neustart“; aus Aus (DelphiLSP, alles an) nichts zu schreiben, Hinweis
    /// „nächster Serverstart“; aus einem anderen Anbieter ebenfalls DelphiLSP.</summary>
    [Test]
    procedure ServerOnFromEachMode;
    /// <summary>Von Server zu Aus: nichts zu schreiben, Hinweis „nächstes Öffnen einer Projektgruppe“; von Server zu
    /// Plugin: Anbieter dpcc und Schalter wie beim Hauptschalter an (wirkt nach dem Neustart).</summary>
    [Test]
    procedure ServerToOffAndPlugin;
    /// <summary>Wahl im Code-Insight-Dialog der IDE: dpcc → Plugin (auch aus Server); ein anderer Anbieter unter
    /// Plugin → Aus; DelphiLSP unter Server → bleibt Server.</summary>
    [Test]
    procedure ProviderChoiceInDialog;
    /// <summary>Statuszeilen der Betriebsart Server und des ausstehenden Wechsels; Protokollzeile nennt die
    /// Betriebsart.</summary>
    [Test]
    procedure ServerStatusLines;
    /// <summary>Aus → Server (Delphi 12): die vier Code-Insight-Optionen für den Server am Ort von DelphiLSP auf True,
    /// je ein Merker mit dem Wert davor, sonst nichts (kein Help Insight, kein Borland.EditOptions.Pascal, kein
    /// Anbieter); Hinweis „nächster Serverstart“ und „erst beim nächsten Start von Delphi“. Schreibt die IDE ihren
    /// Stand zurück, setzt die Gegenprüfung erneut, der Merker behält den Wert davor. Ohne Schlüssel nichts anlegen.
    /// </summary>
    [Test]
    procedure ServerFromOffSetsInsightOptions;
    /// <summary>Plugin → Server mit den Merkern des Nutzers (Delphi 12, gelesener Stand): Auto Code Completions und
    /// Auto Code Parameters bleiben stehen (kein Zurück und wieder Vor), ihre Merker unverändert; Declaration
    /// Information wird True, der Merker behält True als Wert davor; Help Insight und ToolTip Watches zurück, ihre
    /// Merker entfallen; Anbieter DelphiLSP. Schreibt die IDE danach ihren Plugin-Stand zurück, wird kein Wert von dpcc
    /// zum Wert davor. Ein späteres Aus endet mit den ursprünglichen Werten.</summary>
    [Test]
    procedure PluginToServerWithUserMarkers;
    /// <summary>Server → Plugin: gemeinsame Ziele bleiben ohne Schreiben stehen, die Merker behalten den Wert des
    /// Nutzers; Declaration Information und Help Insight auf False; Aus danach wie vorher. Plugin → Server → Plugin in
    /// einer Sitzung (die IDE schreibt dazwischen ihren Plugin-Stand zurück): der Merker gilt danach für False, Aus
    /// stellt den Wert des Nutzers her.</summary>
    [Test]
    procedure ServerToPluginKeepsUserValues;
    /// <summary>Server → Aus: die vier Optionen zurück auf die Werte davor, Merker entfallen, Hinweis „originale
    /// DelphiLSP“; vom Nutzer seither geänderter Wert bleibt.</summary>
    [Test]
    procedure ServerToOffRestoresUserValues;
    /// <summary>Start im Server-Betrieb mit ausgeschalteten Optionen (Delphi 12 und 13): Prüfung meldet die vier,
    /// der Plan setzt sie mit Merker, danach keine Abweichung. Schaltet der Nutzer eine im Server-Betrieb im Dialog
    /// der IDE aus, gilt dieselbe Regel wie in der Betriebsart Plugin: dpcc setzt sie beim nächsten Abgleich erneut,
    /// der Merker nimmt den Wert des Nutzers, Aus stellt ihn her.</summary>
    [Test]
    [TestCase('Delphi 12', 'Software\Embarcadero\BDS\23.0')]
    [TestCase('Delphi 13', 'Software\Embarcadero\BDS\37.0')]
    procedure ServerStartWithOptionsOff(ABaseKey: string);
    /// <summary>Merker aus der Zeit vor dem Server-Betrieb mit Optionen: Namen und Inhalt wie in der Registry gelesen
    /// (23.0 und 37.0) und ein älterer DWORD-Merker; der Wechsel auf Server und danach Aus enden mit den ursprünglichen
    /// Werten.</summary>
    [Test]
    procedure UserMarkersBeforeUpdate;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  dpcc.Core.Localization.Language,
  dpcc.Core.Settings.OperatingMode,
  dpcc.Core.Settings.IdeCheck;

const
  cBase12 = 'Software\Embarcadero\BDS\23.0';
  cBase13 = 'Software\Embarcadero\BDS\37.0';
  cLsp = TDpccIdeCheck.cLspKey;
  cPas = TDpccIdeCheck.cPascalKey;
  cSrc = TDpccIdeCheck.cSourceOptionsKey;
  cGlobal = TDpccIdeCheck.cGlobalKey;

var
  SavedLanguage: TDpccLanguage;

function State(AEnabled, AHover, ADebug: Boolean): TDpccIdeDpccState;
begin
  // Alles vorbelegt (seit der Betriebsart hat der Stand auch Mode).
  Result := Default(TDpccIdeDpccState);
  Result.Enabled := AEnabled;
  if AEnabled then
  begin
    Result.Mode := TDpccOperatingMode.Plugin;
  end;
  Result.HoverTooltip := AHover;
  Result.DebugHoverValues := ADebug;
  Result.AutoMinChars := 0;
end;

procedure AddSwitches(var AInput: TDpccIdeCheckInput; const AKey, ACompletions, ADelay, AParameters, ADeclaration,
  AHelp, AWatches: string);
begin
  AInput.AddKey(AKey);
  AInput.Add(AKey, TDpccIdeCheck.cAutoCodeCompletions, ACompletions);
  AInput.Add(AKey, TDpccIdeCheck.cAutoInvokeDelay, ADelay);
  AInput.Add(AKey, TDpccIdeCheck.cAutoCodeParameters, AParameters);
  AInput.Add(AKey, TDpccIdeCheck.cDeclarationInformation, ADeclaration);
  AInput.Add(AKey, TDpccIdeCheck.cHelpInsight, AHelp);
  AInput.Add(AKey, TDpccIdeCheck.cToolTipWatches, AWatches);
end;

/// <summary>Stand von Delphi 13 auf dem Prüfrechner (gelesen 18.11.2026): DelphiLSP, Auto Code Completions = False.
/// </summary>
function Delphi13: TDpccIdeCheckInput;
begin
  Result := Default(TDpccIdeCheckInput);
  Result.BaseKey := cBase13;
  Result.ProviderId := TDpccIdeCheck.cDelphiLspId;
  Result.Add(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDelphiLspId);
  AddSwitches(Result, cLsp, 'False', '-1', 'True', 'False', 'False', 'False');
  AddSwitches(Result, cPas, 'True', '-1', 'True', 'True', 'False', 'False');
  Result.Add(cGlobal, TDpccIdeCheck.cAutoInvokeOnParameterInsight, 'False');
  Result.Dpcc := State(True, True, True);
end;

/// <summary>Stand von Delphi 12 auf dem Prüfrechner: DelphiLSP, nur dessen Ort, alles an, Error Insight fehlt.
/// </summary>
function Delphi12: TDpccIdeCheckInput;
begin
  Result := Default(TDpccIdeCheckInput);
  Result.BaseKey := cBase12;
  Result.ProviderId := TDpccIdeCheck.cDelphiLspId;
  Result.Add(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDelphiLspId);
  AddSwitches(Result, cLsp, 'True', '-1', 'True', 'True', 'True', 'True');
  Result.Add(cGlobal, TDpccIdeCheck.cAutoInvokeOnParameterInsight, 'False');
  Result.Dpcc := State(True, True, True);
end;

/// <summary>Merker von Delphi 12 aus Ort, Wertname und Inhalt, wie er unter HKCU\Software\dpcc\IdePlugin steht.
/// </summary>
function Marker12(const AKey, AName, AText: string): TDpccIdeMarker;
begin
  Assert.IsTrue(TDpccIdeContext.DecodeMarker(cBase12, TDpccIdeContext.MarkerName(cBase12, AKey, AName), AText,
    Result), 'Merker ' + AName);
end;

/// <summary>Stand von Delphi 12 auf dem Prüfrechner vor D12KEY (gelesen 19.11.2026): dpcc gewählt (von dpcc gesetzt),
/// Borland.EditOptions.Pascal nur mit den drei Werten, die dpcc dort angelegt hatte (ohne Wert davor), am Ort von
/// DelphiLSP alles an.</summary>
function Delphi12WithOldMarkers: TDpccIdeCheckInput;
begin
  Result := Delphi12;
  Result.SetValue(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDpccId);
  Result.ProviderId := TDpccIdeCheck.cDpccId;
  Result.SetValue(cPas, TDpccIdeCheck.cHelpInsight, 'False');
  Result.SetValue(cPas, TDpccIdeCheck.cDeclarationInformation, 'False');
  Result.SetValue(cPas, TDpccIdeCheck.cToolTipWatches, 'False');
  Result.Markers := [
    Marker12(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDpccId + #9'=' + TDpccIdeCheck.cDelphiLspId),
    Marker12(cPas, TDpccIdeCheck.cHelpInsight, 'False'#9'-'),
    Marker12(cPas, TDpccIdeCheck.cDeclarationInformation, 'False'#9'-'),
    Marker12(cPas, TDpccIdeCheck.cToolTipWatches, 'False'#9'-')];
end;

/// <summary>Delphi 13 mit DelphiLSP und nur den Orten AKeys (alle Schalter an).</summary>
function Delphi13Keys(const AKeys: array of string): TDpccIdeCheckInput;
var
  mIndex: Integer;
begin
  Result := Default(TDpccIdeCheckInput);
  Result.BaseKey := cBase13;
  Result.ProviderId := TDpccIdeCheck.cDelphiLspId;
  Result.Add(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDelphiLspId);
  for mIndex := Low(AKeys) to High(AKeys) do
  begin
    AddSwitches(Result, AKeys[mIndex], 'True', '-1', 'True', 'True', 'True', 'True');
  end;
  Result.Add(cGlobal, TDpccIdeCheck.cAutoInvokeOnParameterInsight, 'False');
  Result.Dpcc := State(True, True, True);
end;

/// <summary>Wie Delphi13Keys, aber Delphi 12 (BDS 23.0).</summary>
function Delphi12Keys(const AKeys: array of string): TDpccIdeCheckInput;
begin
  Result := Delphi13Keys(AKeys);
  Result.BaseKey := cBase12;
end;

/// <summary>Schreibt der Plan etwas unter AKey?</summary>
function WritesAt(const APlan: TDpccIdeContextPlan; const AKey: string): Boolean;
var
  mWrite: TDpccIdeWrite;
begin
  for mWrite in APlan.Writes do
  begin
    if SameText(mWrite.Key, AKey) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function ValueOf(const AInput: TDpccIdeCheckInput; const AKey, AName: string): string;
var
  mValue: TDpccIdeRegValue;
begin
  if AInput.TryGet(AKey, AName, mValue) then
  begin
    Result := mValue.Value;
  end
  else
  begin
    Result := '<fehlt>';
  end;
end;

function HasWrite(const APlan: TDpccIdeContextPlan; const AKey, AName: string; out AWrite: TDpccIdeWrite): Boolean;
var
  mWrite: TDpccIdeWrite;
begin
  for mWrite in APlan.Writes do
  begin
    if SameText(mWrite.Key, AKey) and SameText(mWrite.Name, AName) then
    begin
      AWrite := mWrite;
      Exit(True);
    end;
  end;
  AWrite := Default(TDpccIdeWrite);
  Result := False;
end;

function CountOf(const AResult: TDpccIdeCheckResult; ASeverity: TDpccIdeSeverity): Integer;
begin
  Result := AResult.Count(ASeverity);
end;

{ TDpccIdeCheckTests }

procedure TDpccIdeCheckTests.Setup;
begin
  SavedLanguage := TDpccTextLanguage.Current;
  TDpccTextLanguage.Current := TDpccLanguage.German;
end;

procedure TDpccIdeCheckTests.TearDown;
begin
  TDpccTextLanguage.Current := SavedLanguage;
end;

procedure TDpccIdeCheckTests.Delphi13StartWithDelphiLspTurnsDpccOff;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mResult: TDpccIdeCheckResult;
begin
  mInput := Delphi13;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccIdeMode.Ide), Ord(mPlan.Mode), 'Betriebsart');
  Assert.IsFalse(mPlan.Enabled, 'dpcc aus');
  Assert.IsTrue(mPlan.EnabledChanged, 'Hauptschalter umgestellt');
  Assert.AreEqual(0, Integer(Length(mPlan.Writes)), 'nichts zu schreiben');
  Assert.IsFalse(mPlan.ProviderChanged, 'Anbieter bleibt');
  mPlan.ApplyTo(mInput);
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual(cLsp, mResult.ActiveKey, 'Ort von DelphiLSP');
  Assert.IsFalse(mResult.ActiveKeyMissing, 'Schlüssel da');
  Assert.AreEqual('Auto Code Completions', string.Join(',', mResult.DeviationNames), 'Abweichungen');
  Assert.IsTrue(StartsText('IDE-Einstellungen: 1 Abweichung: Auto Code Completions', mResult.LogLine),
    mResult.LogLine);
  // Die Werte unter Borland.EditOptions.Pascal zählen unter DelphiLSP nicht.
  Assert.AreEqual(0, CountOf(mResult, TDpccIdeSeverity.Hint), 'keine Hinweise');
end;

procedure TDpccIdeCheckTests.Delphi12StartWithDelphiLspUsesProviderKey;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mResult: TDpccIdeCheckResult;
begin
  mInput := Delphi12;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccIdeMode.Ide), Ord(mPlan.Mode), 'Betriebsart');
  Assert.IsFalse(mPlan.Enabled, 'dpcc aus');
  Assert.AreEqual(0, Integer(Length(mPlan.Writes)), 'nichts zu schreiben');
  mPlan.ApplyTo(mInput);
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual(cLsp, mResult.ActiveKey, 'auch unter 23.0 der Ort von DelphiLSP');
  Assert.AreEqual(0, CountOf(mResult, TDpccIdeSeverity.Deviation), 'keine Abweichung: ' + mResult.Report);
  // Auto Code Completions, Auto Invoke (fehlt = an), Auto Code Parameters, Error Insight (fehlt = an).
  Assert.AreEqual(4, Integer(Length(mResult.Findings)), 'Regeln unter DelphiLSP');
end;

procedure TDpccIdeCheckTests.MissingKeyIsHintWithDefaults(ABaseKey: string);
var
  mInput: TDpccIdeCheckInput;
  mResult: TDpccIdeCheckResult;
  mFinding: TDpccIdeFinding;
  mHint: Boolean;
begin
  mInput := Default(TDpccIdeCheckInput);
  mInput.BaseKey := ABaseKey;
  mInput.ProviderId := TDpccIdeCheck.cDelphiLspId;
  mInput.Dpcc := State(False, True, True);
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual(cLsp, mResult.ActiveKey, 'Ersatz: Ort von DelphiLSP');
  Assert.IsTrue(mResult.ActiveKeyMissing, 'Schlüssel fehlt');
  Assert.AreEqual(0, CountOf(mResult, TDpccIdeSeverity.Deviation), 'Vorgaben der IDE passen');
  mHint := False;
  for mFinding in mResult.Findings do
  begin
    if (mFinding.Severity = TDpccIdeSeverity.Hint) and (mFinding.ValueName = '') then
    begin
      mHint := True;
      Assert.AreEqual('Schlüssel fehlt (IDE-Vorgabe)', mFinding.Actual, 'Text');
    end;
  end;
  Assert.IsTrue(mHint, 'Hinweis zum Schlüssel');
  Assert.IsTrue(ContainsText(mResult.LogLine, 'Schlüssel fehlt'), mResult.LogLine);
  // Nur das Option Set von dpcc gibt es: DelphiLSP liest es weder unter 23.0 noch unter 37.0 (gelesener Stand von
  // Delphi 12: Code Insight nur mit dem Ort von DelphiLSP, HTML und StyleSheet).
  mInput.AddKey(cPas);
  Assert.AreEqual(cLsp, TDpccIdeCheck.ActiveKey(mInput), 'Ort von DelphiLSP, nicht das Option Set von dpcc');
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.IsTrue(mResult.ActiveKeyMissing, 'Ort von DelphiLSP fehlt weiter');
end;

procedure TDpccIdeCheckTests.Delphi13MasterOnSetsProviderAndSwitches;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mMarker: TDpccIdeMarker;
  mResult: TDpccIdeCheckResult;
begin
  mInput := Delphi13;
  // Vorher (Hauptschalter an, Anbieter noch DelphiLSP): beide Orte geprüft, je eine Abweichung.
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual(cPas + ',' + cLsp, string.Join(',', mResult.CheckedKeys), 'beide vorhandenen Orte');
  Assert.AreEqual('Declaration Information,Auto Code Completions', string.Join(',', mResult.DeviationNames),
    'Abweichungen vorher');
  Assert.IsTrue(ContainsText(mResult.LogLine, 'geprüft ' + cPas + ' + ' + cLsp), mResult.LogLine);
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.AreEqual(Ord(TDpccIdeMode.Dpcc), Ord(mPlan.Mode), 'Betriebsart');
  Assert.IsTrue(mPlan.Enabled, 'dpcc an');
  Assert.IsFalse(mPlan.EnabledChanged, 'war schon an');
  Assert.IsTrue(mPlan.ProviderChanged, 'Anbieter umgestellt');
  Assert.AreNotEqual('', mPlan.Notice, 'Hinweis zum Neustart');
  // Anbieter, Declaration Information (Borland.EditOptions.Pascal) und Auto Code Completions (Ort von DelphiLSP)
  // weichen ab; der Rest passt an beiden Orten schon.
  Assert.AreEqual(3, Integer(Length(mPlan.Writes)), 'Schreibaktionen');
  Assert.IsTrue(HasWrite(mPlan, cSrc, TDpccIdeCheck.cProviderValue, mWrite), 'Anbieter');
  Assert.AreEqual(TDpccIdeCheck.cDpccId, mWrite.Value);
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cDeclarationInformation, mWrite), 'Declaration Information');
  Assert.AreEqual('False', mWrite.Value);
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cAutoCodeCompletions, mWrite), 'Ort von DelphiLSP mit gesetzt');
  Assert.AreEqual('True', mWrite.Value);
  Assert.AreEqual(3, Integer(Length(mPlan.MarkerWrites)), 'Merker');
  for mMarker in mPlan.MarkerWrites do
  begin
    Assert.IsTrue(mMarker.OriginalExists, mMarker.Name + ': Wert davor');
    Assert.IsTrue(StartsText('IdeSet 37.0 ', mMarker.StoreName), mMarker.StoreName);
    if SameText(mMarker.Name, TDpccIdeCheck.cProviderValue) then
    begin
      Assert.AreEqual(TDpccIdeCheck.cDelphiLspId, mMarker.Original, 'Anbieter davor');
    end
    else if SameText(mMarker.Name, TDpccIdeCheck.cDeclarationInformation) then
    begin
      Assert.AreEqual(cPas, mMarker.Key, 'Ort von Declaration Information');
      Assert.AreEqual('True', mMarker.Original, 'Declaration Information davor');
    end
    else
    begin
      Assert.AreEqual(cLsp, mMarker.Key, 'Ort von Auto Code Completions');
      Assert.AreEqual('False', mMarker.Original, 'Auto Code Completions davor');
    end;
  end;
  mPlan.ApplyTo(mInput);
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual(cPas, mResult.ActiveKey, 'erster vorhandener Ort');
  Assert.AreEqual(0, CountOf(mResult, TDpccIdeSeverity.Deviation), 'danach passt alles: ' + mResult.Report);
  Assert.IsTrue(ContainsText(mPlan.LogLine, 'gesetzt: Insight Manager, Declaration Information, Auto Code Completions'),
    mPlan.LogLine);
  // Derselbe Wert weicht an beiden Orten ab: eine Abweichung, nicht zwei.
  mInput := Delphi13;
  mInput.SetValue(cLsp, TDpccIdeCheck.cDeclarationInformation, 'True');
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual('Declaration Information,Auto Code Completions', string.Join(',', mResult.DeviationNames),
    'ohne Doppel');
  Assert.IsTrue(StartsText('IDE-Einstellungen: 2 Abweichungen: Declaration Information, Auto Code Completions',
    mResult.LogLine), mResult.LogLine);
end;

procedure TDpccIdeCheckTests.Delphi13DpccUsesExistingKeysOnly;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
begin
  // Nur Borland.EditOptions.Pascal: der Ort von DelphiLSP wird nicht angelegt.
  mInput := Delphi13Keys([cPas]);
  Assert.AreEqual(cPas, string.Join(',', TDpccIdeCheck.DpccKeys(mInput)), 'nur Pascal');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cHelpInsight, mWrite), 'Help Insight an Pascal');
  Assert.IsFalse(WritesAt(mPlan, cLsp), 'nichts am fehlenden Ort von DelphiLSP');
  mPlan.ApplyTo(mInput);
  Assert.IsFalse(mInput.HasKey(cLsp), 'Ort von DelphiLSP nicht angelegt');
  // Nur der Ort von DelphiLSP: Borland.EditOptions.Pascal wird nicht angelegt.
  mInput := Delphi13Keys([cLsp]);
  Assert.AreEqual(cLsp, string.Join(',', TDpccIdeCheck.DpccKeys(mInput)), 'nur DelphiLSP');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cHelpInsight, mWrite), 'Help Insight am Ort von DelphiLSP');
  Assert.IsFalse(WritesAt(mPlan, cPas), 'nichts am fehlenden Pascal');
  mPlan.ApplyTo(mInput);
  Assert.IsFalse(mInput.HasKey(cPas), 'Pascal nicht angelegt');
  // Keiner da: Ersatz ist der Ort von DelphiLSP (sonst wirkte dpcc nicht), kein Pascal.
  mInput := Delphi13Keys([]);
  Assert.AreEqual(cLsp, string.Join(',', TDpccIdeCheck.DpccKeys(mInput)), 'Ersatz');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cHelpInsight, mWrite), 'Help Insight am Ersatz');
  Assert.IsFalse(WritesAt(mPlan, cPas), 'kein Pascal');
  // Beide da, Version unbekannt: wie Delphi 13.
  mInput := Delphi13Keys([cLsp, cPas]);
  mInput.BaseKey := 'Software\Embarcadero\BDS';
  Assert.AreEqual(cPas + ',' + cLsp, string.Join(',', TDpccIdeCheck.DpccKeys(mInput)), 'unbekannte Version');
  // Unter 23.0 seit HI1 genauso: beide vorhandenen Orte (vorher nur der Ort von DelphiLSP).
  mInput.BaseKey := cBase12;
  Assert.AreEqual(cPas + ',' + cLsp, string.Join(',', TDpccIdeCheck.DpccKeys(mInput)), 'Delphi 12 wie Delphi 13');
end;

procedure TDpccIdeCheckTests.MasterOnThenOffRestoresEverything(ABaseKey: string);
var
  mInput, mBefore: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mValue: TDpccIdeRegValue;
  mKey: string;
begin
  // Ort der Betriebsart dpcc: unter 23.0 (Stand des Prüfrechners ohne Borland.EditOptions.Pascal) der Ort von
  // DelphiLSP, unter 37.0 (auch) Borland.EditOptions.Pascal.
  if ABaseKey = cBase12 then
  begin
    mInput := Delphi12;
    mKey := cLsp;
  end
  else
  begin
    mInput := Delphi13;
    mKey := cPas;
  end;
  // Abweichende Werte an diesem Ort, damit alle Schalter geschrieben werden.
  mInput.SetValue(mKey, TDpccIdeCheck.cAutoCodeCompletions, 'False');
  mInput.SetValue(mKey, TDpccIdeCheck.cAutoInvokeDelay, '300');
  mInput.SetValue(mKey, TDpccIdeCheck.cHelpInsight, 'True');
  mInput.SetValue(cGlobal, TDpccIdeCheck.cAutoInvokeOnParameterInsight, 'True');
  // Eigene Kopie der Werte: Dynamische Arrays teilen sich sonst die Elemente.
  mBefore := mInput;
  mBefore.Values := Copy(mInput.Values);
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  mPlan.ApplyTo(mInput);
  Assert.AreEqual(TDpccIdeCheck.cDpccId, mInput.ProviderId, 'Anbieter dpcc');
  Assert.AreEqual('-1', ValueOf(mInput, mKey, TDpccIdeCheck.cAutoInvokeDelay), 'Verzögerung');
  Assert.AreEqual('False', ValueOf(mInput, mKey, TDpccIdeCheck.cHelpInsight), 'Help Insight');
  Assert.AreEqual('False', ValueOf(mInput, cGlobal, TDpccIdeCheck.cAutoInvokeOnParameterInsight), 'global');
  Assert.IsTrue(Length(mInput.Markers) >= 5, 'Merker');
  if ABaseKey = cBase12 then
  begin
    Assert.IsFalse(mInput.HasKey(cPas), 'fehlendes Borland.EditOptions.Pascal nicht angelegt');
  end;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff);
  Assert.AreEqual(Ord(TDpccIdeMode.Ide), Ord(mPlan.Mode), 'Betriebsart IDE');
  Assert.IsFalse(mPlan.Enabled, 'dpcc aus');
  Assert.IsTrue(mPlan.ProviderChanged, 'Anbieter zurück');
  Assert.AreEqual(0, Integer(Length(mPlan.KeptNames)), 'nichts fremd geändert');
  mPlan.ApplyTo(mInput);
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), 'Merker entfallen');
  Assert.AreEqual(TDpccIdeCheck.cDelphiLspId, mInput.ProviderId, 'Anbieter DelphiLSP');
  for mValue in mBefore.Values do
  begin
    Assert.AreEqual(mValue.Value, ValueOf(mInput, mValue.Key, mValue.Name), mValue.Key + '\' + mValue.Name);
  end;
  Assert.AreEqual(Integer(Length(mBefore.Values)), Integer(Length(mInput.Values)), 'keine neuen Werte');
end;

procedure TDpccIdeCheckTests.RestoreKeepsForeignChange;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
begin
  mInput := Delphi13;
  mInput.SetValue(cPas, TDpccIdeCheck.cAutoInvokeDelay, '500');
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn).ApplyTo(mInput);
  Assert.AreEqual('-1', ValueOf(mInput, cPas, TDpccIdeCheck.cAutoInvokeDelay), 'dpcc hat -1 gesetzt');
  // Der Nutzer stellt die Verzögerung danach selbst auf 200.
  mInput.SetValue(cPas, TDpccIdeCheck.cAutoInvokeDelay, '200');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff);
  Assert.IsFalse(HasWrite(mPlan, cPas, TDpccIdeCheck.cAutoInvokeDelay, mWrite), 'fremd geändert: nicht schreiben');
  Assert.IsTrue(MatchText(TDpccIdeCheck.cAutoInvokeDelay, mPlan.KeptNames), 'als belassen gemeldet');
  mPlan.ApplyTo(mInput);
  Assert.AreEqual('200', ValueOf(mInput, cPas, TDpccIdeCheck.cAutoInvokeDelay), 'Wert des Nutzers bleibt');
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), 'Merker entfallen trotzdem');
  Assert.IsTrue(ContainsText(mPlan.LogLine, 'fremd geändert, belassen: Auto Invoke Delay'), mPlan.LogLine);
end;

procedure TDpccIdeCheckTests.Delphi12DpccUsesExistingKeys;
const
  cNames: array[0..2] of string = (TDpccIdeCheck.cHelpInsight, TDpccIdeCheck.cDeclarationInformation,
    TDpccIdeCheck.cToolTipWatches);
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mMarker: TDpccIdeMarker;
  mResult: TDpccIdeCheckResult;
  mName: string;
begin
  mInput := Delphi12;
  // Im Code-Insight-Dialog der IDE dpcc gewählt, dpcc war aus. Borland.EditOptions.Pascal gibt es (leer); seit HI1
  // zählt er unter 23.0 wie unter 37.0.
  mInput.SetValue(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDpccId);
  mInput.ProviderId := TDpccIdeCheck.cDpccId;
  mInput.Dpcc.Enabled := False;
  mInput.AddKey(cPas);
  Assert.AreEqual(cPas + ',' + cLsp, string.Join(',', TDpccIdeCheck.DpccKeys(mInput)), 'beide vorhandenen Orte');
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual(cPas, mResult.ActiveKey, 'erster vorhandener Ort, wie unter 37.0');
  Assert.IsFalse(mResult.ActiveKeyMissing, 'Schlüssel da');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccIdeMode.Dpcc), Ord(mPlan.Mode), 'Betriebsart dpcc');
  Assert.IsTrue(mPlan.Enabled and mPlan.EnabledChanged, 'Hauptschalter an');
  Assert.IsFalse(mPlan.ProviderChanged, 'Anbieter ist schon dpcc');
  // Werte mit passender Vorgabe bzw. schon passend (Auto Code Completions, Verzögerung, Parameter) bleiben.
  Assert.IsFalse(HasWrite(mPlan, cLsp, TDpccIdeCheck.cAutoCodeCompletions, mWrite), 'passt schon');
  Assert.IsFalse(HasWrite(mPlan, cLsp, TDpccIdeCheck.cAutoInvokeDelay, mWrite), '-1 passt');
  Assert.IsFalse(HasWrite(mPlan, cPas, TDpccIdeCheck.cAutoCodeCompletions, mWrite), 'fehlt = an, passt');
  for mName in cNames do
  begin
    Assert.IsTrue(HasWrite(mPlan, cLsp, mName, mWrite) and (mWrite.Value = 'False') and not mWrite.Delete,
      mName + ' am Ort von DelphiLSP');
    Assert.IsTrue(HasWrite(mPlan, cPas, mName, mWrite) and (mWrite.Value = 'False') and not mWrite.Delete,
      mName + ' an Borland.EditOptions.Pascal');
  end;
  Assert.AreEqual(6, Integer(Length(mPlan.Writes)), 'Schreibaktionen');
  Assert.AreEqual(6, Integer(Length(mPlan.MarkerWrites)), 'Merker');
  for mMarker in mPlan.MarkerWrites do
  begin
    Assert.IsTrue(StartsText('IdeSet 23.0 Code Insight\', mMarker.StoreName), mMarker.StoreName);
    if SameText(mMarker.Key, cLsp) then
    begin
      Assert.IsTrue(mMarker.OriginalExists and (mMarker.Original = 'True'), mMarker.Name + ': davor True');
    end
    else
    begin
      Assert.AreEqual(cPas, mMarker.Key, mMarker.Name + ': Ort');
      Assert.IsFalse(mMarker.OriginalExists, mMarker.Name + ': an Pascal gab es keinen Wert davor');
    end;
  end;
  Assert.IsTrue(ContainsText(mPlan.LogLine, 'gesetzt: Help Insight, Declaration Information, ToolTip Watches'),
    mPlan.LogLine);
  Assert.AreEqual(0, Integer(Length(mPlan.CleanedNames)), 'nichts aufzuräumen');
  mPlan.ApplyTo(mInput);
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual(0, CountOf(mResult, TDpccIdeSeverity.Deviation), 'danach passt alles: ' + mResult.Report);
  Assert.AreEqual(cPas + ',' + cLsp, string.Join(',', mResult.CheckedKeys), 'geprüfte Orte');
  Assert.IsTrue(ContainsText(mResult.LogLine, 'geprüft ' + cPas + ' + ' + cLsp), mResult.LogLine);
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn).HasChanges, 'Gegenprüfung: nichts');

  // Stand des Prüfrechners (nur der Ort von DelphiLSP): wie vor HI1, Borland.EditOptions.Pascal wird nicht angelegt.
  mInput := Delphi12;
  mInput.SetValue(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDpccId);
  mInput.ProviderId := TDpccIdeCheck.cDpccId;
  Assert.AreEqual(cLsp, string.Join(',', TDpccIdeCheck.DpccKeys(mInput)), 'nur der Ort von DelphiLSP');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(3, Integer(Length(mPlan.Writes)), 'Schreibaktionen ohne Pascal');
  Assert.IsFalse(WritesAt(mPlan, cPas), 'nichts am fehlenden Borland.EditOptions.Pascal');
  mPlan.ApplyTo(mInput);
  Assert.IsFalse(mInput.HasKey(cPas), 'Borland.EditOptions.Pascal nicht angelegt');
end;

procedure TDpccIdeCheckTests.Delphi12DpccUsesExistingKeysOnly;
var
  mInput, mBefore: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mValue: TDpccIdeRegValue;
begin
  // Nur Borland.EditOptions.Pascal: der Ort von DelphiLSP wird nicht angelegt.
  mInput := Delphi12Keys([cPas]);
  Assert.AreEqual(cPas, string.Join(',', TDpccIdeCheck.DpccKeys(mInput)), 'nur Pascal');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cHelpInsight, mWrite), 'Help Insight an Pascal');
  Assert.IsFalse(WritesAt(mPlan, cLsp), 'nichts am fehlenden Ort von DelphiLSP');
  mPlan.ApplyTo(mInput);
  Assert.IsFalse(mInput.HasKey(cLsp), 'Ort von DelphiLSP nicht angelegt');
  // Keiner da: Ersatz ist der Ort von DelphiLSP, kein Pascal.
  mInput := Delphi12Keys([]);
  Assert.AreEqual(cLsp, string.Join(',', TDpccIdeCheck.DpccKeys(mInput)), 'Ersatz');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cHelpInsight, mWrite), 'Help Insight am Ersatz');
  Assert.IsFalse(WritesAt(mPlan, cPas), 'kein Pascal');
  // Beide da: an beiden gesetzt und mit dem Hauptschalter aus an beiden wieder wie vorher.
  mInput := Delphi12Keys([cLsp, cPas]);
  Assert.AreEqual(cPas + ',' + cLsp, string.Join(',', TDpccIdeCheck.DpccKeys(mInput)), 'beide');
  mBefore := mInput;
  mBefore.Values := Copy(mInput.Values);
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cHelpInsight, mWrite) and (mWrite.Value = 'False'), 'Pascal');
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cHelpInsight, mWrite) and (mWrite.Value = 'False'), 'DelphiLSP');
  mPlan.ApplyTo(mInput);
  Assert.AreEqual('False', ValueOf(mInput, cPas, TDpccIdeCheck.cHelpInsight), 'Pascal danach');
  Assert.AreEqual('False', ValueOf(mInput, cLsp, TDpccIdeCheck.cHelpInsight), 'DelphiLSP danach');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff);
  Assert.AreEqual(0, Integer(Length(mPlan.CleanedNames)), 'nichts als alter Ort aufgeräumt');
  Assert.IsTrue(MatchText(TDpccIdeCheck.cHelpInsight, mPlan.RestoredNames), 'zurückgedreht');
  mPlan.ApplyTo(mInput);
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), 'Merker entfallen');
  for mValue in mBefore.Values do
  begin
    Assert.AreEqual(mValue.Value, ValueOf(mInput, mValue.Key, mValue.Name), mValue.Key + '\' + mValue.Name);
  end;
end;

procedure TDpccIdeCheckTests.Delphi12BackToLspRestoresLspKey;
const
  cNames: array[0..2] of string = (TDpccIdeCheck.cHelpInsight, TDpccIdeCheck.cDeclarationInformation,
    TDpccIdeCheck.cToolTipWatches);
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mPass: Integer;
  mTrigger: TDpccIdeContextTrigger;
  mName: string;
begin
  // 0: Hauptschalter aus; 1: DelphiLSP im Code-Insight-Dialog der IDE (ProviderChosen: Start mit dem Anbieter).
  for mPass := 0 to 1 do
  begin
    mInput := Delphi12;
    TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn).ApplyTo(mInput);
    Assert.AreEqual('False', ValueOf(mInput, cLsp, TDpccIdeCheck.cHelpInsight), 'dpcc hat Help Insight aus');
    if mPass = 0 then
    begin
      mTrigger := TDpccIdeContextTrigger.MasterOff;
    end
    else
    begin
      mTrigger := TDpccIdeContextTrigger.Start;
      mInput.ProviderId := TDpccIdeCheck.cDelphiLspId;
    end;
    mPlan := TDpccIdeContext.Plan(mInput, mTrigger);
    Assert.AreEqual(Ord(TDpccIdeMode.Ide), Ord(mPlan.Mode), 'Betriebsart IDE, Durchgang ' + IntToStr(mPass));
    for mName in cNames do
    begin
      Assert.IsTrue(HasWrite(mPlan, cLsp, mName, mWrite), mName + ': zurück am Ort von DelphiLSP');
      Assert.IsFalse(mWrite.Delete, mName + ': geschrieben, nicht gelöscht');
      Assert.AreEqual('True', mWrite.Value, mName + ': Wert davor');
      Assert.IsTrue(MatchText(mName, mPlan.RestoredNames), mName + ': als zurückgedreht gemeldet');
    end;
    Assert.IsFalse(WritesAt(mPlan, cPas), 'nichts an Borland.EditOptions.Pascal');
    Assert.AreEqual(0, Integer(Length(mPlan.CleanedNames)), 'nichts aufzuräumen');
    Assert.IsTrue(HasWrite(mPlan, cSrc, TDpccIdeCheck.cProviderValue, mWrite), 'Anbieter zurück');
    Assert.AreEqual(TDpccIdeCheck.cDelphiLspId, mWrite.Value, 'DelphiLSP');
    mPlan.ApplyTo(mInput);
    for mName in cNames do
    begin
      Assert.AreEqual('True', ValueOf(mInput, cLsp, mName), mName + ': wie vorher');
    end;
    Assert.AreEqual(0, Integer(Length(mInput.Markers)), 'Merker entfallen');
    Assert.IsFalse(mInput.HasKey(cPas), 'kein Borland.EditOptions.Pascal angelegt');
    Assert.IsFalse(TDpccIdeContext.Plan(mInput, mTrigger).HasChanges, 'danach nichts mehr zu tun');
  end;
end;

procedure TDpccIdeCheckTests.Delphi12OldPascalMarkersStayValid;
const
  cNames: array[0..2] of string = (TDpccIdeCheck.cHelpInsight, TDpccIdeCheck.cDeclarationInformation,
    TDpccIdeCheck.cToolTipWatches);
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mMarker, mOld: TDpccIdeMarker;
  mName: string;
begin
  // Betriebsart dpcc: Borland.EditOptions.Pascal ist seit HI1 auch unter 23.0 ein Ort der Betriebsart dpcc. Die
  // Werte dort stehen schon so, wie dpcc sie will; die alten Merker bleiben, der Ort von DelphiLSP kommt dazu.
  mInput := Delphi12WithOldMarkers;
  Assert.AreEqual(cPas + ',' + cLsp, string.Join(',', TDpccIdeCheck.DpccKeys(mInput)), 'beide Orte');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccIdeMode.Dpcc), Ord(mPlan.Mode), 'Betriebsart dpcc');
  for mName in cNames do
  begin
    Assert.IsTrue(HasWrite(mPlan, cLsp, mName, mWrite), mName + ': am Ort von DelphiLSP gesetzt');
    Assert.IsFalse(mWrite.Delete, mName + ': am Ort von DelphiLSP nie gelöscht');
    Assert.AreEqual('False', mWrite.Value, mName);
    Assert.IsFalse(HasWrite(mPlan, cPas, mName, mWrite), mName + ': an Pascal nicht gegen das Schreiben aufgeräumt');
    Assert.IsTrue(mInput.TryGetMarker(cPas, mName, mOld), mName + ': alter Merker');
    Assert.IsFalse(MatchText(mOld.StoreName, mPlan.MarkerDeletes), mName + ': alter Merker bleibt');
  end;
  Assert.AreEqual(0, Integer(Length(mPlan.CleanedNames)), 'nichts aufgeräumt');
  Assert.AreEqual(0, Integer(Length(mPlan.RestoredNames)), 'nichts zurückgedreht');
  Assert.IsFalse(ContainsText(mPlan.LogLine, 'aufgeräumt (alter Ort)'), mPlan.LogLine);
  Assert.AreEqual(3, Integer(Length(mPlan.MarkerWrites)), 'neue Merker nur am Ort von DelphiLSP');
  for mMarker in mPlan.MarkerWrites do
  begin
    Assert.AreEqual(cLsp, mMarker.Key, mMarker.Name + ': neuer Merker am Ort von DelphiLSP');
    Assert.IsTrue(mMarker.OriginalExists and (mMarker.Original = 'True'), mMarker.Name + ': davor True');
  end;
  mPlan.ApplyTo(mInput);
  Assert.AreEqual('False', ValueOf(mInput, cPas, TDpccIdeCheck.cHelpInsight), 'Pascal bleibt False');
  Assert.AreEqual(7, Integer(Length(mInput.Markers)), 'Anbieter, drei alte und drei neue Merker');
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start).HasChanges, 'danach nichts mehr');
  // Zurück zu DelphiLSP: am Ort von DelphiLSP wieder True, die von dpcc an Pascal angelegten Werte gelöscht.
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff);
  Assert.AreEqual(0, Integer(Length(mPlan.CleanedNames)), 'Rückweg: nichts als alter Ort gemeldet');
  mPlan.ApplyTo(mInput);
  for mName in cNames do
  begin
    Assert.AreEqual('True', ValueOf(mInput, cLsp, mName), mName + ': am Ort von DelphiLSP zurück');
    Assert.AreEqual('<fehlt>', ValueOf(mInput, cPas, mName), mName + ': an Pascal wieder ohne Wert');
  end;
  Assert.AreEqual(TDpccIdeCheck.cDelphiLspId, mInput.ProviderId, 'Anbieter DelphiLSP');
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), 'Merker entfallen');

  // Betriebsart IDE (DelphiLSP gewählt) mit den alten Merkern: Der Ort von DelphiLSP bleibt unberührt, Pascal wird
  // zurückgedreht (als zurückgedreht gemeldet, nicht als alter Ort).
  mInput := Delphi12WithOldMarkers;
  mInput.ProviderId := TDpccIdeCheck.cDelphiLspId;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccIdeMode.Ide), Ord(mPlan.Mode), 'Betriebsart IDE');
  Assert.IsFalse(WritesAt(mPlan, cLsp), 'Ort von DelphiLSP unberührt');
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cHelpInsight, mWrite) and mWrite.Delete, 'Pascal zurückgedreht');
  Assert.IsTrue(MatchText(TDpccIdeCheck.cHelpInsight, mPlan.RestoredNames), 'als zurückgedreht gemeldet');
  Assert.AreEqual(0, Integer(Length(mPlan.CleanedNames)), 'nicht als alter Ort');
  mPlan.ApplyTo(mInput);
  for mName in cNames do
  begin
    Assert.AreEqual('True', ValueOf(mInput, cLsp, mName), mName + ': am Ort von DelphiLSP wie vorher');
  end;
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), 'Merker entfallen');

  // Vom Nutzer an Pascal geänderter Wert: In der Betriebsart IDE bleibt er, nur der Merker entfällt.
  mInput := Delphi12WithOldMarkers;
  mInput.ProviderId := TDpccIdeCheck.cDelphiLspId;
  mInput.SetValue(cPas, TDpccIdeCheck.cHelpInsight, 'True');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.IsFalse(HasWrite(mPlan, cPas, TDpccIdeCheck.cHelpInsight, mWrite), 'Wert des Nutzers bleibt');
  Assert.IsTrue(MatchText(TDpccIdeCheck.cHelpInsight, mPlan.KeptNames), 'als belassen gemeldet');
  mPlan.ApplyTo(mInput);
  Assert.AreEqual('True', ValueOf(mInput, cPas, TDpccIdeCheck.cHelpInsight), 'wie vom Nutzer gesetzt');
  Assert.IsFalse(mInput.TryGetMarker(cPas, TDpccIdeCheck.cHelpInsight, mOld), 'alter Merker entfällt');
  // In der Betriebsart dpcc setzt dpcc ihn wie unter 37.0 erneut; der Merker behält „kein Wert davor“.
  mInput := Delphi12WithOldMarkers;
  mInput.SetValue(cPas, TDpccIdeCheck.cHelpInsight, 'True');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cHelpInsight, mWrite) and (mWrite.Value = 'False'),
    'in der Betriebsart dpcc erneut gesetzt');
  for mMarker in mPlan.MarkerWrites do
  begin
    if SameText(mMarker.Key, cPas) then
    begin
      Assert.IsFalse(mMarker.OriginalExists, 'Merker behält: kein Wert vor der ersten Änderung');
    end;
  end;
end;

procedure TDpccIdeCheckTests.MarkerOutsideDpccKeysIsCleanedUp(ABaseKey: string);
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mMarker: TDpccIdeMarker;
  mForeign: string;
begin
  if ABaseKey = cBase12 then
  begin
    mInput := Delphi12Keys([cLsp, cPas]);
  end
  else
  begin
    mInput := Delphi13Keys([cLsp, cPas]);
  end;
  mInput.SetValue(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDpccId);
  mInput.ProviderId := TDpccIdeCheck.cDpccId;
  // Ort eines anderen Anbieters unter Code Insight: nie ein Ort der Betriebsart dpcc.
  mForeign := TDpccIdeCheck.ProviderKey('Acme.Insight');
  mInput.SetValue(mForeign, TDpccIdeCheck.cHelpInsight, 'False');
  Assert.IsTrue(TDpccIdeContext.DecodeMarker(ABaseKey, TDpccIdeContext.MarkerName(ABaseKey, mForeign,
    TDpccIdeCheck.cHelpInsight), 'False'#9'=True', mMarker), 'Merker am fremden Ort');
  mInput.Markers := [mMarker];
  Assert.AreEqual(cPas + ',' + cLsp, string.Join(',', TDpccIdeCheck.DpccKeys(mInput)), 'fremder Ort gehört nicht dazu');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccIdeMode.Dpcc), Ord(mPlan.Mode), 'Betriebsart dpcc');
  Assert.IsTrue(HasWrite(mPlan, mForeign, TDpccIdeCheck.cHelpInsight, mWrite) and (mWrite.Value = 'True') and
    not mWrite.Delete, 'an seinem eigenen Ort zurückgedreht');
  Assert.AreEqual(TDpccIdeCheck.cHelpInsight, string.Join(',', mPlan.CleanedNames), 'aufgeräumt');
  Assert.IsTrue(MatchText(mMarker.StoreName, mPlan.MarkerDeletes), 'Merker entfällt');
  Assert.IsTrue(ContainsText(mPlan.LogLine, 'aufgeräumt (alter Ort): Help Insight'), mPlan.LogLine);
  // Die Orte der Betriebsart dpcc werden trotzdem gesetzt.
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cHelpInsight, mWrite) and (mWrite.Value = 'False'), 'Pascal');
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cHelpInsight, mWrite) and (mWrite.Value = 'False'), 'DelphiLSP');
end;

procedure TDpccIdeCheckTests.TooltipOffRestoresOnlyItsSwitches;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
begin
  mInput := Delphi13;
  mInput.SetValue(cPas, TDpccIdeCheck.cHelpInsight, 'True');
  mInput.SetValue(cPas, TDpccIdeCheck.cAutoInvokeDelay, '100');
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn).ApplyTo(mInput);
  mInput.Dpcc.HoverTooltip := False;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccIdeMode.Dpcc), Ord(mPlan.Mode), 'bleibt dpcc');
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cHelpInsight, mWrite), 'Help Insight zurück');
  Assert.AreEqual('True', mWrite.Value);
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cDeclarationInformation, mWrite), 'Declaration zurück');
  Assert.IsFalse(HasWrite(mPlan, cPas, TDpccIdeCheck.cAutoInvokeDelay, mWrite), 'Verzögerung bleibt -1');
  Assert.IsFalse(HasWrite(mPlan, cSrc, TDpccIdeCheck.cProviderValue, mWrite), 'Anbieter bleibt');
end;

procedure TDpccIdeCheckTests.PlanIsIdempotent;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mTrigger: TDpccIdeContextTrigger;
begin
  for mTrigger := Low(TDpccIdeContextTrigger) to High(TDpccIdeContextTrigger) do
  begin
    mInput := Delphi12;
    mInput.SetValue(cLsp, TDpccIdeCheck.cHelpInsight, 'True');
    TDpccIdeContext.Plan(mInput, mTrigger).ApplyTo(mInput);
    mPlan := TDpccIdeContext.Plan(mInput, mTrigger);
    Assert.IsFalse(mPlan.HasChanges, 'Anlass ' + IntToStr(Ord(mTrigger)) + ': ' + mPlan.LogLine);
    Assert.IsTrue(ContainsText(mPlan.LogLine, 'nichts zu ändern'), mPlan.LogLine);
  end;
end;

procedure TDpccIdeCheckTests.ProviderLostAtStartGivesNotice;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
begin
  mInput := Delphi13;
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn).ApplyTo(mInput);
  // Die IDE hat ihre Wahl beim Beenden zurückgeschrieben.
  mInput.SetValue(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDelphiLspId);
  mInput.ProviderId := TDpccIdeCheck.cDelphiLspId;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccIdeMode.Ide), Ord(mPlan.Mode), 'Betriebsart IDE');
  Assert.IsFalse(mPlan.Enabled, 'dpcc aus');
  Assert.IsTrue(ContainsText(mPlan.Notice, 'nicht mehr dpcc'), mPlan.Notice);
  Assert.IsTrue(MatchText(TDpccIdeCheck.cProviderValue, mPlan.KeptNames), 'Anbieter nicht überschrieben');
  Assert.IsTrue(MatchText(TDpccIdeCheck.cDeclarationInformation, mPlan.RestoredNames), 'Schalter zurück');
end;

procedure TDpccIdeCheckTests.LegacyMarkers;
var
  mMarker: TDpccIdeMarker;
begin
  Assert.IsTrue(TDpccIdeContext.DecodeLegacyMarker(cBase13,
    'IdeHelpInsightDisabled 37.0 Borland.EditOptions.Borland.CodeInsight.LSP.Pascal', 1, mMarker), 'mit Ort');
  Assert.AreEqual(cLsp, mMarker.Key);
  Assert.AreEqual(TDpccIdeCheck.cHelpInsight, mMarker.Name);
  Assert.AreEqual('False', mMarker.Written);
  Assert.IsTrue(mMarker.OriginalExists and (mMarker.Original = 'True'), 'davor an');
  Assert.IsTrue(TDpccIdeContext.DecodeLegacyMarker(cBase12, 'IdeTooltipWatchesDisabled 23.0 Borland.EditOptions.Pascal',
    1, mMarker), 'Delphi 12');
  Assert.AreEqual(cPas, mMarker.Key);
  Assert.AreEqual(TDpccIdeCheck.cToolTipWatches, mMarker.Name);
  Assert.IsFalse(TDpccIdeContext.DecodeLegacyMarker(cBase12,
    'IdeHelpInsightDisabled 37.0 Borland.EditOptions.Pascal', 1, mMarker), 'andere Version');
  Assert.IsFalse(TDpccIdeContext.DecodeLegacyMarker(cBase13,
    'IdeHelpInsightDisabled 37.0 Borland.EditOptions.Pascal', 0, mMarker), 'Wert 0');
  Assert.IsTrue(TDpccIdeContext.DecodeLegacyMarker(cBase13, 'IdeHelpInsightDisabled', 1, mMarker),
    'ohne Version ab Delphi 13');
  Assert.AreEqual(cLsp, mMarker.Key, 'Ort von DelphiLSP');
  Assert.IsFalse(TDpccIdeContext.DecodeLegacyMarker(cBase12, 'IdeHelpInsightDisabled', 1, mMarker),
    'ohne Version nicht unter Delphi 12');
  Assert.IsFalse(TDpccIdeContext.DecodeLegacyMarker(cBase13, 'IdeStructureDisabled 37.0 Editor', 1, mMarker),
    'fremder Merker');
end;

procedure TDpccIdeCheckTests.LegacyMarkerIsRestoredAtStart;
var
  mInput: TDpccIdeCheckInput;
  mMarker: TDpccIdeMarker;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
begin
  mInput := Delphi13;
  Assert.IsTrue(TDpccIdeContext.DecodeLegacyMarker(cBase13,
    'IdeHelpInsightDisabled 37.0 Borland.EditOptions.Borland.CodeInsight.LSP.Pascal', 1, mMarker));
  mInput.Markers := [mMarker];
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cHelpInsight, mWrite), 'Help Insight zurück');
  Assert.AreEqual('True', mWrite.Value);
  Assert.IsTrue(MatchText(mMarker.StoreName, mPlan.MarkerDeletes), 'alter Merker entfällt');
end;

procedure TDpccIdeCheckTests.MarkerRoundTrip;
var
  mMarker, mBack: TDpccIdeMarker;
begin
  mMarker := Default(TDpccIdeMarker);
  mMarker.Key := cPas;
  mMarker.Name := TDpccIdeCheck.cAutoInvokeDelay;
  mMarker.Written := '-1';
  mMarker.OriginalExists := True;
  mMarker.Original := '500';
  mMarker.StoreName := TDpccIdeContext.MarkerName(cBase13, mMarker.Key, mMarker.Name);
  Assert.AreEqual('IdeSet 37.0 Code Insight\Borland.EditOptions.Pascal\Auto Invoke Delay', mMarker.StoreName);
  Assert.AreEqual('-1'#9'=500', TDpccIdeContext.EncodeMarker(mMarker));
  Assert.IsTrue(TDpccIdeContext.DecodeMarker(cBase13, mMarker.StoreName, TDpccIdeContext.EncodeMarker(mMarker),
    mBack), 'lesbar');
  Assert.AreEqual(mMarker.Key, mBack.Key);
  Assert.AreEqual(mMarker.Name, mBack.Name);
  Assert.AreEqual('-1', mBack.Written);
  Assert.IsTrue(mBack.OriginalExists and (mBack.Original = '500'), 'Wert davor');
  // Ohne Wert davor, Anbieter mit Punkt im Namen.
  mMarker.Key := cSrc;
  mMarker.Name := TDpccIdeCheck.cProviderValue;
  mMarker.Written := TDpccIdeCheck.cDpccId;
  mMarker.OriginalExists := False;
  mMarker.Original := '';
  mMarker.StoreName := TDpccIdeContext.MarkerName(cBase12, mMarker.Key, mMarker.Name);
  Assert.IsTrue(TDpccIdeContext.DecodeMarker(cBase12, mMarker.StoreName, TDpccIdeContext.EncodeMarker(mMarker),
    mBack), 'ohne Wert davor');
  Assert.AreEqual(cSrc, mBack.Key);
  Assert.AreEqual(TDpccIdeCheck.cProviderValue, mBack.Name);
  Assert.IsFalse(mBack.OriginalExists, 'kein Wert davor');
  Assert.IsFalse(TDpccIdeContext.DecodeMarker(cBase13, mMarker.StoreName, TDpccIdeContext.EncodeMarker(mMarker),
    mBack), 'andere Version');
  Assert.IsFalse(TDpccIdeContext.DecodeMarker(cBase12, mMarker.StoreName, 'kaputt', mBack), 'ohne Tab');
  Assert.IsFalse(TDpccIdeContext.DecodeMarker(cBase12, mMarker.StoreName, 'x'#9'?', mBack), 'unbekannter Inhalt');
  Assert.IsFalse(TDpccIdeContext.DecodeMarker(cBase12, 'HoverTooltip', 'x'#9'-', mBack), 'kein Merker');
end;

procedure TDpccIdeCheckTests.MatchesUsesIdeDefaults;
var
  mValue: TDpccIdeRegValue;
begin
  mValue := Default(TDpccIdeRegValue);
  Assert.IsTrue(TDpccIdeContext.Matches(False, mValue, 'True', TDpccIdeValueKind.Flag), 'Schalter fehlt = an');
  Assert.IsFalse(TDpccIdeContext.Matches(False, mValue, 'False', TDpccIdeValueKind.Flag), 'fehlt ist nicht aus');
  Assert.IsTrue(TDpccIdeContext.Matches(False, mValue, '-1', TDpccIdeValueKind.Number), 'Verzögerung fehlt = -1');
  Assert.IsTrue(TDpccIdeContext.Matches(False, mValue, TDpccIdeCheck.cDelphiLspId, TDpccIdeValueKind.Text),
    'Anbieter fehlt = DelphiLSP');
  mValue.Value := '-5';
  Assert.IsTrue(TDpccIdeContext.Matches(True, mValue, '-1', TDpccIdeValueKind.Number), 'unter 0 = aus');
  mValue.Value := '0';
  Assert.IsFalse(TDpccIdeContext.Matches(True, mValue, '-1', TDpccIdeValueKind.Number), '0 = sofort');
  mValue.Value := 'false';
  Assert.IsTrue(TDpccIdeContext.Matches(True, mValue, 'False', TDpccIdeValueKind.Flag), 'Groß/klein');
  mValue.Value := '1';
  mValue.IsDword := True;
  Assert.IsTrue(TDpccIdeContext.Matches(True, mValue, 'True', TDpccIdeValueKind.Flag), 'DWORD 1');
  mValue.IsDword := False;
  mValue.Value := 'dpcc.codeinsight';
  Assert.IsTrue(TDpccIdeContext.Matches(True, mValue, TDpccIdeCheck.cDpccId, TDpccIdeValueKind.Text), 'Anbieter');
end;

procedure TDpccIdeCheckTests.ErrorInsightAndProviderHint;
var
  mInput: TDpccIdeCheckInput;
  mResult: TDpccIdeCheckResult;
begin
  mInput := Delphi12;
  mInput.Dpcc.Enabled := False;
  mInput.SetValue(cLsp, TDpccIdeCheck.cErrorInsight, 'False');
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual('Error Insight', string.Join(',', mResult.DeviationNames), 'Error Insight aus');
  mInput.ProviderId := TDpccIdeCheck.cDpccId;
  mInput.Dpcc.Enabled := True;
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual(Ord(TDpccIdeProvider.Dpcc), Ord(mResult.Provider), 'Anbieter');
  Assert.IsTrue(CountOf(mResult, TDpccIdeSeverity.Hint) >= 1, 'Hinweis zum Anbieter');
  Assert.IsFalse(MatchText('Error Insight', mResult.DeviationNames), 'Error Insight zählt dann nicht');
  Assert.AreEqual(Ord(TDpccIdeProvider.Other), Ord(TDpccIdeCheck.ProviderOf('Acme.Insight')), 'anderer');
  Assert.AreEqual(Ord(TDpccIdeProvider.Unknown), Ord(TDpccIdeCheck.ProviderOf('  ')), 'leer');
  Assert.AreEqual(TDpccIdeCheck.cCodeInsightRoot + '\Borland.EditOptions.Acme.Insight',
    TDpccIdeCheck.ProviderKey('Acme.Insight'), 'Ort eines anderen Anbieters');
end;

procedure TDpccIdeCheckTests.StatusAndLogLines;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mStatus: string;
begin
  mInput := Delphi13;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.IsTrue(StartsText('IDE-Kontext (Start): Borland.CodeInsight.LSP.Pascal → dpcc aus', mPlan.LogLine),
    mPlan.LogLine);
  mPlan.ApplyTo(mInput);
  mStatus := TDpccIdeContext.StatusText(mInput);
  Assert.IsTrue(StartsText('Betriebsart IDE: Anbieter DelphiLSP, dpcc ist aus.', mStatus), mStatus);
  Assert.IsTrue(ContainsText(mStatus, 'Von dpcc gesetzt: nichts'), mStatus);
  Assert.IsTrue(ContainsText(mStatus, '1 Abweichung: Auto Code Completions'), mStatus);
  // Hauptschalter an, Anbieter umgestellt, aber noch nicht neu gestartet.
  mInput.Dpcc.Enabled := True;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.IsTrue(StartsText('IDE-Kontext (Hauptschalter an): Borland.CodeInsight.LSP.Pascal → dpcc an', mPlan.LogLine),
    mPlan.LogLine);
  Assert.IsTrue(ContainsText(mPlan.LogLine, 'wirkt nach dem Neustart'), mPlan.LogLine);
  mPlan.ApplyTo(mInput);
  mStatus := TDpccIdeContext.StatusText(mInput);
  Assert.IsTrue(StartsText('Betriebsart dpcc', mStatus), mStatus);
  Assert.IsTrue(ContainsText(mStatus, 'Von dpcc gesetzt: Insight Manager, Declaration Information'), mStatus);
  TDpccTextLanguage.Current := TDpccLanguage.English;
  mStatus := TDpccIdeContext.StatusText(mInput);
  Assert.IsTrue(StartsText('Mode dpcc', mStatus), mStatus);
end;

procedure TDpccIdeCheckTests.AutoInvokeIsSetAndRestored;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mMarker: TDpccIdeMarker;
  mFound: Boolean;
begin
  Assert.IsTrue(MatchText(TDpccIdeCheck.cAutoInvoke, TDpccIdeCheck.CodeInsightValueNames), 'wird gelesen');
  Assert.AreEqual('Auto Invoke', TDpccIdeCheck.cAutoInvoke, 'Name des Werts in der Registry');
  // Fehlt der Wert, gilt die Vorgabe der IDE (an): nichts zu schreiben.
  mInput := Delphi13;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.IsFalse(HasWrite(mPlan, cPas, TDpccIdeCheck.cAutoInvoke, mWrite), 'Vorgabe passt');
  // Aus unter Borland.EditOptions.Pascal (unter 37.0 ein Ort der Betriebsart dpcc): setzen, mit Merker und Wert davor.
  mInput := Delphi13;
  mInput.SetValue(cPas, TDpccIdeCheck.cAutoInvoke, 'False');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cAutoInvoke, mWrite), 'Auto Invoke gesetzt');
  Assert.AreEqual('True', mWrite.Value);
  Assert.IsFalse(mWrite.Delete, 'geschrieben, nicht gelöscht');
  Assert.IsTrue(MatchText(TDpccIdeCheck.cAutoInvoke, mPlan.SetNames), 'als gesetzt gemeldet');
  Assert.IsTrue(ContainsText(mPlan.LogLine, TDpccIdeCheck.cAutoInvoke), mPlan.LogLine);
  mFound := False;
  for mMarker in mPlan.MarkerWrites do
  begin
    if SameText(mMarker.Name, TDpccIdeCheck.cAutoInvoke) then
    begin
      mFound := True;
      Assert.AreEqual(cPas, mMarker.Key, 'Ort des Merkers');
      Assert.AreEqual('True', mMarker.Written, 'geschrieben');
      Assert.IsTrue(mMarker.OriginalExists and (mMarker.Original = 'False'), 'Wert davor');
      Assert.AreEqual('IdeSet 37.0 Code Insight\Borland.EditOptions.Pascal\Auto Invoke', mMarker.StoreName);
    end;
  end;
  Assert.IsTrue(mFound, 'Merker für Auto Invoke');
  mPlan.ApplyTo(mInput);
  Assert.AreEqual('True', ValueOf(mInput, cPas, TDpccIdeCheck.cAutoInvoke), 'danach an');
  Assert.AreEqual(0, CountOf(TDpccIdeCheck.Evaluate(mInput), TDpccIdeSeverity.Deviation), 'danach passt alles');
  // Gegenprüfung nach OK: nichts mehr zu tun.
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn).HasChanges, 'idempotent');
  // Die IDE schreibt ihren Stand zurück (Auto Invoke wieder False): die Gegenprüfung setzt ihn erneut, der Merker
  // behält den Wert vor der ersten Änderung.
  mInput.SetValue(cPas, TDpccIdeCheck.cAutoInvoke, 'False');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cAutoInvoke, mWrite) and (mWrite.Value = 'True'),
    'erneut gesetzt');
  mPlan.ApplyTo(mInput);
  // Hauptschalter aus: zurück auf False, Merker entfällt.
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff);
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cAutoInvoke, mWrite), 'zurückgedreht');
  Assert.AreEqual('False', mWrite.Value, 'Wert davor');
  Assert.IsTrue(MatchText(TDpccIdeCheck.cAutoInvoke, mPlan.RestoredNames), 'als zurückgedreht gemeldet');
  mPlan.ApplyTo(mInput);
  Assert.AreEqual('False', ValueOf(mInput, cPas, TDpccIdeCheck.cAutoInvoke), 'wie vorher');
  Assert.IsFalse(mInput.TryGetMarker(cPas, TDpccIdeCheck.cAutoInvoke, mMarker), 'Merker entfallen');
end;

procedure TDpccIdeCheckTests.AutoInvokeOnlyCheckedUnderDelphiLsp;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mResult: TDpccIdeCheckResult;
  mWrite: TDpccIdeWrite;
begin
  mInput := Delphi12;
  mInput.SetValue(cLsp, TDpccIdeCheck.cAutoInvoke, 'False');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccIdeMode.Ide), Ord(mPlan.Mode), 'Betriebsart IDE');
  Assert.IsFalse(HasWrite(mPlan, cLsp, TDpccIdeCheck.cAutoInvoke, mWrite), 'unter DelphiLSP nichts schreiben');
  Assert.AreEqual(0, Integer(Length(mPlan.Writes)), 'nichts zu schreiben');
  mPlan.ApplyTo(mInput);
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual('Auto Invoke', string.Join(',', mResult.DeviationNames), 'nur Protokoll: Abweichung');
  Assert.IsTrue(ContainsText(mResult.LogLine, '1 Abweichung: Auto Invoke'), mResult.LogLine);
end;

procedure TDpccIdeCheckTests.AutoInvokeCaptions;
var
  mInput: TDpccIdeCheckInput;
  mResult: TDpccIdeCheckResult;
  mFinding: TDpccIdeFinding;
  mCompletions, mInvoke: string;
begin
  mInput := Delphi12;
  mInput.Dpcc.Enabled := False;
  mResult := TDpccIdeCheck.Evaluate(mInput);
  mCompletions := '';
  mInvoke := '';
  for mFinding in mResult.Findings do
  begin
    if SameText(mFinding.ValueName, TDpccIdeCheck.cAutoCodeCompletions) then
    begin
      mCompletions := mFinding.Caption;
    end
    else if SameText(mFinding.ValueName, TDpccIdeCheck.cAutoInvoke) then
    begin
      mInvoke := mFinding.Caption;
    end;
  end;
  Assert.AreEqual('Programmierhilfe', mCompletions, 'Auto Code Completions (de)');
  Assert.AreEqual('Automatisch aufrufen', mInvoke, 'Auto Invoke (de)');
  TDpccTextLanguage.Current := TDpccLanguage.English;
  mResult := TDpccIdeCheck.Evaluate(mInput);
  for mFinding in mResult.Findings do
  begin
    if SameText(mFinding.ValueName, TDpccIdeCheck.cAutoCodeCompletions) then
    begin
      Assert.AreEqual('Code completion', mFinding.Caption, 'Auto Code Completions (en)');
    end
    else if SameText(mFinding.ValueName, TDpccIdeCheck.cAutoInvoke) then
    begin
      Assert.AreEqual('Auto invoke', mFinding.Caption, 'Auto Invoke (en)');
    end;
  end;
end;

/// <summary>Gespeicherte Betriebsart Server (Hauptschalter aus, eigene Fenster aus).</summary>
function ServerState: TDpccIdeDpccState;
begin
  Result := State(False, True, True);
  Result.Mode := TDpccOperatingMode.Server;
end;

/// <summary>Delphi 12 bzw. 13 (ABaseKey) mit beiden Orten, Anbieter AProvider ('' = kein Wert) und dpcc-Stand
/// AState.</summary>
function WithProvider(const ABaseKey, AProvider: string; const AState: TDpccIdeDpccState): TDpccIdeCheckInput;
begin
  Result := Delphi13Keys([cLsp, cPas]);
  Result.BaseKey := ABaseKey;
  Result.RemoveValue(cSrc, TDpccIdeCheck.cProviderValue);
  Result.ProviderId := AProvider;
  if AProvider <> '' then
  begin
    Result.SetValue(cSrc, TDpccIdeCheck.cProviderValue, AProvider);
  end;
  Result.Dpcc := AState;
end;

procedure TDpccIdeCheckTests.ServerModeAtStart(ABaseKey: string);
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mProvider: string;
begin
  // DelphiLSP gewählt und ohne Anbieterwert (Vorgabe der IDE = DelphiLSP): Server bleibt, nichts zu tun.
  for mProvider in [TDpccIdeCheck.cDelphiLspId, ''] do
  begin
    mInput := WithProvider(ABaseKey, mProvider, ServerState);
    mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
    Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(mPlan.OperatingMode), 'bleibt Server: "' + mProvider + '"');
    Assert.AreEqual(Ord(TDpccIdeMode.Ide), Ord(mPlan.Mode), 'Code Insight der IDE');
    Assert.IsFalse(mPlan.Enabled, 'eigene Fenster aus');
    Assert.IsFalse(mPlan.OperatingModeChanged, 'nicht geändert');
    Assert.AreEqual(0, Integer(Length(mPlan.Writes)), 'nichts zu schreiben');
    Assert.IsFalse(mPlan.ProviderChanged, 'Anbieter bleibt');
    Assert.IsFalse(mPlan.HasChanges, mPlan.LogLine);
    Assert.IsTrue(ContainsText(mPlan.LogLine, 'Betriebsart Server'), mPlan.LogLine);
  end;
  // dpcc als Anbieter (im Dialog der IDE gewählt): Plugin.
  mInput := WithProvider(ABaseKey, TDpccIdeCheck.cDpccId, ServerState);
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(mPlan.OperatingMode), 'dpcc → Plugin');
  Assert.IsTrue(mPlan.Enabled and mPlan.OperatingModeChanged, 'Plugin an');
  // Ein anderer Anbieter: Aus, mit Hinweis.
  mInput := WithProvider(ABaseKey, 'Borland.CodeInsight.Pascal', ServerState);
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccOperatingMode.Off), Ord(mPlan.OperatingMode), 'anderer Anbieter → Aus');
  Assert.IsTrue(mPlan.OperatingModeChanged, 'geändert');
  Assert.IsTrue(ContainsText(mPlan.Notice, 'anderer Code-Insight-Anbieter'), mPlan.Notice);
  Assert.IsFalse(WritesAt(mPlan, cSrc), 'Anbieter nicht angefasst');
  // Plugin mit DelphiLSP: wie früher Aus.
  mInput := WithProvider(ABaseKey, TDpccIdeCheck.cDelphiLspId, State(True, True, True));
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccOperatingMode.Off), Ord(mPlan.OperatingMode), 'Plugin mit DelphiLSP → Aus');
end;

procedure TDpccIdeCheckTests.ServerOnFromEachMode;
var
  mInput: TDpccIdeCheckInput;
  mPlan, mOff: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mMarker: TDpccIdeMarker;
begin
  // Aus Plugin: vorher ein anderer Anbieter (Merker nennt ihn), dpcc hat auf sich gestellt und Schalter gesetzt.
  mInput := WithProvider(cBase13, 'Acme.Insight', State(True, True, True));
  mInput.SetValue(cLsp, TDpccIdeCheck.cHelpInsight, 'True');
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn).ApplyTo(mInput);
  Assert.AreEqual(TDpccIdeCheck.cDpccId, mInput.ProviderId, 'Plugin: Anbieter dpcc');
  Assert.IsTrue(Length(mInput.Markers) > 1, 'Merker');
  // Zum Vergleich: Aus ginge zum gemerkten Anbieter zurück.
  mOff := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff);
  Assert.AreEqual('Acme.Insight', mOff.ProviderAfter, 'Aus: gemerkter Anbieter');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn);
  Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(mPlan.OperatingMode), 'Server');
  Assert.IsFalse(mPlan.Enabled, 'eigene Fenster aus');
  Assert.IsTrue(HasWrite(mPlan, cSrc, TDpccIdeCheck.cProviderValue, mWrite), 'Anbieter geschrieben');
  Assert.AreEqual(TDpccIdeCheck.cDelphiLspId, mWrite.Value, 'Server: immer DelphiLSP');
  Assert.IsTrue(mPlan.ProviderChanged, 'Anbieter gewechselt');
  Assert.IsTrue(MatchText(TDpccIdeCheck.cHelpInsight, mPlan.RestoredNames), 'Schalter zurück');
  Assert.IsTrue(ContainsText(mPlan.Notice, 'Neustart'), mPlan.Notice);
  Assert.IsTrue(ContainsText(mPlan.Notice, 'dpcc.LspServer.exe'), mPlan.Notice);
  Assert.IsTrue(StartsText('IDE-Kontext (Betriebsart Server)', mPlan.LogLine), mPlan.LogLine);
  mPlan.ApplyTo(mInput);
  Assert.AreEqual('True', ValueOf(mInput, cLsp, TDpccIdeCheck.cHelpInsight), 'Help Insight wieder an');
  // Declaration Information braucht auch der Server: am Ort von DelphiLSP True, der Merker bleibt mit dem Wert vor
  // dem ersten Eingriff für den Rückweg mit Aus; alle anderen Merker entfallen.
  Assert.AreEqual(1, Integer(Length(mInput.Markers)), 'nur der Merker für den Server');
  Assert.IsTrue(mInput.TryGetMarker(cLsp, TDpccIdeCheck.cDeclarationInformation, mMarker),
    'Merker am Ort von DelphiLSP');
  Assert.AreEqual('True', mMarker.Written, 'geschrieben');
  Assert.IsTrue(mMarker.OriginalExists and (mMarker.Original = 'True'), 'Wert vor dem ersten Eingriff');
  Assert.AreEqual('True', ValueOf(mInput, cLsp, TDpccIdeCheck.cDeclarationInformation), 'Declaration Information an');
  Assert.AreEqual('True', ValueOf(mInput, cPas, TDpccIdeCheck.cDeclarationInformation), 'an Pascal zurück');
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn).HasChanges, 'Gegenprüfung: nichts');
  // Aus Aus (DelphiLSP): nichts zu schreiben, wirkt beim nächsten Serverstart der IDE.
  mInput := WithProvider(cBase12, TDpccIdeCheck.cDelphiLspId, State(False, True, True));
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn);
  Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(mPlan.OperatingMode), 'Server');
  Assert.IsTrue(mPlan.OperatingModeChanged, 'geändert');
  Assert.AreEqual(0, Integer(Length(mPlan.Writes)), 'nichts an der IDE');
  Assert.IsFalse(mPlan.ProviderChanged, 'Anbieter bleibt');
  Assert.IsTrue(ContainsText(mPlan.Notice, 'nächsten Start'), mPlan.Notice);
  // Aus einem anderen Anbieter: DelphiLSP.
  mInput := WithProvider(cBase13, 'Acme.Insight', State(False, True, True));
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn);
  Assert.IsTrue(HasWrite(mPlan, cSrc, TDpccIdeCheck.cProviderValue, mWrite), 'Anbieter geschrieben');
  Assert.AreEqual(TDpccIdeCheck.cDelphiLspId, mWrite.Value, 'DelphiLSP');
  Assert.IsTrue(ContainsText(mPlan.Notice, 'Neustart'), mPlan.Notice);
end;

procedure TDpccIdeCheckTests.ServerToOffAndPlugin;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
begin
  mInput := WithProvider(cBase13, TDpccIdeCheck.cDelphiLspId, ServerState);
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff);
  Assert.AreEqual(Ord(TDpccOperatingMode.Off), Ord(mPlan.OperatingMode), 'Aus');
  Assert.IsTrue(mPlan.OperatingModeChanged, 'geändert');
  Assert.AreEqual(0, Integer(Length(mPlan.Writes)), 'nichts an der IDE');
  Assert.IsTrue(ContainsText(mPlan.Notice, 'originale DelphiLSP'), mPlan.Notice);
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(mPlan.OperatingMode), 'Plugin');
  Assert.IsTrue(mPlan.Enabled, 'eigene Fenster an');
  Assert.IsTrue(HasWrite(mPlan, cSrc, TDpccIdeCheck.cProviderValue, mWrite), 'Anbieter');
  Assert.AreEqual(TDpccIdeCheck.cDpccId, mWrite.Value, 'dpcc');
  Assert.IsTrue(ContainsText(mPlan.Notice, 'Neustart'), mPlan.Notice);
end;

procedure TDpccIdeCheckTests.ProviderChoiceInDialog;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
begin
  // Wie TDpccIdeInsightSwitch.ProviderChosen: Start mit dem gewählten Anbieter als Vorgabe.
  mInput := WithProvider(cBase13, TDpccIdeCheck.cDelphiLspId, ServerState);
  mInput.ProviderId := TDpccIdeCheck.cDpccId;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(mPlan.OperatingMode), 'dpcc gewählt → Plugin');
  mInput := WithProvider(cBase13, TDpccIdeCheck.cDpccId, State(True, True, True));
  mInput.ProviderId := TDpccIdeCheck.cDelphiLspId;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccOperatingMode.Off), Ord(mPlan.OperatingMode), 'anderer Anbieter unter Plugin → Aus');
  mInput := WithProvider(cBase12, TDpccIdeCheck.cDelphiLspId, ServerState);
  mInput.ProviderId := TDpccIdeCheck.cDelphiLspId;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(mPlan.OperatingMode), 'DelphiLSP unter Server → Server');
end;

procedure TDpccIdeCheckTests.ServerStatusLines;
var
  mInput: TDpccIdeCheckInput;
  mStatus: string;
begin
  mInput := WithProvider(cBase13, TDpccIdeCheck.cDelphiLspId, ServerState);
  mStatus := TDpccIdeContext.StatusText(mInput);
  Assert.IsTrue(StartsText('Betriebsart Server: Die IDE startet dpcc.LspServer.exe', mStatus), mStatus);
  Assert.IsFalse(ContainsText(mStatus, 'nächsten Start'), 'kein Wechsel offen: ' + mStatus);
  // Server gewählt, aber dpcc noch Anbieter bis zum Neustart.
  mInput := WithProvider(cBase13, TDpccIdeCheck.cDpccId, ServerState);
  mStatus := TDpccIdeContext.StatusText(mInput);
  Assert.IsTrue(ContainsText(mStatus, 'erst dann übernimmt dpcc.LspServer.exe'), mStatus);
  TDpccTextLanguage.Current := TDpccLanguage.English;
  mInput := WithProvider(cBase13, TDpccIdeCheck.cDelphiLspId, ServerState);
  mStatus := TDpccIdeContext.StatusText(mInput);
  Assert.IsTrue(StartsText('Mode Server: the IDE starts dpcc.LspServer.exe', mStatus), mStatus);
end;

const
  /// <summary>Die Code-Insight-Optionen, die dpcc in der Betriebsart Server setzt (Reihenfolge von ServerTargets).
  /// </summary>
  cServerNames: array[0..3] of string = (TDpccIdeCheck.cAutoCodeCompletions, TDpccIdeCheck.cAutoInvoke,
    TDpccIdeCheck.cAutoCodeParameters, TDpccIdeCheck.cDeclarationInformation);

/// <summary>Eigene Kopie: Dynamische Arrays teilen sich sonst die Elemente (SetValue ändert an Ort und Stelle).
/// </summary>
function Clone(const AInput: TDpccIdeCheckInput): TDpccIdeCheckInput;
begin
  Result := AInput;
  Result.Values := Copy(AInput.Values);
  Result.Keys := Copy(AInput.Keys);
  Result.Markers := Copy(AInput.Markers);
end;

/// <summary>Merker von ABaseKey aus Ort, Wertname und Inhalt, wie er unter HKCU\Software\dpcc\IdePlugin steht.
/// </summary>
function MarkerAt(const ABaseKey, AKey, AName, AText: string): TDpccIdeMarker;
begin
  Assert.IsTrue(TDpccIdeContext.DecodeMarker(ABaseKey, TDpccIdeContext.MarkerName(ABaseKey, AKey, AName), AText,
    Result), 'Merker ' + AName);
end;

/// <summary>Schreibt der Plan einen Merker für AKey\AName?</summary>
function HasMarkerWrite(const APlan: TDpccIdeContextPlan; const AKey, AName: string;
  out AMarker: TDpccIdeMarker): Boolean;
var
  mMarker: TDpccIdeMarker;
begin
  for mMarker in APlan.MarkerWrites do
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

/// <summary>Stand des Nutzers unter Delphi 12 (aus der Registry gelesen): Betriebsart Plugin, Anbieter dpcc, nur der
/// Ort von DelphiLSP; dpcc hatte dort Auto Code Completions und Auto Code Parameters auf True (vorher False) und Help
/// Insight, Declaration Information und ToolTip Watches auf False (vorher True) gestellt. Auto Invoke fehlt (an).
/// </summary>
function UserDelphi12: TDpccIdeCheckInput;
begin
  Result := Delphi12;
  Result.SetValue(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDpccId);
  Result.ProviderId := TDpccIdeCheck.cDpccId;
  Result.SetValue(cLsp, TDpccIdeCheck.cHelpInsight, 'False');
  Result.SetValue(cLsp, TDpccIdeCheck.cDeclarationInformation, 'False');
  Result.SetValue(cLsp, TDpccIdeCheck.cToolTipWatches, 'False');
  Result.Markers := [
    MarkerAt(cBase12, cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDpccId + #9'=' + TDpccIdeCheck.cDelphiLspId),
    MarkerAt(cBase12, cLsp, TDpccIdeCheck.cAutoCodeCompletions, 'True'#9'=False'),
    MarkerAt(cBase12, cLsp, TDpccIdeCheck.cAutoCodeParameters, 'True'#9'=False'),
    MarkerAt(cBase12, cLsp, TDpccIdeCheck.cHelpInsight, 'False'#9'=True'),
    MarkerAt(cBase12, cLsp, TDpccIdeCheck.cDeclarationInformation, 'False'#9'=True'),
    MarkerAt(cBase12, cLsp, TDpccIdeCheck.cToolTipWatches, 'False'#9'=True')];
end;

/// <summary>Stand des Nutzers unter Delphi 13 (aus der Registry gelesen): Betriebsart Plugin, Anbieter dpcc, beide
/// Orte; Merker nur für den Anbieter und Declaration Information an Borland.EditOptions.Pascal (False, vorher True).
/// Am Ort von DelphiLSP steht Declaration Information ohne Merker auf False (Wert des Nutzers).</summary>
function UserDelphi13: TDpccIdeCheckInput;
begin
  Result := Delphi13;
  Result.SetValue(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDpccId);
  Result.ProviderId := TDpccIdeCheck.cDpccId;
  Result.SetValue(cLsp, TDpccIdeCheck.cAutoCodeCompletions, 'True');
  Result.SetValue(cPas, TDpccIdeCheck.cDeclarationInformation, 'False');
  Result.Markers := [
    MarkerAt(cBase13, cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDpccId + #9'=' + TDpccIdeCheck.cDelphiLspId),
    MarkerAt(cBase13, cPas, TDpccIdeCheck.cDeclarationInformation, 'False'#9'=True')];
end;

/// <summary>Delphi 12, Betriebsart Aus (DelphiLSP); der Nutzer hat die vier Optionen für den Server selbst aus.
/// </summary>
function OffWithServerOptionsOff: TDpccIdeCheckInput;
var
  mName: string;
begin
  Result := Delphi12;
  Result.Dpcc := State(False, True, True);
  for mName in cServerNames do
  begin
    Result.SetValue(cLsp, mName, 'False');
  end;
end;

procedure TDpccIdeCheckTests.ServerFromOffSetsInsightOptions;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mMarker: TDpccIdeMarker;
  mName: string;
begin
  mInput := OffWithServerOptionsOff;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn);
  Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(mPlan.OperatingMode), 'Server');
  Assert.AreEqual(Ord(TDpccIdeMode.Ide), Ord(mPlan.Mode), 'Code Insight der IDE');
  Assert.IsFalse(mPlan.ProviderChanged, 'Anbieter bleibt DelphiLSP');
  Assert.AreEqual(4, Integer(Length(mPlan.Writes)), 'genau die vier Optionen');
  for mName in cServerNames do
  begin
    Assert.IsTrue(HasWrite(mPlan, cLsp, mName, mWrite) and (mWrite.Value = 'True') and not mWrite.Delete,
      mName + ': am Ort von DelphiLSP True');
  end;
  Assert.IsFalse(WritesAt(mPlan, cPas), 'nichts an Borland.EditOptions.Pascal');
  Assert.IsFalse(HasWrite(mPlan, cLsp, TDpccIdeCheck.cHelpInsight, mWrite), 'Help Insight unberührt');
  Assert.IsFalse(HasWrite(mPlan, cLsp, TDpccIdeCheck.cErrorInsight, mWrite), 'Error Insight unberührt');
  Assert.IsFalse(WritesAt(mPlan, cGlobal), 'InsightGlobalOptions unberührt');
  Assert.AreEqual(4, Integer(Length(mPlan.MarkerWrites)), 'je ein Merker');
  for mMarker in mPlan.MarkerWrites do
  begin
    Assert.AreEqual(cLsp, mMarker.Key, mMarker.Name + ': Ort');
    Assert.AreEqual('True', mMarker.Written, mMarker.Name + ': geschrieben');
    Assert.IsTrue(mMarker.OriginalExists and (mMarker.Original = 'False'), mMarker.Name + ': Wert des Nutzers davor');
    Assert.AreEqual('IdeSet 23.0 ' + cLsp + '\' + mMarker.Name, mMarker.StoreName, 'Name des Merkers');
    Assert.AreEqual('True'#9'=False', TDpccIdeContext.EncodeMarker(mMarker), 'Inhalt des Merkers');
  end;
  Assert.IsTrue(ContainsText(mPlan.Notice, 'nächsten Start des Code-Insight-Servers'), mPlan.Notice);
  Assert.IsTrue(ContainsText(mPlan.Notice, 'erst beim nächsten Start von Delphi'), mPlan.Notice);
  Assert.IsTrue(ContainsText(mPlan.Notice, 'Declaration Information'), mPlan.Notice);
  Assert.IsTrue(ContainsText(mPlan.LogLine,
    'gesetzt: Auto Code Completions, Auto Invoke, Auto Code Parameters, Declaration Information'), mPlan.LogLine);
  mPlan.ApplyTo(mInput);
  Assert.AreEqual(0, CountOf(TDpccIdeCheck.Evaluate(mInput), TDpccIdeSeverity.Deviation), 'danach keine Abweichung');
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn).HasChanges, 'Gegenprüfung: nichts');
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start).HasChanges, 'nächster Start: nichts');
  // Die IDE schreibt beim Beenden ihren Stand aus dem Speicher zurück (dort noch aus): AtExit setzt erneut, der Wert
  // davor bleibt der des Nutzers.
  for mName in cServerNames do
  begin
    mInput.SetValue(cLsp, mName, 'False');
  end;
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn);
  Assert.AreEqual(4, Integer(Length(mPlan.Writes)), 'erneut gesetzt');
  for mMarker in mPlan.MarkerWrites do
  begin
    Assert.IsTrue(mMarker.OriginalExists and (mMarker.Original = 'False'), mMarker.Name + ': Wert davor bleibt');
  end;
  // Ohne Schlüssel (Optionen nie gespeichert): Vorgabe der IDE = an, nichts zu schreiben und nichts anzulegen.
  mInput := Delphi13Keys([]);
  mInput.Dpcc := State(False, True, True);
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn);
  Assert.AreEqual(0, Integer(Length(mPlan.Writes)), 'Vorgabe passt');
  mPlan.ApplyTo(mInput);
  Assert.IsFalse(mInput.HasKey(cLsp), 'Ort von DelphiLSP nicht angelegt');
end;

procedure TDpccIdeCheckTests.PluginToServerWithUserMarkers;
const
  cShared: array[0..1] of string = (TDpccIdeCheck.cAutoCodeCompletions, TDpccIdeCheck.cAutoCodeParameters);
  cPluginOnly: array[0..1] of string = (TDpccIdeCheck.cHelpInsight, TDpccIdeCheck.cToolTipWatches);
var
  mInput, mBack: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mMarker, mOld: TDpccIdeMarker;
  mName: string;
begin
  mInput := UserDelphi12;
  // Ausgangslage stimmt: In der Betriebsart Plugin ist nichts zu tun.
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start).HasChanges, 'Plugin: nichts zu tun');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn);
  Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(mPlan.OperatingMode), 'Server');
  Assert.IsTrue(HasWrite(mPlan, cSrc, TDpccIdeCheck.cProviderValue, mWrite) and
    (mWrite.Value = TDpccIdeCheck.cDelphiLspId), 'Anbieter DelphiLSP');
  // Beide Betriebsarten wollen True: nicht zurück und wieder vor, Merker unverändert (Wert davor False).
  for mName in cShared do
  begin
    Assert.IsFalse(HasWrite(mPlan, cLsp, mName, mWrite), mName + ': kein Schreiben');
    Assert.IsTrue(mInput.TryGetMarker(cLsp, mName, mOld), mName + ': Merker da');
    Assert.IsFalse(MatchText(mOld.StoreName, mPlan.MarkerDeletes), mName + ': Merker bleibt');
    Assert.IsFalse(HasMarkerWrite(mPlan, cLsp, mName, mMarker), mName + ': Merker unverändert');
    Assert.IsFalse(MatchText(mName, mPlan.RestoredNames), mName + ': nicht zurückgedreht');
  end;
  // Declaration Information: Plugin aus, Server an. Der Wert davor bleibt der des Nutzers (True), nicht False.
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cDeclarationInformation, mWrite) and (mWrite.Value = 'True'),
    'Declaration Information True');
  Assert.IsTrue(HasMarkerWrite(mPlan, cLsp, TDpccIdeCheck.cDeclarationInformation, mMarker), 'Merker angepasst');
  Assert.AreEqual('True', mMarker.Written, 'geschrieben');
  Assert.IsTrue(mMarker.OriginalExists and (mMarker.Original = 'True'), 'Wert davor: der des Nutzers');
  Assert.IsFalse(MatchText(mMarker.StoreName, mPlan.MarkerDeletes), 'Merker nicht gelöscht');
  // Nur Plugin: zurück auf den Wert des Nutzers, Merker entfallen.
  for mName in cPluginOnly do
  begin
    Assert.IsTrue(HasWrite(mPlan, cLsp, mName, mWrite) and (mWrite.Value = 'True'), mName + ': zurück');
    Assert.IsTrue(MatchText(mName, mPlan.RestoredNames), mName + ': als zurückgedreht gemeldet');
    Assert.IsTrue(mInput.TryGetMarker(cLsp, mName, mOld) and MatchText(mOld.StoreName, mPlan.MarkerDeletes),
      mName + ': Merker entfällt');
  end;
  Assert.IsFalse(HasWrite(mPlan, cLsp, TDpccIdeCheck.cAutoInvoke, mWrite), 'Auto Invoke fehlt = an');
  Assert.IsTrue(ContainsText(mPlan.Notice, 'Neustart'), mPlan.Notice);
  Assert.IsTrue(ContainsText(mPlan.Notice, 'eingeschaltet: Declaration Information'), mPlan.Notice);
  mPlan.ApplyTo(mInput);
  Assert.AreEqual(TDpccIdeCheck.cDelphiLspId, mInput.ProviderId, 'Anbieter');
  Assert.AreEqual(3, Integer(Length(mInput.Markers)),
    'Merker: Auto Code Completions, Auto Code Parameters, Declaration Information');
  for mName in [TDpccIdeCheck.cAutoCodeCompletions, TDpccIdeCheck.cAutoCodeParameters,
    TDpccIdeCheck.cDeclarationInformation, TDpccIdeCheck.cHelpInsight, TDpccIdeCheck.cToolTipWatches] do
  begin
    Assert.AreEqual('True', ValueOf(mInput, cLsp, mName), mName + ': im Server-Betrieb');
  end;
  Assert.AreEqual(0, CountOf(TDpccIdeCheck.Evaluate(mInput), TDpccIdeSeverity.Deviation), 'Server: keine Abweichung');
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn).HasChanges, 'Gegenprüfung: nichts');
  // Die IDE schreibt ihren Stand aus dem Speicher zurück (die Sitzung lief noch als Plugin): Gegenprüfung bzw. AtExit
  // setzt erneut, und kein Wert, den dpcc als Plugin gesetzt hatte, wird zum Wert davor.
  mBack := Clone(mInput);
  mBack.SetValue(cLsp, TDpccIdeCheck.cDeclarationInformation, 'False');
  mBack.SetValue(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDpccId);
  mBack.ProviderId := TDpccIdeCheck.cDpccId;
  mPlan := TDpccIdeContext.Plan(mBack, TDpccIdeContextTrigger.ServerOn);
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cDeclarationInformation, mWrite) and (mWrite.Value = 'True'),
    'erneut True');
  Assert.IsTrue(HasMarkerWrite(mPlan, cLsp, TDpccIdeCheck.cDeclarationInformation, mMarker) and
    mMarker.OriginalExists and (mMarker.Original = 'True'), 'Wert davor bleibt True');
  Assert.IsTrue(HasWrite(mPlan, cSrc, TDpccIdeCheck.cProviderValue, mWrite) and
    (mWrite.Value = TDpccIdeCheck.cDelphiLspId), 'Anbieter erneut DelphiLSP');
  // Später Aus: die ursprünglichen Werte des Nutzers.
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff).ApplyTo(mInput);
  Assert.AreEqual('False', ValueOf(mInput, cLsp, TDpccIdeCheck.cAutoCodeCompletions), 'Auto Code Completions');
  Assert.AreEqual('False', ValueOf(mInput, cLsp, TDpccIdeCheck.cAutoCodeParameters), 'Auto Code Parameters');
  for mName in [TDpccIdeCheck.cDeclarationInformation, TDpccIdeCheck.cHelpInsight, TDpccIdeCheck.cToolTipWatches] do
  begin
    Assert.AreEqual('True', ValueOf(mInput, cLsp, mName), mName + ': wie vor dpcc');
  end;
  Assert.AreEqual(TDpccIdeCheck.cDelphiLspId, mInput.ProviderId, 'Anbieter DelphiLSP');
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), 'Merker entfallen');
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff).HasChanges, 'danach nichts');
end;

procedure TDpccIdeCheckTests.ServerToPluginKeepsUserValues;
const
  cShared: array[0..1] of string = (TDpccIdeCheck.cAutoCodeCompletions, TDpccIdeCheck.cAutoInvoke);
var
  mInput, mBefore: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mMarker, mOld: TDpccIdeMarker;
  mValue: TDpccIdeRegValue;
  mName: string;
begin
  // Aus (Delphi 13, beide Orte) mit Werten des Nutzers: Programmierhilfe und Automatisch aufrufen aus.
  mInput := WithProvider(cBase13, TDpccIdeCheck.cDelphiLspId, State(False, True, True));
  mInput.SetValue(cLsp, TDpccIdeCheck.cAutoCodeCompletions, 'False');
  mInput.SetValue(cLsp, TDpccIdeCheck.cAutoInvoke, 'False');
  mBefore := Clone(mInput);
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn).ApplyTo(mInput);
  Assert.AreEqual('True', ValueOf(mInput, cLsp, TDpccIdeCheck.cAutoCodeCompletions), 'Server: an');
  // Server → Plugin.
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.AreEqual(Ord(TDpccOperatingMode.Plugin), Ord(mPlan.OperatingMode), 'Plugin');
  for mName in cShared do
  begin
    Assert.IsFalse(HasWrite(mPlan, cLsp, mName, mWrite), mName + ': kein Schreiben');
    Assert.IsFalse(HasMarkerWrite(mPlan, cLsp, mName, mMarker), mName + ': Merker unverändert');
    Assert.IsTrue(mInput.TryGetMarker(cLsp, mName, mOld) and not MatchText(mOld.StoreName, mPlan.MarkerDeletes),
      mName + ': Merker bleibt');
    Assert.IsTrue(mOld.OriginalExists and (mOld.Original = 'False'), mName + ': Wert des Nutzers');
  end;
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cDeclarationInformation, mWrite) and (mWrite.Value = 'False'),
    'Declaration Information aus');
  Assert.IsTrue(HasMarkerWrite(mPlan, cLsp, TDpccIdeCheck.cDeclarationInformation, mMarker) and
    mMarker.OriginalExists and (mMarker.Original = 'True'), 'Declaration Information: Wert davor True');
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cHelpInsight, mWrite) and (mWrite.Value = 'False'),
    'Help Insight aus');
  Assert.IsTrue(HasWrite(mPlan, cSrc, TDpccIdeCheck.cProviderValue, mWrite) and
    (mWrite.Value = TDpccIdeCheck.cDpccId), 'Anbieter dpcc');
  mPlan.ApplyTo(mInput);
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn).HasChanges, 'Gegenprüfung: nichts');
  // Aus: alles wie vor dem ersten Eingriff.
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff).ApplyTo(mInput);
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), 'Merker entfallen');
  for mValue in mBefore.Values do
  begin
    Assert.AreEqual(mValue.Value, ValueOf(mInput, mValue.Key, mValue.Name), mValue.Key + '\' + mValue.Name);
  end;
  Assert.AreEqual(Integer(Length(mBefore.Values)), Integer(Length(mInput.Values)), 'keine neuen Werte');

  // Plugin → Server → Plugin in einer Sitzung: Die IDE schreibt dazwischen ihren Plugin-Stand zurück (Symbol-Insight
  // aus). Der Wert steht dann schon so, wie Plugin ihn will; der Merker gilt danach für False, sonst hielte Aus ihn
  // für fremd geändert.
  mInput := UserDelphi12;
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn).ApplyTo(mInput);
  mInput.SetValue(cLsp, TDpccIdeCheck.cDeclarationInformation, 'False');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.IsFalse(HasWrite(mPlan, cLsp, TDpccIdeCheck.cDeclarationInformation, mWrite), 'steht schon auf False');
  Assert.IsFalse(MatchText(TDpccIdeCheck.cDeclarationInformation, mPlan.SetNames), 'nicht als gesetzt gemeldet');
  Assert.IsTrue(HasMarkerWrite(mPlan, cLsp, TDpccIdeCheck.cDeclarationInformation, mMarker), 'Merker angepasst');
  Assert.AreEqual('False', mMarker.Written, 'gilt jetzt für False');
  Assert.IsTrue(mMarker.OriginalExists and (mMarker.Original = 'True'), 'Wert davor bleibt True');
  mPlan.ApplyTo(mInput);
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn).HasChanges, 'Gegenprüfung: nichts');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff);
  Assert.IsFalse(MatchText(TDpccIdeCheck.cDeclarationInformation, mPlan.KeptNames), 'nicht als fremd belassen');
  mPlan.ApplyTo(mInput);
  Assert.AreEqual('True', ValueOf(mInput, cLsp, TDpccIdeCheck.cDeclarationInformation), 'Wert des Nutzers');
  Assert.AreEqual('False', ValueOf(mInput, cLsp, TDpccIdeCheck.cAutoCodeCompletions), 'Auto Code Completions');
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), 'Merker entfallen');
end;

procedure TDpccIdeCheckTests.ServerToOffRestoresUserValues;
var
  mInput, mBefore: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mValue: TDpccIdeRegValue;
  mName: string;
begin
  mInput := OffWithServerOptionsOff;
  mBefore := Clone(mInput);
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn).ApplyTo(mInput);
  Assert.AreEqual(4, Integer(Length(mInput.Markers)), 'Server: vier Merker');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff);
  Assert.AreEqual(Ord(TDpccOperatingMode.Off), Ord(mPlan.OperatingMode), 'Aus');
  Assert.IsFalse(mPlan.ProviderChanged, 'Anbieter bleibt DelphiLSP');
  Assert.AreEqual(4, Integer(Length(mPlan.Writes)), 'nur die vier Optionen');
  for mName in cServerNames do
  begin
    Assert.IsTrue(HasWrite(mPlan, cLsp, mName, mWrite) and (mWrite.Value = 'False') and not mWrite.Delete,
      mName + ': zurück auf den Wert davor');
    Assert.IsTrue(MatchText(mName, mPlan.RestoredNames), mName + ': als zurückgedreht gemeldet');
  end;
  Assert.AreEqual(0, Integer(Length(mPlan.KeptNames)), 'nichts fremd geändert');
  Assert.IsTrue(ContainsText(mPlan.Notice, 'originale DelphiLSP'), mPlan.Notice);
  mPlan.ApplyTo(mInput);
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), 'Merker entfallen');
  for mValue in mBefore.Values do
  begin
    Assert.AreEqual(mValue.Value, ValueOf(mInput, mValue.Key, mValue.Name), mValue.Key + '\' + mValue.Name);
  end;
  Assert.AreEqual(Integer(Length(mBefore.Values)), Integer(Length(mInput.Values)), 'keine neuen Werte');
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start).HasChanges, 'nächster Start: nichts');
  // Vom Nutzer im Server-Betrieb geändert und seither nicht abgeglichen: bleibt, nur der Merker entfällt.
  mInput := OffWithServerOptionsOff;
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn).ApplyTo(mInput);
  mInput.SetValue(cLsp, TDpccIdeCheck.cAutoCodeParameters, 'False');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff);
  Assert.IsFalse(HasWrite(mPlan, cLsp, TDpccIdeCheck.cAutoCodeParameters, mWrite), 'fremd geändert: nicht schreiben');
  Assert.IsTrue(MatchText(TDpccIdeCheck.cAutoCodeParameters, mPlan.KeptNames), 'als belassen gemeldet');
  mPlan.ApplyTo(mInput);
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), 'Merker entfallen trotzdem');
end;

procedure TDpccIdeCheckTests.ServerStartWithOptionsOff(ABaseKey: string);
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mResult: TDpccIdeCheckResult;
  mWrite: TDpccIdeWrite;
  mMarker: TDpccIdeMarker;
  mName: string;
begin
  mInput := WithProvider(ABaseKey, TDpccIdeCheck.cDelphiLspId, ServerState);
  for mName in cServerNames do
  begin
    mInput.SetValue(cLsp, mName, 'False');
  end;
  // Prüfung in der Betriebsart Server: genau die vier am Ort von DelphiLSP.
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual(cLsp, string.Join(',', mResult.CheckedKeys), 'Ort von DelphiLSP');
  Assert.AreEqual('Auto Code Completions,Auto Invoke,Auto Code Parameters,Declaration Information',
    string.Join(',', mResult.DeviationNames), 'die vier');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(mPlan.OperatingMode), 'bleibt Server');
  Assert.IsFalse(mPlan.OperatingModeChanged, 'nicht geändert');
  Assert.AreEqual(4, Integer(Length(mPlan.Writes)), 'die vier');
  Assert.IsFalse(WritesAt(mPlan, cPas), 'nichts an Borland.EditOptions.Pascal');
  for mName in cServerNames do
  begin
    Assert.IsTrue(HasWrite(mPlan, cLsp, mName, mWrite) and (mWrite.Value = 'True'), mName);
    Assert.IsTrue(HasMarkerWrite(mPlan, cLsp, mName, mMarker), mName + ': Merker');
    Assert.IsTrue(mMarker.OriginalExists and (mMarker.Original = 'False'), mName + ': Wert davor');
    Assert.AreEqual(TDpccIdeContext.MarkerName(ABaseKey, cLsp, mName), mMarker.StoreName, mName + ': Name');
  end;
  Assert.IsTrue(ContainsText(mPlan.Notice, 'erst beim nächsten Start von Delphi'), mPlan.Notice);
  mPlan.ApplyTo(mInput);
  Assert.AreEqual(0, CountOf(TDpccIdeCheck.Evaluate(mInput), TDpccIdeSeverity.Deviation), 'danach keine Abweichung');
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start).HasChanges, 'danach nichts');
  // Der Nutzer schaltet eine Option im Server-Betrieb wieder aus: Der nächste Abgleich (Gegenprüfung, Beenden, Start)
  // setzt sie erneut; der Merker behält den Wert vor dem ersten Eingriff.
  mInput.SetValue(cLsp, TDpccIdeCheck.cAutoCodeCompletions, 'False');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cAutoCodeCompletions, mWrite) and (mWrite.Value = 'True'),
    'erneut gesetzt');
  Assert.IsTrue(HasMarkerWrite(mPlan, cLsp, TDpccIdeCheck.cAutoCodeCompletions, mMarker) and
    (mMarker.Original = 'False'), 'Wert davor bleibt');

  // Dieselbe Regel wie in der Betriebsart Plugin, erst ohne Merker: alles an, der Nutzer schaltet im Dialog der IDE
  // Symbol-Insight aus. dpcc setzt es beim nächsten Abgleich wieder, der Merker nimmt den Wert des Nutzers, Aus stellt
  // ihn her.
  mInput := WithProvider(ABaseKey, TDpccIdeCheck.cDelphiLspId, ServerState);
  mInput.SetValue(cLsp, TDpccIdeCheck.cDeclarationInformation, 'False');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cDeclarationInformation, mWrite) and (mWrite.Value = 'True'),
    'Server: wieder an');
  Assert.IsTrue(HasMarkerWrite(mPlan, cLsp, TDpccIdeCheck.cDeclarationInformation, mMarker) and
    (mMarker.Original = 'False'), 'Server: Merker mit dem Wert des Nutzers');
  mPlan.ApplyTo(mInput);
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff).ApplyTo(mInput);
  Assert.AreEqual('False', ValueOf(mInput, cLsp, TDpccIdeCheck.cDeclarationInformation),
    'Server → Aus: Wert des Nutzers');
  // Zum Vergleich die Betriebsart Plugin mit Programmierhilfe.
  mInput := WithProvider(ABaseKey, TDpccIdeCheck.cDpccId, State(True, True, True));
  mInput.SetValue(cLsp, TDpccIdeCheck.cAutoCodeCompletions, 'False');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cAutoCodeCompletions, mWrite) and (mWrite.Value = 'True'),
    'Plugin: wieder an');
  Assert.IsTrue(HasMarkerWrite(mPlan, cLsp, TDpccIdeCheck.cAutoCodeCompletions, mMarker) and
    (mMarker.Original = 'False'), 'Plugin: Merker mit dem Wert des Nutzers');
  mPlan.ApplyTo(mInput);
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff).ApplyTo(mInput);
  Assert.AreEqual('False', ValueOf(mInput, cLsp, TDpccIdeCheck.cAutoCodeCompletions), 'Plugin → Aus: Wert des Nutzers');
end;

procedure TDpccIdeCheckTests.UserMarkersBeforeUpdate;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mMarker: TDpccIdeMarker;
  mName: string;
begin
  // Namen und Inhalt, wie sie beim Nutzer unter HKCU\Software\dpcc\IdePlugin stehen.
  Assert.AreEqual('IdeSet 23.0 Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal\Auto Code Completions',
    TDpccIdeContext.MarkerName(cBase12, cLsp, TDpccIdeCheck.cAutoCodeCompletions), 'Name 23.0');
  Assert.IsTrue(TDpccIdeContext.DecodeMarker(cBase12,
    'IdeSet 23.0 Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal\Auto Code Completions',
    'True'#9'=False', mMarker), 'lesbar');
  Assert.AreEqual(cLsp, mMarker.Key, 'Ort');
  Assert.AreEqual(TDpccIdeCheck.cAutoCodeCompletions, mMarker.Name, 'Wert');
  Assert.AreEqual('True', mMarker.Written, 'von dpcc gesetzt');
  Assert.IsTrue(mMarker.OriginalExists and (mMarker.Original = 'False'), 'Wert des Nutzers');
  Assert.AreEqual('IdeSet 23.0 Editor\Source Options\Borland.EditOptions.Pascal\Insight Manager',
    TDpccIdeContext.MarkerName(cBase12, cSrc, TDpccIdeCheck.cProviderValue), 'Anbieter 23.0');
  Assert.AreEqual('IdeSet 37.0 Code Insight\Borland.EditOptions.Pascal\Declaration Information',
    TDpccIdeContext.MarkerName(cBase13, cPas, TDpccIdeCheck.cDeclarationInformation), 'Name 37.0');

  // Delphi 12: Server, danach Aus (ausführlich in PluginToServerWithUserMarkers).
  mInput := UserDelphi12;
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn).ApplyTo(mInput);
  Assert.AreEqual('True', ValueOf(mInput, cLsp, TDpccIdeCheck.cAutoCodeCompletions), '23.0 Server: an');
  Assert.AreEqual('True', ValueOf(mInput, cLsp, TDpccIdeCheck.cAutoCodeParameters), '23.0 Server: an');
  Assert.AreEqual('True', ValueOf(mInput, cLsp, TDpccIdeCheck.cDeclarationInformation), '23.0 Server: an');
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff).ApplyTo(mInput);
  Assert.AreEqual('False', ValueOf(mInput, cLsp, TDpccIdeCheck.cAutoCodeCompletions), '23.0 Aus');
  Assert.AreEqual('False', ValueOf(mInput, cLsp, TDpccIdeCheck.cAutoCodeParameters), '23.0 Aus');
  for mName in [TDpccIdeCheck.cDeclarationInformation, TDpccIdeCheck.cHelpInsight, TDpccIdeCheck.cToolTipWatches] do
  begin
    Assert.AreEqual('True', ValueOf(mInput, cLsp, mName), '23.0 Aus: ' + mName);
  end;
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), '23.0: Merker entfallen');

  // Delphi 13: Der Merker an Borland.EditOptions.Pascal geht zurück (liest die IDE mit DelphiLSP nicht); am Ort von
  // DelphiLSP setzt der Server Declaration Information mit dem Wert des Nutzers (False) als Wert davor.
  mInput := UserDelphi13;
  Assert.IsFalse(TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start).HasChanges, '37.0 Plugin: nichts');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.ServerOn);
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cDeclarationInformation, mWrite) and (mWrite.Value = 'True'),
    '37.0: Pascal zurück');
  Assert.IsTrue(MatchText(TDpccIdeCheck.cDeclarationInformation, mPlan.RestoredNames), '37.0: zurückgedreht');
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cDeclarationInformation, mWrite) and (mWrite.Value = 'True'),
    '37.0: DelphiLSP für den Server');
  Assert.IsTrue(HasMarkerWrite(mPlan, cLsp, TDpccIdeCheck.cDeclarationInformation, mMarker) and
    mMarker.OriginalExists and (mMarker.Original = 'False'), '37.0: Wert des Nutzers als Wert davor');
  mPlan.ApplyTo(mInput);
  Assert.AreEqual(1, Integer(Length(mInput.Markers)), '37.0: ein Merker für den Server');
  Assert.AreEqual(0, CountOf(TDpccIdeCheck.Evaluate(mInput), TDpccIdeSeverity.Deviation), '37.0: keine Abweichung');
  TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff).ApplyTo(mInput);
  Assert.AreEqual('False', ValueOf(mInput, cLsp, TDpccIdeCheck.cDeclarationInformation), '37.0 Aus: DelphiLSP');
  Assert.AreEqual('True', ValueOf(mInput, cPas, TDpccIdeCheck.cDeclarationInformation), '37.0 Aus: Pascal');
  Assert.AreEqual(TDpccIdeCheck.cDelphiLspId, mInput.ProviderId, '37.0: Anbieter DelphiLSP');
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), '37.0: Merker entfallen');

  // Älterer DWORD-Merker (vor IDECHECK) für Help Insight: kein Ziel des Servers, also zurück.
  mInput := Delphi12;
  mInput.Dpcc := ServerState;
  mInput.SetValue(cLsp, TDpccIdeCheck.cHelpInsight, 'False');
  Assert.IsTrue(TDpccIdeContext.DecodeLegacyMarker(cBase12,
    'IdeHelpInsightDisabled 23.0 Borland.EditOptions.Borland.CodeInsight.LSP.Pascal', 1, mMarker), 'DWORD-Merker');
  mInput.Markers := [mMarker];
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccOperatingMode.Server), Ord(mPlan.OperatingMode), 'Server');
  Assert.IsTrue(HasWrite(mPlan, cLsp, TDpccIdeCheck.cHelpInsight, mWrite) and (mWrite.Value = 'True'),
    'Help Insight zurück');
  Assert.IsTrue(MatchText(mMarker.StoreName, mPlan.MarkerDeletes), 'DWORD-Merker entfällt');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccIdeCheckTests);

end.
