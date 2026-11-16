Deutsch | [English](../en/settings.md) | [Français](../fr/settings.md)

# Einstellungen

[Übersicht](index.md) › Einstellungen

Die Optionen stehen unter **Tools › Optionen › Drittanbieter › dpcc**. Die Seite trägt den Titel
„Vervollständigung, Parameter-Hint und Tooltip von dpcc“.

## Die Seite

- Links ein Baum mit den Bereichen **Allgemein**, **Vervollständigung**, **Einfügen** und **Hints**.
- Über dem Baum ein Suchfeld „Einstellung suchen …“. Enter springt zum ersten Treffer, Pfeil runter geht in die
  Trefferliste.
- Weicht ein Wert von der Vorgabe ab, steht ein Punkt „●“ vor der Beschriftung. Ein Rechtsklick bietet „Auf Standard
  zurücksetzen“ und „Ganze Seite auf Standard zurücksetzen“.
- Unten die Zeile „Filter:“ mit „Alle“, „Geändert“ und „Nur experimentelle“. Experimentelle Optionen gibt es auf
  dieser Seite derzeit nicht.
- Hängt eine Option an einer anderen, ist sie gesperrt, solange die andere aus ist. Der Grund steht daneben, etwa
  „gesperrt: „…“ (…) ist aus“. Am Hauptschalter hängen alle Optionen der Vervollständigung und der Tooltip.

Gespeichert wird mit **OK**. Ausnahmen: „Verlauf zurücksetzen“, „Entfernen“ und „Alle entfernen“ bei den Favoriten
und „Index neu aufbauen“ wirken sofort.

Die Spalte „Registry-Wert“ nennt den Namen unter `HKCU\Software\dpcc\IdePlugin`, die Spalte „Schlüssel“ den Namen,
den dpcc in Hinweisen und in `settings.json` verwendet. „–“ bei „Registry-Wert“: Die Option liegt nicht in der
Registry, sondern in `settings.json` (siehe [Ablage](#ablage)).

## Allgemein

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Code Insight von dpcc (aus: eingebaute Code Insight der IDE) | `Enabled` | `completion.enabled` | an | Hauptschalter. Aus: dpcc schließt seine Liste, Parameterhilfe und Tooltip; Strg+Leertaste und Strg+Umschalt+Leertaste gehen an die IDE. An: dpcc startet Sitzung und Server, falls sie nicht laufen. Wirkt ohne Neustart der IDE. Der Server läuft beim Ausschalten weiter. |
| Knopf „Index neu aufbauen“ | – | – | – | Fragt nach, löscht alle Index-Caches und baut den Index neu auf. Siehe [Index und Cache](index-cache.md#index-neu-aufbauen). |
| Office-Typbibliotheken und WinRT vorab indizieren (mehr Speicher; „+ Unit“ schlägt ihre Symbole vor) | – | `index.officeAndWinRt` | aus | An: Der Index liest auch die Units unter `$(BDS)\OCX\Servers` (Excel, Word, Outlook, Access, MSHTML) und `$(BDS)\source\rtl\win\winrt` vorab ein; „+ Unit“ schlägt dann auch ihre Symbole vor. Das kostet im Index rund 140 MB. Aus: Über vorhandene `uses` bleiben die Units erreichbar, nur „+ Unit“ kennt sie nicht. Liegt in `settings.json`, nicht in der Registry; der Server baut den Index ohne Neustart um. Siehe [Index und Cache](index-cache.md#office-typbibliotheken-und-winrt). |

## Vervollständigung

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Sichtbare Zeilen der Liste: | `VisibleRows` | `completion.visibleRows` | 9 | 5 bis 20 Zeilen. |
| Breite der Liste automatisch | `ListWidth` | `completion.listWidth` | an (`ListWidth` = 0) | An: Die Liste wächst mit dem breitesten Eintrag. Aus: die zuletzt gezogene Breite (240 bis 720). Ziehen am rechten Rand der Liste setzt die Breite ebenfalls. |
| Verzögerung bis zum Öffnen (ms): | `OpenDelayMs` | `completion.openDelayMs` | 150 | 0 bis 2000; 0 = sofort. Gilt nur für das automatische Öffnen, nicht für Strg+Leertaste. Mit DelphiLSP als gewähltem Anbieter ohne Wirkung (siehe [Bedienung](usage.md#zusammenspiel-mit-delphilsp)). |
| Häufig und zuletzt gewählte Einträge nach oben | `Learning` | `completion.learning` | an | Lernende Gewichtung: Übernommene Einträge bekommen einen Zuschlag in der Rangfolge. Ab 5 Übernahmen gilt ein Eintrag als „häufig“. Gespeichert in `%APPDATA%\dpcc\usage.json`, höchstens 5.000 Einträge. |
| Favoriten anheften (Strg+D) | `Favorites` | `completion.favorites` | an | Strg+D in der offenen Liste heftet an bzw. löst. Siehe [Bedienung](usage.md#favoriten). |
| Geerbte Member nachrangig und nach Klasse gruppiert | `GroupInherited` | `completion.groupInherited` | an | Ohne getippten Anfang: eigene Member zuerst, dann je Vorfahr eine Gruppe „Geerbt von …“. Mit Anfang steht bei gleicher Güte der eigene Member vor dem geerbten. |
| Zweig varianter Record-Felder zeigen | `CompletionVariantBranch` | `completion.variantBranch` | an | Bei Feldern im varianten Teil eines Records (`case … of`) steht die Marke „Zweig 0“, „Zweig 1“ usw. |
| Beim Tippen zeigen: | `CompletionListMode` | `completion.listMode` | Nur Treffer | „Nur Treffer“ (`filter`), „Alle Einträge, Treffer oben“ (`all`), „Treffer, darunter gedämpft der Rest“ (`rest`, unter der Überschrift „Weitere Einträge“). |
| Gilt für: | `CompletionListScope` | `completion.listMode.scope` | Mitgliederlisten nach „.“ | Wo der Listenmodus gilt: „Mitgliederlisten nach „.““ (`members`) oder „Alle Listen“ (`everywhere`). |
| Vorschau des gewählten Eintrags im Editor | `Preview` | `completion.preview` | aus | Der fehlende Teil des gewählten Namens steht kursiv und gedämpft hinter dem Cursor. |
| Knopf „Verlauf zurücksetzen“ | – | – | – | Leert die lernende Gewichtung sofort. |
| Knopf „Breiten zurücksetzen“ | – | – | – | Setzt die Breite der Liste auf die Vorgabe (automatisch); gespeichert mit OK. |

### Angeheftete Favoriten (höchstens 5 je Typ)

Unter den Optionen steht die Liste der angehefteten Favoriten. Ohne Favoriten steht dort „Keine Favoriten
angeheftet.“

| Knopf | Wirkung |
|---|---|
| Entfernen | löst die markierten Favoriten, sofort |
| Alle entfernen | löst alle Favoriten, sofort |

Die Favoriten liegen in `%APPDATA%\dpcc\favorites.json`.

## Einfügen

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Klammern beim Übernehmen von Methoden ergänzen | `AutoParentheses` | `completion.autoParentheses` | an | Ergänzt die Klammern; ein direkt davor getipptes „)“ überspringt die automatische. |
| Schreibweise beim Übernehmen korrigieren (showmessage → ShowMessage) | `FixCase` | `completion.fixCase` | an | Ersetzt das getippte Wort durch die Schreibweise der Deklaration. |
| Übernehmen mit „(“, „;“ und „.“ (Commit-Zeichen) | `CommitCharacters` | `completion.commitCharacters` | an | Trifft der gewählte Eintrag eindeutig, übernimmt eines dieser Zeichen ihn; das Zeichen bleibt stehen. Sonst bleibt nur das Zeichen, und die Liste schließt. |
| Unit beim Übernehmen automatisch in uses eintragen | `AutoUses` | `completion.autoUses` | an | Bei Einträgen, die rechts „+“ und den Namen einer Unit zeigen (etwa „+ System.SysUtils“), trägt dpcc diese Unit in `uses` ein, im selben Undo-Schritt. |
| Parameter-Hint bei „(“ und „,“ | `ParameterHints` | `completion.parameterHints` | an | Aus: keine Parameterhilfe von dpcc, auch nicht über Strg+Umschalt+Leertaste. Das automatische Öffnen bei „(“ und „,“ erreicht dpcc nur, wenn die IDE dpcc als Anbieter aufruft (siehe [Bedienung](usage.md#zusammenspiel-mit-delphilsp)). |
| Platzhalter von Format im Parameter-Hint zuordnen und einfärben | `FormatPlaceholders` | `completion.formatPlaceholders` | an | Zeile zum Platzhalter am Cursor, Warnungen, gleiche Farbe für Platzhalter und Argument. Gesperrt, solange „Parameter-Hint bei „(“ und „,““ aus ist. |

## Hints

| Option | Registry-Wert | Schlüssel | Vorgabe | Wirkung |
|---|---|---|---|---|
| Eigener Tooltip beim Verweilen über Bezeichnern | `HoverTooltip` | `editor.hoverTooltip` | an | Tooltip von dpcc. Solange er an ist, schaltet dpcc Help Insight der IDE ab. Gesperrt, solange der Hauptschalter aus ist. |
| Werte im Hover beim Debuggen (schaltet dafür den Wert-Tooltip der IDE ab) | `DebugHoverValues` | `debug.hoverValues` | an | Bei angehaltenem Programm steht der Wert des Ausdrucks oben im Tooltip. Wer den Wert-Tooltip der IDE will, schaltet diese Option aus. |
| XMLDoc beim Öffnen | – | `hints.xmlDocExpand` | wie zuletzt | „immer zugeklappt“ (`collapsed`), „wie zuletzt“ (`last`), „immer aufgeklappt“ (`expanded`). Der Tooltip zeigt die XMLDoc im aktuellen Stand immer ganz; die Auswahl wird gespeichert, wirkt aber nicht sichtbar. Liegt in `settings.json`, nicht in der Registry. |
| XMLDoc: höchstens Zeilen ohne Scrollen (0 = Bildschirm) | – | `hints.xmlDocMaxLines` | 0 | 0 bis 50. Mehr Zeilen scrollen im Tooltip mit dem Mausrad. 0: begrenzt nur der Platz auf dem Bildschirm. Liegt in `settings.json`, nicht in der Registry. |

## Ablage

| Ort | Inhalt |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | alle Optionen außer `hints.*`. Schalter und Zahlen als DWORD (Schalter 0/1), Auswahlen als Text (`filter`, `members` …). Dazu die Merker für die IDE-Schalter (unten) und `PathOverrideBackup` von `Tools\IdePath.ps1`. |
| `%APPDATA%\dpcc\settings.json` | `hints.xmlDocExpand`, `hints.xmlDocMaxLines`, `index.officeAndWinRt`. Der Server im IDE-Prozess liest die Datei selbst und beobachtet sie. Registry-Werte `XmlDocExpand` und `XmlDocMaxLines` einer älteren Version übernimmt dpcc einmal, solange die Datei die Schlüssel noch nicht hat; danach gilt nur `settings.json`. |
| `%APPDATA%\dpcc\settings-history.json` | frühere Stände der Einstellungen; vor jeder gespeicherten Änderung legt dpcc den alten Stand dort ab |
| `%APPDATA%\dpcc\usage.json` | Verlauf der lernenden Gewichtung |
| `%APPDATA%\dpcc\favorites.json` | angeheftete Favoriten |

Eine unbrauchbare `usage.json` oder `favorites.json` legt dpcc als `….defekt` daneben und beginnt leer. Eine
gesperrte Datei überschreibt es nicht.

Alles auf Vorgabe: die IDE schließen und den Schlüssel `HKCU\Software\dpcc\IdePlugin` sowie `settings.json`
löschen. Vorher den Hauptschalter aus- und mit OK bestätigen, damit dpcc die IDE-Schalter zurückgibt (siehe unten).

## Was dpcc an der IDE umstellt

Für Help Insight und den Wert-Tooltip beim Debuggen gibt es keine Open Tools API. Die Schalter stehen in der Registry
der IDE und werden beim Start der IDE gelesen. dpcc schreibt sie dort und merkt sich unter
`HKCU\Software\dpcc\IdePlugin`, was es selbst abgeschaltet hat. Nur das schaltet es wieder ein.

| IDE-Schalter | Registry-Wert der IDE | dpcc schaltet ab, solange | dpcc gleicht ab | Merker |
|---|---|---|---|---|
| Help Insight | `Help Insight` | Hauptschalter an und „Eigener Tooltip …“ an | beim Laden des Plugins, nach jeder Änderung der Einstellungen und nach OK im Optionsdialog | `IdeHelpInsightDisabled <Version> <Ort>` |
| Ausdrucksauswertung im Kurzhinweis (Wert-Tooltip beim Debuggen) | `ToolTip Watches` | Hauptschalter, Tooltip und „Werte im Hover beim Debuggen“ an | nur nach OK im Optionsdialog von dpcc | `IdeTooltipWatchesDisabled <Version> <Ort>` |

- Ort der Werte: `HKCU\Software\Embarcadero\BDS\37.0\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal`
  (Delphi 13), dazu jeder andere Unterschlüssel von `Code Insight`, der den Wert schon trägt.
- Die IDE liest die Werte erst beim nächsten Start. Bis dahin können zwei Tooltips erscheinen. Das Meldungsfenster
  nennt jede Änderung, etwa „dpcc zeigt den Tooltip selbst und hat Help Insight der IDE abgeschaltet; wirkt nach dem
  nächsten Start von Delphi.“
- Der Wert-Tooltip wird nur nach OK im Optionsdialog abgeglichen, weil die IDE beim Schließen mit OK ihre
  Editoroptionen aus dem Speicher zurückschreibt. Nach der Installation ist er deshalb erst aus, wenn die Seite dpcc
  einmal mit OK geschlossen und die IDE neu gestartet wurde.
- Error Insight, die Strukturhervorhebung und die Wahl des Code-Insight-Anbieters ändert dpcc nicht.
- Zusätzlich meldet dpcc einen eigenen Code-Insight-Manager und die Tastenbindung „dpcc Code Completion“ für
  Strg+Leertaste und Strg+Umschalt+Leertaste an. Beides baut es beim Entladen wieder ab.
