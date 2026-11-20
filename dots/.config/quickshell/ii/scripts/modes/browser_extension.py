#!/usr/bin/env python3
"""Browser extension check and prompt for the browserExtension mode action.

    browser_extension.py check  '<ext json>'            -> one JSON line
    browser_extension.py prompt '<ext json>' [mode name] -> notification with a button

The extension JSON is the action's value: name, firefoxId, chromeId, firefoxUrl,
chromeUrl and page (a page inside the extension, "" when it is always on).

Only the default browser (xdg-settings) is looked at. Profiles are read, never
written: Firefox-family installs from extensions.json and the per-profile
moz-extension UUID from prefs.js, Chromium-family installs from the
Extensions/<id> folder of any profile.
"""

from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HOME = Path.home()

FIREFOX_FAMILY = {
    "firefox": [".mozilla/firefox", ".var/app/org.mozilla.firefox/.mozilla/firefox", "snap/firefox/common/.mozilla/firefox"],
    "zen": [".zen", ".var/app/app.zen_browser.zen/.zen"],
    "librewolf": [".librewolf", ".var/app/io.gitlab.librewolf-community/.librewolf"],
    "floorp": [".floorp", ".var/app/one.ablaze.floorp/.floorp"],
    "waterfox": [".waterfox", ".var/app/net.waterfox.waterfox/.waterfox"],
}

CHROMIUM_FAMILY = {
    "google-chrome": [".config/google-chrome", ".var/app/com.google.Chrome/config/google-chrome"],
    "chromium": [".config/chromium", ".var/app/org.chromium.Chromium/config/chromium"],
    "brave": [".config/BraveSoftware/Brave-Browser", ".var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser"],
    "vivaldi": [".config/vivaldi"],
    "microsoft-edge": [".config/microsoft-edge"],
}


def default_browser() -> str:
    try:
        out = subprocess.run(["xdg-settings", "get", "default-web-browser"],
                             capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        out = ""
    return out


def family_of(desktop: str) -> tuple[str, str]:
    """('firefox' | 'chromium' | '', key into the family table)."""
    name = desktop.lower().removesuffix(".desktop")
    for key in FIREFOX_FAMILY:
        if key in name:
            return "firefox", key
    for key in CHROMIUM_FAMILY:
        if key.split("-")[-1] in name:
            return "chromium", key
    return "", ""


def firefox_profiles(key: str) -> list[Path]:
    profiles = []
    for root in FIREFOX_FAMILY.get(key, []):
        for prefs in glob.glob(str(HOME / root / "*" / "prefs.js")):
            profiles.append(Path(prefs).parent)
    # The profile in use is the one written last.
    return sorted(profiles, key=lambda p: (p / "prefs.js").stat().st_mtime, reverse=True)


def firefox_state(key: str, ext_id: str) -> dict:
    for profile in firefox_profiles(key):
        try:
            addons = json.loads((profile / "extensions.json").read_text()).get("addons", [])
        except (OSError, ValueError):
            continue
        addon = next((a for a in addons if a.get("id") == ext_id), None)
        if not addon:
            continue
        uuid = ""
        try:
            prefs = (profile / "prefs.js").read_text(errors="replace")
            m = re.search(r'user_pref\("extensions\.webextensions\.uuids",\s*"(.*)"\);', prefs)
            if m:
                uuid = json.loads(json.loads('"' + m.group(1) + '"')).get(ext_id, "")
        except (OSError, ValueError):
            pass
        return {"installed": True, "enabled": bool(addon.get("active", True)), "uuid": uuid}
    return {"installed": False, "enabled": False, "uuid": ""}


def chromium_state(key: str, ext_id: str) -> dict:
    for root in CHROMIUM_FAMILY.get(key, []):
        if glob.glob(str(HOME / root / "*" / "Extensions" / ext_id)):
            return {"installed": True, "enabled": True, "uuid": ""}
    return {"installed": False, "enabled": False, "uuid": ""}


def check(ext: dict) -> dict:
    desktop = default_browser()
    family, key = family_of(desktop)
    result = {"browser": key, "family": family, "desktop": desktop,
              "installed": False, "enabled": False, "openUrl": "", "storeUrl": ""}
    page = str(ext.get("page") or "").lstrip("/")
    if family == "firefox":
        ext_id = str(ext.get("firefoxId") or "")
        result["storeUrl"] = str(ext.get("firefoxUrl") or "")
        if ext_id:
            state = firefox_state(key, ext_id)
            result.update(installed=state["installed"], enabled=state["enabled"])
            if page and state["uuid"]:
                result["openUrl"] = f"moz-extension://{state['uuid']}/{page}"
    elif family == "chromium":
        ext_id = str(ext.get("chromeId") or "")
        result["storeUrl"] = str(ext.get("chromeUrl") or "")
        if ext_id:
            state = chromium_state(key, ext_id)
            result.update(installed=state["installed"], enabled=state["enabled"])
            if page and state["installed"]:
                result["openUrl"] = f"chrome-extension://{ext_id}/{page}"
    else:
        result["storeUrl"] = str(ext.get("firefoxUrl") or ext.get("chromeUrl") or "")
    return result


def open_in_browser(desktop: str, url: str) -> None:
    # Extension pages have no handler of their own: hand them to the browser itself.
    if desktop and url.split(":", 1)[0] in ("moz-extension", "chrome-extension"):
        subprocess.Popen(["gtk-launch", desktop, url], start_new_session=True)
    else:
        subprocess.Popen(["xdg-open", url], start_new_session=True)


def prompt(ext: dict, mode: str) -> None:
    state = check(ext)
    name = str(ext.get("name") or "Extension")
    mode = mode or "This mode"
    if state["installed"] and state["enabled"]:
        if not state["openUrl"]:
            return  # Always on: nothing to ask.
        title, body, label, url = (f"Turn on {name}", f"{mode} uses {name} to keep distracting sites away.",
                                   "Turn on", state["openUrl"])
    elif state["installed"]:
        title, body, label, url = (f"{name} is disabled", f"Enable it in your browser's add-ons page for {mode}.",
                                   "", "")
    else:
        if not state["storeUrl"]:
            return
        title, body, label, url = (f"{name} is not installed", f"{mode} works best with it in your browser.",
                                   "Install", state["storeUrl"])
    args = ["notify-send", "-a", "Modes & Routines", "-i", "extension", title, body]
    if not label:
        subprocess.run(args, timeout=10)
        return
    try:
        picked = subprocess.run(args[:1] + ["--wait", "-A", f"open={label}"] + args[1:],
                                capture_output=True, text=True, timeout=600).stdout.strip()
    except subprocess.SubprocessError:
        return
    if picked == "open":
        open_in_browser(state["desktop"], url)


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] not in ("check", "prompt"):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        ext = json.loads(sys.argv[2])
    except ValueError:
        ext = {}
    if sys.argv[1] == "check":
        print(json.dumps(check(ext)))
    else:
        prompt(ext, sys.argv[3] if len(sys.argv) > 3 else "")
    return 0


if __name__ == "__main__":
    sys.exit(main())
