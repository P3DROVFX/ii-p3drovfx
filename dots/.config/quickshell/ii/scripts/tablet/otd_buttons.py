#!/usr/bin/env python3
"""Route OpenTabletDriver tablet buttons to the shell.

OTD has no "run a command" binding, so a button handed to the shell becomes a
Multi-Key Binding that presses a combination nothing else uses
(Ctrl+Alt+Shift+<letter>). Hyprland
binds those keys by code and turns each press into an `iitablet,<kind>,<slot>`
event the shell reads (services/TabletButtons.qml).

    otd_buttons.py status
    otd_buttons.py apply --aux shell,keep,shell,keep --pen keep,keep

The binding a slot had before the shell took it is kept in a backup file, so
"keep" puts the user's own binding back. The settings file is written (the OTD
console only changes the running daemon, never the file) and then loaded into
the daemon when it runs.
"""

import argparse
import copy
import json
import os
import shutil
import subprocess
import sys

CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
STATE_HOME = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
SETTINGS = os.path.join(CONFIG_HOME, "OpenTabletDriver", "settings.json")
BACKUP = os.path.join(STATE_HOME, "quickshell", "user", "otd_buttons_backup.json")

MULTIKEY = "OpenTabletDriver.Desktop.Binding.MultiKeyBinding"
# What a slot handed to the shell presses. It has to be a key OTD's virtual
# keyboard registered with uinput: that device only declares the basic keys
# (letters, digits, F1-F12, keypad...), and the kernel silently drops any other
# code — F13-F24 are accepted by OTD's parser and never reach the compositor.
# Ctrl+Alt+Shift+<letter> is free in this config; Ctrl+Alt+F<n> would switch VT.
# Keep in sync with TabletButtons.qml.
MODS = "Control+Alt+Shift+"
KEYS = {
    "aux": ["Q", "W", "E", "R", "T", "Y", "U", "I"],
    "pen": ["O", "P"],
}
SETTING_LISTS = {"aux": "AuxButtons", "pen": "PenButtons"}
OUR_KEYS = {MODS + k for keys in KEYS.values() for k in keys}
# Bindings an earlier version wrote; still recognised so they are replaced or restored.
OUR_KEYS |= {f"F{n}" for n in range(13, 25)}


def binding_keys(binding):
    if not isinstance(binding, dict) or binding.get("Path") != MULTIKEY:
        return None
    for entry in binding.get("Settings") or []:
        if entry.get("Property") == "Keys":
            return str(entry.get("Value") or "")
    return ""


def is_ours(binding):
    return binding_keys(binding) in OUR_KEYS


def describe(binding):
    if not isinstance(binding, dict) or not binding.get("Enable", True):
        return ""
    name = binding.get("Path", "").rsplit(".", 1)[-1]
    values = [str(s.get("Value")) for s in binding.get("Settings") or [] if s.get("Value") not in (None, "")]
    return f"{name}: {', '.join(values)}" if values else name


def our_binding(key):
    return {"Path": MULTIKEY, "Settings": [{"Property": "Keys", "Value": MODS + key}], "Enable": True}


def load_json(path, fallback):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        return fallback


def write_json(path, data, indent):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".ii-tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=indent)
    os.replace(tmp, path)


def daemon_running():
    return subprocess.run(["pgrep", "-f", "OpenTabletDriver.Daemon"], capture_output=True).returncode == 0


def status():
    settings = load_json(SETTINGS, None)
    result = {
        "installed": shutil.which("otd") is not None,
        "daemon": daemon_running(),
        "settings": SETTINGS,
        "hasSettings": settings is not None,
        "tablets": [],
    }
    for profile in (settings or {}).get("Profiles") or []:
        bindings = profile.get("Bindings") or {}
        tablet = {"name": profile.get("Tablet", "")}
        for kind, field in SETTING_LISTS.items():
            slots = (bindings.get(field) or [])[: len(KEYS[kind])]
            tablet[kind] = [{"current": describe(b), "shell": is_ours(b), "key": MODS + KEYS[kind][i]}
                            for i, b in enumerate(slots)]
        result["tablets"].append(tablet)
    print(json.dumps(result))
    return 0


def apply(args):
    settings = load_json(SETTINGS, None)
    if settings is None:
        print(f"no OpenTabletDriver settings at {SETTINGS}; open OpenTabletDriver once", file=sys.stderr)
        return 2
    backup = load_json(BACKUP, {})
    wanted = {"aux": [s.strip() for s in args.aux.split(",")] if args.aux else [],
              "pen": [s.strip() for s in args.pen.split(",")] if args.pen else []}
    changed = False

    for profile in settings.get("Profiles") or []:
        name = profile.get("Tablet", "")
        bindings = profile.setdefault("Bindings", {})
        saved = backup.setdefault(name, {})
        for kind, field in SETTING_LISTS.items():
            slots = bindings.get(field) or []
            kept = saved.setdefault(kind, {})
            for index in range(min(len(slots), len(KEYS[kind]))):
                want = wanted[kind][index] if index < len(wanted[kind]) else "keep"
                current = slots[index]
                if want == "shell":
                    target = our_binding(KEYS[kind][index])
                    if not is_ours(current):
                        kept[str(index)] = copy.deepcopy(current)
                elif is_ours(current):
                    # Hand the slot back. A slot the shell took before any backup
                    # existed has nothing to restore and goes empty.
                    target = kept.pop(str(index), None)
                else:
                    continue
                if target != current:
                    slots[index] = target
                    changed = True
            bindings[field] = slots

    write_json(BACKUP, backup, 2)
    if changed:
        write_json(SETTINGS, settings, 2)
    if daemon_running():
        loaded = subprocess.run(["otd", "loadsettings", SETTINGS], capture_output=True, text=True, timeout=20)
        if loaded.returncode != 0:
            print((loaded.stderr or loaded.stdout).strip()[-400:], file=sys.stderr)
            return 3
    print("changed" if changed else "unchanged")
    return 0


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    apply_parser = sub.add_parser("apply")
    apply_parser.add_argument("--aux", default="")
    apply_parser.add_argument("--pen", default="")
    args = parser.parse_args()
    return status() if args.command == "status" else apply(args)


if __name__ == "__main__":
    sys.exit(main())
