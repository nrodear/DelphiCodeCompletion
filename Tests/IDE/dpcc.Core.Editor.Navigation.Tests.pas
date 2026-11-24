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
// - Rückmeldung zu einem Sprung ohne Ziel: Meldungstexte je Grund aus dpcc/noTarget (mit Name, Zusatz zum Index),
//   gegen Fluten dieselbe Meldung nicht hintereinander, Zeile fürs dpcc.log ohne Pfad und mit gekennzeichneten
//   Namen.

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
    /// <summary>Dieselbe Datei in anderer Schreibweise (Schrägstriche, "..", Laufwerk, Umlaute in anderer
    /// Groß-/Kleinschreibung) gilt als Klickstelle; ein anderer Ordner nicht. Vorher verglich OnTarget mit SameText,
    /// und der Sprung blieb auf der Deklaration stehen.</summary>
    [Test]
    procedure OnTargetComparesNormalizedPaths;
    /// <summary>FlowResult nennt „gleich der Ausgangsstelle“ auch, wenn der Server den Pfad anders schreibt.</summary>
    [Test]
    procedure FlowResultComparesNormalizedPaths;
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
    /// <summary>Je Grund aus dpcc/noTarget der passende Text, mit Name; ohne Name die allgemeine Fassung.</summary>
    [Test]
    procedure NoTargetTextsNameTheReason;
    /// <summary>indexing = true hängt „Der Index wird noch aufgebaut.“ an; ohne Benachrichtigung „Grund
    /// unbekannt“.</summary>
    [Test]
    procedure NoTargetTextsIndexingAndUnknown;
    /// <summary>Startet noch, Zeitlimit, Fehler beim Öffnen: Sekunden bzw. Dateiname im Text, beide Sprachen.
    /// </summary>
    [Test]
    procedure KindTextsCarryArguments;
    /// <summary>Dieselbe Meldung erscheint nicht zweimal hintereinander, eine andere schon; nach der Frist oder nach
    /// Reset wieder.</summary>
    [Test]
    procedure NoticeRepeatSuppressesSameText;
    /// <summary>Zeile fürs dpcc.log: Ausgang, Dauer, Datei ohne Pfad (gekennzeichnet), Zeile:Spalte, Maus/Cursor.
    /// </summary>
    [Test]
    procedure LogLineHasNoPathAndMarksNames;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  dpcc.Text.LogMarks,
  dpcc.Core.Lsp.LateAnswers,
  dpcc.Core.Localization.Language,
  dpcc.Core.Editor.Navigation;

/// <summary>Grund AReason mit Name AName.</summary>
function NoTarget(AReason: TDpccNoTargetReason; const AName: string; AIndexing: Boolean): TDpccNoTarget;
begin
  Result := Default(TDpccNoTarget);
  Result.Reason := AReason;
  Result.Name := AName;
  Result.Indexing := AIndexing;
end;

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

procedure TDpccNavigationTests.OnTargetComparesNormalizedPaths;
const
  cLine = '    procedure Bar;';
  // Wie der Server den Pfad liefert: Backslashes, ".." aufgelöst, Laufwerk klein.
  cServer = 'c:\Temp\Projekt\UGoto.pas';
begin
  Assert.IsTrue(TDpccGotoDefinition.OnTarget('C:\Temp\Projekt/Unter/../UGoto.pas', 5, 14, cLine, cServer, 5, 14),
    'gemischte Schrägstriche und ..');
  Assert.IsTrue(TDpccGotoDefinition.OnTarget('C:/Temp/Projekt/UGoto.pas', 5, 14, cLine, cServer, 5, 14),
    'nur Schrägstriche');
  Assert.IsTrue(TDpccGotoDefinition.OnTarget('C:\Temp\Projekt\Unter\..\UGoto.pas', 5, 14, cLine, cServer, 5, 14),
    'Punkte im Pfad');
  Assert.IsTrue(TDpccGotoDefinition.OnTarget('C:\Temp\.\Projekt\\UGoto.pas', 5, 14, cLine, cServer, 5, 14),
    '"." und doppelter Trenner');
  Assert.IsTrue(TDpccGotoDefinition.OnTarget('\\?\C:\Temp\Projekt\UGoto.pas', 5, 14, cLine, cServer, 5, 14),
    'Präfix für lange Pfade');
  // "Müller" gegen "MÜLLER": SameText kennt nur A bis Z.
  Assert.IsTrue(TDpccGotoDefinition.OnTarget('C:\M'#$00FC'ller\UGoto.pas', 5, 14, cLine, 'c:\M'#$00DC'LLER\ugoto.pas',
    5, 14), 'Groß/Klein außerhalb von ASCII');
  Assert.IsFalse(TDpccGotoDefinition.OnTarget('C:\Temp\Projekt\Unter\UGoto.pas', 5, 14, cLine, cServer, 5, 14),
    'anderer Ordner');
  Assert.IsFalse(TDpccGotoDefinition.OnTarget('D:\Temp\Projekt\UGoto.pas', 5, 14, cLine, cServer, 5, 14),
    'anderes Laufwerk');
  // OnTargetWhy fällt dasselbe Urteil.
  Assert.IsTrue(TDpccGotoDefinition.OnTargetWhy('C:/Temp/Projekt/UGoto.pas', 5, 14, cLine, cServer, 5,
    14).StartsWith('ja ('), 'OnTargetWhy wie OnTarget');
  Assert.IsTrue(TDpccGotoDefinition.OnTargetWhy('C:\Temp\Projekt\Unter\UGoto.pas', 5, 14, cLine, cServer, 5,
    14).StartsWith('nein ('), 'OnTargetWhy anderer Ordner');
end;

procedure TDpccNavigationTests.FlowResultComparesNormalizedPaths;
var
  mAnswer: TDpccGotoAnswer;
begin
  mAnswer := TDpccGotoDefinition.Answer(TDpccGotoOutcome.Found, 'c:\temp\projekt\ugoto.pas', 5);
  Assert.IsTrue(TDpccGotoLog.FlowResult(TDpccGotoOutcome.Found, mAnswer, True, 'C:/Temp/Projekt/Unter/../UGoto.pas',
    6).EndsWith('gleich der Ausgangsstelle: ja (die IDE bleibt in derselben Zeile)'), 'gleiche Datei');
  Assert.IsTrue(TDpccGotoLog.FlowResult(TDpccGotoOutcome.Found, mAnswer, True, 'C:\Temp\Projekt\Unter\UGoto.pas',
    6).EndsWith('gleich der Ausgangsstelle: nein'), 'anderer Ordner');
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

procedure TDpccNavigationTests.NoTargetTextsNameTheReason;
var
  mText: string;
begin
  mText := TDpccGotoNotice.ForNoTarget(TDpccLanguage.German, NoTarget(TDpccNoTargetReason.NoSource, 'Vcl.Forms',
    False));
  Assert.AreEqual('Kein Sprungziel: Unit Vcl.Forms liegt nur als Package vor (kein Quelltext). Quellordner unter ' +
    'Tools › Optionen › Drittanbieter › dpcc › Zusätzliche Quellordner eintragen.', mText);
  mText := TDpccGotoNotice.ForNoTarget(TDpccLanguage.English, NoTarget(TDpccNoTargetReason.NoSource, 'Vcl.Forms',
    False));
  Assert.Contains(mText, 'Vcl.Forms');
  Assert.Contains(mText, 'Additional source folders');
  Assert.AreEqual('Kein Sprungziel: Unit Werkzeuge nicht gefunden.', TDpccGotoNotice.ForNoTarget(
    TDpccLanguage.German, NoTarget(TDpccNoTargetReason.UnitNotFound, 'Werkzeuge', False)));
  Assert.AreEqual('Kein Sprungziel: „TFoo“ nicht aufgelöst.', TDpccGotoNotice.ForNoTarget(TDpccLanguage.German,
    NoTarget(TDpccNoTargetReason.Unresolved, 'TFoo', False)));
  // Ohne Name: die allgemeine Fassung, kein leeres „Unit  nicht gefunden“.
  Assert.AreEqual('Kein Sprungziel: Unit nicht gefunden.', TDpccGotoNotice.ForNoTarget(TDpccLanguage.German,
    NoTarget(TDpccNoTargetReason.UnitNotFound, '', False)));
  Assert.Contains(TDpccGotoNotice.ForNoTarget(TDpccLanguage.German, NoTarget(TDpccNoTargetReason.InactiveBranch, '',
    False)), '{$IFDEF');
  Assert.Contains(TDpccGotoNotice.ForNoTarget(TDpccLanguage.German, NoTarget(TDpccNoTargetReason.NoIdentifier, '',
    False)), 'kein Bezeichner');
end;

procedure TDpccNavigationTests.NoTargetTextsIndexingAndUnknown;
begin
  Assert.AreEqual('Kein Sprungziel: „TFoo“ nicht aufgelöst. Der Index wird noch aufgebaut.',
    TDpccGotoNotice.ForNoTarget(TDpccLanguage.German, NoTarget(TDpccNoTargetReason.Unresolved, 'TFoo', True)));
  Assert.AreEqual('No jump target: unit X not found. The index is still being built.',
    TDpccGotoNotice.ForNoTarget(TDpccLanguage.English, NoTarget(TDpccNoTargetReason.UnitNotFound, 'X', True)));
  Assert.AreEqual('Kein Sprungziel gefunden (Grund unbekannt).', TDpccGotoNotice.ForNoTarget(TDpccLanguage.German,
    NoTarget(TDpccNoTargetReason.Unknown, '', False)));
  Assert.AreEqual('Kein Sprungziel gefunden.', TDpccGotoNotice.ForNoTarget(TDpccLanguage.German,
    NoTarget(TDpccNoTargetReason.Other, '', False)));
end;

procedure TDpccNavigationTests.KindTextsCarryArguments;
begin
  Assert.AreEqual('dpcc startet noch; der Sprung folgt, sobald dpcc bereit ist (höchstens 10 s nach dem Klick).',
    TDpccGotoNotice.ForKind(TDpccLanguage.German, TDpccGotoNoticeKind.Starting, '', 10, False));
  Assert.AreEqual('Kein Sprung: keine Antwort von dpcc binnen 10 s.', TDpccGotoNotice.ForKind(TDpccLanguage.German,
    TDpccGotoNoticeKind.TimedOut, '', 10, False));
  Assert.AreEqual('No jump: no answer from dpcc within 10 s. The index is still being built.',
    TDpccGotoNotice.ForKind(TDpccLanguage.English, TDpccGotoNoticeKind.TimedOut, '', 10, True));
  Assert.AreEqual('Kein Sprung: Werkzeug.pas ließ sich nicht öffnen.', TDpccGotoNotice.ForKind(TDpccLanguage.German,
    TDpccGotoNoticeKind.OpenFailed, 'Werkzeug.pas', 0, False));
  Assert.Contains(TDpccGotoNotice.ForKind(TDpccLanguage.English, TDpccGotoNoticeKind.NotRunning, '', 0, False),
    'not running');
end;

procedure TDpccNavigationTests.NoticeRepeatSuppressesSameText;
const
  cT0 = 1000000;
var
  mRepeat: TDpccNoticeRepeat;
begin
  mRepeat := Default(TDpccNoticeRepeat);
  Assert.IsTrue(mRepeat.Take('A', cT0), 'erstes Mal');
  Assert.IsFalse(mRepeat.Take('A', cT0 + 1000), 'gleich, gleich danach');
  Assert.IsTrue(mRepeat.Take('B', cT0 + 2000), 'andere Meldung');
  Assert.IsTrue(mRepeat.Take('A', cT0 + 3000), 'wieder A nach B');
  Assert.IsTrue(mRepeat.Take('A', cT0 + 3000 + TDpccNoticeRepeat.cRepeatMs + 1), 'nach der Frist');
  mRepeat.Reset;
  Assert.IsTrue(mRepeat.Take('A', cT0 + 3000 + TDpccNoticeRepeat.cRepeatMs + 2), 'nach einem gelungenen Sprung');
  Assert.IsFalse(mRepeat.Take('', cT0 + 90000), 'leer nie');
end;

procedure TDpccNavigationTests.LogLineHasNoPathAndMarksNames;
var
  mLine: string;
begin
  mLine := TDpccGotoLog.Line(TDpccGotoLog.NoTargetOutcome(NoTarget(TDpccNoTargetReason.NoSource, 'Vcl.Forms', True)),
    87, 'C:\Projekte\Geheim\Werkzeug.pas', 12, 4, True);
  Assert.IsTrue(TLogMarks.HasMarks(mLine), 'Datei und Name gekennzeichnet');
  Assert.AreEqual('Gehe zu Definition: kein Ziel (noSource: Vcl.Forms, Index im Aufbau) nach 87 ms, Werkzeug.pas ' +
    '12:5 (Maus)', TLogMarks.Plain(mLine));
  Assert.IsFalse(mLine.Contains('Geheim'), 'ohne Pfad');
  Assert.AreEqual('Gehe zu Definition: kein Ziel (Grund unbekannt) nach 0 ms, - 0:1 (Cursor)',
    TLogMarks.Plain(TDpccGotoLog.Line(TDpccGotoLog.NoTargetOutcome(NoTarget(TDpccNoTargetReason.Unknown, '', False)),
    0, '', 0, 0, False)));
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccNavigationTests);

end.
