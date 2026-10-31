<#
.SYNOPSIS
  Guided pairing: connect a phone over Wi-Fi without USB first (Android 11+).

.DESCRIPTION
  While the phone shows its "Pair device with pairing code" dialog it
  advertises the pairing service on the network. This wizard waits for that
  announcement (mDNS), pairs with your 6-digit code, then connects to the
  phone's advertised connect service and saves it into the same device
  record phone.ps1 uses.

  Honesty note: you need the phone's screen (or voice control that can reach
  Developer options) to read the code. A phone with a fully dead screen must
  be paired the USB way (docs\WINDOWS.md): there is no cold wireless pairing
  without Android authorization, whoever claims otherwise.

.EXAMPLE
  .\pair.ps1                     # guided flow
  .\pair.ps1 192.168.1.42:39089 123456   # explicit endpoint + code
#>
param(
  [string]$Endpoint,
  [string]$Code
)

$ErrorActionPreference = 'Continue'
$ConfigDir = Join-Path $env:LOCALAPPDATA 'screenless'
$DeviceDir = Join-Path $ConfigDir 'devices'
$MaxSavedIps = 5

function Info($msg) { Write-Host "[screenless-pair] $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "[screenless-pair] $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "`n[screenless-pair] $msg" -ForegroundColor Red; exit 1 }

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  Fail "adb not found. Run windows\install.ps1 first (or open a new terminal after installing)."
}

# ---------------------------------------------------------------------------
# Device bookkeeping: <serial>.conf with serial=/model=/android=/last_seen=/ips=
# ---------------------------------------------------------------------------
function Get-DeviceRecordPath($DeviceSerial) {
  $safe = ($DeviceSerial -replace '[^A-Za-z0-9_.-]', '_')
  Join-Path $DeviceDir "$safe.conf"
}

function Read-DeviceRecord($DeviceSerial) {
  $path = Get-DeviceRecordPath $DeviceSerial
  if (-not (Test-Path $path)) { return $null }
  $record = [ordered]@{}
  foreach ($line in (Get-Content $path)) {
    if ($line -match '^([A-Za-z_]+)=(.*)$') { $record[$matches[1]] = $matches[2] }
  }
  return $record
}

function Save-DeviceRecord($DeviceSerial, $Model, $Android, $NewIp) {
  $path = Get-DeviceRecordPath $DeviceSerial
  $record = Read-DeviceRecord $DeviceSerial
  if (-not $record) {
    $record = [ordered]@{ serial = $DeviceSerial; model = ''; android = ''; last_seen = ''; ips = '' }
  }
  if ($Model) { $record['model'] = $Model }
  if ($Android) { $record['android'] = $Android }
  $record['last_seen'] = (Get-Date).ToString('o')

  if ($NewIp) {
    $known = @()
    if ($record['ips']) { $known = @($record['ips'] -split ',' | Where-Object { $_ }) }
    $ips = @($NewIp) + @($known | Where-Object { $_ -and $_ -ne $NewIp })
    $record['ips'] = (($ips | Select-Object -First $MaxSavedIps) -join ',')
  }

  New-Item -ItemType Directory -Force $DeviceDir | Out-Null
  ($record.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n" |
    Set-Content -Path $path -Encoding ASCII
}

# Extract ip:port pairs from adb's mdns output for a given service type
function Find-MdnsPairings {
  $out = (adb mdns services 2>$null | Out-String)
  if ($out -notmatch '_adb-tls-pairing\.') { return @() }
  $found = @()
  foreach ($m in [regex]::Matches($out, '(\d+\.\d+\.\d+\.\d+):(\d+)')) {
    $found += "$($m.Groups[1].Value):$($m.Groups[2].Value)"
  }
  return $found | Select-Object -Unique
}

function Find-MdnsConnects {
  $out = (adb mdns services 2>$null | Out-String)
  if ($out -notmatch '_adb-tls-connect\.') { return @() }
  $found = @()
  foreach ($m in [regex]::Matches($out, '(\d+\.\d+\.\d+\.\d+):(\d+)')) {
    $found += "$($m.Groups[1].Value):$($m.Groups[2].Value)"
  }
  return $found | Select-Object -Unique
}

function Get-Prop($Transport, $Name) {
  ((adb -s $Transport shell getprop $Name 2>$null) | Out-String).Trim()
}

# Old platform-tools (pre-31) has no adb pair
$adbVersion = (adb --version 2>$null | Select-String -Pattern 'Version\s+(\d+)\.').Matches[0].Groups[1].Value
if ([int]$adbVersion -lt 31) {
  Fail "This adb is too old for wireless pairing; platform-tools 31+ is required (install.ps1 downloads a recent adb)."
}

if (-not $Endpoint -or -not $Code) {
  Write-Host "== Guided wireless pairing (Android 11+) ==" -ForegroundColor Cyan
  Write-Host ""
  Write-Host "On the phone (its screen must be usable):"
  Write-Host "  1. Settings -> Developer options -> turn ON  Wireless debugging"
  Write-Host "  2. Tap  PAIR DEVICE WITH PAIRING CODE  and leave that screen open"
  Write-Host "(The 6-digit code and this dialog's port disappear when it closes, so"
  Write-Host " keep it open until pairing succeeds.)"
  Write-Host ""

  Info 'Searching for the phone pairing announcement ... (leave the dialog open)'
  $endpoints = @()
  for ($i = 0; $i -lt 30 -and -not $endpoints.Count; $i++) {
    $endpoints = @(Find-MdnsPairings) | Where-Object { $_ }
    if (-not $endpoints.Count) { Start-Sleep 2 }
    if ($i % 5 -eq 0) { Info "  nothing yet ($($i * 2) s) ..." }
  }

  if ($endpoints.Count -gt 1) {
    for ($j = 0; $j -lt $endpoints.Count; $j++) { Write-Host "  [$j] $($endpoints[$j])" }
    $pick = Read-Host 'Number to pair with [0], or type ip:port'
    if ($pick -match '^\d+$' -and $pick -lt $endpoints.Count) { $Endpoint = $endpoints[$pick] }
    elseif ($pick) { $Endpoint = $pick }
    else { $Endpoint = $endpoints[0] }
  } elseif ($endpoints.Count -eq 1) {
    $Endpoint = $endpoints[0]
  } else {
    $Endpoint = Read-Host 'No pairing service found via mDNS. Type ip:port as shown on the phone'
  }
}

if ($Endpoint -notmatch ':\d+$') { Fail "Endpoint must look like IP:PORT, e.g. 192.168.1.42:39089" }
if (-not $Code) { $Code = Read-Host '6-digit pairing code from the phone' }
if ($Code -notmatch '^\d{6}$') { Fail 'The code is exactly 6 digits.' }

Info "Pairing with $Endpoint ..."
$out = (adb pair $Endpoint $Code 2>&1 | Out-String)
if ($out -notmatch 'uccess') {
  Fail "Pairing failed: $($out.Trim()) - the code expires fast; reopen the pairing dialog and try again."
}
Info $out.Trim()

# The phone now advertises its (different) connect endpoint
Info "Finding the phone connect service ..."
$connectEndpoints = @(Find-MdnsConnects)
if (-not $connectEndpoints.Count) {
  $connectEndpoints = @((Read-Host 'No connect service found via mDNS; type the phone connect address shown in Developer options'))
}
$connected = $false
$serial = $null
foreach ($target in $connectEndpoints) {
  $result = (adb connect $target 2>&1 | Out-String)
  if ($result -match 'connected to') {
    $connected = $true
    $found = adb devices | Select-String "^\S*$([regex]::Escape($target))\s+device"
    if ($found) { $serial = $found.Matches[0].Value -split '\s+' | Select-Object -First 1 }
    break
  }
}
if (-not $connected) { Fail "Could not connect to any advertised address. The phone may have closed wireless debugging." }

if (-not $serial) { $serial = $connectEndpoints | Select-Object -First 1 }
$model = Get-Prop $serial 'ro.product.model'
$android = Get-Prop $serial 'ro.build.version.release'
Save-DeviceRecord $serial $model $android (($connectEndpoints[0] -split ':')[0])

Info "$model (Android $android) is saved and connected."
Info 'From now on just run phone.ps1 - it reconnects on its own.'
