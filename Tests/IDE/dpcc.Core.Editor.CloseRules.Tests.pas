unit dpcc.Core.Editor.CloseRules.Tests;

// Tests für die Regel „anderes Popup offen“ (S3c, TDpccCloseRules.OtherPopup): Solange über dem Editor die Liste
// der Vervollständigung, ein Parameter-Hint oder ein Menü offen ist, erscheint kein Hover-Tooltip, und ein offener
// schließt. Nicht mit: der Tooltip selbst, unsichtbare und leere Fenster, Fenster mit Titelleiste (IDE, schwebende
// Fenster), Fenster neben dem Editor, Schatten, IME und Kurzhinweise der Werkzeugleisten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccOtherPopupTests = class
  public
    [Test]
    procedure CompletionListOverEditorBlocks;
    [Test]
    procedure OwnTipAndIdeWindowsDoNotBlock;
    [Test]
    procedure IgnoredClassesAndOutsideDoNotBlock;
  end;

implementation

uses
  System.Types,
  dpcc.Core.Editor.CloseRules;

const
  cOwn = 100;
  cPopup = TDpccCloseRules.cWsPopup;
  cCaption = TDpccCloseRules.cWsCaption;

function Editor: TRect;
begin
  Result := Rect(0, 100, 1200, 900);
end;

function Win(AHandle: NativeUInt; AStyle: Cardinal; const AClassName: string; AVisible: Boolean;
  const ABounds: TRect): TDpccTopWindow;
begin
  Result := TDpccTopWindow.Create(AHandle, AStyle, AClassName, AVisible, ABounds);
end;

{ TDpccOtherPopupTests }

procedure TDpccOtherPopupTests.CompletionListOverEditorBlocks;
begin
  // Liste der IDE bzw. von dpcc (WS_POPUP ohne Titel) über dem Editor.
  Assert.IsTrue(TDpccCloseRules.OtherPopup([Win(1, cPopup, 'TCodeCompleteListView', True, Rect(170, 60, 650, 340))],
    cOwn, Editor));
  Assert.IsTrue(TDpccCloseRules.OtherPopup([Win(2, cPopup, 'TDpccCompletionPopup', True, Rect(300, 300, 700, 600))],
    cOwn, Editor));
  // Kontextmenü.
  Assert.IsTrue(TDpccCloseRules.OtherPopup([Win(3, cPopup, '#32768', True, Rect(400, 400, 600, 700))], cOwn,
    Editor));
end;

procedure TDpccOtherPopupTests.OwnTipAndIdeWindowsDoNotBlock;
begin
  // Der Tooltip selbst, die IDE (Titelleiste), das unsichtbare bzw. leere Fenster der Anwendung.
  Assert.IsFalse(TDpccCloseRules.OtherPopup([
    Win(cOwn, cPopup, 'TDpccHoverTip', True, Rect(50, 80, 500, 300)),
    Win(4, cCaption, 'TAppBuilder', True, Rect(-10, 0, 1300, 1000)),
    Win(5, cPopup or cCaption, 'TApplication', True, Rect(600, 500, 600, 500)),
    Win(6, cPopup, 'TDpccSignatureHint', False, Rect(100, 100, 300, 200))], cOwn, Editor));
  Assert.IsFalse(TDpccCloseRules.OtherPopup(nil, cOwn, Editor));
end;

procedure TDpccOtherPopupTests.IgnoredClassesAndOutsideDoNotBlock;
begin
  // Schatten (auch der des Tooltips), Eingabemethoden, Kurzhinweise; ein Popup auf einem anderen Bildschirmteil.
  Assert.IsFalse(TDpccCloseRules.OtherPopup([
    Win(7, cPopup, 'SysShadow', True, Rect(55, 85, 505, 305)),
    Win(8, cPopup, 'IME', True, Rect(0, 100, 10, 110)),
    Win(9, cPopup, 'MSCTFIME UI', True, Rect(0, 100, 10, 110)),
    Win(10, cPopup, 'tooltips_class32', True, Rect(10, 120, 200, 140)),
    Win(11, cPopup, 'TDpccNotificationsWindow', True, Rect(1500, 900, 1800, 1000))], cOwn, Editor));
  // Fenster ohne WS_POPUP (eigenständiges Werkzeugfenster) zählt nicht.
  Assert.IsFalse(TDpccCloseRules.OtherPopup([Win(12, 0, 'TFloatingForm', True, Rect(100, 200, 400, 500))], cOwn,
    Editor));
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccOtherPopupTests);

end.
