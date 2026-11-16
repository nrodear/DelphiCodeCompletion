Deutsch | [English](../en/index-cache.md) | [Français](../fr/index-cache.md)

# Index und Cache

[Übersicht](index.md) › Index und Cache

Vervollständigung, Hover, Parameterhilfe und die Anzeige „+“ mit dem Namen einer fehlenden Unit (etwa
„+ System.SysUtils“) lesen aus einem Symbolindex. Den baut der Server von dpcc im IDE-Prozess auf. Er ist
unabhängig vom Index von DelphiLSP.

## Was im Index steht

Der Umfang ist fest:

- alle Projekte der geöffneten Projektgruppe, das aktive zuerst;
- alle Units der Suchpfade der Projekte;
- die Bibliotheks- und Suchpfade der Installation (RTL, VCL, Komponenten), ohne die Office-Typbibliotheken und WinRT
  (siehe [unten](#office-typbibliotheken-und-winrt)).

Dazu kommen:

- Konfiguration, Plattform, bedingte Symbole, Suchpfade und Unit-Namespaces der aktiven Konfiguration, auch
  ungespeicherte Änderungen. Makros wie `$(BDS)` in Pfaden setzt dpcc wie die IDE ein.
- die Typen der Packages, die in der IDE geladen sind, auch ohne Quelltext. dpcc meldet sie beim Start jeder
  Sitzung an den Server.

Der Index enthält Deklarationen, keine Verwendungen. Seine Speichergrenze ist fest (768 MB).

### Office-Typbibliotheken und WinRT

`$(BDS)\OCX\Servers` (Typbibliotheken von Excel, Word, Outlook und Access, dazu MSHTML) und
`$(BDS)\source\rtl\win\winrt` liest dpcc nicht vorab ein. Zusammen sind das gut 40 % der Symbole der Bibliothek und
rund 140 MB im Index, gebraucht werden sie selten.

- Über `uses` bleiben die Units erreichbar: Vervollständigung, Hover und Parameterhilfe kennen sie, sobald eine Unit
  sie einbindet.
- „+ Unit“ schlägt ihre Symbole nicht vor.
- Der Schalter „Office-Typbibliotheken und WinRT vorab indizieren“ auf der Seite **Allgemein** (`index.officeAndWinRt`
  in `settings.json`) nimmt sie wieder auf. Siehe [Einstellungen](settings.md#allgemein).
- Jede Stellung hat ihren eigenen Bibliotheks-Cache. Beim ersten Umschalten liest dpcc die Bibliothek einmal neu ein;
  danach kommt sie aus dem jeweiligen Cache. Beim Ausschalten nimmt der Server die Units sofort aus dem Index.

## Wann der Index entsteht

- Der Server startet mit der ersten Anfrage, etwa Strg+Leertaste, oder beim Einschalten des Hauptschalters.
- Dann baut er den Index auf. Das läuft im Hintergrund; die IDE wartet nicht darauf.
- Solange der Aufbau läuft, zeigt die Liste „eingeschränkt (Index wird aufgebaut)“ und kann unvollständig sein.
- Der erste Aufbau kann bei großen Installationen einige Minuten dauern, weil er die Bibliothek einliest. Danach
  kommt das meiste aus dem Cache.

## Änderungen

- Änderungen in der Projektgruppe prüft dpcc höchstens alle zwei Sekunden, Änderungen an Konfiguration und
  Optionen höchstens einmal je Sekunde.
- Gespeicherte Dateien meldet dpcc dem Server.
- Änderungen außerhalb der IDE: dpcc beobachtet die Ordner der Projekte (das Git-Arbeitsverzeichnis, sonst den
  Projektordner). Gesammelte Änderungen gehen mit der nächsten Anfrage an den Server.
- Offene Formulare gehen mit ihrem aktuellen Stand aus dem Designer an den Server, nicht von der Platte.

## Cache

Der Cache liegt unter `%LOCALAPPDATA%\dpcc\Index`:

| Pfad | Inhalt |
|---|---|
| `Index\<IDE-Version>\<Hash>\index-<Format>.dpccidx` | Cache eines Projekts |
| `Index\<IDE-Version>\Bibliothek\<Hash>\index-<Format>.dpccidx` | Cache der Bibliothek, getrennt vom Projekt |
| `…\<cache>.lock` | Sperre; nur die erste Instanz schreibt den Cache, weitere lesen ihn nur |
| `…\projekt.txt` | Projektdatei, zu der der Cache gehört |
| `…\benutzt.stamp` | Zeitpunkt der letzten Benutzung |

Die Formatversion steht im Dateinamen. So stören sich verschiedene Versionen von dpcc nicht gegenseitig.

Die Umgebungsvariable `DPCC_CACHE_ROOT` verlegt den ganzen Ordner `%LOCALAPPDATA%\dpcc` des Servers (Caches und
Diagnoselog), etwa für Tests mit einer Kopie des Caches. Ohne sie gilt `LOCALAPPDATA` aus der Umgebung des Prozesses.

Hält der Index schon jede Unit des Bibliotheks- bzw. Suchpfad-Caches im selben Stand, liest ein neuer Aufbau den
Cache nicht noch einmal (etwa nach dem Speichern einer `.dproj`). Das Diagnoselog meldet das als
„index project#n cache skipped library“.

### Aufräumen

Der Server räumt den Cache-Ordner selbst auf:

| Regel | Vorgabe | Schlüssel in `settings.json` |
|---|---|---|
| Caches gelöschter Projekte löschen | an | `index.removeOrphans` (`true`/`false`) |
| Caches löschen, die so viele Tage nicht benutzt wurden | 14 | `index.cacheMaxAgeDays` (0 bis 3650; 0 = aus) |
| Höchstgröße des Cache-Ordners in MB, älteste zuerst | 1024 | `index.cacheMaxMb` (0 = ohne Grenze) |

Liegt die Herkunft eines Caches auf einem Laufwerk, das gerade fehlt (USB, Netz), bleibt er.

## Index neu aufbauen

**Tools › Optionen › Drittanbieter › dpcc › Allgemein › Index neu aufbauen**:

1. dpcc fragt nach: „Alle Index-Caches löschen und den Index neu aufbauen? Der erste Aufbau kann einige Minuten
   dauern.“
2. Eine laufende Sitzung hält es an, löscht alle Index-Caches, die nicht gesperrt sind, und startet die Sitzung neu.
3. Die Seite meldet das Ergebnis:
   - „n Index-Caches gelöscht; der Index wird neu aufgebaut.“ – die Sitzung lief und ist neu gestartet;
   - „n Index-Caches gelöscht; der Index wird beim nächsten Start der Code Completion neu aufgebaut.“ – es lief
     keine Sitzung; der Knopf startet keinen Server;
   - „Index-Cache konnte nicht gelöscht werden: …“ – Fehler.

Den Cache von Hand löschen geht auch: die IDE schließen und `%LOCALAPPDATA%\dpcc\Index` löschen.

## Units vom Index ausschließen

In `dpcc.json` im Projektordner schließt `index.exclude` Dateien aus. Die Muster gelten für den vollen Pfad: `*` ohne
Trenner, `**` über Ordner, `?` ein Zeichen, ohne Groß-/Kleinschreibung.

```json
{
  "index": {
    "exclude": ["**/Demos/**", "**/Generated/*.pas"]
  }
}
```

## Einstellungsdateien des Servers

| Datei | Ort | Gilt für |
|---|---|---|
| `settings.json` | `%APPDATA%\dpcc` | alle Projekte (persönlich, rechnerbezogen) |
| `dpcc.json` | Projektordner | dieses Projekt (für das Team, gehört ins Repository) |

Jeder Schlüssel hat genau einen Ort. Ein Schlüssel am falschen Ort wirkt nicht. In `dpcc.json` ignoriert der Server
Zugangsdaten und absolute Pfade. Er beobachtet beide Dateien selbst; Änderungen wirken ohne Neustart.

Die Index-Schlüssel `index.projectGroup`, `index.searchPaths`, `index.libraryPaths`, `index.usages` und
`memoryBudgetMb` liest der Server noch, damit ältere Dateien ohne Warnung laden. Sie wirken nicht mehr; der Umfang
ist fest. Nur `index.officeAndWinRt` wirkt (siehe [oben](#office-typbibliotheken-und-winrt)).
