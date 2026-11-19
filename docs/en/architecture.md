[Deutsch](../de/architecture.md) | English | [Français](../fr/architecture.md)

# Architecture

[Overview](index.md) › Architecture

## Overview

dpcc consists of a plugin (design-time package) and a completion server. Both run in the IDE process. They speak the
Language Server Protocol (LSP) over JSON-RPC. The connection consists of two memory pipes; there is no separate
server process.

```
IDE (bds.exe)
 ├─ dpcc.IDE.Base370.bpl      plugin: Open Tools API, keys, editor, options page
 │    ├─ dpcc.UI370.bpl       windows: list, tooltip, parameter hint, options page
 │    └─ dpcc.Core370.bpl     logic: LSP client, flow, ranking, settings
 │          │  LSP over JSON-RPC, two memory pipes
 │          ▼
 └─ dpcc.Server370.bpl        completion server on its own thread
      └─ dpcc.Common370.bpl   parser, name resolution, index, LSP features
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
| `dpcc.IDE.Base` | all of the above; `vcl`, `vclwinx`, `designide` | the plugin; the only design-time package |
| `dpcc.Completion.Tests` | links the DCUs | DUnitX test program |

All packages except `dpcc.IDE.Base` are runtime packages (`{$RUNONLY}`). All eight carry the package version as a
suffix (`{$LIBSUFFIX AUTO}`: `370` under Delphi 13, `290` under Delphi 12), the names in `requires` do not. The
order in `dpcc_d13.groupproj` (Delphi 12: `dpcc_d12.groupproj`, without tests) follows the dependencies.

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
| `Index` | symbol index with a catalog of all units, loading on demand and eviction of the library, usage statistics; unit lookup; cache on disk (format 35: one block per unit, directory at the end); extractor with target types, attributes, DLL details and constraints in the directives; full signature from the source (`TIndexFiles.SourceSignature`) |
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
| `Completion` | flow of the list (`TDpccCompletionController`), filtering, ranking, favorites, history, set mode, placeholders |
| `Hover`, `Signature`, `Documentation` | contents of tooltip and parameter hint, XMLDoc rendering |
| `Settings` | plugin settings (`TDpccPluginSettings`: exactly the values of the page, plus two read-only ones), storage in the registry and `settings.json` (`dpcc.Core.Settings.Scopes`), layout of the options page and fixed values (`dpcc.Core.Settings.CompletionView`), master switch without restart |
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
| `Completion` | composition root `dpcc.IDE.Completion.Register`, completion in the editor (chain State → Open → Commit → Editor), placeholders, favorites, history, save notifier |
| `CodeInsight` | Code Insight manager (chain State → Session → Commands → Crashes → Manager) |
| `Hover` | tooltip in the editor, values via the debugger |
| `Signature` | parameter hint in the editor, colors of the Format placeholders |
| `Forms` | forms from the designer to the server |
| `Projects` | project context from the IDE |
| `Settings` | registration of the options page |
| `Foundation` | settings in the registry and `settings.json`, IDE switches, keyboard hook, editor access, splash screen |

## Registration and shutdown

`dpcc.IDE.Completion.Register` is the composition root. `Register` registers, one after the other: safety fuse and
log, language, splash screen, mode (IDE context), Code Insight manager, key binding, forms, save notifier, master
switch, options page. Each step runs on its own; an error costs only that step and is written to the log.

The mode (dpcc is the Code Insight provider or off) is decided by `dpcc.Core.Settings.IdeCheck` without the registry
(`TDpccIdeContext.Plan`: write actions and markers, `TDpccIdeCheck.Evaluate`: check); reading happens in
`dpcc.IDE.Foundation.IdeSettingsCheck`, writing in `dpcc.IDE.Foundation.InsightSwitch` (at startup before the
manager, after OK in the options dialog, on the choice in the IDE's Code Insight dialog via
`IOTACodeInsightManagerEnvOptions` and on exit). See [Settings](settings.md#what-dpcc-changes-in-the-ide).

`Unregister` shuts down in reverse order, also step by step. It runs when the IDE's main window is destroyed or in
finalization, whichever comes first. At the end, the line “dpcc entladen in n ms …” (dpcc unloaded in n ms …) is in
the log.

## Flow: Ctrl+Space

1. The key binding `TDpccCompletionKeys` intercepts Ctrl+Space. If dpcc does not serve the file, the key stays with
   the IDE.
2. `TDpccCodeInsightManager.OpenCompletion` starts the session and the server if needed.
3. `TDpccEditorCompletion` takes the word before the cursor as the prefix and the caret rectangle as the anchor.
4. The session sends the current editor text (the first time `didOpen`, after that `didChange` with the changed
   range) and then `textDocument/completion`. This happens for all sources (server, XMLDoc) at the same time on worker
   threads; the main thread does not wait for it when the list opens.
5. The server determines the context, checks the completion cases in a fixed order and returns entries, in parts for
   large lists.
6. `TDpccCompletionController` filters and sorts locally; the popup from `dpcc.UI` draws only the visible rows.
7. Typing on filters locally. dpcc requests truncated lists again in the background.
8. Accepting writes the name, the `uses` entry and further changes in one undo step. If the entry has a command, it
   goes to the server in the background.

Hover and parameter hint run the same way through the session (`textDocument/hover`, `textDocument/signatureHelp`).
The tooltip is not triggered by the IDE but by the mouse movement, via the Code Editor API.

Ctrl+click and “Find Declaration” only reach dpcc if it is the selected Code Insight provider: the IDE calls the
manager's `GotoDefinition`. It syncs the buffer and asks `textDocument/declaration` through
`TLspSession.GotoTargetAt` in a background thread (on the declaration itself then `textDocument/definition`). The
main thread waits at most 250 ms. Without a target it answers True with an empty file name, and the IDE then cancels
silently. If the answer comes later, it answers just as silently; dpcc then jumps by itself, provided the same file is
active, the caret is still at the starting point, no newer jump request came and at most 3 seconds have passed. The
IDE's symbol hint (`GetHintText`, only without dpcc's own tooltip) also waits at most 250 ms; a later answer is kept
for a few seconds so that the next hint on the same word appears at once. The rules for this are in
`dpcc.Core.Editor.Navigation` and `dpcc.Core.Lsp.LateAnswers`.

## Robustness

- **Safety fuse** (`dpcc.Core.Diagnostics.Guard`): Every entry point from the IDE runs through `TDpccGuard.Run`.
  Exceptions never leave dpcc towards the IDE. Three errors of a feature within five minutes switch off only that
  feature until the IDE is restarted.
- **Queue to the main thread** (`dpcc.Core.Diagnostics.MainThread`): Every entry belongs to its own owner; on
  unloading, waiting entries are discarded so that nothing runs in unloaded code.
- **Server crashes** (`dpcc.IDE.CodeInsight.Manager.Crashes`): restart; after two identical crashes within ten
  minutes, no more automatic restart.
- **Log**: rotating, anonymized, with a lock across several IDE instances. A dedicated thread writes the lines
  (`dpcc.Core.Diagnostics.LogWriter`); whoever logs never waits for the file. On unload it still writes what is
  pending (at most 1 s), last the line “dpcc entladen”.

## Texts and language

Texts are in tables `cTexts: array[TDpccLanguage, …]` with German and English side by side, in `dpcc.UI` in separate
units per feature (`dpcc.UI.Strings`, `dpcc.UI.Completion.Strings`, `dpcc.UI.Settings.Strings` …). The IDE layer sets
the language at load time according to the language of the IDE; it is also passed to the server. Identifiers,
signatures, XMLDoc and log lines are never translated.
