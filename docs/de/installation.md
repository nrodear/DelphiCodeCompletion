Deutsch | [English](../en/installation.md) | [Français](../fr/installation.md)

# Installation

[Übersicht](index.md) › Installation

## Voraussetzungen

- Delphi 13 / RAD Studio 37.0. Für Delphi 12 / RAD Studio 23.0 siehe [Bauen für Delphi 12](#bauen-für-delphi-12).
- Plattform Win32. Die IDE ist ein 32-Bit-Prozess, das Plugin ist deshalb ein Win32-Package.
- Der Quelltext von dpcc. Es gibt keine fertigen BPLs; dpcc wird aus der Projektgruppe gebaut.

## Bauen

1. `dpcc_d13.groupproj` in der IDE öffnen.
2. Plattform Win32, Konfiguration Debug.
3. Alle Projekte der Gruppe bauen. Die Reihenfolge ergibt sich aus den Abhängigkeiten der Gruppe.

Die Ausgabe liegt unter `Output\Win32\Debug`:

| Ordner | Inhalt |
|---|---|
| `Bpl` | die acht BPLs mit der Endung `370` (Package-Version von Delphi 13), darunter das Plugin `dpcc.IDE.Base370.bpl` |
| `Dcp` | die DCP-Dateien der Packages |
| `Dcu` | die DCUs, je Projekt ein Unterordner |
| `Bin` | das Testprogramm `dpcc.Completion.Tests.exe` |

Der Kommandozeilen-Compiler (`dcc32`, MSBuild) ist in den Editionen Community und Starter gesperrt; dort in der IDE
bauen. Mehr dazu unter [Entwicklung](development.md).

### Bauen für Delphi 12

Für Delphi 12 (RAD Studio 23.0) gibt es die Gruppe `dpcc_d12.groupproj` mit denselben acht Packages, ohne das
Testprogramm: Die Tests laufen nur unter Delphi 13.

1. `dpcc_d12.groupproj` in der IDE von Delphi 12 öffnen.
2. Plattform Win32, Konfiguration **D12** für alle acht Projekte (**Projekt › Konfigurationsverwaltung**).
3. Alle Projekte der Gruppe bauen.

Die Konfiguration D12 erbt alle Einstellungen von Debug und baut in einen eigenen Ordner (`Output\Win32\D12`). So
überschreiben sich die Dateien der beiden Versionen nicht. Delphi 12 nie mit der Konfiguration Debug bauen: Es
schreibt sonst in die Ordner von Delphi 13 (dann `dpcc_d13.groupproj` unter Delphi 13 neu bauen). Mehr dazu unter
[Entwicklung](development.md).

| | Delphi 13 | Delphi 12 |
|---|---|---|
| Gruppe | `dpcc_d13.groupproj` | `dpcc_d12.groupproj` |
| Konfiguration | Debug | D12 |
| Ausgabe | `Output\Win32\Debug` | `Output\Win32\D12` |
| Plugin | `dpcc.IDE.Base370.bpl` | `dpcc.IDE.Base290.bpl` |
| übrige BPLs | `dpcc.Text370.bpl` … `dpcc.UI370.bpl` | `dpcc.Text290.bpl` … `dpcc.UI290.bpl` |
| PATH der IDE | `…\Output\Win32\Debug\Bpl` | `…\Output\Win32\D12\Bpl` |
| Registry der IDE | `HKCU\Software\Embarcadero\BDS\37.0` | `HKCU\Software\Embarcadero\BDS\23.0` |
| `Tools\IdePath.ps1` | ohne `-BdsVersion` | `-BdsVersion 23.0` |
| Tests | ja | nein |

Installieren und PATH wie unten, nur mit den Namen und Ordnern aus der Spalte Delphi 12: In der IDE von Delphi 12
`Output\Win32\D12\Bpl\dpcc.IDE.Base290.bpl` hinzufügen (die IDE trägt es unter
`HKCU\Software\Embarcadero\BDS\23.0\Known Packages` ein) und `…\Output\Win32\D12\Bpl` in den PATH der
IDE von Delphi 12 setzen.

## Installieren

1. In der IDE **Komponenten › Packages installieren** öffnen.
2. **Hinzufügen** wählen und `Output\Win32\Debug\Bpl\dpcc.IDE.Base370.bpl` öffnen.
3. Die IDE zeigt das Package mit der Beschreibung „dpcc (Code Insight-Manager)“.

Installiert wird nur `dpcc.IDE.Base370.bpl`. Es braucht zur Laufzeit sieben weitere BPLs (unter Delphi 12 mit der
Endung `290` statt `370`):

| BPL | Aufgabe |
|---|---|
| `dpcc.Text370.bpl` | Texthilfen, nur RTL |
| `dpcc.WinBase370.bpl` | RTL und Windows-API |
| `dpcc.Common370.bpl` | Parser, Index, LSP-Teile, ohne Windows und VCL |
| `dpcc.Windows370.bpl` | Windows-spezifische Teile, ohne VCL |
| `dpcc.Server370.bpl` | der Completion-Server, läuft im IDE-Prozess |
| `dpcc.Core370.bpl` | Logik des Plugins, ohne VCL und ToolsAPI |
| `dpcc.UI370.bpl` | VCL-Oberfläche des Plugins |

Die IDE lädt diese BPLs mit. Windows sucht sie aber nicht im Ordner der Plugin-BPL, sondern über den PATH.
Der Ordner `Output\Win32\Debug\Bpl` muss deshalb im PATH der IDE stehen.

## PATH der IDE setzen

Der Eintrag gehört in die PATH-Überschreibung der IDE, nicht in den PATH von Windows. Die IDE speichert die
Überschreibung in der Registry unter `HKCU\Software\Embarcadero\BDS\37.0\Environment Variables`, Wert `PATH`.

Beispiel, wenn das Repo unter `D:\src\DelphiCodeCompletion` liegt:

```
D:\src\DelphiCodeCompletion\Output\Win32\Debug\Bpl;$(PATH)
```

### Von Hand in der IDE

1. **Tools › Optionen › IDE › Umgebungsvariablen** öffnen.
2. Unter **Benutzerdefinierte Überschreibungen** auf **Neu** klicken oder einen vorhandenen Eintrag `PATH`
   bearbeiten.
3. Variable `PATH`. Wert: der BPL-Ordner vorne, danach `;$(PATH)`. Ein vorhandener Wert bleibt erhalten; der
   BPL-Ordner wird nur vorangestellt.
4. Mit OK schließen und die IDE neu starten.

### Per Skript

`Tools\IdePath.ps1` prüft und setzt denselben Eintrag. Aus dem Repo-Ordner aufrufen. Die IDE vorher schließen;
Änderungen wirken erst beim nächsten Start der IDE.

```powershell
powershell -NoProfile -File Tools\IdePath.ps1                 # Zustand anzeigen
powershell -NoProfile -File Tools\IdePath.ps1 -Action Add     # BPL-Ordner eintragen
powershell -NoProfile -File Tools\IdePath.ps1 -Action Remove  # Eintrag wieder entfernen
```

| Aktion | Wirkung |
|---|---|
| `Status` (Vorgabe) | Zeigt den PATH-Wert, den BPL-Ordner, jede erwartete BPL mit Datum, die installierten dpcc-Packages (Known Packages) und laufende IDE-Instanzen. Ändert nichts. |
| `Check` | Wie `Status`, aber nur die Ergebniszeile. Für Skripte. |
| `Add` | Trägt den BPL-Ordner ein: vor `$(PATH)`, wenn der Wert `$(PATH)` enthält, sonst am Ende; ohne Wert als `<Ordner>;$(PATH)`. Sichert den bisherigen Wert unter `HKCU\Software\dpcc\IdePlugin`, Wert `PathOverrideBackup`. |
| `Remove` | Entfernt den BPL-Ordner aus dem PATH-Wert. Andere Teile des Werts bleiben. Die Sicherung spielt es nicht zurück. |

| Parameter | Vorgabe | Bedeutung |
|---|---|---|
| `-Action` | `Status` | `Status`, `Check`, `Add` oder `Remove` |
| `-BdsVersion` | `37.0` | Version der IDE in der Registry; `23.0` für Delphi 12 |
| `-BplDir` | `Output\Win32\Debug\Bpl` im Repo, mit `-BdsVersion 23.0` `Output\Win32\D12\Bpl` | anderer BPL-Ordner |

Exit-Code von `Status` und `Check`:

| Code | Bedeutung |
|---|---|
| 0 | Eintrag vorhanden, alle BPLs da |
| 1 | Eintrag fehlt; Abhilfe `-Action Add` |
| 2 | BPL-Ordner oder BPLs fehlen; erst die Gruppe bauen |

## Prüfen, ob dpcc geladen ist

- Der Startbildschirm und der Info-Dialog der IDE nennen „dpcc 0.1.0“ (nur Text, ohne Bild).
- Unter **Tools › Optionen › Drittanbieter** steht der Knoten **dpcc**.
- Das Protokoll `%LOCALAPPDATA%\dpcc\Logs\dpcc.log` enthält die Zeile „dpcc angemeldet (Code Completion)“.
- In einer `.pas`-Datei öffnet Strg+Leertaste die Liste von dpcc. Sie zeigt je Zeile die Art als Wort, den Namen
  fett und die Signatur.

## Beim ersten Start

- Den Server startet dpcc mit der ersten Anfrage, etwa mit Strg+Leertaste. Danach baut er den Index auf. Der
  erste Aufbau kann bei großen Installationen einige Minuten dauern, weil er auch die Bibliothek einliest. Danach
  kommt das meiste aus dem Cache. Siehe [Index und Cache](index-cache.md).
- Ist beim Start von Delphi DelphiLSP als Code-Insight-Anbieter gewählt (Vorgabe), schaltet dpcc sich aus. Zum
  Einschalten unter **Tools › Optionen › Drittanbieter › dpcc** den Hauptschalter setzen und mit **OK** schließen:
  dpcc stellt dann den Anbieter der IDE auf dpcc und die nötigen Schalter der IDE (Help Insight, Kurzhinweise,
  Verzögerung). Das wirkt nach dem Neustart von Delphi; das Meldungsfenster nennt es. Siehe
  [Einstellungen](settings.md#was-dpcc-an-der-ide-umstellt).

## Aktualisieren

1. Den neuen Stand holen.
2. Die Gruppe neu bauen (siehe oben).
3. Die IDE neu starten.

Baut man die Gruppe in der IDE, in der dpcc installiert ist, entlädt die IDE das Plugin dabei. dpcc meldet sich
dafür Schritt für Schritt ab. Ein Neustart der IDE danach ist der sichere Weg.

Ältere Stände bauten die sieben Laufzeit-Packages ohne Endung (`dpcc.Text.bpl` … `dpcc.UI.bpl`). Nach dem ersten
Neubau liegen diese Dateien noch im BPL-Ordner; das Plugin lädt sie nicht mehr, sie können weg.

## Deinstallieren

1. Damit dpcc den Anbieter und die Schalter der IDE zurückgibt: unter **Tools › Optionen › Drittanbieter › dpcc**
   den Hauptschalter „Code Insight von dpcc“ ausschalten, mit **OK** schließen und Delphi einmal neu starten. dpcc
   stellt dann den Anbieter zurück (Vorgabe DelphiLSP) und dreht seine Schalter zurück.
2. **Komponenten › Packages installieren** öffnen, „dpcc (Code Insight-Manager)“ wählen und **Entfernen**.
3. Die IDE schließen.
4. Den PATH-Eintrag entfernen: `powershell -NoProfile -File Tools\IdePath.ps1 -Action Remove` oder von Hand unter
   **Tools › Optionen › IDE › Umgebungsvariablen**.

Was danach noch liegt und von Hand gelöscht werden kann:

| Ort | Inhalt |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | Einstellungen, Merker für die IDE-Schalter, `PathOverrideBackup` |
| `%APPDATA%\dpcc` | `settings.json`, `usage.json` (Verlauf), `favorites.json` (Favoriten), aus älteren Versionen `settings-history.json` |
| `%LOCALAPPDATA%\dpcc` | `Logs` (Protokoll), `Index` (Index-Caches) |
| BPL-Ordner | `dpcc.IDE.Expert370.log`, falls das Diagnoseprotokoll an war |

Hat man Schritt 1 ausgelassen, bleibt eventuell dpcc als Anbieter eingetragen, und Help Insight, die Kurzhinweise und
der Wert-Tooltip der IDE bleiben aus. Dann in den Code-Insight-Optionen der IDE DelphiLSP wählen und die Schalter
wieder einschalten. Die Registry-Orte stehen unter
[Einstellungen](settings.md#was-dpcc-an-der-ide-umstellt).
