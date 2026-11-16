unit dpcc.Core.Commands.ShortcutTips;

// Tastenkürzel-Tipps (#600), Teil ohne VCL und Open Tools API: Regeln, wann
// nach einem Aufruf per Maus (Hauptmenü, Kontextmenü, Werkzeugleiste,
// Befehlspalette) ein Tipp mit dem Kürzel erscheint, und die Darstellung des
// Kürzels als Tastenkappen.
// Ein Tipp erscheint nur, wenn
// - shortcutTips.enabled an ist und der Befehl in shortcutTips.scope liegt
//   (dpcc = nur Befehle von dpcc, all = auch die der IDE und anderer
//   Erweiterungen),
// - der Befehl in der aktuellen Tastenbelegung ein Kürzel hat (immer frisch
//   abgefragt, so zeigt der Tipp nach einer Neubelegung sofort das neue),
// - er nicht über das Kürzel aufgerufen wurde,
// - „Nicht mehr zeigen“ für ihn nicht gewählt ist,
// - das Kürzel selbst noch keine drei Mal benutzt wurde (LearnedAfter),
// - für ihn heute noch kein Tipp kam (höchstens einer je Befehl und Tag),
// - keine Debug-Sitzung angehalten ist und kein modaler Dialog offen ist,
// - der letzte Tipp mindestens 30 s her ist (MinGapSeconds).
// Kürzel mit zwei Schritten („Strg+K, Strg+D“) zeigt der Tipp mit beiden
// Schritten; Steps zerlegt den Text der IDE in Schritte und Tasten.
// Die Zählung je Befehl liegt in dpcc.Core.Commands.Usage.

interface

uses
  System.SysUtils,
  System.Types,
  dpcc.Core.Commands.KeyConflicts,
  dpcc.Core.Commands.Usage;

type
  {$SCOPEDENUMS ON}
  /// <summary>shortcutTips.scope: nur Befehle von dpcc oder alle.</summary>
  TDpccTipScope = (Dpcc, All);
  /// <summary>Ergebnis der Regeln: Show oder der erste Grund dagegen.</summary>
  TDpccTipVerdict = (Show, Disabled, OutOfScope, NoShortCut, ViaKeyboard, Hidden, Learned, ShownToday, Debugging,
    Modal, TooSoon);
  {$SCOPEDENUMS OFF}

  /// <summary>Lage beim Aufruf eines Befehls.</summary>
  TDpccTipSituation = record
    /// <summary>shortcutTips.enabled.</summary>
    Enabled: Boolean;
    Scope: TDpccTipScope;
    /// <summary>Befehl von dpcc (sonst IDE oder andere Erweiterung).</summary>
    IsDpcc: Boolean;
    /// <summary>Kürzel in der aktuellen Tastenbelegung als Text; '' = keins.</summary>
    KeyText: string;
    /// <summary>Über das Kürzel aufgerufen.</summary>
    ViaKeyboard: Boolean;
    /// <summary>Debug-Sitzung angehalten (Haltepunkt, Ausnahme).</summary>
    DebugPaused: Boolean;
    /// <summary>Ein modaler Dialog ist offen.</summary>
    ModalOpen: Boolean;
    Now: TDateTime;
    /// <summary>Letzter Tipp der Sitzung, gleich für welchen Befehl; 0 = noch keiner.</summary>
    LastTipAt: TDateTime;
    class function Create(AEnabled: Boolean; AScope: TDpccTipScope; AIsDpcc: Boolean; const AKeyText: string;
      ANow: TDateTime): TDpccTipSituation; static;
  end;

  /// <summary>Was der Tipp zeigt.</summary>
  TDpccShortcutTipView = record
    /// <summary>Schritte des Kürzels, je Schritt die Tasten („Strg“, „Umschalt“, „C“).</summary>
    Steps: TArray<TArray<string>>;
    /// <summary>Beschriftung des Befehls ohne „&amp;“ und „…“.</summary>
    Command: string;
    /// <summary>Link „Alle Kürzel“ zeigen (Tastenkürzel-Übersicht #520 eingeschaltet).</summary>
    ShowAllKeys: Boolean;
    class function Create(const AKeyText, ACommand: string; AShowAllKeys: Boolean): TDpccShortcutTipView; static;
    /// <summary>Kürzel als ein Text: „Strg+K, Strg+D“.</summary>
    function KeyText: string;
  end;

  TDpccShortcutTips = class
  public const
    /// <summary>Nach so vielen Aufrufen über das Kürzel kein Tipp mehr.</summary>
    cLearnedAfter = 3;
    /// <summary>Mindestabstand zwischen zwei Tipps.</summary>
    cMinGapSeconds = 30;
    /// <summary>So lange bleibt der Tipp stehen.</summary>
    cVisibleMs = 4000;
    cScopeDpcc = 'dpcc';
    cScopeAll = 'all';
    /// <summary>Höchster Abstand zwischen den Schritten eines Kürzels mit zwei Schritten.</summary>
    cChordMs = 2000;
    /// <summary>Befehl der Taste, die die Befehlspalette öffnet (#502); kein Befehl der Palette selbst.</summary>
    cPaletteCommandId = 'dpcc.CommandPalette';
  public
    /// <summary>shortcutTips.scope als Wert; Unbekanntes gilt als all.</summary>
    class function ScopeOf(const AText: string): TDpccTipScope; static;
    class function ScopeName(AScope: TDpccTipScope): string; static;
    /// <summary>Die Regeln in fester Reihenfolge; Show oder der erste Grund dagegen.</summary>
    class function Decide(const AEntry: TDpccCommandUsageEntry;
      const ASituation: TDpccTipSituation): TDpccTipVerdict; static;
    /// <summary>Tipp gezeigt: Tag beim Befehl merken.</summary>
    class procedure MarkShown(var AEntry: TDpccCommandUsageEntry; ANow: TDateTime); static;
    /// <summary>A und B am selben Kalendertag; False, wenn eins 0 ist.</summary>
    class function SameDay(A, B: TDateTime): Boolean; static;
    /// <summary>„Strg+Umschalt+C“ → [[Strg, Umschalt, C]]; „Strg+K, Strg+D“ → [[Strg, K], [Strg, D]];
    /// „Strg++“ → [[Strg, +]]. Leer bei leerem Text.</summary>
    class function Steps(const AKeyText: string): TArray<TArray<string>>; static;
    /// <summary>Schritte wieder als Text: Tasten mit „+“, Schritte mit „, “.</summary>
    class function StepsText(const ASteps: TArray<TArray<string>>): string; static;
    /// <summary>Kürzel hinter dem Tabulator einer Menübeschriftung („Lesezeichen&#9;Strg+K, Strg+1“); '' ohne.
    /// </summary>
    class function KeyTextOfCaption(const ACaption: string): string; static;
    /// <summary>Kürzel als TShortCut je Schritt (deutsche oder englische Namen); nil, wenn ein Schritt unlesbar
    /// ist.</summary>
    class function ParseSteps(const AKeyText: string): TArray<Word>; static;
    /// <summary>Schlüssel einer Tastenfolge für das Nachschlagen beim Tippen: „24643“ bzw. „19531,17476“.</summary>
    class function StepsKey(const AShortCuts: TArray<Word>): string; static;
    /// <summary>Kann AShortCut ein Kürzel sein? Mit Strg oder Alt, oder F1–F24 (auch mit Umschalt).</summary>
    class function IsShortCutStroke(AShortCut: Word): Boolean; static;
    /// <summary>Befehl einer dpcc-Taste für Zählung und Tipps: der Befehl der Palette, sonst „dpcc.“ und ein
    /// fester Name.</summary>
    class function DpccCommandId(AFunc: TDpccKeyFunction): string; static;
    /// <summary>dpcc-Taste zum Befehl AId, bei mehreren Tasten für einen Befehl die erste (#775, #777); False,
    /// wenn keine.</summary>
    class function DpccFunctionOf(const AId: string; out AFunc: TDpccKeyFunction): Boolean; static;
    /// <summary>dpcc-Taste ohne Befehl in der Befehlspalette (Befehlspalette selbst, Vervollständigung,
    /// Parameter-Hint, Diagnosemodus, Suchfeld der Willkommensseite); die Karte „dpcc entdecken“ (#757) zeigt
    /// für sie die Taste aus den Einstellungen.</summary>
    class function IsKeyOnly(const AId: string; out AFunc: TDpccKeyFunction): Boolean; static;
    /// <summary>Rechteck AWidth × AHeight unten rechts in AArea mit AMargin Abstand; bleibt in AArea.</summary>
    class function PlaceBottomRight(const AArea: TRect; AWidth, AHeight, AMargin: Integer): TRect; static;
  end;

implementation

uses
  dpcc.Core.Commands.KeyMap;

/// <summary>Einstellung, Umfang, Kürzel und Weg des Aufrufs; Show, wenn nichts dagegen spricht.</summary>
function SetupVerdict(const ASituation: TDpccTipSituation): TDpccTipVerdict;
begin
  if not ASituation.Enabled then
  begin
    Result := TDpccTipVerdict.Disabled;
  end
  else if (ASituation.Scope = TDpccTipScope.Dpcc) and not ASituation.IsDpcc then
  begin
    Result := TDpccTipVerdict.OutOfScope;
  end
  else if Trim(ASituation.KeyText) = '' then
  begin
    Result := TDpccTipVerdict.NoShortCut;
  end
  else if ASituation.ViaKeyboard then
  begin
    Result := TDpccTipVerdict.ViaKeyboard;
  end
  else
  begin
    Result := TDpccTipVerdict.Show;
  end;
end;

/// <summary>Was der Befehl selbst sagt (ausgeblendet, gelernt, heute schon gezeigt); Show sonst.</summary>
function EntryVerdict(const AEntry: TDpccCommandUsageEntry; ANow: TDateTime): TDpccTipVerdict;
begin
  if AEntry.Never then
  begin
    Result := TDpccTipVerdict.Hidden;
  end
  else if AEntry.Keyboard >= TDpccShortcutTips.cLearnedAfter then
  begin
    Result := TDpccTipVerdict.Learned;
  end
  else if TDpccShortcutTips.SameDay(AEntry.LastTip, ANow) then
  begin
    Result := TDpccTipVerdict.ShownToday;
  end
  else
  begin
    Result := TDpccTipVerdict.Show;
  end;
end;

/// <summary>Letzter Tipp so kurz her, dass keiner kommt; auch bei zurückgestellter Uhr nicht sofort wieder.</summary>
function TooSoon(const ASituation: TDpccTipSituation): Boolean;
begin
  Result := (ASituation.LastTipAt > 0)
    and (Abs(ASituation.Now - ASituation.LastTipAt) * SecsPerDay < TDpccShortcutTips.cMinGapSeconds);
end;

/// <summary>Der Augenblick: Debugger angehalten, modales Fenster, letzter Tipp zu kurz her; Show sonst.</summary>
function MomentVerdict(const ASituation: TDpccTipSituation): TDpccTipVerdict;
begin
  if ASituation.DebugPaused then
  begin
    Result := TDpccTipVerdict.Debugging;
  end
  else if ASituation.ModalOpen then
  begin
    Result := TDpccTipVerdict.Modal;
  end
  else if TooSoon(ASituation) then
  begin
    Result := TDpccTipVerdict.TooSoon;
  end
  else
  begin
    Result := TDpccTipVerdict.Show;
  end;
end;

{ TDpccTipSituation }

class function TDpccTipSituation.Create(AEnabled: Boolean; AScope: TDpccTipScope; AIsDpcc: Boolean;
  const AKeyText: string; ANow: TDateTime): TDpccTipSituation;
begin
  Result := Default(TDpccTipSituation);
  Result.Enabled := AEnabled;
  Result.Scope := AScope;
  Result.IsDpcc := AIsDpcc;
  Result.KeyText := AKeyText;
  Result.Now := ANow;
end;

{ TDpccShortcutTipView }

class function TDpccShortcutTipView.Create(const AKeyText, ACommand: string;
  AShowAllKeys: Boolean): TDpccShortcutTipView;
begin
  Result := Default(TDpccShortcutTipView);
  Result.Steps := TDpccShortcutTips.Steps(AKeyText);
  Result.Command := ACommand;
  Result.ShowAllKeys := AShowAllKeys;
end;

function TDpccShortcutTipView.KeyText: string;
begin
  Result := TDpccShortcutTips.StepsText(Steps);
end;

{ TDpccShortcutTips }

class function TDpccShortcutTips.ScopeOf(const AText: string): TDpccTipScope;
begin
  if SameText(Trim(AText), cScopeDpcc) then
  begin
    Result := TDpccTipScope.Dpcc;
  end
  else
  begin
    Result := TDpccTipScope.All;
  end;
end;

class function TDpccShortcutTips.ScopeName(AScope: TDpccTipScope): string;
begin
  if AScope = TDpccTipScope.Dpcc then
  begin
    Result := cScopeDpcc;
  end
  else
  begin
    Result := cScopeAll;
  end;
end;

class function TDpccShortcutTips.SameDay(A, B: TDateTime): Boolean;
begin
  Result := (A > 0) and (B > 0) and (Trunc(A) = Trunc(B));
end;

class function TDpccShortcutTips.Decide(const AEntry: TDpccCommandUsageEntry;
  const ASituation: TDpccTipSituation): TDpccTipVerdict;
begin
  Result := SetupVerdict(ASituation);
  if Result = TDpccTipVerdict.Show then
  begin
    Result := EntryVerdict(AEntry, ASituation.Now);
  end;
  if Result = TDpccTipVerdict.Show then
  begin
    Result := MomentVerdict(ASituation);
  end;
end;

class procedure TDpccShortcutTips.MarkShown(var AEntry: TDpccCommandUsageEntry; ANow: TDateTime);
begin
  AEntry.LastTip := ANow;
end;

/// <summary>Tasten eines Schritts: an „+“ getrennt; ein „+“ am Ende oder doppelt ist die Taste „+“ selbst.
/// </summary>
function KeysOf(const AStep: string): TArray<string>;
var
  mText, mPart: string;
  mIndex: Integer;
begin
  Result := nil;
  mText := Trim(AStep);
  if mText = '' then
  begin
    Exit;
  end;
  mPart := '';
  mIndex := 1;
  while mIndex <= Length(mText) do
  begin
    if (mText[mIndex] = '+') and (Trim(mPart) <> '') then
    begin
      Result := Result + [Trim(mPart)];
      mPart := '';
    end
    else
    begin
      mPart := mPart + mText[mIndex];
    end;
    Inc(mIndex);
  end;
  if Trim(mPart) <> '' then
  begin
    Result := Result + [Trim(mPart)];
  end;
end;

class function TDpccShortcutTips.Steps(const AKeyText: string): TArray<TArray<string>>;
var
  mStep: string;
  mKeys: TArray<string>;
begin
  Result := nil;
  // „Strg+,“ hat ein Komma als Taste: nur „, “ bzw. ein Komma mit Text dahinter trennt Schritte.
  for mStep in Trim(AKeyText).Replace(', ', #1).Split([#1]) do
  begin
    mKeys := KeysOf(mStep);
    if Length(mKeys) > 0 then
    begin
      Result := Result + [mKeys];
    end;
  end;
end;

class function TDpccShortcutTips.StepsText(const ASteps: TArray<TArray<string>>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ASteps) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ', ';
    end;
    Result := Result + string.Join('+', ASteps[mIndex]);
  end;
end;

class function TDpccShortcutTips.KeyTextOfCaption(const ACaption: string): string;
var
  mTab: Integer;
begin
  mTab := Pos(#9, ACaption);
  if mTab = 0 then
  begin
    Exit('');
  end;
  Result := Trim(Copy(ACaption, mTab + 1, MaxInt));
end;

class function TDpccShortcutTips.ParseSteps(const AKeyText: string): TArray<Word>;
var
  mStep: TArray<string>;
  mModifiers, mKey: Word;
  mText: string;
begin
  Result := nil;
  for mStep in Steps(AKeyText) do
  begin
    mText := string.Join('+', mStep);
    mKey := TDpccKeyMap.ParseShortCut(mText, mModifiers);
    // Ein zweiter Schritt darf eine einzelne Taste ohne Umschalttaste sein („Strg+K, D“).
    if (mKey = 0) and (Length(mStep) = 1) and (Length(mStep[0]) = 1) and
      CharInSet(UpCase(mStep[0][1]), ['A'..'Z', '0'..'9'])
    then
    begin
      mKey := Ord(UpCase(mStep[0][1]));
    end;
    if mKey = 0 then
    begin
      Exit(nil);
    end;
    Result := Result + [mKey];
  end;
end;

class function TDpccShortcutTips.StepsKey(const AShortCuts: TArray<Word>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AShortCuts) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + IntToStr(AShortCuts[mIndex]);
  end;
end;

class function TDpccShortcutTips.IsShortCutStroke(AShortCut: Word): Boolean;
var
  mKey: Word;
begin
  mKey := AShortCut and $FF;
  if mKey = 0 then
  begin
    Exit(False);
  end;
  Result := ((AShortCut and (TDpccKeyConflicts.cScCtrl or TDpccKeyConflicts.cScAlt)) <> 0) or
    ((mKey >= $70) and (mKey <= $87));
end;

class function TDpccShortcutTips.DpccCommandId(AFunc: TDpccKeyFunction): string;
begin
  Result := TDpccKeyMap.CommandIdOf(AFunc);
  if Result <> '' then
  begin
    Exit;
  end;
  case AFunc of
    TDpccKeyFunction.Palette:
      Result := cPaletteCommandId;
    TDpccKeyFunction.Completion:
      Result := 'dpcc.Completion';
    TDpccKeyFunction.Signature:
      Result := 'dpcc.Signature';
    TDpccKeyFunction.DiagnosticMode:
      Result := 'dpcc.DiagnosticMode';
    TDpccKeyFunction.WelcomeSearch:
      Result := 'dpcc.WelcomeSearch';
    // Schnellaktionen der Willkommensseite (#764): Knopf (Maus) und Taste zählen unter derselben Kennung.
    TDpccKeyFunction.WelcomeQuickBuild:
      Result := 'dpcc.WelcomeQuickBuild';
    TDpccKeyFunction.WelcomeQuickTests:
      Result := 'dpcc.WelcomeQuickTests';
  else
    Result := 'dpcc.Key' + IntToStr(Ord(AFunc));
  end;
end;

class function TDpccShortcutTips.DpccFunctionOf(const AId: string; out AFunc: TDpccKeyFunction): Boolean;
var
  mFunc: TDpccKeyFunction;
begin
  AFunc := TDpccKeyFunction.Palette;
  for mFunc := Low(TDpccKeyFunction) to High(TDpccKeyFunction) do
  begin
    if SameText(DpccCommandId(mFunc), Trim(AId)) then
    begin
      AFunc := mFunc;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TDpccShortcutTips.IsKeyOnly(const AId: string; out AFunc: TDpccKeyFunction): Boolean;
begin
  Result := DpccFunctionOf(AId, AFunc) and (TDpccKeyMap.CommandIdOf(AFunc) = '');
end;

class function TDpccShortcutTips.PlaceBottomRight(const AArea: TRect; AWidth, AHeight, AMargin: Integer): TRect;
var
  mLeft, mTop: Integer;
begin
  mLeft := AArea.Right - AMargin - AWidth;
  mTop := AArea.Bottom - AMargin - AHeight;
  if mLeft < AArea.Left then
  begin
    mLeft := AArea.Left;
  end;
  if mTop < AArea.Top then
  begin
    mTop := AArea.Top;
  end;
  Result := Rect(mLeft, mTop, mLeft + AWidth, mTop + AHeight);
end;

end.
