unit dpcc.UI.Popup.Window;

// Basis für Popup, Parameter-Hint und Tooltip von dpcc (#410): eigenes,
// selbst gezeichnetes Fenster, das dem Editor nie den Fokus nimmt. Caret, IME
// und Undo bleiben so beim Editor.
//   - WS_POPUP mit WS_EX_NOACTIVATE und WS_EX_TOOLWINDOW, Besitzer ist das
//     Hauptfenster der IDE; Schatten über CS_DROPSHADOW.
//   - WM_MOUSEACTIVATE liefert MA_NOACTIVATE: Klicks wählen, ohne zu aktivieren.
//   - Zeigen über SetWindowPos mit SWP_NOACTIVATE (wie THintWindow), nicht über Visible.
// Aussehen nach dem Entwurf (#411): Farben aus TDpccColors, Rahmen in
// Akzentfarbe, abgerundete Ecken (ab Windows 11 vom Fenstermanager mit
// Kantenglättung, sonst über eine Fensterregion). Mit FlatFrame (Hover-Tooltip seit S3b) flach wie ein Menü der
// IDE: eckig, dünner Rand in der Linienfarbe (Colors.Line) statt Akzent. Code (Namen, Signaturen)
// steht in der Editorschrift (Font), Beschriftungen in der UI-Schrift (UIFont).
// Maße (#412, #445): alle in logischen Pixeln (96 dpi), umgerechnet mit PPI =
// DPI des Monitors am Caret mal Zoom des Editors (SetScaling). So wachsen Schrift,
// Zeilen und Abstände gemeinsam.
// Barrierefreiheit (#447): Jedes Fenster ist ein UI-Automation-Element mit
// Rolle und Name; Announce lässt die Sprachausgabe einen Text vorlesen.
// Tasten bekommt das Fenster nie; der Editor leitet sie über den Tastatur-Hook
// weiter (dpcc.IDE).

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  dpcc.Core.Style.Color,
  dpcc.Core.Style.Palette,
  dpcc.UI.Popup.Accessibility,
  dpcc.Core.Diagnostics.Guard;

type
  TDpccPopupWindow = class(TCustomControl)
  private type
    /// <summary>UI-Automation-Element des Fensters (#447).</summary>
    TAccess = record
      Provider: IDpccRawElementProvider;
      /// <summary>Objekt hinter Provider, für Detach beim Schließen.</summary>
      Element: TDpccAccessibleElement;
      Role: Integer;
      Name: string;
      /// <summary>Zuletzt vorgelesener Text.</summary>
      Announced: string;
    end;

    /// <summary>Wer die Ecken rundet: der Fenstermanager (Windows 11) oder eine Fensterregion.</summary>
    TCorners = record
      ByWindowManager: Boolean;
      /// <summary>CreateWnd hat entschieden, wer die Ecken rundet; vorher keine Region setzen.</summary>
      Known: Boolean;
    end;
  private
    FColors: TDpccColors;
    FUIFont: TFont;
    FBorderColor: TDpccColor;
    FCorners: TCorners;
    FFlatFrame: Boolean;
    FPPI: Integer;
    FAccess: TAccess;
    FGuardFeature: TDpccFeature;
    function Accessible: IDpccRawElementProvider;
    /// <summary>WM_GETOBJECT, WM_MOUSEACTIVATE (MA_NOACTIVATE) und WM_NCHITTEST (HTCLIENT); False für alle
    /// übrigen Nachrichten.</summary>
    function HandleOwnMessage(var AMessage: TMessage): Boolean;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
    procedure SetColors(const AValue: TDpccColors);
    procedure SetBorderColor(AValue: TDpccColor);
    procedure SetFlatFrame(AValue: Boolean);
    procedure UpdateCorners;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    /// <summary>Alle Nachrichten geschützt (#493): Zeichnen, Maus, Tasten des Fensters.</summary>
    procedure WndProc(var Message: TMessage); override;
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure Resize; override;
    /// <summary>Rahmen in BorderColor, sofern nicht der Fenstermanager ihn zeichnet.</summary>
    procedure PaintBorder;
    /// <summary>Logische Pixel (96 dpi) auf den Monitor des Fensters umrechnen.</summary>
    function Scale(AValue: Integer): Integer;
    /// <summary>Gefülltes Rechteck mit abgerundeten Ecken (ARadius logisch).</summary>
    procedure FillRounded(const ARect: TRect; AColor: TDpccColor; ARadius: Integer);
    /// <summary>Umrandetes Rechteck mit abgerundeten Ecken, innen AFill (clNone = durchsichtig).</summary>
    procedure FrameRounded(const ARect: TRect; ALine: TDpccColor; ARadius: Integer; AFill: TColor); overload;
    /// <summary>Wie oben, innen durchsichtig (AFill = clNone).</summary>
    procedure FrameRounded(const ARect: TRect; ALine: TDpccColor; ARadius: Integer); overload;
    /// <summary>Rolle (UiaListControlType, UiaToolTipControlType) und Name für Screenreader.</summary>
    procedure SetAccessible(ARole: Integer; const AName: string);
    /// <summary>Element für UI Automation; Listen liefern hier eine TDpccAccessibleList mit Einträgen.</summary>
    function CreateAccessible(ARole: Integer; const AName: string): TDpccAccessibleElement; virtual;
    /// <summary>Objekt des Elements; nil, solange UI Automation nicht gefragt hat.</summary>
    property AccessibleObject: TDpccAccessibleElement read FAccess.Element;
  public
    /// <summary>Feature, dem Fehler des Fensters angerechnet werden (Sicherung, #493); die Randmarken setzen es
    /// je Ebene.</summary>
    property GuardFeature: TDpccFeature read FGuardFeature write FGuardFeature;
    /// <summary>Lässt einen Screenreader AText vorlesen; derselbe Text zweimal hintereinander nur einmal.</summary>
    procedure Announce(const AText: string);
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Zeigt das Fenster ohne Aktivierung an ABounds (Bildschirmkoordinaten).</summary>
    procedure ShowAt(const ABounds: TRect);
    procedure HidePopup;
    function IsShown: Boolean;
    /// <summary>Arbeitsbereich des Monitors, auf dem APoint liegt.</summary>
    class function WorkAreaAt(const APoint: TPoint): TRect; static;
    property Colors: TDpccColors read FColors write SetColors;
    /// <summary>Rahmenfarbe; Standard Akzent, im Fehlerzustand des Hints Fehlerfarbe.</summary>
    property BorderColor: TDpccColor read FBorderColor write SetBorderColor;
    /// <summary>Flach wie ein Menü der IDE: eckig, Rand in Colors.Line, BorderColor gilt dann nicht.</summary>
    property FlatFrame: Boolean read FFlatFrame write SetFlatFrame;
    /// <summary>Wirksame Pixel je Zoll: Monitor-DPI mal Zoom; Schriften in AFontName/AFontSize (Punkt).</summary>
    procedure SetScaling(AMonitorPPI: Integer; AZoom: Double; const AFontName: string; AFontSize: Integer);
    /// <summary>Pixel je Zoll des Monitors, auf dem APoint liegt.</summary>
    class function MonitorPPI(const APoint: TPoint): Integer; static;
    /// <summary>Wirksame Pixel je Zoll (Monitor-DPI mal Zoom).</summary>
    property PPI: Integer read FPPI;
    /// <summary>Schrift für Beschriftungen, folgt Font in der Größe.</summary>
    property UIFont: TFont read FUIFont;
    property Canvas;
    property Font;
  end;

/// <summary>TDpccColor als TColor.</summary>
function ToColor(AColor: TDpccColor): TColor;

implementation

uses
  dpcc.UI.Popup.Draw,
  // Meldet dpcc.UI bei TDpccPluginModules an (S7b, Reste beim Entladen).
  dpcc.UI.Foundation.Module,
  Winapi.DwmApi,
  System.Math,
  Vcl.Forms,
  Vcl.Themes;

const
  // Windows 11 (ab Build 22000); in älteren Winapi.DwmApi nicht deklariert.
  cDWMWA_WINDOW_CORNER_PREFERENCE = 33;
  cDWMWA_BORDER_COLOR = 34;
  cDWMWCP_DONOTROUND = 1;
  cDWMWCP_ROUNDSMALL = 3;
  cDWMWA_COLOR_NONE = DWORD($FFFFFFFE);
  cCornerRadius = 6;

function ToColor(AColor: TDpccColor): TColor;
begin
  // Eine Umwandlung für alle Popups.
  Result := dpcc.UI.Popup.Draw.ToColor(AColor);
end;

/// <summary>Farben passend zum aktiven VCL-Stil (in der IDE deren Thema).</summary>
function StyleColors: TDpccColors;
begin
  Result := TDpccColors.ForBackground(TDpccColor(ColorToRGB(StyleServices.GetSystemColor(clWindow))));
end;

{ TDpccPopupWindow }

constructor TDpccPopupWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  Visible := False;
  FUIFont := TFont.Create;
  FPPI := Screen.PixelsPerInch;
  FColors := StyleColors;
  FBorderColor := FColors.Accent;
  Perform(CM_FONTCHANGED, 0, 0);
end;

destructor TDpccPopupWindow.Destroy;
begin
  FUIFont.Free;
  inherited Destroy;
end;

function TDpccPopupWindow.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, FPPI, 96);
end;

procedure TDpccPopupWindow.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.Style := WS_POPUP;
  // Nicht TOPMOST: Als Fenster im Besitz der IDE bleibt das Popup über ihr, liegt aber nicht über
  // Dialogen und Fenstern wie „Units suchen“, die danach geöffnet werden.
  Params.ExStyle := WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW or CS_SAVEBITS;
  // Besitzer: Hauptfenster der IDE, damit das Popup mit ihr minimiert wird und über ihr bleibt.
  if Application.MainFormHandle <> 0 then
  begin
    Params.WndParent := Application.MainFormHandle;
  end
  else
  begin
    Params.WndParent := Application.Handle;
  end;
end;

procedure TDpccPopupWindow.CreateWnd;
var
  mPreference: DWORD;
begin
  inherited CreateWnd;
  // Windows 11: runde Ecken mit Kantenglättung und Rahmen vom Fenstermanager.
  mPreference := cDWMWCP_ROUNDSMALL;
  FCorners.ByWindowManager := Succeeded(DwmSetWindowAttribute(Handle, cDWMWA_WINDOW_CORNER_PREFERENCE,
    @mPreference, SizeOf(mPreference)));
  FCorners.Known := True;
  UpdateCorners;
end;

procedure TDpccPopupWindow.DestroyWnd;
begin
  FCorners.Known := False;
  if FAccess.Provider <> nil then
  begin
    // Erst lösen: Elemente, die UI Automation noch hält, fragen das Fenster dann nicht mehr.
    FAccess.Element.Detach;
    FAccess.Element := nil;
    TDpccAccessibility.Release(WindowHandle);
    FAccess.Provider := nil;
  end;
  inherited DestroyWnd;
end;

procedure TDpccPopupWindow.WndProc(var Message: TMessage);
begin
  try
    if not HandleOwnMessage(Message) then
    begin
      inherited WndProc(Message);
    end;
  except
    on E: Exception do
      TDpccGuard.Report(FGuardFeature, E);
  end;
end;

procedure TDpccPopupWindow.SetAccessible(ARole: Integer; const AName: string);
begin
  FAccess.Role := ARole;
  FAccess.Name := AName;
end;

function TDpccPopupWindow.CreateAccessible(ARole: Integer; const AName: string): TDpccAccessibleElement;
begin
  Result := TDpccAccessibleElement.Create(Handle, ARole, AName);
end;

function TDpccPopupWindow.Accessible: IDpccRawElementProvider;
begin
  if (FAccess.Provider = nil) and (FAccess.Role <> 0) and HandleAllocated then
  begin
    FAccess.Element := CreateAccessible(FAccess.Role, FAccess.Name);
    FAccess.Provider := FAccess.Element;
  end;
  Result := FAccess.Provider;
end;

function TDpccPopupWindow.HandleOwnMessage(var AMessage: TMessage): Boolean;
begin
  Result := True;
  case AMessage.Msg of
    WM_GETOBJECT:
      begin
        AMessage.Result := TDpccAccessibility.Answer(Handle, AMessage.WParam, AMessage.LParam, Accessible);
        // Nicht für UI Automation: wie bisher die VCL antworten lassen.
        Result := AMessage.Result <> 0;
      end;
    // Klicks wählen, ohne zu aktivieren.
    WM_MOUSEACTIVATE:
      AMessage.Result := MA_NOACTIVATE;
    WM_NCHITTEST:
      AMessage.Result := HTCLIENT;
  else
    Result := False;
  end;
end;

procedure TDpccPopupWindow.Announce(const AText: string);
begin
  if (AText = FAccess.Announced) or not IsShown then
  begin
    Exit;
  end;
  FAccess.Announced := AText;
  TDpccAccessibility.Announce(Accessible, AText);
end;

procedure TDpccPopupWindow.UpdateCorners;
var
  mBorder, mPreference: DWORD;
begin
  // Schon während inherited CreateWnd kommt WM_SIZE; eine Region mit der Größe von dann bliebe sonst stehen.
  if not HandleAllocated or not FCorners.Known then
  begin
    Exit;
  end;
  if FFlatFrame then
  begin
    // Flach: eckig, ohne Rahmen des Fenstermanagers und ohne Region; den Rand zeichnet PaintBorder.
    if FCorners.ByWindowManager then
    begin
      mPreference := cDWMWCP_DONOTROUND;
      DwmSetWindowAttribute(Handle, cDWMWA_WINDOW_CORNER_PREFERENCE, @mPreference, SizeOf(mPreference));
      mBorder := cDWMWA_COLOR_NONE;
      DwmSetWindowAttribute(Handle, cDWMWA_BORDER_COLOR, @mBorder, SizeOf(mBorder));
    end;
    SetWindowRgn(Handle, 0, IsWindowVisible(Handle));
    Exit;
  end;
  if FCorners.ByWindowManager then
  begin
    mBorder := DWORD(FBorderColor);
    DwmSetWindowAttribute(Handle, cDWMWA_BORDER_COLOR, @mBorder, SizeOf(mBorder));
  end
  else
  begin
    // Ältere Windows-Versionen: Region mit runden Ecken; das Fenster übernimmt sie.
    SetWindowRgn(Handle, CreateRoundRectRgn(0, 0, Width + 1, Height + 1, Scale(2 * cCornerRadius),
      Scale(2 * cCornerRadius)), IsWindowVisible(Handle));
  end;
end;

procedure TDpccPopupWindow.Resize;
begin
  inherited Resize;
  if not FCorners.ByWindowManager and not FFlatFrame then
  begin
    UpdateCorners;
  end;
end;

procedure TDpccPopupWindow.CMFontChanged(var Message: TMessage);
begin
  inherited;
  if FUIFont = nil then
  begin
    Exit;
  end;
  // UI-Schrift der IDE, etwas kleiner als die Editorschrift (Entwurf: 12 zu 13 px).
  FUIFont.Name := Screen.MessageFont.Name;
  FUIFont.PixelsPerInch := Font.PixelsPerInch;
  FUIFont.Height := MulDiv(Font.Height, 12, 13);
  FUIFont.Charset := Font.Charset;
end;

procedure TDpccPopupWindow.SetColors(const AValue: TDpccColors);
begin
  FColors := AValue;
  FBorderColor := FColors.Accent;
  UpdateCorners;
  Invalidate;
end;

procedure TDpccPopupWindow.SetBorderColor(AValue: TDpccColor);
begin
  if FBorderColor = AValue then
  begin
    Exit;
  end;
  FBorderColor := AValue;
  UpdateCorners;
  Invalidate;
end;

procedure TDpccPopupWindow.SetFlatFrame(AValue: Boolean);
begin
  if FFlatFrame = AValue then
  begin
    Exit;
  end;
  // Nur vor dem ersten Zeigen umschalten (Konstruktor): zurück zu runden Ecken setzt UpdateCorners nicht.
  FFlatFrame := AValue;
  UpdateCorners;
  Invalidate;
end;

procedure TDpccPopupWindow.FillRounded(const ARect: TRect; AColor: TDpccColor; ARadius: Integer);
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(AColor);
  Canvas.Pen.Style := psClear;
  // Bei psClear zeichnet RoundRect ein Pixel kleiner; deshalb +1.
  Canvas.RoundRect(ARect.Left, ARect.Top, ARect.Right + 1, ARect.Bottom + 1, Scale(2 * ARadius),
    Scale(2 * ARadius));
  Canvas.Pen.Style := psSolid;
end;

procedure TDpccPopupWindow.FrameRounded(const ARect: TRect; ALine: TDpccColor; ARadius: Integer);
begin
  FrameRounded(ARect, ALine, ARadius, clNone);
end;

procedure TDpccPopupWindow.FrameRounded(const ARect: TRect; ALine: TDpccColor; ARadius: Integer;
  AFill: TColor);
begin
  if AFill = clNone then
  begin
    Canvas.Brush.Style := bsClear;
  end
  else
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := AFill;
  end;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := ToColor(ALine);
  Canvas.RoundRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, Scale(2 * ARadius), Scale(2 * ARadius));
  Canvas.Brush.Style := bsSolid;
end;

procedure TDpccPopupWindow.PaintBorder;
begin
  // Flach: dünner Rand in der Linienfarbe, eckig.
  if FFlatFrame then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(FColors.Line);
    Canvas.FrameRect(ClientRect);
    Exit;
  end;
  // Unter Windows 11 zeichnet der Fenstermanager den Rahmen (DWMWA_BORDER_COLOR).
  if FCorners.ByWindowManager then
  begin
    Exit;
  end;
  FrameRounded(ClientRect, FBorderColor, cCornerRadius);
end;

procedure TDpccPopupWindow.ShowAt(const ABounds: TRect);
begin
  HandleNeeded;
  // Erst Größe, dann ohne Aktivierung zeigen; Visible bleibt False wie bei THintWindow.
  SetBounds(ABounds.Left, ABounds.Top, ABounds.Width, ABounds.Height);
  // SWP_NOOWNERZORDER: Ohne das sortiert Windows die ganze Gruppe der Fenster mit demselben Owner (IDE-
  // Hauptfenster) um und schickt dabei jedem ihrer Threads eine Nachricht. Das IME-Fenster des Parser-Threads
  // der IDE gehört dazu; wartet der Thread gerade, hängt die IDE ohne Meldung (Klick in den Editor).
  SetWindowPos(Handle, HWND_TOP, ABounds.Left, ABounds.Top, ABounds.Width, ABounds.Height,
    SWP_NOACTIVATE or SWP_SHOWWINDOW or SWP_NOOWNERZORDER);
  Invalidate;
end;

procedure TDpccPopupWindow.HidePopup;
begin
  FAccess.Announced := '';
  if HandleAllocated and IsWindowVisible(Handle) then
  begin
    ShowWindow(Handle, SW_HIDE);
  end;
end;

function TDpccPopupWindow.IsShown: Boolean;
begin
  Result := HandleAllocated and IsWindowVisible(Handle);
end;

procedure TDpccPopupWindow.SetScaling(AMonitorPPI: Integer; AZoom: Double; const AFontName: string;
  AFontSize: Integer);
begin
  FPPI := Max(48, Round(AMonitorPPI * AZoom));
  if AFontName <> '' then
  begin
    Font.Name := AFontName;
  end;
  Font.PixelsPerInch := FPPI;
  // Erst nach PixelsPerInch: Size rechnet mit der neuen Dichte in die Höhe um.
  Font.Size := AFontSize;
  UpdateCorners;
end;

class function TDpccPopupWindow.MonitorPPI(const APoint: TPoint): Integer;
var
  mMonitor: TMonitor;
begin
  mMonitor := Screen.MonitorFromPoint(APoint, mdNearest);
  if mMonitor <> nil then
  begin
    Result := mMonitor.PixelsPerInch;
  end
  else
  begin
    Result := Screen.PixelsPerInch;
  end;
end;

class function TDpccPopupWindow.WorkAreaAt(const APoint: TPoint): TRect;
var
  mMonitor: TMonitor;
begin
  mMonitor := Screen.MonitorFromPoint(APoint, mdNearest);
  if mMonitor <> nil then
  begin
    Result := mMonitor.WorkareaRect;
  end
  else
  begin
    Result := Screen.WorkAreaRect;
  end;
end;

end.
