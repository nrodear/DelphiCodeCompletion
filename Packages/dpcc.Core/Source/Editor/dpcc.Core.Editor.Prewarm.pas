unit dpcc.Core.Editor.Prewarm;

// Vorladen beim Öffnen und Aktivieren einer Datei (dpcc/prewarm), ohne VCL und Open Tools API: entscheidet, wann
// und für welchen Dokumentstand die IDE-Seite abgleicht und dem Server dpcc/prewarm schickt.
// - Ruhe: Eine Aktivierung (Öffnen, Tab-Wechsel, Sprung in eine andere Datei) wartet cQuietMs ab. Jede weitere
//   Aktivierung in der Zeit beginnt die Ruhe neu und ersetzt die Datei; schnelles Durchblättern der Tabs löst so
//   nichts aus, nur die Datei, bei der der Benutzer bleibt.
// - Je Datei und Dokumentstand (Version des gemeinsamen Pufferstands, TDpccEditorSnapshot.Version) höchstens einmal;
//   eine andere Sitzung beginnt von vorn.
// - Die Uhr ist einstellbar (Tests); ohne sie gilt TThread.GetTickCount64.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TDpccPrewarmGate = class
  public const
    /// <summary>Ruhe nach der letzten Aktivierung, bevor vorgeladen wird.</summary>
    cQuietMs = 400;
  private
    FClock: TFunc<UInt64>;
    FQuietMs: Cardinal;
    /// <summary>Datei der letzten Aktivierung; '' = keine wartet.</summary>
    FPending: string;
    FActivatedAt: UInt64;
    /// <summary>Sitzung, für die FDone gilt; nur verglichen, nie benutzt.</summary>
    FSession: Pointer;
    /// <summary>Datei (groß) → vorgeladener Dokumentstand.</summary>
    FDone: TDictionary<string, Cardinal>;
    /// <summary>Stand der Uhr in Millisekunden.</summary>
    function Ticks: UInt64;
  public
    /// <summary>AClock: Uhr in Millisekunden (nil = TThread.GetTickCount64); AQuietMs: Ruhe vor dem Vorladen.
    /// </summary>
    constructor Create(const AClock: TFunc<UInt64>; AQuietMs: Cardinal); overload;
    /// <summary>Wie oben mit TThread.GetTickCount64 und cQuietMs.</summary>
    constructor Create; overload;
    destructor Destroy; override;
    /// <summary>Eine Ansicht von AFileName wurde aktiv: Die Ruhe beginnt neu, eine wartende Datei entfällt. ''
    /// verwirft nur die wartende (wie Cancel).</summary>
    procedure Activated(const AFileName: string);
    /// <summary>Wartende Aktivierung verwerfen (andere Datei vorn, die dpcc nicht bedient).</summary>
    procedure Cancel;
    /// <summary>Wartet eine Aktivierung auf das Ende der Ruhe?</summary>
    function Pending: Boolean;
    /// <summary>Millisekunden bis zum Ende der Ruhe; 0, wenn sie vorbei ist oder nichts wartet. Läuft die Uhr
    /// zurück, beginnt die Ruhe von vorn.</summary>
    function WaitMs: Cardinal;
    /// <summary>Ruhe vorbei: True mit der Datei der letzten Aktivierung, die damit nicht mehr wartet.</summary>
    function TakeDue(out AFileName: string): Boolean;
    /// <summary>Soll AFileName mit dem Dokumentstand AVersion in der Sitzung ASession vorgeladen werden? True merkt
    /// sich den Stand (danach False für denselben); eine andere Sitzung vergisst alle gemerkten Stände.</summary>
    function Claim(const AFileName: string; AVersion: Cardinal; ASession: Pointer): Boolean;
    /// <summary>Gemerkten Stand von AFileName vergessen: Das nächste Claim gilt wieder (Sitzung kennt die Datei
    /// nicht mehr, Senden nicht möglich).</summary>
    procedure Forget(const AFileName: string);
    /// <summary>Alles vergessen (Hauptschalter aus, Sitzung gestoppt).</summary>
    procedure Reset;
    property QuietMs: Cardinal read FQuietMs;
  end;

implementation

uses
  System.Classes;

{ TDpccPrewarmGate }

constructor TDpccPrewarmGate.Create(const AClock: TFunc<UInt64>; AQuietMs: Cardinal);
begin
  inherited Create;
  FClock := AClock;
  FQuietMs := AQuietMs;
  FDone := TDictionary<string, Cardinal>.Create;
end;

constructor TDpccPrewarmGate.Create;
begin
  Create(nil, cQuietMs);
end;

destructor TDpccPrewarmGate.Destroy;
begin
  FDone.Free;
  inherited;
end;

function TDpccPrewarmGate.Ticks: UInt64;
begin
  if Assigned(FClock) then
  begin
    Result := FClock();
  end
  else
  begin
    // 64-Bit-Zähler wie TDpccTicks: läuft nicht über.
    Result := TThread.GetTickCount64;
  end;
end;

procedure TDpccPrewarmGate.Activated(const AFileName: string);
begin
  if AFileName = '' then
  begin
    Cancel;
    Exit;
  end;
  FPending := AFileName;
  FActivatedAt := Ticks;
end;

procedure TDpccPrewarmGate.Cancel;
begin
  FPending := '';
end;

function TDpccPrewarmGate.Pending: Boolean;
begin
  Result := FPending <> '';
end;

function TDpccPrewarmGate.WaitMs: Cardinal;
var
  mNow, mElapsed: UInt64;
begin
  if FPending = '' then
  begin
    Exit(0);
  end;
  mNow := Ticks;
  // Uhr zurückgesetzt (etwa im Test): die Ruhe von vorn, lieber einmal zu spät als beim Durchblättern.
  if mNow < FActivatedAt then
  begin
    FActivatedAt := mNow;
  end;
  mElapsed := mNow - FActivatedAt;
  if mElapsed >= FQuietMs then
  begin
    Exit(0);
  end;
  Result := FQuietMs - Cardinal(mElapsed);
end;

function TDpccPrewarmGate.TakeDue(out AFileName: string): Boolean;
begin
  AFileName := '';
  Result := (FPending <> '') and (WaitMs = 0);
  if Result then
  begin
    AFileName := FPending;
    FPending := '';
  end;
end;

function TDpccPrewarmGate.Claim(const AFileName: string; AVersion: Cardinal; ASession: Pointer): Boolean;
var
  mKey: string;
  mVersion: Cardinal;
begin
  if ASession <> FSession then
  begin
    FDone.Clear;
    FSession := ASession;
  end;
  mKey := AnsiUpperCase(AFileName);
  if FDone.TryGetValue(mKey, mVersion) and (mVersion = AVersion) then
  begin
    Exit(False);
  end;
  FDone.AddOrSetValue(mKey, AVersion);
  Result := True;
end;

procedure TDpccPrewarmGate.Forget(const AFileName: string);
begin
  FDone.Remove(AnsiUpperCase(AFileName));
end;

procedure TDpccPrewarmGate.Reset;
begin
  FPending := '';
  FDone.Clear;
  FSession := nil;
end;

end.
