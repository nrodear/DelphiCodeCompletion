unit dpcc.IDE.Hover.HelpInsightHide;

// Fenster von Help Insight der IDE zur Laufzeit verbergen (Auftrag HI1), unabhängig von der Registry: Unter Delphi 12
// erscheint das Fenster THelpInsightWindow (coreide, Inhalt von DelphiLSP) auch mit "Help Insight" = False und sogar
// über dem offenen Popup der Vervollständigung von dpcc. Die Regel (ohne IDE, getestet) steht in
// dpcc.Core.Editor.HelpInsightRule; hier wird sie ausgeführt:
//   - Ereignis-Hook: SetWinEventHook für EVENT_OBJECT_SHOW, nur für den eigenen Prozess und den Hauptthread,
//     WINEVENT_OUTOFCONTEXT. Windows ruft HelpInsightWinEvent dann im Hauptthread, sobald ein Fenster sichtbar wird;
//     der Rückruf prüft die Fensterklasse (GetClassName) und die Regel und verbirgt das Fenster mit
//     ShowWindow(SW_HIDE). Nur verbergen: kein Zerstören, keine Nachricht an das Fenster.
//   - Sicherheitsnetz (Sweep, ohne Ereignis): Beim Öffnen des Popups (PopupChanged aus
//     dpcc.IDE.Completion.EditorState), falls das Fenster schon vorher sichtbar war, und im 100-ms-Wächter des
//     Tooltips (dpcc.IDE.Hover.Editor, vor der Frage nach anderen Popups) über die obersten Fenster des Hauptthreads.
// Lebenszyklus: Start beim Anmelden (dpcc.IDE.Completion.Register, Hauptthread), Stop beim Abbau gleich nach dem
// Anhalten der Hauptthread-Queue und zur Sicherheit in der Finalisierung dieser Unit; Stop löst den Hook mit
// UnhookWinEvent, bevor Code der BPL entladen wird. Der Rückruf prüft zuerst, ob sein Hook noch der angemeldete ist,
// und lässt keine Ausnahme nach außen.
// Protokoll: Der Rückruf schreibt selbst nichts; er reiht die Zeile über TDpccMainThread.ForceQueue ein (nach dem
// laufenden Ereignis, beim Entladen verworfen). Das erste Verbergen je Sitzung steht in dpcc.log, mit eingeschaltetem
// Ablaufprotokoll (TDpccFlow, Diagnose) jedes mit Grund.

interface

type
  TDpccHelpInsightHide = class
  public
    /// <summary>Beim Anmelden, im Hauptthread: Hook setzen. Ein zweiter Aufruf ohne Stop setzt keinen zweiten.
    /// </summary>
    class procedure Start; static;
    /// <summary>Beim Abmelden und Entladen: Hook lösen, nichts mehr verbergen. Mehrfach aufrufbar.</summary>
    class procedure Stop; static;
    /// <summary>Popup der Vervollständigung von dpcc offen bzw. zu (Liste aktiv, auch während sie lädt). Beim Öffnen
    /// einmal Sweep.</summary>
    class procedure PopupChanged(AOpen: Boolean); static;
    /// <summary>Sicherheitsnetz: sichtbare Fenster von Help Insight unter den obersten Fenstern des Hauptthreads nach
    /// der Regel verbergen. Nur im Hauptthread; wirft nie.</summary>
    class procedure Sweep; static;
    /// <summary>Ist der Ereignis-Hook gesetzt?</summary>
    class function Installed: Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Editor.HelpInsightRule,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Diagnostics.Shutdown,
  dpcc.Core.Diagnostics.Flow,
  dpcc.IDE.Foundation.Settings;

var
  // Handle des Ereignis-Hooks; 0 ohne.
  gHook: THandle;
  // Zwischen Start und Stop: dpcc ist angemeldet.
  gStarted: Boolean;
  // Popup der Vervollständigung offen (PopupChanged).
  gPopupOpen: Boolean;
  // Gerade beim Verbergen: kein zweites Verbergen aus einem verschachtelten Aufruf.
  gHiding: Boolean;
  // Das erste Verbergen dieser Sitzung steht schon in dpcc.log.
  gFirstLogged: Boolean;

/// <summary>Fensterklasse von AWindow; '' ohne.</summary>
function WindowClassName(AWindow: HWND): string;
var
  mName: array[0..255] of Char;
  mLength: Integer;
begin
  Result := '';
  mLength := GetClassName(AWindow, mName, Length(mName));
  if mLength > 0 then
  begin
    SetString(Result, PChar(@mName[0]), mLength);
  end;
end;

/// <summary>Protokoll zum Verbergen, nach dem laufenden Ereignis: das erste je Sitzung in dpcc.log, mit
/// Ablaufprotokoll jedes mit Grund.</summary>
procedure NoteHidden(AReason: TDpccHelpInsightHideReason; ASweep: Boolean);
var
  mFirst: Boolean;
  mText: string;
begin
  mFirst := not gFirstLogged;
  gFirstLogged := True;
  if not mFirst and not TDpccFlow.Enabled then
  begin
    Exit;
  end;
  mText := TDpccHelpInsightRule.ReasonText(AReason);
  if ASweep then
  begin
    mText := mText + ', Nachprüfung';
  end;
  TDpccMainThread.ForceQueue(TDpccFeature.Hover,
    procedure
    var
      mFlow: Integer;
    begin
      if mFirst then
      begin
        TDpccGuard.Log('Help Insight der IDE: Fenster ' + TDpccHelpInsightRule.cWindowClass +
          ' verborgen (erstes Mal in dieser Sitzung; Grund: ' + mText + ')');
      end;
      // Ablaufprotokoll (LOG1): eine Zeile je Verbergen; aus, liefert Start 0 und Step tut nichts.
      mFlow := TDpccFlow.Start(TDpccFlowArea.Hover);
      TDpccFlow.Step(mFlow, TDpccFlowArea.Hover, 'Help-Insight-Fenster der IDE verborgen, Grund: ' + mText);
    end);
end;

/// <summary>AWindow nach der Regel verbergen; True, wenn verborgen. Nur im Hauptthread.</summary>
function TryHide(AWindow: HWND; ASweep: Boolean): Boolean;
var
  mClass: string;
  mSettings: TDpccPluginSettings;
  mReason: TDpccHelpInsightHideReason;
begin
  Result := False;
  if not gStarted or gHiding or (AWindow = 0) then
  begin
    Exit;
  end;
  // Zuerst die Klasse: Alle anderen Fenster kosten nur GetClassName, keine Einstellungen.
  mClass := WindowClassName(AWindow);
  if not TDpccHelpInsightRule.IsHelpInsightWindow(mClass) or not IsWindowVisible(AWindow) then
  begin
    Exit;
  end;
  mSettings := TDpccIdeSettings.Current;
  // Eigener Tooltip: nur, wenn er auch erscheinen kann (nicht durch die Sicherung abgeschaltet).
  mReason := TDpccHelpInsightRule.Decide(mClass, mSettings.Enabled and not TDpccShutdown.Signalled,
    mSettings.HoverTooltip and not TDpccGuard.Disabled(TDpccFeature.Hover), gPopupOpen);
  if mReason = TDpccHelpInsightHideReason.None then
  begin
    Exit;
  end;
  gHiding := True;
  try
    ShowWindow(AWindow, SW_HIDE);
  finally
    gHiding := False;
  end;
  NoteHidden(mReason, ASweep);
  Result := True;
end;

/// <summary>Rückruf von SetWinEventHook (WINEVENT_OUTOFCONTEXT, im Hauptthread). Lässt keine Ausnahme nach außen.
/// </summary>
procedure HelpInsightWinEvent(AHook: THandle; AEvent: DWORD; AWindow: HWND; AObject, AChild: Longint;
  AThread, ATime: DWORD); stdcall;
begin
  try
    // Nur das Fenster selbst (nicht Caret, Cursor oder Elemente darin) und nur über den angemeldeten Hook.
    if (gHook = 0) or (AHook <> gHook) or (AEvent <> EVENT_OBJECT_SHOW) or (AObject <> OBJID_WINDOW) or
      (AChild <> CHILDID_SELF) then
    begin
      Exit;
    end;
    TryHide(AWindow, False);
  except
    // Das Verbergen ist Beiwerk: Ein Fehler erreicht weder Windows noch die IDE.
  end;
end;

/// <summary>Rückruf von EnumThreadWindows für Sweep.</summary>
function SweepWindow(AWindow: HWND; AParam: LPARAM): BOOL; stdcall;
begin
  try
    TryHide(AWindow, True);
  except
    // Wie HelpInsightWinEvent: nie nach außen.
  end;
  Result := True;
end;

{ TDpccHelpInsightHide }

class procedure TDpccHelpInsightHide.Start;
begin
  gStarted := True;
  if gHook <> 0 then
  begin
    Exit;
  end;
  // Out-of-context-Ereignisse kommen in dem Thread an, der den Hook setzt: nur aus dem Hauptthread.
  if GetCurrentThreadId <> MainThreadID then
  begin
    TDpccGuard.Log('Help Insight der IDE: Ereignis-Hook nicht gesetzt (nicht im Hauptthread); nur Nachprüfung');
    Exit;
  end;
  gHook := SetWinEventHook(EVENT_OBJECT_SHOW, EVENT_OBJECT_SHOW, 0, HelpInsightWinEvent, GetCurrentProcessId,
    MainThreadID, WINEVENT_OUTOFCONTEXT);
  if gHook = 0 then
  begin
    TDpccGuard.Log('Help Insight der IDE: Ereignis-Hook nicht möglich (' + SysErrorMessage(GetLastError) +
      '); nur Nachprüfung beim Öffnen des Popups und im Wächter des Tooltips');
  end;
end;

class procedure TDpccHelpInsightHide.Stop;
var
  mHook: THandle;
begin
  gStarted := False;
  gPopupOpen := False;
  mHook := gHook;
  // Erst vergessen, dann lösen: Ein Rückruf, der noch ankäme, findet keinen angemeldeten Hook mehr.
  gHook := 0;
  if mHook <> 0 then
  begin
    UnhookWinEvent(mHook);
  end;
end;

class procedure TDpccHelpInsightHide.PopupChanged(AOpen: Boolean);
var
  mWasOpen: Boolean;
begin
  mWasOpen := gPopupOpen;
  gPopupOpen := AOpen;
  // War das Fenster schon sichtbar, bevor das Popup aufging, kommt kein neues Ereignis: einmal nachsehen.
  if AOpen and not mWasOpen then
  begin
    Sweep;
  end;
end;

class procedure TDpccHelpInsightHide.Sweep;
begin
  if not gStarted then
  begin
    Exit;
  end;
  try
    EnumThreadWindows(MainThreadID, @SweepWindow, 0);
  except
    // Nie nach außen; SweepWindow fängt seine Fehler selbst.
  end;
end;

class function TDpccHelpInsightHide.Installed: Boolean;
begin
  Result := gHook <> 0;
end;

initialization

finalization
  // Sicherheitsnetz, falls Stop beim Abmelden nicht lief: kein Hook überlebt das Package.
  TDpccHelpInsightHide.Stop;

end.
