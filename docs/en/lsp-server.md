[Deutsch](../de/lsp-server.md) | English | [Français](../fr/lsp-server.md)

# LSP server (dpcc.LspServer.exe)

[Overview](index.md) › LSP server

`dpcc.LspServer.exe` is dpcc as a standalone language server. It speaks the Language Server Protocol over
stdin/stdout and can take the place of `DelphiLSP.exe` in the Delphi IDE. Inside runs the same server as in the
plugin (index, completion, hover, parameter help, jump targets); on top come the structure view and the format the
IDE expects.

The plugin keeps its built-in server. The EXE is a second, separate way to the same result.

## What it does

| Request | Result |
|---|---|
| `textDocument/completion`, `completionItem/resolve` | list with kind, name and signature like DelphiLSP |
| `textDocument/hover` | declaration and documentation as plain text |
| `textDocument/signatureHelp` | signatures with the current parameter |
| `textDocument/definition`, `declaration`, `typeDefinition` | jump to implementation, declaration, type |
| `textDocument/documentSymbol` | structure view: sections, types with fields, properties and methods, routines |
| `didOpen`, `didChange` (full text or ranges), `didClose` | documents in memory |
| `workspace/didChangeConfiguration` | project data of the IDE, see below |

Whatever it cannot do it answers with error -32601 (method not found), for example `textDocument/implementation` and
`textDocument/references`. There are no code diagnostics (Error Insight stays empty) and no forwarding to
DelphiLSP.

## Command line

```
dpcc.LspServer.exe [--cache-root <folder>] [--log-level debug|info|warning|error] [--no-log] [--version] [--help]
```

Other parameters are ignored. The server answers `initialize` at once and loads project and index in the
background; until the index is ready, answers are empty or incomplete instead of waiting for it. It ends after
`exit` (as a notification or as a request with an id), at the end of the input, or when the process from
`processId` in `initialize` ends. The working directory does not matter.

The EXE exists for Win32 and Win64; both serve Delphi 12 and Delphi 13. It depends on no BPL.

## Storage

| Order | Location |
|---|---|
| 1 | `--cache-root <folder>` |
| 2 | environment variable `DPCC_LSPSERVER_CACHE_ROOT` |
| 3 | `%LOCALAPPDATA%\dpcc.LspServer` |

Below it, as with the plugin, are `Index\<Delphi version>\…` (caches), `projektauswahl.json` and `Logs\Diagnose`
(anonymous diagnostic log), plus the log of the EXE in `Logs\LspServer\lsp-<date>-<process>.log` (one file per
process, deleted after 14 days). The plugin's folder (`%LOCALAPPDATA%\dpcc`) stays untouched; a `DPCC_CACHE_ROOT`
variable does not apply to the EXE. Settings are read like in the plugin from `%APPDATA%\dpcc\settings.json` and
`dpcc.json`, but never written.

The server writes caches to a temporary file and renames it; a hard end (the IDE kills the process after `shutdown`
without `exit`) therefore never leaves half a cache behind.

## Project data from the IDE

The IDE reports the active project via `workspace/didChangeConfiguration`. The server reads:

| Field | Use |
|---|---|
| `project` | main file (.dpr/.dpk); the .dproj next to it becomes a workspace unless the opened files already yield one |
| `dllname` | Delphi version (`dcc32290.dll` → 23.0, `dcc32370.dll` → 37.0) and platform (`dcc32` Win32, `dcc64` Win64) |
| `dccOptions` | `-D` symbols, `-NS` namespaces, `-U` paths: inside the installation or Studio folders as library, otherwise as project search path |
| `browsingPaths` | browsing path of the IDE (library sources) |
| `CommonAppData` | IDE profile (`bds -r`) whose variables and paths the server reads |

Without these data (other clients) the server derives projects from the opened files: the .dproj in the file's
folder or above.

## Clients

If the client calls itself `RAD Studio` in `initialize`, the server answers in the IDE's format (full text on
changes, completion with `kibitzkind` and `DCC_Flags`, parameter help with `documentation`, hover as plain text) and
sends no notifications of its own. Every other client gets standard LSP.

## See also

- [Architecture](architecture.md): server, index and the path of a request
- [Index and cache](index-cache.md)
