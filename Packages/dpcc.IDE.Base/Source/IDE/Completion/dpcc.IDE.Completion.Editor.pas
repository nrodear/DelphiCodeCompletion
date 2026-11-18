unit dpcc.IDE.Completion.Editor;

// Vervollständigung im Editor der IDE (#410, #414, #407): verbindet Datenquelle
// (#408), Ablauf (TDpccCompletionController) und Popup (dpcc.UI) mit dem
// Editor. Der Code Insight-Manager ruft Invoke statt der eingebauten Liste.
//   - Start: Wort vor dem Cursor als Präfix, Caret-Rechteck als Anker des Popups.
//   - Weitertippen: EditorViewModified und ein Zeitgeber (für Cursorbewegungen)
//     lesen die aktuelle Zeile und filtern neu.
//   - Schließen (#414): Cursor verlässt das Wort oder die Zeile, Editor verliert
//     den Fokus, IDE wird inaktiv, Editor scrollt, Ansicht wechselt.
//   - Tasten: Nur solange das Popup offen ist, nimmt es über den gemeinsamen
//     Tastatur-Hook (dpcc.IDE.Foundation.KeyHook) ↑ ↓ Bild↑ Bild↓ Pos1 Ende Enter Tab Esc
//     ohne Umschalt/Strg/Alt entgegen; sonst gehen alle Tasten an den Editor.
//   - Übernahme: ein Undo-Schritt (CreateUndoableWriter) für Name und uses-Ergänzung.
//   - Das Detailpanel (#424) mit Überladungen (Alt+Pfeil, #425) und XMLDoc gibt es seit S7a nicht mehr; die
//     schlichte Liste (S6) fragt keine Details beim Server nach. Strg+Q und Strg+C gehören wieder dem Editor.
//   - Commit-Zeichen (#429): Wird hinter dem Wort "(", ";" oder "." getippt und trifft
//     der gewählte Eintrag klar, wird er übernommen und das Zeichen bleibt stehen;
//     sonst bleibt nur das Zeichen und das Popup schließt. Erkannt nach dem Tippen im
//     Puffer, nicht über eine Tastenbindung: unabhängig vom Tastaturlayout.
//   - Einträge mit Platzhaltern (#51, vom Server, etwa Postfix-Vorlagen oder Gerüste anonymer Methoden):
//     Übernehmen setzt den Text mit der Einrückung der Zeile ein und startet den Platzhalter-Modus
//     (dpcc.IDE.Completion.Placeholders). Eigene Code-Vorlagen gibt es seit S2 nicht mehr.
//   - Diagnosemodus (#479): Invoke nimmt nur bei eingeschalteter Messung beim Aufruf einen Zeitstempel
//     (TDpccContext.Started); der Kontext reicht von dort bis zur Anfrage.
//   - Favoriten (#458, Einstellung Favorites): Strg+D im offenen Popup heftet den gewählten Eintrag an oder löst
//     ihn (TDpccIdeFavorites, sofort gespeichert); Ergebnis bzw. „Schon 5 Favoriten …“ als Hinweis in der
//     Fußzeile. Strg+D gehört bei offener Liste immer dem Popup, nie dem Editor.
//   - Zweites Strg+Leertaste (L3): KeyInvoke fragt TDpccCompletionFallback. Blieb die Liste nach dem vorigen
//     Strg+Leertaste an derselben Stelle ohne Eingabe dazwischen leer, schließt dpcc und die Taste geht an die IDE
//     (DelphiLSP öffnet ihre Liste); die Fußzeile des leeren Zustands weist darauf hin. L4: nur, wenn die Liste der
//     IDE erreichbar ist (dpcc nicht der gewählte Code-Insight-Anbieter); ist sie schon offen, gehört ihr die Taste
//     und dpcc öffnet keine zweite Liste (TDpccIdeList, ermittelt vom Code Insight-Manager).
//   - Tippen (L5, completion.autoMinChars, Regel in TDpccAutoOpen): Jede Änderung führt den Stand der Zeile nach
//     (TDpccTypingTracker). Ist genau ein Zeichen eines Bezeichners ohne Punkt davor getippt worden und hat das Wort
//     die Schwelle erreicht (Vorgabe 0 = aus, eingeschaltet etwa 5 Zeichen), öffnet dpcc die Liste wie ein
//     automatischer Auslöser (mit Verzögerung, Esc-Sperre). Darunter keine Anfrage. Nur in Dateien, die dpcc bedient (OnHandles), nicht im
//     Platzhalter-Modus und nicht, solange die Liste der IDE offen ist (OnIdeListOpen). Eine offene Liste filtert
//     wie bisher weiter; Strg+Leertaste öffnet bei jeder Länge.
// Aufgeteilt in eine Kette von Stufen (dpcc.IDE.Completion.EditorState …EditorCommit); hier Tasten und
// Weitertippen. Die Vorschau im Editor (#434) ist seit OPT2 entfallen (war fest aus).

interface

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.AutoOpen,
  dpcc.Core.Completion.Controller,
  dpcc.Core.Completion.Fallback,
  dpcc.Core.Editor.CloseRules,
  dpcc.Core.Lsp.Session,
  dpcc.IDE.Completion.EditorState,
  dpcc.IDE.Completion.EditorCommit;

type
  /// <summary>Protokoll für die Diagnose (Registry-Wert Diagnose).</summary>
  TDpccLogProc = dpcc.IDE.Completion.EditorState.TDpccLogProc;
  /// <summary>Quellen der Vervollständigung aus dem Kern; setzt die Kompositionswurzel ein.</summary>
  TDpccCompletionSources = dpcc.IDE.Completion.EditorState.TDpccCompletionSources;
  TDpccCompletionSourcesFactory = dpcc.IDE.Completion.EditorState.TDpccCompletionSourcesFactory;

  TDpccEditorCompletion = class(TDpccEditorCompletionCommit)
  private
    procedure Recheck;
    /// <summary>IDE inaktiv, anderes Fenster im Fokus, gescrollt, Größe geändert (#414): schließt; True dann.
    /// </summary>
    function WindowLeft: Boolean;
    /// <summary>Cursor hat das Wort verlassen: übernehmen über ein Commit-Zeichen (#429) oder schließen.</summary>
    procedure LeaveWord(AReason: TDpccCloseReason; const ALineText: string; AIndex, ACharacter: Integer);
    /// <summary>Neues Präfix: lokal weiterfiltern, bei Bedarf im Hintergrund neu fragen.</summary>
    procedure Refilter(const ALineText: string; ALine, ACharacter: Integer);
    procedure TimerTick(Sender: TObject);
    /// <summary>Gehört die Taste gerade dem Popup?</summary>
    function WantsKey(AKey: TDpccNavigationKey): Boolean;
    /// <summary>Gewählten Eintrag als Favorit (#458) anheften bzw. lösen (Strg+D). Speichert und zeigt das Ergebnis
    /// in der Fußzeile.</summary>
    procedure ToggleFavorite;
    /// <summary>Gleich nach der Benachrichtigung automatisch öffnen; AFromGuard: nach dem Enter hinter einem
    /// Konstruktor (#489), sonst nach "(" hinter einem Namen (#472).</summary>
    procedure QueueInvoke(const AView: IOTAEditView; AFromGuard: Boolean);
    procedure SetPending(AFromGuard, AValue: Boolean);
    /// <summary>"(" hinter einem Namen (#472): fragen, ob der Server die Methode anlegen kann; einmal je Stelle.
    /// </summary>
    procedure CheckCallOpened(const AView: IOTAEditView);
    /// <summary>Stand der Zeile des Cursors nachführen (L5); True, wenn gerade ein Zeichen eines Bezeichners getippt
    /// wurde. ALineText und ACharacter: Zeile und Zeichen vor dem Cursor.</summary>
    function TrackTyping(const AView: IOTAEditView; out ALineText: string; out ACharacter: Integer): Boolean;
    /// <summary>Getipptes Zeichen (L5): ab completion.autoMinChars Zeichen gleich nach der Benachrichtigung öffnen.
    /// </summary>
    procedure CheckTyped(const AView: IOTAEditView; const ALineText: string; ACharacter: Integer);
    /// <summary>")" vor der automatischen Klammer (#430): diese überspringen.</summary>
    procedure TrackAutoParen(const AView: IOTAEditView);
    /// <summary>Stelle des Cursors in AView für das zweite Strg+Leertaste (L3): Datei, Zeile, Zeichen, Zeilentext.
    /// </summary>
    function CursorPlace(const AView: IOTAEditView): TDpccCompletionPlace;
  public
    /// <summary>ASources legt die Quellen des Kerns an (Kompositionswurzel).</summary>
    constructor Create(const ASession: TDpccSessionFunc; const ALog: TDpccLogProc;
      const ASources: TDpccCompletionSourcesFactory);
    destructor Destroy; override;
    /// <summary>Taste aus dem Tastatur-Hook; True, wenn verbraucht.</summary>
    function HandleKey(AKey: TDpccNavigationKey): Boolean;
    /// <summary>Befehl im offenen Popup: Strg+D Favorit (#458).</summary>
    function WantsCommand(AKey: Word; AShift: TShiftState): Boolean;
    procedure HandleCommand(AKey: Word; AShift: TShiftState);
    /// <summary>Editortext wurde geändert.</summary>
    procedure EditorModified(const AView: IOTAEditView);
    /// <summary>Strg+Leertaste über die Taste von dpcc (L3). False: Die Taste gehört der IDE, weil an derselben
    /// Stelle nach dem vorigen Strg+Leertaste ohne Eingabe dazwischen die Liste leer blieb und die Liste der IDE
    /// erreichbar ist, oder weil die Liste der IDE schon offen ist (L4, AIde); dann ist die Liste von dpcc
    /// geschlossen. Sonst öffnet dpcc die Vervollständigung (Invoke), True.</summary>
    function KeyInvoke(const AView: IOTAEditView; const AIde: TDpccIdeList): Boolean;
    /// <summary>Stand der Zeile des Cursors in AView merken, ohne etwas auszulösen (L5): Der Manager legt die
    /// Vervollständigung erst beim ersten Tippen in einer Datei von dpcc an; das nächste Zeichen zählt dann.</summary>
    procedure SeedTyping(const AView: IOTAEditView);
    /// <summary>Bedient dpcc die Datei (Hauptschalter, Endung, Sicherung)? Ohne Haken öffnet Tippen nichts (L5).
    /// </summary>
    property OnHandles: TFunc<string, Boolean> read FOnHandles write FOnHandles;
    /// <summary>Sitzung starten bzw. laufende melden, nur im Hauptthread; vor dem Öffnen beim Tippen (L5).</summary>
    property OnEnsureSession: TFunc<Boolean> read FOnEnsureSession write FOnEnsureSession;
    /// <summary>Ist die Liste der IDE gerade offen (L4)? Dann öffnet Tippen keine zweite Liste (L5).</summary>
    property OnIdeListOpen: TFunc<Boolean> read FOnIdeListOpen write FOnIdeListOpen;
  end;

implementation

uses
  Winapi.Windows,
  DockForm,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Completion.Parentheses,
  dpcc.Core.Completion.Favorites,
  dpcc.IDE.Foundation.KeyHook,
  dpcc.IDE.Foundation.Settings,
  dpcc.IDE.Foundation.EditorBuffer,
  dpcc.IDE.Completion.History,
  dpcc.IDE.Completion.Favorites,
  dpcc.UI.Completion.Strings;

type
  TDpccEditNotifier = class(TNotifierObject, INTAEditServicesNotifier)
  private
    FOwner: TDpccEditorCompletion;
  public
    constructor Create(AOwner: TDpccEditorCompletion);
    procedure WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
    procedure WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
    procedure WindowActivated(const EditWindow: INTAEditWindow);
    procedure WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer; var Handled: Boolean);
    procedure EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
  end;

  /// <summary>Tasten des Popups über den gemeinsamen Hook; Priorität vor dem Parameter-Hint.</summary>
  TCompletionKeys = class(TDpccKeyClient)
  private
    FOwner: TDpccEditorCompletion;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  public
    constructor Create(AOwner: TDpccEditorCompletion);
  end;

function NavigationKey(AKey: Word; out ANavigation: TDpccNavigationKey): Boolean;
begin
  Result := True;
  case AKey of
    VK_UP: ANavigation := TDpccNavigationKey.Up;
    VK_DOWN: ANavigation := TDpccNavigationKey.Down;
    VK_PRIOR: ANavigation := TDpccNavigationKey.PageUp;
    VK_NEXT: ANavigation := TDpccNavigationKey.PageDown;
    VK_HOME: ANavigation := TDpccNavigationKey.First;
    VK_END: ANavigation := TDpccNavigationKey.Last;
    VK_RETURN, VK_TAB: ANavigation := TDpccNavigationKey.Accept;
    VK_ESCAPE: ANavigation := TDpccNavigationKey.Cancel;
    // Mengenmodus (#448): anhaken; sonst gehört die Leertaste dem Editor (WantsKey).
    VK_SPACE: ANavigation := TDpccNavigationKey.Toggle;
  else
    Result := False;
  end;
end;

{ TCompletionKeys }

constructor TCompletionKeys.Create(AOwner: TDpccEditorCompletion);
begin
  inherited Create(0);
  FOwner := AOwner;
end;

function TCompletionKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mNavigation: TDpccNavigationKey;
begin
  Result := ((AShift = []) and NavigationKey(AKey, mNavigation) and FOwner.WantsKey(mNavigation)) or
    FOwner.WantsCommand(AKey, AShift);
end;

procedure TCompletionKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mNavigation: TDpccNavigationKey;
begin
  try
    if FOwner.WantsCommand(AKey, AShift) then
    begin
      FOwner.HandleCommand(AKey, AShift);
    end
    else if NavigationKey(AKey, mNavigation) then
    begin
      FOwner.HandleKey(mNavigation);
    end;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Completion, E);
  end;
end;
{ TDpccEditNotifier }

constructor TDpccEditNotifier.Create(AOwner: TDpccEditorCompletion);
begin
  inherited Create;
  FOwner := AOwner;
end;

procedure TDpccEditNotifier.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
end;

procedure TDpccEditNotifier.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
end;

procedure TDpccEditNotifier.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TDpccEditNotifier.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TDpccEditNotifier.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  // Tab-Wechsel schließt (#414).
  try
    FOwner.ViewChanged;
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Completion, E);
  end;
end;

procedure TDpccEditNotifier.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
  try
    FOwner.EditorModified(EditView);
  except
    on E: Exception do
      TDpccGuard.Report(TDpccFeature.Completion, E);
  end;
end;

procedure TDpccEditNotifier.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TDpccEditNotifier.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TDpccEditNotifier.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

{ TDpccEditorCompletion }

constructor TDpccEditorCompletion.Create(const ASession: TDpccSessionFunc; const ALog: TDpccLogProc;
  const ASources: TDpccCompletionSourcesFactory);
var
  mEditor: IOTAEditorServices;
  mNotifier: INTAEditServicesNotifier;
begin
  inherited Create(ASession, ALog, ASources);
  FController.OnCommit :=
    procedure(const AItem: TDpccCompletionItem)
    begin
      Commit(AItem);
      if FController.Usage <> nil then
      begin
        TDpccIdeHistory.Committed;
      end;
    end;
  FKeys := TCompletionKeys.Create(Self);
  FTimer.OnTimer := TimerTick;
  FDelay.Timer.OnTimer := DelayTimerTick;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    mNotifier := TDpccEditNotifier.Create(Self);
    FNotifierIndex := mEditor.AddNotifier(mNotifier);
  end;
end;

destructor TDpccEditorCompletion.Destroy;
var
  mEditor: IOTAEditorServices;
begin
  // Erst abmelden, dann freigeben: Die IDE ruft sonst noch in freigegebene Objekte (#493).
  RemoveKeyHook;
  if (FNotifierIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, mEditor) then
  begin
    mEditor.RemoveNotifier(FNotifierIndex);
    FNotifierIndex := -1;
  end;
  inherited;
end;

function TDpccEditorCompletion.WantsKey(AKey: TDpccNavigationKey): Boolean;
begin
  // Liste offen: alle Navigationstasten, die Leertaste nur im Mengenmodus (#448). Leerer Zustand (#423): nur Esc.
  if AKey = TDpccNavigationKey.Toggle then
  begin
    Result := FController.Visible and FController.SetMode;
  end
  // Nur Deklarationen eines unbekannten Namens, nichts gewählt (#471): Enter gehört dem Editor.
  else if (AKey = TDpccNavigationKey.Accept) and FController.Passive then
  begin
    FController.Close;
    Result := False;
  end
  else
  begin
    Result := FController.Visible or (FController.Empty and (AKey = TDpccNavigationKey.Cancel));
  end;
end;

function TDpccEditorCompletion.WantsCommand(AKey: Word; AShift: TShiftState): Boolean;
begin
  // Strg+D Favorit (#458; bei offener Liste nie an den Editor).
  Result := FController.Visible and (AKey = Ord('D')) and (AShift = [ssCtrl]) and (FController.Favorites <> nil);
end;

procedure TDpccEditorCompletion.HandleCommand(AKey: Word; AShift: TShiftState);
begin
  if (AKey = Ord('D')) and (AShift = [ssCtrl]) then
  begin
    ToggleFavorite;
  end;
end;

procedure TDpccEditorCompletion.ToggleFavorite;
var
  mItem: TDpccCompletionItem;
  mOutcome: TDpccFavoriteToggle;
begin
  mOutcome := FController.ToggleSelectedFavorite(mItem);
  case mOutcome of
    TDpccFavoriteToggle.Added:
      begin
        TDpccIdeFavorites.Save;
        FPopup.ShowNotice(TDpccCompletionStrings.Fmt(TDpccCompletionTextId.FavoritePinned, [mItem.Name]));
      end;
    TDpccFavoriteToggle.Removed:
      begin
        TDpccIdeFavorites.Save;
        FPopup.ShowNotice(TDpccCompletionStrings.Fmt(TDpccCompletionTextId.FavoriteUnpinned, [mItem.Name]));
      end;
    // Ein sechster Favorit ersetzt keinen (#458).
    TDpccFavoriteToggle.Full:
      FPopup.ShowNotice(TDpccCompletionStrings.Fmt(TDpccCompletionTextId.FavoritesFull, [TDpccFavorites.cMaxPerType,
        TDpccFavorites.TypeNameOf(mItem)]));
  else
    if FController.Favorites <> nil then
    begin
      FPopup.ShowNotice(TDpccCompletionStrings.Text(TDpccCompletionTextId.FavoriteNotAllowed));
    end;
  end;
  ActiveChanged;
end;

function TDpccEditorCompletion.HandleKey(AKey: TDpccNavigationKey): Boolean;
begin
  Result := FController.HandleKey(AKey);
  ActiveChanged;
end;

procedure TDpccEditorCompletion.SetPending(AFromGuard, AValue: Boolean);
begin
  if AFromGuard then
  begin
    FGuard.NewLine := AValue;
  end
  else
  begin
    FCall.Opened := AValue;
  end;
end;

procedure TDpccEditorCompletion.QueueInvoke(const AView: IOTAEditView; AFromGuard: Boolean);
var
  mView: IOTAEditView;
begin
  mView := AView;
  // Nicht im Benachrichtigungsaufruf selbst, sondern gleich danach.
  TDpccMainThread.ForceQueue(TDpccFeature.Completion,
    procedure
    begin
      if (mView.Buffer <> nil) and not FController.Active then
      begin
        SetPending(AFromGuard, True);
        if not Invoke(mView, True) then
        begin
          SetPending(AFromGuard, False);
        end;
      end;
    end);
end;

procedure TDpccEditorCompletion.CheckCallOpened(const AView: IOTAEditView);
var
  mLineText: string;
  mLine, mCharacter: Integer;
begin
  mLine := AView.CursorPos.Line;
  mLineText := TDpccEditorBuffer.LineText(AView, mLine);
  mCharacter := TLspSession.ColumnToIndex(mLineText, AView.CursorPos.Col, TDpccEditorBuffer.TabWidth(AView.Buffer));
  if not TDpccParentheses.CallOpened(mLineText, mCharacter) then
  begin
    Exit;
  end;
  if (FCall.Line = mLine) and (FCall.Character = mCharacter) and SameText(FCall.FileName, AView.Buffer.FileName) then
  begin
    Exit;
  end;
  FCall.FileName := AView.Buffer.FileName;
  FCall.Line := mLine;
  FCall.Character := mCharacter;
  QueueInvoke(AView, False);
end;

function TDpccEditorCompletion.TrackTyping(const AView: IOTAEditView; out ALineText: string;
  out ACharacter: Integer): Boolean;
var
  mLine: Integer;
begin
  mLine := AView.CursorPos.Line;
  ALineText := TDpccEditorBuffer.LineText(AView, mLine);
  ACharacter := TLspSession.ColumnToIndex(ALineText, AView.CursorPos.Col, TDpccEditorBuffer.TabWidth(AView.Buffer));
  Result := FTyping.Typed(AView.Buffer.FileName, mLine, ACharacter, ALineText);
end;

procedure TDpccEditorCompletion.SeedTyping(const AView: IOTAEditView);
var
  mLineText: string;
  mCharacter: Integer;
begin
  if (AView <> nil) and (AView.Buffer <> nil) then
  begin
    TrackTyping(AView, mLineText, mCharacter);
  end;
end;

procedure TDpccEditorCompletion.CheckTyped(const AView: IOTAEditView; const ALineText: string; ACharacter: Integer);
var
  mView: IOTAEditView;
begin
  // Unter der Schwelle (oder 0 = aus) bleibt es bei der Rechnung hier: keine Anfrage an den Server.
  if TDpccAutoOpen.Action(TDpccCompletionSource.Typing, ALineText, ACharacter, FController.Active,
    TDpccIdeSettings.Current.AutoMinChars) <> TDpccAutoOpenAction.Query then
  begin
    Exit;
  end;
  if not Assigned(FOnHandles) or not FOnHandles(AView.Buffer.FileName) or PlaceholdersActive or
    (Assigned(FOnIdeListOpen) and FOnIdeListOpen()) then
  begin
    Exit;
  end;
  mView := AView;
  // Nicht im Benachrichtigungsaufruf selbst, sondern gleich danach (wie QueueInvoke).
  TDpccMainThread.ForceQueue(TDpccFeature.Completion,
    procedure
    begin
      if (mView.Buffer <> nil) and not FController.Active and
        (not Assigned(FOnEnsureSession) or FOnEnsureSession()) then
      begin
        Invoke(mView, TDpccCompletionSource.Typing);
      end;
    end);
end;

procedure TDpccEditorCompletion.TrackAutoParen(const AView: IOTAEditView);
var
  mRemoveAt: Integer;
begin
  if AView.CursorPos.Line <> FAutoParen.Line then
  begin
    FAutoParen.Stop;
    Exit;
  end;
  FAutoParen.Update(TDpccEditorBuffer.LineText(AView, FAutoParen.Line), mRemoveAt);
  if mRemoveAt >= 0 then
  begin
    SkipAutoParen(AView, mRemoveAt);
  end;
end;

function TDpccEditorCompletion.CursorPlace(const AView: IOTAEditView): TDpccCompletionPlace;
var
  mLine: Integer;
  mLineText: string;
begin
  mLine := AView.CursorPos.Line;
  mLineText := TDpccEditorBuffer.LineText(AView, mLine);
  Result := TDpccCompletionPlace.At(AView.Buffer.FileName, mLine,
    TLspSession.ColumnToIndex(mLineText, AView.CursorPos.Col, TDpccEditorBuffer.TabWidth(AView.Buffer)), mLineText);
end;

function TDpccEditorCompletion.KeyInvoke(const AView: IOTAEditView; const AIde: TDpccIdeList): Boolean;
begin
  Result := True;
  if (AView <> nil) and (AView.Buffer <> nil) and
    (FFallback.Press(CursorPlace(AView), AIde) = TDpccCompletionRoute.Ide) then
  begin
    if AIde.Open then
    begin
      Log('Vervollständigung: Strg+Leer bei offener Liste der IDE, die Taste gehört ihr');
    end
    else
    begin
      Log('Vervollständigung: zweites Strg+Leer an derselben Stelle, die Liste der IDE übernimmt');
    end;
    Close;
    Exit(False);
  end;
  Invoke(AView);
end;

procedure TDpccEditorCompletion.EditorModified(const AView: IOTAEditView);
var
  mHasBuffer, mTyped: Boolean;
  mLineText: string;
  mCharacter: Integer;
begin
  mHasBuffer := (AView <> nil) and (AView.Buffer <> nil);
  // Tippen (L5): Stand der Zeile bei jeder Änderung nachführen, auch bei offener Liste.
  mTyped := False;
  mCharacter := 0;
  if mHasBuffer then
  begin
    mTyped := TrackTyping(AView, mLineText, mCharacter);
  end;
  // Eingabe verwirft den Merker für das zweite Strg+Leertaste, sobald sich die Stelle geändert hat (L3).
  if FFallback.State <> TDpccFallbackState.Idle then
  begin
    if (AView <> nil) and (AView.Buffer <> nil) then
    begin
      FFallback.Edited(CursorPlace(AView));
    end
    else
    begin
      FFallback.Reset;
    end;
  end;
  if FController.Active then
  begin
    Recheck;
  end;
  if FPlaceholders <> nil then
  begin
    FPlaceholders.EditorModified(AView);
  end;
  // Enter am Ende der Zeile eines übernommenen Konstruktors (#489): nach dem Zeilenende anbieten.
  if not FController.Active and GuardNewLine(AView) then
  begin
    FGuard.Line := 0;
    QueueInvoke(AView, True);
  end
  else if not FController.Active and mHasBuffer then
  begin
    CheckCallOpened(AView);
    if mTyped then
    begin
      CheckTyped(AView, mLineText, mCharacter);
    end;
  end;
  if FAutoParen.Active and mHasBuffer then
  begin
    TrackAutoParen(AView);
  end;
end;

procedure TDpccEditorCompletion.TimerTick(Sender: TObject);
begin
  try
    Recheck;
  except
    on E: Exception do
    begin
      Log('Vervollständigung: ' + E.Message);
      TDpccGuard.Report(TDpccFeature.Completion, E);
      Close;
    end;
  end;
end;

function TDpccEditorCompletion.WindowLeft: Boolean;
var
  mReason: TDpccCloseReason;
begin
  mReason := TDpccCloseRules.Popup(FOpen.Opened, WindowState(FOpen.View, FOpen.Window, GetFocus));
  Result := mReason <> TDpccCloseReason.None;
  if Result then
  begin
    Log('Vervollständigung geschlossen: ' + TDpccCloseRules.Name(mReason));
    Close;
  end;
end;

procedure TDpccEditorCompletion.LeaveWord(AReason: TDpccCloseReason; const ALineText: string; AIndex,
  ACharacter: Integer);
begin
  if AReason <> TDpccCloseReason.NonIdentifier then
  begin
    Log('Vervollständigung geschlossen: ' + TDpccCloseRules.Name(AReason));
    Close;
    Exit;
  end;
  // Commit-Zeichen direkt hinter dem Wort (#429): übernehmen, das Zeichen bleibt.
  if TDpccIdeSettings.Current.CommitCharacters and (AIndex = ACharacter) and
    CharInSet(ALineText[AIndex], ['(', ';', '.']) and FController.CanCommitOnCharacter then
  begin
    FCommitChar.WordEnd := ACharacter - 1;
    FCommitChar.SuffixBytes := TEncoding.UTF8.GetByteCount(string(ALineText[AIndex]));
    try
      FController.CommitSelected;
    finally
      FCommitChar.WordEnd := -1;
    end;
    ActiveChanged;
    Exit;
  end;
  Log(Format('Vervollständigung geschlossen: Zeichen #%d getippt', [Ord(ALineText[AIndex])]));
  Close;
end;

procedure TDpccEditorCompletion.Refilter(const ALineText: string; ALine, ACharacter: Integer);
var
  mPrefix: string;
begin
  mPrefix := Copy(ALineText, FOpen.WordStart + 1, ACharacter - FOpen.WordStart);
  // Gekürzte Liste (#431) oder Wort nicht mehr Fortsetzung der Anfrage (Rücktaste, #616): lokal weiterfiltern
  // und im Hintergrund neu fragen. Sonst nur lokal; der Server wird beim Tippen nicht mehr gefragt.
  if (mPrefix <> FController.Prefix) and FController.NeedsQuery(mPrefix) then
  begin
    FController.Requery(ContextAt(FOpen.View, ALineText, ALine, ACharacter, FOpen.WordStart));
  end
  else
  begin
    FController.UpdatePrefix(mPrefix);
  end;
end;

procedure TDpccEditorCompletion.Recheck;
var
  mCursor: TOTAEditPos;
  mLineText: string;
  mCharacter, mIndex: Integer;
  mReason: TDpccCloseReason;
begin
  if not FController.Active or (FOpen.View = nil) then
  begin
    ActiveChanged;
    Exit;
  end;
  if WindowLeft then
  begin
    Exit;
  end;
  mCursor := FOpen.View.CursorPos;
  mLineText := '';
  mCharacter := 0;
  if mCursor.Line = FOpen.Line then
  begin
    mLineText := TDpccEditorBuffer.LineText(FOpen.View, mCursor.Line);
    mCharacter := TLspSession.ColumnToIndex(mLineText, mCursor.Col, TDpccEditorBuffer.TabWidth(FOpen.View.Buffer));
  end;
  // Andere Zeile, Cursor vor dem Wortanfang oder ein Zeichen, das kein Bezeichner ist: Wort verlassen.
  mReason := TDpccCloseRules.PopupWord(mCursor.Line = FOpen.Line, mLineText, FOpen.WordStart, mCharacter, mIndex);
  if mReason <> TDpccCloseReason.None then
  begin
    LeaveWord(mReason, mLineText, mIndex, mCharacter);
    Exit;
  end;
  Refilter(mLineText, mCursor.Line, mCharacter);
  ActiveChanged;
end;

end.
