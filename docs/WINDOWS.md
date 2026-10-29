# Windows guide

Control an Android phone from a Windows 10/11 laptop: see its screen in a window and use it with your mouse and keyboard. About 10 minutes the first time, one double-click after that.

**You need:** a Windows 10 or 11 laptop, an Android phone (Android 5+; wireless needs both on the same Wi-Fi), and a USB cable that carries data (not a charge-only cable).

---

## Step 1 — Turn on USB debugging on the phone

Do this once. If the phone's screen is broken, use a USB-C OTG adapter with a mouse, or "Hey Google, open settings". If the phone is already trusted by another computer and you have its key files, skip to step 3.

1. **Settings → About phone →** tap **Build number** 7 times. You'll see "You are now a developer".
2. **Settings → System → Developer options:**
   - **USB debugging** → ON
   - **Disable adb authorization timeout** → ON (otherwise trust expires after 7 days)
   - **Default USB configuration** → **File transfer**

> [!NOTE]
> On Xiaomi/Redmi/POCO also turn on **USB debugging (Security settings)**. On Samsung, Build number is under **About phone → Software information**.

## Step 2 — Download this project

**Code → Download ZIP** on the GitHub page, then extract it, for example to `C:\screenless`.
Or with git: `git clone https://github.com/prutxvi/screenless C:\screenless`

## Step 3 — Run the installer

Open **PowerShell** (Start → type `powershell` → Enter) and run:

```powershell
cd C:\screenless\windows
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

This installs [scrcpy](https://github.com/Genymobile/scrcpy) (which includes adb) using `winget` and puts a **Phone** shortcut on your Desktop.

**Moving a phone that's already trusted somewhere else?** If you copied `adbkey` and `adbkey.pub` from the other computer (`~/.android/` on Mac/Linux, `C:\Users\<you>\.android\` on Windows), install them so the phone trusts this laptop with no prompt:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -KeyFolder D:\phone-key
```

> [!WARNING]
> `adbkey` is a private key. Anyone who has it can control the phone over USB. Keep it on a private USB stick or folder, and never commit, upload or email it.

## Step 4 — First connection (USB)

1. Plug the phone in.
2. Double-click **Phone** on the Desktop.
3. First time only (no key installed): the phone asks **"Allow USB debugging?"** → tick **Always allow from this computer** → **Allow**.

A window opens showing the phone. The phone's own screen switches off on purpose (it saves battery and protects a damaged display); the mirror keeps working.

## Step 5 — Go wireless

Running **Phone** over USB also turns on wireless mode and saves the phone's Wi-Fi address. Now:

1. Unplug the cable.
2. Double-click **Phone** again.

It connects over Wi-Fi. Phone and laptop must be on the same network.

> [!IMPORTANT]
> Android switches wireless mode **off every time the phone restarts**. Plug in the cable, double-click **Phone** once, unplug. See [WIRELESS.md](WIRELESS.md) for the reasons and a way to automate it.

## Step 6 (optional) — Make a slow phone faster

With the phone connected:

```powershell
cd C:\screenless\windows
powershell -ExecutionPolicy Bypass -File .\tune.ps1                                  # faster animations + stay awake
powershell -ExecutionPolicy Bypass -File .\tune.ps1 -Debloat ..\debloat\motorola.txt # also disable Motorola bloatware
powershell -ExecutionPolicy Bypass -File .\tune.ps1 -Undo -Debloat ..\debloat\motorola.txt  # undo everything
```

Details and measurements: [PERFORMANCE.md](PERFORMANCE.md).

---

## Controls

| Action | How |
|---|---|
| Tap | Left-click |
| Back | Right-click |
| Home | Middle-click |
| Scroll | Mouse wheel or touchpad |
| Type | Just type |
| Wake / lock (power button) | **Alt + P** |
| Turn the phone's screen off again | **Alt + O** |
| Recent apps | **Alt + S** |
| Copy phone ↔ laptop clipboard | Ctrl + C / Ctrl + V work both ways |
| Unlock pattern | Click and drag the pattern with the mouse |
| Install an APK | Drag the `.apk` file onto the window |

## Options

```powershell
.\phone.bat -Audio              # also play the phone's sound on the laptop
.\phone.bat -Ip 192.168.1.42    # connect to a specific Wi-Fi address
```

## Let an AI agent do the setup

If you use an AI coding agent (OpenCode, Claude Code, Codex), open it in the project folder and say:

> Read AGENTS.md and connect my phone to this laptop.

[AGENTS.md](../AGENTS.md) is a step-by-step runbook it can follow: it runs each command, checks the result, and handles the common failures.

Something wrong? → [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
