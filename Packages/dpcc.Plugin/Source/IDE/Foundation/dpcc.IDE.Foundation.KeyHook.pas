unit dpcc.IDE.Foundation.KeyHook;

// Tastatur-Hook des Hauptthreads für die Fenster von dpcc (#410, #436). Er ist
// nur installiert, solange mindestens ein Fenster offen ist und Tasten braucht;
// sonst berührt dpcc keine Taste. Keine Tastaturbindung der IDE: Eine Bindung für
// Pfeile, Enter, Tab, Pos1, Ende oder Esc nimmt sie dem Editor auch bei
// geschlossenem Fenster weg, weil er sie ohne eigenen Handler verarbeitet.
// Die Clients werden nach Priorität gefragt (kleiner zuerst): Esc schließt zuerst
// die Vervollständigung, dann den Parameter-Hint. Gewollte Tasten erreichen den
// Editor nicht (Drücken und Loslassen) und werden per ForceQueue nach der
// Nachrichtenverarbeitung ausgeführt, nicht im Hook.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes;

type
  TDpccKeyClient = class abstract
  private
    FPriority: Integer;
  protected
    /// <summary>Gehört die Taste gerade diesem Fenster? Im Hook gefragt: schnell, ohne Seiteneffekte.</summary>
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; virtual; abstract;
    /// <summary>Führt die Taste aus; im Hauptthread nach der Nachrichtenverarbeitung.</summary>
    procedure HandleKey(AKey: Word; AShift: TShiftState); virtual; abstract;
  public
    constructor Create(APriority: Integer);
    property Priority: Integer read FPriority;
  end;

  TDpccKeyHook = class
  public
    /// <summary>Meldet AClient an; installiert den Hook beim ersten Client.</summary>
    class procedure Add(AClient: TDpccKeyClient); static;
    /// <summary>Meldet AClient ab; entfernt den Hook beim letzten. Vor dem Freigeben aufrufen.</summary>
    class procedure Remove(AClient: TDpccKeyClient); static;
    class function Contains(AClient: TDpccKeyClient): Boolean; static;
    class function Installed: Boolean; static;
  end;

implementation

uses
  dpcc.Core.Diagnostics.MainThread,
  dpcc.Core.Diagnostics.Guard,
  System.Generics.Collections;

var
  Clients: TList<TDpccKeyClient> = nil;
  Hook: HHOOK = 0;

{ TDpccKeyClient }

constructor TDpccKeyClient.Create(APriority: Integer);
begin
  inherited Create;
  FPriority := APriority;
end;

function CurrentShift: TShiftState;
begin
  Result := [];
  if GetKeyState(VK_SHIFT) < 0 then
  begin
    Include(Result, ssShift);
  end;
  if GetKeyState(VK_CONTROL) < 0 then
  begin
    Include(Result, ssCtrl);
  end;
  if GetKeyState(VK_MENU) < 0 then
  begin
    Include(Result, ssAlt);
  end;
end;

/// <summary>Erster angemeldeter Client, der die Taste will.</summary>
function ClientFor(AKey: Word; AShift: TShiftState; out AClient: TDpccKeyClient): Boolean;
var
  mClient: TDpccKeyClient;
begin
  Result := False;
  AClient := nil;
  if (Clients = nil) or (Clients.Count = 0) then
  begin
    Exit;
  end;
  for mClient in Clients.ToArray do
  begin
    if mClient.WantsKey(AKey, AShift) then
    begin
      AClient := mClient;
      Exit(True);
    end;
  end;
end;

/// <summary>Taste im Hauptthread ausführen, solange der Client noch angemeldet ist.</summary>
procedure QueueKey(AClient: TDpccKeyClient; AKey: Word; AShift: TShiftState);
begin
  TDpccMainThread.ForceQueue(TDpccFeature.EditorCommands,
    procedure
    begin
      try
        if TDpccKeyHook.Contains(AClient) then
        begin
          AClient.HandleKey(AKey, AShift);
        end;
      except
        // Die Clients melden ihre Fehler selbst; hier nur das letzte Netz (#493).
        on E: Exception do
          TDpccGuard.Log('Tastatur: ' + TDpccGuard.ErrorText(E));
      end;
    end);
end;

function KeyboardProc(ACode: Integer; AWParam: WPARAM; ALParam: LPARAM): LRESULT; stdcall;
var
  mClient: TDpccKeyClient;
  mShift: TShiftState;
begin
  try
    mShift := CurrentShift;
    if (ACode = HC_ACTION) and ClientFor(Word(AWParam), mShift, mClient) then
    begin
      // Gedrückt (auch Wiederholung): ausführen; losgelassen nur schlucken.
      if (ALParam and $80000000) = 0 then
      begin
        QueueKey(mClient, Word(AWParam), mShift);
      end;
      Exit(1);
    end;
  except
    // Keine Exception an die IDE (#493); die Taste geht dann an den Editor.
    on E: Exception do
      TDpccGuard.Log('Tastatur-Hook: ' + TDpccGuard.ErrorText(E));
  end;
  Result := CallNextHookEx(Hook, ACode, AWParam, ALParam);
end;

{ TDpccKeyHook }

class procedure TDpccKeyHook.Add(AClient: TDpccKeyClient);
var
  mIndex: Integer;
begin
  if Clients = nil then
  begin
    Clients := TList<TDpccKeyClient>.Create;
  end;
  if Clients.Contains(AClient) then
  begin
    Exit;
  end;
  mIndex := 0;
  while (mIndex < Clients.Count) and (Clients[mIndex].Priority <= AClient.Priority) do
  begin
    Inc(mIndex);
  end;
  Clients.Insert(mIndex, AClient);
  if Hook = 0 then
  begin
    Hook := SetWindowsHookEx(WH_KEYBOARD, @KeyboardProc, 0, GetCurrentThreadId);
  end;
end;

class procedure TDpccKeyHook.Remove(AClient: TDpccKeyClient);
begin
  if Clients = nil then
  begin
    Exit;
  end;
  Clients.Remove(AClient);
  if (Clients.Count = 0) and (Hook <> 0) then
  begin
    UnhookWindowsHookEx(Hook);
    Hook := 0;
  end;
end;

class function TDpccKeyHook.Contains(AClient: TDpccKeyClient): Boolean;
begin
  Result := (Clients <> nil) and Clients.Contains(AClient);
end;

class function TDpccKeyHook.Installed: Boolean;
begin
  Result := Hook <> 0;
end;

initialization

finalization
  if Hook <> 0 then
  begin
    UnhookWindowsHookEx(Hook);
  end;
  Hook := 0;
  FreeAndNil(Clients);

end.
