unit dpcc.IDE.Foundation.DockWindow;

// Gemeinsame Verwaltung der dpcc-Dockfenster (#879) über
// INTAServices.CreateDockableForm: Ergebnisfenster, dpcc-Diagnose,
// Lesezeichen, dpcc-Start.
// - Die IDE gibt Dockfenster auch selbst frei (Entladen des Packages,
//   Desktop-Wechsel, Beenden). FreeNotification auf Form UND Frame setzt die
//   Zeiger zurück; Show legt dann neu an statt einen toten Frame zu benutzen.
// - Das X versteckt die Form, angedockt oft samt Dock-Gastgeber (Reiterseite,
//   Dock-Fenster). Form.Show allein bringt sie dann nicht zurück; Reveal macht
//   die ganze Gastgeberkette sichtbar und wählt die Reiterseite.
// - Persistent: RegisterDockableForm, damit die IDE das Fenster im Desktop
//   speichert und beim Laden selbst anlegt; die Form kommt dann über
//   FrameCreated herein. Registrieren muss früh geschehen (Register des
//   Experten), sonst kennt die IDE beim Laden des Start-Desktops die Kennung
//   noch nicht.
// Die Entscheidungen ohne VCL/OTA liegen in dpcc.Core.Dock.Plan (getestet).
// ApplyIdeTheme: Thema der IDE auf den Inhalt eines dpcc-Fensters, beim
// Anlegen und bei jedem Themenwechsel. ApplyTheme färbt nur Steuerelemente
// ohne Style-Hook (Labels, Panels); Listen, Felder, Combos und Kästchen
// zeichnet der VCL-Stil, den sie über StyleName vom Elternteil erben. Die
// geerbte Kette kann nach einem Themenwechsel noch den alten Stil liefern
// (Fenster bleiben hell bzw. dunkel). Deshalb steht der Stil der IDE ausdrücklich an der
// Wurzel des dpcc-Fensters, alle Kinder erben; ein geänderter Name legt die
// Fenster mit dem neuen Stil neu an. Liefert die Wurzel danach trotzdem einen
// anderen Stil, steht die Kette im Protokoll.
// OnFrameCreated meldet jeden neu angelegten Frame mit der Kennung des Fensters; so hängen andere Teile von
// Base (F1-Hilfe, #1886) etwas an, ohne dass die Grundlage sie kennt.

interface

uses
  Winapi.Messages,
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  ToolsAPI,
  dpcc.UI.Foundation.WndProcHook;

type
  TDpccIdeDockWindow = class(TComponent)
  private
    FDock: INTACustomDockableForm;
    FRegistered: Boolean;
    FForm: TCustomForm;
    FFrame: TCustomFrame;
    /// <summary>Eingehängte Fensterprozedur der Form (WM_CREATE beim Ab- und Andocken); nil ohne Form.</summary>
    FWndHook: TDpccWndProcHook;
    /// <summary>Formen aller dpcc-Dockfenster: Nur sie bekommen das Thema auch an der Form (schwebend).
    /// </summary>
    class var FDockForms: TArray<TCustomForm>;
    class var FOnFrameCreated: TProc<string, TCustomFrame>;
    class function IsDockForm(AForm: TCustomForm): Boolean; static;
    /// <summary>Thema der IDE an der Form: Grund per ApplyTheme, bei dunklem Thema eine dunkle Titelleiste von
    /// Windows. Kein VCL-Stil an der Form: Der zeichnete die Titelleiste selbst und verlor beim Ziehen die
    /// Schaltflächen.</summary>
    class procedure ThemeForm(AForm: TCustomForm); static;
    /// <summary>Dunkle Titelleiste (DWM), solange das IDE-Thema dunkel ist; schwebend sichtbar.</summary>
    class procedure ApplyDarkCaption(AForm: TCustomForm); static;
    procedure FormWndProc(var AMessage: TMessage);
    procedure SetForm(AForm: TCustomForm);
    procedure FreeForm;
    procedure Reveal;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    /// <summary>APersistent: bei der IDE registrieren (Desktop speichern/laden).</summary>
    constructor Create(const ADock: INTACustomDockableForm; APersistent: Boolean); reintroduce;
    /// <summary>Abmelden und die Form freigeben, falls sie noch lebt.</summary>
    destructor Destroy; override;
    /// <summary>Aus INTACustomDockableForm.FrameCreated aufrufen: merkt Frame und Form.</summary>
    procedure FrameCreated(AFrame: TCustomFrame);
    /// <summary>Fenster zeigen, bei Bedarf (neu) anlegen; ACreated: neu angelegt. False ohne Frame.</summary>
    function Show(out ACreated: Boolean): Boolean;
    /// <summary>Lebende Form oder nil.</summary>
    function Form: TCustomForm;
    /// <summary>Lebender Frame oder nil (nil auch, wenn die Form schon weg ist).</summary>
    function Frame: TCustomFrame;
    /// <summary>Wirklich zu sehen: Form und alle Gastgeber sichtbar, Reiterseite aktiv.</summary>
    function Shown: Boolean;
    procedure Hide;
    /// <summary>Thema der IDE auf AControl anwenden (beim Anlegen und bei jedem Themenwechsel).</summary>
    class procedure ApplyIdeTheme(AControl: TWinControl); static;
    /// <summary>Rückruf für jeden neuen Frame (Kennung des Fensters, Frame); nur im Hauptthread.</summary>
    class property OnFrameCreated: TProc<string, TCustomFrame> read FOnFrameCreated write FOnFrameCreated;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Dwmapi,
  Vcl.Graphics,
  Vcl.Themes,
  Vcl.ComCtrls,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Dock.Plan;

type
  // Zugriff auf das geschützte Color von TCustomForm.
  TFormAccess = class(TCustomForm);

{ TDpccIdeDockWindow }

constructor TDpccIdeDockWindow.Create(const ADock: INTACustomDockableForm; APersistent: Boolean);
var
  mServices: INTAServices;
begin
  inherited Create(nil);
  FDock := ADock;
  if APersistent and Supports(BorlandIDEServices, INTAServices, mServices) then
  begin
    mServices.RegisterDockableForm(FDock);
    FRegistered := True;
  end;
end;

destructor TDpccIdeDockWindow.Destroy;
var
  mServices: INTAServices;
begin
  if FRegistered and Supports(BorlandIDEServices, INTAServices, mServices) then
  begin
    mServices.UnregisterDockableForm(FDock);
  end;
  FRegistered := False;
  FreeForm;
  FDock := nil;
  inherited;
end;

procedure TDpccIdeDockWindow.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if Operation <> opRemove then
  begin
    Exit;
  end;
  if AComponent = FFrame then
  begin
    FFrame := nil;
  end;
  if AComponent = FForm then
  begin
    // Die IDE hat die Form freigegeben; ihr Frame ist mit ihr gegangen.
    SetForm(nil);
    FFrame := nil;
  end;
end;

class function TDpccIdeDockWindow.IsDockForm(AForm: TCustomForm): Boolean;
var
  mForm: TCustomForm;
begin
  Result := False;
  if AForm = nil then
  begin
    Exit;
  end;
  for mForm in FDockForms do
  begin
    if mForm = AForm then
    begin
      Exit(True);
    end;
  end;
end;

procedure TDpccIdeDockWindow.SetForm(AForm: TCustomForm);
var
  mIndex: Integer;
begin
  if AForm = FForm then
  begin
    Exit;
  end;
  if FForm <> nil then
  begin
    FForm.RemoveFreeNotification(Self);
    // Liegt eine fremde Prozedur darüber, bleibt der Haken als Durchreicher in deren Kette; Unhook kennzeichnet
    // das Entladen dann als unsicher (Protokoll, Diagnose, Neustart).
    TDpccWndProcHook.Unhook(FWndHook);
    for mIndex := High(FDockForms) downto 0 do
    begin
      if FDockForms[mIndex] = FForm then
      begin
        Delete(FDockForms, mIndex, 1);
      end;
    end;
  end;
  FForm := AForm;
  if FForm <> nil then
  begin
    FForm.FreeNotification(Self);
    if not IsDockForm(FForm) then
    begin
      FDockForms := FDockForms + [FForm];
    end;
    // Beim Ab- und Andocken legt die IDE das Fenster neu an; die Titelleiste muss dann neu dunkel werden.
    FWndHook := TDpccWndProcHook.Create(FForm, FormWndProc);
    ThemeForm(FForm);
  end;
end;

procedure TDpccIdeDockWindow.FrameCreated(AFrame: TCustomFrame);
var
  mParentForm: TCustomForm;
begin
  if AFrame = nil then
  begin
    Exit;
  end;
  if (FFrame <> nil) and (FFrame <> AFrame) then
  begin
    FFrame.RemoveFreeNotification(Self);
  end;
  if (FFrame <> AFrame) and Assigned(FOnFrameCreated) and (FDock <> nil) then
  begin
    FOnFrameCreated(FDock.GetIdentifier, AFrame);
  end;
  FFrame := AFrame;
  FFrame.FreeNotification(Self);
  // Legt die IDE die Form selbst an (Desktop laden), kennen wir sie nur über den Frame.
  if AFrame.Owner is TCustomForm then
  begin
    mParentForm := TCustomForm(AFrame.Owner);
  end
  else
  begin
    mParentForm := GetParentForm(AFrame, False);
  end;
  if mParentForm <> nil then
  begin
    SetForm(mParentForm);
  end;
end;

procedure TDpccIdeDockWindow.FreeForm;
var
  mOld: TCustomForm;
begin
  mOld := FForm;
  if FFrame <> nil then
  begin
    FFrame.RemoveFreeNotification(Self);
  end;
  FFrame := nil;
  SetForm(nil);
  // Nur freigeben, was noch lebt: Hat die IDE die Form schon zerstört, ist Old hier nil.
  mOld.Free;
end;

function TDpccIdeDockWindow.Show(out ACreated: Boolean): Boolean;
var
  mServices: INTAServices;
  mHasServices: Boolean;
  mStep: TDpccDockStep;
  mCreated: TCustomForm;
begin
  ACreated := False;
  mHasServices := Supports(BorlandIDEServices, INTAServices, mServices);
  mStep := TDpccDockPlan.ShowStep(mHasServices, FForm <> nil, FFrame <> nil);
  if mStep = TDpccDockStep.Unavailable then
  begin
    Exit(False);
  end;
  if mStep = TDpccDockStep.RecreateForm then
  begin
    FreeForm;
  end;
  if mStep <> TDpccDockStep.RevealForm then
  begin
    // FrameCreated läuft schon während CreateDockableForm und setzt Frame und Form.
    mCreated := mServices.CreateDockableForm(FDock);
    if mCreated = nil then
    begin
      Exit(False);
    end;
    SetForm(mCreated);
    ACreated := True;
  end;
  Reveal;
  Result := Frame <> nil;
end;

procedure TDpccIdeDockWindow.Reveal;
var
  mHost: TWinControl;
  mSheet: TTabSheet;
begin
  if FForm = nil then
  begin
    Exit;
  end;
  FForm.Visible := True;
  // Angedockt: Reiterseite wählen und versteckte Gastgeber (Dock-Fenster, Leisten) wieder zeigen.
  mHost := FForm.Parent;
  while mHost <> nil do
  begin
    if mHost is TTabSheet then
    begin
      mSheet := TTabSheet(mHost);
      if mSheet.PageControl <> nil then
      begin
        mSheet.PageControl.ActivePage := mSheet;
      end;
    end
    else if not mHost.Visible then
    begin
      mHost.Visible := True;
    end;
    mHost := mHost.Parent;
  end;
  FForm.BringToFront;
end;

function TDpccIdeDockWindow.Form: TCustomForm;
begin
  Result := FForm;
end;

function TDpccIdeDockWindow.Frame: TCustomFrame;
begin
  Result := nil;
  if TDpccDockPlan.FrameUsable(FForm <> nil, FFrame <> nil) then
  begin
    Result := FFrame;
  end;
end;

function TDpccIdeDockWindow.Shown: Boolean;
var
  mHosts: TArray<Boolean>;
  mHost: TWinControl;
begin
  if FForm = nil then
  begin
    Exit(False);
  end;
  mHosts := nil;
  mHost := FForm.Parent;
  while mHost <> nil do
  begin
    mHosts := mHosts + [mHost.Visible];
    mHost := mHost.Parent;
  end;
  Result := TDpccDockPlan.Shown(FForm.Visible, mHosts);
end;

procedure TDpccIdeDockWindow.Hide;
begin
  if FForm <> nil then
  begin
    FForm.Hide;
  end;
end;

class procedure TDpccIdeDockWindow.ApplyIdeTheme(AControl: TWinControl);
var
  mTheming: IOTAIDEThemingServices;
  mStyle: TCustomStyleServices;

  procedure ResetColors(AParent: TWinControl);
  var
    mIndex: Integer;
    mChild: TControl;
  begin
    for mIndex := 0 to AParent.ControlCount - 1 do
    begin
      mChild := AParent.Controls[mIndex];
      if mChild is TListView then
      begin
        TListView(mChild).Color := clWindow;
        TListView(mChild).Font.Color := clWindowText;
      end
      else if mChild is TTreeView then
      begin
        TTreeView(mChild).Color := clWindow;
        TTreeView(mChild).Font.Color := clWindowText;
      end;
      if mChild is TWinControl then
      begin
        ResetColors(TWinControl(mChild));
      end;
    end;
  end;

  procedure Inherit(AParent: TWinControl);
  var
    mIndex: Integer;
    mChild: TControl;
  begin
    for mIndex := 0 to AParent.ControlCount - 1 do
    begin
      mChild := AParent.Controls[mIndex];
      mChild.StyleName := '';
      if mChild is TWinControl then
      begin
        Inherit(TWinControl(mChild));
      end;
    end;
  end;

  function Chain: string;
  var
    mControl: TControl;
  begin
    Result := '';
    mControl := AControl;
    while mControl <> nil do
    begin
      Result := Result + Format(' < %s "%s"', [mControl.ClassName, mControl.StyleName]);
      mControl := mControl.Parent;
    end;
  end;

begin
  if (AControl = nil) or not Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) or
    not mTheming.IDEThemingEnabled then
  begin
    Exit;
  end;
  ResetColors(AControl);
  mTheming.ApplyTheme(AControl);
  mStyle := mTheming.StyleServices;
  if mStyle = nil then
  begin
    Exit;
  end;
  Inherit(AControl);
  if TStyleManager.Style[mStyle.Name] = mStyle then
  begin
    AControl.StyleName := mStyle.Name;
  end;
  if StyleServices(AControl) <> mStyle then
  begin
    TDpccGuard.Log(Format('Thema: %s zeichnet mit Stil "%s" statt "%s";%s', [AControl.ClassName,
      StyleServices(AControl).Name, mStyle.Name, Chain]));
  end;
  // Auch die Form eines dpcc-Dockfensters (schwebend sonst Titelleiste und Grund im Systemstil).
  if not (AControl is TCustomForm) and IsDockForm(GetParentForm(AControl, False)) then
  begin
    ThemeForm(GetParentForm(AControl, False));
  end;
end;

class procedure TDpccIdeDockWindow.ApplyDarkCaption(AForm: TCustomForm);
const
  // Fehlt in Delphi 12 (Winapi.Dwmapi): ab Windows 10 20H1.
  cDWMWA_USE_IMMERSIVE_DARK_MODE = 20;
var
  mTheming: IOTAIDEThemingServices;
  mWindow: TColor;
  mDark: BOOL;
begin
  if (AForm = nil) or not AForm.HandleAllocated or
    not Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) or not mTheming.IDEThemingEnabled or
    (mTheming.StyleServices = nil) then
  begin
    Exit;
  end;
  // Dunkel, wenn der Fenstergrund des IDE-Stils dunkel ist (Helligkeit nach Rec. 601).
  mWindow := ColorToRGB(mTheming.StyleServices.GetSystemColor(clWindow));
  mDark := (GetRValue(mWindow) * 299 + GetGValue(mWindow) * 587 + GetBValue(mWindow) * 114) div 1000 < 128;
  // Ältere Windows-Versionen kennen den Wert nicht und lehnen ihn ab: dann bleibt die Titelleiste hell.
  DwmSetWindowAttribute(AForm.Handle, cDWMWA_USE_IMMERSIVE_DARK_MODE, @mDark, SizeOf(mDark));
end;

procedure TDpccIdeDockWindow.FormWndProc(var AMessage: TMessage);
begin
  if FWndHook <> nil then
  begin
    FWndHook.CallOld(AMessage);
  end;
  // Neu angelegtes Fenster (Ab- oder Andocken): Titelleiste wieder dunkel.
  if (AMessage.Msg = WM_CREATE) and (FForm <> nil) then
    try
      ApplyDarkCaption(FForm);
    except
      on E: Exception do
        TDpccGuard.Log('Dunkle Titelleiste: ' + TDpccGuard.ErrorText(E));
    end;
end;

class procedure TDpccIdeDockWindow.ThemeForm(AForm: TCustomForm);
var
  mTheming: IOTAIDEThemingServices;
begin
  if (AForm = nil) or not Supports(BorlandIDEServices, IOTAIDEThemingServices, mTheming) or
    not mTheming.IDEThemingEnabled then
  begin
    Exit;
  end;
  try
    mTheming.ApplyTheme(AForm);
    // Der Frame ist durchsichtig und zeigt den Grund der Form; ApplyTheme setzt ihn nicht (schwebend hellgrau
    // unter weißer Schrift).
    if mTheming.StyleServices <> nil then
    begin
      TFormAccess(AForm).Color := mTheming.StyleServices.GetSystemColor(clBtnFace);
    end;
    ApplyDarkCaption(AForm);
  except
    // Thema ist Kosmetik: ein Fehler darf das Fenster nicht verhindern.
    on E: Exception do
      TDpccGuard.Log(Format('Thema der Form %s: %s: %s', [AForm.ClassName, E.ClassName,
        TDpccGuard.MessageText(E.Message)]));
  end;
end;

end.
