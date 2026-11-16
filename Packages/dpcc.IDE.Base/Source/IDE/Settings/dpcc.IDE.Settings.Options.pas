unit dpcc.IDE.Settings.Options;

// Meldet die Seite „dpcc“ unter Tools › Optionen › Drittanbieter an
// (INTAAddInOptions, #227) und verbindet sie mit den Einstellungen in der
// Registry. „Verlauf zurücksetzen“ leert die lernende Gewichtung (#418).
// Die Liste der angehefteten Favoriten (#458) kommt aus TDpccIdeFavorites; „Entfernen“ wirkt sofort.
// Die Unterseiten „Snippets“ und „Server“ gibt es seit S2 nicht mehr, die Seite „Index“ seit S4: Statt Kennzahlen,
// „Index löschen“ und „Index-Cache löschen“ (Befehle an den Server, die den Server auch startete) steht auf der Seite
// „Allgemein“ nur noch „Index neu aufbauen“ (Haken RestartIndex, dpcc.IDE.Settings.PageOptions).
// ShowSetting (#628, „Einstellungen dazu …“): öffnet Tools › Optionen, wählt
// die Seite „dpcc“ in der Baumansicht des Dialogs (soweit sie sich finden
// lässt) und zeigt dort die Einstellung mit markierter Zeile (Reveal).
// Seite Issue-Tracker: Den Abschnitt mit Verbindungen, Projekten, Abfragen
// und Prüfungen baut das Modul Tracker (#1455, dpcc.IDE.Tracker.Settings).
// ShowSetting mit Vorgabe („zuordnen …“ aus „Meine Issues“, #1261) reicht die
// Vorgabe nach dem Laden an den Abschnitt, dem die Einstellung gehört.
// Seite Versionsverwaltung: baut und verdrahtet das Modul Versionsverwaltung
// als Abschnitt (#1905); nach OK liest es settings.json über ApplySettings neu.
// ShowVcsServer reicht den Ordner als Vorgabe an dessen Abschnitt.
// Completion-Schnitt: Unter Drittanbieter steht seit S2 nur noch „dpcc“ (die Optionsseite, gefiltert nach
// dpcc.Core.Settings.CompletionView); „Tastenkonflikte“ entfällt seit Rückbau R5, „Snippets“ und „Server“ seit S2.
// Übersicht, „Module“ und die Knoten je Package meldet dpcc nicht mehr an. ShowSetting öffnet immer die Seite
// „dpcc“.

interface

uses
  System.SysUtils,
  dpcc.UI.EditorToolbar.Customize,
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
    /// <summary>dpcc-Befehle der Palette für „Leiste anpassen …“ der Editorleiste (#1101).</summary>
    ToolbarCommands: TFunc<TArray<TDpccToolbarCommandInfo>>;
  end;

  TDpccOptionsRegistration = class
  public
    class procedure Register(const AHooks: TDpccOptionsHooks); static;
    class procedure Unregister; static;
    /// <summary>Tools › Optionen öffnen und auf der Seite „dpcc“ die Einstellung AKey (Name der
    /// Plugin-Einstellung) zeigen und markieren (#628).</summary>
    class procedure ShowSetting(const AKey: string); overload; static;
    /// <summary>Wie ShowSetting; danach bekommt der Abschnitt des Moduls, dem AKey gehört, die Vorgabe AArgument
    /// (z. B. „zuordnen …“ mit dem Projekt, #1261).</summary>
    class procedure ShowSetting(const AKey, AArgument: string); overload; static;
    /// <summary>„Anmeldung am Server nötig – prüfen …“ (#1287): Tools › Optionen auf der Seite Versionsverwaltung
    /// öffnen und den Serverzugang für AFolder prüfen.</summary>
    class procedure ShowVcsServer(const AFolder: string); static;
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
  dpcc.IDE.Settings.OptionsDialog,
  dpcc.UI.Settings.Page.Completion,
  dpcc.UI.Settings.Page.Sections,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.IDE.Foundation.StructureSwitch,
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
  /// <summary>Einstellung, die die Seite „dpcc“ beim nächsten Anlegen zeigen soll (#628); '' ohne.</summary>
  PendingReveal: string;
  /// <summary>Vorgabe zu PendingReveal für den Abschnitt eines Moduls (#1455); '' ohne.</summary>
  PendingArgument: string;
  /// <summary>Rückfall, solange der modale Dialog offen ist: wählt die Seite „dpcc“ im Baum.</summary>
  Selector: TDpccOptionsSelector;

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
  // „Einstellungen dazu …“ (#628): gewünschte Zeile zeigen.
  if PendingReveal <> '' then
  begin
    FPage.Reveal(PendingReveal);
  end;
  TDpccPageOptions.ConnectFavorites(FPage, Hooks.ToolbarCommands);
  // „Index neu aufbauen“ (S4); startet keinen Server, der nicht läuft.
  TDpccPageOptions.ConnectRebuild(FPage, Hooks.RestartIndex);
  TDpccPageOptions.ConnectTransfer(FPage);
  TDpccPageOptions.ConnectHelp(FPage);
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
  // Vorgabe für den Abschnitt eines Moduls (#1455), z. B. „zuordnen …“ aus „Meine Issues“: nach dem Laden.
  if (PendingReveal <> '') and (PendingArgument <> '') then
  begin
    FPage.Part<TDpccSettingsSectionsPart>.ShowSettingArgument(PendingReveal, PendingArgument);
  end;
end;

procedure TDpccAddInOptions.DialogClosed(Accepted: Boolean);
var
  mSettings: TDpccPluginSettings;
  mTarget: IDpccMemorySettingsStore;
begin
  PendingReveal := '';
  PendingArgument := '';
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
    // Strukturhervorhebung und Help Insight der IDE erst nach dem Dialog abgleichen: Mit OK
    // schreibt die IDE danach ihre Editoroptionen aus dem Speicher zurück, auch die Schalter,
    // die dpcc abgeschaltet hatte. Sonst zeigt sie ab dem nächsten Start wieder beide Tooltips.
    if Accepted then
    begin
      TDpccMainThread.ForceQueue(TDpccFeature.Settings,
        procedure
        begin
          TDpccGuard.Run(TDpccFeature.Settings,
            procedure
            begin
              TDpccIdeStructureSwitch.Sync;
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
  PendingReveal := '';
  PendingArgument := '';
  FreeAndNil(Selector);
end;

class procedure TDpccOptionsRegistration.ShowSetting(const AKey: string);
begin
  if Options = nil then
  begin
    Exit;
  end;
  PendingReveal := AKey;
  if Selector = nil then
  begin
    Selector := TDpccOptionsSelector.Create(
      function: Boolean
      begin
        Result := PendingReveal <> '';
      end);
  end;
  // Der Dialog ist modal: Der Zeitgeber wählt die Seite, während er offen ist (nur noch Rückfall).
  Selector.Start;
  try
    // Offizieller Weg: Dialog gleich auf der Seite „dpcc“ unter „Fremdhersteller“ (leere Area). Die Seite zeigt
    // beim Anlegen PendingReveal. Der Baum von Delphi 13 ist kein TTreeView mehr; die Suche darin fand nichts.
    TDpccIdeOptionsDialog.Open(Options.GetCaption);
  finally
    // Modal: Hier ist der Dialog wieder zu. Nicht gefunden oder geschlossen: nichts mehr vormerken.
    if Selector <> nil then
    begin
      Selector.Stop;
    end;
    PendingReveal := '';
  end;
end;

class procedure TDpccOptionsRegistration.ShowSetting(const AKey, AArgument: string);
begin
  PendingArgument := AArgument;
  try
    ShowSetting(AKey);
  finally
    PendingArgument := '';
  end;
end;

class procedure TDpccOptionsRegistration.ShowVcsServer(const AFolder: string);
begin
  // Der Abschnitt der Versionsverwaltung nimmt den Ordner als Vorgabe zu vcs.projects (#1905).
  ShowSetting('VcsProjects', AFolder);
end;

end.
