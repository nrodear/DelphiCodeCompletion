unit dpcc.IDE.Completion.Register;

// Wurzel von dpcc.IDE.Base seit Rückbau R5 (docs\Review\Rueckbau-Liste.md): dpcc ist nur noch Code Completion.
// Register meldet an, was dafür nötig ist, Unregister baut es in der Finalisierung rückwärts ab:
//   - Sicherung und Protokoll (TDpccGuard, Zeitlimit der Quellen, Sprache der Oberfläche), Hauptthread-Queue;
//     der Schreib-Thread der Protokolle (TDpccLogWriter, perf1) startet zuerst und endet nach der Zeile
//     „dpcc entladen“;
//   - Eintrag im Startbildschirm und im Info-Dialog (nur Text, ohne Bild);
//   - den Code Insight-Manager (IOTACodeInsightManager: Strg+Leertaste, Strg+Umschalt+Leertaste, Hover) mit
//     Server im IDE-Prozess (dpcc.IDE.Completion.Adapters);
//   - Formulare an den Server für FieldByName- und Komponenten-Completion (Designer-Notifier, #402/#461);
//   - den Speicher-Notifier für textDocument/didSave (ersetzt den Reloader);
//   - die Betriebsart (IDECHECK, TDpccIdeInsightSwitch): beim Start vor dem Manager nach dem gewählten
//     Code-Insight-Anbieter (DelphiLSP → dpcc aus und eigene Änderungen zurück; dpcc → an und die nötigen Schalter
//     der IDE gesetzt), die Wahl im Code-Insight-Dialog der IDE über den Manager (ManagerEnabled/Disabled) und beim
//     Beenden der zuletzt gewollte Stand noch einmal;
//   - den Hauptschalter ohne Neustart (#407): Springt er nach einer Änderung der Einstellungen um, startet der
//     Manager beim Einschalten Sitzung und Server bzw. schließt beim Ausschalten seine Fenster
//     (TDpccMasterSwitch);
//   - die Optionsseite „dpcc“ (seit S2 ohne die Unterseiten „Snippets“ und „Server“).
//   - das Ablaufprotokoll (LOG1, TDpccFlow): Ziel ist das Diagnoseprotokoll des Managers; „Ablauf protokollieren
//     (Log)“ bzw. Diagnose = 1 schaltet es beim Anmelden und nach OK ohne Neustart (ApplyFlow), mit einer Zeile im
//     Meldungsfenster samt Datei. Beim Abbau aus und ohne Ziel.
//   - Strg+Leertaste und Strg+Umschalt+Leertaste im Editor (Fix „Completion übernimmt wieder“): Delphi 13 ruft
//     Code Insight nur beim Manager auf, der in den Optionen für Delphi gewählt ist (Vorgabe DelphiLSP,
//     Borland.CodeInsight.LSP.Pascal), nie beim angemeldeten dpcc-Manager. Die zwei Tasten belegt dpcc deshalb
//     selbst, nur für Dateien, die dpcc bedient; sonst behält die IDE sie. Blieb die Liste von dpcc nach
//     Strg+Leertaste leer, geht ein zweites Strg+Leertaste an derselben Stelle an die IDE (L3). Ist dpcc selbst der
//     gewählte Manager, landete die durchgereichte Taste wieder bei dpcc (InvokeCodeCompletion): Dann bleibt sie bei
//     dpcc; ist die Liste der IDE schon offen, gehört die Taste ihr (L4, TDpccIdeList).
// Kein Hauptmenü, keine Kontextmenüs, keine Palette, keine weiteren Tasten, kein Statusfeld, keine Andockfenster,
// keine Hinweisfenster und kein Vectored Exception Handler mehr. Fehler stehen im Protokoll; dass der
// Server nach zwei gleichen Abstürzen angehalten ist, meldet eine Zeile im Meldungsfenster und eine Rückfrage
// „Server neu starten?“.
// Wächter des Hauptthreads (TDpccWatchdog, abgespeckt: nur Messung und Zeilen im dpcc.log, ohne Stapelabzug): nach
// der Grundausstattung angemeldet, beim Abbau direkt nach dem Abbruchsignal beendet, solange Protokoll und Fenster
// noch da sind.
// Abbau (#886): jeder Schritt für sich; eine Ausnahme lässt die folgenden nicht aus. Unregister läuft beim
// Zerstören des Hauptfensters (ExitWatch) oder in der Finalisierung, je nachdem, was zuerst kommt. Server-Start und
// -Stopp laufen im Hintergrund; der Schritt „Manager“ (Shutdown → ShutdownSession) wartet nach dem Abbruchsignal
// höchstens 5 s auf diese Threads, bevor Code der BPL entladen wird.

interface

/// <summary>dpcc in der IDE anmelden.</summary>
procedure Register;

implementation

uses
  Winapi.Windows,
  Winapi.PsAPI,
  System.SysUtils,
  System.Classes,
  System.UITypes,
  System.Win.Registry,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.Dialogs,
  ToolsAPI,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.Core.Localization.Language,
  dpcc.Core.Editor.Navigation,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Diagnostics.TimeLimit,
  dpcc.Core.Diagnostics.ExitWatch,
  dpcc.Core.Diagnostics.Teardown,
  dpcc.Core.Diagnostics.LogWriter,
  dpcc.Core.Diagnostics.Flow,
  dpcc.Core.Notifications.Contract,
  dpcc.Core.Notifications.Center,
  dpcc.Core.Notifications.Sources,
  dpcc.Core.Lsp.Session,
  dpcc.Core.Settings.MasterSwitch,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Foundation.About,
  dpcc.IDE.Foundation.InsightSwitch,
  dpcc.IDE.Settings.Options,
  dpcc.IDE.Completion.History,
  dpcc.IDE.Completion.Favorites,
  dpcc.IDE.Completion.Adapters,
  dpcc.IDE.Completion.SaveNotifier,
  dpcc.IDE.Completion.Leftovers,
  dpcc.IDE.Forms.Designer,
  dpcc.IDE.CodeInsight.Manager,
  dpcc.IDE.CodeInsight.Manager.Paths,
  dpcc.IDE.Foundation.Watchdog;

const
  cMessageGroup = 'dpcc';

var
  // Unregister lief schon: beim Zerstören des Hauptfensters, die finalization kommt danach oder gar nicht.
  Unregistered: Boolean;
  ExitWatch: TDpccExitWatch;
  ManagerIndex: Integer = -1;
  // Gehört der IDE (Schnittstellenzähler); gültig, solange er angemeldet ist.
  ManagerInstance: TDpccCodeInsightManager;
  // Eigene Referenz (#886): StopManager baut den Manager selbst ab, auch wenn die IDE ihn noch hält.
  ManagerRef: IInterface;
  Forms: TDpccIdeForms;
  SaveNotifier: TDpccSaveNotifier;
  // Beobachter der Benachrichtigungszentrale (angehaltener Server); -1 ohne.
  NoticeListener: Integer = -1;
  // Höchste schon gemeldete Kennung der Zentrale.
  NoticeSeen: Integer;
  // Zuletzt gesehener Stand des Hauptschalters (#407).
  MasterSwitch: TDpccMasterSwitch;
  // Tastenbelegung Strg+Leertaste/Strg+Umschalt+Leertaste (IOTAKeyboardServices); -1 ohne.
  KeysIndex: Integer = -1;
  // Zuletzt angewandter Stand von „Ablauf protokollieren (Log)“ (LOG1, ApplyFlow).
  FlowOn: Boolean;

{ Meldungen }

/// <summary>Zeile in der Meldungsansicht, Gruppe „dpcc“; nur im Hauptthread.</summary>
procedure MessageLine(const AText: string);
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mGroup := mMessages.GetGroup(cMessageGroup);
  if mGroup = nil then
  begin
    mGroup := mMessages.AddMessageGroup(cMessageGroup);
  end;
  mMessages.AddTitleMessage(AText, mGroup);
end;

/// <summary>Warnung der Sicherung (#493), etwa „Funktion abgeschaltet“: Protokoll und Meldungsansicht, nie als
/// Dialog; aus jedem Thread.</summary>
procedure GuardWarning(const AText: string);
var
  mText: string;
begin
  mText := AText;
  if ManagerInstance <> nil then
  begin
    ManagerInstance.Report(mText);
  end;
  TDpccMainThread.Queue(TDpccFeature.Status,
    procedure
    begin
      MessageLine(mText);
    end);
end;

/// <summary>dpcc.log nimmt nichts mehr an: nur über OutputDebugString (DebugView), aus dem Thread des Schreibers.
/// </summary>
procedure LogError(const AMessage: string);
begin
  if AMessage = '' then
  begin
    OutputDebugString(PChar('dpcc: Protokoll schreibt wieder'));
  end
  else
  begin
    OutputDebugString(PChar('dpcc: Protokoll gestört: ' + TDpccGuard.SafeMessage(AMessage)));
  end;
end;

/// <summary>Neuer Fehler des Servers mit Aktion (nach zwei gleichen Abstürzen angehalten, Aktion „Server neu
/// starten“): Zeile in der Meldungsansicht und Rückfrage für die erste Aktion. Fehler ohne Aktion schreibt der
/// Manager selbst in die Meldungsansicht.</summary>
procedure ShowServerNotice(const AEntry: IDpccNotification);
var
  mActions: TArray<TDpccNotificationAction>;
begin
  MessageLine('dpcc: ' + AEntry.Title + ' – ' + AEntry.Text);
  mActions := AEntry.Actions;
  if (Length(mActions) > 0) and Assigned(mActions[0].Run) and
    (MessageDlg(AEntry.Title + sLineBreak + sLineBreak + AEntry.Text + sLineBreak + sLineBreak +
    mActions[0].Caption + '?', mtError, [mbYes, mbNo], 0) = mrYes) then
  begin
    mActions[0].Run();
  end;
end;

/// <summary>Neue Einträge der Zentrale seit dem letzten Aufruf; nur im Hauptthread.</summary>
procedure CheckNotices;
var
  mEntry: IDpccNotification;
  mFresh: TArray<IDpccNotification>;
begin
  mFresh := nil;
  for mEntry in TDpccNotificationCenter.Default.Items(TDpccNotificationSources.cServer) do
  begin
    if mEntry.Id > NoticeSeen then
    begin
      NoticeSeen := mEntry.Id;
      if (mEntry.Severity = TDpccNotificationSeverity.Error) and (Length(mEntry.Actions) > 0) then
      begin
        mFresh := mFresh + [mEntry];
      end;
    end;
  end;
  for mEntry in mFresh do
  begin
    ShowServerNotice(mEntry);
  end;
end;

procedure StartNotices;
begin
  NoticeSeen := 0;
  NoticeListener := TDpccNotificationCenter.Default.AddListener(
    procedure
    begin
      // Die Zentrale ruft im Thread der Meldung.
      TDpccMainThread.Queue(TDpccFeature.Notifications, CheckNotices);
    end);
end;

procedure StopNotices;
begin
  if NoticeListener >= 0 then
  begin
    TDpccNotificationCenter.Default.RemoveListener(NoticeListener);
  end;
  NoticeListener := -1;
  TDpccNotificationCenter.ReleaseDefault;
end;

{ Sprache }

/// <summary>Sprache für bds.exe unter ARoot\Software\Embarcadero\Locales; '' ohne Eintrag.</summary>
function LocaleUnder(ARegistry: TRegistry; ARoot: HKEY): string;
var
  mNames: TStringList;
  mName: string;
begin
  Result := '';
  ARegistry.RootKey := ARoot;
  if not ARegistry.OpenKeyReadOnly('Software\Embarcadero\Locales') then
  begin
    Exit;
  end;
  mNames := TStringList.Create;
  try
    ARegistry.GetValueNames(mNames);
    for mName in mNames do
    begin
      if SameText(mName, ParamStr(0)) and (ARegistry.GetDataType(mName) = rdString) then
      begin
        Result := ARegistry.ReadString(mName);
      end;
    end;
  finally
    mNames.Free;
    ARegistry.CloseKey;
  end;
end;

/// <summary>Sprachkennung für bds.exe; wie die RTL beim Laden der Ressourcen zuerst HKCU, dann HKLM.</summary>
function RegisteredLanguage: string;
const
  cRoots: array[0..1] of HKEY = (HKEY_CURRENT_USER, HKEY_LOCAL_MACHINE);
var
  mRegistry: TRegistry;
  mRoot: HKEY;
begin
  Result := '';
  mRegistry := TRegistry.Create(KEY_READ);
  try
    for mRoot in cRoots do
    begin
      Result := LocaleUnder(mRegistry, mRoot);
      if Result <> '' then
      begin
        Exit;
      end;
    end;
  finally
    mRegistry.Free;
  end;
end;

/// <summary>Datei einer Ressourcen-DLL; für als Datendatei geladene Handles über GetMappedFileName.</summary>
function ResourceFileName(AInstance: HINST): string;
var
  mBuffer: array[0..MAX_PATH] of Char;
  mLength: DWORD;
begin
  Result := GetModuleName(AInstance);
  if Result = '' then
  begin
    mLength := GetMappedFileName(GetCurrentProcess, Pointer(AInstance and not HINST(3)), @mBuffer[0], MAX_PATH);
    SetString(Result, mBuffer, mLength);
  end;
end;

/// <summary>Endungen der Ressourcen-DLLs der geladenen IDE-Module (coreide370.de → „de“).</summary>
function ResourceCodes: TArray<string>;
var
  mModule: PLibModule;
  mCode: string;
begin
  Result := nil;
  mModule := LibModuleList;
  while mModule <> nil do
  begin
    if (mModule.ResInstance <> 0) and (mModule.ResInstance <> mModule.Instance) then
    begin
      mCode := Copy(ExtractFileExt(ResourceFileName(mModule.ResInstance)), 2, MaxInt);
      if mCode <> '' then
      begin
        Result := Result + [mCode];
      end;
    end;
    mModule := mModule.Next;
  end;
end;

/// <summary>Sprache der Oberfläche nach der IDE (#446); sie geht auch als locale an den Server (#1458).</summary>
procedure InstallLanguage;
var
  mLanguage: TDpccIdeLanguage;
begin
  mLanguage := TDpccIdeLanguage.Decide(ResourceCodes, RegisteredLanguage,
    (GetUserDefaultUILanguage and $3FF) = LANG_GERMAN);
  TDpccStrings.Language := mLanguage.Language;
  TDpccGuard.Log('Sprache der Oberfläche: ' + mLanguage.Describe);
end;

{ Manager }

procedure StartManager;
var
  mServices: IOTACodeInsightServices;
begin
  // Wahl im Code-Insight-Dialog der IDE → Betriebsart (IDECHECK).
  TDpccCodeInsightManager.OnProviderChoice :=
    procedure(ASelected: Boolean)
    begin
      TDpccIdeInsightSwitch.ProviderChosen(ASelected);
    end;
  if Supports(BorlandIDEServices, IOTACodeInsightServices, mServices) then
  begin
    ManagerInstance := TDpccCodeInsightManager.Create(CompletionAdapters);
    ManagerRef := ManagerInstance;
    ManagerIndex := mServices.AddCodeInsightManager(ManagerInstance);
  end;
end;

procedure StopManager;
var
  mServices: IOTACodeInsightServices;
begin
  TDpccCodeInsightManager.OnProviderChoice := nil;
  try
    if (ManagerIndex >= 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, mServices) then
    begin
      mServices.RemoveCodeInsightManager(ManagerIndex);
    end;
    ManagerIndex := -1;
    if ManagerInstance <> nil then
    begin
      // Nicht auf Destroy warten (#886): Hält die IDE den Manager noch (etwa wenn sie dpcc mitten im
      // Gruppen-Build entlädt), liefen sonst Sitzung, Server, Threads und Editor-Anbindungen nach dem Entladen weiter.
      ManagerInstance.Shutdown;
      if ManagerInstance.RefCount > 1 then
      begin
        TDpccGuard.Log(Format('Code-Insight-Manager wird nach dem Abmelden noch %d-mal von der IDE gehalten',
          [ManagerInstance.RefCount - 1]));
      end;
    end;
  finally
    ManagerInstance := nil;
    ManagerRef := nil;
  end;
end;

/// <summary>Welcher Code Insight-Manager bedient Delphi-Dateien? Eine Zeile ins Protokoll: Die IDE ruft nur den in
/// den Optionen gewählten (IOTACodeInsightServices.HandlesFile mit seiner Kennung), andere nie. Ist es dpcc, dazu
/// einmal je Sitzung der Hinweis im Meldungsfenster (NAV, TDpccProviderNotice).</summary>
procedure LogSelection;
const
  cSample = 'dpcc.pas';
var
  mServices: IOTACodeInsightServices;
  mIndex: Integer;
  mSelected: string;
begin
  if not Supports(BorlandIDEServices, IOTACodeInsightServices, mServices) then
  begin
    Exit;
  end;
  mSelected := '';
  for mIndex := 0 to mServices.CodeInsightManagerCount - 1 do
  begin
    if (mServices.CodeInsightManager[mIndex] <> nil) and
      mServices.HandlesFile(cSample, mServices.CodeInsightManager[mIndex].GetIDString) then
    begin
      mSelected := mServices.CodeInsightManager[mIndex].GetIDString;
    end;
  end;
  TDpccGuard.Log(Format('Code Insight für Delphi-Dateien: gewählt „%s“, dpcc an Index %d von %d',
    [mSelected, ManagerIndex, mServices.CodeInsightManagerCount]));
  if (ManagerInstance <> nil) and SameText(mSelected, ManagerInstance.GetIDString) and
    TDpccProviderNotice.TakeFirst then
  begin
    MessageLine(TDpccProviderNotice.Text(TDpccTextLanguage.Current));
  end;
end;

{ Tasten }

type
  /// <summary>Strg+Leertaste und Strg+Umschalt+Leertaste im Editor für dpcc. Technisch nötig: Delphi 13 leitet
  /// beide Tasten an den in den Optionen gewählten Code Insight-Manager (DelphiLSP) und fragt den angemeldeten
  /// dpcc-Manager nie. Bedient dpcc die Datei nicht (Hauptschalter aus, keine Delphi-Datei, Sicherung), bleibt die
  /// Taste bei der IDE; ebenso ein zweites Strg+Leertaste an derselben Stelle, wenn die Liste von dpcc leer blieb
  /// (L3, TDpccCompletionFallback).</summary>
  TDpccCompletionKeys = class(TNotifierObject, IOTAKeyboardBinding)
  private
    procedure Run(const AContext: IOTAKeyContext; ASignature: Boolean; var ABindingResult: TKeyBindingResult);
    procedure CompletionKey(const Context: IOTAKeyContext; KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
    procedure SignatureKey(const Context: IOTAKeyContext; KeyCode: TShortcut; var BindingResult: TKeyBindingResult);
  public
    function GetBindingType: TBindingType;
    function GetDisplayName: string;
    function GetName: string;
    procedure BindKeyboard(const BindingServices: IOTAKeyBindingServices);
  end;

function TDpccCompletionKeys.GetBindingType: TBindingType;
begin
  Result := btPartial;
end;

function TDpccCompletionKeys.GetDisplayName: string;
begin
  Result := 'dpcc Code Completion';
end;

function TDpccCompletionKeys.GetName: string;
begin
  Result := 'dpcc.CompletionKeys';
end;

procedure TDpccCompletionKeys.BindKeyboard(const BindingServices: IOTAKeyBindingServices);
begin
  BindingServices.AddKeyBinding([ShortCut(VK_SPACE, [ssCtrl])], CompletionKey, nil);
  BindingServices.AddKeyBinding([ShortCut(VK_SPACE, [ssCtrl, ssShift])], SignatureKey, nil);
end;

procedure TDpccCompletionKeys.Run(const AContext: IOTAKeyContext; ASignature: Boolean;
  var ABindingResult: TKeyBindingResult);
var
  mFileName: string;
begin
  ABindingResult := krUnhandled;
  try
    if (ManagerInstance = nil) or (AContext = nil) or (AContext.EditBuffer = nil) then
    begin
      Exit;
    end;
    mFileName := AContext.EditBuffer.FileName;
    if not ManagerInstance.HandlesFile(mFileName) then
    begin
      Exit;
    end;
    if ASignature then
    begin
      ManagerInstance.OpenSignature;
    end
    else if not ManagerInstance.OpenCompletion then
    begin
      // Zweites Strg+Leertaste nach leerem Ergebnis an derselben Stelle (L3): Mit krUnhandled läuft die nächste
      // Belegung der Taste, die der IDE; sie öffnet die Liste des gewählten Managers (DelphiLSP). Ebenso bei schon
      // offener Liste der IDE (L4): Sie bedient die Taste, dpcc öffnet keine zweite Liste.
      Exit;
    end;
    ABindingResult := krHandled;
  except
    on E: Exception do
    begin
      TDpccGuard.Log('Taste für Code Completion: ' + TDpccGuard.ErrorText(E));
    end;
  end;
end;

procedure TDpccCompletionKeys.CompletionKey(const Context: IOTAKeyContext; KeyCode: TShortcut;
  var BindingResult: TKeyBindingResult);
begin
  Run(Context, False, BindingResult);
end;

procedure TDpccCompletionKeys.SignatureKey(const Context: IOTAKeyContext; KeyCode: TShortcut;
  var BindingResult: TKeyBindingResult);
begin
  Run(Context, True, BindingResult);
end;

procedure StartKeys;
var
  mKeyboard: IOTAKeyboardServices;
begin
  LogSelection;
  if Supports(BorlandIDEServices, IOTAKeyboardServices, mKeyboard) then
  begin
    KeysIndex := mKeyboard.AddKeyboardBinding(TDpccCompletionKeys.Create);
  end;
end;

procedure StopKeys;
var
  mKeyboard: IOTAKeyboardServices;
begin
  try
    if (KeysIndex >= 0) and Supports(BorlandIDEServices, IOTAKeyboardServices, mKeyboard) then
    begin
      mKeyboard.RemoveKeyboardBinding(KeysIndex);
    end;
  finally
    KeysIndex := -1;
  end;
end;

/// <summary>Laufende Sitzung für den Designer-Notifier; startet keinen Server.</summary>
function RunningSession: TFunc<TLspSession>;
begin
  Result :=
    function: TLspSession
    begin
      Result := nil;
      if ManagerInstance <> nil then
      begin
        Result := ManagerInstance.RunningSession;
      end;
    end;
end;

function Reports: TProc<string>;
begin
  Result :=
    procedure(AText: string)
    begin
      if ManagerInstance <> nil then
      begin
        ManagerInstance.Report(AText);
      end;
    end;
end;

procedure StartForms;
begin
  Forms := TDpccIdeForms.Create(RunningSession(), Reports());
end;

procedure StopForms;
begin
  FreeAndNil(Forms);
end;

procedure StartSaveNotifier;
begin
  SaveNotifier := TDpccSaveNotifier.Create(
    procedure(AFileName: string)
    begin
      if ManagerInstance <> nil then
      begin
        ManagerInstance.NotifySaved(AFileName);
      end;
    end,
    // Geschlossene Datei: didClose an den Server (a1, Speicher-Optimierung Phase 2).
    procedure(AFileName: string)
    begin
      if ManagerInstance <> nil then
      begin
        ManagerInstance.NotifyClosed(AFileName);
      end;
    end);
end;

procedure StopSaveNotifier;
begin
  FreeAndNil(SaveNotifier);
end;

{ Einstellungen }

/// <summary>Betriebsart beim Start (IDECHECK): ist DelphiLSP gewählt, schaltet dpcc sich aus und dreht eigene
/// Änderungen zurück; ist dpcc gewählt, setzt es die nötigen Schalter der IDE. Vor dem Manager, damit er mit dem
/// richtigen Hauptschalter startet. Die Strukturhervorhebung der IDE fasst dpcc seit S9 gar nicht mehr an.</summary>
procedure ApplyIdeContext;
begin
  TDpccIdeInsightSwitch.ApplyAtStart;
end;

/// <summary>Beim Beenden von Delphi den zuletzt gewollten Stand erneut schreiben (die IDE kann ihn beim Speichern
/// ihrer Optionen überschrieben haben); beim bloßen Entladen des Packages nicht.</summary>
procedure IdeContextAtExit;
begin
  if Application.Terminated then
  begin
    TDpccIdeInsightSwitch.AtExit;
  end;
end;

/// <summary>Hauptschalter umgeschaltet (#407): Der Manager reagiert nach dem laufenden Ereignis (etwa erst nach dem
/// Schließen des Optionsdialogs) und nur, wenn der Schalter dann noch so steht; schnelles Hin- und Herschalten lässt
/// so nur den letzten Stand wirken. Beim Entladen verwirft TDpccMainThread.Stop den Eintrag.</summary>
procedure QueueMasterSwitch(AEnabled: Boolean);
const
  cStates: array[Boolean] of string = ('aus', 'an');
begin
  TDpccGuard.Log('Hauptschalter ' + cStates[AEnabled] + ' (ohne Neustart)');
  TDpccMainThread.ForceQueue(TDpccFeature.Settings,
    procedure
    begin
      if (ManagerInstance <> nil) and (TDpccIdeSettings.Current.Enabled = AEnabled) then
      begin
        ManagerInstance.MasterSwitchChanged(AEnabled);
      end;
    end);
end;

/// <summary>„Ablauf protokollieren (Log)“ (LOG1, DWORD Diagnose) anwenden, ohne Neustart: TDpccFlow ein- bzw.
/// ausschalten (wirkt auf jede folgende Zeile, auch auf die bisherigen Diagnosezeilen des Managers). Beim Umschalten
/// und beim Anmelden, wenn an: eine Zeile in dpcc.log und im Diagnoseprotokoll und im Meldungsfenster eine Zeile mit
/// der Datei bzw. „aus“. AStart: beim Anmelden.</summary>
procedure ApplyFlow(AStart: Boolean);
const
  cStates: array[Boolean] of string = ('aus', 'an');
var
  mOn: Boolean;
  mWhen: string;
begin
  mOn := TDpccIdeSettings.Current.Diagnose;
  TDpccFlow.Enabled := mOn;
  if (mOn = FlowOn) and not (AStart and mOn) then
  begin
    Exit;
  end;
  FlowOn := mOn;
  if AStart then
  begin
    mWhen := 'beim Anmelden';
  end
  else
  begin
    mWhen := 'nach OK, ohne Neustart';
  end;
  TDpccGuard.Log('Ablauf protokollieren: ' + cStates[mOn] + ' (' + mWhen + ')');
  TDpccCodeInsightPaths.Append('Ablauf protokollieren: ' + cStates[mOn] + ' (' + mWhen + ')');
  // Nach dem laufenden Ereignis (Optionsdialog, Anmelden; dann ist auch die Sprache gesetzt); beim Entladen verwirft
  // TDpccMainThread.Stop den Eintrag.
  TDpccMainThread.ForceQueue(TDpccFeature.Settings,
    procedure
    begin
      if mOn then
      begin
        MessageLine(TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsDiagnoseOn,
          [TDpccCodeInsightPaths.DiagnoseLog]));
      end
      else
      begin
        MessageLine(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDiagnoseOff));
      end;
    end);
end;

/// <summary>Beim Abbau: Ablaufprotokoll aus und Ziel lösen; die Methode des Ziels liegt in dieser BPL.</summary>
procedure StopFlow;
begin
  TDpccFlow.Enabled := False;
  TDpccFlow.SetSink(nil);
  FlowOn := False;
end;

procedure SettingsChanged;
begin
  // Klarnamen in dpcc.log nur ausdrücklich (#1478, diagnostics.log.names).
  TDpccGuard.SetLogNames(TDpccIdeSettings.Current.LogNames);
  // Ablauf protokollieren (LOG1): sofort, ohne Neustart.
  ApplyFlow(False);
  // Die Schalter der IDE gleicht seit IDECHECK nur noch TDpccIdeInsightSwitch ab (Start, OK, Wahl im Dialog).
  case MasterSwitch.Update(TDpccIdeSettings.Current.Enabled) of
    TDpccMasterSwitchChange.TurnedOn:
      QueueMasterSwitch(True);
    TDpccMasterSwitchChange.TurnedOff:
      QueueMasterSwitch(False);
  end;
end;

/// <summary>Optionsseite „dpcc“ (#227).</summary>
procedure RegisterOptions;
var
  mHooks: TDpccOptionsHooks;
begin
  mHooks := Default(TDpccOptionsHooks);
  mHooks.ResetHistory := TDpccIdeHistory.Reset;
  // „Index neu aufbauen“ der Einstellungsseite (S4): nur eine laufende Sitzung wird angehalten und neu gestartet;
  // kehrt sofort zurück, AClear läuft im Hintergrund (TDpccCodeInsightSession.RebuildIndex).
  mHooks.RestartIndex :=
    function(const AClear: TProc; const ADone: TProc<Boolean>): Boolean
    begin
      if ManagerInstance <> nil then
      begin
        Result := ManagerInstance.RebuildIndex(AClear, ADone);
      end
      else
      begin
        // Ohne Manager (selten): wie früher hier löschen, ohne Server.
        AClear();
        ADone(False);
        Result := True;
      end;
    end;
  TDpccOptionsRegistration.Register(mHooks);
end;

{ Anmelden und Abbau }

/// <summary>Schritt der Anmeldung für sich: Eine Ausnahme kostet nur diesen Teil und steht im Protokoll.</summary>
procedure Start(const AName: string; const AProc: TProc);
begin
  try
    AProc();
  except
    on E: Exception do
    begin
      TDpccGuard.Log(Format('Anmelden von %s fehlgeschlagen: %s', [AName, TDpccGuard.ErrorText(E)]));
    end;
  end;
end;

procedure InstallFoundation;
begin
  // Protokolle schreibt ein eigener Thread (perf1); wer protokolliert, reiht nur ein. Gestoppt als Letztes in Unregister.
  TDpccLogWriter.Shared.Start;
  TDpccGuard.RotatingLog.Writer := TDpccLogWriter.Shared;
  // Zeitlimit der Datenquellen seit S3 fest (Seite „Robustheit“ weg).
  TDpccTimeLimit.LimitMs := TDpccTimeLimit.cDefaultMs;
  TDpccGuard.SetLogNames(TDpccIdeSettings.Current.LogNames);
  // Ablaufprotokoll (LOG1): Zeilen wie jede Diagnosezeile über den Schreib-Thread; an, wenn Diagnose gesetzt ist.
  TDpccFlow.SetSink(
    procedure(const ALine: string)
    begin
      TDpccCodeInsightPaths.Append(ALine);
    end);
  FlowOn := False;
  ApplyFlow(True);
  TDpccGuard.OnWarning := GuardWarning;
  TDpccGuard.RotatingLog.OnError := LogError;
  InstallLanguage;
  // Startbildschirm und Info-Dialog, nur Text.
  TDpccIdeAbout.Register;
end;

procedure Unregister; forward;

procedure WatchIdeExit;
begin
  if (ExitWatch = nil) and (Application.MainForm <> nil) then
  begin
    ExitWatch := TDpccExitWatch.Create(Application.MainForm, Unregister);
  end;
end;

procedure Register;
begin
  Unregistered := False;
  WatchIdeExit;
  // Abbruchsignal eines früheren Entladens in derselben Sitzung zurücknehmen (#493).
  TDpccShutdown.Reset;
  // Einreihen in den Hauptthread wieder annehmen (nach einem früheren Unregister).
  TDpccMainThread.Start;
  InstallFoundation;
  // Wächter des Hauptthreads: misst Hänger, Dauer von Aktivitäten und Warten auf den Server (dpcc.log).
  Start('Watchdog', TDpccWatchdog.Start);
  Start('IdeContext', ApplyIdeContext);
  Start('Notices', StartNotices);
  Start('Manager', StartManager);
  Start('Keys', StartKeys);
  Start('Forms', StartForms);
  Start('SaveNotifier', StartSaveNotifier);
  // Ausgang für den Hauptschalter (#407): Stand beim Anmelden.
  MasterSwitch.Reset(TDpccIdeSettings.Current.Enabled);
  TDpccIdeSettings.OnChanged := SettingsChanged;
  Start('Options', RegisterOptions);
  TDpccGuard.Log('dpcc angemeldet (Code Completion)');
end;

/// <summary>Abbau rückwärts zur Anmeldung, jeder Schritt für sich (#886); die Zeile „dpcc entladen“ steht immer im
/// Protokoll, mit den fehlgeschlagenen Schritten (nur Name und Ausnahmeklasse).</summary>
procedure Unregister;
var
  mStartedAt: UInt64;
  mStopped: Boolean;
  mTeardown: TDpccTeardown;
begin
  if Unregistered then
  begin
    Exit;
  end;
  Unregistered := True;
  mStartedAt := TThread.GetTickCount64;
  mStopped := False;
  mTeardown := TDpccTeardown.Create;
  try
    // Zuerst das gemeinsame Abbruchsignal: Jeder Hintergrund-Thread hört auf zu warten (#493).
    TDpccShutdown.Signal;
    // Wächter zuerst beenden (begrenzt): Er schreibt ins Protokoll und antwortet über ein eigenes Fenster.
    mTeardown.Step('Watchdog', TDpccWatchdog.Stop);
    // Was jetzt noch wartet oder während des Abbaus eingereiht wird, liefe nach dem Entladen in nicht mehr
    // geladenem Code. Queue im Hauptthread läuft weiter sofort.
    mTeardown.Step('MainThread', TDpccMainThread.Stop);
    TDpccGuard.OnWarning := nil;
    TDpccGuard.OnTripped := nil;
    TDpccGuard.OnFailure := nil;
    TDpccGuard.RotatingLog.OnError := nil;
    TDpccIdeSettings.OnChanged := nil;
    mTeardown.Step('IdeContext', IdeContextAtExit);
    // Wartende Gegenprüfung nach der Wahl im Code-Insight-Dialog samt Timer.
    mTeardown.Step('InsightSwitch', TDpccIdeInsightSwitch.Release);
    mTeardown.Step('Options', TDpccOptionsRegistration.Unregister);
    mTeardown.Step('SaveNotifier', StopSaveNotifier);
    mTeardown.Step('Forms', StopForms);
    mTeardown.Step('Keys', StopKeys);
    mTeardown.Step('Manager', StopManager);
    mTeardown.Step('Notices', StopNotices);
    mTeardown.Step('History', TDpccIdeHistory.Release);
    mTeardown.Step('Favorites', TDpccIdeFavorites.Release);
    mTeardown.Step('About', TDpccIdeAbout.Unregister);
    mTeardown.Step('Settings', TDpccIdeSettings.Release);
    mTeardown.Step('Threads',
      procedure
      begin
        mStopped := TDpccTimeLimit.StopAll(TDpccShutdown.cStopMs);
      end);
    mTeardown.Step('Leftovers', FreeLeftovers);
    // Nach Manager und Threads: Keiner schreibt mehr Ablaufzeilen (LOG1).
    mTeardown.Step('Flow', StopFlow);
  finally
    TDpccGuard.Log(Format('dpcc entladen in %d ms; Hintergrund-Threads beendet: %s; Fehler beim Abbau: %s',
      [TThread.GetTickCount64 - mStartedAt, BoolToStr(mStopped, True), mTeardown.Summary]));
    // Ausstehende Protokollzeilen samt dieser begrenzt wegschreiben (perf1), bevor Packages entladen werden; danach
    // schreibt jeder Aufrufer wieder selbst.
    if TDpccLogWriter.Shared <> nil then
    begin
      TDpccLogWriter.Shared.Stop(TDpccShutdown.cStopMs);
    end;
  end;
end;

initialization

finalization
  Unregister;
  FreeAndNil(ExitWatch);

end.
