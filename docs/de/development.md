Deutsch | [English](../en/development.md) | [Français](../fr/development.md)

# Entwicklung

[Übersicht](index.md) › Entwicklung

## Voraussetzungen

- Delphi 13 / RAD Studio 37.0, Plattform Win32.
- Für Delphi 12 / RAD Studio 23.0 nur die Packages (`dpcc_d12.groupproj`), ohne Tests: Delphi 12 bringt DUnitX
  für Win32 nicht mit.
- DUnitX für die Tests; es gehört zu RAD Studio.

## Bauen

`dpcc_d13.groupproj` enthält zehn Projekte:

1. `Packages\dpcc.Text\dpcc.Text.dproj`
2. `Packages\dpcc.WinBase\dpcc.WinBase.dproj`
3. `Packages\dpcc.Common\dpcc.Common.dproj`
4. `Packages\dpcc.Windows\dpcc.Windows.dproj`
5. `Packages\dpcc.Server\dpcc.Server.dproj` (Quellen in `Application\Source\Shell`)
6. `Packages\dpcc.Core\dpcc.Core.dproj`
7. `Packages\dpcc.UI\dpcc.UI.dproj`
8. `Packages\dpcc.Plugin\dpcc.Plugin.dproj`
9. `Tests\dpcc.Completion.Tests.dproj`
10. `Application\dpcc.LspServer.dproj` (der LSP-Server `dpcc.LspServer.exe`, siehe [LSP-Server](lsp-server.md))

Die Gruppe in der IDE öffnen, Win32 und Debug wählen und alle Projekte bauen. Die Abhängigkeiten der Gruppe legen
die Reihenfolge fest.

| Ausgabe | Ordner |
|---|---|
| BPLs | `Output\Win32\Debug\Bpl` |
| DCPs | `Output\Win32\Debug\Dcp` |
| DCUs | `Output\Win32\Debug\Dcu\<Projekt>` |
| Testprogramm, `dpcc.LspServer.exe` (32 Bit) | `Output\Win32\Debug\Bin` |
| `dpcc.LspServer.exe` (64 Bit, eigener Schritt, siehe unten) | `Output\Win64\Debug\Bin` |

**LSP-Server für 64 Bit:** Die Win64-EXE entsteht nicht im Gruppenbau. Eigener Schritt in Delphi 13:
`Application\dpcc.LspServer.dproj` öffnen, Zielplattform **Windows 64-Bit**, Konfiguration Debug, **Erzeugen**
(Make). Die Ausgabe liegt unter `Output\Win64\Debug\Bin`. Das Plugin aus `Output\Win32\<Konfiguration>\Bpl` findet
die EXE dort selbst (Reihenfolge der Orte: [LSP-Server](lsp-server.md#wo-dpcc-die-exe-sucht)). Vor
`Tools\Build-Setup.ps1` also drei Bauten: `dpcc_d13.groupproj` (Debug), `dpcc_d12.groupproj` (D12) und die
Win64-EXE.

Alle acht Packages tragen die Package-Version als Endung (`{$LIBSUFFIX AUTO}`, in der `.dproj` `DllSuffix` =
`$(Auto)`): `dpcc.Text370.bpl` … unter Delphi 13, `dpcc.Text290.bpl` … unter Delphi 12. Die Namen in `requires`
und die `.dcp` bleiben ohne Endung.

**Delphi 12:** `dpcc_d12.groupproj` enthält die Projekte 1 bis 8 mit denselben Abhängigkeiten, ohne das
Testprogramm und ohne den LSP-Server (die EXE aus der Gruppe für Delphi 13 bedient beide Versionen). Jede `.dproj` der Packages hat neben Debug (`Cfg_1`) und Release (`Cfg_2`) die Build-Konfiguration
`D12` (`Cfg_3`). Sie erbt alle Einstellungen von Debug und setzt selbst keine Werte. Weil alle Ausgabe- und
Suchpfade `$(Platform)\$(Config)` enthalten, baut sie ohne eigene Pfade nach `Output\Win32\D12\…`. Delphi 12 baut
mit der Konfiguration D12, Delphi 13 mit Debug.

Eine eigene Konfiguration ist nötig, weil die IDE die Kommandozeile des Compilers aus ihrem eigenen Optionsmodell
bildet. Sie kennt nur die Gruppen der Build-Konfigurationen (`Base`, `Cfg_n` und Plattform-Varianten wie
`Base_Win32`); eine zusätzliche Gruppe mit eigener Bedingung (etwa `Exists(…)`) übergeht sie.

| Ausgabe unter Delphi 12 | Ordner |
|---|---|
| BPLs | `Output\Win32\D12\Bpl` |
| DCPs | `Output\Win32\D12\Dcp` |
| DCUs | `Output\Win32\D12\Dcu\<Projekt>` |

**Delphi 12 nie mit der Konfiguration Debug bauen.** Es schreibt sonst BPLs, DCPs und DCUs in die Ordner von
Delphi 13 (`Output\Win32\Debug\…`); dann die Gruppe `dpcc_d13.groupproj` unter Delphi 13 neu bauen. In der IDE von
Delphi 12 die Konfiguration D12 für alle acht Projekte aktivieren (**Projekt › Konfigurationsverwaltung** oder im
Projektmanager unter **Build-Konfigurationen** je Projekt). Werkzeuge, die die IDE fernsteuern, übergeben die
Konfiguration beim Bauen (etwa `-Config D12 -Platform Win32`). Die IDE speichert die aktive Konfiguration in der
`.dproj` (`<Config Condition="'$(Config)'==''">`). Vor dem Speichern wieder Debug aktivieren, sonst baut auch
Delphi 13 die Konfiguration D12.

In der IDE von Delphi 12 gehört `…\Output\Win32\D12\Bpl` in den PATH (`Tools\IdePath.ps1 -BdsVersion 23.0`),
installiert wird `dpcc.Plugin290.bpl`; siehe [Installation](installation.md#bauen-für-delphi-12).

**Kommandozeile:** Der Kommandozeilen-Compiler (`dcc32`, MSBuild) ist in den Editionen Community und Starter von
Delphi gesperrt. Mit diesen Editionen die Gruppe in der IDE bauen.

Ist dpcc in derselben IDE installiert, entlädt die IDE das Plugin beim Bauen. Nach dem Bauen die IDE neu starten.

Build-Ausgaben gehören nicht ins Repository (`.gitignore`: `Output/`, `*.dcu`, `*.bpl`, `*.exe` …).

### Setup und ZIP

`Tools\Build-Setup.ps1` baut aus den fertigen Dateien das Setup (Inno Setup 6) und daneben das ZIP
`installer\Output\dpcc.LspServer-<x.y.z>.zip` mit `win32\dpcc.LspServer.exe`, `win64\dpcc.LspServer.exe` und
`LIESMICH.txt` (Quelle `installer\LspServer-LIESMICH.txt`). Es prüft vorher die BPLs beider Versionen und beide EXEs:
`Output\Win32\Debug\Bin` mit PE-Machine `014C`, `Output\Win64\Debug\Bin` mit `8664`, jede nicht älter als ihre
Quellen. Andere Ordner über `-LspServerDirWin32` und `-LspServerDirWin64`. Einzelheiten:
[installer/README_Installer.md](../../installer/README_Installer.md).

## Testen

`Tests\dpcc.Completion.Tests.dproj` ist ein DUnitX-Konsolenprogramm, nur in der Gruppe für Delphi 13. Nach dem
Bauen:

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --exclude:Benchmark --exitbehavior:Continue
```

| Option | Bedeutung |
|---|---|
| `--exclude:Benchmark` | lässt die Messungen der Kategorie `Benchmark` aus |
| `--exitbehavior:Continue` | wartet am Ende nicht auf Enter |

- Exit-Code 0, wenn alle Tests bestehen. Ein Speicherleck zählt als Fehlschlag.
- Ausgabe auf der Konsole und als NUnit-XML.
- Das Protokoll der Sicherung schreiben die Tests nach `%TEMP%\dpccCompletionTests\Logs`, nicht in das `dpcc.log`
  der installierten Version. Die Tests lösen absichtlich Fehler aus.
- Mit dem Symbol `TESTINSIGHT` läuft das Programm unter TestInsight statt als Konsole.

| Ordner | Inhalt |
|---|---|
| `Tests\Common\Lsp` | Server-Seite: Vervollständigung, Hover, Parameterhilfe |
| `Tests\Common\Index` | Index: Extractor, Token- und Typtexte, bedingte Kompilierung, Inhalte je Deklaration (Format 35) |
| `Tests\Common\Semantics` | Namensauflösung (aus dem früheren Stand zurückgeholt): lokale Namen, Mitglieder und Vorfahren, Ketten, Überladungen, Generics, Helfer, `with`, Inline-Variablen, Sichtbarkeit, Ausdrücke als Empfänger, die Teile des Resolvers einzeln |
| `Tests\Common\Pascal` | Parser und Präprozessor |
| `Tests\IDE` | Plugin-Seite ohne ToolsAPI: Ablauf der Liste, Rangfolge, Favoriten, Mengenmodus, Platzhalter, Einstellungen, Texte, Betriebsart und Überführung aus `Enabled` (`dpcc.Core.Settings.OperatingMode.Tests`), Entscheidung und Orte der Umleitung auf `dpcc.LspServer.exe` (`dpcc.Core.Lsp.ServerRedirect.Tests`) |
| `Tests\Application\Shell` | Hülle des Servers |
| `Tests\Common` | Speicher: Selbstmessung, Namen der `.dcp`, gemeinsamer Cache, Office-Typbibliotheken und WinRT, Freigabe nach dem Ende des Servers, Dokumente, Namens- und Verweistabellen, Signaturen im Cache, Cache-Format 34, Katalog, Nachladen und Verdrängen, Nutzungsstatistik, Suche über nicht geladene Units, geschützte Units, Wiederverwendung der Verweistabellen, gleichzeitiges Nachladen, Anhängen an den Cache, Verdichten des Caches, Freigabe der gemeinsamen Stände nach dem Stopp, Schreiben der Nutzungsstatistik |
| `Tests\Common` (`dpcc.Common.Sources.Tests`) | Quellen und Aktualität: zusätzliche Quellordner, Office und WinRT bei Bedarf, gleichnamige Units, neue und geänderte Dateien, Fehler je Datei, `uses … in`, Makros und Browsing Path, Typen der Installation ohne Quelltext |
| `Tests\Memory` | Messprogramm für den Speicher (Kategorie `Benchmark`) |
| `Tests\Support` | Hilfen: feste Datenquelle, Leck-Überwachung |

Die Tests linken die DCUs der Packages statisch. Teile mit ToolsAPI (`dpcc.Plugin`) lassen sich nur in der IDE
prüfen.

### Speicher messen

`dpcc.Memory.Bench.Tests` startet den Server im eigenen Prozess wie das Plugin, öffnet eine Projektgruppe mit der
Bibliothek der Installation und schreibt jede Sekunde Private Bytes, Spitze, Working Set und die größte freie Region
des Adressraums in eine CSV-Datei. Messpunkte: Start, Index fertig, nach den Anfragen, nach jedem Neuaufbau
(`.dproj` gespeichert) und nach einem Neustart des Servers. Ohne die Variable `DPCC_MEMBENCH_OUT` endet der Test
sofort. Auf Wunsch folgen nach den Anfragen Vervollständigungen auf zufällige Units der Bibliothek, die das Nachladen
und Verdrängen messen (`DPCC_MEMBENCH_COLD`), Tippen in einer Projekt-Unit mit gleichzeitigen Anfragen, das die
Antwortzeiten misst (`DPCC_MEMBENCH_TYPING`), und große Units in den `uses` einer Projekt-Unit, gefolgt von
Vervollständigungen auf zufällige Units, die Nachladen und Verdrängen zählen (`DPCC_MEMBENCH_PINNED`).

| Variable | Bedeutung |
|---|---|
| `DPCC_MEMBENCH_OUT` | CSV-Datei; die Messpunkte stehen in `<Datei>-points.csv` |
| `DPCC_MEMBENCH_GROUP` | `.groupproj`, deren Projekte den Arbeitsbereich bilden |
| `DPCC_MEMBENCH_REQUESTS`, `DPCC_MEMBENCH_REBUILDS`, `DPCC_MEMBENCH_RESTARTS`, `DPCC_MEMBENCH_BETWEEN` | Anfragen (2000), Neuaufbauten (5), Neustarts (1), Anfragen zwischen zwei Neuaufbauten (100) |
| `DPCC_MEMBENCH_COLD`, `DPCC_MEMBENCH_LIBDIR` | Zahl der Vervollständigungen „Unit.“ auf zufällige Units der Bibliothek (0) und der Ordner ihrer Quellen (`source` von Delphi 13) |
| `DPCC_MEMBENCH_TYPING` | Tipp-Runden (0): je vier Tastendrücke, dann die Tipp-Pause; ein zweiter Thread fragt währenddessen an. Zeile „[typing]“ mit Median, 95. und 99. Perzentil und Höchstwert der Antwortzeiten, jede einzelne in `<Datei>-latency.csv` |
| `DPCC_MEMBENCH_AUTOMIN` | Schwelle für die Vervollständigung nach „:=“ im Tipp-Szenario (5; im Messprogramm fest, die Einstellung `completion.autoMinChars` hat die Vorgabe 0 = aus): Der Name dahinter wird getippt, gefragt wird wie in der IDE erst ab so vielen Zeichen und nur einmal; Stellen ohne Anfrage zählt die zweite Zeile „[typing]“. 0 = nie; -1 = wie vor dieser Regel direkt hinter „=“ ohne Buchstaben |
| `DPCC_MEMBENCH_PINNED`, `DPCC_MEMBENCH_PINNEDUNITS`, `DPCC_MEMBENCH_PINNEDCOUNT` | Vervollständigungen auf zufällige Units (0), nachdem eine Projekt-Unit große Units in ihren `uses` nennt und lädt: kommagetrennte Namen bzw. die größten Dateien der Bibliothek (80). Zeile „[pinned]“ mit Nachladen und Verdrängen |
| `DPCC_MEMBENCH_FREQUENT`, `DPCC_MEMBENCH_FREQNAMES` | Runden (0) mit einem häufigen Namen oberster Ebene (kommagetrennt, Vorgabe `Register`): eine Vervollständigung nach „:=“ auf eine Variable dieses Typs (sucht ihn in allen Units), dann fünf Vervollständigungen auf zufällige Units. Zeile „[frequent]“ mit Nachladen, Verdrängen und Antwortzeiten der Suche |
| `DPCC_MEMBENCH_DEFINITIONS` | Strg+Klick (Auftrag NAV): durch „\|“ getrennte Fälle `Units#Zeile#Wort`; je Fall eine Projekt-Unit mit diesen `uses` und der Zeile im Rumpf einer Routine, dann das Sprungziel des Worts mit eigener Grenze von 1 s (dem früheren Zeitlimit der IDE). Zeilen „[definition]“ mit Ziel, Antwortzeit und nachgeladenen Units, „[definition] Summe“ mit Treffern, Median, Höchstwert und zuletzt der Zahl der Antworten über 250 ms (so lange wartet die IDE heute; darüber reicht dpcc den Sprung nach) |
| `DPCC_CACHE_ROOT` bzw. `LOCALAPPDATA`, `APPDATA` | eigene Ordner, damit der Cache des Benutzers unberührt bleibt; für einen warmen Start eine Kopie des Bibliotheks-Caches hineinlegen |

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --run:dpcc.Memory.Bench.Tests --exitbehavior:Continue
```

Jeder Messpunkt nennt auch den vom Speichermanager belegten Speicher (`alloc_mb`); der Abstand zu den Private Bytes ist
der Verschnitt. Die Zeilen „[lazy]“ und die Spalten `loaded` bis `largest_load_ms` nennen geladene, gepinnte,
freigebbare und nur im Katalog stehende Units, den Katalog, Nachladen und Verdrängen samt Dauer. Fehler im Server (`ERangeError`, `EIntOverflow`, `EAccessViolation`) schreibt das Messprogramm mit
Fehleradresse und Rücksprungadressen nach `<Datei>-exceptions.txt`; aufzulösen mit der `.map`-Datei des
Testprogramms.

Das Testprogramm ist wie `bds.exe` LARGEADDRESSAWARE (4 GB Adressraum). Messdaten gehören nicht ins Repository.

## Konventionen

Aus dem bestehenden Code:

- **Unit-Namen**: `dpcc.<Package>.<Bereich>.<Name>`, etwa `dpcc.Core.Completion.Controller`. Die Units des Servers
  heißen `Shell.*`.
- **Namen**: Felder `F…`, Parameter `A…`, lokale Variablen `m…`. Typen im Plugin `TDpcc…`, Schnittstellen
  `IDpcc…`; in `dpcc.Common` auch nach Bereich (`TLsp…`, `TIndex…`).
- **Blöcke**: `begin`/`end` auch bei einzelnen Anweisungen.
- **Kommentare** auf Deutsch. Jede Unit beginnt mit einem Kommentar zu ihrem Zweck; öffentliche Elemente tragen
  XMLDoc (`/// <summary>`).
- **Schichten**: siehe [Architektur](architecture.md#regeln-der-schichten). Kein VCL und keine ToolsAPI in
  `dpcc.Core`, keine ToolsAPI in `dpcc.UI`.
- **IDE-Einstiege**: Jeder Aufruf aus der IDE (Timer, Notifier, Zeichnen, Tasten) läuft über `TDpccGuard.Run`.
  Der Hauptthread wartet nie auf den Server; Ergebnisse kommen über `TDpccMainThread` zurück.
- **Texte**: Jeder Benutzertext steht deutsch und englisch in einer Tabelle
  `cTexts: array[TDpccLanguage, …]`. In `dpcc.UI` hat jedes Feature eine eigene Strings-Unit. Ein Test prüft alle
  Tabellen: kein leerer Text, gleiche Platzhalter in beiden Sprachen.
- **Zeilenenden**: CRLF für `.pas`, `.dpr`, `.dpk`, `.inc`, `.dfm`, `.dproj`, `.groupproj`, `.ps1`
  (`.gitattributes`).

### Eine Option hinzufügen

Nach dem Muster der vorhandenen Optionen:

1. Feld, Vorgabe und Grenzen in `TDpccPluginSettings` (`dpcc.Core.Settings.Plugin`: Feld, `Defaults`,
   `Normalize`), Lesen und Schreiben in `Exchange` unter dem Registry-Namen (der Schlüssel der Doku steht als
   Kommentar dahinter). Ein nur gelesener Wert (wie `XmlDocMaxLines`) steht nicht in `Exchange`, sondern in `Load`
   und in `ReadOnlyNames`. Einen Katalog der Einstellungen gibt es seit dem Aufräumen nicht mehr.
2. Ort: Liest auch der Server den Wert, liegt er in `settings.json` und bekommt einen Eintrag in
   `TDpccSettingsScopes.Routed` (`dpcc.Core.Settings.Scopes`); sonst liegt er in der Registry.
3. Seite: Die Optionsseite baut `cPageItems` aus `dpcc.Core.Settings.CompletionView` (Abschnitt und Reihenfolge).
   Eine neue Option kommt in `cPageItems`, in `TDpccSettingsPage.BuildItem`, `LoadFrom` und `SaveTo`
   (`dpcc.UI.Settings.Page`) und mit ihrer Beschriftung deutsch und englisch in `dpcc.UI.Settings.Strings`.
4. Fest verdrahtete Werte: Eine Option ohne Platz auf der Seite wird kein Feld, sondern eine Konstante in
   `TDpccFixedSettings` (`dpcc.Core.Settings.CompletionView`), die die Stelle, die sie braucht, direkt liest.
   `TDpccIdeSettings.Current` (`dpcc.IDE.Foundation.Settings`) ist genau der gespeicherte Stand.
5. Test: `dpcc.Core.Settings.CompletionView.Tests` prüft, dass `TDpccPluginSettings.StoredNames` genau die
   Einstellungen der Seite sind und nichts anderes gespeichert oder umgeleitet wird;
   `dpcc.UI.Settings.Page.Tests` prüft die Seite headless in der Test-Exe.

### Betriebsart und Umleitung im Code

| Unit | Aufgabe |
|---|---|
| `dpcc.Core.Settings.OperatingMode` | Betriebsart Aus, Plugin, Server: Kennungen, Registry-Name je Version, Überführung aus `Enabled` |
| `dpcc.Core.Lsp.ServerRedirect` | reine Entscheidung, ob ein Start von `DelphiLSP.exe` umgeleitet wird, und die Orte der EXE; ohne Registry und Dateizugriff, damit testbar |
| `dpcc.Core.Diagnostics.ImportPatch` | Eintrag in der Importtabelle eines Moduls finden, umbiegen und zurücksetzen |
| `dpcc.IDE.Foundation.LspRedirect` | der Hook im Plugin: Einbau beim Anmelden, Abbau beim Entladen, Betriebsart bei jedem Aufruf frisch gelesen |

Tests: `Tests\IDE\dpcc.Core.Settings.OperatingMode.Tests.pas` und `Tests\IDE\dpcc.Core.Lsp.ServerRedirect.Tests.pas`.
Den Hook selbst prüft nur die laufende IDE.

## Beitragen

Das Repository liegt unter <https://github.com/nrodear/DelphiCodeCompletion>. Fehler und Vorschläge als Issue,
Änderungen als Pull Request.

Vor einem Pull Request:

- die ganze Gruppe baut ohne Fehler;
- die Tests laufen grün (`--exclude:Benchmark`);
- neue Benutzertexte stehen deutsch und englisch da;
- die Dokumentation unter `docs` ist angepasst, wenn sich Bedienung oder Optionen ändern.

Lizenz: MIT, siehe [LICENSE](../../LICENSE).
