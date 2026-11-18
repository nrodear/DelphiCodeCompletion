Deutsch | [English](../en/troubleshooting.md) | [Français](../fr/troubleshooting.md)

# Fehlersuche

[Übersicht](index.md) › Fehlersuche

## Das Plugin lädt nicht

Typisch: Die IDE meldet beim Start oder beim Installieren, dass ein Package nicht geladen werden kann.

Ursache ist fast immer der PATH. `dpcc.IDE.Base370.bpl` braucht sieben weitere BPLs, und Windows sucht sie nur über
den PATH.

1. Die IDE schließen.
2. `powershell -NoProfile -File Tools\IdePath.ps1` aufrufen und die Ausgabe lesen. Die letzte Zeile ist das
   Ergebnis. „…“ steht für den BPL-Ordner, 37.0 ist die BDS-Version von Delphi 13 (Parameter `-BdsVersion`):
   - „FEHLT: BPL-Ordner oder BPLs fehlen (…) - erst die Gruppe dpcc_d13 bauen.“ (Exit-Code 2): Die Gruppe ist
     nicht vollständig gebaut. Welche BPL fehlt, zeigt die Liste darüber mit „[fehlt]“. Alle Projekte bauen.
   - „FEHLT: … steht nicht in der PATH-Ueberschreibung der IDE 37.0. Abhilfe: -Action Add“ (Exit-Code 1):
     `-Action Add` aufrufen.
   - „OK: … steht in der PATH-Ueberschreibung der IDE 37.0, alle BPLs vorhanden.“ (Exit-Code 0): PATH und BPLs
     sind in Ordnung.
   - Steht darüber „Hinweis  : n Delphi-Instanz(en) laufen - Aenderungen wirken erst nach einem Neustart.“, läuft
     noch eine IDE. Sie schließen.
3. Die IDE neu starten.

Weitere Ursachen:

- Der PATH steht im PATH von Windows statt in der PATH-Überschreibung der IDE. Siehe
  [Installation](installation.md#path-der-ide-setzen).
- Eine BPL ist älter als die anderen, etwa nach einem abgebrochenen Build. `Tools\IdePath.ps1` zeigt das Datum jeder
  BPL. Die ganze Gruppe neu bauen.
- Gebaut wurde nicht Win32. Die IDE lädt nur Win32-Packages.

## Ist dpcc geladen?

- Startbildschirm und Info-Dialog nennen „dpcc 0.1.0“.
- **Tools › Optionen › Drittanbieter** zeigt den Knoten **dpcc**.
- Im Protokoll steht „dpcc angemeldet (Code Completion)“.

## Strg+Leertaste zeigt die Liste der IDE statt der von dpcc

dpcc gibt die Taste an die IDE weiter, wenn es die Datei nicht bedient:

| Ursache | Abhilfe |
|---|---|
| Die Datei endet nicht auf `.pas`, `.dpr`, `.dpk` oder `.inc`. | Erwartet. |
| Der Hauptschalter ist aus. | **Tools › Optionen › Drittanbieter › dpcc**, „Code Insight von dpcc“ einschalten. |
| Die Sicherung hat die Vervollständigung abgeschaltet. | Das Meldungsfenster nennt das (siehe unten). Die IDE neu starten. |
| Die Liste von dpcc blieb leer, und Strg+Leertaste kam ein zweites Mal an derselben Stelle. | Erwartet, siehe [Bedienung](usage.md#liste-der-ide-wenn-dpcc-nichts-findet). Nach einer Eingabe oder an einer anderen Stelle fragt Strg+Leertaste wieder dpcc. |

## Die Liste nach „.“ sieht anders aus als die mit Strg+Leertaste

Das ist erwartet. Die Liste, die nach „.“ von selbst aufgeht, kommt von DelphiLSP. Siehe
[Bedienung](usage.md#zusammenspiel-mit-delphilsp).

## Die Liste ist leer oder unvollständig

- „eingeschränkt (Index wird aufgebaut)“: Der Index ist noch nicht fertig. Warten.
- Warnleiste „Syntaxfehler in Zeile n“: Vor dem Cursor steht ein Syntaxfehler. Ein Klick auf die unterstrichene
  Zeilenangabe schließt die Liste und setzt den Cursor an den Fehler.
- Eine Unit fehlt: Liegt sie in keinem Projekt, keinem Suchpfad und keinem Bibliothekspfad, kennt dpcc sie nicht.
  Siehe [Index und Cache](index-cache.md#was-im-index-steht).
- Eine Unit fehlt, obwohl ihre Datei im Suchpfad liegt: In `dpcc.log` nach „Datei nicht lesbar“ suchen. Eine Datei,
  die sich nicht lesen oder parsen lässt, übergeht der Index.
- Der Index scheint veraltet: **Index neu aufbauen** auf der Seite **dpcc** (Abschnitt **Index**).
- Findet dpcc an einer Stelle nichts, öffnet ein zweites Strg+Leertaste dort die Liste der IDE (siehe
  [Bedienung](usage.md#liste-der-ide-wenn-dpcc-nichts-findet)).

## Für DUnitX gibt es keine Vorschläge

DUnitX, DUnit und FireDAC liegen der Installation nur als `.dcu` bei. Ohne Quelltext kennt dpcc ihre Typen aus den
Packages, die die IDE geladen hat, und ihre Mitglieder erst, wenn ein Projekt die Unit in den `uses` nennt. Konstanten
und Routinen außerhalb von Typen fehlen dann.

- Liegt der Quelltext vor (etwa ein Klon von DUnitX), seinen Ordner auf der Seite **dpcc** unter „Zusätzliche
  Quellordner“ eintragen. Danach schlägt „+ Unit“ etwa `TestFixtureAttribute` und `Assert` vor. Siehe
  [Index und Cache](index-cache.md#zusätzliche-quellordner).
- Ein Verweis wie `$(DUnitX)` in einem Suchpfad wirkt nur, wenn die Variable in den Umgebungsvariablen der IDE oder
  des Systems steht. Sonst nennt `dpcc.log` den Pfad („… mit unaufgelöstem Verweis übergangen“).

## Strg+Klick springt nicht

Strg+Klick und „Deklaration suchen“ (Alt+↑) gehen an den Code-Insight-Anbieter, der in den Optionen der IDE gewählt
ist. Nur wenn dort dpcc gewählt ist, springt dpcc (siehe
[Bedienung](usage.md#wenn-dpcc-als-anbieter-gewählt-ist)).

| Ursache | Abhilfe |
|---|---|
| Das Ziel liegt in einer Unit ohne Quelltext (nur aus einem Package bekannt). | Erwartet: kein Sprung, keine Meldung. Liegt der Quelltext vor, seinen Ordner unter „Zusätzliche Quellordner“ eintragen. |
| dpcc findet die Unit nicht oder kann den Namen nicht eindeutig auflösen (mehrdeutige Überladung, `with` mit unbekanntem Typ). | Erwartet. Suchpfade prüfen; siehe [Die Liste ist leer oder unvollständig](#die-liste-ist-leer-oder-unvollständig). |
| Der Index wird noch aufgebaut oder die Antwort dauerte länger als 1 Sekunde. | Warten und noch einmal versuchen. |
| Ein Parameter-Hint von dpcc mit mehreren Überladungen ist offen. | Seit dieser Fassung wechselt dort Strg+Alt+↑/↓ die Überladung; Alt+↑ geht an die IDE. |
| Der Tooltip von dpcc verdeckt das Wort. | Strg gedrückt halten: Maus und Klick gehen dann durch den Tooltip an den Editor. |

## Zwei Tooltips erscheinen

- Help Insight der IDE: dpcc schaltet es ab, die IDE liest den Schalter aber erst beim nächsten Start. Die IDE neu
  starten.
- Beim Debuggen der Wert-Tooltip der IDE: dpcc schaltet ihn nur ab, wenn die Seite dpcc mit **OK** geschlossen wird.
  Die Seite einmal öffnen, OK, die IDE neu starten.
- Wer den Tooltip der IDE behalten will, schaltet „Eigener Tooltip beim Verweilen über Bezeichnern“ bzw. „Werte beim
  Debuggen zeigen“ aus.

## Help Insight fehlt nach der Deinstallation

dpcc gibt Help Insight und den Wert-Tooltip nur zurück, solange es geladen ist. Wurde es entfernt, ohne vorher den
Hauptschalter auszuschalten, beide in den Code-Insight-Optionen der IDE wieder einschalten. Die Registry-Werte stehen
unter [Einstellungen](settings.md#was-dpcc-an-der-ide-umstellt).

## Meldungen im Meldungsfenster

Warnungen schreibt dpcc ins Meldungsfenster der IDE und ins Protokoll. Einen Dialog zeigt es von sich aus nur in
einem Fall: Der Server ist zweimal mit derselben Ursache innerhalb von 10 Minuten abgestürzt, und dpcc startet ihn
nicht mehr von selbst neu (siehe [Der Server ist abgestürzt](#der-server-ist-abgestürzt)).

| Meldung | Bedeutung |
|---|---|
| „dpcc: Server wiederholt abgestürzt – Der Server endete zweimal mit … innerhalb von 10 Minuten. dpcc startet ihn nicht mehr von selbst neu …“ | Der Server bleibt beendet, bis er von Hand neu gestartet wird. Dazu erscheint die Rückfrage „Server neu starten?“. |
| „dpcc: … nach 3 Fehlern in 5 Minuten abgeschaltet (zuletzt: …); bis zum Neustart der IDE.“ | Die Sicherung hat eine Funktion abgeschaltet. Sie bleibt bis zum Neustart der IDE aus. Fehler von dpcc erreichen die IDE nie. |
| „dpcc: Quelle „…“ nach 3 Fehlern in 5 Minuten abgeschaltet …“ | Nur diese Datenquelle ist aus; die übrigen laufen weiter. |
| „dpcc zeigt den Tooltip selbst und hat Help Insight der IDE abgeschaltet …“ | siehe „Zwei Tooltips erscheinen“ |
| „dpcc ist in den Optionen der IDE als Code-Insight-Anbieter für Delphi gewählt …“ | Einmal je Sitzung, wenn dpcc der gewählte Anbieter ist: Strg+Klick läuft über dpcc, Error Insight und die übrigen Dienste von DelphiLSP fehlen. Siehe [Bedienung](usage.md#wenn-dpcc-als-anbieter-gewählt-ist). |

## Der Server ist abgestürzt

- Endet der Server unerwartet, startet dpcc ihn neu und schickt die offenen Dateien erneut.
- Endet er zweimal mit derselben Ursache innerhalb von 10 Minuten, startet dpcc ihn nicht mehr von selbst neu, damit
  der Fehler nicht in einer Schleife wiederkehrt. Das Meldungsfenster nennt das („Server wiederholt abgestürzt“), und
  dpcc fragt „Server neu starten?“. Mit **Ja** startet er neu, und die Zählung beginnt von vorn. Mit **Nein** bleibt
  er beendet, bis die IDE neu gestartet wird.
- Die Ursache steht im Protokoll.

## Protokolle

### dpcc.log

| | |
|---|---|
| Ort | `%LOCALAPPDATA%\dpcc\Logs\dpcc.log` |
| Ältere Dateien | `dpcc.1.log` bis `dpcc.4.log`; höchstens 5 Dateien zu je 1 MB |
| Inhalt | Start und Entladen, gewählter Code-Insight-Anbieter, Sprache, Fehler mit Version, Funktion, Fehlerklasse, Meldung und Aufrufstapel |
| Nie enthalten | Quelltext aus dem Editor |

Namen und Pfade sind im Protokoll unkenntlich gemacht. Klarnamen schreibt dpcc nur, wenn unter
`HKCU\Software\dpcc\IdePlugin` der DWORD-Wert `LogNames` = 1 steht. Das Protokoll ist dann nicht mehr anonym; vor
dem Weitergeben prüfen.

Mehrere IDE-Instanzen teilen sich den Ordner; eine Sperre verhindert, dass sie sich gegenseitig stören.

### Diagnoseprotokoll

Für genaue Fehlersuche protokolliert dpcc die Aufrufe der IDE an seinen Code-Insight-Manager:

1. Unter `HKCU\Software\dpcc\IdePlugin` den DWORD-Wert `Diagnose` = 1 anlegen.
2. Die IDE neu starten.
3. Das Protokoll liegt neben der Plugin-BPL: `Output\Win32\Debug\Bpl\dpcc.IDE.Expert370.log`.

Pfade und der Benutzername sind darin ersetzt. Zum Abschalten den Wert löschen oder auf 0 setzen.

### Diagnoselog des Servers

Der Server schreibt ein anonymes Protokoll seiner Anfragen und Indexaufbauten nach
`%LOCALAPPDATA%\dpcc\Logs\Diagnose\diag-<Datum>-<Prozess>.log`, eine Datei je Tag und Prozess, 7 Tage lang
(`diagnostics.log`, `diagnostics.logDays` in `settings.json`).

Den Speicher des IDE-Prozesses meldet es in Zeilen „mem“: beim Start und am Ende jedes Indexaufbaus und spätestens alle
10 Minuten, sobald eine Anfrage endet. Beispiel:

```
14:02:10.521 mem indexDone private 104 MB peak 127 MB ws 118 MB free 2003 MB index 56 MB units 2027 lib 1481 docs 0 trees 0 0 MB dcp 4 27 kb loaded 703 pinned 701 evictable 2 1 MB cold 1324 catalog 13 MB loads 15 evicted 0 loadms 0.2 max 3.6
```

| Feld | Bedeutung |
|---|---|
| `indexStart`, `indexDone`, `periodic` | Anlass: Start bzw. Ende eines Aufbaus, regelmäßige Zeile |
| `private` | Private Bytes des ganzen IDE-Prozesses (zugesagter privater Speicher) |
| `peak` | höchster Stand von `private` seit dem Start der IDE |
| `ws` | Working Set (Speicher im RAM; sinkt beim Auslagern, `private` nicht) |
| `free` | größter zusammenhängender freier Bereich im Adressraum; wird er klein, droht „Out of memory“ trotz freiem RAM |
| `index` | geschätzter Speicher des Symbolindex: geladene Units und Katalog |
| `units`, `lib` | Units im Index, davon aus der Bibliothek |
| `docs` | geöffnete Dokumente beim Server |
| `trees` | Syntaxbäume und ihr geschätzter Speicher |
| `dcp` | gemerkte übersetzte Packages (`.dcp`) und ihre Namen in KB |
| `loaded`, `pinned`, `evictable` | Units mit allen Symbolen im Speicher; davon gepinnt (nie freigegeben) und freigebbar, dazu deren Speicher (Obergrenze 32 MB). Siehe [Bibliothek bei Bedarf](index-cache.md#bibliothek-bei-bedarf) |
| `cold` | Units nur im Katalog |
| `catalog` | geschätzter Speicher des Katalogs aller Units |
| `loads`, `evicted` | seit dem Start des Servers nachgeladene und wieder freigegebene Units |
| `loadms`, `max` | Dauer des Nachladens in ms: Median der letzten Ladevorgänge und Höchstwert |

Auch „run start … mem n MB“ und die Zeilen „index … mem n MB“ nennen die Private Bytes des Prozesses.

## Die IDE braucht viel Speicher

- Das Diagnoselog des Servers zeigt in den Zeilen „mem“, wie viel davon auf den Index entfällt (siehe oben).
- Von der Bibliothek hält der Index nur die Units ständig im Speicher, die die Projekte erreichen oder oft brauchen;
  die übrigen lädt er bei Bedarf und gibt sie wieder frei. Siehe [Index und Cache](index-cache.md#bibliothek-bei-bedarf).
- Die Office-Typbibliotheken und WinRT liegen nur mit ihrem Katalog im Speicher; ihre Symbole lädt dpcc bei Bedarf.
  Siehe [Index und Cache](index-cache.md#office-typbibliotheken-und-winrt).
- Nur die 16 zuletzt benutzten Dateien behalten im Server ihren Syntaxbaum; für ältere baut er ihn beim nächsten Zugriff
  neu auf. Schließt die IDE eine Datei, gibt dpcc sie im Server frei.
- Eine Datei außerhalb der Projektgruppe bekommt einen eigenen Arbeitsbereich. Er verschwindet wieder, wenn die letzte
  seiner Dateien geschlossen ist.
- Endet der Server (Hauptschalter aus, Neustart), gibt dpcc den ganzen Index frei. Laufen dabei noch Anfragen, die nicht
  rechtzeitig enden, folgt die Freigabe, sobald sie fertig sind.

## Einstellungen auf Vorgabe

- Eine Option: auf der Seite **dpcc** von Hand auf die Vorgabe stellen; die Vorgaben stehen unter
  [Einstellungen](settings.md).
- Alles: siehe [Einstellungen](settings.md#ablage).
