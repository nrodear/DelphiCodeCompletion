unit dpcc.IDE.Settings.PageOptions;

// Haken der Optionsseite „dpcc“ zu anderen Teilen der IDE-Schicht: angeheftete Favoriten (#458), Befehle für „Leiste anpassen …“ (#1101), Projektdatei .dpcc (#486),
// Export, Import und „Alles zurücksetzen“ (#723), F1 zur Einstellung unter dem Fokus (#1886) und „Index neu aufbauen“
// (S4, Seite „Allgemein“): laufende Sitzung anhalten, Index-Caches löschen (TIndexCacheDirectory.Clear, wie früher
// „Index-Cache löschen“ #184) und die Sitzung neu starten. Kennzahlen, „Index löschen“ und andere Befehle an den Server
// schickt die Seite seit S4 nicht mehr (der schlanke Server kennt kein workspace/executeCommand); sie startet den
// Server auch nicht. Ohne Zustand; die Seite hält die Methodenreferenzen.

interface

uses
  System.SysUtils,
  Vcl.Controls,
  dpcc.UI.EditorToolbar.Customize,
  dpcc.UI.Settings.Page;

type
  /// <summary>Führt AClear bei angehaltener Sitzung aus und startet eine laufende Sitzung danach neu (S4). True = neu
  /// gestartet, False = es lief keine Sitzung (oder sie startete nicht wieder); startet keinen Server, der nicht lief.
  /// </summary>
  TDpccIndexRestart = reference to function(const AClear: TProc): Boolean;

  TDpccPageOptions = class
  public
    /// <summary>„Index neu aufbauen“ (S4) auf der Seite „Allgemein“: Caches löschen und über ARestart neu aufbauen;
    /// ARestart nil = nur die Caches löschen.</summary>
    class procedure ConnectRebuild(APage: TDpccSettingsPage; const ARestart: TDpccIndexRestart); static;
    /// <summary>Angeheftete Favoriten (#458) und Befehle für „Leiste anpassen …“ (#1101); AToolbarCommands nil =
    /// keine Befehle.</summary>
    class procedure ConnectFavorites(APage: TDpccSettingsPage;
      const AToolbarCommands: TFunc<TArray<TDpccToolbarCommandInfo>>); static;
    /// <summary>Projektdatei .dpcc (#486), Export, Import und „Alles zurücksetzen“ (#723).</summary>
    class procedure ConnectTransfer(APage: TDpccSettingsPage); static;
    /// <summary>F1 (#1886): Hilfe zur Einstellung unter dem Fokus, sonst zur Optionsseite.</summary>
    class procedure ConnectHelp(APage: TDpccSettingsPage); static;
    /// <summary>Schlüssel (x-key) der Einstellung an AControl oder einem seiner Eltern in APage; '' ohne.</summary>
    class function SettingKeyAt(APage: TDpccSettingsPage; AControl: TControl): string; static;
  end;

implementation

uses
  Vcl.Forms,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Common.Index.Adapters.CacheDirectory,
  dpcc.UI.Settings.Strings,
  dpcc.Core.Settings.Catalog,
  dpcc.IDE.Contracts.Help,
  dpcc.IDE.ElementHelp.Keys,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.TeamFile,
  dpcc.Core.Completion.Favorites,
  dpcc.IDE.Completion.Favorites,
  dpcc.IDE.Foundation.TeamFile,
  dpcc.IDE.Settings.Transfer,
  dpcc.UI.Settings.Page.General,
  dpcc.UI.Settings.Page.Completion,
  dpcc.UI.Settings.Page.EditorView,
  dpcc.UI.Settings.Page.TeamFile,
  dpcc.UI.Settings.Page.Transfer,
  dpcc.IDE.Foundation.Files;

/// <summary>„Index neu aufbauen“ (S4): alle Index-Caches löschen, eine laufende Sitzung dafür anhalten und neu
/// starten; Ergebnis als Meldung für die Seite.</summary>
function RebuildIndex(const ARestart: TDpccIndexRestart): string;
var
  mCleared: Integer;
  mRestarted: Boolean;
  mClear: TProc;
begin
  mCleared := 0;
  mClear :=
    procedure
    begin
      mCleared := TIndexCacheDirectory.Clear(TIndexCacheDirectory.DefaultRoot);
    end;
  try
    mRestarted := False;
    if Assigned(ARestart) then
    begin
      mRestarted := ARestart(mClear);
    end
    else
    begin
      mClear();
    end;
    if mRestarted then
    begin
      Result := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsIndexCacheCleared, [mCleared]);
    end
    else
    begin
      Result := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsIndexRebuildLater, [mCleared]);
    end;
  except
    on E: Exception do
      Result := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsIndexCacheFailed, [E.Message]);
  end;
end;

class procedure TDpccPageOptions.ConnectRebuild(APage: TDpccSettingsPage; const ARestart: TDpccIndexRestart);
var
  mRestart: TDpccIndexRestart;
begin
  mRestart := ARestart;
  APage.Part<TDpccSettingsGeneralPart>.OnRebuildIndex :=
    function: string
    begin
      Result := RebuildIndex(mRestart);
    end;
end;

class procedure TDpccPageOptions.ConnectFavorites(APage: TDpccSettingsPage;
  const AToolbarCommands: TFunc<TArray<TDpccToolbarCommandInfo>>);
begin
  APage.Part<TDpccSettingsFavoritesPart>.OnRemoveFavorites :=
    procedure(AKeys: TArray<string>)
    begin
      TDpccGuard.Run(TDpccFeature.Settings,
        procedure
        begin
          TDpccIdeFavorites.Remove(AKeys);
        end);
    end;
  APage.Part<TDpccSettingsFavoritesPart>.OnFavorites :=
    function: TArray<TDpccFavorite>
    begin
      Result := TDpccIdeFavorites.Items;
    end;
  APage.Part<TDpccSettingsEditorViewPart>.OnToolbarCommands :=
    function: TArray<TDpccToolbarCommandInfo>
    begin
      Result := nil;
      if Assigned(AToolbarCommands) then
      begin
        Result := AToolbarCommands();
      end;
    end;
end;

class procedure TDpccPageOptions.ConnectTransfer(APage: TDpccSettingsPage);
begin
  // Werte „aus .dpcc“ auch bei noch ausgeschaltetem Schalter; Öffnen legt die Datei an.
  APage.Part<TDpccSettingsTeamFilePart>.OnTeamFile :=
    function: TDpccTeamSettings
    begin
      Result := TDpccIdeTeamFile.Read(TDpccIdeFiles.ActiveProjectFile);
    end;
  APage.Part<TDpccSettingsTeamFilePart>.OnOpenTeamFile :=
    procedure
    begin
      TDpccGuard.Run(TDpccFeature.Settings,
        procedure
        begin
          TDpccIdeTeamFile.OpenInEditor;
        end);
    end;
  // Mit den Werten der Seite; Import und Zurücksetzen speichern sofort (mit Sicherung), die Seite lädt danach neu.
  APage.Part<TDpccSettingsTransferPart>.OnExportSettings :=
    procedure(ACurrent: TDpccPluginSettings)
    begin
      TDpccIdeSettingsTransfer.ExportSettings(ACurrent);
    end;
  APage.Part<TDpccSettingsTransferPart>.OnImportSettings :=
    function(const ACurrent: TDpccPluginSettings; AProfile: Boolean; out AResult: TDpccPluginSettings): Boolean
    begin
      Result := TDpccIdeSettingsTransfer.ImportSettings(ACurrent, AProfile, AResult);
    end;
  APage.Part<TDpccSettingsTransferPart>.OnResetAllSettings :=
    function(const ACurrent: TDpccPluginSettings; out AResult: TDpccPluginSettings): Boolean
    begin
      Result := TDpccIdeSettingsTransfer.ResetAll(ACurrent, AResult);
    end;
end;

class function TDpccPageOptions.SettingKeyAt(APage: TDpccSettingsPage; AControl: TControl): string;
var
  mControl: TControl;
  mName: string;
  mIndex: Integer;
begin
  Result := '';
  mControl := AControl;
  while (Result = '') and (mControl <> nil) and (mControl <> APage) do
  begin
    for mName in APage.Marks.NamesOf(mControl) do
    begin
      mIndex := APage.Catalog.IndexOfName(mName);
      if (Result = '') and (mIndex >= 0) then
      begin
        Result := APage.Catalog.Entries[mIndex].Key;
      end;
    end;
    mControl := mControl.Parent;
  end;
end;

class procedure TDpccPageOptions.ConnectHelp(APage: TDpccSettingsPage);
begin
  TDpccIdeHelp.AddKey(APage,
    function(out ATopic: TDpccHelpTopic): Boolean
    var
      mKey: string;
    begin
      mKey := SettingKeyAt(APage, Screen.ActiveControl);
      if mKey <> '' then
      begin
        ATopic := TDpccIdeHelp.Topic(TDpccHelpKind.Setting, mKey);
      end
      else
      begin
        ATopic := TDpccIdeHelp.Topic(TDpccHelpKind.Window, TDpccIdeHelp.cOptionsWindow);
      end;
      Result := True;
    end);
end;

end.
