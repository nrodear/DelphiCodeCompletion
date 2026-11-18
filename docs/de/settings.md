Deutsch | [English](../en/settings.md) | [Français](../fr/settings.md)

# Einstellungen

[Übersicht](index.md) › Einstellungen

Die Optionen stehen unter **Tools › Optionen › Drittanbieter › dpcc**. Das ist eine einzige Seite ohne Unterseiten.

## Die Seite

- Oben steht der Hauptschalter, darunter folgen die Abschnitte **Vervollständigung**, **Beim Übernehmen**,
  **Parameter-Hint und Tooltip**, **Index** und **IDE**.
- Ist der Hauptschalter aus, sind alle Optionen darunter und der Knopf „Verlauf zurücksetzen“ grau. „Index neu
  aufbauen“ und „Jetzt prüfen“ bleiben bedienbar.
- „Werte beim Debuggen zeigen“ ist grau, solange „Eigener Tooltip beim Verweilen über Bezeichnern“ aus ist.

Gespeichert wird mit **OK**. Ausnahmen: „Verlauf zurücksetzen“ und „Index neu aufbauen“ wirken sofort, „Jetzt
prüfen“ liest nur.

Einige frühere Optionen stehen nicht mehr auf der Seite und gelten fest (siehe
[Fest eingestellte Werte](#fest-eingestellte-werte)).

Die Spalte „Registry-Wert“ nennt den Namen unter `HKCU\Software\dpcc\IdePlugin`, die Spalte „Schlüssel“ den Namen,
den dpcc in Hinweisen und in `settings.json` verwendet. „–“ bei „Registry-Wert“: Die Option liegt nicht in der
Registry, sondern in `settings.json` (siehe [Ablage](#ablage)).

## Hauptschalter

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Code Insight von dpcc (stellt den Code-Insight-Anbieter der IDE auf dpcc um; aus = DelphiLSP) | `Enabled` | `completion.enabled` | an | Hauptschalter und Betriebsart. An mit OK: dpcc stellt den Code-Insight-Anbieter der IDE auf dpcc und setzt die nötigen Schalter der IDE; aus mit OK: zurück auf den vorigen Anbieter (Vorgabe DelphiLSP), eigene Änderungen zurück. Der Anbieterwechsel wirkt nach dem Neustart von Delphi. Beim Start von Delphi gilt der gewählte Anbieter: Ist DelphiLSP gewählt, schaltet dpcc sich aus. Siehe [Was dpcc an der IDE umstellt](#was-dpcc-an-der-ide-umstellt). Liste, Parameterhilfe und Tooltip von dpcc folgen dem Schalter sofort (aus: Strg+Leertaste und Strg+Umschalt+Leertaste gehen an die IDE); der Server läuft beim Ausschalten weiter. |

## Vervollständigung

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Beim Tippen öffnen ab Zeichen (0 = nie): | `AutoMinChars` | `completion.autoMinChars` | 0 | 0 bis 10; Vorgabe 0 = aus (wie vor dem Öffnen beim Tippen), zum Einschalten z. B. 5 einstellen. Tippt man einen Namen ohne Punkt davor, öffnet die Liste erst, wenn das Wort vor dem Cursor so viele Zeichen hat; darunter fragt dpcc den Server nicht. 0 = Tippen öffnet nie. Strg+Leertaste öffnet bei jeder Länge; nach „.“ und bei den übrigen Auslösern ändert sich nichts. Damit die IDE beim Tippen nicht zusätzlich ihre eigene Liste öffnet, stellt dpcc in der Betriebsart dpcc `Auto Invoke Delay` = -1 (siehe [unten](#was-dpcc-an-der-ide-umstellt)). Siehe [Bedienung](usage.md#öffnen-beim-tippen). |
| Beim Tippen zeigen: | `CompletionListMode` | `completion.listMode` | Nur Treffer | „Nur Treffer“ (`filter`), „Alle Einträge, Treffer oben“ (`all`), „Treffer, darunter gedämpft der Rest“ (`rest`, unter der Überschrift „Weitere Einträge“). Gilt für Mitgliederlisten nach „.“ (fest eingestellt). |
| Sichtbare Zeilen der Liste: | `VisibleRows` | `completion.visibleRows` | 9 | 5 bis 20 Zeilen. |
| Breite automatisch | `ListWidth` | `completion.listWidth` | an (`ListWidth` = 0) | Steht in derselben Zeile wie „Sichtbare Zeilen der Liste“. An: Die Liste wächst mit dem breitesten Eintrag. Aus: die zuletzt gezogene Breite (240 bis 720). Ziehen am rechten Rand der Liste setzt die Breite ebenfalls. |
| Häufig und zuletzt gewählte Einträge nach oben | `Learning` | `completion.learning` | an | Lernende Gewichtung: Übernommene Einträge bekommen einen Zuschlag in der Rangfolge. Ab 5 Übernahmen gilt ein Eintrag als „häufig“. Gespeichert in `%APPDATA%\dpcc\usage.json`, höchstens 5.000 Einträge. |
| Knopf „Verlauf zurücksetzen“ | – | – | – | Steht rechts neben „Häufig und zuletzt gewählte Einträge nach oben“. Leert die lernende Gewichtung sofort; danach bleibt der Knopf grau, bis der Dialog schließt. |

## Beim Übernehmen

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Klammern bei Methoden ergänzen | `AutoParentheses` | `completion.autoParentheses` | an | Ergänzt beim Übernehmen einer Methode die Klammern; ein direkt davor getipptes „)“ überspringt die automatische. |
| Übernehmen mit „(“, „;“ und „.“ | `CommitCharacters` | `completion.commitCharacters` | an | Commit-Zeichen: Trifft der gewählte Eintrag eindeutig, übernimmt eines dieser Zeichen ihn; das Zeichen bleibt stehen. Sonst bleibt nur das Zeichen, und die Liste schließt. |
| Unit automatisch in uses eintragen | `AutoUses` | `completion.autoUses` | an | Bei Einträgen, die rechts „+“ und den Namen einer Unit zeigen (etwa „+ System.SysUtils“), trägt dpcc diese Unit beim Übernehmen in `uses` ein, im selben Undo-Schritt. |

## Parameter-Hint und Tooltip

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Parameter-Hint bei „(“ und „,“ | `ParameterHints` | `completion.parameterHints` | an | Aus: keine Parameterhilfe von dpcc, auch nicht über Strg+Umschalt+Leertaste. Das automatische Öffnen bei „(“ und „,“ erreicht dpcc nur, wenn die IDE dpcc als Anbieter aufruft (siehe [Bedienung](usage.md#zusammenspiel-mit-delphilsp)). |
| Eigener Tooltip beim Verweilen über Bezeichnern | `HoverTooltip` | `editor.hoverTooltip` | an | Tooltip von dpcc. Solange er an ist, schaltet dpcc in der Betriebsart dpcc Help Insight und den Kurzhinweis Symbol-Insight der IDE ab (`Help Insight`, `Declaration Information`). Gesperrt, solange der Hauptschalter aus ist. |
| Werte beim Debuggen zeigen (schaltet den Wert-Tooltip der IDE ab) | `DebugHoverValues` | `debug.hoverValues` | an | Steht eingerückt unter dem Tooltip. Bei angehaltenem Programm steht der Wert des Ausdrucks oben im Tooltip; dpcc schaltet dann die Ausdrucksauswertung im Kurzhinweis der IDE ab (`ToolTip Watches`). Wer den Wert-Tooltip der IDE will, schaltet diese Option aus. Gesperrt, solange „Eigener Tooltip …“ aus ist. |

## Index

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Zusätzliche Quellordner (mit „;“ getrennt, samt Unterordnern): | – | `index.extraSourceFolders` | leer | Ordner mit dem Quelltext von Bibliotheken, die sonst nur als `.dcu` vorliegen (DUnitX, DUnit, FireDAC, Komponenten). Unterordner zählen mit (ohne `.git`, `__history`, `__recovery`); `$(Name)` und `%Name%` werden aufgelöst. Ihre Units schlägt „+ Unit“ vor, geladen werden sie bei Bedarf; sie haben einen eigenen Cache. Liegt in `%APPDATA%\dpcc\settings.json` (in der Datei auch als Liste), nicht in der Registry; der Server baut den Index ohne Neustart um. Ersetzt den früheren Schalter `index.officeAndWinRt`: Office-Typbibliotheken und WinRT stehen immer im Katalog. Siehe [Index und Cache](index-cache.md#zusätzliche-quellordner). |
| Knopf „Index neu aufbauen“ | – | – | – | Fragt nach, löscht alle Index-Caches und baut den Index neu auf. Hängt nicht am Hauptschalter. Siehe [Index und Cache](index-cache.md#index-neu-aufbauen). |

## IDE

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Knopf „Jetzt prüfen“ | – | – | – | Rechts daneben stehen bis zu vier Zeilen: Betriebsart und Anbieter, ob ein Wechsel noch auf den Neustart von Delphi wartet, was dpcc an der IDE gesetzt hat und das Ergebnis der Prüfung (etwa „1 Abweichung: Auto Code Completions“). Beim Öffnen der Seite gelesen, der Knopf liest neu. Liest nur, ändert nichts; hängt nicht am Hauptschalter. Siehe [Was dpcc an der IDE umstellt](#was-dpcc-an-der-ide-umstellt). |

## Fest eingestellte Werte

Diese Optionen stehen nicht mehr auf der Seite. Sie gelten fest mit ihrer bisherigen Vorgabe:

- **Verzögerung bis zum automatischen Öffnen (etwa nach „.“): 150 ms** (`OpenDelayMs`, `completion.openDelayMs`).
  Gilt nur für das automatische Öffnen (nach „.“ und beim Tippen), nicht für Strg+Leertaste. Automatisch öffnet
  dpcc nur in der Betriebsart dpcc; in der Betriebsart IDE (DelphiLSP gewählt) ist dpcc aus (siehe
  [Bedienung](usage.md#zusammenspiel-mit-delphilsp)).
- **Favoriten anheften mit Strg+D: an** (`Favorites`, `completion.favorites`). Strg+D in der offenen Liste heftet an
  bzw. löst; die Favoriten liegen weiter in `%APPDATA%\dpcc\favorites.json`. Siehe
  [Bedienung](usage.md#favoriten).
- **Geerbte Member nachrangig und nach Klasse gruppiert: an** (`GroupInherited`, `completion.groupInherited`). Ohne
  getippten Anfang: eigene Member zuerst, dann je Vorfahr eine Gruppe „Geerbt von …“. Mit Anfang steht bei gleicher
  Güte der eigene Member vor dem geerbten.
- **Zweig varianter Record-Felder zeigen: an** (`CompletionVariantBranch`, `completion.variantBranch`). Bei Feldern
  im varianten Teil eines Records (`case … of`) steht die Marke „Zweig 0“, „Zweig 1“ usw.
- **Listenmodus gilt für: Mitgliederlisten nach „.“** (`CompletionListScope`, `completion.listMode.scope` =
  `members`). „Beim Tippen zeigen“ wirkt nur dort.
- **Vorschau des gewählten Eintrags im Editor: entfallen** (früher `Preview`, `completion.preview`, zuletzt fest
  aus). Seit dem Aufräumen der Einstellungen gibt es auch den Code dafür nicht mehr.
- **Schreibweise beim Übernehmen korrigieren (showmessage → ShowMessage): an** (`FixCase`, `completion.fixCase`).
  Ersetzt das getippte Wort durch die Schreibweise der Deklaration.
- **Platzhalter von Format im Parameter-Hint zuordnen und einfärben: an** (`FormatPlaceholders`,
  `completion.formatPlaceholders`). Zeile zum Platzhalter am Cursor, Warnungen, gleiche Farbe für Platzhalter und
  Argument; nur, solange „Parameter-Hint bei „(“ und „,““ an ist.
- **XMLDoc: höchstens Zeilen ohne Scrollen: 0 = Bildschirm** (`XmlDocMaxLines`, `hints.xmlDocMaxLines`). 0 bis 50.
  Mehr Zeilen scrollen im Tooltip mit dem Mausrad. 0: begrenzt nur der Platz auf dem Bildschirm. Nicht mehr auf der
  Seite, aber weiter über `hints.xmlDocMaxLines` in `%APPDATA%\dpcc\settings.json` einstellbar; der Server liest die
  Datei selbst.

## Nach dem Update

- Die frühere Aufteilung in **Allgemein**, **Vervollständigung**, **Einfügen** und **Hints** gibt es nicht mehr,
  ebenso Baum, Suchfeld, die Zeile „Filter:“, die Markierung geänderter Werte mit „Auf Standard zurücksetzen“ per
  Rechtsklick, die Liste „Angeheftete Favoriten“, den Knopf „Breiten zurücksetzen“ und den Schalter „Experimentelle
  Funktionen erlauben“ (der Schlüssel `experimental.enabled` in `settings.json` wirkt weiter).
- „XMLDoc beim Öffnen“ (`hints.xmlDocExpand`, davor `hints.xmlDocFull`) ist entfallen: Der Tooltip zeigt die XMLDoc
  immer aufgeklappt. Ein alter Wert in `settings.json` bleibt stehen und wird ohne Meldung übergangen; dpcc schreibt
  den Schlüssel nicht mehr.
- Wer eine der jetzt [fest eingestellten](#fest-eingestellte-werte) Optionen geändert hatte, verliert die Abweichung
  ohne Meldung. Die alten Werte unter `HKCU\Software\dpcc\IdePlugin` bleiben liegen und werden nicht mehr beachtet.
- OK speichert nur noch die Werte der Seite: den Hauptschalter und elf Optionen in der Registry,
  `index.extraSourceFolders` in `settings.json`. Früher schrieb jedes OK rund 600 Registry-Werte (auch versteckte
  Einstellungen früherer Reiter, Tasten, Modul-Schalter und experimentelle Schalter) und dazu Server-Schlüssel in
  `settings.json`: `slashCommands.enabled`, `codeLens.metrics`, `metrics`, `experimental.enabled`, `compiler.onSave`,
  `architecture.*`, `query.enabled`, `ruleChecks.enabled`, `hotspots.*`, `references.*`, `navigation.*`, `tests.*`,
  `issues.*` und `vcs.*`. Alle diese Werte bleiben liegen: dpcc liest die alten Registry-Werte nicht mehr, und der
  Server liest die Schlüssel in `settings.json` weiter, ohne Meldung. Fehlen sie, gelten seine Vorgaben; sie gleichen
  denen, die das Plugin früher geschrieben hat.
- „Werte beim Debuggen zeigen“ hängt nur noch an der eigenen Option (und auf der Seite am eigenen Tooltip). Der
  frühere versteckte Modul-Schalter `debug.enabled` (Registry-Wert `DebugEnabled`) schaltet sie nicht mehr ab.
- Den Einstellungsverlauf `%APPDATA%\dpcc\settings-history.json` schreibt dpcc nicht mehr. Eine vorhandene Datei
  bleibt liegen und kann gelöscht werden.

## Ablage

| Ort | Inhalt |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | alle Optionen der Seite außer `index.extraSourceFolders`. Schalter und Zahlen als DWORD (Schalter 0/1), Auswahlen als Text (`filter`, `all`, `rest`). Dazu die Merker für die IDE-Schalter (unten) und `PathOverrideBackup` von `Tools\IdePath.ps1`. Nur gelesen, nie geschrieben: der Support-Schalter `LogNames` (siehe [Fehlersuche](troubleshooting.md)). Alte Werte der fest eingestellten und der entfernten Optionen bleiben liegen, wirken aber nicht; dpcc schreibt sie nicht mehr. |
| `%APPDATA%\dpcc\settings.json` | `index.extraSourceFolders` (von der Seite) und `hints.xmlDocMaxLines` (nur in der Datei einstellbar). Der Server im IDE-Prozess liest die Datei selbst und beobachtet sie. dpcc liest `hints.xmlDocMaxLines` nur und schreibt den Schlüssel nie; fehlt er in der Datei, gilt ein Registry-Wert `XmlDocMaxLines` einer älteren Version, sonst 0. Andere Schlüssel der Datei fasst dpcc nicht an. Ein alter Wert `hints.xmlDocExpand` bzw. `hints.xmlDocFull` bleibt ohne Wirkung. |
| `%APPDATA%\dpcc\settings-history.json` | nur aus älteren Versionen: frühere Stände der Einstellungen. dpcc schreibt und liest die Datei nicht mehr; sie kann gelöscht werden. |
| `%APPDATA%\dpcc\usage.json` | Verlauf der lernenden Gewichtung |
| `%APPDATA%\dpcc\favorites.json` | angeheftete Favoriten |

Eine unbrauchbare `usage.json` oder `favorites.json` legt dpcc als `….defekt` daneben und beginnt leer. Eine
gesperrte Datei überschreibt es nicht.

Alles auf Vorgabe: die IDE schließen und den Schlüssel `HKCU\Software\dpcc\IdePlugin` sowie `settings.json`
löschen. Vorher den Hauptschalter aus- und mit OK bestätigen und Delphi einmal neu starten, damit dpcc den Anbieter
und die IDE-Schalter zurückgibt (siehe unten).

## Was dpcc an der IDE umstellt

dpcc läuft in einer von zwei Betriebsarten, die sich ausschließen. Welche gilt, entscheidet dpcc beim Start von
Delphi selbst nach dem Code-Insight-Anbieter, der in den Optionen der IDE für Delphi gewählt ist (Wert
`Insight Manager` unter `HKCU\<Basis>\Editor\Source Options\Borland.EditOptions.Pascal`). Das gilt für Delphi 12
(`<Basis>` = `Software\Embarcadero\BDS\23.0`) und Delphi 13 (`…\BDS\37.0`) gleich.

| Betriebsart | Gewählter Anbieter | dpcc | Was dpcc an der IDE ändert |
|---|---|---|---|
| IDE | DelphiLSP (Vorgabe) oder ein anderer Anbieter | aus: dpcc schaltet seinen Hauptschalter beim Start aus | Es dreht zurück, was es selbst geändert hatte. Die Werte, die DelphiLSP braucht, prüft es nur und schreibt das Ergebnis ins Protokoll. |
| dpcc | dpcc (`dpcc.CodeInsight`) | an: dpcc schaltet seinen Hauptschalter beim Start ein | Es setzt die Schalter aus der Tabelle [Schalter in der Betriebsart dpcc](#schalter-in-der-betriebsart-dpcc). |

Für diese Schalter gibt es keine Open Tools API: Sie stehen in der Registry der IDE und werden beim Start der IDE
gelesen. dpcc liest und schreibt sie dort, versionsneutral über den Basisschlüssel der laufenden IDE.

### Umschalten

- **Hauptschalter an** und OK: dpcc stellt den Anbieter der IDE auf dpcc (`Insight Manager` = `dpcc.CodeInsight`) und
  setzt die Schalter. Der vorige Anbieter bleibt gemerkt.
- **Hauptschalter aus** und OK: dpcc stellt den Anbieter zurück (auf den gemerkten, sonst auf DelphiLSP) und dreht
  seine übrigen Änderungen zurück.
- **In den Optionen der IDE** (Code Insight) DelphiLSP oder dpcc wählen: Meldet die IDE die Wahl an dpcc, folgt der
  Hauptschalter sofort; sonst gilt die Wahl beim nächsten Start.
- Die IDE liest Anbieter und Schalter nur beim Start. Nach einem Wechsel meldet dpcc einmal im Meldungsfenster
  „… wirkt nach dem Neustart von Delphi“. Bis dahin ruft die IDE den bisherigen Anbieter.
- Weil die IDE mit OK ihre Editoroptionen aus dem Speicher zurückschreibt, schreibt dpcc erst nach dem Dialog, prüft
  danach gegen und schreibt beim Beenden von Delphi den gewollten Stand noch einmal.
- Kommt der Wechsel auf dpcc trotzdem nicht an (die IDE hat ihre Wahl zurückgeschrieben), ist dpcc beim nächsten
  Start aus, und das Meldungsfenster sagt es. Dann den Hauptschalter erneut setzen oder dpcc in den Optionen der IDE
  wählen.
- Jede Entscheidung steht als eine Zeile im Protokoll, etwa „IDE-Kontext (Start): Borland.CodeInsight.LSP.Pascal →
  dpcc aus; zurückgedreht: Help Insight“ bzw. „IDE-Kontext (Hauptschalter an): … → dpcc an; Anbieter → dpcc.CodeInsight
  (wirkt nach dem Neustart); gesetzt: …“.

### Schalter in der Betriebsart dpcc

Gleich für Delphi 12 und 13. Ort, wenn nicht anders genannt: `HKCU\<Basis>\Code Insight\Borland.EditOptions.Pascal`
(das Option Set des dpcc-Managers).

| Option der IDE | Registry-Wert | Soll | Wann | Grund |
|---|---|---|---|---|
| Code-Insight-Anbieter für Delphi | `Insight Manager` (unter `Editor\Source Options\Borland.EditOptions.Pascal`) | `dpcc.CodeInsight` | immer | dpcc bedient Delphi-Dateien selbst. |
| Code-Vervollständigung: Automatisch aufrufen | `Auto Code Completions` | `True` | immer | Aus: Nach „.“ öffnet keine Liste. |
| Code-Vervollständigung: Verzögerung beim Tippen | `Auto Invoke Delay` | `-1` | immer | Ab 0 öffnet die IDE beim Tippen zusätzlich ihre eigene Liste. |
| Code-Parameter: Automatisch aufrufen | `Auto Code Parameters` | `True` | immer | Aus: Der Parameter-Hint öffnet bei „(“ und „,“ nicht von selbst. |
| Kurzhinweis Hilfe-Insight | `Help Insight` | `False` | „Eigener Tooltip …“ an | Sonst zeigt die IDE Help Insight neben dem dpcc-Tooltip. |
| Kurzhinweis Symbol-Insight | `Declaration Information` | `False` | „Eigener Tooltip …“ an | Sonst zeigt die IDE ihren Kurzhinweis neben dem dpcc-Tooltip. |
| Kurzhinweis Ausdrucksauswertung | `ToolTip Watches` | `False` | Tooltip und „Werte beim Debuggen zeigen“ an | Sonst zwei Wert-Tooltips beim Debuggen. |
| Code-Vervollständigung mit dem Parameter-Insight öffnen | `AutoInvokeCompletionOnParameterInsight` (unter `InsightGlobalOptions`) | `False` | immer | Sonst öffnet die IDE mit dem Parameter-Hint zusätzlich ihre Liste. |

Ein fehlender Wert gilt mit der Vorgabe der IDE (Schalter an, Verzögerung -1). Passt er schon, schreibt dpcc nichts.
Die Namen der Optionen sind die der deutschen IDE, gekürzt; maßgeblich ist der Registry-Wert.

### Prüfung in der Betriebsart IDE

Mit DelphiLSP prüft dpcc beim Start, ändert aber nichts. Das Ergebnis steht im Protokoll und im Abschnitt
[IDE](#ide) der Seite.

| Option der IDE | Registry-Wert | Soll | Grund |
|---|---|---|---|
| Code-Vervollständigung: Automatisch aufrufen | `Auto Code Completions` | `True` | Aus: Nach „.“ öffnet keine Liste (siehe [Fehlersuche](troubleshooting.md#nach-dem-punkt-öffnet-keine-liste)). |
| Code-Parameter: Automatisch aufrufen | `Auto Code Parameters` | `True` | Aus: kein Parameter-Hint von selbst. |
| Error Insight | `Error Insight` | `True` (fehlt = an) | Aus: Die Fehlermarkierungen von DelphiLSP fehlen im Editor. |

Orte der Schlüssel je Version:

| | Delphi 12 (BDS 23.0) | Delphi 13 (BDS 37.0) |
|---|---|---|
| DelphiLSP | `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` | `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` |
| dpcc | `Code Insight\Borland.EditOptions.Pascal` | `Code Insight\Borland.EditOptions.Pascal` |

Unter Delphi 12 gab es auf dem Prüfrechner nur den Ort von DelphiLSP (dazu HTML und StyleSheet), keinen
`Borland.EditOptions.Pascal`; dpcc legt ihn in der Betriebsart dpcc bei Bedarf an. Die Schalter von DelphiLSP liest
Delphi 12 wie Delphi 13 nur am Ort von DelphiLSP; `Borland.EditOptions.Pascal` ist das Option Set von dpcc und
zählt in der Betriebsart IDE nicht (früher prüfte dpcc es unter Delphi 12 ersatzweise). Fehlt der geprüfte
Schlüssel ganz,
steht im Ergebnis „Schlüssel fehlt (IDE-Vorgabe)“; das ist kein Fehler. Die Protokollzeile lautet etwa
„IDE-Einstellungen: 1 Abweichung: Auto Code Completions; Anbieter „Borland.CodeInsight.LSP.Pascal“, geprüft …“.

### Merker und Rückweg

- Jede Änderung hält dpcc unter `HKCU\Software\dpcc\IdePlugin` fest, je Version getrennt:
  `IdeSet <Version> <Schlüssel>\<Wert>` mit dem geschriebenen Wert und dem Wert davor (oder dass es keinen gab).
- Zurückgedreht wird nur, was noch so steht, wie dpcc es geschrieben hat. Hat der Nutzer oder die IDE den Wert
  seither geändert, bleibt er; nur der Merker entfällt. Gab es den Wert vorher nicht, löscht dpcc ihn wieder.
- Ältere Merker (`IdeHelpInsightDisabled …`, `IdeTooltipWatchesDisabled …`) gelten weiter: Beim nächsten Abgleich
  dreht dpcc sie zurück bzw. ersetzt sie durch die neuen.
- Error Insight und die Strukturhervorhebung schaltet dpcc nie.
- Vor dem Deinstallieren: Hauptschalter aus, OK, Delphi neu starten. Sonst bleibt `dpcc.CodeInsight` als Anbieter und
  bleiben die Schalter von dpcc stehen.
- Zusätzlich meldet dpcc einen eigenen Code-Insight-Manager und die Tastenbindung „dpcc Code Completion“ für
  Strg+Leertaste und Strg+Umschalt+Leertaste an. Beides baut es beim Entladen wieder ab.
