unit dpcc.UI.Settings.Page.TeamFile;

// Reiter „Einfügen“: was beim Übernehmen eines Vorschlags eingefügt wird. Code-Vorlagen (Schalter, Vorlagen der
// Projektdatei) gibt es seit S2 nicht mehr, den Reiter „Projektdatei“ (.dpcc, #486, teamFile.enabled) seit S8: Er war
// versteckt, und nichts außer ihm las die Projektdatei. Der Name der Unit bleibt.

interface

uses
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Einfügen“.</summary>
  TDpccSettingsTeamFilePart = class(TDpccSettingsPagePart)
  public
    procedure Build;
  end;

implementation

uses
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings;

{ TDpccSettingsTeamFilePart }

procedure TDpccSettingsTeamFilePart.Build;
begin
  // Was beim Übernehmen eingefügt wird.
  AddSheet(TDpccTextId.SettingsTabInsert);
  BindCheck('AutoParentheses', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsParentheses)));
  BindCheck('FixCase', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFixCase)));
  BindCheck('CommitCharacters', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsCommitChars)));
  BindCheck('AutoUses', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsAutoUses)));
  BindCheck('ParameterHints', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsParameterHints)));
  BindCheck('FormatPlaceholders',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFormatPlaceholders)));
end;

end.
