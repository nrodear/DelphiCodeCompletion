[Deutsch](../de/settings.md) | English | [Français](../fr/settings.md)

# Settings

[Overview](index.md) › Settings

The options are under **Tools › Options › Third Party › dpcc**. This is a single page without subpages.

## The page

- The operating mode with three radio buttons is at the top, followed by the sections **Completion**, **When
  accepting**, **Parameter hint and tooltip**, **Index** and **IDE**.
- The options below apply only to the Plugin mode. In the Off and Server modes they and the “Reset history” button
  are grayed out. “Additional source folders”, “Rebuild index”, “Check now” and “Log the flow (log file)” remain
  available.
- “Show values while debugging” is grayed out as long as “Own tooltip when hovering identifiers” is off.

Settings are saved with **OK**. Exceptions: “Reset history” and “Rebuild index” take effect immediately, “Check
now” only reads. “Log the flow (log file)” takes effect after OK without a restart.

Some former options are no longer on the page and have fixed values (see [Fixed values](#fixed-values)).

The “Registry value” column gives the name under `HKCU\Software\dpcc\IdePlugin`, the “Key” column the name that dpcc
uses in hints and in `settings.json`. “–” under “Registry value”: the option is not stored in the registry but in
`settings.json` (see [Storage](#storage)).

## Operating mode

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Mode (three radio buttons) | `OperatingMode 23.0` (Delphi 12) or `OperatingMode 37.0` (Delphi 13); with an own registry profile (`bds -r <profile>`) `OperatingMode <profile> 23.0` or `… 37.0` | `operatingMode` | Plugin | Separately per Delphi version (and per registry profile): `off`, `plugin` or `server`. Replaces the former master switch “Code Insight by dpcc” (`Enabled`, shared by all versions). At runtime exactly one mode applies; the plugin's built-in server and `dpcc.LspServer.exe` never work at the same time. A change to or from Plugin switches the IDE's Code Insight provider and takes effect after restarting Delphi; between Off and Server it takes effect the next time a project group is opened. See [Switching](#switching). The dpcc list, parameter hint and tooltip follow the choice immediately after OK (outside Plugin, Ctrl+Space and Ctrl+Shift+Space go to the IDE); a built-in server that is already running keeps running. |

The three radio buttons and their text on the page:

| Radio button | Text below it |
|---|---|
| “Off – Delphi works without dpcc” | “Delphi uses its own Code Insight provider (DelphiLSP); dpcc shows no windows and redirects nothing.” |
| “Plugin – Code Insight by dpcc in the editor (default)” | “dpcc becomes the IDE's Code Insight provider, with its own list, tooltip and parameter hint. Switching to or from Plugin takes effect after restarting Delphi.” |
| “Server – dpcc.LspServer.exe instead of DelphiLSP” | “Delphi stays in LSP mode and shows its own windows; the answers come from dpcc.LspServer.exe instead of DelphiLSP.exe. The IDE's error marks (Error Insight) stay empty. dpcc turns on code completion, auto invoke, code parameters and symbol insight in the IDE's Code Insight options and restores them when leaving Server; nothing needs to be turned off there for the server. Switching to or from Plugin takes effect after restarting Delphi, between Off and Server the next time a project group is opened; the IDE reads the four options only at the next start of Delphi, though.” |

- **Off** (formerly “master switch off”): Delphi works with its own Code Insight provider (DelphiLSP,
  `Insight Manager` = `Borland.CodeInsight.LSP.Pascal`). dpcc shows no windows and redirects nothing.
- **Plugin** (default after installation, formerly “master switch on”): dpcc is the Code Insight provider
  (`dpcc.CodeInsight`) with the built-in server and its own list, tooltip and parameter hint.
- **Server**: the IDE stays in LSP mode (provider DelphiLSP). When it starts `DelphiLSP.exe`, the plugin starts
  `dpcc.LspServer.exe` in its place. The built-in server and the dpcc windows are off. See
  [Server mode](#server-mode).

### Server mode

- List, hint, tooltip on hover, Structure view and Ctrl+click are those of the IDE; the answers come from
  `dpcc.LspServer.exe`. The dpcc list, tooltip and parameter hint do not appear, Ctrl+Space and Ctrl+Shift+Space go
  to the IDE.
- The IDE's error marks (Error Insight) stay empty: `dpcc.LspServer.exe` delivers no code diagnostics. dpcc does not
  set `ErrorInsightLevel`.
- Without four of the IDE's Code Insight options the IDE does not ask the server: code completion, auto invoke, code
  parameters and tooltip symbol insight. dpcc turns them on itself in the Server mode and sets them back to the
  previous values when switching to Off (see [Options in the Server mode](#options-in-the-server-mode)). Nothing needs
  to be turned off in the IDE's Code Insight dialog for the server. The IDE reads the options only at the next start
  of Delphi.
- The redirection happens from within the plugin (hook on `CreateProcessW` in the module `IDELSP290.bpl` or
  `IDELSP370.bpl`). dpcc changes nothing in the Delphi program folder and needs no administrator rights. Details,
  locations of the EXE and log lines: [LSP server](lsp-server.md#server-mode).
- “Server” can only be selected if dpcc finds the EXE. Otherwise the radio button is grayed out with “Not available:
  dpcc.LspServer.exe is not installed (select the component “LSP server” in the setup).” below it. If Server is
  already selected, it stays selected; the start then falls back to the original DelphiLSP. The hint on the radio
  button names the location found (“Program: …”).
- Not supported: the 64-bit IDE of Delphi 13 (`bin64\bds.exe`). The plugin is 32-bit.

## Completion

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Open automatically after the dot | `OpenAfterDot` | – | on; start value taken once from the IDE (see [After updating](#after-updating)) | After “.” the list opens by itself. Off: dpcc reports no Code Insight to the IDE after “.” (`GetCodeInsightType('.')` returns “none”), no list opens; Ctrl+Space still opens it, the other triggers (“(”, “[”, “<” in XMLDoc, “;” after a constructor) stay. Takes effect after OK immediately, without a restart. Under Delphi 13 the IDE in addition opens after “.” only if Code completion and Auto invoke are on in dpcc's set; dpcc sets both itself in the Plugin mode (see [Switches in the Plugin mode](#switches-in-the-plugin-mode)). Replaces “Auto invoke” in the IDE dialog (see [IDE Code Insight](#ide-code-insight)). Locked outside the Plugin mode. |
| Open on typing from characters (0 = never): | `AutoMinChars` | `completion.autoMinChars` | 0 | 0 to 10; default 0 = off (as before opening while typing existed), to switch it on set e.g. 5. When you type a name without a dot before it, the list opens only once the word before the cursor has this many characters; below that dpcc does not ask the server. 0 = typing never opens it. Ctrl+Space opens it at any length; nothing changes after “.” and for the other triggers. So that the IDE does not additionally open its own list while typing, dpcc sets `Auto Invoke Delay` = -1 in the Plugin mode (see [below](#what-dpcc-changes-in-the-ide)). See [Usage](usage.md#opening-while-typing). |
| While typing, show: | `CompletionListMode` | `completion.listMode` | Only matches | “Only matches” (`filter`), “All entries, matches on top” (`all`), “Matches, then the rest dimmed” (`rest`, under the heading “More entries”). Applies to member lists after “.” (fixed). |
| Visible rows of the list: | `VisibleRows` | `completion.visibleRows` | 9 | 5 to 20 rows. |
| Automatic width | `ListWidth` | `completion.listWidth` | on (`ListWidth` = 0) | In the same row as “Visible rows of the list”. On: the list grows with the widest entry. Off: the width last dragged (240 to 720). Dragging the right edge of the list also sets the width. |
| Show reserved words in the list | – | `completion.keywords` | on; start value taken once from the IDE (see [After updating](#after-updating)) | Keywords such as `begin`, `if` or `procedure` in the list, depending on the position and only after a typed character, never after “.”. Off: the server leaves them out. Stored in `%APPDATA%\dpcc\settings.json` under the key the server reads; a value already set there applies and shows on the page. Takes effect after OK without a restart, from the next list on: the server reads the file again as soon as it changes. Because `dpcc.LspServer.exe` reads the same file, the value also applies in the Server mode. Replaces “Show reserved words” in the IDE dialog. Locked outside the Plugin mode. |
| Frequently and recently chosen entries first | `Learning` | `completion.learning` | on | Learned ranking: accepted entries get a bonus in the ranking. From 5 acceptances on, an entry counts as “frequent”. Stored in `%APPDATA%\dpcc\usage.json`, at most 5,000 entries. |
| Button “Reset history” | – | – | – | To the right of “Frequently and recently chosen entries first”. Clears the learned ranking immediately; after that the button stays grayed out until the dialog closes. |

## When accepting

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Add parentheses to methods | `AutoParentheses` | `completion.autoParentheses` | on | Adds the parentheses when a method is accepted; a “)” typed directly before it skips the automatic one. |
| Accept with “(”, “;” and “.” | `CommitCharacters` | `completion.commitCharacters` | on | Commit characters: if the selected entry is an unambiguous match, one of these characters accepts it; the character stays. Otherwise only the character remains, and the list closes. |
| Add the unit to uses automatically | `AutoUses` | `completion.autoUses` | on | For entries that show “+” and the name of a unit on the right (for example “+ System.SysUtils”), dpcc adds that unit to `uses` when accepting, in the same undo step. |

## Parameter hint and tooltip

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Parameter hint on “(” and “,” | `ParameterHints` | `completion.parameterHints` | on | Off: no dpcc parameter hint, not even via Ctrl+Shift+Space. Automatic opening on “(” and “,” reaches dpcc only if the IDE calls dpcc as the provider (see [Usage](usage.md#interaction-with-delphilsp)). |
| Own tooltip when hovering identifiers | `HoverTooltip` | `editor.hoverTooltip` | on | dpcc tooltip. As long as it is on, dpcc switches off the IDE's Help Insight and tooltip symbol insight in the Plugin mode (`Help Insight`, `Declaration Information`) and hides a Help Insight window that still appears immediately, without a restart. Locked outside the Plugin mode. |
| Show values while debugging (turns off the IDE's value tooltip) | `DebugHoverValues` | `debug.hoverValues` | on | Indented below the tooltip. While the program is paused, the value of the expression is shown at the top of the tooltip; dpcc then switches off the IDE's tooltip expression evaluation (`ToolTip Watches`). If you want the IDE's value tooltip, switch this option off. Locked as long as “Own tooltip …” is off. |
| Popup appearance: | `PopupLook` | `editor.popupLook` | Subtle | “Intense” (`intense`), “Subtle” (`subtle`), “Plain” (`plain`). Sets how much color the dpcc windows use: completion list, tooltip and parameter hint, plus the placeholder markers in the editor. What each level changes is described under [Popup appearance](#popup-appearance). After OK it applies from the next time a window opens. An unknown value in the registry counts as Subtle. Locked outside the Plugin mode. |

### Popup appearance

| Level | Effect |
|---|---|
| Intense | Highlighted areas – the selected row of the list, the header of the tooltip and the selected overload in the parameter hint – look as in Subtle and also get a thick bar in the accent color: at the very top of the tooltip window, to the left of the row in the list, at the left edge in the parameter hint. Outside the highlighted areas the kind column shows one color per kind group, the labels on the right are colored (including “+ Unit” for a missing unit), type and parameter names have their own color, and the active parameter sits on an accent background. |
| Subtle (default) | The same elements, toned down: a light accent background for the selected row and the header, type and parameter names in a toned-down color. The kind column is dimmed; only warnings and errors are colored. |
| Plain | Almost no color: selected row and header on a light gray background, type and parameter names in the text color, keywords in signatures only bold. Errors stay red. |

Error lines use the error color at all three levels. The IDE's own windows are not affected: the IDE's tooltip
symbol insight (when the own tooltip is off), the IDE's Code Insight list and the Messages window. There the IDE
decides the colors.

## Index

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Additional source folders (separated by “;”, including subfolders): | – | `index.extraSourceFolders` | empty | Folders with the source code of libraries that otherwise only exist as `.dcu` (DUnitX, DUnit, FireDAC, components). Subfolders count too (without `.git`, `__history`, `__recovery`); `$(Name)` and `%Name%` are resolved. “+ Unit” suggests their units; they are loaded on demand and have a cache of their own. Stored in `%APPDATA%\dpcc\settings.json` (in the file also as a list), not in the registry; the server rebuilds the index without a restart. Replaces the former switch `index.officeAndWinRt`: the Office type libraries and WinRT are always in the catalog. See [Index and cache](index-cache.md#additional-source-folders). |
| Button “Rebuild index” | – | – | – | Asks for confirmation, deletes all index caches and rebuilds the index. Does not depend on the operating mode. See [Index and cache](index-cache.md#rebuilding-the-index). |

## IDE

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Button “Check now” | – | – | – | The status lines to its right: mode and provider, whether a change is still waiting for Delphi to restart (compared with the provider the running IDE works with), what dpcc has set in the IDE, and the result of the check (for example “1 difference: Auto Code Completions”). The line grows with the text; in the dialog's font, gray. Read when the page opens; the button reads again. Only reads, changes nothing; does not depend on the operating mode. See [What dpcc changes in the IDE](#what-dpcc-changes-in-the-ide). |
| Log the flow (log file) | `Diagnose` | – | off | For every action (Ctrl+click or “Find Declaration”, completion, hover, parameter hints) writes each step from the IDE's call to the result into the diagnostic log next to the plugin BPL. No source code except the word at the position. The same DWORD as the former manually set `Diagnose` = 1: a value set that way shows as checked. Takes effect immediately after OK, without a restart; the Messages window then names the file, so does the hint on the check box. Does not depend on the operating mode. See [Troubleshooting](troubleshooting.md#flow-log). |

## Fixed values

These options are no longer on the page. They have fixed values, the former defaults:

- **Delay before automatic opening (for example after “.”): 150 ms** (`OpenDelayMs`, `completion.openDelayMs`).
  Applies only to automatic opening (after “.” and while typing), not to Ctrl+Space. dpcc opens automatically only
  in the Plugin mode; in the Off and Server modes dpcc opens no list (see
  [Usage](usage.md#interaction-with-delphilsp)).
- **Pin favorites with Ctrl+D: on** (`Favorites`, `completion.favorites`). Ctrl+D in the open list pins or unpins;
  the favorites are still stored in `%APPDATA%\dpcc\favorites.json`. See [Usage](usage.md#favorites).
- **Inherited members ranked lower and grouped by class: on** (`GroupInherited`, `completion.groupInherited`).
  Without a typed prefix: own members first, then one group “Inherited from …” per ancestor. With a prefix, at equal
  match quality the own member comes before the inherited one.
- **Show the branch of variant record fields: on** (`CompletionVariantBranch`, `completion.variantBranch`). Fields
  in the variant part of a record (`case … of`) get the label “branch 0”, “branch 1” and so on.
- **List mode applies to: member lists after “.”** (`CompletionListScope`, `completion.listMode.scope` =
  `members`). “While typing, show” only takes effect there.
- **Preview of the selected entry in the editor: removed** (formerly `Preview`, `completion.preview`, most
  recently fixed to off). Since the settings clean-up, the code for it is gone as well.
- **Fix the case when accepting (showmessage → ShowMessage): on** (`FixCase`, `completion.fixCase`). Replaces the
  typed word with the spelling of the declaration.
- **Match and colour Format placeholders in the parameter hint: on** (`FormatPlaceholders`,
  `completion.formatPlaceholders`). Line for the placeholder at the cursor, warnings, same color for placeholder and
  argument; only as long as “Parameter hint on “(” and “,”” is on.
- **XMLDoc: max. lines before scrolling: 0 = screen** (`XmlDocMaxLines`, `hints.xmlDocMaxLines`). 0 to 50. More
  lines scroll in the tooltip with the mouse wheel. 0: only the space on the screen limits it. No longer on the page,
  but still adjustable via `hints.xmlDocMaxLines` in `%APPDATA%\dpcc\settings.json`; the server reads the file
  itself.

## After updating

- The former division into **General**, **Completion**, **Insertion** and **Hints** no longer exists, nor do the
  tree, the search box, the row “Filter:”, the marking of changed values with “Reset to default” on right-click, the
  list “Pinned favorites”, the “Reset widths” button and the switch “Allow experimental features” (the key
  `experimental.enabled` in `settings.json` still applies).
- “XMLDoc when opened” (`hints.xmlDocExpand`, before that `hints.xmlDocFull`) has been dropped: the tooltip always
  shows the XMLDoc expanded. An old value in `settings.json` stays in the file and is ignored without a message; dpcc
  no longer writes the key.
- If you had changed one of the options that are now [fixed](#fixed-values), the change is lost without a message.
  The old values under `HKCU\Software\dpcc\IdePlugin` stay in place and are ignored.
- The master switch “Code Insight by dpcc” has given way to the [operating mode](#operating-mode): on corresponds to
  Plugin, off to Off; Server is new. The mode applies per Delphi version; dpcc migrates the former value `Enabled` at
  the first start (see [Storage](#storage)).
- OK only saves the values of the page: the operating mode of the running Delphi version and twelve options in the
  registry,
  `index.extraSourceFolders` in `settings.json`. Formerly every OK wrote about 600 registry values (including hidden
  settings of former tabs, keys, module switches and experimental switches) plus server keys in `settings.json`:
  `slashCommands.enabled`, `codeLens.metrics`, `metrics`, `experimental.enabled`, `compiler.onSave`,
  `architecture.*`, `query.enabled`, `ruleChecks.enabled`, `hotspots.*`, `references.*`, `navigation.*`, `tests.*`,
  `issues.*` and `vcs.*`. All of these values stay in place: dpcc no longer reads the old registry values, and the
  server keeps reading the keys in `settings.json` without a message. Without them, its defaults apply; they match
  the values the plugin used to write.
- “Show values while debugging” now depends only on its own option (and, on the page, on the own tooltip). The
  former hidden module switch `debug.enabled` (registry value `DebugEnabled`) no longer turns it off.
- dpcc no longer writes the settings history `%APPDATA%\dpcc\settings-history.json`. An existing file stays in
  place and can be deleted.
- New in the **IDE** section: “Log the flow (log file)”. It switches the same diagnostic log as the registry value
  `Diagnose` = 1 that used to be set by hand only, now without a restart. Since then OK also writes `Diagnose`; if you
  set the value by hand, the check box shows as checked.
- New in the **Completion** section: “Open automatically after the dot” and “Show reserved words in the list”. dpcc
  hides the matching fields in the IDE's Code Insight dialog (see [IDE Code Insight](#ide-code-insight)).
- Start values of the two switches: once at the first start after the update in which the Plugin mode applies (in
  the Off and Server modes dpcc reads and writes nothing for this), from the DelphiLSP set of the running
  version (`HKCU\<base>\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal`; with an own profile,
  `bds -r`, its base key).
  - “Open automatically after the dot” = `Auto Code Completions` and `Auto Invoke` (both on).
  - “Show reserved words in the list” = `Show Reserved Words`.
  - A missing value counts as on.
  - If there is a marker `IdeSet <version> <key>\<value>` for one of the values, the remembered value from before
    applies (the user's), not the one dpcc wrote; without a value before, on applies.
  - If `completion.keywords` was already in `settings.json`, that value applies; dpcc reads nothing from the IDE for
    it.
  - After that dpcc never reads the values from the IDE again. The markers `IdeAdopted OpenAfterDot` and
    `IdeAdopted CompletionKeywords` (DWORD 1, per switch, for all Delphi versions) record this. So the Delphi version
    that first starts in the Plugin mode provides the start values. The log line reads “Startwerte aus den Code-Insight-Optionen der IDE
    übernommen (einmalig, …): OpenAfterDot = …; CompletionKeywords = …” (log lines are always German).
- IDE features in dpcc's set, only under **Delphi 13** and only in the Plugin mode: if `Auto-block Completion`,
  `Block Wrap Style`, `Code Templates`, `Auto Complete Templates` or `Sync Edit Hints` are missing in
  `Code Insight\Borland.EditOptions.Pascal`, dpcc takes the value from the DelphiLSP set once at the first start.
  - Only into gaps: existing values stay, a missing key is not created.
  - Without an `IdeSet` marker: the value belongs to the user afterwards, Off does not turn it back.
  - The marker `IdeAdopted 37.0 IdeFeatures` records that this is done, even if nothing was missing. Usually the set is
    complete; then the log says “IDE-Funktionen: im Satz von dpcc nichts zu übernehmen”.
- **Delphi 12**: dpcc writes nothing for this. Since this version, dpcc names the DelphiLSP set as its option set in
  Delphi 12; block completion and templates there therefore follow, without adoption, the values set for DelphiLSP
  (see [IDE Code Insight](#ide-code-insight)). Markers that earlier versions created under Delphi 12 for
  `Code Insight\Borland.EditOptions.Pascal` are cleaned up by dpcc at the next start (value restored, or deleted if
  it did not exist before; in the log “aufgeräumt (alter Ort)”).
- “Finish incomplete properties” (`Finish properties`) is shared by all providers under `<base>\Class Completion`;
  dpcc does not touch it.

## Storage

| Location | Contents |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | all options on the page except `index.extraSourceFolders` and `completion.keywords`, among them `OpenAfterDot` (“Open automatically after the dot”). Also the markers of the one-time adoption from the IDE (`IdeAdopted OpenAfterDot`, `IdeAdopted CompletionKeywords`, `IdeAdopted 37.0 IdeFeatures`, DWORD 1; see [After updating](#after-updating)); OK does not write them. Switches and numbers as DWORD (switches 0/1), choices as text (`CompletionListMode`: `filter`, `all`, `rest`; `PopupLook`: `intense`, `subtle`, `plain`; the operating mode per version as `OperatingMode 23.0` or `OperatingMode 37.0`: `off`, `plugin`, `server`). The former master switch `Enabled` (DWORD, shared by all versions) is only read, see below. Also the markers for the IDE switches (below) and `PathOverrideBackup` from `Tools\IdePath.ps1`. Read only, never written: the support switch `LogNames` (see [Troubleshooting](troubleshooting.md)). `Diagnose` (“Log the flow (log file)”) is now one of the page's values; OK writes it as 0 or 1, a value set by hand still applies. Old values of the fixed and the removed options stay in place but have no effect; dpcc no longer writes them. |
| `%APPDATA%\dpcc\settings.json` | `index.extraSourceFolders` and `completion.keywords` (both from the page) and `hints.xmlDocMaxLines` (adjustable only in the file). If `completion.keywords` is missing from the file, a registry value `CompletionKeywords` applies, otherwise on. The in-process server reads the file itself and watches it. dpcc only reads `hints.xmlDocMaxLines` and never writes the key; if it is missing from the file, a registry value `XmlDocMaxLines` from an older version applies, otherwise 0. dpcc does not touch other keys in the file. An old value `hints.xmlDocExpand` or `hints.xmlDocFull` has no effect. |
| `%APPDATA%\dpcc\settings-history.json` | only from older versions: earlier states of the settings. dpcc no longer writes or reads the file; it can be deleted. |
| `%APPDATA%\dpcc\usage.json` | history of the learned ranking |
| `%APPDATA%\dpcc\favorites.json` | pinned favorites |

dpcc moves an unusable `usage.json` or `favorites.json` aside as `….defekt` and starts empty. It does not overwrite a
locked file.

Operating mode at the first start of a version:

- If the Delphi version has no value `OperatingMode <version>` of its own yet, the former `Enabled` applies: 0 → Off,
  any other value → Plugin. If `Enabled` is missing too, Plugin applies. An unreadable value counts as a missing one.
- dpcc writes the result under the version's name immediately at the first start. `Enabled` then stays in place
  unchanged and is no longer written.
- If there is neither a value of its own nor `Enabled` (first start after installation), Plugin applies, and dpcc
  switches the IDE's Code Insight provider to dpcc, even if DelphiLSP was selected. This takes effect after restarting
  Delphi.

Everything back to default: close the IDE and delete the key `HKCU\Software\dpcc\IdePlugin` and `settings.json`.
Before that, select the Off mode, confirm with OK and restart Delphi once, so that dpcc hands back the provider and
the IDE switches (see below). At the next start the default Plugin applies again, and dpcc switches the provider to
dpcc once more.

## What dpcc changes in the IDE

dpcc runs per Delphi version in one of three mutually exclusive [operating modes](#operating-mode). It is selected on
the page; when Delphi starts, dpcc reconciles it with the Code Insight provider selected for Delphi in the IDE options
(value `Insight Manager` under `HKCU\<base>\Editor\Source Options\Borland.EditOptions.Pascal`). This is the same for
Delphi 12 (`<base>` = `Software\Embarcadero\BDS\23.0`) and Delphi 13 (`…\BDS\37.0`).

| Mode | IDE provider | dpcc | What dpcc changes in the IDE |
|---|---|---|---|
| Off | DelphiLSP (IDE default) or another provider | no windows, no redirection | It reverts what it changed itself. It only checks the values DelphiLSP needs and writes the result to the log. |
| Plugin | dpcc (`dpcc.CodeInsight`) | built-in server, own list, tooltip and parameter hint | It sets the switches from the table [Switches in the Plugin mode](#switches-in-the-plugin-mode). |
| Server | DelphiLSP (`Borland.CodeInsight.LSP.Pascal`) | no built-in server, no windows; the start of `DelphiLSP.exe` is redirected to `dpcc.LspServer.exe` | It sets the four options from [Options in the Server mode](#options-in-the-server-mode) and reverts everything else as with Off. With OK it sets the provider to DelphiLSP. The redirection lives in the IDE process, not in the registry. |

There is no Open Tools API for these switches: they are in the IDE's registry and are read when the IDE starts. dpcc
reads and writes them there, version-neutrally via the base key of the running IDE.

### Switching

- **Plugin** with OK: dpcc switches the IDE's provider to dpcc (`Insight Manager` = `dpcc.CodeInsight`) and sets the
  switches. The previous provider is remembered.
- **Off** with OK while Plugin applied: dpcc switches the provider back (to the remembered one, otherwise to
  DelphiLSP) and reverts its other changes.
- **Server** with OK: dpcc sets the provider to DelphiLSP in any case (also from another provider, not to the
  remembered value), turns on the four [options for the server](#options-in-the-server-mode) and reverts its other
  Code Insight switches as with Off.
- **Between Plugin and Server**: an option both modes want the same way (code completion, auto invoke, code
  parameters) stays as it is; dpcc does not briefly set it back and forth, and its marker keeps the value from before
  the first change. Symbol insight is turned off by Plugin and on by Server. What only Plugin sets (Help Insight,
  expression evaluation, delay while typing, `AutoInvokeCompletionOnParameterInsight`, provider) goes back to the
  previous value when switching to Server.
- To or from **Plugin** the provider changes; this only takes effect after restarting Delphi (see below).
- **Between Off and Server** (the IDE is already in LSP mode) no restart is needed. The IDE starts its server when the
  first unit of a project group is shown, one per project group; a running server stays until the group is closed.
  The redirection reads the mode anew each time DelphiLSP starts. So: close the project group and open it again.
  If dpcc first has to switch on the four Code Insight options of the server (see [Options in the Server
  mode](#options-in-the-server-mode)), that only applies after Delphi restarts (measured on 28.11.2026 in Delphi
  12 and 13). The Messages window says so once (“Mode Server: the next time the IDE starts its Code Insight server …”
  or “Mode Off: the next time a project group is opened …”).
- **When Delphi starts** the mode follows the selected provider: if dpcc is selected, Plugin applies. If DelphiLSP is
  selected (or no provider is set), a stored Server mode stays, otherwise Off applies. If another provider is
  selected, Off applies; if Server was selected, the Messages window says so. The exception is the first start without
  a stored value (see [Storage](#storage)).
- **In the IDE options** (Code Insight), select a provider: dpcc → Plugin; another provider while Plugin applies → Off
  (as before); DelphiLSP while Server applies → Server stays. If the IDE reports the choice to dpcc, the mode follows
  immediately; otherwise the choice applies at the next start. The choice survives exiting: after OK, dpcc reconciles
  with the mode that is then stored (that is, already the selected one), and on exit it writes this state, not the
  one from before the choice. If you select a different mode on the dpcc page in the same OK, the choice in the Code
  Insight dialog applies.
- The IDE reads the provider and the switches only at startup. After a change, dpcc reports once in the Messages
  window “… takes effect after restarting Delphi”. Until then, the IDE calls the previous provider, and the
  [IDE](#ide) section of the page shows “The provider becomes … at the next start of Delphi”.
- The notices appear in the Messages window's own **dpcc** tab (View › Tool Windows › Messages), not in the “Build”
  tab, which the next build clears.
- Because the IDE writes its editor options back from memory on OK, dpcc writes only after the dialog, checks again
  afterwards and writes the intended state once more when Delphi exits. This also applies to ways back without a
  marker (Off, Server → Off, tooltip off): if on exit the value is again exactly the one from before the way back (the
  IDE wrote its memory back; seen in Delphi 12 after an OK in the options dialog), dpcc writes the way back again; in
  the log “IDE-Kontext beim Beenden: Rückweg erneut geschrieben …”. If a different value is there, it stays.
- The same applies when you select dpcc or another provider in the IDE's Code Insight dialog and confirm with OK: the
  IDE then writes its editor options back from memory and may overwrite values set by dpcc. So dpcc checks once more
  after the options dialog has closed (as soon as no modal window is open any more, for at most 10 minutes) and writes
  overwritten values again, as after OK on the dpcc page. The repair when Delphi exits remains.
- If the switch to dpcc still does not stick (the IDE wrote its choice back), dpcc is off at the next start and the
  Messages window says so. Then select the Plugin mode again or select dpcc in the IDE options.
- Each decision is one line in the log, for example “IDE-Kontext (Start): Borland.CodeInsight.LSP.Pascal → dpcc aus;
  Betriebsart Server; …” or “IDE-Kontext (Hauptschalter an): … → dpcc an; Betriebsart Plugin (geändert); Anbieter →
  dpcc.CodeInsight (wirkt nach dem Neustart); gesetzt: …” (log lines are always German). The trigger in parentheses is
  still called “Hauptschalter an” (Plugin), “Hauptschalter aus” (Off) or “Betriebsart Server” in the log. A change on
  the page is also logged as “IDE-Kontext: Betriebsart mit OK umgestellt: Aus → Server”, a choice in the Code
  Insight dialog as “IDE-Kontext: dpcc im Code-Insight-Dialog der IDE gewählt” or “… anderer Anbieter …”.

### Switches in the Plugin mode

Location unless stated otherwise: the Plugin-mode locations under `HKCU\<base>\Code Insight` (see
[Key locations per version](#key-locations-per-version)). Under Delphi 12 this is the DelphiLSP set
(`Borland.EditOptions.Borland.CodeInsight.LSP.Pascal`), which the IDE there also reads for dpcc; under Delphi 13 each
existing one of `Borland.EditOptions.Pascal` and `Borland.EditOptions.Borland.CodeInsight.LSP.Pascal`.

| IDE option | Registry value | Expected | When | Reason |
|---|---|---|---|---|
| Code Insight provider for Delphi | `Insight Manager` (under `Editor\Source Options\Borland.EditOptions.Pascal`) | `dpcc.CodeInsight` | always | dpcc serves Delphi files itself. |
| Code completion | `Auto Code Completions` | `True` | always | Off: no list opens after “.”. |
| Auto invoke | `Auto Invoke` | `True` | always | Off: the IDE does not invoke code completion after “.” by itself. |
| Code completion: Delay while typing | `Auto Invoke Delay` | `-1` | always | From 0 on, the IDE additionally opens its own list while typing. |
| Code parameters: Auto invoke | `Auto Code Parameters` | `True` | always | Off: the parameter hint does not open on “(” and “,” by itself. |
| Tooltip help insight | `Help Insight` | `False` | “Own tooltip …” on | Otherwise the IDE shows Help Insight next to the dpcc tooltip. In addition, dpcc hides the window at runtime (see below). |
| Tooltip symbol insight | `Declaration Information` | `False` | “Own tooltip …” on | Otherwise the IDE shows its tooltip next to the dpcc tooltip. |
| Tooltip expression evaluation | `ToolTip Watches` | `False` | tooltip and “Show values while debugging” on | Otherwise two value tooltips while debugging. |
| Open code completion with parameter insight | `AutoInvokeCompletionOnParameterInsight` (under `InsightGlobalOptions`) | `False` | always | Otherwise the IDE additionally opens its list with the parameter hint. |

A missing value applies with the IDE default (switches on, delay -1). If it already fits, dpcc writes nothing. The
option names are those of the English IDE, shortened; the registry value is what counts.

Help Insight at runtime: regardless of the registry value, dpcc hides the IDE's Help Insight window as soon as it
becomes visible, as long as the Plugin mode applies and either “Own tooltip …” is on (then always) or dpcc's completion popup is
open (then also with the own tooltip off, so that the window does not cover the list). This takes effect immediately,
without restarting Delphi; in the Off and Server modes the IDE's Help Insight is left alone. The first hide per session is logged
(“Help Insight der IDE: Fenster THelpInsightWindow verborgen …”), with “Log the flow (log file)” every hide with its
reason. At
startup the log also has a line “Help Insight in der Registry (…)” with the value read at the DelphiLSP location,
`Borland.EditOptions.Pascal` and `Borland.EditOptions.HTML` (log lines are always German).

### IDE Code Insight

Applies in the Plugin mode, when dpcc is selected as the provider under **Tools › Options › Editor › Language › Code
Insight**. What dpcc does itself is set on the dpcc page; dpcc hides these fields in the IDE dialog. What the IDE does
on its own stays there. The Off and Server modes do not change: there DelphiLSP is selected, and the dialog shows its
fields.

| Field in the IDE dialog | Registry value | Handled by | In the dialog |
|---|---|---|---|
| Code completion | `Auto Code Completions` | stays with the IDE; dpcc sets it on in the Plugin mode. “Open automatically after the dot” turns the list after “.” off. | visible (no query in the Open Tools API) |
| Auto invoke, with the delay | `Auto Invoke`, `Auto Invoke Delay` | “Open automatically after the dot”; dpcc sets the delay to -1 | hidden |
| Auto parenthesis | `CodeCompleteAutoParens` | “Add parentheses to methods” | hidden |
| History | `History` | “Frequently and recently chosen entries first” | hidden |
| Show reserved words | `Show Reserved Words` | “Show reserved words in the list” | hidden |
| Finish incomplete properties | `Finish properties` (under `Class Completion`, for all providers) | stays with the IDE | visible (no query) |
| Code parameters | `Auto Code Parameters` | “Parameter hint on “(” and “,”” | hidden |
| Tooltip expression evaluation | `ToolTip Watches` | “Show values while debugging” | hidden |
| Tooltip symbol insight | `Declaration Information` | “Own tooltip when hovering identifiers” | hidden |
| Tooltip help insight | `Help Insight` | “Own tooltip when hovering identifiers” | hidden |
| Block completion | `Auto-block Completion` | stays with the IDE | visible |
| Block wrap style | `Block Wrap Style` | stays with the IDE | visible |
| Code template completion | `Code Templates` | stays with the IDE | visible (no query) |
| Auto complete (templates) | `Auto Complete Templates` | stays with the IDE | visible (no query) |
| Hints | `Sync Edit Hints` | stays with the IDE | visible (no query) |
| Generate LSP Config | `CodeInsightLSPGenerate` | concerns DelphiLSP only, no effect with dpcc | hidden |
| Use the 64-bit version of the server (Delphi 13 only) | `CodeInsightUse64BitBinary` | concerns DelphiLSP only, no effect with dpcc | hidden (seen in Delphi 13 with dpcc as the provider on 28 Nov 2026) |
| Use Visual Assist | `CodeCompleteUseVA` | stays with the IDE | as before |
| Error Insight (own tab) | `Error Insight` | stays with the IDE | visible as before |

- dpcc hides via `IOTACodeInsightManagerEnvOptions` (same in Delphi 12 and 13), “Generate LSP Config” via
  `IOTACodeInsightManagerEnvOptions270` (declared the same in both versions). There is no query for Code completion,
  the templates, the hints and the incomplete properties; they stay visible. “Block completion” and its wrap style
  have a query; dpcc keeps them visible.
- The field names are those of the English IDE, shortened; the registry value is what counts. A hidden field keeps its
  value; the IDE writes it with OK as before.

Which registry set the IDE reads with dpcc as the provider (measured on 28 Nov 2026 in the Plugin mode with swapped
values in `Code Insight\Borland.EditOptions.Pascal`, in the DelphiLSP set, `Borland.EditOptions.dpcc.CodeInsight`,
HTML and StyleSheet; checked with begin+Enter, todo+Space and opening after “.”):

| | Delphi 12 (BDS 23.0) | Delphi 13 (BDS 37.0) |
|---|---|---|
| Name from `GetOptionSetName` | `Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` (since this version; before that `Borland.EditOptions.Pascal`) | `Borland.EditOptions.Pascal` |
| Set the IDE reads for dpcc | with the former name none (block completion, templates and opening after “.” were always on in four runs); with the current one the DelphiLSP set: block completion and templates followed exactly this set in two swapped runs, the Code Insight dialog shows its values with the manager dpcc | `Code Insight\Borland.EditOptions.Pascal`; block completion, templates and opening after “.” followed exactly this set in two swapped runs |
| On exit | does not write the set back (a removed value stayed absent after exit); with OK in the options dialog the IDE writes it from memory | writes `Borland.EditOptions.Pascal` back |
| Consequence | Plugin and Server share one set. Block completion and templates apply as set for DelphiLSP; “Open automatically after the dot” turns the list after “.” off. | dpcc takes the IDE features once into gaps of this set (see [After updating](#after-updating)). |

Measured on 28 Nov 2026 in the test profile: Delphi 12 with dpcc as the provider and the current name, block
completion and templates off in the DelphiLSP set (on in `Borland.EditOptions.Pascal`): begin+Enter added no `end`,
todo+Space stayed `todo`; with swapped values the IDE added `end` and the template `{TODO …}`. The values dpcc sets in
Plugin operation (code completion, code parameters, tooltips) are read by the IDE at startup, as with Delphi 13; what
dpcc writes when switching applies after the next start of Delphi.

### Options in the Server mode

Location: `HKCU\<base>\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` (the DelphiLSP location, the
same under Delphi 12 and 13). Values as the strings `True`/`False`, as the IDE writes them.

| IDE option | Registry value | Expected | Reason |
|---|---|---|---|
| Code completion | `Auto Code Completions` | `True` | Off: no list opens after “.”. |
| Auto invoke | `Auto Invoke` | `True` | Off: the IDE does not invoke code completion after “.” by itself. |
| Code parameters: Auto invoke | `Auto Code Parameters` | `True` | Off: the parameter hint does not open on “(” and “,” by itself. |
| Tooltip symbol insight | `Declaration Information` | `True` | Off: the IDE does not ask `dpcc.LspServer.exe` when hovering an identifier. |

- The Server mode sets no other options. `Error Insight` and `ErrorInsightLevel` are left alone.
- Markers and the way back as in the Plugin mode (see [Markers and the way back](#markers-and-the-way-back)). The
  marker keeps the value from before dpcc's first change, even if dpcc had set the option in the Plugin mode before.
  Off restores this value.
- If a value or the key is missing, the IDE default (on) applies; dpcc then writes nothing and creates nothing.
- If you turn off one of the four options in the IDE's Code Insight dialog while the Server mode applies, the same rule
  applies as for the switches of the Plugin mode: dpcc turns it on again at the next reconciliation (check after OK on
  the dpcc page, exit or next start of Delphi). If there was no marker yet, dpcc records the turned-off value as the
  value before; Off then restores it.
- When it takes effect: dpcc writes the values to the registry, checks again after the dialog and writes them once
  more when Delphi exits, in case the IDE overwrote them from memory (as in the Plugin mode). The IDE reads them only
  at the next start of Delphi; dpcc uses no way to change them in the running IDE. If dpcc turned options on, the
  Messages window says so once (“For the server, dpcc turned on in the IDE's Code Insight options: …”).

### Check in the Off and Server modes

dpcc checks at startup. In the Off mode it changes nothing; in the Server mode it checks the four
[options for the server](#options-in-the-server-mode) it sets itself, plus `Error Insight`. The result is in the log
and in the [IDE](#ide) section of the page.

Off mode (with DelphiLSP, check only):

| IDE option | Registry value | Expected | Reason |
|---|---|---|---|
| Code completion | `Auto Code Completions` | `True` | Off: no list opens after “.” (see [Troubleshooting](troubleshooting.md#no-list-opens-after-the-dot)). |
| Auto invoke | `Auto Invoke` | `True` | Off: the IDE does not invoke code completion after “.” by itself (see [Troubleshooting](troubleshooting.md#no-list-opens-after-the-dot)). |
| Code parameters: Auto invoke | `Auto Code Parameters` | `True` | Off: no parameter hint by itself. |
| Error Insight | `Error Insight` | `True` (missing = on) | Off: the DelphiLSP error marks are missing in the editor. In the Server mode they stay empty anyway. |

#### Key locations per version

| | Delphi 12 (BDS 23.0) | Delphi 13 (BDS 37.0) |
|---|---|---|
| Off and Server modes (DelphiLSP) | `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` | `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` |
| Plugin mode | `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` (the same set as Off and Server) | each existing one of `Code Insight\Borland.EditOptions.Pascal` and `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` |

Delphi 12: since this version, dpcc names the DelphiLSP set as its option set there, and the IDE reads it for dpcc
(measured, see [IDE Code Insight](#ide-code-insight)). In the Plugin mode dpcc sets and checks exactly this set; under
Delphi 12 it no longer touches `Borland.EditOptions.Pascal`. Markers of earlier versions for
`Borland.EditOptions.Pascal` are cleaned up by the next reconciliation (“aufgeräumt (alter Ort)”): if the value is
still as dpcc wrote it, the value from before comes back, or it is deleted if there was none; otherwise it stays, and
only the marker is removed. Delphi 13: dpcc sets and checks each of the two locations that exists and creates none
that is missing; if both are missing, it uses the DelphiLSP location. In addition, dpcc hides the Help Insight window
at runtime (see [Switches in the Plugin mode](#switches-in-the-plugin-mode)).

Because Plugin and Server set the same set under Delphi 12, switching works like this (example: a user with code
completion and code parameters off, tooltips on, “Own tooltip” and “Show values while debugging” on):

| Switch | Code completion, code parameters | Symbol insight | Help Insight, expression evaluation | Markers afterwards (the user's value) |
|---|---|---|---|---|
| Off → Plugin | `True` | `False` | `False` | all five, plus `Insight Manager` |
| Plugin → Server | stay `True` (not back and forth) | `True` | back to `True` | code completion, code parameters, symbol insight |
| Server → Plugin | stay `True` | `False` | `False` | all five, plus `Insight Manager` |
| Plugin → Off, Server → Off | back to `False` | back to `True` | back to `True` | none |
| Off → Server | `True` | stays `True` | stay `True` | code completion, code parameters |

`Auto Invoke` is set to `True` in Plugin and Server (if the value is missing, on applies, and dpcc writes nothing).
Only Plugin also sets `Auto Invoke Delay` (-1), `AutoInvokeCompletionOnParameterInsight` (`False`) and the provider.
A start of Delphi in the same mode changes nothing.
If the checked key is missing entirely,
the result says “key missing (IDE default)”; this is not an error. The log line reads for example
“IDE-Einstellungen: 1 Abweichung: Auto Code Completions; Anbieter „Borland.CodeInsight.LSP.Pascal“, geprüft …”.

### Markers and the way back

- dpcc records every change under `HKCU\Software\dpcc\IdePlugin`, separately per version:
  `IdeSet <version> <key>\<value>` with the written value and the value before (or that there was none).
- With an own registry profile (`bds -r <profile>`) the markers are named `IdeSet <profile> <version> …`, the
  operating mode `OperatingMode <profile> <version>` and the marker of the one-time adoption `IdeAdopted <profile>
  <version> IdeFeatures`. So an IDE with an own profile neither reads nor changes the values of the default profile
  (`BDS`). In the default profile the names stay as before; existing markers still apply. Older markers (see below)
  apply only in the default profile.
- Only what is still as dpcc wrote it is reverted. If the user or the IDE has changed the value since, it stays; only
  the marker is removed. If the value did not exist before, dpcc deletes it again.
- A marker always keeps the value from before dpcc's first change, also across a switch between Plugin and Server. If
  the new mode needs the value as well, the marker stays; if it sets it differently, dpcc writes the new value to the
  marker and keeps the value before. Markers from earlier versions still apply unchanged.
- Older markers (`IdeHelpInsightDisabled …`, `IdeTooltipWatchesDisabled …`) still apply: at the next reconciliation
  dpcc reverts them or replaces them with the new ones.
- dpcc never switches Error Insight or structural highlighting.
- dpcc does not set `ErrorInsightLevel` either, not even in the Server mode.
- Before uninstalling: Off mode, OK, restart Delphi. Otherwise `dpcc.CodeInsight` stays selected as the
  provider and dpcc's switches stay in place.
- In addition, dpcc registers its own Code Insight manager and the key binding “dpcc Code Completion” for
  Ctrl+Space and Ctrl+Shift+Space. It removes both again when it is unloaded.
