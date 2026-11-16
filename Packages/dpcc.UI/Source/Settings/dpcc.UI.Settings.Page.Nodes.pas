unit dpcc.UI.Settings.Page.Nodes;

// Knoten der Optionsseite „dpcc“ (#890): verteilt die Zeilen jedes Bereichs auf Unterpunkte (x-nodes) und Rahmen
// der Hauptschalter, baut die Übersicht der Hauptknoten und hält die Seiten der Knoten mit ihren Reitern.

interface

uses
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  dpcc.Core.Settings.Groups,
  dpcc.UI.Settings.Group,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Seite eines Knotens im Baum (#890): der Bereich selbst (Node leer) oder ein Unterpunkt.</summary>
  TDpccSettingsNodePage = record
    Sheet: TTabSheet;
    Box: TScrollBox;
    /// <summary>Index des Bereichs in FSheets.</summary>
    Area: Integer;
    /// <summary>Id aus x-nodes; leer = Hauptknoten des Bereichs.</summary>
    Node: string;
    Caption: string;
    /// <summary>Grund einer Sperre durch einen Hauptschalter auf einer anderen Seite.</summary>
    Banner: TLabel;
    /// <summary>Im Baum grau: nichts auf der Seite wirkt (aus oder gesperrt).</summary>
    Gray: Boolean;
  end;

  TDpccSettingsPageNodes = class(TDpccSettingsPageHost)
  protected
    FPages: TPageControl;
    FGroups: TDpccSettingsGroups;
    FNodePages: TArray<TDpccSettingsNodePage>;
    /// <summary>Spiegel der Hauptschalter in der Übersicht und ihr Original, gleicher Index.</summary>
    FMirrors: TArray<TCheckBox>;
    FMirrored: TArray<TCheckBox>;
    FSyncing: Boolean;
    /// <summary>Zeilen der Übersichten und der Rahmen, auf den jede zeigt, gleicher Index (#1903).</summary>
    FOverviewRows: TArray<TControl>;
    FOverviewFrames: TArray<TDpccSettingsGroup>;
    /// <summary>Rahmen „Funktionen in diesem Bereich“ auf den Hauptknoten.</summary>
    FOverviews: TArray<TDpccSettingsGroup>;
    /// <summary>Reiter der Knoten rechts vom Baum.</summary>
    procedure AddPages;
    /// <summary>Verteilt die Zeilen aller Bereiche auf Knoten und Rahmen (aus dem Schema).</summary>
    procedure BuildNodes;
    function IsOverview(AFrame: TDpccSettingsGroup): Boolean;
  private
    FFrames: TArray<TDpccSettingsGroup>;
    FPlaceTop: Integer;
    /// <summary>Seite des Knotens ANode im Bereich AArea; legt sie bei Bedarf an.</summary>
    function AddNodePage(AArea: Integer; const ANode: string): Integer;
    function AddNodePageCaption(AArea: Integer; const ANode, ACaption: string): Integer;
    procedure Place(AControl: TControl; AHolder: TWinControl);
    procedure BuildArea(AArea: Integer);
    procedure AddOverview(AArea: Integer);
    /// <summary>Rahmen „Funktionen in diesem Bereich“ oben auf der Seite AMain.</summary>
    function NewOverview(AMain: Integer): TDpccSettingsGroup;
    /// <summary>Zeile der Übersicht zum Rahmen AFrame: Spiegel des Hauptschalters und „Details“ zur Seite APage.
    /// </summary>
    procedure AddOverviewRow(AOverview, AFrame: TDpccSettingsGroup; APage: Integer);
    procedure MirrorClick(Sender: TObject);
    procedure DetailsClick(Sender: TObject);
  public
    destructor Destroy; override;
    function PageOf(AControl: TControl): Integer; override;
    function NodeBox(AArea: Integer; const ANode, ACaption: string): TScrollBox; override;
    /// <summary>Zum Testen: Rahmen des Hauptschalters AName (Registry-Name); nil ohne Rahmen.</summary>
    function FrameOf(const AName: string): TDpccSettingsGroup;
    /// <summary>Zum Testen: Reiter des Unterpunkts ANode (Id aus x-nodes).</summary>
    function NodeSheet(const ANode: string): TTabSheet;
    /// <summary>Zum Testen: Spiegel des Hauptschalters AName in der Übersicht seines Bereichs.</summary>
    function OverviewMirror(const AName: string): TCheckBox;
    /// <summary>Id des Unterpunkts zu ASheet; leer beim Hauptknoten.</summary>
    function NodeOfSheet(ASheet: TTabSheet): string;
    /// <summary>Reiter der Seite, einer je Bereich (#227).</summary>
    property Pages: TPageControl read FPages;
    property Groups: TDpccSettingsGroups read FGroups;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Vcl.Graphics,
  Vcl.Themes,
  dpcc.UI.Strings,
  dpcc.UI.Settings.Strings,
  dpcc.UI.Settings.Page.Sheets;

type
  /// <summary>Art einer Zeile beim Aufteilen eines Bereichs: mit Einstellung, angehängt, Beschriftung, sonst.
  /// </summary>
  TDpccRowKind = (rkBound, rkAttached, rkLabel, rkOther);

/// <summary>Liegt AControl in AParent (oder ist es selbst)?</summary>
function Inside(AControl, AParent: TControl): Boolean;
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

/// <summary>Zeilen von ABox in der Reihenfolge von oben nach unten.</summary>
function SortedRows(ABox: TWinControl): TArray<TControl>;
var
  mIndex, mPosition: Integer;
  mControl: TControl;
begin
  Result := nil;
  for mIndex := 0 to ABox.ControlCount - 1 do
  begin
    mControl := ABox.Controls[mIndex];
    mPosition := Length(Result);
    while (mPosition > 0) and (Result[mPosition - 1].Top > mControl.Top) do
    begin
      Dec(mPosition);
    end;
    Insert(mControl, Result, mPosition);
  end;
end;

/// <summary>Zeile nur mit einer Beschriftung (Überschrift, Hinweis, Beschriftung über einem Textfeld).</summary>
function IsLabelRow(AControl: TControl): Boolean;
begin
  Result := (AControl is TDpccSettingsRow) and (TWinControl(AControl).ControlCount = 1) and
    (TWinControl(AControl).Controls[0] is TLabel);
end;

type
  /// <summary>Verteilt die Zeilen eines Bereichs auf die Seiten seiner Knoten und ihre Behälter (Seite oder Rahmen
  /// des Hauptschalters). Gleicher Index in allen Feldern: eine Zeile des Bereichs von oben nach unten.</summary>
  TDpccSettingsAreaLayout = class
  private
    FPage: TDpccSettingsPageNodes;
    FArea: Integer;
    FMain: Integer;
    FRows: TArray<TControl>;
    FKinds: TArray<TDpccRowKind>;
    FNames: TArray<string>;
    FRowPages: TArray<Integer>;
    FHolders: TArray<TWinControl>;
    FFrames: TArray<TDpccSettingsGroup>;
    FResolved: TArray<Boolean>;
    /// <summary>Erster Name der Zeile, den der Katalog kennt; '' ohne Einstellung.</summary>
    function KnownName(AControl: TControl): string;
    /// <summary>Hängt eine Zeile an einem Element in AControl (Liste und Knöpfe einer Funktion)?</summary>
    function HasAttached(AControl: TControl): Boolean;
    function RowOfAnchor(AAnchor: TControl): Integer;
    /// <summary>Rahmen des Hauptschalters AName, wenn er auf der Seite APage steht; sonst nil.</summary>
    function FrameFor(const AName: string; APage: Integer): TDpccSettingsGroup;
    function KindOf(AIndex: Integer): TDpccRowKind;
    /// <summary>Gleiche Seite und gleicher Behälter wie die Zeile AOther.</summary>
    procedure Follow(AIndex, AOther: Integer);
    procedure Classify;
    procedure AddFrames;
    procedure PlaceBound;
    procedure PlaceAttached;
    procedure PlaceOthers;
    procedure PlaceLabels;
    procedure PlaceRows;
  public
    constructor Create(APage: TDpccSettingsPageNodes; AArea: Integer);
    procedure Run;
  end;

{ TDpccSettingsAreaLayout }

constructor TDpccSettingsAreaLayout.Create(APage: TDpccSettingsPageNodes; AArea: Integer);
begin
  inherited Create;
  FPage := APage;
  FArea := AArea;
end;

function TDpccSettingsAreaLayout.KnownName(AControl: TControl): string;
var
  mCandidate: string;
begin
  Result := '';
  for mCandidate in FPage.Marks.NamesWithin(AControl) do
  begin
    if FPage.FGroups.Contains(mCandidate) then
    begin
      Exit(mCandidate);
    end;
  end;
end;

function TDpccSettingsAreaLayout.HasAttached(AControl: TControl): Boolean;
var
  mItem: TPair<TControl, TControl>;
begin
  for mItem in FPage.FAttached do
  begin
    if Inside(mItem.Value, AControl) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDpccSettingsAreaLayout.RowOfAnchor(AAnchor: TControl): Integer;
var
  mCandidate: Integer;
begin
  for mCandidate := 0 to High(FRows) do
  begin
    if Inside(AAnchor, FRows[mCandidate]) then
    begin
      Exit(mCandidate);
    end;
  end;
  Result := -1;
end;

function TDpccSettingsAreaLayout.FrameFor(const AName: string; APage: Integer): TDpccSettingsGroup;
var
  mCandidate: Integer;
begin
  Result := nil;
  if AName = '' then
  begin
    Exit;
  end;
  for mCandidate := 0 to High(FRows) do
  begin
    if (FFrames[mCandidate] <> nil) and (FRowPages[mCandidate] = APage) and SameText(FNames[mCandidate], AName) then
    begin
      Exit(FFrames[mCandidate]);
    end;
  end;
end;

function TDpccSettingsAreaLayout.KindOf(AIndex: Integer): TDpccRowKind;
begin
  Result := rkOther;
  if FNames[AIndex] <> '' then
  begin
    Result := rkBound;
  end
  else if FPage.FAttached.ContainsKey(FRows[AIndex]) then
  begin
    Result := rkAttached;
  end
  else if IsLabelRow(FRows[AIndex]) then
  begin
    Result := rkLabel;
  end;
end;

procedure TDpccSettingsAreaLayout.Follow(AIndex, AOther: Integer);
begin
  FRowPages[AIndex] := FRowPages[AOther];
  FHolders[AIndex] := FHolders[AOther];
  FResolved[AIndex] := True;
end;

procedure TDpccSettingsAreaLayout.Classify;
var
  mIndex: Integer;
begin
  FRows := SortedRows(FPage.Boxes[FArea]);
  FMain := FPage.AddNodePage(FArea, '');
  SetLength(FKinds, Length(FRows));
  SetLength(FNames, Length(FRows));
  SetLength(FRowPages, Length(FRows));
  SetLength(FHolders, Length(FRows));
  SetLength(FFrames, Length(FRows));
  SetLength(FResolved, Length(FRows));
  for mIndex := 0 to High(FRows) do
  begin
    FNames[mIndex] := KnownName(FRows[mIndex]);
    FRowPages[mIndex] := FMain;
    FHolders[mIndex] := FPage.FNodePages[FMain].Box;
    FFrames[mIndex] := nil;
    FResolved[mIndex] := False;
    FKinds[mIndex] := KindOf(mIndex);
  end;
end;

procedure TDpccSettingsAreaLayout.AddFrames;
var
  mIndex: Integer;
begin
  // Unterpunkt jeder Einstellung; Hauptschalter (auch Kontrollkästchen mit angehängter Liste) bekommen einen Rahmen.
  for mIndex := 0 to High(FRows) do
  begin
    if FKinds[mIndex] <> rkBound then
    begin
      Continue;
    end;
    FRowPages[mIndex] := FPage.AddNodePage(FArea, FPage.FGroups.NodeOf(FNames[mIndex]));
    if FPage.FGroups.IsMaster(FNames[mIndex]) or ((FRows[mIndex] is TCheckBox) and HasAttached(FRows[mIndex])) then
    begin
      FFrames[mIndex] := TDpccSettingsGroup.Create(FPage);
      FPage.FFrames := FPage.FFrames + [FFrames[mIndex]];
    end;
  end;
end;

procedure TDpccSettingsAreaLayout.PlaceBound;
var
  mIndex: Integer;
  mFrame: TDpccSettingsGroup;
begin
  // Behälter: der Rahmen des Hauptschalters auf derselben Seite, sonst die Seite selbst.
  for mIndex := 0 to High(FRows) do
  begin
    if FKinds[mIndex] = rkBound then
    begin
      FHolders[mIndex] := FPage.FNodePages[FRowPages[mIndex]].Box;
      mFrame := FrameFor(FPage.FGroups.ParentOf(FNames[mIndex]), FRowPages[mIndex]);
      if mFrame <> nil then
      begin
        FHolders[mIndex] := mFrame;
      end;
      FResolved[mIndex] := True;
    end;
  end;
end;

procedure TDpccSettingsAreaLayout.PlaceAttached;
var
  mIndex, mOther: Integer;
begin
  // Zeilen ohne eigene Einstellung, die zu einer gehören (Liste, Knöpfe): in deren Rahmen.
  for mIndex := 0 to High(FRows) do
  begin
    if FKinds[mIndex] <> rkAttached then
    begin
      Continue;
    end;
    mOther := RowOfAnchor(FPage.FAttached[FRows[mIndex]]);
    if (mOther >= 0) and FResolved[mOther] then
    begin
      Follow(mIndex, mOther);
      if FFrames[mOther] <> nil then
      begin
        FHolders[mIndex] := FFrames[mOther];
      end;
    end;
  end;
end;

procedure TDpccSettingsAreaLayout.PlaceOthers;
var
  mIndex, mPage: Integer;
begin
  // Übrige Zeilen (Pfadfelder, Knöpfe des Bereichs): oben auf der Seite der Zeile davor.
  mPage := FMain;
  for mIndex := 0 to High(FRows) do
  begin
    if FResolved[mIndex] then
    begin
      mPage := FRowPages[mIndex];
    end
    else if FKinds[mIndex] <> rkLabel then
    begin
      FRowPages[mIndex] := mPage;
      FHolders[mIndex] := FPage.FNodePages[mPage].Box;
      FResolved[mIndex] := True;
    end;
  end;
end;

procedure TDpccSettingsAreaLayout.PlaceLabels;
var
  mIndex: Integer;
begin
  // Überschriften und Beschriftungen gehören zur Zeile darunter, am Ende des Bereichs zur Zeile darüber.
  for mIndex := High(FRows) downto 0 do
  begin
    if not FResolved[mIndex] and (mIndex < High(FRows)) and FResolved[mIndex + 1] then
    begin
      Follow(mIndex, mIndex + 1);
    end;
  end;
  for mIndex := 1 to High(FRows) do
  begin
    if not FResolved[mIndex] then
    begin
      Follow(mIndex, mIndex - 1);
    end;
  end;
end;

procedure TDpccSettingsAreaLayout.PlaceRows;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FRows) do
  begin
    if FFrames[mIndex] = nil then
    begin
      FPage.Place(FRows[mIndex], FHolders[mIndex]);
      Continue;
    end;
    FPage.Place(FFrames[mIndex], FHolders[mIndex]);
    FFrames[mIndex].SetMaster(FRows[mIndex], FNames[mIndex]);
    // Rahmen, Hauptschalter und Grund der Sperre bleiben beim Filtern stehen.
    FPage.Marks.Pin(FFrames[mIndex]);
    FPage.Marks.Pin(FRows[mIndex]);
    FPage.Marks.Pin(FFrames[mIndex].Reason);
  end;
end;

procedure TDpccSettingsAreaLayout.Run;
begin
  Classify;
  AddFrames;
  PlaceBound;
  PlaceAttached;
  PlaceOthers;
  PlaceLabels;
  PlaceRows;
end;

{ TDpccSettingsPageNodes }

destructor TDpccSettingsPageNodes.Destroy;
begin
  // Elemente melden beim Abbau nichts mehr (csDestroying); danach fragt keine Sperre mehr die Gruppen.
  Destroying;
  FreeAndNil(FGroups);
  inherited Destroy;
end;

procedure TDpccSettingsPageNodes.AddPages;
begin
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.AlignWithMargins := True;
  FPages.Top := FPages.ScaleValue(100);
end;

function TDpccSettingsPageNodes.AddNodePage(AArea: Integer; const ANode: string): Integer;
begin
  if ANode = '' then
  begin
    Result := AddNodePageCaption(AArea, ANode, '');
  end
  else
  begin
    Result := AddNodePageCaption(AArea, ANode,
      FGroups.NodeCaption(ANode, TDpccStrings.Language = TDpccLanguage.English));
  end;
end;

function TDpccSettingsPageNodes.NodeBox(AArea: Integer; const ANode, ACaption: string): TScrollBox;
begin
  Result := FNodePages[AddNodePageCaption(AArea, ANode, ACaption)].Box;
end;

function TDpccSettingsPageNodes.AddNodePageCaption(AArea: Integer; const ANode, ACaption: string): Integer;
var
  mPage: TDpccSettingsNodePage;
  mIndex: Integer;
begin
  for mIndex := 0 to High(FNodePages) do
  begin
    if (FNodePages[mIndex].Area = AArea) and SameText(FNodePages[mIndex].Node, ANode) then
    begin
      Exit(mIndex);
    end;
  end;
  mPage := Default(TDpccSettingsNodePage);
  mPage.Area := AArea;
  mPage.Node := ANode;
  if ANode = '' then
  begin
    mPage.Sheet := FSheets[AArea];
    mPage.Box := FBoxes[AArea];
    mPage.Caption := FSheets[AArea].Caption;
  end
  else
  begin
    mPage.Caption := ACaption;
    mPage.Sheet := TTabSheet.Create(Self);
    mPage.Sheet.Caption := mPage.Caption;
    mPage.Box := TScrollBox.Create(Self);
    mPage.Box.Parent := mPage.Sheet;
    mPage.Box.Align := alClient;
    mPage.Box.BorderStyle := bsNone;
    mPage.Box.ParentBackground := True;
    mPage.Box.VertScrollBar.Tracking := True;
    mPage.Box.HorzScrollBar.Visible := False;
  end;
  // Hinweis auf eine Sperre durch einen Hauptschalter auf einer anderen Seite, immer ganz oben.
  mPage.Banner := TLabel.Create(Self);
  mPage.Banner.Parent := mPage.Box;
  mPage.Banner.Align := alTop;
  mPage.Banner.AlignWithMargins := True;
  mPage.Banner.Top := 0;
  mPage.Banner.WordWrap := True;
  mPage.Banner.ShowAccelChar := False;
  mPage.Banner.Font.Style := [fsItalic];
  mPage.Banner.Visible := False;
  FMarks.Pin(mPage.Banner);
  FNodePages := FNodePages + [mPage];
  Result := High(FNodePages);
end;

procedure TDpccSettingsPageNodes.Place(AControl: TControl; AHolder: TWinControl);
begin
  if AHolder is TDpccSettingsGroup then
  begin
    TDpccSettingsGroup(AHolder).AddRow(AControl);
  end
  else
  begin
    AControl.Parent := AHolder;
    AControl.Align := alTop;
    AControl.AlignWithMargins := True;
    // alTop ordnet nach Top: jede Zeile unter die vorige.
    AControl.Top := FPlaceTop;
    Inc(FPlaceTop, 100);
  end;
end;

procedure TDpccSettingsPageNodes.BuildNodes;
var
  mArea: Integer;
  mFrame: TDpccSettingsGroup;
  mPart: TDpccSettingsPagePart;
begin
  FGroups := TDpccSettingsGroups.Create(Catalog);
  for mArea := 0 to High(FSheets) do
  begin
    BuildArea(mArea);
  end;
  for mPart in FParts do
  begin
    mPart.AddNodePages;
  end;
  for mFrame in FFrames do
  begin
    if not (mFrame.Parent is TDpccSettingsGroup) then
    begin
      mFrame.AdjustHeight;
    end;
  end;
  for mArea := 0 to High(FSheets) do
  begin
    AddOverview(mArea);
  end;
end;

procedure TDpccSettingsPageNodes.BuildArea(AArea: Integer);
var
  mLayout: TDpccSettingsAreaLayout;
begin
  FPlaceTop := 1000;
  mLayout := TDpccSettingsAreaLayout.Create(Self, AArea);
  try
    mLayout.Run;
  finally
    mLayout.Free;
  end;
end;

function TDpccSettingsPageNodes.NewOverview(AMain: Integer): TDpccSettingsGroup;
var
  mCaption: TLabel;
begin
  Result := TDpccSettingsGroup.Create(Self);
  FPlaceTop := 100000;
  Place(Result, FNodePages[AMain].Box);
  // Überschrift im Stil des Hovers (Großbuchstaben, fett, gedämpft); die Linie zeichnet der Rahmen oben.
  mCaption := TLabel.Create(Self);
  mCaption.Caption := AnsiUpperCase(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsOverviewTitle));
  mCaption.Font.Style := [fsBold];
  mCaption.StyleElements := mCaption.StyleElements - [seFont];
  mCaption.Font.Color := StyleServices.GetSystemColor(clGrayText);
  Result.SetMaster(mCaption, '');
  FOverviews := FOverviews + [Result];
  FMarks.Pin(Result);
end;

procedure TDpccSettingsPageNodes.AddOverviewRow(AOverview, AFrame: TDpccSettingsGroup; APage: Integer);
var
  mRow: TWinControl;
  mDetails, mCaption: TLabel;
  mMirror: TCheckBox;
begin
  mRow := TDpccSettingsRow.Create(Self);
  mRow.Height := mRow.ScaleValue(24);
  AOverview.AddRow(mRow);
  FOverviewRows := FOverviewRows + [mRow];
  FOverviewFrames := FOverviewFrames + [AFrame];
  mDetails := TLabel.Create(Self);
  mDetails.Parent := mRow;
  mDetails.Align := alRight;
  mDetails.AlignWithMargins := True;
  mDetails.Layout := tlCenter;
  mDetails.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsOverviewDetails);
  mDetails.Font.Style := [fsUnderline];
  // Verweisfarbe aus dem IDE-Thema (hell und dunkel), keine eigene Farbe.
  mDetails.Font.Color := StyleServices.GetSystemColor(clHotLight);
  mDetails.Cursor := crHandPoint;
  mDetails.Tag := APage;
  mDetails.OnClick := DetailsClick;
  if AFrame.Master is TCheckBox then
  begin
    mMirror := TCheckBox.Create(Self);
    mMirror.Parent := mRow;
    mMirror.Align := alClient;
    mMirror.Caption := FMarks.TextOfName(AFrame.MasterName);
    mMirror.Tag := Length(FMirrors);
    mMirror.OnClick := MirrorClick;
    FMirrors := FMirrors + [mMirror];
    FMirrored := FMirrored + [TCheckBox(AFrame.Master)];
  end
  else
  begin
    mCaption := TLabel.Create(Self);
    mCaption.Parent := mRow;
    mCaption.Align := alClient;
    mCaption.Layout := tlCenter;
    mCaption.Caption := FMarks.TextOfName(AFrame.MasterName);
  end;
end;

procedure TDpccSettingsPageNodes.AddOverview(AArea: Integer);
var
  mOverview, mFrame: TDpccSettingsGroup;
  mMain, mIndex, mChild: Integer;
  mBox: TScrollBox;
begin
  // Hauptknoten: je Hauptschalter der Unterpunkte eine Zeile mit Spiegel und „Details“.
  mMain := AddNodePage(AArea, '');
  mOverview := nil;
  for mIndex := 0 to High(FNodePages) do
  begin
    if (FNodePages[mIndex].Area <> AArea) or (FNodePages[mIndex].Node = '') then
    begin
      Continue;
    end;
    mBox := FNodePages[mIndex].Box;
    for mChild := 0 to mBox.ControlCount - 1 do
    begin
      if not (mBox.Controls[mChild] is TDpccSettingsGroup) or
        (TDpccSettingsGroup(mBox.Controls[mChild]).Master = nil) then
      begin
        Continue;
      end;
      mFrame := TDpccSettingsGroup(mBox.Controls[mChild]);
      if mOverview = nil then
      begin
        mOverview := NewOverview(mMain);
      end;
      AddOverviewRow(mOverview, mFrame, mIndex);
    end;
  end;
  if mOverview <> nil then
  begin
    mOverview.AdjustHeight;
  end;
end;

procedure TDpccSettingsPageNodes.MirrorClick(Sender: TObject);
var
  mIndex: Integer;
begin
  if FSyncing or not (Sender is TCheckBox) then
  begin
    Exit;
  end;
  mIndex := TCheckBox(Sender).Tag;
  if (mIndex >= 0) and (mIndex <= High(FMirrored)) then
  begin
    FMirrored[mIndex].Checked := TCheckBox(Sender).Checked;
  end;
end;

procedure TDpccSettingsPageNodes.DetailsClick(Sender: TObject);
begin
  if Sender is TControl then
  begin
    SelectPage(TControl(Sender).Tag);
  end;
end;

function TDpccSettingsPageNodes.IsOverview(AFrame: TDpccSettingsGroup): Boolean;
var
  mOverview: TDpccSettingsGroup;
begin
  for mOverview in FOverviews do
  begin
    if mOverview = AFrame then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TDpccSettingsPageNodes.PageOf(AControl: TControl): Integer;
var
  mParent: TControl;
  mIndex: Integer;
begin
  Result := -1;
  mParent := AControl;
  while (mParent <> nil) and not (mParent is TTabSheet) do
  begin
    mParent := mParent.Parent;
  end;
  if mParent = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FNodePages) do
  begin
    if FNodePages[mIndex].Sheet = mParent then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TDpccSettingsPageNodes.FrameOf(const AName: string): TDpccSettingsGroup;
var
  mFrame: TDpccSettingsGroup;
begin
  for mFrame in FFrames do
  begin
    if SameText(mFrame.MasterName, AName) then
    begin
      Exit(mFrame);
    end;
  end;
  Result := nil;
end;

function TDpccSettingsPageNodes.NodeSheet(const ANode: string): TTabSheet;
var
  mPage: TDpccSettingsNodePage;
begin
  for mPage in FNodePages do
  begin
    if (ANode <> '') and SameText(mPage.Node, ANode) then
    begin
      Exit(mPage.Sheet);
    end;
  end;
  Result := nil;
end;

function TDpccSettingsPageNodes.OverviewMirror(const AName: string): TCheckBox;
var
  mFrame: TDpccSettingsGroup;
  mIndex: Integer;
begin
  Result := nil;
  mFrame := FrameOf(AName);
  if mFrame = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FMirrored) do
  begin
    if FMirrored[mIndex] = mFrame.Master then
    begin
      Exit(FMirrors[mIndex]);
    end;
  end;
end;

function TDpccSettingsPageNodes.NodeOfSheet(ASheet: TTabSheet): string;
var
  mPage: TDpccSettingsNodePage;
begin
  for mPage in FNodePages do
  begin
    if mPage.Sheet = ASheet then
    begin
      Exit(mPage.Node);
    end;
  end;
  Result := '';
end;

end.
