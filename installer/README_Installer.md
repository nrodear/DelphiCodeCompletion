# Installer – Bauanleitung (Delphi 12 und Delphi 13)

Das Setup `dpccSetup-<Version>.exe` installiert dpcc für den aktuellen Benutzer in Delphi 12 und/oder Delphi 13,
ohne Administratorrechte. Technik: Inno Setup 6, Skript `installer\dpccSetup.iss`. Es kompiliert nichts, sondern
bündelt die in der IDE gebauten BPLs.

## 0. Unterstützte Delphi-Versionen

BPLs sind an die Compiler-Version gebunden: eine BPL mit der Endung `290` lädt nur in Delphi 12, eine mit `370`
nur in Delphi 13. Die Tabelle entspricht der Übersicht auf der Seite „Bereit zur Installation“ des Setups; bei
Änderungen beide Stellen pflegen.

| Delphi | BDS | IDE | BPLs | Registry-Zweig (HKCU) | Setup |
|---|---|---|---|---|---|
| ≤ 11 | ≤ 22.0 | 32-Bit | – | – | **nicht unterstützt** (keine Projektgruppe) |
| 12 Athens | 23.0 | 32-Bit | acht BPLs `…290.bpl`, Ziel `{app}\bpl\d12` | `…\BDS\23.0\Known Packages` | **ja** |
| 13 Florence | 37.0 | 32-Bit | acht BPLs `…370.bpl`, Ziel `{app}\bpl\d13` | `…\BDS\37.0\Known Packages` | **ja** |
| 13 Florence | 37.0 | 64-Bit | – | – | **nicht in diesem Setup**: dpcc baut nur Win32, die 64-Bit-IDE lädt keine Win32-BPL |

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

Je Version acht BPLs, alle mit `{$LIBSUFFIX AUTO}`:

| BPL | Art |
|---|---|
| `dpcc.Text`, `dpcc.WinBase`, `dpcc.Common`, `dpcc.Windows`, `dpcc.Server`, `dpcc.Core`, `dpcc.UI` | Laufzeitpakete (`{$RUNONLY}`) |
| `dpcc.IDE.Base` | Design-Paket (`{$DESIGNONLY}`), das Plugin; requires die sieben |

Das Setup nimmt beide Versionen immer zusammen auf; vor dem Setup also beide Gruppen bauen.

### Warum der PATH-Eintrag nötig ist

Der Windows-Loader löst `requires` über das Verzeichnis von bds.exe, System32 und PATH auf, **nicht** im Ordner
der Plugin-BPL, und ein `{$RUNONLY}`-Paket gehört nicht in die Known Packages. Deshalb steht dort nur
`dpcc.IDE.Base<suffix>.bpl` (voller Pfad), und das Setup legt `{app}\bpl\<version>` vorn in den IDE-eigenen Override
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
- jede BPL jünger als die neueste Quelldatei (`.pas`, `.dpk`, `.dfm`, `.inc`) ihres Packages.

Die Win32-BPLs tragen keine VERSIONINFO (`VerInfo_IncludeVerInfo` ist für Win32 aus); ein Versionsvergleich der
BPLs entfällt deshalb. Danach ruft das Skript ISCC mit `/DDpccVersion=<x.y.z>.0` und den beiden Quellordnern auf.

| Parameter | Vorgabe | Bedeutung |
|---|---|---|
| `-DryRun` | aus | nur die Prüfungen, danach Ende |
| `-BplDirD12` | `Output\Win32\D12\Bpl` | anderer BPL-Ordner für Delphi 12 |
| `-BplDirD13` | `Output\Win32\Debug\Bpl` | anderer BPL-Ordner für Delphi 13 |
| `-OutDir` | `installer\Output` | Zielordner des Setups (steht über `Output/` in `.gitignore`) |
| `-Iscc` | PATH, dann Standardordner | voller Pfad zu `ISCC.exe` |

Hand-Compile ist ebenso möglich:

```bat
cd installer
iscc dpccSetup.iss
:: abweichende Quellordner:
iscc /DDpccBplSourceDirD12="D:\release\d12" /DDpccBplSourceDirD13="D:\release\d13" dpccSetup.iss
```

Ohne `/DDpccVersion` liest das Skript die Version beim Kompilieren selbst aus `dpcc.Text.Product.Version.pas`
(`cVersion`, mit angehängtem `.0`); eine zweite, von Hand gepflegte Versionsangabe gibt es nicht. Weitere Defines:
`DpccRepoRoot` (Repo-Wurzel mit abschließendem `\`, Vorgabe der Ordner über `installer`) und `DpccDonateUrl`
(leer = kein Spenden-Button). Ergebnis: `installer\Output\dpccSetup-<Version>.exe`. Setup-EXEs gehören nicht ins
Repo.

## 3. Was der Installer tut

- **Per-User, nie elevated** (`PrivilegesRequired=lowest`). Dateien nach `%LOCALAPPDATA%\Programs\dpcc\`:

  | Version | Dateien nach | Known Packages (Wertname = voller Pfad, Daten `dpcc (Code Insight-Manager)`) | PATH-Override |
  |---|---|---|---|
  | Delphi 12 | `bpl\d12\dpcc.*290.bpl` | `HKCU\Software\Embarcadero\BDS\23.0\Known Packages`, Wert `…\bpl\d12\dpcc.IDE.Base290.bpl` | `…\BDS\23.0\Environment Variables`, Wert `PATH` |
  | Delphi 13 | `bpl\d13\dpcc.*370.bpl` | `HKCU\Software\Embarcadero\BDS\37.0\Known Packages`, Wert `…\bpl\d13\dpcc.IDE.Base370.bpl` | `…\BDS\37.0\Environment Variables`, Wert `PATH` |

  Dazu `unins000.exe`/`unins000.dat` in `{app}`, der Eintrag unter „Apps“ von Windows und ein Startmenü-Eintrag
  `dpcc\Uninstall dpcc (IDE-Plugin)`.
- **IDE-PATH-Override**: `{app}\bpl\<version>` kommt vorn in den Wert. Er ist geteilt (InterBase trägt dort z. B.
  `…\IDE_spoof;$(PATH)`): nur das eigene Segment wird bewegt, alles andere bleibt Zeichen für Zeichen. Das Segment
  wird immer entnommen und vorn eingesetzt; eine Doppelinstallation ändert den Wert nicht, und es steht vor einem
  Entwickler-Ordner wie `…\Output\Win32\Debug\Bpl`. Fehlt der Wert in HKCU, ist die Vorlage der Delphi-Installation
  der Ausgangswert (`HKLM\SOFTWARE\WOW6432Node\Embarcadero\BDS\<bds>\Environment Variables\PATH`); HKLM selbst bleibt
  unberührt. Fehlt auch sie, entsteht `<segment>;$(PATH)`. Scheitert das Schreiben, meldet das Setup es (im
  Silent-Lauf im Log) und lässt die fremden Registrierungen dieser Version stehen.
- **Koexistenz-Check, je Version**: eine Registrierung der dpcc-Familie (die acht Packages mit oder ohne
  Versionssuffix, dazu der frühere Name `dpcc.IDE.Expert`) unter anderem Pfad – typisch der eigene Bau aus dem
  Repo – wird gemeldet und aus den Known Packages entfernt; beide zusammen ließen die IDE beim Start scheitern. Der
  PATH-Eintrag des eigenen Baus bleibt stehen. Geprüft wird nur der Zweig angehakter Versionen. Wer danach wieder den
  eigenen Bau nutzt, deinstalliert das Setup und trägt den Bau neu ein
  ([Installation](../docs/de/installation.md#installieren)).
- **Disabled-Packages-Bereinigung**: ein früherer „Package kann nicht geladen werden → Nein“-Eintrag für die
  installierte Plugin-BPL wird entfernt, sonst bliebe sie stumm blockiert.
- **Auswahl auf eigener Seite**: nur gefundene Versionen, installiert wird nur das Angehakte. Wer eine zuvor
  installierte Version aushakt, wird sie los: Registrierung, Override-Segment, Dateien (auch das Diagnoseprotokoll
  `dpcc.IDE.Expert<suffix>.log`), Ordner – in dieser Reihenfolge. Ohne Auswahl geht es nicht weiter.
- **IDE-Check** (Fenster der Klasse `TAppBuilder`) beim Start von Setup und Deinstallation und noch einmal vor dem
  Schreiben. Läuft eine IDE, bricht das Setup mit Meldung ab; es beendet nie Prozesse. Im Silent-Lauf endet es
  ohne Dialog, der Grund steht im Log.
- **Nicht angefasst**: Einstellungen (`HKCU\Software\dpcc\IdePlugin`), Daten (`%APPDATA%\dpcc`), Index-Cache und
  Protokoll (`%LOCALAPPDATA%\dpcc`) und der Code-Insight-Anbieter der IDE. Ist DelphiLSP gewählt (Vorgabe), bleibt
  dpcc nach der Installation aus; eingeschaltet wird es unter **Tools › Optionen › Drittanbieter › dpcc**
  ([Einstellungen](../docs/de/settings.md#was-dpcc-an-der-ide-umstellt)). Die Ready-Seite sagt das.
- **Deinstallation**: zuerst der IDE-Check. Ist dpcc in einer Version, in der das Setup es installiert hat, noch
  Code-Insight-Anbieter (`Insight Manager` = `dpcc.CodeInsight` unter
  `HKCU\Software\Embarcadero\BDS\<bds>\Editor\Source Options\Borland.EditOptions.Pascal`), fragt der Deinstaller
  nach (Vorgabe Nein) und empfiehlt, erst den Hauptschalter auszuschalten; dpcc stellt dann Anbieter und Schalter
  selbst zurück. Der Deinstaller schreibt dort nichts; im Silent-Lauf steht der Hinweis nur im Log. Danach werden
  die Registry-Werte VOR den Dateien entfernt (`uninsdeletevalue` und `usUninstall`-Handler): Known- und
  Disabled-Packages-Wert beider Versionen und das eigene PATH-Segment, nur dieses. Bleibt vom Wert nichts oder nur
  `$(PATH)`, verschwindet er (der Schlüssel mit, wenn er leer ist); bleibt mehr, bleibt der Rest stehen.
  `[UninstallDelete]` räumt `bpl\d12`, `bpl\d13` und den dann leeren `bpl`-Ordner ab. Einstellungen, Daten, Cache
  und Protokoll bleiben; was danach noch liegt, nennt
  [Installation › Deinstallieren](../docs/de/installation.md#deinstallieren).
- **Kein Netzwerk**: das Setup baut keine Verbindung auf. Die Buttons unten links („Stern auf GitHub“, optional
  „Spenden“) öffnen nur auf Klick den Standard-Browser.
- **Sprachauswahl** Deutsch/Englisch, **MIT-Lizenzseite** aus `LICENSE`.

## 4. Testmatrix

| # | Szenario | Erwartung |
|---|---|---|
| 1 | Rechner mit Delphi 13, ohne eigenen Bau, Konto ohne Adminrechte | kein UAC-Prompt; acht BPLs unter `%LOCALAPPDATA%\Programs\dpcc\bpl\d13\`; ein Known-Packages-Wert für `dpcc.IDE.Base370.bpl`, Daten nicht leer; `{app}\bpl\d13` vorn im PATH-Override |
| 2 | IDE-Start danach | dpcc lädt ohne „Package kann nicht geladen werden“; Info-Dialog nennt „dpcc <Version>“; `%LOCALAPPDATA%\dpcc\Logs\dpcc.log` enthält „dpcc angemeldet“ |
| 3 | Setup starten, während Delphi läuft | Abbruch mit Meldung, nichts geschrieben |
| 3a | Delphi erst bei offenem Wizard starten, dann Installieren | Stopp auf der Vorbereiten-Seite, nichts geschrieben |
| 3b | Rechner ohne Delphi 12 und 13 | Abbruch vor der Installation |
| 4 | Rechner mit eigenem Bau (Known Packages auf `Output\…\Bpl`) | Hinweis erscheint; danach nur noch der Installationspfad registriert; IDE lädt dpcc genau einmal |
| 5 | Plugin vorher per „Nein“ deaktiviert (Disabled Packages) | Eintrag weg, dpcc lädt wieder |
| 6 | Dasselbe Setup zweimal | BPLs überschrieben, genau ein Known-Packages-Wert je Version, Segment genau einmal |
| 7 | Silent `dpccSetup-*.exe /VERYSILENT /NORESTART /LOG` | wie #1; Exit-Code 0; Hinweise nur im Log |
| 7b | Silent mit offener IDE | Ende ohne Dialog, Exit-Code ungleich 0, Grund im Log |
| 8 | Eine Version abwählen (Setup erneut) | Dateien, Known-/Disabled-Wert und Segment dieser Version weg |
| 9 | Deinstallation, dpcc noch Anbieter | Rückfrage erscheint; Nein bricht ohne Änderung ab |
| 10 | Deinstallation (IDE zu) | Registry-Werte weg, PATH ohne unser Segment mit allen fremden Segmenten, danach Dateien weg; `HKCU\Software\dpcc`, `%APPDATA%\dpcc`, `%LOCALAPPDATA%\dpcc` unverändert; IDE startet ohne Fehlermeldung |
| 11 | Delphi 12 und 13 gleichzeitig offen | jede IDE lädt ihre `290`- bzw. `370`-Fassung |

Die Interaktion mit der IDE lässt sich nicht automatisch prüfen; die Matrix wird am gebauten Setup von Hand
durchgespielt.

## 5. Grenzen

- Nur Win32; keine Variante für die 64-Bit-IDE von Delphi 13 (dpcc baut dafür keine BPLs).
- Das Setup nimmt immer beide Versionen auf; wer nur eine gebaut hat, kann es nicht bauen.
- Keine Code-Signatur.
