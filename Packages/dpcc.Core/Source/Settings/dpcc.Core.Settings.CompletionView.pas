unit dpcc.Core.Settings.CompletionView;

// Was Tools › Optionen › Fremdhersteller › dpcc zeigt und was fest verdrahtet ist (seit OPT1), ohne VCL und ohne
// Open Tools API:
// - Seit OPT1 gibt es genau eine Seite „dpcc“ ohne Unterseiten (früher Allgemein, Vervollständigung, Einfügen, Hints)
//   und ohne Baum, Suche, Filter und Geändert-Markierung. cPageItems ist ihr Aufbau: Hauptschalter, dann die
//   Abschnitte Vervollständigung, Beim Übernehmen, Parameter-Hint und Tooltip, Index mit zwölf Optionen und zwei
//   Knöpfen. Die Seite (dpcc.UI.Settings.Page) baut genau diese Liste; der Test prüft beides gegeneinander.
// - TDpccFixedSettings: Optionen, die es seit OPT1 nicht mehr auf der Seite gibt, gelten mit ihrer bisherigen Vorgabe.
//   Abweichende alte Werte in der Registry bleiben liegen und werden still ignoriert (Apply in den wirksamen
//   Einstellungen der IDE-Schicht). hints.xmlDocMaxLines bleibt über settings.json einstellbar (der Server liest die
//   Datei selbst); „XMLDoc beim Öffnen“ (hints.xmlDocExpand) gibt es nicht mehr.
// - Einstellungen des Servers (settings.json, dpcc.json) zeigt dpcc seit S2 nicht; die Seite „Tastenkonflikte“ gibt
//   es seit Rückbau R5 nicht mehr.
// Die Werte selbst bleiben unangetastet (Registry, settings.json, dpcc.json); was hier fehlt, zeigt dpcc nur nicht an.

interface

uses
  dpcc.Core.Settings.Catalog,
  dpcc.Core.Settings.Plugin;

type
  /// <summary>Wo eine Einstellung steht: gar nicht oder auf der Seite „dpcc“.</summary>
  TDpccSettingPlace = (spHidden, spMain);

  /// <summary>Abschnitt der Seite „dpcc“: oben der Hauptschalter, darunter die Abschnitte mit Überschrift.</summary>
  TDpccPageSection = (psMaster, psCompletion, psCommit, psHints, psIndex);

  /// <summary>Art eines Elements der Seite.</summary>
  TDpccPageItemKind = (pkSetting, pkButton);

  /// <summary>Element der Seite „dpcc“ in der Reihenfolge der Anzeige.</summary>
  TDpccPageItem = record
    Section: TDpccPageSection;
    Kind: TDpccPageItemKind;
    /// <summary>pkSetting: Name in TDpccPluginSettings.Load/Save (Registry-Name); pkButton: Kennung des Knopfs
    /// (TDpccCompletionView.cResetHistory, cRebuildIndex).</summary>
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
    /// <summary>Ort der Plugin-Einstellung AEntry; spHidden = nicht mehr angezeigt.</summary>
    class function PlaceOf(const AEntry: TDpccCatalogEntry): TDpccSettingPlace; static;
    /// <summary>Zeigt dpcc die Plugin-Einstellung AEntry noch an?</summary>
    class function ShowsSetting(const AEntry: TDpccCatalogEntry): Boolean; static;
    /// <summary>Wie ShowsSetting nach Registry-Name; False, wenn der Katalog den Namen nicht kennt.</summary>
    class function ShowsName(ACatalog: TDpccSettingsCatalog; const AName: string): Boolean; static;
  end;

  /// <summary>Optionen, die seit OPT1 nicht mehr auf der Seite stehen: Sie gelten fest mit ihrer bisherigen
  /// Vorgabe. Ein abweichender alter Wert in der Registry bleibt liegen und wirkt nicht mehr.</summary>
  TDpccFixedSettings = class
  public const
    /// <summary>Verzögerung bis zum Öffnen der Liste nach „.“ (ARG-046).</summary>
    cOpenDelayMs = 150;
    /// <summary>Favoriten anheften (Strg+D, #458); favorites.json bleibt.</summary>
    cFavorites = True;
    /// <summary>Geerbte Member nachrangig und nach Klasse gruppiert (#419).</summary>
    cGroupInherited = True;
    /// <summary>Zweig varianter Record-Felder zeigen (#846).</summary>
    cCompletionVariantBranch = True;
    /// <summary>Listenmodus gilt nur für Mitgliederlisten nach „.“ (#497).</summary>
    cCompletionListScope = 'members';
    /// <summary>Vorschau des gewählten Eintrags im Editor (#434): aus.</summary>
    cPreview = False;
    /// <summary>Schreibweise beim Übernehmen korrigieren (#433).</summary>
    cFixCase = True;
    /// <summary>Platzhalter von Format im Parameter-Hint zuordnen und einfärben (#451).</summary>
    cFormatPlaceholders = True;
  public
    /// <summary>Registry-Namen der fest verdrahteten Einstellungen.</summary>
    class function Names: TArray<string>; static;
    /// <summary>Setzt in ASettings die fest verdrahteten Werte; alles andere bleibt.</summary>
    class procedure Apply(var ASettings: TDpccPluginSettings); static;
  end;

implementation

uses
  System.StrUtils;

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

class function TDpccCompletionView.PlaceOf(const AEntry: TDpccCatalogEntry): TDpccSettingPlace;
begin
  // Einstellungen des Servers haben seit S2 keine Seite mehr.
  if (AEntry.Source = asPlugin) and MatchText(AEntry.Name, SettingNames) then
  begin
    Exit(spMain);
  end;
  Result := spHidden;
end;

class function TDpccCompletionView.ShowsSetting(const AEntry: TDpccCatalogEntry): Boolean;
begin
  Result := PlaceOf(AEntry) <> spHidden;
end;

class function TDpccCompletionView.ShowsName(ACatalog: TDpccSettingsCatalog; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := ACatalog.IndexOfName(AName);
  Result := (mIndex >= 0) and ShowsSetting(ACatalog[mIndex]);
end;

{ TDpccFixedSettings }

class function TDpccFixedSettings.Names: TArray<string>;
begin
  Result := ['OpenDelayMs', 'Favorites', 'GroupInherited', 'CompletionVariantBranch', 'CompletionListScope', 'Preview',
    'FixCase', 'FormatPlaceholders'];
end;

class procedure TDpccFixedSettings.Apply(var ASettings: TDpccPluginSettings);
begin
  ASettings.OpenDelayMs := cOpenDelayMs;
  ASettings.Favorites := cFavorites;
  ASettings.GroupInherited := cGroupInherited;
  ASettings.CompletionVariantBranch := cCompletionVariantBranch;
  ASettings.CompletionListScope := cCompletionListScope;
  ASettings.Preview := cPreview;
  ASettings.FixCase := cFixCase;
  ASettings.FormatPlaceholders := cFormatPlaceholders;
end;

end.
