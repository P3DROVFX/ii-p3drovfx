#!/usr/bin/env python3
"""Scrolling from graphics tablet buttons (services/TabletButtons.qml).

Reads OpenTabletDriver's own virtual keyboard, so only presses that came from the
tablet count; a user typing Ctrl+Alt+Shift+Q on the real keyboard is never seen.

  * fixed keys: a wheel step on press, repeated while held;
  * drag keys: while held, the OTD virtual tablet is grabbed (the cursor stays
    put) and the pen's travel becomes smooth scrolling, like dragging a page.

The wheel comes from a uinput device of our own ("ii tablet scroll"), so the
OpenTabletDriver scroll plugin is not needed.

Configuration arrives as one JSON line on stdin, and may be resent at any time:
  {"fixed": {"16": [0, 1]}, "drag": [24], "step": 1, "speed": 1.0, "invert": false}
fixed maps an evdev key code to [dx, dy] notches (dy > 0 scrolls up).
"""

import ctypes
import json
import os
import select
import signal
import sys
import time

try:
    import evdev
    from evdev import ecodes as e
except ImportError:
    print("python-evdev is not installed", file=sys.stderr)
    sys.exit(3)

KEYBOARD_NAME = "OpenTabletDriver Virtual Keyboard"
TABLET_NAMES = ("OpenTabletDriver Virtual Artist Tablet", "OpenTabletDriver Virtual Tablet")
REPEAT_DELAY = 0.30
REPEAT_INTERVAL = 0.06
RESCAN_INTERVAL = 3.0
HI_RES = 120
PX_PER_NOTCH = 40.0

config = {"fixed": {}, "drag": [], "step": 1, "speed": 1.0, "invert": False}


def die_with_parent():
    try:
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        libc.prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    except OSError:
        pass
    if os.getppid() == 1:
        sys.exit(0)


def find(names):
    for path in evdev.list_devices():
        try:
            device = evdev.InputDevice(path)
        except OSError:
            continue
        if device.name in names:
            return device
        device.close()
    return None


class Wheel:
    def __init__(self):
        caps = {e.EV_REL: [e.REL_WHEEL, e.REL_HWHEEL, e.REL_WHEEL_HI_RES, e.REL_HWHEEL_HI_RES]}
        self.ui = evdev.UInput(caps, name="ii tablet scroll")
        self.rest = [0.0, 0.0]  # hi-res units not yet sent as a whole notch

    def hires(self, dx, dy):
        """Send dx/dy in hi-res units (120 = one notch)."""
        dx, dy = int(round(dx)), int(round(dy))
        if dx == 0 and dy == 0:
            return
        if dy:
            self.ui.write(e.EV_REL, e.REL_WHEEL_HI_RES, dy)
        if dx:
            self.ui.write(e.EV_REL, e.REL_HWHEEL_HI_RES, dx)
        for axis, delta, code in ((0, dx, e.REL_HWHEEL), (1, dy, e.REL_WHEEL)):
            self.rest[axis] += delta
            notches = int(self.rest[axis] / HI_RES)
            if notches:
                self.rest[axis] -= notches * HI_RES
                self.ui.write(e.EV_REL, code, notches)
        self.ui.syn()


class Drag:
    """The pen's travel while a drag key is held."""

    def __init__(self):
        self.device = None
        self.last = [None, None]
        self.scale = [1.0, 1.0]

    def start(self):
        if self.device:
            return
        device = find(TABLET_NAMES)
        if not device:
            return
        try:
            device.grab()
        except OSError:
            device.close()
            return
        self.device = device
        self.last = [None, None]
        # OTD reports in display space: the range is the layout in px * 1000.
        for axis, code in ((0, e.ABS_X), (1, e.ABS_Y)):
            info = device.absinfo(code)
            span = max(1, info.max - info.min)
            self.scale[axis] = 1.0 / 1000.0 if span > 100000 else 1080.0 / span

    def stop(self):
        if not self.device:
            return
        try:
            self.device.ungrab()
        except OSError:
            pass
        self.device.close()
        self.device = None

    def read(self, wheel):
        moved = [0.0, 0.0]
        try:
            events = list(self.device.read())
        except (BlockingIOError, OSError):
            events = []
        for event in events:
            if event.type != e.EV_ABS or event.code not in (e.ABS_X, e.ABS_Y):
                continue
            axis = 0 if event.code == e.ABS_X else 1
            if self.last[axis] is not None:
                moved[axis] += (event.value - self.last[axis]) * self.scale[axis]
            self.last[axis] = event.value
        if moved == [0.0, 0.0]:
            return
        # Content follows the pen: moving it up scrolls the page up, i.e. the wheel down.
        sign = -1.0 if config.get("invert") else 1.0
        factor = HI_RES / PX_PER_NOTCH * float(config.get("speed") or 1.0) * sign
        wheel.hires(moved[0] * -factor, moved[1] * factor)


def main():
    die_with_parent()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    wheel = Wheel()
    drag = Drag()
    keyboard = None
    held = {}  # fixed key code -> next repeat time
    drag_keys_down = set()
    next_scan = 0.0
    stdin_buffer = ""

    def apply_config(line):
        global config
        try:
            config = {**config, **json.loads(line)}
        except ValueError:
            print(f"bad config: {line!r}", file=sys.stderr)

    def step(code):
        dx, dy = config["fixed"].get(str(code), (0, 0))
        n = max(1, int(config.get("step") or 1))
        wheel.hires(dx * n * HI_RES, dy * n * HI_RES)

    try:
        while True:
            now = time.monotonic()
            if keyboard is None and now >= next_scan:
                keyboard = find((KEYBOARD_NAME,))
                next_scan = now + RESCAN_INTERVAL

            fds = [sys.stdin]
            if keyboard:
                fds.append(keyboard)
            if drag.device:
                fds.append(drag.device)
            timeout = RESCAN_INTERVAL if keyboard is None else None
            if held:
                timeout = max(0.0, min(held.values()) - now)
            ready, _, _ = select.select(fds, [], [], timeout)

            if sys.stdin in ready:
                chunk = os.read(sys.stdin.fileno(), 4096).decode(errors="replace")
                if not chunk:
                    return
                stdin_buffer += chunk
                while "\n" in stdin_buffer:
                    line, stdin_buffer = stdin_buffer.split("\n", 1)
                    if line.strip():
                        apply_config(line)

            if keyboard and keyboard in ready:
                try:
                    events = list(keyboard.read())
                except OSError:
                    # The driver restarted and its device went with it.
                    keyboard.close()
                    keyboard = None
                    held.clear()
                    drag_keys_down.clear()
                    drag.stop()
                    events = []
                for event in events:
                    if event.type != e.EV_KEY or event.value == 2:
                        continue
                    code = event.code
                    if str(code) in config["fixed"]:
                        if event.value == 1:
                            step(code)
                            held[code] = time.monotonic() + REPEAT_DELAY
                        else:
                            held.pop(code, None)
                    elif code in config["drag"]:
                        if event.value == 1:
                            drag_keys_down.add(code)
                            drag.start()
                        else:
                            drag_keys_down.discard(code)
                            if not drag_keys_down:
                                drag.stop()

            if drag.device and drag.device in ready:
                drag.read(wheel)

            now = time.monotonic()
            for code, due in list(held.items()):
                if now >= due:
                    step(code)
                    held[code] = now + REPEAT_INTERVAL
    finally:
        drag.stop()


if __name__ == "__main__":
    main()
