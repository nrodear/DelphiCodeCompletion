unit dpcc.Common.Index.Files;

// Zuordnung von Dateien zu Units des Index (#500): die Unit einer Datei oder
// eine Unit, die sie per $I einbindet. Steht im Root des Features Index, weil
// ein Contract nur Typen und Interfaces enthält.
//
// Volle Signatur aus der Quelle (Index-Inhalte L1): Der Index kürzt Signaturen von Konstanten, Aufzählungen und
// Typen auf TIndexSymbol.cMaxSignature Zeichen und speichert für Deklarationen aus nicht geltenden Zweigen nur Name,
// Art und Zeile. SourceSignature liest den Kopf der Deklaration bei Bedarf aus dem Text der Datei über Range (bzw.
// die Zeile), ungekürzt und so formatiert wie die Signatur im Index.

interface

uses
  dpcc.Common.Index.Contract;

type
  /// <summary>Liest den Text einer Datei (Editor-Puffer oder Platte); False, wenn sie fehlt.</summary>
  TIndexReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  TIndexFiles = class
  public
    /// <summary>Unit zu AFileName: die Unit dieser Datei, sonst eine Unit, die sie per $I einbindet (#500).</summary>
    class function UnitOf(const AIndex: ISymbolIndex; const AFileName: string; out AUnit: TUnitIndex): Boolean;
      static;
    /// <summary>Volle Signatur von ASymbol aus AText, dem Text seiner Datei (L1): Kopf der Deklaration im Bereich
    /// Range als eine Zeile, ungekürzt, ohne Kommentare und abschließendes Semikolon. Typen mit Rumpf (class,
    /// record, interface, helper) nur ihre erste Zeile; Routinen bis hinter die Direktiven, ohne Rumpf. Bei
    /// Deklarationen aus nicht geltenden Zweigen (Unavailable, nur die Zeile bekannt) ab dem Anfang der Zeile bis
    /// zum Ende der Deklaration. '' ohne Treffer.</summary>
    class function SourceSignature(const AText: string; const ASymbol: TIndexSymbol): string; static;
    /// <summary>Wie oben; liest die Datei von ASymbol (AUnit.SymbolFile) über AReadText. False, wenn sie sich nicht
    /// lesen lässt oder dort nichts steht.</summary>
    class function SourceSignatureOf(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol;
      const AReadText: TIndexReadText; out ASignature: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  dpcc.Common.Documents.Contract,
  dpcc.Common.Pascal.Contract,
  dpcc.Common.Pascal.Lexer,
  dpcc.Common.Pascal.DirectiveNames,
  dpcc.Common.Index.Extractor.Tokens;

const
  /// <summary>So viele Zeilen ab der Zeile einer nicht geltenden Deklaration höchstens lesen.</summary>
  cUnavailableLines = 40;

{ TIndexFiles }

class function TIndexFiles.UnitOf(const AIndex: ISymbolIndex; const AFileName: string; out AUnit: TUnitIndex): Boolean;
var
  mCandidate: TUnitIndex;
begin
  Result := (AIndex <> nil) and AIndex.FindFile(AFileName, AUnit);
  if Result or (AIndex = nil) then
  begin
    Exit;
  end;
  for mCandidate in AIndex.Units do
  begin
    if IndexText(AFileName, mCandidate.Includes) >= 0 then
    begin
      AUnit := mCandidate;
      Exit(True);
    end;
  end;
end;

/// <summary>Text von APosition bis AEnd (ausgeschlossen) aus ALines; Zeilen mit #10 verbunden.</summary>
function TextBetween(const ALines: TArray<string>; const AStart, AEnd: TTextPosition): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine := Max(AStart.Line, 0) to Min(AEnd.Line, High(ALines)) do
  begin
    if mLine > AStart.Line then
    begin
      Result := Result + #10;
    end;
    if (mLine = AStart.Line) and (mLine = AEnd.Line) then
    begin
      Result := Result + Copy(ALines[mLine], AStart.Character + 1, AEnd.Character - AStart.Character);
    end
    else if mLine = AStart.Line then
    begin
      Result := Result + Copy(ALines[mLine], AStart.Character + 1, MaxInt);
    end
    else if mLine = AEnd.Line then
    begin
      Result := Result + Copy(ALines[mLine], 1, AEnd.Character);
    end
    else
    begin
      Result := Result + ALines[mLine];
    end;
  end;
end;

/// <summary>Steht an AIndex eine Direktive, die noch zum Kopf einer Routine gehört (overload, external, deprecated
/// …)?</summary>
function IsHeaderDirective(const ATokens: TArray<TPascalToken>; AIndex: Integer): Boolean;
begin
  Result := (AIndex <= High(ATokens)) and (ATokens[AIndex].Kind in [TPascalTokenKind.Identifier,
    TPascalTokenKind.Keyword]) and (TDirectiveNames.IsRoutineDirective(ATokens[AIndex].Text) or
    MatchText(ATokens[AIndex].Text, ['inline', 'library', 'deprecated', 'platform', 'experimental']));
end;

/// <summary>Nächstes Token ab AIndex, das weder Kommentar noch Direktive ist.</summary>
function NextCode(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Letztes Token bis AIndex, das weder Kommentar noch Direktive ist (0, wenn keins).</summary>
function NextCodeBack(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result > 0) and (ATokens[Result].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Letztes Token der Deklaration in ATokens: bis zum ersten ";" außerhalb von Klammern, bei Routinen
/// (ARoutine) samt der Direktiven dahinter.</summary>
function DeclarationEnd(const ATokens: TArray<TPascalToken>; ARoutine: Boolean): Integer;
var
  mIndex, mDepth: Integer;
begin
  mDepth := 0;
  for mIndex := 0 to High(ATokens) do
  begin
    if ATokens[mIndex].IsSymbol('(') or ATokens[mIndex].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if (ATokens[mIndex].IsSymbol(')') or ATokens[mIndex].IsSymbol(']')) and (mDepth > 0) then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and ATokens[mIndex].IsSymbol(';') and
      not (ARoutine and IsHeaderDirective(ATokens, NextCode(ATokens, mIndex + 1))) then
    begin
      Exit(mIndex);
    end
    else if (mDepth = 0) and ARoutine and (ATokens[mIndex].Kind = TPascalTokenKind.Keyword) and
      MatchText(ATokens[mIndex].Text, ['begin', 'asm', 'var', 'const', 'type', 'label']) and (mIndex > 0) and
      ATokens[NextCodeBack(ATokens, mIndex - 1)].IsSymbol(';') then
    begin
      Exit(mIndex - 1);
    end;
  end;
  Result := High(ATokens);
end;

class function TIndexFiles.SourceSignature(const AText: string; const ASymbol: TIndexSymbol): string;
var
  mLines: TArray<string>;
  mStart, mEnd: TTextPosition;
  mTokens: TArray<TPascalToken>;
  mReader: TIndexTokenReader;
  mRoutine, mFirstLine: Boolean;
begin
  Result := '';
  mLines := AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]);
  if ASymbol.Unavailable then
  begin
    // Nur die Zeile ist bekannt: ab ihrem Anfang, höchstens cUnavailableLines Zeilen.
    mStart := TTextPosition.Create(ASymbol.SelectionRange.StartPos.Line, 0);
    mEnd := TTextPosition.Create(ASymbol.SelectionRange.StartPos.Line + cUnavailableLines, MaxInt div 2);
  end
  else
  begin
    mStart := ASymbol.Range.StartPos;
    mEnd := ASymbol.Range.EndPos;
  end;
  if (mStart.Line < 0) or (mStart.Line > High(mLines)) then
  begin
    Exit;
  end;
  mRoutine := ASymbol.Kind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_];
  mFirstLine := ASymbol.Kind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType];
  // Rumpf einer Klasse bzw. Routine nicht ganz lesen: Der Kopf steht in den ersten Zeilen.
  if (mFirstLine or mRoutine) and (mEnd.Line > mStart.Line + cUnavailableLines) then
  begin
    mEnd := TTextPosition.Create(mStart.Line + cUnavailableLines, MaxInt div 2);
  end;
  mTokens := TPascalLexer.Tokenize(TextBetween(mLines, mStart, mEnd));
  if Length(mTokens) = 0 then
  begin
    Exit;
  end;
  mReader := TIndexTokenReader.Create(mTokens);
  try
    if mFirstLine then
    begin
      Result := mReader.TokenText(0, High(mTokens), True, 0);
    end
    else
    begin
      Result := mReader.TokenText(0, DeclarationEnd(mTokens, mRoutine), False, 0);
    end;
  finally
    mReader.Free;
  end;
  while Result.EndsWith(';') do
  begin
    Result := Copy(Result, 1, Length(Result) - 1).TrimRight;
  end;
end;

class function TIndexFiles.SourceSignatureOf(const AUnit: TUnitIndex; const ASymbol: TIndexSymbol;
  const AReadText: TIndexReadText; out ASignature: string): Boolean;
var
  mText: string;
begin
  ASignature := '';
  Result := Assigned(AReadText) and AReadText(AUnit.SymbolFile(ASymbol), mText);
  if Result then
  begin
    ASignature := SourceSignature(mText, ASymbol);
    Result := ASignature <> '';
  end;
end;

end.
