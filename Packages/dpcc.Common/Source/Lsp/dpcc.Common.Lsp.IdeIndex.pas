unit dpcc.Common.Lsp.IdeIndex;

// Index für Hover, Vervollständigung und Parameterhilfe: der gemeinsame Index, ergänzt um die Ersatz-Units der
// IDE (dpcc.Common.Lsp.IdeUnits). Gefragt wird immer zuerst der gemeinsame Index; eine Ersatz-Unit zählt nur,
// wenn er die Unit nicht kennt. Ändern (AddUnit, RemoveFile, Budget) geht nur an den gemeinsamen Index.

interface

uses
  System.Generics.Collections,
  dpcc.Common.Index.Contract;

type
  TIdeIndex = class(TInterfacedObject, ISymbolIndex, IIndexIncludeOwners)
  private
    FInner: ISymbolIndex;
    FIde: ISymbolIndex;
  public
    /// <summary>AInner ist der gemeinsame Index, AIde der Index der Ersatz-Units.</summary>
    constructor Create(const AInner, AIde: ISymbolIndex);
    /// <summary>Verwirft den Namensindex der Import-Vorschläge zu diesem Index (TImportNames): Hover,
    /// Vervollständigung und Parameterhilfe fragen über ihn, der Schnappschuss hielt sonst alle Units über das Ende
    /// des Servers hinaus fest (Speicher-Optimierung Phase 2).</summary>
    destructor Destroy; override;
    procedure AddUnit(const AUnit: TUnitIndex);
    procedure RemoveFile(const AFileName: string);
    function FindUnit(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
    procedure AddUnitAliases(const AAliases: TArray<TPair<string, string>>);
    function FindFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    function FindSymbols(const AName: string): TArray<TSymbolLocation>;
    function HasSymbol(const AName: string; const AMatch: TSymbolMatch): Boolean;
    function Descendants(const ATypeName: string): TArray<TSymbolLocation>;
    function Units: TArray<TUnitIndex>;
    function UnavailableUnits: TArray<TUnitIndex>;
    function UnitCount: Integer;
    function SymbolCount: Integer;
    function MemoryBytes: Int64;
    function MemoryParts: TIndexMemoryParts;
    function CompactCount: Integer;
    function OffloadedCount: Integer;
    procedure SetBudget(ABytes: Int64);
    function Budget: Int64;
    function Generation: Int64;
    procedure ReleaseStringPool;
    function FindHeader(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    function FindUnitHeader(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
    function CatalogUnits: TArray<TCatalogUnit>;
    function StoredUnits: TArray<TIndexStoredUnit>;
    procedure AddEvictable(const AUnit: TUnitIndex; const ASource: IIndexUnitSource);
    procedure AddCold(const AHeader: TUnitIndex; const ACatalog: TCatalogUnit; const ASource: IIndexUnitSource;
      ASymbolCount, AUnavailableCount, AUsageCount: Integer);
    function Pin(const AFileName: string; out AWasPinned: Boolean): Boolean;
    function BindSources(const AHeaders: TArray<TUnitIndex>; const ASources: TArray<IIndexUnitSource>): Integer;
    function LazyStats: TIndexLazyStats;
    procedure SetUsage(const AUsage: IIndexUsage);
    function Usage: IIndexUsage;
    function UnitFiles(const AUnitName: string): TArray<string>;
    procedure SetUnitScopes(const AScopes: IIndexUnitScopes);
    function UnitScopes: IIndexUnitScopes;
    procedure SetStaleCheck(const ACheck: IIndexStaleCheck);
    function StaleCheck: IIndexStaleCheck;
    procedure TrimEvictable;
    /// <summary>Einbindende Unit einer Include-Datei (L3): erst im gemeinsamen Index, dann unter den Ersatz-Units.
    /// </summary>
    function IncludeOwner(const AIncludeFile: string): string;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  dpcc.Common.Index.NameIndex;

/// <summary>Einbindende Unit von AIncludeFile in AIndex: über IIndexIncludeOwners, sonst unter den geladenen Units.
/// </summary>
function OwnerIn(const AIndex: ISymbolIndex; const AIncludeFile: string): string;
var
  mOwners: IIndexIncludeOwners;
  mUnit: TUnitIndex;
begin
  Result := '';
  if Supports(AIndex, IIndexIncludeOwners, mOwners) then
  begin
    Exit(mOwners.IncludeOwner(AIncludeFile));
  end;
  for mUnit in AIndex.Units do
  begin
    if IndexText(AIncludeFile, mUnit.Includes) >= 0 then
    begin
      Exit(mUnit.FileName);
    end;
  end;
end;

/// <summary>AFirst, dann ASecond; ohne ASecond AFirst selbst (keine Kopie).</summary>
function Joined(const AFirst, ASecond: TArray<TSymbolLocation>): TArray<TSymbolLocation>;
var
  mIndex: Integer;
begin
  // Kopie: Result darf den Schnappschuss von AFirst nicht verändern.
  Result := Copy(AFirst);
  if Length(ASecond) = 0 then
  begin
    Exit;
  end;
  SetLength(Result, Length(AFirst) + Length(ASecond));
  for mIndex := 0 to High(ASecond) do
  begin
    Result[Length(AFirst) + mIndex] := ASecond[mIndex];
  end;
end;

constructor TIdeIndex.Create(const AInner, AIde: ISymbolIndex);
begin
  inherited Create;
  FInner := AInner;
  FIde := AIde;
end;

destructor TIdeIndex.Destroy;
begin
  TImportNames.Forget(Self);
  FIde := nil;
  FInner := nil;
  inherited;
end;

procedure TIdeIndex.AddUnit(const AUnit: TUnitIndex);
begin
  FInner.AddUnit(AUnit);
end;

procedure TIdeIndex.RemoveFile(const AFileName: string);
begin
  FInner.RemoveFile(AFileName);
end;

function TIdeIndex.FindUnit(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
begin
  Result := FInner.FindUnit(AUnitName, AUnit) or FIde.FindUnit(AUnitName, AUnit);
end;

procedure TIdeIndex.AddUnitAliases(const AAliases: TArray<TPair<string, string>>);
begin
  FInner.AddUnitAliases(AAliases);
end;

function TIdeIndex.FindFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
begin
  Result := FInner.FindFile(AFileName, AUnit) or FIde.FindFile(AFileName, AUnit);
end;

function TIdeIndex.FindSymbols(const AName: string): TArray<TSymbolLocation>;
begin
  Result := Joined(FInner.FindSymbols(AName), FIde.FindSymbols(AName));
end;

function TIdeIndex.HasSymbol(const AName: string; const AMatch: TSymbolMatch): Boolean;
begin
  Result := FInner.HasSymbol(AName, AMatch) or FIde.HasSymbol(AName, AMatch);
end;

function TIdeIndex.Descendants(const ATypeName: string): TArray<TSymbolLocation>;
begin
  Result := Joined(FInner.Descendants(ATypeName), FIde.Descendants(ATypeName));
end;

function TIdeIndex.Units: TArray<TUnitIndex>;
var
  mIde: TArray<TUnitIndex>;
  mInner, mIndex: Integer;
begin
  Result := FInner.Units;
  // Ohne Ersatz-Units den Schnappschuss des gemeinsamen Index unverändert weitergeben (keine Kopie).
  mIde := FIde.Units;
  if Length(mIde) = 0 then
  begin
    Exit;
  end;
  mInner := Length(Result);
  Result := Copy(Result);
  SetLength(Result, mInner + Length(mIde));
  for mIndex := 0 to High(mIde) do
  begin
    Result[mInner + mIndex] := mIde[mIndex];
  end;
end;

function TIdeIndex.UnavailableUnits: TArray<TUnitIndex>;
begin
  Result := FInner.UnavailableUnits;
end;

function TIdeIndex.UnitCount: Integer;
begin
  Result := FInner.UnitCount + FIde.UnitCount;
end;

function TIdeIndex.SymbolCount: Integer;
begin
  Result := FInner.SymbolCount + FIde.SymbolCount;
end;

function TIdeIndex.MemoryBytes: Int64;
begin
  Result := FInner.MemoryBytes;
end;

function TIdeIndex.MemoryParts: TIndexMemoryParts;
begin
  Result := FInner.MemoryParts;
end;

function TIdeIndex.CompactCount: Integer;
begin
  Result := FInner.CompactCount;
end;

function TIdeIndex.OffloadedCount: Integer;
begin
  Result := FInner.OffloadedCount;
end;

procedure TIdeIndex.SetBudget(ABytes: Int64);
begin
  FInner.SetBudget(ABytes);
end;

function TIdeIndex.Budget: Int64;
begin
  Result := FInner.Budget;
end;

procedure TIdeIndex.ReleaseStringPool;
begin
  FInner.ReleaseStringPool;
end;

function TIdeIndex.Generation: Int64;
begin
  // Beide zählen nur hoch: Die Summe ändert sich bei jeder Änderung an einem der beiden.
  Result := FInner.Generation + FIde.Generation;
end;

function TIdeIndex.FindHeader(const AFileName: string; out AUnit: TUnitIndex): Boolean;
begin
  Result := FInner.FindHeader(AFileName, AUnit) or FIde.FindHeader(AFileName, AUnit);
end;

function TIdeIndex.FindUnitHeader(const AUnitName: string; out AUnit: TUnitIndex): Boolean;
begin
  Result := FInner.FindUnitHeader(AUnitName, AUnit) or FIde.FindUnitHeader(AUnitName, AUnit);
end;

function TIdeIndex.CatalogUnits: TArray<TCatalogUnit>;
var
  mIde: TArray<TCatalogUnit>;
  mInner, mIndex: Integer;
begin
  Result := FInner.CatalogUnits;
  // Wie Units: ohne Ersatz-Units den Schnappschuss des gemeinsamen Index unverändert weitergeben.
  mIde := FIde.CatalogUnits;
  if Length(mIde) = 0 then
  begin
    Exit;
  end;
  mInner := Length(Result);
  Result := Copy(Result);
  SetLength(Result, mInner + Length(mIde));
  for mIndex := 0 to High(mIde) do
  begin
    Result[mInner + mIndex] := mIde[mIndex];
  end;
end;

function TIdeIndex.StoredUnits: TArray<TIndexStoredUnit>;
begin
  Result := FInner.StoredUnits;
end;

procedure TIdeIndex.AddEvictable(const AUnit: TUnitIndex; const ASource: IIndexUnitSource);
begin
  FInner.AddEvictable(AUnit, ASource);
end;

procedure TIdeIndex.AddCold(const AHeader: TUnitIndex; const ACatalog: TCatalogUnit; const ASource: IIndexUnitSource;
  ASymbolCount, AUnavailableCount, AUsageCount: Integer);
begin
  FInner.AddCold(AHeader, ACatalog, ASource, ASymbolCount, AUnavailableCount, AUsageCount);
end;

function TIdeIndex.Pin(const AFileName: string; out AWasPinned: Boolean): Boolean;
begin
  Result := FInner.Pin(AFileName, AWasPinned);
end;

function TIdeIndex.BindSources(const AHeaders: TArray<TUnitIndex>; const ASources: TArray<IIndexUnitSource>): Integer;
begin
  Result := FInner.BindSources(AHeaders, ASources);
end;

function TIdeIndex.LazyStats: TIndexLazyStats;
begin
  Result := FInner.LazyStats;
end;

procedure TIdeIndex.SetUsage(const AUsage: IIndexUsage);
begin
  FInner.SetUsage(AUsage);
end;

function TIdeIndex.Usage: IIndexUsage;
begin
  Result := FInner.Usage;
end;

function TIdeIndex.UnitFiles(const AUnitName: string): TArray<string>;
begin
  // Ersatz-Units zählen nur ohne Quelltext; gleichnamige gibt es nur im gemeinsamen Index.
  Result := FInner.UnitFiles(AUnitName);
end;

procedure TIdeIndex.SetUnitScopes(const AScopes: IIndexUnitScopes);
begin
  FInner.SetUnitScopes(AScopes);
end;

function TIdeIndex.UnitScopes: IIndexUnitScopes;
begin
  Result := FInner.UnitScopes;
end;

procedure TIdeIndex.SetStaleCheck(const ACheck: IIndexStaleCheck);
begin
  FInner.SetStaleCheck(ACheck);
end;

function TIdeIndex.StaleCheck: IIndexStaleCheck;
begin
  Result := FInner.StaleCheck;
end;

procedure TIdeIndex.TrimEvictable;
begin
  FInner.TrimEvictable;
end;

function TIdeIndex.IncludeOwner(const AIncludeFile: string): string;
begin
  Result := OwnerIn(FInner, AIncludeFile);
  if Result = '' then
  begin
    Result := OwnerIn(FIde, AIncludeFile);
  end;
end;

end.
