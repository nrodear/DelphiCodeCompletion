unit dpcc.UI.Popup.Draw;

// Gemeinsame Zeichenbausteine der Popups: Farbumwandlung, Maße der
// Chips und Tags (einheitlich Innenabstand 12, Radius 4 in logischen Pixeln),
// Daumen der Scrollleisten (Muted über Fläche, DpccMixThumb) und Trennlinie.
// Bisher hatte jedes Fenster eigene Kopien mit leicht abweichenden Werten.

interface

uses
  System.Types,
  Vcl.Graphics,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette;

type
  TDpccDraw = class
  public const
    /// <summary>Eckenradius (logische Pixel) für die Warnleiste der Liste.</summary>
    cChipRadius = cDpccChipRadius;
  public
    /// <summary>Farbe des Scroll-Daumens.</summary>
    class function ThumbColor(const AColors: TDpccColors): TDpccColor; static;
    /// <summary>Daumen einer Scrollleiste in ARect; ARadius in Gerätepixeln, 0 = eckig.</summary>
    class procedure Thumb(ACanvas: TCanvas; const ARect: TRect; const AColors: TDpccColors;
      ARadius: Integer); static;
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

class procedure TDpccDraw.Thumb(ACanvas: TCanvas; const ARect: TRect; const AColors: TDpccColors;
  ARadius: Integer);
begin
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := ToColor(ThumbColor(AColors));
  if ARadius <= 0 then
  begin
    ACanvas.FillRect(ARect);
    Exit;
  end;
  ACanvas.Pen.Style := psClear;
  // Bei psClear zeichnet RoundRect ein Pixel kleiner; deshalb +1.
  ACanvas.RoundRect(ARect.Left, ARect.Top, ARect.Right + 1, ARect.Bottom + 1, 2 * ARadius, 2 * ARadius);
  ACanvas.Pen.Style := psSolid;
end;

class procedure TDpccDraw.Separator(ACanvas: TCanvas; ALeft, ARight, AY: Integer; AColor: TDpccColor);
begin
  ACanvas.Pen.Style := psSolid;
  ACanvas.Pen.Color := ToColor(AColor);
  ACanvas.MoveTo(ALeft, AY);
  ACanvas.LineTo(ARight, AY);
end;

end.
