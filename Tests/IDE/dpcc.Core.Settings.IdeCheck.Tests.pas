unit dpcc.Core.Settings.IdeCheck.Tests;

// Tests für die Betriebsart von dpcc in der IDE (Auftrag IDECHECK, dpcc.Core.Settings.IdeCheck), ohne Registry:
// Prüfregeln für Delphi 12 (BDS 23.0) und Delphi 13 (BDS 37.0), fehlende Werte und Schlüssel, die Schreibaktionen
// beim Start und mit dem Hauptschalter in beide Richtungen, Rückdrehen nur eigener Änderungen, fremd geänderte Werte
// bleiben, ältere Merker (IdeHelpInsightDisabled …) und das Format der neuen Merker. Die Eingaben spiegeln den
// gelesenen Stand der Prüfrechner (Delphi 13: Auto Code Completions = False unter DelphiLSP; Delphi 12: nur der Ort
// von DelphiLSP, kein Borland.EditOptions.Pascal).

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
    /// <summary>Hauptschalter an (Delphi 13): Anbieter auf dpcc, nur die abweichenden Schalter am Ort von dpcc, je ein
    /// Merker mit dem Wert davor; danach keine Abweichung.</summary>
    [Test]
    procedure Delphi13MasterOnSetsProviderAndSwitches;
    /// <summary>Hauptschalter an, dann aus: alles wieder wie vorher, keine Merker.</summary>
    [Test]
    [TestCase('Delphi 12', 'Software\Embarcadero\BDS\23.0')]
    [TestCase('Delphi 13', 'Software\Embarcadero\BDS\37.0')]
    procedure MasterOnThenOffRestoresEverything(ABaseKey: string);
    /// <summary>Fremd geänderter Wert (Nutzer oder IDE) bleibt beim Rückweg; nur der Merker entfällt.</summary>
    [Test]
    procedure RestoreKeepsForeignChange;
    /// <summary>Delphi 12, dpcc gewählt, Ort von dpcc fehlt: Hauptschalter an, Schalter gesetzt (Merker ohne Wert
    /// davor); aus löscht sie wieder und stellt DelphiLSP ein.</summary>
    [Test]
    procedure Delphi12StartWithDpccSetsSwitches;
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
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  dpcc.Core.Localization.Language,
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
  Result.Enabled := AEnabled;
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
  // Die Werte des Editors (Ort von dpcc) zählen unter DelphiLSP nicht.
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
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  Assert.AreEqual(Ord(TDpccIdeMode.Dpcc), Ord(mPlan.Mode), 'Betriebsart');
  Assert.IsTrue(mPlan.Enabled, 'dpcc an');
  Assert.IsFalse(mPlan.EnabledChanged, 'war schon an');
  Assert.IsTrue(mPlan.ProviderChanged, 'Anbieter umgestellt');
  Assert.AreNotEqual('', mPlan.Notice, 'Hinweis zum Neustart');
  // Nur Anbieter und Declaration Information weichen ab (am Ort von dpcc ist der Rest schon passend).
  Assert.AreEqual(2, Integer(Length(mPlan.Writes)), 'Schreibaktionen');
  Assert.IsTrue(HasWrite(mPlan, cSrc, TDpccIdeCheck.cProviderValue, mWrite), 'Anbieter');
  Assert.AreEqual(TDpccIdeCheck.cDpccId, mWrite.Value);
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cDeclarationInformation, mWrite), 'Declaration Information');
  Assert.AreEqual('False', mWrite.Value);
  Assert.IsFalse(HasWrite(mPlan, cLsp, TDpccIdeCheck.cAutoCodeCompletions, mWrite), 'Ort von DelphiLSP bleibt');
  Assert.AreEqual(2, Integer(Length(mPlan.MarkerWrites)), 'Merker');
  for mMarker in mPlan.MarkerWrites do
  begin
    Assert.IsTrue(mMarker.OriginalExists, mMarker.Name + ': Wert davor');
    Assert.IsTrue(StartsText('IdeSet 37.0 ', mMarker.StoreName), mMarker.StoreName);
    if SameText(mMarker.Name, TDpccIdeCheck.cProviderValue) then
    begin
      Assert.AreEqual(TDpccIdeCheck.cDelphiLspId, mMarker.Original, 'Anbieter davor');
    end
    else
    begin
      Assert.AreEqual('True', mMarker.Original, 'Declaration Information davor');
    end;
  end;
  mPlan.ApplyTo(mInput);
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual(cPas, mResult.ActiveKey, 'Ort von dpcc');
  Assert.AreEqual(0, CountOf(mResult, TDpccIdeSeverity.Deviation), 'danach passt alles: ' + mResult.Report);
  Assert.IsTrue(ContainsText(mPlan.LogLine, 'gesetzt: Insight Manager, Declaration Information'), mPlan.LogLine);
end;

procedure TDpccIdeCheckTests.MasterOnThenOffRestoresEverything(ABaseKey: string);
var
  mInput, mBefore: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mValue: TDpccIdeRegValue;
begin
  if ABaseKey = cBase12 then
  begin
    mInput := Delphi12;
  end
  else
  begin
    mInput := Delphi13;
  end;
  // Abweichende Werte am Ort von dpcc, damit alle Schalter geschrieben werden.
  mInput.SetValue(cPas, TDpccIdeCheck.cAutoCodeCompletions, 'False');
  mInput.SetValue(cPas, TDpccIdeCheck.cAutoInvokeDelay, '300');
  mInput.SetValue(cPas, TDpccIdeCheck.cHelpInsight, 'True');
  mInput.SetValue(cGlobal, TDpccIdeCheck.cAutoInvokeOnParameterInsight, 'True');
  // Eigene Kopie der Werte: Dynamische Arrays teilen sich sonst die Elemente.
  mBefore := mInput;
  mBefore.Values := Copy(mInput.Values);
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOn);
  mPlan.ApplyTo(mInput);
  Assert.AreEqual(TDpccIdeCheck.cDpccId, mInput.ProviderId, 'Anbieter dpcc');
  Assert.AreEqual('-1', ValueOf(mInput, cPas, TDpccIdeCheck.cAutoInvokeDelay), 'Verzögerung');
  Assert.AreEqual('False', ValueOf(mInput, cGlobal, TDpccIdeCheck.cAutoInvokeOnParameterInsight), 'global');
  Assert.IsTrue(Length(mInput.Markers) >= 5, 'Merker');
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

procedure TDpccIdeCheckTests.Delphi12StartWithDpccSetsSwitches;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
  mWrite: TDpccIdeWrite;
  mMarker: TDpccIdeMarker;
  mResult: TDpccIdeCheckResult;
begin
  mInput := Delphi12;
  // Im Code-Insight-Dialog der IDE dpcc gewählt, dpcc war aus.
  mInput.SetValue(cSrc, TDpccIdeCheck.cProviderValue, TDpccIdeCheck.cDpccId);
  mInput.ProviderId := TDpccIdeCheck.cDpccId;
  mInput.Dpcc.Enabled := False;
  mResult := TDpccIdeCheck.Evaluate(mInput);
  Assert.AreEqual(cPas, mResult.ActiveKey, 'Ort von dpcc');
  Assert.IsTrue(mResult.ActiveKeyMissing, 'unter 23.0 fehlt er hier');
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.Start);
  Assert.AreEqual(Ord(TDpccIdeMode.Dpcc), Ord(mPlan.Mode), 'Betriebsart dpcc');
  Assert.IsTrue(mPlan.Enabled and mPlan.EnabledChanged, 'Hauptschalter an');
  Assert.IsFalse(mPlan.ProviderChanged, 'Anbieter ist schon dpcc');
  // Fehlende Werte mit passender Vorgabe (Auto Code Completions, Verzögerung, Parameter) bleiben unberührt.
  Assert.IsFalse(HasWrite(mPlan, cPas, TDpccIdeCheck.cAutoCodeCompletions, mWrite), 'Vorgabe passt');
  Assert.IsFalse(HasWrite(mPlan, cPas, TDpccIdeCheck.cAutoInvokeDelay, mWrite), 'Vorgabe -1 passt');
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cHelpInsight, mWrite), 'Help Insight');
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cDeclarationInformation, mWrite), 'Declaration Information');
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cToolTipWatches, mWrite), 'ToolTip Watches');
  Assert.AreEqual(3, Integer(Length(mPlan.Writes)), 'Schreibaktionen');
  for mMarker in mPlan.MarkerWrites do
  begin
    Assert.IsFalse(mMarker.OriginalExists, mMarker.Name + ': vorher kein Wert');
    Assert.IsTrue(StartsText('IdeSet 23.0 ', mMarker.StoreName), mMarker.StoreName);
  end;
  mPlan.ApplyTo(mInput);
  Assert.AreEqual(0, CountOf(TDpccIdeCheck.Evaluate(mInput), TDpccIdeSeverity.Deviation), 'danach passt alles');
  // Hauptschalter aus: Werte wieder gelöscht, Anbieter DelphiLSP (kein Merker: Vorgabe).
  mPlan := TDpccIdeContext.Plan(mInput, TDpccIdeContextTrigger.MasterOff);
  Assert.IsTrue(HasWrite(mPlan, cPas, TDpccIdeCheck.cHelpInsight, mWrite) and mWrite.Delete, 'Help Insight löschen');
  Assert.IsTrue(HasWrite(mPlan, cSrc, TDpccIdeCheck.cProviderValue, mWrite), 'Anbieter zurück');
  Assert.AreEqual(TDpccIdeCheck.cDelphiLspId, mWrite.Value, 'DelphiLSP');
  mPlan.ApplyTo(mInput);
  Assert.AreEqual('<fehlt>', ValueOf(mInput, cPas, TDpccIdeCheck.cDeclarationInformation), 'gelöscht');
  Assert.AreEqual(0, Integer(Length(mInput.Markers)), 'Merker entfallen');
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
  // Aus am Ort von dpcc: setzen, mit Merker und Wert davor.
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

initialization
  TDUnitX.RegisterTestFixture(TDpccIdeCheckTests);

end.
