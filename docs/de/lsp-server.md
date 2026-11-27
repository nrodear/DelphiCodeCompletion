Deutsch | [English](../en/lsp-server.md) | [Français](../fr/lsp-server.md)

# LSP-Server (dpcc.LspServer.exe)

[Übersicht](index.md) › LSP-Server

`dpcc.LspServer.exe` ist dpcc als eigenständiger Language Server. Er spricht das Language Server Protocol über
stdin/stdout und kann in der Delphi-IDE an die Stelle von `DelphiLSP.exe` treten. Drinnen arbeitet derselbe Server
wie im Plugin (Index, Vervollständigung, Hover, Parameterhilfe, Sprungziele); dazu kommen die Strukturansicht und das
Format, das die IDE erwartet.

Das Plugin behält seinen eingebauten Server. Die EXE ist ein zweiter, getrennter Weg zum selben Ergebnis.

## Was er kann

| Anfrage | Ergebnis |
|---|---|
| `textDocument/completion`, `completionItem/resolve` | Liste mit Art, Name und Signatur wie DelphiLSP |
| `textDocument/hover` | Deklaration und Doku als Klartext |
| `textDocument/signatureHelp` | Signaturen mit aktuellem Parameter |
| `textDocument/definition`, `declaration`, `typeDefinition` | Sprung zu Implementierung, Deklaration, Typ |
| `textDocument/documentSymbol` | Strukturansicht: Abschnitte, Typen mit Feldern, Properties und Methoden, Routinen |
| `didOpen`, `didChange` (ganzer Text oder Bereiche), `didClose` | Dokumente im Speicher |
| `workspace/didChangeConfiguration` | Projektdaten der IDE, siehe unten |

Was er nicht kann, beantwortet er mit dem Fehler -32601 (Methode nicht gefunden), etwa `textDocument/implementation`
und `textDocument/references`. Es gibt keine Code-Diagnosen (Error Insight bleibt leer) und kein Weiterreichen an
DelphiLSP.

## Aufruf

```
dpcc.LspServer.exe [--cache-root <Ordner>] [--log-level debug|info|warning|error] [--no-log] [--version] [--help]
```

Weitere Parameter werden übergangen. Der Server antwortet auf `initialize` sofort und lädt Projekt und Index im
Hintergrund; bis der Index steht, sind Antworten leer oder unvollständig, statt auf ihn zu warten. Er endet nach `exit`
(als Benachrichtigung oder als Anfrage mit id), am Ende der Eingabe oder wenn der Prozess aus `processId` von
`initialize` endet. Der Arbeitsordner spielt keine Rolle.

Die EXE gibt es für Win32 und Win64; beide bedienen Delphi 12 und Delphi 13. Sie hängt an keinem BPL.

## Ablage

| Reihenfolge | Ort |
|---|---|
| 1 | `--cache-root <Ordner>` |
| 2 | Umgebungsvariable `DPCC_LSPSERVER_CACHE_ROOT` |
| 3 | `%LOCALAPPDATA%\dpcc.LspServer` |

Darunter liegen wie beim Plugin `Index\<Delphi-Version>\…` (Caches), `projektauswahl.json` und
`Logs\Diagnose` (anonymes Diagnoselog), dazu das Protokoll der EXE unter
`Logs\LspServer\lsp-<Datum>-<Prozess>.log` (eine Datei je Prozess, nach 14 Tagen gelöscht). Der Ordner des Plugins
(`%LOCALAPPDATA%\dpcc`) bleibt unberührt; eine gesetzte Variable `DPCC_CACHE_ROOT` gilt für die EXE nicht. Die
Einstellungen liest sie wie das Plugin aus `%APPDATA%\dpcc\settings.json` und `dpcc.json`, schreibt sie aber nie.

Caches schreibt der Server über eine Zwischendatei mit anschließendem Umbenennen; ein hartes Ende (die IDE beendet den
Prozess nach `shutdown` ohne `exit`) hinterlässt deshalb keinen halben Cache.

## Projektdaten aus der IDE

Die IDE meldet das aktive Projekt per `workspace/didChangeConfiguration`. Der Server liest daraus:

| Feld | Verwendung |
|---|---|
| `project` | Hauptdatei (.dpr/.dpk); die .dproj daneben wird Arbeitsbereich, wenn die geöffneten Dateien sie nicht schon ergeben |
| `dllname` | Delphi-Version (`dcc32290.dll` → 23.0, `dcc32370.dll` → 37.0) und Plattform (`dcc32` Win32, `dcc64` Win64) |
| `dccOptions` | `-D` Symbole, `-NS` Namespaces, `-U` Pfade: im Installations- oder Studio-Ordner als Bibliothek, sonst als Suchpfad des Projekts |
| `browsingPaths` | Browsing Path der IDE (Quelltexte der Bibliothek) |
| `CommonAppData` | Profil der IDE (`bds -r`), unter dem der Server Variablen und Pfade liest |

Ohne diese Daten (anderer Client) leitet der Server Projekte aus den geöffneten Dateien ab: die .dproj im Ordner der
Datei oder darüber.

## Clients

Meldet sich der Client in `initialize` als `RAD Studio`, antwortet der Server im Format der IDE (ganzer Text bei
Änderungen, Vervollständigung mit `kibitzkind` und `DCC_Flags`, Parameterhilfe mit `documentation`, Hover als
Klartext) und schickt keine eigenen Benachrichtigungen. Jeder andere Client bekommt Standard-LSP.

## Siehe auch

- [Architektur](architecture.md): Server, Index und Ablauf einer Anfrage
- [Index und Cache](index-cache.md)
