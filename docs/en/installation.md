[Deutsch](../de/installation.md) | English | [Français](../fr/installation.md)

# Installation

[Overview](index.md) › Installation

## Requirements

- Delphi 13 / RAD Studio 37.0. For Delphi 12 / RAD Studio 23.0 see [Building for Delphi 12](#building-for-delphi-12).
- Win32 platform. The IDE is a 32-bit process, so the plugin is a Win32 package.
- The dpcc source code. There are no prebuilt BPLs; dpcc is built from the project group.

## Building

1. Open `dpcc_d13.groupproj` in the IDE.
2. Platform Win32, configuration Debug.
3. Build all projects in the group. The order follows from the dependencies of the group.

The output is in `Output\Win32\Debug`:

| Folder | Contents |
|---|---|
| `Bpl` | the eight BPLs with the suffix `370` (package version of Delphi 13), including the plugin `dpcc.IDE.Base370.bpl` |
| `Dcp` | the DCP files of the packages |
| `Dcu` | the DCUs, one subfolder per project |
| `Bin` | the test program `dpcc.Completion.Tests.exe` |

The command-line compiler (`dcc32`, MSBuild) is locked in the Community and Starter editions; build in the IDE there.
More on this under [Development](development.md).

### Building for Delphi 12

For Delphi 12 (RAD Studio 23.0) there is the group `dpcc_d12.groupproj` with the same eight packages, without the
test program: the tests run only under Delphi 13.

1. Open `dpcc_d12.groupproj` in the Delphi 12 IDE.
2. Platform Win32, configuration Debug.
3. Build all projects in the group.

The packages detect Delphi 12 themselves (by `rtl290.bpl` in `$(BDS)\bin`) and build into a folder of their own,
so the files of the two versions do not overwrite each other.

| | Delphi 13 | Delphi 12 |
|---|---|---|
| Group | `dpcc_d13.groupproj` | `dpcc_d12.groupproj` |
| Output | `Output\Win32\Debug` | `Output\290\Win32\Debug` |
| Plugin | `dpcc.IDE.Base370.bpl` | `dpcc.IDE.Base290.bpl` |
| Other BPLs | `dpcc.Text370.bpl` … `dpcc.UI370.bpl` | `dpcc.Text290.bpl` … `dpcc.UI290.bpl` |
| IDE PATH | `…\Output\Win32\Debug\Bpl` | `…\Output\290\Win32\Debug\Bpl` |
| IDE registry | `HKCU\Software\Embarcadero\BDS\37.0` | `HKCU\Software\Embarcadero\BDS\23.0` |
| `Tools\IdePath.ps1` | without `-BdsVersion` | `-BdsVersion 23.0` |
| Tests | yes | no |

Install and set the PATH as below, only with the names and folders from the Delphi 12 column: in the Delphi 12
IDE, add `Output\290\Win32\Debug\Bpl\dpcc.IDE.Base290.bpl` (the IDE enters it under
`HKCU\Software\Embarcadero\BDS\23.0\Known Packages`) and put `…\Output\290\Win32\Debug\Bpl` into the PATH of
the Delphi 12 IDE.

## Installing

1. In the IDE, open **Component › Install Packages…**.
2. Choose **Add…** and open `Output\Win32\Debug\Bpl\dpcc.IDE.Base370.bpl`.
3. The IDE shows the package with the description “dpcc (Code Insight-Manager)”.

Only `dpcc.IDE.Base370.bpl` is installed. At run time it needs seven more BPLs (under Delphi 12 with the suffix
`290` instead of `370`):

| BPL | Purpose |
|---|---|
| `dpcc.Text370.bpl` | text helpers, RTL only |
| `dpcc.WinBase370.bpl` | RTL and Windows API |
| `dpcc.Common370.bpl` | parser, index, LSP parts, without Windows and VCL |
| `dpcc.Windows370.bpl` | Windows-specific parts, without VCL |
| `dpcc.Server370.bpl` | the completion server, runs in the IDE process |
| `dpcc.Core370.bpl` | plugin logic, without VCL and ToolsAPI |
| `dpcc.UI370.bpl` | VCL user interface of the plugin |

The IDE loads these BPLs along with the plugin. However, Windows does not look for them in the folder of the plugin
BPL but via the PATH. The folder `Output\Win32\Debug\Bpl` must therefore be in the IDE's PATH.

## Setting the IDE PATH

The entry belongs in the IDE's PATH override, not in the Windows PATH. The IDE stores the override in the registry
under `HKCU\Software\Embarcadero\BDS\37.0\Environment Variables`, value `PATH`.

Example, if the repo is in `D:\src\DelphiCodeCompletion`:

```
D:\src\DelphiCodeCompletion\Output\Win32\Debug\Bpl;$(PATH)
```

### Manually in the IDE

1. Open **Tools › Options › IDE › Environment Variables**.
2. Under **User overrides**, click **New…** or edit an existing `PATH` entry.
3. Variable `PATH`. Value: the BPL folder first, followed by `;$(PATH)`. An existing value is kept; the BPL folder
   is only prepended.
4. Close with OK and restart the IDE.

### With the script

`Tools\IdePath.ps1` checks and sets the same entry. Run it from the repo folder. Close the IDE first; changes take
effect only at the next start of the IDE.

```powershell
powershell -NoProfile -File Tools\IdePath.ps1                 # show status
powershell -NoProfile -File Tools\IdePath.ps1 -Action Add     # add the BPL folder
powershell -NoProfile -File Tools\IdePath.ps1 -Action Remove  # remove the entry again
```

| Action | Effect |
|---|---|
| `Status` (default) | Shows the PATH value, the BPL folder, each expected BPL with its date, the installed dpcc packages (Known Packages) and running IDE instances. Changes nothing. |
| `Check` | Like `Status`, but only the result line. For scripts. |
| `Add` | Adds the BPL folder: before `$(PATH)` if the value contains `$(PATH)`, otherwise at the end; without a value as `<folder>;$(PATH)`. Backs up the previous value under `HKCU\Software\dpcc\IdePlugin`, value `PathOverrideBackup`. |
| `Remove` | Removes the BPL folder from the PATH value. Other parts of the value stay. It does not restore the backup. |

| Parameter | Default | Meaning |
|---|---|---|
| `-Action` | `Status` | `Status`, `Check`, `Add` or `Remove` |
| `-BdsVersion` | `37.0` | IDE version in the registry; `23.0` for Delphi 12 |
| `-BplDir` | `Output\Win32\Debug\Bpl` in the repo, with `-BdsVersion 23.0` `Output\290\Win32\Debug\Bpl` | a different BPL folder |

Exit code of `Status` and `Check`:

| Code | Meaning |
|---|---|
| 0 | entry present, all BPLs there |
| 1 | entry missing; fix with `-Action Add` |
| 2 | BPL folder or BPLs missing; build the group first |

## Checking that dpcc is loaded

- The IDE's splash screen and About box show “dpcc 0.1.0” (text only, no image).
- Under **Tools › Options › Third Party** there is a **dpcc** node.
- The log `%LOCALAPPDATA%\dpcc\Logs\dpcc.log` contains the line “dpcc angemeldet (Code Completion)” (dpcc
  registered).
- In a `.pas` file, Ctrl+Space opens the dpcc list. Each row shows the kind as a word, the name in bold and the
  signature.

## On the first start

- dpcc starts the server with the first request, for example with Ctrl+Space. The server then builds the index. On
  large installations the first build can take a few minutes because it also reads the library. After that, most of
  it comes from the cache. See [Index and cache](index-cache.md).
- If DelphiLSP is selected as the Code Insight provider when Delphi starts (default), dpcc turns itself off. To turn
  it on, set the master switch under **Tools › Options › Third Party › dpcc** and close with **OK**: dpcc then
  switches the IDE's provider to dpcc and sets the IDE switches it needs (Help Insight, tooltips, delay). This takes
  effect after restarting Delphi; the Messages window says so. See
  [Settings](settings.md#what-dpcc-changes-in-the-ide).

## Updating

1. Get the new version.
2. Rebuild the group (see above).
3. Restart the IDE.

If you build the group in the IDE in which dpcc is installed, the IDE unloads the plugin in the process. dpcc
unregisters step by step for this. Restarting the IDE afterwards is the safe way.

Older versions built the seven runtime packages without a suffix (`dpcc.Text.bpl` … `dpcc.UI.bpl`). After the first
rebuild these files are still in the BPL folder; the plugin no longer loads them, they can be deleted.

## Uninstalling

1. So that dpcc hands the provider and the IDE switches back: under **Tools › Options › Third Party › dpcc**, turn
   off the master switch “Code Insight by dpcc”, close with **OK** and restart Delphi once. dpcc then switches the
   provider back (default DelphiLSP) and reverts its switches.
2. Open **Component › Install Packages…**, select “dpcc (Code Insight-Manager)” and click **Remove**.
3. Close the IDE.
4. Remove the PATH entry: `powershell -NoProfile -File Tools\IdePath.ps1 -Action Remove`, or manually under
   **Tools › Options › IDE › Environment Variables**.

What remains afterwards and can be deleted by hand:

| Location | Contents |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | settings, markers for the IDE switches, `PathOverrideBackup` |
| `%APPDATA%\dpcc` | `settings.json`, `usage.json` (history), `favorites.json` (favorites), from older versions `settings-history.json` |
| `%LOCALAPPDATA%\dpcc` | `Logs` (log), `Index` (index caches) |
| BPL folder | `dpcc.IDE.Expert370.log`, if the diagnostic log was on |

If you skipped step 1, dpcc may remain selected as the provider, and Help Insight, the tooltips and the IDE's value
tooltip may remain off. In that case, select DelphiLSP in the IDE's Code Insight options and switch them back on. The registry locations are listed under
[Settings](settings.md#what-dpcc-changes-in-the-ide).
