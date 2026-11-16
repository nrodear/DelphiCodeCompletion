unit dpcc.UI.Problems.ScopeBox;

// Bereichsliste im Fenster „dpcc-Prüfung“ mit einzelnen Projekten (#1843),
// reine VCL. Füllt die Auswahlliste aus TDpccScopeList: „Aktuelle Datei“,
// „Aktuelles Projekt“, „Projektgruppe“, darunter bei offener Gruppe mit
// mehreren Projekten ein Trennstrich und je Projekt ein Eintrag („Name“,
// beim aktiven „Name (aktiv)“). Die Liste ist selbst gezeichnet, damit der
// Trennstrich eine Linie ist; wer ihn wählt, bleibt auf der vorigen Wahl.
// Zeilenhöhe nach der Schrift, die Klappliste so breit wie der längste
// Eintrag. Texte deutsch und englisch in eigener Tabelle (dpcc.UI.Strings
// liegt über der Unitlänge).

interface

uses
  System.Types,
  Vcl.Controls,
  Vcl.StdCtrls,
  dpcc.Core.Localization.Language,
  dpcc.Core.Problems.ScopeProjects;

type
{$SCOPEDENUMS ON}
  /// <summary>ActiveMark: Eintrag des aktiven Projekts („Name (aktiv)“); Setting: Kontrollkästchen der
  /// Optionsseite (problems.window.scopeProjects).</summary>
  TDpccScopeBoxText = (ActiveMark, Setting);
{$SCOPEDENUMS OFF}

  /// <summary>Bereichsauswahl des Fensters über einer TComboBox (csOwnerDrawFixed).</summary>
  TDpccProblemsScopeBox = class
  private
    FCombo: TComboBox;
    /// <summary>Fenster, mit dem die Liste ein Fenster bekommt (der Frame); ohne dessen Fenster wird nicht gefüllt.
    /// </summary>
    FHost: TWinControl;
    FFixedTexts: TArray<string>;
    FProjects: TArray<TDpccScopeProject>;
    FShowProjects: Boolean;
    FList: TDpccScopeList;
    FChoice: TDpccScopeChoice;
    /// <summary>Kennung der gefüllten Einträge; '' = noch nicht gefüllt.</summary>
    FFilledKey: string;
    procedure DrawItem(AControl: TWinControl; AIndex: Integer; ARect: TRect; AState: TOwnerDrawState);
    /// <summary>Text des Eintrags AIndex der Liste.</summary>
    function ItemText(AIndex: Integer): string;
    /// <summary>Zeilenhöhe nach der Schrift (selbst gezeichnete Liste) und Breite der Klappliste nach dem längsten
    /// Eintrag.</summary>
    procedure FitSizes;
  public
    /// <summary>ACombo gehört dem Aufrufer und liegt in AHost; AFixedTexts in der Reihenfolge von
    /// TDpccFindingScope.</summary>
    constructor Create(AHost: TWinControl; ACombo: TComboBox; const AFixedTexts: TArray<string>);
    class function Text(AId: TDpccScopeBoxText): string; static;
    /// <summary>Einträge neu, wenn sich Projekte oder Schalter geändert haben (braucht ein Fenster); True, wenn
    /// dabei die Wahl auf das aktive Projekt zurückfiel (Einzelprojekt nicht mehr in der Gruppe).</summary>
    function Fill: Boolean;
    /// <summary>Projekte der offenen Gruppe; True wie bei Fill.</summary>
    function SetProjects(const AProjects: TArray<TDpccScopeProject>): Boolean;
    /// <summary>problems.window.scopeProjects; True wie bei Fill.</summary>
    function SetShowProjects(AValue: Boolean): Boolean;
    /// <summary>Wahl setzen und anzeigen.</summary>
    procedure Select(const AChoice: TDpccScopeChoice);
    /// <summary>Nach OnChange: Wahl aus dem gewählten Eintrag. False, wenn nichts Neues gewählt ist (Trennstrich:
    /// die vorige Wahl bleibt markiert).</summary>
    function Pick: Boolean;
    property Choice: TDpccScopeChoice read FChoice;
    property List: TDpccScopeList read FList;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Graphics,
  Vcl.Themes,
  dpcc.Core.Problems.Findings;

const
  cTexts: array[TDpccLanguage, TDpccScopeBoxText] of string = (
    ('%s (aktiv)', 'Einzelne Projekte der Gruppe in der Bereichsliste des Fensters'),
    ('%s (active)', 'Individual projects of the group in the window''s scope list'));
  /// <summary>Rand links im Eintrag und Zugabe der Klappliste bei 96 dpi.</summary>
  cTextIndent = 4;
  cDropExtra = 24;
  /// <summary>Bildschirmauflösung, für die die Maße oben gelten.</summary>
  cDesignPpi = 96;

{ TDpccProblemsScopeBox }

constructor TDpccProblemsScopeBox.Create(AHost: TWinControl; ACombo: TComboBox; const AFixedTexts: TArray<string>);
begin
  inherited Create;
  FHost := AHost;
  FCombo := ACombo;
  FFixedTexts := AFixedTexts;
  FShowProjects := True;
  FChoice := TDpccScopeChoice.Create(TDpccFindingScope.Group, '');
  FList := TDpccScopeList.Create(nil, FShowProjects);
  FCombo.Style := csOwnerDrawFixed;
  FCombo.OnDrawItem := DrawItem;
end;

class function TDpccProblemsScopeBox.Text(AId: TDpccScopeBoxText): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

function TDpccProblemsScopeBox.ItemText(AIndex: Integer): string;
var
  mProject: TDpccScopeProject;
begin
  Result := '';
  if AIndex <= High(FFixedTexts) then
  begin
    Exit(FFixedTexts[AIndex]);
  end;
  if FList.ProjectAt(AIndex, mProject) then
  begin
    Result := mProject.Name;
    if mProject.Active then
    begin
      Result := Format(Text(TDpccScopeBoxText.ActiveMark), [mProject.Name]);
    end;
  end;
end;

function TDpccProblemsScopeBox.Fill: Boolean;
var
  mResolved: TDpccScopeChoice;
  mIndex: Integer;
begin
  FList := TDpccScopeList.Create(FProjects, FShowProjects);
  mResolved := FList.Resolve(FChoice);
  Result := not mResolved.Same(FChoice);
  FChoice := mResolved;
  // Die Einträge brauchen ein Fenster (Items.Add legt es an): erst, wenn der Frame eins hat (CreateWnd).
  if not FHost.HandleAllocated then
  begin
    Exit;
  end;
  if (FFilledKey <> FList.Key) or (FCombo.Items.Count <> FList.Count) then
  begin
    FFilledKey := FList.Key;
    FCombo.Items.BeginUpdate;
    try
      FCombo.Items.Clear;
      for mIndex := 0 to FList.Count - 1 do
      begin
        FCombo.Items.Add(ItemText(mIndex));
      end;
    finally
      FCombo.Items.EndUpdate;
    end;
    FitSizes;
  end;
  FCombo.ItemIndex := FList.IndexOf(FChoice);
end;

procedure TDpccProblemsScopeBox.FitSizes;
var
  mIndex, mWidth: Integer;
begin
  FCombo.Canvas.Font := FCombo.Font;
  FCombo.ItemHeight := FCombo.Canvas.TextHeight('Ag') + MulDiv(cTextIndent, FCombo.CurrentPPI, cDesignPpi);
  mWidth := FCombo.Width;
  for mIndex := 0 to FCombo.Items.Count - 1 do
  begin
    mWidth := Max(mWidth, FCombo.Canvas.TextWidth(FCombo.Items[mIndex]) +
      MulDiv(cDropExtra, FCombo.CurrentPPI, cDesignPpi));
  end;
  SendMessage(FCombo.Handle, CB_SETDROPPEDWIDTH, mWidth, 0);
end;

function TDpccProblemsScopeBox.SetProjects(const AProjects: TArray<TDpccScopeProject>): Boolean;
begin
  FProjects := Copy(AProjects);
  Result := Fill;
end;

function TDpccProblemsScopeBox.SetShowProjects(AValue: Boolean): Boolean;
begin
  FShowProjects := AValue;
  Result := Fill;
end;

procedure TDpccProblemsScopeBox.Select(const AChoice: TDpccScopeChoice);
begin
  FChoice := AChoice;
  Fill;
end;

function TDpccProblemsScopeBox.Pick: Boolean;
var
  mNext: TDpccScopeChoice;
begin
  if (FCombo.ItemIndex < 0) or FList.IsSeparator(FCombo.ItemIndex) then
  begin
    FCombo.ItemIndex := FList.IndexOf(FChoice);
    Exit(False);
  end;
  mNext := FList.ChoiceAt(FCombo.ItemIndex);
  Result := not mNext.Same(FChoice);
  FChoice := mNext;
end;

procedure TDpccProblemsScopeBox.DrawItem(AControl: TWinControl; AIndex: Integer; ARect: TRect;
  AState: TOwnerDrawState);
var
  mCanvas: TCanvas;
  mMiddle: Integer;
begin
  mCanvas := FCombo.Canvas;
  if FList.IsSeparator(AIndex) then
  begin
    // Trennstrich nie hervorgehoben: Fläche der Liste, Linie in Grau.
    mCanvas.Brush.Color := StyleServices(FCombo).GetSystemColor(clWindow);
    mCanvas.FillRect(ARect);
    mMiddle := (ARect.Top + ARect.Bottom) div 2;
    mCanvas.Pen.Color := StyleServices(FCombo).GetSystemColor(clGrayText);
    mCanvas.MoveTo(ARect.Left + MulDiv(cTextIndent, FCombo.CurrentPPI, cDesignPpi), mMiddle);
    mCanvas.LineTo(ARect.Right - MulDiv(cTextIndent, FCombo.CurrentPPI, cDesignPpi), mMiddle);
    Exit;
  end;
  mCanvas.FillRect(ARect);
  if (AIndex >= 0) and (AIndex < FCombo.Items.Count) then
  begin
    mCanvas.TextRect(ARect, ARect.Left + MulDiv(cTextIndent, FCombo.CurrentPPI, cDesignPpi),
      ARect.Top + (ARect.Height - mCanvas.TextHeight('Ag')) div 2, FCombo.Items[AIndex]);
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.UI.Problems.ScopeBox', cTexts[TDpccLanguage.German],
    cTexts[TDpccLanguage.English]);

end.
