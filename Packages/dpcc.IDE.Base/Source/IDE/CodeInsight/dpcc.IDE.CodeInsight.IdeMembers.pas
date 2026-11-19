unit dpcc.IDE.CodeInsight.IdeMembers;

// Sammelt für dpcc/ideMembers die Mitglieder der Typen in Units ohne Quelltext (Hauptthread, auf Nachfrage des
// Servers nach dem Index). Quelle ist die RTTI der geladenen Packages (seit L2 auch die der Installation; der Server
// fragt nur nach Units ohne Quelltext): bei Klassen
// Vorfahr, Interfaces, Felder, Properties (auch Array-Properties) und Methoden mit Parametern, sichtbar ab
// protected; bei Interfaces und Records ebenso, bei Aufzählungen die Werte. Was die RTTI nicht kennt, fehlt:
// Methoden ohne erweiterte RTTI ({$RTTI EXPLICIT METHODS([])}), Vorgabewerte von Parametern, private Mitglieder.
// Ohne Hänger: Die RTTI liest nur der Hauptthread, aber in Takten mit Zeitbudget (StartRun, Step) wie die IDE-Typen
// (dpcc.IDE.CodeInsight.IdeTypes): ein TRttiContext und die Packages für den ganzen Lauf (TDpccRttiPackages, bei
// geladenen oder entladenen Modulen neu geholt), das Budget nach jedem Typ (TDpccSliceWalk). Besucht werden nur die
// Packages, die der Lauf der IDE-Typen für die gewünschten Units gemerkt hat (UnitModules); ist eine Unit unbekannt
// oder ihr Package nicht mehr geladen, alle. Unteilbar bleiben je Package GetTypes, die Namenstabelle beim ersten Typ
// und ein einzelner Typ samt Mitgliedern (Detail). JSON und Senden laufen danach im Hintergrund
// (dpcc.IDE.CodeInsight.Manager.Session).

interface

uses
  System.Rtti,
  dpcc.Core.Lsp.IdeMembers,
  dpcc.Core.Lsp.IdeSlices;

type
  /// <summary>Schrittweise Sammlung der Mitglieder im Hauptthread.</summary>
  IDpccIdeMemberRun = interface
    ['{4DA400A1-130E-4884-82E4-7F54A21FC676}']
    /// <summary>Höchstens etwa ABudgetMs arbeiten (Budget nach jedem Typ geprüft, mindestens ein Schritt); True,
    /// wenn fertig.</summary>
    function Step(ABudgetMs: Cardinal): Boolean;
    /// <summary>Typen samt Mitgliedern der gewünschten Units (reine Datensätze).</summary>
    function Details: TArray<TDpccIdeTypeDetail>;
    /// <summary>Packages, deren RTTI nicht lesbar war.</summary>
    function Failed: Integer;
    /// <summary>Gewünschte Units.</summary>
    function UnitCount: Integer;
    /// <summary>Besuchte Packages.</summary>
    function Packages: Integer;
    /// <summary>Nur die Packages der gewünschten Units besucht (sonst alle)?</summary>
    function Filtered: Boolean;
    /// <summary>Takte dieses Laufs: Anzahl, Summe und längster.</summary>
    function Stats: TDpccSliceStats;
  end;

  TDpccIdeMemberCollector = class
  private
    class function Detail(AType: TRttiType; const AUnit: string; out ADetail: TDpccIdeTypeDetail): Boolean;
      static;
  public
    /// <summary>Neuer Lauf für die Typen samt Mitgliedern der Units AUnits aus den geladenen Packages (ohne die von
    /// dpcc); nur im Hauptthread, Step im Hauptthread aufrufen.</summary>
    class function StartRun(const AUnits: TArray<string>): IDpccIdeMemberRun; static;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  System.Diagnostics,
  System.Generics.Collections,
  dpcc.Core.Lsp.IdeTypes,
  dpcc.IDE.CodeInsight.IdeTypes;

/// <summary>Typ als Text mit Unit (System.Integer); '' ohne Typ oder bei namenlosen Typen.</summary>
function TypeText(AType: TRttiType): string;
begin
  Result := '';
  if AType = nil then
  begin
    Exit;
  end;
  try
    if AType.IsPublicType then
    begin
      Result := AType.QualifiedName;
    end
    else
    begin
      Result := AType.Name;
    end;
  except
    on Exception do
    begin
      Result := AType.Name;
    end;
  end;
  // Namenlose Typen (array of …, Mengen im Parameter) heißen ':…'.
  if Pos(':', Result) > 0 then
  begin
    Result := '';
  end;
end;

function VisibilityText(AVisibility: TMemberVisibility): string;
begin
  case AVisibility of
    mvProtected:
      Result := 'protected';
    mvPublic:
      Result := 'public';
    mvPublished:
      Result := 'published';
  else
    Result := '';
  end;
end;

function FlagText(AFlags: TParamFlags): string;
begin
  Result := '';
  if pfVar in AFlags then
  begin
    Result := 'var';
  end
  else if pfConst in AFlags then
  begin
    Result := 'const';
  end
  else if pfOut in AFlags then
  begin
    Result := 'out';
  end;
end;

function ParamsOf(AMethod: TRttiMethod): TArray<TDpccIdeParam>;
var
  mParam: TRttiParameter;
begin
  Result := nil;
  for mParam in AMethod.GetParameters do
  begin
    Result := Result + [TDpccIdeParam.Make(mParam.Name, TypeText(mParam.ParamType), FlagText(mParam.Flags))];
  end;
end;

/// <summary>Art einer Methode für die Ersatz-Unit; False für Klassenkonstruktoren und Operatoren.</summary>
function MethodKindOf(AMethod: TRttiMethod; out AKind: string; out AStatic: Boolean): Boolean;
begin
  AStatic := AMethod.MethodKind in [mkClassProcedure, mkClassFunction];
  case AMethod.MethodKind of
    mkProcedure, mkSafeProcedure, mkClassProcedure:
      AKind := 'procedure';
    mkFunction, mkSafeFunction, mkClassFunction:
      AKind := 'function';
    mkConstructor:
      AKind := 'constructor';
    mkDestructor:
      AKind := 'destructor';
  else
    AKind := '';
  end;
  Result := AKind <> '';
end;

/// <summary>Mitglied mit Art, Name und Sichtbarkeit; False, wenn es nicht sichtbar ist.</summary>
function NewMember(AMember: TRttiMember; const AKind: string; out AResult: TDpccIdeMember): Boolean;
begin
  AResult := Default(TDpccIdeMember);
  AResult.Kind := AKind;
  AResult.Name := AMember.Name;
  AResult.Visibility := VisibilityText(AMember.Visibility);
  Result := (AResult.Visibility <> '') and IsValidIdent(AResult.Name);
end;

procedure AddFields(AType: TRttiType; AMembers: TList<TDpccIdeMember>);
var
  mField: TRttiField;
  mMember: TDpccIdeMember;
begin
  for mField in AType.GetDeclaredFields do
  begin
    if NewMember(mField, 'field', mMember) then
    begin
      mMember.TypeName := TypeText(mField.FieldType);
      AMembers.Add(mMember);
    end;
  end;
end;

procedure AddProperties(AType: TRttiType; AMembers: TList<TDpccIdeMember>);
var
  mProperty: TRttiProperty;
  mIndexed: TRttiIndexedProperty;
  mMember: TDpccIdeMember;
begin
  for mProperty in AType.GetDeclaredProperties do
  begin
    if NewMember(mProperty, 'property', mMember) then
    begin
      mMember.TypeName := TypeText(mProperty.PropertyType);
      AMembers.Add(mMember);
    end;
  end;
  for mIndexed in AType.GetDeclaredIndexedProperties do
  begin
    if NewMember(mIndexed, 'property', mMember) then
    begin
      mMember.TypeName := TypeText(mIndexed.PropertyType);
      mMember.IsDefault := mIndexed.IsDefault;
      // Die Indexparameter sind die Parameter des Lesezugriffs.
      if mIndexed.ReadMethod <> nil then
      begin
        mMember.Index := ParamsOf(mIndexed.ReadMethod);
      end;
      AMembers.Add(mMember);
    end;
  end;
end;

procedure AddMethods(AType: TRttiType; AMembers: TList<TDpccIdeMember>);
var
  mMethod: TRttiMethod;
  mMember: TDpccIdeMember;
  mKind: string;
  mStatic: Boolean;
begin
  for mMethod in AType.GetDeclaredMethods do
  begin
    if MethodKindOf(mMethod, mKind, mStatic) and NewMember(mMethod, mKind, mMember) then
    begin
      mMember.IsStatic := mStatic;
      mMember.Params := ParamsOf(mMethod);
      if mMethod.ReturnType <> nil then
      begin
        mMember.TypeName := TypeText(mMethod.ReturnType);
      end;
      AMembers.Add(mMember);
    end;
  end;
end;

function MembersOf(AType: TRttiType): TArray<TDpccIdeMember>;
var
  mMembers: TList<TDpccIdeMember>;
begin
  mMembers := TList<TDpccIdeMember>.Create;
  try
    AddFields(AType, mMembers);
    AddProperties(AType, mMembers);
    AddMethods(AType, mMembers);
    Result := mMembers.ToArray;
  finally
    mMembers.Free;
  end;
end;

function InterfacesOf(AType: TRttiInstanceType): TArray<string>;
var
  mInterface: TRttiInterfaceType;
  mName: string;
begin
  Result := nil;
  for mInterface in AType.GetImplementedInterfaces do
  begin
    mName := TypeText(mInterface);
    if mName <> '' then
    begin
      Result := Result + [mName];
    end;
  end;
end;

function EnumValuesOf(AType: TRttiEnumerationType): TArray<string>;
var
  mValue: Integer;
begin
  Result := nil;
  for mValue := AType.MinValue to AType.MaxValue do
  begin
    Result := Result + [GetEnumName(AType.Handle, mValue)];
  end;
end;

/// <summary>Art des Typs für die Ersatz-Unit; '' für Arten ohne Mitglieder (Mengen, Zeiger, Aliase).</summary>
function KindOf(AType: TRttiType): string;
begin
  if AType is TRttiInstanceType then
  begin
    Result := 'class';
  end
  else if AType is TRttiInterfaceType then
  begin
    Result := 'interface';
  end
  else if AType is TRttiRecordType then
  begin
    Result := 'record';
  end
  else if (AType is TRttiEnumerationType) and (AType.Handle <> TypeInfo(Boolean)) then
  begin
    Result := 'enum';
  end
  else
  begin
    Result := '';
  end;
end;

class function TDpccIdeMemberCollector.Detail(AType: TRttiType; const AUnit: string;
  out ADetail: TDpccIdeTypeDetail): Boolean;
begin
  ADetail := Default(TDpccIdeTypeDetail);
  ADetail.UnitName := AUnit;
  ADetail.Name := AType.Name;
  ADetail.Kind := KindOf(AType);
  Result := (ADetail.Kind <> '') and IsValidIdent(ADetail.Name);
  if not Result then
  begin
    Exit;
  end;
  if ADetail.Kind = 'enum' then
  begin
    ADetail.Values := EnumValuesOf(TRttiEnumerationType(AType));
    Exit;
  end;
  if AType.BaseType <> nil then
  begin
    ADetail.Parent := TypeText(AType.BaseType);
  end;
  if AType is TRttiInstanceType then
  begin
    ADetail.Interfaces := InterfacesOf(TRttiInstanceType(AType));
  end;
  ADetail.Members := MembersOf(AType);
end;

type
  /// <summary>Lauf von StartRun: die Packages der gewünschten Units, Typ für Typ bis zum Zeitbudget.</summary>
  TIdeMemberRun = class(TInterfacedObject, IDpccIdeMemberRun)
  private
    FUnitCount: Integer;
    FSkipped: TArray<string>;
    /// <summary>Gewünschte Units (groß).</summary>
    FWanted: TDictionary<string, Boolean>;
    /// <summary>Dateinamen (groß) der zu besuchenden Packages; nil = alle.</summary>
    FFilter: TDictionary<string, Boolean>;
    FPackages: TDpccRttiPackages;
    FPackageCount: Integer;
    FWalk: TDpccSliceWalk;
    FCurrentTypes: TArray<TRttiType>;
    FCurrentFailed: Boolean;
    FDetails: TList<TDpccIdeTypeDetail>;
    FResult: TArray<TDpccIdeTypeDetail>;
    FFailed: Integer;
    FDone: Boolean;
    FStats: TDpccSliceStats;
    function LoadPackage(AOuter: Integer): Integer;
    procedure VisitType(AOuter, AInner: Integer);
    /// <summary>Erster Takt: Kontext und Packages für den ganzen Lauf.</summary>
    procedure OpenPackages;
    procedure ReleaseRtti;
    procedure Finish;
  public
    constructor Create(const AUnits: TArray<string>);
    destructor Destroy; override;
    function Step(ABudgetMs: Cardinal): Boolean;
    function Details: TArray<TDpccIdeTypeDetail>;
    function Failed: Integer;
    function UnitCount: Integer;
    function Packages: Integer;
    function Filtered: Boolean;
    function Stats: TDpccSliceStats;
  end;

class function TDpccIdeMemberCollector.StartRun(const AUnits: TArray<string>): IDpccIdeMemberRun;
begin
  Result := TIdeMemberRun.Create(AUnits);
end;

{ TIdeMemberRun }

constructor TIdeMemberRun.Create(const AUnits: TArray<string>);
var
  mUnit: string;
  mModule: string;
  mModules: TArray<string>;
begin
  inherited Create;
  FUnitCount := Length(AUnits);
  FSkipped := TDpccIdeTypeCollector.SkippedFolders;
  FDetails := TList<TDpccIdeTypeDetail>.Create;
  FWanted := TDictionary<string, Boolean>.Create;
  for mUnit in AUnits do
  begin
    FWanted.AddOrSetValue(UpperCase(mUnit), True);
  end;
  // Packages der Units aus dem Lauf der IDE-Typen; ist eine Unit unbekannt, alle (gestückelt wie sonst).
  if (TDpccIdeTypeCollector.UnitModules <> nil) and
    TDpccIdeTypeCollector.UnitModules.ModulesOf(AUnits, mModules) then
  begin
    FFilter := TDictionary<string, Boolean>.Create;
    for mModule in mModules do
    begin
      FFilter.AddOrSetValue(UpperCase(mModule), True);
    end;
  end;
end;

destructor TIdeMemberRun.Destroy;
begin
  // Auch beim Abbruch (Sitzung gewechselt, Entladen): Kontext und Packages hier freigeben.
  ReleaseRtti;
  FreeAndNil(FFilter);
  FreeAndNil(FWanted);
  FreeAndNil(FDetails);
  inherited;
end;

procedure TIdeMemberRun.ReleaseRtti;
begin
  FCurrentTypes := nil;
  FreeAndNil(FWalk);
  FreeAndNil(FPackages);
end;

procedure TIdeMemberRun.OpenPackages;
begin
  FPackages := TDpccRttiPackages.Create(FSkipped, FFilter);
  if (FFilter <> nil) and (FPackages.Count < FFilter.Count) then
  begin
    // Ein gemerktes Package ist nicht mehr geladen: wie ohne Zuordnung alle besuchen.
    FreeAndNil(FPackages);
    FreeAndNil(FFilter);
    FPackages := TDpccRttiPackages.Create(FSkipped, nil);
  end;
  FPackageCount := FPackages.Count;
  FWalk := TDpccSliceWalk.Create(FPackages.Count);
end;

function TIdeMemberRun.LoadPackage(AOuter: Integer): Integer;
var
  mPackage: TRttiPackage;
begin
  FCurrentTypes := nil;
  FCurrentFailed := False;
  mPackage := FPackages.Package(AOuter);
  // Inzwischen entladen: übergehen.
  if mPackage = nil then
  begin
    Exit(0);
  end;
  // Ein Aufruf, nicht teilbar. Ein Package mit beschädigter RTTI darf die übrigen nicht verhindern.
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

procedure TIdeMemberRun.VisitType(AOuter, AInner: Integer);
var
  mRttiType: TRttiType;
  mType: TDpccIdeType;
  mDetail: TDpccIdeTypeDetail;
begin
  if AInner >= Length(FCurrentTypes) then
  begin
    Exit;
  end;
  try
    mRttiType := FCurrentTypes[AInner];
    if (mRttiType <> nil) and mRttiType.IsPublicType and
      TDpccIdeType.FromQualified(mRttiType.QualifiedName, '', mType) and
      FWanted.ContainsKey(UpperCase(mType.UnitName)) and
      TDpccIdeMemberCollector.Detail(mRttiType, mType.UnitName, mDetail) then
    begin
      FDetails.Add(mDetail);
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

procedure TIdeMemberRun.Finish;
begin
  ReleaseRtti;
  FResult := FDetails.ToArray;
  FDetails.Clear;
  FDone := True;
end;

function TIdeMemberRun.Step(ABudgetMs: Cardinal): Boolean;
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
  // Nach jedem Typ gefragt (TDpccSliceWalk), nicht erst nach einem ganzen Package.
  mExhausted :=
    function: Boolean
    begin
      Result := mWatch.ElapsedMilliseconds >= mBudgetMs;
    end;
  try
    if FPackages = nil then
    begin
      OpenPackages;
    end
    else if FPackages.Refresh then
    begin
      // Module geladen oder entladen: Die Typen des laufenden Packages neu holen, an derselben Stelle weiter.
      FCurrentTypes := nil;
      FWalk.Reload;
    end;
    if not mExhausted() and FWalk.Run(LoadPackage, VisitType, mExhausted) then
    begin
      Finish;
    end;
  finally
    FStats.Add(mWatch.ElapsedMilliseconds);
  end;
  Result := FDone;
end;

function TIdeMemberRun.Details: TArray<TDpccIdeTypeDetail>;
begin
  Result := FResult;
end;

function TIdeMemberRun.Failed: Integer;
begin
  Result := FFailed;
end;

function TIdeMemberRun.UnitCount: Integer;
begin
  Result := FUnitCount;
end;

function TIdeMemberRun.Packages: Integer;
begin
  Result := FPackageCount;
end;

function TIdeMemberRun.Filtered: Boolean;
begin
  Result := FFilter <> nil;
end;

function TIdeMemberRun.Stats: TDpccSliceStats;
begin
  Result := FStats;
end;

end.
