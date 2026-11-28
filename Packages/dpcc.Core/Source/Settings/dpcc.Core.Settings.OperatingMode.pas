unit dpcc.Core.Settings.OperatingMode;

// Betriebsart von dpcc je Delphi-Version (Stufe 2 von dpcc.LspServer.exe), ohne VCL und ohne Registry:
//   - Aus: Die IDE arbeitet mit ihrem eigenen Code-Insight-Anbieter (Vorgabe DelphiLSP); dpcc greift nicht ein.
//   - Plugin: dpcc ist der Code-Insight-Anbieter (dpcc.CodeInsight) mit dem eingebauten Server und eigenen Fenstern
//     (früher „Hauptschalter an“).
//   - Server: Die IDE bleibt im LSP-Betrieb (Anbieter Borland.CodeInsight.LSP.Pascal); das Plugin lenkt den Start von
//     DelphiLSP.exe auf dpcc.LspServer.exe um. Eingebauter Server und dpcc-Fenster sind aus.
// Zur Laufzeit gilt genau eine der drei; eingebauter Server und dpcc.LspServer.exe arbeiten nie gleichzeitig.
// Ablage: unter HKCU\Software\dpcc\IdePlugin je Version ein Text "OperatingMode <Version>" (z. B. "OperatingMode 37.0"
// = 'server'). Gibt es ihn für eine Version noch nicht, gilt der frühere, für alle Versionen gemeinsame DWORD Enabled:
// 0 → Aus, sonst Plugin; fehlt auch er, die Vorgabe Plugin. Die IDE-Schicht schreibt den überführten Wert sofort unter
// dem Namen der Version; Enabled bleibt danach unverändert liegen (dpcc schreibt ihn nicht mehr).

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Betriebsart von dpcc in einer Delphi-Version (siehe Kopf der Unit).</summary>
  TDpccOperatingMode = (Off, Plugin, Server);

  TDpccOperatingModes = class
  public const
    /// <summary>Vorgabe nach der Installation.</summary>
    cDefault = TDpccOperatingMode.Plugin;
    /// <summary>Anfang des Registry-Namens; dahinter ein Leerzeichen und die Version.</summary>
    cValuePrefix = 'OperatingMode';
    /// <summary>Früherer Hauptschalter (DWORD, alle Versionen gemeinsam), nur noch Quelle der Überführung.</summary>
    cLegacyName = 'Enabled';
  public
    /// <summary>Kennung in der Registry: 'off' | 'plugin' | 'server'.</summary>
    class function IdOf(AMode: TDpccOperatingMode): string; static;
    /// <summary>Kennung ohne Groß-/Kleinschreibung und Leerraum; False bei Unbekanntem.</summary>
    class function TryFromId(const AId: string; out AMode: TDpccOperatingMode): Boolean; static;
    /// <summary>Registry-Name für AVersion ("OperatingMode 37.0"); ohne Version nur "OperatingMode".</summary>
    class function ValueName(const AVersion: string): string; static;
    /// <summary>Überführung des alten Enabled: ohne Wert die Vorgabe, 0 → Aus, sonst Plugin.</summary>
    class function FromLegacy(ALegacyExists: Boolean; ALegacyValue: Integer): TDpccOperatingMode; static;
    /// <summary>Gilt der gespeicherte Text (AStoredExists, AStored)? Sonst die Überführung aus Enabled
    /// (AFromLegacy = True).</summary>
    class function Resolve(AStoredExists: Boolean; const AStored: string; ALegacyExists: Boolean;
      ALegacyValue: Integer; out AFromLegacy: Boolean): TDpccOperatingMode; static;
    /// <summary>Name fürs Protokoll (nie übersetzt): Aus, Plugin, Server.</summary>
    class function LogName(AMode: TDpccOperatingMode): string; static;
    /// <summary>Protokollzeile (nie übersetzt), wenn die IDE-Schicht die Betriebsart ohne eigenen Wert für AScope
    /// (Version, bei eigenem Profil mit Profil) festschreibt: aus dem früheren Enabled oder, wenn es auch das nicht
    /// gab (AFromDefault), die Vorgabe nach der Installation.</summary>
    class function TakeOverLogLine(const AScope: string; AMode: TDpccOperatingMode; AFromDefault: Boolean): string;
      static;
  end;

implementation

uses
  System.SysUtils;

const
  cIds: array[TDpccOperatingMode] of string = ('off', 'plugin', 'server');
  cLogNames: array[TDpccOperatingMode] of string = ('Aus', 'Plugin', 'Server');

class function TDpccOperatingModes.IdOf(AMode: TDpccOperatingMode): string;
begin
  Result := cIds[AMode];
end;

class function TDpccOperatingModes.TryFromId(const AId: string; out AMode: TDpccOperatingMode): Boolean;
var
  mMode: TDpccOperatingMode;
begin
  for mMode := Low(TDpccOperatingMode) to High(TDpccOperatingMode) do
  begin
    if SameText(Trim(AId), cIds[mMode]) then
    begin
      AMode := mMode;
      Exit(True);
    end;
  end;
  AMode := cDefault;
  Result := False;
end;

class function TDpccOperatingModes.ValueName(const AVersion: string): string;
begin
  Result := cValuePrefix;
  if Trim(AVersion) <> '' then
  begin
    Result := Result + ' ' + Trim(AVersion);
  end;
end;

class function TDpccOperatingModes.FromLegacy(ALegacyExists: Boolean; ALegacyValue: Integer): TDpccOperatingMode;
begin
  if not ALegacyExists then
  begin
    Result := cDefault;
  end
  else if ALegacyValue = 0 then
  begin
    Result := TDpccOperatingMode.Off;
  end
  else
  begin
    Result := TDpccOperatingMode.Plugin;
  end;
end;

class function TDpccOperatingModes.Resolve(AStoredExists: Boolean; const AStored: string; ALegacyExists: Boolean;
  ALegacyValue: Integer; out AFromLegacy: Boolean): TDpccOperatingMode;
begin
  if AStoredExists and TryFromId(AStored, Result) then
  begin
    AFromLegacy := False;
    Exit;
  end;
  // Kein eigener (oder ein unlesbarer) Wert dieser Version: der frühere gemeinsame Hauptschalter.
  AFromLegacy := True;
  Result := FromLegacy(ALegacyExists, ALegacyValue);
end;

class function TDpccOperatingModes.LogName(AMode: TDpccOperatingMode): string;
begin
  Result := cLogNames[AMode];
end;

class function TDpccOperatingModes.TakeOverLogLine(const AScope: string; AMode: TDpccOperatingMode;
  AFromDefault: Boolean): string;
begin
  if AFromDefault then
  begin
    // Weder eigener Wert noch früheres Enabled: kein „übernommen“, sondern die Vorgabe.
    Result := Format('Betriebsart für Delphi %s: kein gespeicherter Wert und kein früherer Hauptschalter, Vorgabe %s',
      [AScope, LogName(AMode)]);
  end
  else
  begin
    Result := Format('Betriebsart für Delphi %s aus dem früheren Hauptschalter übernommen: %s', [AScope,
      LogName(AMode)]);
  end;
end;

end.
