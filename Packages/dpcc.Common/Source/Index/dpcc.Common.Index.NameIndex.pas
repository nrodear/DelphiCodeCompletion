unit dpcc.Common.Index.NameIndex;

// Namensindex für die Import-Vorschläge der Vervollständigung (#617).
//
// Die Vervollständigung schlägt Symbole aus Units vor, die noch nicht in den
// uses stehen. Statt bei jeder Anfrage alle Units und alle Symbole (bei
// großen Projekten über 500.000) mit dem unscharfen Vergleich zu prüfen,
// hält der Namensindex nur die importierbaren Symbole (interface, oberste
// Ebene) in einer flachen Liste, Projekt-Units vor der Bibliothek.
//
// Zu jedem Namen gehört eine Zeichenmaske (Buchstaben, Ziffern, "_"). Ein
// Treffer, ob Präfix, Teilwort oder Teilfolge, enthält alle Zeichen der
// Anfrage; fehlt eines in der Maske, entfällt der teure Vergleich.
//
// Der Index ist ein unveränderlicher Schnappschuss (nur verwaltete Arrays):
// Wer ihn kopiert, kann ihn ohne Sperre lesen, auch während ein neuer
// aufgebaut wird. Generation sagt, zu welchem Stand des Index er gehört.
//
// TImportNames.Current hält einen Schnappschuss je Index und baut ihn neu,
// wenn sich der Index geändert hat. Während der Index wächst (Aufbau beim
// Start), ändert er sich ständig; große Schnappschüsse werden dann höchstens
// einmal pro RebuildMs erneuert, damit nicht jede Anfrage neu aufbaut.
//
// Speicher-Optimierung Phase 3: Der Schnappschuss steht auf dem Katalog des
// Index (ISymbolIndex.CatalogUnits) statt auf den Units samt Symbolen. Er
// kennt so auch verdrängte Units, hält aber keine vollen Symbol-Arrays fest;
// Nachladen und Verdrängen ändern ihn nicht (Generation bleibt).
//
// L3: Zum Schnappschuss gehört bei Bedarf eine Typtabelle (TImportTypeTable, TImportNames.Types): Klassen und
// Typ-Aliase des Katalogs nach Namen, für die Vorfahrenkette bei raise und Attributen ohne Nachladen. Sie entsteht
// erst bei der ersten solchen Anfrage und fällt mit dem Schnappschuss weg.

interface

uses
  dpcc.Common.Index.Contract;

type
  TImportNameEntry = record
    /// <summary>Position in TImportNameIndex.Units.</summary>
    UnitPos: Integer;
    /// <summary>Position in Units[UnitPos].Symbols (Katalog).</summary>
    SymbolPos: Integer;
    Mask: UInt64;
  end;

  TImportNameIndex = record
    Generation: Int64;
    /// <summary>Katalog aller Units (Phase 3).</summary>
    Units: TArray<TCatalogUnit>;
    /// <summary>Projekt-Units zuerst, dann die Bibliothek.</summary>
    Entries: TArray<TImportNameEntry>;
    /// <summary>Class- und Record-Helper mit Zieltyp (#456), Reihenfolge wie Entries; Mask = 0.</summary>
    Helpers: TArray<TImportNameEntry>;
    /// <summary>Baut den Index aus dem aktuellen Stand von AIndex.</summary>
    class function Build(const AIndex: ISymbolIndex): TImportNameIndex; static;
    /// <summary>Zeichenmaske ohne Groß-/Kleinschreibung; alle übrigen Zeichen teilen sich ein Bit.</summary>
    class function MaskOf(const AName: string): UInt64; static;
    /// <summary>Kann ein Name mit ANameMask zu einer Anfrage mit AQueryMask passen?</summary>
    class function MayMatch(ANameMask, AQueryMask: UInt64): Boolean; static; inline;
    function Count: Integer;
  end;

  /// <summary>Klassen und Typ-Aliase des Katalogs nach Namen (L3): Der Vorfilter bei raise und Attributen prüft
  /// damit die Vorfahrenkette über TCatalogSymbol.Ancestors, ohne kalte Units nachzuladen. Offene Adressierung über
  /// die Einträge des Namensindex (4 Byte je Platz, rund 1,5 Plätze je Typ); Names teilt die Arrays des
  /// Schnappschusses, aus dem die Tabelle entstand. Unveränderlich wie dieser.</summary>
  TImportTypeTable = record
    Names: TImportNameIndex;
    /// <summary>Position in Names.Entries + 1; 0 = frei.</summary>
    Slots: TArray<Integer>;
    /// <summary>Tabelle über die Klassen und Typ-Aliase von ANames.</summary>
    class function Build(const ANames: TImportNameIndex): TImportTypeTable; static;
    /// <summary>Positionen in Names.Entries der Klassen und Typ-Aliase namens AName (ohne Groß-/Kleinschreibung,
    /// wie CompareText); nil ohne.</summary>
    function Named(const AName: string): TArray<Integer>;
    /// <summary>Katalogeintrag zur Position AEntry aus Named.</summary>
    function Symbol(AEntry: Integer): TCatalogSymbol;
  end;

  TImportNames = class
  public const
    /// <summary>Ab so vielen Einträgen wird höchstens alle RebuildMs neu aufgebaut.</summary>
    cLargeCount = 50000;
    cRebuildMs = 1000;
  public
    /// <summary>Aktueller Namensindex zu AIndex; threadsicher.</summary>
    class function Current(const AIndex: ISymbolIndex): TImportNameIndex; static;
    /// <summary>Typtabelle zum aktuellen Namensindex von AIndex (L3); erst beim ersten Bedarf aufgebaut und mit dem
    /// Schnappschuss verworfen. Threadsicher.</summary>
    class function Types(const AIndex: ISymbolIndex): TImportTypeTable; static;
    /// <summary>AOwner (der Symbolindex als Objekt) wird freigegeben: seinen Schnappschuss verwerfen,
    /// sonst hielte der Cache dessen Units über das Ende hinaus fest.</summary>
    class procedure Forget(AOwner: TObject); static;
    /// <summary>Verwirft den Schnappschuss, gleich zu welchem Index (der letzte Server im Prozess ist beendet).
    /// </summary>
    class procedure Clear; static;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics;

var
  CacheLock: TObject;
  CacheOwner: Pointer;
  CacheNames: TImportNameIndex;
  CacheWatch: TStopwatch;
  // Typtabelle zu CacheNames (L3); leer, bis TImportNames.Types sie braucht.
  CacheTypes: TImportTypeTable;

{ TImportNameIndex }

class function TImportNameIndex.MaskOf(const AName: string): UInt64;
var
  mCh: Char;
begin
  Result := 0;
  for mCh in AName do
    case mCh of
      'a'..'z':
        Result := Result or (UInt64(1) shl (Ord(mCh) - Ord('a')));
      'A'..'Z':
        Result := Result or (UInt64(1) shl (Ord(mCh) - Ord('A')));
      '0'..'9':
        Result := Result or (UInt64(1) shl (26 + Ord(mCh) - Ord('0')));
      '_':
        Result := Result or (UInt64(1) shl 36);
    else
      Result := Result or (UInt64(1) shl 37);
    end;
end;

class function TImportNameIndex.MayMatch(ANameMask, AQueryMask: UInt64): Boolean;
begin
  Result := (ANameMask and AQueryMask) = AQueryMask;
end;

/// <summary>Zählt Einträge und Helfer, damit Build die Arrays einmal anlegt. Der Katalog enthält nur importierbare
/// Symbole (interface, oberste Ebene).</summary>
procedure CountImportEntries(const AUnits: TArray<TCatalogUnit>; out AEntries, AHelpers: Integer);
var
  mUnitPos, mSymbolPos: Integer;
begin
  AEntries := 0;
  AHelpers := 0;
  for mUnitPos := 0 to High(AUnits) do
  begin
    Inc(AEntries, Length(AUnits[mUnitPos].Symbols));
    for mSymbolPos := 0 to High(AUnits[mUnitPos].Symbols) do
    begin
      Inc(AHelpers, Ord(AUnits[mUnitPos].Symbols[mSymbolPos].IsHelper));
    end;
  end;
end;

class function TImportNameIndex.Build(const AIndex: ISymbolIndex): TImportNameIndex;
var
  mPass, mUnitPos, mSymbolPos, mUsed, mHelpers: Integer;
begin
  // Generation vor dem Katalog lesen: Ändert sich der Index dazwischen, baut der nächste Aufruf neu.
  Result.Generation := AIndex.Generation;
  Result.Units := AIndex.CatalogUnits;
  CountImportEntries(Result.Units, mUsed, mHelpers);
  SetLength(Result.Entries, mUsed);
  SetLength(Result.Helpers, mHelpers);
  mUsed := 0;
  mHelpers := 0;
  // Erst die Projekt-Units, dann die Bibliothek.
  for mPass := 0 to 1 do
  begin
    for mUnitPos := 0 to High(Result.Units) do
    begin
      if Result.Units[mUnitPos].Library_ <> (mPass = 1) then
      begin
        Continue;
      end;
      for mSymbolPos := 0 to High(Result.Units[mUnitPos].Symbols) do
      begin
        Result.Entries[mUsed].UnitPos := mUnitPos;
        Result.Entries[mUsed].SymbolPos := mSymbolPos;
        Result.Entries[mUsed].Mask := MaskOf(Result.Units[mUnitPos].Symbols[mSymbolPos].Name);
        Inc(mUsed);
        if Result.Units[mUnitPos].Symbols[mSymbolPos].IsHelper then
        begin
          Result.Helpers[mHelpers].UnitPos := mUnitPos;
          Result.Helpers[mHelpers].SymbolPos := mSymbolPos;
          Result.Helpers[mHelpers].Mask := 0;
          Inc(mHelpers);
        end;
      end;
    end;
  end;
end;

function TImportNameIndex.Count: Integer;
begin
  Result := Length(Entries);
end;

{ TImportTypeTable }

/// <summary>FNV-1a über die Zeichen, a–z wie A–Z (passt zu CompareText).</summary>
function TypeNameHash(const AName: string): Cardinal;
var
  mIndex: Integer;
  mCode: Cardinal;
begin
  Result := 2166136261;
  for mIndex := 1 to Length(AName) do
  begin
    mCode := Ord(AName[mIndex]);
    if (mCode >= Ord('a')) and (mCode <= Ord('z')) then
    begin
      Dec(mCode, 32);
    end;
    Result := Cardinal(UInt64(Result xor mCode) * 16777619);
  end;
end;

/// <summary>Gehört der Eintrag AEntry von ANames in die Typtabelle (Klasse oder Typ-Alias)?</summary>
function IsTableEntry(const ANames: TImportNameIndex; AEntry: Integer): Boolean;
begin
  // Über die Indizes: die Katalog-Records nicht kopieren.
  Result := ANames.Units[ANames.Entries[AEntry].UnitPos].Symbols[ANames.Entries[AEntry].SymbolPos].Kind in
    [TIndexSymbolKind.ClassType, TIndexSymbolKind.TypeAlias];
end;

/// <summary>Name des Eintrags AEntry von ANames.</summary>
function EntryName(const ANames: TImportNameIndex; AEntry: Integer): string;
begin
  Result := ANames.Units[ANames.Entries[AEntry].UnitPos].Symbols[ANames.Entries[AEntry].SymbolPos].Name;
end;

class function TImportTypeTable.Build(const ANames: TImportNameIndex): TImportTypeTable;
var
  mEntry, mCount, mSize, mMask, mSlot: Integer;
begin
  Result.Names := ANames;
  mCount := 0;
  for mEntry := 0 to High(ANames.Entries) do
  begin
    Inc(mCount, Ord(IsTableEntry(ANames, mEntry)));
  end;
  // Zweierpotenz mit mindestens 1,5 Plätzen je Typ: Es bleiben immer freie Plätze, die Suche endet.
  mSize := 16;
  while mSize < mCount + mCount div 2 + 1 do
  begin
    mSize := mSize * 2;
  end;
  SetLength(Result.Slots, mSize);
  mMask := mSize - 1;
  for mEntry := 0 to High(ANames.Entries) do
  begin
    if not IsTableEntry(ANames, mEntry) then
    begin
      Continue;
    end;
    mSlot := Integer(TypeNameHash(EntryName(ANames, mEntry)) and Cardinal(mMask));
    while Result.Slots[mSlot] <> 0 do
    begin
      mSlot := (mSlot + 1) and mMask;
    end;
    Result.Slots[mSlot] := mEntry + 1;
  end;
end;

function TImportTypeTable.Named(const AName: string): TArray<Integer>;
var
  mMask, mSlot, mEntry: Integer;
begin
  Result := nil;
  if (Length(Slots) = 0) or (AName = '') then
  begin
    Exit;
  end;
  mMask := Length(Slots) - 1;
  mSlot := Integer(TypeNameHash(AName) and Cardinal(mMask));
  while Slots[mSlot] <> 0 do
  begin
    mEntry := Slots[mSlot] - 1;
    if CompareText(EntryName(Names, mEntry), AName) = 0 then
    begin
      Result := Result + [mEntry];
    end;
    mSlot := (mSlot + 1) and mMask;
  end;
end;

function TImportTypeTable.Symbol(AEntry: Integer): TCatalogSymbol;
begin
  Result := Names.Units[Names.Entries[AEntry].UnitPos].Symbols[Names.Entries[AEntry].SymbolPos];
end;

{ TImportNames }

class function TImportNames.Current(const AIndex: ISymbolIndex): TImportNameIndex;
var
  mFresh: Boolean;
begin
  TMonitor.Enter(CacheLock);
  try
    mFresh := (CacheOwner = Pointer(AIndex as TObject)) and (CacheNames.Generation = AIndex.Generation);
    if not mFresh and (CacheOwner = Pointer(AIndex as TObject)) and (CacheNames.Count >= cLargeCount) and
      (CacheWatch.ElapsedMilliseconds < cRebuildMs) then
    begin
      mFresh := True;
    end;
    if not mFresh then
    begin
      CacheTypes := Default(TImportTypeTable);
      CacheNames := TImportNameIndex.Build(AIndex);
      CacheOwner := Pointer(AIndex as TObject);
      CacheWatch := TStopwatch.StartNew;
    end;
    Result := CacheNames;
  finally
    TMonitor.Exit(CacheLock);
  end;
end;

class function TImportNames.Types(const AIndex: ISymbolIndex): TImportTypeTable;
var
  mNames: TImportNameIndex;
begin
  mNames := Current(AIndex);
  TMonitor.Enter(CacheLock);
  try
    if (CacheTypes.Slots <> nil) and (Pointer(CacheTypes.Names.Entries) = Pointer(mNames.Entries)) then
    begin
      Exit(CacheTypes);
    end;
    Result := TImportTypeTable.Build(mNames);
    // Nur zum gemerkten Schnappschuss behalten: Hat ein anderer Thread ihn inzwischen erneuert, hielte die Tabelle
    // sonst den alten fest.
    if Pointer(mNames.Entries) = Pointer(CacheNames.Entries) then
    begin
      CacheTypes := Result;
    end;
  finally
    TMonitor.Exit(CacheLock);
  end;
end;

class procedure TImportNames.Forget(AOwner: TObject);
begin
  TMonitor.Enter(CacheLock);
  try
    if CacheOwner = Pointer(AOwner) then
    begin
      CacheTypes := Default(TImportTypeTable);
      CacheNames := Default(TImportNameIndex);
      CacheOwner := nil;
    end;
  finally
    TMonitor.Exit(CacheLock);
  end;
end;

class procedure TImportNames.Clear;
begin
  TMonitor.Enter(CacheLock);
  try
    CacheTypes := Default(TImportTypeTable);
    CacheNames := Default(TImportNameIndex);
    CacheOwner := nil;
  finally
    TMonitor.Exit(CacheLock);
  end;
end;

initialization
  CacheLock := TObject.Create;
  // Monitor gleich anlegen: Sonst entsteht er beim ersten Zugriff (oft in einem Test) und gilt dort als Leck.
  TMonitor.Enter(CacheLock);
  TMonitor.Exit(CacheLock);

finalization
  CacheTypes := Default(TImportTypeTable);
  CacheNames := Default(TImportNameIndex);
  CacheLock.Free;

end.
