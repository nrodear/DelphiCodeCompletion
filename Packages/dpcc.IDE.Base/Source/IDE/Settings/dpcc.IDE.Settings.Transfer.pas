unit dpcc.IDE.Settings.Transfer;

// Einstellungen exportieren, importieren und zurücksetzen in der IDE (#723):
// Dateidialoge, Sicherung vor dem Import, Projektwerte des aktiven Projekts
// für die Vorschau, Speichern (settings.json, dann Registry über
// TDpccIdeSettings.Update) und die Befehle der Befehlspalette
// dpcc.SettingsExport, dpcc.SettingsImport, dpcc.SettingsProfile und
// dpcc.SettingsReset (sichtbar mit settings.exportImport). Die Optionsseite
// ruft dieselben Wege mit ihren ungespeicherten Werten auf.
// - Sicherung: %APPDATA%\dpcc\Backups\dpcc-settings-JJJJMMTT-HHMMSS.json,
//   alles unverändert (auch Zustände und Rechnerwerte), die zehn neuesten
//   bleiben (settings.backupBeforeImport).
// - Eingebaute Profile kommen aus dem Plugin selbst (ProfileData, gleich den
//   Dateien unter Setup\Profile).

interface

uses
  System.SysUtils,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.Catalog,
  dpcc.Core.Settings.Transfer;

type
  TDpccIdeSettingsTransfer = class
  private class var
    FCatalog: TDpccSettingsCatalog;
  private
    class function State(const ASettings: TDpccPluginSettings): TDpccSettingsState; static;
    class function BackupFolder: string; static;
    class procedure ProjectTexts(out AProject, ATeam: string); static;
    class function Save(const AState: TDpccSettingsState): Boolean; static;
    class procedure Inform(const AText: string); static;
    class function Import(const ACurrent: TDpccPluginSettings; const AText, AFileName: string;
      out AResult: TDpccPluginSettings): Boolean; static;
    class function ChooseProfile(out AText, AFileName: string): Boolean; static;
    class function ChooseFile(out AText, AFileName: string): Boolean; static;
  public
    /// <summary>Katalog aus den eingebauten Schemata; lebt bis Release.</summary>
    class function Catalog: TDpccSettingsCatalog; static;
    /// <summary>Benutzerordner und -name aus der Umgebung für Pfadmakros.</summary>
    class function Macros: TDpccSettingsEnvironment; static;
    /// <summary>Befehle sichtbar (settings.exportImport).</summary>
    class function Visible: Boolean; static;
    /// <summary>Sichert ACurrent samt settings.json; AFileName = Datei der Sicherung.</summary>
    class function Backup(const ACurrent: TDpccPluginSettings; out AFileName: string): Boolean; static;
    /// <summary>Export mit Auswahl der Bereiche und Speichern-Dialog.</summary>
    class procedure ExportSettings(const ACurrent: TDpccPluginSettings); static;
    /// <summary>Import aus Datei oder eingebautem Profil (AProfile) mit Vorschau; gespeichert, wenn True.</summary>
    class function ImportSettings(const ACurrent: TDpccPluginSettings; AProfile: Boolean;
      out AResult: TDpccPluginSettings): Boolean; static;
    /// <summary>Alles zurücksetzen mit Rückfrage und Sicherung; gespeichert, wenn True.</summary>
    class function ResetAll(const ACurrent: TDpccPluginSettings; out AResult: TDpccPluginSettings): Boolean; static;
    /// <summary>Befehle der Befehlspalette (gespeicherte Werte).</summary>
    class procedure ExportCommand; static;
    class procedure ImportCommand; static;
    class procedure ProfileCommand; static;
    class procedure ResetCommand; static;
    /// <summary>Beim Entladen.</summary>
    class procedure Release; static;
  end;

implementation

uses
  System.IOUtils,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Forms,
  dpcc.Core.Settings.ProfileData,
  dpcc.Core.Projects.Setup,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.UI.Settings.Transfer,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Foundation.TeamFile,
  dpcc.IDE.Foundation.Files;

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
  try
    if FileExists(AFileName) then
    begin
      AText := TFile.ReadAllText(AFileName, TEncoding.UTF8);
      Result := True;
    end;
  except
    on Exception do
      Result := False;
  end;
end;

/// <summary>UTF-8 ohne BOM, Zeilenende CRLF.</summary>
procedure WriteText(const AFileName, AText: string);
begin
  ForceDirectories(ExtractFileDir(AFileName));
  TFile.WriteAllText(AFileName, StringReplace(AText, #10, #13#10, [rfReplaceAll]), TEncoding.GetEncoding(65001));
end;

{ TDpccIdeSettingsTransfer }

class function TDpccIdeSettingsTransfer.Catalog: TDpccSettingsCatalog;
begin
  if FCatalog = nil then
  begin
    FCatalog := TDpccSettingsCatalog.CreateDefault;
  end;
  Result := FCatalog;
end;

class procedure TDpccIdeSettingsTransfer.Release;
begin
  FreeAndNil(FCatalog);
end;

class function TDpccIdeSettingsTransfer.Macros: TDpccSettingsEnvironment;
begin
  Result :=
    function(const AName: string): string
    begin
      Result := GetEnvironmentVariable(AName);
    end;
end;

class function TDpccIdeSettingsTransfer.Visible: Boolean;
begin
  Result := TDpccIdeSettings.Current.SettingsExportImport;
end;

class function TDpccIdeSettingsTransfer.State(const ASettings: TDpccPluginSettings): TDpccSettingsState;
begin
  Result := TDpccSettingsState.Create(ASettings, TDpccIdeSettings.GlobalText);
end;

class function TDpccIdeSettingsTransfer.BackupFolder: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('APPDATA'), 'dpcc'), 'Backups');
end;

class procedure TDpccIdeSettingsTransfer.Inform(const AText: string);
begin
  MessageDlg(AText, TMsgDlgType.mtInformation, [TMsgDlgBtn.mbOK], 0);
end;

class procedure TDpccIdeSettingsTransfer.ProjectTexts(out AProject, ATeam: string);
var
  mProject, mFileName: string;
begin
  AProject := '';
  ATeam := '';
  mProject := TDpccIdeFiles.ActiveProjectFile;
  if mProject = '' then
  begin
    Exit;
  end;
  mFileName := TDpccProjectSetups.ExistingConfig(mProject,
    function(const AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end);
  if mFileName <> '' then
  begin
    ReadText(mFileName, AProject);
  end;
  mFileName := TDpccIdeTeamFile.LocateFor(mProject);
  if mFileName <> '' then
  begin
    ReadText(mFileName, ATeam);
  end;
end;

class function TDpccIdeSettingsTransfer.Save(const AState: TDpccSettingsState): Boolean;
begin
  // Erst settings.json (globale Schlüssel), dann Update: das schreibt die Registry und die umgeleiteten Werte
  // in dieselbe Datei.
  Result := TDpccIdeSettings.SaveGlobalText(AState.GlobalText);
  TDpccIdeSettings.Update(AState.Plugin);
end;

class function TDpccIdeSettingsTransfer.Backup(const ACurrent: TDpccPluginSettings; out AFileName: string): Boolean;
var
  mExport_: TDpccExportResult;
  mOld: string;
  mFiles: TArray<string>;
begin
  AFileName := '';
  Result := False;
  try
    mExport_ := TDpccSettingsTransfer.ExportSettings(Catalog, State(ACurrent), TDpccExportOptions.ForBackup,
      Macros());
    AFileName := TPath.Combine(BackupFolder, TDpccSettingsTransfer.BackupFileName(Now));
    WriteText(AFileName, mExport_.Text);
    Result := True;
    // Ältere Sicherungen aufräumen.
    mFiles := nil;
    for mOld in TDirectory.GetFiles(BackupFolder, TDpccSettingsTransfer.cBackupPrefix + '*.json') do
    begin
      mFiles := mFiles + [ExtractFileName(mOld)];
    end;
    for mOld in TDpccSettingsTransfer.BackupsToDelete(mFiles, TDpccSettingsTransfer.cKeepBackups) do
    begin
      System.SysUtils.DeleteFile(TPath.Combine(BackupFolder, mOld));
    end;
  except
    on E: Exception do
      // Scheitert nur das Aufräumen, gilt die Sicherung trotzdem.
      if not Result then
      begin
        MessageDlg(TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsTransferFailed, [E.Message]),
          TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], 0);
      end;
  end;
end;

class procedure TDpccIdeSettingsTransfer.ExportSettings(const ACurrent: TDpccPluginSettings);
var
  mOptions: TDpccExportOptions;
  mDialog: TSaveDialog;
  mExport_: TDpccExportResult;
  mMessage: string;
  mKeys: TArray<string>;
  mOmission: TDpccExportOmission;
begin
  mOptions := TDpccExportOptions.Create(nil, smOmit);
  if ACurrent.SettingsExportSecrets = 'placeholder' then
  begin
    mOptions.Secrets := smPlaceholder;
  end;
  if not TDpccExportDialog.Execute(Catalog, mOptions, nil) then
  begin
    Exit;
  end;
  mDialog := TSaveDialog.Create(nil);
  try
    mDialog.FileName := TDpccSettingsTransfer.cFileName;
    mDialog.DefaultExt := 'json';
    mDialog.Filter := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFileFilter);
    mDialog.Options := mDialog.Options + [ofOverwritePrompt, ofPathMustExist];
    if not mDialog.Execute then
    begin
      Exit;
    end;
    try
      mExport_ := TDpccSettingsTransfer.ExportSettings(Catalog, State(ACurrent), mOptions, Macros());
      WriteText(mDialog.FileName, mExport_.Text);
    except
      on E: Exception do
      begin
        MessageDlg(TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsTransferFailed, [E.Message]),
          TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], 0);
        Exit;
      end;
    end;
    mMessage := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsExportDone, [mExport_.Count, mDialog.FileName]);
    if Length(mExport_.Omitted) > 0 then
    begin
      mKeys := nil;
      for mOmission in mExport_.Omitted do
      begin
        mKeys := mKeys + [mOmission.Key];
      end;
      mMessage := mMessage + sLineBreak + TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsExportOmitted,
        [string.Join(', ', mKeys)]);
    end;
    if Length(mExport_.Placeholders) > 0 then
    begin
      mMessage := mMessage + sLineBreak + TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsExportPlaceholders,
        [string.Join(', ', mExport_.Placeholders)]);
    end;
    Inform(mMessage);
  finally
    mDialog.Free;
  end;
end;

class function TDpccIdeSettingsTransfer.ChooseFile(out AText, AFileName: string): Boolean;
var
  mDialog: TOpenDialog;
begin
  AText := '';
  AFileName := '';
  mDialog := TOpenDialog.Create(nil);
  try
    mDialog.FileName := TDpccSettingsTransfer.cFileName;
    mDialog.Filter := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFileFilter);
    mDialog.Options := mDialog.Options + [ofFileMustExist];
    Result := mDialog.Execute and ReadText(mDialog.FileName, AText);
    AFileName := mDialog.FileName;
  finally
    mDialog.Free;
  end;
end;

class function TDpccIdeSettingsTransfer.ChooseProfile(out AText, AFileName: string): Boolean;
var
  mFiles, mNames, mDescriptions: TArray<string>;
  mSource: TDpccSettingsFile;
  mName: string;
  mIndex: Integer;
begin
  AText := '';
  AFileName := '';
  mFiles := DpccProfileFiles;
  mNames := nil;
  mDescriptions := nil;
  for mName in mFiles do
  begin
    mSource := TDpccSettingsTransfer.ParseFile(DpccProfileJson(mName));
    if (TDpccStrings.Language = TDpccLanguage.English) and (mSource.NameEn <> '') then
    begin
      mNames := mNames + [mSource.NameEn];
      mDescriptions := mDescriptions + [mSource.DescriptionEn];
    end
    else
    begin
      mNames := mNames + [mSource.Name];
      mDescriptions := mDescriptions + [mSource.Description];
    end;
  end;
  // Letzter Eintrag: eigene Datei.
  mNames := mNames + [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProfileFromFile)];
  mDescriptions := mDescriptions + [''];
  Result := TDpccProfileDialog.Choose(mNames, mDescriptions, mIndex, nil);
  if not Result then
  begin
    Exit;
  end;
  if mIndex > High(mFiles) then
  begin
    Exit(ChooseFile(AText, AFileName));
  end;
  AFileName := mFiles[mIndex];
  AText := DpccProfileJson(AFileName);
end;

class function TDpccIdeSettingsTransfer.Import(const ACurrent: TDpccPluginSettings; const AText, AFileName: string;
  out AResult: TDpccPluginSettings): Boolean;
var
  mSource: TDpccSettingsFile;
  mCurrent: TDpccSettingsState;
  mPreview: TDpccImportPreview;
  mProjectText, mTeamText, mBackupFile, mMessage: string;
  mNext: TDpccSettingsState;
  mCount: Integer;
begin
  AResult := ACurrent;
  Result := False;
  mSource := TDpccSettingsTransfer.ParseFile(AText);
  if not mSource.Valid then
  begin
    MessageDlg(TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsImportInvalidFile, [ExtractFileName(AFileName),
      mSource.Error]),
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
    Exit;
  end;
  mCurrent := State(ACurrent);
  ProjectTexts(mProjectText, mTeamText);
  mPreview := TDpccSettingsTransfer.Preview(Catalog, mCurrent, mSource,
    TDpccImportOptions.Create(TDpccSettingsTransfer.ModeOf(mSource), nil, Macros(), mProjectText, mTeamText));
  if not TDpccImportDialog.Execute(Catalog, AFileName, mPreview,
    function(AMode: TDpccImportMode; const AAreas: TArray<string>): TDpccImportPreview
    begin
      Result := TDpccSettingsTransfer.Preview(Catalog, mCurrent, mSource, TDpccImportOptions.Create(AMode, AAreas,
        Macros(), mProjectText, mTeamText));
    end, nil) then
  begin
    Exit;
  end;
  mCount := mPreview.SelectedCount;
  if mCount = 0 then
  begin
    Inform(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImportNothing));
    Exit;
  end;
  // Vor jedem Import sichern (settings.backupBeforeImport); ohne Sicherung kein Import.
  mBackupFile := '';
  if ACurrent.SettingsBackupBeforeImport and not Backup(ACurrent, mBackupFile) then
  begin
    Exit;
  end;
  mNext := TDpccSettingsTransfer.Apply(Catalog, mCurrent, mPreview);
  Save(mNext);
  AResult := TDpccIdeSettings.Stored;
  Result := True;
  mMessage := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsImportDone, [mCount]);
  if mBackupFile <> '' then
  begin
    mMessage := mMessage + sLineBreak + TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsBackupDone,
      [mBackupFile]);
  end;
  Inform(mMessage);
end;

class function TDpccIdeSettingsTransfer.ImportSettings(const ACurrent: TDpccPluginSettings; AProfile: Boolean;
  out AResult: TDpccPluginSettings): Boolean;
var
  mText, mFileName: string;
  mChosen: Boolean;
begin
  AResult := ACurrent;
  if AProfile then
  begin
    mChosen := ChooseProfile(mText, mFileName);
  end
  else
  begin
    mChosen := ChooseFile(mText, mFileName);
  end;
  Result := mChosen and Import(ACurrent, mText, mFileName, AResult);
end;

class function TDpccIdeSettingsTransfer.ResetAll(const ACurrent: TDpccPluginSettings;
  out AResult: TDpccPluginSettings): Boolean;
var
  mBackupFile, mMessage: string;
begin
  AResult := ACurrent;
  Result := False;
  if MessageDlg(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsResetAllConfirm), TMsgDlgType.mtConfirmation,
    [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0, TMsgDlgBtn.mbNo) <> mrYes then
  begin
    Exit;
  end;
  mBackupFile := '';
  if ACurrent.SettingsBackupBeforeImport and not Backup(ACurrent, mBackupFile) then
  begin
    Exit;
  end;
  Save(TDpccSettingsTransfer.ResetAll(Catalog, State(ACurrent)));
  AResult := TDpccIdeSettings.Stored;
  Result := True;
  mMessage := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsResetAllDone);
  if mBackupFile <> '' then
  begin
    mMessage := mMessage + sLineBreak + TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsBackupDone,
      [mBackupFile]);
  end;
  Inform(mMessage);
end;

class procedure TDpccIdeSettingsTransfer.ExportCommand;
begin
  ExportSettings(TDpccIdeSettings.Stored);
end;

class procedure TDpccIdeSettingsTransfer.ImportCommand;
var
  mImported: TDpccPluginSettings;
begin
  ImportSettings(TDpccIdeSettings.Stored, False, mImported);
end;

class procedure TDpccIdeSettingsTransfer.ProfileCommand;
var
  mImported: TDpccPluginSettings;
begin
  ImportSettings(TDpccIdeSettings.Stored, True, mImported);
end;

class procedure TDpccIdeSettingsTransfer.ResetCommand;
var
  mReset: TDpccPluginSettings;
begin
  ResetAll(TDpccIdeSettings.Stored, mReset);
end;

end.
