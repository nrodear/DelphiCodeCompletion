unit dpcc.UI.Settings.Page;

// Seite „dpcc“ unter Tools › Optionen › Fremdhersteller (#227). Seit OPT1 eine einzige, schlichte Seite ohne Reiter,
// Baum, Suchfeld, Filter, Experimental-Hinweis und Geändert-Markierung: oben der Hauptschalter, darunter die Abschnitte
// Vervollständigung, Beim Übernehmen, Parameter-Hint und Tooltip, Index und (seit IDECHECK) IDE mit Überschrift (fett,
// Großbuchstaben, gedämpft, mit Linie bis zum rechten Rand). Der Abschnitt IDE zeigt Statuszeilen zur Betriebsart
// (Anbieter, was dpcc an der IDE gesetzt hat, Abweichungen); „Jetzt prüfen“ liest sie über OnIdeStatus neu. Aufbau und Reihenfolge kommen aus cPageItems
// (dpcc.Core.Settings.CompletionView); die Seite baut genau diese Liste.
// Reine VCL, im Code aufgebaut; die DFM ist leer, weil TCustomFrame.Create für abgeleitete Frames eine Ressource
// verlangt. Laden und Speichern direkt über TDpccPluginSettings (LoadFrom, SaveTo); die IDE-Schicht liest und
// schreibt Registry und settings.json (index.extraSourceFolders). Die Seite kennt den Server nicht und startet ihn
// nicht: „Index neu aufbauen“ führt die IDE-Schicht aus (OnRebuildIndex), „Verlauf zurücksetzen“ ebenso
// (OnResetHistory), die Statuszeilen des Abschnitts IDE ebenso (OnIdeStatus, nur gelesen).
// Seit LOOK1 steht zuletzt im Abschnitt Parameter-Hint und Tooltip die Auswahl „Darstellung der Popups“ (Intensiv,
// Dezent, Unscheinbar; TDpccPluginSettings.PopupLook); sie ändert nur, wie die Fenster von dpcc zeichnen.
// Seit LOG1 steht zuletzt im Abschnitt IDE „Ablauf protokollieren (Log)“ (TDpccPluginSettings.Diagnose, derselbe
// Registry-Wert wie das frühere Diagnose = 1); sein Hint nennt die Protokolldatei (DiagnoseFile, von der IDE-Schicht).
// Sperren: Hauptschalter aus → alle Optionen und „Verlauf zurücksetzen“ grau; „Werte beim Debuggen“ zusätzlich grau,
// wenn „Eigener Tooltip“ aus ist. „Index neu aufbauen“, „Jetzt prüfen“ und „Ablauf protokollieren“ hängen nicht am
// Hauptschalter.
// „Index neu aufbauen“ läuft im Hintergrund: OnRebuildIndex kehrt sofort zurück. Den Zustand (läuft → Knopf grau,
// Meldung daneben) fragt die Seite über OnRebuildStatus ab, beim Setzen und per Timer der Seite, solange er läuft.
// Die IDE-Schicht hält keinen Verweis auf die Seite; sie kann jederzeit geschlossen und zerstört werden.
// Layout: Beschriftungen links, Felder in einer gemeinsamen Spalte rechts davon. Die Spalte richtet sich nach der
// längsten Beschriftung in der aktuellen Schrift (Deutsch oder Englisch, nach Skalierung und Schriftwechsel neu),
// damit keine Beschriftung in ein Feld ragt. Höhen und Abstände über ScaleValue; die IDE skaliert die Seite mit dem
// Dialog (High-DPI).

interface

uses
  System.Classes,
  System.SysUtils,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.CompletionView,
  dpcc.UI.Settings.ChoiceBox;

const
  /// <summary>Höhe einer Zeile mit Kontrollkästchen (bei 96 dpi).</summary>
  cCheckRowHeight = 21;

type
  /// <summary>Zeile der Seite (Beschriftung und Eingabefeld): zeichnet nichts selbst, der Hintergrund der Seite scheint
  /// durch. Kein TPanel: Das zeichnet im IDE-Thema einen eigenen Hintergrund.</summary>
  TDpccSettingsRow = class(TWinControl)
  public
    constructor Create(AOwner: TComponent); override;
  end;

  /// <summary>Überschrift eines Abschnitts: Text in Großbuchstaben, fett und gedämpft (clGrayText des IDE-Themas),
  /// dahinter eine dünne Linie (clBtnShadow des Themas) bis zum rechten Rand.</summary>
  TDpccSettingsTitle = class(TLabel)
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
  end;

  /// <summary>Element der Seite zu einem Eintrag von cPageItems.</summary>
  TDpccSettingsPageEntry = record
    Item: TDpccPageItem;
    /// <summary>Eingabeelement (Kontrollkästchen, Feld, Auswahl) bzw. Knopf.</summary>
    Control: TControl;
    /// <summary>Beschriftung links neben dem Feld bzw. darüber; nil, wenn das Element sich selbst beschriftet.
    /// </summary>
    Caption: TLabel;
    /// <summary>Zeile, in der das Element steht.</summary>
    Row: TWinControl;
  end;

  /// <summary>Zustand von „Index neu aufbauen“ für die Seite (OnRebuildStatus).</summary>
  TDpccRebuildStatus = record
    /// <summary>Läuft der Neuaufbau noch? Dann ist der Knopf grau.</summary>
    Running: Boolean;
    /// <summary>Meldung neben dem Knopf; '' = bisherige Meldung lassen.</summary>
    Text: string;
  end;

  TDpccSettingsPage = class(TFrame)
  private
    FEntries: TArray<TDpccSettingsPageEntry>;
    FTitles: array[TDpccPageSection] of TDpccSettingsTitle;
    FRows: TArray<TWinControl>;
    FNextTop: Integer;
    FBuilt: Boolean;
    FMaster: TCheckBox;
    /// <summary>Zahlen als Auswahl (0 bis 10 bzw. 5 bis 20): ohne Fenster nutzbar, ohne Tippfehler.</summary>
    FAutoMinChars: TDpccChoiceBox;
    FListMode: TDpccChoiceBox;
    FVisibleRows: TDpccChoiceBox;
    FAutoWidth: TCheckBox;
    FLearning: TCheckBox;
    FResetHistory: TButton;
    FAutoParentheses: TCheckBox;
    FCommitCharacters: TCheckBox;
    FAutoUses: TCheckBox;
    FParameterHints: TCheckBox;
    FHoverTooltip: TCheckBox;
    FDebugHoverValues: TCheckBox;
    /// <summary>„Darstellung der Popups“ (LOOK1), Einträge in der Reihenfolge von TDpccLookLevel.</summary>
    FPopupLook: TDpccChoiceBox;
    FExtraSourceFolders: TEdit;
    FRebuild: TButton;
    FRebuildInfo: TLabel;
    /// <summary>„Jetzt prüfen“ und die Statuszeilen des Abschnitts IDE (IDECHECK).</summary>
    FCheckIde: TButton;
    FIdeStatus: TLabel;
    FOnIdeStatus: TFunc<string>;
    /// <summary>„Ablauf protokollieren (Log)“ (LOG1, Registry-Wert Diagnose); Hint mit der Protokolldatei.</summary>
    FDiagnose: TCheckBox;
    FDiagnoseFile: string;
    /// <summary>Breite der Liste beim Laden (0 = automatisch); gezogene Breiten bleiben, solange „Breite
    /// automatisch“ aus ist.</summary>
    FListWidth: Integer;
    /// <summary>„Verlauf zurücksetzen“ wurde schon gedrückt: bleibt bis zum Schließen grau.</summary>
    FHistoryReset: Boolean;
    FOnResetHistory: TProc;
    FOnRebuildIndex: TFunc<string>;
    FConfirmRebuild: TFunc<Boolean>;
    /// <summary>Zustand von „Index neu aufbauen“ (läuft im Hintergrund); nil = nie „läuft“.</summary>
    FOnRebuildStatus: TFunc<TDpccRebuildStatus>;
    /// <summary>Zuletzt abgefragt: Neuaufbau läuft (Knopf grau).</summary>
    FRebuildRunning: Boolean;
    /// <summary>Fragt den Zustand ab, solange der Neuaufbau läuft; gehört der Seite (mit ihr freigegeben).</summary>
    FRebuildTimer: TTimer;
    procedure Build;
    procedure AddTitle(ASection: TDpccPageSection);
    function AddRow(AHeight: Integer): TWinControl;
    function AddCheckRow(const ACaption: string; AIndent: Integer;
      ARowHeight: Integer = cCheckRowHeight): TCheckBox;
    function AddLabel(ARow: TWinControl; const ACaption: string): TLabel;
    function AddChoiceRow(const ACaption: string; const AItems: array of string;
      out ACaptionLabel: TLabel): TDpccChoiceBox;
    function AddNumberRow(const ACaption: string; AMin, AMax: Integer; out ACaptionLabel: TLabel): TDpccChoiceBox;
    procedure AddEntry(const AItem: TDpccPageItem; AControl: TControl; ACaption: TLabel);
    procedure BuildItem(const AItem: TDpccPageItem);
    /// <summary>Spalte der Felder, Breiten und Lage abhängiger Elemente nach Schrift und Breite der Seite.</summary>
    procedure ArrangeRows;
    function CheckWidth(ACheck: TCheckBox): Integer;
    procedure ToggleClick(Sender: TObject);
    procedure ResetHistoryClick(Sender: TObject);
    procedure RebuildClick(Sender: TObject);
    procedure CheckIdeClick(Sender: TObject);
    procedure SetOnRebuildIndex(const AValue: TFunc<string>);
    procedure SetOnRebuildStatus(const AValue: TFunc<TDpccRebuildStatus>);
    procedure RebuildTimerTick(Sender: TObject);
    procedure SetOnIdeStatus(const AValue: TFunc<string>);
    procedure SetDiagnoseFile(const AValue: string);
    procedure CMFontChanged(var AMessage: TMessage); message CM_FONTCHANGED;
  protected
    procedure CreateWnd; override;
    procedure Resize; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Werte von ASettings auf die Seite.</summary>
    procedure LoadFrom(const ASettings: TDpccPluginSettings);
    /// <summary>Werte der Seite nach ASettings; alles, was die Seite nicht zeigt, bleibt.</summary>
    procedure SaveTo(var ASettings: TDpccPluginSettings);
    /// <summary>Sperren neu setzen: Hauptschalter, Tooltip → Werte beim Debuggen, Knöpfe.</summary>
    procedure UpdateLocks;
    /// <summary>Zustand von „Index neu aufbauen“ über OnRebuildStatus abfragen: Knopf, Meldung und Timer (läuft nur,
    /// solange der Neuaufbau läuft).</summary>
    procedure RefreshRebuild;
    /// <summary>Element zum Namen aus cPageItems (Einstellung oder Knopf); nil, wenn die Seite ihn nicht kennt.
    /// </summary>
    function ControlOf(const AName: string): TControl;
    /// <summary>Breite von AText in der Schrift von AControl (auch ohne Fenster).</summary>
    function TextWidthFor(AControl: TControl; const AText: string): Integer;
    /// <summary>Überschrift des Abschnitts; nil für psMaster.</summary>
    function TitleOf(ASection: TDpccPageSection): TDpccSettingsTitle;
    /// <summary>Elemente in der Reihenfolge der Seite.</summary>
    property Entries: TArray<TDpccSettingsPageEntry> read FEntries;
    /// <summary>Zeilen in der Reihenfolge der Seite (Überschriften eingeschlossen).</summary>
    property Rows: TArray<TWinControl> read FRows;
    property MasterSwitch: TCheckBox read FMaster;
    property AutoWidth: TCheckBox read FAutoWidth;
    property ListModeChoice: TDpccChoiceBox read FListMode;
    property AutoMinCharsChoice: TDpccChoiceBox read FAutoMinChars;
    property VisibleRowsChoice: TDpccChoiceBox read FVisibleRows;
    property HoverTooltip: TCheckBox read FHoverTooltip;
    property DebugHoverValues: TCheckBox read FDebugHoverValues;
    property PopupLookChoice: TDpccChoiceBox read FPopupLook;
    property ResetHistory: TButton read FResetHistory;
    property Rebuild: TButton read FRebuild;
    property RebuildInfo: TLabel read FRebuildInfo;
    property CheckIde: TButton read FCheckIde;
    property IdeStatus: TLabel read FIdeStatus;
    /// <summary>„Ablauf protokollieren (Log)“ im Abschnitt IDE (LOG1).</summary>
    property DiagnoseLog: TCheckBox read FDiagnose;
    /// <summary>Protokolldatei für den Hint an „Ablauf protokollieren (Log)“; setzt die IDE-Schicht ('' = Hint ohne
    /// Datei).</summary>
    property DiagnoseFile: string read FDiagnoseFile write SetDiagnoseFile;
    /// <summary>„Verlauf zurücksetzen“ der lernenden Gewichtung (#418).</summary>
    property OnResetHistory: TProc read FOnResetHistory write FOnResetHistory;
    /// <summary>„Index neu aufbauen“ (S4): stößt das Leeren der Index-Caches und den Neuaufbau an (kehrt sofort
    /// zurück) und liefert die Meldung für die Seite; nil = Knopf gesperrt.</summary>
    property OnRebuildIndex: TFunc<string> read FOnRebuildIndex write SetOnRebuildIndex;
    /// <summary>Zustand von „Index neu aufbauen“ (läuft, Meldung); beim Setzen, nach dem Klick und per Timer
    /// abgefragt. nil = der Knopf ist nie „läuft“.</summary>
    property OnRebuildStatus: TFunc<TDpccRebuildStatus> read FOnRebuildStatus write SetOnRebuildStatus;
    /// <summary>Rückfrage vor dem Neuaufbau; Standard: Dialog mit Ja/Nein.</summary>
    property ConfirmRebuild: TFunc<Boolean> read FConfirmRebuild write FConfirmRebuild;
    /// <summary>Statuszeilen des Abschnitts IDE (Betriebsart, Anbieter, was dpcc gesetzt hat, Abweichungen); beim
    /// Setzen und mit „Jetzt prüfen“ gelesen. nil = Knopf gesperrt, keine Zeilen.</summary>
    property OnIdeStatus: TFunc<string> read FOnIdeStatus write SetOnIdeStatus;
  end;

implementation

{$R *.dfm}

uses
  System.Math,
  System.UITypes,
  Vcl.Dialogs,
  Vcl.Themes,
  // dpcc.UI.Foundation.Module (Anmeldung bei TDpccPluginModules, S7b) steht im Package und läuft mit ihm an; die
  // Seite bindet es nicht ein, damit die Test-Exe sie ohne das Package bauen kann.
  dpcc.UI.Settings.Strings,
  dpcc.Core.Completion.Ranking,
  dpcc.Core.Style.Look;

const
  /// <summary>Einrückung der Optionen unter einer Überschrift bzw. unter „Eigener Tooltip“ (bei 96 dpi).</summary>
  cIndent = 16;
  cSubIndent = 36;
  /// <summary>Höhen der Zeilen (bei 96 dpi): Feld, Überschrift, Knopf (Kontrollkästchen: cCheckRowHeight).</summary>
  cFieldHeight = 25;
  cTitleHeight = 26;
  cButtonHeight = 29;
  /// <summary>Höhe der Zeile mit „Jetzt prüfen“ und bis zu vier Statuszeilen (bei 96 dpi).</summary>
  cIdeStatusHeight = 64;
  /// <summary>Abstand zwischen Beschriftung und Feld bzw. zwischen Elementen einer Zeile.</summary>
  cGap = 12;
  /// <summary>Platz für Kästchen und Rand eines Kontrollkästchens neben dem Text.</summary>
  cCheckGlyph = 26;
  /// <summary>Breite des Pfeils einer Auswahl samt Rand.</summary>
  cChoiceArrow = 36;
  /// <summary>Mindestbreite der Knöpfe.</summary>
  cButtonMinWidth = 140;

{ TDpccSettingsRow }

constructor TDpccSettingsRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csParentBackground] - [csOpaque];
  ParentBackground := True;
  ParentColor := True;
end;

{ TDpccSettingsTitle }

constructor TDpccSettingsTitle.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  AutoSize := False;
  Transparent := True;
  ShowAccelChar := False;
  Font.Style := [fsBold];
  // Die Farbe setzt Paint aus dem IDE-Thema; der Stil soll sie nicht durch die Textfarbe ersetzen.
  StyleElements := StyleElements - [seFont];
end;

procedure TDpccSettingsTitle.Paint;
var
  mText: string;
  mTextWidth, mGap, mLineY: Integer;
begin
  mText := Caption;
  Canvas.Brush.Style := bsClear;
  Canvas.Font := Font;
  Canvas.Font.Color := StyleServices.GetSystemColor(clGrayText);
  Canvas.TextOut(0, 0, mText);
  // Dünne Trennlinie von hinter dem Text bis zum rechten Rand, auf halber Texthöhe.
  mTextWidth := Canvas.TextWidth(mText);
  mGap := ScaleValue(8);
  mLineY := Canvas.TextHeight(mText) div 2;
  if mTextWidth + mGap < ClientWidth then
  begin
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Width := 1;
    Canvas.Pen.Color := StyleServices.GetSystemColor(clBtnShadow);
    Canvas.MoveTo(mTextWidth + mGap, mLineY);
    Canvas.LineTo(ClientWidth, mLineY);
  end;
end;

{ TDpccSettingsPage }

constructor TDpccSettingsPage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Name := 'DpccSettingsPage';
  Width := ScaleValue(520);
  // Eine Seite ohne Reiter: Ist der Bereich der IDE kleiner als der Inhalt, rollt die Seite.
  AutoScroll := True;
  Build;
  FBuilt := True;
  ArrangeRows;
  UpdateLocks;
end;

procedure TDpccSettingsPage.Build;
var
  mItem: TDpccPageItem;
  mSection: TDpccPageSection;
begin
  FNextTop := 0;
  mSection := psMaster;
  for mItem in cPageItems do
  begin
    if mItem.Section <> mSection then
    begin
      mSection := mItem.Section;
      AddTitle(mSection);
    end;
    BuildItem(mItem);
  end;
  // Ohne Ausrichtung der IDE (alClient) reicht die Höhe für alle Zeilen: Summe der Zeilen samt Rändern.
  Height := FNextTop;
end;

procedure TDpccSettingsPage.BuildItem(const AItem: TDpccPageItem);
var
  mRow: TWinControl;
  mCaption: TLabel;
begin
  mCaption := nil;
  if AItem.Name = 'Enabled' then
  begin
    FMaster := AddCheckRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsEnabled), 0);
    FMaster.OnClick := ToggleClick;
    AddEntry(AItem, FMaster, nil);
  end
  else if AItem.Name = 'AutoMinChars' then
  begin
    // L5: Tippen eines Bezeichners öffnet die Liste erst ab so vielen Zeichen (0 bis 10, 0 = nie).
    FAutoMinChars := AddNumberRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsAutoMinChars), 0,
      TDpccPluginSettings.cMaxAutoMinChars, mCaption);
    AddEntry(AItem, FAutoMinChars, mCaption);
  end
  else if AItem.Name = 'CompletionListMode' then
  begin
    // In der Reihenfolge von TDpccListMode.
    FListMode := AddChoiceRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListMode),
      [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListModeFilter),
      TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListModeAll),
      TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListModeRest)], mCaption);
    AddEntry(AItem, FListMode, mCaption);
  end
  else if AItem.Name = 'VisibleRows' then
  begin
    FVisibleRows := AddNumberRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsRows),
      TDpccPluginSettings.cMinVisibleRows, TDpccPluginSettings.cMaxVisibleRows, mCaption);
    AddEntry(AItem, FVisibleRows, mCaption);
  end
  else if AItem.Name = 'ListWidth' then
  begin
    // In der Zeile der sichtbaren Zeilen, rechts vom Feld.
    mRow := FRows[High(FRows)];
    FAutoWidth := TCheckBox.Create(Self);
    FAutoWidth.Parent := mRow;
    FAutoWidth.Top := ScaleValue(3);
    FAutoWidth.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsAutoWidth);
    AddEntry(AItem, FAutoWidth, nil);
  end
  else if AItem.Name = 'Learning' then
  begin
    // Zeile mit Platz für den Knopf „Verlauf zurücksetzen“.
    FLearning := AddCheckRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsLearning), cIndent,
      cButtonHeight);
    FLearning.Top := ScaleValue(6);
    AddEntry(AItem, FLearning, nil);
  end
  else if AItem.Name = cPageResetHistory then
  begin
    // In der Zeile von „Häufig und zuletzt gewählte Einträge nach oben“, rechts davon.
    FResetHistory := TButton.Create(Self);
    FResetHistory.Parent := FLearning.Parent;
    FResetHistory.Top := ScaleValue(2);
    FResetHistory.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsResetHistory);
    FResetHistory.OnClick := ResetHistoryClick;
    AddEntry(AItem, FResetHistory, nil);
  end
  else if AItem.Name = 'AutoParentheses' then
  begin
    FAutoParentheses := AddCheckRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsParentheses), cIndent);
    AddEntry(AItem, FAutoParentheses, nil);
  end
  else if AItem.Name = 'CommitCharacters' then
  begin
    FCommitCharacters := AddCheckRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsCommitChars), cIndent);
    AddEntry(AItem, FCommitCharacters, nil);
  end
  else if AItem.Name = 'AutoUses' then
  begin
    FAutoUses := AddCheckRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsAutoUses), cIndent);
    AddEntry(AItem, FAutoUses, nil);
  end
  else if AItem.Name = 'ParameterHints' then
  begin
    FParameterHints := AddCheckRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsParameterHints), cIndent);
    AddEntry(AItem, FParameterHints, nil);
  end
  else if AItem.Name = 'HoverTooltip' then
  begin
    FHoverTooltip := AddCheckRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsHover), cIndent);
    FHoverTooltip.OnClick := ToggleClick;
    AddEntry(AItem, FHoverTooltip, nil);
  end
  else if AItem.Name = 'DebugHoverValues' then
  begin
    // Unter dem Tooltip eingerückt: wirkt nur mit eigenem Tooltip.
    FDebugHoverValues := AddCheckRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDebugHoverValues),
      cSubIndent);
    AddEntry(AItem, FDebugHoverValues, nil);
  end
  else if AItem.Name = 'PopupLook' then
  begin
    // LOOK1: in der Reihenfolge von TDpccLookLevel; gilt für alle Fenster von dpcc (Liste, Hover, Parameter-Hint).
    FPopupLook := AddChoiceRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPopupLook),
      [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPopupLookIntense),
      TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPopupLookSubtle),
      TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPopupLookPlain)], mCaption);
    AddEntry(AItem, FPopupLook, mCaption);
  end
  else if AItem.Name = 'IndexExtraSourceFolders' then
  begin
    // L2: Beschriftung in einer Zeile, darunter das Feld über die ganze Breite (Pfade brauchen den Platz).
    mRow := AddRow(cCheckRowHeight - 3);
    mCaption := AddLabel(mRow, TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexExtraSourceFolders));
    mRow := AddRow(cFieldHeight);
    FExtraSourceFolders := TEdit.Create(Self);
    FExtraSourceFolders.Parent := mRow;
    FExtraSourceFolders.Top := 1;
    mCaption.FocusControl := FExtraSourceFolders;
    AddEntry(AItem, FExtraSourceFolders, mCaption);
  end
  else if AItem.Name = cPageRebuildIndex then
  begin
    // „Index neu aufbauen“ (S4), rechts daneben das Ergebnis.
    mRow := AddRow(cButtonHeight + 4);
    FRebuild := TButton.Create(Self);
    FRebuild.Parent := mRow;
    FRebuild.Top := ScaleValue(2);
    FRebuild.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexRebuild);
    FRebuild.OnClick := RebuildClick;
    FRebuildInfo := TLabel.Create(Self);
    FRebuildInfo.Parent := mRow;
    FRebuildInfo.AutoSize := False;
    FRebuildInfo.WordWrap := True;
    FRebuildInfo.ShowAccelChar := False;
    FRebuildInfo.Top := 0;
    // Gedämpfter Text in der Farbe des IDE-Themas (hell und dunkel).
    FRebuildInfo.Font.Color := StyleServices.GetSystemColor(clGrayText);
    AddEntry(AItem, FRebuild, nil);
  end
  else if AItem.Name = cPageCheckIde then
  begin
    // „Jetzt prüfen“ (IDECHECK), rechts daneben die Statuszeilen der Betriebsart.
    mRow := AddRow(cIdeStatusHeight);
    FCheckIde := TButton.Create(Self);
    FCheckIde.Parent := mRow;
    FCheckIde.Top := ScaleValue(2);
    FCheckIde.Caption := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsCheckIde);
    FCheckIde.OnClick := CheckIdeClick;
    FIdeStatus := TLabel.Create(Self);
    FIdeStatus.Parent := mRow;
    FIdeStatus.AutoSize := False;
    FIdeStatus.WordWrap := True;
    FIdeStatus.ShowAccelChar := False;
    FIdeStatus.Top := 0;
    FIdeStatus.Font.Color := StyleServices.GetSystemColor(clGrayText);
    AddEntry(AItem, FCheckIde, nil);
  end
  else if AItem.Name = 'Diagnose' then
  begin
    // LOG1: unter „Jetzt prüfen“; derselbe Registry-Wert wie das frühere Diagnose = 1. Der Hint nennt die Datei.
    FDiagnose := AddCheckRow(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDiagnose), cIndent);
    FDiagnose.ShowHint := True;
    FDiagnose.Hint := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDiagnoseHint);
    AddEntry(AItem, FDiagnose, nil);
  end
  else
  begin
    raise EArgumentException.CreateFmt('Unbekanntes Element der Optionsseite: %s', [AItem.Name]);
  end;
end;

procedure TDpccSettingsPage.AddEntry(const AItem: TDpccPageItem; AControl: TControl; ACaption: TLabel);
var
  mEntry: TDpccSettingsPageEntry;
begin
  mEntry.Item := AItem;
  mEntry.Control := AControl;
  mEntry.Caption := ACaption;
  mEntry.Row := AControl.Parent;
  FEntries := FEntries + [mEntry];
end;

function TDpccSettingsPage.AddRow(AHeight: Integer): TWinControl;
begin
  Result := TDpccSettingsRow.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(ScaleValue(4), ScaleValue(1), ScaleValue(4), ScaleValue(1));
  Result.Height := ScaleValue(AHeight);
  // alTop stapelt nach Top: jede neue Zeile unter die vorige.
  Result.Top := FNextTop;
  Inc(FNextTop, Result.Height + Result.Margins.Top + Result.Margins.Bottom);
  FRows := FRows + [Result];
end;

procedure TDpccSettingsPage.AddTitle(ASection: TDpccPageSection);
const
  cIds: array[TDpccPageSection] of TDpccSettingsTextId = (TDpccSettingsTextId.SettingsEnabled,
    TDpccSettingsTextId.SettingsSectionCompletion, TDpccSettingsTextId.SettingsSectionCommit,
    TDpccSettingsTextId.SettingsSectionHints, TDpccSettingsTextId.SettingsSectionIndex,
    TDpccSettingsTextId.SettingsSectionIde);
var
  mRow: TWinControl;
  mTitle: TDpccSettingsTitle;
begin
  mRow := AddRow(cTitleHeight);
  mTitle := TDpccSettingsTitle.Create(Self);
  mTitle.Parent := mRow;
  mTitle.Caption := AnsiUpperCase(TDpccSettingsStrings.Text(cIds[ASection]));
  // Über die ganze Breite der Zeile: Die Linie reicht bis zum rechten Rand; Abstand nach oben trennt die Abschnitte.
  mTitle.Align := alClient;
  mTitle.AlignWithMargins := True;
  mTitle.Margins.SetBounds(0, ScaleValue(9), 0, 0);
  FTitles[ASection] := mTitle;
end;

function TDpccSettingsPage.AddCheckRow(const ACaption: string; AIndent, ARowHeight: Integer): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AddRow(ARowHeight);
  Result.Left := ScaleValue(AIndent);
  Result.Top := ScaleValue(2);
  Result.Caption := ACaption;
end;

function TDpccSettingsPage.AddLabel(ARow: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := ARow;
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
  Result.Left := ScaleValue(cIndent);
  Result.Top := ScaleValue(4);
end;

function TDpccSettingsPage.AddChoiceRow(const ACaption: string; const AItems: array of string;
  out ACaptionLabel: TLabel): TDpccChoiceBox;
var
  mRow: TWinControl;
begin
  mRow := AddRow(cFieldHeight);
  ACaptionLabel := AddLabel(mRow, ACaption);
  Result := TDpccChoiceBox.Create(Self);
  Result.Parent := mRow;
  Result.Top := 1;
  Result.SetChoices(AItems);
  ACaptionLabel.FocusControl := Result;
end;

function TDpccSettingsPage.AddNumberRow(const ACaption: string; AMin, AMax: Integer;
  out ACaptionLabel: TLabel): TDpccChoiceBox;
var
  mItems: TArray<string>;
  mValue: Integer;
begin
  mItems := nil;
  for mValue := AMin to AMax do
  begin
    mItems := mItems + [IntToStr(mValue)];
  end;
  Result := AddChoiceRow(ACaption, mItems, ACaptionLabel);
  // Eintrag 0 ist AMin; so lesen LoadFrom und SaveTo den Wert.
  Result.Tag := AMin;
end;

/// <summary>Breite einer Auswahl: längster Eintrag samt Pfeil.</summary>
function ChoiceWidth(APage: TDpccSettingsPage; ABox: TDpccChoiceBox; const AItems: array of string): Integer;
var
  mItem: string;
begin
  Result := 0;
  for mItem in AItems do
  begin
    Result := Max(Result, APage.TextWidthFor(ABox, mItem));
  end;
  Inc(Result, APage.ScaleValue(cChoiceArrow));
end;

type
  /// <summary>Zugriff auf die geschützte Schrift eines Elements.</summary>
  TControlFont = class(TControl);

function TDpccSettingsPage.TextWidthFor(AControl: TControl; const AText: string): Integer;
var
  mBitmap: TBitmap;
begin
  // Ohne Fenster messen (die IDE und die Tests bauen die Seite, bevor sie eines hat): Schrift des Elements auf der
  // Leinwand eines Bitmaps; die Höhe der Schrift ist schon auf die Skalierung des Elements umgerechnet.
  mBitmap := TBitmap.Create;
  try
    mBitmap.Canvas.Font.Assign(TControlFont(AControl).Font);
    Result := mBitmap.Canvas.TextWidth(AText);
  finally
    mBitmap.Free;
  end;
end;

function TDpccSettingsPage.CheckWidth(ACheck: TCheckBox): Integer;
begin
  Result := TextWidthFor(ACheck, ACheck.Caption) + ScaleValue(cCheckGlyph);
end;

procedure TDpccSettingsPage.ArrangeRows;
var
  mEntry: TDpccSettingsPageEntry;
  mFieldLeft, mRowWidth: Integer;
begin
  if not FBuilt then
  begin
    Exit;
  end;
  // Spalte der Felder: rechts von der längsten Beschriftung links eines Felds.
  mFieldLeft := ScaleValue(cIndent);
  for mEntry in FEntries do
  begin
    if (mEntry.Caption <> nil) and (mEntry.Control.Parent = mEntry.Caption.Parent) then
    begin
      mFieldLeft := Max(mFieldLeft, mEntry.Caption.Left + TextWidthFor(mEntry.Caption, mEntry.Caption.Caption));
    end;
  end;
  Inc(mFieldLeft, ScaleValue(cGap));
  // Auswahlen so breit wie ihr längster Eintrag; „Breite automatisch“ rechts neben den sichtbaren Zeilen.
  FAutoMinChars.SetBounds(mFieldLeft, FAutoMinChars.Top, ChoiceWidth(Self, FAutoMinChars, ['10']),
    FAutoMinChars.Height);
  FVisibleRows.SetBounds(mFieldLeft, FVisibleRows.Top, ChoiceWidth(Self, FVisibleRows, ['20']), FVisibleRows.Height);
  FListMode.SetBounds(mFieldLeft, FListMode.Top, ChoiceWidth(Self, FListMode,
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListModeFilter),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListModeAll),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsListModeRest)]), FListMode.Height);
  FPopupLook.SetBounds(mFieldLeft, FPopupLook.Top, ChoiceWidth(Self, FPopupLook,
    [TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPopupLookIntense),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPopupLookSubtle),
    TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsPopupLookPlain)]), FPopupLook.Height);
  // Kontrollkästchen so breit wie ihr Text.
  for mEntry in FEntries do
  begin
    if mEntry.Control is TCheckBox then
    begin
      mEntry.Control.Width := CheckWidth(TCheckBox(mEntry.Control));
    end;
  end;
  FAutoWidth.Left := FVisibleRows.Left + FVisibleRows.Width + ScaleValue(cGap);
  // „Verlauf zurücksetzen“ rechts neben dem Lernen.
  FResetHistory.SetBounds(FLearning.Left + FLearning.Width + ScaleValue(cGap), FResetHistory.Top,
    Max(ScaleValue(cButtonMinWidth), TextWidthFor(FResetHistory, FResetHistory.Caption) + ScaleValue(24)),
    FResetHistory.Height);
  // Feld der Quellordner über die ganze Breite; „Index neu aufbauen“ mit dem Ergebnis rechts daneben.
  mRowWidth := FExtraSourceFolders.Parent.Width;
  FExtraSourceFolders.SetBounds(ScaleValue(cIndent), FExtraSourceFolders.Top,
    Max(ScaleValue(120), mRowWidth - ScaleValue(cIndent)), FExtraSourceFolders.Height);
  FRebuild.SetBounds(ScaleValue(cIndent), FRebuild.Top,
    Max(ScaleValue(cButtonMinWidth), TextWidthFor(FRebuild, FRebuild.Caption) + ScaleValue(24)), FRebuild.Height);
  FRebuildInfo.SetBounds(FRebuild.Left + FRebuild.Width + ScaleValue(cGap), 0,
    Max(ScaleValue(60), FRebuildInfo.Parent.Width - FRebuild.Left - FRebuild.Width - ScaleValue(cGap)),
    FRebuildInfo.Parent.Height);
  // „Jetzt prüfen“ mit den Statuszeilen rechts daneben (Abschnitt IDE).
  FCheckIde.SetBounds(ScaleValue(cIndent), FCheckIde.Top,
    Max(ScaleValue(cButtonMinWidth), TextWidthFor(FCheckIde, FCheckIde.Caption) + ScaleValue(24)), FCheckIde.Height);
  FIdeStatus.SetBounds(FCheckIde.Left + FCheckIde.Width + ScaleValue(cGap), 0,
    Max(ScaleValue(60), FIdeStatus.Parent.Width - FCheckIde.Left - FCheckIde.Width - ScaleValue(cGap)),
    FIdeStatus.Parent.Height);
end;

procedure TDpccSettingsPage.CreateWnd;
begin
  inherited CreateWnd;
  ArrangeRows;
end;

procedure TDpccSettingsPage.Resize;
begin
  inherited Resize;
  ArrangeRows;
end;

procedure TDpccSettingsPage.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  inherited ChangeScale(M, D, isDpiChange);
  ArrangeRows;
end;

procedure TDpccSettingsPage.CMFontChanged(var AMessage: TMessage);
begin
  inherited;
  // Schrift des Dialogs (ParentFont): Beschriftungen werden breiter oder schmaler.
  ArrangeRows;
end;

function TDpccSettingsPage.ControlOf(const AName: string): TControl;
var
  mEntry: TDpccSettingsPageEntry;
begin
  for mEntry in FEntries do
  begin
    if SameText(mEntry.Item.Name, AName) then
    begin
      Exit(mEntry.Control);
    end;
  end;
  Result := nil;
end;

function TDpccSettingsPage.TitleOf(ASection: TDpccPageSection): TDpccSettingsTitle;
begin
  Result := FTitles[ASection];
end;

procedure TDpccSettingsPage.ToggleClick(Sender: TObject);
begin
  UpdateLocks;
end;

procedure TDpccSettingsPage.UpdateLocks;
var
  mEntry: TDpccSettingsPageEntry;
  mOn: Boolean;
begin
  if not FBuilt then
  begin
    Exit;
  end;
  mOn := FMaster.Checked;
  for mEntry in FEntries do
  begin
    // „Ablauf protokollieren“ (LOG1) auch bei Hauptschalter aus: Das Protokoll zeigt dann, warum dpcc nicht zuständig
    // ist.
    if (mEntry.Control = FMaster) or (mEntry.Control = FRebuild) or (mEntry.Control = FCheckIde) or
      (mEntry.Control = FDiagnose) then
    begin
      Continue;
    end;
    mEntry.Control.Enabled := mOn;
    if mEntry.Caption <> nil then
    begin
      mEntry.Caption.Enabled := mOn;
    end;
  end;
  // Werte beim Debuggen zeigt nur der eigene Tooltip.
  FDebugHoverValues.Enabled := mOn and FHoverTooltip.Checked;
  FResetHistory.Enabled := mOn and not FHistoryReset;
  // „Index neu aufbauen“ hängt wie bisher nicht am Hauptschalter, nur daran, ob die IDE-Schicht ihn ausführt und ob
  // er gerade im Hintergrund läuft.
  FRebuild.Enabled := Assigned(FOnRebuildIndex) and not FRebuildRunning;
  // „Jetzt prüfen“ liest nur; ohne IDE-Schicht (Tests ohne Haken) gesperrt.
  FCheckIde.Enabled := Assigned(FOnIdeStatus);
end;

procedure TDpccSettingsPage.LoadFrom(const ASettings: TDpccPluginSettings);
begin
  FMaster.Checked := ASettings.Enabled;
  FAutoMinChars.Choice := EnsureRange(ASettings.AutoMinChars, 0, TDpccPluginSettings.cMaxAutoMinChars) -
    FAutoMinChars.Tag;
  FListMode.Choice := Ord(TDpccListModes.ModeOf(ASettings.CompletionListMode));
  FVisibleRows.Choice := EnsureRange(ASettings.VisibleRows, TDpccPluginSettings.cMinVisibleRows,
    TDpccPluginSettings.cMaxVisibleRows) - FVisibleRows.Tag;
  FListWidth := ASettings.ListWidth;
  FAutoWidth.Checked := ASettings.ListWidth = 0;
  FLearning.Checked := ASettings.Learning;
  FAutoParentheses.Checked := ASettings.AutoParentheses;
  FCommitCharacters.Checked := ASettings.CommitCharacters;
  FAutoUses.Checked := ASettings.AutoUses;
  FParameterHints.Checked := ASettings.ParameterHints;
  FHoverTooltip.Checked := ASettings.HoverTooltip;
  FDebugHoverValues.Checked := ASettings.DebugHoverValues;
  FPopupLook.Choice := Ord(ASettings.PopupLook);
  FExtraSourceFolders.Text := ASettings.IndexExtraSourceFolders;
  FDiagnose.Checked := ASettings.Diagnose;
  UpdateLocks;
end;

procedure TDpccSettingsPage.SaveTo(var ASettings: TDpccPluginSettings);
begin
  ASettings.Enabled := FMaster.Checked;
  if FAutoMinChars.Choice >= 0 then
  begin
    ASettings.AutoMinChars := FAutoMinChars.Tag + FAutoMinChars.Choice;
  end;
  if (FListMode.Choice >= Ord(Low(TDpccListMode))) and (FListMode.Choice <= Ord(High(TDpccListMode))) then
  begin
    ASettings.CompletionListMode := TDpccListModes.cModeNames[TDpccListMode(FListMode.Choice)];
  end;
  if FVisibleRows.Choice >= 0 then
  begin
    ASettings.VisibleRows := FVisibleRows.Tag + FVisibleRows.Choice;
  end;
  // Automatisch: gezogene Breite vergessen; aus: die zuletzt gezogene bzw. eine mittlere Breite.
  if FAutoWidth.Checked then
  begin
    ASettings.ListWidth := 0;
  end
  else if FListWidth = 0 then
  begin
    ASettings.ListWidth := TDpccPluginSettings.cMinListWidth + 160;
  end
  else
  begin
    ASettings.ListWidth := FListWidth;
  end;
  ASettings.Learning := FLearning.Checked;
  ASettings.AutoParentheses := FAutoParentheses.Checked;
  ASettings.CommitCharacters := FCommitCharacters.Checked;
  ASettings.AutoUses := FAutoUses.Checked;
  ASettings.ParameterHints := FParameterHints.Checked;
  ASettings.HoverTooltip := FHoverTooltip.Checked;
  ASettings.DebugHoverValues := FDebugHoverValues.Checked;
  if (FPopupLook.Choice >= Ord(Low(TDpccLookLevel))) and (FPopupLook.Choice <= Ord(High(TDpccLookLevel))) then
  begin
    ASettings.PopupLook := TDpccLookLevel(FPopupLook.Choice);
  end;
  ASettings.IndexExtraSourceFolders := Trim(FExtraSourceFolders.Text);
  ASettings.Diagnose := FDiagnose.Checked;
  ASettings.Normalize;
end;

procedure TDpccSettingsPage.SetDiagnoseFile(const AValue: string);
begin
  FDiagnoseFile := AValue;
  FDiagnose.Hint := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsDiagnoseHint);
  if AValue <> '' then
  begin
    FDiagnose.Hint := FDiagnose.Hint + sLineBreak + TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsDiagnoseFile,
      [AValue]);
  end;
end;

procedure TDpccSettingsPage.ResetHistoryClick(Sender: TObject);
begin
  if Assigned(FOnResetHistory) then
  begin
    FOnResetHistory();
  end;
  FHistoryReset := True;
  UpdateLocks;
end;

procedure TDpccSettingsPage.SetOnRebuildIndex(const AValue: TFunc<string>);
begin
  FOnRebuildIndex := AValue;
  UpdateLocks;
end;

procedure TDpccSettingsPage.SetOnRebuildStatus(const AValue: TFunc<TDpccRebuildStatus>);
begin
  FOnRebuildStatus := AValue;
  // Seite neu geöffnet, während ein Neuaufbau noch läuft: gleich grau und mit Meldung.
  RefreshRebuild;
end;

procedure TDpccSettingsPage.RefreshRebuild;
var
  mStatus: TDpccRebuildStatus;
begin
  mStatus := Default(TDpccRebuildStatus);
  if Assigned(FOnRebuildStatus) then
  begin
    mStatus := FOnRebuildStatus();
  end;
  FRebuildRunning := mStatus.Running;
  if (mStatus.Text <> '') and (FRebuildInfo <> nil) then
  begin
    FRebuildInfo.Caption := mStatus.Text;
  end;
  if FRebuildRunning and (FRebuildTimer = nil) then
  begin
    // Gehört der Seite: wird mit ihr freigegeben, kein Verweis von außen.
    FRebuildTimer := TTimer.Create(Self);
    FRebuildTimer.Enabled := False;
    FRebuildTimer.Interval := 250;
    FRebuildTimer.OnTimer := RebuildTimerTick;
  end;
  if FRebuildTimer <> nil then
  begin
    FRebuildTimer.Enabled := FRebuildRunning;
  end;
  UpdateLocks;
end;

procedure TDpccSettingsPage.RebuildTimerTick(Sender: TObject);
begin
  RefreshRebuild;
end;

procedure TDpccSettingsPage.RebuildClick(Sender: TObject);
var
  mConfirmed: Boolean;
begin
  if not Assigned(FOnRebuildIndex) or FRebuildRunning then
  begin
    Exit;
  end;
  if Assigned(FConfirmRebuild) then
  begin
    mConfirmed := FConfirmRebuild();
  end
  else
  begin
    mConfirmed := MessageDlg(TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexRebuildConfirm),
      mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  end;
  if not mConfirmed then
  begin
    Exit;
  end;
  // Kehrt sofort zurück: Anhalten, Löschen und Neustart laufen im Hintergrund; den Fortschritt zeigt RefreshRebuild.
  FRebuildInfo.Caption := FOnRebuildIndex();
  if Assigned(FOnRebuildStatus) then
  begin
    RefreshRebuild;
  end;
end;

procedure TDpccSettingsPage.SetOnIdeStatus(const AValue: TFunc<string>);
begin
  FOnIdeStatus := AValue;
  if Assigned(FOnIdeStatus) then
  begin
    FIdeStatus.Caption := FOnIdeStatus();
  end
  else
  begin
    FIdeStatus.Caption := '';
  end;
  UpdateLocks;
end;

procedure TDpccSettingsPage.CheckIdeClick(Sender: TObject);
var
  mCursor: TCursor;
begin
  if not Assigned(FOnIdeStatus) then
  begin
    Exit;
  end;
  mCursor := Screen.Cursor;
  Screen.Cursor := crHourGlass;
  try
    FIdeStatus.Caption := FOnIdeStatus();
  finally
    Screen.Cursor := mCursor;
  end;
end;

end.
