unit dpcc.Core.Notifications.Sources;

// Quellen der Benachrichtigungszentrale (#601) und die Einstellung
// notifications.sources, ohne VCL: bekannte Kennungen in fester Reihenfolge
// (für Optionsseite und Filter) und die Liste „Quelle=Verhalten“ als Text,
// z. B. "shortcutTips=collect, server=off". Show ist die Vorgabe und steht nie
// in der Liste; unbekannte Quellen bleiben erhalten (künftige Hinweise),
// unbekannte Verhalten werden übergangen.

interface

uses
  System.SysUtils,
  dpcc.Core.Notifications.Contract;

type
  /// <summary>Verhalten einer Quelle aus notifications.sources.</summary>
  TDpccNotificationSourceMode = record
    Source: string;
    Mode: TDpccNotificationMode;
  end;

  TDpccNotificationSources = class
  public const
    /// <summary>Build fertig (#535): Ergebnis eines Builds des Benutzers.</summary>
    cBuild = 'build';
    /// <summary>Extern geänderte Dateien neu geladen (#536).</summary>
    cReload = 'reload';
    /// <summary>Server neu gestartet (#393) und Meldungen des Servers.</summary>
    cServer = 'server';
    /// <summary>Tastenkürzel-Tipps (#600).</summary>
    cShortcutTips = 'shortcutTips';
    /// <summary>Compilerprüfung im Hintergrund (#548).</summary>
    cCheck = 'check';
    /// <summary>Build-Server (#763): Build auf dem Server ist rot geworden.</summary>
    cBuildServer = 'buildServer';
    /// <summary>Bauen beim Öffnen eines Projekts (build.onOpen): Ergebnis des Laufs.</summary>
    cOpenBuild = 'openBuild';
    /// <summary>Ausblenden direkt am Element (#628): „Ausgeblendet · Rückgängig“.</summary>
    cHidden = 'hidden';
    /// <summary>uses nachziehen nach dem Umbenennen einer Unit (#512).</summary>
    cUnitRename = 'unitRename';
    /// <summary>Minimap (#873): Hinweis, wenn auch die Minimap der IDE sichtbar ist.</summary>
    cMinimap = 'minimap';
    /// <summary>„Issue anlegen …“ (#1268): Kennung des neuen Issues mit „Im Browser öffnen“. Wie Minimap nicht in
    /// Known (Meldung auf eine Aktion des Benutzers hin).</summary>
    cNewIssue = 'newIssue';
    /// <summary>Änderungen an meinen Issues im Issue-Tracker (#1271).</summary>
    cIssues = 'issues';
    /// <summary>Modulschalter (#1454): dpcc.json legt Prüfregeln fest, das Modul Prüfregeln ist aus. Wie Minimap
    /// nicht in Known (einmal je dpcc.json und Sitzung).</summary>
    cRuleChecks = 'ruleChecks';
    /// <summary>Absturzsicherung (#493): eine Funktion wurde nach wiederholten Fehlern abgeschaltet. Nicht in Known:
    /// Dieser Hinweis lässt sich nicht abstellen, sonst fiele eine abgeschaltete Funktion wieder nicht auf.</summary>
    cFuse = 'fuse';
    /// <summary>dpcc-Module fehlen unter „Known Packages“ der IDE (Meldung vom 05.11.2026). Nicht in Known: Der
    /// Hinweis lässt sich nicht abstellen, sonst fiele ein nicht geladenes Modul nicht auf.</summary>
    cPackages = 'packages';
    /// <summary>Kein Kommandozeilen-Compiler (#1822): einmal überhaupt, gemerkt in ui.editionNoticeShown. Nicht in
    /// Known.</summary>
    cEdition = 'edition';
  public
    /// <summary>Bekannte Quellen in fester Reihenfolge (Optionsseite, Filter).</summary>
    class function Known: TArray<string>; static;
    /// <summary>"show", "collect" bzw. "off".</summary>
    class function ModeName(AMode: TDpccNotificationMode): string; static;
    /// <summary>Verhalten aus seinem Namen (ohne Groß-/Kleinschreibung); False bei unbekanntem Namen.</summary>
    class function TryMode(const AName: string; out AMode: TDpccNotificationMode): Boolean; static;
    /// <summary>Paare aus "quelle=verhalten", getrennt durch Komma, Semikolon oder Zeilenumbruch; Leerraum egal.
    /// Spätere Angaben derselben Quelle gewinnen; Einträge ohne Quelle oder mit unbekanntem Verhalten fallen weg.
    /// </summary>
    class function Parse(const ASpec: string): TArray<TDpccNotificationSourceMode>; static;
    /// <summary>Text für die Einstellung: "quelle=verhalten" mit ", " getrennt, ohne Show.</summary>
    class function ToText(const AModes: TArray<TDpccNotificationSourceMode>): string; static;
    /// <summary>Verhalten von ASource in ASpec; Show ohne Angabe.</summary>
    class function ModeIn(const ASpec, ASource: string): TDpccNotificationMode; static;
    /// <summary>ASpec mit AMode für ASource; die übrigen Angaben bleiben in ihrer Reihenfolge.</summary>
    class function WithMode(const ASpec, ASource: string; AMode: TDpccNotificationMode): string; static;
    /// <summary>Normalisierte Fassung von ASpec (Parse, dann ToText).</summary>
    class function Normalize(const ASpec: string): string; static;
  end;

implementation

{ TDpccNotificationSources }

class function TDpccNotificationSources.Known: TArray<string>;
begin
  Result := [cBuild, cCheck, cReload, cServer, cShortcutTips, cBuildServer, cOpenBuild, cHidden, cUnitRename, cIssues];
end;

class function TDpccNotificationSources.ModeName(AMode: TDpccNotificationMode): string;
begin
  case AMode of
    TDpccNotificationMode.Collect:
      Result := 'collect';
    TDpccNotificationMode.Off:
      Result := 'off';
  else
    Result := 'show';
  end;
end;

class function TDpccNotificationSources.TryMode(const AName: string; out AMode: TDpccNotificationMode): Boolean;
var
  mName: string;
begin
  mName := LowerCase(Trim(AName));
  Result := True;
  if mName = 'collect' then
  begin
    AMode := TDpccNotificationMode.Collect;
  end
  else if mName = 'off' then
  begin
    AMode := TDpccNotificationMode.Off;
  end
  else
  begin
    AMode := TDpccNotificationMode.Show;
    Result := mName = 'show';
  end;
end;

class function TDpccNotificationSources.Parse(const ASpec: string): TArray<TDpccNotificationSourceMode>;
var
  mParts: TArray<string>;
  mPart, mSource: string;
  mEquals, mIndex, mFound: Integer;
  mMode: TDpccNotificationMode;
  mEntry: TDpccNotificationSourceMode;
begin
  Result := nil;
  mParts := ASpec.Split([',', ';', #13, #10]);
  for mPart in mParts do
  begin
    mEquals := Pos('=', mPart);
    if mEquals <= 0 then
    begin
      Continue;
    end;
    mSource := Trim(Copy(mPart, 1, mEquals - 1));
    if (mSource = '') or not TryMode(Copy(mPart, mEquals + 1, MaxInt), mMode) then
    begin
      Continue;
    end;
    mFound := -1;
    for mIndex := 0 to High(Result) do
    begin
      if SameText(Result[mIndex].Source, mSource) then
      begin
        mFound := mIndex;
      end;
    end;
    if mFound >= 0 then
    begin
      Result[mFound].Mode := mMode;
      Continue;
    end;
    mEntry.Source := mSource;
    mEntry.Mode := mMode;
    Result := Result + [mEntry];
  end;
end;

class function TDpccNotificationSources.ToText(const AModes: TArray<TDpccNotificationSourceMode>): string;
var
  mEntry: TDpccNotificationSourceMode;
begin
  Result := '';
  for mEntry in AModes do
  begin
    if (mEntry.Mode = TDpccNotificationMode.Show) or (Trim(mEntry.Source) = '') then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + Trim(mEntry.Source) + '=' + ModeName(mEntry.Mode);
  end;
end;

class function TDpccNotificationSources.ModeIn(const ASpec, ASource: string): TDpccNotificationMode;
var
  mEntry: TDpccNotificationSourceMode;
begin
  Result := TDpccNotificationMode.Show;
  for mEntry in Parse(ASpec) do
  begin
    if SameText(mEntry.Source, ASource) then
    begin
      Result := mEntry.Mode;
    end;
  end;
end;

class function TDpccNotificationSources.WithMode(const ASpec, ASource: string;
  AMode: TDpccNotificationMode): string;
var
  mModes: TArray<TDpccNotificationSourceMode>;
  mIndex: Integer;
  mFound: Boolean;
  mEntry: TDpccNotificationSourceMode;
begin
  mModes := Parse(ASpec);
  mFound := False;
  for mIndex := 0 to High(mModes) do
  begin
    if SameText(mModes[mIndex].Source, ASource) then
    begin
      mModes[mIndex].Mode := AMode;
      mFound := True;
    end;
  end;
  if not mFound and (Trim(ASource) <> '') then
  begin
    mEntry.Source := Trim(ASource);
    mEntry.Mode := AMode;
    mModes := mModes + [mEntry];
  end;
  Result := ToText(mModes);
end;

class function TDpccNotificationSources.Normalize(const ASpec: string): string;
begin
  Result := ToText(Parse(ASpec));
end;

end.
