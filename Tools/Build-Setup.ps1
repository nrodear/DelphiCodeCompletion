<#
.SYNOPSIS
  Baut das Setup von dpcc (installer\dpccSetup.iss, Inno Setup 6) aus den in der IDE gebauten BPLs.

.DESCRIPTION
  Das Setup kompiliert nichts; es buendelt die fertigen BPLs beider Delphi-Versionen:
    Delphi 13: Output\Win32\Debug\Bpl (dpcc_d13.groupproj, Win32, Konfiguration Debug), Endung 370
    Delphi 12: Output\Win32\D12\Bpl   (dpcc_d12.groupproj, Win32, Konfiguration D12),   Endung 290
  Je Version acht BPLs: dpcc.Text, dpcc.WinBase, dpcc.Common, dpcc.Windows, dpcc.Server, dpcc.Core, dpcc.UI und
  das Plugin dpcc.Plugin.

  Vorbedingungen. Das Skript prueft alle und bricht erst dann ab; angelegt wird bis dahin nichts:
    - ISCC.exe gefunden (PATH, -Iscc oder Standardordner von Inno Setup 6)
    - Version aus Packages\dpcc.Text\Source\Product\dpcc.Text.Product.Version.pas lesbar (x.y.z)
    - je Version alle acht BPLs vorhanden, PE-Machine 014C (Win32)
    - jede BPL juenger als die neueste Quelldatei (.pas, .dpk, .dfm, .inc) ihres Packages; sonst zeigte das Setup
      einen alten Stand
  Die BPLs tragen unter Win32 keine VERSIONINFO (VerInfo_IncludeVerInfo ist dort aus); ein Versionsvergleich der
  BPLs ist deshalb nicht moeglich, die Version des Setups kommt allein aus dpcc.Text.Product.Version.

  Danach ruft es ISCC mit /DDpccVersion=<x.y.z>.0, /DDpccBplSourceDirD12, /DDpccBplSourceDirD13 und /O<OutDir>.
  Ergebnis: <OutDir>\dpccSetup-<x.y.z>.0.exe. Das Setup wird nicht ausgefuehrt.

  LSP-Server (Betriebsart Server): Das Setup nimmt dpcc.LspServer.exe in beiden Bitbreiten als abwaehlbare
  Komponente auf. Geprueft wird wie bei den BPLs: Output\Win32\Debug\Bin (PE 014C, Gruppenbau dpcc_d13) und
  Output\Win64\Debug\Bin (PE 8664, eigener Bauschritt Win64) vorhanden und nicht aelter als ihre Quellen
  (Application und die Packages dpcc.Text, dpcc.WinBase, dpcc.Common, dpcc.Windows). Zusaetzlich entsteht
  <OutDir>\dpcc.LspServer-<x.y.z>.zip mit win32\, win64\ und LIESMICH.txt (installer\LspServer-LIESMICH.txt).

.EXAMPLE
  powershell -NoProfile -File Tools\Build-Setup.ps1 -DryRun
  powershell -NoProfile -File Tools\Build-Setup.ps1
  powershell -NoProfile -File Tools\Build-Setup.ps1 -OutDir D:\release
#>
[CmdletBinding()]
param(
  # BPL-Ordner von Delphi 12; Vorgabe Output\Win32\D12\Bpl im Repo.
  [string]$BplDirD12 = '',
  # BPL-Ordner von Delphi 13; Vorgabe Output\Win32\Debug\Bpl im Repo.
  [string]$BplDirD13 = '',
  # Ordner der 32-Bit-EXE dpcc.LspServer.exe; Vorgabe Output\Win32\Debug\Bin (Gruppenbau dpcc_d13).
  [string]$LspServerDirWin32 = '',
  # Ordner der 64-Bit-EXE dpcc.LspServer.exe; Vorgabe Output\Win64\Debug\Bin (eigener Bauschritt Win64).
  [string]$LspServerDirWin64 = '',
  # Zielordner des Setups; Vorgabe installer\Output im Repo (steht in .gitignore).
  [string]$OutDir = '',
  # Voller Pfad zu ISCC.exe, falls es weder im PATH noch im Standardordner liegt.
  [string]$Iscc = '',
  # Nur die Vorbedingungen pruefen, danach Ende. Legt nichts an.
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$iss = Join-Path $repo 'installer\dpccSetup.iss'

if ($BplDirD12 -eq '') { $BplDirD12 = Join-Path $repo 'Output\Win32\D12\Bpl' }
if ($BplDirD13 -eq '') { $BplDirD13 = Join-Path $repo 'Output\Win32\Debug\Bpl' }
if ($LspServerDirWin32 -eq '') { $LspServerDirWin32 = Join-Path $repo 'Output\Win32\Debug\Bin' }
if ($LspServerDirWin64 -eq '') { $LspServerDirWin64 = Join-Path $repo 'Output\Win64\Debug\Bin' }
$LspServerDirWin32 = [IO.Path]::GetFullPath($LspServerDirWin32).TrimEnd('\')
$LspServerDirWin64 = [IO.Path]::GetFullPath($LspServerDirWin64).TrimEnd('\')
if ($OutDir -eq '') { $OutDir = Join-Path $repo 'installer\Output' }
$BplDirD12 = [IO.Path]::GetFullPath($BplDirD12).TrimEnd('\')
$BplDirD13 = [IO.Path]::GetFullPath($BplDirD13).TrimEnd('\')
$OutDir = [IO.Path]::GetFullPath($OutDir).TrimEnd('\')

$packages = @('dpcc.Text', 'dpcc.WinBase', 'dpcc.Common', 'dpcc.Windows', 'dpcc.Server', 'dpcc.Core', 'dpcc.UI',
  'dpcc.Plugin')
$versions = @(
  @{ Name = 'Delphi 12'; Suffix = '290'; Dir = $BplDirD12; Group = 'dpcc_d12.groupproj (Konfiguration D12)' },
  @{ Name = 'Delphi 13'; Suffix = '370'; Dir = $BplDirD13; Group = 'dpcc_d13.groupproj (Konfiguration Debug)' }
)

# COFF-Feld Machine, 4 Byte hinter der PE-Signatur; 0 = keine PE-Datei. Liest nur den Kopf der Datei.
function Get-PeMachine([string]$Path) {
  $stream = [IO.File]::OpenRead($Path)
  try {
    $bytes = New-Object byte[] 4096
    $count = $stream.Read($bytes, 0, $bytes.Length)
  }
  finally {
    $stream.Dispose()
  }
  if ($count -lt 0x40) { return 0 }
  $peOff = [BitConverter]::ToInt32($bytes, 0x3C)
  if (($peOff -lt 0) -or (($peOff + 6) -gt $count)) { return 0 }
  if ([BitConverter]::ToUInt32($bytes, $peOff) -ne 0x4550) { return 0 }
  return [BitConverter]::ToUInt16($bytes, $peOff + 4)
}

# Neueste Quelldatei eines Packages (ohne __history); $null, wenn keine da ist.
function Get-NewestSource([string]$Package) {
  $folder = Join-Path $repo "Packages\$Package"
  if (-not (Test-Path $folder)) { return $null }
  return Get-ChildItem -Path $folder -Recurse -File -Include '*.pas', '*.dpk', '*.dfm', '*.inc' |
    Where-Object { $_.FullName -notmatch '\\__history\\|\\__recovery\\' } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

$findings = New-Object System.Collections.Generic.List[string]

# ---- ISCC -----------------------------------------------------------------------------------------------------
if ($Iscc -eq '') {
  $cmd = Get-Command 'iscc.exe' -ErrorAction SilentlyContinue
  if ($cmd) {
    $Iscc = $cmd.Source
  }
  else {
    foreach ($candidate in @(
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'))) {
      if ($candidate -and (Test-Path $candidate)) { $Iscc = $candidate; break }
    }
  }
}
if (($Iscc -eq '') -or -not (Test-Path $Iscc)) {
  $findings.Add('ISCC.exe nicht gefunden (PATH, Standardordner, -Iscc). Inno Setup 6 installieren.')
}

# ---- Version ----------------------------------------------------------------------------------------------------
$versionFile = Join-Path $repo 'Packages\dpcc.Text\Source\Product\dpcc.Text.Product.Version.pas'
$version = ''
if (Test-Path $versionFile) {
  $match = Select-String -Path $versionFile -Pattern "cVersion\s*=\s*'([^']*)'" | Select-Object -First 1
  if ($match) { $version = $match.Matches[0].Groups[1].Value }
}
if ($version -notmatch '^\d+\.\d+\.\d+$') {
  $findings.Add("Version nicht lesbar oder nicht x.y.z ('$version') in $versionFile.")
}
$versionFull = "$version.0"

# ---- BPLs -------------------------------------------------------------------------------------------------------
''
'{0,-10} {1,-24} {2,-5} {3,-19} {4}' -f 'Version', 'BPL', 'PE', 'Stand', 'Zustand'
foreach ($v in $versions) {
  foreach ($p in $packages) {
    $name = "$p$($v.Suffix).bpl"
    $file = Join-Path $v.Dir $name
    if (-not (Test-Path $file)) {
      '{0,-10} {1,-24} {2,-5} {3,-19} {4}' -f $v.Name, $name, '-', '-', 'FEHLT'
      $findings.Add("$($v.Name): $name fehlt in $($v.Dir).")
      continue
    }
    $state = @()
    $machine = Get-PeMachine $file
    if ($machine -ne 0x014C) {
      $state += 'BITBREITE'
      $findings.Add(('{0}: {1} hat PE-Machine {2:X4}, erwartet 014C (Win32).' -f $v.Name, $name, [int]$machine))
    }
    $built = (Get-Item $file).LastWriteTime
    $source = Get-NewestSource $p
    if ($source -and ($source.LastWriteTime -gt $built)) {
      $state += 'VERALTET'
      $findings.Add(('{0}: {1} ({2:dd.MM.yyyy HH:mm}) ist aelter als {3} ({4:dd.MM.yyyy HH:mm}).' -f
          $v.Name, $name, $built, $source.Name, $source.LastWriteTime))
    }
    $text = if ($state.Count) { $state -join ' + ' } else { 'ok' }
    '{0,-10} {1,-24} {2,-5} {3,-19} {4}' -f $v.Name, $name, ('{0:X4}' -f [int]$machine),
      ('{0:dd.MM.yyyy HH:mm}' -f $built), $text
  }
}
''

# ---- LSP-Server -------------------------------------------------------------------------------------------------
# Eine EXE je Bitbreite. Quellen: Application\dpcc.LspServer.dpr, Application\Source und die Packages, deren Units
# die EXE ueber ihren Suchpfad direkt uebersetzt (dpcc.Text, dpcc.WinBase, dpcc.Common, dpcc.Windows).
$lspExe = 'dpcc.LspServer.exe'
$lspSources = @(Join-Path $repo 'Application') + (@('dpcc.Text', 'dpcc.WinBase', 'dpcc.Common', 'dpcc.Windows') |
    ForEach-Object { Join-Path $repo "Packages\$_\Source" })
$lspNewest = Get-ChildItem -Path $lspSources -Recurse -File -Include '*.pas', '*.dpr', '*.dfm', '*.inc' |
  Where-Object { $_.FullName -notmatch '\\__history\\|\\__recovery\\' } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
$lspTargets = @(
  @{ Name = 'Win32'; Dir = $LspServerDirWin32; Machine = 0x014C; Hint = 'Gruppenbau dpcc_d13 (Win32, Debug)' },
  @{ Name = 'Win64'; Dir = $LspServerDirWin64; Machine = 0x8664; Hint = 'dpcc.LspServer.dproj, Plattform Win64, Debug' }
)
'{0,-10} {1,-24} {2,-5} {3,-19} {4}' -f 'LSP', 'EXE', 'PE', 'Stand', 'Zustand'
foreach ($l in $lspTargets) {
  $file = Join-Path $l.Dir $lspExe
  if (-not (Test-Path $file)) {
    '{0,-10} {1,-24} {2,-5} {3,-19} {4}' -f $l.Name, $lspExe, '-', '-', 'FEHLT'
    $findings.Add("LSP-Server $($l.Name): $lspExe fehlt in $($l.Dir) ($($l.Hint)).")
    continue
  }
  $state = @()
  $machine = Get-PeMachine $file
  if ($machine -ne $l.Machine) {
    $state += 'BITBREITE'
    $findings.Add(('LSP-Server {0}: PE-Machine {1:X4}, erwartet {2:X4}.' -f $l.Name, [int]$machine, $l.Machine))
  }
  $built = (Get-Item $file).LastWriteTime
  if ($lspNewest -and ($lspNewest.LastWriteTime -gt $built)) {
    $state += 'VERALTET'
    $findings.Add(('LSP-Server {0}: {1} ({2:dd.MM.yyyy HH:mm}) ist aelter als {3} ({4:dd.MM.yyyy HH:mm}); {5}.' -f
        $l.Name, $lspExe, $built, $lspNewest.Name, $lspNewest.LastWriteTime, $l.Hint))
  }
  $text = if ($state.Count) { $state -join ' + ' } else { 'ok' }
  '{0,-10} {1,-24} {2,-5} {3,-19} {4}' -f $l.Name, $lspExe, ('{0:X4}' -f [int]$machine),
    ('{0:dd.MM.yyyy HH:mm}' -f $built), $text
}
$readme = Join-Path $repo 'installer\LspServer-LIESMICH.txt'
if (-not (Test-Path $readme)) { $findings.Add("Liesmich fuer das ZIP fehlt: $readme.") }
''

if ($findings.Count -gt 0) {
  $hint = ($versions | ForEach-Object { "$($_.Name): $($_.Group)" }) -join '; '
  throw ("Setup nicht gebaut, {0} Befund(e):`n  - {1}`n" -f $findings.Count, ($findings -join "`n  - ")) +
    "Die Gruppen in der IDE bauen (Win32): $hint. Es wurde nichts angelegt oder veraendert."
}

"Version  : $versionFull"
"ISCC     : $Iscc"
"Skript   : $iss"
"Ziel     : $OutDir\dpccSetup-$versionFull.exe"
$zipFile = Join-Path $OutDir "dpcc.LspServer-$version.zip"
"ZIP      : $zipFile"

if ($DryRun) {
  'Probelauf gruen: 16 BPLs, 2 EXEs des LSP-Servers und Version passen. Nichts angelegt oder veraendert.'
  return
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }
$isccArgs = @(
  '/Q',
  "/DDpccVersion=$versionFull",
  "/DDpccBplSourceDirD12=$BplDirD12",
  "/DDpccBplSourceDirD13=$BplDirD13",
  "/DDpccLspServerDirWin32=$LspServerDirWin32",
  "/DDpccLspServerDirWin64=$LspServerDirWin64",
  "/O$OutDir",
  $iss
)
& $Iscc @isccArgs | Out-Host
if ($LASTEXITCODE -ne 0) { throw "ISCC fehlgeschlagen (Exit $LASTEXITCODE)." }
$setupExe = Join-Path $OutDir "dpccSetup-$versionFull.exe"
if (-not (Test-Path $setupExe)) { throw "Setup-EXE fehlt nach ISCC: $setupExe" }
"Fertig: $setupExe"

# ZIP mit beiden EXEs und dem Liesmich, fuer Nutzer ohne Setup (eigener Bau, andere Ablage). Aufgebaut ueber
# System.IO.Compression, damit die Ordner win32\ und win64\ im Archiv stehen.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
$zip = [IO.Compression.ZipFile]::Open($zipFile, [IO.Compression.ZipArchiveMode]::Create)
try {
  [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $LspServerDirWin32 $lspExe),
    "win32/$lspExe", [IO.Compression.CompressionLevel]::Optimal)
  [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $LspServerDirWin64 $lspExe),
    "win64/$lspExe", [IO.Compression.CompressionLevel]::Optimal)
  [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $readme, 'LIESMICH.txt',
    [IO.Compression.CompressionLevel]::Optimal)
}
finally {
  $zip.Dispose()
}
"Fertig: $zipFile"
