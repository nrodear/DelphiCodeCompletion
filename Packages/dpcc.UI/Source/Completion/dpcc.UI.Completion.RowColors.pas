unit dpcc.UI.Completion.RowColors;

// Vervollständigungs-Popup (#410): Farben einer Zeile der Liste nach der Stufe der Darstellung (LOOK1), ohne
// Fenster und ohne VCL, damit sie sich je Stufe prüfen lassen. Gezeichnet wird in dpcc.UI.Completion.PopupPainter.
//   - Art-Spalte: Look.Kind je Artgruppe (TDpccLook.KindGroupOf des Art-Worts).
//   - Name fett in der Textfarbe, Aktions- und Hinweiszeilen (#444, #466, #471) in Look.Action; getippte Zeichen
//     unterstrichen, mit Look.MatchUsed zusätzlich in Look.Match.
//   - Rest der Signatur in der Textfarbe, das Detail gedämpft.
//   - Marken rechts nach ihrer Art: „+ Unit“ in Look.TagAdd, Warnungen in Look.TagWarn, Fehler in Look.TagError.
//   - Kästchen im Mengenmodus (#448): leer ein Rand in Muted, gewählt Fläche in Look.Action mit Haken in der
//     Flächenfarbe.
//   - Gewählte Zeile auf Look.SelectionBack und erste Zeile der leeren Liste auf Look.HeadBack sind markierte
//     Flächen: ihre Texte in den Farben von Look.Marked (Intensiv wie Dezent: Art gedämpft, Getipptes nur
//     unterstrichen, „+ Unit“ gedämpft, Warnung und Fehler farbig, Aktionen in Akzent, Kästchen in Akzent mit Haken
//     in der Flächenfarbe); den Balken davor (Look.MarkBarUsed) zeichnet PopupPainter.
//   - Gedämpfte Zeilen (geerbt #419, nicht verfügbar #476, Rest #497): jede Farbe zu cDimShare über der Fläche; die
//     gewählte Zeile nie.

interface

uses
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Look,
  dpcc.Core.Completion.Presentation;

type
  /// <summary>Alle Farben einer Zeile der Liste.</summary>
  TDpccRowColors = record
    /// <summary>Art-Spalte.</summary>
    Kind: TDpccColor;
    /// <summary>Name (fett).</summary>
    Name: TDpccColor;
    /// <summary>Getippte Zeichen im Namen (unterstrichen).</summary>
    Match: TDpccColor;
    /// <summary>Rest der Signatur hinter dem Namen.</summary>
    Text: TDpccColor;
    /// <summary>Detail abgesetzt hinter dem Namen.</summary>
    Muted: TDpccColor;
    /// <summary>Marken rechts je Art der Marke.</summary>
    Tags: array[TDpccTagKind] of TDpccColor;
    /// <summary>Rand des leeren Kästchens im Mengenmodus.</summary>
    CheckFrame: TDpccColor;
    /// <summary>Fläche des gewählten Kästchens.</summary>
    CheckFill: TDpccColor;
    /// <summary>Haken im gewählten Kästchen.</summary>
    CheckMark: TDpccColor;
  end;

  TDpccCompletionRowColors = class
  public const
    /// <summary>Anteil der Farbe über der Fläche in gedämpften Zeilen.</summary>
    cDimShare = 0.62;
  public
    /// <summary>AColor in einer gedämpften Zeile (ADim) zu cDimShare über der Fläche, sonst unverändert.</summary>
    class function Dim(const ALook: TDpccLook; AColor: TDpccColor; ADim: Boolean): TDpccColor; static;
    /// <summary>Farbe der Art-Spalte zum Art-Wort (TDpccItemPresentation.KindWord).</summary>
    class function KindColor(const ALook: TDpccLook; const AKindWord: string): TDpccColor; static;
    /// <summary>Farbe des Namens: Aktionen und Hinweise (AAction) in Look.Action, sonst die Textfarbe.</summary>
    class function NameColor(const ALook: TDpccLook; AAction: Boolean): TDpccColor; static;
    /// <summary>Farbe der getippten Zeichen: mit Look.MatchUsed Look.Match, sonst ANameColor.</summary>
    class function MatchColor(const ALook: TDpccLook; ANameColor: TDpccColor): TDpccColor; static;
    /// <summary>Farbe einer Marke rechts nach ihrer Art; andere Arten als Add, Warn, Error gedämpft.</summary>
    class function TagColor(const ALook: TDpccLook; AKind: TDpccTagKind): TDpccColor; static;
    /// <summary>Alle Farben einer Zeile: AKindWord ist das Art-Wort, AAction eine Aktions- oder Hinweiszeile,
    /// ASelected die gewählte Zeile (Farben aus ALook.Marked), ADim eine gedämpfte Zeile (gilt nicht für die
    /// gewählte).</summary>
    class function Row(const ALook: TDpccLook; const AKindWord: string; AAction, ASelected,
      ADim: Boolean): TDpccRowColors; static;
    /// <summary>Text der ersten Zeile der leeren Liste („Keine Treffer für …“) auf Look.HeadBack: die Textfarbe
    /// von ALook.Marked.</summary>
    class function EmptyHeadText(const ALook: TDpccLook): TDpccColor; static;
  end;

implementation

{ TDpccCompletionRowColors }

class function TDpccCompletionRowColors.Dim(const ALook: TDpccLook; AColor: TDpccColor; ADim: Boolean): TDpccColor;
begin
  if ADim then
  begin
    Result := TDpccColorMath.Mix(AColor, ALook.Colors.Surface, cDimShare);
  end
  else
  begin
    Result := AColor;
  end;
end;

class function TDpccCompletionRowColors.KindColor(const ALook: TDpccLook; const AKindWord: string): TDpccColor;
begin
  Result := ALook.Kind[TDpccLook.KindGroupOf(AKindWord)];
end;

class function TDpccCompletionRowColors.NameColor(const ALook: TDpccLook; AAction: Boolean): TDpccColor;
begin
  if AAction then
  begin
    Result := ALook.Action;
  end
  else
  begin
    Result := ALook.Colors.Text;
  end;
end;

class function TDpccCompletionRowColors.MatchColor(const ALook: TDpccLook; ANameColor: TDpccColor): TDpccColor;
begin
  if ALook.MatchUsed then
  begin
    Result := ALook.Match;
  end
  else
  begin
    Result := ANameColor;
  end;
end;

class function TDpccCompletionRowColors.TagColor(const ALook: TDpccLook; AKind: TDpccTagKind): TDpccColor;
begin
  case AKind of
    TDpccTagKind.Add:
      Result := ALook.TagAdd;
    TDpccTagKind.Warn:
      Result := ALook.TagWarn;
    TDpccTagKind.Error:
      Result := ALook.TagError;
  else
    Result := ALook.Colors.Muted;
  end;
end;

class function TDpccCompletionRowColors.Row(const ALook: TDpccLook; const AKindWord: string; AAction, ASelected,
  ADim: Boolean): TDpccRowColors;
var
  mKind: TDpccTagKind;
  mDim: Boolean;
  mLook: TDpccLook;
begin
  Result := Default(TDpccRowColors);
  // Die gewählte Zeile ist eine markierte Fläche: ihre Texte in den Farben von Marked (Intensiv wie Dezent).
  if ASelected then
  begin
    mLook := ALook.Marked;
  end
  else
  begin
    mLook := ALook;
  end;
  // Die gewählte Zeile bleibt voll lesbar.
  mDim := ADim and not ASelected;
  Result.Kind := Dim(mLook, KindColor(mLook, AKindWord), mDim);
  Result.Name := Dim(mLook, NameColor(mLook, AAction), mDim);
  Result.Match := Dim(mLook, MatchColor(mLook, NameColor(mLook, AAction)), mDim);
  Result.Text := Dim(mLook, mLook.Colors.Text, mDim);
  Result.Muted := Dim(mLook, mLook.Colors.Muted, mDim);
  for mKind := Low(TDpccTagKind) to High(TDpccTagKind) do
  begin
    Result.Tags[mKind] := Dim(mLook, TagColor(mLook, mKind), mDim);
  end;
  Result.CheckFrame := Dim(mLook, mLook.Colors.Muted, mDim);
  Result.CheckFill := Dim(mLook, mLook.Action, mDim);
  Result.CheckMark := mLook.Colors.Surface;
end;

class function TDpccCompletionRowColors.EmptyHeadText(const ALook: TDpccLook): TDpccColor;
begin
  // Markierte Fläche wie die gewählte Zeile: Text in der Textfarbe von Marked (in allen Stufen Colors.Text).
  Result := ALook.Marked.Colors.Text;
end;

end.
