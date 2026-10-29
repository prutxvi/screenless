# Performance

Measured on a **Motorola moto g30** (Snapdragon 662, 4 GB RAM, Android 12, 720×1600 @ 60 Hz), mirrored to an Apple Silicon Mac with scrcpy 5.0.1.

## What limits smoothness

| Measurement | Result | Meaning |
|---|---|---|
| Free RAM | 25–650 MB of 4 GB, 1.2 GB swap in use | Memory-starved; the kernel's `kswapd` keeps eating CPU |
| Display | 60 Hz only | 60 fps is the hard ceiling |
| Video encoder | Qualcomm H.264 (hardware) | Fast; scrcpy uses H.264 by default and the launcher pins it |
| Wi-Fi (2.4 GHz phone hotspot) | avg 70–166 ms, max 690 ms, up to 20% loss | The biggest cause of lag over Wi-Fi |
| Thermals | Normal | Not throttling |

## What we changed

| Change | Result | Undo |
|---|---|---|
| Animation scales 1.0 → 0.5 | Screens open about twice as fast | `tune -Undo` |
| Disabled 12 pre-installed apps ([list](../debloat/motorola.txt)) | Free RAM **650 → 860 MB** | `tune -Undo -Debloat ...` |
| No audio streaming by default | Less work for the phone's CPU (audio is encoded in software) | `phone -Audio` |
| Wi-Fi profile: 3 Mbps, 1024 px | Fewer dropped frames on weak Wi-Fi | Edit `phone.ps1` |
| Keep the phone awake | The mirror doesn't go black on Wi-Fi | `tune -Undo` |

## What we tried that doesn't work

- **Wi-Fi low-latency and high-performance modes** (`cmd wifi force-low-latency-mode`) are blocked without root (`SecurityException`).
- **Higher refresh rate:** this panel only supports 60 Hz.
- **Other mirroring apps:** QtScrcpy, Escrcpy and guiscrcpy wrap the same scrcpy engine, so none of them is faster. Vysor and AirDroid add more latency.

## Biggest wins, in order

1. **USB cable** instead of Wi-Fi.
2. **5 GHz Wi-Fi** instead of a 2.4 GHz hotspot.
3. **Uninstall apps you don't use.** On a 4 GB phone, RAM is the bottleneck.
4. `tune` for animations and bloatware.
