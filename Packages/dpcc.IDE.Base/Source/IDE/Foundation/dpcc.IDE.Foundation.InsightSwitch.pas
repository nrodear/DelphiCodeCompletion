unit dpcc.IDE.Foundation.InsightSwitch;

// Betriebsart von dpcc in der IDE (Auftrag IDECHECK): dpcc entscheidet, in welchem Kontext es läuft, und stellt die
// Code-Insight-Schalter der IDE selbst. Die Regeln (ohne Registry, getestet) stehen in dpcc.Core.Settings.IdeCheck
// (TDpccIdeContext.Plan); hier werden sie gelesen (dpcc.IDE.Foundation.IdeSettingsCheck), ausgeführt und gemeldet.
//   - Beim Start von Delphi (ApplyAtStart, vor dem Anmelden des Managers): Ist DelphiLSP (oder ein anderer Anbieter)
//     gewählt, schaltet dpcc sich aus (Hauptschalter) und dreht zurück, was es selbst geändert hatte; die Werte, die
//     DelphiLSP braucht, prüft es nur (Protokoll). Ist dpcc gewählt, bleibt bzw. wird der Hauptschalter an, und dpcc
//     setzt die nötigen Schalter (Help Insight, Declaration Information, ToolTip Watches, Auto Code Completions,
//     Auto Invoke Delay, Auto Code Parameters, AutoInvokeCompletionOnParameterInsight).
//   - Hauptschalter der Seite „dpcc“ mit OK (AfterOptions): aus → an stellt den Anbieter auf dpcc, an → aus zurück
//     (gemerkter Wert, sonst DelphiLSP). Erst nach dem Dialog, denn mit OK schreibt die IDE danach ihre
//     Editoroptionen aus dem Speicher zurück; danach eine Gegenprüfung, die überschriebene Werte erneut schreibt.
//   - Wahl im Code-Insight-Dialog der IDE (ProviderChosen, IOTACodeInsightManagerEnvOptions.ManagerEnabled/Disabled):
//     dieselbe Logik mit dem gewählten Anbieter, sofort für den Hauptschalter; die Schalter der IDE wirken nach dem
//     nächsten Start.
//   - Beim Beenden (AtExit): den zuletzt gewollten Stand noch einmal schreiben, falls die IDE ihn überschrieben hat.
// Jede Änderung hält ein Merker unter HKCU\Software\dpcc\IdePlugin fest (je Version); zurückgedreht wird nur, was
// noch so steht, wie dpcc es geschrieben hat. Ältere Merker (IdeHelpInsightDisabled, IdeTooltipWatchesDisabled)
// gelten weiter und gehen beim nächsten Schreiben in die neuen über. Den Anbieterwechsel liest die IDE erst beim
// Start: Nach einem Wechsel meldet dpcc einmal „wirkt nach dem Neustart von Delphi“ im Meldungsfenster.
// Error Insight fasst dpcc nicht an (der frühere Knopf dafür war entfallen, der Code ohne Aufrufer; seit IDECHECK
// entfernt); die Prüfung meldet es nur.

interface

uses
  dpcc.Core.Settings.IdeCheck;

type
  TDpccIdeInsightSwitch = class
  private
    /// <summary>Plan ausführen: Registry der IDE und Merker schreiben; mit AUpdateSettings auch den Hauptschalter
    /// speichern. True, wenn alles geschrieben werden konnte.</summary>
    class function Execute(const APlan: TDpccIdeContextPlan; AUpdateSettings: Boolean): Boolean; static;
    /// <summary>Lesen, planen, ausführen, protokollieren, Hinweis zeigen.</summary>
    class function Apply(ATrigger: TDpccIdeContextTrigger; const AProviderOverride: string;
      AUpdateSettings: Boolean): TDpccIdeContextPlan; static;
  public
    /// <summary>Beim Start von Delphi: Betriebsart nach dem gewählten Anbieter (eine Zeile ins Protokoll).</summary>
    class procedure ApplyAtStart; static;
    /// <summary>Nach OK im Optionsdialog (in die Warteschlange gestellt): Hauptschalter vorher und nachher.</summary>
    class procedure AfterOptions(AWasEnabled, AIsEnabled: Boolean); static;
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
  System.Win.Registry,
  ToolsAPI,
  dpcc.Core.Settings.Plugin,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Foundation.IdeSettingsCheck;

var
  // Zuletzt gewollter Anlass dieser Sitzung (für AtExit); Applied = es wurde schon einmal geplant.
  LastTrigger: TDpccIdeContextTrigger = TDpccIdeContextTrigger.Start;
  LastProvider: string;
  Applied: Boolean;
  // Schon gezeigte Hinweise dieser Sitzung (jeder nur einmal, kein Dauernerv).
  ShownNotices: TArray<string>;

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
  if AUpdateSettings and APlan.EnabledChanged then
  begin
    mSettings := TDpccIdeSettings.Current;
    mSettings.Enabled := APlan.Enabled;
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

class procedure TDpccIdeInsightSwitch.ApplyAtStart;
var
  mInput: TDpccIdeCheckInput;
begin
  // Ohne ausdrücklichen Anbieter: AtExit folgt dann dem, was in der Registry steht (wählt der Nutzer im Dialog der
  // IDE DelphiLSP, schreibt dpcc beim Beenden den Anbieter nicht wieder auf dpcc).
  Apply(TDpccIdeContextTrigger.Start, '', True);
  // Danach prüfen, was gilt (Betriebsart IDE: die Werte von DelphiLSP, nur Protokoll).
  mInput := TDpccIdeSettingsCheck.Read(TDpccIdeSettings.Current);
  TDpccGuard.Log(TDpccIdeCheck.Evaluate(mInput).LogLine);
end;

class procedure TDpccIdeInsightSwitch.AfterOptions(AWasEnabled, AIsEnabled: Boolean);
var
  mTrigger: TDpccIdeContextTrigger;
begin
  // Es gilt der Hauptschalter der Seite: an = Betriebsart dpcc, aus = IDE (auch ohne Umschalten, etwa wenn der
  // Wechsel noch auf den Neustart wartet oder sich der Tooltip geändert hat).
  if AIsEnabled then
  begin
    mTrigger := TDpccIdeContextTrigger.MasterOn;
  end
  else
  begin
    mTrigger := TDpccIdeContextTrigger.MasterOff;
  end;
  if AWasEnabled <> AIsEnabled then
  begin
    TDpccGuard.Log('IDE-Kontext: Hauptschalter mit OK umgeschaltet');
  end;
  Apply(mTrigger, '', False);
  // Gegenprüfung nach dem Rückschreiben der IDE: was überschrieben ist, erneut schreiben.
  TDpccMainThread.ForceQueue(TDpccFeature.Settings,
    procedure
    begin
      TDpccGuard.Run(TDpccFeature.Settings,
        procedure
        var
          mCheck: TDpccIdeContextPlan;
        begin
          mCheck := TDpccIdeContext.Plan(TDpccIdeSettingsCheck.Read(TDpccIdeSettings.Current), mTrigger);
          if Length(mCheck.Writes) > 0 then
          begin
            TDpccGuard.Log('IDE-Kontext: Gegenprüfung nach OK, von der IDE überschrieben, erneut geschrieben');
            TDpccIdeInsightSwitch.Execute(mCheck, False);
            TDpccGuard.Log(mCheck.LogLine);
          end;
        end);
    end);
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
        begin
          if mSelected then
          begin
            TDpccGuard.Log('IDE-Kontext: dpcc im Code-Insight-Dialog der IDE gewählt');
            TDpccIdeInsightSwitch.Apply(TDpccIdeContextTrigger.Start, TDpccIdeCheck.cDpccId, True);
          end
          else
          begin
            TDpccGuard.Log('IDE-Kontext: anderer Anbieter im Code-Insight-Dialog der IDE gewählt');
            TDpccIdeInsightSwitch.Apply(TDpccIdeContextTrigger.Start, TDpccIdeCheck.cDelphiLspId, True);
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

end.
