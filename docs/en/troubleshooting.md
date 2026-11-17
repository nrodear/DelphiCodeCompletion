[Deutsch](../de/troubleshooting.md) | English | [Français](../fr/troubleshooting.md)

# Troubleshooting

[Overview](index.md) › Troubleshooting

## The plugin does not load

Typical: at startup or during installation, the IDE reports that a package cannot be loaded.

The cause is almost always the PATH. `dpcc.IDE.Base370.bpl` needs seven more BPLs, and Windows looks for them only
via the PATH.

1. Close the IDE.
2. Run `powershell -NoProfile -File Tools\IdePath.ps1` and read the output. The output is always in German; the
   last line is the result. “…” stands for the BPL folder, 37.0 is the BDS version of Delphi 13 (parameter
   `-BdsVersion`):
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
| The master switch is off. | **Tools › Options › Third Party › dpcc › General**, turn on “Code Insight by dpcc”. |
| The safety fuse has switched off completion. | The Messages window reports this (see below). Restart the IDE. |
| The dpcc list stayed empty, and Ctrl+Space was pressed a second time at the same position. | Expected, see [Usage](usage.md#ide-list-when-dpcc-finds-nothing). After typing or at another position, Ctrl+Space asks dpcc again. |

## The list after “.” looks different from the one with Ctrl+Space

This is expected. The list that opens by itself after “.” comes from DelphiLSP. See
[Usage](usage.md#interaction-with-delphilsp).

## The list is empty or incomplete

- “limited (index is being built)”: The index is not finished yet. Wait.
- Warning bar “syntax error in line n”: There is a syntax error before the cursor. A click on the underlined line
  reference closes the list and puts the cursor at the error.
- A unit is missing: If it is in no project, no search path and no library path, dpcc does not know it. See
  [Index and cache](index-cache.md#what-the-index-contains).
- A unit is missing although its file is in the search path: search `dpcc.log` for “Datei nicht lesbar” (file not
  readable). The index skips a file that cannot be read or parsed.
- The index seems outdated: **Rebuild index** on the **General** page.
- If dpcc finds nothing at a position, a second Ctrl+Space there opens the IDE list (see
  [Usage](usage.md#ide-list-when-dpcc-finds-nothing)).

## There are no suggestions for DUnitX

DUnitX, DUnit and FireDAC come with the installation only as `.dcu`. Without source code dpcc knows their types from
the packages the IDE has loaded, and their members only once a project names the unit in its `uses`. Constants and
routines outside of types are then missing.

- If the source code is available (for example a clone of DUnitX), enter its folder on the **General** page under
  “Additional source folders”. After that “+ Unit” suggests for example `TestFixtureAttribute` and `Assert`. See
  [Index and cache](index-cache.md#additional-source-folders).
- A reference such as `$(DUnitX)` in a search path only works if the variable is among the environment variables of
  the IDE or the system. Otherwise `dpcc.log` names the path (“… mit unaufgelöstem Verweis übergangen”, skipped with
  unresolved reference).

## Two tooltips appear

- The IDE's Help Insight: dpcc switches it off, but the IDE reads the switch only at its next start. Restart the IDE.
- The IDE's value tooltip while debugging: dpcc switches it off only when the dpcc page is closed with **OK**. Open
  the page once, OK, restart the IDE.
- If you want to keep the IDE's tooltip, switch off “Own tooltip when hovering identifiers” or “Values in the hover
  while debugging”.

## Help Insight is missing after uninstalling

dpcc hands Help Insight and the value tooltip back only while it is loaded. If it was removed without first turning
off the master switch, switch both back on in the IDE's Code Insight options. The registry values are listed under
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
| “dpcc shows the tooltip itself and switched off the IDE's Help Insight …” | see “Two tooltips appear” |

## The server has crashed

- If the server ends unexpectedly, dpcc restarts it and sends the open files again.
- If it ends twice with the same cause within 10 minutes, dpcc no longer restarts it on its own, so the error does
  not recur in a loop. The Messages window reports this (“Server crashed repeatedly”), and dpcc asks “Restart
  server?”. With **Yes** it restarts, and the count starts over. With **No** it stays stopped until the IDE is
  restarted.
- The cause is in the log.

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

### Diagnostic log

For detailed troubleshooting, dpcc logs the IDE's calls to its Code Insight manager:

1. Create the DWORD value `Diagnose` = 1 under `HKCU\Software\dpcc\IdePlugin`.
2. Restart the IDE.
3. The log is next to the plugin BPL: `Output\Win32\Debug\Bpl\dpcc.IDE.Expert370.log`.

Paths and the user name are replaced in it. To switch it off, delete the value or set it to 0.

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

- One option: right-click, “Reset to default”.
- One area: right-click, “Reset the whole page to default”.
- Everything: see [Settings](settings.md#storage).
