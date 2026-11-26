Deutsch | [English](../en/usage.md) | [Français](../fr/usage.md)

# Bedienung

[Übersicht](index.md) › Bedienung

## Tasten im Editor

| Taste | Wirkung |
|---|---|
| Strg+Leertaste | Vervollständigung von dpcc öffnen |
| Strg+Umschalt+Leertaste | Parameterhilfe von dpcc öffnen |

dpcc belegt diese zwei Tasten mit einer eigenen Tastenbindung („dpcc Code Completion“). Es nimmt sie nur, wenn es
die Datei bedient: Endung `.pas`, `.dpr`, `.dpk` oder `.inc`, Hauptschalter an und die Funktion nicht von der
Sicherung abgeschaltet (siehe [Fehlersuche](troubleshooting.md)). Sonst gehen die Tasten an die IDE. Ebenso geht
ein zweites Strg+Leertaste an die IDE, wenn die Liste von dpcc an derselben Stelle leer blieb, und jedes
Strg+Leertaste, solange die Liste der IDE schon offen ist (siehe [unten](#liste-der-ide-wenn-dpcc-nichts-findet)).

Weitere Tasten belegt dpcc nicht dauerhaft. Pfeile, Enter, Tab und Esc nimmt es nur, solange eines seiner Fenster
offen ist und die Taste braucht.

## Zusammenspiel mit DelphiLSP

Delphi 12 und 13 leiten automatische Auslöser (Tippen von „.“, „(“, „,“) nur an den Code-Insight-Anbieter weiter,
der in den Optionen der IDE für Delphi gewählt ist. Die Vorgabe ist DelphiLSP. dpcc und DelphiLSP laufen deshalb
nicht nebeneinander, sondern in zwei Betriebsarten (Einzelheiten unter
[Einstellungen](settings.md#was-dpcc-an-der-ide-umstellt)):

- **Betriebsart dpcc** (Hauptschalter an): dpcc ist der Anbieter. Die Liste nach „.“, die Parameterhilfe bei „(“ und
  „,“, Strg+Leertaste, Strg+Umschalt+Leertaste und der Tooltip kommen von dpcc. dpcc stellt die nötigen Schalter der
  IDE selbst.
- **Betriebsart IDE** (Hauptschalter aus): DelphiLSP ist der Anbieter, dpcc ist aus. Ist beim Start von Delphi
  DelphiLSP gewählt, schaltet dpcc sich selbst aus.
- Den Hauptschalter einschalten stellt den Anbieter auf dpcc, ausschalten zurück auf DelphiLSP. Das wirkt nach dem
  Neustart von Delphi; bis dahin gilt das Folgende für den alten Anbieter.
- Die Liste, die beim Tippen eines Namens von selbst aufgeht (nur wenn eingeschaltet, siehe
  [Öffnen beim Tippen](#öffnen-beim-tippen)), kommt von dpcc: Dafür beobachtet dpcc den Editor selbst.

Welcher Anbieter gewählt ist, schreibt dpcc beim Start ins Protokoll (Zeile „Code Insight für Delphi-Dateien:
gewählt …“).

### Liste der IDE, wenn dpcc nichts findet

Bleibt die Liste nach Strg+Leertaste leer, steht in ihrer Fußzeile „Strg+Leertaste erneut für die Liste der IDE“.
Ein zweites Strg+Leertaste an derselben Stelle öffnet dann die Liste der IDE (DelphiLSP) statt der von dpcc. Leer
heißt hier: nichts gefunden, kein passender Kontext, ein Fehler oder das Zeitlimit des Servers.

- Es gilt nur, wenn der Cursor noch an derselben Stelle steht (Datei, Zeile, Spalte) und dazwischen nichts getippt
  wurde. Esc dazwischen ändert daran nichts, ein Wechsel des Reiters schon.
- Steht die Antwort von dpcc noch aus, fragt ein weiteres Strg+Leertaste wieder dpcc.
- Danach beginnt es von vorn: Das nächste Strg+Leertaste fragt wieder dpcc.
- Von selbst wechselt dpcc nie zur Liste der IDE.
- Ist die Liste der IDE schon offen (etwa nach „.“ von DelphiLSP), gehört Strg+Leertaste ihr. dpcc öffnet dann keine
  zweite Liste daneben.

Die Liste der IDE kommt vom Code-Insight-Anbieter, der in den Optionen der IDE für Delphi gewählt ist (Vorgabe
DelphiLSP). Ist dort dpcc selbst gewählt, gibt es keine Liste der IDE: Die IDE ruft auch für ein durchgereichtes
Strg+Leertaste wieder dpcc auf, nie DelphiLSP. Der Hinweis in der Fußzeile entfällt dann, und ein zweites
Strg+Leertaste fragt wieder dpcc. Wer die Liste von DelphiLSP als Ausweg haben will, lässt in den Optionen DelphiLSP
gewählt.

### Wenn dpcc als Anbieter gewählt ist

Ist in den Optionen der IDE dpcc als Code-Insight-Anbieter für Delphi gewählt, fragt die IDE für Strg+Klick und
„Deklaration suchen“ (Alt+↑) nur dpcc. Mit DelphiLSP (Vorgabe) springt die IDE wie gewohnt über DelphiLSP; dpcc ist
daran nicht beteiligt.

- Von einer Verwendung springt dpcc zur Deklaration (bei Methoden die in der Klasse bzw. im interface). Steht die
  Stelle schon auf der Deklaration selbst, geht es zur Implementierung, von dort wieder zurück. Bei Überladungen gilt
  die Variante mit denselben Parametertypen.
- Deklarationen ohne Rumpf (abstrakte Methoden, Methoden eines Interface, `external`): Strg+Klick bleibt dort stehen,
  auch bei Überladungen; es springt nicht zu einer anderen Variante.
- `inherited;` ohne Namen springt wie `inherited Name` zur gleichnamigen Methode im Vorfahren.
- Ziele: über Units, Unit-Namen in `uses` (Anfang der Datei), Dateinamen in `{$I …}` bzw. `{$INCLUDE …}` (Anfang der
  eingebundenen Datei; `{$R …}` springt nicht), lokale Variablen und Parameter, Typen, Felder hinter
  Ausdrücken wie `Liste[i].X`, Deklarationen in Include-Dateien und in nicht aktiven Zweigen (`{$IFDEF …}`), Units
  der Bibliothek, die dpcc erst dafür nachlädt (auch Office-Typbibliotheken und WinRT). Bei gleichnamigen Units gilt
  die des eigenen Projekts.
- Kein Ziel, kein Sprung: Units ohne Quelltext (nur aus Packages bekannt), Units, die dpcc nicht findet,
  mehrdeutige Überladungen und `with` mit unbekanntem Typ. Die IDE springt dann nicht; dpcc nennt den Grund im
  Meldungsfenster (Gruppe dpcc), etwa „Unit X liegt nur als Package vor (kein Quelltext)“, „Unit X nicht gefunden“
  oder „„Name“ nicht aufgelöst“. Fehlen Name oder Unit nur, weil der Index noch aufgebaut wird, heißt es statt dessen
  „Kein Sprung: Der Index wird noch aufgebaut. Bitte gleich erneut klicken.“; dpcc wartet dann nicht und springt auch
  nicht nach. Bei anderen Gründen steht während des Aufbaus der Zusatz „Der Index wird noch aufgebaut.“ Dieselbe
  Meldung erscheint nicht mehrfach hintereinander. Jeder Sprung ohne Ziel steht zudem als eine Zeile in `dpcc.log`.
- Bei Strg+Klick gilt die Stelle unter der Maus, bei „Deklaration suchen“ der Cursor.
- Die IDE wartet höchstens 250 ms auf dpcc. Kommt die Antwort später, springt dpcc selbst, sofern dieselbe Datei
  aktiv ist, der Cursor noch im selben Bezeichner steht (dem angeklickten oder dem, in dem er beim Klick stand) und
  die Antwort höchstens 10 Sekunden nach dem Klick eintraf.
- Startet dpcc noch, merkt es sich den Sprung („dpcc startet noch“ im Meldungsfenster) und holt ihn nach, sobald es
  bereit ist, nach denselben Regeln.

Beim ersten Mal je Sitzung nennt das Meldungsfenster, dass dpcc gewählt ist und was dann fehlt: Error Insight
(Fehlermarkierungen im Editor) und die übrigen Dienste von DelphiLSP. Wer sie braucht, schaltet den Hauptschalter
aus (oder wählt in den Optionen der IDE wieder DelphiLSP); ab dem nächsten Start ist dpcc dann aus.

## Die Liste

Strg+Leertaste öffnet die Liste am Cursor. Das Wort vor dem Cursor gilt als Anfang des Gesuchten.

Aufbau einer Zeile:

- links die Art als Wort, gedämpft (`procedure`, `function`, `type`, `property` …);
- der Name fett, die getippten Zeichen unterstrichen;
- dahinter die Signatur oder gedämpft ein Detail;
- rechts gedämpft „+“ und der Name der Unit (etwa „+ System.SysUtils“), wenn die Unit noch nicht in `uses` steht,
  und Warnungen als Text.

Die Fußzeile nennt die Tasten oder einen Hinweis.

### Öffnen beim Tippen

Die Einstellung „Beim Tippen öffnen ab Zeichen“ (`completion.autoMinChars`, siehe [Einstellungen](settings.md)) hat
die Vorgabe 0 = aus: Dann öffnet Tippen die Liste nie, wie vor dieser Funktion. Wer sie will, stellt z. B. 5 ein.
Tippt man dann einen Namen ohne Punkt davor, öffnet dpcc die Liste von selbst, sobald das Wort vor dem Cursor so
viele Zeichen hat. Mit weniger Zeichen fragt dpcc den Server gar nicht: Die Liste aller Namen im Gültigkeitsbereich hätte bei kurzem
Anfang oft über tausend Einträge und bräuchte spürbar Rechenzeit.

- Strg+Leertaste öffnet die Liste wie bisher sofort, bei jeder Zahl von Zeichen.
- Ist die Liste offen (auch mit Strg+Leertaste bei weniger Zeichen geöffnet), filtert jedes weitere Zeichen nur;
  Tippen fragt nicht neu.
- Nach „.“ gilt die Schwelle nicht: Die Mitgliederliste kommt wie bisher mit dem Punkt. Ebenso bleiben die übrigen
  Auslöser unverändert („[“, „(“ hinter einem Namen, „;“ und Enter hinter einem übernommenen Konstruktor).
- In Kommentaren (auch `{$…}`), Strings, Zahlen und mitten in einem Wort öffnet Tippen nichts. Findet der Server
  nichts (etwa in einem mehrzeiligen Kommentar), bleibt die Liste ohne Meldung zu.
- In `uses`, nach `raise` und in Attributklammern gilt dieselbe Schwelle; welche Liste kommt, entscheidet wie bei
  Strg+Leertaste der Server. Units, die noch nicht in `uses` stehen („+ Unit“), bietet er weiterhin erst ab
  2 Zeichen an.
- Die feste Verzögerung bis zum Öffnen (150 ms) gilt auch hier: Wer zügig weitertippt, bekommt die Liste erst in
  der Pause, mit dem bis dahin getippten Wort.
- Ist das getippte Wort schon der Name des gewählten Eintrags (etwa `begin`), ist nichts gewählt: Enter bricht die
  Zeile um, statt den Eintrag zu übernehmen. Eine Pfeiltaste wählt den Eintrag.
- Nach Esc öffnet die Liste im selben Wort nicht wieder von selbst.
- Im Platzhalter-Modus und solange die Liste der IDE offen ist, öffnet Tippen nichts.
- 0 schaltet das Öffnen beim Tippen ab.

### Tasten in der offenen Liste

| Taste | Wirkung |
|---|---|
| ↑ / ↓ | Auswahl bewegen |
| Bild↑ / Bild↓ | seitenweise bewegen |
| Pos1 / Ende | erster / letzter Eintrag |
| Enter oder Tab | gewählten Eintrag übernehmen |
| Esc | Liste schließen |
| weitertippen | Liste filtern |
| Rücktaste | Filter lockern; ist das Wort kürzer als bei der Anfrage, fragt dpcc neu |
| „(“, „;“, „.“ | übernehmen, wenn der gewählte Eintrag eindeutig trifft; das Zeichen bleibt stehen (Commit-Zeichen, abschaltbar) |
| Strg+D | gewählten Eintrag als Favorit anheften oder lösen |
| Leertaste | nur im Mengenmodus: Wert anhaken oder abhaken |

Die Liste schließt auch, wenn der Cursor das Wort oder die Zeile verlässt, der Editor den Fokus verliert, die IDE
inaktiv wird, der Editor scrollt oder die Ansicht wechselt.

Nach dem Schließen mit Esc öffnet ein automatischer Start im selben Wort die Liste nicht wieder. Strg+Leertaste
öffnet sie und hebt diese Sperre auf.

### Filtern und Reihenfolge

Beim Weitertippen filtert dpcc die vorhandene Liste selbst, ohne neue Anfrage. Reihenfolge der Treffer:

1. genauer Name,
2. Anfang mit gleicher Schreibweise,
3. Anfang,
4. Wortanfänge (`TSL` findet `TStringList`),
5. Teilstring,
6. Teilfolge.

Dazu kommen, je nach Einstellung:

- **Favoriten** stehen vor allen anderen, wenn sie zum Getippten passen.
- **Häufig und zuletzt gewählte Einträge** bekommen einen Zuschlag. Ein besserer Treffer bleibt trotzdem vorn.
- **Erwarteter Typ**: Passende Einträge stehen oben unter der Überschrift „Passt zu …“, darunter die übrigen.
- **Geerbte Member**: Ohne getippten Anfang stehen die eigenen Member zuerst, dann je Vorfahr eine Gruppe
  „Geerbt von …“.
- **Listenmodus**: Wahlweise bleiben in Mitgliederlisten nach „.“ beim Tippen auch Einträge ohne Treffer sichtbar.
  Steht dann kein Treffer oben, ist nichts gewählt; Enter gehört dem Editor, eine Pfeiltaste wählt den ersten
  Eintrag.

Übernimmt man mitten in einem Wort, ersetzt dpcc das ganze Wort.

### Breite und Höhe

- Die Zahl der sichtbaren Zeilen ist einstellbar (5 bis 20).
- Den rechten Rand kann man mit der Maus ziehen. Doppelklick unten rechts stellt die automatische Breite wieder her.
- Ohne gezogene Breite wächst die Liste mit dem breitesten Eintrag. Während einer Sitzung schrumpft sie nicht, damit
  sie beim Filtern nicht springt.
- Gekürzte Zeilen zeigen den vollen Text, wenn die Maus 600 ms darauf verweilt.

### Hinweise in der Liste

| Anzeige | Bedeutung |
|---|---|
| „Keine Treffer für „…““ | Nichts passt. Nur Esc gehört der Liste; Pfeile und Enter gehen an den Editor. |
| „Keine Vorschläge an dieser Stelle“ | An dieser Stelle gibt es nichts anzubieten. |
| Fußzeile „Strg+Leertaste erneut für die Liste der IDE“ | Die Liste nach Strg+Leertaste ist leer; ein zweites Strg+Leertaste an derselben Stelle öffnet die Liste der IDE (siehe [oben](#liste-der-ide-wenn-dpcc-nichts-findet)). |
| „eingeschränkt (Index wird aufgebaut)“ | Der Index ist noch nicht fertig; die Liste kann unvollständig sein. |
| Leiste „Ergebnisse möglicherweise unvollständig · Syntaxfehler in Zeile n“ | Vor dem Cursor steht in der aktuellen Routine oder Klasse ein Syntaxfehler. |
| Leiste „Kontext unklar · Syntaxfehler in Zeile n“ | wie oben, und es gibt keine Einträge. |

### Vorschau

Die Vorschau des gewählten Eintrags im Editor (der noch fehlende Teil des Namens kursiv und gedämpft hinter dem
Cursor) gibt es nicht mehr; sie war zuletzt fest ausgeschaltet (siehe
[Einstellungen](settings.md#fest-eingestellte-werte)).

## Was die Liste anbietet

Was erscheint, hängt von der Stelle ab. Der Server prüft die Fälle in fester Reihenfolge; der erste passende
antwortet.

| Stelle | Angebot |
|---|---|
| nach `Ausdruck.` | Mitglieder des Typs samt geerbter; bei Units deren interface-Symbole |
| nach `Ausdruck.` mit bekanntem Typ | zusätzlich Postfix-Vorlagen (siehe unten) |
| sonst | alle sichtbaren Namen: lokal, eigene Klasse, eigene Unit, Units aus `uses` |
| ab zwei getippten Zeichen | auch Symbole aus Units, die noch nicht in `uses` stehen, mit „+“ und dem Namen der Unit; Projekt-Units vor Bibliotheken |
| im `uses`-Abschnitt | bekannte Units in Gruppen: Projekt, RTL/VCL, Drittanbieter; Hinweis, wenn eine Unit schon im anderen Abschnitt steht; Kennzeichen „Zirkelbezug“ |
| nach `inherited ` | Methoden der Vorfahren; die gleichnamige Methode zuerst, mit Argumenten aus den eigenen Parametern |
| nach `class(`, `is`, `as`, nach `:` in Deklarationen | nur Typen |
| nach `<` eines generischen Typs | Typargumente, gefiltert nach den Constraints |
| in `[…]` vor einer Deklaration | Attributklassen, ohne die Endung `Attribute` |
| nach `raise ` und `on E: ` | Exception-Klassen; nach `on E:` zuerst die, die der try-Block laut XMLDoc auslösen kann |
| Vergleich, `case`-Zweig, Zuweisung mit Aufzählungstyp | Werte der Aufzählung zuerst |
| in einem Mengenkonstruktor `[…]` | Mengenmodus (siehe unten) |
| auf einer leeren Zeile einer Klasse mit Interface | fehlende Methoden des Interface zum Anhaken |
| in einer Klassendeklaration nach `procedure ` bzw. `function ` | überschreibbare Methoden |
| nach `property … read` / `write` | passende Felder und Methoden |
| nach `Objekt.Ereignis := ` | passende Methoden und „Neue Methode …“ |
| wo ein Methodenreferenztyp erwartet wird | Gerüst einer anonymen Methode mit passender Signatur |
| an der Namensposition einer Deklaration | Namensvorschläge |
| nach `{$`, `{$IFDEF ` usw. | Compilerdirektiven und bedingte Symbole |
| nach `{$I ` bzw. `{$INCLUDE ` | Namen der `.inc`-Dateien aus dem Ordner der Datei (bzw. dem getippten Unterordner) und aus den Ordnern der Include-Dateien, die die Unit schon einbindet |
| in einem `///`-Kommentar, dessen Parameter nicht mehr passen | „Parameter abgleichen“ |
| in der Unit eines Formulars | Komponenten des Formulars als eigene Gruppe „Formular …“ |
| `Sender.` in einem Ereignisbehandler | Mitglieder des gemeinsamen Typs der Komponenten, denen die Methode im Formular zugewiesen ist |
| in `FieldByName('…')`, `FindField('…')`, `ParamByName('…')` | Feld- bzw. Parameternamen der Datenmenge |
| Name in mehreren Units deklariert | die Variante, die der Compiler wählt, zuerst mit „aktiv“, die übrigen mit ihrer Unit |

### Ausdrücke vor dem Punkt

Hinter dem Punkt kennt die Liste den Typ nicht nur bei Namensketten (`Liste.Items.`), sondern auch nach Ausdrücken:

- Index und Default-Property: `Liste[i].`, `Items[0].`, `FArray[0].`, auch bei `array of T`, statischen Arrays und
  Feldern oder lokalen Variablen mit anonymem Array-Typ
- Klammern, Typumwandlung und `as`: `(Sender as TButton).`, `TButton(Sender).`
- Zeiger: `P^.`, bei einem Zeiger auf einen Record auch `P.`
- Literale: `'abc'.`, `42.` (Mitglieder der Helper von `string` bzw. `Integer`)
- Aufrufe: `Foo(1).` mit der passenden Überladung, Aufrufe über Prozedurtypen und `reference to` (`FOnGet(1).`),
  generische Routinen ohne Typargumente (`Max(A, B).`, `T` aus den Argumenten)
- verschachtelte Typen als Typ eines Mitglieds: `Dict.Values.`, `Liste.GetEnumerator.Current.`

Inline-Variablen ohne Typangabe erhalten den Typ ihres Ausdrucks auch bei Operatoren (`var S := A + IntToStr(1);`
ist ein `string`, `I / 2` ein `Extended`, Vergleiche und `not` ein `Boolean`), bei `class operator` von Records,
bei `@X` (Zeiger auf den Typ von `X`), `P^`, Mengenkonstruktoren und anonymen Methoden. Die Variable einer
`for … in`-Schleife ohne Typangabe hat den Elementtyp: das Element eines Arrays, `Char` bei einem `string`, sonst
`GetEnumerator.Current`.

Nach einem Typnamen (`TFoo.`) zeigt die Liste nur, was über den Typ aufrufbar ist: Klassenmethoden, Konstruktoren,
`class var`, `class property`, Konstanten, verschachtelte Typen und die Werte einer Aufzählung. Nach `TFoo.Create.`,
`TFoo(X).` und `Self.` erscheinen alle Mitglieder.

### „+ Unit“

Steht ein Bezeichner in einer Unit, die noch nicht in `uses` steht, zeigt die Zeile rechts „+“ und den Namen dieser
Unit, etwa „+ System.SysUtils“ bei `FreeAndNil`. „+ Unit“ ist also kein fester Text; „Unit“ steht in dieser Doku für
den Namen. Beim Übernehmen trägt dpcc die Unit in `uses` ein (Einstellung „Unit automatisch in uses eintragen“).
Name und `uses`-Eintrag sind ein einziger Undo-Schritt.

„+ Unit“ bietet auch Werte von Aufzählungen an (etwa `fsBold` aus `Vcl.Graphics`). Generische Typen zeigen ihre
Typparameter (`TList<T>`), eingefügt wird nur der Name. Steht hinter dem Wort schon ein `<`, kommen sie vor
gleichnamigen Typen ohne Typparameter, sonst danach. Siehe [Index und Cache](index-cache.md#inhalt-je-deklaration).

### FieldByName und Formulare

dpcc liest dafür die Formulardatei (DFM) der Unit. Bei offenen Formularen nimmt es den aktuellen Stand aus dem
Designer, auch ungespeichert; Änderungen im Designer gehen nach 500 ms an den Server. Die Umwandlung in Text und das
Senden laufen im Hintergrund; ein unverändertes Formular wird gar nicht erst umgewandelt.

Quellen für Feldnamen, in dieser Reihenfolge:

1. persistente Felder der Datenmenge,
2. Spalten der SQL-Anweisung aus `SQL.Strings` bzw. `CommandText` (Aliasnamen gelten; bei `*` keine Spalten),
3. für `ParamByName`: die `:Platzhalter` der Anweisung und die Einträge der Params-Sammlung.

Ohne Formulardatei oder ohne die Datenmenge darin gibt es keine Namen. Für Datenmengen anderer Datenmodule
(`DM.qryOrders`) sucht dpcc die globale Variable im Index und liest die Formulardatei ihrer Unit.

### Postfix-Vorlagen

Hinter `Ausdruck.` bietet die Liste nach den Mitgliedern Kürzel an, die den Ausdruck umformen. Angeboten wird nur,
was zum Typ passt. Anweisungen gibt es nur, wenn der Ausdruck die Zeile beginnt.

| Kürzel | Ergebnis | Typ |
|---|---|---|
| `for`, `forin` | `for var Item in Liste do` | aufzählbar |
| `tryf` | `try … finally Obj.Free; end;` | Klasse |
| `ifa`, `notnil` | `if Assigned(X) then` | Klasse, Interface, Zeiger |
| `nil` | `if not Assigned(X) then` | Klasse, Interface, Zeiger |
| `not` | `not B` | Boolean |
| `if` | `if B then` | Boolean |
| `fmt` | `Format(S, [])` | String |
| `free` | `FreeAndNil(Obj);` | Klasse |
| `try` | `var Foo := TFoo.Create; try … finally Foo.Free; end;` | Konstruktoraufruf |
| `var` | `var Name := X;` | bekannter Typ |
| `exit` | `Exit(X);` | in einer Funktion |

## Platzhalter

Manche Einträge setzen Text mit Platzhaltern ein, etwa Postfix-Vorlagen oder das Gerüst einer anonymen Methode.
dpcc führt die Platzhalter selbst:

| Taste | Wirkung |
|---|---|
| tippen | ersetzt die Vorgabe des aktuellen Platzhalters |
| Tab | nächster Platzhalter; nach dem letzten an die Endposition |
| Umschalt+Tab | vorheriger Platzhalter |
| Enter | beenden und an die Endposition springen |
| Esc | an Ort und Stelle beenden |

Der aktuelle Platzhalter ist durchgezogen umrahmt, verknüpfte gestrichelt, die übrigen gepunktet. Hinter der Zeile
steht „Platzhalter 1 / 3 · Tab weiter · Esc fertig“. Verknüpfte Platzhalter mit derselben Nummer gleicht dpcc an.
Eine Änderung außerhalb oder ein Wechsel der Ansicht beendet den Modus.

Endet der Modus regulär (Esc, Enter, Tab nach dem letzten), macht ein Strg+Z das ganze Einsetzen in einem Schritt
rückgängig.

## Mengenmodus

In einem Mengenkonstruktor (`Anchors := [akLeft, |`) zeigt die Liste alle Werte des Elementtyps mit
Kontrollkästchen. Werte, die schon in der Klammer stehen, sind angehakt. Die Überschrift lautet etwa
„TAnchors · Menge von TAnchorKind“.

| Taste | Wirkung |
|---|---|
| Leertaste | gewählten Wert anhaken oder abhaken |
| Enter oder Tab, nachdem in dieser Liste die Leertaste gedrückt wurde | ganze Klammer neu schreiben: genau die angehakten Werte in Deklarationsreihenfolge, ohne Haken `[]`; bei `{$SCOPEDENUMS ON}` mit Typpräfix |
| Enter oder Tab, ohne dass in dieser Liste die Leertaste gedrückt wurde | den gewählten Wert zusätzlich anhaken und die Klammer wie oben neu schreiben: die vorhandenen Werte und der gewählte |
| Esc | verwerfen |

Die Fußzeile zeigt „Leertaste wählen · Enter einfügen · Esc verwerfen“ und die Zahl der gewählten Werte.

Dieselbe Liste dient für „Interface implementieren“: fehlende Methoden, alle angehakt; Enter fügt die angehakten ein.

## Favoriten

Strg+D in der offenen Liste heftet den gewählten Eintrag an oder löst ihn. Das ist fest eingeschaltet (siehe
[Einstellungen](settings.md#fest-eingestellte-werte)).

- Ein Favorit gilt für ein Paar aus Typ und Member. Der Typ ist die deklarierende Klasse, auf Unit-Ebene die Unit.
  Ein Favorit `TDataSet.Open` gilt damit für jede Datenmenge.
- Höchstens 5 Favoriten je Typ. Ein weiterer ersetzt keinen; die Fußzeile meldet „Schon 5 Favoriten bei …“.
- Angeheftete Einträge stehen oben, wenn sie zum Getippten passen.
- dpcc speichert sofort in `%APPDATA%\dpcc\favorites.json`.
- Eine Liste der Favoriten auf der Optionsseite gibt es nicht mehr; gelöst wird mit Strg+D auf dem Eintrag.

## Übernehmen

Was beim Übernehmen passiert, ist größtenteils einstellbar (Abschnitt „Beim Übernehmen“, siehe
[Einstellungen](settings.md#beim-übernehmen)):

- **Klammern**: Bei Methoden ergänzt dpcc die Klammern. Tippt man direkt vor der automatisch eingefügten
  schließenden Klammer ein „)“, überspringt dpcc die automatische, statt „))“ zu erzeugen.
- **Schreibweise**: `showmessage` wird zu `ShowMessage` (fest eingeschaltet).
- **Unit in uses**: siehe „+ Unit“.
- **Commit-Zeichen**: „(“, „;“ und „.“ übernehmen.

## Parameterhilfe

Strg+Umschalt+Leertaste in einem Aufruf zeigt die Signaturen der aufgerufenen Routine an der öffnenden Klammer.

- Alle Überladungen stehen untereinander. In der gewählten ist der aktive Parameter fett und unterstrichen.
  Überladungen mit zu wenigen Parametern sind gedämpft.
- Vorgewählt ist die erste Überladung, zu der die bisherigen Argumente passen. Dafür zählen Literale, Namen und der
  Typ von Ausdrücken wie `Liefere(1)`, `Liste[i]` oder `A + 1`.
- Ein Klick wählt eine Überladung; Strg+Alt+↑ / Strg+Alt+↓ wechselt sie. Alt+↑ bleibt bei der IDE („Deklaration
  suchen“), die Pfeile allein bewegen den Cursor.
- Bei verschachtelten Aufrufen zeigt eine Pfadzeile oben die äußeren Aufrufe, etwa „ShowMessage › Format“.
- Darunter stehen Name und Beschreibung des aktiven Parameters aus der XMLDoc (ohne `<param>`: „nicht
  dokumentiert“), Standardwerte („optional, Standard …“) und die Beschreibung der Methode.
- Erlaubt keine Überladung so viele Argumente, steht dort „Keine Überladung mit n Parametern.“
- Ist die Vervollständigungsliste offen oder unten kein Platz, steht die Parameterhilfe über der Zeile.
- Esc schließt. Sie schließt auch, wenn der Cursor den Aufruf verlässt (auch durch „)“), bei Fokusverlust, Scrollen
  oder Wechsel des Reiters.
- Wird die schließende Klammer entfernt und steht der Cursor danach in einem Aufruf, erscheint die Hilfe erneut;
  nicht für einen Aufruf, dessen Hilfe mit Esc geschlossen wurde.

### Welche Aufrufe sie kennt

- **Geerbte Überladungen**: Trägt eine Methode der Ableitung `overload`, stehen die gleichnamigen Methoden der
  Vorfahren mit in der Liste (`TAbgeleitet.Add(const S: string)` und das geerbte `Add(A: Integer)`). Ohne
  `overload` verdeckt die Ableitung sie wie beim Compiler.
- **Prozedurtypen**: Aufrufe über Variablen, Felder, Properties und Parameter eines Prozedurtyps zeigen dessen
  Signatur, etwa `FOnChange(Self` (`TNotifyEvent`), `Callback(1` oder `AProc(` mit `AProc: TProc<Integer>`. Bei
  generischen Typen sind die Typargumente eingesetzt (`TProc<Integer> = reference to procedure (Arg1: Integer)`).
- **Typargumente vor der Klammer**: `Foo<Integer>(` zeigt nur die generische Überladung, mit eingesetztem
  Typargument.
- **Index-Properties**: `Liste.Items[` und `Liste[` (default-Property) zeigen die Indexparameter, mit
  Strg+Umschalt+Leertaste oder beim Komma. Steht die eckige Klammer in einem Aufruf (`Foo(Liste[`), bleibt es bei
  dessen Signaturen; bei einem Array statt einer Property erscheint nichts.

### Platzhalter von Format

Bei `Format` und anderen Formatroutinen nennt eine Zeile den Platzhalter zum Argument am Cursor, etwa „Platzhalter 2
von 2 erwartet ganzzahlig“. Sie warnt bei überzähligen Argumenten, ungültigen Platzhaltern und Typkonflikten mit
Literalen. Platzhalter und Argument bekommen im Editor dieselbe Hintergrundfarbe, solange die Parameterhilfe offen
ist. Das ist fest eingeschaltet und entfällt nur mit der ganzen Parameterhilfe („Parameter-Hint bei „(“ und „,““).

## Hover

Verweilt die Maus 500 ms über einem Bezeichner, zeigt dpcc darunter einen Tooltip. Die IDE wartet dabei nie auf
den Server.

Inhalt, von oben nach unten (leere Abschnitte entfallen):

| Abschnitt | Inhalt |
|---|---|
| Wert im Debugger | Ausdruck und Wert bei angehaltenem Programm, bis zur Antwort „wird ausgewertet …“ |
| Kopfzeile | Art und Signatur, auch mehrzeilig vollständig |
| Herkunft, Fundort | Art in Worten, Bibliothek, Herkunft; Datei und Zeile |
| Wert, Veraltung | Wert einer Konstante, auch aus einfachen Ausdrücken; `deprecated`, `platform`, `experimental`; nicht aktiver Zweig |
| XMLDoc | Zusammenfassung, Parameter, Rückgabe, Ausnahmen, Hinweise, Beispiel, Siehe auch; `<inheritdoc/>` wird aufgelöst; ohne `///` der normale Kommentar (siehe unten) |
| published-Mitglieder | bei Komponentenklassen Properties und Ereignisse samt geerbter |
| Vererbung | Vererbungskette bzw. Zieltyp einer Klassenreferenz |

Ist der Tooltip höher als der Platz oder als die eingestellte Zeilenzahl, scrollt die XMLDoc mit dem Mausrad.

Der Tooltip schließt 300 ms nachdem die Maus Bezeichner und Tooltip verlassen hat, sofort bei Esc und jeder anderen
Taste (außer Umschalt, Strg, Alt allein), bei Mausklick, Scrollen, Größenänderung und wenn die IDE inaktiv wird.
Ist eine Vervollständigungsliste, eine Parameterhilfe oder ein Menü offen, erscheint kein Tooltip.

Strg+Klick durch den Tooltip: Solange Strg gedrückt ist, gehen Maus und Klick durch den Tooltip an den Editor
darunter. Steht die Maus über dem Tooltip, schließt Strg ihn. So bleibt auch ein Wort, das der Tooltip verdeckt, mit
Strg+Klick erreichbar.

### Signatur, Kommentare und Werte

- **Signatur:** Zieht sich eine Deklaration über mehrere Zeilen, zeigt die Kopfzeile sie vollständig (Parameter,
  Ergebnis und Direktiven wie `virtual` oder `stdcall`) als eine Zeile ohne Kommentare. Bei Klassen, Records und
  Interfaces bleibt es bei der ersten Zeile. Sehr lange Köpfe kürzt dpcc nach 1000 Zeichen mit „…“.
- **Abgeleiteter Typ:** Bei Inline-Variablen ohne Typangabe (`var X := TFoo.Create;`, `for var I := 0 to …`) setzt
  dpcc den Typ ein, der aus dem Ausdruck folgt: `var X: TFoo := TFoo.Create;`. Lässt sich der Typ nicht sicher
  bestimmen, bleibt die Zeile wie im Quelltext.
- **Kommentare als Doku:** XMLDoc mit `///` hat Vorrang. Ohne sie zeigt dpcc den normalen Kommentarblock direkt über
  der Deklaration (`//`, `{ }` oder `(* *)`, ohne Leerzeile dazwischen) und den Kommentar am Ende der Zeile mit dem
  Namen. Nicht als Doku gelten Datei- und Lizenzköpfe (Block am Dateianfang oder mit Wörtern wie Copyright, License,
  Lizenz), Blöcke hinter einer Leerzeile, Trennlinien wie `//-----`, ein einzelner Name wie `{ TFoo }` und
  auskommentierter Code (Zeilen mit `:=`, auf `;` endende Anweisungen, `begin`/`end` …); besteht ein Block
  überwiegend aus Code, entfällt er ganz. Den Kommentar am Zeilenende zeigt die Kopfzeile nicht mehr.
- **Werte:** Konstanten zeigen ihren Wert auch bei einfachen Ausdrücken: Ganzzahlen mit
  `+ - * div mod and or xor not shl shr`, Vorzeichen und Klammern, Texte mit `+` und Verweise auf andere Konstanten
  der Unit oder aus dem Index (`cMax = cBase * 2`). Was dpcc nicht sicher berechnen kann (Gleitkomma, Funktionen wie
  `High` oder `Ord`, Vergleiche, Kreise), zeigt keinen Wert.
- **Nicht aktive Zweige:** Über einer Deklaration in einem Zweig, der unter der aktuellen Konfiguration nicht gilt
  (`{$IFDEF …}`), zeigt der Hover ihren Kopf und Kommentar aus der Datei mit dem Hinweis „Nicht aktiv“ und der
  Bedingung.

Kommentare stehen nicht im Index; der Hover liest sie bei Bedarf aus der einen Datei der Deklaration.

### Werte beim Debuggen

Ist das Programm angehalten und die Einstellung „Werte beim Debuggen zeigen“ an, wertet dpcc den Ausdruck unter
der Maus über den Debugger der IDE aus. Die Auswertung ruft nichts im Programm auf. Der Wert steht ganz oben.

### Help Insight

Solange der Tooltip von dpcc an ist, schaltet dpcc Help Insight der IDE ab, damit nicht zwei Tooltips erscheinen.
Details unter [Einstellungen](settings.md#was-dpcc-an-der-ide-umstellt).

## Sprache

Die Texte von dpcc sind deutsch, wenn die IDE deutsch ist, sonst englisch. Bezeichner, Signaturen und XMLDoc werden
nie übersetzt.
