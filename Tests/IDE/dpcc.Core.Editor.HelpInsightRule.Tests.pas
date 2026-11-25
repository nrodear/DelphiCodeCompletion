unit dpcc.Core.Editor.HelpInsightRule.Tests;

// Tests für die Regel „Fenster von Help Insight der IDE verbergen“ (Auftrag HI1, dpcc.Core.Editor.HelpInsightRule):
// alle Kombinationen aus dpcc an/aus, eigenem Tooltip und offenem Popup, fremde Fensterklassen, Groß-/Kleinschreibung
// der Klasse, Gründe fürs Protokoll und die Diagnosezeile zu den Registry-Werten (fehlender Schlüssel bzw. Wert).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccHelpInsightRuleTests = class
  public
    /// <summary>Alle acht Kombinationen mit der Klasse THelpInsightWindow: aus = nie; eigener Tooltip an = immer
    /// (Grund eigener Tooltip, auch mit offenem Popup); sonst nur mit offenem Popup.</summary>
    [Test]
    procedure AllCombinations;
    /// <summary>Fremde Klassen (auch ähnliche Namen, leer, mit Leerzeichen) werden in keiner Kombination verborgen.
    /// </summary>
    [Test]
    procedure ForeignClassIsNeverHidden;
    /// <summary>Die Klasse ohne Groß-/Kleinschreibung.</summary>
    [Test]
    [TestCase('klein', 'thelpinsightwindow')]
    [TestCase('groß', 'THELPINSIGHTWINDOW')]
    [TestCase('gemischt', 'tHelpinsightWINDOW')]
    procedure ClassNameIgnoresCase(AClassName: string);
    /// <summary>Konstante der Klasse und Gründe fürs Protokoll.</summary>
    [Test]
    procedure ConstantsAndReasonTexts;
    /// <summary>Diagnose: Orte, Text je Eintrag (Wert, Wert fehlt, Schlüssel fehlt), ganze Zeile.</summary>
    [Test]
    procedure RegistryLine;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Settings.IdeCheck,
  dpcc.Core.Editor.HelpInsightRule;

const
  cClass = TDpccHelpInsightRule.cWindowClass;

function CaseText(AActive, AOwn, APopup: Boolean): string;
begin
  Result := Format('aktiv=%s Tooltip=%s Popup=%s', [BoolToStr(AActive, True), BoolToStr(AOwn, True),
    BoolToStr(APopup, True)]);
end;

{ TDpccHelpInsightRuleTests }

procedure TDpccHelpInsightRuleTests.AllCombinations;
var
  mActive, mOwn, mPopup: Boolean;
  mExpected, mActual: TDpccHelpInsightHideReason;
begin
  for mActive := False to True do
  begin
    for mOwn := False to True do
    begin
      for mPopup := False to True do
      begin
        if not mActive then
        begin
          mExpected := TDpccHelpInsightHideReason.None;
        end
        else if mOwn then
        begin
          mExpected := TDpccHelpInsightHideReason.OwnTooltip;
        end
        else if mPopup then
        begin
          mExpected := TDpccHelpInsightHideReason.PopupOpen;
        end
        else
        begin
          mExpected := TDpccHelpInsightHideReason.None;
        end;
        mActual := TDpccHelpInsightRule.Decide(cClass, mActive, mOwn, mPopup);
        Assert.AreEqual(Ord(mExpected), Ord(mActual), CaseText(mActive, mOwn, mPopup));
        Assert.IsTrue((mExpected <> TDpccHelpInsightHideReason.None) =
          TDpccHelpInsightRule.ShouldHide(cClass, mActive, mOwn, mPopup), 'ShouldHide ' +
          CaseText(mActive, mOwn, mPopup));
      end;
    end;
  end;
  // Die drei Fälle des Auftrags ausdrücklich.
  Assert.IsFalse(TDpccHelpInsightRule.ShouldHide(cClass, False, True, True), 'dpcc aus: nie');
  Assert.IsTrue(TDpccHelpInsightRule.ShouldHide(cClass, True, True, False), 'eigener Tooltip an: immer');
  Assert.IsTrue(TDpccHelpInsightRule.ShouldHide(cClass, True, False, True), 'Popup offen: auch ohne Tooltip');
  Assert.IsFalse(TDpccHelpInsightRule.ShouldHide(cClass, True, False, False), 'weder Tooltip noch Popup');
end;

procedure TDpccHelpInsightRuleTests.ForeignClassIsNeverHidden;
const
  // Leer, Tooltip von dpcc, Kurzhinweis, Liste der IDE, ähnliche Namen, Leerzeichen davor bzw. dahinter.
  cForeign: array[0..7] of string = ('', 'TDpccHoverTip', 'THintWindow', 'TCodeCompletionListBox',
    'THelpInsightWindowEx', 'THelpInsight', ' THelpInsightWindow', 'THelpInsightWindow ');
var
  mClass: string;
  mActive, mOwn, mPopup: Boolean;
begin
  for mClass in cForeign do
  begin
    Assert.IsFalse(TDpccHelpInsightRule.IsHelpInsightWindow(mClass), '„' + mClass + '“: keine Klasse von Help Insight');
    for mActive := False to True do
    begin
      for mOwn := False to True do
      begin
        for mPopup := False to True do
        begin
          Assert.AreEqual(Ord(TDpccHelpInsightHideReason.None),
            Ord(TDpccHelpInsightRule.Decide(mClass, mActive, mOwn, mPopup)),
            '„' + mClass + '“ ' + CaseText(mActive, mOwn, mPopup));
        end;
      end;
    end;
  end;
end;

procedure TDpccHelpInsightRuleTests.ClassNameIgnoresCase(AClassName: string);
begin
  Assert.IsTrue(TDpccHelpInsightRule.IsHelpInsightWindow(AClassName), AClassName);
  Assert.AreEqual(Ord(TDpccHelpInsightHideReason.OwnTooltip),
    Ord(TDpccHelpInsightRule.Decide(AClassName, True, True, False)), 'eigener Tooltip');
  Assert.AreEqual(Ord(TDpccHelpInsightHideReason.PopupOpen),
    Ord(TDpccHelpInsightRule.Decide(AClassName, True, False, True)), 'Popup offen');
  Assert.AreEqual(Ord(TDpccHelpInsightHideReason.None),
    Ord(TDpccHelpInsightRule.Decide(AClassName, False, True, True)), 'dpcc aus');
end;

procedure TDpccHelpInsightRuleTests.ConstantsAndReasonTexts;
begin
  Assert.AreEqual('THelpInsightWindow', TDpccHelpInsightRule.cWindowClass, 'Klasse aus coreide');
  Assert.AreEqual('Help Insight', TDpccHelpInsightRule.cValueName, 'Registry-Wert');
  Assert.AreEqual(TDpccIdeCheck.cHelpInsight, TDpccHelpInsightRule.cValueName, 'derselbe Name wie in IdeCheck');
  Assert.AreEqual('eigener Tooltip an', TDpccHelpInsightRule.ReasonText(TDpccHelpInsightHideReason.OwnTooltip));
  Assert.AreEqual('Popup offen', TDpccHelpInsightRule.ReasonText(TDpccHelpInsightHideReason.PopupOpen));
  Assert.AreEqual('keiner', TDpccHelpInsightRule.ReasonText(TDpccHelpInsightHideReason.None));
end;

procedure TDpccHelpInsightRuleTests.RegistryLine;
var
  mKeys: TArray<string>;
  mEntries: TArray<TDpccHelpInsightRegEntry>;
  mEntry: TDpccHelpInsightRegEntry;
begin
  mKeys := TDpccHelpInsightRule.DiagnosisKeys;
  Assert.AreEqual(TDpccIdeCheck.cLspKey + '|' + TDpccIdeCheck.cPascalKey + '|' +
    'Code Insight\Borland.EditOptions.HTML', string.Join('|', mKeys), 'Orte in dieser Reihenfolge');
  Assert.AreEqual('Code Insight\Borland.EditOptions.HTML', TDpccHelpInsightRule.cHtmlKey, 'Ort für HTML');
  // Ohne Schlüssel kein Wert, auch wenn einer übergeben wird.
  mEntry := TDpccHelpInsightRegEntry.Create(TDpccIdeCheck.cPascalKey, False, True, 'True');
  Assert.IsFalse(mEntry.ValueExists, 'ohne Schlüssel kein Wert');
  Assert.AreEqual('(Schlüssel fehlt)', TDpccHelpInsightRule.EntryText(mEntry));
  mEntry := TDpccHelpInsightRegEntry.Create(TDpccIdeCheck.cPascalKey, True, False, '');
  Assert.AreEqual('(Wert fehlt)', TDpccHelpInsightRule.EntryText(mEntry));
  mEntry := TDpccHelpInsightRegEntry.Create(TDpccIdeCheck.cLspKey, True, True, 'False');
  Assert.AreEqual('False', TDpccHelpInsightRule.EntryText(mEntry));
  mEntries := [
    TDpccHelpInsightRegEntry.Create(mKeys[0], True, True, 'False'),
    TDpccHelpInsightRegEntry.Create(mKeys[1], False, False, ''),
    TDpccHelpInsightRegEntry.Create(mKeys[2], True, True, '0')];
  Assert.AreEqual('Help Insight in der Registry (23.0): Borland.EditOptions.Borland.CodeInsight.LSP.Pascal = False; ' +
    'Borland.EditOptions.Pascal = (Schlüssel fehlt); Borland.EditOptions.HTML = 0',
    TDpccHelpInsightRule.RegistryLine('Software\Embarcadero\BDS\23.0', mEntries));
  mEntries := [TDpccHelpInsightRegEntry.Create(mKeys[2], True, False, '')];
  Assert.AreEqual('Help Insight in der Registry (37.0): Borland.EditOptions.HTML = (Wert fehlt)',
    TDpccHelpInsightRule.RegistryLine('Software\Embarcadero\BDS\37.0', mEntries));
  // Ohne IDE (kein Basisschlüssel): Version unbekannt, nichts gelesen.
  Assert.AreEqual('Help Insight in der Registry (?): (nichts gelesen)', TDpccHelpInsightRule.RegistryLine('', nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccHelpInsightRuleTests);

end.
