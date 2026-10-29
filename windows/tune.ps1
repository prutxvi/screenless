<#
.SYNOPSIS
  Make a slow phone feel faster while mirroring. Every change is reversible with -Undo.

.DESCRIPTION
  - Animation scales 1.0 -> 0.5 (screens open about twice as fast)
  - Keep the phone awake so the mirror never goes black
  - Optional: disable pre-installed bloatware listed in a text file (one package per line)

.EXAMPLE
  .\tune.ps1
  .\tune.ps1 -Debloat ..\debloat\motorola.txt
  .\tune.ps1 -Undo -Debloat ..\debloat\motorola.txt
#>
param(
  [string]$Debloat,
  [switch]$Undo
)

$ErrorActionPreference = 'Continue'
function Info($msg) { Write-Host "[screenless] $msg" -ForegroundColor Cyan }

$devices = @(adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\tdevice$' })
if ($devices.Count -ne 1) { Write-Host 'Connect exactly one phone (USB or Wi-Fi) first.' -ForegroundColor Red; exit 1 }

function Get-FreeRamMB {
  $line = adb shell cat /proc/meminfo | Select-String 'MemAvailable:\s+(\d+)'
  [int]($line.Matches[0].Groups[1].Value) / 1024
}
$before = Get-FreeRamMB

$scale = if ($Undo) { '1.0' } else { '0.5' }
foreach ($k in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') {
  adb shell settings put global $k $scale
}
Info "Animation scale: $scale"

$stay = if ($Undo) { 'false' } else { 'true' }
adb shell svc power stayon $stay
Info "Stay awake: $stay"

if ($Debloat) {
  $pmArgs = if ($Undo) { @('enable') } else { @('disable-user', '--user', '0') }
  Get-Content $Debloat | Where-Object { $_.Trim() -and -not $_.StartsWith('#') } | ForEach-Object {
    $pkg = $_.Trim()
    $out = (adb shell pm @pmArgs $pkg 2>&1 | Out-String).Trim()
    Write-Host "  $pkg -> $out"
  }
}

if (-not $Undo) {
  adb shell am kill-all
  Start-Sleep 3
  Info ("Free RAM: {0:N0} MB -> {1:N0} MB" -f $before, (Get-FreeRamMB))
}
