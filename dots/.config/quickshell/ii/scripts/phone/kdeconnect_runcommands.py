#!/usr/bin/env python3
"""Offer the shell's own actions to a phone through KDE Connect's Run Command plugin.

The plugin keeps its commands in the device's KConfig file, as one JSON object under
[General] commands, and sends that list to the phone whenever the file is announced as
changed. There is no D-Bus method to add a command, so this edits the file and then
emits the same `configChanged` signal the plugin's own settings page emits.

Only entries whose key starts with `ii-` belong to the shell. Anything else in there is
the user's and is kept untouched, in both directions.

    kdeconnect_runcommands.py <device-id> enable|disable
"""
import json
import os
import subprocess
import sys
from pathlib import Path

PREFIX = "ii-"
IPC = "qs -c ii ipc call"

COMMANDS = {
    "ii-mirror": ("Mirror the phone on the PC", f"{IPC} phone mirrorWindow"),
    "ii-stop-mirror": ("Stop mirroring", f"{IPC} phone stopMirroring"),
    "ii-record": ("Record the phone screen (start/stop)", f"{IPC} phone toggleRecording"),
    "ii-play-pause": ("PC: play/pause media", f"{IPC} mpris playPause"),
    "ii-next": ("PC: next track", f"{IPC} mpris next"),
    "ii-mute": ("PC: mute/unmute sound", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
    "ii-lock": ("PC: lock the screen", f"{IPC} lock activate"),
    "ii-suspend": ("PC: suspend", "systemctl suspend"),
}


def config_path(device_id):
    base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return base / "kdeconnect" / device_id / "kdeconnect_runcommand" / "config"


def read_lines(path):
    try:
        return path.read_text().splitlines()
    except FileNotFoundError:
        return []


def current_commands(lines):
    group = None
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            group = stripped[1:-1]
        elif group == "General" and stripped.startswith("commands="):
            raw = stripped[len("commands="):]
            # QSettings-style spelling, in case a file was ever written that way.
            if raw.startswith("@ByteArray(") and raw.endswith(")"):
                raw = raw[len("@ByteArray("):-1]
            try:
                value = json.loads(raw)
                return value if isinstance(value, dict) else {}
            except ValueError:
                return {}
    return {}


def write_commands(lines, commands):
    # KConfig reads the value raw; compact JSON has no characters it escapes.
    entry = "commands=" + json.dumps(commands, separators=(",", ":"), ensure_ascii=False)
    out, group, written = [], None, False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if group == "General" and not written:
                out.append(entry)
                written = True
            group = stripped[1:-1]
        elif group == "General" and stripped.startswith("commands="):
            if not written:
                out.append(entry)
                written = True
            continue
        out.append(line)
    if not written:
        if group != "General":
            if out and out[-1].strip():
                out.append("")
            out.append("[General]")
        out.append(entry)
    return "\n".join(out) + "\n"


def announce(device_id):
    subprocess.run(
        ["gdbus", "emit", "--session",
         "--object-path", f"/kdeconnect/{device_id}/kdeconnect_runcommand",
         "--signal", "org.kde.kdeconnect.config.configChanged"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)


def main():
    if len(sys.argv) != 3 or sys.argv[2] not in ("enable", "disable") or "/" in sys.argv[1]:
        sys.stderr.write(__doc__)
        return 2
    device_id, mode = sys.argv[1], sys.argv[2]
    path = config_path(device_id)
    lines = read_lines(path)
    commands = {k: v for k, v in current_commands(lines).items() if not k.startswith(PREFIX)}
    if mode == "enable":
        for key, (name, command) in COMMANDS.items():
            commands[key] = {"name": name, "command": command}

    path.parent.mkdir(parents=True, exist_ok=True)
    text = write_commands(lines, commands)
    if text != ("\n".join(lines) + "\n" if lines else ""):
        tmp = path.with_suffix(".ii-tmp")
        tmp.write_text(text)
        tmp.replace(path)
    announce(device_id)
    print(json.dumps({"ok": True, "count": len([k for k in commands if k.startswith(PREFIX)])}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
