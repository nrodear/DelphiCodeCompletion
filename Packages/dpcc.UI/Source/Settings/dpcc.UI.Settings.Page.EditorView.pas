unit dpcc.UI.Settings.Page.EditorView;

// Reiter „Editor“, erster Teil: Anzeige im Editor (Statusleiste #1155, Kopf, Minimap, Änderungsmarken, gleiche
// Stellen). Die Editorleiste (#1101) mit „Leiste anpassen …“ gibt es seit S7a nicht mehr.

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  dpcc.Core.Settings.Plugin,
  dpcc.UI.Settings.ChoiceBox,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Editor“, erster Teil: Anzeige im Editor (Statusleiste #1155, Kopf, Minimap,
  /// Änderungsmarken, gleiche Stellen).</summary>
  TDpccSettingsEditorViewPart = class(TDpccSettingsPagePart)
  private
    FXmlDocExpand: TDpccChoiceBox;
    FNestedRoutines: TDpccChoiceBox;
    FStickyScrollBlockMinLines: TEdit;
    FMinimapRender: TDpccChoiceBox;
    FMinimapSide: TDpccChoiceBox;
    FMinimapShowSlider: TDpccChoiceBox;
    FEditorStatusBarItems: TEdit;
    FGitGutter: TCheckBox;
    FSelectionMatchesMinLength: TEdit;
    FSelectionMatchesMaxMatches: TEdit;
    procedure BuildBreadcrumbs;
  public
    procedure Build;
    procedure Build2;
    procedure Build3;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    procedure BindMarks; override;
    property StickyScrollBlockMinLines: TEdit read FStickyScrollBlockMinLines;
    property MinimapRender: TDpccChoiceBox read FMinimapRender;
    /// <summary>Zum Testen: Färbung lokaler Routinen (#1788).</summary>
    property NestedRoutines: TDpccChoiceBox read FNestedRoutines;
    property EditorStatusBarItemsEdit: TEdit read FEditorStatusBarItems;
    property SelectionMatchesMinLength: TEdit read FSelectionMatchesMinLength;
    property SelectionMatchesMaxMatches: TEdit read FSelectionMatchesMaxMatches;
    property GitGutter: TCheckBox read FGitGutter;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Vcl.Controls,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.Core.Documentation.Contract,
  dpcc.Core.Editor.RoutineNesting,
  dpcc.Core.Settings.StatusBarItems;

{ TDpccSettingsEditorViewPart }

/// <summary>Brotkrumenleiste (#590): Glieder, Sprungmenüs, Farben und Tastenkürzel.</summary>
procedure TDpccSettingsEditorViewPart.BuildBreadcrumbs;
begin
  // Brotkrumenleiste (#590).
  BindCheck('Breadcrumbs', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbs)));
  BindCheck('BreadcrumbsShowUnit',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsShowUnit)));
  // Sichtbarkeitsabschnitt als Glied (#1759).
  BindCheck('BreadcrumbsVisibility',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsVisibility)));
  // Unterblock in Typen (#1767).
  BindCheck('BreadcrumbsMemberBlocks',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsMemberBlocks)));
  // Sichtbarkeitsmarke am Methodenglied (#1765).
  BindCheck('BreadcrumbsVisibilityMark',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsVisibilityMark)));
  // Deklarationsblock der Unit (#1766).
  BindCheck('BreadcrumbsDeclarationBlocks',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsDeclarationBlocks)));
  // Bedingungszweig (#1763).
  BindCheck('BreadcrumbsConditionals',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsConditionals)));
  // Region (#1764).
  BindCheck('BreadcrumbsRegions',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsRegions)));
  // try/except/finally und case-Zweig (#1769).
  BindCheck('BreadcrumbsStatements',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsStatements)));
  // Sprungmenü am Sichtbarkeitsglied (#1768).
  BindCheck('BreadcrumbsSectionCounts',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsSectionCounts)));
  BindCheck('BreadcrumbsSectionAppend',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsSectionAppend)));
  BindCheck('BreadcrumbsSectionCreate',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsSectionCreate)));
  BindCheck('BreadcrumbsIdeColors',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsIdeColors)));
  BindCheck('BreadcrumbsHideIdeToolbar',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsHideIdeToolbar)));
  BindKey('BreadcrumbsKey', AddKey(TDpccStrings.Text(TDpccTextId.BreadcrumbsCommand)));
  BindKey('SectionAppendKey', AddKey(TDpccStrings.Text(TDpccTextId.SectionAppendCommand)));
  // Rechtsklick-Menü an den Gliedern (#1786).
  BindCheck('BreadcrumbsContextMenu',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsContextMenu)));
  // Überladungen mit Zähler und Parametern (#1784).
  BindCheck('BreadcrumbsOverloads',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsOverloads)));
  BindCheck('BreadcrumbsInterfaces',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsInterfaces)));
  BindCheck('BreadcrumbsMetrics',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBreadcrumbsMetrics)));
end;

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
  BindCheck('PairColors', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPairs)));
  BindCheck('PairGuides', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPairGuides)));
  // Anweisungen mitfärben, Linienbreite und Deckkraft (#653); wirken nur mit der Paarfärbung.
  BindCheck('PairOwners', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPairOwners)));
  BindText('PairGuideWidth', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPairGuideWidth)));
  BindText('PairGuideOpacity', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPairGuideOpacity)));
  // Lokale Routinen abheben (#1788): Färbung und Band getrennt.
  FNestedRoutines := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNestedRoutines),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNestedRoutinesOuter),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNestedRoutinesDeeper),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNestedRoutinesColor)]);
  BindCheck('NestedRoutineBand', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNestedRoutineBand)));
  BindCheck('InactiveDim', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsInactiveDim)));
  BindCheck('InlayHints', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsInlayHints)));
  // Typmarken von Inline-Variablen (#453), unabhängig von den Parameternamen.
  BindCheck('InlayTypeHints', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsInlayTypeHints)));
  // Symbole aus Include-Dateien hinter {$I} (#860).
  BindCheck('InlayDefineHints', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsInlayDefineHints)));
  // Code hinter Steuerzeichen wie ^C (#862).
  BindCheck('InlayCharHints', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsInlayCharHints)));
  // Marke „braucht kein Self“ hinter Methoden, die Self nicht brauchen (#686).
  BindCheck('InlayMethodHints', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsInlayMethodHints)));
  // Beschriftung hinter dem end langer Blöcke (#620).
  BindCheck('BlockEndLabels', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBlockEndLabels)));
  BindText('BlockEndLabelsMinLines',
    AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBlockEndLabelsMinLines)));
  BindCheck('DimUnusedUses', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDimUnusedUses)));
  BuildBreadcrumbs;
  BindCheck('MouseNavButtons', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMouseNavButtons)));
end;

procedure TDpccSettingsEditorViewPart.Build2;
begin
  // dpcc-Statusleiste unten im Editorfenster (#1155).
  BindCheck('EditorStatusBar', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsEditorStatusBar)));
  FEditorStatusBarItems := AddTextLine(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsEditorStatusBarItems));
  // Aufrufdiagramm (#1122).
  BindCheck('CallHierarchyDiagram',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsCallHierarchyDiagram)));
  // Mitlaufender Kopf (#506, experimentell).
  BindCheck('StickyScroll', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStickyScroll)));
  BindText('StickyScrollMaxLines',
    AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStickyScrollMaxLines)));
  BindCheck('StickyScrollTypes', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStickyScrollTypes)));
  BindCheck('StickyScrollRoutines',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStickyScrollRoutines)));
  BindCheck('StickyScrollBlocks',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStickyScrollBlocks)));
  BindCheck('StickyScrollLoops', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStickyScrollLoops)));
  BindCheck('StickyScrollTry', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStickyScrollTry)));
  BindCheck('StickyScrollCase', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStickyScrollCase)));
  BindCheck('StickyScrollWith', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsStickyScrollWith)));
  FStickyScrollBlockMinLines := AddNumber(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsStickyScrollBlockMinLines));
  // Minimap neben der Scrollleiste (#873, experimentell).
  BindCheck('Minimap', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimap)));
  FMinimapRender := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapRender),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapBlocks),
      TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapCharacters)]);
  BindText('MinimapWidth', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapWidth)));
  BindText('MinimapScale', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapScale)));
  BindText('MinimapMaxColumn', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapMaxColumn)));
  FMinimapSide := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapSide),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapRight),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapLeft)]);
  FMinimapShowSlider := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapSlider),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapSliderAlways),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapSliderHover)]);
  BindCheck('MinimapSectionHeaders', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapHeaders)));
  BindCheck('MinimapHighlightMethod', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapMethod)));
  BindCheck('MinimapMarkers', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapMarkers)));
  BindCheck('MinimapClickJumps', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMinimapClickJumps)));
  // Änderungsmarken und Zeilenhistorie (#507).
  FGitGutter := BindCheck('GitGutter', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGitGutter)));
  BindKey('NextChangeKey', AddKey(TDpccStrings.Text(TDpccTextId.NextChangeCommand)));
  BindKey('PreviousChangeKey', AddKey(TDpccStrings.Text(TDpccTextId.PreviousChangeCommand)));
  BindCheck('GitBlame', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGitBlame)));
  // dpcc-Spalte in der Zeilenleiste (#768): Hauptschalter und je Symbolart ein Häkchen.
  BindCheck('GutterColumn', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGutterColumn)));
  BindCheck('GutterColumnProblems',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGutterColumnProblems)));
  BindCheck('GutterColumnCodeActions',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGutterColumnActions)));
  BindCheck('GutterColumnOverrides',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGutterColumnOverrides)));
  // Gleichen Text wie die Markierung hervorheben (#709).
  BindCheck('SelectionMatches', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSelectionMatches)));
  FSelectionMatchesMinLength := AddNumber(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsSelectionMatchesMinLength));
end;

procedure TDpccSettingsEditorViewPart.Build3;
begin
  BindCheck('SelectionMatchesCaseSensitive',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSelectionMatchesCase)));
  BindCheck('SelectionMatchesWholeWord',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSelectionMatchesWholeWord)));
  BindCheck('SelectionMatchesNavigateF3',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSelectionMatchesF3)));
  FSelectionMatchesMaxMatches := AddNumber(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsSelectionMatchesMax));
end;

procedure TDpccSettingsEditorViewPart.BindMarks;
begin
  // Aus SaveTo: Element und die Einstellungen, die es schreibt. Listen aus mehreren Haken zeigen keinen Punkt
  // (der gälte für jeden Haken), lassen sich aber zurücksetzen.
  FPage.Marks.Bind(FEditorStatusBarItems, ['EditorStatusBarItems']);
  FPage.Marks.Bind(FStickyScrollBlockMinLines, ['StickyScrollBlockMinLines']);
  FPage.Marks.Bind(FMinimapRender, ['MinimapRender']);
  FPage.Marks.Bind(FMinimapSide, ['MinimapSide']);
  FPage.Marks.Bind(FMinimapShowSlider, ['MinimapShowSlider']);
  FPage.Marks.Bind(FSelectionMatchesMinLength, ['SelectionMatchesMinLength']);
  FPage.Marks.Bind(FSelectionMatchesMaxMatches, ['SelectionMatchesMaxMatches']);
  FPage.Marks.Bind(FXmlDocExpand, ['XmlDocExpand']);
  FPage.Marks.Bind(FNestedRoutines, ['NestedRoutines']);
end;

procedure TDpccSettingsEditorViewPart.Load(const ASettings: TDpccPluginSettings);
begin
  FEditorStatusBarItems.Text := ASettings.EditorStatusBarItems;
  FStickyScrollBlockMinLines.Text := IntToStr(ASettings.StickyScrollBlockMinLines);
  FMinimapRender.Choice := Max(0, IndexText(ASettings.MinimapRender, ['blocks', 'characters']));
  FMinimapSide.Choice := Max(0, IndexText(ASettings.MinimapSide, ['right', 'left']));
  FMinimapShowSlider.Choice := Max(0, IndexText(ASettings.MinimapShowSlider, ['always', 'mouseover']));
  FSelectionMatchesMinLength.Text := IntToStr(ASettings.SelectionMatchesMinLength);
  FSelectionMatchesMaxMatches.Text := IntToStr(ASettings.SelectionMatchesMaxMatches);
  FXmlDocExpand.Choice := Ord(TDpccDocDisplay.ExpandOf(ASettings.XmlDocExpand));
  FNestedRoutines.Choice := Ord(TDpccRoutineNesting.StyleOf(ASettings.NestedRoutines));
end;

procedure TDpccSettingsEditorViewPart.Save(var ASettings: TDpccPluginSettings);
begin
  ASettings.EditorStatusBarItems := TDpccStatusBarItems.Normalize(FEditorStatusBarItems.Text);
  ASettings.StickyScrollBlockMinLines := StrToIntDef(FStickyScrollBlockMinLines.Text,
    ASettings.StickyScrollBlockMinLines);
  ASettings.MinimapRender := 'blocks';
  if FMinimapRender.Choice = 1 then
  begin
    ASettings.MinimapRender := 'characters';
  end;
  ASettings.MinimapSide := 'right';
  if FMinimapSide.Choice = 1 then
  begin
    ASettings.MinimapSide := 'left';
  end;
  ASettings.MinimapShowSlider := 'always';
  if FMinimapShowSlider.Choice = 1 then
  begin
    ASettings.MinimapShowSlider := 'mouseover';
  end;
  ASettings.SelectionMatchesMinLength := StrToIntDef(FSelectionMatchesMinLength.Text,
    ASettings.SelectionMatchesMinLength);
  ASettings.SelectionMatchesMaxMatches := StrToIntDef(FSelectionMatchesMaxMatches.Text,
    ASettings.SelectionMatchesMaxMatches);
  ASettings.XmlDocExpand := TDpccDocDisplay.ExpandName(TDpccDocExpand(EnsureRange(FXmlDocExpand.Choice, 0, 2)));
  ASettings.NestedRoutines := TDpccRoutineNesting.cStyleNames[TDpccNestedRoutineStyle(EnsureRange(
    FNestedRoutines.Choice, Ord(Low(TDpccNestedRoutineStyle)), Ord(High(TDpccNestedRoutineStyle))))];
end;

end.
