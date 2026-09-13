#!/usr/bin/env python3
"""
Reads a Vial keyboard's own physical layout and keymap over raw HID.

The point is that nothing here is hardcoded per keyboard: the firmware carries
its own KLE layout and its keymap, so a split, staggered, rotated board draws
itself correctly and its layers come back labelled. Everything used here is a
read command, and all of it works while the keyboard is locked -- Vial's lock
only gates writes and the matrix tester.

Emits one JSON object on stdout. `--pretty` for reading it by hand.
"""

import glob
import json
import lzma
import math
import os
import select
import struct
import sys

# VIA/Vial raw HID interface: usage page 0xFF60, usage 0x61.
USAGE_PAGE = 0xFF60
USAGE = 0x61
MSG_LEN = 32

CMD_GET_PROTOCOL_VERSION = 0x01
CMD_GET_KEYBOARD_VALUE = 0x02
CMD_DYNAMIC_KEYMAP_MACRO_GET_COUNT = 0x0C
CMD_DYNAMIC_KEYMAP_MACRO_GET_BUFFER_SIZE = 0x0D
CMD_DYNAMIC_KEYMAP_MACRO_GET_BUFFER = 0x0E
CMD_DYNAMIC_KEYMAP_GET_LAYER_COUNT = 0x11
CMD_DYNAMIC_KEYMAP_GET_BUFFER = 0x12
CMD_VIAL_PREFIX = 0xFE

VIAL_GET_KEYBOARD_ID = 0x00
VIAL_GET_SIZE = 0x01
VIAL_GET_DEFINITION = 0x02

ID_LAYOUT_OPTIONS = 0x02
ID_UNHANDLED = 0xFF

KC_NO = 0x0000
KC_TRANSPARENT = 0x0001


# ---------------------------------------------------------------- device ----
def _descriptor_matches(path):
    """True when a hidraw node is the vendor-defined page the Vial protocol uses.

    The interface is found by what it declares rather than by its index: the
    order of a keyboard's interfaces is not guaranteed, and the wrong one
    silently swallows every command.
    """
    try:
        with open(os.path.join(path, "device", "report_descriptor"), "rb") as handle:
            desc = handle.read()
    except OSError:
        return False
    # Usage Page (0xFF60) as a 16-bit item, followed by Usage (0x61).
    return bytes([0x06, USAGE_PAGE & 0xFF, USAGE_PAGE >> 8, 0x09, USAGE]) in desc


def find_device():
    for path in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        uevent = os.path.join(path, "device", "uevent")
        try:
            with open(uevent) as handle:
                info = handle.read()
        except OSError:
            continue
        # Vial firmware advertises itself in the serial number.
        if "vial:" not in info:
            continue
        if not _descriptor_matches(path):
            continue
        node = "/dev/" + os.path.basename(path)
        if os.access(node, os.R_OK | os.W_OK):
            return node, _uevent_value(info, "HID_NAME")
    return None, ""


def _uevent_value(info, key):
    for line in info.splitlines():
        if line.startswith(key + "="):
            return line[len(key) + 1:]
    return ""


class Keyboard:
    def __init__(self, node):
        self.fd = os.open(node, os.O_RDWR | os.O_NONBLOCK)
        while select.select([self.fd], [], [], 0)[0]:
            os.read(self.fd, MSG_LEN)

    def close(self):
        os.close(self.fd)

    def send(self, payload, timeout=1.0):
        """One request, one reply. The leading 0x00 is the report id hidraw wants."""
        os.write(self.fd, bytes([0x00]) + bytes(payload) + bytes(MSG_LEN - len(payload)))
        ready, _, _ = select.select([self.fd], [], [], timeout)
        if not ready:
            raise TimeoutError("keyboard did not answer")
        return os.read(self.fd, MSG_LEN)

    def layer_count(self):
        return self.send([CMD_DYNAMIC_KEYMAP_GET_LAYER_COUNT])[1]

    def layout_options(self):
        reply = self.send([CMD_GET_KEYBOARD_VALUE, ID_LAYOUT_OPTIONS])
        if reply[0] == ID_UNHANDLED:
            return 0
        return struct.unpack(">I", reply[2:6])[0]

    def definition(self):
        """The keyboard's own KLE layout, stored LZMA-compressed in firmware."""
        size = struct.unpack("<I", self.send([CMD_VIAL_PREFIX, VIAL_GET_SIZE])[0:4])[0]
        payload, block, left = b"", 0, size
        while left > 0:
            chunk = self.send([CMD_VIAL_PREFIX, VIAL_GET_DEFINITION]
                              + list(struct.pack("<I", block)))
            payload += chunk[:left] if left < MSG_LEN else chunk
            block += 1
            left -= MSG_LEN
        return json.loads(lzma.decompress(payload))

    def macros(self):
        """The macros as text, indexed by number.

        A macro is a run of bytes in one shared buffer, ended by a zero. What a
        macro finally produces depends on the layout the desktop is running --
        "'a" is a-acute under a dead-key layout and two characters under a plain
        one -- so what comes back here is what the key sends, not what appears.
        """
        count = self.send([CMD_DYNAMIC_KEYMAP_MACRO_GET_COUNT])[1]
        size = struct.unpack(">H", self.send([CMD_DYNAMIC_KEYMAP_MACRO_GET_BUFFER_SIZE])[1:3])[0]
        buf, offset = b"", 0
        while offset < size:
            chunk = min(28, size - offset)
            buf += self.send([CMD_DYNAMIC_KEYMAP_MACRO_GET_BUFFER,
                              (offset >> 8) & 0xFF, offset & 0xFF, chunk])[4:4 + chunk]
            offset += chunk
        out = []
        for raw in buf.split(b"\x00")[:count]:
            try:
                text = raw.decode("ascii")
            except UnicodeDecodeError:
                text = ""
            out.append(text if text.isprintable() else "")
        return out + [""] * (count - len(out))

    def keymap(self, rows, cols, layers):
        """Every layer in one bulk read rather than a round trip per key."""
        total = rows * cols * layers * 2
        buf, offset = b"", 0
        while offset < total:
            size = min(28, total - offset)
            reply = self.send([CMD_DYNAMIC_KEYMAP_GET_BUFFER,
                               (offset >> 8) & 0xFF, offset & 0xFF, size])
            buf += reply[4:4 + size]
            offset += size
        return list(struct.unpack(">%dH" % (rows * cols * layers), buf))


# ------------------------------------------------------------------- KLE ----
def layout_choice(options, group, groups):
    """Which choice a layout group is on, out of the packed `layout_options`.

    Groups are packed low bits first, each taking as many bits as its number of
    choices needs. Only the value the keyboard itself reports is ever decoded.
    """
    shift = 0
    for index, count in enumerate(groups):
        width = max(1, (max(1, count - 1)).bit_length())
        if index == group:
            return (options >> shift) & ((1 << width) - 1)
        shift += width
    return 0


def parse_kle(rows, options, groups):
    """KLE rows into absolutely positioned keys, in key units.

    Keys carry a rotation and the point to rotate about, which is what makes a
    split board's thumb cluster land where it does. A key whose fourth label is
    "group,choice" belongs to a layout option and is dropped unless that group
    is on that choice -- that is how one definition covers a board with an
    optional encoder or an extra key.
    """
    keys = []
    cur = {"x": 0.0, "y": 0.0, "w": 1.0, "h": 1.0, "r": 0.0, "rx": 0.0, "ry": 0.0}
    cluster = {"x": 0.0, "y": 0.0}
    for row in rows:
        if not isinstance(row, list):
            continue
        for item in row:
            if isinstance(item, dict):
                if "r" in item:
                    cur["r"] = float(item["r"])
                if "rx" in item:
                    cur["rx"] = cluster["x"] = float(item["rx"])
                    cur["x"], cur["y"] = cluster["x"], cluster["y"]
                if "ry" in item:
                    cur["ry"] = cluster["y"] = float(item["ry"])
                    cur["x"], cur["y"] = cluster["x"], cluster["y"]
                if "y" in item:
                    cur["y"] += float(item["y"])
                if "x" in item:
                    cur["x"] += float(item["x"])
                if "w" in item:
                    cur["w"] = float(item["w"])
                if "h" in item:
                    cur["h"] = float(item["h"])
                continue

            labels = str(item).split("\n")
            keep = True
            if len(labels) > 3 and "," in labels[3]:
                group, choice = labels[3].split(",")[:2]
                keep = layout_choice(options, int(group), groups) == int(choice)
            if keep and "," in labels[0]:
                matrix_row, matrix_col = labels[0].split(",")[:2]
                keys.append({
                    "row": int(matrix_row),
                    "col": int(matrix_col),
                    "x": round(cur["x"], 4),
                    "y": round(cur["y"], 4),
                    "w": round(cur["w"], 4),
                    "h": round(cur["h"], 4),
                    "r": round(cur["r"], 4),
                    "rx": round(cur["rx"], 4),
                    "ry": round(cur["ry"], 4),
                    # Vial marks an encoder with an "e" in the tenth label.
                    "encoder": len(labels) > 9 and labels[9] == "e",
                })
            cur["x"] += cur["w"]
            cur["w"] = cur["h"] = 1.0
        cur["y"] += 1.0
        cur["x"] = cur["rx"]
    return keys


def bounds(keys):
    """The box the board really occupies, corners of rotated keys included.

    A KLE definition is not written flush against the origin -- this Corne
    starts a whole unit down -- and a thumb key turned 30 degrees reaches past
    the corner it would have had unrotated. Measuring the drawn corners instead
    of the nominal rectangles is what stops the preview from reserving a strip
    of nothing along two edges and then scaling the board down to fit it.
    """
    xs, ys = [], []
    for key in keys:
        angle = math.radians(key["r"])
        cos, sin = math.cos(angle), math.sin(angle)
        for cx, cy in ((key["x"], key["y"]),
                       (key["x"] + key["w"], key["y"]),
                       (key["x"] + key["w"], key["y"] + key["h"]),
                       (key["x"], key["y"] + key["h"])):
            dx, dy = cx - key["rx"], cy - key["ry"]
            xs.append(key["rx"] + dx * cos - dy * sin)
            ys.append(key["ry"] + dx * sin + dy * cos)
    if not xs:
        return 0.0, 0.0, 0.0, 0.0
    return min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys)


def normalise(keys):
    """Slides the board flush against the origin, and reports its size.

    The rotation origin moves with the keys, so the angle each one is drawn at
    is untouched -- only where the whole board sits changes.
    """
    min_x, min_y, width, height = bounds(keys)
    for key in keys:
        for axis, offset in (("x", min_x), ("rx", min_x), ("y", min_y), ("ry", min_y)):
            key[axis] = round(key[axis] - offset, 4)
    return round(width, 4), round(height, 4)


def layout_groups(definition):
    """How many choices each layout option offers, in order."""
    labels = definition.get("layouts", {}).get("labels", [])
    groups = []
    for label in labels:
        # A plain string is an on/off option; a list is its name then its choices.
        groups.append(len(label) - 1 if isinstance(label, list) else 2)
    return groups


# -------------------------------------------------------------- keycodes ----
# HID usage codes, as QMK names them. `label` is what the cap shows; `char` is
# the character the key actually types, which is what lets the typing test keep
# pointing at the next key on a keymap it has never seen before.
_BASIC = {
    0x7A: ("Undo", ""), 0x7B: ("Cut", ""), 0x7C: ("Copy", ""), 0x7D: ("Paste", ""),
    0xAD: ("Stop", ""), 0xD9: ("Wheel\n↑", ""), 0xDA: ("Wheel\n↓", ""),
    0xA8: ("Mute", ""), 0xA9: ("Vol+", ""), 0xAA: ("Vol-", ""),
    0xAB: ("Next", ""), 0xAC: ("Prev", ""), 0xAE: ("Play", ""),
    0xBD: ("Bri+", ""), 0xBE: ("Bri-", ""),
    0x28: ("Enter", "\n"), 0x29: ("Esc", ""), 0x2A: ("Bksp", ""), 0x2B: ("Tab", "\t"),
    0x2C: ("Space", " "), 0x2D: ("-", "-"), 0x2E: ("=", "="), 0x2F: ("[", "["),
    0x30: ("]", "]"), 0x31: ("\\", "\\"), 0x32: ("#", "#"), 0x33: (";", ";"),
    0x34: ("'", "'"), 0x35: ("`", "`"), 0x36: (",", ","), 0x37: (".", "."),
    0x38: ("/", "/"), 0x39: ("Caps", ""),
    0x46: ("PrtSc", ""), 0x47: ("ScrLk", ""), 0x48: ("Pause", ""), 0x49: ("Ins", ""),
    0x4A: ("Home", ""), 0x4B: ("PgUp", ""), 0x4C: ("Del", ""), 0x4D: ("End", ""),
    0x4E: ("PgDn", ""), 0x4F: ("→", ""), 0x50: ("←", ""), 0x51: ("↓", ""),
    0x52: ("↑", ""), 0x53: ("NumLk", ""), 0x65: ("Menu", ""),
    # The right-hand modifiers are broken over two lines rather than left as one
    # long word: a 1u cap has room for about five monospace characters, and
    # "RShift" on one line only fits by shrinking past reading size.
    0xE0: ("Ctrl", ""), 0xE1: ("Shift", ""), 0xE2: ("Alt", ""), 0xE3: ("Super", ""),
    0xE4: ("R\nCtrl", ""), 0xE5: ("R\nShift", ""),
    0xE6: ("Alt\nGr", ""), 0xE7: ("R\nSuper", ""),
}

# What a key types with Shift held, for the labels on a symbol layer.
_SHIFTED = {
    "1": "!", "2": "@", "3": "#", "4": "$", "5": "%", "6": "^", "7": "&",
    "8": "*", "9": "(", "0": ")", "-": "_", "=": "+", "[": "{", "]": "}",
    "\\": "|", ";": ":", "'": "\"", "`": "~", ",": "<", ".": ">", "/": "?",
}

_QUANTUM = {
    0x7820: "RGB\non/off", 0x7821: "RGB\nnext", 0x7822: "RGB\nprev",
    0x7823: "Hue+", 0x7824: "Hue-", 0x7827: "RGB+", 0x7828: "RGB-",
    0x7C00: "Boot", 0x7C01: "Reboot", 0x7C02: "Debug", 0x7C03: "EEPROM",
    # QMK's tri layer pair, which Vial labels exactly like this.
    0x7C77: "Fn1\n(Fn3)", 0x7C78: "Fn2\n(Fn3)",
}

_LAYER_RANGES = [
    (0x5200, "TO"), (0x5220, "MO"), (0x5240, "DF"),
    (0x5260, "TG"), (0x5280, "OSL"), (0x52C0, "TT"),
]

_MOD_NAMES = ["Ctrl", "Shift", "Alt", "Super"]


def _basic(code):
    """(label, char) for a plain HID usage code."""
    if 0x04 <= code <= 0x1D:
        letter = chr(ord("a") + code - 0x04)
        return letter, letter
    if 0x1E <= code <= 0x26:
        digit = chr(ord("1") + code - 0x1E)
        return digit, digit
    if code == 0x27:
        return "0", "0"
    if 0x3A <= code <= 0x45:
        return "F%d" % (code - 0x3A + 1), ""
    if 0x68 <= code <= 0x73:
        return "F%d" % (code - 0x68 + 13), ""
    return _BASIC.get(code, ("0x%04X" % code, ""))


def _mod_label(bits):
    names = [_MOD_NAMES[i] for i in range(4) if bits & (1 << i)]
    return "+".join(names)


def describe(code, macros=None):
    """One keycode as (label, char). Unknown codes keep their hex, not a lie."""
    if code in (KC_NO, KC_TRANSPARENT):
        return "", ""
    if code <= 0xFF:
        return _basic(code)
    # A macro is named by what it sends, which beats a number nobody can read.
    if 0x7700 <= code <= 0x77FF:
        text = (macros or [])[code - 0x7700] if code - 0x7700 < len(macros or []) else ""
        return (text or "M%d" % (code - 0x7700)), ""
    if code in _QUANTUM:
        return _QUANTUM[code], ""
    # Modified basic key: mods in the high byte, the key itself in the low one.
    if 0x0100 <= code <= 0x1FFF:
        bits = (code >> 8) & 0x0F
        label, char = _basic(code & 0xFF)
        if bits == 0x02 and char in _SHIFTED:      # plain Shift on a symbol
            return _SHIFTED[char], _SHIFTED[char]
        if bits == 0x02 and len(char) == 1 and char.isalpha():
            return char.upper(), char.upper()
        return "%s\n%s" % (_mod_label(bits), label), ""
    if 0x2000 <= code <= 0x3FFF:                    # mod-tap
        label, _ = _basic(code & 0xFF)
        return "%s\n%s" % (label, _mod_label((code >> 8) & 0x0F)), ""
    if 0x4000 <= code <= 0x4FFF:                    # layer-tap
        label, _ = _basic(code & 0xFF)
        return "%s\nL%d" % (label, (code >> 8) & 0x0F), ""
    # One-shot ("sticky") modifiers: tapped, they hang on the next key pressed.
    if 0x52A0 <= code <= 0x52BF:
        return "OSM\n%s" % (_mod_label(code & 0x0F) or "?"), ""
    # Tap dance: one key with separate tap, hold and double-tap actions, which
    # live in their own table rather than in the keycode.
    if 0x5700 <= code <= 0x57FF:
        return "TD%d" % (code - 0x5700), ""
    for base, name in _LAYER_RANGES:
        if base <= code < base + 0x20:
            return "%s(%d)" % (name, code - base), ""
    if 0x7800 <= code <= 0x78FF:
        return "RGB", ""
    return "0x%04X" % code, ""


def build_layers(codes, keys, rows, cols, layer_count, macros=None):
    """Per-layer labels for each key, with transparency already resolved.

    The preview selects one layer over layer 0; it does not know the device's
    live layer stack. Transparent positions therefore resolve against layer 0,
    never against inactive intermediate layers.
    """
    layers = []
    for layer in range(layer_count):
        entries = []
        for key in keys:
            index = layer * rows * cols + key["row"] * cols + key["col"]
            code = codes[index] if index < len(codes) else KC_NO
            assigned_code = code
            inherited = False
            if code == KC_TRANSPARENT and layer > 0:
                index = key["row"] * cols + key["col"]
                code = codes[index] if index < len(codes) else KC_NO
                inherited = True
            label, char = describe(code, macros)
            entries.append({"label": label, "char": char, "inherited": inherited,
                            "code": assigned_code, "resolvedCode": code})
        layers.append(entries)
    return layers


def read_keyboard():
    node, name = find_device()
    if node is None:
        return {"available": False,
                "error": "no readable Vial raw HID interface; check the connection and device permissions"}
    board = Keyboard(node)
    try:
        definition = board.definition()
        matrix = definition.get("matrix", {})
        rows, cols = int(matrix.get("rows", 0)), int(matrix.get("cols", 0))
        if rows <= 0 or cols <= 0:
            return {"available": False, "error": "keyboard reported no matrix size"}
        layer_count = board.layer_count()
        options = board.layout_options()
        keys = parse_kle(definition.get("layouts", {}).get("keymap", []),
                         options, layout_groups(definition))
        # An encoder is not a key anybody types on, so it is left out of a
        # preview that exists to point at the next letter.
        keys = [key for key in keys if not key["encoder"]]
        codes = board.keymap(rows, cols, layer_count)
        width, height = normalise(keys)
        identity = board.send([CMD_VIAL_PREFIX, VIAL_GET_KEYBOARD_ID])
        uid = struct.unpack("<Q", identity[4:12])[0]
        return {
            "available": True,
            "name": definition.get("name") or name,
            "deviceUid": f"{uid:016x}",
            "layerCount": layer_count,
            "width": width,
            "height": height,
            "keys": keys,
            "layers": build_layers(codes, keys, rows, cols, layer_count, board.macros()),
        }
    finally:
        board.close()


def main():
    try:
        result = read_keyboard()
    except Exception as error:                       # noqa: BLE001 - reported, not raised
        result = {"available": False, "error": str(error)}
    indent = 1 if "--pretty" in sys.argv else None
    print(json.dumps(result, indent=indent, ensure_ascii=False))
    return 0 if result.get("available") else 1


if __name__ == "__main__":
    sys.exit(main())
