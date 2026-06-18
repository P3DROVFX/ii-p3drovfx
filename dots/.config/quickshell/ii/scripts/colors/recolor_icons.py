#!/usr/bin/env python3
"""
recolor_icons.py — Dynamic Material You Icon Theme Generator

Pipeline:
  1. Recolor SVGs from base icon theme (brightness-based color mapping)
  2. Scavenge missing icons from .desktop files (abs paths + system lookup)
  3. Use gowall to recolor raster icons (PNG/JPG) with Material You palette
  4. Inject everything into DynamicTheme so the system treats them as native

This extends icon pack coverage to 100% — apps without themed icons
(e.g. Zen Browser, AppImages) get gowall-recolored versions automatically.
"""
import os
import json
import re
import shutil
import subprocess
import tempfile
import configparser
import glob
import hashlib
from concurrent.futures import ThreadPoolExecutor


# ── Paths ────────────────────────────────────────────────────────────────────
CONFIG_JSON = os.path.expanduser("~/.config/illogical-impulse/config.json")
COLORS_JSON = os.path.expanduser("~/.local/state/quickshell/user/generated/colors.json")
TARGET_THEME_PATH = os.path.expanduser("~/.local/share/icons/DynamicTheme")

ICON_SEARCH_DIRS = [
    os.path.expanduser("~/.icons"),
    os.path.expanduser("~/.local/share/icons"),
    "/usr/share/icons",
    "/usr/local/share/icons",
    # Flatpak exports — hicolor icons for flatpak apps
    "/var/lib/flatpak/exports/share/icons",
    os.path.expanduser("~/.local/share/flatpak/exports/share/icons"),
]

DESKTOP_SEARCH_DIRS = [
    "/usr/share/applications",
    os.path.expanduser("~/.local/share/applications"),
    "/usr/local/share/applications",
    # Flatpak exports — apps installed via flatpak
    "/var/lib/flatpak/exports/share/applications",
    os.path.expanduser("~/.local/share/flatpak/exports/share/applications"),
]

# Icon sizes to search in icon themes (largest first for best quality)
ICON_SIZE_DIRS = [
    "256x256/apps", "512x512/apps", "192x192/apps", "128x128/apps",
    "96x96/apps", "64x64/apps", "48x48/apps", "scalable/apps",
]


# ── Config & Colors ─────────────────────────────────────────────────────────
def get_config():
    try:
        if os.path.exists(CONFIG_JSON):
            with open(CONFIG_JSON, 'r') as f:
                return json.load(f)
    except Exception as e:
        print(f"Error reading config: {e}")
    return {}


def get_colors():
    try:
        if os.path.exists(COLORS_JSON):
            with open(COLORS_JSON, 'r') as f:
                data = json.load(f)
                if "colors" in data:
                    # Always prefer dark mode colors for icons as requested
                    if "dark" in data["colors"]:
                        return data["colors"]["dark"]
                    elif "light" in data["colors"]:
                        return data["colors"]["light"]
                    return data["colors"]
                return data
    except Exception as e:
        print(f"Error reading colors: {e}")
    return None


def get_icon_colors():
    """
    Fetch colors specifically for icons.
    The user wants icons to ALWAYS use dark mode colors even in light mode.
    """
    config = get_config()
    imgpath = config.get("background", {}).get("wallpaperPath")
    palette_type = config.get("appearance", {}).get("palette", {}).get("type", "scheme-tonal-spot")
    accent_color = config.get("appearance", {}).get("palette", {}).get("accentColor")

    # If we can't find the source, fallback to the current colors.json
    if not imgpath and not accent_color:
        return get_colors()

    try:
        # We run matugen directly to get the JSON output with all modes
        # We use --dry-run to avoid errors with missing templates and force dark mode for icons
        cmd = ["matugen"]
        if accent_color and accent_color.startswith("#"):
            cmd += ["color", "hex", accent_color]
        elif imgpath:
            cmd += ["image", imgpath, "--source-color-index", "0"]
        else:
            return get_colors()

        cmd += ["-t", palette_type, "-j", "hex", "--dry-run", "--mode", "dark"]
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.stdout:
            try:
                # Extract JSON part from stdout in case of warnings/errors
                json_str = result.stdout
                start = json_str.find('{')
                end = json_str.rfind('}')
                if start != -1 and end != -1:
                    data = json.loads(json_str[start:end+1])
                    if "colors" in data:
                        colors = {}
                        for key, val in data["colors"].items():
                            # Extract the dark mode color for every key
                            if "dark" in val:
                                colors[key] = val["dark"].get("color", val["dark"].get("hex"))
                            elif "default" in val:
                                colors[key] = val["default"].get("color", val["default"].get("hex"))
                        if colors:
                            return colors
            except:
                pass
    except Exception as e:
        print(f"Error fetching dark colors via matugen: {e}")
    
    return get_colors()


# ── SVG Recoloring (Phase 1) ────────────────────────────────────────────────
def get_brightness(hex_color):
    hex_color = hex_color.lstrip('#')
    if len(hex_color) == 3:
        hex_color = ''.join([c*2 for c in hex_color])
    try:
        r = int(hex_color[0:2], 16)
        g = int(hex_color[2:4], 16)
        b = int(hex_color[4:6], 16)
        return (0.299 * r + 0.587 * g + 0.114 * b)
    except:
        return 128


def recolor_svg(content, colors):
    # Collect available tones and sort them by brightness
    # We use a mix of primary, secondary and their containers to get a rich scale
    candidates = [
        colors.get('primary'),
        colors.get('primary_container'),
        colors.get('secondary'),
        colors.get('secondary_container'),
        colors.get('on_primary'),
        colors.get('on_secondary')
    ]
    palette = []
    seen = set()
    for c in candidates:
        if c and c.lower() not in seen:
            palette.append(c.lower())
            seen.add(c.lower())
            
    palette.sort(key=get_brightness)
    
    # Ensure we don't use pure black if it's the only dark tone and we have others
    if len(palette) > 3 and get_brightness(palette[0]) < 10:
        palette.pop(0)

    def color_replacer(match):
        hex_color = match.group(0)
        brightness = get_brightness(hex_color)
        # Map brightness to palette index
        idx = int((brightness / 256.0) * len(palette))
        return palette[min(idx, len(palette)-1)]

    hex_pattern = re.compile(r'#[0-9a-fA-F]{6}|#[0-9a-fA-F]{3}')
    new_content = hex_pattern.sub(color_replacer, content)

    if not new_content.strip().startswith("<?xml"):
        new_content = '<?xml version="1.0" encoding="UTF-8"?>\n' + new_content
    return new_content


def process_file(args):
    src_file, dst_file, colors = args
    try:
        if src_file.endswith(".svg"):
            with open(src_file, 'r', errors='ignore') as f:
                content = f.read()
            new_content = recolor_svg(content, colors)
            with open(dst_file, 'w') as f:
                f.write(new_content)
        else:
            shutil.copy2(src_file, dst_file)
        return True
    except:
        return False


# ── Icon Scavenging (Phase 2) ───────────────────────────────────────────────
def find_icon_in_themes(icon_name, theme_dirs):
    """Search system icon themes for icon_name, return best resolution path."""
    for theme_dir in theme_dirs:
        if not os.path.isdir(theme_dir):
            continue
        for theme in os.listdir(theme_dir):
            theme_path = os.path.join(theme_dir, theme)
            if theme == "DynamicTheme" or not os.path.isdir(theme_path):
                continue
            for size_dir in ICON_SIZE_DIRS:
                apps_dir = os.path.join(theme_path, size_dir)
                if not os.path.isdir(apps_dir):
                    continue
                for ext in [".svg", ".png", ".xpm"]:
                    candidate = os.path.join(apps_dir, icon_name + ext)
                    if os.path.isfile(candidate):
                        return candidate
    # Also check hicolor and pixmaps
    for fallback in ["/usr/share/pixmaps", "/usr/share/icons/hicolor"]:
        if os.path.isdir(fallback):
            if fallback.endswith("pixmaps"):
                for ext in [".svg", ".png", ".xpm", ""]:
                    candidate = os.path.join(fallback, icon_name + ext)
                    if os.path.isfile(candidate):
                        return candidate
            else:
                for size_dir in ICON_SIZE_DIRS:
                    apps_dir = os.path.join(fallback, size_dir)
                    if not os.path.isdir(apps_dir):
                        continue
                    for ext in [".svg", ".png", ".xpm"]:
                        candidate = os.path.join(apps_dir, icon_name + ext)
                        if os.path.isfile(candidate):
                            return candidate
    return None


def get_existing_tema_icons():
    """Get set of icon names (lowercase, no ext) already in DynamicTheme."""
    icons = set()
    for root, dirs, files in os.walk(TARGET_THEME_PATH):
        for f in files:
            name = os.path.splitext(f)[0]
            icons.add(name.lower())
    return icons


IMAGE_EXTENSIONS = {".png", ".svg", ".jpg", ".jpeg", ".xpm", ".gif", ".bmp"}

def strip_image_ext(name):
    """Strip image extension only. Preserves reverse-domain names like com.rtosta.zapzap."""
    _name, ext = os.path.splitext(name)
    if ext.lower() in IMAGE_EXTENSIONS:
        return _name
    return name  # keep as-is: com.rtosta.zapzap → com.rtosta.zapzap (not .zapzap stripped)


def scavenge_missing_icons(existing_icons):
    """
    Parse .desktop files, find icons not in DynamicTheme.
    Returns list of (icon_name, source_path) tuples for raster icons to recolor.
    SVG icons are processed inline (recolored directly).
    Also returns a mapping of absolute path icon basenames to their original .desktop paths.
    """
    missing_raster = []  # (icon_name, source_path) — for gowall
    missing_svg = []     # (icon_name, source_path) — for direct SVG recolor
    absolute_path_desktops = {} # icon_name -> desktop_file_path

    for desktop_dir in DESKTOP_SEARCH_DIRS:
        if not os.path.isdir(desktop_dir):
            continue
        for df in glob.glob(os.path.join(desktop_dir, "*.desktop")):
            try:
                cp = configparser.ConfigParser(interpolation=None)
                cp.read(df, encoding='utf-8')
                if not cp.has_section('Desktop Entry'):
                    continue
                icon = cp.get('Desktop Entry', 'Icon', fallback='')
                if not icon:
                    continue

                # Resolve source path and determine the icon name to inject
                source_path = None
                if icon.startswith("/"):
                    # Absolute path — use .desktop filename as primary icon name
                    # e.g., zen.desktop with Icon=/path/to/default128.png → inject as "zen"
                    desktop_basename = os.path.splitext(os.path.basename(df))[0]
                    icon_basename = desktop_basename
                    file_basename = os.path.splitext(os.path.basename(icon))[0]

                    # Check if either name already exists
                    if icon_basename.lower() in existing_icons and file_basename.lower() in existing_icons:
                        continue

                    if os.path.isfile(icon):
                        source_path = icon
                    else:
                        for ext in [".png", ".svg", ".xpm"]:
                            if os.path.isfile(icon + ext):
                                source_path = icon + ext
                                break

                    if source_path:
                        absolute_path_desktops[icon_basename] = df
                else:
                    # Icon name — use as-is (preserve full reverse-domain: com.rtosta.zapzap)
                    icon_basename = strip_image_ext(os.path.basename(icon))
                    if icon_basename.lower() in existing_icons:
                        continue
                    source_path = find_icon_in_themes(icon, ICON_SEARCH_DIRS)

                if not source_path:
                    continue

                # Determine names to inject (primary + alias for abs-path icons)
                names_to_inject = [icon_basename]
                if icon.startswith("/"):
                    file_basename = strip_image_ext(os.path.basename(icon))
                    if file_basename.lower() != icon_basename.lower() and file_basename.lower() not in existing_icons:
                        names_to_inject.append(file_basename)

                for inject_name in names_to_inject:
                    if source_path.endswith(".svg"):
                        missing_svg.append((inject_name, source_path))
                    elif source_path.lower().endswith((".png", ".jpg", ".jpeg", ".xpm")):
                        missing_raster.append((inject_name, source_path))
                    else:
                        # Extensionless files (common in AppImages) — treat as raster
                        missing_raster.append((inject_name, source_path))

            except Exception:
                continue

    return missing_svg, missing_raster, absolute_path_desktops


def hex_to_rgb(hex_color):
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

def recolor_raster_icons(raster_icons, colors, target_apps_dir):
    import base64
    try:
        from PIL import Image
    except ImportError:
        print("  Pillow not installed, skipping accurate raster recoloring")
        return []

    if not raster_icons:
        return []

    def get_luminance(rgb):
        return 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]

    # Build a multi-stop gradient palette for deep, rich recoloring
    # Including 'on' colors to ensure we have a full range from dark to light
    raw_palette = [
        hex_to_rgb(colors.get('on_primary', '#000000')),
        hex_to_rgb(colors.get('on_secondary', '#111111')),
        hex_to_rgb(colors.get('secondary_container', '#222222')),
        hex_to_rgb(colors.get('primary_container', '#444444')),
        hex_to_rgb(colors.get('secondary', '#888888')),
        hex_to_rgb(colors.get('primary', '#ffffff'))
    ]
    raw_palette.sort(key=get_luminance)

    r_lut, g_lut, b_lut = [], [], []
    num_colors = len(raw_palette)
    for i in range(256):
        t = i / 255.0
        scaled_t = t * (num_colors - 1)
        idx = int(scaled_t)
        if idx >= num_colors - 1:
            c = raw_palette[-1]
        else:
            fraction = scaled_t - idx
            c1 = raw_palette[idx]
            c2 = raw_palette[idx + 1]
            c = (
                int(c1[0] + (c2[0] - c1[0]) * fraction),
                int(c1[1] + (c2[1] - c1[1]) * fraction),
                int(c1[2] + (c2[2] - c1[2]) * fraction)
            )
        r_lut.append(c[0])
        g_lut.append(c[1])
        b_lut.append(c[2])

    successful_names = []
    with tempfile.TemporaryDirectory() as tmpdir:
        for icon_name, source_path in raster_icons:
            try:
                img = Image.open(source_path).convert("RGBA")
                alpha = img.split()[3]
                gray = img.convert("L")
                
                # Apply gradient map
                r = gray.point(r_lut)
                g = gray.point(g_lut)
                b = gray.point(b_lut)
                
                mapped = Image.merge("RGB", (r, g, b))
                mapped.putalpha(alpha)
                img = mapped
                
                # Save full res for SVG wrapping
                out_path = os.path.join(tmpdir, icon_name + ".png")
                img.save(out_path, "PNG")
                
                # Place in multiple size directories
                sizes = [256, 128, 64, 48, 32, 24, 16]
                for size in sizes:
                    size_dir = f"{size}x{size}/apps"
                    dest_dir = os.path.join(TARGET_THEME_PATH, size_dir)
                    os.makedirs(dest_dir, exist_ok=True)
                    dest_file = os.path.join(dest_dir, icon_name + ".png")
                    
                    resized = img.resize((size, size), Image.Resampling.LANCZOS)
                    resized.save(dest_file, "PNG")

                # Wrap in an SVG and place in scalable/apps so Qt QIcon is guaranteed to pick it up
                scalable_dir = os.path.join(TARGET_THEME_PATH, "scalable/apps")
                os.makedirs(scalable_dir, exist_ok=True)
                svg_dest_file = os.path.join(scalable_dir, icon_name + ".svg")
                with open(out_path, "rb") as f:
                    b64_data = base64.b64encode(f.read()).decode('ascii')
                
                svg_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<svg viewBox="0 0 256 256" width="256" height="256" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <image width="256" height="256" xlink:href="data:image/png;base64,{b64_data}"/>
</svg>"""
                with open(svg_dest_file, "w") as f:
                    f.write(svg_content)
                
                successful_names.append(icon_name)
            except Exception as e:
                print(f"  Failed to process {icon_name}: {e}")

    return successful_names


def inject_scavenged_svgs(svg_icons, colors, target_apps_dir):
    """Recolor scavenged SVG icons and inject into DynamicTheme."""
    successful_names = []
    for icon_name, source_path in svg_icons:
        try:
            with open(source_path, 'r', errors='ignore') as f:
                content = f.read()
            new_content = recolor_svg(content, colors)

            for size_dir in ["scalable/apps", "symbolic/apps"]:
                dest_dir = os.path.join(TARGET_THEME_PATH, size_dir)
                os.makedirs(dest_dir, exist_ok=True)
                dest_file = os.path.join(dest_dir, icon_name + ".svg")
                with open(dest_file, 'w') as f:
                    f.write(new_content)

            successful_names.append(icon_name)
        except Exception:
            pass
    return successful_names


def patch_desktop_file(original_df_path, new_icon_name):
    """
    Safely copies system .desktop files to the user local folder if needed,
    and replaces absolute Icon paths with the relative themed icon name.
    """
    user_apps_dir = os.path.expanduser("~/.local/share/applications")
    filename = os.path.basename(original_df_path)
    dest_df_path = os.path.join(user_apps_dir, filename)

    if os.path.abspath(original_df_path) != os.path.abspath(dest_df_path):
        try:
            os.makedirs(user_apps_dir, exist_ok=True)
            shutil.copy2(original_df_path, dest_df_path)
            print(f"  Copied system desktop file {filename} to user directory")
        except Exception as e:
            print(f"  Failed to copy {original_df_path} to {dest_df_path}: {e}")
            return False

    try:
        with open(dest_df_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()

        new_lines = []
        in_desktop_entry = False
        icon_replaced = False

        for line in lines:
            stripped = line.strip()
            if stripped.startswith('[') and stripped.endswith(']'):
                if stripped == '[Desktop Entry]':
                    in_desktop_entry = True
                else:
                    in_desktop_entry = False

            if in_desktop_entry and line.startswith('Icon='):
                new_lines.append(f"Icon={new_icon_name}\n")
                icon_replaced = True
            else:
                new_lines.append(line)

        if icon_replaced:
            with open(dest_df_path, 'w', encoding='utf-8') as f:
                f.writelines(new_lines)
            print(f"  Patched {filename} to use Icon={new_icon_name}")
            return True
    except Exception as e:
        print(f"  Failed to patch desktop file {dest_df_path}: {e}")

    return False


def create_lowercase_symlinks(theme_path):
    """
    Scans the theme path and creates lowercase symlinks for all files containing
    uppercase characters. This ensures case-insensitive icon lookup succeeds on Linux.
    """
    print("Creating lowercase symlinks for case-insensitive icon lookup...")
    symlink_count = 0
    for root, dirs, files in os.walk(theme_path):
        for f in files:
            lower_f = f.lower()
            if lower_f != f:
                lower_path = os.path.join(root, lower_f)
                if not os.path.exists(lower_path):
                    try:
                        os.symlink(f, lower_path)
                        symlink_count += 1
                    except Exception:
                        pass
    print(f"  Created {symlink_count} lowercase symlinks.")


# ── Main Generation ─────────────────────────────────────────────────────────
def generate():
    global TARGET_THEME_PATH
    config = get_config()
    colors = get_icon_colors()

    if not colors:
        print("No colors found. Please check ~/.local/state/quickshell/user/generated/colors.json")
        return

    # Get icon theme from config or default
    icon_theme_name = config.get("appearance", {}).get("iconTheme", "Papirus-Base")
    print(f"Configured icon theme: {icon_theme_name}")

    # Locate base theme
    base_theme_path = ""
    for d in ICON_SEARCH_DIRS:
        p = os.path.join(d, icon_theme_name)
        if os.path.exists(p):
            base_theme_path = p
            break

    if not base_theme_path:
        print(f"Icon theme '{icon_theme_name}' not found. Falling back...")
        for fallback_name in ["Papirus-Base", "Papirus", "breeze", "Adwaita"]:
            for d in ICON_SEARCH_DIRS:
                p = os.path.join(d, fallback_name)
                if os.path.exists(p):
                    base_theme_path = p
                    icon_theme_name = fallback_name
                    break
            if base_theme_path: break

    if not base_theme_path:
        print("No suitable base theme found.")
        return

    print(f"Generating DynamicTheme using {icon_theme_name} as base from {base_theme_path}...")

    # ── Skip if colors haven't changed ───────────────────────────────────
    colors_hash = hashlib.md5(json.dumps(colors, sort_keys=True).encode()).hexdigest()
    hash_file = TARGET_THEME_PATH + ".colhash"
    try:
        if os.path.isfile(hash_file) and open(hash_file).read().strip() == colors_hash and os.path.isdir(TARGET_THEME_PATH):
            # Check same base theme too
            base_tag = TARGET_THEME_PATH + ".basetheme"
            if os.path.isfile(base_tag) and open(base_tag).read().strip() == icon_theme_name:
                print(f"Colors unchanged (hash={colors_hash[:8]}), skipping regeneration.")
                return
    except Exception:
        pass

    # ── Phase 0: Generate into temp dir, then atomic swap ─────────────────
    # We generate into TARGET_THEME_PATH + ".new" and rename at the end
    # so Quickshell always has a complete set of icons available.
    NEW_THEME_PATH = TARGET_THEME_PATH + ".new"
    if os.path.exists(NEW_THEME_PATH):
        shutil.rmtree(NEW_THEME_PATH)
    os.makedirs(NEW_THEME_PATH, exist_ok=True)

    # Patch all TARGET_THEME_PATH references below to point to NEW_THEME_PATH during generation
    # We do this by temporarily swapping the global
    OLD_TARGET = TARGET_THEME_PATH
    TARGET_THEME_PATH = NEW_THEME_PATH

    # Create index.theme
    src_index = os.path.join(base_theme_path, "index.theme")
    dst_index = os.path.join(TARGET_THEME_PATH, "index.theme")

    if os.path.exists(src_index):
        with open(src_index, 'r') as f:
            lines = f.readlines()

        with open(dst_index, 'w') as f:
            for line in lines:
                if line.startswith("Name="):
                    f.write("Name=DynamicTheme\n")
                elif line.startswith("Inherits="):
                    f.write(f"Inherits={icon_theme_name},hicolor\n")
                elif line.startswith("Comment="):
                    f.write(f"Comment=Dynamic Material You icons from {icon_theme_name}\n")
                else:
                    f.write(line)
    else:
        with open(dst_index, "w") as f:
            f.write(f"[Icon Theme]\nName=DynamicTheme\nInherits={icon_theme_name},hicolor\n"
                    f"Directories=scalable/apps,symbolic/apps,256x256/apps,128x128/apps,48x48/apps\n\n"
                    f"[scalable/apps]\nSize=256\nMinSize=16\nMaxSize=1024\nType=Scalable\nContext=Applications\n\n"
                    f"[symbolic/apps]\nSize=16\nMinSize=8\nMaxSize=512\nType=Scalable\nContext=Applications\n\n"
                    f"[256x256/apps]\nSize=256\nType=Fixed\nContext=Applications\n\n"
                    f"[128x128/apps]\nSize=128\nType=Fixed\nContext=Applications\n\n"
                    f"[48x48/apps]\nSize=48\nType=Fixed\nContext=Applications\n")

    # ── Phase 1: Recolor base theme SVGs ─────────────────────────────────
    tasks = []
    processed_folders = set()

    for root_dir, dirs, files in os.walk(base_theme_path):
        if any(x in root_dir.lower() for x in ["apps", "places", "categories", "devices", "status", "actions"]):
            rel_path = os.path.relpath(root_dir, base_theme_path)
            dst_folder = os.path.join(TARGET_THEME_PATH, rel_path)
            os.makedirs(dst_folder, exist_ok=True)
            processed_folders.add(rel_path)

            for filename in files:
                if filename.endswith(".svg") or filename.endswith(".png"):
                    tasks.append((os.path.join(root_dir, filename), os.path.join(dst_folder, filename), colors))

    print(f"[Phase 1] Processing {len(tasks)} base theme icons from {len(processed_folders)} folders...")

    with ThreadPoolExecutor(max_workers=12) as executor:
        results = list(executor.map(process_file, tasks))

    base_count = sum(1 for r in results if r)
    print(f"[Phase 1] Done! {base_count} base icons recolored.")

    # ── Phase 2: Scavenge & recolor missing icons ────────────────────────
    print("[Phase 2] Scavenging missing icons from .desktop files...")
    existing = get_existing_tema_icons()
    missing_svg, missing_raster, absolute_path_desktops = scavenge_missing_icons(existing)
    print(f"  Found {len(missing_svg)} SVG + {len(missing_raster)} raster icons to scavenge")

    svg_count = 0
    raster_count = 0

    # 2a: SVGs — direct recolor
    if missing_svg:
        successful_svgs = inject_scavenged_svgs(missing_svg, colors, TARGET_THEME_PATH)
        svg_count = len(successful_svgs)
        print(f"  Injected {svg_count} scavenged SVG icons")
        for name in successful_svgs:
            if name in absolute_path_desktops:
                patch_desktop_file(absolute_path_desktops[name], name)

    # 2b: Raster — Pillow pixel-perfect brightness mapping recolor
    if missing_raster:
        successful_rasters = recolor_raster_icons(missing_raster, colors, TARGET_THEME_PATH)
        raster_count = len(successful_rasters)
        print(f"  Injected {raster_count} Pillow-recolored raster icons")
        for name in successful_rasters:
            if name in absolute_path_desktops:
                patch_desktop_file(absolute_path_desktops[name], name)

    # ── Phase 3: Finalize ────────────────────────────────────────────────
    # Create lowercase symlinks for case-insensitive lookup
    create_lowercase_symlinks(TARGET_THEME_PATH)

    # Update index.theme Directories if needed (ensure scavenged dirs are listed)
    _ensure_directories_in_index(dst_index)

    print("[Phase 3] Updating icon cache...")
    subprocess.run(["gtk-update-icon-cache", "-f", TARGET_THEME_PATH], capture_output=True)

    # ── Atomic swap: replace old DynamicTheme with new one ───────────────
    # Restores TARGET_THEME_PATH global to original value before swapping
    TARGET_THEME_PATH = OLD_TARGET
    OLD_PATH = TARGET_THEME_PATH + ".old"
    if os.path.exists(TARGET_THEME_PATH):
        if os.path.exists(OLD_PATH):
            shutil.rmtree(OLD_PATH)
        os.rename(TARGET_THEME_PATH, OLD_PATH)
    os.rename(NEW_THEME_PATH, TARGET_THEME_PATH)
    if os.path.exists(OLD_PATH):
        shutil.rmtree(OLD_PATH)

    # Save hash so next run can skip if colors unchanged
    try:
        with open(hash_file, 'w') as f:
            f.write(colors_hash)
        base_tag = TARGET_THEME_PATH + ".basetheme"
        with open(base_tag, 'w') as f:
            f.write(icon_theme_name)
    except Exception:
        pass

    # Notify system
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", "DynamicTheme"], capture_output=True)

    total = base_count + svg_count + raster_count
    print(f"Generation complete. {total} total icons in DynamicTheme.")


def _ensure_directories_in_index(index_path):
    """Make sure all actual subdirs are listed in index.theme Directories."""
    if not os.path.isfile(index_path):
        return

    actual_dirs = set()
    for root, dirs, files in os.walk(TARGET_THEME_PATH):
        if files:
            rel = os.path.relpath(root, TARGET_THEME_PATH)
            if rel != ".":
                actual_dirs.add(rel)

    with open(index_path, 'r') as f:
        content = f.read()

    # Find existing Directories= line
    match = re.search(r'^Directories=(.*)$', content, re.MULTILINE)
    if match:
        existing = set(d.strip() for d in match.group(1).split(',') if d.strip())
        merged = existing | actual_dirs
        new_line = "Directories=" + ",".join(sorted(merged))
        content = content[:match.start()] + new_line + content[match.end():]

        # Add missing section headers for new directories
        for d in actual_dirs - existing:
            parts = d.split('/')
            context = "Applications" if "apps" in d.lower() else (
                "MimeTypes" if "mime" in d.lower() else
                "Places" if "places" in d.lower() else
                "Devices" if "devices" in d.lower() else
                "Actions" if "actions" in d.lower() else
                "Status" if "status" in d.lower() else
                "Categories"
            )
            # Determine if scalable or fixed
            if "scalable" in d.lower() or "symbolic" in d.lower():
                section = (f"\n\n[{d}]\nSize=256\nMinSize=16\nMaxSize=1024\n"
                          f"Type=Scalable\nContext={context}\n")
            else:
                # Try to extract size from dir name
                size_match = re.search(r'(\d+)x\d+', d)
                size = size_match.group(1) if size_match else "48"
                section = f"\n\n[{d}]\nSize={size}\nType=Fixed\nContext={context}\n"

            content += section

        with open(index_path, 'w') as f:
            f.write(content)


if __name__ == "__main__":
    generate()
