[Deutsch](../de/index.md) | English | [Français](../fr/index.md)

# dpcc – Documentation

dpcc (Delphi Pascal Code Completion) is a plugin for the Delphi IDE. It provides its own code completion, a
parameter hint and a tooltip over identifiers. For this, it builds its own index of the project, search paths and
library inside the IDE process.

Version 0.1.0, for Delphi 13 (RAD Studio 37.0), Win32. For Delphi 12 (RAD Studio 23.0) there is a separate
project group without tests, see [Building for Delphi 12](installation.md#building-for-delphi-12).

## For users

| Page | Contents |
|---|---|
| [Installation](installation.md) | Requirements, building, installing, the IDE PATH, updating, uninstalling |
| [Usage](usage.md) | Keys, the list, what it offers, hover, parameter hint, placeholders, set mode, favorites |
| [Settings](settings.md) | Every option on the Tools › Options › Third Party › dpcc page, storage, what dpcc changes in the IDE |
| [Index and cache](index-cache.md) | What the index contains, where the cache is, rebuilding, cleanup |
| [Troubleshooting](troubleshooting.md) | Plugin does not load, list missing, duplicate tooltips, logs |
| [LSP server](lsp-server.md) | dpcc.LspServer.exe: standalone language server over stdio, Server mode, command line, storage, what it does |

## For developers

| Page | Contents |
|---|---|
| [Architecture](architecture.md) | Packages, layers, in-process server, flow of a request |
| [Development](development.md) | Building in the IDE, tests, conventions, contributing |

## In short: what dpcc takes over

| Feature | Trigger | Provided by |
|---|---|---|
| Completion | Ctrl+Space | dpcc |
| Parameter hint | Ctrl+Shift+Space | dpcc |
| Tooltip over identifiers | Mouse rests over an identifier | dpcc |
| List that opens by itself after “.” | Typing “.” | dpcc if it is the Code Insight provider (Plugin mode); otherwise DelphiLSP (IDE), and dpcc is off |

The table applies to the Plugin mode (default). dpcc serves files with the extensions `.pas`, `.dpr`, `.dpk` and
`.inc`. In all other files and in the Off mode, the IDE stays in charge. In the Server mode the IDE shows its own
windows, and the answers come from `dpcc.LspServer.exe` (see [LSP server](lsp-server.md#server-mode)).

## License

MIT, see [LICENSE](../../LICENSE).
