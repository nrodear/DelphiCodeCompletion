unit dpcc.UI.Settings.Page.Parts;

// Teile der Optionsseite „dpcc“ (#227) je Bereich: legt sie in der Reihenfolge der Reiter an und baut ihre
// Elemente. Die Seite selbst kennt nur den Ablauf (Bindung, Abschnitte der Module, Baum). Base baut nur seine
// eigenen Einstellungen; die der Module (Debugger, Tests, Suche …) bringen die Module als Abschnitte mit (#1456).

interface

uses
  dpcc.UI.Settings.Page.Host;

type
  TDpccSettingsPageParts = class
  private
    class procedure CreateParts(APage: TDpccSettingsPageHost); static;
  public
    /// <summary>Legt die Teile der Bereiche auf APage an und baut ihre Reiter in der Reihenfolge der Seite.</summary>
    class procedure Build(APage: TDpccSettingsPageHost); static;
  end;

implementation

uses
  dpcc.UI.Settings.Page.Build,
  dpcc.UI.Settings.Page.Colors,
  dpcc.UI.Settings.Page.Commands,
  dpcc.UI.Settings.Page.Completion,
  dpcc.UI.Settings.Page.EditorCode,
  dpcc.UI.Settings.Page.EditorView,
  dpcc.UI.Settings.Page.General,
  dpcc.UI.Settings.Page.Rules,
  dpcc.UI.Settings.Page.Startup,
  dpcc.UI.Settings.Page.TeamFile,
  dpcc.UI.Settings.Page.Transfer,
  dpcc.UI.Settings.Page.Sections;

class procedure TDpccSettingsPageParts.CreateParts(APage: TDpccSettingsPageHost);
begin
  APage.AddPart(TDpccSettingsGeneralPart.Create(APage));
  APage.AddPart(TDpccSettingsNotificationsPart.Create(APage));
  APage.AddPart(TDpccSettingsTransferPart.Create(APage));
  APage.AddPart(TDpccSettingsCompletionPart.Create(APage));
  APage.AddPart(TDpccSettingsFavoritesPart.Create(APage));
  APage.AddPart(TDpccSettingsTeamFilePart.Create(APage));
  APage.AddPart(TDpccSettingsEditorViewPart.Create(APage));
  APage.AddPart(TDpccSettingsEditorCodePart.Create(APage));
  APage.AddPart(TDpccSettingsColorsPart.Create(APage));
  APage.AddPart(TDpccSettingsBuildPart.Create(APage));
  APage.AddPart(TDpccSettingsRulesPart.Create(APage));
  APage.AddPart(TDpccSettingsCommandsPart.Create(APage));
  APage.AddPart(TDpccSettingsStartupPart.Create(APage));
  // Seite Versionsverwaltung: Abschnitt des Moduls Versionsverwaltung (#1905).
  // Zuletzt: Die Abschnitte der Module laden und speichern nach den Einstellungen von Base.
  APage.AddPart(TDpccSettingsSectionsPart.Create(APage));
end;

class procedure TDpccSettingsPageParts.Build(APage: TDpccSettingsPageHost);
begin
  CreateParts(APage);
  APage.Part<TDpccSettingsGeneralPart>.Build;
  APage.Part<TDpccSettingsGeneralPart>.Build2;
  APage.Part<TDpccSettingsNotificationsPart>.Build;
  APage.Part<TDpccSettingsTransferPart>.Build;
  APage.Part<TDpccSettingsCompletionPart>.Build;
  APage.Part<TDpccSettingsCompletionPart>.Build2;
  APage.Part<TDpccSettingsFavoritesPart>.Build;
  APage.Part<TDpccSettingsTeamFilePart>.Build;
  APage.Part<TDpccSettingsEditorViewPart>.Build;
  APage.Part<TDpccSettingsEditorViewPart>.Build2;
  APage.Part<TDpccSettingsEditorViewPart>.Build3;
  APage.Part<TDpccSettingsEditorCodePart>.Build;
  APage.Part<TDpccSettingsEditorCodePart>.Build2;
  APage.Part<TDpccSettingsEditorCodePart>.Build3;
  APage.Part<TDpccSettingsColorsPart>.Build;
  APage.Part<TDpccSettingsBuildPart>.Build;
  APage.Part<TDpccSettingsRulesPart>.Build;
  APage.Part<TDpccSettingsCommandsPart>.Build;
  APage.Part<TDpccSettingsCommandsPart>.Build2;
  APage.Part<TDpccSettingsStartupPart>.Build;
  APage.Part<TDpccSettingsTeamFilePart>.Build2;
end;

end.
