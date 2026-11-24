unit dpcc.Core.Editor.TabStops;

// Tabulatorpositionen des Editors (Editoroptionen der IDE, BufferOptions.TabStops) ohne IDE und ohne VCL. Bisher
// galt die erste Zahl der Angabe als Tabweite; die Angabe meint aber (Delphi-Hilfe, Editoroptionen):
//   - EINE Zahl: Abstand, alle N Spalten ("8" = Stopps in Spalte 9, 17, 25, …).
//   - MEHRERE Zahlen: absolute Spalten (1-basiert), aufsteigend. Hinter der letzten Position geht es im letzten
//     Abstand weiter: "3 5" = Stopps in Spalte 3, 5, 7, 9, … (Weite 2); "9 17" wie "8"; "4 10 20" = 4, 10, 20, 30, ….
//   - Leer oder ungültig (keine Zahl, Zahl < 1, nicht streng aufsteigend): wie bisher Abstand 8.
// Daraus die Umrechnung Editorspalte (1-basiert) ↔ Zeichenindex (0-basiert, UTF-16 wie im LSP): Ein Tab springt zur
// nächsten Tabulatorposition rechts der aktuellen Spalte, jedes andere Zeichen zählt eine Spalte, hinter dem
// Zeilenende je Zeichen eine Spalte. Rein und ohne Zugriff auf die IDE; der Wert hält nur wenige Zahlen.

interface

type
  /// <summary>Tabulatorpositionen einer Editoransicht. Default(TDpccTabStops) gilt wie Abstand 8.</summary>
  TDpccTabStops = record
  public const
    /// <summary>Abstand bei leerer oder ungültiger Angabe (wie bisher).</summary>
    cDefaultWidth = 8;
  private
    /// <summary>Feste Positionen (1-basiert, streng aufsteigend); nil bei gleichmäßigem Abstand.</summary>
    FStops: TArray<Integer>;
    /// <summary>Abstand überall (FStops = nil) bzw. hinter der letzten festen Position; &lt; 1 heißt
    /// cDefaultWidth.</summary>
    FWidth: Integer;
  public
    /// <summary>Gleichmäßig alle AWidth Spalten; AWidth &lt; 1 ergibt cDefaultWidth.</summary>
    class function Uniform(AWidth: Integer): TDpccTabStops; static;
    /// <summary>Aus der Angabe der Editoroptionen ("8", "3 5", "4 10 20"); Trenner sind Leerzeichen, Tab, Komma und
    /// Semikolon. Leer oder ungültig: Uniform(cDefaultWidth).</summary>
    class function Parse(const AText: string): TDpccTabStops; static;
    /// <summary>Gleichmäßiger Abstand (eine Zahl oder Vorgabe)?</summary>
    function IsUniform: Boolean;
    /// <summary>Abstand hinter der letzten festen Position (bei gleichmäßigem Abstand dieser), mindestens 1.
    /// Für Stellen, die nur eine Weite kennen (etwa FormattingOptions.tabSize des LSP).</summary>
    function Width: Integer;
    /// <summary>Die Positionen als Text: "8" bei gleichmäßigem Abstand, sonst die festen Positionen wie "3 5".
    /// </summary>
    function ToText: string;
    /// <summary>Nächste Tabulatorposition rechts von AColumn (1-basiert): Spalte, in der das Zeichen nach einem
    /// Tab in Spalte AColumn steht. AColumn &lt; 1 zählt wie 1.</summary>
    function NextStop(AColumn: Integer): Integer;
    /// <summary>Zeichenindex (0-basiert) zur Editorspalte AColumn (1-basiert) in ALine. Liegt AColumn in einem Tab,
    /// zählt das Zeichen nach ihm; hinter dem Zeilenende höchstens Length(ALine).</summary>
    function ColumnToIndex(const ALine: string; AColumn: Integer): Integer;
    /// <summary>Editorspalte (1-basiert) zum Zeichenindex AIndex (0-basiert) in ALine; Umkehrung von ColumnToIndex,
    /// hinter dem Zeilenende je Zeichen eine Spalte.</summary>
    function IndexToColumn(const ALine: string; AIndex: Integer): Integer;
    /// <summary>ALine mit jedem Tab als Leerzeichen bis zur nächsten Tabulatorposition (Anzeige im Editor).</summary>
    function DisplayLine(const ALine: string): string;
  end;

implementation

uses
  System.SysUtils;

{ TDpccTabStops }

class function TDpccTabStops.Uniform(AWidth: Integer): TDpccTabStops;
begin
  Result := Default(TDpccTabStops);
  if AWidth < 1 then
  begin
    AWidth := cDefaultWidth;
  end;
  Result.FWidth := AWidth;
end;

class function TDpccTabStops.Parse(const AText: string): TDpccTabStops;
var
  mParts: TArray<string>;
  mPart: string;
  mNumbers: TArray<Integer>;
  mValue, mCount: Integer;
begin
  Result := Uniform(cDefaultWidth);
  mParts := AText.Split([' ', #9, ',', ';'], TStringSplitOptions.ExcludeEmpty);
  mNumbers := nil;
  SetLength(mNumbers, Length(mParts));
  mCount := 0;
  for mPart in mParts do
  begin
    // Jede Angabe muss eine Zahl ≥ 1 sein; mehrere streng aufsteigend. Sonst gilt die Vorgabe ganz.
    if not TryStrToInt(Trim(mPart), mValue) or (mValue < 1) then
    begin
      Exit;
    end;
    if (mCount > 0) and (mValue <= mNumbers[mCount - 1]) then
    begin
      Exit;
    end;
    mNumbers[mCount] := mValue;
    Inc(mCount);
  end;
  if mCount = 0 then
  begin
    Exit;
  end;
  if mCount = 1 then
  begin
    // Eine Zahl: Abstand.
    Exit(Uniform(mNumbers[0]));
  end;
  SetLength(mNumbers, mCount);
  Result.FStops := mNumbers;
  Result.FWidth := mNumbers[mCount - 1] - mNumbers[mCount - 2];
end;

function TDpccTabStops.IsUniform: Boolean;
begin
  Result := Length(FStops) = 0;
end;

function TDpccTabStops.Width: Integer;
begin
  Result := FWidth;
  if Result < 1 then
  begin
    Result := cDefaultWidth;
  end;
end;

function TDpccTabStops.ToText: string;
var
  mIndex: Integer;
begin
  if IsUniform then
  begin
    Exit(IntToStr(Width));
  end;
  Result := '';
  for mIndex := 0 to High(FStops) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ' ';
    end;
    Result := Result + IntToStr(FStops[mIndex]);
  end;
end;

function TDpccTabStops.NextStop(AColumn: Integer): Integer;
var
  mStop, mLast, mWidth: Integer;
begin
  if AColumn < 1 then
  begin
    AColumn := 1;
  end;
  mWidth := Width;
  if IsUniform then
  begin
    // Spalte 1, 1 + N, 1 + 2N, …: von AColumn zur nächsten davon.
    Exit(((AColumn - 1) div mWidth + 1) * mWidth + 1);
  end;
  for mStop in FStops do
  begin
    if mStop > AColumn then
    begin
      Exit(mStop);
    end;
  end;
  // Hinter der letzten festen Position im letzten Abstand weiter.
  mLast := FStops[High(FStops)];
  Result := mLast + ((AColumn - mLast) div mWidth + 1) * mWidth;
end;

function TDpccTabStops.ColumnToIndex(const ALine: string; AColumn: Integer): Integer;
var
  mVisual: Integer;
begin
  // Spalte 1 = erstes Zeichen. Wie bisher: Ein Zeichen, dessen Spalten AColumn überdecken (Tab), gilt als
  // übersprungen, sobald seine Anfangsspalte vor AColumn liegt.
  Result := 0;
  mVisual := 1;
  while (Result < Length(ALine)) and (mVisual < AColumn) do
  begin
    if ALine[Result + 1] = #9 then
    begin
      mVisual := NextStop(mVisual);
    end
    else
    begin
      Inc(mVisual);
    end;
    Inc(Result);
  end;
end;

function TDpccTabStops.IndexToColumn(const ALine: string; AIndex: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 1;
  for mIndex := 1 to AIndex do
  begin
    if (mIndex <= Length(ALine)) and (ALine[mIndex] = #9) then
    begin
      Result := NextStop(Result);
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

function TDpccTabStops.DisplayLine(const ALine: string): string;
var
  mBuilder: TStringBuilder;
  mChar: Char;
begin
  if Pos(#9, ALine) = 0 then
  begin
    Exit(ALine);
  end;
  mBuilder := TStringBuilder.Create(Length(ALine) + 16);
  try
    for mChar in ALine do
    begin
      if mChar = #9 then
      begin
        // Spalte des nächsten Zeichens ist Length + 1; bis zur nächsten Position mit Leerzeichen auffüllen.
        mBuilder.Append(' ', NextStop(mBuilder.Length + 1) - (mBuilder.Length + 1));
      end
      else
      begin
        mBuilder.Append(mChar);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
