unit dpcc.Core.Diagnostics.FpuState;

// Gleitkomma-Einstellung im dpcc.log (FPU1), ohne VCL und ohne Open Tools API: Anlass war ein Absturz der Delphi-12-IDE
// mit Stapelüberlauf in clr.dll. Ein Hintergrund-Thread der IDE (Error Insight) rief .NET-Code auf, während im
// x87-Steuerwort die Ausnahme „Invalid Operation“ nicht maskiert war; System.Default8087CW der gemeinsamen RTL stand
// auf $137A statt auf der Vorgabe $033F (alle maskiert). dpcc setzt das Steuerwort nirgends und ändert es auch hier
// nicht: Es protokolliert nur, wie es steht und wann es sich ändert.
// - Diese Unit bekommt nur Zahlen (Word bzw. Cardinal) und baut daraus Texte; gelesen wird in der IDE-Schicht
//   (dpcc.IDE.Foundation.FpuWatch), dort auch nur unter x86/x64.
// - Steuerwort: Bits 0–5 sind die Masken der sechs Ausnahmen (Invalid, Denormal, ZeroDivide, Overflow, Underflow,
//   Precision); ein gesetztes Bit heißt maskiert. Die übrigen Bits (Genauigkeit, Rundung) zählen nur für Changed.
// - TDpccFpuWatch merkt sich den zuletzt gemeldeten Stand und zählt die Änderungsmeldungen; nach cMaxReports Meldungen
//   je Sitzung schweigt er, die letzte Meldung sagt das. Kein eigener Thread, keine Sperre: Er lebt im Hauptthread.

interface

type
  /// <summary>Texte und Vergleiche zur Gleitkomma-Einstellung (x87-Steuerwort, MXCSR), nur aus Zahlen.</summary>
  TDpccFpuState = record
  public const
    /// <summary>Masken der sechs Ausnahmen im x87-Steuerwort (Bits 0–5).</summary>
    cMaskBits = $003F;
    /// <summary>Vorgabe der Delphi-RTL für Default8087CW: alle Ausnahmen maskiert.</summary>
    cDefault8087CW = $033F;
    /// <summary>Höchstens so viele Änderungsmeldungen je Sitzung.</summary>
    cMaxReports = 20;
  public
    /// <summary>„$033F“: Hex-Wert mit mindestens vier Stellen.</summary>
    class function HexText(AValue: Cardinal): string; static;
    /// <summary>Namen der nicht maskierten Ausnahmen in Bitfolge, mit „, “ getrennt; '' wenn alle maskiert sind.
    /// </summary>
    class function UnmaskedNames(AControlWord: Word): string; static;
    /// <summary>„$137A (nicht maskiert: Invalid, ZeroDivide)“ bzw. „$033F (alle maskiert)“.</summary>
    class function ControlWordText(AControlWord: Word): string; static;
    /// <summary>Gleich im Sinne der Masken: nur die Bits 0–5 werden verglichen.</summary>
    class function SameMasks(AControlWord, AOther: Word): Boolean; static;
    /// <summary>Geändert: das ganze Wort, auch Genauigkeit und Rundung.</summary>
    class function Changed(AOld, ANew: Word): Boolean; static;
    /// <summary>Teil einer Änderungszeile: „AName $033F (alle maskiert) → $137A (…)“, bei gleichen Masken mit
    /// „, Masken gleich“; ohne Änderung „AName unverändert $033F (…)“.</summary>
    class function ChangeText(const AName: string; AOld, ANew: Word): string; static;
    /// <summary>Zeile beim Anmelden: Vorgabe des Prozesses und Steuerwort des Hauptthreads mit Klartext, MXCSR
    /// (Vorgabe und Hauptthread) nur als Hex.</summary>
    class function StartLine(ADefault, AMain: Word; ADefaultMxcsr, AMainMxcsr: Cardinal): string; static;
    /// <summary>Zeile zu einer Änderung: alter → neuer Wert für Vorgabe und Hauptthread, Sekunden seit dem Anmelden und
    /// die laufende Nummer ANumber von höchstens AMax; die Meldung mit ANumber ≥ AMax sagt, dass weitere Änderungen
    /// nicht mehr gemeldet werden.</summary>
    class function ChangeLine(AOldDefault, ANewDefault, AOldMain, ANewMain: Word; ASeconds: Int64;
      ANumber, AMax: Integer): string; static;
  end;

  /// <summary>Zuletzt gemeldeter Stand (Vorgabe und Hauptthread) und Zahl der Änderungsmeldungen dieser Sitzung.
  /// Nach Clear bzw. ohne Reset inaktiv: Differs liefert dann False.</summary>
  TDpccFpuWatch = record
  private
    FActive: Boolean;
    FDefault: Word;
    FMain: Word;
    FReported: Integer;
    FMaxReports: Integer;
  public
    /// <summary>Beim Anmelden: Ausgangsstand merken, Zähler auf 0, aktiv.</summary>
    procedure Reset(ADefault, AMain: Word; AMaxReports: Integer = TDpccFpuState.cMaxReports);
    /// <summary>Beim Abmelden: inaktiv, alles auf 0.</summary>
    procedure Clear;
    /// <summary>Aktiv, Obergrenze nicht erreicht und mindestens eines der beiden Wörter anders als zuletzt gemeldet.
    /// Nur Vergleiche, kein Text.</summary>
    function Differs(ADefault, AMain: Word): Boolean;
    /// <summary>Gilt Differs: Zeile zur Änderung (ChangeLine), Zähler +1, neuer Stand gemerkt; sonst ''.</summary>
    function Take(ADefault, AMain: Word; ASeconds: Int64): string;
    property Active: Boolean read FActive;
    property Reported: Integer read FReported;
    property LastDefault: Word read FDefault;
    property LastMain: Word read FMain;
  end;

implementation

uses
  System.SysUtils;

{ TDpccFpuState }

class function TDpccFpuState.HexText(AValue: Cardinal): string;
begin
  Result := Format('$%.4X', [AValue]);
end;

class function TDpccFpuState.UnmaskedNames(AControlWord: Word): string;
const
  cNames: array[0..5] of string = ('Invalid', 'Denormal', 'ZeroDivide', 'Overflow', 'Underflow', 'Precision');
var
  mBit: Integer;
begin
  Result := '';
  for mBit := Low(cNames) to High(cNames) do
  begin
    if (AControlWord and (1 shl mBit)) = 0 then
    begin
      if Result <> '' then
      begin
        Result := Result + ', ';
      end;
      Result := Result + cNames[mBit];
    end;
  end;
end;

class function TDpccFpuState.ControlWordText(AControlWord: Word): string;
var
  mNames: string;
begin
  mNames := UnmaskedNames(AControlWord);
  if mNames = '' then
  begin
    Result := HexText(AControlWord) + ' (alle maskiert)';
  end
  else
  begin
    Result := HexText(AControlWord) + ' (nicht maskiert: ' + mNames + ')';
  end;
end;

class function TDpccFpuState.SameMasks(AControlWord, AOther: Word): Boolean;
begin
  Result := (AControlWord and cMaskBits) = (AOther and cMaskBits);
end;

class function TDpccFpuState.Changed(AOld, ANew: Word): Boolean;
begin
  Result := AOld <> ANew;
end;

class function TDpccFpuState.ChangeText(const AName: string; AOld, ANew: Word): string;
begin
  if not Changed(AOld, ANew) then
  begin
    Exit(AName + ' unverändert ' + ControlWordText(ANew));
  end;
  Result := AName + ' ' + ControlWordText(AOld) + ' → ' + ControlWordText(ANew);
  if SameMasks(AOld, ANew) then
  begin
    Result := Result + ', Masken gleich';
  end;
end;

class function TDpccFpuState.StartLine(ADefault, AMain: Word; ADefaultMxcsr, AMainMxcsr: Cardinal): string;
begin
  Result := Format('Gleitkomma beim Start: Vorgabe %s; Hauptthread %s; MXCSR Vorgabe %s, Hauptthread %s',
    [ControlWordText(ADefault), ControlWordText(AMain), HexText(ADefaultMxcsr), HexText(AMainMxcsr)]);
end;

class function TDpccFpuState.ChangeLine(AOldDefault, ANewDefault, AOldMain, ANewMain: Word; ASeconds: Int64;
  ANumber, AMax: Integer): string;
begin
  Result := Format('Gleitkomma geändert nach %d s (Meldung %d von höchstens %d): %s; %s',
    [ASeconds, ANumber, AMax, ChangeText('Vorgabe', AOldDefault, ANewDefault),
    ChangeText('Hauptthread', AOldMain, ANewMain)]);
  if ANumber >= AMax then
  begin
    Result := Result + '; weitere Änderungen werden nicht mehr gemeldet';
  end;
end;

{ TDpccFpuWatch }

procedure TDpccFpuWatch.Reset(ADefault, AMain: Word; AMaxReports: Integer);
begin
  FActive := True;
  FDefault := ADefault;
  FMain := AMain;
  FReported := 0;
  FMaxReports := AMaxReports;
end;

procedure TDpccFpuWatch.Clear;
begin
  FActive := False;
  FDefault := 0;
  FMain := 0;
  FReported := 0;
  FMaxReports := 0;
end;

function TDpccFpuWatch.Differs(ADefault, AMain: Word): Boolean;
begin
  Result := FActive and (FReported < FMaxReports) and
    (TDpccFpuState.Changed(FDefault, ADefault) or TDpccFpuState.Changed(FMain, AMain));
end;

function TDpccFpuWatch.Take(ADefault, AMain: Word; ASeconds: Int64): string;
begin
  if not Differs(ADefault, AMain) then
  begin
    Exit('');
  end;
  Inc(FReported);
  Result := TDpccFpuState.ChangeLine(FDefault, ADefault, FMain, AMain, ASeconds, FReported, FMaxReports);
  FDefault := ADefault;
  FMain := AMain;
end;

end.
