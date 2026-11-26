[Deutsch](../de/troubleshooting.md) | English | [Français](../fr/troubleshooting.md)

# Troubleshooting

[Overview](index.md) › Troubleshooting

## The plugin does not load

Typical: at startup or during installation, the IDE reports that a package cannot be loaded.

The cause is almost always the PATH. `dpcc.Plugin370.bpl` needs seven more BPLs, and Windows looks for them only
via the PATH.

1. Close the IDE.
2. Run `powershell -NoProfile -File Tools\IdePath.ps1` and read the output. The output is always in German; the
   last line is the result. “…” stands for the BPL folder, 37.0 is the BDS version of Delphi 13 (parameter
   `-BdsVersion`; for Delphi 12 `-BdsVersion 23.0`, then the message names the group dpcc_d12 and the folder
   `Output\Win32\D12\…`):
   - “FEHLT: BPL-Ordner oder BPLs fehlen (…) - erst die Gruppe dpcc_d13 bauen.” (MISSING: BPL folder or BPLs
     missing (…) - build the group dpcc_d13 first; exit code 2): The group has not been built completely. The list
     above shows the missing BPL with “[fehlt]” (missing). Build all projects.
   - “FEHLT: … steht nicht in der PATH-Ueberschreibung der IDE 37.0. Abhilfe: -Action Add” (MISSING: … is not in
     the PATH override of IDE 37.0. Fix: -Action Add; exit code 1): run `-Action Add`.
   - “OK: … steht in der PATH-Ueberschreibung der IDE 37.0, alle BPLs vorhanden.” (OK: … is in the PATH override
     of IDE 37.0, all BPLs present; exit code 0): PATH and BPLs are fine.
   - If the output above contains “Hinweis  : n Delphi-Instanz(en) laufen - Aenderungen wirken erst nach einem
     Neustart.” (Note: n Delphi instance(s) running - changes take effect only after a restart), an IDE is still
     running. Close it.
3. Restart the IDE.

Other causes:

- The PATH entry is in the Windows PATH instead of the IDE's PATH override. See
  [Installation](installation.md#setting-the-ide-path).
- One BPL is older than the others, for example after an aborted build. `Tools\IdePath.ps1` shows the date of each
  BPL. Rebuild the whole group.
- The build was not for Win32. The IDE loads only Win32 packages.

## Is dpcc loaded?

- The splash screen and the About box show “dpcc 0.1.0”.
- **Tools › Options › Third Party** shows the **dpcc** node.
- The log contains “dpcc angemeldet (Code Completion)” (dpcc registered).

## Ctrl+Space shows the IDE's list instead of the dpcc list

dpcc passes the key on to the IDE if it does not serve the file:

| Cause | Fix |
|---|---|
| The file does not end in `.pas`, `.dpr`, `.dpk` or `.inc`. | Expected. |
| The master switch is off. | **Tools › Options › Third Party › dpcc**, turn on “Code Insight by dpcc”. |
| The safety fuse has switched off completion. | The Messages window reports this (see below). Restart the IDE. |
| The dpcc list stayed empty, and Ctrl+Space was pressed a second time at the same position. | Expected, see [Usage](usage.md#ide-list-when-dpcc-finds-nothing). After typing or at another position, Ctrl+Space asks dpcc again. |

## No list opens after the dot

Usually “Code completion” is off in the IDE's Code Insight options (registry value `Auto Code Completions` =
`False`). Then neither the IDE's list nor the dpcc list opens after “.”. A second possible reason: “Auto invoke” is off
(`Auto Invoke` = `False`); then the IDE does not invoke code completion after “.” by itself.

- dpcc mode: dpcc sets both values to `True` itself when Delphi starts; takes effect after the next start.
- IDE mode (DelphiLSP selected): dpcc only reports the difference, in the log (“IDE-Einstellungen: 1 Abweichung: Auto
  Code Completions”) and on the dpcc page in the **IDE** section. Switch on “Code completion” and “Auto invoke” in the
  IDE's Code Insight options.

Locations and expected values for Delphi 12 and 13: [Settings](settings.md#what-dpcc-changes-in-the-ide).

## The list after “.” looks different from the one with Ctrl+Space

Expected after switching dpcc on until Delphi is restarted: the list that opens by itself after “.” still comes from
the previous provider (DelphiLSP). After the restart dpcc is the provider. See
[Usage](usage.md#interaction-with-delphilsp).

## The list is empty or incomplete

- “limited (index is being built)”: The index is not finished yet. Wait.
- Warning bar “syntax error in line n”: There is a syntax error before the cursor. A click on the underlined line
  reference closes the list and puts the cursor at the error.
- A unit is missing: If it is in no project, no search path and no library path, dpcc does not know it. See
  [Index and cache](index-cache.md#what-the-index-contains).
- A unit is missing although its file is in the search path: search `dpcc.log` for “Datei nicht lesbar” (file not
  readable). The index skips a file that cannot be read or parsed.
- The index seems outdated: **Rebuild index** on the **dpcc** page (section **Index**).
- If dpcc finds nothing at a position, a second Ctrl+Space there opens the IDE list (see
  [Usage](usage.md#ide-list-when-dpcc-finds-nothing)).

## There are no suggestions for DUnitX

DUnitX, DUnit and FireDAC come with the installation only as `.dcu`. Without source code dpcc knows their types from
the packages the IDE has loaded, and their members only once a project names the unit in its `uses`. Constants and
routines outside of types are then missing.

- If the source code is available (for example a clone of DUnitX), enter its folder on the **dpcc** page under
  “Additional source folders”. After that “+ Unit” suggests for example `TestFixtureAttribute` and `Assert`. See
  [Index and cache](index-cache.md#additional-source-folders).
- A reference such as `$(DUnitX)` in a search path only works if the variable is among the environment variables of
  the IDE or the system. Otherwise `dpcc.log` names the path (“… mit unaufgelöstem Verweis übergangen”, skipped with
  unresolved reference).

## Ctrl+click does not jump

Ctrl+click and “Find Declaration” (Alt+↑) go to the Code Insight provider selected in the IDE options. Only if dpcc
is selected there does dpcc jump (see [Usage](usage.md#when-dpcc-is-selected-as-the-provider)).

| Cause | Remedy |
|---|---|
| The target is in a unit without source (known only from a package). Message “unit X is only available as a package”. | Expected: no jump. If the source is available, add its folder under “Additional source folders”. |
| dpcc does not find the unit or cannot resolve the name uniquely (ambiguous overload, `with` with an unknown type). Message “unit X not found” or “"Name" could not be resolved”. | Expected. Check the search paths; see [The list is empty or incomplete](#the-list-is-empty-or-incomplete). |
| The index is still being built (“No jump: the index is still being built. Please click again in a moment.”, for other reasons the addition “The index is still being built.”; dpcc then does not jump later), dpcc is still starting or the answer took longer than 10 seconds (“no answer from dpcc within 10 s”). After 250 ms dpcc jumps by itself, but only until then and only while the cursor stays in the same identifier. | Wait and try again. |
| No message in the Messages window. | `dpcc.log` records every jump without a target in one line `Gehe zu Definition: <outcome> nach <n> ms, <file> <line>:<column> (Maus\|Cursor)` (log lines are not translated), including discarded late answers (“Cursor bewegt”, “andere Datei aktiv”, “neuerer Sprungwunsch”, “zu spät”). |
| Ctrl+click on a use jumps to the declaration, but Ctrl+click on the declaration does not jump to the implementation. | Switch on “Log the flow (log file)”, repeat the jump and send the chain (see [Flow log](#flow-log)): it shows the verdict of `OnTarget` and whether `definition` was asked. |
| A dpcc parameter hint with several overloads is open. | Since this version, Ctrl+Alt+↑/↓ switches the overload there; Alt+↑ goes to the IDE. |
| The dpcc tooltip covers the word. | Hold down Ctrl: mouse and click then go through the tooltip to the editor. |

### Jumping into another package

If a package requires another one (`requires`), dpcc looks for its source `<Name>.dpk` and adds the units of its
`contains` to the project's index. It searches the folders of all reported projects of the group (including those still
loading), the project folder, the search paths, the
[additional source folders](index-cache.md#additional-source-folders) and the folders next to the project folder
(`Packages\<Name>\<Name>.dpk`, one level). The other package does not have to be a project of the group. If a package
project joins the group later, the existing packages reload. If only the compiled package (`.dcp`, BPL) exists, there
is no target; if the source is elsewhere, add its folder under “Additional source folders”.

If dpcc finds no target, the server reports the reason (`dpcc/noTarget`) before the empty answer: `noDocument` (file
unknown to the server), `noIdentifier` (no identifier at the position), `unresolved` (name not resolved),
`unitNotFound` (unit from `uses` not found), `noSource` (unit only available as a package without source),
`inactiveBranch` (inactive `$IFDEF` branch), `other`; plus whether the index is still being built. The server
diagnostic log shows the same reason in the request line (`empty:unitNotFound` …, the name only as a code `name=h…`),
preceded by a line `declaration start` or `definition start`.

## Two tooltips appear

- The IDE reads its switches only at its next start. dpcc switches off Help Insight, tooltip symbol insight and,
  while debugging, tooltip expression evaluation as soon as it is the Code Insight provider. Restart Delphi.
- In addition, dpcc hides the IDE's Help Insight window (for example “TQRCustomBand Type”) at runtime as soon as it
  appears: always with the own tooltip on, otherwise while dpcc's list is open. No restart is needed for this, also
  under Delphi 12, where the registry value alone does not reliably take effect. With dpcc off, the IDE's window
  stays. The log has “Help Insight der IDE: Fenster THelpInsightWindow verborgen …” at the first hide and
  “Help Insight in der Registry (…)” with the values read at startup.
- The dpcc page shows the state in the **IDE** section (“Check now”).
- If you want to keep the IDE's tooltip, switch off “Own tooltip when hovering identifiers” or “Show values while
  debugging”.

## Help Insight is missing after uninstalling

dpcc hands back the provider and the IDE switches only while it is loaded. If it was removed without first turning
off the master switch and restarting Delphi, select DelphiLSP in the IDE's Code Insight options and switch Help
Insight, tooltip symbol insight and tooltip expression evaluation back on. The registry values are listed under
[Settings](settings.md#what-dpcc-changes-in-the-ide).

## Messages in the Messages window

dpcc writes warnings to the IDE's Messages window and to the log. It shows a dialog on its own in one case only: the
server has crashed twice with the same cause within 10 minutes, and dpcc no longer restarts it on its own (see
[The server has crashed](#the-server-has-crashed)).

| Message | Meaning |
|---|---|
| “dpcc: Server crashed repeatedly – The server ended twice with … within 10 minutes. dpcc no longer restarts it on its own …” | The server stays stopped until it is restarted manually. The prompt “Restart server?” appears for this. |
| “dpcc: … switched off after 3 errors in 5 minutes (last: …) until the IDE is restarted.” | The safety fuse has switched off a feature. It stays off until the IDE is restarted. Errors in dpcc never reach the IDE. |
| “dpcc: source "…" switched off after 3 errors in 5 minutes …” | Only this data source is off; the others keep running. |
| “dpcc: dpcc switched the IDE's Code Insight provider to dpcc; takes effect after restarting Delphi.” | After master switch on and OK, once per session. Until the restart the IDE calls the previous provider. See [Settings](settings.md#what-dpcc-changes-in-the-ide). |
| “dpcc: dpcc switched the IDE's Code Insight provider back to …; takes effect after restarting Delphi …” | After master switch off and OK, once per session. |
| “dpcc: The Code Insight provider is no longer dpcc …; dpcc is off …” | At startup: dpcc had set itself as the provider, but the IDE started with another one (changed in the IDE options or written back by the IDE). To turn dpcc on, set the master switch again. |
| “dpcc is selected as the Code Insight provider for Delphi in the IDE options …” | Once per session if dpcc is the selected provider: Ctrl+click goes through dpcc, Error Insight and the other DelphiLSP services are missing. See [Usage](usage.md#when-dpcc-is-selected-as-the-provider). |

## The server has crashed

- If the server ends unexpectedly, dpcc restarts it and sends the open files again.
- If it ends twice with the same cause within 10 minutes, dpcc no longer restarts it on its own, so the error does
  not recur in a loop. The Messages window reports this (“Server crashed repeatedly”), and dpcc asks “Restart
  server?”. With **Yes** it restarts, and the count starts over. With **No** it stays stopped until the IDE is
  restarted.
- The cause is in the log.

## The IDE crashes with a stack overflow in clr.dll

Symptom: the IDE terminates with a stack overflow; the crash dump shows `clr.dll` and a background thread of the IDE
(such as Error Insight) calling .NET code. In one case that was examined, the floating-point setting was the reason:
the “Invalid” exception was unmasked in the x87 control word, and `System.Default8087CW` of the shared RTL was `$137A`
instead of `$033F` (the Delphi RTL default, all exceptions masked). The dump does not show who changed it (the IDE, an
expert, a package).

dpcc never changes this setting. It only reads it and writes these lines to `dpcc.log` (log lines are always in
German):

| Line | Meaning |
|---|---|
| `Gleitkomma beim Start: Vorgabe $033F (alle maskiert); Hauptthread $033F (alle maskiert); MXCSR Vorgabe $1F80, Hauptthread $1F80` | State when dpcc registers: the process default (“Vorgabe”) and the main thread's control word (“Hauptthread”) with the unmasked exceptions (“nicht maskiert: …”, or “alle maskiert” = all masked), plus the SSE setting (MXCSR) as hex only. |
| `Gleitkomma geändert nach 95 s (Meldung 1 von höchstens 20): Vorgabe $033F (alle maskiert) → $137A (nicht maskiert: Invalid, ZeroDivide); Hauptthread unverändert $033F (alle maskiert)` | Something changed the setting after dpcc registered (seconds since then); old → new value, separately for the default and the main thread. “Masken gleich” means only precision or rounding differ. |

The check runs on the main-thread watchdog's cycle (about every 50 ms, two reads). A line is written only when
something changed, at most 20 per session; the last one ends with “weitere Änderungen werden nicht mehr gemeldet” (no
further changes will be reported). With the [flow log](#flow-log) switched on, the change line also goes there.

If one of these lines says “nicht maskiert: Invalid”:

1. Compare the time of the change line with what happened at that moment (package loaded, project opened, tests
   started).
2. Switch off other experts and design packages (such as TestInsight) for a test, restart the IDE and look at the
   start line again. If everything stays at `$033F (alle maskiert)`, the change comes from one of those switched off.
3. Pass the lines together with the crash dump to the maker of that expert or to Embarcadero.

## Logs

### dpcc.log

| | |
|---|---|
| Location | `%LOCALAPPDATA%\dpcc\Logs\dpcc.log` |
| Older files | `dpcc.1.log` to `dpcc.4.log`; at most 5 files of 1 MB each |
| Contents | startup and unloading, selected Code Insight provider, language, errors with version, feature, error class, message and call stack |
| Never contained | source code from the editor |

Names and paths are made unrecognizable in the log. dpcc writes real names only if the DWORD value `LogNames` = 1 is
set under `HKCU\Software\dpcc\IdePlugin`. The log is then no longer anonymous; check it before passing it on.

Several IDE instances share the folder; a lock prevents them from interfering with each other.

### Flow log

For detailed troubleshooting, dpcc writes the flow of every action to a log of its own (formerly “diagnostic log”):
for Ctrl+click or “Find Declaration”, completion, hover and parameter hints one line per step, from the IDE's call to
the result. All lines of one action carry the same ID (`#12 Sprung: …`, `#13 Vervollständigung: …`; the log lines
are in German); the last line of a chain says where and why it ends. As before, the log also contains the IDE's other
calls to the Code Insight manager.

To switch it on:

1. **Tools › Options › Third Party › dpcc**, section **IDE**: check “Log the flow (log file)” and confirm with OK.
   This takes effect immediately, without a restart. The Messages window (group dpcc) names the file (“dpcc: The flow
   is logged to …”), so does the hint on the check box.
2. Or by hand as before: create the DWORD value `Diagnose` = 1 under `HKCU\Software\dpcc\IdePlugin` and restart the
   IDE. It is the same value; the page shows it as checked.

| | |
|---|---|
| Location | next to the plugin BPL: `dpcc.IDE.Expert290.log` (Delphi 12) or `dpcc.IDE.Expert370.log` (Delphi 13), for example `Output\Win32\Debug\Bpl\dpcc.IDE.Expert370.log` |
| Older files | `dpcc.IDE.Expert370.1.log` to `….4.log`; at most 5 files of 1 MB each |
| Contents | one line per step with the time: the IDE's entry point, every early exit with its reason, the server's answers, the result returned to the IDE. Files only by name, positions as line:column |
| Never contained | folders and the user name (replaced), source code except the one word at the position |

Example: Ctrl+click on the name of a method in the class (line 12), jump to the implementation (line 40):

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

If the declaration does not jump, the chain shows the step where it stops: `OnTarget nein (Datei verschieden …)` with
“definition nicht gefragt” (the IDE and the server spell the file differently), `definition: leer`, or a `definition`
that points back to the declaration, and finally `gleich der Ausgangsstelle: ja (die IDE bleibt in derselben Zeile)`
(the IDE stays on the same line). Whether the server found a pair of declaration and implementation is in the
[server diagnostic log](#server-diagnostic-log), in the `declaration` or `definition` line at the same time:
`pair=found pairChosen=implementation` or `pair=none:<reason>` with `pairSame` (places of the routine) and
`pairVariant` (of those, with matching parameter types). Reasons: `noUnit` (unit of the target not in the index),
`noSymbol` (routine not found there), `single` (only one place, no second half), `params` (several places, but the
parameter types do not match).

What to send:

1. Switch on “Log the flow (log file)” (OK).
2. Perform the action once, for example Ctrl+click on the declaration.
3. Send the lines with this ID from the flow log, plus `dpcc.log` and the server diagnostic log of the same day.
   Look at them before passing them on: file names and the word at the position are in plain text.
4. Switch it off again.

To switch it off: uncheck and OK (immediately) or delete the registry value or set it to 0. Measuring the slowest
calls on unload and the hangs without a dpcc action (see below) follow the switch only after the next IDE start.

### Hangs and slow actions

A watchdog checks every 50 ms whether the IDE's main thread responds. Together with the times of dpcc actions it
writes these lines to `dpcc.log` (the log itself is in German):

| Line | Meaning |
|---|---|
| `Hauptthread hängt seit 260 ms in Vervollständigung öffnen` | The IDE has not responded for 250 ms or more while dpcc runs this action. Written immediately, even if the IDE never recovers. |
| `Hauptthread hing 1300 ms in Vervollständigung öffnen` | The IDE responds again; total duration of the hang. |
| `Hauptthread: Symbolhinweis: 87 ms` | A dpcc action held up the IDE for 50 ms or more without a hang. |
| `Hauptthread wartete 340 ms auf Server textDocument/completion: Zeitlimit` | The IDE waited 100 ms or more for the server; outcome: `Antwort` (answer), `Zeitlimit` (timeout), `abgebrochen` (cancelled) or `Fehler` (error). |
| `Hänger mit dpcc-Aktivität in dieser Sitzung: 3, längster 1300 ms, …` | Summary on unload if there were hangs. |

The lines are throttled: at most one line per action and minute (`dazu n weitere …` counts the skipped ones), at most
5 hangs per minute individually (`… nicht einzeln protokolliert, zusammen n ms`). If the IDE hangs without a dpcc
action (for example while compiling), dpcc writes nothing. Modal dialogs do not count as hangs, nor does time in which
the IDE was stopped in a debugger.

With `Diagnose` = 1 or “Log the flow (log file)” at IDE start (see above), hangs without a dpcc action also appear in
the flow log as `… ohne dpcc-Aktivität`, and on unload it lists the 10 slowest calls, server requests and completion
queries.

### Server diagnostic log

The server writes an anonymous log of its requests and index builds to
`%LOCALAPPDATA%\dpcc\Logs\Diagnose\diag-<date>-<process>.log`, one file per day and process, kept for 7 days
(`diagnostics.log`, `diagnostics.logDays` in `settings.json`).

It reports the memory of the IDE process in “mem” lines: at the start and at the end of every index build and at least
every 10 minutes, as soon as a request ends. Example:

```
14:02:10.521 mem indexDone private 104 MB peak 127 MB ws 118 MB free 2003 MB index 56 MB units 2027 lib 1481 docs 0 trees 0 0 MB dcp 4 27 kb loaded 703 pinned 701 evictable 2 1 MB cold 1324 catalog 13 MB loads 15 evicted 0 loadms 0.2 max 3.6
```

| Field | Meaning |
|---|---|
| `indexStart`, `indexDone`, `periodic` | occasion: start or end of a build, regular line |
| `private` | private bytes of the whole IDE process (committed private memory) |
| `peak` | highest value of `private` since the IDE started |
| `ws` | working set (memory in RAM; drops when paged out, `private` does not) |
| `free` | largest contiguous free region of the address space; if it gets small, “Out of memory” looms despite free RAM |
| `index` | estimated memory of the symbol index: loaded units and catalog |
| `units`, `lib` | units in the index, of which from the library |
| `docs` | documents open at the server |
| `trees` | syntax trees and their estimated memory |
| `dcp` | remembered compiled packages (`.dcp`) and their names in KB |
| `loaded`, `pinned`, `evictable` | units with all symbols in memory; of which pinned (never released) and releasable, with their memory (limit 32 MB). See [Library on demand](index-cache.md#library-on-demand) |
| `cold` | units only in the catalog |
| `catalog` | estimated memory of the catalog of all units |
| `loads`, `evicted` | units loaded on demand and released again since the server started |
| `loadms`, `max` | duration of loading on demand in ms: median of the recent loads and maximum |

“run start … mem n MB” and the “index … mem n MB” lines also give the private bytes of the process.

## The IDE uses a lot of memory

- The “mem” lines of the server diagnostic log show how much of it is due to the index (see above).
- Of the library, the index keeps only the units the projects reach or often need permanently in memory; it loads the
  others on demand and releases them again. See [Index and cache](index-cache.md#library-on-demand).
- The Office type libraries and WinRT stay in memory only with their catalog; dpcc loads their symbols on demand. See
  [Index and cache](index-cache.md#office-type-libraries-and-winrt).
- Only the 16 most recently used files keep their syntax tree in the server; for older ones it builds the tree again on
  the next access. When the IDE closes a file, dpcc releases it in the server.
- A file outside the project group gets a workspace of its own. It goes away again when the last of its files is
  closed.
- When the server ends (master switch off, restart), dpcc releases the whole index. If requests are still running and
  do not end in time, the release follows as soon as they are done.

## Settings back to default

- One option: set it back to the default by hand on the **dpcc** page; the defaults are listed under
  [Settings](settings.md).
- Everything: see [Settings](settings.md#storage).
