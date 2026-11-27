Deutsch | [English](../en/lsp-server.md) | [Français](../fr/lsp-server.md)

# LSP-Server (dpcc.LspServer.exe)

[Übersicht](index.md) › LSP-Server

`dpcc.LspServer.exe` ist dpcc als eigenständiger Language Server. Er spricht das Language Server Protocol über
stdin/stdout und tritt in der Delphi-IDE an die Stelle von `DelphiLSP.exe`. Drinnen arbeitet derselbe Server wie im
Plugin (Index, Vervollständigung, Hover, Parameterhilfe, Sprungziele); dazu kommen die Strukturansicht und das
Format, das die IDE erwartet.

In die IDE bindet ihn das Plugin ein: in der [Betriebsart Server](#betriebsart-server). Der eingebaute Server des
Plugins (Betriebsart Plugin) und die EXE arbeiten nie gleichzeitig.

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

Die EXE gibt es für Win32 und Win64; beide bedienen Delphi 12 und Delphi 13. Sie hängt an keinem BPL. Die 32-Bit-IDE
startet auch die 64-Bit-EXE.

## Betriebsart Server

In der Betriebsart Server bleibt die IDE im LSP-Betrieb (Anbieter DelphiLSP) und zeigt ihre eigenen Fenster: Liste,
Hint, Tooltip beim Verweilen, Strukturansicht und Strg+Klick. Startet sie `DelphiLSP.exe`, startet das Plugin statt
dessen `dpcc.LspServer.exe` mit denselben Parametern; Flags, Handles, Umgebung und Arbeitsordner bleiben, wie die IDE
sie setzt. Dafür biegt das Plugin in der laufenden IDE den Aufruf von `kernel32!CreateProcessW` im Modul
`IDELSP290.bpl` (Delphi 12) bzw. `IDELSP370.bpl` (Delphi 13) um (Hook in der Importtabelle). Im Delphi-Programmordner
ändert es nichts, Administratorrechte braucht es nicht.

### Einschalten

1. Die EXE bereitstellen: im Setup die Komponente „LSP-Server“ wählen (Vorgabe), sie aus dem ZIP an einen der
   [Orte](#wo-dpcc-die-exe-sucht) legen oder selbst bauen (siehe [Installation](installation.md#lsp-server)).
2. **Tools › Optionen › Drittanbieter › dpcc**, Betriebsart „Server – dpcc.LspServer.exe an Stelle von DelphiLSP“
   wählen und mit **OK** schließen. dpcc stellt den Code-Insight-Anbieter der IDE dabei auf DelphiLSP.
3. Kam der Wechsel aus Plugin (oder war ein anderer Anbieter gewählt), Delphi neu starten. Kam er aus Aus, die
   Projektgruppe schließen und wieder öffnen: Die IDE startet ihren Server, wenn die erste Unit einer Projektgruppe
   angezeigt wird, einen je Gruppe, und ein laufender Server bleibt, bis die Gruppe geschlossen wird.

Die Betriebsart gilt je Delphi-Version (siehe [Einstellungen](settings.md#betriebsart)). Bei jedem Start von
DelphiLSP liest der Hook sie frisch aus der Registry; zurück auf das originale DelphiLSP geht es also mit „Aus“ und
erneutem Öffnen der Projektgruppe. Fehlt die EXE, ist „Server“ auf der Seite grau mit dem Hinweis „Nicht wählbar:
dpcc.LspServer.exe ist nicht installiert …“. Ist Server schon gewählt, bleibt es gewählt, und der Start fällt auf
das originale DelphiLSP zurück. Der Hint am Feld nennt den gefundenen Ort.

### Wo dpcc die EXE sucht

Relativ zum geladenen Plugin, in dieser Reihenfolge; auf 64-Bit-Windows jeweils zuerst die 64-Bit-EXE (`win64`,
`Win64`), dann die 32-Bit-EXE:

| Aufbau | Plugin | EXE |
|---|---|---|
| Setup | `{app}\bpl\d12` bzw. `{app}\bpl\d13` (`{app}` = `%LOCALAPPDATA%\Programs\dpcc`) | `{app}\server\win64\dpcc.LspServer.exe`, dann `{app}\server\win32\dpcc.LspServer.exe` |
| eigener Bau | `Output\Win32\<Konfiguration>\Bpl` | `Output\Win64\<Konfiguration>\Bin`, ersatzweise `Output\Win64\Debug\Bin` und `Output\Win64\Release\Bin`, dann dieselben unter `Output\Win32` |
| zuletzt | beliebig | neben dem Plugin, etwa aus dem ZIP dorthin gelegt |

Für den eigenen Bau unter Delphi 12 (Konfiguration D12) heißt das: zuerst `Output\Win64\D12\Bin`, dann
`Output\Win64\Debug\Bin` und `…\Release\Bin`, dann dieselben unter `Output\Win32`.

### Protokoll

Jeder Schritt steht als Zeile in `dpcc.log` (`%LOCALAPPDATA%\dpcc\Logs`):

| Zeile | Bedeutung |
|---|---|
| `LSP-Umleitung: Hook beim Anmelden (37.0): 1 Eintrag/Einträge in IDELSP370.bpl umgebogen; Betriebsart jetzt Server; EXE: …` | Der Hook sitzt. War `IDELSP` beim Anmelden noch nicht geladen, holt dpcc den Einbau nach („Hook nachgeholt nach n ms …“, höchstens 5 Minuten lang). |
| `LSP-Umleitung: #1 DelphiLSP umgeleitet auf <EXE> (PID n)` | Die IDE startete ihren Server; gestartet wurde `dpcc.LspServer.exe`. |
| `LSP-Umleitung: #2 Start von DelphiLSP nicht umgeleitet (<Grund>)` | Das originale DelphiLSP startet. Gründe: `Betriebsart Aus`, `Betriebsart Plugin`, `dpcc.LspServer.exe nicht gefunden`, `dpcc.LspServer.exe fehlt: <Pfad>`. |
| `LSP-Umleitung: #3 Start von dpcc.LspServer.exe fehlgeschlagen (Fehler n), Originalaufruf` | Die EXE ließ sich nicht starten (Windows-Fehlercode n); statt dessen startet das originale DelphiLSP. |
| `LSP-Umleitung: Hook abgebaut: …` | Beim Entladen des Plugins, auch in der laufenden IDE. Danach startet wieder das Original. |
| `Eingebauter Server: startet nicht (Betriebsart Server)` | Beim Anmelden des Plugins: In den Betriebsarten Aus und Server startet der eingebaute Server in dieser Sitzung nicht (bei Plugin: `… startet bei Bedarf (Betriebsart Plugin); keine Umleitung von DelphiLSP`). |
| `Eingebauter Server nicht gestartet: …` | Der eingebaute Server des Plugins bleibt aus, mit Grund (Betriebsart oder vorige Umleitung, siehe unten). |

Das eigene Protokoll der EXE liegt unter ihrer [Ablage](#ablage).

### Gegenseitiger Ausschluss

- Der eingebaute Server des Plugins startet nur in der Betriebsart Plugin.
- Hat der Hook in dieser Sitzung der IDE schon einmal auf `dpcc.LspServer.exe` umgeleitet, startet der eingebaute
  Server bis zum Neustart von Delphi nicht, auch wenn danach Plugin gewählt wird.
- In der Betriebsart Plugin leitet der Hook nie um; die IDE ruft DelphiLSP dann ohnehin nicht.

### Grenzen

- Error Insight bleibt leer: Der Server liefert keine Code-Diagnosen. dpcc setzt `ErrorInsightLevel` nicht.
- Nicht unterstützt: die 64-Bit-IDE von Delphi 13 (`bin64\bds.exe`, `Known Packages x64`). Das Plugin ist 32 Bit
  und lädt dort nicht.
- Fehlt die EXE oder schlägt ihr Start fehl, startet das originale DelphiLSP; eine Zeile steht im Protokoll.
- Der Absturz von Delphi 12 beim Anzeigen einer Unit mit Gleitkommazahl tritt im LSP-Betrieb nicht auf (siehe
  [Fehlersuche](troubleshooting.md#delphi-12-absturz-beim-anzeigen-einer-unit-mit-gleitkommazahl)).

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

- [Einstellungen › Betriebsart](settings.md#betriebsart)
- [Architektur](architecture.md): Server, Index und Ablauf einer Anfrage
- [Index und Cache](index-cache.md)
