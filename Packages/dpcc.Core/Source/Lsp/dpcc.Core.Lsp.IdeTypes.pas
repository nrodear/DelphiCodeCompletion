unit dpcc.Core.Lsp.IdeTypes;

// Typen aus den geladenen Packages der IDE für den Server (dpcc/ideTypes). Die IDE kennt jeden Typ eines
// geladenen Packages samt Unit über die RTTI, auch wenn das Package nur als BPL/DCP/DCU installiert ist und die
// .pas fehlt. Der Server nutzt sie, damit unresolved-type und unresolved-identifier für solche Typen schweigen,
// die Schnellkorrektur die Unit vorschlägt und die Vervollständigung sie anbietet. Hier ohne Open Tools API und
// RTTI: Aufteilen qualifizierter Namen und das JSON der Meldung; gesammelt wird in dpcc.IDE.CodeInsight.IdeTypes.
// L2: Auch Packages der Installation zählen, aber nur mit Units ohne Quelltext (DUnitX, FireDAC, IoT …): Was als .pas
// in der Installation liegt, steht im Index, und Quelltext gewinnt (KeepInstalled).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  /// <summary>Ein Typ der IDE mit Unit und, bei Klassen, dem direkten Vorfahren samt Unit.</summary>
  TDpccIdeType = record
    Name: string;
    UnitName: string;
    /// <summary>Vorfahr mit Unit (Vcl.Controls.TCustomControl); '' ohne.</summary>
    Parent: string;
    /// <summary>Typ aus dem qualifizierten Namen AQualified (Unit.Typ) und dem qualifizierten Vorfahren
    /// AParent; False für Namen ohne Unit und generische Instanzen (mit &lt;).</summary>
    class function FromQualified(const AQualified, AParent: string; out AType: TDpccIdeType): Boolean; static;
  end;

  TDpccIdeTypes = class
  public const
    cMethod = 'dpcc/ideTypes';
  public
    /// <summary>Parameter von dpcc/ideTypes: je Unit ein Eintrag in der Reihenfolge des ersten Vorkommens, ohne
    /// doppelte Typen. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const ATypes: TArray<TDpccIdeType>): TJSONObject; static;
    /// <summary>ATypes ohne doppelte Typen (Unit.Typ ohne Groß-/Kleinschreibung), der erste bleibt samt Vorfahr, die
    /// Reihenfolge auch: Palette und RTTI der Packages melden dieselben Komponenten.</summary>
    class function Unique(const ATypes: TArray<TDpccIdeType>): TArray<TDpccIdeType>; static;
    /// <summary>Liegt AFileName unter einem der Ordner AFolders (ohne Groß-/Kleinschreibung)?</summary>
    class function InFolders(const AFileName: string; const AFolders: TArray<string>): Boolean; static;
    /// <summary>Unit-Namen (groß) der Dateien AFiles, etwa aller .pas der Installation (L2). Der Aufrufer gibt das
    /// Ergebnis frei.</summary>
    class function UnitNames(const AFiles: TArray<string>): TDictionary<string, Boolean>; static;
    /// <summary>Typ aus einem Package der Installation behalten (L2)? Nur, wenn seine Unit in ASourceUnits (groß)
    /// fehlt: Units mit Quelltext stehen im Index.</summary>
    class function KeepInstalled(const AType: TDpccIdeType; const ASourceUnits: TDictionary<string, Boolean>): Boolean;
      static;
  end;

implementation

{ TDpccIdeType }

class function TDpccIdeType.FromQualified(const AQualified, AParent: string; out AType: TDpccIdeType): Boolean;
var
  mDot: Integer;
begin
  AType := Default(TDpccIdeType);
  mDot := AQualified.LastIndexOf('.');
  Result := (mDot > 0) and (mDot < AQualified.Length - 1) and (Pos('<', AQualified) = 0);
  if Result then
  begin
    AType.UnitName := AQualified.Substring(0, mDot);
    AType.Name := AQualified.Substring(mDot + 1);
    AType.Parent := AParent;
  end;
end;

{ TDpccIdeTypes }

/// <summary>Element von "types": Name allein oder mit Vorfahr.</summary>
function TypeJson(const AType: TDpccIdeType): TJSONValue;
var
  mObject: TJSONObject;
begin
  if AType.Parent = '' then
  begin
    Exit(TJSONString.Create(AType.Name));
  end;
  mObject := TJSONObject.Create;
  mObject.AddPair('name', AType.Name);
  mObject.AddPair('parent', AType.Parent);
  Result := mObject;
end;

/// <summary>Liste "types" der Unit AUnit in AUnits, bei Bedarf neu angelegt (AOrder hält die Reihenfolge).
/// </summary>
function TypesOf(AUnits: TDictionary<string, TJSONArray>; AOrder: TJSONArray; const AUnit: string): TJSONArray;
var
  mEntry: TJSONObject;
begin
  if AUnits.TryGetValue(UpperCase(AUnit), Result) then
  begin
    Exit;
  end;
  Result := TJSONArray.Create;
  mEntry := TJSONObject.Create;
  mEntry.AddPair('unit', AUnit);
  mEntry.AddPair('types', Result);
  AOrder.AddElement(mEntry);
  AUnits.Add(UpperCase(AUnit), Result);
end;

class function TDpccIdeTypes.ToJson(const ATypes: TArray<TDpccIdeType>): TJSONObject;
var
  mOrder: TJSONArray;
  mUnits: TDictionary<string, TJSONArray>;
  mSeen: TDictionary<string, Boolean>;
  mType: TDpccIdeType;
  mKey: string;
begin
  Result := TJSONObject.Create;
  mOrder := TJSONArray.Create;
  Result.AddPair('units', mOrder);
  mUnits := TDictionary<string, TJSONArray>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mType in ATypes do
    begin
      mKey := UpperCase(mType.UnitName + '.' + mType.Name);
      if (mType.Name <> '') and (mType.UnitName <> '') and not mSeen.ContainsKey(mKey) then
      begin
        mSeen.Add(mKey, True);
        TypesOf(mUnits, mOrder, mType.UnitName).AddElement(TypeJson(mType));
      end;
    end;
  finally
    mSeen.Free;
    mUnits.Free;
  end;
end;

class function TDpccIdeTypes.Unique(const ATypes: TArray<TDpccIdeType>): TArray<TDpccIdeType>;
var
  mSeen: TDictionary<string, Boolean>;
  mIndex, mCount: Integer;
  mKey: string;
begin
  Result := nil;
  SetLength(Result, Length(ATypes));
  mCount := 0;
  mSeen := TDictionary<string, Boolean>.Create(Length(ATypes));
  try
    for mIndex := 0 to High(ATypes) do
    begin
      // Derselbe Schlüssel wie in ToJson.
      mKey := UpperCase(ATypes[mIndex].UnitName + '.' + ATypes[mIndex].Name);
      if mSeen.ContainsKey(mKey) then
      begin
        Continue;
      end;
      mSeen.Add(mKey, True);
      Result[mCount] := ATypes[mIndex];
      Inc(mCount);
    end;
  finally
    mSeen.Free;
  end;
  SetLength(Result, mCount);
end;

class function TDpccIdeTypes.UnitNames(const AFiles: TArray<string>): TDictionary<string, Boolean>;
var
  mFileName: string;
begin
  Result := TDictionary<string, Boolean>.Create(Length(AFiles));
  for mFileName in AFiles do
  begin
    Result.AddOrSetValue(UpperCase(ChangeFileExt(ExtractFileName(mFileName), '')), True);
  end;
end;

class function TDpccIdeTypes.KeepInstalled(const AType: TDpccIdeType;
  const ASourceUnits: TDictionary<string, Boolean>): Boolean;
begin
  Result := (ASourceUnits = nil) or not ASourceUnits.ContainsKey(UpperCase(AType.UnitName));
end;

class function TDpccIdeTypes.InFolders(const AFileName: string; const AFolders: TArray<string>): Boolean;
var
  mFolder: string;
begin
  for mFolder in AFolders do
  begin
    if (mFolder <> '') and AFileName.StartsWith(IncludeTrailingPathDelimiter(mFolder), True) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
