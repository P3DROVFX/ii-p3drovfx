#!/usr/bin/env python3
"""Stage what the ii-p3drovfx SDDM theme needs to look like the lock screen.

Writes $XDG_STATE_HOME/quickshell/user/generated/sddm/state.json (atomically).
Nothing here needs root: the ii-sddm-sync path unit notices the new file and
copies the referenced files into /var/lib/ii-sddm as root, reading them with
this user's permissions.

The shell passes what only it knows (the cursor it applied, each monitor's
scale); run by hand, those fall back to gsettings and `hyprctl monitors -j`.

Usage: stage_sddm.py [--cursor-theme NAME] [--cursor-size PX] [--scales JSON]
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
STATE_HOME = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state")
SHELL_CONFIG = CONFIG_HOME / "illogical-impulse/config.json"
GENERATED = STATE_HOME / "quickshell/user/generated"
OUT_DIR = GENERATED / "sddm"
OUT_FILE = OUT_DIR / "state.json"

VIDEO_EXTS = {".mp4", ".webm", ".mkv", ".avi", ".mov", ".m4v", ".gif"}
# Islands the greeter can draw, per side. Anything else on the lock (alarm,
# weather, modes...) depends on the user's session and has no meaning here.
LEFT_ISLANDS = ("battery", "capsLock", "keyboardLayout")
RIGHT_ISLANDS = ("sleep", "power", "reboot")
# Background widgets the greeter can draw in the centre of the screen.
CLOCK_WIDGETS = {"clock_digital": "digital", "clock_cookie": "cookie"}


def get(obj, path, default=None):
    for key in path.split("."):
        if not isinstance(obj, dict) or key not in obj:
            return default
        obj = obj[key]
    return obj


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def font_file(family):
    """The file fontconfig would use for `family`, or "" when it substitutes another."""
    if not family:
        return ""
    out = run(["fc-match", "-f", "%{family}\n%{file}", family])
    lines = out.split("\n")
    if len(lines) < 2:
        return ""
    families = [f.strip().lower() for f in lines[0].split(",")]
    return lines[1] if family.strip().lower() in families else ""


def lock_wallpaper(cfg):
    """The image the lock shows: its own one when set apart, else the desktop's."""
    desktop = get(cfg, "background.wallpaperPath", "") or ""
    lock = get(cfg, "background.lockscreenWallpaperPath", "") or ""
    if get(cfg, "background.useSeparateLockscreenWallpaper", False) and lock and lock != desktop:
        return lock, True
    return desktop, False


def still_frame(path):
    """A video wallpaper is shown on the greeter as its first frame."""
    target = OUT_DIR / "wallpaper-frame.png"
    if not shutil.which("ffmpeg"):
        return ""
    result = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-frames:v", "1", str(target)],
        capture_output=True, timeout=60)
    return str(target) if result.returncode == 0 and target.is_file() else ""


def avatar():
    """A picture SDDM cannot find on its own: ~/.face* sits in an unreadable home.
    /var/lib/AccountsService/icons is already read by SDDM, so it is left alone."""
    for name in (".face.icon", ".face"):
        candidate = HOME / name
        if candidate.is_file():
            return str(candidate)
    return ""


def cursor(theme, size):
    if not theme:
        theme = run(["gsettings", "get", "org.gnome.desktop.interface", "cursor-theme"]).strip("'")
    if not size:
        try:
            size = int(run(["gsettings", "get", "org.gnome.desktop.interface", "cursor-size"]) or 0)
        except ValueError:
            size = 0
    # A system-wide copy is preferred: the greeter reads it as is, nothing is copied.
    path = ""
    for base in (Path("/usr/share/icons"), Path("/usr/local/share/icons"), HOME / ".local/share/icons", HOME / ".icons"):
        if (base / theme / "cursors").is_dir():
            path = str(base / theme)
            break
    return {"theme": theme or "", "size": int(size or 24), "path": path}


def monitor_scales(given):
    if given:
        return {str(k): float(v) for k, v in json.loads(given).items()}
    try:
        monitors = json.loads(run(["hyprctl", "monitors", "-j"]) or "[]")
    except json.JSONDecodeError:
        monitors = []
    return {m["name"]: float(m["scale"]) for m in monitors if "name" in m and "scale" in m}


def clock(cfg):
    """The clock the lock centres, if any (the first matching widget wins)."""
    for widget in get(cfg, "background.activeWidgets", []) or []:
        if not isinstance(widget, dict):
            continue
        style = CLOCK_WIDGETS.get(widget.get("id", ""))
        if style and widget.get("lockBehavior", "hide") != "hide":
            return style
    return "none"


def colors(separate_lock):
    """The lock's palette: lockscreen_colors.json only when it has its own wallpaper."""
    for name in (("lockscreen_colors.json", "colors.json") if separate_lock else ("colors.json",)):
        path = GENERATED / name
        try:
            data = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        return {k: v for k, v in data.items()
                if isinstance(v, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", v)}
    return {}


def widget_colors(given):
    """camelCase scheme fields -> snake_case tokens, kept only when they are colours."""
    try:
        data = json.loads(given) if given else {}
    except json.JSONDecodeError:
        return {}
    out = {}
    for key, value in data.items():
        if isinstance(value, str) and re.fullmatch(r"#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?", value):
            out[re.sub(r"(?<!^)([A-Z])", r"_\1", key).lower()] = value
    return out


def islands(cfg, key, allowed):
    order = get(cfg, f"lock.islands.{key}", list(allowed)) or []
    return [i for i in order if i in allowed]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cursor-theme", default="")
    parser.add_argument("--cursor-size", type=int, default=0)
    parser.add_argument("--scales", default="")
    # The background-widget colour scheme as the shell resolved it: {field: "#AARRGGBB"}.
    parser.add_argument("--widget-colors", default="")
    args = parser.parse_args()

    try:
        cfg = json.loads(SHELL_CONFIG.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(f"[stage-sddm] cannot read {SHELL_CONFIG}: {error}", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    wallpaper, separate = lock_wallpaper(cfg)
    if wallpaper and Path(wallpaper).suffix.lower() in VIDEO_EXTS:
        wallpaper = still_frame(wallpaper)
    if wallpaper and not Path(wallpaper).is_file():
        wallpaper = ""

    fonts_cfg = get(cfg, "appearance.fonts", {}) or {}
    families = {
        "main": fonts_cfg.get("main", "Google Sans Flex"),
        "numbers": fonts_cfg.get("numbers", "Google Sans Flex"),
        "expressive": fonts_cfg.get("expressive", "Space Grotesk"),
        "icons": "Material Symbols Rounded",
    }
    fonts = {role: font_file(family) for role, family in families.items()}

    hidden = get(cfg, "lock.islands.hidden", []) or []
    settings = {
        "roundness_full": bool(fonts_cfg.get("roundnessFull", True)),
        "rounding_value": get(cfg, "appearance.roundingValue", 28),
        "sharp_mode": bool(get(cfg, "appearance.sharpMode", False)),
        "anim_multiplier": get(cfg, "appearance.animationMultiplier", 1),
        "transparency": bool(get(cfg, "appearance.transparency.enable", False)),
        "extra_background_tint": bool(get(cfg, "appearance.extraBackgroundTint", True)),
        "material_shape_chars": bool(get(cfg, "lock.materialShapeChars", True)),
        "blur_enable": bool(get(cfg, "lock.blur.enable", True)),
        "blur_radius": get(cfg, "lock.blur.radius", 45),
        "desaturate_enable": bool(get(cfg, "lock.desaturate.enable", True)),
        "desaturate_amount": get(cfg, "lock.desaturate.amount", 0.25),
        "colorwash_enable": bool(get(cfg, "lock.colorWash.enable", False)),
        "colorwash_amount": get(cfg, "lock.colorWash.amount", 0.5),
        "vignette_enable": bool(get(cfg, "lock.vignette.enable", True)),
        "vignette_amount": get(cfg, "lock.vignette.amount", 0.3),
        "battery_low": get(cfg, "battery.low", 20),
        "battery_critical": get(cfg, "battery.critical", 5),
        "islands_left": islands(cfg, "left", LEFT_ISLANDS),
        "islands_right": islands(cfg, "right", RIGHT_ISLANDS),
        "islands_hidden": [i for i in hidden if i in LEFT_ISLANDS + RIGHT_ISLANDS],
        "clock_style": clock(cfg),
        "clock_time_format": get(cfg, "time.format", "hh:mm"),
        "clock_date_format": get(cfg, "time.dateFormat", "MM/dd, ddd"),
        "clock_seconds_format": get(cfg, "time.secondsFormat", "ss"),
    }
    digital = get(cfg, "background.widgets.clock_digital", {}) or {}
    settings.update({
        "digital_colorful": bool(digital.get("colorful", False)),
        "digital_show_colon": bool(digital.get("showColon", True)),
        "digital_show_seconds": bool(get(cfg, "bar.clock.showSeconds", False)),
        "digital_vertical": bool(digital.get("vertical", False)),
        "digital_show_date": bool(digital.get("showDate", True)),
        "digital_line_spacing": get(digital, "lineSpacing", 0),
        "digital_font_size": get(digital, "font.size", 90),
        "digital_font_weight": get(digital, "font.weight", 350),
        "digital_font_width": get(digital, "font.width", 100),
        "digital_font_roundness": get(digital, "font.roundness", 0),
        "digital_quote": digital.get("quoteText", "") if digital.get("quoteEnable") else "",
    })
    cookie = get(cfg, "background.widgets.clock_cookie", {}) or {}
    settings.update({
        "cookie_sides": cookie.get("sides", 14),
        "cookie_background_style": cookie.get("backgroundStyle", "cookie"),
        "cookie_background_shape": cookie.get("backgroundShape", "Arch"),
        "cookie_dial_style": cookie.get("dialNumberStyle", "full"),
        "cookie_hour_hand": cookie.get("hourHandStyle", "fill"),
        "cookie_minute_hand": cookie.get("minuteHandStyle", "medium"),
        "cookie_second_hand": cookie.get("secondHandStyle", "dot"),
        "cookie_date_style": cookie.get("dateStyle", "bubble"),
        "cookie_time_indicators": bool(cookie.get("timeIndicators", True)),
        "cookie_hour_marks": bool(cookie.get("hourMarks", False)),
        "cookie_constantly_rotate": bool(cookie.get("constantlyRotate", False)),
        "cookie_quote": cookie.get("quoteText", "") if cookie.get("quoteEnable") else "",
        "widget_shadows": bool(get(cfg, "background.widgets.enableShadows", True)),
        "show_locked_text": bool(get(cfg, "lock.showLockedText", True)),
    })

    state = {
        "version": 1,
        "wallpaper": wallpaper,
        "fonts": fonts,
        "families": families,
        "avatar": avatar(),
        "cursor": cursor(args.cursor_theme, args.cursor_size),
        "scales": monitor_scales(args.scales),
        "colors": colors(separate),
        "widget_colors": widget_colors(args.widget_colors),
        "settings": settings,
    }

    text = json.dumps(state, indent=2, sort_keys=True)
    try:
        if OUT_FILE.read_text() == text:
            return 0  # unchanged: do not wake the sync service
    except OSError:
        pass
    tmp = OUT_FILE.with_suffix(".tmp")
    tmp.write_text(text)
    os.replace(tmp, OUT_FILE)
    print(f"[stage-sddm] staged {OUT_FILE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
