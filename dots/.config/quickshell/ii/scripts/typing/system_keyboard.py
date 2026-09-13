#!/usr/bin/env python3
"""Read Hyprland's active XKB layout into a portable visual keyboard map.

No keyboard/configuration writes, event capture or polling. libxkbcommon is
loaded through ctypes (already part of the desktop; no Python package needed).
XKB describes symbols, not a laptop's chassis: use standard compact ANSI/ISO/
ABNT2 geometry, including the extra Brazilian slash key, without a numpad.
"""
import argparse
import ctypes as c
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone


class RuleNames(c.Structure):
    _fields_ = [(name, c.c_char_p) for name in ("rules", "model", "layout", "variant", "options")]


class XkbMap:
    def __init__(self, layout, variant="", model="", options="", rules=""):
        self.lib = c.CDLL("libxkbcommon.so.0")
        signatures = {
            "context_new": (c.c_void_p, [c.c_int]),
            "context_unref": (None, [c.c_void_p]),
            "keymap_new_from_names": (c.c_void_p, [c.c_void_p, c.POINTER(RuleNames), c.c_int]),
            "keymap_unref": (None, [c.c_void_p]),
            "keymap_num_layouts": (c.c_uint32, [c.c_void_p]),
            "keymap_layout_get_name": (c.c_char_p, [c.c_void_p, c.c_uint32]),
            "keymap_key_by_name": (c.c_uint32, [c.c_void_p, c.c_char_p]),
            "state_new": (c.c_void_p, [c.c_void_p]),
            "state_unref": (None, [c.c_void_p]),
            "state_update_mask": (c.c_uint32, [c.c_void_p] + [c.c_uint32] * 6),
            "state_update_key": (c.c_uint32, [c.c_void_p, c.c_uint32, c.c_int]),
            "state_key_get_one_sym": (c.c_uint32, [c.c_void_p, c.c_uint32]),
            "keysym_get_name": (c.c_int, [c.c_uint32, c.c_char_p, c.c_size_t]),
            "keysym_to_utf8": (c.c_int, [c.c_uint32, c.c_char_p, c.c_size_t]),
        }
        for name, (result, args) in signatures.items():
            fn = getattr(self.lib, "xkb_" + name)
            fn.restype, fn.argtypes = result, args
            setattr(self, name, fn)
        self.context = self.context_new(0)
        if not self.context:
            raise ValueError("Could not initialize XKB")
        names = RuleNames(*(v.encode() for v in (rules or "evdev", model or "pc105", layout, variant, options)))
        self.keymap = self.keymap_new_from_names(self.context, c.byref(names), 0)
        if not self.keymap:
            self.context_unref(self.context)
            raise ValueError("Could not compile the configured XKB layout")

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.keymap_unref(self.keymap)
        self.context_unref(self.context)

    def names(self):
        return [(self.keymap_layout_get_name(self.keymap, i) or b"").decode()
                for i in range(self.keymap_num_layouts(self.keymap))]

    def keycode(self, name):
        return self.keymap_key_by_name(self.keymap, name.encode())

    def layer(self, keys, group, shift=False, altgr=False):
        state = self.state_new(self.keymap)
        if not state:
            raise ValueError("Could not read XKB symbols")
        try:
            self.state_update_mask(state, 0, 0, 0, 0, 0, group)
            # Press these only inside the local XKB state, never on a device.
            for name, pressed in (("LFSH", shift), ("RALT", altgr)):
                if pressed:
                    self.state_update_key(state, self.keycode(name), 1)
            entries = []
            for key in keys:
                code = self.keycode(key["name"])
                sym = self.state_key_get_one_sym(state, code)
                name = c.create_string_buffer(128)
                value = c.create_string_buffer(128)
                self.keysym_get_name(sym, name, len(name))
                self.keysym_to_utf8(sym, value, len(value))
                symbol_name, character = name.value.decode(), value.value.decode()
                printable = character if character.isprintable() else ""
                label = SYMBOL_LABELS.get(symbol_name, printable or symbol_name)
                entries.append({"label": label, "char": printable, "code": code,
                                "resolvedCode": sym, "description": symbol_name})
            return entries
        finally:
            self.state_unref(state)


SYMBOL_LABELS = {
    "NoSymbol": "", "Escape": "Esc", "BackSpace": "Bksp", "Return": "Enter",
    "Tab": "Tab", "ISO_Left_Tab": "Tab", "Caps_Lock": "Caps",
    "Shift_L": "Shift", "Shift_R": "Shift", "Control_L": "Ctrl", "Control_R": "Ctrl",
    "Super_L": "Super", "Super_R": "Super", "Alt_L": "Alt", "Alt_R": "Alt",
    "ISO_Level3_Shift": "AltGr", "ISO_Level5_Shift": "AltGr", "space": "Space",
    "Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "Delete": "Del",
    "Insert": "Ins", "Prior": "PgUp", "Next": "PgDn", "Print": "PrtSc",
    "Scroll_Lock": "Scroll", "Pause": "Pause", "Menu": "Menu",
    "dead_acute": "´", "dead_grave": "`", "dead_tilde": "~", "dead_circumflex": "^",
    "dead_diaeresis": "¨", "dead_cedilla": "¸", "dead_ogonek": "˛",
    "dead_macron": "¯", "dead_caron": "ˇ", "dead_breve": "˘",
    "dead_abovedot": "˙", "dead_belowdot": "◌̣", "dead_doubleacute": "˝",
    "dead_abovering": "˚", "dead_belowcomma": "◌̦",
}


def geometry(layout, model=""):
    """Standard alphanumeric block plus navigation cluster (not device probing)."""
    abnt = layout == "br" or model == "abnt2"
    iso = abnt or model in ("pc102", "pc105") or layout in ("de", "fr", "gb", "pt", "es", "it")
    keys = []

    def row(y, names, x=0):
        for item in names:
            name, width = (item, 1) if isinstance(item, str) else item
            keys.append({"name": name, "row": y, "col": sum(k["row"] == y for k in keys),
                         "x": x, "y": y, "w": width, "h": 1, "r": 0, "rx": 0, "ry": 0})
            x += width

    row(0, ["ESC", ("FK01", 1.15), "FK02", "FK03", "FK04", ("FK05", 1.15), "FK06", "FK07", "FK08", ("FK09", 1.15), "FK10", "FK11", "FK12"])
    row(1, ["TLDE"] + [f"AE{i:02}" for i in range(1, 13)] + [("BKSP", 2)])
    row(2, [("TAB", 1.5)] + [f"AD{i:02}" for i in range(1, 13)] + ([] if iso else [("BKSL", 1.5)]))
    row(3, [("CAPS", 1.75)] + [f"AC{i:02}" for i in range(1, 12)] + (["BKSL", ("RTRN", 1.25)] if iso else [("RTRN", 2.25)]))
    if iso:
        # Rectangular lower stem of the ISO Enter; spans the two physical rows.
        keys[-1].update(y=2, h=2)
    row(4, [("LFSH", 1.25), "LSGT"] if iso else [("LFSH", 2.25)])
    row(4, [f"AB{i:02}" for i in range(1, 11)] + (["AB11", ("RTSH", 1.75)] if abnt else [("RTSH", 2.75)]), x=2.25)
    row(5, [("LCTL", 1.25), ("LWIN", 1.25), ("LALT", 1.25), ("SPCE", 6.25), ("RALT", 1.25), ("RWIN", 1.25), ("MENU", 1.25), ("RCTL", 1.25)])
    for y, names in ((0, ["PRSC", "SCLK", "PAUS"]), (1, ["INS", "HOME", "PGUP"]),
                     (2, ["DELE", "END", "PGDN"]), (4, ["UP"]), (5, ["LEFT", "DOWN", "RGHT"])):
        row(y, names, x=16.5 if y == 4 else 15.5)
    return keys, "abnt2" if abnt else "iso" if iso else "ansi"


def active_group(device, names):
    active = str(device.get("active_keymap", "")).strip()
    index = device.get("active_layout_index")
    if isinstance(index, int) and 0 <= index < len(names) and (not active or names[index] == active):
        return index
    if active in names:
        return names.index(active)
    if not active and len(names) == 1:
        return 0
    # A custom kb_file (e.g. Corne) can report the global layout/variant even
    # though it uses completely different symbols. Never label that as US.
    raise ValueError("The device uses a custom or unrecognized XKB map; use Detect Vial for firmware keyboards")


def read_device(device, manual=False):
    layouts = str(device.get("layout", ""))
    if not layouts.strip():
        raise ValueError("No XKB layout was reported")
    variants, model = str(device.get("variant", "")), str(device.get("model", ""))
    options, rules = str(device.get("options", "")), str(device.get("rules", ""))
    with XkbMap(layouts, variants, model, options, rules) as xkb:
        group = active_group(device, xkb.names())
        layout = layouts.split(",")[group].strip()
        variant = (variants.split(",") + [""] * (group + 1))[group].strip()
        keys, shape = geometry(layout, model)
        name = xkb.names()[group] + (" · ABNT2" if shape == "abnt2" else "")
        identity = json.dumps([layout, variant, model, options, rules, shape])
        return {"available": True, "source": "manual" if manual else "system", "name": name,
                "deviceUid": "" if manual else "xkb:" + hashlib.sha256(identity.encode()).hexdigest()[:24],
                "deviceName": device.get("name", ""), "layout": layout, "variant": variant,
                "model": model, "options": options, "preset": shape,
                "width": 18.5, "height": 6, "keys": keys,
                "layers": [xkb.layer(keys, group, shift, altgr) for shift, altgr in
                           ((False, False), (True, False), (False, True), (True, True))],
                "layerNames": ["Base", "Shift", "AltGr", "Shift + AltGr"],
                "readAt": datetime.now(timezone.utc).isoformat()}


def detect(devices):
    ignored = ("video-bus", "power-button", "sleep-button", "wireless-radio", "consumer-control", "system-control", "avrcp")
    keyboards = [d for d in devices.get("keyboards", []) if isinstance(d, dict)
                 and not any(word in d.get("name", "").lower() for word in ignored)]
    keyboards.sort(key=lambda d: (not d.get("main", False), d.get("name") != "at-translated-set-2-keyboard"))
    for device in keyboards:
        try:
            return read_device(device)
        except ValueError:
            continue
    raise ValueError("No standard active layout could be read from Hyprland. Use Detect Vial for a custom firmware keyboard, or add a manual layout.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preset", choices=["abnt2"])
    args = parser.parse_args()
    try:
        if args.preset:
            result = read_device({"layout": "br", "model": "abnt2", "active_layout_index": 0}, manual=True)
        else:
            reply = subprocess.run(["hyprctl", "devices", "-j"], capture_output=True, text=True, timeout=5, check=True)
            result = detect(json.loads(reply.stdout))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(json.dumps({"available": False, "error": str(error)}, ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
