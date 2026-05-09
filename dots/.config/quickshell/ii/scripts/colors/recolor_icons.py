#!/usr/bin/env python3
import os
import json
import re
import shutil
import subprocess
from concurrent.futures import ThreadPoolExecutor

# Paths
# Based on Directories.qml, the config is actually in ~/.config/illogical-impulse/config.json
CONFIG_JSON = os.path.expanduser("~/.config/illogical-impulse/config.json")
COLORS_JSON = os.path.expanduser("~/.local/state/quickshell/user/generated/colors.json")
TARGET_THEME_PATH = os.path.expanduser("~/.local/share/icons/TemaDinamico")

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
                    if "dark" in data["colors"]:
                        return data["colors"]["dark"]
                    elif "light" in data["colors"]:
                        return data["colors"]["light"]
                    return data["colors"]
                return data
    except Exception as e:
        print(f"Error reading colors: {e}")
    return None

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
    primary = colors.get('primary', '#ffffff')
    primary_container = colors.get('primary_container', '#444444')
    on_primary_container = colors.get('on_primary_container', '#ffffff')
    
    def color_replacer(match):
        hex_color = match.group(0)
        brightness = get_brightness(hex_color)
        if brightness < 60:
            return primary
        elif brightness < 180:
            return primary_container
        else:
            return on_primary_container

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

def generate():
    config = get_config()
    colors = get_colors()
    
    if not colors:
        print("No colors found. Please check ~/.local/state/quickshell/user/generated/colors.json")
        return

    # Get icon theme from config or default
    icon_theme_name = config.get("appearance", {}).get("iconTheme", "Papirus-Base")
    print(f"Configured icon theme: {icon_theme_name}")
    
    # Locate base theme
    base_theme_path = ""
    search_dirs = [
        os.path.expanduser("~/.icons"),
        os.path.expanduser("~/.local/share/icons"),
        "/usr/share/icons",
        "/usr/local/share/icons"
    ]
    
    for d in search_dirs:
        p = os.path.join(d, icon_theme_name)
        if os.path.exists(p):
            base_theme_path = p
            break
            
    if not base_theme_path:
        print(f"Icon theme '{icon_theme_name}' not found. Falling back...")
        for fallback_name in ["Papirus-Base", "Papirus", "breeze", "Adwaita"]:
            for d in search_dirs:
                p = os.path.join(d, fallback_name)
                if os.path.exists(p):
                    base_theme_path = p
                    icon_theme_name = fallback_name
                    break
            if base_theme_path: break

    if not base_theme_path:
        print("No suitable base theme found.")
        return

    print(f"Generating TemaDinamico using {icon_theme_name} as base from {base_theme_path}...")
    
    # Ensure target directory exists
    if os.path.exists(TARGET_THEME_PATH):
        shutil.rmtree(TARGET_THEME_PATH)
    os.makedirs(TARGET_THEME_PATH, exist_ok=True)

    # Create index.theme
    src_index = os.path.join(base_theme_path, "index.theme")
    dst_index = os.path.join(TARGET_THEME_PATH, "index.theme")
    
    if os.path.exists(src_index):
        with open(src_index, 'r') as f:
            lines = f.readlines()
        
        with open(dst_index, 'w') as f:
            for line in lines:
                if line.startswith("Name="):
                    f.write("Name=TemaDinamico\n")
                elif line.startswith("Inherits="):
                    f.write(f"Inherits={icon_theme_name},hicolor\n")
                elif line.startswith("Comment="):
                    f.write(f"Comment=Dynamic Material You icons from {icon_theme_name}\n")
                else:
                    f.write(line)
    else:
        with open(dst_index, "w") as f:
            f.write(f"[Icon Theme]\nName=TemaDinamico\nInherits={icon_theme_name},hicolor\nDirectories=scalable/apps,symbolic/apps\n")

    # Scavenge ALL app-related folders
    tasks = []
    processed_folders = set()
    
    for root_dir, dirs, files in os.walk(base_theme_path):
        folder_name = os.path.basename(root_dir)
        # We want apps, places, categories, devices... basically everything that defines the UI look
        if any(x in root_dir.lower() for x in ["apps", "places", "categories", "devices", "status", "actions"]):
            rel_path = os.path.relpath(root_dir, base_theme_path)
            dst_folder = os.path.join(TARGET_THEME_PATH, rel_path)
            os.makedirs(dst_folder, exist_ok=True)
            processed_folders.add(rel_path)
            
            for filename in files:
                if filename.endswith(".svg") or filename.endswith(".png"):
                    tasks.append((os.path.join(root_dir, filename), os.path.join(dst_folder, filename), colors))

    print(f"Processing {len(tasks)} icons from {len(processed_folders)} folders using 12 threads...")
    
    with ThreadPoolExecutor(max_workers=12) as executor:
        results = list(executor.map(process_file, tasks))
    
    print(f"Done! {sum(1 for r in results if r)} icons processed.")

    # Update icon cache
    print("Updating icon cache...")
    subprocess.run(["gtk-update-icon-cache", "-f", TARGET_THEME_PATH], capture_output=True)
    
    # Notify system
    subprocess.run(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", "TemaDinamico"], capture_output=True)
    
    print("Generation complete.")

if __name__ == "__main__":
    generate()
