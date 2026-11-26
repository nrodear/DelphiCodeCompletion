Deutsch | [English](../en/troubleshooting.md) | [Français](../fr/troubleshooting.md)

# Fehlersuche

[Übersicht](index.md) › Fehlersuche

## Das Plugin lädt nicht

Typisch: Die IDE meldet beim Start oder beim Installieren, dass ein Package nicht geladen werden kann.

Ursache ist fast immer der PATH. `dpcc.Plugin370.bpl` braucht sieben weitere BPLs, und Windows sucht sie nur über
den PATH.

1. Die IDE schließen.
2. `powershell -NoProfile -File Tools\IdePath.ps1` aufrufen und die Ausgabe lesen. Die letzte Zeile ist das
   Ergebnis. „…“ steht für den BPL-Ordner, 37.0 ist die BDS-Version von Delphi 13 (Parameter `-BdsVersion`; für
   Delphi 12 `-BdsVersion 23.0`, dann nennt die Meldung die Gruppe dpcc_d12 und den Ordner `Output\Win32\D12\…`):
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

## Nach dem Punkt öffnet keine Liste

Meist steht in den Code-Insight-Optionen der IDE „Programmierhilfe“ aus (Registry-Wert `Auto Code Completions` =
`False`). Dann öffnet nach „.“ weder die Liste der IDE noch die von dpcc. Zweiter möglicher Grund: „Automatisch
aufrufen“ steht aus (`Auto Invoke` = `False`); dann ruft die IDE die Vervollständigung nach „.“ nicht von selbst auf.

- Betriebsart dpcc: dpcc stellt beide Werte beim Start von Delphi selbst auf `True`; wirkt nach dem nächsten Start.
- Betriebsart IDE (DelphiLSP gewählt): dpcc meldet die Abweichung nur, im Protokoll („IDE-Einstellungen: 1 Abweichung:
  Auto Code Completions“) und auf der Seite dpcc im Abschnitt **IDE**. In den Code-Insight-Optionen der IDE
  „Programmierhilfe“ und „Automatisch aufrufen“ einschalten.

Orte und Soll-Werte für Delphi 12 und 13: [Einstellungen](settings.md#was-dpcc-an-der-ide-umstellt).

## Die Liste nach „.“ sieht anders aus als die mit Strg+Leertaste

Nach dem Einschalten von dpcc bis zum Neustart von Delphi erwartet: Die Liste, die nach „.“ von selbst aufgeht, kommt
noch vom bisherigen Anbieter (DelphiLSP). Nach dem Neustart ist dpcc der Anbieter. Siehe
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
| Das Ziel liegt in einer Unit ohne Quelltext (nur aus einem Package bekannt). Meldung „Unit X liegt nur als Package vor“. | Erwartet: kein Sprung. Liegt der Quelltext vor, seinen Ordner unter „Zusätzliche Quellordner“ eintragen. |
| dpcc findet die Unit nicht oder kann den Namen nicht eindeutig auflösen (mehrdeutige Überladung, `with` mit unbekanntem Typ). Meldung „Unit X nicht gefunden“ bzw. „„Name“ nicht aufgelöst“. | Erwartet. Suchpfade prüfen; siehe [Die Liste ist leer oder unvollständig](#die-liste-ist-leer-oder-unvollständig). |
| Der Index wird noch aufgebaut („Kein Sprung: Der Index wird noch aufgebaut. Bitte gleich erneut klicken.“, bei anderen Gründen der Zusatz „Der Index wird noch aufgebaut.“; dpcc springt dann nicht nach), dpcc startet noch oder die Antwort dauerte länger als 10 Sekunden („keine Antwort binnen 10 s“). Nach 250 ms springt dpcc selbst, aber nur bis dahin und nur, solange der Cursor im selben Bezeichner bleibt. | Warten und noch einmal versuchen. |
| Keine Meldung im Meldungsfenster. | `dpcc.log` nennt jeden Sprung ohne Ziel in einer Zeile `Gehe zu Definition: <Ausgang> nach <n> ms, <Datei> <Zeile>:<Spalte> (Maus\|Cursor)`, auch verworfene späte Antworten („Cursor bewegt“, „andere Datei aktiv“, „neuerer Sprungwunsch“, „zu spät“). |
| Strg+Klick auf eine Verwendung springt zur Deklaration, Strg+Klick auf die Deklaration aber nicht zur Implementierung. | „Ablauf protokollieren (Log)“ einschalten, den Sprung wiederholen und die Kette schicken (siehe [Ablaufprotokoll](#ablaufprotokoll)): Sie zeigt das Urteil von `OnTarget` und ob `definition` gefragt wurde. |
| Ein Parameter-Hint von dpcc mit mehreren Überladungen ist offen. | Seit dieser Fassung wechselt dort Strg+Alt+↑/↓ die Überladung; Alt+↑ geht an die IDE. |
| Der Tooltip von dpcc verdeckt das Wort. | Strg gedrückt halten: Maus und Klick gehen dann durch den Tooltip an den Editor. |

### Sprung in ein anderes Package

Verlangt ein Package (`requires`) ein anderes, sucht dpcc dessen Quelle `<Name>.dpk` und nimmt die Units aus seinem
`contains` in den Index des Projekts auf. Gesucht wird in den Ordnern aller gemeldeten Projekte der Gruppe (auch derer,
die noch geladen werden), im Projektordner, in den Suchpfaden, in den
[zusätzlichen Quellordnern](index-cache.md#zusätzliche-quellordner) und in den Ordnern neben dem Projektordner
(`Packages\<Name>\<Name>.dpk`, eine Ebene). Das andere Package muss dafür kein Projekt der Gruppe sein. Kommt ein
Package-Projekt später zur Gruppe, laden die vorhandenen Packages neu. Gibt es nur das übersetzte Package (`.dcp`,
BPL), gibt es kein Ziel; liegt der Quelltext woanders, seinen Ordner unter „Zusätzliche Quellordner“ eintragen.

Findet dpcc kein Ziel, meldet der Server den Grund (`dpcc/noTarget`) vor der leeren Antwort: `noDocument` (Datei dem
Server unbekannt), `noIdentifier` (kein Bezeichner an der Stelle), `unresolved` (Name nicht aufgelöst),
`unitNotFound` (Unit aus `uses` nicht gefunden), `noSource` (Unit nur als Package ohne Quelltext), `inactiveBranch`
(nicht geltender `$IFDEF`-Zweig), `other`; dazu, ob der Index noch aufgebaut wird. Im Diagnoselog des Servers steht
derselbe Grund in der Zeile der Anfrage (`empty:unitNotFound` …, der Name nur als Kennzahl `name=h…`), vorher eine
Zeile `declaration start` bzw. `definition start`.

## Zwei Tooltips erscheinen

- Die IDE liest ihre Schalter erst beim nächsten Start. dpcc stellt Help Insight, den Kurzhinweis Symbol-Insight und
  beim Debuggen die Ausdrucksauswertung ab, sobald es der Code-Insight-Anbieter ist. Delphi neu starten.
- Das Fenster von Help Insight (etwa „TQRCustomBand Typ“) verbirgt dpcc zusätzlich zur Laufzeit, sobald es
  erscheint: bei eingeschaltetem eigenem Tooltip immer, sonst solange die Liste von dpcc offen ist. Dafür ist kein
  Neustart nötig; auch unter Delphi 12, wo der Registry-Wert allein nicht sicher wirkt. Ist dpcc aus, bleibt das
  Fenster der IDE. Im Protokoll steht beim ersten Verbergen „Help Insight der IDE: Fenster THelpInsightWindow
  verborgen …“ und beim Start „Help Insight in der Registry (…)“ mit den gelesenen Werten.
- Den Stand zeigt die Seite dpcc im Abschnitt **IDE** („Jetzt prüfen“).
- Wer den Tooltip der IDE behalten will, schaltet „Eigener Tooltip beim Verweilen über Bezeichnern“ bzw. „Werte beim
  Debuggen zeigen“ aus.

## Help Insight fehlt nach der Deinstallation

dpcc gibt den Anbieter und die Schalter der IDE nur zurück, solange es geladen ist. Wurde es entfernt, ohne vorher den
Hauptschalter auszuschalten und Delphi neu zu starten, in den Code-Insight-Optionen der IDE DelphiLSP wählen und Help
Insight, den Kurzhinweis Symbol-Insight und die Ausdrucksauswertung wieder einschalten. Die Registry-Werte stehen
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
| „dpcc: dpcc hat den Code-Insight-Anbieter der IDE auf dpcc umgestellt; wirkt nach dem Neustart von Delphi.“ | Nach Hauptschalter an und OK, einmal je Sitzung. Bis zum Neustart ruft die IDE den bisherigen Anbieter. Siehe [Einstellungen](settings.md#was-dpcc-an-der-ide-umstellt). |
| „dpcc: dpcc hat den Code-Insight-Anbieter der IDE wieder auf … gestellt; wirkt nach dem Neustart von Delphi …“ | Nach Hauptschalter aus und OK, einmal je Sitzung. |
| „dpcc: Der Code-Insight-Anbieter ist nicht mehr dpcc …; dpcc ist aus …“ | Beim Start: dpcc hatte sich als Anbieter eingetragen, die IDE startete aber mit einem anderen (in den Optionen der IDE geändert oder von der IDE zurückgeschrieben). Zum Einschalten den Hauptschalter wieder setzen. |
| „dpcc ist in den Optionen der IDE als Code-Insight-Anbieter für Delphi gewählt …“ | Einmal je Sitzung, wenn dpcc der gewählte Anbieter ist: Strg+Klick läuft über dpcc, Error Insight und die übrigen Dienste von DelphiLSP fehlen. Siehe [Bedienung](usage.md#wenn-dpcc-als-anbieter-gewählt-ist). |

## Der Server ist abgestürzt

- Endet der Server unerwartet, startet dpcc ihn neu und schickt die offenen Dateien erneut.
- Endet er zweimal mit derselben Ursache innerhalb von 10 Minuten, startet dpcc ihn nicht mehr von selbst neu, damit
  der Fehler nicht in einer Schleife wiederkehrt. Das Meldungsfenster nennt das („Server wiederholt abgestürzt“), und
  dpcc fragt „Server neu starten?“. Mit **Ja** startet er neu, und die Zählung beginnt von vorn. Mit **Nein** bleibt
  er beendet, bis die IDE neu gestartet wird.
- Die Ursache steht im Protokoll.

## Die IDE stürzt mit Stapelüberlauf in clr.dll ab

Bild: Die IDE beendet sich mit einem Stapelüberlauf (Stack Overflow); das Absturzabbild zeigt `clr.dll` und einen
Hintergrund-Thread der IDE (etwa Error Insight), der .NET-Code aufruft. In einem untersuchten Fall war die
Gleitkomma-Einstellung der Grund: Im x87-Steuerwort war die Ausnahme „Invalid“ nicht maskiert, die Vorgabe
`System.Default8087CW` der gemeinsamen RTL stand auf `$137A` statt auf `$033F` (Vorgabe der Delphi-RTL, alle
Ausnahmen maskiert). Wer sie verstellt (die IDE, ein Experte, ein Package), zeigt das Abbild nicht.

dpcc ändert diese Einstellung nie. Es liest sie nur und schreibt dazu ins `dpcc.log`:

| Zeile | Bedeutung |
|---|---|
| `Gleitkomma beim Start: Vorgabe $033F (alle maskiert); Hauptthread $033F (alle maskiert); MXCSR Vorgabe $1F80, Hauptthread $1F80` | Stand beim Anmelden von dpcc: Vorgabe des Prozesses und Steuerwort des Hauptthreads mit den nicht maskierten Ausnahmen, dazu die SSE-Einstellung (MXCSR) nur als Hex. |
| `Gleitkomma geändert nach 95 s (Meldung 1 von höchstens 20): Vorgabe $033F (alle maskiert) → $137A (nicht maskiert: Invalid, ZeroDivide); Hauptthread unverändert $033F (alle maskiert)` | Seit dem Anmelden hat jemand die Einstellung geändert; alter → neuer Wert, getrennt für Vorgabe und Hauptthread. „Masken gleich“ heißt: Nur Genauigkeit oder Rundung sind anders. |

Geprüft wird im Takt des Wächters des Hauptthreads (etwa alle 50 ms, zwei Lesezugriffe). Eine Zeile entsteht nur bei
einer Änderung, höchstens 20 je Sitzung; die letzte endet mit „weitere Änderungen werden nicht mehr gemeldet“. Mit
eingeschaltetem [Ablaufprotokoll](#ablaufprotokoll) steht die Änderungszeile auch dort.

Steht in einer dieser Zeilen „nicht maskiert: Invalid“:

1. Die Uhrzeit der Änderungszeile mit dem vergleichen, was gerade geschah (Package geladen, Projekt geöffnet, Tests
   gestartet).
2. Andere Experten und Design-Packages (etwa TestInsight) testweise abschalten, die IDE neu starten und die Startzeile
   erneut ansehen. Bleibt danach alles bei `$033F (alle maskiert)`, kommt die Änderung von einem der abgeschalteten.
3. Die Zeilen zusammen mit dem Absturzabbild an den Hersteller dieses Experten bzw. an Embarcadero geben.

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

### Ablaufprotokoll

Für genaue Fehlersuche schreibt dpcc den Ablauf jeder Aktion in ein eigenes Protokoll (früher „Diagnoseprotokoll“):
für Strg+Klick bzw. „Deklaration suchen“, Vervollständigung, Hover und Parameterhilfe je Schritt eine Zeile, vom
Aufruf der IDE bis zum Ergebnis. Alle Zeilen einer Aktion tragen dieselbe Kennung (`#12 Sprung: …`,
`#13 Vervollständigung: …`); die letzte Zeile einer Kette sagt, wo und warum sie endet. Dazu stehen dort wie bisher
die übrigen Aufrufe der IDE an den Code-Insight-Manager.

Einschalten:

1. **Tools › Optionen › Drittanbieter › dpcc**, Abschnitt **IDE**: „Ablauf protokollieren (Log)“ anhaken und mit OK
   bestätigen. Das wirkt sofort, ohne Neustart. Das Meldungsfenster (Gruppe dpcc) nennt die Datei („dpcc: Der Ablauf
   wird protokolliert in …“), der Hint am Schalter ebenso.
2. Oder wie bisher von Hand: unter `HKCU\Software\dpcc\IdePlugin` den DWORD-Wert `Diagnose` = 1 anlegen und die IDE
   neu starten. Es ist derselbe Wert; die Seite zeigt ihn angehakt.

| | |
|---|---|
| Ort | neben der Plugin-BPL: `dpcc.IDE.Expert290.log` (Delphi 12) bzw. `dpcc.IDE.Expert370.log` (Delphi 13), etwa `Output\Win32\Debug\Bpl\dpcc.IDE.Expert370.log` |
| Ältere Dateien | `dpcc.IDE.Expert370.1.log` bis `….4.log`; höchstens 5 Dateien zu je 1 MB |
| Inhalt | je Schritt eine Zeile mit Uhrzeit: Einstieg der IDE, jeder frühe Ausstieg mit Grund, Antworten des Servers, Ergebnis an die IDE. Dateien nur mit Namen, Stellen als Zeile:Spalte |
| Nie enthalten | Ordner und Benutzername (ersetzt), Quelltext außer dem einen Wort an der Stelle |

Beispiel: Strg+Klick auf den Namen einer Methode in der Klasse (Zeile 12), Sprung zur Implementierung (Zeile 40):

```
10:15:02.114 #7 Sprung: Eintritt IOTACodeInsightManager.GotoDefinition(Index -1), Datei Haupt.pas
10:15:02.115 #7 Sprung: Stelle der IDE keine (nur Index), Strg True, Cursor 12:15 (Editorspalte 15), Maus über Bezeichner 12:16, gefragt 12:16 (Maus)
10:15:02.115 #7 Sprung: Stelle Haupt.pas 12:16 (Maus), Wort „Rechne“
10:15:02.118 #7 Sprung: declaration: Haupt.pas 12:15 nach 3 ms
10:15:02.118 #7 Sprung: OnTarget ja (Datei gleich; Zeile ja, 12 | 12; Stelle im Wort ja, Spalte 16, Ziel ab 15)
10:15:02.121 #7 Sprung: definition: Haupt.pas 40:20
10:15:02.121 #7 Sprung: Antwort der Sitzung nach 6 ms: Haupt.pas 40:20
10:15:02.121 #7 Sprung: Ergebnis an die IDE: True, Haupt.pas Zeile 40; gleich der Ausgangsstelle: nein
```

Springt die Deklaration nicht, zeigt die Kette den Schritt, an dem es hängt: `OnTarget nein (Datei verschieden …)`
mit „definition nicht gefragt“ (die IDE und der Server schreiben die Datei verschieden), `definition: leer` oder eine
`definition`, die wieder auf die Deklaration zeigt, und zuletzt `gleich der Ausgangsstelle: ja (die IDE bleibt in
derselben Zeile)`. Ob der Server ein Paar aus Deklaration und Implementierung gefunden hat, steht im
[Diagnoselog des Servers](#diagnoselog-des-servers) in der Zeile `declaration` bzw. `definition` derselben Uhrzeit:
`pair=found pairChosen=implementation` oder `pair=none:<Grund>` mit `pairSame` (Fundstellen der Routine) und
`pairVariant` (davon mit passenden Parametertypen). Gründe: `noUnit` (Unit des Ziels nicht im Index), `noSymbol`
(Routine dort nicht gefunden), `single` (nur eine Fundstelle, keine zweite Hälfte), `params` (mehrere Fundstellen,
aber die Parametertypen passen nicht zusammen).

Was mitschicken:

1. „Ablauf protokollieren (Log)“ einschalten (OK).
2. Die Aktion einmal ausführen, etwa Strg+Klick auf die Deklaration.
3. Die Zeilen dieser Kennung aus dem Ablaufprotokoll schicken, dazu `dpcc.log` und das Diagnoselog des Servers vom
   selben Tag. Vor dem Weitergeben ansehen: Dateinamen und das Wort an der Stelle stehen im Klartext.
4. Den Schalter wieder ausschalten.

Abschalten: Häkchen entfernen und OK (wirkt sofort) bzw. den Registry-Wert löschen oder auf 0 setzen. Die Messung der
langsamsten Aufrufe beim Entladen und die Hänger ohne dpcc-Aktion (siehe unten) folgen dem Schalter erst nach dem
nächsten Start der IDE.

### Hänger und langsame Aktionen

Ein Wächter prüft alle 50 ms, ob der Hauptthread der IDE antwortet. Zusammen mit den Zeiten der dpcc-Aktionen
schreibt er diese Zeilen ins `dpcc.log`:

| Zeile | Bedeutung |
|---|---|
| `Hauptthread hängt seit 260 ms in Vervollständigung öffnen` | Die IDE reagiert seit 250 ms oder länger nicht, während dpcc diese Aktion ausführt. Steht sofort im Protokoll, auch wenn die IDE danach nicht mehr reagiert. |
| `Hauptthread hing 1300 ms in Vervollständigung öffnen` | Die IDE reagiert wieder; Gesamtdauer des Hängers. |
| `Hauptthread: Symbolhinweis: 87 ms` | Eine dpcc-Aktion hielt die IDE 50 ms oder länger auf, ohne dass sie hing. |
| `Hauptthread wartete 340 ms auf Server textDocument/completion: Zeitlimit` | Die IDE wartete 100 ms oder länger auf eine Antwort des Servers; Ausgang: `Antwort`, `Zeitlimit`, `abgebrochen` oder `Fehler`. |
| `Hänger mit dpcc-Aktivität in dieser Sitzung: 3, längster 1300 ms, …` | Zusammenfassung beim Entladen, wenn es Hänger gab. |

Die Zeilen sind gedrosselt: je Aktion höchstens eine Zeile pro Minute (`dazu n weitere …` nennt die übergangenen),
höchstens 5 Hänger pro Minute einzeln (`… nicht einzeln protokolliert, zusammen n ms`). Hängt die IDE ohne
dpcc-Aktion (etwa beim Compilieren), schreibt dpcc nichts. Modale Dialoge zählen nicht als Hänger, ebenso Zeit, in der
die IDE im Debugger angehalten war.

Mit `Diagnose` = 1 bzw. „Ablauf protokollieren (Log)“ beim Start der IDE (siehe oben) stehen zusätzlich Hänger ohne
dpcc-Aktion als `… ohne dpcc-Aktivität` im Ablaufprotokoll, und beim Entladen folgen dort die 10 langsamsten Aufrufe,
Server-Anfragen und Abfragen der Vervollständigung.

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
