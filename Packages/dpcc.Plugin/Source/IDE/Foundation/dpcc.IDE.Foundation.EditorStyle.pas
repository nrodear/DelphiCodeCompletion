unit dpcc.IDE.Foundation.EditorStyle;

// Aussehen der dpcc-Fenster in der IDE (#411, #412, #445): Hell oder Dunkel
// nach dem aktiven IDE-Thema, ersatzweise nach der Windows-Einstellung
// „App-Modus“; Schrift aus den Editoroptionen; Pixeldichte des Monitors am
// Caret mal Zoom des Editors (aus der Caret-Höhe, TDpccScaling). Wird bei
// jedem Öffnen eines Fensters abgefragt, sodass Thema, Monitor und Zoom ohne
// Neustart wirken.
// Stufe der Darstellung (LOOK1): LookLevel aus der Einstellung PopupLook, Look = TDpccLook.From(ListColors,
// LookLevel); Apply setzt beides am Fenster.

interface

uses
  Winapi.Windows,
  System.Types,
  Vcl.Graphics,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette,
  dpcc.Core.Style.Look,
  dpcc.UI.Popup.Window;

type
  TDpccIdeStyle = class
  private const
    /// <summary>So lange (ms) gelten gelesene ListColors; Editor-Überlagerungen fragen sie je gezeichneter Zeile ab.
    /// </summary>
    cListColorsLifetime = 1000;
  private class var
    FListColors: TDpccColors;
    FListColorsTick: Cardinal;
    FListColorsKnown: Boolean;
    class function ReadListColors: TDpccColors; static;
  public
    /// <summary>Feste dpcc-Palette, hell oder dunkel nach IDE-Thema bzw. Windows; nur noch Rückfall für
    /// WindowColors ohne IDE-Thema. Alle Fenster und Editor-Überlagerungen nehmen seit S8 ListColors.</summary>
    class function Colors: TDpccColors; static;
    /// <summary>Fläche und Schrift wie Listen und Eingabefelder des IDE-Themas (clWindow/clWindowText), ohne
    /// Thema Colors. Colors nimmt vom Thema nur
    /// hell oder dunkel und setzt die feste Palette ein; deren dunkle Fläche liegt weit unter der des Themas.
    /// </summary>
    class function WindowColors: TDpccColors; static;
    /// <summary>Farben der Code-Insight-Liste der IDE (Strg+Leertaste, S3c): Die Liste malt mit dem Farbschema des
    /// Editors – Fläche = Hintergrund von „Plain text“, Namen = „Identifier“, Schlüsselwörter = „Reserved word“
    /// (Editor\Highlight unter dem Registry-Schlüssel der IDE, nur gelesen). Kommentare und Strings ebenso; Rand und
    /// Gedämpftes (auch die Art-Kennung, KindLabel, S8) daraus gemischt wie bei WindowColors. Ohne lesbares
    /// Farbschema WindowColors. Seit S8 nehmen alle dpcc-Fenster (Hover, Parameter-Hint, Tooltip) und die
    /// Editor-Überlagerungen sie, damit alles aussieht wie die Liste; eine Sekunde zwischengespeichert.</summary>
    class function ListColors: TDpccColors; static;
    /// <summary>Darstellung der Popups aus den Einstellungen (PopupLook, Optionsseite).</summary>
    class function LookLevel: TDpccLookLevel; static;
    /// <summary>Alle Farben der eingestellten Stufe: TDpccLook.From(ListColors, LookLevel); für Zeichner ohne
    /// Fenster (Editor-Überlagerungen). Fenster nehmen TDpccPopupWindow.Look.</summary>
    class function Look: TDpccLook; static;
    /// <summary>Farben (ListColors), Stufe (LookLevel), Editorschrift und Skalierung auf AWindow übertragen. ACaret:
    /// Caret-Rechteck in Bildschirmkoordinaten (Monitor und Zoom). Liefert eine Zeile für das Diagnoseprotokoll.
    /// </summary>
    class function Apply(AWindow: TDpccPopupWindow; const ACaret: TRect): string; static;
    /// <summary>Texthöhe der Editorschrift bei 96 dpi ohne Zoom (Bezug für Linienbreiten, #653).</summary>
    class function BaseTextHeight: Integer; static;
    /// <summary>ARect halb durchsichtig mit AColor überziehen; der Text darunter bleibt lesbar.</summary>
    class procedure Blend(ADC: HDC; const ARect: TRect; AColor: COLORREF; AAlpha: Byte); static;
    /// <summary>Hintergrund des Editors an X, Y; ersatzweise die Pinselfarbe der Zeichenfläche.</summary>
    class function SampleBack(ACanvas: TCanvas; AX, AY: Integer): TDpccColor; static;
  end;

implementation

uses
  System.SysUtils,
  System.Win.Registry,
  ToolsAPI,
  dpcc.Core.Style.Scaling,
  dpcc.IDE.Foundation.Settings;

function WindowsUsesLightApps: Boolean;
var
  mRegistry: TRegistry;
begin
  Result := True;
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if mRegistry.OpenKeyReadOnly('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize') and
      mRegistry.ValueExists('AppsUseLightTheme') then
    begin
      Result := mRegistry.ReadInteger('AppsUseLightTheme') <> 0;
    end;
  finally
    mRegistry.Free;
  end;
end;

/// <summary>Texthöhe der Schrift bei APPI ohne Zoom, in Gerätepixeln.</summary>
function TextHeightAt(const AFontName: string; AFontSize, APPI: Integer): Integer;
var
  mBitmap: TBitmap;
begin
  mBitmap := TBitmap.Create;
  try
    mBitmap.Canvas.Font.Name := AFontName;
    mBitmap.Canvas.Font.PixelsPerInch := APPI;
    mBitmap.Canvas.Font.Size := AFontSize;
    Result := mBitmap.Canvas.TextHeight('Wg');
  finally
    mBitmap.Free;
  end;
end;

{ TDpccIdeStyle }

class procedure TDpccIdeStyle.Blend(ADC: HDC; const ARect: TRect; AColor: COLORREF; AAlpha: Byte);
var
  mMemory: HDC;
  mBitmap, mOld: HBITMAP;
  mFunc: TBlendFunction;
begin
  if (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top) then
  begin
    Exit;
  end;
  mMemory := CreateCompatibleDC(ADC);
  mBitmap := CreateCompatibleBitmap(ADC, 1, 1);
  mOld := SelectObject(mMemory, mBitmap);
  try
    SetPixel(mMemory, 0, 0, AColor);
    mFunc.BlendOp := AC_SRC_OVER;
    mFunc.BlendFlags := 0;
    mFunc.SourceConstantAlpha := AAlpha;
    mFunc.AlphaFormat := 0;
    AlphaBlend(ADC, ARect.Left, ARect.Top, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top, mMemory, 0, 0, 1, 1,
      mFunc);
  finally
    SelectObject(mMemory, mOld);
    DeleteObject(mBitmap);
    DeleteDC(mMemory);
  end;
end;

class function TDpccIdeStyle.SampleBack(ACanvas: TCanvas; AX, AY: Integer): TDpccColor;
var
  mSample: COLORREF;
begin
  mSample := GetPixel(ACanvas.Handle, AX, AY);
  if mSample = CLR_INVALID then
  begin
    Result := TDpccColor(ColorToRGB(ACanvas.Brush.Color));
  end
  else
  begin
    Result := TDpccColor(mSample);
  end;
end;

class function TDpccIdeStyle.Colors: TDpccColors;
var
  mTheming: IOTAIDEThemingServices;
begin
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) and mTheming.IDEThemingEnabled then
  begin
    Exit(TDpccColors.ForBackground(TDpccColor(ColorToRGB(mTheming.StyleServices.GetSystemColor(clWindow)))));
  end;
  if WindowsUsesLightApps then
  begin
    Result := TDpccColors.Light;
  end
  else
  begin
    Result := TDpccColors.Dark;
  end;
end;

class function TDpccIdeStyle.WindowColors: TDpccColors;
var
  mTheming: IOTAIDEThemingServices;
begin
  if Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) and mTheming.IDEThemingEnabled then
  begin
    Exit(TDpccColors.ForWindow(TDpccColor(ColorToRGB(mTheming.StyleServices.GetSystemColor(clWindow))),
      TDpccColor(ColorToRGB(mTheming.StyleServices.GetSystemColor(clWindowText)))));
  end;
  Result := Colors;
end;

/// <summary>Farbe des Elements AElement im Farbschema des Editors: Vordergrund (AForeground) bzw. Hintergrund;
/// False ohne eigenen Wert (Vorgabe der IDE) oder ohne lesbaren Schlüssel.</summary>
function HighlightColor(const ABaseKey, AElement: string; AForeground: Boolean; out AColor: TDpccColor): Boolean;
const
  cValues: array[Boolean] of string = ('Background Color New', 'Foreground Color New');
  cDefaults: array[Boolean] of string = ('Default Background', 'Default Foreground');
var
  mRegistry: TRegistry;
begin
  Result := False;
  AColor := 0;
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if not mRegistry.OpenKeyReadOnly(ABaseKey + '\Editor\Highlight\' + AElement) or
      not mRegistry.ValueExists(cValues[AForeground]) then
    begin
      Exit;
    end;
    if mRegistry.ValueExists(cDefaults[AForeground]) and
      SameText(mRegistry.ReadString(cDefaults[AForeground]), 'True') then
    begin
      Exit;
    end;
    try
      AColor := TDpccColor(ColorToRGB(StringToColor(mRegistry.ReadString(cValues[AForeground]))));
      Result := True;
    except
      on EConvertError do
        Result := False;
    end;
  finally
    mRegistry.Free;
  end;
end;

class function TDpccIdeStyle.ListColors: TDpccColors;
var
  mNow: Cardinal;
begin
  // Kurz zwischengespeichert: Die Überlagerungen im Editor (Platzhalter, Vorschau) zeichnen Zeile für Zeile, das
  // Farbschema steht in der Registry. Nach einer Sekunde wird neu gelesen, sodass Änderungen ohne Neustart wirken.
  mNow := GetTickCount;
  if not FListColorsKnown or (mNow < FListColorsTick) or (mNow - FListColorsTick > cListColorsLifetime) then
  begin
    FListColors := ReadListColors;
    FListColorsTick := mNow;
    FListColorsKnown := True;
  end;
  Result := FListColors;
end;

class function TDpccIdeStyle.ReadListColors: TDpccColors;
var
  mServices: IOTAServices;
  mBaseKey: string;
  mBack, mText, mColor: TDpccColor;
begin
  Result := WindowColors;
  if not Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Exit;
  end;
  mBaseKey := mServices.GetBaseRegistryKey;
  if not HighlightColor(mBaseKey, 'Plain text', False, mBack) then
  begin
    Exit;
  end;
  if not HighlightColor(mBaseKey, 'Identifier', True, mText) and
    not HighlightColor(mBaseKey, 'Plain text', True, mText) then
  begin
    mText := Result.Text;
  end;
  Result := TDpccColors.ForWindow(mBack, mText);
  if HighlightColor(mBaseKey, 'Reserved word', True, mColor) then
  begin
    Result.Keyword := mColor;
  end;
  if HighlightColor(mBaseKey, 'Comment', True, mColor) then
  begin
    Result.Comment := mColor;
  end;
  if HighlightColor(mBaseKey, 'String', True, mColor) then
  begin
    Result.StringLiteral := mColor;
  end;
end;

class function TDpccIdeStyle.LookLevel: TDpccLookLevel;
begin
  Result := TDpccIdeSettings.Current.PopupLook;
end;

class function TDpccIdeStyle.Look: TDpccLook;
begin
  Result := TDpccLook.From(ListColors, LookLevel);
end;

class function TDpccIdeStyle.BaseTextHeight: Integer;
var
  mEditor: IOTAEditorServices;
begin
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditor) and (mEditor.EditOptions <> nil) then
  begin
    Result := TextHeightAt(mEditor.EditOptions.FontName, mEditor.EditOptions.FontSize, 96);
  end
  else
  begin
    Result := 16;
  end;
end;

class function TDpccIdeStyle.Apply(AWindow: TDpccPopupWindow; const ACaret: TRect): string;
var
  mEditor: IOTAEditorServices;
  mFontName: string;
  mFontSize, mMonitorPPI, mTextHeight: Integer;
  mZoom: Double;
begin
  AWindow.Colors := ListColors;
  AWindow.LookLevel := LookLevel;
  mFontName := AWindow.Font.Name;
  mFontSize := AWindow.Font.Size;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditor) and (mEditor.EditOptions <> nil) then
  begin
    mFontName := mEditor.EditOptions.FontName;
    mFontSize := mEditor.EditOptions.FontSize;
  end;
  mMonitorPPI := TDpccPopupWindow.MonitorPPI(ACaret.CenterPoint);
  mTextHeight := TextHeightAt(mFontName, mFontSize, mMonitorPPI);
  mZoom := TDpccScaling.ZoomFromCaret(ACaret.Height, mTextHeight);
  AWindow.SetScaling(mMonitorPPI, mZoom, mFontName, mFontSize);
  Result := Format('Darstellung: %s %d pt, Monitor %d dpi, Caret %d px, Text %d px, Zoom %.2f',
    [mFontName, mFontSize, mMonitorPPI, ACaret.Height, mTextHeight, mZoom], TFormatSettings.Invariant);
end;

end.
