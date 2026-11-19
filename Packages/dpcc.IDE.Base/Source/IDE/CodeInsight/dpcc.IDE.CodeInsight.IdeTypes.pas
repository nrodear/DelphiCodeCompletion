unit dpcc.IDE.CodeInsight.IdeTypes;

// Sammelt die Typen der geladenen Packages für dpcc/ideTypes (Hauptthread, beim Start der Sitzung). Zwei Quellen:
// - die RTTI jedes geladenen Packages (TRttiContext.GetPackages): alle öffentlichen Typen samt Unit, bei Klassen
//   mit Vorfahr; so kennt die IDE auch Typen aus Packages, die nur als BPL/DCP/DCU installiert sind;
// - die Komponenten der Palette (IOTAPackageServices, über RegisterComponents angemeldet) über GetClass.
// Die Packages von dpcc selbst bleiben außen vor (sie gehören nicht in fremde Projekte). Packages der Installation
// zählen seit L2 mit, aber nur ihre Units ohne Quelltext (DUnitX, FireDAC, IoT …): Units, deren .pas unter
// $(BDS)\source oder $(BDS)\OCX liegt, stehen im Index; Quelltext gewinnt. Die Liste dieser .pas entsteht einmal je
// Sitzung der IDE.
// Ohne Hänger (Start der Sitzung): Die Liste der .pas entsteht im Hintergrund-Thread des Serverstarts
// (PrepareSourceUnits, threadsicher). Die RTTI der Packages liest nur der Hauptthread (ein Worker darf das nicht:
// entladene Packages, nicht threadsichere IDE-Packages), aber in Takten mit Zeitbudget (StartRun, Step; die
// Schrittlogik TDpccSliceWalk steht in dpcc.Core.Lsp.IdeSlices):
//   - erst die Palette, Komponente für Komponente über mehrere Takte; Dateiname und Art jedes Moduls (dpcc,
//     Installation, sonst) einmal je Lauf statt je Komponente zweimal GetModuleName;
//   - dann die Packages, Typ für Typ: Das Budget gilt nach jedem Typ, ein großes Package (rtl, vcl, coreide,
//     FireDAC) verteilt sich auf mehrere Takte. Unteilbar bleiben je Package GetTypes (legt beim ersten Mal alle
//     TRttiType-Objekte an) und beim ersten Typ die Namenstabelle des Packages (IsPublicType, QualifiedName);
//   - ein TRttiContext und die Liste der Packages für den ganzen Lauf (TDpccRttiPackages): Der Kontext hält die
//     RTTI-Objekte zwischen den Takten am Leben. Entlädt die IDE dazwischen ein Package, gibt System.Rtti dessen
//     Objekte frei; jeder Takt vergleicht deshalb zuerst den Stand der Module (LibModuleList) und holt die Packages
//     bei einer Änderung neu, ohne alte Objekte anzufassen (entladene fallen weg, das laufende lädt seine Typen neu).
// Eindeutig machen, JSON und Senden laufen danach im Hintergrund (dpcc.IDE.CodeInsight.Manager.Session). Das
// Ergebnis (nur Texte, noch mit doppelten) bleibt je Stand der geladenen Module gemerkt: Ein Neustart des Servers ohne
// neue Packages schickt es sofort. Dazu die Zuordnung Unit → Package (UnitModules): Der Lauf der Mitglieder
// (dpcc.IDE.CodeInsight.IdeMembers) besucht damit nur die Packages der gewünschten Units.

interface

uses
  System.Rtti,
  System.Generics.Collections,
  dpcc.Core.Lsp.IdeTypes,
  dpcc.Core.Lsp.IdeSlices;

type
  /// <summary>Schrittweise Sammlung der IDE-Typen im Hauptthread.</summary>
  IDpccIdeTypeRun = interface
    ['{3F6B2C8E-9A41-4D7B-B0E5-6C2D8F1A4E93}']
    /// <summary>Höchstens etwa ABudgetMs arbeiten (Budget nach jedem Typ bzw. jeder Komponente geprüft, mindestens
    /// ein Schritt); True, wenn fertig.</summary>
    function Step(ABudgetMs: Cardinal): Boolean;
    /// <summary>Typen in der Reihenfolge der Quellen (Palette zuerst), noch mit doppelten: TDpccIdeTypes.Unique
    /// läuft im Hintergrund.</summary>
    function Types: TArray<TDpccIdeType>;
    /// <summary>Packages, deren RTTI nicht lesbar war.</summary>
    function Failed: Integer;
    /// <summary>Gelesene Module (ohne die von dpcc).</summary>
    function Modules: Integer;
    /// <summary>Ergebnis aus dem Merker (Stand der Module unverändert).</summary>
    function FromCache: Boolean;
    /// <summary>Takte dieses Laufs: Anzahl, Summe und längster.</summary>
    function Stats: TDpccSliceStats;
  end;

  /// <summary>Packages eines Laufs über mehrere Takte (nur Hauptthread): ein TRttiContext für den ganzen Lauf (hält
  /// die RTTI-Objekte zwischen den Takten am Leben) und die Packages außerhalb der übersprungenen Ordner in fester
  /// Reihenfolge. Freigeben am Ende oder beim Abbruch des Laufs.</summary>
  TDpccRttiPackages = class
  private
    FContext: TRttiContext;
    FHandles: TArray<HINST>;
    FNames: TArray<string>;
    FPackages: TArray<TRttiPackage>;
    FStamp: string;
  public
    /// <summary>Packages außerhalb von ASkipped; AFilter (Dateinamen groß, nil = alle): nur diese.</summary>
    constructor Create(const ASkipped: TArray<string>; const AFilter: TDictionary<string, Boolean>);
    destructor Destroy; override;
    /// <summary>Zu Beginn jedes weiteren Takts: True, wenn die IDE seit dem letzten Mal Module geladen oder entladen
    /// hat. Dann sind alle RTTI-Objekte früherer Takte ungültig (nicht mehr anfassen); Package liefert die
    /// aktuellen.</summary>
    function Refresh: Boolean;
    function Count: Integer;
    /// <summary>Package AIndex; nil, wenn es inzwischen entladen ist.</summary>
    function Package(AIndex: Integer): TRttiPackage;
    /// <summary>Dateiname des Packages AIndex.</summary>
    function FileName(AIndex: Integer): string;
    /// <summary>Stand der geladenen Module (Handles aus LibModuleList).</summary>
    class function ModuleStamp: string; static;
  end;

  TDpccIdeTypeCollector = class
  private
    class var FSourceUnits: TDictionary<string, Boolean>;
    class var FLock: TObject;
    /// <summary>Gemerktes Ergebnis (StartRun) und der Stand der Module, zu dem es gehört.</summary>
    class var FCacheSignature: string;
    class var FCacheTypes: TArray<TDpccIdeType>;
    class var FCacheFailed: Integer;
    class var FCacheModules: Integer;
    /// <summary>Unit → Packages aus dem letzten fertigen Lauf.</summary>
    class var FUnitModules: TDpccUnitModules;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Liste der .pas (SourceUnits) anlegen, falls noch nicht da; threadsicher, für den Hintergrund-Thread
    /// des Serverstarts.</summary>
    class procedure PrepareSourceUnits; static;
    /// <summary>Neuer Lauf über die geladenen Module (nur Hauptthread); Step im Hauptthread aufrufen.</summary>
    class function StartRun: IDpccIdeTypeRun; static;
    /// <summary>Ergebnis eines fertigen Laufs merken (nur Hauptthread); übernimmt AUnitModules (nil: die bisherige
    /// Zuordnung bleibt).</summary>
    class procedure Remember(const ASignature: string; const ATypes: TArray<TDpccIdeType>; AFailed, AModules: Integer;
      AUnitModules: TDpccUnitModules); static;
    /// <summary>Unit → Packages aus dem letzten fertigen Lauf der IDE-Typen; nil vorher. Gehört der Klasse, nur
    /// Hauptthread.</summary>
    class function UnitModules: TDpccUnitModules; static;
    /// <summary>Ordner, deren Packages nicht zählen: dpcc (L2: die Installation zählt mit, siehe SourceUnits).
    /// </summary>
    class function SkippedFolders: TArray<string>; static;
    /// <summary>Ordner der Installation (bds.exe liegt in &lt;Installation&gt;\bin).</summary>
    class function InstallationFolder: string; static;
    /// <summary>Unit-Namen (groß) aller .pas unter $(BDS)\source und $(BDS)\OCX; einmal je Sitzung gelistet.
    /// Gehört der Klasse.</summary>
    class function SourceUnits: TDictionary<string, Boolean>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  ToolsAPI;

{$SCOPEDENUMS ON}

type
  /// <summary>Art des Moduls einer Komponente der Palette.</summary>
  TDpccModuleKind = (Skipped, Installed, Other);
{$SCOPEDENUMS OFF}

type
  /// <summary>Modul einer Komponente der Palette, einmal je Lauf ermittelt.</summary>
  TDpccPaletteModule = record
    Kind: TDpccModuleKind;
    FileName: string;
  end;

  /// <summary>Lauf von StartRun: erst die Palette, dann die Packages, Typ für Typ bis zum Zeitbudget.</summary>
  TIdeTypeRun = class(TInterfacedObject, IDpccIdeTypeRun)
  private
    FSkipped: TArray<string>;
    FInstallation: string;
    FSignature: string;
    FDone: Boolean;
    FFromCache: Boolean;
    FTypes: TList<TDpccIdeType>;
    FResult: TArray<TDpccIdeType>;
    FFailed: Integer;
    FModuleCount: Integer;
    FStats: TDpccSliceStats;
    FUnitModules: TDpccUnitModules;
    // Palette: die Dienste nur während eines Takts, nie über Takte hinweg.
    FServices: IOTAPackageServices;
    FPalette: TDpccSliceWalk;
    FPaletteDone: Boolean;
    FPaletteFailed: Boolean;
    FModuleInfos: TDictionary<HINST, TDpccPaletteModule>;
    // RTTI der Packages: Kontext und Packages für den ganzen Lauf, die Typen des laufenden Packages.
    FPackages: TDpccRttiPackages;
    FWalk: TDpccSliceWalk;
    FCurrentTypes: TArray<TRttiType>;
    FCurrentModule: string;
    FCurrentSources: TDictionary<string, Boolean>;
    FCurrentFailed: Boolean;
    /// <summary>Dateiname und Art des Moduls AModule, je Lauf einmal ermittelt.</summary>
    function ModuleInfo(AModule: HINST): TDpccPaletteModule;
    /// <summary>Komponente AName der Palette als Typ samt Modul; False, wenn ihre Klasse nicht angemeldet ist, in
    /// einem Package von dpcc liegt oder (Installation) Quelltext hat.</summary>
    function PaletteType(const AName: string; out AType: TDpccIdeType; out AModule: string): Boolean;
    function LoadPalette(AOuter: Integer): Integer;
    procedure VisitPalette(AOuter, AInner: Integer);
    function LoadPackage(AOuter: Integer): Integer;
    procedure VisitType(AOuter, AInner: Integer);
    procedure StepPalette(const AExhausted: TFunc<Boolean>);
    procedure StepPackages(const AExhausted: TFunc<Boolean>);
    /// <summary>Kontext, Packages und gehaltene RTTI-Objekte freigeben (Ende oder Abbruch des Laufs).</summary>
    procedure ReleaseRtti;
    procedure Finish;
  public
    constructor Create;
    destructor Destroy; override;
    function Step(ABudgetMs: Cardinal): Boolean;
    function Types: TArray<TDpccIdeType>;
    function Failed: Integer;
    function Modules: Integer;
    function FromCache: Boolean;
    function Stats: TDpccSliceStats;
  end;

class constructor TDpccIdeTypeCollector.Create;
begin
  FLock := TObject.Create;
end;

class destructor TDpccIdeTypeCollector.Destroy;
begin
  FreeAndNil(FSourceUnits);
  FreeAndNil(FUnitModules);
  FCacheTypes := nil;
  FreeAndNil(FLock);
end;

class procedure TDpccIdeTypeCollector.Remember(const ASignature: string; const ATypes: TArray<TDpccIdeType>;
  AFailed, AModules: Integer; AUnitModules: TDpccUnitModules);
begin
  FCacheSignature := ASignature;
  FCacheTypes := ATypes;
  FCacheFailed := AFailed;
  FCacheModules := AModules;
  if AUnitModules <> nil then
  begin
    FUnitModules.Free;
    FUnitModules := AUnitModules;
  end;
end;

class function TDpccIdeTypeCollector.UnitModules: TDpccUnitModules;
begin
  Result := FUnitModules;
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

{ TDpccRttiPackages }

class function TDpccRttiPackages.ModuleStamp: string;
var
  mModule: PLibModule;
  mStamp: TStringBuilder;
begin
  mStamp := TStringBuilder.Create;
  try
    mModule := LibModuleList;
    while mModule <> nil do
    begin
      mStamp.Append(IntToHex(Int64(NativeUInt(mModule.Instance)), 1)).Append(';');
      mModule := mModule.Next;
    end;
    Result := mStamp.ToString;
  finally
    mStamp.Free;
  end;
end;

constructor TDpccRttiPackages.Create(const ASkipped: TArray<string>; const AFilter: TDictionary<string, Boolean>);
var
  mPackage: TRttiPackage;
  mName: string;
begin
  inherited Create;
  FStamp := ModuleStamp;
  for mPackage in FContext.GetPackages do
  begin
    mName := mPackage.Name;
    if TDpccIdeTypes.InFolders(mName, ASkipped) or
      ((AFilter <> nil) and not AFilter.ContainsKey(UpperCase(mName))) then
    begin
      Continue;
    end;
    FHandles := FHandles + [mPackage.Handle];
    FNames := FNames + [mName];
    FPackages := FPackages + [mPackage];
  end;
end;

destructor TDpccRttiPackages.Destroy;
begin
  // Erst die Verweise, dann der Kontext: Mit dem letzten Kontext gibt System.Rtti seine Objekte frei.
  FPackages := nil;
  FContext.Free;
  inherited;
end;

function TDpccRttiPackages.Refresh: Boolean;
var
  mStamp: string;
  mFresh: TArray<TRttiPackage>;
  mPackage: TRttiPackage;
  mIndex: Integer;
begin
  mStamp := ModuleStamp;
  Result := mStamp <> FStamp;
  if not Result then
  begin
    Exit;
  end;
  FStamp := mStamp;
  // Die alten Objekte nicht anfassen: System.Rtti hat die entladener Packages schon freigegeben. Neue Packages
  // bleiben außen vor (der Lauf gilt dem Stand an seinem Anfang), entladene fallen weg.
  mFresh := FContext.GetPackages;
  for mIndex := 0 to High(FHandles) do
  begin
    FPackages[mIndex] := nil;
    for mPackage in mFresh do
    begin
      if mPackage.Handle = FHandles[mIndex] then
      begin
        FPackages[mIndex] := mPackage;
        Break;
      end;
    end;
  end;
end;

function TDpccRttiPackages.Count: Integer;
begin
  Result := Length(FPackages);
end;

function TDpccRttiPackages.Package(AIndex: Integer): TRttiPackage;
begin
  Result := FPackages[AIndex];
end;

function TDpccRttiPackages.FileName(AIndex: Integer): string;
begin
  Result := FNames[AIndex];
end;

{ TIdeTypeRun }

constructor TIdeTypeRun.Create;
begin
  inherited Create;
  FTypes := TList<TDpccIdeType>.Create;
  // Stand der geladenen Module: gleicher Stand, gleiche Typen.
  FSignature := TDpccRttiPackages.ModuleStamp;
  if (FSignature <> '') and (FSignature = TDpccIdeTypeCollector.FCacheSignature) then
  begin
    FResult := TDpccIdeTypeCollector.FCacheTypes;
    FFailed := TDpccIdeTypeCollector.FCacheFailed;
    FModuleCount := TDpccIdeTypeCollector.FCacheModules;
    FFromCache := True;
    FDone := True;
    Exit;
  end;
  FSkipped := TDpccIdeTypeCollector.SkippedFolders;
  // Einmal je Lauf: ParamStr und GetModuleName fragen das Betriebssystem.
  FInstallation := TDpccIdeTypeCollector.InstallationFolder;
  FUnitModules := TDpccUnitModules.Create;
  FModuleInfos := TDictionary<HINST, TDpccPaletteModule>.Create;
end;

destructor TIdeTypeRun.Destroy;
begin
  // Auch beim Abbruch (Sitzung gewechselt, Entladen): Kontext und Packages hier freigeben.
  ReleaseRtti;
  FreeAndNil(FPalette);
  FreeAndNil(FModuleInfos);
  FreeAndNil(FUnitModules);
  FreeAndNil(FTypes);
  inherited;
end;

procedure TIdeTypeRun.ReleaseRtti;
begin
  FCurrentTypes := nil;
  FCurrentSources := nil;
  FreeAndNil(FWalk);
  FreeAndNil(FPackages);
end;

function TIdeTypeRun.ModuleInfo(AModule: HINST): TDpccPaletteModule;
begin
  if FModuleInfos.TryGetValue(AModule, Result) then
  begin
    Exit;
  end;
  Result.FileName := GetModuleName(AModule);
  if TDpccIdeTypes.InFolders(Result.FileName, FSkipped) then
  begin
    Result.Kind := TDpccModuleKind.Skipped;
  end
  else if TDpccIdeTypes.InFolders(Result.FileName, [FInstallation]) then
  begin
    Result.Kind := TDpccModuleKind.Installed;
  end
  else
  begin
    Result.Kind := TDpccModuleKind.Other;
  end;
  FModuleInfos.Add(AModule, Result);
end;

function TIdeTypeRun.PaletteType(const AName: string; out AType: TDpccIdeType; out AModule: string): Boolean;
var
  mClass: TPersistentClass;
  mInfo: TDpccPaletteModule;
  mParent: string;
begin
  AType := Default(TDpccIdeType);
  AModule := '';
  // GetClass sucht linear in den angemeldeten Klassen; je Komponente einmal, das Budget gilt danach.
  mClass := GetClass(AName);
  if mClass = nil then
  begin
    Exit(False);
  end;
  mInfo := ModuleInfo(FindClassHInstance(mClass));
  // L2: Komponenten der Installation nur aus Units ohne Quelltext.
  if (mInfo.Kind = TDpccModuleKind.Skipped) or ((mInfo.Kind = TDpccModuleKind.Installed) and
    TDpccIdeTypeCollector.SourceUnits.ContainsKey(UpperCase(mClass.UnitName))) then
  begin
    Exit(False);
  end;
  AModule := mInfo.FileName;
  mParent := '';
  if mClass.ClassParent <> nil then
  begin
    mParent := mClass.ClassParent.UnitName + '.' + mClass.ClassParent.ClassName;
  end;
  Result := TDpccIdeType.FromQualified(mClass.UnitName + '.' + mClass.ClassName, mParent, AType);
end;

function TIdeTypeRun.LoadPalette(AOuter: Integer): Integer;
begin
  Result := 0;
  try
    // Zwischen zwei Takten kann sich die Palette ändern (Package installiert oder entfernt).
    if AOuter < FServices.PackageCount then
    begin
      Result := FServices.ComponentCount[AOuter];
    end;
  except
    on Exception do
    begin
      if not FPaletteFailed then
      begin
        FPaletteFailed := True;
        Inc(FFailed);
      end;
    end;
  end;
end;

procedure TIdeTypeRun.VisitPalette(AOuter, AInner: Integer);
var
  mType: TDpccIdeType;
  mModule: string;
begin
  try
    if (AOuter < FServices.PackageCount) and (AInner < FServices.ComponentCount[AOuter]) and
      PaletteType(FServices.ComponentNames[AOuter, AInner], mType, mModule) then
    begin
      FTypes.Add(mType);
      FUnitModules.Add(mType.UnitName, mModule);
    end;
  except
    on Exception do
    begin
      if not FPaletteFailed then
      begin
        FPaletteFailed := True;
        Inc(FFailed);
      end;
    end;
  end;
end;

function TIdeTypeRun.LoadPackage(AOuter: Integer): Integer;
var
  mPackage: TRttiPackage;
begin
  FCurrentTypes := nil;
  FCurrentSources := nil;
  FCurrentFailed := False;
  FCurrentModule := FPackages.FileName(AOuter);
  mPackage := FPackages.Package(AOuter);
  // Inzwischen entladen: übergehen.
  if mPackage = nil then
  begin
    Exit(0);
  end;
  // L2: Packages der Installation nur mit ihren Units ohne Quelltext.
  if TDpccIdeTypes.InFolders(FCurrentModule, [FInstallation]) then
  begin
    FCurrentSources := TDpccIdeTypeCollector.SourceUnits;
  end;
  // Ein Aufruf, nicht teilbar; gehalten bis zum nächsten Package (oder neu geholt, wenn Module wechseln). Ein
  // Package mit beschädigter RTTI darf die übrigen nicht verhindern.
  try
    FCurrentTypes := mPackage.GetTypes;
  except
    on Exception do
    begin
      FCurrentFailed := True;
      Inc(FFailed);
    end;
  end;
  Result := Length(FCurrentTypes);
end;

procedure TIdeTypeRun.VisitType(AOuter, AInner: Integer);
var
  mRttiType: TRttiType;
  mType: TDpccIdeType;
begin
  if AInner >= Length(FCurrentTypes) then
  begin
    Exit;
  end;
  try
    mRttiType := FCurrentTypes[AInner];
    if (mRttiType <> nil) and mRttiType.IsPublicType and
      TDpccIdeType.FromQualified(mRttiType.QualifiedName, ParentOf(mRttiType), mType) and
      TDpccIdeTypes.KeepInstalled(mType, FCurrentSources) then
    begin
      FTypes.Add(mType);
      FUnitModules.Add(mType.UnitName, FCurrentModule);
    end;
  except
    // Je Package höchstens einmal gezählt; die übrigen Typen des Packages zählen weiter.
    on Exception do
    begin
      if not FCurrentFailed then
      begin
        FCurrentFailed := True;
        Inc(FFailed);
      end;
    end;
  end;
end;

procedure TIdeTypeRun.StepPalette(const AExhausted: TFunc<Boolean>);
begin
  if not Supports(BorlandIDEServices, IOTAPackageServices, FServices) then
  begin
    FPaletteDone := True;
    Exit;
  end;
  if FPalette = nil then
  begin
    FPalette := TDpccSliceWalk.Create(FServices.PackageCount);
  end;
  FPaletteDone := FPalette.Run(LoadPalette, VisitPalette, AExhausted);
end;

procedure TIdeTypeRun.StepPackages(const AExhausted: TFunc<Boolean>);
begin
  if FPackages = nil then
  begin
    // Erster Takt der RTTI: Kontext und Packages für den ganzen Lauf.
    FPackages := TDpccRttiPackages.Create(FSkipped, nil);
    FModuleCount := FPackages.Count;
    FWalk := TDpccSliceWalk.Create(FPackages.Count);
    if AExhausted() then
    begin
      Exit;
    end;
  end
  else if FPackages.Refresh then
  begin
    // Module geladen oder entladen: Die Typen des laufenden Packages neu holen, an derselben Stelle weiter.
    FCurrentTypes := nil;
    FWalk.Reload;
  end;
  if FWalk.Run(LoadPackage, VisitType, AExhausted) then
  begin
    Finish;
  end;
end;

procedure TIdeTypeRun.Finish;
begin
  ReleaseRtti;
  // Eindeutig machen (Palette und RTTI melden dieselben Komponenten) erst im Hintergrund.
  FResult := FTypes.ToArray;
  FTypes.Clear;
  FDone := True;
  // Die Zuordnung Unit → Package gehört ab hier der Klasse.
  TDpccIdeTypeCollector.Remember(FSignature, FResult, FFailed, FModuleCount, FUnitModules);
  FUnitModules := nil;
end;

function TIdeTypeRun.Step(ABudgetMs: Cardinal): Boolean;
var
  mWatch: TStopwatch;
  mBudgetMs: Cardinal;
  mExhausted: TFunc<Boolean>;
begin
  if FDone then
  begin
    Exit(True);
  end;
  mWatch := TStopwatch.StartNew;
  mBudgetMs := ABudgetMs;
  // Nach jeder Komponente bzw. jedem Typ gefragt (TDpccSliceWalk), nicht erst nach einem ganzen Package.
  mExhausted :=
    function: Boolean
    begin
      Result := mWatch.ElapsedMilliseconds >= mBudgetMs;
    end;
  try
    if not FPaletteDone then
    begin
      StepPalette(mExhausted);
    end
    else
    begin
      StepPackages(mExhausted);
    end;
  finally
    // Die Dienste der IDE nie über einen Takt hinaus halten.
    FServices := nil;
    FStats.Add(mWatch.ElapsedMilliseconds);
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
  Result := FModuleCount;
end;

function TIdeTypeRun.FromCache: Boolean;
begin
  Result := FFromCache;
end;

function TIdeTypeRun.Stats: TDpccSliceStats;
begin
  Result := FStats;
end;

end.
