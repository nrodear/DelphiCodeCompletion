unit dpcc.Core.Editor.CloseRules;

// Schließlogik der dpcc-Fenster (#414, ARG-009) ohne IDE und ohne VCL:
//
// | Ereignis                          | Popup    | Parameter-Hint                     | Tooltip           |
// |-----------------------------------|----------|------------------------------------|-------------------|
// | Esc                               | schließt | schließt (wenn kein Popup offen)   | schließt          |
// | Übernahme eines Eintrags          | schließt | bleibt bzw. öffnet (#429)          | –                 |
// | Cursor verlässt Wort bzw. Aufruf  | schließt | schließt                           | schließt          |
// | Fokus weg, IDE inaktiv            | schließt | schließt                           | schließt          |
// | Editor scrollt                    | schließt | wandert mit, schließt außer Sicht  | schließt          |
// | Größe ändert sich, Tab-Wechsel    | schließt | schließt                           | schließt          |
// | Maus verlässt Bezeichner und Tip  | –        | –                                  | nach 300 ms       |
//
// Dazu (S3c): Solange ein anderes Popup über dem Editor offen ist (Liste der Vervollständigung der IDE oder von
// dpcc, Parameter-Hint, Kontextmenü), erscheint kein Tooltip, und ein offener schließt (OtherPopup).
// Die Editor-Units lesen den Zustand (Application.Active, GetFocus, TopRow …)
// und fragen hier, ob und warum geschlossen wird. Esc und Übernahme regeln
// der Controller der Vervollständigung und die Tastenreihenfolge (#410).

interface

uses
  System.Types;

{$SCOPEDENUMS ON}

type
  TDpccCloseReason = (None, Inactive, FocusLost, OtherFile, Resized, Scrolled, OutOfView, OtherLine, BeforeWord,
    NonIdentifier);

  /// <summary>Was die Editor-Units beim Öffnen und bei jeder Prüfung ablesen.</summary>
  TDpccEditorWindowState = record
    /// <summary>Die IDE ist die aktive Anwendung.</summary>
    AppActive: Boolean;
    /// <summary>Fenster mit dem Fokus (HWND als Zahl), 0 ohne.</summary>
    Focus: NativeUInt;
    FileName: string;
    /// <summary>Oberste sichtbare Zeile, ab 1 wie TOTAEditView.TopRow.</summary>
    TopRow: Integer;
    /// <summary>Sichtbare Zeilen.</summary>
    Rows: Integer;
    Size: TPoint;
  end;

  /// <summary>Oberstes Fenster der Anwendung (EnumThreadWindows), wie die Editor-Units es ablesen.</summary>
  TDpccTopWindow = record
    /// <summary>HWND als Zahl.</summary>
    Handle: NativeUInt;
    /// <summary>GWL_STYLE.</summary>
    Style: Cardinal;
    ClassName: string;
    Visible: Boolean;
    /// <summary>Fenster in Bildschirmkoordinaten.</summary>
    Bounds: TRect;
    class function Create(AHandle: NativeUInt; AStyle: Cardinal; const AClassName: string; AVisible: Boolean;
      const ABounds: TRect): TDpccTopWindow; static;
  end;

  TDpccCloseRules = record
  public const
    /// <summary>WS_POPUP und WS_CAPTION (Winapi.Windows), hier ohne Abhängigkeit von Windows.</summary>
    cWsPopup = Cardinal($80000000);
    cWsCaption = Cardinal($00C00000);
    /// <summary>So lange bleibt der Tooltip, nachdem die Maus Bezeichner und Tooltip verlassen hat.</summary>
    cTooltipHideDelayMs = 300;
    /// <summary>So lange verweilt die Maus, bevor ein Tooltip erscheint (dpcc-Tooltip, Issue-Kennungen #1265).
    /// </summary>
    cTooltipShowDelayMs = 500;
  private
    class function Window(const AOpened, ANow: TDpccEditorWindowState): TDpccCloseReason; static;
  public
    /// <summary>Popup der Vervollständigung: IDE inaktiv, Fokus, Tab, Größe, Scrollen.</summary>
    class function Popup(const AOpened, ANow: TDpccEditorWindowState): TDpccCloseReason; static;
    /// <summary>Wort verlassen: andere Zeile, Cursor vor dem Wortanfang oder ein Zeichen, das kein Bezeichner ist.
    /// AWordStart und ACharacter 0-basiert; AIndex ist dann die Stelle des Zeichens (1-basiert in ALineText).
    /// </summary>
    class function PopupWord(ALineSame: Boolean; const ALineText: string; AWordStart, ACharacter: Integer;
      out AIndex: Integer): TDpccCloseReason; static;
    /// <summary>Verzögertes Öffnen der Liste (ARG-046): Nach der Wartezeit öffnet sie nur, wenn das Fenster
    /// unverändert ist und seit dem Auslösen an ACharacterAtStart nur Bezeichnerzeichen getippt wurden.</summary>
    class function DelayedOpen(const AOpened, ANow: TDpccEditorWindowState; ALineSame: Boolean;
      const ALineText: string; ACharacterAtStart, ACharacter: Integer): Boolean; static;
    /// <summary>Parameter-Hint. Gescrollt mit sichtbarer Ankerzeile (Zeile der Klammer beim Öffnen, ab 1) ist
    /// kein Grund: Der Hint wandert dann mit (AMove).</summary>
    class function Hint(const AOpened, ANow: TDpccEditorWindowState; AAnchorLine: Integer;
      out AMove: Boolean): TDpccCloseReason; static;
    /// <summary>Tooltip. Angeheftet oder mit der Maus darüber bleibt er bei Fokus- und Tab-Wechsel, nicht aber,
    /// wenn die IDE inaktiv wird.</summary>
    class function Tooltip(const AOpened, ANow: TDpccEditorWindowState; APinned, AMouseOver: Boolean)
      : TDpccCloseReason; static;
    /// <summary>Ist über AArea (Editor in Bildschirmkoordinaten) ein anderes Popup offen: sichtbar, WS_POPUP ohne
    /// Titelleiste, nicht leer, nicht AOwn (der Tooltip selbst) und kein Fenster für Eingabehilfen, Schatten oder
    /// Kurzhinweise der Werkzeugleisten? Dann zeigt der Tooltip nichts bzw. schließt (S3c).</summary>
    class function OtherPopup(const AWindows: TArray<TDpccTopWindow>; AOwn: NativeUInt;
      const AArea: TRect): Boolean; static;
    /// <summary>Für das Protokoll.</summary>
    class function Name(AReason: TDpccCloseReason): string; static;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Completion.Word;

{ TDpccTopWindow }

class function TDpccTopWindow.Create(AHandle: NativeUInt; AStyle: Cardinal; const AClassName: string;
  AVisible: Boolean; const ABounds: TRect): TDpccTopWindow;
begin
  Result.Handle := AHandle;
  Result.Style := AStyle;
  Result.ClassName := AClassName;
  Result.Visible := AVisible;
  Result.Bounds := ABounds;
end;

{ TDpccCloseRules }

class function TDpccCloseRules.OtherPopup(const AWindows: TArray<TDpccTopWindow>; AOwn: NativeUInt;
  const AArea: TRect): Boolean;
const
  // Fenster der Eingabemethoden, Kurzhinweise von Werkzeugleisten und Schatten (CS_DROPSHADOW, auch der des
  // Tooltips selbst): kein Popup über dem Editor.
  cIgnored: array[0..3] of string = ('IME', 'MSCTFIME UI', 'tooltips_class32', 'SysShadow');
var
  mWindow: TDpccTopWindow;
  mIgnored: string;
  mSkip: Boolean;
begin
  Result := False;
  for mWindow in AWindows do
  begin
    if not mWindow.Visible or (mWindow.Handle = AOwn) or (mWindow.Style and cWsPopup = 0) or
      (mWindow.Style and cWsCaption = cWsCaption) or mWindow.Bounds.IsEmpty or
      not mWindow.Bounds.IntersectsWith(AArea) then
    begin
      Continue;
    end;
    mSkip := False;
    for mIgnored in cIgnored do
    begin
      mSkip := mSkip or SameText(mWindow.ClassName, mIgnored);
    end;
    if not mSkip then
    begin
      Exit(True);
    end;
  end;
end;

class function TDpccCloseRules.Window(const AOpened, ANow: TDpccEditorWindowState): TDpccCloseReason;
begin
  Result := TDpccCloseReason.None;
  if not ANow.AppActive then
  begin
    Result := TDpccCloseReason.Inactive;
  end
  else if ANow.Focus <> AOpened.Focus then
  begin
    Result := TDpccCloseReason.FocusLost;
  end
  else if not SameText(ANow.FileName, AOpened.FileName) then
  begin
    Result := TDpccCloseReason.OtherFile;
  end
  else if ANow.Size <> AOpened.Size then
  begin
    Result := TDpccCloseReason.Resized;
  end;
end;

class function TDpccCloseRules.Popup(const AOpened, ANow: TDpccEditorWindowState): TDpccCloseReason;
begin
  Result := Window(AOpened, ANow);
  if (Result = TDpccCloseReason.None) and (ANow.TopRow <> AOpened.TopRow) then
  begin
    Result := TDpccCloseReason.Scrolled;
  end;
end;

class function TDpccCloseRules.PopupWord(ALineSame: Boolean; const ALineText: string; AWordStart,
  ACharacter: Integer; out AIndex: Integer): TDpccCloseReason;
var
  mIndex: Integer;
begin
  AIndex := 0;
  if not ALineSame then
  begin
    Exit(TDpccCloseReason.OtherLine);
  end;
  if ACharacter < AWordStart then
  begin
    Exit(TDpccCloseReason.BeforeWord);
  end;
  for mIndex := AWordStart + 1 to ACharacter do
  begin
    if (mIndex > Length(ALineText)) or not TDpccWord.IsIdentifierChar(ALineText[mIndex]) then
    begin
      AIndex := mIndex;
      Exit(TDpccCloseReason.NonIdentifier);
    end;
  end;
  Result := TDpccCloseReason.None;
end;

class function TDpccCloseRules.DelayedOpen(const AOpened, ANow: TDpccEditorWindowState; ALineSame: Boolean;
  const ALineText: string; ACharacterAtStart, ACharacter: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := (Popup(AOpened, ANow) = TDpccCloseReason.None) and
    (PopupWord(ALineSame, ALineText, ACharacterAtStart, ACharacter, mIndex) = TDpccCloseReason.None);
end;

class function TDpccCloseRules.Hint(const AOpened, ANow: TDpccEditorWindowState; AAnchorLine: Integer;
  out AMove: Boolean): TDpccCloseReason;
begin
  AMove := False;
  Result := Window(AOpened, ANow);
  if (Result <> TDpccCloseReason.None) or (ANow.TopRow = AOpened.TopRow) then
  begin
    Exit;
  end;
  // Die Klammer, an der der Hint hängt, entscheidet, nicht der Caret.
  if (AAnchorLine < ANow.TopRow) or (AAnchorLine >= ANow.TopRow + ANow.Rows) then
  begin
    Result := TDpccCloseReason.OutOfView;
  end
  else
  begin
    AMove := True;
  end;
end;

class function TDpccCloseRules.Tooltip(const AOpened, ANow: TDpccEditorWindowState; APinned,
  AMouseOver: Boolean): TDpccCloseReason;
begin
  Result := Window(AOpened, ANow);
  if (Result = TDpccCloseReason.None) and (ANow.TopRow <> AOpened.TopRow) then
  begin
    Result := TDpccCloseReason.Scrolled;
  end;
  // Angeheftet oder mit der Maus darüber: Fokus- und Tab-Wechsel lassen ihn stehen.
  if (APinned or AMouseOver) and (Result in [TDpccCloseReason.FocusLost, TDpccCloseReason.OtherFile]) then
  begin
    Result := TDpccCloseReason.None;
  end;
end;

class function TDpccCloseRules.Name(AReason: TDpccCloseReason): string;
const
  cNames: array[TDpccCloseReason] of string = ('keiner', 'IDE inaktiv', 'Fokus woanders', 'anderer Tab',
    'Größe geändert', 'gescrollt', 'außer Sicht', 'andere Zeile', 'Cursor vor dem Wortanfang',
    'Zeichen getippt');
begin
  Result := cNames[AReason];
end;

end.
