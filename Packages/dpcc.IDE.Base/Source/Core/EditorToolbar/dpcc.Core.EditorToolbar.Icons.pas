unit dpcc.Core.EditorToolbar.Icons;

// dpcc-Editorleiste (#1101), Symbole je Befehl ohne VCL und OTA: IconOf
// ordnet bekannten Befehlen der Befehlspalette ein Symbol zu; unbekannte
// zeigen den ersten Buchstaben ihrer Beschriftung (Letter). Die Formen stehen
// in dpcc.Core.EditorToolbar.Glyphs.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Symbole der Editorleiste (dpcc.Core.EditorToolbar.Glyphs); Letter = erster Buchstabe der
  /// Beschriftung.</summary>
  TDpccToolbarIcon = (Letter, InterfacePart, ImplementationPart, UsesClause, Initialization_, Return, Back,
    Forward, Toggle, TestUnit, UnitSearch, FindMethod, QuickOpen, CodeActions, Format, Problems, Outline,
    Palette, More, Gear,
    // Designer-Leiste (#1442).
    ComponentSearch, NonVisual, NonVisualHidden, SelectParent, TabOrder, AlignControls,
    // Eigene Knöpfe der Designer-Ansichten (#605 bis #612).
    MeasureDistances, ResizePreview, ScalePreview, NameSuggest, Structure, DataBindings, ExtractFrame, EventMap,
    // Gleiche auswählen (#738), Anordnen (#730 ff.), Abstandsgriffe (#734), gemeinsame Größengriffe (#737),
    // Schnellleiste (#735), Lupe (#743), Eigenschaften suchen (#524), Verwendungen im Code (#750), Rückgängig im
    // Designer (#1887).
    SelectSimilar, Arrange, GapHandles, MultiResize, SelectionBar, Magnifier, PropertySearch, Usages, DesignerUndo);
{$SCOPEDENUMS OFF}

  TDpccToolbarIcons = class
  public
    class function IconOf(const AId: string): TDpccToolbarIcon; static;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Settings.ToolbarItems;

class function TDpccToolbarIcons.IconOf(const AId: string): TDpccToolbarIcon;
const
  cIds: array[0..18] of string = (TDpccToolbarItems.cGotoInterface, TDpccToolbarItems.cGotoImplementation,
    TDpccToolbarItems.cGotoUses, TDpccToolbarItems.cGotoInitialization, TDpccToolbarItems.cReturnFromSection,
    'dpcc.NavBack', 'dpcc.NavForward', 'dpcc.ToggleMethod', 'dpcc.SwitchTestUnit', 'dpcc.UnitSearch',
    TDpccToolbarItems.cFindMethod, 'dpcc.QuickOpen', 'dpcc.CodeActions', 'dpcc.FormatCode',
    'dpcc.ProblemsWindow', 'dpcc.Outline', TDpccToolbarItems.cCommandPalette, TDpccToolbarItems.cCustomize,
    'dpcc.SymbolSearch');
  cIcons: array[0..18] of TDpccToolbarIcon = (TDpccToolbarIcon.InterfacePart,
    TDpccToolbarIcon.ImplementationPart, TDpccToolbarIcon.UsesClause, TDpccToolbarIcon.Initialization_,
    TDpccToolbarIcon.Return, TDpccToolbarIcon.Back, TDpccToolbarIcon.Forward, TDpccToolbarIcon.Toggle,
    TDpccToolbarIcon.TestUnit, TDpccToolbarIcon.UnitSearch, TDpccToolbarIcon.FindMethod,
    TDpccToolbarIcon.QuickOpen, TDpccToolbarIcon.CodeActions, TDpccToolbarIcon.Format,
    TDpccToolbarIcon.Problems, TDpccToolbarIcon.Outline, TDpccToolbarIcon.Palette, TDpccToolbarIcon.Gear,
    TDpccToolbarIcon.FindMethod);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(cIds) do
  begin
    if SameText(cIds[mIndex], AId) then
    begin
      Exit(cIcons[mIndex]);
    end;
  end;
  Result := TDpccToolbarIcon.Letter;
end;

end.
