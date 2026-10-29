# Troubleshooting

Always start with `adb devices -l`. It tells you what the laptop can see.

| Symptom | Cause | Fix |
|---|---|---|
| Phone not listed at all (Windows) | Missing USB driver | Device Manager → look for an unknown Android device. Install the manufacturer's driver (Motorola: *Motorola Device Manager*; others: Google USB Driver) and replug |
| Phone not listed at all | Charge-only cable, or USB mode | Try another cable and port; set **Default USB configuration → File transfer** |
| `unauthorized` | Laptop not trusted | Tick **Always allow** on the phone prompt, or install a trusted key (`install.ps1 -KeyFolder`) and run `adb kill-server` |
| `offline` | Stale connection | Unplug, wait 5 s, replug. On Wi-Fi: `adb disconnect`, then run Phone again |
| Mirror window is black | Phone is asleep or locked | Alt+P (Cmd+P on Mac), then draw the unlock pattern with the mouse |
| `Could not reach <ip>:5555` | Phone restarted, so wireless mode is off | Plug in USB, run Phone once, unplug |
| Wi-Fi worked yesterday, not today | Phone got a new IP | Run Phone over USB once (it saves the new IP), or pass `-Ip` |
| Laggy or jumpy over Wi-Fi | Weak or 2.4 GHz network | Use 5 GHz or USB. See [WIRELESS.md](WIRELESS.md#smoothness-over-wi-fi) |
| `scrcpy` not found right after install | PATH not refreshed | Close and reopen PowerShell |
| Windows SmartScreen blocks scrcpy | Unsigned download warning | It's the official Genymobile build: **More info → Run anyway** |
| `cannot connect to daemon` / port 5037 busy | Another adb is running (Android Studio, Vysor) | Close them, or `taskkill /IM adb.exe /F`, then retry |
| Encoder error on start | Phone lacks the requested encoder | Remove `--video-codec=h264` from the launcher, or list encoders with `scrcpy --list-encoders` |
| Phone restarts by itself | Out of memory | Uninstall unused apps; run `tune` |
