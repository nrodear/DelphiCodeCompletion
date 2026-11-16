unit dpcc.Core.Settings.Reassigned;

// Einstellungen der Unterstreichung neu zugewiesener Variablen (#712):
// - highlight.reassigned.targets: kommagetrennte Arten (locals, loopVars,
//   valueParams, varParams, fields; Vorgabe "locals,valueParams"); unbekannte
//   fallen weg, die Reihenfolge ist fest. Dieselben Namen versteht der Server
//   (dpcc.server.reassigned).
// - highlight.reassigned.style: dotted, solid oder wavy.
// - highlight.reassigned.color: theme (Akzentfarbe des Themas) oder #RRGGBB.
// Liegt bei den Einstellungen, damit der Parser ohne den Editor-Kern auskommt;
// Antwort und Zeichnen rechnet dpcc.Core.Editor.Reassigned.

interface

uses
  dpcc.Core.Style.Color;

type
{$SCOPEDENUMS ON}
  TDpccReassignedTarget = (Locals, LoopVars, ValueParams, VarParams, Fields);
  TDpccReassignedStyle = (Dotted, Solid, Wavy);
{$SCOPEDENUMS OFF}
  TDpccReassignedTargets = set of TDpccReassignedTarget;

  TDpccReassignedNames = class
  public const
    cDefaultTargets = [TDpccReassignedTarget.Locals, TDpccReassignedTarget.ValueParams];
    cStyles: array[TDpccReassignedStyle] of string = ('dotted', 'solid', 'wavy');
    cThemeColor = 'theme';
  public
    class function TargetName(ATarget: TDpccReassignedTarget): string; static;
    class function TryTarget(const AName: string; out ATarget: TDpccReassignedTarget): Boolean; static;
    class function ParseTargets(const AText: string): TDpccReassignedTargets; static;
    class function TargetsText(ATargets: TDpccReassignedTargets): string; static;
    /// <summary>Bekannte Namen in fester Reihenfolge, ohne Doppelte.</summary>
    class function NormalizeTargets(const AText: string): string; static;
    /// <summary>Art der Linie; unbekannt = dotted.</summary>
    class function StyleOf(const AText: string): TDpccReassignedStyle; static;
    /// <summary>Eigene Farbe aus #RRGGBB; False bei theme oder unlesbarem Wert (dann gilt die Themenfarbe).</summary>
    class function TryColor(const AText: string; out AColor: TDpccColor): Boolean; static;
    /// <summary>theme oder #RRGGBB in Großbuchstaben; Unlesbares wird theme.</summary>
    class function NormalizeColor(const AText: string): string; static;
  end;

implementation

uses
  System.SysUtils;

const
  cTargetNames: array[TDpccReassignedTarget] of string = ('locals', 'loopVars', 'valueParams', 'varParams',
    'fields');

class function TDpccReassignedNames.TargetName(ATarget: TDpccReassignedTarget): string;
begin
  Result := cTargetNames[ATarget];
end;

class function TDpccReassignedNames.TryTarget(const AName: string; out ATarget: TDpccReassignedTarget): Boolean;
var
  mTarget: TDpccReassignedTarget;
begin
  for mTarget := Low(TDpccReassignedTarget) to High(TDpccReassignedTarget) do
  begin
    if SameText(Trim(AName), cTargetNames[mTarget]) then
    begin
      ATarget := mTarget;
      Exit(True);
    end;
  end;
  ATarget := TDpccReassignedTarget.Locals;
  Result := False;
end;

class function TDpccReassignedNames.ParseTargets(const AText: string): TDpccReassignedTargets;
var
  mPart: string;
  mTarget: TDpccReassignedTarget;
begin
  Result := [];
  for mPart in AText.Split([',', ';', ' ']) do
  begin
    if TryTarget(mPart, mTarget) then
    begin
      Include(Result, mTarget);
    end;
  end;
end;

class function TDpccReassignedNames.TargetsText(ATargets: TDpccReassignedTargets): string;
var
  mTarget: TDpccReassignedTarget;
begin
  Result := '';
  for mTarget := Low(TDpccReassignedTarget) to High(TDpccReassignedTarget) do
  begin
    if mTarget in ATargets then
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + cTargetNames[mTarget];
    end;
  end;
end;

class function TDpccReassignedNames.NormalizeTargets(const AText: string): string;
begin
  Result := TargetsText(ParseTargets(AText));
end;

class function TDpccReassignedNames.StyleOf(const AText: string): TDpccReassignedStyle;
var
  mStyle: TDpccReassignedStyle;
begin
  for mStyle := Low(TDpccReassignedStyle) to High(TDpccReassignedStyle) do
  begin
    if SameText(Trim(AText), cStyles[mStyle]) then
    begin
      Exit(mStyle);
    end;
  end;
  Result := TDpccReassignedStyle.Dotted;
end;

class function TDpccReassignedNames.TryColor(const AText: string; out AColor: TDpccColor): Boolean;
var
  mValue: Integer;
  mText: string;
begin
  AColor := 0;
  mText := Trim(AText);
  Result := (Length(mText) = 7) and (mText[1] = '#') and TryStrToInt('$' + Copy(mText, 2, 6), mValue);
  if Result then
  begin
    AColor := TDpccColorMath.FromHex(mText);
  end;
end;

class function TDpccReassignedNames.NormalizeColor(const AText: string): string;
var
  mColor: TDpccColor;
begin
  if TryColor(AText, mColor) then
  begin
    Result := TDpccColorMath.ToHex(mColor);
  end
  else
  begin
    Result := cThemeColor;
  end;
end;

end.
