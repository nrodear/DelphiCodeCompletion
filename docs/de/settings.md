Deutsch | [English](../en/settings.md) | [Français](../fr/settings.md)

# Einstellungen

[Übersicht](index.md) › Einstellungen

Die Optionen stehen unter **Tools › Optionen › Drittanbieter › dpcc**. Das ist eine einzige Seite ohne Unterseiten.

## Die Seite

- Oben steht die Betriebsart mit drei Optionsfeldern, darunter folgen die Abschnitte **Vervollständigung**, **Beim
  Übernehmen**, **Parameter-Hint und Tooltip**, **Index** und **IDE**.
- Die Optionen darunter gelten nur für die Betriebsart Plugin. In den Betriebsarten Aus und Server sind sie und der
  Knopf „Verlauf zurücksetzen“ grau. „Zusätzliche Quellordner“, „Index neu aufbauen“, „Jetzt prüfen“ und „Ablauf
  protokollieren (Log)“ bleiben bedienbar.
- „Werte beim Debuggen zeigen“ ist grau, solange „Eigener Tooltip beim Verweilen über Bezeichnern“ aus ist.

Gespeichert wird mit **OK**. Ausnahmen: „Verlauf zurücksetzen“ und „Index neu aufbauen“ wirken sofort, „Jetzt
prüfen“ liest nur. „Ablauf protokollieren (Log)“ wirkt nach OK ohne Neustart.

Einige frühere Optionen stehen nicht mehr auf der Seite und gelten fest (siehe
[Fest eingestellte Werte](#fest-eingestellte-werte)).

Die Spalte „Registry-Wert“ nennt den Namen unter `HKCU\Software\dpcc\IdePlugin`, die Spalte „Schlüssel“ den Namen,
den dpcc in Hinweisen und in `settings.json` verwendet. „–“ bei „Registry-Wert“: Die Option liegt nicht in der
Registry, sondern in `settings.json` (siehe [Ablage](#ablage)).

## Betriebsart

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Betriebsart (drei Optionsfelder) | `OperatingMode 23.0` (Delphi 12) bzw. `OperatingMode 37.0` (Delphi 13); mit eigenem Registry-Profil (`bds -r <Profil>`) `OperatingMode <Profil> 23.0` bzw. `… 37.0` | `operatingMode` | Plugin | Je Delphi-Version (und je Registry-Profil) getrennt: `off`, `plugin` oder `server`. Ersetzt den früheren Hauptschalter „Code Insight von dpcc“ (`Enabled`, für alle Versionen gemeinsam). Zur Laufzeit gilt genau eine Betriebsart; der eingebaute Server des Plugins und `dpcc.LspServer.exe` arbeiten nie gleichzeitig. Ein Wechsel von oder zu Plugin stellt den Code-Insight-Anbieter der IDE um und wirkt nach dem Neustart von Delphi; zwischen Aus und Server wirkt er beim nächsten Öffnen einer Projektgruppe. Siehe [Umschalten](#umschalten). Liste, Parameterhilfe und Tooltip von dpcc folgen der Wahl nach OK sofort (außer in Plugin gehen Strg+Leertaste und Strg+Umschalt+Leertaste an die IDE); ein schon laufender eingebauter Server läuft weiter. |

Die drei Optionsfelder und ihr Text auf der Seite:

| Optionsfeld | Text darunter |
|---|---|
| „Aus – Delphi arbeitet ohne dpcc“ | „Delphi nutzt seinen eigenen Code-Insight-Anbieter (DelphiLSP); dpcc zeigt keine Fenster und leitet nichts um.“ |
| „Plugin – Code Insight von dpcc im Editor (Vorgabe)“ | „dpcc wird der Code-Insight-Anbieter der IDE, mit eigener Liste, Tooltip und Parameter-Hint. Der Wechsel von oder zu Plugin wirkt nach dem Neustart von Delphi.“ |
| „Server – dpcc.LspServer.exe an Stelle von DelphiLSP“ | „Delphi bleibt im LSP-Betrieb und zeigt seine eigenen Fenster; die Antworten liefert dpcc.LspServer.exe statt DelphiLSP.exe. Die Fehlermarkierung der IDE (Error Insight) bleibt leer. dpcc schaltet in den Code-Insight-Optionen der IDE Programmierhilfe, Automatisch aufrufen, Code-Parameter und Symbol-Insight ein und stellt sie beim Verlassen von Server zurück; dort muss man für den Server nichts abschalten. Der Wechsel von oder zu Plugin wirkt nach dem Neustart von Delphi, zwischen Aus und Server beim nächsten Öffnen einer Projektgruppe; die vier Optionen liest die IDE aber erst beim nächsten Start von Delphi.“ |

- **Aus** (früher „Hauptschalter aus“): Delphi arbeitet mit seinem eigenen Code-Insight-Anbieter (DelphiLSP,
  `Insight Manager` = `Borland.CodeInsight.LSP.Pascal`). dpcc zeigt keine Fenster und leitet nichts um.
- **Plugin** (Vorgabe nach der Installation, früher „Hauptschalter an“): dpcc ist der Code-Insight-Anbieter
  (`dpcc.CodeInsight`) mit eingebautem Server und eigener Liste, eigenem Tooltip und Parameter-Hint.
- **Server**: Die IDE bleibt im LSP-Betrieb (Anbieter DelphiLSP). Startet sie `DelphiLSP.exe`, startet das Plugin an
  dessen Stelle `dpcc.LspServer.exe`. Eingebauter Server und Fenster von dpcc sind aus. Siehe
  [Betriebsart Server](#betriebsart-server).

### Betriebsart Server

- Liste, Hint, Tooltip beim Verweilen, Strukturansicht und Strg+Klick sind die der IDE; die Antworten kommen von
  `dpcc.LspServer.exe`. Liste, Tooltip und Parameter-Hint von dpcc erscheinen nicht, Strg+Leertaste und
  Strg+Umschalt+Leertaste gehen an die IDE.
- Die Fehlermarkierung der IDE (Error Insight) bleibt leer: `dpcc.LspServer.exe` liefert keine Code-Diagnosen. dpcc
  setzt `ErrorInsightLevel` nicht.
- Ohne vier Code-Insight-Optionen der IDE fragt die IDE den Server nicht: Programmierhilfe, Automatisch aufrufen,
  Code-Parameter und Kurzhinweis Symbol-Insight. dpcc schaltet sie in der Betriebsart Server selbst ein und stellt sie
  beim Wechsel nach Aus wieder auf die Werte davor (siehe
  [Optionen in der Betriebsart Server](#optionen-in-der-betriebsart-server)). Im Code-Insight-Dialog der IDE muss
  für den Server nichts abgeschaltet werden. Die IDE liest die Optionen erst beim nächsten Start von Delphi.
- Umgeleitet wird aus dem Plugin heraus (Hook auf `CreateProcessW` im Modul `IDELSP290.bpl` bzw. `IDELSP370.bpl`).
  Im Delphi-Programmordner ändert dpcc nichts, Administratorrechte braucht es nicht. Einzelheiten, Orte der EXE und
  Protokollzeilen: [LSP-Server](lsp-server.md#betriebsart-server).
- „Server“ ist nur wählbar, wenn dpcc die EXE findet. Sonst ist das Feld grau, darunter steht „Nicht wählbar:
  dpcc.LspServer.exe ist nicht installiert (im Setup die Komponente „LSP-Server“ wählen).“ Ist Server schon gewählt,
  bleibt es gewählt; der Start fällt dann auf das originale DelphiLSP zurück. Der Hint am Feld nennt den gefundenen
  Ort der EXE („Programm: …“).
- Nicht unterstützt: die 64-Bit-IDE von Delphi 13 (`bin64\bds.exe`). Das Plugin ist 32 Bit.

## Vervollständigung

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Nach dem Punkt automatisch öffnen | `OpenAfterDot` | – | an; Startwert einmal aus der IDE (siehe [Nach dem Update](#nach-dem-update)) | Nach „.“ öffnet die Liste von selbst. Aus: dpcc meldet der IDE nach „.“ keine Code Insight (`GetCodeInsightType('.')` liefert „keine“), es öffnet sich keine Liste; Strg+Leertaste öffnet sie weiter, die übrigen Auslöser („(“, „[“, „<“ in XMLDoc, „;“ hinter einem Konstruktor) bleiben. Wirkt nach OK sofort, ohne Neustart. Unter Delphi 13 öffnet die IDE nach „.“ zudem nur, wenn im Satz von dpcc Programmierhilfe und Automatisch aufrufen an sind; beide stellt dpcc in der Betriebsart Plugin selbst ein (siehe [Schalter in der Betriebsart Plugin](#schalter-in-der-betriebsart-plugin)). Tritt an die Stelle von „Automatisch aufrufen“ im Dialog der IDE (siehe [Code Insight der IDE](#code-insight-der-ide)). Gesperrt außerhalb der Betriebsart Plugin. |
| Beim Tippen öffnen ab Zeichen (0 = nie): | `AutoMinChars` | `completion.autoMinChars` | 0 | 0 bis 10; Vorgabe 0 = aus (wie vor dem Öffnen beim Tippen), zum Einschalten z. B. 5 einstellen. Tippt man einen Namen ohne Punkt davor, öffnet die Liste erst, wenn das Wort vor dem Cursor so viele Zeichen hat; darunter fragt dpcc den Server nicht. 0 = Tippen öffnet nie. Strg+Leertaste öffnet bei jeder Länge; nach „.“ und bei den übrigen Auslösern ändert sich nichts. Damit die IDE beim Tippen nicht zusätzlich ihre eigene Liste öffnet, stellt dpcc in der Betriebsart Plugin `Auto Invoke Delay` = -1 (siehe [unten](#was-dpcc-an-der-ide-umstellt)). Siehe [Bedienung](usage.md#öffnen-beim-tippen). |
| Beim Tippen zeigen: | `CompletionListMode` | `completion.listMode` | Nur Treffer | „Nur Treffer“ (`filter`), „Alle Einträge, Treffer oben“ (`all`), „Treffer, darunter gedämpft der Rest“ (`rest`, unter der Überschrift „Weitere Einträge“). Gilt für Mitgliederlisten nach „.“ (fest eingestellt). |
| Sichtbare Zeilen der Liste: | `VisibleRows` | `completion.visibleRows` | 9 | 5 bis 20 Zeilen. |
| Breite automatisch | `ListWidth` | `completion.listWidth` | an (`ListWidth` = 0) | Steht in derselben Zeile wie „Sichtbare Zeilen der Liste“. An: Die Liste wächst mit dem breitesten Eintrag. Aus: die zuletzt gezogene Breite (240 bis 720). Ziehen am rechten Rand der Liste setzt die Breite ebenfalls. |
| Reservierte Wörter in der Liste zeigen | – | `completion.keywords` | an; Startwert einmal aus der IDE (siehe [Nach dem Update](#nach-dem-update)) | Schlüsselwörter wie `begin`, `if` oder `procedure` in der Liste, passend zur Stelle und erst ab einem getippten Zeichen, nie nach „.“. Aus: Der Server lässt sie weg. Liegt in `%APPDATA%\dpcc\settings.json` unter dem Schlüssel, den der Server liest; ein dort schon gesetzter Wert gilt und erscheint auf der Seite. Wirkt nach OK ohne Neustart ab der nächsten Liste: Der Server liest die Datei neu, sobald sie sich ändert. Weil `dpcc.LspServer.exe` dieselbe Datei liest, gilt der Wert auch in der Betriebsart Server. Tritt an die Stelle von „Reservierte Wörter anzeigen“ im Dialog der IDE. Gesperrt außerhalb der Betriebsart Plugin. |
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
| Eigener Tooltip beim Verweilen über Bezeichnern | `HoverTooltip` | `editor.hoverTooltip` | an | Tooltip von dpcc. Solange er an ist, schaltet dpcc in der Betriebsart Plugin Help Insight und den Kurzhinweis Symbol-Insight der IDE ab (`Help Insight`, `Declaration Information`) und verbirgt ein trotzdem erscheinendes Fenster von Help Insight sofort, ohne Neustart. Gesperrt außerhalb der Betriebsart Plugin. |
| Werte beim Debuggen zeigen (schaltet den Wert-Tooltip der IDE ab) | `DebugHoverValues` | `debug.hoverValues` | an | Steht eingerückt unter dem Tooltip. Bei angehaltenem Programm steht der Wert des Ausdrucks oben im Tooltip; dpcc schaltet dann die Ausdrucksauswertung im Kurzhinweis der IDE ab (`ToolTip Watches`). Wer den Wert-Tooltip der IDE will, schaltet diese Option aus. Gesperrt, solange „Eigener Tooltip …“ aus ist. |
| Darstellung der Popups: | `PopupLook` | `editor.popupLook` | Dezent | „Intensiv“ (`intense`), „Dezent“ (`subtle`), „Unscheinbar“ (`plain`). Bestimmt, wie stark die Fenster von dpcc färben: Vervollständigungsliste, Tooltip und Parameter-Hint, dazu die Platzhalter-Markierungen im Editor. Was jede Stufe ändert, steht unter [Darstellung der Popups](#darstellung-der-popups). Gilt nach OK ab dem nächsten Öffnen eines Fensters. Ein unbekannter Wert in der Registry gilt als Dezent. Gesperrt außerhalb der Betriebsart Plugin. |

### Darstellung der Popups

| Stufe | Wirkung |
|---|---|
| Intensiv | Markierte Flächen – die gewählte Zeile der Liste, die Kopfzeile des Tooltips und die gewählte Überladung im Parameter-Hint – sehen aus wie in Dezent und bekommen zusätzlich einen dicken Balken in der Akzentfarbe: im Tooltip ganz oben am Fenster, in der Liste links vor der Zeile, im Parameter-Hint am linken Rand. Außerhalb der markierten Flächen zeigt die Art-Spalte eine Farbe je Art-Gruppe, die Marken rechts sind farbig (auch „+ Unit“ für eine fehlende Unit), Typ- und Parameternamen stehen in eigener Farbe, der aktive Parameter liegt auf einer Akzentfläche. |
| Dezent (Vorgabe) | Dieselben Elemente abgeschwächt: schwache Akzentfläche für gewählte Zeile und Kopfzeile, Typ- und Parameternamen in abgeschwächter Farbe. Die Art-Spalte ist gedämpft, farbig sind nur Warnungen und Fehler. |
| Unscheinbar | Fast ohne Farbe: gewählte Zeile und Kopfzeile auf hellgrauer Fläche, Typ- und Parameternamen in Textfarbe, Schlüsselwörter in Signaturen nur fett. Fehler bleiben rot. |

Fehlerzeilen stehen in allen drei Stufen in der Fehlerfarbe. Nicht betroffen sind die Fenster der IDE selbst: der
Symbolhinweis der IDE (wenn der eigene Tooltip aus ist), die Code-Insight-Liste der IDE und das Meldungsfenster. Dort
bestimmt die IDE die Farben.

## Index

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Zusätzliche Quellordner (mit „;“ getrennt, samt Unterordnern): | – | `index.extraSourceFolders` | leer | Ordner mit dem Quelltext von Bibliotheken, die sonst nur als `.dcu` vorliegen (DUnitX, DUnit, FireDAC, Komponenten). Unterordner zählen mit (ohne `.git`, `__history`, `__recovery`); `$(Name)` und `%Name%` werden aufgelöst. Ihre Units schlägt „+ Unit“ vor, geladen werden sie bei Bedarf; sie haben einen eigenen Cache. Liegt in `%APPDATA%\dpcc\settings.json` (in der Datei auch als Liste), nicht in der Registry; der Server baut den Index ohne Neustart um. Ersetzt den früheren Schalter `index.officeAndWinRt`: Office-Typbibliotheken und WinRT stehen immer im Katalog. Siehe [Index und Cache](index-cache.md#zusätzliche-quellordner). |
| Knopf „Index neu aufbauen“ | – | – | – | Fragt nach, löscht alle Index-Caches und baut den Index neu auf. Hängt nicht an der Betriebsart. Siehe [Index und Cache](index-cache.md#index-neu-aufbauen). |

## IDE

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Knopf „Jetzt prüfen“ | – | – | – | Rechts daneben stehen die Statuszeilen: Betriebsart und Anbieter, ob ein Wechsel noch auf den Neustart von Delphi wartet (verglichen mit dem Anbieter, mit dem die laufende IDE arbeitet), was dpcc an der IDE gesetzt hat und das Ergebnis der Prüfung (etwa „1 Abweichung: Auto Code Completions“). Die Zeile wächst mit dem Text; in der Schrift des Dialogs, grau. Beim Öffnen der Seite gelesen, der Knopf liest neu. Liest nur, ändert nichts; hängt nicht an der Betriebsart. Siehe [Was dpcc an der IDE umstellt](#was-dpcc-an-der-ide-umstellt). |
| Ablauf protokollieren (Log) | `Diagnose` | – | aus | Schreibt für jede Aktion (Strg+Klick bzw. „Deklaration suchen“, Vervollständigung, Hover, Parameterhilfe) jeden Schritt vom Aufruf der IDE bis zum Ergebnis ins Diagnoseprotokoll neben der Plugin-BPL. Ohne Quelltext außer dem Wort an der Stelle. Derselbe DWORD wie das frühere `Diagnose` = 1 von Hand: Ein so gesetzter Wert erscheint angehakt. Wirkt nach OK sofort, ohne Neustart; das Meldungsfenster nennt dann die Datei, der Hint am Schalter ebenso. Hängt nicht an der Betriebsart. Siehe [Fehlersuche](troubleshooting.md#ablaufprotokoll). |

## Fest eingestellte Werte

Diese Optionen stehen nicht mehr auf der Seite. Sie gelten fest mit ihrer bisherigen Vorgabe:

- **Verzögerung bis zum automatischen Öffnen (etwa nach „.“): 150 ms** (`OpenDelayMs`, `completion.openDelayMs`).
  Gilt nur für das automatische Öffnen (nach „.“ und beim Tippen), nicht für Strg+Leertaste. Automatisch öffnet
  dpcc nur in der Betriebsart Plugin; in den Betriebsarten Aus und Server öffnet dpcc keine Liste (siehe
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
- Der Hauptschalter „Code Insight von dpcc“ ist der [Betriebsart](#betriebsart) gewichen: an entspricht Plugin, aus
  entspricht Aus; neu ist Server. Die Betriebsart gilt je Delphi-Version; den früheren Wert `Enabled` überführt dpcc
  beim ersten Start (siehe [Ablage](#ablage)).
- OK speichert nur noch die Werte der Seite: die Betriebsart der laufenden Delphi-Version und zwölf Optionen in der
  Registry,
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
- Neu im Abschnitt **IDE**: „Ablauf protokollieren (Log)“. Er schaltet dasselbe Diagnoseprotokoll wie der bisher nur
  von Hand gesetzte Registry-Wert `Diagnose` = 1, jetzt ohne Neustart. OK schreibt `Diagnose` seitdem mit; wer den
  Wert von Hand gesetzt hat, sieht das Häkchen gesetzt.
- Neu im Abschnitt **Vervollständigung**: „Nach dem Punkt automatisch öffnen“ und „Reservierte Wörter in der Liste
  zeigen“. Die Felder dazu blendet dpcc im Code-Insight-Dialog der IDE aus (siehe
  [Code Insight der IDE](#code-insight-der-ide)).
- Startwerte der beiden Schalter: einmal beim ersten Start nach dem Update, an dem die Betriebsart Plugin gilt (in
  den Betriebsarten Aus und Server liest und schreibt dpcc dafür nichts), aus dem Satz von DelphiLSP der
  laufenden Version (`HKCU\<Basis>\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal`; mit eigenem
  Profil, `bds -r`, dessen Basisschlüssel).
  - „Nach dem Punkt automatisch öffnen“ = `Auto Code Completions` und `Auto Invoke` (beide an).
  - „Reservierte Wörter in der Liste zeigen“ = `Show Reserved Words`.
  - Ein fehlender Wert gilt als an.
  - Steht für einen der Werte ein Merker `IdeSet <Version> <Schlüssel>\<Wert>`, gilt der gemerkte Wert davor (der des
    Nutzers), nicht der von dpcc geschriebene; ohne Wert davor gilt an.
  - Stand `completion.keywords` schon in `settings.json`, gilt dieser Wert; dpcc liest dafür nichts aus der IDE.
  - Danach liest dpcc die Werte nie wieder aus der IDE. Das halten die Merker `IdeAdopted OpenAfterDot` und
    `IdeAdopted CompletionKeywords` (DWORD 1, je Schalter, für alle Delphi-Versionen) fest. Die Delphi-Version, die
    zuerst in der Betriebsart Plugin startet, liefert also die Startwerte. Die Zeile im Protokoll lautet „Startwerte aus den
    Code-Insight-Optionen der IDE übernommen (einmalig, …): OpenAfterDot = …; CompletionKeywords = …“.
- Funktionen der IDE im Satz von dpcc, nur unter **Delphi 13** und nur in der Betriebsart Plugin: Fehlen in
  `Code Insight\Borland.EditOptions.Pascal` die Werte `Auto-block Completion`, `Block Wrap Style`, `Code Templates`,
  `Auto Complete Templates` oder `Sync Edit Hints`, übernimmt dpcc beim ersten Start einmal den Wert aus dem Satz von
  DelphiLSP.
  - Nur in Lücken: Vorhandene Werte bleiben, ein fehlender Schlüssel wird nicht angelegt.
  - Ohne Merker `IdeSet`: Der Wert gehört danach dem Nutzer, Aus dreht ihn nicht zurück.
  - Erledigt hält der Merker `IdeAdopted 37.0 IdeFeatures` fest, auch wenn nichts fehlte. In der Regel ist der Satz
    voll belegt; dann steht im Protokoll „IDE-Funktionen: im Satz von dpcc nichts zu übernehmen“.
- **Delphi 12**: Dafür schreibt dpcc nichts. Seit dieser Fassung nennt dpcc in Delphi 12 als Optionssatz den von
  DelphiLSP; Blockvervollständigung und Vorlagen folgen dort also ohne Übernahme den Werten, die man für DelphiLSP
  eingestellt hat (siehe [Code Insight der IDE](#code-insight-der-ide)). Merker, die frühere Fassungen unter Delphi 12
  für `Code Insight\Borland.EditOptions.Pascal` angelegt haben, räumt dpcc beim nächsten Start auf (Wert zurück bzw.
  gelöscht, wenn es ihn vorher nicht gab; im Protokoll „aufgeräumt (alter Ort)“).
- „Unvollständige Eigenschaften abschließen“ (`Finish properties`) liegt für alle Anbieter gemeinsam unter
  `<Basis>\Class Completion`; dpcc fasst es nicht an.

## Ablage

| Ort | Inhalt |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | alle Optionen der Seite außer `index.extraSourceFolders` und `completion.keywords`, darunter `OpenAfterDot` („Nach dem Punkt automatisch öffnen“). Dazu die Merker der einmaligen Übernahme aus der IDE (`IdeAdopted OpenAfterDot`, `IdeAdopted CompletionKeywords`, `IdeAdopted 37.0 IdeFeatures`, DWORD 1; siehe [Nach dem Update](#nach-dem-update)); OK schreibt sie nicht. Schalter und Zahlen als DWORD (Schalter 0/1), Auswahlen als Text (`CompletionListMode`: `filter`, `all`, `rest`; `PopupLook`: `intense`, `subtle`, `plain`; die Betriebsart je Version als `OperatingMode 23.0` bzw. `OperatingMode 37.0`: `off`, `plugin`, `server`). Der frühere Hauptschalter `Enabled` (DWORD, für alle Versionen gemeinsam) wird nur noch gelesen, siehe unten. Dazu die Merker für die IDE-Schalter (unten) und `PathOverrideBackup` von `Tools\IdePath.ps1`. Nur gelesen, nie geschrieben: der Support-Schalter `LogNames` (siehe [Fehlersuche](troubleshooting.md)). `Diagnose` („Ablauf protokollieren (Log)“) gehört seit dieser Fassung zu den Werten der Seite; OK schreibt ihn als 0 oder 1, ein von Hand gesetzter Wert gilt weiter. Alte Werte der fest eingestellten und der entfernten Optionen bleiben liegen, wirken aber nicht; dpcc schreibt sie nicht mehr. |
| `%APPDATA%\dpcc\settings.json` | `index.extraSourceFolders` und `completion.keywords` (beide von der Seite) und `hints.xmlDocMaxLines` (nur in der Datei einstellbar). Fehlt `completion.keywords` in der Datei, gilt ein Registry-Wert `CompletionKeywords`, sonst an. Der Server im IDE-Prozess liest die Datei selbst und beobachtet sie. dpcc liest `hints.xmlDocMaxLines` nur und schreibt den Schlüssel nie; fehlt er in der Datei, gilt ein Registry-Wert `XmlDocMaxLines` einer älteren Version, sonst 0. Andere Schlüssel der Datei fasst dpcc nicht an. Ein alter Wert `hints.xmlDocExpand` bzw. `hints.xmlDocFull` bleibt ohne Wirkung. |
| `%APPDATA%\dpcc\settings-history.json` | nur aus älteren Versionen: frühere Stände der Einstellungen. dpcc schreibt und liest die Datei nicht mehr; sie kann gelöscht werden. |
| `%APPDATA%\dpcc\usage.json` | Verlauf der lernenden Gewichtung |
| `%APPDATA%\dpcc\favorites.json` | angeheftete Favoriten |

Eine unbrauchbare `usage.json` oder `favorites.json` legt dpcc als `….defekt` daneben und beginnt leer. Eine
gesperrte Datei überschreibt es nicht.

Betriebsart beim ersten Start einer Version:

- Hat die Delphi-Version noch keinen eigenen Wert `OperatingMode <Version>`, gilt das frühere `Enabled`: 0 → Aus,
  jeder andere Wert → Plugin. Fehlt auch `Enabled`, gilt Plugin. Ein unlesbarer Wert zählt wie ein fehlender.
- Das Ergebnis schreibt dpcc beim ersten Start sofort unter dem Namen der Version. `Enabled` bleibt danach
  unverändert liegen und wird nicht mehr geschrieben.
- Gibt es weder einen eigenen Wert noch `Enabled` (erster Start nach der Installation), gilt Plugin, und dpcc stellt
  den Code-Insight-Anbieter der IDE auf dpcc, auch wenn DelphiLSP gewählt war. Das wirkt nach dem Neustart von
  Delphi.

Alles auf Vorgabe: die IDE schließen und den Schlüssel `HKCU\Software\dpcc\IdePlugin` sowie `settings.json`
löschen. Vorher die Betriebsart Aus wählen, mit OK bestätigen und Delphi einmal neu starten, damit dpcc den Anbieter
und die IDE-Schalter zurückgibt (siehe unten). Beim nächsten Start gilt dann wieder die Vorgabe Plugin, und dpcc
stellt den Anbieter erneut auf dpcc.

## Was dpcc an der IDE umstellt

dpcc läuft je Delphi-Version in einer von drei [Betriebsarten](#betriebsart), die sich ausschließen. Gewählt wird
sie auf der Seite; beim Start von Delphi gleicht dpcc sie mit dem Code-Insight-Anbieter ab, der in den Optionen der
IDE für Delphi gewählt ist (Wert `Insight Manager` unter
`HKCU\<Basis>\Editor\Source Options\Borland.EditOptions.Pascal`). Das gilt für Delphi 12
(`<Basis>` = `Software\Embarcadero\BDS\23.0`) und Delphi 13 (`…\BDS\37.0`) gleich.

| Betriebsart | Anbieter der IDE | dpcc | Was dpcc an der IDE ändert |
|---|---|---|---|
| Aus | DelphiLSP (Vorgabe der IDE) oder ein anderer Anbieter | keine Fenster, keine Umleitung | Es dreht zurück, was es selbst geändert hatte. Die Werte, die DelphiLSP braucht, prüft es nur und schreibt das Ergebnis ins Protokoll. |
| Plugin | dpcc (`dpcc.CodeInsight`) | eingebauter Server, eigene Liste, Tooltip und Parameter-Hint | Es setzt die Schalter aus der Tabelle [Schalter in der Betriebsart Plugin](#schalter-in-der-betriebsart-plugin). |
| Server | DelphiLSP (`Borland.CodeInsight.LSP.Pascal`) | kein eingebauter Server, keine Fenster; der Start von `DelphiLSP.exe` wird auf `dpcc.LspServer.exe` umgeleitet | Es setzt die vier Optionen aus [Optionen in der Betriebsart Server](#optionen-in-der-betriebsart-server) und dreht alles andere zurück wie bei Aus. Den Anbieter stellt es mit OK auf DelphiLSP. Die Umleitung sitzt im Prozess der IDE, nicht in der Registry. |

Für diese Schalter gibt es keine Open Tools API: Sie stehen in der Registry der IDE und werden beim Start der IDE
gelesen. dpcc liest und schreibt sie dort, versionsneutral über den Basisschlüssel der laufenden IDE.

### Umschalten

- **Plugin** mit OK: dpcc stellt den Anbieter der IDE auf dpcc (`Insight Manager` = `dpcc.CodeInsight`) und setzt
  die Schalter. Der vorige Anbieter bleibt gemerkt.
- **Aus** mit OK, während Plugin galt: dpcc stellt den Anbieter zurück (auf den gemerkten, sonst auf DelphiLSP) und
  dreht seine übrigen Änderungen zurück.
- **Server** mit OK: dpcc stellt den Anbieter in jedem Fall auf DelphiLSP (auch aus einem anderen Anbieter, nicht auf
  den gemerkten Wert), schaltet die vier [Optionen für den Server](#optionen-in-der-betriebsart-server) ein und dreht
  seine übrigen Code-Insight-Schalter zurück wie bei Aus.
- **Zwischen Plugin und Server**: Eine Option, die beide Betriebsarten gleich wollen (Programmierhilfe, Automatisch
  aufrufen, Code-Parameter), bleibt stehen; dpcc stellt sie nicht kurz zurück und wieder vor, und ihr Merker behält
  den Wert von vor dem ersten Eingriff. Symbol-Insight schaltet Plugin aus und Server ein. Was nur Plugin stellt
  (Help Insight, Ausdrucksauswertung, Verzögerung beim Tippen, `AutoInvokeCompletionOnParameterInsight`, Anbieter),
  geht beim Wechsel auf Server zurück auf den Wert davor.
- Von oder zu **Plugin** wechselt der Anbieter; das wirkt erst nach dem Neustart von Delphi (siehe unten).
- **Zwischen Aus und Server** (die IDE ist schon im LSP-Betrieb) braucht es keinen Neustart. Die IDE startet ihren
  Server, wenn die erste Unit einer Projektgruppe angezeigt wird, einen je Projektgruppe; ein laufender Server bleibt,
  bis die Gruppe geschlossen wird. Die Umleitung liest die Betriebsart bei jedem Start von DelphiLSP neu. Also: die
  Projektgruppe schließen und wieder öffnen. Muss dpcc dabei die vier Code-Insight-Optionen des Servers erst
  einschalten (siehe [Optionen in der Betriebsart Server](#optionen-in-der-betriebsart-server)), gilt das erst
  nach dem Neustart von Delphi (gemessen am 28.11.2026 in Delphi 12 und 13). Das Meldungsfenster sagt es einmal
  („Betriebsart Server: Beim nächsten Start des Code-Insight-Servers …“ bzw. „Betriebsart Aus: Beim nächsten Öffnen
  einer Projektgruppe …“).
- **Beim Start von Delphi** richtet sich die Betriebsart nach dem gewählten Anbieter: Ist dpcc gewählt, gilt Plugin.
  Ist DelphiLSP gewählt (oder kein Anbieter eingetragen), bleibt eine gespeicherte Betriebsart Server stehen, sonst
  gilt Aus. Ist ein anderer Anbieter gewählt, gilt Aus; war Server gewählt, sagt das Meldungsfenster es. Ausnahme ist
  der erste Start ohne gespeicherten Wert (siehe [Ablage](#ablage)).
- **In den Optionen der IDE** (Code Insight) einen Anbieter wählen: dpcc → Plugin; ein anderer Anbieter, während
  Plugin gilt → Aus (wie bisher); DelphiLSP, während Server gilt → Server bleibt. Meldet die IDE die Wahl an dpcc,
  folgt die Betriebsart sofort; sonst gilt die Wahl beim nächsten Start. Die Wahl übersteht das Beenden: Nach OK
  gleicht dpcc mit der Betriebsart ab, die dann gespeichert ist (also schon der gewählten), und beim Beenden schreibt
  es diesen Stand, nicht den von vor der Wahl. Wählt man im selben OK auf der Seite dpcc eine andere Betriebsart, gilt
  die Wahl im Code-Insight-Dialog.
- Die IDE liest Anbieter und Schalter nur beim Start. Nach einem Wechsel meldet dpcc einmal im Meldungsfenster
  „… wirkt nach dem Neustart von Delphi“. Bis dahin ruft die IDE den bisherigen Anbieter, und der Abschnitt
  [IDE](#ide) der Seite zeigt „Der Anbieter wird beim nächsten Start von Delphi …“.
- Die Hinweise stehen im eigenen Reiter **dpcc** des Meldungsfensters (Ansicht › Tool-Fenster › Meldungen), nicht im
  Reiter „Erzeugen“, den der nächste Build leert.
- Weil die IDE mit OK ihre Editoroptionen aus dem Speicher zurückschreibt, schreibt dpcc erst nach dem Dialog, prüft
  danach gegen und schreibt beim Beenden von Delphi den gewollten Stand noch einmal. Das gilt auch für Rückwege ohne
  Merker (Aus, Server → Aus, Tooltip aus): Steht beim Beenden wieder genau der Wert von vor dem Rückweg (die IDE hat
  ihren Speicher zurückgeschrieben; gesehen in Delphi 12 nach einem OK im Optionsdialog), schreibt dpcc den Rückweg
  erneut; im Protokoll „IDE-Kontext beim Beenden: Rückweg erneut geschrieben …“. Steht dort ein anderer Wert, bleibt
  er.
- Dasselbe gilt, wenn man im Code-Insight-Dialog der IDE dpcc oder einen anderen Anbieter wählt und mit OK bestätigt:
  Die IDE schreibt danach ihre Editoroptionen aus dem Speicher zurück und kann Werte von dpcc überschreiben. dpcc prüft
  deshalb nach dem Schließen des Optionsdialogs noch einmal nach (sobald kein modales Fenster mehr offen ist,
  höchstens 10 Minuten lang) und schreibt überschriebene Werte erneut, wie nach OK auf der Seite dpcc. Die Reparatur
  beim Beenden von Delphi bleibt.
- Kommt der Wechsel auf dpcc trotzdem nicht an (die IDE hat ihre Wahl zurückgeschrieben), ist dpcc beim nächsten
  Start aus, und das Meldungsfenster sagt es. Dann die Betriebsart Plugin erneut wählen oder dpcc in den Optionen der
  IDE wählen.
- Jede Entscheidung steht als eine Zeile im Protokoll, etwa „IDE-Kontext (Start): Borland.CodeInsight.LSP.Pascal →
  dpcc aus; Betriebsart Server; …“ bzw. „IDE-Kontext (Hauptschalter an): … → dpcc an; Betriebsart Plugin (geändert);
  Anbieter → dpcc.CodeInsight (wirkt nach dem Neustart); gesetzt: …“. Der Anlass in Klammern heißt im Protokoll
  weiter „Hauptschalter an“ (Plugin), „Hauptschalter aus“ (Aus) bzw. „Betriebsart Server“. Ein Wechsel auf der Seite
  steht zusätzlich als „IDE-Kontext: Betriebsart mit OK umgestellt: Aus → Server“, eine Wahl im Code-Insight-Dialog
  als „IDE-Kontext: dpcc im Code-Insight-Dialog der IDE gewählt“ bzw. „… anderer Anbieter …“.

### Schalter in der Betriebsart Plugin

Ort, wenn nicht anders genannt: die Orte der Betriebsart Plugin unter `HKCU\<Basis>\Code Insight` (siehe
[Orte der Schlüssel je Version](#orte-der-schlüssel-je-version)). Unter Delphi 12 ist das der Satz von DelphiLSP
(`Borland.EditOptions.Borland.CodeInsight.LSP.Pascal`), den die IDE dort auch für dpcc liest; unter Delphi 13 jeder
vorhandene aus `Borland.EditOptions.Pascal` und `Borland.EditOptions.Borland.CodeInsight.LSP.Pascal`.

| Option der IDE | Registry-Wert | Soll | Wann | Grund |
|---|---|---|---|---|
| Code-Insight-Anbieter für Delphi | `Insight Manager` (unter `Editor\Source Options\Borland.EditOptions.Pascal`) | `dpcc.CodeInsight` | immer | dpcc bedient Delphi-Dateien selbst. |
| Programmierhilfe | `Auto Code Completions` | `True` | immer | Aus: Nach „.“ öffnet keine Liste. |
| Automatisch aufrufen | `Auto Invoke` | `True` | immer | Aus: Die IDE ruft die Vervollständigung nach „.“ nicht von selbst auf. |
| Code-Vervollständigung: Verzögerung beim Tippen | `Auto Invoke Delay` | `-1` | immer | Ab 0 öffnet die IDE beim Tippen zusätzlich ihre eigene Liste. |
| Code-Parameter: Automatisch aufrufen | `Auto Code Parameters` | `True` | immer | Aus: Der Parameter-Hint öffnet bei „(“ und „,“ nicht von selbst. |
| Kurzhinweis Hilfe-Insight | `Help Insight` | `False` | „Eigener Tooltip …“ an | Sonst zeigt die IDE Help Insight neben dem dpcc-Tooltip. Zusätzlich verbirgt dpcc das Fenster zur Laufzeit (siehe unten). |
| Kurzhinweis Symbol-Insight | `Declaration Information` | `False` | „Eigener Tooltip …“ an | Sonst zeigt die IDE ihren Kurzhinweis neben dem dpcc-Tooltip. |
| Kurzhinweis Ausdrucksauswertung | `ToolTip Watches` | `False` | Tooltip und „Werte beim Debuggen zeigen“ an | Sonst zwei Wert-Tooltips beim Debuggen. |
| Code-Vervollständigung mit dem Parameter-Insight öffnen | `AutoInvokeCompletionOnParameterInsight` (unter `InsightGlobalOptions`) | `False` | immer | Sonst öffnet die IDE mit dem Parameter-Hint zusätzlich ihre Liste. |

Ein fehlender Wert gilt mit der Vorgabe der IDE (Schalter an, Verzögerung -1). Passt er schon, schreibt dpcc nichts.
Die Namen der Optionen sind die der deutschen IDE, gekürzt; maßgeblich ist der Registry-Wert.

Help Insight zur Laufzeit: Unabhängig vom Registry-Wert verbirgt dpcc das Fenster von Help Insight der IDE, sobald
es sichtbar wird, solange die Betriebsart Plugin gilt und entweder „Eigener Tooltip …“ an ist (dann immer) oder das Popup der
Vervollständigung von dpcc offen ist (dann auch bei ausgeschaltetem eigenem Tooltip, damit das Fenster die Liste
nicht verdeckt). Das wirkt sofort, ohne Neustart von Delphi; in den Betriebsarten Aus und Server bleibt Help Insight
der IDE unberührt.
Das erste Verbergen je Sitzung steht im Protokoll („Help Insight der IDE: Fenster THelpInsightWindow verborgen …“),
mit „Ablauf protokollieren (Log)“ jedes mit Grund. Beim Start steht außerdem eine Zeile „Help Insight in der
Registry (…)“ mit dem gelesenen Wert an den Orten von DelphiLSP, `Borland.EditOptions.Pascal` und
`Borland.EditOptions.HTML`.

### Code Insight der IDE

Gilt in der Betriebsart Plugin, wenn unter **Tools › Optionen › Editor › Sprache › Code Insight** dpcc als Anbieter
gewählt ist. Was dpcc selbst macht, stellt man auf der Seite dpcc ein; im Dialog der IDE blendet dpcc diese Felder
aus. Was die IDE allein macht, bleibt dort. Die Betriebsarten Aus und Server ändern sich dadurch nicht: Dort ist
DelphiLSP gewählt, und der Dialog zeigt dessen Felder.

| Feld im Dialog der IDE | Registry-Wert | Geregelt von | Im Dialog |
|---|---|---|---|
| Programmierhilfe | `Auto Code Completions` | bleibt IDE; dpcc stellt es in der Betriebsart Plugin auf an. Die Liste nach „.“ schaltet „Nach dem Punkt automatisch öffnen“ ab. | sichtbar (keine Abfrage in der Open Tools API) |
| Automatisch aufrufen, samt Verzögerung | `Auto Invoke`, `Auto Invoke Delay` | „Nach dem Punkt automatisch öffnen“; die Verzögerung stellt dpcc auf -1 | ausgeblendet |
| Automatische Klammern | `CodeCompleteAutoParens` | „Klammern bei Methoden ergänzen“ | ausgeblendet |
| Verlauf | `History` | „Häufig und zuletzt gewählte Einträge nach oben“ | ausgeblendet |
| Reservierte Wörter anzeigen | `Show Reserved Words` | „Reservierte Wörter in der Liste zeigen“ | ausgeblendet |
| Unvollständige Eigenschaften abschließen | `Finish properties` (unter `Class Completion`, für alle Anbieter) | bleibt IDE | sichtbar (keine Abfrage) |
| Code-Parameter | `Auto Code Parameters` | „Parameter-Hint bei „(“ und „,““ | ausgeblendet |
| Kurzhinweis Ausdrucksauswertung | `ToolTip Watches` | „Werte beim Debuggen zeigen“ | ausgeblendet |
| Kurzhinweis Symbol-Insight | `Declaration Information` | „Eigener Tooltip beim Verweilen über Bezeichnern“ | ausgeblendet |
| Kurzhinweis Hilfe-Insight | `Help Insight` | „Eigener Tooltip beim Verweilen über Bezeichnern“ | ausgeblendet |
| Blockvervollständigung | `Auto-block Completion` | bleibt IDE | sichtbar |
| Umbruchstil der Blockvervollständigung | `Block Wrap Style` | bleibt IDE | sichtbar |
| Code-Vorlagen vervollständigen | `Code Templates` | bleibt IDE | sichtbar (keine Abfrage) |
| Vorlagen automatisch vervollständigen | `Auto Complete Templates` | bleibt IDE | sichtbar (keine Abfrage) |
| Hinweise | `Sync Edit Hints` | bleibt IDE | sichtbar (keine Abfrage) |
| LSP-Konfiguration generieren | `CodeInsightLSPGenerate` | betrifft nur DelphiLSP, mit dpcc ohne Wirkung | ausgeblendet |
| 64-Bit-Version des Servers verwenden (nur Delphi 13) | `CodeInsightUse64BitBinary` | betrifft nur DelphiLSP, mit dpcc ohne Wirkung | ausgeblendet (in Delphi 13 mit dpcc als Anbieter gesehen am 28.11.2026) |
| Visual Assist verwenden | `CodeCompleteUseVA` | bleibt IDE | wie bisher |
| Error Insight (eigener Reiter) | `Error Insight` | bleibt IDE | sichtbar wie bisher |

- dpcc blendet über `IOTACodeInsightManagerEnvOptions` aus (Delphi 12 und 13 gleich), „LSP-Konfiguration
  generieren“ über `IOTACodeInsightManagerEnvOptions270` (in beiden Versionen gleich deklariert). Für
  Programmierhilfe, die Vorlagen, die Hinweise und die unvollständigen Eigenschaften gibt es keine Abfrage; sie
  bleiben sichtbar. „Blockvervollständigung“ und ihr Umbruchstil haben eine Abfrage, dpcc lässt sie sichtbar.
- Die Namen der Felder sind die der deutschen IDE, gekürzt; maßgeblich ist der Registry-Wert. Ein ausgeblendetes Feld
  behält seinen Wert; die IDE schreibt ihn mit OK wie bisher.

Welchen Satz der Registry die IDE mit dpcc als Anbieter liest (gemessen am 28.11.2026 im Plugin-Betrieb mit
vertauschten Werten in `Code Insight\Borland.EditOptions.Pascal`, im Satz von DelphiLSP,
`Borland.EditOptions.dpcc.CodeInsight`, HTML und StyleSheet; geprüft mit begin+Enter, todo+Leertaste und dem Öffnen
nach „.“):

| | Delphi 12 (BDS 23.0) | Delphi 13 (BDS 37.0) |
|---|---|---|
| Name aus `GetOptionSetName` | `Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` (seit dieser Fassung; vorher `Borland.EditOptions.Pascal`) | `Borland.EditOptions.Pascal` |
| Satz, den die IDE für dpcc liest | mit dem früheren Namen keinen (Blockvervollständigung, Vorlagen und das Öffnen nach „.“ waren in vier Läufen immer an); mit dem jetzigen den Satz von DelphiLSP: Blockvervollständigung und Vorlagen folgten in zwei vertauschten Läufen genau diesem Satz, der Code-Insight-Dialog zeigt mit Manager dpcc seine Werte | `Code Insight\Borland.EditOptions.Pascal`; Blockvervollständigung, Vorlagen und das Öffnen nach „.“ folgten in zwei vertauschten Läufen genau diesem Satz |
| Beim Beenden | schreibt den Satz nicht zurück (ein entfernter Wert blieb nach dem Beenden weg); mit OK im Optionsdialog schreibt die IDE ihn aus dem Speicher | schreibt `Borland.EditOptions.Pascal` zurück |
| Folge | Plugin und Server teilen sich einen Satz. Blockvervollständigung und Vorlagen gelten wie für DelphiLSP eingestellt; die Liste nach „.“ schaltet „Nach dem Punkt automatisch öffnen“ ab. | Die Funktionen der IDE übernimmt dpcc einmal in Lücken dieses Satzes (siehe [Nach dem Update](#nach-dem-update)). |

Gemessen am 28.11.2026 im Testprofil: Delphi 12 mit dpcc als Anbieter und dem jetzigen Namen, Blockvervollständigung
und Vorlagen im Satz von DelphiLSP aus (in `Borland.EditOptions.Pascal` an): begin+Enter ergänzte kein `end`,
todo+Leertaste blieb `todo`; mit vertauschten Werten ergänzte die IDE `end` und die Vorlage `{TODO …}`. Die
Werte, die dpcc im Plugin-Betrieb stellt (Programmierhilfe, Code-Parameter, Tooltips), liest die IDE wie bei Delphi 13
beim Start; was dpcc beim Wechsel schreibt, gilt nach dem nächsten Start von Delphi.

### Optionen in der Betriebsart Server

Ort: `HKCU\<Basis>\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` (der Ort von DelphiLSP, unter
Delphi 12 und 13 gleich). Werte als Zeichenkette `True`/`False`, wie die IDE sie schreibt.

| Option der IDE | Registry-Wert | Soll | Grund |
|---|---|---|---|
| Programmierhilfe | `Auto Code Completions` | `True` | Aus: Nach „.“ öffnet keine Liste. |
| Automatisch aufrufen | `Auto Invoke` | `True` | Aus: Die IDE ruft die Vervollständigung nach „.“ nicht von selbst auf. |
| Code-Parameter: Automatisch aufrufen | `Auto Code Parameters` | `True` | Aus: Der Parameter-Hint öffnet bei „(“ und „,“ nicht von selbst. |
| Kurzhinweis Symbol-Insight | `Declaration Information` | `True` | Aus: Beim Verweilen über einem Bezeichner fragt die IDE `dpcc.LspServer.exe` nicht. |

- Andere Optionen stellt die Betriebsart Server nicht. `Error Insight` und `ErrorInsightLevel` bleiben unberührt.
- Merker und Rückweg wie in der Betriebsart Plugin (siehe [Merker und Rückweg](#merker-und-rückweg)). Gemerkt
  bleibt der Wert von vor dem ersten Eingriff von dpcc, auch wenn dpcc die Option zuvor in der Betriebsart Plugin
  gestellt hatte. Aus stellt diesen Wert wieder her.
- Fehlt ein Wert oder der Schlüssel, gilt die Vorgabe der IDE (an); dpcc schreibt dann nichts und legt nichts an.
- Schaltet man eine der vier Optionen in der Betriebsart Server im Code-Insight-Dialog der IDE aus, gilt dieselbe
  Regel wie für die Schalter der Betriebsart Plugin: dpcc schaltet sie beim nächsten Abgleich wieder ein (Gegenprüfung
  nach OK auf der Seite dpcc, Beenden oder nächster Start von Delphi). Gab es noch keinen Merker, merkt dpcc den
  ausgeschalteten Wert als Wert davor; Aus stellt ihn dann wieder her.
- Wann es wirkt: dpcc schreibt die Werte in die Registry, prüft nach dem Dialog gegen und schreibt sie beim Beenden
  von Delphi noch einmal, falls die IDE sie aus dem Speicher überschrieben hat (wie in der Betriebsart Plugin). Die
  IDE liest sie erst beim nächsten Start von Delphi; einen Weg, sie in der laufenden IDE umzustellen, nutzt dpcc
  nicht. Hat dpcc Optionen eingeschaltet, sagt das Meldungsfenster es einmal („Für den Server hat dpcc in den
  Code-Insight-Optionen der IDE eingeschaltet: …“).

### Prüfung in den Betriebsarten Aus und Server

dpcc prüft beim Start. In der Betriebsart Aus ändert es nichts; in der Betriebsart Server prüft es die vier
[Optionen für den Server](#optionen-in-der-betriebsart-server), die es selbst setzt, und dazu `Error Insight`. Das
Ergebnis steht im Protokoll und im Abschnitt [IDE](#ide) der Seite.

Betriebsart Aus (mit DelphiLSP, nur geprüft):

| Option der IDE | Registry-Wert | Soll | Grund |
|---|---|---|---|
| Programmierhilfe | `Auto Code Completions` | `True` | Aus: Nach „.“ öffnet keine Liste (siehe [Fehlersuche](troubleshooting.md#nach-dem-punkt-öffnet-keine-liste)). |
| Automatisch aufrufen | `Auto Invoke` | `True` | Aus: Die IDE ruft die Vervollständigung nach „.“ nicht von selbst auf (siehe [Fehlersuche](troubleshooting.md#nach-dem-punkt-öffnet-keine-liste)). |
| Code-Parameter: Automatisch aufrufen | `Auto Code Parameters` | `True` | Aus: kein Parameter-Hint von selbst. |
| Error Insight | `Error Insight` | `True` (fehlt = an) | Aus: Die Fehlermarkierungen von DelphiLSP fehlen im Editor. In der Betriebsart Server bleiben sie ohnehin leer. |

#### Orte der Schlüssel je Version

| | Delphi 12 (BDS 23.0) | Delphi 13 (BDS 37.0) |
|---|---|---|
| Betriebsarten Aus und Server (DelphiLSP) | `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` | `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` |
| Betriebsart Plugin | `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` (derselbe Satz wie Aus und Server) | jeder vorhandene aus `Code Insight\Borland.EditOptions.Pascal` und `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` |

Delphi 12: Seit dieser Fassung nennt dpcc dort als Optionssatz den von DelphiLSP, und die IDE liest ihn für dpcc
(gemessen, siehe [Code Insight der IDE](#code-insight-der-ide)). dpcc setzt und prüft in der Betriebsart Plugin genau
diesen Satz; `Borland.EditOptions.Pascal` fasst es unter Delphi 12 nicht mehr an. Merker früherer Fassungen für
`Borland.EditOptions.Pascal` räumt der nächste Abgleich auf („aufgeräumt (alter Ort)“): Steht der Wert noch so, wie
dpcc ihn schrieb, kommt der Wert davor zurück bzw. wird gelöscht, wenn es keinen gab; sonst bleibt er, und nur der
Merker entfällt. Delphi 13: dpcc setzt und prüft jeden der beiden Orte, den es gibt, und legt keinen fehlenden an;
fehlen beide, nimmt es den Ort von DelphiLSP. Das Fenster von Help Insight verbirgt dpcc zusätzlich zur Laufzeit
(siehe [Schalter in der Betriebsart Plugin](#schalter-in-der-betriebsart-plugin)).

Weil Plugin und Server unter Delphi 12 denselben Satz stellen, gilt beim Wechsel (Beispiel: Nutzer mit
Programmierhilfe und Code-Parametern aus, Tooltips an, „Eigener Tooltip“ und „Werte beim Debuggen zeigen“ an):

| Wechsel | Programmierhilfe, Code-Parameter | Symbol-Insight | Help Insight, Ausdrucksauswertung | Merker danach (Wert des Nutzers) |
|---|---|---|---|---|
| Aus → Plugin | `True` | `False` | `False` | alle fünf, dazu `Insight Manager` |
| Plugin → Server | bleiben `True` (nicht zurück und wieder vor) | `True` | zurück auf `True` | Programmierhilfe, Code-Parameter, Symbol-Insight |
| Server → Plugin | bleiben `True` | `False` | `False` | alle fünf, dazu `Insight Manager` |
| Plugin → Aus, Server → Aus | zurück auf `False` | zurück auf `True` | zurück auf `True` | keine |
| Aus → Server | `True` | bleibt `True` | bleiben `True` | Programmierhilfe, Code-Parameter |

`Automatisch aufrufen` steht in Plugin und Server auf `True` (fehlt der Wert, gilt an, dann schreibt dpcc nichts).
Nur Plugin stellt dazu `Auto Invoke Delay` (-1), `AutoInvokeCompletionOnParameterInsight` (`False`) und den Anbieter.
Ein Start von Delphi in derselben Betriebsart ändert nichts.
Fehlt der geprüfte Schlüssel ganz, steht im Ergebnis „Schlüssel fehlt (IDE-Vorgabe)“; das ist kein Fehler. Die
Protokollzeile lautet etwa
„IDE-Einstellungen: 1 Abweichung: Auto Code Completions; Anbieter „Borland.CodeInsight.LSP.Pascal“, geprüft …“.

### Merker und Rückweg

- Jede Änderung hält dpcc unter `HKCU\Software\dpcc\IdePlugin` fest, je Version getrennt:
  `IdeSet <Version> <Schlüssel>\<Wert>` mit dem geschriebenen Wert und dem Wert davor (oder dass es keinen gab).
- Mit eigenem Registry-Profil (`bds -r <Profil>`) heißen die Merker `IdeSet <Profil> <Version> …`, die Betriebsart
  `OperatingMode <Profil> <Version>` und der Merker der einmaligen Übernahme `IdeAdopted <Profil> <Version>
  IdeFeatures`. Eine IDE mit eigenem Profil liest und ändert die Werte des Standardprofils (`BDS`) also nicht. Im
  Standardprofil bleiben die Namen wie bisher; vorhandene Merker gelten weiter. Ältere Merker (siehe unten) gelten nur
  im Standardprofil.
- Zurückgedreht wird nur, was noch so steht, wie dpcc es geschrieben hat. Hat der Nutzer oder die IDE den Wert
  seither geändert, bleibt er; nur der Merker entfällt. Gab es den Wert vorher nicht, löscht dpcc ihn wieder.
- Ein Merker behält immer den Wert von vor dem ersten Eingriff von dpcc, auch über einen Wechsel zwischen Plugin und
  Server. Braucht die neue Betriebsart den Wert ebenfalls, bleibt der Merker stehen; stellt sie ihn anders, schreibt
  dpcc den neuen Wert in den Merker und behält den Wert davor. Merker aus früheren Fassungen gelten unverändert
  weiter.
- Ältere Merker (`IdeHelpInsightDisabled …`, `IdeTooltipWatchesDisabled …`) gelten weiter: Beim nächsten Abgleich
  dreht dpcc sie zurück bzw. ersetzt sie durch die neuen.
- Error Insight und die Strukturhervorhebung schaltet dpcc nie.
- `ErrorInsightLevel` setzt dpcc ebenfalls nicht, auch nicht in der Betriebsart Server.
- Vor dem Deinstallieren: Betriebsart Aus, OK, Delphi neu starten. Sonst bleibt `dpcc.CodeInsight` als Anbieter und
  bleiben die Schalter von dpcc stehen.
- Zusätzlich meldet dpcc einen eigenen Code-Insight-Manager und die Tastenbindung „dpcc Code Completion“ für
  Strg+Leertaste und Strg+Umschalt+Leertaste an. Beides baut es beim Entladen wieder ab.
