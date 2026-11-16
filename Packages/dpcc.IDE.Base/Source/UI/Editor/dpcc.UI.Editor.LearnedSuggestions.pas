unit dpcc.UI.Editor.LearnedSuggestions;

// Gelernte Vorschläge (#1890): Texte für Befehl, Optionsseite und die Liste
// „Gelernte Vorschläge“, deutsch und englisch (eigene Tabelle, weil
// dpcc.UI.Strings über der Grenze der Unitlänge liegt), und die Liste selbst,
// reine VCL: je Muster Auslöser, Folge, Anteil, Stellen, Herkunft (Projekt
// oder dpcc.json) und wie oft es übernommen bzw. verworfen wurde. Das
// Kästchen schaltet ein Muster ab, „Vergessen“ löscht seine Lernzähler,
// Doppelklick bzw. „Zum Beleg“ zeigt die erste Stelle. Die Liste kennt die
// Ablage nicht; die IDE-Schicht reicht Zustand und Rückrufe herein.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  dpcc.Core.Localization.Language,
  dpcc.Core.Editor.LearnedSuggestions;

type
{$SCOPEDENUMS ON}
  TDpccLearnedText = (Command, Title, Intro, Empty, NoServer, ColumnTrigger, ColumnFollow, ColumnShare, ColumnCount,
    ColumnOrigin, ColumnUsed, OriginProject, OriginTeam, Used, Forget, GoToExample, Close, SettingLearned, SettingDelay,
    SettingMinShare, SettingMinCount, SettingLearnFromUsage);
{$SCOPEDENUMS OFF}

  TDpccLearnedTexts = class
  public
    class function Text(AId: TDpccLearnedText): string; static;
  end;

  /// <summary>Zeile der Liste.</summary>
  TDpccLearnedListItem = record
    Pattern: TDpccLearnedPattern;
    /// <summary>Nicht abgeschaltet.</summary>
    On_: Boolean;
    Accepted: Integer;
    Rejected: Integer;
  end;

  /// <summary>Rückrufe der Liste; AIndex zählt in den übergebenen Zeilen.</summary>
  TDpccLearnedListEvents = record
    /// <summary>Muster an- bzw. abschalten.</summary>
    Toggle: TProc<Integer, Boolean>;
    /// <summary>Lernzähler vergessen; liefert die Zeile danach.</summary>
    Forget: TFunc<Integer, TDpccLearnedListItem>;
    /// <summary>Zum ersten Beleg springen.</summary>
    GoTo_: TProc<Integer>;
  end;

  TDpccLearnedList = class
  public
    /// <summary>Modal; kehrt mit „Schließen“ oder Esc zurück.</summary>
    class procedure Execute(const AItems: TArray<TDpccLearnedListItem>; const AEvents: TDpccLearnedListEvents);
      static;
  end;

implementation

const
  cTexts: array[TDpccLanguage, TDpccLearnedText] of string = (
    ('Gelernte Vorschläge anzeigen …', 'Gelernte Vorschläge',
      'Was im Projekt meist auf einen Auslöser folgt. Das Kästchen schaltet ein Muster ab, „Vergessen“ löscht, wie ' +
      'oft es übernommen oder verworfen wurde.',
      'Noch keine Muster ab zwei Stellen. dpcc lernt beim Indizieren aus dem Projekt und aus suggestions.patterns ' +
      'in dpcc.json.',
      'Die Liste ist nicht verfügbar: Der dpcc-Server läuft nicht oder antwortet nicht.',
      'Auslöser', 'Folge', 'Anteil', 'Stellen', 'Herkunft', 'Genutzt', 'Projekt', 'dpcc.json',
      '%d× übernommen, %d× verworfen', 'Vergessen', 'Zum Beleg', 'Schließen',
      'Gelernte Vorschläge nach Enter (Tab übernimmt, Esc verwirft)', 'Pause bis zum Vorschlag (ms):',
      'Mindestanteil der Folge (%):', 'Mindestzahl der Stellen:', 'Aus der Nutzung lernen (Tab und Esc zählen)'),
    ('Show learned suggestions …', 'Learned suggestions',
      'What usually follows a trigger in the project. The check box turns a pattern off, "Forget" clears how often ' +
      'it was accepted or discarded.',
      'No patterns with two or more places yet. dpcc learns while indexing the project and from ' +
      'suggestions.patterns in dpcc.json.',
      'The list is not available: the dpcc server is not running or does not answer.',
      'Trigger', 'Follow-up', 'Share', 'Places', 'Origin', 'Used', 'Project', 'dpcc.json',
      '%d× accepted, %d× discarded', 'Forget', 'Go to example', 'Close',
      'Learned suggestions after Enter (Tab accepts, Esc discards)', 'Pause before the suggestion (ms):',
      'Minimum share of the follow-up (%):', 'Minimum number of places:', 'Learn from usage (Tab and Esc count)'));

{ TDpccLearnedTexts }

class function TDpccLearnedTexts.Text(AId: TDpccLearnedText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

function T(AId: TDpccLearnedText): string;
begin
  Result := TDpccLearnedTexts.Text(AId);
end;

const
  /// <summary>Maße in Pixeln bei 96 dpi.</summary>
  cWindowWidth = 860;
  cWindowHeight = 460;
  cButtonWidth = 110;
  cButtonTop = 9;
  cButtonBarHeight = 44;
  cGap = 10;
  cWidthTrigger = 190;
  cWidthFollow = 260;
  cWidthShare = 60;
  cWidthCount = 70;
  cWidthOrigin = 80;
  cWidthUsed = 180;

type
  /// <summary>Fenster der Liste mit seinen Ereignissen.</summary>
  TListWindow = class(TForm)
  private
    FItems: TArray<TDpccLearnedListItem>;
    FEvents: TDpccLearnedListEvents;
    FList: TListView;
    FForget: TButton;
    FGoTo: TButton;
    /// <summary>Beim Füllen keine Rückrufe für die Kästchen.</summary>
    FFilling: Boolean;
    procedure Fill(AItem: TListItem; const ARow: TDpccLearnedListItem);
    procedure Build;
    procedure BuildIntro;
    procedure BuildButtons;
    procedure BuildList;
    procedure FillList;
    procedure AddColumn(const ACaption: string; AWidth: Integer);
    function AddButton(AParent: TWinControl; const ACaption: string; ALeft: Integer): TButton;
    procedure ItemChecked(Sender: TObject; Item: TListItem);
    procedure ItemSelected(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ForgetClick(Sender: TObject);
    procedure GoToClick(Sender: TObject);
    procedure UpdateButtons;
  end;

procedure TListWindow.AddColumn(const ACaption: string; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := FList.Columns.Add;
  mColumn.Caption := ACaption;
  mColumn.Width := ScaleValue(AWidth);
end;

function TListWindow.AddButton(AParent: TWinControl; const ACaption: string; ALeft: Integer): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Width := ScaleValue(cButtonWidth);
  Result.Top := ScaleValue(cButtonTop);
  Result.Left := ScaleValue(ALeft);
end;

procedure TListWindow.Fill(AItem: TListItem; const ARow: TDpccLearnedListItem);
var
  mOrigin: string;
begin
  mOrigin := T(TDpccLearnedText.OriginProject);
  if ARow.Pattern.Team then
  begin
    mOrigin := T(TDpccLearnedText.OriginTeam);
  end;
  AItem.Caption := ARow.Pattern.Trigger;
  AItem.SubItems.Clear;
  AItem.SubItems.Add(ARow.Pattern.Text);
  AItem.SubItems.Add(Format('%d %%', [ARow.Pattern.Share]));
  AItem.SubItems.Add(Format('%d / %d', [ARow.Pattern.Count, ARow.Pattern.Total]));
  AItem.SubItems.Add(mOrigin);
  AItem.SubItems.Add(Format(T(TDpccLearnedText.Used), [ARow.Accepted, ARow.Rejected]));
  AItem.Checked := ARow.On_;
end;

procedure TListWindow.Build;
begin
  Caption := T(TDpccLearnedText.Title);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Width := ScaleValue(cWindowWidth);
  Height := ScaleValue(cWindowHeight);
  BuildIntro;
  BuildButtons;
  BuildList;
  FillList;
  FList.OnItemChecked := ItemChecked;
  FList.OnSelectItem := ItemSelected;
  FList.OnDblClick := GoToClick;
  if FList.Items.Count > 0 then
  begin
    FList.Items[0].Selected := True;
    ActiveControl := FList;
  end;
  UpdateButtons;
end;

procedure TListWindow.BuildIntro;
var
  mIntro: TLabel;
begin
  mIntro := TLabel.Create(Self);
  mIntro.Parent := Self;
  mIntro.Align := alTop;
  mIntro.WordWrap := True;
  mIntro.AlignWithMargins := True;
  mIntro.Caption := T(TDpccLearnedText.Intro);
  if Length(FItems) = 0 then
  begin
    mIntro.Caption := mIntro.Caption + sLineBreak + sLineBreak + T(TDpccLearnedText.Empty);
  end;
end;

procedure TListWindow.BuildButtons;
var
  mButtons: TPanel;
  mClose: TButton;
begin
  mButtons := TPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alBottom;
  mButtons.Height := ScaleValue(cButtonBarHeight);
  mButtons.BevelOuter := bvNone;
  FForget := AddButton(mButtons, T(TDpccLearnedText.Forget), cGap);
  FForget.OnClick := ForgetClick;
  FGoTo := AddButton(mButtons, T(TDpccLearnedText.GoToExample), cGap + cButtonWidth + cGap);
  FGoTo.OnClick := GoToClick;
  mClose := AddButton(mButtons, T(TDpccLearnedText.Close), 0);
  mClose.Left := mButtons.ClientWidth - mClose.Width - ScaleValue(cGap);
  mClose.Anchors := [akTop, akRight];
  mClose.ModalResult := mrOk;
  mClose.Cancel := True;
  mClose.Default := True;
end;

procedure TListWindow.BuildList;
begin
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.Checkboxes := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  AddColumn(T(TDpccLearnedText.ColumnTrigger), cWidthTrigger);
  AddColumn(T(TDpccLearnedText.ColumnFollow), cWidthFollow);
  AddColumn(T(TDpccLearnedText.ColumnShare), cWidthShare);
  AddColumn(T(TDpccLearnedText.ColumnCount), cWidthCount);
  AddColumn(T(TDpccLearnedText.ColumnOrigin), cWidthOrigin);
  AddColumn(T(TDpccLearnedText.ColumnUsed), cWidthUsed);
end;

procedure TListWindow.FillList;
var
  mIndex: Integer;
  mItem: TListItem;
begin
  FFilling := True;
  FList.Items.BeginUpdate;
  try
    for mIndex := 0 to High(FItems) do
    begin
      mItem := FList.Items.Add;
      mItem.Data := Pointer(mIndex);
      Fill(mItem, FItems[mIndex]);
    end;
  finally
    FList.Items.EndUpdate;
    FFilling := False;
  end;
end;

procedure TListWindow.UpdateButtons;
var
  mSelected: Boolean;
begin
  mSelected := FList.Selected <> nil;
  FForget.Enabled := mSelected;
  FGoTo.Enabled := mSelected and (Length(FItems[NativeInt(FList.Selected.Data)].Pattern.Evidence) > 0);
end;

procedure TListWindow.ItemChecked(Sender: TObject; Item: TListItem);
var
  mIndex: Integer;
begin
  if FFilling or (Item = nil) then
  begin
    Exit;
  end;
  mIndex := NativeInt(Item.Data);
  FItems[mIndex].On_ := Item.Checked;
  if Assigned(FEvents.Toggle) then
  begin
    FEvents.Toggle(mIndex, Item.Checked);
  end;
end;

procedure TListWindow.ItemSelected(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
end;

procedure TListWindow.ForgetClick(Sender: TObject);
var
  mIndex: Integer;
begin
  if (FList.Selected = nil) or not Assigned(FEvents.Forget) then
  begin
    Exit;
  end;
  mIndex := NativeInt(FList.Selected.Data);
  FItems[mIndex] := FEvents.Forget(mIndex);
  FFilling := True;
  try
    Fill(FList.Selected, FItems[mIndex]);
  finally
    FFilling := False;
  end;
end;

procedure TListWindow.GoToClick(Sender: TObject);
begin
  if (FList.Selected <> nil) and Assigned(FEvents.GoTo_) and
    (Length(FItems[NativeInt(FList.Selected.Data)].Pattern.Evidence) > 0) then
  begin
    FEvents.GoTo_(NativeInt(FList.Selected.Data));
  end;
end;

{ TDpccLearnedList }

class procedure TDpccLearnedList.Execute(const AItems: TArray<TDpccLearnedListItem>;
  const AEvents: TDpccLearnedListEvents);
var
  mWindow: TListWindow;
begin
  mWindow := TListWindow.CreateNew(nil);
  try
    mWindow.FItems := Copy(AItems);
    mWindow.FEvents := AEvents;
    mWindow.Build;
    mWindow.ShowModal;
  finally
    mWindow.Free;
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.UI.Editor.LearnedSuggestions', cTexts[TDpccLanguage.German],
    cTexts[TDpccLanguage.English]);

end.
