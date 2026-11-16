unit dpcc.IDE.Foundation.About;

// Eintrag von dpcc im Startbildschirm (IOTASplashScreenServices) und im Info-Dialog (IOTAAboutBoxServices) der IDE:
// nur Text (Name, Version, Beschreibung), ohne Bild. Beide Dienste erwarten ein HBITMAP; dpcc übergibt 0.
// Seit S5 hat dpcc keine Bilder mehr (kein Symbol, keine Bildliste, kein Fenstersymbol).

interface

type
  TDpccIdeAbout = class
  public
    /// <summary>Startbildschirm und Info-Dialog anmelden; ein fehlender Dienst verhindert den anderen nicht.</summary>
    class procedure Register; static;
    /// <summary>Eintrag im Info-Dialog wieder entfernen (den Startbildschirm gibt es dann nicht mehr).</summary>
    class procedure Unregister; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  ToolsAPI,
  dpcc.Core.Product.Version,
  dpcc.Core.Diagnostics.Guard,
  dpcc.UI.Foundation.Strings;

const
  cNoBitmap = HBITMAP(0);

var
  AboutIndex: Integer = -1;
  SplashDone: Boolean;

function Title: string;
begin
  Result := TDpccFoundationStrings.Fmt(TDpccFoundationTextId.SymbolTitle, [TDpccPluginVersion.cVersion]);
end;

procedure AddSplash;
begin
  if SplashDone or (SplashScreenServices = nil) then
  begin
    Exit;
  end;
  SplashDone := True;
  SplashScreenServices.AddPluginBitmap(Title, cNoBitmap);
end;

procedure AddAbout;
var
  mServices: IOTAAboutBoxServices;
begin
  if (AboutIndex >= 0) or not Supports(BorlandIDEServices, IOTAAboutBoxServices, mServices) then
  begin
    Exit;
  end;
  AboutIndex := mServices.AddPluginInfo(Title, TDpccFoundationStrings.Text(TDpccFoundationTextId.SymbolDescription),
    cNoBitmap);
end;

{ TDpccIdeAbout }

class procedure TDpccIdeAbout.Register;
begin
  try
    AddSplash;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Status, E);
  end;
  try
    AddAbout;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Status, E);
  end;
end;

class procedure TDpccIdeAbout.Unregister;
var
  mAbout: IOTAAboutBoxServices;
begin
  if (AboutIndex >= 0) and Supports(BorlandIDEServices, IOTAAboutBoxServices, mAbout) then
  begin
    mAbout.RemovePluginInfo(AboutIndex);
  end;
  AboutIndex := -1;
end;

end.
