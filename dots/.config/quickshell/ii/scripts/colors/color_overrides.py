#!/usr/bin/env python3
"""Hand-picked key colors on top of a generated Material scheme.

Matugen has no way to pin a single role: it derives every role from one source
color. What it does have is `matugen json <dump>`, which renders the templates
from a colors dump instead of generating one. So an override is a patch on the
dump (or on a flat colors.json for themes): the picked color lands exactly on
its role and the roles that belong to it - containers, "on" colors, fixed
variants, the surface ladder - are rebuilt from a tonal palette of that color,
on the tones the Material spec gives them.

Commands:
  patch-dump DUMP --mode M --overrides JSON   patch a `matugen -j hex` dump in place
  patch-flat FILE --mode M --overrides JSON   patch a flat colors.json in place
  derive --mode M --overrides JSON [--base FILE]  print the flat roles as JSON
  theme --color HEX --scheme S --dark OUT --light OUT
                                              write a dark/light theme pair from a seed
  schemes --color HEX                         print the preview roles of every scheme
"""
import argparse
import json
import os
import re
import subprocess
import sys

from materialyoucolor.hct import Hct
from materialyoucolor.palettes.tonal_palette import TonalPalette
from materialyoucolor.utils.color_utils import argb_from_rgb, rgba_from_argb

KEY_ROLES = ("primary", "secondary", "tertiary", "surface")
HEX_RE = re.compile(r"^#?[0-9a-fA-F]{6}$")


def to_hex(color) -> str:
    """An ARGB int, or the [r, g, b, a] list TonalPalette.tone returns."""
    r, g, b, _ = color if isinstance(color, (list, tuple)) else rgba_from_argb(color)
    return "#{:02x}{:02x}{:02x}".format(round(r), round(g), round(b))


def from_hex(value: str) -> int:
    value = value.lstrip("#")
    return argb_from_rgb(int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def clamp_tone(tone: float) -> float:
    return max(0.0, min(100.0, tone))


def accent_roles(name: str, color: str, dark: bool) -> dict:
    """The roles of one accent family, built around the exact picked color."""
    hct = Hct.from_int(from_hex(color))
    palette = TonalPalette.from_hue_and_chroma(hct.hue, max(hct.chroma, 4.0))
    tone = palette.tone
    # "on" color: whichever end of the palette contrasts with the picked tone.
    on_color = tone(10) if hct.tone >= 55 else tone(100)
    roles = {
        name: to_hex(from_hex(color)),
        f"on_{name}": to_hex(on_color),
        f"{name}_container": to_hex(tone(30 if dark else 90)),
        f"on_{name}_container": to_hex(tone(90 if dark else 10)),
        f"{name}_fixed": to_hex(tone(90)),
        f"{name}_fixed_dim": to_hex(tone(80)),
        f"on_{name}_fixed": to_hex(tone(10)),
        f"on_{name}_fixed_variant": to_hex(tone(30)),
    }
    if name == "primary":
        roles["surface_tint"] = roles["primary"]
        roles["inverse_primary"] = to_hex(tone(40 if dark else 80))
    return roles


def surface_roles(color: str) -> dict:
    """The neutral ladder around the exact picked surface.

    Whether it reads as dark or light comes from the color itself, not from the
    mode: a light surface picked for dark mode still gets dark text on it.
    """
    hct = Hct.from_int(from_hex(color))
    base = hct.tone
    dark = base < 50
    neutral = TonalPalette.from_hue_and_chroma(hct.hue, hct.chroma)
    variant = TonalPalette.from_hue_and_chroma(hct.hue, hct.chroma + 4.0)
    n = lambda t: to_hex(neutral.tone(clamp_tone(t)))
    v = lambda t: to_hex(variant.tone(clamp_tone(t)))
    exact = to_hex(from_hex(color))
    # Offsets from the spec's surface tone (6 dark / 98 light) to each container.
    if dark:
        ladder = {"surface_dim": 0, "surface_container_lowest": -2, "surface_container_low": 4,
                  "surface_container": 6, "surface_container_high": 11,
                  "surface_container_highest": 16, "surface_bright": 18}
        on = {"on_surface": n(90), "on_background": n(90), "on_surface_variant": v(80),
              "outline": v(60), "outline_variant": v(base + 24), "surface_variant": v(base + 24),
              "inverse_surface": n(90), "inverse_on_surface": n(20)}
    else:
        ladder = {"surface_dim": -11, "surface_container_lowest": 2, "surface_container_low": -2,
                  "surface_container": -4, "surface_container_high": -6,
                  "surface_container_highest": -8, "surface_bright": 0}
        on = {"on_surface": n(10), "on_background": n(10), "on_surface_variant": v(30),
              "outline": v(50), "outline_variant": v(base - 18), "surface_variant": v(base - 8),
              "inverse_surface": n(20), "inverse_on_surface": n(95)}
    roles = {"surface": exact, "background": exact}
    for role, offset in ladder.items():
        roles[role] = exact if offset == 0 else n(base + offset)
    roles.update(on)
    return roles


def valid_overrides(overrides: dict) -> dict:
    result = {}
    for role in KEY_ROLES:
        value = str((overrides or {}).get(role) or "").strip()
        if HEX_RE.match(value):
            result[role] = value if value.startswith("#") else "#" + value
    return result


def derive(overrides: dict, mode: str) -> dict:
    overrides = valid_overrides(overrides)
    dark = mode != "light"
    if "surface" in overrides:
        # Accents follow the surface they sit on.
        dark = Hct.from_int(from_hex(overrides["surface"])).tone < 50
    roles = {}
    if "surface" in overrides:
        roles.update(surface_roles(overrides["surface"]))
    for role in ("primary", "secondary", "tertiary"):
        if role in overrides:
            roles.update(accent_roles(role, overrides[role], dark))
    return roles


def load_overrides(raw: str) -> dict:
    if not raw:
        return {}
    if os.path.isfile(raw):
        with open(raw) as f:
            raw = f.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def write_json(path: str, data: dict) -> None:
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def patch_dump(path: str, mode: str, overrides: dict) -> int:
    with open(path) as f:
        dump = json.load(f)
    roles = derive(overrides, mode)
    colors = dump.get("colors", {})
    for role, value in roles.items():
        entry = colors.get(role)
        if not isinstance(entry, dict):
            continue
        for key in ("default", mode):
            if isinstance(entry.get(key), dict):
                entry[key]["color"] = value
    write_json(path, dump)
    return len(roles)


def patch_flat(path: str, mode: str, overrides: dict) -> int:
    with open(path) as f:
        colors = json.load(f)
    roles = derive(overrides, mode)
    colors.update(roles)
    write_json(path, colors)
    return len(roles)


SCHEMES = ("scheme-tonal-spot", "scheme-content", "scheme-fidelity", "scheme-intense", "scheme-vibrant",
           "scheme-expressive", "scheme-fruit-salad", "scheme-rainbow", "scheme-neutral", "scheme-monochrome")
PREVIEW_ROLES = ("primary", "on_primary", "primary_container", "on_primary_container",
                 "secondary", "secondary_container", "on_secondary_container",
                 "tertiary", "tertiary_container", "on_tertiary_container",
                 "surface", "surface_container", "surface_container_high", "on_surface", "on_surface_variant",
                 "outline_variant")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))


def seed_scheme(color: str, scheme: str) -> dict:
    """{"dark": {...}, "light": {...}} flat roles of one scheme for a seed."""
    matugen_scheme = "scheme-fidelity" if scheme == "scheme-intense" else scheme
    out = subprocess.run(
        ["bash", os.path.join(SCRIPT_DIR, "matugen.sh"), "color", "hex", color,
         "--dry-run", "-q", "-j", "hex", "-t", matugen_scheme],
        check=True, capture_output=True, text=True).stdout
    colors = json.loads(out)["colors"]
    result = {}
    for mode in ("dark", "light"):
        result[mode] = {role: entry[mode]["color"] for role, entry in sorted(colors.items())
                        if isinstance(entry, dict) and mode in entry}
    if scheme == "scheme-intense":
        # Same surface boost switchwall applies after matugen.
        import tempfile
        for mode in ("dark", "light"):
            with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
                json.dump(result[mode], f)
            try:
                subprocess.run([sys.executable, os.path.join(SCRIPT_DIR, "boost_surface_chroma.py"),
                                f.name, "--mode", mode], check=False, capture_output=True)
                with open(f.name) as boosted:
                    result[mode] = json.load(boosted)
            finally:
                os.unlink(f.name)
    return result


def theme(color: str, scheme: str, dark_out: str, light_out: str) -> None:
    """A theme pair from a seed, in the flat format of defaults/themes."""
    pair = seed_scheme(color, scheme)
    for mode, target in (("dark", dark_out), ("light", light_out)):
        os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
        write_json(target, pair[mode])


def schemes(color: str) -> dict:
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=len(SCHEMES)) as pool:
        pairs = list(pool.map(lambda scheme: seed_scheme(color, scheme), SCHEMES))
    return {scheme: {mode: {role: pair[mode].get(role, "#000000") for role in PREVIEW_ROLES}
                     for mode in ("dark", "light")}
            for scheme, pair in zip(SCHEMES, pairs)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("patch-dump", "patch-flat"):
        p = sub.add_parser(name)
        p.add_argument("file")
        p.add_argument("--mode", choices=["dark", "light"], default="dark")
        p.add_argument("--overrides", default="", help="JSON object or a file holding one")
    p = sub.add_parser("derive")
    p.add_argument("--mode", choices=["dark", "light"], default="dark")
    p.add_argument("--overrides", default="")
    p = sub.add_parser("theme")
    p.add_argument("--color", required=True)
    p.add_argument("--scheme", default="scheme-tonal-spot")
    p.add_argument("--dark", required=True)
    p.add_argument("--light", required=True)
    p = sub.add_parser("schemes")
    p.add_argument("--color", required=True)
    args = parser.parse_args()

    if args.command == "patch-dump":
        patch_dump(args.file, args.mode, load_overrides(args.overrides))
    elif args.command == "patch-flat":
        patch_flat(args.file, args.mode, load_overrides(args.overrides))
    elif args.command == "derive":
        print(json.dumps(derive(load_overrides(args.overrides), args.mode)))
    elif args.command in ("theme", "schemes"):
        if not HEX_RE.match(args.color):
            print("invalid color", file=sys.stderr)
            return 2
        color = args.color if args.color.startswith("#") else "#" + args.color
        if args.command == "theme":
            theme(color, args.scheme, args.dark, args.light)
        else:
            print(json.dumps(schemes(color)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
