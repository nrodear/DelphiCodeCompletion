unit dpcc.IDE.Settings.PageOptions;

// Haken der Optionsseite „dpcc“ zu anderen Teilen der IDE-Schicht: „Index neu aufbauen“ (S4, seit OPT1 im Abschnitt
// „Index“ der einen Seite): laufende Sitzung anhalten, Index-Caches löschen (TIndexCacheDirectory.Clear, wie früher
// „Index-Cache löschen“ #184) und die Sitzung neu starten. Kennzahlen, „Index löschen“ und andere Befehle an den Server
// schickt die Seite seit S4 nicht mehr (der schlanke Server kennt kein workspace/executeCommand); sie startet den
// Server auch nicht. Ohne Zustand; die Seite hält die Methodenreferenz.
// Seit S7a ohne „Leiste anpassen …“ (#1101), Export, Import und „Alles zurücksetzen“ (#723) und F1 zur Einstellung
// unter dem Fokus (#1886); seit S8 ohne die Projektdatei .dpcc (#486). Seit OPT1 ohne die Liste der angehefteten
// Favoriten (#458): Strg+D in der Liste bleibt, favorites.json auch.

interface

uses
  System.SysUtils,
  dpcc.UI.Settings.Page;

type
  /// <summary>Führt AClear bei angehaltener Sitzung aus und startet eine laufende Sitzung danach neu (S4). True = neu
  /// gestartet, False = es lief keine Sitzung (oder sie startete nicht wieder); startet keinen Server, der nicht lief.
  /// </summary>
  TDpccIndexRestart = reference to function(const AClear: TProc): Boolean;

  TDpccPageOptions = class
  public
    /// <summary>„Index neu aufbauen“ (S4): Caches löschen und über ARestart neu aufbauen; ARestart nil = nur die
    /// Caches löschen.</summary>
    class procedure ConnectRebuild(APage: TDpccSettingsPage; const ARestart: TDpccIndexRestart); static;
  end;

implementation

uses
  dpcc.Common.Index.Adapters.CacheDirectory,
  dpcc.UI.Settings.Strings;

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
  APage.OnRebuildIndex :=
    function: string
    begin
      Result := RebuildIndex(mRestart);
    end;
end;

end.
