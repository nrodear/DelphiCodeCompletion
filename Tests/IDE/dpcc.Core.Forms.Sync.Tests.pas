unit dpcc.Core.Forms.Sync.Tests;

// Abgleich offener Formulare ohne Arbeit im Hauptthread (dpcc.Core.Forms.Sync), ohne IDE und ohne Threads:
// Fingerabdruck „unverändert“, Reihenfolge je Formular (ein Auftrag je Datei, danach genau einmal der neueste Stand,
// Generationen, Epoche einer Sitzung), Schließen während eines Auftrags, Höchstzahl gleichzeitiger Aufträge, Auswahl
// großer Formulare je Takt, Quelltexte eines gespeicherten Moduls und die Teilung von TDpccFormText in Binärstrom und
// Text.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccFormSyncTests = class
  public
    /// <summary>Gleiche Bytes: gleicher Fingerabdruck; andere Bytes oder Länge: anderer; leer = unbekannt.</summary>
    [Test]
    procedure FingerprintDetectsChange;
    /// <summary>Gleicher Strom wie zuletzt: unverändert; neuer Strom: Start.</summary>
    [Test]
    procedure UnchangedIsSkipped;
    /// <summary>Je Datei ein Auftrag; Änderungen währenddessen warten, nur der neueste läuft danach genau einmal.
    /// </summary>
    [Test]
    procedure OneRunPerFileThenLatestOnce;
    /// <summary>Ein doppelt oder veraltet gemeldetes Ende ändert nichts; Generationen steigen.</summary>
    [Test]
    procedure StaleFinishIsIgnored;
    /// <summary>Neue Sitzung: laufende Ergebnisse verworfen, danach alles neu.</summary>
    [Test]
    procedure ResetDiscardsRunningResults;
    /// <summary>Geschlossen während des Auftrags: Abmelden erst nach seinem Ende, Ergebnis nicht übernommen.</summary>
    [Test]
    procedure CloseWhileRunningDefersClose;
    /// <summary>Wieder geöffnet, bevor der Auftrag fertig ist: kein Abmelden, der neue Stand folgt.</summary>
    [Test]
    procedure ReopenWhileClosingKeepsForm;
    /// <summary>Höchstens MaxRunning Aufträge; weitere starten der Reihe nach.</summary>
    [Test]
    procedure MaxRunningQueuesOthers;
    /// <summary>Nicht angekommen: derselbe Strom geht beim nächsten Mal neu los.</summary>
    [Test]
    procedure FailedRunIsResent;
    /// <summary>Takt beim Abgleich aller: höchstens AMax, ein großes oder unbekanntes allein.</summary>
    [Test]
    procedure TickTakesLargeFormsAlone;
    /// <summary>Gemerkte Größe übersteht eine neue Sitzung, nicht das Schließen.</summary>
    [Test]
    procedure LastSizeSurvivesReset;
    /// <summary>Quelltexte eines gespeicherten Moduls nur aus seinem Namen.</summary>
    [Test]
    procedure SavedSourcesFromModuleName;
    /// <summary>Write = BinaryToText(WriteBinary); geänderte Eigenschaft ändert den Fingerabdruck.</summary>
    [Test]
    procedure BinaryAndTextAgree;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  dpcc.Core.Forms.Text,
  dpcc.Core.Forms.Sync;

const
  cFile = 'C:\P\Haupt.dfm';
  cOther = 'C:\P\Neben.dfm';
  cThird = 'C:\P\Dritte.dfm';

function Bytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;

procedure TDpccFormSyncTests.FingerprintDetectsChange;
var
  mA, mB, mC, mEmpty: TDpccFormFingerprint;
begin
  mA := TDpccFormFingerprint.FromBinary(Bytes('object Form1: TForm1 end'));
  mB := TDpccFormFingerprint.FromBinary(Bytes('object Form1: TForm1 end'));
  mC := TDpccFormFingerprint.FromBinary(Bytes('object Form1: TForm1 Tag=1 end'));
  mEmpty := TDpccFormFingerprint.FromBinary(nil);
  Assert.IsTrue(mA.SameAs(mB));
  Assert.IsFalse(mA.SameAs(mC));
  Assert.IsFalse(mA.IsEmpty);
  Assert.IsTrue(mEmpty.IsEmpty);
  Assert.IsFalse(mA.SameAs(mEmpty));
end;

procedure TDpccFormSyncTests.UnchangedIsSkipped;
var
  mPlan: TDpccFormSyncPlan;
  mJob, mAgain: TDpccFormSyncJob;
begin
  mPlan := TDpccFormSyncPlan.Create;
  try
    Assert.IsTrue(mPlan.Offer(cFile, Bytes('eins'), mJob) = TDpccFormOffer.Start);
    Assert.AreEqual(cFile, mJob.FileName);
    Assert.IsTrue(mPlan.Finished(mJob, True).Accepted);
    // Gleicher Stand (auch in anderer Schreibweise der Datei): nichts zu tun.
    Assert.IsTrue(mPlan.Offer(cFile, Bytes('eins'), mAgain) = TDpccFormOffer.Unchanged);
    Assert.IsTrue(mPlan.Offer(LowerCase(cFile), Bytes('eins'), mAgain) = TDpccFormOffer.Unchanged);
    Assert.IsTrue(mPlan.Offer(cFile, Bytes('zwei'), mAgain) = TDpccFormOffer.Start);
    Assert.AreEqual(1, mPlan.Running);
  finally
    mPlan.Free;
  end;
end;

procedure TDpccFormSyncTests.OneRunPerFileThenLatestOnce;
var
  mPlan: TDpccFormSyncPlan;
  mFirst, mQueued: TDpccFormSyncJob;
  mDone: TDpccFormSyncDone;
begin
  mPlan := TDpccFormSyncPlan.Create;
  try
    Assert.IsTrue(mPlan.Offer(cFile, Bytes('eins'), mFirst) = TDpccFormOffer.Start);
    Assert.IsTrue(mPlan.Offer(cFile, Bytes('zwei'), mQueued) = TDpccFormOffer.Queued);
    Assert.IsTrue(mPlan.Offer(cFile, Bytes('drei'), mQueued) = TDpccFormOffer.Queued);
    // Zurück auf den wartenden Stand: unverändert, nichts Neues.
    Assert.IsTrue(mPlan.Offer(cFile, Bytes('drei'), mQueued) = TDpccFormOffer.Unchanged);
    Assert.AreEqual(1, mPlan.Running);
    mDone := mPlan.Finished(mFirst, True);
    Assert.IsTrue(mDone.Accepted);
    Assert.IsTrue(mDone.HasNext);
    // Nur der neueste Stand läuft, mit jüngerer Generation.
    Assert.AreEqual('drei', TEncoding.UTF8.GetString(mDone.Next.Binary));
    Assert.IsTrue(mDone.Next.Generation > mFirst.Generation);
    Assert.AreEqual(1, mPlan.Running);
    mDone := mPlan.Finished(mDone.Next, True);
    Assert.IsTrue(mDone.Accepted);
    Assert.IsFalse(mDone.HasNext);
    Assert.AreEqual(0, mPlan.Running);
  finally
    mPlan.Free;
  end;
end;

procedure TDpccFormSyncTests.StaleFinishIsIgnored;
var
  mPlan: TDpccFormSyncPlan;
  mFirst, mSecond, mDummy: TDpccFormSyncJob;
  mDone: TDpccFormSyncDone;
begin
  mPlan := TDpccFormSyncPlan.Create;
  try
    mPlan.Offer(cFile, Bytes('eins'), mFirst);
    mPlan.Offer(cFile, Bytes('zwei'), mDummy);
    mDone := mPlan.Finished(mFirst, True);
    mSecond := mDone.Next;
    Assert.IsTrue(mPlan.IsCurrent(mSecond));
    Assert.IsFalse(mPlan.IsCurrent(mFirst));
    // Das alte Ende noch einmal: weder übernommen noch ein Zähler verändert.
    mDone := mPlan.Finished(mFirst, True);
    Assert.IsFalse(mDone.Accepted);
    Assert.IsFalse(mDone.HasNext);
    Assert.AreEqual(1, mPlan.Running);
    Assert.IsTrue(mPlan.Finished(mSecond, True).Accepted);
    Assert.IsFalse(mPlan.Finished(mSecond, True).Accepted);
    Assert.AreEqual(0, mPlan.Running);
  finally
    mPlan.Free;
  end;
end;

procedure TDpccFormSyncTests.ResetDiscardsRunningResults;
var
  mPlan: TDpccFormSyncPlan;
  mOld, mNew: TDpccFormSyncJob;
  mDone: TDpccFormSyncDone;
begin
  mPlan := TDpccFormSyncPlan.Create;
  try
    mPlan.Offer(cFile, Bytes('eins'), mOld);
    mPlan.Reset;
    Assert.AreEqual(0, mPlan.Running);
    Assert.IsFalse(mPlan.IsCurrent(mOld));
    // Neue Sitzung: derselbe Stand geht neu los, in der neuen Epoche.
    Assert.IsTrue(mPlan.Offer(cFile, Bytes('eins'), mNew) = TDpccFormOffer.Start);
    Assert.IsTrue(mNew.Epoch <> mOld.Epoch);
    mDone := mPlan.Finished(mOld, True);
    Assert.IsFalse(mDone.Accepted);
    Assert.AreEqual('', mDone.CloseFile);
    Assert.AreEqual(1, mPlan.Running);
    Assert.IsTrue(mPlan.IsCurrent(mNew));
  finally
    mPlan.Free;
  end;
end;

procedure TDpccFormSyncTests.CloseWhileRunningDefersClose;
var
  mPlan: TDpccFormSyncPlan;
  mJob, mDummy: TDpccFormSyncJob;
  mDone: TDpccFormSyncDone;
begin
  mPlan := TDpccFormSyncPlan.Create;
  try
    mPlan.Offer(cFile, Bytes('eins'), mJob);
    mPlan.Offer(cFile, Bytes('zwei'), mDummy);
    Assert.IsFalse(mPlan.Close(cFile));
    Assert.IsFalse(mPlan.IsCurrent(mJob));
    mDone := mPlan.Finished(mJob, True);
    Assert.IsFalse(mDone.Accepted);
    Assert.AreEqual(cFile, mDone.CloseFile);
    // Der wartende Stand des geschlossenen Formulars läuft nicht mehr.
    Assert.IsFalse(mDone.HasNext);
    Assert.AreEqual(0, mPlan.Running);
    // Ohne laufenden Auftrag: sofort abmelden.
    Assert.IsTrue(mPlan.Close(cFile));
    Assert.IsTrue(mPlan.Close(cOther));
  finally
    mPlan.Free;
  end;
end;

procedure TDpccFormSyncTests.ReopenWhileClosingKeepsForm;
var
  mPlan: TDpccFormSyncPlan;
  mJob, mDummy: TDpccFormSyncJob;
  mDone: TDpccFormSyncDone;
begin
  mPlan := TDpccFormSyncPlan.Create;
  try
    mPlan.Offer(cFile, Bytes('eins'), mJob);
    Assert.IsFalse(mPlan.Close(cFile));
    Assert.IsTrue(mPlan.Offer(cFile, Bytes('zwei'), mDummy) = TDpccFormOffer.Queued);
    mDone := mPlan.Finished(mJob, True);
    Assert.AreEqual('', mDone.CloseFile);
    Assert.IsTrue(mDone.HasNext);
    Assert.AreEqual('zwei', TEncoding.UTF8.GetString(mDone.Next.Binary));
  finally
    mPlan.Free;
  end;
end;

procedure TDpccFormSyncTests.MaxRunningQueuesOthers;
var
  mPlan: TDpccFormSyncPlan;
  mA, mB, mC: TDpccFormSyncJob;
  mDone: TDpccFormSyncDone;
begin
  mPlan := TDpccFormSyncPlan.Create(2);
  try
    Assert.IsTrue(mPlan.Offer(cFile, Bytes('a'), mA) = TDpccFormOffer.Start);
    Assert.IsTrue(mPlan.Offer(cOther, Bytes('b'), mB) = TDpccFormOffer.Start);
    Assert.IsTrue(mPlan.Offer(cThird, Bytes('c'), mC) = TDpccFormOffer.Queued);
    Assert.AreEqual(2, mPlan.Running);
    mDone := mPlan.Finished(mA, True);
    Assert.IsTrue(mDone.HasNext);
    Assert.AreEqual(cThird, mDone.Next.FileName);
    Assert.AreEqual(2, mPlan.Running);
    Assert.IsFalse(mPlan.Finished(mB, True).HasNext);
    Assert.IsFalse(mPlan.Finished(mDone.Next, True).HasNext);
    Assert.AreEqual(0, mPlan.Running);
  finally
    mPlan.Free;
  end;
end;

procedure TDpccFormSyncTests.FailedRunIsResent;
var
  mPlan: TDpccFormSyncPlan;
  mJob: TDpccFormSyncJob;
begin
  mPlan := TDpccFormSyncPlan.Create;
  try
    mPlan.Offer(cFile, Bytes('eins'), mJob);
    Assert.IsFalse(mPlan.Finished(mJob, False).Accepted);
    Assert.IsTrue(mPlan.Offer(cFile, Bytes('eins'), mJob) = TDpccFormOffer.Start);
  finally
    mPlan.Free;
  end;
end;

procedure TDpccFormSyncTests.TickTakesLargeFormsAlone;
const
  cLarge = 1000;
begin
  Assert.AreEqual(0, TDpccFormSyncPlan.TickCount(nil, 2, cLarge));
  Assert.AreEqual(2, TDpccFormSyncPlan.TickCount(TArray<Int64>.Create(10, 20, 30), 2, cLarge));
  Assert.AreEqual(3, TDpccFormSyncPlan.TickCount(TArray<Int64>.Create(10, 20, 30), 5, cLarge));
  // Großes vorne: allein; großes dahinter: erst im nächsten Takt.
  Assert.AreEqual(1, TDpccFormSyncPlan.TickCount(TArray<Int64>.Create(5000, 20), 2, cLarge));
  Assert.AreEqual(1, TDpccFormSyncPlan.TickCount(TArray<Int64>.Create(10, 5000), 2, cLarge));
  // Noch nie gemessen zählt als groß.
  Assert.AreEqual(1, TDpccFormSyncPlan.TickCount(TArray<Int64>.Create(0, 20), 2, cLarge));
  Assert.AreEqual(1, TDpccFormSyncPlan.TickCount(TArray<Int64>.Create(10, 20), 0, cLarge));
  Assert.IsTrue(TDpccFormSyncPlan.IsLarge(0, cLarge));
  Assert.IsTrue(TDpccFormSyncPlan.IsLarge(cLarge, cLarge));
  Assert.IsFalse(TDpccFormSyncPlan.IsLarge(cLarge - 1, cLarge));
end;

procedure TDpccFormSyncTests.LastSizeSurvivesReset;
var
  mPlan: TDpccFormSyncPlan;
  mJob: TDpccFormSyncJob;
begin
  mPlan := TDpccFormSyncPlan.Create;
  try
    Assert.IsTrue(mPlan.LastSize(cFile) = 0);
    mPlan.Offer(cFile, Bytes('vier'), mJob);
    Assert.IsTrue(mPlan.LastSize(cFile) = 4);
    mPlan.Reset;
    Assert.IsTrue(mPlan.LastSize(cFile) = 4);
    mPlan.Close(cFile);
    Assert.IsTrue(mPlan.LastSize(cFile) = 0);
  finally
    mPlan.Free;
  end;
end;

procedure TDpccFormSyncTests.SavedSourcesFromModuleName;
var
  mFiles: TArray<string>;
begin
  mFiles := TDpccModuleSources.SavedSources('C:\P\Haupt.pas');
  Assert.AreEqual(1, Integer(Length(mFiles)));
  Assert.AreEqual('C:\P\Haupt.pas', mFiles[0]);
  mFiles := TDpccModuleSources.SavedSources('C:\P\Projekt.dproj');
  Assert.AreEqual(2, Integer(Length(mFiles)));
  Assert.AreEqual('C:\P\Projekt.dpr', mFiles[0]);
  Assert.AreEqual('C:\P\Projekt.dpk', mFiles[1]);
  mFiles := TDpccModuleSources.SavedSources('C:\P\Haupt.dfm');
  Assert.AreEqual(1, Integer(Length(mFiles)));
  Assert.AreEqual('C:\P\Haupt.pas', mFiles[0]);
  Assert.AreEqual(0, Integer(Length(TDpccModuleSources.SavedSources(''))));
end;

procedure TDpccFormSyncTests.BinaryAndTextAgree;
var
  mRoot: TComponent;
  mBinary, mAgain: TBytes;
  mText: string;
begin
  mRoot := TComponent.Create(nil);
  try
    mRoot.Name := 'Haupt';
    mBinary := TDpccFormText.WriteBinary(mRoot, nil);
    Assert.IsTrue(Length(mBinary) > 0);
    mText := TDpccFormText.BinaryToText(mBinary);
    Assert.AreEqual(TDpccFormText.Write(mRoot, nil), mText);
    Assert.IsTrue(mText.Contains('Haupt'));
    mAgain := TDpccFormText.WriteBinary(mRoot, nil);
    Assert.IsTrue(TDpccFormFingerprint.FromBinary(mBinary).SameAs(TDpccFormFingerprint.FromBinary(mAgain)));
    mRoot.Tag := 7;
    mAgain := TDpccFormText.WriteBinary(mRoot, nil);
    Assert.IsFalse(TDpccFormFingerprint.FromBinary(mBinary).SameAs(TDpccFormFingerprint.FromBinary(mAgain)));
    Assert.AreEqual('', TDpccFormText.BinaryToText(nil));
  finally
    mRoot.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccFormSyncTests);

end.
