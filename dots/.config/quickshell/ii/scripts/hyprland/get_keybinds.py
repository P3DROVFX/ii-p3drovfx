#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys

parser = argparse.ArgumentParser(description='Hyprland keybind reader')
parser.add_argument('--path', type=str, default=None, action='append',
                    help='path to keybind file (repeatable; uses hyprctl if not specified)')
parser.add_argument('--flat', action='store_true',
                    help='emit one entry per bind with file, line, options and managed flag')
args = parser.parse_args()


class KeyBinding(dict):
    def __init__(self, mods, key, dispatcher, params, comment):
        self["mods"] = mods
        self["key"] = key
        self["dispatcher"] = dispatcher
        self["params"] = params
        self["comment"] = comment


class Unbinding(dict):
    def __init__(self, mods, key, comment):
        self["mods"] = mods
        self["key"] = key
        self["comment"] = comment


class Section(dict):
    def __init__(self, children, keybinds, unbinds, name):
        self["children"] = children
        self["keybinds"] = keybinds
        self["unbinds"] = unbinds
        self["name"] = name


# X11 modifier masks, which is what Hyprland reports. ALT and CTRL used to be the wrong way
# round here, so every bind the hyprctl fallback produced named the wrong modifier.
MODMASKS = {
    1: "SHIFT",
    2: "CAPS",
    4: "CTRL",
    8: "ALT",
    16: "MOD2",
    32: "MOD3",
    64: "SUPER",
    128: "MOD5",
}


def decode_modmask(mask):
    parts = []
    for val, name in sorted(MODMASKS.items()):
        if mask & val:
            parts.append(name)
    return parts


def autogenerate_comment(dispatcher, params=""):
    match dispatcher:
        case "resizewindow":
            return "Resize window"
        case "movewindow":
            if params == "":
                return "Move window"
            return "Window: move in {} direction".format({
                "l": "left", "r": "right", "u": "up", "d": "down",
            }.get(params, "null"))
        case "pin":
            return "Window: pin (show on all workspaces)"
        case "splitratio":
            return "Window split ratio {}".format(params)
        case "togglefloating":
            return "Float/unfloat window"
        case "resizeactive":
            return "Resize window by {}".format(params)
        case "killactive":
            return "Close window"
        case "fullscreen":
            return "Toggle {}".format({"0": "fullscreen", "1": "maximization", "2": "fullscreen on Hyprland's side"}.get(params, "null"))
        case "fakefullscreen":
            return "Toggle fake fullscreen"
        case "workspace":
            if params == "+1":
                return "Workspace: focus right"
            elif params == "-1":
                return "Workspace: focus left"
            return "Focus workspace {}".format(params)
        case "movefocus":
            return "Window: move focus {}".format({"l": "left", "r": "right", "u": "up", "d": "down"}.get(params, "null"))
        case "swapwindow":
            return "Window: swap in {} direction".format({"l": "left", "r": "right", "u": "up", "d": "down"}.get(params, "null"))
        case "movetoworkspace":
            if params == "+1":
                return "Window: move to right workspace (non-silent)"
            elif params == "-1":
                return "Window: move to left workspace (non-silent)"
            return "Window: move to workspace {} (non-silent)".format(params)
        case "movetoworkspacesilent":
            if params == "+1":
                return "Window: move to right workspace"
            elif params == "-1":
                return "Window: move to left workspace"
            return "Window: move to workspace {}".format(params)
        case "togglespecialworkspace":
            return "Workspace: toggle special"
        case "exec":
            return "Execute: {}".format(params)
        case _:
            return ""


# ─── Lua parser ──────────────────────────────────────────────────────────────

LUA_BIND_RE = re.compile(r'hl\.bind\s*\(([^)]*)\)\s*', re.DOTALL)
LUA_FIRST_ARG_RE = re.compile(r'"([^"]+)"')
LUA_DESC_RE = re.compile(r'description\s*=\s*"([^"]*)"')
LUA_SECTION_RE = re.compile(r'^--##!\s+(.+)$')
LUA_COMMENT_BIND_PATTERN = re.compile(r'^--?#/#\s+(bind|unbind)\w*\s*=')
LUA_DISPATCH_RE = re.compile(
    r'hl\.dsp\.(?P<dispatcher>global|exec_cmd)\s*\(\s*"(?P<params>(?:\\.|[^"\\])*)"\s*\)',
    re.DOTALL,
)


def parse_lua_binds(path):
    with open(os.path.expanduser(os.path.expandvars(path)), 'r') as f:
        content = f.read()

    root = Section([], [], [], "")
    stack = [(root, 0)]
    current = root

    lines = content.split('\n')
    i = 0
    while i < len(lines):
        raw = lines[i]

        # Section header
        m = re.match(LUA_SECTION_RE, raw)
        if m:
            scope = 2
            name = m.group(1).strip()
            while stack and stack[-1][1] >= scope:
                stack.pop()
            new_section = Section([], [], [], name)
            stack[-1][0]["children"].append(new_section)
            stack.append((new_section, scope))
            current = new_section
            i += 1
            continue

        # hl.bind call - may span multiple lines
        stripped = raw.strip()
        if stripped.startswith('hl.bind('):
            bind_src = stripped
            # collect continuation lines until matching closing paren
            depth = stripped.count('(') - stripped.count(')')
            i += 1
            while depth > 0 and i < len(lines):
                line = lines[i]
                bind_src += '\n' + line
                depth += line.count('(') - line.count(')')
                i += 1
            process_lua_bind(bind_src, current)
            continue

        # hl.unbind
        if stripped.startswith('hl.unbind('):
            bind_src = stripped
            depth = stripped.count('(') - stripped.count(')')
            i += 1
            while depth > 0 and i < len(lines):
                line = lines[i]
                bind_src += '\n' + line
                depth += line.count('(') - line.count(')')
                i += 1
            process_lua_bind(bind_src, current, is_unbind=True)
            continue

        # Cheatsheet-only documentation binds (not registered with Hyprland)
        # e.g. `--#/# bind = SUPER+SHIFT, ↑/↓/←/→,, # Move workspace to monitor`
        if re.match(LUA_COMMENT_BIND_PATTERN, stripped):
            # Strip leading `--` so conf-style parsing sees `#/# bind = ...`
            lines[i] = stripped[2:].lstrip() if stripped.startswith("--") else stripped
            keybind = get_keybind_at_line(i, lines)
            if isinstance(keybind, KeyBinding):
                current["keybinds"].append(keybind)
            elif isinstance(keybind, Unbinding):
                current["unbinds"].append(keybind)
            i += 1
            continue

        i += 1

    # Wrap orphan root keybinds/unbinds into an implicit section so QML
    # (which walks .children) can discover them.
    if (root.get("keybinds") and len(root["keybinds"]) > 0) or \
       (root.get("unbinds") and len(root["unbinds"]) > 0):
        implicit = Section(
            [],
            list(root.get("keybinds") or []),
            list(root.get("unbinds") or []),
            "Keybinds",
        )
        root["children"].insert(0, implicit)
        root["keybinds"] = []
        root["unbinds"] = []

    # Nest each section's direct keybinds into a synthetic child sub-section
    # so the QML parseKeymaps function sees child.children with keybind data.
    # Unbinds stay on the section itself — parseUnbinds walks all nodes.
    for section in root["children"]:
        if section.get("keybinds") and len(section["keybinds"]) > 0:
            sub = Section([], list(section["keybinds"]), [], section.get("name", ""))
            section["children"].append(sub)
            section["keybinds"] = []

    return root


def process_lua_bind(bind_src, current, is_unbind=False):
    # Extract the first string argument: mods + key
    m = LUA_FIRST_ARG_RE.search(bind_src)
    if not m:
        return
    combo = m.group(1)
    parts = [p.strip() for p in combo.split('+')]
    mods = parts[:-1] if len(parts) > 1 else []
    key = parts[-1]

    # Extract description from options table
    desc_m = LUA_DESC_RE.search(bind_src)
    comment = desc_m.group(1).strip() if desc_m else ''

    # Check for [hidden] or [ignore] markers
    if '[hidden]' in comment or '[ignore]' in comment:
        return

    if is_unbind:
        # Unbinds don't need descriptions — they only filter the cheatsheet
        current["unbinds"].append(Unbinding(mods, key, comment))
        return

    # Skip binds without descriptions (they're internal).
    if not comment:
        return

    # The Lua frontend registers its binds as internal `__lua` callbacks, so
    # `hyprctl binds` cannot expose the command that should run. Preserve the
    # literal dispatchers the frontend declares instead. The Search can then
    # invoke `global quickshell:…` or `exec …` through Hyprland.dispatch when
    # the selected keybind receives Enter.
    dispatch_match = LUA_DISPATCH_RE.search(bind_src)
    dispatcher = ''
    params = ''
    if dispatch_match:
        dispatcher = 'exec' if dispatch_match.group('dispatcher') == 'exec_cmd' else 'global'
        params = bytes(dispatch_match.group('params'), 'utf-8').decode('unicode_escape')

    current["keybinds"].append(KeyBinding(mods, key, dispatcher, params, comment))


# ─── Conf parser (original) ──────────────────────────────────────────────────

TITLE_REGEX = r"#+!"
COMMENT_BIND_PATTERN = r"^\s*#/#\s+(bind|unbind)\s*="
HIDE_COMMENT = "[hidden]"
MOD_SEPARATORS = ['+', ' ']


def read_content(path):
    expanded = os.path.expanduser(os.path.expandvars(path))
    if not os.access(expanded, os.R_OK):
        return "error"
    with open(expanded, "r") as file:
        return file.read()


def get_keybind_at_line(line_number, content_lines, line_start=0):
    line = content_lines[line_number]
    command, keys = line.split("=", 1)

    keys, *comment = keys.split("#", 1)

    if 'unbind' in command:
        comment = list(map(str.strip, comment))
        if comment:
            comment = comment[0]
            if comment.startswith("[ignore]"):
                return None
        mods, key, *_ = list(map(str.strip, keys.split(",", 3)))
        if mods:
            modstring = mods + MOD_SEPARATORS[0]
            mods = []
            p = 0
            for index, char in enumerate(modstring):
                if char in MOD_SEPARATORS:
                    if index - p > 1:
                        mods.append(modstring[p:index])
                    p = index + 1
        else:
            mods = []
        return Unbinding(mods, key, comment)

    mods, key, dispatcher, *params = list(map(str.strip, keys.split(",", 4)))
    params = "".join(map(str.strip, params))
    comment = list(map(str.strip, comment))

    if comment:
        comment = comment[0]
        if comment.startswith("[hidden]"):
            return None
    else:
        comment = autogenerate_comment(dispatcher, params)

    if mods:
        modstring = mods + MOD_SEPARATORS[0]
        mods = []
        p = 0
        for index, char in enumerate(modstring):
            if char in MOD_SEPARATORS:
                if index - p > 1:
                    mods.append(modstring[p:index])
                p = index + 1
    else:
        mods = []

    return KeyBinding(mods, key, dispatcher, params, comment)


def get_binds_recursive(current_content, scope, content_lines, reading_line):
    while reading_line < len(content_lines):
        line = content_lines[reading_line]
        heading_search_result = re.search(TITLE_REGEX, line)
        if heading_search_result is not None and heading_search_result.start() == 0:
            heading_scope = line.find('!')
            if heading_scope <= scope:
                reading_line -= 1
                return current_content, reading_line
            section_name = line[(heading_scope + 1):].strip()
            reading_line += 1
            child, reading_line = get_binds_recursive(Section([], [], [], section_name), heading_scope, content_lines, reading_line)
            current_content["children"].append(child)

        elif re.match(COMMENT_BIND_PATTERN, line):
            keybind = get_keybind_at_line(reading_line, content_lines, line_start=len("#/# "))
            if isinstance(keybind, KeyBinding):
                current_content["keybinds"].append(keybind)
            elif isinstance(keybind, Unbinding):
                current_content["unbinds"].append(keybind)
            reading_line += 1

        elif line == "" or not (line.lstrip().startswith("bind") or line.lstrip().startswith("unbind")):
            reading_line += 1

        else:
            keybind = get_keybind_at_line(reading_line, content_lines)
            if isinstance(keybind, KeyBinding):
                current_content["keybinds"].append(keybind)
            elif isinstance(keybind, Unbinding):
                current_content["unbinds"].append(keybind)
            reading_line += 1

    return current_content, reading_line


def parse_conf(path):
    content = read_content(path)
    if content == "error":
        return "error"
    content_lines = content.splitlines()
    result, _ = get_binds_recursive(Section([], [], [], ""), 0, content_lines, 0)
    return result


# ─── Flat parser: one entry per bind, with where it came from ────────────────
#
# The tree above answers "what should the cheatsheet print". This answers "what is in the file,
# on which line, with which options, and is it ours" - everything Settings -> Hyprland needs to
# list a shortcut and then rewrite it. They share a file and nothing else, so a change to one
# cannot break the other.
#
# Lua lexing is not repeated here: hyprgui.py already has a tokeniser that survives nested
# parentheses, long strings and comments, and it sits in this same folder.

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import hyprgui
except Exception:
    hyprgui = None

MOD_NAMES = {
    "SHIFT": "SHIFT", "CAPS": "CAPS", "CAPSLOCK": "CAPS",
    "CTRL": "CTRL", "CONTROL": "CTRL",
    "ALT": "ALT", "MOD1": "ALT", "MOD2": "MOD2", "MOD3": "MOD3",
    "SUPER": "SUPER", "WIN": "SUPER", "LOGO": "SUPER", "MOD4": "SUPER", "MOD5": "MOD5",
}
MOD_BITS = {"SHIFT": 1, "CAPS": 2, "CTRL": 4, "ALT": 8, "MOD2": 16, "MOD3": 32,
            "SUPER": 64, "MOD5": 128}
MOD_ORDER = ["CTRL", "SUPER", "ALT", "SHIFT", "CAPS", "MOD2", "MOD3", "MOD5"]


def split_combo(combo):
    """"SUPER + SHIFT + A" -> (["CTRL"-ordered mods], "A").

    A word that is not a modifier ends the modifier run: it is the key, plus signs and all.
    Guessing otherwise would quietly turn a malformed combo into a plausible wrong one.
    """
    parts = [p.strip() for p in str(combo).split('+')]
    parts = [p for p in parts if p != ""]
    if not parts:
        return [], ""
    mods = []
    for index, part in enumerate(parts[:-1]):
        name = MOD_NAMES.get(part.upper())
        if name is None:
            return sorted(set(mods), key=MOD_ORDER.index), "+".join(parts[index:])
        mods.append(name)
    return sorted(set(mods), key=MOD_ORDER.index), parts[-1]


def modmask_of(mods):
    mask = 0
    for mod in mods:
        mask |= MOD_BITS.get(mod, 0)
    return mask


def canonical_combo(mods, key):
    """What two binds must share to be on the same key. Case folded, because Hyprland matches
    key names case-insensitively and stock writes Page_down where custom writes Page_Down."""
    return "%s%s%s" % ("+".join(mods), "+" if mods else "", str(key).lower())


ALIAS_RE = re.compile(r'(?m)^[ \t]*local[ \t]+function[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*\(')
FUNCTION_END_RE = re.compile(r'(?m)^[ \t]*end[ \t]*$')


def find_bind_aliases(text):
    """Local helpers that wrap hl.bind / hl.unbind.

    custom/keybinds.lua defines `rebind(key, action, opts)` because hl.bind is additive - the
    stock bind has to be released first or both fire. Without this, every shortcut written that
    way would be invisible to the settings page.
    """
    kinds = {}
    bodies = {}
    for m in ALIAS_RE.finditer(text):
        name = m.group(1)
        tail = FUNCTION_END_RE.search(text, m.end())
        body = text[m.end():tail.start()] if tail else text[m.end():]
        bodies[name] = body
        if 'hl.bind' in body:
            kinds[name] = 'bind'
        elif 'hl.unbind' in body:
            kinds[name] = 'unbind'
    # A helper that binds *and* calls a helper that unbinds releases the stock bind first.
    releases = set()
    for name, body in bodies.items():
        if kinds.get(name) != 'bind':
            continue
        if 'hl.unbind' in body or any(
                other != name and kinds.get(other) == 'unbind' and re.search(
                    r'\b%s[ \t]*\(' % re.escape(other), body)
                for other in bodies):
            releases.add(name)
    return kinds, releases


SECTION_RE = re.compile(r'(?m)^[ \t]*--[ \t]*(#+)![ \t]*(.*?)[ \t]*$')


def section_index(text):
    """(offset, depth, name) for every --#! column and --##! section header, in file order."""
    return [(m.start(), len(m.group(1)), m.group(2).strip()) for m in SECTION_RE.finditer(text)]


def section_at(index, offset):
    """The innermost heading in force at an offset. A column with no name only resets."""
    column = section = ""
    for start, depth, name in index:
        if start > offset:
            break
        if depth <= 1:
            column, section = name, ""
        else:
            section = name
    if column and section:
        return "%s / %s" % (column, section)
    return section or column


SUBMAP_RE = re.compile(r'(?m)^[ \t]*hl\.define_submap[ \t]*\([ \t]*["\']([^"\']+)["\']')


def submap_spans(text):
    """(start, end, name) for every hl.define_submap block, so the binds inside it are known
    to only fire while that submap is active rather than looking like ordinary shortcuts."""
    out = []
    for m in SUBMAP_RE.finditer(text):
        open_paren = text.index('(', m.start())
        close = hyprgui._match_paren(text, open_paren)
        if close is None:
            continue
        out.append((m.start(), close, m.group(1)))
    return out


def submap_at(spans, offset):
    for start, end, name in spans:
        if start <= offset <= end:
            return name
    return ""


def _flat_calls(text, aliases):
    """Every bind-ish call in the file: hl.bind, hl.unbind, pcall(hl.unbind, ..) and aliases."""
    names = [r'hl\.bind', r'hl\.unbind'] + [re.escape(name) for name in sorted(aliases)]
    pattern = re.compile(r'(?m)^[ \t]*(?:(pcall)[ \t]*\([ \t]*(hl\.unbind)[ \t]*,|(' +
                         '|'.join(names) + r')[ \t]*\()')
    out = []
    for m in pattern.finditer(text):
        if m.group(1):
            name = 'hl.unbind'
            open_paren = text.index('(', m.start())
        else:
            name = m.group(3)
            open_paren = m.end() - 1
        close = hyprgui._match_paren(text, open_paren)
        if close is None:
            continue
        args = text[open_paren + 1:close]
        if m.group(1):
            args = args.split(',', 1)[1] if ',' in args else args
        out.append((name, args, m.start(), close))
    return out


HIDDEN_RE = re.compile(r'\[(hidden|ignore)\]')


def parse_lua_flat(path, label):
    """One entry per bind or unbind statement in a Lua keybind file."""
    expanded = os.path.expanduser(os.path.expandvars(path))
    if hyprgui is None or not os.access(expanded, os.R_OK):
        return {"file": label, "path": expanded, "binds": [], "hasRegion": False,
                "readable": False}
    with open(expanded, 'r', encoding='utf-8', errors='surrogateescape') as handle:
        text = handle.read()

    begin, end, _ = hyprgui.find_region(text.splitlines(keepends=True))
    region = None
    if begin is not None:
        lines = text.splitlines(keepends=True)
        region = (begin + 1, end)          # 1-based line numbers, end exclusive-ish

    alias_kinds, alias_releases = find_bind_aliases(text)
    sections = section_index(text)
    submaps = submap_spans(text)

    binds = []
    for name, args_source, start, close in _flat_calls(text, alias_kinds):
        if name == 'hl.bind':
            kind, alias, releases = 'bind', None, False
        elif name == 'hl.unbind':
            kind, alias, releases = 'unbind', None, False
        else:
            kind = alias_kinds.get(name, 'bind')
            alias = name
            releases = name in alias_releases
        try:
            args = hyprgui.parse_args(args_source)
        except (ValueError, IndexError):
            continue
        if not args:
            continue

        line = text.count('\n', 0, start) + 1
        eol = text.find('\n', close)
        trailing = text[close:eol if eol >= 0 else len(text)]
        first = args[0]
        entry = {
            "kind": kind,
            "line": line,
            "file": label,
            "section": section_at(sections, start),
            "submap": submap_at(submaps, start),
            "alias": alias,
            "releases": releases,
            "managed": bool(region and region[0] <= line < region[1]),
            "hidden": bool(HIDDEN_RE.search(trailing)),
        }
        if isinstance(first, str):
            mods, key = split_combo(first)
            entry.update({"combo": first, "mods": mods, "key": key,
                          "modmask": modmask_of(mods),
                          "canonical": canonical_combo(mods, key), "resolved": True})
        else:
            source = first.get("__raw") if isinstance(first, dict) else repr(first)
            entry.update({"combo": source, "mods": [], "key": "", "modmask": 0,
                          "canonical": "", "resolved": False})
        if kind == 'bind':
            action = args[1] if len(args) > 1 else None
            entry["action"] = action.get("__raw") if isinstance(action, dict) and "__raw" in action \
                else (action if isinstance(action, str) else None)
            # A `function() ... end` action contains commas that the argument splitter reads as
            # separators, so the option table is not reliably the third argument. Take the last
            # argument that is a plain table, and treat the rest of the call as part of the action.
            opts = {}
            for candidate in reversed(args[2:]):
                if isinstance(candidate, dict) and "__raw" not in candidate:
                    opts = {k: v for k, v in candidate.items() if k != "__array"}
                    break
            entry["opts"] = opts
            entry["complex"] = bool(entry["action"] and
                                    str(entry["action"]).lstrip().startswith("function"))
            description = opts.get("description")
            entry["description"] = description if isinstance(description, str) else ""
            if entry["hidden"]:
                entry["description"] = ""
        binds.append(entry)

    return {"file": label, "path": expanded, "binds": binds, "hasRegion": begin is not None,
            "readable": True, "aliases": alias_kinds}


def flat_label(path):
    """Both keybind files are called keybinds.lua, so the folder is the distinguishing half."""
    parts = os.path.normpath(os.path.expanduser(os.path.expandvars(path))).split(os.sep)
    return os.sep.join(parts[-2:]) if len(parts) >= 2 else parts[-1]


def parse_flat(paths):
    files = [parse_lua_flat(path, flat_label(path)) for path in paths]
    return {"files": files,
            "binds": [bind for entry in files for bind in entry["binds"]]}


# ─── hyprctl fallback ───────────────────────────────────────────────────────

def parse_hyprctl():
    try:
        result = subprocess.run(['hyprctl', 'binds', '-j'],
                                capture_output=True, text=True, timeout=10)
        if result.returncode != 0:
            return "error"
        binds = json.loads(result.stdout)
    except Exception:
        return "error"

    root = Section([], [], [], "")
    section_map = {}

    for b in binds:
        desc = b.get('description', '').strip()
        if not desc:
            continue
        if desc.startswith('[hidden]'):
            continue

        mods = decode_modmask(b.get('modmask', 0))
        key = b.get('key', '')

        section_name = "Misc"
        if ':' in desc:
            prefix = desc.split(':')[0]
            if prefix:
                section_name = prefix

        if section_name not in section_map:
            sec = Section([], [], [], section_name)
            root["children"].append(sec)
            section_map[section_name] = sec

        section_map[section_name]["keybinds"].append(
            KeyBinding(mods, key, b.get('dispatcher', ''), b.get('arg', ''), desc)
        )

    return root


# ─── Main ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    paths = args.path or []

    if args.flat:
        print(json.dumps(parse_flat(paths)))
        sys.exit(0)

    # The tree output takes one file, which is how every existing caller uses it.
    path = paths[0] if paths else None

    result = None
    if path:
        expanded = os.path.expanduser(os.path.expandvars(path))
        if not os.access(expanded, os.R_OK):
            # File doesn't exist or isn't readable - return empty
            result = Section([], [], [], "")
        else:
            try:
                if path.lower().endswith('.lua'):
                    result = parse_lua_binds(path)
                else:
                    result = parse_conf(path)
            except Exception:
                result = "error"

    if result is None or result == "error":
        result = parse_hyprctl()

    if result == "error":
        result = Section([], [], [], "")

    print(json.dumps(result))
