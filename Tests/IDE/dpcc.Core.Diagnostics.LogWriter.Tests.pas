unit dpcc.Core.Diagnostics.LogWriter.Tests;

// Tests für den Schreib-Thread der Protokolle (perf1, dpcc.Core.Diagnostics.LogWriter) und seinen Einsatz in
// TDpccRotatingLog:
// - Reihenfolge: Zeilen kommen in der Reihenfolge des Einreihens beim Ziel an, mit dem Zeitstempel des Aufrufs.
// - Überlauf: Ist die Warteschlange voll, wird verworfen; die Zahl kommt danach als eine Zeile.
// - Flush wartet, bis alles geschrieben ist; ohne Thread kehrt es sofort zurück.
// - Nach Stop liefert Enqueue False, und TDpccRotatingLog schreibt wieder selbst (keine Zeile geht verloren).
// - Hängt ein Schreibvorgang beim Stop, geht der Thread an TDpccOverdueThreads und schreibt danach zu Ende.
// Das Testprogramm startet TDpccLogWriter.Shared nicht: Alle übrigen Tests schreiben ihr Protokoll synchron.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccLogWriterTests = class
  public
    /// <summary>Erste Benutzung (Thread, Generics, Kodierung, Mutex) vor der Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure KeepsOrderAndStamp;
    /// <summary>Volle Warteschlange: verworfen und als eine Zeile gezählt gemeldet.</summary>
    [Test]
    procedure OverflowIsCountedInOneLine;
    [Test]
    procedure FlushWaitsUntilWritten;
    [Test]
    procedure EnqueueFailsAfterStop;
    /// <summary>TDpccRotatingLog: mit laufendem Thread nach Flush in der Datei, nach Stop sofort.</summary>
    [Test]
    procedure RotatingLogWritesThroughWriterAndAfterStop;
    /// <summary>Hängt das Ziel beim Stop, endet Stop nach der Zeitgrenze; der Thread schreibt danach zu Ende.
    /// </summary>
    [Test]
    procedure StopWithHangingTargetHandsOverThread;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  dpcc.Core.Diagnostics.LogWriter,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.WorkerSlot;

const
  cWaitMs = 5000;

type
  /// <summary>Sammelt Zeilen aus dem Schreib-Thread; blockiert auf Wunsch den ersten Schreibvorgang bis Release.
  /// </summary>
  TCollectTarget = class(TInterfacedObject, IDpccLogTarget)
  private
    FLock: TCriticalSection;
    FLines: TStringList;
    FStamps: TArray<TDateTime>;
    FBatches: Integer;
    FBlockFirst: Boolean;
    FEntered: TEvent;
    FRelease: TEvent;
  public
    constructor Create(ABlockFirst: Boolean);
    destructor Destroy; override;
    procedure WriteLines(const ALines: TArray<TDpccLogLine>);
    function Text: string;
    function Count: Integer;
    function Batches: Integer;
    function Stamp(AIndex: Integer): TDateTime;
    /// <summary>Gesetzt, sobald der erste Schreibvorgang begonnen hat.</summary>
    property Entered: TEvent read FEntered;
    property Release: TEvent read FRelease;
  end;

constructor TCollectTarget.Create(ABlockFirst: Boolean);
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FLines := TStringList.Create;
  FBlockFirst := ABlockFirst;
  FEntered := TEvent.Create(nil, True, False, '');
  FRelease := TEvent.Create(nil, True, False, '');
end;

destructor TCollectTarget.Destroy;
begin
  FRelease.Free;
  FEntered.Free;
  FLines.Free;
  FLock.Free;
  inherited;
end;

procedure TCollectTarget.WriteLines(const ALines: TArray<TDpccLogLine>);
var
  mLine: TDpccLogLine;
begin
  FEntered.SetEvent;
  if FBlockFirst then
  begin
    FBlockFirst := False;
    FRelease.WaitFor(cWaitMs);
  end;
  FLock.Enter;
  try
    for mLine in ALines do
    begin
      FLines.Add(mLine.Text);
      FStamps := FStamps + [mLine.Stamp];
    end;
    Inc(FBatches);
  finally
    FLock.Leave;
  end;
end;

function TCollectTarget.Text: string;
begin
  FLock.Enter;
  try
    Result := string.Join('|', FLines.ToStringArray);
  finally
    FLock.Leave;
  end;
end;

function TCollectTarget.Count: Integer;
begin
  FLock.Enter;
  try
    Result := FLines.Count;
  finally
    FLock.Leave;
  end;
end;

function TCollectTarget.Batches: Integer;
begin
  FLock.Enter;
  try
    Result := FBatches;
  finally
    FLock.Leave;
  end;
end;

function TCollectTarget.Stamp(AIndex: Integer): TDateTime;
begin
  FLock.Enter;
  try
    Result := FStamps[AIndex];
  finally
    FLock.Leave;
  end;
end;

/// <summary>Leerer eigener Ordner für ein Testprotokoll.</summary>
function NewLogFolder: string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'dpccLogWriterTests' + PathDelim + TGUID.NewGuid.ToString);
  ForceDirectories(Result);
end;

procedure RemoveLogFolder(const AFolder: string);
begin
  try
    if TDirectory.Exists(AFolder) then
    begin
      TDirectory.Delete(AFolder, True);
    end;
  except
    // Aufräumen ist Beiwerk.
  end;
end;

{ TDpccLogWriterTests }

procedure TDpccLogWriterTests.WarmUp;
var
  mWriter: TDpccLogWriter;
  mTarget: TCollectTarget;
  mTargetRef: IDpccLogTarget;
  mLog: TDpccRotatingLog;
  mFolder: string;
begin
  mTarget := TCollectTarget.Create(False);
  mTargetRef := mTarget;
  mWriter := TDpccLogWriter.Create(4);
  try
    mWriter.Start;
    mWriter.Enqueue(mTargetRef, TDpccLogLine.Create('a'));
    mWriter.Flush(cWaitMs);
    mWriter.Stop(cWaitMs);
  finally
    mWriter.Free;
  end;
  mFolder := NewLogFolder;
  mLog := TDpccRotatingLog.Create(mFolder);
  try
    mLog.Add('Vorwärmen');
    TFile.ReadAllText(mLog.FileName, TEncoding.UTF8);
  finally
    mLog.Free;
    RemoveLogFolder(mFolder);
  end;
end;

procedure TDpccLogWriterTests.KeepsOrderAndStamp;
var
  mWriter: TDpccLogWriter;
  mTarget: TCollectTarget;
  mTargetRef: IDpccLogTarget;
  mIndex: Integer;
  mExpected: TStringList;
  mLine: TDpccLogLine;
begin
  mTarget := TCollectTarget.Create(False);
  mTargetRef := mTarget;
  mExpected := TStringList.Create;
  mWriter := TDpccLogWriter.Create;
  try
    mWriter.Start;
    for mIndex := 1 to 500 do
    begin
      mExpected.Add(IntToStr(mIndex));
      Assert.IsTrue(mWriter.Enqueue(mTargetRef, TDpccLogLine.Create(IntToStr(mIndex))), 'eingereiht');
    end;
    // Zeitstempel vom Aufruf, nicht vom Schreiben.
    mLine := TDpccLogLine.Create('alt');
    mLine.Stamp := EncodeDate(2001, 2, 3);
    mExpected.Add('alt');
    mWriter.Enqueue(mTargetRef, mLine);
    Assert.IsTrue(mWriter.Flush(cWaitMs), 'Flush');
    Assert.AreEqual(string.Join('|', mExpected.ToStringArray), mTarget.Text);
    Assert.IsTrue(mTarget.Stamp(500) = EncodeDate(2001, 2, 3), 'Zeitstempel des Aufrufs');
    Assert.IsTrue(mWriter.Stop(cWaitMs), 'Stop');
  finally
    mWriter.Free;
    mExpected.Free;
  end;
end;

procedure TDpccLogWriterTests.OverflowIsCountedInOneLine;
var
  mWriter: TDpccLogWriter;
  mTarget: TCollectTarget;
  mTargetRef: IDpccLogTarget;
  mIndex: Integer;
begin
  mTarget := TCollectTarget.Create(True);
  mTargetRef := mTarget;
  mWriter := TDpccLogWriter.Create(5);
  try
    mWriter.Start;
    mWriter.Enqueue(mTargetRef, TDpccLogLine.Create('erste'));
    // Der Thread steckt im ersten Schreibvorgang: Ab jetzt füllt sich die Warteschlange.
    Assert.AreEqual(Ord(wrSignaled), Ord(mTarget.Entered.WaitFor(cWaitMs)), 'erster Schreibvorgang');
    for mIndex := 1 to 8 do
    begin
      Assert.IsTrue(mWriter.Enqueue(mTargetRef, TDpccLogLine.Create(IntToStr(mIndex))), 'übernommen oder gezählt');
    end;
    mTarget.Release.SetEvent;
    Assert.IsTrue(mWriter.Flush(cWaitMs), 'Flush');
    Assert.AreEqual('erste|1|2|3|4|5|Protokoll: 3 Zeilen verworfen (Warteschlange voll)', mTarget.Text);
    Assert.IsTrue(mWriter.Stop(cWaitMs), 'Stop');
  finally
    mTarget.Release.SetEvent;
    mWriter.Free;
  end;
end;

procedure TDpccLogWriterTests.FlushWaitsUntilWritten;
var
  mWriter: TDpccLogWriter;
  mTarget: TCollectTarget;
  mTargetRef: IDpccLogTarget;
begin
  mTarget := TCollectTarget.Create(True);
  mTargetRef := mTarget;
  mWriter := TDpccLogWriter.Create;
  try
    // Ohne Thread nichts zu warten.
    Assert.IsTrue(mWriter.Flush(0), 'ohne Thread');
    mWriter.Start;
    mWriter.Enqueue(mTargetRef, TDpccLogLine.Create('x'));
    Assert.AreEqual(Ord(wrSignaled), Ord(mTarget.Entered.WaitFor(cWaitMs)), 'Schreibvorgang begonnen');
    Assert.IsFalse(mWriter.Flush(50), 'Schreibvorgang hängt noch');
    Assert.AreEqual(0, mTarget.Count);
    mTarget.Release.SetEvent;
    Assert.IsTrue(mWriter.Flush(cWaitMs), 'danach geschrieben');
    Assert.AreEqual(1, mTarget.Count);
    Assert.IsTrue(mWriter.Stop(cWaitMs), 'Stop');
  finally
    mTarget.Release.SetEvent;
    mWriter.Free;
  end;
end;

procedure TDpccLogWriterTests.EnqueueFailsAfterStop;
var
  mWriter: TDpccLogWriter;
  mTarget: TCollectTarget;
  mTargetRef: IDpccLogTarget;
begin
  mTarget := TCollectTarget.Create(False);
  mTargetRef := mTarget;
  mWriter := TDpccLogWriter.Create;
  try
    Assert.IsFalse(mWriter.Enqueue(mTargetRef, TDpccLogLine.Create('vorher')), 'vor Start');
    mWriter.Start;
    Assert.IsTrue(mWriter.Running);
    Assert.IsTrue(mWriter.Enqueue(mTargetRef, TDpccLogLine.Create('letzte')), 'laufend');
    // Stop schreibt Ausstehendes noch weg.
    Assert.IsTrue(mWriter.Stop(cWaitMs), 'Stop');
    Assert.AreEqual('letzte', mTarget.Text);
    Assert.IsFalse(mWriter.Running);
    Assert.IsFalse(mWriter.Enqueue(mTargetRef, TDpccLogLine.Create('danach')), 'nach Stop');
    // Wieder startbar (Package erneut geladen).
    mWriter.Start;
    Assert.IsTrue(mWriter.Enqueue(mTargetRef, TDpccLogLine.Create('neu')), 'nach erneutem Start');
    Assert.IsTrue(mWriter.Stop(cWaitMs), 'zweiter Stop');
    Assert.AreEqual('letzte|neu', mTarget.Text);
  finally
    mWriter.Free;
  end;
end;

procedure TDpccLogWriterTests.RotatingLogWritesThroughWriterAndAfterStop;
var
  mWriter: TDpccLogWriter;
  mLog: TDpccRotatingLog;
  mFolder, mText: string;
begin
  mFolder := NewLogFolder;
  mWriter := TDpccLogWriter.Create;
  try
    mLog := TDpccRotatingLog.Create(mFolder);
    try
      mWriter.Start;
      mLog.Writer := mWriter;
      mLog.Add('Zeile eins');
      mLog.Add('Zeile zwei');
      Assert.IsTrue(mLog.Flush(cWaitMs), 'Flush');
      mText := TFile.ReadAllText(mLog.FileName, TEncoding.UTF8);
      Assert.IsTrue(Pos('Zeile eins', mText) > 0, mText);
      Assert.IsTrue(Pos('Zeile eins', mText) < Pos('Zeile zwei', mText), 'Reihenfolge');
      // Format unverändert: Datum, Uhrzeit mit Millisekunden, Text.
      Assert.IsTrue(mText.Contains(FormatDateTime('yyyy-mm-dd', Date)), mText);
      // Nach dem Stop schreibt Add selbst; die Zeile steht sofort in der Datei.
      Assert.IsTrue(mWriter.Stop(cWaitMs), 'Stop');
      mLog.Add('nach dem Stopp');
      mText := TFile.ReadAllText(mLog.FileName, TEncoding.UTF8);
      Assert.IsTrue(Pos('nach dem Stopp', mText) > Pos('Zeile zwei', mText), mText);
      Assert.AreEqual(0, mLog.Lost);
    finally
      mLog.Free;
    end;
  finally
    mWriter.Free;
    RemoveLogFolder(mFolder);
  end;
end;

procedure TDpccLogWriterTests.StopWithHangingTargetHandsOverThread;
var
  mWriter: TDpccLogWriter;
  mTarget: TCollectTarget;
  mTargetRef: IDpccLogTarget;
begin
  mTarget := TCollectTarget.Create(True);
  mTargetRef := mTarget;
  mWriter := TDpccLogWriter.Create;
  try
    mWriter.Start;
    mWriter.Enqueue(mTargetRef, TDpccLogLine.Create('hängt'));
    Assert.AreEqual(Ord(wrSignaled), Ord(mTarget.Entered.WaitFor(cWaitMs)), 'Schreibvorgang begonnen');
    mWriter.Enqueue(mTargetRef, TDpccLogLine.Create('wartet'));
    Assert.IsFalse(mWriter.Stop(50), 'Stop endet nach der Zeitgrenze');
    // Danach schreibt jeder selbst; der übergebene Thread schreibt seine Warteschlange zu Ende.
    Assert.IsFalse(mWriter.Enqueue(mTargetRef, TDpccLogLine.Create('nach Stop')), 'nach Stop');
    mTarget.Release.SetEvent;
    Assert.IsTrue(TDpccOverdueThreads.Settle(HInstance, cWaitMs), 'Thread beendet');
    Assert.AreEqual('hängt|wartet', mTarget.Text);
  finally
    mTarget.Release.SetEvent;
    mWriter.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccLogWriterTests);

end.
