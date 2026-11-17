unit dpcc.IDE.CodeInsight.IdeTypes;

// Sammelt die Typen der geladenen Packages für dpcc/ideTypes (Hauptthread, beim Start der Sitzung). Zwei Quellen:
// - die RTTI jedes geladenen Packages (TRttiContext.GetPackages): alle öffentlichen Typen samt Unit, bei Klassen
//   mit Vorfahr; so kennt die IDE auch Typen aus Packages, die nur als BPL/DCP/DCU installiert sind;
// - die Komponenten der Palette (IOTAPackageServices, über RegisterComponents angemeldet) über GetClass.
// Die Packages von dpcc selbst bleiben außen vor (sie gehören nicht in fremde Projekte). Packages der Installation
// zählen seit L2 mit, aber nur ihre Units ohne Quelltext (DUnitX, FireDAC, IoT …): Units, deren .pas unter
// $(BDS)\source oder $(BDS)\OCX liegt, stehen im Index; Quelltext gewinnt. Die Liste dieser .pas entsteht einmal je
// Sitzung der IDE.

interface

uses
  System.Generics.Collections,
  dpcc.Core.Lsp.IdeTypes;

type
  TDpccIdeTypeCollector = class
  private
    /// <summary>Typen der Packages an ATypes anhängen; Ergebnis: Zahl der Packages, deren RTTI nicht lesbar war.
    /// </summary>
    class function AddPackages(const ASkipped: TArray<string>; ATypes: TList<TDpccIdeType>): Integer; static;
    class procedure AddPalette(const ASkipped: TArray<string>; ATypes: TList<TDpccIdeType>); static;
  private
    class var FSourceUnits: TDictionary<string, Boolean>;
  public
    class destructor Destroy;
    /// <summary>Ordner, deren Packages nicht zählen: dpcc (L2: die Installation zählt mit, siehe SourceUnits).
    /// </summary>
    class function SkippedFolders: TArray<string>; static;
    /// <summary>Ordner der Installation (bds.exe liegt in &lt;Installation&gt;\bin).</summary>
    class function InstallationFolder: string; static;
    /// <summary>Unit-Namen (groß) aller .pas unter $(BDS)\source und $(BDS)\OCX; einmal je Sitzung gelistet.
    /// Gehört der Klasse.</summary>
    class function SourceUnits: TDictionary<string, Boolean>; static;
    /// <summary>Typen der geladenen Packages außerhalb der Installation; nur im Hauptthread. AFailed: Packages,
    /// deren RTTI nicht lesbar war (sie fehlen im Ergebnis).</summary>
    class function Collect(out AFailed: Integer): TArray<TDpccIdeType>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Rtti,
  ToolsAPI;

class destructor TDpccIdeTypeCollector.Destroy;
begin
  FreeAndNil(FSourceUnits);
end;

class function TDpccIdeTypeCollector.InstallationFolder: string;
begin
  Result := ExtractFileDir(ExtractFileDir(ParamStr(0)));
end;

class function TDpccIdeTypeCollector.SkippedFolders: TArray<string>;
begin
  // Base und seine Module liegen im Ordner von Base. L2: Die Installation zählt mit (Units ohne Quelltext).
  Result := TArray<string>.Create(ExcludeTrailingPathDelimiter(ExtractFilePath(GetModuleName(HInstance))));
end;

class function TDpccIdeTypeCollector.SourceUnits: TDictionary<string, Boolean>;
var
  mFiles: TArray<string>;
  mFolder: string;
begin
  if FSourceUnits = nil then
  begin
    mFiles := nil;
    for mFolder in TArray<string>.Create('source', 'OCX') do
    begin
      try
        if TDirectory.Exists(TPath.Combine(InstallationFolder, mFolder)) then
        begin
          mFiles := mFiles + TDirectory.GetFiles(TPath.Combine(InstallationFolder, mFolder), '*.pas',
            TSearchOption.soAllDirectories);
        end;
      except
        // Nicht lesbar: dann zählen die Typen dieser Packages wie bisher nicht doppelt, sondern gar nicht.
        on Exception do
          ;
      end;
    end;
    FSourceUnits := TDpccIdeTypes.UnitNames(mFiles);
  end;
  Result := FSourceUnits;
end;

/// <summary>Qualifizierter Name des Vorfahren einer Klasse; '' ohne.</summary>
function ParentOf(AType: TRttiType): string;
begin
  Result := '';
  if (AType is TRttiInstanceType) and (AType.BaseType <> nil) then
  begin
    Result := AType.BaseType.QualifiedName;
  end;
end;

/// <summary>Öffentliche Typen von APackage an ATypes anhängen; ASourceUnits (nicht nil bei Packages der
/// Installation, L2): Typen dieser Units entfallen, sie haben Quelltext.</summary>
procedure AddPackageTypes(APackage: TRttiPackage; ATypes: TList<TDpccIdeType>;
  const ASourceUnits: TDictionary<string, Boolean>);
var
  mRttiType: TRttiType;
  mType: TDpccIdeType;
begin
  for mRttiType in APackage.GetTypes do
  begin
    if mRttiType.IsPublicType and TDpccIdeType.FromQualified(mRttiType.QualifiedName, ParentOf(mRttiType), mType) and
      TDpccIdeTypes.KeepInstalled(mType, ASourceUnits) then
    begin
      ATypes.Add(mType);
    end;
  end;
end;

class function TDpccIdeTypeCollector.AddPackages(const ASkipped: TArray<string>;
  ATypes: TList<TDpccIdeType>): Integer;
var
  mContext: TRttiContext;
  mPackage: TRttiPackage;
  mSources: TDictionary<string, Boolean>;
begin
  Result := 0;
  mContext := TRttiContext.Create;
  try
    for mPackage in mContext.GetPackages do
    begin
      if TDpccIdeTypes.InFolders(mPackage.Name, ASkipped) then
      begin
        Continue;
      end;
      // L2: Packages der Installation nur mit ihren Units ohne Quelltext.
      mSources := nil;
      if TDpccIdeTypes.InFolders(mPackage.Name, [InstallationFolder]) then
      begin
        mSources := SourceUnits;
      end;
      // Ein Package mit beschädigter RTTI darf die übrigen nicht verhindern.
      try
        AddPackageTypes(mPackage, ATypes, mSources);
      except
        on Exception do
        begin
          Inc(Result);
        end;
      end;
    end;
  finally
    mContext.Free;
  end;
end;

/// <summary>Komponente AName der Palette als Typ; False, wenn ihre Klasse nicht angemeldet ist oder in einem
/// Package unter ASkipped liegt.</summary>
function PaletteType(const AName: string; const ASkipped: TArray<string>; out AType: TDpccIdeType): Boolean;
var
  mClass: TPersistentClass;
  mParent: string;
begin
  mClass := GetClass(AName);
  Result := (mClass <> nil) and not TDpccIdeTypes.InFolders(GetModuleName(FindClassHInstance(mClass)), ASkipped) and
    (not TDpccIdeTypes.InFolders(GetModuleName(FindClassHInstance(mClass)),
    [TDpccIdeTypeCollector.InstallationFolder]) or
    not TDpccIdeTypeCollector.SourceUnits.ContainsKey(UpperCase(mClass.UnitName)));
  if not Result then
  begin
    Exit;
  end;
  mParent := '';
  if mClass.ClassParent <> nil then
  begin
    mParent := mClass.ClassParent.UnitName + '.' + mClass.ClassParent.ClassName;
  end;
  Result := TDpccIdeType.FromQualified(mClass.UnitName + '.' + mClass.ClassName, mParent, AType);
end;

class procedure TDpccIdeTypeCollector.AddPalette(const ASkipped: TArray<string>;
  ATypes: TList<TDpccIdeType>);
var
  mServices: IOTAPackageServices;
  mPackage, mComponent: Integer;
  mType: TDpccIdeType;
begin
  if not Supports(BorlandIDEServices, IOTAPackageServices, mServices) then
  begin
    Exit;
  end;
  for mPackage := 0 to mServices.PackageCount - 1 do
  begin
    for mComponent := 0 to mServices.ComponentCount[mPackage] - 1 do
    begin
      if PaletteType(mServices.ComponentNames[mPackage, mComponent], ASkipped, mType) then
      begin
        ATypes.Add(mType);
      end;
    end;
  end;
end;

class function TDpccIdeTypeCollector.Collect(out AFailed: Integer): TArray<TDpccIdeType>;
var
  mSkipped: TArray<string>;
  mTypes: TList<TDpccIdeType>;
begin
  mSkipped := SkippedFolders;
  mTypes := TList<TDpccIdeType>.Create;
  try
    AddPalette(mSkipped, mTypes);
    AFailed := AddPackages(mSkipped, mTypes);
    Result := mTypes.ToArray;
  finally
    mTypes.Free;
  end;
end;

end.
