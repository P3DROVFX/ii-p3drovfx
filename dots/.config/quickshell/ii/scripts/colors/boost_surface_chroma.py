#!/usr/bin/env python3
import sys
import json
import argparse
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

    for token in SURFACE_TOKENS:
        if token in colors:
            try:
                argb = hex_to_argb(colors[token])
                boosted = boost_chroma(argb, surface_factor)
                colors[token] = argb_to_hex(boosted)
            except Exception:
                pass

    for token in ACCENT_TOKENS:
        if token in colors:
            try:
                argb = hex_to_argb(colors[token])
                boosted = boost_chroma(argb, accent_factor)
                colors[token] = argb_to_hex(boosted)
            except Exception:
                pass

    with open(args.json_path, 'w') as f:
        json.dump(colors, f, indent=2)

if __name__ == '__main__':
    main()
