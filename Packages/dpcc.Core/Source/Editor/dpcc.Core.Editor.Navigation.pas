unit dpcc.Core.Editor.Navigation;

// Regeln für Strg+Klick und „Deklaration suchen“ (Auftrag NAV) ohne IDE und ohne VCL. Die Editor-Units lesen den
// Zustand (Tasten, Maus, Antwort des Servers) und fragen hier, was gilt.
//   - Sprung (TDpccGotoDefinition): Delphi 13 fragt für Strg+Klick, „Deklaration suchen“ und Alt+↑ nur den in den
//     Optionen gewählten Code-Insight-Anbieter (GotoDefinition, ToolsAPI). Ist das dpcc, meldet es ein gefundenes
//     Ziel mit Datei und Zeile. In jedem anderen Fall (nichts gefunden, Ersatz-Unit ohne Quelltext, Zeitlimit,
//     Sicherung, kein Server) bricht es still ab: True mit leerem Dateinamen. False hieße für die IDE „Fehlschlag
//     melden“; sie zeigte dann „Datei "" nicht gefunden“. An einen anderen Anbieter reicht die IDE nicht weiter.
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
    Failed);

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
    /// in der Klasse), und der Sprung geht zur Implementierung.</summary>
    class function OnTarget(const AFileName: string; ALine, ACharacter: Integer; const ALineText,
      ATargetFile: string; ATargetLine, ATargetCharacter: Integer): Boolean; static;
    /// <summary>Stelle der Anfrage (X = Zeichen, Y = Zeile): bei gedrückter Strg-Taste (Strg+Klick) und gültiger
    /// Mausstelle über einem Bezeichner AMouse, sonst ACaret.</summary>
    class function ChoosePosition(ACtrlDown, AMouseValid: Boolean; const AMouse, ACaret: TPoint): TPoint; static;
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
  System.Math;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TNavigationText = (ProviderNotice, OverloadKeys);

{$SCOPEDENUMS OFF}

const
  cTexts: array[TDpccLanguage, TNavigationText] of string = (
    ('dpcc ist in den Optionen der IDE als Code-Insight-Anbieter für Delphi gewählt. Strg+Klick und „Deklaration ' +
     'suchen“ laufen über dpcc; ohne Ziel (etwa in Units ohne Quelltext) springt die IDE nicht. Error Insight ' +
     '(Fehlermarkierungen im Editor) und die übrigen Dienste von DelphiLSP fehlen dann. Wer sie braucht, wählt ' +
     'dort wieder DelphiLSP; Strg+Leertaste bleibt bei dpcc.',
     'Strg+Alt+↑/↓'),
    ('dpcc is selected as the Code Insight provider for Delphi in the IDE options. Ctrl+click and “Find ' +
     'Declaration” go through dpcc; without a target (for example in units without source) the IDE does not ' +
     'jump. Error Insight (error marks in the editor) and the other DelphiLSP services are missing then. If you ' +
     'need them, select DelphiLSP there again; Ctrl+Space stays with dpcc.',
     'Ctrl+Alt+↑/↓'));

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
  Result := SameText(AFileName, ATargetFile) and (ALine = ATargetLine) and (ACharacter >= ATargetCharacter) and
    (ATargetCharacter < Length(ALineText));
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
