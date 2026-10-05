#!/usr/bin/env python3
import copy
import json
import os
import sys
import glob
import re
import shutil
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
    "enableTasksWidget",
    "enableWidgetStack",
    "widgetStackItems",
    "utilityWidgets",
    "utilities",
    "livePreviewSlots",
    "livePreviewPaintCursor",
    "livePreviewCaptureMode",
    "livePreviewFollowActiveWindow",
    "showPhoneButton",
    "showTrashButton",
    "showOverviewButton",
    "showPinButton",
    "switchPresetsOnScroll",
}

SEARCH_APPEARANCE_KEYS = {
    "positionStyle",
    "centerVerticalRatio",
    "bestMatch",
    "baseWidth",
    "baseHeight",
    "connectStyle",
    "appearance",
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
    # background.monitorWallpapers is machine-local too, but a preset does
    # carry it: portable_monitor_wallpapers() on save, apply_monitor_wallpapers()
    # on apply, which maps it onto the importer's screens.
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
    # Dock utility widgets: the LocalSend target, folders and favorite sites.
    "dock.utilities.send.localsendIp",
    "dock.utilities.send.localsendAlias",
    "dock.utilities.send.kdeDevice",
    "dock.utilities.files.folder",
    "dock.utilities.screenshots.folder",
    "dock.utilities.favorites.sites",
    "soundcore.macAddress",
    "phone.contacts.favoriteIds",
    "phone.microphone.wifiIp",
    "phone.scrcpy.wirelessIp",
    "phone.webcam.wifiIp",
    "sidebar.booru.zerochan.username",
    # The libinput id of a touchpad that exists on one laptop. Machine-local
    # in the same way a monitor name is, and applying it silently stops touch
    # gestures working on everyone else's.
    "interactions.touchGestures.deviceId",
    "todo",
    "googleDrive",
    "cheatsheet",
    "tailscale.exitNode",
    "tailscale.advertiseRoutes",
    "vpn.defaultProfile",
    "vpn.defaultLocation",
    "vpn.recentProvider",
    "bar.weather.city",
    "bar.weather.enableGPS",
    "update.lastAutoCheck",
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
SEARCH_LOCAL_PREFERENCE_PATHS = (
    "search.modules",
    "search.frecency",
    "search.frecencyData",
    "search.sectionOrder",
    "search.aliases",
    "search.prefix",
    "search.keybindings",
    "search.typingTest",
    "search.fileSearch",
    "search.fileSearchDirectory",
    "search.browserSites",
    "search.typoTolerance",
    "search.suggestions",
    "search.enableSystemControls",
    "search.enableMathPreview",
    "search.showSettings",
    "search.alwaysListApps",
    "search.nonAppResultDelay",
    "search.sloppy",
    "search.levenshtein",
    "search.fuzzyThreshold",
    "search.fuzzyRelativeCutoff",
    "search.blurFileSearchResultPreviews",
    "search.fileBrowser",
    "search.ai",
    "search.favorites",
    "search.fallbacks",
    "search.history",
    "search.clipboard",
    "search.nowPlaying",
    "search.showNowPlayingBubble",
    "search.imageSearch.useCircleSelection",
    "search.excludedSites",
)

LOCAL_PREFERENCE_PATHS = (
    "appearance.iconTheme",
    "appearance.icons.enableThemed",
    "language",
    "bar.weather.useUSCS",
    "policies",
    "workSafety",
    # What each touchpad swipe does is a habit of the hand, and a list written for
    # another laptop's touchpad. A theme that rebinds it is a theme nobody can use.
    "interactions.touchpadGestures",
) + SEARCH_LOCAL_PREFERENCE_PATHS

# Everything merge() hands back to the importer.
LOCAL_ONLY_PATHS = (
    MONITOR_BINDING_PATHS + PERSONAL_PATHS + LOCAL_FOLDER_PATHS + LOCAL_PREFERENCE_PATHS
)
# The shell keeps a durable mirror of every path here (plus the dock/search
# keys above and the blacklisted root sections) in
# ~/.config/illogical-impulse/local-preferences.json, so deleting config.json
# no longer takes them with it. Written by modules/common/LocalPreferences.qml
# — keep the protected-path list there in sync with the lists above. The file
# is a plain { "<concrete dotted path>": value } map.
LOCAL_PREFERENCES_NAME = "local-preferences.json"

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


# ---------------------------------------------------------------------------
# Schema compatibility
#
# "Migrate up, block newer". Config.qml carries every older schema forward on
# its own, so an old preset is safe. A preset written against a newer schema
# is not: it holds keys and shapes this build has never heard of, and
# JsonAdapter coerces those into whatever the local type happens to be without
# ever saying so.
# ---------------------------------------------------------------------------

def current_config_version():
    """The schema version this build understands, read from Config.qml."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    qml = os.path.join(root, 'modules', 'common', 'Config.qml')
    try:
        with open(qml, 'r', encoding='utf-8') as handle:
            match = re.search(r'currentConfigVersion\s*:\s*(\d+)', handle.read())
        if match:
            return int(match.group(1))
    except Exception:
        pass
    # Config.qml moved or could not be read. The live config was written by
    # this build, so its own version is the next best answer.
    try:
        path = os.path.join(user_home(), '.config', 'illogical-impulse', 'config.json')
        with open(path, 'r', encoding='utf-8') as handle:
            value = json.load(handle).get('configVersion')
        if isinstance(value, int) and not isinstance(value, bool):
            return value
    except Exception:
        pass
    return None


def compatibility(preset_version):
    """Say whether a preset can be applied, and why not when it cannot."""
    ours = current_config_version()
    known = isinstance(preset_version, int) and not isinstance(preset_version, bool)
    if ours is None or not known:
        # Nothing to compare. A preset from before versioning existed reads
        # as unknown rather than old, and refusing those would lock out every
        # preset exported before the store was built.
        return {'ok': True, 'status': 'unknown', 'ours': ours, 'theirs': preset_version}
    if preset_version > ours:
        return {
            'ok': False,
            'status': 'too-new',
            'ours': ours,
            'theirs': preset_version,
            'reason': 'This preset was made for a newer version of the shell. Update first.',
        }
    if preset_version < ours:
        return {'ok': True, 'status': 'migrate', 'ours': ours, 'theirs': preset_version}
    return {'ok': True, 'status': 'current', 'ours': ours, 'theirs': preset_version}


def preset_config_version(preset_path):
    """The schema version a preset file was written against, or None."""
    try:
        with open(preset_path, 'r', encoding='utf-8') as handle:
            value = json.load(handle).get('configVersion')
    except Exception:
        return None
    return value if isinstance(value, int) and not isinstance(value, bool) else None


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


def local_preferences_path(config_path):
    return os.path.join(os.path.dirname(os.path.abspath(config_path)), LOCAL_PREFERENCES_NAME)


def load_local_preferences(config_path):
    """The importer's durable protected settings, or {} if there is none."""
    try:
        with open(local_preferences_path(config_path), 'r', encoding='utf-8') as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def restore_local_preferences(merged, local):
    """Fill machine-local paths the merged config lost entirely.

    restore_local_only() hands back whatever the current config.json still
    holds; when that file was just deleted there is nothing to hand back and
    the preset's own (or absent) values would win. The durable mirror has
    them, so consult it for any protected path still missing after the
    merge. Values already in the merged config are never overwritten.
    """
    for dotted, value in local.items():
        if not isinstance(dotted, str) or not dotted:
            continue
        path = dotted.split('.')
        if get_path(merged, path, _MISSING) is _MISSING:
            set_path(merged, path, copy.deepcopy(value))


def resolve_asset_paths(merged, current, presets_dir, preset_name):
    """Point each shipped asset field at the copy that ships with the preset.

    A bundled `{name}_banner.*` (or `{name}.<ext>` wallpaper) is the exact
    image the author exported, so it replaces whatever path the preset
    carries even when that path happens to exist on the importer's disk --
    applying a preset means swapping in its banner, not colliding with a
    same-named local file. With no bundled copy, a preset path that exists
    stays; a dead path falls back to the importer's own.
    """
    finders = {'wallpaper': find_wallpaper_fallback, 'banner': find_banner_fallback}
    for dotted, kind in ASSET_PATHS:
        path = dotted.split('.')
        bundled = None
        if kind and presets_dir and preset_name:
            bundled = finders[kind](presets_dir, preset_name)
        if bundled:
            set_path(merged, path, bundled)
            continue
        value = plain_path(get_path(merged, path, ''))
        if value and os.path.exists(value):
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


ROOT_PRESET_BLACKLIST_KEYS = {
    "googleDrive",
    "todo",
    "ai",
    "cheatsheet",
}

def remove_secrets_and_userdata(data, is_root=True):
    if isinstance(data, dict):
        cleaned = {}
        for k, v in data.items():
            if is_root and k in ROOT_PRESET_BLACKLIST_KEYS:
                continue
            if not is_root and k == 'googleDrive':
                continue
            if is_sensitive_key(k):
                continue
            if k == 'search' and isinstance(v, dict):
                search_copy = {}
                for sk, sv in v.items():
                    if sk not in SEARCH_APPEARANCE_KEYS:
                        continue
                    if is_sensitive_key(sk):
                        continue
                    search_copy[sk] = remove_secrets_and_userdata(sv, is_root=False)
                if search_copy:
                    cleaned[k] = search_copy
                continue
            if k == 'dock' and isinstance(v, dict):
                dock_copy = {}
                for dk, dv in v.items():
                    if dk in DOCK_BLACKLIST_KEYS or is_sensitive_key(dk):
                        continue
                    dock_copy[dk] = remove_secrets_and_userdata(dv, is_root=False)
                if dock_copy:
                    cleaned[k] = dock_copy
                continue
            child = remove_secrets_and_userdata(v, is_root=False)
            # A container emptied by the stripping goes with it: leaving a
            # `services: {gmail: {}}` husk behind would still write it into
            # every config the preset is applied to. Objects the author
            # genuinely left empty are kept untouched.
            if isinstance(child, dict) and not child and v:
                continue
            cleaned[k] = child
        return cleaned
    elif isinstance(data, list):
        return [remove_secrets_and_userdata(x, is_root=False) for x in data]
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

# ---------------------------------------------------------------------------
# Video wallpapers and per-screen wallpapers
# ---------------------------------------------------------------------------

# Wallpapers.videoExtensions; switchwall.sh plays the same set.
VIDEO_EXTS = ('.mp4', '.mkv', '.webm', '.avi', '.mov', '.m4v', '.ogv')
# Edit Mode's per-screen wallpapers ship next to the preset as
# `{name}_screen<N>.<ext>`; an entry names its file by this id.
SCREEN_ASSET_RE = re.compile(r'^screen[0-9]+$')
# WallpaperLayout.framingMemory.
FRAMING_MEMORY = 12


def is_video(path):
    return isinstance(path, str) and os.path.splitext(plain_path(path))[1].lower() in VIDEO_EXTS


def poster_cache_dir():
    base = os.environ.get('XDG_CACHE_HOME') or os.path.join(user_home(), '.cache')
    return os.path.join(base, 'quickshell-ii', 'preset-posters')


def video_frame_seconds(data, paths):
    """The moment the author picked for a video's colours (and its poster)."""
    background = data.get('background') if isinstance(data, dict) else None
    times = background.get('videoFrameTimes') if isinstance(background, dict) else None
    wanted = {plain_path(p) for p in paths if p}
    for item in times if isinstance(times, list) else []:
        if isinstance(item, dict) and plain_path(item.get('path', '')) in wanted:
            seconds = item.get('seconds')
            if isinstance(seconds, (int, float)) and not isinstance(seconds, bool) and seconds > 0:
                return float(seconds)
    return 0.0


def video_poster(video, seconds=0.0):
    """A still of `video` an Image can show, cached by file and moment.

    Qt's Image cannot decode a video, so every preset card showed nothing for
    a video wallpaper. "" when ffmpeg is missing or the file is unreadable.
    """
    import hashlib
    import subprocess
    try:
        stat = os.stat(video)
    except OSError:
        return ''
    key = hashlib.sha256(('%s\0%d\0%d\0%s' % (
        os.path.abspath(video), stat.st_size, int(stat.st_mtime), seconds)).encode()).hexdigest()[:24]
    directory = poster_cache_dir()
    poster = os.path.join(directory, key + '.jpg')
    if os.path.isfile(poster) and os.path.getsize(poster) > 0:
        return poster
    try:
        os.makedirs(directory, exist_ok=True)
    except OSError:
        return ''
    handle, partial = tempfile.mkstemp(dir=directory, prefix='.poster-', suffix='.jpg')
    os.close(handle)
    try:
        for at in ([seconds, 0] if seconds > 0 else [0]):
            try:
                subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', str(at), '-i', video,
                                '-frames:v', '1', '-vf', "scale='min(1280,iw)':-2", partial],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=20, check=False)
            except (OSError, subprocess.SubprocessError):
                return ''
            if os.path.getsize(partial) > 0:
                os.replace(partial, poster)
                return poster
        return ''
    finally:
        if os.path.exists(partial):
            os.unlink(partial)


def screen_key(model, serial):
    model = str(model or '').strip()
    serial = str(serial or '').strip()
    return '' if not model and not serial else '%s/%s' % (model, serial)


def list_monitors():
    """Connected monitors left to right, keyed like WallpaperLayout.screenKeys.

    [] when Hyprland cannot be asked (tests, a TTY); callers then keep the
    connector names the preset carries.
    """
    try:
        import subprocess
        out = subprocess.check_output(['hyprctl', 'monitors', '-j'], timeout=2, stderr=subprocess.DEVNULL)
        monitors = json.loads(out.decode('utf-8'))
    except Exception:
        return []
    if not isinstance(monitors, list):
        return []
    rows = [m for m in monitors if isinstance(m, dict) and isinstance(m.get('name'), str) and m['name']]
    rows.sort(key=lambda m: (m.get('x', 0) if isinstance(m.get('x'), (int, float)) else 0,
                             m.get('y', 0) if isinstance(m.get('y'), (int, float)) else 0))
    keys = [screen_key(m.get('model'), m.get('serial')) for m in rows]
    # Twin monitors without serials cannot be told apart: connector only.
    return [{'name': m['name'], 'key': key if key and keys.count(key) == 1 else ''}
            for m, key in zip(rows, keys)]


def portable_monitor_wallpapers(data, live=False, keep_keys=True):
    """Make Edit Mode's per-screen wallpapers something a preset can carry.

    Each picture a screen shows of its own gets an asset id (`screen0`, ...)
    that names the copy bundled next to the preset, and its framings say
    which picture they belong to (`wallpaper` = the shared one) instead of a
    path on the author's disk. `screen` is the screen's place from the left,
    the fallback when the importer's connectors are named differently.
    Framings of pictures the preset does not ship are only history and drop.
    """
    background = data.get('background') if isinstance(data, dict) else None
    if not isinstance(background, dict) or 'monitorWallpapers' not in background:
        return
    entries = background.get('monitorWallpapers')
    if not isinstance(entries, list):
        background['monitorWallpapers'] = []
        return
    shared = plain_path(background.get('wallpaperPath', ''))
    order = {m['name']: i for i, m in enumerate(list_monitors())} if live else {}
    assets = {}
    portable = []
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get('monitor'), str) or not entry['monitor']:
            continue
        item = {'monitor': entry['monitor']}
        key = entry.get('key')
        if keep_keys and isinstance(key, str) and key:
            item['key'] = key
        screen = entry.get('screen')
        if not isinstance(screen, int) or isinstance(screen, bool):
            screen = None
        screen = order.get(entry['monitor'], screen) if live else (screen if screen is not None
                                                                   else order.get(entry['monitor']))
        if screen is not None:
            item['screen'] = screen
        own = plain_path(entry.get('path', ''))
        item['path'] = own
        if own:
            if own not in assets:
                assets[own] = 'screen%d' % len(assets)
            item['asset'] = assets[own]
        framings = []
        for framing in entry.get('framings') or []:
            if not isinstance(framing, dict):
                continue
            path = plain_path(framing.get('path', ''))
            if own and path == own:
                asset = item['asset']
            elif shared and path == shared:
                asset = 'wallpaper'
            else:
                continue
            framings.append(dict(framing, path=path, asset=asset))
        item['framings'] = framings
        if own or framings:
            portable.append(item)
    background['monitorWallpapers'] = portable


def screen_asset_files(presets_dir, preset_name):
    """{asset id: file} for the per-screen wallpapers bundled with a preset."""
    found = {}
    prefix = '%s_' % preset_name
    for filepath in glob.glob(os.path.join(glob.escape(presets_dir), glob.escape(prefix) + 'screen*.*')):
        stem, ext = os.path.splitext(os.path.basename(filepath)[len(prefix):])
        if SCREEN_ASSET_RE.match(stem) and ext.lower() not in ('.json', '.zip'):
            found[stem] = filepath
    return found


def bundle_screens(preset_path, presets_dir, preset_name):
    """Copy every per-screen wallpaper a preset names next to it.

    The sources are read before anything is removed: a preset re-saved after
    being applied points straight at its own `{name}_screen<N>` copies, and
    those may swap numbers.
    """
    with open(preset_path, 'r', encoding='utf-8') as f:
        preset = json.load(f)
    background = preset.get('background') if isinstance(preset, dict) else None
    entries = background.get('monitorWallpapers') if isinstance(background, dict) else None
    wanted = {}
    for entry in entries if isinstance(entries, list) else []:
        if not isinstance(entry, dict):
            continue
        asset = entry.get('asset')
        source = plain_path(expand_val(entry.get('path', ''), user_home()))
        if isinstance(asset, str) and SCREEN_ASSET_RE.match(asset) and source and os.path.isfile(source):
            wanted.setdefault(asset, source)
    with tempfile.TemporaryDirectory(dir=presets_dir, prefix='.screens-') as staging:
        staged = {}
        for asset, source in wanted.items():
            target = os.path.join(staging, asset + os.path.splitext(source)[1].lower())
            shutil.copy2(source, target)
            staged[asset] = target
        for old in screen_asset_files(presets_dir, preset_name).values():
            os.remove(old)
        for asset, target in staged.items():
            os.replace(target, os.path.join(presets_dir, '%s_%s' % (preset_name, os.path.basename(target))))


def apply_monitor_wallpapers(merged, preset, current, presets_dir=None, preset_name=None):
    """Hand the preset's per-screen wallpapers to the importer's screens.

    `monitorWallpapers` is machine-local and comes back from the current
    config first; this then decides what each screen shows. Every screen
    starts on the preset's shared wallpaper (a look is not applied while
    one monitor keeps the old picture); a screen the preset gives its own
    wallpaper is matched by monitor, then connector, then place from the
    left. The importer's framings of other pictures are kept.
    """
    background = merged.get('background')
    if not isinstance(background, dict):
        return
    current_bg = current.get('background') if isinstance(current, dict) else None
    existing = current_bg.get('monitorWallpapers') if isinstance(current_bg, dict) else None
    result = []
    for entry in existing if isinstance(existing, list) else []:
        if isinstance(entry, dict) and isinstance(entry.get('monitor'), str) and entry['monitor']:
            item = {k: copy.deepcopy(v) for k, v in entry.items() if k not in ('asset', 'screen')}
            item['path'] = ''
            item['framings'] = [f for f in item.get('framings') or [] if isinstance(f, dict)]
            result.append(item)

    preset_bg = preset.get('background') if isinstance(preset, dict) else None
    incoming = preset_bg.get('monitorWallpapers') if isinstance(preset_bg, dict) else None
    incoming = [e for e in incoming if isinstance(e, dict) and isinstance(e.get('monitor'), str)
                and e['monitor']] if isinstance(incoming, list) else []
    files = screen_asset_files(presets_dir, preset_name) if presets_dir and preset_name else {}
    shared = plain_path(background.get('wallpaperPath', ''))

    def resolve(asset, path):
        if asset == 'wallpaper':
            return shared
        if isinstance(asset, str) and asset in files:
            return files[asset]
        path = plain_path(path)
        return path if path and os.path.isfile(path) else ''

    monitors = list_monitors() if incoming else []
    used = set()

    def target_for(entry):
        free = [m for m in monitors if m['name'] not in used]
        key = entry.get('key') if isinstance(entry.get('key'), str) else ''
        hit = next((m for m in free if key and m['key'] == key), None)
        hit = hit or next((m for m in free if m['name'] == entry['monitor']), None)
        screen = entry.get('screen')
        if not hit and isinstance(screen, int) and not isinstance(screen, bool) and 0 <= screen < len(monitors):
            hit = monitors[screen] if monitors[screen]['name'] not in used else None
        if not hit and not monitors:
            hit = {'name': entry['monitor'], 'key': key}
        return hit

    for entry in incoming:
        target = target_for(entry)
        if not target:
            continue
        used.add(target['name'])
        own = resolve(entry.get('asset'), entry.get('path', '')) if entry.get('path') or entry.get('asset') else ''
        if own == shared:
            own = ''
        framings = []
        for framing in entry.get('framings') or []:
            if not isinstance(framing, dict):
                continue
            path = resolve(framing.get('asset'), framing.get('path', ''))
            if path:
                framings.append({k: v for k, v in dict(framing, path=path).items() if k != 'asset'})
        key = target.get('key') or ''
        slot = next((e for e in result if key and e.get('key') == key), None) or next(
            (e for e in result if e['monitor'] == target['name'] and (not e.get('key') or not key)), None)
        if slot is None:
            slot = {'monitor': target['name'], 'key': key, 'path': '', 'framings': []}
            result.append(slot)
        slot['monitor'] = target['name']
        if key:
            slot['key'] = key
        slot['path'] = own
        paths = {f['path'] for f in framings}
        slot['framings'] = (framings + [f for f in slot['framings']
                                        if plain_path(f.get('path', '')) not in paths])[:FRAMING_MEMORY]

    # WallpaperLayout keeps no empty entries.
    background['monitorWallpapers'] = [e for e in result if e.get('path') or e.get('framings')]


def carry_video_frame_time(merged, preset, current):
    """Keep the author's colour frame when the video is now the bundled copy.

    videoFrameTimes is keyed by path, and applying points wallpaperPath at
    `{name}.<ext>` in the presets folder, so the author's pick (and with it the
    palette and poster) was lost. The importer's own picks for other videos
    stay.
    """
    background = merged.get('background')
    if not isinstance(background, dict):
        return
    resolved = background.get('wallpaperPath', '')
    preset_bg = preset.get('background') if isinstance(preset.get('background'), dict) else {}
    current_bg = current.get('background') if isinstance(current.get('background'), dict) else {}
    original = preset_bg.get('wallpaperPath', '')
    times = [t for t in current_bg.get('videoFrameTimes') or [] if isinstance(t, dict)]
    if not is_video(resolved):
        background['videoFrameTimes'] = times
        return
    seconds = video_frame_seconds(preset, [original, resolved])
    times = [t for t in times if plain_path(t.get('path', '')) != plain_path(resolved)]
    if seconds > 0:
        times.append({'path': plain_path(resolved), 'seconds': seconds})
    background['videoFrameTimes'] = times


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

def detect_display_resolution():
    try:
        import subprocess
        out = subprocess.check_output(['hyprctl', 'monitors', '-j'], timeout=1, stderr=subprocess.DEVNULL)
        monitors = json.loads(out.decode('utf-8'))
        if isinstance(monitors, list) and monitors:
            focused = next((m for m in monitors if m.get('focused')), monitors[0])
            w = focused.get('width')
            h = focused.get('height')
            if isinstance(w, (int, float)) and isinstance(h, (int, float)) and w > 0 and h > 0:
                return {'width': int(w), 'height': int(h)}
    except Exception:
        pass
    return {'width': 1920, 'height': 1080}

def normalize_active_widgets(data):
    background = data.get('background')
    if not isinstance(background, dict):
        return
    active_widgets = background.get('activeWidgets')
    if not isinstance(active_widgets, list):
        return

    for entry in active_widgets:
        if not isinstance(entry, dict):
            continue
        positions = entry.get('positions')
        if isinstance(positions, dict) and positions:
            first_key = next(iter(positions))
            forked = positions[first_key]
            if isinstance(forked, dict):
                if 'x' in forked:
                    entry['x'] = forked['x']
                if 'y' in forked:
                    entry['y'] = forked['y']
                if 'scale' in forked:
                    entry['scale'] = forked['scale']

        lock_positions = entry.get('lockPositions')
        if isinstance(lock_positions, dict) and lock_positions:
            first_key = next(iter(lock_positions))
            forked_lock = lock_positions[first_key]
            if isinstance(forked_lock, dict):
                if 'lockX' in forked_lock:
                    entry['lockX'] = forked_lock['lockX']
                if 'lockY' in forked_lock:
                    entry['lockY'] = forked_lock['lockY']

def sanitize_data(data, home_dir, snapshot=False):
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
    # Per-screen wallpapers travel, matched to the importer's screens on
    # apply. A monitor's model/serial stays on the author's machine.
    portable_monitor_wallpapers(data, live=snapshot, keep_keys=snapshot)
    # Where switchwall put this machine's screen-sized copy of the video.
    background = data.get('background')
    if isinstance(background, dict):
        background.pop('videoPlaybackSource', None)
        background.pop('videoPlaybackPath', None)

    if 'background' in data and isinstance(data['background'], dict):
        if 'referenceResolution' not in data['background']:
            data['background']['referenceResolution'] = detect_display_resolution()
        normalize_active_widgets(data)

    return data

def clamp_config_version(data):
    """Cap a snapshot's schema version at the one this build understands.

    config.json keeps whatever version last wrote it, and Config.qml never
    migrates down: after running a build with a newer schema and going back,
    the file still claims the newer one. A preset saved from it is shaped by
    this build, so stamping it newer would have this very shell refuse it.
    """
    ours = current_config_version()
    version = data.get('configVersion')
    if not isinstance(ours, int) or not isinstance(version, int) or isinstance(version, bool):
        return data
    if version > ours:
        data['configVersion'] = ours
    return data

def sanitize(input_path, output_path, snapshot=False):
    with open(input_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    home_dir = os.environ.get('HOME', '')
    if home_dir.endswith('/'):
        home_dir = home_dir[:-1]

    data = sanitize_data(data, home_dir, snapshot=snapshot)
    # Only a snapshot of the running config is clamped. An imported preset
    # keeps the version its author's shell gave it, so a newer one is still
    # refused.
    if snapshot:
        data = clamp_config_version(data)

    # Written through a temp file: the presets list is re-read right after a
    # save, and a half-written preset reads as malformed and drops out of the
    # grid until the next refresh.
    atomic_write_json(output_path, data)

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
    # The same pass a preset goes through on its way out, run on its way in.
    # Presets written by this build are already clean, so this is a no-op for
    # them; it is the hand-edited and pre-blacklist files that need it, and
    # an apply is the last moment anything can still be dropped silently.
    preset = remove_secrets_and_userdata(preset)
    merged = deep_merge(current, preset)
    restore_local_only(merged, current)
    restore_local_preferences(merged, load_local_preferences(config_path))
    resolve_asset_paths(merged, current, presets_dir, preset_name)
    apply_monitor_wallpapers(merged, preset, current, presets_dir, preset_name)
    carry_video_frame_time(merged, preset, current)
    # A screen-sized copy of the importer's previous video, not of this one;
    # switchwall publishes the right one when it switches.
    if isinstance(merged.get('background'), dict) and isinstance(current.get('background'), dict):
        for key in ('videoPlaybackSource', 'videoPlaybackPath'):
            if key in current['background']:
                merged['background'][key] = current['background'][key]
            else:
                merged['background'].pop(key, None)

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

    verdict = compatibility(preset.get('configVersion'))
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

    return {'ok': True, 'total': len(findings), 'groups': groups, 'compatibility': verdict}


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
                
        original = wall_path
        if not wall_path or not os.path.exists(wall_path):
            fallback = find_wallpaper_fallback(presets_dir, preset_name)
            wall_path = fallback if fallback else ''

        # The cards are Images: a video wallpaper shows its poster, taken at
        # the moment the author picked for the colours.
        video = is_video(wall_path)
        if video:
            wall_path = video_poster(wall_path, video_frame_seconds(data, [original, wall_path]))
        screens = bg.get('monitorWallpapers') if isinstance(bg, dict) else None
        screens = len([e for e in screens if isinstance(e, dict) and e.get('asset')]) \
            if isinstance(screens, list) else 0

        # 0, never null: a ListModel fixes its roles on the first row, and a
        # null there would type the role as something no other row fits.
        version = data.get('configVersion')
        if not isinstance(version, int) or isinstance(version, bool):
            version = 0
        print(json.dumps({"name": preset_name, "wallpaper": wall_path,
                          "configVersion": version, "video": video,
                          "screenWallpapers": screens}))

def main():
    if len(sys.argv) < 2:
        sys.exit(1)
        
    action = sys.argv[1]
    if action == 'sanitize':
        if len(sys.argv) < 4:
            sys.exit(1)
        sanitize(sys.argv[2], sys.argv[3])
    elif action == 'snapshot':
        if len(sys.argv) < 4:
            sys.exit(1)
        sanitize(sys.argv[2], sys.argv[3], snapshot=True)
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
    elif action == 'compat':
        if len(sys.argv) < 3:
            sys.exit(1)
        print(json.dumps(compatibility(preset_config_version(sys.argv[2]))))
    elif action == 'bundle-screens':
        if len(sys.argv) < 5:
            sys.exit(1)
        bundle_screens(sys.argv[2], sys.argv[3], sys.argv[4])
    elif action == 'list':
        if len(sys.argv) < 3:
            sys.exit(1)
        list_presets(sys.argv[2])
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
