<#
.SYNOPSIS
  Prueft und pflegt den PATH-Eintrag fuer die dpcc-BPLs in den IDE-Umgebungsvariablen von RAD Studio
  (Tools > Optionen > IDE > Umgebungsvariablen > Benutzerdefinierte Ueberschreibungen).

.DESCRIPTION
  dpcc.Plugin<Suffix>.bpl braucht zur Laufzeit dpcc.Text, dpcc.WinBase, dpcc.Common, dpcc.Windows,
  dpcc.Server, dpcc.Core und dpcc.UI<Suffix>.bpl. Windows sucht abhaengige BPLs nicht im Ordner der Plugin-BPL, sondern
  ueber PATH. Dieses Skript traegt den BPL-Ausgabeordner in die PATH-Ueberschreibung der IDE ein
  (HKCU\Software\Embarcadero\BDS\<Version>\Environment Variables, Wert PATH) und zeigt den Zustand an.
  <Suffix> ist die Package-Version (LIBSUFFIX AUTO): 370 fuer Delphi 13 (BDS 37.0), 290 fuer Delphi 12 (BDS 23.0).
  BPL-Ordner ohne -BplDir: Output\Win32\Debug\Bpl fuer Delphi 13 (Konfiguration Debug), Output\Win32\D12\Bpl
  fuer Delphi 12 (Konfiguration D12).

  Aktionen:
    Status  (Vorgabe) Zustand anzeigen, nichts aendern. Exit-Code 0 = alles in Ordnung, 1 = Eintrag fehlt,
            2 = BPL-Ordner oder BPLs fehlen.
    Check   wie Status, aber nur die Ergebniszeile (fuer Skripte).
    Add     Ordner vor $(PATH) eintragen; der bisherige Wert wird unter HKCU\Software\dpcc\IdePlugin
            (PathOverrideBackup) gesichert. Wirkt beim naechsten Start der IDE.
    Remove  Eintrag wieder entfernen.

.EXAMPLE
  powershell -NoProfile -File Tools\IdePath.ps1
  powershell -NoProfile -File Tools\IdePath.ps1 -Action Add
  powershell -NoProfile -File Tools\IdePath.ps1 -Action Remove -BdsVersion 37.0
  powershell -NoProfile -File Tools\IdePath.ps1 -BdsVersion 23.0
#>
[CmdletBinding()]
param(
  [ValidateSet('Status', 'Check', 'Add', 'Remove')]
  [string]$Action = 'Status',
  [string]$BdsVersion = '37.0',
  [string]$BplDir = ''
)

$ErrorActionPreference = 'Stop'

$Major = 0
if (-not [int]::TryParse(($BdsVersion -split '\.')[0], [ref]$Major) -or $Major -le 0) {
  throw "Unbekannte BDS-Version '$BdsVersion' (erwartet z. B. 37.0 oder 23.0)."
}
# Package-Version (LIBSUFFIX AUTO): bis BDS 23.0 (Delphi 12) BDS + 6 (23.0 -> 290), ab BDS 37.0 (Delphi 13) gleich
# (37.0 -> 370).
if ($Major -le 23) { $Suffix = '{0}0' -f ($Major + 6) } else { $Suffix = '{0}0' -f $Major }
# Delphi 13 baut mit der Konfiguration Debug nach Output\Win32\Debug, Delphi 12 mit der Konfiguration D12 nach
# Output\Win32\D12 (dpcc_d12.groupproj). Delphi 12 darf nie mit Debug bauen (schreibt sonst in die Ordner von 13).
if ($Major -ge 37) { $ConfigName = 'Debug'; $Group = 'dpcc_d13' } else { $ConfigName = 'D12'; $Group = 'dpcc_d12' }

if ($BplDir -eq '') {
  $BplDir = Join-Path (Split-Path -Parent $PSScriptRoot) "Output\Win32\$ConfigName\Bpl"
}
$BplDir = [IO.Path]::GetFullPath($BplDir).TrimEnd('\')

$EnvKey = "HKCU:\Software\Embarcadero\BDS\$BdsVersion\Environment Variables"
$KnownKey = "HKCU:\Software\Embarcadero\BDS\$BdsVersion\Known Packages"
$DpccKey = 'HKCU:\Software\dpcc\IdePlugin'
$Required = @('dpcc.Text', 'dpcc.WinBase', 'dpcc.Common', 'dpcc.Windows', 'dpcc.Server', 'dpcc.Core', 'dpcc.UI',
  'dpcc.Plugin') | ForEach-Object { "$_$Suffix.bpl" }

function Get-PathOverride {
  if (-not (Test-Path $EnvKey)) { return $null }
  $item = Get-ItemProperty -Path $EnvKey -ErrorAction SilentlyContinue
  if ($null -eq $item -or -not ($item.PSObject.Properties.Name -contains 'PATH')) { return $null }
  return [string]$item.PATH
}

function Split-PathValue([string]$AValue) {
  if ([string]::IsNullOrEmpty($AValue)) { return @() }
  return @($AValue -split ';' | Where-Object { $_ -ne '' })
}

function Test-Entry([string]$AValue) {
  foreach ($part in (Split-PathValue $AValue)) {
    if ($part.TrimEnd('\') -ieq $BplDir) { return $true }
  }
  return $false
}

function Get-State {
  $value = Get-PathOverride
  $files = foreach ($name in $Required) {
    $path = Join-Path $BplDir $name
    [pscustomobject]@{
      Name    = $name
      Exists  = Test-Path $path
      Changed = if (Test-Path $path) { (Get-Item $path).LastWriteTime } else { $null }
    }
  }
  $known = @()
  if (Test-Path $KnownKey) {
    $known = @((Get-ItemProperty $KnownKey).PSObject.Properties |
      Where-Object { $_.Name -match 'dpcc' } | ForEach-Object { $_.Name })
  }
  [pscustomobject]@{
    Value      = $value
    HasEntry   = Test-Entry $value
    DirExists  = Test-Path $BplDir
    Files      = $files
    Missing    = @($files | Where-Object { -not $_.Exists })
    Known      = $known
    IdeRunning = @(Get-Process -Name 'bds' -ErrorAction SilentlyContinue).Count
  }
}

# Gibt nur den Exit-Code zurueck; die Meldung geht ueber Write-Host, damit sie nicht im Rueckgabewert landet.
function Write-Result($AState) {
  if (-not $AState.DirExists -or $AState.Missing.Count -gt 0) {
    Write-Host "FEHLT: BPL-Ordner oder BPLs fehlen ($BplDir) - erst die Gruppe $Group bauen."
    return 2
  }
  if (-not $AState.HasEntry) {
    Write-Host "FEHLT: $BplDir steht nicht in der PATH-Ueberschreibung der IDE $BdsVersion. Abhilfe: -Action Add"
    return 1
  }
  Write-Host "OK: $BplDir steht in der PATH-Ueberschreibung der IDE $BdsVersion, alle BPLs vorhanden."
  return 0
}

function Show-Status($AState) {
  Write-Output "dpcc - IDE-Umgebungsvariable PATH (BDS $BdsVersion)"
  Write-Output "  Registry : $EnvKey"
  if ($null -eq $AState.Value) {
    Write-Output '  PATH     : (keine Ueberschreibung gesetzt)'
  }
  else {
    Write-Output "  PATH     : $($AState.Value)"
  }
  Write-Output "  BPL-Ordner: $BplDir $(if ($AState.DirExists) { '(vorhanden)' } else { '(FEHLT)' })"
  foreach ($file in $AState.Files) {
    if ($file.Exists) {
      Write-Output ("    [ok]    {0,-24} {1:dd.MM.yyyy HH:mm:ss}" -f $file.Name, $file.Changed)
    }
    else {
      Write-Output ("    [fehlt] {0}" -f $file.Name)
    }
  }
  if ($AState.Known.Count -gt 0) {
    Write-Output '  Known Packages:'
    foreach ($entry in $AState.Known) { Write-Output "    $entry" }
  }
  else {
    Write-Output '  Known Packages: kein dpcc-Package installiert'
  }
  if ($AState.IdeRunning -gt 0) {
    Write-Output "  Hinweis  : $($AState.IdeRunning) Delphi-Instanz(en) laufen - Aenderungen wirken erst nach einem Neustart."
  }
}

$state = Get-State

switch ($Action) {
  'Status' {
    Show-Status $state
    $code = Write-Result $state
    exit $code
  }
  'Check' {
    $code = Write-Result $state
    exit $code
  }
  'Add' {
    if ($state.HasEntry) {
      Write-Output 'Unveraendert: Eintrag ist schon vorhanden.'
    }
    else {
      $old = $state.Value
      if (-not (Test-Path $DpccKey)) { New-Item -Path $DpccKey -Force | Out-Null }
      Set-ItemProperty -Path $DpccKey -Name 'PathOverrideBackup' -Value $(if ($null -eq $old) { '' } else { $old })
      if ([string]::IsNullOrEmpty($old)) {
        $new = "$BplDir;`$(PATH)"
      }
      else {
        $parts = Split-PathValue $old
        $index = [Array]::FindIndex([string[]]$parts, [Predicate[string]] { param($p) $p -ieq '$(PATH)' })
        if ($index -ge 0) {
          $list = [Collections.Generic.List[string]]::new([string[]]$parts)
          $list.Insert($index, $BplDir)
          $new = $list -join ';'
        }
        else {
          $new = "$old;$BplDir"
        }
      }
      if (-not (Test-Path $EnvKey)) { New-Item -Path $EnvKey -Force | Out-Null }
      Set-ItemProperty -Path $EnvKey -Name 'PATH' -Value $new
      Write-Output "Eingetragen. Vorher: $old"
      Write-Output "           Jetzt : $new"
      Write-Output "Sicherung des alten Werts: $DpccKey\PathOverrideBackup"
    }
    $state = Get-State
    Show-Status $state
    $code = Write-Result $state
    exit $code
  }
  'Remove' {
    if (-not $state.HasEntry) {
      Write-Output 'Unveraendert: Eintrag ist nicht vorhanden.'
    }
    else {
      $parts = @(Split-PathValue $state.Value | Where-Object { $_.TrimEnd('\') -ine $BplDir })
      $new = $parts -join ';'
      Set-ItemProperty -Path $EnvKey -Name 'PATH' -Value $new
      Write-Output "Entfernt. Jetzt: $new"
    }
    $state = Get-State
    Show-Status $state
    $null = Write-Result $state
    exit 0
  }
}
