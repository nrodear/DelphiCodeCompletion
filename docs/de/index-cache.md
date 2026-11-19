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
- die Bibliotheks- und Suchpfade der Installation (RTL, VCL, Komponenten) samt Office-Typbibliotheken und WinRT
  (siehe [unten](#office-typbibliotheken-und-winrt));
- die zusätzlichen Quellordner (siehe [unten](#zusätzliche-quellordner)).

Dazu kommen:

- Konfiguration, Plattform, bedingte Symbole, Suchpfade und Unit-Namespaces der aktiven Konfiguration, auch
  ungespeicherte Änderungen. Makros wie `$(BDS)` in Pfaden setzt dpcc wie die IDE ein: zuerst die Umgebungsvariablen
  der IDE-Optionen, dann die Ordner der Installation, zuletzt alle Umgebungsvariablen des Prozesses. Einen Pfad mit
  einem Verweis, den dpcc nicht auflösen kann, lässt es weg und nennt ihn in `dpcc.log` („… mit unaufgelöstem Verweis
  übergangen“).
- Bibliothekspfad und Browsing Path der laufenden IDE, auch mit eigenem Profil (`bds -r`). Win64x hat in der Registry
  keinen eigenen Browsing Path; dort gilt der von Win64.
- die Typen der Packages, die in der IDE geladen sind, auch ohne Quelltext. dpcc meldet sie beim Start jeder
  Sitzung an den Server. Aus den Packages der Installation zählen nur Units ohne Quelltext (etwa DUnitX, DUnit,
  FireDAC); was als `.pas` unter `$(BDS)\source` oder `$(BDS)\OCX` liegt, kommt aus dem Quelltext. Die Mitglieder
  dieser Typen holt der Server nur für Units, die ein Projekt in seinen `uses` nennt.
- Units aus `uses X in 'Pfad'` in der `.dpr`, auch ohne Eintrag in der `.dproj`. Die `uses` einer Unit sucht dpcc wie
  der Compiler zuerst in ihrem eigenen Ordner.
- Eine Datei außerhalb der Projektgruppe bekommt das Projekt aus ihrem Ordner oder einem darüber. Liegen dort mehrere
  `.dproj`, gilt die, die die Datei nennt, sonst die erste in alphabetischer Reihenfolge. Ohne Projekt gilt der Ordner
  der Datei als Suchpfad; seine Units lädt dpcc bei Bedarf.

Der Index enthält Deklarationen, keine Verwendungen. Seine Speichergrenze ist fest (768 MB).

### Inhalt je Deklaration

Seit Cache-Format 35 hält der Index je Deklaration mehr fest:

- Werte von Aufzählungen ohne `{$SCOPEDENUMS ON}` stehen im Katalog. „+ Unit“ schlägt damit auch `fsBold`, `ssShift`
  oder `rfReplaceAll` vor. Werte anonymer Aufzählungen (`set of (a, b)`, `F: (x, y)`) und Felder anonymer Records
  (`F: record … end`) stehen mit dem Typ- bzw. Feldnamen als Container im Index.
- Der Katalog kennt die Zahl der Typparameter. „+ Unit“ zeigt generische Typen mit Platzhaltern (`TList<T>`) und fügt
  nur den Namen ein. Steht hinter dem Wort ein `<`, kommt der generische Typ zuerst, sonst der gleichnamige ohne
  Typparameter (etwa `TList` aus `System.Classes`).
- Ein ausdrücklicher Wert in einer Aufzählung (`A = B + 1`) gehört zu seinem Wert; vorher zählte `B` als weiterer Wert.
- In Units der Bibliothek speichert der Index die Rümpfe im implementation-Teil nicht mehr, die eine Deklaration aus
  dem interface wiederholen. Die Angaben einer DLL-Routine (`external`, `name`, `index`, `delayed`) und die Zeile des
  Rumpfs stehen an der Deklaration. Routinen, die nur im implementation-Teil stehen, bleiben. Projekt-Units sind davon
  nicht betroffen.
- Zeiger, Arrays, Mengen, `class of`, Prozedurtypen und Teilbereiche behalten ihren Zieltyp (`PInteger` → `^Integer`,
  samt Array-Grenzen), auch bei Feldern und Variablen mit anonymem Typ. Ebenso stehen Attribute (`[Weak]`), die Arten
  `resourcestring`, `threadvar`, `class operator` und `destructor`, die Nachricht hinter `message` und die
  Einschränkungen der Typparameter im Index.
- Signaturen von Routinen, Methoden und Konstruktoren stehen bis 1000 Zeichen im Index, alle anderen bis 300 Zeichen.
  Die volle Länge liest dpcc bei Bedarf aus der Quelldatei, ebenso die Deklaration aus einem nicht geltenden Zweig
  (Detailanzeige der Liste).
- Bedingte Kompilierung: Konstanten der eigenen Unit wie `GenericSafeArrays = False` wertet dpcc in `{$IF}` aus,
  `Declared()` kennt die eingebauten Typen (`AnsiChar`, `Integer` …), und die Bibliothek liest `{$IFOPT}` mit den
  Vorgaben des Compilers. Vorher galten in diesen Fällen beide Zweige. Eine gleichnamige Deklaration eines nicht
  geltenden Zweigs (`{$IFDEF WIN64} function F(…)` … `{$ELSE}` …) erscheint als nicht verfügbar, auch wenn der
  geltende Zweig denselben Namen hat; `A, B: T` in einem `var`-Abschnitt liefert beide Namen.
- `.dpk`: `contains` gilt wie `uses`, `requires` steht getrennt.
- Den XMLDoc-Kurztext speichert der Index nicht mehr. Hover und Liste lesen die Doku wie bisher aus der Quelldatei.

### Bibliothek bei Bedarf

Von der Bibliothek hält der Index nur einen Teil mit allen Symbolen im Speicher. Immer geladen (gepinnt) sind:

- die Units der Projekte und ihrer Suchpfade;
- die Units, die die Projekte über `uses` erreichen (interface und implementation der Projekt-Units, von dort weiter
  über die `uses` im interface);
- die Units, die eine Projekt-Unit in ihren `uses` nennt, auch eben getippte in einer offenen Datei;
- oft genutzte Units der Bibliothek (siehe [Nutzungsstatistik](#nutzungsstatistik)).

Von allen übrigen Units kennt der Index einen Katalog: Name, Datei, `uses`, die ersten Typen und alle Symbole, die
eine andere Unit importieren kann. Darüber zeigen „+ Unit“, gleichnamige Symbole aus anderen Units, die
Vervollständigung im `uses`-Abschnitt und die Suche nach Class Helpern weiter alle Units. Die vollständigen Symbole
einer solchen Unit liest dpcc erst, wenn Vervollständigung, Hover, Parameterhilfe oder Gehe zu Definition sie brauchen,
aus ihrem Block im Cache. Das dauert meist unter 5 ms, bei sehr großen Units bis etwa 150 ms.

Belegen die so nachgeladenen Units zusammen geschätzt mehr als 32 MB, gibt dpcc die am seltensten genutzte wieder frei, bei
Gleichstand die am längsten nicht genutzte. Es gibt immer die ganze Unit frei; ihr Katalogeintrag bleibt. Die Grenze
ist fest und keine Einstellung. Units aus den `uses` einer Projekt-Unit und oft genutzte zählen dabei nicht mit; sie
sind gepinnt (siehe oben).

Einschränkung: Aktionen, die einen Namen in allen Units suchen (etwa beim Anlegen von Zugriffsmethoden oder bei
Feldnamen aus Datenmodulen), finden Symbole oberster Ebene aller Units und laden die Units dafür nach. Eine solche Suche
übernimmt die Treffer jeder nachgeladenen Unit sofort; die Grenze von 32 MB gilt dabei weiter, auch für andere Anfragen.
So sieht sie alle Treffer, ohne dass bei häufigen Namen (etwa `Register`) alle ihre Units zugleich im Speicher liegen.
Mitglieder von Klassen und Records finden sie nur in geladenen Units.

Deklarationen aus Include-Dateien (`{$I …}`) einer Unit, die nur im Katalog steht, findet dpcc über eine Tabelle
Include-Datei → Unit: Der Kopf jeder Unit nennt ihre Include-Dateien, auch bei Units, die nur im Katalog stehen
(sie stehen im Verzeichnis des Caches). Hover, Parameterhilfe und die Details der Vervollständigung laden so die
einbindende Unit nach, bei [gleichnamigen Units](#gleichnamige-units) die Datei, die die Include-Datei einbindet. Die
Tabelle hält einen Eintrag je Include-Datei und ändert das Cache-Format nicht (weiter Format 35).

Nach `raise`, `on E: ` und in Attributklammern prüft die Vervollständigung Klassen aus Units, die nur im Katalog
stehen, über die Vorfahren im Katalog und lädt diese Units dafür nicht nach. Klassen aus Packages der IDE ohne
Quelltext kommen über ihren Vorfahren dazu, wie ihn die IDE meldet.

#### Nutzungsstatistik

dpcc zählt je Unit der Bibliothek, wie oft Anfragen sie brauchen und wie oft eine Projekt-Unit sie neu in ihre `uses`
aufnimmt, etwa über „+ Unit“. Die Punkte halbieren sich jede Woche. Oft genutzte Units lädt der nächste Aufbau gleich,
und dpcc gibt sie nicht wieder frei. Die Statistik steht in `usage.dat` neben dem Bibliotheks-Cache (siehe
[Cache](#cache)). Der Server schreibt sie beim Beenden und höchstens alle 10 Minuten, und nur, wenn sie sich geändert
hat; zwei Schreibvorgänge laufen nie gleichzeitig. Geht sie verloren, beginnt sie neu; der Index merkt davon nichts.

### Office-Typbibliotheken und WinRT

`$(BDS)\OCX\Servers` (Typbibliotheken von Excel, Word, Outlook und Access) und `$(BDS)\source\rtl\win\winrt`
gehören zur Bibliothek wie jede andere Unit der Installation: Sie stehen im Bibliotheks-Cache und im Katalog, „+ Unit“
schlägt ihre Symbole vor. Im Speicher liegt nur ihr Katalog; die Symbole einer Unit lädt dpcc erst, wenn
Vervollständigung, Hover oder Parameterhilfe sie brauchen.

- Nennt eine Unit außerhalb der Installation sie in ihren `uses`, bleibt sie geladen. Über die `uses` anderer Units der
  Installation kommt sie nicht dazu.
- Den früheren Schalter „Office-Typbibliotheken und WinRT vorab indizieren“ (`index.officeAndWinRt`) gibt es nicht mehr.
  Ein Wert in `settings.json` wirkt nicht und erzeugt keine Meldung.
- Der erste Start nach dem Update liest diese Units einmal ein. Der Bibliotheks-Cache wächst um rund 41 MB,
  der Katalog im Speicher um rund 7 MB. Den bisherigen Bibliotheks-Cache ohne sie räumt dpcc nach
  `index.cacheMaxAgeDays` Tagen ohne Benutzung weg.

### Zusätzliche Quellordner

Units, die die Installation nur als `.dcu` mitbringt (DUnitX, DUnit, FireDAC …), kennt dpcc aus der IDE nur mit ihren
Typen (siehe [oben](#was-im-index-steht)). Liegt ihr Quelltext auf der Platte, nennt man seinen Ordner auf der Seite
**dpcc** unter „Zusätzliche Quellordner“ (`index.extraSourceFolders` in `settings.json`, siehe
[Einstellungen](settings.md#index)):

- mehrere Ordner mit `;` getrennt, in `settings.json` auch als Liste;
- Unterordner zählen mit, außer `.git`, `__history` und `__recovery`; höchstens 2000 Ordner; `index.exclude` gilt;
- `$(Name)` (Variablen der IDE und der Umgebung) und `%Name%` (Umgebung) werden aufgelöst; ein relativer Pfad gilt ab
  dem Projektordner;
- ihre Units kommen wie die Bibliothek in den Index: im Katalog („+ Unit“), geladen bei Bedarf, gelesen mit den
  Symbolen von Plattform und Version, nicht denen des Projekts. Sie haben einen eigenen Cache (siehe [Cache](#cache)),
  ein anderer Ordner liest also nicht die ganze Bibliothek neu.

Beispiel: die Quellen von DUnitX, `…\DUnitX\Source`. Das sind 64 Units mit rund 2600 Symbolen; der erste Aufbau liest sie in
weniger als einer Sekunde, ihr Cache hat 0,3 MB, der Katalog wächst um rund 0,1 MB.

### Gleichnamige Units

Gibt es eine Unit mehrfach, etwa eine angepasste Kopie einer Bibliotheks-Unit im Projekt oder `Unit1` in zwei
Projekten der Gruppe, behält der Index alle Dateien. Welche gilt, entscheidet das Projekt der Datei, in der man
arbeitet, in der Reihenfolge des Compilers: Units des Projekts, Projektordner, Suchpfade, Bibliothek, zusätzliche
Quellordner. Ohne Projektbezug gilt: Projekt vor Suchpfad vor Bibliothek vor Zusatzordner. Auch die Unit-Namespaces
(`DCC_Namespace`) gelten je Projekt.

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
- Ordner außerhalb davon (Suchpfade in anderen Repositories, Komponenten im Bibliothekspfad, zusätzliche Quellordner,
  `$(BDS)`) prüft der Server selbst: bei Arbeit im Editor höchstens alle 10 Sekunden, in einem eigenen Thread. Neue,
  geänderte und gelöschte Units übernimmt er.
- Eine neue Unit in einem Suchpfad, Bibliotheksordner oder zusätzlichen Quellordner kommt gleich in den Index, nicht
  erst, wenn eine Unit sie nennt.
- Lädt dpcc eine Unit der Bibliothek bei Bedarf, prüft es vorher den Stand ihrer Datei; ist er anders als im Cache, liest
  es sie neu.
- Als geändert gilt eine Datei mit anderem Zeitstempel oder mit gleichem Zeitstempel und anderer Größe.
- Eine Änderung nur am Browsing Path der IDE baut den Index neu auf.
- Eine Datei, die sich nicht lesen oder parsen lässt (etwa wegen ihrer Kodierung), fehlt im Index; der Aufbau läuft
  weiter. `dpcc.log` nennt sie mit Pfad und Fehler („Datei nicht lesbar, im Index übergangen“), das Diagnoselog zählt sie
  („index project#n unreadable“). Ist der Speicher erschöpft, liest der Aufbau danach keine Dateien mehr und behält den
  Stand bis dahin.
- Offene Formulare gehen mit ihrem aktuellen Stand aus dem Designer an den Server, nicht von der Platte.

## Cache

Der Cache liegt unter `%LOCALAPPDATA%\dpcc\Index`:

| Pfad | Inhalt |
|---|---|
| `Index\<IDE-Version>\<Hash>\index-<Format>.dpccidx` | Cache eines Projekts |
| `Index\<IDE-Version>\Bibliothek\<Hash>\index-<Format>.dpccidx` | Cache der Bibliothek, getrennt vom Projekt |
| `Index\<IDE-Version>\Bibliothek\<Hash>\usage.dat` | Nutzungsstatistik der Bibliothek (siehe [oben](#nutzungsstatistik)) |
| `Index\<IDE-Version>\Zusatzordner\<Hash>\index-<Format>.dpccidx` | Cache der zusätzlichen Quellordner, je Plattform, Version und Ordnern |
| `…\<cache>.lock` | Sperre; nur die erste Instanz schreibt den Cache, weitere lesen ihn nur |
| `…\projekt.txt` | Projektdatei, zu der der Cache gehört |
| `…\benutzt.stamp` | Zeitpunkt der letzten Benutzung |

Die Formatversion steht im Dateinamen. So stören sich verschiedene Versionen von dpcc nicht gegenseitig.

Seit Format 34 steht jede Unit in einem eigenen Block mit eigener Prüfsumme. Ein Verzeichnis am Ende der Datei nennt
alle Units samt ihrem Katalog. dpcc liest beim Start nur das Verzeichnis und die Blöcke der Units, die es lädt, über ein
offenes Handle; eine andere Instanz kann die Datei trotzdem ersetzen. Ein beschädigter Block betrifft nur seine Unit,
dpcc liest sie dann aus der Quelldatei neu. Das aktuelle Format 35 bringt die Inhalte aus
[Inhalt je Deklaration](#inhalt-je-deklaration). Das Verzeichnis nennt je Unit auch ihre Include-Dateien; daraus
entsteht beim Start die Tabelle Include-Datei → Unit (siehe [Bibliothek bei Bedarf](#bibliothek-bei-bedarf)).

Caches älterer Formate (etwa `index-34.dpccidx`) liest dpcc nicht mehr: Der erste Start nach dem Update baut den Index
einmal neu auf. Sobald dpcc einen Cache im neuen Format geschrieben hat, löscht es im selben Ordner die Dateien
`index-<Nummer>.dpccidx` älterer Formate samt ihrer `.lock`-Datei, sofern keine andere Instanz sie sperrt (etwa eine
ältere Version von dpcc in einer zweiten IDE). Andere Dateien bleiben. „Index neu aufbauen“ (siehe
[unten](#index-neu-aufbauen)) löscht alle Caches sofort.

Beim ersten Aufbau ohne Cache schreibt dpcc den Bibliotheks-Cache zwischendurch, damit die neu gelesenen Units den
Speicher wieder verlassen dürfen. Dabei hängt es nur die neuen Blöcke und ein neues Verzeichnis an die Datei an, und
zwar nur an die Datei, die es selbst zuletzt geschrieben hat (gleicher Zeitstempel, gleiche Größe, gleicher Kopf); sonst
schreibt es sie ganz. Den Projekt-Cache schreibt es zwischendurch nur, wenn Units der Bibliothek außerhalb der
Installation hinzugekommen sind (etwa Quellen von Drittanbietern; sie stehen im Projekt-Cache), sonst erst am Ende des
Aufbaus. Jedes Anhängen lässt das vorige Verzeichnis als ungenutzten Platz in der Datei; ist er am Ende eines Aufbaus
größer als 4 MB oder als 10 % der Datei, schreibt dpcc sie ganz neu. Bricht das Anhängen ab, gilt der vorige Stand
weiter, und wer die Datei gerade liest, liest seine Blöcke unverändert weiter. Die Zeilen „cacheWrite library“ des
Diagnoselogs nennen bei den Zwischenständen nur die angehängten KB.

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

**Tools › Optionen › Drittanbieter › dpcc › Index neu aufbauen**:

1. dpcc fragt nach: „Alle Index-Caches löschen und den Index neu aufbauen? Der erste Aufbau kann einige Minuten
   dauern.“
2. Eine laufende Sitzung hält es an, löscht alle Index-Caches, die nicht gesperrt sind, und startet die Sitzung neu.
   Das läuft im Hintergrund; die IDE bleibt bedienbar. Solange es läuft, ist der Knopf grau und daneben steht
   „Index wird neu aufgebaut: Sitzung wird angehalten, Caches werden gelöscht …“. Die Optionen dürfen
   währenddessen geschlossen werden; beim nächsten Öffnen zeigt die Seite den aktuellen Stand.
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
ist fest. Ebenso `index.officeAndWinRt`: Office-Typbibliotheken und WinRT stehen immer im Katalog (siehe
[oben](#office-typbibliotheken-und-winrt)). `index.extraSourceFolders` wirkt (siehe
[oben](#zusätzliche-quellordner)).
