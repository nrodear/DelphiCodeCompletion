Deutsch | [English](README.en.md) | [Français](README.fr.md)

# dpcc – Delphi Pascal Code Completion

Version 0.1.0

dpcc ist ein Plugin (Design-Time-Package) für die Delphi-IDE. Es bringt eine eigene Code-Vervollständigung
mit, die im IDE-Prozess einen eigenen Index über Projekt, Suchpfade und Bibliothek aufbaut.

Ausführliche Dokumentation: [docs/de/index.md](docs/de/index.md).

## Funktionen

- **Vervollständigung mit Strg+Leertaste**: schlichte Liste der passenden Bezeichner (Art, Name, Signatur).
  Steht ein Bezeichner in einer Unit, die noch nicht im `uses`-Abschnitt steht, zeigt die Liste „+“ und den Namen
  der Unit (etwa „+ System.SysUtils“) und trägt die Unit beim Übernehmen ein.
- **Parameterhilfe mit Strg+Umschalt+Leertaste**: Signaturen der aufgerufenen Routine, der aktuelle Parameter
  ist hervorgehoben.
- **Hover**: Tooltip über einem Bezeichner mit Deklaration, Fundort und XMLDoc-Kommentar; beim Debuggen
  zusätzlich der Wert der Variablen.
- **FieldByName-Vervollständigung**: Feldnamen in `FieldByName('…')` und Komponenten aus den Formularen (DFM)
  des Projekts.

Die Liste, die nach einem „.“ von selbst aufgeht, kommt weiterhin von DelphiLSP. Strg+Leertaste und
Strg+Umschalt+Leertaste übernimmt dpcc in den Dateien, die es bedient. Details: [Bedienung](docs/de/usage.md).

## Voraussetzungen

- Delphi 13 / RAD Studio 37.0
- Plattform Win32 (die IDE ist ein 32-Bit-Prozess)

## Bauen

Die Projektgruppe `dpcc_d13.groupproj` in der IDE öffnen und alle Projekte bauen (Win32, Debug). Die Ausgabe landet
unter `Output\Win32\Debug` (BPLs in `Bpl`, das Testprogramm in `Bin`). Mehr dazu:
[Entwicklung](docs/de/development.md).

## Installieren

1. In der IDE über **Komponenten › Packages installieren** die Datei
   `Output\Win32\Debug\Bpl\dpcc.IDE.Base370.bpl` hinzufügen.
2. `dpcc.IDE.Base370.bpl` braucht zur Laufzeit die sieben BPLs `dpcc.Text`, `dpcc.WinBase`, `dpcc.Common`,
   `dpcc.Windows`, `dpcc.Server`, `dpcc.Core` und `dpcc.UI`. Windows sucht sie über den PATH. Der Ordner
   `Output\Win32\Debug\Bpl` muss deshalb im PATH der IDE stehen.

### PATH der IDE setzen

Der Eintrag gehört in die PATH-Überschreibung der IDE (**Tools › Optionen › IDE › Umgebungsvariablen ›
Benutzerdefinierte Überschreibungen**), nicht in den Windows-PATH. Beispiel, wenn das Repo unter
`D:\src\DelphiCodeCompletion` liegt:

```
D:\src\DelphiCodeCompletion\Output\Win32\Debug\Bpl;$(PATH)
```

Oder per Skript, aus dem Repo-Ordner und bei geschlossener IDE:

```powershell
powershell -NoProfile -File Tools\IdePath.ps1                 # Zustand anzeigen
powershell -NoProfile -File Tools\IdePath.ps1 -Action Add     # BPL-Ordner eintragen
powershell -NoProfile -File Tools\IdePath.ps1 -Action Remove  # Eintrag wieder entfernen
```

Der Eintrag wirkt beim nächsten Start der IDE. Alle Schritte, Prüfen und Deinstallieren:
[Installation](docs/de/installation.md).

Die Optionen stehen unter **Tools › Optionen › Drittanbieter › dpcc**: [Einstellungen](docs/de/settings.md).
Wenn etwas nicht geht: [Fehlersuche](docs/de/troubleshooting.md).

## Tests

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --exclude:Benchmark --exitbehavior:Continue
```

Siehe [Entwicklung](docs/de/development.md#testen).

## Lizenz

MIT, siehe [LICENSE](LICENSE).
