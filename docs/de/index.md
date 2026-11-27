Deutsch | [English](../en/index.md) | [Français](../fr/index.md)

# dpcc – Dokumentation

dpcc (Delphi Pascal Code Completion) ist ein Plugin für die Delphi-IDE. Es bringt eine eigene
Code-Vervollständigung, eine Parameterhilfe und einen Tooltip über Bezeichnern mit. Dafür baut es im
IDE-Prozess einen eigenen Index über Projekt, Suchpfade und Bibliothek auf.

Version 0.1.0, für Delphi 13 (RAD Studio 37.0), Win32. Für Delphi 12 (RAD Studio 23.0) gibt es eine eigene
Projektgruppe ohne Tests, siehe [Bauen für Delphi 12](installation.md#bauen-für-delphi-12).

## Für Anwender

| Seite | Inhalt |
|---|---|
| [Installation](installation.md) | Voraussetzungen, Bauen, Installieren, PATH der IDE, Aktualisieren, Deinstallieren |
| [Bedienung](usage.md) | Tasten, die Liste, was sie anbietet, Hover, Parameterhilfe, Platzhalter, Mengenmodus, Favoriten |
| [Einstellungen](settings.md) | Jede Option der Seite Tools › Optionen › Drittanbieter › dpcc, Ablage, was dpcc an der IDE umstellt |
| [Index und Cache](index-cache.md) | Was im Index steht, wo der Cache liegt, Neuaufbau, Aufräumen |
| [Fehlersuche](troubleshooting.md) | Plugin lädt nicht, Liste fehlt, doppelte Tooltips, Protokolle |
| [LSP-Server](lsp-server.md) | dpcc.LspServer.exe: eigenständiger Language Server über stdio, Betriebsart Server, Aufruf, Ablage, was er kann |

## Für Entwickler

| Seite | Inhalt |
|---|---|
| [Architektur](architecture.md) | Packages, Schichten, Server im IDE-Prozess, Ablauf einer Anfrage |
| [Entwicklung](development.md) | Bauen in der IDE, Tests, Konventionen, Beitragen |

## Kurz: was dpcc übernimmt

| Funktion | Auslöser | Von wem |
|---|---|---|
| Vervollständigung | Strg+Leertaste | dpcc |
| Parameterhilfe | Strg+Umschalt+Leertaste | dpcc |
| Tooltip über Bezeichnern | Maus verweilt über einem Bezeichner | dpcc |
| Liste, die nach „.“ von selbst aufgeht | Tippen von „.“ | dpcc, wenn es der Code-Insight-Anbieter ist (Betriebsart Plugin); sonst DelphiLSP (IDE), dann ist dpcc aus |

Die Tabelle gilt für die Betriebsart Plugin (Vorgabe). dpcc bedient Dateien mit den Endungen `.pas`, `.dpr`, `.dpk`
und `.inc`. In allen anderen Dateien und in der Betriebsart Aus bleibt die IDE zuständig. In der Betriebsart Server
zeigt die IDE ihre eigenen Fenster, die Antworten kommen von `dpcc.LspServer.exe` (siehe
[LSP-Server](lsp-server.md#betriebsart-server)).

## Lizenz

MIT, siehe [LICENSE](../../LICENSE).
