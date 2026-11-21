; =============================================================================
; dpccSetup.iss  -  Inno Setup 6.x, dpcc-Paketsatz fuer Delphi 12 und Delphi 13
; Installiert die acht Packages von dpcc je Benutzer und traegt sie in die IDE ein.
; Beschreibung, Bau und Testmatrix: installer\README_Installer.md
;
; Leitplanken (bindend):
;   * Per-User: HKCU + %LOCALAPPDATA%\Programs\dpcc - NIE elevieren
;     (elevated wuerde HKCU in den Admin-Hive schreiben).
;   * "Known Packages" (NICHT "Known IDE Packages"/"Experts"); Wertdaten NIE
;     leer (leere Wertdaten = Package laedt nicht). Dort steht nur
;     dpcc.IDE.Base<suffix>.bpl ({$DESIGNONLY}); die sieben Laufzeitpakete
;     ({$RUNONLY}) gehoeren nie dorthin, die IDE findet sie ueber den PATH.
;   * Deinstallation: Registry-Werte VOR den Dateien entfernen.
;   * Das Setup baut KEINE Netzverbindung auf - kein Update-Check, keine
;     Telemetrie, kein Download.
;   * Nur Win32: D12 = BDS 23.0, D13 = BDS 37.0, jeweils die 32-bit-IDE.
;   * Der IDE-PATH-Override ist ein GETEILTER Wert: nur das eigene Segment
;     einfuegen oder entfernen, nie den Wert ersetzen.
;   * Einstellungen (HKCU\Software\dpcc), Daten (%APPDATA%\dpcc), Cache und
;     Protokoll (%LOCALAPPDATA%\dpcc) fasst das Setup nicht an, auch die
;     Deinstallation nicht.
;   * Den Code-Insight-Anbieter der IDE stellt dpcc beim Start selbst um;
;     das Setup schreibt dort nichts. Die Deinstallation warnt nur, wenn dpcc
;     noch als Anbieter eingetragen ist.
;   * Laeuft eine Delphi-IDE, bricht das Setup ab; es beendet nie Prozesse.
; =============================================================================

; --- Repo-Wurzel ----------------------------------------------------------------
; Absolut, mit abschliessendem Backslash. Per ISCC /D ueberschreibbar:
;   iscc /DDpccRepoRoot="D:\pfad\zum\repo\" dpccSetup.iss
#ifndef DpccRepoRoot
  #define DpccRepoRoot SourcePath + "..\"
#endif

; --- Versionsstand --------------------------------------------------------------
; Einzige Quelle ist dpcc.Text.Product.Version (TDpccVersion.cVersion, SemVer
; x.y.z); das Setup liest sie beim Kompilieren selbst und haengt ".0" an
; (VERSIONINFO hat vier Felder). Tools\Build-Setup.ps1 reicht dieselbe Zahl
; per /DDpccVersion=x.y.z.0 durch. Ein Hand-Compile ohne /D bekommt damit
; dieselbe Version, eine von Hand gepflegte Kopie gibt es nicht.
; Vierstellig (DpccVersion) bleiben VersionInfoVersion und der Dateiname des
; Setups; angezeigt wird die dreistellige Fassung DpccVersionShort (x.y.z),
; die unten aus DpccVersion entsteht, indem der letzte Teil wegfaellt.
#ifndef DpccVersion
  #define DpccVersionFile DpccRepoRoot + "Packages\dpcc.Text\Source\Product\dpcc.Text.Product.Version.pas"
  ; Zeilenweise lesen bis zur ersten Zeile mit "cVersion = '...'". Bewusst als
  ; Ausdruck im #for und nicht als #sub: ein #if innerhalb von #sub griff
  ; beim Test nicht (Inno Setup 6.7).
  #define VerMarker "cVersion = '"
  #define VerTail(str L) Copy(L, Pos(VerMarker, L) + Len(VerMarker), Len(L))
  #define VerOf(str L) Pos(VerMarker, L) > 0 ? Copy(VerTail(L), 1, Pos("'", VerTail(L)) - 1) : ""
  #define VerHandle
  #define VerFound ""
  #for {VerHandle = FileOpen(DpccVersionFile); VerHandle && !FileEof(VerHandle) && VerFound == ""; ""} VerFound = VerOf(FileRead(VerHandle))
  #if VerHandle
    #expr FileClose(VerHandle)
  #endif
  #if VerFound == ""
    #error dpcc-Version nicht gefunden (cVersion in dpcc.Text.Product.Version.pas)
  #endif
  #define DpccVersion VerFound + ".0"
#endif
; Anzeige ohne den letzten Teil: 0.1.0.0 -> 0.1.0 (AppVersion).
#define DpccVersionShort Copy(DpccVersion, 1, RPos(".", DpccVersion) - 1)
#define DpccAppName     "Delphi Pascal Code Completion (dpcc)"
#define DpccPublisher   "dear Technologies"

; --- Community-Buttons unten links im Wizard. Klick
; oeffnet den STANDARD-BROWSER - rein nutzerinitiiert, das Setup selbst baut
; keine Verbindung auf. DpccDonateUrl leer = Spenden-Button erscheint nicht
; (fuer dpcc ist kein Spendenlink festgelegt; per /DDpccDonateUrl=... setzbar).
#ifndef DpccDonateUrl
  #define DpccDonateUrl ""
#endif
#define DpccGitHubUrl   "https://github.com/nrodear/DelphiCodeCompletion"

; --- Quell-BPLs -------------------------------------------------------------------
; Acht BPLs je Delphi-Version, alle mit {$LIBSUFFIX AUTO}:
;   dpcc.Text, dpcc.WinBase, dpcc.Common, dpcc.Windows, dpcc.Server,
;   dpcc.Core, dpcc.UI    Laufzeitpakete ({$RUNONLY})
;   dpcc.IDE.Base         Design-Paket ({$DESIGNONLY}), requires die sieben
; Die dproj setzen DCC_BplOutput auf Output\$(Platform)\$(Config)\Bpl im Repo:
;   Delphi 13: dpcc_d13.groupproj, Win32, Konfiguration Debug -> Output\Win32\Debug\Bpl
;   Delphi 12: dpcc_d12.groupproj, Win32, Konfiguration D12   -> Output\Win32\D12\Bpl
; Genau dorthin zeigen die Defaults; per ISCC /D ueberschreibbar:
;   iscc /DDpccBplSourceDirD12="D:\release\d12" /DDpccBplSourceDirD13="D:\release\d13" dpccSetup.iss
;
; Ladeweg: Der Windows-Loader loest requires ueber bds.exe-Verzeichnis,
; System32 und PATH auf, NIE im Ordner der Design-BPL. Deshalb steht nur
; dpcc.IDE.Base<suffix>.bpl in den Known Packages (voller Pfad), und
; {app}\bpl\<version> kommt vorn in den IDE-eigenen Override
; HKCU\Software\Embarcadero\BDS\<bds>\Environment Variables\PATH (derselbe
; Eintrag, den Tools\IdePath.ps1 fuer den Entwickler-Bau setzt).
#ifndef DpccBplSourceDirD12
  #define DpccBplSourceDirD12 DpccRepoRoot + "Output\Win32\D12\Bpl"
#endif
#ifndef DpccBplSourceDirD13
  #define DpccBplSourceDirD13 DpccRepoRoot + "Output\Win32\Debug\Bpl"
#endif

; Package-Version (LIBSUFFIX AUTO): 290 fuer Delphi 12, 370 fuer Delphi 13.
; Der Suffix steckt in JEDEM der acht Namen; damit koennen die BPLs beider
; Versionen nebeneinander im PATH stehen, ohne dass Delphi 12 die Fassung von
; Delphi 13 laedt.
#define DpccSuffixD12 "290"
#define DpccSuffixD13 "370"
#define DpccIdeBplD12 "dpcc.IDE.Base" + DpccSuffixD12 + ".bpl"
#define DpccIdeBplD13 "dpcc.IDE.Base" + DpccSuffixD13 + ".bpl"
; Wertdaten der Known Packages = {$DESCRIPTION} aus dpcc.IDE.Base.dpk.
#define DpccPackageDescription "dpcc - Delphi Pascal Code Completion"

; BDS-Registry-Schluessel (HKCU). Der Nummernsprung 23.0 -> 37.0 ist real.
#define KnownPackages23 "Software\Embarcadero\BDS\23.0\Known Packages"
#define KnownPackages37 "Software\Embarcadero\BDS\37.0\Known Packages"

; --- Keine 64-bit-IDE ---------------------------------------------------------------
; Delphi 12 hat keine 64-bit-IDE. Delphi 13 hat eine (bin64\bds.exe, eigener
; Zweig "Known Packages x64"); dpcc baut dafuer aber keine Win64-BPLs, es gibt
; nur Output\Win32. Deshalb gibt es keine Schiene fuer die 64-bit-IDE:
; eine Win32-BPL laedt die 64-bit-IDE nie.

[Setup]
; Eigene AppId; an ihr erkennt Windows das Produkt bei Update und Deinstallation.
AppId={{1CC1EC9F-520B-40D8-A96C-CC5387D2FEC0}
AppName={#DpccAppName}
AppVersion={#DpccVersionShort}
; Ohne VersionInfoVersion bleibt die FileVersion der Setup-Exe LEER.
VersionInfoVersion={#DpccVersion}
AppPublisher={#DpccPublisher}
AppPublisherURL={#DpccGitHubUrl}
AppSupportURL={#DpccGitHubUrl}/issues
DefaultDirName={localappdata}\Programs\dpcc
DisableProgramGroupPage=yes
; NIE elevieren (HKCU-Schreibziel!):
PrivilegesRequired=lowest
OutputBaseFilename=dpccSetup-{#DpccVersion}
Compression=lzma2
SolidCompression=yes
; Das Setup selbst laeuft als 32-bit-Prozess; es legt nur Win32-BPLs ab.
ArchitecturesAllowed=x86compatible x64compatible
UninstallDisplayName={#DpccAppName}
; Nicht auf eine BPL zeigen: jede Version ist abwaehlbar, die Datei fehlte dann.
UninstallDisplayIcon={uninstallexe}
; Kein Neustart noetig; der IDE-Check passiert im [Code]-Teil:
CloseApplications=no
; Sprachauswahl IMMER anbieten (deutsche Nutzer mit englischem Windows sind
; in der Delphi-Welt haeufig - fragen statt raten):
ShowLanguageDialog=yes
; Lizenz-Seite: MIT, LICENSE im Repo-Root.
LicenseFile={#DpccRepoRoot}LICENSE

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
de.IdeRunning=Eine Delphi-IDE (bds.exe) scheint zu laufen. Bitte alle Delphi-Instanzen schließen und erneut starten. Das Setup beendet keine Programme.
en.IdeRunning=A Delphi IDE (bds.exe) appears to be running. Please close all Delphi instances and start again. Setup does not close any programs.
de.NoDelphi=Es wurde weder Delphi 12 (BDS 23.0) noch Delphi 13 (BDS 37.0) auf diesem System gefunden. dpcc unterstützt Delphi 12 und Delphi 13 (jeweils die 32-bit-IDE); ältere Versionen werden nicht unterstützt. Das Setup wird beendet, es wird nichts installiert.
en.NoDelphi=Neither Delphi 12 (BDS 23.0) nor Delphi 13 (BDS 37.0) was found on this system. dpcc supports Delphi 12 and Delphi 13 (32-bit IDE each); older versions are not supported. Setup will close without installing anything.
de.DevBplWarn=Unter "%2" ist bereits eine Registrierung von dpcc mit anderem Pfad eingetragen (z. B. ein eigener Bau aus dem Repo):%n%n%1%nDer Eintrag wird durch die Installations-Registrierung ersetzt; beide zusammen ließen die IDE beim Start scheitern. Wer später wieder den eigenen Bau nutzt, trägt ihn neu ein (docs\de\installation.md).
en.DevBplWarn=A registration of dpcc with a different path already exists under "%2" (for example your own build from the repository):%n%n%1%nIt will be replaced by the installed registration; having both would make the IDE fail at startup. To use your own build again later, register it again (docs\en\installation.md).
de.OverrideFail=Der PATH-Eintrag der IDE konnte nicht geschrieben werden (%1). Ohne ihn lädt dpcc beim IDE-Start nicht.
en.OverrideFail=The IDE's PATH entry could not be written (%1). Without it dpcc will not load when the IDE starts.
de.ProviderStill=dpcc ist noch als Code-Insight-Anbieter eingetragen in:%n%n%1%nOhne das Plugin bleiben dort sonst Help Insight, die Kurzhinweise und der Wert-Tooltip der IDE aus.%n%nEmpfohlen: Delphi starten, unter Tools > Optionen > Drittanbieter > dpcc den Hauptschalter ausschalten, mit OK schließen, Delphi einmal neu starten und wieder schließen. dpcc stellt dabei den Anbieter (DelphiLSP) und seine Schalter zurück.%n%nTrotzdem jetzt deinstallieren?
en.ProviderStill=dpcc is still set as the Code Insight provider in:%n%n%1%nWithout the plugin, Help Insight, tooltips and the value tooltip of the IDE would then stay off there.%n%nRecommended: start Delphi, turn off the main switch under Tools > Options > Third Party > dpcc, close with OK, restart Delphi once and close it again. dpcc then restores the provider (DelphiLSP) and its switches.%n%nUninstall now anyway?
de.DonateBtn=Spenden
en.DonateBtn=Donate
de.StarBtn=Stern auf GitHub
en.StarBtn=Star on GitHub
; Startmenue-Eintrag zum Deinstaller (siehe [Icons]).
de.UninstallShortcut=dpcc deinstallieren
en.UninstallShortcut=Uninstall dpcc
; --- Auswahlliste der Ziel-IDEs -----------------------------------------------
; Angezeigt wird nur, was auf diesem Rechner wirklich gefunden wurde - die
; Check:-Ausdruecke der [Components] blenden den Rest aus.
de.TypeFull=Alle gefundenen Delphi-Versionen
en.TypeFull=All Delphi versions found
de.TypeCustom=Benutzerdefiniert
en.TypeCustom=Custom
de.CompD12=Delphi 12 Athens (32-bit-IDE)
en.CompD12=Delphi 12 Athens (32-bit IDE)
de.CompD13=Delphi 13 Florence (32-bit-IDE)
en.CompD13=Delphi 13 Florence (32-bit IDE)
de.NoComponent=Bitte mindestens eine Delphi-Version auswählen - sonst wird dpcc nicht installiert.
en.NoComponent=Please select at least one Delphi version - otherwise dpcc is not installed.
; Versions-Uebersicht auf der "Ready to Install"-Seite. Dieselben Aussagen
; wie die Tabelle in README_Installer.md, Abschnitt 0 - bei Aenderungen BEIDE
; Stellen pflegen.
de.ReadyHead=Unterstützte Delphi-Versionen:
en.ReadyHead=Supported Delphi versions:
de.ReadyYes1=Delphi 12 Athens (32-bit-IDE)  -  wird unterstützt
en.ReadyYes1=Delphi 12 Athens (32-bit IDE)  -  supported
de.ReadyYes2=Delphi 13 Florence (32-bit-IDE)  -  wird unterstützt
en.ReadyYes2=Delphi 13 Florence (32-bit IDE)  -  supported
de.ReadyNo1=Delphi 13 Florence (64-bit-IDE)  -  nicht unterstützt (nur 32-bit-IDE)
en.ReadyNo1=Delphi 13 Florence (64-bit IDE)  -  not supported (32-bit IDE only)
de.ReadyNo2=Delphi 11 und älter  -  nicht unterstützt
en.ReadyNo2=Delphi 11 and older  -  not supported
de.ReadyNote=Alternative: das Projekt von GitHub laden und die Packages selbst in der IDE bauen und installieren - Anleitung (docs\de\installation.md) im Repository:
en.ReadyNote=Alternative: download the project from GitHub and build/install the packages yourself in the IDE - instructions (docs\en\installation.md) in the repository:
de.ReadyPath=Das Setup trägt seinen Paketordner vorn in die PATH-Einstellung der gewählten IDEs ein (Tools > Optionen > IDE > Umgebungsvariablen), sonst findet die IDE die sieben Laufzeitpakete von dpcc nicht. Bestehende Einträge bleiben erhalten, die Deinstallation nimmt nur diesen Ordner wieder heraus.
en.ReadyPath=Setup adds its package folder to the front of the PATH setting of the selected IDEs (Tools > Options > IDE > Environment Variables); without it the IDE cannot find the seven runtime packages of dpcc. Existing entries stay in place, uninstalling removes only this folder.
de.ReadyStart=Nach der Installation: Ist in Delphi DelphiLSP als Code-Insight-Anbieter gewählt (Vorgabe), bleibt dpcc zunächst aus. Einschalten unter Tools > Optionen > Drittanbieter > dpcc (Hauptschalter, OK, Delphi neu starten).
en.ReadyStart=After installing: if DelphiLSP is the Code Insight provider in Delphi (default), dpcc stays off at first. Turn it on under Tools > Options > Third Party > dpcc (main switch, OK, restart Delphi).

[Messages]
de.WelcomeLabel2=%n[name/ver] wird auf Ihrem Computer installiert (nur für den aktuellen Benutzer, ohne Administratorrechte).%n%nDieses Setup baut keine Netzwerkverbindungen auf: kein Update-Check, keine Telemetrie, kein Download.
en.WelcomeLabel2=%nThis will install [name/ver] on your computer (current user only, no administrator rights).%n%nThis setup never opens network connections: no update check, no telemetry, no download.

[Types]
Name: "full";   Description: "{cm:TypeFull}"
Name: "custom"; Description: "{cm:TypeCustom}"; Flags: iscustom

[Components]
; Check: entscheidet, ob der Eintrag ueberhaupt ERSCHEINT. Eine nicht
; installierte IDE steht damit gar nicht erst zur Auswahl.
; disablenouninstallwarning: Innos Warnung "wird nicht deinstalliert" waere
; hier falsch, CurStepChanged entfernt Abgewaehltes restlos.
Name: "d12"; Description: "{cm:CompD12}"; Types: full custom; \
  Flags: disablenouninstallwarning; Check: IsDelphi12Installed
Name: "d13"; Description: "{cm:CompD13}"; Types: full custom; \
  Flags: disablenouninstallwarning; Check: IsDelphi13Installed

[Files]
; Acht BPLs je Version, Components statt Check: nur schreiben, wenn die IDE
; wirklich da und gewaehlt ist. Bewusst einzeln aufgezaehlt, keine Wildcard:
; im Ausgabeordner liegen auch .map/.drc, Protokolle und Sicherungskopien.
; --- Delphi 12 (BDS 23.0) -----------------------------------------------------
Source: "{#DpccBplSourceDirD12}\dpcc.Text{#DpccSuffixD12}.bpl";    DestDir: "{app}\bpl\d12"; Flags: ignoreversion; Components: d12
Source: "{#DpccBplSourceDirD12}\dpcc.WinBase{#DpccSuffixD12}.bpl"; DestDir: "{app}\bpl\d12"; Flags: ignoreversion; Components: d12
Source: "{#DpccBplSourceDirD12}\dpcc.Common{#DpccSuffixD12}.bpl";  DestDir: "{app}\bpl\d12"; Flags: ignoreversion; Components: d12
Source: "{#DpccBplSourceDirD12}\dpcc.Windows{#DpccSuffixD12}.bpl"; DestDir: "{app}\bpl\d12"; Flags: ignoreversion; Components: d12
Source: "{#DpccBplSourceDirD12}\dpcc.Server{#DpccSuffixD12}.bpl";  DestDir: "{app}\bpl\d12"; Flags: ignoreversion; Components: d12
Source: "{#DpccBplSourceDirD12}\dpcc.Core{#DpccSuffixD12}.bpl";    DestDir: "{app}\bpl\d12"; Flags: ignoreversion; Components: d12
Source: "{#DpccBplSourceDirD12}\dpcc.UI{#DpccSuffixD12}.bpl";      DestDir: "{app}\bpl\d12"; Flags: ignoreversion; Components: d12
Source: "{#DpccBplSourceDirD12}\{#DpccIdeBplD12}";                 DestDir: "{app}\bpl\d12"; Flags: ignoreversion; Components: d12

; --- Delphi 13 (BDS 37.0) -----------------------------------------------------
Source: "{#DpccBplSourceDirD13}\dpcc.Text{#DpccSuffixD13}.bpl";    DestDir: "{app}\bpl\d13"; Flags: ignoreversion; Components: d13
Source: "{#DpccBplSourceDirD13}\dpcc.WinBase{#DpccSuffixD13}.bpl"; DestDir: "{app}\bpl\d13"; Flags: ignoreversion; Components: d13
Source: "{#DpccBplSourceDirD13}\dpcc.Common{#DpccSuffixD13}.bpl";  DestDir: "{app}\bpl\d13"; Flags: ignoreversion; Components: d13
Source: "{#DpccBplSourceDirD13}\dpcc.Windows{#DpccSuffixD13}.bpl"; DestDir: "{app}\bpl\d13"; Flags: ignoreversion; Components: d13
Source: "{#DpccBplSourceDirD13}\dpcc.Server{#DpccSuffixD13}.bpl";  DestDir: "{app}\bpl\d13"; Flags: ignoreversion; Components: d13
Source: "{#DpccBplSourceDirD13}\dpcc.Core{#DpccSuffixD13}.bpl";    DestDir: "{app}\bpl\d13"; Flags: ignoreversion; Components: d13
Source: "{#DpccBplSourceDirD13}\dpcc.UI{#DpccSuffixD13}.bpl";      DestDir: "{app}\bpl\d13"; Flags: ignoreversion; Components: d13
Source: "{#DpccBplSourceDirD13}\{#DpccIdeBplD13}";                 DestDir: "{app}\bpl\d13"; Flags: ignoreversion; Components: d13

[UninstallDelete]
; Inno entfernt die installierten Dateien selbst. Die bpl-Ordner koennen aber
; Reste tragen: das Diagnoseprotokoll dpcc.IDE.Expert<suffix>.log, das dpcc
; neben das Plugin schreibt, oder eine BPL aus einem frueheren Lauf. Ohne
; diese Zeilen bliebe {app} als Geruest stehen.
Type: filesandordirs; Name: "{app}\bpl\d12"
Type: filesandordirs; Name: "{app}\bpl\d13"
Type: dirifempty;     Name: "{app}\bpl"

[InstallDelete]
; Fruehere Setups legten den Startmenue-Eintrag unter "dpcc" an. Beim
; Drueberinstallieren die alte Verknuepfung entfernen, sonst stuenden zwei
; Eintraege zum Deinstaller im Startmenue; der Ordner nur, wenn er leer ist.
Type: files;      Name: "{userprograms}\dpcc\Uninstall dpcc (IDE-Plugin).lnk"
Type: dirifempty; Name: "{userprograms}\dpcc"

[Icons]
; Sichtbarer Weg zum Deinstaller: ein IDE-Plugin hat keine startbare EXE und
; damit keinen natuerlichen Fundort. {userprograms}: per-user, kein Admin.
Name: "{userprograms}\Delphi Pascal Code Completion\{cm:UninstallShortcut}"; Filename: "{uninstallexe}"

[Registry]
; HKCU-Registrierung, je Version nur dpcc.IDE.Base<suffix>.bpl. Die sieben
; Laufzeitpakete gehoeren NIE hierher ({$RUNONLY}), sie findet die IDE ueber
; den PATH-Override, den CurStepChanged setzt.
; Wertname = voller BPL-Pfad, Wertdaten = Beschreibung (NIE leer!).
; uninsdeletevalue: Inno deinstalliert in umgekehrter Installationsreihenfolge,
; die Registry-Werte verschwinden also VOR den Dateien; zusaetzlich raeumt
; CurUninstallStepChanged (usUninstall).
Root: HKCU; Subkey: "{#KnownPackages23}"; ValueType: string; \
  ValueName: "{app}\bpl\d12\{#DpccIdeBplD12}"; \
  ValueData: "{#DpccPackageDescription}"; \
  Flags: uninsdeletevalue; Components: d12
Root: HKCU; Subkey: "{#KnownPackages37}"; ValueType: string; \
  ValueName: "{app}\bpl\d13\{#DpccIdeBplD13}"; \
  ValueData: "{#DpccPackageDescription}"; \
  Flags: uninsdeletevalue; Components: d13

[Code]
// ---------------------------------------------------------------------------
// IDE-Check, Koexistenz-Check gegen eigene Baus, Disabled-Packages-
// Bereinigung, IDE-PATH-Override, Abwahl = Entfernen, Uninstall-Reihenfolge,
// Warnung vor dem Deinstallieren, solange dpcc Code-Insight-Anbieter ist.
// KEINERLEI Netzwerkzugriff.
// ---------------------------------------------------------------------------

const
  KNOWN_PACKAGES_23    = 'Software\Embarcadero\BDS\23.0\Known Packages';
  DISABLED_PACKAGES_23 = 'Software\Embarcadero\BDS\23.0\Disabled Packages';
  ENV_VARS_23          = 'Software\Embarcadero\BDS\23.0\Environment Variables';
  PASCAL_OPTIONS_23    = 'Software\Embarcadero\BDS\23.0\Editor\Source Options\Borland.EditOptions.Pascal';
  KNOWN_PACKAGES_37    = 'Software\Embarcadero\BDS\37.0\Known Packages';
  DISABLED_PACKAGES_37 = 'Software\Embarcadero\BDS\37.0\Disabled Packages';
  ENV_VARS_37          = 'Software\Embarcadero\BDS\37.0\Environment Variables';
  PASCAL_OPTIONS_37    = 'Software\Embarcadero\BDS\37.0\Editor\Source Options\Borland.EditOptions.Pascal';
  SUFFIX_D12           = '{#DpccSuffixD12}';
  SUFFIX_D13           = '{#DpccSuffixD13}';
  // Wert "Insight Manager", wenn dpcc der Code-Insight-Anbieter fuer Delphi ist.
  DPCC_INSIGHT_MANAGER = 'dpcc.CodeInsight';

// Laeuft eine Delphi-IDE? Erkennung ueber das IDE-Hauptfenster (Klasse
// TAppBuilder) - bewusst ohne Prozess-APIs, bleibt lowest-privilege.
// Unterscheidet nicht zwischen BDS-Versionen; das passt, das Setup fasst
// beide an.
function IsDelphiIdeRunning: Boolean;
begin
  Result := FindWindowByClassName('TAppBuilder') <> 0;
end;

// Wurzelverzeichnis einer BDS-Version, oder '' wenn sie nicht da ist.
//   1. HKCU\Software\Embarcadero\BDS\<v>\RootDir - existiert, sobald die IDE
//      fuer diesen Benutzer einmal gestartet wurde.
//   2. HKLM\Software\Embarcadero\BDS\<v>\RootDir - der Installationseintrag
//      (32-bit-Setup-Prozess -> WOW6432Node-Sicht passt zur 32-bit-IDE).
function BdsRootDir(const Version: string): string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER,
       'Software\Embarcadero\BDS\' + Version, 'RootDir', Result) then
    if not RegQueryStringValue(HKEY_LOCAL_MACHINE,
         'Software\Embarcadero\BDS\' + Version, 'RootDir', Result) then
      Result := '';
end;

// Zaehlt nur mit real vorhandener bin\bds.exe - ein Registry-Leichnam nach
// einer Deinstallation von Delphi zaehlt nicht.
function IsBdsInstalled(const Version: string): Boolean;
var
  RootDir: string;
begin
  RootDir := BdsRootDir(Version);
  Result := (RootDir <> '')
        and FileExists(AddBackslash(RootDir) + 'bin\bds.exe');
end;

function IsDelphi12Installed: Boolean;
begin
  Result := IsBdsInstalled('23.0');
end;

function IsDelphi13Installed: Boolean;
begin
  Result := IsBdsInstalled('37.0');
end;

function IsAnySupportedIdeInstalled: Boolean;
begin
  Result := IsDelphi12Installed or IsDelphi13Installed;
end;

// AStamm + Versions-Ziffern + .bpl? Trifft dpcc.UI.bpl, dpcc.UI290.bpl und
// dpcc.UI370.bpl, aber kein fremdes dpcc.UITools.bpl.
function IsPaketMitSuffix(const FileName, AStamm: string): Boolean;
var
  Rest: string;
  I: Integer;
begin
  Result := False;
  if Length(FileName) < Length(AStamm) + 4 then
    Exit;
  if CompareText(Copy(FileName, 1, Length(AStamm)), AStamm) <> 0 then
    Exit;
  if CompareText(Copy(FileName, Length(FileName) - 3, 4), '.bpl') <> 0 then
    Exit;
  Rest := Copy(FileName, Length(AStamm) + 1,
    Length(FileName) - Length(AStamm) - 4);
  for I := 1 to Length(Rest) do
    if (Rest[I] < '0') or (Rest[I] > '9') then
      Exit;
  Result := True;
end;

// Gehoert der BPL-Dateiname zur dpcc-Familie? Die acht Packages mit oder
// ohne Versionssuffix (aeltere Staende bauten die Laufzeitpakete ohne), dazu
// dpcc.IDE.Expert, der fruehere Name des Plugins. Jede Registrierung dieser
// Familie ausserhalb des Installationsordners ist eine Koexistenz-Gefahr:
// dieselben Units in zwei geladenen Packages lassen die IDE beim Start
// scheitern.
function IsDpccFamilyBpl(const FileName: string): Boolean;
begin
  Result := IsPaketMitSuffix(FileName, 'dpcc.Text')
    or IsPaketMitSuffix(FileName, 'dpcc.WinBase')
    or IsPaketMitSuffix(FileName, 'dpcc.Common')
    or IsPaketMitSuffix(FileName, 'dpcc.Windows')
    or IsPaketMitSuffix(FileName, 'dpcc.Server')
    or IsPaketMitSuffix(FileName, 'dpcc.Core')
    or IsPaketMitSuffix(FileName, 'dpcc.UI')
    or IsPaketMitSuffix(FileName, 'dpcc.IDE.Base')
    or IsPaketMitSuffix(FileName, 'dpcc.IDE.Expert');
end;

// Voller Installationspfad einer Version bzw. einer BPL darin.
function VersionsOrdner(const AOrdner: string): string;
begin
  Result := ExpandConstant('{app}\bpl\') + AOrdner;
end;

function BplPfad(const AOrdner, ABpl: string): string;
begin
  Result := AddBackslash(VersionsOrdner(AOrdner)) + ABpl;
end;

function IdeBplName(const ASuffix: string): string;
begin
  Result := 'dpcc.IDE.Base' + ASuffix + '.bpl';
end;

// Fremde Registrierungen der dpcc-Familie in EINEM Registry-Zweig sammeln:
// Wertnamen (= volle BPL-Pfade), die auf einen Familiennamen enden, aber NICHT
// auf die installierte Plugin-BPL dieser Version zeigen. Typisch ist der
// eigene Bau aus Output\Win32\<Konfiguration>\Bpl.
procedure CollectForeignPluginEntries(const AKey, AOrdner, ASuffix: string;
  Entries: TStringList);
var
  Names: TArrayOfString;
  I: Integer;
  N: string;
begin
  if RegGetValueNames(HKEY_CURRENT_USER, AKey, Names) then
    for I := 0 to GetArrayLength(Names) - 1 do
    begin
      N := Names[I];
      if IsDpccFamilyBpl(ExtractFileName(N)) and
         (CompareText(N, BplPfad(AOrdner, IdeBplName(ASuffix))) <> 0) then
        Entries.Add(N);
    end;
end;

// ---------------------------------------------------------------------------
// IDE-PATH-Override. Der Wert ist GETEILT, InterBase steht dort z. B. mit
// ...\IDE_spoof;$(PATH). Deshalb nur das eigene Segment bewegen und alles
// andere Zeichen fuer Zeichen stehen lassen.
// ---------------------------------------------------------------------------

function IstGleichesSegment(const A, B: string): Boolean;
begin
  Result := AnsiLowercase(RemoveBackslash(Trim(A)))
          = AnsiLowercase(RemoveBackslash(Trim(B)));
end;

function OverrideOhneSegment(const AWert, ASegment: string): string;
var
  Teile: TArrayOfString;
  I, Behalten: Integer;
begin
  Result := '';
  Behalten := 0;
  Teile := StringSplit(AWert, [';'], stAll);
  for I := 0 to GetArrayLength(Teile) - 1 do
    if not IstGleichesSegment(Teile[I], ASegment) then
    begin
      if Behalten > 0 then
        Result := Result + ';';
      Result := Result + Teile[I];
      Behalten := Behalten + 1;
    end;
end;

// Immer entnehmen und vorn einsetzen: das haelt den Wert bei Doppelinstallation
// stabil und holt das Segment vor einen Entwickler-Ordner, falls einer drin ist.
function OverrideMitSegment(const AWert, ASegment: string): string;
begin
  Result := OverrideOhneSegment(AWert, ASegment);
  // Ohne $(PATH) verloere die IDE ihren geerbten Suchpfad.
  if Trim(Result) = '' then
    Result := '$(PATH)';
  Result := ASegment + ';' + Result;
end;

// Bleibt nach dem Entfernen nur das, was das Setup selbst angelegt haette,
// ist der Ausgangszustand "kein Wert" wiederhergestellt.
function IstLeererOverride(const AWert: string): Boolean;
begin
  Result := (Trim(AWert) = '') or (CompareText(Trim(AWert), '$(PATH)') = 0);
end;

// RegWriteStringValue erhaelt REG_EXPAND_SZ (Inno-Hilfe), RegQueryStringValue
// liest beide Typen; der Werttyp eines vorhandenen Werts bleibt also.
// Fehlt der HKCU-Wert, gilt die Vorlage der Delphi-Installation aus HKLM
// (32-bit-Sicht) als Ausgangswert. Sonst gingen ihre Segmente verloren, denn
// der neue HKCU-Wert verdeckt sie.
function SetzeOverrideSegment(const AEnvKey, AOrdner: string): Boolean;
var
  Alt, Neu: string;
  Vorhanden: Boolean;
begin
  Vorhanden := RegQueryStringValue(HKEY_CURRENT_USER, AEnvKey, 'PATH', Alt);
  if not Vorhanden then
    if not RegQueryStringValue(HKEY_LOCAL_MACHINE_32, AEnvKey, 'PATH', Alt) then
      Alt := '';
  Neu := OverrideMitSegment(Alt, VersionsOrdner(AOrdner));
  Result := (Vorhanden and (Neu = Alt))
    or RegWriteStringValue(HKEY_CURRENT_USER, AEnvKey, 'PATH', Neu);
end;

// Eine aus HKLM entstandene HKCU-Kopie bleibt ohne unser Segment stehen: ob
// sie vorher schon da war, ist nicht unterscheidbar, und sie wirkt wie die
// Vorlage.
procedure EntferneOverrideSegment(const AEnvKey, AOrdner: string);
var
  Alt, Neu: string;
begin
  if not RegQueryStringValue(HKEY_CURRENT_USER, AEnvKey, 'PATH', Alt) then
    Exit;
  Neu := OverrideOhneSegment(Alt, VersionsOrdner(AOrdner));
  if Neu = Alt then
    Exit;     // nicht unser Segment drin -> der Wert geht uns nichts an
  if IstLeererOverride(Neu) then
  begin
    RegDeleteValue(HKEY_CURRENT_USER, AEnvKey, 'PATH');
    RegDeleteKeyIfEmpty(HKEY_CURRENT_USER, AEnvKey);
  end
  else
    RegWriteStringValue(HKEY_CURRENT_USER, AEnvKey, 'PATH', Neu);
end;

// Ein Dialog hielte einen Silent-Lauf an, bis jemand klickt; dort genuegt das Log.
procedure MeldeFehler(const AText: string; const ASilent: Boolean);
begin
  Log(AText);
  if not ASilent then
    MsgBox(AText, mbError, MB_OK);
end;

function InitializeSetup: Boolean;
begin
  Result := True;
  // Erst "ist eine unterstuetzte IDE da?", dann "laeuft sie?" - die
  // Nicht-installiert-Meldung ist die praezisere von beiden.
  if not IsAnySupportedIdeInstalled then
  begin
    MeldeFehler(CustomMessage('NoDelphi'), WizardSilent);
    Result := False;
    Exit;
  end;
  if IsDelphiIdeRunning then
  begin
    MeldeFehler(CustomMessage('IdeRunning'), WizardSilent);
    Result := False;
  end;
end;

// Zweiter Blick unmittelbar vor dem Schreiben: eine waehrend des Wizards
// gestartete IDE haelt die BPLs fest. Der Text stoppt Setup auf der
// Vorbereiten-Seite. Silent zeigt Inno ihn als Dialog, deshalb faengt
// NextButtonClick diesen Fall vorher ab.
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if IsDelphiIdeRunning then
    Result := CustomMessage('IdeRunning');
end;

// ---------------------------------------------------------------------------
// Community-Buttons unten links. ShellExecAsOriginalUser: oeffnet den Browser
// im Nutzerkontext - reiner Klick-Link, das Setup baut keine Verbindung auf.
// ---------------------------------------------------------------------------

procedure OpenCommunityUrl(const Url: string);
var
  ErrCode: Integer;
begin
  ShellExecAsOriginalUser('open', Url, '', '', SW_SHOWNORMAL, ewNoWait, ErrCode);
end;

procedure StarButtonClick(Sender: TObject);
begin
  OpenCommunityUrl('{#DpccGitHubUrl}');
end;

#if DpccDonateUrl != ""
procedure DonateButtonClick(Sender: TObject);
begin
  OpenCommunityUrl('{#DpccDonateUrl}');
end;
#endif

// "Ready to Install"-Seite: Versions-Uebersicht, Selbstbau-Hinweis, PATH-
// und Start-Hinweis VOR den Standard-Infos (Zielordner, Auswahl).
// Darstellung: TRichEditViewer ueber dem ReadyMemo, damit die INSTALLIERBAREN
// Versionen FETT stehen koennen (Memo kann kein Bold); das Plain-Memo bleibt
// als Fallback gefuellt.
var
  GReadyRich   : TRichEditViewer;
  GMemoDirInfo  : string;
  GMemoCompInfo : string;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo,
  MemoTasksInfo: String): String;
begin
  GMemoDirInfo  := MemoDirInfo;
  GMemoCompInfo := MemoComponentsInfo;
  Result := CustomMessage('ReadyHead') + NewLine + NewLine
          + CustomMessage('ReadyYes1') + NewLine
          + CustomMessage('ReadyYes2') + NewLine
          + CustomMessage('ReadyNo1') + NewLine
          + CustomMessage('ReadyNo2') + NewLine + NewLine
          + CustomMessage('ReadyNote') + NewLine
          + '{#DpccGitHubUrl}' + NewLine + NewLine
          + CustomMessage('ReadyPath') + NewLine + NewLine
          + CustomMessage('ReadyStart') + NewLine;
  if MemoComponentsInfo <> '' then
    Result := Result + NewLine + MemoComponentsInfo + NewLine;
  if MemoDirInfo <> '' then
    Result := Result + NewLine + MemoDirInfo + NewLine;
end;

// RTF-Sonderzeichen entschaerfen (Backslash/geschweifte Klammern - der
// Zielordner-Block enthaelt Windows-Pfade). Zeichen jenseits von ASCII
// (Umlaute der Texte, Benutzernamen im Zielordner) gehen als \uN in den
// RTF-Text: RTFText ist ein AnsiString, ohne das haenge ihre Darstellung an
// der Codepage des Rechners.
function RtfEscape(const S: string): string;
var
  I, Code: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    Code := Ord(S[I]);
    if (S[I] = '\') or (S[I] = '{') or (S[I] = '}') then
      Result := Result + '\' + S[I]
    else if Code > 127 then
    begin
      // \uN erwartet eine vorzeichenbehaftete 16-Bit-Zahl; "?" ist der Ersatz
      // fuer Leser ohne Unicode.
      if Code > 32767 then
        Code := Code - 65536;
      Result := Result + '\u' + IntToStr(Code) + '?';
    end
    else
      Result := Result + S[I];
  end;
end;

// Zeilenumbrueche des Memo-Texts (#13#10) in RTF-\par wandeln.
function RtfPar(const S: string): string;
begin
  Result := RtfEscape(S);
  StringChangeEx(Result, #13#10, '\par ', True);
  StringChangeEx(Result, #13, '\par ', True);
  StringChangeEx(Result, #10, '\par ', True);
end;

function BuildReadyRtf: string;
begin
  // \ansicpg1252: der Zielordner-Block kommt aus der Sprachdatei und darf
  // Umlaute enthalten; Segoe UI \fs18 = 9pt wie die Wizard-Schrift.
  Result :=
    '{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0 Segoe UI;}}\f0\fs18 '
    + RtfPar(CustomMessage('ReadyHead')) + '\par \par '
    + '{\b ' + RtfPar(CustomMessage('ReadyYes1')) + '}\par '
    + '{\b ' + RtfPar(CustomMessage('ReadyYes2')) + '}\par '
    + RtfPar(CustomMessage('ReadyNo1')) + '\par '
    + RtfPar(CustomMessage('ReadyNo2')) + '\par \par '
    + RtfPar(CustomMessage('ReadyNote')) + '\par '
    + RtfPar('{#DpccGitHubUrl}') + '\par \par '
    + RtfPar(CustomMessage('ReadyPath')) + '\par \par '
    + RtfPar(CustomMessage('ReadyStart')) + '\par ';
  if GMemoCompInfo <> '' then
    Result := Result + '\par ' + RtfPar(GMemoCompInfo) + '\par ';
  if GMemoDirInfo <> '' then
    Result := Result + '\par ' + RtfPar(GMemoDirInfo) + '\par ';
  Result := Result + '}';
end;

// Auf der Komponentenseite nicht weiterlassen, wenn nichts angehakt ist.
// Ohne das liefe das Setup durch und installierte kein einziges Plugin.
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  // Silent-Gegenstueck zu PrepareToInstall: ein False beendet Setup ohne Dialog.
  if (CurPageID = wpReady) and WizardSilent and IsDelphiIdeRunning then
  begin
    MeldeFehler(CustomMessage('IdeRunning'), True);
    Result := False;
    Exit;
  end;
  if CurPageID <> wpSelectComponents then
    Exit;
  if not (WizardIsComponentSelected('d12')
       or WizardIsComponentSelected('d13')) then
  begin
    MeldeFehler(CustomMessage('NoComponent'), WizardSilent);
    Result := False;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if GReadyRich = nil then Exit;
  if CurPageID = wpReady then
  begin
    GReadyRich.RTFText := BuildReadyRtf;
    GReadyRich.Visible := True;
    WizardForm.ReadyMemo.Visible := False;
  end
  else
    GReadyRich.Visible := False;
end;

procedure InitializeWizard;
var
  Btn: TNewButton;
  NextLeft: Integer;
begin
  // Ready-Memo: Inno-Default ist WordWrap AUS + horizontaler Scrollbalken -
  // die Hinweis-Saetze liefen damit aus dem Bild. Umbruch an, nur vertikal
  // scrollen (gilt fuer das Fallback-Memo; die Anzeige uebernimmt der
  // RichViewer).
  WizardForm.ReadyMemo.WordWrap   := True;
  WizardForm.ReadyMemo.ScrollBars := ssVertical;

  // RichEdit-Viewer anstelle des ReadyMemo, etwas nach unten geschoben (das
  // zweizeilige "Click Install..."-Label wuerde sonst angeschnitten) und
  // unten verkuerzt.
  GReadyRich := TRichEditViewer.Create(WizardForm);
  GReadyRich.Parent := WizardForm.ReadyMemo.Parent;
  GReadyRich.SetBounds(WizardForm.ReadyMemo.Left,
    WizardForm.ReadyMemo.Top + ScaleY(16),
    WizardForm.ReadyMemo.Width,
    WizardForm.ReadyMemo.Height - ScaleY(48));
  GReadyRich.Anchors    := WizardForm.ReadyMemo.Anchors;
  GReadyRich.ReadOnly   := True;
  GReadyRich.ScrollBars := ssVertical;
  GReadyRich.UseRichEdit := True;
  GReadyRich.Visible    := False;

  NextLeft := ScaleX(12);

#if DpccDonateUrl != ""
  Btn := TNewButton.Create(WizardForm);
  Btn.Parent  := WizardForm;
  Btn.Left    := NextLeft;
  Btn.Top     := WizardForm.CancelButton.Top;
  Btn.Width   := ScaleX(100);
  Btn.Height  := WizardForm.CancelButton.Height;
  Btn.Caption := CustomMessage('DonateBtn');
  Btn.OnClick := @DonateButtonClick;
  NextLeft := Btn.Left + Btn.Width + ScaleX(8);
#endif

  Btn := TNewButton.Create(WizardForm);
  Btn.Parent  := WizardForm;
  Btn.Left    := NextLeft;
  Btn.Top     := WizardForm.CancelButton.Top;
  Btn.Width   := ScaleX(110);
  Btn.Height  := WizardForm.CancelButton.Height;
  Btn.Caption := CustomMessage('StarBtn');
  Btn.OnClick := @StarButtonClick;
end;

// Meldung im Wizard; ein Silent-Lauf darf an keinem Dialog haengen bleiben,
// dort steht der Text nur im Log.
procedure Hinweis(const AText: string);
begin
  Log(AText);
  if not WizardSilent then
    MsgBox(AText, mbInformation, MB_OK);
end;

// Fremde dpcc-Registrierungen eines Zweigs entfernen und den Nutzer darueber
// unterrichten. Stillschweigend loeschen waere falsch: es ist SEINE
// Registrierung, die verschwindet.
procedure RaeumeFremdeRegistrierungen(const AKey, AOrdner, ASuffix: string);
var
  Foreign: TStringList;
  I: Integer;
begin
  Foreign := TStringList.Create;
  try
    CollectForeignPluginEntries(AKey, AOrdner, ASuffix, Foreign);
    if Foreign.Count > 0 then
      Hinweis(FmtMessage(CustomMessage('DevBplWarn'), [Foreign.Text, AKey]));
    for I := 0 to Foreign.Count - 1 do
      RegDeleteValue(HKEY_CURRENT_USER, AKey, Foreign[I]);
  finally
    Foreign.Free;
  end;
end;

procedure EntferneDatei(const APfad: string);
begin
  if FileExists(APfad) then
    DeleteFile(APfad);
end;

procedure EntferneRegistrierung(const AOrdner, ASuffix, AKnownKey, ADisabledKey: string);
begin
  RegDeleteValue(HKEY_CURRENT_USER, AKnownKey, BplPfad(AOrdner, IdeBplName(ASuffix)));
  RegDeleteValue(HKEY_CURRENT_USER, ADisabledKey, BplPfad(AOrdner, IdeBplName(ASuffix)));
end;

// Eine Version restlos entfernen: Registrierung, Override-Segment, Dateien,
// Ordner.
//
// WOZU: Inno installiert eine abgewaehlte Komponente nicht - es entfernt sie
// aber auch NICHT, wenn sie aus einem frueheren Lauf noch daliegt. Wer das
// Setup erneut startet und eine Delphi-Version aushakt, haette sonst weiter
// BPLs und Registry-Eintrag, und die IDE wuerde dpcc weiter laden.
procedure EntferneVariante(const AOrdner, ASuffix, AKnownKey, ADisabledKey,
  AEnvKey: string);
begin
  // Registry zuerst, Dateien danach - dieselbe Reihenfolge wie bei der
  // Deinstallation. Eine registrierte, aber fehlende BPL laesst die IDE bei
  // jedem Start scheitern.
  EntferneRegistrierung(AOrdner, ASuffix, AKnownKey, ADisabledKey);
  EntferneOverrideSegment(AEnvKey, AOrdner);
  EntferneDatei(BplPfad(AOrdner, IdeBplName(ASuffix)));
  EntferneDatei(BplPfad(AOrdner, 'dpcc.UI' + ASuffix + '.bpl'));
  EntferneDatei(BplPfad(AOrdner, 'dpcc.Core' + ASuffix + '.bpl'));
  EntferneDatei(BplPfad(AOrdner, 'dpcc.Server' + ASuffix + '.bpl'));
  EntferneDatei(BplPfad(AOrdner, 'dpcc.Windows' + ASuffix + '.bpl'));
  EntferneDatei(BplPfad(AOrdner, 'dpcc.Common' + ASuffix + '.bpl'));
  EntferneDatei(BplPfad(AOrdner, 'dpcc.WinBase' + ASuffix + '.bpl'));
  EntferneDatei(BplPfad(AOrdner, 'dpcc.Text' + ASuffix + '.bpl'));
  // Diagnoseprotokoll, das dpcc neben das Plugin schreibt (falls es an war).
  EntferneDatei(BplPfad(AOrdner, 'dpcc.IDE.Expert' + ASuffix + '.log'));
  RemoveDir(VersionsOrdner(AOrdner));   // wirkt nur, wenn leer - genau so gewollt
end;

// Eine angehakte Version fertigstellen; Dateien und Known-Packages-Wert hat
// Inno zu diesem Zeitpunkt schon geschrieben.
procedure RichteVersionEin(const AOrdner, ASuffix, AKnownKey, ADisabledKey,
  AEnvKey: string);
begin
  // Override VOR jeder Bereinigung: ohne ihn laedt der Paketsatz nicht, und
  // eine Entwickler-Registrierung waere dann der einzige lauffaehige Stand.
  if not SetzeOverrideSegment(AEnvKey, AOrdner) then
  begin
    MeldeFehler(FmtMessage(CustomMessage('OverrideFail'), [AEnvKey]), WizardSilent);
    Exit;
  end;

  // Koexistenz-Check, aber NUR fuer angehakte Versionen. Einen Registry-
  // Zweig, den das Setup gar nicht bespielt, fasst es nicht an - dort darf
  // der Nutzer seinen eigenen Bau behalten.
  RaeumeFremdeRegistrierungen(AKnownKey, AOrdner, ASuffix);

  // Disabled-Packages-Bereinigung: hatte der Nutzer das Paket frueher per
  // "Package kann nicht geladen werden -> Nein" deaktiviert, bliebe der
  // Eintrag bestehen und wuerde die frische Installation stumm blockieren.
  RegDeleteValue(HKEY_CURRENT_USER, ADisabledKey, BplPfad(AOrdner, IdeBplName(ASuffix)));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep <> ssPostInstall then
    Exit;

  if WizardIsComponentSelected('d12') then
    RichteVersionEin('d12', SUFFIX_D12, KNOWN_PACKAGES_23, DISABLED_PACKAGES_23, ENV_VARS_23)
  else
    EntferneVariante('d12', SUFFIX_D12, KNOWN_PACKAGES_23, DISABLED_PACKAGES_23, ENV_VARS_23);

  if WizardIsComponentSelected('d13') then
    RichteVersionEin('d13', SUFFIX_D13, KNOWN_PACKAGES_37, DISABLED_PACKAGES_37, ENV_VARS_37)
  else
    EntferneVariante('d13', SUFFIX_D13, KNOWN_PACKAGES_37, DISABLED_PACKAGES_37, ENV_VARS_37);
end;

// Ist dpcc in dieser Version installiert (unser Known-Packages-Wert) UND noch
// Code-Insight-Anbieter fuer Delphi? Nur lesen: den Anbieter samt den
// Schaltern, die dpcc gesetzt hat, stellt dpcc selbst zurueck (Hauptschalter
// aus); ein halbes Zuruecksetzen durch den Deinstaller waere schlechter.
function IstNochAnbieter(const AOrdner, ASuffix, AKnownKey, AOptionsKey: string): Boolean;
var
  Wert: string;
begin
  Result := RegValueExists(HKEY_CURRENT_USER, AKnownKey, BplPfad(AOrdner, IdeBplName(ASuffix)))
    and RegQueryStringValue(HKEY_CURRENT_USER, AOptionsKey, 'Insight Manager', Wert)
    and (CompareText(Trim(Wert), DPCC_INSIGHT_MANAGER) = 0);
end;

function InitializeUninstall: Boolean;
var
  Liste: string;
begin
  Result := True;
  if IsDelphiIdeRunning then
  begin
    MeldeFehler(CustomMessage('IdeRunning'), UninstallSilent);
    Result := False;
    Exit;
  end;

  Liste := '';
  if IstNochAnbieter('d12', SUFFIX_D12, KNOWN_PACKAGES_23, PASCAL_OPTIONS_23) then
    Liste := Liste + 'Delphi 12 (BDS 23.0)' + #13#10;
  if IstNochAnbieter('d13', SUFFIX_D13, KNOWN_PACKAGES_37, PASCAL_OPTIONS_37) then
    Liste := Liste + 'Delphi 13 (BDS 37.0)' + #13#10;
  if Liste <> '' then
  begin
    // Silent: nur ins Log, der Lauf geht weiter (kein Dialog haelt ihn an).
    Log(FmtMessage(CustomMessage('ProviderStill'), [Liste]));
    if not UninstallSilent then
      if MsgBox(FmtMessage(CustomMessage('ProviderStill'), [Liste]),
           mbConfirmation, MB_YESNO or MB_DEFBUTTON2) <> IDYES then
        Result := False;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  // usUninstall feuert VOR dem Loeschen der Dateien -> hier die Registry-
  // Werte explizit raeumen ("Registry vor Dateien"), auch wenn
  // uninsdeletevalue dieselbe Reihenfolge schon garantiert. Beide Versionen,
  // unabhaengig von der Auswahl - loeschen, was nicht existiert, ist folgenlos.
  // Einstellungen, Daten, Cache und Protokoll von dpcc bleiben.
  if CurUninstallStep = usUninstall then
  begin
    EntferneOverrideSegment(ENV_VARS_23, 'd12');
    EntferneOverrideSegment(ENV_VARS_37, 'd13');
    EntferneRegistrierung('d12', SUFFIX_D12, KNOWN_PACKAGES_23, DISABLED_PACKAGES_23);
    EntferneRegistrierung('d13', SUFFIX_D13, KNOWN_PACKAGES_37, DISABLED_PACKAGES_37);
  end;
end;
