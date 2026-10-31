<#
.SYNOPSIS
  One-time setup on a Windows laptop: installs scrcpy (with adb), optionally installs a
  trusted adb key, and puts a "Phone" shortcut on the Desktop.

.EXAMPLE
  .\install.ps1                         # install scrcpy + shortcut
  .\install.ps1 -KeyFolder D:\phone-key # also trust an existing key (no prompt on the phone)
#>
param([string]$KeyFolder)

$ErrorActionPreference = 'Stop'
function Info($msg) { Write-Host "[screenless] $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "[screenless] $msg" -ForegroundColor Red; exit 1 }

# 1. scrcpy (bundles adb)
if (Get-Command scrcpy -ErrorAction SilentlyContinue) {
  Info "scrcpy already installed: $((scrcpy --version | Select-Object -First 1))"
} elseif (Get-Command winget -ErrorAction SilentlyContinue) {
  Info 'Installing scrcpy via winget ...'
  winget install --exact --id Genymobile.scrcpy --accept-source-agreements --accept-package-agreements
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
} else {
  # Fall back: no winget (older Win10/LTSC often lacks it) — download the official
  # Genymobile release zip directly and put it on the user PATH.
  $zipDir = Join-Path $env:LOCALAPPDATA 'Programs\screenless\scrcpy'
  Info 'winget not found. Downloading the official scrcpy release from GitHub ...'
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod 'https://api.github.com/repos/Genymobile/scrcpy/releases/latest'
    $asset = $release.assets | Where-Object { $_.name -match '^scrcpy-win64-.*\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw 'No win64 zip asset in the latest release' }
    $destZip = Join-Path $env:TEMP $asset.name
    Info "Downloading $($asset.name) ($([math]::Round($asset.size / 1MB)) MB) ..."
    Invoke-WebRequest $asset.browser_download_url -OutFile $destZip -UseBasicParsing
    if (Test-Path $zipDir) { Remove-Item $zipDir -Recurse -Force }
    Expand-Archive $destZip -DestinationPath $zipDir -Force
    Remove-Item $destZip -ErrorAction SilentlyContinue

    # put the extracted folder (binaries live in its root) on the user PATH
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath -notlike "*$zipDir*") {
      [Environment]::SetEnvironmentVariable('Path', "$zipDir;$userPath", 'User')
    }
    $env:Path = "$zipDir;$env:Path"
    Info "scrcpy installed to $zipDir and added to your PATH."
  } catch {
    Fail "Could not download scrcpy automatically ($($_.Exception.Message)). Download scrcpy-win64 from https://github.com/Genymobile/scrcpy/releases, extract it, and add the folder to PATH."
  }
}

# 2. Optional trusted key
if ($KeyFolder) {
  foreach ($f in 'adbkey', 'adbkey.pub') {
    if (-not (Test-Path (Join-Path $KeyFolder $f))) { Fail "Missing $f in $KeyFolder" }
  }
  $adbDir = Join-Path $env:USERPROFILE '.android'
  New-Item -ItemType Directory -Force $adbDir | Out-Null
  $stamp = Get-Date -Format yyyyMMddHHmmss
  foreach ($f in 'adbkey', 'adbkey.pub') {
    $dest = Join-Path $adbDir $f
    if (Test-Path $dest) { Rename-Item $dest "$f.backup-$stamp"; Info "Backed up existing $f" }
    Copy-Item (Join-Path $KeyFolder $f) $dest
  }
  if (Get-Command adb -ErrorAction SilentlyContinue) { adb kill-server | Out-Null }
  Info 'Trusted key installed.'
}

# 3. Desktop shortcut
$bat = Join-Path $PSScriptRoot 'phone.bat'
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Phone.lnk'
$shell = New-Object -ComObject WScript.Shell
$sc = $shell.CreateShortcut($lnk)
$sc.TargetPath = $bat
$sc.WorkingDirectory = $PSScriptRoot
$sc.Save()
Info "Desktop shortcut created: $lnk"

Info 'Done. Plug in the phone and double-click "Phone" on the Desktop.'
