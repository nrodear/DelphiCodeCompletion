unit dpcc.Core.Style.Look;

// Darstellung der Popups in drei Stufen (LOOK1): Intensiv, Dezent, Unscheinbar. TDpccLook enthält alle Farben, die
// die Zeichner der Fenster (Liste, Hover, Parameterhilfe, Doku, Editor-Überlagerungen) brauchen, abgeleitet aus der
// Grundpalette TDpccColors (in der IDE TDpccIdeStyle.ListColors) und der Stufe. Ohne VCL und ohne Einstellungen:
// Die Stufe liefert der Aufrufer (in der IDE TDpccIdeStyle.LookLevel aus der Einstellung PopupLook).
//   - Intensiv: Art-Spalte, Zahlen und Typen in den Platzhalterfarben, Akzentfläche unter dem aktiven Parameter,
//     Rand im Akzent. Jede markierte Fläche (Kopfzeile des Hovers, gewählte Zeile der Liste, erste Zeile der leeren
//     Liste, gewählte Überladung) sieht aus wie in Dezent – Fläche und Farben ihrer Inhalte (Marked) – und bekommt
//     dazu einen Balken von cDpccLookMarkBar logischen Pixeln in MarkBar (Akzent): im Hover oben am Fenster, bei
//     Zeilen links davor bzw. am linken Innenrand.
//   - Dezent: das bisherige Aussehen (S8) mit schwacher Auswahl- und Kopffläche und abgeschwächter Typfarbe.
//   - Unscheinbar: fast alles in Text- und gedämpfter Farbe; nur Fehler bleiben farbig.
// Mischungen über TDpccColorMath.Mix wie color-mix() im Entwurf (dpcc-popups.html, Abschnitt „Stufen“ und Regel
// „Intensiv, allgemeine Regel“).

interface

uses
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette;

type
{$SCOPEDENUMS ON}
  /// <summary>Darstellung der Popups: intensiv, dezent, unscheinbar.</summary>
  TDpccLookLevel = (Intense, Subtle, Plain);

  /// <summary>Gruppen der Art-Wörter (function, property …) für die Farbe der Art-Spalte.</summary>
  TDpccKindGroup = (None, Routine, Variable, TypeName, Misc, Prop, Constant);
{$SCOPEDENUMS OFF}

  TDpccLook = record
    Level: TDpccLookLevel;
    /// <summary>Grundpalette, aus der alles abgeleitet ist.</summary>
    Colors: TDpccColors;
    // Fenster
    /// <summary>Rand aller Popups.</summary>
    Frame: TDpccColor;
    /// <summary>Rand des Hover-Tooltips.</summary>
    HoverFrame: TDpccColor;
    // Auswahl (Liste, Parameterhilfe)
    SelectionBack: TDpccColor;
    // Kopfzeile (Hover, Zeile „Keine Treffer“ der leeren Liste)
    HeadBack: TDpccColor;
    // Markierte Flächen (Auswahl und Kopfzeile)
    /// <summary>True (nur Intensiv): jede markierte Fläche bekommt einen Balken von cDpccLookMarkBar logischen
    /// Pixeln in MarkBar.</summary>
    MarkBarUsed: Boolean;
    /// <summary>Farbe des Balkens: Intensiv der Akzent, sonst (ohne Balken) die Fläche.</summary>
    MarkBar: TDpccColor;
    // Liste
    /// <summary>Farbe der Art-Spalte je Gruppe (KindGroupOf).</summary>
    Kind: array[TDpccKindGroup] of TDpccColor;
    /// <summary>True: getippte Zeichen in Match, sonst in der Farbe des Namens.</summary>
    MatchUsed: Boolean;
    Match: TDpccColor;
    TagAdd, TagWarn, TagError: TDpccColor;
    /// <summary>Aktions- und Hinweiszeilen, gewähltes Kästchen.</summary>
    Action: TDpccColor;
    // Syntax in Signaturen
    SynKeyword, SynString, SynComment, SynNumber, SynType: TDpccColor;
    ParamBackUsed: Boolean;
    /// <summary>Fläche des aktiven Parameters.</summary>
    ParamBack: TDpccColor;
    // Doku
    Link: TDpccColor;
    DocHeading, DocHeadingLine, DocParam, DocType: TDpccColor;
    FormatLine: TDpccColor;
    // Meldungen
    Warn: TDpccColor;
    WarnBackUsed: Boolean;
    WarnBack: TDpccColor;
    Error: TDpccColor;
    // Editor
    /// <summary>Deckkraft (0..255) der Format-Platzhalter im Editor.</summary>
    MarkAlpha: Byte;
    /// <summary>Rahmen der Vorlagen-Platzhalter im Editor.</summary>
    PlaceholderFrame: TDpccColor;
    /// <summary>Alle Farben der Stufe ALevel aus der Grundpalette AColors.</summary>
    class function From(const AColors: TDpccColors; ALevel: TDpccLookLevel): TDpccLook; static;
    /// <summary>Gruppe des Art-Worts aus TDpccItemPresentation.KindWord (Groß/Klein egal); None für Leeres und
    /// Unbekanntes.</summary>
    class function KindGroupOf(const AKindWord: string): TDpccKindGroup; static;
    /// <summary>Look für die Inhalte einer markierten Fläche (Kopfzeile, gewählte Zeile, gewählte Überladung):
    /// Intensiv die Farben von Dezent aus derselben Grundpalette, sonst dieser Look selbst. Den Balken
    /// (MarkBarUsed, MarkBar) nimmt der Zeichner aus dem Look des Fensters, nicht aus diesem.</summary>
    function Marked: TDpccLook;
  end;

const
  cDpccLookLevelDefault = TDpccLookLevel.Subtle;

  /// <summary>Dicke des Balkens markierter Flächen (MarkBarUsed) in logischen Pixeln.</summary>
  cDpccLookMarkBar = 3;

  /// <summary>Anteil des Akzents über der Fläche für die gewählte Zeile (Dezent und Intensiv): hell und dunkel wie in
  /// TDpccColors.ForWindow.</summary>
  cDpccLookSelectionLight = 0.15;
  cDpccLookSelectionDark = 0.25;

/// <summary>Kennung der Stufe für Einstellungen: 'intense' | 'subtle' | 'plain'.</summary>
function DpccLookLevelToId(ALevel: TDpccLookLevel): string;
/// <summary>Stufe zur Kennung (Groß/Klein egal); Unbekanntes liefert ADefault.</summary>
function DpccLookLevelFromId(const AId: string; ADefault: TDpccLookLevel): TDpccLookLevel;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  /// <summary>Intensiv: Anteil der Platzhalterfarbe über dem Text (Art-Spalte, Zahlen, Typen, Doku).</summary>
  cStrongShare = 0.8;
  /// <summary>Dezent: abgeschwächte Typ- und Parameterfarbe.</summary>
  cSoftShare = 0.55;
  /// <summary>Intensiv: Rand und Linie unter Doku-Überschriften, Akzent über der Fläche.</summary>
  cFrameShare = 0.55;
  /// <summary>Intensiv: Akzentfläche unter dem aktiven Parameter.</summary>
  cParamShare = 0.18;
  /// <summary>Unscheinbar: Text über der Fläche für Auswahl und Kopfzeile.</summary>
  cPlainBackShare = 0.10;
  /// <summary>Unscheinbar: Text über der Fläche für die Art-Spalte (schwächer als Muted).</summary>
  cPlainKindShare = 0.5;
  /// <summary>Dezent: Akzent über Muted für Doku-Überschriften.</summary>
  cSubtleHeadingShare = 0.5;
  /// <summary>Warnfläche: Intensiv und Dezent.</summary>
  cWarnShareIntense = 0.14;
  cWarnShareSubtle = 0.07;

  cMarkAlpha: array[TDpccLookLevel] of Byte = (110, 70, 36);
  cIds: array[TDpccLookLevel] of string = ('intense', 'subtle', 'plain');

function Mix(AFront, ABack: TDpccColor; AAlpha: Double): TDpccColor;
begin
  Result := TDpccColorMath.Mix(AFront, ABack, AAlpha);
end;

/// <summary>Anteil des Akzents für die gewählte Zeile: auf dunkler Fläche kräftiger, wie in ForWindow.</summary>
function SelectionShare(ASurface: TDpccColor): Double;
begin
  if TDpccColorMath.IsDark(ASurface) then
  begin
    Result := cDpccLookSelectionDark;
  end
  else
  begin
    Result := cDpccLookSelectionLight;
  end;
end;

/// <summary>Platzhalterfarbe zur Artgruppe: Routine = 0 … Constant = 5.</summary>
function GroupPlaceholder(const AColors: TDpccColors; AGroup: TDpccKindGroup): TDpccColor;
begin
  Result := AColors.Placeholders[Ord(AGroup) - Ord(TDpccKindGroup.Routine)];
end;

procedure FillIntense(var ALook: TDpccLook);
var
  mColors: TDpccColors;
  mGroup: TDpccKindGroup;
  mShare: Double;
begin
  mColors := ALook.Colors;
  mShare := SelectionShare(mColors.Surface);
  ALook.Frame := Mix(mColors.Accent, mColors.Surface, cFrameShare);
  ALook.HoverFrame := mColors.Accent;
  // Markierte Flächen wie in Dezent, dazu der Balken im Akzent.
  ALook.SelectionBack := Mix(mColors.Accent, mColors.Surface, mShare);
  ALook.HeadBack := Mix(mColors.Accent, mColors.Surface, mShare / 2);
  ALook.MarkBarUsed := True;
  ALook.MarkBar := mColors.Accent;
  ALook.Kind[TDpccKindGroup.None] := mColors.Muted;
  for mGroup := TDpccKindGroup.Routine to High(TDpccKindGroup) do
  begin
    ALook.Kind[mGroup] := Mix(GroupPlaceholder(mColors, mGroup), mColors.Text, cStrongShare);
  end;
  ALook.MatchUsed := True;
  ALook.Match := mColors.Accent;
  ALook.TagAdd := Mix(mColors.Placeholders[2], mColors.Text, cStrongShare);
  ALook.TagWarn := mColors.Warn;
  ALook.TagError := mColors.Error;
  ALook.Action := mColors.Accent;
  ALook.SynKeyword := mColors.Keyword;
  ALook.SynString := mColors.StringLiteral;
  ALook.SynComment := mColors.Comment;
  ALook.SynNumber := Mix(mColors.Placeholders[1], mColors.Text, cStrongShare);
  ALook.SynType := Mix(mColors.Placeholders[2], mColors.Text, cStrongShare);
  ALook.ParamBackUsed := True;
  ALook.ParamBack := Mix(mColors.Accent, mColors.Surface, cParamShare);
  ALook.Link := mColors.Accent;
  ALook.DocHeading := mColors.Accent;
  ALook.DocHeadingLine := Mix(mColors.Accent, mColors.Surface, cFrameShare);
  ALook.DocParam := Mix(mColors.Placeholders[1], mColors.Text, cStrongShare);
  ALook.DocType := Mix(mColors.Placeholders[2], mColors.Text, cStrongShare);
  ALook.FormatLine := mColors.Accent;
  ALook.Warn := mColors.Warn;
  ALook.WarnBackUsed := True;
  ALook.WarnBack := Mix(mColors.Warn, mColors.Surface, cWarnShareIntense);
  ALook.PlaceholderFrame := mColors.Accent;
end;

procedure FillSubtle(var ALook: TDpccLook);
var
  mColors: TDpccColors;
  mGroup: TDpccKindGroup;
  mShare: Double;
begin
  mColors := ALook.Colors;
  mShare := SelectionShare(mColors.Surface);
  ALook.Frame := mColors.Line;
  ALook.HoverFrame := mColors.Line;
  ALook.SelectionBack := Mix(mColors.Accent, mColors.Surface, mShare);
  // Kopfzeile halb so stark wie die gewählte Zeile.
  ALook.HeadBack := Mix(mColors.Accent, mColors.Surface, mShare / 2);
  ALook.MarkBarUsed := False;
  ALook.MarkBar := mColors.Surface;
  for mGroup := Low(TDpccKindGroup) to High(TDpccKindGroup) do
  begin
    ALook.Kind[mGroup] := mColors.Muted;
  end;
  ALook.MatchUsed := False;
  ALook.Match := mColors.Text;
  ALook.TagAdd := mColors.Muted;
  ALook.TagWarn := mColors.Warn;
  ALook.TagError := mColors.Error;
  ALook.Action := mColors.Accent;
  ALook.SynKeyword := mColors.Keyword;
  ALook.SynString := mColors.StringLiteral;
  ALook.SynComment := mColors.Comment;
  ALook.SynNumber := mColors.Text;
  ALook.SynType := Mix(mColors.Placeholders[2], mColors.Text, cSoftShare);
  ALook.ParamBackUsed := False;
  ALook.ParamBack := mColors.Surface;
  ALook.Link := mColors.Accent;
  ALook.DocHeading := Mix(mColors.Accent, mColors.Muted, cSubtleHeadingShare);
  ALook.DocHeadingLine := mColors.Line;
  ALook.DocParam := Mix(mColors.Placeholders[1], mColors.Text, cSoftShare);
  ALook.DocType := Mix(mColors.Placeholders[2], mColors.Text, cSoftShare);
  ALook.FormatLine := mColors.Accent;
  ALook.Warn := mColors.Warn;
  ALook.WarnBackUsed := True;
  ALook.WarnBack := Mix(mColors.Warn, mColors.Surface, cWarnShareSubtle);
  ALook.PlaceholderFrame := mColors.Text;
end;

procedure FillPlain(var ALook: TDpccLook);
var
  mColors: TDpccColors;
  mGroup: TDpccKindGroup;
begin
  mColors := ALook.Colors;
  ALook.Frame := mColors.Line;
  ALook.HoverFrame := mColors.Line;
  ALook.SelectionBack := Mix(mColors.Text, mColors.Surface, cPlainBackShare);
  ALook.HeadBack := Mix(mColors.Text, mColors.Surface, cPlainBackShare);
  ALook.MarkBarUsed := False;
  ALook.MarkBar := mColors.Surface;
  for mGroup := Low(TDpccKindGroup) to High(TDpccKindGroup) do
  begin
    ALook.Kind[mGroup] := Mix(mColors.Text, mColors.Surface, cPlainKindShare);
  end;
  ALook.MatchUsed := False;
  ALook.Match := mColors.Text;
  ALook.TagAdd := mColors.Muted;
  ALook.TagWarn := mColors.Muted;
  ALook.TagError := mColors.Muted;
  ALook.Action := mColors.Text;
  // Keine Syntaxfarben; Schlüsselwörter bleiben nur fett.
  ALook.SynKeyword := mColors.Text;
  ALook.SynString := mColors.Text;
  ALook.SynComment := mColors.Muted;
  ALook.SynNumber := mColors.Text;
  ALook.SynType := mColors.Text;
  ALook.ParamBackUsed := False;
  ALook.ParamBack := mColors.Surface;
  ALook.Link := mColors.Text;
  ALook.DocHeading := mColors.Muted;
  ALook.DocHeadingLine := mColors.Line;
  ALook.DocParam := mColors.Text;
  ALook.DocType := mColors.Text;
  ALook.FormatLine := mColors.Muted;
  ALook.Warn := mColors.Muted;
  ALook.WarnBackUsed := False;
  ALook.WarnBack := mColors.Surface;
  ALook.PlaceholderFrame := mColors.Muted;
end;

{ TDpccLook }

class function TDpccLook.From(const AColors: TDpccColors; ALevel: TDpccLookLevel): TDpccLook;
begin
  Result := Default(TDpccLook);
  Result.Level := ALevel;
  Result.Colors := AColors;
  case ALevel of
    TDpccLookLevel.Intense:
      FillIntense(Result);
    TDpccLookLevel.Plain:
      FillPlain(Result);
  else
    FillSubtle(Result);
  end;
  // In allen Stufen gleich.
  Result.Error := AColors.Error;
  Result.MarkAlpha := cMarkAlpha[ALevel];
end;

class function TDpccLook.KindGroupOf(const AKindWord: string): TDpccKindGroup;
var
  mWord: string;
begin
  mWord := Trim(AKindWord);
  if MatchText(mWord, ['function', 'procedure', 'constructor', 'destructor']) then
  begin
    Result := TDpccKindGroup.Routine;
  end
  else if MatchText(mWord, ['field', 'var']) then
  begin
    Result := TDpccKindGroup.Variable;
  end
  else if MatchText(mWord, ['type', 'unit']) then
  begin
    Result := TDpccKindGroup.TypeName;
  end
  else if MatchText(mWord, ['keyword', 'snippet', 'xmldoc']) then
  begin
    Result := TDpccKindGroup.Misc;
  end
  else if MatchText(mWord, ['property', 'event']) then
  begin
    Result := TDpccKindGroup.Prop;
  end
  else if SameText(mWord, 'const') then
  begin
    Result := TDpccKindGroup.Constant;
  end
  else
  begin
    Result := TDpccKindGroup.None;
  end;
end;

function TDpccLook.Marked: TDpccLook;
begin
  // Intensiv: Inhalte markierter Flächen wie in Dezent (Art gedämpft, Getipptes nur unterstrichen, „+ Unit“
  // gedämpft, Syntaxfarben von Dezent, keine Fläche unter dem aktiven Parameter).
  if Level = TDpccLookLevel.Intense then
  begin
    Result := TDpccLook.From(Colors, TDpccLookLevel.Subtle);
  end
  else
  begin
    Result := Self;
  end;
end;

function DpccLookLevelToId(ALevel: TDpccLookLevel): string;
begin
  Result := cIds[ALevel];
end;

function DpccLookLevelFromId(const AId: string; ADefault: TDpccLookLevel): TDpccLookLevel;
var
  mLevel: TDpccLookLevel;
begin
  for mLevel := Low(TDpccLookLevel) to High(TDpccLookLevel) do
  begin
    if SameText(Trim(AId), cIds[mLevel]) then
    begin
      Exit(mLevel);
    end;
  end;
  Result := ADefault;
end;

end.
