unit dpcc.Core.Settings.CompletionView;

// Completion-Schnitt (docs\Konzept-Completion-Schnitt.md): Was Tools › Optionen › Drittanbieter › dpcc noch
// zeigt. Eine Stelle für alle Seiten, ohne VCL und ohne Open Tools API:
// - Plugin-Einstellungen (Optionsseite „dpcc“, ihre Suche, Suche der Befehlspalette): die Seiten (x-page)
//   Vervollständigung, Einfügen und Hints, dazu aus Allgemein der Hauptschalter (completion.enabled), die
//   Tasten für Vervollständigung und Parameter-Hint (Seite „Tastenkonflikte“) und die XMLDoc-Anzeige im
//   Detailpanel (hints.xmlDoc*). Pfad und Betriebsart eines eigenen Server-Prozesses entfallen seit S1, die Seite
//   „Robustheit“ und die Extras des Hovers seit S3, die Seite „Index“ seit S4 (Umfang, Verwendungen und
//   Speichergrenze fest; „Index neu aufbauen“ steht als Knopf auf „Allgemein“). Seit S6 ist die Liste schlicht
//   wie die Code-Insight-Liste der IDE; seit S7a gibt es Filter-Chips, Detailpanel und Auswahlmarke auch als
//   Einstellung nicht mehr, ebenso die gelernten Vorschläge (suggestions.*).
// - Einstellungen des Servers (settings.json, dpcc.json) zeigt dpcc seit S2 nicht mehr: Die Seite „dpcc › Server“
//   mit dem Dialog für globale und Projekt-Einstellungen ist weg; der Server im IDE-Prozess liest beide Dateien
//   weiter selbst.
// - Tasten auf der Seite „Tastenkonflikte“: nur Vervollständigung und Parameter-Hint.
// Die Werte selbst bleiben unangetastet (Registry, settings.json, dpcc.json); was hier fehlt, zeigt dpcc nur
// nicht mehr an.
// Seit S8 gibt es die versteckten Schalter ohne Wirkung der Reiter Allgemein und Hints auch als Einstellung nicht
// mehr (Statusfeld, Diagnosemodus, Tastenkürzel-Tipps, Projektdatei, Inlay-Hints, Brotkrumenleiste, Minimap usw.);
// ShowsKey (für die Seite „Tastenkonflikte“, seit Rückbau R5 weg) entfällt mit dpcc.Core.Commands.KeyConflicts.

interface

uses
  dpcc.Core.Settings.Catalog;

type
  /// <summary>Wo eine Einstellung steht: gar nicht, auf der Seite „dpcc“ oder auf „Tastenkonflikte“. Die Seite
  /// „Server“ gibt es seit S2 nicht mehr.</summary>
  TDpccSettingPlace = (spHidden, spMain, spKeys);

  TDpccCompletionView = class
  public const
    /// <summary>Überschrift des Reiters Editor, auf dem nur noch Hover und XMLDoc stehen (gleich in beiden
    /// Sprachen).</summary>
    cHintsCaption = 'Hints';
  public
    /// <summary>Ort der Plugin-Einstellung AEntry; spHidden = nicht mehr angezeigt.</summary>
    class function PlaceOf(const AEntry: TDpccCatalogEntry): TDpccSettingPlace; static;
    /// <summary>Zeigt dpcc die Plugin-Einstellung AEntry noch an (auf irgendeiner Seite)?</summary>
    class function ShowsSetting(const AEntry: TDpccCatalogEntry): Boolean; static;
    /// <summary>Wie ShowsSetting nach Registry-Name; False, wenn der Katalog den Namen nicht kennt.</summary>
    class function ShowsName(ACatalog: TDpccSettingsCatalog; const AName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

const
  /// <summary>Seiten (x-page) der Plugin-Einstellungen, die ganz bleiben.</summary>
  cPluginPages: array[0..2] of string = ('Vervollständigung', 'Einfügen', 'Hints'); // german-ok x-page
  /// <summary>Einzelne Plugin-Einstellungen (x-key) anderer Seiten: Hauptschalter und, seit der
  /// Speicher-Optimierung c1, „Office-Typbibliotheken und WinRT vorab indizieren“ auf „Allgemein“.</summary>
  cPluginKeys: array[0..1] of string = ('completion.enabled', 'index.officeAndWinRt');
  /// <summary>Tasten (x-key) auf der Seite „Tastenkonflikte“.</summary>
  cKeyKeys: array[0..3] of string = ('keys.completion', 'keys.completionPriority', 'keys.signature',
    'keys.signaturePriority');
  /// <summary>XMLDoc im Hover (hints.xmlDocExpand, hints.xmlDocMaxLines), auch wenn x-page Editor sagt.</summary>
  cHintsPrefix = 'hints.';
  cKeysPage = 'Tastenkonflikte'; // german-ok x-page

{ TDpccCompletionView }

class function TDpccCompletionView.PlaceOf(const AEntry: TDpccCatalogEntry): TDpccSettingPlace;
begin
  // Einstellungen des Servers haben seit S2 keine Seite mehr.
  if AEntry.Source <> asPlugin then
  begin
    Exit(spHidden);
  end;
  if MatchText(AEntry.Key, cKeyKeys) then
  begin
    Exit(spKeys);
  end;
  if SameText(AEntry.Page, cKeysPage) then
  begin
    Exit(spHidden);
  end;

  if MatchText(AEntry.Page, cPluginPages) or MatchText(AEntry.Key, cPluginKeys) or
    StartsText(cHintsPrefix, AEntry.Key) then
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

end.
