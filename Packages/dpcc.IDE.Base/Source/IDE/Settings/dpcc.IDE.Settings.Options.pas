unit dpcc.IDE.Settings.Options;

// Meldet die Seite „dpcc“ unter Tools › Optionen › Drittanbieter an
// (INTAAddInOptions, #227) und verbindet sie mit den Einstellungen in der
// Registry. „Verlauf zurücksetzen“ leert die lernende Gewichtung (#418).
// Die Liste der angehefteten Favoriten (#458) kommt aus TDpccIdeFavorites; „Entfernen“ wirkt sofort.
// Die Unterseiten „Snippets“ und „Server“ gibt es seit S2 nicht mehr, die Seite „Index“ seit S4: Statt Kennzahlen,
// „Index löschen“ und „Index-Cache löschen“ (Befehle an den Server, die den Server auch startete) steht auf der Seite
// „Allgemein“ nur noch „Index neu aufbauen“ (Haken RestartIndex, dpcc.IDE.Settings.PageOptions).
// Completion-Schnitt: Unter Drittanbieter steht seit S2 nur noch „dpcc“ (die Optionsseite, gefiltert nach
// dpcc.Core.Settings.CompletionView); „Tastenkonflikte“ entfällt seit Rückbau R5, „Snippets“ und „Server“ seit S2.
// Übersicht, „Module“ und die Knoten je Package meldet dpcc nicht mehr an.
// Seit S7a ohne ShowSetting („Einstellungen dazu …“, #628; es gab keinen Aufrufer mehr), ohne Abschnitte der Module
// (#1455) und ohne „Leiste anpassen …“ der Editorleiste (#1101).

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
  dpcc.Core.Settings.History,
  dpcc.Core.Settings.NodeScope,
  dpcc.UI.Settings.Page,
  dpcc.UI.Settings.Page.Completion,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.IDE.Foundation.InsightSwitch,
  dpcc.IDE.Foundation.Settings;

type
  TDpccAddInOptions = class(TInterfacedObject, INTAAddInOptions)
  private
    FPage: TDpccSettingsPage;
    /// <summary>Knoten je Package (#1903): Besitzer, Überschrift im Baum ('dpcc.Module.Tests') und im Kopf.
    /// </summary>
    FScope: TDpccSettingsNodeScope;
    FCaption: string;
    FTitle: string;
    /// <summary>Stand beim Laden; gespeichert wird nur, was der Knoten daran geändert hat.</summary>
    FLoaded: TDpccPluginSettings;
  public
    constructor Create(const AScope: TDpccSettingsNodeScope; const ACaption, ATitle: string);
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
  /// <summary>Seite „dpcc“ (Completion-Schnitt: die Optionsseite selbst, ohne Übersicht und Module).</summary>
  Options: INTAAddInOptions;
  /// <summary>Gesetzt von Register, geleert von Unregister.</summary>
  Hooks: TDpccOptionsHooks;

{ TDpccAddInOptions }

function TDpccAddInOptions.GetArea: string;
begin
  // Leer: unter „Drittanbieter“, wie die Open Tools API empfiehlt.
  Result := '';
end;

constructor TDpccAddInOptions.Create(const AScope: TDpccSettingsNodeScope; const ACaption, ATitle: string);
begin
  inherited Create;
  FScope := AScope;
  FCaption := ACaption;
  FTitle := ATitle;
end;

function TDpccAddInOptions.GetCaption: string;
begin
  Result := FCaption;
end;

function TDpccAddInOptions.GetFrameClass: TCustomFrameClass;
begin
  Result := TDpccSettingsPage;
end;

procedure TDpccAddInOptions.FrameCreated(AFrame: TCustomFrame);
begin
  FPage := AFrame as TDpccSettingsPage;
  FPage.Part<TDpccSettingsCompletionPart>.OnResetHistory := Hooks.ResetHistory;
  TDpccPageOptions.ConnectFavorites(FPage);
  // „Index neu aufbauen“ (S4); startet keinen Server, der nicht läuft.
  TDpccPageOptions.ConnectRebuild(FPage, Hooks.RestartIndex);
  // Suchfeld über dem Baum (#1884): ohne Module nur Base. Andere Knoten gibt es seit S2 nicht mehr.
  FPage.Search.OnInstalled :=
    function(const ASwitch: string): Boolean
    begin
      Result := ASwitch = '';
    end;
  // Knoten je Package (#1903): nur, was diesem Knoten gehört.
  FPage.SetTitle(FTitle);
  FPage.ApplyScope(FScope);
  FLoaded := TDpccIdeSettings.Stored;
  FPage.LoadFrom(FLoaded);
end;

procedure TDpccAddInOptions.DialogClosed(Accepted: Boolean);
var
  mSettings: TDpccPluginSettings;
  mTarget: IDpccMemorySettingsStore;
begin
  try
    if Accepted and (FPage <> nil) then
    begin
      // Nur die Änderungen dieses Knotens: Ein anderer Knoten hat vielleicht schon gespeichert (#1903).
      mTarget := TDpccMemorySettingsStore.FromSettings(TDpccIdeSettings.Stored);
      TDpccSettingsMerge.Changes(TDpccMemorySettingsStore.FromSettings(FLoaded),
        TDpccMemorySettingsStore.FromSettings(FPage.CurrentSettings), mTarget);
      mSettings := TDpccIdeSettings.Stored;
      mSettings.Load(mTarget);
      mSettings.Normalize;
      TDpccIdeSettings.Update(mSettings);
    end;
    // Help Insight und Wert-Tooltip der IDE erst nach dem Dialog abgleichen: Mit OK
    // schreibt die IDE danach ihre Editoroptionen aus dem Speicher zurück, auch die Schalter,
    // die dpcc abgeschaltet hatte. Sonst zeigt sie ab dem nächsten Start wieder beide Tooltips.
    // Die Strukturhervorhebung der IDE fasst dpcc seit S9 nicht mehr an.
    if Accepted then
    begin
      TDpccMainThread.ForceQueue(TDpccFeature.Settings,
        procedure
        begin
          TDpccGuard.Run(TDpccFeature.Settings,
            procedure
            begin
              TDpccIdeInsightSwitch.Sync;
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
    // Completion-Schnitt: nur die Seite „dpcc“ („Tastenkonflikte“ entfällt seit Rückbau R5, „Snippets“ und
    // „Server“ seit S2).
    Options := TDpccAddInOptions.Create(TDpccSettingsNodeScope.Base, 'dpcc',
      TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTitle));
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
