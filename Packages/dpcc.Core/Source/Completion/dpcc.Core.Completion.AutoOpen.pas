unit dpcc.Core.Completion.AutoOpen;

// Automatisches Öffnen der Vervollständigung beim Tippen (L5, Einstellung completion.autoMinChars). Ohne IDE und
// ohne Fenster, damit die Regel testbar ist; die IDE-Schicht (dpcc.IDE.Completion.Editor, …EditorOpen) fragt sie
// bei jeder Änderung im Editor und noch einmal vor der Anfrage.
// - Strg+Leertaste (Key) fragt immer, bei jeder Länge des Worts, auch bei offener Liste: wie bisher.
// - Auslösezeichen (Trigger: "." und "[" von der IDE, "(" hinter einem Namen, ";" bzw. Enter hinter einem
//   übernommenen Konstruktor, "{" in einer Wertdarstellung, "'" in FieldByName, "<" in XMLDoc) behalten ihre
//   eigenen Regeln und fragen wie bisher.
// - Tippen (Typing) eines Bezeichners ohne Punkt davor öffnet die Liste erst, wenn das Wort vor dem Cursor
//   AMinChars Zeichen hat (Vorgabe seit NAV 0 = nie wie vor L5; zum Einschalten etwa 5). Darunter keine Anfrage an den Server und
//   kein Popup: Listen des Gültigkeitsbereichs haben bei kurzem Anfang oft über tausend Einträge (bis ~200 ms
//   Rechenzeit im Server). Nach einem Punkt (Mitgliederliste, die kommt wie bisher über "."), in Kommentaren (auch
//   Direktiven "{$"), in Strings, in Zahlen ($FF, #13, 1E5) und mitten in einem Wort öffnet Tippen nie.
//   Welche Liste kommt (Gültigkeitsbereich, uses, raise, Attribut), entscheidet wie bei Strg+Leertaste der Server;
//   seine eigene Grenze bleibt: Units, die noch nicht in uses stehen, erst ab 2 Zeichen.
// - Ist die Liste schon offen (etwa mit Strg+Leertaste bei weniger Zeichen geöffnet), filtert sie beim Tippen
//   weiter (Filter); Tippen startet keine neue Anfrage.
// TDpccTypingTracker erkennt aus zwei aufeinanderfolgenden Ständen einer Zeile, ob genau ein Zeichen eines
// Bezeichners direkt vor dem Cursor dazugekommen ist. Einfügen, das Übernehmen eines Eintrags, Rücktaste und
// Änderungen mit mehreren Zeichen lösen nichts aus.

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Woher eine Anfrage der Vervollständigung kommt.</summary>
  TDpccCompletionSource = (
    /// <summary>Strg+Leertaste.</summary>
    Key,
    /// <summary>Automatisch nach einem Auslösezeichen, mit dessen eigenen Regeln.</summary>
    Trigger,
    /// <summary>Automatisch beim Tippen eines Bezeichners ohne Punkt davor (L5).</summary>
    Typing);

  /// <summary>Was eine Eingabe mit der Liste tut.</summary>
  TDpccAutoOpenAction = (
    /// <summary>Keine Anfrage, kein Popup.</summary>
    None,
    /// <summary>Anfragen und die Liste öffnen (bzw. neu öffnen).</summary>
    Query,
    /// <summary>Die offene Liste filtert weiter; keine neue Anfrage.</summary>
    Filter);

  TDpccAutoOpen = record
  public const
    /// <summary>Vorgabe von completion.autoMinChars: 0 = aus, wie vor L5 (Entscheidung des Nutzers nach L5); wer
    /// das Öffnen beim Tippen will, stellt etwa 5 ein.</summary>
    cDefaultMinChars = 0;
    /// <summary>0 = Tippen öffnet nie (wie vor L5).</summary>
    cMinMinChars = 0;
    cMaxMinChars = 10;
  public
    /// <summary>Steht ALine bis vor das Zeichen an AIndex (0-basiert: AIndex Zeichen davor) im Code, nicht in einem
    /// String oder Kommentar dieser Zeile? Kommentare aus früheren Zeilen sieht die Zeile nicht.</summary>
    class function InCode(const ALine: string; AIndex: Integer): Boolean; static;
    /// <summary>Länge des Bezeichners direkt vor dem Cursor (ACharacter Zeichen davor), wenn Tippen dort öffnen
    /// darf; 0 nach einem Punkt, in Kommentar, String oder Zahl, mitten in einem Wort und ohne Wort.</summary>
    class function TypedWord(const ALine: string; ACharacter: Integer): Integer; static;
    /// <summary>Entscheidung für eine Eingabe aus ASource am Cursor (ALine, ACharacter Zeichen davor). AListOpen:
    /// Die Liste ist offen (auch während sie lädt). AMinChars: completion.autoMinChars (0 = Tippen öffnet nie).
    /// </summary>
    class function Action(ASource: TDpccCompletionSource; const ALine: string; ACharacter: Integer;
      AListOpen: Boolean; AMinChars: Integer): TDpccAutoOpenAction; static;
  end;

  /// <summary>Letzter Stand der Zeile des Cursors, um ein getipptes Zeichen zu erkennen.</summary>
  TDpccTypingTracker = record
  private
    FValid: Boolean;
    FFileName: string;
    FLine: Integer;
    FLineText: string;
  public
    /// <summary>Neuer Stand nach einer Änderung im Editor (Zeile ALine, ALineText, Cursor nach ACharacter Zeichen).
    /// True, wenn gegenüber dem vorigen Stand derselben Zeile genau ein Zeichen eines Bezeichners direkt vor dem
    /// Cursor dazugekommen ist und sonst nichts. Merkt sich den neuen Stand.</summary>
    function Typed(const AFileName: string; ALine, ACharacter: Integer; const ALineText: string): Boolean;
    /// <summary>Vergisst den Stand; die nächste Änderung zählt nicht als Tippen.</summary>
    procedure Reset;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Completion.Word;

type
  TLineState = (Code, Text, Brace, Paren);

{ TDpccAutoOpen }

class function TDpccAutoOpen.InCode(const ALine: string; AIndex: Integer): Boolean;
var
  mIndex, mLast, mParenAt: Integer;
  mState: TLineState;
begin
  mState := TLineState.Code;
  mParenAt := 0;
  mLast := AIndex;
  if mLast > Length(ALine) then
  begin
    mLast := Length(ALine);
  end;
  mIndex := 1;
  while mIndex <= mLast do
  begin
    case mState of
      TLineState.Code:
        if ALine[mIndex] = '''' then
        begin
          mState := TLineState.Text;
        end
        else if ALine[mIndex] = '{' then
        begin
          mState := TLineState.Brace;
        end
        else if (ALine[mIndex] = '(') and (mIndex < Length(ALine)) and (ALine[mIndex + 1] = '*') then
        begin
          mState := TLineState.Paren;
          mParenAt := mIndex;
          Inc(mIndex);
        end
        else if (ALine[mIndex] = '/') and (mIndex < Length(ALine)) and (ALine[mIndex + 1] = '/') then
        begin
          Exit(False);
        end;
      TLineState.Text:
        // '' im String schließt und öffnet gleich wieder.
        if ALine[mIndex] = '''' then
        begin
          mState := TLineState.Code;
        end;
      TLineState.Brace:
        if ALine[mIndex] = '}' then
        begin
          mState := TLineState.Code;
        end;
      TLineState.Paren:
        if (ALine[mIndex] = ')') and (ALine[mIndex - 1] = '*') and (mIndex - 1 > mParenAt + 1) then
        begin
          mState := TLineState.Code;
        end;
    end;
    Inc(mIndex);
  end;
  Result := mState = TLineState.Code;
end;

class function TDpccAutoOpen.TypedWord(const ALine: string; ACharacter: Integer): Integer;
var
  mStart: Integer;
begin
  Result := 0;
  if (ACharacter <= 0) or (ACharacter > Length(ALine)) then
  begin
    Exit;
  end;
  // Mitten in einem Wort (etwa beim Umbenennen): nicht öffnen.
  if (ACharacter < Length(ALine)) and TDpccWord.IsIdentifierChar(ALine[ACharacter + 1]) then
  begin
    Exit;
  end;
  mStart := TDpccWord.StartBefore(ALine, ACharacter);
  if mStart = ACharacter then
  begin
    Exit;
  end;
  // Zahl (1E5) bzw. Zahl mit Vorzeichen ($FF, #13, %101): kein Bezeichner.
  if CharInSet(ALine[mStart + 1], ['0'..'9']) then
  begin
    Exit;
  end;
  // Nach einem Punkt: Mitgliederliste, die kommt wie bisher über "." (auch Bereiche "1..Max").
  if (mStart > 0) and CharInSet(ALine[mStart], ['.', '$', '#', '%']) then
  begin
    Exit;
  end;
  if not InCode(ALine, mStart) then
  begin
    Exit;
  end;
  Result := ACharacter - mStart;
end;

class function TDpccAutoOpen.Action(ASource: TDpccCompletionSource; const ALine: string; ACharacter: Integer;
  AListOpen: Boolean; AMinChars: Integer): TDpccAutoOpenAction;
begin
  if ASource <> TDpccCompletionSource.Typing then
  begin
    // Strg+Leertaste und Auslösezeichen: wie bisher.
    Exit(TDpccAutoOpenAction.Query);
  end;
  if AListOpen then
  begin
    Result := TDpccAutoOpenAction.Filter;
  end
  else if (AMinChars > 0) and (TypedWord(ALine, ACharacter) >= AMinChars) then
  begin
    Result := TDpccAutoOpenAction.Query;
  end
  else
  begin
    Result := TDpccAutoOpenAction.None;
  end;
end;

{ TDpccTypingTracker }

function TDpccTypingTracker.Typed(const AFileName: string; ALine, ACharacter: Integer;
  const ALineText: string): Boolean;
begin
  // Nur der Text zählt, nicht der vorige Cursor: Pfeiltasten und Mausklicks melden keine Änderung, der gemerkte
  // Cursor wäre dann veraltet.
  Result := FValid and (ALine = FLine) and SameText(AFileName, FFileName) and
    (Length(ALineText) = Length(FLineText) + 1) and (ACharacter >= 1) and (ACharacter <= Length(ALineText)) and
    TDpccWord.IsIdentifierChar(ALineText[ACharacter]) and
    (Copy(ALineText, 1, ACharacter - 1) + Copy(ALineText, ACharacter + 1, MaxInt) = FLineText);
  FValid := True;
  FFileName := AFileName;
  FLine := ALine;
  FLineText := ALineText;
end;

procedure TDpccTypingTracker.Reset;
begin
  FValid := False;
  FFileName := '';
  FLine := 0;
  FLineText := '';
end;

end.
