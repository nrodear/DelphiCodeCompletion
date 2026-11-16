unit dpcc.UI.Settings.Page.Commands;

// Reiter „Editorbefehle“ (#399): Tasten der Befehle und Blockkommentar (#703),
// Untermenü dpcc im Kontextmenü des Editors (#2102).

interface

uses
  Vcl.StdCtrls,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.ContextMenuGroups,
  dpcc.UI.Settings.ChoiceBox,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Editorbefehle“ (#399): Tasten der Befehle und Blockkommentar (#703).</summary>
  TDpccSettingsCommandsPart = class(TDpccSettingsPagePart)
  private
    FToggleBlockCommentStyle: TDpccChoiceBox;
    FToggleBlockCommentFallback: TDpccChoiceBox;
    FToggleBlockCommentScope: TDpccChoiceBox;
    /// <summary>Gezeigte Untermenüs im Kontextmenü dpcc des Editors (#2102), je Gruppe ein Häkchen.</summary>
    FContextGroups: array[TDpccContextMenuGroup] of TCheckBox;
    procedure BuildContextMenu;
  public
    procedure Build;
    procedure Build2;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    procedure BindMarks; override;
    property ToggleBlockCommentStyle: TDpccChoiceBox read FToggleBlockCommentStyle;
    property ToggleBlockCommentFallback: TDpccChoiceBox read FToggleBlockCommentFallback;
    property ToggleBlockCommentScope: TDpccChoiceBox read FToggleBlockCommentScope;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings;

{ TDpccSettingsCommandsPart }

procedure TDpccSettingsCommandsPart.Build;
begin
  // Editorbefehle (#399): ein Vorrang für alle.
  AddSheet(TDpccTextId.SettingsTabCommands);
  BindKey('ActionsKey', AddKey(TDpccStrings.Text(TDpccTextId.EditorActions)));
  BindKey('ExpandKey', AddKey(TDpccStrings.Text(TDpccTextId.EditorExpand)));
  BindKey('ShrinkKey', AddKey(TDpccStrings.Text(TDpccTextId.EditorShrink)));
  BindKey('ImplementationKey', AddKey(TDpccStrings.Text(TDpccTextId.MenuImplementations)));
  BindKey('TypeDefinitionKey', AddKey(TDpccStrings.Text(TDpccTextId.EditorTypeDefinition)));
  // Deklaration ⇄ Implementierung (#775); aus: Klassennavigation der IDE.
  BindCheck('MethodToggle', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMethodToggle)));
  BindKey('MethodToggleUpKey', AddKey(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMethodToggleUp)));
  BindKey('MethodToggleDownKey', AddKey(TDpccStrings.Text(TDpccTextId.SettingsMethodToggleDown)));
  // Sprung zum Gegenstück (#635); aus: beide Tasten bleiben frei.
  BindCheck('JumpToMatch', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsJumpToMatch)));
  BindKey('JumpToMatchKey', AddKey(TDpccStrings.Text(TDpccTextId.JumpToMatchCommand)));
  BindKey('JumpToMatchSelectKey', AddKey(TDpccStrings.Text(TDpccTextId.JumpToMatchSelectCommand)));
  // Zeilen verschieben und duplizieren (#634); aus: die Tasten bleiben der IDE.
  BindCheck('MoveLines', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMoveLines)));
  BindKey('MoveLinesUpKey', AddKey(TDpccStrings.Text(TDpccTextId.MoveLinesUpCommand)));
  BindKey('MoveLinesDownKey', AddKey(TDpccStrings.Text(TDpccTextId.MoveLinesDownCommand)));
  BindKey('DuplicateLinesUpKey', AddKey(TDpccStrings.Text(TDpccTextId.DuplicateLinesUpCommand)));
  BindKey('DuplicateLinesDownKey', AddKey(TDpccStrings.Text(TDpccTextId.DuplicateLinesDownCommand)));
  // Blockkommentar umschalten (#703).
  BindCheck('ToggleBlockComment',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsToggleBlockComment)));
  BindKey('ToggleBlockCommentKey', AddKey(TDpccStrings.Text(TDpccTextId.ToggleBlockCommentCommand)));
  FToggleBlockCommentStyle := AddChoice(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsToggleBlockCommentStyle),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.ToggleBlockCommentBraces),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.ToggleBlockCommentParens)]);
  FToggleBlockCommentFallback := AddChoice(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsToggleBlockCommentFallback),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.ToggleBlockCommentLineComments),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.ToggleBlockCommentRefuse)]);
  BindCheck('ToggleBlockCommentOwnLines',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsToggleBlockCommentOwnLines)));
  FToggleBlockCommentScope := AddChoice(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsToggleBlockCommentScope),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.ToggleBlockCommentStatement),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.ToggleBlockCommentLine)]);
  // Neue Zeile ober- oder unterhalb (#700).
  BindCheck('NewLineAround', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNewLineAround)));
  BindKey('NewLineBelowKey', AddKey(TDpccStrings.Text(TDpccTextId.NewLineBelowCommand)));
  BindKey('NewLineAboveKey', AddKey(TDpccStrings.Text(TDpccTextId.NewLineAboveCommand)));
  BindCheck('NewLineAroundStatementAware',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNewLineAroundStatementAware)));
  // Umschließung entfernen (#657).
  BindCheck('Unwrap', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsUnwrap)));
  BindKey('UnwrapKey', AddKey(TDpccStrings.Text(TDpccTextId.UnwrapCommand)));
  // Sicher löschen (#716).
  BindCheck('SafeDelete', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSafeDelete)));
  BindKey('SafeDeleteKey', AddKey(TDpccStrings.Text(TDpccTextId.SafeDeleteCommand)));
  BindKey('TestUnitKey', AddKey(TDpccStrings.Text(TDpccTextId.EditorTestUnit)));
  // Abschnittssprünge der Editorleiste (#1101), auch ohne die Leiste.
  BindKey('GotoInterfaceKey', AddKey(TDpccStrings.Text(TDpccTextId.GotoInterfaceCommand)));
  BindKey('GotoImplementationKey', AddKey(TDpccStrings.Text(TDpccTextId.GotoImplementationCommand)));
  // Navigationsverlauf über Dateien (#504).
  BindCheck('NavHistory', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsNavHistory)));
  BindKey('NavBackKey', AddKey(TDpccStrings.Text(TDpccTextId.NavBackCommand)));
  BindKey('NavForwardKey', AddKey(TDpccStrings.Text(TDpccTextId.NavForwardCommand)));
  BindKey('LastEditKey', AddKey(TDpccStrings.Text(TDpccTextId.NavLastEditCommand)));
end;

procedure TDpccSettingsCommandsPart.Build2;
begin
  // Definition und Referenzen einblenden (#505).
  BindCheck('Peek', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPeek)));
  BindText('PeekHeightLines', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPeekHeight)));
  BindCheck('PeekShowImplementation',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPeekImplementation)));
  BindKey('PeekDefinitionKey', AddKey(TDpccStrings.Text(TDpccTextId.PeekDefinitionCommand)));
  BindKey('PeekReferencesKey', AddKey(TDpccStrings.Text(TDpccTextId.PeekReferencesCommand)));
  // Treffersicherheit der Verwendungen (#1119).
  BindCheck('ReferencesInferred',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReferencesInferred)));
  BindCheck('ReferencesTextMatches',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReferencesTextMatches)));
  // Auswirkungsanalyse (#1120).
  BindCheck('Impact', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImpact)));
  BindText('ImpactDepth', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsImpactDepth)));
  // Datenfluss im Ergebnisfenster (#690).
  BindCheck('DataFlow', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDataFlow)));
  BindText('DataFlowMaxDepth', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDataFlowMaxDepth)));
  BindCheck('DataFlowExcludeTests',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDataFlowExcludeTests)));
  BindCheck('Outline', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsOutline)));
  BindCheck('OutlineAlphabetical',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsOutlineAlphabetical)));
  BindCheck('OutlineFollowCursor',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsOutlineFollowCursor)));
  BindCheck('OutlineConditions', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsOutlineConditions)));
  // „Element ausblenden …“ am gezeichneten Element (#628).
  BindKey('HideElementKey', AddKey(TDpccStrings.Text(TDpccTextId.HideElementCommand)));
  // Nächster/vorheriger Befund (#509).
  BindKey('NextProblemKey', AddKey(TDpccStrings.Text(TDpccTextId.ProblemNextCommand)));
  BindKey('PreviousProblemKey', AddKey(TDpccStrings.Text(TDpccTextId.ProblemPreviousCommand)));
  // Fenster „dpcc-Prüfung“ (#909).
  BindKey('ProblemsWindowKey', AddKey(TDpccStrings.Text(TDpccTextId.ProblemsWindowCommand)));
  // „Datei jetzt prüfen“ (#1744).
  BindKey('CheckFileKey', AddKey(TDpccStrings.Text(TDpccTextId.ProblemsCheckFileCommand)));
  // „Issue anlegen …“ (#1268), ohne Vorgabe.
  BindKey('CreateIssueKey', AddKey(TDpccStrings.Text(TDpccTextId.CreateIssueCommand)));
  BindKey('UndoKey', AddKey(TDpccStrings.Text(TDpccTextId.UndoMenu)));
  BindKey('RedoKey', AddKey(TDpccStrings.Text(TDpccTextId.RedoMenu)));
  BindCheck('EditorKeysPriority',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsEditorKeysPriority)));
  BindCheck('SlashCommands', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSlashCommands)));
  // Einstellungen mit @ in der Befehlspalette (#1884).
  BindCheck('PaletteSettingsPrefix', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.PaletteSettingsPrefix)));
  // Erzeugen-Menü (#719): Schnellbefehle, Vorlagen und Code-Aktionen an der Cursorstelle.
  BindCheck('GenerateMenu', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGenerateMenu)));
  BindKey('GenerateMenuKey', AddKey(TDpccStrings.Text(TDpccTextId.GenerateMenuCommand)));
  BindText('GenerateMenuGroups',
    AddTextLine(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGenerateMenuGroups)));
  BindText('GenerateMenuHidden',
    AddTextLine(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGenerateMenuHidden)));
  BindCheck('GenerateMenuRecentFirst',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGenerateMenuRecentFirst)));
  BindCheck('GenerateMenuShowCommandNames',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGenerateMenuShowCommandNames)));
  // Untermenü dpcc in der Projektverwaltung (#1817).
  BindCheck('ProjectContextMenu',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProjectContextMenu)));
  // Assistenten in Datei › Neu › Weitere (#1821).
  BindCheck('GalleryWizards', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGalleryWizards)));
  BuildContextMenu;
  // Liste der Benachrichtigungen (#601).
  BindKey('NotificationsKey', AddKey(TDpccStrings.Text(TDpccTextId.NotificationsCommand)));
end;

procedure TDpccSettingsCommandsPart.BuildContextMenu;
const
  // Eine Zeile Text über den Häkchen der Untermenüs.
  cGroupsLabelHeight = 20;
  cTexts: array[TDpccContextMenuGroup] of TDpccSettingsTextId = (
    TDpccSettingsTextId.SettingsContextGroupNavigation, TDpccSettingsTextId.SettingsContextGroupEdit,
    TDpccSettingsTextId.SettingsContextGroupAnalysis, TDpccSettingsTextId.SettingsContextGroupFindings,
    TDpccSettingsTextId.SettingsContextGroupDebug, TDpccSettingsTextId.SettingsContextGroupTests,
    TDpccSettingsTextId.SettingsContextGroupNotes);
var
  mGroup: TDpccContextMenuGroup;
begin
  // Untermenü dpcc im Kontextmenü des Editors (#2102): nur Passendes und je Untermenü ein Häkchen.
  BindCheck('EditorContextMenuContextual',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsEditorContextMenuContextual)));
  AddWrappedLabel(cGroupsLabelHeight, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsEditorContextMenuGroups));
  for mGroup := Low(TDpccContextMenuGroup) to High(TDpccContextMenuGroup) do
  begin
    FContextGroups[mGroup] := AddCheck(TDpccSettingsStrings.Text(cTexts[mGroup]));
  end;
end;

procedure TDpccSettingsCommandsPart.BindMarks;
var
  mGroup: TDpccContextMenuGroup;
begin
  for mGroup := Low(TDpccContextMenuGroup) to High(TDpccContextMenuGroup) do
  begin
    FPage.Marks.Bind(FContextGroups[mGroup], ['EditorContextMenuGroups']);
  end;
  FPage.Marks.Bind(FToggleBlockCommentStyle, ['ToggleBlockCommentStyle']);
  FPage.Marks.Bind(FToggleBlockCommentFallback, ['ToggleBlockCommentFallback']);
  FPage.Marks.Bind(FToggleBlockCommentScope, ['ToggleBlockCommentWithoutSelection']);
end;

procedure TDpccSettingsCommandsPart.Load(const ASettings: TDpccPluginSettings);
var
  mGroup: TDpccContextMenuGroup;
  mGroups: TDpccContextMenuGroups;
begin
  mGroups := TDpccContextMenuGroupNames.Parse(ASettings.EditorContextMenuGroups);
  for mGroup := Low(TDpccContextMenuGroup) to High(TDpccContextMenuGroup) do
  begin
    FContextGroups[mGroup].Checked := mGroup in mGroups;
  end;
  FToggleBlockCommentStyle.Choice := Max(0, IndexText(ASettings.ToggleBlockCommentStyle, ['braces', 'parens']));
  FToggleBlockCommentFallback.Choice := Max(0, IndexText(ASettings.ToggleBlockCommentFallback,
    ['lineComments', 'refuse']));
  FToggleBlockCommentScope.Choice := Max(0, IndexText(ASettings.ToggleBlockCommentWithoutSelection,
    ['statement', 'line']));
end;

procedure TDpccSettingsCommandsPart.Save(var ASettings: TDpccPluginSettings);
var
  mGroup: TDpccContextMenuGroup;
  mGroups: TDpccContextMenuGroups;
begin
  mGroups := [];
  for mGroup := Low(TDpccContextMenuGroup) to High(TDpccContextMenuGroup) do
  begin
    if FContextGroups[mGroup].Checked then
    begin
      Include(mGroups, mGroup);
    end;
  end;
  ASettings.EditorContextMenuGroups := TDpccContextMenuGroupNames.Text(mGroups);
  ASettings.ToggleBlockCommentStyle := 'braces';
  if FToggleBlockCommentStyle.Choice = 1 then
  begin
    ASettings.ToggleBlockCommentStyle := 'parens';
  end;
  ASettings.ToggleBlockCommentFallback := 'lineComments';
  if FToggleBlockCommentFallback.Choice = 1 then
  begin
    ASettings.ToggleBlockCommentFallback := 'refuse';
  end;
  ASettings.ToggleBlockCommentWithoutSelection := 'statement';
  if FToggleBlockCommentScope.Choice = 1 then
  begin
    ASettings.ToggleBlockCommentWithoutSelection := 'line';
  end;
end;

end.
