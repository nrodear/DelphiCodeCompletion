unit dpcc.UI.Settings.Page.Colors;

// Reiter „Farben“: eigene Paarfarben je Thema und ihre Reihenfolge.

interface

uses
  System.Classes,
  System.UITypes,
  Vcl.ExtCtrls,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette,
  dpcc.Core.Settings.Plugin,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Farben“: eigene Paarfarben je Thema und ihre Reihenfolge.</summary>
  TDpccSettingsColorsPart = class(TDpccSettingsPagePart)
  private
    // Eigene Paarfarben je Thema, eine Fläche je Tiefe.
    FLightSwatches: array[0..4] of TShape;
    FDarkSwatches: array[0..4] of TShape;
    // Eigene Farbe lokaler Routinen je Thema (#1788).
    FNestedLight: array[0..0] of TShape;
    FNestedDark: array[0..0] of TShape;
    /// <summary>Zeile mit Beschriftung und fünf Farbflächen.</summary>
    procedure AddSwatches(const ACaption: string; var ASwatches: array of TShape);
    procedure SwatchMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ResetColorsClick(Sender: TObject);
    class procedure ShowPairs(const ASwatches: array of TShape; const APairs: TDpccPairColors); static;
    /// <summary>Farben der Flächen als Einstellung; gleich der Palette = leer.</summary>
    class function PairsSetting(const ASwatches: array of TShape; const ADefault: TDpccPairColors): string; static;
    /// <summary>Farbe der Fläche als Einstellung; gleich ADefault = leer (#1788).</summary>
    class function ColorSetting(ASwatch: TShape; ADefault: TDpccColor): string; static;
  public
    procedure Build;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    procedure BindMarks; override;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.Dialogs,
  dpcc.UI.Settings.Page.Sheets,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings;

{ TDpccSettingsColorsPart }

procedure TDpccSettingsColorsPart.Build;
var
  mPanel: TWinControl;
  mTitle: TLabel;
  mButton: TButton;
begin
  // Eigene Paarfarben und deren Reihenfolge je Thema.
  AddSheet(TDpccTextId.SettingsTabColors);
  AddSwatches(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPairColorsLight), FLightSwatches);
  AddSwatches(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPairColorsDark), FDarkSwatches);
  AddSwatches(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNestedRoutineColorLight), FNestedLight);
  AddSwatches(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNestedRoutineColorDark), FNestedDark);
  mPanel := AddPanel(22);
  mTitle := TLabel.Create(FPage);
  mTitle.Parent := mPanel;
  mTitle.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPairColorsHint);
  mTitle.Left := 0;
  mTitle.Top := mTitle.ScaleValue(3);
  mTitle.Font.Color := clGrayText;
  mPanel := AddPanel(32);
  mButton := TButton.Create(FPage);
  mButton.Parent := mPanel;
  mButton.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPairColorsReset);
  mButton.Left := 0;
  mButton.Top := mButton.ScaleValue(3);
  mButton.Width := mButton.ScaleValue(150);
  mButton.OnClick := ResetColorsClick;
  Attach(mPanel, FLightSwatches[0]);
end;

procedure TDpccSettingsColorsPart.BindMarks;
begin
  FPage.Marks.Bind(FLightSwatches[0], ['PairColorsLight']);
  FPage.Marks.Bind(FDarkSwatches[0], ['PairColorsDark']);
  FPage.Marks.Bind(FNestedLight[0], ['NestedRoutineColorLight']);
  FPage.Marks.Bind(FNestedDark[0], ['NestedRoutineColorDark']);
end;

procedure TDpccSettingsColorsPart.AddSwatches(const ACaption: string; var ASwatches: array of TShape);
var
  mPanel: TWinControl;
  mCaption: TLabel;
  mIndex: Integer;
begin
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(FPage);
  mCaption.Parent := mPanel;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(5);
  for mIndex := 0 to High(ASwatches) do
  begin
    ASwatches[mIndex] := TShape.Create(FPage);
    ASwatches[mIndex].Parent := mPanel;
    ASwatches[mIndex].SetBounds(cFieldLeft + mIndex * 34, 1, 28, 22);
    ASwatches[mIndex].Pen.Color := clGray;
    ASwatches[mIndex].Cursor := crHandPoint;
    ASwatches[mIndex].Hint := IntToStr(mIndex + 1);
    ASwatches[mIndex].ShowHint := True;
    ASwatches[mIndex].OnMouseDown := SwatchMouseDown;
  end;
end;

procedure TDpccSettingsColorsPart.SwatchMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  mDialog: TColorDialog;
begin
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mDialog := TColorDialog.Create(nil);
  try
    mDialog.Color := TShape(Sender).Brush.Color;
    mDialog.Options := mDialog.Options + [cdFullOpen];
    if mDialog.Execute then
    begin
      TShape(Sender).Brush.Color := mDialog.Color;
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TDpccSettingsColorsPart.ResetColorsClick(Sender: TObject);
begin
  ShowPairs(FLightSwatches, TDpccColors.Light.Pairs);
  ShowPairs(FDarkSwatches, TDpccColors.Dark.Pairs);
  FNestedLight[0].Brush.Color := TColor(TDpccColors.Light.NestedRoutine);
  FNestedDark[0].Brush.Color := TColor(TDpccColors.Dark.NestedRoutine);
end;

class procedure TDpccSettingsColorsPart.ShowPairs(const ASwatches: array of TShape; const APairs: TDpccPairColors);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ASwatches) do
  begin
    ASwatches[mIndex].Brush.Color := TColor(APairs[mIndex]);
  end;
end;

class function TDpccSettingsColorsPart.PairsSetting(const ASwatches: array of TShape;
  const ADefault: TDpccPairColors): string;
var
  mPairs: TDpccPairColors;
  mIndex: Integer;
begin
  for mIndex := 0 to High(mPairs) do
  begin
    mPairs[mIndex] := TDpccColor(ColorToRGB(ASwatches[mIndex].Brush.Color));
  end;
  Result := TDpccColors.PairsText(mPairs);
  if Result = TDpccColors.PairsText(ADefault) then
  begin
    Result := '';
  end;
end;

class function TDpccSettingsColorsPart.ColorSetting(ASwatch: TShape; ADefault: TDpccColor): string;
var
  mColor: TDpccColor;
begin
  mColor := TDpccColor(ColorToRGB(ASwatch.Brush.Color));
  Result := '';
  if mColor <> ADefault then
  begin
    Result := TDpccColorMath.ToHex(mColor);
  end;
end;

procedure TDpccSettingsColorsPart.Load(const ASettings: TDpccPluginSettings);
begin
  ShowPairs(FLightSwatches, TDpccColors.Light.WithPairs(ASettings.PairColorsLight).Pairs);
  ShowPairs(FDarkSwatches, TDpccColors.Dark.WithPairs(ASettings.PairColorsDark).Pairs);
  FNestedLight[0].Brush.Color := TColor(TDpccColors.Light.WithNestedRoutine(ASettings.NestedRoutineColorLight)
    .NestedRoutine);
  FNestedDark[0].Brush.Color := TColor(TDpccColors.Dark.WithNestedRoutine(ASettings.NestedRoutineColorDark)
    .NestedRoutine);
end;

procedure TDpccSettingsColorsPart.Save(var ASettings: TDpccPluginSettings);
begin
  ASettings.PairColorsLight := PairsSetting(FLightSwatches, TDpccColors.Light.Pairs);
  ASettings.PairColorsDark := PairsSetting(FDarkSwatches, TDpccColors.Dark.Pairs);
  ASettings.NestedRoutineColorLight := ColorSetting(FNestedLight[0], TDpccColors.Light.NestedRoutine);
  ASettings.NestedRoutineColorDark := ColorSetting(FNestedDark[0], TDpccColors.Dark.NestedRoutine);
end;

end.
