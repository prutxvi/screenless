<#
.SYNOPSIS
  Make a slow phone feel faster while mirroring. Every change is reversible with -Undo.

.DESCRIPTION
  - Animation scales 1.0 -> 0.5 (screens open about twice as fast)
  - Keep the phone awake so the mirror never goes black
  - Optional: disable pre-installed bloatware listed in a text file (one package per line)

  Works on a specific phone: pass -Serial, or pick from a list when several are connected.

.EXAMPLE
  .\tune.ps1
  .\tune.ps1 -Debloat ..\debloat\motorola.txt
  .\tune.ps1 -Serial ABC123 -Debloat ..\debloat\motorola.txt
  .\tune.ps1 -Undo -Debloat ..\debloat\motorola.txt
#>
param(
  [string]$Serial,
  [string]$Debloat,
  [switch]$Undo
)

$ErrorActionPreference = 'Continue'
function Info($msg) { Write-Host "[screenless] $msg" -ForegroundColor Cyan }

function Get-Devices {
  adb devices -l | Select-Object -Skip 1 | Where-Object { $_.Trim() } | ForEach-Object {
    $parts = $_ -split '\s+'
    [pscustomobject]@{ Serial = $parts[0]; State = $parts[1] }
  }
}

$devices = @(Get-Devices | Where-Object { $_.State -eq 'device' })
if ($devices.Count -eq 0) { Write-Host 'Connect exactly one phone (USB or Wi-Fi) first.' -ForegroundColor Red; exit 1 }

if ($Serial) {
  if (-not ($devices | Where-Object Serial -eq $Serial)) {
    Write-Host "Phone '$Serial' is not connected/connectable." -ForegroundColor Red; exit 1
  }
  $serial = $Serial
} elseif ($devices.Count -eq 1) {
  $serial = $devices[0].Serial
} else {
  Write-Host 'Multiple phones connected:'
  for ($i = 0; $i -lt $devices.Count; $i++) { Write-Host ("  [{0}] {1}" -f $i, $devices[$i].Serial) }
  $pick = Read-Host "Number to tune [0-$($devices.Count - 1)]"
  $idx = 0
  if (-not [int]::TryParse($pick, [ref]$idx) -or $idx -lt 0 -or $idx -ge $devices.Count) {
    Write-Host 'Invalid selection.' -ForegroundColor Red; exit 1
  }
  $serial = $devices[$idx].Serial
}

$A = @('-s', $serial)

function Get-FreeRamMB {
  $line = adb @A shell cat /proc/meminfo | Select-String 'MemAvailable:\s+(\d+)'
  [int]($line.Matches[0].Groups[1].Value) / 1024
}
$before = Get-FreeRamMB

$scale = if ($Undo) { '1.0' } else { '0.5' }
foreach ($k in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') {
  adb @A shell settings put global $k $scale
}
Info "Animation scale: $scale"

$stay = if ($Undo) { 'false' } else { 'true' }
adb @A shell svc power stayon $stay
Info "Stay awake: $stay"

if ($Debloat) {
  $pmArgs = if ($Undo) { @('enable') } else { @('disable-user', '--user', '0') }
  Get-Content $Debloat | Where-Object { $_.Trim() -and -not $_.StartsWith('#') } | ForEach-Object {
    $pkg = $_.Trim()
    $out = (adb @A shell pm @pmArgs $pkg 2>&1 | Out-String).Trim()
    Write-Host "  $pkg -> $out"
  }
}

if (-not $Undo) {
  adb @A shell am kill-all
  Start-Sleep 3
  Info ("Free RAM: {0:N0} MB -> {1:N0} MB" -f $before, (Get-FreeRamMB))
}
