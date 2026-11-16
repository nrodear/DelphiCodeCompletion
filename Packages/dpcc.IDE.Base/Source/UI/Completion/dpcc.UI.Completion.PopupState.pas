unit dpcc.UI.Completion.PopupState;

// Vervollständigungs-Popup (#410), unterste Stufe: Typen, Zustand und gemessene Höhen. Die Klasse ist nach
// Aufgaben in eine Kette geteilt, damit jede Stufe überschaubar bleibt:
//   TDpccCompletionPopupState (Zustand, Höhen) → TDpccCompletionPopupLayout (Lage von Liste, Panel und
//   Fenster, Panel-Schnittstelle) → TDpccCompletionPopupPainter (Zeichnen, Tooltip) → TDpccCompletionPopup
//   (dpcc.UI.Completion.Popup: Maus, Anzeige der Liste, Barrierefreiheit).
// Aufrufer verwenden nur TDpccCompletionPopup; Beschreibung des Aussehens dort.

interface

uses
  Vcl.Controls,
  Winapi.Messages,
  System.Classes,
  System.Types,
  Vcl.ExtCtrls,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Width,
  dpcc.Core.Completion.Ranking,
  dpcc.Core.Documentation.Layout,
  dpcc.UI.Popup.Window,
  dpcc.UI.Popup.Tip,
  dpcc.UI.Completion.Details;

type
  TDpccPositionEvent = reference to procedure(APosition: Integer);
  /// <summary>Gezogene Breiten in logischen Pixeln; AListWidth 0 = automatisch.</summary>
  TDpccWidthsEvent = reference to procedure(AListWidth, APanelWidth: Integer);
  TDpccPanelEvent = reference to procedure(ACollapsed: Boolean);
  /// <summary>Klick auf die Zeilenangabe der Warnleiste (#457); 0-basiert.</summary>
  TDpccSyntaxLineEvent = reference to procedure(ALine, ACharacter: Integer);

{$SCOPEDENUMS ON}
  TDpccChipEvent = reference to procedure(AChip: TDpccChip);
  TDpccOverloadEvent = reference to procedure(ADelta: Integer);
  /// <summary>Klick auf einen Verweis bzw. Link der XMLDoc im Panel (#654); AControl bei Strg+Klick.</summary>
  TDpccDocLinkEvent = reference to procedure(const ALink: TDpccDocLink; AControl: Boolean);
  TDpccDragKind = (None, ListWidth, PanelWidth);
  TDpccHitArea = (None, Splitter, Edge, Grip, PanelBar);
{$SCOPEDENUMS OFF}

  /// <summary>Zeilen-, Chip- und Fußzeilenhöhe: einmal gemessen, neu nach Schrift- oder Dichtewechsel.
  /// </summary>
  TDpccPopupMetrics = record
    RowHeight: Integer;
    ChipsHeight: Integer;
    FooterHeight: Integer;
    /// <summary>Dichte bei der Messung; Scale hängt an PPI, auch wenn die Schrift gleich bleibt.</summary>
    PPI: Integer;
    Valid: Boolean;
  end;

  /// <summary>Detailpanel (#424): Bereich, Seite, eingeklappt (#428) und Breite (#416).</summary>
  TDpccPopupPanel = record
    /// <summary>Panelbereich in dieser Sitzung belegt.</summary>
    Shown: Boolean;
    /// <summary>Panel links der Liste (rechts kein Platz).</summary>
    Left: Boolean;
    /// <summary>Vom Benutzer eingeklappt (Strg+Q, Klick auf die Leiste).</summary>
    Collapsed: Boolean;
    /// <summary>Weder rechts noch links Platz: für diese Lage eingeklappt.</summary>
    AutoCollapsed: Boolean;
    /// <summary>Breite in logischen Pixeln.</summary>
    Width: Integer;
  end;

  /// <summary>Filter-Chips (#422): Anzahlen, aktiver Chip und die zuletzt gezeichneten Flächen.</summary>
  TDpccPopupChips = record
    Counts: TDpccChipCounts;
    Active: TDpccChip;
    Visible: Boolean;
    Rects: TArray<TRect>;
    Kinds: TArray<TDpccChip>;
  end;

  /// <summary>Leerer Zustand (#423): Präfix ohne Treffer und Gesamtzahl.</summary>
  TDpccPopupEmpty = record
    Showing: Boolean;
    Prefix: string;
    Total: Integer;
  end;

  /// <summary>Ziehen einer Breite (#416) in Bildschirmkoordinaten.</summary>
  TDpccPopupDrag = record
    Kind: TDpccDragKind;
    StartX: Integer;
    StartWidth: Integer;
    /// <summary>-1, wenn Ziehen nach links verbreitert (Panel links der Liste).</summary>
    Sign: Integer;
  end;

  /// <summary>Ereignisse des Popups.</summary>
  TDpccPopupEvents = record
    OnSelect: TDpccPositionEvent;
    OnAccept: TDpccPositionEvent;
    OnWidthsChanged: TDpccWidthsEvent;
    OnPanelToggled: TDpccPanelEvent;
    OnChip: TDpccChipEvent;
    OnOverload: TDpccOverloadEvent;
    OnDocLink: TDpccDocLinkEvent;
    OnFavorite: TDpccPositionEvent;
    OnSyntaxLine: TDpccSyntaxLineEvent;
  end;

  /// <summary>Einstellungen der Darstellung (Beschreibung an den Eigenschaften von TDpccCompletionPopup).</summary>
  TDpccPopupOptions = record
    DimInherited: Boolean;
    ShowVariantBranch: Boolean;
    Limited: Boolean;
    Target: string;
    FavoritesEnabled: Boolean;
    SelectionMarker: Boolean;
  end;

  TDpccCompletionPopupState = class(TDpccPopupWindow)
  public const
    cDefaultVisibleRows = 9;
    cMinWidth = TDpccPopupWidth.cMinListWidth;
    cMaxWidth = TDpccPopupWidth.cMaxListWidth;
    cDefaultPanelWidth = 320;
    cCollapsedPanelWidth = 22;
  protected const
    /// <summary>Platz für das Kontrollkästchen im Mengenmodus (#448): Rand 7, Kästchen 13, Abstand 6.</summary>
    cCheckWidth = 19;
    /// <summary>Sternspalte der Favoriten (#458): Rand 4, Stern 12; das Badge rückt um so viel nach rechts.</summary>
    cStarWidth = 14;
  protected
    FItems: TDpccCompletionItems;
    FOrder: TArray<Integer>;
    FSelected: Integer;
    FTop: Integer;
    FVisibleRows: Integer;
    FAnchor: TRect;
    FPattern: string;
    /// <summary>Position der Überschrift „Weitere Einträge“ (#497); -1 ohne.</summary>
    FRestFrom: Integer;
    FSessionWidth: Integer;
    FSessionHeight: Integer;
    FEmpty: TDpccPopupEmpty;
    FDetailView: TDpccDetailView;
    FPanel: TDpccPopupPanel;
    /// <summary>Gezogene Breite der Liste in logischen Pixeln, 0 = automatisch (#416).</summary>
    FManualListWidth: Integer;
    FMetrics: TDpccPopupMetrics;
    FChips: TDpccPopupChips;
    // Unvollständiger Code (#457): Hinweis und Fläche der Zeilenangabe.
    FSyntax: TDpccSyntaxNotice;
    FSyntaxLink: TRect;
    // Hinweis in der Fußzeile (#458).
    FNotice: string;
    // Tooltip für gekürzte Zeilen (#420): je sichtbarer Zeile gekürzt ja/nein, Zeile unter der Maus.
    FTip: TDpccTextTip;
    FTipTimer: TTimer;
    FTruncated: TArray<Boolean>;
    FHoverPosition: Integer;
    FDrag: TDpccPopupDrag;
    FEvents: TDpccPopupEvents;
    FOptions: TDpccPopupOptions;
    // Gerade gezeichnete Zeile: gedämpft (#419, #476, #497) bzw. Aktion in Akzentfarbe (#444).
    FDimRow: Boolean;
    FActionRow: Boolean;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
    procedure InvalidateMetrics;
    procedure EnsureMetrics;
    function Pad: Integer;
    function RowHeight: Integer;
    function FooterHeight: Integer;
    function ScrollReserve: Integer;
    function RowCount: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

uses
  System.Math,
  dpcc.UI.Popup.Accessibility,
  dpcc.UI.Completion.Strings;

const
  /// <summary>Verweilen auf einer gekürzten Zeile, bis der volle Text erscheint (#420).</summary>
  cTipDelayMs = 600;

{ TDpccCompletionPopupState }

constructor TDpccCompletionPopupState.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  SetAccessible(cUiaListControlType, TDpccCompletionStrings.Text(TDpccCompletionTextId.AccessCompletion));
  FVisibleRows := cDefaultVisibleRows;
  FSelected := -1;
  FRestFrom := -1;
  FDetailView := TDpccDetailView.Create;
  FHoverPosition := -1;
  FTip := TDpccTextTip.Create(Self);
  FTipTimer := TTimer.Create(Self);
  FTipTimer.Enabled := False;
  FTipTimer.Interval := cTipDelayMs;
  // lsp-ignore: control-fixed-bounds -- Record in logischen Pixeln, skaliert beim Zeichnen
  FPanel.Width := cDefaultPanelWidth;
  FOptions.SelectionMarker := True;
  FOptions.ShowVariantBranch := True;
end;

destructor TDpccCompletionPopupState.Destroy;
begin
  FDetailView.Free;
  inherited Destroy;
end;

procedure TDpccCompletionPopupState.CMFontChanged(var Message: TMessage);
begin
  // Erst die Basis: sie leitet die UI-Schrift aus der Editorschrift ab.
  inherited;
  InvalidateMetrics;
end;

procedure TDpccCompletionPopupState.InvalidateMetrics;
begin
  FMetrics.Valid := False;
end;

procedure TDpccCompletionPopupState.EnsureMetrics;
var
  mUIHeight: Integer;
begin
  // Dichte zusätzlich prüfen: Scale hängt an PPI, auch wenn die Schrift gleich bleibt.
  if FMetrics.Valid and (FMetrics.PPI = PPI) then
  begin
    Exit;
  end;
  Canvas.Font := UIFont;
  mUIHeight := Canvas.TextHeight('Wg');
  Canvas.Font := Font;
  FMetrics.RowHeight := Max(Canvas.TextHeight('Wg') + Scale(9), Scale(24));
  FMetrics.ChipsHeight := mUIHeight + Scale(12);
  FMetrics.FooterHeight := mUIHeight + Scale(10);
  FMetrics.PPI := PPI;
  FMetrics.Valid := True;
end;

function TDpccCompletionPopupState.Pad: Integer;
begin
  Result := Scale(4);
end;

function TDpccCompletionPopupState.RowHeight: Integer;
begin
  EnsureMetrics;
  Result := FMetrics.RowHeight;
end;

function TDpccCompletionPopupState.FooterHeight: Integer;
begin
  EnsureMetrics;
  Result := FMetrics.FooterHeight;
end;

function TDpccCompletionPopupState.ScrollReserve: Integer;
begin
  Result := Scale(8);
end;

function TDpccCompletionPopupState.RowCount: Integer;
begin
  Result := Min(FVisibleRows, Length(FOrder));
end;

end.
