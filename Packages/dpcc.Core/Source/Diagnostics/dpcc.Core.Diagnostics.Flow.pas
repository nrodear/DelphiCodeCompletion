unit dpcc.Core.Diagnostics.Flow;

// Ablaufprotokoll (LOG1), ohne VCL und ohne Open Tools API: „Ablauf protokollieren (Log)“ auf der Seite dpcc, derselbe
// Schalter wie der Registry-Wert Diagnose = 1 unter HKCU\Software\dpcc\IdePlugin. Für jede Aktion des Anwenders
// (Strg+Klick bzw. „Deklaration suchen“, Vervollständigung, Hover, Parameterhilfe) steht im Diagnoseprotokoll eine Kette
// kurzer Zeilen vom Aufruf der IDE bis zum Ergebnis, eine Zeile je Schritt, alle mit derselben Kennung („#12 Sprung:
// …“). Wo die Kette endet, sagt ihre letzte Zeile samt Grund.
// - Ein und aus zur Laufzeit (Enabled): Die IDE-Schicht setzt den Schalter beim Anmelden und nach OK auf der Seite
//   (dpcc.IDE.Completion.Register). Ausgeschaltet prüfen die Stellen nur diese Klassenvariable, bevor sie einen Text
//   bauen; Start liefert dann 0, Step tut nichts.
// - Ziel (Sink): eine Methode der IDE-Schicht, die die Zeile wie jede andere Diagnosezeile an den Schreib-Thread
//   übergibt (TDpccCodeInsightPaths.Append, perf1); der aufrufende Thread wartet nie auf die Datei. Ohne Ziel (Tests,
//   vor dem Anmelden) entfällt die Zeile. Fehler des Ziels fängt Step ab: Das Protokoll stört nie.
// - Kennung: laufende Nummer je Prozess (Start). Je Bereich merkt sich die Unit die zuletzt begonnene Aktion (Current);
//   Stellen ohne eigene Übergabe (Ergebnis der Vervollständigung, Zeigen des Tooltips) schreiben unter ihr.
// - Inhalt: Dateien nur mit Namen ohne Ordner (FileText), Stellen als Zeile:Spalte, feste Wörter und Codes; aus dem
//   Quelltext nur das eine Wort an der Stelle (WordText, gekürzt). Das Ziel entfernt zusätzlich Pfade und den
//   Benutzernamen (TDpccCodeInsightPaths.WithoutPaths). Die Zeilen werden nie übersetzt.
// - Threads: Start, Current und Step aus jedem Thread; Step liest das Ziel unter einer Sperre, die es nur bei
//   eingeschaltetem Schalter nimmt.

interface

uses
  System.SysUtils,
  System.SyncObjs;

type
{$SCOPEDENUMS ON}
  /// <summary>Bereich einer Aktion: Sprung (Strg+Klick, „Deklaration suchen“), Vervollständigung, Hover (Tooltip von
  /// dpcc und Symbolhinweis der IDE), Parameterhilfe.</summary>
  TDpccFlowArea = (Jump, Completion, Hover, Signature);
{$SCOPEDENUMS OFF}

  /// <summary>Ziel der Zeilen; aus jedem Thread, muss sofort zurückkehren.</summary>
  TDpccFlowSink = reference to procedure(const ALine: string);

  TDpccFlow = class
  public const
    /// <summary>Höchstens so viele Zeichen des Worts an der Stelle.</summary>
    cMaxWordLength = 64;
  private class var
    FEnabled: Boolean;
    FLock: TCriticalSection;
    FSink: TDpccFlowSink;
    FLastId: Integer;
    FCurrent: array[TDpccFlowArea] of Integer;
  public
    class constructor CreateFlow;
    class destructor DestroyFlow;
    /// <summary>Ablauf protokollieren? Vorgabe aus.</summary>
    class property Enabled: Boolean read FEnabled write FEnabled;
    /// <summary>Ziel der Zeilen setzen; nil = keins (beim Entladen).</summary>
    class procedure SetSink(const ASink: TDpccFlowSink); static;
    /// <summary>Neue Aktion im Bereich AArea: neue Kennung, ab jetzt auch Current(AArea); 0, wenn nicht
    /// protokolliert wird.</summary>
    class function Start(AArea: TDpccFlowArea): Integer; static;
    /// <summary>Zuletzt begonnene Aktion des Bereichs; 0 ohne.</summary>
    class function Current(AArea: TDpccFlowArea): Integer; static;
    /// <summary>Zeile zum Schritt AText der Aktion AId (Format wie Line) ans Ziel; nichts, wenn nicht protokolliert
    /// wird. Wirft nie.</summary>
    class procedure Step(AId: Integer; AArea: TDpccFlowArea; const AText: string); static;
    /// <summary>„#&lt;AId&gt; &lt;Bereich&gt;: AText“; ohne Kennung (AId ≤ 0) „#- &lt;Bereich&gt;: AText“.</summary>
    class function Line(AId: Integer; AArea: TDpccFlowArea; const AText: string): string; static;
    /// <summary>Name des Bereichs im Protokoll: Sprung, Vervollständigung, Hover, Parameterhilfe.</summary>
    class function AreaName(AArea: TDpccFlowArea): string; static;
    /// <summary>Dateiname ohne Ordner (Trenner \, / und :); „-“ ohne Datei.</summary>
    class function FileText(const AFileName: string): string; static;
    /// <summary>„Datei Zeile:Spalte“: ALine 1-basiert, ACharacter 0-basiert (Spalte = ACharacter + 1).</summary>
    class function PlaceText(const AFileName: string; ALine, ACharacter: Integer): string; static;
    /// <summary>Wort ALineText[AStart + 1 .. AEnd] (AStart 0-basiert, AEnd hinter dem letzten Zeichen) in „…“, gekürzt
    /// auf cMaxWordLength Zeichen; „(kein Wort)“, wenn nichts dazwischen liegt.</summary>
    class function WordText(const ALineText: string; AStart, AEnd: Integer): string; static;
    /// <summary>Vergleich zweier Dateien wie TDpccGotoDefinition.OnTarget (TTextUris.SamePath): „gleich“ bei
    /// gleichem Text ohne Groß-/Kleinschreibung in ASCII, „gleich nach Vereinheitlichung (…)“ mit der Art der
    /// Abweichung (Trennzeichen, Groß/Klein außerhalb von ASCII, „.“/„..“; ohne den Pfad), sonst „verschieden
    /// (A | B)“ mit den Namen ohne Ordner; bei gleichem Namen die Art des Unterschieds (Kurzname, URI-Kodierung,
    /// Laufwerk, sonst
    /// Ordner mit ihrer Tiefe), nie die Ordner selbst. Beginnt genau dann mit „gleich“, wenn SamePath gilt.
    /// </summary>
    class function FileComparison(const AFileName, AOtherName: string): string; static;
    /// <summary>„ja“ bzw. „nein“.</summary>
    class function YesNo(AValue: Boolean): string; static;
    /// <summary>AText ohne Kennzeichen (dpcc.Text.LogMarks, Zeilen fürs dpcc.log): Namen werden zu „&lt;name&gt;“
    /// (kein Quelltext außer dem Wort an der Stelle), Pfade zum Dateinamen ohne Ordner, fremder Text bleibt.</summary>
    class function Unmarked(const AText: string): string; static;
  end;

implementation

uses
  System.Math,
  dpcc.Text.LogMarks,
  dpcc.Text.Uris;

{ TDpccFlow }

class constructor TDpccFlow.CreateFlow;
begin
  FLock := TCriticalSection.Create;
end;

class destructor TDpccFlow.DestroyFlow;
begin
  FEnabled := False;
  FSink := nil;
  FreeAndNil(FLock);
end;

class procedure TDpccFlow.SetSink(const ASink: TDpccFlowSink);
begin
  if FLock = nil then
  begin
    Exit;
  end;
  FLock.Enter;
  try
    FSink := ASink;
  finally
    FLock.Leave;
  end;
end;

class function TDpccFlow.Start(AArea: TDpccFlowArea): Integer;
begin
  Result := 0;
  if not FEnabled then
  begin
    Exit;
  end;
  Result := AtomicIncrement(FLastId);
  FCurrent[AArea] := Result;
end;

class function TDpccFlow.Current(AArea: TDpccFlowArea): Integer;
begin
  Result := FCurrent[AArea];
end;

class procedure TDpccFlow.Step(AId: Integer; AArea: TDpccFlowArea; const AText: string);
var
  mSink: TDpccFlowSink;
begin
  if not FEnabled or (FLock = nil) then
  begin
    Exit;
  end;
  try
    FLock.Enter;
    try
      mSink := FSink;
    finally
      FLock.Leave;
    end;
    if Assigned(mSink) then
    begin
      mSink(Line(AId, AArea, Unmarked(AText)));
    end;
  except
    // Das Protokoll ist Beiwerk: Ein Fehler beim Schreiben erreicht weder die IDE noch den Aufrufer.
  end;
end;

class function TDpccFlow.AreaName(AArea: TDpccFlowArea): string;
const
  cNames: array[TDpccFlowArea] of string = ('Sprung', 'Vervollständigung', 'Hover', 'Parameterhilfe');
begin
  Result := cNames[AArea];
end;

class function TDpccFlow.Line(AId: Integer; AArea: TDpccFlowArea; const AText: string): string;
begin
  if AId > 0 then
  begin
    Result := Format('#%d %s: %s', [AId, AreaName(AArea), AText]);
  end
  else
  begin
    Result := Format('#- %s: %s', [AreaName(AArea), AText]);
  end;
end;

class function TDpccFlow.FileText(const AFileName: string): string;
begin
  if AFileName = '' then
  begin
    Exit('-');
  end;
  // Auch mit / als Trenner (URI-artige Pfade): ExtractFileName kennt unter Windows nur \ und :.
  Result := Copy(AFileName, LastDelimiter('\/:', AFileName) + 1, MaxInt);
  if Result = '' then
  begin
    Result := '-';
  end;
end;

class function TDpccFlow.PlaceText(const AFileName: string; ALine, ACharacter: Integer): string;
begin
  Result := Format('%s %d:%d', [FileText(AFileName), ALine, ACharacter + 1]);
end;

class function TDpccFlow.WordText(const ALineText: string; AStart, AEnd: Integer): string;
var
  mFirst, mLast: Integer;
begin
  mFirst := Max(AStart, 0);
  mLast := Min(AEnd, Length(ALineText));
  if mLast <= mFirst then
  begin
    Exit('(kein Wort)');
  end;
  Result := Copy(ALineText, mFirst + 1, Min(mLast - mFirst, cMaxWordLength));
  if mLast - mFirst > cMaxWordLength then
  begin
    Result := Result + '…';
  end;
  Result := '„' + Result + '“';
end;

/// <summary>Zahl der Trennzeichen \ und / in APath (Tiefe des Ordners).</summary>
function Depth(const APath: string): Integer;
var
  mChar: Char;
begin
  Result := 0;
  for mChar in APath do
  begin
    if (mChar = '\') or (mChar = '/') then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>APath mit / statt \.</summary>
function Slashed(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

class function TDpccFlow.FileComparison(const AFileName, AOtherName: string): string;
var
  mName, mOther, mKind: string;
begin
  if SameText(AFileName, AOtherName) then
  begin
    Exit('gleich');
  end;
  // Dasselbe Urteil wie OnTarget (TTextUris.SamePath): gleich nach dem Vereinheitlichen, dazu was abwich.
  if TTextUris.SamePath(AFileName, AOtherName) then
  begin
    if SameText(Slashed(AFileName), Slashed(AOtherName)) then
    begin
      mKind := 'nur die Trennzeichen (Schrägstrich statt Backslash)';
    end
    else if AnsiSameText(Slashed(AFileName), Slashed(AOtherName)) then
    begin
      mKind := 'nur Groß-/Kleinschreibung außerhalb von ASCII';
    end
    else
    begin
      mKind := 'Schreibweise des Pfads („.“, „..“, doppelte Trenner oder Präfix für lange Pfade)';
    end;
    Exit(Format('gleich nach Vereinheitlichung (%s)', [mKind]));
  end;
  mName := FileText(AFileName);
  mOther := FileText(AOtherName);
  if not SameText(mName, mOther) then
  begin
    if AnsiSameText(mName, mOther) then
    begin
      // SameText vergleicht nur A bis Z ohne Groß-/Kleinschreibung.
      Exit(Format('verschieden (%s | %s; nur Groß-/Kleinschreibung außerhalb von ASCII)', [mName, mOther]));
    end;
    Exit(Format('verschieden (%s | %s)', [mName, mOther]));
  end;
  // Gleicher Name: nur die Art des Unterschieds im Ordner, nie der Ordner selbst. Trennzeichen, Groß/Klein und "."
  // bzw. ".." gleicht SamePath schon aus; es bleibt, was ein reiner Textvergleich nicht klären kann.
  if (Pos('~', AFileName) > 0) <> (Pos('~', AOtherName) > 0) then
  begin
    mKind := 'Kurzname (8.3) in einer der beiden';
  end
  else if (Pos('%', AFileName) > 0) <> (Pos('%', AOtherName) > 0) then
  begin
    mKind := 'URI-Kodierung (%) in einer der beiden';
  end
  else if not SameText(ExtractFileDrive(AFileName), ExtractFileDrive(AOtherName)) then
  begin
    mKind := 'anderes Laufwerk';
  end
  else
  begin
    mKind := Format('anderer Ordner, Tiefe %d | %d', [Depth(AFileName), Depth(AOtherName)]);
  end;
  Result := Format('verschieden (gleicher Name %s; %s)', [mName, mKind]);
end;

class function TDpccFlow.YesNo(AValue: Boolean): string;
begin
  if AValue then
  begin
    Result := 'ja';
  end
  else
  begin
    Result := 'nein';
  end;
end;

class function TDpccFlow.Unmarked(const AText: string): string;
begin
  if not TLogMarks.HasMarks(AText) then
  begin
    Exit(AText);
  end;
  Result := TLogMarks.Resolve(AText,
    function(AKind: TLogMarkKind; const AValue: string): string
    begin
      case AKind of
        TLogMarkKind.Name:
          Result := '<name>';
        TLogMarkKind.Path:
          Result := TDpccFlow.FileText(AValue);
      else
        Result := AValue;
      end;
    end);
end;

end.
