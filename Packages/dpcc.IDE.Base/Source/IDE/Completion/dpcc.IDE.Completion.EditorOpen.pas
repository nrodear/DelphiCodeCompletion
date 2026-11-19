unit dpcc.IDE.Completion.EditorOpen;

// Vervollständigung im Editor (#410), Stufe Öffnen: Wort vor dem Cursor als Präfix, Caret-Rechteck als Anker des
// Popups, Einstellungen ins Popup, verzögertes automatisches Öffnen (ARG-046). Kette:
// dpcc.IDE.Completion.EditorState.
// Beim Tippen eines Bezeichners (L5, TDpccCompletionSource.Typing) prüft Invoke vor allem anderen und nach der
// Verzögerung noch einmal die Regel TDpccAutoOpen (completion.autoMinChars): Unter der Schwelle keine Anfrage und kein
// Popup, eine offene Liste filtert weiter. Strg+Leertaste und Auslösezeichen gehen wie bisher durch.

interface

uses
  Winapi.Windows,
  System.Types,
  ToolsAPI,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.AutoOpen,
  dpcc.IDE.Completion.EditorState;

type
  TDpccEditorCompletionOpen = class(TDpccEditorCompletionState)
  protected
    procedure DelayTimerTick(Sender: TObject);
    /// <summary>Kontext an der Cursorstelle; ALine ab 1, ACharacter und AWordStart 0-basiert.</summary>
    function ContextAt(const AView: IOTAEditView; const ALineText: string; ALine, ACharacter,
      AWordStart: Integer): TDpccContext;
  private
    procedure ApplyStyle(const ACaret: TRect);
    function CaretRect(out AWindow: HWND; out ARect: TRect): Boolean;
    /// <summary>Einstellungen der Liste in Popup und Ablauf übernehmen (vor jedem Öffnen).</summary>
    procedure ApplyOptions;
    /// <summary>Popup am Wortanfang verankern (ACaret: Caret-Rechteck) und die offene Stelle merken.</summary>
    procedure Anchor(const AView: IOTAEditView; AWindow: HWND; ACaret: TRect; ALine, AWordStart: Integer;
      const APrefix: string);
    /// <summary>Verzögertes Öffnen vormerken (ARG-046); DelayTimerTick ruft Invoke mit ASource wieder auf.</summary>
    procedure StartDelay(const AView: IOTAEditView; ALine, ACharacter: Integer; AWindow: HWND;
      ASource: TDpccCompletionSource);
    /// <summary>Zeichen, nach dem die IDE automatisch geöffnet hat ('' ohne besonderes).</summary>
    function AutomaticTrigger(const AView: IOTAEditView; const ALineText: string; ACharacter: Integer): string;
  public
    /// <summary>Öffnet die Vervollständigung an der Cursorstelle von AView; False, wenn nicht möglich.
    /// AAutomatic: von der IDE nach einem Zeichen ausgelöst, nicht über Strg+Leer. Steht dann "[" vor dem
    /// Cursor, fragt dpcc nur nach Mengenwerten (#448).</summary>
    function Invoke(const AView: IOTAEditView; AAutomatic: Boolean): Boolean; overload;
    /// <summary>Wie oben über Strg+Leer (AAutomatic = False).</summary>
    function Invoke(const AView: IOTAEditView): Boolean; overload;
    /// <summary>Wie oben mit dem Auslöser: Key = Strg+Leer, Trigger = automatisch nach einem Zeichen, Typing = beim
    /// Tippen eines Bezeichners (L5): nur ab completion.autoMinChars Zeichen und nur ohne offene Liste.</summary>
    function Invoke(const AView: IOTAEditView; ASource: TDpccCompletionSource): Boolean; overload;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.Timing,
  dpcc.Core.Completion.Word,
  dpcc.Core.Completion.Ranking,
  dpcc.Core.Editor.CloseRules,
  dpcc.Core.Lsp.Session,
  dpcc.IDE.Completion.History,
  dpcc.IDE.Completion.Favorites,
  dpcc.Core.Settings.CompletionView,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Foundation.EditorBuffer,
  dpcc.IDE.Foundation.EditorStyle;

/// <summary>Plattform und Konfiguration des aktiven Projekts („Win32 · Debug“, #476); '' ohne Projekt.</summary>
function ActiveTarget: string;
var
  mProject: IOTAProject;
begin
  Result := '';
  mProject := GetActiveProject;
  if mProject = nil then
  begin
    Exit;
  end;
  Result := mProject.CurrentPlatform;
  if mProject.CurrentConfiguration <> '' then
  begin
    if Result <> '' then
    begin
      Result := Result + ' · ' + mProject.CurrentConfiguration;
    end
    else
    begin
      Result := mProject.CurrentConfiguration;
    end;
  end;
end;

const
  /// <summary>Auslöser fürs Protokoll (L5).</summary>
  cSourceNames: array[TDpccCompletionSource] of string = (', Strg+Leer', ', Zeichen', ', Tippen');

/// <summary>Steht ein AChar direkt vor dem Cursor (ACharacter 0-basiert)?</summary>
function TypedBefore(const ALineText: string; ACharacter: Integer; AChar: Char): Boolean;
begin
  Result := (ACharacter > 0) and (ACharacter <= Length(ALineText)) and (ALineText[ACharacter] = AChar);
end;

{ TDpccEditorCompletionOpen }

procedure TDpccEditorCompletionOpen.ApplyStyle(const ACaret: TRect);
begin
  // Farben aus dem Thema der IDE (hell/dunkel), Schrift aus den Editoroptionen, Monitor-DPI und Zoom
  // am Caret (#411, #412, #445).
  Log(TDpccIdeStyle.Apply(FPopup, ACaret));
  // Schlicht (S6): Farben wie der Hover-Tooltip und die Code-Insight-Liste der IDE (Farbschema des Editors),
  // Auswahl in der Auswahlfarbe des IDE-Themas.
  FPopup.Colors := TDpccIdeStyle.CompletionListColors;
end;

function TDpccEditorCompletionOpen.CaretRect(out AWindow: HWND; out ARect: TRect): Boolean;
var
  mInfo: TGUIThreadInfo;
begin
  FillChar(mInfo, SizeOf(mInfo), 0);
  mInfo.cbSize := SizeOf(mInfo);
  Result := GetGUIThreadInfo(GetCurrentThreadId, mInfo) and (mInfo.hwndCaret <> 0);
  if not Result then
  begin
    Exit;
  end;
  AWindow := mInfo.hwndCaret;
  ARect := mInfo.rcCaret;
  MapWindowPoints(AWindow, 0, ARect, 2);
end;

function TDpccEditorCompletionOpen.ContextAt(const AView: IOTAEditView; const ALineText: string; ALine,
  ACharacter, AWordStart: Integer): TDpccContext;
begin
  Result := Default(TDpccContext);
  Result.FileName := AView.Buffer.FileName;
  Result.Text := TDpccEditorBuffer.Text(AView.Buffer);
  Result.Line := ALine - 1;
  Result.Character := ACharacter;
  Result.Prefix := Copy(ALineText, AWordStart + 1, ACharacter - AWordStart);
  if (AWordStart > 0) and (ALineText[AWordStart] = '.') then
  begin
    Result.Kind := TDpccContextKind.MemberAccess;
  end
  else
  begin
    Result.Kind := TDpccContextKind.Identifier;
  end;
end;

function TDpccEditorCompletionOpen.AutomaticTrigger(const AView: IOTAEditView; const ALineText: string;
  ACharacter: Integer): string;
begin
  Result := '';
  // Nach "[" automatisch geöffnet (#448): nur ein Mengenkonstruktor bekommt eine Liste.
  if TypedBefore(ALineText, ACharacter, '[') then
  begin
    Result := '[';
  end
  // Nach dem ";" hinter einem übernommenen Konstruktor (#489): nur „Mit try…finally absichern“.
  else if TypedBefore(ALineText, ACharacter, ';') and GuardPending(AView) then
  begin
    Result := ';';
    FGuard.Line := 0;
  end
  // Nach dem Zeilenende (Enter) hinter einem übernommenen Konstruktor ohne ";" (#489).
  else if FGuard.NewLine then
  begin
    Result := #10;
  end
  // Nach "(" hinter einem Namen (#472): nur „Methode anlegen“, wenn der Name unbekannt ist.
  else if FCall.Opened then
  begin
    Result := '(';
  end;
end;

procedure TDpccEditorCompletionOpen.ApplyOptions;
begin
  FPopup.VisibleRows := TDpccIdeSettings.Current.VisibleRows;
  FPopup.ManualListWidth := TDpccIdeSettings.Current.ListWidth;
  // Fest seit OPT1 (TDpccFixedSettings): Gruppen geerbter Member (#419), Marke „Zweig 0“ an Feldern varianter
  // Records (#846), Listenmodus nur für Mitgliederlisten (#497).
  FController.GroupInherited := TDpccFixedSettings.cGroupInherited;
  FPopup.DimInherited := TDpccFixedSettings.cGroupInherited;
  FPopup.ShowVariantBranch := TDpccFixedSettings.cCompletionVariantBranch;
  // Einträge ohne Treffer zeigen (#497).
  FController.ListMode := TDpccListModes.ModeOf(TDpccIdeSettings.Current.CompletionListMode);
  FController.ListScope := TDpccListModes.ScopeOf(TDpccFixedSettings.cCompletionListScope);
  // Während der Server indiziert, liefert er den vorhandenen Stand; die Fußzeile sagt es (#492).
  FPopup.Limited := IndexingNow;
  FPopup.Target := ActiveTarget;
  // Lernende Gewichtung (#418).
  if TDpccIdeSettings.Current.Learning then
  begin
    FController.Usage := TDpccIdeHistory.Instance;
  end
  else
  begin
    FController.Usage := nil;
  end;
  // Favoriten (#458, fest an seit OPT1): angeheftete Einträge oben, Strg+D in der Liste.
  FController.Favorites := TDpccIdeFavorites.Instance;
  // Beispielnamen verworfener Dubletten im Diagnoselog nur mit diagnostics.log.names (#1478).
  FController.LogNames := TDpccIdeSettings.Current.LogNames;
end;

procedure TDpccEditorCompletionOpen.StartDelay(const AView: IOTAEditView; ALine, ACharacter: Integer;
  AWindow: HWND; ASource: TDpccCompletionSource);
begin
  FDelay.Source := ASource;
  FDelay.View := AView;
  FDelay.Line := ALine;
  FDelay.Character := ACharacter;
  FDelay.Window := AWindow;
  FDelay.State := WindowState(AView, AWindow, AWindow);
  FDelay.Timer.Interval := TDpccFixedSettings.cOpenDelayMs;
  FDelay.Timer.Enabled := True;
end;

procedure TDpccEditorCompletionOpen.Anchor(const AView: IOTAEditView; AWindow: HWND; ACaret: TRect; ALine,
  AWordStart: Integer; const APrefix: string);
begin
  // Das Popup beginnt am Wortanfang, nicht am Caret.
  FPopup.Canvas.Font := FPopup.Font;
  ACaret.Left := ACaret.Left - FPopup.Canvas.TextWidth(APrefix);
  FPopup.Anchor := ACaret;
  FOpen.View := AView;
  FOpen.Window := AWindow;
  FOpen.Line := ALine;
  FOpen.WordStart := AWordStart;
  FOpen.Opened := WindowState(AView, AWindow, AWindow);
end;

function TDpccEditorCompletionOpen.Invoke(const AView: IOTAEditView): Boolean;
begin
  Result := Invoke(AView, TDpccCompletionSource.Key);
end;

function TDpccEditorCompletionOpen.Invoke(const AView: IOTAEditView; AAutomatic: Boolean): Boolean;
begin
  if AAutomatic then
  begin
    Result := Invoke(AView, TDpccCompletionSource.Trigger);
  end
  else
  begin
    Result := Invoke(AView, TDpccCompletionSource.Key);
  end;
end;

function TDpccEditorCompletionOpen.Invoke(const AView: IOTAEditView; ASource: TDpccCompletionSource): Boolean;
var
  mAutomatic: Boolean;
  mContext: TDpccContext;
  mLineText: string;
  mCursor: TOTAEditPos;
  mCharacter, mWordStart: Integer;
  mWindow: HWND;
  mAnchor: TRect;
  mStarted: Int64;
begin
  Result := False;
  // Diagnosemodus (#479): Kontext ab hier messen.
  mStarted := 0;
  if TDpccQueryTimings.Enabled then
  begin
    mStarted := TDpccQueryTimings.Stamp;
  end;
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  mCursor := AView.CursorPos;
  mLineText := TDpccEditorBuffer.LineText(AView, mCursor.Line);
  mCharacter := TLspSession.ColumnToIndex(mLineText, mCursor.Col, TDpccEditorBuffer.TabWidth(AView.Buffer));
  mWordStart := TDpccWord.StartBefore(mLineText, mCharacter);
  mAutomatic := ASource <> TDpccCompletionSource.Key;
  // Beim Tippen (L5): erst ab completion.autoMinChars Zeichen, sonst keine Anfrage; offene Liste filtert weiter.
  if (ASource = TDpccCompletionSource.Typing) and (TDpccAutoOpen.Action(ASource, mLineText, mCharacter,
    FController.Active, TDpccIdeSettings.Current.AutoMinChars) <> TDpccAutoOpenAction.Query) then
  begin
    Exit;
  end;
  if not CaretRect(mWindow, mAnchor) then
  begin
    Log('Vervollständigung: kein Caret gefunden');
    Exit;
  end;
  CancelDelay;
  // Verzögerung bis zum Öffnen (ARG-046, fest TDpccFixedSettings.cOpenDelayMs): nur beim automatischen Auslösen;
  // DelayTimerTick ruft wieder auf.
  if mAutomatic and not FDelay.Running then
  begin
    StartDelay(AView, mCursor.Line, mCharacter, mWindow, ASource);
    Exit(True);
  end;
  mContext := ContextAt(AView, mLineText, mCursor.Line, mCharacter, mWordStart);
  mContext.Automatic := mAutomatic;
  mContext.Typed := ASource = TDpccCompletionSource.Typing;
  mContext.Started := mStarted;
  // Mit Esc geschlossen (#414): im selben Wort nicht automatisch wieder öffnen.
  if mAutomatic and FController.Dismissed(mContext) then
  begin
    Exit;
  end;
  // Beim Tippen gibt es kein Auslösezeichen; "(" bzw. ";" vor dem Wort gehören zu einem früheren Öffnen.
  if ASource = TDpccCompletionSource.Trigger then
  begin
    mContext.Trigger := AutomaticTrigger(AView, mLineText, mCharacter);
  end;
  FGuard.NewLine := False;
  FCall.Opened := False;
  ApplyStyle(mAnchor);
  ApplyOptions;
  Anchor(AView, mWindow, mAnchor, mCursor.Line, mWordStart, mContext.Prefix);
  // Ohne Datei- und Bezeichnernamen: Das Diagnoselog soll weitergegeben werden können (#647).
  Log(Format('Vervollständigung (%s%s): Zeile %d, Zeichen %d, Präfix %d Zeichen',
    [ExtractFileExt(mContext.FileName), cSourceNames[ASource], mContext.Line + 1, mContext.Character,
    Length(mContext.Prefix)]));
  FController.Start(mContext);
  ActiveChanged;
  Result := True;
end;

procedure TDpccEditorCompletionOpen.DelayTimerTick(Sender: TObject);
var
  mView: IOTAEditView;
  mLineText: string;
  mCharacter: Integer;
  mSame: Boolean;
  mSource: TDpccCompletionSource;
begin
  mView := FDelay.View;
  mSource := FDelay.Source;
  CancelDelay;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    Exit;
  end;
  try
    mSame := mView.CursorPos.Line = FDelay.Line;
    mLineText := TDpccEditorBuffer.LineText(mView, mView.CursorPos.Line);
    mCharacter := TLspSession.ColumnToIndex(mLineText, mView.CursorPos.Col,
      TDpccEditorBuffer.TabWidth(mView.Buffer));
    if not TDpccCloseRules.DelayedOpen(FDelay.State, WindowState(mView, FDelay.Window, GetFocus), mSame,
      mLineText, FDelay.Character, mCharacter) then
    begin
      Log('Vervollständigung: verzögertes Öffnen verworfen');
      Exit;
    end;
    FDelay.Running := True;
    try
      Invoke(mView, mSource);
    finally
      FDelay.Running := False;
    end;
  except
    on E: Exception do
    begin
      Log('Vervollständigung: ' + E.Message);
      TDpccGuard.Report(TDpccFeature.Completion, E);
    end;
  end;
end;

end.
