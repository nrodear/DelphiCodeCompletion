unit dpcc.UI.Completion.PopupState;

// Vervollständigungs-Popup (#410), unterste Stufe: Typen, Zustand und gemessene Höhen. Die Klasse ist nach
// Aufgaben in eine Kette geteilt, damit jede Stufe überschaubar bleibt:
//   TDpccCompletionPopupState (Zustand, Höhen) → TDpccCompletionPopupLayout (Lage von Liste und Fenster) →
//   TDpccCompletionPopupPainter (Zeichnen, Tooltip) → TDpccCompletionPopup (dpcc.UI.Completion.Popup: Maus,
//   Anzeige der Liste, Barrierefreiheit).
// Aufrufer verwenden nur TDpccCompletionPopup; Beschreibung des Aussehens dort.
// Schlicht (S6): Zeilen in der UI-Schrift, so hoch wie die Zeilen des Hover-Tooltips (Schrifthöhe + cRowPad);
// flacher Rahmen (FlatFrame) wie Hover und Menüs der IDE. Seit S7a ist das das einzige Aussehen: Filter-Chips,
// Detailpanel, Sternspalte, Badges und Auswahlmarke sind entfernt.

interface

uses
  Vcl.Controls,
  Winapi.Messages,
  System.Classes,
  System.Types,
  Vcl.ExtCtrls,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Width,
  dpcc.UI.Popup.Window,
  dpcc.UI.Popup.Tip;

type
  TDpccPositionEvent = reference to procedure(APosition: Integer);
  /// <summary>Gezogene Breite der Liste in logischen Pixeln (#416); 0 = automatisch.</summary>
  TDpccWidthEvent = reference to procedure(AListWidth: Integer);
  /// <summary>Klick auf die Zeilenangabe der Warnleiste (#457); 0-basiert.</summary>
  TDpccSyntaxLineEvent = reference to procedure(ALine, ACharacter: Integer);

{$SCOPEDENUMS ON}
  /// <summary>Rechter Rand des Fensters (Breite ziehen, #416) bzw. dessen unteres Ende (Doppelklick: automatische
  /// Breite).</summary>
  TDpccHitArea = (None, Edge, Corner);
{$SCOPEDENUMS OFF}

  /// <summary>Zeilen-, Warnleisten- und Fußzeilenhöhe: einmal gemessen, neu nach Schrift- oder Dichtewechsel.
  /// </summary>
  TDpccPopupMetrics = record
    RowHeight: Integer;
    SyntaxHeight: Integer;
    FooterHeight: Integer;
    /// <summary>Dichte bei der Messung; Scale hängt an PPI, auch wenn die Schrift gleich bleibt.</summary>
    PPI: Integer;
    Valid: Boolean;
  end;

  /// <summary>Leerer Zustand (#423): Präfix ohne Treffer und Gesamtzahl.</summary>
  TDpccPopupEmpty = record
    Showing: Boolean;
    Prefix: string;
    Total: Integer;
  end;

  /// <summary>Ziehen der Breite der Liste am rechten Rand (#416) in Bildschirmkoordinaten.</summary>
  TDpccPopupDrag = record
    Active: Boolean;
    StartX: Integer;
    StartWidth: Integer;
  end;

  /// <summary>Ereignisse des Popups.</summary>
  TDpccPopupEvents = record
    OnSelect: TDpccPositionEvent;
    OnAccept: TDpccPositionEvent;
    OnWidthChanged: TDpccWidthEvent;
    OnSyntaxLine: TDpccSyntaxLineEvent;
  end;

  /// <summary>Einstellungen der Darstellung (Beschreibung an den Eigenschaften von TDpccCompletionPopup).</summary>
  TDpccPopupOptions = record
    DimInherited: Boolean;
    ShowVariantBranch: Boolean;
    Limited: Boolean;
    Target: string;
  end;

  TDpccCompletionPopupState = class(TDpccPopupWindow)
  public const
    cDefaultVisibleRows = 9;
    cMinWidth = TDpccPopupWidth.cMinListWidth;
    cMaxWidth = TDpccPopupWidth.cMaxListWidth;
  protected const
    /// <summary>Platz für das Kontrollkästchen im Mengenmodus (#448): Rand 7, Kästchen 13, Abstand 6.</summary>
    cCheckWidth = 19;
    /// <summary>Maße wie im Hover-Tooltip (logische Pixel): Zeile = Schrifthöhe + cRowPad, Text cInset vom Rand
    /// der Zeile, Art-Spalte so breit wie cKindSample plus cKindGap, Abstand vor dem Detail bzw. der Unit cGap.
    /// </summary>
    cRowPad = 9;
    cInset = 4;
    cKindSample = 'constructor';
    cKindGap = 24;
    cGap = 12;
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
    /// <summary>Gezogene Breite der Liste in logischen Pixeln, 0 = automatisch (#416).</summary>
    FManualListWidth: Integer;
    FMetrics: TDpccPopupMetrics;
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
    // Gerade gezeichnete Zeile: gedämpft (#419, #476, #497).
    FDimRow: Boolean;
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
  FHoverPosition := -1;
  FTip := TDpccTextTip.Create(Self);
  FTipTimer := TTimer.Create(Self);
  FTipTimer.Enabled := False;
  FTipTimer.Interval := cTipDelayMs;
  FOptions.ShowVariantBranch := True;
  // Schlicht (S6): flach wie der Hover-Tooltip und die Menüs der IDE.
  FlatFrame := True;
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
  // Wie eine Zeile des Hover-Tooltips bzw. der Code-Insight-Liste: UI-Schrift + cRowPad.
  FMetrics.RowHeight := mUIHeight + Scale(cRowPad);
  FMetrics.SyntaxHeight := mUIHeight + Scale(12);
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
