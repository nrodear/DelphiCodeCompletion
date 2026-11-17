unit dpcc.Windows.Projects.DelphiInstallation;

// Bibliothekspfade einer Delphi-Installation aus der Registry.
//
//   HKCU\Software\Embarcadero\BDS\<Version>\Library\<Plattform>\Search Path
//   HKCU\Software\Embarcadero\BDS\<Version>\Library\<Plattform>\Browsing Path
//   HKCU\Software\Embarcadero\BDS\<Version>\Environment Variables
//   HKLM\SOFTWARE\(WOW6432Node\)Embarcadero\BDS\<Version>\RootDir
//
// Verweise wie $(BDSLIB) und $(Platform) werden aufgelöst. Variablen aus
// "Environment Variables" haben Vorrang vor den eingebauten, die
// Umgebungsvariablen des Prozesses gelten zuletzt (L2: alle, nicht nur fünf).
// Mit eigenem Profil der IDE (bds -r) meldet das Plugin den Registry-Schlüssel;
// dann gelten dessen Bibliothekspfade und Variablen (L2). Win64x hat in der
// Registry keinen Browsing Path; dann gilt der von Win64 (L2).
// Beispiele für Versionen: 23.0 = Delphi 12, 37.0 = Delphi 13.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Common.Projects.Contract;

type
  TDelphiInstallation = class(TInterfacedObject, ILibraryPathProvider)
  private
    FVersion: string;
    FRootDir: string;
    /// <summary>Schlüssel der Einstellungen unter HKCU, z. B. Software\Embarcadero\BDS\37.0 (L2: auch ein Profil).
    /// </summary>
    FBaseKey: string;
    FVariables: TArray<TPair<string, string>>;
    function ReadPaths(const APlatform, AValueName: string): TArray<string>;
    function ExpandFor(const AText, APlatform: string): string;
    procedure LoadVariables;
  public
    /// <summary>Installierte Versionen (z. B. "37.0"), aufsteigend sortiert.</summary>
    class function Versions: TArray<string>; static;
    /// <summary>Neueste Installation oder nil, wenn keine gefunden wurde.</summary>
    class function Latest: ILibraryPathProvider; static;
    /// <summary>Installationsordner der Version (z. B. "37.0") ohne abschließenden Trenner; '' ohne Installation.
    /// </summary>
    class function RootDirOf(const AVersion: string): string; static;
    /// <summary>EProjectError, wenn die Version nicht installiert ist.</summary>
    constructor Create(const AVersion: string); overload;
    /// <summary>Wie oben; ABaseKey: Registry-Schlüssel der laufenden IDE (Profil -r), '' = Standardprofil.</summary>
    constructor Create(const AVersion, ABaseKey: string); overload;
    /// <summary>Werte aller Umgebungsvariablen des Prozesses (L2), Name=Wert.</summary>
    class function ProcessEnvironment: TArray<TPair<string, string>>; static;
    { ILibraryPathProvider }
    function LibraryPaths(const APlatform: string): TArray<string>;
    function BrowsingPaths(const APlatform: string): TArray<string>;
    function Variables: TArray<TPair<string, string>>;
    property Version: string read FVersion;
    property RootDir: string read FRootDir;
    property BaseKey: string read FBaseKey;
  end;

implementation

uses
  System.Classes,
  System.Generics.Defaults,
  System.Win.Registry,
  Winapi.Windows,
  Winapi.ShlObj,
  dpcc.Common.Projects.Paths;

const
  cBdsKey = 'Software\Embarcadero\BDS';
  // Die IDE ist eine 32-Bit-Anwendung; ihre HKLM-Einträge liegen je nach Version in einer der Ansichten.
  cRegistryViews: array[0..1] of LongWord = (KEY_READ, KEY_READ or KEY_WOW64_32KEY);

function OpenRead(ARoot: HKEY; const AKey: string; AAccess: LongWord): TRegistry; overload;
begin
  Result := TRegistry.Create(AAccess);
  Result.RootKey := ARoot;
  if not Result.OpenKeyReadOnly(AKey) then
  begin
    FreeAndNil(Result);
  end;
end;

// Wie oben mit AAccess = KEY_READ.
function OpenRead(ARoot: HKEY; const AKey: string): TRegistry; overload;
begin
  Result := OpenRead(ARoot, AKey, KEY_READ);
end;

function FolderPath(AFolder: Integer): string;
var
  mBuffer: array[0..MAX_PATH] of Char;
begin
  if SHGetFolderPath(0, AFolder, 0, SHGFP_TYPE_CURRENT, mBuffer) = S_OK then
  begin
    Result := mBuffer;
  end
  else
  begin
    Result := '';
  end;
end;

function CompareVersions(const A, B: string): Integer;
var
  mNumberA: Double;
  mNumberB: Double;
begin
  mNumberA := StrToFloatDef(A, 0, TFormatSettings.Invariant);
  mNumberB := StrToFloatDef(B, 0, TFormatSettings.Invariant);
  if mNumberA < mNumberB then
  begin
    Result := -1;
  end
  else if mNumberA > mNumberB then
  begin
    Result := 1;
  end
  else
  begin
    Result := 0;
  end;
end;

function ReadRootDir(const AVersion: string): string;
var
  mRegistry: TRegistry;
  mAccess: LongWord;
begin
  Result := '';
  for mAccess in cRegistryViews do
  begin
    mRegistry := OpenRead(HKEY_LOCAL_MACHINE, cBdsKey + '\' + AVersion, mAccess);
    if mRegistry <> nil then
      try
        if mRegistry.ValueExists('RootDir') then
        begin
          Result := ExcludeTrailingPathDelimiter(mRegistry.ReadString('RootDir'));
        end;
      finally
        mRegistry.Free;
      end;
    if Result <> '' then
    begin
      Exit;
    end;
  end;
  mRegistry := OpenRead(HKEY_CURRENT_USER, cBdsKey + '\' + AVersion);
  if mRegistry <> nil then
    try
      if mRegistry.ValueExists('RootDir') then
      begin
        Result := ExcludeTrailingPathDelimiter(mRegistry.ReadString('RootDir'));
      end;
    finally
      mRegistry.Free;
    end;
end;

{ TDelphiInstallation }

class function TDelphiInstallation.Versions: TArray<string>;
var
  mRegistry: TRegistry;
  mNames: TStringList;
  mFound: TList<string>;
  mName: string;
begin
  mFound := TList<string>.Create;
  mNames := TStringList.Create;
  try
    mRegistry := OpenRead(HKEY_CURRENT_USER, cBdsKey);
    if mRegistry <> nil then
      try
        mRegistry.GetKeyNames(mNames);
      finally
        mRegistry.Free;
      end;
    for mName in mNames do
    begin
      if (StrToFloatDef(mName, 0, TFormatSettings.Invariant) > 0) and (ReadRootDir(mName) <> '') then
      begin
        mFound.Add(mName);
      end;
    end;
    mFound.Sort(TComparer<string>.Construct(CompareVersions));
    Result := mFound.ToArray;
  finally
    mNames.Free;
    mFound.Free;
  end;
end;

class function TDelphiInstallation.RootDirOf(const AVersion: string): string;
begin
  Result := ReadRootDir(AVersion);
end;

class function TDelphiInstallation.Latest: ILibraryPathProvider;
var
  mInstalled: TArray<string>;
begin
  mInstalled := Versions;
  if Length(mInstalled) = 0 then
  begin
    Result := nil;
  end
  else
  begin
    Result := TDelphiInstallation.Create(mInstalled[High(mInstalled)]);
  end;
end;

constructor TDelphiInstallation.Create(const AVersion: string);
begin
  Create(AVersion, '');
end;

constructor TDelphiInstallation.Create(const AVersion, ABaseKey: string);
begin
  inherited Create;
  FVersion := AVersion;
  FBaseKey := ExcludeTrailingPathDelimiter(Trim(ABaseKey));
  if FBaseKey = '' then
  begin
    FBaseKey := cBdsKey + '\' + AVersion;
  end;
  FRootDir := ReadRootDir(AVersion);
  if FRootDir = '' then
  begin
    raise EProjectError.CreateFmt('Delphi-Version %s ist nicht installiert', [AVersion]);
  end;
  LoadVariables;
end;

procedure TDelphiInstallation.LoadVariables;
var
  mValues: TList<TPair<string, string>>;
  mRegistry: TRegistry;
  mNames: TStringList;
  mName: string;
  mStudioFolder: string;
begin
  mValues := TList<TPair<string, string>>.Create;
  mNames := TStringList.Create;
  try
    // Benutzerdefinierte Variablen der IDE zuerst, damit sie Vorrang haben.
    mRegistry := OpenRead(HKEY_CURRENT_USER, FBaseKey + '\Environment Variables');
    if mRegistry <> nil then
      try
        mRegistry.GetValueNames(mNames);
        for mName in mNames do
        begin
          mValues.Add(TPair<string, string>.Create(mName, mRegistry.ReadString(mName)));
        end;
      finally
        mRegistry.Free;
      end;
    mStudioFolder := 'Embarcadero\Studio\' + FVersion;
    mValues.Add(TPair<string, string>.Create('BDS', FRootDir));
    mValues.Add(TPair<string, string>.Create('BDSBIN', FRootDir + '\bin'));
    mValues.Add(TPair<string, string>.Create('BDSLIB', FRootDir + '\lib'));
    mValues.Add(TPair<string, string>.Create('BDSINCLUDE', FRootDir + '\include'));
    mValues.Add(TPair<string, string>.Create('BDSCOMMONDIR',
      IncludeTrailingPathDelimiter(FolderPath(CSIDL_COMMON_DOCUMENTS)) + mStudioFolder));
    mValues.Add(TPair<string, string>.Create('BDSUSERDIR',
      IncludeTrailingPathDelimiter(FolderPath(CSIDL_PERSONAL)) + mStudioFolder));
    mValues.Add(TPair<string, string>.Create('BDSCatalogRepository',
      IncludeTrailingPathDelimiter(FolderPath(CSIDL_PERSONAL)) + mStudioFolder + '\CatalogRepository'));
    // L2: alle Umgebungsvariablen des Prozesses zuletzt (vorher nur fünf); wie TDpccPathMacros im Plugin.
    mValues.AddRange(ProcessEnvironment);
    FVariables := mValues.ToArray;
  finally
    mNames.Free;
    mValues.Free;
  end;
end;

class function TDelphiInstallation.ProcessEnvironment: TArray<TPair<string, string>>;
var
  mBlock, mEntry: PChar;
  mText: string;
  mEqual: Integer;
  mList: TList<TPair<string, string>>;
begin
  mList := TList<TPair<string, string>>.Create;
  try
    mBlock := GetEnvironmentStrings;
    if mBlock <> nil then
    try
      mEntry := mBlock;
      while mEntry^ <> #0 do
      begin
        mText := mEntry;
        Inc(mEntry, Length(mText) + 1);
        // Einträge wie "=C:=C:\…" (Laufwerke der Konsole) haben keinen Namen.
        mEqual := Pos('=', mText, 2);
        if mEqual > 1 then
        begin
          mList.Add(TPair<string, string>.Create(Copy(mText, 1, mEqual - 1), Copy(mText, mEqual + 1, MaxInt)));
        end;
      end;
    finally
      FreeEnvironmentStrings(mBlock);
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TDelphiInstallation.ExpandFor(const AText, APlatform: string): string;
var
  mIndex: Integer;
begin
  Result := AText;
  // Variablen dürfen auf andere verweisen; drei Durchgänge genügen in der Praxis.
  for mIndex := 1 to 3 do
  begin
    Result := TProjectPaths.ExpandVariables(Result,
      FVariables + [TPair<string, string>.Create('Platform', APlatform)]);
    if Pos('$(', Result) = 0 then
    begin
      Break;
    end;
  end;
end;

function TDelphiInstallation.ReadPaths(const APlatform, AValueName: string): TArray<string>;
var
  mRegistry: TRegistry;
  mItem: string;
begin
  Result := nil;
  mRegistry := OpenRead(HKEY_CURRENT_USER, FBaseKey + '\Library\' + APlatform);
  if mRegistry = nil then
  begin
    Exit;
  end;
  try
    if not mRegistry.ValueExists(AValueName) then
    begin
      Exit;
    end;
    for mItem in TProjectPaths.SplitList(mRegistry.ReadString(AValueName)) do
    begin
      Result := Result + [TProjectPaths.Normalize(ExpandFor(mItem, APlatform))];
    end;
  finally
    mRegistry.Free;
  end;
end;

function TDelphiInstallation.LibraryPaths(const APlatform: string): TArray<string>;
begin
  Result := ReadPaths(APlatform, 'Search Path');
end;

function TDelphiInstallation.BrowsingPaths(const APlatform: string): TArray<string>;
begin
  Result := ReadPaths(APlatform, 'Browsing Path');
  // L2: Win64x (modernes 64-Bit) hat in der Registry keinen Browsing Path; die Quellen sind die von Win64.
  if (Length(Result) = 0) and SameText(APlatform, 'Win64x') then
  begin
    Result := ReadPaths('Win64', 'Browsing Path');
  end;
end;

function TDelphiInstallation.Variables: TArray<TPair<string, string>>;
begin
  Result := FVariables;
end;

end.
