unit dpcc.Core.Diagnostics.Flow.Tests;

// Tests für das Ablaufprotokoll (LOG1): „Ablauf protokollieren (Log)“ auf der Seite dpcc, derselbe Registry-Wert wie
// das frühere Diagnose = 1.
// - TDpccFlow (dpcc.Core.Diagnostics.Flow): Format der Zeilen („#n Bereich: …“), Kennungen je Bereich, ausgeschaltet
//   weder Kennung noch Zeile, ein Fehler des Ziels erreicht den Aufrufer nie, Kennzeichen von dpcc.log werden zu
//   Dateinamen bzw. „<name>“; Dateien nur ohne Ordner, das Wort an der Stelle gekürzt, Vergleich zweier Dateien ohne
//   die Ordner zu nennen.
// - TDpccGotoDefinition.OnTargetWhy: dasselbe Urteil wie OnTarget, mit seinen Teilen (Datei, Zeile, Stelle im Wort).
// - TDpccGotoLog.FlowResult: letzte Zeile eines Sprungs (Ergebnis an die IDE, gleich der Ausgangsstelle).
// - TDpccPluginSettings.Diagnose: DWORD Diagnose, Vorgabe aus; ein von Hand gesetztes Diagnose = 1 (auch andere
//   Werte ungleich 0) gilt, gespeichert wird 0/1 zuletzt nach den übrigen Werten der Seite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccFlowTests = class
  public
    /// <summary>„#12 Sprung: …“, ohne Kennung „#- …“; Namen der vier Bereiche.</summary>
    [Test]
    procedure LineFormatAndAreas;
    /// <summary>Ausgeschaltet: Start liefert 0, Step ruft das Ziel nicht.</summary>
    [Test]
    procedure DisabledWritesNothing;
    /// <summary>Eingeschaltet: neue Kennungen je Start, Current je Bereich, Zeilen ans Ziel; nach dem Ausschalten nichts
    /// mehr.</summary>
    [Test]
    procedure EnabledWritesThroughSink;
    /// <summary>Ein Ziel, das wirft, stört den Aufrufer nicht.</summary>
    [Test]
    procedure SinkErrorNeverEscapes;
    /// <summary>Kennzeichen aus dpcc.log-Zeilen: Name → „&lt;name&gt;“, Pfad → Dateiname, Text bleibt.</summary>
    [Test]
    procedure MarksBecomeFileNamesAndPlaceholders;
    /// <summary>Datei ohne Ordner (auch mit / und als URI), Stelle als Zeile:Spalte, Wort gekürzt.</summary>
    [Test]
    procedure FilePlaceAndWordTexts;
    /// <summary>Gleiche Dateien „gleich“; sonst beide Namen bzw. bei gleichem Namen die Art des Unterschieds.</summary>
    [Test]
    procedure FileComparisonNamesTheDifference;
    /// <summary>OnTargetWhy beginnt genau dann mit „ja“, wenn OnTarget gilt, und nennt die Teile.</summary>
    [Test]
    procedure OnTargetWhyMatchesOnTarget;
    /// <summary>Ergebnis an die IDE: mit Datei und Vergleich zur Ausgangsstelle, ohne Datei mit Ausgang.</summary>
    [Test]
    procedure FlowResultTellsWhatTheIdeGets;
    /// <summary>Diagnose: Vorgabe aus, DWORD, von Hand gesetzt gilt, gespeichert als 0/1 zuletzt.</summary>
    [Test]
    procedure DiagnoseSettingUsesTheRegistryValue;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  dpcc.Text.LogMarks,
  dpcc.Core.Diagnostics.Flow,
  dpcc.Core.Editor.Navigation,
  dpcc.Core.Settings.Plugin;

{ TDpccFlowTests }

procedure TDpccFlowTests.LineFormatAndAreas;
begin
  Assert.AreEqual('#12 Sprung: Eintritt', TDpccFlow.Line(12, TDpccFlowArea.Jump, 'Eintritt'));
  Assert.AreEqual('#- Hover: x', TDpccFlow.Line(0, TDpccFlowArea.Hover, 'x'));
  Assert.AreEqual('Sprung', TDpccFlow.AreaName(TDpccFlowArea.Jump));
  Assert.AreEqual('Vervollständigung', TDpccFlow.AreaName(TDpccFlowArea.Completion));
  Assert.AreEqual('Hover', TDpccFlow.AreaName(TDpccFlowArea.Hover));
  Assert.AreEqual('Parameterhilfe', TDpccFlow.AreaName(TDpccFlowArea.Signature));
  Assert.AreEqual('ja', TDpccFlow.YesNo(True));
  Assert.AreEqual('nein', TDpccFlow.YesNo(False));
end;

procedure TDpccFlowTests.DisabledWritesNothing;
var
  mCalls: Integer;
begin
  mCalls := 0;
  TDpccFlow.SetSink(
    procedure(const ALine: string)
    begin
      Inc(mCalls);
    end);
  try
    TDpccFlow.Enabled := False;
    Assert.AreEqual(0, TDpccFlow.Start(TDpccFlowArea.Jump), 'keine Kennung');
    TDpccFlow.Step(5, TDpccFlowArea.Jump, 'nichts');
    Assert.AreEqual(0, mCalls, 'kein Aufruf des Ziels');
  finally
    TDpccFlow.SetSink(nil);
  end;
end;

procedure TDpccFlowTests.EnabledWritesThroughSink;
var
  mLines: string;
  mFirst, mSecond, mHover: Integer;
begin
  mLines := '';
  TDpccFlow.SetSink(
    procedure(const ALine: string)
    begin
      mLines := mLines + ALine + '|';
    end);
  try
    TDpccFlow.Enabled := True;
    mFirst := TDpccFlow.Start(TDpccFlowArea.Jump);
    mSecond := TDpccFlow.Start(TDpccFlowArea.Jump);
    mHover := TDpccFlow.Start(TDpccFlowArea.Hover);
    Assert.IsTrue(mFirst > 0, 'Kennung');
    Assert.IsTrue(mSecond > mFirst, 'laufende Nummer');
    Assert.IsTrue(mHover > mSecond, 'eine Nummer für alle Bereiche');
    Assert.AreEqual(mSecond, TDpccFlow.Current(TDpccFlowArea.Jump), 'zuletzt begonnener Sprung');
    Assert.AreEqual(mHover, TDpccFlow.Current(TDpccFlowArea.Hover), 'zuletzt begonnener Hover');
    TDpccFlow.Step(mSecond, TDpccFlowArea.Jump, 'Eintritt');
    Assert.AreEqual(Format('#%d Sprung: Eintritt|', [mSecond]), mLines, 'Zeile');
    TDpccFlow.Enabled := False;
    TDpccFlow.Step(mSecond, TDpccFlowArea.Jump, 'danach');
    Assert.AreEqual(Format('#%d Sprung: Eintritt|', [mSecond]), mLines, 'ausgeschaltet keine Zeile');
  finally
    TDpccFlow.Enabled := False;
    TDpccFlow.SetSink(nil);
  end;
end;

procedure TDpccFlowTests.SinkErrorNeverEscapes;
var
  mRaised: Boolean;
begin
  TDpccFlow.SetSink(
    procedure(const ALine: string)
    begin
      raise EInOutError.Create('Platte voll');
    end);
  try
    TDpccFlow.Enabled := True;
    mRaised := False;
    try
      TDpccFlow.Step(1, TDpccFlowArea.Completion, 'Zeile');
    except
      mRaised := True;
    end;
    Assert.IsFalse(mRaised, 'Fehler des Ziels');
  finally
    TDpccFlow.Enabled := False;
    TDpccFlow.SetSink(nil);
  end;
end;

procedure TDpccFlowTests.MarksBecomeFileNamesAndPlaceholders;
var
  mText: string;
begin
  mText := 'kein Ziel (unresolved: ' + TLogMarks.Name('Geheim') + ') in ' + TLogMarks.Path('C:\Kunde\Haupt.pas') +
    ': ' + TLogMarks.Text('Zeitlimit');
  Assert.AreEqual('kein Ziel (unresolved: <name>) in Haupt.pas: Zeitlimit', TDpccFlow.Unmarked(mText));
  Assert.AreEqual('ohne Kennzeichen', TDpccFlow.Unmarked('ohne Kennzeichen'));
end;

procedure TDpccFlowTests.FilePlaceAndWordTexts;
const
  cLine = '  Result := Foo.Bar(1);';
begin
  Assert.AreEqual('Unit1.pas', TDpccFlow.FileText('C:\Projekt\Quellen\Unit1.pas'), 'Windows-Pfad');
  Assert.AreEqual('Unit1.pas', TDpccFlow.FileText('c:/projekt/Unit1.pas'), 'Schrägstriche');
  Assert.AreEqual('Unit1.pas', TDpccFlow.FileText('Unit1.pas'), 'ohne Ordner');
  Assert.AreEqual('-', TDpccFlow.FileText(''), 'ohne Datei');
  Assert.AreEqual('A.pas 12:5', TDpccFlow.PlaceText('C:\P\A.pas', 12, 4), 'Zeile 1-basiert, Spalte = Zeichen + 1');
  // "Foo" beginnt bei Zeichen 12 und endet vor 15.
  Assert.AreEqual('„Foo“', TDpccFlow.WordText(cLine, 12, 15), 'Wort');
  Assert.AreEqual('(kein Wort)', TDpccFlow.WordText(cLine, 15, 15), 'leer');
  Assert.AreEqual('(kein Wort)', TDpccFlow.WordText('', 0, 3), 'ohne Zeile');
  Assert.AreEqual('„' + StringOfChar('a', TDpccFlow.cMaxWordLength) + '…“',
    TDpccFlow.WordText(StringOfChar('a', 100), 0, 100), 'gekürzt');
end;

procedure TDpccFlowTests.FileComparisonNamesTheDifference;
begin
  Assert.AreEqual('gleich', TDpccFlow.FileComparison('C:\P\Haupt.pas', 'c:\p\HAUPT.pas'), 'Groß/Klein in ASCII');
  Assert.AreEqual('verschieden (A.pas | B.pas)', TDpccFlow.FileComparison('C:\P\A.pas', 'C:\P\B.pas'),
    'andere Datei');
  Assert.IsTrue(ContainsText(TDpccFlow.FileComparison('C:\P\A.pas', 'C:/P/A.pas'), 'Trennzeichen'), 'Schrägstrich');
  // Wie OnTarget (TTextUris.SamePath): Trennzeichen, "." und ".." und Groß/Klein außerhalb von ASCII machen keine
  // andere Datei; das Urteil beginnt mit „gleich“ und nennt, was abwich.
  Assert.IsTrue(StartsText('gleich nach Vereinheitlichung', TDpccFlow.FileComparison('C:\P\A.pas', 'C:/P/A.pas')),
    'Schrägstrich ist dieselbe Datei');
  Assert.IsTrue(StartsText('gleich nach Vereinheitlichung', TDpccFlow.FileComparison('C:\P\Q\..\A.pas',
    'c:\p\a.pas')), '".." ist dieselbe Datei');
  Assert.IsTrue(StartsText('gleich nach Vereinheitlichung', TDpccFlow.FileComparison('C:\M'#$00FC'ller\A.pas',
    'C:\M'#$00DC'LLER\A.pas')), 'Umlaut ist dieselbe Datei');
  Assert.IsTrue(ContainsText(TDpccFlow.FileComparison('C:\P\A.pas', 'D:\P\A.pas'), 'anderes Laufwerk'), 'Laufwerk');
  Assert.IsTrue(ContainsText(TDpccFlow.FileComparison('C:\PROGRA~1\A.pas', 'C:\Programme\A.pas'), 'Kurzname'),
    'Kurzname');
  Assert.IsTrue(ContainsText(TDpccFlow.FileComparison('C:\Mein%20Ordner\A.pas', 'C:\Mein Ordner\A.pas'),
    'URI-Kodierung'), 'Kodierung');
  Assert.AreEqual('verschieden (gleicher Name A.pas; anderer Ordner, Tiefe 2 | 3)',
    TDpccFlow.FileComparison('C:\P\A.pas', 'C:\P\Q\A.pas'), 'Ordner');
  Assert.IsTrue(ContainsText(TDpccFlow.FileComparison('C:\Müller\A.pas', 'C:\MÜLLER\A.pas'),
    'außerhalb von ASCII'), 'Umlaut im Ordner');
  // Nie die Ordner selbst.
  Assert.IsFalse(ContainsText(TDpccFlow.FileComparison('C:\Geheim\A.pas', 'C:\Geheim\Q\A.pas'), 'Geheim'),
    'Ordnername');
end;

procedure TDpccFlowTests.OnTargetWhyMatchesOnTarget;
type
  TCase = record
    FileName: string;
    Line, Character: Integer;
    LineText, TargetFile: string;
    TargetLine, TargetCharacter: Integer;
  end;
const
  cDecl = '    procedure Bar;';
  cUse = '  Foo := Bar(Foo);';
  cCases: array[0..9] of TCase = (
    (FileName: 'C:\P\Haupt.pas'; Line: 5; Character: 14; LineText: cDecl; TargetFile: 'c:\p\haupt.pas';
      TargetLine: 5; TargetCharacter: 14),
    (FileName: 'C:\P\Haupt.pas'; Line: 5; Character: 16; LineText: cDecl; TargetFile: 'C:\P\Haupt.pas';
      TargetLine: 5; TargetCharacter: 14),
    (FileName: 'C:\P\Haupt.pas'; Line: 5; Character: 17; LineText: cDecl; TargetFile: 'C:\P\Haupt.pas';
      TargetLine: 5; TargetCharacter: 14),
    (FileName: 'C:\P\A.pas'; Line: 3; Character: 2; LineText: cUse; TargetFile: 'C:\P\B.pas'; TargetLine: 3;
      TargetCharacter: 2),
    (FileName: 'C:\P\A.pas'; Line: 3; Character: 2; LineText: cUse; TargetFile: 'C:\P\A.pas'; TargetLine: 4;
      TargetCharacter: 2),
    (FileName: 'C:\P\A.pas'; Line: 3; Character: 9; LineText: cUse; TargetFile: 'C:\P\A.pas'; TargetLine: 3;
      TargetCharacter: 2),
    (FileName: 'C:\P\A.pas'; Line: 3; Character: 1; LineText: cUse; TargetFile: 'C:\P\A.pas'; TargetLine: 3;
      TargetCharacter: 2),
    (FileName: 'C:\P\Haupt.pas'; Line: 5; Character: 14; LineText: cDecl; TargetFile: 'C:\P\Q\Haupt.pas';
      TargetLine: 5; TargetCharacter: 14),
    // Dieselbe Datei in anderer Schreibweise (Schrägstriche, ".."): OnTarget gilt, OnTargetWhy sagt „ja“.
    (FileName: 'C:/P/Haupt.pas'; Line: 5; Character: 14; LineText: cDecl; TargetFile: 'c:\p\haupt.pas';
      TargetLine: 5; TargetCharacter: 14),
    (FileName: 'C:\P\Q\..\Haupt.pas'; Line: 5; Character: 14; LineText: cDecl; TargetFile: 'c:\p\haupt.pas';
      TargetLine: 5; TargetCharacter: 14));
var
  mCase: TCase;
  mIndex: Integer;
  mWhy: string;
  mOn: Boolean;
begin
  for mIndex := Low(cCases) to High(cCases) do
  begin
    mCase := cCases[mIndex];
    mOn := TDpccGotoDefinition.OnTarget(mCase.FileName, mCase.Line, mCase.Character, mCase.LineText,
      mCase.TargetFile, mCase.TargetLine, mCase.TargetCharacter);
    mWhy := TDpccGotoDefinition.OnTargetWhy(mCase.FileName, mCase.Line, mCase.Character, mCase.LineText,
      mCase.TargetFile, mCase.TargetLine, mCase.TargetCharacter);
    Assert.IsTrue(mOn = StartsText('ja ', mWhy), Format('Fall %d: %s', [mIndex, mWhy]));
    Assert.IsTrue(StartsText('ja ', mWhy) or StartsText('nein ', mWhy),
      Format('Fall %d beginnt mit ja/nein', [mIndex]));
  end;
  // Die Teile: Datei, Zeile (1-basiert), Stelle im Wort.
  mWhy := TDpccGotoDefinition.OnTargetWhy('C:\P\Haupt.pas', 5, 14, cDecl, 'c:\p\haupt.pas', 5, 14);
  Assert.AreEqual('ja (Datei gleich; Zeile ja, 6 | 6; Stelle im Wort ja, Spalte 15, Ziel ab 15)', mWhy);
  mWhy := TDpccGotoDefinition.OnTargetWhy('C:\P\A.pas', 3, 2, cUse, 'C:\P\B.pas', 3, 2);
  Assert.AreEqual('nein (Datei verschieden (A.pas | B.pas); Zeile ja, 4 | 4; Stelle im Wort -, Spalte 3, Ziel ab 3)',
    mWhy);
  mWhy := TDpccGotoDefinition.OnTargetWhy('C:\P\A.pas', 3, 9, cUse, 'C:\P\A.pas', 3, 2);
  Assert.IsTrue(ContainsText(mWhy, 'Stelle im Wort nein'), mWhy);
  mWhy := TDpccGotoDefinition.OnTargetWhy('C:\P\A.pas', 3, 2, cUse, 'C:\P\A.pas', 4, 2);
  Assert.IsTrue(ContainsText(mWhy, 'Zeile nein, 4 | 5'), mWhy);
  // Schrägstriche statt Backslashes: ja, und die Datei heißt „gleich nach Vereinheitlichung“.
  mWhy := TDpccGotoDefinition.OnTargetWhy('C:/P/Haupt.pas', 5, 14, cDecl, 'c:\p\haupt.pas', 5, 14);
  Assert.IsTrue(StartsText('ja (Datei gleich nach Vereinheitlichung', mWhy), mWhy);
end;

procedure TDpccFlowTests.FlowResultTellsWhatTheIdeGets;
var
  mAnswer: TDpccGotoAnswer;
  mText: string;
begin
  // Ziel in derselben Zeile: Die IDE bleibt stehen (der Fall „Deklaration springt nicht“).
  mAnswer := TDpccGotoDefinition.Answer(TDpccGotoOutcome.Found, 'C:\P\Haupt.pas', 5);
  mText := TDpccGotoLog.FlowResult(TDpccGotoOutcome.Found, mAnswer, True, 'c:\p\haupt.pas', 6);
  Assert.AreEqual('Ergebnis an die IDE: True, Haupt.pas Zeile 6; gleich der Ausgangsstelle: ja (die IDE bleibt in ' +
    'derselben Zeile)', mText);
  mText := TDpccGotoLog.FlowResult(TDpccGotoOutcome.Found, mAnswer, True, 'C:\P\Haupt.pas', 20);
  Assert.IsTrue(EndsText('gleich der Ausgangsstelle: nein', mText), mText);
  mText := TDpccGotoLog.FlowResult(TDpccGotoOutcome.Found, mAnswer, False, '', 0);
  Assert.IsTrue(EndsText('gleich der Ausgangsstelle: unbekannt', mText), mText);
  // Ohne Ziel: True ohne Datei, mit Ausgang; nachgereicht bzw. wartend mit Hinweis.
  mAnswer := TDpccGotoDefinition.Answer(TDpccGotoOutcome.NotFound, '', 0);
  Assert.AreEqual('Ergebnis an die IDE: True ohne Datei (kein Sprung der IDE), Ausgang NotFound',
    TDpccGotoLog.FlowResult(TDpccGotoOutcome.NotFound, mAnswer, True, 'C:\P\A.pas', 1));
  mAnswer := TDpccGotoDefinition.Answer(TDpccGotoOutcome.Deferred, '', 0);
  Assert.IsTrue(ContainsText(TDpccGotoLog.FlowResult(TDpccGotoOutcome.Deferred, mAnswer, True, 'C:\P\A.pas', 1),
    'LateGoto'), 'nachgereicht');
  mAnswer := TDpccGotoDefinition.Answer(TDpccGotoOutcome.Starting, '', 0);
  Assert.IsTrue(ContainsText(TDpccGotoLog.FlowResult(TDpccGotoOutcome.Starting, mAnswer, True, 'C:\P\A.pas', 1),
    'wartet auf den Start'), 'Start');
  Assert.AreEqual('NoSession', TDpccGotoLog.OutcomeName(TDpccGotoOutcome.NoSession));
  Assert.AreEqual('Starting', TDpccGotoLog.OutcomeName(TDpccGotoOutcome.Starting));
end;

procedure TDpccFlowTests.DiagnoseSettingUsesTheRegistryValue;
var
  mStore: IDpccMemorySettingsStore;
  mSettings: TDpccPluginSettings;
  mStored: TArray<string>;
begin
  Assert.IsFalse(TDpccPluginSettings.Defaults.Diagnose, 'Vorgabe aus');
  // Von Hand gesetzt wie bisher (DWORD Diagnose = 1): gilt; jeder Wert ungleich 0 wie bisher an.
  mStore := TDpccMemorySettingsStore.Create;
  mStore.WriteInteger('Diagnose', 1);
  mSettings.Load(mStore);
  Assert.IsTrue(mSettings.Diagnose, 'Diagnose = 1');
  mStore.WriteInteger('Diagnose', 2);
  mSettings.Load(mStore);
  Assert.IsTrue(mSettings.Diagnose, 'Diagnose = 2');
  mStore.WriteInteger('Diagnose', 0);
  mSettings.Load(mStore);
  Assert.IsFalse(mSettings.Diagnose, 'Diagnose = 0');
  // Kein DWORD (Text): wie fehlend, wie TDpccCodeInsightPaths.DiagnoseEnabled.
  mStore := TDpccMemorySettingsStore.Create;
  mStore.WriteString('Diagnose', '1');
  mSettings.Load(mStore);
  Assert.IsFalse(mSettings.Diagnose, 'Text');
  // Gespeichert als DWORD 0/1 unter demselben Namen, zuletzt (Abschnitt IDE).
  mSettings := TDpccPluginSettings.Defaults;
  mSettings.Diagnose := True;
  mStore := TDpccMemorySettingsStore.FromSettings(mSettings);
  Assert.IsTrue(mStore.HasInteger('Diagnose'), 'DWORD');
  Assert.AreEqual('1', mStore.Text('Diagnose'), 'an');
  mSettings.Diagnose := False;
  mSettings.Save(mStore);
  Assert.AreEqual('0', mStore.Text('Diagnose'), 'aus');
  mStored := TDpccPluginSettings.StoredNames;
  Assert.AreEqual('Diagnose', mStored[High(mStored)], 'zuletzt gespeichert');
  Assert.IsFalse(MatchText('Diagnose', TDpccPluginSettings.ReadOnlyNames), 'nicht nur gelesen');
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccFlowTests);

end.
