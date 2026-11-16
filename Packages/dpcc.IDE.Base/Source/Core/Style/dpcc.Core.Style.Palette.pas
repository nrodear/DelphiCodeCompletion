unit dpcc.Core.Style.Palette;

// Farbrollen von dpcc (#411, #421) nach dem Entwurf "dpcc-Oberfläche":
// fester Akzent in griechischem Blau, alles andere je nach Hell- oder
// Dunkelmodus. Auswahl und Flächen ergeben sich wie im Entwurf durch Mischen
// des Akzents mit dem Hintergrund. Die Oberfläche verwendet nur diese Rollen,
// keine fest verdrahteten Farben.

interface

uses
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Signal;

type
  /// <summary>Art eines Badges in der Liste (#421); bestimmt dessen Farben.</summary>
  TDpccBadgeKind = (Function_, Procedure_, Property_, Field, Event, Constant, Type_, Variable, Unit_, Snippet,
    Keyword, XmlDoc);

  TDpccBadgeColors = record
    Background: TDpccColor;
    Text: TDpccColor;
  end;

  /// <summary>Farben der Klammer- und Blockpaare je Tiefe, zyklisch (#514).</summary>
  TDpccPairColors = array[0..4] of TDpccColor;

  /// <summary>Farben der Platzhalter von Format und ihrer Argumente (#451), zyklisch.</summary>
  TDpccPlaceholderColors = array[0..5] of TDpccColor;

  /// <summary>Farben einer Inlay-Hint-Marke: aus dem Editorhintergrund gemischt.</summary>
  TDpccHintColors = record
    Text: TDpccColor;
    Pen: TDpccColor;
    Fill: TDpccColor;
  end;

  TDpccColors = record
    IsDark: Boolean;
    /// <summary>Fläche der Fenster.</summary>
    Surface: TDpccColor;
    /// <summary>Abgesetzte Fläche: Fußzeile, Detailpanel, Doku-Zeile im Hint.</summary>
    Gutter: TDpccColor;
    Text: TDpccColor;
    /// <summary>Gedämpfter Text: Signaturen, Units, Beschreibungen.</summary>
    Muted: TDpccColor;
    /// <summary>Trennlinien, Ränder der Tags, Scrollleiste.</summary>
    Line: TDpccColor;
    /// <summary>Rahmen der Fenster, getroffene Zeichen, aktiver Parameter.</summary>
    Accent: TDpccColor;
    AccentSoft: TDpccColor;
    /// <summary>Gewählte Zeile: Akzent zu 12 % (hell) bzw. 15 % (dunkel) über Surface.</summary>
    Selection: TDpccColor;
    Keyword: TDpccColor;
    StringLiteral: TDpccColor;
    Comment: TDpccColor;
    Add: TDpccColor;
    AddSoft: TDpccColor;
    Warn: TDpccColor;
    WarnSoft: TDpccColor;
    Error: TDpccColor;
    ErrorSoft: TDpccColor;
    Badges: array[TDpccBadgeKind] of TDpccBadgeColors;
    /// <summary>Klammer- und Blockpaare je Tiefe, zyklisch (#514).</summary>
    Pairs: TDpccPairColors;
    /// <summary>Eigene Farbe lokaler Routinen (#1788, highlight.nestedRoutines = color).</summary>
    NestedRoutine: TDpccColor;
    /// <summary>Platzhalter von Format und ihre Argumente (#451), halb durchsichtig über dem Text.</summary>
    Placeholders: TDpccPlaceholderColors;
    /// <summary>Zustandspunkte, Plaketten und Befundsymbole (#1255); nicht Add/Warn/Error, die für Text gedacht
    /// sind.</summary>
    Signals: TDpccSignals;
    /// <summary>Eigene Paarfarben aus den Einstellungen: leer oder ungültig = Palette.</summary>
    function WithPairs(const ACustom: string): TDpccColors;
    /// <summary>Eigene Farbe lokaler Routinen aus den Einstellungen (#1788): „#RRGGBB“; leer oder ungültig =
    /// Palette.</summary>
    function WithNestedRoutine(const ACustom: string): TDpccColors;
    /// <summary>True, wenn AText genau eine Farbe „#RRGGBB“ ist; AColor erhält sie (#1788).</summary>
    class function ParseColor(const AText: string; out AColor: TDpccColor): Boolean; static;
    /// <summary>„#RRGGBB,…“ mit genau fünf Farben in Reihenfolge der Tiefe.</summary>
    class function ParsePairs(const AText: string; out APairs: TDpccPairColors): Boolean; static;
    class function PairsText(const APairs: TDpccPairColors): string; static;
    class function Light: TDpccColors; static;
    class function Dark: TDpccColors; static;
    /// <summary>Light oder Dark, je nachdem ob ABackground (Fensterfarbe der IDE) dunkel ist.</summary>
    class function ForBackground(ABackground: TDpccColor): TDpccColors; static;
    /// <summary>Farben für Leisten im Rahmen der IDE (Brotkrumenleiste): Fläche AFace und Text AText aus dem
    /// IDE-Thema, Gedämpftes, Linien und Auswahl daraus gemischt; Badges und Akzent wie ForBackground(AFace).</summary>
    class function ForChrome(AFace, AText: TDpccColor): TDpccColors; static;
    /// <summary>Farben für andockbare Fenster mit Inhalt (Issue, Board): Fläche AWindow und Text AText aus dem
    /// IDE-Thema (clWindow/clWindowText) wie ForChrome; Gutter leicht zum Text hin abgesetzt, damit Spalten und
    /// Abzeichen sich von der Fläche abheben.</summary>
    class function ForWindow(AWindow, AText: TDpccColor): TDpccColors; static;
    /// <summary>Farben der Inlay-Hint-Marken auf dem Editorhintergrund ABack: Text deutlich
    /// lesbar, Fläche leicht im Akzent abgesetzt.</summary>
    class function InlayHint(ABack: TDpccColor): TDpccHintColors; static;
  end;

const
  /// <summary>Blasse Probleme (Text seither geändert): Anteil der Schweregradfarbe über der Fläche,
  /// gleich in Editor und Hover.</summary>
  cDpccMixFaded = 0.55;
  /// <summary>Daumen der Scrollleisten: Anteil von Muted über der Fläche.</summary>
  cDpccMixThumb = 0.5;
  /// <summary>Inlay-Hint-Marken: Anteile von Text bzw. Akzent über dem Editorhintergrund.</summary>
  cDpccMixInlayText = 0.8;
  cDpccMixInlayPen = 0.45;
  cDpccMixInlayFill = 0.2;
  /// <summary>Leisten im Rahmen der IDE: Anteile des Textes über der Fläche für gedämpften Text und Linien.</summary>
  cDpccMixChromeMuted = 0.7;
  cDpccMixChromeLine = 0.18;
  /// <summary>Fenster im Rahmen der IDE: Anteil des Textes über der Fläche für Gutter (Spalten, Abzeichen).</summary>
  cDpccMixWindowGutter = 0.06;
  /// <summary>Chips und Tags: Innenabstand links und rechts zusammen und Eckenradius, logische Pixel.</summary>
  cDpccChipPad = 12;
  cDpccChipRadius = 4;

implementation

uses
  System.SysUtils;

function Hex(const AHex: string): TDpccColor;
begin
  Result := TDpccColorMath.FromHex(AHex);
end;

function Badge(const ABackground, AText: string): TDpccBadgeColors;
begin
  Result.Background := Hex(ABackground);
  Result.Text := Hex(AText);
end;

{ TDpccColors }

class function TDpccColors.Light: TDpccColors;
begin
  Result := Default(TDpccColors);
  Result.IsDark := False;
  Result.Surface := Hex('#FFFFFF');
  Result.Gutter := Hex('#F3F5F8');
  Result.Text := Hex('#1B2230');
  Result.Muted := Hex('#586274');
  Result.Line := Hex('#DCE2EA');
  Result.Accent := Hex('#0D5EAF');
  Result.AccentSoft := Hex('#E3EEF9');
  Result.Selection := TDpccColorMath.Mix(Result.Accent, Result.Surface, 0.12);
  Result.Keyword := Hex('#0D5EAF');
  Result.StringLiteral := Hex('#8A4A0B');
  Result.Comment := Hex('#6A7384');
  Result.Add := Hex('#1E6B3A');
  Result.AddSoft := Hex('#E3F3E8');
  Result.Warn := Hex('#9A5B00');
  Result.WarnSoft := Hex('#FDF1DC');
  Result.Error := Hex('#B42318');
  Result.ErrorSoft := Hex('#FDE8E6');
  Result.Badges[TDpccBadgeKind.Function_] := Badge('#E3EEF9', '#0D4C8C');
  Result.Badges[TDpccBadgeKind.Procedure_] := Badge('#E6F0EC', '#24634B');
  Result.Badges[TDpccBadgeKind.Property_] := Badge('#FCEBDD', '#9A3412');
  Result.Badges[TDpccBadgeKind.Field] := Badge('#E7F1F3', '#245A66');
  Result.Badges[TDpccBadgeKind.Event] := Badge('#F1E8FA', '#6B2FA0');
  Result.Badges[TDpccBadgeKind.Constant] := Badge('#FBF3D6', '#7A5A00');
  Result.Badges[TDpccBadgeKind.Type_] := Badge('#CCDDF2', '#0A3F75');
  Result.Badges[TDpccBadgeKind.Variable] := Badge('#E7F1F3', '#245A66');
  Result.Badges[TDpccBadgeKind.Unit_] := Badge('#ECEFF3', '#3E4756');
  Result.Badges[TDpccBadgeKind.Snippet] := Badge('#ECEFF3', '#3E4756');
  Result.Badges[TDpccBadgeKind.Keyword] := Badge('#ECEFF3', '#3E4756');
  Result.Badges[TDpccBadgeKind.XmlDoc] := Badge('#ECEFF3', '#3E4756');
  // Kräftig und gesättigt (#653): vom schwarzen bzw. dunkelblauen Text der Schlüsselwörter klar
  // verschieden (ΔE2000 ≥ 30), untereinander ≥ 30, gegen Weiß ≥ 4,5 : 1. Tiefe 0 nicht blau, weil
  // die IDE Schlüsselwörter im hellen Schema dunkelblau zeichnet; kein Rot neben der Fehlerfarbe.
  // Reihenfolge beginnt bei Blau; zyklisch wie zuvor, damit Nachbarn unterscheidbar bleiben.
  Result.Pairs[0] := Hex('#0071E3');
  Result.Pairs[1] := Hex('#EE0000');
  Result.Pairs[2] := Hex('#007C8A');
  Result.Pairs[3] := Hex('#C000E0');
  Result.Pairs[4] := Hex('#008700');
  // Lokale Routinen (#1788): Bernstein, keiner der Paarfarben ähnlich, gegen Weiß über 4,5 : 1.
  Result.NestedRoutine := Hex('#A85A00');
  // Sechs deutlich verschiedene Töne für die Platzhalter (#451); Rot fehlt, es bleibt den Fehlern.
  Result.Placeholders[0] := Hex('#0071E3');
  Result.Placeholders[1] := Hex('#D86A00');
  Result.Placeholders[2] := Hex('#008700');
  Result.Placeholders[3] := Hex('#C000E0');
  Result.Placeholders[4] := Hex('#007C8A');
  Result.Placeholders[5] := Hex('#A08000');
  Result.Signals := TDpccSignals.Light;
end;

class function TDpccColors.Dark: TDpccColors;
begin
  Result := Default(TDpccColors);
  Result.IsDark := True;
  Result.Surface := Hex('#1A1E25');
  Result.Gutter := Hex('#15181D');
  Result.Text := Hex('#E3E7ED');
  Result.Muted := Hex('#9AA3B2');
  Result.Line := Hex('#2B313B');
  Result.Accent := Hex('#5B9BE6');
  Result.AccentSoft := Hex('#1B2D45');
  // 15 % statt 18 % wie im Entwurf: sonst hat der Akzent darauf weniger als 4,5 : 1.
  Result.Selection := TDpccColorMath.Mix(Result.Accent, Result.Surface, 0.15);
  Result.Keyword := Hex('#7FB0EE');
  Result.StringLiteral := Hex('#E3B27A');
  Result.Comment := Hex('#8A93A3');
  Result.Add := Hex('#7FD39A');
  Result.AddSoft := Hex('#1D3325');
  Result.Warn := Hex('#F0C06A');
  Result.WarnSoft := Hex('#3A2E17');
  Result.Error := Hex('#F59A8F');
  Result.ErrorSoft := Hex('#3E201E');
  Result.Badges[TDpccBadgeKind.Function_] := Badge('#1B2D45', '#9CC3F2');
  Result.Badges[TDpccBadgeKind.Procedure_] := Badge('#1C3329', '#86D0AE');
  Result.Badges[TDpccBadgeKind.Property_] := Badge('#43301F', '#F5B783');
  Result.Badges[TDpccBadgeKind.Field] := Badge('#1F3338', '#8FCAD6');
  Result.Badges[TDpccBadgeKind.Event] := Badge('#36264A', '#CBA6F2');
  Result.Badges[TDpccBadgeKind.Constant] := Badge('#3B3218', '#E8C96A');
  Result.Badges[TDpccBadgeKind.Type_] := Badge('#2A4670', '#B8D5F7');
  Result.Badges[TDpccBadgeKind.Variable] := Badge('#1F3338', '#8FCAD6');
  Result.Badges[TDpccBadgeKind.Unit_] := Badge('#272D36', '#B9C1CC');
  Result.Badges[TDpccBadgeKind.Snippet] := Badge('#272D36', '#B9C1CC');
  Result.Badges[TDpccBadgeKind.Keyword] := Badge('#272D36', '#B9C1CC');
  Result.Badges[TDpccBadgeKind.XmlDoc] := Badge('#272D36', '#B9C1CC');
  // #653: Die bisherigen Pastelltöne lagen zu nah am hellen Text (Kontrast unter 1,8 : 1 und
  // ΔE2000 unter 30); dieselben Farbtöne wie hell, gesättigt und mittelhell.
  // Reihenfolge beginnt bei Blau; zyklisch wie zuvor, damit Nachbarn unterscheidbar bleiben.
  Result.Pairs[0] := Hex('#3C94FF');
  Result.Pairs[1] := Hex('#F67676');
  Result.Pairs[2] := Hex('#00A4A4');
  Result.Pairs[3] := Hex('#E250FF');
  Result.Pairs[4] := Hex('#24AA24');
  Result.NestedRoutine := Hex('#E8A33D');
  Result.Placeholders[0] := Hex('#3C94FF');
  Result.Placeholders[1] := Hex('#FF9A3D');
  Result.Placeholders[2] := Hex('#24AA24');
  Result.Placeholders[3] := Hex('#E250FF');
  Result.Placeholders[4] := Hex('#00A4A4');
  Result.Placeholders[5] := Hex('#D6B020');
  Result.Signals := TDpccSignals.Dark;
end;

function TDpccColors.WithPairs(const ACustom: string): TDpccColors;
var
  mCustom: TDpccPairColors;
begin
  Result := Self;
  if ParsePairs(ACustom, mCustom) then
  begin
    Result.Pairs := mCustom;
  end;
end;

function TDpccColors.WithNestedRoutine(const ACustom: string): TDpccColors;
var
  mColor: TDpccColor;
begin
  Result := Self;
  if ParseColor(ACustom, mColor) then
  begin
    Result.NestedRoutine := mColor;
  end;
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

class function TDpccColors.ForChrome(AFace, AText: TDpccColor): TDpccColors;
begin
  Result := ForBackground(AFace);
  Result.Surface := AFace;
  Result.Gutter := AFace;
  Result.Text := AText;
  Result.Muted := TDpccColorMath.Mix(AText, AFace, cDpccMixChromeMuted);
  Result.Line := TDpccColorMath.Mix(AText, AFace, cDpccMixChromeLine);
  if Result.IsDark then
  begin
    Result.Selection := TDpccColorMath.Mix(Result.Accent, AFace, 0.25);
  end
  else
  begin
    Result.Selection := TDpccColorMath.Mix(Result.Accent, AFace, 0.15);
  end;
end;

class function TDpccColors.ForWindow(AWindow, AText: TDpccColor): TDpccColors;
begin
  Result := ForChrome(AWindow, AText);
  Result.Gutter := TDpccColorMath.Mix(AText, AWindow, cDpccMixWindowGutter);
end;

class function TDpccColors.InlayHint(ABack: TDpccColor): TDpccHintColors;
var
  mColors: TDpccColors;
begin
  mColors := ForBackground(ABack);
  Result.Text := TDpccColorMath.Mix(mColors.Text, ABack, cDpccMixInlayText);
  Result.Pen := TDpccColorMath.Mix(mColors.Accent, ABack, cDpccMixInlayPen);
  Result.Fill := TDpccColorMath.Mix(mColors.Accent, ABack, cDpccMixInlayFill);
end;

end.
