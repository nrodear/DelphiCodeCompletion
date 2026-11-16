[Deutsch](../de/index.md) | English | [Français](../fr/index.md)

# dpcc – Documentation

dpcc (Delphi Pascal Code Completion) is a plugin for the Delphi IDE. It provides its own code completion, a
parameter hint and a tooltip over identifiers. For this, it builds its own index of the project, search paths and
library inside the IDE process.

Version 0.1.0, for Delphi 13 (RAD Studio 37.0), Win32.

## For users

| Page | Contents |
|---|---|
| [Installation](installation.md) | Requirements, building, installing, the IDE PATH, updating, uninstalling |
| [Usage](usage.md) | Keys, the list, what it offers, hover, parameter hint, placeholders, set mode, favorites |
| [Settings](settings.md) | Every option on the Tools › Options › Third Party › dpcc page, storage, what dpcc changes in the IDE |
| [Index and cache](index-cache.md) | What the index contains, where the cache is, rebuilding, cleanup |
| [Troubleshooting](troubleshooting.md) | Plugin does not load, list missing, duplicate tooltips, logs |

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
| List that opens by itself after “.” | Typing “.” | DelphiLSP (IDE) |

dpcc serves files with the extensions `.pas`, `.dpr`, `.dpk` and `.inc`. In all other files, and when the master
switch is off, the IDE stays in charge.

## License

MIT, see [LICENSE](../../LICENSE).
