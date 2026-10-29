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

## Controls

Same as [Windows](WINDOWS.md#controls), with **Cmd** instead of Alt: **Cmd + P** wake/lock, **Cmd + O** phone screen off.

## Known macOS issue: port 5037 busy

If adb prints `could not install *smartsocket* listener: Address already in use` (it happens when another macOS user account left adb running), use a different port for this session:

```bash
export ANDROID_ADB_SERVER_PORT=5038
./macos/phone.sh
```

Add the `export` line to `~/.zshrc` to make it permanent.
