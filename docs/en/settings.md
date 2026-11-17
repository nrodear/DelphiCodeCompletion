[Deutsch](../de/settings.md) | English | [Français](../fr/settings.md)

# Settings

[Overview](index.md) › Settings

The options are under **Tools › Options › Third Party › dpcc**. The page has the title “Completion, parameter hint
and tooltip by dpcc”.

## The page

- On the left, a tree with the areas **General**, **Completion**, **Insertion** and **Hints**.
- Above the tree, a search box “Search settings …”. Enter jumps to the first hit, arrow down moves into the list of
  hits.
- If a value differs from the default, a dot “●” appears before the label. A right-click offers “Reset to default”
  and “Reset the whole page to default”.
- At the bottom, the row “Filter:” with “All”, “Changed” and “Experimental only”. There are currently no
  experimental options on this page.
- If an option depends on another one, it is locked as long as the other one is off. The reason is shown next to
  it, for example “locked: “…” (…) is off”. All completion options and the tooltip depend on the master switch.

Settings are saved with **OK**. Exceptions: “Reset history”, “Remove” and “Remove all” for the favorites, and
“Rebuild index” take effect immediately.

The “Registry value” column gives the name under `HKCU\Software\dpcc\IdePlugin`, the “Key” column the name that dpcc
uses in hints and in `settings.json`. “–” under “Registry value”: the option is not stored in the registry but in
`settings.json` (see [Storage](#storage)).

## General

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Code Insight by dpcc (off: built-in Code Insight of the IDE) | `Enabled` | `completion.enabled` | on | Master switch. Off: dpcc closes its list, parameter hint and tooltip; Ctrl+Space and Ctrl+Shift+Space go to the IDE. On: dpcc starts the session and the server if they are not running. Takes effect without restarting the IDE. The server keeps running when switched off. |
| Button “Rebuild index” | – | – | – | Asks for confirmation, deletes all index caches and rebuilds the index. See [Index and cache](index-cache.md#rebuilding-the-index). |
| Additional source folders (separated by “;”, including subfolders; e.g. DUnitX sources) | – | `index.extraSourceFolders` | empty | Folders with the source code of libraries that otherwise only exist as `.dcu` (DUnitX, DUnit, FireDAC, components). Subfolders count too (without `.git`, `__history`, `__recovery`); `$(Name)` and `%Name%` are resolved. “+ Unit” suggests their units; they are loaded on demand and have a cache of their own. Stored in `settings.json` (in the file also as a list), not in the registry; the server rebuilds the index without a restart. Replaces the former switch `index.officeAndWinRt`: the Office type libraries and WinRT are always in the catalog. See [Index and cache](index-cache.md#additional-source-folders). |

## Completion

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Visible rows of the list: | `VisibleRows` | `completion.visibleRows` | 9 | 5 to 20 rows. |
| Automatic list width | `ListWidth` | `completion.listWidth` | on (`ListWidth` = 0) | On: the list grows with the widest entry. Off: the width last dragged (240 to 720). Dragging the right edge of the list also sets the width. |
| Delay before opening (ms): | `OpenDelayMs` | `completion.openDelayMs` | 150 | 0 to 2000; 0 = immediately. Applies only to automatic opening, not to Ctrl+Space. No effect with DelphiLSP as the selected provider (see [Usage](usage.md#interaction-with-delphilsp)). |
| Frequently and recently chosen entries first | `Learning` | `completion.learning` | on | Learned ranking: accepted entries get a bonus in the ranking. From 5 acceptances on, an entry counts as “frequent”. Stored in `%APPDATA%\dpcc\usage.json`, at most 5,000 entries. |
| Pin favorites (Ctrl+D) | `Favorites` | `completion.favorites` | on | Ctrl+D in the open list pins or unpins. See [Usage](usage.md#favorites). |
| Inherited members ranked lower and grouped by class | `GroupInherited` | `completion.groupInherited` | on | Without a typed prefix: own members first, then one group “Inherited from …” per ancestor. With a prefix, at equal match quality the own member comes before the inherited one. |
| Show the branch of variant record fields | `CompletionVariantBranch` | `completion.variantBranch` | on | Fields in the variant part of a record (`case … of`) get the label “branch 0”, “branch 1” and so on. |
| While typing, show: | `CompletionListMode` | `completion.listMode` | Only matches | “Only matches” (`filter`), “All entries, matches on top” (`all`), “Matches, then the rest dimmed” (`rest`, under the heading “More entries”). |
| Applies to: | `CompletionListScope` | `completion.listMode.scope` | Member lists after “.” | Where the list mode applies: “Member lists after “.”” (`members`) or “All lists” (`everywhere`). |
| Preview of the selected entry in the editor | `Preview` | `completion.preview` | off | The missing part of the selected name appears in italics and dimmed after the cursor. |
| Button “Reset history” | – | – | – | Clears the learned ranking immediately. |
| Button “Reset widths” | – | – | – | Sets the list width back to the default (automatic); saved with OK. |

### Pinned favorites (at most 5 per type)

Below the options is the list of pinned favorites. Without favorites it shows “No pinned favorites.”

| Button | Effect |
|---|---|
| Remove | unpins the selected favorites, immediately |
| Remove all | unpins all favorites, immediately |

The favorites are stored in `%APPDATA%\dpcc\favorites.json`.

## Insertion

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Add parentheses when accepting methods | `AutoParentheses` | `completion.autoParentheses` | on | Adds the parentheses; a “)” typed directly before it skips the automatic one. |
| Fix the case when accepting (showmessage → ShowMessage) | `FixCase` | `completion.fixCase` | on | Replaces the typed word with the spelling of the declaration. |
| Accept with "(", ";" and "." (commit characters) | `CommitCharacters` | `completion.commitCharacters` | on | If the selected entry is an unambiguous match, one of these characters accepts it; the character stays. Otherwise only the character remains, and the list closes. |
| Add the unit to uses automatically when accepting | `AutoUses` | `completion.autoUses` | on | For entries that show “+” and the name of a unit on the right (for example “+ System.SysUtils”), dpcc adds that unit to `uses`, in the same undo step. |
| Parameter hint on "(" and "," | `ParameterHints` | `completion.parameterHints` | on | Off: no dpcc parameter hint, not even via Ctrl+Shift+Space. Automatic opening on “(” and “,” reaches dpcc only if the IDE calls dpcc as the provider (see [Usage](usage.md#interaction-with-delphilsp)). |
| Match and colour Format placeholders in the parameter hint | `FormatPlaceholders` | `completion.formatPlaceholders` | on | Line for the placeholder at the cursor, warnings, same color for placeholder and argument. Locked as long as “Parameter hint on "(" and ","” is off. |

## Hints

| Option | Registry value | Key | Default | Effect |
|---|---|---|---|---|
| Own tooltip when hovering identifiers | `HoverTooltip` | `editor.hoverTooltip` | on | dpcc tooltip. As long as it is on, dpcc switches off the IDE's Help Insight. Locked as long as the master switch is off. |
| Values in the hover while debugging (turns off the IDE's value tooltip) | `DebugHoverValues` | `debug.hoverValues` | on | While the program is paused, the value of the expression is shown at the top of the tooltip. If you want the IDE's value tooltip, switch this option off. |
| XMLDoc when opened | – | `hints.xmlDocExpand` | as last time | “always collapsed” (`collapsed`), “as last time” (`last`), “always expanded” (`expanded`). In the current version the tooltip always shows the XMLDoc in full; the choice is saved but has no visible effect. Stored in `settings.json`, not in the registry. |
| XMLDoc: max. lines before scrolling (0 = screen) | – | `hints.xmlDocMaxLines` | 0 | 0 to 50. More lines scroll in the tooltip with the mouse wheel. 0: only the space on the screen limits it. Stored in `settings.json`, not in the registry. |

## Storage

| Location | Contents |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | all options except `hints.*`. Switches and numbers as DWORD (switches 0/1), choices as text (`filter`, `members` …). Also the markers for the IDE switches (below) and `PathOverrideBackup` from `Tools\IdePath.ps1`. |
| `%APPDATA%\dpcc\settings.json` | `hints.xmlDocExpand`, `hints.xmlDocMaxLines`, `index.extraSourceFolders`. The in-process server reads the file itself and watches it. Registry values `XmlDocExpand` and `XmlDocMaxLines` from an older version are taken over once, as long as the file does not have the keys yet; after that only `settings.json` applies. |
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
| Tooltip expression evaluation (debugger value tooltip) | `ToolTip Watches` | master switch, tooltip and “Values in the hover while debugging” on | only after OK in the dpcc options dialog | `IdeTooltipWatchesDisabled <version> <location>` |

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
