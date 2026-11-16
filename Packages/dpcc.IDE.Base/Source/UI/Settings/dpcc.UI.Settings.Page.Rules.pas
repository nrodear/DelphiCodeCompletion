unit dpcc.UI.Settings.Page.Rules;

// Bereich „Prüfregeln“ (#909): Fenster „dpcc-Prüfung“, laufende Prüfung und Compiler vorab (#1024). Wege zu den
// Regeln, Profile, Baseline und Unterdrückungen trägt der Abschnitt des Moduls Prüfregeln bei (#1755).

interface

uses
  Vcl.StdCtrls,
  dpcc.Core.Settings.Plugin,
  dpcc.UI.Settings.ChoiceBox,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Bereich „Prüfregeln“ (#909): Prüffenster und Compiler vorab (#1024); den Rest liefert das Modul
  /// Prüfregeln als Abschnitt (#1755).</summary>
  TDpccSettingsRulesPart = class(TDpccSettingsPagePart)
  private
    FProblemsWindowScope: TDpccChoiceBox;
    FProblemsWindowGroupBy: TDpccChoiceBox;
    FProblemsWindowClosedUnits: TDpccChoiceBox;
    FProblemsCompilerMerge: TDpccChoiceBox;
    FProblemsUpdate: TDpccChoiceBox;
    FProblemsLiveDelay: TEdit;
  public
    procedure Build;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    procedure BindMarks; override;
    property ProblemsWindowScopeChoice: TDpccChoiceBox read FProblemsWindowScope;
    property ProblemsWindowGroupByChoice: TDpccChoiceBox read FProblemsWindowGroupBy;
    property ProblemsWindowClosedUnitsChoice: TDpccChoiceBox read FProblemsWindowClosedUnits;
    property ProblemsCompilerMergeChoice: TDpccChoiceBox read FProblemsCompilerMerge;
    property ProblemsUpdateChoice: TDpccChoiceBox read FProblemsUpdate;
    property ProblemsLiveDelayEdit: TEdit read FProblemsLiveDelay;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.UI.Problems.ScopeBox;

const
  /// <summary>Werte von problems.window.scope und problems.window.groupBy in der Reihenfolge der Auswahl (#909).
  /// </summary>
  cScopeValues: array[0..2] of string = ('file', 'project', 'group');
  cGroupByValues: array[0..3] of string = ('none', 'file', 'rule', 'category');
  /// <summary>Werte von problems.window.closedUnits in der Reihenfolge der Auswahl (#1108).</summary>
  cClosedUnitsValues: array[0..2] of string = ('dimmed', 'normal', 'hidden');
  /// <summary>Werte von problems.compilerMerge in der Reihenfolge der Auswahl (#1024).</summary>
  cCompilerMergeValues: array[0..1] of string = ('merge', 'both');
  /// <summary>Werte von problems.update in der Reihenfolge der Auswahl (wie TDpccProblemsRefresh).</summary>
  cProblemsUpdateValues: array[0..2] of string = ('live', 'save', 'manual');

{ TDpccSettingsRulesPart }

procedure TDpccSettingsRulesPart.Build;
begin
  // Prüfregeln (#909): das Fenster „dpcc-Prüfung“ und die laufende Prüfung. Den Weg zu den Regeln (sie stehen in
  // den Dialogen der Einstellungsdateien), Profile, Baseline und Unterdrückungen trägt das Modul bei (#1755).
  AddSheet(TDpccTextId.SettingsTabRules);
  BindCheck('ProblemsWindow', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsWindow)));
  FProblemsWindowScope := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsWindowScope),
    [TDpccStrings.Text(TDpccTextId.ProblemsScopeFile), TDpccStrings.Text(TDpccTextId.ProblemsScopeProject),
    TDpccStrings.Text(TDpccTextId.ProblemsScopeGroup)]);
  // Einzelne Projekte der Gruppe in der Bereichsliste (#1843).
  BindCheck('ProblemsWindowScopeProjects', AddCheck(TDpccProblemsScopeBox.Text(TDpccScopeBoxText.Setting)));
  FProblemsWindowGroupBy := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsWindowGroupBy),
    [TDpccStrings.Text(TDpccTextId.ProblemsGroupNone), TDpccStrings.Text(TDpccTextId.ProblemsGroupFile),
    TDpccStrings.Text(TDpccTextId.ProblemsGroupRule), TDpccStrings.Text(TDpccTextId.ProblemsGroupCategory)]);
  BindCheck('ProblemsWindowCompiler',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsWindowCompiler)));
  BindCheck('ProblemsWindowFollowCursor',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsWindowFollowCursor)));
  // Offene Units zuerst (#1108); der Hauptschalter sperrt die beiden Zeilen darunter (x-parent).
  BindCheck('ProblemsWindowOpenFirst',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsWindowOpenFirst)));
  FProblemsWindowClosedUnits := AddChoice(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsProblemsWindowClosedUnits),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.ProblemsClosedDimmed),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.ProblemsClosedNormal),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.ProblemsClosedHidden)]);
  BindCheck('ProblemsWindowShowCleanActive', AddCheck(
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsWindowShowCleanActive)));
  // Wann die offene Datei geprüft wird, und die Verzögerung der Live-Prüfung.
  FProblemsUpdate := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsUpdate),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.ProblemsUpdateLive),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.ProblemsUpdateSave),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.ProblemsUpdateManual)]);
  FProblemsLiveDelay := BindText('ProblemsLiveDelayMs',
    AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsLiveDelay)));
  // Liste „dpcc-Probleme“ im Meldungsfenster (#398), seit #909 nur noch zusätzlich zum Fenster.
  BindCheck('ProblemsMessageList', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsList)));
  // Fehler der IDE (Error Insight) neben die dpcc-Befunde (#1819).
  BindCheck('ProblemsIdeErrors',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsIdeErrors)));
  // Gruppe „Compiler vorab“ (#1024): stehen über x-node im Knoten der Gruppe unter dem Regel-Editor.
  FProblemsCompilerMerge := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsCompilerMerge),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.ProblemsCompilerMergeMerge),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.ProblemsCompilerMergeBoth)]);
  BindCheck('ProblemsShowCompilerCode',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsProblemsShowCompilerCode)));
end;

procedure TDpccSettingsRulesPart.BindMarks;
begin
  FPage.Marks.Bind(FProblemsWindowScope, ['ProblemsWindowScope']);
  FPage.Marks.Bind(FProblemsWindowGroupBy, ['ProblemsWindowGroupBy']);
  FPage.Marks.Bind(FProblemsWindowClosedUnits, ['ProblemsWindowClosedUnits']);
  FPage.Marks.Bind(FProblemsCompilerMerge, ['ProblemsCompilerMerge']);
  FPage.Marks.Bind(FProblemsUpdate, ['ProblemsUpdate']);
end;

procedure TDpccSettingsRulesPart.Load(const ASettings: TDpccPluginSettings);
begin
  FProblemsWindowScope.Choice := Max(0, IndexText(ASettings.ProblemsWindowScope, cScopeValues));
  FProblemsWindowGroupBy.Choice := Max(0, IndexText(ASettings.ProblemsWindowGroupBy, cGroupByValues));
  FProblemsWindowClosedUnits.Choice := Max(0, IndexText(ASettings.ProblemsWindowClosedUnits, cClosedUnitsValues));
  FProblemsCompilerMerge.Choice := Max(0, IndexText(ASettings.ProblemsCompilerMerge, cCompilerMergeValues));
  FProblemsUpdate.Choice := Max(0, IndexText(ASettings.ProblemsUpdate, cProblemsUpdateValues));
end;

procedure TDpccSettingsRulesPart.Save(var ASettings: TDpccPluginSettings);
begin
  if (FProblemsWindowScope.Choice >= 0) and (FProblemsWindowScope.Choice <= High(cScopeValues)) then
  begin
    ASettings.ProblemsWindowScope := cScopeValues[FProblemsWindowScope.Choice];
  end;
  if (FProblemsWindowGroupBy.Choice >= 0) and (FProblemsWindowGroupBy.Choice <= High(cGroupByValues)) then
  begin
    ASettings.ProblemsWindowGroupBy := cGroupByValues[FProblemsWindowGroupBy.Choice];
  end;
  if (FProblemsWindowClosedUnits.Choice >= 0) and (FProblemsWindowClosedUnits.Choice <= High(cClosedUnitsValues)) then
  begin
    ASettings.ProblemsWindowClosedUnits := cClosedUnitsValues[FProblemsWindowClosedUnits.Choice];
  end;
  if (FProblemsCompilerMerge.Choice >= 0) and (FProblemsCompilerMerge.Choice <= High(cCompilerMergeValues)) then
  begin
    ASettings.ProblemsCompilerMerge := cCompilerMergeValues[FProblemsCompilerMerge.Choice];
  end;
  if (FProblemsUpdate.Choice >= 0) and (FProblemsUpdate.Choice <= High(cProblemsUpdateValues)) then
  begin
    ASettings.ProblemsUpdate := cProblemsUpdateValues[FProblemsUpdate.Choice];
  end;
end;

end.
