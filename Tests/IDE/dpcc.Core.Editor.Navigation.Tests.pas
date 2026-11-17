unit dpcc.Core.Editor.Navigation.Tests;

// Regeln für Strg+Klick und „Deklaration suchen“ (Auftrag NAV, dpcc.Core.Editor.Navigation):
// - Antwort an die IDE: immer True; Datei und Zeile nur mit Ziel. Vor NAV lieferte GotoDefinition False, wenn der
//   Server keine Sprungziele bot (schlanker Server) oder -32601 meldete; die IDE zeigte dann „Datei "" nicht
//   gefunden“ (gegen den alten Stand: NotOfferedIsSilent).
// - Auf der Deklaration selbst geht der Sprung zur Implementierung (OnTarget), die Stelle ist bei Strg+Klick die
//   unter der Maus (ChoosePosition).
// - Hinweis einmal je Sitzung, wenn dpcc der gewählte Anbieter ist.
// - Parameter-Hint: Überladung mit Strg+Alt+↑/↓; Alt+↑/↓ gehört der IDE (vor NAV schluckte der Hint Alt+↑/↓,
//   gegen den alten Stand: AltArrowsBelongToIde).
// - Tooltip: Strg lässt die Maus durch und schließt ihn, wenn sie über ihm steht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccNavigationTests = class
  public
    [Test]
    procedure FoundAnswersFileAndLine;
    [Test]
    procedure NotFoundIsSilent;
    [Test]
    procedure NotOfferedIsSilent;
    [Test]
    procedure OnlyFailureIsReported;
    [Test]
    procedure OnTargetWithinSameName;
    [Test]
    procedure OnTargetOtherLineFileOrWord;
    [Test]
    procedure CtrlClickTakesMousePosition;
    [Test]
    procedure NoticeOnlyOnce;
    [Test]
    procedure NoticeTextsNameMissingAndCtrlClick;
    [Test]
    procedure CtrlAltArrowsSwitchOverload;
    [Test]
    procedure AltArrowsBelongToIde;
    [Test]
    procedure SingleSignatureTakesNoKey;
    [Test]
    procedure TooltipPassesMouseWithCtrl;
    [Test]
    procedure CtrlClosesTooltipOnlyUnderMouse;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  dpcc.Core.Localization.Language,
  dpcc.Core.Editor.Navigation;

const
  cUp = $26;
  cDown = $28;
  cEscape = $1B;
  cKeyA = $41;

{ TDpccNavigationTests }

procedure TDpccNavigationTests.FoundAnswersFileAndLine;
var
  mAnswer: TDpccGotoAnswer;
begin
  mAnswer := TDpccGotoDefinition.Answer(TDpccGotoOutcome.Found, 'C:\P\Werkzeug.pas', 4);
  Assert.IsTrue(mAnswer.Result);
  Assert.AreEqual('C:\P\Werkzeug.pas', mAnswer.FileName);
  Assert.AreEqual(5, mAnswer.Line, 'Zeile 1-basiert für die IDE');
  Assert.IsFalse(mAnswer.Report);
  // Gefunden ohne Datei: still abbrechen.
  mAnswer := TDpccGotoDefinition.Answer(TDpccGotoOutcome.Found, '', 4);
  Assert.IsTrue(mAnswer.Result);
  Assert.AreEqual('', mAnswer.FileName);
  Assert.AreEqual(0, mAnswer.Line);
end;

procedure TDpccNavigationTests.NotFoundIsSilent;
var
  mOutcome: TDpccGotoOutcome;
  mAnswer: TDpccGotoAnswer;
begin
  // True mit leerem Dateinamen: Die IDE bricht still ab (ToolsAPI), keine Meldung „Datei "" nicht gefunden“.
  for mOutcome := Low(TDpccGotoOutcome) to High(TDpccGotoOutcome) do
  begin
    if mOutcome = TDpccGotoOutcome.Found then
    begin
      Continue;
    end;
    mAnswer := TDpccGotoDefinition.Answer(mOutcome, 'C:\P\Egal.pas', 3);
    Assert.IsTrue(mAnswer.Result, 'immer True');
    Assert.AreEqual('', mAnswer.FileName, 'ohne Datei');
    Assert.AreEqual(0, mAnswer.Line, 'ohne Zeile');
  end;
end;

procedure TDpccNavigationTests.NotOfferedIsSilent;
var
  mAnswer: TDpccGotoAnswer;
begin
  // Vor NAV: False („die IDE übernimmt“) – die IDE meldete dann einen Fehlschlag mit leerem Dateinamen.
  mAnswer := TDpccGotoDefinition.Answer(TDpccGotoOutcome.NotOffered, '', 0);
  Assert.IsTrue(mAnswer.Result);
  Assert.IsFalse(mAnswer.Report);
  mAnswer := TDpccGotoDefinition.Answer(TDpccGotoOutcome.TimedOut, '', 0);
  Assert.IsTrue(mAnswer.Result);
  Assert.IsFalse(mAnswer.Report, 'Zeitlimit ist erwartbar');
end;

procedure TDpccNavigationTests.OnlyFailureIsReported;
var
  mOutcome: TDpccGotoOutcome;
begin
  for mOutcome := Low(TDpccGotoOutcome) to High(TDpccGotoOutcome) do
  begin
    Assert.IsTrue((mOutcome = TDpccGotoOutcome.Failed) = TDpccGotoDefinition.Answer(mOutcome, '', 0).Report,
      'Meldung nur bei unerwartetem Fehler');
  end;
end;

procedure TDpccNavigationTests.OnTargetWithinSameName;
const
  cLine = '    procedure Bar;';
begin
  // Ziel beginnt bei Zeichen 14 ("Bar"); Stellen 14 bis 17 (hinter dem Namen) gehören dazu.
  Assert.IsTrue(TDpccGotoDefinition.OnTarget('C:\P\Haupt.pas', 5, 14, cLine, 'c:\p\haupt.pas', 5, 14), 'Anfang');
  Assert.IsTrue(TDpccGotoDefinition.OnTarget('C:\P\Haupt.pas', 5, 16, cLine, 'C:\P\Haupt.pas', 5, 14), 'Mitte');
  Assert.IsTrue(TDpccGotoDefinition.OnTarget('C:\P\Haupt.pas', 5, 17, cLine, 'C:\P\Haupt.pas', 5, 14), 'Ende');
end;

procedure TDpccNavigationTests.OnTargetOtherLineFileOrWord;
const
  cLine = '  Foo := Bar(Foo);';
begin
  Assert.IsFalse(TDpccGotoDefinition.OnTarget('C:\P\A.pas', 3, 2, cLine, 'C:\P\B.pas', 3, 2), 'andere Datei');
  Assert.IsFalse(TDpccGotoDefinition.OnTarget('C:\P\A.pas', 3, 2, cLine, 'C:\P\A.pas', 4, 2), 'andere Zeile');
  Assert.IsFalse(TDpccGotoDefinition.OnTarget('C:\P\A.pas', 3, 9, cLine, 'C:\P\A.pas', 3, 2), 'anderes Wort');
  Assert.IsFalse(TDpccGotoDefinition.OnTarget('C:\P\A.pas', 3, 1, cLine, 'C:\P\A.pas', 3, 2), 'vor dem Ziel');
end;

procedure TDpccNavigationTests.CtrlClickTakesMousePosition;
var
  mMouse, mCaret: TPoint;
begin
  mMouse := TPoint.Create(7, 12);
  mCaret := TPoint.Create(3, 40);
  Assert.AreEqual(7, TDpccGotoDefinition.ChoosePosition(True, True, mMouse, mCaret).X, 'Strg+Klick: Maus');
  Assert.AreEqual(12, TDpccGotoDefinition.ChoosePosition(True, True, mMouse, mCaret).Y);
  Assert.AreEqual(40, TDpccGotoDefinition.ChoosePosition(False, True, mMouse, mCaret).Y, 'ohne Strg: Cursor');
  Assert.AreEqual(40, TDpccGotoDefinition.ChoosePosition(True, False, mMouse, mCaret).Y, 'Maus neben dem Wort');
end;

procedure TDpccNavigationTests.NoticeOnlyOnce;
begin
  TDpccProviderNotice.Reset;
  try
    Assert.IsTrue(TDpccProviderNotice.Pending);
    Assert.IsTrue(TDpccProviderNotice.TakeFirst, 'erstes Mal');
    Assert.IsFalse(TDpccProviderNotice.Pending);
    Assert.IsFalse(TDpccProviderNotice.TakeFirst, 'zweites Mal');
    Assert.IsFalse(TDpccProviderNotice.TakeFirst, 'drittes Mal');
  finally
    TDpccProviderNotice.Reset;
  end;
end;

procedure TDpccNavigationTests.NoticeTextsNameMissingAndCtrlClick;
var
  mGerman, mEnglish: string;
begin
  mGerman := TDpccProviderNotice.Text(TDpccLanguage.German);
  mEnglish := TDpccProviderNotice.Text(TDpccLanguage.English);
  Assert.Contains(mGerman, 'Error Insight');
  Assert.Contains(mGerman, 'Strg+Klick');
  Assert.Contains(mGerman, 'DelphiLSP');
  Assert.Contains(mEnglish, 'Error Insight');
  Assert.Contains(mEnglish, 'Ctrl+click');
  Assert.Contains(mEnglish, 'DelphiLSP');
end;

procedure TDpccNavigationTests.CtrlAltArrowsSwitchOverload;
begin
  Assert.AreEqual(-1, TDpccOverloadKeys.Step(cUp, [ssCtrl, ssAlt], 3), 'Strg+Alt+↑: vorige');
  Assert.AreEqual(1, TDpccOverloadKeys.Step(cDown, [ssCtrl, ssAlt], 3), 'Strg+Alt+↓: nächste');
  Assert.AreEqual(0, TDpccOverloadKeys.Step(cKeyA, [ssCtrl, ssAlt], 3), 'andere Taste');
  Assert.AreEqual('Strg+Alt+↑/↓', TDpccOverloadKeys.Caption(TDpccLanguage.German));
  Assert.AreEqual('Ctrl+Alt+↑/↓', TDpccOverloadKeys.Caption(TDpccLanguage.English));
end;

procedure TDpccNavigationTests.AltArrowsBelongToIde;
begin
  // Alt+↑ ist „Deklaration suchen“ der IDE; ohne Modifizierer bewegen die Pfeile den Caret.
  Assert.AreEqual(0, TDpccOverloadKeys.Step(cUp, [ssAlt], 3), 'Alt+↑');
  Assert.AreEqual(0, TDpccOverloadKeys.Step(cDown, [ssAlt], 3), 'Alt+↓');
  Assert.AreEqual(0, TDpccOverloadKeys.Step(cUp, [], 3), '↑');
  Assert.AreEqual(0, TDpccOverloadKeys.Step(cDown, [ssCtrl], 3), 'Strg+↓');
  Assert.AreEqual(0, TDpccOverloadKeys.Step(cUp, [ssCtrl, ssAlt, ssShift], 3), 'Strg+Alt+Umschalt+↑');
end;

procedure TDpccNavigationTests.SingleSignatureTakesNoKey;
begin
  Assert.AreEqual(0, TDpccOverloadKeys.Step(cUp, [ssCtrl, ssAlt], 1));
  Assert.AreEqual(0, TDpccOverloadKeys.Step(cDown, [ssCtrl, ssAlt], 0));
end;

procedure TDpccNavigationTests.TooltipPassesMouseWithCtrl;
begin
  Assert.IsTrue(TDpccTooltipMouse.PassThrough(True));
  Assert.IsFalse(TDpccTooltipMouse.PassThrough(False));
end;

procedure TDpccNavigationTests.CtrlClosesTooltipOnlyUnderMouse;
begin
  Assert.IsTrue(TDpccTooltipMouse.KeyCloses(TDpccTooltipMouse.cKeyControl, True), 'Strg über dem Tooltip');
  Assert.IsFalse(TDpccTooltipMouse.KeyCloses(TDpccTooltipMouse.cKeyControl, False), 'Strg über dem Wort');
  Assert.IsFalse(TDpccTooltipMouse.KeyCloses(TDpccTooltipMouse.cKeyShift, True), 'Umschalt');
  Assert.IsFalse(TDpccTooltipMouse.KeyCloses(TDpccTooltipMouse.cKeyMenu, True), 'Alt');
  Assert.IsTrue(TDpccTooltipMouse.KeyCloses(cEscape, False), 'Esc');
  Assert.IsTrue(TDpccTooltipMouse.KeyCloses(cKeyA, False), 'Buchstabe');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccNavigationTests);

end.
