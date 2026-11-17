unit dpcc.IDE.CodeInsight.IdeMembers;

// Sammelt für dpcc/ideMembers die Mitglieder der Typen in Units ohne Quelltext (Hauptthread, auf Nachfrage des
// Servers nach dem Index). Quelle ist die RTTI der geladenen Packages (seit L2 auch die der Installation; der Server
// fragt nur nach Units ohne Quelltext): bei Klassen
// Vorfahr, Interfaces, Felder, Properties (auch Array-Properties) und Methoden mit Parametern, sichtbar ab
// protected; bei Interfaces und Records ebenso, bei Aufzählungen die Werte. Was die RTTI nicht kennt, fehlt:
// Methoden ohne erweiterte RTTI ({$RTTI EXPLICIT METHODS([])}), Vorgabewerte von Parametern, private Mitglieder.

interface

uses
  System.Rtti,
  dpcc.Core.Lsp.IdeMembers;

type
  TDpccIdeMemberCollector = class
  private
    class function Detail(AType: TRttiType; const AUnit: string; out ADetail: TDpccIdeTypeDetail): Boolean;
      static;
  public
    /// <summary>Typen samt Mitgliedern der Units AUnits aus den geladenen Packages außerhalb der Installation;
    /// nur im Hauptthread. AFailed: Packages, deren RTTI nicht lesbar war.</summary>
    class function Details(const AUnits: TArray<string>; out AFailed: Integer): TArray<TDpccIdeTypeDetail>; static;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
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

/// <summary>Typen von APackage in den Units AWanted (Großbuchstaben) an ADetails anhängen.</summary>
procedure AddPackageDetails(APackage: TRttiPackage; AWanted: TDictionary<string, Boolean>;
  ADetails: TList<TDpccIdeTypeDetail>);
var
  mRttiType: TRttiType;
  mType: TDpccIdeType;
  mDetail: TDpccIdeTypeDetail;
begin
  for mRttiType in APackage.GetTypes do
  begin
    if mRttiType.IsPublicType and TDpccIdeType.FromQualified(mRttiType.QualifiedName, '', mType) and
      AWanted.ContainsKey(UpperCase(mType.UnitName)) and
      TDpccIdeMemberCollector.Detail(mRttiType, mType.UnitName, mDetail) then
    begin
      ADetails.Add(mDetail);
    end;
  end;
end;

class function TDpccIdeMemberCollector.Details(const AUnits: TArray<string>;
  out AFailed: Integer): TArray<TDpccIdeTypeDetail>;
var
  mUnit: string;
  mFolders: TArray<string>;
  mWanted: TDictionary<string, Boolean>;
  mDetails: TList<TDpccIdeTypeDetail>;
  mContext: TRttiContext;
  mPackage: TRttiPackage;
begin
  AFailed := 0;
  mFolders := TDpccIdeTypeCollector.SkippedFolders;
  mWanted := TDictionary<string, Boolean>.Create;
  mDetails := TList<TDpccIdeTypeDetail>.Create;
  mContext := TRttiContext.Create;
  try
    for mUnit in AUnits do
    begin
      mWanted.AddOrSetValue(UpperCase(mUnit), True);
    end;
    for mPackage in mContext.GetPackages do
    begin
      if TDpccIdeTypes.InFolders(mPackage.Name, mFolders) then
      begin
        Continue;
      end;
      // Ein Package mit beschädigter RTTI darf die übrigen nicht verhindern.
      try
        AddPackageDetails(mPackage, mWanted, mDetails);
      except
        on Exception do
        begin
          Inc(AFailed);
        end;
      end;
    end;
    Result := mDetails.ToArray;
  finally
    mContext.Free;
    mDetails.Free;
    mWanted.Free;
  end;
end;

end.
