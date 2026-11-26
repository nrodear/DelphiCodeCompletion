unit dpcc.IDE.Settings.PageOptions;

// Haken der Optionsseite „dpcc“ zu anderen Teilen der IDE-Schicht: „Index neu aufbauen“ (S4, seit OPT1 im Abschnitt
// „Index“ der einen Seite): laufende Sitzung anhalten, Index-Caches löschen (TIndexCacheDirectory.Clear, wie früher
// „Index-Cache löschen“ #184) und die Sitzung neu starten. Kennzahlen, „Index löschen“ und andere Befehle an den Server
// schickt die Seite seit S4 nicht mehr (der schlanke Server kennt kein workspace/executeCommand); sie startet den
// Server auch nicht. Die Seite hält die Methodenreferenzen.
// Ohne Warten im Hauptthread: Der Klick stößt den Neuaufbau nur an (TDpccIndexRestart kehrt sofort zurück); das
// Löschen läuft im Hintergrund-Thread der Sitzung, der Abschluss kommt über ADone im Hauptthread. Den Zustand (läuft,
// Meldung) hält diese Unit über das Schließen der Seite hinaus (nur Hauptthread); die Seite fragt ihn über
// OnRebuildStatus ab. Weder Thread noch Abschluss kennen die Seite, sie darf jederzeit zerstört werden.
// Seit S7a ohne „Leiste anpassen …“ (#1101), Export, Import und „Alles zurücksetzen“ (#723) und F1 zur Einstellung
// unter dem Fokus (#1886); seit S8 ohne die Projektdatei .dpcc (#486). Seit OPT1 ohne die Liste der angehefteten
// Favoriten (#458): Strg+D in der Liste bleibt, favorites.json auch.
// Seit IDECHECK der Abschnitt „IDE“: Statuszeilen zur Betriebsart (Anbieter, was dpcc gesetzt hat, Abweichungen) aus
// der Registry, nur gelesen (TDpccIdeSettingsCheck.Status); „Jetzt prüfen“ liest neu.

interface

uses
  System.SysUtils,
  dpcc.UI.Settings.Page;

type
  /// <summary>Stößt „Index neu aufbauen“ an und kehrt sofort zurück (S4): Sitzung im Hintergrund anhalten, danach
  /// AClear genau einmal in einem Hintergrund-Thread (ohne VCL und Open Tools API), danach ADone im Hauptthread (True
  /// = eine vorher laufende Sitzung wurde neu gestartet; startet keinen Server, der nicht lief). True = angestoßen;
  /// False = abgelehnt (läuft schon, entladen), dann weder AClear noch ADone. Beim Entladen entfallen beide.
  /// </summary>
  TDpccIndexRestart = reference to function(const AClear: TProc; const ADone: TProc<Boolean>): Boolean;

  TDpccPageOptions = class
  public
    /// <summary>„Index neu aufbauen“ (S4): Caches löschen und über ARestart neu aufbauen; ARestart nil = nur die
    /// Caches löschen (dann im Hauptthread). Setzt auch OnRebuildStatus der Seite.</summary>
    class procedure ConnectRebuild(APage: TDpccSettingsPage; const ARestart: TDpccIndexRestart); static;
    /// <summary>Zustand von „Index neu aufbauen“ für die Seite (nur Hauptthread).</summary>
    class function RebuildStatus: TDpccRebuildStatus; static;
    /// <summary>Abschnitt „IDE“: Status der Betriebsart nach den gespeicherten Einstellungen (IDECHECK).</summary>
    class procedure ConnectIdeStatus(APage: TDpccSettingsPage); static;
  end;

implementation

uses
  dpcc.Common.Index.Adapters.CacheDirectory,
  dpcc.UI.Settings.Strings,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Foundation.IdeSettingsCheck,
  dpcc.Core.Diagnostics.Hangs;

var
  /// <summary>Läuft „Index neu aufbauen“? Lebt über das Schließen der Seite hinaus (nur Hauptthread).</summary>
  gRebuildRunning: Boolean;
  /// <summary>Meldung dazu für die Seite; '' vor dem ersten Klick.</summary>
  gRebuildText: string;

/// <summary>Meldung nach dem Löschen: Fehler, neu gestartet oder Neuaufbau beim nächsten Start.</summary>
function DoneText(ACleared: Integer; const AError: string; ARestarted: Boolean): string;
begin
  if AError <> '' then
  begin
    Result := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsIndexCacheFailed, [AError]);
  end
  else if ARestarted then
  begin
    Result := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsIndexCacheCleared, [ACleared]);
  end
  else
  begin
    Result := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsIndexRebuildLater, [ACleared]);
  end;
end;

/// <summary>„Index neu aufbauen“ (S4), Klick auf der Seite: anstoßen und sofort die Meldung „läuft …“ liefern. Das
/// Löschen (AClear) läuft im Hintergrund, der Abschluss (ADone) setzt Zustand und Meldung im Hauptthread. Ein zweiter
/// Klick während des Laufs tut nichts.</summary>
function RebuildIndex(const ARestart: TDpccIndexRestart): string;
var
  mActivity: IInterface;
  mRoot: string;
  mCleared: Integer;
  mError: string;
  mClear: TProc;
  mDone: TProc<Boolean>;
  mStarted: Boolean;
begin
  mActivity := TDpccActivity.Scope('Index neu aufbauen (Optionsseite)');
  if gRebuildRunning then
  begin
    Exit(gRebuildText);
  end;
  mCleared := 0;
  mError := '';
  try
    // Pfad im Hauptthread bestimmen; der Thread bekommt nur die Zeichenkette.
    mRoot := TIndexCacheDirectory.DefaultRoot;
  except
    on E: Exception do
    begin
      // Auch als Zustand: Sonst überschreibt die nächste Abfrage der Seite die Meldung mit einer älteren.
      gRebuildText := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsIndexCacheFailed, [E.Message]);
      Exit(gRebuildText);
    end;
  end;
  // Im Hintergrund-Thread: nur Dateien, keine VCL; Fehler als Text an den Abschluss.
  mClear :=
    procedure
    begin
      try
        mCleared := TIndexCacheDirectory.Clear(mRoot);
      except
        on E: Exception do
        begin
          mError := E.Message;
        end;
      end;
    end;
  // Im Hauptthread (TDpccMainThread.Queue); beim Entladen verworfen.
  mDone :=
    procedure(ARestarted: Boolean)
    begin
      gRebuildRunning := False;
      gRebuildText := DoneText(mCleared, mError, ARestarted);
    end;
  // Vor dem Anstoßen: Ohne Manager ruft der Haken ADone sofort auf.
  gRebuildRunning := True;
  gRebuildText := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexRebuildRunning);
  try
    if Assigned(ARestart) then
    begin
      mStarted := ARestart(mClear, mDone);
    end
    else
    begin
      mClear();
      mDone(False);
      mStarted := True;
    end;
    if not mStarted then
    begin
      // Abgelehnt (läuft in der Sitzung schon, entladen): nichts angestoßen, Knopf wieder frei. Nicht „läuft …“
      // stehen lassen: Die Seite zeigt den Text neben dem freien Knopf.
      gRebuildRunning := False;
      gRebuildText := TDpccSettingsStrings.Text(TDpccSettingsTextId.SettingsIndexRebuildRejected);
    end;
  except
    on E: Exception do
    begin
      gRebuildRunning := False;
      gRebuildText := TDpccSettingsStrings.Fmt(TDpccSettingsTextId.SettingsIndexCacheFailed, [E.Message]);
    end;
  end;
  Result := gRebuildText;
end;

class function TDpccPageOptions.RebuildStatus: TDpccRebuildStatus;
begin
  Result := Default(TDpccRebuildStatus);
  Result.Running := gRebuildRunning;
  Result.Text := gRebuildText;
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
  // Nach OnRebuildIndex: Die Seite fragt den Zustand gleich ab (neu geöffnet, während ein Neuaufbau läuft).
  APage.OnRebuildStatus :=
    function: TDpccRebuildStatus
    begin
      Result := TDpccPageOptions.RebuildStatus;
    end;
end;

class procedure TDpccPageOptions.ConnectIdeStatus(APage: TDpccSettingsPage);
begin
  APage.OnIdeStatus :=
    function: string
    begin
      try
        Result := TDpccIdeSettingsCheck.Status(TDpccIdeSettings.Current);
      except
        on E: Exception do
          Result := E.Message;
      end;
    end;
end;

end.
