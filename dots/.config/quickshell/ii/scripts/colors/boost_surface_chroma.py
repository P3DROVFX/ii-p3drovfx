#!/usr/bin/env python3
import os
import sys
import json
import argparse

# Ensure we use the quickshell virtualenv python which has materialyoucolor
try:
    from materialyoucolor.hct import Hct
    from materialyoucolor.utils.color_utils import rgba_from_argb, argb_from_rgb
except (ModuleNotFoundError, ImportError):
    venv = os.environ.get("ILLOGICAL_IMPULSE_VIRTUAL_ENV") or os.path.expanduser("~/.local/state/quickshell/.venv")
    venv_python = os.path.join(venv, "bin", "python3")
    if os.path.exists(venv_python) and sys.executable != venv_python:
        os.execv(venv_python, [venv_python] + sys.argv)
    raise

def hex_to_argb(hex_code):
    return argb_from_rgb(int(hex_code[1:3], 16), int(hex_code[3:5], 16), int(hex_code[5:], 16))

def argb_to_hex(argb):
    return '#{:02x}{:02x}{:02x}'.format(*map(round, rgba_from_argb(argb)))

def boost_chroma(argb, factor=3.0):
    hct = Hct.from_int(argb)
    return Hct.from_hct(hct.hue, hct.chroma * factor, hct.tone).to_int()

SURFACE_TOKENS = [
    'background',
    'surface',
    'surface_bright',
    'surface_container',
    'surface_container_high',
    'surface_container_highest',
    'surface_container_low',
    'surface_container_lowest',
    'surface_dim',
    'surface_variant',
]

ACCENT_TOKENS = [
    'primary',
    'primary_container',
    'primary_fixed',
    'primary_fixed_dim',
    'secondary',
    'secondary_container',
    'secondary_fixed',
    'secondary_fixed_dim',
    'tertiary',
    'tertiary_container',
    'tertiary_fixed',
    'tertiary_fixed_dim',
]

def boost_color_dict(colors, mode, surface_factor, accent_factor):
    if "colors" in colors and isinstance(colors["colors"], dict):
        # Matugen dump format
        dump_colors = colors["colors"]
        for token in SURFACE_TOKENS:
            if token in dump_colors and isinstance(dump_colors[token], dict):
                for variant in (mode, "default"):
                    if variant in dump_colors[token] and isinstance(dump_colors[token][variant], dict):
                        hex_code = dump_colors[token][variant].get("color")
                        if hex_code and isinstance(hex_code, str):
                            try:
                                boosted = boost_chroma(hex_to_argb(hex_code), surface_factor)
                                dump_colors[token][variant]["color"] = argb_to_hex(boosted)
                            except Exception:
                                pass
        for token in ACCENT_TOKENS:
            if token in dump_colors and isinstance(dump_colors[token], dict):
                for variant in (mode, "default"):
                    if variant in dump_colors[token] and isinstance(dump_colors[token][variant], dict):
                        hex_code = dump_colors[token][variant].get("color")
                        if hex_code and isinstance(hex_code, str):
                            try:
                                boosted = boost_chroma(hex_to_argb(hex_code), accent_factor)
                                dump_colors[token][variant]["color"] = argb_to_hex(boosted)
                            except Exception:
                                pass
    else:
        # Flat dictionary format
        for token in SURFACE_TOKENS:
            if token in colors and isinstance(colors[token], str):
                try:
                    argb = hex_to_argb(colors[token])
                    boosted = boost_chroma(argb, surface_factor)
                    colors[token] = argb_to_hex(boosted)
                except Exception:
                    pass

        for token in ACCENT_TOKENS:
            if token in colors and isinstance(colors[token], str):
                try:
                    argb = hex_to_argb(colors[token])
                    boosted = boost_chroma(argb, accent_factor)
                    colors[token] = argb_to_hex(boosted)
                except Exception:
                    pass

def main():
    parser = argparse.ArgumentParser(description='Boost surface chroma in colors.json')
    parser.add_argument('json_path', help='Path to colors.json')
    parser.add_argument('--mode', choices=['dark', 'light'], default='dark', help='Color mode')
    args = parser.parse_args()

    if args.mode == 'light':
        surface_factor = 10.0
        accent_factor = 3.0
    else:
        surface_factor = 7.0
        accent_factor = 2.5

    with open(args.json_path, 'r') as f:
        colors = json.load(f)

    boost_color_dict(colors, args.mode, surface_factor, accent_factor)

    tmp_path = f"{args.json_path}.tmp.{os.getpid()}"
    with open(tmp_path, 'w') as f:
        json.dump(colors, f, indent=2)
        f.write("\n")
    os.replace(tmp_path, args.json_path)

if __name__ == '__main__':
    main()
