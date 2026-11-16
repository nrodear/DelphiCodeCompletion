unit dpcc.UI.Popup.Window;

// Basis für Popup, Parameter-Hint und Tooltip von dpcc (#410): eigenes,
// selbst gezeichnetes Fenster, das dem Editor nie den Fokus nimmt. Caret, IME
// und Undo bleiben so beim Editor.
//   - WS_POPUP mit WS_EX_NOACTIVATE und WS_EX_TOOLWINDOW, Besitzer ist das
//     Hauptfenster der IDE; Schatten über CS_DROPSHADOW.
//   - WM_MOUSEACTIVATE liefert MA_NOACTIVATE: Klicks wählen, ohne zu aktivieren.
//   - Zeigen über SetWindowPos mit SWP_NOACTIVATE (wie THintWindow), nicht über Visible.
// Aussehen (seit S8 für alle Fenster gleich, wie der Hover-Tooltip): Farben aus TDpccColors, flach wie ein Menü
// der IDE – eckig (unter Windows 11 die Rundung des Fenstermanagers ausgeschaltet), dünner Rand in der
// Linienfarbe (Colors.Line). Den früheren runden Weg mit Akzentrahmen gibt es nicht mehr. Code (Namen, Signaturen)
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
  private
    FColors: TDpccColors;
    FUIFont: TFont;
    FPPI: Integer;
    FAccess: TAccess;
    FGuardFeature: TDpccFeature;
    function Accessible: IDpccRawElementProvider;
    /// <summary>WM_GETOBJECT, WM_MOUSEACTIVATE (MA_NOACTIVATE) und WM_NCHITTEST (HTCLIENT); False für alle
    /// übrigen Nachrichten.</summary>
    function HandleOwnMessage(var AMessage: TMessage): Boolean;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
    procedure SetColors(const AValue: TDpccColors);
    /// <summary>Eckig und ohne Rahmen des Fenstermanagers (Windows 11); den Rand zeichnet PaintBorder.</summary>
    procedure SquareCorners;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    /// <summary>Alle Nachrichten geschützt (#493): Zeichnen, Maus, Tasten des Fensters.</summary>
    procedure WndProc(var Message: TMessage); override;
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    /// <summary>Dünner, eckiger Rand in Colors.Line.</summary>
    procedure PaintBorder;
    /// <summary>Logische Pixel (96 dpi) auf den Monitor des Fensters umrechnen.</summary>
    function Scale(AValue: Integer): Integer;
    /// <summary>Gefülltes, eckiges Rechteck.</summary>
    procedure FillBox(const ARect: TRect; AColor: TDpccColor);
    /// <summary>Eckiger Rahmen von 1 px in ALine, innen durchsichtig.</summary>
    procedure FrameBox(const ARect: TRect; ALine: TDpccColor);
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
  cDWMWA_COLOR_NONE = DWORD($FFFFFFFE);

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
begin
  inherited CreateWnd;
  SquareCorners;
end;

procedure TDpccPopupWindow.DestroyWnd;
begin
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

procedure TDpccPopupWindow.SquareCorners;
var
  mBorder, mPreference: DWORD;
begin
  // Windows 11 rundet Popups sonst selbst und zeichnet einen eigenen Rand; ältere Versionen tun beides nicht.
  // Schlägt der Aufruf fehl (Windows 10), bleibt das Fenster ohnehin eckig.
  mPreference := cDWMWCP_DONOTROUND;
  if Succeeded(DwmSetWindowAttribute(Handle, cDWMWA_WINDOW_CORNER_PREFERENCE, @mPreference,
    SizeOf(mPreference))) then
  begin
    mBorder := cDWMWA_COLOR_NONE;
    DwmSetWindowAttribute(Handle, cDWMWA_BORDER_COLOR, @mBorder, SizeOf(mBorder));
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
  Invalidate;
end;

procedure TDpccPopupWindow.FillBox(const ARect: TRect; AColor: TDpccColor);
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(AColor);
  Canvas.FillRect(ARect);
end;

procedure TDpccPopupWindow.FrameBox(const ARect: TRect; ALine: TDpccColor);
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(ALine);
  Canvas.FrameRect(ARect);
end;

procedure TDpccPopupWindow.PaintBorder;
begin
  FrameBox(ClientRect, FColors.Line);
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
