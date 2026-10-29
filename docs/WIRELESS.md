# Wireless mode

## How it works

Over USB, the launcher runs `adb tcpip 5555`, which tells the phone to also accept adb connections over Wi-Fi on port 5555, and saves the phone's IP address. Later, with no cable, it runs `adb connect <ip>:5555`.

The phone only accepts computers whose adb key it already trusts, so other devices on the network can't connect.

## The restart limitation

Android turns wireless adb **off on every restart**, and an app can't turn it back on without root. Choose one:

| Way back | Effort | Needs the phone's screen |
|---|---|---|
| **Plug in USB, run Phone, unplug** | 10 seconds | No |
| **Developer options → Wireless debugging** (Android 11+) → *Pair device with pairing code*, then `adb pair <ip:port> <code>` and `adb connect <ip:port>` | 1 minute | Yes |
| **Automate it at boot** (below) | One-time setup | Only for setup |

## Automate it at boot (Android 11+, experimental)

An automation app can switch on **Wireless debugging** when the phone boots, provided it's given one extra permission over adb.

1. Install **MacroDroid** (free) from the Play Store.
2. With the phone connected, grant it permission to change secure settings:
   ```
   adb shell pm grant com.arlosoft.macrodroid android.permission.WRITE_SECURE_SETTINGS
   ```
3. In MacroDroid, create a macro: Trigger **Device Boot** → Action **System Setting**, table **Global**, key `adb_wifi_enabled`, value `1`.
4. Pair the laptop once: **Developer options → Wireless debugging → Pair device with pairing code**, then `adb pair <ip:port> <code>`.

Wireless debugging (unlike `tcpip 5555`) uses a **random port**. adb finds paired phones on the network by itself (mDNS), so check with `adb devices` after a restart, or `adb mdns services`.

> [!NOTE]
> Behaviour varies by manufacturer and Android version, and some networks block mDNS. The USB method always works.

## Smoothness over Wi-Fi

What matters is the Wi-Fi itself, not the phone. From our measurements ([PERFORMANCE.md](PERFORMANCE.md)): a 2.4 GHz phone hotspot averaged **70–166 ms** with peaks of **690 ms** and up to 20% packet loss, which no mirroring setting can fix.

- Use a **5 GHz** network. On an iPhone hotspot, turn **Maximize Compatibility** off. On an Android hotspot, set **AP band → 5 GHz**.
- Keep the laptop and phone near the router.
- On Wi-Fi the launcher automatically lowers quality (3 Mbps, 1024 px) so fewer frames are dropped.
- For the lowest lag, use USB.
