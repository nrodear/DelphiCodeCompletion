unit dpcc.IDE.Settings.Options;

// Meldet die Seite „dpcc“ unter Tools › Optionen › Drittanbieter an
// (INTAAddInOptions, #227) und verbindet sie mit den Einstellungen in der
// Registry. „Verlauf zurücksetzen“ leert die lernende Gewichtung (#418).
// Seit OPT1 eine einzige Seite ohne Unterseiten, Baum, Suche und Knoten je Package: FrameCreated lädt die gespeicherten
// Einstellungen (TDpccIdeSettings.Current), OK schreibt die Werte der Seite darüber und speichert (Registry und für
// index.extraSourceFolders settings.json); seit OPT2 nur noch genau diese Werte. Die Liste der angehefteten Favoriten (#458) gibt es nicht mehr.
// Die Unterseiten „Snippets“ und „Server“ gibt es seit S2 nicht mehr, die Seite „Index“ seit S4: Statt Kennzahlen,
// „Index löschen“ und „Index-Cache löschen“ (Befehle an den Server, die den Server auch startete) steht auf der Seite
// „Allgemein“ nur noch „Index neu aufbauen“ (Haken RestartIndex, dpcc.IDE.Settings.PageOptions).
// Completion-Schnitt: Unter Drittanbieter steht seit S2 nur noch „dpcc“ (die Optionsseite, gefiltert nach
// dpcc.Core.Settings.CompletionView); „Tastenkonflikte“ entfällt seit Rückbau R5, „Snippets“ und „Server“ seit S2.
// Übersicht, „Module“ und die Knoten je Package meldet dpcc nicht mehr an.
// Seit S7a ohne ShowSetting („Einstellungen dazu …“, #628; es gab keinen Aufrufer mehr), ohne Abschnitte der Module
// (#1455) und ohne „Leiste anpassen …“ der Editorleiste (#1101).
// Seit LOG1 „Ablauf protokollieren (Log)“: FrameCreated liest den DWORD Diagnose frisch (von Hand gesetzt gilt) und
// gibt der Seite die Protokolldatei für den Hint; die Wirkung nach OK schaltet dpcc.IDE.Completion.Register
// (SettingsChanged) ohne Neustart.

interface

uses
  System.SysUtils,
  dpcc.IDE.Settings.PageOptions;

type
  /// <summary>Was die Optionsseiten von anderen Features brauchen; setzt die Composition (die Seiten
  /// importieren Befehlszählung, Tipps, Code Insight-Manager und Vervollständigung nicht). Nicht gesetzte Haken
  /// bleiben ohne Wirkung bzw. liefern ''.</summary>
  TDpccOptionsHooks = record
    /// <summary>Lernende Gewichtung zurücksetzen (#418).</summary>
    ResetHistory: TProc;
    /// <summary>„Index neu aufbauen“ (S4): Caches bei angehaltener Sitzung löschen, laufende Sitzung neu starten.
    /// </summary>
    RestartIndex: TDpccIndexRestart;
  end;

  TDpccOptionsRegistration = class
  public
    class procedure Register(const AHooks: TDpccOptionsHooks); static;
    class procedure Unregister; static;
  end;

implementation

uses
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Diagnostics.Guard,
  Vcl.Forms,
  ToolsAPI,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.OperatingMode,
  dpcc.UI.Settings.Page,
  dpcc.IDE.Foundation.InsightSwitch,
  dpcc.IDE.Foundation.LspRedirect,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.CodeInsight.Manager.Paths;

type
  TDpccAddInOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TDpccSettingsPage;
  public
    function GetArea: string;
    function GetCaption: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    procedure DialogClosed(Accepted: Boolean);
    function ValidateContents: Boolean;
    function GetHelpContext: Integer;
    function IncludeInIDEInsight: Boolean;
  end;

var
  /// <summary>Seite „dpcc“ (seit OPT1 die einzige, ohne Unterseiten).</summary>
  Options: INTAAddInOptions;
  /// <summary>Gesetzt von Register, geleert von Unregister.</summary>
  Hooks: TDpccOptionsHooks;

{ TDpccAddInOptions }

function TDpccAddInOptions.GetArea: string;
begin
  // Leer: unter „Drittanbieter“, wie die Open Tools API empfiehlt.
  Result := '';
end;

function TDpccAddInOptions.GetCaption: string;
begin
  Result := 'dpcc';
end;

function TDpccAddInOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TDpccSettingsPage;
end;

procedure TDpccAddInOptions.FrameCreated(AFrame: TCustomFrame);
begin
  FPage := AFrame as TDpccSettingsPage;
  FPage.OnResetHistory := Hooks.ResetHistory;
  // „Index neu aufbauen“ (S4); startet keinen Server, der nicht läuft.
  TDpccPageOptions.ConnectRebuild(FPage, Hooks.RestartIndex);
  // Abschnitt „IDE“ (IDECHECK): Betriebsart, Anbieter, was dpcc gesetzt hat; nur gelesen.
  TDpccPageOptions.ConnectIdeStatus(FPage);
  // „Ablauf protokollieren (Log)“ (LOG1): Hint mit der Datei; ein seit dem Start von Hand gesetztes Diagnose = 1
  // erscheint angehakt.
  FPage.DiagnoseFile := TDpccCodeInsightPaths.DiagnoseLog;
  // Betriebsart Server nur mit installierter dpcc.LspServer.exe (Ort relativ zum Plugin).
  FPage.ServerExe := TDpccLspRedirectHook.ServerExe;
  TDpccIdeSettings.RefreshDiagnose;
  FPage.LoadFrom(TDpccIdeSettings.Current);
end;

procedure TDpccAddInOptions.DialogClosed(Accepted: Boolean);
var
  mSettings: TDpccPluginSettings;
  mWasMode, mPageMode: TDpccOperatingMode;
begin
  try
    mWasMode := TDpccIdeSettings.Current.Mode;
    mPageMode := mWasMode;
    if Accepted and (FPage <> nil) then
    begin
      // Gespeicherter Stand, darüber die Werte der Seite; was die Seite nicht zeigt, bleibt, wie es ist.
      mSettings := TDpccIdeSettings.Current;
      FPage.SaveTo(mSettings);
      TDpccIdeSettings.Update(mSettings);
      mPageMode := mSettings.Mode;
    end;
    // Betriebsart (IDECHECK) erst nach dem Dialog: Mit OK schreibt die IDE danach ihre Editoroptionen aus dem
    // Speicher zurück, auch die Schalter, die dpcc gesetzt hat. Plugin stellt den Anbieter der IDE auf dpcc, Aus
    // wieder zurück, Server auf DelphiLSP; ein Anbieterwechsel wirkt nach dem Neustart von Delphi. Die
    // Strukturhervorhebung der IDE fasst dpcc seit S9 nicht mehr an. Welche Betriebsart gilt, liest AfterOptions erst
    // beim Ausführen: Eine Wahl im Code-Insight-Dialog der IDE im selben OK steht vorher in der Warteschlange.
    if Accepted then
    begin
      TDpccMainThread.ForceQueue(TDpccFeature.Settings,
        procedure
        begin
          TDpccGuard.Run(TDpccFeature.Settings,
            procedure
            begin
              TDpccIdeInsightSwitch.AfterOptions(mWasMode, mPageMode);
            end);
        end);
    end;
    FPage := nil;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Settings, E);
  end;
end;

function TDpccAddInOptions.ValidateContents: Boolean;
begin
  Result := True;
end;

function TDpccAddInOptions.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TDpccAddInOptions.IncludeInIDEInsight: Boolean;
begin
  Result := True;
end;

{ TDpccOptionsRegistration }

class procedure TDpccOptionsRegistration.Register(const AHooks: TDpccOptionsHooks);
var
  mServices: INTAEnvironmentOptionsServices;
begin
  if (Options = nil) and Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, mServices) then
  begin
    Hooks := AHooks;
    // Nur die Seite „dpcc“ („Tastenkonflikte“ entfällt seit Rückbau R5, „Snippets“ und „Server“ seit S2, die
    // Unterseiten seit OPT1).
    Options := TDpccAddInOptions.Create;
    mServices.RegisterAddInOptions(Options);
  end;
end;

class procedure TDpccOptionsRegistration.Unregister;
var
  mServices: INTAEnvironmentOptionsServices;
begin
  if Supports(BorlandIDEServices, INTAEnvironmentOptionsServices, mServices) then
  begin
    if Options <> nil then
    begin
      mServices.UnregisterAddInOptions(Options);
    end;
  end;
  Options := nil;
  Hooks := Default(TDpccOptionsHooks);
end;

end.
