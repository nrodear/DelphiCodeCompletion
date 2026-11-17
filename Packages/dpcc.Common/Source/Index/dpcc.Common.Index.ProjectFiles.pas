unit dpcc.Common.Index.ProjectFiles;

// Was aus einem Projekt in den Index gehört: Hauptdatei und eingetragene
// Units in Projektreihenfolge (ohne Duplikate), dazu die aktiven Symbole
// aus Projekt, Plattform und Compilerversion.
// PathFiles listet alle Units von Suchpfaden (#648), damit auch Units in den
// Index kommen, die noch keine Unit einbindet.
// Zusätzliche Quellordner (L2, index.extraSourceFolders): ExpandFolder löst $(Name) und %Name% auf, FolderTree
// nimmt die Unterordner dazu (ohne .git, __history und __recovery), ExtraSignature ist ihr Cache-Schlüssel.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  dpcc.Common.Projects.Contract;

type
  /// <summary>Pascal-Units (*.pas) direkt in AFolder, ohne Unterordner; leer, wenn der Ordner fehlt.</summary>
  TIndexListUnits = reference to function(const AFolder: string): TArray<string>;
  /// <summary>True, wenn die Datei nicht in den Index soll (index.exclude).</summary>
  TIndexExcluded = reference to function(const AFileName: string): Boolean;
  /// <summary>Unterordner von AFolder (volle Pfade); leer, wenn er fehlt oder nicht lesbar ist.</summary>
  TIndexListFolders = reference to function(const AFolder: string): TArray<string>;
  /// <summary>Wert der Umgebungsvariablen AName; '' ohne.</summary>
  TIndexEnvironment = reference to function(const AName: string): string;

  TIndexProjectFiles = class
  public
    class function Files(const AProject: TProjectInfo): TArray<string>; static;
    /// <summary>Alle Units der Ordner APaths in deren Reihenfolge, je Ordner sortiert, ohne Duplikate,
    /// ohne die Dateien aus ASkip und ohne ausgeschlossene (#648). Suchpfade sind wie beim Compiler
    /// nicht rekursiv.</summary>
    class function PathFiles(const APaths: TArray<string>; const AListUnits: TIndexListUnits;
      const AExcluded: TIndexExcluded; const ASkip: TArray<string>): TArray<string>; static;
    /// <summary>ABdsVersion wie in der Registry, z. B. '23.0' für Delphi 12 (ergibt VER360); '' = ohne
    /// VERxxx.</summary>
    class function Defines(const AProject: TProjectInfo; const ABdsVersion: string): TArray<string>; static;
    /// <summary>Schlüssel für Projekt, Konfiguration, Plattform, Version, Symbole, Suchpfade und Namespaces;
    /// gleicher Schlüssel, gleicher Index. Ändert sich einer davon, gilt der Cache nicht mehr.</summary>
    class function Signature(const AProject: TProjectInfo; const ACompilerVersion: string): string; static;
    /// <summary>Symbole für die Units der Installation (#647): nur Plattform und Compilerversion. RTL, VCL
    /// und FMX kommen als fertige DCUs; die Defines des Projekts wirken auf sie nicht.</summary>
    class function LibraryDefines(const AProject: TProjectInfo; const ABdsVersion: string): TArray<string>; static;
    /// <summary>Schlüssel des Bibliotheks-Caches (#492): Compilerversion und Plattform, ohne Projekt und
    /// ohne dessen Defines (#647). Alle Projekte und Konfigurationen teilen sich RTL/VCL/FMX.</summary>
    class function LibrarySignature(const AProject: TProjectInfo; const ACompilerVersion: string): string; static;
    /// <summary>Zusätzlicher Quellordner AFolder mit aufgelösten Verweisen (L2): $(Name) aus AVariables, dann aus
    /// AEnvironment; %Name% aus AEnvironment. '' wenn ein Verweis $(…) offen bleibt.</summary>
    class function ExpandFolder(const AFolder: string; const AVariables: TArray<TPair<string, string>>;
      const AEnvironment: TIndexEnvironment): string; static;
    /// <summary>Die Ordner ARoots samt aller Unterordner (L2), jeder einmal, Wurzeln in ihrer Reihenfolge und darunter
    /// alphabetisch; ohne .git, __history und __recovery. Höchstens AMaxFolders Ordner; ATruncated sagt, ob die
    /// Grenze griff.</summary>
    class function FolderTree(const ARoots: TArray<string>; const AListFolders: TIndexListFolders;
      AMaxFolders: Integer; out ATruncated: Boolean): TArray<string>; static;
    /// <summary>Ist AFolderName (ohne Pfad) ein Ordner, den der Index nie durchsucht (.git, __history, __recovery)?
    /// </summary>
    class function SkippedFolder(const AFolderName: string): Boolean; static;
    /// <summary>Schlüssel des Caches der zusätzlichen Quellordner (L2): Compilerversion und Plattform wie die
    /// Bibliothek, dazu die Wurzeln (ohne Reihenfolge und Schreibweise).</summary>
    class function ExtraSignature(const AProject: TProjectInfo; const ACompilerVersion: string;
      const ARoots: TArray<string>): string; static;
  end;

implementation

uses
  System.Generics.Defaults,
  dpcc.Common.Projects.Paths,
  dpcc.Common.Pascal.Preprocessor;

/// <summary>Symbole in Großschreibung, sortiert: Reihenfolge und Schreibweise ändern den Index nicht.</summary>
function SortedKey(const AItems: TArray<string>): string;
var
  mItems: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mItems, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    mItems[mIndex] := UpperCase(Trim(AItems[mIndex]));
  end;
  TArray.Sort<string>(mItems);
  Result := String.Join(';', mItems);
end;

{ TIndexProjectFiles }

class function TIndexProjectFiles.Files(const AProject: TProjectInfo): TArray<string>;
var
  mFound: TList<string>;
  mSeen: TDictionary<string, Boolean>;
  mProjectUnit: TProjectUnit;

  procedure AddFile(const AFileName: string);
  begin
    if (AFileName <> '') and not mSeen.ContainsKey(AnsiUpperCase(AFileName)) then
    begin
      mSeen.Add(AnsiUpperCase(AFileName), True);
      mFound.Add(AFileName);
    end;
  end;

begin
  mFound := TList<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    AddFile(AProject.MainSource);
    for mProjectUnit in AProject.Units do
    begin
      AddFile(mProjectUnit.FileName);
    end;
    Result := mFound.ToArray;
  finally
    mSeen.Free;
    mFound.Free;
  end;
end;

class function TIndexProjectFiles.PathFiles(const APaths: TArray<string>; const AListUnits: TIndexListUnits;
  const AExcluded: TIndexExcluded; const ASkip: TArray<string>): TArray<string>;
var
  mFound: TList<string>;
  mSeen, mFolders: TDictionary<string, Boolean>;
  mFolder, mKey, mFileName: string;
  mUnits: TArray<string>;
begin
  mFound := TList<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  mFolders := TDictionary<string, Boolean>.Create;
  try
    for mFileName in ASkip do
    begin
      mSeen.AddOrSetValue(AnsiUpperCase(mFileName), True);
    end;
    for mFolder in APaths do
    begin
      mKey := AnsiUpperCase(ExcludeTrailingPathDelimiter(Trim(mFolder)));
      if (mKey = '') or mFolders.ContainsKey(mKey) then
      begin
        Continue;
      end;
      mFolders.Add(mKey, True);
      mUnits := AListUnits(ExcludeTrailingPathDelimiter(Trim(mFolder)));
      TArray.Sort<string>(mUnits);
      for mFileName in mUnits do
      begin
        mKey := AnsiUpperCase(mFileName);
        if mSeen.ContainsKey(mKey) then
        begin
          Continue;
        end;
        mSeen.Add(mKey, True);
        if Assigned(AExcluded) and AExcluded(mFileName) then
        begin
          Continue;
        end;
        mFound.Add(mFileName);
      end;
    end;
    Result := mFound.ToArray;
  finally
    mFolders.Free;
    mSeen.Free;
    mFound.Free;
  end;
end;

class function TIndexProjectFiles.Defines(const AProject: TProjectInfo; const ABdsVersion: string): TArray<string>;
var
  mVersion: Double;
begin
  if not TryStrToFloat(ABdsVersion, mVersion, TFormatSettings.Invariant) then
  begin
    mVersion := 0;
  end;
  // Dazu die Schalterstände für $IFOPT ("$R+", #847).
  Result := AProject.Defines + TPascalPreprocessor.PredefinedSymbols(AProject.Platform,
    TPascalPreprocessor.CompilerVersionOfBds(mVersion)) + TPascalPreprocessor.ProjectSwitches(AProject.Properties);
end;

class function TIndexProjectFiles.LibraryDefines(const AProject: TProjectInfo;
  const ABdsVersion: string): TArray<string>;
var
  mVersion: Double;
begin
  if not TryStrToFloat(ABdsVersion, mVersion, TFormatSettings.Invariant) then
  begin
    mVersion := 0;
  end;
  // Dazu die Vorgaben des Compilers für $IFOPT (L1, "$R-*" …): Die Bibliothek liest kein Projekt, und ohne
  // Schalterstand galten bei {$IFOPT R+} … {$ELSE} beide Zweige.
  Result := TPascalPreprocessor.PredefinedSymbols(AProject.Platform,
    TPascalPreprocessor.CompilerVersionOfBds(mVersion)) + TPascalPreprocessor.ProjectSwitches(nil);
end;

class function TIndexProjectFiles.LibrarySignature(const AProject: TProjectInfo;
  const ACompilerVersion: string): string;
begin
  // "2": Ältere Caches enthielten Units, die mit den Defines des Projekts gelesen wurden.
  Result := 'LIBRARY2|' + UpperCase(AProject.Platform) + '|' + ACompilerVersion;
end;

/// <summary>Ersetzt AOpen Name AClose in AText über AEnvironment; unbekannte Namen bleiben stehen.</summary>
function ExpandMarked(const AText, AOpen, AClose: string; const AEnvironment: TIndexEnvironment): string;
var
  mStart, mStop: Integer;
  mValue: string;
begin
  Result := AText;
  if not Assigned(AEnvironment) then
  begin
    Exit;
  end;
  mStart := Pos(AOpen, Result);
  while mStart > 0 do
  begin
    mStop := Pos(AClose, Result, mStart + Length(AOpen));
    if mStop = 0 then
    begin
      Break;
    end;
    mValue := '';
    if mStop > mStart + Length(AOpen) then
    begin
      mValue := AEnvironment(Copy(Result, mStart + Length(AOpen), mStop - mStart - Length(AOpen)));
    end;
    if mValue = '' then
    begin
      // Kein bekannter Name: hinter dem öffnenden Zeichen weitersuchen.
      mStart := Pos(AOpen, Result, mStart + 1);
      Continue;
    end;
    Result := Copy(Result, 1, mStart - 1) + mValue + Copy(Result, mStop + Length(AClose), MaxInt);
    mStart := Pos(AOpen, Result, mStart + Length(mValue));
  end;
end;

class function TIndexProjectFiles.ExpandFolder(const AFolder: string; const AVariables: TArray<TPair<string, string>>;
  const AEnvironment: TIndexEnvironment): string;
var
  mPass: Integer;
begin
  Result := Trim(AFolder);
  // Variablen dürfen auf andere verweisen; drei Durchgänge wie bei den Bibliothekspfaden.
  for mPass := 1 to 3 do
  begin
    Result := ExpandMarked(TProjectPaths.ExpandVariables(Result, AVariables), '$(', ')', AEnvironment);
    Result := ExpandMarked(Result, '%', '%', AEnvironment);
    if Pos('$(', Result) = 0 then
    begin
      Break;
    end;
  end;
  if (Result = '') or (Pos('$(', Result) > 0) then
  begin
    Exit('');
  end;
  Result := TProjectPaths.Normalize(Result);
end;

class function TIndexProjectFiles.SkippedFolder(const AFolderName: string): Boolean;
begin
  Result := SameText(AFolderName, '.git') or SameText(AFolderName, '__history') or
    SameText(AFolderName, '__recovery');
end;

class function TIndexProjectFiles.FolderTree(const ARoots: TArray<string>; const AListFolders: TIndexListFolders;
  AMaxFolders: Integer; out ATruncated: Boolean): TArray<string>;
var
  mFound: TList<string>;
  mSeen: TDictionary<string, Boolean>;
  mPending: TStack<string>;
  mRoot, mFolder, mKey: string;
  mChildren: TArray<string>;
  mIndex: Integer;
begin
  ATruncated := False;
  mFound := TList<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  mPending := TStack<string>.Create;
  try
    for mRoot in ARoots do
    begin
      if Trim(mRoot) = '' then
      begin
        Continue;
      end;
      mPending.Clear;
      mPending.Push(ExcludeTrailingPathDelimiter(Trim(mRoot)));
      // Tiefe zuerst, Geschwister alphabetisch: dieselbe Reihenfolge bei jedem Aufbau (Schlüssel der Unit-Listen).
      while (mPending.Count > 0) and not ATruncated do
      begin
        mFolder := mPending.Pop;
        mKey := AnsiUpperCase(mFolder);
        if mSeen.ContainsKey(mKey) then
        begin
          Continue;
        end;
        if mFound.Count >= AMaxFolders then
        begin
          ATruncated := True;
          Continue;
        end;
        mSeen.Add(mKey, True);
        mFound.Add(mFolder);
        mChildren := AListFolders(mFolder);
        TArray.Sort<string>(mChildren, TIStringComparer.Ordinal);
        for mIndex := High(mChildren) downto 0 do
        begin
          if not SkippedFolder(ExtractFileName(ExcludeTrailingPathDelimiter(mChildren[mIndex]))) then
          begin
            mPending.Push(ExcludeTrailingPathDelimiter(mChildren[mIndex]));
          end;
        end;
      end;
    end;
    Result := mFound.ToArray;
  finally
    mPending.Free;
    mSeen.Free;
    mFound.Free;
  end;
end;

class function TIndexProjectFiles.ExtraSignature(const AProject: TProjectInfo; const ACompilerVersion: string;
  const ARoots: TArray<string>): string;
begin
  // Mit den Symbolen der Bibliothek gelesen (TIndexFileDefines): Plattform und Version gehören in den Schlüssel.
  Result := 'EXTRA1|' + UpperCase(AProject.Platform) + '|' + ACompilerVersion + '|' + SortedKey(ARoots);
end;

class function TIndexProjectFiles.Signature(const AProject: TProjectInfo; const ACompilerVersion: string): string;
begin
  Result := AnsiUpperCase(AProject.FileName) + '|' + UpperCase(AProject.Config) + '|' +
    UpperCase(AProject.Platform) + '|' + ACompilerVersion + '|' + SortedKey(AProject.Defines) + '|' +
    AnsiUpperCase(String.Join(';', AProject.SearchPaths)) + '|' + UpperCase(String.Join(';', AProject.Namespaces)) +
    '|' + String.Join(';', TPascalPreprocessor.ProjectSwitches(AProject.Properties));
end;

end.
