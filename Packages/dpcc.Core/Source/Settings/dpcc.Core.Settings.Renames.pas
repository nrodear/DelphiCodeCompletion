unit dpcc.Core.Settings.Renames;

// Umbenannte Plugin-Einstellungen übernehmen (#1280), ohne VCL und ohne
// Registry. Grundlage ist x-renamedFrom im Plugin-Katalog: frühere Namen in
// TDpccPluginSettings.Load/Save (Registry), unter denen derselbe Wert
// unverändert gespeichert war. Anders als x-formerKeys, das auch umgerechnete
// Werte meint (hints.xmlDocFull → hints.xmlDocExpand) und nur der Import
// auswertet, darf hier ohne Sondercode kopiert werden. Je früherem Namen mit
// Wert:
// - neuer Name ohne Wert: Wert übernehmen, alten entfernen (Übernommen);
// - neuer Name mit Wert: der neue gilt, der alte wird entfernt (Verworfen);
// - Wert der falschen Art (Text statt Zahl o. ä.): alten entfernen (Ungültig).
// Danach steht kein früherer Name mehr in der Ablage, ein zweiter Start findet
// nichts. Die Ergebnisse protokolliert der Aufrufer, eine Zeile je Übernahme.

interface

uses
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.Catalog;

type
  TDpccSettingsRenameOutcome = (srMoved, srSuperseded, srInvalid);

  TDpccSettingsRename = record
    /// <summary>Früherer Name in der Ablage (x-renamedFrom).</summary>
    OldName: string;
    /// <summary>Früherer Schlüssel für das Protokoll: erster Eintrag von x-formerKeys, sonst OldName.</summary>
    OldKey: string;
    /// <summary>Name in TDpccPluginSettings.Load/Save.</summary>
    NewName: string;
    /// <summary>Schlüssel (x-key) der Einstellung.</summary>
    NewKey: string;
    Outcome: TDpccSettingsRenameOutcome;
    /// <summary>Eine Zeile für das Protokoll, z. B. „Einstellung welcomePage.issues.query heißt jetzt
    /// issues.query“.</summary>
    function LogLine: string;
  end;

  TDpccSettingsRenames = class
  public
    /// <summary>Frühere Namen aller Plugin-Einträge in ACatalog nach x-renamedFrom übernehmen: AStore liest und
    /// schreibt die Werte, ANames prüft und entfernt die Namen (meist dasselbe Objekt). Liefert je gefundenem
    /// früheren Namen ein Ergebnis; leer, wenn nichts zu tun war.</summary>
    class function Apply(const AStore: IDpccSettingsStore; const ANames: IDpccSettingsNames;
      ACatalog: TDpccSettingsCatalog): TArray<TDpccSettingsRename>; static;
  end;

implementation

uses
  System.SysUtils;

// Wert unter AName in der Art von AKind lesen; False, wenn dort ein Wert anderer Art steht. Zwei Lesungen mit
// verschiedener Vorgabe unterscheiden „Wert gleich Vorgabe“ von „Wert nicht lesbar“.
function ReadValue(const AStore: IDpccSettingsStore; AKind: TDpccSettingKind; const AName: string;
  out ANumber: Integer; out AText: string): Boolean;
begin
  ANumber := 0;
  AText := '';
  if AKind in [akBoolean, akInteger] then
  begin
    ANumber := AStore.ReadInteger(AName, 0);
    Result := (ANumber <> 0) or (AStore.ReadInteger(AName, 1) = 0);
  end
  else
  begin
    AText := AStore.ReadString(AName, '');
    Result := (AText <> '') or (AStore.ReadString(AName, #1) = '');
  end;
end;

{ TDpccSettingsRename }

function TDpccSettingsRename.LogLine: string;
begin
  case Outcome of
    srMoved:
      Result := Format('Einstellung %s heißt jetzt %s; Wert übernommen', [OldKey, NewKey]);
    srSuperseded:
      Result := Format('Warnung: Einstellung %s stand zusätzlich unter dem früheren Namen %s; ' +
        'es gilt der neue Wert, der alte wurde entfernt', [NewKey, OldKey]);
  else
    Result := Format('Warnung: Einstellung %s (früher %s) hatte einen Wert der falschen Art; er wurde entfernt',
      [NewKey, OldKey]);
  end;
end;

/// <summary>Wert von AFormer unter dem neuen Namen speichern; False bei einem Wert der falschen Art.</summary>
function MoveValue(const AStore: IDpccSettingsStore; const AEntry: TDpccCatalogEntry;
  const AFormer: string): Boolean;
var
  mNumber: Integer;
  mText: string;
begin
  Result := ReadValue(AStore, AEntry.Kind, AFormer, mNumber, mText);
  if not Result then
  begin
    Exit;
  end;
  if AEntry.Kind in [akBoolean, akInteger] then
  begin
    AStore.WriteInteger(AEntry.Name, mNumber);
  end
  else
  begin
    AStore.WriteString(AEntry.Name, mText);
  end;
end;

/// <summary>Früheren Namen AFormer von AEntry übernehmen und entfernen.</summary>
function RenameOne(const AStore: IDpccSettingsStore; const ANames: IDpccSettingsNames;
  const AEntry: TDpccCatalogEntry; const AFormer: string): TDpccSettingsRename;
begin
  Result := Default(TDpccSettingsRename);
  Result.OldName := AFormer;
  Result.OldKey := AFormer;
  if Length(AEntry.FormerKeys) > 0 then
  begin
    Result.OldKey := AEntry.FormerKeys[0];
  end;
  Result.NewName := AEntry.Name;
  Result.NewKey := AEntry.Key;
  if ANames.Contains(AEntry.Name) then
  begin
    Result.Outcome := srSuperseded;
  end
  else if MoveValue(AStore, AEntry, AFormer) then
  begin
    Result.Outcome := srMoved;
  end
  else
  begin
    Result.Outcome := srInvalid;
  end;
  ANames.Remove(AFormer);
end;

{ TDpccSettingsRenames }

class function TDpccSettingsRenames.Apply(const AStore: IDpccSettingsStore; const ANames: IDpccSettingsNames;
  ACatalog: TDpccSettingsCatalog): TArray<TDpccSettingsRename>;
var
  mIndex: Integer;
  mEntry: TDpccCatalogEntry;
  mFormer: string;
begin
  Result := nil;
  for mIndex := 0 to ACatalog.Count - 1 do
  begin
    mEntry := ACatalog[mIndex];
    if mEntry.Source <> asPlugin then
    begin
      Continue;
    end;
    for mFormer in mEntry.RenamedFrom do
    begin
      if not SameText(mFormer, mEntry.Name) and ANames.Contains(mFormer) then
      begin
        Result := Result + [RenameOne(AStore, ANames, mEntry, mFormer)];
      end;
    end;
  end;
end;

end.
