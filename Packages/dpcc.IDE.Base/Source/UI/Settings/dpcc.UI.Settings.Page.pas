unit dpcc.UI.Settings.Page;

// Seite „dpcc“ unter Tools › Optionen › Drittanbieter (#227). Reine VCL, im Code aufgebaut: Reiter je
// Bereich, darin Steuerelemente untereinander; die IDE skaliert sie mit dem Dialog. Die DFM ist leer;
// TCustomFrame.Create verlangt für abgeleitete Frames eine Ressource. Laden und Speichern über
// TDpccPluginSettings; die IDE-Schicht liest und schreibt die Registry.
// Die Tastenkürzel von Befehlspalette und Prüfung stehen auf der eigenen Seite „Tastenkonflikte“
// (dpcc.UI.Settings.Keys, #494). Den Reiter „Robustheit“ gibt es seit S3 nicht mehr: Was die Sicherung nach
// wiederholten Fehlern abschaltet (#493), bleibt bis zum Neustart der IDE aus.
// Den Reiter „Index“ (Umfang, Verwendungen, Speichergrenze, Kennzahlen, Befehle an den Server) gibt es seit S4 nicht
// mehr; auf „Allgemein“ steht nur „Index neu aufbauen“ (OnRebuildIndex, die IDE-Schicht führt es aus). Die Seite
// kennt den Server nicht und startet ihn nicht.
// Im Seitenkopf steht seit S3 nur der Titel (ohne Symbol).
// Jeder Reiter bleibt niedriger als die Seite: Sonst scrollt die IDE ihren Bereich beim Reiterwechsel
// zum Fokus, und die Seite „springt“.
// Reiter Vervollständigung: angeheftete Favoriten (#458) an/aus, Liste („TDataSet.Open“) mit „Entfernen“
// und „Alle entfernen“. Die Seite kennt die Ablage nicht; OnFavorites liefert die Liste, OnRemoveFavorites
// löst die Schlüssel sofort (nicht erst mit OK).
// Reveal (#628, „Einstellungen dazu …“ am gezeichneten Element): wählt den Reiter einer Einstellung über ihren
// Schlüssel (Name der Plugin-Einstellung), rollt sie ins Bild, setzt den Fokus und hebt die Zeile fett hervor.
// Bereich Prüfregeln (#909): Unterknoten „Prüffenster“ (problems.window*, problems.live) und „Compiler vorab“
// (problems.compilerMerge, problems.showCompilerCode). Den Weg zu den Regeln (Dialoge der Einstellungsdateien
// mit einem Knoten je Gruppe), Profile, Baseline und Unterdrückungen baut das Modul Prüfregeln als Abschnitt
// (#1755).
// Bereich Versionsverwaltung (#1285): Art (vcs.provider), Programme git und svn mit eigenem Pfad, „…“ und
// „Prüfen“ (Version und Fundort, im Hintergrund über OnVcsCheck), Zeitlimit je Aufruf und „Aktuelles Projekt“
// (beim ersten Zeigen der Seite einmal im Hintergrund abgefragt, OnVcsProject); Links auf die Seiten, die die
// Anzeige steuern. Ohne Klick startet kein Prozess: Beim Öffnen zeigt OnVcsLocate nur, welche Datei gälte.
// Bereich Issue-Tracker (#1280): nur der Modulschalter; Tracker, Abfrage, Start-Optionen, Muster und Zugang
// (issues.*) baut das Modul Tracker als Abschnitt (#1455). Auf der Willkommensseite bleibt nur die Sektion an/aus
// mit dem Sprung „Tracker-Einstellungen …“.
// Abschnitte der Module (#1455): Jeder IDpccSettingsSectionProvider der Registry liefert
// der Seite einen eigenen Abschnitt, den sie in den Reiter seines Bereichs baut (Bausteine über
// IDpccSettingsSectionHost). Geht ein Modul, schließt die Seite seinen Abschnitt; seine Werte bleiben erhalten.
// Suchfeld über dem Baum (#1884, settings.search): Treffer dieses Knotens zeigt die Seite selbst (Reveal), Treffer
// anderer Knoten öffnet OnOpenSetting (die IDE-Schicht springt im offenen Dialog zum Knoten).
// Completion-Schnitt: Nach dem Aufbau blendet ApplyView aus, was dpcc.Core.Settings.CompletionView nicht mehr zeigt;
// die Suche findet nur, was hier sichtbar steht, und die Einstellungen der Seite „Tastenkonflikte“ (die Seite
// „Server“ gibt es seit S2 nicht mehr).
// Seit S7a baut die Seite die Teile ohne sichtbare Einstellung nicht mehr (Build, Farben, Befehle, EditorCode,
// Prüfregeln, Start, Export/Import, Benachrichtigungen) und keine Abschnitte der Module: Es gab keine Module, die
// welche anmelden. Was die Kommentare oben zu diesen Bereichen sagen, ist Geschichte.

interface

uses
  System.Classes,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.Forms,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.Search,
  dpcc.UI.Settings.ChoiceBox,
  dpcc.UI.Settings.Page.Tree,
  dpcc.UI.Settings.Page.Search;

type
  TDpccSettingsPage = class(TDpccSettingsPageTree)
  private
    FTitle: TLabel;
    FWidths: TDpccPluginSettings;
    /// <summary>Reveal vor dem Fenster: folgt in CreateWnd.</summary>
    FPendingReveal: string;
    FExperimentalBanner: TWinControl;
    FFilterRow: TWinControl;
    FFilter: TDpccChoiceBox;
    FOnOpenSetting: TProc<string, string>;
    procedure ApplyReveal(const AKey: string);
    /// <summary>AControl oder, wenn ein Hauptschalter es sperrt, dieser Schalter.</summary>
    function RevealTarget(AControl: TControl): TControl;
    procedure ExperimentalAllowClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure SearchOpen(AHit: TDpccSettingHit);
    /// <summary>Kopf mit Titel.</summary>
    procedure AddHeader;
    /// <summary>Kopfzeile mit Hinweis und Knopf „Erlauben“, solange experimental.enabled aus ist (#834).</summary>
    procedure AddExperimentalBanner;
    /// <summary>Zeile unten mit dem Filter Alle / Geändert / Nur experimentelle (#834).</summary>
    procedure AddFilterRow;
    procedure LoadControls(const ASettings: TDpccPluginSettings);
    /// <summary>Bindet die Elemente an ihre Einstellungen (Punkt, Kontextmenü, Zurücksetzen je Seite).</summary>
    procedure BindControls;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Werte der Seite (ungespeichert) über den zuletzt geladenen.</summary>
    function CurrentSettings: TDpccPluginSettings; override;
    /// <summary>Punkte an geänderten Werten und Knöpfe neu setzen (#723).</summary>
    procedure RefreshMarks; override;
    /// <summary>Einstellungen ANames (Registry-Namen) auf der Seite auf den Standard setzen; gespeichert wird
    /// erst mit OK (#723).</summary>
    procedure ResetNames(const ANames: TArray<string>); override;
    /// <summary>Alle Einstellungen des sichtbaren Reiters auf den Standard setzen (#723).</summary>
    procedure ResetPage; override;
    procedure LoadFrom(const ASettings: TDpccPluginSettings); override;
    procedure SaveTo(var ASettings: TDpccPluginSettings);
    /// <summary>Zeigt die Einstellung AKey (Name der Plugin-Einstellung, #628): Reiter, ins Bild rollen, Fokus,
    /// Zeile fett. False, wenn die Seite den Schlüssel nicht kennt; ohne Fenster folgt es in CreateWnd.</summary>
    function Reveal(const AKey: string): Boolean; override;
    /// <summary>Zum Testen: Zahl der Reiter (Bereiche).</summary>
    function SheetCountForTests: Integer;
    /// <summary>Überschrift im Kopf (#1903: Name des Knotens, z. B. „Base“ oder „Tests“).</summary>
    procedure SetTitle(const ACaption: string);
    property ExperimentalBanner: TWinControl read FExperimentalBanner;
    property Filter: TDpccChoiceBox read FFilter;
    /// <summary>Treffer der Suche in einem anderen Knoten: Einstellung (Name) und Modulschalter ('' = Base).
    /// </summary>
    property OnOpenSetting: TProc<string, string> read FOnOpenSetting write FOnOpenSetting;
    /// <summary>Suchfeld über dem Baum (#1884).</summary>
    property Search: TDpccSettingsSearchBox read FSearch;
  end;

implementation

{$R *.dfm}

uses
  dpcc.Core.Settings.Transfer,
  dpcc.Core.Settings.Experimental,
  dpcc.Core.Settings.History,
  dpcc.Core.Settings.Groups,
  dpcc.Core.Settings.CompletionView,
  dpcc.UI.Settings.Page.Sheets,
  dpcc.UI.Settings.Page.Host,
  dpcc.UI.Settings.Page.Nodes,
  dpcc.UI.Settings.Page.Parts,
  dpcc.UI.Settings.Page.General,
  dpcc.UI.Settings.Marks,
  dpcc.UI.Settings.Strings,
  dpcc.Core.Diagnostics.Hangs;

const
  /// <summary>Aktionen für den Einfrier-Wächter (Protokollnamen, nicht übersetzt).</summary>
  cBuildActivity = 'Settings page: build';
  cWindowActivity = 'Settings page: window';

{ TDpccSettingsPage }

constructor TDpccSettingsPage.Create(AOwner: TComponent);
var
  mActivity: IInterface;
begin
  // Die IDE legt die Seite selbst an (auch für IDE Insight): ohne Aktion hieße ein Hänger hier im Bericht nur „–“.
  mActivity := TDpccActivity.Scope(cBuildActivity);
  inherited Create(AOwner);
  Name := 'DpccSettingsPage';
  Width := ScaleValue(480);
  // Die Reiter tragen den Inhalt; scrollt die Seite selbst, springt sie beim Reiterwechsel zum Fokus.
  AutoScroll := False;
  // Mit Reitern reicht die Höhe des längsten Reiters; höher, und die IDE scrollt ihren Bereich beim
  // Reiterwechsel zum Fokus (die Seite „springt“).
  Height := ScaleValue(440);
  // Kopf mit Titel.
  AddHeader;
  AddExperimentalBanner;
  AddNavigation;
  TDpccSettingsPageParts.Build(Self);
  // „Einstellungen dazu …“ am gezeichneten Element (#628) und an Bereichen der Willkommensseite (#767).
  BindControls;
  AddFilterRow;
  BuildNodes;
  ApplyView;
  UpdateLocks;
  // Suche über die Einstellungen (#1884): Beschriftungen der Elemente und aktuelle Werte von der Seite.
  FSearch.OnLabel :=
    function(const AName: string): string
    begin
      Result := FMarks.TextOfName(AName);
    end;
  FSearch.OnSettings := CurrentSettings;
  FSearch.OnShown :=
    function(const AName: string): Boolean
    var
      mIndex: Integer;
    begin
      mIndex := Catalog.IndexOfName(AName);
      Result := (mIndex >= 0) and ((TDpccCompletionView.PlaceOf(Catalog[mIndex]) = spKeys) or
        SettingShown(AName));
    end;
  FSearch.OnOpen := SearchOpen;
end;

procedure TDpccSettingsPage.SearchOpen(AHit: TDpccSettingHit);
begin
  if SameText(AHit.Module, Scope.Switch) and Reveal(AHit.Name) then
  begin
    Exit;
  end;
  if Assigned(FOnOpenSetting) then
  begin
    FOnOpenSetting(AHit.Name, AHit.Module);
  end;
end;

procedure TDpccSettingsPage.AddHeader;
var
  mPanel: TWinControl;
  mTitle: TLabel;
begin
  mPanel := TDpccSettingsRow.Create(Self);
  mPanel.Parent := Self;
  mPanel.Align := alTop;
  mPanel.Height := mPanel.ScaleValue(40);
  mTitle := TLabel.Create(Self);
  mTitle.Parent := mPanel;
  mTitle.Left := mTitle.ScaleValue(4);
  mTitle.Top := mTitle.ScaleValue(12);
  mTitle.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsTitle);
  mTitle.Font.Style := [fsBold];
  FTitle := mTitle;
end;

procedure TDpccSettingsPage.AddExperimentalBanner;
var
  mText: TLabel;
  mButton: TButton;
begin
  FExperimentalBanner := TDpccSettingsRow.Create(Self);
  FExperimentalBanner.Parent := Self;
  FExperimentalBanner.Align := alTop;
  FExperimentalBanner.AlignWithMargins := True;
  FExperimentalBanner.Top := FExperimentalBanner.ScaleValue(50);
  FExperimentalBanner.Height := FExperimentalBanner.ScaleValue(28);
  FExperimentalBanner.Visible := False;
  mButton := TButton.Create(Self);
  mButton.Parent := FExperimentalBanner;
  mButton.Align := alRight;
  mButton.Width := mButton.ScaleValue(90);
  mButton.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExperimentalAllow);
  mButton.OnClick := ExperimentalAllowClick;
  mText := TLabel.Create(Self);
  mText.Parent := FExperimentalBanner;
  mText.Align := alClient;
  mText.Layout := tlCenter;
  mText.WordWrap := True;
  mText.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsExperimentalOff);
end;

procedure TDpccSettingsPage.AddFilterRow;
var
  mCaption: TLabel;
begin
  FFilterRow := TDpccSettingsRow.Create(Self);
  FFilterRow.Parent := Self;
  FFilterRow.Align := alBottom;
  FFilterRow.AlignWithMargins := True;
  FFilterRow.Height := FFilterRow.ScaleValue(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := FFilterRow;
  mCaption.Left := 0;
  mCaption.Top := mCaption.ScaleValue(5);
  mCaption.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFilter);
  // Reihenfolge wie TDpccSettingsFilter.
  FFilter := TDpccChoiceBox.Create(Self);
  FFilter.Parent := FFilterRow;
  FFilter.Left := FFilter.ScaleValue(60);
  FFilter.Top := 1;
  FFilter.Width := FFilter.ScaleValue(180);
  FFilter.SetChoices([TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFilterAll),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFilterModified),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsFilterExperimental)]);
  FFilter.Choice := 0;
  FFilter.OnChange := FilterChange;
  FMarks.MarkExperimental(TDpccExperimental.PluginNames(Catalog));
end;

procedure TDpccSettingsPage.ExperimentalAllowClick(Sender: TObject);
begin
  // Wie ein Klick auf das Kontrollkästchen: Punkte und Hinweis folgen über die Bindung.
  Part<TDpccSettingsGeneralPart>.ExperimentalEnabled.Checked := True;
end;

procedure TDpccSettingsPage.FilterChange(Sender: TObject);
begin
  if (FFilter.Choice >= Ord(Low(TDpccSettingsFilter))) and (FFilter.Choice <= Ord(High(TDpccSettingsFilter))) then
  begin
    FMarks.ApplyFilter(TDpccSettingsFilter(FFilter.Choice));
  end;
  // Knoten ohne Treffer fallen aus dem Baum (#890).
  if ListReady(FTree) then
  begin
    FillTree;
  end;
end;

procedure TDpccSettingsPage.SetTitle(const ACaption: string);
begin
  FTitle.Caption := ACaption;
end;

function TDpccSettingsPage.Reveal(const AKey: string): Boolean;
begin
  Result := ControlOf(AKey) <> nil;
  if not Result then
  begin
    Exit;
  end;
  if HandleAllocated then
  begin
    ApplyReveal(AKey);
  end
  else
  begin
    FPendingReveal := AKey;
  end;
end;

/// <summary>Rollt AControl in seinem Kasten ins Bild.</summary>
procedure ScrollToControl(AControl: TControl);
var
  mParent: TWinControl;
begin
  mParent := AControl.Parent;
  while (mParent <> nil) and not (mParent is TScrollBox) do
  begin
    mParent := mParent.Parent;
  end;
  if mParent is TScrollBox then
  begin
    TScrollBox(mParent).ScrollInView(AControl);
  end;
end;

/// <summary>Zeile hervorheben: Kontrollkästchen fett, sonst die Beschriftung der Zeile.</summary>
procedure HighlightRow(AControl: TControl);
var
  mChild: Integer;
begin
  if AControl is TCheckBox then
  begin
    TCheckBox(AControl).Font.Style := [fsBold];
    Exit;
  end;
  if AControl.Parent = nil then
  begin
    Exit;
  end;
  for mChild := 0 to AControl.Parent.ControlCount - 1 do
  begin
    if AControl.Parent.Controls[mChild] is TLabel then
    begin
      TLabel(AControl.Parent.Controls[mChild]).Font.Style := [fsBold];
    end;
  end;
end;

/// <summary>Fokus nur mit sichtbarer Form: CanFocus allein lässt eine noch verborgene Form durch („kann den Fokus
/// nicht erhalten“).</summary>
procedure FocusShown(AControl: TControl);
begin
  if (AControl is TWinControl) and TWinControl(AControl).CanFocus and (GetParentForm(AControl) <> nil) and
    GetParentForm(AControl).Visible then
  begin
    TWinControl(AControl).SetFocus;
  end;
end;

function TDpccSettingsPage.RevealTarget(AControl: TControl): TControl;
var
  mNames: TArray<string>;
  mLock: TDpccSettingsLock;
  mMaster: TControl;
begin
  // Gesperrt (#890): den Hauptschalter zeigen, der sie freigibt.
  Result := AControl;
  mNames := FMarks.NamesOf(AControl);
  if (Length(mNames) = 0) or (FGroups = nil) then
  begin
    Exit;
  end;
  mLock := LockOfName(mNames[0]);
  if mLock.Locked then
  begin
    mMaster := FMarks.ControlOfName(mLock.Master);
    if mMaster <> nil then
    begin
      Result := mMaster;
    end;
  end;
end;

procedure TDpccSettingsPage.ApplyReveal(const AKey: string);
var
  mControl: TControl;
begin
  FPendingReveal := '';
  mControl := ControlOf(AKey);
  if mControl = nil then
  begin
    Exit;
  end;
  mControl := RevealTarget(mControl);
  // Knoten des Elements wählen, wie ein Klick im Baum links.
  SelectPage(PageOf(mControl));
  ScrollToControl(mControl);
  HighlightRow(mControl);
  FocusShown(mControl);
end;

// Art und Hauptbranch je Projekt (#1286): wie die Tabelle Projekte der Seite Issue-Tracker (#1261), dieselbe
// Auflösung (dpcc.Core.Projects.Matching).

procedure TDpccSettingsPage.BindControls;
var
  mPart: TDpccSettingsPagePart;
  mIndex: Integer;
begin
  for mPart in FParts do
  begin
    mPart.BindMarks;
  end;
  // Gebundene Elemente erst jetzt: Die Markierung übernimmt OnClick und Hint, die der Aufbau gesetzt hat.
  for mIndex := 0 to FBindings.Count - 1 do
  begin
    FMarks.Bind(FBindings.Item(mIndex).Control, [FBindings.Item(mIndex).Name]);
  end;
end;

function TDpccSettingsPage.CurrentSettings: TDpccPluginSettings;
begin
  Result := FWidths;
  SaveTo(Result);
end;

procedure TDpccSettingsPage.RefreshMarks;
begin
  FExperimentalBanner.Visible := FMarks.HasExperimental and
    not Part<TDpccSettingsGeneralPart>.ExperimentalEnabled.Checked;
  UpdateLocks;
  // Geänderte Werte ändern sich mit jeder Eingabe; der Filter folgt, auch im Baum.
  if FMarks.Filter = sfModified then
  begin
    FMarks.ApplyFilter(sfModified);
    if ListReady(FTree) then
    begin
      FillTree;
    end;
  end;
end;

procedure TDpccSettingsPage.ResetNames(const ANames: TArray<string>);
begin
  if Length(ANames) = 0 then
  begin
    Exit;
  end;
  LoadFrom(TDpccSettingsTransfer.ResetNames(Catalog, CurrentSettings, ANames));
end;

procedure TDpccSettingsPage.ResetPage;
var
  mCurrent, mIndex: Integer;
  mNames: TArray<string>;
begin
  // Ohne Fenster hängen die Reiter noch nicht am PageControl.
  mCurrent := ActiveNode;
  if mCurrent < 0 then
  begin
    Exit;
  end;
  // Unterpunkt: nur seine Einstellungen; Hauptknoten: der ganze Bereich mit allen Unterpunkten (#890).
  if FNodePages[mCurrent].Node <> '' then
  begin
    mNames := FMarks.NamesIn(FNodePages[mCurrent].Box);
  end
  else
  begin
    mNames := nil;
    for mIndex := 0 to High(FNodePages) do
    begin
      if FNodePages[mIndex].Area = FNodePages[mCurrent].Area then
      begin
        mNames := mNames + FMarks.NamesIn(FNodePages[mIndex].Box);
      end;
    end;
  end;
  ResetNames(mNames);
end;

procedure TDpccSettingsPage.CreateWnd;
var
  mPage: TDpccSettingsNodePage;
  mPart: TDpccSettingsPagePart;
  mActivity: IInterface;
begin
  mActivity := TDpccActivity.Scope(cWindowActivity);
  inherited CreateWnd;
  // Je Knoten ein Reiter, in der Reihenfolge des Baums.
  for mPage in FNodePages do
  begin
    if mPage.Sheet.PageControl = nil then
    begin
      mPage.Sheet.PageControl := FPages;
      mPage.Sheet.TabVisible := False;
    end;
  end;
  // Der Baum braucht ein Fenster für seine Knoten (wie die Reiter); zeigt die zuletzt gewählte Seite.
  FillTree;
  // Listen der Teile brauchen ein Fenster; vorher bleiben sie leer.
  for mPart in FParts do
  begin
    mPart.WindowReady;
  end;
  // Gewünschte Einstellung (#628) erst mit Fenster zeigen.
  if FPendingReveal <> '' then
  begin
    ApplyReveal(FPendingReveal);
  end;
end;


// Prüfregeln (#909).


procedure TDpccSettingsPage.LoadFrom(const ASettings: TDpccPluginSettings);
begin
  // Während des Ladens lösen die Elemente keine Neuberechnung der Punkte aus.
  FMarks.BeginLoad;
  try
    LoadControls(ASettings);
  finally
    FMarks.EndLoad;
  end;
  RefreshMarks;
end;

procedure TDpccSettingsPage.LoadControls(const ASettings: TDpccPluginSettings);
var
  mPart: TDpccSettingsPagePart;
begin
  FWidths := ASettings;
  FSearch.SetAvailable(ASettings.SettingsSearch);
  FBindings.Load(TDpccMemorySettingsStore.FromSettings(ASettings));
  for mPart in FParts do
  begin
    mPart.Load(ASettings);
  end;
end;

procedure TDpccSettingsPage.SaveTo(var ASettings: TDpccPluginSettings);
var
  mPart: TDpccSettingsPagePart;
  mStore: IDpccMemorySettingsStore;
begin
  mStore := TDpccMemorySettingsStore.FromSettings(ASettings);
  FBindings.Save(mStore);
  ASettings.Load(mStore);
  for mPart in FParts do
  begin
    mPart.Save(ASettings);
  end;
  ASettings.Normalize;
end;


function TDpccSettingsPage.SheetCountForTests: Integer;
begin
  Result := Length(FSheets);
end;

end.
