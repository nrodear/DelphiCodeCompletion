unit dpcc.Core.Completion.Width.Tests;

// Tests für die Breite des Vervollständigungs-Popups (#416, #415): Grenzen,
// nur wachsen, gezogene Breite vor der Automatik, Grenzen des Panels.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccPopupWidthTests = class
  public
    [Test]
    procedure FitsIntoLimits;
    [Test]
    procedure LongSignatureFitsWithinMaxWidth;
    [Test]
    procedure GrowsButNeverShrinks;
    [Test]
    procedure ManualWidthWins;
    [Test]
    procedure PanelHasOwnLimits;
  end;

implementation

uses
  dpcc.Core.Completion.Width;

{ TDpccPopupWidthTests }

procedure TDpccPopupWidthTests.FitsIntoLimits;
begin
  Assert.AreEqual(TDpccPopupWidth.cMinListWidth, TDpccPopupWidth.Fit(100, TDpccPopupWidth.cMinListWidth,
    TDpccPopupWidth.cMaxListWidth));
  Assert.AreEqual(TDpccPopupWidth.cMaxListWidth, TDpccPopupWidth.Fit(5000, TDpccPopupWidth.cMinListWidth,
    TDpccPopupWidth.cMaxListWidth));
  Assert.AreEqual(400, TDpccPopupWidth.Fit(400, TDpccPopupWidth.cMinListWidth, TDpccPopupWidth.cMaxListWidth));
end;

procedure TDpccPopupWidthTests.LongSignatureFitsWithinMaxWidth;
const
  // 60 Zeichen Signatur bei 7 px je Zeichen, Name, Badge und Ränder.
  Measured = 60 * 7 + 120 + 47 + 30;
begin
  Assert.AreEqual(Measured, TDpccPopupWidth.Fit(Measured, TDpccPopupWidth.cMinListWidth,
    TDpccPopupWidth.cMaxListWidth), 'Ohne Kürzung, solange MaxWidth reicht');
end;

procedure TDpccPopupWidthTests.GrowsButNeverShrinks;
var
  Session: Integer;
begin
  // Filtern von "A" (breite Einträge) zu "Add" (schmale): die Breite bleibt.
  Session := TDpccPopupWidth.Grow(0, 520);
  Session := TDpccPopupWidth.Grow(Session, 310);
  Assert.AreEqual(520, Session);
  Session := TDpccPopupWidth.Grow(Session, 610);
  Assert.AreEqual(610, Session);
end;

procedure TDpccPopupWidthTests.ManualWidthWins;
begin
  Assert.AreEqual(450, TDpccPopupWidth.Effective(450, 610));
  // Doppelklick auf den Griff setzt die gezogene Breite auf 0: wieder automatisch.
  Assert.AreEqual(610, TDpccPopupWidth.Effective(0, 610));
end;

procedure TDpccPopupWidthTests.PanelHasOwnLimits;
var
  PanelMin, ListMin: Integer;
begin
  // Gezogene Panelbreite (#416): eigene Grenzen, unabhängig von der Liste.
  Assert.AreEqual(TDpccPopupWidth.cMaxPanelWidth, TDpccPopupWidth.Fit(900, TDpccPopupWidth.cMinPanelWidth,
    TDpccPopupWidth.cMaxPanelWidth));
  Assert.AreEqual(TDpccPopupWidth.cMinPanelWidth, TDpccPopupWidth.Fit(100, TDpccPopupWidth.cMinPanelWidth,
    TDpccPopupWidth.cMaxPanelWidth));
  // Über Variablen: Der Vergleich der Konstanten selbst ergibt W1022.
  PanelMin := TDpccPopupWidth.cMinPanelWidth;
  ListMin := TDpccPopupWidth.cMinListWidth;
  Assert.IsTrue(PanelMin < ListMin);
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccPopupWidthTests);

end.
