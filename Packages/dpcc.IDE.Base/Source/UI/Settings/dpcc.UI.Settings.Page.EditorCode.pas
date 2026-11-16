unit dpcc.UI.Settings.Page.EditorCode;

// Reiter „Editor“, zweiter Teil: Bearbeiten (neu zugewiesene Variablen, Methodenreihenfolge, Übersichtsleiste,
// Kommentare, Anweisungen, Einfügemarken, Fehlertext, Code Lens).

interface

uses
  Vcl.StdCtrls,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Editor.Overview,
  dpcc.Core.Settings.Reassigned,
  dpcc.UI.Settings.ChoiceBox,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Editor“, zweiter Teil: Bearbeiten (neu zugewiesene Variablen, Methodenreihenfolge,
  /// Übersichtsleiste, Kommentare, Anweisungen, Einfügemarken, Fehlertext, Code Lens).</summary>
  TDpccSettingsEditorCodePart = class(TDpccSettingsPagePart)
  private
    /// <summary>Fehlertext am Zeilenende (#509): aus, nur Fehler, Fehler und Warnungen, alle.</summary>
    FInlineDiagnostics: TDpccChoiceBox;
    FReassignedTargets: array[TDpccReassignedTarget] of TCheckBox;
    FReassignedStyle: TDpccChoiceBox;
    FReassignedColor: TEdit;
    FMethodPlacement: TDpccChoiceBox;
    /// <summary>Regionen beim Öffnen (#1814): unverändert, zu, auf oder aus.</summary>
    FRegionFolds: TDpccChoiceBox;
    FOverviewKinds: array[TDpccOverviewKind] of TCheckBox;
    FContinueCommentsBlockPrefix: TEdit;
    FCompleteStatementBeginEnd: TDpccChoiceBox;
    FCompleteStatementTryKind: TDpccChoiceBox;
    FSmartPaste: TDpccChoiceBox;
    FMultiCursorModifier: TDpccChoiceBox;
    procedure Save2(var ASettings: TDpccPluginSettings);
  public
    procedure Build;
    procedure Build2;
    procedure Build3;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    procedure BindMarks; override;
    /// <summary>Zum Testen: Häkchen je Art, Linie und Farbe (#712).</summary>
    function ReassignedTargetCheck(ATarget: TDpccReassignedTarget): TCheckBox;
    property ContinueCommentsBlockPrefix: TEdit read FContinueCommentsBlockPrefix;
    property CompleteStatementBeginEnd: TDpccChoiceBox read FCompleteStatementBeginEnd;
    property CompleteStatementTryKind: TDpccChoiceBox read FCompleteStatementTryKind;
    property SmartPaste: TDpccChoiceBox read FSmartPaste;
    property MultiCursorModifier: TDpccChoiceBox read FMultiCursorModifier;
    property ReassignedStyleBox: TDpccChoiceBox read FReassignedStyle;
    property ReassignedColorEdit: TEdit read FReassignedColor;
    /// <summary>Zum Testen: Methodenrümpfe in Deklarationsreihenfolge (#660).</summary>
    property MethodPlacementBox: TDpccChoiceBox read FMethodPlacement;
    /// <summary>Zum Testen: Regionen beim Öffnen (#1814).</summary>
    property RegionFoldsBox: TDpccChoiceBox read FRegionFolds;
    /// <summary>Zum Testen: Fehlertext am Zeilenende, Zähler und Sprungtasten (#509).</summary>
    property InlineDiagnostics: TDpccChoiceBox read FInlineDiagnostics;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.StrUtils,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.UI.Editor.RegionFolds,
  dpcc.Core.Settings.Plugin.Store,
  dpcc.Core.Problems.InlineHints;

{ TDpccSettingsEditorCodePart }

procedure TDpccSettingsEditorCodePart.Build;
begin
  // Austrittspunkte hervorheben (#698).
  BindCheck('ExitPoints', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExitPoints)));
  BindCheck('ExitPointsExceptions',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExitPointsExceptions)));
  BindCheck('ExitPointsLoops', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExitPointsLoops)));
  BindCheck('ExitPointsBadge', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExitPointsBadge)));
  // Neu zugewiesene Variablen (#712): an/aus, je Art ein Häkchen, Linie und Farbe.
  BindCheck('Reassigned', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReassigned)));
  FReassignedTargets[TDpccReassignedTarget.Locals] :=
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReassignedLocals));
  FReassignedTargets[TDpccReassignedTarget.LoopVars] :=
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReassignedLoopVars));
  FReassignedTargets[TDpccReassignedTarget.ValueParams] :=
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReassignedValueParams));
  FReassignedTargets[TDpccReassignedTarget.VarParams] :=
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReassignedVarParams));
  FReassignedTargets[TDpccReassignedTarget.Fields] :=
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReassignedFields));
  FReassignedStyle := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReassignedStyle),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReassignedStyleDotted),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReassignedStyleSolid),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReassignedStyleWavy)]);
  FReassignedColor := AddTextLine(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsReassignedColor));
  // Typ des markierten Ausdrucks (#689): seit S3 nur noch das (ausgeblendete) Kürzel.
  BindKey('ExpressionTypeKey', AddKey(TDpccStrings.Text(TDpccTextId.ExpressionTypeCommand)));
  // Methodenrümpfe in Deklarationsreihenfolge (#660): wie die Deklaration, alphabetisch oder aus.
  FMethodPlacement := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMethodPlacement),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMethodPlacementGrouped),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMethodPlacementDeclaration),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMethodPlacementAlphabetical),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMethodPlacementOff)]);
  // Regionen beim Öffnen (#1814).
  FRegionFolds := AddChoice(TDpccRegionFoldsTexts.Text(TDpccRegionFoldsText.Setting), TDpccRegionFoldsTexts.Choices);
  // Übersichtsleiste (#519): an/aus und je Art ein Häkchen.
  BindCheck('OverviewRuler', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsOverviewRuler)));
  FOverviewKinds[TDpccOverviewKind.Diagnostics] :=
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsOverviewDiagnostics));
  FOverviewKinds[TDpccOverviewKind.Search] := AddCheck(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsOverviewSearch));
  FOverviewKinds[TDpccOverviewKind.Changes] := AddCheck(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsOverviewChanges));
  FOverviewKinds[TDpccOverviewKind.Breakpoints] :=
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsOverviewBreakpoints));
  // Kommentar beim Enter fortsetzen (#696).
  BindCheck('ContinueComments', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsContinueComments)));
  BindCheck('ContinueCommentsLineComments',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsContinueCommentsLineComments)));
  BindCheck('ContinueCommentsLists',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsContinueCommentsLists)));
  FContinueCommentsBlockPrefix := AddTextLine(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsContinueCommentsBlockPrefix));
  // Markierung beim Tippen umschließen (#672).
  BindCheck('WrapSelection', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsWrapSelection)));
  BindText('WrapSelectionChars',
    AddTextLine(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsWrapSelectionChars)));
end;

procedure TDpccSettingsEditorCodePart.Build2;
begin
  // Anweisung vervollständigen (#697).
  BindCheck('CompleteStatement', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsCompleteStatement)));
  BindKey('CompleteStatementKey', AddKey(TDpccStrings.Text(TDpccTextId.CompleteStatementCommand)));
  FCompleteStatementBeginEnd := AddChoice(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsCompleteStatementBeginEnd),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBeginEndAlways),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBeginEndMultiLine),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsBeginEndNever)]);
  FCompleteStatementTryKind := AddChoice(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsCompleteStatementTryKind),
    [TDpccStrings.Text(TDpccTextId.CompleteStatementTryFinally),
    TDpccStrings.Text(TDpccTextId.CompleteStatementTryExcept),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTryKindAsk)]);
  BindCheck('CompleteStatementMethodBody',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsCompleteStatementMethodBody)));
  // Formatieren (#43).
  BindCheck('FormatCode', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFormatCode)));
  BindKey('FormatCodeKey', AddKey(TDpccStrings.Text(TDpccTextId.FormatCodeCommand)));
  // Muster fortsetzen (#671).
  BindCheck('ContinuePattern', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsContinuePattern)));
  BindText('ContinuePatternMinLines',
    AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsContinuePatternMinLines)));
  // Mehrere Einfügemarken (#589, experimentell).
  BindCheck('MultiCursor', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMultiCursor)));
  FMultiCursorModifier := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMultiCursorModifier),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMultiCursorAlt),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMultiCursorCtrl)]);
  BindKey('MultiCursorNextKey', AddKey(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMultiCursorNext)));
  BindKey('MultiCursorSkipKey', AddKey(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMultiCursorSkip)));
  BindKey('MultiCursorLineEndsKey',
    AddKey(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMultiCursorLineEnds)));
  BindKey('MultiCursorAboveKey', AddKey(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMultiCursorAbove)));
  BindKey('MultiCursorBelowKey', AddKey(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMultiCursorBelow)));
  // Bezeichner live mitziehen (#658, experimentell).
  BindCheck('LinkedEditing', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsLinkedEditing)));
  // Einfügen mit uses-Ergänzung (#515, experimentell).
  FSmartPaste := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSmartPaste),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSmartPasteOff),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSmartPasteUses),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSmartPasteIndent),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSmartPasteBoth)]);
  FOverviewKinds[TDpccOverviewKind.Bookmarks] := AddCheck(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsOverviewBookmarks));
  FOverviewKinds[TDpccOverviewKind.Cursor] := AddCheck(TDpccSettingsStrings.Text(
    TDpccSettingsTextId.SettingsOverviewCursor));
  // Rekursionssymbole im Rand (#623).
  BindCheck('RecursionMarkers', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsRecursionMarkers)));
  BindText('RecursionMarkersDepth',
    AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsRecursionMarkersDepth)));
  // Fehlertext am Zeilenende (#509); die Reihenfolge folgt TDpccInlineDiagnosticsMode.
  FInlineDiagnostics := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsInlineDiagnostics),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsInlineDiagnosticsOff),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsInlineDiagnosticsErrors),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsInlineDiagnosticsWarnings),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsInlineDiagnosticsAll)]);
  // Marken folgen ihrer Zeile sofort (#1818).
  BindCheck('TrackLines', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTrackLines)));
end;

procedure TDpccSettingsEditorCodePart.Build3;
begin
  BindCheck('CodeLensTestUnit', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsCodeLensTestUnit)));
  BindCheck('Metrics', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMetricsAll)));
  BindCheck('TodoList', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTodoList)));
  BindCheck('MetricsReport', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsMetricsReport)));
end;

function TDpccSettingsEditorCodePart.ReassignedTargetCheck(ATarget: TDpccReassignedTarget): TCheckBox;
begin
  Result := FReassignedTargets[ATarget];
end;

procedure TDpccSettingsEditorCodePart.BindMarks;
var
  mKind: TDpccOverviewKind;
  mTarget: TDpccReassignedTarget;
begin
  FPage.Bind('InlineDiagnostics', FInlineDiagnostics);
  for mTarget := Low(TDpccReassignedTarget) to High(TDpccReassignedTarget) do
  begin
    FPage.Marks.Bind(FReassignedTargets[mTarget], ['ReassignedTargets']);
  end;
  FPage.Marks.Bind(FReassignedStyle, ['ReassignedStyle']);
  FPage.Marks.Bind(FReassignedColor, ['ReassignedColor']);
  FPage.Marks.Bind(FMethodPlacement, ['MethodPlacement']);
  FPage.Marks.Bind(FRegionFolds, ['RegionFolds']);
  for mKind := Low(TDpccOverviewKind) to High(TDpccOverviewKind) do
  begin
    FPage.Marks.Bind(FOverviewKinds[mKind], ['OverviewRulerKinds']);
  end;
  FPage.Marks.Bind(FContinueCommentsBlockPrefix, ['ContinueCommentsBlockPrefix']);
  FPage.Marks.Bind(FCompleteStatementBeginEnd, ['CompleteStatementBeginEnd']);
  FPage.Marks.Bind(FCompleteStatementTryKind, ['CompleteStatementTryKind']);
  FPage.Marks.Bind(FMultiCursorModifier, ['MultiCursorModifier']);
  FPage.Marks.Bind(FSmartPaste, ['SmartPaste']);
  FPage.Marks.Bind(FInlineDiagnostics, ['InlineDiagnostics']);
end;

procedure TDpccSettingsEditorCodePart.Load(const ASettings: TDpccPluginSettings);
var
  mKind: TDpccOverviewKind;
  mKinds: TDpccOverviewKinds;
  mTarget: TDpccReassignedTarget;
  mTargets: TDpccReassignedTargets;
begin
  mTargets := TDpccReassignedNames.ParseTargets(ASettings.ReassignedTargets);
  for mTarget := Low(TDpccReassignedTarget) to High(TDpccReassignedTarget) do
  begin
    FReassignedTargets[mTarget].Checked := mTarget in mTargets;
  end;
  FReassignedStyle.Choice := Ord(TDpccReassignedNames.StyleOf(ASettings.ReassignedStyle));
  FReassignedColor.Text := ASettings.ReassignedColor;
  FMethodPlacement.Choice := Max(0, IndexText(ASettings.MethodPlacement, cDpccMethodPlacements));
  FRegionFolds.Choice := Max(0, IndexText(ASettings.RegionFolds, cDpccRegionFoldModes));
  mKinds := TDpccOverview.Kinds(ASettings.OverviewRulerKinds);
  for mKind := Low(TDpccOverviewKind) to High(TDpccOverviewKind) do
  begin
    FOverviewKinds[mKind].Checked := mKind in mKinds;
  end;
  FContinueCommentsBlockPrefix.Text := ASettings.ContinueCommentsBlockPrefix;
  // Reihenfolge der Auswahl: always, multiLine, never bzw. finally, except, ask.
  FCompleteStatementBeginEnd.Choice := 1;
  if ASettings.CompleteStatementBeginEnd = TDpccPluginSettings.cBeginEndAlways then
  begin
    FCompleteStatementBeginEnd.Choice := 0;
  end
  else if ASettings.CompleteStatementBeginEnd = TDpccPluginSettings.cBeginEndNever then
  begin
    FCompleteStatementBeginEnd.Choice := 2;
  end;
  FCompleteStatementTryKind.Choice := 0;
  if ASettings.CompleteStatementTryKind = TDpccPluginSettings.cTryKindExcept then
  begin
    FCompleteStatementTryKind.Choice := 1;
  end
  else if ASettings.CompleteStatementTryKind = TDpccPluginSettings.cTryKindAsk then
  begin
    FCompleteStatementTryKind.Choice := 2;
  end;
  FSmartPaste.Choice := Max(0, IndexText(ASettings.SmartPaste, ['off', 'uses', 'indent', 'both']));
  FMultiCursorModifier.Choice := 0;
  if ASettings.MultiCursorModifier = TDpccPluginSettings.cMultiCursorModifierCtrl then
  begin
    FMultiCursorModifier.Choice := 1;
  end;
  FInlineDiagnostics.Choice := Ord(TDpccInlineDiagnostics.ModeOf(ASettings.InlineDiagnostics));
end;

procedure TDpccSettingsEditorCodePart.Save(var ASettings: TDpccPluginSettings);
var
  mKind: TDpccOverviewKind;
  mKinds: TDpccOverviewKinds;
  mTarget: TDpccReassignedTarget;
  mTargets: TDpccReassignedTargets;
begin
  mTargets := [];
  for mTarget := Low(TDpccReassignedTarget) to High(TDpccReassignedTarget) do
  begin
    if FReassignedTargets[mTarget].Checked then
    begin
      Include(mTargets, mTarget);
    end;
  end;
  ASettings.ReassignedTargets := TDpccReassignedNames.TargetsText(mTargets);
  ASettings.ReassignedStyle := TDpccReassignedNames.cStyles[TDpccReassignedStyle(EnsureRange(
    FReassignedStyle.Choice, 0, Ord(High(TDpccReassignedStyle))))];
  ASettings.ReassignedColor := TDpccReassignedNames.NormalizeColor(FReassignedColor.Text);
  ASettings.MethodPlacement := cDpccMethodPlacements[EnsureRange(FMethodPlacement.Choice, 0,
    High(cDpccMethodPlacements))];
  mKinds := [];
  for mKind := Low(TDpccOverviewKind) to High(TDpccOverviewKind) do
  begin
    if FOverviewKinds[mKind].Checked then
    begin
      Include(mKinds, mKind);
    end;
  end;
  ASettings.OverviewRulerKinds := TDpccOverview.KindsText(mKinds);
  // Leerraum am Rand gehört zum Präfix (' * ').
  ASettings.ContinueCommentsBlockPrefix := FContinueCommentsBlockPrefix.Text;
  case FCompleteStatementBeginEnd.Choice of
    0:
      ASettings.CompleteStatementBeginEnd := TDpccPluginSettings.cBeginEndAlways;
    2:
      ASettings.CompleteStatementBeginEnd := TDpccPluginSettings.cBeginEndNever;
  else
    ASettings.CompleteStatementBeginEnd := TDpccPluginSettings.cBeginEndMultiLine;
  end;
  case FCompleteStatementTryKind.Choice of
    1:
      ASettings.CompleteStatementTryKind := TDpccPluginSettings.cTryKindExcept;
    2:
      ASettings.CompleteStatementTryKind := TDpccPluginSettings.cTryKindAsk;
  else
    ASettings.CompleteStatementTryKind := TDpccPluginSettings.cTryKindFinally;
  end;
  ASettings.SmartPaste := 'off';
  case FSmartPaste.Choice of
    1:
      ASettings.SmartPaste := 'uses';
    2:
      ASettings.SmartPaste := 'indent';
    3:
      ASettings.SmartPaste := 'both';
  end;
  Save2(ASettings);
end;

procedure TDpccSettingsEditorCodePart.Save2(var ASettings: TDpccPluginSettings);
begin
  ASettings.RegionFolds := cDpccRegionFoldModes[EnsureRange(FRegionFolds.Choice, 0, High(cDpccRegionFoldModes))];
  ASettings.MultiCursorModifier := TDpccPluginSettings.cMultiCursorModifierAlt;
  if FMultiCursorModifier.Choice = 1 then
  begin
    ASettings.MultiCursorModifier := TDpccPluginSettings.cMultiCursorModifierCtrl;
  end;
  ASettings.InlineDiagnostics := TDpccInlineDiagnostics.ModeName(
    TDpccInlineDiagnosticsMode(EnsureRange(FInlineDiagnostics.Choice, 0, Ord(High(TDpccInlineDiagnosticsMode)))));
end;

end.
