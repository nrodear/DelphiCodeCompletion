[Deutsch](../de/development.md) | English | [Français](../fr/development.md)

# Development

[Overview](index.md) › Development

## Requirements

- Delphi 13 / RAD Studio 37.0, Win32 platform.
- DUnitX for the tests; it comes with RAD Studio.

## Building

`dpcc_d13.groupproj` contains nine projects:

1. `Packages\dpcc.Text\dpcc.Text.dproj`
2. `Packages\dpcc.WinBase\dpcc.WinBase.dproj`
3. `Packages\dpcc.Common\dpcc.Common.dproj`
4. `Packages\dpcc.Windows\dpcc.Windows.dproj`
5. `Packages\dpcc.Server\dpcc.Server.dproj` (sources in `Application\Source\Shell`)
6. `Packages\dpcc.Core\dpcc.Core.dproj`
7. `Packages\dpcc.UI\dpcc.UI.dproj`
8. `Packages\dpcc.IDE.Base\dpcc.IDE.Base.dproj`
9. `Tests\dpcc.Completion.Tests.dproj`

Open the group in the IDE, select Win32 and Debug, and build all projects. The dependencies of the group determine
the order.

| Output | Folder |
|---|---|
| BPLs | `Output\Win32\Debug\Bpl` |
| DCPs | `Output\Win32\Debug\Dcp` |
| DCUs | `Output\Win32\Debug\Dcu\<project>` |
| Test program | `Output\Win32\Debug\Bin` |

**Command line:** The command-line compiler (`dcc32`, MSBuild) is locked in the Community and Starter editions of
Delphi. With these editions, build the group in the IDE.

If dpcc is installed in the same IDE, the IDE unloads the plugin while building. Restart the IDE after building.

Build output does not belong in the repository (`.gitignore`: `Output/`, `*.dcu`, `*.bpl`, `*.exe` …).

## Testing

`Tests\dpcc.Completion.Tests.dproj` is a DUnitX console program. After building:

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --exclude:Benchmark --exitbehavior:Continue
```

| Option | Meaning |
|---|---|
| `--exclude:Benchmark` | skips the measurements in the `Benchmark` category |
| `--exitbehavior:Continue` | does not wait for Enter at the end |

- Exit code 0 if all tests pass. A memory leak counts as a failure.
- Output on the console and as NUnit XML.
- The tests write the safety fuse log to `%TEMP%\dpccCompletionTests\Logs`, not to the `dpcc.log` of the installed
  version. The tests trigger errors on purpose.
- With the symbol `TESTINSIGHT`, the program runs under TestInsight instead of as a console program.

| Folder | Contents |
|---|---|
| `Tests\Common\Lsp` | server side: completion, hover, parameter hint |
| `Tests\IDE` | plugin side without ToolsAPI: flow of the list, ranking, favorites, set mode, placeholders, settings, texts |
| `Tests\Application\Shell` | shell of the server |
| `Tests\Support` | helpers: fixed data source, leak monitoring |

The tests link the DCUs of the packages statically. Parts that use the ToolsAPI (`dpcc.IDE.Base`) can only be checked
in the IDE.

## Conventions

From the existing code:

- **Unit names**: `dpcc.<Package>.<Area>.<Name>`, for example `dpcc.Core.Completion.Controller`. The server units
  are named `Shell.*`.
- **Names**: fields `F…`, parameters `A…`, local variables `m…`. Types in the plugin `TDpcc…`, interfaces
  `IDpcc…`; in `dpcc.Common` also by area (`TLsp…`, `TIndex…`).
- **Blocks**: `begin`/`end` even for single statements.
- **Comments** in German. Every unit starts with a comment about its purpose; public elements carry XMLDoc
  (`/// <summary>`).
- **Layers**: see [Architecture](architecture.md#layer-rules). No VCL and no ToolsAPI in `dpcc.Core`, no ToolsAPI
  in `dpcc.UI`.
- **IDE entry points**: Every call from the IDE (timers, notifiers, drawing, keys) runs through `TDpccGuard.Run`.
  The main thread never waits for the server; results come back through `TDpccMainThread`.
- **Texts**: Every user-facing text is in German and English in a table `cTexts: array[TDpccLanguage, …]`. In
  `dpcc.UI` each feature has its own strings unit. A test checks all tables: no empty text, the same placeholders
  in both languages.
- **Line endings**: CRLF for `.pas`, `.dpr`, `.dpk`, `.inc`, `.dfm`, `.dproj`, `.groupproj`, `.ps1`
  (`.gitattributes`).

### Adding an option

Following the pattern of the existing options:

1. Field, default, limits and reading/writing in the matching record, for example
   `dpcc.Core.Settings.Plugin.Completion` (`Defaults`, `Normalize`, `Exchange`), and the property in
   `TDpccPluginSettings` (`dpcc.Core.Settings.Plugin`).
2. Entry in the catalog `dpcc.Core.Settings.PluginSchemaData` with `x-key`, `x-area` and `x-page`. The file is
   maintained by hand.
3. Visibility: `dpcc.Core.Settings.CompletionView` shows the pages (`x-page`) “Vervollständigung” (Completion),
   “Einfügen” (Insertion) and “Hints” in full. From other pages it shows only individual keys: the master switch
   `completion.enabled` (area “General”, `cPluginKeys`) and all keys `hints.*`. The page itself adds the “Rebuild
   index” button in the area “General”. A new option on another page must be listed in `cPluginKeys`.
4. Control in the part of the page, for example `dpcc.UI.Settings.Page.Completion`, with
   `BindCheck('<registry name>', …)`.
5. Label in German and English in `dpcc.UI.Settings.Strings`.
6. Test.

## Contributing

The repository is at <https://github.com/nrodear/DelphiCodeCompletion>. Report bugs and suggestions as issues,
changes as pull requests.

Before a pull request:

- the whole group builds without errors;
- the tests pass (`--exclude:Benchmark`);
- new user-facing texts are available in German and English;
- the documentation under `docs` is updated if usage or options change.

License: MIT, see [LICENSE](../../LICENSE).
