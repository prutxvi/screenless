# AGENTS.md — connect an Android phone to this laptop

Runbook for AI coding agents (OpenCode, Claude Code, Codex). Goal: the user can see and control their Android phone from this laptop with **scrcpy**, first over USB, then over Wi-Fi, through the launcher in this repo.

Work through the steps in order. After each command, compare the output with **Expect**. If it doesn't match, apply **If it fails**, then [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). Tell the user one short line per step. Use PowerShell on Windows and zsh/bash on macOS; commands below are Windows unless marked.

## Rules

- **Never read aloud, print, upload, paste or commit the contents of `adbkey`.** It's a private key that controls the phone. Copy the file locally only.
- Ask the user before installing software.
- Change phone settings only through this runbook's commands.
- Don't kill adb while Android Studio or Vysor is in use without telling the user.

## Step 1 — Tools

```powershell
Get-Command scrcpy, adb -ErrorAction SilentlyContinue | Select-Object Name, Source
```

**Expect:** both found. **If not:** ask, then run `powershell -ExecutionPolicy Bypass -File windows\install.ps1` (macOS: `brew install scrcpy`). Open a new terminal afterwards so PATH refreshes.

## Step 2 — Trust

Ask the user: *"Has this phone been connected to another computer before, and do you have its `adbkey` files?"*

- **Yes:** get the folder path and run `powershell -ExecutionPolicy Bypass -File windows\install.ps1 -KeyFolder "<path>"` (macOS: copy both files into `~/.android/`, then `adb kill-server`).
- **No:** the phone needs **USB debugging ON** (docs/WINDOWS.md, step 1). The user will tap **Allow** on the phone in step 3.

## Step 3 — USB

Ask the user to plug in the phone with a data cable, then:

```powershell
adb devices -l
```

**Expect:** a line ending in `device ... model:<phone>`.
**If it fails:**
- nothing listed → USB driver (Device Manager; install the manufacturer driver or the Google USB Driver), or a charge-only cable
- `unauthorized` → the user taps **Always allow → Allow** on the phone, or redo step 2 with the key
- `offline` → unplug, wait 5 s, replug

## Step 4 — Mirror over USB

```powershell
windows\phone.bat
```

(macOS: `./macos/phone.sh`)

**Expect:** `[screenless] Phone Wi-Fi IP: ... (saved)`, then a window showing the phone. Ask the user to confirm that clicking works. The phone's own screen turns off on purpose.

## Step 5 — Wireless

Ask the user to close the window and unplug the cable, then run `windows\phone.bat` again.

**Expect:** `Connecting over Wi-Fi to <ip>:5555`, then the window.
**If it fails:** laptop and phone must be on the same network. If the phone restarted since step 4, repeat step 4.

## Step 6 — Optional speed-up

Offer it; run it only if the user agrees:

```powershell
powershell -ExecutionPolicy Bypass -File windows\tune.ps1
```

For Motorola phones, add `-Debloat debloat\motorola.txt`. Everything can be undone with `-Undo`.

## Step 7 — Hand-off

Tell the user:
- Double-click **Phone** on the Desktop (or `windows\phone.bat`) to start.
- Left-click = tap, right-click = back, middle-click = home, **Alt+P** = wake/lock, **Alt+O** = phone screen off (Cmd on macOS).
- After the phone restarts: plug in USB, start Phone once, unplug.
