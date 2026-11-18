[Deutsch](../de/installation.md) | English | [Français](../fr/installation.md)

# Installation

[Overview](index.md) › Installation

## Requirements

- Delphi 13 / RAD Studio 37.0.
- Win32 platform. The IDE is a 32-bit process, so the plugin is a Win32 package.
- The dpcc source code. There are no prebuilt BPLs; dpcc is built from the project group.

## Building

1. Open `dpcc_d13.groupproj` in the IDE.
2. Platform Win32, configuration Debug.
3. Build all projects in the group. The order follows from the dependencies of the group.

The output is in `Output\Win32\Debug`:

| Folder | Contents |
|---|---|
| `Bpl` | the eight BPLs, including the plugin `dpcc.IDE.Base370.bpl` |
| `Dcp` | the DCP files of the packages |
| `Dcu` | the DCUs, one subfolder per project |
| `Bin` | the test program `dpcc.Completion.Tests.exe` |

The command-line compiler (`dcc32`, MSBuild) is locked in the Community and Starter editions; build in the IDE there.
More on this under [Development](development.md).

## Installing

1. In the IDE, open **Component › Install Packages…**.
2. Choose **Add…** and open `Output\Win32\Debug\Bpl\dpcc.IDE.Base370.bpl`.
3. The IDE shows the package with the description “dpcc (Code Insight-Manager)”.

Only `dpcc.IDE.Base370.bpl` is installed. At run time it needs seven more BPLs:

| BPL | Purpose |
|---|---|
| `dpcc.Text.bpl` | text helpers, RTL only |
| `dpcc.WinBase.bpl` | RTL and Windows API |
| `dpcc.Common.bpl` | parser, index, LSP parts, without Windows and VCL |
| `dpcc.Windows.bpl` | Windows-specific parts, without VCL |
| `dpcc.Server.bpl` | the completion server, runs in the IDE process |
| `dpcc.Core.bpl` | plugin logic, without VCL and ToolsAPI |
| `dpcc.UI.bpl` | VCL user interface of the plugin |

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
| `-BdsVersion` | `37.0` | IDE version in the registry |
| `-BplDir` | `Output\Win32\Debug\Bpl` in the repo | a different BPL folder |

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
- dpcc switches off the IDE's Help Insight as long as its own tooltip is on. The Messages window reports this. The
  IDE reads the switch only at its next start; until then, two tooltips may appear. See
  [Settings](settings.md#what-dpcc-changes-in-the-ide).

## Updating

1. Get the new version.
2. Rebuild the group (see above).
3. Restart the IDE.

If you build the group in the IDE in which dpcc is installed, the IDE unloads the plugin in the process. dpcc
unregisters step by step for this. Restarting the IDE afterwards is the safe way.

## Uninstalling

1. So that dpcc hands the IDE switches back: under **Tools › Options › Third Party › dpcc**, turn off the master
   switch “Code Insight by dpcc” and close with **OK**. dpcc then switches Help Insight and the debugger value
   tooltip back on if it had switched them off.
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

If you skipped step 1, Help Insight and the IDE's value tooltip may remain off. In that case, switch both back on in
the IDE's Code Insight options. The registry locations are listed under
[Settings](settings.md#what-dpcc-changes-in-the-ide).
