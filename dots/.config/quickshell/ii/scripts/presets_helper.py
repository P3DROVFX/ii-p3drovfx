#!/usr/bin/env python3
import json
import os
import sys
import glob
import re

SENSITIVE_KEY_NAMES = {
    "password", "passwd", "secret", "clientsecret", "token", "accesstoken",
    "refreshtoken", "idtoken", "sessiontoken", "apikey", "credentials",
    "credential", "authorization", "cookie", "cookies"
}

def _normalize_key(key: str) -> str:
    return key.lower().replace('_', '').replace('-', '')

def is_sensitive_key(key: str) -> bool:
    norm_k = _normalize_key(key)
    if norm_k in SENSITIVE_KEY_NAMES:
        return True
    if any(norm_k.endswith(s) for s in ("apikey", "secret", "token", "password", "passwd")):
        return True
    return False

DOCK_BLACKLIST_KEYS = {
    "pinnedApps",
    "pinnedFiles",
    "appGroups",
    "order",
    "ignoredAppRegexes",
    "livePreviewAppId",
    "enableMediaWidget",
    "enableWeatherWidget",
    "enableSportsWidget",
    "enableLivePreviewWidget",
    "livePreviewSlots",
    "livePreviewPaintCursor",
    "livePreviewCaptureMode",
    "livePreviewFollowActiveWindow",
    "showPhoneButton",
    "showTrashButton",
    "showOverviewButton",
    "showPinButton",
}

def remove_secrets_and_userdata(data):
    if isinstance(data, dict):
        cleaned = {}
        for k, v in data.items():
            if k == 'googleDrive':
                continue
            if is_sensitive_key(k):
                continue
            if k == 'search' and isinstance(v, dict):
                search_copy = {}
                for sk, sv in v.items():
                    if sk == 'aliases':
                        continue
                    if is_sensitive_key(sk):
                        continue
                    search_copy[sk] = remove_secrets_and_userdata(sv)
                cleaned[k] = search_copy
                continue
            if k == 'dock' and isinstance(v, dict):
                dock_copy = {}
                for dk, dv in v.items():
                    if dk in DOCK_BLACKLIST_KEYS or is_sensitive_key(dk):
                        continue
                    dock_copy[dk] = remove_secrets_and_userdata(dv)
                cleaned[k] = dock_copy
                continue
            cleaned[k] = remove_secrets_and_userdata(v)
        return cleaned
    elif isinstance(data, list):
        return [remove_secrets_and_userdata(x) for x in data]
    return data

def sanitize_val(val, home_dir):
    if isinstance(val, dict):
        return {k: sanitize_val(v, home_dir) for k, v in val.items()}
    elif isinstance(val, list):
        return [sanitize_val(x, home_dir) for x in val]
    elif isinstance(val, str):
        if home_dir and home_dir in val:
            val = val.replace(home_dir, '$HOME')
        val = re.sub(r'/(?:var/)?home/[^/\s"\']+', '$HOME', val)
        return val
    return val

def normalize_path_field(data, section_name, field_name, home_dir, fallback=None):
    section = data.get(section_name)
    if not isinstance(section, dict) or field_name not in section:
        return

    value = section.get(field_name)
    if not isinstance(value, str) or not value:
        return

    path = value.strip()
    if path.startswith('file://'):
        path = path[7:]

    if path == '$HOME' or path.startswith('$HOME' + os.sep) or path.startswith('$HOME/'):
        section[field_name] = path
        return

    if home_dir and (path == home_dir or path.startswith(home_dir + os.sep) or path.startswith(home_dir + '/')):
        section[field_name] = '$HOME' + path[len(home_dir):]
        return

    # Check for foreign /home/<user> or /var/home/<user>
    matched_home = re.match(r'^/(?:var/)?home/[^/]+(/.*)?$', path)
    if matched_home:
        subpath = matched_home.group(1) or ''
        section[field_name] = '$HOME' + subpath
        return

    if os.path.isabs(path) and fallback:
        section[field_name] = fallback
    else:
        section[field_name] = path

def reset_monitor_bindings(data):
    background = data.get('background')
    if isinstance(background, dict) and isinstance(background.get('widgets'), dict):
        widgets = background['widgets']
        widgets['showOnlyOnSingleMonitor'] = False
        widgets['targetMonitor'] = ''

    bar = data.get('bar')
    if isinstance(bar, dict):
        bar['onlyShowOnSingleMonitor'] = False
        bar['singleMonitorName'] = ''
        bar['screenList'] = []

        floating_notch = bar.get('floatingNotch')
        if isinstance(floating_notch, dict):
            floating_notch['onlyShowOnSingleMonitor'] = False
            floating_notch['singleMonitorName'] = ''

    interactions = data.get('interactions')
    if isinstance(interactions, dict) and isinstance(interactions.get('touchGestures'), dict):
        interactions['touchGestures']['targetMonitor'] = 'auto'

    notifications = data.get('notifications')
    if isinstance(notifications, dict) and isinstance(notifications.get('monitor'), dict):
        notifications['monitor']['enable'] = False
        notifications['monitor']['name'] = ''

def sanitize_data(data, home_dir):
    data = remove_secrets_and_userdata(data)

    if 'appearance' in data and isinstance(data['appearance'], dict):
        icons = data['appearance'].get('icons')
        if isinstance(icons, dict):
            icons['enableThemed'] = False
        data['appearance']['iconTheme'] = ''

    data = sanitize_val(data, home_dir)

    # Keep user paths portable when a preset is imported by another account.
    normalize_path_field(data, 'screenRecord', 'savePath', home_dir, '$HOME/Videos')
    normalize_path_field(data, 'screenSnip', 'savePath', home_dir, '$HOME/Pictures/Screenshots')
    normalize_path_field(data, 'localsend', 'downloadPath', home_dir, '$HOME/Downloads')
    normalize_path_field(data, 'userProfile', 'imagePath', home_dir)
    normalize_path_field(data, 'sidebar', 'bannerImage', home_dir)
    if 'sidebar' in data and isinstance(data['sidebar'], dict) and 'dashboardHeader' in data['sidebar'] and isinstance(data['sidebar']['dashboardHeader'], dict):
        normalize_path_field(data['sidebar'], 'dashboardHeader', 'profileImagePath', home_dir)

    # Monitor connector names are local to the source machine.
    reset_monitor_bindings(data)
    return data

def sanitize(input_path, output_path):
    with open(input_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    home_dir = os.environ.get('HOME', '')
    if home_dir.endswith('/'):
        home_dir = home_dir[:-1]

    data = sanitize_data(data, home_dir)

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=4)

def expand_val(val, home_dir):
    if isinstance(val, dict):
        return {k: expand_val(v, home_dir) for k, v in val.items()}
    elif isinstance(val, list):
        return [expand_val(x, home_dir) for x in val]
    elif isinstance(val, str):
        if '$HOME' in val:
            return val.replace('$HOME', home_dir)
        return val
    return val

def expand(input_path, output_path, presets_dir, preset_name):
    with open(input_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    home_dir = os.environ.get('HOME', '')
    if home_dir.endswith('/'):
        home_dir = home_dir[:-1]
        
    data = expand_val(data, home_dir)
    
    # Check if background.wallpaperPath exists
    bg = data.get('background', {})
    if isinstance(bg, dict):
        wall_path = bg.get('wallpaperPath', '')
        if not wall_path or not os.path.exists(wall_path):
            # Check for fallback file in presets_dir
            fallback = find_wallpaper_fallback(presets_dir, preset_name)
            if fallback:
                bg['wallpaperPath'] = fallback
                data['background'] = bg

    # Check if userProfile.imagePath exists
    profile = data.get('userProfile', {})
    if isinstance(profile, dict):
        profile_path = profile.get('imagePath', '')
        if not profile_path or not os.path.exists(profile_path):
            fallback_prof = find_profile_fallback(presets_dir, preset_name)
            if fallback_prof:
                profile['imagePath'] = fallback_prof
                data['userProfile'] = profile

    # Check sidebar.dashboardHeader.profileImagePath and sidebar.bannerImage
    sb = data.get('sidebar', {})
    if isinstance(sb, dict):
        dash_hdr = sb.get('dashboardHeader', {})
        if isinstance(dash_hdr, dict):
            p_path = dash_hdr.get('profileImagePath', '')
            if not p_path or not os.path.exists(p_path):
                fallback_prof = find_profile_fallback(presets_dir, preset_name)
                if fallback_prof:
                    dash_hdr['profileImagePath'] = fallback_prof
                    sb['dashboardHeader'] = dash_hdr

        banner_path = sb.get('bannerImage', '')
        if not banner_path or not os.path.exists(banner_path):
            fallback_banner = find_banner_fallback(presets_dir, preset_name)
            if fallback_banner:
                sb['bannerImage'] = fallback_banner
                data['sidebar'] = sb

    # Preserve target user's existing dock apps and widgets when output config already exists
    if os.path.exists(output_path):
        try:
            with open(output_path, 'r', encoding='utf-8') as f:
                existing_config = json.load(f)
            if isinstance(existing_config, dict) and isinstance(existing_config.get('dock'), dict):
                if 'dock' not in data or not isinstance(data['dock'], dict):
                    data['dock'] = {}
                for key in DOCK_BLACKLIST_KEYS:
                    if key in existing_config['dock']:
                        data['dock'][key] = existing_config['dock'][key]
        except Exception:
            pass

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=4)

def find_wallpaper_fallback(presets_dir, preset_name):
    pattern = os.path.join(presets_dir, f"{preset_name}.*")
    for filepath in glob.glob(pattern):
        ext = os.path.splitext(filepath)[1].lower()
        if ext not in ('.json', '.zip'):
            base = os.path.basename(filepath)
            if not base.startswith(f"{preset_name}_profile.") and not base.startswith(f"{preset_name}_banner."):
                return filepath
    return None

def find_profile_fallback(presets_dir, preset_name):
    pattern = os.path.join(presets_dir, f"{preset_name}_profile.*")
    for filepath in glob.glob(pattern):
        ext = os.path.splitext(filepath)[1].lower()
        if ext not in ('.json', '.zip'):
            return filepath
    return None

def find_banner_fallback(presets_dir, preset_name):
    pattern = os.path.join(presets_dir, f"{preset_name}_banner.*")
    for filepath in glob.glob(pattern):
        ext = os.path.splitext(filepath)[1].lower()
        if ext not in ('.json', '.zip'):
            return filepath
    return None

def list_presets(presets_dir):
    home_dir = os.environ.get('HOME', '')
    if home_dir.endswith('/'):
        home_dir = home_dir[:-1]
        
    pattern = os.path.join(presets_dir, "*.json")
    # Sort presets by name case-insensitively
    preset_files = sorted(glob.glob(pattern), key=lambda x: os.path.basename(x).lower())
    for json_path in preset_files:
        filename = os.path.basename(json_path)
        preset_name = os.path.splitext(filename)[0]
        
        try:
            with open(json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except Exception:
            continue
            
        bg = data.get('background', {})
        wall_path = ''
        if isinstance(bg, dict):
            wall_path = bg.get('wallpaperPath', '')
            if wall_path:
                wall_path = wall_path.replace('$HOME', home_dir)
                
        if not wall_path or not os.path.exists(wall_path):
            fallback = find_wallpaper_fallback(presets_dir, preset_name)
            if fallback:
                wall_path = fallback
                
        print(json.dumps({"name": preset_name, "wallpaper": wall_path}))

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
        
    action = sys.argv[1]
    if action == 'sanitize':
        if len(sys.argv) < 4:
            sys.exit(1)
        sanitize(sys.argv[2], sys.argv[3])
    elif action == 'expand':
        if len(sys.argv) < 6:
            sys.exit(1)
        expand(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5])
    elif action == 'list':
        if len(sys.argv) < 3:
            sys.exit(1)
        list_presets(sys.argv[2])
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
