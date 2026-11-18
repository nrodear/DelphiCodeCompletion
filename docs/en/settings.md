[Deutsch](../de/settings.md) | English | [Français](../fr/settings.md)

# Settings

[Overview](index.md) › Settings

The options are under **Tools › Options › Third Party › dpcc**. This is a single page without subpages.

## The page

- The master switch is at the top, followed by the sections **Completion**, **When accepting**, **Parameter hint
  and tooltip** and **Index**.
- If the master switch is off, all options below it and the “Reset history” button are grayed out. “Rebuild index”
  remains available.
- “Show values while debugging” is grayed out as long as “Own tooltip when hovering identifiers” is off.

Settings are saved with **OK**. Exceptions: “Reset history” and “Rebuild index” take effect immediately.

Some former options are no longer on the page and have fixed values (see [Fixed values](#fixed-values)).

The “Registry value” column gives the name under `HKCU\Software\dpcc\IdePlugin`, the “Key” column the name that dpcc
uses in hints and in `settings.json`. “–” under “Registry value”: the option is not stored in the registry but in
`settings.json` (see [Storage](#storage)).

## Master switch

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Code Insight by dpcc (off: built-in Code Insight of the IDE) | `Enabled` | `completion.enabled` | on | Master switch. Off: dpcc closes its list, parameter hint and tooltip; Ctrl+Space and Ctrl+Shift+Space go to the IDE. On: dpcc starts the session and the server if they are not running. Takes effect without restarting the IDE. The server keeps running when switched off. |

## Completion

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Open on typing from characters (0 = never): | `AutoMinChars` | `completion.autoMinChars` | 0 | 0 to 10; default 0 = off (as before opening while typing existed), to switch it on set e.g. 5. When you type a name without a dot before it, the list opens only once the word before the cursor has this many characters; below that dpcc does not ask the server. 0 = typing never opens it. Ctrl+Space opens it at any length; nothing changes after “.” and for the other triggers. Also works with DelphiLSP as the selected provider. See [Usage](usage.md#opening-while-typing). |
| While typing, show: | `CompletionListMode` | `completion.listMode` | Only matches | “Only matches” (`filter`), “All entries, matches on top” (`all`), “Matches, then the rest dimmed” (`rest`, under the heading “More entries”). Applies to member lists after “.” (fixed). |
| Visible rows of the list: | `VisibleRows` | `completion.visibleRows` | 9 | 5 to 20 rows. |
| Automatic width | `ListWidth` | `completion.listWidth` | on (`ListWidth` = 0) | In the same row as “Visible rows of the list”. On: the list grows with the widest entry. Off: the width last dragged (240 to 720). Dragging the right edge of the list also sets the width. |
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
| Own tooltip when hovering identifiers | `HoverTooltip` | `editor.hoverTooltip` | on | dpcc tooltip. As long as it is on, dpcc switches off the IDE's Help Insight. Locked as long as the master switch is off. |
| Show values while debugging (turns off the IDE's value tooltip) | `DebugHoverValues` | `debug.hoverValues` | on | Indented below the tooltip. While the program is paused, the value of the expression is shown at the top of the tooltip. If you want the IDE's value tooltip, switch this option off. Locked as long as “Own tooltip …” is off. |

## Index

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Additional source folders (separated by “;”, including subfolders): | – | `index.extraSourceFolders` | empty | Folders with the source code of libraries that otherwise only exist as `.dcu` (DUnitX, DUnit, FireDAC, components). Subfolders count too (without `.git`, `__history`, `__recovery`); `$(Name)` and `%Name%` are resolved. “+ Unit” suggests their units; they are loaded on demand and have a cache of their own. Stored in `%APPDATA%\dpcc\settings.json` (in the file also as a list), not in the registry; the server rebuilds the index without a restart. Replaces the former switch `index.officeAndWinRt`: the Office type libraries and WinRT are always in the catalog. See [Index and cache](index-cache.md#additional-source-folders). |
| Button “Rebuild index” | – | – | – | Asks for confirmation, deletes all index caches and rebuilds the index. Does not depend on the master switch. See [Index and cache](index-cache.md#rebuilding-the-index). |

## Fixed values

These options are no longer on the page. They have fixed values, the former defaults:

- **Delay before automatic opening (for example after “.”): 150 ms** (`OpenDelayMs`, `completion.openDelayMs`).
  Applies only to automatic opening, not to Ctrl+Space. With DelphiLSP as the selected provider it only applies to
  opening while typing, which dpcc triggers itself (see [Usage](usage.md#interaction-with-delphilsp)).
- **Pin favorites with Ctrl+D: on** (`Favorites`, `completion.favorites`). Ctrl+D in the open list pins or unpins;
  the favorites are still stored in `%APPDATA%\dpcc\favorites.json`. See [Usage](usage.md#favorites).
- **Inherited members ranked lower and grouped by class: on** (`GroupInherited`, `completion.groupInherited`).
  Without a typed prefix: own members first, then one group “Inherited from …” per ancestor. With a prefix, at equal
  match quality the own member comes before the inherited one.
- **Show the branch of variant record fields: on** (`CompletionVariantBranch`, `completion.variantBranch`). Fields
  in the variant part of a record (`case … of`) get the label “branch 0”, “branch 1” and so on.
- **List mode applies to: member lists after “.”** (`CompletionListScope`, `completion.listMode.scope` =
  `members`). “While typing, show” only takes effect there.
- **Preview of the selected entry in the editor: off** (`Preview`, `completion.preview`).
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

## Storage

| Location | Contents |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | all options on the page except `index.extraSourceFolders`. Switches and numbers as DWORD (switches 0/1), choices as text (`filter`, `all`, `rest`). Also the markers for the IDE switches (below) and `PathOverrideBackup` from `Tools\IdePath.ps1`. Old values of the fixed options stay in place but have no effect. |
| `%APPDATA%\dpcc\settings.json` | `index.extraSourceFolders` (from the page) and `hints.xmlDocMaxLines` (adjustable only in the file). The in-process server reads the file itself and watches it. The registry value `XmlDocMaxLines` from an older version is taken over once, as long as the file does not have the key yet; after that only `settings.json` applies. An old value `hints.xmlDocExpand` or `hints.xmlDocFull` has no effect. |
| `%APPDATA%\dpcc\settings-history.json` | earlier states of the settings; before every saved change, dpcc stores the old state there |
| `%APPDATA%\dpcc\usage.json` | history of the learned ranking |
| `%APPDATA%\dpcc\favorites.json` | pinned favorites |

dpcc moves an unusable `usage.json` or `favorites.json` aside as `….defekt` and starts empty. It does not overwrite a
locked file.

Everything back to default: close the IDE and delete the key `HKCU\Software\dpcc\IdePlugin` and `settings.json`.
Before that, turn off the master switch and confirm with OK, so that dpcc hands back the IDE switches (see below).

## What dpcc changes in the IDE

There is no Open Tools API for Help Insight and the debugger value tooltip. The switches are in the IDE's registry
and are read when the IDE starts. dpcc writes them there and records under `HKCU\Software\dpcc\IdePlugin` what it has
switched off itself. It switches only that back on.

| IDE switch | IDE registry value | dpcc switches it off as long as | dpcc reconciles | Marker |
|---|---|---|---|---|
| Help Insight | `Help Insight` | master switch on and “Own tooltip …” on | when the plugin loads, after every change of the settings and after OK in the options dialog | `IdeHelpInsightDisabled <version> <location>` |
| Tooltip expression evaluation (debugger value tooltip) | `ToolTip Watches` | master switch, tooltip and “Show values while debugging” on | only after OK in the dpcc options dialog | `IdeTooltipWatchesDisabled <version> <location>` |

- Location of the values: `HKCU\Software\Embarcadero\BDS\37.0\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal`
  (Delphi 13), plus every other subkey of `Code Insight` that already has the value.
- The IDE reads the values only at its next start. Until then, two tooltips may appear. The Messages window reports
  every change, for example “dpcc shows the tooltip itself and switched off the IDE's Help Insight; takes effect after
  the next start of Delphi.”
- The value tooltip is reconciled only after OK in the options dialog, because the IDE writes its editor options back
  from memory when the dialog is closed with OK. After installation it is therefore off only once the dpcc page has
  been closed with OK and the IDE has been restarted.
- dpcc does not change Error Insight, structural highlighting or the choice of the Code Insight provider.
- In addition, dpcc registers its own Code Insight manager and the key binding “dpcc Code Completion” for
  Ctrl+Space and Ctrl+Shift+Space. It removes both again when it is unloaded.
