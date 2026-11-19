unit dpcc.Core.Projects.ContextGate;

// Wann der Projektkontext voll gelesen wird (V2, die IDE hängt beim Tippen nicht am Lesen des Kontexts): Das volle
// Lesen (Projektoptionen der aktiven Konfiguration mit ihren Elternstufen, Bibliotheks- und Browsing-Pfad aus der
// Registry, FileExists je Projekt, danach die Suche nach .git für die beobachteten Ordner) lief früher bei jeder
// Anfrage, höchstens einmal je Sekunde, im Hauptthread. Jetzt prüft der Tipp-Pfad nur einen billigen Fingerabdruck
// der Gruppe (Projekte, aktives Projekt, Konfiguration und Plattform je Projekt; ohne Datei- und Registry-Zugriff).
// Voll gelesen wird nur
//   - beim ersten Mal (Start),
//   - sofort, wenn sich der Fingerabdruck geändert hat,
//   - sofort nach einem Ereignis (Signal), etwa wenn ein modaler Dialog der IDE geschlossen wurde: Dort ändert man
//     Projektoptionen (Suchpfad, Defines) und den Bibliothekspfad,
//   - wenn seit dem letzten vollen Lesen der Sicherheitstakt (cSafetyMs) abgelaufen ist: So fallen auch Änderungen
//     ohne Ereignis weiterhin auf (Optionen auf anderen Wegen, Registry durch einen anderen Prozess), nur später.
// cSafetyMs = 15 s: Das volle Lesen kostet je Gruppe einige Millisekunden (mehr auf Netzlaufwerken); die üblichen
// Wege (Projekt, Konfiguration, Plattform, Optionsdialoge) deckt schon der Fingerabdruck bzw. das Ereignis ab, der
// Takt fängt nur seltene Wege auf. 15 s sind ein Fünfzehntel der früheren Last und liegen in der Größenordnung, in
// der der Server Ordner außerhalb der Projekte prüft (10 s).
// Reine Logik ohne Open Tools API, die Uhr ist einstellbar (Tests). Signal und Signals sind threadsicher; Due und
// Done gehören einem Thread (in der IDE dem Hauptthread).

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  /// <summary>Warum voll gelesen wird; None = nicht nötig.</summary>
  TDpccContextReadReason = (None, First, Changed, Event, Safety);
  {$SCOPEDENUMS OFF}

  /// <summary>Entscheidung „Projektkontext voll lesen ja/nein“ (siehe Kopf).</summary>
  TDpccProjectContextGate = class
  public const
    /// <summary>Spätestens nach so vielen Millisekunden seit dem letzten vollen Lesen wieder voll lesen.</summary>
    cSafetyMs = 15000;
  private
    FClock: TFunc<UInt64>;
    FSafetyMs: UInt64;
    /// <summary>Schon einmal voll gelesen (Done)?</summary>
    FRead: Boolean;
    FFingerprint: string;
    FReadAt: UInt64;
    /// <summary>Zähler der Ereignisse (atomar) und sein Stand beim letzten vollen Lesen.</summary>
    FSignals: Integer;
    FSignalsSeen: Integer;
  public
    /// <summary>AClock liefert Millisekunden (in der IDE TDpccTicks.Now).</summary>
    constructor Create(const AClock: TFunc<UInt64>; ASafetyMs: Cardinal = cSafetyMs);
    /// <summary>Ereignis: Die nächste Prüfung liest voll. Threadsicher.</summary>
    procedure Signal;
    /// <summary>Stand des Ereigniszählers; vor dem vollen Lesen holen und an Done geben, damit ein Ereignis während
    /// des Lesens nicht verloren geht. Threadsicher.</summary>
    function Signals: Integer;
    /// <summary>Muss voll gelesen werden, wenn der Fingerabdruck jetzt AFingerprint ist? Ändert nichts.</summary>
    function Due(const AFingerprint: string): TDpccContextReadReason;
    /// <summary>Voll gelesen mit Fingerabdruck AFingerprint; ASignals = Signals vor dem Lesen.</summary>
    procedure Done(const AFingerprint: string; ASignals: Integer);
    /// <summary>Teil des Fingerabdrucks für ein Projekt (Datei, Konfiguration, Plattform, aktiv).</summary>
    class function ProjectPart(const AFileName, AConfiguration, APlatform: string; AActive: Boolean): string; static;
    /// <summary>Anlass als Text fürs Diagnoseprotokoll; '' für None.</summary>
    class function ReasonText(AReason: TDpccContextReadReason): string; static;
  end;

implementation

{ TDpccProjectContextGate }

constructor TDpccProjectContextGate.Create(const AClock: TFunc<UInt64>; ASafetyMs: Cardinal);
begin
  inherited Create;
  FClock := AClock;
  FSafetyMs := ASafetyMs;
end;

procedure TDpccProjectContextGate.Signal;
begin
  AtomicIncrement(FSignals);
end;

function TDpccProjectContextGate.Signals: Integer;
begin
  Result := AtomicCmpExchange(FSignals, 0, 0);
end;

function TDpccProjectContextGate.Due(const AFingerprint: string): TDpccContextReadReason;
var
  mNow: UInt64;
begin
  if not FRead then
  begin
    Exit(TDpccContextReadReason.First);
  end;
  if AFingerprint <> FFingerprint then
  begin
    Exit(TDpccContextReadReason.Changed);
  end;
  if Signals <> FSignalsSeen then
  begin
    Exit(TDpccContextReadReason.Event);
  end;
  mNow := FClock();
  // Eine Uhr, die zurückläuft, zählt wie keine vergangene Zeit (wie TDpccTicks.Since).
  if (mNow >= FReadAt) and (mNow - FReadAt >= FSafetyMs) then
  begin
    Exit(TDpccContextReadReason.Safety);
  end;
  Result := TDpccContextReadReason.None;
end;

procedure TDpccProjectContextGate.Done(const AFingerprint: string; ASignals: Integer);
begin
  FRead := True;
  FFingerprint := AFingerprint;
  FReadAt := FClock();
  FSignalsSeen := ASignals;
end;

class function TDpccProjectContextGate.ProjectPart(const AFileName, AConfiguration, APlatform: string;
  AActive: Boolean): string;
begin
  // Trennzeichen, die in Dateinamen und Konfigurationsnamen nicht vorkommen.
  Result := AFileName + #31 + AConfiguration + #31 + APlatform + #31 + BoolToStr(AActive, False) + #30;
end;

class function TDpccProjectContextGate.ReasonText(AReason: TDpccContextReadReason): string;
begin
  case AReason of
    TDpccContextReadReason.First:
      Result := 'erstes Lesen';
    TDpccContextReadReason.Changed:
      Result := 'Projekt, Konfiguration oder Plattform geändert';
    TDpccContextReadReason.Event:
      Result := 'Ereignis';
    TDpccContextReadReason.Safety:
      Result := 'Sicherheitstakt';
  else
    Result := '';
  end;
end;

end.
