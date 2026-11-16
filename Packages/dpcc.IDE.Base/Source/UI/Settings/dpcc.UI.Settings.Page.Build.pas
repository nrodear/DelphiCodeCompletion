unit dpcc.UI.Settings.Page.Build;

// Reiter „Compiler“: Probleme im Editor und Aktion nach dem Speichern (#398, #548). Module bauen ihre Einstellungen
// zum Compiler als Abschnitte in diesen Reiter (#1455).

interface

uses
  Vcl.StdCtrls,
  dpcc.Core.Settings.Plugin,
  dpcc.UI.Settings.ChoiceBox,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Compiler“: Probleme im Editor und Aktion nach dem Speichern (#398, #548).</summary>
  TDpccSettingsBuildPart = class(TDpccSettingsPagePart)
  private
    FAfterSave: TDpccChoiceBox;
  public
    procedure Build;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    procedure BindMarks; override;
    /// <summary>Zum Testen: nichts, Syntaxprüfung, Kompilieren.</summary>
    property AfterSaveChoice: TDpccChoiceBox read FAfterSave;
  end;

implementation

uses
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings;

{ TDpccSettingsBuildPart }

procedure TDpccSettingsBuildPart.Build;
begin
  // Probleme im Editor und eine Aktion nach dem Speichern (#398, #548): Syntaxprüfung der IDE oder
  // Kompilieren durch den Server (compiler.onSave in settings.json), nie beides.
  AddSheet(TDpccTextId.SettingsTabCompiler);
  BindCheck('Problems', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblems)));
  BindCheck('ProblemsStatusCounter',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsStatusCounter)));
  // Reihenfolge: nichts, Syntaxprüfung (CheckOnSave), Kompilieren (CompileOnSave).
  FAfterSave := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsCheckOnSave),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsAfterSaveNone),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsAfterSaveCheck),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsAfterSaveCompile)]);
  BindText('CheckOnSaveDelayMs', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsCheckDelay)));
  BindText('CheckOnSaveMaxMs', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsCheckMax)));
  BindCheck('ShowInterfaceCost', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsShowInterfaceCost)));
end;

procedure TDpccSettingsBuildPart.BindMarks;
begin
  FPage.Marks.Bind(FAfterSave, ['CheckOnSave', 'CompileOnSave']);
end;

procedure TDpccSettingsBuildPart.Load(const ASettings: TDpccPluginSettings);
begin
  FAfterSave.Choice := 0;
  if ASettings.CheckOnSave then
  begin
    FAfterSave.Choice := 1;
  end
  else if ASettings.CompileOnSave then
  begin
    FAfterSave.Choice := 2;
  end;
end;

procedure TDpccSettingsBuildPart.Save(var ASettings: TDpccPluginSettings);
begin
  ASettings.CheckOnSave := FAfterSave.Choice = 1;
  ASettings.CompileOnSave := FAfterSave.Choice = 2;
end;

end.
