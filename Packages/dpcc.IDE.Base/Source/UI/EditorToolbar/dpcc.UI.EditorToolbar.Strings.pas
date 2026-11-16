unit dpcc.UI.EditorToolbar.Strings;

// Oberflächentexte des Features Editorleiste auf Deutsch und Englisch. Die Sprache bestimmt
// `TDpccStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `dpcc.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TDpccEditorToolbarTextId = (
    FindMethodPrompt, FindMethodNoOutline, EditorToolbarCustomizeTitle, EditorToolbarAvailable,
    EditorToolbarCurrent, EditorToolbarSeparator, EditorToolbarAddHint, EditorToolbarRemoveHint,
    EditorToolbarUpHint, EditorToolbarDownHint, EditorToolbarRestoreDefault, EditorToolbarOk, EditorToolbarCancel);

  TDpccEditorToolbarStrings = class
  public
    class function Text(AId: TDpccEditorToolbarTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TDpccEditorToolbarTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  dpcc.UI.Strings;

const
  cTexts: array[TDpccLanguage, TDpccEditorToolbarTextId] of string = (
    (
     'Methode in %s',
     'dpcc: Die Gliederung dieser Datei ist noch nicht da; gleich noch einmal versuchen.',
     'dpcc-Editorleiste anpassen',
     'Verfügbare Befehle (Befehlspalette)',
     'In der Leiste',
     '— Trennstrich —',
     'Hinzufügen',
     'Entfernen',
     'Nach oben',
     'Nach unten',
     'Standard wiederherstellen',
     'OK',
     'Abbrechen'),
    (
     'Method in %s',
     'dpcc: The outline of this file is not ready yet; try again in a moment.',
     'Customize dpcc editor toolbar',
     'Available commands (command palette)',
     'In the toolbar',
     '— Separator —',
     'Add',
     'Remove',
     'Move up',
     'Move down',
     'Restore default',
     'OK',
     'Cancel'));

{ TDpccEditorToolbarStrings }

class function TDpccEditorToolbarStrings.Text(AId: TDpccEditorToolbarTextId): string;
begin
  Result := cTexts[TDpccStrings.Language, AId];
end;

class function TDpccEditorToolbarStrings.Fmt(AId: TDpccEditorToolbarTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
