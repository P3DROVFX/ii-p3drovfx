#!/usr/bin/env python3
import copy
import json
import os
import sys
import glob
import re
import tempfile

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

# ---------------------------------------------------------------------------
# Machine-local and personal config paths
#
# A preset is a whole config.json, so everything the author's machine knows
# about rides along with it: paired-device MAC addresses, contact ids, the
# folder they save recordings to, the name on their profile card. None of it
# means anything on another machine and some of it is nobody else's business,
# so it is stripped when a preset is written and taken from the importer's own
# config when one is applied.
#
# Paths are dotted; "*" matches any dict key or list index.
# ---------------------------------------------------------------------------

# Blanked rather than removed. Presets published before merge() existed carry
# these keys, and a neutral value is what those presets expect to find.
MONITOR_BINDING_PATHS = (
    "bar.onlyShowOnSingleMonitor",
    "bar.singleMonitorName",
    "bar.screenList",
    "bar.floatingNotch.onlyShowOnSingleMonitor",
    "bar.floatingNotch.singleMonitorName",
    "background.widgets.showOnlyOnSingleMonitor",
    "background.widgets.targetMonitor",
    "interactions.touchGestures.targetMonitor",
    "notifications.monitor.enable",
    "notifications.monitor.name",
)

# Identity and paired hardware. Removed outright: there is no neutral value
# worth shipping, and these travel no better than they anonymize.
PERSONAL_PATHS = (
    "userProfile.customName",
    "userProfile.customBio",
    "userProfile.customGreeting",
    "userProfile.imagePath",
    "sidebar.dashboardHeader.profileImagePath",
    "background.widgets.*.imagePath",
    "background.thumbnailPath",
    "bluetoothDeviceImages",
    "soundcore.macAddress",
    "phone.contacts.favoriteIds",
    "phone.microphone.wifiIp",
    "todo.googleTasks.taskListId",
    "todo.googleTasks.taskListTitle",
    "tailscale.exitNode",
    "tailscale.advertiseRoutes",
    "vpn.defaultProfile",
    "vpn.defaultLocation",
    "vpn.recentProvider",
    "update.lastAutoCheck",
    "update.scriptPath",
)

# Folders that exist on the author's disk and probably nowhere else.
LOCAL_FOLDER_PATHS = (
    "screenRecord.savePath",
    "screenSnip.savePath",
    "localsend.downloadPath",
    "mediaDownloader.downloadPath",
    "wallpapers.paths",
    "wallpaperSelector.customDefaultPath",
    "wallpaperSelector.directories",
)

# Choices a theme has no business overriding.
LOCAL_PREFERENCE_PATHS = (
    "appearance.iconTheme",
    "appearance.icons.enableThemed",
    "language",
    "policies",
    "workSafety",
)

# Everything merge() hands back to the importer.
LOCAL_ONLY_PATHS = (
    MONITOR_BINDING_PATHS + PERSONAL_PATHS + LOCAL_FOLDER_PATHS + LOCAL_PREFERENCE_PATHS
)

# Path fields a preset is meant to bring with it. Each falls back to a bundled
# asset, then to whatever the importer already had, so applying a preset never
# leaves a dead path behind. A kind of None skips the bundled-asset step.
ASSET_PATHS = (
    ("background.wallpaperPath", "wallpaper"),
    ("background.lightModeWallpaperPath", None),
    ("sidebar.bannerImage", "banner"),
)

# ---------------------------------------------------------------------------
# Risk scanning
#
# A preset is a whole config file, and a handful of config keys are commands
# the shell hands to a shell. Applying a stranger's preset is therefore a
# decision that has to be made with the facts in hand, so everything a preset
# would change that can run something, redirect traffic or widen what the
# assistant may do on its own is collected up front and shown before a single
# byte is written.
# ---------------------------------------------------------------------------

# (pattern, category, note). Patterns take the same dotted form as above.
RISK_RULES = (
    ("apps.*", "shell", "Command run when this shell action is picked"),
    ("update.scriptFlags", "shell", "Arguments handed to the updater"),
    ("mediaDownloader.extraArgs", "shell", "Extra arguments handed to the downloader"),
    ("ai.tools.allowShellInLocalPolicy", "ai", "Lets the assistant run shell commands"),
    ("ai.tools.alwaysAllow", "ai", "Assistant tools that stop asking first"),
    ("dnsOverTls.serverName", "network", "Encrypted DNS resolver"),
    ("dnsOverTls.serverAddress", "network", "Encrypted DNS resolver"),
    ("mediaDownloader.proxy", "network", "Proxy every download goes through"),
    ("search.engineBaseUrl", "network", "Where the search bar sends what is typed"),
    ("search.imageSearch.imageSearchEngineBaseUrl", "network", "Where image searches are uploaded"),
)

# Modes and routines can carry a "shell" action whose value is run with sh -c
# when the mode starts or ends, and a mode can start itself off a trigger, so
# these run without anyone pressing anything.
MODE_ACTION_PATTERNS = ("modes.modes.*.actions.*", "modes.routines.*.actions.*")

SEVERITY = {"shell": "high", "ai": "high", "network": "medium", "unknown": "medium"}

RISK_ORDER = ("shell", "ai", "network", "unknown")

# Strings that read like a command line. Deliberately loose: a false positive
# costs one more line in the dialog, a miss costs someone their session.
COMMAND_HINT_RE = re.compile(
    r"\$\(|`|&&|\|\||;\s*\S|\b(?:sh|bash|zsh|fish)\s+-c\b"
    r"|\b(?:curl|wget|ncat|socat|ssh|scp)\b|\brm\s+-|\bnc\s+-"
    r"|\b(?:pkexec|sudo|doas)\b|\bchmod\b|\beval\b|\bbase64\b"
    r"|\bsystemctl\b|\bcrontab\b|\.sh\b|\.py\b"
)

# Long enough to read a command, short enough that one line cannot flood the
# dialog and hide the rest of the findings.
VALUE_PREVIEW_LIMIT = 300

_MISSING = object()


def user_home():
    home = os.environ.get('HOME', '')
    return home[:-1] if home.endswith('/') else home


def plain_path(value):
    """Strip the file:// scheme and any ?query from a path-ish string."""
    if not isinstance(value, str):
        return ''
    path = value.strip()
    if path.startswith('file://'):
        path = path[7:]
    return path.split('?', 1)[0]


def _match_children(node, token):
    """Yield the keys of `node` that one path token selects."""
    if isinstance(node, dict):
        if token == '*':
            for key in list(node.keys()):
                yield key
        elif token in node:
            yield token
    elif isinstance(node, list):
        if token == '*':
            for index in range(len(node)):
                yield index
        elif token.lstrip('-').isdigit() and -len(node) <= int(token) < len(node):
            yield int(token)


def find_paths(data, pattern):
    """Every concrete path in `data` matching a dotted pattern."""
    results = [[]]
    for token in pattern.split('.'):
        matches = []
        for path in results:
            node = get_path(data, path, _MISSING)
            if node is _MISSING:
                continue
            for key in _match_children(node, token):
                matches.append(path + [key])
        results = matches
        if not results:
            break
    return results


def get_path(data, path, default=None):
    node = data
    for key in path:
        if isinstance(node, dict) and key in node:
            node = node[key]
        elif isinstance(node, list) and isinstance(key, int) and -len(node) <= key < len(node):
            node = node[key]
        else:
            return default
    return node


def set_path(data, path, value):
    node = data
    for key in path[:-1]:
        if isinstance(node, list):
            node = node[key]
            continue
        if not isinstance(node.get(key), (dict, list)):
            node[key] = {}
        node = node[key]
    node[path[-1]] = value


def del_path(data, path):
    parent = get_path(data, path[:-1], _MISSING)
    if parent is _MISSING:
        return
    key = path[-1]
    if isinstance(parent, dict):
        parent.pop(key, None)
    elif isinstance(parent, list) and isinstance(key, int) and -len(parent) <= key < len(parent):
        del parent[key]


def strip_paths(data, patterns):
    for pattern in patterns:
        # Deepest first, so deleting a parent never invalidates a pending path.
        for path in sorted(find_paths(data, pattern), key=len, reverse=True):
            del_path(data, path)


def deep_merge(base, overlay):
    """Overlay wins for scalars and lists; dicts merge key by key.

    Merging rather than overwriting is what lets a preset omit the importer's
    API keys, search aliases and dock pins instead of erasing them.
    """
    if not isinstance(base, dict) or not isinstance(overlay, dict):
        return copy.deepcopy(overlay)
    merged = copy.deepcopy(base)
    for key, value in overlay.items():
        merged[key] = deep_merge(merged[key], value) if key in merged else copy.deepcopy(value)
    return merged


def restore_local_only(merged, current):
    """Put the importer's machine-local values back over the preset's."""
    for pattern in LOCAL_ONLY_PATHS:
        strip_paths(merged, (pattern,))
        for path in find_paths(current, pattern):
            set_path(merged, path, copy.deepcopy(get_path(current, path)))


def resolve_asset_paths(merged, current, presets_dir, preset_name):
    """Point each shipped asset field at something that actually exists."""
    finders = {'wallpaper': find_wallpaper_fallback, 'banner': find_banner_fallback}
    for dotted, kind in ASSET_PATHS:
        path = dotted.split('.')
        value = plain_path(get_path(merged, path))
        if value and os.path.exists(value):
            continue
        bundled = None
        if kind and presets_dir and preset_name:
            bundled = finders[kind](presets_dir, preset_name)
        if bundled:
            set_path(merged, path, bundled)
            continue
        local = get_path(current, path)
        if isinstance(local, str) and local:
            set_path(merged, path, local)


def atomic_write_json(path, data):
    """Write via a temp file in the same directory, then rename over the target.

    config.json is watched; a partial read of a half-written file would be
    reported as malformed and block every subsequent save.
    """
    directory = os.path.dirname(os.path.abspath(path)) or '.'
    os.makedirs(directory, exist_ok=True)
    handle, tmp_path = tempfile.mkstemp(dir=directory, prefix='.preset-', suffix='.json')
    try:
        with os.fdopen(handle, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=4)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_path, path)
    except BaseException:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


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

    # Identity and paired hardware never travel with a preset. These are
    # dropped rather than blanked so that applying the preset falls through to
    # whatever the importer already had.
    strip_paths(data, PERSONAL_PATHS)

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

def merge(preset_path, config_path, out_path, presets_dir=None, preset_name=None):
    """Apply a preset onto an existing config without destroying what is local.

    The preset is layered over the current config rather than replacing it, so
    keys a preset legitimately does not carry -- API keys, search aliases, dock
    pins -- survive untouched. Whatever the preset does carry but should not
    (monitor names, save folders, the author's profile card) is handed back
    from the current config afterwards.
    """
    with open(preset_path, 'r', encoding='utf-8') as f:
        preset = json.load(f)
    if not isinstance(preset, dict):
        raise ValueError('preset is not a JSON object')

    current = {}
    if os.path.exists(config_path):
        # A config that no longer parses is the only source of truth for the
        # user's settings, so refuse rather than merge onto an empty dict and
        # silently reset everything the file still held.
        with open(config_path, 'r', encoding='utf-8') as f:
            current = json.load(f)
        if not isinstance(current, dict):
            raise ValueError('existing config is not a JSON object')

    preset = expand_val(preset, user_home())
    merged = deep_merge(current, preset)
    restore_local_only(merged, current)
    resolve_asset_paths(merged, current, presets_dir, preset_name)

    # migrateRaw() in Config.qml only runs when the file still says which
    # version it was written for, so the preset's version has to survive the
    # merge. Stamping the current version here would skip every migration the
    # preset needs and leave retyped keys to be mangled by JsonAdapter.
    if 'configVersion' in preset:
        merged['configVersion'] = preset['configVersion']

    atomic_write_json(out_path, merged)


def _dotted(path):
    return '.'.join(str(key) for key in path)


def _preview(value):
    """One-line, length-capped rendering of a value for the dialog."""
    text = value if isinstance(value, str) else json.dumps(value, sort_keys=True)
    text = ' '.join(text.split())
    if len(text) > VALUE_PREVIEW_LIMIT:
        text = text[:VALUE_PREVIEW_LIMIT - 1] + '\u2026'
    return text


def _is_empty(value):
    """True for values that change nothing worth warning about."""
    return value is None or value is False or (isinstance(value, (str, list, dict)) and not value)


def _changed(merged, current, path):
    return get_path(merged, path, _MISSING) != get_path(current, path, _MISSING)


def _walk_strings(node, path=()):
    if isinstance(node, dict):
        for key, value in node.items():
            for found in _walk_strings(value, path + (key,)):
                yield found
    elif isinstance(node, list):
        for index, value in enumerate(node):
            for found in _walk_strings(value, path + (index,)):
                yield found
    elif isinstance(node, str):
        yield list(path), node


def _shell_action_commands(action):
    """The start/end command pair of one mode or routine action, if it has any."""
    if not isinstance(action, dict) or action.get('type') != 'shell':
        return []
    value = action.get('value')
    pairs = value if isinstance(value, dict) else {'start': value}
    return [(when, pairs.get(when)) for when in ('start', 'end')
            if isinstance(pairs.get(when), str) and pairs.get(when).strip()]


def _existing_shell_commands(current):
    """Every shell command the config already runs, so re-listing one is quiet.

    Matching on the command text rather than the path is what keeps a
    reordered mode list from being reported as a page of new commands.
    """
    commands = set()
    for pattern in MODE_ACTION_PATTERNS:
        for path in find_paths(current, pattern):
            for _, command in _shell_action_commands(get_path(current, path)):
                commands.add(command)
    return commands


def _scan_mode_actions(merged, current, seen):
    known = _existing_shell_commands(current)
    findings = []
    for pattern in MODE_ACTION_PATTERNS:
        for path in find_paths(merged, pattern):
            action = get_path(merged, path)
            owner = get_path(merged, path[:-2], {})
            name = owner.get('name') or owner.get('id') or _dotted(path[:-2])
            # Also claim the bare value path: a shell action may hold its
            # command as a plain string, and the sweep below would then list
            # the same command a second time as an unrecognised one.
            seen.add(tuple(path + ['value']))
            for when, command in _shell_action_commands(action):
                if command in known:
                    continue
                seen.add(tuple(path + ['value', when]))
                findings.append({
                    'category': 'shell',
                    'path': _dotted(path + ['value', when]),
                    'label': '%s (%s)' % (name, 'on start' if when == 'start' else 'on end'),
                    'note': 'Run by a mode or routine, which can start on its own',
                    'value': _preview(command),
                })
    return findings


def scan(preset_path, config_path=None):
    """What applying this preset would let run, reach or unlock.

    Reported against the merged result rather than the preset itself: anything
    merge() hands back from the local config cannot be delivered by a preset,
    so warning about it would be a lie in the one direction that matters.
    """
    with open(preset_path, 'r', encoding='utf-8') as f:
        preset = json.load(f)
    if not isinstance(preset, dict):
        raise ValueError('preset is not a JSON object')

    current = {}
    if config_path and os.path.exists(config_path):
        with open(config_path, 'r', encoding='utf-8') as f:
            loaded = json.load(f)
        if isinstance(loaded, dict):
            current = loaded

    preset = expand_val(preset, user_home())
    merged = deep_merge(current, preset)
    restore_local_only(merged, current)

    seen = set()
    findings = _scan_mode_actions(merged, current, seen)

    for pattern, category, note in RISK_RULES:
        for path in find_paths(merged, pattern):
            if tuple(path) in seen or not _changed(merged, current, path):
                continue
            value = get_path(merged, path)
            if _is_empty(value):
                continue
            seen.add(tuple(path))
            findings.append({
                'category': category,
                'path': _dotted(path),
                'label': _dotted(path),
                'note': note,
                'value': _preview(value),
            })

    # Keys nobody has classified yet. A preset written for a newer build can
    # carry a command in a setting this list has never heard of, so anything
    # that merely reads like a command line is surfaced too.
    for path, value in _walk_strings(preset):
        if tuple(path) in seen or not COMMAND_HINT_RE.search(value):
            continue
        if not _changed(merged, current, path):
            continue
        seen.add(tuple(path))
        findings.append({
            'category': 'unknown',
            'path': _dotted(path),
            'label': _dotted(path),
            'note': 'Unrecognised setting that reads like a command',
            'value': _preview(value),
        })

    groups = []
    for category in RISK_ORDER:
        items = [f for f in findings if f['category'] == category]
        if items:
            groups.append({
                'id': category,
                'severity': SEVERITY[category],
                'count': len(items),
                'items': items,
            })

    return {'ok': True, 'total': len(findings), 'groups': groups}


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
    elif action == 'merge':
        if len(sys.argv) < 5:
            sys.exit(1)
        presets_dir = sys.argv[5] if len(sys.argv) > 5 else None
        preset_name = sys.argv[6] if len(sys.argv) > 6 else None
        try:
            merge(sys.argv[2], sys.argv[3], sys.argv[4], presets_dir, preset_name)
        except Exception as exc:
            print(f'merge failed: {exc}', file=sys.stderr)
            sys.exit(1)
    elif action == 'scan':
        if len(sys.argv) < 3:
            sys.exit(1)
        config_path = sys.argv[3] if len(sys.argv) > 3 else None
        # Always one JSON line, failure included: the dialog that reads this
        # has to be able to say why it could not vouch for a preset.
        try:
            print(json.dumps(scan(sys.argv[2], config_path)))
        except Exception as exc:
            print(json.dumps({'ok': False, 'error': str(exc)}))
            sys.exit(1)
    elif action == 'list':
        if len(sys.argv) < 3:
            sys.exit(1)
        list_presets(sys.argv[2])
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
