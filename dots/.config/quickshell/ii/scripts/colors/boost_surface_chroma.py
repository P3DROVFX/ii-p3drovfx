#!/usr/bin/env python3
import sys
import json
from materialyoucolor.hct import Hct
from materialyoucolor.utils.color_utils import rgba_from_argb, argb_from_rgb

def hex_to_argb(hex_code):
    return argb_from_rgb(int(hex_code[1:3], 16), int(hex_code[3:5], 16), int(hex_code[5:], 16))

def argb_to_hex(argb):
    return '#{:02X}{:02X}{:02X}'.format(*map(round, rgba_from_argb(argb)))

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

def main():
    if len(sys.argv) < 2:
        print("Usage: boost_surface_chroma.py <colors.json path> [chroma_factor]", file=sys.stderr)
        sys.exit(1)

    json_path = sys.argv[1]
    chroma_factor = float(sys.argv[2]) if len(sys.argv) > 2 else 7.0

    with open(json_path, 'r') as f:
        colors = json.load(f)

    for token in SURFACE_TOKENS:
        if token in colors:
            try:
                argb = hex_to_argb(colors[token])
                boosted = boost_chroma(argb, chroma_factor)
                colors[token] = argb_to_hex(boosted)
            except Exception:
                pass

    for token in ACCENT_TOKENS:
        if token in colors:
            try:
                argb = hex_to_argb(colors[token])
                boosted = boost_chroma(argb, 2.5)
                colors[token] = argb_to_hex(boosted)
            except Exception:
                pass

    with open(json_path, 'w') as f:
        json.dump(colors, f, indent=2)

if __name__ == '__main__':
    main()
