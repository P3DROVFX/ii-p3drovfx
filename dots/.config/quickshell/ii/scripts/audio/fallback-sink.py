#!/usr/bin/env python3
"""Pick the output that takes over when the default Bluetooth sink goes away.

WirePlumber falls back to the highest priority.session, and a USB microphone's
headphone-jack sink (fifine: 1109) outranks the laptop speaker (1000), so a
disconnected headset left the sound going into a microphone. The order here:

1. another Bluetooth sink;
2. a sink with a real output: not on a microphone/webcam device, not a virtual
   sink, and whose port is not reported unplugged (an HDMI port with no screen);
   highest priority.session first.

Usage: fallback-sink.py <departed sink name>
Prints the chosen sink name. Exit 3 = the departed sink's Bluetooth card is
still there (a profile switch, or the disconnect has not landed yet): ask again.
Exit 1 = nothing suitable; leave WirePlumber's choice alone.
"""

import json
import os
import subprocess
import sys

NOT_REAL_FORM_FACTORS = {"microphone", "webcam"}
HARDWARE_APIS = {"alsa", "bluez5"}


def pactl_json(kind):
    out = subprocess.check_output(
        ["pactl", "-f", "json", "list", kind], text=True, timeout=3,
        env={**os.environ, "LC_ALL": "C"})
    return json.loads(out or "[]")


def bluetooth_address(sink_name):
    # bluez_output.40_35_E6_31_8B_AC.1 -> 40_35_E6_31_8B_AC
    parts = sink_name.split(".")
    return parts[1] if len(parts) >= 2 and parts[0] == "bluez_output" else ""


def priority(sink):
    try:
        return int(sink.get("properties", {}).get("priority.session", 0))
    except (TypeError, ValueError):
        return 0


def is_bluetooth(sink):
    return sink.get("name", "").startswith("bluez_output.")


def has_real_output(sink):
    props = sink.get("properties", {})
    if props.get("device.api") not in HARDWARE_APIS:
        return False  # EasyEffects, the multi-output sink, null sinks
    if props.get("device.form_factor", props.get("device.form-factor")) in NOT_REAL_FORM_FACTORS:
        return False
    ports = sink.get("ports") or []
    if ports:
        active = next((p for p in ports if p.get("name") == sink.get("active_port")), None)
        if active is not None and active.get("availability") == "not available":
            return False
        if all(p.get("availability") == "not available" for p in ports):
            return False
    return True


def choose(sinks, cards, departed):
    """Return (sink name or None, still_connected)."""
    address = bluetooth_address(departed)
    candidates = [s for s in sinks if s.get("name") != departed]
    if address and any(c.get("name") == f"bluez_card.{address}" for c in cards):
        same_device = [s for s in candidates if bluetooth_address(s.get("name", "")) == address]
        if same_device:
            return max(same_device, key=priority)["name"], True
        return None, True
    bluetooth = [s for s in candidates if is_bluetooth(s)]
    if bluetooth:
        return max(bluetooth, key=priority)["name"], False
    real = [s for s in candidates if has_real_output(s)]
    if real:
        return max(real, key=priority)["name"], False
    return None, False


def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        sinks, cards = pactl_json("sinks"), pactl_json("cards")
    except (OSError, subprocess.SubprocessError, ValueError) as err:
        print(f"pactl failed: {err}", file=sys.stderr)
        return 1
    name, still_connected = choose(sinks, cards, sys.argv[1])
    if name:
        print(name)
        return 0
    return 3 if still_connected else 1


if __name__ == "__main__":
    sys.exit(main())
