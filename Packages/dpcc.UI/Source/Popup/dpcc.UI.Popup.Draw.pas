unit dpcc.UI.Popup.Draw;

// Gemeinsame Zeichenbausteine der Popups: Farbumwandlung, Daumen der
// Scrollleisten (Muted über Fläche, DpccMixThumb, eckig) und Trennlinie.
// Seit S8 ist alles flach und eckig wie im Hover-Tooltip; Radien gibt es nicht mehr.

interface

uses
  System.Types,
  Vcl.Graphics,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette;

type
  TDpccDraw = class
  public
    /// <summary>Farbe des Scroll-Daumens.</summary>
    class function ThumbColor(const AColors: TDpccColors): TDpccColor; static;
    /// <summary>Daumen einer Scrollleiste in ARect, eckig.</summary>
    class procedure Thumb(ACanvas: TCanvas; const ARect: TRect; const AColors: TDpccColors); static;
    /// <summary>Waagrechte Trennlinie von ALeft bis ARight auf Höhe AY.</summary>
    class procedure Separator(ACanvas: TCanvas; ALeft, ARight, AY: Integer; AColor: TDpccColor); static;
  end;

/// <summary>TColor zur dpcc-Farbe (gleiches Format); eine Stelle für alle Popups.</summary>
function ToColor(AColor: TDpccColor): TColor;

implementation

function ToColor(AColor: TDpccColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TDpccDraw }

class function TDpccDraw.ThumbColor(const AColors: TDpccColors): TDpccColor;
begin
  Result := TDpccColorMath.Mix(AColors.Muted, AColors.Surface, cDpccMixThumb);
end;

class procedure TDpccDraw.Thumb(ACanvas: TCanvas; const ARect: TRect; const AColors: TDpccColors);
begin
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := ToColor(ThumbColor(AColors));
  ACanvas.FillRect(ARect);
end;

class procedure TDpccDraw.Separator(ACanvas: TCanvas; ALeft, ARight, AY: Integer; AColor: TDpccColor);
begin
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Color := ToColor(AColor);
  ACanvas.MoveTo(ALeft, AY);
  ACanvas.LineTo(ARight, AY);
end;

end.
