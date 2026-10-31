# macOS guide

1. Turn on USB debugging on the phone: [WINDOWS.md, step 1](WINDOWS.md#step-1--turn-on-usb-debugging-on-the-phone) (same on every computer).
2. Install scrcpy (includes adb):
   ```bash
   brew install scrcpy
   ```
3. Get the project and run it:
   ```bash
   git clone https://github.com/prutxvi/screenless && cd screenless
   ./macos/phone.sh          # add "audio" to play the phone's sound on the Mac
   ```
4. First time only: on the phone, tick **Always allow from this computer** → **Allow**. To skip the prompt with a key from another computer, copy `adbkey` and `adbkey.pub` into `~/.android/`, then run `adb kill-server`.

Wireless works the same as on Windows: run once over USB, unplug, run again. See [WIRELESS.md](WIRELESS.md).

## The Mac app (optional)

Prefer a window to a terminal? Build the native app:

```bash
cd app/macos && ./build.sh --install
```

It lists your phones as cards with a Mirror button each, auto-reconnects, and has a pairing wizard. See the [README](../README.md#mac-app).

## Controls

Same as [Windows](WINDOWS.md#controls), with **Cmd** instead of Alt: **Cmd + P** wake/lock, **Cmd + O** phone screen off.

## Known macOS issue: port 5037 busy (rare)

If adb prints `could not install *smartsocket* listener: Address already in use` (it happens when another macOS user account left adb running), use a different port for this session:

```bash
export ANDROID_ADB_SERVER_PORT=5038
./macos/phone.sh
```

Only use this while the conflict lasts: the Mac app and the launchers must share **one** adb server. If two run on different ports, they fight over the phone and the app shows "No phone connected". `adb kill-server` and start again on the default port once 5037 is free.

If adb says `No route to host` for a phone that answers `ping`, restart the server (`adb kill-server`) from Terminal: an adb server started by another app can lose Local Network access.
