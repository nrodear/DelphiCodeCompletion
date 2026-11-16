unit dpcc.UI.Settings.Page.Tree;

// Baum links auf der Optionsseite „dpcc“ (#890; vorher eine Liste): Bereiche und Unterpunkte, gewählte Seite und
// aufgeklappte Bereiche bis zum nächsten Öffnen. Dazu die Sperren durch Hauptschalter: Grund am Rahmen, Hinweis oben
// auf der Seite, Spiegel in der Übersicht und graue Knoten.
// Completion-Schnitt (ApplyView): Zeilen, deren Einstellungen dpcc.Core.Settings.CompletionView nicht mehr zeigt,
// fallen heraus, samt ihren Beschriftungen und angehängten Zeilen; Seiten ohne gezeigte Einstellung fallen aus dem
// Baum. Gespeicherte Werte bleiben unberührt.

interface

uses
  Vcl.Controls,
  Vcl.ComCtrls,
  dpcc.Core.Settings.Groups,
  dpcc.Core.Settings.NodeScope,
  dpcc.UI.Settings.Group,
  dpcc.UI.Settings.Page.Nodes,
  dpcc.UI.Settings.Page.Search;

type
  TDpccSettingsPageTree = class(TDpccSettingsPageNodes)
  protected
    /// <summary>Bereiche und ihre Unterpunkte als Baum links (#890; vorher eine Liste).</summary>
    FTree: TTreeView;
    /// <summary>Suchfeld über dem Baum (#1884); mit Text ersetzt die Trefferliste den Baum.</summary>
    FSearch: TDpccSettingsSearchBox;
    /// <summary>Baum links und rechts daneben die Reiter der Knoten.</summary>
    procedure AddNavigation;
    procedure FillTree;
    function ActiveNode: Integer;
    function LockOfName(const AName: string): TDpccSettingsLock;
  private
    FFillingTree: Boolean;
    FScope: TDpccSettingsNodeScope;
    /// <summary>Seiten ohne Element des Knotens (#1903), Index wie FNodePages.</summary>
    FScopeHidden: TArray<Boolean>;
    /// <summary>Vom Completion-Schnitt ausgeblendete Zeilen (ApplyView).</summary>
    FViewHidden: TArray<TControl>;
    function ViewHides(AControl: TControl): Boolean;
    /// <summary>Blendet in AHolder (Seite oder Rahmen) die Zeilen aus, die der Completion-Schnitt nicht zeigt;
    /// True, wenn eine gezeigte Einstellung bleibt.</summary>
    function FilterRows(AHolder: TWinControl): Boolean;
    /// <summary>Modulschalter (x-module) der Einstellung AName: der eigene oder der eines Vorfahren; '' = Base.
    /// </summary>
    function ModuleOfName(const AName: string): string;
    function InScope(AControl: TControl): Boolean;
    procedure ScopeOverviews;
    // Gewählte Seite und aufgeklappte Bereiche bis zum nächsten Öffnen (ohne verwaltete Typen: Leckmonitor).
    class var FLastPage: Integer;
    class var FExpandedAreas: set of Byte;
    class var FStateKnown: Boolean;
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure TreeExpanded(Sender: TObject; Node: TTreeNode);
    procedure TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    function PageShown(AIndex: Integer): Boolean;
    /// <summary>Vom Knoten ausgeblendete Seite AIndex: nur ein Bereich mit sichtbaren Unterpunkten bleibt.</summary>
    function ScopeShown(AIndex: Integer): Boolean;
    /// <summary>Hauptknoten AIndex: trifft der Filter einen Unterpunkt seines Bereichs?</summary>
    function AreaHasMatch(AIndex: Integer): Boolean;
    procedure RefreshTree;
    /// <summary>Knoten der gezeigten Seiten; liefert den Knoten der Seite ASelected, sonst den ersten.</summary>
    function AddTreeNodes(ASelected: Integer): TTreeNode;
    procedure ExpandAreas;
    procedure ShowWanted(AWanted: TTreeNode);
    function IsOn(const AName: string): Boolean;
    function LockText(const ALock: TDpccSettingsLock): string;
    procedure ApplyLocks(AContainer: TWinControl; ALocked: Boolean; var AOutside: TArray<string>);
    procedure ApplyFrameLocks(AFrame: TDpccSettingsGroup; ALocked: Boolean; var AOutside: TArray<string>);
    /// <summary>Gesperrt durch einen Hauptschalter, der nicht im selben Rahmen steht; dessen Grund nach AOutside.
    /// </summary>
    function RowLocked(AControl: TControl; var AOutside: TArray<string>): Boolean;
    function PageGray(AIndex: Integer): Boolean;
    /// <summary>Beim Zeigen eines Reiters: die Seite Versionsverwaltung fragt einmal „Aktuelles Projekt“ ab.
    /// </summary>
    procedure SheetShown(ASheet: TTabSheet);
  public
    procedure SelectPage(AIndex: Integer); override;
    /// <summary>Knoten je Package (#1903): nur die Elemente zeigen, die AScope gehören; Seiten ohne solche fallen
    /// aus dem Baum. Nach dem Aufbau, vor dem Laden.</summary>
    procedure ApplyScope(const AScope: TDpccSettingsNodeScope);
    /// <summary>Hat der Knoten etwas zu zeigen?</summary>
    function ScopeHasContent: Boolean;
    /// <summary>Completion-Schnitt: nur die Zeilen zeigen, die dpcc.Core.Settings.CompletionView behält; Seiten
    /// ohne solche fallen aus dem Baum, die Bindungen der übrigen aus der Markierung. Nach dem Aufbau, vor dem
    /// Laden.</summary>
    procedure ApplyView;
    /// <summary>Steht die Einstellung AName sichtbar auf der Seite (nicht vom Completion-Schnitt ausgeblendet)?
    /// </summary>
    function SettingShown(const AName: string): Boolean;
    property Scope: TDpccSettingsNodeScope read FScope;
    /// <summary>Sperren, Grund, Spiegel und graue Knoten nach den aktuellen Werten (#890).</summary>
    procedure UpdateLocks;
    function SheetGray(ASheet: TTabSheet): Boolean;
    /// <summary>Gemerkte Auswahl und aufgeklappte Bereiche vergessen (Tests).</summary>
    class procedure ForgetTreeState; static;
    /// <summary>Baum der Bereiche und Unterpunkte links; schaltet Pages um (#890).</summary>
    property Navigation: TTreeView read FTree;
  end;

implementation

uses
  Vcl.Themes,
  System.SysUtils,
  System.Classes,
  Vcl.StdCtrls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  dpcc.UI.Settings.Strings,
  dpcc.UI.Settings.ChoiceBox,
  dpcc.UI.Settings.Marks,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Page.Sheets,
  dpcc.UI.Settings.Page.Host,
  dpcc.UI.Settings.Page.General,
  dpcc.Core.Settings.CompletionView;

procedure AddUnique(var AList: TArray<string>; const AText: string);
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if mItem = AText then
    begin
      Exit;
    end;
  end;
  AList := AList + [AText];
end;

function PageIndexOf(ANode: TTreeNode): Integer;
begin
  Result := -1;
  if ANode <> nil then
  begin
    Result := Integer(NativeInt(ANode.Data));
  end;
end;

{ TDpccSettingsPageTree }

procedure TDpccSettingsPageTree.AddNavigation;
var
  mPanel: TPanel;
begin
  // Reiter je Bereich (#227); jeder stapelt seine Elemente neu von oben. Viele Reiter: in Zeilen.
  // Bereiche und Unterpunkte als Baum links (#890); die Reiter selbst bleiben unsichtbar, der Baum schaltet sie um.
  // Links: Suchfeld (#1884) über dem Baum; mit Suchtext ersetzt die Trefferliste den Baum.
  mPanel := TPanel.Create(Self);
  mPanel.Parent := Self;
  mPanel.Align := alLeft;
  mPanel.Width := mPanel.ScaleValue(176);
  mPanel.BevelOuter := bvNone;
  mPanel.ParentBackground := True;
  FSearch := TDpccSettingsSearchBox.Create(Self, mPanel, Catalog,
    function: TDpccSettingsGroups
    begin
      Result := FGroups;
    end);
  FSearch.OnSearching :=
    procedure(AShowing: Boolean)
    begin
      FTree.Visible := not AShowing;
    end;
  FTree := TTreeView.Create(Self);
  FTree.Parent := mPanel;
  FTree.Align := alClient;
  FTree.AlignWithMargins := True;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.OnChange := TreeChange;
  FTree.OnExpanded := TreeExpanded;
  FTree.OnCollapsed := TreeExpanded;
  FTree.OnCustomDrawItem := TreeCustomDrawItem;
  AddPages;
end;

procedure TDpccSettingsPageTree.SheetShown(ASheet: TTabSheet);
var
  mPart: TDpccSettingsPagePart;
begin
  for mPart in FParts do
  begin
    mPart.SheetShown(ASheet);
  end;
end;

function TDpccSettingsPageTree.ActiveNode: Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  if FPages.ActivePage = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FNodePages) do
  begin
    if FNodePages[mIndex].Sheet = FPages.ActivePage then
    begin
      Exit(mIndex);
    end;
  end;
end;

procedure TDpccSettingsPageTree.SelectPage(AIndex: Integer);
var
  mIndex: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FNodePages)) then
  begin
    Exit;
  end;
  FPages.ActivePage := FNodePages[AIndex].Sheet;
  SheetShown(FNodePages[AIndex].Sheet);
  if not ListReady(FTree) then
  begin
    Exit;
  end;
  for mIndex := 0 to FTree.Items.Count - 1 do
  begin
    if PageIndexOf(FTree.Items[mIndex]) = AIndex then
    begin
      FTree.Selected := FTree.Items[mIndex];
      Break;
    end;
  end;
end;

function TDpccSettingsPageTree.ModuleOfName(const AName: string): string;
begin
  Result := TDpccSettingsNodeScope.ModuleOf(Catalog, FGroups, AName);
end;

function TDpccSettingsPageTree.InScope(AControl: TControl): Boolean;
var
  mNames, mModules: TArray<string>;
  mName: string;
begin
  mNames := FMarks.NamesOf(AControl);
  if AControl is TWinControl then
  begin
    mNames := mNames + FMarks.NamesIn(TWinControl(AControl));
  end;
  mModules := nil;
  for mName in mNames do
  begin
    mModules := mModules + [ModuleOfName(mName)];
  end;
  Result := FScope.Includes(SectionOwnersIn(AControl), mModules);
end;

procedure TDpccSettingsPageTree.ApplyScope(const AScope: TDpccSettingsNodeScope);
var
  mIndex, mChild: Integer;
  mBox: TScrollBox;
  mControl: TControl;
  mAny: Boolean;
begin
  FScope := AScope;
  FSearch.OwnModule := AScope.Switch;
  SetLength(FScopeHidden, Length(FNodePages));
  for mIndex := 0 to High(FNodePages) do
  begin
    mBox := FNodePages[mIndex].Box;
    mAny := False;
    for mChild := 0 to mBox.ControlCount - 1 do
    begin
      mControl := mBox.Controls[mChild];
      if (mControl = FNodePages[mIndex].Banner) or ((mControl is TDpccSettingsGroup) and
        IsOverview(TDpccSettingsGroup(mControl))) then
      begin
        Continue;
      end;
      if InScope(mControl) then
      begin
        mAny := mAny or mControl.Visible;
      end
      else
      begin
        mControl.Visible := False;
      end;
    end;
    FScopeHidden[mIndex] := not mAny;
  end;
  ScopeOverviews;
  if ListReady(FTree) then
  begin
    FillTree;
  end;
end;

procedure TDpccSettingsPageTree.ScopeOverviews;
var
  mIndex: Integer;
  mOverview: TDpccSettingsGroup;
  mShown: Boolean;
  mChild: Integer;
begin
  // Übersicht „Funktionen in diesem Bereich“: nur Zeilen zu Rahmen, die der Knoten zeigt.
  for mIndex := 0 to High(FOverviewRows) do
  begin
    FOverviewRows[mIndex].Visible := FOverviewFrames[mIndex].Visible;
  end;
  for mOverview in FOverviews do
  begin
    mShown := False;
    for mIndex := 0 to High(FOverviewRows) do
    begin
      mShown := mShown or (FOverviewRows[mIndex].Visible and (FOverviewRows[mIndex].Parent <> nil) and
        ((FOverviewRows[mIndex].Parent = mOverview) or (FOverviewRows[mIndex].Parent.Parent = mOverview)));
    end;
    mOverview.Visible := mShown;
    if mShown then
    begin
      mOverview.AdjustHeight;
      // Hauptknoten mit Übersicht: zeigen, auch wenn er selbst nichts hat.
      for mChild := 0 to High(FNodePages) do
      begin
        if mOverview.Parent = FNodePages[mChild].Box then
        begin
          FScopeHidden[mChild] := False;
        end;
      end;
    end;
  end;
end;

function TDpccSettingsPageTree.ViewHides(AControl: TControl): Boolean;
var
  mHidden: TControl;
begin
  for mHidden in FViewHidden do
  begin
    if mHidden = AControl then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Zeilen von AHolder von oben nach unten.</summary>
function RowsByTop(AHolder: TWinControl): TArray<TControl>;
var
  mIndex, mPosition: Integer;
  mControl: TControl;
begin
  Result := nil;
  for mIndex := 0 to AHolder.ControlCount - 1 do
  begin
    mControl := AHolder.Controls[mIndex];
    mPosition := Length(Result);
    while (mPosition > 0) and (Result[mPosition - 1].Top > mControl.Top) do
    begin
      Dec(mPosition);
    end;
    Insert(mControl, Result, mPosition);
  end;
end;

/// <summary>Liegt AControl in AParent (oder ist es selbst)?</summary>
function InsideOf(AControl, AParent: TControl): Boolean;
var
  mParent: TControl;
begin
  mParent := AControl;
  while (mParent <> nil) and (mParent <> AParent) do
  begin
    mParent := mParent.Parent;
  end;
  Result := mParent <> nil;
end;

type
  /// <summary>Art einer Zeile für den Completion-Schnitt: mit Einstellung (auch Rahmen), angehängt, Beschriftung,
  /// sonst (Knöpfe, Pfadfeld, Listen ohne eigene Einstellung).</summary>
  TDpccViewRowKind = (vkBound, vkAttached, vkLabel, vkOther);

function TDpccSettingsPageTree.FilterRows(AHolder: TWinControl): Boolean;
var
  mAll, mRows: TArray<TControl>;
  mKinds: TArray<TDpccViewRowKind>;
  mShow: TArray<Boolean>;
  mControl, mAnchor: TControl;
  mNames: TArray<string>;
  mIndex, mOther, mNext: Integer;
  mFrame: TDpccSettingsGroup;
  mSkip: Boolean;

  function AnyShown(const ANames: TArray<string>): Boolean;
  var
    mCandidate: string;
  begin
    for mCandidate in ANames do
    begin
      if TDpccCompletionView.ShowsName(Catalog, mCandidate) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

begin
  Result := False;
  mRows := nil;
  mAll := RowsByTop(AHolder);
  for mControl in mAll do
  begin
    // Kopf und Grund eines Rahmens, Hinweis oben auf der Seite und die Übersicht bleiben dem Rahmen bzw. der Seite.
    mSkip := (AHolder is TDpccSettingsGroup) and ((mControl = TDpccSettingsGroup(AHolder).Master) or
      (mControl = TDpccSettingsGroup(AHolder).Reason));
    mSkip := mSkip or ((mControl is TDpccSettingsGroup) and IsOverview(TDpccSettingsGroup(mControl)));
    for mIndex := 0 to High(FNodePages) do
    begin
      mSkip := mSkip or (mControl = FNodePages[mIndex].Banner);
    end;
    if not mSkip then
    begin
      mRows := mRows + [mControl];
    end;
  end;
  SetLength(mKinds, Length(mRows));
  SetLength(mShow, Length(mRows));
  // Zeilen mit Einstellung (Rahmen: Hauptschalter oder eine Zeile darin) und übrige Zeilen.
  for mIndex := 0 to High(mRows) do
  begin
    mControl := mRows[mIndex];
    mShow[mIndex] := True;
    if mControl is TDpccSettingsGroup then
    begin
      mFrame := TDpccSettingsGroup(mControl);
      mKinds[mIndex] := vkBound;
      mShow[mIndex] := FilterRows(mFrame);
      if (mFrame.Master <> nil) and AnyShown(FMarks.NamesWithin(mFrame.Master)) then
      begin
        mShow[mIndex] := True;
      end;
      mFrame.AdjustHeight;
      Continue;
    end;
    mNames := FMarks.NamesWithin(mControl);
    if Length(mNames) > 0 then
    begin
      mKinds[mIndex] := vkBound;
      mShow[mIndex] := AnyShown(mNames);
    end
    else if FAttached.ContainsKey(mControl) then
    begin
      mKinds[mIndex] := vkAttached;
    end
    else if (mControl is TDpccSettingsRow) and (TWinControl(mControl).ControlCount = 1) and
      (TWinControl(mControl).Controls[0] is TLabel) then
    begin
      mKinds[mIndex] := vkLabel;
    end
    else
    begin
      mKinds[mIndex] := vkOther;
    end;
  end;
  // Angehängte Zeilen (Liste und Knöpfe einer Funktion) folgen ihrer Funktion.
  for mIndex := 0 to High(mRows) do
  begin
    if mKinds[mIndex] <> vkAttached then
    begin
      Continue;
    end;
    mAnchor := FAttached[mRows[mIndex]];
    mOther := -1;
    for mNext := 0 to High(mRows) do
    begin
      if (mNext <> mIndex) and (mKinds[mNext] <> vkAttached) and InsideOf(mAnchor, mRows[mNext]) then
      begin
        mOther := mNext;
      end;
    end;
    if mOther >= 0 then
    begin
      mShow[mIndex] := mShow[mOther];
    end
    else
    begin
      mNames := FMarks.NamesWithin(mAnchor);
      mShow[mIndex] := (Length(mNames) = 0) or AnyShown(mNames);
    end;
  end;
  // Beschriftungen: unter einer Zeile ohne Einstellung (Pfadfeld) gehören sie zu ihr, sonst zur Zeile darunter.
  for mIndex := 0 to High(mRows) do
  begin
    if mKinds[mIndex] <> vkLabel then
    begin
      Continue;
    end;
    mOther := mIndex - 1;
    while (mOther >= 0) and (mKinds[mOther] = vkLabel) do
    begin
      Dec(mOther);
    end;
    if (mOther >= 0) and (mKinds[mOther] = vkOther) then
    begin
      Continue;
    end;
    mNext := mIndex + 1;
    while (mNext <= High(mRows)) and (mKinds[mNext] = vkLabel) do
    begin
      Inc(mNext);
    end;
    if mNext <= High(mRows) then
    begin
      mShow[mIndex] := mShow[mNext];
    end
    else if mOther >= 0 then
    begin
      mShow[mIndex] := mShow[mOther];
    end;
  end;
  for mIndex := 0 to High(mRows) do
  begin
    if not mShow[mIndex] then
    begin
      mRows[mIndex].Visible := False;
      FViewHidden := FViewHidden + [mRows[mIndex]];
    end
    else if mKinds[mIndex] = vkBound then
    begin
      Result := True;
    end;
  end;
end;

procedure TDpccSettingsPageTree.ApplyView;
var
  mIndex, mChild: Integer;
  mBox: TScrollBox;
  mControl: TControl;
  mEditor: string;
begin
  FViewHidden := nil;
  for mIndex := 0 to High(FNodePages) do
  begin
    mBox := FNodePages[mIndex].Box;
    if FilterRows(mBox) then
    begin
      Continue;
    end;
    // Seite ohne gezeigte Einstellung: auch ihre Knöpfe, Listen und Hinweise ausblenden.
    for mChild := 0 to mBox.ControlCount - 1 do
    begin
      mControl := mBox.Controls[mChild];
      if (mControl = FNodePages[mIndex].Banner) or ((mControl is TDpccSettingsGroup) and
        IsOverview(TDpccSettingsGroup(mControl))) or not mControl.Visible then
      begin
        Continue;
      end;
      mControl.Visible := False;
      FViewHidden := FViewHidden + [mControl];
    end;
  end;
  for mControl in FViewHidden do
  begin
    FMarks.Drop(mControl);
  end;
  // Auf dem Reiter Editor stehen nur noch Hover und XMLDoc.
  mEditor := TDpccStrings.Text(TDpccTextId.SettingsTabEditor);
  for mIndex := 0 to High(FNodePages) do
  begin
    if (FNodePages[mIndex].Node = '') and SameText(FNodePages[mIndex].Caption, mEditor) then
    begin
      FNodePages[mIndex].Caption := TDpccCompletionView.cHintsCaption;
      FNodePages[mIndex].Sheet.Caption := TDpccCompletionView.cHintsCaption;
    end;
  end;
  ApplyScope(FScope);
end;

function TDpccSettingsPageTree.SettingShown(const AName: string): Boolean;
var
  mParent: TControl;
begin
  mParent := FMarks.ControlOfName(AName);
  Result := mParent <> nil;
  while Result and (mParent <> nil) do
  begin
    Result := not ViewHides(mParent);
    mParent := mParent.Parent;
  end;
end;

function TDpccSettingsPageTree.ScopeHasContent: Boolean;
var
  mHidden: Boolean;
begin
  for mHidden in FScopeHidden do
  begin
    if not mHidden then
    begin
      Exit(True);
    end;
  end;
  Result := Length(FScopeHidden) = 0;
end;

function TDpccSettingsPageTree.ScopeShown(AIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  // Knoten je Package (#1903): Seiten ohne Element des Knotens fallen weg; ein Bereich bleibt für seine Punkte.
  Result := False;
  if FNodePages[AIndex].Node <> '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FNodePages) do
  begin
    if (mIndex <> AIndex) and (FNodePages[mIndex].Area = FNodePages[AIndex].Area) and
      (mIndex <= High(FScopeHidden)) and not FScopeHidden[mIndex] then
    begin
      Exit(True);
    end;
  end;
end;

function TDpccSettingsPageTree.AreaHasMatch(AIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  // Ein Bereich bleibt, solange einer seiner Punkte trifft.
  Result := False;
  if FNodePages[AIndex].Node <> '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FNodePages) do
  begin
    if (mIndex <> AIndex) and (FNodePages[mIndex].Area = FNodePages[AIndex].Area) and
      FMarks.HasMatch(FNodePages[mIndex].Box) then
    begin
      Exit(True);
    end;
  end;
end;

function TDpccSettingsPageTree.PageShown(AIndex: Integer): Boolean;
begin
  if (AIndex <= High(FScopeHidden)) and FScopeHidden[AIndex] then
  begin
    Result := ScopeShown(AIndex);
  end
  else
  begin
    // Der Filter blendet Unterpunkte ohne Treffer aus.
    Result := (FMarks.Filter = sfAll) or FMarks.HasMatch(FNodePages[AIndex].Box) or AreaHasMatch(AIndex);
  end;
end;

function TDpccSettingsPageTree.AddTreeNodes(ASelected: Integer): TTreeNode;
var
  mIndex, mArea: Integer;
  mAreaNodes: TArray<TTreeNode>;
  mNode: TTreeNode;
begin
  Result := nil;
  SetLength(mAreaNodes, Length(Sheets));
  for mIndex := 0 to High(FNodePages) do
  begin
    if not PageShown(mIndex) then
    begin
      Continue;
    end;
    mArea := FNodePages[mIndex].Area;
    if FNodePages[mIndex].Node = '' then
    begin
      mNode := FTree.Items.AddObject(nil, FNodePages[mIndex].Caption, Pointer(NativeInt(mIndex)));
      mAreaNodes[mArea] := mNode;
    end
    else
    begin
      mNode := FTree.Items.AddChildObject(mAreaNodes[mArea], FNodePages[mIndex].Caption, Pointer(NativeInt(mIndex)));
    end;
    if mIndex = ASelected then
    begin
      Result := mNode;
    end;
  end;
  if (Result = nil) and (FTree.Items.Count > 0) then
  begin
    Result := FTree.Items[0];
  end;
end;

procedure TDpccSettingsPageTree.ExpandAreas;
var
  mIndex, mArea: Integer;
  mNode: TTreeNode;
begin
  // Aufgeklappt wie beim letzten Mal; beim ersten Öffnen der Bereich der gewählten Seite.
  for mIndex := 0 to FTree.Items.Count - 1 do
  begin
    mNode := FTree.Items[mIndex];
    if (mNode.Level = 0) and mNode.HasChildren then
    begin
      mArea := FNodePages[PageIndexOf(mNode)].Area;
      mNode.Expanded := FStateKnown and (mArea <= High(Byte)) and (Byte(mArea) in FExpandedAreas);
    end;
  end;
end;

procedure TDpccSettingsPageTree.ShowWanted(AWanted: TTreeNode);
begin
  if AWanted = nil then
  begin
    Exit;
  end;
  if AWanted.Parent <> nil then
  begin
    AWanted.Parent.Expanded := True;
  end
  else if not FStateKnown and AWanted.HasChildren then
  begin
    AWanted.Expanded := True;
  end;
  FTree.Selected := AWanted;
  FPages.ActivePage := FNodePages[PageIndexOf(AWanted)].Sheet;
end;

procedure TDpccSettingsPageTree.FillTree;
var
  mSelected: Integer;
  mWanted: TTreeNode;
begin
  mSelected := ActiveNode;
  if (mSelected < 0) and FStateKnown then
  begin
    mSelected := FLastPage;
  end;
  FFillingTree := True;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    mWanted := AddTreeNodes(mSelected);
    ExpandAreas;
    ShowWanted(mWanted);
  finally
    FTree.Items.EndUpdate;
    FFillingTree := False;
  end;
  RefreshTree;
end;

procedure TDpccSettingsPageTree.RefreshTree;
var
  mIndex, mPage: Integer;
  mNode: TTreeNode;
  mText: string;
begin
  if not ListReady(FTree) then
  begin
    Exit;
  end;
  for mIndex := 0 to FTree.Items.Count - 1 do
  begin
    mNode := FTree.Items[mIndex];
    mPage := PageIndexOf(mNode);
    if (mPage < 0) or (mPage > High(FNodePages)) then
    begin
      Continue;
    end;
    // Punkt wie an den Einstellungen: Auf dieser Seite ist etwas geändert.
    mText := FNodePages[mPage].Caption;
    if FMarks.HasMarked(FNodePages[mPage].Box) then
    begin
      mText := TDpccSettingsMarks.cDot + mText;
    end;
    if mNode.Text <> mText then
    begin
      mNode.Text := mText;
    end;
  end;
  FTree.Invalidate;
end;

procedure TDpccSettingsPageTree.TreeChange(Sender: TObject; Node: TTreeNode);
var
  mIndex: Integer;
begin
  mIndex := PageIndexOf(Node);
  if (mIndex < 0) or (mIndex > High(FNodePages)) or (csDestroying in ComponentState) then
  begin
    Exit;
  end;
  FPages.ActivePage := FNodePages[mIndex].Sheet;
  SheetShown(FNodePages[mIndex].Sheet);
  // Beim Neuaufbau des Baums wählt er selbst; gemerkt wird nur die Wahl des Nutzers.
  if FFillingTree then
  begin
    Exit;
  end;
  FLastPage := mIndex;
  FStateKnown := True;
end;

procedure TDpccSettingsPageTree.TreeExpanded(Sender: TObject; Node: TTreeNode);
var
  mIndex, mArea: Integer;
begin
  mIndex := PageIndexOf(Node);
  if FFillingTree or (csDestroying in ComponentState) or (mIndex < 0) or (mIndex > High(FNodePages)) then
  begin
    Exit;
  end;
  mArea := FNodePages[mIndex].Area;
  if (mArea < 0) or (mArea > High(Byte)) then
  begin
    Exit;
  end;
  if Node.Expanded then
  begin
    Include(FExpandedAreas, Byte(mArea));
  end
  else
  begin
    Exclude(FExpandedAreas, Byte(mArea));
  end;
  FStateKnown := True;
end;

procedure TDpccSettingsPageTree.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
  var DefaultDraw: Boolean);
var
  mIndex: Integer;
begin
  DefaultDraw := True;
  // Abgeschaltete oder gesperrte Unterpunkte grau.
  mIndex := PageIndexOf(Node);
  if (mIndex >= 0) and (mIndex <= High(FNodePages)) and FNodePages[mIndex].Gray and not (cdsSelected in State) then
  begin
    // Hintergrund in der Stilfarbe, sonst zeichnet die Zeile weiß bzw. schwarz (clWindow, clWindowText ohne Stil).
    if not (cdsSelected in State) then
    begin
      Sender.Canvas.Brush.Color := StyleServices(Sender).GetSystemColor(clWindow);
      Sender.Canvas.Font.Color := StyleServices(Sender).GetSystemColor(clWindowText);
    end;
    Sender.Canvas.Font.Color := StyleServices(Sender).GetSystemColor(clGrayText);
  end;
end;

function TDpccSettingsPageTree.IsOn(const AName: string): Boolean;
var
  mControl: TControl;
begin
  // Kontrollkästchen: angehakt; Auswahl (etwa „Beim Öffnen bauen“): ein Eintrag außer dem ersten („nicht …“).
  mControl := FMarks.ControlOfName(AName);
  if mControl is TCheckBox then
  begin
    Result := TCheckBox(mControl).Checked;
  end
  else if mControl is TDpccChoiceBox then
  begin
    Result := TDpccChoiceBox(mControl).Choice > 0;
  end
  else
  begin
    Result := True;
  end;
end;

function TDpccSettingsPageTree.LockOfName(const AName: string): TDpccSettingsLock;
begin
  Result := FGroups.LockOf(AName, IsOn, Part<TDpccSettingsGeneralPart>.ExperimentalEnabled.Checked);
end;

function TDpccSettingsPageTree.LockText(const ALock: TDpccSettingsLock): string;
var
  mPage, mEntry: Integer;
  mWhere, mCaption: string;
begin
  Result := '';
  case ALock.Reason of
    lrExperimental:
      Result := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsLockedExperimental);
    lrMasterOff:
      begin
        mCaption := FMarks.TextOfName(ALock.Master);
        if mCaption = '' then
        begin
          mCaption := FGroups.KeyOf(ALock.Master);
        end;
        mWhere := '';
        mPage := PageOf(FMarks.ControlOfName(ALock.Master));
        if mPage >= 0 then
        begin
          mWhere := FSheets[FNodePages[mPage].Area].Caption;
          if FNodePages[mPage].Node <> '' then
          begin
            mWhere := mWhere + ' › ' + FNodePages[mPage].Caption;
          end;
        end
        else
        begin
          mEntry := Catalog.IndexOfName(ALock.Master);
          if mEntry >= 0 then
          begin
            mWhere := Catalog.Entries[mEntry].Page;
          end;
        end;
        Result := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsLockedMaster, [mCaption, mWhere]);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TDpccSettingsPageTree.ApplyFrameLocks(AFrame: TDpccSettingsGroup; ALocked: Boolean;
  var AOutside: TArray<string>);
var
  mLock: TDpccSettingsLock;
  mMasterLocked: Boolean;
begin
  // Der Hauptschalter selbst: gesperrt durch einen Rahmen darüber, einen Schalter woanders oder experimentell.
  mLock := LockOfName(AFrame.MasterName);
  mMasterLocked := ALocked or mLock.Locked;
  SetLocked(AFrame.Master, mMasterLocked);
  if mLock.Locked and not ALocked then
  begin
    AFrame.ShowReason(LockText(mLock));
  end
  else
  begin
    AFrame.ShowReason('');
  end;
  ApplyLocks(AFrame, mMasterLocked or not IsOn(AFrame.MasterName), AOutside);
end;

function TDpccSettingsPageTree.RowLocked(AControl: TControl; var AOutside: TArray<string>): Boolean;
var
  mAnchor: TControl;
  mLock: TDpccSettingsLock;
  mSetting: string;
  mNames: TArray<string>;
begin
  // Zeile ohne Rahmen: ihr Hauptschalter steht auf einer anderen Seite (Grund oben auf der Seite).
  Result := False;
  mNames := FMarks.NamesWithin(AControl);
  if (Length(mNames) = 0) and FAttached.TryGetValue(AControl, mAnchor) then
  begin
    mNames := FMarks.NamesWithin(mAnchor);
  end;
  for mSetting in mNames do
  begin
    mLock := LockOfName(mSetting);
    if not mLock.Locked then
    begin
      Continue;
    end;
    Result := True;
    if mLock.Reason = lrMasterOff then
    begin
      AddUnique(AOutside, LockText(mLock));
    end;
  end;
end;

procedure TDpccSettingsPageTree.ApplyLocks(AContainer: TWinControl; ALocked: Boolean; var AOutside: TArray<string>);
var
  mIndex: Integer;
  mControl: TControl;
  mFrame: TDpccSettingsGroup;
begin
  for mIndex := 0 to AContainer.ControlCount - 1 do
  begin
    mControl := AContainer.Controls[mIndex];
    if (AContainer is TDpccSettingsGroup) and ((mControl = TDpccSettingsGroup(AContainer).Master) or
      (mControl = TDpccSettingsGroup(AContainer).Reason)) then
    begin
      Continue;
    end;
    if mControl is TDpccSettingsGroup then
    begin
      mFrame := TDpccSettingsGroup(mControl);
      if not IsOverview(mFrame) and (mFrame.Master <> nil) then
      begin
        ApplyFrameLocks(mFrame, ALocked, AOutside);
      end;
    end
    else
    begin
      SetLocked(mControl, ALocked or RowLocked(mControl, AOutside));
    end;
  end;
end;

function TDpccSettingsPageTree.PageGray(AIndex: Integer): Boolean;
var
  mBox: TScrollBox;
  mIndex: Integer;
  mControl: TControl;
  mFrame: TDpccSettingsGroup;
  mAny: Boolean;
begin
  // Grau, wenn nichts auf der Seite wirkt: jeder Rahmen aus oder gesperrt, jede übrige Einstellung gesperrt.
  mBox := FNodePages[AIndex].Box;
  mAny := False;
  for mIndex := 0 to mBox.ControlCount - 1 do
  begin
    mControl := mBox.Controls[mIndex];
    if ViewHides(mControl) then
    begin
      Continue;
    end;
    if mControl is TDpccSettingsGroup then
    begin
      mFrame := TDpccSettingsGroup(mControl);
      if IsOverview(mFrame) or (mFrame.Master = nil) then
      begin
        Continue;
      end;
      mAny := True;
      if mFrame.Master.Enabled and IsOn(mFrame.MasterName) then
      begin
        Exit(False);
      end;
    end
    else if Length(FMarks.NamesWithin(mControl)) > 0 then
    begin
      mAny := True;
      if mControl.Enabled then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := mAny;
end;

procedure TDpccSettingsPageTree.UpdateLocks;
var
  mIndex: Integer;
  mOutside: TArray<string>;
begin
  if FGroups = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FNodePages) do
  begin
    mOutside := nil;
    ApplyLocks(FNodePages[mIndex].Box, False, mOutside);
    FNodePages[mIndex].Banner.Caption := string.Join(sLineBreak, mOutside);
    FNodePages[mIndex].Banner.Visible := Length(mOutside) > 0;
  end;
  // Spiegel in der Übersicht folgen ihrem Hauptschalter.
  FSyncing := True;
  try
    for mIndex := 0 to High(FMirrors) do
    begin
      FMirrors[mIndex].Checked := FMirrored[mIndex].Checked;
      FMirrors[mIndex].Enabled := FMirrored[mIndex].Enabled;
    end;
  finally
    FSyncing := False;
  end;
  for mIndex := 0 to High(FNodePages) do
  begin
    FNodePages[mIndex].Gray := PageGray(mIndex);
  end;
  RefreshTree;
end;

function TDpccSettingsPageTree.SheetGray(ASheet: TTabSheet): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FNodePages) do
  begin
    if FNodePages[mIndex].Sheet = ASheet then
    begin
      Exit(FNodePages[mIndex].Gray);
    end;
  end;
  Result := False;
end;

class procedure TDpccSettingsPageTree.ForgetTreeState;
begin
  FStateKnown := False;
  FLastPage := 0;
  FExpandedAreas := [];
end;

end.
