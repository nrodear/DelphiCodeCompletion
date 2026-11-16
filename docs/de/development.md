Deutsch | [English](../en/development.md) | [Français](../fr/development.md)

# Entwicklung

[Übersicht](index.md) › Entwicklung

## Voraussetzungen

- Delphi 13 / RAD Studio 37.0, Plattform Win32.
- DUnitX für die Tests; es gehört zu RAD Studio.

## Bauen

`dpcc_d13.groupproj` enthält neun Projekte:

1. `Packages\dpcc.Text\dpcc.Text.dproj`
2. `Packages\dpcc.WinBase\dpcc.WinBase.dproj`
3. `Packages\dpcc.Common\dpcc.Common.dproj`
4. `Packages\dpcc.Windows\dpcc.Windows.dproj`
5. `Packages\dpcc.Server\dpcc.Server.dproj` (Quellen in `Application\Source\Shell`)
6. `Packages\dpcc.Core\dpcc.Core.dproj`
7. `Packages\dpcc.UI\dpcc.UI.dproj`
8. `Packages\dpcc.IDE.Base\dpcc.IDE.Base.dproj`
9. `Tests\dpcc.Completion.Tests.dproj`

Die Gruppe in der IDE öffnen, Win32 und Debug wählen und alle Projekte bauen. Die Abhängigkeiten der Gruppe legen
die Reihenfolge fest.

| Ausgabe | Ordner |
|---|---|
| BPLs | `Output\Win32\Debug\Bpl` |
| DCPs | `Output\Win32\Debug\Dcp` |
| DCUs | `Output\Win32\Debug\Dcu\<Projekt>` |
| Testprogramm | `Output\Win32\Debug\Bin` |

**Kommandozeile:** Der Kommandozeilen-Compiler (`dcc32`, MSBuild) ist in den Editionen Community und Starter von
Delphi gesperrt. Mit diesen Editionen die Gruppe in der IDE bauen.

Ist dpcc in derselben IDE installiert, entlädt die IDE das Plugin beim Bauen. Nach dem Bauen die IDE neu starten.

Build-Ausgaben gehören nicht ins Repository (`.gitignore`: `Output/`, `*.dcu`, `*.bpl`, `*.exe` …).

## Testen

`Tests\dpcc.Completion.Tests.dproj` ist ein DUnitX-Konsolenprogramm. Nach dem Bauen:

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
| `Tests\IDE` | Plugin-Seite ohne ToolsAPI: Ablauf der Liste, Rangfolge, Favoriten, Mengenmodus, Platzhalter, Einstellungen, Texte |
| `Tests\Application\Shell` | Hülle des Servers |
| `Tests\Common` | Speicher: Selbstmessung, Namen der `.dcp`, gemeinsamer Cache, Office-Typbibliotheken und WinRT, Freigabe nach dem Ende des Servers, Dokumente, Namens- und Verweistabellen, Signaturen im Cache, Cache-Format 34, Katalog, Nachladen und Verdrängen, Nutzungsstatistik, Suche über nicht geladene Units, geschützte Units, Wiederverwendung der Verweistabellen, gleichzeitiges Nachladen, Anhängen an den Cache |
| `Tests\Memory` | Messprogramm für den Speicher (Kategorie `Benchmark`) |
| `Tests\Support` | Hilfen: feste Datenquelle, Leck-Überwachung |

Die Tests linken die DCUs der Packages statisch. Teile mit ToolsAPI (`dpcc.IDE.Base`) lassen sich nur in der IDE
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
| `DPCC_MEMBENCH_PINNED`, `DPCC_MEMBENCH_PINNEDUNITS`, `DPCC_MEMBENCH_PINNEDCOUNT` | Vervollständigungen auf zufällige Units (0), nachdem eine Projekt-Unit große Units in ihren `uses` nennt und lädt: kommagetrennte Namen bzw. die größten Dateien der Bibliothek (80). Zeile „[pinned]“ mit Nachladen und Verdrängen |
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

1. Feld, Vorgabe, Grenzen und Lesen/Schreiben im passenden Record, etwa `dpcc.Core.Settings.Plugin.Completion`
   (`Defaults`, `Normalize`, `Exchange`), und die Eigenschaft in `TDpccPluginSettings`
   (`dpcc.Core.Settings.Plugin`).
2. Eintrag im Katalog `dpcc.Core.Settings.PluginSchemaData` mit `x-key`, `x-area` und `x-page`. Die Datei wird von
   Hand gepflegt.
3. Sichtbarkeit: `dpcc.Core.Settings.CompletionView` zeigt die Seiten (`x-page`) „Vervollständigung“, „Einfügen“
   und „Hints“ ganz. Von anderen Seiten zeigt es nur einzelne Schlüssel: den Hauptschalter `completion.enabled`
   (Bereich „Allgemein“, `cPluginKeys`) und alle Schlüssel `hints.*`. Den Knopf „Index neu aufbauen“ im Bereich
   „Allgemein“ setzt die Seite selbst. Eine neue Option auf einer anderen Seite muss in `cPluginKeys` stehen.
4. Bedienelement im Teil der Seite, etwa `dpcc.UI.Settings.Page.Completion`, mit `BindCheck('<Registry-Name>', …)`.
5. Beschriftung deutsch und englisch in `dpcc.UI.Settings.Strings`.
6. Test.

## Beitragen

Das Repository liegt unter <https://github.com/nrodear/DelphiCodeCompletion>. Fehler und Vorschläge als Issue,
Änderungen als Pull Request.

Vor einem Pull Request:

- die ganze Gruppe baut ohne Fehler;
- die Tests laufen grün (`--exclude:Benchmark`);
- neue Benutzertexte stehen deutsch und englisch da;
- die Dokumentation unter `docs` ist angepasst, wenn sich Bedienung oder Optionen ändern.

Lizenz: MIT, siehe [LICENSE](../../LICENSE).
