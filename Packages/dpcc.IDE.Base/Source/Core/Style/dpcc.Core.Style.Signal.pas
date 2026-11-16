unit dpcc.Core.Style.Signal;

// Signalfarben je Design (#1255): Zustandspunkte (Statusfeld, dpcc-Statusleiste,
// Statusfenster, Einrichtung), Plaketten und Befundsymbole. Früher nahmen sie
// die Textfarben Add/Warn/Error/Muted, die für Text auf der Fensterfläche
// gedacht sind; im hellen Design waren sie dunkel und entsättigt und als
// kleiner Punkt kaum zu unterscheiden, das gelbe Warndreieck hatte auf hellem
// Grund nur 1,8 : 1. Jetzt (Variante A, Entwurf in #1255):
// - Hell: kräftige Füllung (Fill) mit dunklem Rand (Ring); der Rand hält
//   mindestens 4 : 1 zur Leistenfläche, die Füllung macht die Farbe auf einen
//   Blick erkennbar.
// - Dunkel: helle, gesättigte Füllung ohne eigenen Rand (Ring = Fill), auf den
//   dunklen Flächen der IDE mindestens 4 : 1.
// - Mark: Zeichen auf der Füllung (Kreuz, „i“, Ausrufezeichen); Solid und
//   OnSolid: Plakette mit Zahl darauf.
// Die Farben gehören zur Palette der Fläche, auf der sie liegen
// (TDpccColors.Signals; für Leisten ForChrome mit der Fläche der Leiste).

interface

uses
  dpcc.Core.Style.Color,
  dpcc.Core.Status.Contract;

type
{$SCOPEDENUMS ON}
  /// <summary>Bedeutung einer Signalfarbe: in Ordnung, Warnung bzw. läuft, Fehler, ohne Aussage, Hinweis.</summary>
  TDpccSignalKind = (Ok, Warn, Error, Idle, Info);
{$SCOPEDENUMS OFF}

  TDpccSignal = record
    /// <summary>Fläche von Punkt und Symbol.</summary>
    Fill: TDpccColor;
    /// <summary>Rand von Punkt und Symbol; trägt den Kontrast zur Fläche darunter.</summary>
    Ring: TDpccColor;
    /// <summary>Zeichen auf Fill (Kreuz, „i“, Ausrufezeichen).</summary>
    Mark: TDpccColor;
    /// <summary>Fläche einer Plakette mit Text.</summary>
    Solid: TDpccColor;
    /// <summary>Text auf Solid.</summary>
    OnSolid: TDpccColor;
  end;

  TDpccSignals = record
    Items: array[TDpccSignalKind] of TDpccSignal;
    function Get(AKind: TDpccSignalKind): TDpccSignal;
    /// <summary>Signal zum Zustand einer Statuszeile.</summary>
    function ForStatus(AState: TDpccStatusState): TDpccSignal;
    class function Light: TDpccSignals; static;
    class function Dark: TDpccSignals; static;
    class function KindOf(AState: TDpccStatusState): TDpccSignalKind; static;
  end;

implementation

function Signal(const AFill, ARing, AMark, ASolid, AOnSolid: string): TDpccSignal;
begin
  Result.Fill := TDpccColorMath.FromHex(AFill);
  Result.Ring := TDpccColorMath.FromHex(ARing);
  Result.Mark := TDpccColorMath.FromHex(AMark);
  Result.Solid := TDpccColorMath.FromHex(ASolid);
  Result.OnSolid := TDpccColorMath.FromHex(AOnSolid);
end;

{ TDpccSignals }

class function TDpccSignals.Light: TDpccSignals;
begin
  Result.Items[TDpccSignalKind.Ok] := Signal('#22C55E', '#15803D', '#FFFFFF', '#15803D', '#FFFFFF');
  // Ausrufezeichen dunkel: Weiß hätte auf dem Bernstein nur 2,1 : 1.
  Result.Items[TDpccSignalKind.Warn] := Signal('#F59E0B', '#B45309', '#3A2500', '#B45309', '#FFFFFF');
  Result.Items[TDpccSignalKind.Error] := Signal('#EF4444', '#B91C1C', '#FFFFFF', '#B91C1C', '#FFFFFF');
  Result.Items[TDpccSignalKind.Idle] := Signal('#A3ADBD', '#64748B', '#FFFFFF', '#64748B', '#FFFFFF');
  Result.Items[TDpccSignalKind.Info] := Signal('#3B82F6', '#1D4ED8', '#FFFFFF', '#1D4ED8', '#FFFFFF');
end;

class function TDpccSignals.Dark: TDpccSignals;
begin
  // Helle Füllung: Zeichen und Text darauf dunkel.
  Result.Items[TDpccSignalKind.Ok] := Signal('#4ADE80', '#4ADE80', '#15181D', '#4ADE80', '#15181D');
  Result.Items[TDpccSignalKind.Warn] := Signal('#FBBF24', '#FBBF24', '#15181D', '#FBBF24', '#15181D');
  Result.Items[TDpccSignalKind.Error] := Signal('#F87171', '#F87171', '#15181D', '#F87171', '#15181D');
  Result.Items[TDpccSignalKind.Idle] := Signal('#9AA3B2', '#9AA3B2', '#15181D', '#9AA3B2', '#15181D');
  Result.Items[TDpccSignalKind.Info] := Signal('#60A5FA', '#60A5FA', '#15181D', '#60A5FA', '#15181D');
end;

class function TDpccSignals.KindOf(AState: TDpccStatusState): TDpccSignalKind;
begin
  case AState of
    TDpccStatusState.Green:
      Result := TDpccSignalKind.Ok;
    TDpccStatusState.Yellow:
      Result := TDpccSignalKind.Warn;
    TDpccStatusState.Red:
      Result := TDpccSignalKind.Error;
  else
    Result := TDpccSignalKind.Idle;
  end;
end;

function TDpccSignals.Get(AKind: TDpccSignalKind): TDpccSignal;
begin
  Result := Items[AKind];
end;

function TDpccSignals.ForStatus(AState: TDpccStatusState): TDpccSignal;
begin
  Result := Items[KindOf(AState)];
end;

end.
