unit dpcc.Core.Completion.Fallback;

// Zweites Strg+Leertaste öffnet die Liste der IDE (L3), ohne Fenster und ohne IDE: Das erste Strg+Leertaste fragt
// dpcc. Bleibt dessen Liste leer (nichts gefunden, kein Kontext, Fehler oder Zeitlimit einer Quelle – alles endet im
// leeren Zustand, #423), gehört ein weiteres Strg+Leertaste an derselben Stelle ohne Eingabe dazwischen der IDE, die
// dann ihre eigene Liste öffnet (DelphiLSP). Einen automatischen Wechsel gibt es nicht.
//   - Press: Strg+Leertaste über die Taste von dpcc an einer Stelle (Datei, Zeile, Zeichen, Text der Zeile). Liegt
//     genau dort ein leeres Ergebnis vor, gehört die Taste der IDE und der Merker ist danach zurückgesetzt; sonst
//     fragt dpcc und der Merker wartet auf das Ergebnis.
//   - Settled: Die Abfrage ist abgeschlossen (TDpccCompletionController.OnSettled; das Ergebnis kommt erst nach dem
//     Tastendruck). Es zählt nur für einen wartenden Druck. True heißt: jetzt den Hinweis zeigen.
//   - Solange das Ergebnis aussteht, fragt ein weiteres Drücken dpcc erneut, nie die IDE.
//   - Edited: Eingabe im Editor. Hat sich die Stelle geändert (Zeichen, Zeile, Text, Datei), ist der Merker weg; eine
//     Meldung ohne Änderung lässt ihn stehen.
//   - Reset: anderer Reiter, Hauptschalter aus.
// Ein Cursorwechsel braucht kein eigenes Ereignis: Press vergleicht die ganze Stelle.
// L4, was die IDE beim Druck kann (TDpccIdeList, die IDE-Seite ermittelt es):
//   - Reachable: Ein durchgereichtes Strg+Leertaste kommt bei einem anderen Code-Insight-Anbieter an. Ist dpcc selbst
//     der für die Datei gewählte Anbieter (Tools > Optionen, Code Insight für Delphi), ruft die IDE mit der Taste
//     wieder dpcc auf (InvokeCodeCompletion) und nie DelphiLSP: Dann gibt es keine Liste der IDE, der zweite Druck
//     fragt dpcc erneut, und der Hinweis auf das zweite Drücken entfällt (Settled liefert False).
//   - Open: Die Liste der IDE ist schon offen. Dann gehört Strg+Leertaste ihr (Route Ide), dpcc öffnet keine zweite
//     Liste daneben; der Merker ist danach zurückgesetzt.

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Wer Strg+Leertaste bedient: dpcc fragt seinen Server, Ide lässt die IDE ihre Liste öffnen.</summary>
  TDpccCompletionRoute = (Dpcc, Ide);

  /// <summary>Stand des Merkers: nichts gemerkt, Ergebnis eines Drucks steht aus, leeres Ergebnis an der Stelle.
  /// </summary>
  TDpccFallbackState = (Idle, Pending, Empty);

  /// <summary>Was die IDE beim Druck kann (L4): Reachable, wenn ein durchgereichtes Strg+Leertaste bei einem anderen
  /// Code-Insight-Anbieter ankommt (dpcc ist für die Datei nicht der gewählte); Open, wenn die Liste der IDE schon
  /// offen ist.</summary>
  TDpccIdeList = record
    Reachable: Boolean;
    Open: Boolean;
    /// <summary>Wie bis L3 angenommen: erreichbar, nicht offen.</summary>
    class function Usual: TDpccIdeList; static;
    class function Create(AReachable, AOpen: Boolean): TDpccIdeList; static;
  end;

  /// <summary>Stelle im Editor: Datei, Zeile (ab 1), Zeichen (0-basiert) und Text der Zeile. Der Text erkennt eine
  /// Eingabe auch dann, wenn der Cursor danach wieder an derselben Spalte steht.</summary>
  TDpccCompletionPlace = record
    FileName: string;
    Line: Integer;
    Character: Integer;
    LineText: string;
    class function At(const AFileName: string; ALine, ACharacter: Integer;
      const ALineText: string): TDpccCompletionPlace; static;
    /// <summary>Gleiche Stelle: Datei ohne Groß/klein, Zeile, Zeichen und Text der Zeile genau.</summary>
    function Same(const AOther: TDpccCompletionPlace): Boolean;
  end;

  /// <summary>Merker für das zweite Strg+Leertaste; nur im Hauptthread.</summary>
  TDpccCompletionFallback = class
  private
    FState: TDpccFallbackState;
    FPlace: TDpccCompletionPlace;
    /// <summary>War die Liste der IDE beim wartenden Druck erreichbar (L4)? Nur dann gibt es den Hinweis.</summary>
    FIdeReachable: Boolean;
  public
    /// <summary>Strg+Leertaste an APlace, die IDE wie bis L3 angenommen (TDpccIdeList.Usual).</summary>
    function Press(const APlace: TDpccCompletionPlace): TDpccCompletionRoute; overload;
    /// <summary>Strg+Leertaste an APlace (L4). Ide, wenn die Liste der IDE schon offen ist (AIde.Open: keine zweite
    /// Liste von dpcc daneben) oder wenn an genau dieser Stelle ein leeres Ergebnis vorliegt und die Liste der IDE
    /// erreichbar ist (AIde.Reachable); dann ist der Merker danach zurückgesetzt. Sonst Dpcc, und der Merker wartet
    /// auf das Ergebnis an APlace.</summary>
    function Press(const APlace: TDpccCompletionPlace; const AIde: TDpccIdeList): TDpccCompletionRoute; overload;
    /// <summary>Die Abfrage ist abgeschlossen; AEmpty: Die Liste zeigt den leeren Zustand. Zählt nur, solange ein
    /// Druck wartet. True: Das leere Ergebnis ist gemerkt, und der Hinweis auf das zweite Drücken gehört angezeigt;
    /// nie, wenn die Liste der IDE beim Druck nicht erreichbar war (L4).</summary>
    function Settled(AEmpty: Boolean): Boolean;
    /// <summary>Eingabe im Editor; APlace ist die Stelle des Cursors danach. Verwirft den Merker, wenn sie sich
    /// geändert hat.</summary>
    procedure Edited(const APlace: TDpccCompletionPlace);
    /// <summary>Merker verwerfen (anderer Reiter, Hauptschalter aus).</summary>
    procedure Reset;
    property State: TDpccFallbackState read FState;
    /// <summary>Gemerkte Stelle; nur bei State &lt;&gt; Idle belegt.</summary>
    property Place: TDpccCompletionPlace read FPlace;
  end;

{$SCOPEDENUMS OFF}

implementation

uses
  System.SysUtils;

{ TDpccCompletionPlace }

class function TDpccCompletionPlace.At(const AFileName: string; ALine, ACharacter: Integer;
  const ALineText: string): TDpccCompletionPlace;
begin
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.LineText := ALineText;
end;

function TDpccCompletionPlace.Same(const AOther: TDpccCompletionPlace): Boolean;
begin
  Result := (Line = AOther.Line) and (Character = AOther.Character) and (LineText = AOther.LineText) and
    SameText(FileName, AOther.FileName);
end;

{ TDpccIdeList }

class function TDpccIdeList.Usual: TDpccIdeList;
begin
  Result := Create(True, False);
end;

class function TDpccIdeList.Create(AReachable, AOpen: Boolean): TDpccIdeList;
begin
  Result.Reachable := AReachable;
  Result.Open := AOpen;
end;

{ TDpccCompletionFallback }

function TDpccCompletionFallback.Press(const APlace: TDpccCompletionPlace): TDpccCompletionRoute;
begin
  Result := Press(APlace, TDpccIdeList.Usual);
end;

function TDpccCompletionFallback.Press(const APlace: TDpccCompletionPlace;
  const AIde: TDpccIdeList): TDpccCompletionRoute;
begin
  // Die Liste der IDE ist offen: Die Taste gehört ihr, dpcc öffnet keine zweite Liste daneben (L4).
  if AIde.Open then
  begin
    Reset;
    Exit(TDpccCompletionRoute.Ide);
  end;
  if (FState = TDpccFallbackState.Empty) and FPlace.Same(APlace) and AIde.Reachable then
  begin
    Reset;
    Exit(TDpccCompletionRoute.Ide);
  end;
  // Auch ein zweiter Druck, solange das Ergebnis aussteht, und jeder, solange dpcc der gewählte Anbieter ist: dpcc
  // fragt erneut.
  FState := TDpccFallbackState.Pending;
  FPlace := APlace;
  FIdeReachable := AIde.Reachable;
  Result := TDpccCompletionRoute.Dpcc;
end;

function TDpccCompletionFallback.Settled(AEmpty: Boolean): Boolean;
begin
  Result := False;
  if FState <> TDpccFallbackState.Pending then
  begin
    Exit;
  end;
  if AEmpty then
  begin
    FState := TDpccFallbackState.Empty;
    Result := FIdeReachable;
  end
  else
  begin
    Reset;
  end;
end;

procedure TDpccCompletionFallback.Edited(const APlace: TDpccCompletionPlace);
begin
  if (FState <> TDpccFallbackState.Idle) and not FPlace.Same(APlace) then
  begin
    Reset;
  end;
end;

procedure TDpccCompletionFallback.Reset;
begin
  FState := TDpccFallbackState.Idle;
  FPlace := Default(TDpccCompletionPlace);
  FIdeReachable := False;
end;

end.
