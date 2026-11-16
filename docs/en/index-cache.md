[Deutsch](../de/index-cache.md) | English | [Français](../fr/index-cache.md)

# Index and cache

[Overview](index.md) › Index and cache

Completion, hover, parameter hint and the “+” display with the name of a missing unit (for example
“+ System.SysUtils”) read from a symbol index. The dpcc server builds it inside the IDE process. It is
independent of the DelphiLSP index.

## What the index contains

The scope is fixed:

- all projects of the open project group, the active one first;
- all units in the search paths of the projects;
- the library and search paths of the installation (RTL, VCL, components), without the Office type libraries and
  WinRT (see [below](#office-type-libraries-and-winrt)).

In addition:

- configuration, platform, conditional symbols, search paths and unit namespaces of the active configuration, including
  unsaved changes. dpcc expands macros such as `$(BDS)` in paths the same way as the IDE.
- the types of the packages loaded in the IDE, even without source code. dpcc reports them to the server at the start
  of every session.

The index contains declarations, not usages. Its memory limit is fixed (768 MB).

### Library on demand

Of the library, the index keeps only a part in memory with all symbols. Always loaded (pinned) are:

- the units of the projects and of their search paths;
- the units the projects reach through `uses` (interface and implementation of the project units, from there on
  through the `uses` in the interface);
- the units that a project unit names in its `uses`, including ones just typed in an open file;
- frequently used units of the library (see [Usage statistics](#usage-statistics)).

Of all other units, the index knows a catalog: name, file, `uses`, the first types and all symbols another unit can
import. Through it, “+ Unit”, same-name symbols from other units, completion in the `uses` section and the search for
class helpers still cover all units. dpcc reads the complete symbols of such a unit from its block in the cache only
when completion, hover, parameter help or go to definition need them. This usually takes less than 5 ms, up to about
150 ms for very large units.

If the units loaded this way take more than an estimated 32 MB together, dpcc releases the least frequently used one, on a tie the
one unused for the longest time. It always releases the whole unit; its catalog entry stays. The limit is fixed and not
a setting.

Limitation: actions that search a name in all units (for example when creating accessor methods or for field names
from data modules) find top-level symbols of all units and load those units for it. They find members of classes and
records only in loaded units.

#### Usage statistics

For every unit of the library, dpcc counts how often requests need it and how often a project unit newly adds it to its
`uses`, for example through “+ Unit”. The points are halved every week. The next build loads frequently used units at
once, and dpcc does not release them. The statistics are stored in `usage.dat` next to the library cache (see
[Cache](#cache)). The server writes them when it ends and at most every 10 minutes. If they are lost, they start over;
the index does not notice.

### Office type libraries and WinRT

dpcc does not read `$(BDS)\OCX\Servers` (type libraries of Excel, Word, Outlook and Access, plus MSHTML) and
`$(BDS)\source\rtl\win\winrt` in advance. Together they are a good 40 % of the library's symbols and about 140 MB
in the index, and they are rarely needed.

- The units remain reachable through `uses`: if a unit outside the installation uses them, the build reads them at
  once. If only a unit of the installation uses them, dpcc loads them when completion, hover or parameter help need
  them.
- “+ Unit” does not suggest their symbols.
- The switch “Pre-index Office type libraries and WinRT” on the **General** page (`index.officeAndWinRt` in
  `settings.json`) brings them back. See [Settings](settings.md#general).
- Each position has its own library cache. The first time you switch, dpcc reads the library once more; after that it
  comes from the respective cache. When switched off, the server removes the units from the index immediately.

## When the index is built

- The server starts with the first request, for example Ctrl+Space, or when the master switch is turned on.
- It then builds the index. This runs in the background; the IDE does not wait for it.
- While the build is running, the list shows “limited (index is being built)” and may be incomplete.
- On large installations the first build can take a few minutes because it reads the library. After that, most of it
  comes from the cache.

## Changes

- dpcc checks for changes in the project group at most every two seconds, for changes to configuration and options at
  most once per second.
- dpcc reports saved files to the server.
- Changes outside the IDE: dpcc watches the project folders (the Git working directory, otherwise the project folder).
  Collected changes go to the server with the next request.
- Open forms go to the server with their current state from the designer, not from disk.

## Cache

The cache is located under `%LOCALAPPDATA%\dpcc\Index`:

| Path | Contents |
|---|---|
| `Index\<IDE version>\<hash>\index-<format>.dpccidx` | cache of a project |
| `Index\<IDE version>\Bibliothek\<hash>\index-<format>.dpccidx` | cache of the library, separate from the project |
| `Index\<IDE version>\Bibliothek\<hash>\usage.dat` | usage statistics of the library (see [above](#usage-statistics)) |
| `…\<cache>.lock` | lock; only the first instance writes the cache, further instances only read it |
| `…\projekt.txt` | project file the cache belongs to |
| `…\benutzt.stamp` | time of last use |

The format version is part of the file name. This way, different versions of dpcc do not interfere with each other.

Since format 34, every unit is stored in a block of its own with its own checksum. A directory at the end of the file
lists all units with their catalog. At startup, dpcc reads only the directory and the blocks of the units it loads,
through an open handle; another instance can still replace the file. A damaged block affects only its unit; dpcc then
reads it again from the source file. dpcc no longer reads caches of older formats (for example `index-33.dpccidx`): the
first start after the update builds the index once more. The old file stays until the size-based cleanup removes it;
“Rebuild index” (see [below](#rebuilding-the-index)) deletes it at once.

The environment variable `DPCC_CACHE_ROOT` moves the server's whole `%LOCALAPPDATA%\dpcc` folder (caches and
diagnostic log), for example for tests with a copy of the cache. Without it, `LOCALAPPDATA` from the process
environment applies.

If the index already holds every unit of the library or search path cache in the same state, a new build does not
read the cache again (for example after saving a `.dproj`). The diagnostic log reports this as
“index project#n cache skipped library”.

### Cleanup

The server cleans up the cache folder itself:

| Rule | Default | Key in `settings.json` |
|---|---|---|
| Delete caches of deleted projects | on | `index.removeOrphans` (`true`/`false`) |
| Delete caches not used for this many days | 14 | `index.cacheMaxAgeDays` (0 to 3650; 0 = off) |
| Maximum size of the cache folder in MB, oldest first | 1024 | `index.cacheMaxMb` (0 = no limit) |

If the origin of a cache is on a drive that is currently missing (USB, network), the cache is kept.

## Rebuilding the index

**Tools › Options › Third Party › dpcc › General › Rebuild index**:

1. dpcc asks: “Delete all index caches and rebuild the index? The first build can take a few minutes.”
2. It stops a running session, deletes all index caches that are not locked, and restarts the session.
3. The page reports the result:
   - “n index caches deleted; the index is being rebuilt.” – the session was running and has been restarted;
   - “n index caches deleted; the index is rebuilt the next time code completion starts.” – no session was running;
     the button does not start a server;
   - “Index cache could not be deleted: …” – error.

You can also delete the cache by hand: close the IDE and delete `%LOCALAPPDATA%\dpcc\Index`.

## Excluding units from the index

In `dpcc.json` in the project folder, `index.exclude` excludes files. The patterns apply to the full path: `*`
without separators, `**` across folders, `?` one character, case-insensitive.

```json
{
  "index": {
    "exclude": ["**/Demos/**", "**/Generated/*.pas"]
  }
}
```

## Server settings files

| File | Location | Applies to |
|---|---|---|
| `settings.json` | `%APPDATA%\dpcc` | all projects (personal, per machine) |
| `dpcc.json` | project folder | this project (for the team, belongs in the repository) |

Each key has exactly one location. A key in the wrong location has no effect. In `dpcc.json` the server ignores
credentials and absolute paths. It watches both files itself; changes take effect without a restart.

The server still reads the index keys `index.projectGroup`, `index.searchPaths`, `index.libraryPaths`, `index.usages`
and `memoryBudgetMb`, so that older files load without a warning. They no longer have any effect; the scope is fixed.
Only `index.officeAndWinRt` takes effect (see [above](#office-type-libraries-and-winrt)).
