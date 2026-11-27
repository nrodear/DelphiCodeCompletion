unit Shell.LspServer.RadStudio.Settings;

// Host-Rolle Shell, nur in dpcc.LspServer.exe: Projektdaten der RAD-Studio-IDE. Im LSP-Betrieb schickt die IDE sie
// per workspace/didChangeConfiguration (zweimal je Projekt) unter "settings":
//   project      URI der .dpr/.dpk des aktiven Projekts
//   dllname      Compiler der Code-Insight-Prüfung: dcc32290.dll (Delphi 12) bzw. dcc32370.dll (Delphi 13); daraus
//                Delphi-Version (BDS 23.0 bzw. 37.0) und Plattform (dcc32 = Win32, dcc64 = Win64)
//   dccOptions   die ganze Compiler-Befehlszeile: -D Symbole, -U Unit-Pfade, -I/-R/-O weitere Pfade, -NS Namespaces,
//                -A Unit-Aliase und Ausgabeordner, die hier keine Rolle spielen
//   projectFiles [{name, file}] die Units des Projekts (nur gezählt: der Server liest die .dproj selbst)
//   browsingPaths URIs des Browsing Path der IDE
//   CommonAppData URI des Profilordners …/Embarcadero/<Profil>/<Version>/; daraus der Registry-Schlüssel des Profils
//                (bds -r), unter dem der Server Variablen und Pfade der IDE liest
// TRadStudioProject.FromSettings bildet daraus den Projektkontext im Format von dpcc/projectContext
// (dpcc.Common.Lsp.IdeProject); ToContextJson liefert die Parameter dieser Benachrichtigung.
// Die -U-Pfade enthalten den Bibliothekspfad der IDE und den Suchpfad des Projekts in einer Liste. Pfade im
// Installationsordner von Delphi und in den Studio-Ordnern unter Dokumente bzw. Öffentliche Dokumente
// (…\Embarcadero\Studio\…) gelten als Bibliothek, alle übrigen als Suchpfad des Projekts. So indiziert dpcc die
// DCU-Ordner der Bibliothek nicht als Projekt; Quelltexte der Bibliothek kommen über den Browsing Path.

interface

uses
  System.SysUtils,
  System.JSON;

type
  /// <summary>Projektkontext aus den Einstellungen der RAD-Studio-IDE.</summary>
  TRadStudioProject = record
    /// <summary>Hauptdatei (.dpr/.dpk) als Pfad; '' ohne Angabe.</summary>
    MainFile: string;
    /// <summary>.dproj neben der Hauptdatei (wie die IDE sie anlegt), auch wenn sie fehlt.</summary>
    ProjectFile: string;
    DllName: string;
    /// <summary>BDS-Version aus dllname, z. B. "23.0"; '' unbekannt.</summary>
    BdsVersion: string;
    /// <summary>Plattform aus dllname, z. B. "Win32"; '' unbekannt.</summary>
    Platform: string;
    Defines: TArray<string>;
    /// <summary>-U ohne die Bibliothekspfade (siehe Kopf der Unit).</summary>
    SearchPaths: TArray<string>;
    /// <summary>-U im Installations- oder Studio-Ordner.</summary>
    LibraryPaths: TArray<string>;
    IncludePaths: TArray<string>;
    Namespaces: TArray<string>;
    /// <summary>Unit-Aliase aus -A ("WinTypes=Winapi.Windows").</summary>
    Aliases: TArray<string>;
    BrowsingPaths: TArray<string>;
    /// <summary>Registry-Schlüssel des Profils unter HKCU, z. B. Software\Embarcadero\BDS\37.0; '' unbekannt.</summary>
    RegistryKey: string;
    /// <summary>Zahl der Einträge in projectFiles.</summary>
    UnitCount: Integer;
    /// <summary>settings.project war gesetzt.</summary>
    function HasProject: Boolean;
    /// <summary>Liest die Parameter von didChangeConfiguration (mit oder ohne Hülle "settings"). Ohne "project"
    /// bleibt HasProject False.</summary>
    class function FromSettings(const AParams: TJSONValue): TRadStudioProject; static;
    /// <summary>Delphi-Version aus dem Namen der Compiler-DLL: dcc32290.dll → 23.0, dcc32370.dll → 37.0; ''
    /// unbekannt.</summary>
    class function VersionOfDll(const ADllName: string): string; static;
    /// <summary>Plattform aus dem Namen der Compiler-DLL; '' unbekannt.</summary>
    class function PlatformOfDll(const ADllName: string): string; static;
    /// <summary>Zerlegt eine Compiler-Befehlszeile in Schalter; Anführungszeichen umschließen Teile mit
    /// Leerzeichen und fallen weg.</summary>
    class function SplitCommandLine(const ALine: string): TArray<string>; static;
    /// <summary>Liste hinter einem Schalter: durch ";" getrennt, ohne leere Einträge und ohne
    /// Anführungszeichen.</summary>
    class function SplitList(const AValue: string): TArray<string>; static;
    /// <summary>Registry-Schlüssel aus dem Profilordner …/Embarcadero/&lt;Profil&gt;/&lt;Version&gt;/; ''
    /// sonst.</summary>
    class function RegistryKeyOfAppData(const APath: string): string; static;
    /// <summary>Liegt APath in der Installation oder in einem Studio-Ordner (Bibliothek)?</summary>
    class function IsLibraryPath(const APath: string): Boolean; static;
    /// <summary>Parameter für dpcc/projectContext (aktives Projekt); gehört dem Aufrufer.</summary>
    function ToContextJson: TJSONObject;
    /// <summary>Eine Zeile fürs Protokoll, ohne Pfade.</summary>
    function Describe: string;
  end;

implementation

uses
  System.StrUtils,
  dpcc.Common.Documents.Uris;

function JsonList(const AItems: TArray<string>): TJSONArray;
var
  mItem: string;
begin
  Result := TJSONArray.Create;
  for mItem in AItems do
  begin
    Result.Add(mItem);
  end;
end;

/// <summary>Hängt AValue an AList an, wenn es noch nicht darin steht (ohne Groß-/Kleinschreibung).</summary>
procedure AddUnique(var AList: TArray<string>; const AValue: string);
begin
  if (AValue <> '') and (IndexText(AValue, AList) < 0) then
  begin
    AList := AList + [AValue];
  end;
end;

{ TRadStudioProject }

function TRadStudioProject.HasProject: Boolean;
begin
  Result := MainFile <> '';
end;

class function TRadStudioProject.VersionOfDll(const ADllName: string): string;
var
  mName, mDigits: string;
  mIndex, mNumber: Integer;
begin
  Result := '';
  mName := ChangeFileExt(ExtractFileName(Trim(ADllName)), '');
  // Die letzten drei Ziffern: 290, 370 …
  mIndex := Length(mName);
  while (mIndex > 0) and CharInSet(mName[mIndex], ['0'..'9']) do
  begin
    Dec(mIndex);
  end;
  mDigits := Copy(mName, mIndex + 1, MaxInt);
  if Length(mDigits) < 3 then
  begin
    Exit;
  end;
  mDigits := Copy(mDigits, Length(mDigits) - 2, 3);
  if not TryStrToInt(mDigits, mNumber) or (mNumber < 100) then
  begin
    Exit;
  end;
  // Bis Delphi 12 hing die BDS-Version um 6 hinter der Package-Version (290 → 23.0); seit Delphi 13 sind beide
  // gleich (370 → 37.0).
  if mNumber >= 370 then
  begin
    Result := Format('%d.0', [mNumber div 10]);
  end
  else
  begin
    Result := Format('%d.0', [mNumber div 10 - 6]);
  end;
end;

class function TRadStudioProject.PlatformOfDll(const ADllName: string): string;
const
  cPrefixes: array[0..8] of string = ('dccosxarm64', 'dcciosarm64', 'dcciossimarm64', 'dccaarm64', 'dcclinux64',
    'dccosx64', 'dccaarm', 'dcc64', 'dcc32');
  cPlatforms: array[0..8] of string = ('OSXARM64', 'iOSDevice64', 'iOSSimARM64', 'Android64', 'Linux64', 'OSX64',
    'Android', 'Win64', 'Win32');
var
  mName: string;
  mIndex: Integer;
begin
  Result := '';
  mName := LowerCase(ExtractFileName(Trim(ADllName)));
  for mIndex := Low(cPrefixes) to High(cPrefixes) do
  begin
    if StartsStr(cPrefixes[mIndex], mName) then
    begin
      Exit(cPlatforms[mIndex]);
    end;
  end;
end;

class function TRadStudioProject.SplitCommandLine(const ALine: string): TArray<string>;
var
  mIndex: Integer;
  mQuoted: Boolean;
  mCurrent: TStringBuilder;

  procedure Flush;
  begin
    if mCurrent.Length > 0 then
    begin
      Result := Result + [mCurrent.ToString];
      mCurrent.Clear;
    end;
  end;

begin
  Result := nil;
  mQuoted := False;
  mCurrent := TStringBuilder.Create;
  try
    for mIndex := 1 to Length(ALine) do
    begin
      if ALine[mIndex] = '"' then
      begin
        // Anführungszeichen umschließen nur Teile ("-I"c:\a b";c:\c"): Sie fallen weg, das Leerzeichen bleibt.
        mQuoted := not mQuoted;
      end
      else if not mQuoted and CharInSet(ALine[mIndex], [' ', #9, #13, #10]) then
      begin
        Flush;
      end
      else
      begin
        mCurrent.Append(ALine[mIndex]);
      end;
    end;
    Flush;
  finally
    mCurrent.Free;
  end;
end;

class function TRadStudioProject.SplitList(const AValue: string): TArray<string>;
var
  mItem, mValue: string;
begin
  Result := nil;
  for mItem in AValue.Split([';']) do
  begin
    mValue := Trim(StringReplace(mItem, '"', '', [rfReplaceAll]));
    if mValue <> '' then
    begin
      Result := Result + [mValue];
    end;
  end;
end;

class function TRadStudioProject.RegistryKeyOfAppData(const APath: string): string;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  Result := '';
  mParts := ExcludeTrailingPathDelimiter(StringReplace(APath, '/', '\', [rfReplaceAll])).Split(['\']);
  // …\Embarcadero\<Profil>\<Version>
  for mIndex := High(mParts) - 2 downto 0 do
  begin
    if SameText(mParts[mIndex], 'Embarcadero') and (mIndex + 2 = High(mParts)) and (mParts[mIndex + 1] <> '') and
      (mParts[mIndex + 2] <> '') and CharInSet(mParts[mIndex + 2][1], ['0'..'9']) then
    begin
      Exit('Software\Embarcadero\' + mParts[mIndex + 1] + '\' + mParts[mIndex + 2]);
    end;
  end;
end;

class function TRadStudioProject.IsLibraryPath(const APath: string): Boolean;
var
  mPath: string;
begin
  mPath := LowerCase(IncludeTrailingPathDelimiter(StringReplace(APath, '/', '\', [rfReplaceAll])));
  // Installationsordner (…\Embarcadero\Studio\37.0\) und die Studio-Ordner unter Dokumente und Öffentliche
  // Dokumente (…\Embarcadero\Studio\37.0\Imports, …\Dcp, CatalogRepository) sowie Variablen wie $(BDS).
  Result := ContainsStr(mPath, '\embarcadero\studio\') or StartsStr('$(bds', mPath) or
    StartsStr('$(platform', mPath);
end;

/// <summary>Pfad aus einer URI oder einem Pfad.</summary>
function PathOf(const AValue: string): string;
begin
  if StartsText('file:', AValue) then
  begin
    Result := TDocumentUris.ToPath(AValue);
  end
  else
  begin
    Result := AValue;
  end;
end;

class function TRadStudioProject.FromSettings(const AParams: TJSONValue): TRadStudioProject;
var
  mSettings: TJSONObject;
  mValue: TJSONValue;
  mOption, mPath: string;
  mItem: TJSONValue;
  mFile: string;
begin
  Result := Default(TRadStudioProject);
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  mSettings := TJSONObject(AParams);
  if mSettings.GetValue('settings') is TJSONObject then
  begin
    mSettings := TJSONObject(mSettings.GetValue('settings'));
  end;
  mValue := mSettings.GetValue('project');
  if (mValue is TJSONString) and (Trim(mValue.Value) <> '') then
  begin
    Result.MainFile := PathOf(Trim(mValue.Value));
    Result.ProjectFile := ChangeFileExt(Result.MainFile, '.dproj');
  end;
  Result.DllName := mSettings.GetValue<string>('dllname', '');
  Result.BdsVersion := VersionOfDll(Result.DllName);
  Result.Platform := PlatformOfDll(Result.DllName);
  for mOption in SplitCommandLine(mSettings.GetValue<string>('dccOptions', '')) do
  begin
    // Schalter mit zwei Buchstaben zuerst: -NS vor -N…, -LE/-LN/-LU vor -L.
    if StartsText('-NS', mOption) then
    begin
      for mPath in SplitList(Copy(mOption, 4, MaxInt)) do
      begin
        AddUnique(Result.Namespaces, mPath);
      end;
    end
    else if StartsText('-N', mOption) or StartsText('-L', mOption) or StartsText('-E', mOption) or
      StartsText('--', mOption) or StartsText('-$', mOption) then
    begin
      // Ausgabeordner, Packages, Compilerschalter: für den Index ohne Bedeutung.
    end
    else if StartsStr('-D', mOption) or StartsStr('-d', mOption) then
    begin
      for mPath in SplitList(Copy(mOption, 3, MaxInt)) do
      begin
        AddUnique(Result.Defines, UpperCase(mPath));
      end;
    end
    else if StartsStr('-U', mOption) or StartsStr('-u', mOption) then
    begin
      for mPath in SplitList(Copy(mOption, 3, MaxInt)) do
      begin
        if IsLibraryPath(mPath) then
        begin
          AddUnique(Result.LibraryPaths, mPath);
        end
        else
        begin
          AddUnique(Result.SearchPaths, mPath);
        end;
      end;
    end
    else if StartsStr('-I', mOption) or StartsStr('-i', mOption) then
    begin
      for mPath in SplitList(Copy(mOption, 3, MaxInt)) do
      begin
        AddUnique(Result.IncludePaths, mPath);
      end;
    end
    else if StartsStr('-A', mOption) or StartsStr('-a', mOption) then
    begin
      for mPath in SplitList(Copy(mOption, 3, MaxInt)) do
      begin
        AddUnique(Result.Aliases, mPath);
      end;
    end;
  end;
  mValue := mSettings.GetValue('browsingPaths');
  if mValue is TJSONArray then
  begin
    for mItem in TJSONArray(mValue) do
    begin
      if mItem is TJSONString then
      begin
        AddUnique(Result.BrowsingPaths, ExcludeTrailingPathDelimiter(PathOf(Trim(mItem.Value))));
      end;
    end;
  end;
  mFile := mSettings.GetValue<string>('CommonAppData', '');
  if mFile <> '' then
  begin
    Result.RegistryKey := RegistryKeyOfAppData(PathOf(mFile));
  end;
  mValue := mSettings.GetValue('projectFiles');
  if mValue is TJSONArray then
  begin
    Result.UnitCount := TJSONArray(mValue).Count;
  end;
end;

function TRadStudioProject.ToContextJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', ProjectFile);
  Result.AddPair('configuration', '');
  Result.AddPair('platform', Platform);
  if BdsVersion <> '' then
  begin
    Result.AddPair('bdsVersion', BdsVersion);
  end;
  Result.AddPair('defines', JsonList(Defines));
  Result.AddPair('searchPaths', JsonList(SearchPaths));
  Result.AddPair('namespaces', JsonList(Namespaces));
  if Length(LibraryPaths) > 0 then
  begin
    Result.AddPair('libraryPaths', JsonList(LibraryPaths));
  end;
  if Length(BrowsingPaths) > 0 then
  begin
    Result.AddPair('browsingPaths', JsonList(BrowsingPaths));
  end;
  if RegistryKey <> '' then
  begin
    Result.AddPair('registryKey', RegistryKey);
  end;
  Result.AddPair('active', TJSONBool.Create(True));
end;

function TRadStudioProject.Describe: string;
begin
  Result := Format('%s, BDS %s, %s: Defines %s; %d Suchpfade, %d Bibliothekspfade, %d Namespaces, %d Aliase, ' +
    '%d Browsing-Pfade, %d Units, Registry-Schlüssel des Profils: %s', [ExtractFileExt(MainFile), BdsVersion,
    Platform, string.Join(';', Defines), Length(SearchPaths), Length(LibraryPaths), Length(Namespaces),
    Length(Aliases), Length(BrowsingPaths), UnitCount, BoolToStr(RegistryKey <> '', True)]);
end;

end.
