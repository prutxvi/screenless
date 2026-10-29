"""Phone agent v0: Claude drives an Android phone over adb.

Loop: screenshot + UI elements -> Claude picks an action -> adb executes -> repeat.
Anything marked irreversible (pay, send, OTP, delete, order) waits for a y/n in the terminal.

Usage:  python agent.py "open YouTube and search for lofi music"
"""

import base64
import io
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

import anthropic
from PIL import Image

ADB = os.environ.get("ADB") or shutil.which("adb") or "adb"
MODEL = "claude-opus-5-5"
MAX_STEPS = 40
SHOT_MAX_EDGE = 1400  # downscale screenshots so they stay under the vision size limit

SYSTEM = """You operate an Android phone for a user who cannot use its touchscreen.
After every action you get a fresh screenshot plus a list of on-screen UI elements with their center coordinates.

How to work:
- Prefer tapping coordinates from the UI element list; they are exact. Fall back to estimating from the screenshot only when the element is missing from the list.
- Coordinates are in real screen pixels (the element list uses them; the screenshot is scaled, its size is stated with each shot).
- Open apps with open_app using the package name when you know it; otherwise go home and find the icon.
- type_text only supports plain ASCII. If the task needs another script (Telugu, Hindi), say so and stop.
- Set irreversible=true on any action that pays money, sends a message, submits an OTP, places an order, deletes data or changes account settings. The user must approve it.
- If the user declines an action, do not retry it. Ask what they want instead by finishing.
- When the task is done or impossible, call finish with a one-line summary."""

TOOLS = [
    {
        "name": "tap",
        "description": "Tap the screen at (x, y) in real screen pixels.",
        "strict": True,
        "input_schema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer"},
                "y": {"type": "integer"},
                "target": {"type": "string", "description": "What you are tapping, e.g. 'Send button'."},
                "irreversible": {"type": "boolean"},
            },
            "required": ["x", "y", "target", "irreversible"],
            "additionalProperties": False,
        },
    },
    {
        "name": "swipe",
        "description": "Swipe from (x1, y1) to (x2, y2). Swipe up (y2 < y1) to scroll down a list.",
        "strict": True,
        "input_schema": {
            "type": "object",
            "properties": {
                "x1": {"type": "integer"}, "y1": {"type": "integer"},
                "x2": {"type": "integer"}, "y2": {"type": "integer"},
            },
            "required": ["x1", "y1", "x2", "y2"],
            "additionalProperties": False,
        },
    },
    {
        "name": "type_text",
        "description": "Type ASCII text into the focused field. Tap the field first.",
        "strict": True,
        "input_schema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "irreversible": {"type": "boolean"},
            },
            "required": ["text", "irreversible"],
            "additionalProperties": False,
        },
    },
    {
        "name": "key",
        "description": "Press a system key.",
        "strict": True,
        "input_schema": {
            "type": "object",
            "properties": {"key": {"type": "string", "enum": ["back", "home", "enter", "recents"]}},
            "required": ["key"],
            "additionalProperties": False,
        },
    },
    {
        "name": "open_app",
        "description": "Launch an app by package name, e.g. com.whatsapp.",
        "strict": True,
        "input_schema": {
            "type": "object",
            "properties": {"package": {"type": "string"}},
            "required": ["package"],
            "additionalProperties": False,
        },
    },
    {
        "name": "finish",
        "description": "End the task with a one-line summary for the user.",
        "strict": True,
        "input_schema": {
            "type": "object",
            "properties": {"summary": {"type": "string"}},
            "required": ["summary"],
            "additionalProperties": False,
        },
    },
]

KEYCODES = {"back": "KEYCODE_BACK", "home": "KEYCODE_HOME", "enter": "KEYCODE_ENTER", "recents": "KEYCODE_APP_SWITCH"}


def adb(*args, binary=False):
    out = subprocess.run([ADB, *args], capture_output=True, timeout=30)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.decode(errors="replace").strip() or f"adb {args[0]} failed")
    return out.stdout if binary else out.stdout.decode(errors="replace")


def screen_size():
    m = re.search(r"(\d+)x(\d+)", adb("shell", "wm", "size"))
    return int(m.group(1)), int(m.group(2))


def screenshot():
    """PNG of the screen, downscaled to SHOT_MAX_EDGE. Returns (base64, width, height)."""
    img = Image.open(io.BytesIO(adb("exec-out", "screencap", "-p", binary=True)))
    img.thumbnail((SHOT_MAX_EDGE, SHOT_MAX_EDGE))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.standard_b64encode(buf.getvalue()).decode(), img.width, img.height


def ui_elements():
    """Compact list of labelled / clickable nodes from uiautomator, with center coords."""
    try:
        adb("shell", "uiautomator", "dump", "/sdcard/ui.xml")
        root = ET.fromstring(adb("exec-out", "cat", "/sdcard/ui.xml"))
    except Exception as e:  # dump fails on some screens (video, secure views)
        return f"(UI element list unavailable: {e})"
    lines = []
    for node in root.iter("node"):
        label = node.get("text") or node.get("content-desc") or ""
        clickable = node.get("clickable") == "true"
        if not label and not clickable:
            continue
        m = re.findall(r"\d+", node.get("bounds", ""))
        if len(m) != 4:
            continue
        x1, y1, x2, y2 = map(int, m)
        if x2 <= x1 or y2 <= y1:
            continue
        cls = node.get("class", "").rsplit(".", 1)[-1]
        rid = node.get("resource-id", "").rsplit("/", 1)[-1]
        tag = " [tap]" if clickable else ""
        lines.append(f"({(x1 + x2) // 2},{(y1 + y2) // 2}) {cls} {label!r} {rid}{tag}".rstrip())
    return "\n".join(lines[:150]) or "(no labelled elements)"


def observe(real_w, real_h):
    """Content blocks describing the current screen."""
    data, w, h = screenshot()
    return [
        {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": data}},
        {"type": "text", "text": f"Screenshot is {w}x{h}; real screen is {real_w}x{real_h}. "
                                 f"Multiply screenshot coords by {real_w / w:.3f} for real pixels.\n"
                                 f"UI elements (real pixels):\n{ui_elements()}"},
    ]


def approve(description):
    answer = input(f"\n⚠️  Agent wants to: {description}\n   Allow? [y/N] ").strip().lower()
    return answer in ("y", "yes")


def run_tool(name, args):
    """Execute one action. Returns a short status string."""
    if args.get("irreversible"):
        what = args.get("target") or f"type {args.get('text')!r}"
        if not approve(f"{name} → {what}"):
            return "USER DECLINED this action. Do not retry it."
    if name == "tap":
        adb("shell", "input", "tap", str(args["x"]), str(args["y"]))
        return f"tapped {args['target']}"
    if name == "swipe":
        adb("shell", "input", "swipe", *map(str, (args["x1"], args["y1"], args["x2"], args["y2"])), "300")
        return "swiped"
    if name == "type_text":
        if not args["text"].isascii():
            return "ERROR: only ASCII text can be typed."
        adb("shell", "input", "text", shlex.quote(args["text"].replace(" ", "%s")))
        return "typed"
    if name == "key":
        adb("shell", "input", "keyevent", KEYCODES[args["key"]])
        return f"pressed {args['key']}"
    if name == "open_app":
        adb("shell", "monkey", "-p", args["package"], "-c", "android.intent.category.LAUNCHER", "1")
        return f"launched {args['package']}"
    return f"unknown tool {name}"


def main():
    if len(sys.argv) < 2:
        sys.exit('usage: agent.py "task for the phone"')
    task = " ".join(sys.argv[1:])
    real_w, real_h = screen_size()
    client = anthropic.Anthropic()

    messages = [{"role": "user", "content": [{"type": "text", "text": f"Task: {task}"}, *observe(real_w, real_h)]}]

    for step in range(1, MAX_STEPS + 1):
        response = client.beta.messages.create(
            model=MODEL,
            max_tokens=16000,
            system=SYSTEM,
            tools=TOOLS,
            messages=messages,
            output_config={"effort": "medium"},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        )
        if response.stop_reason == "refusal":
            sys.exit(f"Model refused: {response.stop_details}")
        messages.append({"role": "assistant", "content": response.content})

        for block in response.content:
            if block.type == "text" and block.text.strip():
                print(f"🤖 {block.text.strip()}")

        calls = [b for b in response.content if b.type == "tool_use"]
        if not calls:
            print("Agent stopped without calling finish.")
            return

        results = []
        for call in calls:
            if call.name == "finish":
                print(f"\n✅ {call.input['summary']}")
                return
            try:
                status = run_tool(call.name, call.input)
                is_error = status.startswith("ERROR")
            except Exception as e:
                status, is_error = f"ERROR: {e}", True
            print(f"  [{step}] {call.name} {call.input} → {status}")
            results.append({"type": "tool_result", "tool_use_id": call.id, "content": status, "is_error": is_error})

        # Fresh view of the screen after this step's actions, attached to the last result
        time.sleep(1.2)  # let animations settle
        results[-1]["content"] = [{"type": "text", "text": results[-1]["content"]}, *observe(real_w, real_h)]
        messages.append({"role": "user", "content": results})

    print(f"Stopped after {MAX_STEPS} steps.")


if __name__ == "__main__":
    main()
