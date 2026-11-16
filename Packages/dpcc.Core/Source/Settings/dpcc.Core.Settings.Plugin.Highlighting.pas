unit dpcc.Core.Settings.Plugin.Highlighting;

// Einstellungen des IDE-Plugins, Bereich Hervorhebung (highlight.*) (#227):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TDpccPluginSettings (dpcc.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  dpcc.Core.Settings.Plugin.Store;

type
  /// <summary>Plugin-Einstellungen: Hervorhebungen im Editor und Farben. Anweisungen mitfärben, Breite und Deckkraft
  /// der Blocklinien, Färbung lokaler Routinen, inaktive Zweige ausgrauen und gleichen Text hervorheben gibt es seit
  /// S8 nicht mehr, die Schalter Paarfärbung und Blocklinien (highlight.pairColors, highlight.pairGuides) seit S9:
  /// dpcc zeichnet keine Paare und schaltet die Strukturhervorhebung der IDE nicht mehr ab.</summary>
  TDpccPluginHighlightingSettings = record
    /// <summary>Eigene Paarfarben je Thema („#RRGGBB,…“, fünf Stück); leer = Standardpalette.</summary>
    PairColorsLight: string;
    PairColorsDark: string;
    /// <summary>Eigene Farbe lokaler Routinen je Thema („#RRGGBB“); leer = Palette (#1788).</summary>
    NestedRoutineColorLight: string;
    NestedRoutineColorDark: string;
    /// <summary>Austrittspunkte hervorheben (#698, editor.exitPoints).</summary>
    ExitPoints: Boolean;
    /// <summary>Auf except bzw. on die auslösenden Aufrufe zeigen (#698).</summary>
    ExitPointsExceptions: Boolean;
    /// <summary>Auf Break bzw. Continue die Schleife zeigen (#698).</summary>
    ExitPointsLoops: Boolean;
    /// <summary>Marke mit der Anzahl am Routinenkopf (#698).</summary>
    ExitPointsBadge: Boolean;
    /// <summary>Neu zugewiesene Variablen unterstreichen (#712, highlight.reassigned).</summary>
    Reassigned: Boolean;
    /// <summary>Arten, kommagetrennt: locals, loopVars, valueParams, varParams, fields (#712), siehe
    /// TDpccReassignedNames.</summary>
    ReassignedTargets: string;
    /// <summary>Linie: dotted, solid oder wavy (#712).</summary>
    ReassignedStyle: string;
    /// <summary>Farbe: theme oder #RRGGBB (#712).</summary>
    ReassignedColor: string;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TDpccPluginHighlightingSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TDpccSettingsExchange);
  end;

implementation

uses
  dpcc.Core.Settings.Reassigned,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette;

/// <summary>Eigene Paarfarben einheitlich schreiben; ungültig = leer (Standardpalette).</summary>
function NormalPairs(const AText: string): string;
var
  mPairs: TDpccPairColors;
begin
  if TDpccColors.ParsePairs(AText, mPairs) then
  begin
    Result := TDpccColors.PairsText(mPairs);
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Eine Farbe einheitlich schreiben; ungültig = leer (Palette, #1788).</summary>
function NormalColor(const AText: string): string;
var
  mColor: TDpccColor;
begin
  Result := '';
  if TDpccColors.ParseColor(AText, mColor) then
  begin
    Result := TDpccColorMath.ToHex(mColor);
  end;
end;

{ TDpccPluginHighlightingSettings }

class function TDpccPluginHighlightingSettings.Defaults: TDpccPluginHighlightingSettings;
begin
  Result.PairColorsLight := '';
  Result.PairColorsDark := '';
  Result.NestedRoutineColorLight := '';
  Result.NestedRoutineColorDark := '';
  Result.ExitPoints := True;
  Result.ExitPointsExceptions := True;
  Result.ExitPointsLoops := True;
  Result.ExitPointsBadge := True;
  Result.Reassigned := True;
  Result.ReassignedTargets := TDpccReassignedNames.TargetsText(TDpccReassignedNames.cDefaultTargets);
  Result.ReassignedStyle := 'dotted';
  Result.ReassignedColor := TDpccReassignedNames.cThemeColor;
end;

procedure TDpccPluginHighlightingSettings.Normalize;
begin
  PairColorsLight := NormalPairs(PairColorsLight);
  PairColorsDark := NormalPairs(PairColorsDark);
  NestedRoutineColorLight := NormalColor(NestedRoutineColorLight);
  NestedRoutineColorDark := NormalColor(NestedRoutineColorDark);
  ReassignedTargets := TDpccReassignedNames.NormalizeTargets(ReassignedTargets);
  ReassignedStyle := Choice(ReassignedStyle, TDpccReassignedNames.cStyles);
  ReassignedColor := TDpccReassignedNames.NormalizeColor(ReassignedColor);
end;

procedure TDpccPluginHighlightingSettings.Exchange(const AIo: TDpccSettingsExchange);
begin
  AIo.Text('PairColorsLight', PairColorsLight);
  AIo.Text('PairColorsDark', PairColorsDark);
  AIo.Text('NestedRoutineColorLight', NestedRoutineColorLight);
  AIo.Text('NestedRoutineColorDark', NestedRoutineColorDark);
  AIo.Flag('ExitPoints', ExitPoints);
  AIo.Flag('ExitPointsExceptions', ExitPointsExceptions);
  AIo.Flag('ExitPointsLoops', ExitPointsLoops);
  AIo.Flag('ExitPointsBadge', ExitPointsBadge);
  AIo.Flag('Reassigned', Reassigned);
  AIo.Text('ReassignedTargets', ReassignedTargets);
  AIo.Text('ReassignedStyle', ReassignedStyle);
  AIo.Text('ReassignedColor', ReassignedColor);
end;

end.
