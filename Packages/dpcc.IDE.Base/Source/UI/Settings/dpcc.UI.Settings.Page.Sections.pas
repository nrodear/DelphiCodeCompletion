unit dpcc.UI.Settings.Page.Sections;

// Abschnitte der Module auf der Optionsseite „dpcc“ (#1455): Jeder
// IDpccSettingsSectionProvider der Registry liefert einen eigenen Abschnitt, den der Teil in den Reiter seiner
// Seite (x-page) bzw. seines Bereichs (x-area) baut (Bausteine über IDpccSettingsSectionHost). Reiter, die erst für
// Abschnitte entstehen, folgen der Reihenfolge des Katalogs. Geht ein Modul, schließt er seinen Abschnitt; seine
// Werte bleiben erhalten.

interface

uses
  System.Generics.Collections,
  Vcl.Controls,
  dpcc.Core.Settings.Plugin,
  dpcc.Core.Settings.History,
  dpcc.Core.Settings.Contract,
  dpcc.UI.Settings.Contract,
  dpcc.Core.Modules.Contract,
  dpcc.UI.Settings.Bindings,
  dpcc.UI.Settings.Page.Host;

type
  /// <summary>Abschnitte der Module (#1455) mit ihrer Anmeldung und ihrem Host, gleicher Index; der letzte Teil der
  /// Seite: lädt und speichert nach den übrigen.</summary>
  TDpccSettingsSectionsPart = class(TDpccSettingsPagePart)
  private
    FSections: TArray<IDpccSettingsSection>;
    FProviders: TArray<IDpccSettingsSectionProvider>;
    FHosts: TArray<IDpccSettingsSectionHost>;
    /// <summary>Felder der Abschnitte an Plugin-Einstellungen.</summary>
    FBindings: TDpccSettingsBindings;
    /// <summary>Reiter, die erst für einen Abschnitt entstanden sind: Bereich und Index in den Reitern der Seite.
    /// </summary>
    FAreas: TArray<TPair<string, Integer>>;
    FWatch: IDpccRegistryListener;
    FWatchRegistration: IDpccRegistration;
    /// <summary>Erster Reiter mit einer Einstellung der Seite (AByPage) bzw. des Bereichs AArea; -1 ohne.</summary>
    function SheetWith(const AArea: string; AByPage: Boolean): Integer;
    /// <summary>Reiter der Seite bzw. des Bereichs AArea (x-page oder x-area); -1 ohne.</summary>
    function SheetOfArea(const AArea: string): Integer;
    /// <summary>Beschriftung eines neuen Reiters für AArea: Bereich aus dem Katalog, sonst Name der Seite.</summary>
    function AreaSheetCaption(const AArea: string): string;
    function CreateSection(const AProvider: IDpccSettingsSectionProvider): IDpccSettingsSection;
    procedure AddBuilt(const AProvider: IDpccSettingsSectionProvider; const ASection: IDpccSettingsSection);
    procedure AddBinding(const AName: string; AControl: TControl; AKind: TDpccSettingsBindingKind;
      const AValues: TArray<string>);
    /// <summary>Name der Plugin-Einstellung zum Schlüssel AKey (x-key); EDpccSettingsKey ohne.</summary>
    function NameOf(const AKey: string): string;
    /// <summary>Eigenes Element AControl eines Abschnitts an AKeys (x-key): Punkt nur mit AMark, Zurücksetzen,
    /// Unterpunkt, Sperre und Sprungziel.</summary>
    procedure MarkOwn(AControl: TControl; const AKeys: TArray<string>; AMark: Boolean);
    function Values(const AStore: IDpccMemorySettingsStore): IDpccSettingsValues;
    /// <summary>Abschnitte abgemeldeter Module schließen (Regel 3).</summary>
    procedure DropMissing;
    procedure CloseAll;
  public
    constructor Create(APage: TDpccSettingsPageHost);
    destructor Destroy; override;
    /// <summary>Abschnitte der Module aus der Registry bauen und auf Abmeldungen hören.</summary>
    procedure Build;
    procedure Load(const ASettings: TDpccPluginSettings); override;
    procedure Save(var ASettings: TDpccPluginSettings); override;
    /// <summary>Die Seite hat ein Fenster: Abschnitte füllen ihre Listen.</summary>
    procedure WindowReady; override;
    /// <summary>Einstellung AName (Registry-Name) mit Vorgabe AArgument zeigen (z. B. „zuordnen …“ mit dem
    /// Projekt): Der Abschnitt des Moduls, dem sie gehört, legt an bzw. wählt. False ohne Abschnitt dazu.
    /// </summary>
    function ShowSettingArgument(const AName, AArgument: string): Boolean;
    /// <summary>Zum Testen: Zahl der gebauten Abschnitte.</summary>
    function Count: Integer;
  end;

implementation

uses
  System.SysUtils,
  Vcl.StdCtrls,
  dpcc.Core.Diagnostics.Guard,
  dpcc.Core.Settings.Catalog,
  dpcc.Core.Settings.StoreValues,
  dpcc.Core.Settings.PageNames,
  dpcc.Core.Modules.Registry,
  dpcc.UI.Strings;

const
  cSectionKeyMissing = 'Einstellung %s ist keine Plugin-Einstellung';
  cSectionChoiceMismatch = 'Auswahl %s: Anzeige und Werte verschieden lang';

type
  /// <summary>Host und Wächter der Abschnitte lösen sich von der Seite, wenn sie schließt (#1455).</summary>
  IDpccSettingsDetachable = interface
    ['{816EC08A-0148-46B9-AD92-1374D8305711}']
    procedure Detach;
  end;

  /// <summary>Bausteine der Seite für einen Abschnitt eines Moduls (#1455). Hält die Seite nur, solange sie lebt;
  /// nach dem Schließen der Seite tut er nichts mehr.</summary>
  TDpccSettingsSectionHost = class(TInterfacedObject, IDpccSettingsSectionHost, IDpccSettingsDetachable)
  private
    FPart: TDpccSettingsSectionsPart;
    FPage: TDpccSettingsPageHost;
    function NameOf(const AKey: string): string;
  public
    constructor Create(APart: TDpccSettingsSectionsPart);
    procedure Detach;
    procedure AddTitle(const ACaption: string);
    function AddHint(const AText: string; AHeight: Integer): TControl;
    function AddSwitch(const AKey, ACaption: string): TControl;
    function AddModuleSwitch(const AKey: string): TControl;
    function AddNumber(const AKey, ACaption: string): TControl;
    function AddText(const AKey, ACaption: string): TControl;
    function AddChoice(const AKey, ACaption: string; const ACaptions, AValues: TArray<string>): TControl;
    function AddKey(const AKey, ACaption: string): TControl;
    function AddOwnCheck(const ACaption: string; const AKeys: TArray<string>): TControl;
    function AddOwnNumber(const ACaption: string; const AKeys: TArray<string>): TControl;
    function AddOwnText(const ACaption: string; const AKeys: TArray<string>): TControl;
    function AddOwnChoice(const ACaption: string; const ACaptions, AKeys: TArray<string>): TControl;
    procedure ShareKeys(AControl: TControl; const AKeys: TArray<string>);
    function AddRow(AHeight: Integer; const AKeys: TArray<string>): TWinControl;
    procedure Attach(ARow, AAnchor: TControl);
    procedure Changed;
    procedure Allow(AControl: TControl; AEnabled: Boolean);
    function ListReady(AControl: TWinControl): Boolean;
    function Reveal(const AKey: string): Boolean;
    function Shows(const AKey: string): Boolean;
  end;

  /// <summary>Abschnitte vor dem Aufbau mit ihrem Anbieter; Order liefert die Reihenfolge des Aufbaus: nach der
  /// ersten Einstellung ihres Reiters im Katalog, bei Gleichstand in der Reihenfolge der Anmeldung.</summary>
  TDpccPendingSections = class
  private
    FCatalog: TDpccSettingsCatalog;
    FRanks: TArray<Integer>;
    FProviders: TArray<IDpccSettingsSectionProvider>;
    FSections: TArray<IDpccSettingsSection>;
    function RankOf(const AArea: string): Integer;
  public
    constructor Create(ACatalog: TDpccSettingsCatalog);
    /// <summary>Merkt ASection; ohne Abschnitt (Anbieter gescheitert) nichts.</summary>
    procedure Add(const AProvider: IDpccSettingsSectionProvider; const ASection: IDpccSettingsSection);
    function Order: TArray<Integer>;
    property Providers: TArray<IDpccSettingsSectionProvider> read FProviders;
    property Sections: TArray<IDpccSettingsSection> read FSections;
  end;

  /// <summary>Hört für die Seite auf die Registry: Geht ein Modul, schließt die Seite seinen Abschnitt (Regel 2).
  /// </summary>
  TDpccSettingsSectionWatch = class(TInterfacedObject, IDpccRegistryListener, IDpccSettingsDetachable)
  private
    FPart: TDpccSettingsSectionsPart;
  public
    constructor Create(APart: TDpccSettingsSectionsPart);
    procedure Detach;
    procedure RegistryChanged(const AChange: TDpccRegistryChange);
  end;

{ TDpccPendingSections }

constructor TDpccPendingSections.Create(ACatalog: TDpccSettingsCatalog);
begin
  inherited Create;
  FCatalog := ACatalog;
end;

function TDpccPendingSections.RankOf(const AArea: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FCatalog.Count - 1 do
  begin
    if SameText(FCatalog[mIndex].Page, AArea) or SameText(FCatalog[mIndex].Area, AArea) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := MaxInt;
end;

procedure TDpccPendingSections.Add(const AProvider: IDpccSettingsSectionProvider;
  const ASection: IDpccSettingsSection);
begin
  if ASection = nil then
  begin
    Exit;
  end;
  FProviders := FProviders + [AProvider];
  FSections := FSections + [ASection];
  FRanks := FRanks + [RankOf(ASection.AreaId)];
end;

function TDpccPendingSections.Order: TArray<Integer>;
var
  mIndex, mPosition: Integer;
begin
  // Einfügen nach Rang; gleicher Rang bleibt in der Reihenfolge der Anmeldung (stabil).
  Result := nil;
  for mIndex := 0 to High(FSections) do
  begin
    mPosition := Length(Result);
    while (mPosition > 0) and (FRanks[Result[mPosition - 1]] > FRanks[mIndex]) do
    begin
      Dec(mPosition);
    end;
    Insert(mIndex, Result, mPosition);
  end;
end;

{ TDpccSettingsSectionHost }

constructor TDpccSettingsSectionHost.Create(APart: TDpccSettingsSectionsPart);
begin
  inherited Create;
  FPart := APart;
  FPage := APart.FPage;
end;

procedure TDpccSettingsSectionHost.Detach;
begin
  FPart := nil;
  FPage := nil;
end;

function TDpccSettingsSectionHost.NameOf(const AKey: string): string;
begin
  Result := FPart.NameOf(AKey);
end;

procedure TDpccSettingsSectionHost.AddTitle(const ACaption: string);
begin
  if FPage <> nil then
  begin
    FPage.AddTitleText(ACaption);
  end;
end;

function TDpccSettingsSectionHost.AddHint(const AText: string; AHeight: Integer): TControl;
begin
  Result := nil;
  if FPage <> nil then
  begin
    Result := FPage.AddWrappedLabel(AHeight, AText);
  end;
end;

function TDpccSettingsSectionHost.AddSwitch(const AKey, ACaption: string): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := NameOf(AKey);
  Result := FPage.AddCheck(ACaption);
  FPart.AddBinding(mName, Result, sbkCheck, nil);
end;

function TDpccSettingsSectionHost.AddModuleSwitch(const AKey: string): TControl;
var
  mIndex: Integer;
  mCaption: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mIndex := FPage.Catalog.IndexOfName(NameOf(AKey));
  // Ein Schlüssel, den der Katalog nicht kennt, trägt sich selbst als Beschriftung.
  mCaption := AKey;
  if mIndex >= 0 then
  begin
    mCaption := FPage.Catalog[mIndex].Caption;
    if TDpccStrings.Language = TDpccLanguage.English then
    begin
      mCaption := FPage.Catalog[mIndex].CaptionEn;
    end;
  end;
  Result := AddSwitch(AKey, mCaption);
end;

function TDpccSettingsSectionHost.AddNumber(const AKey, ACaption: string): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := NameOf(AKey);
  Result := FPage.AddNumber(ACaption);
  FPart.AddBinding(mName, Result, sbkText, nil);
end;

function TDpccSettingsSectionHost.AddText(const AKey, ACaption: string): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := NameOf(AKey);
  Result := FPage.AddTextLine(ACaption);
  FPart.AddBinding(mName, Result, sbkText, nil);
end;

function TDpccSettingsSectionHost.AddChoice(const AKey, ACaption: string;
  const ACaptions, AValues: TArray<string>): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  if Length(ACaptions) <> Length(AValues) then
  begin
    raise EDpccSettingsKey.CreateFmt(cSectionChoiceMismatch, [AKey]);
  end;
  mName := NameOf(AKey);
  Result := FPage.AddChoice(ACaption, ACaptions);
  FPart.AddBinding(mName, Result, sbkChoice, AValues);
end;

function TDpccSettingsSectionHost.AddKey(const AKey, ACaption: string): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := NameOf(AKey);
  Result := FPage.AddKey(ACaption);
  FPart.AddBinding(mName, Result, sbkShortcut, nil);
end;

function TDpccSettingsSectionHost.AddOwnCheck(const ACaption: string; const AKeys: TArray<string>): TControl;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  Result := FPage.AddCheck(ACaption);
  FPart.MarkOwn(Result, AKeys, True);
end;

function TDpccSettingsSectionHost.AddOwnNumber(const ACaption: string; const AKeys: TArray<string>): TControl;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  Result := FPage.AddNumber(ACaption);
  FPart.MarkOwn(Result, AKeys, True);
end;

function TDpccSettingsSectionHost.AddOwnText(const ACaption: string; const AKeys: TArray<string>): TControl;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  Result := FPage.AddTextLine(ACaption);
  FPart.MarkOwn(Result, AKeys, True);
end;

function TDpccSettingsSectionHost.AddOwnChoice(const ACaption: string;
  const ACaptions, AKeys: TArray<string>): TControl;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  Result := FPage.AddChoice(ACaption, ACaptions);
  FPart.MarkOwn(Result, AKeys, True);
end;

procedure TDpccSettingsSectionHost.ShareKeys(AControl: TControl; const AKeys: TArray<string>);
begin
  if (FPage <> nil) and (AControl <> nil) then
  begin
    FPart.MarkOwn(AControl, AKeys, False);
  end;
end;

function TDpccSettingsSectionHost.AddRow(AHeight: Integer; const AKeys: TArray<string>): TWinControl;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  Result := FPage.AddPanel(AHeight);
  // Die Bindung hängt an der Zeile der Seite, nie an Elementen des Moduls: Die gibt das Modul in Close frei.
  FPart.MarkOwn(Result, AKeys, True);
end;

procedure TDpccSettingsSectionHost.Attach(ARow, AAnchor: TControl);
begin
  if FPage <> nil then
  begin
    FPage.Attach(ARow, AAnchor);
  end;
end;

procedure TDpccSettingsSectionHost.Changed;
begin
  if FPage <> nil then
  begin
    FPage.RefreshMarks;
  end;
end;

procedure TDpccSettingsSectionHost.Allow(AControl: TControl; AEnabled: Boolean);
begin
  if (FPage <> nil) and (AControl <> nil) then
  begin
    FPage.Allow(AControl, AEnabled);
  end;
end;

function TDpccSettingsSectionHost.ListReady(AControl: TWinControl): Boolean;
begin
  Result := (FPage <> nil) and (AControl <> nil) and FPage.ListReady(AControl);
end;

function TDpccSettingsSectionHost.Reveal(const AKey: string): Boolean;
var
  mName: string;
begin
  Result := False;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := TDpccSettingsStoreValues.PluginName(FPage.Catalog, AKey);
  Result := (mName <> '') and FPage.Reveal(mName);
end;

function TDpccSettingsSectionHost.Shows(const AKey: string): Boolean;
var
  mName: string;
begin
  Result := False;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := TDpccSettingsStoreValues.PluginName(FPage.Catalog, AKey);
  Result := (mName <> '') and (FPage.ControlOfSetting(mName) <> nil);
end;

{ TDpccSettingsSectionWatch }

constructor TDpccSettingsSectionWatch.Create(APart: TDpccSettingsSectionsPart);
begin
  inherited Create;
  FPart := APart;
end;

procedure TDpccSettingsSectionWatch.Detach;
begin
  FPart := nil;
end;

procedure TDpccSettingsSectionWatch.RegistryChanged(const AChange: TDpccRegistryChange);
begin
  if (FPart <> nil) and IsEqualGUID(AChange.IID, IDpccSettingsSectionProvider) then
  begin
    FPart.DropMissing;
  end;
end;

/// <summary>Zeigen AFirst und ASecond auf dasselbe Objekt (Vergleich über IInterface, nicht über die
/// Schnittstelle)?</summary>
function SameInstance(const AFirst, ASecond: IInterface): Boolean;
begin
  Result := (AFirst as IInterface) = (ASecond as IInterface);
end;

{ TDpccSettingsSectionsPart }

constructor TDpccSettingsSectionsPart.Create(APage: TDpccSettingsPageHost);
begin
  inherited Create(APage);
  FBindings := TDpccSettingsBindings.Create;
end;

destructor TDpccSettingsSectionsPart.Destroy;
begin
  // Zuerst die Abschnitte schließen: Ihre Elemente liegen in Zeilen der Seite.
  CloseAll;
  FreeAndNil(FBindings);
  inherited Destroy;
end;

function TDpccSettingsSectionsPart.SheetWith(const AArea: string; AByPage: Boolean): Integer;
var
  mSheet, mIndex: Integer;
  mName, mValue: string;
begin
  for mSheet := 0 to High(FPage.Boxes) do
  begin
    for mName in FPage.Marks.NamesIn(FPage.Boxes[mSheet]) do
    begin
      mIndex := FPage.Catalog.IndexOfName(mName);
      if mIndex < 0 then
      begin
        Continue;
      end;
      mValue := FPage.Catalog[mIndex].Area;
      if AByPage then
      begin
        mValue := FPage.Catalog[mIndex].Page;
      end;
      if SameText(mValue, AArea) then
      begin
        Exit(mSheet);
      end;
    end;
  end;
  Result := -1;
end;

function TDpccSettingsSectionsPart.SheetOfArea(const AArea: string): Integer;
var
  mSheet: Integer;
begin
  // Reiter einer Seite bzw. eines Bereichs: der erste, auf dem eine Einstellung mit dieser Seite (x-page) steht,
  // sonst der erste mit diesem Bereich (x-area). Zuerst die Seite: „Editor“ ist Seite und Bereich, und
  // Einstellungen des Bereichs „editor“ stehen auch auf „Allgemein“.
  Result := SheetWith(AArea, True);
  if Result < 0 then
  begin
    Result := SheetWith(AArea, False);
  end;
  if Result >= 0 then
  begin
    Exit;
  end;
  for mSheet := 0 to High(FAreas) do
  begin
    if SameText(FAreas[mSheet].Key, AArea) then
    begin
      Exit(FAreas[mSheet].Value);
    end;
  end;
  Result := -1;
end;

procedure TDpccSettingsSectionsPart.Build;
var
  mItem: IInterface;
  mProvider: IDpccSettingsSectionProvider;
  mPending: TDpccPendingSections;
  mIndex: Integer;
begin
  // Abschnitte der Module (#1455): in den Reiter ihrer Seite, hinter die Einstellungen von Base. Neue Reiter in der
  // Reihenfolge des Katalogs, nicht in der zufälligen Reihenfolge der Anmeldung.
  mPending := TDpccPendingSections.Create(FPage.Catalog);
  try
    for mItem in DpccModuleRegistry.FindAll(IDpccSettingsSectionProvider) do
    begin
      if Supports(mItem, IDpccSettingsSectionProvider, mProvider) then
      begin
        mPending.Add(mProvider, CreateSection(mProvider));
      end;
    end;
    for mIndex in mPending.Order do
    begin
      AddBuilt(mPending.Providers[mIndex], mPending.Sections[mIndex]);
    end;
  finally
    mPending.Free;
  end;
  FWatch := TDpccSettingsSectionWatch.Create(Self);
  FWatchRegistration := DpccModuleRegistry.Subscribe(FWatch);
end;

function TDpccSettingsSectionsPart.CreateSection(
  const AProvider: IDpccSettingsSectionProvider): IDpccSettingsSection;
begin
  Result := nil;
  try
    Result := AProvider.CreateSection;
  except
    on E: Exception do
    begin
      TDpccGuard.ReportProvider('settings', E);
    end;
  end;
end;

function TDpccSettingsSectionsPart.AreaSheetCaption(const AArea: string): string;
var
  mEnglish: Boolean;
begin
  mEnglish := TDpccStrings.Language = TDpccLanguage.English;
  if FPage.Catalog.HasArea(AArea) then
  begin
    Result := FPage.Catalog.AreaCaption(AArea, mEnglish);
  end
  else
  begin
    Result := TDpccSettingsPageNames.Caption(AArea, mEnglish);
  end;
end;

function TDpccSettingsSectionsPart.NameOf(const AKey: string): string;
begin
  Result := TDpccSettingsStoreValues.PluginName(FPage.Catalog, AKey);
  if Result = '' then
  begin
    raise EDpccSettingsKey.CreateFmt(cSectionKeyMissing, [AKey]);
  end;
end;

procedure TDpccSettingsSectionsPart.MarkOwn(AControl: TControl; const AKeys: TArray<string>; AMark: Boolean);
var
  mNames: TArray<string>;
  mKey, mName: string;
begin
  if Length(AKeys) = 0 then
  begin
    Exit;
  end;
  mNames := nil;
  for mKey in AKeys do
  begin
    mNames := mNames + [NameOf(mKey)];
  end;
  FPage.Marks.Bind(AControl, mNames, AMark);
  for mName in mNames do
  begin
    FPage.Bind(mName, AControl);
  end;
end;

/// <summary>Modul, das AProvider in der Registry angemeldet hat; '' für Base, AFallback, wenn es fehlt.</summary>
function OwnerOfProvider(const AProvider: IDpccSettingsSectionProvider; const AFallback: string): string;
var
  mItem: TDpccProvided;
  mWanted: IInterface;
begin
  Result := AFallback;
  if AProvider = nil then
  begin
    Exit;
  end;
  mWanted := AProvider as IInterface;
  for mItem in DpccModuleRegistry.Provisions(IDpccSettingsSectionProvider) do
  begin
    if (mItem.Instance as IInterface) = mWanted then
    begin
      Exit(mItem.OwnerId);
    end;
  end;
end;

/// <summary>Knoten, in dem ASection steht: das Modul, das seinen Anbieter angemeldet hat (nicht OwnerId: Abschnitt
/// und Modul dürfen anders heißen, z. B. dpcc.buildTools und dpcc.build), bei einem Beitrag das Modul, das dessen
/// Vertrag bereitstellt. False, wenn der Gastgeber fehlt.</summary>
function NodeOfSection(const AProvider: IDpccSettingsSectionProvider; const ASection: IDpccSettingsSection;
  out ANode: string): Boolean;
var
  mContribution: IDpccSettingsContribution;
  mProvided: TArray<TDpccProvided>;
begin
  ANode := OwnerOfProvider(AProvider, ASection.OwnerId);
  if not Supports(ASection, IDpccSettingsContribution, mContribution) then
  begin
    Exit(True);
  end;
  mProvided := DpccModuleRegistry.Provisions(mContribution.HostContract);
  Result := Length(mProvided) > 0;
  if Result then
  begin
    ANode := mProvided[0].OwnerId;
  end;
end;

/// <summary>Elemente direkt in ABox.</summary>
function Children(ABox: TWinControl): TArray<TControl>;
var
  mIndex: Integer;
begin
  SetLength(Result, ABox.ControlCount);
  for mIndex := 0 to ABox.ControlCount - 1 do
  begin
    Result[mIndex] := ABox.Controls[mIndex];
  end;
end;

function Contains(const AList: TArray<TControl>; AControl: TControl): Boolean;
var
  mItem: TControl;
begin
  for mItem in AList do
  begin
    if mItem = AControl then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TDpccSettingsSectionsPart.AddBuilt(const AProvider: IDpccSettingsSectionProvider;
  const ASection: IDpccSettingsSection);
var
  mSheet: Integer;
  mHost: TDpccSettingsSectionHost;
  mHostRef: IDpccSettingsSectionHost;
  mBefore: TArray<TControl>;
  mChild: TControl;
  mNode: string;
begin
  if ASection = nil then
  begin
    Exit;
  end;
  // Beitrag zu einem anderen Modul (#1903): steht im Knoten des Gastgebers; ohne Gastgeber gar nicht.
  if not NodeOfSection(AProvider, ASection, mNode) then
  begin
    ASection.Close;
    Exit;
  end;
  mSheet := SheetOfArea(ASection.AreaId);
  if mSheet < 0 then
  begin
    // Reiter, den Base nicht hat: eigener Reiter mit der Beschriftung des Katalogs (sonst die Id).
    FPage.AddSheetCaption(AreaSheetCaption(ASection.AreaId));
    mSheet := High(FPage.Sheets);
    FAreas := FAreas + [TPair<string, Integer>.Create(ASection.AreaId, mSheet)];
  end;
  FPage.ContinueSheet(mSheet);
  mBefore := Children(FPage.Boxes[mSheet]);
  mHost := TDpccSettingsSectionHost.Create(Self);
  mHostRef := mHost;
  try
    ASection.Build(mHostRef);
  except
    on E: Exception do
    begin
      // Ein fehlerhafter Abschnitt darf den Optionsdialog nicht verhindern; er bleibt zu und wird gemeldet.
      mHost.Detach;
      TDpccGuard.ReportProvider('settings:' + ASection.OwnerId, E);
      ASection.Close;
      Exit;
    end;
  end;
  // Knoten je Package (#1903): Die neuen Zeilen gehören dem Modul des Abschnitts.
  for mChild in Children(FPage.Boxes[mSheet]) do
  begin
    if not Contains(mBefore, mChild) then
    begin
      FPage.MarkSectionOwner(mChild, mNode);
    end;
  end;
  FSections := FSections + [ASection];
  FProviders := FProviders + [AProvider];
  FHosts := FHosts + [mHostRef];
end;

procedure TDpccSettingsSectionsPart.AddBinding(const AName: string; AControl: TControl;
  AKind: TDpccSettingsBindingKind; const AValues: TArray<string>);
begin
  FPage.BindValues(FBindings, AName, AControl, AKind, AValues);
  FPage.Marks.Bind(AControl, [AName]);
end;

function TDpccSettingsSectionsPart.Values(const AStore: IDpccMemorySettingsStore): IDpccSettingsValues;
begin
  Result := TDpccSettingsStoreValues.Create(FPage.Catalog, AStore,
    TDpccMemorySettingsStore.FromSettings(TDpccPluginSettings.Defaults));
end;

procedure TDpccSettingsSectionsPart.Load(const ASettings: TDpccPluginSettings);
var
  mStore: IDpccMemorySettingsStore;
  mValues: IDpccSettingsValues;
  mSection: IDpccSettingsSection;
begin
  if (Length(FSections) = 0) and (FBindings.Count = 0) then
  begin
    Exit;
  end;
  mStore := TDpccMemorySettingsStore.FromSettings(ASettings);
  FBindings.Load(mStore);
  mValues := Values(mStore);
  for mSection in FSections do
  begin
    mSection.Load(mValues);
  end;
end;

procedure TDpccSettingsSectionsPart.Save(var ASettings: TDpccPluginSettings);
var
  mStore: IDpccMemorySettingsStore;
  mSection: IDpccSettingsSection;
  mValues: IDpccSettingsValues;
begin
  if (Length(FSections) = 0) and (FBindings.Count = 0) then
  begin
    Exit;
  end;
  mStore := TDpccMemorySettingsStore.FromSettings(ASettings);
  FBindings.Save(mStore);
  mValues := Values(mStore);
  for mSection in FSections do
  begin
    mSection.Save(mValues);
  end;
  ASettings.Load(mStore);
end;

procedure TDpccSettingsSectionsPart.DropMissing;
var
  mCurrent: TArray<IInterface>;
  mKeep: TArray<IDpccSettingsSection>;
  mKeepProviders: TArray<IDpccSettingsSectionProvider>;
  mKeepHosts: TArray<IDpccSettingsSectionHost>;
  mIndex: Integer;
  mItem: IInterface;
  mFound: Boolean;
begin
  // Ein abgemeldetes Modul erreicht danach nichts mehr (Regel 3): Abschnitt schließen und vergessen. Seine
  // Werte bleiben, gebundene Felder gehören der Seite. Neue Abschnitte zeigt erst die nächste Seite.
  mCurrent := DpccModuleRegistry.FindAll(IDpccSettingsSectionProvider);
  mKeep := nil;
  mKeepProviders := nil;
  mKeepHosts := nil;
  for mIndex := 0 to High(FSections) do
  begin
    mFound := False;
    for mItem in mCurrent do
    begin
      if SameInstance(mItem, FProviders[mIndex]) then
      begin
        mFound := True;
      end;
    end;
    if mFound then
    begin
      mKeep := mKeep + [FSections[mIndex]];
      mKeepProviders := mKeepProviders + [FProviders[mIndex]];
      mKeepHosts := mKeepHosts + [FHosts[mIndex]];
    end
    else
    begin
      (FHosts[mIndex] as IDpccSettingsDetachable).Detach;
      FSections[mIndex].Close;
    end;
  end;
  FSections := mKeep;
  FProviders := mKeepProviders;
  FHosts := mKeepHosts;
end;

procedure TDpccSettingsSectionsPart.CloseAll;
var
  mIndex: Integer;
begin
  if FWatch <> nil then
  begin
    (FWatch as IDpccSettingsDetachable).Detach;
  end;
  if FWatchRegistration <> nil then
  begin
    FWatchRegistration.Revoke;
  end;
  FWatchRegistration := nil;
  FWatch := nil;
  for mIndex := 0 to High(FSections) do
  begin
    (FHosts[mIndex] as IDpccSettingsDetachable).Detach;
    FSections[mIndex].Close;
  end;
  FSections := nil;
  FProviders := nil;
  FHosts := nil;
  if FBindings <> nil then
  begin
    FBindings.Clear;
  end;
end;

procedure TDpccSettingsSectionsPart.WindowReady;
var
  mSection: IDpccSettingsSection;
begin
  for mSection in FSections do
  begin
    mSection.WindowReady;
  end;
end;

function TDpccSettingsSectionsPart.ShowSettingArgument(const AName, AArgument: string): Boolean;
var
  mIndex: Integer;
  mKey: string;
  mSection: IDpccSettingsSection;
begin
  Result := False;
  mIndex := FPage.Catalog.IndexOfName(AName);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mKey := FPage.Catalog[mIndex].Key;
  for mSection in FSections do
  begin
    if mSection.Show(mKey, AArgument) then
    begin
      Exit(True);
    end;
  end;
end;

function TDpccSettingsSectionsPart.Count: Integer;
begin
  Result := Length(FSections);
end;

end.
