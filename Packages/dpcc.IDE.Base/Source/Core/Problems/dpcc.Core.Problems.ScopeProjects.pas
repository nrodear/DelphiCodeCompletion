unit dpcc.Core.Problems.ScopeProjects;

// Bereichsliste des Fensters „dpcc-Prüfung“ mit einzelnen Projekten (#1843),
// ohne Open Tools API und ohne VCL. Die Liste hat immer die drei festen
// Einträge „Aktuelle Datei“, „Aktuelles Projekt“ und „Projektgruppe“ (in der
// Reihenfolge von TDpccFindingScope). Ist problems.window.scopeProjects an und
// hat die offene Gruppe mehr als ein Projekt, folgen ein Trennstrich (nicht
// wählbar) und je Projekt der Gruppe ein Eintrag in der Reihenfolge der Gruppe.
// Eine Wahl ist ein Bereich und bei „Projekt“ der Name eines Projekts
// ('' = das jeweils aktive). Ein gewähltes Projekt bleibt, auch wenn ein
// anderes aktiv wird; fehlt es in der Gruppe, gilt wieder das aktive.

interface

uses
  dpcc.Core.Problems.Findings;

type
  /// <summary>Ein Projekt der offenen Gruppe: Name (Dateiname ohne Endung), Projektdatei, aktiv?</summary>
  TDpccScopeProject = record
    Name: string;
    FileName: string;
    Active: Boolean;
    class function Create(const AFileName: string; AActive: Boolean): TDpccScopeProject; static;
  end;

  /// <summary>Gewählter Bereich; Project nur bei Scope = Project: Name des Einzelprojekts, '' = aktives Projekt.
  /// </summary>
  TDpccScopeChoice = record
    Scope: TDpccFindingScope;
    Project: string;
    class function Create(AScope: TDpccFindingScope; const AProject: string): TDpccScopeChoice; static;
    /// <summary>Gleicher Bereich und gleiches Projekt (Groß-/Kleinschreibung egal)?</summary>
    function Same(const AOther: TDpccScopeChoice): Boolean;
  end;

  /// <summary>Einträge der Bereichsliste: feste Bereiche, Trennstrich, Einzelprojekte.</summary>
  TDpccScopeList = record
  private
    /// <summary>Alle Projekte der Gruppe bzw. gezeigte Einzelprojekte (leer ohne Einzelprojekte).</summary>
    FAll: TArray<TDpccScopeProject>;
    FProjects: TArray<TDpccScopeProject>;
    /// <summary>Index des ersten Projekts, -1 ohne Einzelprojekte.</summary>
    function FirstProject: Integer;
  public
    /// <summary>Liste zu den Projekten der Gruppe; Einzelprojekte nur mit AShowProjects und mehr als einem
    /// Projekt.</summary>
    class function Create(const AProjects: TArray<TDpccScopeProject>; AShowProjects: Boolean): TDpccScopeList;
      static;
    /// <summary>Zahl der Einträge samt Trennstrich.</summary>
    function Count: Integer;
    /// <summary>Index des Trennstrichs, -1 ohne Einzelprojekte.</summary>
    function SeparatorIndex: Integer;
    function IsSeparator(AIndex: Integer): Boolean;
    /// <summary>Projekt des Eintrags AIndex; False für feste Einträge, Trennstrich und außerhalb.</summary>
    function ProjectAt(AIndex: Integer; out AProject: TDpccScopeProject): Boolean;
    /// <summary>Wahl zum Eintrag AIndex; Trennstrich und außerhalb ergeben „Aktuelles Projekt“.</summary>
    function ChoiceAt(AIndex: Integer): TDpccScopeChoice;
    /// <summary>Eintrag zur Wahl: Einzelprojekt, sonst der feste Eintrag ihres Bereichs.</summary>
    function IndexOf(const AChoice: TDpccScopeChoice): Integer;
    /// <summary>Wahl, die gilt: Ein Einzelprojekt, das die Gruppe nicht (mehr) hat oder das die Liste nicht zeigt
    /// (Einzelprojekte aus, nur ein Projekt), wird zum aktiven Projekt. Ohne bekannte Projekte (Gruppe noch nicht
    /// geladen) bleibt die Wahl.</summary>
    function Resolve(const AChoice: TDpccScopeChoice): TDpccScopeChoice;
    /// <summary>Name des aktiven Projekts, '' ohne.</summary>
    function ActiveName: string;
    /// <summary>Kennung der Einträge (Projekte und aktives); gleich = die Liste muss nicht neu gefüllt werden.
    /// </summary>
    function Key: string;
    property Projects: TArray<TDpccScopeProject> read FProjects;
  end;

  TDpccScopeFiles = class
  public
    /// <summary>Alle Dateien der Listen ohne Doppelte (Groß-/Kleinschreibung egal), in der Reihenfolge des ersten
    /// Auftretens.</summary>
    class function Union(const ALists: TArray<TArray<string>>): TArray<string>; static;
    /// <summary>Projekt mit dem Namen AName (Groß-/Kleinschreibung egal); False, wenn keins so heißt.</summary>
    class function Find(const AProjects: TArray<TDpccScopeProject>; const AName: string;
      out AProject: TDpccScopeProject): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections;

const
  /// <summary>Feste Einträge: TDpccFindingScope.</summary>
  cFixedCount = Ord(High(TDpccFindingScope)) + 1;

{ TDpccScopeProject }

class function TDpccScopeProject.Create(const AFileName: string; AActive: Boolean): TDpccScopeProject;
begin
  Result.FileName := AFileName;
  Result.Name := ChangeFileExt(ExtractFileName(AFileName.Replace('/', PathDelim)), '');
  Result.Active := AActive;
end;

{ TDpccScopeChoice }

class function TDpccScopeChoice.Create(AScope: TDpccFindingScope; const AProject: string): TDpccScopeChoice;
begin
  Result.Scope := AScope;
  Result.Project := '';
  if AScope = TDpccFindingScope.Project then
  begin
    Result.Project := Trim(AProject);
  end;
end;

function TDpccScopeChoice.Same(const AOther: TDpccScopeChoice): Boolean;
begin
  Result := (Scope = AOther.Scope) and SameText(Project, AOther.Project);
end;

{ TDpccScopeList }

class function TDpccScopeList.Create(const AProjects: TArray<TDpccScopeProject>;
  AShowProjects: Boolean): TDpccScopeList;
begin
  Result.FAll := Copy(AProjects);
  Result.FProjects := nil;
  if AShowProjects and (Length(AProjects) > 1) then
  begin
    Result.FProjects := Copy(AProjects);
  end;
end;

function TDpccScopeList.FirstProject: Integer;
begin
  Result := -1;
  if Length(FProjects) > 0 then
  begin
    Result := cFixedCount + 1;
  end;
end;

function TDpccScopeList.Count: Integer;
begin
  Result := cFixedCount;
  if Length(FProjects) > 0 then
  begin
    Result := cFixedCount + 1 + Length(FProjects);
  end;
end;

function TDpccScopeList.SeparatorIndex: Integer;
begin
  Result := -1;
  if Length(FProjects) > 0 then
  begin
    Result := cFixedCount;
  end;
end;

function TDpccScopeList.IsSeparator(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex = SeparatorIndex);
end;

function TDpccScopeList.ProjectAt(AIndex: Integer; out AProject: TDpccScopeProject): Boolean;
var
  mOffset: Integer;
begin
  AProject := Default(TDpccScopeProject);
  mOffset := AIndex - FirstProject;
  Result := (FirstProject >= 0) and (mOffset >= 0) and (mOffset < Length(FProjects));
  if Result then
  begin
    AProject := FProjects[mOffset];
  end;
end;

function TDpccScopeList.ChoiceAt(AIndex: Integer): TDpccScopeChoice;
var
  mProject: TDpccScopeProject;
begin
  if (AIndex >= 0) and (AIndex < cFixedCount) then
  begin
    Exit(TDpccScopeChoice.Create(TDpccFindingScope(AIndex), ''));
  end;
  if ProjectAt(AIndex, mProject) then
  begin
    Exit(TDpccScopeChoice.Create(TDpccFindingScope.Project, mProject.Name));
  end;
  Result := TDpccScopeChoice.Create(TDpccFindingScope.Project, '');
end;

function TDpccScopeList.IndexOf(const AChoice: TDpccScopeChoice): Integer;
var
  mIndex: Integer;
begin
  Result := Ord(AChoice.Scope);
  if (AChoice.Scope <> TDpccFindingScope.Project) or (AChoice.Project = '') then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FProjects) do
  begin
    if SameText(FProjects[mIndex].Name, AChoice.Project) then
    begin
      Exit(FirstProject + mIndex);
    end;
  end;
end;

function TDpccScopeList.Resolve(const AChoice: TDpccScopeChoice): TDpccScopeChoice;
begin
  Result := AChoice;
  if (Length(FAll) > 0) and (Result.Project <> '') and (IndexOf(Result) = Ord(Result.Scope)) then
  begin
    Result.Project := '';
  end;
end;

function TDpccScopeList.ActiveName: string;
var
  mProject: TDpccScopeProject;
begin
  Result := '';
  for mProject in FAll do
  begin
    if mProject.Active then
    begin
      Exit(mProject.Name);
    end;
  end;
end;

function TDpccScopeList.Key: string;
var
  mProject: TDpccScopeProject;
begin
  Result := Length(FProjects).ToString;
  for mProject in FAll do
  begin
    Result := Result + '|' + mProject.FileName;
    if mProject.Active then
    begin
      Result := Result + '*';
    end;
  end;
end;

{ TDpccScopeFiles }

class function TDpccScopeFiles.Union(const ALists: TArray<TArray<string>>): TArray<string>;
var
  mSeen: TDictionary<string, Boolean>;
  mFiles: TList<string>;
  mList: TArray<string>;
  mName: string;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  mFiles := TList<string>.Create;
  try
    for mList in ALists do
    begin
      for mName in mList do
      begin
        if (mName <> '') and mSeen.TryAdd(mName.ToLower, True) then
        begin
          mFiles.Add(mName);
        end;
      end;
    end;
    Result := mFiles.ToArray;
  finally
    mFiles.Free;
    mSeen.Free;
  end;
end;

class function TDpccScopeFiles.Find(const AProjects: TArray<TDpccScopeProject>; const AName: string;
  out AProject: TDpccScopeProject): Boolean;
var
  mProject: TDpccScopeProject;
begin
  AProject := Default(TDpccScopeProject);
  for mProject in AProjects do
  begin
    if SameText(mProject.Name, Trim(AName)) then
    begin
      AProject := mProject;
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
