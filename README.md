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

dpcc läuft in einer von zwei Betriebsarten, je nach dem Code-Insight-Anbieter, der in der IDE für Delphi gewählt
ist. In der Betriebsart dpcc (Hauptschalter an, Anbieter dpcc) kommen auch die Liste nach „.“ und die Parameterhilfe
bei „(“ und „,“ von dpcc. In der Betriebsart IDE (Anbieter DelphiLSP, Vorgabe) ist dpcc aus. Der Hauptschalter
stellt den Anbieter um; das wirkt nach dem Neustart von Delphi. Details:
[Bedienung](docs/de/usage.md#zusammenspiel-mit-delphilsp) und
[Einstellungen](docs/de/settings.md#was-dpcc-an-der-ide-umstellt).

## Voraussetzungen

- Delphi 13 / RAD Studio 37.0; für Delphi 12 / RAD Studio 23.0 gibt es eine eigene Projektgruppe ohne Tests
  (siehe [Bauen für Delphi 12](docs/de/installation.md#bauen-für-delphi-12))
- Plattform Win32 (die IDE ist ein 32-Bit-Prozess)

## Bauen

Die Projektgruppe `dpcc_d13.groupproj` in der IDE öffnen und alle Projekte bauen (Win32, Debug). Die Ausgabe landet
unter `Output\Win32\Debug` (BPLs in `Bpl`, das Testprogramm in `Bin`). Für Delphi 12 ist es
`dpcc_d12.groupproj` mit der Konfiguration D12 (nie Debug) und der Ausgabe unter `Output\Win32\D12`. Mehr dazu:
[Entwicklung](docs/de/development.md).

## Installieren

1. In der IDE über **Komponenten › Packages installieren** die Datei
   `Output\Win32\Debug\Bpl\dpcc.Plugin370.bpl` hinzufügen.
2. `dpcc.Plugin370.bpl` braucht zur Laufzeit die sieben BPLs `dpcc.Text370`, `dpcc.WinBase370`,
   `dpcc.Common370`, `dpcc.Windows370`, `dpcc.Server370`, `dpcc.Core370` und `dpcc.UI370`. Windows sucht sie
   über den PATH. Der Ordner `Output\Win32\Debug\Bpl` muss deshalb im PATH der IDE stehen.
3. Unter Delphi 12 heißen die Dateien `…290.bpl` (Plugin `dpcc.Plugin290.bpl`), der Ordner ist
   `Output\Win32\D12\Bpl`.

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

### Setup

Aus den gebauten BPLs beider Gruppen erzeugt `Tools\Build-Setup.ps1` mit Inno Setup 6 das Setup
`installer\Output\dpccSetup-<Version>.exe`. Es installiert dpcc für den aktuellen Benutzer in Delphi 12 und/oder 13,
ohne Administratorrechte, und setzt Known Packages und PATH der IDE selbst. Siehe
[Mit dem Setup installieren](docs/de/installation.md#mit-dem-setup-installieren).

Die Optionen stehen unter **Tools › Optionen › Drittanbieter › dpcc**: [Einstellungen](docs/de/settings.md).
Wenn etwas nicht geht: [Fehlersuche](docs/de/troubleshooting.md).

## Tests

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --exclude:Benchmark --exitbehavior:Continue
```

Siehe [Entwicklung](docs/de/development.md#testen). Die Tests gibt es nur für Delphi 13.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
