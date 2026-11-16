# dpcc – Delphi Pascal Code Completion

Version 0.1.0

dpcc ist ein Plugin (Design-Time-Package) für die Delphi-IDE. Es bringt eine eigene Code-Vervollständigung
mit, die im IDE-Prozess einen eigenen Index über Projekt, Suchpfade und Bibliothek aufbaut.

## Funktionen

- **Vervollständigung mit Strg+Leertaste**: Liste der passenden Bezeichner mit Detailpanel (Signatur, Unit,
  Kurztext aus der XML-Dokumentation). Steht ein Bezeichner in einer Unit, die noch nicht im `uses`-Abschnitt
  steht, zeigt die Liste „+ Unit“ und trägt die Unit beim Übernehmen ein.
- **Parameterhilfe mit Strg+Umschalt+Leertaste**: Signaturen der aufgerufenen Routine, der aktuelle Parameter
  ist hervorgehoben.
- **Hover**: Tooltip über einem Bezeichner mit Deklaration, Fundort und XMLDoc-Kommentar; beim Debuggen
  zusätzlich der Wert der Variablen.
- **FieldByName-Vervollständigung**: Feldnamen in `FieldByName('…')` und Komponenten aus den Formularen (DFM)
  des Projekts.

Die Liste, die nach einem „.“ von selbst aufgeht, kommt weiterhin von DelphiLSP. Strg+Leertaste und
Strg+Umschalt+Leertaste übernimmt dpcc in den Dateien, die es bedient.

## Voraussetzungen

- Delphi 13 / RAD Studio 37.0
- Plattform Win32 (die IDE ist ein 32-Bit-Prozess)

## Bauen

Die Projektgruppe `dpcc_d13.groupproj` in der IDE öffnen und alle Projekte bauen (Win32, Debug). Die
Reihenfolge ergibt sich aus den Abhängigkeiten der Gruppe:

1. `dpcc.Text`
2. `dpcc.WinBase`
3. `dpcc.Common`
4. `dpcc.Windows`
5. `dpcc.Server`
6. `dpcc.IDE.Base` (das Plugin)
7. `dpcc.Completion.Tests` (Testprogramm)

Die Ausgabe landet unter `Output\Win32\Debug` (BPLs in `Bpl`, das Testprogramm in `Bin`).

## Installieren

1. In der IDE über **Komponenten › Packages installieren** die Datei
   `Output\Win32\Debug\Bpl\dpcc.IDE.Base370.bpl` hinzufügen.
2. `dpcc.IDE.Base370.bpl` braucht zur Laufzeit die übrigen dpcc-BPLs. Der Ordner `Output\Win32\Debug\Bpl`
   muss deshalb im PATH der IDE stehen. Das Skript `Tools\IdePath.ps1` prüft und setzt den Eintrag in den
   Umgebungsvariablen der IDE:

   ```powershell
   powershell -NoProfile -File Tools\IdePath.ps1              # Zustand anzeigen
   powershell -NoProfile -File Tools\IdePath.ps1 -Action Add  # Eintrag setzen
   ```

   Der Eintrag wirkt beim nächsten Start der IDE.

Die Optionen stehen unter **Tools › Optionen › Drittanbieter › dpcc**.

## Tests

`Tests\dpcc.Completion.Tests.dproj` ist ein DUnitX-Konsolenprogramm (DUnitX gehört zu RAD Studio). Nach dem
Bauen:

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --exclude:Benchmark --exitbehavior:Continue
```

## Lizenz

MIT, siehe [LICENSE](LICENSE).
