# Phone agent (experimental)

Let Claude use the phone for you. Each step, it reads the screen (a screenshot plus every on-screen element with exact tap coordinates), picks one action, and performs it over adb, repeating until the task is done.

```
python agent.py "open YouTube and search for lofi music"
```

## Setup

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt        # Windows: .venv\Scripts\pip install -r requirements.txt
export ANTHROPIC_API_KEY=sk-ant-...              # Windows: $env:ANTHROPIC_API_KEY = "sk-ant-..."
```

Requires Python 3.10+, adb on PATH (comes with scrcpy), and one connected phone.

## How it works

| | |
|---|---|
| **Model** | Claude Opus 5.5 (`claude-opus-5-5`), with server-side fallback if a request is refused |
| **Sees** | Screenshot (downscaled to 1400 px) + `uiautomator` element list with real-pixel centres |
| **Can do** | tap, swipe, type text, back / home / enter / recents, open app by package, finish |
| **Safety gate** | Any action Claude marks irreversible (payment, sending a message, OTP, order, deletion, account change) waits for **y/N** in the terminal. A declined action isn't retried |
| **Limits** | 40 steps per task. ASCII typing only (`adb input text` can't type other scripts). Screens that block screenshots (banking apps, DRM video) appear black |

## Cost

Every step sends one screenshot and the element list to the API, typically a few US cents per step on Opus. Start with short tasks.

> [!CAUTION]
> This is a prototype. Watch it while it runs, keep the approval gate on, and don't point it at banking or payment apps.
