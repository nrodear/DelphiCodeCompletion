unit dpcc.Core.Settings.CompletionView;

// Was Tools › Optionen › Fremdhersteller › dpcc zeigt und was fest verdrahtet ist (seit OPT1), ohne VCL und ohne
// Open Tools API:
// - Es gibt genau eine Seite „dpcc“ ohne Unterseiten, Baum, Suche, Filter und Geändert-Markierung. cPageItems ist ihr
//   Aufbau: Hauptschalter, dann die Abschnitte Vervollständigung, Beim Übernehmen, Parameter-Hint und Tooltip, Index
//   mit zwölf Optionen und zwei Knöpfen. Die Seite (dpcc.UI.Settings.Page) baut genau diese Liste, und
//   TDpccPluginSettings speichert genau diese Optionen; die Tests prüfen beides gegeneinander.
// - TDpccFixedSettings: Optionen, die es seit OPT1 nicht mehr auf der Seite gibt, gelten mit ihrer bisherigen Vorgabe.
//   Seit OPT2 lesen die Stellen, die sie brauchen, die Werte direkt von hier; TDpccPluginSettings hat keine Felder
//   mehr dafür. Abweichende alte Werte in der Registry bleiben liegen und werden nicht gelesen. hints.xmlDocMaxLines
//   bleibt über settings.json einstellbar (TDpccPluginSettings.XmlDocMaxLines, nur gelesen). Die Vorschau im Editor
//   (completion.preview, fest aus) ist samt Code entfallen.
// - Einstellungen des Servers (settings.json, dpcc.json) zeigt dpcc seit S2 nicht.

interface

type
  /// <summary>Abschnitt der Seite „dpcc“: oben der Hauptschalter, darunter die Abschnitte mit Überschrift.</summary>
  TDpccPageSection = (psMaster, psCompletion, psCommit, psHints, psIndex);

  /// <summary>Art eines Elements der Seite.</summary>
  TDpccPageItemKind = (pkSetting, pkButton);

  /// <summary>Element der Seite „dpcc“ in der Reihenfolge der Anzeige.</summary>
  TDpccPageItem = record
    Section: TDpccPageSection;
    Kind: TDpccPageItemKind;
    /// <summary>pkSetting: Name in TDpccPluginSettings.Load/Save (Registry-Name); pkButton: Kennung des Knopfs
    /// (cPageResetHistory, cPageRebuildIndex).</summary>
    Name: string;
  end;

const
  /// <summary>Kennung des Knopfs „Verlauf zurücksetzen“ (lernende Gewichtung, #418).</summary>
  cPageResetHistory = 'ResetHistory';
  /// <summary>Kennung des Knopfs „Index neu aufbauen“ (S4).</summary>
  cPageRebuildIndex = 'RebuildIndex';
  /// <summary>Aufbau der Seite „dpcc“ (OPT1): Hauptschalter, zwölf Optionen in vier Abschnitten und zwei Knöpfe.
  /// ListWidth ist „Breite automatisch“ (0 = automatisch) in der Zeile der sichtbaren Zeilen.</summary>
  cPageItems: array[0..14] of TDpccPageItem = (
    (Section: psMaster; Kind: pkSetting; Name: 'Enabled'),
    (Section: psCompletion; Kind: pkSetting; Name: 'AutoMinChars'),
    (Section: psCompletion; Kind: pkSetting; Name: 'CompletionListMode'),
    (Section: psCompletion; Kind: pkSetting; Name: 'VisibleRows'),
    (Section: psCompletion; Kind: pkSetting; Name: 'ListWidth'),
    (Section: psCompletion; Kind: pkSetting; Name: 'Learning'),
    (Section: psCompletion; Kind: pkButton; Name: cPageResetHistory),
    (Section: psCommit; Kind: pkSetting; Name: 'AutoParentheses'),
    (Section: psCommit; Kind: pkSetting; Name: 'CommitCharacters'),
    (Section: psCommit; Kind: pkSetting; Name: 'AutoUses'),
    (Section: psHints; Kind: pkSetting; Name: 'ParameterHints'),
    (Section: psHints; Kind: pkSetting; Name: 'HoverTooltip'),
    (Section: psHints; Kind: pkSetting; Name: 'DebugHoverValues'),
    (Section: psIndex; Kind: pkSetting; Name: 'IndexExtraSourceFolders'),
    (Section: psIndex; Kind: pkButton; Name: cPageRebuildIndex));

type
  TDpccCompletionView = class
  public
    /// <summary>Namen der Einstellungen auf der Seite in der Reihenfolge von cPageItems (mit Hauptschalter).
    /// </summary>
    class function SettingNames: TArray<string>; static;
  end;

  /// <summary>Optionen, die seit OPT1 nicht mehr auf der Seite stehen: Sie gelten fest mit ihrer bisherigen
  /// Vorgabe. Ein abweichender alter Wert in der Registry bleibt liegen und wirkt nicht mehr.</summary>
  TDpccFixedSettings = class
  public const
    /// <summary>Verzögerung bis zum Öffnen der Liste nach „.“ (ARG-046, früher completion.openDelayMs).</summary>
    cOpenDelayMs = 150;
    /// <summary>Favoriten anheften (Strg+D, #458, früher completion.favorites); favorites.json bleibt.</summary>
    cFavorites = True;
    /// <summary>Geerbte Member nachrangig, nach Klasse gruppiert und gedämpft (#419, früher
    /// completion.groupInherited).</summary>
    cGroupInherited = True;
    /// <summary>Zweig varianter Record-Felder zeigen (#846, früher completion.variantBranch).</summary>
    cCompletionVariantBranch = True;
    /// <summary>Listenmodus gilt nur für Mitgliederlisten nach „.“ (#497, früher completion.listMode.scope).
    /// </summary>
    cCompletionListScope = 'members';
    /// <summary>Schreibweise beim Übernehmen korrigieren (#433, früher completion.fixCase).</summary>
    cFixCase = True;
    /// <summary>Platzhalter von Format im Parameter-Hint zuordnen und einfärben (#451, früher
    /// completion.formatPlaceholders).</summary>
    cFormatPlaceholders = True;
  end;

implementation

{ TDpccCompletionView }

class function TDpccCompletionView.SettingNames: TArray<string>;
var
  mItem: TDpccPageItem;
begin
  Result := nil;
  for mItem in cPageItems do
  begin
    if mItem.Kind = pkSetting then
    begin
      Result := Result + [mItem.Name];
    end;
  end;
end;

end.
