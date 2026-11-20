unit dpcc.Core.Lsp.LateAnswers.Tests;

// Tests für kurz erwartete Antworten (dpcc.Core.Lsp.LateAnswers): Übergabe zwischen Hintergrund-Thread und
// Hauptthread (rechtzeitig, nachgereicht, mit echtem Thread), die Regeln für ein nachgereichtes Sprungziel (gleiches
// Wort statt gleicher Spalte, Alter bis zur Ankunft der Antwort, 10 s), die Ablage der Gründe aus dpcc/noTarget
// (Zuordnung zur Stelle, Verfall, Kette declaration → definition) und der Zwischenspeicher der Symbolhinweise (Wort,
// Textstand, Verfall, Größe).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccLateAnswersTests = class
  public
    /// <summary>Antwort vor dem Warten: Await sofort True, Complete meldet „nicht nachreichen“.</summary>
    [Test]
    procedure SlotAnswerInTime;
    /// <summary>Aufgegeben vor der Antwort: Await False, Complete meldet „nachreichen“; danach ist sie da.</summary>
    [Test]
    procedure SlotAnswerLate;
    /// <summary>Ein Thread antwortet innerhalb der Wartezeit.</summary>
    [Test]
    procedure SlotWaitsForThread;
    /// <summary>Gleiche Datei, Cursor unverändert, gleiche Generation, rechtzeitig: springen.</summary>
    [Test]
    procedure LateGotoJumps;
    /// <summary>Cursor an der Stelle der Anfrage (Strg+Klick) zählt wie unverändert; Groß-/Kleinschreibung der Datei
    /// zählt nicht.</summary>
    [Test]
    procedure LateGotoAcceptsCaretAtRequest;
    /// <summary>Kein Ziel, neuerer Sprungwunsch, zu alt, andere Datei, Cursor bewegt: verwerfen.</summary>
    [Test]
    procedure LateGotoRejects;
    /// <summary>Wartezeit 250 ms, Obergrenze und Zeitlimit 10 s.</summary>
    [Test]
    procedure LateGotoLimits;
    /// <summary>Cursor irgendwo im Bezeichner der Klickstelle oder der Ausgangsstelle (auch direkt dahinter):
    /// springen; im Nachbarwort oder in anderer Zeile: verwerfen.</summary>
    [Test]
    procedure LateGotoAcceptsSameWord;
    /// <summary>Das Alter zählt bis zur Ankunft im Hintergrund-Thread, nicht bis zur Zustellung im Hauptthread.
    /// </summary>
    [Test]
    procedure LateGotoAgeUntilArrival;
    /// <summary>Bezeichner an einer Stelle: darin, direkt dahinter, außerhalb.</summary>
    [Test]
    procedure WordRangeFindsIdentifier;
    /// <summary>Parameter von dpcc/noTarget: alle Felder, unbekannter oder fehlender Grund, fehlende Stelle.</summary>
    [Test]
    procedure NoTargetParsesParams;
    /// <summary>Abholen nur zur selben Stelle (Datei ohne Groß-/Kleinschreibung), einmalig; verfällt; höchstens
    /// AMaxEntries.</summary>
    [Test]
    procedure NoTargetStoreMatchesAndExpires;
    /// <summary>Kette declaration → definition: der aussagekräftigere Grund, Methode als Filter, Index-Hinweis aus
    /// beiden.</summary>
    [Test]
    procedure NoTargetChainTakesBetterReason;
    /// <summary>Jede Stelle im selben Wort ergibt denselben Schlüssel; außerhalb eines Worts die Stelle selbst.
    /// </summary>
    [Test]
    procedure HintKeyUsesWordStart;
    /// <summary>Gemerkt und wiedergefunden, auch ein leerer Hinweis; verfällt nach der Lebensdauer.</summary>
    [Test]
    procedure HintCacheStoresAndExpires;
    /// <summary>Anderer Textstand derselben Datei macht deren Einträge ungültig, andere Dateien bleiben.</summary>
    [Test]
    procedure HintCacheDropsChangedDocument;
    /// <summary>Höchstens AMaxEntries Einträge; der älteste fällt weg.</summary>
    [Test]
    procedure HintCacheEvictsOldest;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  dpcc.Core.Lsp.LateAnswers;

const
  cT0 = 1000000;
  cFile = 'C:\P\Werkzeug.pas';

function Origin: TDpccGotoOrigin;
begin
  Result := Default(TDpccGotoOrigin);
  Result.Generation := 7;
  Result.FileName := cFile;
  Result.CaretLine := 12;
  Result.CaretCharacter := 4;
  Result.AtLine := 14;
  Result.AtCharacter := 9;
  Result.StartedMs := cT0;
end;

function NowAt(ALine, ACharacter: Integer; AMs: UInt64): TDpccGotoNow;
begin
  Result := Default(TDpccGotoNow);
  Result.Generation := 7;
  Result.FileName := cFile;
  Result.CaretLine := ALine;
  Result.CaretCharacter := ACharacter;
  Result.NowMs := AMs;
end;

function TextAnswer(const AText: string): TDpccAnswer;
begin
  Result := Default(TDpccAnswer);
  Result.Found := True;
  Result.Text := AText;
end;

{ TDpccLateAnswersTests }

procedure TDpccLateAnswersTests.SlotAnswerInTime;
var
  mSlot: IDpccAnswerSlot;
begin
  mSlot := TDpccAnswerSlot.Create(cT0);
  Assert.IsFalse(mSlot.Done, 'noch offen');
  Assert.IsTrue(mSlot.Complete(TextAnswer('Hinweis')), 'Hauptthread holt selbst ab');
  Assert.IsTrue(mSlot.Await(0), 'schon da');
  Assert.AreEqual('Hinweis', mSlot.Answer.Text);
  Assert.IsTrue(mSlot.StartedMs = cT0, 'Beginn');
end;

procedure TDpccLateAnswersTests.SlotAnswerLate;
var
  mSlot: IDpccAnswerSlot;
begin
  mSlot := TDpccAnswerSlot.Create(cT0);
  Assert.IsFalse(mSlot.Await(1), 'kommt später');
  Assert.IsFalse(mSlot.Complete(TextAnswer('spät')), 'nachreichen');
  Assert.IsTrue(mSlot.Done, 'abgegeben');
  Assert.IsTrue(mSlot.Await(0), 'jetzt da');
  Assert.AreEqual('spät', mSlot.Answer.Text);
end;

procedure TDpccLateAnswersTests.SlotWaitsForThread;
var
  mSlot: IDpccAnswerSlot;
  mThread: TThread;
  mInTime: Boolean;
begin
  mSlot := TDpccAnswerSlot.Create(cT0);
  mInTime := False;
  mThread := TThread.CreateAnonymousThread(
    procedure
    begin
      TThread.Sleep(20);
      mInTime := mSlot.Complete(TextAnswer('aus dem Thread'));
    end);
  mThread.FreeOnTerminate := False;
  try
    mThread.Start;
    Assert.IsTrue(mSlot.Await(5000), 'innerhalb der Wartezeit');
    mThread.WaitFor;
    Assert.IsTrue(mInTime, 'nicht nachgereicht');
    Assert.AreEqual('aus dem Thread', mSlot.Answer.Text);
  finally
    mThread.Free;
  end;
end;

/// <summary>Urteil für Origin und ANow wie erwartet.</summary>
procedure CheckVerdict(AExpected: TDpccGotoVerdict; const ANow: TDpccGotoNow; AFound: Boolean; AMaxAgeMs: Cardinal;
  const AMessage: string);
begin
  Assert.AreEqual(Ord(AExpected), Ord(TDpccLateGoto.Verdict(Origin, ANow, AFound, AMaxAgeMs)),
    AMessage + ' (' + TDpccLateGoto.VerdictText(TDpccLateGoto.Verdict(Origin, ANow, AFound, AMaxAgeMs)) + ')');
end;

procedure TDpccLateAnswersTests.LateGotoJumps;
begin
  CheckVerdict(TDpccGotoVerdict.Jump, NowAt(12, 4, cT0 + 900), True, TDpccLateAnswers.cMaxAgeMs, 'rechtzeitig');
  // Genau an der Obergrenze gilt es noch.
  CheckVerdict(TDpccGotoVerdict.Jump, NowAt(12, 4, cT0 + 3000), True, 3000, 'an der Grenze');
end;

procedure TDpccLateAnswersTests.LateGotoAcceptsCaretAtRequest;
var
  mNow: TDpccGotoNow;
begin
  CheckVerdict(TDpccGotoVerdict.Jump, NowAt(14, 9, cT0 + 500), True, 3000, 'Cursor an der Klickstelle');
  mNow := NowAt(12, 4, cT0 + 500);
  mNow.FileName := 'c:\p\WERKZEUG.pas';
  CheckVerdict(TDpccGotoVerdict.Jump, mNow, True, 3000, 'Dateiname');
end;

procedure TDpccLateAnswersTests.LateGotoRejects;
var
  mNow: TDpccGotoNow;
begin
  CheckVerdict(TDpccGotoVerdict.NoTarget, NowAt(12, 4, cT0 + 100), False, 3000, 'kein Ziel');
  mNow := NowAt(12, 4, cT0 + 100);
  mNow.Generation := 8;
  CheckVerdict(TDpccGotoVerdict.Superseded, mNow, True, 3000, 'neuerer Sprungwunsch');
  CheckVerdict(TDpccGotoVerdict.TooOld, NowAt(12, 4, cT0 + 3001), True, 3000, 'zu alt');
  mNow := NowAt(12, 4, cT0 + 100);
  mNow.FileName := 'C:\P\Andere.pas';
  CheckVerdict(TDpccGotoVerdict.OtherFile, mNow, True, 3000, 'andere Datei');
  mNow.FileName := '';
  CheckVerdict(TDpccGotoVerdict.OtherFile, mNow, True, 3000, 'keine Ansicht');
  CheckVerdict(TDpccGotoVerdict.CursorMoved, NowAt(12, 5, cT0 + 100), True, 3000, 'Zeichen');
  CheckVerdict(TDpccGotoVerdict.CursorMoved, NowAt(13, 4, cT0 + 100), True, 3000, 'Zeile');
  Assert.IsTrue(TDpccLateGoto.VerdictText(TDpccGotoVerdict.CursorMoved) <> '', 'Text fürs Protokoll');
end;

procedure TDpccLateAnswersTests.LateGotoLimits;
begin
  Assert.AreEqual(250, TDpccLateAnswers.cWaitMs, 'Hauptthread wartet höchstens 250 ms');
  Assert.AreEqual(10000, TDpccLateAnswers.cMaxAgeMs, 'Zeitlimit und Obergrenze 10 s');
end;

const
  /// <summary>Zeile der Klickstelle: "Werkzeug" von Zeichen 12 bis vor 20, "Name" von 21 bis vor 25.</summary>
  cClickLine = '  Result := Werkzeug.Name;';
  /// <summary>Zeile des Cursors beim Fragen: "Foo" von Zeichen 2 bis vor 5.</summary>
  cCaretLine = '  Foo := 1;';

/// <summary>Sprungwunsch mit Klick in "Werkzeug" (Zeile 14, Zeichen 15) und Cursor in "Foo" (Zeile 12, Zeichen 3),
/// samt Bezeichnern.</summary>
function WordOrigin: TDpccGotoOrigin;
begin
  Result := Origin;
  Result.AtLine := 14;
  Result.AtCharacter := 15;
  Result.CaretLine := 12;
  Result.CaretCharacter := 3;
  TDpccLateGoto.WordRange(cClickLine, Result.AtCharacter, Result.AtWordStart, Result.AtWordEnd);
  TDpccLateGoto.WordRange(cCaretLine, Result.CaretCharacter, Result.CaretWordStart, Result.CaretWordEnd);
end;

/// <summary>Urteil für WordOrigin bei Cursor ALine/ACharacter, rechtzeitig.</summary>
function WordVerdict(ALine, ACharacter: Integer): TDpccGotoVerdict;
begin
  Result := TDpccLateGoto.Verdict(WordOrigin, NowAt(ALine, ACharacter, cT0 + 100), True, TDpccLateAnswers.cMaxAgeMs);
end;

procedure TDpccLateAnswersTests.LateGotoAcceptsSameWord;
begin
  Assert.AreEqual(Ord(TDpccGotoVerdict.Jump), Ord(WordVerdict(14, 12)), 'Anfang von Werkzeug');
  Assert.AreEqual(Ord(TDpccGotoVerdict.Jump), Ord(WordVerdict(14, 17)), 'andere Spalte in Werkzeug');
  Assert.AreEqual(Ord(TDpccGotoVerdict.Jump), Ord(WordVerdict(14, 20)), 'direkt hinter Werkzeug');
  Assert.AreEqual(Ord(TDpccGotoVerdict.Jump), Ord(WordVerdict(12, 2)), 'im Wort des Cursors beim Fragen');
  Assert.AreEqual(Ord(TDpccGotoVerdict.Jump), Ord(WordVerdict(12, 5)), 'direkt hinter Foo');
  Assert.AreEqual(Ord(TDpccGotoVerdict.CursorMoved), Ord(WordVerdict(14, 22)), 'im Nachbarwort Name');
  Assert.AreEqual(Ord(TDpccGotoVerdict.CursorMoved), Ord(WordVerdict(14, 11)), 'vor Werkzeug');
  Assert.AreEqual(Ord(TDpccGotoVerdict.CursorMoved), Ord(WordVerdict(12, 6)), 'hinter Foo');
  Assert.AreEqual(Ord(TDpccGotoVerdict.CursorMoved), Ord(WordVerdict(13, 15)), 'andere Zeile');
end;

procedure TDpccLateAnswersTests.LateGotoAgeUntilArrival;
var
  mNow: TDpccGotoNow;
begin
  // Der Eintrag im Hauptthread kam erst nach 60 s dran, die Antwort war aber nach 900 ms da.
  mNow := NowAt(12, 4, cT0 + 60000);
  mNow.ArrivedMs := cT0 + 900;
  Assert.IsTrue(TDpccLateGoto.AgeMs(Origin, mNow) = 900, 'Alter bis zur Ankunft');
  Assert.AreEqual(Ord(TDpccGotoVerdict.Jump), Ord(TDpccLateGoto.Verdict(Origin, mNow, True,
    TDpccLateAnswers.cMaxAgeMs)), 'rechtzeitig angekommen');
  mNow.ArrivedMs := cT0 + 10000;
  Assert.AreEqual(Ord(TDpccGotoVerdict.Jump), Ord(TDpccLateGoto.Verdict(Origin, mNow, True,
    TDpccLateAnswers.cMaxAgeMs)), 'an der Grenze');
  mNow.ArrivedMs := cT0 + 10001;
  Assert.AreEqual(Ord(TDpccGotoVerdict.TooOld), Ord(TDpccLateGoto.Verdict(Origin, mNow, True,
    TDpccLateAnswers.cMaxAgeMs)), 'zu spät angekommen');
  // Ohne Ankunftszeit zählt die Zustellung; vor dem Klick (Uhr) nie negativ.
  mNow.ArrivedMs := 0;
  Assert.IsTrue(TDpccLateGoto.AgeMs(Origin, mNow) = 60000, 'ohne Ankunft');
  mNow.ArrivedMs := cT0 - 5;
  Assert.IsTrue(TDpccLateGoto.AgeMs(Origin, mNow) = 0, 'nie negativ');
end;

procedure TDpccLateAnswersTests.WordRangeFindsIdentifier;
var
  mStart, mEnd: Integer;
begin
  Assert.IsTrue(TDpccLateGoto.WordRange(cClickLine, 15, mStart, mEnd), 'in Werkzeug');
  Assert.AreEqual(12, mStart);
  Assert.AreEqual(20, mEnd);
  Assert.IsTrue(TDpccLateGoto.WordRange(cClickLine, 20, mStart, mEnd), 'direkt dahinter');
  Assert.AreEqual(12, mStart);
  Assert.AreEqual(20, mEnd);
  Assert.IsTrue(TDpccLateGoto.WordRange(cClickLine, 25, mStart, mEnd), 'hinter Name, vor dem Semikolon');
  Assert.AreEqual(21, mStart);
  Assert.AreEqual(25, mEnd);
  Assert.IsFalse(TDpccLateGoto.WordRange(cClickLine, 1, mStart, mEnd), 'Leerzeichen');
  Assert.AreEqual(1, mStart);
  Assert.AreEqual(1, mEnd);
  Assert.IsFalse(TDpccLateGoto.WordRange(cClickLine, 26, mStart, mEnd), 'hinter dem Semikolon');
  Assert.IsFalse(TDpccLateGoto.WordRange(cClickLine, -1, mStart, mEnd), 'vor der Zeile');
  Assert.IsFalse(TDpccLateGoto.WordRange('', 0, mStart, mEnd), 'leere Zeile');
end;

procedure TDpccLateAnswersTests.NoTargetParsesParams;
var
  mParams: TJSONValue;
  mNote: TDpccNoTargetNote;
begin
  mParams := TJSONObject.ParseJSONValue('{"method":"textDocument/declaration","uri":"file:///C:/P/Werkzeug.pas",' +
    '"line":3,"character":7,"reason":"noSource","name":"Vcl.Forms","indexing":true}');
  try
    Assert.IsTrue(TDpccNoTargetNote.Parse(mParams, mNote));
    Assert.AreEqual('file:///C:/P/Werkzeug.pas', mNote.FileName, 'URI; die Sitzung macht den Pfad daraus');
    Assert.AreEqual(3, mNote.Line);
    Assert.AreEqual(7, mNote.Character);
    Assert.AreEqual(Ord(TDpccNoTargetReason.NoSource), Ord(mNote.Target.Reason));
    Assert.AreEqual('Vcl.Forms', mNote.Target.Name);
    Assert.IsTrue(mNote.Target.Indexing);
    Assert.AreEqual('textDocument/declaration', mNote.Target.Method);
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"uri":"file:///C:/P/A.pas","line":0,"character":0,"reason":"neu"}');
  try
    Assert.IsTrue(TDpccNoTargetNote.Parse(mParams, mNote));
    Assert.AreEqual(Ord(TDpccNoTargetReason.Other), Ord(mNote.Target.Reason), 'unbekannter Grund');
    Assert.IsFalse(mNote.Target.Indexing, 'ohne indexing');
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"uri":"file:///C:/P/A.pas","line":0,"character":0}');
  try
    Assert.IsTrue(TDpccNoTargetNote.Parse(mParams, mNote));
    Assert.AreEqual(Ord(TDpccNoTargetReason.Other), Ord(mNote.Target.Reason), 'Benachrichtigung ohne Grund');
  finally
    mParams.Free;
  end;
  mParams := TJSONObject.ParseJSONValue('{"uri":"file:///C:/P/A.pas","character":0,"reason":"noDocument"}');
  try
    Assert.IsFalse(TDpccNoTargetNote.Parse(mParams, mNote), 'ohne Zeile');
  finally
    mParams.Free;
  end;
  Assert.IsFalse(TDpccNoTargetNote.Parse(nil, mNote), 'ohne Parameter');
  Assert.AreEqual(Ord(TDpccNoTargetReason.Unknown), Ord(TDpccNoTarget.ReasonOf('')));
  Assert.AreEqual(Ord(TDpccNoTargetReason.Unresolved), Ord(TDpccNoTarget.ReasonOf('UNRESOLVED')));
  Assert.AreEqual(Ord(TDpccNoTargetReason.InactiveBranch), Ord(TDpccNoTarget.ReasonOf('inactiveBranch')));
  Assert.AreEqual('unitNotFound', TDpccNoTarget.CodeOf(TDpccNoTargetReason.UnitNotFound));
end;

/// <summary>Abgelegter Grund an der Stelle.</summary>
function Note(const AFileName: string; ALine, ACharacter: Integer; const AMethod: string;
  AReason: TDpccNoTargetReason; const AName: string; AIndexing: Boolean): TDpccNoTargetNote;
begin
  Result := Default(TDpccNoTargetNote);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.Target.Method := AMethod;
  Result.Target.Reason := AReason;
  Result.Target.Name := AName;
  Result.Target.Indexing := AIndexing;
end;

procedure TDpccLateAnswersTests.NoTargetStoreMatchesAndExpires;
var
  mStore: IDpccNoTargets;
  mTarget: TDpccNoTarget;
  mLine: Integer;
begin
  mStore := TDpccNoTargets.Create(3, 5000);
  mStore.Add(Note(cFile, 3, 7, '', TDpccNoTargetReason.Unresolved, 'TFoo', False), cT0);
  Assert.IsFalse(mStore.Take('', cFile, 3, 8, cT0 + 10, mTarget), 'anderes Zeichen');
  Assert.IsFalse(mStore.Take('', cFile, 4, 7, cT0 + 10, mTarget), 'andere Zeile');
  Assert.IsFalse(mStore.Take('', 'C:\P\Andere.pas', 3, 7, cT0 + 10, mTarget), 'andere Datei');
  Assert.AreEqual(Ord(TDpccNoTargetReason.Unknown), Ord(mTarget.Reason), 'ohne Treffer: unbekannt');
  Assert.IsTrue(mStore.Take('textDocument/declaration', 'c:\p\WERKZEUG.pas', 3, 7, cT0 + 10, mTarget),
    'Datei ohne Groß-/Kleinschreibung, Eintrag ohne Methode passt zu jeder');
  Assert.AreEqual('TFoo', mTarget.Name);
  Assert.IsFalse(mStore.Take('', cFile, 3, 7, cT0 + 20, mTarget), 'nur einmal');
  mStore.Add(Note(cFile, 3, 7, '', TDpccNoTargetReason.Unresolved, 'TFoo', False), cT0);
  Assert.IsTrue(mStore.Take('', cFile, 3, 7, cT0 + 5000, mTarget), 'an der Grenze');
  mStore.Add(Note(cFile, 3, 7, '', TDpccNoTargetReason.Unresolved, 'TFoo', False), cT0);
  Assert.IsFalse(mStore.Take('', cFile, 3, 7, cT0 + 5001, mTarget), 'verfallen');
  Assert.AreEqual(0, mStore.Count, 'verfallene entfernt');
  for mLine := 0 to 3 do
  begin
    mStore.Add(Note(cFile, mLine, 0, '', TDpccNoTargetReason.NoIdentifier, '', False), cT0 + UInt64(mLine));
  end;
  Assert.AreEqual(3, mStore.Count, 'höchstens drei');
  Assert.IsFalse(mStore.Take('', cFile, 0, 0, cT0 + 10, mTarget), 'ältester weg');
  Assert.IsTrue(mStore.Take('', cFile, 3, 0, cT0 + 10, mTarget), 'neuester da');
end;

procedure TDpccLateAnswersTests.NoTargetChainTakesBetterReason;
const
  cDeclaration = 'textDocument/declaration';
  cDefinition = 'textDocument/definition';
var
  mStore: IDpccNoTargets;
  mTarget, mA, mB: TDpccNoTarget;
begin
  mStore := TDpccNoTargets.Create;
  mStore.Add(Note(cFile, 3, 7, cDeclaration, TDpccNoTargetReason.Unresolved, 'TFoo', False), cT0);
  mStore.Add(Note(cFile, 3, 7, cDefinition, TDpccNoTargetReason.NoSource, 'Vcl.Forms', True), cT0 + 1);
  Assert.IsTrue(mStore.Take('', cFile, 3, 7, cT0 + 10, mTarget), 'beide');
  Assert.AreEqual(Ord(TDpccNoTargetReason.NoSource), Ord(mTarget.Reason), 'aussagekräftiger');
  Assert.AreEqual('Vcl.Forms', mTarget.Name);
  Assert.IsTrue(mTarget.Indexing);
  Assert.AreEqual(0, mStore.Count, 'beide abgeholt');
  // Mit Methode nur der Grund dieser Anfrage; der andere bleibt liegen.
  mStore.Add(Note(cFile, 3, 7, cDeclaration, TDpccNoTargetReason.Unresolved, 'TFoo', False), cT0);
  mStore.Add(Note(cFile, 3, 7, cDefinition, TDpccNoTargetReason.NoSource, 'Vcl.Forms', True), cT0 + 1);
  Assert.IsTrue(mStore.Take(cDeclaration, cFile, 3, 7, cT0 + 10, mTarget));
  Assert.AreEqual(Ord(TDpccNoTargetReason.Unresolved), Ord(mTarget.Reason));
  Assert.AreEqual(cDeclaration, mTarget.Method);
  Assert.AreEqual(1, mStore.Count);
  // Rangfolge direkt.
  mA := Default(TDpccNoTarget);
  mB := Default(TDpccNoTarget);
  mB.Reason := TDpccNoTargetReason.NoIdentifier;
  Assert.AreEqual(Ord(TDpccNoTargetReason.NoIdentifier), Ord(TDpccNoTarget.Better(mA, mB).Reason),
    'vor unbekannt');
  mA.Reason := TDpccNoTargetReason.UnitNotFound;
  mB.Reason := TDpccNoTargetReason.Unresolved;
  Assert.AreEqual(Ord(TDpccNoTargetReason.UnitNotFound), Ord(TDpccNoTarget.Better(mA, mB).Reason),
    'Unit nicht gefunden vor nicht aufgelöst');
  mA.Reason := TDpccNoTargetReason.Other;
  mA.Name := 'erster';
  mB.Reason := TDpccNoTargetReason.Other;
  mB.Name := 'zweiter';
  Assert.AreEqual('erster', TDpccNoTarget.Better(mA, mB).Name, 'Gleichstand: der erste');
end;

procedure TDpccLateAnswersTests.HintKeyUsesWordStart;
const
  cLine = '  Result := Werkzeug.Name;';
var
  mHash: Integer;
  mFirst, mSecond, mOther: TDpccHintKey;
begin
  mHash := TDpccHintKey.HashOf('Text');
  // "Werkzeug" beginnt bei Zeichen 12 (0-basiert).
  mFirst := TDpccHintKey.Make(cFile, cLine, 3, 12, mHash);
  mSecond := TDpccHintKey.Make(cFile, cLine, 3, 17, mHash);
  Assert.AreEqual(12, mFirst.WordStart);
  Assert.IsTrue(mFirst.SameAs(mSecond), 'dasselbe Wort');
  mOther := TDpccHintKey.Make(cFile, cLine, 3, 21, mHash);
  Assert.AreEqual(21, mOther.WordStart, 'Name');
  Assert.IsFalse(mFirst.SameAs(mOther), 'anderes Wort');
  // Außerhalb eines Worts (Leerzeichen): die Stelle selbst.
  Assert.AreEqual(1, TDpccHintKey.Make(cFile, cLine, 3, 1, mHash).WordStart);
  Assert.IsFalse(mFirst.SameAs(TDpccHintKey.Make(cFile, cLine, 3, 12, TDpccHintKey.HashOf('Text2'))),
    'anderer Textstand');
  Assert.IsFalse(mFirst.SameAs(TDpccHintKey.Make(cFile, cLine, 4, 12, mHash)), 'andere Zeile');
  Assert.AreEqual(TDpccHintKey.HashOf('gleich'), TDpccHintKey.HashOf('gleich'));
end;

procedure TDpccLateAnswersTests.HintCacheStoresAndExpires;
var
  mCache: IDpccHintCache;
  mKey, mEmpty: TDpccHintKey;
  mText: string;
begin
  mCache := TDpccHintCache.Create(4, 5000);
  mKey := TDpccHintKey.Make(cFile, 'Werkzeug', 0, 3, 1);
  Assert.IsFalse(mCache.Lookup(mKey, cT0, mText), 'leer');
  mCache.Store(mKey, 'function Werkzeug: Integer', cT0);
  Assert.IsTrue(mCache.Lookup(TDpccHintKey.Make(cFile, 'Werkzeug', 0, 0, 1), cT0 + 100, mText), 'selbes Wort');
  Assert.AreEqual('function Werkzeug: Integer', mText);
  mEmpty := TDpccHintKey.Make(cFile, 'Werkzeug', 1, 0, 1);
  mCache.Store(mEmpty, '', cT0);
  Assert.IsTrue(mCache.Lookup(mEmpty, cT0 + 100, mText), 'leerer Hinweis zählt');
  Assert.AreEqual('', mText);
  Assert.IsTrue(mCache.Lookup(mKey, cT0 + 5000, mText), 'an der Grenze noch gültig');
  Assert.IsFalse(mCache.Lookup(mKey, cT0 + 5001, mText), 'verfallen');
  Assert.AreEqual(0, mCache.Count, 'verfallene Einträge entfernt');
end;

procedure TDpccLateAnswersTests.HintCacheDropsChangedDocument;
var
  mCache: IDpccHintCache;
  mText: string;
begin
  mCache := TDpccHintCache.Create(4, 5000);
  mCache.Store(TDpccHintKey.Make(cFile, 'Werkzeug', 0, 0, 1), 'alt', cT0);
  mCache.Store(TDpccHintKey.Make('C:\P\Andere.pas', 'Werkzeug', 0, 0, 5), 'andere', cT0);
  // Derselbe Schlüssel mit neuem Textstand: Der alte Eintrag der Datei fällt weg.
  Assert.IsFalse(mCache.Lookup(TDpccHintKey.Make(cFile, 'Werkzeug', 0, 0, 2), cT0 + 10, mText), 'geändert');
  Assert.AreEqual(1, mCache.Count, 'nur die andere Datei bleibt');
  Assert.IsTrue(mCache.Lookup(TDpccHintKey.Make('C:\P\Andere.pas', 'Werkzeug', 0, 0, 5), cT0 + 10, mText));
  Assert.AreEqual('andere', mText);
  mCache.Clear;
  Assert.AreEqual(0, mCache.Count);
end;

procedure TDpccLateAnswersTests.HintCacheEvictsOldest;
var
  mCache: IDpccHintCache;
  mLine: Integer;
  mText: string;
begin
  mCache := TDpccHintCache.Create(3, 5000);
  for mLine := 0 to 3 do
  begin
    mCache.Store(TDpccHintKey.Make(cFile, 'Werkzeug', mLine, 0, 1), IntToStr(mLine), cT0 + UInt64(mLine));
  end;
  Assert.AreEqual(3, mCache.Count);
  Assert.IsFalse(mCache.Lookup(TDpccHintKey.Make(cFile, 'Werkzeug', 0, 0, 1), cT0 + 10, mText), 'ältester weg');
  Assert.IsTrue(mCache.Lookup(TDpccHintKey.Make(cFile, 'Werkzeug', 3, 0, 1), cT0 + 10, mText));
  Assert.AreEqual('3', mText);
  // Erneut gemerkt ersetzt den Eintrag statt ihn zu verdoppeln.
  mCache.Store(TDpccHintKey.Make(cFile, 'Werkzeug', 3, 0, 1), 'neu', cT0 + 20);
  Assert.AreEqual(3, mCache.Count);
  Assert.IsTrue(mCache.Lookup(TDpccHintKey.Make(cFile, 'Werkzeug', 3, 0, 1), cT0 + 30, mText));
  Assert.AreEqual('neu', mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccLateAnswersTests);

end.
