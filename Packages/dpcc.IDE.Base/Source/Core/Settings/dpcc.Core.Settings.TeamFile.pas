unit dpcc.Core.Settings.TeamFile;

// Projektdatei .dpcc (#486): Einstellungen des Plugins für alle im Team, im
// Repository eingecheckt. Persönliche Einstellungen (Registry) bleiben davon
// getrennt; die Einstellungen des Servers stehen in dpcc.json (#403). Teil
// ohne VCL und Open Tools API: Datei finden, lesen, prüfen und den Vorrang vor
// den persönlichen Einstellungen bestimmen.
// - Ort: der nächste Ordner mit .dpcc ab dem Ordner der .dproj aufwärts bis
//   zur Wurzel des Repositorys (nächster Ordner mit .git oder .svn); ohne
//   Repository bis zum Ordner der geöffneten .groupproj, wenn sie darüber
//   liegt, sonst nur der Ordner der .dproj. Danach der Ordner der .groupproj
//   (etwa eine Gruppe außerhalb des Repositorys). Relative Pfade gelten ab
//   dem Ordner der Datei.
// - Format: JSON mit Kommentaren (// und /* */) und Schema-Version:
//     {"version": 1,
//      "naming": {"field": "F", "parameter": "A", "local": "L",         #452
//                 "constant": "c"},                                   #1111
//      "formatFunctions": [{"name": "Log", "formatIndex": 0}],         #451
//      "sqlTargets": ["TMyQuery.SQL"],                                  #462
//      "fileMethods": ["TDateien.Laden"],                               #478
//      "mainThreadExceptions": ["TLogger.Write"],                       #484
//      "startProfiles": [{"name": "Demo", "parameters": "-demo",        #575
//        "workingDir": "Bin", "host": "", "environment": {"MODUS": "demo"}}],
//      "ci": {"provider": "jenkins", "url": "https://ci.firma.de",      #763
//             "job": "kasse", "multibranch": true},
//      "tracker": {"provider": "youtrack",                              #765
//                  "url": "https://firma.youtrack.cloud", "project": "ATL"},
//      "vcs": {"provider": "svn", "mainBranch": "trunk"},              #1286
//      "hidden": [{"setting": "BlockEndLabels", "file": "Source/Kunde.pas", #628
//                  "anchor": "TKunde.Speichern"}],
//      "debugDisplayRules": {                                            #854
//        "FireDAC.Comp.Client.TFDConnection": "{ConnectionName} ({DriverName})",
//        "TKunde": {"template": "{Name}, {Ort}", "children": ["Name", "Ort"]}}}
// - Verboten und beim Lesen ignoriert (mit Meldung, dpcc.Text.Checkin):
//   Zugangsdaten (Schlüssel wie token oder password auf jeder Ebene, Adressen
//   mit Benutzer oder Token, Umgebungsvariablen wie DB_PASSWORD), absolute
//   Pfade und relative Pfade, die aus der Wurzel herausführen. Ein Startprofil
//   mit solchem Inhalt entfällt ganz. Benutzer und Token für CI und Tracker
//   gehören in den Anmeldespeicher von Windows.
// - Fehlerhafte Datei (kein JSON oder kein Objekt): Valid ist False, es gelten
//   nur die persönlichen Einstellungen. Unbekannte Schlüssel und falsche Typen
//   werden gemeldet und übergangen; der Rest gilt.
// - Vorrang: ein Wert aus .dpcc schlägt die persönliche Einstellung (Präfixe,
//   Format-Index und Startprofil gleichen Namens); Listen ergänzen sich, die
//   Einträge der Projektdatei zuerst.

interface

uses
  System.SysUtils,
  dpcc.Core.Settings.HiddenPlaces;

type
{$SCOPEDENUMS ON}
  /// <summary>Präfix-Arten der Benennung (#452); Constant nur für die Prüfregel naming-prefix (#1111).</summary>
  TDpccNamingKind = (Field, Parameter, Local, Constant);

  /// <summary>Art einer Meldung zur Projektdatei.</summary>
  TDpccTeamIssueKind = (
    /// <summary>Kein JSON oder kein Objekt; die Datei gilt nicht.</summary>
    Syntax,
    /// <summary>"version" fehlt oder ist neuer als CurrentVersion.</summary>
    Version,
    UnknownKey,
    WrongType,
    InvalidValue,
    Credential,
    AbsolutePath,
    OutsidePath);
{$SCOPEDENUMS OFF}

  /// <summary>Meldung zur Projektdatei; den Text bildet die Oberfläche aus Kind und Path.</summary>
  TDpccTeamIssue = record
    Kind: TDpccTeamIssueKind;
    /// <summary>Betroffene Einstellung, z. B. "naming.field" oder "startProfiles[Demo].host"; '' für die Datei.
    /// </summary>
    Path: string;
    /// <summary>Bei Syntax: Zeile und Spalte (ab 1) der ersten fehlerhaften Stelle; 0, wenn unbekannt.</summary>
    Line: Integer;
    Column: Integer;
    class function Create(AKind: TDpccTeamIssueKind; const APath: string): TDpccTeamIssue; static;
  end;

  /// <summary>Format-artige Funktion mit dem Index ihres Formatparameters (ab 0, #451).</summary>
  TDpccFormatFunction = record
    Name: string;
    FormatIndex: Integer;
    class function Create(const AName: string; AFormatIndex: Integer): TDpccFormatFunction; static;
  end;

  TDpccTeamVariable = record
    Name: string;
    Value: string;
  end;

  /// <summary>Gemeinsames Startprofil (#575, Schnellaktion „Startprofil“ #764).</summary>
  TDpccStartProfile = record
    Name: string;
    Parameters: string;
    /// <summary>Arbeitsordner relativ zur Projektdatei; '' = Vorgabe der IDE.</summary>
    WorkingDir: string;
    /// <summary>Host-Anwendung relativ zur Projektdatei oder mit Makro ($(BDS)…); '' = keine.</summary>
    Host: string;
    Environment: TArray<TDpccTeamVariable>;
  end;

  /// <summary>Build-Server des Projekts (#763); Benutzer und Token im Anmeldespeicher von Windows.</summary>
  TDpccTeamCi = record
    /// <summary>"jenkins".</summary>
    Provider: string;
    Url: string;
    Job: string;
    /// <summary>Multibranch-Job: es gilt der Job des aktuellen Branches.</summary>
    Multibranch: Boolean;
    function Configured: Boolean;
  end;

  /// <summary>Issue-Tracker des Projekts (#765); das Token im Anmeldespeicher von Windows.</summary>
  TDpccTeamTracker = record
    /// <summary>"github" oder "youtrack".</summary>
    Provider: string;
    Url: string;
    /// <summary>Projektkürzel (YouTrack "ATL") bzw. "owner/repo" (GitHub).</summary>
    Project: string;
    function Configured: Boolean;
  end;

  /// <summary>Versionsverwaltung des Projekts (#1286): Art und Hauptbranch für alle im Team; Vorrang vor der
  /// persönlichen Zeile in vcs.projects.</summary>
  TDpccTeamVcs = record
    /// <summary>"auto", "git", "svn" oder "off"; '' = nicht gesetzt.</summary>
    Provider: string;
    /// <summary>Hauptbranch, z. B. "develop" bzw. SVN "trunk"; '' = nicht gesetzt.</summary>
    MainBranch: string;
    function Configured: Boolean;
  end;

  /// <summary>Wertdarstellung beim Debuggen für einen Typ (#854, debug.displayRules.project), etwa für fremde
  /// Klassen wie TFDConnection.</summary>
  TDpccTeamDisplayRule = record
    /// <summary>Typname mit oder ohne Unit.</summary>
    TypeName: string;
    /// <summary>Vorlage wie in // dpcc-debug: ('' = nur children).</summary>
    Template: string;
    Children: TArray<string>;
  end;

  /// <summary>Eine Zeile der Anzeige „aus .dpcc“.</summary>
  TDpccTeamValue = record
    Key: string;
    Value: string;
  end;

  /// <summary>Inhalt der Projektdatei nach dem Lesen; nur erlaubte Werte.</summary>
  TDpccTeamSettings = record
    /// <summary>.dproj, für die der Stand gilt; '' ohne Projekt (setzt die IDE-Schicht).</summary>
    Project: string;
    /// <summary>Vollständiger Pfad der Datei; '' ohne Projektdatei.</summary>
    FileName: string;
    /// <summary>Ordner der Datei; Basis relativer Pfade.</summary>
    Folder: string;
    /// <summary>Wurzel, die kein Pfad verlassen darf (Repository, sonst Folder).</summary>
    Root: string;
    /// <summary>Datei ist JSON mit einem Objekt; sonst gelten nur die persönlichen Einstellungen.</summary>
    Valid: Boolean;
    Version: Integer;
    Naming: array[TDpccNamingKind] of string;
    HasNaming: array[TDpccNamingKind] of Boolean;
    FormatFunctions: TArray<TDpccFormatFunction>;
    SqlTargets: TArray<string>;
    FileMethods: TArray<string>;
    MainThreadExceptions: TArray<string>;
    StartProfiles: TArray<TDpccStartProfile>;
    Ci: TDpccTeamCi;
    Tracker: TDpccTeamTracker;
    Vcs: TDpccTeamVcs;
    /// <summary>An einer Stelle oder in einer Datei ausgeblendete Elemente (#628).</summary>
    Hidden: TArray<TDpccHiddenPlace>;
    /// <summary>Wertdarstellungen beim Debuggen (#854).</summary>
    DisplayRules: TArray<TDpccTeamDisplayRule>;
    Issues: TArray<TDpccTeamIssue>;
    /// <summary>Es gibt eine Projektdatei (gültig oder nicht).</summary>
    function Exists: Boolean;
    /// <summary>Die Datei setzt mindestens einen Wert.</summary>
    function HasValues: Boolean;
    function IndexOfProfile(const AName: string): Integer;
  end;

  /// <summary>Gibt es die Datei bzw. den Ordner (.git darf beides sein)?</summary>
  TDpccTeamFileExists = reference to function(const APath: string): Boolean;

  TDpccTeamFile = class
  public const
    cFileName = '.dpcc';
    cDisplayRulesKey = 'debugDisplayRules';
    cCurrentVersion = 1;
  public
    /// <summary>Projektdatei zum Ordner einer .dproj ohne Projektgruppe (siehe Kopf); '' ohne.</summary>
    class function Locate(const AProjectFolder: string; const AExists: TDpccTeamFileExists): string; overload;
      static;
    /// <summary>Projektdatei zum Ordner einer .dproj und dem Ordner der geöffneten .groupproj ('' ohne Gruppe):
    /// nächster Ordner mit .dpcc aufwärts bis zur Wurzel, dann der Ordner der Gruppe (siehe Kopf); '' ohne.
    /// </summary>
    class function Locate(const AProjectFolder, AGroupFolder: string; const AExists: TDpccTeamFileExists): string;
      overload; static;
    /// <summary>Nächster Ordner mit .git oder .svn ab AFolder aufwärts, sonst AFolder.</summary>
    class function RootOf(const AFolder: string; const AExists: TDpccTeamFileExists): string; static;
    /// <summary>Liest den Text der Datei AFileName; ARoot begrenzt die Pfade ('' = Ordner der Datei).</summary>
    class function Parse(const AText, AFileName, ARoot: string): TDpccTeamSettings; static;
    /// <summary>Ohne Projektdatei.</summary>
    class function Empty: TDpccTeamSettings; static;
    /// <summary>Inhalt einer neuen Projektdatei mit Version und Beispielen als Kommentar.</summary>
    class function Skeleton: string; static;
    /// <summary>Präfix aus der Projektdatei, sonst APersonal.</summary>
    class function Prefix(const ATeam: TDpccTeamSettings; AKind: TDpccNamingKind;
      const APersonal: string): string; static;
    /// <summary>Einträge von ATeam, dann die von APersonal, die dort fehlen (ohne Groß-/Kleinschreibung).</summary>
    class function MergeNames(const ATeam, APersonal: TArray<string>): TArray<string>; static;
    /// <summary>Wie MergeNames; bei gleichem Namen gilt der Index aus ATeam.</summary>
    class function MergeFormatFunctions(const ATeam,
      APersonal: TArray<TDpccFormatFunction>): TArray<TDpccFormatFunction>; static;
    /// <summary>Wie MergeNames; bei gleichem Namen gilt das Profil aus ATeam.</summary>
    class function MergeStartProfiles(const ATeam,
      APersonal: TArray<TDpccStartProfile>): TArray<TDpccStartProfile>; static;
    /// <summary>Gesetzte Werte zur Anzeige „aus .dpcc“, in der Reihenfolge des Formats.</summary>
    class function Values(const ATeam: TDpccTeamSettings): TArray<TDpccTeamValue>; static;
    /// <summary>ARelative an AFolder gehängt, „.“ und „..“ aufgelöst, Trenner „\“.</summary>
    class function Combine(const AFolder, ARelative: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  System.StrUtils,
  dpcc.Text.Jsonc,
  dpcc.Text.Checkin,
  dpcc.Text.DebugDisplay,
  dpcc.Core.Localization.Language;

const
  cNamingKeys: array[TDpccNamingKind] of string = ('field', 'parameter', 'local', 'constant');

function IsSeparator(ACh: Char): Boolean;
begin
  Result := (ACh = '\') or (ACh = '/');
end;

function WithoutTrailing(const APath: string): string;
begin
  Result := APath;
  while (Length(Result) > 1) and IsSeparator(Result[Length(Result)]) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

function JoinPath(const AFolder, AName: string): string;
begin
  Result := WithoutTrailing(AFolder) + '\' + AName;
end;

/// <summary>Übergeordneter Ordner; '' oberhalb von Laufwerk oder Server.</summary>
function ParentOf(const AFolder: string): string;
var
  mPath: string;
  mIndex: Integer;
begin
  Result := '';
  mPath := WithoutTrailing(AFolder);
  for mIndex := Length(mPath) downto 1 do
  begin
    if IsSeparator(mPath[mIndex]) then
    begin
      Result := Copy(mPath, 1, mIndex - 1);
      Break;
    end;
  end;
  if (Result <> '') and IsSeparator(Result[Length(Result)]) then
  begin
    Result := '';
  end;
end;

/// <summary>Nächster Ordner mit .git (Ordner oder Datei bei Worktrees) oder .svn ab AFolder aufwärts; '' ohne.
/// </summary>
function RepositoryRoot(const AFolder: string; const AExists: TDpccTeamFileExists): string;
var
  mFolder: string;
begin
  mFolder := WithoutTrailing(AFolder);
  while mFolder <> '' do
  begin
    if AExists(JoinPath(mFolder, '.git')) or AExists(JoinPath(mFolder, '.svn')) then
    begin
      Exit(mFolder);
    end;
    mFolder := ParentOf(mFolder);
  end;
  Result := '';
end;

/// <summary>Ist AFolder derselbe Ordner wie AChild oder liegt AChild darunter?</summary>
function FolderContains(const AFolder, AChild: string): Boolean;
var
  mFolder, mChild: string;
begin
  mFolder := WithoutTrailing(AFolder);
  mChild := WithoutTrailing(AChild);
  Result := (mFolder <> '') and (SameText(mFolder, mChild) or
    SameText(mFolder + '\', Copy(mChild, 1, Length(mFolder) + 1)));
end;

function FolderOf(const AFileName: string): string;
var
  mIndex: Integer;
begin
  for mIndex := Length(AFileName) downto 1 do
  begin
    if IsSeparator(AFileName[mIndex]) then
    begin
      Exit(Copy(AFileName, 1, mIndex - 1));
    end;
  end;
  Result := '';
end;

function IsPrefixText(const AText: string): Boolean;
var
  mCh: Char;
begin
  for mCh in AText do
  begin
    if not CharInSet(mCh, ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function IsHttpUrl(const AText: string): Boolean;
var
  mLower: string;
begin
  mLower := LowerCase(AText);
  Result := (Copy(mLower, 1, 7) = 'http://') or (Copy(mLower, 1, 8) = 'https://');
end;

{ TDpccTeamIssue }

class function TDpccTeamIssue.Create(AKind: TDpccTeamIssueKind; const APath: string): TDpccTeamIssue;
begin
  Result.Kind := AKind;
  Result.Path := APath;
  Result.Line := 0;
  Result.Column := 0;
end;

{ TDpccFormatFunction }

class function TDpccFormatFunction.Create(const AName: string; AFormatIndex: Integer): TDpccFormatFunction;
begin
  Result.Name := AName;
  Result.FormatIndex := AFormatIndex;
end;

{ TDpccTeamCi }

function TDpccTeamCi.Configured: Boolean;
begin
  Result := (Provider <> '') and (Url <> '') and (Job <> '');
end;

{ TDpccTeamTracker }

function TDpccTeamTracker.Configured: Boolean;
begin
  Result := (Provider <> '') and (Url <> '');
end;

{ TDpccTeamVcs }

function TDpccTeamVcs.Configured: Boolean;
begin
  Result := (Provider <> '') or (MainBranch <> '');
end;

{ TDpccTeamSettings }

function TDpccTeamSettings.Exists: Boolean;
begin
  Result := FileName <> '';
end;

function TDpccTeamSettings.HasValues: Boolean;
begin
  Result := Length(TDpccTeamFile.Values(Self)) > 0;
end;

function TDpccTeamSettings.IndexOfProfile(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(StartProfiles) do
  begin
    if SameText(StartProfiles[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

type
  /// <summary>Liest das Wurzelobjekt der Projektdatei in TDpccTeamSettings.</summary>
  TTeamReader = class
  private
    FTeam: TDpccTeamSettings;
    procedure Report(AKind: TDpccTeamIssueKind; const APath: string);
    /// <summary>Meldet AKey als Zugangsdaten, wenn er danach aussieht.</summary>
    function IsCredential(const AKey, APath: string): Boolean;
    /// <summary>Meldet Zugangsdaten in einem unbekannten Wert (Schlüssel, Adressen).</summary>
    procedure ScanCredentials(AValue: TJSONValue; const APath: string);
    function ReadString(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
    function ReadUrl(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
    /// <summary>Relativer Pfad, der in der Wurzel bleibt.</summary>
    function ReadPath(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
    function ReadNames(AValue: TJSONValue; const APath: string): TArray<string>;
    procedure ReadNamingKey(const AKey, APath: string; AValue: TJSONValue);
    procedure ReadNaming(AValue: TJSONValue);
    function ReadFormatIndex(AValue: TJSONValue; const APath: string; var AIndex: Integer): Boolean;
    function ReadFormatFunction(AEntry: TJSONObject; const APath: string;
      out AFunction: TDpccFormatFunction): Boolean;
    function ReadParameters(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
    function ReadProfileKey(const AKey, APath: string; AValue: TJSONValue; var AProfile: TDpccStartProfile): Boolean;
    function ReadHiddenPlace(AItem: TJSONObject; const APath: string; out APlace: TDpccHiddenPlace): Boolean;
    function ReadChildren(AField: TJSONValue; const APath: string): TArray<string>;
    function ReadDisplayFields(AValue: TJSONObject; const APath: string; var ARule: TDpccTeamDisplayRule): Boolean;
    function ReadDisplayRule(AValue: TJSONValue; const APath: string; var ARule: TDpccTeamDisplayRule;
      out AReported: Boolean): Boolean;
    function ReadProvider(AValue: TJSONValue; const APath: string; const AAllowed: array of string;
      out AProvider: string): Boolean;
    function ReadBool(AValue: TJSONValue; const APath: string; var AFlag: Boolean): Boolean;
    function ReadCiKey(const AKey, APath: string; AValue: TJSONValue; var ACi: TDpccTeamCi): Boolean;
    function ReadTrackerKey(const AKey, APath: string; AValue: TJSONValue; var ATracker: TDpccTeamTracker): Boolean;
    procedure ReadVcsKey(const AKey, APath: string; AValue: TJSONValue; var AVcs: TDpccTeamVcs);
    function ReadListKey(const AKey: string; AValue: TJSONValue): Boolean;
    procedure ReadKey(const AKey: string; AValue: TJSONValue);
    procedure ReadFormatFunctions(AValue: TJSONValue);
    function ReadEnvironment(AValue: TJSONValue; const APath: string;
      out AVariables: TArray<TDpccTeamVariable>): Boolean;
    function ReadStartProfile(AValue: TJSONValue; const APath: string; out AProfile: TDpccStartProfile): Boolean;
    procedure ReadStartProfiles(AValue: TJSONValue);
    procedure ReadCi(AValue: TJSONValue);
    procedure ReadTracker(AValue: TJSONValue);
    procedure ReadVcs(AValue: TJSONValue);
    procedure ReadHidden(AValue: TJSONValue);
    procedure ReadDisplayRules(AValue: TJSONValue);
    procedure ReadVersion(AValue: TJSONValue);
  public
    constructor Create(const AFileName, ARoot: string);
    procedure Read(ARoot: TJSONObject);
    /// <summary>Datei ungültig; ALine/AColumn = erste fehlerhafte Stelle (0 = unbekannt).</summary>
    procedure Invalid(ALine, AColumn: Integer);
    property Team: TDpccTeamSettings read FTeam;
  end;

constructor TTeamReader.Create(const AFileName, ARoot: string);
begin
  inherited Create;
  FTeam := TDpccTeamFile.Empty;
  FTeam.FileName := AFileName;
  FTeam.Folder := FolderOf(AFileName);
  FTeam.Root := ARoot;
  if FTeam.Root = '' then
  begin
    FTeam.Root := FTeam.Folder;
  end;
end;

procedure TTeamReader.Report(AKind: TDpccTeamIssueKind; const APath: string);
begin
  FTeam.Issues := FTeam.Issues + [TDpccTeamIssue.Create(AKind, APath)];
end;

procedure TTeamReader.Invalid(ALine, AColumn: Integer);
var
  mIssue: TDpccTeamIssue;
begin
  FTeam.Valid := False;
  mIssue := TDpccTeamIssue.Create(TDpccTeamIssueKind.Syntax, '');
  mIssue.Line := ALine;
  mIssue.Column := AColumn;
  FTeam.Issues := FTeam.Issues + [mIssue];
end;

function TTeamReader.IsCredential(const AKey, APath: string): Boolean;
begin
  Result := TTextCheckin.IsCredentialKey(AKey);
  if Result then
  begin
    Report(TDpccTeamIssueKind.Credential, APath);
  end;
end;

procedure TTeamReader.ScanCredentials(AValue: TJSONValue; const APath: string);
var
  mIndex: Integer;
  mKey: string;
begin
  if AValue is TJSONObject then
  begin
    for mIndex := 0 to TJSONObject(AValue).Count - 1 do
    begin
      mKey := TJSONObject(AValue).Pairs[mIndex].JsonString.Value;
      if not IsCredential(mKey, APath + '.' + mKey) then
      begin
        ScanCredentials(TJSONObject(AValue).Pairs[mIndex].JsonValue, APath + '.' + mKey);
      end;
    end;
  end
  else if AValue is TJSONArray then
  begin
    for mIndex := 0 to TJSONArray(AValue).Count - 1 do
    begin
      ScanCredentials(TJSONArray(AValue).Items[mIndex], APath);
    end;
  end
  else if (AValue is TJSONString) and TTextCheckin.HasUrlCredentials(TJSONString(AValue).Value) then
  begin
    Report(TDpccTeamIssueKind.Credential, APath);
  end;
end;

function TTeamReader.ReadString(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
begin
  AText := '';
  // TJSONNumber erbt von TJSONString: Zahlen sind hier falsche Typen.
  Result := (AValue is TJSONString) and not (AValue is TJSONNumber);
  if not Result then
  begin
    Report(TDpccTeamIssueKind.WrongType, APath);
    Exit;
  end;
  AText := Trim(TJSONString(AValue).Value);
  if TTextCheckin.HasUrlCredentials(AText) then
  begin
    Report(TDpccTeamIssueKind.Credential, APath);
    AText := '';
    Result := False;
  end;
end;

function TTeamReader.ReadUrl(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
begin
  Result := ReadString(AValue, APath, AText);
  if Result and (AText <> '') and not IsHttpUrl(AText) then
  begin
    Report(TDpccTeamIssueKind.InvalidValue, APath);
    AText := '';
    Result := False;
  end;
end;

function TTeamReader.ReadPath(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
begin
  Result := ReadString(AValue, APath, AText);
  if not Result or (AText = '') then
  begin
    Exit;
  end;
  if TTextCheckin.IsAbsolutePath(AText) then
  begin
    Report(TDpccTeamIssueKind.AbsolutePath, APath);
  end
  else if not TTextCheckin.StaysInside(FTeam.Root, FTeam.Folder, AText) then
  begin
    Report(TDpccTeamIssueKind.OutsidePath, APath);
  end
  else
  begin
    Exit(True);
  end;
  AText := '';
  Result := False;
end;

function TTeamReader.ReadNames(AValue: TJSONValue; const APath: string): TArray<string>;
var
  mIndex: Integer;
  mItem, mText: string;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Report(TDpccTeamIssueKind.WrongType, APath);
    Exit;
  end;
  for mIndex := 0 to TJSONArray(AValue).Count - 1 do
  begin
    mItem := Format('%s[%d]', [APath, mIndex]);
    if not ReadString(TJSONArray(AValue).Items[mIndex], mItem, mText) then
    begin
      Continue;
    end;
    if mText = '' then
    begin
      Report(TDpccTeamIssueKind.InvalidValue, mItem);
    end
    else
    begin
      Result := Result + [mText];
    end;
  end;
end;

procedure TTeamReader.ReadNamingKey(const AKey, APath: string; AValue: TJSONValue);
var
  mKind: TDpccNamingKind;
  mText: string;
begin
  for mKind := Low(TDpccNamingKind) to High(TDpccNamingKind) do
  begin
    if AKey <> cNamingKeys[mKind] then
    begin
      Continue;
    end;
    if not ReadString(AValue, APath, mText) then
    begin
      Exit;
    end;
    if not IsPrefixText(mText) then
    begin
      Report(TDpccTeamIssueKind.InvalidValue, APath);
      Exit;
    end;
    FTeam.Naming[mKind] := mText;
    FTeam.HasNaming[mKind] := True;
    Exit;
  end;
  Report(TDpccTeamIssueKind.UnknownKey, APath);
end;

procedure TTeamReader.ReadNaming(AValue: TJSONValue);
var
  mIndex: Integer;
  mKey, mPath: string;
begin
  if not (AValue is TJSONObject) then
  begin
    Report(TDpccTeamIssueKind.WrongType, 'naming');
    Exit;
  end;
  for mIndex := 0 to TJSONObject(AValue).Count - 1 do
  begin
    mKey := TJSONObject(AValue).Pairs[mIndex].JsonString.Value;
    mPath := 'naming.' + mKey;
    if not IsCredential(mKey, mPath) then
    begin
      ReadNamingKey(mKey, mPath, TJSONObject(AValue).Pairs[mIndex].JsonValue);
    end;
  end;
end;

function TTeamReader.ReadFormatIndex(AValue: TJSONValue; const APath: string; var AIndex: Integer): Boolean;
begin
  Result := AValue is TJSONNumber;
  if Result then
  begin
    AIndex := TJSONNumber(AValue).AsInt;
  end
  else
  begin
    Report(TDpccTeamIssueKind.WrongType, APath);
  end;
end;

function TTeamReader.ReadFormatFunction(AEntry: TJSONObject; const APath: string;
  out AFunction: TDpccFormatFunction): Boolean;
var
  mPair, mFormatIndex: Integer;
  mKey, mName: string;
  mValue: TJSONValue;
begin
  mName := '';
  mFormatIndex := -1;
  Result := True;
  for mPair := 0 to AEntry.Count - 1 do
  begin
    mKey := AEntry.Pairs[mPair].JsonString.Value;
    mValue := AEntry.Pairs[mPair].JsonValue;
    if IsCredential(mKey, APath + '.' + mKey) then
    begin
      Continue;
    end;
    if mKey = 'name' then
    begin
      Result := ReadString(mValue, APath + '.name', mName) and Result;
    end
    else if mKey = 'formatIndex' then
    begin
      Result := ReadFormatIndex(mValue, APath + '.formatIndex', mFormatIndex) and Result;
    end
    else
    begin
      Report(TDpccTeamIssueKind.UnknownKey, APath + '.' + mKey);
    end;
  end;
  if Result and ((mName = '') or (mFormatIndex < 0)) then
  begin
    Report(TDpccTeamIssueKind.InvalidValue, APath);
    Result := False;
  end;
  AFunction := TDpccFormatFunction.Create(mName, mFormatIndex);
end;

procedure TTeamReader.ReadFormatFunctions(AValue: TJSONValue);
var
  mIndex: Integer;
  mItem: string;
  mFunction: TDpccFormatFunction;
begin
  if not (AValue is TJSONArray) then
  begin
    Report(TDpccTeamIssueKind.WrongType, 'formatFunctions');
    Exit;
  end;
  for mIndex := 0 to TJSONArray(AValue).Count - 1 do
  begin
    mItem := Format('formatFunctions[%d]', [mIndex]);
    if not (TJSONArray(AValue).Items[mIndex] is TJSONObject) then
    begin
      Report(TDpccTeamIssueKind.WrongType, mItem);
    end
    else if ReadFormatFunction(TJSONObject(TJSONArray(AValue).Items[mIndex]), mItem, mFunction) then
    begin
      FTeam.FormatFunctions := TDpccTeamFile.MergeFormatFunctions(FTeam.FormatFunctions, [mFunction]);
    end;
  end;
end;

function TTeamReader.ReadEnvironment(AValue: TJSONValue; const APath: string;
  out AVariables: TArray<TDpccTeamVariable>): Boolean;
var
  mIndex: Integer;
  mVariable: TDpccTeamVariable;
  mPath: string;
begin
  AVariables := nil;
  if not (AValue is TJSONObject) then
  begin
    Report(TDpccTeamIssueKind.WrongType, APath);
    Exit(False);
  end;
  Result := True;
  for mIndex := 0 to TJSONObject(AValue).Count - 1 do
  begin
    mVariable.Name := TJSONObject(AValue).Pairs[mIndex].JsonString.Value;
    mPath := APath + '.' + mVariable.Name;
    if TTextCheckin.IsCredentialName(mVariable.Name) then
    begin
      Report(TDpccTeamIssueKind.Credential, mPath);
      Result := False;
      Continue;
    end;
    if not ReadString(TJSONObject(AValue).Pairs[mIndex].JsonValue, mPath, mVariable.Value) then
    begin
      Result := False;
      Continue;
    end;
    if TTextCheckin.ContainsMachinePath(mVariable.Value) then
    begin
      Report(TDpccTeamIssueKind.AbsolutePath, mPath);
      Result := False;
      Continue;
    end;
    AVariables := AVariables + [mVariable];
  end;
end;

function TTeamReader.ReadParameters(AValue: TJSONValue; const APath: string; out AText: string): Boolean;
begin
  Result := ReadString(AValue, APath, AText);
  if Result and TTextCheckin.ContainsMachinePath(AText) then
  begin
    Report(TDpccTeamIssueKind.AbsolutePath, APath);
    Result := False;
  end;
end;

function TTeamReader.ReadProfileKey(const AKey, APath: string; AValue: TJSONValue;
  var AProfile: TDpccStartProfile): Boolean;
begin
  Result := True;
  if IsCredential(AKey, APath) then
  begin
    Result := False;
  end
  else if AKey = 'name' then
  begin
    Result := ReadString(AValue, APath, AProfile.Name);
  end
  else if AKey = 'parameters' then
  begin
    Result := ReadParameters(AValue, APath, AProfile.Parameters);
  end
  else if AKey = 'workingDir' then
  begin
    Result := ReadPath(AValue, APath, AProfile.WorkingDir);
  end
  else if AKey = 'host' then
  begin
    Result := ReadPath(AValue, APath, AProfile.Host);
  end
  else if AKey = 'environment' then
  begin
    Result := ReadEnvironment(AValue, APath, AProfile.Environment);
  end
  else
  begin
    Report(TDpccTeamIssueKind.UnknownKey, APath);
    ScanCredentials(AValue, APath);
  end;
end;

/// <summary>Ort eines Startprofils in Meldungen: mit Namen, sonst mit Index.</summary>
function ProfilePath(AEntry: TJSONObject; const APath: string): string;
var
  mValue: TJSONValue;
begin
  Result := APath;
  mValue := AEntry.GetValue('name');
  if (mValue is TJSONString) and (Trim(TJSONString(mValue).Value) <> '') then
  begin
    Result := Format('startProfiles[%s]', [Trim(TJSONString(mValue).Value)]);
  end;
end;

function TTeamReader.ReadStartProfile(AValue: TJSONValue; const APath: string;
  out AProfile: TDpccStartProfile): Boolean;
var
  mIndex: Integer;
  mEntry: TJSONObject;
  mKey, mPath: string;
begin
  AProfile := Default(TDpccStartProfile);
  if not (AValue is TJSONObject) then
  begin
    Report(TDpccTeamIssueKind.WrongType, APath);
    Exit(False);
  end;
  mEntry := TJSONObject(AValue);
  mPath := ProfilePath(mEntry, APath);
  Result := True;
  for mIndex := 0 to mEntry.Count - 1 do
  begin
    mKey := mEntry.Pairs[mIndex].JsonString.Value;
    Result := ReadProfileKey(mKey, mPath + '.' + mKey, mEntry.Pairs[mIndex].JsonValue, AProfile) and Result;
  end;
  if Result and (AProfile.Name = '') then
  begin
    Report(TDpccTeamIssueKind.InvalidValue, mPath + '.name');
    Result := False;
  end;
end;

procedure TTeamReader.ReadStartProfiles(AValue: TJSONValue);
var
  mIndex: Integer;
  mProfile: TDpccStartProfile;
begin
  if not (AValue is TJSONArray) then
  begin
    Report(TDpccTeamIssueKind.WrongType, 'startProfiles');
    Exit;
  end;
  for mIndex := 0 to TJSONArray(AValue).Count - 1 do
  begin
    if not ReadStartProfile(TJSONArray(AValue).Items[mIndex], Format('startProfiles[%d]', [mIndex]), mProfile) then
    begin
      Continue;
    end;
    if FTeam.IndexOfProfile(mProfile.Name) >= 0 then
    begin
      Report(TDpccTeamIssueKind.InvalidValue, Format('startProfiles[%s]', [mProfile.Name]));
    end
    else
    begin
      FTeam.StartProfiles := FTeam.StartProfiles + [mProfile];
    end;
  end;
end;

function TTeamReader.ReadHiddenPlace(AItem: TJSONObject; const APath: string; out APlace: TDpccHiddenPlace): Boolean;
var
  mMember: Integer;
  mKey, mSetting, mFileName, mAnchor: string;
  mValue: TJSONValue;
begin
  mSetting := '';
  mFileName := '';
  mAnchor := '';
  Result := True;
  for mMember := 0 to AItem.Count - 1 do
  begin
    mKey := AItem.Pairs[mMember].JsonString.Value;
    mValue := AItem.Pairs[mMember].JsonValue;
    if mKey = 'setting' then
    begin
      Result := ReadString(mValue, APath + '.setting', mSetting) and Result;
    end
    else if mKey = 'file' then
    begin
      Result := ReadPath(mValue, APath + '.file', mFileName) and Result;
    end
    else if mKey = 'anchor' then
    begin
      Result := ReadString(mValue, APath + '.anchor', mAnchor) and Result;
    end
    else
    begin
      Report(TDpccTeamIssueKind.UnknownKey, APath + '.' + mKey);
    end;
  end;
  if Result and ((mSetting = '') or (mFileName = '')) then
  begin
    Report(TDpccTeamIssueKind.InvalidValue, APath);
    Result := False;
  end;
  APlace := TDpccHiddenPlace.Create(mSetting, mFileName, mAnchor);
end;

procedure TTeamReader.ReadHidden(AValue: TJSONValue);
var
  mIndex: Integer;
  mItem: TJSONValue;
  mPath: string;
  mPlace: TDpccHiddenPlace;
begin
  if not (AValue is TJSONArray) then
  begin
    Report(TDpccTeamIssueKind.WrongType, TDpccHiddenPlaces.cKey);
    Exit;
  end;
  for mIndex := 0 to TJSONArray(AValue).Count - 1 do
  begin
    mItem := TJSONArray(AValue).Items[mIndex];
    mPath := Format('%s[%d]', [TDpccHiddenPlaces.cKey, mIndex]);
    if not (mItem is TJSONObject) then
    begin
      Report(TDpccTeamIssueKind.WrongType, mPath);
    end
    else if ReadHiddenPlace(TJSONObject(mItem), mPath, mPlace) then
    begin
      FTeam.Hidden := FTeam.Hidden + [mPlace];
    end;
  end;
end;

function TTeamReader.ReadChildren(AField: TJSONValue; const APath: string): TArray<string>;
begin
  // Liste oder kommagetrennt wie in // dpcc-debug-children:
  if (AField is TJSONString) and not (AField is TJSONNumber) then
  begin
    Result := TDebugDisplayText.SplitNames(AField.Value);
  end
  else
  begin
    Result := TDebugDisplayText.SplitNames(string.Join(',', ReadNames(AField, APath)));
  end;
end;

function TTeamReader.ReadDisplayFields(AValue: TJSONObject; const APath: string;
  var ARule: TDpccTeamDisplayRule): Boolean;
var
  mMember: Integer;
  mKey: string;
  mField: TJSONValue;
begin
  Result := True;
  for mMember := 0 to AValue.Count - 1 do
  begin
    mKey := AValue.Pairs[mMember].JsonString.Value;
    mField := AValue.Pairs[mMember].JsonValue;
    if mKey = 'template' then
    begin
      Result := ReadString(mField, APath + '.template', ARule.Template) and Result;
    end
    else if mKey = 'children' then
    begin
      ARule.Children := ReadChildren(mField, APath + '.children');
    end
    else
    begin
      Report(TDpccTeamIssueKind.UnknownKey, APath + '.' + mKey);
    end;
  end;
end;

/// <summary>Vorlage oder Kinder, und eine Vorlage muss sich lesen lassen.</summary>
function DisplayRuleValid(const ARule: TDpccTeamDisplayRule): Boolean;
begin
  if ARule.Template = '' then
  begin
    Result := ARule.Children <> nil;
  end
  else
  begin
    Result := TDebugDisplayTemplate.Parse(ARule.Template).Valid;
  end;
end;

/// <summary>Eine Regel aus AValue (Objekt oder nur die Vorlage); False ohne Meldung, wenn der Wert schon falsch
/// gemeldet ist (AReported).</summary>
function TTeamReader.ReadDisplayRule(AValue: TJSONValue; const APath: string; var ARule: TDpccTeamDisplayRule;
  out AReported: Boolean): Boolean;
begin
  AReported := False;
  if AValue is TJSONObject then
  begin
    Result := ReadDisplayFields(TJSONObject(AValue), APath, ARule) and (ARule.TypeName <> '');
  end
  else
  begin
    AReported := not ReadString(AValue, APath, ARule.Template);
    Result := not AReported and (ARule.TypeName <> '');
  end;
  Result := Result and DisplayRuleValid(ARule);
end;

procedure TTeamReader.ReadDisplayRules(AValue: TJSONValue);
var
  mIndex: Integer;
  mPath: string;
  mRule: TDpccTeamDisplayRule;
  mReported: Boolean;
begin
  if not (AValue is TJSONObject) then
  begin
    Report(TDpccTeamIssueKind.WrongType, TDpccTeamFile.cDisplayRulesKey);
    Exit;
  end;
  for mIndex := 0 to TJSONObject(AValue).Count - 1 do
  begin
    mRule := Default(TDpccTeamDisplayRule);
    mRule.TypeName := Trim(TJSONObject(AValue).Pairs[mIndex].JsonString.Value);
    mPath := TDpccTeamFile.cDisplayRulesKey + '.' + mRule.TypeName;
    if ReadDisplayRule(TJSONObject(AValue).Pairs[mIndex].JsonValue, mPath, mRule, mReported) then
    begin
      FTeam.DisplayRules := FTeam.DisplayRules + [mRule];
    end
    else if not mReported then
    begin
      Report(TDpccTeamIssueKind.InvalidValue, mPath);
    end;
  end;
end;

/// <summary>Anbieter in Kleinbuchstaben; False (gemeldet), wenn er nicht in AAllowed steht.</summary>
function TTeamReader.ReadProvider(AValue: TJSONValue; const APath: string; const AAllowed: array of string;
  out AProvider: string): Boolean;
begin
  Result := ReadString(AValue, APath, AProvider);
  if not Result then
  begin
    Exit;
  end;
  AProvider := LowerCase(AProvider);
  Result := MatchStr(AProvider, AAllowed);
  if not Result then
  begin
    Report(TDpccTeamIssueKind.InvalidValue, APath);
  end;
end;

function TTeamReader.ReadBool(AValue: TJSONValue; const APath: string; var AFlag: Boolean): Boolean;
begin
  Result := AValue is TJSONBool;
  if Result then
  begin
    AFlag := TJSONBool(AValue).AsBoolean;
  end
  else
  begin
    Report(TDpccTeamIssueKind.WrongType, APath);
  end;
end;

function TTeamReader.ReadCiKey(const AKey, APath: string; AValue: TJSONValue; var ACi: TDpccTeamCi): Boolean;
begin
  Result := True;
  if AKey = 'provider' then
  begin
    Result := ReadProvider(AValue, APath, ['jenkins'], ACi.Provider);
  end
  else if AKey = 'url' then
  begin
    ReadUrl(AValue, APath, ACi.Url);
  end
  else if AKey = 'job' then
  begin
    ReadString(AValue, APath, ACi.Job);
  end
  else if AKey = 'multibranch' then
  begin
    ReadBool(AValue, APath, ACi.Multibranch);
  end
  else
  begin
    Report(TDpccTeamIssueKind.UnknownKey, APath);
    ScanCredentials(AValue, APath);
  end;
end;

procedure TTeamReader.ReadCi(AValue: TJSONValue);
var
  mIndex: Integer;
  mKey, mPath: string;
  mCi: TDpccTeamCi;
begin
  if not (AValue is TJSONObject) then
  begin
    Report(TDpccTeamIssueKind.WrongType, 'ci');
    Exit;
  end;
  mCi := Default(TDpccTeamCi);
  mCi.Provider := 'jenkins';
  for mIndex := 0 to TJSONObject(AValue).Count - 1 do
  begin
    mKey := TJSONObject(AValue).Pairs[mIndex].JsonString.Value;
    mPath := 'ci.' + mKey;
    // Ein unbekannter Anbieter verwirft den ganzen Abschnitt.
    if not IsCredential(mKey, mPath) and not ReadCiKey(mKey, mPath, TJSONObject(AValue).Pairs[mIndex].JsonValue,
      mCi) then
    begin
      Exit;
    end;
  end;
  FTeam.Ci := mCi;
end;

function TTeamReader.ReadTrackerKey(const AKey, APath: string; AValue: TJSONValue;
  var ATracker: TDpccTeamTracker): Boolean;
begin
  Result := True;
  if AKey = 'provider' then
  begin
    Result := ReadProvider(AValue, APath, ['github', 'youtrack'], ATracker.Provider);
  end
  else if AKey = 'url' then
  begin
    ReadUrl(AValue, APath, ATracker.Url);
  end
  else if AKey = 'project' then
  begin
    ReadString(AValue, APath, ATracker.Project);
  end
  else
  begin
    Report(TDpccTeamIssueKind.UnknownKey, APath);
    ScanCredentials(AValue, APath);
  end;
end;

procedure TTeamReader.ReadTracker(AValue: TJSONValue);
var
  mIndex: Integer;
  mKey, mPath: string;
  mTracker: TDpccTeamTracker;
begin
  if not (AValue is TJSONObject) then
  begin
    Report(TDpccTeamIssueKind.WrongType, 'tracker');
    Exit;
  end;
  mTracker := Default(TDpccTeamTracker);
  for mIndex := 0 to TJSONObject(AValue).Count - 1 do
  begin
    mKey := TJSONObject(AValue).Pairs[mIndex].JsonString.Value;
    mPath := 'tracker.' + mKey;
    // Ein unbekannter Anbieter verwirft den ganzen Abschnitt.
    if not IsCredential(mKey, mPath) and not ReadTrackerKey(mKey, mPath,
      TJSONObject(AValue).Pairs[mIndex].JsonValue, mTracker) then
    begin
      Exit;
    end;
  end;
  if (mTracker.Provider = '') and (mTracker.Url <> '') then
  begin
    Report(TDpccTeamIssueKind.InvalidValue, 'tracker.provider');
    Exit;
  end;
  FTeam.Tracker := mTracker;
end;

/// <summary>Leerzeichen und Steuerzeichen gibt es in keinem Branch-Namen; ein solcher Wert gilt nicht.</summary>
function IsBranchText(const AText: string): Boolean;
begin
  Result := (Trim(AText) <> '') and (Trim(AText).IndexOfAny([' ', #9, #10, #13]) < 0);
end;

procedure TTeamReader.ReadVcsKey(const AKey, APath: string; AValue: TJSONValue; var AVcs: TDpccTeamVcs);
var
  mText: string;
begin
  if (AKey <> 'provider') and (AKey <> 'mainBranch') then
  begin
    Report(TDpccTeamIssueKind.UnknownKey, APath);
    ScanCredentials(AValue, APath);
    Exit;
  end;
  if not ReadString(AValue, APath, mText) then
  begin
    Exit;
  end;
  if AKey = 'mainBranch' then
  begin
    if IsBranchText(mText) then
    begin
      AVcs.MainBranch := Trim(mText);
    end
    else
    begin
      Report(TDpccTeamIssueKind.InvalidValue, APath);
    end;
  end
  else if MatchStr(LowerCase(Trim(mText)), ['auto', 'git', 'svn', 'off']) then
  begin
    AVcs.Provider := LowerCase(Trim(mText));
  end
  else
  begin
    Report(TDpccTeamIssueKind.InvalidValue, APath);
  end;
end;

procedure TTeamReader.ReadVcs(AValue: TJSONValue);
var
  mIndex: Integer;
  mKey, mPath: string;
  mVcs: TDpccTeamVcs;
begin
  if not (AValue is TJSONObject) then
  begin
    Report(TDpccTeamIssueKind.WrongType, 'vcs');
    Exit;
  end;
  mVcs := Default(TDpccTeamVcs);
  for mIndex := 0 to TJSONObject(AValue).Count - 1 do
  begin
    mKey := TJSONObject(AValue).Pairs[mIndex].JsonString.Value;
    mPath := 'vcs.' + mKey;
    if not IsCredential(mKey, mPath) then
    begin
      ReadVcsKey(mKey, mPath, TJSONObject(AValue).Pairs[mIndex].JsonValue, mVcs);
    end;
  end;
  FTeam.Vcs := mVcs;
end;

procedure TTeamReader.ReadVersion(AValue: TJSONValue);
var
  mVersion: Integer;
begin
  if not (AValue is TJSONNumber) then
  begin
    Report(TDpccTeamIssueKind.WrongType, 'version');
    Exit;
  end;
  mVersion := TJSONNumber(AValue).AsInt;
  if mVersion < 1 then
  begin
    Report(TDpccTeamIssueKind.InvalidValue, 'version');
    Exit;
  end;
  FTeam.Version := mVersion;
  if mVersion > TDpccTeamFile.cCurrentVersion then
  begin
    Report(TDpccTeamIssueKind.Version, 'version');
  end;
end;

function TTeamReader.ReadListKey(const AKey: string; AValue: TJSONValue): Boolean;
begin
  Result := True;
  if AKey = 'sqlTargets' then
  begin
    FTeam.SqlTargets := TDpccTeamFile.MergeNames(ReadNames(AValue, AKey), nil);
  end
  else if AKey = 'fileMethods' then
  begin
    FTeam.FileMethods := TDpccTeamFile.MergeNames(ReadNames(AValue, AKey), nil);
  end
  else if AKey = 'mainThreadExceptions' then
  begin
    FTeam.MainThreadExceptions := TDpccTeamFile.MergeNames(ReadNames(AValue, AKey), nil);
  end
  else
  begin
    Result := False;
  end;
end;

procedure TTeamReader.ReadKey(const AKey: string; AValue: TJSONValue);
begin
  if ReadListKey(AKey, AValue) then
  begin
    Exit;
  end;
  if AKey = 'version' then
  begin
    ReadVersion(AValue);
  end
  else if AKey = 'naming' then
  begin
    ReadNaming(AValue);
  end
  else if AKey = 'formatFunctions' then
  begin
    ReadFormatFunctions(AValue);
  end
  else if AKey = 'startProfiles' then
  begin
    ReadStartProfiles(AValue);
  end
  else if AKey = 'ci' then
  begin
    ReadCi(AValue);
  end
  else if AKey = 'tracker' then
  begin
    ReadTracker(AValue);
  end
  else if AKey = 'vcs' then
  begin
    ReadVcs(AValue);
  end
  else if AKey = TDpccHiddenPlaces.cKey then
  begin
    ReadHidden(AValue);
  end
  else if AKey = TDpccTeamFile.cDisplayRulesKey then
  begin
    ReadDisplayRules(AValue);
  end
  else
  begin
    Report(TDpccTeamIssueKind.UnknownKey, AKey);
    ScanCredentials(AValue, AKey);
  end;
end;

procedure TTeamReader.Read(ARoot: TJSONObject);
var
  mIndex: Integer;
  mKey: string;
  mHasVersion: Boolean;
begin
  FTeam.Valid := True;
  mHasVersion := False;
  for mIndex := 0 to ARoot.Count - 1 do
  begin
    mKey := ARoot.Pairs[mIndex].JsonString.Value;
    if not IsCredential(mKey, mKey) and (mKey <> '$schema') then
    begin
      mHasVersion := mHasVersion or (mKey = 'version');
      ReadKey(mKey, ARoot.Pairs[mIndex].JsonValue);
    end;
  end;
  if not mHasVersion then
  begin
    Report(TDpccTeamIssueKind.Version, 'version');
  end;
end;

{ TDpccTeamFile }

class function TDpccTeamFile.Empty: TDpccTeamSettings;
begin
  Result := Default(TDpccTeamSettings);
  Result.Version := cCurrentVersion;
end;

class function TDpccTeamFile.RootOf(const AFolder: string; const AExists: TDpccTeamFileExists): string;
begin
  Result := RepositoryRoot(AFolder, AExists);
  if Result = '' then
  begin
    Result := WithoutTrailing(AFolder);
  end;
end;

class function TDpccTeamFile.Locate(const AProjectFolder: string; const AExists: TDpccTeamFileExists): string;
begin
  Result := Locate(AProjectFolder, '', AExists);
end;

class function TDpccTeamFile.Locate(const AProjectFolder, AGroupFolder: string;
  const AExists: TDpccTeamFileExists): string;
var
  mFolder, mLimit, mGroup: string;
begin
  Result := '';
  mFolder := WithoutTrailing(AProjectFolder);
  mGroup := WithoutTrailing(AGroupFolder);
  if mFolder = '' then
  begin
    Exit;
  end;
  // Grenze der Suche aufwärts: Wurzel des Repositorys, ohne Repository die Gruppe darüber, sonst nur der Ordner.
  mLimit := RepositoryRoot(mFolder, AExists);
  if (mLimit = '') and FolderContains(mGroup, mFolder) then
  begin
    mLimit := mGroup;
  end;
  if mLimit = '' then
  begin
    mLimit := mFolder;
  end;
  while mFolder <> '' do
  begin
    if AExists(JoinPath(mFolder, cFileName)) then
    begin
      Exit(JoinPath(mFolder, cFileName));
    end;
    if SameText(mFolder, mLimit) then
    begin
      Break;
    end;
    mFolder := ParentOf(mFolder);
  end;
  // Die Gruppe kann außerhalb des Repositorys liegen (darüber oder daneben).
  if (mGroup <> '') and AExists(JoinPath(mGroup, cFileName)) then
  begin
    Result := JoinPath(mGroup, cFileName);
  end;
end;

class function TDpccTeamFile.Parse(const AText, AFileName, ARoot: string): TDpccTeamSettings;
var
  mReader: TTeamReader;
  mValue: TJSONValue;
  mOffset, mLine, mColumn: Integer;
begin
  mReader := TTeamReader.Create(AFileName, ARoot);
  try
    mValue := nil;
    if Trim(AText) <> '' then
    begin
      mValue := TJSONObject.ParseJSONValue(TJsoncScanner.StripComments(AText));
    end;
    try
      if mValue is TJSONObject then
      begin
        mReader.Read(TJSONObject(mValue));
      end
      else
      begin
        // Wo es hakt, sagt die Meldung mit Zeile und Spalte (sonst sucht man in der Datei nach dem Fehler).
        mLine := 0;
        mColumn := 0;
        mOffset := TJsoncScanner.SyntaxError(AText);
        if mOffset > 0 then
        begin
          TJsoncScanner.LineColumn(AText, mOffset, mLine, mColumn);
        end;
        mReader.Invalid(mLine, mColumn);
      end;
    finally
      mValue.Free;
    end;
    Result := mReader.Team;
  finally
    mReader.Free;
  end;
end;

const
  /// <summary>Gerüst der Teamdatei (TDpccTeamFile.Skeleton) je Sprache.</summary>
  cSkeletonLines: array[TDpccLanguage, 0..31] of string = (
    ('{',
     '  // Projekteinstellungen von dpcc für alle im Team (eingecheckt). Persönliche',
     '  // Einstellungen stehen unter Tools > Optionen > dpcc; ein Wert aus dieser',
     '  // Datei hat Vorrang. Keine Zugangsdaten und keine absoluten Pfade: dpcc',
     '  // ignoriert solche Einträge. Pfade relativ zu dieser Datei.',
     '  "version": 1,',
     '  "naming": {',
     '    // "field": "F", "parameter": "A", "local": "L", "constant": "c"',
     '  },',
     '  "formatFunctions": [',
     '    // {"name": "Log", "formatIndex": 0}',
     '  ],',
     '  "sqlTargets": [',
     '    // "TMyQuery.SQL"',
     '  ],',
     '  "fileMethods": [',
     '    // "TDateien.Laden"',
     '  ],',
     '  "mainThreadExceptions": [',
     '    // "TLogger.Write"',
     '  ],',
     '  "startProfiles": [',
     '    // {"name": "Demo", "parameters": "-demo", "workingDir": "Bin", "environment": {"MODUS": "demo"}}',
     '  ],',
     '  // Build-Server und Issue-Tracker; Benutzer und Token im Anmeldespeicher von Windows:',
     '  // "ci": {"provider": "jenkins", "url": "https://ci.example.com", "job": "projekt", "multibranch": false},',
     '  // "tracker": {"provider": "youtrack", "url": "https://example.youtrack.cloud", "project": "ATL"},',
     '  // Im Editor ausgeblendete Elemente („Nur hier“ bzw. „In dieser Datei ausblenden“, #628):',
     '  // "hidden": [{"setting": "BlockEndLabels", "file": "Source/Kunde.pas", "anchor": "TKunde.Speichern"}],',
     '  // Wertdarstellung beim Debuggen für fremde Klassen (eigene: // dpcc-debug: über dem Typ, #854):',
     '  // "debugDisplayRules": {"FireDAC.Comp.Client.TFDConnection": "{ConnectionName} ({DriverName})"},',
     '}'),
    ('{',
     '  // dpcc project settings for the whole team (checked in). Personal',
     '  // settings are under Tools > Options > dpcc; a value from this',
     '  // file takes precedence. No credentials and no absolute paths: dpcc',
     '  // ignores such entries. Paths are relative to this file.',
     '  "version": 1,',
     '  "naming": {',
     '    // "field": "F", "parameter": "A", "local": "L", "constant": "c"',
     '  },',
     '  "formatFunctions": [',
     '    // {"name": "Log", "formatIndex": 0}',
     '  ],',
     '  "sqlTargets": [',
     '    // "TMyQuery.SQL"',
     '  ],',
     '  "fileMethods": [',
     '    // "TFiles.Load"',
     '  ],',
     '  "mainThreadExceptions": [',
     '    // "TLogger.Write"',
     '  ],',
     '  "startProfiles": [',
     '    // {"name": "Demo", "parameters": "-demo", "workingDir": "Bin", "environment": {"MODE": "demo"}}',
     '  ],',
     '  // Build server and issue tracker; user and token in the Windows credential store:',
     '  // "ci": {"provider": "jenkins", "url": "https://ci.example.com", "job": "project", "multibranch": false},',
     '  // "tracker": {"provider": "youtrack", "url": "https://example.youtrack.cloud", "project": "ATL"},',
     '  // Elements hidden in the editor ("Only here" or "Hide in this file", #628):',
     '  // "hidden": [{"setting": "BlockEndLabels", "file": "Source/Customer.pas", "anchor": "TCustomer.Save"}],',
     '  // Value display while debugging for foreign classes (own ones: // dpcc-debug: above the type, #854):',
     '  // "debugDisplayRules": {"FireDAC.Comp.Client.TFDConnection": "{ConnectionName} ({DriverName})"},',
     '}'));

class function TDpccTeamFile.Skeleton: string;
begin
  Result := string.Join(#13#10, cSkeletonLines[TDpccTextLanguage.Current]) + #13#10;
end;

class function TDpccTeamFile.Prefix(const ATeam: TDpccTeamSettings; AKind: TDpccNamingKind;
  const APersonal: string): string;
begin
  Result := APersonal;
  if ATeam.Valid and ATeam.HasNaming[AKind] then
  begin
    Result := ATeam.Naming[AKind];
  end;
end;

class function TDpccTeamFile.MergeNames(const ATeam, APersonal: TArray<string>): TArray<string>;
var
  mItem, mKnown: string;
  mFound: Boolean;
begin
  Result := nil;
  for mItem in ATeam + APersonal do
  begin
    mFound := False;
    for mKnown in Result do
    begin
      if SameText(mKnown, mItem) then
      begin
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TDpccTeamFile.MergeFormatFunctions(const ATeam,
  APersonal: TArray<TDpccFormatFunction>): TArray<TDpccFormatFunction>;
var
  mItem, mKnown: TDpccFormatFunction;
  mFound: Boolean;
begin
  Result := nil;
  for mItem in ATeam + APersonal do
  begin
    mFound := False;
    for mKnown in Result do
    begin
      if SameText(mKnown.Name, mItem.Name) then
      begin
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

class function TDpccTeamFile.MergeStartProfiles(const ATeam,
  APersonal: TArray<TDpccStartProfile>): TArray<TDpccStartProfile>;
var
  mItem, mKnown: TDpccStartProfile;
  mFound: Boolean;
begin
  Result := nil;
  for mItem in ATeam + APersonal do
  begin
    mFound := False;
    for mKnown in Result do
    begin
      if SameText(mKnown.Name, mItem.Name) then
      begin
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Result := Result + [mItem];
    end;
  end;
end;

procedure AddValue(var AValues: TArray<TDpccTeamValue>; const AKey, AValue: string);
var
  mValue: TDpccTeamValue;
begin
  mValue.Key := AKey;
  mValue.Value := AValue;
  AValues := AValues + [mValue];
end;

/// <summary>AKey mit den Einträgen durch Komma getrennt; ohne Einträge nichts.</summary>
procedure AddList(var AValues: TArray<TDpccTeamValue>; const AKey: string; const AItems: TArray<string>);
begin
  if Length(AItems) > 0 then
  begin
    AddValue(AValues, AKey, string.Join(', ', AItems));
  end;
end;

function FormatFunctionItems(const AFunctions: TArray<TDpccFormatFunction>): TArray<string>;
var
  mItem: TDpccFormatFunction;
begin
  Result := nil;
  for mItem in AFunctions do
  begin
    Result := Result + [Format('%s (%d)', [mItem.Name, mItem.FormatIndex])];
  end;
end;

function ProfileItems(const AProfiles: TArray<TDpccStartProfile>): TArray<string>;
var
  mProfile: TDpccStartProfile;
begin
  Result := nil;
  for mProfile in AProfiles do
  begin
    Result := Result + [mProfile.Name];
  end;
end;

function HiddenItems(const APlaces: TArray<TDpccHiddenPlace>): TArray<string>;
var
  mPlace: TDpccHiddenPlace;
  mText: string;
begin
  Result := nil;
  for mPlace in APlaces do
  begin
    mText := mPlace.Setting + ' ' + mPlace.FileName;
    if mPlace.Anchor <> '' then
    begin
      mText := mText + ' (' + mPlace.Anchor + ')';
    end;
    Result := Result + [mText];
  end;
end;

function RuleItems(const ARules: TArray<TDpccTeamDisplayRule>): TArray<string>;
var
  mRule: TDpccTeamDisplayRule;
begin
  Result := nil;
  for mRule in ARules do
  begin
    Result := Result + [mRule.TypeName];
  end;
end;

function TrackerText(const ATracker: TDpccTeamTracker): string;
begin
  Result := ATracker.Provider + ', ' + ATracker.Url;
  if ATracker.Project <> '' then
  begin
    Result := Result + ', ' + ATracker.Project;
  end;
end;

function VcsText(const AVcs: TDpccTeamVcs): string;
begin
  Result := AVcs.Provider;
  if (Result <> '') and (AVcs.MainBranch <> '') then
  begin
    Result := Result + ', ';
  end;
  Result := Result + AVcs.MainBranch;
end;

class function TDpccTeamFile.Values(const ATeam: TDpccTeamSettings): TArray<TDpccTeamValue>;
var
  mKind: TDpccNamingKind;
begin
  Result := nil;
  if not ATeam.Valid then
  begin
    Exit;
  end;
  for mKind := Low(TDpccNamingKind) to High(TDpccNamingKind) do
  begin
    if ATeam.HasNaming[mKind] then
    begin
      AddValue(Result, 'naming.' + cNamingKeys[mKind], '"' + ATeam.Naming[mKind] + '"');
    end;
  end;
  AddList(Result, 'formatFunctions', FormatFunctionItems(ATeam.FormatFunctions));
  AddList(Result, 'sqlTargets', ATeam.SqlTargets);
  AddList(Result, 'fileMethods', ATeam.FileMethods);
  AddList(Result, 'mainThreadExceptions', ATeam.MainThreadExceptions);
  AddList(Result, 'startProfiles', ProfileItems(ATeam.StartProfiles));
  if ATeam.Ci.Configured then
  begin
    AddValue(Result, 'ci', Format('%s, %s, %s', [ATeam.Ci.Provider, ATeam.Ci.Url, ATeam.Ci.Job]));
  end;
  if ATeam.Tracker.Configured then
  begin
    AddValue(Result, 'tracker', TrackerText(ATeam.Tracker));
  end;
  if ATeam.Vcs.Configured then
  begin
    AddValue(Result, 'vcs', VcsText(ATeam.Vcs));
  end;
  AddList(Result, TDpccHiddenPlaces.cKey, HiddenItems(ATeam.Hidden));
  AddList(Result, cDisplayRulesKey, RuleItems(ATeam.DisplayRules));
end;

/// <summary>Teil eines Pfads anhängen: '' und '.' entfallen, '..' nimmt den letzten Teil weg (nie den ersten).
/// </summary>
procedure AddPathPart(var AParts: TArray<string>; const APart: string);
begin
  if (APart = '') or (APart = '.') then
  begin
    Exit;
  end;
  if APart <> '..' then
  begin
    AParts := AParts + [APart];
  end
  else if Length(AParts) > 1 then
  begin
    SetLength(AParts, Length(AParts) - 1);
  end;
end;

/// <summary>'\\' vor einem UNC-Pfad, '\' vor einem Pfad ab der Wurzel, sonst ''.</summary>
function PathLead(const AFolder: string): string;
begin
  Result := '';
  if (Length(AFolder) >= 2) and IsSeparator(AFolder[1]) and IsSeparator(AFolder[2]) then
  begin
    Result := '\\';
  end
  else if (AFolder <> '') and IsSeparator(AFolder[1]) then
  begin
    Result := '\';
  end;
end;

class function TDpccTeamFile.Combine(const AFolder, ARelative: string): string;
var
  mPath: string;
  mParts: TArray<string>;
  mStart, mIndex: Integer;
begin
  mPath := AFolder + '\' + ARelative;
  mParts := nil;
  mStart := 1;
  for mIndex := 1 to Length(mPath) + 1 do
  begin
    if (mIndex > Length(mPath)) or IsSeparator(mPath[mIndex]) then
    begin
      AddPathPart(mParts, Copy(mPath, mStart, mIndex - mStart));
      mStart := mIndex + 1;
    end;
  end;
  Result := PathLead(AFolder) + string.Join('\', mParts);
end;

end.
