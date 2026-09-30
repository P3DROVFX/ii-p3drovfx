#!/usr/bin/env python3
"""
Builds services/easyEffects/EasyEffectsPlugins.js from the Easy Effects sources.

Easy Effects installs no schema: every default, range and choice list is compiled
into the binary. The shell's effect editor needs them to add an effect to a preset
(a missing choice key keeps whatever the previous preset left, so a new block has to
spell every one out) and to draw its controls. They come from the upstream sources
at a tagged release:

  src/contents/kcfg/easyeffects_db_<plugin>.kcfg   types, defaults, ranges, choices
  src/<plugin>_preset.cpp                          which JSON key maps to which entry
  src/tags_<plugin>.hpp                            per-band entry names

Usage:
  generate_plugin_table.py [--tag v8.3.0] [--source DIR] [--out PATH]

--source reads a local checkout instead of fetching raw files from GitHub.
"""

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

REPO_RAW = "https://raw.githubusercontent.com/wwmm/easyeffects/{tag}/{path}"
HERE = Path(__file__).resolve().parent
DEFAULT_OUT = HERE.parent.parent / "services" / "easyEffects" / "EasyEffectsPlugins.js"

# Plugin id -> display name, as tags_plugin_name.cpp lists them. Level meter and
# the analysis nodes are not user-facing effects and are left out.
PLUGINS = {
    "autogain": "Autogain",
    "bass_enhancer": "Bass Enhancer",
    "bass_loudness": "Bass Loudness",
    "compressor": "Compressor",
    "convolver": "Convolver",
    "crossfeed": "Crossfeed",
    "crosstalk_canceller": "Crosstalk Canceller",
    "crusher": "Crusher",
    "crystalizer": "Crystalizer",
    "deepfilternet": "Deep Noise Remover",
    "deesser": "Deesser",
    "delay": "Delay",
    "echo_canceller": "Echo Canceller",
    "equalizer": "Equalizer",
    "midside_equalizer": "Mid-Side Equalizer",
    "exciter": "Exciter",
    "expander": "Expander",
    "filter": "Filter",
    "gate": "Gate",
    "limiter": "Limiter",
    "loudness": "Loudness",
    "maximizer": "Maximizer",
    "multiband_compressor": "Multiband Compressor",
    "multiband_gate": "Multiband Gate",
    "pitch": "Pitch",
    "reverb": "Reverberation",
    "rnnoise": "Noise Reduction",
    "speex": "Speech Processor",
    "stereo_tools": "Stereo Tools",
    "voice_suppressor": "Voice Suppressor",
    "autotune": "Autotune",
}

# Effects whose bands hang off named channels, loaded through the equalizer channel schema.
CHANNELLED = {"equalizer": ["left", "right"], "midside_equalizer": ["mid", "side"]}
# Effects with a fixed number of band sections, loaded with `.at("bandN")`.
MULTIBAND = {"multiband_compressor", "multiband_gate"}

UPDATE_RE = re.compile(r'UPDATE_(ENUM_LIKE_)?PROPERTY\(\s*"([^"]+)"\s*,\s*(\w+)\s*\)')
UPDATE_SUB_RE = re.compile(
    r'UPDATE_(ENUM_LIKE_)?PROPERTY_INSIDE_SUBSECTION\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*(\w+)\s*\)')
BAND_VALUE_RE = re.compile(r'(band_\w+)\[n\]\.data\(\),\s*(?:settings->(\w+)Labels\(\)\.indexOf\()?'
                           r'\s*jbandn\.value\(\s*"([^"]+)"')
TAG_ARRAY_RE = re.compile(r'constexpr auto (band_\w+)\s*=\s*std::to_array\(\{\{"([^"]+)"\}')
ENTRY_RE = re.compile(r'<entry name="(\w+)" type="(\w+)">(.*?)</entry>', re.S)
STRING_KEYS = {"kernel-name": "KernelName", "model-name": "ModelName"}


class Source:
    def __init__(self, tag, local):
        self.tag = tag
        self.local = Path(local) if local else None

    def read(self, path, optional=False):
        try:
            if self.local:
                return (self.local / path).read_text()
            url = REPO_RAW.format(tag=self.tag, path=path)
            with urllib.request.urlopen(url, timeout=30) as response:
                return response.read().decode()
        except Exception:
            if optional:
                return ""
            raise


def lower_first(name):
    return name[:1].lower() + name[1:]


def parse_number(text, kind):
    text = text.strip()
    if kind == "Bool":
        return text.lower() == "true"
    if kind in ("Int", "UInt", "Enum"):
        return int(float(text)) if re.fullmatch(r"-?\d+(\.\d+)?", text) else 0
    if kind == "Double":
        value = float(text)
        return int(value) if value.is_integer() else value
    return text


def parse_kcfg(text):
    entries = {}
    for name, kind, body in ENTRY_RE.findall(text):
        def tag(t):
            match = re.search(rf"<{t}>(.*?)</{t}>", body, re.S)
            return match.group(1).strip() if match else None

        entry = {"type": kind, "label": tag("label") or ""}
        default = tag("default")
        if kind == "StringList":
            entry["default"] = default.split(",") if default else []
        elif default is not None:
            entry["default"] = parse_number(default, kind)
        for bound in ("min", "max"):
            value = tag(bound)
            if value is not None:
                entry[bound] = parse_number(value, "Double")
        entries[name] = entry
    return entries


def load_body(cpp):
    match = re.search(r"::load\(const nlohmann::json& json\)\s*\{(.*?)\n\}", cpp, re.S)
    return match.group(1) if match else ""


def control_for(key, prop, entries, enum, section=""):
    entry = entries.get(prop)
    if entry is None:
        return None
    control = {"key": key, "prop": prop}
    if section:
        control["section"] = section
    if enum:
        labels = entries.get(prop + "Labels", {}).get("default", [])
        if not labels:
            return None
        index = entry.get("default", 0)
        control.update(type="enum", options=labels, default=labels[index] if index < len(labels) else labels[0])
        return control
    kind = entry["type"]
    if kind == "Bool":
        control.update(type="bool", default=entry.get("default", False))
    elif kind in ("Double", "Int", "UInt"):
        control.update(type="int" if kind != "Double" else "double", default=entry.get("default", 0))
        for bound in ("min", "max"):
            if bound in entry:
                control[bound] = entry[bound]
    elif kind == "String":
        control.update(type="string", default=entry.get("default", ""))
    else:
        return None
    return control


def band_controls(plugin, cpp, entries, source, count):
    """The keys every `bandN` section carries, resolved through the tag arrays."""
    tags = source.read(f"src/tags_{plugin}.hpp", optional=True)
    patterns = {}
    for array, first in TAG_ARRAY_RE.findall(tags):
        # "band0AttackTime" -> "band%1AttackTime", the per-band entry pattern.
        patterns[array] = re.sub(r"^band0", "band%1", first)
    body = re.sub(r"\s+", " ", load_body(cpp))
    controls = []
    seen = set()
    for array, labels_of, key in BAND_VALUE_RE.findall(body):
        if key in seen or array not in patterns:
            continue
        seen.add(key)
        pattern = patterns[array]
        per_band = [entries.get(pattern.replace("%1", str(n))) for n in range(count)]
        first_band = next((n for n, e in enumerate(per_band) if e is not None), None)
        if first_band is None:
            continue
        sample = per_band[first_band]
        control = {"key": key, "propPattern": pattern, "fromBand": first_band}
        if labels_of:
            labels = entries.get(lower_first(labels_of) + "Labels", {}).get("default", [])
            control.update(type="enum", options=labels,
                           defaults=[labels[e.get("default", 0)] if e else None for e in per_band])
        elif sample["type"] == "Bool":
            control.update(type="bool", defaults=[e.get("default", False) if e else None for e in per_band])
        else:
            control.update(type="double" if sample["type"] == "Double" else "int",
                           defaults=[e.get("default", 0) if e else None for e in per_band])
            for bound in ("min", "max"):
                if bound in sample:
                    control[bound] = sample[bound]
        controls.append(control)
    return controls


def channel_band_controls(source):
    entries = parse_kcfg(source.read("src/contents/kcfg/easyeffects_db_equalizer_channel.kcfg"))
    count = sum(1 for name in entries if re.fullmatch(r"band\d+Gain", name))
    spec = [("type", "Type", True), ("mode", "Mode", True), ("slope", "Slope", True),
            ("solo", "Solo", False), ("mute", "Mute", False), ("gain", "Gain", False),
            ("frequency", "Frequency", False), ("q", "Q", False), ("width", "Width", False)]
    controls = []
    for key, suffix, enum in spec:
        per_band = [entries.get(f"band{n}{suffix}") for n in range(count)]
        sample = per_band[0]
        control = {"key": key, "propPattern": "band%1" + suffix, "fromBand": 0}
        if enum:
            labels = entries[f"band{suffix}Labels"]["default"]
            control.update(type="enum", options=labels, defaults=[labels[e.get("default", 0)] for e in per_band])
        elif sample["type"] == "Bool":
            control.update(type="bool", defaults=[e.get("default", False) for e in per_band])
        else:
            control.update(type="double", defaults=[e.get("default", 0) for e in per_band])
            for bound in ("min", "max"):
                if bound in sample:
                    control[bound] = sample[bound]
        controls.append(control)
    return count, controls


def build(source):
    table = {}
    eq_count, eq_bands = channel_band_controls(source)
    for plugin, name in PLUGINS.items():
        kcfg = source.read(f"src/contents/kcfg/easyeffects_db_{plugin}.kcfg", optional=True)
        cpp = source.read(f"src/{plugin}_preset.cpp", optional=True)
        if not kcfg or not cpp:
            print(f"skipping {plugin}: sources missing", file=sys.stderr)
            continue
        entries = parse_kcfg(kcfg)
        body = load_body(cpp)
        controls = []
        for section_match in UPDATE_SUB_RE.finditer(body):
            enum, section, key, prop = section_match.groups()
            control = control_for(key, lower_first(prop), entries, bool(enum), section)
            if control:
                controls.append(control)
        for match in UPDATE_RE.finditer(body):
            enum, key, prop = match.groups()
            control = control_for(key, lower_first(prop), entries, bool(enum))
            if control:
                controls.append(control)
        for key, prop in STRING_KEYS.items():
            if f'"{key}"' in body and lower_first(prop) in entries:
                control = control_for(key, lower_first(prop), entries, False)
                if control:
                    controls.append(control)
        # Top-level keys first, then each subsection together, in the loader's order.
        controls.sort(key=lambda c: 1 if c.get("section") else 0)
        plugin_entry = {"name": name, "controls": controls}
        if plugin in CHANNELLED:
            plugin_entry["channels"] = CHANNELLED[plugin]
            plugin_entry["bands"] = {"count": eq_count, "countKey": "num-bands", "controls": eq_bands}
        elif plugin in MULTIBAND:
            match = re.search(r"n_bands\s*=\s*(\d+)", source.read(f"src/tags_{plugin}.hpp", optional=True))
            count = int(match.group(1)) if match else 8
            plugin_entry["bands"] = {"count": count, "controls": band_controls(plugin, cpp, entries, source, count)}
        table[plugin] = plugin_entry
    return table


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tag", default="v8.3.0")
    parser.add_argument("--source", help="local Easy Effects checkout")
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    args = parser.parse_args()

    table = build(Source(args.tag, args.source))
    version = args.tag.lstrip("v")
    # One effect per line: small, and a regenerated table still diffs by effect.
    body = "{\n" + ",\n".join(
        f"    {json.dumps(plugin)}: {json.dumps(entry, ensure_ascii=False, separators=(',', ':'))}"
        for plugin, entry in table.items()) + "\n}"
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        ".pragma library\n\n"
        "// Generated by scripts/easyeffects/generate_plugin_table.py from Easy Effects "
        f"{args.tag}. Do not edit by hand; rerun the script against a newer tag instead.\n"
        "//\n"
        "// Per effect: its display name, every preset key with its type, range, default and\n"
        "// choices, the socket property it maps to (`prop`), and for banded effects the\n"
        "// per-band keys (`propPattern` with %1 for the band index).\n\n"
        f'var sourceVersion = "{version}";\n\n'
        f"var plugins = {body};\n"
    )
    print(f"wrote {out} ({len(table)} effects)")


if __name__ == "__main__":
    main()
