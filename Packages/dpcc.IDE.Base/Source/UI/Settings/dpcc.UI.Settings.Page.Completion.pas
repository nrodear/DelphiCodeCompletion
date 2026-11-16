unit dpcc.UI.Settings.Page.Completion;

// Reiter „Vervollständigung“: Zeilen, Breite, Listenmodus, Verlauf, angeheftete Favoriten (#458) und gelernte
// Vorschläge (#1890).

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Completion.Favorites,
  dpcc.UI.Settings.ChoiceBox,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Vervollständigung“: Zeilen, Breite, Listenmodus, Verlauf und angeheftete Favoriten
  /// (#458).</summary>
  TDpccSettingsCompletionPart = class(TDpccSettingsPagePart)
  private
    FRowsLabel: TLabel;
    FRows: TEdit;
    FRowsUpDown: TUpDown;
    FAutoWidth: TCheckBox;
    /// <summary>Listenmodus beim Tippen und sein Geltungsbereich (#497).</summary>
    FListMode: TDpccChoiceBox;
    FListScope: TDpccChoiceBox;
    FResetHistory: TButton;
    // Favoriten (#458): Schalter, Liste und Schlüssel je Zeile.
    FFavorites: TCheckBox;
    FResetWidths: TButton;
    /// <summary>Breiten der Vervollständigungsliste (gezogen bzw. zurückgesetzt), gespeichert mit OK.</summary>
    FListWidth, FPanelWidth: Integer;
    FOnResetHistory: TProc;
    procedure ResetHistoryClick(Sender: TObject);
    procedure ResetWidthsClick(Sender: TObject);
    procedure AutoWidthClick(Sender: TObject);
  public
    procedure Build;
    procedure Build2;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    procedure BindMarks; override;
    /// <summary>„Verlauf zurücksetzen“ der lernenden Gewichtung (#418).</summary>
    property OnResetHistory: TProc read FOnResetHistory write FOnResetHistory;
    /// <summary>Zum Testen: Favoriten (#458).</summary>
    property FavoritesCheck: TCheckBox read FFavorites;
    /// <summary>Zum Testen: Listenmodus der Vervollständigung (#497).</summary>
    property ListModeChoice: TDpccChoiceBox read FListMode;
    property ListScopeChoice: TDpccChoiceBox read FListScope;
    property AutoWidth: TCheckBox read FAutoWidth;
  end;

  /// <summary>Angeheftete Favoriten (#458) auf dem Reiter „Vervollständigung“: Liste mit „Entfernen“ und „Alle
  /// entfernen“. Die Seite kennt die Ablage nicht; OnFavorites liefert die Liste, OnRemoveFavorites löst die
  /// Schlüssel sofort (nicht erst mit OK).</summary>
  TDpccSettingsFavoritesPart = class(TDpccSettingsPagePart)
  private
    FFavoritesList: TListBox;
    FFavoritesRemove: TButton;
    FFavoritesRemoveAll: TButton;
    /// <summary>Schlüssel je Zeile der Liste.</summary>
    FFavoriteKeys: TArray<string>;
    FOnFavorites: TFunc<TArray<TDpccFavorite>>;
    FOnRemoveFavorites: TProc<TArray<string>>;
    procedure FavoritesRemoveClick(Sender: TObject);
    procedure FavoritesRemoveAllClick(Sender: TObject);
    procedure SetOnFavorites(const AValue: TFunc<TArray<TDpccFavorite>>);
  public
    procedure Build;
    procedure WindowReady; override;
    /// <summary>Liste der angehefteten Favoriten neu lesen (#458).</summary>
    procedure RefreshFavorites;
    /// <summary>Angeheftete Favoriten (#458) für die Liste; nil = keine Liste.</summary>
    property OnFavorites: TFunc<TArray<TDpccFavorite>> read FOnFavorites write SetOnFavorites;
    /// <summary>Favoriten mit diesen Schlüsseln lösen (#458, „Entfernen“, „Alle entfernen“).</summary>
    property OnRemoveFavorites: TProc<TArray<string>> read FOnRemoveFavorites write FOnRemoveFavorites;
    /// <summary>Zum Testen.</summary>
    property FavoritesList: TListBox read FFavoritesList;
    property FavoritesRemove: TButton read FFavoritesRemove;
    property FavoritesRemoveAll: TButton read FFavoritesRemoveAll;
  end;

implementation

uses
  System.Math,
  Vcl.Controls,
  dpcc.UI.Settings.Page.Sheets,
  dpcc.UI.Strings,
  dpcc.UI.Editor.LearnedSuggestions,
  dpcc.UI.Settings.Strings,
  dpcc.Core.Completion.Ranking;

{ TDpccSettingsCompletionPart }

procedure TDpccSettingsCompletionPart.Build;
var
  mPanel: TWinControl;
begin
  // Liste der Vervollständigung.
  AddSheet(TDpccTextId.SettingsTabCompletion);
  mPanel := AddPanel(26);
  FRowsLabel := TLabel.Create(FPage);
  FRowsLabel.Parent := mPanel;
  FRowsLabel.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsRows);
  FRowsLabel.Left := 0;
  FRowsLabel.Top := FRowsLabel.ScaleValue(5);
  FRows := TEdit.Create(FPage);
  FRows.Parent := mPanel;
  FRows.Left := cFieldLeft;
  FRows.Top := 1;
  FRows.Width := FRows.ScaleValue(44);
  FRows.NumbersOnly := True;
  FRowsUpDown := TUpDown.Create(FPage);
  FRowsUpDown.Parent := mPanel;
  FRowsUpDown.Associate := FRows;
  FRowsUpDown.Min := TDpccPluginSettings.cMinVisibleRows;
  FRowsUpDown.Max := TDpccPluginSettings.cMaxVisibleRows;
  FAutoWidth := AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsAutoWidth));
  FAutoWidth.OnClick := AutoWidthClick;
  BindText('OpenDelayMs', AddNumber(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsOpenDelay)));
  BindCheck('PanelCollapsed', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPanelCollapsed)));
  BindCheck('SelectionMarker', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsSelectionMarker)));
  BindCheck('FilterChips', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsChips)));
  BindCheck('Learning', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsLearning)));
  FFavorites := BindCheck('Favorites', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFavorites)));
  BindCheck('GroupInherited', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsGroupInherited)));
  BindCheck('CompletionVariantBranch',
    AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsCompletionVariantBranch)));
  // In der Reihenfolge von TDpccListMode bzw. TDpccListScope.
  FListMode := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListMode),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListModeFilter),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListModeAll),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListModeRest)]);
  FListScope := AddChoice(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListScope),
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListScopeMembers),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListScopeEverywhere)]);
  BindCheck('Preview', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPreview)));
  // Gelernte Vorschläge (#1890): Schattentext nach Enter aus dem eigenen Code.
  BindCheck('SuggestionsLearned', AddCheck(TDpccLearnedTexts.Text(TDpccLearnedText.SettingLearned)));
  BindText('SuggestionsDelayMs', AddNumber(TDpccLearnedTexts.Text(TDpccLearnedText.SettingDelay)));
  BindText('SuggestionsMinShare', AddNumber(TDpccLearnedTexts.Text(TDpccLearnedText.SettingMinShare)));
  BindText('SuggestionsMinCount', AddNumber(TDpccLearnedTexts.Text(TDpccLearnedText.SettingMinCount)));
  BindCheck('SuggestionsLearnFromUsage', AddCheck(TDpccLearnedTexts.Text(TDpccLearnedText.SettingLearnFromUsage)));
  mPanel := AddPanel(32);
  FResetHistory := TButton.Create(FPage);
  FResetHistory.Parent := mPanel;
  FResetHistory.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsResetHistory);
  FResetHistory.Left := 0;
  FResetHistory.Top := FResetHistory.ScaleValue(3);
  FResetHistory.Width := FResetHistory.ScaleValue(150);
  FResetHistory.OnClick := ResetHistoryClick;
  FResetWidths := TButton.Create(FPage);
  FResetWidths.Parent := mPanel;
end;

procedure TDpccSettingsCompletionPart.Build2;
begin
  FResetWidths.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsResetWidths);
  FResetWidths.Left := FResetWidths.ScaleValue(160);
  FResetWidths.Top := FResetWidths.ScaleValue(3);
  FResetWidths.Width := FResetWidths.ScaleValue(150);
  FResetWidths.OnClick := ResetWidthsClick;
end;

procedure TDpccSettingsCompletionPart.BindMarks;
begin
  FPage.Marks.Bind(FRows, ['VisibleRows']);
  FPage.Marks.Bind(FListMode, ['CompletionListMode']);
  FPage.Marks.Bind(FListScope, ['CompletionListScope']);
end;

procedure TDpccSettingsCompletionPart.Load(const ASettings: TDpccPluginSettings);
begin
  FListWidth := ASettings.ListWidth;
  FPanelWidth := ASettings.PanelWidth;
  FRowsUpDown.Position := ASettings.VisibleRows;
  FAutoWidth.OnClick := nil;
  FAutoWidth.Checked := ASettings.ListWidth = 0;
  FAutoWidth.OnClick := AutoWidthClick;
  FListMode.Choice := Ord(TDpccListModes.ModeOf(ASettings.CompletionListMode));
  FListScope.Choice := Ord(TDpccListModes.ScopeOf(ASettings.CompletionListScope));
end;

procedure TDpccSettingsCompletionPart.Save(var ASettings: TDpccPluginSettings);
begin
  ASettings.ListWidth := FListWidth;
  ASettings.PanelWidth := FPanelWidth;
  ASettings.VisibleRows := FRowsUpDown.Position;
  if (FListMode.Choice >= Ord(Low(TDpccListMode))) and (FListMode.Choice <= Ord(High(TDpccListMode))) then
  begin
    ASettings.CompletionListMode := TDpccListModes.cModeNames[TDpccListMode(FListMode.Choice)];
  end;
  if (FListScope.Choice >= Ord(Low(TDpccListScope))) and (FListScope.Choice <= Ord(High(TDpccListScope))) then
  begin
    ASettings.CompletionListScope := TDpccListModes.cScopeNames[TDpccListScope(FListScope.Choice)];
  end;
end;

procedure TDpccSettingsCompletionPart.AutoWidthClick(Sender: TObject);
begin
  // Automatisch: gezogene Breite vergessen; aus: die zuletzt gezogene bzw. die Vorgabe.
  if FAutoWidth.Checked then
  begin
    FListWidth := 0;
  end
  else if FListWidth = 0 then
  begin
    FListWidth := TDpccPluginSettings.cMinListWidth + 160;
  end;
end;

procedure TDpccSettingsCompletionPart.ResetHistoryClick(Sender: TObject);
begin
  if Assigned(FOnResetHistory) then
  begin
    FOnResetHistory();
  end;
  Allow(FResetHistory, False);
end;

procedure TDpccSettingsCompletionPart.ResetWidthsClick(Sender: TObject);
begin
  FListWidth := TDpccPluginSettings.Defaults.ListWidth;
  FPanelWidth := TDpccPluginSettings.Defaults.PanelWidth;
  FAutoWidth.OnClick := nil;
  FAutoWidth.Checked := FListWidth = 0;
  FAutoWidth.OnClick := AutoWidthClick;
  Allow(FResetWidths, False);
end;

{ TDpccSettingsFavoritesPart }

procedure TDpccSettingsFavoritesPart.Build;
var
  mPanel: TWinControl;
  mFavorites: TCheckBox;
begin
  mFavorites := FPage.Part<TDpccSettingsCompletionPart>.FavoritesCheck;
  AddTitle(TDpccTextId.SettingsFavoritesTitle);
  mPanel := AddPanel(80);
  FFavoritesList := TListBox.Create(FPage);
  FFavoritesList.Parent := mPanel;
  FFavoritesList.Align := alClient;
  FFavoritesList.MultiSelect := True;
  mPanel := AddPanel(32);
  FFavoritesRemove := TButton.Create(FPage);
  FFavoritesRemove.Parent := mPanel;
  FFavoritesRemove.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFavoritesRemove);
  FFavoritesRemove.Left := 0;
  FFavoritesRemove.Top := FFavoritesRemove.ScaleValue(3);
  FFavoritesRemove.Width := FFavoritesRemove.ScaleValue(150);
  FFavoritesRemove.OnClick := FavoritesRemoveClick;
  FFavoritesRemoveAll := TButton.Create(FPage);
  FFavoritesRemoveAll.Parent := mPanel;
  FFavoritesRemoveAll.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFavoritesRemoveAll);
  FFavoritesRemoveAll.Left := FFavoritesRemoveAll.ScaleValue(160);
  FFavoritesRemoveAll.Top := FFavoritesRemoveAll.ScaleValue(3);
  FFavoritesRemoveAll.Width := FFavoritesRemoveAll.ScaleValue(150);
  FFavoritesRemoveAll.OnClick := FavoritesRemoveAllClick;
  Attach(FFavoritesList.Parent, mFavorites);
  Attach(mPanel, mFavorites);
end;

procedure TDpccSettingsFavoritesPart.WindowReady;
begin
  RefreshFavorites;
end;

procedure TDpccSettingsFavoritesPart.SetOnFavorites(const AValue: TFunc<TArray<TDpccFavorite>>);
begin
  FOnFavorites := AValue;
  RefreshFavorites;
end;

procedure TDpccSettingsFavoritesPart.RefreshFavorites;
var
  mFavorites: TArray<TDpccFavorite>;
  mFavorite: TDpccFavorite;
  mAny: Boolean;
begin
  // Wie die Liste der Sicherung: ohne Fenster folgt das in CreateWnd.
  if not FPage.HandleAllocated then
  begin
    Exit;
  end;
  mFavorites := nil;
  if Assigned(FOnFavorites) then
  begin
    mFavorites := FOnFavorites();
  end;
  FFavoriteKeys := nil;
  mAny := Length(mFavorites) > 0;
  FFavoritesList.Items.BeginUpdate;
  try
    FFavoritesList.Items.Clear;
    for mFavorite in mFavorites do
    begin
      FFavoritesList.Items.Add(mFavorite.DisplayName);
      FFavoriteKeys := FFavoriteKeys + [mFavorite.Key];
    end;
    if not mAny then
    begin
      FFavoritesList.Items.Add(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFavoritesNone));
    end;
  finally
    FFavoritesList.Items.EndUpdate;
  end;
  Allow(FFavoritesList, mAny);
  Allow(FFavoritesRemove, mAny and Assigned(FOnRemoveFavorites));
  Allow(FFavoritesRemoveAll, mAny and Assigned(FOnRemoveFavorites));
end;

procedure TDpccSettingsFavoritesPart.FavoritesRemoveClick(Sender: TObject);
var
  mKeys: TArray<string>;
  mIndex: Integer;
begin
  if not Assigned(FOnRemoveFavorites) then
  begin
    Exit;
  end;
  mKeys := nil;
  for mIndex := 0 to Min(FFavoritesList.Items.Count, Length(FFavoriteKeys)) - 1 do
  begin
    if FFavoritesList.Selected[mIndex] then
    begin
      mKeys := mKeys + [FFavoriteKeys[mIndex]];
    end;
  end;
  if Length(mKeys) = 0 then
  begin
    Exit;
  end;
  FOnRemoveFavorites(mKeys);
  RefreshFavorites;
end;

procedure TDpccSettingsFavoritesPart.FavoritesRemoveAllClick(Sender: TObject);
begin
  if not Assigned(FOnRemoveFavorites) or (Length(FFavoriteKeys) = 0) then
  begin
    Exit;
  end;
  FOnRemoveFavorites(Copy(FFavoriteKeys));
  RefreshFavorites;
end;

end.
