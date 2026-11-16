[Deutsch](README.md) | English | [Français](README.fr.md)

# dpcc – Delphi Pascal Code Completion

Version 0.1.0

dpcc is a plugin (design-time package) for the Delphi IDE. It provides its own code completion, which builds its
own index of the project, search paths and library inside the IDE process.

Full documentation: [docs/en/index.md](docs/en/index.md).

## Features

- **Completion with Ctrl+Space**: a plain list of the matching identifiers (kind, name, signature).
  If an identifier is in a unit that is not yet in the `uses` section, the list shows “+” and the name of the unit
  (for example “+ System.SysUtils”) and adds the unit when accepting.
- **Parameter hint with Ctrl+Shift+Space**: signatures of the called routine, with the current parameter
  highlighted.
- **Hover**: tooltip over an identifier with declaration, location and XMLDoc comment; while debugging, also the
  value of the variable.
- **FieldByName completion**: field names in `FieldByName('…')` and components from the project's forms (DFM).

The list that opens by itself after “.” still comes from DelphiLSP. dpcc takes over Ctrl+Space and
Ctrl+Shift+Space in the files it serves. Details: [Usage](docs/en/usage.md).

## Requirements

- Delphi 13 / RAD Studio 37.0
- Win32 platform (the IDE is a 32-bit process)

## Building

Open the project group `dpcc_d13.groupproj` in the IDE and build all projects (Win32, Debug). The output goes to
`Output\Win32\Debug` (BPLs in `Bpl`, the test program in `Bin`). More on this:
[Development](docs/en/development.md).

## Installing

1. In the IDE, add the file `Output\Win32\Debug\Bpl\dpcc.IDE.Base370.bpl` via
   **Component › Install Packages…**.
2. At run time, `dpcc.IDE.Base370.bpl` needs the seven BPLs `dpcc.Text`, `dpcc.WinBase`, `dpcc.Common`,
   `dpcc.Windows`, `dpcc.Server`, `dpcc.Core` and `dpcc.UI`. Windows looks for them via the PATH. The folder
   `Output\Win32\Debug\Bpl` must therefore be in the IDE's PATH.

### Setting the IDE PATH

The entry belongs in the IDE's PATH override (**Tools › Options › IDE › Environment Variables ›
User overrides**), not in the Windows PATH. Example, if the repo is in `D:\src\DelphiCodeCompletion`:

```
D:\src\DelphiCodeCompletion\Output\Win32\Debug\Bpl;$(PATH)
```

Or with the script, from the repo folder and with the IDE closed:

```powershell
powershell -NoProfile -File Tools\IdePath.ps1                 # show status
powershell -NoProfile -File Tools\IdePath.ps1 -Action Add     # add the BPL folder
powershell -NoProfile -File Tools\IdePath.ps1 -Action Remove  # remove the entry again
```

The entry takes effect at the next start of the IDE. All steps, checking and uninstalling:
[Installation](docs/en/installation.md).

The options are under **Tools › Options › Third Party › dpcc**: [Settings](docs/en/settings.md).
If something does not work: [Troubleshooting](docs/en/troubleshooting.md).

## Tests

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --exclude:Benchmark --exitbehavior:Continue
```

See [Development](docs/en/development.md#testing).

## License

MIT, see [LICENSE](LICENSE).
