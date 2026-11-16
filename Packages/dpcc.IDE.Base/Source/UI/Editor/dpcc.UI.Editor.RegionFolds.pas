unit dpcc.UI.Editor.RegionFolds;

// Texte zu „Regionen beim Öffnen“ (#1814, editor.regionFolds): Befehle zum Zu- und Aufklappen aller Regionen und
// die Auswahl auf der Optionsseite, deutsch und englisch. Eigene Tabelle, weil dpcc.UI.Strings über der Grenze
// der Unitlänge liegt.

interface

uses
  dpcc.Core.Localization.Language;

type
{$SCOPEDENUMS ON}
  TDpccRegionFoldsText = (CollapseCommand, ExpandCommand, Setting, ChoiceKeep, ChoiceCollapse, ChoiceExpand,
    ChoiceOff);
{$SCOPEDENUMS OFF}

  TDpccRegionFoldsTexts = class
  public
    /// <summary>Text AId in der Sprache der Oberfläche.</summary>
    class function Text(AId: TDpccRegionFoldsText): string; static;
    /// <summary>Einträge der Auswahl in der Reihenfolge von DpccRegionFoldModes.</summary>
    class function Choices: TArray<string>; static;
  end;

implementation

const
  cTexts: array[TDpccLanguage, TDpccRegionFoldsText] of string = (
    ('Alle Regionen zuklappen', 'Alle Regionen aufklappen', 'Regionen beim Öffnen:', 'unverändert lassen',
      'alle zuklappen', 'alle aufklappen', 'aus (auch keine Befehle)'),
    ('Collapse all regions', 'Expand all regions', 'Regions when a file opens:', 'leave unchanged',
      'collapse all', 'expand all', 'off (no commands either)'));

{ TDpccRegionFoldsTexts }

class function TDpccRegionFoldsTexts.Text(AId: TDpccRegionFoldsText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

class function TDpccRegionFoldsTexts.Choices: TArray<string>;
begin
  Result := TArray<string>.Create(Text(TDpccRegionFoldsText.ChoiceKeep), Text(TDpccRegionFoldsText.ChoiceCollapse),
    Text(TDpccRegionFoldsText.ChoiceExpand), Text(TDpccRegionFoldsText.ChoiceOff));
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.UI.Editor.RegionFolds', cTexts[TDpccLanguage.German],
    cTexts[TDpccLanguage.English]);

end.
