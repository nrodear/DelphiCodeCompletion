[Deutsch](../de/installation.md) | English | [Français](../fr/installation.md)

# Installation

[Overview](index.md) › Installation

## Requirements

- Delphi 13 / RAD Studio 37.0. For Delphi 12 / RAD Studio 23.0 see [Building for Delphi 12](#building-for-delphi-12).
- Win32 platform. The IDE is a 32-bit process, so the plugin is a Win32 package. The 64-bit IDE of Delphi 13
  (`bin64\bds.exe`) is not supported.
- The dpcc source code. There are no prebuilt BPLs; dpcc is built from the project group. A setup can be created
  from the built BPLs, see [Installing with the setup](#installing-with-the-setup).

## Building

1. Open `dpcc_d13.groupproj` in the IDE.
2. Platform Win32, configuration Debug.
3. Build all projects in the group. The order follows from the dependencies of the group.

The output is in `Output\Win32\Debug`:

| Folder | Contents |
|---|---|
| `Bpl` | the eight BPLs with the suffix `370` (package version of Delphi 13), including the plugin `dpcc.Plugin370.bpl` |
| `Dcp` | the DCP files of the packages |
| `Dcu` | the DCUs, one subfolder per project |
| `Bin` | the test program `dpcc.Completion.Tests.exe` and the LSP server `dpcc.LspServer.exe` (32-bit) |

The 64-bit EXE of the LSP server is not built by the group build, see [LSP server](#lsp-server).

The command-line compiler (`dcc32`, MSBuild) is locked in the Community and Starter editions; build in the IDE there.
More on this under [Development](development.md).

### Building for Delphi 12

For Delphi 12 (RAD Studio 23.0) there is the group `dpcc_d12.groupproj` with the same eight packages, without the
test program: the tests run only under Delphi 13.

1. Open `dpcc_d12.groupproj` in the Delphi 12 IDE.
2. Platform Win32, configuration **D12** for all eight projects (**Project › Configuration Manager**).
3. Build all projects in the group.

The configuration D12 inherits all settings from Debug and builds into a folder of its own (`Output\Win32\D12`),
so the files of the two versions do not overwrite each other. Never build Delphi 12 with the configuration Debug:
otherwise it writes into the Delphi 13 folders (then rebuild `dpcc_d13.groupproj` under Delphi 13). More on this
in [Development](development.md).

| | Delphi 13 | Delphi 12 |
|---|---|---|
| Group | `dpcc_d13.groupproj` | `dpcc_d12.groupproj` |
| Configuration | Debug | D12 |
| Output | `Output\Win32\Debug` | `Output\Win32\D12` |
| Plugin | `dpcc.Plugin370.bpl` | `dpcc.Plugin290.bpl` |
| Other BPLs | `dpcc.Text370.bpl` … `dpcc.UI370.bpl` | `dpcc.Text290.bpl` … `dpcc.UI290.bpl` |
| IDE PATH | `…\Output\Win32\Debug\Bpl` | `…\Output\Win32\D12\Bpl` |
| IDE registry | `HKCU\Software\Embarcadero\BDS\37.0` | `HKCU\Software\Embarcadero\BDS\23.0` |
| `Tools\IdePath.ps1` | without `-BdsVersion` | `-BdsVersion 23.0` |
| Tests | yes | no |

Install and set the PATH as below, only with the names and folders from the Delphi 12 column: in the Delphi 12
IDE, add `Output\Win32\D12\Bpl\dpcc.Plugin290.bpl` (the IDE enters it under
`HKCU\Software\Embarcadero\BDS\23.0\Known Packages`) and put `…\Output\Win32\D12\Bpl` into the PATH of
the Delphi 12 IDE.

## Installing

1. In the IDE, open **Component › Install Packages…**.
2. Choose **Add…** and open `Output\Win32\Debug\Bpl\dpcc.Plugin370.bpl`.
3. The IDE shows the package with the description “dpcc - Delphi Pascal Code Completion”.

Only `dpcc.Plugin370.bpl` is installed. At run time it needs seven more BPLs (under Delphi 12 with the suffix
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

Earlier versions were named `dpcc.IDE.Base370.bpl` or `dpcc.IDE.Base290.bpl`. If such an entry is still installed,
remove it under **Component › Install Packages…** before adding `dpcc.Plugin370.bpl`: having both would make the IDE
fail at startup. The setup removes the old entry by itself.

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
| `-BplDir` | `Output\Win32\Debug\Bpl` in the repo, with `-BdsVersion 23.0` `Output\Win32\D12\Bpl` | a different BPL folder |

Exit code of `Status` and `Check`:

| Code | Meaning |
|---|---|
| 0 | entry present, all BPLs there |
| 1 | entry missing; fix with `-Action Add` |
| 2 | BPL folder or BPLs missing; build the group first |

## Installing with the setup

Instead of adding the package and the PATH entry by hand, you can create a setup from the built BPLs (Inno Setup 6).
It installs dpcc for the current user, without administrator rights, into Delphi 12 and/or Delphi 13 (32-bit IDE
each).

1. Build both groups: `dpcc_d13.groupproj` (configuration Debug) and `dpcc_d12.groupproj` (configuration D12), see
   above, plus the 64-bit EXE of the LSP server (see [LSP server](#lsp-server)).
2. Create the setup, from the repo folder:

   ```powershell
   powershell -NoProfile -File Tools\Build-Setup.ps1 -DryRun   # check only, creates nothing
   powershell -NoProfile -File Tools\Build-Setup.ps1           # installer\Output\dpccSetup-<version>.exe
   ```

   Next to the setup, `installer\Output\dpcc.LspServer-<version>.zip` is created (see [LSP server](#lsp-server)).
3. Close all Delphi instances and run `dpccSetup-<version>.exe`. Only the Delphi versions the setup finds are
   offered, plus the component “LSP server dpcc.LspServer.exe (for the mode “Server”, 32 and 64 bit)”. It is
   preselected and can be deselected.

For each version the setup copies the eight BPLs to `%LOCALAPPDATA%\Programs\dpcc\bpl\d12` or `…\bpl\d13`, registers
`dpcc.Plugin290.bpl` or `dpcc.Plugin370.bpl` under the IDE's `Known Packages` and puts its BPL folder at the front
of the IDE's PATH. With the component LSP server it puts `dpcc.LspServer.exe` into
`%LOCALAPPDATA%\Programs\dpcc\server\win32` and, only on 64-bit Windows, into `…\server\win64`. Deselecting the
component in a later setup run removes the EXEs. A registration of your own build (for example from
`Output\Win32\Debug\Bpl`) is replaced after a notice: having both would make the IDE fail at startup. If Delphi is
running, the setup stops.

After installation the Plugin mode applies, separately per Delphi version; the setup selects no mode. See
[On the first start](#on-the-first-start).

To uninstall, use Windows **Apps** or the Start menu entry **Delphi Pascal Code Completion › Uninstall dpcc**.
Before that, select the mode “Off” as in [Uninstalling](#uninstalling), step 1; if dpcc is still the Code Insight
provider, the uninstaller asks. It removes the registration, its PATH segment and the files, including
`dpcc.LspServer.exe`; settings, data and cache stay.
Details (German): [installer/README_Installer.md](../../installer/README_Installer.md).

## LSP server

`dpcc.LspServer.exe` is needed only for the Server mode (see [LSP server](lsp-server.md)). There are three ways to
get the EXE:

- **Setup**: component “LSP server” (default), see above.
- **ZIP**: `dpcc.LspServer-<version>.zip` contains `win32\dpcc.LspServer.exe`, `win64\dpcc.LspServer.exe` and
  `LIESMICH.txt`. Put one of the two EXEs next to the plugin (into the folder of `dpcc.Plugin290.bpl` or
  `dpcc.Plugin370.bpl`) or extract the folders `win64` and `win32` to `%LOCALAPPDATA%\Programs\dpcc\server` (with
  the setup layout). On 64-bit Windows use the 64-bit EXE; the 32-bit IDE starts it.
- **Own build**: the 32-bit EXE is built by the group build `dpcc_d13.groupproj` (project
  `Application\dpcc.LspServer.dproj`, Win32, Debug, output `Output\Win32\Debug\Bin`). The 64-bit EXE in a separate
  step in Delphi 13: open `Application\dpcc.LspServer.dproj`, target platform **Windows 64-bit**, configuration
  Debug, **Make**. The output is in `Output\Win64\Debug\Bin`. The plugin finds it there by itself.

Where the plugin looks for the EXE is listed under [LSP server](lsp-server.md#where-dpcc-looks-for-the-exe). The dpcc
page shows whether it is found: without the EXE, “Server” is grayed out.

## Checking that dpcc is loaded

- The IDE's splash screen and About box show “dpcc 0.1.0” (text only, no image).
- Under **Tools › Options › Third Party** there is a **dpcc** node.
- The log `%LOCALAPPDATA%\dpcc\Logs\dpcc.log` contains the line “dpcc angemeldet (Code Completion)” (dpcc
  registered).
- In the Plugin mode, Ctrl+Space opens the dpcc list in a `.pas` file. Each row shows the kind as a word, the name in bold and the
  signature.

## On the first start

- In the Plugin mode dpcc starts the built-in server with the first request, for example with Ctrl+Space. The server
  then builds the index. On large installations the first build can take a few minutes because it also reads the
  library. After that, most of it comes from the cache. See [Index and cache](index-cache.md).
- After installation the Plugin mode applies. If there is no stored value for the Delphi version yet (not even the
  former master switch), dpcc switches the IDE's Code Insight provider to dpcc at the first start and sets the IDE
  switches it needs (Help Insight, tooltips, delay), even if DelphiLSP was selected. This takes effect after
  restarting Delphi; the Messages window says so. Until then the list after “.” still comes from DelphiLSP.
- Another mode is selected under **Tools › Options › Third Party › dpcc**: “Off” (Delphi without dpcc) or “Server”
  (the IDE keeps its windows, the answers come from `dpcc.LspServer.exe`). See
  [Settings](settings.md#operating-mode) and [What dpcc changes in the IDE](settings.md#what-dpcc-changes-in-the-ide).

## Updating

1. Get the new version.
2. Rebuild the group (see above).
3. Restart the IDE.

If you build the group in the IDE in which dpcc is installed, the IDE unloads the plugin in the process. dpcc
unregisters step by step for this. Restarting the IDE afterwards is the safe way.

Older versions built the seven runtime packages without a suffix (`dpcc.Text.bpl` … `dpcc.UI.bpl`). After the first
rebuild these files are still in the BPL folder; the plugin no longer loads them, they can be deleted.

## Uninstalling

1. So that dpcc hands the provider and the IDE switches back: under **Tools › Options › Third Party › dpcc**, select
   the mode “Off”, close with **OK** and restart Delphi once. dpcc then switches the provider back (default
   DelphiLSP) and reverts its switches. This applies per Delphi version.
2. Open **Component › Install Packages…**, select “dpcc - Delphi Pascal Code Completion” and click **Remove**.
3. Close the IDE.
4. Remove the PATH entry: `powershell -NoProfile -File Tools\IdePath.ps1 -Action Remove`, or manually under
   **Tools › Options › IDE › Environment Variables**.

What remains afterwards and can be deleted by hand:

| Location | Contents |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | settings (including `OperatingMode <version>` and a former `Enabled`), markers for the IDE switches, `PathOverrideBackup` |
| `%APPDATA%\dpcc` | `settings.json`, `usage.json` (history), `favorites.json` (favorites), from older versions `settings-history.json` |
| `%LOCALAPPDATA%\dpcc` | `Logs` (log), `Index` (index caches) |
| `%LOCALAPPDATA%\dpcc.LspServer` | caches and log of `dpcc.LspServer.exe`, if the Server mode was used (see [LSP server](lsp-server.md#storage)) |
| BPL folder | `dpcc.IDE.Expert370.log`, if the diagnostic log was on |

If you skipped step 1, dpcc may remain selected as the provider, and Help Insight, the tooltips and the IDE's value
tooltip may remain off. In that case, select DelphiLSP in the IDE's Code Insight options and switch them back on. The registry locations are listed under
[Settings](settings.md#what-dpcc-changes-in-the-ide).
