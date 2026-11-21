unit dpcc.UI.Popup.Tip;

// Kleiner Tooltip im dpcc-Stil (#420): zeigt den vollständigen Text eines
// gekürzten Eintrags. Ohne Fokus wie alle dpcc-Fenster, eine Zeile in der
// Editorschrift, höchstens so breit wie der Arbeitsbereich des Monitors.
// Seit S8 flach wie der Hover-Tooltip: eckig, 1 px Rand, Farben der Liste (ListColors). Text auf der Fläche in
// allen Stufen (LOOK1); nur der Rand folgt der Stufe (FrameColor). Wer Colors setzt, gibt auch LookLevel des
// Elternfensters mit (die Liste in TipTimer).

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  dpcc.UI.Popup.Window;

type
  TDpccTextTip = class(TDpccPopupWindow)
  private
    FText: string;
  protected
    procedure Paint; override;
  public
    /// <summary>Zeigt AText mit der linken oberen Ecke an APoint (Bildschirmkoordinaten).</summary>
    procedure ShowText(const AText: string; const APoint: TPoint);
    property Text: string read FText;
  end;

implementation

uses
  System.Math;

{ TDpccTextTip }

procedure TDpccTextTip.ShowText(const AText: string; const APoint: TPoint);
var
  mArea, mBounds: TRect;
  mWidth, mHeight: Integer;
begin
  FText := AText;
  Canvas.Font := Font;
  mArea := WorkAreaAt(APoint);
  mWidth := Min(Canvas.TextWidth(AText) + Scale(18), mArea.Width);
  mHeight := Canvas.TextHeight('Wg') + Scale(10);
  mBounds := TRect.Create(APoint, mWidth, mHeight);
  if mBounds.Right > mArea.Right then
  begin
    mBounds.SetLocation(Max(mArea.Left, mArea.Right - mWidth), mBounds.Top);
  end;
  if mBounds.Bottom > mArea.Bottom then
  begin
    mBounds.SetLocation(mBounds.Left, mArea.Bottom - mHeight);
  end;
  ShowAt(mBounds);
  Invalidate;
end;

procedure TDpccTextTip.Paint;
var
  mText: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font := Font;
  Canvas.Font.Color := ToColor(Colors.Text);
  Canvas.Brush.Style := bsClear;
  mText := Rect(Scale(9), 0, ClientWidth - Scale(9), ClientHeight);
  DrawText(Canvas.Handle, PChar(FText), -1, mText, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
  PaintBorder;
end;

end.
