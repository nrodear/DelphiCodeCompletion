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

## The list after “.” looks different from the one with Ctrl+Space

This is expected. The list that opens by itself after “.” comes from DelphiLSP. See
[Usage](usage.md#interaction-with-delphilsp).

## The list is empty or incomplete

- “limited (index is being built)”: The index is not finished yet. Wait.
- Warning bar “syntax error in line n”: There is a syntax error before the cursor. A click on the underlined line
  reference closes the list and puts the cursor at the error.
- A unit is missing: If it is in no project, no search path and no library path, dpcc does not know it. See
  [Index and cache](index-cache.md#what-the-index-contains).
- The index seems outdated: **Rebuild index** on the **General** page.

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

## Settings back to default

- One option: right-click, “Reset to default”.
- One area: right-click, “Reset the whole page to default”.
- Everything: see [Settings](settings.md#storage).
