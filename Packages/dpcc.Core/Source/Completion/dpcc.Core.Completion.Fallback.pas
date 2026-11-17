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

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Wer Strg+Leertaste bedient: dpcc fragt seinen Server, Ide lässt die IDE ihre Liste öffnen.</summary>
  TDpccCompletionRoute = (Dpcc, Ide);

  /// <summary>Stand des Merkers: nichts gemerkt, Ergebnis eines Drucks steht aus, leeres Ergebnis an der Stelle.
  /// </summary>
  TDpccFallbackState = (Idle, Pending, Empty);

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
  public
    /// <summary>Strg+Leertaste an APlace. Ide nur, wenn an genau dieser Stelle ein leeres Ergebnis vorliegt; dann
    /// ist der Merker danach zurückgesetzt. Sonst Dpcc, und der Merker wartet auf das Ergebnis an APlace.</summary>
    function Press(const APlace: TDpccCompletionPlace): TDpccCompletionRoute;
    /// <summary>Die Abfrage ist abgeschlossen; AEmpty: Die Liste zeigt den leeren Zustand. Zählt nur, solange ein
    /// Druck wartet. True: Das leere Ergebnis ist gemerkt, der Hinweis auf das zweite Drücken gehört angezeigt.
    /// </summary>
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

{ TDpccCompletionFallback }

function TDpccCompletionFallback.Press(const APlace: TDpccCompletionPlace): TDpccCompletionRoute;
begin
  if (FState = TDpccFallbackState.Empty) and FPlace.Same(APlace) then
  begin
    Reset;
    Exit(TDpccCompletionRoute.Ide);
  end;
  // Auch ein zweiter Druck, solange das Ergebnis aussteht: dpcc fragt erneut.
  FState := TDpccFallbackState.Pending;
  FPlace := APlace;
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
    Result := True;
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
end;

end.
