unit dpcc.UI.Completion.RowColors.Tests;

// Tests für die Farben einer Zeile der Vervollständigungsliste je Stufe der Darstellung (LOOK1,
// dpcc.UI.Completion.RowColors): Art-Spalte, Marken rechts, Name von Aktionszeilen, getippte Zeichen, Kästchen im
// Mengenmodus, gewählte Zeile (Intensiv in den Farben von Dezent, Look.Marked), gedämpfte Zeilen und die erste Zeile
// der leeren Liste.
// Erwartet wird gegen die Grundpalette und TDpccColorMath.Mix wie im Entwurf (dpcc-popups.html, Tabelle „Was jede
// Stufe ändert“), auf heller und dunkler Palette und auf den Farben des Editors.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccCompletionRowColorsTests = class
  public
    /// <summary>Intensiv: Platzhalterfarbe je Artgruppe; Dezent gedämpft; Unscheinbar schwächer gedämpft.</summary>
    [Test]
    procedure KindColorPerLevel;
    /// <summary>Unbekanntes und leeres Art-Wort nehmen die Farbe der Gruppe None.</summary>
    [Test]
    procedure KindColorUnknownWord;
    /// <summary>Intensiv: „+ Unit“ farbig, Warnung und Fehler farbig; Dezent: „+ Unit“ gedämpft; Unscheinbar: alles
    /// gedämpft. Neutrale und Akzent-Marken gedämpft.</summary>
    [Test]
    procedure TagColorPerLevel;
    /// <summary>Aktions- und Hinweiszeilen in Akzent (Intensiv, Dezent) bzw. Textfarbe (Unscheinbar); sonst Text.
    /// </summary>
    [Test]
    procedure ActionNamePerLevel;
    /// <summary>Getippte Zeichen nur bei Intensiv in Akzent, sonst in der Farbe des Namens.</summary>
    [Test]
    procedure MatchColorPerLevel;
    /// <summary>Gewählte Zeile bei Intensiv: wie in Dezent (Art gedämpft, Getipptes in der Farbe des Namens,
    /// „+ Unit“ gedämpft, Warnung und Fehler farbig, Aktion in Akzent, Kästchen in Akzent mit Haken in der
    /// Flächenfarbe), auch wenn die Zeile sonst gedämpft wäre; kein Text in der Flächenfarbe.</summary>
    [Test]
    procedure SelectedRowLikeSubtleWhenIntense;
    /// <summary>Gewählte Zeile bei Dezent und Unscheinbar: jeder Text behält seine Farbe, auch wenn die Zeile sonst
    /// gedämpft wäre.</summary>
    [Test]
    procedure SelectedRowKeepsColorsOtherwise;
    /// <summary>Gedämpfte Zeile: jede Farbe zu 62 % über der Fläche.</summary>
    [Test]
    procedure DimRowMixesWithSurface;
    /// <summary>Kästchen: leer Rand gedämpft, gewählt Fläche in Look.Action mit Haken in der Flächenfarbe.</summary>
    [Test]
    procedure CheckColorsUnselected;
    /// <summary>„Keine Treffer …“ in allen Stufen in der Textfarbe (Intensiv wie Dezent).</summary>
    [Test]
    procedure EmptyHeadTextPerLevel;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette,
  dpcc.Core.Style.Look,
  dpcc.Core.Completion.Presentation,
  dpcc.UI.Completion.RowColors;

const
  cPaletteNames: array[0..3] of string = ('hell', 'dunkel', 'Editor hell', 'Editor dunkel');
  cKindWords: array[0..5] of string = ('function', 'field', 'type', 'keyword', 'property', 'const');

function Palettes: TArray<TDpccColors>;
begin
  Result := [TDpccColors.Light, TDpccColors.Dark,
    TDpccColors.ForWindow(TDpccColorMath.FromHex('#FFFFFF'), TDpccColorMath.FromHex('#000000')),
    TDpccColors.ForWindow(TDpccColorMath.FromHex('#1E1E1E'), TDpccColorMath.FromHex('#D4D4D4'))];
end;

function Mix(AFront, ABack: TDpccColor; AAlpha: Double): TDpccColor;
begin
  Result := TDpccColorMath.Mix(AFront, ABack, AAlpha);
end;

procedure Same(AExpected, AActual: TDpccColor; const AName: string);
begin
  Assert.AreEqual(TDpccColorMath.ToHex(AExpected), TDpccColorMath.ToHex(AActual), AName);
end;

function LevelName(const APalette: string; ALevel: TDpccLookLevel): string;
begin
  Result := APalette + ' ' + DpccLookLevelToId(ALevel);
end;

/// <summary>Alle Farben zweier Zeilen gleich.</summary>
procedure SameRow(const AExpected, AActual: TDpccRowColors; const AName: string);
var
  mKind: TDpccTagKind;
begin
  Same(AExpected.Kind, AActual.Kind, AName + ': Kind');
  Same(AExpected.Name, AActual.Name, AName + ': Name');
  Same(AExpected.Match, AActual.Match, AName + ': Match');
  Same(AExpected.Text, AActual.Text, AName + ': Text');
  Same(AExpected.Muted, AActual.Muted, AName + ': Muted');
  for mKind := Low(TDpccTagKind) to High(TDpccTagKind) do
  begin
    Same(AExpected.Tags[mKind], AActual.Tags[mKind], AName + ': Tag ' + IntToStr(Ord(mKind)));
  end;
  Same(AExpected.CheckFrame, AActual.CheckFrame, AName + ': CheckFrame');
  Same(AExpected.CheckFill, AActual.CheckFill, AName + ': CheckFill');
  Same(AExpected.CheckMark, AActual.CheckMark, AName + ': CheckMark');
end;

{ TDpccCompletionRowColorsTests }

procedure TDpccCompletionRowColorsTests.KindColorPerLevel;
var
  mPalettes: TArray<TDpccColors>;
  mColors: TDpccColors;
  mIndex, mWord: Integer;
  mLook: TDpccLook;
  mName: string;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    mColors := mPalettes[mIndex];
    for mWord := 0 to High(cKindWords) do
    begin
      mName := cPaletteNames[mIndex] + ' ' + cKindWords[mWord];
      // Reihenfolge der Wörter wie die Artgruppen Routine … Constant, also Platzhalterfarbe 0 … 5.
      mLook := TDpccLook.From(mColors, TDpccLookLevel.Intense);
      Same(Mix(mColors.Placeholders[mWord], mColors.Text, 0.8),
        TDpccCompletionRowColors.KindColor(mLook, cKindWords[mWord]), mName + ' intense');
      mLook := TDpccLook.From(mColors, TDpccLookLevel.Subtle);
      Same(mColors.Muted, TDpccCompletionRowColors.KindColor(mLook, cKindWords[mWord]), mName + ' subtle');
      mLook := TDpccLook.From(mColors, TDpccLookLevel.Plain);
      Same(Mix(mColors.Text, mColors.Surface, 0.5), TDpccCompletionRowColors.KindColor(mLook, cKindWords[mWord]),
        mName + ' plain');
    end;
    // Die Zeile nimmt dieselbe Farbe für die Art-Spalte.
    mLook := TDpccLook.From(mColors, TDpccLookLevel.Intense);
    Same(TDpccCompletionRowColors.KindColor(mLook, 'procedure'),
      TDpccCompletionRowColors.Row(mLook, 'procedure', False, False, False).Kind, cPaletteNames[mIndex] + ' Row');
  end;
end;

procedure TDpccCompletionRowColorsTests.KindColorUnknownWord;
var
  mLevel: TDpccLookLevel;
  mLook: TDpccLook;
begin
  for mLevel := Low(TDpccLookLevel) to High(TDpccLookLevel) do
  begin
    mLook := TDpccLook.From(TDpccColors.Light, mLevel);
    Same(mLook.Kind[TDpccKindGroup.None], TDpccCompletionRowColors.KindColor(mLook, ''),
      DpccLookLevelToId(mLevel) + ' leer');
    Same(mLook.Kind[TDpccKindGroup.None], TDpccCompletionRowColors.KindColor(mLook, 'label'),
      DpccLookLevelToId(mLevel) + ' label');
  end;
  // Intensiv: Unbekanntes gedämpft, nicht in einer Platzhalterfarbe.
  Same(TDpccColors.Light.Muted, TDpccCompletionRowColors.KindColor(TDpccLook.From(TDpccColors.Light,
    TDpccLookLevel.Intense), 'label'), 'intense label gedämpft');
end;

procedure TDpccCompletionRowColorsTests.TagColorPerLevel;
var
  mPalettes: TArray<TDpccColors>;
  mColors: TDpccColors;
  mIndex: Integer;
  mLevel: TDpccLookLevel;
  mLook: TDpccLook;
  mName: string;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    mColors := mPalettes[mIndex];
    mLook := TDpccLook.From(mColors, TDpccLookLevel.Intense);
    mName := LevelName(cPaletteNames[mIndex], TDpccLookLevel.Intense);
    Same(Mix(mColors.Placeholders[2], mColors.Text, 0.8), TDpccCompletionRowColors.TagColor(mLook,
      TDpccTagKind.Add), mName + ': Add');
    Same(mColors.Warn, TDpccCompletionRowColors.TagColor(mLook, TDpccTagKind.Warn), mName + ': Warn');
    Same(mColors.Error, TDpccCompletionRowColors.TagColor(mLook, TDpccTagKind.Error), mName + ': Error');

    mLook := TDpccLook.From(mColors, TDpccLookLevel.Subtle);
    mName := LevelName(cPaletteNames[mIndex], TDpccLookLevel.Subtle);
    Same(mColors.Muted, TDpccCompletionRowColors.TagColor(mLook, TDpccTagKind.Add), mName + ': Add');
    Same(mColors.Warn, TDpccCompletionRowColors.TagColor(mLook, TDpccTagKind.Warn), mName + ': Warn');
    Same(mColors.Error, TDpccCompletionRowColors.TagColor(mLook, TDpccTagKind.Error), mName + ': Error');

    mLook := TDpccLook.From(mColors, TDpccLookLevel.Plain);
    mName := LevelName(cPaletteNames[mIndex], TDpccLookLevel.Plain);
    Same(mColors.Muted, TDpccCompletionRowColors.TagColor(mLook, TDpccTagKind.Add), mName + ': Add');
    Same(mColors.Muted, TDpccCompletionRowColors.TagColor(mLook, TDpccTagKind.Warn), mName + ': Warn');
    Same(mColors.Muted, TDpccCompletionRowColors.TagColor(mLook, TDpccTagKind.Error), mName + ': Error');

    for mLevel := Low(TDpccLookLevel) to High(TDpccLookLevel) do
    begin
      mLook := TDpccLook.From(mColors, mLevel);
      mName := LevelName(cPaletteNames[mIndex], mLevel);
      Same(mColors.Muted, TDpccCompletionRowColors.TagColor(mLook, TDpccTagKind.Neutral), mName + ': Neutral');
      Same(mColors.Muted, TDpccCompletionRowColors.TagColor(mLook, TDpccTagKind.Accent), mName + ': Accent');
      // Die Zeile nimmt dieselben Farben für die Marken.
      Same(TDpccCompletionRowColors.TagColor(mLook, TDpccTagKind.Warn),
        TDpccCompletionRowColors.Row(mLook, 'function', False, False, False).Tags[TDpccTagKind.Warn],
        mName + ': Row Warn');
    end;
  end;
end;

procedure TDpccCompletionRowColorsTests.ActionNamePerLevel;
var
  mPalettes: TArray<TDpccColors>;
  mColors: TDpccColors;
  mIndex: Integer;
  mLevel: TDpccLookLevel;
  mLook: TDpccLook;
  mName: string;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    mColors := mPalettes[mIndex];
    mName := cPaletteNames[mIndex];
    Same(mColors.Accent, TDpccCompletionRowColors.NameColor(TDpccLook.From(mColors, TDpccLookLevel.Intense), True),
      mName + ' intense');
    Same(mColors.Accent, TDpccCompletionRowColors.NameColor(TDpccLook.From(mColors, TDpccLookLevel.Subtle), True),
      mName + ' subtle');
    Same(mColors.Text, TDpccCompletionRowColors.NameColor(TDpccLook.From(mColors, TDpccLookLevel.Plain), True),
      mName + ' plain');
    for mLevel := Low(TDpccLookLevel) to High(TDpccLookLevel) do
    begin
      mLook := TDpccLook.From(mColors, mLevel);
      Same(mColors.Text, TDpccCompletionRowColors.NameColor(mLook, False), LevelName(mName, mLevel) + ' Name');
      Same(TDpccCompletionRowColors.NameColor(mLook, True),
        TDpccCompletionRowColors.Row(mLook, 'function', True, False, False).Name, LevelName(mName, mLevel) + ' Row');
    end;
  end;
end;

procedure TDpccCompletionRowColorsTests.MatchColorPerLevel;
var
  mPalettes: TArray<TDpccColors>;
  mColors: TDpccColors;
  mIndex: Integer;
  mLook: TDpccLook;
  mName: string;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    mColors := mPalettes[mIndex];
    mName := cPaletteNames[mIndex];
    mLook := TDpccLook.From(mColors, TDpccLookLevel.Intense);
    Same(mColors.Accent, TDpccCompletionRowColors.Row(mLook, 'function', False, False, False).Match,
      mName + ' intense');
    mLook := TDpccLook.From(mColors, TDpccLookLevel.Subtle);
    Same(mColors.Text, TDpccCompletionRowColors.Row(mLook, 'function', False, False, False).Match,
      mName + ' subtle');
    // Ohne MatchUsed folgt das Getippte dem Namen, auch in einer Aktionszeile.
    Same(mColors.Accent, TDpccCompletionRowColors.Row(mLook, 'function', True, False, False).Match,
      mName + ' subtle Aktion');
    mLook := TDpccLook.From(mColors, TDpccLookLevel.Plain);
    Same(mColors.Text, TDpccCompletionRowColors.Row(mLook, 'function', False, False, False).Match,
      mName + ' plain');
  end;
end;

procedure TDpccCompletionRowColorsTests.SelectedRowLikeSubtleWhenIntense;
var
  mPalettes: TArray<TDpccColors>;
  mColors: TDpccColors;
  mIndex: Integer;
  mLook, mSubtle: TDpccLook;
  mRow: TDpccRowColors;
  mName: string;
  mAction: Boolean;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    mColors := mPalettes[mIndex];
    mName := cPaletteNames[mIndex];
    mLook := TDpccLook.From(mColors, TDpccLookLevel.Intense);
    mSubtle := TDpccLook.From(mColors, TDpccLookLevel.Subtle);
    // Auch eine Zeile, die sonst gedämpft wäre: genau die Farben der gewählten Zeile in Dezent.
    for mAction := False to True do
    begin
      SameRow(TDpccCompletionRowColors.Row(mSubtle, 'function', mAction, True, True),
        TDpccCompletionRowColors.Row(mLook, 'function', mAction, True, True),
        mName + ' Aktion ' + BoolToStr(mAction, True));
    end;
    // Einzeln gegen die Grundpalette: gewöhnliche Zeile …
    mRow := TDpccCompletionRowColors.Row(mLook, 'function', False, True, True);
    Same(mColors.Muted, mRow.Kind, mName + ': Kind gedämpft');
    Same(mColors.Text, mRow.Name, mName + ': Name');
    Same(mColors.Text, mRow.Match, mName + ': Getipptes nur unterstrichen, nicht in Akzent');
    Same(mColors.Text, mRow.Text, mName + ': Text');
    Same(mColors.Muted, mRow.Muted, mName + ': Muted');
    Same(mColors.Muted, mRow.Tags[TDpccTagKind.Add], mName + ': Add gedämpft');
    Same(mColors.Warn, mRow.Tags[TDpccTagKind.Warn], mName + ': Warn');
    Same(mColors.Error, mRow.Tags[TDpccTagKind.Error], mName + ': Error');
    Same(mColors.Muted, mRow.CheckFrame, mName + ': CheckFrame');
    Same(mColors.Accent, mRow.CheckFill, mName + ': CheckFill');
    Same(mColors.Surface, mRow.CheckMark, mName + ': CheckMark');
    // … und Aktionszeile: Name und Getipptes in Akzent.
    mRow := TDpccCompletionRowColors.Row(mLook, 'function', True, True, False);
    Same(mColors.Accent, mRow.Name, mName + ': Aktion');
    Same(mColors.Accent, mRow.Match, mName + ': Aktion getippt');
    // Nicht gewählte Zeilen behalten die Farben von Intensiv.
    mRow := TDpccCompletionRowColors.Row(mLook, 'function', False, False, False);
    Same(Mix(mColors.Placeholders[0], mColors.Text, 0.8), mRow.Kind, mName + ': nicht gewählt, Kind');
    Same(mColors.Accent, mRow.Match, mName + ': nicht gewählt, Match');
  end;
end;

procedure TDpccCompletionRowColorsTests.SelectedRowKeepsColorsOtherwise;
var
  mPalettes: TArray<TDpccColors>;
  mIndex: Integer;
  mLevel: TDpccLookLevel;
  mLook: TDpccLook;
  mName: string;
  mAction: Boolean;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    for mLevel in [TDpccLookLevel.Subtle, TDpccLookLevel.Plain] do
    begin
      mLook := TDpccLook.From(mPalettes[mIndex], mLevel);
      Assert.IsFalse(mLook.MarkBarUsed, LevelName(cPaletteNames[mIndex], mLevel) + ': MarkBarUsed');
      for mAction := False to True do
      begin
        mName := LevelName(cPaletteNames[mIndex], mLevel) + ' Aktion ' + BoolToStr(mAction, True);
        SameRow(TDpccCompletionRowColors.Row(mLook, 'property', mAction, False, False),
          TDpccCompletionRowColors.Row(mLook, 'property', mAction, True, False), mName);
        // Die gewählte Zeile wird nie gedämpft.
        SameRow(TDpccCompletionRowColors.Row(mLook, 'property', mAction, False, False),
          TDpccCompletionRowColors.Row(mLook, 'property', mAction, True, True), mName + ' gedämpft');
      end;
    end;
  end;
end;

procedure TDpccCompletionRowColorsTests.DimRowMixesWithSurface;
var
  mPalettes: TArray<TDpccColors>;
  mIndex: Integer;
  mLevel: TDpccLookLevel;
  mLook: TDpccLook;
  mPlain, mDim: TDpccRowColors;
  mKind: TDpccTagKind;
  mSurface: TDpccColor;
  mName: string;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    mSurface := mPalettes[mIndex].Surface;
    for mLevel := Low(TDpccLookLevel) to High(TDpccLookLevel) do
    begin
      mName := LevelName(cPaletteNames[mIndex], mLevel);
      mLook := TDpccLook.From(mPalettes[mIndex], mLevel);
      mPlain := TDpccCompletionRowColors.Row(mLook, 'function', True, False, False);
      mDim := TDpccCompletionRowColors.Row(mLook, 'function', True, False, True);
      Same(Mix(mPlain.Kind, mSurface, 0.62), mDim.Kind, mName + ': Kind');
      Same(Mix(mPlain.Name, mSurface, 0.62), mDim.Name, mName + ': Name');
      Same(Mix(mPlain.Match, mSurface, 0.62), mDim.Match, mName + ': Match');
      Same(Mix(mPlain.Text, mSurface, 0.62), mDim.Text, mName + ': Text');
      Same(Mix(mPlain.Muted, mSurface, 0.62), mDim.Muted, mName + ': Muted');
      for mKind := Low(TDpccTagKind) to High(TDpccTagKind) do
      begin
        Same(Mix(mPlain.Tags[mKind], mSurface, 0.62), mDim.Tags[mKind], mName + ': Tag ' + IntToStr(Ord(mKind)));
      end;
    end;
  end;
end;

procedure TDpccCompletionRowColorsTests.CheckColorsUnselected;
var
  mPalettes: TArray<TDpccColors>;
  mIndex: Integer;
  mLevel: TDpccLookLevel;
  mLook: TDpccLook;
  mRow: TDpccRowColors;
  mName: string;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    for mLevel := Low(TDpccLookLevel) to High(TDpccLookLevel) do
    begin
      mName := LevelName(cPaletteNames[mIndex], mLevel);
      mLook := TDpccLook.From(mPalettes[mIndex], mLevel);
      mRow := TDpccCompletionRowColors.Row(mLook, 'const', False, False, False);
      Same(mPalettes[mIndex].Muted, mRow.CheckFrame, mName + ': CheckFrame');
      Same(mLook.Action, mRow.CheckFill, mName + ': CheckFill');
      Same(mPalettes[mIndex].Surface, mRow.CheckMark, mName + ': CheckMark');
    end;
  end;
end;

procedure TDpccCompletionRowColorsTests.EmptyHeadTextPerLevel;
var
  mPalettes: TArray<TDpccColors>;
  mIndex: Integer;
  mName: string;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    mName := cPaletteNames[mIndex];
    Same(mPalettes[mIndex].Text, TDpccCompletionRowColors.EmptyHeadText(TDpccLook.From(mPalettes[mIndex],
      TDpccLookLevel.Intense)), mName + ' intense');
    Same(mPalettes[mIndex].Text, TDpccCompletionRowColors.EmptyHeadText(TDpccLook.From(mPalettes[mIndex],
      TDpccLookLevel.Subtle)), mName + ' subtle');
    Same(mPalettes[mIndex].Text, TDpccCompletionRowColors.EmptyHeadText(TDpccLook.From(mPalettes[mIndex],
      TDpccLookLevel.Plain)), mName + ' plain');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccCompletionRowColorsTests);

end.
