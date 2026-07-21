#!/usr/bin/env python3
"""Carry existing translations across the label renames made by the settings
reorganization (phases 1-6).

Locale files under translations/ are keyed by the English source string, so
every renamed Translation.tr(...) label orphans whatever translation the old
string had. For each old->new pair below, this copies the translation stored
under the OLD key to the NEW key, in every locale that actually has it, and
keeps the old key untouched (out-of-tree forks may still use the old label).

The English identity locale (value == key) is skipped for a pair, since new
English strings already fall back to the tr() argument. Re-running is a no-op:
a pair is only applied when the new key is still missing.

Run from the ii config root:  python3 scripts/i18n/migrate_renames.py
"""
import json
import glob
import os
import sys

# old English source string  ->  new English source string
RENAMES = {
    # --- 6.1 label conventions ---
    "Low warning": "Low warning (%)",
    "Critical warning": "Critical warning (%)",
    "Full battery warning": "Full battery warning (%)",
    "Tint percentage": "Tint (%)",
    "Dim percentage": "Dim (%)",
    "Scale %": "Scale (%)",
    "Background opacity %": "Background opacity (%)",
    "Terminal: Harmony %": "Terminal: Harmony (%)",
    "Terminal: Foreground boost %": "Terminal: Foreground boost (%)",
    "Zoom animation when overview/cheatsheet is open (Beta)":
        "Zoom animation when overview/cheatsheet is open (Experimental)",
    "Experimental - Scale windows with wallpaper":
        "Scale windows with wallpaper (Experimental)",
    # --- section-title renames (phases 1-5) ---
    "Style: Blurred": "Blur style",
    "Style: General": "Widgets & layout",
    "Border Customization": "Borders",
    "Borders & Gaps": "Gaps",
    "Base Icon Themes": "Icons",
    "Decorative Options": "Details",
    "Appearance Preferences": "Theme",
    "File Paths & Transfers": "LocalSend",
    "Corner Mouse Actions": "Screen corners",
    # --- page-name renames (phases 1-5) ---
    "Backgrounds": "Wallpaper",
    "Bar & Status Bar": "Bar",
    "Hyprland Rules": "Windows",
    "Overview Screen": "Overview",
    "System Overlays": "Overlays & OSD",
    "App Search": "Launcher",
    "Monitors": "Displays",
}


def main():
    root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    files = sorted(glob.glob(os.path.join(root, "translations", "*.json")))
    if not files:
        print("no translation files found", file=sys.stderr)
        return 1
    total = 0
    for path in files:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        copied = []
        for old, new in RENAMES.items():
            if old in data and new not in data and data[old] != old:
                data[new] = data[old]
                copied.append(new)
        if copied:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
                f.write("\n")
            total += len(copied)
            print(f"{os.path.basename(path)}: +{len(copied)} ({', '.join(copied)})")
        else:
            print(f"{os.path.basename(path)}: no orphaned translations to carry over")
    print(f"total carried over: {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
