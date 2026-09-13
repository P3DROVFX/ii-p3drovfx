#!/usr/bin/env python3
"""Shows what a pen's buttons actually send, if anything.

Pen mode binds the stylus's barrel buttons by reading `BTN_STYLUS` / `BTN_STYLUS2` from
the tablet device — see scripts/osk/README.md for why that needs no driver integration.
When a button does nothing, the question is always the same and always hard to answer
from inside the shell: did the press reach Linux at all?

This answers it. Run it, press the buttons, and read the summary. Every input device is
watched, not only the tablet, because a driver that maps a barrel button to a mouse click
or a keystroke sends it from somewhere else entirely — and knowing *that* is the
difference between "the driver is not sending it" and "the driver is sending the wrong
thing".

Usage:  pen-buttons.py [seconds]
"""

import glob
import os
import select
import struct
import sys
import time

EVENT_SIZE = 24  # struct input_event on 64-bit: 2x __s64 time, 2x __u16, __s32
EV_KEY = 0x01

# The codes worth naming. Anything else is printed as hex, which is enough to look up.
BUTTONS = {
    0x110: "BTN_LEFT", 0x111: "BTN_RIGHT", 0x112: "BTN_MIDDLE",
    0x113: "BTN_SIDE", 0x114: "BTN_EXTRA", 0x115: "BTN_FORWARD", 0x116: "BTN_BACK",
    0x140: "BTN_TOOL_PEN", 0x141: "BTN_TOOL_RUBBER", 0x14a: "BTN_TOUCH",
    0x14b: "BTN_STYLUS  <- pen mode binds this", 0x14c: "BTN_STYLUS2 <- pen mode binds this",
}

# What pen mode actually listens for.
PEN_BUTTONS = (0x14b, 0x14c)


def device_name(node):
    leaf = node.rsplit("/", 1)[-1]
    try:
        with open("/sys/class/input/%s/device/name" % leaf) as handle:
            return handle.read().strip()
    except OSError:
        return leaf


def main():
    seconds = float(sys.argv[1]) if len(sys.argv) > 1 else 20.0

    handles = {}
    unreadable = 0
    for node in sorted(glob.glob("/dev/input/event*")):
        try:
            handles[os.open(node, os.O_RDONLY | os.O_NONBLOCK)] = device_name(node)
        except OSError:
            unreadable += 1

    if not handles:
        print("Could not open any input device. Add your user to the `input` group:")
        print("  sudo usermod -aG input $USER      (then log back in)")
        return 1

    print("Watching %d input devices for %.0f seconds." % (len(handles), seconds))
    if unreadable:
        print("  (%d could not be opened — check the `input` group if the tablet is missing)"
              % unreadable)
    print()
    print("  Press the pen's barrel buttons now. Touch the tip too, so the output shows")
    print("  the pen is being seen at all.")
    print()

    tip = 0
    barrel = 0
    others = {}
    deadline = time.time() + seconds

    while time.time() < deadline:
        ready, _, _ = select.select(list(handles), [], [], 0.2)
        for handle in ready:
            try:
                data = os.read(handle, EVENT_SIZE * 64)
            except OSError:
                continue
            for offset in range(0, len(data) // EVENT_SIZE * EVENT_SIZE, EVENT_SIZE):
                _, _, etype, code, value = struct.unpack(
                    "qqHHi", data[offset:offset + EVENT_SIZE])
                if etype != EV_KEY or value not in (0, 1):
                    continue
                name = handles[handle]
                label = BUTTONS.get(code, hex(code))
                if code in PEN_BUTTONS:
                    barrel += 1
                    print("  %-38s %s = %d" % (name[:38], label, value))
                elif code == 0x14a:
                    tip += 1
                    print("  %-38s %s = %d" % (name[:38], label, value))
                else:
                    others[(name, label)] = others.get((name, label), 0) + 1

    print()
    print("─" * 72)
    if barrel:
        print("Barrel buttons: %d events. The shell can see them — if pen mode still does" % barrel)
        print("nothing, the problem is in the shell, not the driver.")
    elif tip:
        print("The pen is being seen (%d tip events) but NOT ONE barrel button arrived." % tip)
        print("Nothing in Linux is receiving those presses, so the shell cannot either.")
        print("Look at the driver's own button bindings — with OpenTabletDriver, the pen")
        print("buttons must be bound to something that reaches the virtual tablet.")
    else:
        print("Nothing from the pen at all — no tip, no buttons.")
        print("Either the pen was not used during the window, or the tablet is not")
        print("reporting. Check that the driver is running and the tablet is detected.")

    if others:
        print()
        print("Other buttons seen meanwhile (a driver may be mapping the pen to one of these):")
        for (name, label), count in sorted(others.items(), key=lambda item: -item[1])[:8]:
            print("  %-38s %-12s x%d" % (name[:38], label, count))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
