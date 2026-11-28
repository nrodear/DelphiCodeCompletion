unit dpcc.IDE.Foundation.IdeSettingsCheck;

// Liest den Stand der IDE für die Betriebsart (Auftrag IDECHECK, Regeln in dpcc.Core.Settings.IdeCheck), nur lesend
// (KEY_READ): den gewählten Code-Insight-Anbieter, die Code-Insight-Schalter an den Orten von DelphiLSP und dpcc,
// InsightGlobalOptions und die Merker unter HKCU\Software\dpcc\IdePlugin (was dpcc geändert hat, je Version).
// Geschrieben wird nur in dpcc.IDE.Foundation.InsightSwitch.
// Versionsneutral (Delphi 12 und 13): Basis immer IOTAServices.GetBaseRegistryKey, die Orte bestimmt Core.
// Der Anbieter kommt aus der Registry ("Insight Manager"; so hat die IDE ihn beim Start gelesen). Fehlt der Wert,
// wie in LogSelection (dpcc.IDE.Completion.Register) von der IDE (IOTACodeInsightServices.HandlesFile).

interface

uses
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.IdeCheck;

type
  TDpccIdeSettingsCheck = class
  private class var
    FRunningProvider: string;
  public
    /// <summary>Anbieter, mit dem die laufende IDE arbeitet: beim Start gelesen (InsightSwitch.ApplyAtStart), nach
    /// einer Wahl im Code-Insight-Dialog der gewählte; '' = unbekannt. Read gibt ihn als RunningProviderId mit
    /// (Zeile „wartet auf den Neustart“ der Optionsseite).</summary>
    class property RunningProvider: string read FRunningProvider write FRunningProvider;
    /// <summary>Basisschlüssel der IDE ohne führenden und abschließenden Backslash; '' ohne IDE.</summary>
    class function BaseKey: string; static;
    /// <summary>Kennung des Code-Insight-Anbieters, den die IDE für Delphi-Dateien ruft; '' wenn sie keinen nennt.
    /// </summary>
    class function ServicesProviderId: string; static;
    /// <summary>Stand aus der Registry (nur gelesen) samt Merkern und dpcc-Stand aus ASettings.</summary>
    class function Read(const ASettings: TDpccPluginSettings): TDpccIdeCheckInput; static;
    /// <summary>Lesen und prüfen.</summary>
    class function Run(const ASettings: TDpccPluginSettings): TDpccIdeCheckResult; static;
    /// <summary>Statuszeilen für die Optionsseite (Abschnitt „IDE“).</summary>
    class function Status(const ASettings: TDpccPluginSettings): string; static;
    /// <summary>Diagnose (HI1), nur gelesen: Wert "Help Insight" an den Orten
    /// TDpccHelpInsightRule.DiagnosisKeys der laufenden IDE-Version als eine Zeile fürs Protokoll; ein fehlender
    /// Schlüssel oder Wert ist als solcher benannt.</summary>
    class function HelpInsightLine: string; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Win.Registry,
  ToolsAPI,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Editor.HelpInsightRule,
  dpcc.IDE.Foundation.Settings;

class function TDpccIdeSettingsCheck.BaseKey: string;
var
  mServices: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Result := mServices.GetBaseRegistryKey;
  end;
  while (Result <> '') and (Result[1] = '\') do
  begin
    Delete(Result, 1, 1);
  end;
  while (Result <> '') and (Result[Length(Result)] = '\') do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

class function TDpccIdeSettingsCheck.ServicesProviderId: string;
const
  cSample = 'dpcc.pas';
var
  mServices: IOTACodeInsightServices;
  mIndex: Integer;
  mManager: IOTACodeInsightManager;
begin
  Result := '';
  try
    if not Supports(BorlandIDEServices, IOTACodeInsightServices, mServices) then
    begin
      Exit;
    end;
    for mIndex := 0 to mServices.CodeInsightManagerCount - 1 do
    begin
      mManager := mServices.CodeInsightManager[mIndex];
      if (mManager <> nil) and mServices.HandlesFile(cSample, mManager.GetIDString) then
      begin
        Result := mManager.GetIDString;
      end;
    end;
  except
    on E: Exception do
    begin
      TDpccGuard.Log('IDE-Kontext: Anbieter der IDE nicht ermittelt: ' + TDpccGuard.ErrorText(E));
      Result := '';
    end;
  end;
end;

/// <summary>Die Werte ANames unter ABase\AKey, soweit vorhanden; den Schlüssel selbst, wenn es ihn gibt.</summary>
procedure ReadValues(ARegistry: TRegistry; const ABase, AKey: string; const ANames: array of string;
  var AInput: TDpccIdeCheckInput);
var
  mIndex: Integer;
  mName: string;
begin
  if not ARegistry.OpenKeyReadOnly(ABase + '\' + AKey) then
  begin
    Exit;
  end;
  try
    AInput.AddKey(AKey);
    for mIndex := Low(ANames) to High(ANames) do
    begin
      mName := ANames[mIndex];
      if not ARegistry.ValueExists(mName) then
      begin
        Continue;
      end;
      case ARegistry.GetDataType(mName) of
        rdString, rdExpandString:
          AInput.Add(AKey, mName, ARegistry.ReadString(mName));
        rdInteger:
          AInput.Add(AKey, mName, IntToStr(ARegistry.ReadInteger(mName)), True);
      end;
    end;
  finally
    ARegistry.CloseKey;
  end;
end;

/// <summary>Merker dieser Version unter HKCU\Software\dpcc\IdePlugin: neue (IdeSet …) und ältere (DWORD).</summary>
procedure ReadMarkers(ARegistry: TRegistry; var AInput: TDpccIdeCheckInput);
var
  mNames: TStringList;
  mName: string;
  mMarker: TDpccIdeMarker;
begin
  if not ARegistry.OpenKeyReadOnly(cDpccRegistryKey) then
  begin
    Exit;
  end;
  mNames := TStringList.Create;
  try
    ARegistry.GetValueNames(mNames);
    for mName in mNames do
    begin
      case ARegistry.GetDataType(mName) of
        rdString, rdExpandString:
          if TDpccIdeContext.DecodeMarker(AInput.BaseKey, mName, ARegistry.ReadString(mName), mMarker) then
          begin
            AInput.Markers := AInput.Markers + [mMarker];
          end;
        rdInteger:
          if TDpccIdeContext.DecodeLegacyMarker(AInput.BaseKey, mName, ARegistry.ReadInteger(mName), mMarker) then
          begin
            AInput.Markers := AInput.Markers + [mMarker];
          end;
      end;
    end;
  finally
    mNames.Free;
    ARegistry.CloseKey;
  end;
end;

class function TDpccIdeSettingsCheck.Read(const ASettings: TDpccPluginSettings): TDpccIdeCheckInput;
var
  mRegistry: TRegistry;
  mKey: string;
  mRegistered: TDpccIdeRegValue;
begin
  Result := Default(TDpccIdeCheckInput);
  Result.Dpcc := TDpccIdeDpccState.From(ASettings);
  Result.BaseKey := BaseKey;
  if Result.BaseKey = '' then
  begin
    Exit;
  end;
  // Nur lesen: Geschrieben wird ausschließlich in TDpccIdeInsightSwitch.
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    try
      ReadValues(mRegistry, Result.BaseKey, TDpccIdeCheck.cSourceOptionsKey, [TDpccIdeCheck.cProviderValue], Result);
      if Result.TryGet(TDpccIdeCheck.cSourceOptionsKey, TDpccIdeCheck.cProviderValue, mRegistered) then
      begin
        Result.ProviderId := Trim(mRegistered.Value);
      end;
      for mKey in TDpccIdeCheck.KeysToRead(Result.ProviderId) do
      begin
        ReadValues(mRegistry, Result.BaseKey, mKey, TDpccIdeCheck.CodeInsightValueNames, Result);
      end;
      ReadValues(mRegistry, Result.BaseKey, TDpccIdeCheck.cGlobalKey, [TDpccIdeCheck.cAutoInvokeOnParameterInsight],
        Result);
      ReadMarkers(mRegistry, Result);
    except
      // Ohne Leserecht gilt, was bis dahin gelesen ist; der Rest mit den Vorgaben der IDE.
      on E: ERegistryException do
        TDpccGuard.Log('IDE-Kontext: Registry nicht lesbar: ' + TDpccGuard.ErrorText(E));
    end;
  finally
    mRegistry.Free;
  end;
  if Result.ProviderId = '' then
  begin
    // Kein Wert in der Registry (Vorgabe der IDE): die IDE fragen.
    Result.ProviderId := ServicesProviderId;
  end;
  Result.RunningProviderId := FRunningProvider;
end;

class function TDpccIdeSettingsCheck.Run(const ASettings: TDpccPluginSettings): TDpccIdeCheckResult;
begin
  Result := TDpccIdeCheck.Evaluate(Read(ASettings));
end;

class function TDpccIdeSettingsCheck.Status(const ASettings: TDpccPluginSettings): string;
begin
  Result := TDpccIdeContext.StatusText(Read(ASettings));
end;

/// <summary>"Help Insight" unter ABase\AKey, nur gelesen.</summary>
function ReadHelpInsight(ARegistry: TRegistry; const ABase, AKey: string): TDpccHelpInsightRegEntry;
var
  mKeyExists, mValueExists: Boolean;
  mValue: string;
begin
  mKeyExists := False;
  mValueExists := False;
  mValue := '';
  try
    mKeyExists := ARegistry.OpenKeyReadOnly(ABase + '\' + AKey);
    if mKeyExists then
    begin
      try
        mValueExists := ARegistry.ValueExists(TDpccHelpInsightRule.cValueName);
        if mValueExists then
        begin
          case ARegistry.GetDataType(TDpccHelpInsightRule.cValueName) of
            rdString, rdExpandString:
              mValue := ARegistry.ReadString(TDpccHelpInsightRule.cValueName);
            rdInteger:
              mValue := IntToStr(ARegistry.ReadInteger(TDpccHelpInsightRule.cValueName));
          else
            mValue := '(anderer Typ)';
          end;
        end;
      finally
        ARegistry.CloseKey;
      end;
    end;
  except
    // Ohne Leserecht: als gelesen gilt, was bis dahin da war; die Zeile nennt den Fehler.
    on E: ERegistryException do
    begin
      mValueExists := mKeyExists;
      mValue := '(nicht lesbar: ' + TDpccGuard.ErrorText(E) + ')';
    end;
  end;
  Result := TDpccHelpInsightRegEntry.Create(AKey, mKeyExists, mValueExists, mValue);
end;

class function TDpccIdeSettingsCheck.HelpInsightLine: string;
var
  mBase, mKey: string;
  mRegistry: TRegistry;
  mEntries: TArray<TDpccHelpInsightRegEntry>;
begin
  mBase := BaseKey;
  mEntries := nil;
  if mBase <> '' then
  begin
    // Nur lesen (KEY_READ), wie Read.
    mRegistry := TRegistry.Create(KEY_READ);
    try
      mRegistry.RootKey := HKEY_CURRENT_USER;
      for mKey in TDpccHelpInsightRule.DiagnosisKeys do
      begin
        mEntries := mEntries + [ReadHelpInsight(mRegistry, mBase, mKey)];
      end;
    finally
      mRegistry.Free;
    end;
  end;
  Result := TDpccHelpInsightRule.RegistryLine(mBase, mEntries);
end;

end.
