unit dpcc.IDE.Foundation.InsightSwitch;

// Betriebsart von dpcc in der IDE (Auftrag IDECHECK): dpcc entscheidet, in welchem Kontext es läuft, und stellt die
// Code-Insight-Schalter der IDE selbst. Die Regeln (ohne Registry, getestet) stehen in dpcc.Core.Settings.IdeCheck
// (TDpccIdeContext.Plan); hier werden sie gelesen (dpcc.IDE.Foundation.IdeSettingsCheck), ausgeführt und gemeldet.
//   - Beim Start von Delphi (ApplyAtStart, vor dem Anmelden des Managers): Ist DelphiLSP (oder ein anderer Anbieter)
//     gewählt, schaltet dpcc sich aus (Hauptschalter) und dreht zurück, was es selbst geändert hatte; die Werte, die
//     DelphiLSP braucht, prüft es nur (Protokoll). Ist dpcc gewählt, bleibt bzw. wird der Hauptschalter an, und dpcc
//     setzt die nötigen Schalter (Help Insight, Declaration Information, ToolTip Watches, Auto Code Completions
//     „Programmierhilfe“, Auto Invoke „Automatisch aufrufen“, Auto Invoke Delay, Auto Code Parameters,
//     AutoInvokeCompletionOnParameterInsight).
//   - Hauptschalter der Seite „dpcc“ mit OK (AfterOptions): aus → an stellt den Anbieter auf dpcc, an → aus zurück
//     (gemerkter Wert, sonst DelphiLSP). Erst nach dem Dialog, denn mit OK schreibt die IDE danach ihre
//     Editoroptionen aus dem Speicher zurück; danach eine Gegenprüfung, die überschriebene Werte erneut schreibt.
//   - Wahl im Code-Insight-Dialog der IDE (ProviderChosen, IOTACodeInsightManagerEnvOptions.ManagerEnabled/Disabled):
//     dieselbe Logik mit dem gewählten Anbieter, sofort für den Hauptschalter; die Schalter der IDE wirken nach dem
//     nächsten Start. Mit OK schreibt die IDE danach ihre Editoroptionen aus dem Speicher zurück und überschreibt
//     dabei Werte von dpcc (Help Insight, Declaration Information, ToolTip Watches wieder True). Deshalb folgt eine
//     verzögerte Gegenprüfung (ScheduleRecheck): Ein Timer fragt alle cRecheckPollMs, ob der Optionsdialog zu ist
//     (kein modales Fenster mehr, zwei Takte hintereinander), höchstens cRecheckMaxMs lang, und wendet dann denselben
//     Plan an wie die Gegenprüfung nach OK (Werte nachsetzen, Merker pflegen): dpcc gewählt mit MasterOn, ein anderer
//     Anbieter mit MasterOff.
//   - Beim Beenden (AtExit): den zuletzt gewollten Stand noch einmal schreiben, falls die IDE ihn überschrieben hat.
// Jede Änderung hält ein Merker unter HKCU\Software\dpcc\IdePlugin fest (je Version); zurückgedreht wird nur, was
// noch so steht, wie dpcc es geschrieben hat. Ältere Merker (IdeHelpInsightDisabled, IdeTooltipWatchesDisabled)
// gelten weiter und gehen beim nächsten Schreiben in die neuen über. Den Anbieterwechsel liest die IDE erst beim
// Start: Nach einem Wechsel meldet dpcc einmal „wirkt nach dem Neustart von Delphi“ im Meldungsfenster.
// Error Insight fasst dpcc nicht an (der frühere Knopf dafür war entfallen, der Code ohne Aufrufer; seit IDECHECK
// entfernt); die Prüfung meldet es nur.
// Drei Betriebsarten (Stufe 2 von dpcc.LspServer.exe, je Delphi-Version gespeichert): Plugin ≙ MasterOn, Aus ≙
// MasterOff, Server ≙ ServerOn (wie MasterOff, der Anbieter wird aber in jedem Fall DelphiLSP; die Umleitung auf
// dpcc.LspServer.exe macht dpcc.IDE.Foundation.LspRedirect). Beim Start bleibt Server stehen, solange DelphiLSP
// gewählt ist; wählt der Nutzer im Dialog der IDE dpcc, gilt Plugin, einen anderen Anbieter unter Plugin: Aus.
// In der Betriebsart Server setzt der Plan außerdem die vier Code-Insight-Optionen, ohne die die IDE den Server nicht
// fragt (TDpccIdeContext.ServerTargets), und Aus dreht sie zurück. Der Weg ist derselbe wie für die Schalter der
// Betriebsart Plugin: Registry und Merker (Execute), Gegenprüfung nach OK bzw. nach dem Dialog (Recheck) und erneutes
// Schreiben beim Beenden (AtExit). Einen Laufzeitweg über IOTAEnvironmentOptions.Values gibt es hier nicht: Die IDE
// liest die Werte beim nächsten Start von Delphi.
// Help Insight (HI1): Die Orte der Betriebsart dpcc sind unter Delphi 12 und 13 gleich (jeder vorhandene aus
// Borland.EditOptions.Pascal und dem Ort von DelphiLSP, TDpccIdeCheck.DpccKeys). Weil der Registry-Wert unter
// Delphi 12 nicht sicher wirkt, verbirgt dpcc.IDE.Hover.HelpInsightHide das Fenster zusätzlich zur Laufzeit; beim
// Start steht der gelesene Wert "Help Insight" je Ort als eine Zeile im Protokoll (ApplyAtStart).
// CI-OPT (nur Startweg, Plan unverändert): Nach dem Abgleich in der Betriebsart Plugin übernimmt ApplyAtStart einmal
// die Startwerte der Schalter „Nach dem Punkt automatisch öffnen“ und „Reservierte Wörter in der Liste zeigen“ aus dem
// Satz von DelphiLSP (AdoptStartValues, Merker „IdeAdopted …“) und unter Delphi 13 einmal die Funktionen der IDE
// (Blockvervollständigung, Vorlagen, Hinweise) nach Borland.EditOptions.Pascal, nur in Lücken und ohne Merker
// (CopyIdeFeatures, Merker „IdeAdopted 37.0 IdeFeatures“). Unter Delphi 12 schreibt dpcc dafür nichts; in den
// Betriebsarten Aus und Server keins von beiden.

interface

uses
  dpcc.Core.Settings.IdeCheck,
  dpcc.Core.Settings.OperatingMode;

type
  TDpccIdeInsightSwitch = class
  private
    /// <summary>Plan ausführen: Registry der IDE und Merker schreiben; mit AUpdateSettings auch den Hauptschalter
    /// speichern. True, wenn alles geschrieben werden konnte.</summary>
    class function Execute(const APlan: TDpccIdeContextPlan; AUpdateSettings: Boolean): Boolean; static;
    /// <summary>Lesen, planen, ausführen, protokollieren, Hinweis zeigen.</summary>
    class function Apply(ATrigger: TDpccIdeContextTrigger; const AProviderOverride: string;
      AUpdateSettings: Boolean): TDpccIdeContextPlan; static;
  public const
    /// <summary>Takt, in dem die Gegenprüfung nach der Wahl im Dialog nachsieht, ob der Dialog zu ist.</summary>
    cRecheckPollMs = 500;
    /// <summary>So lange wartet sie höchstens auf das Schließen des Dialogs.</summary>
    cRecheckMaxMs = 10 * 60 * 1000;
  public
    /// <summary>Gegenprüfung: Plan für ATrigger (mit AProviderOverride, falls gesetzt) erneut lesen und schreiben,
    /// was die IDE überschrieben hat (ohne den Hauptschalter); AReason für das Protokoll.</summary>
    class procedure Recheck(ATrigger: TDpccIdeContextTrigger; const AProviderOverride, AReason: string); static;
    /// <summary>Gegenprüfung nach dem Schließen des Optionsdialogs einplanen (siehe Kopf); ersetzt eine noch
    /// wartende.</summary>
    class procedure ScheduleRecheck(ATrigger: TDpccIdeContextTrigger; const AProviderOverride: string); static;
    /// <summary>Beim Entladen: wartende Gegenprüfung samt Timer abbauen (nur Hauptthread).</summary>
    class procedure Release; static;
    /// <summary>Beim Start von Delphi: Betriebsart nach dem gewählten Anbieter (eine Zeile ins Protokoll).</summary>
    class procedure ApplyAtStart; static;
    /// <summary>Nach OK im Optionsdialog (in die Warteschlange gestellt): Betriebsart vorher und nachher.</summary>
    class procedure AfterOptions(AWasMode, AIsMode: TDpccOperatingMode); static;
    /// <summary>Wahl im Code-Insight-Dialog der IDE: ASelected = dpcc gewählt.</summary>
    class procedure ProviderChosen(ASelected: Boolean); static;
    /// <summary>Beim Beenden: den zuletzt gewollten Stand erneut schreiben (nur Registry, ohne Einstellungen).
    /// </summary>
    class procedure AtExit; static;
  end;

implementation

uses
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Diagnostics.Guard,
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Win.Registry,
  Vcl.Forms,
  Vcl.ExtCtrls,
  ToolsAPI,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Editor.CodeInsightKeys,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Foundation.IdeSettingsCheck;

type
  /// <summary>Wartet mit einem Timer, bis der Optionsdialog zu ist, und startet dann die Gegenprüfung.</summary>
  TRecheckWaiter = class
  private
    FTimer: TTimer;
    FTrigger: TDpccIdeContextTrigger;
    FProvider: string;
    FDeadline: UInt64;
    /// <summary>Takte hintereinander ohne modales Fenster.</summary>
    FQuietTicks: Integer;
    procedure Tick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Arm(ATrigger: TDpccIdeContextTrigger; const AProvider: string);
  end;

var
  // Zuletzt gewollter Anlass dieser Sitzung (für AtExit); Applied = es wurde schon einmal geplant.
  LastTrigger: TDpccIdeContextTrigger = TDpccIdeContextTrigger.Start;
  LastProvider: string;
  Applied: Boolean;
  // Schon gezeigte Hinweise dieser Sitzung (jeder nur einmal, kein Dauernerv).
  ShownNotices: TArray<string>;
  // Wartende Gegenprüfung nach der Wahl im Code-Insight-Dialog; nil ohne.
  Waiter: TRecheckWaiter;

/// <summary>Ist noch ein modales Fenster offen (Optionsdialog der IDE)?</summary>
function ModalWindowOpen: Boolean;
begin
  Result := (Application <> nil) and (Application.ModalLevel > 0);
  if not Result and (Screen <> nil) and (Screen.ActiveCustomForm <> nil) then
  begin
    Result := fsModal in Screen.ActiveCustomForm.FormState;
  end;
end;

{ TRecheckWaiter }

constructor TRecheckWaiter.Create;
begin
  inherited Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TDpccIdeInsightSwitch.cRecheckPollMs;
  FTimer.OnTimer := Tick;
end;

destructor TRecheckWaiter.Destroy;
begin
  FTimer.Free;
  inherited;
end;

procedure TRecheckWaiter.Arm(ATrigger: TDpccIdeContextTrigger; const AProvider: string);
begin
  FTrigger := ATrigger;
  FProvider := AProvider;
  FDeadline := TThread.GetTickCount64 + TDpccIdeInsightSwitch.cRecheckMaxMs;
  FQuietTicks := 0;
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TRecheckWaiter.Tick(Sender: TObject);
begin
  TDpccGuard.Run(TDpccFeature.Settings,
    procedure
    begin
      if TThread.GetTickCount64 >= FDeadline then
      begin
        FTimer.Enabled := False;
        TDpccGuard.Log('IDE-Kontext: Gegenprüfung nach der Wahl im Dialog aufgegeben (Dialog nach 10 min noch offen)');
        Exit;
      end;
      // Die IDE schreibt ihre Editoroptionen beim OK des Dialogs zurück; erst danach prüfen.
      if ModalWindowOpen then
      begin
        FQuietTicks := 0;
        Exit;
      end;
      Inc(FQuietTicks);
      if FQuietTicks < 2 then
      begin
        Exit;
      end;
      FTimer.Enabled := False;
      TDpccIdeInsightSwitch.Recheck(FTrigger, FProvider, 'nach der Wahl im Code-Insight-Dialog');
    end);
end;

/// <summary>Hinweis ins Meldungsfenster, je Sitzung nur einmal; beim Laden des Plugins ist es noch nicht bereit.
/// </summary>
procedure ShowNotice(const AText: string);
var
  mText, mShown: string;
begin
  if AText = '' then
  begin
    Exit;
  end;
  for mShown in ShownNotices do
  begin
    if mShown = AText then
    begin
      Exit;
    end;
  end;
  ShownNotices := ShownNotices + [AText];
  mText := AText;
  TDpccMainThread.ForceQueue(TDpccFeature.EditorCommands,
    procedure
    var
      mMessages: IOTAMessageServices;
    begin
      if Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
      begin
        mMessages.AddTitleMessage('dpcc: ' + mText);
      end;
    end);
end;

class function TDpccIdeInsightSwitch.Execute(const APlan: TDpccIdeContextPlan; AUpdateSettings: Boolean): Boolean;
var
  mBase: string;
  mRegistry: TRegistry;
  mWrite: TDpccIdeWrite;
  mMarker: TDpccIdeMarker;
  mName: string;
  mSettings: TDpccPluginSettings;
begin
  Result := True;
  mBase := TDpccIdeSettingsCheck.BaseKey;
  if (mBase <> '') and ((Length(APlan.Writes) > 0) or (Length(APlan.MarkerWrites) > 0) or
    (Length(APlan.MarkerDeletes) > 0)) then
  begin
    mRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
    try
      mRegistry.RootKey := HKEY_CURRENT_USER;
      try
        for mWrite in APlan.Writes do
        begin
          if mWrite.Delete then
          begin
            if mRegistry.OpenKey(mBase + '\' + mWrite.Key, False) and mRegistry.ValueExists(mWrite.Name) then
            begin
              mRegistry.DeleteValue(mWrite.Name);
            end;
          end
          else if mRegistry.OpenKey(mBase + '\' + mWrite.Key, True) then
          begin
            // Als Zeichenkette, wie die IDE ihre Schalter schreibt ("True"/"False", "-1").
            mRegistry.WriteString(mWrite.Name, mWrite.Value);
          end
          else
          begin
            Result := False;
          end;
          mRegistry.CloseKey;
        end;
        // Merker erst nach den Werten: Ohne geschriebenen Wert gäbe es nichts zurückzudrehen.
        if mRegistry.OpenKey(cDpccRegistryKey, True) then
        begin
          for mName in APlan.MarkerDeletes do
          begin
            if mRegistry.ValueExists(mName) then
            begin
              mRegistry.DeleteValue(mName);
            end;
          end;
          for mMarker in APlan.MarkerWrites do
          begin
            mRegistry.WriteString(mMarker.StoreName, TDpccIdeContext.EncodeMarker(mMarker));
          end;
        end
        else
        begin
          Result := False;
        end;
        mRegistry.CloseKey;
      except
        // Ohne Schreibrecht bleibt die IDE, wie sie ist.
        on E: ERegistryException do
        begin
          TDpccGuard.Log('IDE-Kontext: Registry nicht beschreibbar: ' + TDpccGuard.ErrorText(E));
          Result := False;
        end;
      end;
    finally
      mRegistry.Free;
    end;
  end;
  if AUpdateSettings and (APlan.OperatingModeChanged or APlan.EnabledChanged) then
  begin
    // Betriebsart dieser Version (Aus, Plugin, Server); Enabled ist daraus abgeleitet.
    mSettings := TDpccIdeSettings.Current;
    mSettings.Mode := APlan.OperatingMode;
    TDpccIdeSettings.Update(mSettings);
  end;
end;

class function TDpccIdeInsightSwitch.Apply(ATrigger: TDpccIdeContextTrigger; const AProviderOverride: string;
  AUpdateSettings: Boolean): TDpccIdeContextPlan;
var
  mInput: TDpccIdeCheckInput;
begin
  mInput := TDpccIdeSettingsCheck.Read(TDpccIdeSettings.Current);
  if AProviderOverride <> '' then
  begin
    mInput.ProviderId := AProviderOverride;
  end;
  Result := TDpccIdeContext.Plan(mInput, ATrigger);
  Applied := True;
  LastTrigger := ATrigger;
  LastProvider := AProviderOverride;
  if not Execute(Result, AUpdateSettings) then
  begin
    TDpccGuard.Log('IDE-Kontext: nicht alles geschrieben');
  end;
  if Result.HasChanges or (ATrigger = TDpccIdeContextTrigger.Start) then
  begin
    TDpccGuard.Log(Result.LogLine);
  end;
  ShowNotice(Result.Notice);
end;

/// <summary>CI-OPT: Startwerte von „Nach dem Punkt automatisch öffnen“ und „Reservierte Wörter in der Liste zeigen“
/// einmal aus dem Satz von DelphiLSP dieser Version (TDpccIdeStartValues), beim ersten Start in der Betriebsart Plugin
/// (AMode, wie der Plan ihn ergibt); danach nie wieder. Nach dem Abgleich: Was der Plan am Ort von DelphiLSP gesetzt
/// hat, trägt einen Merker, und es gilt der Wert des Nutzers davor. In den Betriebsarten Aus und Server nichts, damit
/// sich dort nichts ändert (completion.keywords läse auch dpcc.LspServer.exe).</summary>
procedure AdoptStartValues(AMode: TDpccOperatingMode);
var
  mInput: TDpccIdeCheckInput;
  mSettings: TDpccPluginSettings;
  mAdopted: TArray<string>;
begin
  mSettings := TDpccIdeSettings.Current;
  if (AMode <> TDpccOperatingMode.Plugin) or (mSettings.OpenAfterDotAdopted and mSettings.KeywordsAdopted) then
  begin
    Exit;
  end;
  mInput := TDpccIdeSettingsCheck.Read(mSettings);
  mAdopted := TDpccIdeStartValues.Adopt(mInput, mSettings);
  if Length(mAdopted) = 0 then
  begin
    Exit;
  end;
  TDpccIdeSettings.SaveAdoption(mSettings);
  TDpccGuard.Log('Startwerte aus den Code-Insight-Optionen der IDE übernommen (einmalig, ' +
    TDpccIdeCheck.cLspKey + '): ' + string.Join('; ', mAdopted));
end;

/// <summary>CI-OPT: unter Delphi 13 in der Betriebsart Plugin die Funktionen der IDE (Blockvervollständigung,
/// Vorlagen, Hinweise) einmal aus dem Satz von DelphiLSP nach Borland.EditOptions.Pascal, nur wo der Wert dort fehlt
/// (TDpccIdeContext.FeatureCopies); ohne Merker, der Wert gehört danach dem Nutzer. Unter Delphi 12 nichts: Die IDE
/// liest dort für dpcc keinen Satz.</summary>
procedure CopyIdeFeatures(AMode: TDpccOperatingMode);
var
  mSettings: TDpccPluginSettings;
  mInput: TDpccIdeCheckInput;
  mWrites: TArray<TDpccIdeWrite>;
  mWrite: TDpccIdeWrite;
  mBase: string;
  mRegistry: TRegistry;
  mNames: TArray<string>;
begin
  mSettings := TDpccIdeSettings.Current;
  if mSettings.IdeFeaturesAdopted or (AMode <> TDpccOperatingMode.Plugin) or
    (TDpccCodeInsightKeys.MajorVersion(TDpccIdeSettingsCheck.BaseKey) < TDpccIdeContext.cFeatureCopyVersion) then
  begin
    Exit;
  end;
  mInput := TDpccIdeSettingsCheck.Read(mSettings);
  mWrites := TDpccIdeContext.FeatureCopies(mInput, AMode);
  mBase := mInput.BaseKey;
  mNames := nil;
  if (mBase <> '') and (Length(mWrites) > 0) then
  begin
    mRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
    try
      mRegistry.RootKey := HKEY_CURRENT_USER;
      try
        for mWrite in mWrites do
        begin
          // Den Schlüssel gibt es (FeatureCopies prüft das); nicht anlegen.
          if mRegistry.OpenKey(mBase + '\' + mWrite.Key, False) then
          begin
            mRegistry.WriteString(mWrite.Name, mWrite.Value);
            mNames := mNames + [mWrite.Name + ' = ' + mWrite.Value];
          end;
          mRegistry.CloseKey;
        end;
      except
        on E: ERegistryException do
        begin
          TDpccGuard.Log('IDE-Funktionen: Registry nicht beschreibbar: ' + TDpccGuard.ErrorText(E));
          Exit;
        end;
      end;
    finally
      mRegistry.Free;
    end;
  end;
  if mBase = '' then
  begin
    Exit;
  end;
  // Einmalig je Version: Auch ohne Lücke gilt die Übernahme als erledigt.
  mSettings.IdeFeaturesAdopted := True;
  TDpccIdeSettings.SaveAdoption(mSettings);
  if Length(mNames) > 0 then
  begin
    TDpccGuard.Log('IDE-Funktionen in den Satz von dpcc übernommen (einmalig, ' + TDpccIdeCheck.cPascalKey +
      ', nur fehlende Werte): ' + string.Join('; ', mNames));
  end
  else
  begin
    TDpccGuard.Log('IDE-Funktionen: im Satz von dpcc nichts zu übernehmen (' + TDpccIdeCheck.cPascalKey + ')');
  end;
end;

class procedure TDpccIdeInsightSwitch.ApplyAtStart;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
begin
  // Diagnose (HI1): "Help Insight" an den Orten von DelphiLSP, dpcc und HTML, wie die IDE sie beim Start vorfand
  // (vor dem Abgleich; nur gelesen). Ein Fehler hier kostet nur diese Zeile, nie den Abgleich.
  try
    TDpccGuard.Log(TDpccIdeSettingsCheck.HelpInsightLine + ' (beim Start, vor dem Abgleich)');
  except
    on E: Exception do
    begin
      TDpccGuard.Log('Help Insight in der Registry: nicht gelesen: ' + TDpccGuard.ErrorText(E));
    end;
  end;
  // Ohne ausdrücklichen Anbieter: AtExit folgt dann dem, was in der Registry steht (wählt der Nutzer im Dialog der
  // IDE DelphiLSP, schreibt dpcc beim Beenden den Anbieter nicht wieder auf dpcc).
  if TDpccIdeSettings.TakeFreshDefault then
  begin
    // Erster Start nach der Installation (kein gespeicherter Wert, auch kein früheres Enabled): Vorgabe Plugin, also
    // wie Plugin mit OK (Anbieter dpcc, wirkt nach dem Neustart), statt beim gewählten DelphiLSP auszuschalten.
    TDpccGuard.Log('IDE-Kontext: erster Start ohne gespeicherte Betriebsart, Vorgabe Plugin');
    mPlan := Apply(TDpccIdeContextTrigger.MasterOn, '', True);
  end
  else
  begin
    mPlan := Apply(TDpccIdeContextTrigger.Start, '', True);
  end;
  // CI-OPT: Startwerte der beiden Schalter, nur in der Betriebsart Plugin, nach dem Abgleich (hat der Plan am Ort von
  // DelphiLSP geschrieben, gilt über den Merker der Wert des Nutzers). Ein Fehler kostet nur die Übernahme.
  try
    AdoptStartValues(mPlan.OperatingMode);
  except
    on E: Exception do
    begin
      TDpccGuard.Log('Startwerte aus der IDE: nicht übernommen: ' + TDpccGuard.ErrorText(E));
    end;
  end;
  // CI-OPT: nur in der Betriebsart Plugin und nur unter Delphi 13, nach dem Abgleich (der Plan legt keinen Schlüssel
  // an, FeatureCopies ebenso nicht).
  try
    CopyIdeFeatures(mPlan.OperatingMode);
  except
    on E: Exception do
    begin
      TDpccGuard.Log('IDE-Funktionen: nicht übernommen: ' + TDpccGuard.ErrorText(E));
    end;
  end;
  // Danach prüfen, was gilt (Betriebsart IDE: die Werte von DelphiLSP, nur Protokoll).
  mInput := TDpccIdeSettingsCheck.Read(TDpccIdeSettings.Current);
  TDpccGuard.Log(TDpccIdeCheck.Evaluate(mInput).LogLine);
end;

class procedure TDpccIdeInsightSwitch.AfterOptions(AWasMode, AIsMode: TDpccOperatingMode);
var
  mTrigger: TDpccIdeContextTrigger;
begin
  // Es gilt die Betriebsart der Seite: Plugin = Betriebsart dpcc, Aus = IDE, Server = IDE mit Anbieter DelphiLSP und
  // Umleitung auf dpcc.LspServer.exe (auch ohne Umschalten, etwa wenn der Wechsel noch auf den Neustart wartet oder
  // sich der Tooltip geändert hat).
  case AIsMode of
    TDpccOperatingMode.Plugin:
      mTrigger := TDpccIdeContextTrigger.MasterOn;
    TDpccOperatingMode.Server:
      mTrigger := TDpccIdeContextTrigger.ServerOn;
  else
    mTrigger := TDpccIdeContextTrigger.MasterOff;
  end;
  if AWasMode <> AIsMode then
  begin
    TDpccGuard.Log(Format('IDE-Kontext: Betriebsart mit OK umgestellt: %s → %s', [TDpccOperatingModes.LogName(AWasMode),
      TDpccOperatingModes.LogName(AIsMode)]));
  end;
  Apply(mTrigger, '', False);
  // Gegenprüfung nach dem Rückschreiben der IDE: was überschrieben ist, erneut schreiben.
  TDpccMainThread.ForceQueue(TDpccFeature.Settings,
    procedure
    begin
      TDpccGuard.Run(TDpccFeature.Settings,
        procedure
        begin
          TDpccIdeInsightSwitch.Recheck(mTrigger, '', 'nach OK');
        end);
    end);
end;

class procedure TDpccIdeInsightSwitch.Recheck(ATrigger: TDpccIdeContextTrigger; const AProviderOverride,
  AReason: string);
var
  mInput: TDpccIdeCheckInput;
  mCheck: TDpccIdeContextPlan;
begin
  mInput := TDpccIdeSettingsCheck.Read(TDpccIdeSettings.Current);
  if AProviderOverride <> '' then
  begin
    mInput.ProviderId := AProviderOverride;
  end;
  mCheck := TDpccIdeContext.Plan(mInput, ATrigger);
  if (Length(mCheck.Writes) > 0) or (Length(mCheck.MarkerWrites) > 0) or (Length(mCheck.MarkerDeletes) > 0) then
  begin
    TDpccGuard.Log('IDE-Kontext: Gegenprüfung ' + AReason + ', von der IDE überschrieben, erneut geschrieben');
    // Nur Registry und Merker; den Hauptschalter hat der Anlass selbst schon gesetzt.
    Execute(mCheck, False);
    TDpccGuard.Log(mCheck.LogLine);
  end
  else
  begin
    TDpccGuard.Log('IDE-Kontext: Gegenprüfung ' + AReason + ': nichts überschrieben');
  end;
end;

class procedure TDpccIdeInsightSwitch.ScheduleRecheck(ATrigger: TDpccIdeContextTrigger;
  const AProviderOverride: string);
begin
  if Waiter = nil then
  begin
    Waiter := TRecheckWaiter.Create;
  end;
  Waiter.Arm(ATrigger, AProviderOverride);
end;

class procedure TDpccIdeInsightSwitch.Release;
begin
  FreeAndNil(Waiter);
end;

class procedure TDpccIdeInsightSwitch.ProviderChosen(ASelected: Boolean);
var
  mSelected: Boolean;
begin
  mSelected := ASelected;
  // Nach dem laufenden Ereignis der IDE; der Anbieter steht dann noch nicht in der Registry, deshalb ausdrücklich.
  TDpccMainThread.ForceQueue(TDpccFeature.Settings,
    procedure
    begin
      TDpccGuard.Run(TDpccFeature.Settings,
        procedure
        var
          mPlan: TDpccIdeContextPlan;
        begin
          if mSelected then
          begin
            TDpccGuard.Log('IDE-Kontext: dpcc im Code-Insight-Dialog der IDE gewählt');
            TDpccIdeInsightSwitch.Apply(TDpccIdeContextTrigger.Start, TDpccIdeCheck.cDpccId, True);
            // Mit OK schreibt die IDE danach ihre Editoroptionen zurück: nach dem Dialog nachsetzen.
            TDpccIdeInsightSwitch.ScheduleRecheck(TDpccIdeContextTrigger.MasterOn, TDpccIdeCheck.cDpccId);
          end
          else
          begin
            // Plugin → Aus (wie früher); eine gespeicherte Betriebsart Server bleibt mit DelphiLSP stehen.
            TDpccGuard.Log('IDE-Kontext: anderer Anbieter im Code-Insight-Dialog der IDE gewählt');
            mPlan := TDpccIdeInsightSwitch.Apply(TDpccIdeContextTrigger.Start, TDpccIdeCheck.cDelphiLspId, True);
            if mPlan.OperatingMode = TDpccOperatingMode.Server then
            begin
              TDpccIdeInsightSwitch.ScheduleRecheck(TDpccIdeContextTrigger.ServerOn, TDpccIdeCheck.cDelphiLspId);
            end
            else
            begin
              TDpccIdeInsightSwitch.ScheduleRecheck(TDpccIdeContextTrigger.MasterOff, TDpccIdeCheck.cDelphiLspId);
            end;
          end;
        end);
    end);
end;

class procedure TDpccIdeInsightSwitch.AtExit;
var
  mInput: TDpccIdeCheckInput;
  mPlan: TDpccIdeContextPlan;
begin
  if not Applied then
  begin
    Exit;
  end;
  mInput := TDpccIdeSettingsCheck.Read(TDpccIdeSettings.Current);
  if LastProvider <> '' then
  begin
    mInput.ProviderId := LastProvider;
  end;
  mPlan := TDpccIdeContext.Plan(mInput, LastTrigger);
  if Length(mPlan.Writes) > 0 then
  begin
    Execute(mPlan, False);
    TDpccGuard.Log('IDE-Kontext beim Beenden erneut geschrieben: ' + mPlan.LogLine);
  end;
end;

initialization

finalization
  // Sicherheitsnetz, falls Release beim Abmelden nicht lief: kein Timer überlebt das Package.
  FreeAndNil(Waiter);

end.
