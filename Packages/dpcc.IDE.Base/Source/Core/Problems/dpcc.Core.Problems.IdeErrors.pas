unit dpcc.Core.Problems.IdeErrors;

// Fehler der IDE neben den dpcc-Befunden (#1819, problems.ideErrors), ohne
// VCL und Open Tools API.
// - ToProblem: ein Fehler aus Error Insight (TDpccIdeError, Werte wie in
//   TOTAError) als TDpccProblem mit Quelle "IDE"; Zeilen 0-basiert wie im
//   LSP. Art aus Severity wie im LSP (1 Fehler, 2 Warnung, 3 Info, 4 Hinweis),
//   unbekannte Werte gelten als Fehler: Error Insight meldet Fehler.
// - Merge: Abgleich mit den dpcc-Befunden der Datei. Ein Fehler der IDE an
//   derselben Zeile, mit überlappendem Bereich und derselben Art bestätigt
//   den dpcc-Befund (IdeConfirmed, Quelle „dpcc + IDE“) und fällt weg; der
//   Rest bleibt als „nur IDE“ stehen.
// - OriginOf: Quelle für Spalte und Filter „Quelle“ im Fenster
//   „dpcc-Prüfung“ (dpcc, dpcc + IDE, IDE; Compiler, Tests und Aufgaben
//   gehören zu keiner der beiden und heißen Other).
// - TDpccIdeErrorJournal: Befunde „nur dpcc“ der Regeln für undeklarierte
//   Bezeichner und unbekannte Typen sind Kandidaten für Fehlalarme. Je Stelle
//   einmal eine Zeile fürs Protokoll, ohne Datei- und Bezeichnernamen (#1478):
//   Regel, Art und Zeile.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Core.Problems.Contract;

type
  {$SCOPEDENUMS ON}
  /// <summary>Quelle eines Befunds (#1819): nur dpcc, dpcc und IDE, nur IDE, anderes (Compiler, Tests,
  /// Aufgaben).</summary>
  TDpccProblemOrigin = (Dpcc, Both, Ide, Other);
  {$SCOPEDENUMS OFF}

  TDpccIdeErrors = class
  public const
    /// <summary>Quelle der Diagnosen des Servers.</summary>
    cDpccSource = 'dpcc';
    /// <summary>Text der Quelle eines von der IDE bestätigten Befunds.</summary>
    cBothSource = 'dpcc + IDE';
    /// <summary>Regeln, deren Befunde „nur dpcc“ Fehlalarme sein können (undeklariert, unbekannter Typ).</summary>
    cFalseAlarmRules: array[0..2] of string = ('unresolved-identifier', 'unresolved-type', 'unresolved-attribute');
    /// <summary>Werte von Severity wie im LSP; alle anderen gelten als Fehler.</summary>
    cSeverityWarning = 2;
    cSeverityInformation = 3;
    cSeverityHint = 4;
  public
    /// <summary>Fehler der IDE als Problem mit Quelle "IDE", Zeilen und Spalten 0-basiert.</summary>
    class function ToProblem(const AError: TDpccIdeError): TDpccProblem; static;
    class function ToProblems(const AErrors: TArray<TDpccIdeError>): TArray<TDpccProblem>; static;
    /// <summary>Severity der IDE als Schweregrad; unbekannt = Fehler.</summary>
    class function SeverityOf(AValue: Integer): TDpccProblemSeverity; static;
    /// <summary>Befund von dpcc (Quelle "dpcc", auch vom Compiler bestätigt)?</summary>
    class function IsDpcc(const AProblem: TDpccProblem): Boolean; static;
    /// <summary>Bestätigt AIde den dpcc-Befund ADpcc? Gleiche Zeile, überlappender Bereich (leere Bereiche
    /// zählen als ein Zeichen), gleiche Art (Fehler, Warnung, Info und Hinweis zusammen).</summary>
    class function Matches(const ADpcc, AIde: TDpccProblem): Boolean; static;
    /// <summary>AProblems (Befunde einer Datei) und AIde (Fehler der IDE derselben Datei) zusammen: bestätigte
    /// dpcc-Befunde mit IdeConfirmed, ohne die bestätigenden Fehler der IDE; nach Position sortiert.</summary>
    class function Merge(const AProblems, AIde: TArray<TDpccProblem>): TArray<TDpccProblem>; static;
    class function OriginOf(const AProblem: TDpccProblem): TDpccProblemOrigin; static;
    /// <summary>Text der Spalte „Quelle“: "dpcc", "dpcc + IDE", "IDE" bzw. die Quelle selbst.</summary>
    class function OriginText(const AProblem: TDpccProblem): string; static;
    /// <summary>Gehört die Regel zu den möglichen Fehlalarmen (cFalseAlarmRules)?</summary>
    class function IsFalseAlarmRule(const ACode: string): Boolean; static;
  end;

  /// <summary>Protokoll möglicher Fehlalarme (#1819): Befunde „nur dpcc“ aus cFalseAlarmRules, je Stelle einmal.
  /// Nur im Hauptthread.</summary>
  TDpccIdeErrorJournal = class
  private
    FSeen: TDictionary<string, Boolean>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neue Zeilen fürs Protokoll aus den abgeglichenen Befunden AMerged der Datei AFileName (Ergebnis
    /// von Merge), ohne Namen: „Error Insight: nur dpcc, Regel unresolved-identifier, Fehler, Zeile 12“.</summary>
    function NewLines(const AFileName: string; const AMerged: TArray<TDpccProblem>): TArray<string>;
    /// <summary>Gemerkte Stellen vergessen (Speicher geleert).</summary>
    procedure Clear;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults;

const
  /// <summary>Bits der Spalte in PositionOf; die Zeile steht darüber.</summary>
  cLineShift = 32;
  /// <summary>Teile einer Protokollzeile möglicher Fehlalarme, englisch wie die übrigen Protokollzeilen.</summary>
  cJournalRule = 'Error Insight: dpcc only, rule ';
  cJournalSeparator = ', ';
  cJournalLine = ', line ';

{ TDpccIdeErrors }

class function TDpccIdeErrors.SeverityOf(AValue: Integer): TDpccProblemSeverity;
begin
  case AValue of
    cSeverityWarning:
      Result := TDpccProblemSeverity.Warning;
    cSeverityInformation:
      Result := TDpccProblemSeverity.Information;
    cSeverityHint:
      Result := TDpccProblemSeverity.Hint;
  else
    Result := TDpccProblemSeverity.Error;
  end;
end;

class function TDpccIdeErrors.ToProblem(const AError: TDpccIdeError): TDpccProblem;
begin
  Result := Default(TDpccProblem);
  Result.StartLine := Max(0, AError.StartLine - 1);
  Result.StartCharacter := Max(0, AError.StartCharIndex);
  Result.EndLine := Max(Result.StartLine, AError.StopLine - 1);
  Result.EndCharacter := Max(0, AError.StopCharIndex);
  if (Result.EndLine = Result.StartLine) and (Result.EndCharacter < Result.StartCharacter) then
  begin
    Result.EndCharacter := Result.StartCharacter;
  end;
  Result.Severity := SeverityOf(AError.Severity);
  Result.Source := TDpccProblem.cIdeSource;
  Result.Message := Trim(AError.Text);
end;

class function TDpccIdeErrors.ToProblems(const AErrors: TArray<TDpccIdeError>): TArray<TDpccProblem>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AErrors));
  for mIndex := 0 to High(AErrors) do
  begin
    Result[mIndex] := ToProblem(AErrors[mIndex]);
  end;
end;

class function TDpccIdeErrors.IsDpcc(const AProblem: TDpccProblem): Boolean;
begin
  Result := SameText(AProblem.Source, cDpccSource) or SameText(AProblem.Source, TDpccProblem.cConfirmedSource);
end;

/// <summary>Fehler, Warnung bzw. Info (Information und Hinweis).</summary>
function KindRank(ASeverity: TDpccProblemSeverity): Integer;
begin
  Result := Min(Ord(ASeverity), Ord(TDpccProblemSeverity.Information));
end;

/// <summary>Stelle als eine Zahl: Zeile vor Spalte.</summary>
function PositionOf(ALine, ACharacter: Integer): Int64;
begin
  Result := (Int64(ALine) shl cLineShift) + Max(0, ACharacter);
end;

class function TDpccIdeErrors.Matches(const ADpcc, AIde: TDpccProblem): Boolean;
var
  mStartA, mEndA, mStartB, mEndB: Int64;
begin
  if (ADpcc.StartLine <> AIde.StartLine) or (KindRank(ADpcc.Severity) <> KindRank(AIde.Severity)) then
  begin
    Exit(False);
  end;
  mStartA := PositionOf(ADpcc.StartLine, ADpcc.StartCharacter);
  mEndA := Max(PositionOf(ADpcc.EndLine, ADpcc.EndCharacter), mStartA + 1);
  mStartB := PositionOf(AIde.StartLine, AIde.StartCharacter);
  mEndB := Max(PositionOf(AIde.EndLine, AIde.EndCharacter), mStartB + 1);
  Result := (mStartA < mEndB) and (mStartB < mEndA);
end;

/// <summary>Index des ersten noch freien Fehlers der IDE, der ADpcc bestätigt; -1 ohne.</summary>
function MatchingIndex(const ADpcc: TDpccProblem; const AIde: TArray<TDpccProblem>;
  const AUsed: TArray<Boolean>): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AIde) do
  begin
    if not AUsed[mIndex] and TDpccIdeErrors.Matches(ADpcc, AIde[mIndex]) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure SortByPosition(var AProblems: TArray<TDpccProblem>);
begin
  TArray.Sort<TDpccProblem>(AProblems, TComparer<TDpccProblem>.Construct(
    function(const A, B: TDpccProblem): Integer
    begin
      Result := A.StartLine - B.StartLine;
      if Result = 0 then
      begin
        Result := A.StartCharacter - B.StartCharacter;
      end;
      if Result = 0 then
      begin
        Result := Ord(A.Severity) - Ord(B.Severity);
      end;
      // Nicht stabil sortiert: bei Gleichstand dpcc vor IDE, dann nach Meldung.
      if Result = 0 then
      begin
        Result := Ord(A.IsIde) - Ord(B.IsIde);
      end;
      if Result = 0 then
      begin
        Result := CompareStr(A.Message, B.Message);
      end;
    end));
end;

class function TDpccIdeErrors.Merge(const AProblems, AIde: TArray<TDpccProblem>): TArray<TDpccProblem>;
var
  mUsed: TArray<Boolean>;
  mIndex, mFound, mCount: Integer;
begin
  Result := Copy(AProblems);
  if AIde = nil then
  begin
    Exit;
  end;
  SetLength(mUsed, Length(AIde));
  for mIndex := 0 to High(Result) do
  begin
    if IsDpcc(Result[mIndex]) then
    begin
      mFound := MatchingIndex(Result[mIndex], AIde, mUsed);
      if mFound >= 0 then
      begin
        mUsed[mFound] := True;
        Result[mIndex].IdeConfirmed := True;
      end;
    end;
  end;
  mCount := Length(Result);
  SetLength(Result, mCount + Length(AIde));
  for mIndex := 0 to High(AIde) do
  begin
    if not mUsed[mIndex] then
    begin
      Result[mCount] := AIde[mIndex];
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
  SortByPosition(Result);
end;

class function TDpccIdeErrors.OriginOf(const AProblem: TDpccProblem): TDpccProblemOrigin;
begin
  if AProblem.IsIde then
  begin
    Result := TDpccProblemOrigin.Ide;
  end
  else if not IsDpcc(AProblem) then
  begin
    Result := TDpccProblemOrigin.Other;
  end
  else if AProblem.IdeConfirmed then
  begin
    Result := TDpccProblemOrigin.Both;
  end
  else
  begin
    Result := TDpccProblemOrigin.Dpcc;
  end;
end;

class function TDpccIdeErrors.OriginText(const AProblem: TDpccProblem): string;
begin
  case OriginOf(AProblem) of
    TDpccProblemOrigin.Dpcc:
      Result := cDpccSource;
    TDpccProblemOrigin.Both:
      Result := cBothSource;
    TDpccProblemOrigin.Ide:
      Result := TDpccProblem.cIdeSource;
  else
    Result := AProblem.Source;
  end;
end;

class function TDpccIdeErrors.IsFalseAlarmRule(const ACode: string): Boolean;
var
  mRule: string;
begin
  for mRule in cFalseAlarmRules do
  begin
    if SameText(mRule, ACode) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TDpccIdeErrorJournal }

constructor TDpccIdeErrorJournal.Create;
begin
  inherited Create;
  FSeen := TDictionary<string, Boolean>.Create;
end;

destructor TDpccIdeErrorJournal.Destroy;
begin
  FSeen.Free;
  inherited Destroy;
end;

/// <summary>Art für das Protokoll, englisch wie die übrigen Protokollzeilen.</summary>
function KindName(ASeverity: TDpccProblemSeverity): string;
begin
  case KindRank(ASeverity) of
    0:
      Result := 'error';
    1:
      Result := 'warning';
  else
    Result := 'info';
  end;
end;

function TDpccIdeErrorJournal.NewLines(const AFileName: string;
  const AMerged: TArray<TDpccProblem>): TArray<string>;
var
  mProblem: TDpccProblem;
  mKey: string;
begin
  Result := nil;
  for mProblem in AMerged do
  begin
    if (TDpccIdeErrors.OriginOf(mProblem) <> TDpccProblemOrigin.Dpcc) or
      not TDpccIdeErrors.IsFalseAlarmRule(mProblem.Code) then
    begin
      Continue;
    end;
    mKey := LowerCase(AFileName) + '|' + LowerCase(mProblem.Code) + '|' + IntToStr(mProblem.StartLine) + ':' +
      IntToStr(mProblem.StartCharacter);
    if FSeen.ContainsKey(mKey) then
    begin
      Continue;
    end;
    FSeen.Add(mKey, True);
    Result := Result + [cJournalRule + LowerCase(mProblem.Code) + cJournalSeparator + KindName(mProblem.Severity) +
      cJournalLine + IntToStr(mProblem.StartLine + 1)];
  end;
end;

procedure TDpccIdeErrorJournal.Clear;
begin
  FSeen.Clear;
end;

end.
