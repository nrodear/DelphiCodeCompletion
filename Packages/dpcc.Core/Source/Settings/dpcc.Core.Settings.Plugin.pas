unit dpcc.Core.Settings.Plugin;

// Einstellungen des IDE-Plugins (#227, Teil Vervollständigung), ohne VCL und
// ohne Registry: Vorgaben, Grenzen, Lesen und Schreiben über einen Speicher.
// Die IDE-Schicht speichert in HKCU\Software\dpcc\IdePlugin, Tests im
// Arbeitsspeicher. Breiten in logischen Pixeln (96 dpi, #412).
// Die Server-Einstellungen unter den Feldern (Index, Speicher, XMLDoc,
// Inlay-Hints, Schnellbefehle, Kompilieren nach dem Speichern) liegen in
// %APPDATA%\dpcc\settings.json; TDpccRoutedSettingsStore leitet sie dorthin
// (dpcc.Core.Settings.Scopes).
// Die Felder liegen je Bereich in dpcc.Core.Settings.Plugin.<Bereich> (Records je Bereich nach x-area des
// Plugin-Schemas); TDpccPluginSettings reicht sie als Eigenschaften durch, die Zugriffe bleiben gleich.

interface

uses
  dpcc.Core.Settings.Plugin.Bookmarks,
  dpcc.Core.Settings.Plugin.Build,
  dpcc.Core.Settings.Plugin.CodeActions,
  dpcc.Core.Settings.Plugin.Completion,
  dpcc.Core.Settings.Plugin.Debug,
  dpcc.Core.Settings.Plugin.Editor,
  dpcc.Core.Settings.Plugin.General,
  dpcc.Core.Settings.Plugin.Highlighting,
  dpcc.Core.Settings.Plugin.Issues,
  dpcc.Core.Settings.Plugin.Keys,
  dpcc.Core.Settings.Plugin.Rules,
  dpcc.Core.Settings.Plugin.Store,
  dpcc.Core.Settings.Plugin.VersionControl,
  dpcc.Core.Settings.Plugin.Welcome;

type
  /// <summary>Ablage für Einstellungen (dpcc.Core.Settings.Plugin.Store).</summary>
  IDpccSettingsStore = dpcc.Core.Settings.Plugin.Store.IDpccSettingsStore;
  /// <summary>Ablage, die gespeicherte Namen kennt und entfernen kann (dpcc.Core.Settings.Plugin.Store).</summary>
  IDpccSettingsNames = dpcc.Core.Settings.Plugin.Store.IDpccSettingsNames;

  TDpccPluginSettings = record
  private
    FCompletion: TDpccPluginCompletionSettings;
    FEditingKeys: TDpccPluginEditingKeysSettings;
    FKeyPriorities: TDpccPluginKeyPrioritiesSettings;
    FEditorTyping: TDpccPluginEditorTypingSettings;
    FGeneralServer: TDpccPluginGeneralServerSettings;
    FHighlighting: TDpccPluginHighlightingSettings;
    FEditorInsight: TDpccPluginEditorInsightSettings;
    FBookmarks: TDpccPluginBookmarksSettings;
    FNavigationKeys: TDpccPluginNavigationKeysSettings;
    FEditorNavigation: TDpccPluginEditorNavigationSettings;
    FRules: TDpccPluginRulesSettings;
    FBuild: TDpccPluginBuildSettings;
    FCodeActions: TDpccPluginCodeActionsSettings;
    FDebug: TDpccPluginDebugSettings;
    FGeneral: TDpccPluginGeneralSettings;
    FUnitSearch: TDpccPluginUnitSearchSettings;
    FEditorView: TDpccPluginEditorViewSettings;
    FIssues: TDpccPluginIssuesSettings;
    FWelcome: TDpccPluginWelcomeSettings;
    FWelcomeTiles: TDpccPluginWelcomeTilesSettings;
    FIssueWork: TDpccPluginIssueWorkSettings;
    FVcs: TDpccPluginVcsSettings;
    procedure Exchange(const AIo: TDpccSettingsExchange);
  public const
    cMinVisibleRows = dpcc.Core.Settings.Plugin.Completion.cMinVisibleRows;
    cMaxVisibleRows = dpcc.Core.Settings.Plugin.Completion.cMaxVisibleRows;
    cMinListWidth = dpcc.Core.Settings.Plugin.Completion.cMinListWidth;
    cMaxXmlDocLines = dpcc.Core.Settings.Plugin.Editor.cMaxXmlDocLines;
    cMinPeekLines = dpcc.Core.Settings.Plugin.Editor.cMinPeekLines;
    cMaxPeekLines = dpcc.Core.Settings.Plugin.Editor.cMaxPeekLines;
    cMinImpactDepth = dpcc.Core.Settings.Plugin.Editor.cMinImpactDepth;
    cMaxImpactDepth = dpcc.Core.Settings.Plugin.Editor.cMaxImpactDepth;
    cMinTestsAffectedDepth = dpcc.Core.Settings.Plugin.Build.cMinTestsAffectedDepth;
    cMaxTestsAffectedDepth = dpcc.Core.Settings.Plugin.Build.cMaxTestsAffectedDepth;
    cMinDataFlowDepth = dpcc.Core.Settings.Plugin.Editor.cMinDataFlowDepth;
    cMaxDataFlowDepth = dpcc.Core.Settings.Plugin.Editor.cMaxDataFlowDepth;
    cMinInlineValuesPerLine = dpcc.Core.Settings.Plugin.Debug.cMinInlineValuesPerLine;
    cMaxQuickChordWait = dpcc.Core.Settings.Plugin.Bookmarks.cMaxQuickChordWait;
    cMinRecursionDepth = dpcc.Core.Settings.Plugin.Editor.cMinRecursionDepth;
    cMaxRecursionDepth = dpcc.Core.Settings.Plugin.Editor.cMaxRecursionDepth;
    cMaxOpenDelay = dpcc.Core.Settings.Plugin.Completion.cMaxOpenDelay;
    cMinSafeStartupTimeout = dpcc.Core.Settings.Plugin.General.cMinSafeStartupTimeout;
    cMaxSafeSettingsHistory = dpcc.Core.Settings.Plugin.General.cMaxSafeSettingsHistory;
    cMinUndoDepth = dpcc.Core.Settings.Plugin.Editor.cMinUndoDepth;
    cMaxUndoDepth = dpcc.Core.Settings.Plugin.Editor.cMaxUndoDepth;
    cMinUndoMaxSizeMb = dpcc.Core.Settings.Plugin.Editor.cMinUndoMaxSizeMb;
    cMaxUndoMaxSizeMb = dpcc.Core.Settings.Plugin.Editor.cMaxUndoMaxSizeMb;
    cMaxSearchHistory = dpcc.Core.Settings.Plugin.Editor.cMaxSearchHistory;
    cMinContinueCount = dpcc.Core.Settings.Plugin.Welcome.cMinContinueCount;
    cMaxContinueCount = dpcc.Core.Settings.Plugin.Welcome.cMaxContinueCount;
    cMinContinueIssuesCount = dpcc.Core.Settings.Plugin.Welcome.cMinContinueIssuesCount;
    cMaxContinueIssuesCount = dpcc.Core.Settings.Plugin.Welcome.cMaxContinueIssuesCount;
    cMinTrendPoints = dpcc.Core.Settings.Plugin.Welcome.cMinTrendPoints;
    cMaxTrendPoints = dpcc.Core.Settings.Plugin.Welcome.cMaxTrendPoints;
    cMinTestFailures = dpcc.Core.Settings.Plugin.Welcome.cMinTestFailures;
    cMaxTestFailures = dpcc.Core.Settings.Plugin.Welcome.cMaxTestFailures;
    cMinCiIntervalMinutes = dpcc.Core.Settings.Plugin.Welcome.cMinCiIntervalMinutes;
    cMaxCiIntervalMinutes = dpcc.Core.Settings.Plugin.Welcome.cMaxCiIntervalMinutes;
    cDefaultCiProvider = dpcc.Core.Settings.Plugin.Welcome.cDefaultCiProvider;
    cIssuesStartBranch = dpcc.Core.Settings.Plugin.Issues.cIssuesStartBranch;
    cIssuesStartRemember = dpcc.Core.Settings.Plugin.Issues.cIssuesStartRemember;
    cDefaultIssuesEndComment = dpcc.Core.Settings.Plugin.Issues.cDefaultIssuesEndComment;
    cDefaultIssuesReviewComment = dpcc.Core.Settings.Plugin.Issues.cDefaultIssuesReviewComment;
    cDefaultIssuesCommentSnippets = dpcc.Core.Settings.Plugin.Issues.cDefaultIssuesCommentSnippets;
    cMaxIssuesTemplate = dpcc.Core.Settings.Plugin.Issues.cMaxIssuesTemplate;
    cMinIssuesIdleMinutes = dpcc.Core.Settings.Plugin.Issues.cMinIssuesIdleMinutes;
    cMaxIssuesTimeRounding = dpcc.Core.Settings.Plugin.Issues.cMaxIssuesTimeRounding;
    cMinIssuesNotifyMinutes = dpcc.Core.Settings.Plugin.Issues.cMinIssuesNotifyMinutes;
    cDefaultIssuesNotifyMinutes = dpcc.Core.Settings.Plugin.Issues.cDefaultIssuesNotifyMinutes;
    cIssuesNotifyAssigned = dpcc.Core.Settings.Plugin.Issues.cIssuesNotifyAssigned;
    cIssuesNotifyAssignedOrCreated = dpcc.Core.Settings.Plugin.Issues.cIssuesNotifyAssignedOrCreated;
    cIssuesNotifyWatched = dpcc.Core.Settings.Plugin.Issues.cIssuesNotifyWatched;
    cIssuesSprintAsk = dpcc.Core.Settings.Plugin.Issues.cIssuesSprintAsk;
    cIssuesSprintAlways = dpcc.Core.Settings.Plugin.Issues.cIssuesSprintAlways;
    cIssuesSprintNever = dpcc.Core.Settings.Plugin.Issues.cIssuesSprintNever;
    cBeginEndAlways = dpcc.Core.Settings.Plugin.Editor.cBeginEndAlways;
    cBeginEndMultiLine = dpcc.Core.Settings.Plugin.Editor.cBeginEndMultiLine;
    cBeginEndNever = dpcc.Core.Settings.Plugin.Editor.cBeginEndNever;
    cTryKindFinally = dpcc.Core.Settings.Plugin.Editor.cTryKindFinally;
    cTryKindExcept = dpcc.Core.Settings.Plugin.Editor.cTryKindExcept;
    cTryKindAsk = dpcc.Core.Settings.Plugin.Editor.cTryKindAsk;
    cMultiCursorModifierAlt = dpcc.Core.Settings.Plugin.Editor.cMultiCursorModifierAlt;
    cMultiCursorModifierCtrl = dpcc.Core.Settings.Plugin.Editor.cMultiCursorModifierCtrl;
    cDesignerSearchWindow = dpcc.Core.Settings.Plugin.Editor.cDesignerSearchWindow;
    cHelpSourceOnline = dpcc.Core.Settings.Plugin.General.cHelpSourceOnline;
    cHelpSourceLocal = dpcc.Core.Settings.Plugin.General.cHelpSourceLocal;
    cDesignerSearchPopup = dpcc.Core.Settings.Plugin.Editor.cDesignerSearchPopup;
    cDesignerScopeForm = dpcc.Core.Settings.Plugin.Editor.cDesignerScopeForm;
    cDesignerUsagesUnit = dpcc.Core.Settings.Plugin.Editor.cDesignerUsagesUnit;
    cDesignerUsagesProject = dpcc.Core.Settings.Plugin.Editor.cDesignerUsagesProject;
    cDesignerUsagesGroup = dpcc.Core.Settings.Plugin.Editor.cDesignerUsagesGroup;
    cDesignerScopeParent = dpcc.Core.Settings.Plugin.Editor.cDesignerScopeParent;
    cDesignerSetsLocal = dpcc.Core.Settings.Plugin.Editor.cDesignerSetsLocal;
    cDesignerSetsShared = dpcc.Core.Settings.Plugin.Editor.cDesignerSetsShared;
    cDesignerGroupsAltClick = dpcc.Core.Settings.Plugin.Editor.cDesignerGroupsAltClick;
    cDesignerGroupsDoubleClick = dpcc.Core.Settings.Plugin.Editor.cDesignerGroupsDoubleClick;
    cFitSourceCaption = dpcc.Core.Settings.Plugin.Editor.cFitSourceCaption;
    cGapAnchorCenter = dpcc.Core.Settings.Plugin.Editor.cGapAnchorCenter;
    cGapAnchorFirst = dpcc.Core.Settings.Plugin.Editor.cGapAnchorFirst;
    cGapAnchorLast = dpcc.Core.Settings.Plugin.Editor.cGapAnchorLast;
    cResizeModeDelta = dpcc.Core.Settings.Plugin.Editor.cResizeModeDelta;
    cResizeModeAlign = dpcc.Core.Settings.Plugin.Editor.cResizeModeAlign;
    cSelectionBarAuto = dpcc.Core.Settings.Plugin.Editor.cSelectionBarAuto;
    cSelectionBarShortcut = dpcc.Core.Settings.Plugin.Editor.cSelectionBarShortcut;
    cFitSourceText = dpcc.Core.Settings.Plugin.Editor.cFitSourceText;
    cFitSourceItems = dpcc.Core.Settings.Plugin.Editor.cFitSourceItems;
    cButtonBarBottomRight = dpcc.Core.Settings.Plugin.Editor.cButtonBarBottomRight;
    cButtonBarBottomLeft = dpcc.Core.Settings.Plugin.Editor.cButtonBarBottomLeft;
    cButtonBarRightTop = dpcc.Core.Settings.Plugin.Editor.cButtonBarRightTop;
    cButtonBarRightBottom = dpcc.Core.Settings.Plugin.Editor.cButtonBarRightBottom;
    cLabelLeft = dpcc.Core.Settings.Plugin.Editor.cLabelLeft;
    cLabelAbove = dpcc.Core.Settings.Plugin.Editor.cLabelAbove;
    cGridLabelLeft = dpcc.Core.Settings.Plugin.Editor.cGridLabelLeft;
    cGridLabelRight = dpcc.Core.Settings.Plugin.Editor.cGridLabelRight;
    cGridLabelAbove = dpcc.Core.Settings.Plugin.Editor.cGridLabelAbove;
    cMinNotificationEntries = dpcc.Core.Settings.Plugin.General.cMinNotificationEntries;
    cMaxNotificationEntries = dpcc.Core.Settings.Plugin.General.cMaxNotificationEntries;
    cDefaultTrendSeries = dpcc.Core.Settings.Plugin.Welcome.cDefaultTrendSeries;
    cDefaultHelpReportUrl = dpcc.Core.Settings.Plugin.Welcome.cDefaultHelpReportUrl;
  public
    class function Defaults: TDpccPluginSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    procedure Load(const AStore: IDpccSettingsStore);
    procedure Save(const AStore: IDpccSettingsStore);
    property Enabled: Boolean read FCompletion.Enabled write FCompletion.Enabled;
    property VisibleRows: Integer read FCompletion.VisibleRows write FCompletion.VisibleRows;
    property ListWidth: Integer read FCompletion.ListWidth write FCompletion.ListWidth;
    property AutoParentheses: Boolean read FCompletion.AutoParentheses write FCompletion.AutoParentheses;
    property FixCase: Boolean read FCompletion.FixCase write FCompletion.FixCase;
    property CommitCharacters: Boolean read FCompletion.CommitCharacters write FCompletion.CommitCharacters;
    property AutoUses: Boolean read FCompletion.AutoUses write FCompletion.AutoUses;
    property ParameterHints: Boolean read FCompletion.ParameterHints write FCompletion.ParameterHints;
    property FormatPlaceholders: Boolean read FCompletion.FormatPlaceholders write FCompletion.FormatPlaceholders;
    property OpenDelayMs: Integer read FCompletion.OpenDelayMs write FCompletion.OpenDelayMs;
    property PaletteKey: Integer read FEditingKeys.PaletteKey write FEditingKeys.PaletteKey;
    property CheckKey: Integer read FEditingKeys.CheckKey write FEditingKeys.CheckKey;
    property PaletteKeyPriority: Boolean read FKeyPriorities.PaletteKeyPriority write FKeyPriorities.PaletteKeyPriority;
    property CheckKeyPriority: Boolean read FKeyPriorities.CheckKeyPriority write FKeyPriorities.CheckKeyPriority;
    property CompletionKey: Integer read FEditingKeys.CompletionKey write FEditingKeys.CompletionKey;
    property SignatureKey: Integer read FEditingKeys.SignatureKey write FEditingKeys.SignatureKey;
    property CompletionKeyPriority: Boolean read FKeyPriorities.CompletionKeyPriority
      write FKeyPriorities.CompletionKeyPriority;
    property SignatureKeyPriority: Boolean read FKeyPriorities.SignatureKeyPriority
      write FKeyPriorities.SignatureKeyPriority;
    property Learning: Boolean read FCompletion.Learning write FCompletion.Learning;
    property Favorites: Boolean read FCompletion.Favorites write FCompletion.Favorites;
    property GroupInherited: Boolean read FCompletion.GroupInherited write FCompletion.GroupInherited;
    property CompletionVariantBranch: Boolean read FCompletion.CompletionVariantBranch
      write FCompletion.CompletionVariantBranch;
    property CompletionListMode: string read FCompletion.CompletionListMode write FCompletion.CompletionListMode;
    property CompletionListScope: string read FCompletion.CompletionListScope write FCompletion.CompletionListScope;
    property Preview: Boolean read FCompletion.Preview write FCompletion.Preview;
    property HoverTooltip: Boolean read FEditorTyping.HoverTooltip write FEditorTyping.HoverTooltip;
    property RecursionMarkers: Boolean read FEditorTyping.RecursionMarkers write FEditorTyping.RecursionMarkers;
    property RecursionMarkersDepth: Integer read FEditorTyping.RecursionMarkersDepth
      write FEditorTyping.RecursionMarkersDepth;
    property Notes: Boolean read FEditorInsight.Notes write FEditorInsight.Notes;
    property BookmarksNamed: Boolean read FBookmarks.BookmarksNamed write FBookmarks.BookmarksNamed;
    property BookmarksShared: Boolean read FBookmarks.BookmarksShared write FBookmarks.BookmarksShared;
    property BookmarkKey: Integer read FNavigationKeys.BookmarkKey write FNavigationKeys.BookmarkKey;
    property HideElementKey: Integer read FNavigationKeys.HideElementKey write FNavigationKeys.HideElementKey;
    property SearchReplaceIde: Boolean read FEditorNavigation.SearchReplaceIde write FEditorNavigation.SearchReplaceIde;
    property SearchResultsInMessages: Boolean read FEditorNavigation.SearchResultsInMessages
      write FEditorNavigation.SearchResultsInMessages;
    property SearchReplace: Boolean read FEditorNavigation.SearchReplace write FEditorNavigation.SearchReplace;
    property SearchRegex: Boolean read FEditorNavigation.SearchRegex write FEditorNavigation.SearchRegex;
    property SearchHistory: Integer read FEditorNavigation.SearchHistory write FEditorNavigation.SearchHistory;
    property SearchMultiFile: Boolean read FEditorNavigation.SearchMultiFile write FEditorNavigation.SearchMultiFile;
    property SearchReplaceKey: Integer read FNavigationKeys.SearchReplaceKey write FNavigationKeys.SearchReplaceKey;
    property SearchFromFirstHit: Boolean read FEditorNavigation.SearchFromFirstHit
      write FEditorNavigation.SearchFromFirstHit;
    property SearchKey: Integer read FNavigationKeys.SearchKey write FNavigationKeys.SearchKey;
    property SearchNextKey: Integer read FNavigationKeys.SearchNextKey write FNavigationKeys.SearchNextKey;
    property SearchPreviousKey: Integer read FNavigationKeys.SearchPreviousKey write FNavigationKeys.SearchPreviousKey;
    property SearchMethodKey: Integer read FNavigationKeys.SearchMethodKey write FNavigationKeys.SearchMethodKey;
    property PairColorsLight: string read FHighlighting.PairColorsLight write FHighlighting.PairColorsLight;
    property PairColorsDark: string read FHighlighting.PairColorsDark write FHighlighting.PairColorsDark;
    property NestedRoutineColorLight: string read FHighlighting.NestedRoutineColorLight
      write FHighlighting.NestedRoutineColorLight;
    property NestedRoutineColorDark: string read FHighlighting.NestedRoutineColorDark
      write FHighlighting.NestedRoutineColorDark;
    property Problems: Boolean read FEditorInsight.Problems write FEditorInsight.Problems;
    property ProblemsMessageList: Boolean read FRules.ProblemsMessageList write FRules.ProblemsMessageList;
    property ProblemsWindow: Boolean read FRules.ProblemsWindow write FRules.ProblemsWindow;
    property ProblemsWindowScope: string read FRules.ProblemsWindowScope write FRules.ProblemsWindowScope;
    property ProblemsWindowScopeProjects: Boolean read FRules.ProblemsWindowScopeProjects
      write FRules.ProblemsWindowScopeProjects;
    property ProblemsWindowScopeProject: string read FRules.ProblemsWindowScopeProject
      write FRules.ProblemsWindowScopeProject;
    property ProblemsWindowGroupBy: string read FRules.ProblemsWindowGroupBy write FRules.ProblemsWindowGroupBy;
    property ProblemsWindowColumns: string read FRules.ProblemsWindowColumns write FRules.ProblemsWindowColumns;
    property ProblemsWindowCompiler: Boolean read FRules.ProblemsWindowCompiler write FRules.ProblemsWindowCompiler;
    property ProblemsWindowFollowCursor: Boolean read FRules.ProblemsWindowFollowCursor
      write FRules.ProblemsWindowFollowCursor;
    property ProblemsWindowOpenFirst: Boolean read FRules.ProblemsWindowOpenFirst write FRules.ProblemsWindowOpenFirst;
    property ProblemsWindowClosedUnits: string read FRules.ProblemsWindowClosedUnits
      write FRules.ProblemsWindowClosedUnits;
    property ProblemsWindowShowCleanActive: Boolean read FRules.ProblemsWindowShowCleanActive
      write FRules.ProblemsWindowShowCleanActive;
    property ProblemsCompilerMerge: string read FRules.ProblemsCompilerMerge write FRules.ProblemsCompilerMerge;
    property ProblemsShowCompilerCode: Boolean read FRules.ProblemsShowCompilerCode
      write FRules.ProblemsShowCompilerCode;
    property ProblemsIdeErrors: Boolean read FRules.ProblemsIdeErrors write FRules.ProblemsIdeErrors;
    property ProblemsWindowKey: Integer read FNavigationKeys.ProblemsWindowKey write FNavigationKeys.ProblemsWindowKey;
    property CheckFileKey: Integer read FNavigationKeys.CheckFileKey write FNavigationKeys.CheckFileKey;
    property CreateIssueKey: Integer read FEditingKeys.CreateIssueKey write FEditingKeys.CreateIssueKey;
    property GotoInterfaceKey: Integer read FNavigationKeys.GotoInterfaceKey write FNavigationKeys.GotoInterfaceKey;
    property GotoImplementationKey: Integer read FNavigationKeys.GotoImplementationKey
      write FNavigationKeys.GotoImplementationKey;
    property ProblemsUpdate: string read FRules.ProblemsUpdate write FRules.ProblemsUpdate;
    property ProblemsLiveDelayMs: Integer read FRules.ProblemsLiveDelayMs write FRules.ProblemsLiveDelayMs;
    property FixBulk: Boolean read FRules.FixBulk write FRules.FixBulk;
    property InlineDiagnostics: string read FEditorTyping.InlineDiagnostics write FEditorTyping.InlineDiagnostics;
    property TrackLines: Boolean read FEditorTyping.TrackLines write FEditorTyping.TrackLines;
    property ProblemsStatusCounter: Boolean read FEditorInsight.ProblemsStatusCounter
      write FEditorInsight.ProblemsStatusCounter;
    property NextProblemKey: Integer read FNavigationKeys.NextProblemKey write FNavigationKeys.NextProblemKey;
    property PreviousProblemKey: Integer read FNavigationKeys.PreviousProblemKey
      write FNavigationKeys.PreviousProblemKey;
    property CheckOnSave: Boolean read FBuild.CheckOnSave write FBuild.CheckOnSave;
    property CompileOnSave: Boolean read FBuild.CompileOnSave write FBuild.CompileOnSave;
    property CheckOnSaveDelayMs: Integer read FBuild.CheckOnSaveDelayMs write FBuild.CheckOnSaveDelayMs;
    property CheckOnSaveMaxMs: Integer read FBuild.CheckOnSaveMaxMs write FBuild.CheckOnSaveMaxMs;
    property McpBuild: Boolean read FBuild.McpBuild write FBuild.McpBuild;
    property AssistantsEnabled: Boolean read FBuild.AssistantsEnabled write FBuild.AssistantsEnabled;
    property AssistantsEdit: Boolean read FBuild.AssistantsEdit write FBuild.AssistantsEdit;
    property BuildOnOpen: Boolean read FBuild.BuildOnOpen write FBuild.BuildOnOpen;
    property BuildOnOpenKind: string read FBuild.BuildOnOpenKind write FBuild.BuildOnOpenKind;
    property BuildOnOpenScope: string read FBuild.BuildOnOpenScope write FBuild.BuildOnOpenScope;
    property BuildOnOpenDelayMs: Integer read FBuild.BuildOnOpenDelayMs write FBuild.BuildOnOpenDelayMs;
    property BuildOnOpenExclude: string read FBuild.BuildOnOpenExclude write FBuild.BuildOnOpenExclude;
    property BuildOnOpenConfig: string read FBuild.BuildOnOpenConfig write FBuild.BuildOnOpenConfig;
    property BuildOnOpenPlatform: string read FBuild.BuildOnOpenPlatform write FBuild.BuildOnOpenPlatform;
    property ActionsKey: Integer read FEditingKeys.ActionsKey write FEditingKeys.ActionsKey;
    property ExpandKey: Integer read FEditingKeys.ExpandKey write FEditingKeys.ExpandKey;
    property ShrinkKey: Integer read FEditingKeys.ShrinkKey write FEditingKeys.ShrinkKey;
    property ImplementationKey: Integer read FNavigationKeys.ImplementationKey write FNavigationKeys.ImplementationKey;
    property TypeDefinitionKey: Integer read FNavigationKeys.TypeDefinitionKey write FNavigationKeys.TypeDefinitionKey;
    property MethodToggle: Boolean read FCodeActions.MethodToggle write FCodeActions.MethodToggle;
    property MethodToggleUpKey: Integer read FNavigationKeys.MethodToggleUpKey write FNavigationKeys.MethodToggleUpKey;
    property MethodToggleDownKey: Integer read FNavigationKeys.MethodToggleDownKey
      write FNavigationKeys.MethodToggleDownKey;
    property TestUnitKey: Integer read FEditingKeys.TestUnitKey write FEditingKeys.TestUnitKey;
    property CodeLensTestUnit: Boolean read FEditorInsight.CodeLensTestUnit write FEditorInsight.CodeLensTestUnit;
    property CodeLensMetrics: Boolean read FEditorInsight.CodeLensMetrics write FEditorInsight.CodeLensMetrics;
    property Metrics: Boolean read FEditorInsight.Metrics write FEditorInsight.Metrics;
    property CodeLensTests: Boolean read FEditorInsight.CodeLensTests write FEditorInsight.CodeLensTests;
    property TestRun: Boolean read FBuild.TestRun write FBuild.TestRun;
    property TestsAfterBuild: Boolean read FBuild.TestsAfterBuild write FBuild.TestsAfterBuild;
    property TestsBuildFirst: Boolean read FBuild.TestsBuildFirst write FBuild.TestsBuildFirst;
    property TestsAffected: Boolean read FBuild.TestsAffected write FBuild.TestsAffected;
    property TestsAffectedDepth: Integer read FBuild.TestsAffectedDepth write FBuild.TestsAffectedDepth;
    property TestsAffectedBeforeCommit: Boolean read FBuild.TestsAffectedBeforeCommit
      write FBuild.TestsAffectedBeforeCommit;
    property BuildZeroHints: Boolean read FBuild.BuildZeroHints write FBuild.BuildZeroHints;
    property ShowInterfaceCost: Boolean read FBuild.ShowInterfaceCost write FBuild.ShowInterfaceCost;
    property BuildSummary: Boolean read FBuild.BuildSummary write FBuild.BuildSummary;
    property BuildWarningsAsErrors: string read FBuild.BuildWarningsAsErrors write FBuild.BuildWarningsAsErrors;
    property BuildCompilerSwitches: Boolean read FBuild.BuildCompilerSwitches write FBuild.BuildCompilerSwitches;
    property BuildSwitchesInStatusBar: Boolean read FBuild.BuildSwitchesInStatusBar
      write FBuild.BuildSwitchesInStatusBar;
    property ReleaseGuard: Boolean read FBuild.ReleaseGuard write FBuild.ReleaseGuard;
    property BuildGate: string read FBuild.BuildGate write FBuild.BuildGate;
    property TasksEnabled: Boolean read FBuild.TasksEnabled write FBuild.TasksEnabled;
    property TasksProblemsFromOutput: Boolean read FBuild.TasksProblemsFromOutput write FBuild.TasksProblemsFromOutput;
    property TasksBeforeBuild: string read FBuild.TasksBeforeBuild write FBuild.TasksBeforeBuild;
    property TasksSaveBeforeRun: Boolean read FBuild.TasksSaveBeforeRun write FBuild.TasksSaveBeforeRun;
    property TasksRunChecksParallel: Boolean read FBuild.TasksRunChecksParallel write FBuild.TasksRunChecksParallel;
    property TasksOnlyFindings: Boolean read FBuild.TasksOnlyFindings write FBuild.TasksOnlyFindings;
    property BuildGateTimeoutMs: Integer read FBuild.BuildGateTimeoutMs write FBuild.BuildGateTimeoutMs;
    property ReleaseConfigs: string read FBuild.ReleaseConfigs write FBuild.ReleaseConfigs;
    property ReleaseChecks: string read FBuild.ReleaseChecks write FBuild.ReleaseChecks;
    property TestDebug: Boolean read FDebug.TestDebug write FDebug.TestDebug;
    property TestBreakAtStart: Boolean read FDebug.TestBreakAtStart write FDebug.TestBreakAtStart;
    property DebugHoverValues: Boolean read FDebug.DebugHoverValues write FDebug.DebugHoverValues;
    property DebugVisualizers: Boolean read FDebug.DebugVisualizers write FDebug.DebugVisualizers;
    property DebugVisualizerTypes: string read FDebug.DebugVisualizerTypes write FDebug.DebugVisualizerTypes;
    property DebugVisualizerNameFields: string read FDebug.DebugVisualizerNameFields
      write FDebug.DebugVisualizerNameFields;
    property DebugVisualizerMaxLength: Integer read FDebug.DebugVisualizerMaxLength
      write FDebug.DebugVisualizerMaxLength;
    property DebugVisualizerTimeoutMs: Integer read FDebug.DebugVisualizerTimeoutMs
      write FDebug.DebugVisualizerTimeoutMs;
    property DebugVisualizerMaxImagePixels: Integer read FDebug.DebugVisualizerMaxImagePixels
      write FDebug.DebugVisualizerMaxImagePixels;
    property DebugVisualizerEvaluation: string read FDebug.DebugVisualizerEvaluation
      write FDebug.DebugVisualizerEvaluation;
    property DebugDisplayRules: Boolean read FDebug.DebugDisplayRules write FDebug.DebugDisplayRules;
    property DebugDisplayRulesAllowCalls: Boolean read FDebug.DebugDisplayRulesAllowCalls
      write FDebug.DebugDisplayRulesAllowCalls;
    property DebugStepIntoTarget: Boolean read FDebug.DebugStepIntoTarget write FDebug.DebugStepIntoTarget;
    property DebugStepFilters: Boolean read FDebug.DebugStepFilters write FDebug.DebugStepFilters;
    property DebugStepFilterKinds: string read FDebug.DebugStepFilterKinds write FDebug.DebugStepFilterKinds;
    property DebugStepFilterPatterns: string read FDebug.DebugStepFilterPatterns write FDebug.DebugStepFilterPatterns;
    property DebugStepIntoTargetKey: Integer read FDebug.DebugStepIntoTargetKey write FDebug.DebugStepIntoTargetKey;
    property DebugBreakOnNextEvent: Boolean read FDebug.DebugBreakOnNextEvent write FDebug.DebugBreakOnNextEvent;
    property DebugBreakOnNextEventExcluded: string read FDebug.DebugBreakOnNextEventExcluded
      write FDebug.DebugBreakOnNextEventExcluded;
    property DebugExplainUnavailable: Boolean read FDebug.DebugExplainUnavailable write FDebug.DebugExplainUnavailable;
    property DebugCompletionInDialogs: Boolean read FDebug.DebugCompletionInDialogs
      write FDebug.DebugCompletionInDialogs;
    property DebugEvaluateWindow: Boolean read FDebug.DebugEvaluateWindow write FDebug.DebugEvaluateWindow;
    property DebugEvaluateReplaceCtrlF7: Boolean read FDebug.DebugEvaluateReplaceCtrlF7
      write FDebug.DebugEvaluateReplaceCtrlF7;
    property DebugExplainAccessViolation: Boolean read FDebug.DebugExplainAccessViolation
      write FDebug.DebugExplainAccessViolation;
    property DebugExplainAccessViolationAllowCalls: Boolean read FDebug.DebugExplainAccessViolationAllowCalls
      write FDebug.DebugExplainAccessViolationAllowCalls;
    property DebugExceptionHistory: Boolean read FDebug.DebugExceptionHistory write FDebug.DebugExceptionHistory;
    property DebugJustMyCode: Boolean read FDebug.DebugJustMyCode write FDebug.DebugJustMyCode;
    property DebugExceptionBanner: Boolean read FDebug.DebugExceptionBanner write FDebug.DebugExceptionBanner;
    property DebugExceptionBannerIgnoreAtLocation: Boolean read FDebug.DebugExceptionBannerIgnoreAtLocation
      write FDebug.DebugExceptionBannerIgnoreAtLocation;
    property DebugInlineValues: Boolean read FDebug.DebugInlineValues write FDebug.DebugInlineValues;
    property DebugInlineValuesPerLine: Integer read FDebug.DebugInlineValuesPerLine
      write FDebug.DebugInlineValuesPerLine;
    property DebugOwnCodeFolders: string read FDebug.DebugOwnCodeFolders write FDebug.DebugOwnCodeFolders;
    property StartProfiles: Boolean read FDebug.StartProfiles write FDebug.StartProfiles;
    property StartProfilesStatusField: Boolean read FDebug.StartProfilesStatusField
      write FDebug.StartProfilesStatusField;
    property TodoList: Boolean read FEditorInsight.TodoList write FEditorInsight.TodoList;
    property BaselineUpdate: Boolean read FEditorInsight.BaselineUpdate write FEditorInsight.BaselineUpdate;
    property MetricsReport: Boolean read FEditorInsight.MetricsReport write FEditorInsight.MetricsReport;
    property DfmPropertyRules: Boolean read FEditorInsight.DfmPropertyRules write FEditorInsight.DfmPropertyRules;
    property EditorKeysPriority: Boolean read FKeyPriorities.EditorKeysPriority write FKeyPriorities.EditorKeysPriority;
    property SlashCommands: Boolean read FCodeActions.SlashCommands write FCodeActions.SlashCommands;
    property GenerateMenu: Boolean read FCodeActions.GenerateMenu write FCodeActions.GenerateMenu;
    property ProjectContextMenu: Boolean read FCodeActions.ProjectContextMenu write FCodeActions.ProjectContextMenu;
    property GalleryWizards: Boolean read FCodeActions.GalleryWizards write FCodeActions.GalleryWizards;
    property EditorContextMenuContextual: Boolean read FCodeActions.EditorContextMenuContextual
      write FCodeActions.EditorContextMenuContextual;
    property EditorContextMenuGroups: string read FCodeActions.EditorContextMenuGroups
      write FCodeActions.EditorContextMenuGroups;
    property GenerateMenuKey: Integer read FEditingKeys.GenerateMenuKey write FEditingKeys.GenerateMenuKey;
    property GenerateMenuGroups: string read FCodeActions.GenerateMenuGroups write FCodeActions.GenerateMenuGroups;
    property GenerateMenuHidden: string read FCodeActions.GenerateMenuHidden write FCodeActions.GenerateMenuHidden;
    property GenerateMenuRecentFirst: Boolean read FCodeActions.GenerateMenuRecentFirst
      write FCodeActions.GenerateMenuRecentFirst;
    property GenerateMenuShowCommandNames: Boolean read FCodeActions.GenerateMenuShowCommandNames
      write FCodeActions.GenerateMenuShowCommandNames;
    property XmlDocExpand: string read FEditorInsight.XmlDocExpand write FEditorInsight.XmlDocExpand;
    property XmlDocMaxLines: Integer read FEditorInsight.XmlDocMaxLines write FEditorInsight.XmlDocMaxLines;
    property QuickToggleKey: Integer read FEditingKeys.QuickToggleKey write FEditingKeys.QuickToggleKey;
    property QuickToggleKeyPriority: Boolean read FKeyPriorities.QuickToggleKeyPriority
      write FKeyPriorities.QuickToggleKeyPriority;
    property DiagnosticModeKey: Integer read FEditingKeys.DiagnosticModeKey write FEditingKeys.DiagnosticModeKey;
    property DiagnosticModeKeyPriority: Boolean read FKeyPriorities.DiagnosticModeKeyPriority
      write FKeyPriorities.DiagnosticModeKeyPriority;
    property ArchitectureEnabled: Boolean read FGeneralServer.ArchitectureEnabled
      write FGeneralServer.ArchitectureEnabled;
    property QueryEnabled: Boolean read FGeneralServer.QueryEnabled write FGeneralServer.QueryEnabled;
    property ArchitectureScope: string read FGeneralServer.ArchitectureScope write FGeneralServer.ArchitectureScope;
    property ArchitectureIncludeLibraryUnits: Boolean read FGeneralServer.ArchitectureIncludeLibraryUnits
      write FGeneralServer.ArchitectureIncludeLibraryUnits;
    property ArchitectureCentralUnits: Integer read FGeneralServer.ArchitectureCentralUnits
      write FGeneralServer.ArchitectureCentralUnits;
    property ArchitectureWindowPlaced: Boolean read FGeneral.ArchitectureWindowPlaced
      write FGeneral.ArchitectureWindowPlaced;
    property UnitRelationsWindowPlaced: Boolean read FGeneral.UnitRelationsWindowPlaced
      write FGeneral.UnitRelationsWindowPlaced;
    property HotspotsEnabled: Boolean read FGeneralServer.HotspotsEnabled write FGeneralServer.HotspotsEnabled;
    property HotspotsMonths: Integer read FGeneralServer.HotspotsMonths write FGeneralServer.HotspotsMonths;
    property HotspotsCouplingMinCommits: Integer read FGeneralServer.HotspotsCouplingMinCommits
      write FGeneralServer.HotspotsCouplingMinCommits;
    property HotspotsWindowPlaced: Boolean read FGeneral.HotspotsWindowPlaced write FGeneral.HotspotsWindowPlaced;
    property SymbolPath: Boolean read FEditorNavigation.SymbolPath write FEditorNavigation.SymbolPath;
    property ExperimentalEnabled: Boolean read FGeneralServer.ExperimentalEnabled
      write FGeneralServer.ExperimentalEnabled;
    /// <summary>index.officeAndWinRt (c1): OCX\Servers und WinRT vorab indizieren; Vorgabe aus.</summary>
    property IndexOfficeAndWinRt: Boolean read FGeneralServer.IndexOfficeAndWinRt
      write FGeneralServer.IndexOfficeAndWinRt;
    property SetupChecklist: Boolean read FGeneral.SetupChecklist write FGeneral.SetupChecklist;
    property SetupChecklistSeen: Boolean read FGeneral.SetupChecklistSeen write FGeneral.SetupChecklistSeen;
    property KeyOverview: Boolean read FNavigationKeys.KeyOverview write FNavigationKeys.KeyOverview;
    property KeyStartupCheck: Boolean read FEditingKeys.KeyStartupCheck write FEditingKeys.KeyStartupCheck;
    property SafeAskAfterCrash: Boolean read FGeneralServer.SafeAskAfterCrash write FGeneralServer.SafeAskAfterCrash;
    property SafeAutoAfterRepeatedCrash: Boolean read FGeneralServer.SafeAutoAfterRepeatedCrash
      write FGeneralServer.SafeAutoAfterRepeatedCrash;
    property SafeStartupKey: string read FGeneralServer.SafeStartupKey write FGeneralServer.SafeStartupKey;
    property SafeStartupTimeoutMs: Integer read FGeneralServer.SafeStartupTimeoutMs
      write FGeneralServer.SafeStartupTimeoutMs;
    property SafeKeepSettingsHistory: Integer read FGeneralServer.SafeKeepSettingsHistory
      write FGeneralServer.SafeKeepSettingsHistory;
    property UndoMultiFile: Boolean read FEditorInsight.UndoMultiFile write FEditorInsight.UndoMultiFile;
    property UndoMultiFileDepth: Integer read FEditorInsight.UndoMultiFileDepth write FEditorInsight.UndoMultiFileDepth;
    property UndoMultiFilePersist: Boolean read FEditorInsight.UndoMultiFilePersist
      write FEditorInsight.UndoMultiFilePersist;
    property UndoMultiFileMaxSizeMb: Integer read FEditorInsight.UndoMultiFileMaxSizeMb
      write FEditorInsight.UndoMultiFileMaxSizeMb;
    property UndoMultiFileOnConflict: string read FEditorInsight.UndoMultiFileOnConflict
      write FEditorInsight.UndoMultiFileOnConflict;
    property UndoMultiFileNewFiles: string read FEditorInsight.UndoMultiFileNewFiles
      write FEditorInsight.UndoMultiFileNewFiles;
    property UndoKey: Integer read FEditingKeys.UndoKey write FEditingKeys.UndoKey;
    property RedoKey: Integer read FEditingKeys.RedoKey write FEditingKeys.RedoKey;
    property UpdatesCheck: Boolean read FGeneral.UpdatesCheck write FGeneral.UpdatesCheck;
    property UpdatesInstall: string read FGeneral.UpdatesInstall write FGeneral.UpdatesInstall;
    property UpdatesChannel: string read FGeneral.UpdatesChannel write FGeneral.UpdatesChannel;
    property UpdatesNewModules: string read FGeneral.UpdatesNewModules write FGeneral.UpdatesNewModules;
    property BugReportAnonymize: Boolean read FGeneralServer.BugReportAnonymize write FGeneralServer.BugReportAnonymize;
    property LogNames: Boolean read FGeneralServer.LogNames write FGeneralServer.LogNames;
    property UnitSearchEnabled: Boolean read FUnitSearch.UnitSearchEnabled write FUnitSearch.UnitSearchEnabled;
    property UnitSearchReplaceIdeDialog: Boolean read FUnitSearch.UnitSearchReplaceIdeDialog
      write FUnitSearch.UnitSearchReplaceIdeDialog;
    property UnitSearchReplaceUseUnitDialog: Boolean read FUnitSearch.UnitSearchReplaceUseUnitDialog
      write FUnitSearch.UnitSearchReplaceUseUnitDialog;
    property UnitSearchReplaceFormsDialog: Boolean read FUnitSearch.UnitSearchReplaceFormsDialog
      write FUnitSearch.UnitSearchReplaceFormsDialog;
    property UnitSearchRememberCollapsed: Boolean read FUnitSearch.UnitSearchRememberCollapsed
      write FUnitSearch.UnitSearchRememberCollapsed;
    property UnitSearchFilters: Boolean read FUnitSearch.UnitSearchFilters write FUnitSearch.UnitSearchFilters;
    property UnitSearchFilterSyntax: Boolean read FUnitSearch.UnitSearchFilterSyntax
      write FUnitSearch.UnitSearchFilterSyntax;
    property UnitSearchFormCaptions: Boolean read FUnitSearch.UnitSearchFormCaptions
      write FUnitSearch.UnitSearchFormCaptions;
    property UnitSearchPreview: Boolean read FUnitSearch.UnitSearchPreview write FUnitSearch.UnitSearchPreview;
    property UnitSearchPreviewForm: Boolean read FUnitSearch.UnitSearchPreviewForm
      write FUnitSearch.UnitSearchPreviewForm;
    property UnitSearchPreviewUsedBy: Boolean read FUnitSearch.UnitSearchPreviewUsedBy
      write FUnitSearch.UnitSearchPreviewUsedBy;
    property UnitSearchPreviewAutoCollapse: Boolean read FUnitSearch.UnitSearchPreviewAutoCollapse
      write FUnitSearch.UnitSearchPreviewAutoCollapse;
    property UnitSearchMultiSelect: Boolean read FUnitSearch.UnitSearchMultiSelect
      write FUnitSearch.UnitSearchMultiSelect;
    property UnitSearchActions: Boolean read FUnitSearch.UnitSearchActions write FUnitSearch.UnitSearchActions;
    property UnitSearchActionsAddUses: Boolean read FUnitSearch.UnitSearchActionsAddUses
      write FUnitSearch.UnitSearchActionsAddUses;
    property UnitSearchPathStyle: string read FUnitSearch.UnitSearchPathStyle write FUnitSearch.UnitSearchPathStyle;
    property UnitSearchGroupBy: string read FUnitSearch.UnitSearchGroupBy write FUnitSearch.UnitSearchGroupBy;
    property UnitSearchDefaultScope: string read FUnitSearch.UnitSearchDefaultScope
      write FUnitSearch.UnitSearchDefaultScope;
    property UnitSearchKey: Integer read FNavigationKeys.UnitSearchKey write FNavigationKeys.UnitSearchKey;
    property QuickOpen: Boolean read FEditorNavigation.QuickOpen write FEditorNavigation.QuickOpen;
    property QuickOpenLibrary: Boolean read FEditorNavigation.QuickOpenLibrary write FEditorNavigation.QuickOpenLibrary;
    property QuickOpenKey: Integer read FNavigationKeys.QuickOpenKey write FNavigationKeys.QuickOpenKey;
    property NavHistory: Boolean read FEditorNavigation.NavHistory write FEditorNavigation.NavHistory;
    property NavBackKey: Integer read FNavigationKeys.NavBackKey write FNavigationKeys.NavBackKey;
    property NavForwardKey: Integer read FNavigationKeys.NavForwardKey write FNavigationKeys.NavForwardKey;
    property LastEditKey: Integer read FNavigationKeys.LastEditKey write FNavigationKeys.LastEditKey;
    property Peek: Boolean read FEditorNavigation.Peek write FEditorNavigation.Peek;
    property PeekHeightLines: Integer read FEditorNavigation.PeekHeightLines write FEditorNavigation.PeekHeightLines;
    property PeekShowImplementation: Boolean read FEditorNavigation.PeekShowImplementation
      write FEditorNavigation.PeekShowImplementation;
    property ReferencesInferred: Boolean read FEditorNavigation.ReferencesInferred
      write FEditorNavigation.ReferencesInferred;
    property ReferencesTextMatches: Boolean read FEditorNavigation.ReferencesTextMatches
      write FEditorNavigation.ReferencesTextMatches;
    property Impact: Boolean read FEditorNavigation.Impact write FEditorNavigation.Impact;
    property ImpactDepth: Integer read FEditorNavigation.ImpactDepth write FEditorNavigation.ImpactDepth;
    property DataFlow: Boolean read FEditorNavigation.DataFlow write FEditorNavigation.DataFlow;
    property DataFlowMaxDepth: Integer read FEditorNavigation.DataFlowMaxDepth write FEditorNavigation.DataFlowMaxDepth;
    property DataFlowExcludeTests: Boolean read FEditorNavigation.DataFlowExcludeTests
      write FEditorNavigation.DataFlowExcludeTests;
    property PeekDefinitionKey: Integer read FNavigationKeys.PeekDefinitionKey write FNavigationKeys.PeekDefinitionKey;
    property PeekReferencesKey: Integer read FNavigationKeys.PeekReferencesKey write FNavigationKeys.PeekReferencesKey;
    property Outline: Boolean read FEditorNavigation.Outline write FEditorNavigation.Outline;
    property OutlineAlphabetical: Boolean read FEditorNavigation.OutlineAlphabetical
      write FEditorNavigation.OutlineAlphabetical;
    property OutlineFollowCursor: Boolean read FEditorNavigation.OutlineFollowCursor
      write FEditorNavigation.OutlineFollowCursor;
    property OutlineConditions: Boolean read FEditorNavigation.OutlineConditions
      write FEditorNavigation.OutlineConditions;
    property EditorToolbar: Boolean read FEditorView.EditorToolbar write FEditorView.EditorToolbar;
    property EditorToolbarPosition: string read FEditorView.EditorToolbarPosition
      write FEditorView.EditorToolbarPosition;
    property EditorToolbarItems: string read FEditorView.EditorToolbarItems write FEditorView.EditorToolbarItems;
    property EditorToolbarReturnButton: Boolean read FEditorView.EditorToolbarReturnButton
      write FEditorView.EditorToolbarReturnButton;
    property EditorToolbarLabels: Boolean read FEditorView.EditorToolbarLabels write FEditorView.EditorToolbarLabels;
    property EditorDesignerBar: Boolean read FEditorView.EditorDesignerBar write FEditorView.EditorDesignerBar;
    property DesignerSearchKey: Integer read FEditorView.DesignerSearchKey write FEditorView.DesignerSearchKey;
    property DesignerSearchStyle: string read FEditorView.DesignerSearchStyle write FEditorView.DesignerSearchStyle;
    property DesignerFuzzySearch: Boolean read FEditorView.DesignerFuzzySearch write FEditorView.DesignerFuzzySearch;
    property DesignerTabOrderClick: Boolean read FEditorView.DesignerTabOrderClick
      write FEditorView.DesignerTabOrderClick;
    property DesignerTabOrderOverlay: Boolean read FEditorView.DesignerTabOrderOverlay
      write FEditorView.DesignerTabOrderOverlay;
    property DesignerTabOrderPaths: Boolean read FEditorView.DesignerTabOrderPaths
      write FEditorView.DesignerTabOrderPaths;
    property DesignerTabOrderColors: Boolean read FEditorView.DesignerTabOrderColors
      write FEditorView.DesignerTabOrderColors;
    property DesignerAlign: Boolean read FEditorView.DesignerAlign write FEditorView.DesignerAlign;
    property DesignerSelectSimilar: Boolean read FEditorView.DesignerSelectSimilar
      write FEditorView.DesignerSelectSimilar;
    property DesignerSelectDescendants: Boolean read FEditorView.DesignerSelectDescendants
      write FEditorView.DesignerSelectDescendants;
    property DesignerSelectScope: string read FEditorView.DesignerSelectScope write FEditorView.DesignerSelectScope;
    property DesignerSelectionSets: Boolean read FEditorView.DesignerSelectionSets
      write FEditorView.DesignerSelectionSets;
    property DesignerSelectionSetsShortcuts: Boolean read FEditorView.DesignerSelectionSetsShortcuts
      write FEditorView.DesignerSelectionSetsShortcuts;
    property DesignerSelectionSetsStorage: string read FEditorView.DesignerSelectionSetsStorage
      write FEditorView.DesignerSelectionSetsStorage;
    property DesignerSelectionSetsSaveKey: Integer read FEditorView.DesignerSelectionSetsSaveKey
      write FEditorView.DesignerSelectionSetsSaveKey;
    property DesignerShowInDesigner: Boolean read FEditorView.DesignerShowInDesigner
      write FEditorView.DesignerShowInDesigner;
    property DesignerShowInDesignerKey: Integer read FEditorView.DesignerShowInDesignerKey
      write FEditorView.DesignerShowInDesignerKey;
    property DesignerPropertySearch: Boolean read FEditorView.DesignerPropertySearch
      write FEditorView.DesignerPropertySearch;
    property DesignerUsages: Boolean read FEditorView.DesignerUsages write FEditorView.DesignerUsages;
    property DesignerUsagesStatusCount: Boolean read FEditorView.DesignerUsagesStatusCount
      write FEditorView.DesignerUsagesStatusCount;
    property DesignerUsagesScope: string read FEditorView.DesignerUsagesScope write FEditorView.DesignerUsagesScope;
    property DesignerUsagesKey: Integer read FEditorView.DesignerUsagesKey write FEditorView.DesignerUsagesKey;
    property DesignerSpatialNavigation: Boolean read FEditorView.DesignerSpatialNavigation
      write FEditorView.DesignerSpatialNavigation;
    property DesignerSpatialCrossContainers: Boolean read FEditorView.DesignerSpatialCrossContainers
      write FEditorView.DesignerSpatialCrossContainers;
    property DesignerMeasureDistances: Boolean read FEditorView.DesignerMeasureDistances
      write FEditorView.DesignerMeasureDistances;
    property DesignerMeasureAltKey: Boolean read FEditorView.DesignerMeasureAltKey
      write FEditorView.DesignerMeasureAltKey;
    property DesignerResizePreview: Boolean read FEditorView.DesignerResizePreview
      write FEditorView.DesignerResizePreview;
    property DesignerResizePreviewSizes: string read FEditorView.DesignerResizePreviewSizes
      write FEditorView.DesignerResizePreviewSizes;
    property DesignerResizePreviewShowAnchors: Boolean read FEditorView.DesignerResizePreviewShowAnchors
      write FEditorView.DesignerResizePreviewShowAnchors;
    property DesignerScalePreview: Boolean read FEditorView.DesignerScalePreview
      write FEditorView.DesignerScalePreview;
    property DesignerScalePreviewLevels: string read FEditorView.DesignerScalePreviewLevels
      write FEditorView.DesignerScalePreviewLevels;
    property DesignerScalePreviewScreens: string read FEditorView.DesignerScalePreviewScreens
      write FEditorView.DesignerScalePreviewScreens;
    property DesignerLongTextFactor: Integer read FEditorView.DesignerLongTextFactor
      write FEditorView.DesignerLongTextFactor;
    property DesignerNameSuggest: Boolean read FEditorView.DesignerNameSuggest write FEditorView.DesignerNameSuggest;
    property DesignerNameSuggestSources: string read FEditorView.DesignerNameSuggestSources
      write FEditorView.DesignerNameSuggestSources;
    property DesignerNameSuggestUmlauts: string read FEditorView.DesignerNameSuggestUmlauts
      write FEditorView.DesignerNameSuggestUmlauts;
    property DesignerNameSuggestRenameHandlers: Boolean read FEditorView.DesignerNameSuggestRenameHandlers
      write FEditorView.DesignerNameSuggestRenameHandlers;
    property DesignerNameSuggestPrefixes: string read FEditorView.DesignerNameSuggestPrefixes
      write FEditorView.DesignerNameSuggestPrefixes;
    property DesignerStructure: Boolean read FEditorView.DesignerStructure write FEditorView.DesignerStructure;
    property DesignerStructureHideOnForm: Boolean read FEditorView.DesignerStructureHideOnForm
      write FEditorView.DesignerStructureHideOnForm;
    property DesignerDataBindings: Boolean read FEditorView.DesignerDataBindings
      write FEditorView.DesignerDataBindings;
    property DesignerExtractFrame: Boolean read FEditorView.DesignerExtractFrame
      write FEditorView.DesignerExtractFrame;
    property DesignerEventMap: Boolean read FEditorView.DesignerEventMap write FEditorView.DesignerEventMap;
    property DesignerFitToText:Boolean read FEditorView.DesignerFitToText write FEditorView.DesignerFitToText;
    property DesignerFitToTextMinWidth: Integer read FEditorView.DesignerFitToTextMinWidth
      write FEditorView.DesignerFitToTextMinWidth;
    property DesignerFitToTextPadding: Integer read FEditorView.DesignerFitToTextPadding
      write FEditorView.DesignerFitToTextPadding;
    property DesignerFitToTextSources: string read FEditorView.DesignerFitToTextSources
      write FEditorView.DesignerFitToTextSources;
    property DesignerButtonBar: Boolean read FEditorView.DesignerButtonBar write FEditorView.DesignerButtonBar;
    property DesignerButtonBarOrder: string read FEditorView.DesignerButtonBarOrder
      write FEditorView.DesignerButtonBarOrder;
    property DesignerButtonBarPosition: string read FEditorView.DesignerButtonBarPosition
      write FEditorView.DesignerButtonBarPosition;
    property DesignerButtonBarGap: Integer read FEditorView.DesignerButtonBarGap write FEditorView.DesignerButtonBarGap;
    property DesignerButtonBarMargin: Integer read FEditorView.DesignerButtonBarMargin
      write FEditorView.DesignerButtonBarMargin;
    property DesignerButtonBarSetModalResult: Boolean read FEditorView.DesignerButtonBarSetModalResult
      write FEditorView.DesignerButtonBarSetModalResult;
    property DesignerButtonBarRoles: string read FEditorView.DesignerButtonBarRoles
      write FEditorView.DesignerButtonBarRoles;
    property DesignerDuplicateRow: Boolean read FEditorView.DesignerDuplicateRow
      write FEditorView.DesignerDuplicateRow;
    property DesignerDuplicateRowShareEvents: Boolean read FEditorView.DesignerDuplicateRowShareEvents
      write FEditorView.DesignerDuplicateRowShareEvents;
    property DesignerDuplicateRowDefaultGap: Integer read FEditorView.DesignerDuplicateRowDefaultGap
      write FEditorView.DesignerDuplicateRowDefaultGap;
    property DesignerInsertSpace: Boolean read FEditorView.DesignerInsertSpace
      write FEditorView.DesignerInsertSpace;
    property DesignerInsertSpaceGrowParent: Boolean read FEditorView.DesignerInsertSpaceGrowParent
      write FEditorView.DesignerInsertSpaceGrowParent;
    property DesignerFitContainer: Boolean read FEditorView.DesignerFitContainer
      write FEditorView.DesignerFitContainer;
    property DesignerFitContainerPadding: Integer read FEditorView.DesignerFitContainerPadding
      write FEditorView.DesignerFitContainerPadding;
    property DesignerFitContainerAlignTopLeft: Boolean read FEditorView.DesignerFitContainerAlignTopLeft
      write FEditorView.DesignerFitContainerAlignTopLeft;
    property DesignerNearAlignment: Boolean read FEditorView.DesignerNearAlignment
      write FEditorView.DesignerNearAlignment;
    property DesignerNearAlignmentTolerance: Integer read FEditorView.DesignerNearAlignmentTolerance
      write FEditorView.DesignerNearAlignmentTolerance;
    property DesignerNearAlignmentBaseline: Boolean read FEditorView.DesignerNearAlignmentBaseline
      write FEditorView.DesignerNearAlignmentBaseline;
    property DesignerNearAlignmentIgnoreClasses: string read FEditorView.DesignerNearAlignmentIgnoreClasses
      write FEditorView.DesignerNearAlignmentIgnoreClasses;
    property DesignerDefaultSizes: Boolean read FEditorView.DesignerDefaultSizes
      write FEditorView.DesignerDefaultSizes;
    property DesignerDefaultSizesTable: string read FEditorView.DesignerDefaultSizesTable
      write FEditorView.DesignerDefaultSizesTable;
    property DesignerDefaultSizesApplyOnInsert: Boolean read FEditorView.DesignerDefaultSizesApplyOnInsert
      write FEditorView.DesignerDefaultSizesApplyOnInsert;
    property DesignerDefaultSizesMarkDeviations: Boolean read FEditorView.DesignerDefaultSizesMarkDeviations
      write FEditorView.DesignerDefaultSizesMarkDeviations;
    property DesignerZOrder: Boolean read FEditorView.DesignerZOrder write FEditorView.DesignerZOrder;
    property DesignerZOrderShortcuts: Boolean read FEditorView.DesignerZOrderShortcuts
      write FEditorView.DesignerZOrderShortcuts;
    property DesignerZOrderIncludeParents: Boolean read FEditorView.DesignerZOrderIncludeParents
      write FEditorView.DesignerZOrderIncludeParents;
    property DesignerPropertyPainter: Boolean read FEditorView.DesignerPropertyPainter
      write FEditorView.DesignerPropertyPainter;
    property DesignerPropertyPainterDefaultGroups: string read FEditorView.DesignerPropertyPainterDefaultGroups
      write FEditorView.DesignerPropertyPainterDefaultGroups;
    property DesignerPropertyPainterRememberPerClass: Boolean read FEditorView.DesignerPropertyPainterRememberPerClass
      write FEditorView.DesignerPropertyPainterRememberPerClass;
    property DesignerSuggestAnchors: Boolean read FEditorView.DesignerSuggestAnchors
      write FEditorView.DesignerSuggestAnchors;
    property DesignerSuggestAnchorsEdgeDistance: Integer read FEditorView.DesignerSuggestAnchorsEdgeDistance
      write FEditorView.DesignerSuggestAnchorsEdgeDistance;
    property DesignerSuggestAnchorsKeepExisting: Boolean read FEditorView.DesignerSuggestAnchorsKeepExisting
      write FEditorView.DesignerSuggestAnchorsKeepExisting;
    property DesignerSuggestAnchorsFillClasses: string read FEditorView.DesignerSuggestAnchorsFillClasses
      write FEditorView.DesignerSuggestAnchorsFillClasses;
    property DesignerTextTable: Boolean read FEditorView.DesignerTextTable write FEditorView.DesignerTextTable;
    property DesignerTextTableChecks: string read FEditorView.DesignerTextTableChecks
      write FEditorView.DesignerTextTableChecks;
    property DesignerTextTableSynonyms: string read FEditorView.DesignerTextTableSynonyms
      write FEditorView.DesignerTextTableSynonyms;
    property DesignerTextTableExcludeProperties: string read FEditorView.DesignerTextTableExcludeProperties
      write FEditorView.DesignerTextTableExcludeProperties;
    property DesignerLabelPairs: Boolean read FEditorView.DesignerLabelPairs write FEditorView.DesignerLabelPairs;
    property DesignerLabelPairsBaseline: Boolean read FEditorView.DesignerLabelPairsBaseline
      write FEditorView.DesignerLabelPairsBaseline;
    property DesignerLabelPairsFocusControl: Boolean read FEditorView.DesignerLabelPairsFocusControl
      write FEditorView.DesignerLabelPairsFocusControl;
    property DesignerLabelPairsMoveTogether: Boolean read FEditorView.DesignerLabelPairsMoveTogether
      write FEditorView.DesignerLabelPairsMoveTogether;
    property DesignerLabelPairsPairDistance: Integer read FEditorView.DesignerLabelPairsPairDistance
      write FEditorView.DesignerLabelPairsPairDistance;
    property DesignerLabelPairsNewLabelPosition: string read FEditorView.DesignerLabelPairsNewLabelPosition
      write FEditorView.DesignerLabelPairsNewLabelPosition;
    property DesignerLabelPairsAbbreviations: string read FEditorView.DesignerLabelPairsAbbreviations
      write FEditorView.DesignerLabelPairsAbbreviations;
    property DesignerArrangeForm: Boolean read FEditorView.DesignerArrangeForm write FEditorView.DesignerArrangeForm;
    property DesignerArrangeFormRowGap: Integer read FEditorView.DesignerArrangeFormRowGap
      write FEditorView.DesignerArrangeFormRowGap;
    property DesignerArrangeFormLabelGap: Integer read FEditorView.DesignerArrangeFormLabelGap
      write FEditorView.DesignerArrangeFormLabelGap;
    property DesignerArrangeFormLabelAlign: string read FEditorView.DesignerArrangeFormLabelAlign
      write FEditorView.DesignerArrangeFormLabelAlign;
    property DesignerArrangeFormEqualFieldWidth: Boolean read FEditorView.DesignerArrangeFormEqualFieldWidth
      write FEditorView.DesignerArrangeFormEqualFieldWidth;
    property DesignerArrangeFormTwoPerRow: Boolean read FEditorView.DesignerArrangeFormTwoPerRow
      write FEditorView.DesignerArrangeFormTwoPerRow;
    property DesignerArrangeFormSetTabOrder: Boolean read FEditorView.DesignerArrangeFormSetTabOrder
      write FEditorView.DesignerArrangeFormSetTabOrder;
    property DesignerWrapInContainer: Boolean read FEditorView.DesignerWrapInContainer
      write FEditorView.DesignerWrapInContainer;
    property DesignerWrapInContainerPadding: Integer read FEditorView.DesignerWrapInContainerPadding
      write FEditorView.DesignerWrapInContainerPadding;
    property DesignerWrapInContainerDefaultClass: string read FEditorView.DesignerWrapInContainerDefaultClass
      write FEditorView.DesignerWrapInContainerDefaultClass;
    property DesignerWrapInContainerClasses: string read FEditorView.DesignerWrapInContainerClasses
      write FEditorView.DesignerWrapInContainerClasses;
    property DesignerFontsColors: Boolean read FEditorView.DesignerFontsColors write FEditorView.DesignerFontsColors;
    property DesignerFontsColorsRestoreParent: Boolean read FEditorView.DesignerFontsColorsRestoreParent
      write FEditorView.DesignerFontsColorsRestoreParent;
    property DesignerFontsColorsIgnoreColors: string read FEditorView.DesignerFontsColorsIgnoreColors
      write FEditorView.DesignerFontsColorsIgnoreColors;
    property DesignerGroups: Boolean read FEditorView.DesignerGroups write FEditorView.DesignerGroups;
    property DesignerGroupsMemberClick: string read FEditorView.DesignerGroupsMemberClick
      write FEditorView.DesignerGroupsMemberClick;
    property DesignerGroupsStorage: string read FEditorView.DesignerGroupsStorage
      write FEditorView.DesignerGroupsStorage;
    property DesignerInlineCaption: Boolean read FEditorView.DesignerInlineCaption
      write FEditorView.DesignerInlineCaption;
    property DesignerInlineCaptionSlowDoubleClick: Boolean read FEditorView.DesignerInlineCaptionSlowDoubleClick
      write FEditorView.DesignerInlineCaptionSlowDoubleClick;
    property DesignerInlineCaptionAutoWidth: Boolean read FEditorView.DesignerInlineCaptionAutoWidth
      write FEditorView.DesignerInlineCaptionAutoWidth;
    property DesignerInlineCaptionKey: Integer read FEditorView.DesignerInlineCaptionKey
      write FEditorView.DesignerInlineCaptionKey;
    property DesignerInlineCaptionProperties: string read FEditorView.DesignerInlineCaptionProperties
      write FEditorView.DesignerInlineCaptionProperties;
    property DesignerGapHandles: Boolean read FEditorView.DesignerGapHandles write FEditorView.DesignerGapHandles;
    property DesignerGapHandlesSnapValues: string read FEditorView.DesignerGapHandlesSnapValues
      write FEditorView.DesignerGapHandlesSnapValues;
    property DesignerGapHandlesAnchor: string read FEditorView.DesignerGapHandlesAnchor
      write FEditorView.DesignerGapHandlesAnchor;
    property DesignerMultiResize: Boolean read FEditorView.DesignerMultiResize write FEditorView.DesignerMultiResize;
    property DesignerMultiResizeMode: string read FEditorView.DesignerMultiResizeMode
      write FEditorView.DesignerMultiResizeMode;
    property DesignerMultiResizeLeftTopHandles: Boolean read FEditorView.DesignerMultiResizeLeftTopHandles
      write FEditorView.DesignerMultiResizeLeftTopHandles;
    property DesignerSelectionBar: Boolean read FEditorView.DesignerSelectionBar write FEditorView.DesignerSelectionBar;
    property DesignerSelectionBarMode: string read FEditorView.DesignerSelectionBarMode
      write FEditorView.DesignerSelectionBarMode;
    property DesignerSelectionBarDelayMs: Integer read FEditorView.DesignerSelectionBarDelayMs
      write FEditorView.DesignerSelectionBarDelayMs;
    property DesignerSelectionBarItems: string read FEditorView.DesignerSelectionBarItems
      write FEditorView.DesignerSelectionBarItems;
    property DesignerSelectionBarKey: Integer read FEditorView.DesignerSelectionBarKey
      write FEditorView.DesignerSelectionBarKey;
    property DesignerMagnifier: Boolean read FEditorView.DesignerMagnifier write FEditorView.DesignerMagnifier;
    property DesignerMagnifierZoom: Integer read FEditorView.DesignerMagnifierZoom
      write FEditorView.DesignerMagnifierZoom;
    property DesignerMagnifierGrid: Boolean read FEditorView.DesignerMagnifierGrid
      write FEditorView.DesignerMagnifierGrid;
    property DesignerMagnifierEdges: Boolean read FEditorView.DesignerMagnifierEdges
      write FEditorView.DesignerMagnifierEdges;
    property DesignerMagnifierKey: Integer read FEditorView.DesignerMagnifierKey
      write FEditorView.DesignerMagnifierKey;
    property DesignerUndo: Boolean read FEditorView.DesignerUndo write FEditorView.DesignerUndo;
    property DesignerUndoSteps: Integer read FEditorView.DesignerUndoSteps write FEditorView.DesignerUndoSteps;
    property QuickBookmarks: Boolean read FBookmarks.QuickBookmarks write FBookmarks.QuickBookmarks;
    property QuickBookmarksGutter: Boolean read FBookmarks.QuickBookmarksGutter write FBookmarks.QuickBookmarksGutter;
    property QuickBookmarksGutterClick: Boolean read FBookmarks.QuickBookmarksGutterClick
      write FBookmarks.QuickBookmarksGutterClick;
    property QuickBookmarksNumberedKeys: Boolean read FBookmarks.QuickBookmarksNumberedKeys
      write FBookmarks.QuickBookmarksNumberedKeys;
    property QuickBookmarkKey: Integer read FBookmarks.QuickBookmarkKey write FBookmarks.QuickBookmarkKey;
    property QuickBookmarkKeyPriority: Boolean read FKeyPriorities.QuickBookmarkKeyPriority
      write FKeyPriorities.QuickBookmarkKeyPriority;
    property QuickBookmarkChordWait: Integer read FBookmarks.QuickBookmarkChordWait
      write FBookmarks.QuickBookmarkChordWait;
    property QuickBookmarkSetKey: Integer read FNavigationKeys.QuickBookmarkSetKey
      write FNavigationKeys.QuickBookmarkSetKey;
    property QuickBookmarkSetKeyPriority: Boolean read FKeyPriorities.QuickBookmarkSetKeyPriority
      write FKeyPriorities.QuickBookmarkSetKeyPriority;
    property QuickBookmarkJumpKey: Integer read FNavigationKeys.QuickBookmarkJumpKey
      write FNavigationKeys.QuickBookmarkJumpKey;
    property QuickBookmarkJumpKeyPriority: Boolean read FKeyPriorities.QuickBookmarkJumpKeyPriority
      write FKeyPriorities.QuickBookmarkJumpKeyPriority;
    property QuickBookmarksScope: string read FBookmarks.QuickBookmarksScope write FBookmarks.QuickBookmarksScope;
    property QuickBookmarksImportIde: Boolean read FBookmarks.QuickBookmarksImportIde
      write FBookmarks.QuickBookmarksImportIde;
    property NextBookmarkKey: Integer read FNavigationKeys.NextBookmarkKey write FNavigationKeys.NextBookmarkKey;
    property PreviousBookmarkKey: Integer read FNavigationKeys.PreviousBookmarkKey
      write FNavigationKeys.PreviousBookmarkKey;
    property MinimapNoticeShown: Boolean read FEditorView.MinimapNoticeShown write FEditorView.MinimapNoticeShown;
    property ExitPoints: Boolean read FHighlighting.ExitPoints write FHighlighting.ExitPoints;
    property ExitPointsExceptions: Boolean read FHighlighting.ExitPointsExceptions
      write FHighlighting.ExitPointsExceptions;
    property ExitPointsLoops: Boolean read FHighlighting.ExitPointsLoops write FHighlighting.ExitPointsLoops;
    property ExitPointsBadge: Boolean read FHighlighting.ExitPointsBadge write FHighlighting.ExitPointsBadge;
    property Reassigned: Boolean read FHighlighting.Reassigned write FHighlighting.Reassigned;
    property ReassignedTargets: string read FHighlighting.ReassignedTargets write FHighlighting.ReassignedTargets;
    property ReassignedStyle: string read FHighlighting.ReassignedStyle write FHighlighting.ReassignedStyle;
    property ReassignedColor: string read FHighlighting.ReassignedColor write FHighlighting.ReassignedColor;
    property ToggleBlockComment: Boolean read FEditingKeys.ToggleBlockComment write FEditingKeys.ToggleBlockComment;
    property ToggleBlockCommentKey: Integer read FEditingKeys.ToggleBlockCommentKey
      write FEditingKeys.ToggleBlockCommentKey;
    property ToggleBlockCommentStyle: string read FEditingKeys.ToggleBlockCommentStyle
      write FEditingKeys.ToggleBlockCommentStyle;
    property ToggleBlockCommentFallback: string read FEditingKeys.ToggleBlockCommentFallback
      write FEditingKeys.ToggleBlockCommentFallback;
    property ToggleBlockCommentOwnLines: Boolean read FEditingKeys.ToggleBlockCommentOwnLines
      write FEditingKeys.ToggleBlockCommentOwnLines;
    property ToggleBlockCommentWithoutSelection: string read FEditingKeys.ToggleBlockCommentWithoutSelection
      write FEditingKeys.ToggleBlockCommentWithoutSelection;
    property NewLineAround: Boolean read FEditingKeys.NewLineAround write FEditingKeys.NewLineAround;
    property NewLineBelowKey: Integer read FEditingKeys.NewLineBelowKey write FEditingKeys.NewLineBelowKey;
    property NewLineAboveKey: Integer read FEditingKeys.NewLineAboveKey write FEditingKeys.NewLineAboveKey;
    property NewLineAroundStatementAware: Boolean read FEditingKeys.NewLineAroundStatementAware
      write FEditingKeys.NewLineAroundStatementAware;
    property Unwrap: Boolean read FEditingKeys.Unwrap write FEditingKeys.Unwrap;
    property UnwrapKey: Integer read FEditingKeys.UnwrapKey write FEditingKeys.UnwrapKey;
    property ExpressionTypeKey: Integer read FEditingKeys.ExpressionTypeKey write FEditingKeys.ExpressionTypeKey;
    property MethodPlacement: string read FEditorTyping.MethodPlacement write FEditorTyping.MethodPlacement;
    property RegionFolds: string read FEditorTyping.RegionFolds write FEditorTyping.RegionFolds;
    property SafeDelete: Boolean read FEditingKeys.SafeDelete write FEditingKeys.SafeDelete;
    property SafeDeleteKey: Integer read FEditingKeys.SafeDeleteKey write FEditingKeys.SafeDeleteKey;
    property OverviewRuler: Boolean read FEditorView.OverviewRuler write FEditorView.OverviewRuler;
    property OverviewRulerKinds: string read FEditorView.OverviewRulerKinds write FEditorView.OverviewRulerKinds;
    property JumpToMatch: Boolean read FNavigationKeys.JumpToMatch write FNavigationKeys.JumpToMatch;
    property JumpToMatchKey: Integer read FNavigationKeys.JumpToMatchKey write FNavigationKeys.JumpToMatchKey;
    property JumpToMatchSelectKey: Integer read FNavigationKeys.JumpToMatchSelectKey
      write FNavigationKeys.JumpToMatchSelectKey;
    property MoveLines: Boolean read FEditingKeys.MoveLines write FEditingKeys.MoveLines;
    property MoveLinesUpKey: Integer read FEditingKeys.MoveLinesUpKey write FEditingKeys.MoveLinesUpKey;
    property MoveLinesDownKey: Integer read FEditingKeys.MoveLinesDownKey write FEditingKeys.MoveLinesDownKey;
    property DuplicateLinesUpKey: Integer read FEditingKeys.DuplicateLinesUpKey write FEditingKeys.DuplicateLinesUpKey;
    property DuplicateLinesDownKey: Integer read FEditingKeys.DuplicateLinesDownKey
      write FEditingKeys.DuplicateLinesDownKey;
    property ContinueComments: Boolean read FEditorTyping.ContinueComments write FEditorTyping.ContinueComments;
    property ContinueCommentsLineComments: Boolean read FEditorTyping.ContinueCommentsLineComments
      write FEditorTyping.ContinueCommentsLineComments;
    property ContinueCommentsLists: Boolean read FEditorTyping.ContinueCommentsLists
      write FEditorTyping.ContinueCommentsLists;
    property ContinueCommentsBlockPrefix: string read FEditorTyping.ContinueCommentsBlockPrefix
      write FEditorTyping.ContinueCommentsBlockPrefix;
    property WrapSelection: Boolean read FEditorTyping.WrapSelection write FEditorTyping.WrapSelection;
    property WrapSelectionChars: string read FEditorTyping.WrapSelectionChars write FEditorTyping.WrapSelectionChars;
    property CompleteStatement: Boolean read FEditorTyping.CompleteStatement write FEditorTyping.CompleteStatement;
    property CompleteStatementKey: Integer read FEditingKeys.CompleteStatementKey
      write FEditingKeys.CompleteStatementKey;
    property CompleteStatementBeginEnd: string read FEditorTyping.CompleteStatementBeginEnd
      write FEditorTyping.CompleteStatementBeginEnd;
    property CompleteStatementTryKind: string read FEditorTyping.CompleteStatementTryKind
      write FEditorTyping.CompleteStatementTryKind;
    property CompleteStatementMethodBody: Boolean read FEditorTyping.CompleteStatementMethodBody
      write FEditorTyping.CompleteStatementMethodBody;
    property FormatCode: Boolean read FEditorTyping.FormatCode write FEditorTyping.FormatCode;
    property FormatCodeKey: Integer read FEditingKeys.FormatCodeKey write FEditingKeys.FormatCodeKey;
    property ContinuePattern: Boolean read FEditorTyping.ContinuePattern write FEditorTyping.ContinuePattern;
    property ContinuePatternMinLines: Integer read FEditorTyping.ContinuePatternMinLines
      write FEditorTyping.ContinuePatternMinLines;
    property MultiCursor: Boolean read FEditorTyping.MultiCursor write FEditorTyping.MultiCursor;
    property LinkedEditing: Boolean read FEditorTyping.LinkedEditing write FEditorTyping.LinkedEditing;
    property SmartPaste: string read FEditorTyping.SmartPaste write FEditorTyping.SmartPaste;
    property MultiCursorModifier: string read FEditorTyping.MultiCursorModifier write FEditorTyping.MultiCursorModifier;
    property MultiCursorNextKey: Integer read FEditingKeys.MultiCursorNextKey write FEditingKeys.MultiCursorNextKey;
    property MultiCursorSkipKey: Integer read FEditingKeys.MultiCursorSkipKey write FEditingKeys.MultiCursorSkipKey;
    property MultiCursorLineEndsKey: Integer read FEditingKeys.MultiCursorLineEndsKey
      write FEditingKeys.MultiCursorLineEndsKey;
    property MultiCursorAboveKey: Integer read FEditingKeys.MultiCursorAboveKey write FEditingKeys.MultiCursorAboveKey;
    property MultiCursorBelowKey: Integer read FEditingKeys.MultiCursorBelowKey write FEditingKeys.MultiCursorBelowKey;
    property DebugEnabled: Boolean read FDebug.DebugEnabled write FDebug.DebugEnabled;
    property IssuesEnabled: Boolean read FIssues.IssuesEnabled write FIssues.IssuesEnabled;
    property AnalysisEnabled: Boolean read FGeneralServer.AnalysisEnabled write FGeneralServer.AnalysisEnabled;
    property TestsEnabled: Boolean read FBuild.TestsEnabled write FBuild.TestsEnabled;
    property BuildToolsEnabled: Boolean read FBuild.BuildToolsEnabled write FBuild.BuildToolsEnabled;
    property BuildPipelineEnabled: Boolean read FBuild.BuildPipelineEnabled write FBuild.BuildPipelineEnabled;
    property BookmarksEnabled: Boolean read FBookmarks.BookmarksEnabled write FBookmarks.BookmarksEnabled;
    property DesignerEnabled: Boolean read FEditorInsight.DesignerEnabled write FEditorInsight.DesignerEnabled;
    property RuleChecksEnabled: Boolean read FRules.RuleChecksEnabled write FRules.RuleChecksEnabled;
    property SearchEnabled: Boolean read FEditorNavigation.SearchEnabled write FEditorNavigation.SearchEnabled;
    property WelcomePage: Boolean read FWelcome.WelcomePage write FWelcome.WelcomePage;
    property WelcomePageIdePage: Boolean read FWelcome.WelcomePageIdePage write FWelcome.WelcomePageIdePage;
    property WelcomePageLayout: string read FWelcome.WelcomePageLayout write FWelcome.WelcomePageLayout;
    property WelcomePageOpenOnStart: Boolean read FWelcome.WelcomePageOpenOnStart write FWelcome.WelcomePageOpenOnStart;
    property WelcomePageOpenWhenNoProject: Boolean read FWelcome.WelcomePageOpenWhenNoProject
      write FWelcome.WelcomePageOpenWhenNoProject;
    property WelcomePageHeader: Boolean read FWelcome.WelcomePageHeader write FWelcome.WelcomePageHeader;
    property WelcomePageGreeting: Boolean read FWelcome.WelcomePageGreeting write FWelcome.WelcomePageGreeting;
    property WelcomePageSearch: Boolean read FWelcomeTiles.WelcomePageSearch write FWelcomeTiles.WelcomePageSearch;
    property WelcomePageSearchSymbols: Boolean read FWelcomeTiles.WelcomePageSearchSymbols
      write FWelcomeTiles.WelcomePageSearchSymbols;
    property WelcomePageSearchKey: Integer read FNavigationKeys.WelcomePageSearchKey
      write FNavigationKeys.WelcomePageSearchKey;
    property WelcomePageWhatsNew: string read FWelcome.WelcomePageWhatsNew write FWelcome.WelcomePageWhatsNew;
    property WhatsNewSeen: string read FWelcome.WhatsNewSeen write FWelcome.WhatsNewSeen;
    property WelcomePageProjectStatus: Boolean read FWelcomeTiles.WelcomePageProjectStatus
      write FWelcomeTiles.WelcomePageProjectStatus;
    property WelcomePageMaxProjects: Integer read FWelcomeTiles.WelcomePageMaxProjects
      write FWelcomeTiles.WelcomePageMaxProjects;
    property WelcomePageRefreshVcs: Boolean read FWelcomeTiles.WelcomePageRefreshVcs
      write FWelcomeTiles.WelcomePageRefreshVcs;
    property WelcomePageUnsaved: Boolean read FWelcomeTiles.WelcomePageUnsaved write FWelcomeTiles.WelcomePageUnsaved;
    property WelcomePageUnsavedMinAgeHours: Integer read FWelcomeTiles.WelcomePageUnsavedMinAgeHours
      write FWelcomeTiles.WelcomePageUnsavedMinAgeHours;
    property WelcomePageUnsavedWarnHours: Integer read FWelcomeTiles.WelcomePageUnsavedWarnHours
      write FWelcomeTiles.WelcomePageUnsavedWarnHours;
    property WelcomePageUnsavedAlertHours: Integer read FWelcomeTiles.WelcomePageUnsavedAlertHours
      write FWelcomeTiles.WelcomePageUnsavedAlertHours;
    property WelcomePageUnsavedHideWhenClean: Boolean read FWelcomeTiles.WelcomePageUnsavedHideWhenClean
      write FWelcomeTiles.WelcomePageUnsavedHideWhenClean;
    property WelcomePageStatusTile: Boolean read FWelcomeTiles.WelcomePageStatusTile
      write FWelcomeTiles.WelcomePageStatusTile;
    property WelcomePageStatusTileOnlyProblems: Boolean read FWelcomeTiles.WelcomePageStatusTileOnlyProblems
      write FWelcomeTiles.WelcomePageStatusTileOnlyProblems;
    property WelcomePageDiscover: Boolean read FWelcomeTiles.WelcomePageDiscover
      write FWelcomeTiles.WelcomePageDiscover;
    property TipsUsageTracking: Boolean read FWelcome.TipsUsageTracking write FWelcome.TipsUsageTracking;
    property WelcomePageHelp: Boolean read FWelcomeTiles.WelcomePageHelp write FWelcomeTiles.WelcomePageHelp;
    property WelcomePageHelpReportUrl: string read FWelcomeTiles.WelcomePageHelpReportUrl
      write FWelcomeTiles.WelcomePageHelpReportUrl;
    property WelcomePageHelpReportFolder: string read FWelcomeTiles.WelcomePageHelpReportFolder
      write FWelcomeTiles.WelcomePageHelpReportFolder;
    property WelcomePageProjectSetup: Boolean read FWelcomeTiles.WelcomePageProjectSetup
      write FWelcomeTiles.WelcomePageProjectSetup;
    property WelcomePageNewFromTemplate: Boolean read FWelcomeTiles.WelcomePageNewFromTemplate
      write FWelcomeTiles.WelcomePageNewFromTemplate;
    property WelcomePageContinue: Boolean read FWelcomeTiles.WelcomePageContinue
      write FWelcomeTiles.WelcomePageContinue;
    property WelcomePageContinueCount: Integer read FWelcomeTiles.WelcomePageContinueCount
      write FWelcomeTiles.WelcomePageContinueCount;
    property WelcomePageContinueIncoming: Boolean read FWelcomeTiles.WelcomePageContinueIncoming
      write FWelcomeTiles.WelcomePageContinueIncoming;
    property WelcomePageContinueFetch: Boolean read FWelcomeTiles.WelcomePageContinueFetch
      write FWelcomeTiles.WelcomePageContinueFetch;
    property WelcomePageContinueIssues: Boolean read FWelcomeTiles.WelcomePageContinueIssues
      write FWelcomeTiles.WelcomePageContinueIssues;
    property WelcomePageContinueIssuesCount: Integer read FWelcomeTiles.WelcomePageContinueIssuesCount
      write FWelcomeTiles.WelcomePageContinueIssuesCount;
    property WelcomePageSaved: Boolean read FWelcomeTiles.WelcomePageSaved write FWelcomeTiles.WelcomePageSaved;
    property WelcomePageTrends: Boolean read FWelcomeTiles.WelcomePageTrends write FWelcomeTiles.WelcomePageTrends;
    property WelcomePageTrendsPoints: Integer read FWelcomeTiles.WelcomePageTrendsPoints
      write FWelcomeTiles.WelcomePageTrendsPoints;
    property WelcomePageTrendsSeries: string read FWelcomeTiles.WelcomePageTrendsSeries
      write FWelcomeTiles.WelcomePageTrendsSeries;
    property WelcomePageTests: Boolean read FWelcomeTiles.WelcomePageTests write FWelcomeTiles.WelcomePageTests;
    property WelcomePageTestsMaxFailures: Integer read FWelcomeTiles.WelcomePageTestsMaxFailures
      write FWelcomeTiles.WelcomePageTestsMaxFailures;
    property WelcomePageTestsCi: Boolean read FWelcomeTiles.WelcomePageTestsCi write FWelcomeTiles.WelcomePageTestsCi;
    property WelcomePageTestsCiProvider: string read FWelcomeTiles.WelcomePageTestsCiProvider
      write FWelcomeTiles.WelcomePageTestsCiProvider;
    property WelcomePageTestsCiIntervalMinutes: Integer read FWelcomeTiles.WelcomePageTestsCiIntervalMinutes
      write FWelcomeTiles.WelcomePageTestsCiIntervalMinutes;
    property WelcomePageTestsCiNotify: Boolean read FWelcomeTiles.WelcomePageTestsCiNotify
      write FWelcomeTiles.WelcomePageTestsCiNotify;
    property WelcomePageQuickActions: Boolean read FWelcomeTiles.WelcomePageQuickActions
      write FWelcomeTiles.WelcomePageQuickActions;
    property WelcomePageQuickActionsItems: string read FWelcomeTiles.WelcomePageQuickActionsItems
      write FWelcomeTiles.WelcomePageQuickActionsItems;
    property WelcomePageQuickActionsConsole: string read FWelcomeTiles.WelcomePageQuickActionsConsole
      write FWelcomeTiles.WelcomePageQuickActionsConsole;
    property WelcomePageQuickActionsBuildKey: Integer read FNavigationKeys.WelcomePageQuickActionsBuildKey
      write FNavigationKeys.WelcomePageQuickActionsBuildKey;
    property WelcomePageQuickActionsTestKey: Integer read FNavigationKeys.WelcomePageQuickActionsTestKey
      write FNavigationKeys.WelcomePageQuickActionsTestKey;
    property CiLogin: Boolean read FWelcomeTiles.CiLogin write FWelcomeTiles.CiLogin;
    property WelcomePageIssues: Boolean read FWelcomeTiles.WelcomePageIssues write FWelcomeTiles.WelcomePageIssues;
    property WelcomePageSprint: Boolean read FWelcomeTiles.WelcomePageSprint write FWelcomeTiles.WelcomePageSprint;
    property IssuesTracker: string read FIssues.IssuesTracker write FIssues.IssuesTracker;
    property IssuesStart: string read FIssues.IssuesStart write FIssues.IssuesStart;
    property IssuesBranchPattern: string read FIssues.IssuesBranchPattern write FIssues.IssuesBranchPattern;
    property IssuesBranchBase: string read FIssues.IssuesBranchBase write FIssues.IssuesBranchBase;
    property IssuesCommitPattern: string read FIssues.IssuesCommitPattern write FIssues.IssuesCommitPattern;
    property TrackerLogin: Boolean read FIssues.TrackerLogin write FIssues.TrackerLogin;
    property IssuesConnections: string read FIssues.IssuesConnections write FIssues.IssuesConnections;
    property IssuesPreview: Boolean read FIssueWork.IssuesPreview write FIssueWork.IssuesPreview;
    property IssuesPreviewComments: Boolean read FIssueWork.IssuesPreviewComments
      write FIssueWork.IssuesPreviewComments;
    property IssuesCodeLinks: Boolean read FIssueWork.IssuesCodeLinks write FIssueWork.IssuesCodeLinks;
    property IssuesBlameLinks: Boolean read FIssueWork.IssuesBlameLinks write FIssueWork.IssuesBlameLinks;
    property IssuesBlameMaxRevisions: Integer read FIssueWork.IssuesBlameMaxRevisions
      write FIssueWork.IssuesBlameMaxRevisions;
    property IssuesProjects: string read FIssues.IssuesProjects write FIssues.IssuesProjects;
    property IssuesQueries: string read FIssues.IssuesQueries write FIssues.IssuesQueries;
    property IssuesQueryPicker: Boolean read FIssues.IssuesQueryPicker write FIssues.IssuesQueryPicker;
    property IssuesProjectPicker: Boolean read FIssues.IssuesProjectPicker write FIssues.IssuesProjectPicker;
    property IssuesWelcomeProject: string read FIssues.IssuesWelcomeProject write FIssues.IssuesWelcomeProject;
    property IssuesAllProjects: Boolean read FIssues.IssuesAllProjects write FIssues.IssuesAllProjects;
    property IssuesAllProjectsPerGroup: Integer read FIssues.IssuesAllProjectsPerGroup
      write FIssues.IssuesAllProjectsPerGroup;
    property IssuesSuggestPaths: Boolean read FIssues.IssuesSuggestPaths write FIssues.IssuesSuggestPaths;
    property IssuesCreate: Boolean read FIssueWork.IssuesCreate write FIssueWork.IssuesCreate;
    property IssuesCreateIncludeCode: Boolean read FIssueWork.IssuesCreateIncludeCode
      write FIssueWork.IssuesCreateIncludeCode;
    property VcsProvider: string read FVcs.VcsProvider write FVcs.VcsProvider;
    property VcsGitPath: string read FVcs.VcsGitPath write FVcs.VcsGitPath;
    property VcsSvnPath: string read FVcs.VcsSvnPath write FVcs.VcsSvnPath;
    property VcsTimeoutSeconds: Integer read FVcs.VcsTimeoutSeconds write FVcs.VcsTimeoutSeconds;
    property VcsProjects: string read FVcs.VcsProjects write FVcs.VcsProjects;
    property VcsBranchSvnLocation: string read FVcs.VcsBranchSvnLocation write FVcs.VcsBranchSvnLocation;
    property VcsBranchSvnSource: string read FVcs.VcsBranchSvnSource write FVcs.VcsBranchSvnSource;
    property VcsBranchSvnAfter: string read FVcs.VcsBranchSvnAfter write FVcs.VcsBranchSvnAfter;
    property VcsBranchSvnCheckoutFolder: string read FVcs.VcsBranchSvnCheckoutFolder
      write FVcs.VcsBranchSvnCheckoutFolder;
    property VcsBranchSvnMessage: string read FVcs.VcsBranchSvnMessage write FVcs.VcsBranchSvnMessage;
    property VcsExternalsOnBranch: string read FVcs.VcsExternalsOnBranch write FVcs.VcsExternalsOnBranch;
    property VcsExternalsSuggestBranch: string read FVcs.VcsExternalsSuggestBranch write FVcs.VcsExternalsSuggestBranch;
    property VcsExternalsRules: string read FVcs.VcsExternalsRules write FVcs.VcsExternalsRules;
    property VcsExternalsShow: Boolean read FVcs.VcsExternalsShow write FVcs.VcsExternalsShow;
    property VcsExternalsUpdate: string read FVcs.VcsExternalsUpdate write FVcs.VcsExternalsUpdate;
    property VcsEnabled: Boolean read FVcs.VcsEnabled write FVcs.VcsEnabled;
    property VcsBranchConfirm: Boolean read FVcs.VcsBranchConfirm write FVcs.VcsBranchConfirm;
    property VcsBranchGitBase: string read FVcs.VcsBranchGitBase write FVcs.VcsBranchGitBase;
    property VcsBranchGitPush: string read FVcs.VcsBranchGitPush write FVcs.VcsBranchGitPush;
    property VcsBranchGitUncommitted: string read FVcs.VcsBranchGitUncommitted write FVcs.VcsBranchGitUncommitted;
    property VcsBranchGitWorktree: Boolean read FVcs.VcsBranchGitWorktree write FVcs.VcsBranchGitWorktree;
    property VcsBranchGitWorktreeFolder: string read FVcs.VcsBranchGitWorktreeFolder
      write FVcs.VcsBranchGitWorktreeFolder;
    property IssuesSyncState: Boolean read FIssues.IssuesSyncState write FIssues.IssuesSyncState;
    property IssuesStateField: string read FIssues.IssuesStateField write FIssues.IssuesStateField;
    property IssuesAssigneeField: string read FIssues.IssuesAssigneeField write FIssues.IssuesAssigneeField;
    property IssuesStartState: string read FIssues.IssuesStartState write FIssues.IssuesStartState;
    property IssuesAssignOnStart: Boolean read FIssues.IssuesAssignOnStart write FIssues.IssuesAssignOnStart;
    property IssuesStartComment: string read FIssues.IssuesStartComment write FIssues.IssuesStartComment;
    property IssuesEndStates: string read FIssues.IssuesEndStates write FIssues.IssuesEndStates;
    property IssuesReviewStates: string read FIssues.IssuesReviewStates write FIssues.IssuesReviewStates;
    property IssuesEndComment: string read FIssues.IssuesEndComment write FIssues.IssuesEndComment;
    property IssuesReviewComment: string read FIssues.IssuesReviewComment write FIssues.IssuesReviewComment;
    property IssuesEndFields: string read FIssues.IssuesEndFields write FIssues.IssuesEndFields;
    property IssuesEndTime: Boolean read FIssues.IssuesEndTime write FIssues.IssuesEndTime;
    property IssuesTimeTracking: Boolean read FIssueWork.IssuesTimeTracking write FIssueWork.IssuesTimeTracking;
    property IssuesIdleMinutes: Integer read FIssueWork.IssuesIdleMinutes write FIssueWork.IssuesIdleMinutes;
    property IssuesTimeRounding: Integer read FIssueWork.IssuesTimeRounding write FIssueWork.IssuesTimeRounding;
    property IssuesPreviewChecklists: Boolean read FIssueWork.IssuesPreviewChecklists
      write FIssueWork.IssuesPreviewChecklists;
    property IssuesChecklistStatus: Boolean read FIssueWork.IssuesChecklistStatus
      write FIssueWork.IssuesChecklistStatus;
    property IssuesStatusState: Boolean read FIssueWork.IssuesStatusState write FIssueWork.IssuesStatusState;
    property IssuesSprintOnStart: string read FIssueWork.IssuesSprintOnStart write FIssueWork.IssuesSprintOnStart;
    property IssuesPreviewLinks: Boolean read FIssueWork.IssuesPreviewLinks write FIssueWork.IssuesPreviewLinks;
    property IssuesWarnBlocked: Boolean read FIssueWork.IssuesWarnBlocked write FIssueWork.IssuesWarnBlocked;
    property IssuesBoard: Boolean read FIssueWork.IssuesBoard write FIssueWork.IssuesBoard;
    property IssuesBoardConfirmMove: Boolean read FIssueWork.IssuesBoardConfirmMove
      write FIssueWork.IssuesBoardConfirmMove;
    property IssuesBoardOnlyMine: Boolean read FIssueWork.IssuesBoardOnlyMine write FIssueWork.IssuesBoardOnlyMine;
    property IssuesIdeColors: Boolean read FIssueWork.IssuesIdeColors write FIssueWork.IssuesIdeColors;
    property IssuesFlowMap: Boolean read FIssueWork.IssuesFlowMap write FIssueWork.IssuesFlowMap;
    property IssuesFlowMapDays: Integer read FIssueWork.IssuesFlowMapDays write FIssueWork.IssuesFlowMapDays;
    property IssuesFlowMapStuckDays: Integer read FIssueWork.IssuesFlowMapStuckDays
      write FIssueWork.IssuesFlowMapStuckDays;
    property IssuesSprintBurndown: Boolean read FIssueWork.IssuesSprintBurndown write FIssueWork.IssuesSprintBurndown;
    property IssuesSprintCompare: Boolean read FIssueWork.IssuesSprintCompare write FIssueWork.IssuesSprintCompare;
    property IssuesPaletteSearch: Boolean read FIssueWork.IssuesPaletteSearch write FIssueWork.IssuesPaletteSearch;
    property IssuesCommentEditor: Boolean read FIssueWork.IssuesCommentEditor write FIssueWork.IssuesCommentEditor;
    property IssuesCommentSnippets: string read FIssueWork.IssuesCommentSnippets write FIssueWork.IssuesCommentSnippets;
    property IssuesPreviewDevelopment: Boolean read FIssueWork.IssuesPreviewDevelopment
      write FIssueWork.IssuesPreviewDevelopment;
    property IssuesNotify: Boolean read FIssueWork.IssuesNotify write FIssueWork.IssuesNotify;
    property IssuesNotifyIntervalMinutes: Integer read FIssueWork.IssuesNotifyIntervalMinutes
      write FIssueWork.IssuesNotifyIntervalMinutes;
    property IssuesNotifyScope: string read FIssueWork.IssuesNotifyScope write FIssueWork.IssuesNotifyScope;
    property IssuesReopened: Boolean read FIssueWork.IssuesReopened write FIssueWork.IssuesReopened;
    property IssuesReviewBuild: Boolean read FIssueWork.IssuesReviewBuild write FIssueWork.IssuesReviewBuild;
    property IssuesAttach: Boolean read FIssueWork.IssuesAttach write FIssueWork.IssuesAttach;
    property IssuesAttachLogFiles: string read FIssueWork.IssuesAttachLogFiles write FIssueWork.IssuesAttachLogFiles;
    property IssuesAttachMaxImageWidth: Integer read FIssueWork.IssuesAttachMaxImageWidth
      write FIssueWork.IssuesAttachMaxImageWidth;
    property IssuesAttachRaiseProgram: Boolean read FIssueWork.IssuesAttachRaiseProgram
      write FIssueWork.IssuesAttachRaiseProgram;
    property WelcomePageCustomLayout: Boolean read FWelcome.WelcomePageCustomLayout
      write FWelcome.WelcomePageCustomLayout;
    property WelcomePageColumns: Integer read FWelcome.WelcomePageColumns write FWelcome.WelcomePageColumns;
    property WelcomePageLayouts: string read FWelcome.WelcomePageLayouts write FWelcome.WelcomePageLayouts;
    property WelcomePageActiveLayout: string read FWelcome.WelcomePageActiveLayout
      write FWelcome.WelcomePageActiveLayout;
    property Notifications: Boolean read FGeneral.Notifications write FGeneral.Notifications;
    property NotificationsSources: string read FGeneral.NotificationsSources write FGeneral.NotificationsSources;
    property NotificationsMaxEntries: Integer read FGeneral.NotificationsMaxEntries
      write FGeneral.NotificationsMaxEntries;
    property NotificationsKey: Integer read FNavigationKeys.NotificationsKey write FNavigationKeys.NotificationsKey;
    property SettingsExportImport: Boolean read FGeneral.SettingsExportImport write FGeneral.SettingsExportImport;
    property SettingsMarkModified: Boolean read FGeneral.SettingsMarkModified write FGeneral.SettingsMarkModified;
    property SettingsSearch: Boolean read FGeneral.SettingsSearch write FGeneral.SettingsSearch;
    property PaletteSettingsPrefix: Boolean read FGeneral.PaletteSettingsPrefix write FGeneral.PaletteSettingsPrefix;
    property HelpEnabled: Boolean read FGeneral.HelpEnabled write FGeneral.HelpEnabled;
    property HelpSource: string read FGeneral.HelpSource write FGeneral.HelpSource;
    property DiagnosticsEditionCheck: Boolean read FGeneral.DiagnosticsEditionCheck
      write FGeneral.DiagnosticsEditionCheck;
    property EditionNoticeShown: Boolean read FGeneral.EditionNoticeShown write FGeneral.EditionNoticeShown;
    property SettingsBackupBeforeImport: Boolean read FGeneral.SettingsBackupBeforeImport
      write FGeneral.SettingsBackupBeforeImport;
    property SettingsExportSecrets: string read FGeneral.SettingsExportSecrets write FGeneral.SettingsExportSecrets;
  end;

implementation

uses
  System.SysUtils;

{ TDpccPluginSettings }

class function TDpccPluginSettings.Defaults: TDpccPluginSettings;
begin
  Result.FCompletion := TDpccPluginCompletionSettings.Defaults;
  Result.FEditingKeys := TDpccPluginEditingKeysSettings.Defaults;
  Result.FKeyPriorities := TDpccPluginKeyPrioritiesSettings.Defaults;
  Result.FEditorTyping := TDpccPluginEditorTypingSettings.Defaults;
  Result.FGeneralServer := TDpccPluginGeneralServerSettings.Defaults;
  Result.FHighlighting := TDpccPluginHighlightingSettings.Defaults;
  Result.FEditorInsight := TDpccPluginEditorInsightSettings.Defaults;
  Result.FBookmarks := TDpccPluginBookmarksSettings.Defaults;
  Result.FNavigationKeys := TDpccPluginNavigationKeysSettings.Defaults;
  Result.FEditorNavigation := TDpccPluginEditorNavigationSettings.Defaults;
  Result.FRules := TDpccPluginRulesSettings.Defaults;
  Result.FBuild := TDpccPluginBuildSettings.Defaults;
  Result.FCodeActions := TDpccPluginCodeActionsSettings.Defaults;
  Result.FDebug := TDpccPluginDebugSettings.Defaults;
  Result.FGeneral := TDpccPluginGeneralSettings.Defaults;
  Result.FUnitSearch := TDpccPluginUnitSearchSettings.Defaults;
  Result.FEditorView := TDpccPluginEditorViewSettings.Defaults;
  Result.FIssues := TDpccPluginIssuesSettings.Defaults;
  Result.FWelcome := TDpccPluginWelcomeSettings.Defaults;
  Result.FWelcomeTiles := TDpccPluginWelcomeTilesSettings.Defaults;
  Result.FIssueWork := TDpccPluginIssueWorkSettings.Defaults;
  Result.FVcs := TDpccPluginVcsSettings.Defaults;
end;

procedure TDpccPluginSettings.Normalize;
begin
  FCompletion.Normalize;
  FEditingKeys.Normalize;
  FEditorTyping.Normalize;
  FGeneralServer.Normalize;
  FHighlighting.Normalize;
  FEditorInsight.Normalize;
  FBookmarks.Normalize;
  FNavigationKeys.Normalize;
  FEditorNavigation.Normalize;
  FRules.Normalize;
  FBuild.Normalize;
  FCodeActions.Normalize;
  FDebug.Normalize;
  FGeneral.Normalize;
  FUnitSearch.Normalize;
  FEditorView.Normalize;
  FIssues.Normalize;
  FWelcome.Normalize;
  FWelcomeTiles.Normalize;
  FIssueWork.Normalize;
  FVcs.Normalize;
end;

procedure TDpccPluginSettings.Exchange(const AIo: TDpccSettingsExchange);
begin
  FCompletion.Exchange(AIo);
  FEditingKeys.Exchange(AIo);
  FKeyPriorities.Exchange(AIo);
  FEditorTyping.Exchange(AIo);
  FGeneralServer.Exchange(AIo);
  FHighlighting.Exchange(AIo);
  FEditorInsight.Exchange(AIo);
  FBookmarks.Exchange(AIo);
  FNavigationKeys.Exchange(AIo);
  FEditorNavigation.Exchange(AIo);
  FRules.Exchange(AIo);
  FBuild.Exchange(AIo);
  FCodeActions.Exchange(AIo);
  FDebug.Exchange(AIo);
  FGeneral.Exchange(AIo);
  FUnitSearch.Exchange(AIo);
  FEditorView.Exchange(AIo);
  FIssues.Exchange(AIo);
  FWelcome.Exchange(AIo);
  FWelcomeTiles.Exchange(AIo);
  FIssueWork.Exchange(AIo);
  FVcs.Exchange(AIo);
end;

procedure TDpccPluginSettings.Load(const AStore: IDpccSettingsStore);
begin
  Self := Defaults;
  Exchange(TDpccSettingsExchange.Reader(AStore));
  Normalize;
end;

procedure TDpccPluginSettings.Save(const AStore: IDpccSettingsStore);
begin
  Normalize;
  Exchange(TDpccSettingsExchange.Writer(AStore));
end;

end.
