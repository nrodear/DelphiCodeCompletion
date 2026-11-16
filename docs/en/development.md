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
| `Tests\Common\Index` | index: extractor, token and type texts, conditional compilation, content per declaration (format 35) |
| `Tests\Common\Pascal` | parser and preprocessor |
| `Tests\IDE` | plugin side without ToolsAPI: flow of the list, ranking, favorites, set mode, placeholders, settings, texts |
| `Tests\Application\Shell` | shell of the server |
| `Tests\Common` | memory: self-measurement, names of the `.dcp`, shared cache, Office type libraries and WinRT, release after the server ends, documents, name and reference tables, signatures in the cache, cache format 34, catalog, loading on demand and eviction, usage statistics, search across units not loaded, protected units, reuse of the reference tables, concurrent loading, appending to the cache, compacting the cache, releasing the shared states after a stop, writing the usage statistics |
| `Tests\Memory` | memory benchmark (category `Benchmark`) |
| `Tests\Support` | helpers: fixed data source, leak monitoring |

The tests link the DCUs of the packages statically. Parts that use the ToolsAPI (`dpcc.IDE.Base`) can only be checked
in the IDE.

### Measuring memory

`dpcc.Memory.Bench.Tests` starts the server inside its own process like the plugin does, opens a project group with
the library of the installation and writes private bytes, peak, working set and the largest free region of the address
space to a CSV file every second. Measuring points: start, index ready, after the requests, after every rebuild
(`.dproj` saved) and after a server restart. Without the variable `DPCC_MEMBENCH_OUT` the test ends at once. On
request, completions on random units of the library follow the requests and measure loading on demand and eviction
(`DPCC_MEMBENCH_COLD`), typing in a project unit with concurrent requests measures the response times
(`DPCC_MEMBENCH_TYPING`), and large units in the `uses` of a project unit, followed by completions on random units,
count loading and eviction (`DPCC_MEMBENCH_PINNED`).

| Variable | Meaning |
|---|---|
| `DPCC_MEMBENCH_OUT` | CSV file; the measuring points are in `<file>-points.csv` |
| `DPCC_MEMBENCH_GROUP` | `.groupproj` whose projects form the workspace |
| `DPCC_MEMBENCH_REQUESTS`, `DPCC_MEMBENCH_REBUILDS`, `DPCC_MEMBENCH_RESTARTS`, `DPCC_MEMBENCH_BETWEEN` | requests (2000), rebuilds (5), restarts (1), requests between two rebuilds (100) |
| `DPCC_MEMBENCH_COLD`, `DPCC_MEMBENCH_LIBDIR` | number of completions “Unit.” on random units of the library (0) and the folder of their sources (`source` of Delphi 13) |
| `DPCC_MEMBENCH_TYPING` | typing rounds (0): four keystrokes each, then the typing pause; meanwhile a second thread sends requests. Line “[typing]” with median, 95th and 99th percentile and maximum of the response times, each one in `<file>-latency.csv` |
| `DPCC_MEMBENCH_PINNED`, `DPCC_MEMBENCH_PINNEDUNITS`, `DPCC_MEMBENCH_PINNEDCOUNT` | completions on random units (0) after a project unit names and loads large units in its `uses`: comma-separated names or the largest files of the library (80). Line “[pinned]” with loading and eviction |
| `DPCC_MEMBENCH_FREQUENT`, `DPCC_MEMBENCH_FREQNAMES` | rounds (0) with a frequent top-level name (comma-separated, default `Register`): a completion after “:=” on a variable of this type (searches it in all units), then five completions on random units. Line “[frequent]” with loading, eviction and response times of the search |
| `DPCC_CACHE_ROOT` or `LOCALAPPDATA`, `APPDATA` | own folders so that the user's cache stays untouched; for a warm start, put a copy of the library cache there |

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --run:dpcc.Memory.Bench.Tests --exitbehavior:Continue
```

Every measuring point also gives the memory allocated by the memory manager (`alloc_mb`); the gap to the private bytes
is the overhead. The “[lazy]” lines and the columns `loaded` to `largest_load_ms` give loaded, pinned, releasable and
catalog-only units, the catalog, loading on demand and eviction with their duration. Errors in the server (`ERangeError`, `EIntOverflow`, `EAccessViolation`) are written by the benchmark
with the error address and the return addresses to `<file>-exceptions.txt`; resolve them with the `.map` file of the
test program.

Like `bds.exe`, the test program is LARGEADDRESSAWARE (4 GB address space). Measurement data does not belong in the
repository.

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
