unit dpcc.Core.Settings.Plugin.Completion;

// Einstellungen des IDE-Plugins, Bereich Vervollständigung (completion.*) (#227):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TDpccPluginSettings (dpcc.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.
// Seit S7a ohne Detailpanel (Breite, eingeklappt), Auswahlmarke, Filter-Chips und gelernte Vorschläge
// (suggestions.*): Alte Werte dieser Namen in der Registry bleiben liegen und werden nicht mehr gelesen.

interface

uses
  dpcc.Core.Settings.Plugin.Store;

const
  cMinVisibleRows = 5;
  cMaxVisibleRows = 20;
  cMinListWidth = 240;
  cMaxListWidth = 720;
  /// <summary>Verzögerung bis zum automatischen Öffnen der Liste (ARG-046, #227); 0 = sofort.</summary>
  cMaxOpenDelay = 2000;
  /// <summary>Zeichen des Bezeichners, ab denen Tippen die Liste öffnet (L5, completion.autoMinChars); 0 = nie.
  /// Wie TDpccAutoOpen.cDefaultMinChars bzw. cMaxMinChars (Settings darf Completion nicht einbinden, der Test prüft
  /// Gleichheit).</summary>
  cDefaultAutoMinChars = 0;
  cMaxAutoMinChars = 10;
  /// <summary>Wie TDpccListModes.cModeNames bzw. ScopeNames (#497); Settings darf Completion nicht einbinden
  ///, der Test prüft Gleichheit.</summary>
  cCompletionListModeNames: array[0..2] of string = ('filter', 'all', 'rest');
  cCompletionListScopeNames: array[0..1] of string = ('members', 'everywhere');

type
  /// <summary>Plugin-Einstellungen: Liste, Einfügen und Vorschau der Vervollständigung.</summary>
  TDpccPluginCompletionSettings = record
    /// <summary>Hauptschalter (#407): aus = eingebaute Code Insight der IDE.</summary>
    Enabled: Boolean;
    /// <summary>Sichtbare Zeilen der Liste (#413).</summary>
    VisibleRows: Integer;
    /// <summary>Von Hand gezogene Breite der Liste, 0 = automatisch (#416).</summary>
    ListWidth: Integer;
    /// <summary>Klammern beim Übernehmen von Methoden (#430).</summary>
    AutoParentheses: Boolean;
    /// <summary>Schreibweise des getippten Worts beim Übernehmen korrigieren (#433).</summary>
    FixCase: Boolean;
    /// <summary>Übernehmen über "(", ";" und "." (#429).</summary>
    CommitCharacters: Boolean;
    /// <summary>Unit beim Übernehmen automatisch in uses eintragen (#180).</summary>
    AutoUses: Boolean;
    /// <summary>Parameter-Hint bei "(" und "," (#436).</summary>
    ParameterHints: Boolean;
    /// <summary>Platzhalter von Format im Parameter-Hint zuordnen und im Editor einfärben (#451).</summary>
    FormatPlaceholders: Boolean;
    /// <summary>Millisekunden zwischen automatischem Auslösen (".") und dem Öffnen der Liste (ARG-046).</summary>
    OpenDelayMs: Integer;
    /// <summary>Beim Tippen eines Bezeichners ohne Punkt davor öffnet die Liste erst ab so vielen Zeichen
    /// (L5, completion.autoMinChars); 0 = Tippen öffnet nie. Strg+Leertaste gilt immer.</summary>
    AutoMinChars: Integer;
    /// <summary>Lernende Gewichtung (#418).</summary>
    Learning: Boolean;
    /// <summary>Favoriten anheften (#458): Strg+D in der Liste, angeheftete Einträge stehen oben;
    /// gespeichert in %APPDATA%\dpcc\favorites.json.</summary>
    Favorites: Boolean;
    /// <summary>Geerbte Member nachrangig und gruppiert (#419).</summary>
    GroupInherited: Boolean;
    /// <summary>Marke „Zweig 0“ an Feldern varianter Records (#846, completion.variantBranch).</summary>
    CompletionVariantBranch: Boolean;
    /// <summary>Beim Tippen nur Treffer (filter), alle Einträge mit Treffern oben (all) oder Treffer und darunter
    /// gedämpft der Rest (rest) (completion.listMode, #497).</summary>
    CompletionListMode: string;
    /// <summary>Wo der Listenmodus gilt: Mitgliederlisten nach "." (members) oder überall (everywhere)
    /// (completion.listMode.scope, #497).</summary>
    CompletionListScope: string;
    /// <summary>Vorschau des gewählten Eintrags im Editor (#434).</summary>
    Preview: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TDpccPluginCompletionSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TDpccSettingsExchange);
  end;

implementation

uses
  System.Math;

{ TDpccPluginCompletionSettings }

class function TDpccPluginCompletionSettings.Defaults: TDpccPluginCompletionSettings;
begin
  Result.Enabled := True;
  Result.VisibleRows := 9;
  Result.ListWidth := 0;
  Result.AutoParentheses := True;
  Result.FixCase := True;
  Result.CommitCharacters := True;
  Result.AutoUses := True;
  Result.ParameterHints := True;
  Result.FormatPlaceholders := True;
  Result.OpenDelayMs := 150;
  Result.AutoMinChars := cDefaultAutoMinChars;
  Result.Learning := True;
  Result.Favorites := True;
  Result.GroupInherited := True;
  Result.CompletionVariantBranch := True;
  Result.CompletionListMode := cCompletionListModeNames[0];
  Result.CompletionListScope := cCompletionListScopeNames[0];
  Result.Preview := False;
end;

procedure TDpccPluginCompletionSettings.Normalize;
begin
  VisibleRows := EnsureRange(VisibleRows, cMinVisibleRows, cMaxVisibleRows);
  if ListWidth <> 0 then
  begin
    ListWidth := EnsureRange(ListWidth, cMinListWidth, cMaxListWidth);
  end;
  CompletionListMode := Choice(CompletionListMode, cCompletionListModeNames);
  CompletionListScope := Choice(CompletionListScope, cCompletionListScopeNames);
  OpenDelayMs := EnsureRange(OpenDelayMs, 0, cMaxOpenDelay);
  AutoMinChars := EnsureRange(AutoMinChars, 0, cMaxAutoMinChars);
end;

procedure TDpccPluginCompletionSettings.Exchange(const AIo: TDpccSettingsExchange);
begin
  AIo.Flag('Enabled', Enabled);
  AIo.Number('VisibleRows', VisibleRows);
  AIo.Number('ListWidth', ListWidth);
  AIo.Flag('AutoParentheses', AutoParentheses);
  AIo.Flag('FixCase', FixCase);
  AIo.Flag('CommitCharacters', CommitCharacters);
  AIo.Flag('AutoUses', AutoUses);
  AIo.Flag('ParameterHints', ParameterHints);
  AIo.Flag('FormatPlaceholders', FormatPlaceholders);
  AIo.Number('OpenDelayMs', OpenDelayMs);
  AIo.Number('AutoMinChars', AutoMinChars);
  AIo.Flag('Learning', Learning);
  AIo.Flag('Favorites', Favorites);
  AIo.Flag('GroupInherited', GroupInherited);
  AIo.Flag('CompletionVariantBranch', CompletionVariantBranch);
  AIo.Text('CompletionListMode', CompletionListMode);
  AIo.Text('CompletionListScope', CompletionListScope);
  AIo.Flag('Preview', Preview);
end;

end.
