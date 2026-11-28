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
- the library and search paths of the installation (RTL, VCL, components) including the Office type libraries and
  WinRT (see [below](#office-type-libraries-and-winrt));
- the additional source folders (see [below](#additional-source-folders)).

In addition:

- configuration, platform, conditional symbols, search paths and unit namespaces of the active configuration, including
  unsaved changes. dpcc expands macros such as `$(BDS)` in paths the same way as the IDE: first the environment
  variables of the IDE options, then the folders of the installation, last all environment variables of the process. A
  path with a reference dpcc cannot resolve is left out and named in `dpcc.log` (“… skipped with unresolved
  reference”, logged in German).
- library path and browsing path of the running IDE, also with its own profile (`bds -r`). Win64x has no browsing path
  of its own in the registry; there the one of Win64 applies.
- the types of the packages loaded in the IDE, even without source code. dpcc reports them to the server at the start
  of every session. From the packages of the installation only units without source code count (such as DUnitX, DUnit,
  FireDAC); whatever lies as `.pas` under `$(BDS)\source` or `$(BDS)\OCX` comes from the source code. The server fetches
  the members of these types only for units that a project names in its `uses`. dpcc reads both in small steps of
  about 15 ms so that the IDE stays responsive, and sends in the background; with `Diagnose` = 1 the lines
  `IDE-Typen` and `IDE-Mitglieder` in the diagnostic log name the number of steps and the longest one.
- units from `uses X in 'path'` in the `.dpr`, even without an entry in the `.dproj`. Like the compiler, dpcc looks for
  the `uses` of a unit in the unit's own folder first.
- A file outside the project group gets the project from its folder or a folder above. If there are several `.dproj`,
  the one that names the file applies, otherwise the first in alphabetical order. Without a project the folder of the
  file counts as a search path; dpcc loads its units on demand.

The index contains declarations, not usages. Its memory limit is fixed (768 MB).

### Content per declaration

Since cache format 35, the index keeps more per declaration:

- Values of enumerations without `{$SCOPEDENUMS ON}` are in the catalog. “+ Unit” therefore also suggests `fsBold`,
  `ssShift` or `rfReplaceAll`. Values of anonymous enumerations (`set of (a, b)`, `F: (x, y)`) and fields of anonymous
  records (`F: record … end`) are in the index with the type or field name as their container.
- The catalog knows the number of type parameters. “+ Unit” shows generic types with placeholders (`TList<T>`) and
  inserts only the name. If a `<` follows the word, the generic type comes first, otherwise the one of the same name
  without type parameters (for example `TList` from `System.Classes`).
- An explicit value in an enumeration (`A = B + 1`) belongs to its value; before, `B` counted as another value.
- In library units, the index no longer stores the bodies in the implementation section that repeat a declaration of
  the interface. The details of a DLL routine (`external`, `name`, `index`, `delayed`) and the line of the body are
  stored with the declaration. Routines that only exist in the implementation section remain. Project units are not
  affected.
- Pointers, arrays, sets, `class of`, procedural types and subranges keep their target type (`PInteger` → `^Integer`,
  including array bounds), also for fields and variables of an anonymous type. Attributes (`[Weak]`), the kinds
  `resourcestring`, `threadvar`, `class operator` and `destructor`, the message after `message` and the constraints of
  type parameters are in the index as well.
- Signatures of routines, methods and constructors are stored with up to 1000 characters, all others with up to 300
  characters. dpcc reads the full length from the source file when needed, as well as the declaration from a branch
  that does not apply (detail view of the list).
- Conditional compilation: dpcc evaluates constants of the same unit such as `GenericSafeArrays = False` in `{$IF}`,
  `Declared()` knows the built-in types (`AnsiChar`, `Integer` …), and the library reads `{$IFOPT}` with the
  compiler defaults. Before, both branches applied in these cases. A declaration of the same name in a branch that
  does not apply (`{$IFDEF WIN64} function F(…)` … `{$ELSE}` …) is shown as unavailable, even if the branch that
  applies has the same name; `A, B: T` in a `var` section yields both names.
- `.dpk`: `contains` counts like `uses`, `requires` is kept separately.
- The index no longer stores the XMLDoc summary. Hover and list read the documentation from the source file as before.

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
a setting. Units from the `uses` of a project unit and frequently used units do not count; they are pinned (see
above).

Limitation: actions that search a name in all units (for example when creating accessor methods or for field names from
data modules) find top-level symbols of all units and load those units for it. Such a search takes over the matches of
every reloaded unit at once; the 32 MB limit keeps applying meanwhile, also for other requests. That way it sees all
matches without holding all units of a frequent name (such as `Register`) in memory at the same time. They find members
of classes and records only in loaded units.

Declarations from include files (`{$I …}`) of a unit that is only in the catalog are found through an include file →
unit table: the header of every unit lists its include files, also for units that are only in the catalog (they are
stored in the cache directory). Hover, parameter hint and the details of completion thus load the including unit;
for [units with the same name](#units-with-the-same-name), the file that includes the include file. The table holds
one entry per include file and does not change the cache format (still format 35).

After `raise`, `on E: ` and in attribute brackets, completion checks classes from units that are only in the catalog
through the ancestors in the catalog and does not load those units for it. Classes from IDE packages without source
code come in through their ancestor as reported by the IDE.

#### Prewarming on open

When a file becomes active in the editor (opening, switching tabs, a jump) and stays active for about 0.4 s, the plugin
syncs it with the server in the background and asks for it to be prewarmed (`dpcc/prewarm`); flipping through tabs
quickly triggers nothing, and each file and state is prewarmed at most once. The server then, on its own low-priority
thread, puts the file's syntax tree into the cache used by requests and loads the units of its `uses` (plus System) the
way the first request would: from the catalog or via the search paths. So the first Ctrl+Click, tooltip or completion
list after opening no longer has to load anything. At most one job runs; another file cancels it before the next unit.
Cold units are only loaded while the loaded-on-demand units stay below three quarters of the 32 MB limit; prewarming
pins nothing and evicts no unit in use. While the index is being built it waits until the build has finished. The
server's diagnostic log shows one line per job: `prewarm doc#n units … catalog … parsed … missing … ms … cancelled …`.

#### Usage statistics

For every unit of the library, dpcc counts how often requests need it and how often a project unit newly adds it to its
`uses`, for example through “+ Unit”. The points are halved every week. The next build loads frequently used units at
once, and dpcc does not release them. The statistics are stored in `usage.dat` next to the library cache (see
[Cache](#cache)). The server writes them when it ends and at most every 10 minutes, and only if they have changed; two
writes never run at the same time. If they are lost, they start over; the index does not notice.

### Office type libraries and WinRT

`$(BDS)\OCX\Servers` (type libraries of Excel, Word, Outlook and Access) and `$(BDS)\source\rtl\win\winrt` belong
to the library like every other unit of the installation: they are in the library cache and in the catalog, and
“+ Unit” suggests their symbols. Only their catalog stays in memory; dpcc loads the symbols of a unit when completion,
hover or parameter help need them.

- If a unit outside the installation names them in its `uses`, they stay loaded. They do not come in through the
  `uses` of other units of the installation.
- The former switch “Pre-index Office type libraries and WinRT” (`index.officeAndWinRt`) no longer exists. A value in
  `settings.json` has no effect and produces no message.
- The first start after the update reads these units once. The library cache grows by about 41 MB, the
  catalog in memory by about 7 MB. dpcc removes the previous library cache without them after
  `index.cacheMaxAgeDays` days without use.

### Additional source folders

dpcc knows units that the installation only ships as `.dcu` (DUnitX, DUnit, FireDAC …) from the IDE only with their
types (see [above](#what-the-index-contains)). If their source code is on disk, name its folder on the **dpcc** page
under “Additional source folders” (`index.extraSourceFolders` in `settings.json`, see [Settings](settings.md#index)):

- several folders separated by `;`, in `settings.json` also as a list;
- subfolders count too, except `.git`, `__history` and `__recovery`; at most 2000 folders; `index.exclude` applies;
- `$(Name)` (variables of the IDE and the environment) and `%Name%` (environment) are resolved; a relative path applies
  from the project folder;
- their units enter the index like the library: in the catalog (“+ Unit”), loaded on demand, read with the symbols of
  platform and version, not those of the project. They have a cache of their own (see [Cache](#cache)), so another
  folder does not read the whole library again.

Example: the sources of DUnitX, `…\DUnitX\Source`. That is 64 units with about 2600 symbols; the first build reads them
in less than a second, their cache has 0.3 MB, the catalog grows by about 0.1 MB.

### Units with the same name

If a unit exists more than once, for example an adapted copy of a library unit in the project or `Unit1` in two
projects of the group, the index keeps all files. Which one applies is decided by the project of the file you are
working in, in the order of the compiler: units of the project, project folder, search paths, library, additional
source folders. Without a project the order is: project before search path before library before additional folders.
The unit namespaces (`DCC_Namespace`) also apply per project.

### Other Delphi installations

When several Delphi versions are installed, dpcc (the plugin as well as dpcc.LspServer.exe) neither takes units from
the folder of another installation into the index nor from a cache. So Delphi 12 does not jump into the Delphi 13
sources for `TStringList`. Exempt are folders the project itself names: project files, the project's search paths,
the IDE's library and browsing paths and additional source folders. Whoever opens, say,
`Studio\37.0\source\rtl\BuildWinRTL.dproj` in Delphi 12 or enters a Delphi 13 folder as a search path keeps those
units including the cache; all other units of the other installation stay out. If a cache still held such units
(earlier versions), the next build writes it again without them. The log names the excluded folders ("Units anderer
Delphi-Installationen bleiben draußen: …") and the counts ("… aus dem Index genommen, … aus den Caches nicht
übernommen").

## When the index is built

- In the Plugin mode the server starts with the first request, for example Ctrl+Space, or when switching to Plugin.
  In the Server mode `dpcc.LspServer.exe` builds its own index (see [LSP server](lsp-server.md#storage)).
- It then builds the index. This runs in the background; the IDE does not wait for it.
- While the build is running, the list shows “limited (index is being built)” and may be incomplete.
- On large installations the first build can take a few minutes because it reads the library. After that, most of it
  comes from the cache.

## Changes

- dpcc checks for changes in the project group at most every two seconds, for changes to configuration and options at
  most once per second. It only compares projects, active project, configuration and platform; search paths, defines
  and library path are read again when one of these changes, when an IDE dialog (such as project options) closes, and
  otherwise at least every 15 seconds.
- dpcc reports saved files to the server.
- Changes outside the IDE: dpcc watches the project folders (the Git working directory, otherwise the project folder).
  Collected changes go to the server with the next request.
- Folders outside of these (search paths in other repositories, components in the library path, additional source
  folders, `$(BDS)`) are checked by the server itself: while you work in the editor, at most every 10 seconds, in a
  thread of its own. It takes over new, changed and deleted units.
- A new unit in a search path, library folder or additional source folder enters the index at once, not only when a
  unit names it.
- Before dpcc loads a library unit on demand, it checks the state of its file; if it differs from the cache, dpcc reads
  the file again.
- A file counts as changed if its time stamp differs, or if the time stamp is the same and the size differs.
- A change to the browsing path of the IDE alone rebuilds the index.
- A file that cannot be read or parsed (for example because of its encoding) is missing from the index; the build
  continues. `dpcc.log` names it with path and error (“Datei nicht lesbar, im Index übergangen”), the diagnostic log
  counts it (“index project#n unreadable”). If memory runs out, the build reads no more files and keeps what it has.
- Open forms go to the server with their current state from the designer, not from disk.

## Cache

The cache is located under `%LOCALAPPDATA%\dpcc\Index`:

| Path | Contents |
|---|---|
| `Index\<IDE version>\<hash>\index-<format>.dpccidx` | cache of a project |
| `Index\<IDE version>\Bibliothek\<hash>\index-<format>.dpccidx` | cache of the library, separate from the project |
| `Index\<IDE version>\Bibliothek\<hash>\usage.dat` | usage statistics of the library (see [above](#usage-statistics)) |
| `Index\<IDE version>\Zusatzordner\<hash>\index-<format>.dpccidx` | cache of the additional source folders, per platform, version and folders |
| `…\<cache>.lock` | lock; only the first instance writes the cache, further instances only read it |
| `…\projekt.txt` | project file the cache belongs to |
| `…\benutzt.stamp` | time of last use |

The format version is part of the file name. This way, different versions of dpcc do not interfere with each other.

Since format 34, every unit is stored in a block of its own with its own checksum. A directory at the end of the file
lists all units with their catalog. At startup, dpcc reads only the directory and the blocks of the units it loads,
through an open handle; another instance can still replace the file. A damaged block affects only its unit; dpcc then
reads it again from the source file. The current format 35 adds the content from
[Content per declaration](#content-per-declaration). The directory also lists the include files of every unit; at
startup, the include file → unit table is built from it (see [Library on demand](#library-on-demand)).

dpcc no longer reads caches of older formats (for example `index-34.dpccidx`): the first start after the update builds
the index once more. As soon as dpcc has written a cache in the new format, it deletes the files
`index-<number>.dpccidx` of older formats in the same folder together with their `.lock` file, unless another instance
holds them (for example an older version of dpcc in a second IDE). Other files remain. “Rebuild index” (see
[below](#rebuilding-the-index)) deletes all caches at once.

During the first build without a cache, dpcc writes the library cache in between so that the newly read units may leave
memory again. It only appends the new blocks and a new directory to the file, and only to the file it last wrote itself
(same time stamp, same size, same header); otherwise it writes the whole file. It writes the project cache in between
only if library units outside the installation were added (for example third-party sources; they are stored in the
project cache), otherwise only at the end of the build. Every append leaves the previous directory as unused space in
the file; if that space is larger than 4 MB or 10 % of the file at the end of a build, dpcc rewrites the whole file. If
appending is interrupted, the previous state stays valid, and whoever is reading the file keeps reading its blocks
unchanged. For these intermediate states, the “cacheWrite library” lines of the diagnostic log give only the appended
KB.

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

**Tools › Options › Third Party › dpcc › Rebuild index**:

1. dpcc asks: “Delete all index caches and rebuild the index? The first build can take a few minutes.”
2. It stops a running session, deletes all index caches that are not locked, and restarts the session. This runs
   in the background; the IDE stays responsive. While it runs, the button is grayed out and shows “Rebuilding index:
   stopping the session, deleting caches …” next to it. You may close the options meanwhile; when you open them
   again, the page shows the current state.
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
The same applies to `index.officeAndWinRt`: the Office type libraries and WinRT are always in the catalog (see
[above](#office-type-libraries-and-winrt)). `index.extraSourceFolders` takes effect (see
[above](#additional-source-folders)).
