unit dpcc.IDE.Projects.Context;

// Projektkontext aus der laufenden IDE (#396): Konfiguration und Plattform
// des Projekts, bedingte Symbole, Suchpfade und Unit-Namespaces aus den
// Optionen der aktiven Konfiguration für die aktive Plattform (mit geerbten
// Werten, auch ungespeicherte Änderungen), Bibliothekspfade aus den
// Bibliotheksoptionen der laufenden IDE (auch mit eigenem Profil -r) und ihre
// Version. Nur im Hauptthread aufrufen. Seit L2 auch der Browsing Path (Win64x ohne
// eigenen: der von Win64) und der Registry-Schlüssel des Profils.
//
// Ob GetValue(…, True) die geerbten Werte wirklich einsetzt, ist nur in der
// IDE prüfbar. Deshalb: Steht danach noch $(DCC_Define) im Wert, setzt das
// Plugin die Elternkonfigurationen selbst ein; fehlt die
// Konfigurationsschnittstelle oder wirft sie, gelten die Projektoptionen
// (IOTAProjectOptions.Values). Welcher Weg galt, steht in Source und mit
// Diagnose=1 im Protokoll.
//
// Macros (#759): Werte für $(…) in Such- und Bibliothekspfaden wie die IDE
// sie kennt: Umgebungsvariablen aus den IDE-Optionen (Registry "Environment
// Variables" des laufenden Profils), BDS-Ordner der laufenden IDE (BDS,
// BDSLIB, BDSBIN, BDSINCLUDE), BDSCOMMONDIR, BDSUSERDIR und
// BDSCatalogRepository der Version, Projekt, Plattform und Konfiguration;
// zuletzt die Umgebung des Prozesses.
//
// Präfixe (#452) und eigene Formatroutinen (#451) aus der Projektdatei .dpcc
// gibt es seit Rückbau R6 nicht mehr (TeamFile entfällt).
//
// Nicht bei jeder Anfrage voll lesen (V2): Group liest voll (FileExists, Optionen mit Elternstufen, Registry je
// Projekt; Aktivität „Projektkontext lesen“ im Einfrier-Wächter) und merkt sich die gespeicherten Projekte
// (SavedProjects, Generation). Der Tipp-Pfad ruft GroupIfDue: Das bildet nur einen Fingerabdruck der Gruppe aus der
// Open Tools API im Speicher (Projekte, aktives Projekt, Konfiguration und Plattform je Projekt) und liest voll nur,
// wenn TDpccProjectContextGate (dpcc.Core.Projects.ContextGate) es verlangt: Fingerabdruck geändert, Ereignis oder
// Sicherheitstakt (15 s). Ereignis ist das Schließen jedes modalen Dialogs der IDE (Projektoptionen, Tools ›
// Optionen; TApplicationEvents.OnModalEnd, beim Entladen in finalization freigegeben) und Invalidate.

interface

uses
  ToolsAPI,
  dpcc.Core.Projects.Contract,
  dpcc.Core.Projects.PathCheck;

type
  TDpccIdeProjectContext = class
  public
    /// <summary>Kontext eines Projekts; Project = '' für Projekte, die keine gespeicherte .dproj sind.</summary>
    class function Read(const AProject: IOTAProject): TDpccProjectContext; static;
    /// <summary>Kontexte aller Projekte der geöffneten Gruppe, die eine gespeicherte .dproj haben (volles Lesen; merkt
    /// sich Projekte und Fingerabdruck, siehe Kopf). Nur im Hauptthread.</summary>
    class function Group: TArray<TDpccProjectContext>; static;
    /// <summary>Für den Tipp-Pfad (Hauptthread): Nur wenn voll gelesen werden muss (Fingerabdruck geändert, Ereignis,
    /// Sicherheitstakt, erstes Mal), True mit AContexts wie Group und dem Anlass AReason (fürs Protokoll); sonst False
    /// ohne Datei- und Registry-Zugriff.</summary>
    class function GroupIfDue(out AContexts: TArray<TDpccProjectContext>; out AReason: string): Boolean; static;
    /// <summary>Gespeicherte Projekte (.dproj) der Gruppe aus dem letzten vollen Lesen, das aktive zuerst; ohne
    /// Datei-Zugriff.</summary>
    class function SavedProjects: TArray<string>; static;
    /// <summary>Zählt jedes volle Lesen; ein neuer Wert heißt, SavedProjects ist neu ermittelt.</summary>
    class function Generation: Cardinal; static;
    /// <summary>Ereignis: Die nächste Prüfung (GroupIfDue) liest voll. Threadsicher.</summary>
    class procedure Invalidate; static;
    /// <summary>Werte für $(…) in den Pfaden von AContext (siehe Kopf); nur im Hauptthread aufrufen, das Ergebnis
    /// darf in einen Hintergrundthread.</summary>
    class function Macros(const AContext: TDpccProjectContext): TDpccPathMacros; static;
    /// <summary>Wert der Option AName in Konfiguration AConfiguration ('' = aktive) für APlatform ('' = ohne
    /// Plattformkonfiguration), mit geerbten Werten wie Read; '' = nicht gesetzt oder nicht lesbar. Ohne
    /// Konfigurationsschnittstelle gelten die Projektoptionen, aber nur für die aktive Konfiguration (#533).
    /// </summary>
    class function ConfigurationValue(const AProject: IOTAProject; const AConfiguration, APlatform,
      AName: string): string; static;
    /// <summary>Namen der Build-Konfigurationen des Projekts (z. B. Base, Debug, Release); leer, wenn nicht lesbar.
    /// </summary>
    class function Configurations(const AProject: IOTAProject): TArray<string>; static;
    /// <summary>Hat das Projekt die Konfiguration AName (Groß-/Kleinschreibung egal)?</summary>
    class function HasConfiguration(const AProject: IOTAProject; const AName: string): Boolean; static;
    /// <summary>Build-Konfiguration AName ('' = aktive) ohne Plattform, etwa zum Setzen einer Option (#840); nil
    /// ohne.</summary>
    class function BuildConfiguration(const AProject: IOTAProject; const AName: string): IOTABuildConfiguration;
      static;
    /// <summary>Version von AProject in AConfiguration und APlatform aus seinen Versionsinformationen (#533, #1455);
    /// '' ohne.</summary>
    class function Version(const AProject: IOTAProject; const AConfiguration, APlatform: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Variants,
  System.Win.Registry,
  Winapi.Windows,
  Vcl.Forms,
  Vcl.AppEvnts,
  dpcc.Core.Versions.Project,
  dpcc.Core.Projects.ContextGate,
  dpcc.Core.Diagnostics.Deadline,
  dpcc.Core.Diagnostics.Hangs;

type
  /// <summary>Meldet das Schließen jedes modalen Dialogs der IDE als Ereignis (V2): In Projektoptionen und Tools ›
  /// Optionen ändert man Suchpfad, Defines und Bibliothekspfad. Nur im Hauptthread erzeugt und freigegeben.</summary>
  TModalWatch = class
  private
    FEvents: TApplicationEvents;
    procedure ModalEnded(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
  end;

var
  /// <summary>Entscheidung „voll lesen ja/nein“; von initialization bis finalization.</summary>
  ContextGate: TDpccProjectContextGate;
  /// <summary>Beobachter der modalen Dialoge; beim ersten vollen Lesen erzeugt, in finalization freigegeben.</summary>
  ModalWatch: TModalWatch;
  /// <summary>Ergebnis des letzten vollen Lesens (nur Hauptthread).</summary>
  ReadProjects: TArray<string>;
  ReadGeneration: Cardinal;

{ TModalWatch }

constructor TModalWatch.Create;
begin
  inherited Create;
  FEvents := TApplicationEvents.Create(nil);
  FEvents.OnModalEnd := ModalEnded;
end;

destructor TModalWatch.Destroy;
begin
  // Abmelden, bevor das Package entladen ist: TApplicationEvents trägt sich beim Freigeben aus der Verteilung der VCL
  // aus.
  FreeAndNil(FEvents);
  inherited;
end;

procedure TModalWatch.ModalEnded(Sender: TObject);
begin
  // Nur ein Zähler: kann nicht werfen und kostet nichts im Dialog der IDE.
  TDpccIdeProjectContext.Invalidate;
end;

/// <summary>Modale Dialoge beobachten, einmal je Laden des Packages (Hauptthread).</summary>
procedure WatchModalDialogs;
begin
  if (ModalWatch = nil) and (Application <> nil) and (GetCurrentThreadId = MainThreadID) then
  begin
    ModalWatch := TModalWatch.Create;
  end;
end;

/// <summary>Fingerabdruck der Gruppe nur aus der Open Tools API im Speicher (ohne Datei und Registry); False, wenn
/// nicht lesbar.</summary>
function TryFingerprint(const AGroup: IOTAProjectGroup; out AFingerprint: string): Boolean;
var
  mActive, mProject: IOTAProject;
  mIndex: Integer;
  mConfiguration, mPlatform: string;
begin
  AFingerprint := '';
  if AGroup = nil then
  begin
    Exit(True);
  end;
  try
    mActive := AGroup.ActiveProject;
    for mIndex := 0 to AGroup.ProjectCount - 1 do
    begin
      mProject := AGroup.Projects[mIndex];
      if mProject = nil then
      begin
        Continue;
      end;
      mConfiguration := '';
      mPlatform := '';
      // Wie Read: Konfiguration und Plattform nur bei .dproj.
      if SameText(ExtractFileExt(mProject.FileName), '.dproj') then
      begin
        mConfiguration := mProject.CurrentConfiguration;
        mPlatform := mProject.CurrentPlatform;
      end;
      AFingerprint := AFingerprint + TDpccProjectContextGate.ProjectPart(mProject.FileName, mConfiguration, mPlatform,
        mProject = mActive);
    end;
    Result := True;
  except
    on Exception do
    begin
      AFingerprint := '';
      Result := False;
    end;
  end;
end;

function MainGroup: IOTAProjectGroup;
var
  mModules: IOTAModuleServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Result := mModules.MainProjectGroup;
  end;
end;

/// <summary>Konfiguration AConfiguration ('' = aktive), für APlatform deren Plattformkonfiguration; nil ohne.
/// </summary>
function NamedConfiguration(const AProject: IOTAProject; const AConfiguration,
  APlatform: string): IOTABuildConfiguration;
var
  mConfigurations: IOTAProjectOptionsConfigurations;
  mPlatformed: IOTABuildConfiguration;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, mConfigurations) then
  begin
    Exit;
  end;
  if AConfiguration = '' then
  begin
    Result := mConfigurations.ActiveConfiguration;
  end
  else
  begin
    for mIndex := 0 to mConfigurations.ConfigurationCount - 1 do
    begin
      if SameText(mConfigurations.Configurations[mIndex].Name, AConfiguration) then
      begin
        Result := mConfigurations.Configurations[mIndex];
        Break;
      end;
    end;
  end;
  if (Result = nil) or (APlatform = '') then
  begin
    Exit;
  end;
  // Plattformabhängige Werte (z. B. Suchpfade nur für Win64) stehen in der Plattformkonfiguration.
  mPlatformed := Result.PlatformConfiguration[APlatform];
  if mPlatformed <> nil then
  begin
    Result := mPlatformed;
  end;
end;

function BuildConfiguration(const AProject: IOTAProject; const APlatform: string): IOTABuildConfiguration;
begin
  Result := NamedConfiguration(AProject, '', APlatform);
end;

/// <summary>Wert mit geerbten Werten; AResolved wird True, wenn das Plugin $(AName) selbst einsetzen musste.</summary>
function ConfigValue(const ABuild: IOTABuildConfiguration; const AName: string; ADepth: Integer;
  var AResolved: Boolean): string;
var
  mParent: IOTABuildConfiguration;
begin
  Result := ABuild.GetValue(AName, True);
  if not TDpccProjectContext.RefersToItself(Result, AName) then
  begin
    Exit;
  end;
  mParent := ABuild.Parent;
  if (mParent = nil) or (ADepth > 8) then
  begin
    Result := TDpccProjectContext.Inherit(Result, AName, '');
  end
  else
  begin
    Result := TDpccProjectContext.Inherit(Result, AName, ConfigValue(mParent, AName, ADepth + 1, AResolved));
  end;
  AResolved := True;
end;

function OptionValue(const AProject: IOTAProject; const AName: string): string;
begin
  try
    Result := TDpccProjectContext.Inherit(VarToStr(AProject.ProjectOptions.Values[AName]), AName, '');
  except
    on Exception do
      Result := '';
  end;
end;

procedure ReadOptions(const AProject: IOTAProject; var AContext: TDpccProjectContext);
var
  mBuild: IOTABuildConfiguration;
  mResolved: Boolean;
begin
  mResolved := False;
  try
    mBuild := BuildConfiguration(AProject, AContext.Platform);
    if mBuild <> nil then
    begin
      AContext.Defines := TDpccProjectContext.List(ConfigValue(mBuild, 'DCC_Define', 0, mResolved));
      AContext.SearchPaths := TDpccProjectContext.List(ConfigValue(mBuild, 'DCC_UnitSearchPath', 0, mResolved));
      AContext.Namespaces := TDpccProjectContext.List(ConfigValue(mBuild, 'DCC_Namespace', 0, mResolved));
      AContext.Source := TDpccProjectContext.cSourceConfiguration;
      if mResolved then
      begin
        AContext.Source := TDpccProjectContext.cSourceResolved;
      end;
      Exit;
    end;
  except
    on Exception do
      ; // Ersatzweg unten.
  end;
  if AProject.ProjectOptions = nil then
  begin
    Exit;
  end;
  AContext.Defines := TDpccProjectContext.List(OptionValue(AProject, 'DCC_Define'));
  AContext.SearchPaths := TDpccProjectContext.List(OptionValue(AProject, 'DCC_UnitSearchPath'));
  AContext.Namespaces := TDpccProjectContext.List(OptionValue(AProject, 'DCC_Namespace'));
  AContext.Source := TDpccProjectContext.cSourceOptions;
end;

/// <summary>Liste AValueName ("Search Path", "Browsing Path") der Bibliotheksoptionen unter ABaseKey.</summary>
function RegistryPaths(const ABaseKey, APlatform, AValueName: string): TArray<string>;
var
  mRegistry: TRegistry;
begin
  Result := nil;
  if (ABaseKey = '') or (APlatform = '') then
  begin
    Exit;
  end;
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if mRegistry.OpenKeyReadOnly(ABaseKey + '\Library\' + APlatform) and mRegistry.ValueExists(AValueName) then
    begin
      Result := TDpccProjectContext.List(mRegistry.ReadString(AValueName));
    end;
  finally
    mRegistry.Free;
  end;
end;

function LibraryPaths(const ABaseKey, APlatform: string): TArray<string>;
begin
  Result := RegistryPaths(ABaseKey, APlatform, 'Search Path');
end;

/// <summary>Browsing Path (L2); Win64x hat keinen eigenen und nimmt den von Win64.</summary>
function BrowsingPaths(const ABaseKey, APlatform: string): TArray<string>;
begin
  Result := RegistryPaths(ABaseKey, APlatform, 'Browsing Path');
  if (Length(Result) = 0) and SameText(APlatform, 'Win64x') then
  begin
    Result := RegistryPaths(ABaseKey, 'Win64', 'Browsing Path');
  end;
end;

function BaseRegistryKey: string;
var
  mServices: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Result := mServices.GetBaseRegistryKey;
  end;
end;

/// <summary>Umgebungsvariablen der IDE-Optionen unter ABaseKey in AMacros; nichts ohne Schlüssel.</summary>
procedure AddIdeEnvironment(var AMacros: TDpccPathMacros; const ABaseKey: string);
var
  mRegistry: TRegistry;
  mNames: TStringList;
  mName: string;
begin
  if ABaseKey = '' then
  begin
    Exit;
  end;
  mRegistry := TRegistry.Create(KEY_READ);
  mNames := TStringList.Create;
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if mRegistry.OpenKeyReadOnly(ABaseKey + '\Environment Variables') then
    begin
      mRegistry.GetValueNames(mNames);
      for mName in mNames do
      begin
        try
          AMacros.Add(mName, mRegistry.ReadString(mName));
        except
          on Exception do
            ; // Kein Text (etwa REG_DWORD): übergehen.
        end;
      end;
    end;
  finally
    mNames.Free;
    mRegistry.Free;
  end;
end;

class function TDpccIdeProjectContext.Read(const AProject: IOTAProject): TDpccProjectContext;
var
  mBaseKey: string;
begin
  Result := Default(TDpccProjectContext);
  if (AProject = nil) or not SameText(ExtractFileExt(AProject.FileName), '.dproj') or
    not FileExists(AProject.FileName) then
  begin
    Exit;
  end;
  Result.Project := AProject.FileName;
  Result.Configuration := AProject.CurrentConfiguration;
  Result.Platform := AProject.CurrentPlatform;
  mBaseKey := BaseRegistryKey;
  Result.BdsVersion := TDpccProjectContext.VersionOfRegistryKey(mBaseKey);
  ReadOptions(AProject, Result);
  Result.LibraryPaths := LibraryPaths(mBaseKey, Result.Platform);
  // L2: Browsing Path und Schlüssel des Profils; eine Änderung am Browsing Path ändert so den Kontext.
  Result.BrowsingPaths := BrowsingPaths(mBaseKey, Result.Platform);
  Result.RegistryKey := mBaseKey;
end;

class function TDpccIdeProjectContext.Macros(const AContext: TDpccProjectContext): TDpccPathMacros;
var
  mStudio: string;
  mServices: IOTAServices;
begin
  Result := TDpccPathMacros.Create(
    function(const AName: string): string
    begin
      Result := GetEnvironmentVariable(AName);
    end);
  // Umgebungsvariablen aus den IDE-Optionen (Tools › Optionen › Umgebungsvariablen) gehen allem vor.
  AddIdeEnvironment(Result, BaseRegistryKey);
  // Ordner der laufenden IDE.
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Result.AddBds(mServices.GetRootDirectory);
  end;
  // Ordner der Version unter „Öffentliche Dokumente“ und „Dokumente“, wie sie die IDE setzt.
  if AContext.BdsVersion <> '' then
  begin
    mStudio := 'Embarcadero\Studio\' + AContext.BdsVersion;
    try
      Result.AddDefault('BDSCOMMONDIR', IncludeTrailingPathDelimiter(TPath.GetSharedDocumentsPath) + mStudio);
      Result.AddDefault('BDSUSERDIR', IncludeTrailingPathDelimiter(TPath.GetDocumentsPath) + mStudio);
      Result.AddDefault('BDSCatalogRepository', IncludeTrailingPathDelimiter(TPath.GetDocumentsPath) + mStudio +
        '\CatalogRepository');
    except
      on Exception do
        ; // Ordner nicht ermittelbar: dann gilt die Umgebung des Prozesses.
    end;
  end;
  Result.AddProject(AContext.Project, AContext.Platform, AContext.Configuration);
end;

class function TDpccIdeProjectContext.ConfigurationValue(const AProject: IOTAProject; const AConfiguration,
  APlatform, AName: string): string;
var
  mBuild: IOTABuildConfiguration;
  mResolved: Boolean;
begin
  Result := '';
  if AProject = nil then
  begin
    Exit;
  end;
  mResolved := False;
  try
    mBuild := NamedConfiguration(AProject, AConfiguration, APlatform);
    if mBuild <> nil then
    begin
      Exit(ConfigValue(mBuild, AName, 0, mResolved));
    end;
  except
    on Exception do
      ; // Ersatzweg unten.
  end;
  if (AProject.ProjectOptions <> nil) and
    ((AConfiguration = '') or SameText(AConfiguration, AProject.CurrentConfiguration)) then
  begin
    Result := OptionValue(AProject, AName);
  end;
end;

class function TDpccIdeProjectContext.BuildConfiguration(const AProject: IOTAProject;
  const AName: string): IOTABuildConfiguration;
begin
  Result := nil;
  if AProject <> nil then
  begin
    Result := NamedConfiguration(AProject, AName, '');
  end;
end;

class function TDpccIdeProjectContext.Configurations(const AProject: IOTAProject): TArray<string>;
var
  mItems: IOTAProjectOptionsConfigurations;
  mIndex: Integer;
begin
  Result := nil;
  try
    if (AProject <> nil) and Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, mItems) then
    begin
      for mIndex := 0 to mItems.ConfigurationCount - 1 do
      begin
        Result := Result + [mItems.Configurations[mIndex].Name];
      end;
    end;
  except
    on Exception do
      Result := nil;
  end;
end;

class function TDpccIdeProjectContext.HasConfiguration(const AProject: IOTAProject; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in Configurations(AProject) do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
end;

class function TDpccIdeProjectContext.Group: TArray<TDpccProjectContext>;
var
  mActivity: IInterface;
  mProjects: IOTAProjectGroup;
  mIndex: Integer;
  mContext: TDpccProjectContext;
  mSignals: Integer;
  mFingerprint: string;
  mKnown: Boolean;
  mActive, mOthers: TArray<string>;
begin
  // Messbar im Einfrier-Wächter (Hauptthread ab 50 ms).
  mActivity := TDpccActivity.Scope('Projektkontext lesen');
  Result := nil;
  WatchModalDialogs;
  // Vor dem Lesen: Ein Ereignis währenddessen löst das nächste volle Lesen aus.
  mSignals := ContextGate.Signals;
  mProjects := MainGroup;
  mKnown := TryFingerprint(mProjects, mFingerprint);
  if mProjects <> nil then
  begin
    for mIndex := 0 to mProjects.ProjectCount - 1 do
    begin
      mContext := Read(mProjects.Projects[mIndex]);
      // Aktives Projekt für Dateien, die zu mehreren Projekten gehören (#46).
      mContext.Active := mProjects.Projects[mIndex] = mProjects.ActiveProject;
      if mContext.Project <> '' then
      begin
        Result := Result + [mContext];
        // Projektliste wie TDpccCodeInsightSession.GroupProjects: gespeicherte .dproj, das aktive zuerst.
        if mContext.Active then
        begin
          mActive := mActive + [mContext.Project];
        end
        else
        begin
          mOthers := mOthers + [mContext.Project];
        end;
      end;
    end;
  end;
  ReadProjects := mActive + mOthers;
  Inc(ReadGeneration);
  // Ohne lesbaren Fingerabdruck bleibt der alte Stand; GroupIfDue liest dann jedes Mal voll (wie vor V2).
  if mKnown then
  begin
    ContextGate.Done(mFingerprint, mSignals);
  end;
end;

class function TDpccIdeProjectContext.GroupIfDue(out AContexts: TArray<TDpccProjectContext>;
  out AReason: string): Boolean;
var
  mFingerprint: string;
  mReason: TDpccContextReadReason;
begin
  AContexts := nil;
  AReason := '';
  if TryFingerprint(MainGroup, mFingerprint) then
  begin
    mReason := ContextGate.Due(mFingerprint);
  end
  else
  begin
    mReason := TDpccContextReadReason.Changed;
  end;
  if mReason = TDpccContextReadReason.None then
  begin
    Exit(False);
  end;
  AReason := TDpccProjectContextGate.ReasonText(mReason);
  AContexts := Group;
  Result := True;
end;

class function TDpccIdeProjectContext.SavedProjects: TArray<string>;
begin
  Result := ReadProjects;
end;

class function TDpccIdeProjectContext.Generation: Cardinal;
begin
  Result := ReadGeneration;
end;

class procedure TDpccIdeProjectContext.Invalidate;
begin
  if ContextGate <> nil then
  begin
    ContextGate.Signal;
  end;
end;

class function TDpccIdeProjectContext.Version(const AProject: IOTAProject; const AConfiguration,
  APlatform: string): string;

  function Value(const AName: string): string;
  begin
    Result := Trim(ConfigurationValue(AProject, AConfiguration, APlatform, AName));
  end;

begin
  Result := '';
  if (AProject = nil) or (AProject.ProjectOptions = nil) then
  begin
    Exit;
  end;
  Result := TDpccProjectVersion.FromOptions(Value('VerInfo_IncludeVerInfo'), Value('VerInfo_Keys'), Value('VerInfo_MajorVer'),
    Value('VerInfo_MinorVer'), Value('VerInfo_Release'), Value('VerInfo_Build'));
end;

/// <summary>Entscheidung mit dem 64-Bit-Tickzähler als Uhr.</summary>
function NewContextGate: TDpccProjectContextGate;
begin
  Result := TDpccProjectContextGate.Create(
    function: UInt64
    begin
      Result := TDpccTicks.Now;
    end);
end;

initialization
  ContextGate := NewContextGate;

finalization
  // Erst den Beobachter (er meldet an ContextGate), dann die Entscheidung; beides im Hauptthread beim Entladen.
  FreeAndNil(ModalWatch);
  FreeAndNil(ContextGate);

end.
