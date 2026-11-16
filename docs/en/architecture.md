[Deutsch](../de/architecture.md) | English | [Français](../fr/architecture.md)

# Architecture

[Overview](index.md) › Architecture

## Overview

dpcc consists of a plugin (design-time package) and a completion server. Both run in the IDE process. They speak the
Language Server Protocol (LSP) over JSON-RPC. The connection consists of two memory pipes; there is no separate
server process.

```
IDE (bds.exe)
 ├─ dpcc.IDE.Base370.bpl   plugin: Open Tools API, keys, editor, options page
 │    ├─ dpcc.UI.bpl       windows: list, tooltip, parameter hint, options page
 │    └─ dpcc.Core.bpl     logic: LSP client, flow, ranking, settings
 │          │  LSP over JSON-RPC, two memory pipes
 │          ▼
 └─ dpcc.Server.bpl        completion server on its own thread
      └─ dpcc.Common.bpl   parser, name resolution, index, LSP features
```

The IDE's main thread never waits for the server. Writing only puts a message into the pipe; a reader thread passes
the responses on to the client, and results reach the main thread through a separate queue.

## Packages

| Package | `requires` (apart from RTL/VCL) | Purpose |
|---|---|---|
| `dpcc.Text` | – | text helpers without Windows: lines, characters, encoding, fuzzy matching, JSON, URIs, version |
| `dpcc.WinBase` | – | process helpers via the Windows API |
| `dpcc.Common` | Text | language core and server features, free of Windows and VCL |
| `dpcc.Windows` | WinBase, Common | Windows-specific adapters: file watcher, paths, Delphi installation, debug output |
| `dpcc.Server` | Text, WinBase, Common, Windows | shell of the completion server; sources in `Application\Source\Shell` |
| `dpcc.Core` | Text, WinBase, Common, Windows, Server | plugin logic, without VCL and ToolsAPI |
| `dpcc.UI` | Text, WinBase, Common, Windows, Server, Core; `vcl` | VCL user interface, without ToolsAPI |
| `dpcc.IDE.Base` | all of the above; `vcl`, `vclwinx`, `designide` | the plugin; the only design-time package, suffix by version (`370`) |
| `dpcc.Completion.Tests` | links the DCUs | DUnitX test program |

All packages except `dpcc.IDE.Base` are runtime packages (`{$RUNONLY}`). The order in `dpcc_d13.groupproj` follows
the dependencies.

### Layer rules

- Dependencies point only downwards in the table.
- `dpcc.Common` and `dpcc.Text` need neither Windows units nor VCL.
- `dpcc.Core` knows neither VCL nor ToolsAPI. What it needs from the IDE it gets through interfaces and hooks that
  `dpcc.IDE.Base` sets.
- `dpcc.UI` knows the VCL, but not the ToolsAPI.
- Only `dpcc.IDE.Base` talks to the IDE.

## dpcc.Common

| Folder | Contents |
|---|---|
| `Pascal` | lexer, parser, syntax tree, preprocessor, include files, XMLDoc, format routines |
| `Semantics` | name resolution: types, overloads, generics, class helpers, `with`, visibility |
| `Index` | symbol index, unit lookup, cache on disk |
| `Projects` | reading `.dproj`, project groups and packages; unit lookup |
| `Dfm` | form files |
| `Lsp` | completion, hover, parameter hint, document synchronization, lifecycle |
| `JsonRpc` | messages, transport, dispatcher, worker pool, watchdog |
| `Configuration` | `settings.json` and `dpcc.json`: reading, key locations, defaults |
| `Documents`, `Editing` | documents, encoding, text snippets such as postfix templates and field names |

## Server (dpcc.Server)

The sources are in `Application\Source\Shell`.

| Unit | Purpose |
|---|---|
| `Shell.Composition.InProcess` | starts the server on its own thread in the IDE process, connects the memory pipes, shuts it down in a fixed order |
| `Shell.Composition.CompletionServer` | composition root of the server: wires up protocol, session, documents, index, completion, hover and parameter hint |
| `Shell.Composition.Configuration` | watches `settings.json` and `dpcc.json` |
| `Shell.Workspace.*` | workspaces: loading projects, building the index, locking and cleaning up the cache |

The server has no diagnostics, no compiler, no refactorings and no commands; it serves only completion, hover and
the parameter hint.

If the server hangs during unloading, `Shell.Composition.InProcess` keeps the code of `dpcc.Server` and its
dependencies loaded until the IDE exits. This way no thread jumps into unloaded code.

## dpcc.Core

| Folder | Contents |
|---|---|
| `Lsp` | LSP client, session (initialize, document synchronization, requests), adapter to the in-process server, crash handling |
| `Completion` | flow of the list (`TDpccCompletionController`), filtering, ranking, favorites, history, set mode, placeholders, preview |
| `Hover`, `Signature`, `Documentation` | contents of tooltip and parameter hint, XMLDoc rendering |
| `Settings` | plugin settings, catalog, locks, visible options (`dpcc.Core.Settings.CompletionView`) |
| `Diagnostics` | safety fuse (`TDpccGuard`), log, queue to the main thread, shutdown |
| `Localization` | language of the texts |

## dpcc.UI

| Folder | Contents |
|---|---|
| `Completion` | list (popup), drawing, texts |
| `Hover` | tooltip |
| `Signature` | parameter hint |
| `Settings` | options page “dpcc” |
| `Popup`, `Documentation` | shared window base, accessibility, XMLDoc view |

## dpcc.IDE.Base

| Folder | Contents |
|---|---|
| `Completion` | composition root `dpcc.IDE.Completion.Register`, completion in the editor (chain State → Open → Commit → Editor), placeholders, preview, favorites, history, save notifier |
| `CodeInsight` | Code Insight manager (chain State → Session → Commands → Crashes → Manager) |
| `Hover` | tooltip in the editor, values via the debugger |
| `Signature` | parameter hint in the editor, colors of the Format placeholders |
| `Forms` | forms from the designer to the server |
| `Projects` | project context from the IDE |
| `Settings` | registration of the options page |
| `Foundation` | settings in the registry and `settings.json`, IDE switches, keyboard hook, editor access, splash screen |

## Registration and shutdown

`dpcc.IDE.Completion.Register` is the composition root. `Register` registers, one after the other: safety fuse and
log, language, splash screen, Code Insight manager, key binding, forms, save notifier, Help Insight reconciliation,
master switch, options page. Each step runs on its own; an error costs only that step and is written to the log.

`Unregister` shuts down in reverse order, also step by step. It runs when the IDE's main window is destroyed or in
finalization, whichever comes first. At the end, the line “dpcc entladen in n ms …” (dpcc unloaded in n ms …) is in
the log.

## Flow: Ctrl+Space

1. The key binding `TDpccCompletionKeys` intercepts Ctrl+Space. If dpcc does not serve the file, the key stays with
   the IDE.
2. `TDpccCodeInsightManager.OpenCompletion` starts the session and the server if needed.
3. `TDpccEditorCompletion` takes the word before the cursor as the prefix and the caret rectangle as the anchor.
4. The session sends the current editor text (the first time `didOpen`, after that `didChange` with the changed
   range) and then `textDocument/completion`.
5. The server determines the context, checks the completion cases in a fixed order and returns entries, in parts for
   large lists.
6. `TDpccCompletionController` filters and sorts locally; the popup from `dpcc.UI` draws only the visible rows.
7. Typing on filters locally. dpcc requests truncated lists again in the background.
8. Accepting writes the name, the `uses` entry and further changes in one undo step.

Hover and parameter hint run the same way through the session (`textDocument/hover`, `textDocument/signatureHelp`).
The tooltip is not triggered by the IDE but by the mouse movement, via the Code Editor API.

## Robustness

- **Safety fuse** (`dpcc.Core.Diagnostics.Guard`): Every entry point from the IDE runs through `TDpccGuard.Run`.
  Exceptions never leave dpcc towards the IDE. Three errors of a feature within five minutes switch off only that
  feature until the IDE is restarted.
- **Queue to the main thread** (`dpcc.Core.Diagnostics.MainThread`): Every entry belongs to its own owner; on
  unloading, waiting entries are discarded so that nothing runs in unloaded code.
- **Server crashes** (`dpcc.IDE.CodeInsight.Manager.Crashes`): restart; after two identical crashes within ten
  minutes, no more automatic restart.
- **Log**: rotating, anonymized, with a lock across several IDE instances.

## Texts and language

Texts are in tables `cTexts: array[TDpccLanguage, …]` with German and English side by side, in `dpcc.UI` in separate
units per feature (`dpcc.UI.Strings`, `dpcc.UI.Completion.Strings`, `dpcc.UI.Settings.Strings` …). The IDE layer sets
the language at load time according to the language of the IDE; it is also passed to the server. Identifiers,
signatures, XMLDoc and log lines are never translated.
