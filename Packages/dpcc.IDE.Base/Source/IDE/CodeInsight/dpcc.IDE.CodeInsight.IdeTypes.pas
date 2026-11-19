unit dpcc.IDE.CodeInsight.IdeTypes;

// Sammelt die Typen der geladenen Packages für dpcc/ideTypes (Hauptthread, beim Start der Sitzung). Zwei Quellen:
// - die RTTI jedes geladenen Packages (TRttiContext.GetPackages): alle öffentlichen Typen samt Unit, bei Klassen
//   mit Vorfahr; so kennt die IDE auch Typen aus Packages, die nur als BPL/DCP/DCU installiert sind;
// - die Komponenten der Palette (IOTAPackageServices, über RegisterComponents angemeldet) über GetClass.
// Die Packages von dpcc selbst bleiben außen vor (sie gehören nicht in fremde Projekte). Packages der Installation
// zählen seit L2 mit, aber nur ihre Units ohne Quelltext (DUnitX, FireDAC, IoT …): Units, deren .pas unter
// $(BDS)\source oder $(BDS)\OCX liegt, stehen im Index; Quelltext gewinnt. Die Liste dieser .pas entsteht einmal je
// Sitzung der IDE.
// Hänger beim Öffnen eines Formulars (Start der Sitzung): Die Liste der .pas entsteht im Hintergrund-Thread des
// Serverstarts (PrepareSourceUnits, threadsicher). Die RTTI der Packages liest nur der Hauptthread, aber in kleinen
// Schritten (StartRun, Step mit Zeitbudget, je Takt ein paar Packages): Ein Package kann zwischen zwei Takten
// entladen werden, deshalb hält ein Lauf nur die Handles der Module und sucht sein Package je Schritt neu. Ein Worker
// darf die RTTI nicht lesen (entladene Packages, nicht threadsichere IDE-Packages). Das Ergebnis (nur Texte) bleibt
// je Stand der geladenen Module gemerkt: Ein Neustart des Servers ohne neue Packages schickt es sofort.

interface

uses
  System.Generics.Collections,
  dpcc.Core.Lsp.IdeTypes;

type
  /// <summary>Schrittweise Sammlung der IDE-Typen im Hauptthread.</summary>
  IDpccIdeTypeRun = interface
    ['{3F6B2C8E-9A41-4D7B-B0E5-6C2D8F1A4E93}']
    /// <summary>Höchstens etwa ABudgetMs arbeiten (mindestens ein Schritt); True, wenn fertig.</summary>
    function Step(ABudgetMs: Cardinal): Boolean;
    function Types: TArray<TDpccIdeType>;
    /// <summary>Packages, deren RTTI nicht lesbar war.</summary>
    function Failed: Integer;
    /// <summary>Gelesene Module (ohne die von dpcc).</summary>
    function Modules: Integer;
    /// <summary>Ergebnis aus dem Merker (Stand der Module unverändert).</summary>
    function FromCache: Boolean;
  end;

  TDpccIdeTypeCollector = class
  private
    /// <summary>Typen der Packages an ATypes anhängen; Ergebnis: Zahl der Packages, deren RTTI nicht lesbar war.
    /// </summary>
    class function AddPackages(const ASkipped: TArray<string>; ATypes: TList<TDpccIdeType>): Integer; static;
    class procedure AddPalette(const ASkipped: TArray<string>; ATypes: TList<TDpccIdeType>); static;
  private
    class var FSourceUnits: TDictionary<string, Boolean>;
    class var FLock: TObject;
    /// <summary>Gemerktes Ergebnis (StartRun) und der Stand der Module, zu dem es gehört.</summary>
    class var FCacheSignature: string;
    class var FCacheTypes: TArray<TDpccIdeType>;
    class var FCacheFailed: Integer;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Liste der .pas (SourceUnits) anlegen, falls noch nicht da; threadsicher, für den Hintergrund-Thread
    /// des Serverstarts.</summary>
    class procedure PrepareSourceUnits; static;
    /// <summary>Neuer Lauf über die geladenen Module (nur Hauptthread); Step im Hauptthread aufrufen.</summary>
    class function StartRun: IDpccIdeTypeRun; static;
    /// <summary>Ergebnis eines fertigen Laufs merken (nur Hauptthread).</summary>
    class procedure Remember(const ASignature: string; const ATypes: TArray<TDpccIdeType>; AFailed: Integer); static;
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
  System.Diagnostics,
  ToolsAPI;

type
  /// <summary>Lauf von StartRun: Palette, dann je Schritt Module bis zum Zeitbudget.</summary>
  TIdeTypeRun = class(TInterfacedObject, IDpccIdeTypeRun)
  private
    FModules: TArray<HINST>;
    FIndex: Integer;
    FPaletteDone: Boolean;
    FDone: Boolean;
    FFromCache: Boolean;
    FSkipped: TArray<string>;
    FSignature: string;
    FTypes: TList<TDpccIdeType>;
    FResult: TArray<TDpccIdeType>;
    FFailed: Integer;
    procedure StepModule(const APackages: TArray<TRttiPackage>; AModule: HINST);
    procedure Finish;
  public
    constructor Create;
    destructor Destroy; override;
    function Step(ABudgetMs: Cardinal): Boolean;
    function Types: TArray<TDpccIdeType>;
    function Failed: Integer;
    function Modules: Integer;
    function FromCache: Boolean;
  end;

class constructor TDpccIdeTypeCollector.Create;
begin
  FLock := TObject.Create;
end;

class destructor TDpccIdeTypeCollector.Destroy;
begin
  FreeAndNil(FSourceUnits);
  FCacheTypes := nil;
  FreeAndNil(FLock);
end;

class procedure TDpccIdeTypeCollector.Remember(const ASignature: string; const ATypes: TArray<TDpccIdeType>;
  AFailed: Integer);
begin
  FCacheSignature := ASignature;
  FCacheTypes := ATypes;
  FCacheFailed := AFailed;
end;

class function TDpccIdeTypeCollector.StartRun: IDpccIdeTypeRun;
begin
  Result := TIdeTypeRun.Create;
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

class procedure TDpccIdeTypeCollector.PrepareSourceUnits;
var
  mFiles: TArray<string>;
  mFolder: string;
begin
  if (FSourceUnits <> nil) or (FLock = nil) then
  begin
    Exit;
  end;
  // Der Hintergrund-Thread des Serverstarts legt die Liste an; der Hauptthread liest sie erst danach.
  System.TMonitor.Enter(FLock);
  try
    if FSourceUnits <> nil then
    begin
      Exit;
    end;
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
    // Erst die fertige Liste veröffentlichen: Wer FSourceUnits ohne Sperre liest, sieht nil oder alles.
    FSourceUnits := TDpccIdeTypes.UnitNames(mFiles);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

class function TDpccIdeTypeCollector.SourceUnits: TDictionary<string, Boolean>;
begin
  if FSourceUnits = nil then
  begin
    PrepareSourceUnits;
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

/// <summary>Ist AModule noch geladen (LibModuleList)?</summary>
function ModuleLoaded(AModule: HINST): Boolean;
var
  mModule: PLibModule;
begin
  Result := False;
  mModule := LibModuleList;
  while mModule <> nil do
  begin
    if HINST(mModule.Instance) = AModule then
    begin
      Exit(True);
    end;
    mModule := mModule.Next;
  end;
end;

{ TIdeTypeRun }

constructor TIdeTypeRun.Create;
var
  mModule: PLibModule;
begin
  inherited Create;
  FSkipped := TDpccIdeTypeCollector.SkippedFolders;
  FTypes := TList<TDpccIdeType>.Create;
  FSignature := '';
  mModule := LibModuleList;
  while mModule <> nil do
  begin
    // Stand der geladenen Module: gleicher Stand, gleiche Typen.
    FSignature := FSignature + IntToHex(Int64(NativeUInt(mModule.Instance)), 1) + ';';
    if not TDpccIdeTypes.InFolders(GetModuleName(mModule.Instance), FSkipped) then
    begin
      FModules := FModules + [HINST(mModule.Instance)];
    end;
    mModule := mModule.Next;
  end;
  if (FSignature <> '') and (FSignature = TDpccIdeTypeCollector.FCacheSignature) then
  begin
    FResult := TDpccIdeTypeCollector.FCacheTypes;
    FFailed := TDpccIdeTypeCollector.FCacheFailed;
    FFromCache := True;
    FDone := True;
  end;
end;

destructor TIdeTypeRun.Destroy;
begin
  FTypes.Free;
  inherited;
end;

procedure TIdeTypeRun.StepModule(const APackages: TArray<TRttiPackage>; AModule: HINST);
var
  mPackage: TRttiPackage;
  mSources: TDictionary<string, Boolean>;
begin
  // Zwischen zwei Takten entladen: übergehen.
  if not ModuleLoaded(AModule) then
  begin
    Exit;
  end;
  for mPackage in APackages do
  begin
    if mPackage.Handle <> AModule then
    begin
      Continue;
    end;
    // L2: Packages der Installation nur mit ihren Units ohne Quelltext.
    mSources := nil;
    if TDpccIdeTypes.InFolders(mPackage.Name, [TDpccIdeTypeCollector.InstallationFolder]) then
    begin
      mSources := TDpccIdeTypeCollector.SourceUnits;
    end;
    // Ein Package mit beschädigter RTTI darf die übrigen nicht verhindern.
    try
      AddPackageTypes(mPackage, FTypes, mSources);
    except
      on Exception do
      begin
        Inc(FFailed);
      end;
    end;
    Break;
  end;
end;

procedure TIdeTypeRun.Finish;
begin
  FResult := FTypes.ToArray;
  FDone := True;
  TDpccIdeTypeCollector.Remember(FSignature, FResult, FFailed);
end;

function TIdeTypeRun.Step(ABudgetMs: Cardinal): Boolean;
var
  mWatch: TStopwatch;
  mContext: TRttiContext;
  mPackages: TArray<TRttiPackage>;
begin
  if FDone then
  begin
    Exit(True);
  end;
  mWatch := TStopwatch.StartNew;
  // Ein Kontext je Takt, nie über Takte hinweg: Dazwischen kann die IDE Packages entladen.
  mContext := TRttiContext.Create;
  try
    mPackages := nil;
    repeat
      if not FPaletteDone then
      begin
        FPaletteDone := True;
        try
          TDpccIdeTypeCollector.AddPalette(FSkipped, FTypes);
        except
          on Exception do
          begin
            Inc(FFailed);
          end;
        end;
      end
      else if FIndex < Length(FModules) then
      begin
        if mPackages = nil then
        begin
          mPackages := mContext.GetPackages;
        end;
        StepModule(mPackages, FModules[FIndex]);
        Inc(FIndex);
      end;
      if FPaletteDone and (FIndex >= Length(FModules)) then
      begin
        Finish;
      end;
    until FDone or (mWatch.ElapsedMilliseconds >= ABudgetMs);
  finally
    mPackages := nil;
    mContext.Free;
  end;
  Result := FDone;
end;

function TIdeTypeRun.Types: TArray<TDpccIdeType>;
begin
  Result := FResult;
end;

function TIdeTypeRun.Failed: Integer;
begin
  Result := FFailed;
end;

function TIdeTypeRun.Modules: Integer;
begin
  Result := Length(FModules);
end;

function TIdeTypeRun.FromCache: Boolean;
begin
  Result := FFromCache;
end;

end.
