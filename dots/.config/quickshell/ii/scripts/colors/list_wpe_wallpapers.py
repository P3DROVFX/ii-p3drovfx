#!/usr/bin/env python3
import os
import json
import glob

def find_workshop_paths():
    roots = [
        "/mnt/01DA34356F1F3C40/SteamLibrary/steamapps/workshop/content/431960",
        os.path.expanduser("~/.local/share/Steam/steamapps/workshop/content/431960"),
        os.path.expanduser("~/.steam/steam/steamapps/workshop/content/431960"),
        os.path.expanduser("~/.steam/root/steamapps/workshop/content/431960"),
    ]
    
    config_path = os.path.expanduser("~/.config/illogical-impulse/config.json")
    if os.path.exists(config_path):
        try:
            with open(config_path, "r") as f:
                cfg = json.load(f)
                assets_path = cfg.get("background", {}).get("wallpaperEngineAssetsPath", "")
                if assets_path:
                    # Adjust assets_path to workshop path
                    workshop_path = assets_path.replace("common/wallpaper_engine/assets", "workshop/content/431960")
                    workshop_path = workshop_path.replace("common/wallpaper_engine", "workshop/content/431960")
                    if os.path.exists(workshop_path) and workshop_path not in roots:
                        roots.insert(0, workshop_path)
        except Exception:
            pass

    valid_paths = [r for r in roots if os.path.exists(r)]
    return valid_paths

def list_wallpapers():
    paths = find_workshop_paths()
    wallpapers = []
    seen_ids = set()

    for path in paths:
        subdirs = glob.glob(os.path.join(path, "*"))
        for subdir in subdirs:
            if not os.path.isdir(subdir):
                continue
            id_str = os.path.basename(subdir)
            if not id_str.isdigit():
                continue
            if id_str in seen_ids:
                continue
            seen_ids.add(id_str)

            project_json_path = os.path.join(subdir, "project.json")
            if os.path.exists(project_json_path):
                try:
                    with open(project_json_path, "r") as f:
                        data = json.load(f)
                        title = data.get("title", f"Wallpaper {id_str}")
                        preview = data.get("preview", "")
                        preview_path = ""
                        if preview:
                            p_path = os.path.join(subdir, preview)
                            if os.path.exists(p_path):
                                preview_path = p_path

                        wp_type = data.get("type", "NONE")
                        file_ref = data.get("file", "")
                        # Resolve the actual file path for video wallpapers
                        content_file = ""
                        if file_ref:
                            candidate = os.path.join(subdir, file_ref)
                            if os.path.exists(candidate):
                                content_file = candidate

                        mtime = os.path.getmtime(subdir)
                        wallpapers.append({
                            "id": id_str,
                            "title": title,
                            "preview": preview_path,
                            "path": subdir,
                            "mtime": mtime,
                            "type": wp_type,
                            "file": content_file
                        })
                except Exception:
                    pass
    
    # Sort wallpapers by mtime descending (newest first)
    wallpapers.sort(key=lambda x: x.get("mtime", 0), reverse=True)
    
    # Save output to /tmp/wpe_installed_wallpapers.json
    output_path = "/tmp/wpe_installed_wallpapers.json"
    with open(output_path, "w") as f:
        json.dump(wallpapers, f, indent=4)

if __name__ == "__main__":
    list_wallpapers()
