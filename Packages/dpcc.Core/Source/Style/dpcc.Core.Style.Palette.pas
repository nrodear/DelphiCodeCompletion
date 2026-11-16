unit dpcc.Core.Style.Palette;

// Farbrollen von dpcc (#411, #421) nach dem Entwurf "dpcc-Oberfläche":
// fester Akzent in griechischem Blau, alles andere je nach Hell- oder
// Dunkelmodus. Die Oberfläche verwendet nur diese Rollen, keine fest
// verdrahteten Farben.
// Seit S8 sind alle Fenster flach wie der Hover-Tooltip und nehmen die Farben des
// Editors (TDpccIdeStyle.ListColors auf Grundlage von ForWindow). Abgesetzte
// Flächen (Gutter, *Soft), Paarfarben, lokale Routinen, Zustandspunkte und
// Inlay-Marken gibt es nicht mehr.

interface

uses
  dpcc.Core.Style.Color;

type
  /// <summary>Farben der Klammer- und Blockpaare je Tiefe (Format der Einstellung highlight.pairColors, #514).
  /// </summary>
  TDpccPairColors = array[0..4] of TDpccColor;

  /// <summary>Farben der Platzhalter von Format und ihrer Argumente (#451), zyklisch.</summary>
  TDpccPlaceholderColors = array[0..5] of TDpccColor;

  TDpccColors = record
    IsDark: Boolean;
    /// <summary>Fläche der Fenster.</summary>
    Surface: TDpccColor;
    Text: TDpccColor;
    /// <summary>Gedämpfter Text: Signaturen, Units, Beschreibungen, Art-Kennung, Überschriften.</summary>
    Muted: TDpccColor;
    /// <summary>Rand der Fenster, Trennlinien, Scrollleiste.</summary>
    Line: TDpccColor;
    /// <summary>Verweise und Links (blau), Aktionen in der Liste, Platzhalterzeile im Parameter-Hint.</summary>
    Accent: TDpccColor;
    /// <summary>Gewählte Zeile bzw. Überladung, Markierung in der Doku.</summary>
    Selection: TDpccColor;
    Keyword: TDpccColor;
    StringLiteral: TDpccColor;
    Comment: TDpccColor;
    Warn: TDpccColor;
    Error: TDpccColor;
    /// <summary>Platzhalter von Format und ihre Argumente (#451), halb durchsichtig über dem Text.</summary>
    Placeholders: TDpccPlaceholderColors;
    /// <summary>Art-Kennung („unit“, „procedure“, „type“) in Hover und Vervollständigungsliste: gedämpft wie der
    /// übrige Nebentext (S8), nicht in der Farbe der reservierten Wörter.</summary>
    function KindLabel: TDpccColor;
    /// <summary>True, wenn AText genau eine Farbe „#RRGGBB“ ist; AColor erhält sie (#1788).</summary>
    class function ParseColor(const AText: string; out AColor: TDpccColor): Boolean; static;
    /// <summary>„#RRGGBB,…“ mit genau fünf Farben in Reihenfolge der Tiefe.</summary>
    class function ParsePairs(const AText: string; out APairs: TDpccPairColors): Boolean; static;
    class function PairsText(const APairs: TDpccPairColors): string; static;
    class function Light: TDpccColors; static;
    class function Dark: TDpccColors; static;
    /// <summary>Light oder Dark, je nachdem ob ABackground (Fensterfarbe der IDE) dunkel ist.</summary>
    class function ForBackground(ABackground: TDpccColor): TDpccColors; static;
    /// <summary>Farben für Fenster auf der Fläche AWindow mit Text AText (Farbschema des Editors bzw. IDE-Thema):
    /// Gedämpftes, Linien und Auswahl daraus gemischt, Akzent und Syntaxfarben wie ForBackground(AWindow).
    /// </summary>
    class function ForWindow(AWindow, AText: TDpccColor): TDpccColors; static;
  end;

const
  /// <summary>Daumen der Scrollleisten: Anteil von Muted über der Fläche.</summary>
  cDpccMixThumb = 0.5;
  /// <summary>ForWindow: Anteile des Textes über der Fläche für gedämpften Text und Linien.</summary>
  cDpccMixWindowMuted = 0.7;
  cDpccMixWindowLine = 0.18;

implementation

uses
  System.SysUtils;

function Hex(const AHex: string): TDpccColor;
begin
  Result := TDpccColorMath.FromHex(AHex);
end;

{ TDpccColors }

class function TDpccColors.Light: TDpccColors;
begin
  Result := Default(TDpccColors);
  Result.IsDark := False;
  Result.Surface := Hex('#FFFFFF');
  Result.Text := Hex('#1B2230');
  Result.Muted := Hex('#586274');
  Result.Line := Hex('#DCE2EA');
  Result.Accent := Hex('#0D5EAF');
  Result.Selection := TDpccColorMath.Mix(Result.Accent, Result.Surface, 0.12);
  Result.Keyword := Hex('#0D5EAF');
  Result.StringLiteral := Hex('#8A4A0B');
  Result.Comment := Hex('#6A7384');
  Result.Warn := Hex('#9A5B00');
  Result.Error := Hex('#B42318');
  // Sechs deutlich verschiedene Töne für die Platzhalter (#451); Rot fehlt, es bleibt den Fehlern.
  Result.Placeholders[0] := Hex('#0071E3');
  Result.Placeholders[1] := Hex('#D86A00');
  Result.Placeholders[2] := Hex('#008700');
  Result.Placeholders[3] := Hex('#C000E0');
  Result.Placeholders[4] := Hex('#007C8A');
  Result.Placeholders[5] := Hex('#A08000');
end;

class function TDpccColors.Dark: TDpccColors;
begin
  Result := Default(TDpccColors);
  Result.IsDark := True;
  Result.Surface := Hex('#1A1E25');
  Result.Text := Hex('#E3E7ED');
  Result.Muted := Hex('#9AA3B2');
  Result.Line := Hex('#2B313B');
  Result.Accent := Hex('#5B9BE6');
  // 15 % statt 18 % wie im Entwurf: sonst hat der Akzent darauf weniger als 4,5 : 1.
  Result.Selection := TDpccColorMath.Mix(Result.Accent, Result.Surface, 0.15);
  Result.Keyword := Hex('#7FB0EE');
  Result.StringLiteral := Hex('#E3B27A');
  Result.Comment := Hex('#8A93A3');
  Result.Warn := Hex('#F0C06A');
  Result.Error := Hex('#F59A8F');
  Result.Placeholders[0] := Hex('#3C94FF');
  Result.Placeholders[1] := Hex('#FF9A3D');
  Result.Placeholders[2] := Hex('#24AA24');
  Result.Placeholders[3] := Hex('#E250FF');
  Result.Placeholders[4] := Hex('#00A4A4');
  Result.Placeholders[5] := Hex('#D6B020');
end;

function TDpccColors.KindLabel: TDpccColor;
begin
  Result := Muted;
end;

class function TDpccColors.ParseColor(const AText: string; out AColor: TDpccColor): Boolean;
var
  mText: string;
begin
  Result := False;
  AColor := 0;
  mText := Trim(AText);
  if (Length(mText) <> 7) or (mText[1] <> '#') then
  begin
    Exit;
  end;
  try
    AColor := Hex(mText);
  except
    on EConvertError do
      Exit;
  end;
  Result := True;
end;

class function TDpccColors.ParsePairs(const AText: string; out APairs: TDpccPairColors): Boolean;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  Result := False;
  mParts := AText.Split([',']);
  if Length(mParts) <> Length(APairs) then
  begin
    Exit;
  end;
  try
    for mIndex := 0 to High(mParts) do
    begin
      APairs[mIndex] := Hex(Trim(mParts[mIndex]));
    end;
  except
    on EConvertError do
      Exit;
  end;
  Result := True;
end;

class function TDpccColors.PairsText(const APairs: TDpccPairColors): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(APairs) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + TDpccColorMath.ToHex(APairs[mIndex]);
  end;
end;

class function TDpccColors.ForBackground(ABackground: TDpccColor): TDpccColors;
begin
  if TDpccColorMath.IsDark(ABackground) then
  begin
    Result := Dark;
  end
  else
  begin
    Result := Light;
  end;
end;

class function TDpccColors.ForWindow(AWindow, AText: TDpccColor): TDpccColors;
begin
  Result := ForBackground(AWindow);
  Result.Surface := AWindow;
  Result.Text := AText;
  Result.Muted := TDpccColorMath.Mix(AText, AWindow, cDpccMixWindowMuted);
  Result.Line := TDpccColorMath.Mix(AText, AWindow, cDpccMixWindowLine);
  if Result.IsDark then
  begin
    Result.Selection := TDpccColorMath.Mix(Result.Accent, AWindow, 0.25);
  end
  else
  begin
    Result.Selection := TDpccColorMath.Mix(Result.Accent, AWindow, 0.15);
  end;
end;

end.
