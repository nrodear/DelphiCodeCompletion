unit dpcc.Core.Editor.Navigation;

// Regeln für Strg+Klick und „Deklaration suchen“ (Auftrag NAV) ohne IDE und ohne VCL. Die Editor-Units lesen den
// Zustand (Tasten, Maus, Antwort des Servers) und fragen hier, was gilt.
//   - Sprung (TDpccGotoDefinition): Delphi 13 fragt für Strg+Klick, „Deklaration suchen“ und Alt+↑ nur den in den
//     Optionen gewählten Code-Insight-Anbieter (GotoDefinition, ToolsAPI). Ist das dpcc, meldet es ein gefundenes
//     Ziel mit Datei und Zeile. In jedem anderen Fall (nichts gefunden, Ersatz-Unit ohne Quelltext, Zeitlimit,
//     Sicherung, kein Server) bricht es still ab: True mit leerem Dateinamen. False hieße für die IDE „Fehlschlag
//     melden“; sie zeigte dann „Datei "" nicht gefunden“. An einen anderen Anbieter reicht die IDE nicht weiter.
//     Kommt die Antwort nicht innerhalb der Wartezeit (Deferred), ebenso still; dpcc springt dann selbst nach.
//     Startet der Server noch (Starting), merkt sich dpcc den Wunsch und springt nach, sobald er bereit ist.
//   - Rückmeldung (TDpccGotoNotice, TDpccNoticeRepeat, TDpccGotoLog): Für die IDE bleibt es still, dpcc selbst nennt
//     den Grund im Meldungsfenster (Unit nur als Package, Unit nicht gefunden, Name nicht aufgelöst, dpcc startet
//     noch, keine Antwort …; dieselbe Meldung nicht mehrfach hintereinander) und schreibt jeden Sprung ohne Ziel als
//     eine Zeile ins dpcc.log (Ausgang, Dauer, Datei ohne Pfad, Zeile:Spalte; Datei und Namen gekennzeichnet für die
//     Anonymisierung, dpcc.Text.LogMarks).
//   - Ziel wie „Deklaration suchen“ der IDE: Von einer Verwendung zur Deklaration; steht die Stelle schon auf
//     der Deklaration selbst (OnTarget), zur Implementierung (textDocument/definition), von dort wieder zurück.
//   - Stelle (ChoosePosition): Bei Strg+Klick die Stelle unter der Maus, sonst der Caret. Ob die IDE den Caret vor
//     GotoDefinition auf die Klickstelle setzt, ist in der IDE nicht geprüft; stimmen beide überein, ändert die
//     Wahl nichts.
//   - Hinweis (TDpccProviderNotice): einmal je Sitzung eine Zeile im Meldungsfenster, wenn dpcc der gewählte
//     Anbieter ist: was dann fehlt (Error Insight) und dass Strg+Klick über dpcc läuft.
//   - Parameter-Hint (TDpccOverloadKeys): Die Überladung wechselt mit Strg+Alt+↑/↓. Alt+↑ ist in der
//     Standardbelegung „Deklaration suchen“ und gehört der IDE; einfache Pfeile bewegen den Caret.
//   - Tooltip (TDpccTooltipMouse): Mit gedrückter Strg-Taste lässt der dpcc-Tooltip die Maus durch (Strg+Klick auf
//     ein Wort, das er verdeckt); Strg mit der Maus über dem Tooltip schließt ihn.

interface

uses
  System.Classes,
  System.Types,
  dpcc.Core.Lsp.LateAnswers,
  dpcc.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Ausgang einer Sprunganfrage der IDE (GotoDefinition).</summary>
  TDpccGotoOutcome = (
    /// <summary>Ziel gefunden.</summary>
    Found,
    /// <summary>Der Server kennt kein Ziel (auch Ersatz-Unit ohne Quelltext, nicht gefundene Unit).</summary>
    NotFound,
    /// <summary>Von der Sicherung abgeschaltet.</summary>
    Disabled,
    /// <summary>Keine Editoransicht oder Stelle außerhalb des Puffers.</summary>
    NoView,
    /// <summary>Kein Server (Hauptschalter aus, Start fehlgeschlagen).</summary>
    NoSession,
    /// <summary>Der Server meldet keine Sprungziele (definitionProvider fehlt, -32601).</summary>
    NotOffered,
    /// <summary>Zeitlimit oder beendeter Server (ELspClientError): erwartbar, keine Meldung.</summary>
    TimedOut,
    /// <summary>Unerwarteter Fehler: Meldung und Sicherung.</summary>
    Failed,
    /// <summary>Antwort nicht innerhalb der Wartezeit des Hauptthreads: still abbrechen, dpcc springt selbst, sobald
    /// sie kommt und noch passt (dpcc.Core.Lsp.LateAnswers).</summary>
    Deferred,
    /// <summary>Der Server startet noch: still abbrechen, der Wunsch ist gemerkt; dpcc fragt und springt selbst,
    /// sobald die Sitzung bereit ist und er noch passt.</summary>
    Starting);

  /// <summary>Art der Rückmeldung im Meldungsfenster zu einem Sprung ohne Ziel.</summary>
  TDpccGotoNoticeKind = (
    /// <summary>Der Server kennt kein Ziel (Grund aus dpcc/noTarget, TDpccGotoNotice.ForNoTarget).</summary>
    NoTarget,
    /// <summary>Der Server startet noch; der Sprung folgt (Argument: Sekunden).</summary>
    Starting,
    /// <summary>Kein Server (Start gesperrt oder fehlgeschlagen).</summary>
    NotRunning,
    /// <summary>Der Server bietet keine Sprungziele.</summary>
    NotOffered,
    /// <summary>Keine Antwort binnen der Frist (Argument: Sekunden).</summary>
    TimedOut,
    /// <summary>Verbindung zum Server unterbrochen.</summary>
    ServerLost,
    /// <summary>Das Ziel ließ sich nicht öffnen (Argument: Dateiname).</summary>
    OpenFailed);

  /// <summary>Antwort an die IDE: Ergebnis von GotoDefinition, Datei und Zeile (1-basiert); Report = Fehler melden.
  /// </summary>
  TDpccGotoAnswer = record
    Result: Boolean;
    FileName: string;
    Line: Integer;
    Report: Boolean;
  end;

  TDpccGotoDefinition = record
  public
    /// <summary>Antwort für AOutcome; AFileName und ALine (0-basiert wie im LSP) zählen nur bei Found.</summary>
    class function Answer(AOutcome: TDpccGotoOutcome; const AFileName: string; ALine: Integer): TDpccGotoAnswer;
      static;
    /// <summary>Steht die Stelle ALine/ACharacter (0-basiert) in ALineText im Namen, der in derselben Datei bei
    /// ATargetLine/ATargetCharacter beginnt? Dann liegt sie auf der Deklaration selbst (Strg+Klick auf den Namen
    /// in der Klasse), und der Sprung geht zur Implementierung. „Dieselbe Datei“ nach TTextUris.SamePath (Trenner,
    /// "." und "..", Groß/Klein auch außerhalb von ASCII), ohne Zugriff aufs Dateisystem.</summary>
    class function OnTarget(const AFileName: string; ALine, ACharacter: Integer; const ALineText,
      ATargetFile: string; ATargetLine, ATargetCharacter: Integer): Boolean; static;
    /// <summary>Begründung von OnTarget fürs Ablaufprotokoll (LOG1, nie übersetzt), mit denselben Bedingungen: „ja“
    /// bzw. „nein“, dann Datei (TDpccFlow.FileComparison: gleich oder beide Namen), Zeile (beide, 1-basiert) und
    /// Stelle im Wort (vom Beginn des Ziels bis zur Stelle nur Bezeichnerzeichen; „-“, wenn Datei oder Zeile schon
    /// abweichen), dazu Spalte der Stelle und des Ziels. Ändert nichts am Urteil von OnTarget.</summary>
    class function OnTargetWhy(const AFileName: string; ALine, ACharacter: Integer; const ALineText,
      ATargetFile: string; ATargetLine, ATargetCharacter: Integer): string; static;
    /// <summary>Stelle der Anfrage (X = Zeichen, Y = Zeile): bei gedrückter Strg-Taste (Strg+Klick) und gültiger
    /// Mausstelle über einem Bezeichner AMouse, sonst ACaret.</summary>
    class function ChoosePosition(ACtrlDown, AMouseValid: Boolean; const AMouse, ACaret: TPoint): TPoint; static;
  end;

  /// <summary>Texte der Rückmeldung im Meldungsfenster zu einem Sprung ohne Ziel.</summary>
  TDpccGotoNotice = record
  public
    /// <summary>Meldung zum Grund des Servers in der Sprache ALanguage, mit Name (Unit, Bezeichner) wo vorhanden und
    /// dem Zusatz „Der Index wird noch aufgebaut.“ bei Indexing. Ist der Name nicht aufgelöst bzw. die Unit nicht
    /// gefunden, solange der Index aufgebaut wird, statt „Kein Sprungziel“ die Bitte, gleich erneut zu klicken
    /// (Entscheidung des Nutzers, 26.11.2026: kein Warten, kein Nachreichen).</summary>
    class function ForNoTarget(ALanguage: TDpccLanguage; const ANoTarget: TDpccNoTarget): string; static;
    /// <summary>Meldung der Art AKind (außer NoTarget): AArgument ist der Dateiname (OpenFailed), ASeconds die
    /// Frist (Starting, TimedOut); AIndexing hängt den Zusatz zum Index an.</summary>
    class function ForKind(ALanguage: TDpccLanguage; AKind: TDpccGotoNoticeKind; const AArgument: string;
      ASeconds: Integer; AIndexing: Boolean): string; static;
  end;

  /// <summary>Gegen Fluten: dieselbe Meldung nicht mehrfach hintereinander (innerhalb von cRepeatMs). Ein
  /// gelungener Sprung (Reset) gibt sie wieder frei.</summary>
  TDpccNoticeRepeat = record
  public const
    cRepeatMs = 30000;
  private
    FLastText: string;
    FLastMs: UInt64;
  public
    /// <summary>Soll AText jetzt erscheinen? False, wenn derselbe Text zuletzt vor höchstens cRepeatMs erschien.
    /// Merkt sich AText, wenn True.</summary>
    function Take(const AText: string; ANowMs: UInt64): Boolean;
    procedure Reset;
  end;

  /// <summary>Zeilen fürs dpcc.log zu einem Sprung (nie übersetzt). Datei ohne Pfad und Namen sind gekennzeichnet
  /// (TLogMarks): Das Protokoll anonymisiert sie, außer mit diagnostics.log.names.</summary>
  TDpccGotoLog = record
  public
    /// <summary>„Gehe zu Definition: &lt;AOutcome&gt; nach &lt;n&gt; ms, &lt;Datei&gt; &lt;Zeile&gt;:&lt;Spalte&gt;
    /// (Maus|Cursor)“; ALine 1-basiert, ACharacter 0-basiert (Spalte = ACharacter + 1, Tabs als ein Zeichen).
    /// </summary>
    class function Line(const AOutcome: string; AElapsedMs: Int64; const AFileName: string; ALine,
      ACharacter: Integer; AMouse: Boolean): string; static;
    /// <summary>Ausgang „kein Ziel (Grund[: Name][, Index im Aufbau])“ mit dem Wert von reason; ohne Benachrichtigung
    /// „kein Ziel (Grund unbekannt)“.</summary>
    class function NoTargetOutcome(const ANoTarget: TDpccNoTarget): string; static;
    /// <summary>Name des Ausgangs im Ablaufprotokoll (LOG1): Found, NotFound … wie in TDpccGotoOutcome.</summary>
    class function OutcomeName(AOutcome: TDpccGotoOutcome): string; static;
    /// <summary>Letzte Zeile eines Sprungs im Ablaufprotokoll (LOG1): was GotoDefinition der IDE zurückgibt. Mit Datei
    /// „Ergebnis an die IDE: True, Datei Zeile n; gleich der Ausgangsstelle: ja|nein“ (gleich = dieselbe Datei und
    /// Zeile wie AOriginFile/AOriginLine, die IDE bleibt dann stehen); ohne Datei „Ergebnis an die IDE: True ohne
    /// Datei (kein Sprung der IDE), Ausgang …“ samt Hinweis bei Deferred bzw. Starting. AOriginLine 1-basiert;
    /// AHasOrigin False: Stelle unbekannt.</summary>
    class function FlowResult(AOutcome: TDpccGotoOutcome; const AAnswer: TDpccGotoAnswer; AHasOrigin: Boolean;
      const AOriginFile: string; AOriginLine: Integer): string; static;
  end;

  /// <summary>Hinweis im Meldungsfenster, wenn dpcc der gewählte Code-Insight-Anbieter ist (einmal je Sitzung).
  /// </summary>
  TDpccProviderNotice = record
  private class var
    FShown: Boolean;
  public
    /// <summary>Text in der Sprache ALanguage.</summary>
    class function Text(ALanguage: TDpccLanguage): string; static;
    /// <summary>True nur beim ersten Aufruf seit dem Laden (bzw. seit Reset); danach False.</summary>
    class function TakeFirst: Boolean; static;
    /// <summary>Noch nicht gezeigt? Ändert nichts.</summary>
    class function Pending: Boolean; static;
    /// <summary>Für Tests: wieder wie nach dem Laden.</summary>
    class procedure Reset; static;
  end;

  /// <summary>Tasten des Parameter-Hints für den Wechsel der Überladung.</summary>
  TDpccOverloadKeys = record
  public const
    cKeyUp = $26;
    cKeyDown = $28;
  public
    /// <summary>+1 (nächste), -1 (vorige) oder 0 (Taste gehört nicht dem Hint): nur Strg+Alt+↑/↓ und nur bei
    /// mindestens zwei Überladungen.</summary>
    class function Step(AKey: Word; AShift: TShiftState; ASignatures: Integer): Integer; static;
    /// <summary>Kürzel für Doku und Protokoll in der Sprache ALanguage.</summary>
    class function Caption(ALanguage: TDpccLanguage): string; static;
  end;

  /// <summary>Maus und Strg-Taste am dpcc-Tooltip (Strg+Klick auf ein verdecktes Wort).</summary>
  TDpccTooltipMouse = record
  public const
    cKeyShift = $10;
    cKeyControl = $11;
    cKeyMenu = $12;
  public
    /// <summary>Lässt der Tooltip die Maus an den Editor darunter durch (WM_NCHITTEST → HTTRANSPARENT)? Ja, solange
    /// Strg gedrückt ist.</summary>
    class function PassThrough(ACtrlDown: Boolean): Boolean; static;
    /// <summary>Schließt die Taste AKey den offenen Tooltip? Jede Taste außer Umschalt, Strg und Alt allein; Strg
    /// aber, wenn die Maus über dem Tooltip steht (er verdeckt dann das Wort für Strg+Klick).</summary>
    class function KeyCloses(AKey: Word; AMouseOverTip: Boolean): Boolean; static;
  end;

{$SCOPEDENUMS OFF}

implementation

uses
  System.SysUtils,
  System.Math,
  dpcc.Text.LogMarks,
  dpcc.Text.Uris,
  dpcc.Core.Diagnostics.Flow;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TNavigationText = (ProviderNotice, OverloadKeys, NoSource, NoSourceUnnamed, UnitNotFound, UnitNotFoundUnnamed,
    Unresolved, UnresolvedUnnamed, NoIdentifier, NoDocument, InactiveBranch, OtherReason, UnknownReason, Starting,
    NotRunning, NotOffered, TimedOut, ServerLost, OpenFailed, IndexingSuffix, IndexingRetry);

{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TNavigationText] of string = (
    ('dpcc ist in den Optionen der IDE als Code-Insight-Anbieter für Delphi gewählt. Strg+Klick und „Deklaration ' +
     'suchen“ laufen über dpcc; ohne Ziel (etwa in Units ohne Quelltext) springt die IDE nicht. Error Insight ' +
     '(Fehlermarkierungen im Editor) und die übrigen Dienste von DelphiLSP fehlen dann. Wer sie braucht, schaltet ' +
     'den Hauptschalter der Seite dpcc aus oder wählt in den Optionen der IDE wieder DelphiLSP; dpcc ist dann ab ' +
     'dem nächsten Start aus.',
     'Strg+Alt+↑/↓',
     'Kein Sprungziel: Unit %s liegt nur als Package vor (kein Quelltext). Quellordner unter Tools › Optionen › ' +
     'Drittanbieter › dpcc › Zusätzliche Quellordner eintragen.',
     'Kein Sprungziel: Die Unit liegt nur als Package vor (kein Quelltext). Quellordner unter Tools › Optionen › ' +
     'Drittanbieter › dpcc › Zusätzliche Quellordner eintragen.',
     'Kein Sprungziel: Unit %s nicht gefunden.',
     'Kein Sprungziel: Unit nicht gefunden.',
     'Kein Sprungziel: „%s“ nicht aufgelöst.',
     'Kein Sprungziel: Name nicht aufgelöst.',
     'Kein Sprungziel: An dieser Stelle steht kein Bezeichner.',
     'Kein Sprungziel: dpcc kennt die Datei noch nicht.',
     'Kein Sprungziel: Die Stelle liegt in einem nicht aktiven Zweig ({$IFDEF …}).',
     'Kein Sprungziel gefunden.',
     'Kein Sprungziel gefunden (Grund unbekannt).',
     'dpcc startet noch; der Sprung folgt, sobald dpcc bereit ist (höchstens %d s nach dem Klick).',
     'Kein Sprung: dpcc läuft nicht (Server nicht gestartet).',
     'Kein Sprung: Der dpcc-Server bietet keine Sprungziele an.',
     'Kein Sprung: keine Antwort von dpcc binnen %d s.',
     'Kein Sprung: Die Verbindung zum dpcc-Server ist unterbrochen.',
     'Kein Sprung: %s ließ sich nicht öffnen.',
     'Der Index wird noch aufgebaut.',
     'Kein Sprung: Der Index wird noch aufgebaut. Bitte gleich erneut klicken.'),
    ('dpcc is selected as the Code Insight provider for Delphi in the IDE options. Ctrl+click and “Find ' +
     'Declaration” go through dpcc; without a target (for example in units without source) the IDE does not ' +
     'jump. Error Insight (error marks in the editor) and the other DelphiLSP services are missing then. If you ' +
     'need them, turn off the master switch on the dpcc page or select DelphiLSP in the IDE options again; dpcc ' +
     'is then off from the next start.',
     'Ctrl+Alt+↑/↓',
     'No jump target: unit %s is only available as a package (no source). Add its source folder under Tools › ' +
     'Options › Third Party › dpcc › Additional source folders.',
     'No jump target: the unit is only available as a package (no source). Add its source folder under Tools › ' +
     'Options › Third Party › dpcc › Additional source folders.',
     'No jump target: unit %s not found.',
     'No jump target: unit not found.',
     'No jump target: “%s” could not be resolved.',
     'No jump target: name could not be resolved.',
     'No jump target: there is no identifier at this position.',
     'No jump target: dpcc does not know this file yet.',
     'No jump target: the position is in an inactive branch ({$IFDEF …}).',
     'No jump target found.',
     'No jump target found (reason unknown).',
     'dpcc is still starting; the jump follows as soon as dpcc is ready (at most %d s after the click).',
     'No jump: dpcc is not running (server not started).',
     'No jump: the dpcc server does not offer jump targets.',
     'No jump: no answer from dpcc within %d s.',
     'No jump: the connection to the dpcc server is lost.',
     'No jump: %s could not be opened.',
     'The index is still being built.',
     'No jump: the index is still being built. Please click again in a moment.'));

function IsNameChar(AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AChar) > 127);
end;

{ TDpccGotoDefinition }

class function TDpccGotoDefinition.Answer(AOutcome: TDpccGotoOutcome; const AFileName: string;
  ALine: Integer): TDpccGotoAnswer;
begin
  Result := Default(TDpccGotoAnswer);
  // Immer True: False ließe die IDE „Datei "" nicht gefunden“ melden (ToolsAPI, GotoDefinition).
  Result.Result := True;
  if (AOutcome = TDpccGotoOutcome.Found) and (AFileName <> '') then
  begin
    Result.FileName := AFileName;
    Result.Line := ALine + 1;
  end;
  Result.Report := AOutcome = TDpccGotoOutcome.Failed;
end;

class function TDpccGotoDefinition.OnTarget(const AFileName: string; ALine, ACharacter: Integer; const ALineText,
  ATargetFile: string; ATargetLine, ATargetCharacter: Integer): Boolean;
var
  mIndex: Integer;
begin
  // Datei über TTextUris.SamePath: Der Server liefert den Pfad vereinheitlicht (Backslashes, "." und ".." aufgelöst,
  // Laufwerk klein), die IDE übergibt ihn, wie er im Editor steht (C:/…, …\Unter\..\…, Umlaute in anderer
  // Schreibung). Mit SameText galt die Deklaration dann nicht als Klickstelle.
  Result := TTextUris.SamePath(AFileName, ATargetFile) and (ALine = ATargetLine) and
    (ACharacter >= ATargetCharacter) and (ATargetCharacter < Length(ALineText));
  if not Result then
  begin
    Exit;
  end;
  // Von Beginn des Ziels bis vor die Stelle nur Bezeichnerzeichen: dasselbe Wort (auch mit dem Cursor direkt
  // hinter dem Namen).
  for mIndex := ATargetCharacter + 1 to Min(ACharacter, Length(ALineText)) do
  begin
    if not IsNameChar(ALineText[mIndex]) then
    begin
      Exit(False);
    end;
  end;
end;

class function TDpccGotoDefinition.OnTargetWhy(const AFileName: string; ALine, ACharacter: Integer; const ALineText,
  ATargetFile: string; ATargetLine, ATargetCharacter: Integer): string;
var
  mSameFile, mSameLine, mInWord: Boolean;
  mIndex: Integer;
  mWord: string;
begin
  // Dieselben Bedingungen wie OnTarget, nur einzeln festgehalten.
  mSameFile := TTextUris.SamePath(AFileName, ATargetFile);
  mSameLine := ALine = ATargetLine;
  mInWord := (ACharacter >= ATargetCharacter) and (ATargetCharacter < Length(ALineText));
  if mInWord then
  begin
    for mIndex := ATargetCharacter + 1 to Min(ACharacter, Length(ALineText)) do
    begin
      if not IsNameChar(ALineText[mIndex]) then
      begin
        mInWord := False;
        Break;
      end;
    end;
  end;
  if mSameFile and mSameLine then
  begin
    mWord := TDpccFlow.YesNo(mInWord);
  end
  else
  begin
    // Andere Datei oder Zeile: Die Spalte des Ziels bezieht sich nicht auf diese Zeile.
    mWord := '-';
  end;
  Result := Format('%s (Datei %s; Zeile %s, %d | %d; Stelle im Wort %s, Spalte %d, Ziel ab %d)',
    [TDpccFlow.YesNo(mSameFile and mSameLine and mInWord), TDpccFlow.FileComparison(AFileName, ATargetFile),
    TDpccFlow.YesNo(mSameLine), ALine + 1, ATargetLine + 1, mWord, ACharacter + 1, ATargetCharacter + 1]);
end;

class function TDpccGotoDefinition.ChoosePosition(ACtrlDown, AMouseValid: Boolean; const AMouse,
  ACaret: TPoint): TPoint;
begin
  if ACtrlDown and AMouseValid then
  begin
    Result := AMouse;
  end
  else
  begin
    Result := ACaret;
  end;
end;

{ TDpccGotoNotice }

/// <summary>Text AId in der Sprache ALanguage.</summary>
function NavText(ALanguage: TDpccLanguage; AId: TNavigationText): string;
begin
  Result := cTexts[ALanguage, AId];
end;

/// <summary>ANamed mit AName, ohne Namen AUnnamed.</summary>
function NamedText(ALanguage: TDpccLanguage; ANamed, AUnnamed: TNavigationText; const AName: string): string;
begin
  if Trim(AName) = '' then
  begin
    Result := NavText(ALanguage, AUnnamed);
  end
  else
  begin
    Result := Format(NavText(ALanguage, ANamed), [Trim(AName)]);
  end;
end;

/// <summary>AText mit dem Zusatz „Der Index wird noch aufgebaut.“, wenn AIndexing.</summary>
function WithIndexing(ALanguage: TDpccLanguage; const AText: string; AIndexing: Boolean): string;
begin
  Result := AText;
  if AIndexing then
  begin
    Result := Result + ' ' + NavText(ALanguage, TNavigationText.IndexingSuffix);
  end;
end;

class function TDpccGotoNotice.ForNoTarget(ALanguage: TDpccLanguage; const ANoTarget: TDpccNoTarget): string;
begin
  // Während des Indexaufbaus fehlen Namen und Units oft nur vorläufig: zum erneuten Klick auffordern.
  if ANoTarget.Indexing and (ANoTarget.Reason in [TDpccNoTargetReason.Unresolved,
    TDpccNoTargetReason.UnitNotFound]) then
  begin
    Exit(NavText(ALanguage, TNavigationText.IndexingRetry));
  end;
  case ANoTarget.Reason of
    TDpccNoTargetReason.NoSource:
      Result := NamedText(ALanguage, TNavigationText.NoSource, TNavigationText.NoSourceUnnamed, ANoTarget.Name);
    TDpccNoTargetReason.UnitNotFound:
      Result := NamedText(ALanguage, TNavigationText.UnitNotFound, TNavigationText.UnitNotFoundUnnamed,
        ANoTarget.Name);
    TDpccNoTargetReason.Unresolved:
      Result := NamedText(ALanguage, TNavigationText.Unresolved, TNavigationText.UnresolvedUnnamed, ANoTarget.Name);
    TDpccNoTargetReason.NoIdentifier:
      Result := NavText(ALanguage, TNavigationText.NoIdentifier);
    TDpccNoTargetReason.NoDocument:
      Result := NavText(ALanguage, TNavigationText.NoDocument);
    TDpccNoTargetReason.InactiveBranch:
      Result := NavText(ALanguage, TNavigationText.InactiveBranch);
    TDpccNoTargetReason.Other:
      Result := NavText(ALanguage, TNavigationText.OtherReason);
  else
    // Ohne Benachrichtigung (älterer Server).
    Result := NavText(ALanguage, TNavigationText.UnknownReason);
  end;
  Result := WithIndexing(ALanguage, Result, ANoTarget.Indexing);
end;

class function TDpccGotoNotice.ForKind(ALanguage: TDpccLanguage; AKind: TDpccGotoNoticeKind;
  const AArgument: string; ASeconds: Integer; AIndexing: Boolean): string;
begin
  case AKind of
    TDpccGotoNoticeKind.Starting:
      Result := Format(NavText(ALanguage, TNavigationText.Starting), [ASeconds]);
    TDpccGotoNoticeKind.NotRunning:
      Result := NavText(ALanguage, TNavigationText.NotRunning);
    TDpccGotoNoticeKind.NotOffered:
      Result := NavText(ALanguage, TNavigationText.NotOffered);
    TDpccGotoNoticeKind.TimedOut:
      Result := Format(NavText(ALanguage, TNavigationText.TimedOut), [ASeconds]);
    TDpccGotoNoticeKind.ServerLost:
      Result := NavText(ALanguage, TNavigationText.ServerLost);
    TDpccGotoNoticeKind.OpenFailed:
      Result := Format(NavText(ALanguage, TNavigationText.OpenFailed), [AArgument]);
  else
    // NoTarget gehört zu ForNoTarget.
    Result := NavText(ALanguage, TNavigationText.UnknownReason);
  end;
  Result := WithIndexing(ALanguage, Result, AIndexing);
end;

{ TDpccNoticeRepeat }

function TDpccNoticeRepeat.Take(const AText: string; ANowMs: UInt64): Boolean;
begin
  Result := (AText <> '') and not ((AText = FLastText) and (ANowMs >= FLastMs) and
    (ANowMs - FLastMs <= cRepeatMs));
  if Result then
  begin
    FLastText := AText;
    FLastMs := ANowMs;
  end;
end;

procedure TDpccNoticeRepeat.Reset;
begin
  FLastText := '';
  FLastMs := 0;
end;

{ TDpccGotoLog }

class function TDpccGotoLog.Line(const AOutcome: string; AElapsedMs: Int64; const AFileName: string; ALine,
  ACharacter: Integer; AMouse: Boolean): string;
const
  cPlaces: array[Boolean] of string = ('Cursor', 'Maus');
var
  mFile: string;
begin
  mFile := '-';
  if AFileName <> '' then
  begin
    mFile := TLogMarks.Path(ExtractFileName(AFileName));
  end;
  Result := Format('Gehe zu Definition: %s nach %d ms, %s %d:%d (%s)', [AOutcome, AElapsedMs, mFile, ALine,
    ACharacter + 1, cPlaces[AMouse]]);
end;

class function TDpccGotoLog.NoTargetOutcome(const ANoTarget: TDpccNoTarget): string;
begin
  if ANoTarget.Reason = TDpccNoTargetReason.Unknown then
  begin
    Result := 'kein Ziel (Grund unbekannt';
  end
  else
  begin
    Result := 'kein Ziel (' + TDpccNoTarget.CodeOf(ANoTarget.Reason);
  end;
  if ANoTarget.Name <> '' then
  begin
    Result := Result + ': ' + TLogMarks.Name(ANoTarget.Name);
  end;
  if ANoTarget.Indexing then
  begin
    Result := Result + ', Index im Aufbau';
  end;
  Result := Result + ')';
end;

class function TDpccGotoLog.OutcomeName(AOutcome: TDpccGotoOutcome): string;
const
  cNames: array[TDpccGotoOutcome] of string = ('Found', 'NotFound', 'Disabled', 'NoView', 'NoSession', 'NotOffered',
    'TimedOut', 'Failed', 'Deferred', 'Starting');
begin
  Result := cNames[AOutcome];
end;

class function TDpccGotoLog.FlowResult(AOutcome: TDpccGotoOutcome; const AAnswer: TDpccGotoAnswer;
  AHasOrigin: Boolean; const AOriginFile: string; AOriginLine: Integer): string;
var
  mSame: string;
begin
  if AAnswer.FileName <> '' then
  begin
    if not AHasOrigin then
    begin
      mSame := 'unbekannt';
    end
    else if TTextUris.SamePath(AAnswer.FileName, AOriginFile) and (AAnswer.Line = AOriginLine) then
    begin
      // Die IDE springt nur an eine Zeile: dieselbe Datei und Zeile heißt, der Cursor bleibt, wo er ist. Die Datei
      // des Ziels kommt vom Server, die Ausgangsstelle von der IDE: Vergleich wie OnTarget.
      mSame := 'ja (die IDE bleibt in derselben Zeile)';
    end
    else
    begin
      mSame := 'nein';
    end;
    Result := Format('Ergebnis an die IDE: %s, %s Zeile %d; gleich der Ausgangsstelle: %s',
      [BoolToStr(AAnswer.Result, True), TDpccFlow.FileText(AAnswer.FileName), AAnswer.Line, mSame]);
    Exit;
  end;
  Result := Format('Ergebnis an die IDE: %s ohne Datei (kein Sprung der IDE), Ausgang %s',
    [BoolToStr(AAnswer.Result, True), OutcomeName(AOutcome)]);
  case AOutcome of
    TDpccGotoOutcome.Deferred:
      Result := Result + '; die Antwort kommt später (LateGoto)';
    TDpccGotoOutcome.Starting:
      Result := Result + '; der Wunsch wartet auf den Start';
  end;
end;

{ TDpccProviderNotice }

class function TDpccProviderNotice.Text(ALanguage: TDpccLanguage): string;
begin
  Result := cTexts[ALanguage, TNavigationText.ProviderNotice];
end;

class function TDpccProviderNotice.TakeFirst: Boolean;
begin
  Result := not FShown;
  FShown := True;
end;

class function TDpccProviderNotice.Pending: Boolean;
begin
  Result := not FShown;
end;

class procedure TDpccProviderNotice.Reset;
begin
  FShown := False;
end;

{ TDpccOverloadKeys }

class function TDpccOverloadKeys.Step(AKey: Word; AShift: TShiftState; ASignatures: Integer): Integer;
begin
  Result := 0;
  if (ASignatures < 2) or (AShift <> [ssCtrl, ssAlt]) then
  begin
    Exit;
  end;
  case AKey of
    cKeyUp:
      Result := -1;
    cKeyDown:
      Result := 1;
  end;
end;

class function TDpccOverloadKeys.Caption(ALanguage: TDpccLanguage): string;
begin
  Result := cTexts[ALanguage, TNavigationText.OverloadKeys];
end;

{ TDpccTooltipMouse }

class function TDpccTooltipMouse.PassThrough(ACtrlDown: Boolean): Boolean;
begin
  Result := ACtrlDown;
end;

class function TDpccTooltipMouse.KeyCloses(AKey: Word; AMouseOverTip: Boolean): Boolean;
begin
  case AKey of
    cKeyShift, cKeyMenu:
      Result := False;
    cKeyControl:
      Result := AMouseOverTip;
  else
    Result := True;
  end;
end;

initialization
  TDpccTextLanguage.AddTable('dpcc.Core.Editor.Navigation', cTexts[TDpccLanguage.German],
    cTexts[TDpccLanguage.English]);

end.
