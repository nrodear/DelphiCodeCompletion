[Deutsch](../de/lsp-server.md) | English | [Français](../fr/lsp-server.md)

# LSP server (dpcc.LspServer.exe)

[Overview](index.md) › LSP server

`dpcc.LspServer.exe` is dpcc as a standalone language server. It speaks the Language Server Protocol over
stdin/stdout and takes the place of `DelphiLSP.exe` in the Delphi IDE. Inside runs the same server as in the plugin
(index, completion, hover, parameter help, jump targets); on top come the structure view and the format the IDE
expects.

The plugin integrates it into the IDE: in the [Server mode](#server-mode). The plugin's built-in server (Plugin mode)
and the EXE never work at the same time.

## What it does

| Request | Result |
|---|---|
| `textDocument/completion`, `completionItem/resolve` | list with kind, name and signature like DelphiLSP |
| `textDocument/hover` | declaration and documentation; for RAD Studio as HTML like DelphiLSP (see below) |
| `textDocument/signatureHelp` | signatures with the current parameter |
| `textDocument/definition`, `declaration`, `typeDefinition` | jump to implementation, declaration, type |
| `textDocument/implementation` | RAD Studio only: same target as `definition` |
| `textDocument/documentSymbol` | structure view: sections, types with fields, properties and methods, routines |
| `didOpen`, `didChange` (full text or ranges), `didClose` | documents in memory |
| `workspace/didChangeConfiguration` | project data of the IDE, see below |

Whatever it cannot do it answers with error -32601 (method not found), for example `textDocument/references`
(for clients other than RAD Studio also `textDocument/implementation`). There are no code diagnostics (Error Insight stays empty) and no forwarding to
DelphiLSP.

## Command line

```
dpcc.LspServer.exe [--cache-root <folder>] [--log-level debug|info|warning|error] [--no-log] [--version] [--help]
```

Other parameters are ignored. The server answers `initialize` at once and loads project and index in the
background; until the index is ready, answers are empty or incomplete instead of waiting for it. It ends after
`exit` (as a notification or as a request with an id), at the end of the input, or when the process from
`processId` in `initialize` ends. The working directory does not matter.

The EXE exists for Win32 and Win64; both serve Delphi 12 and Delphi 13. It depends on no BPL. The 32-bit IDE also
starts the 64-bit EXE.

## Server mode

In the Server mode the IDE stays in LSP mode (provider DelphiLSP) and shows its own windows: list, hint, tooltip on
hover, Structure view and Ctrl+click. When it starts `DelphiLSP.exe`, the plugin starts `dpcc.LspServer.exe` instead,
with the same parameters; flags, handles, environment and working directory stay as the IDE sets them. For this the
plugin redirects the call to `kernel32!CreateProcessW` in the module `IDELSP290.bpl` (Delphi 12) or `IDELSP370.bpl`
(Delphi 13) inside the running IDE (hook in the import table). It changes nothing in the Delphi program folder and
needs no administrator rights.

### Turning it on

1. Provide the EXE: select the component “LSP server” in the setup (default), put it from the ZIP into one of the
   [locations](#where-dpcc-looks-for-the-exe) or build it yourself (see [Installation](installation.md#lsp-server)).
2. **Tools › Options › Third Party › dpcc**, select the mode “Server – dpcc.LspServer.exe instead of DelphiLSP” and
   close with **OK**. dpcc sets the IDE's Code Insight provider to DelphiLSP and turns on the four Code Insight
   options without which the IDE does not ask the server: code completion (`Auto Code Completions`), auto invoke
   (`Auto Invoke`), code parameters (`Auto Code Parameters`) and tooltip symbol insight (`Declaration Information`).
   When switching to Off it sets them back to the previous values. Nothing needs to be turned off in the IDE's Code
   Insight dialog for the server. Details: [Settings](settings.md#options-in-the-server-mode).
3. If the change came from Plugin (or another provider was selected), restart Delphi. If it came from Off, close the
   project group and open it again: the IDE starts its server when the first unit of a project group is shown, one
   per group, and a running server stays until the group is closed. If dpcc turned on one of the four options in the
   process (the Messages window names them), it only applies after the next start of Delphi: the IDE reads these
   options only at startup.

The mode applies per Delphi version (see [Settings](settings.md#operating-mode)). Each time DelphiLSP starts, the
hook reads it fresh from the registry; so going back to the original DelphiLSP means “Off” and opening the project
group again. If the EXE is missing, “Server” is grayed out on the page with the note “Not available:
dpcc.LspServer.exe is not installed …”. If Server is already selected, it stays selected, and the start falls back
to the original DelphiLSP. The hint on the radio button names the location found.

### Where dpcc looks for the EXE

Relative to the loaded plugin, in this order; on 64-bit Windows the 64-bit EXE (`win64`, `Win64`) comes first each
time, then the 32-bit EXE:

| Layout | Plugin | EXE |
|---|---|---|
| Setup | `{app}\bpl\d12` or `{app}\bpl\d13` (`{app}` = `%LOCALAPPDATA%\Programs\dpcc`) | `{app}\server\win64\dpcc.LspServer.exe`, then `{app}\server\win32\dpcc.LspServer.exe` |
| own build | `Output\Win32\<configuration>\Bpl` | `Output\Win64\<configuration>\Bin`, as a fallback `Output\Win64\Debug\Bin` and `Output\Win64\Release\Bin`, then the same under `Output\Win32` |
| last | any | next to the plugin, for example put there from the ZIP |

For your own build under Delphi 12 (configuration D12) this means: first `Output\Win64\D12\Bin`, then
`Output\Win64\Debug\Bin` and `…\Release\Bin`, then the same under `Output\Win32`.

### Log

Each step is a line in `dpcc.log` (`%LOCALAPPDATA%\dpcc\Logs`; log lines are always German):

| Line | Meaning |
|---|---|
| `LSP-Umleitung: Hook beim Anmelden (37.0): 1 Eintrag/Einträge in IDELSP370.bpl umgebogen; Betriebsart jetzt Server; EXE: …` | The hook is in place. If `IDELSP` was not loaded yet at registration, dpcc installs it later (“Hook nachgeholt nach n ms …”, for at most 5 minutes). |
| `LSP-Umleitung: #1 DelphiLSP umgeleitet auf <EXE> (PID n)` | The IDE started its server; `dpcc.LspServer.exe` was started. |
| `LSP-Umleitung: #2 Start von DelphiLSP nicht umgeleitet (<Grund>)` | The original DelphiLSP starts. Reasons: `Betriebsart Aus`, `Betriebsart Plugin`, `dpcc.LspServer.exe nicht gefunden`, `dpcc.LspServer.exe fehlt: <Pfad>`. |
| `LSP-Umleitung: #3 Start von dpcc.LspServer.exe fehlgeschlagen (Fehler n), Originalaufruf` | The EXE could not be started (Windows error code n); the original DelphiLSP starts instead. |
| `LSP-Umleitung: Hook abgebaut: …` | When the plugin is unloaded, also in the running IDE. After that the original starts again. |
| `Eingebauter Server: startet nicht (Betriebsart Server)` | When the plugin registers: in the modes Off and Server the built-in server does not start in this session (with Plugin: `… startet bei Bedarf (Betriebsart Plugin); keine Umleitung von DelphiLSP`). |
| `Eingebauter Server nicht gestartet: …` | The plugin's built-in server stays off, with the reason (mode or an earlier redirection, see below). |

The EXE's own log is in its [storage](#storage).

### Mutual exclusion

- The plugin's built-in server starts only in the Plugin mode.
- Once the hook has redirected to `dpcc.LspServer.exe` in this IDE session, the built-in server does not start until
  Delphi is restarted, even if Plugin is selected afterwards.
- In the Plugin mode the hook never redirects; the IDE does not call DelphiLSP then anyway.

### Limits

- Error Insight stays empty: the server delivers no code diagnostics. dpcc does not set `ErrorInsightLevel`.
- Apart from the four Code Insight options from [Turning it on](#turning-it-on), the Server mode changes nothing in
  the IDE.
- Not supported: the 64-bit IDE of Delphi 13 (`bin64\bds.exe`, `Known Packages x64`). The plugin is 32-bit and does
  not load there.
- If the EXE is missing or fails to start, the original DelphiLSP starts; one line goes to the log.
- The Delphi 12 crash when showing a unit with a floating-point number does not occur in LSP mode (see
  [Troubleshooting](troubleshooting.md#delphi-12-crash-when-showing-a-unit-with-a-floating-point-number)).

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

If the client calls itself `RAD Studio` in `initialize`, the server answers in the form of the original DelphiLSP
and sends no notifications of its own. Every other client gets standard LSP.

### Form of the answers for RAD Studio

Measured on 27.11.2026 in Delphi 12 and 13 against the original DelphiLSP (inside the running IDE); the IDE's
windows thus look as they do with the original, only the content may differ.

| Request | Form |
|---|---|
| hover | `contents` is **one** HTML string in the Help Insight frame (`HelpInsight.css`): a heading such as `function TProbe.Twice(const A: Integer): Integer`, a link `file (line)`, then summary, parameters, returns and remarks from the XMLDoc. Earlier versions sent plain text here, which the IDE rendered as HTML (lines ran together). |
| signatureHelp | one entry per parameter with its type (`A: Integer`, groups such as `A, B: Integer` resolved), `documentation` as HTML (`kind` html), per parameter `kind` xml |
| definition, declaration, typeDefinition, implementation | **one** Location object (no array); open files with the same URI spelling as in `didOpen`; definition and implementation on a library routine jump to its body like DelphiLSP |
| completion | `kibitzkind` 2 after `.`, 7 without a dot, 15 in the uses clause; `sortText` hexadecimal; overloads as separate entries; `kind`, `detail` and `DCC_Flags` per symbol kind like DelphiLSP; inactive `{$IFDEF}` branches are left out; the whole list (up to 5000 entries) instead of the first 1000; with the IDE's `enableKeyWordCompletion` the keywords at the end of the identifier list (kind 14, `sortText` `k000` …) |
| completionItem/resolve | the same entry as in the list, including `DCC_Flags`, without `documentation` |
| documentSymbol | with a uses section and its units; enums and type aliases like records (kind 23), constructors like methods (kind 6), property with its access part as `detail` |

Known differences in content: the heading of the parameter help does not name the class or unit (`function Add(…)` instead of `function TProbe.Add(…)`; not visible in the IDE's parameter hint); the uses clause list only holds units with source (no plain namespaces such as `System`, no units that exist only as .dcu), the identifier list no qualified class members such as `TThread.Queue`.

Delphi version: the server takes the version of the IDE that starts it (from `processId` in `initialize`) even before its project data, also when the .dproj was last saved by another version. It neither keeps units of another installation in the index nor takes them from a cache, except folders the project itself names (as in the plugin, see [Index and cache](index-cache.md#other-delphi-installations)); in earlier versions Delphi 12 could jump into the Delphi 13 sources this way, for example for `TStringList`. The body of a library routine for definition and implementation comes from the shared core, in the plugin as in the server.

## See also

- [Settings › Operating mode](settings.md#operating-mode)
- [Architecture](architecture.md): server, index and the path of a request
- [Index and cache](index-cache.md)
