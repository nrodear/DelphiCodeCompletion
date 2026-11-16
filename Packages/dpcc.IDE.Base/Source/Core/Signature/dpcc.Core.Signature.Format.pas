unit dpcc.Core.Signature.Format;

// Platzhalter im Parameter-Hint (#451), ohne Fenster: was die Hint-Zeile zum Eintrag am Cursor sagt und welche
// Stellen im Editor welche Farbe bekommen. Die Daten liefert der Server (TDpccSignatureFormat).
// - Zeile: Problem zuerst (ungültiger Platzhalter, überzähliges Argument, Typkonflikt mit einem Literal), dann
//   der Platzhalter des Eintrags am Cursor („Platzhalter 2 von 2 erwartet ganzzahlig“), bei "*" Breite bzw.
//   Genauigkeit, ohne Platzhalter „kommt nicht vor“.
// - Farben: Platzhalter i und sein Argument bekommen Farbe i mod SlotCount; ein Argument, das nur Breite oder
//   Genauigkeit liefert, die Farbe seines Platzhalters. Nur einzeilige Stellen; leere Einträge nicht.

interface

uses
  System.SysUtils,
  dpcc.Core.Signature.Contract;

type
  {$SCOPEDENUMS ON}
  TDpccFormatLineKind = (None, Placeholder, Width, Precision, Unused, Problem);
  {$SCOPEDENUMS OFF}

  /// <summary>Inhalt der Hint-Zeile; die Texte baut die Oberfläche.</summary>
  TDpccFormatLine = record
    Kind: TDpccFormatLineKind;
    /// <summary>Platzhalter ab 0 und ihre Zahl.</summary>
    Placeholder: Integer;
    Count: Integer;
    /// <summary>Typbuchstabe des Platzhalters bzw. "*" für Breite und Genauigkeit.</summary>
    TypeChar: Char;
    PlaceholderText: string;
    /// <summary>Argument ab 0 (Unused, Problem).</summary>
    Argument: Integer;
    Problem: TDpccFormatProblem;
    /// <summary>Art des Literals beim Typkonflikt.</summary>
    ProblemKind: string;
    function IsError: Boolean;
  end;

  /// <summary>Eine einzufärbende Stelle in einer Zeile (Zeichen ab 0, Stop exklusiv).</summary>
  TDpccFormatMark = record
    Line: Integer;
    Start: Integer;
    Stop: Integer;
    Slot: Integer;
  end;

  TDpccSignatureFormats = record
  public const
    /// <summary>Zahl der Farben; danach wiederholen sie sich.</summary>
    cSlotCount = 6;
  public
    /// <summary>Zeile zum Eintrag AArgument (-1 außerhalb der Liste: nur ein Problem).</summary>
    class function Line(const AFormat: TDpccSignatureFormat; AArgument: Integer): TDpccFormatLine; static;
    /// <summary>Alle einzufärbenden Stellen, nach Zeile und Anfang sortiert.</summary>
    class function Marks(const AFormat: TDpccSignatureFormat): TArray<TDpccFormatMark>; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults;

{ TDpccFormatLine }

function TDpccFormatLine.IsError: Boolean;
begin
  Result := Kind in [TDpccFormatLineKind.Problem, TDpccFormatLineKind.Unused];
end;

/// <summary>Zeile bei einem Problem des Formats.</summary>
procedure ProblemLine(const AFormat: TDpccSignatureFormat; var ALine: TDpccFormatLine);
begin
  ALine.Kind := TDpccFormatLineKind.Problem;
  ALine.Problem := AFormat.Problem;
  ALine.Placeholder := AFormat.ProblemPlaceholder;
  ALine.Argument := AFormat.ProblemArgument;
  ALine.ProblemKind := AFormat.ProblemKind;
  if (ALine.Placeholder >= 0) and (ALine.Placeholder < ALine.Count) then
  begin
    ALine.TypeChar := AFormat.Placeholders[ALine.Placeholder].TypeChar;
    ALine.PlaceholderText := AFormat.Placeholders[ALine.Placeholder].Text;
    // Konflikt beim "*": Breite bzw. Genauigkeit erwartet eine Ganzzahl.
    if (AFormat.Problem = TDpccFormatProblem.TypeConflict) and
      (AFormat.Placeholders[ALine.Placeholder].Argument <> ALine.Argument) then
    begin
      ALine.TypeChar := '*';
    end;
  end;
end;

/// <summary>Was AArgument für APlaceholder liefert; None, wenn nichts.</summary>
function RoleOf(const APlaceholder: TDpccFormatPlaceholder; AArgument: Integer): TDpccFormatLineKind;
begin
  if APlaceholder.Argument = AArgument then
  begin
    Result := TDpccFormatLineKind.Placeholder;
  end
  else if APlaceholder.WidthArgument = AArgument then
  begin
    Result := TDpccFormatLineKind.Width;
  end
  else if APlaceholder.PrecisionArgument = AArgument then
  begin
    Result := TDpccFormatLineKind.Precision;
  end
  else
  begin
    Result := TDpccFormatLineKind.None;
  end;
end;

/// <summary>Zeile zum Eintrag AArgument ohne Problem: sein Platzhalter oder (bei bekannter Zuordnung) Unused.
/// </summary>
procedure ArgumentLine(const AFormat: TDpccSignatureFormat; AArgument: Integer; var ALine: TDpccFormatLine);
var
  mIndex: Integer;
  mKind: TDpccFormatLineKind;
begin
  for mIndex := 0 to High(AFormat.Placeholders) do
  begin
    mKind := RoleOf(AFormat.Placeholders[mIndex], AArgument);
    if mKind <> TDpccFormatLineKind.None then
    begin
      ALine.Kind := mKind;
      ALine.Placeholder := mIndex;
      ALine.PlaceholderText := AFormat.Placeholders[mIndex].Text;
      ALine.TypeChar := '*';
      if mKind = TDpccFormatLineKind.Placeholder then
      begin
        ALine.TypeChar := AFormat.Placeholders[mIndex].TypeChar;
      end;
      Exit;
    end;
  end;
  // Kein Platzhalter für diesen Eintrag (bei bekannter Zuordnung).
  if AFormat.ArgumentCount >= 0 then
  begin
    ALine.Kind := TDpccFormatLineKind.Unused;
  end;
end;

/// <summary>Platzhalter, dessen Farbe ein Argument bekommt; -1 ohne. Erst der Wert, dann Breite und
/// Genauigkeit: ein Argument bekommt die Farbe des Platzhalters, den es füllt.</summary>
function SlotsOf(const AFormat: TDpccSignatureFormat): TArray<Integer>;

  procedure Take(var ASlots: TArray<Integer>; AArgument, APlaceholder: Integer);
  begin
    if (AArgument >= 0) and (AArgument <= High(ASlots)) and (ASlots[AArgument] < 0) then
    begin
      ASlots[AArgument] := APlaceholder;
    end;
  end;

var
  mIndex: Integer;
begin
  SetLength(Result, Length(AFormat.Arguments));
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := -1;
  end;
  for mIndex := 0 to High(AFormat.Placeholders) do
  begin
    Take(Result, AFormat.Placeholders[mIndex].Argument, mIndex);
  end;
  for mIndex := 0 to High(AFormat.Placeholders) do
  begin
    Take(Result, AFormat.Placeholders[mIndex].WidthArgument, mIndex);
    Take(Result, AFormat.Placeholders[mIndex].PrecisionArgument, mIndex);
  end;
end;

/// <summary>Nur einzeilige, nicht leere Stellen.</summary>
procedure AddMark(var AMarks: TArray<TDpccFormatMark>; const ARange: TDpccFormatRange; ASlot: Integer);
var
  mMark: TDpccFormatMark;
begin
  if (ARange.StartLine <> ARange.EndLine) or (ARange.StartCharacter >= ARange.EndCharacter) or
    (ARange.StartLine < 0) then
  begin
    Exit;
  end;
  mMark.Line := ARange.StartLine;
  mMark.Start := ARange.StartCharacter;
  mMark.Stop := ARange.EndCharacter;
  mMark.Slot := ASlot mod TDpccSignatureFormats.cSlotCount;
  AMarks := AMarks + [mMark];
end;

function MarkOrder(const A, B: TDpccFormatMark): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Start - B.Start;
  end;
  if Result = 0 then
  begin
    Result := A.Stop - B.Stop;
  end;
end;

{ TDpccSignatureFormats }

class function TDpccSignatureFormats.Line(const AFormat: TDpccSignatureFormat; AArgument: Integer): TDpccFormatLine;
begin
  Result := Default(TDpccFormatLine);
  Result.Placeholder := -1;
  Result.Argument := AArgument;
  Result.Count := Length(AFormat.Placeholders);
  if not AFormat.Found then
  begin
    Exit;
  end;
  if AFormat.Problem <> TDpccFormatProblem.None then
  begin
    ProblemLine(AFormat, Result);
  end
  else if AArgument >= 0 then
  begin
    ArgumentLine(AFormat, AArgument, Result);
  end;
end;

class function TDpccSignatureFormats.Marks(const AFormat: TDpccSignatureFormat): TArray<TDpccFormatMark>;
var
  mIndex: Integer;
  mPlaceholder: TDpccFormatPlaceholder;
  mSlots: TArray<Integer>;
begin
  Result := nil;
  if not AFormat.Found then
  begin
    Exit;
  end;
  mSlots := SlotsOf(AFormat);
  for mIndex := 0 to High(AFormat.Placeholders) do
  begin
    mPlaceholder := AFormat.Placeholders[mIndex];
    if mPlaceholder.Valid and mPlaceholder.HasRange then
    begin
      AddMark(Result, mPlaceholder.Range, mIndex);
    end;
  end;
  for mIndex := 0 to High(AFormat.Arguments) do
  begin
    if mSlots[mIndex] >= 0 then
    begin
      AddMark(Result, AFormat.Arguments[mIndex], mSlots[mIndex]);
    end;
  end;
  TArray.Sort<TDpccFormatMark>(Result, TComparer<TDpccFormatMark>.Construct(MarkOrder));
end;

end.
