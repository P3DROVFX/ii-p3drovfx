#!/usr/bin/env python3
"""Layout-aware keystroke reporter for the on-screen keystroke overlay.

Reads `/dev/input/event*` directly through evdev and prints one JSON object per
line on stdout, which `KeypressService.qml` turns into on-screen chips.

Why evdev and not the compositor: Wayland deliberately gives no client the
global key stream, and Quickshell only ever sees the keys pressed while one of
its own surfaces has focus.  Reading the kernel devices is the same route
`showmethekey` takes.  It needs no root here because the user is in the `input`
group; if that ever stops being true the script exits with a clear message
instead of silently reporting nothing.

Why xkb and not a keycode table: evdev reports *physical* keys, so on an AZERTY
keyboard the key a US table calls `A` is really `Q`.  libxkbcommon translates
using the very layout Hyprland has loaded, which is the only way the overlay can
show what the user actually typed.  Without the bindings installed the script
still runs, falling back to the US names carried by evdev itself.

Modifiers also report their *release*, so the overlay can keep a held `Ctrl`
visibly pressed down until it is let go.  Ordinary keys only report presses,
plus their auto-repeat when `--repeats` is given, which is how a held Backspace
becomes a climbing `×N` on screen rather than a single chip.

Nothing is ever written to disk: the stream exists only for as long as the
overlay is visible, and dies with the process.
"""

from __future__ import annotations

import argparse
import json
import os
import select
import sys
import time

try:
    import evdev
    from evdev import ecodes
except ImportError:  # pragma: no cover - guarded at the QML layer too
    print(json.dumps({"type": "error", "message": "python-evdev is not installed"}), flush=True)
    sys.exit(1)

try:
    from xkbcommon import xkb
except ImportError:  # optional: the US fallback below keeps the overlay usable
    xkb = None


# How often the device list is re-read, so a keyboard plugged in mid-recording
# starts being reported without restarting the overlay.
RESCAN_INTERVAL = 2.0
# Two devices reporting the same key this close together are the same physical
# press seen twice (a remapper's virtual device next to the real one).
DEDUP_WINDOW = 0.015

# Keys that are only ever a modifier: they are reported on their own, and are
# also what turns a following key into a shortcut.
MODIFIER_KEYS = {
    ecodes.KEY_LEFTCTRL: "Ctrl",
    ecodes.KEY_RIGHTCTRL: "Ctrl",
    ecodes.KEY_LEFTSHIFT: "Shift",
    ecodes.KEY_RIGHTSHIFT: "Shift",
    ecodes.KEY_LEFTALT: "Alt",
    ecodes.KEY_RIGHTALT: "AltGr",
    ecodes.KEY_LEFTMETA: "Super",
    ecodes.KEY_RIGHTMETA: "Super",
}

# Keys with no printable form, named the way a keyboard is labelled rather than
# the way the kernel spells it.
NAMED_KEYS = {
    ecodes.KEY_ESC: "Esc",
    ecodes.KEY_TAB: "Tab",
    ecodes.KEY_ENTER: "Enter",
    ecodes.KEY_KPENTER: "Enter",
    ecodes.KEY_BACKSPACE: "Backspace",
    ecodes.KEY_DELETE: "Delete",
    ecodes.KEY_INSERT: "Insert",
    ecodes.KEY_HOME: "Home",
    ecodes.KEY_END: "End",
    ecodes.KEY_PAGEUP: "PgUp",
    ecodes.KEY_PAGEDOWN: "PgDn",
    ecodes.KEY_UP: "↑",
    ecodes.KEY_DOWN: "↓",
    ecodes.KEY_LEFT: "←",
    ecodes.KEY_RIGHT: "→",
    ecodes.KEY_CAPSLOCK: "CapsLock",
    ecodes.KEY_NUMLOCK: "NumLock",
    ecodes.KEY_SCROLLLOCK: "ScrollLock",
    ecodes.KEY_SPACE: "Space",
    ecodes.KEY_SYSRQ: "PrtSc",
    ecodes.KEY_PAUSE: "Pause",
    ecodes.KEY_MENU: "Menu",
    ecodes.KEY_COMPOSE: "Menu",
}
for _fn in range(1, 25):
    _code = getattr(ecodes, f"KEY_F{_fn}", None)
    if _code is not None:
        NAMED_KEYS[_code] = f"F{_fn}"

MOUSE_BUTTONS = {
    ecodes.BTN_LEFT: "Click",
    ecodes.BTN_RIGHT: "Right click",
    ecodes.BTN_MIDDLE: "Middle click",
    ecodes.BTN_SIDE: "Back",
    ecodes.BTN_EXTRA: "Forward",
}

# Keysym names that libxkbcommon returns for keys the tables above already
# cover; anything else falls through to its keysym name with underscores fixed.
SYM_RENAMES = {
    "Return": "Enter",
    "Escape": "Esc",
    "Prior": "PgUp",
    "Next": "PgDn",
    "BackSpace": "Backspace",
    "Up": "↑",
    "Down": "↓",
    "Left": "←",
    "Right": "→",
    "space": "Space",
    "ISO_Level3_Shift": "AltGr",
}


class Translator:
    """Turns an evdev keycode into the label a user would recognise."""

    def __init__(self, layout: str, variant: str, options: str):
        self.state = None
        if xkb is None:
            return
        try:
            keymap = xkb.Context().keymap_new_from_names(
                layout=layout or "us",
                variant=variant or "",
                options=options or "",
            )
            self.state = keymap.state_new()
        except Exception as exc:  # a bad layout string must not kill the stream
            note(f"xkb keymap for '{layout}' failed ({exc}); falling back to US names")
            self.state = None

    @property
    def layout_aware(self) -> bool:
        return self.state is not None

    def update(self, code: int, pressed: bool) -> None:
        if self.state is None:
            return
        direction = xkb.XKB_KEY_DOWN if pressed else xkb.XKB_KEY_UP
        self.state.update_key(code + 8, direction)

    def active_modifiers(self) -> list[str]:
        if self.state is None:
            return []
        effective = xkb.XKB_STATE_MODS_EFFECTIVE
        mods = []
        if self.state.mod_name_is_active("Control", effective):
            mods.append("Ctrl")
        if self.state.mod_name_is_active("Mod1", effective) or self.state.mod_name_is_active("Alt", effective):
            mods.append("Alt")
        if self.state.mod_name_is_active("Mod4", effective) or self.state.mod_name_is_active("Super", effective):
            mods.append("Super")
        if self.state.mod_name_is_active("Shift", effective):
            mods.append("Shift")
        return mods

    def label(self, code: int, as_shortcut: bool) -> str:
        """`as_shortcut` asks for the key's name rather than the text it types,
        because `Ctrl+C` reads better than `Ctrl+c` and a shortcut is about the
        key, not about the character it would have inserted."""
        named = NAMED_KEYS.get(code)
        if named:
            return named

        if self.state is not None:
            try:
                sym = self.state.key_get_one_sym(code + 8)
                name = xkb.keysym_get_name(sym)
            except Exception:
                name = ""
            if name in SYM_RENAMES:
                return SYM_RENAMES[name]
            if name and name != "NoSymbol":
                if as_shortcut and len(name) == 1:
                    return name.upper()
                text = self.state.key_get_string(code + 8)
                if text and text.isprintable() and not as_shortcut:
                    return text
                if len(name) == 1:
                    return name
                return name.replace("_", " ")

        # No xkb: evdev's own name is a US-layout guess, which is still better
        # than showing nothing at all.
        raw = ecodes.KEY.get(code)
        if isinstance(raw, list):
            raw = raw[0]
        if not raw:
            return f"#{code}"
        pretty = raw.replace("KEY_", "").replace("_", " ").title()
        return pretty.upper() if len(pretty) == 1 else pretty


def note(message: str) -> None:
    print(json.dumps({"type": "note", "message": message}), flush=True)


def emit(payload: dict) -> None:
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def is_keyboard(device: evdev.InputDevice) -> bool:
    keys = device.capabilities().get(ecodes.EV_KEY, [])
    return ecodes.KEY_A in keys and ecodes.KEY_SPACE in keys


def is_pointer(device: evdev.InputDevice) -> bool:
    keys = device.capabilities().get(ecodes.EV_KEY, [])
    return ecodes.BTN_LEFT in keys and ecodes.KEY_A not in keys


def scan_devices(want_mouse: bool, existing: dict) -> dict:
    """Open every device we care about, keeping the ones already open.

    A device grabbed by a remapper such as keyd delivers nothing here, which is
    exactly right: its virtual keyboard carries the remapped keys instead, so
    the overlay reports what the user's keymap actually produces.
    """
    found = {}
    for path in evdev.list_devices():
        if path in existing:
            found[path] = existing[path]
            continue
        try:
            device = evdev.InputDevice(path)
        except (PermissionError, OSError):
            continue
        if is_keyboard(device) or (want_mouse and is_pointer(device)):
            found[path] = device
        else:
            device.close()

    for path, device in existing.items():
        if path not in found:
            try:
                device.close()
            except OSError:
                pass
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layout", default="us", help="xkb layout code, e.g. fr")
    parser.add_argument("--variant", default="", help="xkb variant, e.g. azerty")
    parser.add_argument("--options", default="", help="xkb options string")
    parser.add_argument("--mouse", action="store_true", help="also report mouse buttons")
    parser.add_argument("--repeats", action="store_true", help="report auto-repeat as its own event")
    args = parser.parse_args()

    if not os.access("/dev/input", os.R_OK):
        emit({"type": "error", "message": "no read access to /dev/input (add your user to the 'input' group)"})
        return 1

    translator = Translator(args.layout, args.variant, args.options)
    if not translator.layout_aware:
        note("python-xkbcommon missing: key labels assume a US layout")

    devices = scan_devices(args.mouse, {})
    if not devices:
        emit({"type": "error", "message": "no readable keyboard found under /dev/input"})
        return 1
    emit({"type": "ready", "devices": len(devices), "layout": args.layout, "layoutAware": translator.layout_aware})

    last_scan = time.monotonic()
    recent: dict[int, float] = {}

    while True:
        try:
            readable, _, _ = select.select(list(devices.values()), [], [], RESCAN_INTERVAL)
        except (OSError, ValueError):
            # A device vanished between select() calls; rebuild and carry on.
            devices = scan_devices(args.mouse, {})
            continue

        now = time.monotonic()
        if now - last_scan >= RESCAN_INTERVAL:
            devices = scan_devices(args.mouse, devices)
            last_scan = now

        for device in readable:
            try:
                events = list(device.read())
            except (OSError, BlockingIOError):
                continue

            for event in events:
                if event.type != ecodes.EV_KEY:
                    continue
                # value: 0 released, 1 pressed, 2 auto-repeat
                # xkb refcounts key-downs, so an auto-repeat (value 2) fed to it
                # as another press would outlive the single release and leave
                # the modifier stuck: only the real edges reach it.
                if event.value != 2 and event.code not in MOUSE_BUTTONS:
                    translator.update(event.code, event.value == 1)
                if event.value == 0:
                    if event.code in MODIFIER_KEYS:
                        emit({"type": "release", "label": MODIFIER_KEYS[event.code]})
                    continue
                if event.value == 2 and (not args.repeats or event.code in MODIFIER_KEYS):
                    # A held modifier is already shown as held; its auto-repeat
                    # carries no information the release will not.
                    continue

                stamp = time.monotonic()
                if stamp - recent.get(event.code, 0.0) < DEDUP_WINDOW:
                    continue
                recent[event.code] = stamp

                if event.code in MOUSE_BUTTONS:
                    emit({
                        "type": "key",
                        "kind": "mouse",
                        "label": MOUSE_BUTTONS[event.code],
                        "modifiers": translator.active_modifiers(),
                        "repeat": event.value == 2,
                    })
                    continue

                if event.code in MODIFIER_KEYS:
                    emit({
                        "type": "key",
                        "kind": "modifier",
                        "label": MODIFIER_KEYS[event.code],
                        "modifiers": [],
                        "repeat": event.value == 2,
                    })
                    continue

                # Shift alone is not what makes a shortcut — `Shift+a` is just
                # `A` — so only the other three promote a key to a combo.
                mods = translator.active_modifiers()
                is_shortcut = any(mod in ("Ctrl", "Alt", "Super") for mod in mods)
                label = translator.label(event.code, is_shortcut)
                # Typed text is a single character that landed in a document;
                # an arrow is one character too, but it is a key.
                is_text = event.code not in NAMED_KEYS and len(label) == 1
                emit({
                    "type": "key",
                    "kind": "shortcut" if is_shortcut else ("text" if is_text else "key"),
                    "label": label,
                    "modifiers": [mod for mod in mods if mod != "Shift" or is_shortcut],
                    "repeat": event.value == 2,
                })


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
    except BrokenPipeError:
        # The overlay went away; nothing left to report to.
        sys.exit(0)
