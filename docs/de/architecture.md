Deutsch | [English](../en/architecture.md) | [Français](../fr/architecture.md)

# Architektur

[Übersicht](index.md) › Architektur

## Überblick

dpcc besteht aus einem Plugin (Design-Time-Package) und einem Completion-Server. Beide laufen im Prozess der IDE.
Sie sprechen das Language Server Protocol (LSP) über JSON-RPC. Die Verbindung sind zwei Speicher-Pipes; einen
eigenen Server-Prozess gibt es nicht.

```
IDE (bds.exe)
 ├─ dpcc.Plugin370.bpl        Plugin: Open Tools API, Tasten, Editor, Optionsseite
 │    ├─ dpcc.UI370.bpl       Fenster: Liste, Tooltip, Parameterhilfe, Optionsseite
 │    └─ dpcc.Core370.bpl     Logik: LSP-Client, Ablauf, Rangfolge, Einstellungen
 │          │  LSP über JSON-RPC, zwei Speicher-Pipes
 │          ▼
 └─ dpcc.Server370.bpl        Completion-Server auf eigenem Thread
      └─ dpcc.Common370.bpl   Parser, Namensauflösung, Index, LSP-Funktionen
```

Der Hauptthread der IDE wartet nie auf den Server. Schreiben legt eine Nachricht nur in die Pipe; ein Lese-Thread
reicht die Antworten an den Client weiter, Ergebnisse kommen über eine eigene Warteschlange in den Hauptthread.

## Packages

| Package | `requires` (außer RTL/VCL) | Aufgabe |
|---|---|---|
| `dpcc.Text` | – | Texthilfen ohne Windows: Zeilen, Zeichen, Kodierung, unscharfer Vergleich, JSON, URIs, Version |
| `dpcc.WinBase` | – | Prozesshilfen über die Windows-API |
| `dpcc.Common` | Text | Sprachkern und Server-Funktionen, frei von Windows und VCL |
| `dpcc.Windows` | WinBase, Common | Windows-spezifische Adapter: Dateibeobachter, Pfade, Delphi-Installation, Debug-Ausgabe |
| `dpcc.Server` | Text, WinBase, Common, Windows | Hülle des Completion-Servers; Quellen in `Application\Source\Shell` |
| `dpcc.Core` | Text, WinBase, Common, Windows, Server | Logik des Plugins, ohne VCL und ToolsAPI |
| `dpcc.UI` | Text, WinBase, Common, Windows, Server, Core; `vcl` | VCL-Oberfläche, ohne ToolsAPI |
| `dpcc.Plugin` | alle obigen; `vcl`, `vclwinx`, `designide` | das Plugin; einziges Design-Time-Package |
| `dpcc.Completion.Tests` | linkt die DCUs | DUnitX-Testprogramm |

Alle Packages außer `dpcc.Plugin` sind Laufzeit-Packages (`{$RUNONLY}`). Alle acht tragen die Package-Version als
Endung (`{$LIBSUFFIX AUTO}`: `370` unter Delphi 13, `290` unter Delphi 12), die Namen in `requires` nicht. Die
Reihenfolge in `dpcc_d13.groupproj` (Delphi 12: `dpcc_d12.groupproj`, ohne Tests) folgt den Abhängigkeiten.

### Regeln der Schichten

- Abhängigkeiten zeigen nur nach unten in der Tabelle.
- `dpcc.Common` und `dpcc.Text` brauchen weder Windows-Units noch VCL.
- `dpcc.Core` kennt weder VCL noch ToolsAPI. Was es von der IDE braucht, bekommt es über Schnittstellen und Haken,
  die `dpcc.Plugin` setzt.
- `dpcc.UI` kennt die VCL, aber nicht die ToolsAPI.
- Nur `dpcc.Plugin` spricht mit der IDE.

## dpcc.Common

| Ordner | Inhalt |
|---|---|
| `Pascal` | Lexer, Parser, Syntaxbaum, Präprozessor, Include-Dateien, XMLDoc, Formatroutinen |
| `Semantics` | Namensauflösung: Typen, Überladungen, Generics, Class Helper, `with`, Sichtbarkeit |
| `Index` | Symbolindex mit Katalog aller Units, bedarfsweisem Laden und Verdrängen der Bibliothek, Nutzungsstatistik; Unit-Suche; Cache auf der Platte (Format 35: Block je Unit, Verzeichnis am Ende); Extractor mit Zieltypen, Attributen, DLL-Angaben und Einschränkungen in den Direktiven; volle Signatur aus der Quelle (`TIndexFiles.SourceSignature`) |
| `Projects` | Lesen von `.dproj`, Projektgruppen und Packages; Unit-Suche |
| `Dfm` | Formulardateien |
| `Lsp` | Vervollständigung, Hover, Parameterhilfe, Dokumentabgleich, Lebenszyklus |
| `JsonRpc` | Nachrichten, Transport, Dispatcher, Worker-Pool, Watchdog |
| `Configuration` | `settings.json` und `dpcc.json`: Lesen, Orte der Schlüssel, Vorgaben |
| `Documents`, `Editing` | Dokumente, Kodierung, Textbausteine wie Postfix-Vorlagen und Feldnamen |

## Server (dpcc.Server)

Die Quellen liegen in `Application\Source\Shell`.

| Unit | Aufgabe |
|---|---|
| `Shell.Composition.InProcess` | startet den Server auf eigenem Thread im IDE-Prozess, verbindet die Speicher-Pipes, baut ihn in fester Reihenfolge ab |
| `Shell.Composition.CompletionServer` | Wurzel des Servers: verdrahtet Protokoll, Sitzung, Dokumente, Index, Vervollständigung, Hover und Parameterhilfe |
| `Shell.Composition.Configuration` | beobachtet `settings.json` und `dpcc.json` |
| `Shell.Workspace.*` | Arbeitsbereiche: Projekte laden, Index aufbauen, Cache sperren und aufräumen |

Der Server hat keine Diagnosen, keinen Compiler, keine Refactorings und keine Befehle; er dient nur der
Vervollständigung, dem Hover und der Parameterhilfe.

Hängt der Server beim Entladen, hält `Shell.Composition.InProcess` den Code von `dpcc.Server` und seinen
Abhängigkeiten bis zum Ende der IDE geladen. So springt kein Thread in entladenen Code.

## dpcc.Core

| Ordner | Inhalt |
|---|---|
| `Lsp` | LSP-Client, Sitzung (initialize, Dokumentabgleich, Anfragen), Adapter zum Server im Prozess, Absturzbehandlung |
| `Completion` | Ablauf der Liste (`TDpccCompletionController`), Filtern, Rangfolge, Favoriten, Verlauf, Mengenmodus, Platzhalter |
| `Hover`, `Signature`, `Documentation` | Inhalt von Tooltip und Parameterhilfe, XMLDoc-Darstellung |
| `Settings` | Plugin-Einstellungen (`TDpccPluginSettings`: genau die Werte der Seite, dazu zwei nur gelesene), Ablage in Registry und `settings.json` (`dpcc.Core.Settings.Scopes`), Aufbau der Optionsseite und fest eingestellte Werte (`dpcc.Core.Settings.CompletionView`), Betriebsart Aus/Plugin/Server je Version (`dpcc.Core.Settings.OperatingMode`), Wechsel der eigenen Fenster ohne Neustart |
| `Diagnostics` | Sicherung (`TDpccGuard`), Protokoll, Warteschlange zum Hauptthread, Abbau |
| `Localization` | Sprache der Texte |

## dpcc.UI

| Ordner | Inhalt |
|---|---|
| `Completion` | Liste (Popup), Zeichnen, Texte |
| `Hover` | Tooltip |
| `Signature` | Parameterhilfe |
| `Settings` | Optionsseite „dpcc“ |
| `Popup`, `Documentation` | gemeinsame Fensterbasis, Barrierefreiheit, XMLDoc-Ansicht |

## dpcc.Plugin

| Ordner | Inhalt |
|---|---|
| `Completion` | Wurzel `dpcc.IDE.Completion.Register`, Vervollständigung im Editor (Kette State → Open → Commit → Editor), Platzhalter, Favoriten, Verlauf, Speicher-Notifier |
| `CodeInsight` | Code-Insight-Manager (Kette State → Session → Commands → Crashes → Manager) |
| `Hover` | Tooltip im Editor, Werte über den Debugger |
| `Signature` | Parameterhilfe im Editor, Farben der Format-Platzhalter |
| `Forms` | Formulare aus dem Designer an den Server |
| `Projects` | Projektkontext aus der IDE |
| `Settings` | Anmeldung der Optionsseite |
| `Foundation` | Einstellungen in Registry und `settings.json`, IDE-Schalter, Tastatur-Hook, Editorzugriff, Startbildschirm, Umleitung von `DelphiLSP.exe` auf `dpcc.LspServer.exe` (Betriebsart Server) |

## Anmelden und Abbauen

`dpcc.IDE.Completion.Register` ist die Wurzel. `Register` meldet nacheinander an: Sicherung und Protokoll, Sprache,
Startbildschirm, Betriebsart (IDE-Kontext), Umleitung für die Betriebsart Server (`dpcc.IDE.Foundation.LspRedirect`,
siehe [LSP-Server](lsp-server.md#betriebsart-server)), Code-Insight-Manager, Tastenbindung, Formulare,
Speicher-Notifier, Wechsel der Betriebsart ohne Neustart, Optionsseite. Jeder Schritt läuft für sich; ein Fehler kostet nur diesen Schritt und steht im
Protokoll.

Den Abgleich der Betriebsart mit dem Code-Insight-Anbieter (Plugin: dpcc ist Anbieter; Aus und Server: DelphiLSP)
entscheidet `dpcc.Core.Settings.IdeCheck` ohne Registry
(`TDpccIdeContext.Plan`: Schreibaktionen und Merker, `TDpccIdeCheck.Evaluate`: Prüfung); gelesen wird in
`dpcc.IDE.Foundation.IdeSettingsCheck`, geschrieben in `dpcc.IDE.Foundation.InsightSwitch` (beim Start vor dem
Manager, nach OK im Optionsdialog, bei der Wahl im Code-Insight-Dialog der IDE über
`IOTACodeInsightManagerEnvOptions` und beim Beenden). Siehe [Einstellungen](settings.md#was-dpcc-an-der-ide-umstellt).

`Unregister` baut in umgekehrter Reihenfolge ab, ebenfalls Schritt für Schritt. Es läuft beim Zerstören des
Hauptfensters der IDE oder in der Finalisierung, je nachdem, was zuerst kommt. Am Ende steht die Zeile „dpcc entladen
in n ms …“ im Protokoll.

## Ablauf: Strg+Leertaste

1. Die Tastenbindung `TDpccCompletionKeys` fängt Strg+Leertaste ab. Bedient dpcc die Datei nicht, bleibt die Taste
   bei der IDE.
2. `TDpccCodeInsightManager.OpenCompletion` startet bei Bedarf Sitzung und Server.
3. `TDpccEditorCompletion` nimmt das Wort vor dem Cursor als Anfang und das Caret-Rechteck als Anker.
4. Die Sitzung schickt den aktuellen Editortext (beim ersten Mal `didOpen`, danach `didChange` mit dem geänderten
   Bereich) und dann `textDocument/completion`. Das geschieht für alle Quellen (Server, XMLDoc) gleichzeitig auf
   Arbeiter-Threads; der Hauptthread wartet beim Öffnen nicht darauf.
5. Der Server bestimmt den Kontext, prüft die Fälle der Vervollständigung in fester Reihenfolge und liefert Einträge,
   bei großen Listen in Teilen.
6. `TDpccCompletionController` filtert und sortiert lokal; das Popup aus `dpcc.UI` zeichnet nur die sichtbaren Zeilen.
7. Weitertippen filtert lokal. Gekürzte Listen fragt dpcc im Hintergrund neu an.
8. Übernehmen schreibt Name, `uses`-Eintrag und weitere Änderungen in einem Undo-Schritt. Hat der Eintrag einen
   Befehl, geht er im Hintergrund an den Server.

Hover und Parameterhilfe laufen genauso über die Sitzung (`textDocument/hover`, `textDocument/signatureHelp`). Den
Tooltip löst nicht die IDE aus, sondern die Mausbewegung über die Code-Editor-API.

Strg+Klick und „Deklaration suchen“ erreichen dpcc nur, wenn es der gewählte Code-Insight-Anbieter ist: Die IDE ruft
`GotoDefinition` des Managers. Er gleicht den Puffer ab und fragt in einem Hintergrund-Thread über
`TLspSession.GotoTargetAt` `textDocument/declaration` (auf der Deklaration selbst danach `textDocument/definition`).
Der Hauptthread wartet höchstens 250 ms. Ohne Ziel antwortet er True mit leerem Dateinamen, die IDE bricht dann still
ab; den Grund schickt der Server vor der leeren Antwort als Benachrichtigung `dpcc/noTarget` (reason, name, indexing),
die Sitzung legt ihn im Lese-Thread ab, `GotoTargetAt` holt ihn ab, und dpcc zeigt ihn im Meldungsfenster und
schreibt eine Zeile ins `dpcc.log`. Kommt die Antwort später, antwortet er genauso still; dpcc springt dann selbst,
sofern dieselbe Datei aktiv ist, der Cursor noch im Bezeichner der Klickstelle oder der Ausgangsstelle steht, kein
neuerer Sprungwunsch kam und die Antwort höchstens 10 Sekunden nach dem Klick im Hintergrund-Thread eintraf (das ist
zugleich das Zeitlimit der Anfrage). Startet der Server noch, merkt sich der Manager den Wunsch und fragt nach dem
Start mit denselben Regeln.
Der Symbolhinweis der IDE (`GetHintText`, nur ohne eigenen dpcc-Tooltip) wartet ebenso höchstens 250 ms; eine spätere
Antwort merkt sich dpcc einige Sekunden, damit der nächste Hinweis auf dasselbe Wort sofort erscheint. Die Regeln dazu
stehen in `dpcc.Core.Editor.Navigation` und `dpcc.Core.Lsp.LateAnswers`.

Vorladen beim Öffnen und Aktivieren: Der Editor-Beobachter der Anbindungen (`dpcc.IDE.CodeInsight.Manager.Editors`)
meldet jede aktive Ansicht; nach 0,4 s Ruhe (`dpcc.Core.Editor.Prewarm`) liest der Hauptthread den Puffer, ein
Arbeiter aus `TDpccTimeLimit` gleicht ab und schickt `dpcc/prewarm` (`TLspSession.Prewarm`). Der Server
(`Shell.Composition.Prewarm`) legt Baum und Units der `uses` im eigenen Thread in die Zwischenspeicher der Anfragen,
siehe [Index und Cache](index-cache.md#vorladen-beim-öffnen).

## Robustheit

- **Sicherung** (`dpcc.Core.Diagnostics.Guard`): Jeder Einstiegspunkt aus der IDE läuft über `TDpccGuard.Run`.
  Exceptions verlassen dpcc nie in Richtung IDE. Drei Fehler einer Funktion in fünf Minuten schalten nur diese
  Funktion bis zum Neustart der IDE ab.
- **Warteschlange zum Hauptthread** (`dpcc.Core.Diagnostics.MainThread`): Jeder Eintrag gehört einem eigenen
  Besitzer; beim Entladen werden wartende Einträge verworfen, damit nichts in entladenem Code läuft.
- **Server-Abstürze** (`dpcc.IDE.CodeInsight.Manager.Crashes`): Neustart; nach zwei gleichen Abstürzen in zehn
  Minuten kein automatischer Neustart mehr.
- **Protokoll**: rotierend, anonymisiert, mit Sperre über mehrere IDE-Instanzen. Die Zeilen schreibt ein eigener
  Thread (`dpcc.Core.Diagnostics.LogWriter`); wer protokolliert, wartet nie auf die Datei. Beim Entladen schreibt er
  Ausstehendes noch weg (höchstens 1 s), zuletzt die Zeile „dpcc entladen“.

## Texte und Sprache

Texte stehen in Tabellen `cTexts: array[TDpccLanguage, …]` mit Deutsch und Englisch nebeneinander, in `dpcc.UI` je
Feature in eigenen Units (`dpcc.UI.Strings`, `dpcc.UI.Completion.Strings`, `dpcc.UI.Settings.Strings` …). Die Sprache
setzt die IDE-Schicht beim Laden nach der Sprache der IDE; sie geht auch an den Server. Bezeichner, Signaturen,
XMLDoc und Protokollzeilen werden nie übersetzt.
