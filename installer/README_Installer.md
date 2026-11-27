# Installer – Bauanleitung (Delphi 12 und Delphi 13)

Das Setup `dpccSetup-<Version>.exe` installiert dpcc für den aktuellen Benutzer in Delphi 12 und/oder Delphi 13,
ohne Administratorrechte. Technik: Inno Setup 6, Skript `installer\dpccSetup.iss`. Es kompiliert nichts, sondern
bündelt die in der IDE gebauten BPLs und, als abwählbare Komponente, den LSP-Server `dpcc.LspServer.exe` in 32 und
64 Bit.

## 0. Unterstützte Delphi-Versionen

BPLs sind an die Compiler-Version gebunden: eine BPL mit der Endung `290` lädt nur in Delphi 12, eine mit `370`
nur in Delphi 13. Die Tabelle entspricht der Übersicht auf der Seite „Bereit zur Installation“ des Setups; bei
Änderungen beide Stellen pflegen.

| Delphi | BDS | IDE | BPLs | Registry-Zweig (HKCU) | Setup |
|---|---|---|---|---|---|
| ≤ 11 | ≤ 22.0 | 32-Bit | – | – | **nicht unterstützt** (keine Projektgruppe) |
| 12 Athens | 23.0 | 32-Bit | acht BPLs `…290.bpl`, Ziel `{app}\bpl\d12` | `…\BDS\23.0\Known Packages` | **wird unterstützt** |
| 13 Florence | 37.0 | 32-Bit | acht BPLs `…370.bpl`, Ziel `{app}\bpl\d13` | `…\BDS\37.0\Known Packages` | **wird unterstützt** |
| 13 Florence | 37.0 | 64-Bit | – | – | **nicht unterstützt** (nur 32-Bit-IDE): dpcc baut nur Win32, die 64-Bit-IDE lädt keine Win32-BPL |

Das Setup zeigt nur die Versionen zur Auswahl, deren IDE es findet (`RootDir` unter
`HKCU` bzw. `HKLM\…\Embarcadero\BDS\<bds>` und dort eine vorhandene `bin\bds.exe`). Findet es keine, bricht es
vor der Installation ab.

## 1. Was zu bauen ist (in der IDE)

Der Kommandozeilen-Compiler ist in den Editionen Community und Starter gesperrt; gebaut wird in der IDE, wie in
[docs/de/installation.md](../docs/de/installation.md) beschrieben:

| Delphi | Gruppe | Plattform / Konfiguration | BPL-Ordner (Quelle des Setups) | ISCC-Define |
|---|---|---|---|---|
| 13 | `dpcc_d13.groupproj` | Win32 / Debug | `Output\Win32\Debug\Bpl` | `DpccBplSourceDirD13` |
| 12 | `dpcc_d12.groupproj` | Win32 / D12 | `Output\Win32\D12\Bpl` | `DpccBplSourceDirD12` |

Dazu der LSP-Server, eine EXE je Bitbreite für beide Delphi-Versionen:

| EXE | Entsteht | Ordner (Quelle des Setups) | ISCC-Define |
|---|---|---|---|
| `dpcc.LspServer.exe` 32 Bit | im Gruppenbau `dpcc_d13.groupproj` (Projekt `Application\dpcc.LspServer.dproj`, Win32 / Debug) | `Output\Win32\Debug\Bin` | `DpccLspServerDirWin32` |
| `dpcc.LspServer.exe` 64 Bit | **nicht** im Gruppenbau: in Delphi 13 `Application\dpcc.LspServer.dproj` öffnen, Zielplattform Windows 64-Bit, Konfiguration Debug, Erzeugen | `Output\Win64\Debug\Bin` | `DpccLspServerDirWin64` |

Je Version acht BPLs, alle mit `{$LIBSUFFIX AUTO}`:

| BPL | Art |
|---|---|
| `dpcc.Text`, `dpcc.WinBase`, `dpcc.Common`, `dpcc.Windows`, `dpcc.Server`, `dpcc.Core`, `dpcc.UI` | Laufzeitpakete (`{$RUNONLY}`) |
| `dpcc.Plugin` | Design-Paket (`{$DESIGNONLY}`), das Plugin; requires die sieben |

Das Setup nimmt beide Versionen und beide EXEs immer zusammen auf; vor dem Setup also beide Gruppen bauen und die
Win64-EXE.

### Warum der PATH-Eintrag nötig ist

Der Windows-Loader löst `requires` über das Verzeichnis von bds.exe, System32 und PATH auf, **nicht** im Ordner
der Plugin-BPL, und ein `{$RUNONLY}`-Paket gehört nicht in die Known Packages. Deshalb steht dort nur
`dpcc.Plugin<suffix>.bpl` (voller Pfad), und das Setup legt `{app}\bpl\<version>` vorn in den IDE-eigenen Override
`HKCU\Software\Embarcadero\BDS\<bds>\Environment Variables\PATH` – derselbe Eintrag, den `Tools\IdePath.ps1` für den
eigenen Bau setzt.

## 2. Setup bauen

Voraussetzung: **Inno Setup 6.x** (`ISCC.exe` im PATH oder im Standardordner von Inno Setup 6).

**Regelweg: `Tools\Build-Setup.ps1`** aus dem Repo-Ordner:

```powershell
powershell -NoProfile -File Tools\Build-Setup.ps1 -DryRun   # nur prüfen, nichts anlegen
powershell -NoProfile -File Tools\Build-Setup.ps1           # Setup bauen
```

Das Skript prüft vorher alles und bricht erst dann ab; angelegt ist bis dahin nichts:

- `ISCC.exe` gefunden,
- Version aus `Packages\dpcc.Text\Source\Product\dpcc.Text.Product.Version.pas` lesbar (`x.y.z`),
- je Version alle acht BPLs vorhanden, PE-Machine `014C` (Win32),
- jede BPL jünger als die neueste Quelldatei (`.pas`, `.dpk`, `.dfm`, `.inc`) ihres Packages,
- beide EXEs des LSP-Servers vorhanden: `Output\Win32\Debug\Bin\dpcc.LspServer.exe` mit PE-Machine `014C`,
  `Output\Win64\Debug\Bin\dpcc.LspServer.exe` mit `8664` (x64), jede nicht älter als ihre Quellen.

Die Win32-BPLs tragen keine VERSIONINFO (`VerInfo_IncludeVerInfo` ist für Win32 aus); ein Versionsvergleich der
BPLs entfällt deshalb. Danach ruft das Skript ISCC mit `/DDpccVersion=<x.y.z>.0`, den beiden BPL-Ordnern und den
beiden EXE-Ordnern (`/DDpccLspServerDirWin32`, `/DDpccLspServerDirWin64`) auf und legt neben dem Setup das ZIP
`installer\Output\dpcc.LspServer-<x.y.z>.zip` an:

| Eintrag im ZIP | Quelle |
|---|---|
| `win32\dpcc.LspServer.exe` | EXE aus `-LspServerDirWin32` |
| `win64\dpcc.LspServer.exe` | EXE aus `-LspServerDirWin64` |
| `LIESMICH.txt` | `installer\LspServer-LIESMICH.txt` (deutsch und englisch) |

Das ZIP ist für alle, die die EXE ohne Setup neben ein Plugin legen wollen (siehe
[Installation › LSP-Server](../docs/de/installation.md#lsp-server)).

| Parameter | Vorgabe | Bedeutung |
|---|---|---|
| `-DryRun` | aus | nur die Prüfungen, danach Ende |
| `-BplDirD12` | `Output\Win32\D12\Bpl` | anderer BPL-Ordner für Delphi 12 |
| `-BplDirD13` | `Output\Win32\Debug\Bpl` | anderer BPL-Ordner für Delphi 13 |
| `-LspServerDirWin32` | `Output\Win32\Debug\Bin` | anderer Ordner der 32-Bit-EXE |
| `-LspServerDirWin64` | `Output\Win64\Debug\Bin` | anderer Ordner der 64-Bit-EXE |
| `-OutDir` | `installer\Output` | Zielordner des Setups (steht über `Output/` in `.gitignore`) |
| `-Iscc` | PATH, dann Standardordner | voller Pfad zu `ISCC.exe` |

Hand-Compile ist ebenso möglich:

```bat
cd installer
iscc dpccSetup.iss
:: abweichende Quellordner:
iscc /DDpccBplSourceDirD12="D:\release\d12" /DDpccBplSourceDirD13="D:\release\d13" dpccSetup.iss
:: abweichende Ordner der beiden EXEs:
iscc /DDpccLspServerDirWin32="D:\release\win32" /DDpccLspServerDirWin64="D:\release\win64" dpccSetup.iss
```

Das ZIP legt nur `Tools\Build-Setup.ps1` an, nicht ISCC.

Ohne `/DDpccVersion` liest das Skript die Version beim Kompilieren selbst aus `dpcc.Text.Product.Version.pas`
(`cVersion`, mit angehängtem `.0`); eine zweite, von Hand gepflegte Versionsangabe gibt es nicht. Die vierstellige
Fassung steht im Dateinamen und in der VERSIONINFO der Setup-EXE; angezeigt wird (`AppVersion`, abgeleitet als
`DpccVersionShort`) die dreistellige, z. B. `0.1.0` statt `0.1.0.0`. Weitere Defines:
`DpccRepoRoot` (Repo-Wurzel mit abschließendem `\`, Vorgabe der Ordner über `installer`), `DpccLspServerDirWin32`
und `DpccLspServerDirWin64` (Vorgabe `Output\Win32\Debug\Bin` bzw. `Output\Win64\Debug\Bin` unter `DpccRepoRoot`)
und `DpccDonateUrl` (leer = kein Spenden-Button). Ergebnis: `installer\Output\dpccSetup-<Version>.exe`. Setup-EXEs gehören nicht ins
Repo.

## 3. Was der Installer tut

- **Per-User, nie elevated** (`PrivilegesRequired=lowest`). Dateien nach `%LOCALAPPDATA%\Programs\dpcc\`:

  | Version | Dateien nach | Known Packages (Wertname = voller Pfad, Daten `dpcc - Delphi Pascal Code Completion`) | PATH-Override |
  |---|---|---|---|
  | Delphi 12 | `bpl\d12\dpcc.*290.bpl` | `HKCU\Software\Embarcadero\BDS\23.0\Known Packages`, Wert `…\bpl\d12\dpcc.Plugin290.bpl` | `…\BDS\23.0\Environment Variables`, Wert `PATH` |
  | Delphi 13 | `bpl\d13\dpcc.*370.bpl` | `HKCU\Software\Embarcadero\BDS\37.0\Known Packages`, Wert `…\bpl\d13\dpcc.Plugin370.bpl` | `…\BDS\37.0\Environment Variables`, Wert `PATH` |
  | LSP-Server (Komponente `lspserver`) | `server\win32\dpcc.LspServer.exe`, auf 64-Bit-Windows zusätzlich `server\win64\dpcc.LspServer.exe` | – | – |

  Dazu `unins000.exe`/`unins000.dat` in `{app}`, der Eintrag unter „Apps“ von Windows und ein Startmenü-Eintrag
  `Delphi Pascal Code Completion\dpcc deinstallieren` (englisch: `Uninstall dpcc`). Die Verknüpfung
  `dpcc\Uninstall dpcc (IDE-Plugin)` früherer Setups entfernt `[InstallDelete]` beim Drüberinstallieren, den Ordner
  `dpcc` nur, wenn er dann leer ist.
- **Anzeige**: Programmname „Delphi Pascal Code Completion (dpcc)“ (Wizard und „Apps“), Herausgeber
  „dear Technologies“, Version dreistellig (`x.y.z`). Die Paketbeschreibung in den Known Packages
  entspricht `{$DESCRIPTION}` aus `dpcc.Plugin.dpk`.
- **IDE-PATH-Override**: `{app}\bpl\<version>` kommt vorn in den Wert. Er ist geteilt (InterBase trägt dort z. B.
  `…\IDE_spoof;$(PATH)`): nur das eigene Segment wird bewegt, alles andere bleibt Zeichen für Zeichen. Das Segment
  wird immer entnommen und vorn eingesetzt; eine Doppelinstallation ändert den Wert nicht, und es steht vor einem
  Entwickler-Ordner wie `…\Output\Win32\Debug\Bpl`. Fehlt der Wert in HKCU, ist die Vorlage der Delphi-Installation
  der Ausgangswert (`HKLM\SOFTWARE\WOW6432Node\Embarcadero\BDS\<bds>\Environment Variables\PATH`); HKLM selbst bleibt
  unberührt. Fehlt auch sie, entsteht `<segment>;$(PATH)`. Scheitert das Schreiben, meldet das Setup es (im
  Silent-Lauf im Log) und lässt die fremden Registrierungen dieser Version stehen.
- **Koexistenz-Check, je Version**: eine Registrierung der dpcc-Familie (die acht Packages mit oder ohne
  Versionssuffix, dazu die früheren Namen `dpcc.IDE.Base` und `dpcc.IDE.Expert`) unter anderem Pfad – typisch der eigene Bau aus dem
  Repo – wird gemeldet und aus den Known Packages entfernt; beide zusammen ließen die IDE beim Start scheitern. Der
  PATH-Eintrag des eigenen Baus bleibt stehen. Geprüft wird nur der Zweig angehakter Versionen. Wer danach wieder den
  eigenen Bau nutzt, deinstalliert das Setup und trägt den Bau neu ein
  ([Installation](../docs/de/installation.md#installieren)).
- **Update vom früheren Plugin-Namen**: Bis zur Umbenennung hieß das Plugin `dpcc.IDE.Base<suffix>.bpl`. Vor allem
  anderen entfernt das Setup je angehakter Version den Known- und Disabled-Packages-Wert
  `{app}\bpl\<version>\dpcc.IDE.Base<suffix>.bpl` und danach die alte Datei (`EntferneAltesPlugin`), ohne Hinweis –
  beides stammt von einem früheren Lauf dieses Setups. Sonst meldete Delphi ein fehlendes Package oder lüde neben dem
  neuen Plugin den alten Stand. Abwahl einer Version und Deinstallation räumen den alten Namen ebenso ab.
- **Disabled-Packages-Bereinigung**: ein früherer „Package kann nicht geladen werden → Nein“-Eintrag für die
  installierte Plugin-BPL wird entfernt, sonst bliebe sie stumm blockiert.
- **Auswahl auf eigener Seite**: nur gefundene Versionen, installiert wird nur das Angehakte. Wer eine zuvor
  installierte Version aushakt, wird sie los: Registrierung, Override-Segment, Dateien (auch das Diagnoseprotokoll
  `dpcc.IDE.Expert<suffix>.log`), Ordner – in dieser Reihenfolge. Ohne Auswahl geht es nicht weiter.
- **Komponente LSP-Server** (`lspserver`, „LSP-Server dpcc.LspServer.exe (für die Betriebsart „Server“, 32 und 64
  Bit)“): unabhängig von der Delphi-Version, vorgewählt, abwählbar. Ziel `{app}\server\win32` und, nur auf 64-Bit-
  Windows, `{app}\server\win64`; dort sucht das Plugin die EXE (64 Bit zuerst). Wer sie bei einem erneuten Setup
  abwählt, wird beide EXEs und die dann leeren Ordner los. Ohne EXE zeigt die Seite dpcc die Betriebsart „Server“ als
  nicht wählbar; eine schon gewählte fällt beim Start auf das originale DelphiLSP zurück.
- **IDE-Check** (Fenster der Klasse `TAppBuilder`) beim Start von Setup und Deinstallation und noch einmal vor dem
  Schreiben. Läuft eine IDE, bricht das Setup mit Meldung ab; es beendet nie Prozesse. Im Silent-Lauf endet es
  ohne Dialog, der Grund steht im Log.
- **Nicht angefasst**: Einstellungen (`HKCU\Software\dpcc\IdePlugin`), Daten (`%APPDATA%\dpcc`), Index-Cache und
  Protokoll (`%LOCALAPPDATA%\dpcc`), die Ablage des LSP-Servers (`%LOCALAPPDATA%\dpcc.LspServer`) und der
  Code-Insight-Anbieter der IDE. Das Setup wählt keine Betriebsart. Nach der Installation gilt die Betriebsart
  „Plugin“, je Delphi-Version getrennt: Gibt es für die Version noch keinen gespeicherten Wert (auch kein früheres
  `Enabled`), stellt dpcc beim ersten Start den Code-Insight-Anbieter der IDE selbst auf dpcc, auch wenn DelphiLSP
  gewählt war; das wirkt nach einem Neustart von Delphi. Eine gespeicherte Betriebsart bleibt. Gewählt wird sie unter
  **Tools › Optionen › Drittanbieter › dpcc** ([Einstellungen](../docs/de/settings.md#betriebsart)). Die Ready-Seite
  sagt das: „Nach der Installation gilt die Betriebsart „Plugin“ … je Delphi-Version getrennt; das Setup wählt sie
  nicht. „Server“ braucht die Komponente LSP-Server.“
- **Deinstallation**: zuerst der IDE-Check. Ist dpcc in einer Version, in der das Setup es installiert hat, noch
  Code-Insight-Anbieter (`Insight Manager` = `dpcc.CodeInsight` unter
  `HKCU\Software\Embarcadero\BDS\<bds>\Editor\Source Options\Borland.EditOptions.Pascal`), fragt der Deinstaller
  nach (Vorgabe Nein) und empfiehlt, erst die Betriebsart „Aus“ zu wählen und Delphi einmal neu zu starten; dpcc
  stellt dann Anbieter und Schalter selbst zurück. Der Deinstaller schreibt dort nichts; im Silent-Lauf steht der Hinweis nur im Log. Danach werden
  die Registry-Werte VOR den Dateien entfernt (`uninsdeletevalue` und `usUninstall`-Handler): Known- und
  Disabled-Packages-Wert beider Versionen und das eigene PATH-Segment, nur dieses. Bleibt vom Wert nichts oder nur
  `$(PATH)`, verschwindet er (der Schlüssel mit, wenn er leer ist); bleibt mehr, bleibt der Rest stehen.
  `[UninstallDelete]` räumt `bpl\d12`, `bpl\d13` und den dann leeren `bpl`-Ordner ab. Die installierten
  `dpcc.LspServer.exe` entfernt Inno selbst, `[UninstallDelete]` danach die dann leeren Ordner `server\win32`,
  `server\win64` und `server`. Einstellungen, Daten, Cache
  und Protokoll bleiben; was danach noch liegt, nennt
  [Installation › Deinstallieren](../docs/de/installation.md#deinstallieren).
- **Kein Netzwerk**: das Setup baut keine Verbindung auf. Die Buttons unten links („Stern auf GitHub“, optional
  „Spenden“) öffnen nur auf Klick den Standard-Browser.
- **Sprachauswahl** Deutsch/Englisch, **MIT-Lizenzseite** aus `LICENSE`.

## 4. Testmatrix

| # | Szenario | Erwartung |
|---|---|---|
| 1 | Rechner mit Delphi 13, ohne eigenen Bau, Konto ohne Adminrechte | kein UAC-Prompt; acht BPLs unter `%LOCALAPPDATA%\Programs\dpcc\bpl\d13\`; ein Known-Packages-Wert für `dpcc.Plugin370.bpl`, Daten nicht leer; `{app}\bpl\d13` vorn im PATH-Override |
| 2 | IDE-Start danach | dpcc lädt ohne „Package kann nicht geladen werden“; Info-Dialog nennt „dpcc <Version>“; `%LOCALAPPDATA%\dpcc\Logs\dpcc.log` enthält „dpcc angemeldet“ |
| 3 | Setup starten, während Delphi läuft | Abbruch mit Meldung, nichts geschrieben |
| 3a | Delphi erst bei offenem Wizard starten, dann Installieren | Stopp auf der Vorbereiten-Seite, nichts geschrieben |
| 3b | Rechner ohne Delphi 12 und 13 | Abbruch vor der Installation |
| 4 | Rechner mit eigenem Bau (Known Packages auf `Output\…\Bpl`) | Hinweis erscheint; danach nur noch der Installationspfad registriert; IDE lädt dpcc genau einmal |
| 5 | Plugin vorher per „Nein“ deaktiviert (Disabled Packages) | Eintrag weg, dpcc lädt wieder |
| 6 | Dasselbe Setup zweimal | BPLs überschrieben, genau ein Known-Packages-Wert je Version, Segment genau einmal |
| 6a | Update über ein Setup mit dem alten Plugin-Namen (`dpcc.IDE.Base<suffix>.bpl`) | kein Hinweis; danach nur der Wert `…\dpcc.Plugin<suffix>.bpl` je Version, `dpcc.IDE.Base<suffix>.bpl` weder in Known/Disabled Packages noch in `{app}\bpl\<version>`; IDE startet ohne Fehlermeldung |
| 7 | Silent `dpccSetup-*.exe /VERYSILENT /NORESTART /LOG` | wie #1; Exit-Code 0; Hinweise nur im Log |
| 7b | Silent mit offener IDE | Ende ohne Dialog, Exit-Code ungleich 0, Grund im Log |
| 8 | Eine Version abwählen (Setup erneut) | Dateien, Known-/Disabled-Wert und Segment dieser Version weg |
| 9 | Deinstallation, dpcc noch Anbieter | Rückfrage erscheint und empfiehlt die Betriebsart „Aus“; Nein bricht ohne Änderung ab |
| 10 | Deinstallation (IDE zu) | Registry-Werte weg, PATH ohne unser Segment mit allen fremden Segmenten, danach Dateien weg, auch `{app}\server\win32` und `{app}\server\win64`; `HKCU\Software\dpcc`, `%APPDATA%\dpcc`, `%LOCALAPPDATA%\dpcc`, `%LOCALAPPDATA%\dpcc.LspServer` unverändert; IDE startet ohne Fehlermeldung |
| 11 | Delphi 12 und 13 gleichzeitig offen | jede IDE lädt ihre `290`- bzw. `370`-Fassung |
| 12 | Komponente LSP-Server angewählt (Vorgabe), 64-Bit-Windows | `{app}\server\win32\dpcc.LspServer.exe` (PE `014C`) und `{app}\server\win64\dpcc.LspServer.exe` (PE `8664`); auf der Seite dpcc ist „Server“ wählbar, der Hint am Feld nennt die 64-Bit-EXE |
| 13 | Komponente LSP-Server abgewählt (Setup erneut) | beide EXEs und die leeren `server`-Ordner weg; „Server“ grau mit „Nicht wählbar: …“; war Server gewählt, bleibt es gewählt, und `dpcc.log` nennt „Start von DelphiLSP nicht umgeleitet (dpcc.LspServer.exe nicht gefunden)“ |
| 14 | Betriebsart Server, Projektgruppe öffnen | `dpcc.log`: „LSP-Umleitung: #n DelphiLSP umgeleitet auf …\server\win64\dpcc.LspServer.exe (PID n)“; die IDE zeigt ihre Liste mit Antworten von `dpcc.LspServer.exe` |
| 15 | Erste Installation ohne gespeicherte Betriebsart, DelphiLSP gewählt | erster Start: Meldung „dpcc hat den Code-Insight-Anbieter der IDE auf dpcc umgestellt …“; `OperatingMode <bds>` = `plugin`; nach dem Neustart ist dpcc Anbieter |

Die Interaktion mit der IDE lässt sich nicht automatisch prüfen; die Matrix wird am gebauten Setup von Hand
durchgespielt.

## 5. Grenzen

- Nur Win32; keine Variante für die 64-Bit-IDE von Delphi 13 (dpcc baut dafür keine BPLs). Die 64-Bit-EXE des
  LSP-Servers ändert daran nichts: Sie läuft als eigener Prozess, gestartet von der 32-Bit-IDE.
- Das Setup nimmt immer beide Versionen und beide EXEs auf; wer nur eine gebaut hat, kann es nicht bauen.
- Keine Code-Signatur.
