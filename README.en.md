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

dpcc runs in one of two modes, depending on the Code Insight provider selected in the IDE for Delphi. In the dpcc
mode (master switch on, provider dpcc) the list after “.” and the parameter hint at “(” and “,” also come from
dpcc. In the IDE mode (provider DelphiLSP, the default) dpcc is off. The master switch changes the provider; this
takes effect after restarting Delphi. Details: [Usage](docs/en/usage.md#interaction-with-delphilsp) and
[Settings](docs/en/settings.md#what-dpcc-changes-in-the-ide).

## Requirements

- Delphi 13 / RAD Studio 37.0; for Delphi 12 / RAD Studio 23.0 there is a separate project group without tests
  (see [Building for Delphi 12](docs/en/installation.md#building-for-delphi-12))
- Win32 platform (the IDE is a 32-bit process)

## Building

Open the project group `dpcc_d13.groupproj` in the IDE and build all projects (Win32, Debug). The output goes to
`Output\Win32\Debug` (BPLs in `Bpl`, the test program in `Bin`). For Delphi 12 it is `dpcc_d12.groupproj` with
the configuration D12 (never Debug) and the output in `Output\Win32\D12`. More on this: [Development](docs/en/development.md).

## Installing

1. In the IDE, add the file `Output\Win32\Debug\Bpl\dpcc.Plugin370.bpl` via
   **Component › Install Packages…**.
2. At run time, `dpcc.Plugin370.bpl` needs the seven BPLs `dpcc.Text370`, `dpcc.WinBase370`,
   `dpcc.Common370`, `dpcc.Windows370`, `dpcc.Server370`, `dpcc.Core370` and `dpcc.UI370`. Windows looks for
   them via the PATH. The folder `Output\Win32\Debug\Bpl` must therefore be in the IDE's PATH.
3. Under Delphi 12 the files are named `…290.bpl` (plugin `dpcc.Plugin290.bpl`), the folder is
   `Output\Win32\D12\Bpl`.

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

### Setup

From the built BPLs of both groups, `Tools\Build-Setup.ps1` creates the setup `installer\Output\dpccSetup-<version>.exe`
with Inno Setup 6. It installs dpcc for the current user into Delphi 12 and/or 13, without administrator rights, and
sets the IDE's Known Packages and PATH itself. See
[Installing with the setup](docs/en/installation.md#installing-with-the-setup).

The options are under **Tools › Options › Third Party › dpcc**: [Settings](docs/en/settings.md).
If something does not work: [Troubleshooting](docs/en/troubleshooting.md).

## Tests

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --exclude:Benchmark --exitbehavior:Continue
```

See [Development](docs/en/development.md#testing). The tests exist only for Delphi 13.

## License

MIT, see [LICENSE](LICENSE).
