<#
.SYNOPSIS
  Mirror and control an Android phone from this Windows laptop.

.DESCRIPTION
  USB plugged in  -> mirrors over USB, remembers the phone's Wi-Fi IPs and re-arms wireless mode.
  No cable        -> tries every remembered Wi-Fi IP, then discovers the phone on the network
                     via adb mDNS (Android 11+ wireless debugging), then connects to the first
                     that answers. If the mirror drops mid-session it reconnects automatically.

  One text record per device is kept in %LOCALAPPDATA%\screenless\devices\<serial>.conf so the
  launcher and the macOS launcher share the same bookkeeping format.

.EXAMPLE
  .\phone.ps1                    # video only (smoothest)
  .\phone.ps1 -Audio             # also play the phone's sound on the laptop (Android 11+)
  .\phone.ps1 -Ip 192.168.1.42   # connect to a specific Wi-Fi address right now
  .\phone.ps1 -Serial ABC123     # pick a specific USB phone when several are connected
#>
param(
  [switch]$Audio,
  [string]$Ip,
  [string]$Serial
)

# adb writes normal status lines to stderr; don't let PowerShell treat them as fatal
$ErrorActionPreference = 'Continue'
$Port = 5555
$ConfigDir = Join-Path $env:LOCALAPPDATA 'screenless'
$DeviceDir = Join-Path $ConfigDir 'devices'
$LegacyIpFile = Join-Path $ConfigDir 'last-ip.txt'
$MaxSavedIps = 5
$MaxRetries = 3
$RetryDelaySeconds = 3

function Fail($msg) { Write-Host "`n[screenless] $msg" -ForegroundColor Red; exit 1 }
function Info($msg) { Write-Host "[screenless] $msg" -ForegroundColor Cyan }

foreach ($tool in 'adb', 'scrcpy') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    Fail "$tool not found. Run windows\install.ps1 first (or open a new terminal after installing)."
  }
}

# Parse `adb devices -l` into objects: Serial, State, Usb
function Get-Devices {
  adb devices -l | Select-Object -Skip 1 | Where-Object { $_.Trim() } | ForEach-Object {
    $parts = $_ -split '\s+'
    [pscustomobject]@{ Serial = $parts[0]; State = $parts[1]; Usb = ($_ -match '\busb:') }
  }
}

# Read a system property from a device (serial or ip:port)
function Get-Prop($Transport, $Name) {
  ((adb -s $Transport shell getprop $Name 2>$null) | Out-String).Trim()
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
    # Newest IP first, capped so DHCP churn over months can't grow the file
    $known = @()
    if ($record['ips']) { $known = @($record['ips'] -split ',' | Where-Object { $_ }) }
    $ips = @($NewIp) + @($known | Where-Object { $_ -and $_ -ne $NewIp })
    $record['ips'] = (($ips | Select-Object -First $MaxSavedIps) -join ',')
  }

  New-Item -ItemType Directory -Force $DeviceDir | Out-Null
  ($record.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n" |
    Set-Content -Path $path -Encoding ASCII
}

# Every remembered Wi-Fi IP, newest device first; also imports the old last-ip.txt once
function Get-KnownIps {
  $known = New-Object System.Collections.Generic.List[string]
  if (Test-Path $DeviceDir) {
    foreach ($recordPath in (Get-ChildItem $DeviceDir -Filter '*.conf' | Sort-Object LastWriteTime -Descending)) {
      foreach ($line in (Get-Content $recordPath.FullName)) {
        if ($line -match '^ips=(.*)$') {
          foreach ($ip in ($matches[1] -split ',')) {
            $ip = $ip.Trim()
            if ($ip -and -not $known.Contains($ip)) { $known.Add($ip) }
          }
        }
      }
    }
  }
  if (Test-Path $LegacyIpFile) {
    # (opencode) validate the legacy file actually holds an IP address
    $legacy = (Get-Content $LegacyIpFile -Raw -ErrorAction SilentlyContinue).Trim()
    if ($legacy.Trim() -match '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})') { $legacy = $matches[1] } else { $legacy = $null }
    if ($legacy) {
      if (-not $known.Contains($legacy)) { $known.Add($legacy) }
      Save-DeviceRecord 'legacy-device' '' '' $legacy
    }
  }
  return $known
}

# Phones advertising wireless-debugging connect services on this network (Android 11+, already paired)
function Find-MdnsEndpoints {
  $out = (adb mdns services 2>$null | Out-String)
  if ($out -notmatch '_adb-tls-connect\.') { return @() }
  $endpoints = @()
  foreach ($m in [regex]::Matches($out, '(\d+\.\d+\.\d+\.\d+):(\d+)')) {
    $endpoints += "$($m.Groups[1].Value):$($m.Groups[2].Value)"
  }
  return $endpoints | Select-Object -Unique
}

function Get-Model($Transport) {
  # Prefer the saved record (works even when the phone is unreachable), fall back to adb
  $record = Read-DeviceRecord $Transport
  if ($record -and $record['model']) { return $record['model'] }
  return Get-Prop $Transport 'ro.product.model'
}

# Try each address once; returns which one connected, or $null
function Connect-First([string[]]$Targets) {
  foreach ($target in $targets) {
    # Skip addresses that don't answer within 2 s (adb connect alone can hang for a minute)
    $hostPart, $portPart = $target -split ':'
    $probe = New-Object System.Net.Sockets.TcpClient
    $open = $false
    try { $open = $probe.ConnectAsync($hostPart, [int]$portPart).Wait(2000) } catch { $open = $false }
    $probe.Close()
    if (-not $open) { Info "  $target not reachable on this network, skipping"; continue }
    Info "Connecting over Wi-Fi to $target ..."
    $result = (adb connect $target 2>&1 | Out-String)
    if ($result -match 'connected to') { return $target }
    Info "  $target did not answer ($($result.Trim()))"
  }
  return $null
}

$common = @('--video-codec=h264', '--max-fps=60', '--turn-screen-off')
if (-not $Audio) { $common += '--no-audio' }

# --- pick the USB phone (if any) ---
$usbs = @(Get-Devices | Where-Object Usb)

$usb = $null
if ($usbs.Count -gt 1) {
  if ($Serial) {
    $usb = $usbs | Where-Object { $_.Serial -eq $Serial } | Select-Object -First 1
    if (-not $usb) { Fail "Serial '$Serial' is not among the USB devices connected: $($usbs.Serial -join ', ')" }
  } else {
    Info 'Multiple USB devices connected:'
    for ($i = 0; $i -lt $usbs.Count; $i++) {
      $label = Get-Model $usbs[$i].Serial
      Write-Host ("  [{0}] {1}  {2}  {3}" -f $i, $usbs[$i].Serial, $usbs[$i].State, $label)
    }
    $pick = Read-Host "Number to mirror [0-$($usbs.Count - 1)]"
    $idx = 0
    if (-not [int]::TryParse($pick, [ref]$idx) -or $idx -lt 0 -or $idx -ge $usbs.Count) {
      Fail 'Invalid selection.'
    }
    $usb = $usbs[$idx]
  }
} elseif ($usbs.Count -eq 1) { $usb = $usbs[0] }

if ($usb) {
  if ($usb.State -eq 'unauthorized') {
    Fail "Phone is connected but not trusted. Tick 'Always allow' on the phone's prompt, or install a trusted key (docs\WINDOWS.md, step 3)."
  }
  if ($usb.State -ne 'device') { Fail "Phone state is '$($usb.State)'. Unplug, wait 5 seconds, plug back in." }
  $UsbSerial = $usb.Serial

  if ($Audio) {
    # Audio forwarding needs Android 11+ (SDK 30); on older phones fall back to video-only
    $sdk = (Get-Prop $UsbSerial 'ro.build.version.sdk') -as [int]
    if ($sdk -and $sdk -lt 30) {
      Write-Host "[screenless] Phone runs Android SDK $sdk; audio forwarding needs Android 11 (SDK 30). Continuing video-only." -ForegroundColor Yellow
      $common = @('--video-codec=h264', '--max-fps=60', '--turn-screen-off', '--no-audio')
      $Audio = $false
    }
  }

  # Save the phone's current Wi-Fi IP (one record per device, history of IPs) for cable-free use
  $phoneIp = $null
  $addrLines = adb -s $UsbSerial shell ip -f inet addr show wlan0 2>$null | Out-String
  $addr = $addrLines | Select-String 'inet (\d+\.\d+\.\d+\.\d+)'
  if ($addr) {
    $phoneIp = $addr.Matches[0].Groups[1].Value
    Save-DeviceRecord $UsbSerial (Get-Prop $UsbSerial 'ro.product.model') (Get-Prop $UsbSerial 'ro.build.version.release') $phoneIp
    Info "Phone Wi-Fi IP: $phoneIp (saved)"
  } else {
    Save-DeviceRecord $UsbSerial (Get-Prop $UsbSerial 'ro.product.model') (Get-Prop $UsbSerial 'ro.build.version.release') $null
    Info 'Could not read the phone''s Wi-Fi IP (no Wi-Fi/data connection?). Wireless reconnection later may fail.'
  }

  # Wireless mode turns off on every phone restart; re-arm it while we're plugged in
  # (adbd restarts after tcpip, so wait until the phone is back on USB)
  adb -s $UsbSerial tcpip $Port | Out-Null
  for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 500
    if ((adb -s $UsbSerial get-state 2>$null) -eq 'device') { break }
  }
  adb -s $UsbSerial shell input keyevent KEYCODE_WAKEUP | Out-Null

  Info 'Mirroring over USB. Close the window to stop.'
  $attempt = 0
  while ($true) {
    scrcpy -s $UsbSerial --video-bit-rate=8M --stay-awake @common
    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) { break }   # window closed normally
    $attempt++
    if ($attempt -gt $MaxRetries) { Fail "scrcpy kept failing (exit $exitCode)." }
    Info "Mirror dropped (exit $exitCode). Retrying in $RetryDelaySeconds s ... [$attempt/$MaxRetries]"
    Start-Sleep $RetryDelaySeconds
    if (-not (Get-Devices | Where-Object { $_.Serial -eq $UsbSerial -and $_.State -eq 'device' })) {
      Info 'Phone no longer visible over USB. Waiting up to 30 s for it to come back ...'
      $found = $false
      for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep 2
        if (Get-Devices | Where-Object { $_.Serial -eq $UsbSerial -and $_.State -eq 'device' }) { $found = $true; break }
      }
      if (-not $found) { Fail 'Phone did not come back. Check the cable and run Phone again.' }
    }
  }
  exit 0
}

# --- no cable: reconnect over Wi-Fi ---
$targets = @()
# A phone adb already holds over Wi-Fi wins (e.g. connected by an earlier run)
$live = Get-Devices | Where-Object { $_.State -eq 'device' -and $_.Serial -match ':\d+$' } | Select-Object -First 1
if ($live) { $targets += $live.Serial }
if ($Ip) { $targets += "${Ip}:$Port" }
$targets += @(Get-KnownIps | ForEach-Object { "$($_):$Port" })
$targets += @(Find-MdnsEndpoints)
$targets = @($targets | Select-Object -Unique)

if ($targets.Count -eq 0) {
  Fail 'No USB phone, no remembered Wi-Fi IP, and nothing discovered on the network. Plug the phone in once and run this again.'
}

$target = Connect-First $targets
if (-not $target) {
  Fail "Could not reach any address: $($targets -join ', '). If the phone restarted, wireless mode is off: plug in USB once and run this again."
}
Info "Connected to $target."

adb -s $target shell input keyevent KEYCODE_WAKEUP | Out-Null

Info 'Mirroring over Wi-Fi. Close the window to stop.'
# Lower bitrate/size so a weak network drops fewer frames; watchdog reconnects on a drop
$wifiArgs = @('--video-bit-rate=3M', '--max-size=1024')
$attempt = 0
$finalExit = 0
while ($true) {
  scrcpy -s $target --stay-awake @common @wifiArgs
  $exitCode = $LASTEXITCODE
  if ($exitCode -eq 0) { break }   # window closed normally

  $attempt++
  if ($attempt -gt $MaxRetries) {
    Info "Wi-Fi reconnect failed after $MaxRetries attempts."
    $finalExit = $exitCode
    break
  }
  Info "Mirror dropped (exit $exitCode). Reconnecting ... [$attempt/$MaxRetries]"
  Start-Sleep $RetryDelaySeconds

  # Drop the stale transport, then retry the last address, then every other remembered one
  adb disconnect $target 2>$null | Out-Null
  $candidates = @(@($target) + @($targets | Where-Object { $_ -ne $target }))
  $target = Connect-First $candidates

  if (-not $target) {
    # Nothing remembered answered: ask adb for phones advertising on the network right now
    $fresh = @(Find-MdnsEndpoints)
    if ($fresh.Count) { Info 'Discovering wireless-debugging devices on this network ...' }
    $target = Connect-First $fresh
  }
  if ($target) { $attempt = 0 }   # got a fresh session: reset the retry budget
}

# Close our session so no half-open transport lingers (wireless mode itself stays armed until phone reboot)
adb disconnect $target 2>$null | Out-Null
exit $finalExit
