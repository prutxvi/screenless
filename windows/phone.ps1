<#
.SYNOPSIS
  Mirror and control an Android phone from this Windows laptop.

.DESCRIPTION
  USB plugged in  -> mirrors over USB, remembers the phone's Wi-Fi IP and re-arms wireless mode.
  No cable        -> connects over Wi-Fi to the last remembered IP.

.EXAMPLE
  .\phone.ps1              # video only (smoothest)
  .\phone.ps1 -Audio       # also play the phone's sound on the laptop
  .\phone.ps1 -Ip 192.168.1.42
#>
param(
  [switch]$Audio,
  [string]$Ip
)

# adb writes normal status lines to stderr; don't let PowerShell treat them as fatal
$ErrorActionPreference = 'Continue'
$Port = 5555
$ConfigDir = Join-Path $env:LOCALAPPDATA 'screenless'
$IpFile = Join-Path $ConfigDir 'last-ip.txt'

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

$common = @('--video-codec=h264', '--max-fps=60', '--turn-screen-off')
if (-not $Audio) { $common += '--no-audio' }

$usb = Get-Devices | Where-Object Usb | Select-Object -First 1

if ($usb) {
  if ($usb.State -eq 'unauthorized') {
    Fail "Phone is connected but not trusted. Tick 'Always allow' on the phone's prompt, or install a trusted key (docs\WINDOWS.md, step 3)."
  }
  if ($usb.State -ne 'device') { Fail "Phone state is '$($usb.State)'. Unplug, wait 5 seconds, plug back in." }

  # Remember the Wi-Fi IP for cable-free use later
  $addr = adb -s $usb.Serial shell ip -f inet addr show wlan0 2>$null | Select-String 'inet (\d+\.\d+\.\d+\.\d+)'
  if ($addr) {
    New-Item -ItemType Directory -Force $ConfigDir | Out-Null
    $addr.Matches[0].Groups[1].Value | Set-Content $IpFile
    Info "Phone Wi-Fi IP: $($addr.Matches[0].Groups[1].Value) (saved)"
  }

  # Wireless mode turns off on every phone restart; re-arm it while we're plugged in
  adb -s $usb.Serial tcpip $Port | Out-Null
  adb -s $usb.Serial wait-for-usb-device
  adb -s $usb.Serial shell svc power stayon true
  adb -s $usb.Serial shell input keyevent KEYCODE_WAKEUP

  Info 'Mirroring over USB. Close the window to stop.'
  scrcpy -s $usb.Serial --video-bit-rate=8M --stay-awake @common
  exit $LASTEXITCODE
}

# No cable: Wi-Fi
if (-not $Ip -and (Test-Path $IpFile)) { $Ip = (Get-Content $IpFile -Raw).Trim() }
if (-not $Ip) { Fail 'No USB phone and no saved Wi-Fi IP. Plug the phone in once and run this again.' }

$target = "${Ip}:$Port"
Info "Connecting over Wi-Fi to $target ..."
$result = adb connect $target 2>&1 | Out-String
if ($result -notmatch 'connected to') {
  Fail "Could not reach $target. If the phone restarted, wireless mode is off: plug in USB once and run this again. ($($result.Trim()))"
}

adb -s $target shell svc power stayon true
adb -s $target shell input keyevent KEYCODE_WAKEUP

Info 'Mirroring over Wi-Fi. Close the window to stop.'
# Less data per frame so a weak network drops fewer frames
scrcpy -s $target --video-bit-rate=3M --max-size=1024 @common
exit $LASTEXITCODE
