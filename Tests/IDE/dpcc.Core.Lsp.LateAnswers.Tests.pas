unit dpcc.Core.Lsp.LateAnswers.Tests;

// Tests für kurz erwartete Antworten (dpcc.Core.Lsp.LateAnswers): Übergabe zwischen Hintergrund-Thread und
// Hauptthread (rechtzeitig, nachgereicht, mit echtem Thread), die Regeln für ein nachgereichtes Sprungziel und der
// Zwischenspeicher der Symbolhinweise (Wort, Textstand, Verfall, Größe).

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
