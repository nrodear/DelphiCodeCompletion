unit dpcc.UI.Settings.Page.Parts;

// Teile der Optionsseite „dpcc“ (#227) je Bereich: legt sie in der Reihenfolge der Reiter an und baut ihre
// Elemente. Die Seite selbst kennt nur den Ablauf (Bindung, Baum). Seit S7a nur noch die Teile mit sichtbaren
// Einstellungen: Allgemein, Vervollständigung (mit Favoriten), Einfügen (im Teil Projektdatei) und Hints (Teil
// EditorView). Teile ohne sichtbare Einstellung (Build, Farben, Befehle, EditorCode, Prüfregeln, Start,
// Export/Import, Benachrichtigungen) und die Abschnitte der Module gibt es nicht mehr, den Reiter „Projektdatei“ seit S8.

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
  dpcc.UI.Settings.Page.Completion,
  dpcc.UI.Settings.Page.EditorView,
  dpcc.UI.Settings.Page.General,
  dpcc.UI.Settings.Page.TeamFile;

class procedure TDpccSettingsPageParts.CreateParts(APage: TDpccSettingsPageHost);
begin
  APage.AddPart(TDpccSettingsGeneralPart.Create(APage));
  APage.AddPart(TDpccSettingsCompletionPart.Create(APage));
  APage.AddPart(TDpccSettingsFavoritesPart.Create(APage));
  APage.AddPart(TDpccSettingsTeamFilePart.Create(APage));
  APage.AddPart(TDpccSettingsEditorViewPart.Create(APage));
end;

class procedure TDpccSettingsPageParts.Build(APage: TDpccSettingsPageHost);
begin
  CreateParts(APage);
  APage.Part<TDpccSettingsGeneralPart>.Build;
  APage.Part<TDpccSettingsCompletionPart>.Build;
  APage.Part<TDpccSettingsCompletionPart>.Build2;
  APage.Part<TDpccSettingsFavoritesPart>.Build;
  APage.Part<TDpccSettingsTeamFilePart>.Build;
  APage.Part<TDpccSettingsEditorViewPart>.Build;
end;

end.
