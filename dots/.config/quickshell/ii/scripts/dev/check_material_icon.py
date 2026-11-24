#!/usr/bin/env python3
"""Check that Material Symbols icon names exist in the installed Rounded font.

Usage: check_material_icon.py NAME [NAME...]
A name the font lacks renders as its literal text (or nothing) in the shell,
with no warning in the log. Exit status 1 when any name is missing.
"""
import glob
import sys

try:
    from fontTools.ttLib import TTFont
except ImportError:
    print("fontTools is needed: pip install --user fonttools", file=sys.stderr)
    sys.exit(2)

candidates = sorted(glob.glob("/usr/share/fonts/**/MaterialSymbolsRounded*.ttf", recursive=True))
if not candidates:
    print("Material Symbols Rounded font not found", file=sys.stderr)
    sys.exit(2)
glyphs = set(TTFont(candidates[0]).getGlyphOrder())
missing = 0
for name in sys.argv[1:]:
    ok = name in glyphs
    missing += 0 if ok else 1
    print(("OK      " if ok else "MISSING ") + name)
sys.exit(1 if missing else 0)
