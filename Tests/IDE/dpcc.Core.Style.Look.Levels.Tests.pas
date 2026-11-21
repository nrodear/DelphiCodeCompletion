unit dpcc.Core.Style.Look.Levels.Tests;

// Tests für die Stufen der Darstellung (LOOK1, dpcc.Core.Style.Look): Jede Farbe von TDpccLook folgt in jeder Stufe
// der Formel aus dem Entwurf (dpcc-popups.html, Abschnitt „Stufen“), geprüft gegen TDpccColorMath.Mix auf heller
// und dunkler Grundpalette sowie auf den Farben des Editors (ForWindow), nicht gegen abgetippte Hexwerte. Dazu die
// Artgruppen (KindGroupOf), die Kennungen der Stufen für die Einstellungen und die markierten Flächen (Entwurf
// „Intensiv, allgemeine Regel“): Intensiv Flächen wie Dezent mit Balken (MarkBarUsed, MarkBar, cDpccLookMarkBar),
// Inhalte über Marked in den Farben von Dezent.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDpccStyleLookLevelsTests = class
  public
    /// <summary>Intensiv: Auswahl und Kopfzeile wie Dezent mit Balken im Akzent, Platzhalterfarben für Art, Zahl und
    /// Typ.</summary>
    [Test]
    procedure IntenseFollowsFormula;
    /// <summary>Dezent: Auswahl 15 % bzw. 25 % Akzent, Kopfzeile halb so stark, Typen abgeschwächt.</summary>
    [Test]
    procedure SubtleFollowsFormula;
    /// <summary>Unscheinbar: Text und Gedämpftes, nur Fehler farbig.</summary>
    [Test]
    procedure PlainFollowsFormula;
    /// <summary>Level und Grundpalette stehen im Look; Fehlerfarbe in allen Stufen gleich; Vorgabe Dezent.</summary>
    [Test]
    procedure LevelColorsAndErrorKept;
    /// <summary>Dezent auf den Farben des Editors: gewählte Zeile wie Colors.Selection aus ForWindow.</summary>
    [Test]
    procedure SubtleSelectionMatchesForWindow;
    [Test]
    procedure KindGroupOfWords;
    [Test]
    procedure LevelIdsRoundTrip;
    /// <summary>Unbekannte und leere Kennung liefern die Vorgabe; Groß/Klein egal.</summary>
    [Test]
    procedure LevelFromIdTolerant;
    /// <summary>Marked: Intensiv alle Farben von Dezent aus derselben Grundpalette (Stufe Dezent, ohne Balken),
    /// Dezent und Unscheinbar der Look selbst.</summary>
    [Test]
    procedure MarkedPerLevel;
    /// <summary>Balken markierter Flächen: nur Intensiv, im Akzent, 3 logische Pixel; sonst ohne Balken mit der
    /// Fläche als Farbe. Die Fläche selbst ist in Intensiv und Dezent gleich.</summary>
    [Test]
    procedure MarkBarOnlyIntense;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette,
  dpcc.Core.Style.Look;

const
  cPaletteNames: array[0..3] of string = ('hell', 'dunkel', 'Editor hell', 'Editor dunkel');

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

/// <summary>Anteil des Akzents der gewählten Zeile (Dezent): 0,15 auf heller, 0,25 auf dunkler Fläche.</summary>
function SelectionShare(const AColors: TDpccColors): Double;
begin
  if TDpccColorMath.IsDark(AColors.Surface) then
  begin
    Result := 0.25;
  end
  else
  begin
    Result := 0.15;
  end;
end;

procedure Same(AExpected, AActual: TDpccColor; const AName: string);
begin
  Assert.AreEqual(TDpccColorMath.ToHex(AExpected), TDpccColorMath.ToHex(AActual), AName);
end;

/// <summary>Alle Farben und Schalter zweier Looks gleich (außer Level).</summary>
procedure SameLook(const AExpected, AActual: TDpccLook; const AName: string);
var
  mGroup: TDpccKindGroup;
begin
  Same(AExpected.Colors.Surface, AActual.Colors.Surface, AName + ': Colors.Surface');
  Same(AExpected.Colors.Text, AActual.Colors.Text, AName + ': Colors.Text');
  Same(AExpected.Colors.Accent, AActual.Colors.Accent, AName + ': Colors.Accent');
  Same(AExpected.Frame, AActual.Frame, AName + ': Frame');
  Same(AExpected.HoverFrame, AActual.HoverFrame, AName + ': HoverFrame');
  Same(AExpected.SelectionBack, AActual.SelectionBack, AName + ': SelectionBack');
  Same(AExpected.HeadBack, AActual.HeadBack, AName + ': HeadBack');
  Assert.AreEqual(Ord(AExpected.MarkBarUsed), Ord(AActual.MarkBarUsed), AName + ': MarkBarUsed');
  Same(AExpected.MarkBar, AActual.MarkBar, AName + ': MarkBar');
  for mGroup := Low(TDpccKindGroup) to High(TDpccKindGroup) do
  begin
    Same(AExpected.Kind[mGroup], AActual.Kind[mGroup], AName + ': Kind ' + IntToStr(Ord(mGroup)));
  end;
  Assert.AreEqual(Ord(AExpected.MatchUsed), Ord(AActual.MatchUsed), AName + ': MatchUsed');
  Same(AExpected.Match, AActual.Match, AName + ': Match');
  Same(AExpected.TagAdd, AActual.TagAdd, AName + ': TagAdd');
  Same(AExpected.TagWarn, AActual.TagWarn, AName + ': TagWarn');
  Same(AExpected.TagError, AActual.TagError, AName + ': TagError');
  Same(AExpected.Action, AActual.Action, AName + ': Action');
  Same(AExpected.SynKeyword, AActual.SynKeyword, AName + ': SynKeyword');
  Same(AExpected.SynString, AActual.SynString, AName + ': SynString');
  Same(AExpected.SynComment, AActual.SynComment, AName + ': SynComment');
  Same(AExpected.SynNumber, AActual.SynNumber, AName + ': SynNumber');
  Same(AExpected.SynType, AActual.SynType, AName + ': SynType');
  Assert.AreEqual(Ord(AExpected.ParamBackUsed), Ord(AActual.ParamBackUsed), AName + ': ParamBackUsed');
  Same(AExpected.ParamBack, AActual.ParamBack, AName + ': ParamBack');
  Same(AExpected.Link, AActual.Link, AName + ': Link');
  Same(AExpected.DocHeading, AActual.DocHeading, AName + ': DocHeading');
  Same(AExpected.DocHeadingLine, AActual.DocHeadingLine, AName + ': DocHeadingLine');
  Same(AExpected.DocParam, AActual.DocParam, AName + ': DocParam');
  Same(AExpected.DocType, AActual.DocType, AName + ': DocType');
  Same(AExpected.FormatLine, AActual.FormatLine, AName + ': FormatLine');
  Same(AExpected.Warn, AActual.Warn, AName + ': Warn');
  Assert.AreEqual(Ord(AExpected.WarnBackUsed), Ord(AActual.WarnBackUsed), AName + ': WarnBackUsed');
  Same(AExpected.WarnBack, AActual.WarnBack, AName + ': WarnBack');
  Same(AExpected.Error, AActual.Error, AName + ': Error');
  Assert.AreEqual(Integer(AExpected.MarkAlpha), Integer(AActual.MarkAlpha), AName + ': MarkAlpha');
  Same(AExpected.PlaceholderFrame, AActual.PlaceholderFrame, AName + ': PlaceholderFrame');
end;

procedure CheckIntense(const AColors: TDpccColors; const AName: string);
var
  mLook: TDpccLook;
  mShare: Double;
begin
  mLook := TDpccLook.From(AColors, TDpccLookLevel.Intense);
  mShare := SelectionShare(AColors);
  Same(Mix(AColors.Accent, AColors.Surface, 0.55), mLook.Frame, AName + ': Frame');
  Same(AColors.Accent, mLook.HoverFrame, AName + ': HoverFrame');
  // Markierte Flächen wie Dezent (keine volle Akzentfläche mehr), dazu der Balken im Akzent.
  Same(Mix(AColors.Accent, AColors.Surface, mShare), mLook.SelectionBack, AName + ': SelectionBack');
  Same(Mix(AColors.Accent, AColors.Surface, mShare / 2), mLook.HeadBack, AName + ': HeadBack');
  Assert.IsTrue(mLook.MarkBarUsed, AName + ': MarkBarUsed');
  Same(AColors.Accent, mLook.MarkBar, AName + ': MarkBar');
  Same(Mix(AColors.Placeholders[0], AColors.Text, 0.8), mLook.Kind[TDpccKindGroup.Routine], AName + ': Kind Routine');
  Same(Mix(AColors.Placeholders[1], AColors.Text, 0.8), mLook.Kind[TDpccKindGroup.Variable],
    AName + ': Kind Variable');
  Same(Mix(AColors.Placeholders[2], AColors.Text, 0.8), mLook.Kind[TDpccKindGroup.TypeName],
    AName + ': Kind TypeName');
  Same(Mix(AColors.Placeholders[3], AColors.Text, 0.8), mLook.Kind[TDpccKindGroup.Misc], AName + ': Kind Misc');
  Same(Mix(AColors.Placeholders[4], AColors.Text, 0.8), mLook.Kind[TDpccKindGroup.Prop], AName + ': Kind Prop');
  Same(Mix(AColors.Placeholders[5], AColors.Text, 0.8), mLook.Kind[TDpccKindGroup.Constant],
    AName + ': Kind Constant');
  Same(AColors.Muted, mLook.Kind[TDpccKindGroup.None], AName + ': Kind None');
  Assert.IsTrue(mLook.MatchUsed, AName + ': MatchUsed');
  Same(AColors.Accent, mLook.Match, AName + ': Match');
  Same(Mix(AColors.Placeholders[2], AColors.Text, 0.8), mLook.TagAdd, AName + ': TagAdd');
  Same(AColors.Warn, mLook.TagWarn, AName + ': TagWarn');
  Same(AColors.Error, mLook.TagError, AName + ': TagError');
  Same(AColors.Accent, mLook.Action, AName + ': Action');
  Same(AColors.Keyword, mLook.SynKeyword, AName + ': SynKeyword');
  Same(AColors.StringLiteral, mLook.SynString, AName + ': SynString');
  Same(AColors.Comment, mLook.SynComment, AName + ': SynComment');
  Same(Mix(AColors.Placeholders[1], AColors.Text, 0.8), mLook.SynNumber, AName + ': SynNumber');
  Same(Mix(AColors.Placeholders[2], AColors.Text, 0.8), mLook.SynType, AName + ': SynType');
  Assert.IsTrue(mLook.ParamBackUsed, AName + ': ParamBackUsed');
  Same(Mix(AColors.Accent, AColors.Surface, 0.18), mLook.ParamBack, AName + ': ParamBack');
  Same(AColors.Accent, mLook.Link, AName + ': Link');
  Same(AColors.Accent, mLook.DocHeading, AName + ': DocHeading');
  Same(Mix(AColors.Accent, AColors.Surface, 0.55), mLook.DocHeadingLine, AName + ': DocHeadingLine');
  Same(Mix(AColors.Placeholders[1], AColors.Text, 0.8), mLook.DocParam, AName + ': DocParam');
  Same(Mix(AColors.Placeholders[2], AColors.Text, 0.8), mLook.DocType, AName + ': DocType');
  Same(AColors.Accent, mLook.FormatLine, AName + ': FormatLine');
  Same(AColors.Warn, mLook.Warn, AName + ': Warn');
  Assert.IsTrue(mLook.WarnBackUsed, AName + ': WarnBackUsed');
  Same(Mix(AColors.Warn, AColors.Surface, 0.14), mLook.WarnBack, AName + ': WarnBack');
  Same(AColors.Error, mLook.Error, AName + ': Error');
  Assert.AreEqual(110, Integer(mLook.MarkAlpha), AName + ': MarkAlpha');
  Same(AColors.Accent, mLook.PlaceholderFrame, AName + ': PlaceholderFrame');
end;

procedure CheckSubtle(const AColors: TDpccColors; const AName: string);
var
  mLook: TDpccLook;
  mGroup: TDpccKindGroup;
  mShare: Double;
begin
  mLook := TDpccLook.From(AColors, TDpccLookLevel.Subtle);
  mShare := SelectionShare(AColors);
  Same(AColors.Line, mLook.Frame, AName + ': Frame');
  Same(AColors.Line, mLook.HoverFrame, AName + ': HoverFrame');
  Same(Mix(AColors.Accent, AColors.Surface, mShare), mLook.SelectionBack, AName + ': SelectionBack');
  Same(Mix(AColors.Accent, AColors.Surface, mShare / 2), mLook.HeadBack, AName + ': HeadBack');
  Assert.IsFalse(mLook.MarkBarUsed, AName + ': MarkBarUsed');
  Same(AColors.Surface, mLook.MarkBar, AName + ': MarkBar');
  for mGroup := Low(TDpccKindGroup) to High(TDpccKindGroup) do
  begin
    Same(AColors.Muted, mLook.Kind[mGroup], AName + ': Kind ' + IntToStr(Ord(mGroup)));
  end;
  Assert.IsFalse(mLook.MatchUsed, AName + ': MatchUsed');
  Same(AColors.Text, mLook.Match, AName + ': Match');
  Same(AColors.Muted, mLook.TagAdd, AName + ': TagAdd');
  Same(AColors.Warn, mLook.TagWarn, AName + ': TagWarn');
  Same(AColors.Error, mLook.TagError, AName + ': TagError');
  Same(AColors.Accent, mLook.Action, AName + ': Action');
  Same(AColors.Keyword, mLook.SynKeyword, AName + ': SynKeyword');
  Same(AColors.StringLiteral, mLook.SynString, AName + ': SynString');
  Same(AColors.Comment, mLook.SynComment, AName + ': SynComment');
  Same(AColors.Text, mLook.SynNumber, AName + ': SynNumber');
  Same(Mix(AColors.Placeholders[2], AColors.Text, 0.55), mLook.SynType, AName + ': SynType');
  Assert.IsFalse(mLook.ParamBackUsed, AName + ': ParamBackUsed');
  Same(AColors.Surface, mLook.ParamBack, AName + ': ParamBack');
  Same(AColors.Accent, mLook.Link, AName + ': Link');
  Same(Mix(AColors.Accent, AColors.Muted, 0.5), mLook.DocHeading, AName + ': DocHeading');
  Same(AColors.Line, mLook.DocHeadingLine, AName + ': DocHeadingLine');
  Same(Mix(AColors.Placeholders[1], AColors.Text, 0.55), mLook.DocParam, AName + ': DocParam');
  Same(Mix(AColors.Placeholders[2], AColors.Text, 0.55), mLook.DocType, AName + ': DocType');
  Same(AColors.Accent, mLook.FormatLine, AName + ': FormatLine');
  Same(AColors.Warn, mLook.Warn, AName + ': Warn');
  Assert.IsTrue(mLook.WarnBackUsed, AName + ': WarnBackUsed');
  Same(Mix(AColors.Warn, AColors.Surface, 0.07), mLook.WarnBack, AName + ': WarnBack');
  Same(AColors.Error, mLook.Error, AName + ': Error');
  Assert.AreEqual(70, Integer(mLook.MarkAlpha), AName + ': MarkAlpha');
  Same(AColors.Text, mLook.PlaceholderFrame, AName + ': PlaceholderFrame');
end;

procedure CheckPlain(const AColors: TDpccColors; const AName: string);
var
  mLook: TDpccLook;
  mGroup: TDpccKindGroup;
begin
  mLook := TDpccLook.From(AColors, TDpccLookLevel.Plain);
  Same(AColors.Line, mLook.Frame, AName + ': Frame');
  Same(AColors.Line, mLook.HoverFrame, AName + ': HoverFrame');
  Same(Mix(AColors.Text, AColors.Surface, 0.10), mLook.SelectionBack, AName + ': SelectionBack');
  Same(Mix(AColors.Text, AColors.Surface, 0.10), mLook.HeadBack, AName + ': HeadBack');
  Assert.IsFalse(mLook.MarkBarUsed, AName + ': MarkBarUsed');
  Same(AColors.Surface, mLook.MarkBar, AName + ': MarkBar');
  for mGroup := Low(TDpccKindGroup) to High(TDpccKindGroup) do
  begin
    Same(Mix(AColors.Text, AColors.Surface, 0.5), mLook.Kind[mGroup], AName + ': Kind ' + IntToStr(Ord(mGroup)));
  end;
  Assert.IsFalse(mLook.MatchUsed, AName + ': MatchUsed');
  Same(AColors.Text, mLook.Match, AName + ': Match');
  Same(AColors.Muted, mLook.TagAdd, AName + ': TagAdd');
  Same(AColors.Muted, mLook.TagWarn, AName + ': TagWarn');
  Same(AColors.Muted, mLook.TagError, AName + ': TagError');
  Same(AColors.Text, mLook.Action, AName + ': Action');
  Same(AColors.Text, mLook.SynKeyword, AName + ': SynKeyword');
  Same(AColors.Text, mLook.SynString, AName + ': SynString');
  Same(AColors.Muted, mLook.SynComment, AName + ': SynComment');
  Same(AColors.Text, mLook.SynNumber, AName + ': SynNumber');
  Same(AColors.Text, mLook.SynType, AName + ': SynType');
  Assert.IsFalse(mLook.ParamBackUsed, AName + ': ParamBackUsed');
  Same(AColors.Surface, mLook.ParamBack, AName + ': ParamBack');
  Same(AColors.Text, mLook.Link, AName + ': Link');
  Same(AColors.Muted, mLook.DocHeading, AName + ': DocHeading');
  Same(AColors.Line, mLook.DocHeadingLine, AName + ': DocHeadingLine');
  Same(AColors.Text, mLook.DocParam, AName + ': DocParam');
  Same(AColors.Text, mLook.DocType, AName + ': DocType');
  Same(AColors.Muted, mLook.FormatLine, AName + ': FormatLine');
  Same(AColors.Muted, mLook.Warn, AName + ': Warn');
  Assert.IsFalse(mLook.WarnBackUsed, AName + ': WarnBackUsed');
  Same(AColors.Surface, mLook.WarnBack, AName + ': WarnBack');
  Same(AColors.Error, mLook.Error, AName + ': Error');
  Assert.AreEqual(36, Integer(mLook.MarkAlpha), AName + ': MarkAlpha');
  Same(AColors.Muted, mLook.PlaceholderFrame, AName + ': PlaceholderFrame');
end;

{ TDpccStyleLookLevelsTests }

procedure TDpccStyleLookLevelsTests.IntenseFollowsFormula;
var
  mPalettes: TArray<TDpccColors>;
  mIndex: Integer;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    CheckIntense(mPalettes[mIndex], cPaletteNames[mIndex]);
  end;
end;

procedure TDpccStyleLookLevelsTests.SubtleFollowsFormula;
var
  mPalettes: TArray<TDpccColors>;
  mIndex: Integer;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    CheckSubtle(mPalettes[mIndex], cPaletteNames[mIndex]);
  end;
end;

procedure TDpccStyleLookLevelsTests.PlainFollowsFormula;
var
  mPalettes: TArray<TDpccColors>;
  mIndex: Integer;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    CheckPlain(mPalettes[mIndex], cPaletteNames[mIndex]);
  end;
end;

procedure TDpccStyleLookLevelsTests.LevelColorsAndErrorKept;
var
  mPalettes: TArray<TDpccColors>;
  mIndex: Integer;
  mLevel: TDpccLookLevel;
  mLook: TDpccLook;
  mName: string;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    for mLevel := Low(TDpccLookLevel) to High(TDpccLookLevel) do
    begin
      mLook := TDpccLook.From(mPalettes[mIndex], mLevel);
      mName := cPaletteNames[mIndex] + ' ' + DpccLookLevelToId(mLevel);
      Assert.AreEqual(Ord(mLevel), Ord(mLook.Level), mName + ': Level');
      Same(mPalettes[mIndex].Surface, mLook.Colors.Surface, mName + ': Colors.Surface');
      Same(mPalettes[mIndex].Text, mLook.Colors.Text, mName + ': Colors.Text');
      Same(mPalettes[mIndex].Error, mLook.Error, mName + ': Error');
    end;
  end;
  Assert.AreEqual(Ord(TDpccLookLevel.Subtle), Ord(cDpccLookLevelDefault), 'Vorgabe Dezent');
end;

procedure TDpccStyleLookLevelsTests.SubtleSelectionMatchesForWindow;
var
  mColors: TDpccColors;
begin
  mColors := TDpccColors.ForWindow(TDpccColorMath.FromHex('#FFFFFF'), TDpccColorMath.FromHex('#000000'));
  Same(mColors.Selection, TDpccLook.From(mColors, TDpccLookLevel.Subtle).SelectionBack, 'Editor hell');
  mColors := TDpccColors.ForWindow(TDpccColorMath.FromHex('#1E1E1E'), TDpccColorMath.FromHex('#D4D4D4'));
  Same(mColors.Selection, TDpccLook.From(mColors, TDpccLookLevel.Subtle).SelectionBack, 'Editor dunkel');
end;

procedure TDpccStyleLookLevelsTests.KindGroupOfWords;

  procedure Check(AExpected: TDpccKindGroup; const AWord: string);
  begin
    Assert.AreEqual(Ord(AExpected), Ord(TDpccLook.KindGroupOf(AWord)), '"' + AWord + '"');
  end;

begin
  Check(TDpccKindGroup.Routine, 'function');
  Check(TDpccKindGroup.Routine, 'procedure');
  Check(TDpccKindGroup.Routine, 'constructor');
  Check(TDpccKindGroup.Routine, 'destructor');
  Check(TDpccKindGroup.Variable, 'field');
  Check(TDpccKindGroup.Variable, 'var');
  Check(TDpccKindGroup.TypeName, 'type');
  Check(TDpccKindGroup.TypeName, 'unit');
  Check(TDpccKindGroup.Misc, 'keyword');
  Check(TDpccKindGroup.Misc, 'snippet');
  Check(TDpccKindGroup.Misc, 'xmldoc');
  Check(TDpccKindGroup.Prop, 'property');
  Check(TDpccKindGroup.Prop, 'event');
  Check(TDpccKindGroup.Constant, 'const');
  // Groß/Klein egal.
  Check(TDpccKindGroup.Routine, 'Function');
  Check(TDpccKindGroup.Prop, 'PROPERTY');
  Check(TDpccKindGroup.Constant, 'Const');
  // Leer und Unbekanntes.
  Check(TDpccKindGroup.None, '');
  Check(TDpccKindGroup.None, 'operator');
  Check(TDpccKindGroup.None, 'label');
end;

procedure TDpccStyleLookLevelsTests.LevelIdsRoundTrip;
var
  mLevel, mOther: TDpccLookLevel;
begin
  Assert.AreEqual('intense', DpccLookLevelToId(TDpccLookLevel.Intense));
  Assert.AreEqual('subtle', DpccLookLevelToId(TDpccLookLevel.Subtle));
  Assert.AreEqual('plain', DpccLookLevelToId(TDpccLookLevel.Plain));
  for mLevel := Low(TDpccLookLevel) to High(TDpccLookLevel) do
  begin
    // Vorgabe absichtlich die nächste Stufe: Das Ergebnis muss aus der Kennung kommen.
    mOther := TDpccLookLevel((Ord(mLevel) + 1) mod (Ord(High(TDpccLookLevel)) + 1));
    Assert.AreEqual(Ord(mLevel), Ord(DpccLookLevelFromId(DpccLookLevelToId(mLevel), mOther)),
      DpccLookLevelToId(mLevel));
  end;
end;

procedure TDpccStyleLookLevelsTests.LevelFromIdTolerant;
begin
  Assert.AreEqual(Ord(TDpccLookLevel.Intense), Ord(DpccLookLevelFromId('INTENSE', TDpccLookLevel.Plain)));
  Assert.AreEqual(Ord(TDpccLookLevel.Subtle), Ord(DpccLookLevelFromId('Subtle', TDpccLookLevel.Intense)));
  Assert.AreEqual(Ord(TDpccLookLevel.Plain), Ord(DpccLookLevelFromId('pLaIn', TDpccLookLevel.Subtle)));
  Assert.AreEqual(Ord(TDpccLookLevel.Plain), Ord(DpccLookLevelFromId('gibtsnicht', TDpccLookLevel.Plain)));
  Assert.AreEqual(Ord(TDpccLookLevel.Intense), Ord(DpccLookLevelFromId('', TDpccLookLevel.Intense)));
  // Deutsche Namen sind keine Kennungen.
  Assert.AreEqual(Ord(TDpccLookLevel.Intense), Ord(DpccLookLevelFromId('dezent', TDpccLookLevel.Intense)));
end;

procedure TDpccStyleLookLevelsTests.MarkedPerLevel;
var
  mPalettes: TArray<TDpccColors>;
  mIndex: Integer;
  mLevel: TDpccLookLevel;
  mLook, mMarked: TDpccLook;
  mName: string;
begin
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    mName := cPaletteNames[mIndex];
    // Intensiv: Inhalte markierter Flächen in den Farben von Dezent, also auch ohne eigenen Balken.
    mMarked := TDpccLook.From(mPalettes[mIndex], TDpccLookLevel.Intense).Marked;
    Assert.AreEqual(Ord(TDpccLookLevel.Subtle), Ord(mMarked.Level), mName + ' intense: Level');
    SameLook(TDpccLook.From(mPalettes[mIndex], TDpccLookLevel.Subtle), mMarked, mName + ' intense');
    // Einzeln, was die Regel verlangt: Art gedämpft, Getipptes nur unterstrichen, „+ Unit“ gedämpft, Zahl in
    // Textfarbe, Typ abgeschwächt, keine Fläche unter dem aktiven Parameter.
    Same(mPalettes[mIndex].Muted, mMarked.Kind[TDpccKindGroup.Routine], mName + ' intense: Kind Routine');
    Assert.IsFalse(mMarked.MatchUsed, mName + ' intense: MatchUsed');
    Same(mPalettes[mIndex].Muted, mMarked.TagAdd, mName + ' intense: TagAdd');
    Same(mPalettes[mIndex].Text, mMarked.SynNumber, mName + ' intense: SynNumber');
    Same(Mix(mPalettes[mIndex].Placeholders[2], mPalettes[mIndex].Text, 0.55), mMarked.SynType,
      mName + ' intense: SynType');
    Assert.IsFalse(mMarked.ParamBackUsed, mName + ' intense: ParamBackUsed');
    // Dezent und Unscheinbar: der Look selbst.
    for mLevel in [TDpccLookLevel.Subtle, TDpccLookLevel.Plain] do
    begin
      mLook := TDpccLook.From(mPalettes[mIndex], mLevel);
      mMarked := mLook.Marked;
      Assert.AreEqual(Ord(mLevel), Ord(mMarked.Level), mName + ' ' + DpccLookLevelToId(mLevel) + ': Level');
      SameLook(mLook, mMarked, mName + ' ' + DpccLookLevelToId(mLevel));
    end;
  end;
end;

procedure TDpccStyleLookLevelsTests.MarkBarOnlyIntense;
var
  mPalettes: TArray<TDpccColors>;
  mIndex: Integer;
  mIntense, mSubtle: TDpccLook;
  mName: string;
begin
  Assert.AreEqual(3, cDpccLookMarkBar, 'Dicke des Balkens');
  mPalettes := Palettes;
  for mIndex := 0 to High(mPalettes) do
  begin
    mName := cPaletteNames[mIndex];
    mIntense := TDpccLook.From(mPalettes[mIndex], TDpccLookLevel.Intense);
    mSubtle := TDpccLook.From(mPalettes[mIndex], TDpccLookLevel.Subtle);
    Assert.IsTrue(mIntense.MarkBarUsed, mName + ' intense: MarkBarUsed');
    Same(mPalettes[mIndex].Accent, mIntense.MarkBar, mName + ' intense: MarkBar');
    // Keine volle Akzentfläche mehr: dieselbe Fläche wie Dezent.
    Same(mSubtle.SelectionBack, mIntense.SelectionBack, mName + ': SelectionBack wie Dezent');
    Same(mSubtle.HeadBack, mIntense.HeadBack, mName + ': HeadBack wie Dezent');
    Assert.AreNotEqual(Integer(mPalettes[mIndex].Accent), Integer(mIntense.SelectionBack),
      mName + ': SelectionBack nicht der volle Akzent');
    Assert.IsFalse(mSubtle.MarkBarUsed, mName + ' subtle: MarkBarUsed');
    Assert.IsFalse(TDpccLook.From(mPalettes[mIndex], TDpccLookLevel.Plain).MarkBarUsed,
      mName + ' plain: MarkBarUsed');
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TDpccStyleLookLevelsTests);

end.
