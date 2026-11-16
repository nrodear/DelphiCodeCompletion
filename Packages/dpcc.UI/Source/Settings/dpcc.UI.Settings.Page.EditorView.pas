unit dpcc.UI.Settings.Page.EditorView;

// Reiter „Editor“ (gezeigt als „Hints“, Completion-Schnitt): Hover, Werte beim Debuggen und XMLDoc. Die Editorleiste
// (#1101) mit „Leiste anpassen …“ gibt es seit S7a nicht mehr; Inlay-Hints, Blockende, Brotkrumenleiste, Statusleiste,
// mitlaufender Kopf, Minimap, Änderungsmarken, dpcc-Spalte, gleichen Text hervorheben und die übrigen Schalter der
// Paarfärbung seit S8 (sie waren versteckt und wirkten nicht).
// Paarfärbung und Blocklinien (highlight.pairColors, highlight.pairGuides) bleiben versteckt gebaut: Sind beide an,
// schaltet dpcc beim Speichern die Strukturhervorhebung der IDE ab (TDpccIdeStructureSwitch.Sync).

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  dpcc.Core.Settings.Plugin,
  dpcc.UI.Settings.ChoiceBox,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Editor“ (gezeigt als „Hints“): Hover, Werte beim Debuggen und XMLDoc.</summary>
  TDpccSettingsEditorViewPart = class(TDpccSettingsPagePart)
  private
    FXmlDocExpand: TDpccChoiceBox;
  public
    procedure Build;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    procedure BindMarks; override;
  end;

implementation

uses
  System.Math,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.Core.Documentation.Contract;

{ TDpccSettingsEditorViewPart }

procedure TDpccSettingsEditorViewPart.Build;
begin
  AddSheet(TDpccTextId.SettingsTabEditor);
  // Schlichter Tooltip (S3, S3b mit vollem Inhalt): an/aus. Inhalte zeigt er wie früher vorgegeben; nur die Werte
  // beim Debuggen sind schaltbar, weil dpcc dafür den Wert-Tooltip der IDE abschaltet (wer den der IDE will, schaltet
  // sie hier aus).
  BindCheck('HoverTooltip', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsHover)));
  BindCheck('DebugHoverValues', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDebugHoverValues)));
  // XMLDoc im Detailpanel der Vervollständigung (#654, #770): zu- oder aufgeklappt beim Öffnen; gespeichert in
  // settings.json (hints.*, #227).
  FXmlDocExpand := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsXmlDocExpand),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsXmlDocCollapsed),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsXmlDocLast),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsXmlDocExpanded)]);
  BindText('XmlDocMaxLines', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsXmlDocMaxLines)));
  // Versteckt (Completion-Schnitt), aber wirksam: Mit beiden an schaltet dpcc die Strukturhervorhebung der IDE ab.
  BindCheck('PairColors', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPairs)));
  BindCheck('PairGuides', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPairGuides)));
end;

procedure TDpccSettingsEditorViewPart.BindMarks;
begin
  // Aus SaveTo: Element und die Einstellungen, die es schreibt.
  FPage.Marks.Bind(FXmlDocExpand, ['XmlDocExpand']);
end;

procedure TDpccSettingsEditorViewPart.Load(const ASettings: TDpccPluginSettings);
begin
  FXmlDocExpand.Choice := Ord(TDpccDocDisplay.ExpandOf(ASettings.XmlDocExpand));
end;

procedure TDpccSettingsEditorViewPart.Save(var ASettings: TDpccPluginSettings);
begin
  ASettings.XmlDocExpand := TDpccDocDisplay.ExpandName(TDpccDocExpand(EnsureRange(FXmlDocExpand.Choice, 0, 2)));
end;

end.
