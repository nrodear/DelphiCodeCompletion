unit dpcc.UI.Settings.Page.TeamFile;

// Reiter „Einfügen“ und „Projektdatei“ (.dpcc, #486). Code-Vorlagen (Schalter, Vorlagen der Projektdatei) gibt es seit
// S2 nicht mehr.

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.TeamFile,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Einfügen“ und „Projektdatei“ (.dpcc, #486).</summary>
  TDpccSettingsTeamFilePart = class(TDpccSettingsPagePart)
  private
    // Projektdatei .dpcc (#486): Schalter, Anzeige der Werte „aus .dpcc“, Öffnen.
    FTeamFile: TCheckBox;
    FTeamFileInfo: TLabel;
    FTeamFileOpen: TButton;
    FOnTeamFile: TFunc<TDpccTeamSettings>;
    FOnOpenTeamFile: TProc;
    procedure AddTeamFileSection;
    procedure TeamFileClick(Sender: TObject);
    procedure TeamFileOpenClick(Sender: TObject);
    procedure SetOnTeamFile(const AValue: TFunc<TDpccTeamSettings>);
  public
    procedure Build;
    procedure Build2;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    /// <summary>Anzeige der Projektdatei neu aufbauen (#486).</summary>
    procedure RefreshTeamFile;
    /// <summary>Projektdatei .dpcc des aktiven Projekts (#486) für die Anzeige „aus .dpcc“; nil = keine.</summary>
    property OnTeamFile: TFunc<TDpccTeamSettings> read FOnTeamFile write SetOnTeamFile;
    /// <summary>„Projektdatei öffnen“: anlegen, falls es sie nicht gibt, und im Editor öffnen (#486).</summary>
    property OnOpenTeamFile: TProc read FOnOpenTeamFile write FOnOpenTeamFile;
    /// <summary>Zum Testen: Projektdatei (#486).</summary>
    property TeamFileCheck: TCheckBox read FTeamFile;
    property TeamFileInfo: TLabel read FTeamFileInfo;
    property TeamFileOpenButton: TButton read FTeamFileOpen;
  end;

implementation

uses
  Vcl.Controls,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings;

const
  // Höhe des Hinweises zur Teamdatei.
  cTeamFileHintHeight = 36;

/// <summary>Fehler einer ungültigen Projektdatei; mit Zeile und Spalte, wenn bekannt: Dort steht er im JSON.
/// </summary>
function TeamInvalidText(const ATeam: TDpccTeamSettings): string;
var
  mIssue: TDpccTeamIssue;
begin
  Result := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTeamFileInvalid);
  for mIssue in ATeam.Issues do
  begin
    if (mIssue.Kind = TDpccTeamIssueKind.Syntax) and (mIssue.Line > 0) then
    begin
      Exit(TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsTeamFileInvalidAt, [mIssue.Line, mIssue.Column]));
    end;
  end;
end;

/// <summary>Werte einer gültigen Projektdatei nach der Zeile mit ihrem Ort.</summary>
function TeamValueLines(const ATeam: TDpccTeamSettings): TArray<string>;
var
  mValue: TDpccTeamValue;
begin
  Result := nil;
  for mValue in TDpccTeamFile.Values(ATeam) do
  begin
    Result := Result + [TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsTeamFileValue, [mValue.Key,
      mValue.Value])];
  end;
  if Length(Result) = 0 then
  begin
    Result := Result + [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTeamFileNoValues)];
  end;
  if Length(ATeam.Issues) > 0 then
  begin
    Result := Result + [TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsTeamFileIssues, [Length(ATeam.Issues)])];
  end;
end;

/// <summary>Zeilen der Anzeige „aus .dpcc“ (#486).</summary>
function TeamFileLines(AOn: Boolean; const ATeam: TDpccTeamSettings): TArray<string>;
begin
  if not AOn then
  begin
    Result := TArray<string>.Create(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTeamFileOff));
  end
  else if ATeam.Project = '' then
  begin
    Result := TArray<string>.Create(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTeamFileNoProject));
  end
  else if not ATeam.Exists then
  begin
    Result := TArray<string>.Create(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTeamFileMissing));
  end
  else if not ATeam.Valid then
  begin
    Result := TArray<string>.Create(TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsTeamFileLocation,
      [ATeam.FileName]),
      TeamInvalidText(ATeam));
  end
  else
  begin
    Result := TArray<string>.Create(TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsTeamFileLocation,
      [ATeam.FileName])) +
      TeamValueLines(ATeam);
  end;
end;

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

procedure TDpccSettingsTeamFilePart.Build2;
begin
  AddSheet(TDpccTextId.SettingsTabTeamFile);
  AddTeamFileSection;
end;

procedure TDpccSettingsTeamFilePart.Load(const ASettings: TDpccPluginSettings);
begin
  RefreshTeamFile;
end;

procedure TDpccSettingsTeamFilePart.AddTeamFileSection;
var
  mPanel: TWinControl;
begin
  // Projektdatei .dpcc (#486): Schalter, Erklärung, „Projektdatei öffnen“ und jeder Wert mit „aus .dpcc“.
  FTeamFile := BindCheck('TeamFile', AddCheck(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTeamFile)));
  FTeamFile.OnClick := TeamFileClick;
  Attach(AddWrappedLabel(cTeamFileHintHeight,
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTeamFileHint)).Parent, FTeamFile);
  mPanel := AddPanel(32);
  FTeamFileOpen := TButton.Create(FPage);
  FTeamFileOpen.Parent := mPanel;
  FTeamFileOpen.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTeamFileOpen);
  FTeamFileOpen.Left := 0;
  FTeamFileOpen.Top := FTeamFileOpen.ScaleValue(3);
  FTeamFileOpen.Width := FTeamFileOpen.ScaleValue(180);
  FTeamFileOpen.OnClick := TeamFileOpenClick;
  Attach(mPanel, FTeamFile);
  FTeamFileInfo := AddWrappedLabel(180, '');
  Attach(FTeamFileInfo.Parent, FTeamFile);
  RefreshTeamFile;
end;

procedure TDpccSettingsTeamFilePart.TeamFileClick(Sender: TObject);
begin
  RefreshTeamFile;
end;

procedure TDpccSettingsTeamFilePart.TeamFileOpenClick(Sender: TObject);
begin
  if Assigned(FOnOpenTeamFile) then
  begin
    FOnOpenTeamFile();
  end;
  RefreshTeamFile;
end;

procedure TDpccSettingsTeamFilePart.SetOnTeamFile(const AValue: TFunc<TDpccTeamSettings>);
begin
  FOnTeamFile := AValue;
  RefreshTeamFile;
end;

procedure TDpccSettingsTeamFilePart.RefreshTeamFile;
var
  mTeam: TDpccTeamSettings;
begin
  // Ausgeschaltet wird die Datei nicht gelesen.
  mTeam := TDpccTeamFile.Empty;
  if FTeamFile.Checked and Assigned(FOnTeamFile) then
  begin
    mTeam := FOnTeamFile();
  end;
  FTeamFileInfo.Caption := string.Join(sLineBreak, TeamFileLines(FTeamFile.Checked, mTeam));
  Allow(FTeamFileOpen, FTeamFile.Checked and (mTeam.Project <> ''));
end;

end.
