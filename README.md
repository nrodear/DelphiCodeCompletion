# dpcc – Delphi Pascal Code Completion

Version 0.1.0

dpcc ist ein Plugin (Design-Time-Package) für die Delphi-IDE. Es bringt eine eigene Code-Vervollständigung
mit, die im IDE-Prozess einen eigenen Index über Projekt, Suchpfade und Bibliothek aufbaut.

## Funktionen

- **Vervollständigung mit Strg+Leertaste**: schlichte Liste der passenden Bezeichner (Art, Name, Signatur).
  Steht ein Bezeichner in einer Unit, die noch nicht im `uses`-Abschnitt
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
6. `dpcc.Core` (Logik des Plugins, ohne VCL und ToolsAPI)
7. `dpcc.UI` (VCL-Oberfläche des Plugins)
8. `dpcc.IDE.Base` (das Plugin: Anbindung an die IDE)
9. `dpcc.Completion.Tests` (Testprogramm)

Die Ausgabe landet unter `Output\Win32\Debug` (BPLs in `Bpl`, das Testprogramm in `Bin`).

## Installieren

1. In der IDE über **Komponenten › Packages installieren** die Datei
   `Output\Win32\Debug\Bpl\dpcc.IDE.Base370.bpl` hinzufügen.
2. `dpcc.IDE.Base370.bpl` braucht zur Laufzeit die sieben Laufzeit-BPLs `dpcc.Text`, `dpcc.WinBase`,
   `dpcc.Common`, `dpcc.Windows`, `dpcc.Server`, `dpcc.Core` und `dpcc.UI` (je `.bpl`, ohne Versionsendung).
   Installiert wird nur `dpcc.IDE.Base370.bpl`; die übrigen lädt die IDE mit. Windows sucht diese BPLs nicht
   im Ordner der Plugin-BPL, sondern über den PATH. Der Ordner `Output\Win32\Debug\Bpl` muss deshalb im PATH
   der IDE stehen.

### PATH der IDE setzen

Der Eintrag gehört in die PATH-Überschreibung der IDE, nicht in den Windows-PATH. Beispiel, wenn das Repo unter
`D:\src\DelphiCodeCompletion` liegt:

```
D:\src\DelphiCodeCompletion\Output\Win32\Debug\Bpl;$(PATH)
```

**Von Hand in der IDE:**

1. **Tools › Optionen › IDE › Umgebungsvariablen** öffnen.
2. Unter **Benutzerdefinierte Überschreibungen** auf **Neu** klicken (oder einen vorhandenen Eintrag `PATH`
   bearbeiten).
3. Variable `PATH`, Wert: der BPL-Ordner vorne, danach `;$(PATH)` (siehe Beispiel). Ein bestehender Wert bleibt
   erhalten, der BPL-Ordner wird nur vorangestellt.
4. Mit OK schließen und die IDE neu starten.

Die IDE speichert die Überschreibung in der Registry unter
`HKCU\Software\Embarcadero\BDS\37.0\Environment Variables`, Wert `PATH`.

**Per Skript:** `Tools\IdePath.ps1` prüft und setzt denselben Eintrag (aus dem Repo-Ordner aufrufen, die IDE
vorher schließen):

```powershell
powershell -NoProfile -File Tools\IdePath.ps1                 # Zustand anzeigen
powershell -NoProfile -File Tools\IdePath.ps1 -Action Add     # BPL-Ordner vor $(PATH) eintragen
powershell -NoProfile -File Tools\IdePath.ps1 -Action Remove  # Eintrag wieder entfernen
```

`-Action Add` sichert den bisherigen Wert unter `HKCU\Software\dpcc\IdePlugin`. Der Eintrag wirkt beim nächsten
Start der IDE.

Die Optionen stehen unter **Tools › Optionen › Drittanbieter › dpcc**.

## Tests

`Tests\dpcc.Completion.Tests.dproj` ist ein DUnitX-Konsolenprogramm (DUnitX gehört zu RAD Studio). Nach dem
Bauen:

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --exclude:Benchmark --exitbehavior:Continue
```

## Lizenz

MIT, siehe [LICENSE](LICENSE).
